local addonName, addon = ...

addon.ActionBarLabels = addon.ActionBarLabels or {}
local Labels = addon.ActionBarLabels

local DEFAULT_ACTION_BUTTON_COUNT = _G.NUM_ACTIONBAR_BUTTONS or 12
local PET_ACTION_BUTTON_COUNT = _G.NUM_PET_ACTION_SLOTS or 10
local STANCE_ACTION_BUTTON_COUNT = _G.NUM_STANCE_SLOTS or _G.NUM_SHAPESHIFT_SLOTS or 10

local function GetActionBarButtonPrefix(barName)
	if not barName then return nil, 0 end
	if barName == "MainMenuBar" or barName == "MainActionBar" then return "ActionButton", DEFAULT_ACTION_BUTTON_COUNT end
	if barName == "PetActionBar" then return "PetActionButton", PET_ACTION_BUTTON_COUNT end
	if barName == "StanceBar" then return "StanceButton", STANCE_ACTION_BUTTON_COUNT end
	return barName .. "Button", DEFAULT_ACTION_BUTTON_COUNT
end

local ACTION_BAR_NAME_LOOKUP
local function EnsureActionBarNameLookup()
	if ACTION_BAR_NAME_LOOKUP then return ACTION_BAR_NAME_LOOKUP end
	ACTION_BAR_NAME_LOOKUP = {}
	if addon.variables and addon.variables.actionBarNames then
		for _, info in ipairs(addon.variables.actionBarNames) do
			if info.name then ACTION_BAR_NAME_LOOKUP[info.name] = true end
		end
	end
	return ACTION_BAR_NAME_LOOKUP
end

local function DetermineButtonBarName(button)
	if not button then return nil end
	if button.EQOL_ActionBarName then return button.EQOL_ActionBarName end
	local lookup = EnsureActionBarNameLookup()
	local parent = button:GetParent()
	while parent do
		if parent.GetName then
			local pName = parent:GetName()
			if pName and lookup[pName] then
				button.EQOL_ActionBarName = pName
				return pName
			end
		end
		parent = parent:GetParent()
	end
	return nil
end

local function ForEachActionButton(callback)
	if type(callback) ~= "function" then return end
	local list = addon.variables and addon.variables.actionBarNames
	if not list then return end
	local seen = {}
	for _, info in ipairs(list) do
		local prefix, count = GetActionBarButtonPrefix(info.name)
		if prefix and count then
			for i = 1, count do
				local button = _G[prefix .. i]
				if button and not seen[button] then
					seen[button] = true
					if not button.EQOL_ActionBarName then button.EQOL_ActionBarName = info.name end
					callback(button, info, i)
				end
			end
		end
	end
end

local function EnsureOverlay(btn)
	if btn.EQOL_RangeOverlay then return btn.EQOL_RangeOverlay end
	local tex = btn:CreateTexture(nil, "OVERLAY", nil, 7)
	tex:SetAllPoints(btn.icon or btn.Icon or btn)
	tex:Hide()
	btn.EQOL_RangeOverlay = tex
	return tex
end

local function ShowRangeOverlay(btn, show)
	local ov = EnsureOverlay(btn)
	if show and addon.db and addon.db.actionBarFullRangeColoring then
		local col = addon.db.actionBarFullRangeColor or { r = 1, g = 0.1, b = 0.1 }
		local alpha = addon.db.actionBarFullRangeAlpha or 0.35
		ov:SetColorTexture(col.r, col.g, col.b, alpha)
		ov:Show()
	else
		ov:Hide()
	end
end

function Labels.RefreshAllRangeOverlays()
	ForEachActionButton(function(button) ActionButton_UpdateRangeIndicator(button) end)
end

local function UpdateMacroNameVisibility(button, hide)
	if not button or not button.GetName then return end

	local nameFrame = button.Name or _G[button:GetName() .. "Name"]
	if not nameFrame then return end

	if hide then
		if not nameFrame.EQOL_IsHiddenByEQOL then
			nameFrame.EQOL_OriginalAlpha = nameFrame:GetAlpha()
			nameFrame:SetAlpha(0)
			nameFrame.EQOL_IsHiddenByEQOL = true
		end
	elseif nameFrame.EQOL_IsHiddenByEQOL then
		nameFrame:SetAlpha(nameFrame.EQOL_OriginalAlpha or 1)
		nameFrame.EQOL_IsHiddenByEQOL = nil
	end
end

function Labels.RefreshAllMacroNameVisibility()
	local hide = addon.db and addon.db.hideMacroNames
	local overrideEnabled = addon.db and addon.db.actionBarMacroFontOverride and not hide
	local fontFace = addon.db and addon.db.actionBarMacroFontFace or addon.variables.defaultFont
	local fontSize = tonumber(addon.db and addon.db.actionBarMacroFontSize) or 12
	local fontOutline = addon.db and addon.db.actionBarMacroFontOutline or "OUTLINE"
	if fontSize < 6 then fontSize = 6 end
	if fontSize > 32 then fontSize = 32 end
	ForEachActionButton(function(button, info)
		if info.name ~= "PetActionBar" and info.name ~= "StanceBar" then
			UpdateMacroNameVisibility(button, hide)
			local nameFrame = button.Name or (button.GetName and _G[button:GetName() .. "Name"])
			if nameFrame and nameFrame.SetFont then
				if overrideEnabled then
					if not nameFrame.EQOL_OriginalMacroFont then
						local face, size, outline = nameFrame:GetFont()
						nameFrame.EQOL_OriginalMacroFont = { face = face, size = size, outline = outline }
					end
					local ok = nameFrame:SetFont(fontFace or addon.variables.defaultFont, fontSize, fontOutline or "OUTLINE")
					if not ok then nameFrame:SetFont(addon.variables.defaultFont, fontSize, fontOutline or "OUTLINE") end
					nameFrame.EQOL_UsingMacroOverride = true
				elseif nameFrame.EQOL_UsingMacroOverride then
					local orig = nameFrame.EQOL_OriginalMacroFont or {}
					local face = orig.face or addon.variables.defaultFont
					local size = orig.size or 12
					local outline = orig.outline or "OUTLINE"
					nameFrame:SetFont(face, size, outline)
					nameFrame.EQOL_UsingMacroOverride = nil
					nameFrame.EQOL_OriginalMacroFont = nil
				end
			end
		end
	end)
end

local function GetActionButtonHotkey(button)
	if not button then return nil end
	if button.HotKey then return button.HotKey end
	if button.GetName then return _G[button:GetName() .. "HotKey"] end
	return nil
end

local function NormalizeFontSize(size, minValue, maxValue)
	local value = tonumber(size) or minValue
	if value < minValue then value = minValue end
	if value > maxValue then value = maxValue end
	return value
end

Labels.NormalizeFontSize = NormalizeFontSize

local function ApplyFontWithFallback(region, face, size, outline)
	if not region or not region.SetFont then return end
	local ok = region:SetFont(face or addon.variables.defaultFont, size, outline or "OUTLINE")
	if not ok then region:SetFont(addon.variables.defaultFont, size, outline or "OUTLINE") end
end

local function ShouldHideHotkey(barName)
	if not addon.db or not barName then return false end
	local overrides = addon.db.actionBarHiddenHotkeys
	if type(overrides) ~= "table" then return false end
	return overrides[barName] == true
end

local function UpdateHotkeyVisibility(hotkey, hide)
	if not hotkey or not hotkey.SetAlpha then return end
	if hide then
		if not hotkey.EQOL_PreviousAlpha or hotkey.EQOL_PreviousAlpha <= 0 then hotkey.EQOL_PreviousAlpha = hotkey:GetAlpha() end
		if not hotkey.EQOL_PreviousAlpha or hotkey.EQOL_PreviousAlpha <= 0 then hotkey.EQOL_PreviousAlpha = 1 end
		hotkey:SetAlpha(0)
		hotkey.EQOL_Hidden = true
	else
		if hotkey.EQOL_Hidden then
			hotkey:SetAlpha(hotkey.EQOL_PreviousAlpha or 1)
			hotkey.EQOL_PreviousAlpha = nil
			hotkey.EQOL_Hidden = nil
		end
	end
end

local HOTKEY_SHORT_REPLACEMENTS = {
	{ "MOUSE WHEEL DOWN", "MWD" },
	{ "MOUSE WHEEL UP", "MWU" },
	{ "MOUSE WHEEL", "MW" },
	{ "MOUSE BUTTON", "M" },
	{ "MOUSEBUTTON", "M" },
	{ "MOUSE", "M" },
	{ "BUTTON", "M" },
	{ "NUM PAD ", "N" },
	{ "NUMPAD", "N" },
	{ "PAGEUP", "PU" },
	{ "PAGEDOWN", "PD" },
	{ "SPACEBAR", "SP" },
	{ "BACKSPACE", "BS" },
	{ "DELETE", "DEL" },
	{ "INSERT", "INS" },
	{ "HOME", "HM" },
	{ "ARROW", "" },
	{ "CAPSLOCK", "CAPS" },
}

local function EscapePattern(text)
	if type(text) ~= "string" or text == "" then return "" end
	return text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

local function GetGlobalUpper(key, fallback)
	local value = _G[key]
	if type(value) ~= "string" or value == "" then value = fallback end
	if type(value) ~= "string" or value == "" then return nil end
	return string.upper(value)
end

local mouseButtonShortcutPatterns
local function EnsureMouseButtonShortcuts()
	if mouseButtonShortcutPatterns then return mouseButtonShortcutPatterns end
	mouseButtonShortcutPatterns = {}
	for i = 1, 31 do
		local label = GetGlobalUpper("KEY_BUTTON" .. i)
		if label then table.insert(mouseButtonShortcutPatterns, { pattern = EscapePattern(label), replacement = "M" .. i }) end
	end
	local mwDown = GetGlobalUpper("KEY_MOUSEWHEELDOWN")
	if mwDown then table.insert(mouseButtonShortcutPatterns, { pattern = EscapePattern(mwDown), replacement = "MWD" }) end
	local mwUp = GetGlobalUpper("KEY_MOUSEWHEELUP")
	if mwUp then table.insert(mouseButtonShortcutPatterns, { pattern = EscapePattern(mwUp), replacement = "MWU" }) end
	return mouseButtonShortcutPatterns
end

local modifierShortcutPatterns
local function EnsureModifierShortcutPatterns()
	if modifierShortcutPatterns then return modifierShortcutPatterns end
	modifierShortcutPatterns = {}
	local function addModifier(globalKey, replacement, fallback)
		local text = GetGlobalUpper(globalKey, fallback)
		if text and text ~= "" then table.insert(modifierShortcutPatterns, { pattern = EscapePattern(text) .. "%-", replacement = replacement }) end
	end
	addModifier("SHIFT_KEY_TEXT", "S", "SHIFT")
	addModifier("CTRL_KEY_TEXT", "C", "CTRL")
	addModifier("ALT_KEY_TEXT", "A", "ALT")
	return modifierShortcutPatterns
end

local function ShortenHotkeyText(text)
	if type(text) ~= "string" or text == "" then return text end
	local isMinusKeybind
	if string.sub(text, -1) == "-" then isMinusKeybind = true end
	if _G.RANGE_INDICATOR and text == _G.RANGE_INDICATOR then return text end
	local short = text:upper()
	for _, data in ipairs(EnsureMouseButtonShortcuts()) do
		short = short:gsub(data.pattern, data.replacement)
	end
	for _, data in ipairs(EnsureModifierShortcutPatterns()) do
		short = short:gsub(data.pattern, data.replacement)
	end
	for _, repl in ipairs(HOTKEY_SHORT_REPLACEMENTS) do
		short = short:gsub(repl[1], repl[2])
	end
	short = short:gsub("CTRL%-", "C")
	short = short:gsub("CONTROL%-", "C")
	short = short:gsub("ALT%-", "A")
	short = short:gsub("SHIFT%-", "S")
	short = short:gsub("OPTION%-", "O")
	short = short:gsub("COMMAND%-", "CM")
	short = short:gsub("PLUS", "+")
	short = short:gsub("MINUS", "-")
	short = short:gsub("MULTIPLY", "*")
	short = short:gsub("DIVIDE", "/")
	short = short:gsub("[%s%-]", "")
	if isMinusKeybind then short = short .. "-" end
	return short
end

local function ApplyHotkeyStyling(button)
	if not addon.db then return end
	local hotkey = GetActionButtonHotkey(button)
	if not hotkey then return end
	local originalText = hotkey:GetText()
	if hotkey.EQOL_ShortApplied and originalText ~= hotkey.EQOL_ShortValue then
		hotkey.EQOL_ShortApplied = nil
		hotkey.EQOL_ShortValue = nil
	end

	local face = addon.db.actionBarHotkeyFontFace or addon.variables.defaultFont
	local size = NormalizeFontSize(addon.db.actionBarHotkeyFontSize, 6, 32)
	local outline = addon.db.actionBarHotkeyFontOutline or "OUTLINE"
	if addon.db.actionBarHotkeyFontOverride then
		if not hotkey.EQOL_OriginalHotkeyFont then
			local oface, osize, ooutline = hotkey:GetFont()
			hotkey.EQOL_OriginalHotkeyFont = { face = oface, size = osize, outline = ooutline }
		end
		ApplyFontWithFallback(hotkey, face, size, outline)
		hotkey.EQOL_UsingHotkeyOverride = true
	elseif hotkey.EQOL_UsingHotkeyOverride then
		local orig = hotkey.EQOL_OriginalHotkeyFont or {}
		local restoreFace = orig.face or addon.variables.defaultFont
		local restoreSize = orig.size or size
		local restoreOutline = orig.outline or "OUTLINE"
		ApplyFontWithFallback(hotkey, restoreFace, restoreSize, restoreOutline)
		hotkey.EQOL_UsingHotkeyOverride = nil
		hotkey.EQOL_OriginalHotkeyFont = nil
	end

	local barName = DetermineButtonBarName(button)
	UpdateHotkeyVisibility(hotkey, ShouldHideHotkey(barName))

	if addon.db.actionBarShortHotkeys then
		if not hotkey.EQOL_ShortApplied then hotkey.EQOL_OriginalHotkeyText = originalText end
		local baseText = hotkey.EQOL_OriginalHotkeyText or originalText
		local shortText = ShortenHotkeyText(baseText)
		if shortText and shortText ~= hotkey:GetText() then
			hotkey:SetText(shortText)
			hotkey.EQOL_ShortApplied = true
			hotkey.EQOL_ShortValue = shortText
		end
	else
		if hotkey.EQOL_ShortApplied and hotkey.EQOL_OriginalHotkeyText then hotkey:SetText(hotkey.EQOL_OriginalHotkeyText) end
		hotkey.EQOL_ShortApplied = nil
		hotkey.EQOL_ShortValue = nil
	end
end

local function InstallHotkeyHook()
	if Labels.hotkeyHookInstalled then return end
	local hooked = false
	if ActionBarActionButtonMixin and type(ActionBarActionButtonMixin.UpdateHotkeys) == "function" then
		hooksecurefunc(ActionBarActionButtonMixin, "UpdateHotkeys", ApplyHotkeyStyling)
		hooked = true
	end
	if hooked then
		Labels.hotkeyHookInstalled = true
		if Labels.hotkeyHookFrame then
			Labels.hotkeyHookFrame:UnregisterEvent("PLAYER_LOGIN")
			Labels.hotkeyHookFrame:SetScript("OnEvent", nil)
			Labels.hotkeyHookFrame = nil
		end
	end
end

InstallHotkeyHook()
if not Labels.hotkeyHookInstalled then
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:SetScript("OnEvent", function(self)
		InstallHotkeyHook()
		if Labels.hotkeyHookInstalled then
			self:UnregisterEvent("PLAYER_LOGIN")
			self:SetScript("OnEvent", nil)
		end
	end)
	Labels.hotkeyHookFrame = frame
end

function Labels.RefreshAllHotkeyStyles()
	ForEachActionButton(function(button) ApplyHotkeyStyling(button) end)
end

hooksecurefunc("ActionButton_UpdateRangeIndicator", function(self, checksRange, inRange)
	if not self or not self.action then return end
	if checksRange and inRange == false then
		ShowRangeOverlay(self, true)
	else
		ShowRangeOverlay(self, false)
	end
end)

local function OnPlayerLogin(self, event)
	if event ~= "PLAYER_LOGIN" then return end
	if Labels.RefreshAllMacroNameVisibility then Labels.RefreshAllMacroNameVisibility() end
	if Labels.RefreshAllHotkeyStyles then Labels.RefreshAllHotkeyStyles() end
	if Labels.RefreshAllRangeOverlays then Labels.RefreshAllRangeOverlays() end
	if self then
		self:UnregisterEvent("PLAYER_LOGIN")
		self:SetScript("OnEvent", nil)
	end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", OnPlayerLogin)
