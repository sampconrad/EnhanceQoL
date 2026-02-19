local addonName, addon = ...

addon.ActionBarLabels = addon.ActionBarLabels or {}
local Labels = addon.ActionBarLabels

local DEFAULT_ACTION_BUTTON_COUNT = _G.NUM_ACTIONBAR_BUTTONS or 12
local PET_ACTION_BUTTON_COUNT = _G.NUM_PET_ACTION_SLOTS or 10
local STANCE_ACTION_BUTTON_COUNT = _G.NUM_STANCE_SLOTS or _G.NUM_SHAPESHIFT_SLOTS or 10
local DEFAULT_BORDER_STYLE = "DEFAULT"
local QUICK_SLOT_BORDER = "Interface\\Buttons\\UI-Quickslot2"
local DEFAULT_BORDER_EDGE_SIZE = 16
local DEFAULT_BORDER_PADDING = 0
local LSM = LibStub("LibSharedMedia-3.0", true)

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

local function GetNormalTexture(button)
	if not button then return nil end
	if button.NormalTexture then return button.NormalTexture end
	if button.GetNormalTexture then return button:GetNormalTexture() end
	return nil
end

local function GetBorderEdgeSize()
	if not addon.db then return DEFAULT_BORDER_EDGE_SIZE end
	local value = tonumber(addon.db.actionBarBorderEdgeSize)
	if value == nil then value = DEFAULT_BORDER_EDGE_SIZE end
	if value < 1 then value = 1 end
	if value > 64 then value = 64 end
	return value
end

local function GetBorderPadding()
	if not addon.db then return DEFAULT_BORDER_PADDING end
	local value = tonumber(addon.db.actionBarBorderPadding)
	if value == nil then value = DEFAULT_BORDER_PADDING end
	if value < -32 then value = -32 end
	if value > 32 then value = 32 end
	return value
end

local function GetBorderColor()
	if not addon.db or not addon.db.actionBarBorderColoring then return 1, 1, 1, 1 end
	local col = addon.db.actionBarBorderColor or {}
	local r = tonumber(col.r) or 1
	local g = tonumber(col.g) or 1
	local b = tonumber(col.b) or 1
	local a = tonumber(col.a) or 1
	if r < 0 then
		r = 0
	elseif r > 1 then
		r = 1
	end
	if g < 0 then
		g = 0
	elseif g > 1 then
		g = 1
	end
	if b < 0 then
		b = 0
	elseif b > 1 then
		b = 1
	end
	if a < 0 then
		a = 0
	elseif a > 1 then
		a = 1
	end
	return r, g, b, a
end

local function BuildLSMBorderCache()
	local cache = {}
	if LSM and LSM.HashTable then
		for _, path in pairs(LSM:HashTable("border") or {}) do
			if type(path) == "string" and path ~= "" then cache[path] = true end
		end
	end
	Labels._lsmBorderCache = cache
end

local function IsLSMBorderPath(path)
	if not path or path == "" then return false end
	if not Labels._lsmBorderCache then BuildLSMBorderCache() end
	return Labels._lsmBorderCache and Labels._lsmBorderCache[path] == true
end

function Labels.ResetBorderCache() Labels._lsmBorderCache = nil end

local function GetCustomBorderStyle()
	if not addon.db then return DEFAULT_BORDER_STYLE end
	local style = addon.db.actionBarBorderStyle
	if type(style) ~= "string" or style == "" then return DEFAULT_BORDER_STYLE end
	return style
end

local function IsCustomBorderStyle(style) return type(style) == "string" and style ~= "" and style ~= DEFAULT_BORDER_STYLE end

local function EnsureCustomBorderTexture(button)
	if not button then return nil end
	local border = button.EQOL_CustomBorder
	if border then return border end
	border = button:CreateTexture(nil, "BORDER")
	border:SetBlendMode("BLEND")
	border:Hide()
	button.EQOL_CustomBorder = border
	return border
end

local function UpdateCustomBorderSizing(border, button)
	if not border or not button then return end
	local padding = GetBorderPadding()
	border:ClearAllPoints()
	border:SetPoint("CENTER", button, "CENTER", 0, 0)
	local normalTexture = GetNormalTexture(button)
	if normalTexture then
		local width, height = normalTexture:GetSize()
		if width and width > 0 and height and height > 0 then
			local newWidth = width + padding * 2
			local newHeight = height + padding * 2
			if newWidth < 1 then newWidth = 1 end
			if newHeight < 1 then newHeight = 1 end
			border:SetSize(newWidth, newHeight)
			return
		end
	end
	border:SetAllPoints()
end

local function EnsureCustomBorderFrame(button)
	if not button then return nil end
	local frame = button.EQOL_CustomBorderFrame
	if frame then return frame end
	frame = CreateFrame("Frame", nil, button, "BackdropTemplate")
	frame:SetFrameStrata(button:GetFrameStrata())
	frame:SetFrameLevel((button:GetFrameLevel() or 0) + 1)
	frame:EnableMouse(false)
	frame:Hide()
	button.EQOL_CustomBorderFrame = frame
	return frame
end

local function UpdateCustomBorderFrame(frame, button)
	if not frame or not button then return end
	local padding = GetBorderPadding()
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", button, "TOPLEFT", -padding, padding)
	frame:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", padding, -padding)
end

local function ApplyBackdropBorder(button, style)
	local frame = EnsureCustomBorderFrame(button)
	if not frame then return end
	UpdateCustomBorderFrame(frame, button)
	local edgeSize = GetBorderEdgeSize()
	if frame.EQOL_BorderStyle ~= style or frame.EQOL_BorderEdgeSize ~= edgeSize then
		frame:SetBackdrop({ edgeFile = style, edgeSize = edgeSize })
		frame.EQOL_BorderStyle = style
		frame.EQOL_BorderEdgeSize = edgeSize
	end
	local r, g, b, a = GetBorderColor()
	frame:SetBackdropBorderColor(r, g, b, a)
	frame:Show()
end

local function ApplyCustomBorder(button, style)
	local border = button and button.EQOL_CustomBorder
	local borderFrame = button and button.EQOL_CustomBorderFrame
	if not IsCustomBorderStyle(style) then
		if border then border:Hide() end
		if borderFrame then borderFrame:Hide() end
		return
	end

	if IsLSMBorderPath(style) then
		if border then border:Hide() end
		ApplyBackdropBorder(button, style)
		return
	end

	if borderFrame then borderFrame:Hide() end
	border = EnsureCustomBorderTexture(button)
	if not border then return end
	UpdateCustomBorderSizing(border, button)
	if border.EQOL_BorderStyle ~= style then
		border:SetTexture(style)
		border.EQOL_BorderStyle = style
	end
	if style == QUICK_SLOT_BORDER then
		border:SetTexCoord(0.2, 0.8, 0.2, 0.8)
	else
		border:SetTexCoord(0, 1, 0, 1)
	end
	local r, g, b, a = GetBorderColor()
	border:SetVertexColor(r, g, b, a)
	border:Show()
end

local function ApplyBorderVisibility(button, hide)
	local normalTexture = GetNormalTexture(button)
	if not normalTexture then return end

	if hide then
		if not normalTexture.EQOL_OriginalBorderState then normalTexture.EQOL_OriginalBorderState = {
			alpha = normalTexture:GetAlpha(),
			shown = normalTexture:IsShown() ~= false,
		} end
		normalTexture:SetAlpha(0)
		normalTexture:Hide()
		normalTexture.EQOL_BorderHiddenByEQOL = true
	elseif normalTexture.EQOL_BorderHiddenByEQOL then
		local restore = normalTexture.EQOL_OriginalBorderState or {}
		normalTexture:SetAlpha(restore.alpha or 1)
		if restore.shown == false then
			normalTexture:Hide()
		else
			normalTexture:Show()
		end
		normalTexture.EQOL_BorderHiddenByEQOL = nil
		normalTexture.EQOL_OriginalBorderState = nil
	end
end

local function RefreshButtonBorder(button)
	if not addon.db then return end
	local isActionButton = DetermineButtonBarName(button) ~= nil
	if not isActionButton then
		ApplyBorderVisibility(button, false)
		ApplyCustomBorder(button, nil)
		return
	end
	local style = GetCustomBorderStyle()
	local hasCustom = IsCustomBorderStyle(style)
	local hide = addon.db.actionBarHideBorders or hasCustom
	ApplyBorderVisibility(button, hide)
	ApplyCustomBorder(button, hasCustom and style or nil)
end

function Labels.RefreshActionButtonBorders()
	if Labels.EnsureActionButtonArtHook then Labels.EnsureActionButtonArtHook() end
	ForEachActionButton(function(button) RefreshButtonBorder(button) end)
end

function Labels.RefreshActionButtonBorder(button) RefreshButtonBorder(button) end

local function SyncRangeOverlayMask(btn, icon, overlay)
	if not (btn and icon and overlay) then return end
	if not overlay.AddMaskTexture then return end

	local currentMasks = overlay.EQOL_IconMasks
	local currentCount = type(currentMasks) == "table" and #currentMasks or 0
	local iconMaskCount = 0
	if icon.GetNumMaskTextures and icon.GetMaskTexture then iconMaskCount = icon:GetNumMaskTextures() or 0 end
	local fallbackMask = btn.IconMask
	local wantedCount = iconMaskCount
	if wantedCount == 0 and fallbackMask then wantedCount = 1 end

	local same = currentCount == wantedCount
	if same then
		for i = 1, wantedCount do
			local wantedMask
			if iconMaskCount > 0 then
				wantedMask = icon:GetMaskTexture(i)
			else
				wantedMask = fallbackMask
			end
			if currentMasks[i] ~= wantedMask then
				same = false
				break
			end
		end
	end
	if same then return end

	if type(currentMasks) == "table" and overlay.RemoveMaskTexture then
		for i = 1, #currentMasks do
			local mask = currentMasks[i]
			if mask then overlay:RemoveMaskTexture(mask) end
		end
	end

	if wantedCount > 0 then
		local newMasks = {}
		for i = 1, wantedCount do
			local wantedMask
			if iconMaskCount > 0 then
				wantedMask = icon:GetMaskTexture(i)
			else
				wantedMask = fallbackMask
			end
			if wantedMask then
				overlay:AddMaskTexture(wantedMask)
				newMasks[#newMasks + 1] = wantedMask
			end
		end
		overlay.EQOL_IconMasks = newMasks
	else
		overlay.EQOL_IconMasks = nil
	end
end

local function EnsureRangeOverlay(btn, icon)
	if not (btn and icon and btn.CreateTexture) then return nil end
	local overlay = btn.EQOL_RangeOverlay
	if not overlay then
		overlay = btn:CreateTexture(nil, "OVERLAY")
		overlay:Hide()
		btn.EQOL_RangeOverlay = overlay
	end
	if overlay.EQOL_AnchorIcon ~= icon then
		overlay:ClearAllPoints()
		overlay:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
		overlay:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
		overlay.EQOL_AnchorIcon = icon
	end
	SyncRangeOverlayMask(btn, icon, overlay)
	return overlay
end

local function ShowRangeOverlay(btn, show)
	local icon = btn and (btn.icon or btn.Icon)
	if not icon or not btn then return end
	btn.EQOL_RangeOverlayActive = show
	local overlay = EnsureRangeOverlay(btn, icon)
	if not overlay then return end
	if show and addon.db and addon.db.actionBarFullRangeColoring then
		local col = addon.db.actionBarFullRangeColor or { r = 1, g = 0.1, b = 0.1 }
		local alpha = col.a
		if alpha == nil then alpha = 0.45 end
		overlay:SetColorTexture(col.r or 1, col.g or 0.1, col.b or 0.1, alpha)
		overlay:Show()
	else
		overlay:Hide()
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

local function GetActionButtonCount(button)
	if not button then return nil end
	if button.Count then return button.Count end
	if button.GetName then return _G[button:GetName() .. "Count"] end
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

local function ApplyCountStyling(button)
	if not addon.db then return end
	local count = GetActionButtonCount(button)
	if not count then return end
	local face = addon.db.actionBarCountFontFace or addon.variables.defaultFont
	local size = NormalizeFontSize(addon.db.actionBarCountFontSize, 6, 32)
	local outline = addon.db.actionBarCountFontOutline or "OUTLINE"
	if addon.db.actionBarCountFontOverride then
		if not count.EQOL_OriginalCountFont then
			local oface, osize, ooutline = count:GetFont()
			count.EQOL_OriginalCountFont = { face = oface, size = osize, outline = ooutline }
		end
		ApplyFontWithFallback(count, face, size, outline)
		count.EQOL_UsingCountOverride = true
	elseif count.EQOL_UsingCountOverride then
		local orig = count.EQOL_OriginalCountFont or {}
		local restoreFace = orig.face or addon.variables.defaultFont
		local restoreSize = orig.size or size
		local restoreOutline = orig.outline or "OUTLINE"
		ApplyFontWithFallback(count, restoreFace, restoreSize, restoreOutline)
		count.EQOL_UsingCountOverride = nil
		count.EQOL_OriginalCountFont = nil
	end
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
Labels.ShortenHotkeyText = ShortenHotkeyText

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

local function InstallCountHook()
	if Labels.countHookInstalled then return end
	local hooked = false
	if ActionBarActionButtonMixin and type(ActionBarActionButtonMixin.UpdateCount) == "function" then
		hooksecurefunc(ActionBarActionButtonMixin, "UpdateCount", ApplyCountStyling)
		hooked = true
	end
	if hooked then
		Labels.countHookInstalled = true
		if Labels.countHookFrame then
			Labels.countHookFrame:UnregisterEvent("PLAYER_LOGIN")
			Labels.countHookFrame:SetScript("OnEvent", nil)
			Labels.countHookFrame = nil
		end
	end
end

InstallCountHook()
if not Labels.countHookInstalled then
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:SetScript("OnEvent", function(self)
		InstallCountHook()
		if Labels.countHookInstalled then
			self:UnregisterEvent("PLAYER_LOGIN")
			self:SetScript("OnEvent", nil)
		end
	end)
	Labels.countHookFrame = frame
end

function Labels.RefreshAllCountStyles()
	ForEachActionButton(function(button) ApplyCountStyling(button) end)
end

hooksecurefunc("ActionButton_UpdateRangeIndicator", function(self, checksRange, inRange)
	if not self or not self.action then return end
	self.EQOL_RangeOutOfRange = checksRange and inRange == false
	if checksRange and inRange == false then
		ShowRangeOverlay(self, true)
	else
		ShowRangeOverlay(self, false)
	end
end)

local function EnsureRangeUsableHook()
	if Labels._rangeUsableHooked then return end
	local mixin = _G.ActionBarActionButtonMixin
	if not (mixin and mixin.UpdateUsable) then return end
	hooksecurefunc(mixin, "UpdateUsable", function(self)
		if not addon.db or not addon.db.actionBarFullRangeColoring then return end
		if not self or not self.action then return end
		if self.EQOL_RangeOutOfRange then
			ShowRangeOverlay(self, true)
		else
			ShowRangeOverlay(self, false)
		end
	end)
	Labels._rangeUsableHooked = true
end

-- Refresh range overlays when the bar changes (mount/vehicle/override/stance swaps)
do
	local refreshPending = false
	local function RequestRangeRefresh()
		if refreshPending then return end
		if not addon.db or not addon.db.actionBarFullRangeColoring then return end
		refreshPending = true
		C_Timer.After(0, function()
			refreshPending = false
			if Labels.RefreshAllRangeOverlays then Labels.RefreshAllRangeOverlays() end
		end)
	end

	local events = {
		"UPDATE_OVERRIDE_ACTIONBAR",
		"UPDATE_VEHICLE_ACTIONBAR",
		"UPDATE_BONUS_ACTIONBAR",
		"UPDATE_SHAPESHIFT_FORM",
		"PLAYER_MOUNT_DISPLAY_CHANGED",
	}
	local rangeFrame
	local function EnsureRangeFrame()
		if rangeFrame then return rangeFrame end
		rangeFrame = CreateFrame("Frame")
		rangeFrame:SetScript("OnEvent", RequestRangeRefresh)
		return rangeFrame
	end

	function Labels.UpdateRangeOverlayEvents()
		local frame = EnsureRangeFrame()
		frame:UnregisterAllEvents()
		if addon.db and addon.db.actionBarFullRangeColoring then
			for _, evt in ipairs(events) do
				frame:RegisterEvent(evt)
			end
		end
	end
end

-- Debounced hotkey refresh for bindings changes (quick keybind mode)
do
	local refreshPending = false
	local function RequestHotkeyRefresh()
		if refreshPending then return end
		refreshPending = true
		C_Timer.After(0.05, function()
			refreshPending = false
			if Labels.RefreshAllHotkeyStyles then Labels.RefreshAllHotkeyStyles() end
		end)
	end

	local hotkeyFrame
	local function EnsureHotkeyFrame()
		if hotkeyFrame then return hotkeyFrame end
		hotkeyFrame = CreateFrame("Frame")
		hotkeyFrame:SetScript("OnEvent", RequestHotkeyRefresh)
		return hotkeyFrame
	end

	function Labels.UpdateHotkeyRefreshEvents()
		local frame = EnsureHotkeyFrame()
		frame:UnregisterAllEvents()
		frame:RegisterEvent("UPDATE_BINDINGS")
	end
end

local function OnPlayerLogin(self, event)
	if event ~= "PLAYER_LOGIN" then return end
	if Labels.EnsureActionButtonArtHook then Labels.EnsureActionButtonArtHook() end
	EnsureRangeUsableHook()
	if Labels.RefreshAllMacroNameVisibility then Labels.RefreshAllMacroNameVisibility() end
	if Labels.RefreshAllHotkeyStyles then Labels.RefreshAllHotkeyStyles() end
	if Labels.RefreshAllCountStyles then Labels.RefreshAllCountStyles() end
	if Labels.RefreshAllRangeOverlays then Labels.RefreshAllRangeOverlays() end
	if Labels.RefreshActionButtonBorders then Labels.RefreshActionButtonBorders() end
	if Labels.UpdateRangeOverlayEvents then Labels.UpdateRangeOverlayEvents() end
	if Labels.UpdateHotkeyRefreshEvents then Labels.UpdateHotkeyRefreshEvents() end
	if self then
		self:UnregisterEvent("PLAYER_LOGIN")
		self:SetScript("OnEvent", nil)
	end
end

function Labels.EnsureActionButtonArtHook()
	if Labels._actionBarArtHooked then return end
	local mixin = _G.BaseActionButtonMixin
	if not mixin or not mixin.UpdateButtonArt then return end
	hooksecurefunc(mixin, "UpdateButtonArt", function(button)
		if Labels.RefreshActionButtonBorder then Labels.RefreshActionButtonBorder(button) end
	end)
	Labels._actionBarArtHooked = true
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", OnPlayerLogin)
