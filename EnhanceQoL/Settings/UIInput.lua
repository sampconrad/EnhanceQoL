-- luacheck: globals C_Timer C_MountJournal LE_MOUNT_JOURNAL_FILTER_COLLECTED LE_MOUNT_JOURNAL_FILTER_UNUSABLE C_PetJournal C_ToyBox C_ToyBoxInfo ToyBox CollectionsMicroButton MainMenuMicroButton_HideAlert CollectionsMicroButton_SetAlertShown MicroButtonPulseStop CreateFrame C_CVar UIParent SetCVar ReloadUI

local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local getCVarOptionState = addon.functions.GetCVarOptionState or function() return false end
local setCVarOptionState = addon.functions.SetCVarOptionState or function() end

-- Mount/pet fanfare auto-clear (unwrap)
local mountUnwrapDebounce = false

local function ApplyNotificationOverlaySetting(first)
	local hideOverlay = addon.db and addon.db.hideMicroMenuNotificationOverlay
	if first and not hideOverlay then return end
	if not MICRO_BUTTONS then return end

	for _, name in ipairs(MICRO_BUTTONS) do
		local overlay = _G[name] and _G[name].NotificationOverlay
		if overlay then overlay:SetAlpha(hideOverlay and 0 or 1) end
	end
end

local function ShouldAutoUnwrapMounts() return addon.db and addon.db.autoUnwrapMounts end

local function StopCollectionAlert(microButton)
	if microButton and MainMenuMicroButton_HideAlert then MainMenuMicroButton_HideAlert(microButton) end
	if CollectionsMicroButton_SetAlertShown then CollectionsMicroButton_SetAlertShown(false) end
end

local function ClearMountFanfare()
	if not C_MountJournal or not C_MountJournal.GetNumMountsNeedingFanfare then return false end
	if C_MountJournal.GetNumMountsNeedingFanfare() <= 0 then return false end

	local lastSetting = {}
	for i = LE_MOUNT_JOURNAL_FILTER_COLLECTED, LE_MOUNT_JOURNAL_FILTER_UNUSABLE do
		lastSetting[i] = C_MountJournal.GetCollectedFilterSetting(i) and true or false
		C_MountJournal.SetCollectedFilterSetting(i, i == LE_MOUNT_JOURNAL_FILTER_COLLECTED)
	end

	for i = 1, C_MountJournal.GetNumDisplayedMounts() do
		local mId = C_MountJournal.GetDisplayedMountID(i)
		if C_MountJournal.NeedsFanfare(mId) then C_MountJournal.ClearFanfare(mId) end
	end

	for i = LE_MOUNT_JOURNAL_FILTER_COLLECTED, LE_MOUNT_JOURNAL_FILTER_UNUSABLE do
		if lastSetting[i] ~= nil then C_MountJournal.SetCollectedFilterSetting(i, lastSetting[i]) end
	end

	return true
end

local function ClearPetFanfare()
	if not C_PetJournal or not C_PetJournal.GetNumPetsNeedingFanfare or not C_PetJournal.GetOwnedPetIDs then return false end
	if (C_PetJournal.GetNumPetsNeedingFanfare() or 0) == 0 then return false end

	local cleared = false
	local ids = C_PetJournal.GetOwnedPetIDs()
	for _, petID in ipairs(ids or {}) do
		if petID and C_PetJournal.PetNeedsFanfare and C_PetJournal.PetNeedsFanfare(petID) then
			if C_PetJournal.ClearFanfare then C_PetJournal.ClearFanfare(petID) end
			cleared = true
		end
	end

	return cleared
end

local function ClearToyFanfare()
	if not C_ToyBoxInfo or not C_ToyBoxInfo.ClearFanfare or not C_ToyBoxInfo.NeedsFanfare then return false end
	local cleared = false

	if ToyBox and ToyBox.fanfareToys then
		for toyID, needs in pairs(ToyBox.fanfareToys) do
			if needs and toyID and C_ToyBoxInfo.NeedsFanfare(toyID) then
				C_ToyBoxInfo.ClearFanfare(toyID)
				cleared = true
			end
		end
		if cleared then return true end
	end

	if C_ToyBox and C_ToyBox.GetNumToys and C_ToyBox.GetToyFromIndex then
		local numToys = C_ToyBox.GetNumToys()
		for i = 1, numToys do
			local toyID = C_ToyBox.GetToyFromIndex(i)
			if toyID and C_ToyBoxInfo.NeedsFanfare(toyID) then
				C_ToyBoxInfo.ClearFanfare(toyID)
				cleared = true
			end
		end
	end

	return cleared
end

local function AutoUnwrapMounts(microButton, text, force)
	if not ShouldAutoUnwrapMounts() then return end
	local hideAlert = force or text == COLLECTION_UNOPENED_PLURAL or text == COLLECTION_UNOPENED_SINGULAR
	if not force and not hideAlert then return end
	if mountUnwrapDebounce then return end
	mountUnwrapDebounce = true
	C_Timer.After(0.2, function()
		if not ShouldAutoUnwrapMounts() then
			mountUnwrapDebounce = false
			return
		end
		local mountCleared = ClearMountFanfare()
		local petCleared = ClearPetFanfare()
		local toyCleared = ClearToyFanfare()
		if mountCleared or petCleared or toyCleared or hideAlert then StopCollectionAlert(microButton or CollectionsMicroButton) end
		mountUnwrapDebounce = false
	end)
end

hooksecurefunc("MainMenuMicroButton_ShowAlert", function(microButton, text, tutorialIndex, cvarBitfield) AutoUnwrapMounts(microButton, text) end)

local autoUnwrapEventFrame
local function UpdateAutoUnwrapWatcher()
	if not autoUnwrapEventFrame then
		autoUnwrapEventFrame = CreateFrame("Frame")
		autoUnwrapEventFrame:SetScript("OnEvent", function(_, event)
			if event == "NEW_PET_ADDED" or event == "NEW_MOUNT_ADDED" or event == "NEW_TOY_ADDED" then AutoUnwrapMounts(CollectionsMicroButton, nil, true) end
			if event == "PLAYER_LOGIN" then AutoUnwrapMounts(CollectionsMicroButton, nil, true) end
		end)
	end

	autoUnwrapEventFrame:UnregisterAllEvents()
	if ShouldAutoUnwrapMounts() then
		autoUnwrapEventFrame:RegisterEvent("PLAYER_LOGIN")
		autoUnwrapEventFrame:RegisterEvent("NEW_PET_ADDED")
		autoUnwrapEventFrame:RegisterEvent("NEW_MOUNT_ADDED")
		autoUnwrapEventFrame:RegisterEvent("NEW_TOY_ADDED")
	end
end
addon.functions.UpdateAutoUnwrapWatcher = UpdateAutoUnwrapWatcher

local cUIInput = addon.SettingsLayout.rootUI

local framesExpandable = addon.SettingsLayout.uiFramesExpandable
if not framesExpandable then
	framesExpandable = addon.functions.SettingsCreateExpandableSection(cUIInput, {
		name = L["VisibilityAndFadingFrames"] or "Visibility & Fading (Frames)",
		expanded = false,
		colorizeTitle = false,
	})
	addon.SettingsLayout.uiFramesExpandable = framesExpandable
end

local barsResourcesExpandable = addon.SettingsLayout.uiBarsResourcesExpandable
if not barsResourcesExpandable then
	barsResourcesExpandable = addon.functions.SettingsCreateExpandableSection(cUIInput, {
		name = L["BarsAndResources"] or "Bars & Resources",
		expanded = false,
		colorizeTitle = false,
		newTagID = "ResourceBars",
	})
	addon.SettingsLayout.uiBarsResourcesExpandable = barsResourcesExpandable
end

local verticalScale = 11 / 17
local horizontalScale = 565 / 571

local UI_SCALE_PRESETS = {
	Scale4K = 0.355555555556,
	Scale1440p = 0.533333333333,
	Scale1080p = 0.711111111111,
	Scale1440p125 = 0.666666666666,
	Scale1080p125 = 0.888888888888,
}

local function applyUIScalePreset()
	local db = addon.db
	if not db then return end

	local scale = UI_SCALE_PRESETS[db.uiScalePreset]
	if not scale then return end
	if addon.functions and addon.functions.setCVarValue then
		addon.functions.setCVarValue("useUiScale", "1")
		addon.functions.setCVarValue("uiscale", tostring(scale))
	elseif C_CVar and C_CVar.SetCVar then
		C_CVar.SetCVar("useUiScale", "1")
		C_CVar.SetCVar("uiscale", tostring(scale))
	end

	if UIParent and UIParent.SetScale then UIParent:SetScale(scale) end
end
addon.functions.applyUIScalePreset = applyUIScalePreset

local function EQOL_UpdateStatusBars(container, height, width, scale)
	if not container then return end

	container:SetHeight(height)
	container:SetWidth(width)

	for _, child in pairs({ container:GetChildren() }) do
		if child and child.StatusBar then
			local point = { child:GetPoint() }

			child:SetHeight(height)
			child:SetWidth(width)

			child.StatusBar:SetHeight(height * verticalScale)
			child.StatusBar:SetWidth(width * horizontalScale)

			child:ClearAllPoints()
			child:SetPoint(point[1], point[2], point[3], -5 * (width / 571), (3 / 20) * height)

			if child.ExhaustionLevelFillBar then
				child.ExhaustionLevelFillBar:SetHeight(height * verticalScale)
				child.ExhaustionLevelFillBar:SetWidth(width * horizontalScale)

				local fillPoint = { child.ExhaustionLevelFillBar:GetPoint() }
				child.ExhaustionLevelFillBar:ClearAllPoints()
				child.ExhaustionLevelFillBar:SetPoint(fillPoint[1], fillPoint[2], fillPoint[3], 5 * (width / 571), (3 / 20) * height)

				if child.ExhaustionTick and child.ExhaustionTick.UpdateTickPosition then child.ExhaustionTick:UpdateTickPosition() end
			end
		end
	end
	container:SetScale(scale)
end

function addon.functions.SettingsCreateClassSpecificResourceBars(category, parentSection)
	if not category or not parentSection then return end

	local class, classTag = UnitClass("player")
	if not classTag then return end

	local data = {}

	local function addTotemCheckbox(dbKey)
		table.insert(data, {
			var = dbKey,
			text = L["shaman_HideTotem"],
			func = function(value) addon.db[dbKey] = value end,
			get = function() return addon.db[dbKey] end,
			parentSection = parentSection,
		})
	end

	if classTag == "DEATHKNIGHT" then
		table.insert(data, {
			var = "deathknight_HideRuneFrame",
			text = L["deathknight_HideRuneFrame"],
			func = function(value)
				addon.db["deathknight_HideRuneFrame"] = value
				if addon.functions and addon.functions.UpdateClassResourceVisibility then addon.functions.UpdateClassResourceVisibility() end
			end,
			parentSection = parentSection,
		})
		addTotemCheckbox("deathknight_HideTotemBar")
	elseif classTag == "DRUID" then
		addTotemCheckbox("druid_HideTotemBar")
		table.insert(data, {
			var = "druid_HideComboPoint",
			text = L["druid_HideComboPoint"],
			func = function(value)
				addon.db["druid_HideComboPoint"] = value
				if addon.functions and addon.functions.UpdateClassResourceVisibility then addon.functions.UpdateClassResourceVisibility() end
			end,
			parentSection = parentSection,
		})
	elseif classTag == "EVOKER" then
		table.insert(data, {
			var = "evoker_HideEssence",
			text = L["evoker_HideEssence"],
			func = function(value)
				addon.db["evoker_HideEssence"] = value
				if addon.functions and addon.functions.UpdateClassResourceVisibility then addon.functions.UpdateClassResourceVisibility() end
			end,
			parentSection = parentSection,
		})
	elseif classTag == "MAGE" then
		addTotemCheckbox("mage_HideTotemBar")
	elseif classTag == "MONK" then
		table.insert(data, {
			var = "monk_HideHarmonyBar",
			text = L["monk_HideHarmonyBar"],
			func = function(value)
				addon.db["monk_HideHarmonyBar"] = value
				if addon.functions and addon.functions.UpdateClassResourceVisibility then addon.functions.UpdateClassResourceVisibility() end
			end,
			parentSection = parentSection,
		})
		addTotemCheckbox("monk_HideTotemBar")
	elseif classTag == "PRIEST" then
		addTotemCheckbox("priest_HideTotemBar")
	elseif classTag == "SHAMAN" then
		addTotemCheckbox("shaman_HideTotem")
	elseif classTag == "ROGUE" then
		table.insert(data, {
			var = "rogue_HideComboPoint",
			text = L["rogue_HideComboPoint"],
			func = function(value)
				addon.db["rogue_HideComboPoint"] = value
				if addon.functions and addon.functions.UpdateClassResourceVisibility then addon.functions.UpdateClassResourceVisibility() end
			end,
			parentSection = parentSection,
		})
	elseif classTag == "PALADIN" then
		addTotemCheckbox("paladin_HideTotemBar")
		table.insert(data, {
			var = "paladin_HideHolyPower",
			text = L["paladin_HideHolyPower"],
			func = function(value)
				addon.db["paladin_HideHolyPower"] = value
				if addon.functions and addon.functions.UpdateClassResourceVisibility then addon.functions.UpdateClassResourceVisibility() end
			end,
			parentSection = parentSection,
		})
	elseif classTag == "WARLOCK" then
		table.insert(data, {
			var = "warlock_HideSoulShardBar",
			text = L["warlock_HideSoulShardBar"],
			func = function(value)
				addon.db["warlock_HideSoulShardBar"] = value
				if addon.functions and addon.functions.UpdateClassResourceVisibility then addon.functions.UpdateClassResourceVisibility() end
			end,
			parentSection = parentSection,
		})
		addTotemCheckbox("warlock_HideTotemBar")
	end

	if #data == 0 then return end

	addon.functions.SettingsCreateHeadline(category, L["headerClassInfo"]:format(class), { parentSection = parentSection })
	table.sort(data, function(a, b) return a.text < b.text end)
	addon.functions.SettingsCreateCheckboxes(category, data)
end

addon.functions.SettingsCreateHeadline(cUIInput, L["XP_Rep"], { parentSection = barsResourcesExpandable })

local data = {
	{
		var = "modifyXPRepBar",
		text = L["modifyXPRepBar"],
		func = function(v)
			addon.db["modifyXPRepBar"] = v
			local height, width, scale = 17, 571, 1
			if v == true then
				if addon.db and addon.db.modifyXPRepBarHeight then height = addon.db and addon.db.modifyXPRepBarHeight end
				if addon.db and addon.db.modifyXPRepBarWidth then width = addon.db and addon.db.modifyXPRepBarWidth end
				if addon.db and addon.db.modifyXPRepBarScale then scale = addon.db and addon.db.modifyXPRepBarScale end
			end
			EQOL_UpdateStatusBars(MainStatusTrackingBarContainer, height, width, scale)
			EQOL_UpdateStatusBars(SecondaryStatusTrackingBarContainer, height, width, scale)
		end,
		parentSection = barsResourcesExpandable,
		children = {
			{
				var = "modifyXPRepBarWidth",
				text = HUD_EDIT_MODE_SETTING_CHAT_FRAME_WIDTH,
				get = function()
					local w = MainStatusTrackingBarContainer:GetSize()
					return addon.db and addon.db.modifyXPRepBarWidth or w
				end,
				set = function(v)
					addon.db["modifyXPRepBarWidth"] = v
					local _, height = MainStatusTrackingBarContainer:GetSize()
					local scale = MainStatusTrackingBarContainer:GetScale()
					EQOL_UpdateStatusBars(MainStatusTrackingBarContainer, height, v, scale)
					EQOL_UpdateStatusBars(SecondaryStatusTrackingBarContainer, height, v, scale)
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["modifyXPRepBar"]
						and addon.SettingsLayout.elements["modifyXPRepBar"].setting
						and addon.SettingsLayout.elements["modifyXPRepBar"].setting:GetValue() == true
				end,
				min = 200,
				max = 800,
				step = 1,
				parent = true,
				default = 571,
				sType = "slider",
				parentSection = barsResourcesExpandable,
			},
			{
				var = "modifyXPRepBarHeight",
				text = HUD_EDIT_MODE_SETTING_CHAT_FRAME_HEIGHT,
				get = function()
					local _, h = MainStatusTrackingBarContainer:GetSize()
					return addon.db and addon.db.modifyXPRepBarHeight or h
				end,
				set = function(v)
					addon.db["modifyXPRepBarHeight"] = v
					local width = MainStatusTrackingBarContainer:GetSize()
					local scale = MainStatusTrackingBarContainer:GetScale()
					EQOL_UpdateStatusBars(MainStatusTrackingBarContainer, v, width, scale)
					EQOL_UpdateStatusBars(SecondaryStatusTrackingBarContainer, v, width, scale)
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["modifyXPRepBar"]
						and addon.SettingsLayout.elements["modifyXPRepBar"].setting
						and addon.SettingsLayout.elements["modifyXPRepBar"].setting:GetValue() == true
				end,
				min = 10,
				max = 75,
				step = 1,
				parent = true,
				default = 17,
				sType = "slider",
				parentSection = barsResourcesExpandable,
			},
			{
				var = "modifyXPRepBarScale",
				text = RENDER_SCALE,
				get = function() return addon.db and addon.db.modifyXPRepBarScale or 1 end,
				set = function(v)
					addon.db["modifyXPRepBarScale"] = v
					local width, height = MainStatusTrackingBarContainer:GetSize()
					EQOL_UpdateStatusBars(MainStatusTrackingBarContainer, height, width, v)
					EQOL_UpdateStatusBars(SecondaryStatusTrackingBarContainer, height, width, v)
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["modifyXPRepBar"]
						and addon.SettingsLayout.elements["modifyXPRepBar"].setting
						and addon.SettingsLayout.elements["modifyXPRepBar"].setting:GetValue() == true
				end,
				min = 0.5,
				max = 3,
				step = 0.05,
				parent = true,
				default = 1,
				sType = "slider",
				parentSection = barsResourcesExpandable,
			},
		},
	},
}
addon.functions.SettingsCreateCheckboxes(cUIInput, data)

if addon.functions and addon.functions.SettingsCreateClassSpecificResourceBars then addon.functions.SettingsCreateClassSpecificResourceBars(cUIInput, barsResourcesExpandable) end
if addon.Aura and addon.Aura.functions and addon.Aura.functions.AddResourceBarsSettings then addon.Aura.functions.AddResourceBarsSettings() end

local interfaceExpandable = addon.functions.SettingsCreateExpandableSection(cUIInput, {
	name = L["PopupsAndUITweaks"] or "Popups & UI Tweaks",
	expanded = false,
	colorizeTitle = false,
	newTagID = "PopupsAndUITweaks",
})

local uiScaleOptions = {
	NoScaling = L["uiScalePresetNone"] or "No scaling",
	Scale4K = "0.3556 (4K)",
	Scale1080p = "0.7111 (1080p)",
	Scale1440p = "0.5333 (1440p)",
	Scale1440p125 = "0.6666 (1440p 125%)",
	Scale1080p125 = "0.8888 (1080p 125%)",
}

local uiScaleOrder = { "NoScaling", "Scale4K", "Scale1440p", "Scale1440p125", "Scale1080p", "Scale1080p125" }

addon.functions.SettingsCreateDropdown(cUIInput, {
	var = "uiScalePreset",
	text = L["uiScalePreset"] or "Login UI scaling",
	list = uiScaleOptions,
	order = uiScaleOrder,
	get = function() return addon.db and addon.db.uiScalePreset or "NoScaling" end,
	set = function(v)
		addon.db.uiScalePreset = v
		ReloadUI()
	end,
	desc = L["uiScalePresetDesc"] or "Automatically applies a preset UI scale when you log in.\n|cffff0000Warning:|r Changing this will reload your UI.",
	parentSection = interfaceExpandable,
})

data = {
	{
		var = "ignoreTalkingHead",
		text = string.format(L["ignoreTalkingHeadN"], HUD_EDIT_MODE_TALKING_HEAD_FRAME_LABEL),
		func = function(v) addon.db["ignoreTalkingHead"] = v end,
		parentSection = interfaceExpandable,
	},
	{
		var = "ffxDeath",
		text = L["ffxDeath"],
		get = function() return getCVarOptionState("ffxDeath") end,
		func = function(value) setCVarOptionState("ffxDeath", value) end,
		default = false,
		parentSection = interfaceExpandable,
	},
	{
		var = "hideZoneText",
		text = L["hideZoneText"],
		func = function(v)
			addon.db["hideZoneText"] = v
			addon.functions.toggleZoneText(addon.db["hideZoneText"])
		end,
		parentSection = interfaceExpandable,
	},
	{
		var = "hideMicroMenuNotificationOverlay",
		text = L["hideMicroMenuNotificationOverlay"],
		desc = L["hideMicroMenuNotificationOverlayDesc"],
		func = function(v)
			addon.db["hideMicroMenuNotificationOverlay"] = v and true or false
			ApplyNotificationOverlaySetting()
		end,
		parentSection = interfaceExpandable,
	},
	{
		var = "hideRaidTools",
		text = L["hideRaidTools"],
		func = function(v)
			addon.db["hideRaidTools"] = v
			addon.functions.updateRaidToolsHook()
		end,
		parentSection = interfaceExpandable,
	},
}
addon.functions.SettingsCreateCheckboxes(cUIInput, data)
----- REGION END

function addon.functions.initUIInput()
	addon.functions.InitDBValue("uiScalePreset", "NoScaling")
	addon.functions.InitDBValue("autoUnwrapMounts", false)
	addon.functions.InitDBValue("hideMicroMenuNotificationOverlay", false)
	UpdateAutoUnwrapWatcher()
	ApplyNotificationOverlaySetting(true)

	if addon.db and addon.db.modifyXPRepBar then
		local height, width, scale = 17, 571, 1
		if addon.db and addon.db.modifyXPRepBarHeight then height = addon.db and addon.db.modifyXPRepBarHeight end
		if addon.db and addon.db.modifyXPRepBarWidth then width = addon.db and addon.db.modifyXPRepBarWidth end
		if addon.db and addon.db.modifyXPRepBarScale then scale = addon.db and addon.db.modifyXPRepBarScale end
		EQOL_UpdateStatusBars(MainStatusTrackingBarContainer, height, width, scale)
		EQOL_UpdateStatusBars(SecondaryStatusTrackingBarContainer, height, width, scale)
	end

	local druidFlightWatcher
	local druidFlightPending

	local function isPlayerDruid()
		local classTag = (addon.variables and addon.variables.unitClass) or select(2, UnitClass("player"))
		return classTag == "DRUID"
	end

	local function evaluateDruidFlightForm()
		if not addon.db or not addon.db["autoCancelDruidFlightForm"] then
			druidFlightPending = nil
			return
		end
		if not isPlayerDruid() then
			druidFlightPending = nil
			return
		end
		if not GetShapeshiftFormID or not IsFlyableArea or not CancelShapeshiftForm then return end
		local formID = GetShapeshiftFormID()
		if formID == 3 and IsFlyableArea() then
			if InCombatLockdown and InCombatLockdown() then
				druidFlightPending = true
				return
			end
			druidFlightPending = nil
			CancelShapeshiftForm()
		else
			druidFlightPending = nil
		end
	end

	local function handleDruidFlightEvent(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			if druidFlightPending then evaluateDruidFlightForm() end
		else
			evaluateDruidFlightForm()
		end
	end

	function addon.functions.updateDruidFlightFormWatcher()
		if not druidFlightWatcher then
			druidFlightWatcher = CreateFrame("Frame")
			druidFlightWatcher:SetScript("OnEvent", handleDruidFlightEvent)
		end
		druidFlightWatcher:UnregisterEvent("MOUNT_JOURNAL_USABILITY_CHANGED")
		druidFlightWatcher:UnregisterEvent("PLAYER_REGEN_ENABLED")
		druidFlightPending = nil
		if addon.db and addon.db["autoCancelDruidFlightForm"] and isPlayerDruid() then
			druidFlightWatcher:RegisterEvent("MOUNT_JOURNAL_USABILITY_CHANGED")
			druidFlightWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
			evaluateDruidFlightForm()
		end
	end

	addon.functions.updateDruidFlightFormWatcher()
end

local eventHandlers = {}

local function registerEvents(frame)
	for event in pairs(eventHandlers) do
		frame:RegisterEvent(event)
	end
end

local function eventHandler(self, event, ...)
	if eventHandlers[event] then eventHandlers[event](...) end
end

local frameLoad = CreateFrame("Frame")

registerEvents(frameLoad)
frameLoad:SetScript("OnEvent", eventHandler)
