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

local UF = addon.Aura and addon.Aura.UF
if not (UF and settingType) then return end

local MIN_WIDTH = 50
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
	{ value = "NONE", label = NONE or "None" },
}

local outlineOptions = {
	{ value = "NONE", label = L["None"] or "None" },
	{ value = "OUTLINE", label = L["Outline"] or "Outline" },
	{ value = "THICKOUTLINE", label = L["Thick Outline"] or "Thick Outline" },
	{ value = "MONOCHROMEOUTLINE", label = L["Monochrome Outline"] or "Monochrome Outline" },
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
	WARLOCK = true,
}

local function isBossUnit(unit) return unit == "boss" or (unit and unit:match("^boss%d+$")) end

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
local sampleAbsorb = addon.variables.ufSampleAbsorb
addon.variables.ufSampleCast = addon.variables.ufSampleCast or {}
local sampleCast = addon.variables.ufSampleCast

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

local function refresh(unit)
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
				root:CreateRadio(opt.label, function() return getter() == opt.value end, function() setter(opt.value) end)
			end
		end,
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
	local statusDef = def.status or {}
	local showName = getValue(unit, { "status", "enabled" }, statusDef.enabled ~= false) ~= false
	local showLevel = getValue(unit, { "status", "levelEnabled" }, statusDef.levelEnabled ~= false) ~= false
	local ciDef = statusDef.combatIndicator or {}
	local showCombat = unit == "player" and getValue(unit, { "status", "combatIndicator", "enabled" }, ciDef.enabled ~= false) ~= false
	local showStatus = showName or showLevel or showCombat
	local statusHeight = showStatus and (cfg.statusHeight or def.statusHeight or 18) or 0
	local width = cfg.width or def.width or frame:GetWidth() or 200
	local barGap = powerEnabled and (cfg.barGap or def.barGap or 0) or 0
	local powerHeight = powerEnabled and (cfg.powerHeight or def.powerHeight or 16) or 0
	local height = statusHeight + (cfg.healthHeight or def.healthHeight or 24) + powerHeight + barGap
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
	local classHasResource = isPlayer and classResourceClasses[addon.variables and addon.variables.unitClass]
	local copyOptions = availableCopySources(unit)

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

	list[#list + 1] = checkbox(L["UFShowTooltip"] or "Show unit tooltip", function() return getValue(unit, { "showTooltip" }, def.showTooltip or false) == true end, function(val)
		setValue(unit, { "showTooltip" }, val and true or false)
		refreshSelf()
	end, def.showTooltip or false, "frame")

	list[#list + 1] = slider(L["UFWidth"] or "Frame width", MIN_WIDTH, 800, 1, function() return getValue(unit, { "width" }, def.width or MIN_WIDTH) end, function(val)
		setValue(unit, { "width" }, math.max(MIN_WIDTH, val or MIN_WIDTH))
		refreshSelf()
	end, def.width or MIN_WIDTH, "frame", true)

	list[#list + 1] = slider(L["UFBarGap"] or "Gap between bars", 0, 10, 1, function() return getValue(unit, { "barGap" }, def.barGap or 0) end, function(val)
		setValue(unit, { "barGap" }, val or 0)
		refreshSelf()
	end, def.barGap or 0, "frame", true)

	if isBoss then
		list[#list + 1] = slider(L["UFBossSpacing"] or "Boss spacing", 0, 40, 1, function() return getValue(unit, { "spacing" }, def.spacing or 4) end, function(val)
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

	list[#list + 1] = slider(L["UFBorderSize"] or "Border size", 1, 8, 1, function()
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

	list[#list + 1] = { name = L["HealthBar"] or "Health Bar", kind = settingType.Collapsible, id = "health", defaultCollapsed = true }

	list[#list + 1] = slider(L["UFHealthHeight"] or "Health height", 8, 80, 1, function() return getValue(unit, { "healthHeight" }, def.healthHeight or 24) end, function(val)
		setValue(unit, { "healthHeight" }, val or def.healthHeight or 24)
		refresh()
	end, def.healthHeight or 24, "health", true)

	local healthDef = def.health or {}

	if not isBoss then
		list[#list + 1] = checkbox(
			L["UFUseClassColor"] or "Use class color",
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

	list[#list + 1] = radioDropdown(L["TextLeft"] or "Left text", textOptions, function() return getValue(unit, { "health", "textLeft" }, healthDef.textLeft or "PERCENT") end, function(val)
		setValue(unit, { "health", "textLeft" }, val)
		refresh()
	end, healthDef.textLeft or "PERCENT", "health")

	list[#list + 1] = radioDropdown(L["TextRight"] or "Right text", textOptions, function() return getValue(unit, { "health", "textRight" }, healthDef.textRight or "CURMAX") end, function(val)
		setValue(unit, { "health", "textRight" }, val)
		refresh()
	end, healthDef.textRight or "CURMAX", "health")

	list[#list + 1] = slider(L["FontSize"] or "Font size", 8, 30, 1, function() return getValue(unit, { "health", "fontSize" }, healthDef.fontSize or 14) end, function(val)
		debounced(unit .. "_healthFontSize", function()
			setValue(unit, { "health", "fontSize" }, val or healthDef.fontSize or 14)
			refresh()
		end)
	end, healthDef.fontSize or 14, "health", true)

	local fontOpts = fontOptions()
	if #fontOpts > 0 then
		list[#list + 1] = radioDropdown(L["Font"] or "Font", fontOpts, function() return getValue(unit, { "health", "font" }, healthDef.font or defaultFontPath()) end, function(val)
			setValue(unit, { "health", "font" }, val)
			refresh()
		end, healthDef.font or defaultFontPath(), "health")
	end

	list[#list + 1] = radioDropdown(
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

	list[#list + 1] = slider(
		L["TextLeftOffsetX"] or "Left text X offset",
		-200,
		200,
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

	list[#list + 1] = slider(
		L["TextLeftOffsetY"] or "Left text Y offset",
		-200,
		200,
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

	list[#list + 1] = slider(
		L["TextRightOffsetX"] or "Right text X offset",
		-200,
		200,
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

	list[#list + 1] = slider(
		L["TextRightOffsetY"] or "Right text Y offset",
		-200,
		200,
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

	list[#list + 1] = checkbox(L["Use short numbers"] or "Use short numbers", function() return getValue(unit, { "health", "useShortNumbers" }, healthDef.useShortNumbers ~= false) end, function(val)
		setValue(unit, { "health", "useShortNumbers" }, val and true or false)
		refresh()
	end, healthDef.useShortNumbers ~= false, "health")

	local textureOpts = textureOptions
	list[#list + 1] = radioDropdown(L["Bar Texture"] or "Bar Texture", textureOpts, function() return getValue(unit, { "health", "texture" }, healthDef.texture or "DEFAULT") end, function(val)
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

	if unit ~= "pet" and not isBoss then
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

		list[#list + 1] = checkbox(L["Show sample absorb"] or "Show sample absorb", function() return sampleAbsorb[unit] == true end, function(val)
			sampleAbsorb[unit] = val and true or false
			refresh()
		end, false, "absorb")

		list[#list + 1] = radioDropdown(
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

	list[#list + 1] = checkboxColor({
		name = L["UFPowerColor"] or "Custom power color",
		parentId = "power",
		defaultChecked = powerDef.useCustomColor == true,
		isChecked = function() return getValue(unit, { "power", "useCustomColor" }, powerDef.useCustomColor == true) == true end,
		onChecked = function(val)
			debounced(unit .. "_powerCustomColorToggle", function()
				setValue(unit, { "power", "useCustomColor" }, val and true or false)
				if val and not getValue(unit, { "power", "color" }) then setValue(unit, { "power", "color" }, powerDef.color or { 0.1, 0.45, 1, 1 }) end
				refreshSelf()
				refreshSettingsUI()
			end)
		end,
		getColor = function() return toRGBA(getValue(unit, { "power", "color" }, powerDef.color or { 0.1, 0.45, 1, 1 }), powerDef.color or { 0.1, 0.45, 1, 1 }) end,
		onColor = function(color)
			debounced(unit .. "_powerCustomColor", function()
				setColor(unit, { "power", "color" }, color.r, color.g, color.b, color.a)
				setValue(unit, { "power", "useCustomColor" }, true)
				refreshSelf()
			end)
		end,
		colorDefault = {
			r = (powerDef.color and powerDef.color[1]) or 0.1,
			g = (powerDef.color and powerDef.color[2]) or 0.45,
			b = (powerDef.color and powerDef.color[3]) or 1,
			a = (powerDef.color and powerDef.color[4]) or 1,
		},
		isEnabled = isPowerEnabled,
	})

	local powerTextLeft = radioDropdown(L["TextLeft"] or "Left text", textOptions, function() return getValue(unit, { "power", "textLeft" }, powerDef.textLeft or "PERCENT") end, function(val)
		setValue(unit, { "power", "textLeft" }, val)
		refreshSelf()
	end, powerDef.textLeft or "PERCENT", "power")
	powerTextLeft.isEnabled = isPowerEnabled
	list[#list + 1] = powerTextLeft

	local powerTextRight = radioDropdown(L["TextRight"] or "Right text", textOptions, function() return getValue(unit, { "power", "textRight" }, powerDef.textRight or "CURMAX") end, function(val)
		setValue(unit, { "power", "textRight" }, val)
		refreshSelf()
	end, powerDef.textRight or "CURMAX", "power")
	powerTextRight.isEnabled = isPowerEnabled
	list[#list + 1] = powerTextRight

	local powerFontSize = slider(L["FontSize"] or "Font size", 8, 30, 1, function() return getValue(unit, { "power", "fontSize" }, powerDef.fontSize or 14) end, function(val)
		debounced(unit .. "_powerFontSize", function()
			setValue(unit, { "power", "fontSize" }, val or powerDef.fontSize or 14)
			refreshSelf()
		end)
	end, powerDef.fontSize or 14, "power", true)
	powerFontSize.isEnabled = isPowerEnabled
	list[#list + 1] = powerFontSize

	if #fontOpts > 0 then
		local powerFont = radioDropdown(L["Font"] or "Font", fontOpts, function() return getValue(unit, { "power", "font" }, powerDef.font or defaultFontPath()) end, function(val)
			setValue(unit, { "power", "font" }, val)
			refreshSelf()
		end, powerDef.font or defaultFontPath(), "power")
		powerFont.isEnabled = isPowerEnabled
		list[#list + 1] = powerFont
	end

	local powerFontOutline = radioDropdown(
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

	local powerLeftX = slider(
		L["TextLeftOffsetX"] or "Left text X offset",
		-200,
		200,
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
	list[#list + 1] = powerLeftX

	local powerLeftY = slider(
		L["TextLeftOffsetY"] or "Left text Y offset",
		-200,
		200,
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
	list[#list + 1] = powerLeftY

	local powerRightX = slider(
		L["TextRightOffsetX"] or "Right text X offset",
		-200,
		200,
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
	list[#list + 1] = powerRightX

	local powerRightY = slider(
		L["TextRightOffsetY"] or "Right text Y offset",
		-200,
		200,
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
	list[#list + 1] = powerRightY

	list[#list + 1] = checkbox(L["Use short numbers"] or "Use short numbers", function() return getValue(unit, { "power", "useShortNumbers" }, powerDef.useShortNumbers ~= false) end, function(val)
		setValue(unit, { "power", "useShortNumbers" }, val and true or false)
		refresh()
	end, powerDef.useShortNumbers ~= false, "power", isPowerEnabled)

	local powerTexture = radioDropdown(L["Bar Texture"] or "Bar Texture", textureOpts, function() return getValue(unit, { "power", "texture" }, powerDef.texture or "DEFAULT") end, function(val)
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
			-400,
			400,
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

		local classOffsetY = slider(L["Offset Y"] or "Offset Y", -400, 400, 1, function() return getValue(unit, { "classResource", "offset", "y" }, defaultOffsetY()) end, function(val)
			debounced(unit .. "_classResourceOffsetY", function()
				setValue(unit, { "classResource", "offset", "y" }, val or 0)
				refreshSelf()
			end)
		end, defaultOffsetY(), "classResource", true)
		classOffsetY.isEnabled = isClassResourceEnabled
		list[#list + 1] = classOffsetY

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
		-200,
		200,
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
		-200,
		200,
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

	if unit == "target" or unit == "focus" or isBoss then
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

		local castOffsetX = slider(L["Offset X"] or "Offset X", -200, 200, 1, function() return getValue(unit, { "cast", "offset", "x" }, (castDef.offset and castDef.offset.x) or 0) end, function(val)
			setValue(unit, { "cast", "offset", "x" }, val or 0)
			refresh()
		end, (castDef.offset and castDef.offset.x) or 0, "cast", true)
		castOffsetX.isEnabled = isCastEnabled
		list[#list + 1] = castOffsetX

		local castOffsetY = slider(L["Offset Y"] or "Offset Y", -200, 200, 1, function() return getValue(unit, { "cast", "offset", "y" }, (castDef.offset and castDef.offset.y) or 0) end, function(val)
			setValue(unit, { "cast", "offset", "y" }, val or 0)
			refresh()
		end, (castDef.offset and castDef.offset.y) or 0, "cast", true)
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

		list[#list + 1] = checkbox(L["Show spell name"] or "Show spell name", function() return getValue(unit, { "cast", "showName" }, castDef.showName ~= false) ~= false end, function(val)
			setValue(unit, { "cast", "showName" }, val and true or false)
			refresh()
			refreshSettingsUI()
		end, castDef.showName ~= false, "cast", isCastEnabled)

		local castNameX = slider(
			L["Name X Offset"] or "Name X Offset",
			-200,
			200,
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
			-200,
			200,
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

		local castNameFont = radioDropdown(L["Font"] or "Font", fontOptions(), function() return getValue(unit, { "cast", "font" }, castDef.font or "") end, function(val)
			setValue(unit, { "cast", "font" }, val)
			refresh()
		end, castDef.font or "", "cast")
		castNameFont.isEnabled = isCastNameEnabled
		list[#list + 1] = castNameFont

		local castNameFontSize = slider(L["FontSize"] or "Font size", 8, 30, 1, function() return getValue(unit, { "cast", "fontSize" }, castDef.fontSize or 12) end, function(val)
			setValue(unit, { "cast", "fontSize" }, val or 12)
			refresh()
		end, castDef.fontSize or 12, "cast", true)
		castNameFontSize.isEnabled = isCastNameEnabled
		list[#list + 1] = castNameFontSize

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

		local castDurX = slider(
			L["Duration X Offset"] or "Duration X Offset",
			-200,
			200,
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
			-200,
			200,
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

		list[#list + 1] = checkbox(L["Show sample cast"] or "Show sample cast", function() return sampleCast[unit] == true end, function(val)
			sampleCast[unit] = val and true or false
			refresh()
		end, false, "cast", isCastEnabled)

		local castTexture = radioDropdown(L["Cast texture"] or "Cast texture", textureOpts, function() return getValue(unit, { "cast", "texture" }, castDef.texture or "DEFAULT") end, function(val)
			setValue(unit, { "cast", "texture" }, val)
			refresh()
		end, castDef.texture or "DEFAULT", "cast")
		castTexture.isEnabled = isCastEnabled
		list[#list + 1] = castTexture

		list[#list + 1] = checkboxColor({
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
			get = function() return getValue(unit, { "cast", "notInterruptibleColor" }, castDef.notInterruptibleColor or { 0.6, 0.6, 0.6, 1 }) end,
			set = function(_, color)
				setColor(unit, { "cast", "notInterruptibleColor" }, color.r, color.g, color.b, color.a)
				refresh()
			end,
			colorGet = function() return getValue(unit, { "cast", "notInterruptibleColor" }, castDef.notInterruptibleColor or { 0.6, 0.6, 0.6, 1 }) end,
			colorSet = function(_, color)
				setColor(unit, { "cast", "notInterruptibleColor" }, color.r, color.g, color.b, color.a)
				refresh()
			end,
			colorDefault = {
				r = (castDef.notInterruptibleColor and castDef.notInterruptibleColor[1]) or 0.6,
				g = (castDef.notInterruptibleColor and castDef.notInterruptibleColor[2]) or 0.6,
				b = (castDef.notInterruptibleColor and castDef.notInterruptibleColor[3]) or 0.6,
				a = (castDef.notInterruptibleColor and castDef.notInterruptibleColor[4]) or 1,
			},
			hasOpacity = true,
		}
	end

	list[#list + 1] = { name = L["UFStatusLine"] or "Status line", kind = settingType.Collapsible, id = "status", defaultCollapsed = true }
	local statusDef = def.status or {}
	local function isNameEnabled() return getValue(unit, { "status", "enabled" }, statusDef.enabled ~= false) ~= false end
	local function isLevelEnabled() return getValue(unit, { "status", "levelEnabled" }, statusDef.levelEnabled ~= false) ~= false end
	local function isStatusTextEnabled() return isNameEnabled() or isLevelEnabled() end

	list[#list + 1] = checkbox(L["UFStatusEnable"] or "Show status line", isNameEnabled, function(val)
		setValue(unit, { "status", "enabled" }, val and true or false)
		refresh()
		refreshSettingsUI()
	end, statusDef.enabled ~= false, "status")

	if isPlayer then
		local ciDef = statusDef.combatIndicator or {}
		local function isCombatIndicatorEnabled()
			return getValue(unit, { "status", "combatIndicator", "enabled" }, ciDef.enabled ~= false) ~= false
		end
		local combatIndicatorToggle = checkbox(
			L["UFCombatIndicator"] or "Show combat indicator",
			function() return getValue(unit, { "status", "combatIndicator", "enabled" }, ciDef.enabled ~= false) end,
			function(val)
				setValue(unit, { "status", "combatIndicator", "enabled" }, val and true or false)
				refresh()
				refreshSettingsUI()
			end,
			ciDef.enabled ~= false,
			"status"
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
			"status",
			true
		)
		combatIndicatorSize.isEnabled = isCombatIndicatorEnabled
		list[#list + 1] = combatIndicatorSize

		local combatIndicatorOffsetX = slider(
			L["UFCombatIndicatorOffsetX"] or "Combat indicator X offset",
			-300,
			300,
			1,
			function() return getValue(unit, { "status", "combatIndicator", "offset", "x" }, (ciDef.offset and ciDef.offset.x) or -8) end,
			function(val)
				local off = getValue(unit, { "status", "combatIndicator", "offset" }, { x = -8, y = 0 }) or {}
				off.x = val or -8
				setValue(unit, { "status", "combatIndicator", "offset" }, off)
				refresh()
			end,
			(ciDef.offset and ciDef.offset.x) or -8,
			"status",
			true
		)
		combatIndicatorOffsetX.isEnabled = isCombatIndicatorEnabled
		list[#list + 1] = combatIndicatorOffsetX

		local combatIndicatorOffsetY = slider(
			L["UFCombatIndicatorOffsetY"] or "Combat indicator Y offset",
			-300,
			300,
			1,
			function() return getValue(unit, { "status", "combatIndicator", "offset", "y" }, (ciDef.offset and ciDef.offset.y) or 0) end,
			function(val)
				local off = getValue(unit, { "status", "combatIndicator", "offset" }, { x = -8, y = 0 }) or {}
				off.y = val or 0
				setValue(unit, { "status", "combatIndicator", "offset" }, off)
				refresh()
			end,
			(ciDef.offset and ciDef.offset.y) or 0,
			"status",
			true
		)
		combatIndicatorOffsetY.isEnabled = isCombatIndicatorEnabled
		list[#list + 1] = combatIndicatorOffsetY
	end

	local showLevelToggle = checkbox(L["UFShowLevel"] or "Show level", function() return getValue(unit, { "status", "levelEnabled" }, statusDef.levelEnabled ~= false) end, function(val)
		setValue(unit, { "status", "levelEnabled" }, val and true or false)
		refresh()
		refreshSettingsUI()
	end, statusDef.levelEnabled ~= false, "status")
	list[#list + 1] = showLevelToggle

	if not isBoss then
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
	end

	local statusFontSize = slider(L["FontSize"] or "Font size", 8, 30, 1, function() return getValue(unit, { "status", "fontSize" }, statusDef.fontSize or 14) end, function(val)
		debounced(unit .. "_statusFontSize", function()
			setValue(unit, { "status", "fontSize" }, val or statusDef.fontSize or 14)
			refreshSelf()
		end)
	end, statusDef.fontSize or 14, "status", true)
	statusFontSize.isEnabled = isStatusTextEnabled
	list[#list + 1] = statusFontSize

	fontOpts = fontOptions()
	if #fontOpts > 0 then
		local statusFont = radioDropdown(L["Font"] or "Font", fontOpts, function() return getValue(unit, { "status", "font" }, statusDef.font or defaultFontPath()) end, function(val)
			setValue(unit, { "status", "font" }, val)
			refreshSelf()
		end, statusDef.font or defaultFontPath(), "status")
		statusFont.isEnabled = isStatusTextEnabled
		list[#list + 1] = statusFont
	end

	local statusFontOutline = radioDropdown(
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

	local nameAnchorSetting = radioDropdown(L["UFNameAnchor"] or "Name anchor", anchorOptions, function() return getValue(unit, { "status", "nameAnchor" }, statusDef.nameAnchor or "LEFT") end, function(val)
		setValue(unit, { "status", "nameAnchor" }, val)
		refresh()
	end, statusDef.nameAnchor or "LEFT", "status")
	nameAnchorSetting.isEnabled = isNameEnabled
	list[#list + 1] = nameAnchorSetting

	local nameOffsetXSetting = slider(
		L["UFNameX"] or "Name X offset",
		-200,
		200,
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
		-200,
		200,
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

	local levelOffsetXSetting = slider(
		L["UFLevelX"] or "Level X offset",
		-200,
		200,
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
		-200,
		200,
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

	if unit == "player" then
		list[#list + 1] = { name = L["UFRestingIndicator"] or "Resting indicator", kind = settingType.Collapsible, id = "resting", defaultCollapsed = true }
		local restDef = def.resting or {}
		local function isRestEnabled() return getValue(unit, { "resting", "enabled" }, restDef.enabled ~= false) ~= false end

		list[#list + 1] = checkbox(L["UFRestingEnable"] or "Show resting indicator", function() return getValue(unit, { "resting", "enabled" }, restDef.enabled ~= false) ~= false end, function(val)
			setValue(unit, { "resting", "enabled" }, val and true or false)
			refresh()
		end, restDef.enabled ~= false, "resting")

		list[#list + 1] = slider(L["UFRestingSize"] or "Resting size", 10, 80, 1, function() return getValue(unit, { "resting", "size" }, restDef.size or 20) end, function(val)
			setValue(unit, { "resting", "size" }, val or restDef.size or 20)
			refresh()
		end, restDef.size or 20, "resting", true)
		list[#list].isEnabled = isRestEnabled

		list[#list + 1] = slider(
			L["UFRestingOffsetX"] or "Resting offset X",
			-200,
			200,
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
			"resting",
			true
		)
		list[#list].isEnabled = isRestEnabled

		list[#list + 1] = slider(
			L["UFRestingOffsetY"] or "Resting offset Y",
			-200,
			200,
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
			"resting",
			true
		)
		list[#list].isEnabled = isRestEnabled
	end

	if unit == "target" then
		list[#list + 1] = { name = L["Auras"] or "Auras", kind = settingType.Collapsible, id = "auras", defaultCollapsed = true }
		local auraDef = def.auraIcons or { size = 24, padding = 2, max = 16, showCooldown = true }
		local function debuffAnchorValue() return getValue(unit, { "auraIcons", "debuffAnchor" }, getValue(unit, { "auraIcons", "anchor" }, auraDef.debuffAnchor or auraDef.anchor or "BOTTOM")) end
		local function debuffOffsetYDefault() return (debuffAnchorValue() == "TOP" and 5 or -5) end

		list[#list + 1] = slider(L["Aura size"] or "Aura size", 12, 48, 1, function() return getValue(unit, { "auraIcons", "size" }, auraDef.size or 24) end, function(val)
			setValue(unit, { "auraIcons", "size" }, val or auraDef.size or 24)
			refresh()
		end, auraDef.size or 24, "auras", true)

		list[#list + 1] = slider(L["Aura spacing"] or "Aura spacing", 0, 10, 1, function() return getValue(unit, { "auraIcons", "padding" }, auraDef.padding or 2) end, function(val)
			setValue(unit, { "auraIcons", "padding" }, val or 0)
			refresh()
		end, auraDef.padding or 2, "auras", true)

		list[#list + 1] = slider(L["UFMaxAuras"] or "Max auras", 4, 40, 1, function() return getValue(unit, { "auraIcons", "max" }, auraDef.max or 16) end, function(val)
			setValue(unit, { "auraIcons", "max" }, val or auraDef.max or 16)
			refresh()
		end, auraDef.max or 16, "auras", true)

		list[#list + 1] = checkbox(L["Show cooldown text"] or "Show cooldown text", function() return getValue(unit, { "auraIcons", "showCooldown" }, auraDef.showCooldown ~= false) end, function(val)
			setValue(unit, { "auraIcons", "showCooldown" }, val and true or false)
			refresh()
		end, auraDef.showCooldown ~= false, "auras")

		list[#list + 1] = slider(L["Aura stack size"] or "Aura stack size", 8, 32, 1, function() return getValue(unit, { "auraIcons", "countFontSize" }, auraDef.countFontSize or 14) end, function(val)
			setValue(unit, { "auraIcons", "countFontSize" }, val or 14)
			refresh()
		end, auraDef.countFontSize or 14, "auras", true)

		local stackOutlineOptions = {
			{ value = "NONE", label = L["None"] or "None" },
			{ value = "OUTLINE", label = L["Outline"] or "Outline" },
			{ value = "THICKOUTLINE", label = L["Thick outline"] or "Thick outline" },
			{ value = "MONOCHROMEOUTLINE", label = L["Monochrome outline"] or "Monochrome outline" },
		}
		list[#list + 1] = radioDropdown(
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

		list[#list + 1] = slider(
			L["Aura stack offset X"] or "Aura stack offset X",
			-50,
			50,
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

		list[#list + 1] = slider(
			L["Aura stack offset Y"] or "Aura stack offset Y",
			-50,
			50,
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
			if UF and UF.FullScanTargetAuras then UF.FullScanTargetAuras() end
		end, (auraDef.hidePermanentAuras or auraDef.hidePermanent) == true, "auras")

		local anchorOpts = {
			{ value = "TOP", label = L["Top"] or "Top" },
			{ value = "BOTTOM", label = L["Bottom"] or "Bottom" },
		}
		list[#list + 1] = radioDropdown(L["Aura anchor"] or "Aura anchor", anchorOpts, function() return getValue(unit, { "auraIcons", "anchor" }, auraDef.anchor or "BOTTOM") end, function(val)
			setValue(unit, { "auraIcons", "anchor" }, val or "BOTTOM")
			refresh()
		end, auraDef.anchor or "BOTTOM", "auras")

		list[#list + 1] = slider(
			L["Aura Offset X"] or "Aura Offset X",
			-200,
			200,
			1,
			function() return getValue(unit, { "auraIcons", "offset", "x" }, (auraDef.offset and auraDef.offset.x) or 0) end,
			function(val)
				setValue(unit, { "auraIcons", "offset", "x" }, val or 0)
				refresh()
			end,
			(auraDef.offset and auraDef.offset.x) or 0,
			"auras",
			true
		)

		list[#list + 1] = slider(
			L["Aura Offset Y"] or "Aura Offset Y",
			-200,
			200,
			1,
			function() return getValue(unit, { "auraIcons", "offset", "y" }, (auraDef.offset and auraDef.offset.y) or (auraDef.anchor == "TOP" and 5 or -5)) end,
			function(val)
				setValue(unit, { "auraIcons", "offset", "y" }, val or 0)
				refresh()
			end,
			(auraDef.offset and auraDef.offset.y) or (auraDef.anchor == "TOP" and 5 or -5),
			"auras",
			true
		)

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

		local function isSeparateDebuffEnabled() return getValue(unit, { "auraIcons", "separateDebuffAnchor" }, auraDef.separateDebuffAnchor == true) == true end

		local debuffAnchorSetting = radioDropdown(L["UFDebuffAnchor"] or "Debuff anchor", anchorOpts, function() return debuffAnchorValue() end, function(val)
			setValue(unit, { "auraIcons", "debuffAnchor" }, val or nil)
			refresh()
		end, auraDef.debuffAnchor or auraDef.anchor or "BOTTOM", "auras")
		debuffAnchorSetting.isEnabled = isSeparateDebuffEnabled
		list[#list + 1] = debuffAnchorSetting

		list[#list + 1] = slider(
			L["Debuff Offset X"] or "Debuff Offset X",
			-200,
			200,
			1,
			function() return getValue(unit, { "auraIcons", "debuffOffset", "x" }, (auraDef.debuffOffset and auraDef.debuffOffset.x) or (auraDef.offset and auraDef.offset.x) or 0) end,
			function(val)
				setValue(unit, { "auraIcons", "debuffOffset", "x" }, val or 0)
				refresh()
			end,
			(auraDef.debuffOffset and auraDef.debuffOffset.x) or (auraDef.offset and auraDef.offset.x) or 0,
			"auras",
			true
		)
		list[#list].isEnabled = isSeparateDebuffEnabled

		list[#list + 1] = slider(
			L["Debuff Offset Y"] or "Debuff Offset Y",
			-200,
			200,
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
		layoutDefaults = layout,
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

if not UF.EditModeRegistered then
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

-- Simple toggles in Settings panel (keep basic visibility outside Edit Mode)
if addon.functions and addon.functions.SettingsCreateCategory then
	local cUF = addon.functions.SettingsCreateCategory(nil, L["UFPlusRoot"] or "UF Plus", nil, "UFPlus")
	addon.SettingsLayout.ufPlusCategory = cUF
	addon.functions.SettingsCreateText(cUF, "|cff99e599" .. L["UFPlusHint"] .. "|r")
	addon.functions.SettingsCreateText(cUF, "")
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
		})
		return def.enabled or false
	end

	addToggle("player", L["UFPlayerEnable"] or "Enable custom player frame", "ufEnablePlayer")
	addon.functions.SettingsCreateText(cUF, L["UFPlayerCastbarHint"] or 'Uses Blizzard\'s Player Castbar.\nBefore enabling, open Edit Mode\nand make sure the Player Frame setting\n"HUD_EDIT_MODE_SETTING_UNIT_FRAME_CAST_BAR_UNDERNEATH" is unchecked.')
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

		addon.functions.SettingsCreateHeadline(cUF, L["Profiles"] or "Profiles")
		addon.functions.SettingsCreateDropdown(cUF, {
			var = "ufProfileScope",
			text = L["ProfileScope"] or (L["Apply to"] or "Apply to"),
			list = scopeOptions,
			get = getScope,
			set = setScope,
			default = "ALL",
		})

		addon.functions.SettingsCreateButton(cUF, {
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
		})

		addon.functions.SettingsCreateButton(cUF, {
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
		})
	end
end
