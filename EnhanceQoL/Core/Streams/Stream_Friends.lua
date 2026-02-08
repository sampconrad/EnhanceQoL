-- luacheck: globals EnhanceQoL C_FriendList
local addonName, addon = ...

local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream
-- Forward declarations used across functions
local listWindow -- AceGUI window
local populateListWindow -- function to (re)build the list window
local function getOptionsHint()
	if addon.DataPanel and addon.DataPanel.GetOptionsHintText then
		local text = addon.DataPanel.GetOptionsHintText()
		if text ~= nil then return text end
		return nil
	end
	return L["Right-Click for options"]
end

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.friends = addon.db.datapanel.friends or {}
	db = addon.db.datapanel.friends
	db.fontSize = db.fontSize or 13
	if db.splitDisplay == nil then db.splitDisplay = false end
	if db.splitDisplayInline == nil then db.splitDisplayInline = false end
end

local function RestorePosition(frame)
	if db.point and db.x and db.y then
		frame:ClearAllPoints()
		frame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
	end
end

local aceWindow
local function createAceWindow()
	if aceWindow then
		aceWindow:Show()
		return
	end
	ensureDB()
	local frame = AceGUI:Create("Window")
	aceWindow = frame.frame
	frame:SetTitle((addon.DataPanel and addon.DataPanel.GetStreamOptionsTitle and addon.DataPanel.GetStreamOptionsTitle(stream and stream.meta and stream.meta.title)) or GAMEMENU_OPTIONS)
	frame:SetWidth(300)
	frame:SetHeight(200)
	frame:SetLayout("List")

	frame.frame:SetScript("OnShow", function(self) RestorePosition(self) end)
	frame.frame:SetScript("OnHide", function(self)
		local point, _, _, xOfs, yOfs = self:GetPoint()
		db.point = point
		db.x = xOfs
		db.y = yOfs
	end)

	local fontSize = AceGUI:Create("Slider")
	fontSize:SetLabel(FONT_SIZE)
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(fontSize)

	local splitDisplayInline
	local splitDisplay = AceGUI:Create("CheckBox")
	splitDisplay:SetLabel(L["Friends/Guild display"] or "Show friends + guild")
	splitDisplay:SetValue(db.splitDisplay == true)
	splitDisplay:SetCallback("OnValueChanged", function(_, _, val)
		db.splitDisplay = val and true or false
		if splitDisplayInline and splitDisplayInline.SetDisabled then
			splitDisplayInline:SetDisabled(not db.splitDisplay)
		end
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(splitDisplay)

	splitDisplayInline = AceGUI:Create("CheckBox")
	splitDisplayInline:SetLabel(L["Friends/Guild display single line"] or "Single-line layout")
	splitDisplayInline:SetValue(db.splitDisplayInline == true)
	splitDisplayInline:SetDisabled(not db.splitDisplay)
	splitDisplayInline:SetCallback("OnValueChanged", function(_, _, val)
		db.splitDisplayInline = val and true or false
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(splitDisplayInline)

	frame.frame:Show()
end

local GetNumFriends = C_FriendList.GetNumFriends
local GetFriendInfoByIndex = C_FriendList.GetFriendInfoByIndex

local myGuid = UnitGUID("player")

-- Build reverse lookup for class tokens from localized names for coloring
local CLASS_TOKEN_BY_LOCALIZED = {}
if LOCALIZED_CLASS_NAMES_MALE then
	for token, loc in pairs(LOCALIZED_CLASS_NAMES_MALE) do
		CLASS_TOKEN_BY_LOCALIZED[loc] = token
	end
end
if LOCALIZED_CLASS_NAMES_FEMALE then
	for token, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
		CLASS_TOKEN_BY_LOCALIZED[loc] = token
	end
end

local function normalizeRealmName(realm)
	if not realm or realm == "" then return "" end
	-- remove spaces and apostrophes for stable keys, lowercase
	realm = realm:gsub("%s+", ""):gsub("'", "")
	return realm:lower()
end

local myRealm = GetRealmName and GetRealmName() or nil
local myRealmKey = normalizeRealmName(myRealm)

local function splitNameRealm(name)
	if not name then return nil, nil end
	-- Names coming from various APIs can sometimes end up with the realm
	-- appended multiple times (e.g., "Name-Antonidas-Antonidas-...").
	-- We always want:
	--   base  = the character name (before the first hyphen)
	--   realm = the final segment (after the last hyphen), if present
	local base, remainder = name:match("^([^%-]+)%-(.+)$")
	if base then
		-- Take only the last segment of the remainder as the realm
		local realm = remainder:match("([^%-]+)$")
		return base, realm
	end
	return name, nil
end

local function makeKey(name, realm)
	local base, r = splitNameRealm(name)
	base = base or name or ""
	r = r or realm or myRealm
	return (base:lower() .. "-" .. normalizeRealmName(r or ""))
end

local function displayName(name, realm)
	local base, r = splitNameRealm(name)
	base = base or name or ""
	r = r or realm
	local rKey = normalizeRealmName(r or "")
	if rKey == "" or rKey == myRealmKey then return base end
	-- Show cross-realm without spaces in realm to match WoW name formatting
	local realmDisplay = (r or ""):gsub("%s+", "")
	return base .. "-" .. realmDisplay
end

local function classDisplayAndColor(classTokenOrLocalized)
	if not classTokenOrLocalized or classTokenOrLocalized == "" then return nil, nil end
	local token = classTokenOrLocalized
	if token:upper() == token then
		-- Looks like a class file token (e.g., "MAGE")
	else
		-- Probably localized name; try reverse-lookup
		token = CLASS_TOKEN_BY_LOCALIZED[classTokenOrLocalized] or token
	end
	local nameLocalized = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or (LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[token]) or classTokenOrLocalized
	local colorTbl = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)
	local color = colorTbl and colorTbl[token]
	return nameLocalized, color
end

-- Structured tooltip data: sections with lists
local tooltipData = { bnet = {}, friends = {}, guild = {} }

local function wipeTooltipSections()
	wipe(tooltipData.bnet)
	wipe(tooltipData.friends)
	wipe(tooltipData.guild)
end

local function getFriends(stream)
	ensureDB()
	wipeTooltipSections()

	local seen = {} -- key -> true (dedupe across sources)
	local totalUnique = 0
	local friendsCount = 0
	local guildOnlineCount = 0

	-- 1) Battle.net friends (prefer these when deduping)
	local numBNetTotal, _ = BNGetNumFriends()
	if numBNetTotal and numBNetTotal > 0 then
		for i = 1, numBNetTotal do
			local info = C_BattleNet.GetFriendAccountInfo(i)
			local ga = info and info.gameAccountInfo
			if ga and ga.isOnline and ga.clientProgram == BNET_CLIENT_WOW and ga.characterName and ga.characterLevel then
				local key = makeKey(ga.characterName, ga.realmName)
				if not seen[key] then
					seen[key] = true
					totalUnique = totalUnique + 1
					local classNameLocalized = ga.className
					local classDisp, color = classDisplayAndColor(classNameLocalized)
					-- BNet presence / status details
					local bnName = info and (info.accountName or (info.battleTag and info.battleTag:match("^[^#]+"))) or nil
					-- Prefer game-specific AFK/DND, fall back to account level
					local isAFK = (ga.isGameAFK == true) or (info and info.isAFK == true)
					local isDND = (ga.isGameBusy == true) or (info and info.isDND == true)
					local status
					if isDND then
						status = "DND"
					elseif isAFK then
						status = "AFK"
					end
					table.insert(tooltipData.bnet, {
						name = displayName(ga.characterName, ga.realmName),
						level = ga.characterLevel,
						class = classDisp,
						color = color,
						bnName = bnName,
						status = status,
						client = ga.clientProgram,
						presence = ga.richPresence or ga.gameText,
					})
				end
			end
		end
	end

	-- 2) Regular WoW friends
	local numWoWFriends = C_FriendList.GetNumFriends()
	for i = 1, numWoWFriends do
		local friendInfo = C_FriendList.GetFriendInfoByIndex(i)
		if friendInfo and friendInfo.connected then
			local key = makeKey(friendInfo.name)
			if not seen[key] then
				seen[key] = true
				totalUnique = totalUnique + 1
				local classDisp, color = classDisplayAndColor(friendInfo.className or friendInfo.classNameFile or "")
				local nameForDisp = displayName(friendInfo.name)
				table.insert(tooltipData.friends, {
					name = nameForDisp,
					level = friendInfo.level,
					class = classDisp,
					color = color,
					status = (friendInfo.dnd and "DND") or (friendInfo.afk and "AFK") or nil,
					presence = friendInfo.area,
					note = friendInfo.notes,
				})
			end
		end
	end
	friendsCount = totalUnique

	-- 3) Guild members
	local gMember = GetNumGuildMembers and GetNumGuildMembers()
	if gMember and gMember > 0 then
		for i = 1, gMember do
			local name, _, _, level, _, _, _, _, isOnline, _, classToken, _, _, _, _, _, guid = GetGuildRosterInfo(i)
			if isOnline and guid ~= myGuid and name and level then
				guildOnlineCount = guildOnlineCount + 1
				local key = makeKey(name)
				if not seen[key] then
					seen[key] = true
					totalUnique = totalUnique + 1
					local classDisp, color = classDisplayAndColor(classToken)
					table.insert(tooltipData.guild, {
						name = displayName(name),
						level = level,
						class = classDisp,
						color = color,
					})
				end
			end
		end
	end

	-- Sort each section by name
	local function byName(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end
	table.sort(tooltipData.bnet, byName)
	table.sort(tooltipData.friends, byName)
	table.sort(tooltipData.guild, byName)

	stream.snapshot.fontSize = db and db.fontSize or 13
	if db and db.splitDisplay then
		if db.splitDisplayInline then
			stream.snapshot.text = string.format("%s: %d  %s: %d", GUILD, guildOnlineCount, FRIENDS, friendsCount)
		else
			stream.snapshot.text = string.format("%s: %d\n%s: %d", GUILD, guildOnlineCount, FRIENDS, friendsCount)
		end
	else
		stream.snapshot.text = totalUnique .. " " .. FRIENDS
	end

	-- If our extended window is open, refresh its content
	if listWindow and listWindow.frame and listWindow.frame:IsShown() then populateListWindow() end
end

local function ensureListWindow()
	if listWindow and listWindow.frame and listWindow.frame:IsShown() then return listWindow end
	local frame = AceGUI:Create("Window")
	listWindow = frame
	frame:SetTitle(FRIENDS)
	frame:SetWidth(720)
	frame:SetHeight(520)
	frame:SetLayout("Fill")

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("Flow")
	frame:AddChild(scroll)

	frame._scroll = scroll
	return frame
end

local function colorizedName(name, color)
	if not color then return name end
	local r, g, b = color.r or 1, color.g or 1, color.b or 1
	return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, name)
end

local function addHeader(scroll, title)
	local header = AceGUI:Create("Label")
	header:SetFullWidth(true)
	header:SetText("|cffffd100" .. title .. "|r")
	header:SetFont(addon.variables and addon.variables.defaultFont or GameFontNormal:GetFont(), 14, "OUTLINE")
	scroll:AddChild(header)
end

local function addRow(scroll, cols)
	-- cols: array of { text=..., width=relativeWidth }
	local row = AceGUI:Create("SimpleGroup")
	row:SetFullWidth(true)
	row:SetLayout("Flow")
	for i, col in ipairs(cols) do
		local lbl = AceGUI:Create("Label")
		lbl:SetRelativeWidth(col.width or (1 / #cols))
		lbl:SetText(col.text or "")
		scroll:AddChild(lbl)
	end
end

function populateListWindow()
	if not (listWindow and listWindow._scroll) then return end
	local scroll = listWindow._scroll
	scroll:ReleaseChildren()

	-- Header row
	local headerRow = AceGUI:Create("SimpleGroup")
	headerRow:SetFullWidth(true)
	headerRow:SetLayout("Flow")
	local function headerLabel(text, width)
		local lbl = AceGUI:Create("Label")
		lbl:SetText("|cffcccccc" .. text .. "|r")
		lbl:SetRelativeWidth(width)
		headerRow:AddChild(lbl)
	end
	headerLabel(NAME, 0.30)
	headerLabel("Client", 0.12)
	headerLabel((_G.PRESENCE or L["Presence"] or "Presence"), 0.38)
	headerLabel((_G.NOTES_LABEL or "Note"), 0.20)
	scroll:AddChild(headerRow)

	-- Battle.net section
	addHeader(scroll, BATTLENET_OPTIONS_LABEL or "Battle.net")
	for _, v in ipairs(tooltipData.bnet) do
		local bnSuffix = v.bnName and (" |cff80bfff(" .. v.bnName .. ")|r") or ""
		local status = v.status == "DND" and " |cffff5050[DND]|r" or (v.status == "AFK" and " |cffffb84d[AFK]|r" or "")
		local nameText = colorizedName(v.name, v.color) .. bnSuffix .. status
		addRow(scroll, {
			{ text = nameText, width = 0.30 },
			{ text = v.client or "WoW", width = 0.12 },
			{ text = v.presence or "", width = 0.38 },
			{ text = v.note or "", width = 0.20 },
		})
	end

	-- Regular WoW friends (excluding those already shown via BNet)
	addHeader(scroll, FRIENDS)
	for _, v in ipairs(tooltipData.friends) do
		local status = v.status == "DND" and " |cffff5050[DND]|r" or (v.status == "AFK" and " |cffffb84d[AFK]|r" or "")
		local nameText = colorizedName(v.name, v.color) .. status
		local presence = v.presence or ((v.class and v.level) and (v.class .. " (" .. tostring(v.level) .. ")") or "")
		addRow(scroll, {
			{ text = nameText, width = 0.30 },
			{ text = "WoW", width = 0.12 },
			{ text = presence, width = 0.38 },
			{ text = v.note or "", width = 0.20 },
		})
	end
end

local function toggleListWindow()
	local frame = ensureListWindow()
	if frame.frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
		populateListWindow()
	end
end

local provider = {
	id = "friends",
	version = 1,
	title = FRIENDS,
	update = getFriends,
	events = {
		PLAYER_LOGIN = function(stream) addon.DataHub:RequestUpdate(stream) end,
		BN_FRIEND_ACCOUNT_ONLINE = function(stream) addon.DataHub:RequestUpdate(stream) end,
		BN_FRIEND_ACCOUNT_OFFLINE = function(stream) addon.DataHub:RequestUpdate(stream) end,
		BN_FRIEND_INFO_CHANGED = function(stream) addon.DataHub:RequestUpdate(stream) end,
		FRIENDLIST_UPDATE = function(stream) addon.DataHub:RequestUpdate(stream) end,
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then
			createAceWindow()
		else
			toggleListWindow()
		end
	end,
	OnMouseEnter = function(btn)
		local tip = GameTooltip
		tip:ClearLines()
		tip:SetOwner(btn, "ANCHOR_TOPLEFT")

		local function addSection(title, items, color)
			if #items == 0 then return end
			color = color or HIGHLIGHT_FONT_COLOR
			tip:AddLine(string.format("%s (%d)", title, #items), color.r, color.g, color.b)
			for _, v in ipairs(items) do
				local right = v.level or ""
				if v.class and v.level then right = string.format("%s (%s)", v.class, v.level) end
				-- Append BN name and status for BNet entries; presence for others
				local left = v.name
				if v.bnName then left = string.format("%s |cff80bfff(%s)|r", left, v.bnName) end
				if v.status == "DND" then
					left = left .. " |cffff5050[DND]|r"
				elseif v.status == "AFK" then
					left = left .. " |cffffb84d[AFK]|r"
				end
				if (not v.bnName) and v.presence then right = v.presence end
				if v.color then
					tip:AddDoubleLine(left, right, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, v.color.r, v.color.g, v.color.b)
				else
					tip:AddDoubleLine(left, right)
				end
			end
			tip:AddLine(" ")
		end

		addSection(BATTLENET_OPTIONS_LABEL or "Battle.net", tooltipData.bnet, CreateColor(0.3, 0.7, 1.0))
		addSection(FRIENDS, tooltipData.friends, CreateColor(0.8, 0.8, 1.0))
		addSection(GUILD, tooltipData.guild, CreateColor(0.25, 1.0, 0.4))

		local hint = getOptionsHint()
		if hint then tip:AddLine(hint) end
		tip:Show()

		-- Keep first line styling consistent
		local name = tip:GetName()
		local left1 = _G[name .. "TextLeft1"]
		local right1 = _G[name .. "TextRight1"]
		local r, g, b = NORMAL_FONT_COLOR:GetRGB()
		if left1 then
			left1:SetFontObject(GameTooltipText)
			left1:SetTextColor(r, g, b)
		end
		if right1 then
			right1:SetFontObject(GameTooltipText)
			right1:SetTextColor(r, g, b)
		end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

-- If the list window is open during updates, refresh its contents
hooksecurefunc(addon.DataHub, "RequestUpdate", function(_)
	if listWindow and listWindow.frame and listWindow.frame:IsShown() then populateListWindow() end
end)

return provider
