local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end
local L = LibStub("AceLocale-3.0"):GetLocale(parentAddonName)
_G["BINDING_NAME_EQOL_TOGGLE_CHATHISTORY"] = L["CH_BINDING_TOGGLE"]

addon.ChatIM = addon.ChatIM or {}
local ChatIM = addon.ChatIM

ChatIM.ChannelHistory = ChatIM.ChannelHistory or {}
local ChannelHistory = ChatIM.ChannelHistory

ChannelHistory.version = 1
ChannelHistory.maxLines = ChannelHistory.maxLines or 500
ChannelHistory.uiMaxLines = ChannelHistory.uiMaxLines or 1000
ChannelHistory.enabled = ChannelHistory.enabled or false
ChannelHistory.frame = ChannelHistory.frame or CreateFrame("Frame")
ChannelHistory.events = ChannelHistory.events or nil
ChannelHistory.debugFrame = ChannelHistory.debugFrame or nil
ChannelHistory.EVENT_FILTER_KEY = ChannelHistory.EVENT_FILTER_KEY
	or {
		CHAT_MSG_SAY = "SAY",
		CHAT_MSG_YELL = "YELL",
		CHAT_MSG_WHISPER = "WHISPER",
		CHAT_MSG_WHISPER_INFORM = "WHISPER",
		CHAT_MSG_BN_WHISPER = "BN_WHISPER",
		CHAT_MSG_BN_WHISPER_INFORM = "BN_WHISPER",
		CHAT_MSG_PARTY = "PARTY",
		CHAT_MSG_INSTANCE_CHAT = "INSTANCE",
		CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE",
		CHAT_MSG_RAID = "RAID",
		CHAT_MSG_RAID_LEADER = "RAID",
		CHAT_MSG_GUILD = "GUILD",
		CHAT_MSG_OFFICER = "OFFICER",
		CHAT_MSG_CHANNEL = "GENERAL",
		CHAT_MSG_COMMUNITIES_CHANNEL = "GENERAL",
		CHAT_MSG_LOOT = "LOOT",
		CHAT_MSG_MONEY = "MONEY",
		CHAT_MSG_CURRENCY = "CURRENCY",
		CHAT_MSG_ACHIEVEMENT = "ACHIEVEMENT",
		CHAT_MSG_GUILD_ACHIEVEMENT = "GUILD",
		CHAT_MSG_SYSTEM = "SYSTEM",
		CHAT_MSG_OPENING = "OPENING",
		CHAT_MSG_MONSTER_EMOTE = "MONSTER",
		CHAT_MSG_MONSTER_PARTY = "MONSTER",
		CHAT_MSG_MONSTER_SAY = "MONSTER",
		CHAT_MSG_MONSTER_WHISPER = "MONSTER",
		CHAT_MSG_MONSTER_YELL = "MONSTER",
		CHAT_MSG_RAID_BOSS_EMOTE = "MONSTER",
		CHAT_MSG_RAID_BOSS_WHISPER = "MONSTER",
	}
ChannelHistory.loggedIn = ChannelHistory.loggedIn or (IsLoggedIn and IsLoggedIn()) or false
ChannelHistory.defaultFilters = {
	SAY = true,
	GUILD = true,
	PARTY = true,
	INSTANCE = true,
	OFFICER = true,
	RAID = true,
	YELL = true,
	WHISPER = true,
	BN_WHISPER = true,
	GENERAL = true,
	MONEY = true,
	CURRENCY = true,
	ACHIEVEMENT = true,
	SYSTEM = true,
	OPENING = true,
	MONSTER = true,
}
ChannelHistory.ui = ChannelHistory.ui or {}
ChannelHistory.runtime = ChannelHistory.runtime or { guidClassCache = {}, guidClassCacheSize = 0, refreshPending = false, formattedCache = nil, bnetTagCache = {} }
local GUID_CACHE_LIMIT = 2000
local splitSender, getSenderClass, toColorCode, getChatColor, formatLine, deriveScope, resolveClassFromGUID, normalizeChannelBucket, realmFromCharKey
local MU = MenuUtil
local function isPlayerGUID(guid) return guid and guid:sub(1, 7) == "Player-" end
local function isTableEmpty(t) return type(t) ~= "table" or next(t) == nil end

local function getClassStyle(classFile)
	if not classFile then return nil end
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	return color
end

local IGNORED_EVENTS = {
	CHAT_MSG_ADDON = true,
	CHAT_MSG_BN_INLINE_TOAST_ALERT = true,
	CHAT_MSG_BN_INLINE_TOAST_BROADCAST = true,
	CHAT_MSG_BN_INLINE_TOAST_BROADCAST_INFORM = true,
	CHAT_MSG_BN_INLINE_TOAST_CONVERSATION = true,
}

local ADDITIONAL_EVENTS = {}

local function now() return (GetServerTime and GetServerTime()) or time() end

local function sanitizeRealm(realm)
	if not realm or realm == "" then realm = GetRealmName() or "Unknown" end
	realm = realm:gsub("%s+", "")
	return realm
end

local cacheBNetTag

local function resolveBNetTag(accountID)
	if not accountID then return nil end
	accountID = tonumber(accountID) or accountID
	local cache = ChannelHistory.runtime and ChannelHistory.runtime.bnetTagCache
	if cache and cache[accountID] then return cache[accountID] end
	local info = C_BattleNet and C_BattleNet.GetAccountInfoByID and C_BattleNet.GetAccountInfoByID(accountID)
	local tag = info and info.battleTag
	if tag then cacheBNetTag(accountID, tag) end
	return tag
end
local function ensureCopyPopup()
	if not StaticPopupDialogs then return end
	if StaticPopupDialogs["EQOL_URL_COPY"] then return end
	StaticPopupDialogs["EQOL_URL_COPY"] = {
		text = CALENDAR_COPY_EVENT,
		button1 = CLOSE,
		hasEditBox = true,
		editBoxWidth = 320,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
		OnShow = function(self, data)
			local editBox = self.editBox or (self.GetEditBox and self:GetEditBox())
			if editBox then
				editBox:SetText(data or "")
				editBox:SetFocus()
				editBox:HighlightText()
			end
		end,
	}
end

local assetPath = "Interface\\AddOns\\EnhanceQoL\\Assets\\"

local function showCopyDialog(text)
	ensureCopyPopup()
	if StaticPopup_Show then StaticPopup_Show("EQOL_URL_COPY", nil, nil, text or "") end
end

local function sanitizeCopyText(text)
	if not text then return "" end
	text = text:gsub("\r", "")
	text = text:gsub("[\001-\008\011\012\014-\031]", "")
	return text
end

local BN_CACHE_LIMIT = 2000

cacheBNetTag = function(accountID, tag)
	ChannelHistory.runtime = ChannelHistory.runtime or {}
	local rt = ChannelHistory.runtime
	rt.bnetTagCache = rt.bnetTagCache or {}
	rt.bnetTagCacheSize = rt.bnetTagCacheSize or 0

	if rt.bnetTagCache[accountID] == nil then rt.bnetTagCacheSize = rt.bnetTagCacheSize + 1 end

	rt.bnetTagCache[accountID] = tag

	if rt.bnetTagCacheSize > BN_CACHE_LIMIT then
		table.wipe(rt.bnetTagCache)
		rt.bnetTagCacheSize = 0
	end
end

local function buildFilterOptions()
	return {
		{ key = "SAY", label = string.format("|T2056011:14:14:0:0|t %s", SAY) },
		{ key = "YELL", label = string.format("|T892447:14:14:0:0|t %s", YELL) },
		{ key = "WHISPER", label = string.format("|T133458:14:14:0:0|t %s", WHISPER) },
		{ key = "BN_WHISPER", label = string.format("|TInterface\\FriendsFrame\\UI-Toast-ChatInviteIcon:14:14:0:0|t %s", BN_WHISPER) },
		{ key = "PARTY", label = string.format("|T134149:14:14:0:0|t %s", PARTY) },
		{ key = "INSTANCE", label = string.format("|TInterface\\AddOns\\EnhanceQoL\\Icons\\Dungeon.tga:14:14:0:0|t %s", INSTANCE) },
		{ key = "RAID", label = string.format("|TInterface\\AddOns\\EnhanceQoL\\Icons\\Raid.tga:14:14:0:0|t %s", RAID) },
		{ key = "GUILD", label = string.format("|T514261:14:14:0:0|t %s", GUILD) },
		{ key = "OFFICER", label = string.format("|T133071:14:14:0:0|t %s", OFFICER) },
		{ key = "GENERAL", label = GENERAL },
		{ key = "LOOT", label = string.format("|T133639:14:14:0:0|t %s", LOOT) },
		{ key = "MONEY", label = string.format("|T133785:14:14:0:0|t %s", MONEY) },
		{ key = "CURRENCY", label = string.format("|TInterface\\Icons\\inv_misc_coin_01:14:14:0:0|t %s", CURRENCY) },
		{ key = "ACHIEVEMENT", label = string.format("|T236507:14:14:0:0|t %s", ACHIEVEMENTS) },
		{ key = "SYSTEM", label = SYSTEM_MESSAGES or SYSTEM },
		{ key = "OPENING", label = OPENING },
		{ key = "MONSTER", label = EXAMPLE_TARGET_MONSTER or "Monster" },
	}
end

function ChannelHistory:InvalidateLootQualityCache()
	self.runtime = self.runtime or {}
	self.runtime.lootQualitySelection = nil
	self.runtime.lootQualityHasSelection = nil
end

local function ensureLootQualitySelection()
	ChannelHistory.runtime = ChannelHistory.runtime or {}
	if ChannelHistory.runtime.lootQualitySelection then return ChannelHistory.runtime.lootQualitySelection, ChannelHistory.runtime.lootQualityHasSelection end

	local db = addon.db or {}
	local selected = db.chatChannelHistoryLootQualities
	local function defaultSelection()
		local map = {}
		local maxQ = (Enum and Enum.ItemQuality and Enum.ItemQuality.WoWToken) or 8
		for i = 0, maxQ do
			map[i] = true
		end
		return map
	end

	local hasSelection = false
	if selected and type(selected) == "table" then
		for _, v in pairs(selected) do
			if v then
				hasSelection = true
				break
			end
		end
	end
	if not hasSelection then
		selected = defaultSelection()
		db.chatChannelHistoryLootQualities = selected
		hasSelection = true
	end

	ChannelHistory.runtime.lootQualitySelection = selected
	ChannelHistory.runtime.lootQualityHasSelection = hasSelection
	return selected, hasSelection
end

local function shouldFilterLootByQuality(msg, event)
	if not msg or msg == "" then return false end
	if event ~= "CHAT_MSG_LOOT" then return false end

	local selected, hasSelection = ensureLootQualitySelection()
	if not hasSelection then return false end -- no selection means allow all

	local function matchQuality(quality)
		if not quality then return false end
		return selected[quality] or selected[tostring(quality)] or false
	end

	-- Colorblind format embeds quality as |cnIQ<quality>:...
	local embeddedQuality = msg:match("|cnIQ(%d+):")
	if embeddedQuality then
		local qNum = tonumber(embeddedQuality)
		if matchQuality(qNum) then return false end
		return true
	end

	return false -- no item links; keep
end

local function ensureClearPopups()
	if not StaticPopupDialogs then return end
	if not StaticPopupDialogs["EQOL_CLEAR_HISTORY_CHAR"] then
		StaticPopupDialogs["EQOL_CLEAR_HISTORY_CHAR"] = {
			text = "Clear chat history for %s?",
			button1 = YES,
			button2 = CANCEL,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
			OnAccept = function(selfPopup, data)
				if data and data.faction and data.realm and data.char then ChannelHistory:WipeCharacterHistory(data.faction, data.realm, data.char) end
			end,
		}
	end
	if not StaticPopupDialogs["EQOL_CLEAR_HISTORY_CHANNEL"] then
		StaticPopupDialogs["EQOL_CLEAR_HISTORY_CHANNEL"] = {
			text = "Clear chat history for %s in current scope?",
			button1 = YES,
			button2 = CANCEL,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
			OnAccept = function(selfPopup, data)
				if data and data.filterKey then ChannelHistory:WipeChannelHistory(data.filterKey) end
			end,
		}
	end
end

local function showPlayerMenu(owner, rawName, isBN, bnetID)
	if not rawName then return false end
	local name = Ambiguate and Ambiguate(rawName, "none") or rawName
	if MU and MU.CreateContextMenu then
		MU.CreateContextMenu(owner, function(_, root, target)
			root:CreateTitle(target)
			root:CreateDivider()
			local unit = target
			local accountID = bnetID
			if isBN and not accountID and BNet_GetBNetIDAccount then accountID = BNet_GetBNetIDAccount(target) end
			if isBN and accountID and C_BattleNet and C_BattleNet.GetAccountInfoByID then
				local info = C_BattleNet.GetAccountInfoByID(accountID)
				local gameInfo = info and info.gameAccountInfo
				if
					gameInfo
					and gameInfo.isOnline
					and gameInfo.clientProgram == BNET_CLIENT_WOW
					and WOW_PROJECT_ID == gameInfo.wowProjectID
					and gameInfo.regionID == GetCurrentRegion()
					and gameInfo.characterName
					and gameInfo.realmName
				then
					local realmKey = sanitizeRealm(gameInfo.realmName)
					unit = string.format("%s-%s", gameInfo.characterName, realmKey)
				end
			else
				if unit and not unit:match("%-") then unit = unit .. "-" .. sanitizeRealm(GetRealmName() or "") end
			end

			if unit then root:CreateButton(INVITE, function(u) C_PartyInfo.InviteUnit(u) end, unit) end
			local function toggleIgnore(unitName)
				if ChatIM and ChatIM.ToggleIgnore then
					ChatIM:ToggleIgnore(unitName)
				elseif C_FriendList and C_FriendList.IsIgnored then
					if C_FriendList.IsIgnored(unitName) then
						C_FriendList.DelIgnore(unitName)
					else
						C_FriendList.AddIgnore(unitName)
					end
				end
			end
			local ignoreLabel = (C_FriendList and C_FriendList.IsIgnored and C_FriendList.IsIgnored(target)) and UNIGNORE_QUEST or IGNORE
			root:CreateButton(ignoreLabel, toggleIgnore, target)
			root:CreateDivider()
			root:CreateTitle(UNIT_FRAME_DROPDOWN_SUBSECTION_TITLE_OTHER)
			if unit then
				root:CreateButton(COPY_CHARACTER_NAME, function(u) showCopyDialog(u) end, unit)
			else
				root:CreateButton(COPY_CHARACTER_NAME, function(u) showCopyDialog(u) end, target)
			end
			local regionTable = { "US", "KR", "EU", "TW", "CN" }
			local regionKey = regionTable[GetCurrentRegion()] or "EU"
			local char, realm = target:match("^([^%-]+)%-(.+)$")
			local rioChar, rioRealm = char, realm
			if not rioChar and unit and unit:match("%-") then
				rioChar, rioRealm = unit:match("^([^%-]+)%-(.+)$")
			end
			if rioChar and rioRealm and addon and addon.db then
				local lowerRealm = rioRealm:gsub("%s+", "-"):lower()
				local lowerChar = rioChar:lower()
				if addon.db["enableChatIMRaiderIO"] then
					local rio = string.format("https://raider.io/characters/%s/%s/%s", regionKey:lower(), lowerRealm, lowerChar)
					root:CreateButton("RaiderIO", function(link) showCopyDialog(link) end, rio)
				end
				if addon.db["enableChatIMWCL"] then
					local wcl = string.format("https://www.warcraftlogs.com/character/%s/%s/%s", regionKey:lower(), lowerRealm, lowerChar)
					root:CreateButton("WarcraftLogs", function(link) showCopyDialog(link) end, wcl)
				end
			end
		end, name)
		return true
	end
	showCopyDialog(name)
	return true
end

local function isVisibleKey(key)
	if type(key) ~= "string" then return true end
	return key:sub(1, 1) ~= "_"
end

local function buildKeys()
	local name = UnitName("player") or "Unknown"
	local realmName = GetRealmName() or "Unknown"
	local faction = UnitFactionGroup("player") or "Neutral"
	local realmKey = sanitizeRealm(realmName)

	return {
		player = name,
		realmName = realmName,
		realmKey = realmKey,
		faction = faction,
		charKey = name .. "-" .. realmKey,
	}
end

local function isLoggingEnabled(filterKey)
	if not filterKey then return true end
	local filters = addon.db and addon.db.chatChannelFiltersEnable
	if not filters then return true end
	local val = filters[filterKey]
	if val == nil then return true end
	return val and true or false
end

local function buildEventSet()
	local events = {}
	if ChannelHistory.EVENT_FILTER_KEY then
		for event, filterKey in pairs(ChannelHistory.EVENT_FILTER_KEY) do
			if not IGNORED_EVENTS[event] and isLoggingEnabled(filterKey) then events[event] = true end
		end
	end
	for _, event in ipairs(ADDITIONAL_EVENTS) do
		local filterKey = ChannelHistory.EVENT_FILTER_KEY and ChannelHistory.EVENT_FILTER_KEY[event]
		if not IGNORED_EVENTS[event] and isLoggingEnabled(filterKey) then events[event] = true end
	end
	return events
end

local function safeSelect(index, ...)
	local value = select(index, ...)
	if value == "" then return nil end
	return value
end

function ChannelHistory:InitStorage()
	EnhanceQoL_ChannelHistory = EnhanceQoL_ChannelHistory or { _version = self.version }
	if not EnhanceQoL_ChannelHistory._version then EnhanceQoL_ChannelHistory._version = self.version end
	self.history = EnhanceQoL_ChannelHistory
	self.keys = buildKeys()
	self.runtime = self.runtime or {}
	self.runtime.guidClassCache = self.runtime.guidClassCache or {}
	if type(self.runtime.guidClassCacheSize) ~= "number" then
		local count = 0
		for _ in pairs(self.runtime.guidClassCache) do
			count = count + 1
		end
		self.runtime.guidClassCacheSize = count
	end
	self.runtime.bnetTagCache = self.runtime.bnetTagCache or {}
	self.runtime.refreshPending = false
	self.runtime.seq = self.runtime.seq or 0
	self.runtime.formattedCache = self.runtime.formattedCache or {}
	setmetatable(self.runtime.formattedCache, { __mode = "k" })
	if addon.db and addon.db.chatChannelHistoryMaxViewLines then self.uiMaxLines = addon.db.chatChannelHistoryMaxViewLines end
end

function ChannelHistory:SetMaxLines(value)
	if not self.history or not self.keys then self:InitStorage() end
	local runtime = self.runtime or {}
	self.runtime = runtime
	local oldMax = self.maxLines or 500
	local newMax = value or oldMax or 500
	local normalizedAt = self.history and self.history._normalizedMaxLines
	local normalizedVersion = (self.history and self.history._normalizedVersion) or 0
	if not runtime.didNormalize and normalizedAt and normalizedAt == newMax and normalizedVersion == self.version then runtime.didNormalize = true end
	local needsNormalize = (newMax ~= oldMax) or not runtime.didNormalize or normalizedAt ~= newMax or normalizedVersion ~= self.version
	self.maxLines = newMax
	if addon.db then addon.db.chatChannelHistoryMaxLines = newMax end
	if not needsNormalize or not self.history then return end

	for _, realms in pairs(self.history) do
		if type(realms) == "table" then
			for _, realmData in pairs(realms) do
				local chars = type(realmData) == "table" and realmData.characters
				if type(chars) == "table" then
					for _, charData in pairs(chars) do
						if charData.channels then
							for _, channel in pairs(charData.channels) do
								normalizeChannelBucket(channel, self.maxLines)
							end
						end
					end
				end
			end
		end
	end
	runtime.didNormalize = true
	self.history._normalizedMaxLines = newMax
	self.history._normalizedVersion = self.version
end

function ChannelHistory:SetUILineLimit(value)
	local limit = tonumber(value) or 1000
	self.uiMaxLines = limit
	if addon.db then addon.db.chatChannelHistoryMaxViewLines = limit end
	if self.ui and self.ui.logFrame then
		self.ui.logFrame:SetMaxLines(limit)
		self:RequestLogRefresh()
	end
end

function ChannelHistory:SetFrameStrata(strata)
	local value = strata or "MEDIUM"
	self.frameStrata = value
	if addon.db then addon.db.chatHistoryFrameStrata = value end
	self:ApplyFrameZOrder()
	self:UpdateToggleButtonStrata()
end

function ChannelHistory:SetFrameLevel(level)
	local lvl = tonumber(level) or 600
	if lvl < 1 then lvl = 1 end
	self.frameLevel = lvl
	if addon.db then addon.db.chatHistoryFrameLevel = lvl end
	self:ApplyFrameZOrder()
	self:UpdateToggleButtonStrata()
end

function ChannelHistory:ApplyFrameZOrder()
	local strata = self.frameStrata or (addon.db and addon.db.chatHistoryFrameStrata) or "MEDIUM"
	local level = self.frameLevel or (addon.db and addon.db.chatHistoryFrameLevel) or 600

	if self.debugFrame then
		self.debugFrame:SetFrameStrata(strata)
		self.debugFrame:SetFrameLevel(level)
	end

	local baseLevel = (self.debugFrame and self.debugFrame:GetFrameLevel()) or level
	if not self.ui then return end

	local function applyZOrder(frame, offset)
		if not frame then return end
		frame:SetFrameStrata(strata)
		frame:SetFrameLevel(baseLevel + (offset or 0))
	end

	applyZOrder(self.ui.closeButton, 2)
	applyZOrder(self.ui.optionsButton, 2)
	applyZOrder(self.ui.copyButton, 2)
	if self.ui.copyPopup then
		self.ui.copyPopup:SetFrameStrata(strata)
		self.ui.copyPopup:SetFrameLevel(baseLevel + 50)
	end
end

function ChannelHistory:UpdateLogFontSize(size, frame)
	local fontSource = ChatFontNormal or GameFontNormal or NumberFontNormal
	local fontFile, fontHeight, fontFlags = fontSource:GetFont()
	local target = frame or (self.ui and self.ui.logFrame)
	local fontObj = self.ui and self.ui.logFont
	if not fontObj then
		fontObj = CreateFont("EnhanceQoLChannelHistoryLogFont")
		if self.ui then self.ui.logFont = fontObj end
	end
	local resolvedSize = size or (addon.db and addon.db.chatChannelHistoryFontSize) or fontHeight or 12
	fontObj:SetFont(fontFile, resolvedSize, fontFlags or "")
	if target then
		target:SetFontObject(fontObj)
		target:SetJustifyH("LEFT")
		target:SetJustifyV("TOP")
		target:SetIndentedWordWrap(false)
	end
end

function ChannelHistory:ApplyFontSize() self:UpdateLogFontSize(addon.db and addon.db.chatChannelHistoryFontSize or 12) end

local function getCharacterBucket(create)
	if not ChannelHistory.keys then ChannelHistory:InitStorage() end
	local storage = ChannelHistory.history
	if not storage then return end

	local keys = ChannelHistory.keys
	local faction = storage[keys.faction]
	if not faction and create then
		faction = {}
		storage[keys.faction] = faction
	end
	if not faction then return end

	local realm = faction[keys.realmKey]
	if not realm and create then
		realm = { realmName = keys.realmName, characters = {} }
		faction[keys.realmKey] = realm
	end
	if not realm or not realm.characters then return end

	local characters = realm.characters
	local charBucket = characters[keys.charKey]
	if not charBucket and create then
		local className, classFile, classID = UnitClass("player")
		charBucket = {
			name = keys.player,
			realm = keys.realmName,
			faction = keys.faction,
			className = className,
			classFile = classFile,
			classID = classID,
			channels = {},
		}
		characters[keys.charKey] = charBucket
		ChannelHistory:RefreshLeftList()
	end

	return charBucket, characters, realm, faction
end

local function buildChannelKey(event, ...)
	local base = event:sub(10)

	if event == "CHAT_MSG_CHANNEL" then
		local channelName = safeSelect(4, ...)
		local channelIndex = safeSelect(8, ...)
		local channelBaseName = safeSelect(9, ...)
		local descriptor = channelBaseName or channelName or base
		local keyPart = descriptor
		if channelIndex then keyPart = tostring(channelIndex) .. ":" .. descriptor end
		local label = channelIndex and (tostring(channelIndex) .. ": " .. descriptor) or descriptor
		return base .. ":" .. keyPart, label
	end

	if event == "CHAT_MSG_COMMUNITIES_CHANNEL" then
		local communityID = safeSelect(18, ...)
		local streamID = safeSelect(19, ...)
		local channelName = safeSelect(4, ...) or base
		local descriptor
		if communityID or streamID then descriptor = string.format("%s:%s", communityID or "COMMUNITY", streamID or "STREAM") end
		local label = descriptor and (descriptor .. ":" .. channelName) or channelName
		return base .. ":" .. (descriptor or channelName), label
	end

	local channelName = safeSelect(4, ...)
	if channelName then return base .. ":" .. channelName, channelName end

	return base, base
end

local function getLineCount(channelBucket)
	if not channelBucket or not channelBucket.lines then return 0 end
	return channelBucket._count or #channelBucket.lines
end

local function getLineAt(channelBucket, pos, countOverride)
	if not channelBucket or not channelBucket.lines then return nil end
	local lines = channelBucket.lines
	local count = countOverride or channelBucket._count or #lines
	if pos < 1 or pos > count then return nil end
	local cap = channelBucket._cap or #lines
	if cap <= 0 then cap = count end
	local head = channelBucket._head or 1
	local idx = (head + pos - 2) % cap + 1
	return lines[idx]
end

local function iterChannelLines(channelBucket)
	if not channelBucket or not channelBucket.lines then
		return function() end
	end
	local lines = channelBucket.lines
	local cap = channelBucket._cap or #lines
	local count = channelBucket._count or #lines
	if count <= 0 then
		return function() end
	end
	if cap <= 0 then cap = count end
	local head = channelBucket._head or 1
	local i = 0

	return function()
		i = i + 1
		if i > count then return end
		local idx = (head + i - 2) % cap + 1
		return lines[idx]
	end
end

local function appendLine(channelBucket)
	local cap = ChannelHistory.maxLines or 0
	if cap <= 0 then return nil end

	local lines = channelBucket.lines
	if not lines then
		lines = {}
		channelBucket.lines = lines
	end

	local bucketCap = channelBucket._cap
	local head = channelBucket._head or 1
	local count = channelBucket._count or #lines
	if not bucketCap or bucketCap <= 0 then bucketCap = #lines end

	if bucketCap ~= cap or count > cap then
		local newLines = {}
		local start = math.max(1, count - cap + 1)
		for i = start, count do
			local idx
			if channelBucket._cap and bucketCap > 0 then
				idx = (head + i - 2) % bucketCap + 1
			else
				idx = i
			end
			newLines[#newLines + 1] = lines[idx]
		end
		lines = newLines
		channelBucket.lines = lines
		bucketCap = cap
		head = 1
		count = #lines
	end

	local insertIdx = (head + count - 1) % cap + 1
	local slot = lines[insertIdx]
	if not slot then
		slot = {}
		lines[insertIdx] = slot
	end

	if count < cap then
		count = count + 1
	else
		head = head % cap + 1
	end

	channelBucket._cap = cap
	channelBucket._head = head
	channelBucket._count = count
	return slot
end

local function normalizeChannelBucketInner(channelBucket, cap)
	if not channelBucket then return end
	cap = cap or ChannelHistory.maxLines or 0
	channelBucket.lines = channelBucket.lines or {}
	if cap <= 0 then
		wipe(channelBucket.lines)
		channelBucket._cap = cap
		channelBucket._head = 1
		channelBucket._count = 0
		return
	end

	local count = channelBucket._count or #channelBucket.lines
	local head = channelBucket._head or 1
	local oldCap = channelBucket._cap or #channelBucket.lines
	if oldCap <= 0 then oldCap = count end

	if count <= cap and channelBucket._cap == cap and channelBucket._head then
		channelBucket._count = count
		channelBucket._cap = channelBucket._cap or cap
		channelBucket._head = head
		return
	end

	local newLines = {}
	local start = math.max(1, count - cap + 1)
	for i = start, count do
		local idx
		if channelBucket._cap and oldCap > 0 then
			idx = (head + i - 2) % oldCap + 1
		else
			idx = i
		end
		newLines[#newLines + 1] = channelBucket.lines[idx]
	end

	channelBucket.lines = newLines
	channelBucket._cap = cap
	channelBucket._head = 1
	channelBucket._count = #newLines
end

normalizeChannelBucket = normalizeChannelBucketInner

function ChannelHistory:Store(event, ...)
	local filterKey = self.EVENT_FILTER_KEY and self.EVENT_FILTER_KEY[event]
	-- Skip learn/unlearn spam unconditionally
	if filterKey == "SYSTEM" and addon.functions and addon.functions.ChatLearnFilter then
		local firstArg = ...
		if addon.functions.ChatLearnFilter(nil, nil, firstArg) then return end
	end
	if self.maxLines == 0 then return end
	if not self.history or not self.keys then self:InitStorage() end
	local charBucket = getCharacterBucket(true)
	if not charBucket then return end
	local currentCharKey = self.keys and self.keys.charKey

	local msg, sender, _, _, _, _, _, _, _, _, lineID, guid, bnetIDAccount, _, _ = ...
	if issecretvalue and issecretvalue(msg) then return end
	-- Skip channel notices and trivial change messages
	if event == "CHAT_MSG_CHANNEL_NOTICE" or event == "CHAT_MSG_CHANNEL_NOTICE_USER" then return end
	if msg == "YOU_CHANGED" then return end
	if filterKey == "LOOT" and shouldFilterLootByQuality(msg, event) then return end
	if event == "CHAT_MSG_ACHIEVEMENT" or event == "CHAT_MSG_GUILD_ACHIEVEMENT" then
		local replacement
		local linkTarget = sender
		local nameColor
		local chatColorLocal = (ChatTypeInfo and ChatTypeInfo["SYSTEM"]) or nil
		if guid and (UnitGUID and guid == UnitGUID("player")) then nameColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[(select(2, UnitClass("player")))] end
		if not nameColor and guid then
			local _, classTok = getSenderClass(guid)
			if classTok then nameColor = getClassStyle(classTok) end
		end
		local nameColorCode = toColorCode(nameColor or chatColorLocal or { r = 1, g = 1, b = 1 })
		if sender and sender:find("|Hplayer:", 1, true) then linkTarget = sender:match("^|Hplayer:([^:|]+)") end
		if not linkTarget or linkTarget == "" then linkTarget = ACHIEVEMENT_BROADCAST end

		local displayText = linkTarget
		if linkTarget and linkTarget:find("-", 1, true) then
			local namePart, realmPart = linkTarget:match("^([^%-]+)%-(.+)$")
			if namePart then
				displayText = namePart
				local myRealm = self.keys and self.keys.realmKey
				if myRealm and realmPart ~= myRealm then displayText = namePart .. "-" .. realmPart end
			end
		end

		if linkTarget and linkTarget ~= "" then
			replacement = string.format("|Hplayer:%s|h%s[%s]|r|h", linkTarget, nameColorCode, displayText)
			sender = linkTarget
		else
			replacement = ACHIEVEMENT_BROADCAST or "%s"
		end

		msg = msg:gsub("%%s", replacement, 1)
	end
	local channelKey, channelLabel = buildChannelKey(event, ...)
	channelKey = channelKey or event
	local classFile
	if guid and isPlayerGUID(guid) then
		local _, classTok = getSenderClass(guid)
		classFile = classTok
	end
	if filterKey == "BN_WHISPER" then
		local plain = (BNTokenFindName and BNTokenFindName(sender)) or sender
		local accountID = bnetIDAccount
		if not accountID and BNet_GetBNetIDAccount and plain then accountID = BNet_GetBNetIDAccount(plain) end
		accountID = tonumber(accountID) or nil
		if accountID then
			bnetIDAccount = accountID
			local tag = resolveBNetTag(accountID)
			if tag and tag ~= "" then sender = string.format("|HBNplayer:%s:%s|h[%s]|h", tag, tostring(accountID), tag) end
		end
	end
	local stamp = now()
	self.runtime.seq = (self.runtime.seq or 0) + 1

	charBucket.channels = charBucket.channels or {}
	local channelBucket = charBucket.channels[channelKey] or { label = channelLabel or channelKey, lines = {} }
	channelBucket.label = channelLabel or channelBucket.label or channelKey

	local slot = appendLine(channelBucket)
	if not slot then return end
	local cache = self.runtime and self.runtime.formattedCache
	if cache then cache[slot] = nil end
	-- clear legacy/derived fields on reused slots to avoid stale state bleed-through
	slot.color = nil
	slot.event = nil
	slot.senderBTag = nil
	slot.senderName = nil
	slot.senderRealmKey = nil
	slot.ownerRealmKey = nil
	slot.ownerFaction = nil
	slot.time = stamp
	slot.filterKey = filterKey
	slot.outbound = event == "CHAT_MSG_WHISPER_INFORM" or event == "CHAT_MSG_BN_WHISPER_INFORM"
	slot.event = event
	slot.message = msg or ""
	slot.sender = sender or ""
	slot.ownerCharKey = self.keys.charKey
	slot.ownerRealmKey = self.keys.realmKey
	slot.ownerFaction = self.keys.faction
	slot.senderClassFile = classFile
	slot.lineID = lineID
	slot.guid = guid
	slot.seq = self.runtime.seq
	slot.bnetIDAccount = bnetIDAccount
	if filterKey == "BN_WHISPER" and bnetIDAccount then slot.senderBTag = resolveBNetTag(bnetIDAccount) end
	channelBucket.lastUpdated = stamp
	-- do not pre-format; format on demand
	charBucket.channels[channelKey] = channelBucket
	charBucket.lastUpdated = slot.time
	if not charBucket.classFile then
		local className, classFile, classID = UnitClass("player")
		charBucket.className = className
		charBucket.classFile = classFile
		charBucket.classID = classID
	end
	if self.debugFrame and self.debugFrame:IsShown() then
		if self:ShouldDisplayLive(slot, currentCharKey) then self:AppendLineToLog(slot) end
	end
end

local function iterCharacters(scope, realmKey, charKey, factionKey)
	if not ChannelHistory.history or not ChannelHistory.keys then
		return function() end
	end

	local function yieldFromRealm(realm)
		if not realm or not realm.characters then
			return function() end
		end
		local keyList = {}
		for charKeyInner in pairs(realm.characters) do
			table.insert(keyList, charKeyInner)
		end
		table.sort(keyList)
		local i = 0
		return function()
			i = i + 1
			local key = keyList[i]
			if not key then return end
			return key, realm.characters[key]
		end
	end

	local function yieldFromFaction(factionBucket)
		if not factionBucket then
			return function() end
		end
		local realmKeys = {}
		for rKey, bucket in pairs(factionBucket) do
			if type(bucket) == "table" and isVisibleKey(rKey) then table.insert(realmKeys, rKey) end
		end
		table.sort(realmKeys)
		local realmIndex = 0
		local charIter = nil
		return function()
			while true do
				if not charIter then
					realmIndex = realmIndex + 1
					local rKey = realmKeys[realmIndex]
					if not rKey then return end
					charIter = yieldFromRealm(factionBucket[rKey])
				end
				local ck, data = charIter()
				if ck then return ck, data end
				charIter = nil
			end
		end
	end

	if scope == nil or scope == "character" then
		local targetChar = charKey or ChannelHistory.keys.charKey
		local inferredRealm = realmFromCharKey(targetChar)
		local targetRealm = realmKey or inferredRealm or ChannelHistory.keys.realmKey
		local targetFaction = factionKey or ChannelHistory.keys.faction
		local factionBucket = ChannelHistory.history[targetFaction]
		local realmBucket = factionBucket and factionBucket[targetRealm]
		local bucket = realmBucket and realmBucket.characters and realmBucket.characters[targetChar]
		local returned = false
		return function()
			if returned or not bucket then return end
			returned = true
			return targetChar, bucket
		end
	end

	if scope == "realm" then
		local targetRealm = realmKey or ChannelHistory.keys.realmKey
		if factionKey then
			local factionBucket = ChannelHistory.history[factionKey]
			return yieldFromRealm(factionBucket and factionBucket[targetRealm])
		end
		-- aggregate both factions for this realm
		local factionKeys = {}
		for fKey, bucket in pairs(ChannelHistory.history) do
			if type(bucket) == "table" and isVisibleKey(fKey) and bucket[targetRealm] then table.insert(factionKeys, fKey) end
		end
		table.sort(factionKeys)
		local fIndex = 0
		local charIter = nil
		return function()
			while true do
				if not charIter then
					fIndex = fIndex + 1
					local fKey = factionKeys[fIndex]
					if not fKey then return end
					charIter = yieldFromRealm(ChannelHistory.history[fKey] and ChannelHistory.history[fKey][targetRealm])
				end
				local ck, data = charIter()
				if ck then return ck, data end
				charIter = nil
			end
		end
	end

	if scope == "faction" and factionKey then
		local bucket = ChannelHistory.history[factionKey]
		if type(bucket) ~= "table" then
			return function() end
		end

		if realmKey and bucket[realmKey] then return yieldFromRealm(bucket[realmKey]) end
		return yieldFromFaction(bucket)
	end

	if scope == "faction" then
		local factionKeys = {}
		for fKey, bucket in pairs(ChannelHistory.history) do
			if type(bucket) == "table" and isVisibleKey(fKey) then table.insert(factionKeys, fKey) end
		end
		table.sort(factionKeys)
		local fIndex = 0
		local charIter = nil
		return function()
			while true do
				if not charIter then
					fIndex = fIndex + 1
					local fKey = factionKeys[fIndex]
					if not fKey then return end
					charIter = yieldFromFaction(ChannelHistory.history[fKey])
				end
				local ck, data = charIter()
				if ck then return ck, data end
				charIter = nil
			end
		end
	end

	return function() end
end

function ChannelHistory:GetChannels(scope)
	if not self.history or not self.keys then self:InitStorage() end
	scope = scope or "character"
	local channels = {}
	for _, charData in iterCharacters(scope) do
		if charData and charData.channels then
			for channelKey, channelData in pairs(charData.channels) do
				channels[channelKey] = channels[channelKey] or { label = channelData.label or channelKey, count = 0 }
				channels[channelKey].count = channels[channelKey].count + getLineCount(channelData)
			end
		end
	end
	return channels
end

function ChannelHistory:GetHistory(scope, channelKey)
	if not self.history or not self.keys then self:InitStorage() end
	scope = scope or "character"
	local result = {}
	if not channelKey or channelKey == "" then return result end

	for charKey, charData in iterCharacters(scope) do
		if charData and charData.channels and charData.channels[channelKey] and charData.channels[channelKey].lines then
			for line in iterChannelLines(charData.channels[channelKey]) do
				table.insert(result, {
					character = charKey,
					faction = charData.faction or self.keys and self.keys.faction,
					realm = charData.realm,
					channel = channelKey,
					label = charData.channels[channelKey].label or channelKey,
					data = line,
				})
			end
		end
	end

	table.sort(result, function(a, b)
		local at = a.data.time or 0
		local bt = b.data.time or 0
		if at ~= bt then return at < bt end
		local aid = (a.data.seq or a.data.lineID or 0)
		local bid = (b.data.seq or b.data.lineID or 0)
		return aid < bid
	end)
	return result
end

local function setClassIcon(btn, classFile)
	if not btn or not btn.icon then return end
	if CLASS_ICON_TCOORDS and classFile and CLASS_ICON_TCOORDS[classFile] then
		local coords = CLASS_ICON_TCOORDS[classFile]
		btn.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
		btn.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
		btn.icon:Show()
	else
		btn.icon:SetTexture(nil)
		btn.icon:Hide()
	end
end

local CHAT_COLOR_KEYS = {
	SAY = "SAY",
	YELL = "YELL",
	WHISPER = "WHISPER",
	BN_WHISPER = "BN_WHISPER",
	PARTY = "PARTY",
	INSTANCE = "INSTANCE_CHAT",
	RAID = "RAID",
	GUILD = "GUILD",
	OFFICER = "OFFICER",
	GENERAL = "CHANNEL", -- fallback to channel1 if CHANNEL missing
	LOOT = "LOOT",
	MONEY = "MONEY",
	ACHIEVEMENT = "ACHIEVEMENT",
	SYSTEM = "SYSTEM",
	OPENING = "OPENING",
	MONSTER = "MONSTER_SAY",
}

local CHAT_COLOR_FALLBACK = {
	SAY = { r = 1, g = 1, b = 1 },
	YELL = { r = 1, g = 0.25, b = 0.25 },
	WHISPER = { r = 1, g = 0.5, b = 1 },
	BN_WHISPER = { r = 0, g = 1, b = 0.96 },
	PARTY = { r = 170 / 255, g = 170 / 255, b = 1 },
	INSTANCE = { r = 170 / 255, g = 170 / 255, b = 1 },
	RAID = { r = 1, g = 127 / 255, b = 0 },
	GUILD = { r = 0.25, g = 1, b = 0.25 },
	OFFICER = { r = 0.25, g = 0.75, b = 0.25 },
	GENERAL = { r = 192 / 255, g = 128 / 255, b = 128 / 255 },
	LOOT = { r = 0, g = 170 / 255, b = 0 },
	MONEY = { r = 0, g = 170 / 255, b = 0 },
	ACHIEVEMENT = { r = 1, g = 0.75, b = 0.25 },
	SYSTEM = { r = 1, g = 1, b = 0 },
	OPENING = { r = 128 / 255, g = 128 / 255, b = 1 },
	MONSTER = { r = 0.9, g = 0.7, b = 0.3 },
}

function splitSender(sender)
	if not sender or sender == "" then return nil, nil end
	local name, realm = sender:match("^(.-)%-(.+)$")
	if not name or name == "" then name = sender end
	if realm and realm ~= "" then realm = sanitizeRealm(realm) end
	return name, realm
end

function realmFromCharKey(charKey)
	if not charKey or charKey == "" then return nil end
	local _, realm = splitSender(charKey)
	return realm
end

local CLASS_NAME_TO_FILE = nil

local function buildClassLookup()
	if CLASS_NAME_TO_FILE then return end
	CLASS_NAME_TO_FILE = {}
	if LOCALIZED_CLASS_NAMES_MALE then
		for token, loc in pairs(LOCALIZED_CLASS_NAMES_MALE) do
			CLASS_NAME_TO_FILE[loc] = token
		end
	end
	if LOCALIZED_CLASS_NAMES_FEMALE then
		for token, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
			CLASS_NAME_TO_FILE[loc] = token
		end
	end
end

local function resolveClassToken(val)
	buildClassLookup()
	if type(val) ~= "string" then return nil end
	local upper = val:upper()
	if RAID_CLASS_COLORS and RAID_CLASS_COLORS[upper] then return upper end
	return CLASS_NAME_TO_FILE and CLASS_NAME_TO_FILE[val] or nil
end

local function cacheGuidClass(guid, token, loc)
	if not guid or not token or not isPlayerGUID(guid) then return end
	local runtime = ChannelHistory.runtime
	if not runtime then return end
	runtime.guidClassCache = runtime.guidClassCache or {}
	runtime.guidClassCacheSize = runtime.guidClassCacheSize or 0
	local cache = runtime.guidClassCache
	local existing = cache[guid]
	cache[guid] = { token = token, loc = loc or token }
	if not existing then runtime.guidClassCacheSize = runtime.guidClassCacheSize + 1 end
	local limit = GUID_CACHE_LIMIT or 0
	if limit > 0 and runtime.guidClassCacheSize > limit then
		wipe(cache)
		runtime.guidClassCacheSize = 0
		cache[guid] = { token = token, loc = loc or token }
		runtime.guidClassCacheSize = 1
	end
end

function resolveClassFromGUID(guid)
	if not guid or not isPlayerGUID(guid) or not GetPlayerInfoByGUID then return nil end
	local cache = ChannelHistory.runtime and ChannelHistory.runtime.guidClassCache
	if cache and cache[guid] then return cache[guid].token end
	local locClass, classFile = GetPlayerInfoByGUID(guid)
	local className = locClass
	local token = classFile or resolveClassToken(className)
	if token then cacheGuidClass(guid, token, className) end
	return token
end

function getSenderClass(guid)
	if not guid or not isPlayerGUID(guid) or not GetPlayerInfoByGUID then return nil, nil end
	local cache = ChannelHistory.runtime and ChannelHistory.runtime.guidClassCache
	if cache and cache[guid] then return cache[guid].loc, cache[guid].token end
	local locClass, classFile = GetPlayerInfoByGUID(guid)
	local className = locClass
	local token = classFile or resolveClassToken(className)
	local locName = className
	if not locName and token then locName = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or (LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[token]) or token end
	if token then cacheGuidClass(guid, token, locName or token) end
	return locName, token
end

function toColorCode(color)
	if not color then return "|r" end
	local r = math.floor((color.r or 1) * 255 + 0.5)
	local g = math.floor((color.g or 1) * 255 + 0.5)
	local b = math.floor((color.b or 1) * 255 + 0.5)
	return string.format("|cff%02x%02x%02x", r, g, b)
end

local function formatURLs(text)
	if not text or text == "" then return text end
	if not (text:find("://", 1, true) or text:find("www.", 1, true)) then return text end
	local function repl(url) return "|Hurl:" .. url .. "|h[|cffffffff" .. url .. "|r]|h" end
	text = text:gsub("https?://%S+", repl)
	if text:sub(1, 4) == "www." then text = text:gsub("^(www%.%S+)", repl) end
	text = text:gsub("(%s)(www%.%S+)", function(space, url) return space .. repl(url) end)
	return text
end

local colorCacheByEvent = {}
local colorCacheByKey = {}

local function resolveChatTypeInfo(chatKey)
	if not chatKey then return nil end
	local info = ChatTypeInfo and ChatTypeInfo[chatKey]
	if (not info or not info.r) and chatKey == "CHANNEL" then info = ChatTypeInfo and ChatTypeInfo["CHANNEL1"] end
	if info and info.r and info.g and info.b then return info end
	return nil
end

function getChatColor(key, event)
	if not key and not event then return nil end

	if event and type(event) == "string" then
		local cached = colorCacheByEvent[event]
		if cached ~= nil then return cached end

		local chatKeyFromEvent = event:sub(10) -- "CHAT_MSG_" weg
		local infoFromEvent = resolveChatTypeInfo(chatKeyFromEvent)
		if infoFromEvent then
			colorCacheByEvent[event] = infoFromEvent
			return infoFromEvent
		end
		local fb = (CHAT_COLOR_FALLBACK and CHAT_COLOR_FALLBACK[chatKeyFromEvent]) or nil
		colorCacheByEvent[event] = fb or false
		if fb then return fb end
	end

	local mappedKey = (CHAT_COLOR_KEYS and (CHAT_COLOR_KEYS[key] or key)) or key
	local cached = colorCacheByKey[mappedKey]
	if cached ~= nil then return cached end

	local info = resolveChatTypeInfo(mappedKey)
	if info then
		colorCacheByKey[mappedKey] = info
		return info
	end

	local fb = (CHAT_COLOR_FALLBACK and (CHAT_COLOR_FALLBACK[mappedKey] or CHAT_COLOR_FALLBACK[key])) or nil
	colorCacheByKey[mappedKey] = fb or false
	return fb
end

local _formatParts = {}

function formatLine(self, line)
	if not line then return "" end
	local cache = self.runtime and self.runtime.formattedCache
	if cache and cache[line] then return cache[line] end

	-- Enrich sender info if it was not stored yet (old lines)
	local senderNameStored, senderRealmStored = line.senderName, line.senderRealmKey
	local senderName, senderRealmKey = senderNameStored, senderRealmStored
	if not senderName or senderRealmKey == nil then
		senderName, senderRealmKey = splitSender(line.sender)
	end

	local playerName = self.keys and self.keys.player
	local playerGUID = self.runtime and self.runtime.playerGUID
	if not playerGUID and UnitGUID then
		playerGUID = UnitGUID("player")
		if self.runtime then self.runtime.playerGUID = playerGUID end
	end
	local isOutbound = line.outbound or (line.event == "CHAT_MSG_WHISPER_INFORM" or line.event == "CHAT_MSG_BN_WHISPER_INFORM")
	local isSelf = false
	if isOutbound then
		isSelf = true
	elseif playerGUID and line.guid and line.guid == playerGUID then
		isSelf = true
	elseif playerName and senderName and senderName == playerName then
		isSelf = true
	end

	local classFile = line.senderClassFile
	if not classFile and line.guid then
		local _, classTok = getSenderClass(line.guid)
		classFile = classTok
		if not classFile then classFile = resolveClassFromGUID(line.guid) end
	end
	local classColor = classFile and getClassStyle(classFile) or nil

	local ownerRealmKey = line.ownerRealmKey or realmFromCharKey(line.ownerCharKey) or (self.keys and self.keys.realmKey)
	local playerRealmKey = ownerRealmKey
	senderRealmKey = senderRealmKey or playerRealmKey
	local sameRealm = senderRealmKey and playerRealmKey and senderRealmKey == playerRealmKey
	local displayName = senderName or ""
	if line.filterKey == "BN_WHISPER" then
		if line.senderBTag and line.senderBTag ~= "" then
			displayName = line.senderBTag
		elseif line.bnetIDAccount then
			local tag = resolveBNetTag(line.bnetIDAccount)
			if tag and tag ~= "" then
				displayName = tag
				line.senderBTag = tag
			elseif line.sender and line.sender:find("#", 1, true) then
				displayName = line.sender
				line.senderBTag = line.sender
			end
		end
		senderRealmKey = nil
		sameRealm = true
	end
	if isSelf then
		sameRealm = true
	elseif displayName ~= "" and not sameRealm and senderRealmKey and senderRealmKey ~= "" then
		displayName = displayName .. "-" .. senderRealmKey
	end

	local timeText = date("%H:%M:%S", line.time or now())
	timeText = string.format("|cffb0b0b0%s|r", timeText)

	local chatColor = line.color or getChatColor(line.filterKey, line.event) or { r = 1, g = 0.82, b = 0 }
	local chatColorCode = toColorCode(chatColor)

	local nameColor = classColor or chatColor
	local nameColorCode = toColorCode(nameColor)
	local nameText = ""
	if displayName and displayName ~= "" then
		local isAchievementEvent = line.event == "CHAT_MSG_ACHIEVEMENT" or line.event == "CHAT_MSG_GUILD_ACHIEVEMENT"
		if isAchievementEvent then
			nameText = ""
		elseif line.filterKey == "MONSTER" then
			nameText = string.format("%s%s|r", nameColorCode, displayName)
		elseif line.filterKey == "BN_WHISPER" and line.bnetIDAccount then
			nameText = string.format("|HBNplayer:%s:%s|h%s[%s]|r|h", displayName, tostring(line.bnetIDAccount or ""), nameColorCode, displayName)
		else
			local linkTarget = line.sender and line.sender ~= "" and line.sender or displayName
			local prefix = ""
			if isOutbound and (line.filterKey == "WHISPER" or line.filterKey == "BN_WHISPER") then
				local toPrefix = L["CH_TO_PREFIX"]
				if toPrefix and toPrefix ~= "" then prefix = toPrefix .. " " end
			end
			nameText = string.format("%s|Hplayer:%s|h%s[%s]|r|h", prefix, linkTarget, nameColorCode, displayName)
		end
	end

	local body = formatURLs(line.message or "")
	if body:find("|r", 1, true) then body = body:gsub("|r", "|r" .. chatColorCode) end

	table.wipe(_formatParts)
	local parts = _formatParts
	parts[1] = timeText
	parts[2] = " "
	parts[3] = chatColorCode
	local n = 3
	if nameText ~= "" then
		n = n + 1
		parts[n] = nameText
		n = n + 1
		parts[n] = "|r"
		n = n + 1
		parts[n] = chatColorCode
		n = n + 1
		parts[n] = ": "
	end
	n = n + 1
	parts[n] = body
	n = n + 1
	parts[n] = "|r"

	local text = table.concat(parts, "", 1, n)
	if cache then cache[line] = text end
	return text
end

local function matchesSearchLower(needle, message, sender, channelKey)
	if not needle or needle == "" then return true end
	if message and message:lower():find(needle, 1, true) then return true end
	if sender and sender:lower():find(needle, 1, true) then return true end
	if channelKey and type(channelKey) == "string" and channelKey:lower():find(needle, 1, true) then return true end
	return false
end

local function parseSelection(self)
	local sel = self.ui and self.ui.selection or {}
	local selType = sel.type or "character"
	local selChar = sel.charKey
	local selRealm = sel.realmKey or sel.realm
	local selFaction = sel.factionKey or sel.faction
	if selType == "character" and not selChar and sel.key then selChar = sel.key:match("^char:[^:]+:[^:]+:(.+)$") end
	if selType == "realm" and not selRealm and sel.key then selRealm = sel.key:match("^realm:(.+)$") end
	if selType == "faction" and (not selFaction or not selRealm) and sel.key then
		local rKey, fKey = sel.key:match("^faction:([^:]+):(.+)$")
		selRealm = selRealm or rKey
		selFaction = selFaction or fKey
	end
	selFaction = selFaction or (self.keys and self.keys.faction)
	selRealm = selRealm or (self.keys and self.keys.realmKey)
	selChar = selChar or (self.keys and self.keys.charKey)
	return selType, selFaction, selRealm, selChar
end

function ChannelHistory:ForEachSelectedCharacter(fn)
	if not self.history then return end
	local selType, selFaction, selRealm, selChar = parseSelection(self)
	for fKey, faction in pairs(self.history) do
		if isVisibleKey(fKey) and type(faction) == "table" then
			if selType ~= "faction" or not selFaction or fKey == selFaction then
				for realmKey, realm in pairs(faction or {}) do
					if type(realm) == "table" then
						local restrictRealm = (selType == "realm" or selType == "faction")
						if (not restrictRealm) or not selRealm or (realmKey == selRealm) then
							for charKey, bucket in pairs(realm.characters or {}) do
								if selType ~= "character" or not selChar or charKey == selChar then fn(bucket, fKey, realmKey, charKey, realm) end
							end
						end
					end
				end
			end
		end
	end
end

local function wipeEmptyContainers(history)
	if type(history) ~= "table" then return end

	for fKey, faction in pairs(history) do
		-- skip metadata keys like _version and skip non-tables
		if isVisibleKey(fKey) and type(faction) == "table" then
			for realmKey, realm in pairs(faction) do
				if type(realm) == "table" then
					local characters = realm.characters
					if type(characters) == "table" then
						for charKey, bucket in pairs(characters) do
							-- bucket/channels must be tables, otherwise treat as empty
							if type(bucket) ~= "table" or type(bucket.channels) ~= "table" or isTableEmpty(bucket.channels) then characters[charKey] = nil end
						end

						-- remove empty realm
						if isTableEmpty(characters) then faction[realmKey] = nil end
					end
				end
			end

			-- remove empty faction bucket (Alliance/Horde)
			if isTableEmpty(faction) then history[fKey] = nil end
		end
	end
end

function ChannelHistory:WipeCharacterHistory(factionKey, realmKey, charKey)
	if not self.history or not factionKey or not realmKey or not charKey then return end
	local faction = self.history[factionKey]
	if not faction then return end
	local realm = faction[realmKey]
	if not realm or not realm.characters then return end
	realm.characters[charKey] = nil
	wipeEmptyContainers(self.history)
	self:RefreshLeftList()
	self:RequestLogRefresh()
end

function ChannelHistory:WipeChannelHistory(filterKey)
	if not self.history or not filterKey then return end
	local removed = 0

	self:ForEachSelectedCharacter(function(bucket)
		if type(bucket.channels) ~= "table" then return end

		for chKey, chData in pairs(bucket.channels) do
			if chData and chData.lines then
				local originalCount = getLineCount(chData)

				local keep = {}
				for line in iterChannelLines(chData) do
					if line.filterKey ~= filterKey then keep[#keep + 1] = line end
				end

				local delta = originalCount - #keep
				if delta > 0 then
					removed = removed + delta
					chData.lines = keep
					chData._count = #keep
					chData._head = 1
					chData._cap = #keep
					if #keep == 0 then bucket.channels[chKey] = nil end
				end
			end
		end
	end)

	wipeEmptyContainers(self.history)
	self:RefreshLeftList()
	self:RequestLogRefresh()
	return removed
end

function ChannelHistory:ShouldDisplayLive(line, currentCharKey)
	if not line then return false end
	if not self.debugFrame or not self.debugFrame:IsShown() then return false end
	if not self.ui or not self.ui.logFrame then return false end
	if not line.filterKey and line.event and self.EVENT_FILTER_KEY then line.filterKey = self.EVENT_FILTER_KEY[line.event] end
	if not self:IsFilterEnabled(line.filterKey) then return false end
	local scope, realmKey, charKey, factionKey = deriveScope(self.ui.selection, self.keys)
	if scope == "character" then
		if charKey and line.ownerCharKey and charKey ~= line.ownerCharKey then return false end
	elseif scope == "realm" then
		local lineRealm = line.ownerRealmKey or realmFromCharKey(line.ownerCharKey) or self.keys.realmKey
		if realmKey and lineRealm and realmKey ~= lineRealm then return false end
		local lineFaction = line.ownerFaction or (self.keys and self.keys.faction)
		if factionKey and lineFaction and factionKey ~= lineFaction then return false end
	elseif scope == "faction" and factionKey then
		local lineFaction = line.ownerFaction or (self.keys and self.keys.faction)
		if lineFaction and factionKey ~= lineFaction then return false end

		local lineRealm = line.ownerRealmKey or realmFromCharKey(line.ownerCharKey) or (self.keys and self.keys.realmKey)
		if realmKey and lineRealm and realmKey ~= lineRealm then return false end
	end

	local needle = self.ui and self.ui.searchNeedleLower
	if needle == nil and self.ui and self.ui.rightSearch then
		needle = (self.ui.rightSearch:GetText() or ""):lower()
		self.ui.searchNeedleLower = needle
	end
	if not matchesSearchLower(needle, line.message, line.sender, line.filterKey) then return false end
	return true
end

function ChannelHistory:UpdateStatusBar(count, maxUI, scopeLabel)
	if not self.ui or not self.ui.statusBar or not self.ui.statusBar.text then return end
	if scopeLabel then self.ui.statusScopeLabel = scopeLabel end
	if maxUI then self.ui.statusMax = maxUI end
	if count ~= nil then self.ui.statusCount = count end
	local label = self.ui.statusScopeLabel or ALL or "All"
	local maxVal = self.ui.statusMax or (self.ui.logFrame and self.ui.logFrame:GetMaxLines()) or self.uiMaxLines or 0
	local cnt = self.ui.statusCount or 0
	self.ui.statusBar.text:SetText(string.format("%s   •   %d / %d", label, cnt, maxVal))
end

function ChannelHistory:AppendLineToLog(line)
	if not self.ui or not self.ui.logFrame then return end
	local text = formatLine(self, line)
	self.ui.logFrame:AddMessage(text, 1, 1, 1)
	if self.ui.logFrame.ScrollToBottom then self.ui.logFrame:ScrollToBottom() end
	local maxUI = (self.ui.logFrame and self.ui.logFrame:GetMaxLines()) or self.uiMaxLines or 0
	local nextCount = (self.ui and self.ui.statusCount or 0) + 1
	if maxUI and maxUI > 0 then nextCount = math.min(nextCount, maxUI) end
	self:UpdateStatusBar(nextCount, maxUI)
end

function ChannelHistory:RequestLogRefresh()
	if self.runtime and self.runtime.refreshPending then return end
	if not self.runtime then self.runtime = {} end
	self.runtime.refreshPending = true
	C_Timer.After(0.15, function()
		self.runtime.refreshPending = false
		if self.debugFrame and self.debugFrame:IsShown() then self:RefreshLogView() end
	end)
end

function ChannelHistory:RequestLeftRefresh()
	self.runtime = self.runtime or {}
	if self.runtime.leftRefreshPending then return end
	self.runtime.leftRefreshPending = true
	C_Timer.After(0.05, function()
		self.runtime.leftRefreshPending = false
		if self.debugFrame and self.debugFrame:IsShown() then self:RefreshLeftList() end
	end)
end

function ChannelHistory:IsFilterEnabled(filterKey)
	if not filterKey then return true end
	self.ui = self.ui or {}
	self.ui.filters = self.ui.filters or {}
	local stored = self.ui.filters[filterKey]
	if stored ~= nil then return stored end
	return self.defaultFilters[filterKey] ~= false
end

function ChannelHistory:LoadFiltersFromDB()
	self.ui = self.ui or {}
	self.ui.filters = self.ui.filters or {}
	if addon.db and addon.db.chatChannelFilters then
		for k, v in pairs(addon.db.chatChannelFilters) do
			self.ui.filters[k] = v and true or false
		end
	end
end

function ChannelHistory:SetSelection(selection)
	if type(selection) ~= "table" then return end
	if not self.history or not self.keys then self:InitStorage() end
	self.ui = self.ui or {}
	self.ui.selection = selection
	if self.history then self.history._selection = selection end
	if addon.db then addon.db.chatHistorySelection = selection end
end

function deriveScope(selection, keys)
	if not selection then return "character", keys and keys.realmKey, keys and keys.charKey, keys and keys.faction end
	if selection.type == "header" then return "faction", nil, nil, nil end
	if selection.type == "realm" then
		local realmKey = selection.realm or (selection.key and selection.key:match("^realm:(.+)$")) or selection.key
		return "realm", realmKey, nil, nil
	end
	if selection.type == "faction" then
		local realmKey, factionKey = (selection.key or ""):match("^faction:([^:]+):(.+)$")
		if not factionKey then factionKey = selection.faction or (selection.key and selection.key:match("^faction:(.+)$")) end
		if not realmKey then realmKey = selection.realm or (keys and keys.realmKey) end
		return "faction", realmKey, nil, factionKey
	end
	if selection.type == "character" then
		local realmKey, factionKey, charKey = (selection.key or ""):match("^char:([^:]+):([^:]+):(.+)$")
		if not charKey then charKey = selection.key and selection.key:match("^char:(.+)$") or selection.key end
		if not realmKey then realmKey = selection.realm or (keys and keys.realmKey) end
		if not factionKey then factionKey = selection.faction or (keys and keys.faction) end
		return "character", realmKey, charKey, factionKey
	end
	return "character", keys and keys.realmKey, keys and keys.charKey, keys and keys.faction
end

local function collectLines(self, scope, realmKey, charKey, factionKey, searchNeedle, limit)
	local results = {}
	if not self.history or not self.keys then self:InitStorage() end

	local filters = self.ui and self.ui.filters or {}
	local defaults = self.defaultFilters or {}
	local function isEnabled(key)
		if not key then return true end
		local v = filters[key]
		if v ~= nil then return v end
		return defaults[key] ~= false
	end

	local function ensureFilter(line)
		if not line.filterKey and line.event and self.EVENT_FILTER_KEY then line.filterKey = self.EVENT_FILTER_KEY[line.event] end
		return line.filterKey
	end

	local maxResults = (limit and limit > 0) and limit or nil

	local function higher(a, b)
		if a.time ~= b.time then return a.time > b.time end
		return (a.id or 0) > (b.id or 0)
	end

	local function getOrderId(line) return line and (line.seq or line.lineID or 0) or 0 end

	local heap = {}
	local function push(entry)
		local idx = #heap + 1
		heap[idx] = entry
		while idx > 1 do
			local parent = math.floor(idx / 2)
			if not higher(entry, heap[parent]) then break end
			heap[idx] = heap[parent]
			idx = parent
		end
		heap[idx] = entry
	end

	local function pop()
		local root = heap[1]
		if not root then return nil end
		local last = heap[#heap]
		heap[#heap] = nil
		if #heap == 0 then return root end

		heap[1] = last
		local i = 1
		local size = #heap
		while true do
			local left = i * 2
			local right = left + 1
			local largest = i

			if left <= size and higher(heap[left], heap[largest]) then largest = left end
			if right <= size and higher(heap[right], heap[largest]) then largest = right end
			if largest == i then break end
			heap[i], heap[largest] = heap[largest], heap[i]
			i = largest
		end
		return root
	end

	local function matches(line)
		ensureFilter(line)
		if not isEnabled(line.filterKey) then return false end
		return matchesSearchLower(searchNeedle, line.message, line.sender, line.filterKey)
	end

	local function pullNext(stream)
		while stream.index > 0 do
			local line = getLineAt(stream.bucket, stream.index, stream.count)
			stream.index = stream.index - 1
			if line and matches(line) then return line end
		end
	end

	for _, cd in iterCharacters(scope, realmKey, charKey, factionKey) do
		if cd and cd.channels then
			for _, channelData in pairs(cd.channels) do
				local count = getLineCount(channelData)
				if count > 0 then
					local stream = { bucket = channelData, count = count, index = count }
					local line = pullNext(stream)
					if line then push({
						line = line,
						stream = stream,
						time = line.time or 0,
						id = getOrderId(line),
					}) end
				end
			end
		end
	end

	while #heap > 0 do
		local entry = pop()
		if not entry then break end
		results[#results + 1] = entry.line
		if maxResults and #results >= maxResults then break end

		local nextLine = pullNext(entry.stream)
		if nextLine then push({
			line = nextLine,
			stream = entry.stream,
			time = nextLine.time or 0,
			id = getOrderId(nextLine),
		}) end
	end

	local n = #results
	for i = 1, math.floor(n / 2) do
		results[i], results[n - i + 1] = results[n - i + 1], results[i]
	end

	return results
end

local function setLabelText(label, text)
	if label then label:SetText(text) end
end

function ChannelHistory:EnsureSelection()
	self.ui = self.ui or {}
	if self.ui.selection then return end
	if not self.history or not self.keys then self:InitStorage() end
	local function buildCharSelectionKey(keys) return string.format("char:%s:%s:%s", keys.realmKey or "", keys.faction or "", keys.charKey or "") end
	local stored = (self.history and self.history._selection) or (addon.db and addon.db.chatHistorySelection)
	if stored and type(stored) == "table" and stored.type then
		if stored.type == "character" and type(stored.key) == "string" and not stored.key:match("^char:[^:]+:[^:]+:") then
			stored.key = buildCharSelectionKey(self.keys or {})
			stored.realmKey = (self.keys and self.keys.realmKey) or stored.realmKey
			stored.factionKey = (self.keys and self.keys.faction) or stored.factionKey
			stored.charKey = (self.keys and self.keys.charKey) or stored.charKey
		end
		self:SetSelection(stored)
		return
	end
	self:SetSelection({
		type = "character",
		key = buildCharSelectionKey(self.keys or {}),
		factionKey = self.keys and self.keys.faction,
		realmKey = self.keys and self.keys.realmKey,
		charKey = self.keys and self.keys.charKey,
	})
end

-- UI helpers: left tree
function ChannelHistory:BuildLeftEntries(filterText)
	if not self.history or not self.keys then self:InitStorage() end
	local entries = {}
	self.ui = self.ui or {}
	self.ui.leftState = self.ui.leftState or { realms = {}, factions = {}, accountExpanded = true }
	local state = self.ui.leftState
	state.realms = state.realms or {}
	state.factions = state.factions or {}
	local playerCharKey = string.format("char:%s:%s:%s", self.keys.realmKey or "", self.keys.faction or "", self.keys.charKey or "")
	self:EnsureSelection()
	filterText = filterText and filterText:lower()

	local function matchesFilter(name, realm)
		if not filterText or filterText == "" then return true end
		if name and name:lower():find(filterText, 1, true) then return true end
		if realm and realm:lower():find(filterText, 1, true) then return true end
		return false
	end

	-- Account node
	table.insert(entries, { kind = "header", label = ALL, level = 0, key = "account", expanded = state.accountExpanded ~= false })

	-- Build realm -> faction -> chars map
	local history = self.history or {}
	local realms = {}
	for fKey, factionBucket in pairs(history) do
		if type(factionBucket) == "table" and isVisibleKey(fKey) then
			for realmKey, realmData in pairs(factionBucket) do
				if type(realmData) == "table" and isVisibleKey(realmKey) then
					local entry = realms[realmKey]
					if not entry then
						entry = { label = realmData.realmName or realmKey, factions = {} }
						realms[realmKey] = entry
					end
					entry.factions[fKey] = realmData
				end
			end
		end
	end

	local realmKeys = {}
	for realmKey in pairs(realms) do
		table.insert(realmKeys, realmKey)
	end
	table.sort(realmKeys)

	for _, realmKey in ipairs(realmKeys) do
		local realmEntry = realms[realmKey]
		local realmLabel = realmEntry.label or realmKey
		local realmNode = {
			kind = "realm",
			label = realmLabel,
			level = 1,
			key = string.format("realm:%s", realmKey),
			expanded = state.realms[realmKey] ~= false,
			realmKey = realmKey,
		}
		table.insert(entries, realmNode)

		if realmNode.expanded then
			local factionKeys = {}
			for fKey in pairs(realmEntry.factions) do
				table.insert(factionKeys, fKey)
			end
			table.sort(factionKeys)
			state.factions[realmKey] = state.factions[realmKey] or {}

			for _, fKey in ipairs(factionKeys) do
				local realmData = realmEntry.factions[fKey]
				local factionNode = {
					kind = "faction",
					label = fKey,
					level = 2,
					key = string.format("faction:%s:%s", realmKey, fKey),
					expanded = state.factions[realmKey][fKey] ~= false,
					realmKey = realmKey,
					factionKey = fKey,
				}
				table.insert(entries, factionNode)

				if factionNode.expanded and realmData and realmData.characters then
					local charKeys = {}
					for charKey in pairs(realmData.characters) do
						table.insert(charKeys, charKey)
					end
					table.sort(charKeys)
					for _, charKey in ipairs(charKeys) do
						local charData = realmData.characters[charKey]
						if charData and matchesFilter(charData.name, realmLabel) then
							table.insert(entries, {
								kind = "character",
								label = charData.name or charKey,
								level = 3,
								key = string.format("char:%s:%s:%s", realmKey, fKey, charKey),
								realm = realmLabel,
								factionKey = fKey,
								realmKey = realmKey,
								classFile = charData.classFile,
								className = charData.className,
								charKey = charKey,
							})
						end
					end
				end
			end
		end
	end

	self.ui = self.ui or {}
	self.ui.leftEntries = entries
	return entries
end

local function handleLeftClick(btn, button)
	if button ~= "LeftButton" then return end
	local data = btn.entry
	if not data then return end
	local selfRef = ChannelHistory
	if data.kind == "character" then
		selfRef:SetSelection({
			type = "character",
			key = data.key,
			faction = data.factionKey,
			factionKey = data.factionKey,
			realmKey = data.realmKey,
			charKey = data.charKey,
		})
		selfRef:RefreshLeftList()
		selfRef:RequestLogRefresh()
	elseif data.kind == "realm" then
		local realmKey = data.realmKey or data.key:match("^realm:(.+)$") or data.key
		selfRef:SetSelection({ type = "realm", key = data.key, realm = realmKey, realmKey = realmKey })
		selfRef:RefreshLeftList()
		selfRef:RequestLogRefresh()
	elseif data.kind == "faction" then
		selfRef:SetSelection({
			type = "faction",
			key = data.key,
			faction = data.factionKey,
			factionKey = data.factionKey,
			realmKey = data.realmKey,
		})
		selfRef:RefreshLeftList()
		selfRef:RequestLogRefresh()
	elseif data.kind == "header" then
		selfRef:SetSelection({ type = "header", key = data.key })
		selfRef:RefreshLeftList()
		selfRef:RequestLogRefresh()
	end
end

local function handleToggleClick(toggleFrame, button)
	if button ~= "LeftButton" then return end
	local btn = toggleFrame:GetParent()
	local data = btn and btn.entry
	if not data then return end
	local selfRef = ChannelHistory
	if data.kind == "realm" then
		local realmKey = data.realmKey or data.key:match("^realm:(.+)$") or data.key
		local newState = not data.expanded
		selfRef.ui.leftState.realms[realmKey] = newState
	elseif data.kind == "faction" then
		local realmKey = data.realmKey or selfRef.keys.realmKey
		selfRef.ui.leftState.factions[realmKey] = selfRef.ui.leftState.factions[realmKey] or {}
		local fKey = data.factionKey or (data.key and data.key:match("^faction:[^:]+:(.+)$")) or data.key
		local newState = not data.expanded
		selfRef.ui.leftState.factions[realmKey][fKey] = newState
	else
		return
	end
	selfRef:RefreshLeftList()
end

local function handleToggleEnter(toggleFrame)
	local btn = toggleFrame:GetParent()
	if btn and btn.hl then btn.hl:Show() end
end

local function handleToggleLeave(toggleFrame)
	local btn = toggleFrame:GetParent()
	if btn and btn.hl then btn.hl:Hide() end
end

local function ensureLeftButtons(self, count)
	self.ui.leftButtons = self.ui.leftButtons or {}
	local buttons = self.ui.leftButtons
	local content = self.ui.leftContent
	local buttonHeight = 22

	for i = #buttons + 1, count do
		local btn = CreateFrame("Button", nil, content)
		btn:EnableMouse(true)
		btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		btn:SetHeight(buttonHeight)
		btn:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -((i - 1) * buttonHeight))
		btn:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, -((i - 1) * buttonHeight))

		btn.bg = btn:CreateTexture(nil, "BACKGROUND")
		btn.bg:SetAllPoints()
		btn.bg:SetTexture("Interface\\AuctionFrame\\AuctionHouse-UI-Row-Select")
		btn.bg:SetTexCoord(0, 1, 0, 1)
		btn.bg:SetVertexColor(1, 1, 1, 0)

		btn.glow = btn:CreateTexture(nil, "OVERLAY")
		btn.glow:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
		btn.glow:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 1)
		btn.glow:SetWidth(4)
		btn.glow:SetColorTexture(1, 0.82, 0, 0.7)
		btn.glow:Hide()

		btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
		btn.hl:SetAllPoints()
		btn.hl:SetColorTexture(1, 1, 1, 0.08)
		btn.hl:Hide()

		btn.icon = btn:CreateTexture(nil, "ARTWORK")
		btn.icon:SetSize(16, 16)
		btn.icon:SetPoint("LEFT", btn, "LEFT", 4, 0)

		btn.toggle = btn:CreateTexture(nil, "ARTWORK")
		btn.toggle:SetSize(12, 12)
		btn.toggle:SetPoint("LEFT", btn, "LEFT", 2, 0)
		btn.toggle:Hide()
		btn.toggleFrame = CreateFrame("Button", nil, btn)
		btn.toggleFrame:SetSize(18, 18)
		btn.toggleFrame:SetPoint("LEFT", btn, "LEFT", 0, 0)
		btn.toggleFrame:Hide()

		btn.nameText = btn:CreateFontString(nil, "OVERLAY")
		btn.nameText:SetFontObject("GameFontNormal")
		btn.nameText:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)

		btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

		btn:SetScript("OnEnter", function(selfBtn)
			if selfBtn.hl then selfBtn.hl:Show() end
		end)
		btn:SetScript("OnLeave", function(selfBtn)
			if selfBtn.hl then selfBtn.hl:Hide() end
		end)
		btn:SetScript("OnMouseUp", function(selfBtn, button)
			if button == "RightButton" then
				if ChannelHistory.ShowCharacterContextMenu then ChannelHistory:ShowCharacterContextMenu(selfBtn.entry) end
				return
			end
			handleLeftClick(selfBtn, button)
		end)
		btn.toggleFrame:SetScript("OnMouseUp", handleToggleClick)
		btn.toggleFrame:SetScript("OnEnter", handleToggleEnter)
		btn.toggleFrame:SetScript("OnLeave", handleToggleLeave)

		buttons[i] = btn
	end

	return buttonHeight, buttons
end

function ChannelHistory:RefreshLeftList()
	if not self.debugFrame or not self.ui or not self.ui.leftContent then return end
	local filter = self.ui.leftSearch and self.ui.leftSearch:GetText()
	local entries = self:BuildLeftEntries(filter)
	local buttonHeight, buttons = ensureLeftButtons(self, #entries)
	if self.ui.leftScroll and self.ui.leftContent then
		local width = math.max(1, (self.ui.leftScroll:GetWidth() or 0) - 16)
		self.ui.leftContent:SetWidth(width)
	end

	for i, entry in ipairs(entries) do
		local btn = buttons[i]
		btn.entry = entry
		btn:Show()

		local sel = self.ui.selection or { type = "character", key = self.keys.charKey and ("char:" .. self.keys.charKey) or nil }
		local selected = sel and sel.key == entry.key and sel.type == entry.kind
		btn.bg:SetVertexColor(1, 1, 1, selected and 0.35 or 0)
		if btn.glow then btn.glow:SetShown(selected) end
		btn.icon:Hide()
		btn.toggle:Hide()
		btn.toggleFrame:Hide()

		local indent = (entry.level or 0) * 14
		local baseX = 10 + indent

		btn.icon:ClearAllPoints()
		btn.nameText:ClearAllPoints()
		btn.toggleFrame:ClearAllPoints()
		btn.toggle:ClearAllPoints()
		btn.toggleFrame:SetPoint("LEFT", btn, "LEFT", baseX - 10, 0)
		btn.toggle:SetPoint("CENTER", btn.toggleFrame, "CENTER", 0, 0)

		if entry.kind == "header" then
			btn.toggle:Hide()
			btn.toggleFrame:Hide()
			btn.icon:Hide()
			btn.nameText:SetPoint("LEFT", btn, "LEFT", baseX, 0)
			setLabelText(btn.nameText, entry.label)
			btn.nameText:SetTextColor(1, 0.9, 0.6)
		elseif entry.kind == "faction" then
			btn.toggle:Show()
			btn.toggle:SetAtlas(entry.expanded and "NPE_ArrowDown" or "NPE_ArrowRight")
			btn.toggleFrame:Show()
			btn.icon:SetTexture("Interface\\FriendsFrame\\PlusManz-Highlight")
			btn.icon:SetPoint("LEFT", btn, "LEFT", baseX - 10, 0)
			btn.icon:Show()
			btn.nameText:SetPoint("LEFT", btn.icon, "RIGHT", 4, 0)
			setLabelText(btn.nameText, entry.label or entry.key)
			btn.nameText:SetTextColor(0.9, 0.9, 0.9)
		elseif entry.kind == "realm" then
			btn.toggle:Show()
			btn.toggle:SetAtlas(entry.expanded and "NPE_ArrowDown" or "NPE_ArrowRight")
			btn.toggleFrame:Show()
			btn.icon:SetTexture("Interface\\FriendsFrame\\PlusManz-Highlight")
			btn.icon:SetPoint("LEFT", btn, "LEFT", baseX - 10, 0)
			btn.icon:Show()
			btn.nameText:SetPoint("LEFT", btn.icon, "RIGHT", 4, 0)
			setLabelText(btn.nameText, entry.label or entry.key)
			btn.nameText:SetTextColor(0.85, 0.85, 0.85)
		elseif entry.kind == "character" then
			local classFile = entry.classFile or (entry.charKey == (self.keys.charKey or "") and select(2, UnitClass("player")))
			setClassIcon(btn, classFile)
			btn.icon:SetPoint("LEFT", btn, "LEFT", baseX + 12, 0)
			btn.nameText:SetPoint("LEFT", btn.icon, "RIGHT", 8, 0)
			setLabelText(btn.nameText, entry.label or entry.charKey or "")
			local color = getClassStyle(classFile)
			if color then
				btn.nameText:SetTextColor(color.r, color.g, color.b)
			else
				btn.nameText:SetTextColor(0.9, 0.9, 0.9)
			end
		else
			setLabelText(btn.nameText, entry.label or entry.key)
		end
	end

	for j = #entries + 1, #buttons do
		buttons[j]:Hide()
	end

	local totalHeight = #entries * buttonHeight
	self.ui.leftContent:SetHeight(totalHeight)
	if self.ui.leftScroll then self.ui.leftScroll:UpdateScrollChildRect() end
	if self.ui.leftScroll and self.ui.leftScrollThin then self:UpdateThinScrollFrameBar(self.ui.leftScrollThin, self.ui.leftScroll) end
end

function ChannelHistory:OnEvent(event, ...)
	if not self.enabled then return end
	if not self.loggedIn then return end
	if not self.events or not self.events[event] then return end
	self:Store(event, ...)
end

ChannelHistory.frame:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		ChannelHistory.loggedIn = true
		ChannelHistory:InitStorage()
		ChannelHistory:SetMaxLines(addon.db and addon.db["chatChannelHistoryMaxLines"])
		ChannelHistory:SetUILineLimit(addon.db and addon.db.chatChannelHistoryMaxViewLines)
		if ChannelHistory.enabled then
			ChannelHistory:RegisterEvents()
			ChannelHistory:CreateDebugFrame()
			ChannelHistory:RefreshLogView()
		end
		return
	end
	ChannelHistory:OnEvent(event, ...)
end)

function ChannelHistory:RegisterEvents()
	if not self.frame then return end
	self.loggedIn = self.loggedIn or (IsLoggedIn and IsLoggedIn()) or false
	self.frame:UnregisterAllEvents()
	self.frame:RegisterEvent("PLAYER_LOGIN")
	if not self.loggedIn then return end
	self.events = buildEventSet()
	for event in pairs(self.events or {}) do
		self.frame:RegisterEvent(event)
	end
end

function ChannelHistory:UpdateLoggingFilter(filterKey)
	if not filterKey then return end
	self.events = self.events or buildEventSet()
	self.loggedIn = self.loggedIn or (IsLoggedIn and IsLoggedIn()) or false
	local shouldEnable = isLoggingEnabled(filterKey)

	local function apply(event)
		if not event or IGNORED_EVENTS[event] then return end
		local hasEvent = self.events and self.events[event]
		if shouldEnable then
			if not hasEvent then
				self.events[event] = true
				if self.enabled and self.loggedIn and self.frame then self.frame:RegisterEvent(event) end
			end
		else
			if hasEvent then
				self.events[event] = nil
				if self.frame then self.frame:UnregisterEvent(event) end
			end
		end
	end

	for event, key in pairs(self.EVENT_FILTER_KEY or {}) do
		if key == filterKey then apply(event) end
	end
	for _, event in ipairs(ADDITIONAL_EVENTS) do
		local key = self.EVENT_FILTER_KEY and self.EVENT_FILTER_KEY[event]
		if key == filterKey then apply(event) end
	end
end

function ChannelHistory:SetEnabled(enabled)
	self.enabled = enabled and true or false
	if addon.db then addon.db.enableChatHistory = self.enabled end
	self.loggedIn = self.loggedIn or (IsLoggedIn and IsLoggedIn()) or false
	self:LoadFiltersFromDB()
	self:SetUILineLimit(addon.db and addon.db.chatChannelHistoryMaxViewLines or self.uiMaxLines)
	self:UpdateLogFontSize(addon.db and addon.db.chatChannelHistoryFontSize or 12)
	self:EnsureToggleButton()
	if self.enabled then
		if self.loggedIn then
			self:InitStorage()
			self.events = buildEventSet()
			self:SetMaxLines(addon.db and addon.db["chatChannelHistoryMaxLines"])
			self:SetUILineLimit(addon.db and addon.db.chatChannelHistoryMaxViewLines or self.uiMaxLines)
		end
		self:RegisterEvents()
		if self.loggedIn then
			self:CreateDebugFrame()
			if self.ui and self.ui.leftSearch then
				self.ui.leftSearch:SetText("")
				SearchBoxTemplate_OnTextChanged(self.ui.leftSearch)
			end
			self:RefreshLeftList()
			self:RefreshLogView()
		end
	else
		if self.frame then self.frame:UnregisterAllEvents() end
		if self.debugFrame then self.debugFrame:Hide() end
		if self.toggleButton then self.toggleButton:Hide() end
	end
end

function ChannelHistory:ToggleWindow()
	if not self.enabled then return end
	if not self.debugFrame then self:CreateDebugFrame() end
	if not self.debugFrame then return end
	if self.debugFrame:IsShown() then
		self.debugFrame:Hide()
	else
		self.debugFrame:Show()
		self:RefreshLogView()
	end
end

-- Simple debug frame (no AceGUI) to iterate on layout
local WINDOW_BACKDROP = {
	bgFile = nil,
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true,
	tileSize = 32,
	edgeSize = 16,
	insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

local PANEL_BACKDROP = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true,
	tileSize = 32,
	edgeSize = 16,
	insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

local function applyPanelBackdrop(panel)
	panel:SetBackdrop(PANEL_BACKDROP)
	panel:SetBackdropColor(0, 0, 0, 0.55)
	panel:SetBackdropBorderColor(0.75, 0.65, 0.4, 0.95)
end

local function applyInsetBorder(frame, offset)
	if not frame then return end
	offset = offset or 10

	-- Clean up legacy single-texture border
	if frame.eqolInsetBorder then
		frame.eqolInsetBorder:Hide()
		frame.eqolInsetBorder = nil
	end

	local layer, subLevel = "BORDER", 2
	local path = "Interface\\AddOns\\EnhanceQoL\\Assets\\border_round_"
	local cornerSize = 36
	local edgeSize = 36

	frame.eqolInsetParts = frame.eqolInsetParts or {}
	local parts = frame.eqolInsetParts

	local function tex(name)
		if not parts[name] then parts[name] = frame:CreateTexture(nil, layer, nil, subLevel) end
		local t = parts[name]
		t:SetAlpha(0.7)
		t:SetTexture(path .. name .. ".tga")
		t:SetDrawLayer(layer, subLevel)
		return t
	end

	local tl = tex("tl")
	tl:SetSize(cornerSize, cornerSize)
	tl:ClearAllPoints()
	tl:SetPoint("TOPLEFT", frame, "TOPLEFT", offset, -offset)

	local tr = tex("tr")
	tr:SetSize(cornerSize, cornerSize)
	tr:ClearAllPoints()
	tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -offset, -offset)

	local bl = tex("bl")
	bl:SetSize(cornerSize, cornerSize)
	bl:ClearAllPoints()
	bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", offset, offset)

	local br = tex("br")
	br:SetSize(cornerSize, cornerSize)
	br:ClearAllPoints()
	br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -offset, offset)

	local top = tex("t")
	top:ClearAllPoints()
	top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
	top:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0)
	top:SetHeight(edgeSize)
	top:SetHorizTile(true)

	local bottom = tex("b")
	bottom:ClearAllPoints()
	bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT", 0, 0)
	bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
	bottom:SetHeight(edgeSize)
	bottom:SetHorizTile(true)

	local left = tex("l")
	left:ClearAllPoints()
	left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT", 0, 0)
	left:SetWidth(edgeSize)
	left:SetVertTile(true)

	local right = tex("r")
	right:ClearAllPoints()
	right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0)
	right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
	right:SetWidth(edgeSize)
	right:SetVertTile(true)
end

function ChannelHistory:UpdateToggleButtonPosition()
	if not self.toggleButton then return end
	local anchor = QuickJoinToastButton or UIParent
	local x = (addon.db and addon.db.chatHistoryButtonOffsetX) or 0
	local y = (addon.db and addon.db.chatHistoryButtonOffsetY) or -10
	self.toggleButton:ClearAllPoints()
	self.toggleButton:SetPoint("TOP", anchor, "BOTTOM", x, y)
end

function ChannelHistory:UpdateToggleButtonSize()
	if not self.toggleButton then return end
	-- Square base for the new icon
	local baseW, baseH = 30, 30
	local w, h = baseW, baseH
	self.toggleButton:SetSize(w, h)
	if self.toggleButton.icon then
		local iconSize = baseW
		self.toggleButton.icon:SetSize(iconSize, iconSize)
		self.toggleButton.icon:SetPoint("CENTER", self.toggleButton, "CENTER", 0, -1)
	end
end

function ChannelHistory:EnsureToggleButton()
	if not addon.db or not addon.db.enableChatHistory or addon.db.chatHistoryShowButton == false then
		if self.toggleButton then self.toggleButton:Hide() end
		return
	end
	if not self.toggleButton then
		local btn = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
		btn:SetNormalAtlas("chatframe-button-up")
		btn:SetHighlightAtlas("chatframe-button-up")
		btn:SetPushedAtlas("chatframe-button-up")
		btn.icon = btn:CreateTexture(nil, "OVERLAY", nil, 1)
		btn.icon:SetPoint("CENTER", btn, "CENTER", 0, -1)
		btn.icon:SetSize(32, 32)
		btn.icon:SetAtlas("lorewalking-map-icon")
		btn.icon:SetAlpha(1)
		btn:SetText("")
		btn:SetScript("OnClick", function() self:ToggleWindow() end)
		btn:SetFrameStrata("MEDIUM")
		self.toggleButton = btn
	end
	self:UpdateToggleButtonSize()
	self.toggleButton:Show()
	self:UpdateToggleButtonPosition()
end

function ChannelHistory:UpdateToggleButtonStrata()
	if not self.toggleButton then return end
	self.toggleButton:SetFrameStrata(self.frameStrata or "MEDIUM")
	self.toggleButton:SetFrameLevel((self.frameLevel or 600) + 10)
end

function ChannelHistory:ShowCharacterContextMenu(entry)
	if not MU or not MU.CreateContextMenu then return end
	if not entry or entry.kind ~= "character" then return end
	local name = entry.label or entry.charKey or "Character"
	local charKey = entry.charKey
	local realmKey = entry.realmKey or (entry.key and entry.key:match("^char:([^:]+):[^:]+:.+$"))
	local factionKey = entry.factionKey or (entry.key and entry.key:match("^char:[^:]+:([^:]+):.+$"))
	ensureClearPopups()
	MU.CreateContextMenu(UIParent, function(_, root)
		root:CreateTitle(name)
		root:CreateButton("Clear history", function() StaticPopup_Show("EQOL_CLEAR_HISTORY_CHAR", name, nil, { faction = factionKey, realm = realmKey, char = charKey }) end)
	end)
end

function ChannelHistory:ShowChannelContextMenu(filterInfo)
	if not MU or not MU.CreateContextMenu then return end
	if not filterInfo or not filterInfo.key then return end
	local label = filterInfo.label or filterInfo.key
	local clearLabel = (L and L["CH_CLEAR_SCOPE"]) or "Clear history in current scope"
	ensureClearPopups()
	MU.CreateContextMenu(UIParent, function(_, root)
		root:CreateTitle(label)
		root:CreateButton(clearLabel, function() StaticPopup_Show("EQOL_CLEAR_HISTORY_CHANNEL", label, nil, { filterKey = filterInfo.key }) end)
	end)
end

function ChannelHistory:SaveFramePosition()
	if not addon.db or not self.debugFrame then return end
	local point, _, relativePoint, xOfs, yOfs = self.debugFrame:GetPoint(1)
	addon.db.chatHistoryFramePos = {
		point = point or "CENTER",
		relativePoint = relativePoint or "CENTER",
		x = xOfs or 0,
		y = yOfs or 0,
	}
end

function ChannelHistory:RestoreFramePosition()
	if not self.debugFrame then return end
	local pos = addon.db and addon.db.chatHistoryFramePos
	self.debugFrame:ClearAllPoints()
	if pos and pos.point and pos.relativePoint then
		self.debugFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x or 0, pos.y or 0)
	else
		self.debugFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
end

-- Thin scrollbar helpers for the log frame
function ChannelHistory:CreateThinScrollbar(parent, logFrame, xOffset)
	local sb = CreateFrame("Slider", nil, parent)
	sb:SetOrientation("VERTICAL")
	sb:SetWidth(10)
	sb:SetPoint("TOPLEFT", logFrame, "TOPRIGHT", xOffset or 6, 0)
	sb:SetPoint("BOTTOMLEFT", logFrame, "BOTTOMRIGHT", xOffset or 6, 0)
	sb:SetValueStep(1)
	sb:SetObeyStepOnDrag(true)

	sb.track = sb:CreateTexture(nil, "BACKGROUND")
	sb.track:SetPoint("TOP", sb, "TOP", 0, -2)
	sb.track:SetPoint("BOTTOM", sb, "BOTTOM", 0, 2)
	sb.track:SetWidth(1)
	sb.track:SetColorTexture(1, 1, 1, 0.22)

	sb.channel = sb:CreateTexture(nil, "BACKGROUND", nil, -1)
	sb.channel:SetPoint("TOP", sb, "TOP", 0, 0)
	sb.channel:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)
	sb.channel:SetWidth(6)
	sb.channel:SetColorTexture(0, 0, 0, 0.28)

	local thumb = sb:CreateTexture(nil, "ARTWORK")
	thumb:SetSize(6, 22)
	thumb:SetColorTexture(1, 1, 1, 0.45)
	sb:SetThumbTexture(thumb)
	sb.thumb = thumb

	sb:EnableMouse(true)
	sb:SetScript("OnEnter", function()
		sb.track:SetColorTexture(1, 1, 1, 0.32)
		sb.thumb:SetColorTexture(1, 1, 1, 0.65)
	end)
	sb:SetScript("OnLeave", function()
		sb.track:SetColorTexture(1, 1, 1, 0.22)
		sb.thumb:SetColorTexture(1, 1, 1, 0.45)
	end)

	sb._suppress = false

	local function setOffsetSafe(offset)
		offset = math.max(0, math.floor((offset or 0) + 0.5))
		if logFrame.SetScrollOffset then
			logFrame:SetScrollOffset(offset)
			return
		end

		local cur = logFrame:GetScrollOffset() or 0
		local delta = offset - cur
		if delta > 0 then
			for _ = 1, delta do
				logFrame:ScrollUp()
			end
		elseif delta < 0 then
			for _ = 1, -delta do
				logFrame:ScrollDown()
			end
		end
	end

	sb:SetScript("OnValueChanged", function(sl, value)
		if sl._suppress then return end
		local minVal, maxVal = sl:GetMinMaxValues()
		value = math.max(minVal or 0, math.min(maxVal or 0, math.floor((value or 0) + 0.5)))

		local desiredOffset = (maxVal or 0) - value
		setOffsetSafe(desiredOffset)

		self:UpdateThinScrollbar(sl, logFrame)
	end)

	logFrame:SetScript("OnMouseWheel", function(_, delta)
		local minVal, maxVal = sb:GetMinMaxValues()
		local cur = sb:GetValue() or maxVal or 0
		local newVal = cur - delta
		if minVal and newVal < minVal then newVal = minVal end
		if maxVal and newVal > maxVal then newVal = maxVal end
		sb:SetValue(newVal)
	end)

	return sb
end

function ChannelHistory:UpdateThinScrollbar(sb, logFrame)
	if not sb or not logFrame then return end

	local num = logFrame:GetNumMessages() or 0
	local maxVal = math.max(0, num - 1)
	local offset = logFrame:GetScrollOffset() or 0
	local sliderValue = maxVal - offset

	sb._suppress = true
	sb:SetMinMaxValues(0, maxVal)
	sb:SetValue(sliderValue)
	sb._suppress = false

	local hasScroll = maxVal > 0
	if sb.thumb then sb.thumb:SetAlpha(hasScroll and 0.28 or 0) end
	if sb.track then sb.track:SetAlpha(hasScroll and 0.12 or 0) end
	if sb.channel then sb.channel:SetAlpha(hasScroll and 0.18 or 0) end
end

function ChannelHistory:CreateThinScrollFrameBar(scrollFrame, xOffset)
	if not scrollFrame then return nil end
	local parent = scrollFrame:GetParent() or scrollFrame
	local sb = CreateFrame("Slider", nil, parent)
	sb:SetOrientation("VERTICAL")
	sb:SetWidth(10)
	sb:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", xOffset or 4, 0)
	sb:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", xOffset or 4, 0)
	sb:SetValueStep(1)
	sb:SetObeyStepOnDrag(true)

	sb.track = sb:CreateTexture(nil, "BACKGROUND")
	sb.track:SetPoint("TOP", sb, "TOP", 0, -2)
	sb.track:SetPoint("BOTTOM", sb, "BOTTOM", 0, 2)
	sb.track:SetWidth(1)
	sb.track:SetColorTexture(1, 1, 1, 0.22)

	sb.channel = sb:CreateTexture(nil, "BACKGROUND", nil, -1)
	sb.channel:SetPoint("TOP", sb, "TOP", 0, 0)
	sb.channel:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)
	sb.channel:SetWidth(6)
	sb.channel:SetColorTexture(0, 0, 0, 0.28)

	local thumb = sb:CreateTexture(nil, "ARTWORK")
	thumb:SetSize(6, 22)
	thumb:SetColorTexture(1, 1, 1, 0.45)
	sb:SetThumbTexture(thumb)
	sb.thumb = thumb

	sb:EnableMouse(true)
	sb:SetScript("OnEnter", function()
		sb.track:SetColorTexture(1, 1, 1, 0.32)
		sb.thumb:SetColorTexture(1, 1, 1, 0.65)
	end)
	sb:SetScript("OnLeave", function()
		sb.track:SetColorTexture(1, 1, 1, 0.22)
		sb.thumb:SetColorTexture(1, 1, 1, 0.45)
	end)

	sb._suppress = false

	local function applyVisibility(range)
		local hasScroll = range and range > 0
		if sb.thumb then sb.thumb:SetAlpha(hasScroll and 0.45 or 0) end
		if sb.track then sb.track:SetAlpha(hasScroll and 0.22 or 0) end
		if sb.channel then sb.channel:SetAlpha(hasScroll and 0.28 or 0) end
	end

	local function updateRange(_, _, yRange)
		local vrange = yRange
		if vrange == nil and scrollFrame.GetVerticalScrollRange then vrange = scrollFrame:GetVerticalScrollRange() end
		local maxRange = math.max(0, vrange or 0)
		sb._suppress = true
		sb:SetMinMaxValues(0, maxRange)
		local cur = sb:GetValue() or 0
		if cur > maxRange then sb:SetValue(maxRange) end
		sb._suppress = false
		applyVisibility(maxRange)
	end

	scrollFrame:SetScript("OnScrollRangeChanged", updateRange)

	sb:SetScript("OnValueChanged", function(sl, value)
		if sl._suppress then return end
		local minVal, maxVal = sl:GetMinMaxValues()
		value = math.max(minVal or 0, math.min(maxVal or 0, math.floor((value or 0) + 0.5)))
		sl._suppress = true
		sl:SetValue(value)
		sl._suppress = false
		scrollFrame:SetVerticalScroll(value)
	end)

	scrollFrame:SetScript("OnVerticalScroll", function(_, offset)
		sb._suppress = true
		sb:SetValue(offset or 0)
		sb._suppress = false
	end)

	scrollFrame:EnableMouseWheel(true)
	scrollFrame:SetScript("OnMouseWheel", function(_, delta)
		local minVal, maxVal = sb:GetMinMaxValues()
		local cur = sb:GetValue() or 0
		local step = 30
		local newVal = cur - (delta * step)
		if minVal and newVal < minVal then newVal = minVal end
		if maxVal and newVal > maxVal then newVal = maxVal end
		sb:SetValue(newVal)
	end)

	local initialRange = scrollFrame.GetVerticalScrollRange and scrollFrame:GetVerticalScrollRange() or 0
	updateRange(nil, nil, initialRange)

	return sb
end

function ChannelHistory:UpdateThinScrollFrameBar(sb, scrollFrame)
	if not sb or not scrollFrame then return end
	local yRange = scrollFrame.GetVerticalScrollRange and scrollFrame:GetVerticalScrollRange() or 0
	local maxRange = math.max(0, yRange or 0)
	local offset = scrollFrame:GetVerticalScroll() or 0
	sb._suppress = true
	sb:SetMinMaxValues(0, maxRange)
	sb:SetValue(math.min(offset, maxRange))
	sb._suppress = false
	local hasScroll = maxRange > 0
	if sb.thumb then sb.thumb:SetAlpha(hasScroll and 0.45 or 0) end
	if sb.track then sb.track:SetAlpha(hasScroll and 0.22 or 0) end
	if sb.channel then sb.channel:SetAlpha(hasScroll and 0.28 or 0) end
end

local function ensureFilterRowPool(self)
	self.ui.filterRowPool = self.ui.filterRowPool or {}
	return self.ui.filterRowPool
end

local function acquireFilterRow(self, index, parent, checkHeight, handleFilterClick)
	local pool = ensureFilterRowPool(self)
	local row = pool[index]
	if row then
		row:SetParent(parent)
		row:Show()
		return row
	end

	row = CreateFrame("Button", nil, parent)
	row:SetHeight(checkHeight)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetTexture("Interface\\AuctionFrame\\AuctionHouse-UI-Row-Select")
	row.bg:SetTexCoord(0, 1, 0, 1)
	row.bg:SetVertexColor(1, 1, 1, 0)

	row.hl = row:CreateTexture(nil, "HIGHLIGHT")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(1, 1, 1, 0.08)
	row.hl:Hide()

	row.cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.cb:SetSize(checkHeight, checkHeight)
	row.cb:SetPoint("LEFT", row, "LEFT", 2, 0)
	row.cb:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.text:SetPoint("LEFT", row.cb, "RIGHT", 6, 0)
	row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	row.text:SetJustifyH("LEFT")

	local function showHL()
		if row.hl then row.hl:Show() end
	end
	local function hideHL()
		if row.hl then row.hl:Hide() end
	end

	row:SetScript("OnEnter", showHL)
	row:SetScript("OnLeave", hideHL)
	row:SetScript("OnMouseUp", function(r, btn)
		if not r.info then return end
		handleFilterClick(r.info, btn)
	end)

	row.cb:SetScript("OnClick", function(cb, btn)
		local r = cb:GetParent()
		if not r or not r.info then return end
		handleFilterClick(r.info, btn, cb:GetChecked())
	end)

	pool[index] = row
	return row
end

local function createSearchBox(parent, placeholder)
	local box = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
	box:SetHeight(22)
	box:SetAutoFocus(false)
	box:SetMaxLetters(128)
	if box.Instructions and placeholder then box.Instructions:SetText(placeholder) end
	return box
end

function ChannelHistory:CreateFilterUI()
	if not self.debugFrame or not self.middle then return end
	self.ui.filters = self.ui.filters or {}
	local container = self.ui.filterContainer
	if not container then
		container = CreateFrame("Frame", nil, self.middle)
		self.ui.filterContainer = container
	end

	container:ClearAllPoints()
	container:SetPoint("TOPLEFT", self.middle, "TOPLEFT", 12, -36)
	container:SetPoint("TOPRIGHT", self.middle, "TOPRIGHT", -12, -36)
	container:SetPoint("BOTTOM", self.middle, "BOTTOM", 0, 8)

	ChannelHistory.filterOptions = buildFilterOptions()

	local filters = ChannelHistory.filterOptions
	local filterByKey = {}
	for _, info in ipairs(filters) do
		filterByKey[info.key] = info
	end

	local function getFilterColor(key)
		local color = getChatColor and getChatColor(key)
		if color and color.r and color.g and color.b then return color end
		return nil
	end

	local function setFilterState(key, state)
		self.ui.filters = self.ui.filters or {}
		self.ui.filters[key] = state and true or false
		if addon.db then
			addon.db.chatChannelFilters = addon.db.chatChannelFilters or {}
			addon.db.chatChannelFilters[key] = self.ui.filters[key]
		end
		if self.ui.filterChecksByKey and self.ui.filterChecksByKey[key] then self.ui.filterChecksByKey[key]:SetChecked(self.ui.filters[key]) end
	end

	local function setExclusive(key)
		for k in pairs(filterByKey) do
			setFilterState(k, k == key)
		end
	end

	local function handleFilterClick(info, buttonName, targetState)
		if not info or not info.key then return end
		if buttonName == "RightButton" then
			if self.ShowChannelContextMenu then self:ShowChannelContextMenu(info) end
			setFilterState(info.key, self:IsFilterEnabled(info.key))
			return
		end

		if IsShiftKeyDown() then
			setExclusive(info.key)
		else
			local newState = targetState
			if newState == nil then newState = not self:IsFilterEnabled(info.key) end
			setFilterState(info.key, newState and true or false)
		end
		self:RequestLogRefresh()
	end

	local topBar = self.ui.filterTopBar
	if not topBar then
		topBar = CreateFrame("Frame", nil, container)
		topBar:SetHeight(26)
		topBar:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
		topBar:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
		local function makeBtn(text, handler)
			local btn = CreateFrame("Button", nil, topBar, "UIPanelButtonTemplate")
			btn:SetHeight(22)
			btn:SetText(text)
			btn:SetScript("OnClick", handler)
			btn:SetNormalTexture("Interface\\AddOns\\EnhanceQoL\\Assets\\buttonbackground.tga")
			btn:SetPushedTexture("Interface\\AddOns\\EnhanceQoL\\Assets\\buttonbackground.tga")
			btn:SetHighlightTexture("Interface\\AddOns\\EnhanceQoL\\Assets\\buttonbackground.tga")
			local hl = btn:GetHighlightTexture()
			if hl then hl:SetBlendMode("ADD") end
			return btn
		end
		local function setAll(state)
			for _, info in ipairs(filters) do
				setFilterState(info.key, state)
			end
			self:RequestLogRefresh()
		end
		local function invert()
			for _, info in ipairs(filters) do
				local newVal = not self:IsFilterEnabled(info.key)
				setFilterState(info.key, newVal)
			end
			self:RequestLogRefresh()
		end
		topBar.allBtn = makeBtn(ALL or "All", function() setAll(true) end)
		topBar.noneBtn = makeBtn(NONE or "None", function() setAll(false) end)
		local invertLabel = (L and L["CH_FILTER_INVERT"]) or (_G and _G.INVERT) or "Invert"
		topBar.invertBtn = makeBtn(invertLabel, invert)
		topBar.allBtn:SetPoint("LEFT", topBar, "LEFT", 0, 0)
		topBar.noneBtn:SetPoint("LEFT", topBar.allBtn, "RIGHT", 4, 0)
		topBar.invertBtn:SetPoint("LEFT", topBar.noneBtn, "RIGHT", 4, 0)
		self.ui.filterTopBar = topBar
	end

	local scroll = self.ui.filterScroll
	if not scroll then
		scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", container, "TOPLEFT", 2, -30)
		scroll:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 5, 0)
		local sb = scroll.ScrollBar or scroll.scrollBar
		if sb then
			sb:Hide()
			sb:EnableMouse(false)
		end
		self.ui.filterScroll = scroll
		local content = CreateFrame("Frame", nil, scroll)
		content:SetSize(1, 1)
		scroll:SetScrollChild(content)
		self.ui.filterList = content
		local function UpdateFilterListWidth()
			if not self.ui.filterScroll or not self.ui.filterList then return end

			-- etwas Platz rechts lassen (thin scrollbar / padding)
			local w = math.max(1, (self.ui.filterScroll:GetWidth() or 0) - 16)
			self.ui.filterList:SetWidth(w)
		end

		-- einmal sofort
		UpdateFilterListWidth()

		-- und bei Größenänderungen automatisch nachziehen
		if not self.ui.filterScroll._eqolWidthHooked then
			self.ui.filterScroll._eqolWidthHooked = true
			self.ui.filterScroll:HookScript("OnSizeChanged", UpdateFilterListWidth)
			self.ui.filterScroll:HookScript("OnShow", UpdateFilterListWidth)
		end
		self.ui.filterScrollThin = self:CreateThinScrollFrameBar(scroll, -10)
	end

	local filterGroups = {
		{ title = L["CH_FILTER_CAT_CHAT"] or CHAT or "Chat", keys = { "SAY", "YELL", "WHISPER", "BN_WHISPER", "PARTY", "INSTANCE", "RAID", "GUILD", "OFFICER", "GENERAL" } },
		{ title = L["CH_FILTER_CAT_SYSTEM"] or SYSTEM_MESSAGES or "System", keys = { "LOOT", "MONEY", "CURRENCY", "ACHIEVEMENT", "SYSTEM", "OPENING" } },
		{ title = L["CH_FILTER_CAT_MISC"] or OTHER or "Other", keys = { "MONSTER" } },
	}
	local hideUnlogged = addon.db and addon.db.chatHistoryHideUnlogged
	local loggingEnabled = addon.db and addon.db.chatChannelFiltersEnable or {}

	local checkHeight = 19
	local spacing = 4
	local y = 0
	-- reset collections
	self.ui.filterChecksByKey = {}
	self:LoadFiltersFromDB()
	local pool = ensureFilterRowPool(self)
	for _, row in ipairs(pool) do
		row:Hide()
		row:ClearAllPoints()
		row:SetParent(self.ui.filterList)
	end

	local rowIndex = 0
	for _, group in ipairs(filterGroups) do
		for _, key in ipairs(group.keys) do
			local info = filterByKey[key]
			local isLogged = loggingEnabled and loggingEnabled[key] ~= false
			if info and (not hideUnlogged or isLogged) then
				rowIndex = rowIndex + 1
				local row = acquireFilterRow(self, rowIndex, self.ui.filterList, checkHeight, handleFilterClick)
				row.info = info
				row:SetPoint("TOPLEFT", self.ui.filterList, "TOPLEFT", 0, -y)
				row:SetPoint("TOPRIGHT", self.ui.filterList, "TOPRIGHT", 0, -y)
				row:Show()

				local cb = row.cb
				self.ui.filterChecksByKey[key] = cb
				cb:SetChecked(self:IsFilterEnabled(info.key))
				cb:Show()

				row.text:SetText(info.label or info.key)
				local c = getFilterColor(info.key)
				if c then
					row.text:SetTextColor(c.r or 1, c.g or 1, c.b or 1)
				else
					row.text:SetTextColor(1, 1, 1)
				end

				y = y + checkHeight + spacing
			end
		end
	end

	for i = rowIndex + 1, #pool do
		if pool[i] then pool[i]:Hide() end
	end
	self.ui.filterList:SetHeight(y)
	if self.ui.filterScroll and self.ui.filterScroll.UpdateScrollChildRect then self.ui.filterScroll:UpdateScrollChildRect() end
	if self.ui.filterScrollThin then self:UpdateThinScrollFrameBar(self.ui.filterScrollThin, self.ui.filterScroll) end
	container:Show()
end

function ChannelHistory:EnsureLogFrame()
	if self.ui.logFrame then return end
	local frame = CreateFrame("ScrollingMessageFrame", nil, self.right)
	if self.ui.statusBar then
		frame:SetPoint("TOPLEFT", self.ui.statusBar, "BOTTOMLEFT", 0, -8)
	else
		frame:SetPoint("TOPLEFT", self.right, "TOPLEFT", 10, -62)
	end
	frame:SetPoint("BOTTOMRIGHT", self.right, "BOTTOMRIGHT", -18, 10)

	frame:SetFading(false)
	frame:SetSpacing(1)
	frame:SetHyperlinksEnabled(true)
	frame:EnableMouseWheel(true)

	-- Ensure font is set so AddMessage renders
	self:UpdateLogFontSize(addon.db and addon.db.chatChannelHistoryFontSize or 12, frame)
	frame:SetJustifyH("LEFT")
	frame:SetJustifyV("TOP")
	frame:SetIndentedWordWrap(false)

	local maxLines = self.uiMaxLines or (addon.db and addon.db.chatChannelHistoryMaxViewLines) or 1000
	self.uiMaxLines = maxLines
	frame:SetMaxLines(maxLines)

	frame:SetScript("OnHyperlinkClick", function(_, link, text, button)
		if button == "RightButton" then
			local linkType, payload = link:match("^(%a+):(.+)$")
			if payload and (linkType == "player" or linkType == "BNplayer") then
				local namePart = payload:match("^[^:]+")
				local accountID
				if linkType == "BNplayer" then accountID = tonumber(select(2, strsplit(":", payload))) end
				if namePart and showPlayerMenu(frame, namePart, linkType == "BNplayer", accountID) then return end
			end
		end
		if link and link:match("^url:") then
			local payload = link:match("^url:(.+)$")
			showCopyDialog(payload)
			return
		end
		if SetItemRef then
			local chatFrame = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME or ChatFrame1 or frame
			SetItemRef(link, text, button, chatFrame)
		end
	end)
	frame._urlHooked = true

	-- Thin scrollbar
	local slider = self:CreateThinScrollbar(self.right, frame, -4)
	self.ui.logFrame = frame
	self.ui.logScroll = slider
end

function ChannelHistory:RefreshLogView()
	if not self.history or not self.keys then self:InitStorage() end
	if not self.debugFrame or not self.ui or not self.ui.logFrame then return end
	local scope, realmKey, charKey, factionKey = deriveScope(self.ui.selection, self.keys)
	local needle = self.ui and self.ui.searchNeedleLower
	if needle == nil and self.ui and self.ui.rightSearch then
		needle = (self.ui.rightSearch:GetText() or ""):lower()
		self.ui.searchNeedleLower = needle
	end
	local log = self.ui.logFrame
	local maxUI = (log and log:GetMaxLines()) or self.uiMaxLines or 1000
	local lines = collectLines(self, scope, realmKey, charKey, factionKey, needle, maxUI)

	local scopeLabel = ALL
	if scope == "faction" then
		if factionKey then
			scopeLabel = string.format("%s: %s (%s)", L["IgnoreServer"] or REALM, realmKey or (self.keys and self.keys.realmKey) or "", factionKey)
		else
			scopeLabel = ALL
		end
	elseif scope == "realm" and realmKey then
		scopeLabel = (L["IgnoreServer"] or REALM) .. ": " .. realmKey
	elseif scope == "character" and charKey then
		scopeLabel = CHARACTER .. ": " .. charKey
	end

	if self.ui.statusBar and self.ui.statusBar.text then self:UpdateStatusBar(#lines, maxUI, scopeLabel) end
	log:Clear()
	local lastDate
	for i = 1, #lines do
		local lt = lines[i].time or now()
		local currDate = date("%Y-%m-%d", lt)
		if currDate ~= lastDate then
			log:AddMessage(string.format("|cff777777----- %s -----|r", currDate or ""), 1, 1, 1)
			lastDate = currDate
		end
		local text = formatLine(self, lines[i])
		log:AddMessage(text, 1, 1, 1)
	end
	log:ScrollToBottom()
	if self.ui.logScroll then self:UpdateThinScrollbar(self.ui.logScroll, log) end
end

function ChannelHistory:LayoutDebugFrame(width, height)
	if not self.debugFrame then return end
	local f = self.debugFrame
	width = width or f:GetWidth()
	height = height or f:GetHeight()

	local padding = 18
	local spacing = 18
	local headerOffset = 17
	local leftCollapsed = self.ui and self.ui.leftCollapsed

	local availableWidth = width - (padding * 2) - (spacing * 2)
	local availableHeight = height - padding - headerOffset

	local leftWidth = math.max(220, math.floor(availableWidth * 0.28))
	local midWidth = math.max(190, math.floor(availableWidth * 0.17))
	local rightWidth = availableWidth - leftWidth - midWidth
	if rightWidth < 280 then
		local deficit = 280 - rightWidth
		rightWidth = 280
		leftWidth = math.max(180, leftWidth - math.floor(deficit * 0.55))
		midWidth = math.max(160, midWidth - math.ceil(deficit * 0.55))
	end
	if leftCollapsed then
		leftWidth = 0
		availableWidth = width - (padding * 2) - spacing
		midWidth = math.max(160, math.floor(availableWidth * 0.20))
		rightWidth = math.max(380, availableWidth - midWidth)
		f.left:Hide()
	else
		f.left:Show()
	end

	-- Left panel
	f.left:SetPoint("TOPLEFT", f, "TOPLEFT", padding, -headerOffset)
	f.left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", padding, padding + 3)
	f.left:SetWidth(leftWidth)

	-- Middle panel
	f.middle:ClearAllPoints()
	if leftCollapsed then
		f.middle:SetPoint("TOPLEFT", f, "TOPLEFT", padding, -headerOffset)
		f.middle:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", padding, padding + 3)
	else
		f.middle:SetPoint("TOPLEFT", f.left, "TOPRIGHT", spacing, 0)
		f.middle:SetPoint("BOTTOMLEFT", f.left, "BOTTOMRIGHT", spacing, 0)
	end
	f.middle:SetWidth(midWidth)
	if self.ui and self.ui.filterContainer then
		self.ui.filterContainer:SetPoint("TOPLEFT", f.middle, "TOPLEFT", 12, -36)
		self.ui.filterContainer:SetPoint("TOPRIGHT", f.middle, "TOPRIGHT", -12, -36)
	end

	-- Right panel
	f.right:ClearAllPoints()
	f.right:SetPoint("TOPLEFT", f.middle, "TOPRIGHT", spacing, 0)
	f.right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(padding / 2), padding + 3)
	f.right:SetWidth(rightWidth)

	if self.ui and self.ui.leftToggle then
		self.ui.leftToggle:ClearAllPoints()
		self.ui.leftToggle:SetPoint("TOPLEFT", f, "TOPLEFT", padding - 6, -headerOffset + 4)
		local atlas = leftCollapsed and "NPE_ArrowRight" or "NPE_ArrowLeft"
		self.ui.leftToggle:SetNormalAtlas(atlas)
		self.ui.leftToggle:SetPushedAtlas(atlas)
		self.ui.leftToggle:SetHighlightAtlas(atlas)
	end
end

function ChannelHistory:CreateDebugFrame(showImmediately)
	if self.debugFrame then return end
	self:InitStorage()

	local f = CreateFrame("Frame", "EnhanceQoLChannelHistoryFrame", UIParent, "BackdropTemplate")
	self.debugFrame = f
	self.ui = self.ui or {}
	self.ui.leftButtons = self.ui.leftButtons or {}
	self.ui.leftEntries = self.ui.leftEntries or {}
	self.ui.leftState = self.ui.leftState or { realms = {}, factions = {}, accountExpanded = true }
	self.ui.filters = self.ui.filters or {}
	self:EnsureSelection()
	self.runtime = self.runtime or { guidClassCache = {} }

	f:SetSize(950, 550)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetResizable(false)
	f:SetBackdrop(nil)
	f:SetBackdropBorderColor(0, 0, 0, 0)
	f:SetHitRectInsets(-13, -19, -13, -19)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
	f.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 10)
	f.bg:SetTexture("Interface\\AddOns\\EnhanceQoL\\Assets\\background_dark.tga")
	f.bg:SetAlpha(0.9)
	self:RestoreFramePosition()
	self:SetFrameStrata((addon.db and addon.db.chatHistoryFrameStrata) or self.frameStrata or "MEDIUM")
	self:SetFrameLevel((addon.db and addon.db.chatHistoryFrameLevel) or self.frameLevel or 600)
	self:UpdateToggleButtonStrata()
	self:UpdateToggleButtonSize()

	local function applyAtlas(texture, atlas)
		if not texture or not atlas then return end
		texture:SetAtlas(atlas, true)
		local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
		if info then texture:SetSize(info.width or texture:GetWidth(), info.height or texture:GetHeight()) end
		return info
	end

	-- Alliance-styled frame tiles
	local borderLayer, borderSubLevel = "BORDER", 0
	local borderPath = "Interface\\AddOns\\EnhanceQoL\\Assets\\PanelBorder_"
	local cornerSize = 70
	local edgeThickness = 70
	local cornerOffsets = 13

	local function makeTex(key, layer, subLevel)
		local tex = f:CreateTexture(nil, layer or borderLayer, nil, subLevel or borderSubLevel)
		tex:SetTexture(borderPath .. key .. ".tga")
		tex:SetAlpha(0.95)
		return tex
	end

	local tl = makeTex("tl", borderLayer, borderSubLevel + 1)
	tl:SetSize(cornerSize, cornerSize)
	tl:SetPoint("TOPLEFT", f, "TOPLEFT", -cornerOffsets, cornerOffsets)

	local tr = makeTex("tr", borderLayer, borderSubLevel + 1)
	tr:SetSize(cornerSize, cornerSize)
	tr:SetPoint("TOPRIGHT", f, "TOPRIGHT", cornerOffsets + 8, cornerOffsets)

	local bl = makeTex("bl", borderLayer, borderSubLevel + 1)
	bl:SetSize(cornerSize, cornerSize)
	bl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -cornerOffsets, -cornerOffsets)

	local br = makeTex("br", borderLayer, borderSubLevel + 1)
	br:SetSize(cornerSize, cornerSize)
	br:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", cornerOffsets + 8, -cornerOffsets)

	local top = makeTex("t", borderLayer, borderSubLevel)
	top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
	top:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0)
	top:SetHeight(edgeThickness)
	top:SetHorizTile(true)

	local bottom = makeTex("b", borderLayer, borderSubLevel)
	bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT", 0, 0)
	bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
	bottom:SetHeight(edgeThickness)
	bottom:SetHorizTile(true)

	local left = makeTex("l", borderLayer, borderSubLevel)
	left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT", 0, 0)
	left:SetWidth(edgeThickness)
	left:SetVertTile(true)

	local right = makeTex("r", borderLayer, borderSubLevel)
	right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0)
	right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
	right:SetWidth(edgeThickness)
	right:SetVertTile(true)

	f:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
	f:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		self:SaveFramePosition()
	end)
	f:SetScript("OnMouseDown", function(frame, button)
		if button == "LeftButton" and not frame.isSizing then frame:StartMoving() end
	end)
	f:SetScript("OnMouseUp", function(frame)
		frame:StopMovingOrSizing()
		self:SaveFramePosition()
	end)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 20, 12)
	self.ui.closeButton = close
	-- Exit button border
	local closeBorder = close:CreateTexture(nil, "ARTWORK", nil, 1)
	closeBorder:SetAtlas("AllianceFrame_ExitBorder", true)
	closeBorder:SetPoint("CENTER", close, "CENTER", 0, 0)
	self.ui.closeBorder = closeBorder

	local function openChatSettings()
		if InCombatLockdown and InCombatLockdown() then
			if UIErrorsFrame and ERR_NOT_IN_COMBAT then UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0, 0) end
			return
		end

		Settings.OpenToCategory(addon.SettingsLayout.chatframeCategory:GetID(), L["CH_TITLE_HISTORY"])
	end

	local helpBtn = CreateFrame("Button", nil, f)
	helpBtn:SetSize(32, 32)
	helpBtn:SetPoint("TOPLEFT", f, "TOPLEFT", -13, 13)
	helpBtn:SetNormalTexture("Interface\\common\\help-i")
	helpBtn:SetHighlightTexture("Interface\\common\\help-i")
	if helpBtn:GetHighlightTexture() then helpBtn:GetHighlightTexture():SetAlpha(0.7) end
	helpBtn:SetScript("OnEnter", function(btn)
		if not GameTooltip then return end
		GameTooltip:SetOwner(btn, "ANCHOR_RIGHT", 6, 0)
		GameTooltip:ClearLines()
		GameTooltip:AddLine(L["CH_HELP_TITLE"] or (HELP_LABEL or "Help"), 1, 0.82, 0)
		GameTooltip:AddLine(L["CH_HELP_ACTIONS"] or "", 1, 1, 1, true)
		GameTooltip:AddLine(" ", 1, 1, 1, true)
		GameTooltip:AddLine(L["CH_HELP_DELETE"] or "", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	helpBtn:SetScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)
	self.ui.clearHelpButton = helpBtn

	local optionsBtn = CreateFrame("Button", nil, f)
	optionsBtn:SetSize(16, 16)
	optionsBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -22)
	optionsBtn:SetNormalAtlas("QuestLog-icon-setting")
	optionsBtn:SetHighlightAtlas("QuestLog-icon-setting")
	optionsBtn:SetScript("OnClick", openChatSettings)
	optionsBtn:SetScript("OnEnter", function(btn)
		if not GameTooltip then return end
		GameTooltip:SetOwner(btn, "ANCHOR_RIGHT", -2, 0)
		GameTooltip:ClearLines()
		GameTooltip:AddLine(OPTIONS, 1, 0.82, 0)
		GameTooltip:AddLine(CHAT, 1, 1, 1)
		GameTooltip:Show()
	end)
	optionsBtn:SetScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)
	self.ui.optionsButton = optionsBtn

	local copyBtn = CreateFrame("Button", nil, f)
	copyBtn:SetSize(20, 20)
	copyBtn:SetPoint("RIGHT", optionsBtn, "RIGHT", -25, -1)
	copyBtn:SetNormalTexture("Interface\\AddOns\\EnhanceQoL\\Icons\\copy.tga")
	copyBtn:SetHighlightTexture("Interface\\AddOns\\EnhanceQoL\\Icons\\copy.tga")
	if copyBtn:GetHighlightTexture() then copyBtn:GetHighlightTexture():SetAlpha(0.6) end
	copyBtn:SetMotionScriptsWhileDisabled(true)
	self.ui.copyButton = copyBtn

	local copyPopup
	local function ensureCopyPopupFrame()
		if copyPopup then return copyPopup end
		local assetPath = "Interface\\AddOns\\EnhanceQoL\\Assets\\"
		local popup = CreateFrame("Frame", "EnhanceQoLChannelHistoryCopy", UIParent, "BackdropTemplate")
		popup:SetSize(640, 400)
		popup:SetPoint("CENTER")
		popup:SetFrameStrata("DIALOG")
		popup:SetClampedToScreen(true)
		popup:EnableMouse(true)
		popup:SetMovable(true)

		popup.bg = popup:CreateTexture(nil, "BACKGROUND")
		popup.bg:SetAllPoints()
		popup.bg:SetTexture(assetPath .. "background_gray.tga")
		popup.bg:SetAlpha(0.9)
		applyInsetBorder(popup, -6)

		local closeCopy = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
		closeCopy:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 4, 4)

		local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		title:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -12)
		title:SetText(L["CH_COPY_TITLE"])

		-- Drag handle on the outer/top border only (keeps the edit box selectable)
		local dragHandle = CreateFrame("Frame", nil, popup)
		dragHandle:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, 0)
		dragHandle:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, 0)
		dragHandle:SetHeight(28)
		dragHandle:EnableMouse(true)
		dragHandle:RegisterForDrag("LeftButton")
		dragHandle:SetScript("OnDragStart", function() popup:StartMoving() end)
		dragHandle:SetScript("OnDragStop", function() popup:StopMovingOrSizing() end)

		local scroll = CreateFrame("ScrollFrame", nil, popup)
		scroll:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, -36)
		scroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -18, 12)
		scroll:EnableMouseWheel(true)

		local editBox = CreateFrame("EditBox", nil, scroll)
		editBox:SetMultiLine(true)
		editBox:SetAutoFocus(true)
		editBox:SetFontObject(ChatFontNormal or GameFontNormal)
		editBox:SetJustifyH("LEFT")
		editBox:SetJustifyV("TOP")
		editBox:SetTextColor(1, 1, 1, 1)
		editBox:SetMaxLetters(100000)
		editBox:ClearAllPoints()
		editBox:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -10)
		editBox:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, -10)
		editBox:SetWidth(580)
		editBox:SetScript("OnEscapePressed", function() popup:Hide() end)

		scroll:SetScrollChild(editBox)

		popup.editBox = editBox
		popup.scroll = scroll
		popup.scrollBar = self:CreateThinScrollFrameBar(scroll, 6)

		function popup:RefreshScrollHeight()
			if not self.editBox or not self.scroll then return end
			local width = (self.scroll:GetWidth() or 0)
			if width < 50 then return end -- layout not ready yet
			self.editBox:SetWidth(width - 4)
			local textHeight = self.editBox.GetTextHeight and self.editBox:GetTextHeight() or 0
			local minHeight = self.scroll:GetHeight() or 0
			self.editBox:SetHeight(math.max(textHeight + 16, minHeight))
			if self.scrollBar and ChannelHistory and ChannelHistory.UpdateThinScrollFrameBar then ChannelHistory:UpdateThinScrollFrameBar(self.scrollBar, self.scroll) end
		end

		scroll:SetScript("OnSizeChanged", function() popup:RefreshScrollHeight() end)

		copyPopup = popup
		ChannelHistory.ui = ChannelHistory.ui or {}
		ChannelHistory.ui.copyPopup = popup
		return popup
	end

	local function buildCopyTextFromData()
		if not self.history or not self.keys then self:InitStorage() end

		local scope, realmKey, charKey, factionKey = deriveScope(self.ui.selection, self.keys)
		local search = self.ui.rightSearch and self.ui.rightSearch:GetText()
		local needle = search and search:lower()

		local maxUI = (self.ui.logFrame and self.ui.logFrame:GetMaxLines()) or self.uiMaxLines or 1000
		local dataLines = collectLines(self, scope, realmKey, charKey, factionKey, needle, maxUI)

		local out = {}
		local lastDate

		for i = 1, #dataLines do
			local lt = dataLines[i].time or now()
			local currDate = date("%Y-%m-%d", lt)

			if currDate ~= lastDate then
				out[#out + 1] = string.format("|cff777777----- %s -----|r", currDate or "")
				lastDate = currDate
			end

			out[#out + 1] = formatLine(self, dataLines[i])
		end

		return table.concat(out, "\n")
	end

	local function copyVisibleLines()
		local popup = ensureCopyPopupFrame()
		popup:Show()

		local text = sanitizeCopyText(buildCopyTextFromData())
		local maxLetters = 15000
		if text and #text > maxLetters then text = string.sub(text, -maxLetters) end
		popup.editBox._justSet = true
		popup.editBox:SetText(text or "")

		-- C_Timer.After(0, function()
		-- 	if popup.RefreshScrollHeight then popup:RefreshScrollHeight() end
		-- 	if popup.scroll then popup.scroll:SetVerticalScroll(0) end
		-- 	if popup.scrollBar and ChannelHistory and ChannelHistory.UpdateThinScrollFrameBar then ChannelHistory:UpdateThinScrollFrameBar(popup.scrollBar, popup.scroll) end

		-- 	popup.editBox:SetCursorPosition(0)
		-- 	popup.editBox:SetFocus()
		-- 	popup.editBox:HighlightText()
		-- end)
	end

	copyBtn:SetScript("OnClick", function() copyVisibleLines() end)
	copyBtn:SetScript("OnEnter", function(btn)
		if not GameTooltip then return end
		GameTooltip:SetOwner(btn, "ANCHOR_TOPRIGHT", -2, -2)
		GameTooltip:ClearLines()
		GameTooltip:AddLine(L["CH_COPY_TITLE"], 1, 0.82, 0)
		GameTooltip:AddLine(L["CH_COPY_HINT"], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	copyBtn:SetScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)

	local assetPath = "Interface\\AddOns\\EnhanceQoL\\Assets\\"

	-- Panels
	f.left = CreateFrame("Frame", nil, f, "BackdropTemplate")
	-- applyPanelBackdrop(f.left)
	f.left.bg = f.left:CreateTexture(nil, "BACKGROUND", nil, -7)
	f.left.bg:SetAllPoints()
	f.left.bg:SetTexture(assetPath .. "background_gray.tga")
	f.left.bg:SetAlpha(0.75)
	self.left = f.left
	applyInsetBorder(f.left, -4)

	f.middle = CreateFrame("Frame", nil, f, "BackdropTemplate")
	-- applyPanelBackdrop(f.middle)
	f.middle.bg = f.middle:CreateTexture(nil, "BACKGROUND", nil, -7)
	f.middle.bg:SetAllPoints()
	f.middle.bg:SetTexture(assetPath .. "background_gray.tga")
	f.middle.bg:SetAlpha(0.75)
	self.middle = f.middle
	applyInsetBorder(f.middle, -4)

	f.right = CreateFrame("Frame", nil, f, "BackdropTemplate")
	-- applyPanelBackdrop(f.right)
	f.right.bg = f.right:CreateTexture(nil, "BACKGROUND", nil, -7)
	f.right.bg:SetAllPoints()
	f.right.bg:SetTexture(assetPath .. "background_gray.tga")
	f.right.bg:SetAlpha(0.35)
	self.right = f.right
	applyInsetBorder(f.right, -4)

	-- Collapse toggle for left panel
	self.ui.leftCollapsed = addon.db and addon.db.chatHistoryLeftCollapsed or false
	local toggle = CreateFrame("Button", nil, f)
	toggle:SetSize(18, 18)
	toggle:SetNormalAtlas("NPE_ArrowLeft")
	toggle:SetPushedAtlas("NPE_ArrowLeft")
	toggle:SetHighlightAtlas("NPE_ArrowLeft")
	toggle:SetScript("OnClick", function()
		self.ui.leftCollapsed = not self.ui.leftCollapsed
		if addon.db then addon.db.chatHistoryLeftCollapsed = self.ui.leftCollapsed end
		self:LayoutDebugFrame()
	end)
	self.ui.leftToggle = toggle

	local function createPanelHeader(parent, label)
		local hdr = CreateFrame("Frame", nil, parent)
		hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -6)
		hdr:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -6)
		hdr:SetHeight(24)
		local text = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		text:SetPoint("LEFT", hdr, "LEFT", 4, 0)
		text:SetText(label)
		text:SetTextColor(1, 0.88, 0.5)
		local line = hdr:CreateTexture(nil, "ARTWORK")
		line:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 2, 2)
		line:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", -1, 2)
		line:SetHeight(1)
		line:SetColorTexture(1, 1, 1, 0.15)
		return hdr
	end

	createPanelHeader(f.left, L["CH_TITLE_SCOPE"])
	createPanelHeader(f.middle, L["CH_TITLE_FILTERS"])
	createPanelHeader(f.right, L["CH_TITLE_HISTORY"])

	-- Search bars (debug placeholders)
	local leftSearch = createSearchBox(f.left, L["CH_SEARCH_CHAR_REALM"])
	leftSearch:SetPoint("TOPLEFT", f.left, "TOPLEFT", 14, -34)
	leftSearch:SetPoint("TOPRIGHT", f.left, "TOPRIGHT", -7, -34)
	self.ui.leftSearch = leftSearch
	leftSearch:SetScript("OnTextChanged", function(box)
		SearchBoxTemplate_OnTextChanged(box)
		ChannelHistory:RequestLeftRefresh()
	end)

	local rightSearch = createSearchBox(f.right, L["CH_SEARCH_LOGS"])
	rightSearch:SetPoint("TOPLEFT", f.right, "TOPLEFT", 14, -34)
	rightSearch:SetPoint("TOPRIGHT", f.right, "TOPRIGHT", -6, -34)
	self.ui.rightSearch = rightSearch
	self.ui.searchNeedleLower = self.ui.searchNeedleLower or ""
	rightSearch:SetScript("OnTextChanged", function(box)
		SearchBoxTemplate_OnTextChanged(box)
		self.ui.searchNeedleLower = (box:GetText() or ""):lower()
		ChannelHistory:RequestLogRefresh()
	end)
	self.ui.statusBar = CreateFrame("Frame", nil, f.right, "BackdropTemplate")
	self.ui.statusBar:SetPoint("TOPLEFT", rightSearch, "BOTTOMLEFT", -4, -4)
	self.ui.statusBar:SetPoint("TOPRIGHT", rightSearch, "BOTTOMRIGHT", 0, -4)
	self.ui.statusBar:SetHeight(18)
	self.ui.statusBar.bg = self.ui.statusBar:CreateTexture(nil, "BACKGROUND")
	self.ui.statusBar.bg:SetAllPoints()
	self.ui.statusBar.bg:SetColorTexture(0, 0, 0, 0.35)
	self.ui.statusBar.text = self.ui.statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	self.ui.statusBar.text:SetPoint("LEFT", self.ui.statusBar, "LEFT", 6, 0)
	self.ui.statusBar.text:SetPoint("RIGHT", self.ui.statusBar, "RIGHT", -6, 0)
	self.ui.statusBar.text:SetJustifyH("LEFT")
	self.ui.statusBar.text:SetText("")

	-- Left list scroll
	local listTopOffset = -63
	local leftScroll = CreateFrame("ScrollFrame", nil, f.left, "UIPanelScrollFrameTemplate")
	leftScroll:SetPoint("TOPLEFT", f.left, "TOPLEFT", 2, listTopOffset)
	leftScroll:SetPoint("BOTTOMRIGHT", f.left, "BOTTOMRIGHT", -22, 15)
	local sb = leftScroll.ScrollBar or leftScroll.scrollBar
	if sb then
		sb:ClearAllPoints()
		sb:SetPoint("TOPRIGHT", leftScroll, "TOPRIGHT", -2, -20)
		sb:SetPoint("BOTTOMRIGHT", leftScroll, "BOTTOMRIGHT", -2, 12)
		sb:SetWidth(16)
	end

	local leftContent = CreateFrame("Frame", nil, leftScroll)
	leftContent:SetSize(1, 1)
	leftScroll:SetScrollChild(leftContent)

	self.ui.leftScroll = leftScroll
	self.ui.leftContent = leftContent

	-- Hide default scrollbar and apply thin variant
	local defaultSB = leftScroll.ScrollBar or leftScroll.scrollBar
	if defaultSB then
		defaultSB:Hide()
		defaultSB:EnableMouse(false)
		if defaultSB.ScrollUpButton then defaultSB.ScrollUpButton:Hide() end
		if defaultSB.ScrollDownButton then defaultSB.ScrollDownButton:Hide() end
	end
	self.ui.leftScrollThin = self:CreateThinScrollFrameBar(leftScroll, 4)

	-- Resize grip
	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -6, 6)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function(frame, button)
		if button == "LeftButton" then
			-- sizing disabled
		end
	end)
	grip:SetScript("OnMouseUp", function() end)
	grip:Hide()

	f:SetScript("OnSizeChanged", function(frame, w, h) ChannelHistory:LayoutDebugFrame(w, h) end)
	f:SetScript("OnHide", function()
		if ChannelHistory.runtime and ChannelHistory.runtime.formattedCache then wipe(ChannelHistory.runtime.formattedCache) end
		self:SaveFramePosition()
	end)

	self:ApplyFrameZOrder()

	self:LayoutDebugFrame(950, 500)
	self:RefreshLeftList()
	self:CreateFilterUI()
	self:EnsureLogFrame()
	self:RefreshLogView()
	f:Hide()
	if showImmediately then f:Show() end
end
