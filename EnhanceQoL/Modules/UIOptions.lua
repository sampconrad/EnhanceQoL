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

	local function buildHitIndicator() end

	local function buildCore() end

	local function buildHealthText() end

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

if addon.functions and addon.functions.RegisterOptionsPage then
	addon.functions.RegisterOptionsPage("ui\001actionbar", addVisibilityHub)
	addon.functions.RegisterOptionsPage("ui\001unitframe", addUnitFrame2)
end
