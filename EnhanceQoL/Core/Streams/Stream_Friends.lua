-- luacheck: globals EnhanceQoL C_FriendList
local addonName, addon = ...

local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.friends = addon.db.datapanel.friends or {}
	db = addon.db.datapanel.friends
	db.fontSize = db.fontSize or 13
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
	frame:SetTitle(GAMEMENU_OPTIONS)
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
	fontSize:SetLabel("Font size")
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(fontSize)

	frame.frame:Show()
end

local GetNumFriends = C_FriendList.GetNumFriends
local GetFriendInfoByIndex = C_FriendList.GetFriendInfoByIndex

local myGuid = UnitGUID("player")

-- Build reverse lookup for class tokens from localized names for coloring
local CLASS_TOKEN_BY_LOCALIZED = {}
if LOCALIZED_CLASS_NAMES_MALE then
    for token, loc in pairs(LOCALIZED_CLASS_NAMES_MALE) do CLASS_TOKEN_BY_LOCALIZED[loc] = token end
end
if LOCALIZED_CLASS_NAMES_FEMALE then
    for token, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do CLASS_TOKEN_BY_LOCALIZED[loc] = token end
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
    local base, realm = name:match("^([^%-]+)%-(.+)$")
    if base then
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
    if rKey == "" or rKey == myRealmKey then
        return base
    end
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
    local nameLocalized = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token])
        or (LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[token])
        or classTokenOrLocalized
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
    wipeTooltipSections()

    local seen = {} -- key -> true (dedupe across sources)
    local totalUnique = 0

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
                    table.insert(tooltipData.bnet, {
                        name = displayName(ga.characterName, ga.realmName),
                        level = ga.characterLevel,
                        class = classDisp,
                        color = color,
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
                })
            end
        end
    end

    -- 3) Guild members
    local gMember = GetNumGuildMembers and GetNumGuildMembers()
    if gMember and gMember > 0 then
        for i = 1, gMember do
            local name, _, _, level, _, _, _, _, isOnline, _, classToken, _, _, _, _, _, guid = GetGuildRosterInfo(i)
            if isOnline and guid ~= myGuid and name and level then
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
    local function byName(a, b)
        return (a.name or ""):lower() < (b.name or ""):lower()
    end
    table.sort(tooltipData.bnet, byName)
    table.sort(tooltipData.friends, byName)
    table.sort(tooltipData.guild, byName)

    stream.snapshot.fontSize = db and db.fontSize or 13
    stream.snapshot.text = totalUnique .. " " .. FRIENDS
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
		FRIENDLIST_UPDATE = function(stream) addon.DataHub:RequestUpdate(stream) end,
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
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
                if v.color then
                    tip:AddDoubleLine(v.name, right, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, v.color.r, v.color.g, v.color.b)
                else
                    tip:AddDoubleLine(v.name, right)
                end
            end
            tip:AddLine(" ")
        end

        addSection(BATTLENET_OPTIONS_LABEL or "Battle.net", tooltipData.bnet, CreateColor(0.3, 0.7, 1.0))
        addSection(FRIENDS, tooltipData.friends, CreateColor(0.8, 0.8, 1.0))
        addSection(GUILD, tooltipData.guild, CreateColor(0.25, 1.0, 0.4))

        tip:AddLine(L["Right-Click for options"])
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

return provider
