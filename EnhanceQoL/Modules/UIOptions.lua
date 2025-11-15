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

local function addUIFrame(container)
	local data = {
		{
			parent = "",
			var = "ignoreTalkingHead",
			text = string.format(L["ignoreTalkingHeadN"], HUD_EDIT_MODE_TALKING_HEAD_FRAME_LABEL),
			type = "CheckBox",
			callback = function(self, _, value) addon.db["ignoreTalkingHead"] = value end,
		},
		{
			parent = "",
			var = "hideDynamicFlightBar",
			text = L["hideDynamicFlightBar"]:format(DYNAMIC_FLIGHT),
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["hideDynamicFlightBar"] = value
				addon.functions.toggleDynamicFlightBar(addon.db["hideDynamicFlightBar"])
			end,
		},
		{
			parent = "",
			var = "hideQuickJoinToast",
			text = HIDE .. " " .. COMMUNITIES_NOTIFICATION_SETTINGS_DIALOG_QUICK_JOIN_LABEL,
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["hideQuickJoinToast"] = value
				addon.functions.toggleQuickJoinToastButton(addon.db["hideQuickJoinToast"])
			end,
		},
		{
			parent = "",
			var = "hideZoneText",
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["hideZoneText"] = value
				addon.functions.toggleZoneText(addon.db["hideZoneText"])
			end,
		},
		{
			parent = "",
			var = "hideOrderHallBar",
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["hideOrderHallBar"] = value
				if OrderHallCommandBar then
					if value then
						OrderHallCommandBar:Hide()
					else
						OrderHallCommandBar:Show()
					end
				end
			end,
		},
		{
			parent = "",
			var = "hideMinimapButton",
			text = L["Hide Minimap Button"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["hideMinimapButton"] = value
				addon.functions.toggleMinimapButton(addon.db["hideMinimapButton"])
			end,
		},
		{
			parent = "",
			var = "hideRaidTools",
			text = L["Hide Raid Tools"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["hideRaidTools"] = value
				addon.functions.toggleRaidTools(addon.db["hideRaidTools"], _G.CompactRaidFrameManager)
			end,
		},
		{
			parent = "",
			var = "optionsFrameScale",
			type = "Slider",
			text = L["optionsFrameScale"],
			value = addon.db["optionsFrameScale"] or 1.0,
			min = OPTIONS_FRAME_MIN_SCALE,
			max = OPTIONS_FRAME_MAX_SCALE,
			step = 0.05,
			labelFormatter = function(val) return string.format("%.2f", val) end,
			callback = function(widget, _, val)
				local applied = addon.functions.applyOptionsFrameScale(val)
				if math.abs(applied - val) > 0.0001 then widget:SetValue(applied) end
			end,
		},
		-- Game Menu scaling toggle
		{
			parent = MAINMENU_BUTTON,
			var = "gameMenuScaleEnabled",
			text = L["enableGameMenuScale"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["gameMenuScaleEnabled"] = value
				if value then
					addon.functions.applyGameMenuScale()
				else
					-- Only restore default if we were the last to apply a scale
					if GameMenuFrame and addon.variables and addon.variables.gameMenuScaleLastApplied then
						local current = GameMenuFrame:GetScale() or 1.0
						if math.abs(current - addon.variables.gameMenuScaleLastApplied) < 0.0001 then GameMenuFrame:SetScale(1.0) end
					end
				end
				container:ReleaseChildren()
				addUIFrame(container)
			end,
		},
	}

	-- Conditionally add the slider when enabled
	if addon.db["gameMenuScaleEnabled"] then
		table.insert(data, {
			parent = MAINMENU_BUTTON,
			var = "gameMenuScale",
			type = "Slider",
			text = L["gameMenuScale"],
			value = addon.db["gameMenuScale"],
			min = 0.5,
			max = 2.0,
			step = 0.05,
			labelFormatter = function(val) return string.format("%.2f", val) end,
			callback = function(widget, _, val)
				local rounded = math.floor(val * 100 + 0.5) / 100
				addon.db["gameMenuScale"] = rounded
				if math.abs(rounded - val) > 0.0001 then
					widget:SetValue(rounded)
				else
					addon.functions.applyGameMenuScale()
				end
			end,
		})
	end

	addon.functions.createWrapperData(data, container, L)
end

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
			cb:SetRelativeWidth(0.5)
			if disableOthers and rule.key ~= "ALWAYS_HIDDEN" then cb:SetDisabled(true) end
			scenarioGroup:AddChild(cb)
		end
		if disableOthers then
			local warn = addon.functions.createLabelAce(L["visibilityAlwaysHiddenActive"] or "", nil, nil, 10)
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

		-- TODO actually no workaround for auras on raid frames so disabling this feature for now
		if not addon.variables.isMidnight then
			local cbRaid = addon.functions.createCheckboxAce(L["hideRaidFrameBuffs"], addon.db["hideRaidFrameBuffs"], function(_, _, value)
				addon.db["hideRaidFrameBuffs"] = value
				addon.functions.updateRaidFrameBuffs()
				addon.variables.requireReload = true
			end)
			g:AddChild(cbRaid)
		end

		local cbLeader = addon.functions.createCheckboxAce(L["showLeaderIconRaidFrame"], addon.db["showLeaderIconRaidFrame"], function(_, _, value)
			addon.db["showLeaderIconRaidFrame"] = value
			if value then
				setLeaderIcon()
			else
				removeLeaderIcon()
			end
		end)
		g:AddChild(cbLeader)

		local cbSolo = addon.functions.createCheckboxAce(L["showPartyFrameInSoloContent"], addon.db["showPartyFrameInSoloContent"], function(_, _, value)
			addon.db["showPartyFrameInSoloContent"] = value
			addon.variables.requireReload = true
			buildCoreUF()
			ApplyUnitFrameSettingByVar("unitframeSettingPlayerFrame")
			addon.functions.togglePartyFrameTitle(addon.db["hidePartyFrameTitle"])
		end)
		g:AddChild(cbSolo)

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

local function addChatFrame(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)
	scroll:PauseLayout()

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local function doLayout()
		if scroll and scroll.DoLayout then scroll:DoLayout() end
	end

	wrapper:PauseLayout()
	local groups = {}

	local function ensureGroup(key)
		local g, known
		if groups[key] then
			g = groups[key]
			g:PauseLayout()
			g:ReleaseChildren()
			known = true
		else
			g = addon.functions.createContainer("InlineGroup", "List")
			wrapper:AddChild(g)
			groups[key] = g
		end
		return g, known
	end

	local function finishGroup(g, known)
		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildGeneral()
		local g, known = ensureGroup("general")
		local options = {
			{
				var = "chatShowLootCurrencyIcons",
				text = L["chatLootCurrencyIcons"],
				desc = L["chatLootCurrencyIconsDesc"],
				onToggle = function(value)
					addon.db["chatShowLootCurrencyIcons"] = value
					if addon.ChatIcons and addon.ChatIcons.SetEnabled then addon.ChatIcons:SetEnabled(value) end
				end,
			},
			{
				var = "chatHideLearnUnlearn",
				text = L["chatHideLearnUnlearn"],
				desc = L["chatHideLearnUnlearnDesc"],
				onToggle = function(value)
					addon.db["chatHideLearnUnlearn"] = value
					if addon.functions.ApplyChatLearnFilter then addon.functions.ApplyChatLearnFilter(value) end
				end,
			},
		}

		table.sort(options, function(a, b) return a.text < b.text end)

		for _, entry in ipairs(options) do
			local cb = addon.functions.createCheckboxAce(entry.text, addon.db[entry.var], function(_, _, value)
				if entry.onToggle then
					entry.onToggle(value)
				else
					addon.db[entry.var] = value
				end
			end, entry.desc)
			g:AddChild(cb)
		end

		finishGroup(g, known)
	end

	local function buildFade()
		local g, known = ensureGroup("fade")

		local fadeCheckbox = addon.functions.createCheckboxAce(L["chatFrameFadeEnabled"], addon.db["chatFrameFadeEnabled"], function(_, _, value)
			addon.db["chatFrameFadeEnabled"] = value
			if ChatFrame1 then ChatFrame1:SetFading(value) end
			buildFade()
		end)
		g:AddChild(fadeCheckbox)

		if addon.db["chatFrameFadeEnabled"] then
			local sliderTimeVisible = addon.functions.createSliderAce(
				L["chatFrameFadeTimeVisibleText"] .. ": " .. addon.db["chatFrameFadeTimeVisible"] .. "s",
				addon.db["chatFrameFadeTimeVisible"],
				1,
				300,
				1,
				function(self, _, value)
					addon.db["chatFrameFadeTimeVisible"] = value
					if ChatFrame1 then ChatFrame1:SetTimeVisible(value) end
					self:SetLabel(L["chatFrameFadeTimeVisibleText"] .. ": " .. value .. "s")
				end
			)
			g:AddChild(sliderTimeVisible)

			g:AddChild(addon.functions.createSpacerAce())

			local sliderFadeDuration = addon.functions.createSliderAce(
				L["chatFrameFadeDurationText"] .. ": " .. addon.db["chatFrameFadeDuration"] .. "s",
				addon.db["chatFrameFadeDuration"],
				1,
				60,
				1,
				function(self, _, value)
					addon.db["chatFrameFadeDuration"] = value
					if ChatFrame1 then ChatFrame1:SetFadeDuration(value) end
					self:SetLabel(L["chatFrameFadeDurationText"] .. ": " .. value .. "s")
				end
			)
			g:AddChild(sliderFadeDuration)
		end

		finishGroup(g, known)
	end

	local function buildBubbleFont()
		local g, known = ensureGroup("bubbleFont")
		local overrideCheckbox = addon.functions.createCheckboxAce(L["chatBubbleFontOverride"], addon.db["chatBubbleFontOverride"], function(_, _, value)
			addon.db["chatBubbleFontOverride"] = value
			addon.functions.ApplyChatBubbleFontSize(addon.db["chatBubbleFontSize"])
			buildBubbleFont()
		end, L["chatBubbleFontOverrideDesc"])
		g:AddChild(overrideCheckbox)

		if addon.db["chatBubbleFontOverride"] then
			local function labelText(size) return L["chatBubbleFontSize"] .. ": " .. size end
			local currentSize = tonumber(addon.db and addon.db["chatBubbleFontSize"]) or DEFAULT_CHAT_BUBBLE_FONT_SIZE
			local slider = addon.functions.createSliderAce(labelText(currentSize), currentSize, CHAT_BUBBLE_FONT_MIN, CHAT_BUBBLE_FONT_MAX, 1, function(self, _, value)
				local applied = addon.functions.ApplyChatBubbleFontSize(value)
				addon.db["chatBubbleFontSize"] = applied
				self:SetValue(applied)
				self:SetLabel(labelText(applied))
			end)
			g:AddChild(slider)
		end

		finishGroup(g, known)
	end

	local function buildChatIM()
		local g, known = ensureGroup("chatIM")

		local entries = {
			{
				var = "enableChatIM",
				text = L["enableChatIM"],
				desc = L["enableChatIMDesc"],
				onToggle = function(value)
					addon.db["enableChatIM"] = value
					if addon.ChatIM and addon.ChatIM.SetEnabled then addon.ChatIM:SetEnabled(value) end
					if not value then addon.variables.requireReload = true end
				end,
				rebuild = true,
			},
		}

		table.sort(entries, function(a, b) return a.text < b.text end)

		for _, entry in ipairs(entries) do
			local cb = addon.functions.createCheckboxAce(entry.text, addon.db[entry.var], function(_, _, value)
				if entry.onToggle then
					entry.onToggle(value)
				else
					addon.db[entry.var] = value
				end
				if entry.rebuild then buildChatIM() end
			end, entry.desc)
			g:AddChild(cb)
		end

		if addon.db["enableChatIM"] then
			local sub = addon.functions.createContainer("InlineGroup", "List")
			g:AddChild(sub)

			local subEntries = {
				{
					var = "enableChatIMFade",
					text = L["enableChatIMFade"],
					desc = L["enableChatIMFadeDesc"],
					onToggle = function(value)
						addon.db["enableChatIMFade"] = value
						if addon.ChatIM and addon.ChatIM.SetEnabled then addon.ChatIM:UpdateAlpha() end
					end,
				},
				{
					var = "enableChatIMRaiderIO",
					text = L["enableChatIMRaiderIO"],
				},
				{
					var = "enableChatIMWCL",
					text = L["enableChatIMWCL"],
				},
				{
					var = "chatIMUseCustomSound",
					text = L["enableChatIMCustomSound"],
					onToggle = function(value) addon.db["chatIMUseCustomSound"] = value end,
					rebuild = true,
				},
				{
					var = "chatIMHideInCombat",
					text = L["chatIMHideInCombat"],
					desc = L["chatIMHideInCombatDesc"],
				},
				{
					var = "chatIMUseAnimation",
					text = L["chatIMUseAnimation"],
					desc = L["chatIMUseAnimationDesc"],
				},
			}

			table.sort(subEntries, function(a, b) return a.text < b.text end)

			for _, entry in ipairs(subEntries) do
				local cb = addon.functions.createCheckboxAce(entry.text, addon.db[entry.var], function(_, _, value)
					if entry.onToggle then
						entry.onToggle(value)
					else
						addon.db[entry.var] = value
					end
					if entry.var == "chatIMHideInCombat" and addon.ChatIM and addon.ChatIM.SetEnabled then addon.ChatIM:SetEnabled(true) end
					if entry.rebuild then buildChatIM() end
				end, entry.desc)
				sub:AddChild(cb)
			end

			sub:AddChild(addon.functions.createSpacerAce())

			if addon.db["chatIMUseCustomSound"] then
				if addon.ChatIM and addon.ChatIM.BuildSoundTable and not addon.ChatIM.availableSounds then addon.ChatIM:BuildSoundTable() end
				local soundList = {}
				for name in pairs(addon.ChatIM and addon.ChatIM.availableSounds or {}) do
					soundList[name] = name
				end
				local list, order = addon.functions.prepareListForDropdown(soundList)
				local dropSound = addon.functions.createDropdownAce(L["ChatIMCustomSound"], list, order, function(self, _, val)
					addon.db["chatIMCustomSoundFile"] = val
					self:SetValue(val)
					local file = addon.ChatIM and addon.ChatIM.availableSounds and addon.ChatIM.availableSounds[val]
					if file then PlaySoundFile(file, "Master") end
				end)
				dropSound:SetValue(addon.db["chatIMCustomSoundFile"])
				sub:AddChild(dropSound)
				sub:AddChild(addon.functions.createSpacerAce())
			end

			local sliderHistory = addon.functions.createSliderAce(L["ChatIMHistoryLimit"] .. ": " .. addon.db["chatIMMaxHistory"], addon.db["chatIMMaxHistory"], 0, 1000, 1, function(self, _, value)
				addon.db["chatIMMaxHistory"] = value
				if addon.ChatIM and addon.ChatIM.SetMaxHistoryLines then addon.ChatIM:SetMaxHistoryLines(value) end
				self:SetLabel(L["ChatIMHistoryLimit"] .. ": " .. value)
			end)
			sub:AddChild(sliderHistory)

			local historyList = {}
			for name in pairs(EnhanceQoL_IMHistory or {}) do
				historyList[name] = name
			end
			local list, order = addon.functions.prepareListForDropdown(historyList)
			local dropHistory = addon.functions.createDropdownAce(L["ChatIMHistoryPlayer"], list, order, function(self, _, val) self:SetValue(val) end)

			local btnDelete = addon.functions.createButtonAce(L["ChatIMHistoryDelete"], 140, function()
				local target = dropHistory:GetValue()
				if not target then return end
				StaticPopupDialogs["EQOL_DELETE_IM_HISTORY"] = StaticPopupDialogs["EQOL_DELETE_IM_HISTORY"]
					or {
						text = L["ChatIMHistoryDeleteConfirm"],
						button1 = YES,
						button2 = CANCEL,
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						preferredIndex = 3,
					}
				StaticPopupDialogs["EQOL_DELETE_IM_HISTORY"].OnAccept = function()
					EnhanceQoL_IMHistory[target] = nil
					if addon.ChatIM and addon.ChatIM.history then addon.ChatIM.history[target] = nil end
					buildChatIM()
				end
				StaticPopup_Show("EQOL_DELETE_IM_HISTORY", target)
			end)

			local btnClear = addon.functions.createButtonAce(L["ChatIMHistoryClearAll"], 140, function()
				StaticPopupDialogs["EQOL_CLEAR_IM_HISTORY"] = StaticPopupDialogs["EQOL_CLEAR_IM_HISTORY"]
					or {
						text = L["ChatIMHistoryClearConfirm"],
						button1 = YES,
						button2 = CANCEL,
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						preferredIndex = 3,
					}
				StaticPopupDialogs["EQOL_CLEAR_IM_HISTORY"].OnAccept = function()
					wipe(EnhanceQoL_IMHistory)
					if addon.ChatIM then addon.ChatIM.history = EnhanceQoL_IMHistory end
					buildChatIM()
				end
				StaticPopup_Show("EQOL_CLEAR_IM_HISTORY")
			end)

			sub:AddChild(dropHistory)
			sub:AddChild(btnDelete)
			sub:AddChild(btnClear)

			sub:AddChild(addon.functions.createSpacerAce())

			local hint = AceGUI:Create("Label")
			hint:SetFullWidth(true)
			hint:SetFont(addon.variables.defaultFont, 14, "OUTLINE")
			hint:SetText("|cffffd700" .. L["RightClickCloseTab"] .. "|r ")
			sub:AddChild(hint)
		end

		finishGroup(g, known)
	end

	buildGeneral()
	buildFade()
	buildBubbleFont()
	buildChatIM()

	wrapper:ResumeLayout()
	doLayout()
	scroll:ResumeLayout()
	scroll:DoLayout()
end

-- (removed old addMinimapFrame; replaced by addMinimapFrame2 below)

-- New modular minimap UI builder that avoids full page rebuilds

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
	addon.functions.RegisterOptionsPage("ui", addUIFrame)
	addon.functions.RegisterOptionsPage("ui\001actionbar", addVisibilityHub)
	addon.functions.RegisterOptionsPage("ui\001chatframe", addChatFrame)
	addon.functions.RegisterOptionsPage("ui\001unitframe", addUnitFrame2)
	addon.functions.RegisterOptionsPage("ui\001datapanel", buildDatapanelFrame)
	addon.functions.RegisterOptionsPage("ui\001social", addSocialFrame)
	addon.functions.RegisterOptionsPage("ui\001system", addCVarFrame)
end
