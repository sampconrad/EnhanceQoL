-- luacheck: globals EnhanceQoL GAMEMENU_OPTIONS MenuResponse ReadOwnKeystone
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream
local openKeystone
local provider
local registerOpenKeystoneCallbacks

local KEYSTONE_ITEM_IDS = { 180653, 158923, 138019 }
local DEFAULT_KEYSTONE_ICON = "Interface\\Icons\\inv_relicsrunestone"

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
	addon.db.datapanel.mythickey = addon.db.datapanel.mythickey or {}
	db = addon.db.datapanel.mythickey
	db.prefix = db.prefix or ""
	db.fontSize = db.fontSize or 14
	if db.hideIcon == nil then db.hideIcon = false end
end

local function RestorePosition(frame)
	if db and db.point and db.x and db.y then
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

	local prefix = AceGUI:Create("EditBox")
	prefix:SetLabel(L["Prefix"] or "Prefix")
	prefix:SetText(db.prefix)
	prefix:SetCallback("OnEnterPressed", function(_, _, val)
		db.prefix = val or ""
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(prefix)

	local fontSize = AceGUI:Create("Slider")
	fontSize:SetLabel(FONT_SIZE)
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(fontSize)

	local hide = AceGUI:Create("CheckBox")
	hide:SetLabel(L["Hide icon"] or "Hide icon")
	hide:SetValue(db.hideIcon)
	hide:SetCallback("OnValueChanged", function(_, _, val)
		db.hideIcon = val and true or false
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(hide)

	frame.frame:Show()
end

local function getOwnKeystone()
	if type(ReadOwnKeystone) == "function" then return ReadOwnKeystone() end
	if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID then
		return C_MythicPlus.GetOwnedKeystoneChallengeMapID() or 0, (C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel() or 0)
	end
	if C_ChallengeMode and C_ChallengeMode.GetOwnedKeystoneMapID then
		return C_ChallengeMode.GetOwnedKeystoneMapID() or 0, (C_ChallengeMode.GetOwnedKeystoneLevel and C_ChallengeMode.GetOwnedKeystoneLevel() or 0)
	end
	return 0, 0
end

local function getKeystoneIcon()
	if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneInfo then
		local _, _, _, itemLink = C_MythicPlus.GetOwnedKeystoneInfo()
		if itemLink and GetItemIcon then
			local icon = GetItemIcon(itemLink)
			if icon then return icon end
		end
	end
	if C_Item and C_Item.GetItemIconByID then
		for _, id in ipairs(KEYSTONE_ITEM_IDS) do
			local icon = C_Item.GetItemIconByID(id)
			if icon then return icon end
		end
	end
	for _, id in ipairs(KEYSTONE_ITEM_IDS) do
		local icon = select(5, GetItemInfoInstant(id))
		if icon then return icon end
	end
	return DEFAULT_KEYSTONE_ICON
end

local function updateKey(stream)
	registerOpenKeystoneCallbacks()
	ensureDB()
	local mapID, level = getOwnKeystone()
	local hasKey = mapID and mapID > 0 and level and level > 0
	local mapName
	if hasKey and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then mapName = C_ChallengeMode.GetMapUIInfo(mapID) end

	local size = db.fontSize or 14
	local icon = ""
	if not db.hideIcon then icon = ("|T%s:%d:%d:0:0|t "):format(getKeystoneIcon(), size, size) end
	local prefix = db.prefix ~= "" and (db.prefix .. " ") or ""
	if hasKey then
		local name = mapName or (mapID and ("#" .. mapID) or UNKNOWN)
		stream.snapshot.text = ("%s%s+%d %s"):format(icon, prefix, level, name)
	else
		stream.snapshot.text = ("%s%s%s"):format(icon, prefix, L["No Keystone"] or "No Keystone")
	end
	stream.snapshot.fontSize = size

	local tooltipLines = {}
	if hasKey then
		local name = mapName or (mapID and ("#" .. mapID) or UNKNOWN)
		tooltipLines[#tooltipLines + 1] = ("%s +%d"):format(name, level)
	else
		tooltipLines[#tooltipLines + 1] = L["No Keystone"] or "No Keystone"
	end
	local hint = getOptionsHint()
	if hint then tooltipLines[#tooltipLines + 1] = hint end
	stream.snapshot.tooltip = table.concat(tooltipLines, "\n")
end

registerOpenKeystoneCallbacks = function()
	if openKeystone then return end
	local lib = LibStub and LibStub:GetLibrary("LibOpenKeystone-1.0", true)
	if not lib or not lib.RegisterCallback then return end
	openKeystone = lib
	local function refresh()
		if stream then addon.DataHub:RequestUpdate(stream) end
	end
	lib.RegisterCallback(provider, "KeystoneUpdate", refresh)
	lib.RegisterCallback(provider, "KeystoneWipe", refresh)
end

provider = {
	id = "mythickey",
	version = 1,
	title = L["Mythic+ Key"] or "Mythic+ Key",
	update = updateKey,
	events = {
		PLAYER_LOGIN = function(stream) addon.DataHub:RequestUpdate(stream) end,
		PLAYER_ENTERING_WORLD = function(stream) addon.DataHub:RequestUpdate(stream) end,
		BAG_UPDATE_DELAYED = function(stream) addon.DataHub:RequestUpdate(stream) end,
		CHALLENGE_MODE_COMPLETED = function(stream) addon.DataHub:RequestUpdate(stream) end,
		CHALLENGE_MODE_RESET = function(stream) addon.DataHub:RequestUpdate(stream) end,
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)
registerOpenKeystoneCallbacks()

return provider
