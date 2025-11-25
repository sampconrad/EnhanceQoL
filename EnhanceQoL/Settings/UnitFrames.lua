local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local cUnitFrame = addon.functions.SettingsCreateCategory(nil, UNITFRAME_LABEL, nil, "UnitFrame")
addon.SettingsLayout.unitFrameCategory = cUnitFrame
addon.functions.SettingsCreateHeadline(cUnitFrame, COMBAT_TEXT_LABEL)

local data = {
	{
		var = "hideHitIndicatorPlayer",
		text = L["hideHitIndicatorPlayer"],
		func = function(v)
			addon.db["hideHitIndicatorPlayer"] = v
			if v then
				PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator:Hide()
			else
				PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator:Show()
			end
		end,
	},
	{
		var = "hideHitIndicatorPet",
		text = L["hideHitIndicatorPet"],
		func = function(v)
			addon.db["hideHitIndicatorPet"] = v
			if v and PetHitIndicator then PetHitIndicator:Hide() end
		end,
	},
}
addon.functions.SettingsCreateCheckboxes(cUnitFrame, data)

addon.functions.SettingsCreateHeadline(cUnitFrame, L["Health Text"])

addon.functions.SettingsCreateText(cUnitFrame, "|cff99e599" .. string.format(L["HealthTextExplain"], VIDEO_OPTIONS_DISABLED) .. "|r")

addon.functions.SettingsCreateDropdown(cUnitFrame, {
	list = { OFF = VIDEO_OPTIONS_DISABLED, PERCENT = STATUS_TEXT_PERCENT, ABS = STATUS_TEXT_VALUE, BOTH = STATUS_TEXT_BOTH, _order = { "OFF", "PERCENT", "ABS", "BOTH" } },
	text = L["PlayerHealthText"],
	get = function() return addon.db["healthTextPlayerMode"] or "OFF" end,
	set = function(key)
		addon.db["healthTextPlayerMode"] = key
		if addon.HealthText and addon.HealthText.SetMode then addon.HealthText:SetMode("player", addon.db["healthTextPlayerMode"]) end
	end,
	default = "OFF",
	var = "healthTextPlayerMode",
	type = Settings.VarType.String,
	sType = "dropdown",
})
addon.functions.SettingsCreateDropdown(cUnitFrame, {
	list = { OFF = VIDEO_OPTIONS_DISABLED, PERCENT = STATUS_TEXT_PERCENT, ABS = STATUS_TEXT_VALUE, BOTH = STATUS_TEXT_BOTH, _order = { "OFF", "PERCENT", "ABS", "BOTH" } },
	text = L["TargetHealthText"],
	get = function() return addon.db["healthTextTargetMode"] or "OFF" end,
	set = function(key)
		addon.db["healthTextTargetMode"] = key
		if addon.HealthText and addon.HealthText.SetMode then addon.HealthText:SetMode("target", addon.db["healthTextTargetMode"]) end
	end,
	default = "OFF",
	var = "healthTextTargetMode",
	type = Settings.VarType.String,
	sType = "dropdown",
})
addon.functions.SettingsCreateDropdown(cUnitFrame, {
	list = { OFF = VIDEO_OPTIONS_DISABLED, PERCENT = STATUS_TEXT_PERCENT, ABS = STATUS_TEXT_VALUE, BOTH = STATUS_TEXT_BOTH, _order = { "OFF", "PERCENT", "ABS", "BOTH" } },
	text = L["BossHealthText"],
	get = function() return addon.db["healthTextBossMode"] or "OFF" end,
	set = function(key)
		addon.db["healthTextBossMode"] = key
		if addon.HealthText and addon.HealthText.SetMode then addon.HealthText:SetMode("boss", addon.db["healthTextBossMode"]) end
	end,
	default = "OFF",
	var = "healthTextBossMode",
	type = Settings.VarType.String,
	sType = "dropdown",
})

----- REGION END

function addon.functions.initUIInput() end

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
