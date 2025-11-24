local addonName, addon = ...

local L = addon.L
local AceGUI = addon.AceGUI
local math = math
local ActionBarLabels = addon.ActionBarLabels
local constants = addon.constants or {}
local OPTIONS_FRAME_MIN_SCALE = constants.OPTIONS_FRAME_MIN_SCALE or 0.5
local OPTIONS_FRAME_MAX_SCALE = constants.OPTIONS_FRAME_MAX_SCALE or 2
local ACTION_BAR_FRAME_NAMES = constants.ACTION_BAR_FRAME_NAMES or {}
local ACTION_BAR_ANCHOR_ORDER = constants.ACTION_BAR_ANCHOR_ORDER or {}
local ACTION_BAR_ANCHOR_CONFIG = constants.ACTION_BAR_ANCHOR_CONFIG or {}
local DEFAULT_CHAT_BUBBLE_FONT_SIZE = _G.DEFAULT_CHAT_BUBBLE_FONT_SIZE or 13
local CHAT_BUBBLE_FONT_MIN = _G.CHAT_BUBBLE_FONT_MIN or 1
local CHAT_BUBBLE_FONT_MAX = _G.CHAT_BUBBLE_FONT_MAX or 36

local function setCVarValue(...)
	if addon.functions and addon.functions.setCVarValue then return addon.functions.setCVarValue(...) end
end

local noop = function() end
local NormalizeActionBarVisibilityConfig = (addon.functions and addon.functions.NormalizeActionBarVisibilityConfig) or noop
local UpdateActionBarMouseover = (addon.functions and addon.functions.UpdateActionBarMouseover) or noop
local RefreshAllActionBarAnchors = (addon.functions and addon.functions.RefreshAllActionBarAnchors) or noop
local NormalizeUnitFrameVisibilityConfig = (addon.functions and addon.functions.NormalizeUnitFrameVisibilityConfig) or noop
local UpdateUnitFrameMouseover = (addon.functions and addon.functions.UpdateUnitFrameMouseover) or noop
local ApplyUnitFrameSettingByVar = (addon.functions and addon.functions.ApplyUnitFrameSettingByVar) or noop
local GetVisibilityRuleMetadata = (addon.functions and addon.functions.GetVisibilityRuleMetadata) or function() return {} end
local setLeaderIcon = (addon.functions and addon.functions.setLeaderIcon) or noop
local removeLeaderIcon = (addon.functions and addon.functions.removeLeaderIcon) or noop

local function buildActionBarExtras(parent)
	if not parent then return end

	local anchorSection
	local anchorDropdownContainer
	local anchorOptions = {
		TOPLEFT = L["topLeft"] or "Top Left",
		TOPRIGHT = L["topRight"] or "Top Right",
		BOTTOMLEFT = L["bottomLeft"] or "Bottom Left",
		BOTTOMRIGHT = L["bottomRight"] or "Bottom Right",
	}

	local function rebuildAnchorDropdowns()
		if not anchorDropdownContainer then return end
		anchorDropdownContainer:ReleaseChildren()
		anchorDropdownContainer:SetLayout("Flow")
		for index = 1, #ACTION_BAR_FRAME_NAMES do
			local label = L["actionBarAnchorDropdown"] and string.format(L["actionBarAnchorDropdown"], index) or string.format("Action Bar %d button anchor", index)
			local dropdown = addon.functions.createDropdownAce(label, anchorOptions, ACTION_BAR_ANCHOR_ORDER, function(_, _, key)
				if not ACTION_BAR_ANCHOR_CONFIG[key] then return end
				addon.db["actionBarAnchor" .. index] = key
				RefreshAllActionBarAnchors()
			end)
			local currentValue = addon.db["actionBarAnchor" .. index]
			if not currentValue or not ACTION_BAR_ANCHOR_CONFIG[currentValue] then currentValue = addon.db["actionBarAnchorDefault" .. index] end
			if not currentValue or not ACTION_BAR_ANCHOR_CONFIG[currentValue] then currentValue = ACTION_BAR_ANCHOR_ORDER and ACTION_BAR_ANCHOR_ORDER[1] end
			if currentValue then dropdown:SetValue(currentValue) end
			dropdown:SetDisabled(not addon.db["actionBarAnchorEnabled"])
			if dropdown.SetRelativeWidth then dropdown:SetRelativeWidth(0.5) end
			anchorDropdownContainer:AddChild(dropdown)
		end
		if anchorDropdownContainer.DoLayout then anchorDropdownContainer:DoLayout() end
		if anchorSection and anchorSection.DoLayout then anchorSection:DoLayout() end
	end

	anchorSection = addon.functions.createContainer("InlineGroup", "List")
	anchorSection:SetTitle(L["actionBarAnchorSectionTitle"] or "Button growth")
	anchorSection:SetFullWidth(true)
	parent:AddChild(anchorSection)

	local anchorToggle = addon.functions.createCheckboxAce(L["actionBarAnchorEnable"] or "Modify Action Bar anchor", addon.db["actionBarAnchorEnabled"] == true, function(_, _, value)
		addon.db["actionBarAnchorEnabled"] = value and true or false
		RefreshAllActionBarAnchors()
		rebuildAnchorDropdowns()
	end, L["actionBarAnchorEnableDesc"])
	anchorSection:AddChild(anchorToggle)

	anchorDropdownContainer = addon.functions.createContainer("SimpleGroup", "Flow")
	anchorDropdownContainer:SetFullWidth(true)
	anchorSection:AddChild(anchorDropdownContainer)
	rebuildAnchorDropdowns()

	parent:AddChild(addon.functions.createSpacerAce())

	local LSM = LibStub("LibSharedMedia-3.0", true)
	local function buildFontDropdownData()
		local map = {
			[addon.variables.defaultFont] = L["actionBarFontDefault"] or "Blizzard Font",
		}
		if LSM and LSM.HashTable then
			for name, path in pairs(LSM:HashTable("font") or {}) do
				if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
			end
		end
		return addon.functions.prepareListForDropdown(map)
	end

	local outlineMap = {
		NONE = L["fontOutlineNone"] or NONE,
		OUTLINE = L["fontOutlineThin"] or "Outline",
		THICKOUTLINE = L["fontOutlineThick"] or "Thick Outline",
		MONOCHROMEOUTLINE = L["fontOutlineMono"] or "Monochrome Outline",
	}
	local outlineOrder = { "NONE", "OUTLINE", "THICKOUTLINE", "MONOCHROMEOUTLINE" }

	local labelGroup = addon.functions.createContainer("InlineGroup", "List")
	labelGroup:SetTitle(L["actionBarLabelGroupTitle"] or "Button text")
	labelGroup:SetFullWidth(true)
	parent:AddChild(labelGroup)

	local fontList, fontOrder = buildFontDropdownData()
	local macroControls, hotkeyControls = {}, {}
	local cbHideMacroNames, macroOverrideCheckbox, hotkeyOverrideCheckbox

	local function updateLabelControlStates()
		local hideMacros = addon.db["hideMacroNames"] == true
		local macroOverrideEnabled = addon.db.actionBarMacroFontOverride == true and not hideMacros
		local hotkeyOverrideEnabled = addon.db.actionBarHotkeyFontOverride == true

		if macroOverrideCheckbox then macroOverrideCheckbox:SetDisabled(hideMacros) end
		for _, widget in ipairs(macroControls) do
			if widget and widget.SetDisabled then widget:SetDisabled(not macroOverrideEnabled) end
		end
		for _, widget in ipairs(hotkeyControls) do
			if widget and widget.SetDisabled then widget:SetDisabled(not hotkeyOverrideEnabled) end
		end
	end

	cbHideMacroNames = addon.functions.createCheckboxAce(L["hideMacroNames"], addon.db["hideMacroNames"], function(_, _, value)
		addon.db["hideMacroNames"] = value
		updateLabelControlStates()
		if ActionBarLabels and ActionBarLabels.RefreshAllMacroNameVisibility then ActionBarLabels.RefreshAllMacroNameVisibility() end
	end, L["hideMacroNamesDesc"])
	labelGroup:AddChild(cbHideMacroNames)

	macroOverrideCheckbox = addon.functions.createCheckboxAce(L["actionBarMacroFontOverride"] or "Change macro font", addon.db.actionBarMacroFontOverride == true, function(_, _, value)
		addon.db.actionBarMacroFontOverride = value and true or false
		updateLabelControlStates()
		if ActionBarLabels and ActionBarLabels.RefreshAllMacroNameVisibility then ActionBarLabels.RefreshAllMacroNameVisibility() end
		if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
	end)
	labelGroup:AddChild(macroOverrideCheckbox)

	local macroFontRow = addon.functions.createContainer("SimpleGroup", "Flow")
	macroFontRow:SetFullWidth(true)
	local macroFont = addon.functions.createDropdownAce(L["actionBarMacroFontLabel"] or "Macro name font", fontList, fontOrder, function(_, _, key)
		addon.db.actionBarMacroFontFace = key
		if ActionBarLabels and ActionBarLabels.RefreshAllMacroNameVisibility then ActionBarLabels.RefreshAllMacroNameVisibility() end
		if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
	end)
	local macroFaceValue = addon.db.actionBarMacroFontFace or addon.variables.defaultFont
	if not fontList[macroFaceValue] then macroFaceValue = addon.variables.defaultFont end
	macroFont:SetValue(macroFaceValue)
	macroFont:SetFullWidth(false)
	macroFont:SetRelativeWidth(0.6)
	macroFontRow:AddChild(macroFont)
	table.insert(macroControls, macroFont)

	local macroOutline = addon.functions.createDropdownAce(L["actionBarFontOutlineLabel"] or "Font outline", outlineMap, outlineOrder, function(_, _, key)
		addon.db.actionBarMacroFontOutline = key
		if ActionBarLabels and ActionBarLabels.RefreshAllMacroNameVisibility then ActionBarLabels.RefreshAllMacroNameVisibility() end
		if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
	end)
	macroOutline:SetValue(addon.db.actionBarMacroFontOutline or "OUTLINE")
	macroOutline:SetFullWidth(false)
	macroOutline:SetRelativeWidth(0.4)
	macroFontRow:AddChild(macroOutline)
	table.insert(macroControls, macroOutline)
	labelGroup:AddChild(macroFontRow)

	local macroSizeValue = math.floor((addon.db.actionBarMacroFontSize or 12) + 0.5)
	local macroSizeLabel = (L["actionBarMacroFontSize"] or "Macro font size") .. ": " .. macroSizeValue
	local macroSizeSlider = addon.functions.createSliderAce(macroSizeLabel, macroSizeValue, 8, 24, 1, function(self, _, val)
		local value = math.floor(val + 0.5)
		addon.db.actionBarMacroFontSize = value
		self:SetLabel((L["actionBarMacroFontSize"] or "Macro font size") .. ": " .. value)
		if ActionBarLabels and ActionBarLabels.RefreshAllMacroNameVisibility then ActionBarLabels.RefreshAllMacroNameVisibility() end
		if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
	end)
	table.insert(macroControls, macroSizeSlider)
	labelGroup:AddChild(macroSizeSlider)

	hotkeyOverrideCheckbox = addon.functions.createCheckboxAce(L["actionBarHotkeyFontOverride"] or "Change keybind font", addon.db.actionBarHotkeyFontOverride == true, function(_, _, value)
		addon.db.actionBarHotkeyFontOverride = value and true or false
		updateLabelControlStates()
		if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyVisibility then ActionBarLabels.RefreshAllHotkeyVisibility() end
		if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
	end)
	labelGroup:AddChild(hotkeyOverrideCheckbox)

	local hotkeyFontRow = addon.functions.createContainer("SimpleGroup", "Flow")
	hotkeyFontRow:SetFullWidth(true)
	local hotkeyFont = addon.functions.createDropdownAce(L["actionBarHotkeyFontLabel"] or "Hotkey font", fontList, fontOrder, function(_, _, key)
		addon.db.actionBarHotkeyFontFace = key
		if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyVisibility then ActionBarLabels.RefreshAllHotkeyVisibility() end
		if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
	end)
	local hotkeyFaceValue = addon.db.actionBarHotkeyFontFace or addon.variables.defaultFont
	if not fontList[hotkeyFaceValue] then hotkeyFaceValue = addon.variables.defaultFont end
	hotkeyFont:SetValue(hotkeyFaceValue)
	hotkeyFont:SetFullWidth(false)
	hotkeyFont:SetRelativeWidth(0.6)
	hotkeyFontRow:AddChild(hotkeyFont)
	table.insert(hotkeyControls, hotkeyFont)

	local hotkeyOutline = addon.functions.createDropdownAce(L["actionBarFontOutlineLabel"] or "Font outline", outlineMap, outlineOrder, function(_, _, key)
		addon.db.actionBarHotkeyFontOutline = key
		if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyVisibility then ActionBarLabels.RefreshAllHotkeyVisibility() end
		if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
	end)
	hotkeyOutline:SetValue(addon.db.actionBarHotkeyFontOutline or "OUTLINE")
	hotkeyOutline:SetFullWidth(false)
	hotkeyOutline:SetRelativeWidth(0.4)
	hotkeyFontRow:AddChild(hotkeyOutline)
	table.insert(hotkeyControls, hotkeyOutline)
	labelGroup:AddChild(hotkeyFontRow)

	local hotkeySizeValue = math.floor((addon.db.actionBarHotkeyFontSize or 12) + 0.5)
	local hotkeySizeLabel = (L["actionBarHotkeyFontSize"] or "Hotkey font size") .. ": " .. hotkeySizeValue
	local hotkeySizeSlider = addon.functions.createSliderAce(hotkeySizeLabel, hotkeySizeValue, 8, 24, 1, function(self, _, val)
		local value = math.floor(val + 0.5)
		addon.db.actionBarHotkeyFontSize = value
		self:SetLabel((L["actionBarHotkeyFontSize"] or "Hotkey font size") .. ": " .. value)
		if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyVisibility then ActionBarLabels.RefreshAllHotkeyVisibility() end
		if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
	end)
	table.insert(hotkeyControls, hotkeySizeSlider)
	labelGroup:AddChild(hotkeySizeSlider)

	local keybindVisibilityHeader = addon.functions.createLabelAce(L["actionBarKeybindVisibilityHeader"] or "Keybind label visibility", nil, nil, 12)
	keybindVisibilityHeader:SetFullWidth(true)
	labelGroup:AddChild(keybindVisibilityHeader)

	local keybindVisibilityContainer = addon.functions.createContainer("SimpleGroup", "Flow")
	keybindVisibilityContainer:SetFullWidth(true)
	labelGroup:AddChild(keybindVisibilityContainer)

	for _, cbData in ipairs(addon.variables.actionBarNames) do
		local cb = addon.functions.createCheckboxAce(cbData.text, addon.db["hideKeybindLabel_" .. cbData.name], function(_, _, value)
			addon.db["hideKeybindLabel_" .. cbData.name] = value and true or false
			if ActionBarLabels and ActionBarLabels.ApplySingleHotkeyVisibility then ActionBarLabels.ApplySingleHotkeyVisibility(cbData.name) end
		end)
		cb:SetRelativeWidth(0.33)
		keybindVisibilityContainer:AddChild(cb)
		table.insert(hotkeyControls, cb)
	end

	local shortHotkeys = addon.functions.createCheckboxAce(L["actionBarShortHotkeys"] or "Shorten keybind text", addon.db.actionBarShortHotkeys == true, function(_, _, value)
		addon.db.actionBarShortHotkeys = value and true or false
		if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
	end, L["actionBarShortHotkeysDesc"])
	labelGroup:AddChild(shortHotkeys)

	local rangeOptionsGroup
	local function rebuildRangeOptions()
		if not rangeOptionsGroup then return end
		rangeOptionsGroup:ReleaseChildren()
		if addon.db["actionBarFullRangeColoring"] then
			local colorPicker = AceGUI:Create("ColorPicker")
			colorPicker:SetLabel(L["rangeOverlayColor"])
			local c = addon.db["actionBarFullRangeColor"]
			colorPicker:SetColor(c.r, c.g, c.b)
			colorPicker:SetCallback("OnValueChanged", function(_, _, r, g, b)
				addon.db["actionBarFullRangeColor"] = { r = r, g = g, b = b }
				if ActionBarLabels and ActionBarLabels.RefreshAllRangeOverlays then ActionBarLabels.RefreshAllRangeOverlays() end
			end)
			rangeOptionsGroup:AddChild(colorPicker)

			local alphaPercent = math.floor((addon.db["actionBarFullRangeAlpha"] or 0.35) * 100)
			local sliderAlpha = addon.functions.createSliderAce(L["rangeOverlayAlpha"] .. ": " .. alphaPercent .. "%", alphaPercent, 1, 100, 1, function(self, _, val)
				addon.db["actionBarFullRangeAlpha"] = val / 100
				self:SetLabel(L["rangeOverlayAlpha"] .. ": " .. val .. "%")
				if ActionBarLabels and ActionBarLabels.RefreshAllRangeOverlays then ActionBarLabels.RefreshAllRangeOverlays() end
			end)
			rangeOptionsGroup:AddChild(sliderAlpha)
		end
		if rangeOptionsGroup.DoLayout then rangeOptionsGroup:DoLayout() end
	end

	local cbRange = addon.functions.createCheckboxAce(L["fullButtonRangeColoring"], addon.db["actionBarFullRangeColoring"], function(_, _, value)
		addon.db["actionBarFullRangeColoring"] = value
		if ActionBarLabels and ActionBarLabels.RefreshAllRangeOverlays then ActionBarLabels.RefreshAllRangeOverlays() end
		rebuildRangeOptions()
	end, L["fullButtonRangeColoringDesc"])
	labelGroup:AddChild(cbRange)

	rangeOptionsGroup = addon.functions.createContainer("SimpleGroup", "List")
	rangeOptionsGroup:SetFullWidth(true)
	labelGroup:AddChild(rangeOptionsGroup)

	rebuildRangeOptions()

	local perBarGroup = addon.functions.createContainer("InlineGroup", "Flow")
	perBarGroup:SetTitle(L["actionBarHideHotkeysGroup"] or "Hide keybinds per bar")
	perBarGroup:SetFullWidth(true)
	labelGroup:AddChild(perBarGroup)

	for _, cbData in ipairs(addon.variables.actionBarNames or {}) do
		if cbData.name then
			local checkbox = addon.functions.createCheckboxAce(cbData.text or cbData.name, addon.db.actionBarHiddenHotkeys[cbData.name] == true, function(_, _, value)
				if value then
					addon.db.actionBarHiddenHotkeys[cbData.name] = true
				else
					addon.db.actionBarHiddenHotkeys[cbData.name] = nil
				end
				if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
			end, L["actionBarHideHotkeysDesc"])
			checkbox:SetFullWidth(false)
			if checkbox.SetRelativeWidth then checkbox:SetRelativeWidth(0.5) end
			perBarGroup:AddChild(checkbox)
		end
	end

	labelGroup:AddChild(addon.functions.createSpacerAce())

	updateLabelControlStates()
end

local function addVisibilityHub(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local function requestLayout()
		if wrapper and wrapper.DoLayout then wrapper:DoLayout() end
		if scroll and scroll.DoLayout then scroll:DoLayout() end
	end

	local introTemplate = L["visibilityHubIntro"]
	if not introTemplate and L["ActionbarVisibilityExplain"] then
		introTemplate = L["ActionbarVisibilityExplain"]:format(_G["HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_ALWAYS"], _G["HUD_EDIT_MODE_MENU"])
	end
	introTemplate = introTemplate or ""
	local intro = addon.functions.createLabelAce("|cffffd700" .. introTemplate .. "|r", nil, nil, 12)
	intro:SetFullWidth(true)
	wrapper:AddChild(intro)
	wrapper:AddChild(addon.functions.createSpacerAce())

	local selectorsGroup = addon.functions.createContainer("InlineGroup", "Flow")
	selectorsGroup:SetTitle(L["visibilitySelectorsTitle"] or L["visibilityKindLabel"] or "Selection")
	selectorsGroup:SetFullWidth(true)
	wrapper:AddChild(selectorsGroup)

	local kindOptions = {
		actionbar = L["visibilityKindActionBars"] or ACTIONBARS_LABEL,
		frame = L["visibilityKindFrames"] or UNITFRAME_LABEL,
	}
	local kindOrder = { "actionbar", "frame" }

	addon.db.visibilityHubSelection = addon.db.visibilityHubSelection or {}
	local selectionStore = addon.db.visibilityHubSelection
	local state = { kind = addon.db.visibilityHubKind or "actionbar" }
	if kindOptions[state.kind] == nil then state.kind = "actionbar" end
	addon.db.visibilityHubKind = state.kind

	local elementDropdown
	local currentElementKey
	local currentElement
	local elementLookup = {}
	local visibilityRules = GetVisibilityRuleMetadata() or {}
	local rebuildScenarioGroup
	local rebuildExtrasGroup
	local updateRuleSelection

	local function getElementsForKind(kind)
		local source = kind == "actionbar" and addon.variables.actionBarNames or addon.variables.unitFrameNames
		local list, order, lookup = {}, {}, {}
		for _, entry in ipairs(source) do
			local key = entry.var or entry.name
			if key then
				local label = entry.text or entry.name or key
				list[key] = label
				table.insert(order, key)
				lookup[key] = entry
			end
		end
		table.sort(order, function(a, b)
			local la = list[a] or a
			local lb = list[b] or b
			return la < lb
		end)
		return list, order, lookup
	end

	local function getRulesForCurrentElement()
		local active = {}
		for key, data in pairs(visibilityRules) do
			local allowed = data.appliesTo and data.appliesTo[state.kind]
			if allowed and data.unitRequirement and currentElement then
				if currentElement.unitToken ~= data.unitRequirement then allowed = false end
			end
			if allowed then table.insert(active, data) end
		end
		table.sort(active, function(a, b)
			local oa = a.order or 999
			local ob = b.order or 999
			if oa == ob then return (a.label or a.key) < (b.label or b.key) end
			return oa < ob
		end)
		return active
	end

	local scenarioGroup = addon.functions.createContainer("InlineGroup", "List")
	scenarioGroup:SetTitle(L["visibilityScenarioGroupTitle"] or L["ActionBarVisibilityLabel"] or "Visibility")
	scenarioGroup:SetFullWidth(true)
	wrapper:AddChild(scenarioGroup)

	local extrasGroup = addon.functions.createContainer("InlineGroup", "List")
	extrasGroup:SetFullWidth(true)
	wrapper:AddChild(extrasGroup)

	local function getCurrentConfig()
		if not currentElement or not currentElement.var then return nil end
		if state.kind == "actionbar" then
			return NormalizeActionBarVisibilityConfig(currentElement.var)
		else
			return NormalizeUnitFrameVisibilityConfig(currentElement.var)
		end
	end

	rebuildExtrasGroup = function()
		extrasGroup:ReleaseChildren()
		if state.kind == "actionbar" then
			buildActionBarExtras(extrasGroup)
		else
			local note = addon.functions.createLabelAce(L["visibilityFrameExtrasNote"] or "", nil, nil, 12)
			note:SetFullWidth(true)
			extrasGroup:AddChild(note)
		end
		requestLayout()
	end

	updateRuleSelection = function(ruleKey, checked)
		if not currentElement or not currentElement.var then return end
		local working = addon.db[currentElement.var]
		if type(working) ~= "table" then working = {} end
		if checked then
			working[ruleKey] = true
		else
			working[ruleKey] = nil
		end
		if state.kind == "actionbar" then
			local normalized = NormalizeActionBarVisibilityConfig(currentElement.var, working)
			UpdateActionBarMouseover(currentElement.name, normalized, currentElement.var)
		else
			NormalizeUnitFrameVisibilityConfig(currentElement.var, working)
			UpdateUnitFrameMouseover(currentElement.name, currentElement)
		end
		rebuildScenarioGroup()
		rebuildExtrasGroup()
		requestLayout()
		return true
	end

	rebuildScenarioGroup = function()
		scenarioGroup:ReleaseChildren()
		scenarioGroup:SetTitle(L["visibilityScenarioGroupTitle"] or L["ActionBarVisibilityLabel"] or "Visibility")
		if not currentElement then
			local emptyLabel = addon.functions.createLabelAce(L["visibilityNoElement"] or "", nil, nil, 12)
			emptyLabel:SetFullWidth(true)
			scenarioGroup:AddChild(emptyLabel)
			requestLayout()
			return
		end
		local explain
		if state.kind == "actionbar" and L["ActionbarVisibilityExplain"] then
			explain = L["ActionbarVisibilityExplain"]:format(_G["HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_ALWAYS"], _G["HUD_EDIT_MODE_MENU"])
		elseif state.kind == "frame" then
			explain = L["visibilityFrameExplain"] or L["UnitFrameHideExplain"]
		end
		if explain then
			local lbl = addon.functions.createLabelAce("|cffffd700" .. explain .. "|r", nil, nil, 12)
			lbl:SetFullWidth(true)
			scenarioGroup:AddChild(lbl)
			scenarioGroup:AddChild(addon.functions.createSpacerAce())
		end
		local config = getCurrentConfig() or {}
		local groupedRuleActive = config.ALWAYS_HIDE_IN_GROUP == true
		local rules = getRulesForCurrentElement()
		if #rules == 0 then
			local none = addon.functions.createLabelAce(L["visibilityNoRules"] or "", nil, nil, 12)
			none:SetFullWidth(true)
			scenarioGroup:AddChild(none)
			requestLayout()
			return
		end
		local disableOthers = config.ALWAYS_HIDDEN == true
		for _, rule in ipairs(rules) do
			local value = config and config[rule.key] == true
			local cb = addon.functions.createCheckboxAce(rule.label or rule.key or "", value, function(_, _, checked) updateRuleSelection(rule.key, checked) end, rule.description)
			if cb.SetFullWidth then
				cb:SetFullWidth(true)
			else
				cb:SetRelativeWidth(1.0)
			end
			if disableOthers and rule.key ~= "ALWAYS_HIDDEN" then cb:SetDisabled(true) end
			scenarioGroup:AddChild(cb)
		end
		if disableOthers then
			local warn = addon.functions.createLabelAce(L["visibilityAlwaysHiddenActive"] or "", nil, nil, 10)
			warn:SetFullWidth(true)
			scenarioGroup:AddChild(addon.functions.createSpacerAce())
			scenarioGroup:AddChild(warn)
		elseif groupedRuleActive then
			local warn = addon.functions.createLabelAce(
				L["visibilityHideInGroupActive"]
					or 'When you are in a party or raid, only "Always hide in party/raid" (and Mouseover, if enabled) is evaluated; other visibility rules are ignored while grouped.',
				nil,
				nil,
				10
			)
			warn:SetFullWidth(true)
			scenarioGroup:AddChild(addon.functions.createSpacerAce())
			scenarioGroup:AddChild(warn)
		end
		requestLayout()
	end

	local function rebuildElementDropdown()
		local list, order, lookup = getElementsForKind(state.kind)
		elementLookup = lookup
		local desired = selectionStore[state.kind]
		if not desired or not elementLookup[desired] then desired = order[1] end
		selectionStore[state.kind] = desired
		currentElementKey = desired
		currentElement = desired and elementLookup[desired] or nil
		elementDropdown:SetList(list, order)
		elementDropdown:SetDisabled(#order == 0)
		if desired then
			elementDropdown:SetValue(desired)
		else
			elementDropdown:SetValue(nil)
		end
		rebuildScenarioGroup()
		rebuildExtrasGroup()
		requestLayout()
	end

	local kindDropdown = AceGUI:Create("Dropdown")
	kindDropdown:SetLabel(L["visibilityKindLabel"] or L["visibilitySelectorsTitle"] or "Category")
	kindDropdown:SetList(kindOptions, kindOrder)
	kindDropdown:SetValue(state.kind)
	kindDropdown:SetRelativeWidth(0.5)
	kindDropdown:SetCallback("OnValueChanged", function(_, _, key)
		if not kindOptions[key] or state.kind == key then return end
		state.kind = key
		addon.db.visibilityHubKind = key
		rebuildElementDropdown()
	end)
	selectorsGroup:AddChild(kindDropdown)

	elementDropdown = AceGUI:Create("Dropdown")
	elementDropdown:SetLabel(L["visibilityElementLabel"] or UNITFRAME_LABEL)
	elementDropdown:SetRelativeWidth(0.5)
	elementDropdown:SetCallback("OnValueChanged", function(_, _, key)
		if key == currentElementKey then return end
		selectionStore[state.kind] = key
		currentElementKey = key
		currentElement = key and elementLookup[key] or nil
		rebuildScenarioGroup()
		rebuildExtrasGroup()
	end)
	selectorsGroup:AddChild(elementDropdown)

	rebuildElementDropdown()
end

local function addUnitFrame2(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)
	local function doLayout()
		if scroll and scroll.DoLayout then scroll:DoLayout() end
	end
	wrapper:PauseLayout()

	local groups = {}

	local function ensureGroup(key, title)
		local g, known
		if groups[key] then
			g = groups[key]
			groups[key]:PauseLayout()
			groups[key]:ReleaseChildren()
			known = true
		else
			g = addon.functions.createContainer("InlineGroup", "List")
			g:SetTitle(title)
			wrapper:AddChild(g)
			groups[key] = g
		end

		return g, known
	end

	local function buildHitIndicator()
		local g, known = ensureGroup("hit", COMBAT_TEXT_LABEL)
		local data = {
			{
				var = "hideHitIndicatorPlayer",
				text = L["hideHitIndicatorPlayer"],
				func = function(_, _, value)
					addon.db["hideHitIndicatorPlayer"] = value
					if value then
						PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator:Hide()
					else
						PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator:Show()
					end
				end,
			},
			{
				var = "hideHitIndicatorPet",
				text = L["hideHitIndicatorPet"],
				func = function(_, _, value)
					addon.db["hideHitIndicatorPet"] = value
					if value and PetHitIndicator then PetHitIndicator:Hide() end
				end,
			},
		}
		table.sort(data, function(a, b) return a.text < b.text end)
		for _, cb in ipairs(data) do
			local w = addon.functions.createCheckboxAce(cb.text, addon.db[cb.var], cb.func)
			g:AddChild(w)
		end
		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildCore()
		local g, known = ensureGroup("core", "")
		g:SetLayout("Flow")
		local labelHeadline = addon.functions.createLabelAce("|cffffd700" .. (L["visibilityUnitFrameRedirect"] or L["UnitFrameHideExplain"]) .. "|r", nil, nil, 14)
		labelHeadline:SetFullWidth(true)
		g:AddChild(labelHeadline)
		g:AddChild(addon.functions.createSpacerAce())
		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildHealthText()
		local g, known = ensureGroup("healthText", L["Health Text"] or "Health Text")
		g:SetLayout("Flow")

		local list = { OFF = VIDEO_OPTIONS_DISABLED, PERCENT = STATUS_TEXT_PERCENT, ABS = STATUS_TEXT_VALUE, BOTH = STATUS_TEXT_BOTH }
		local order = { "OFF", "PERCENT", "ABS", "BOTH" }

		local htExplainText =
			string.format(L["HealthTextExplain"] or "%s follows Blizzard 'Status Text'. Any other mode shows your chosen format for Player, Target, and Boss frames.", VIDEO_OPTIONS_DISABLED)
		local lbl = addon.functions.createLabelAce("|cffffd700" .. htExplainText .. "|r", nil, nil, 10)
		lbl:SetFullWidth(true)
		g:AddChild(lbl)

		local dp = AceGUI:Create("Dropdown")
		dp:SetLabel(L["PlayerHealthText"] or "Player health text")
		dp:SetList(list, order)
		dp:SetValue(addon.db and addon.db["healthTextPlayerMode"] or "OFF")
		dp:SetRelativeWidth(0.33)
		dp:SetCallback("OnValueChanged", function(_, _, key)
			addon.db["healthTextPlayerMode"] = key or "OFF"
			if addon.HealthText and addon.HealthText.SetMode then addon.HealthText:SetMode("player", addon.db["healthTextPlayerMode"]) end
		end)
		g:AddChild(dp)

		local dt = AceGUI:Create("Dropdown")
		dt:SetLabel(L["TargetHealthText"] or "Target health text")
		dt:SetList(list, order)
		dt:SetValue(addon.db and addon.db["healthTextTargetMode"] or "OFF")
		dt:SetRelativeWidth(0.33)
		dt:SetCallback("OnValueChanged", function(_, _, key)
			addon.db["healthTextTargetMode"] = key or "OFF"
			if addon.HealthText and addon.HealthText.SetMode then addon.HealthText:SetMode("target", addon.db["healthTextTargetMode"]) end
		end)
		g:AddChild(dt)

		local db = AceGUI:Create("Dropdown")
		db:SetLabel(L["BossHealthText"] or "Boss health text")
		db:SetList(list, order)
		db:SetValue(addon.db and (addon.db["healthTextBossMode"] or addon.db["bossHealthMode"]) or "OFF")
		db:SetRelativeWidth(0.33)
		db:SetCallback("OnValueChanged", function(_, _, key)
			addon.db["healthTextBossMode"] = key or "OFF"
			if addon.HealthText and addon.HealthText.SetMode then addon.HealthText:SetMode("boss", addon.db["healthTextBossMode"]) end
		end)
		g:AddChild(db)

		-- OFF = obey Blizzard CVar, others override; no extra toggles

		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildCoreUF()
		local g, known = ensureGroup("coreUF", "")
		local labelHeadlineUF = addon.functions.createLabelAce("|cffffd700" .. (L["UnitFrameUFExplain"]:format(_G.RAID or "RAID", _G.PARTY or "Party", _G.PLAYER or "Player")) .. "|r", nil, nil, 14)
		labelHeadlineUF:SetFullWidth(true)
		g:AddChild(labelHeadlineUF)
		g:AddChild(addon.functions.createSpacerAce())

		local cbLeader = addon.functions.createCheckboxAce(L["showLeaderIconRaidFrame"], addon.db["showLeaderIconRaidFrame"], function(_, _, value)
			addon.db["showLeaderIconRaidFrame"] = value
			if value then
				setLeaderIcon()
			else
				removeLeaderIcon()
			end
		end)
		g:AddChild(cbLeader)

		if not addon.variables.isMidnight then
			local cbSolo = addon.functions.createCheckboxAce(L["showPartyFrameInSoloContent"], addon.db["showPartyFrameInSoloContent"], function(_, _, value)
				addon.db["showPartyFrameInSoloContent"] = value
				addon.variables.requireReload = true
				buildCoreUF()
				ApplyUnitFrameSettingByVar("unitframeSettingPlayerFrame")
				addon.functions.togglePartyFrameTitle(addon.db["hidePartyFrameTitle"])
			end)
			g:AddChild(cbSolo)
		end

		local cbTitle = addon.functions.createCheckboxAce(L["hidePartyFrameTitle"], addon.db["hidePartyFrameTitle"], function(_, _, value)
			addon.db["hidePartyFrameTitle"] = value
			addon.functions.togglePartyFrameTitle(value)
		end)
		g:AddChild(cbTitle)

		-- Hide resting animation and glow on the Player frame
		local cbRest = addon.functions.createCheckboxAce(L["hideRestingGlow"] or "Hide resting animation and glow", addon.db["hideRestingGlow"], function(_, _, value)
			addon.db["hideRestingGlow"] = value
			if addon.functions.ApplyRestingVisuals then addon.functions.ApplyRestingVisuals() end
		end, L["hideRestingGlowDesc"] or "Removes the 'ZZZ' status texture and the resting glow on the player frame while resting.")
		g:AddChild(cbRest)

		local sliderName
		local cbTrunc = addon.functions.createCheckboxAce(L["unitFrameTruncateNames"], addon.db.unitFrameTruncateNames, function(_, _, v)
			addon.db.unitFrameTruncateNames = v
			if sliderName then sliderName:SetDisabled(not v) end
			addon.functions.updateUnitFrameNames()
		end)
		g:AddChild(cbTrunc)

		sliderName = addon.functions.createSliderAce(L["unitFrameMaxNameLength"] .. ": " .. addon.db.unitFrameMaxNameLength, addon.db.unitFrameMaxNameLength, 1, 20, 1, function(self, _, val)
			addon.db.unitFrameMaxNameLength = val
			self:SetLabel(L["unitFrameMaxNameLength"] .. ": " .. val)
			addon.functions.updateUnitFrameNames()
		end)
		sliderName:SetDisabled(not addon.db.unitFrameTruncateNames)
		g:AddChild(sliderName)

		local sliderScale
		local cbScale = addon.functions.createCheckboxAce(L["unitFrameScaleEnable"], addon.db.unitFrameScaleEnabled, function(_, _, v)
			addon.db.unitFrameScaleEnabled = v
			if sliderScale then sliderScale:SetDisabled(not v) end
			if v then
				addon.functions.updatePartyFrameScale()
			else
				addon.variables.requireReload = true
				addon.functions.checkReloadFrame()
			end
		end)
		g:AddChild(cbScale)

		sliderScale = addon.functions.createSliderAce(L["unitFrameScale"] .. ": " .. addon.db.unitFrameScale, addon.db.unitFrameScale, 0.5, 2, 0.05, function(self, _, val)
			addon.db.unitFrameScale = val
			self:SetLabel(L["unitFrameScale"] .. ": " .. string.format("%.2f", val))
			addon.functions.updatePartyFrameScale()
		end)
		sliderScale:SetDisabled(not addon.db.unitFrameScaleEnabled)
		g:AddChild(sliderScale)

		g:AddChild(addon.functions.createSpacerAce())

		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildCast()
		local g, known = ensureGroup("cast", L["CastBars"] or "Cast Bars")
		local dd = AceGUI:Create("Dropdown")
		dd:SetLabel(L["castBarsToHide"] or "Cast bars to hide")
		local list = {
			PlayerCastingBarFrame = L["castBar_player"] or _G.PLAYER or "Player",
			TargetFrameSpellBar = L["castBar_target"] or TARGET or "Target",
			FocusFrameSpellBar = L["castBar_focus"] or FOCUS or "Focus",
		}
		local order = { "PlayerCastingBarFrame", "TargetFrameSpellBar", "FocusFrameSpellBar" }
		dd:SetList(list, order)
		dd:SetMultiselect(true)
		dd:SetFullWidth(true)
		dd:SetCallback("OnValueChanged", function(widget, _, key, checked)
			addon.db.hiddenCastBars = addon.db.hiddenCastBars or {}
			addon.db.hiddenCastBars[key] = checked and true or false
			addon.functions.ApplyCastBarVisibility()
		end)
		if type(addon.db.hiddenCastBars) == "table" then
			for k, v in pairs(addon.db.hiddenCastBars) do
				if v then dd:SetItemValue(k, true) end
			end
		end
		g:AddChild(dd)
		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	buildHitIndicator()
	buildCore()
	buildHealthText()
	buildCoreUF()
	buildCast()
	wrapper:ResumeLayout()
	doLayout()
end

local function buildDatapanelFrame(container)
	local DataPanel = addon.DataPanel
	local DataHub = addon.DataHub
	local panels = DataPanel.List()

	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	-- Panel management controls
	local controlGroup = addon.functions.createContainer("InlineGroup", "Flow")
	controlGroup:SetTitle(L["Panels"] or "Panels")
	wrapper:AddChild(controlGroup)

	addon.db = addon.db or {}
	addon.db.dataPanelsOptions = addon.db.dataPanelsOptions or {}

	local editModeHint = addon.functions.createLabelAce("|cffffd700" .. (L["DataPanelEditModeHint"] or "Configure DataPanels in Edit Mode.") .. "|r", nil, nil, 12)
	editModeHint:SetFullWidth(true)
	controlGroup:AddChild(editModeHint)

	local hintToggle = addon.functions.createCheckboxAce(L["Show options tooltip hint"], addon.DataPanel.ShouldShowOptionsHint and addon.DataPanel.ShouldShowOptionsHint(), function(_, _, val)
		if addon.DataPanel.SetShowOptionsHint then addon.DataPanel.SetShowOptionsHint(val and true or false) end
		for name in pairs(DataHub.streams) do
			DataHub:RequestUpdate(name)
		end
	end)
	hintToggle:SetRelativeWidth(1.0)
	controlGroup:AddChild(hintToggle)

	addon.db.dataPanelsOptions.menuModifier = addon.db.dataPanelsOptions.menuModifier or "NONE"
	local modifierList = {
		NONE = L["Context menu modifier: None"] or (NONE or "None"),
		SHIFT = SHIFT_KEY_TEXT or "Shift",
		CTRL = CTRL_KEY_TEXT or "Ctrl",
		ALT = ALT_KEY_TEXT or "Alt",
	}
	local modifierOrder = { "NONE", "SHIFT", "CTRL", "ALT" }
	local modifierDropdown = addon.functions.createDropdownAce(L["Context menu modifier"] or "Context menu modifier", modifierList, modifierOrder, function(widget, _, key)
		if addon.DataPanel.SetMenuModifier then addon.DataPanel.SetMenuModifier(key) end
		if widget and widget.SetValue then widget:SetValue(key) end
	end)
	if modifierDropdown.SetValue then modifierDropdown:SetValue(addon.DataPanel.GetMenuModifier and addon.DataPanel.GetMenuModifier() or "NONE") end
	modifierDropdown:SetRelativeWidth(1.0)
	controlGroup:AddChild(modifierDropdown)

	local newName = addon.functions.createEditboxAce(L["Panel Name"] or "Panel Name")
	newName:SetRelativeWidth(0.4)
	controlGroup:AddChild(newName)

	local addButton = addon.functions.createButtonAce(L["Add Panel"] or "Add Panel", 120, function()
		local id = newName:GetText()
		if id and id ~= "" then
			DataPanel.Create(id)
			container:ReleaseChildren()
			buildDatapanelFrame(container)
		end
	end)
	addButton:SetRelativeWidth(0.3)
	controlGroup:AddChild(addButton)

	scroll:DoLayout()
end

local TooltipUtil = _G.TooltipUtil

local function addSocialFrame(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "List")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)

	local data = {
		{
			parent = "",
			var = "blockDuelRequests",
			text = L["blockDuelRequests"],
			type = "CheckBox",
			callback = function(self, _, value) addon.db["blockDuelRequests"] = value end,
		},
		{
			parent = "",
			var = "blockPetBattleRequests",
			text = L["blockPetBattleRequests"],
			type = "CheckBox",
			callback = function(self, _, value) addon.db["blockPetBattleRequests"] = value end,
		},
		{
			parent = "",
			var = "blockPartyInvites",
			text = L["blockPartyInvites"],
			type = "CheckBox",
			callback = function(self, _, value) addon.db["blockPartyInvites"] = value end,
		},
		{
			parent = "",
			var = "enableIgnore",
			text = L["EnableAdvancedIgnore"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["enableIgnore"] = value
				if addon.Ignore and addon.Ignore.SetEnabled then addon.Ignore:SetEnabled(value) end
				container:ReleaseChildren()
				addSocialFrame(container)
			end,
		},
	}
	if addon.db["enableIgnore"] then
		table.insert(data, {
			parent = "",
			var = "ignoreAttachFriendsFrame",
			text = L["IgnoreAttachFriends"],
			desc = L["IgnoreAttachFriendsDesc"],
			type = "CheckBox",
			callback = function(self, _, value) addon.db["ignoreAttachFriendsFrame"] = value end,
		})
		table.insert(data, {
			parent = "",
			var = "ignoreAnchorFriendsFrame",
			text = L["IgnoreAnchorFriends"],
			desc = L["IgnoreAnchorFriendsDesc"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["ignoreAnchorFriendsFrame"] = value
				if addon.Ignore and addon.Ignore.UpdateAnchor then addon.Ignore:UpdateAnchor() end
			end,
		})
		table.insert(data, {
			parent = "",
			var = "ignoreTooltipNote",
			text = L["IgnoreTooltipNote"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["ignoreTooltipNote"] = value
				container:ReleaseChildren()
				addSocialFrame(container)
			end,
			desc = L["IgnoreNoteDesc"],
		})
	end

	table.sort(data, function(a, b)
		local textA = a.var
		local textB = b.var
		if a.text then
			textA = a.text
		else
			textA = L[a.var]
		end
		if b.text then
			textB = b.text
		else
			textB = L[b.var]
		end
		return textA < textB
	end)

	for _, checkboxData in ipairs(data) do
		local desc
		if checkboxData.desc then desc = checkboxData.desc end
		local cb = addon.functions.createCheckboxAce(checkboxData.text, addon.db[checkboxData.var], checkboxData.callback, desc)
		groupCore:AddChild(cb)
	end

	-- Inline section for auto-accept invites
	local groupInv = addon.functions.createContainer("InlineGroup", "List")
	groupInv:SetTitle(L["autoAcceptGroupInvite"]) -- Section title
	wrapper:AddChild(groupInv)

	local cbMain = addon.functions.createCheckboxAce(L["autoAcceptGroupInvite"], addon.db["autoAcceptGroupInvite"], function(self, _, value)
		addon.db["autoAcceptGroupInvite"] = value
		container:ReleaseChildren()
		addSocialFrame(container)
	end)
	groupInv:AddChild(cbMain)

	if addon.db["autoAcceptGroupInvite"] then
		local lbl = addon.functions.createLabelAce("|cffffd700" .. L["autoAcceptGroupInviteOptions"] .. "|r", nil, nil, 12)
		lbl:SetFullWidth(true)
		groupInv:AddChild(lbl)

		local cbGuild = addon.functions.createCheckboxAce(
			L["autoAcceptGroupInviteGuildOnly"],
			addon.db["autoAcceptGroupInviteGuildOnly"],
			function(self, _, value) addon.db["autoAcceptGroupInviteGuildOnly"] = value end
		)
		groupInv:AddChild(cbGuild)

		local cbFriends = addon.functions.createCheckboxAce(
			L["autoAcceptGroupInviteFriendOnly"],
			addon.db["autoAcceptGroupInviteFriendOnly"],
			function(self, _, value) addon.db["autoAcceptGroupInviteFriendOnly"] = value end
		)
		groupInv:AddChild(cbFriends)
	end

	local friendsDecorGroup = addon.functions.createContainer("InlineGroup", "List")
	friendsDecorGroup:SetTitle(L["friendsListDecorGroup"] or "Friends list enhancements")
	wrapper:AddChild(friendsDecorGroup)

	local friendsOptionsGroup
	local function rebuildFriendsDecorOptions()
		if not friendsOptionsGroup then return end
		friendsOptionsGroup:ReleaseChildren()
		if addon.db["friendsListDecorEnabled"] then
			local showLocation = addon.functions.createCheckboxAce(L["friendsListDecorShowLocation"] or "Show area and realm", addon.db["friendsListDecorShowLocation"] ~= false, function(_, _, value)
				addon.db["friendsListDecorShowLocation"] = value and true or false
				if addon.FriendsListDecor and addon.FriendsListDecor.Refresh then addon.FriendsListDecor:Refresh() end
			end)
			friendsOptionsGroup:AddChild(showLocation)

			local hideRealm = addon.functions.createCheckboxAce(L["friendsListDecorHideOwnRealm"] or "Hide your home realm", addon.db["friendsListDecorHideOwnRealm"] ~= false, function(_, _, value)
				addon.db["friendsListDecorHideOwnRealm"] = value and true or false
				if addon.FriendsListDecor and addon.FriendsListDecor.Refresh then addon.FriendsListDecor:Refresh() end
			end)
			friendsOptionsGroup:AddChild(hideRealm)

			local labelBase = L["friendsListDecorNameFontSize"] or "Friend name font size"
			local function fontSizeLabel(val)
				if val <= 0 then return DEFAULT or "Default" end
				return tostring(val)
			end
			local currentValue = addon.db["friendsListDecorNameFontSize"] or 0
			local sliderFont = addon.functions.createSliderAce(string.format("%s: %s", labelBase, fontSizeLabel(currentValue)), currentValue, 0, 24, 1, function(self, _, value)
				local rounded = math.floor((value or 0) + 0.5)
				if rounded > 0 and rounded < 8 then rounded = 8 end
				if rounded > 24 then rounded = 24 end
				addon.db["friendsListDecorNameFontSize"] = rounded
				self:SetLabel(string.format("%s: %s", labelBase, fontSizeLabel(rounded)))
				if rounded ~= value then self:SetValue(rounded) end
				if addon.FriendsListDecor and addon.FriendsListDecor.Refresh then addon.FriendsListDecor:Refresh() end
			end)
			friendsOptionsGroup:AddChild(sliderFont)
		end
		if friendsOptionsGroup.DoLayout then friendsOptionsGroup:DoLayout() end
		if friendsDecorGroup and friendsDecorGroup.DoLayout then friendsDecorGroup:DoLayout() end
		if groupCore and groupCore.DoLayout then groupCore:DoLayout() end
		if wrapper and wrapper.DoLayout then wrapper:DoLayout() end
		if scroll and scroll.DoLayout then scroll:DoLayout() end
	end

	local friendsToggle = addon.functions.createCheckboxAce(
		L["friendsListDecorEnabledLabel"] or L["friendsListDecorGroup"] or "Enhanced friends list styling",
		addon.db["friendsListDecorEnabled"] == true,
		function(_, _, value)
			addon.db["friendsListDecorEnabled"] = value and true or false
			if addon.FriendsListDecor and addon.FriendsListDecor.SetEnabled then addon.FriendsListDecor:SetEnabled(addon.db["friendsListDecorEnabled"]) end
			rebuildFriendsDecorOptions()
		end,
		L["friendsListDecorEnabledDesc"]
	)
	friendsDecorGroup:AddChild(friendsToggle)

	friendsOptionsGroup = addon.functions.createContainer("SimpleGroup", "List")
	friendsOptionsGroup:SetFullWidth(true)
	friendsDecorGroup:AddChild(friendsOptionsGroup)
	rebuildFriendsDecorOptions()

	if addon.db["ignoreTooltipNote"] then
		local sliderMaxChars = addon.functions.createSliderAce(
			L["IgnoreTooltipMaxChars"] .. ": " .. addon.db["ignoreTooltipMaxChars"],
			addon.db["ignoreTooltipMaxChars"],
			20,
			200,
			1,
			function(self, _, val)
				addon.db["ignoreTooltipMaxChars"] = val
				self:SetLabel(L["IgnoreTooltipMaxChars"] .. ": " .. val)
			end
		)
		groupCore:AddChild(sliderMaxChars)

		local sliderWords = addon.functions.createSliderAce(
			L["IgnoreTooltipWordsPerLine"] .. ": " .. addon.db["ignoreTooltipWordsPerLine"],
			addon.db["ignoreTooltipWordsPerLine"],
			1,
			20,
			1,
			function(self, _, val)
				addon.db["ignoreTooltipWordsPerLine"] = val
				self:SetLabel(L["IgnoreTooltipWordsPerLine"] .. ": " .. val)
			end
		)
		groupCore:AddChild(sliderWords)

		groupCore:AddChild(addon.functions.createSpacerAce())
	end

	local labelHeadline = addon.functions.createLabelAce("|cffffd700" .. L["IgnoreDesc"], nil, nil, 14)
	labelHeadline:SetFullWidth(true)
	groupCore:AddChild(labelHeadline)
	container:DoLayout()
	wrapper:DoLayout()
	groupCore:DoLayout()
	groupInv:DoLayout()
	scroll:DoLayout()
end

local function addCVarFrame(container, d)
	local scroll = addon.functions.createContainer("ScrollFrame", "List")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local persistenceGroup = addon.functions.createContainer("InlineGroup", "List")
	persistenceGroup:SetFullWidth(true)
	persistenceGroup:SetTitle(L["cvarPersistenceHeader"])
	wrapper:AddChild(persistenceGroup)

	local persistenceCheckbox = addon.functions.createCheckboxAce(L["cvarPersistence"], addon.db.cvarPersistenceEnabled, function(self, _, value)
		addon.db.cvarPersistenceEnabled = value and true or false
		addon.variables.requireReload = true
		if addon.functions.initializePersistentCVars then addon.functions.initializePersistentCVars() end
	end, L["cvarPersistenceDesc"])
	persistenceGroup:AddChild(persistenceCheckbox)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	groupCore:SetTitle(L["CVar"])
	wrapper:AddChild(groupCore)

	local data = addon.variables.cvarOptions

	local categories = {}
	for key, optionData in pairs(data) do
		local categoryKey = optionData.category or "cvarCategoryMisc"
		if not categories[categoryKey] then categories[categoryKey] = {} end
		table.insert(categories[categoryKey], {
			key = key,
			description = optionData.description,
			trueValue = optionData.trueValue,
			falseValue = optionData.falseValue,
			register = optionData.register or nil,
			persistent = optionData.persistent or nil,
			category = categoryKey,
		})
	end

	local function addCategoryGroup(categoryKey, entries)
		if not entries or #entries == 0 then return end

		table.sort(entries, function(a, b) return (a.description or "") < (b.description or "") end)

		local categoryGroup = addon.functions.createContainer("InlineGroup", "List")
		categoryGroup:SetTitle(L[categoryKey] or categoryKey)
		categoryGroup:SetFullWidth(true)
		groupCore:AddChild(categoryGroup)

		for _, entry in ipairs(entries) do
			local cvarKey = entry.key
			local cvarDesc = entry.description
			local cvarTrue = entry.trueValue
			local cvarFalse = entry.falseValue

			if entry.register and nil == GetCVar(cvarKey) then C_CVar.RegisterCVar(cvarKey, cvarTrue) end

			local actValue = (GetCVar(cvarKey) == cvarTrue)

			local cbElement = addon.functions.createCheckboxAce(cvarDesc, actValue, function(self, _, value)
				addon.variables.requireReload = true
				local newValue
				if value then
					newValue = cvarTrue
				else
					newValue = cvarFalse
				end

				if entry.persistent then
					addon.db.cvarOverrides = addon.db.cvarOverrides or {}
					addon.db.cvarOverrides[cvarKey] = newValue
				end

				setCVarValue(cvarKey, newValue)
			end)
			cbElement.trueValue = cvarTrue
			cbElement.falseValue = cvarFalse

			categoryGroup:AddChild(cbElement)
		end
	end

	local categoryOrder = {
		"cvarCategoryUtility",
		"cvarCategoryMovementInput",
		"cvarCategoryDisplay",
		"cvarCategorySystem",
		"cvarCategoryMisc",
	}

	for _, categoryKey in ipairs(categoryOrder) do
		if categories[categoryKey] then
			addCategoryGroup(categoryKey, categories[categoryKey])
			categories[categoryKey] = nil
		end
	end

	if next(categories) then
		local remaining = {}
		for categoryKey, entries in pairs(categories) do
			table.insert(remaining, { key = categoryKey, entries = entries })
		end
		table.sort(remaining, function(a, b)
			local labelA = L[a.key] or a.key
			local labelB = L[b.key] or b.key
			return labelA < labelB
		end)
		for _, bucket in ipairs(remaining) do
			addCategoryGroup(bucket.key, bucket.entries)
		end
	end
	scroll:DoLayout()
end

if addon.functions and addon.functions.RegisterOptionsPage then
	addon.functions.RegisterOptionsPage("ui\001actionbar", addVisibilityHub)
	addon.functions.RegisterOptionsPage("ui\001unitframe", addUnitFrame2)
	addon.functions.RegisterOptionsPage("ui\001datapanel", buildDatapanelFrame)
	addon.functions.RegisterOptionsPage("ui\001social", addSocialFrame)
	addon.functions.RegisterOptionsPage("ui\001system", addCVarFrame)
end
