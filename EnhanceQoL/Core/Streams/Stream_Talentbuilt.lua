-- luacheck: globals EnhanceQoL GAMEMENU_OPTIONS
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local provider

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.talent = addon.db.datapanel.talent or {}
	db = addon.db.datapanel.talent
	db.prefix = db.prefix or ""
	db.fontSize = db.fontSize or 14
	db.hideIcon = db.hideIcon or false
end
local function RestorePosition(frame)
	if db.point and db.x and addon.db.y then
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
	local frame = AceGUI:Create("Frame")
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

	local prefix = AceGUI:Create("EditBox")
	prefix:SetLabel("Prefix")
	prefix:SetText(db.prefix)
	prefix:SetCallback("OnEnterPressed", function(_, _, val)
		db.prefix = val or ""
		addon.DataHub:RequestUpdate(provider)
	end)
	frame:AddChild(prefix)

	local fontSize = AceGUI:Create("Slider")
	fontSize:SetLabel("Font size")
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		addon.DataHub:RequestUpdate(provider)
	end)
	frame:AddChild(fontSize)

	local hide = AceGUI:Create("CheckBox")
	hide:SetLabel("Hide icon")
	hide:SetValue(db.hideIcon)
	hide:SetCallback("OnValueChanged", function(_, _, val)
		db.hideIcon = val and true or false
		addon.DataHub:RequestUpdate(provider)
	end)
	frame:AddChild(hide)

	frame.frame:Show()
end

local function GetConfigName(configID)
	if configID then
		if type(configID) == "number" then
			local info = C_Traits.GetConfigInfo(configID)
			if info then return info.name end
		end
	end
	return "Unknown"
end

local function GetCurrentTalents(stream)
	ensureDB()
	local specId = PlayerUtil.GetCurrentSpecID()
	local name = "Unknown"
	if specId then name = GetConfigName(C_ClassTalents.GetLastSelectedSavedConfigID(specId)) end
	local prefix = db.prefix ~= "" and (db.prefix .. " ") or ""
	local icon = ""
	if not db.hideIcon then
		local size = db.fontSize or 14
		icon = ("|TInterface\\Minimap\\Tracking\\Target:%d:%d:0:0|t "):format(size, size)
	end
	stream.snapshot.text = icon .. prefix .. name
	stream.snapshot.fontSize = db.fontSize
	stream.snapshot.tooltip = L["Right-Click for options"]
end

provider = {
	id = "talent",
	version = 1,
	title = TALENTS,
	update = GetCurrentTalents,
	events = {
		PLAYER_LOGIN = function(stream)
			C_Timer.After(1, function() addon.DataHub:RequestUpdate(stream) end)
		end,
		TRAIT_CONFIG_CREATED = function(stream) addon.DataHub:RequestUpdate(stream) end,
		TRAIT_CONFIG_DELETED = function(stream) addon.DataHub:RequestUpdate(stream) end,
		TRAIT_CONFIG_UPDATED = function(stream)
			C_Timer.After(0.02, function() addon.DataHub:RequestUpdate(stream) end)
		end,
		ZONE_CHANGED_NEW_AREA = function(stream) addon.DataHub:RequestUpdate(stream) end,
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
}

EnhanceQoL.DataHub.RegisterStream(provider)

return provider
