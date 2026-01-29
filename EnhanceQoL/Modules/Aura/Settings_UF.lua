local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")
local LSM = LibStub("LibSharedMedia-3.0")
local EditMode = addon.EditMode
local settingType = EditMode and EditMode.lib and EditMode.lib.SettingType
local After = C_Timer and C_Timer.After
local GetVisibilityRuleMetadata = addon.functions and addon.functions.GetVisibilityRuleMetadata
local NormalizeUnitFrameVisibilityConfig = addon.functions and addon.functions.NormalizeUnitFrameVisibilityConfig

local UF = addon.Aura and addon.Aura.UF
local UFHelper = addon.Aura and addon.Aura.UFHelper
if not (UF and settingType) then return end

local MIN_WIDTH = 50
local OFFSET_RANGE = 400
local defaultStrata = (_G.PlayerFrame and _G.PlayerFrame.GetFrameStrata and _G.PlayerFrame:GetFrameStrata()) or "MEDIUM"
local defaultLevel = (_G.PlayerFrame and _G.PlayerFrame.GetFrameLevel and _G.PlayerFrame:GetFrameLevel()) or 0

local strataOptions = {
	{ value = "BACKGROUND", label = "BACKGROUND" },
	{ value = "LOW", label = "LOW" },
	{ value = "MEDIUM", label = "MEDIUM" },
	{ value = "HIGH", label = "HIGH" },
	{ value = "DIALOG", label = "DIALOG" },
	{ value = "FULLSCREEN", label = "FULLSCREEN" },
	{ value = "FULLSCREEN_DIALOG", label = "FULLSCREEN_DIALOG" },
	{ value = "TOOLTIP", label = "TOOLTIP" },
}

local textOptions = {
	{ value = "PERCENT", label = L["PERCENT"] or "Percent" },
	{ value = "CURMAX", label = L["Current/Max"] or "Current/Max" },
	{ value = "CURRENT", label = L["Current"] or "Current" },
	{ value = "MAX", label = L["Max"] or "Max" },
	{ value = "CURPERCENT", label = L["Current / Percent"] or "Current / Percent" },
	{ value = "CURMAXPERCENT", label = L["Current/Max Percent"] or "Current/Max Percent" },
	{ value = "MAXPERCENT", label = L["Max / Percent"] or "Max / Percent" },
	{ value = "PERCENTMAX", label = L["Percent / Max"] or "Percent / Max" },
	{ value = "PERCENTCUR", label = L["Percent / Current"] or "Percent / Current" },
	{ value = "PERCENTCURMAX", label = L["Percent / Current / Max"] or "Percent / Current / Max" },
	{ value = "LEVELPERCENT", label = L["Level / Percent"] or "Level / Percent" },
	{ value = "LEVELPERCENTMAX", label = L["Level / Percent / Max"] or "Level / Percent / Max" },
	{ value = "LEVELPERCENTCUR", label = L["Level / Percent / Current"] or "Level / Percent / Current" },
	{ value = "LEVELPERCENTCURMAX", label = L["Level / Percent / Current / Max"] or "Level / Percent / Current / Max" },
	{ value = "NONE", label = NONE or "None" },
}

local delimiterOptions = {
	{ value = " ", label = L["Space"] or "Space" },
	{ value = "  ", label = L["Double Space"] or "Double space" },
	{ value = "/", label = "/" },
	{ value = ":", label = ":" },
	{ value = "-", label = "-" },
	{ value = "–", label = "–" },
	{ value = "|", label = "|" },
	{ value = "•", label = "•" },
	{ value = "·", label = "·" },
}

local function normalizeTextMode(value)
	if value == "CURPERCENTDASH" then return "CURPERCENT" end
	return value
end

local delimiterModeCounts = {
	CURMAX = 1,
	CURPERCENT = 1,
	MAXPERCENT = 1,
	PERCENTMAX = 1,
	PERCENTCUR = 1,
	LEVELPERCENT = 1,
	CURMAXPERCENT = 2,
	PERCENTCURMAX = 2,
	LEVELPERCENTMAX = 2,
	LEVELPERCENTCUR = 2,
	LEVELPERCENTCURMAX = 3,
}

local function textModeDelimiterCount(value)
	local mode = normalizeTextMode(value)
	if type(mode) ~= "string" then return 0 end
	if mode == "PERCENT" or mode == "CURRENT" or mode == "MAX" or mode == "NONE" then return 0 end
	return delimiterModeCounts[mode] or 0
end

local function maxDelimiterCount(leftMode, centerMode, rightMode)
	local count = textModeDelimiterCount(leftMode)
	local centerCount = textModeDelimiterCount(centerMode)
	if centerCount > count then count = centerCount end
	local rightCount = textModeDelimiterCount(rightMode)
	if rightCount > count then count = rightCount end
	return count
end

local outlineOptions = {
	{ value = "NONE", label = L["None"] or "None" },
	{ value = "OUTLINE", label = L["Outline"] or "Outline" },
	{ value = "THICKOUTLINE", label = L["Thick Outline"] or "Thick Outline" },
	{ value = "MONOCHROMEOUTLINE", label = L["Monochrome Outline"] or "Monochrome Outline" },
	{ value = "DROPSHADOW", label = L["Drop shadow"] or "Drop shadow" },
}

local anchorOptions = {
	{ value = "LEFT", label = "LEFT" },
	{ value = "CENTER", label = "CENTER" },
	{ value = "RIGHT", label = "RIGHT" },
}

local classResourceClasses = {
	DEATHKNIGHT = true,
	DRUID = true,
	EVOKER = true,
	MAGE = true,
	MONK = true,
	PALADIN = true,
	ROGUE = true,
	SHAMAN = true,
	WARLOCK = true,
}
local totemFrameClasses = {
	DEATHKNIGHT = true,
	DRUID = true,
	MAGE = true,
	MONK = true,
	PALADIN = true,
	PRIEST = true,
	SHAMAN = true,
	WARLOCK = true,
}

local bossUnitLookup = { boss = true }
for i = 1, (MAX_BOSS_FRAMES or 5) do
	bossUnitLookup["boss" .. i] = true
end
local function isBossUnit(unit) return type(unit) == "string" and bossUnitLookup[unit] == true end

local function defaultsFor(unit)
	if UF.GetDefaults then
		local d = UF.GetDefaults(unit)
		if d then return d end
	end
	if UF.defaults then return UF.defaults[unit] or UF.defaults.player end
	return {}
end
local function defaultFontPath() return (addon.variables and addon.variables.defaultFont) or (LSM and LSM:Fetch("font", LSM.DefaultMedia.font)) or STANDARD_TEXT_FONT end

local pendingDebounce = {}
local pendingTimers = {}
local function debounced(key, fn)
	if not After then return fn and fn() end
	pendingDebounce[key] = fn
	if pendingTimers[key] then return end
	pendingTimers[key] = true
	After(0.05, function()
		pendingTimers[key] = nil
		local cb = pendingDebounce[key]
		pendingDebounce[key] = nil
		if cb then cb() end
	end)
end

local function getDefaultPowerColor(token)
	if PowerBarColor and token then
		local c = PowerBarColor[token]
		if c then
			if c.r then return c.r, c.g, c.b, c.a or 1 end
			if c[1] then return c[1], c[2], c[3], c[4] or 1 end
		end
	end
	return 0.1, 0.45, 1, 1
end

local function getPowerLabel(token)
	if not token then return "" end
	local label = _G[token]
	if not label or label == "" then label = token:gsub("_", " ") end
	return label
end

local mainPowerTokenCache
local function getMainPowerTokens()
	if mainPowerTokenCache then return mainPowerTokenCache end
	local list = {}
	local seen = {}
	local excluded = {
		HOLY_POWER = true,
		MAELSTROM_WEAPON = true,
		MAELSTROM = true,
		SOUL_SHARDS = true,
		CHI = true,
		ESSENCE = true,
		ARCANE_CHARGES = true,
	}
	local powertypeClasses = addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.powertypeClasses
	if type(powertypeClasses) == "table" then
		for _, specs in pairs(powertypeClasses) do
			if type(specs) == "table" then
				for _, info in pairs(specs) do
					local main = info and info.MAIN
					if type(main) == "string" and not seen[main] and not excluded[main] then
						seen[main] = true
						list[#list + 1] = main
					end
				end
			end
		end
	end
	table.sort(list, function(a, b) return tostring(getPowerLabel(a)) < tostring(getPowerLabel(b)) end)
	mainPowerTokenCache = list
	return list
end

local function getPowerOverride(token)
	local overrides = addon.db and addon.db.ufPowerColorOverrides
	return overrides and overrides[token]
end

local function setPowerOverride(token, r, g, b, a)
	addon.db = addon.db or {}
	addon.db.ufPowerColorOverrides = addon.db.ufPowerColorOverrides or {}
	addon.db.ufPowerColorOverrides[token] = { r or 1, g or 1, b or 1, a or 1 }
end

local function clearPowerOverride(token)
	local overrides = addon.db and addon.db.ufPowerColorOverrides
	if not overrides then return end
	overrides[token] = nil
	if not next(overrides) then addon.db.ufPowerColorOverrides = nil end
end

local function getDefaultNPCColor(key)
	if UFHelper and UFHelper.getNPCColorDefault then
		local r, g, b, a = UFHelper.getNPCColorDefault(key)
		if r then return r, g, b, a end
	end
	return 0, 0.8, 0, 1
end

local function getNPCOverride(key)
	local overrides = addon.db and addon.db.ufNPCColorOverrides
	return overrides and overrides[key]
end

local function setNPCOverride(key, r, g, b, a)
	addon.db = addon.db or {}
	addon.db.ufNPCColorOverrides = addon.db.ufNPCColorOverrides or {}
	addon.db.ufNPCColorOverrides[key] = { r or 1, g or 1, b or 1, a or 1 }
end

local function clearNPCOverride(key)
	local overrides = addon.db and addon.db.ufNPCColorOverrides
	if not overrides then return end
	overrides[key] = nil
	if not next(overrides) then addon.db.ufNPCColorOverrides = nil end
end

local npcColorEntries = {
	{ key = "enemy", label = L["UFNPCEnemy"] or "Enemy NPC" },
	{ key = "neutral", label = L["UFNPCNeutral"] or "Neutral" },
	{ key = "friendly", label = L["UFNPCFriendly"] or "Friendly NPC" },
}

local function ensureConfig(unit)
	if UF.GetConfig then return UF.GetConfig(unit) end
	addon.db = addon.db or {}
	addon.db.ufFrames = addon.db.ufFrames or {}
	local key = unit
	if isBossUnit(unit) then key = "boss" end
	if key == "boss" and not addon.db.ufFrames[key] then
		for i = 1, (MAX_BOSS_FRAMES or 5) do
			if addon.db.ufFrames["boss" .. i] then
				addon.db.ufFrames[key] = addon.db.ufFrames["boss" .. i]
				break
			end
		end
	end
	addon.db.ufFrames[key] = addon.db.ufFrames[key] or {}
	return addon.db.ufFrames[key]
end

addon.variables = addon.variables or {}
addon.variables.ufSampleAbsorb = addon.variables.ufSampleAbsorb or {}
addon.variables.ufSampleHealAbsorb = addon.variables.ufSampleHealAbsorb or {}
local sampleAbsorb = addon.variables.ufSampleAbsorb
local sampleHealAbsorb = addon.variables.ufSampleHealAbsorb

local function getValue(unit, path, fallback)
	local cfg = ensureConfig(unit)
	local cur = cfg
	for i = 1, #path do
		if not cur then return fallback end
		cur = cur[path[i]]
		if cur == nil then return fallback end
	end
	return cur
end

local function setValue(unit, path, value)
	local cfg = ensureConfig(unit)
	local cur = cfg
	for i = 1, #path - 1 do
		cur[path[i]] = cur[path[i]] or {}
		cur = cur[path[i]]
	end
	cur[path[#path]] = value
end

local function toRGBA(value, fallback)
	if not value then value = fallback end
	if not value then return 1, 1, 1, 1 end
	if value.r then return value.r or 1, value.g or 1, value.b or 1, value.a or 1 end
	return value[1] or (fallback and fallback[1]) or 1, value[2] or (fallback and fallback[2]) or 1, value[3] or (fallback and fallback[3]) or 1, value[4] or (fallback and fallback[4]) or 1
end

local function setColor(unit, path, r, g, b, a)
	local _, _, _, curA = toRGBA(getValue(unit, path))
	setValue(unit, path, { r or 1, g or 1, b or 1, a or curA or 1 })
end

local function canRefresh() return addon.db ~= nil and addon.Aura and addon.Aura.UFInitialized end

local function refresh(unit)
	if not canRefresh() then return end
	if UF.RefreshUnit and unit then
		UF.RefreshUnit(unit)
	elseif UF.Refresh then
		UF.Refresh()
	end
end

local function refreshSettingsUI()
	local lib = addon.EditModeLib
	if lib and lib.internal and lib.internal.RefreshSettings then lib.internal:RefreshSettings() end
	if lib and lib.internal and lib.internal.RefreshSettingValues then lib.internal:RefreshSettingValues() end
end

local frameIds = {
	player = "EQOL_UF_Player",
	target = "EQOL_UF_Target",
	targettarget = "EQOL_UF_ToT",
	pet = "EQOL_UF_Pet",
	focus = "EQOL_UF_Focus",
	boss = "EQOL_UF_Boss",
}

local function refreshEditModeFrame(unit)
	if not (EditMode and EditMode.RefreshFrame) then return end
	local frameId = frameIds[unit]
	if frameId then EditMode:RefreshFrame(frameId) end
end

local copyDialogKey = "EQOL_UF_COPY_SETTINGS"
local copyFrameLabels = {
	player = L["UFPlayerFrame"] or PLAYER,
	target = L["UFTargetFrame"] or TARGET,
	targettarget = L["UFToTFrame"] or "Target of Target",
	pet = L["UFPetFrame"] or PET,
	focus = L["UFFocusFrame"] or FOCUS,
	boss = L["UFBossFrame"] or BOSS or "Boss Frame",
}

local function availableCopySources(unit)
	local opts = {}
	for key, label in pairs(copyFrameLabels) do
		if key ~= unit then opts[#opts + 1] = { value = key, label = label } end
	end
	table.sort(opts, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return opts
end

local function getVisibilityRuleOptions(unit)
	if not GetVisibilityRuleMetadata then return {} end
	local options = {}
	local unitToken = unit
	for key, data in pairs(GetVisibilityRuleMetadata() or {}) do
		local allowed = data.appliesTo and data.appliesTo.frame
		if allowed and data.unitRequirement and data.unitRequirement ~= unitToken then allowed = false end
		if allowed and unitToken == "player" and key == "PLAYER_HEALTH_NOT_FULL" then allowed = false end
		if allowed then options[#options + 1] = { value = key, label = data.label or key, order = data.order or 999 } end
	end
	table.sort(options, function(a, b)
		if a.order == b.order then return tostring(a.label) < tostring(b.label) end
		return a.order < b.order
	end)
	return options
end

local function showCopySettingsPopup(fromUnit, toUnit)
	if not (fromUnit and toUnit and UF.CopySettings) then return end
	StaticPopupDialogs[copyDialogKey] = StaticPopupDialogs[copyDialogKey]
		or {
			text = "%s",
			button1 = L["Copy"] or ACCEPT,
			button2 = CANCEL,
			hideOnEscape = true,
			timeout = 0,
			whileDead = 1,
			preferredIndex = 3,
			OnAccept = function(self, data)
				local payload = data or self.data
				if payload and payload.from and payload.to and UF.CopySettings then
					if UF.CopySettings(payload.from, payload.to, { keepAnchor = true, keepEnabled = true }) then
						refresh(payload.to)
						refreshSettingsUI()
					end
				end
			end,
		}
	local dialog = StaticPopupDialogs[copyDialogKey]
	if not dialog then return end
	local fromLabel = copyFrameLabels[fromUnit] or fromUnit
	local toLabel = copyFrameLabels[toUnit] or toUnit
	dialog.text = string.format("%s\n\n%s -> %s", L["Copy settings"] or "Copy settings", fromLabel, toLabel)
	StaticPopup_Show(copyDialogKey, nil, nil, { from = fromUnit, to = toUnit })
end

local function hideFrameReset(frame)
	local lib = addon.EditModeLib
	if frame and lib and lib.SetFrameSettingsResetVisible then lib:SetFrameSettingsResetVisible(frame, false) end
end

local function fontOptions()
	local list = {}
	local defaultPath = defaultFontPath()
	if not LSM then return list end
	local hash = LSM:HashTable("font") or {}
	local hasDefault = false
	for name, path in pairs(hash) do
		if type(path) == "string" and path ~= "" then list[#list + 1] = { value = path, label = tostring(name) } end
		if path == defaultPath then hasDefault = true end
	end
	if defaultPath and not hasDefault then list[#list + 1] = { value = defaultPath, label = L["Default"] or "Default" } end
	table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return list
end

local function textureOptions()
	local list = {}
	local seen = {}
	local function add(value, label)
		local lv = tostring(value or ""):lower()
		if lv == "" or seen[lv] then return end
		seen[lv] = true
		list[#list + 1] = { value = value, label = label }
	end
	add("DEFAULT", "Default (Blizzard)")
	add("SOLID", "Solid")
	if not LSM then return list end
	local hash = LSM:HashTable("statusbar") or {}
	for name, path in pairs(hash) do
		if type(path) == "string" and path ~= "" then add(name, tostring(name)) end
	end
	table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return list
end

local function borderOptions()
	local list = {}
	local seen = {}
	local function add(value, label)
		local lv = tostring(value or ""):lower()
		if lv == "" or seen[lv] then return end
		seen[lv] = true
		list[#list + 1] = { value = value, label = label }
	end
	add("DEFAULT", L["Default"] or "Default")
	if not LSM then return list end
	local hash = LSM:HashTable("border") or {}
	for name, path in pairs(hash) do
		if type(path) == "string" and path ~= "" then add(name, tostring(name)) end
	end
	table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return list
end

local function radioDropdown(name, options, getter, setter, default, parentId)
	return {
		name = name,
		kind = settingType.Dropdown,
		height = 180,
		parentId = parentId,
		default = default,
		generator = function(_, root)
			local opts = type(options) == "function" and options() or options
			if type(opts) ~= "table" then return end
			for _, opt in ipairs(opts) do
				local value = opt.value
				local label = opt.label
				root:CreateRadio(label, function() return getter() == value end, function() setter(value) end)
			end
		end,
	}
end

local function checkboxDropdown(name, options, getter, setter, default, parentId)
	return {
		name = name,
		kind = settingType.Dropdown,
		height = 180,
		parentId = parentId,
		default = default,
		generator = function(_, root)
			local opts = type(options) == "function" and options() or options
			if type(opts) ~= "table" then return end
			for _, opt in ipairs(opts) do
				local value = opt.value
				local label = opt.label
				root:CreateCheckbox(label, function() return getter() == value end, function()
					if getter() ~= value then setter(value) end
				end)
			end
		end,
	}
end

local function multiDropdown(name, options, isSelected, setSelected, default, parentId, isEnabled)
	return {
		name = name,
		kind = settingType.Dropdown,
		height = 200,
		parentId = parentId,
		default = default,
		generator = function(_, root)
			local opts = type(options) == "function" and options() or options
			if type(opts) ~= "table" then return end
			for _, opt in ipairs(opts) do
				root:CreateCheckbox(opt.label, function() return isSelected(opt.value) end, function() setSelected(opt.value, not isSelected(opt.value)) end)
			end
		end,
		isEnabled = isEnabled,
	}
end

local function slider(name, minVal, maxVal, step, getter, setter, default, parentId, allowInput, formatter)
	return {
		name = name,
		kind = settingType.Slider,
		parentId = parentId,
		minValue = minVal,
		maxValue = maxVal,
		valueStep = step,
		allowInput = allowInput,
		default = default,
		get = function() return getter() end,
		set = function(_, value) setter(value) end,
		formatter = formatter,
	}
end

local function checkbox(name, getter, setter, default, parentId, isEnabled)
	return {
		name = name,
		kind = settingType.Checkbox,
		parentId = parentId,
		default = default,
		get = function() return getter() end,
		set = function(_, value) setter(value) end,
		isEnabled = isEnabled,
	}
end

local function checkboxColor(args)
	return {
		name = args.name,
		kind = settingType.CheckboxColor,
		parentId = args.parentId,
		default = args.defaultChecked,
		get = function() return args.isChecked() end,
		set = function(_, value) args.onChecked(value) end,
		colorDefault = args.colorDefault,
		colorGet = function()
			local r, g, b, a = args.getColor()
			return { r = r, g = g, b = b, a = a }
		end,
		colorSet = function(_, value) args.onColor(value) end,
		hasOpacity = true,
	}
end

local function anchorUsesUIParent(unit)
	local cfg = ensureConfig(unit)
	local def = defaultsFor(unit)
	local anchor = (cfg and cfg.anchor) or (def and def.anchor) or {}
	local rel = anchor.relativeTo or anchor.relativeFrame or "UIParent"
	return rel == "UIParent"
end

local function calcLayout(unit, frame)
	local cfg = ensureConfig(unit)
	local def = defaultsFor(unit)
	local anchor = cfg.anchor or def.anchor or {}
	local powerEnabled = getValue(unit, { "power", "enabled" }, (def.power and def.power.enabled) ~= false)
	local pcfg = cfg.power or {}
	local powerDetached = powerEnabled and pcfg.detached == true
	local statusDef = def.status or {}
	local showName = getValue(unit, { "status", "enabled" }, statusDef.enabled ~= false) ~= false
	local showLevel = getValue(unit, { "status", "levelEnabled" }, statusDef.levelEnabled ~= false) ~= false
	local ciDef = statusDef.combatIndicator or {}
	local showCombat = unit == "player" and getValue(unit, { "status", "combatIndicator", "enabled" }, ciDef.enabled ~= false) ~= false
	local usDef = statusDef.unitStatus or {}
	local showUnitStatus = getValue(unit, { "status", "unitStatus", "enabled" }, usDef.enabled == true) == true
	local showStatus = showName or showLevel or showCombat or showUnitStatus
	local statusHeight = showStatus and (cfg.statusHeight or def.statusHeight or 18) or 0
	local borderOffset = 0
	if cfg.border and cfg.border.enabled then
		borderOffset = cfg.border.offset
		if borderOffset == nil then borderOffset = cfg.border.edgeSize or 1 end
		borderOffset = math.max(0, borderOffset or 0)
	end

	local portraitDef = def.portrait or {}
	local portraitCfg = cfg.portrait or {}
	local portraitEnabled = portraitCfg.enabled
	if portraitEnabled == nil then portraitEnabled = portraitDef.enabled end
	portraitEnabled = portraitEnabled == true

	local healthHeight = cfg.healthHeight or def.healthHeight or 24
	local powerHeight = powerEnabled and (cfg.powerHeight or def.powerHeight or 16) or 0
	local stackHeight = healthHeight + (powerDetached and 0 or powerHeight)
	local portraitInnerHeight = stackHeight
	local portraitSize = portraitEnabled and math.max(1, portraitInnerHeight) or 0

	local separatorEnabled = false
	local separatorSize = 0
	if portraitEnabled and cfg.enabled ~= false then
		local borderCfg = cfg.border or {}
		if borderCfg.enabled == true then
			local sdef = portraitDef.separator or {}
			local scfg = portraitCfg.separator or {}
			local enabled = scfg.enabled
			if enabled == nil then enabled = sdef.enabled end
			if enabled == nil then enabled = true end
			if enabled == true then
				local size = scfg.size
				if size == nil then size = sdef.size end
				if not size or size <= 0 then size = borderCfg.edgeSize or 1 end
				separatorEnabled = true
				separatorSize = math.max(1, size or 1)
			end
		end
	end

	local portraitSpace = portraitEnabled and (portraitSize + (separatorEnabled and separatorSize or 0)) or 0
	local width = (cfg.width or def.width or frame:GetWidth() or 200) + borderOffset * 2 + portraitSpace
	local height = statusHeight + stackHeight + borderOffset * 2
	return {
		point = anchor.point or "CENTER",
		relativePoint = anchor.relativePoint or anchor.point or "CENTER",
		x = anchor.x or 0,
		y = anchor.y or 0,
		width = width,
		height = height,
	}
end

local function buildUnitSettings(unit)
	local def = defaultsFor(unit)
	local list = {}
	local isBoss = isBossUnit(unit)
	local refreshFunc = refresh
	local function refreshSelf()
		if isBoss and UF.UpdateBossFrames then
			UF.UpdateBossFrames(true)
		else
			refreshFunc(unit)
		end
	end
	local refresh = refreshSelf
	local isPlayer = unit == "player"
	local isPet = unit == "pet"
	local classHasResource = isPlayer and classResourceClasses[addon.variables and addon.variables.unitClass]
	local classHasTotemFrame = isPlayer and totemFrameClasses[addon.variables and addon.variables.unitClass]
	local copyOptions = availableCopySources(unit)
	local visibilityOptions = getVisibilityRuleOptions(unit)
	local function getVisibilityConfig()
		local cfg = ensureConfig(unit)
		local raw = cfg and cfg.visibility
		if NormalizeUnitFrameVisibilityConfig then return NormalizeUnitFrameVisibilityConfig(nil, raw, { skipSave = true, ignoreOverride = true }) end
		if type(raw) == "table" then return raw end
		return nil
	end
	local function isVisibilityRuleSelected(key)
		local config = getVisibilityConfig()
		return config and config[key] == true
	end
	local function setVisibilityRule(key, shouldSelect)
		local cfg = ensureConfig(unit)
		local working = type(cfg.visibility) == "table" and cfg.visibility or {}
		if key == "ALWAYS_HIDDEN" and shouldSelect then
			working = { ALWAYS_HIDDEN = true }
		elseif shouldSelect then
			working[key] = true
			working.ALWAYS_HIDDEN = nil
		else
			working[key] = nil
		end
		if not next(working) then working = nil end
		cfg.visibility = working
		if UF and UF.ApplyVisibilityRules then UF.ApplyVisibilityRules(unit) end
		refreshSettingsUI()
	end
	local function getVisibilityFadeValue()
		local cfg = ensureConfig(unit)
		local fade = cfg and cfg.visibilityFade
		local value = type(fade) == "number" and fade or nil
		if value == nil and addon and addon.functions and addon.functions.GetFrameFadedAlpha then value = addon.functions.GetFrameFadedAlpha() end
		if type(value) ~= "number" then value = 0 end
		if value < 0 then value = 0 end
		if value > 1 then value = 1 end
		return math.floor((value * 100) + 0.5)
	end
	local function setVisibilityFadeValue(value)
		local cfg = ensureConfig(unit)
		local pct = tonumber(value)
		if pct == nil then pct = 0 end
		if pct < 0 then pct = 0 end
		if pct > 100 then pct = 100 end
		cfg.visibilityFade = pct / 100
		if UF and UF.ApplyVisibilityRules then UF.ApplyVisibilityRules(unit) end
	end

	list[#list + 1] = { name = SETTINGS or "Settings", kind = settingType.Collapsible, id = "utility", defaultCollapsed = true }

	list[#list + 1] = {
		name = L["Copy settings"] or "Copy settings",
		kind = settingType.Dropdown,
		height = 180,
		parentId = "utility",
		default = nil,
		generator = function(_, root)
			for _, opt in ipairs(copyOptions) do
				root:CreateRadio(opt.label, function() return false end, function() showCopySettingsPopup(opt.value, unit) end)
			end
		end,
		isEnabled = function() return #copyOptions > 0 end,
	}

	list[#list + 1] = { name = L["Frame"] or "Frame", kind = settingType.Collapsible, id = "frame", defaultCollapsed = false }

	local function isTooltipEnabled() return getValue(unit, { "showTooltip" }, def.showTooltip or false) == true end

	list[#list + 1] = checkbox(L["UFShowTooltip"] or "Show unit tooltip", isTooltipEnabled, function(val)
		setValue(unit, { "showTooltip" }, val and true or false)
		refreshSelf()
		refreshSettingsUI()
	end, def.showTooltip or false, "frame")

	list[#list + 1] = checkbox(
		L["UFTooltipUseEditMode"] or "Use Edit Mode tooltip position",
		function() return getValue(unit, { "tooltipUseEditMode" }, def.tooltipUseEditMode == true) == true end,
		function(val) setValue(unit, { "tooltipUseEditMode" }, val and true or false) end,
		def.tooltipUseEditMode == true,
		"frame",
		isTooltipEnabled
	)

	if #visibilityOptions > 0 then
		list[#list + 1] = multiDropdown(L["Show when"] or "Show when", visibilityOptions, isVisibilityRuleSelected, setVisibilityRule, nil, "frame")
		list[#list + 1] = slider(
			OPACITY or "Opacity",
			0,
			100,
			1,
			function() return getVisibilityFadeValue() end,
			function(val) setVisibilityFadeValue(val) end,
			0,
			"frame",
			true,
			function(val) return tostring(val) .. "%" end
		)
	end

	list[#list + 1] = slider(L["UFWidth"] or "Frame width", MIN_WIDTH, 800, 1, function() return getValue(unit, { "width" }, def.width or MIN_WIDTH) end, function(val)
		setValue(unit, { "width" }, math.max(MIN_WIDTH, val or MIN_WIDTH))
		refreshSelf()
	end, def.width or MIN_WIDTH, "frame", true)

	if isBoss then
		list[#list + 1] = slider(L["UFBossSpacing"] or "Boss spacing", 0, 100, 1, function() return getValue(unit, { "spacing" }, def.spacing or 4) end, function(val)
			setValue(unit, { "spacing" }, val or def.spacing or 4)
			refreshSelf()
		end, def.spacing or 4, "frame", true)

		local growthOpts = {
			{ value = "DOWN", label = L["Down"] or "Down" },
			{ value = "UP", label = L["Up"] or "Up" },
		}
		list[#list + 1] = radioDropdown(L["UFBossGrowth"] or "Growth direction", growthOpts, function() return (getValue(unit, { "growth" }, def.growth or "DOWN") or "DOWN"):upper() end, function(val)
			setValue(unit, { "growth" }, (val or "DOWN"):upper())
			refreshSelf()
		end, (def.growth or "DOWN"):upper(), "frame")
	end

	list[#list + 1] = radioDropdown(L["UFStrata"] or "Frame strata", strataOptions, function() return getValue(unit, { "strata" }, def.strata or defaultStrata or "") end, function(val)
		setValue(unit, { "strata" }, val ~= "" and val or nil)
		refreshSelf()
	end, def.strata or defaultStrata or "", "frame")

	list[#list + 1] = slider(L["UFFrameLevel"] or "Frame level", 0, 50, 1, function() return getValue(unit, { "frameLevel" }, def.frameLevel or defaultLevel) end, function(val)
		debounced(unit .. "_frameLevel", function()
			setValue(unit, { "frameLevel" }, val or defaultLevel)
			refreshSelf()
		end)
	end, def.frameLevel or defaultLevel, "frame", true)

	list[#list + 1] = checkboxColor({
		name = L["UFShowBorder"] or "Show border",
		parentId = "frame",
		defaultChecked = (def.border and def.border.enabled) ~= false,
		isChecked = function()
			local border = getValue(unit, { "border" }, def.border or {})
			return border.enabled ~= false
		end,
		onChecked = function(val)
			local border = getValue(unit, { "border" }, def.border or {})
			border.enabled = val and true or false
			setValue(unit, { "border" }, border)
			refresh()
			refreshSettingsUI()
		end,
		getColor = function()
			local border = getValue(unit, { "border" }, def.border or {})
			return toRGBA(border.color, def.border and def.border.color or { 0, 0, 0, 0.8 })
		end,
		onColor = function(color)
			local border = getValue(unit, { "border" }, def.border or {})
			border.color = { color.r, color.g, color.b, color.a }
			setValue(unit, { "border" }, border)
			refresh()
			refreshSettingsUI()
		end,
		colorDefault = {
			r = (def.border and def.border.color and def.border.color[1]) or 0,
			g = (def.border and def.border.color and def.border.color[2]) or 0,
			b = (def.border and def.border.color and def.border.color[3]) or 0,
			a = (def.border and def.border.color and def.border.color[4]) or 0.8,
		},
	})

	local function isBorderEnabled() return getValue(unit, { "border", "enabled" }, (def.border and def.border.enabled) ~= false) ~= false end

	local borderTexture = checkboxDropdown(L["Border texture"] or "Border texture", borderOptions, function()
		local border = getValue(unit, { "border" }, def.border or {})
		return border.texture or (def.border and def.border.texture) or "DEFAULT"
	end, function(val)
		local border = getValue(unit, { "border" }, def.border or {})
		border.texture = val or "DEFAULT"
		setValue(unit, { "border" }, border)
		refresh()
	end, (def.border and def.border.texture) or "DEFAULT", "frame")
	borderTexture.isEnabled = isBorderEnabled
	list[#list + 1] = borderTexture

	local borderSizeSetting = slider(L["UFBorderSize"] or "Border size", 1, 64, 1, function()
		local border = getValue(unit, { "border" }, def.border or {})
		return border.edgeSize or 1
	end, function(val)
		debounced(unit .. "_borderEdge", function()
			local border = getValue(unit, { "border" }, def.border or {})
			border.edgeSize = val or 1
			setValue(unit, { "border" }, border)
			refresh()
		end)
	end, max(1, (def.border and def.border.edgeSize) or 1), "frame", true)
	borderSizeSetting.isEnabled = isBorderEnabled
	list[#list + 1] = borderSizeSetting

	local borderOffsetSetting = slider(L["Border offset"] or "Border offset", 0, 64, 1, function()
		local border = getValue(unit, { "border" }, def.border or {})
		if border.offset == nil then return border.edgeSize or 1 end
		return border.offset
	end, function(val)
		debounced(unit .. "_borderOffset", function()
			local border = getValue(unit, { "border" }, def.border or {})
			border.offset = val or 0
			setValue(unit, { "border" }, border)
			refresh()
		end)
	end, (def.border and def.border.offset) or (def.border and def.border.edgeSize) or 1, "frame", true)
	borderOffsetSetting.isEnabled = isBorderEnabled
	list[#list + 1] = borderOffsetSetting

	list[#list + 1] = checkbox(
		L["UFDetachedPowerBorder"] or "Show border for detached power bar",
		function() return getValue(unit, { "border", "detachedPower" }, def.border and def.border.detachedPower == true) == true end,
		function(val)
			local border = getValue(unit, { "border" }, def.border or {})
			border.detachedPower = val and true or false
			setValue(unit, { "border" }, border)
			refresh()
		end,
		def.border and def.border.detachedPower == true,
		"frame"
	)

	local detachedBorderTexture = checkboxDropdown(L["UFDetachedPowerBorderTexture"] or "Detached power border texture", borderOptions, function()
		local border = getValue(unit, { "border" }, def.border or {})
		return border.detachedPowerTexture or border.texture or (def.border and def.border.texture) or "DEFAULT"
	end, function(val)
		local border = getValue(unit, { "border" }, def.border or {})
		border.detachedPowerTexture = val or "DEFAULT"
		setValue(unit, { "border" }, border)
		refresh()
	end, (def.border and def.border.detachedPowerTexture) or (def.border and def.border.texture) or "DEFAULT", "frame")
	list[#list + 1] = detachedBorderTexture

	local detachedBorderSize = slider(L["UFDetachedPowerBorderSize"] or "Detached power border size", 1, 64, 1, function()
		local border = getValue(unit, { "border" }, def.border or {})
		return border.detachedPowerSize or border.edgeSize or 1
	end, function(val)
		debounced(unit .. "_detachedPowerBorderSize", function()
			local border = getValue(unit, { "border" }, def.border or {})
			border.detachedPowerSize = val or 1
			setValue(unit, { "border" }, border)
			refresh()
		end)
	end, (def.border and def.border.detachedPowerSize) or (def.border and def.border.edgeSize) or 1, "frame", true)
	list[#list + 1] = detachedBorderSize

	local detachedBorderOffset = slider(L["UFDetachedPowerBorderOffset"] or "Detached power border offset", 0, 64, 1, function()
		local border = getValue(unit, { "border" }, def.border or {})
		if border.detachedPowerOffset == nil then
			if border.offset ~= nil then return border.offset end
			return border.edgeSize or 1
		end
		return border.detachedPowerOffset
	end, function(val)
		debounced(unit .. "_detachedPowerBorderOffset", function()
			local border = getValue(unit, { "border" }, def.border or {})
			border.detachedPowerOffset = val or 0
			setValue(unit, { "border" }, border)
			refresh()
		end)
	end, (def.border and def.border.detachedPowerOffset) or (def.border and def.border.offset) or (def.border and def.border.edgeSize) or 1, "frame", true)
	list[#list + 1] = detachedBorderOffset

	local powerDefaults = def.power or {}
	local detachedStrataOptions = { { value = "", label = L["Default"] or "Default" } }
	for i = 1, #strataOptions do
		detachedStrataOptions[#detachedStrataOptions + 1] = strataOptions[i]
	end
	local detachedPowerStrata = radioDropdown(
		L["UFDetachedPowerStrata"] or "Detached power bar strata",
		detachedStrataOptions,
		function() return getValue(unit, { "power", "detachedStrata" }, powerDefaults.detachedStrata or "") end,
		function(val)
			if val == "" then val = nil end
			setValue(unit, { "power", "detachedStrata" }, val)
			refresh()
		end,
		powerDefaults.detachedStrata or "",
		"frame",
		true
	)
	list[#list + 1] = detachedPowerStrata

	local detachedPowerLevelOffset = slider(
		L["UFDetachedPowerLevelOffset"] or "Detached power bar level offset",
		0,
		50,
		1,
		function() return getValue(unit, { "power", "detachedFrameLevelOffset" }, powerDefaults.detachedFrameLevelOffset or 5) end,
		function(val)
			debounced(unit .. "_detachedPowerLevelOffset", function()
				setValue(unit, { "power", "detachedFrameLevelOffset" }, val or powerDefaults.detachedFrameLevelOffset or 5)
				refresh()
			end)
		end,
		powerDefaults.detachedFrameLevelOffset or 5,
		"frame",
		true
	)
	list[#list + 1] = detachedPowerLevelOffset

	local highlightDef = def.highlight or {}
	list[#list + 1] = checkboxColor({
		name = L["UFHighlightBorder"] or "Highlight border",
		parentId = "frame",
		defaultChecked = highlightDef.enabled == true,
		isChecked = function() return getValue(unit, { "highlight", "enabled" }, highlightDef.enabled == true) == true end,
		onChecked = function(val)
			local highlight = getValue(unit, { "highlight" }, highlightDef)
			highlight.enabled = val and true or false
			setValue(unit, { "highlight" }, highlight)
			refresh()
			refreshSettingsUI()
		end,
		getColor = function()
			local highlight = getValue(unit, { "highlight" }, highlightDef)
			return toRGBA(highlight.color, highlightDef.color or { 1, 0, 0, 1 })
		end,
		onColor = function(color)
			local highlight = getValue(unit, { "highlight" }, highlightDef)
			highlight.color = { color.r, color.g, color.b, color.a }
			setValue(unit, { "highlight" }, highlight)
			refresh()
			refreshSettingsUI()
		end,
		colorDefault = {
			r = (highlightDef.color and highlightDef.color[1]) or 1,
			g = (highlightDef.color and highlightDef.color[2]) or 0,
			b = (highlightDef.color and highlightDef.color[3]) or 0,
			a = (highlightDef.color and highlightDef.color[4]) or 1,
		},
	})

	local function isHighlightEnabled() return getValue(unit, { "highlight", "enabled" }, highlightDef.enabled == true) == true end
	local function isHighlightAggroEnabled() return isHighlightEnabled() and (isPlayer or isPet) end

	list[#list + 1] = checkbox(
		L["UFHighlightMouseover"] or "Highlight on mouseover",
		function() return getValue(unit, { "highlight", "mouseover" }, highlightDef.mouseover ~= false) == true end,
		function(val)
			setValue(unit, { "highlight", "mouseover" }, val and true or false)
			refresh()
		end,
		highlightDef.mouseover ~= false,
		"frame",
		isHighlightEnabled
	)

	if isPlayer or isPet then
		list[#list + 1] = checkbox(L["UFHighlightAggro"] or "Highlight on aggro", function() return getValue(unit, { "highlight", "aggro" }, highlightDef.aggro ~= false) == true end, function(val)
			setValue(unit, { "highlight", "aggro" }, val and true or false)
			refresh()
		end, highlightDef.aggro ~= false, "frame", isHighlightAggroEnabled)
	end

	local highlightTexture = checkboxDropdown(
		L["UFHighlightTexture"] or "Highlight texture",
		borderOptions,
		function() return getValue(unit, { "highlight", "texture" }, highlightDef.texture or "DEFAULT") end,
		function(val)
			setValue(unit, { "highlight", "texture" }, val or "DEFAULT")
			refresh()
		end,
		highlightDef.texture or "DEFAULT",
		"frame"
	)
	highlightTexture.isEnabled = isHighlightEnabled
	list[#list + 1] = highlightTexture

	local highlightSizeSetting = slider(L["UFHighlightSize"] or "Highlight size", 1, 64, 1, function() return getValue(unit, { "highlight", "size" }, highlightDef.size or 2) end, function(val)
		debounced(unit .. "_highlightSize", function()
			setValue(unit, { "highlight", "size" }, val or highlightDef.size or 2)
			refresh()
		end)
	end, highlightDef.size or 2, "frame", true)
	highlightSizeSetting.isEnabled = isHighlightEnabled
	list[#list + 1] = highlightSizeSetting

	local portraitDef = def.portrait or {}
	list[#list + 1] = { name = L["UFPortrait"] or "Portrait", kind = settingType.Collapsible, id = "portrait", defaultCollapsed = true }
	local function isPortraitEnabled() return getValue(unit, { "portrait", "enabled" }, portraitDef.enabled == true) == true end

	list[#list + 1] = checkbox(L["UFPortraitEnable"] or "Enable portrait", isPortraitEnabled, function(val)
		setValue(unit, { "portrait", "enabled" }, val and true or false)
		refreshSelf()
		refreshSettingsUI()
	end, portraitDef.enabled == true, "portrait")

	local portraitSideOptions = {
		{ value = "LEFT", label = HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_DIRECTION_LEFT or "Left" },
		{ value = "RIGHT", label = HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_DIRECTION_RIGHT or "Right" },
	}
	local portraitSide = radioDropdown(
		L["UFPortraitSide"] or "Portrait side",
		portraitSideOptions,
		function() return (getValue(unit, { "portrait", "side" }, portraitDef.side or "LEFT") or "LEFT"):upper() end,
		function(val)
			setValue(unit, { "portrait", "side" }, (val or "LEFT"):upper())
			refreshSelf()
		end,
		(portraitDef.side or "LEFT"):upper(),
		"portrait"
	)
	portraitSide.isEnabled = isPortraitEnabled
	list[#list + 1] = portraitSide

	local portraitSquareBackground = checkbox(
		L["UFPortraitSquareBackground"] or "Force square background",
		function() return getValue(unit, { "portrait", "squareBackground" }, portraitDef.squareBackground == true) == true end,
		function(val)
			setValue(unit, { "portrait", "squareBackground" }, val and true or false)
			refreshSelf()
		end,
		portraitDef.squareBackground == true,
		"portrait"
	)
	portraitSquareBackground.isEnabled = isPortraitEnabled
	list[#list + 1] = portraitSquareBackground

	local portraitSeparatorDef = portraitDef.separator or {}
	local function isPortraitSeparatorEnabled()
		local enabled = getValue(unit, { "portrait", "separator", "enabled" }, portraitSeparatorDef.enabled)
		if enabled == nil then enabled = true end
		return enabled == true
	end

	list[#list + 1] = checkbox(L["UFPortraitSeparatorEnable"] or "Show portrait separator", isPortraitSeparatorEnabled, function(val)
		setValue(unit, { "portrait", "separator", "enabled" }, val and true or false)
		refreshSelf()
	end, portraitSeparatorDef.enabled ~= false, "portrait")
	list[#list].isEnabled = isPortraitEnabled

	local portraitSeparatorSize = slider(L["UFPortraitSeparatorSize"] or "Separator size", 1, 64, 1, function()
		local size = getValue(unit, { "portrait", "separator", "size" }, portraitSeparatorDef.size)
		if not size or size <= 0 then
			local border = getValue(unit, { "border" }, def.border or {})
			size = border.edgeSize or 1
		end
		return size
	end, function(val)
		setValue(unit, { "portrait", "separator", "size" }, val or 1)
		refreshSelf()
	end, portraitSeparatorDef.size or (def.border and def.border.edgeSize) or 1, "portrait", true)
	portraitSeparatorSize.isEnabled = function() return isPortraitEnabled() and isPortraitSeparatorEnabled() end
	list[#list + 1] = portraitSeparatorSize

	local portraitSeparatorTexture = radioDropdown(
		L["UFPortraitSeparatorTexture"] or "Separator texture",
		textureOptions,
		function() return getValue(unit, { "portrait", "separator", "texture" }, portraitSeparatorDef.texture or "SOLID") or "SOLID" end,
		function(val)
			setValue(unit, { "portrait", "separator", "texture" }, val or "SOLID")
			refreshSelf()
		end,
		portraitSeparatorDef.texture or "SOLID",
		"portrait"
	)
	portraitSeparatorTexture.isEnabled = function() return isPortraitEnabled() and isPortraitSeparatorEnabled() end
	list[#list + 1] = portraitSeparatorTexture

	local portraitSeparatorColor = checkboxColor({
		name = L["UFPortraitSeparatorColor"] or "Separator color",
		parentId = "portrait",
		defaultChecked = portraitSeparatorDef.useCustomColor == true,
		isChecked = function() return getValue(unit, { "portrait", "separator", "useCustomColor" }, portraitSeparatorDef.useCustomColor == true) == true end,
		onChecked = function(val)
			setValue(unit, { "portrait", "separator", "useCustomColor" }, val and true or false)
			if val and not getValue(unit, { "portrait", "separator", "color" }) then
				local border = getValue(unit, { "border" }, def.border or {})
				local fallback = border.color or (def.border and def.border.color) or { 0, 0, 0, 0.8 }
				setValue(unit, { "portrait", "separator", "color" }, { fallback[1] or 0, fallback[2] or 0, fallback[3] or 0, fallback[4] or 0.8 })
			end
			refreshSelf()
		end,
		getColor = function()
			local border = getValue(unit, { "border" }, def.border or {})
			local fallback = border.color or (def.border and def.border.color) or { 0, 0, 0, 0.8 }
			return toRGBA(getValue(unit, { "portrait", "separator", "color" }, portraitSeparatorDef.color or fallback), portraitSeparatorDef.color or fallback)
		end,
		onColor = function(color)
			setColor(unit, { "portrait", "separator", "color" }, color.r, color.g, color.b, color.a)
			setValue(unit, { "portrait", "separator", "useCustomColor" }, true)
			refreshSelf()
		end,
		colorDefault = {
			r = (portraitSeparatorDef.color and portraitSeparatorDef.color[1]) or (def.border and def.border.color and def.border.color[1]) or 0,
			g = (portraitSeparatorDef.color and portraitSeparatorDef.color[2]) or (def.border and def.border.color and def.border.color[2]) or 0,
			b = (portraitSeparatorDef.color and portraitSeparatorDef.color[3]) or (def.border and def.border.color and def.border.color[3]) or 0,
			a = (portraitSeparatorDef.color and portraitSeparatorDef.color[4]) or (def.border and def.border.color and def.border.color[4]) or 0.8,
		},
	})
	portraitSeparatorColor.isEnabled = function() return isPortraitEnabled() and isPortraitSeparatorEnabled() end
	list[#list + 1] = portraitSeparatorColor

	list[#list + 1] = { name = L["HealthBar"] or "Health Bar", kind = settingType.Collapsible, id = "health", defaultCollapsed = true }

	list[#list + 1] = slider(L["UFHealthHeight"] or "Health height", 8, 80, 1, function() return getValue(unit, { "healthHeight" }, def.healthHeight or 24) end, function(val)
		setValue(unit, { "healthHeight" }, val or def.healthHeight or 24)
		refresh()
	end, def.healthHeight or 24, "health", true)

	local healthDef = def.health or {}

	if not isBoss then
		list[#list + 1] = checkbox(
			L["UFUseClassColor"] or "Use class color (players)",
			function() return getValue(unit, { "health", "useClassColor" }, healthDef.useClassColor == true) == true end,
			function(val)
				setValue(unit, { "health", "useClassColor" }, val and true or false)
				if val then setValue(unit, { "health", "useCustomColor" }, false) end
				refreshSelf()
				refreshSettingsUI()
			end,
			healthDef.useClassColor == true,
			"health",
			function() return getValue(unit, { "health", "useCustomColor" }, healthDef.useCustomColor == true) ~= true end
		)
	end

	list[#list + 1] = checkboxColor({
		name = L["UFHealthColor"] or "Custom health color",
		parentId = "health",
		defaultChecked = healthDef.useCustomColor == true,
		isChecked = function() return getValue(unit, { "health", "useCustomColor" }, healthDef.useCustomColor == true) == true end,
		onChecked = function(val)
			local useCustom = val and true or false
			setValue(unit, { "health", "useCustomColor" }, useCustom)
			if useCustom then setValue(unit, { "health", "useClassColor" }, false) end
			if useCustom and not getValue(unit, { "health", "color" }) then setValue(unit, { "health", "color" }, healthDef.color or { 0.0, 0.8, 0.0, 1 }) end
			refreshSelf()
			refreshSettingsUI()
		end,
		getColor = function() return toRGBA(getValue(unit, { "health", "color" }, healthDef.color or { 0.0, 0.8, 0.0, 1 }), healthDef.color or { 0.0, 0.8, 0.0, 1 }) end,
		onColor = function(color)
			setColor(unit, { "health", "color" }, color.r, color.g, color.b, color.a)
			setValue(unit, { "health", "useCustomColor" }, true)
			setValue(unit, { "health", "useClassColor" }, false)
			refreshSelf()
		end,
		colorDefault = {
			r = (healthDef.color and healthDef.color[1]) or 0.0,
			g = (healthDef.color and healthDef.color[2]) or 0.8,
			b = (healthDef.color and healthDef.color[3]) or 0.0,
			a = (healthDef.color and healthDef.color[4]) or 1,
		},
		isEnabled = function() return getValue(unit, { "health", "useClassColor" }, healthDef.useClassColor == true) ~= true end,
	})

	local showTapDeniedColor = unit == "target" or unit == "targettarget" or unit == "focus" or isBoss
	if showTapDeniedColor then
		local tapDef = healthDef.tapDeniedColor or { 0.5, 0.5, 0.5, 1 }
		list[#list + 1] = checkboxColor({
			name = L["UFTapDeniedColor"] or "Tapped mob color",
			parentId = "health",
			defaultChecked = healthDef.useTapDeniedColor ~= false,
			isChecked = function() return getValue(unit, { "health", "useTapDeniedColor" }, healthDef.useTapDeniedColor ~= false) ~= false end,
			onChecked = function(val)
				setValue(unit, { "health", "useTapDeniedColor" }, val and true or false)
				if val and not getValue(unit, { "health", "tapDeniedColor" }) then setValue(unit, { "health", "tapDeniedColor" }, tapDef) end
				refreshSelf()
				refreshSettingsUI()
			end,
			getColor = function() return toRGBA(getValue(unit, { "health", "tapDeniedColor" }, tapDef), tapDef) end,
			onColor = function(color)
				setColor(unit, { "health", "tapDeniedColor" }, color.r, color.g, color.b, color.a)
				setValue(unit, { "health", "useTapDeniedColor" }, true)
				refreshSelf()
			end,
			colorDefault = { r = tapDef[1] or 0.5, g = tapDef[2] or 0.5, b = tapDef[3] or 0.5, a = tapDef[4] or 1 },
		})
	end

	list[#list + 1] = radioDropdown(
		L["TextLeft"] or "Left text",
		textOptions,
		function() return normalizeTextMode(getValue(unit, { "health", "textLeft" }, healthDef.textLeft or "PERCENT")) end,
		function(val)
			setValue(unit, { "health", "textLeft" }, val)
			refresh()
			refreshSettingsUI()
		end,
		healthDef.textLeft or "PERCENT",
		"health"
	)

	list[#list + 1] = radioDropdown(
		L["TextCenter"] or "Center text",
		textOptions,
		function() return normalizeTextMode(getValue(unit, { "health", "textCenter" }, healthDef.textCenter or "NONE")) end,
		function(val)
			setValue(unit, { "health", "textCenter" }, val)
			refresh()
			refreshSettingsUI()
		end,
		healthDef.textCenter or "NONE",
		"health"
	)

	list[#list + 1] = radioDropdown(
		L["TextRight"] or "Right text",
		textOptions,
		function() return normalizeTextMode(getValue(unit, { "health", "textRight" }, healthDef.textRight or "CURMAX")) end,
		function(val)
			setValue(unit, { "health", "textRight" }, val)
			refresh()
			refreshSettingsUI()
		end,
		healthDef.textRight or "CURMAX",
		"health"
	)

	local healthDelimiterSetting = radioDropdown(
		L["Delimiter"] or "Delimiter",
		delimiterOptions,
		function() return getValue(unit, { "health", "textDelimiter" }, healthDef.textDelimiter or " ") end,
		function(val)
			setValue(unit, { "health", "textDelimiter" }, val)
			refresh()
		end,
		healthDef.textDelimiter or " ",
		"health"
	)
	local function healthDelimiterCount()
		local leftMode = getValue(unit, { "health", "textLeft" }, healthDef.textLeft or "PERCENT")
		local centerMode = getValue(unit, { "health", "textCenter" }, healthDef.textCenter or "NONE")
		local rightMode = getValue(unit, { "health", "textRight" }, healthDef.textRight or "CURMAX")
		return maxDelimiterCount(leftMode, centerMode, rightMode)
	end
	healthDelimiterSetting.isShown = function() return healthDelimiterCount() >= 1 end
	list[#list + 1] = healthDelimiterSetting

	local healthDelimiterSecondary = radioDropdown(L["Secondary Delimiter"] or "Secondary delimiter", delimiterOptions, function()
		local primary = getValue(unit, { "health", "textDelimiter" }, healthDef.textDelimiter or " ")
		return getValue(unit, { "health", "textDelimiterSecondary" }, primary)
	end, function(val)
		setValue(unit, { "health", "textDelimiterSecondary" }, val)
		refresh()
	end, healthDef.textDelimiterSecondary or healthDef.textDelimiter or " ", "health")
	healthDelimiterSecondary.isShown = function() return healthDelimiterCount() >= 2 end
	list[#list + 1] = healthDelimiterSecondary

	local healthDelimiterTertiary = radioDropdown(L["Tertiary Delimiter"] or "Tertiary delimiter", delimiterOptions, function()
		local primary = getValue(unit, { "health", "textDelimiter" }, healthDef.textDelimiter or " ")
		local secondary = getValue(unit, { "health", "textDelimiterSecondary" }, primary)
		return getValue(unit, { "health", "textDelimiterTertiary" }, secondary)
	end, function(val)
		setValue(unit, { "health", "textDelimiterTertiary" }, val)
		refresh()
	end, healthDef.textDelimiterTertiary or healthDef.textDelimiterSecondary or healthDef.textDelimiter or " ", "health")
	healthDelimiterTertiary.isShown = function() return healthDelimiterCount() >= 3 end
	list[#list + 1] = healthDelimiterTertiary

	list[#list + 1] = checkbox(
		L["Hide % symbol"] or "Hide % symbol",
		function() return getValue(unit, { "health", "hidePercentSymbol" }, healthDef.hidePercentSymbol == true) == true end,
		function(val)
			setValue(unit, { "health", "hidePercentSymbol" }, val and true or false)
			refresh()
		end,
		healthDef.hidePercentSymbol == true,
		"health"
	)

	list[#list + 1] = slider(L["FontSize"] or "Font size", 8, 30, 1, function() return getValue(unit, { "health", "fontSize" }, healthDef.fontSize or 14) end, function(val)
		debounced(unit .. "_healthFontSize", function()
			setValue(unit, { "health", "fontSize" }, val or healthDef.fontSize or 14)
			refresh()
		end)
	end, healthDef.fontSize or 14, "health", true)

	if #fontOptions() > 0 then
		list[#list + 1] = checkboxDropdown(L["Font"] or "Font", fontOptions, function() return getValue(unit, { "health", "font" }, healthDef.font or defaultFontPath()) end, function(val)
			setValue(unit, { "health", "font" }, val)
			refresh()
		end, healthDef.font or defaultFontPath(), "health")
	end

	list[#list + 1] = checkboxDropdown(
		L["Font outline"] or "Font outline",
		outlineOptions,
		function() return getValue(unit, { "health", "fontOutline" }, healthDef.fontOutline or "OUTLINE") end,
		function(val)
			setValue(unit, { "health", "fontOutline" }, val)
			refresh()
		end,
		healthDef.fontOutline or "OUTLINE",
		"health"
	)

	local function showHealthTextOffsets(key, fallback)
		local mode = normalizeTextMode(getValue(unit, { "health", key }, fallback))
		return mode ~= "NONE"
	end

	local healthLeftX = slider(
		L["TextLeftOffsetX"] or "Left text X offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return (getValue(unit, { "health", "offsetLeft", "x" }, (healthDef.offsetLeft and healthDef.offsetLeft.x) or 0)) end,
		function(val)
			debounced(unit .. "_healthLeftX", function()
				setValue(unit, { "health", "offsetLeft", "x" }, val or 0)
				refresh()
			end)
		end,
		(healthDef.offsetLeft and healthDef.offsetLeft.x) or 0,
		"health",
		true
	)
	healthLeftX.isShown = function() return showHealthTextOffsets("textLeft", healthDef.textLeft or "PERCENT") end
	list[#list + 1] = healthLeftX

	local healthLeftY = slider(
		L["TextLeftOffsetY"] or "Left text Y offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return (getValue(unit, { "health", "offsetLeft", "y" }, (healthDef.offsetLeft and healthDef.offsetLeft.y) or 0)) end,
		function(val)
			debounced(unit .. "_healthLeftY", function()
				setValue(unit, { "health", "offsetLeft", "y" }, val or 0)
				refresh()
			end)
		end,
		(healthDef.offsetLeft and healthDef.offsetLeft.y) or 0,
		"health",
		true
	)
	healthLeftY.isShown = function() return showHealthTextOffsets("textLeft", healthDef.textLeft or "PERCENT") end
	list[#list + 1] = healthLeftY

	local healthCenterX = slider(
		L["TextCenterOffsetX"] or "Center text X offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return (getValue(unit, { "health", "offsetCenter", "x" }, (healthDef.offsetCenter and healthDef.offsetCenter.x) or 0)) end,
		function(val)
			debounced(unit .. "_healthCenterX", function()
				setValue(unit, { "health", "offsetCenter", "x" }, val or 0)
				refresh()
			end)
		end,
		(healthDef.offsetCenter and healthDef.offsetCenter.x) or 0,
		"health",
		true
	)
	healthCenterX.isShown = function() return showHealthTextOffsets("textCenter", healthDef.textCenter or "NONE") end
	list[#list + 1] = healthCenterX

	local healthCenterY = slider(
		L["TextCenterOffsetY"] or "Center text Y offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return (getValue(unit, { "health", "offsetCenter", "y" }, (healthDef.offsetCenter and healthDef.offsetCenter.y) or 0)) end,
		function(val)
			debounced(unit .. "_healthCenterY", function()
				setValue(unit, { "health", "offsetCenter", "y" }, val or 0)
				refresh()
			end)
		end,
		(healthDef.offsetCenter and healthDef.offsetCenter.y) or 0,
		"health",
		true
	)
	healthCenterY.isShown = function() return showHealthTextOffsets("textCenter", healthDef.textCenter or "NONE") end
	list[#list + 1] = healthCenterY

	local healthRightX = slider(
		L["TextRightOffsetX"] or "Right text X offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return (getValue(unit, { "health", "offsetRight", "x" }, (healthDef.offsetRight and healthDef.offsetRight.x) or 0)) end,
		function(val)
			debounced(unit .. "_healthRightX", function()
				setValue(unit, { "health", "offsetRight", "x" }, val or 0)
				refresh()
			end)
		end,
		(healthDef.offsetRight and healthDef.offsetRight.x) or 0,
		"health",
		true
	)
	healthRightX.isShown = function() return showHealthTextOffsets("textRight", healthDef.textRight or "CURMAX") end
	list[#list + 1] = healthRightX

	local healthRightY = slider(
		L["TextRightOffsetY"] or "Right text Y offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return (getValue(unit, { "health", "offsetRight", "y" }, (healthDef.offsetRight and healthDef.offsetRight.y) or 0)) end,
		function(val)
			debounced(unit .. "_healthRightY", function()
				setValue(unit, { "health", "offsetRight", "y" }, val or 0)
				refresh()
			end)
		end,
		(healthDef.offsetRight and healthDef.offsetRight.y) or 0,
		"health",
		true
	)
	healthRightY.isShown = function() return showHealthTextOffsets("textRight", healthDef.textRight or "CURMAX") end
	list[#list + 1] = healthRightY

	list[#list + 1] = checkbox(L["Use short numbers"] or "Use short numbers", function() return getValue(unit, { "health", "useShortNumbers" }, healthDef.useShortNumbers ~= false) end, function(val)
		setValue(unit, { "health", "useShortNumbers" }, val and true or false)
		refresh()
	end, healthDef.useShortNumbers ~= false, "health")

	local textureOpts = textureOptions
	list[#list + 1] = checkboxDropdown(L["Bar Texture"] or "Bar Texture", textureOpts, function() return getValue(unit, { "health", "texture" }, healthDef.texture or "DEFAULT") end, function(val)
		setValue(unit, { "health", "texture" }, val)
		refresh()
	end, healthDef.texture or "DEFAULT", "health")

	list[#list + 1] = checkboxColor({
		name = L["UFBarBackdrop"] or "Show bar backdrop",
		parentId = "health",
		defaultChecked = (healthDef.backdrop and healthDef.backdrop.enabled) ~= false,
		isChecked = function() return getValue(unit, { "health", "backdrop", "enabled" }, (healthDef.backdrop and healthDef.backdrop.enabled) ~= false) ~= false end,
		onChecked = function(val)
			debounced(unit .. "_healthBackdrop", function()
				setValue(unit, { "health", "backdrop", "enabled" }, val and true or false)
				refresh()
				refreshSettingsUI()
			end)
		end,
		getColor = function()
			return toRGBA(getValue(unit, { "health", "backdrop", "color" }, healthDef.backdrop and healthDef.backdrop.color), healthDef.backdrop and healthDef.backdrop.color or { 0, 0, 0, 0.6 })
		end,
		onColor = function(color)
			debounced(unit .. "_healthBackdropColor", function()
				setColor(unit, { "health", "backdrop", "color" }, color.r, color.g, color.b, color.a)
				refresh()
			end)
		end,
		colorDefault = { r = 0, g = 0, b = 0, a = 0.6 },
	})

	if unit ~= "pet" then
		local function getOverlayHeightFallback()
			local height = getValue(unit, { "healthHeight" }, def.healthHeight or 24)
			if not height or height <= 0 then height = def.healthHeight or 24 end
			return height
		end

		list[#list + 1] = { name = L["AbsorbBar"] or "Absorb Bar", kind = settingType.Collapsible, id = "absorb", defaultCollapsed = true }
		local absorbColorDef = healthDef.absorbColor or { 0.85, 0.95, 1, 0.7 }

		list[#list + 1] = checkboxColor({
			name = L["Use custom absorb color"] or "Use custom absorb color",
			parentId = "absorb",
			defaultChecked = healthDef.absorbUseCustomColor == true,
			isChecked = function() return getValue(unit, { "health", "absorbUseCustomColor" }, healthDef.absorbUseCustomColor == true) == true end,
			onChecked = function(val)
				debounced(unit .. "_absorbCustomColorToggle", function()
					setValue(unit, { "health", "absorbUseCustomColor" }, val and true or false)
					if val and not getValue(unit, { "health", "absorbColor" }) then setValue(unit, { "health", "absorbColor" }, absorbColorDef) end
					refresh()
					refreshSettingsUI()
				end)
			end,
			getColor = function() return toRGBA(getValue(unit, { "health", "absorbColor" }, absorbColorDef), absorbColorDef) end,
			onColor = function(color)
				setColor(unit, { "health", "absorbColor" }, color.r, color.g, color.b, color.a)
				setValue(unit, { "health", "absorbUseCustomColor" }, true)
				refresh()
			end,
			colorDefault = {
				r = absorbColorDef[1] or 0.85,
				g = absorbColorDef[2] or 0.95,
				b = absorbColorDef[3] or 1,
				a = absorbColorDef[4] or 0.7,
			},
		})

		list[#list + 1] = checkbox(
			L["Use absorb glow"] or "Use absorb glow",
			function() return getValue(unit, { "health", "useAbsorbGlow" }, healthDef.useAbsorbGlow ~= false) ~= false end,
			function(val)
				setValue(unit, { "health", "useAbsorbGlow" }, val and true or false)
				refresh()
			end,
			healthDef.useAbsorbGlow ~= false,
			"absorb"
		)

		list[#list + 1] = checkbox(
			L["Reverse fill"] or "Reverse fill",
			function() return getValue(unit, { "health", "absorbReverseFill" }, healthDef.absorbReverseFill == true) == true end,
			function(val)
				setValue(unit, { "health", "absorbReverseFill" }, val and true or false)
				refresh()
			end,
			healthDef.absorbReverseFill == true,
			"absorb"
		)

		list[#list + 1] = slider(L["Absorb overlay height"] or "Absorb overlay height", 1, 80, 1, function()
			local fallback = getOverlayHeightFallback()
			local val = getValue(unit, { "health", "absorbOverlayHeight" }, healthDef.absorbOverlayHeight)
			if not val or val <= 0 then return fallback end
			return math.min(val, fallback)
		end, function(val)
			setValue(unit, { "health", "absorbOverlayHeight" }, val or getOverlayHeightFallback())
			refresh()
		end, getOverlayHeightFallback(), "absorb", true)

		list[#list + 1] = checkbox(L["Show sample absorb"] or "Show sample absorb", function() return sampleAbsorb[unit] == true end, function(val)
			sampleAbsorb[unit] = val and true or false
			refresh()
		end, false, "absorb")

		local absorbTextureSetting = checkboxDropdown(
			L["Absorb texture"] or "Absorb texture",
			textureOpts,
			function() return getValue(unit, { "health", "absorbTexture" }, healthDef.absorbTexture or healthDef.texture or "SOLID") end,
			function(val)
				setValue(unit, { "health", "absorbTexture" }, val)
				refresh()
			end,
			healthDef.absorbTexture or healthDef.texture or "SOLID",
			"absorb"
		)
		list[#list + 1] = absorbTextureSetting

		list[#list + 1] = { name = L["HealAbsorbBar"] or "Heal Absorb Bar", kind = settingType.Collapsible, id = "healAbsorb", defaultCollapsed = true }
		local healAbsorbColorDef = healthDef.healAbsorbColor or { 1, 0.3, 0.3, 0.7 }

		list[#list + 1] = checkboxColor({
			name = L["Use custom heal absorb color"] or "Use custom heal absorb color",
			parentId = "healAbsorb",
			defaultChecked = healthDef.healAbsorbUseCustomColor == true,
			isChecked = function() return getValue(unit, { "health", "healAbsorbUseCustomColor" }, healthDef.healAbsorbUseCustomColor == true) == true end,
			onChecked = function(val)
				debounced(unit .. "_healAbsorbCustomColorToggle", function()
					setValue(unit, { "health", "healAbsorbUseCustomColor" }, val and true or false)
					if val and not getValue(unit, { "health", "healAbsorbColor" }) then setValue(unit, { "health", "healAbsorbColor" }, healAbsorbColorDef) end
					refresh()
					refreshSettingsUI()
				end)
			end,
			getColor = function() return toRGBA(getValue(unit, { "health", "healAbsorbColor" }, healAbsorbColorDef), healAbsorbColorDef) end,
			onColor = function(color)
				setColor(unit, { "health", "healAbsorbColor" }, color.r, color.g, color.b, color.a)
				setValue(unit, { "health", "healAbsorbUseCustomColor" }, true)
				refresh()
			end,
			colorDefault = {
				r = healAbsorbColorDef[1] or 1,
				g = healAbsorbColorDef[2] or 0.3,
				b = healAbsorbColorDef[3] or 0.3,
				a = healAbsorbColorDef[4] or 0.7,
			},
		})

		list[#list + 1] = checkbox(
			L["Reverse heal absorb fill"] or "Reverse heal absorb fill",
			function() return getValue(unit, { "health", "healAbsorbReverseFill" }, healthDef.healAbsorbReverseFill == true) == true end,
			function(val)
				setValue(unit, { "health", "healAbsorbReverseFill" }, val and true or false)
				refresh()
			end,
			healthDef.healAbsorbReverseFill == true,
			"healAbsorb"
		)

		list[#list + 1] = slider(L["Heal absorb overlay height"] or "Heal absorb overlay height", 1, 80, 1, function()
			local fallback = getOverlayHeightFallback()
			local val = getValue(unit, { "health", "healAbsorbOverlayHeight" }, healthDef.healAbsorbOverlayHeight)
			if not val or val <= 0 then return fallback end
			return math.min(val, fallback)
		end, function(val)
			setValue(unit, { "health", "healAbsorbOverlayHeight" }, val or getOverlayHeightFallback())
			refresh()
		end, getOverlayHeightFallback(), "healAbsorb", true)

		list[#list + 1] = checkbox(L["Show sample heal absorb"] or "Show sample heal absorb", function() return sampleHealAbsorb[unit] == true end, function(val)
			sampleHealAbsorb[unit] = val and true or false
			refresh()
		end, false, "healAbsorb")

		local healAbsorbTextureSetting = checkboxDropdown(
			L["Heal absorb texture"] or "Heal absorb texture",
			textureOpts,
			function() return getValue(unit, { "health", "healAbsorbTexture" }, healthDef.healAbsorbTexture or healthDef.texture or "SOLID") end,
			function(val)
				setValue(unit, { "health", "healAbsorbTexture" }, val)
				refresh()
			end,
			healthDef.healAbsorbTexture or healthDef.texture or "SOLID",
			"healAbsorb"
		)
		list[#list + 1] = healAbsorbTextureSetting
	end

	list[#list + 1] = { name = L["PowerBar"] or "Power Bar", kind = settingType.Collapsible, id = "power", defaultCollapsed = true }
	local powerDef = def.power or {}
	local function isPowerEnabled() return getValue(unit, { "power", "enabled" }, powerDef.enabled ~= false) ~= false end

	list[#list + 1] = checkbox(L["Show power bar"] or "Show power bar", isPowerEnabled, function(val)
		setValue(unit, { "power", "enabled" }, val and true or false)
		refreshSelf()
		refreshSettingsUI()
	end, powerDef.enabled ~= false, "power")

	local powerHeightSetting = slider(L["UFPowerHeight"] or "Power height", 6, 60, 1, function() return getValue(unit, { "powerHeight" }, def.powerHeight or 16) end, function(val)
		debounced(unit .. "_powerHeight", function()
			setValue(unit, { "powerHeight" }, val or def.powerHeight or 16)
			refresh()
		end)
	end, def.powerHeight or 16, "power", true)
	powerHeightSetting.isEnabled = isPowerEnabled
	list[#list + 1] = powerHeightSetting

	local function isPowerDetached() return getValue(unit, { "power", "detached" }, powerDef.detached == true) == true end

	local powerDetachedSetting = checkbox(L["UFPowerDetached"] or "Detach power bar", isPowerDetached, function(val)
		setValue(unit, { "power", "detached" }, val and true or false)
		refresh()
		refreshSettingsUI()
	end, powerDef.detached == true, "power", isPowerEnabled)
	list[#list + 1] = powerDetachedSetting

	local function isPowerDetachedEnabled() return isPowerEnabled() and isPowerDetached() end

	local powerEmptyFallbackSetting = checkbox(
		L["UFPowerEmptyFallback"] or "Handle empty power bars (max 0)",
		function() return getValue(unit, { "power", "emptyMaxFallback" }, powerDef.emptyMaxFallback == true) == true end,
		function(val)
			setValue(unit, { "power", "emptyMaxFallback" }, val and true or false)
			refresh()
		end,
		powerDef.emptyMaxFallback == true,
		"power",
		isPowerEnabled
	)
	powerEmptyFallbackSetting.isEnabled = isPowerDetachedEnabled
	powerEmptyFallbackSetting.isShown = isPowerDetachedEnabled
	list[#list + 1] = powerEmptyFallbackSetting

	local powerWidthSetting = slider(L["UFPowerWidth"] or "Power width", MIN_WIDTH, 800, 1, function()
		local fallback = getValue(unit, { "width" }, def.width or MIN_WIDTH)
		return getValue(unit, { "power", "width" }, fallback)
	end, function(val)
		debounced(unit .. "_powerWidth", function()
			setValue(unit, { "power", "width" }, math.max(MIN_WIDTH, val or MIN_WIDTH))
			refresh()
		end)
	end, def.width or MIN_WIDTH, "power", true)
	powerWidthSetting.isEnabled = isPowerDetachedEnabled
	powerWidthSetting.isShown = isPowerDetachedEnabled
	list[#list + 1] = powerWidthSetting

	local powerOffsetX = slider(L["Offset X"] or "Offset X", -OFFSET_RANGE, OFFSET_RANGE, 1, function() return getValue(unit, { "power", "offset", "x" }, 0) end, function(val)
		debounced(unit .. "_powerOffsetX", function()
			setValue(unit, { "power", "offset", "x" }, val or 0)
			refresh()
		end)
	end, 0, "power", true)
	powerOffsetX.isEnabled = isPowerDetachedEnabled
	powerOffsetX.isShown = isPowerDetachedEnabled
	list[#list + 1] = powerOffsetX

	local powerOffsetY = slider(L["Offset Y"] or "Offset Y", -OFFSET_RANGE, OFFSET_RANGE, 1, function() return getValue(unit, { "power", "offset", "y" }, 0) end, function(val)
		debounced(unit .. "_powerOffsetY", function()
			setValue(unit, { "power", "offset", "y" }, val or 0)
			refresh()
		end)
	end, 0, "power", true)
	powerOffsetY.isEnabled = isPowerDetachedEnabled
	powerOffsetY.isShown = isPowerDetachedEnabled
	list[#list + 1] = powerOffsetY

	local powerTextLeft = radioDropdown(
		L["TextLeft"] or "Left text",
		textOptions,
		function() return normalizeTextMode(getValue(unit, { "power", "textLeft" }, powerDef.textLeft or "PERCENT")) end,
		function(val)
			setValue(unit, { "power", "textLeft" }, val)
			refreshSelf()
			refreshSettingsUI()
		end,
		powerDef.textLeft or "PERCENT",
		"power"
	)
	powerTextLeft.isEnabled = isPowerEnabled
	list[#list + 1] = powerTextLeft

	local powerTextCenter = radioDropdown(
		L["TextCenter"] or "Center text",
		textOptions,
		function() return normalizeTextMode(getValue(unit, { "power", "textCenter" }, powerDef.textCenter or "NONE")) end,
		function(val)
			setValue(unit, { "power", "textCenter" }, val)
			refreshSelf()
			refreshSettingsUI()
		end,
		powerDef.textCenter or "NONE",
		"power"
	)
	powerTextCenter.isEnabled = isPowerEnabled
	list[#list + 1] = powerTextCenter

	local powerTextRight = radioDropdown(
		L["TextRight"] or "Right text",
		textOptions,
		function() return normalizeTextMode(getValue(unit, { "power", "textRight" }, powerDef.textRight or "CURMAX")) end,
		function(val)
			setValue(unit, { "power", "textRight" }, val)
			refreshSelf()
			refreshSettingsUI()
		end,
		powerDef.textRight or "CURMAX",
		"power"
	)
	powerTextRight.isEnabled = isPowerEnabled
	list[#list + 1] = powerTextRight

	local powerDelimiter = radioDropdown(
		L["Delimiter"] or "Delimiter",
		delimiterOptions,
		function() return getValue(unit, { "power", "textDelimiter" }, powerDef.textDelimiter or " ") end,
		function(val)
			setValue(unit, { "power", "textDelimiter" }, val)
			refreshSelf()
		end,
		powerDef.textDelimiter or " ",
		"power"
	)
	local function powerDelimiterCount()
		local leftMode = getValue(unit, { "power", "textLeft" }, powerDef.textLeft or "PERCENT")
		local centerMode = getValue(unit, { "power", "textCenter" }, powerDef.textCenter or "NONE")
		local rightMode = getValue(unit, { "power", "textRight" }, powerDef.textRight or "CURMAX")
		return maxDelimiterCount(leftMode, centerMode, rightMode)
	end
	powerDelimiter.isShown = function() return powerDelimiterCount() >= 1 end
	powerDelimiter.isEnabled = isPowerEnabled
	list[#list + 1] = powerDelimiter

	local powerDelimiterSecondary = radioDropdown(L["Secondary Delimiter"] or "Secondary delimiter", delimiterOptions, function()
		local primary = getValue(unit, { "power", "textDelimiter" }, powerDef.textDelimiter or " ")
		return getValue(unit, { "power", "textDelimiterSecondary" }, primary)
	end, function(val)
		setValue(unit, { "power", "textDelimiterSecondary" }, val)
		refreshSelf()
	end, powerDef.textDelimiterSecondary or powerDef.textDelimiter or " ", "power")
	powerDelimiterSecondary.isShown = function() return powerDelimiterCount() >= 2 end
	powerDelimiterSecondary.isEnabled = isPowerEnabled
	list[#list + 1] = powerDelimiterSecondary

	local powerDelimiterTertiary = radioDropdown(L["Tertiary Delimiter"] or "Tertiary delimiter", delimiterOptions, function()
		local primary = getValue(unit, { "power", "textDelimiter" }, powerDef.textDelimiter or " ")
		local secondary = getValue(unit, { "power", "textDelimiterSecondary" }, primary)
		return getValue(unit, { "power", "textDelimiterTertiary" }, secondary)
	end, function(val)
		setValue(unit, { "power", "textDelimiterTertiary" }, val)
		refreshSelf()
	end, powerDef.textDelimiterTertiary or powerDef.textDelimiterSecondary or powerDef.textDelimiter or " ", "power")
	powerDelimiterTertiary.isShown = function() return powerDelimiterCount() >= 3 end
	powerDelimiterTertiary.isEnabled = isPowerEnabled
	list[#list + 1] = powerDelimiterTertiary

	list[#list + 1] = checkbox(L["Hide % symbol"] or "Hide % symbol", function() return getValue(unit, { "power", "hidePercentSymbol" }, powerDef.hidePercentSymbol == true) == true end, function(val)
		setValue(unit, { "power", "hidePercentSymbol" }, val and true or false)
		refresh()
	end, powerDef.hidePercentSymbol == true, "power", isPowerEnabled)

	local powerFontSize = slider(L["FontSize"] or "Font size", 8, 30, 1, function() return getValue(unit, { "power", "fontSize" }, powerDef.fontSize or 14) end, function(val)
		debounced(unit .. "_powerFontSize", function()
			setValue(unit, { "power", "fontSize" }, val or powerDef.fontSize or 14)
			refreshSelf()
		end)
	end, powerDef.fontSize or 14, "power", true)
	powerFontSize.isEnabled = isPowerEnabled
	list[#list + 1] = powerFontSize

	if #fontOptions() > 0 then
		local powerFont = checkboxDropdown(L["Font"] or "Font", fontOptions, function() return getValue(unit, { "power", "font" }, powerDef.font or defaultFontPath()) end, function(val)
			setValue(unit, { "power", "font" }, val)
			refreshSelf()
		end, powerDef.font or defaultFontPath(), "power")
		powerFont.isEnabled = isPowerEnabled
		list[#list + 1] = powerFont
	end

	local powerFontOutline = checkboxDropdown(
		L["Font outline"] or "Font outline",
		outlineOptions,
		function() return getValue(unit, { "power", "fontOutline" }, powerDef.fontOutline or "OUTLINE") end,
		function(val)
			setValue(unit, { "power", "fontOutline" }, val)
			refresh()
		end,
		powerDef.fontOutline or "OUTLINE",
		"power"
	)
	powerFontOutline.isEnabled = isPowerEnabled
	list[#list + 1] = powerFontOutline

	local function showPowerTextOffsets(key, fallback)
		local mode = normalizeTextMode(getValue(unit, { "power", key }, fallback))
		return mode ~= "NONE"
	end

	local powerLeftX = slider(
		L["TextLeftOffsetX"] or "Left text X offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return (getValue(unit, { "power", "offsetLeft", "x" }, (powerDef.offsetLeft and powerDef.offsetLeft.x) or 0)) end,
		function(val)
			debounced(unit .. "_powerLeftX", function()
				setValue(unit, { "power", "offsetLeft", "x" }, val or 0)
				refresh()
			end)
		end,
		(powerDef.offsetLeft and powerDef.offsetLeft.x) or 0,
		"power",
		true
	)
	powerLeftX.isEnabled = isPowerEnabled
	powerLeftX.isShown = function() return showPowerTextOffsets("textLeft", powerDef.textLeft or "PERCENT") end
	list[#list + 1] = powerLeftX

	local powerLeftY = slider(
		L["TextLeftOffsetY"] or "Left text Y offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return (getValue(unit, { "power", "offsetLeft", "y" }, (powerDef.offsetLeft and powerDef.offsetLeft.y) or 0)) end,
		function(val)
			debounced(unit .. "_powerLeftY", function()
				setValue(unit, { "power", "offsetLeft", "y" }, val or 0)
				refresh()
			end)
		end,
		(powerDef.offsetLeft and powerDef.offsetLeft.y) or 0,
		"power",
		true
	)
	powerLeftY.isEnabled = isPowerEnabled
	powerLeftY.isShown = function() return showPowerTextOffsets("textLeft", powerDef.textLeft or "PERCENT") end
	list[#list + 1] = powerLeftY

	local powerCenterX = slider(
		L["TextCenterOffsetX"] or "Center text X offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return (getValue(unit, { "power", "offsetCenter", "x" }, (powerDef.offsetCenter and powerDef.offsetCenter.x) or 0)) end,
		function(val)
			debounced(unit .. "_powerCenterX", function()
				setValue(unit, { "power", "offsetCenter", "x" }, val or 0)
				refresh()
			end)
		end,
		(powerDef.offsetCenter and powerDef.offsetCenter.x) or 0,
		"power",
		true
	)
	powerCenterX.isEnabled = isPowerEnabled
	powerCenterX.isShown = function() return showPowerTextOffsets("textCenter", powerDef.textCenter or "NONE") end
	list[#list + 1] = powerCenterX

	local powerCenterY = slider(
		L["TextCenterOffsetY"] or "Center text Y offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return (getValue(unit, { "power", "offsetCenter", "y" }, (powerDef.offsetCenter and powerDef.offsetCenter.y) or 0)) end,
		function(val)
			debounced(unit .. "_powerCenterY", function()
				setValue(unit, { "power", "offsetCenter", "y" }, val or 0)
				refresh()
			end)
		end,
		(powerDef.offsetCenter and powerDef.offsetCenter.y) or 0,
		"power",
		true
	)
	powerCenterY.isEnabled = isPowerEnabled
	powerCenterY.isShown = function() return showPowerTextOffsets("textCenter", powerDef.textCenter or "NONE") end
	list[#list + 1] = powerCenterY

	local powerRightX = slider(
		L["TextRightOffsetX"] or "Right text X offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return (getValue(unit, { "power", "offsetRight", "x" }, (powerDef.offsetRight and powerDef.offsetRight.x) or 0)) end,
		function(val)
			debounced(unit .. "_powerRightX", function()
				setValue(unit, { "power", "offsetRight", "x" }, val or 0)
				refresh()
			end)
		end,
		(powerDef.offsetRight and powerDef.offsetRight.x) or 0,
		"power",
		true
	)
	powerRightX.isEnabled = isPowerEnabled
	powerRightX.isShown = function() return showPowerTextOffsets("textRight", powerDef.textRight or "CURMAX") end
	list[#list + 1] = powerRightX

	local powerRightY = slider(
		L["TextRightOffsetY"] or "Right text Y offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return (getValue(unit, { "power", "offsetRight", "y" }, (powerDef.offsetRight and powerDef.offsetRight.y) or 0)) end,
		function(val)
			debounced(unit .. "_powerRightY", function()
				setValue(unit, { "power", "offsetRight", "y" }, val or 0)
				refresh()
			end)
		end,
		(powerDef.offsetRight and powerDef.offsetRight.y) or 0,
		"power",
		true
	)
	powerRightY.isEnabled = isPowerEnabled
	powerRightY.isShown = function() return showPowerTextOffsets("textRight", powerDef.textRight or "CURMAX") end
	list[#list + 1] = powerRightY

	list[#list + 1] = checkbox(L["Use short numbers"] or "Use short numbers", function() return getValue(unit, { "power", "useShortNumbers" }, powerDef.useShortNumbers ~= false) end, function(val)
		setValue(unit, { "power", "useShortNumbers" }, val and true or false)
		refresh()
	end, powerDef.useShortNumbers ~= false, "power", isPowerEnabled)

	local powerTexture = checkboxDropdown(L["Bar Texture"] or "Bar Texture", textureOpts, function() return getValue(unit, { "power", "texture" }, powerDef.texture or "DEFAULT") end, function(val)
		setValue(unit, { "power", "texture" }, val)
		refresh()
	end, powerDef.texture or "DEFAULT", "power")
	powerTexture.isEnabled = isPowerEnabled
	list[#list + 1] = powerTexture

	list[#list + 1] = checkboxColor({
		name = L["UFBarBackdrop"] or "Show bar backdrop",
		parentId = "power",
		defaultChecked = (powerDef.backdrop and powerDef.backdrop.enabled) ~= false,
		isChecked = function() return getValue(unit, { "power", "backdrop", "enabled" }, (powerDef.backdrop and powerDef.backdrop.enabled) ~= false) ~= false end,
		onChecked = function(val)
			debounced(unit .. "_powerBackdrop", function()
				setValue(unit, { "power", "backdrop", "enabled" }, val and true or false)
				refresh()
				refreshSettingsUI()
			end)
		end,
		getColor = function()
			return toRGBA(getValue(unit, { "power", "backdrop", "color" }, powerDef.backdrop and powerDef.backdrop.color), powerDef.backdrop and powerDef.backdrop.color or { 0, 0, 0, 0.6 })
		end,
		onColor = function(color)
			debounced(unit .. "_powerBackdropColor", function()
				setColor(unit, { "power", "backdrop", "color" }, color.r, color.g, color.b, color.a)
				refresh()
			end)
		end,
		colorDefault = { r = 0, g = 0, b = 0, a = 0.6 },
		isEnabled = isPowerEnabled,
	})

	local mainPowerTokens = getMainPowerTokens()
	if #mainPowerTokens > 0 then
		list[#list + 1] = { name = L["UFMainPowerColors"] or "Main power colors", kind = settingType.Collapsible, id = "mainPowerColors", defaultCollapsed = true }
		for _, token in ipairs(mainPowerTokens) do
			local label = getPowerLabel(token)
			local dr, dg, db, da = getDefaultPowerColor(token)
			local defaultColor = { dr, dg, db, da }
			list[#list + 1] = checkboxColor({
				name = label,
				parentId = "mainPowerColors",
				defaultChecked = false,
				isChecked = function() return getPowerOverride(token) ~= nil end,
				onChecked = function(val)
					debounced("uf_powercolor_toggle_" .. token, function()
						if val then
							setPowerOverride(token, dr, dg, db, da)
						else
							clearPowerOverride(token)
						end
						if UF and UF.Refresh then UF.Refresh() end
						refreshSettingsUI()
					end)
				end,
				getColor = function() return toRGBA(getPowerOverride(token) or defaultColor, defaultColor) end,
				onColor = function(color)
					debounced("uf_powercolor_pick_" .. token, function()
						setPowerOverride(token, color.r, color.g, color.b, color.a)
						if UF and UF.Refresh then UF.Refresh() end
						refreshSettingsUI()
					end)
				end,
				colorDefault = { r = dr, g = dg, b = db, a = da },
			})
		end
	end

	local showNPCColors = unit == "target" or unit == "targettarget" or unit == "focus" or isBoss
	if showNPCColors then
		list[#list + 1] = { name = L["UFNPCColors"] or "NPC colors", kind = settingType.Collapsible, id = "npcColors", defaultCollapsed = true }
		for _, entry in ipairs(npcColorEntries) do
			local dr, dg, db, da = getDefaultNPCColor(entry.key)
			local defaultColor = { dr, dg, db, da }
			list[#list + 1] = checkboxColor({
				name = entry.label,
				parentId = "npcColors",
				defaultChecked = false,
				isChecked = function() return getNPCOverride(entry.key) ~= nil end,
				onChecked = function(val)
					debounced("uf_npccolor_toggle_" .. entry.key, function()
						if val then
							setNPCOverride(entry.key, dr, dg, db, da)
						else
							clearNPCOverride(entry.key)
						end
						if UF and UF.Refresh then UF.Refresh() end
						refreshSettingsUI()
					end)
				end,
				getColor = function() return toRGBA(getNPCOverride(entry.key) or defaultColor, defaultColor) end,
				onColor = function(color)
					debounced("uf_npccolor_pick_" .. entry.key, function()
						setNPCOverride(entry.key, color.r, color.g, color.b, color.a)
						if UF and UF.Refresh then UF.Refresh() end
						refreshSettingsUI()
					end)
				end,
				colorDefault = { r = dr, g = dg, b = db, a = da },
			})
		end
	end

	local function SnapToStep(value, step, minV, maxV)
		value = tonumber(value)
		if not value then return nil end

		if minV then value = math.max(minV, value) end
		if maxV then value = math.min(maxV, value) end

		local inv = 1 / (step or 1)
		local ticks = math.floor(value * inv + 0.5)
		local snapped = ticks / inv

		snapped = math.floor(snapped * 100 + 0.5) / 100
		return snapped
	end

	if isPlayer and classHasResource then
		local crDef = def.classResource or {}
		list[#list + 1] = { name = L["ClassResource"] or "Class Resource", kind = settingType.Collapsible, id = "classResource", defaultCollapsed = true }
		local function isClassResourceEnabled() return getValue(unit, { "classResource", "enabled" }, crDef.enabled ~= false) ~= false end
		local function defaultOffsetY()
			local anchor = getValue(unit, { "classResource", "anchor" }, crDef.anchor or "TOP")
			return anchor == "TOP" and -5 or 5
		end

		list[#list + 1] = checkbox(L["Show class resource"] or "Show class resource", isClassResourceEnabled, function(val)
			setValue(unit, { "classResource", "enabled" }, val and true or false)
			refreshSelf()
		end, crDef.enabled ~= false, "classResource")

		local classAnchorOpts = {
			{ value = "TOP", label = L["Top"] or "Top" },
			{ value = "BOTTOM", label = L["Bottom"] or "Bottom" },
		}
		local classAnchor = radioDropdown(L["Anchor"] or "Anchor", classAnchorOpts, function() return getValue(unit, { "classResource", "anchor" }, crDef.anchor or "TOP") end, function(val)
			setValue(unit, { "classResource", "anchor" }, val or "TOP")
			refreshSelf()
		end, crDef.anchor or "TOP", "classResource")
		classAnchor.isEnabled = isClassResourceEnabled
		list[#list + 1] = classAnchor

		local classOffsetX = slider(
			L["Offset X"] or "Offset X",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "classResource", "offset", "x" }, (crDef.offset and crDef.offset.x) or 0) end,
			function(val)
				debounced(unit .. "_classResourceOffsetX", function()
					setValue(unit, { "classResource", "offset", "x" }, val or 0)
					refreshSelf()
				end)
			end,
			(crDef.offset and crDef.offset.x) or 0,
			"classResource",
			true
		)
		classOffsetX.isEnabled = isClassResourceEnabled
		list[#list + 1] = classOffsetX

		local classOffsetY = slider(
			L["Offset Y"] or "Offset Y",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "classResource", "offset", "y" }, defaultOffsetY()) end,
			function(val)
				debounced(unit .. "_classResourceOffsetY", function()
					setValue(unit, { "classResource", "offset", "y" }, val or 0)
					refreshSelf()
				end)
			end,
			defaultOffsetY(),
			"classResource",
			true
		)
		classOffsetY.isEnabled = isClassResourceEnabled
		list[#list + 1] = classOffsetY

		local classScale = slider(
			L["Scale"] or "Scale",
			0.5,
			2,
			0.05,
			function()
				local v = getValue(unit, { "classResource", "scale" }, crDef.scale or 1)
				return SnapToStep(v, 0.05, 0.5, 2) or 1
			end,
			function(val)
				debounced(unit .. "_classResourceScale", function()
					val = SnapToStep(val, 0.05, 0.5, 2) or 1
					setValue(unit, { "classResource", "scale" }, val)
					refreshSelf()

					-- DAS ist der Punkt: UI-Wert neu setzen
					refreshSettingsUI()
				end)
			end,
			SnapToStep(crDef.scale or 1, 0.05, 0.5, 2) or 1,
			"classResource",
			true,
			function(value)
				value = SnapToStep(value, 0.05, 0.5, 2) or 1
				return string.format("%.2f", value)
			end
		)
		classScale.isEnabled = isClassResourceEnabled
		list[#list + 1] = classScale
	end

	if isPlayer and classHasTotemFrame then
		local crDef = def.classResource or {}
		local totemDef = type(crDef.totemFrame) == "table" and crDef.totemFrame or {}
		local function normalizeTotemValue(value)
			if value == true then return { enabled = true } end
			if type(value) == "table" then return value end
			return {}
		end
		local function getTotemConfig() return normalizeTotemValue(getValue(unit, { "classResource", "totemFrame" }, crDef.totemFrame)) end
		local function updateTotemConfig(handler)
			local current = getTotemConfig()
			local nextCfg = {}
			for key, val in pairs(current) do
				nextCfg[key] = val
			end
			handler(nextCfg)
			setValue(unit, { "classResource", "totemFrame" }, nextCfg)
		end
		local function isTotemFrameEnabled()
			local cfg = getTotemConfig()
			local enabled = cfg.enabled
			if enabled == nil then enabled = totemDef.enabled end
			return enabled == true
		end

		list[#list + 1] = { name = L["Totem Frame"] or "Totem Frame", kind = settingType.Collapsible, id = "totemFrame", defaultCollapsed = true }

		list[#list + 1] = checkbox(L["Re-anchor Totem Frame"] or "Re-anchor Totem Frame", isTotemFrameEnabled, function(val)
			updateTotemConfig(function(cfg) cfg.enabled = val and true or false end)
			refreshSelf()
		end, totemDef.enabled == true, "totemFrame")

		local totemAnchorOptions = {
			{ value = "TOPLEFT", label = L["Top left"] or "Top left" },
			{ value = "TOP", label = L["Top"] or "Top" },
			{ value = "TOPRIGHT", label = L["Top right"] or "Top right" },
			{ value = "LEFT", label = L["Left"] or "Left" },
			{ value = "CENTER", label = L["Center"] or "Center" },
			{ value = "RIGHT", label = L["Right"] or "Right" },
			{ value = "BOTTOMLEFT", label = L["Bottom left"] or "Bottom left" },
			{ value = "BOTTOM", label = L["Bottom"] or "Bottom" },
			{ value = "BOTTOMRIGHT", label = L["Bottom right"] or "Bottom right" },
		}
		local totemAnchor = radioDropdown(L["Anchor"] or "Anchor", totemAnchorOptions, function()
			local cfg = getTotemConfig()
			return cfg.anchor or totemDef.anchor or "BOTTOMRIGHT"
		end, function(val)
			updateTotemConfig(function(cfg) cfg.anchor = val or "BOTTOMRIGHT" end)
			refreshSelf()
		end, totemDef.anchor or "BOTTOMRIGHT", "totemFrame")
		totemAnchor.isEnabled = isTotemFrameEnabled
		list[#list + 1] = totemAnchor

		local totemOffsetX = slider(L["Offset X"] or "Offset X", -OFFSET_RANGE, OFFSET_RANGE, 1, function()
			local cfg = getTotemConfig()
			local offset = cfg.offset or {}
			if offset.x == nil and totemDef.offset then return totemDef.offset.x or 0 end
			return offset.x or 0
		end, function(val)
			debounced(unit .. "_totemFrameOffsetX", function()
				updateTotemConfig(function(cfg)
					cfg.offset = cfg.offset or {}
					cfg.offset.x = val or 0
				end)
				refreshSelf()
			end)
		end, (totemDef.offset and totemDef.offset.x) or 0, "totemFrame", true)
		totemOffsetX.isEnabled = isTotemFrameEnabled
		list[#list + 1] = totemOffsetX

		local totemOffsetY = slider(L["Offset Y"] or "Offset Y", -OFFSET_RANGE, OFFSET_RANGE, 1, function()
			local cfg = getTotemConfig()
			local offset = cfg.offset or {}
			if offset.y == nil and totemDef.offset then return totemDef.offset.y or 0 end
			return offset.y or 0
		end, function(val)
			debounced(unit .. "_totemFrameOffsetY", function()
				updateTotemConfig(function(cfg)
					cfg.offset = cfg.offset or {}
					cfg.offset.y = val or 0
				end)
				refreshSelf()
			end)
		end, (totemDef.offset and totemDef.offset.y) or 0, "totemFrame", true)
		totemOffsetY.isEnabled = isTotemFrameEnabled
		list[#list + 1] = totemOffsetY

		local totemScale = slider(
			L["Scale"] or "Scale",
			0.5,
			2,
			0.05,
			function()
				local cfg = getTotemConfig()
				local v = cfg.scale
				if v == nil then v = totemDef.scale or 1 end
				return SnapToStep(v, 0.05, 0.5, 2) or 1
			end,
			function(val)
				debounced(unit .. "_totemFrameScale", function()
					val = SnapToStep(val, 0.05, 0.5, 2) or 1
					updateTotemConfig(function(cfg) cfg.scale = val end)
					refreshSelf()
					refreshSettingsUI()
				end)
			end,
			SnapToStep(totemDef.scale or 1, 0.05, 0.5, 2) or 1,
			"totemFrame",
			true,
			function(value)
				value = SnapToStep(value, 0.05, 0.5, 2) or 1
				return string.format("%.2f", value)
			end
		)
		totemScale.isEnabled = isTotemFrameEnabled
		list[#list + 1] = totemScale

		local totemSample = checkbox(L["Show sample in Edit Mode"] or "Show sample in Edit Mode", function()
			local cfg = getTotemConfig()
			local val = cfg.showSample
			if val == nil then val = totemDef.showSample end
			return val == true
		end, function(val)
			updateTotemConfig(function(cfg) cfg.showSample = val and true or false end)
			refreshSelf()
		end, totemDef.showSample == true, "totemFrame")
		totemSample.isEnabled = isTotemFrameEnabled
		list[#list + 1] = totemSample
	end

	local raidIconDef = def.raidIcon or { enabled = true, size = 18, offset = { x = 0, y = -2 } }
	local function isRaidIconEnabled() return getValue(unit, { "raidIcon", "enabled" }, raidIconDef.enabled ~= false) ~= false end
	list[#list + 1] = { name = L["RaidTargetIcon"] or "Raid Target Icon", kind = settingType.Collapsible, id = "raidicon", defaultCollapsed = true }

	list[#list + 1] = checkbox(L["Show raid target icon"] or "Show raid target icon", isRaidIconEnabled, function(val)
		setValue(unit, { "raidIcon", "enabled" }, val and true or false)
		refreshSelf()
	end, raidIconDef.enabled ~= false, "raidicon")

	local raidIconSize = slider(L["Icon size"] or "Icon size", 10, 30, 1, function() return getValue(unit, { "raidIcon", "size" }, raidIconDef.size or 18) end, function(val)
		local v = val or raidIconDef.size or 18
		if v < 10 then v = 10 end
		if v > 30 then v = 30 end
		setValue(unit, { "raidIcon", "size" }, v)
		refreshSelf()
	end, raidIconDef.size or 18, "raidicon", true)
	raidIconSize.isEnabled = isRaidIconEnabled
	list[#list + 1] = raidIconSize

	local raidIconOffsetX = slider(
		L["Offset X"] or "Offset X",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return getValue(unit, { "raidIcon", "offset", "x" }, (raidIconDef.offset and raidIconDef.offset.x) or 0) end,
		function(val)
			setValue(unit, { "raidIcon", "offset", "x" }, val or 0)
			refreshSelf()
		end,
		(raidIconDef.offset and raidIconDef.offset.x) or 0,
		"raidicon",
		true
	)
	raidIconOffsetX.isEnabled = isRaidIconEnabled
	list[#list + 1] = raidIconOffsetX

	local raidIconOffsetY = slider(
		L["Offset Y"] or "Offset Y",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return getValue(unit, { "raidIcon", "offset", "y" }, (raidIconDef.offset and raidIconDef.offset.y) or 0) end,
		function(val)
			setValue(unit, { "raidIcon", "offset", "y" }, val or 0)
			refreshSelf()
		end,
		(raidIconDef.offset and raidIconDef.offset.y) or 0,
		"raidicon",
		true
	)
	raidIconOffsetY.isEnabled = isRaidIconEnabled
	list[#list + 1] = raidIconOffsetY

	if unit == "player" or unit == "target" or unit == "focus" or isBoss then
		local castDef = def.cast or {}
		list[#list + 1] = { name = L["CastBar"] or "Cast Bar", kind = settingType.Collapsible, id = "cast", defaultCollapsed = true }
		local function isCastEnabled() return getValue(unit, { "cast", "enabled" }, castDef.enabled ~= false) ~= false end
		local function isCastIconEnabled() return isCastEnabled() and getValue(unit, { "cast", "showIcon" }, castDef.showIcon ~= false) ~= false end
		local function isCastNameEnabled() return isCastEnabled() and getValue(unit, { "cast", "showName" }, castDef.showName ~= false) ~= false end
		local function isCastDurationEnabled() return isCastEnabled() and getValue(unit, { "cast", "showDuration" }, castDef.showDuration ~= false) ~= false end

		list[#list + 1] = checkbox(L["Show cast bar"] or "Show cast bar", function() return getValue(unit, { "cast", "enabled" }, castDef.enabled ~= false) ~= false end, function(val)
			setValue(unit, { "cast", "enabled" }, val and true or false)
			refresh()
			refreshSettingsUI()
		end, castDef.enabled ~= false, "cast")

		local castWidth = slider(L["UFWidth"] or "Frame width", 50, 800, 1, function() return getValue(unit, { "cast", "width" }, castDef.width or def.width or 220) end, function(val)
			setValue(unit, { "cast", "width" }, math.max(50, val or 50))
			refresh()
		end, castDef.width or def.width or 220, "cast", true)
		castWidth.isEnabled = isCastEnabled
		list[#list + 1] = castWidth

		local castHeight = slider(L["Cast bar height"] or "Cast bar height", 6, 40, 1, function() return getValue(unit, { "cast", "height" }, castDef.height or 16) end, function(val)
			setValue(unit, { "cast", "height" }, val or castDef.height or 16)
			refresh()
		end, castDef.height or 16, "cast", true)
		castHeight.isEnabled = isCastEnabled
		list[#list + 1] = castHeight

		local anchorOpts = {
			{ value = "TOP", label = L["Top"] or "Top" },
			{ value = "BOTTOM", label = L["Bottom"] or "Bottom" },
		}
		local castAnchor = radioDropdown(L["Anchor"] or "Anchor", anchorOpts, function() return getValue(unit, { "cast", "anchor" }, castDef.anchor or "BOTTOM") end, function(val)
			setValue(unit, { "cast", "anchor" }, val or "BOTTOM")
			refresh()
		end, castDef.anchor or "BOTTOM", "cast")
		castAnchor.isEnabled = isCastEnabled
		list[#list + 1] = castAnchor

		local castOffsetX = slider(
			L["Offset X"] or "Offset X",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "cast", "offset", "x" }, (castDef.offset and castDef.offset.x) or 0) end,
			function(val)
				setValue(unit, { "cast", "offset", "x" }, val or 0)
				refresh()
			end,
			(castDef.offset and castDef.offset.x) or 0,
			"cast",
			true
		)
		castOffsetX.isEnabled = isCastEnabled
		list[#list + 1] = castOffsetX

		local castOffsetY = slider(
			L["Offset Y"] or "Offset Y",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "cast", "offset", "y" }, (castDef.offset and castDef.offset.y) or 0) end,
			function(val)
				setValue(unit, { "cast", "offset", "y" }, val or 0)
				refresh()
			end,
			(castDef.offset and castDef.offset.y) or 0,
			"cast",
			true
		)
		castOffsetY.isEnabled = isCastEnabled
		list[#list + 1] = castOffsetY

		list[#list + 1] = checkbox(L["Show spell icon"] or "Show spell icon", function() return getValue(unit, { "cast", "showIcon" }, castDef.showIcon ~= false) ~= false end, function(val)
			setValue(unit, { "cast", "showIcon" }, val and true or false)
			refresh()
			refreshSettingsUI()
		end, castDef.showIcon ~= false, "cast", isCastEnabled)

		local castIconSize = slider(L["Icon size"] or "Icon size", 8, 64, 1, function() return getValue(unit, { "cast", "iconSize" }, castDef.iconSize or 22) end, function(val)
			setValue(unit, { "cast", "iconSize" }, val or castDef.iconSize or 22)
			refresh()
		end, castDef.iconSize or 22, "cast", true)
		castIconSize.isEnabled = isCastIconEnabled
		list[#list + 1] = castIconSize

		local castIconOffsetX = slider(
			L["Icon X Offset"] or "Icon X Offset",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "cast", "iconOffset", "x" }, (castDef.iconOffset and castDef.iconOffset.x) or -4) end,
			function(val)
				setValue(unit, { "cast", "iconOffset", "x" }, val or -4)
				refresh()
			end,
			(castDef.iconOffset and castDef.iconOffset.x) or -4,
			"cast",
			true
		)
		castIconOffsetX.isEnabled = isCastIconEnabled
		list[#list + 1] = castIconOffsetX

		list[#list + 1] = checkbox(L["Show spell name"] or "Show spell name", function() return getValue(unit, { "cast", "showName" }, castDef.showName ~= false) ~= false end, function(val)
			setValue(unit, { "cast", "showName" }, val and true or false)
			refresh()
			refreshSettingsUI()
		end, castDef.showName ~= false, "cast", isCastEnabled)

		if unit == "player" then
			list[#list + 1] = checkbox(
				L["Show cast target"] or "Show cast target",
				function() return getValue(unit, { "cast", "showCastTarget" }, castDef.showCastTarget == true) == true end,
				function(val)
					setValue(unit, { "cast", "showCastTarget" }, val and true or false)
					refresh()
					refreshSettingsUI()
				end,
				castDef.showCastTarget == true,
				"cast",
				isCastNameEnabled
			)
		end

		local castNameX = slider(
			L["Name X Offset"] or "Name X Offset",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "cast", "nameOffset", "x" }, (castDef.nameOffset and castDef.nameOffset.x) or 6) end,
			function(val)
				setValue(unit, { "cast", "nameOffset", "x" }, val or 0)
				refresh()
			end,
			(castDef.nameOffset and castDef.nameOffset.x) or 6,
			"cast",
			true
		)
		castNameX.isEnabled = isCastNameEnabled
		list[#list + 1] = castNameX

		local castNameY = slider(
			L["Name Y Offset"] or "Name Y Offset",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "cast", "nameOffset", "y" }, (castDef.nameOffset and castDef.nameOffset.y) or 0) end,
			function(val)
				setValue(unit, { "cast", "nameOffset", "y" }, val or 0)
				refresh()
			end,
			(castDef.nameOffset and castDef.nameOffset.y) or 0,
			"cast",
			true
		)
		castNameY.isEnabled = isCastNameEnabled
		list[#list + 1] = castNameY

		local function getCastFont() return getValue(unit, { "cast", "font" }, castDef.font or "") end

		local castNameFont = {
			name = L["Font"] or "Font",
			kind = settingType.DropdownColor,
			height = 180,
			parentId = "cast",
			default = castDef.font or "",
			generator = function(_, root)
				local opts = fontOptions()
				if type(opts) ~= "table" then return end
				for _, opt in ipairs(opts) do
					local value = opt.value
					local label = opt.label
					root:CreateCheckbox(label, function() return getCastFont() == value end, function()
						if getCastFont() ~= value then
							setValue(unit, { "cast", "font" }, value)
							refresh()
						end
					end)
				end
			end,
			colorDefault = { r = 1, g = 1, b = 1, a = 1 },
			colorGet = function()
				local fallback = castDef.fontColor or { 1, 1, 1, 1 }
				local r, g, b, a = toRGBA(getValue(unit, { "cast", "fontColor" }, castDef.fontColor), fallback)
				return { r = r, g = g, b = b, a = a }
			end,
			colorSet = function(_, color)
				setColor(unit, { "cast", "fontColor" }, color.r, color.g, color.b, color.a)
				refresh()
			end,
			hasOpacity = true,
		}
		castNameFont.isEnabled = isCastNameEnabled
		list[#list + 1] = castNameFont

		local castNameFontOutline = checkboxDropdown(
			L["Font outline"] or "Font outline",
			outlineOptions,
			function() return getValue(unit, { "cast", "fontOutline" }, castDef.fontOutline or "OUTLINE") end,
			function(val)
				setValue(unit, { "cast", "fontOutline" }, val)
				refresh()
			end,
			castDef.fontOutline or "OUTLINE",
			"cast"
		)
		castNameFontOutline.isEnabled = isCastNameEnabled
		list[#list + 1] = castNameFontOutline

		local castNameFontSize = slider(L["FontSize"] or "Font size", 8, 30, 1, function() return getValue(unit, { "cast", "fontSize" }, castDef.fontSize or 12) end, function(val)
			setValue(unit, { "cast", "fontSize" }, val or 12)
			refresh()
		end, castDef.fontSize or 12, "cast", true)
		castNameFontSize.isEnabled = isCastNameEnabled
		list[#list + 1] = castNameFontSize

		local castNameMaxCharsSetting = slider(
			L["UFCastNameMaxChars"] or "Cast name max width",
			0,
			100,
			1,
			function() return getValue(unit, { "cast", "nameMaxChars" }, castDef.nameMaxChars or 0) end,
			function(val)
				setValue(unit, { "cast", "nameMaxChars" }, val or 0)
				refresh()
			end,
			castDef.nameMaxChars or 0,
			"cast",
			true
		)
		castNameMaxCharsSetting.isEnabled = isCastNameEnabled
		list[#list + 1] = castNameMaxCharsSetting

		list[#list + 1] = checkbox(
			L["Show cast duration"] or "Show cast duration",
			function() return getValue(unit, { "cast", "showDuration" }, castDef.showDuration ~= false) ~= false end,
			function(val)
				setValue(unit, { "cast", "showDuration" }, val and true or false)
				refresh()
				refreshSettingsUI()
			end,
			castDef.showDuration ~= false,
			"cast",
			isCastEnabled
		)

		local castDurationFormatOptions = {
			{ value = "REMAINING", label = L["UFCastDurationRemaining"] or "Remaining" },
			{ value = "ELAPSED_TOTAL", label = L["UFCastDurationElapsedTotal"] or "Elapsed/Total" },
		}

		local castDurationFormat = checkboxDropdown(
			L["UFCastDurationFormat"] or "Cast duration format",
			castDurationFormatOptions,
			function() return getValue(unit, { "cast", "durationFormat" }, castDef.durationFormat or "REMAINING") end,
			function(val)
				setValue(unit, { "cast", "durationFormat" }, val or "REMAINING")
				refresh()
			end,
			castDef.durationFormat or "REMAINING",
			"cast"
		)
		castDurationFormat.isEnabled = isCastDurationEnabled
		list[#list + 1] = castDurationFormat

		local castDurX = slider(
			L["Duration X Offset"] or "Duration X Offset",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "cast", "durationOffset", "x" }, (castDef.durationOffset and castDef.durationOffset.x) or -6) end,
			function(val)
				setValue(unit, { "cast", "durationOffset", "x" }, val or 0)
				refresh()
			end,
			(castDef.durationOffset and castDef.durationOffset.x) or -6,
			"cast",
			true
		)

		castDurX.isEnabled = isCastDurationEnabled
		list[#list + 1] = castDurX

		local castDurY = slider(
			L["Duration Y Offset"] or "Duration Y Offset",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "cast", "durationOffset", "y" }, (castDef.durationOffset and castDef.durationOffset.y) or 0) end,
			function(val)
				setValue(unit, { "cast", "durationOffset", "y" }, val or 0)
				refresh()
			end,
			(castDef.durationOffset and castDef.durationOffset.y) or 0,
			"cast",
			true
		)
		castDurY.isEnabled = isCastDurationEnabled
		list[#list + 1] = castDurY

		local castTexture = checkboxDropdown(L["Cast texture"] or "Cast texture", textureOpts, function() return getValue(unit, { "cast", "texture" }, castDef.texture or "DEFAULT") end, function(val)
			setValue(unit, { "cast", "texture" }, val)
			refresh()
		end, castDef.texture or "DEFAULT", "cast")
		castTexture.isEnabled = isCastEnabled
		list[#list + 1] = castTexture

		local castBackdrop = checkboxColor({
			name = L["UFBarBackdrop"] or "Show bar backdrop",
			parentId = "cast",
			defaultChecked = (castDef.backdrop and castDef.backdrop.enabled) ~= false,
			isChecked = function() return getValue(unit, { "cast", "backdrop", "enabled" }, (castDef.backdrop and castDef.backdrop.enabled) ~= false) ~= false end,
			onChecked = function(val)
				setValue(unit, { "cast", "backdrop", "enabled" }, val and true or false)
				refresh()
				refreshSettingsUI()
			end,
			getColor = function()
				return toRGBA(getValue(unit, { "cast", "backdrop", "color" }, castDef.backdrop and castDef.backdrop.color), castDef.backdrop and castDef.backdrop.color or { 0, 0, 0, 0.6 })
			end,
			onColor = function(color)
				setColor(unit, { "cast", "backdrop", "color" }, color.r, color.g, color.b, color.a)
				refresh()
			end,
			colorDefault = { r = 0, g = 0, b = 0, a = 0.6 },
			isEnabled = isCastEnabled,
		})
		castBackdrop.isEnabled = isCastEnabled
		list[#list + 1] = castBackdrop

		list[#list + 1] = {
			name = L["Cast color"] or "Cast color",
			kind = settingType.Color,
			parentId = "cast",
			isEnabled = isCastEnabled,
			get = function() return getValue(unit, { "cast", "color" }, castDef.color or { 0.9, 0.7, 0.2, 1 }) end,
			set = function(_, color)
				setColor(unit, { "cast", "color" }, color.r, color.g, color.b, color.a)
				refresh()
			end,
			colorGet = function() return getValue(unit, { "cast", "color" }, castDef.color or { 0.9, 0.7, 0.2, 1 }) end,
			colorSet = function(_, color)
				setColor(unit, { "cast", "color" }, color.r, color.g, color.b, color.a)
				refresh()
			end,
			colorDefault = {
				r = (castDef.color and castDef.color[1]) or 0.9,
				g = (castDef.color and castDef.color[2]) or 0.7,
				b = (castDef.color and castDef.color[3]) or 0.2,
				a = (castDef.color and castDef.color[4]) or 1,
			},
			hasOpacity = true,
		}

		list[#list + 1] = {
			name = L["Not interruptible color"] or "Not interruptible color",
			kind = settingType.Color,
			parentId = "cast",
			isEnabled = isCastEnabled,
			get = function() return getValue(unit, { "cast", "notInterruptibleColor" }, castDef.notInterruptibleColor or { 204 / 255, 204 / 255, 204 / 255, 1 }) end,
			set = function(_, color)
				setColor(unit, { "cast", "notInterruptibleColor" }, color.r, color.g, color.b, color.a)
				refresh()
			end,
			colorGet = function() return getValue(unit, { "cast", "notInterruptibleColor" }, castDef.notInterruptibleColor or { 204 / 255, 204 / 255, 204 / 255, 1 }) end,
			colorSet = function(_, color)
				setColor(unit, { "cast", "notInterruptibleColor" }, color.r, color.g, color.b, color.a)
				refresh()
			end,
			colorDefault = {
				r = (castDef.notInterruptibleColor and castDef.notInterruptibleColor[1]) or (204 / 255),
				g = (castDef.notInterruptibleColor and castDef.notInterruptibleColor[2]) or (204 / 255),
				b = (castDef.notInterruptibleColor and castDef.notInterruptibleColor[3]) or (204 / 255),
				a = (castDef.notInterruptibleColor and castDef.notInterruptibleColor[4]) or 1,
			},
			hasOpacity = true,
		}
	end

	list[#list + 1] = { name = L["UFStatusLine"] or "Status line", kind = settingType.Collapsible, id = "status", defaultCollapsed = true }
	local statusDef = def.status or {}
	local function isNameEnabled() return getValue(unit, { "status", "enabled" }, statusDef.enabled ~= false) ~= false end
	local function isLevelEnabled() return getValue(unit, { "status", "levelEnabled" }, statusDef.levelEnabled ~= false) ~= false end
	local function isUnitStatusEnabled() return getValue(unit, { "status", "unitStatus", "enabled" }, (statusDef.unitStatus and statusDef.unitStatus.enabled) == true) == true end
	local function isStatusTextEnabled() return isNameEnabled() or isLevelEnabled() or isUnitStatusEnabled() end
	local classIconDef = statusDef.classificationIcon or { enabled = false, hideText = false, size = 16, offset = { x = -4, y = 0 } }
	local function isClassificationIconEnabled() return getValue(unit, { "status", "classificationIcon", "enabled" }, classIconDef.enabled == true) == true end

	local showNameToggle = checkbox(L["UFStatusEnable"] or "Show status line", isNameEnabled, function(val)
		setValue(unit, { "status", "enabled" }, val and true or false)
		refresh()
		refreshSettingsUI()
	end, statusDef.enabled ~= false, "status")
	list[#list + 1] = showNameToggle

	local nameColorSetting = checkboxColor({
		name = L["UFNameColor"] or "Custom name color",
		parentId = "status",
		defaultChecked = (statusDef.nameColorMode or "CLASS") ~= "CLASS",
		isChecked = function() return getValue(unit, { "status", "nameColorMode" }, statusDef.nameColorMode or "CLASS") ~= "CLASS" end,
		onChecked = function(val)
			setValue(unit, { "status", "nameColorMode" }, val and "CUSTOM" or "CLASS")
			refresh()
		end,
		getColor = function() return toRGBA(getValue(unit, { "status", "nameColor" }, statusDef.nameColor or { 0.8, 0.8, 1, 1 }), statusDef.nameColor or { 0.8, 0.8, 1, 1 }) end,
		onColor = function(color)
			setColor(unit, { "status", "nameColor" }, color.r, color.g, color.b, color.a)
			setValue(unit, { "status", "nameColorMode" }, "CUSTOM")
			refresh()
		end,
		colorDefault = {
			r = (statusDef.nameColor and statusDef.nameColor[1]) or 0.8,
			g = (statusDef.nameColor and statusDef.nameColor[2]) or 0.8,
			b = (statusDef.nameColor and statusDef.nameColor[3]) or 1,
			a = (statusDef.nameColor and statusDef.nameColor[4]) or 1,
		},
	})
	nameColorSetting.isEnabled = isNameEnabled
	list[#list + 1] = nameColorSetting

	local nameAnchorSetting = radioDropdown(
		L["UFNameAnchor"] or "Name anchor",
		anchorOptions,
		function() return getValue(unit, { "status", "nameAnchor" }, statusDef.nameAnchor or "LEFT") end,
		function(val)
			setValue(unit, { "status", "nameAnchor" }, val)
			refresh()
		end,
		statusDef.nameAnchor or "LEFT",
		"status"
	)
	nameAnchorSetting.isEnabled = isNameEnabled
	list[#list + 1] = nameAnchorSetting

	local nameFontSizeSetting = slider(L["Name font size"] or "Name font size", 8, 30, 1, function() return getValue(unit, { "status", "nameFontSize" }, statusDef.fontSize or 14) end, function(val)
		debounced(unit .. "_statusNameFontSize", function()
			setValue(unit, { "status", "nameFontSize" }, val or statusDef.fontSize or 14)
			refreshSelf()
		end)
	end, statusDef.fontSize or 14, "status", true)
	nameFontSizeSetting.isEnabled = isNameEnabled
	list[#list + 1] = nameFontSizeSetting

	local nameMaxCharsSetting = slider(
		L["UFNameMaxChars"] or "Name max width",
		0,
		100,
		1,
		function() return getValue(unit, { "status", "nameMaxChars" }, statusDef.nameMaxChars or 0) end,
		function(val)
			setValue(unit, { "status", "nameMaxChars" }, val or 0)
			refresh()
		end,
		statusDef.nameMaxChars or 15,
		"status",
		true
	)
	nameMaxCharsSetting.isEnabled = isNameEnabled
	list[#list + 1] = nameMaxCharsSetting

	local nameOffsetXSetting = slider(
		L["UFNameX"] or "Name X offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return getValue(unit, { "status", "nameOffset", "x" }, (statusDef.nameOffset and statusDef.nameOffset.x) or 0) end,
		function(val)
			setValue(unit, { "status", "nameOffset", "x" }, val or 0)
			refresh()
		end,
		(statusDef.nameOffset and statusDef.nameOffset.x) or 0,
		"status",
		true
	)
	nameOffsetXSetting.isEnabled = isNameEnabled
	list[#list + 1] = nameOffsetXSetting

	local nameOffsetYSetting = slider(
		L["UFNameY"] or "Name Y offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return getValue(unit, { "status", "nameOffset", "y" }, (statusDef.nameOffset and statusDef.nameOffset.y) or 0) end,
		function(val)
			setValue(unit, { "status", "nameOffset", "y" }, val or 0)
			refresh()
		end,
		(statusDef.nameOffset and statusDef.nameOffset.y) or 0,
		"status",
		true
	)
	nameOffsetYSetting.isEnabled = isNameEnabled
	list[#list + 1] = nameOffsetYSetting

	local showLevelToggle = checkbox(L["UFShowLevel"] or "Show level", function() return getValue(unit, { "status", "levelEnabled" }, statusDef.levelEnabled ~= false) end, function(val)
		setValue(unit, { "status", "levelEnabled" }, val and true or false)
		refresh()
		refreshSettingsUI()
	end, statusDef.levelEnabled ~= false, "status")
	list[#list + 1] = showLevelToggle

	local hideLevelAtMaxToggle = checkbox(
		L["UFHideLevelAtMax"] or "Hide at max level",
		function() return getValue(unit, { "status", "hideLevelAtMax" }, statusDef.hideLevelAtMax == true) end,
		function(val)
			setValue(unit, { "status", "hideLevelAtMax" }, val and true or false)
			refresh()
		end,
		statusDef.hideLevelAtMax == true,
		"status"
	)
	hideLevelAtMaxToggle.isEnabled = isLevelEnabled
	list[#list + 1] = hideLevelAtMaxToggle

	local levelColorSetting = checkboxColor({
		name = L["UFLevelColor"] or "Custom level color",
		parentId = "status",
		defaultChecked = (statusDef.levelColorMode or "CLASS") ~= "CLASS",
		isChecked = function() return getValue(unit, { "status", "levelColorMode" }, statusDef.levelColorMode or "CLASS") ~= "CLASS" end,
		onChecked = function(val)
			setValue(unit, { "status", "levelColorMode" }, val and "CUSTOM" or "CLASS")
			refresh()
		end,
		getColor = function() return toRGBA(getValue(unit, { "status", "levelColor" }, statusDef.levelColor or { 1, 0.85, 0, 1 }), statusDef.levelColor or { 1, 0.85, 0, 1 }) end,
		onColor = function(color)
			setColor(unit, { "status", "levelColor" }, color.r, color.g, color.b, color.a)
			setValue(unit, { "status", "levelColorMode" }, "CUSTOM")
			refresh()
		end,
		colorDefault = {
			r = (statusDef.levelColor and statusDef.levelColor[1]) or 1,
			g = (statusDef.levelColor and statusDef.levelColor[2]) or 0.85,
			b = (statusDef.levelColor and statusDef.levelColor[3]) or 0,
			a = (statusDef.levelColor and statusDef.levelColor[4]) or 1,
		},
	})
	levelColorSetting.isEnabled = isLevelEnabled
	list[#list + 1] = levelColorSetting

	local levelAnchorSetting = radioDropdown(
		L["UFLevelAnchor"] or "Level anchor",
		anchorOptions,
		function() return getValue(unit, { "status", "levelAnchor" }, statusDef.levelAnchor or "RIGHT") end,
		function(val)
			setValue(unit, { "status", "levelAnchor" }, val)
			refresh()
		end,
		statusDef.levelAnchor or "RIGHT",
		"status"
	)
	levelAnchorSetting.isEnabled = isLevelEnabled
	list[#list + 1] = levelAnchorSetting

	local levelFontSizeSetting = slider(
		L["Level font size"] or "Level font size",
		8,
		30,
		1,
		function() return getValue(unit, { "status", "levelFontSize" }, statusDef.fontSize or 14) end,
		function(val)
			debounced(unit .. "_statusLevelFontSize", function()
				setValue(unit, { "status", "levelFontSize" }, val or statusDef.fontSize or 14)
				refreshSelf()
			end)
		end,
		statusDef.fontSize or 14,
		"status",
		true
	)
	levelFontSizeSetting.isEnabled = isLevelEnabled
	list[#list + 1] = levelFontSizeSetting

	local levelOffsetXSetting = slider(
		L["UFLevelX"] or "Level X offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return getValue(unit, { "status", "levelOffset", "x" }, (statusDef.levelOffset and statusDef.levelOffset.x) or 0) end,
		function(val)
			setValue(unit, { "status", "levelOffset", "x" }, val or 0)
			refresh()
		end,
		(statusDef.levelOffset and statusDef.levelOffset.x) or 0,
		"status",
		true
	)
	levelOffsetXSetting.isEnabled = isLevelEnabled
	list[#list + 1] = levelOffsetXSetting

	local levelOffsetYSetting = slider(
		L["UFLevelY"] or "Level Y offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return getValue(unit, { "status", "levelOffset", "y" }, (statusDef.levelOffset and statusDef.levelOffset.y) or 0) end,
		function(val)
			setValue(unit, { "status", "levelOffset", "y" }, val or 0)
			refresh()
		end,
		(statusDef.levelOffset and statusDef.levelOffset.y) or 0,
		"status",
		true
	)
	levelOffsetYSetting.isEnabled = isLevelEnabled
	list[#list + 1] = levelOffsetYSetting

	if not isPlayer then
		list[#list + 1] = checkbox(L["UFShowClassificationIcon"] or "Show elite/rare icon", isClassificationIconEnabled, function(val)
			setValue(unit, { "status", "classificationIcon", "enabled" }, val and true or false)
			refresh()
			refreshSettingsUI()
		end, classIconDef.enabled == true, "status")

		local hideClassTextToggle = checkbox(
			L["UFClassificationIconHideText"] or "Hide elite/rare text indicators",
			function() return getValue(unit, { "status", "classificationIcon", "hideText" }, classIconDef.hideText == true) == true end,
			function(val)
				setValue(unit, { "status", "classificationIcon", "hideText" }, val and true or false)
				refresh()
			end,
			classIconDef.hideText == true,
			"status"
		)
		hideClassTextToggle.isEnabled = isClassificationIconEnabled
		hideClassTextToggle.isShown = isClassificationIconEnabled
		list[#list + 1] = hideClassTextToggle

		local classIconSize = slider(L["Icon size"] or "Icon size", 8, 40, 1, function() return getValue(unit, { "status", "classificationIcon", "size" }, classIconDef.size or 16) end, function(val)
			local v = val or classIconDef.size or 16
			setValue(unit, { "status", "classificationIcon", "size" }, v)
			refresh()
		end, classIconDef.size or 16, "status", true)
		classIconSize.isEnabled = isClassificationIconEnabled
		classIconSize.isShown = isClassificationIconEnabled
		list[#list + 1] = classIconSize

		local classIconOffsetX = slider(
			L["UFClassificationIconOffsetX"] or "Elite/rare icon X offset",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "status", "classificationIcon", "offset", "x" }, (classIconDef.offset and classIconDef.offset.x) or -4) end,
			function(val)
				local off = getValue(unit, { "status", "classificationIcon", "offset" }, { x = -4, y = 0 }) or {}
				off.x = val or 0
				setValue(unit, { "status", "classificationIcon", "offset" }, off)
				refresh()
			end,
			(classIconDef.offset and classIconDef.offset.x) or -4,
			"status",
			true
		)
		classIconOffsetX.isEnabled = isClassificationIconEnabled
		classIconOffsetX.isShown = isClassificationIconEnabled
		list[#list + 1] = classIconOffsetX

		local classIconOffsetY = slider(
			L["UFClassificationIconOffsetY"] or "Elite/rare icon Y offset",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "status", "classificationIcon", "offset", "y" }, (classIconDef.offset and classIconDef.offset.y) or 0) end,
			function(val)
				local off = getValue(unit, { "status", "classificationIcon", "offset" }, { x = -4, y = 0 }) or {}
				off.y = val or 0
				setValue(unit, { "status", "classificationIcon", "offset" }, off)
				refresh()
			end,
			(classIconDef.offset and classIconDef.offset.y) or 0,
			"status",
			true
		)
		classIconOffsetY.isEnabled = isClassificationIconEnabled
		classIconOffsetY.isShown = isClassificationIconEnabled
		list[#list + 1] = classIconOffsetY
	end

	if #fontOptions() > 0 then
		local statusFont = checkboxDropdown(L["Font"] or "Font", fontOptions, function() return getValue(unit, { "status", "font" }, statusDef.font or defaultFontPath()) end, function(val)
			setValue(unit, { "status", "font" }, val)
			refreshSelf()
		end, statusDef.font or defaultFontPath(), "status")
		statusFont.isEnabled = isStatusTextEnabled
		list[#list + 1] = statusFont
	end

	local statusFontOutline = checkboxDropdown(
		L["Font outline"] or "Font outline",
		outlineOptions,
		function() return getValue(unit, { "status", "fontOutline" }, statusDef.fontOutline or "OUTLINE") end,
		function(val)
			setValue(unit, { "status", "fontOutline" }, val)
			refreshSelf()
		end,
		statusDef.fontOutline or "OUTLINE",
		"status"
	)
	statusFontOutline.isEnabled = isStatusTextEnabled
	list[#list + 1] = statusFontOutline

	local usDef = statusDef.unitStatus or {}

	list[#list + 1] = { name = L["UFUnitStatus"] or "Unit status", kind = settingType.Collapsible, id = "unitStatus", defaultCollapsed = true }

	if unit == "player" or unit == "target" or unit == "focus" then
		local pvpDef = def.pvpIndicator or { enabled = false, size = 20, offset = { x = -24, y = -2 } }
		local function isPvPIndicatorEnabled() return getValue(unit, { "pvpIndicator", "enabled" }, pvpDef.enabled == true) == true end

		list[#list + 1] = checkbox(L["UFPvPIndicatorEnable"] or "Show PvP indicator", isPvPIndicatorEnabled, function(val)
			setValue(unit, { "pvpIndicator", "enabled" }, val and true or false)
			refreshSelf()
		end, pvpDef.enabled == true, "unitStatus")

		local pvpIconSize = slider(L["Icon size"] or "Icon size", 10, 40, 1, function() return getValue(unit, { "pvpIndicator", "size" }, pvpDef.size or 20) end, function(val)
			local v = val or pvpDef.size or 20
			if v < 10 then v = 10 end
			if v > 40 then v = 40 end
			setValue(unit, { "pvpIndicator", "size" }, v)
			refreshSelf()
		end, pvpDef.size or 20, "unitStatus", true)
		pvpIconSize.isEnabled = isPvPIndicatorEnabled
		list[#list + 1] = pvpIconSize

		local pvpOffsetX = slider(
			L["Offset X"] or "Offset X",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "pvpIndicator", "offset", "x" }, (pvpDef.offset and pvpDef.offset.x) or 0) end,
			function(val)
				setValue(unit, { "pvpIndicator", "offset", "x" }, val or 0)
				refreshSelf()
			end,
			(pvpDef.offset and pvpDef.offset.x) or 0,
			"unitStatus",
			true
		)
		pvpOffsetX.isEnabled = isPvPIndicatorEnabled
		list[#list + 1] = pvpOffsetX

		local pvpOffsetY = slider(
			L["Offset Y"] or "Offset Y",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "pvpIndicator", "offset", "y" }, (pvpDef.offset and pvpDef.offset.y) or 0) end,
			function(val)
				setValue(unit, { "pvpIndicator", "offset", "y" }, val or 0)
				refreshSelf()
			end,
			(pvpDef.offset and pvpDef.offset.y) or 0,
			"unitStatus",
			true
		)
		pvpOffsetY.isEnabled = isPvPIndicatorEnabled
		list[#list + 1] = pvpOffsetY

		local roleDef = def.roleIndicator or { enabled = false, size = 18, offset = { x = 24, y = -2 } }
		local function isRoleIndicatorEnabled() return getValue(unit, { "roleIndicator", "enabled" }, roleDef.enabled == true) == true end

		list[#list + 1] = checkbox(L["UFRoleIndicatorEnable"] or "Show role indicator", isRoleIndicatorEnabled, function(val)
			setValue(unit, { "roleIndicator", "enabled" }, val and true or false)
			refreshSelf()
		end, roleDef.enabled == true, "unitStatus")

		local roleIconSize = slider(L["Icon size"] or "Icon size", 10, 40, 1, function() return getValue(unit, { "roleIndicator", "size" }, roleDef.size or 18) end, function(val)
			local v = val or roleDef.size or 18
			if v < 10 then v = 10 end
			if v > 40 then v = 40 end
			setValue(unit, { "roleIndicator", "size" }, v)
			refreshSelf()
		end, roleDef.size or 18, "unitStatus", true)
		roleIconSize.isEnabled = isRoleIndicatorEnabled
		list[#list + 1] = roleIconSize

		local roleOffsetX = slider(
			L["UFRoleIndicatorOffsetX"] or "Role indicator X offset",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "roleIndicator", "offset", "x" }, (roleDef.offset and roleDef.offset.x) or 0) end,
			function(val)
				setValue(unit, { "roleIndicator", "offset", "x" }, val or 0)
				refreshSelf()
			end,
			(roleDef.offset and roleDef.offset.x) or 0,
			"unitStatus",
			true
		)
		roleOffsetX.isEnabled = isRoleIndicatorEnabled
		list[#list + 1] = roleOffsetX

		local roleOffsetY = slider(
			L["UFRoleIndicatorOffsetY"] or "Role indicator Y offset",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "roleIndicator", "offset", "y" }, (roleDef.offset and roleDef.offset.y) or 0) end,
			function(val)
				setValue(unit, { "roleIndicator", "offset", "y" }, val or 0)
				refreshSelf()
			end,
			(roleDef.offset and roleDef.offset.y) or 0,
			"unitStatus",
			true
		)
		roleOffsetY.isEnabled = isRoleIndicatorEnabled
		list[#list + 1] = roleOffsetY
	end

	list[#list + 1] = checkbox(L["UFUnitStatusEnable"] or "Show unit status", function() return getValue(unit, { "status", "unitStatus", "enabled" }, usDef.enabled == true) == true end, function(val)
		setValue(unit, { "status", "unitStatus", "enabled" }, val and true or false)
		refresh()
		refreshSettingsUI()
	end, usDef.enabled == true, "unitStatus")

	local unitStatusOffsetX = slider(
		L["UFUnitStatusOffsetX"] or "Unit status X offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return getValue(unit, { "status", "unitStatus", "offset", "x" }, (usDef.offset and usDef.offset.x) or 0) end,
		function(val)
			local off = getValue(unit, { "status", "unitStatus", "offset" }, { x = 0, y = 0 }) or {}
			off.x = val or 0
			setValue(unit, { "status", "unitStatus", "offset" }, off)
			refresh()
		end,
		(usDef.offset and usDef.offset.x) or 0,
		"unitStatus",
		true
	)
	unitStatusOffsetX.isEnabled = isUnitStatusEnabled
	list[#list + 1] = unitStatusOffsetX

	local unitStatusOffsetY = slider(
		L["UFUnitStatusOffsetY"] or "Unit status Y offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return getValue(unit, { "status", "unitStatus", "offset", "y" }, (usDef.offset and usDef.offset.y) or 0) end,
		function(val)
			local off = getValue(unit, { "status", "unitStatus", "offset" }, { x = 0, y = 0 }) or {}
			off.y = val or 0
			setValue(unit, { "status", "unitStatus", "offset" }, off)
			refresh()
		end,
		(usDef.offset and usDef.offset.y) or 0,
		"unitStatus",
		true
	)
	unitStatusOffsetY.isEnabled = isUnitStatusEnabled
	list[#list + 1] = unitStatusOffsetY

	local unitStatusFontSizeSetting = slider(
		L["FontSize"] or "Font size",
		8,
		30,
		1,
		function() return getValue(unit, { "status", "unitStatus", "fontSize" }, usDef.fontSize or statusDef.fontSize or 14) end,
		function(val)
			debounced(unit .. "_unitStatusFontSize", function()
				setValue(unit, { "status", "unitStatus", "fontSize" }, val or statusDef.fontSize or 14)
				refreshSelf()
			end)
		end,
		usDef.fontSize or statusDef.fontSize or 14,
		"unitStatus",
		true
	)
	unitStatusFontSizeSetting.isEnabled = isUnitStatusEnabled
	list[#list + 1] = unitStatusFontSizeSetting

	if #fontOptions() > 0 then
		local unitStatusFontSetting = checkboxDropdown(
			L["Font"] or "Font",
			fontOptions,
			function() return getValue(unit, { "status", "unitStatus", "font" }, usDef.font or statusDef.font or defaultFontPath()) end,
			function(val)
				setValue(unit, { "status", "unitStatus", "font" }, val)
				refreshSelf()
			end,
			usDef.font or statusDef.font or defaultFontPath(),
			"unitStatus"
		)
		unitStatusFontSetting.isEnabled = isUnitStatusEnabled
		list[#list + 1] = unitStatusFontSetting
	end

	local unitStatusFontOutlineSetting = checkboxDropdown(
		L["Font outline"] or "Font outline",
		outlineOptions,
		function() return getValue(unit, { "status", "unitStatus", "fontOutline" }, usDef.fontOutline or statusDef.fontOutline or "OUTLINE") end,
		function(val)
			setValue(unit, { "status", "unitStatus", "fontOutline" }, val)
			refreshSelf()
		end,
		usDef.fontOutline or statusDef.fontOutline or "OUTLINE",
		"unitStatus"
	)
	unitStatusFontOutlineSetting.isEnabled = isUnitStatusEnabled
	list[#list + 1] = unitStatusFontOutlineSetting

	if unit == "player" then
		local function isGroupEnabled() return isUnitStatusEnabled() and getValue(unit, { "status", "unitStatus", "showGroup" }, usDef.showGroup == true) == true end

		list[#list + 1] = checkbox(
			L["UFUnitStatusShowGroup"] or "Show group number",
			function() return getValue(unit, { "status", "unitStatus", "showGroup" }, usDef.showGroup == true) == true end,
			function(val)
				setValue(unit, { "status", "unitStatus", "showGroup" }, val and true or false)
				refresh()
			end,
			usDef.showGroup == true,
			"unitStatus"
		)
		list[#list].isEnabled = isUnitStatusEnabled

		list[#list + 1] = slider(
			L["UFUnitStatusGroupSize"] or "Group number size",
			8,
			30,
			1,
			function() return getValue(unit, { "status", "unitStatus", "groupFontSize" }, usDef.groupFontSize or usDef.fontSize or statusDef.fontSize or 14) end,
			function(val)
				setValue(unit, { "status", "unitStatus", "groupFontSize" }, val or usDef.fontSize or statusDef.fontSize or 14)
				refresh()
			end,
			usDef.groupFontSize or usDef.fontSize or statusDef.fontSize or 14,
			"unitStatus",
			true
		)
		list[#list].isEnabled = isGroupEnabled

		list[#list + 1] = slider(
			L["UFUnitStatusGroupOffsetX"] or "Group number X offset",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "status", "unitStatus", "groupOffset", "x" }, (usDef.groupOffset and usDef.groupOffset.x) or 0) end,
			function(val)
				local off = getValue(unit, { "status", "unitStatus", "groupOffset" }, { x = 0, y = 0 }) or {}
				off.x = val or 0
				setValue(unit, { "status", "unitStatus", "groupOffset" }, off)
				refresh()
			end,
			(usDef.groupOffset and usDef.groupOffset.x) or 0,
			"unitStatus",
			true
		)
		list[#list].isEnabled = isGroupEnabled

		list[#list + 1] = slider(
			L["UFUnitStatusGroupOffsetY"] or "Group number Y offset",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "status", "unitStatus", "groupOffset", "y" }, (usDef.groupOffset and usDef.groupOffset.y) or 0) end,
			function(val)
				local off = getValue(unit, { "status", "unitStatus", "groupOffset" }, { x = 0, y = 0 }) or {}
				off.y = val or 0
				setValue(unit, { "status", "unitStatus", "groupOffset" }, off)
				refresh()
			end,
			(usDef.groupOffset and usDef.groupOffset.y) or 0,
			"unitStatus",
			true
		)
		list[#list].isEnabled = isGroupEnabled

		local restDef = def.resting or {}
		local function isRestEnabled() return getValue(unit, { "resting", "enabled" }, restDef.enabled ~= false) ~= false end

		list[#list + 1] = checkbox(L["UFRestingEnable"] or "Show resting indicator", function() return getValue(unit, { "resting", "enabled" }, restDef.enabled ~= false) ~= false end, function(val)
			setValue(unit, { "resting", "enabled" }, val and true or false)
			refresh()
		end, restDef.enabled ~= false, "unitStatus")

		list[#list + 1] = slider(L["UFRestingSize"] or "Resting size", 10, 80, 1, function() return getValue(unit, { "resting", "size" }, restDef.size or 20) end, function(val)
			setValue(unit, { "resting", "size" }, val or restDef.size or 20)
			refresh()
		end, restDef.size or 20, "unitStatus", true)
		list[#list].isEnabled = isRestEnabled

		list[#list + 1] = slider(
			L["UFRestingOffsetX"] or "Resting offset X",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "resting", "offset", "x" }, (restDef.offset and restDef.offset.x) or 0) end,
			function(val)
				local defx = (restDef.offset and restDef.offset.x) or 0
				local off = getValue(unit, { "resting", "offset" }, { x = defx, y = 0 }) or {}
				off.x = val ~= nil and val or defx
				setValue(unit, { "resting", "offset" }, off)
				refresh()
			end,
			(restDef.offset and restDef.offset.x) or 0,
			"unitStatus",
			true
		)
		list[#list].isEnabled = isRestEnabled

		list[#list + 1] = slider(
			L["UFRestingOffsetY"] or "Resting offset Y",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "resting", "offset", "y" }, (restDef.offset and restDef.offset.y) or 0) end,
			function(val)
				local defy = (restDef.offset and restDef.offset.y) or 0
				local off = getValue(unit, { "resting", "offset" }, { x = 0, y = defy }) or {}
				off.y = val ~= nil and val or defy
				setValue(unit, { "resting", "offset" }, off)
				refresh()
			end,
			(restDef.offset and restDef.offset.y) or 0,
			"unitStatus",
			true
		)
		list[#list].isEnabled = isRestEnabled
	end

	if isPlayer then
		local ciDef = statusDef.combatIndicator or {}
		local function isCombatIndicatorEnabled() return getValue(unit, { "status", "combatIndicator", "enabled" }, ciDef.enabled ~= false) ~= false end
		local combatIndicatorToggle = checkbox(
			L["UFCombatIndicator"] or "Show combat indicator",
			function() return getValue(unit, { "status", "combatIndicator", "enabled" }, ciDef.enabled ~= false) end,
			function(val)
				setValue(unit, { "status", "combatIndicator", "enabled" }, val and true or false)
				refresh()
				refreshSettingsUI()
			end,
			ciDef.enabled ~= false,
			"unitStatus"
		)
		list[#list + 1] = combatIndicatorToggle

		local combatIndicatorSize = slider(
			L["UFCombatIndicatorSize"] or "Combat indicator size",
			10,
			64,
			1,
			function() return getValue(unit, { "status", "combatIndicator", "size" }, ciDef.size or 18) end,
			function(val)
				setValue(unit, { "status", "combatIndicator", "size" }, val or ciDef.size or 18)
				refresh()
			end,
			ciDef.size or 18,
			"unitStatus",
			true
		)
		combatIndicatorSize.isEnabled = isCombatIndicatorEnabled
		list[#list + 1] = combatIndicatorSize

		local combatIndicatorOffsetX = slider(
			L["UFCombatIndicatorOffsetX"] or "Combat indicator X offset",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "status", "combatIndicator", "offset", "x" }, (ciDef.offset and ciDef.offset.x) or -8) end,
			function(val)
				local off = getValue(unit, { "status", "combatIndicator", "offset" }, { x = -8, y = 0 }) or {}
				off.x = val or -8
				setValue(unit, { "status", "combatIndicator", "offset" }, off)
				refresh()
			end,
			(ciDef.offset and ciDef.offset.x) or -8,
			"unitStatus",
			true
		)
		combatIndicatorOffsetX.isEnabled = isCombatIndicatorEnabled
		list[#list + 1] = combatIndicatorOffsetX

		local combatIndicatorOffsetY = slider(
			L["UFCombatIndicatorOffsetY"] or "Combat indicator Y offset",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "status", "combatIndicator", "offset", "y" }, (ciDef.offset and ciDef.offset.y) or 0) end,
			function(val)
				local off = getValue(unit, { "status", "combatIndicator", "offset" }, { x = -8, y = 0 }) or {}
				off.y = val or 0
				setValue(unit, { "status", "combatIndicator", "offset" }, off)
				refresh()
			end,
			(ciDef.offset and ciDef.offset.y) or 0,
			"unitStatus",
			true
		)
		combatIndicatorOffsetY.isEnabled = isCombatIndicatorEnabled
		list[#list + 1] = combatIndicatorOffsetY
	end

	if unit == "player" or unit == "target" or isBossUnit(unit) then
		list[#list + 1] = { name = L["Auras"] or "Auras", kind = settingType.Collapsible, id = "auras", defaultCollapsed = true }
		local auraDef = def.auraIcons or { enabled = true, size = 24, padding = 2, max = 16, showCooldown = true }
		local function debuffAnchorValue() return getValue(unit, { "auraIcons", "debuffAnchor" }, getValue(unit, { "auraIcons", "anchor" }, auraDef.debuffAnchor or auraDef.anchor or "BOTTOM")) end
		local function defaultAuraOffset(anchor)
			if anchor == "TOP" then return 0, 5 end
			if anchor == "LEFT" then return -5, 0 end
			if anchor == "RIGHT" then return 5, 0 end
			return 0, -5
		end
		local function defaultAuraOffsetX(anchor)
			local x = defaultAuraOffset(anchor)
			return x
		end
		local function defaultAuraOffsetY(anchor)
			local _, y = defaultAuraOffset(anchor)
			return y
		end
		local function debuffOffsetYDefault() return defaultAuraOffsetY(debuffAnchorValue()) end
		local function isAuraEnabled() return getValue(unit, { "auraIcons", "enabled" }, auraDef.enabled ~= false) ~= false end
		local function refreshAuras()
			if not (UF and UF.FullScanTargetAuras) then return end
			if unit == "boss" then
				for i = 1, (MAX_BOSS_FRAMES or 5) do
					UF.FullScanTargetAuras("boss" .. i)
				end
			else
				UF.FullScanTargetAuras(unit)
			end
		end

		list[#list + 1] = checkbox(L["UFAurasEnabled"] or "Enable auras", isAuraEnabled, function(val)
			setValue(unit, { "auraIcons", "enabled" }, val and true or false)
			refresh()
			refreshSettingsUI()
			refreshAuras()
		end, auraDef.enabled ~= false, "auras")

		list[#list + 1] = slider(L["Aura size"] or "Aura size", 12, 48, 1, function() return getValue(unit, { "auraIcons", "size" }, auraDef.size or 24) end, function(val)
			setValue(unit, { "auraIcons", "size" }, val or auraDef.size or 24)
			refresh()
		end, auraDef.size or 24, "auras", true)
		list[#list].isEnabled = isAuraEnabled

		list[#list + 1] = slider(
			L["Aura debuff size"] or "Aura debuff size",
			12,
			48,
			1,
			function() return getValue(unit, { "auraIcons", "debuffSize" }, auraDef.debuffSize or auraDef.size or 24) end,
			function(val)
				setValue(unit, { "auraIcons", "debuffSize" }, val or auraDef.debuffSize or auraDef.size or 24)
				refresh()
			end,
			auraDef.debuffSize or auraDef.size or 24,
			"auras",
			true
		)
		list[#list].isEnabled = isAuraEnabled

		list[#list + 1] = slider(L["Aura spacing"] or "Aura spacing", 0, 10, 1, function() return getValue(unit, { "auraIcons", "padding" }, auraDef.padding or 2) end, function(val)
			setValue(unit, { "auraIcons", "padding" }, val or 0)
			refresh()
		end, auraDef.padding or 2, "auras", true)
		list[#list].isEnabled = isAuraEnabled

		list[#list + 1] = slider(L["UFMaxAuras"] or "Max auras", 4, 40, 1, function() return getValue(unit, { "auraIcons", "max" }, auraDef.max or 16) end, function(val)
			setValue(unit, { "auraIcons", "max" }, val or auraDef.max or 16)
			refresh()
		end, auraDef.max or 16, "auras", true)
		list[#list].isEnabled = isAuraEnabled

		list[#list + 1] = slider(
			L["Aura per row"] or "Auras per row",
			0,
			40,
			1,
			function() return getValue(unit, { "auraIcons", "perRow" }, auraDef.perRow or 0) end,
			function(val)
				val = tonumber(val) or 0
				if val < 0 then val = 0 end
				setValue(unit, { "auraIcons", "perRow" }, math.floor(val + 0.5))
				refresh()
			end,
			auraDef.perRow or 0,
			"auras",
			true,
			function(value)
				value = tonumber(value) or 0
				if value <= 0 then return L["Auto"] or "Auto" end
				return tostring(math.floor(value + 0.5))
			end
		)
		list[#list].isEnabled = isAuraEnabled

		list[#list + 1] = checkbox(L["Show cooldown text (buffs)"] or "Show cooldown text (buffs)", function()
			local val = getValue(unit, { "auraIcons", "showCooldownBuffs" })
			if val == nil then val = getValue(unit, { "auraIcons", "showCooldown" }, auraDef.showCooldown ~= false) end
			return val ~= false
		end, function(val)
			setValue(unit, { "auraIcons", "showCooldownBuffs" }, val and true or false)
			refresh()
		end, auraDef.showCooldown ~= false, "auras")
		list[#list].isEnabled = isAuraEnabled

		list[#list + 1] = checkbox(L["Show cooldown text (debuffs)"] or "Show cooldown text (debuffs)", function()
			local val = getValue(unit, { "auraIcons", "showCooldownDebuffs" })
			if val == nil then val = getValue(unit, { "auraIcons", "showCooldown" }, auraDef.showCooldown ~= false) end
			return val ~= false
		end, function(val)
			setValue(unit, { "auraIcons", "showCooldownDebuffs" }, val and true or false)
			refresh()
		end, auraDef.showCooldown ~= false, "auras")
		list[#list].isEnabled = isAuraEnabled

		list[#list + 1] = checkbox(L["Show buffs"] or "Show buffs", function() return getValue(unit, { "auraIcons", "showBuffs" }, auraDef.showBuffs ~= false) end, function(val)
			setValue(unit, { "auraIcons", "showBuffs" }, val and true or false)
			refresh()
			refreshAuras()
		end, auraDef.showBuffs ~= false, "auras")
		list[#list].isEnabled = isAuraEnabled

		list[#list + 1] = checkbox(L["Show debuffs"] or "Show debuffs", function() return getValue(unit, { "auraIcons", "showDebuffs" }, auraDef.showDebuffs ~= false) end, function(val)
			setValue(unit, { "auraIcons", "showDebuffs" }, val and true or false)
			refresh()
			refreshAuras()
		end, auraDef.showDebuffs ~= false, "auras")
		list[#list].isEnabled = isAuraEnabled

		list[#list + 1] = checkbox(
			L["Highlight dispellable"] or "Highlight dispellable",
			function() return getValue(unit, { "auraIcons", "blizzardDispelBorder" }, auraDef.blizzardDispelBorder == true) == true end,
			function(val)
				setValue(unit, { "auraIcons", "blizzardDispelBorder" }, val and true or false)
				refresh()
				refreshAuras()
			end,
			auraDef.blizzardDispelBorder == true,
			"auras"
		)
		list[#list].isEnabled = isAuraEnabled

		list[#list + 1] = slider(
			L["Cooldown text size (buffs)"] or "Cooldown text size (buffs)",
			0,
			32,
			1,
			function() return getValue(unit, { "auraIcons", "cooldownFontSizeBuff" }, auraDef.cooldownFontSizeBuff or auraDef.cooldownFontSize or 0) end,
			function(val)
				val = tonumber(val) or 0
				if val < 0 then val = 0 end
				setValue(unit, { "auraIcons", "cooldownFontSizeBuff" }, val)
				refresh()
			end,
			auraDef.cooldownFontSizeBuff or auraDef.cooldownFontSize or 0,
			"auras",
			true,
			function(value)
				value = tonumber(value) or 0
				if value <= 0 then return L["Auto"] or "Auto" end
				return tostring(math.floor(value + 0.5))
			end
		)
		list[#list].isEnabled = isAuraEnabled

		list[#list + 1] = slider(
			L["Cooldown text size (debuffs)"] or "Cooldown text size (debuffs)",
			0,
			32,
			1,
			function() return getValue(unit, { "auraIcons", "cooldownFontSizeDebuff" }, auraDef.cooldownFontSizeDebuff or auraDef.cooldownFontSize or 0) end,
			function(val)
				val = tonumber(val) or 0
				if val < 0 then val = 0 end
				setValue(unit, { "auraIcons", "cooldownFontSizeDebuff" }, val)
				refresh()
			end,
			auraDef.cooldownFontSizeDebuff or auraDef.cooldownFontSize or 0,
			"auras",
			true,
			function(value)
				value = tonumber(value) or 0
				if value <= 0 then return L["Auto"] or "Auto" end
				return tostring(math.floor(value + 0.5))
			end
		)
		list[#list].isEnabled = isAuraEnabled

		list[#list + 1] = slider(
			L["Aura stack size (buffs)"] or "Aura stack size (buffs)",
			8,
			32,
			1,
			function() return getValue(unit, { "auraIcons", "countFontSizeBuff" }, auraDef.countFontSizeBuff or auraDef.countFontSize or 14) end,
			function(val)
				setValue(unit, { "auraIcons", "countFontSizeBuff" }, val or 14)
				refresh()
			end,
			auraDef.countFontSizeBuff or auraDef.countFontSize or 14,
			"auras",
			true
		)
		list[#list].isEnabled = isAuraEnabled

		list[#list + 1] = slider(
			L["Aura stack size (debuffs)"] or "Aura stack size (debuffs)",
			8,
			32,
			1,
			function() return getValue(unit, { "auraIcons", "countFontSizeDebuff" }, auraDef.countFontSizeDebuff or auraDef.countFontSize or 14) end,
			function(val)
				setValue(unit, { "auraIcons", "countFontSizeDebuff" }, val or 14)
				refresh()
			end,
			auraDef.countFontSizeDebuff or auraDef.countFontSize or 14,
			"auras",
			true
		)
		list[#list].isEnabled = isAuraEnabled

		local stackOutlineOptions = {
			{ value = "NONE", label = L["None"] or "None" },
			{ value = "OUTLINE", label = L["Outline"] or "Outline" },
			{ value = "THICKOUTLINE", label = L["Thick outline"] or "Thick outline" },
			{ value = "MONOCHROMEOUTLINE", label = L["Monochrome outline"] or "Monochrome outline" },
		}
		list[#list + 1] = checkboxDropdown(
			L["Aura stack outline"] or "Aura stack outline",
			stackOutlineOptions,
			function() return getValue(unit, { "auraIcons", "countFontOutline" }, auraDef.countFontOutline or "OUTLINE") end,
			function(val)
				setValue(unit, { "auraIcons", "countFontOutline" }, val or nil)
				refresh()
			end,
			auraDef.countFontOutline or "OUTLINE",
			"auras"
		)
		list[#list].isEnabled = isAuraEnabled

		local stackAnchorOptions = {
			{ value = "TOPLEFT", label = L["Top left"] or "Top left" },
			{ value = "TOPRIGHT", label = L["Top right"] or "Top right" },
			{ value = "BOTTOMLEFT", label = L["Bottom left"] or "Bottom left" },
			{ value = "BOTTOMRIGHT", label = L["Bottom right"] or "Bottom right" },
			{ value = "CENTER", label = L["Center"] or "Center" },
		}
		list[#list + 1] = radioDropdown(
			L["Aura stack position"] or "Aura stack position",
			stackAnchorOptions,
			function() return getValue(unit, { "auraIcons", "countAnchor" }, auraDef.countAnchor or "BOTTOMRIGHT") end,
			function(val)
				setValue(unit, { "auraIcons", "countAnchor" }, val or "BOTTOMRIGHT")
				refresh()
			end,
			auraDef.countAnchor or "BOTTOMRIGHT",
			"auras"
		)
		list[#list].isEnabled = isAuraEnabled

		list[#list + 1] = slider(
			L["Aura stack offset X"] or "Aura stack offset X",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "auraIcons", "countOffset", "x" }, (auraDef.countOffset and auraDef.countOffset.x) or -2) end,
			function(val)
				setValue(unit, { "auraIcons", "countOffset", "x" }, val or 0)
				refresh()
			end,
			(auraDef.countOffset and auraDef.countOffset.x) or -2,
			"auras",
			true
		)
		list[#list].isEnabled = isAuraEnabled

		list[#list + 1] = slider(
			L["Aura stack offset Y"] or "Aura stack offset Y",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "auraIcons", "countOffset", "y" }, (auraDef.countOffset and auraDef.countOffset.y) or 2) end,
			function(val)
				setValue(unit, { "auraIcons", "countOffset", "y" }, val or 0)
				refresh()
			end,
			(auraDef.countOffset and auraDef.countOffset.y) or 2,
			"auras",
			true
		)
		list[#list].isEnabled = isAuraEnabled

		list[#list + 1] = checkbox(L["UFHidePermanentAuras"] or "Hide permanent auras", function()
			local val = getValue(unit, { "auraIcons", "hidePermanentAuras" })
			if val == nil then val = getValue(unit, { "auraIcons", "hidePermanent" }) end
			if val == nil then val = auraDef.hidePermanentAuras end
			if val == nil then val = auraDef.hidePermanent end
			return val == true
		end, function(val)
			setValue(unit, { "auraIcons", "hidePermanentAuras" }, val and true or false)
			setValue(unit, { "auraIcons", "hidePermanent" }, nil)
			refresh()
			refreshAuras()
		end, (auraDef.hidePermanentAuras or auraDef.hidePermanent) == true, "auras")
		list[#list].isEnabled = isAuraEnabled

		local leftLabel = HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_LEFT or L["Left"] or "Left"
		local rightLabel = HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_RIGHT or L["Right"] or "Right"
		local anchorOpts = {
			{ value = "TOP", label = L["Top"] or "Top" },
			{ value = "BOTTOM", label = L["Bottom"] or "Bottom" },
			{ value = "LEFT", label = leftLabel },
			{ value = "RIGHT", label = rightLabel },
		}
		list[#list + 1] = radioDropdown(L["Aura anchor"] or "Aura anchor", anchorOpts, function() return getValue(unit, { "auraIcons", "anchor" }, auraDef.anchor or "BOTTOM") end, function(val)
			setValue(unit, { "auraIcons", "anchor" }, val or "BOTTOM")
			refresh()
		end, auraDef.anchor or "BOTTOM", "auras")
		list[#list].isEnabled = isAuraEnabled

		local upLabel = HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_UP or L["Up"] or "Up"
		local downLabel = HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_DOWN or L["Down"] or "Down"
		local function growthLabel(first, second) return ("%s %s"):format(first, second) end
		local growthOptions = {
			{ value = "UPRIGHT", label = growthLabel(upLabel, rightLabel) },
			{ value = "UPLEFT", label = growthLabel(upLabel, leftLabel) },
			{ value = "RIGHTUP", label = growthLabel(rightLabel, upLabel) },
			{ value = "RIGHTDOWN", label = growthLabel(rightLabel, downLabel) },
			{ value = "LEFTUP", label = growthLabel(leftLabel, upLabel) },
			{ value = "LEFTDOWN", label = growthLabel(leftLabel, downLabel) },
			{ value = "DOWNLEFT", label = growthLabel(downLabel, leftLabel) },
			{ value = "DOWNRIGHT", label = growthLabel(downLabel, rightLabel) },
		}
		local function defaultAuraGrowth()
			local anchor = getValue(unit, { "auraIcons", "anchor" }, auraDef.anchor or "BOTTOM")
			if anchor == "TOP" then return "RIGHTUP" end
			if anchor == "LEFT" then return "LEFTDOWN" end
			return "RIGHTDOWN"
		end
		list[#list + 1] = radioDropdown(
			L["GrowthDirection"] or "Growth direction",
			growthOptions,
			function() return (getValue(unit, { "auraIcons", "growth" }, defaultAuraGrowth()) or defaultAuraGrowth()):upper() end,
			function(val)
				setValue(unit, { "auraIcons", "growth" }, (val or defaultAuraGrowth()):upper())
				refresh()
			end,
			defaultAuraGrowth(),
			"auras"
		)
		list[#list].isEnabled = isAuraEnabled

		list[#list + 1] = slider(L["Aura Offset X"] or "Aura Offset X", -OFFSET_RANGE, OFFSET_RANGE, 1, function()
			local anchor = getValue(unit, { "auraIcons", "anchor" }, auraDef.anchor or "BOTTOM")
			return getValue(unit, { "auraIcons", "offset", "x" }, (auraDef.offset and auraDef.offset.x) or defaultAuraOffsetX(anchor))
		end, function(val)
			setValue(unit, { "auraIcons", "offset", "x" }, val or 0)
			refresh()
		end, (auraDef.offset and auraDef.offset.x) or defaultAuraOffsetX(auraDef.anchor or "BOTTOM"), "auras", true)
		list[#list].isEnabled = isAuraEnabled

		list[#list + 1] = slider(L["Aura Offset Y"] or "Aura Offset Y", -OFFSET_RANGE, OFFSET_RANGE, 1, function()
			local anchor = getValue(unit, { "auraIcons", "anchor" }, auraDef.anchor or "BOTTOM")
			return getValue(unit, { "auraIcons", "offset", "y" }, (auraDef.offset and auraDef.offset.y) or defaultAuraOffsetY(anchor))
		end, function(val)
			setValue(unit, { "auraIcons", "offset", "y" }, val or 0)
			refresh()
		end, (auraDef.offset and auraDef.offset.y) or defaultAuraOffsetY(auraDef.anchor or "BOTTOM"), "auras", true)
		list[#list].isEnabled = isAuraEnabled

		list[#list + 1] = checkbox(
			L["UFSeparateDebuffAnchor"] or "Separate debuff anchor",
			function() return getValue(unit, { "auraIcons", "separateDebuffAnchor" }, auraDef.separateDebuffAnchor == true) end,
			function(val)
				setValue(unit, { "auraIcons", "separateDebuffAnchor" }, val and true or false)
				refresh()
				refreshSettingsUI()
			end,
			auraDef.separateDebuffAnchor == true,
			"auras"
		)
		list[#list].isEnabled = isAuraEnabled

		local function isSeparateDebuffEnabled() return isAuraEnabled() and getValue(unit, { "auraIcons", "separateDebuffAnchor" }, auraDef.separateDebuffAnchor == true) == true end

		local debuffAnchorSetting = radioDropdown(L["UFDebuffAnchor"] or "Debuff anchor", anchorOpts, function() return debuffAnchorValue() end, function(val)
			setValue(unit, { "auraIcons", "debuffAnchor" }, val or nil)
			refresh()
		end, auraDef.debuffAnchor or auraDef.anchor or "BOTTOM", "auras")
		debuffAnchorSetting.isEnabled = isSeparateDebuffEnabled
		list[#list + 1] = debuffAnchorSetting

		local function defaultDebuffGrowth()
			local baseGrowth = getValue(unit, { "auraIcons", "growth" }, nil)
			if baseGrowth and baseGrowth ~= "" then return baseGrowth end
			local anchor = debuffAnchorValue()
			if anchor == "TOP" then return "RIGHTUP" end
			if anchor == "LEFT" then return "LEFTDOWN" end
			return "RIGHTDOWN"
		end

		local debuffGrowthSetting = radioDropdown(
			L["Debuff Growth Direction"] or "Debuff growth direction",
			growthOptions,
			function() return (getValue(unit, { "auraIcons", "debuffGrowth" }, defaultDebuffGrowth()) or defaultDebuffGrowth()):upper() end,
			function(val)
				setValue(unit, { "auraIcons", "debuffGrowth" }, (val or defaultDebuffGrowth()):upper())
				refresh()
			end,
			defaultDebuffGrowth(),
			"auras"
		)
		debuffGrowthSetting.isEnabled = isSeparateDebuffEnabled
		list[#list + 1] = debuffGrowthSetting

		list[#list + 1] = slider(
			L["Debuff Offset X"] or "Debuff Offset X",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function()
				return getValue(
					unit,
					{ "auraIcons", "debuffOffset", "x" },
					(auraDef.debuffOffset and auraDef.debuffOffset.x) or (auraDef.offset and auraDef.offset.x) or defaultAuraOffsetX(debuffAnchorValue())
				)
			end,
			function(val)
				setValue(unit, { "auraIcons", "debuffOffset", "x" }, val or 0)
				refresh()
			end,
			(auraDef.debuffOffset and auraDef.debuffOffset.x) or (auraDef.offset and auraDef.offset.x) or defaultAuraOffsetX(auraDef.debuffAnchor or auraDef.anchor or "BOTTOM"),
			"auras",
			true
		)
		list[#list].isEnabled = isSeparateDebuffEnabled

		list[#list + 1] = slider(
			L["Debuff Offset Y"] or "Debuff Offset Y",
			-OFFSET_RANGE,
			OFFSET_RANGE,
			1,
			function() return getValue(unit, { "auraIcons", "debuffOffset", "y" }, (auraDef.debuffOffset and auraDef.debuffOffset.y) or debuffOffsetYDefault()) end,
			function(val)
				setValue(unit, { "auraIcons", "debuffOffset", "y" }, val or 0)
				refresh()
			end,
			(auraDef.debuffOffset and auraDef.debuffOffset.y) or debuffOffsetYDefault(),
			"auras",
			true
		)
		list[#list].isEnabled = isSeparateDebuffEnabled
	end

	return list
end

local DEFAULT_SETTINGS_MAX_HEIGHT = 900

local function registerUnitFrame(unit, info)
	if UF.EnsureFrames then
		if unit == "boss" then
			UF.EnsureFrames("boss1")
		else
			UF.EnsureFrames(unit)
		end
	end
	refresh()
	local frame = _G[info.frameName]
	if not frame then return end
	local layout = calcLayout(unit, frame)
	local settingsList = buildUnitSettings(unit)
	EditMode:RegisterFrame(info.frameId, {
		frame = frame,
		title = info.title,
		enableOverlayToggle = true,
		allowDrag = function() return anchorUsesUIParent(unit) end,
		settingsSpacing = 1,
		sliderHeight = 28,
		layoutDefaults = layout,
		settingsMaxHeight = DEFAULT_SETTINGS_MAX_HEIGHT,
		onApply = function(_, _, data)
			local cfg = ensureConfig(unit)
			cfg.anchor = cfg.anchor or {}
			if data.point then
				cfg.anchor.point = data.point
				cfg.anchor.relativePoint = data.relativePoint or data.point
				cfg.anchor.x = data.x or 0
				cfg.anchor.y = data.y or 0
				cfg.anchor.relativeTo = cfg.anchor.relativeTo or "UIParent"
			end
			refresh()
		end,
		isEnabled = function() return ensureConfig(unit).enabled == true end,
		settings = settingsList,
		showOutsideEditMode = true,
		collapseExclusive = true,
		showReset = false,
	})
	hideFrameReset(frame)
end

local function registerEditModeFrames()
	if UF.EditModeRegistered then return end
	UF.EditModeRegistered = true
	local frames = {
		player = { frameName = "EQOLUFPlayerFrame", frameId = frameIds.player, title = L["UFPlayerFrame"] or PLAYER },
		target = { frameName = "EQOLUFTargetFrame", frameId = frameIds.target, title = L["UFTargetFrame"] or TARGET },
		targettarget = { frameName = "EQOLUFToTFrame", frameId = frameIds.targettarget, title = L["UFToTFrame"] or "Target of Target" },
		pet = { frameName = "EQOLUFPetFrame", frameId = frameIds.pet, title = L["UFPetFrame"] or PET },
		focus = { frameName = "EQOLUFFocusFrame", frameId = frameIds.focus, title = L["UFFocusFrame"] or FOCUS },
		boss = { frameName = "EQOLUFBossContainer", frameId = frameIds.boss, title = (L["UFBossFrame"] or "Boss Frames") },
	}
	for unit, info in pairs(frames) do
		registerUnitFrame(unit, info)
	end
	if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RefreshSettingValues then addon.EditModeLib.internal:RefreshSettingValues() end
end

local function registerSettingsUI()
	if UF.SettingsRegistered then return end
	if not (addon.functions and addon.functions.SettingsCreateCategory) then return end
	-- Simple toggles in Settings panel (keep basic visibility outside Edit Mode)
	local cUF = addon.SettingsLayout.rootUI
	local expandable = addon.SettingsLayout.expEQoLUnitFrames
	if not expandable then
		expandable = addon.functions.SettingsCreateExpandableSection(cUF, {
			name = L["CustomUnitFrames"] or "EQoL Unit Frames",
			expanded = false,
			colorizeTitle = false,
		})
		addon.SettingsLayout.expEQoLUnitFrames = expandable
	end

	addon.SettingsLayout.ufPlusCategory = cUF
	addon.functions.SettingsCreateText(cUF, "|cff99e599" .. L["UFPlusHint"] .. "|r", { parentSection = expandable })
	addon.functions.SettingsCreateText(cUF, "", { parentSection = expandable })
	--@debug@
	addon.functions.SettingsCreateCheckbox(cUF, {
		var = "ufEnableGroupFrames",
		text = L["UFGroupFramesEnable"] or "Enable party/raid group frames",
		default = false,
		get = function() return addon.db and addon.db.ufEnableGroupFrames == true end,
		func = function(val)
			addon.db = addon.db or {}
			addon.db.ufEnableGroupFrames = val and true or false
			if UF and UF.GroupFrames then
				if val then
					UF.GroupFrames:EnableFeature()
				else
					UF.GroupFrames:DisableFeature()
				end
			end
		end,
		parentSection = expandable,
	})
	--@end-debug@
	local function addToggle(unit, label, varName)
		local def = defaultsFor(unit)
		addon.functions.SettingsCreateCheckbox(cUF, {
			var = varName,
			text = label,
			default = def.enabled or false,
			get = function() return ensureConfig(unit).enabled == true end,
			func = function(val)
				local cfg = ensureConfig(unit)
				cfg.enabled = val and true or false
				if unit == "player" then
					if cfg.enabled then
						UF.Enable()
					else
						UF.Disable()
					end
				else
					UF.Refresh()
				end
				if UF.StopEventsIfInactive then UF.StopEventsIfInactive() end
				refreshEditModeFrame(unit)
				if val == false then
					addon.variables.requireReload = true
					if addon.functions and addon.functions.checkReloadFrame then addon.functions.checkReloadFrame() end
				end
			end,
			parentSection = expandable,
		})
		return def.enabled or false
	end

	addToggle("player", L["UFPlayerEnable"] or "Enable custom player frame", "ufEnablePlayer")
	local castbarSetting = _G.HUD_EDIT_MODE_SETTING_UNIT_FRAME_CAST_BAR_UNDERNEATH or "Castbar underneath"
	addon.functions.SettingsCreateText(
		cUF,
		(L["UFPlayerCastbarHint"] or 'Uses Blizzard\'s Player Castbar.\nBefore enabling, open Edit Mode\nand make sure the Player Frame setting\n"%s" is unchecked.'):format(castbarSetting),
		{ parentSection = expandable }
	)
	addToggle("target", L["UFTargetEnable"] or "Enable custom target frame", "ufEnableTarget")
	addToggle("targettarget", L["UFToTEnable"] or "Enable target-of-target frame", "ufEnableToT")
	addToggle("pet", L["UFPetEnable"] or "Enable pet frame", "ufEnablePet")
	addToggle("focus", L["UFFocusEnable"] or "Enable focus frame", "ufEnableFocus")
	addon.functions.SettingsCreateCheckbox(cUF, {
		var = "ufEnableBoss",
		text = L["UFBossEnable"] or "Enable boss frames",
		default = false,
		get = function()
			for i = 1, 5 do
				local cfg = ensureConfig("boss" .. i)
				if cfg.enabled then return true end
			end
			return false
		end,
		func = function(val)
			for i = 1, 5 do
				local u = "boss" .. i
				local cfg = ensureConfig(u)
				cfg.enabled = val and true or false
			end
			if UF.Refresh then UF.Refresh() end
			if UF.StopEventsIfInactive then UF.StopEventsIfInactive() end
			refreshEditModeFrame("boss")
			if val == false then
				addon.variables.requireReload = true
				if addon.functions and addon.functions.checkReloadFrame then addon.functions.checkReloadFrame() end
			end
		end,
		parentSection = expandable,
	})

	local function getDefaultClassColor(classTag)
		local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classTag]
		if color then
			if color.GetRGBA then return color:GetRGBA() end
			return color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1, color.a or color[4] or 1
		end
		if C_ClassColor and C_ClassColor.GetClassColor then
			local classColor = C_ClassColor.GetClassColor(classTag)
			if classColor and classColor.GetRGBA then return classColor:GetRGBA() end
		end
		return 1, 1, 1, 1
	end

	local function ensureCustomClassColors()
		addon.db.ufClassColors = addon.db.ufClassColors or {}
		local order = CLASS_SORT_ORDER or {}
		if #order == 0 and RAID_CLASS_COLORS then
			for classTag in pairs(RAID_CLASS_COLORS) do
				order[#order + 1] = classTag
			end
			table.sort(order)
		end
		for _, classTag in ipairs(order) do
			if not addon.db.ufClassColors[classTag] then
				local r, g, b, a = getDefaultClassColor(classTag)
				addon.db.ufClassColors[classTag] = { r = r, g = g, b = b, a = a }
			end
		end
	end

	local classEntries = {}
	do
		local order = CLASS_SORT_ORDER or {}
		if #order == 0 and RAID_CLASS_COLORS then
			for classTag in pairs(RAID_CLASS_COLORS) do
				order[#order + 1] = classTag
			end
			table.sort(order)
		end
		for _, classTag in ipairs(order) do
			local label = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classTag]) or classTag
			classEntries[#classEntries + 1] = { key = classTag, label = label }
		end
	end

	addon.functions.SettingsCreateHeadline(cUF, L["ufClassColorsHeader"] or "Class colors", { parentSection = expandable })

	addon.functions.SettingsCreateCheckbox(cUF, {
		var = "ufUseCustomClassColors",
		text = L["ufUseCustomClassColors"] or "Use custom class colors for unit frames",
		desc = L["ufUseCustomClassColorsDesc"] or "Overrides class colors used by Enhance QoL unit frames.",
		func = function(value)
			addon.db["ufUseCustomClassColors"] = value
			if value then ensureCustomClassColors() end
			if Settings and Settings.NotifyUpdate then Settings.NotifyUpdate("EQOL_ufUseCustomClassColors") end
			if addon.Aura and addon.Aura.UF and addon.Aura.UF.Refresh then addon.Aura.UF.Refresh() end
		end,
		parentSection = expandable,
	})

	local classColorParent = addon.SettingsLayout.elements["ufUseCustomClassColors"] and addon.SettingsLayout.elements["ufUseCustomClassColors"].element
	addon.functions.SettingsCreateColorOverrides(cUF, {
		var = "ufClassColors",
		text = L["ufClassColorsLabel"] or "Class colors",
		entries = classEntries,
		getColor = function(key)
			local overrides = addon.db and addon.db.ufClassColors
			local color = overrides and overrides[key]
			if color then return color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1, color.a or color[4] or 1 end
			return getDefaultClassColor(key)
		end,
		setColor = function(key, r, g, b, a)
			addon.db.ufClassColors = addon.db.ufClassColors or {}
			addon.db.ufClassColors[key] = { r = r, g = g, b = b, a = a }
			if addon.Aura and addon.Aura.UF and addon.Aura.UF.Refresh then addon.Aura.UF.Refresh() end
		end,
		getDefaultColor = function(key) return getDefaultClassColor(key) end,
		parent = classColorParent,
		parentCheck = function()
			local entry = addon.SettingsLayout.elements["ufUseCustomClassColors"]
			return entry and entry.setting and entry.setting:GetValue() == true
		end,
		parentSection = expandable,
	})

	do -- Profile export/import
		local scopeOptions = {
			ALL = L["UFProfileScopeAll"] or "All frames",
			player = L["UFPlayerFrame"] or PLAYER,
			target = L["UFTargetFrame"] or TARGET,
			targettarget = L["UFToTFrame"] or "Target of Target",
			focus = L["UFFocusFrame"] or FOCUS,
			pet = L["UFPetFrame"] or PET,
			boss = L["UFBossFrame"] or BOSS or "Boss Frame",
		}
		local function getScope()
			addon.db = addon.db or {}
			local cur = addon.db.ufProfileScope or "ALL"
			if not scopeOptions[cur] then cur = "ALL" end
			addon.db.ufProfileScope = cur
			return cur
		end
		local function setScope(val)
			addon.db = addon.db or {}
			addon.db.ufProfileScope = scopeOptions[val] and val or "ALL"
		end

		local cProfiles = addon.SettingsLayout.rootPROFILES

		local expandableProfile = addon.functions.SettingsCreateExpandableSection(cProfiles, {
			name = L["CustomUnitFrames"],
			expanded = false,
			colorizeTitle = false,
		})
		addon.functions.SettingsCreateDropdown(cProfiles, {
			var = "ufProfileScope",
			text = L["ProfileScope"] or (L["Apply to"] or "Apply to"),
			list = scopeOptions,
			get = getScope,
			set = setScope,
			default = "ALL",
			parentSection = expandableProfile,
		})

		addon.functions.SettingsCreateButton(cProfiles, {
			var = "ufExportProfile",
			text = L["Export"] or "Export",
			func = function()
				local scopeKey = getScope()
				local code
				local reason
				if UF.ExportProfile then
					code, reason = UF.ExportProfile(scopeKey)
				end
				if not code then
					local msg = (UF.ExportErrorMessage and UF.ExportErrorMessage(reason)) or (L["UFExportProfileFailed"] or "Export failed.")
					print("|cff00ff98Enhance QoL|r: " .. tostring(msg))
					return
				end
				StaticPopupDialogs["EQOL_UF_EXPORT_SETTINGS"] = StaticPopupDialogs["EQOL_UF_EXPORT_SETTINGS"]
					or {
						text = L["UFExportProfileTitle"] or "Export Unit Frames",
						button1 = CLOSE,
						hasEditBox = true,
						editBoxWidth = 320,
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						preferredIndex = 3,
					}
				StaticPopupDialogs["EQOL_UF_EXPORT_SETTINGS"].text = L["UFExportProfileTitle"] or "Export Unit Frames"
				StaticPopupDialogs["EQOL_UF_EXPORT_SETTINGS"].OnShow = function(self)
					self:SetFrameStrata("TOOLTIP")
					local editBox = self.editBox or self:GetEditBox()
					editBox:SetText(code)
					editBox:HighlightText()
					editBox:SetFocus()
				end
				StaticPopup_Show("EQOL_UF_EXPORT_SETTINGS")
			end,
			parentSection = expandableProfile,
		})

		addon.functions.SettingsCreateButton(cProfiles, {
			var = "ufImportProfile",
			text = L["Import"] or "Import",
			func = function()
				local importText = (L["UFImportProfileTitle"] or "Import Unit Frames")
				if L["UFImportProfileReloadHint"] then importText = importText .. "\n\n" .. L["UFImportProfileReloadHint"] end
				StaticPopupDialogs["EQOL_UF_IMPORT_SETTINGS"] = StaticPopupDialogs["EQOL_UF_IMPORT_SETTINGS"]
					or {
						text = importText,
						button1 = OKAY,
						button2 = CANCEL,
						hasEditBox = true,
						editBoxWidth = 320,
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						preferredIndex = 3,
					}
				StaticPopupDialogs["EQOL_UF_IMPORT_SETTINGS"].text = importText
				StaticPopupDialogs["EQOL_UF_IMPORT_SETTINGS"].OnShow = function(self)
					self:SetFrameStrata("TOOLTIP")
					local editBox = self.editBox or self:GetEditBox()
					editBox:SetText("")
					editBox:SetFocus()
				end
				StaticPopupDialogs["EQOL_UF_IMPORT_SETTINGS"].EditBoxOnEnterPressed = function(editBox)
					local parent = editBox:GetParent()
					if parent and parent.button1 then parent.button1:Click() end
				end
				StaticPopupDialogs["EQOL_UF_IMPORT_SETTINGS"].OnAccept = function(self)
					local editBox = self.editBox or self:GetEditBox()
					local input = editBox:GetText() or ""
					local scopeKey = getScope()
					local ok, applied = false, nil
					if UF.ImportProfile then
						ok, applied = UF.ImportProfile(input, scopeKey)
					end
					if not ok then
						local msg = UF.ImportErrorMessage and UF.ImportErrorMessage(applied) or (L["UFImportProfileFailed"] or "Import failed.")
						print("|cff00ff98Enhance QoL|r: " .. tostring(msg))
						return
					end
					if applied and #applied > 0 then
						local names = {}
						for _, key in ipairs(applied) do
							names[#names + 1] = scopeOptions[key] or key
						end
						local label = table.concat(names, ", ")
						local msg = (L["UFImportProfileSuccess"] or "Unit Frames updated for: %s"):format(label)
						print("|cff00ff98Enhance QoL|r: " .. msg)
					else
						local msg = L["UFImportProfileSuccessGeneric"] or "Unit Frame profile imported."
						print("|cff00ff98Enhance QoL|r: " .. msg)
					end
					if ReloadUI then ReloadUI() end
				end
				StaticPopup_Show("EQOL_UF_IMPORT_SETTINGS")
			end,
			parentSection = expandableProfile,
		})
	end

	if addon.Aura and addon.Aura.functions and addon.Aura.functions.AddResourceBarsProfileSettings then addon.Aura.functions.AddResourceBarsProfileSettings() end
	UF.SettingsRegistered = true
end

function UF.RegisterSettings()
	if not addon.db then return end
	registerSettingsUI()
	if UF.EditModeRegistered then return end
	local editMode = addon.EditMode
	local lib = editMode and editMode.lib
	local function isLayoutReady()
		if not lib or not lib.GetActiveLayoutName then return true end
		local name = lib:GetActiveLayoutName()
		return name ~= nil and name ~= ""
	end
	if isLayoutReady() then
		registerEditModeFrames()
		return
	end
	if UF._pendingEditModeRegister then return end
	UF._pendingEditModeRegister = true
	local waiter = CreateFrame("Frame")
	waiter:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
	waiter:RegisterEvent("PLAYER_LOGIN")
	waiter:SetScript("OnEvent", function()
		if not isLayoutReady() then return end
		registerEditModeFrames()
		UF._pendingEditModeRegister = nil
		waiter:UnregisterAllEvents()
		waiter:SetScript("OnEvent", nil)
	end)
end
