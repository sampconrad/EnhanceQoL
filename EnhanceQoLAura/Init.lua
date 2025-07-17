local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Aura = {}
addon.Aura.functions = {}
addon.Aura.variables = {}
addon.Aura.sounds = {}
addon.LAura = {} -- Locales for aura
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")

-- resource bar defaults
addon.functions.InitDBValue("enableResourceFrame", false)
addon.functions.InitDBValue("personalResourceBarHealthWidth", 200)
addon.functions.InitDBValue("personalResourceBarHealthHeight", 20)
addon.functions.InitDBValue("personalResourceBarManaWidth", 200)
addon.functions.InitDBValue("personalResourceBarManaHeight", 20)

-- spec specific settings for personal resource bars
addon.functions.InitDBValue("personalResourceBarSettings", {})
addon.functions.InitDBValue("personalResourceBarAnchors", {})

addon.functions.InitDBValue("buffTrackerCategories", {
	[1] = {
		name = string.format("%s", L["Example"]),
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
addon.functions.InitDBValue("buffTrackerShowCharges", false)

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
		if buff.showCooldown == nil then buff.showCooldown = false end
		if buff.showCharges == nil then
			buff.showCharges = addon.db["buffTrackerShowCharges"]
			if buff.showCharges == nil then buff.showCharges = false end
		end
	end
end
