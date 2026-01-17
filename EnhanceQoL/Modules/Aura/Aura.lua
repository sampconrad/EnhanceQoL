local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")
-- (no direct LSM/AceGUI usage here; UI rendering handled in submodules)

function addon.Aura.functions.init()
	addon.functions.addToTree(nil, {
		value = "bufftracker",
		text = L["BuffTracker"] or "Aura Tracker",
	})
end

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
	if seg == "" or seg == "combat" or seg == "combatassist" then seg = "bufftracker" end

	if seg == "bufftracker" then
		addon.Aura.functions.addBuffTrackerOptions(container)
		addon.Aura.scanBuffs()
	end
end
addon.Aura.functions.BuildSoundTable()
