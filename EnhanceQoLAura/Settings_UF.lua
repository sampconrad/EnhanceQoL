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
	addon.db.ufFrames[unit] = addon.db.ufFrames[unit] or {}
	return addon.db.ufFrames[unit]
end

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
	local list = { { value = "DEFAULT", label = "Default (Blizzard)" } }
	if not LSM then return list end
	local hash = LSM:HashTable("statusbar") or {}
	for name, path in pairs(hash) do
		if type(path) == "string" and path ~= "" then list[#list + 1] = { value = name, label = tostring(name) } end
	end
	table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return list
end

local function radioDropdown(name, options, getter, setter, default, parentId)
	return {
		name = name,
		kind = settingType.Dropdown,
		parentId = parentId,
		default = default,
		generator = function(_, root)
			for _, opt in ipairs(options) do
				root:CreateRadio(opt.label, function() return getter() == opt.value end, function() setter(opt.value) end)
			end
		end,
	}
end

local function slider(name, minVal, maxVal, step, getter, setter, default, parentId, allowInput)
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
	local statusHeight = (cfg.status and cfg.status.enabled ~= false) and (cfg.statusHeight or def.statusHeight or 18) or 0
	local width = cfg.width or def.width or frame:GetWidth() or 200
	local height = statusHeight + (cfg.healthHeight or def.healthHeight or 24) + (cfg.powerHeight or def.powerHeight or 16) + (cfg.barGap or def.barGap or 0)
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
	local function refreshSelf() refresh(unit) end
	local refresh = refreshSelf

	list[#list + 1] = { name = L["Frame"] or "Frame", kind = settingType.Collapsible, id = "frame", defaultCollapsed = false }

	list[#list + 1] = checkbox(L["UFPlayerEnable"] or "Enable", function() return getValue(unit, { "enabled" }, def.enabled or false) == true end, function(val)
		setValue(unit, { "enabled" }, val and true or false)
		refreshSelf()
		refreshSettingsUI()
	end, def.enabled or false, "frame")

	list[#list + 1] = slider(L["UFWidth"] or "Frame width", MIN_WIDTH, 800, 1, function() return getValue(unit, { "width" }, def.width or MIN_WIDTH) end, function(val)
		setValue(unit, { "width" }, math.max(MIN_WIDTH, val or MIN_WIDTH))
		refreshSelf()
	end, def.width or MIN_WIDTH, "frame", true)

	list[#list + 1] = slider(L["UFBarGap"] or "Gap between bars", 0, 10, 1, function() return getValue(unit, { "barGap" }, def.barGap or 0) end, function(val)
		setValue(unit, { "barGap" }, val or 0)
		refreshSelf()
	end, def.barGap or 0, "frame", true)

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

	list[#list + 1] = checkbox(L["UFUseClassColor"] or "Use class color", function() return getValue(unit, { "health", "useClassColor" }, healthDef.useClassColor == true) == true end, function(val)
		setValue(unit, { "health", "useClassColor" }, val and true or false)
		if val then setValue(unit, { "health", "useCustomColor" }, false) end
		refreshSelf()
		refreshSettingsUI()
	end, healthDef.useClassColor == true, "health", function() return getValue(unit, { "health", "useCustomColor" }, healthDef.useCustomColor == true) ~= true end)

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

	local textureOpts = textureOptions()
	list[#list + 1] = radioDropdown(L["Bar Texture"] or "Bar Texture", textureOpts, function() return getValue(unit, { "health", "texture" }, healthDef.texture or "DEFAULT") end, function(val)
		setValue(unit, { "health", "texture" }, val)
		refresh()
	end, healthDef.texture or "DEFAULT", "health")

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

	list[#list + 1] = checkbox(L["Use absorb glow"] or "Use absorb glow", function()
		return getValue(unit, { "health", "useAbsorbGlow" }, healthDef.useAbsorbGlow ~= false) ~= false
	end, function(val)
		setValue(unit, { "health", "useAbsorbGlow" }, val and true or false)
		refresh()
	end, healthDef.useAbsorbGlow ~= false, "absorb")

	list[#list + 1] = checkbox(L["Show sample absorb"] or "Show sample absorb", function()
		return getValue(unit, { "health", "showSampleAbsorb" }, healthDef.showSampleAbsorb == true)
	end, function(val)
		setValue(unit, { "health", "showSampleAbsorb" }, val and true or false)
		refresh()
	end, healthDef.showSampleAbsorb == true, "absorb")

	list[#list + 1] = radioDropdown(L["Absorb texture"] or "Absorb texture", textureOpts, function()
		return getValue(unit, { "health", "absorbTexture" }, healthDef.absorbTexture or healthDef.texture or "DEFAULT")
	end, function(val)
		setValue(unit, { "health", "absorbTexture" }, val)
		refresh()
	end, healthDef.absorbTexture or healthDef.texture or "DEFAULT", "absorb")

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

	list[#list + 1] = { name = L["PowerBar"] or "Power Bar", kind = settingType.Collapsible, id = "power", defaultCollapsed = true }
	local powerDef = def.power or {}

	list[#list + 1] = slider(L["UFPowerHeight"] or "Power height", 6, 60, 1, function() return getValue(unit, { "powerHeight" }, def.powerHeight or 16) end, function(val)
		debounced(unit .. "_powerHeight", function()
			setValue(unit, { "powerHeight" }, val or def.powerHeight or 16)
			refresh()
		end)
	end, def.powerHeight or 16, "power", true)

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
	})

	list[#list + 1] = radioDropdown(L["TextLeft"] or "Left text", textOptions, function() return getValue(unit, { "power", "textLeft" }, powerDef.textLeft or "PERCENT") end, function(val)
		setValue(unit, { "power", "textLeft" }, val)
		refreshSelf()
	end, powerDef.textLeft or "PERCENT", "power")

	list[#list + 1] = radioDropdown(L["TextRight"] or "Right text", textOptions, function() return getValue(unit, { "power", "textRight" }, powerDef.textRight or "CURMAX") end, function(val)
		setValue(unit, { "power", "textRight" }, val)
		refreshSelf()
	end, powerDef.textRight or "CURMAX", "power")

	list[#list + 1] = slider(L["FontSize"] or "Font size", 8, 30, 1, function() return getValue(unit, { "power", "fontSize" }, powerDef.fontSize or 14) end, function(val)
		debounced(unit .. "_powerFontSize", function()
			setValue(unit, { "power", "fontSize" }, val or powerDef.fontSize or 14)
			refreshSelf()
		end)
	end, powerDef.fontSize or 14, "power", true)

	if #fontOpts > 0 then
		list[#list + 1] = radioDropdown(L["Font"] or "Font", fontOpts, function() return getValue(unit, { "power", "font" }, powerDef.font or defaultFontPath()) end, function(val)
			setValue(unit, { "power", "font" }, val)
			refreshSelf()
		end, powerDef.font or defaultFontPath(), "power")
	end

	list[#list + 1] = radioDropdown(
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

	list[#list + 1] = slider(
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

	list[#list + 1] = slider(
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

	list[#list + 1] = slider(
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

	list[#list + 1] = slider(
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

	list[#list + 1] = checkbox(L["Use short numbers"] or "Use short numbers", function() return getValue(unit, { "power", "useShortNumbers" }, powerDef.useShortNumbers ~= false) end, function(val)
		setValue(unit, { "power", "useShortNumbers" }, val and true or false)
		refresh()
	end, powerDef.useShortNumbers ~= false, "power")

	list[#list + 1] = radioDropdown(L["Bar Texture"] or "Bar Texture", textureOpts, function() return getValue(unit, { "power", "texture" }, powerDef.texture or "DEFAULT") end, function(val)
		setValue(unit, { "power", "texture" }, val)
		refresh()
	end, powerDef.texture or "DEFAULT", "power")

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
	})

	list[#list + 1] = { name = L["UFStatusLine"] or "Status line", kind = settingType.Collapsible, id = "status", defaultCollapsed = true }
	local statusDef = def.status or {}

	list[#list + 1] = checkbox(L["UFStatusEnable"] or "Show status line", function() return getValue(unit, { "status", "enabled" }, statusDef.enabled ~= false) end, function(val)
		setValue(unit, { "status", "enabled" }, val and true or false)
		refresh()
	end, statusDef.enabled ~= false, "status")

	list[#list + 1] = checkbox(L["UFShowLevel"] or "Show level", function() return getValue(unit, { "status", "levelEnabled" }, statusDef.levelEnabled ~= false) end, function(val)
		setValue(unit, { "status", "levelEnabled" }, val and true or false)
		refresh()
	end, statusDef.levelEnabled ~= false, "status")

	list[#list + 1] = checkboxColor({
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

	list[#list + 1] = checkboxColor({
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

	list[#list + 1] = slider(L["FontSize"] or "Font size", 8, 30, 1, function() return getValue(unit, { "status", "fontSize" }, statusDef.fontSize or 14) end, function(val)
		debounced(unit .. "_statusFontSize", function()
			setValue(unit, { "status", "fontSize" }, val or statusDef.fontSize or 14)
			refreshSelf()
		end)
	end, statusDef.fontSize or 14, "status", true)

	fontOpts = fontOptions()
	if #fontOpts > 0 then
		list[#list + 1] = radioDropdown(L["Font"] or "Font", fontOpts, function() return getValue(unit, { "status", "font" }, statusDef.font or defaultFontPath()) end, function(val)
			setValue(unit, { "status", "font" }, val)
			refreshSelf()
		end, statusDef.font or defaultFontPath(), "status")
	end

	list[#list + 1] = radioDropdown(
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

	list[#list + 1] = radioDropdown(L["UFNameAnchor"] or "Name anchor", anchorOptions, function() return getValue(unit, { "status", "nameAnchor" }, statusDef.nameAnchor or "LEFT") end, function(val)
		setValue(unit, { "status", "nameAnchor" }, val)
		refresh()
	end, statusDef.nameAnchor or "LEFT", "status")

	list[#list + 1] = slider(
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

	list[#list + 1] = slider(
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

	list[#list + 1] = radioDropdown(
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

	list[#list + 1] = slider(
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

	list[#list + 1] = slider(
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

	if unit == "target" then
		list[#list + 1] = { name = L["Auras"] or "Auras", kind = settingType.Collapsible, id = "auras", defaultCollapsed = true }
		local auraDef = def.auraIcons or { size = 24, padding = 2, max = 16, showCooldown = true }

		list[#list + 1] = slider(L["UFHealthHeight"] or "Aura size", 12, 48, 1, function() return getValue(unit, { "auraIcons", "size" }, auraDef.size or 24) end, function(val)
			setValue(unit, { "auraIcons", "size" }, val or auraDef.size or 24)
			refresh()
		end, auraDef.size or 24, "auras", true)

		list[#list + 1] = slider(L["UFBarGap"] or "Aura spacing", 0, 10, 1, function() return getValue(unit, { "auraIcons", "padding" }, auraDef.padding or 2) end, function(val)
			setValue(unit, { "auraIcons", "padding" }, val or 0)
			refresh()
		end, auraDef.padding or 2, "auras", true)

		list[#list + 1] = slider(L["UFFrameLevel"] or "Max auras", 4, 40, 1, function() return getValue(unit, { "auraIcons", "max" }, auraDef.max or 16) end, function(val)
			setValue(unit, { "auraIcons", "max" }, val or auraDef.max or 16)
			refresh()
		end, auraDef.max or 16, "auras", true)

		list[#list + 1] = checkbox(L["Show cooldown text"] or "Show cooldown text", function() return getValue(unit, { "auraIcons", "showCooldown" }, auraDef.showCooldown ~= false) end, function(val)
			setValue(unit, { "auraIcons", "showCooldown" }, val and true or false)
			refresh()
		end, auraDef.showCooldown ~= false, "auras")
	end

	return list
end

local function registerUnitFrame(unit, info)
	if UF.EnsureFrames then UF.EnsureFrames(unit) end
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
			if data.width then cfg.width = data.width end
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
		player = { frameName = "EQOLUFPlayerFrame", frameId = "EQOL_UF_Player", title = L["UFPlayerFrame"] or PLAYER },
		target = { frameName = "EQOLUFTargetFrame", frameId = "EQOL_UF_Target", title = L["UFTargetFrame"] or TARGET },
		targettarget = { frameName = "EQOLUFToTFrame", frameId = "EQOL_UF_ToT", title = L["UFToTFrame"] or "Target of Target" },
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
			end,
		})
		return def.enabled or false
	end

	addToggle("player", L["UFPlayerEnable"] or "Enable custom player frame", "ufEnablePlayer")
	addToggle("target", L["UFTargetEnable"] or "Enable custom target frame", "ufEnableTarget")
	addToggle("targettarget", L["UFToTEnable"] or "Enable target-of-target frame", "ufEnableToT")
end
