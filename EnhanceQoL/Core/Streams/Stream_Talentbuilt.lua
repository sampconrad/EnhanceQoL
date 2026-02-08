-- luacheck: globals EnhanceQoL GAMEMENU_OPTIONS MenuResponse MenuUtil ClassTalentHelper PlayerSpellsMicroButton
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream
local provider
local TALENTS_PREFIX_DEFAULT = (TALENTS or "Talents") .. ":"

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
	addon.db.datapanel.talent = addon.db.datapanel.talent or {}
	db = addon.db.datapanel.talent
	db.prefix = db.prefix or TALENTS_PREFIX_DEFAULT
	db.fontSize = db.fontSize or 14
	db.hideIcon = db.hideIcon or false
end
local function RestorePosition(frame)
	if db.point and db.x and db.y then
		frame:ClearAllPoints()
		frame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
	end
end

local aceWindow

local function GetConfigName(configID)
	if configID then
		if type(configID) == "number" then
			local info = C_Traits.GetConfigInfo(configID)
			if info then return info.name end
		end
	end
	return UNKNOWN
end

local function switchToConfig(configID, index)
	if InCombatLockdown and InCombatLockdown() then
		if UIErrorsFrame and ERR_NOT_IN_COMBAT then UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT) end
		return
	end
	if ClassTalentHelper and ClassTalentHelper.SwitchToLoadoutByIndex and index then
		ClassTalentHelper.SwitchToLoadoutByIndex(index)
		return
	end
	if C_ClassTalents and C_ClassTalents.SetActiveConfigID then
		C_ClassTalents.SetActiveConfigID(configID)
		return
	end
	if PlayerSpellsMicroButton then PlayerSpellsMicroButton:Click() end
end

local function showLoadoutMenu(owner)
	if not MenuUtil or not MenuUtil.CreateContextMenu then return end
	local specId = PlayerUtil.GetCurrentSpecID()
	if not specId then return end
	local configs = C_ClassTalents.GetConfigIDsBySpecID(specId) or {}
	local activeConfig = C_ClassTalents.GetLastSelectedSavedConfigID(specId)
	local inCombat = InCombatLockdown and InCombatLockdown()

	MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
		rootDescription:SetTag("MENU_EQOL_TALENT_LOADOUTS")
		rootDescription:CreateTitle(TALENTS)

		if #configs == 0 then
			local row = rootDescription:CreateButton(L["No saved loadouts"] or "No saved loadouts")
			row:SetEnabled(false)
		else
			for index, configID in ipairs(configs) do
				local name = GetConfigName(configID)
				local radio = rootDescription:CreateRadio(name, function() return configID == activeConfig end, function()
					switchToConfig(configID, index)
					return MenuResponse and MenuResponse.Close
				end, configID)
				if inCombat then radio:SetEnabled(false) end
			end
		end

		rootDescription:CreateDivider()
		rootDescription:CreateButton(L["Open Talents"] or "Open Talents", function()
			if PlayerSpellsMicroButton then PlayerSpellsMicroButton:Click() end
		end)
	end)
end

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

local function GetCurrentTalents(stream)
	ensureDB()
	local specId = PlayerUtil.GetCurrentSpecID()
	local name = UNKNOWN
	if specId then name = GetConfigName(C_ClassTalents.GetLastSelectedSavedConfigID(specId)) end
	local prefix = ""
	if db.prefix ~= "" then
		if db.prefix == TALENTS_PREFIX_DEFAULT then
			prefix = ("|cffc0c0c0%s|r "):format(TALENTS_PREFIX_DEFAULT)
		else
			prefix = db.prefix .. " "
		end
	end
	local icon = ""
	if not db.hideIcon then
		local size = db and db.fontSize or 14
		icon = ("|TInterface\\Addons\\EnhanceQoL\\Icons\\Talents:%d:%d:0:0|t "):format(size, size)
	end
	stream.snapshot.text = icon .. prefix .. name
	stream.snapshot.fontSize = db.fontSize
	local hint = getOptionsHint()
	local clickHint = L["Talent loadout click hint"] or "Left-click to switch loadout"
	if hint then
		stream.snapshot.tooltip = clickHint .. "\n" .. hint
	else
		stream.snapshot.tooltip = clickHint
	end
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
		PLAYER_SPECIALIZATION_CHANGED = function(stream) addon.DataHub:RequestUpdate(stream) end,
		ZONE_CHANGED_NEW_AREA = function(stream) addon.DataHub:RequestUpdate(stream) end,
	},
	OnClick = function(button, btn)
		if btn == "RightButton" then
			createAceWindow()
		else
			showLoadoutMenu(button)
		end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
