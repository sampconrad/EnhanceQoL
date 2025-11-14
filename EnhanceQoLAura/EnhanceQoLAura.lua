-- Store the original Blizzard SetupMenu generator for rewrapping
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")
-- (no direct LSM/AceGUI usage here; UI rendering handled in submodules)

local children = {
	{ value = "bufftracker", text = L["BuffTracker"] }, -- Aura Tracker
}
if not addon.variables.isMidnight then
	table.insert(children, { value = "casttracker", text = L["CastTracker"] or "Cast Tracker" })
	table.insert(children, { value = "cooldownnotify", text = L["CooldownNotify"] or "Cooldown Notify" })
end
-- Group Aura subfeatures under Combat Assist within Combat & Dungeons
addon.functions.addToTree("combat", {
	value = "combatassist",
	text = L["CombatAssist"] or "Combat Assist",
	children = children,
})

function addon.Aura.functions.treeCallback(container, group)
	container:ReleaseChildren()
	-- Normalize group to last segment (supports legacy "aura\001..." and new "combat\001..." paths)
	local seg = group
	local ap = group:find("aura\001", 1, true)
	local cp = group:find("combat\001", 1, true)
	if ap then seg = group:sub(ap + #"aura\001") end
	if cp then seg = group:sub(cp + #"combat\001") end
	-- Strip optional Combat Assist prefix when nested: combat\001combatassist\001...
	if type(seg) == "string" and seg:sub(1, #"combatassist\001") == "combatassist\001" then seg = seg:sub(#"combatassist\001" + 1) end

	if seg == "combatassist" then
		addon.Aura.functions.addResourceFrame(container)
	elseif seg == "bufftracker" then
		addon.Aura.functions.addBuffTrackerOptions(container)
		addon.Aura.scanBuffs()
	elseif seg == "casttracker" and addon.Aura.CastTracker and addon.Aura.CastTracker.functions then
		addon.Aura.CastTracker.functions.addCastTrackerOptions(container)
		if addon.Aura.CastTracker.functions.Refresh then addon.Aura.CastTracker.functions.Refresh() end
	elseif seg == "cooldownnotify" and addon.Aura.CooldownNotify and addon.Aura.CooldownNotify.functions then
		addon.Aura.CooldownNotify.functions.addCooldownNotifyOptions(container)
	end
end
addon.Aura.functions.BuildSoundTable()
