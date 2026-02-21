local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.CombatText = addon.CombatText or {}
local CombatText = addon.CombatText

local L = LibStub("AceLocale-3.0"):GetLocale(parentAddonName)
local EditMode = addon.EditMode
local SettingType = EditMode and EditMode.lib and EditMode.lib.SettingType
local LSM = LibStub("LibSharedMedia-3.0", true)

local EDITMODE_ID = "combatText"
local PREVIEW_PADDING_X = 20
local PREVIEW_PADDING_Y = 10

local function defaultFontFace() return (addon.variables and addon.variables.defaultFont) or STANDARD_TEXT_FONT end

CombatText.defaults = CombatText.defaults
	or {
		duration = 3,
		fontSize = 32,
		fontFace = defaultFontFace(),
		color = { r = 1, g = 1, b = 1, a = 1 },
		enterColor = { r = 1, g = 1, b = 1, a = 1 },
		leaveColor = { r = 1, g = 1, b = 1, a = 1 },
	}

local defaults = CombatText.defaults
defaults.enterColor = defaults.enterColor or defaults.color or { r = 1, g = 1, b = 1, a = 1 }
defaults.leaveColor = defaults.leaveColor or defaults.color or defaults.enterColor or { r = 1, g = 1, b = 1, a = 1 }
defaults.color = defaults.color or defaults.enterColor

local DB_ENABLED = "combatTextEnabled"
local DB_DURATION = "combatTextDuration"
local DB_FONT = "combatTextFont"
local DB_FONT_SIZE = "combatTextFontSize"
local DB_COLOR = "combatTextColor"
local DB_ENTER_COLOR = "combatTextEnterColor"
local DB_LEAVE_COLOR = "combatTextLeaveColor"

local function getValue(key, fallback)
	if not addon.db then return fallback end
	local value = addon.db[key]
	if value == nil then return fallback end
	return value
end

local function clamp(value, minValue, maxValue)
	value = tonumber(value) or minValue
	if value < minValue then return minValue end
	if value > maxValue then return maxValue end
	return value
end

local function normalizeColor(value, fallback)
	if type(value) == "table" then
		local r = value.r or value[1] or 1
		local g = value.g or value[2] or 1
		local b = value.b or value[3] or 1
		local a = value.a or value[4]
		return r, g, b, a
	elseif type(value) == "number" then
		return value, value, value
	end
	local d = fallback or defaults.color or {}
	return d.r or 1, d.g or 1, d.b or 1, d.a
end

local function normalizeFontFace(value)
	if type(value) ~= "string" or value == "" then return nil end
	return value
end

local function fontFaceOptions()
	local list = {}
	local defaultPath = defaultFontFace()
	local hasDefault = false
	if LSM and LSM.HashTable then
		local hash = LSM:HashTable("font") or {}
		for name, path in pairs(hash) do
			if type(path) == "string" and path ~= "" then
				list[#list + 1] = { value = path, label = tostring(name) }
				if path == defaultPath then hasDefault = true end
			end
		end
	end
	if defaultPath and not hasDefault then list[#list + 1] = { value = defaultPath, label = DEFAULT } end
	table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return list
end

local function combatLabel() return _G.COMBAT or "Combat" end

local function getCombatText(inCombat)
	local key = inCombat and "combatTextEnter" or "combatTextLeave"
	local text = L[key]
	if type(text) == "string" and text ~= "" and text ~= key then return text end
	return (inCombat and "+" or "-") .. combatLabel()
end

function CombatText:GetDuration() return clamp(getValue(DB_DURATION, defaults.duration), 0.5, 10) end

function CombatText:GetFontSize() return clamp(getValue(DB_FONT_SIZE, defaults.fontSize), 8, 96) end

function CombatText:GetFontFace()
	local face = normalizeFontFace(getValue(DB_FONT, defaults.fontFace))
	if not face then face = defaultFontFace() end
	return face
end

function CombatText:GetEnterColor()
	local fallback = defaults.enterColor or defaults.color
	local value = getValue(DB_ENTER_COLOR, getValue(DB_COLOR, fallback))
	return normalizeColor(value, fallback)
end

function CombatText:GetLeaveColor()
	local fallback = defaults.leaveColor or defaults.enterColor or defaults.color
	local value = getValue(DB_LEAVE_COLOR, getValue(DB_COLOR, fallback))
	return normalizeColor(value, fallback)
end

function CombatText:GetColor() return self:GetEnterColor() end

function CombatText:ApplyStyle(r, g, b, a)
	if not self.frame or not self.frame.text then return end
	local font = self:GetFontFace()
	local size = self:GetFontSize()
	local ok = self.frame.text:SetFont(font, size, "OUTLINE")
	if not ok then self.frame.text:SetFont(defaultFontFace(), size, "OUTLINE") end
	if r == nil or g == nil or b == nil then
		r, g, b, a = self:GetEnterColor()
	end
	self.frame.text:SetTextColor(r, g, b, a or 1)
end

function CombatText:UpdateFrameSize()
	if not self.frame or not self.frame.text then return end
	local width = self.frame.text:GetStringWidth()
	local height = self.frame.text:GetStringHeight()
	if width < 1 then width = 1 end
	if height < 1 then height = 1 end
	self.frame:SetSize(width + PREVIEW_PADDING_X, height + PREVIEW_PADDING_Y)
	if self.frame.bg then self.frame.bg:SetAllPoints(self.frame) end
end

function CombatText:EnsureFrame()
	if self.frame then return self.frame end

	local frame = CreateFrame("Frame", "EQOL_CombatText", UIParent)
	frame:SetClampedToScreen(true)
	frame:SetFrameStrata("HIGH")
	frame:Hide()

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(frame)
	bg:SetColorTexture(0.1, 0.1, 0.1, 0.4)
	bg:Hide()
	frame.bg = bg

	local text = frame:CreateFontString(nil, "OVERLAY")
	text:SetPoint("CENTER")
	text:SetJustifyH("CENTER")
	text:SetJustifyV("MIDDLE")
	frame.text = text

	self.frame = frame
	self:ApplyStyle()
	self:UpdateFrameSize()

	return frame
end

function CombatText:CancelHideTimer()
	if self.hideTimer then
		self.hideTimer:Cancel()
		self.hideTimer = nil
	end
end

function CombatText:SetText(text)
	if not self.frame or not self.frame.text then return end
	self.frame.text:SetText(text or "")
	self:UpdateFrameSize()
end

function CombatText:ShowText(text, r, g, b, a)
	local frame = self:EnsureFrame()
	if not frame then return end
	self:CancelHideTimer()
	self:ApplyStyle(r, g, b, a)
	self:SetText(text)
	frame:Show()
	local duration = self:GetDuration()
	if duration > 0 then self.hideTimer = C_Timer.NewTimer(duration, function()
		CombatText.hideTimer = nil
		CombatText:HideText()
	end) end
end

function CombatText:HideText()
	self:CancelHideTimer()
	if self.previewing then return end
	if self.frame then self.frame:Hide() end
end

function CombatText:ShowCombatText(inCombat)
	if self.previewing then return end
	local r, g, b, a
	if inCombat then
		r, g, b, a = self:GetEnterColor()
	else
		r, g, b, a = self:GetLeaveColor()
	end
	self:ShowText(getCombatText(inCombat), r, g, b, a)
end

function CombatText:ShowEditModeHint(show)
	if not self.frame then return end
	if show then
		self.previewing = true
		self:CancelHideTimer()
		if self.frame.bg then self.frame.bg:Show() end
		local r, g, b, a = self:GetEnterColor()
		self:ApplyStyle(r, g, b, a)
		self:SetText(getCombatText(true))
		self.frame:Show()
	else
		self.previewing = nil
		if self.frame.bg then self.frame.bg:Hide() end
		self:HideText()
	end
end

function CombatText:OnEvent(event)
	if event == "PLAYER_REGEN_DISABLED" then
		self:ShowCombatText(true)
	elseif event == "PLAYER_REGEN_ENABLED" then
		self:ShowCombatText(false)
	end
end

function CombatText:RegisterEvents()
	if self.eventsRegistered then return end
	local frame = self:EnsureFrame()
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	frame:SetScript("OnEvent", function(_, event) CombatText:OnEvent(event) end)
	self.eventsRegistered = true
end

function CombatText:UnregisterEvents()
	if not self.eventsRegistered or not self.frame then return end
	self.frame:UnregisterEvent("PLAYER_REGEN_DISABLED")
	self.frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self.frame:SetScript("OnEvent", nil)
	self.eventsRegistered = false
end

function CombatText:ApplyLayoutData(data)
	if not data or not addon.db then return end

	local duration = clamp(data.duration or defaults.duration, 0.5, 10)
	local fontSize = clamp(data.fontSize or defaults.fontSize, 8, 96)
	local fontFace = normalizeFontFace(data.fontFace) or defaultFontFace()
	local enterR, enterG, enterB, enterA = normalizeColor(data.enterColor or data.color or defaults.enterColor, defaults.enterColor)
	local leaveR, leaveG, leaveB, leaveA = normalizeColor(data.leaveColor or data.enterColor or data.color or defaults.leaveColor, defaults.leaveColor)

	addon.db[DB_DURATION] = duration
	addon.db[DB_FONT_SIZE] = fontSize
	addon.db[DB_FONT] = fontFace
	addon.db[DB_ENTER_COLOR] = { r = enterR, g = enterG, b = enterB, a = enterA }
	addon.db[DB_LEAVE_COLOR] = { r = leaveR, g = leaveG, b = leaveB, a = leaveA }
	addon.db[DB_COLOR] = { r = enterR, g = enterG, b = enterB, a = enterA }

	self:ApplyStyle()
	self:UpdateFrameSize()
end

local function applySetting(field, value)
	if not addon.db then return end

	if field == "duration" then
		local duration = clamp(value, 0.5, 10)
		addon.db[DB_DURATION] = duration
		value = duration
	elseif field == "fontSize" then
		local fontSize = clamp(value, 8, 96)
		addon.db[DB_FONT_SIZE] = fontSize
		value = fontSize
	elseif field == "fontFace" then
		local fontFace = normalizeFontFace(value) or defaultFontFace()
		addon.db[DB_FONT] = fontFace
		value = fontFace
	elseif field == "enterColor" then
		local r, g, b, a = normalizeColor(value, defaults.enterColor)
		addon.db[DB_ENTER_COLOR] = { r = r, g = g, b = b, a = a }
		addon.db[DB_COLOR] = { r = r, g = g, b = b, a = a }
		value = addon.db[DB_ENTER_COLOR]
	elseif field == "leaveColor" then
		local r, g, b, a = normalizeColor(value, defaults.leaveColor)
		addon.db[DB_LEAVE_COLOR] = { r = r, g = g, b = b, a = a }
		value = addon.db[DB_LEAVE_COLOR]
	elseif field == "color" then
		local r, g, b, a = normalizeColor(value, defaults.enterColor)
		addon.db[DB_COLOR] = { r = r, g = g, b = b, a = a }
		addon.db[DB_ENTER_COLOR] = { r = r, g = g, b = b, a = a }
		addon.db[DB_LEAVE_COLOR] = { r = r, g = g, b = b, a = a }
		value = addon.db[DB_ENTER_COLOR]
	end

	if EditMode and EditMode.SetValue then EditMode:SetValue(EDITMODE_ID, field, value, nil, true) end
	CombatText:ApplyStyle()
	CombatText:UpdateFrameSize()
end

local editModeRegistered = false

function CombatText:RegisterEditMode()
	if editModeRegistered or not EditMode or not EditMode.RegisterFrame then return end

	local settings
	if SettingType then
		settings = {
			{
				name = L["combatTextDuration"] or "Display duration",
				kind = SettingType.Slider,
				field = "duration",
				default = defaults.duration,
				minValue = 0.5,
				maxValue = 10,
				valueStep = 0.1,
				get = function() return CombatText:GetDuration() end,
				set = function(_, value) applySetting("duration", value) end,
				formatter = function(value) return string.format("%.1fs", tonumber(value) or 0) end,
			},
			{
				name = L["combatTextFontSize"] or "Font size",
				kind = SettingType.Slider,
				field = "fontSize",
				default = defaults.fontSize,
				minValue = 8,
				maxValue = 96,
				valueStep = 1,
				get = function() return CombatText:GetFontSize() end,
				set = function(_, value) applySetting("fontSize", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = L["combatTextFont"] or "Font",
				kind = SettingType.Dropdown,
				field = "fontFace",
				height = 200,
				get = function() return CombatText:GetFontFace() end,
				set = function(_, value) applySetting("fontFace", value) end,
				generator = function(_, root)
					for _, option in ipairs(fontFaceOptions()) do
						root:CreateRadio(option.label, function() return CombatText:GetFontFace() == option.value end, function() applySetting("fontFace", option.value) end)
					end
				end,
			},
			{
				name = L["combatTextEnterColor"] or "Entering combat color",
				kind = SettingType.Color,
				field = "enterColor",
				default = defaults.enterColor,
				hasOpacity = true,
				get = function()
					local r, g, b, a = CombatText:GetEnterColor()
					return { r = r, g = g, b = b, a = a }
				end,
				set = function(_, value) applySetting("enterColor", value) end,
			},
			{
				name = L["combatTextLeaveColor"] or "Leaving combat color",
				kind = SettingType.Color,
				field = "leaveColor",
				default = defaults.leaveColor,
				hasOpacity = true,
				get = function()
					local r, g, b, a = CombatText:GetLeaveColor()
					return { r = r, g = g, b = b, a = a }
				end,
				set = function(_, value) applySetting("leaveColor", value) end,
			},
		}
	end

	EditMode:RegisterFrame(EDITMODE_ID, {
		frame = self:EnsureFrame(),
		title = L["CombatText"] or "Combat text",
		layoutDefaults = {
			point = "CENTER",
			relativePoint = "CENTER",
			x = 0,
			y = 120,
			duration = self:GetDuration(),
			fontSize = self:GetFontSize(),
			fontFace = self:GetFontFace(),
			enterColor = (function()
				local r, g, b, a = self:GetEnterColor()
				return { r = r, g = g, b = b, a = a }
			end)(),
			leaveColor = (function()
				local r, g, b, a = self:GetLeaveColor()
				return { r = r, g = g, b = b, a = a }
			end)(),
		},
		onApply = function(_, _, data) CombatText:ApplyLayoutData(data) end,
		onEnter = function() CombatText:ShowEditModeHint(true) end,
		onExit = function() CombatText:ShowEditModeHint(false) end,
		isEnabled = function() return addon.db and addon.db[DB_ENABLED] end,
		settings = settings,
		showOutsideEditMode = false,
		showReset = false,
		showSettingsReset = false,
		enableOverlayToggle = true,
	})

	editModeRegistered = true
end

function CombatText:OnSettingChanged(enabled)
	if enabled then
		self:EnsureFrame()
		self:RegisterEditMode()
		self:RegisterEvents()
		self:ApplyStyle()
	else
		self:UnregisterEvents()
		self.previewing = nil
		if self.frame and self.frame.bg then self.frame.bg:Hide() end
		self:HideText()
	end

	if EditMode and EditMode.RefreshFrame then EditMode:RefreshFrame(EDITMODE_ID) end
end

return CombatText
