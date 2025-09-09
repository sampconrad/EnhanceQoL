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

-- spec specific settings for personal resource bars
addon.functions.InitDBValue("personalResourceBarSettings", {})
addon.functions.InitDBValue("personalResourceBarAnchors", {})

-- defaults for new cast tracker categories
addon.functions.InitDBValue("castTrackerBarWidth", 200)
addon.functions.InitDBValue("castTrackerBarHeight", 20)
addon.functions.InitDBValue("castTrackerBarColor", { 1, 0.5, 0, 1 })
addon.functions.InitDBValue("castTrackerBarSound", SOUNDKIT.ALARM_CLOCK_WARNING_3)
addon.functions.InitDBValue("castTrackerBarDirection", "DOWN")
addon.functions.InitDBValue("castTrackerSounds", {})
addon.functions.InitDBValue("castTrackerSoundsEnabled", {})
addon.functions.InitDBValue("castTrackerTextSize", 12)
addon.functions.InitDBValue("castTrackerTextColor", { 1, 1, 1, 1 })
addon.functions.InitDBValue("castTrackerUseAltSpellIcon", false)

addon.functions.InitDBValue("buffTrackerCategories", {
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

addon.functions.InitDBValue("castTrackerCategories", {
	[1] = {
		name = string.format("%s", L["Example"]),
		anchor = { point = "CENTER", x = 0, y = 0 },
		width = addon.db.castTrackerBarWidth,
		height = addon.db.castTrackerBarHeight,
		color = addon.db.castTrackerBarColor,
		textSize = addon.db.castTrackerTextSize,
		textColor = addon.db.castTrackerTextColor,
		direction = addon.db.castTrackerBarDirection,
		barTexture = "DEFAULT",
		spells = {},
	},
})
addon.functions.InitDBValue("castTrackerEnabled", {})
addon.functions.InitDBValue("castTrackerLocked", {})
addon.functions.InitDBValue("castTrackerOrder", {})
addon.functions.InitDBValue("castTrackerSelectedCategory", 1)

if addon.db["castTracker"] and not addon.db["castTrackerCategories"] then
	local old = addon.db["castTracker"]
	addon.db["castTrackerCategories"] = {
		[1] = {
			name = string.format("%s", L["Example"]),
			anchor = old.anchor or { point = "CENTER", x = 0, y = 0 },
			width = old.width or addon.db.castTrackerBarWidth,
			height = old.height or addon.db.castTrackerBarHeight,
			color = old.color or addon.db.castTrackerBarColor,
			textSize = addon.db.castTrackerTextSize,
			textColor = addon.db.castTrackerTextColor,
			direction = old.direction or addon.db.castTrackerBarDirection,
			spells = old.spells or {},
		},
	}
	addon.db["castTracker"] = nil
end

for id, cat in pairs(addon.db["castTrackerCategories"] or {}) do
	cat.anchor = cat.anchor or { point = "CENTER", x = 0, y = 0 }
	cat.width = cat.width or addon.db.castTrackerBarWidth
	cat.height = cat.height or addon.db.castTrackerBarHeight
	cat.color = cat.color or addon.db.castTrackerBarColor
	cat.textSize = cat.textSize or addon.db.castTrackerTextSize
	cat.textColor = cat.textColor or addon.db.castTrackerTextColor
	cat.direction = cat.direction or addon.db.castTrackerBarDirection
	if cat.barTexture == nil then cat.barTexture = "DEFAULT" end
	cat.spells = cat.spells or {}
	addon.db.castTrackerSounds[id] = addon.db.castTrackerSounds[id] or {}
	addon.db.castTrackerSoundsEnabled[id] = addon.db.castTrackerSoundsEnabled[id] or {}
	for sid, spell in pairs(cat.spells) do
		if type(spell) ~= "table" then
			cat.spells[sid] = { altIDs = {} }
			spell = cat.spells[sid]
		else
			spell.altIDs = spell.altIDs or {}
		end
		if spell.sound then
			addon.db.castTrackerSounds[id][sid] = spell.sound
			addon.db.castTrackerSoundsEnabled[id][sid] = true
			spell.sound = nil
		elseif cat.sound then
			addon.db.castTrackerSounds[id][sid] = cat.sound
			addon.db.castTrackerSoundsEnabled[id][sid] = true
		end
		if spell.customTextEnabled == nil then spell.customTextEnabled = false end
		if spell.customText == nil then spell.customText = "" end
	end
	cat.sound = nil
	if addon.db["castTrackerEnabled"][id] == nil then addon.db["castTrackerEnabled"][id] = false end
	if addon.db["castTrackerLocked"][id] == nil then addon.db["castTrackerLocked"][id] = false end
	addon.db["castTrackerOrder"][id] = addon.db["castTrackerOrder"][id] or {}
end

if type(addon.db["castTrackerSelectedCategory"]) ~= "number" then addon.db["castTrackerSelectedCategory"] = 1 end

-- defaults for cooldown notify
addon.functions.InitDBValue("cooldownNotifyCategories", {
	[1] = {
		name = string.format("%s", L["Example"]),
		anchor = { point = "CENTER", x = 0, y = 0 },
		iconSize = 75,
		fadeInTime = 0.3,
		fadeOutTime = 0.7,
		holdTime = 0,
		animScale = 1.5,
		showName = true,
		useAdvancedTracking = true,
		spells = {},
		ignoredSpells = {},
		items = {},
		pets = {},
	},
})
addon.functions.InitDBValue("cooldownNotifyEnabled", {})
addon.functions.InitDBValue("cooldownNotifyLocked", {})
addon.functions.InitDBValue("cooldownNotifyOrder", {})
addon.functions.InitDBValue("cooldownNotifySounds", {})
addon.functions.InitDBValue("cooldownNotifySoundsEnabled", {})
addon.functions.InitDBValue("cooldownNotifyDefaultSound", SOUNDKIT.ALARM_CLOCK_WARNING_3)
addon.functions.InitDBValue("cooldownNotifySelectedCategory", 1)

for _, cat in pairs(addon.db.cooldownNotifyCategories or {}) do
	if cat.useAdvancedTracking == nil then cat.useAdvancedTracking = true end
	cat.spells = cat.spells or {}
	cat.ignoredSpells = cat.ignoredSpells or {}
end

function addon.Aura.functions.BuildSoundTable()
	local LSM = LibStub("LibSharedMedia-3.0")
	local result = {}

	for name, path in pairs(LSM:HashTable("sound")) do
		result[name] = path
	end
	addon.Aura.sounds = result
end
