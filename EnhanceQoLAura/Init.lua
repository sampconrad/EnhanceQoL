local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

-- Ensure the order table exists before we manipulate it later
addon.functions.InitDBValue("unitFrameAuraOrder", {})
addon.functions.InitDBValue("unitFrameAuraEnabled", {})

if not addon.db["unitFrameAuraTrackers"] then
	addon.db["unitFrameAuraTrackers"] = {
		[1] = {
			name = "Default",
			anchor = addon.db.unitFrameAuraAnchor or "CENTER",
			direction = addon.db.unitFrameAuraDirection or "RIGHT",
			iconSize = addon.db.unitFrameAuraIconSize or 20,
			spells = addon.db.unitFrameAuraIDs or { -- [235313] = "Blazing Barrier", -- Mage
				[1022] = "Blessing of Protection", -- Paladin
				[6940] = "Blessing of Sacrifice", -- Paladin
				[204018] = "Blessing of Spellwarding", -- Paladin
				[212800] = "Blur", -- Demon Hunter
				[45182] = "Cheating Death", -- Rogue (talent)
				[31224] = "Cloak of Shadows", -- Rogue
				[122278] = "Dampen Harm", -- Monk
				[108416] = "Dark Pact", -- Warlock
				[19236] = "Desperate Prayer", -- Priest
				[290109] = "Desperate Prayer", -- Priest (PvP talent aura)
				[118038] = "Die by the Sword", -- Warrior
				[122783] = "Diffuse Magic", -- Monk
				[47585] = "Dispersion", -- Priest (Shadow)
				[403876] = "Divine Protection", -- Paladin (DF rework)
				[642] = "Divine Shield", -- Paladin
				[184364] = "Enraged Regeneration", -- Warrior (Fury)
				[5277] = "Evasion", -- Rogue
				[586] = "Fade", -- Priest
				[1966] = "Feint", -- Rogue
				[115203] = "Fortifying Brew", -- Monk (Brewmaster/MW talent)
				[383883] = "Fury of the Sun King", -- Priest (Holy talent)
				[47788] = "Guardian Spirit", -- Priest (Holy)
				[11426] = "Ice Barrier", -- Mage (Frost)
				[414658] = "Ice Cold", -- Mage (talent)
				[48792] = "Icebound Fortitude", -- Death Knight
				[102342] = "Ironbark", -- Druid (Resto on target)
				[116849] = "Life Cocoon", -- Monk (Mistweaver)
				[363916] = "Obsidian Scales", -- Evoker
				[33206] = "Pain Suppression", -- Priest (Discipline)
				[235450] = "Prismatic Barrier", -- Mage (Arcane)
				[374348] = "Renewing Blaze", -- Evoker
				[184662] = "Shield of Vengeance", -- Paladin (Ret)
				[23920] = "Spell Reflection", -- Warrior
				[61336] = "Survival Instincts", -- Druid (Feral/Guardian)
				[190514] = "Survival of the Fittest", -- Hunter (BM/MM)
				[190515] = "Survival of the Fittest", -- Hunter (Survival)
				[357170] = "Time Dilation", -- Evoker (Preservation on target)
				[122470] = "Touch of Karma", -- Monk (Windwalker)
				[104773] = "Unending Resolve", -- Warlock
				[173189] = "Unending Resolve", -- Warlock (Glyph / alt aura)
				[401238] = "Writhing Ward", -- Death Knight (talent)
				[114893] = "Stone Bulwark", -- Shaman (PvP talent)
				[462844] = "Stone Bulwark", -- Shaman (DF redesign)
				[65116] = "Stoneform", -- Dwarf racial
				[432496] = "Holy Bulwark", -- Paladin (Holy talent)
				[377842] = "Ursine Vigor", -- Druid (Guardian talent)
				[200851] = "Rage of the Sleeper", -- Rage of the Sleeper
				[22812] = "Barkskin", -- Barkskin,
			},
		},
	}
end

for tId, tracker in pairs(addon.db["unitFrameAuraTrackers"]) do
        if not tracker.anchor then tracker.anchor = "CENTER" end
        if not tracker.direction then tracker.direction = "RIGHT" end
        if not tracker.iconSize then tracker.iconSize = addon.db.unitFrameAuraIconSize or 20 end
        if not tracker.timerScale then tracker.timerScale = addon.db.unitFrameAuraTimerScale or 0.6 end
        if not tracker.spells then tracker.spells = {} end
	addon.db.unitFrameAuraOrder[tId] = addon.db.unitFrameAuraOrder[tId] or {}
	local newSpells = {}
	for id, info in pairs(tracker.spells) do
		if type(info) == "string" then
			local spellData = C_Spell.GetSpellInfo(id)
			newSpells[id] = { name = spellData and spellData.name or info, icon = spellData and spellData.iconID }
		else
			newSpells[id] = info
		end
		if not tContains(addon.db.unitFrameAuraOrder[tId], id) then table.insert(addon.db.unitFrameAuraOrder[tId], id) end
	end
	tracker.spells = newSpells
	if addon.db.unitFrameAuraEnabled[tId] == nil then addon.db.unitFrameAuraEnabled[tId] = true end
end

addon.Aura = {}
addon.Aura.functions = {}
addon.Aura.variables = {}
addon.Aura.sounds = {}
addon.LAura = {} -- Locales for aura

-- Default defensive abilities tracked on unit frames
addon.Aura.defaults = {}

addon.functions.InitDBValue("AuraCooldownTrackerBarHeight", 30)
addon.functions.InitDBValue("AuraSafedZones", {})
addon.functions.InitDBValue("personalResourceBarHealth", {})
addon.functions.InitDBValue("personalResourceBarHealthWidth", 100)
addon.functions.InitDBValue("personalResourceBarHealthHeight", 25)
addon.functions.InitDBValue("personalResourceBarManaWidth", 100)
addon.functions.InitDBValue("personalResourceBarManaHeight", 25)
addon.functions.InitDBValue("buffTrackerCategories", {
	[1] = {
		name = "Example",
		point = "CENTER",
		x = 0,
		y = 0,
		size = 36,
		direction = "RIGHT",
		buffs = {},
	},
})
addon.functions.InitDBValue("buffTrackerEnabled", {})
addon.functions.InitDBValue("buffTrackerLocked", {})
addon.functions.InitDBValue("buffTrackerHidden", {})
addon.functions.InitDBValue("buffTrackerSelectedCategory", 1)
addon.functions.InitDBValue("buffTrackerOrder", {})
addon.functions.InitDBValue("buffTrackerSounds", {})
addon.functions.InitDBValue("buffTrackerSoundsEnabled", {})
addon.functions.InitDBValue("buffTrackerShowStacks", false)
addon.functions.InitDBValue("buffTrackerShowTimerText", true)
addon.functions.InitDBValue("unitFrameAuraIDs", {})
addon.functions.InitDBValue("unitFrameAuraAnchor", "CENTER")
addon.functions.InitDBValue("unitFrameAuraDirection", "RIGHT")
addon.functions.InitDBValue("unitFrameAuraIconSize", 20)
addon.functions.InitDBValue("unitFrameAuraTimerScale", 0.6)
addon.functions.InitDBValue("unitFrameAuraShowTime", false)
addon.functions.InitDBValue("unitFrameAuraShowSwipe", true)
addon.functions.InitDBValue("unitFrameAuraTrackers", nil)
addon.functions.InitDBValue("unitFrameAuraSelectedTracker", 1)

if type(addon.db["buffTrackerSelectedCategory"]) ~= "number" then addon.db["buffTrackerSelectedCategory"] = 1 end

for _, cat in pairs(addon.db["buffTrackerCategories"]) do
	for _, buff in pairs(cat.buffs or {}) do
		if not buff.altIDs then buff.altIDs = {} end
		if buff.showAlways == nil then buff.showAlways = false end
		if buff.glow == nil then buff.glow = false end
		if not buff.trackType then buff.trackType = "BUFF" end
		if not buff.conditions then
			buff.conditions = { join = "AND", conditions = {} }
			if buff.showWhenMissing then table.insert(buff.conditions.conditions, { type = "missing", operator = "==", value = true }) end
			if buff.stackOp and buff.stackVal then table.insert(buff.conditions.conditions, { type = "stack", operator = buff.stackOp, value = buff.stackVal }) end
			if buff.timeOp and buff.timeVal then table.insert(buff.conditions.conditions, { type = "time", operator = buff.timeOp, value = buff.timeVal }) end
		end
		buff.showWhenMissing = nil
		buff.stackOp = nil
		buff.stackVal = nil
		buff.timeOp = nil
		buff.timeVal = nil
		if not buff.allowedSpecs then buff.allowedSpecs = {} end
		if not buff.allowedClasses then buff.allowedClasses = {} end
		if not buff.allowedRoles then buff.allowedRoles = {} end
		if buff.showStacks == nil then
			buff.showStacks = addon.db["buffTrackerShowStacks"]
			if buff.showStacks == nil then buff.showStacks = true end
		end
		if buff.showTimerText == nil then
			buff.showTimerText = addon.db["buffTrackerShowTimerText"]
			if buff.showTimerText == nil then buff.showTimerText = true end
		end
	end
end
