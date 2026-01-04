local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local ActionBarLabels = addon.ActionBarLabels
local constants = addon.constants or {}

local NormalizeActionBarVisibilityConfig = addon.functions.NormalizeActionBarVisibilityConfig or function() end
local NormalizeUnitFrameVisibilityConfig = addon.functions.NormalizeUnitFrameVisibilityConfig or function() end
local UpdateActionBarMouseover = addon.functions.UpdateActionBarMouseover or function() end
local UpdateUnitFrameMouseover = addon.functions.UpdateUnitFrameMouseover or function() end
local RefreshAllActionBarAnchors = addon.functions.RefreshAllActionBarAnchors or function() end
local RefreshAllActionBarVisibilityAlpha = addon.functions.RefreshAllActionBarVisibilityAlpha or function() end
local GetActionBarFadeStrength = addon.functions.GetActionBarFadeStrength or function() return 1 end
local GetFrameFadeStrength = addon.functions.GetFrameFadeStrength or function() return 1 end
local RefreshAllFrameVisibilityAlpha = addon.functions.RefreshAllFrameVisibilityAlpha or function() end
local GetVisibilityRuleMetadata = addon.functions.GetVisibilityRuleMetadata or function() return {} end
local HasFrameVisibilityOverride = addon.functions.HasFrameVisibilityOverride or function() return false end
local SetCooldownViewerVisibility = addon.functions.SetCooldownViewerVisibility or function() end
local GetCooldownViewerVisibility = addon.functions.GetCooldownViewerVisibility or function() return nil end
local IsCooldownViewerEnabled = addon.functions.IsCooldownViewerEnabled or function() return false end

local ACTION_BAR_FRAME_NAMES = constants.ACTION_BAR_FRAME_NAMES or {}
local ACTION_BAR_ANCHOR_ORDER = constants.ACTION_BAR_ANCHOR_ORDER or {}
local ACTION_BAR_ANCHOR_CONFIG = constants.ACTION_BAR_ANCHOR_CONFIG or {}
local COOLDOWN_VIEWER_FRAMES = constants.COOLDOWN_VIEWER_FRAMES or {}
local COOLDOWN_VIEWER_VISIBILITY_MODES = constants.COOLDOWN_VIEWER_VISIBILITY_MODES or {
	NONE = "NONE",
	HIDE_WHILE_MOUNTED = "HIDE_WHILE_MOUNTED",
}
local wipe = wipe
local fontOrder = {}

addon.db = addon.db or {}
addon.db.actionBarHiddenHotkeys = type(addon.db.actionBarHiddenHotkeys) == "table" and addon.db.actionBarHiddenHotkeys or {}

local function collectRuleOptions(kind)
	local options = {}
	for key, data in pairs(GetVisibilityRuleMetadata() or {}) do
		if data.appliesTo and data.appliesTo[kind] then table.insert(options, {
			value = key,
			text = data.label or key,
			order = data.order or 999,
		}) end
	end
	table.sort(options, function(a, b)
		if a.order == b.order then return a.text < b.text end
		return a.order < b.order
	end)
	return options
end

local ACTIONBAR_RULE_OPTIONS = collectRuleOptions("actionbar")
local function notifyFrameRuleLocked(label)
	local base = L["visibilityRule_lockedByUF"] or "Visibility is controlled by Enhanced Unit Frames. Disable them to change this setting."
	if label and label ~= "" then base = base .. " (" .. tostring(label) .. ")" end
	print("|cff00ff98Enhance QoL|r: " .. base)
end

local function buildFontDropdown()
	local map = {
		[addon.variables.defaultFont] = L["actionBarFontDefault"] or "Blizzard Font",
	}
	local LSM = LibStub("LibSharedMedia-3.0", true)
	if LSM and LSM.HashTable then
		for name, path in pairs(LSM:HashTable("font") or {}) do
			if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
		end
	end
	local list, order = addon.functions.prepareListForDropdown(map)
	wipe(fontOrder)
	for i, key in ipairs(order) do
		fontOrder[i] = key
	end
	return list
end

local function createActionBarVisibility(category, expandable)
	if #ACTIONBAR_RULE_OPTIONS == 0 then return end

	addon.functions.SettingsCreateHeadline(category, L["visibilityScenarioGroupTitle"] or ACTIONBARS_LABEL, { parentSection = expandable })

	local explain = L["ActionbarVisibilityExplain2"]
	if explain and _G["HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_ALWAYS"] and _G["HUD_EDIT_MODE_MENU"] then
		addon.functions.SettingsCreateText(category, explain:format(_G["HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_ALWAYS"], _G["HUD_EDIT_MODE_MENU"]), { parentSection = expandable })
	end

	local bars, seenVars = {}, {}
	for _, info in ipairs(addon.variables.actionBarNames or {}) do
		if info.var and not seenVars[info.var] then
			table.insert(bars, info)
			seenVars[info.var] = true
		end
	end

	table.sort(bars, function(a, b) return (a.text or a.name or "") < (b.text or b.name or "") end)

	for _, info in ipairs(bars) do
		if info.var and info.name then
			local exp = expandable
			local ABRule = collectRuleOptions("actionbar")

			addon.functions.SettingsCreateMultiDropdown(category, {
				var = info.var .. "_visibility",
				text = info.text or info.name or info.var,
				options = ABRule,
				isSelectedFunc = function(key)
					local cfg = NormalizeActionBarVisibilityConfig(info.var)
					return cfg and cfg[key] == true
				end,
				setSelectedFunc = function(key, shouldSelect)
					local working = addon.db[info.var]
					if type(working) ~= "table" then working = {} end
					if shouldSelect then
						working[key] = true
					else
						working[key] = nil
					end
					local normalized = NormalizeActionBarVisibilityConfig(info.var, working)
					UpdateActionBarMouseover(info.name, normalized, info.var)
				end,
				parentSection = exp,
			})
		end
	end

	addon.functions.SettingsCreateCheckbox(category, {
		var = "actionBarMouseoverShowAll",
		text = L["actionBarMouseoverShowAll"] or "Show all action bars on mouseover",
		desc = L["actionBarMouseoverShowAllDesc"] or "When any action bar is hovered, show every action bar that uses the Mouseover rule.",
		func = function(value)
			addon.db.actionBarMouseoverShowAll = value and true or false
			for _, info in ipairs(addon.variables.actionBarNames or {}) do
				if info.var and info.name then
					local normalized = NormalizeActionBarVisibilityConfig(info.var)
					UpdateActionBarMouseover(info.name, normalized, info.var)
				end
			end
			RefreshAllActionBarVisibilityAlpha()
		end,
		parentSection = expandable,
	})

	local function getFadePercent()
		local value = GetActionBarFadeStrength()
		if value < 0 then value = 0 end
		if value > 1 then value = 1 end
		return math.floor((value * 100) + 0.5)
	end

	addon.functions.SettingsCreateSlider(category, {
		var = "actionBarFadeStrength",
		text = L["actionBarFadeStrength"] or "Fade amount",
		desc = L["actionBarFadeStrengthDesc"],
		min = 0,
		max = 100,
		step = 1,
		default = 100,
		get = getFadePercent,
		set = function(val)
			local pct = tonumber(val) or 0
			if pct < 0 then pct = 0 end
			if pct > 100 then pct = 100 end
			addon.db.actionBarFadeStrength = pct / 100
			RefreshAllActionBarVisibilityAlpha(true)
		end,
		parentSection = expandable,
	})
end

local function createAnchorControls(category, expandable)
	if #ACTION_BAR_FRAME_NAMES == 0 then return end

	addon.functions.SettingsCreateHeadline(category, L["actionBarAnchorSectionTitle"] or "Button growth", { parentSection = expandable })

	local anchorToggle = addon.functions.SettingsCreateCheckbox(category, {
		var = "actionBarAnchorEnabled",
		text = L["actionBarAnchorEnable"] or "Modify Action Bar anchor",
		desc = L["actionBarAnchorEnableDesc"],
		func = function(value)
			addon.db["actionBarAnchorEnabled"] = value and true or false
			RefreshAllActionBarAnchors()
		end,
		parentSection = expandable,
	})

	local anchorOptions = {
		TOPLEFT = L["topLeft"] or "Top Left",
		TOPRIGHT = L["topRight"] or "Top Right",
		BOTTOMLEFT = L["bottomLeft"] or "Bottom Left",
		BOTTOMRIGHT = L["bottomRight"] or "Bottom Right",
	}
	local anchorOrder = ACTION_BAR_ANCHOR_ORDER

	for index = 1, #ACTION_BAR_FRAME_NAMES do
		local label
		if L["actionBarAnchorDropdown"] then
			label = L["actionBarAnchorDropdown"]:format(index)
		else
			label = string.format("Action Bar %d button anchor", index)
		end

		local dbKey = "actionBarAnchor" .. index
		local defaultKey = "actionBarAnchorDefault" .. index

		addon.functions.SettingsCreateDropdown(category, {
			var = dbKey,
			text = label,
			list = anchorOptions,
			order = anchorOrder,
			default = addon.db[defaultKey] or ACTION_BAR_ANCHOR_ORDER[1],
			get = function()
				local current = addon.db[dbKey]
				if not current or not ACTION_BAR_ANCHOR_CONFIG[current] then current = addon.db[defaultKey] end
				if not current or not ACTION_BAR_ANCHOR_CONFIG[current] then current = ACTION_BAR_ANCHOR_ORDER[1] end
				return current
			end,
			set = function(key)
				if not ACTION_BAR_ANCHOR_CONFIG[key] then return end
				addon.db[dbKey] = key
				RefreshAllActionBarAnchors()
			end,
			parent = true,
			element = anchorToggle.element,
			parentCheck = function() return anchorToggle.setting and anchorToggle.setting:GetValue() == true end,
			parentSection = expandable,
		})
	end
end

local function createButtonAppearanceControls(category, expandable)
	addon.functions.SettingsCreateHeadline(category, L["actionBarAppearanceHeader"] or "Button appearance", { parentSection = expandable })

	addon.functions.SettingsCreateCheckbox(category, {
		var = "actionBarHideBorders",
		text = L["actionBarHideBorders"] or "Hide button borders",
		desc = L["actionBarHideBordersDesc"] or "Remove the default border texture around action buttons.",
		func = function(value)
			addon.db.actionBarHideBorders = value and true or false
			if ActionBarLabels and ActionBarLabels.RefreshActionButtonBorders then ActionBarLabels.RefreshActionButtonBorders() end
		end,
		parentSection = expandable,
	})

	addon.functions.SettingsCreateCheckbox(category, {
		var = "actionBarHideAssistedRotation",
		text = L["actionBarHideAssistedRotation"] or "Hide assisted rotation overlay",
		desc = L["actionBarHideAssistedRotationDesc"] or "Hide the Assisted Combat Rotation glow/overlay that Blizzard adds to the action button.",
		func = function(value)
			addon.db.actionBarHideAssistedRotation = value and true or false
			if addon.functions.UpdateAssistedCombatFrameHiding then addon.functions.UpdateAssistedCombatFrameHiding() end
		end,
		parentSection = expandable,
	})

	addon.functions.SettingsCreateCheckbox(category, {
		var = "hideExtraActionArtwork",
		text = L["hideExtraActionArtwork"] or "Hide Extra Action/Zone Ability artwork",
		desc = L["hideExtraActionArtworkDesc"] or "Hide the decorative frame on the Extra Action Button and Zone Ability and disable mouse input on the Extra Action bar.",
		func = function(value)
			addon.db.hideExtraActionArtwork = value and true or false
			if addon.functions.ApplyExtraActionArtworkSetting then addon.functions.ApplyExtraActionArtworkSetting() end
		end,
		parentSection = expandable,
	})
end

local function createLabelControls(category, expandable)
	addon.functions.SettingsCreateHeadline(category, L["actionBarLabelGroupTitle"] or "Button text", { parentSection = expandable })

	local outlineOrder = { "NONE", "OUTLINE", "THICKOUTLINE", "MONOCHROMEOUTLINE" }
	local outlineOptions = {
		NONE = L["fontOutlineNone"] or NONE,
		OUTLINE = L["fontOutlineThin"] or "Outline",
		THICKOUTLINE = L["fontOutlineThick"] or "Thick Outline",
		MONOCHROMEOUTLINE = L["fontOutlineMono"] or "Monochrome Outline",
	}

	local macroOverride
	local hideMacro = addon.functions.SettingsCreateCheckbox(category, {
		var = "hideMacroNames",
		text = L["hideMacroNames"],
		desc = L["hideMacroNamesDesc"],
		func = function(value)
			addon.db["hideMacroNames"] = value and true or false
			if value then
				addon.db.actionBarMacroFontOverride = false
				if macroOverride and macroOverride.setting then macroOverride.setting:SetValue(false) end
			end
			if ActionBarLabels and ActionBarLabels.RefreshAllMacroNameVisibility then ActionBarLabels.RefreshAllMacroNameVisibility() end
		end,
		parentSection = expandable,
	})

	macroOverride = addon.functions.SettingsCreateCheckbox(category, {
		var = "actionBarMacroFontOverride",
		text = L["actionBarMacroFontOverride"] or "Change macro font",
		func = function(value)
			if value then
				addon.db["hideMacroNames"] = false
				if hideMacro and hideMacro.setting then hideMacro.setting:SetValue(false) end
			end
			addon.db.actionBarMacroFontOverride = value and true or false
			if ActionBarLabels and ActionBarLabels.RefreshAllMacroNameVisibility then ActionBarLabels.RefreshAllMacroNameVisibility() end
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
		parentSection = expandable,
	})

	local function macroParentCheck() return macroOverride.setting and macroOverride.setting:GetValue() == true and hideMacro.setting and hideMacro.setting:GetValue() ~= true end

	addon.functions.SettingsCreateScrollDropdown(category, {
		var = "actionBarMacroFontFace",
		text = L["actionBarMacroFontLabel"] or "Macro name font",
		listFunc = buildFontDropdown,
		order = fontOrder,
		default = addon.variables.defaultFont,
		get = function()
			local current = addon.db.actionBarMacroFontFace or addon.variables.defaultFont
			local list = buildFontDropdown()
			if not list[current] then current = addon.variables.defaultFont end
			return current
		end,
		set = function(key)
			addon.db.actionBarMacroFontFace = key
			if ActionBarLabels and ActionBarLabels.RefreshAllMacroNameVisibility then ActionBarLabels.RefreshAllMacroNameVisibility() end
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
		parent = true,
		element = macroOverride.element,
		parentCheck = macroParentCheck,
		parentSection = expandable,
	})

	addon.functions.SettingsCreateDropdown(category, {
		var = "actionBarMacroFontOutline",
		text = L["actionBarFontOutlineLabel"] or "Font outline",
		list = outlineOptions,
		order = outlineOrder,
		default = "OUTLINE",
		get = function() return addon.db.actionBarMacroFontOutline or "OUTLINE" end,
		set = function(key)
			addon.db.actionBarMacroFontOutline = key
			if ActionBarLabels and ActionBarLabels.RefreshAllMacroNameVisibility then ActionBarLabels.RefreshAllMacroNameVisibility() end
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
		parent = true,
		element = macroOverride.element,
		parentCheck = macroParentCheck,
		parentSection = expandable,
	})

	addon.functions.SettingsCreateSlider(category, {
		var = "actionBarMacroFontSize",
		text = L["actionBarMacroFontSize"] or "Macro font size",
		min = 8,
		max = 24,
		step = 1,
		default = 12,
		get = function()
			local value = tonumber(addon.db.actionBarMacroFontSize) or 12
			if value < 8 then value = 8 end
			if value > 24 then value = 24 end
			return value
		end,
		set = function(val)
			val = math.floor(val + 0.5)
			if val < 8 then val = 8 end
			if val > 24 then val = 24 end
			addon.db.actionBarMacroFontSize = val
			if ActionBarLabels and ActionBarLabels.RefreshAllMacroNameVisibility then ActionBarLabels.RefreshAllMacroNameVisibility() end
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
		parent = true,
		element = macroOverride.element,
		parentCheck = macroParentCheck,
		parentSection = expandable,
	})

	local hotkeyOverride = addon.functions.SettingsCreateCheckbox(category, {
		var = "actionBarHotkeyFontOverride",
		text = L["actionBarHotkeyFontOverride"] or "Change keybind font",
		func = function(value)
			addon.db.actionBarHotkeyFontOverride = value and true or false
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyVisibility then ActionBarLabels.RefreshAllHotkeyVisibility() end
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
		parentSection = expandable,
	})

	local function hotkeyParentCheck() return hotkeyOverride.setting and hotkeyOverride.setting:GetValue() == true end

	addon.functions.SettingsCreateScrollDropdown(category, {
		var = "actionBarHotkeyFontFace",
		text = L["actionBarHotkeyFontLabel"] or "Keybind font",
		listFunc = buildFontDropdown,
		order = fontOrder,
		default = addon.variables.defaultFont,
		get = function()
			local current = addon.db.actionBarHotkeyFontFace or addon.variables.defaultFont
			local list = buildFontDropdown()
			if not list[current] then current = addon.variables.defaultFont end
			return current
		end,
		set = function(key)
			addon.db.actionBarHotkeyFontFace = key
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyVisibility then ActionBarLabels.RefreshAllHotkeyVisibility() end
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
		parent = true,
		element = hotkeyOverride.element,
		parentCheck = hotkeyParentCheck,
		parentSection = expandable,
	})

	addon.functions.SettingsCreateDropdown(category, {
		var = "actionBarHotkeyFontOutline",
		text = L["actionBarFontOutlineLabel"] or "Font outline",
		list = outlineOptions,
		order = outlineOrder,
		default = "OUTLINE",
		get = function() return addon.db.actionBarHotkeyFontOutline or "OUTLINE" end,
		set = function(key)
			addon.db.actionBarHotkeyFontOutline = key
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyVisibility then ActionBarLabels.RefreshAllHotkeyVisibility() end
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
		parent = true,
		element = hotkeyOverride.element,
		parentCheck = hotkeyParentCheck,
		parentSection = expandable,
	})

	addon.functions.SettingsCreateSlider(category, {
		var = "actionBarHotkeyFontSize",
		text = L["actionBarHotkeyFontSize"] or "Keybind font size",
		min = 8,
		max = 24,
		step = 1,
		default = 12,
		get = function()
			local value = tonumber(addon.db.actionBarHotkeyFontSize) or 12
			if value < 8 then value = 8 end
			if value > 24 then value = 24 end
			return value
		end,
		set = function(val)
			val = math.floor(val + 0.5)
			if val < 8 then val = 8 end
			if val > 24 then val = 24 end
			addon.db.actionBarHotkeyFontSize = val
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyVisibility then ActionBarLabels.RefreshAllHotkeyVisibility() end
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
		parent = true,
		element = hotkeyOverride.element,
		parentCheck = hotkeyParentCheck,
		parentSection = expandable,
	})

	addon.functions.SettingsCreateHeadline(category, L["actionBarKeybindVisibilityHeader"] or "Keybind label visibility", { parentSection = expandable })

	local barOptions = {}
	for _, info in ipairs(addon.variables.actionBarNames or {}) do
		if info.name then table.insert(barOptions, { value = info.name, text = info.text or info.name }) end
	end
	table.sort(barOptions, function(a, b) return tostring(a.text) < tostring(b.text) end)

	addon.functions.SettingsCreateCheckbox(category, {
		var = "actionBarShortHotkeys",
		text = L["actionBarShortHotkeys"] or "Shorten keybind text",
		desc = L["actionBarShortHotkeysDesc"],
		func = function(value)
			addon.db.actionBarShortHotkeys = value and true or false
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
		parentSection = expandable,
	})

	local rangeToggle = addon.functions.SettingsCreateCheckbox(category, {
		var = "actionBarFullRangeColoring",
		text = L["fullButtonRangeColoring"],
		desc = L["fullButtonRangeColoringDesc"],
		func = function(value)
			addon.db["actionBarFullRangeColoring"] = value
			if ActionBarLabels and ActionBarLabels.UpdateRangeOverlayEvents then ActionBarLabels.UpdateRangeOverlayEvents() end
			if ActionBarLabels and ActionBarLabels.RefreshAllRangeOverlays then ActionBarLabels.RefreshAllRangeOverlays() end
		end,
		parentSection = expandable,
	})

	addon.functions.SettingsCreateColorPicker(category, {
		var = "actionBarFullRangeColor",
		text = L["rangeOverlayColor"],
		callback = function()
			if ActionBarLabels and ActionBarLabels.RefreshAllRangeOverlays then ActionBarLabels.RefreshAllRangeOverlays() end
		end,
		parent = true,
		element = rangeToggle.element,
		parentCheck = function() return rangeToggle.setting and rangeToggle.setting:GetValue() == true end,
		colorizeLabel = true,
		parentSection = expandable,
	})

	addon.functions.SettingsCreateMultiDropdown(category, {
		var = "actionBarHiddenHotkeys",
		text = L["actionBarHideHotkeysGroup"] or "Hide keybinds per bar",
		options = barOptions,
		isSelectedFunc = function(key) return addon.db.actionBarHiddenHotkeys and addon.db.actionBarHiddenHotkeys[key] == true end,
		setSelectedFunc = function(key, shouldSelect)
			if type(addon.db.actionBarHiddenHotkeys) ~= "table" then addon.db.actionBarHiddenHotkeys = {} end
			if shouldSelect then
				addon.db.actionBarHiddenHotkeys[key] = true
			else
				addon.db.actionBarHiddenHotkeys[key] = nil
			end
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
		desc = L["actionBarHideHotkeysDesc"],
		parentSection = expandable,
	})
end

local function createActionBarCategory()
	--local category = addon.functions.SettingsCreateCategory(nil, L["visibilityKindActionBars"] or ACTIONBARS_LABEL, nil, "ActionBar")
	--addon.SettingsLayout.actionBarCategory = category
	local category = addon.SettingsLayout.rootUI

	local expandable = addon.functions.SettingsCreateExpandableSection(category, {
		name = ACTIONBARS_LABEL,
		expanded = false,
		colorizeTitle = false,
	})

	createActionBarVisibility(category, expandable)
	createAnchorControls(category, expandable)
	createButtonAppearanceControls(category, expandable)
	createLabelControls(category, expandable)
end

local function setFrameRule(info, key, shouldSelect)
	if not info or not info.var then return end
	if HasFrameVisibilityOverride(info.var) then
		notifyFrameRuleLocked(info.text or info.name or info.var)
		return
	end
	local working = addon.db[info.var]
	if type(working) ~= "table" then working = {} end

	if key == "ALWAYS_HIDDEN" and shouldSelect then
		working = { ALWAYS_HIDDEN = true }
	elseif shouldSelect then
		working[key] = true
		working.ALWAYS_HIDDEN = nil
	else
		working[key] = nil
	end

	NormalizeUnitFrameVisibilityConfig(info.var, working)
	UpdateUnitFrameMouseover(info.name, info)
end

local function getFrameRuleOptions(info)
	local options = {}
	for key, data in pairs(GetVisibilityRuleMetadata() or {}) do
		local allowed = data.appliesTo and data.appliesTo.frame
		if allowed and data.unitRequirement and data.unitRequirement ~= info.unitToken then allowed = false end
		if allowed then table.insert(options, { value = key, text = data.label or key, order = data.order or 999 }) end
	end
	table.sort(options, function(a, b)
		if a.order == b.order then return a.text < b.text end
		return a.order < b.order
	end)
	return options
end

local function createCooldownViewerDropdowns(category, expandable)
	if not category or #COOLDOWN_VIEWER_FRAMES == 0 then return end

	addon.functions.SettingsCreateHeadline(category, L["cooldownManagerHeader"] or "Show when", { parentSection = expandable })

	local options = {
		{ value = COOLDOWN_VIEWER_VISIBILITY_MODES.IN_COMBAT, text = L["cooldownManagerShowCombat"] or "In combat" },
		{ value = COOLDOWN_VIEWER_VISIBILITY_MODES.WHILE_MOUNTED, text = L["cooldownManagerShowMounted"] or "Mounted" },
		{ value = COOLDOWN_VIEWER_VISIBILITY_MODES.WHILE_NOT_MOUNTED, text = L["cooldownManagerShowNotMounted"] or "Not mounted" },
		{ value = COOLDOWN_VIEWER_VISIBILITY_MODES.MOUSEOVER, text = L["cooldownManagerShowMouseover"] or "On mouseover" },
	}
	local labels = {
		EssentialCooldownViewer = L["cooldownViewerEssential"] or "Essential Cooldown Viewer",
		UtilityCooldownViewer = L["cooldownViewerUtility"] or "Utility Cooldown Viewer",
		BuffBarCooldownViewer = L["cooldownViewerBuffBar"] or "Buff Bar Cooldowns",
		BuffIconCooldownViewer = L["cooldownViewerBuffIcon"] or "Buff Icon Cooldowns",
	}

	local function dropdownEnabled() return IsCooldownViewerEnabled() end
	local desc = L["cooldownManagerShowDesc"] or "Requires the Cooldown Viewer to be enabled (cooldownViewerEnabled = 1). Visible while any selected condition is true."

	for _, frameName in ipairs(COOLDOWN_VIEWER_FRAMES) do
		local exp = expandable
		local label = labels[frameName] or frameName
		addon.functions.SettingsCreateMultiDropdown(category, {
			var = "cooldownViewerVisibility_" .. tostring(frameName),
			text = label,
			options = options,
			hideSummary = true,
			isSelectedFunc = function(key)
				local cfg = GetCooldownViewerVisibility(frameName)
				return cfg and cfg[key] == true
			end,
			setSelectedFunc = function(key, shouldSelect) SetCooldownViewerVisibility(frameName, key, shouldSelect) end,
			getSelection = function() return GetCooldownViewerVisibility(frameName) or {} end,
			setSelection = function(map)
				for _, opt in ipairs(options) do
					local key = opt.value
					local desired = map and map[key] == true
					SetCooldownViewerVisibility(frameName, key, desired)
				end
			end,
			isEnabled = dropdownEnabled,
			desc = desc,
			parentSection = exp,
		})
	end
end

local function createFrameCategory()
	local category = addon.SettingsLayout.rootUI

	local expandable = addon.functions.SettingsCreateExpandableSection(category, {
		name = L["visibilityKindFrames"],
		newTagID = "VisibilityFrames",
		expanded = false,
		colorizeTitle = false,
	})
	addon.SettingsLayout.uiFramesExpandable = expandable

	addon.functions.SettingsCreateHeadline(category, L["visibilityScenarioGroupTitle"] or (L["ActionBarVisibilityLabel"] or "Visibility"), { parentSection = expandable })
	if L["visibilityFrameExplain2"] then addon.functions.SettingsCreateText(category, L["visibilityFrameExplain2"], { parentSection = expandable }) end

	local frames = {}
	for _, info in ipairs(addon.variables.unitFrameNames or {}) do
		table.insert(frames, info)
	end
	table.sort(frames, function(a, b) return (a.text or a.name or "") < (b.text or b.name or "") end)

	for _, info in ipairs(frames) do
		if info.var and info.name then
			local exp = expandable
			local options = getFrameRuleOptions(info)
			if #options > 0 then
				local init = addon.functions.SettingsCreateMultiDropdown(category, {
					var = info.var .. "_visibility",
					text = info.text or info.name or info.var,
					options = options,
					isSelectedFunc = function(key)
						local cfg = NormalizeUnitFrameVisibilityConfig(info.var)
						return cfg and cfg[key] == true
					end,
					setSelectedFunc = function(key, shouldSelect) setFrameRule(info, key, shouldSelect) end,
					isEnabled = function()
						if not addon.Aura then return true end

						local db = addon.db.ufFrames
						if not db then return true end

						if info.name == "PlayerFrame" and db.player and db.player.enabled then
							return false
						elseif info.name == "TargetFrame" and db.target and db.target.enabled then
							return false
						end

						return true
					end,
					parentSection = exp,
				})
			end
		end
	end

	local function getFrameFadePercent()
		local value = GetFrameFadeStrength()
		if value < 0 then value = 0 end
		if value > 1 then value = 1 end
		return math.floor((value * 100) + 0.5)
	end

	addon.functions.SettingsCreateSlider(category, {
		var = "frameVisibilityFadeStrength",
		text = L["frameFadeStrength"] or "Fade amount",
		desc = L["frameFadeStrengthDesc"],
		min = 0,
		max = 100,
		step = 1,
		default = 100,
		get = getFrameFadePercent,
		set = function(val)
			local pct = tonumber(val) or 0
			if pct < 0 then pct = 0 end
			if pct > 100 then pct = 100 end
			addon.db.frameVisibilityFadeStrength = pct / 100
			RefreshAllFrameVisibilityAlpha()
		end,
		parentSection = expandable,
	})

	createCooldownViewerDropdowns(category, expandable)
end

function addon.functions.initUIOptions() end

createActionBarCategory()
createFrameCategory()
