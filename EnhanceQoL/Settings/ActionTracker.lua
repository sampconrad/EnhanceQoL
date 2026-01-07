local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local ActionTracker = addon.ActionTracker

local cUI = addon.SettingsLayout.rootUI

local expandable = addon.functions.SettingsCreateExpandableSection(cUI, {
	name = L["ActionTracker"] or "Action Tracker",
	expanded = false,
	colorizeTitle = false,
})

addon.functions.SettingsCreateText(cUI, L["actionTrackerDesc"] or "Shows your most recently cast spells as icons.", {
	parentSection = expandable,
})

addon.functions.SettingsCreateCheckbox(cUI, {
	var = "actionTrackerEnabled",
	text = L["actionTrackerEnabled"] or "Enable Action Tracker",
	func = function(value)
		addon.db["actionTrackerEnabled"] = value and true or false
		if addon.ActionTracker and addon.ActionTracker.OnSettingChanged then addon.ActionTracker:OnSettingChanged(addon.db["actionTrackerEnabled"]) end
	end,
	parentSection = expandable,
})

addon.functions.SettingsCreateText(cUI, "|cffffd700" .. (L["actionTrackerEditModeHint"] or "Use Edit Mode to configure the tracker.") .. "|r", {
	parentSection = expandable,
})

function addon.functions.initActionTracker()
	local defaults = (ActionTracker and ActionTracker.defaults) or {}
	addon.functions.InitDBValue("actionTrackerEnabled", false)
	addon.functions.InitDBValue("actionTrackerMaxIcons", defaults.maxIcons or 5)
	addon.functions.InitDBValue("actionTrackerIconSize", defaults.iconSize or 48)
	addon.functions.InitDBValue("actionTrackerSpacing", defaults.spacing or 0)
	addon.functions.InitDBValue("actionTrackerDirection", defaults.direction or "RIGHT")
	addon.functions.InitDBValue("actionTrackerFadeDuration", defaults.fadeDuration or 0)

	if addon.ActionTracker and addon.ActionTracker.OnSettingChanged then addon.ActionTracker:OnSettingChanged(addon.db["actionTrackerEnabled"]) end
end
