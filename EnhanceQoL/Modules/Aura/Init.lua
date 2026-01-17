local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Aura = addon.Aura or {}
addon.Aura.functions = addon.Aura.functions or {}
addon.Aura.variables = addon.Aura.variables or {}
addon.Aura.sounds = addon.Aura.sounds or {}
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")

function addon.Aura.functions.InitDB()
	if not addon.db or not addon.functions or not addon.functions.InitDBValue then return end
	local init = addon.functions.InitDBValue

	-- resource bar defaults
	init("enableResourceFrame", false)
	init("resourceBarsHideOutOfCombat", false)
	init("resourceBarsHideMounted", false)
	init("resourceBarsHideVehicle", false)

	-- spec specific settings for personal resource bars
	init("personalResourceBarSettings", {})
	init("personalResourceBarAnchors", {})

	init("buffTrackerCategories", {
		[1] = {
			name = string.format("%s", L["Example"]),
			point = "CENTER",
			x = 0,
			y = 0,
			size = 36,
			spacing = 2,
			direction = "RIGHT",
			buffs = {},
		},
	})
	init("buffTrackerEnabled", {})
	init("buffTrackerLocked", {})
	init("buffTrackerHidden", {})
	init("buffTrackerSelectedCategory", 1)
	init("buffTrackerOrder", {})
	init("buffTrackerSounds", {})
	init("buffTrackerSoundsEnabled", {})
	init("buffTrackerShowStacks", false)
	init("buffTrackerShowTimerText", true)
	init("buffTrackerShowCharges", false)

	if type(addon.db["buffTrackerSelectedCategory"]) ~= "number" then addon.db["buffTrackerSelectedCategory"] = 1 end

	for _, cat in pairs(addon.db["buffTrackerCategories"]) do
		if cat.spacing == nil then cat.spacing = 2 end
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

end

function addon.Aura.functions.BuildSoundTable()
	local LSM = LibStub("LibSharedMedia-3.0")
	local result = {}

	for name, path in pairs(LSM:HashTable("sound")) do
		result[name] = path
	end
	addon.Aura.sounds = result
end
