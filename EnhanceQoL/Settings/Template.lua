local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local cChar = addon.functions.SettingsCreateCategory(nil, L["CombatDungeons"])
addon.SettingsLayout.characterInspectCategory = cChar
local data = {}

addon.functions.SettingsCreateCheckboxes(cChar, data)

local eventHandlers = {

	["LFG_LIST_APPLICANT_UPDATED"] = function() end,
}

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
