-- Store the original Blizzard SetupMenu generator for rewrapping
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")
local AceGUI = addon.AceGUI

addon.variables.statusTable.groups["aura"] = true

addon.functions.addToTree(nil, {
	value = "aura",
	text = L["Aura"],
	children = {
		--@debug@
		{ value = "resourcebar", text = DISPLAY_PERSONAL_RESOURCE },
		--@end-debug@
		{ value = "bufftracker", text = L["BuffTracker"] },
		{ value = "casttracker", text = L["CastTracker"] or "Cast Tracker" },
		{ value = "cooldownnotify", text = L["CooldownNotify"] or "Cooldown Notify" },
	},
})

function addon.Aura.functions.treeCallback(container, group)
	container:ReleaseChildren()
	if group == "aura\001resourcebar" then
		addon.Aura.functions.addResourceFrame(container)
	elseif group == "aura\001bufftracker" then
		addon.Aura.functions.addBuffTrackerOptions(container)
		addon.Aura.scanBuffs()
	elseif group == "aura\001casttracker" and addon.Aura.CastTracker and addon.Aura.CastTracker.functions then
		addon.Aura.CastTracker.functions.addCastTrackerOptions(container)

		-- refresh layout in case options changed
		if addon.Aura.CastTracker.functions.Refresh then addon.Aura.CastTracker.functions.Refresh() end
	elseif group == "aura\001cooldownnotify" and addon.Aura.CooldownNotify and addon.Aura.CooldownNotify.functions then
		addon.Aura.CooldownNotify.functions.addCooldownNotifyOptions(container)
	end
end
