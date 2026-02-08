-- luacheck: globals EnhanceQoL GAMEMENU_OPTIONS MenuResponse MenuUtil LOOT_SPECIALIZATION
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream
local last = {}
local LOOTSPEC_TITLE = SELECT_LOOT_SPECIALIZATION or LOOT_SPECIALIZATION or "Loot Specialization"

local function getOptionsHint()
	if addon.DataPanel and addon.DataPanel.GetOptionsHintText then
		local text = addon.DataPanel.GetOptionsHintText()
		if text ~= nil then return text end
		return nil
	end
	return L["Right-Click for options"]
end

local function ensureDB()
	if db then return end
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.lootspec = addon.db.datapanel.lootspec or {}
	db = addon.db.datapanel.lootspec
	db.prefix = db.prefix or ""
	db.fontSize = db.fontSize or 14
	if db.hidePrefix == nil then db.hidePrefix = false end
	if db.hideIcon == nil then db.hideIcon = false end
	if db.truncateSpecName == nil then
		if db.iconOnly ~= nil then
			db.truncateSpecName = db.iconOnly
		else
			db.truncateSpecName = false
		end
	end
	if db.hideIcon and db.truncateSpecName then db.truncateSpecName = false end
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

	local hidePrefix = AceGUI:Create("CheckBox")
	hidePrefix:SetLabel(L["Hide prefix"] or "Hide prefix")
	hidePrefix:SetValue(db.hidePrefix)
	hidePrefix:SetCallback("OnValueChanged", function(_, _, val)
		db.hidePrefix = val and true or false
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(hidePrefix)

	local fontSize = AceGUI:Create("Slider")
	fontSize:SetLabel(FONT_SIZE)
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(fontSize)

	local hide
	local truncateName

	hide = AceGUI:Create("CheckBox")
	hide:SetLabel(L["Hide icon"] or "Hide icon")
	hide:SetValue(db.hideIcon)
	hide:SetCallback("OnValueChanged", function(_, _, val)
		db.hideIcon = val and true or false
		if db.hideIcon and db.truncateSpecName then
			db.truncateSpecName = false
			if truncateName and truncateName.SetValue then truncateName:SetValue(false) end
		end
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(hide)

	truncateName = AceGUI:Create("CheckBox")
	truncateName:SetLabel(L["Truncate loot spec"] or "Truncate loot spec")
	truncateName:SetValue(db.truncateSpecName)
	truncateName:SetCallback("OnValueChanged", function(_, _, val)
		db.truncateSpecName = val and true or false
		if db.truncateSpecName and db.hideIcon then
			db.hideIcon = false
			if hide and hide.SetValue then hide:SetValue(false) end
		end
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(truncateName)

	frame.frame:Show()
end

local function getCurrentSpecInfo()
	local specIndex = C_SpecializationInfo.GetSpecialization()
	if not specIndex then return nil end
	local specID, specName, _, specIcon = GetSpecializationInfo(specIndex)
	return specIndex, specID, specName, specIcon
end

local function showLootSpecMenu(owner)
	if not MenuUtil or not MenuUtil.CreateContextMenu then return end
	local specIndex, specID, specName = getCurrentSpecInfo()
	if not specID then return end
	local lootSpecID = GetLootSpecialization() or 0
	local inCombat = InCombatLockdown and InCombatLockdown()

	local totalSpecs = GetNumSpecializations and GetNumSpecializations() or 0
	if totalSpecs == 0 and C_SpecializationInfo.GetNumSpecializationsForClassID and addon.variables and addon.variables.unitClassID then
		totalSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(addon.variables.unitClassID)
	end

	MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
		rootDescription:SetTag("MENU_EQOL_LOOTSPEC")
		rootDescription:CreateTitle(LOOT_SPECIALIZATION or "Loot Specialization")

		local defaultText = (LOOT_SPECIALIZATION_DEFAULT and specName) and LOOT_SPECIALIZATION_DEFAULT:format(specName) or (L["Default loot spec"] or "Default")
		local defaultRadio = rootDescription:CreateRadio(defaultText, function() return lootSpecID == 0 end, function()
			if InCombatLockdown and InCombatLockdown() then
				if UIErrorsFrame and ERR_NOT_IN_COMBAT then UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT) end
				return
			end
			SetLootSpecialization(0)
			return MenuResponse and MenuResponse.Close
		end, 0)
		if inCombat then defaultRadio:SetEnabled(false) end

		for i = 1, totalSpecs do
			local sID, sName = GetSpecializationInfo(i)
			if sID and sName then
				local radio = rootDescription:CreateRadio(sName, function() return lootSpecID == sID end, function()
					if InCombatLockdown and InCombatLockdown() then
						if UIErrorsFrame and ERR_NOT_IN_COMBAT then UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT) end
						return
					end
					if lootSpecID == sID then return MenuResponse and MenuResponse.Close end
					SetLootSpecialization(sID)
					return MenuResponse and MenuResponse.Close
				end, sID)
				if inCombat then radio:SetEnabled(false) end
			end
		end

		rootDescription:CreateDivider()
		rootDescription:CreateTitle(SPECIALIZATION or "Specialization")
		for i = 1, totalSpecs do
			local _, sName = GetSpecializationInfo(i)
			if sName then
				local radio = rootDescription:CreateRadio(sName, function() return specIndex == i end, function()
					if InCombatLockdown and InCombatLockdown() then
						if UIErrorsFrame and ERR_NOT_IN_COMBAT then UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT) end
						return
					end
					if specIndex == i then return MenuResponse and MenuResponse.Close end
					C_SpecializationInfo.SetSpecialization(i)
					return MenuResponse and MenuResponse.Close
				end, i)
				if inCombat then radio:SetEnabled(false) end
			end
		end
	end)
end

local function updateLootSpec(stream)
	ensureDB()
	local specIndex, specID, specName, specIcon = getCurrentSpecInfo()
	local lootSpecID = GetLootSpecialization() or 0
	local hint = getOptionsHint()
	local keySpecID = specID or 0
	local keySpecName = specName or ""
	local keySpecIcon = specIcon or 0

	if
		last.specID == keySpecID
		and last.specName == keySpecName
		and last.specIcon == keySpecIcon
		and last.lootSpecID == lootSpecID
		and last.prefix == db.prefix
		and last.hidePrefix == db.hidePrefix
		and last.fontSize == db.fontSize
		and last.hideIcon == db.hideIcon
		and last.truncateSpecName == db.truncateSpecName
		and last.hint == hint
	then
		return
	end

	last.specID = keySpecID
	last.specName = keySpecName
	last.specIcon = keySpecIcon
	last.lootSpecID = lootSpecID
	last.prefix = db.prefix
	last.hidePrefix = db.hidePrefix
	last.fontSize = db.fontSize
	last.hideIcon = db.hideIcon
	last.truncateSpecName = db.truncateSpecName
	last.hint = hint

	local lootName, lootIcon
	if lootSpecID == 0 then
		lootName = specName or UNKNOWN
		lootIcon = specIcon
	else
		local _, name, _, icon = GetSpecializationInfoByID(lootSpecID)
		lootName = name or UNKNOWN
		lootIcon = icon
	end

	local size = db.fontSize or 14
	local label = _G.LOOT or "Loot"
	local icon = db.hidePrefix and "" or ("|cffc0c0c0%s:|r "):format(label)
	if not db.hideIcon and lootIcon then icon = icon .. ("|T%d:%d:%d:0:0|t "):format(lootIcon, size, size) end
	local prefix = db.prefix ~= "" and (db.prefix .. " ") or ""
	local name = db.truncateSpecName and "" or (lootName or UNKNOWN)
	stream.snapshot.text = icon .. prefix .. name
	stream.snapshot.fontSize = size

	local clickHint = L["Loot spec click hint"] or "Left-click to change loot and active specialization"
	if hint then
		stream.snapshot.tooltip = clickHint .. "\n" .. hint
	else
		stream.snapshot.tooltip = clickHint
	end
end

local provider = {
	id = "lootspec",
	version = 1,
	title = LOOTSPEC_TITLE,
	update = updateLootSpec,
	events = {
		PLAYER_LOGIN = function(stream) addon.DataHub:RequestUpdate(stream) end,
		PLAYER_LOOT_SPEC_UPDATED = function(stream) addon.DataHub:RequestUpdate(stream) end,
		PLAYER_SPECIALIZATION_CHANGED = function(stream) addon.DataHub:RequestUpdate(stream) end,
		TRAIT_CONFIG_UPDATED = function(stream) addon.DataHub:RequestUpdate(stream) end,
	},
	OnClick = function(button, btn)
		if btn == "RightButton" then
			createAceWindow()
		else
			showLootSpecMenu(button)
		end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
