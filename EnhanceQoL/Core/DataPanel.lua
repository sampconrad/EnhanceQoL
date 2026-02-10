local addonName, addon = ...
addon.DataPanel = addon.DataPanel or {}
local DataPanel = addon.DataPanel
local DataHub = addon.DataHub
local L = addon.L
local EditMode = addon.EditMode
local SettingType = EditMode and EditMode.lib and EditMode.lib.SettingType
local LSM = LibStub("LibSharedMedia-3.0", true)

local DEFAULT_TEXT_ALPHA = 100
local DEFAULT_BACKDROP_ALPHA = 0.5
local DEFAULT_BORDER_ALPHA = 1
local DEFAULT_BORDER_SIZE = 16
local DEFAULT_BORDER_OFFSET = 0
local DEFAULT_FONT_OUTLINE = true
local DEFAULT_FONT_SHADOW = false
local DEFAULT_STREAM_GAP = 5
local DEFAULT_STREAM_FONT_SCALE = 100
local SHADOW_OFFSET_X = 1
local SHADOW_OFFSET_Y = -1
local SHADOW_ALPHA = 0.8
local DEFAULT_BACKGROUND_TEXTURE = "Interface/Tooltips/UI-Tooltip-Background"
local DEFAULT_BORDER_TEXTURE = "Interface/Tooltips/UI-Tooltip-Border"
local SOLID_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local DEFAULT_BACKDROP_COLOR = { r = 0, g = 0, b = 0, a = DEFAULT_BACKDROP_ALPHA }
local DEFAULT_BORDER_COLOR = { r = 1, g = 1, b = 1, a = DEFAULT_BORDER_ALPHA }
local BACKDROP_INSET = 4

local DELETE_BUTTON_LABEL = L["DataPanelDelete"] or "Delete panel"
local DELETE_CONFIRM_TEXT = L["DataPanelDeleteConfirm"] or 'Are you sure you want to delete "%s"? This cannot be undone.'

local DELETE_PANEL_POPUP = addonName .. "DeleteDataPanel"
if not StaticPopupDialogs[DELETE_PANEL_POPUP] then
	StaticPopupDialogs[DELETE_PANEL_POPUP] = {
		text = DELETE_CONFIRM_TEXT,
		button1 = YES,
		button2 = CANCEL,
		showAlert = true,
		hideOnEscape = true,
		timeout = 0,
		whileDead = 1,
		preferredIndex = 3,
		OnAccept = function(self)
			if self.data then DataPanel.Delete(self.data) end
		end,
	}
end

local panels = {}
local STRATA_ORDER = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
local VALID_STRATA = {}
for _, strata in ipairs(STRATA_ORDER) do
	VALID_STRATA[strata] = true
end
local STRATA_INDEX = {}
for index, strata in ipairs(STRATA_ORDER) do
	STRATA_INDEX[strata] = index
end
local CONTENT_ANCHOR_ORDER = { "LEFT", "CENTER", "RIGHT" }
local VALID_CONTENT_ANCHOR = {}
for _, anchor in ipairs(CONTENT_ANCHOR_ORDER) do
	VALID_CONTENT_ANCHOR[anchor] = true
end
local CONTENT_ANCHOR_OPTIONS = {
	{ value = "LEFT", label = L["LEFT"] or "Left" },
	{ value = "CENTER", label = L["CENTER"] or "Center" },
	{ value = "RIGHT", label = L["RIGHT"] or "Right" },
}

local function normalizePercent(value, fallback)
	local num = tonumber(value)
	if not num then num = tonumber(fallback) end
	if not num then return DEFAULT_TEXT_ALPHA end
	if num < 0 then return 0 end
	if num > 100 then return 100 end
	return num
end

local function clamp(value, minV, maxV)
	if value < minV then return minV end
	if value > maxV then return maxV end
	return value
end

local function normalizeStreamGap(value, fallback)
	local num = tonumber(value)
	if not num then num = tonumber(fallback) end
	if not num then return DEFAULT_STREAM_GAP end
	if num < 0 then return 0 end
	if num > 100 then return 100 end
	return num
end

local function normalizeStreamFontScale(value, fallback)
	local num = tonumber(value)
	if not num then num = tonumber(fallback) end
	if not num then return DEFAULT_STREAM_FONT_SCALE end
	if num < 50 then return 50 end
	if num > 200 then return 200 end
	return num
end

local function normalizeBorderSize(value, fallback)
	local num = tonumber(value)
	if not num then num = tonumber(fallback) end
	if not num then return DEFAULT_BORDER_SIZE end
	return clamp(num, 1, 64)
end

local function normalizeBorderOffset(value, fallback)
	local num = tonumber(value)
	if not num then num = tonumber(fallback) end
	if not num then return DEFAULT_BORDER_OFFSET end
	return clamp(num, -20, 20)
end

local function defaultFontFace() return (addon.variables and addon.variables.defaultFont) or STANDARD_TEXT_FONT end

local function normalizeFontFace(value)
	if type(value) ~= "string" or value == "" then return nil end
	return value
end

local function normalizeMediaKey(value, fallback)
	if type(value) ~= "string" or value == "" then return fallback end
	return value
end

local function normalizeColorTable(value, fallback)
	local r, g, b, a
	if type(value) == "table" then
		r = value.r or value[1]
		g = value.g or value[2]
		b = value.b or value[3]
		a = value.a or value[4]
	elseif type(value) == "number" then
		r, g, b, a = value, value, value, 1
	end
	fallback = fallback or DEFAULT_BACKDROP_COLOR
	r = r or fallback.r or fallback[1] or 1
	g = g or fallback.g or fallback[2] or 1
	b = b or fallback.b or fallback[3] or 1
	a = a or fallback.a or fallback[4] or 1
	return { r = r, g = g, b = b, a = a }
end

local function colorsEqual(a, b)
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	local ar, ag, ab, aa = a.r or a[1], a.g or a[2], a.b or a[3], a.a or a[4]
	local br, bg, bb, ba = b.r or b[1], b.g or b[2], b.b or b[3], b.a or b[4]
	return ar == br and ag == bg and ab == bb and aa == ba
end

local function resolveBackgroundTexture(key)
	if key == "SOLID" then return SOLID_TEXTURE end
	if not key or key == "" or key == "DEFAULT" then return DEFAULT_BACKGROUND_TEXTURE end
	if LSM and LSM.Fetch then
		local tex = LSM:Fetch("background", key, true)
		if tex and tex ~= "" then return tex end
	end
	return key
end

local function resolveBorderTexture(key)
	if key == "SOLID" then return SOLID_TEXTURE end
	if not key or key == "" or key == "DEFAULT" then return DEFAULT_BORDER_TEXTURE end
	if LSM and LSM.Fetch then
		local tex = LSM:Fetch("border", key, true)
		if tex and tex ~= "" then return tex end
	end
	return key
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

local function backgroundTextureOptions()
	local list = {}
	local seen = {}
	local function add(value, label)
		local lv = tostring(value or ""):lower()
		if lv == "" or seen[lv] then return end
		seen[lv] = true
		list[#list + 1] = { value = value, label = label }
	end
	add("DEFAULT", _G.DEFAULT or "Default")
	add("SOLID", "Solid")
	if LSM and LSM.HashTable then
		for name, path in pairs(LSM:HashTable("background") or {}) do
			if type(path) == "string" and path ~= "" then add(name, tostring(name)) end
		end
	end
	table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return list
end

local function borderTextureOptions()
	local list = {}
	local seen = {}
	local function add(value, label)
		local lv = tostring(value or ""):lower()
		if lv == "" or seen[lv] then return end
		seen[lv] = true
		list[#list + 1] = { value = value, label = label }
	end
	add("DEFAULT", _G.DEFAULT or "Default")
	add("SOLID", "Solid")
	if LSM and LSM.HashTable then
		for name, path in pairs(LSM:HashTable("border") or {}) do
			if type(path) == "string" and path ~= "" then add(name, tostring(name)) end
		end
	end
	table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return list
end

local function slotTooltipsEnabled(slot)
	local panel = slot and slot.panel
	return not (panel and panel.info and panel.info.showTooltips == false)
end

local fadeWatcher
local function ensureFadeWatcher()
	if fadeWatcher then return end
	fadeWatcher = CreateFrame("Frame")
	fadeWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	fadeWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	fadeWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	fadeWatcher:SetScript("OnEvent", function(_, event)
		local inCombat
		if event == "PLAYER_REGEN_ENABLED" then
			inCombat = false
		elseif event == "PLAYER_REGEN_DISABLED" then
			inCombat = true
		end
		for _, panel in pairs(panels) do
			if panel and panel.ApplyAlpha then panel:ApplyAlpha(inCombat) end
		end
	end)
end

local function normalizeStrata(strata, fallback)
	if type(strata) == "string" then
		local upper = string.upper(strata)
		if VALID_STRATA[upper] then return upper end
	end
	if type(fallback) == "string" then
		local upper = string.upper(fallback)
		if VALID_STRATA[upper] then return upper end
	end
	return "MEDIUM"
end

local function normalizeContentAnchor(anchor, fallback)
	if type(anchor) == "string" then
		local upper = string.upper(anchor)
		if VALID_CONTENT_ANCHOR[upper] then return upper end
	end
	if type(fallback) == "string" then
		local upper = string.upper(fallback)
		if VALID_CONTENT_ANCHOR[upper] then return upper end
	end
	return "LEFT"
end

local function hasInlineTexture(text)
	if type(text) ~= "string" then return false end
	return text:find("|T", 1, true) or text:find("|A", 1, true)
end

local function scheduleInlineReflowAll()
	for _, panel in pairs(panels) do
		if panel and panel.ScheduleTextReflow then panel:ScheduleTextReflow() end
	end
end

local function updateSelectionStrata(panel, targetStrata)
	if not panel or not panel.frame then return end
	local selection = panel.frame.Selection
	if not selection or not selection.SetFrameStrata then return end
	if not panel._selectionBaseStrata then
		local baseStrata = (selection.GetFrameStrata and selection:GetFrameStrata()) or "MEDIUM"
		panel._selectionBaseStrata = baseStrata
		panel._selectionBaseStrataIndex = STRATA_INDEX[baseStrata] or STRATA_INDEX.MEDIUM
	end
	local baseIndex = panel._selectionBaseStrataIndex or STRATA_INDEX.MEDIUM
	local normalized = normalizeStrata(targetStrata, panel._selectionBaseStrata)
	local targetIndex = STRATA_INDEX[normalized]
	local targetStrataFinal = (targetIndex and targetIndex > baseIndex) and normalized or panel._selectionBaseStrata
	if targetStrataFinal and selection.GetFrameStrata and selection:GetFrameStrata() ~= targetStrataFinal then selection:SetFrameStrata(targetStrataFinal) end
end

local STRATA_DROPDOWN_VALUES = {}
for _, strata in ipairs(STRATA_ORDER) do
	STRATA_DROPDOWN_VALUES[#STRATA_DROPDOWN_VALUES + 1] = { text = strata, isRadio = true }
end

local function copyList(source)
	local result = {}
	if source then
		for i, v in ipairs(source) do
			result[i] = v
		end
	end
	return result
end

local function streamDisplayName(name)
	local stream = DataHub and DataHub.streams and DataHub.streams[name]
	if stream and stream.meta then return stream.meta.title or stream.meta.name or name end
	return name
end

local function sortedStreams()
	local list = {}
	if DataHub and DataHub.streams then
		for name in pairs(DataHub.streams) do
			list[#list + 1] = name
		end
	end
	table.sort(list, function(a, b) return streamDisplayName(a) < streamDisplayName(b) end)
	return list
end

local function shouldShowOptionsHint()
	local opts = addon.db and addon.db.dataPanelsOptions
	return not (opts and opts.hideRightClickHint)
end

function DataPanel.ShouldShowOptionsHint() return shouldShowOptionsHint() end

function DataPanel.GetOptionsHintText()
	if shouldShowOptionsHint() then return L["Right-Click for options"] end
end

function DataPanel.GetStreamOptionsTitle(streamTitle)
	local optionsTitle = GAMEMENU_OPTIONS or OPTIONS or "Options"
	if streamTitle and streamTitle ~= "" then return tostring(streamTitle) .. " - " .. optionsTitle end
	return optionsTitle
end

local function partsOnEnter(b)
	local s = b.slot
	if not s then return end
	if not slotTooltipsEnabled(s) then return end
	GameTooltip:SetOwner(b, "ANCHOR_TOPLEFT")
	if s.perCurrency and b.currencyID then
		GameTooltip:SetCurrencyByID(b.currencyID)
		if s.showDescription == false then
			local info = C_CurrencyInfo.GetCurrencyInfo(b.currencyID)
			if info and info.description and info.description ~= "" then
				local name = GameTooltip:GetName()
				for i = 2, GameTooltip:NumLines() do
					local line = _G[name .. "TextLeft" .. i]
					if line and line:GetText() == info.description then
						line:SetText("")
						break
					end
				end
			end
		end
		local hint = DataPanel.GetOptionsHintText and DataPanel.GetOptionsHintText()
		if hint then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(hint)
		end
	elseif s.tooltip then
		GameTooltip:SetText(s.tooltip)
	end
	GameTooltip:Show()
end

local function partsOnLeave() GameTooltip:Hide() end

local function partsOnClick(b, btn, ...)
	local s = b.slot
	if btn == "RightButton" and not (s and s.ignoreMenuModifier) and not DataPanel.IsMenuModifierActive(btn) then return end
	if not s then return end
	local fn = s.OnClick
	if type(fn) == "table" then fn = fn[btn] end
	if fn then fn(b, btn, ...) end
end

local pendingSecure = {}
local pendingSecureFrame

local function queueSecureUpdate(data)
	if not data then return end
	pendingSecure[data] = true
	if not pendingSecureFrame then
		pendingSecureFrame = CreateFrame("Frame")
		pendingSecureFrame:SetScript("OnEvent", function()
			if InCombatLockdown and InCombatLockdown() then return end
			for entry in pairs(pendingSecure) do
				pendingSecure[entry] = nil
				local payload = entry.pendingPayload
				entry.pendingPayload = nil
				if entry.applyPayload and payload then entry.applyPayload(payload, true) end
			end
			if not next(pendingSecure) then pendingSecureFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
		end)
	end
	pendingSecureFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function payloadHasSecureParts(payload)
	if not payload or not payload.parts then return false end
	for _, part in ipairs(payload.parts) do
		if part and part.secure then return true end
	end
	return false
end

local function registerEditModePanel(panel)
	if not EditMode or not EditMode.RegisterFrame then return end
	if panel.editModeRegistered then
		if panel.editModeId then EditMode:RefreshFrame(panel.editModeId) end
		return
	end

	local id = "dataPanel:" .. tostring(panel.id)
	panel.frame.editModeName = panel.name

	local defaults = {
		point = panel.info.point or "CENTER",
		x = panel.info.x or 0,
		y = panel.info.y or 0,
		width = panel.info.width or panel.frame:GetWidth() or 200,
		height = panel.info.height or panel.frame:GetHeight() or 20,
		hideBorder = panel.info.hideBorder or false,
		clickThrough = panel.info.clickThrough == true,
		strata = normalizeStrata(panel.info.strata, panel.frame:GetFrameStrata()),
		contentAnchor = normalizeContentAnchor(panel.info.contentAnchor, "LEFT"),
		streams = copyList(panel.info.streams),
		streamGap = normalizeStreamGap(panel.info.streamGap, DEFAULT_STREAM_GAP),
		fontOutline = panel.info.fontOutline ~= false,
		fontShadow = panel.info.fontShadow == true,
		streamFontScale = normalizeStreamFontScale(panel.info.streamFontScale, DEFAULT_STREAM_FONT_SCALE),
		useClassTextColor = panel.info.useClassTextColor == true,
		fontFace = normalizeFontFace(panel.info.fontFace) or defaultFontFace(),
		backgroundTexture = normalizeMediaKey(panel.info.backgroundTexture, "DEFAULT"),
		backgroundColor = normalizeColorTable(panel.info.backgroundColor, DEFAULT_BACKDROP_COLOR),
		borderTexture = normalizeMediaKey(panel.info.borderTexture, "DEFAULT"),
		borderColor = normalizeColorTable(panel.info.borderColor, DEFAULT_BORDER_COLOR),
		borderSize = normalizeBorderSize(panel.info.borderSize, DEFAULT_BORDER_SIZE),
		borderOffset = normalizeBorderOffset(panel.info.borderOffset, DEFAULT_BORDER_OFFSET),
		showTooltips = panel.info.showTooltips ~= false,
		textAlphaInCombat = normalizePercent(panel.info.textAlphaInCombat, DEFAULT_TEXT_ALPHA),
		textAlphaOutOfCombat = normalizePercent(panel.info.textAlphaOutOfCombat, panel.info.textAlphaInCombat),
	}
	panel.info.strata = defaults.strata
	panel.info.contentAnchor = defaults.contentAnchor
	panel.info.fontFace = defaults.fontFace
	panel.info.backgroundTexture = defaults.backgroundTexture
	panel.info.backgroundColor = defaults.backgroundColor
	panel.info.borderTexture = defaults.borderTexture
	panel.info.borderColor = defaults.borderColor
	panel.info.borderSize = defaults.borderSize
	panel.info.borderOffset = defaults.borderOffset
	panel.info.showTooltips = defaults.showTooltips
	panel.info.streamGap = defaults.streamGap

	local settings
	if SettingType then
		local function isBorderVisible(layoutName)
			if EditMode and EditMode.GetValue then
				local value = EditMode:GetValue(id, "hideBorder", layoutName)
				if value ~= nil then return not value end
			end
			return not (panel.info and panel.info.hideBorder)
		end
		local function isClickThrough(layoutName)
			if EditMode and EditMode.GetValue then
				local value = EditMode:GetValue(id, "clickThrough", layoutName)
				if value ~= nil then return value == true end
			end
			return panel.info and panel.info.clickThrough == true
		end

		settings = {
			{
				name = L["DataPanelWidth"],
				kind = SettingType.Slider,
				field = "width",
				default = defaults.width,
				minValue = 50,
				maxValue = 800,
				valueStep = 1,
			},
			{
				name = L["DataPanelHeight"],
				kind = SettingType.Slider,
				field = "height",
				default = defaults.height,
				minValue = 16,
				maxValue = 800,
				valueStep = 1,
			},
			{
				name = L["DataPanelBackgroundTexture"] or "Background texture",
				kind = SettingType.Dropdown,
				field = "backgroundTexture",
				default = defaults.backgroundTexture,
				height = 200,
				get = function(layoutName)
					if EditMode and EditMode.GetValue then return EditMode:GetValue(id, "backgroundTexture", layoutName) end
					return panel.info and panel.info.backgroundTexture or defaults.backgroundTexture
				end,
				set = function(layoutName, value)
					if EditMode and EditMode.SetValue then
						EditMode:SetValue(id, "backgroundTexture", value, layoutName)
					elseif panel.info then
						panel.info.backgroundTexture = normalizeMediaKey(value, "DEFAULT")
						panel:ApplyBorder()
					end
				end,
				generator = function(_, rootDescription, data)
					for _, option in ipairs(backgroundTextureOptions()) do
						rootDescription:CreateRadio(option.label, function() return data.get and data.get(nil) == option.value end, function()
							if data.set then data.set(nil, option.value) end
						end)
					end
				end,
			},
			{
				name = L["DataPanelBackgroundColor"] or "Background color",
				kind = SettingType.Color,
				field = "backgroundColor",
				default = defaults.backgroundColor,
				hasOpacity = true,
				get = function(layoutName)
					if EditMode and EditMode.GetValue then return EditMode:GetValue(id, "backgroundColor", layoutName) end
					return panel.info and panel.info.backgroundColor or defaults.backgroundColor
				end,
				set = function(layoutName, value)
					if EditMode and EditMode.SetValue then
						EditMode:SetValue(id, "backgroundColor", value, layoutName)
					elseif panel.info then
						panel.info.backgroundColor = normalizeColorTable(value, DEFAULT_BACKDROP_COLOR)
						panel:ApplyBackdropAlpha()
					end
				end,
			},
			{
				name = L["DataPanelHideBorder"],
				kind = SettingType.Checkbox,
				field = "hideBorder",
				default = defaults.hideBorder,
			},
			{
				name = L["DataPanelBorderTexture"] or "Border texture",
				kind = SettingType.Dropdown,
				field = "borderTexture",
				default = defaults.borderTexture,
				height = 200,
				get = function(layoutName)
					if EditMode and EditMode.GetValue then return EditMode:GetValue(id, "borderTexture", layoutName) end
					return panel.info and panel.info.borderTexture or defaults.borderTexture
				end,
				set = function(layoutName, value)
					if EditMode and EditMode.SetValue then
						EditMode:SetValue(id, "borderTexture", value, layoutName)
					elseif panel.info then
						panel.info.borderTexture = normalizeMediaKey(value, "DEFAULT")
						panel:ApplyBorder()
					end
				end,
				generator = function(_, rootDescription, data)
					for _, option in ipairs(borderTextureOptions()) do
						rootDescription:CreateRadio(option.label, function() return data.get and data.get(nil) == option.value end, function()
							if data.set then data.set(nil, option.value) end
						end)
					end
				end,
				isEnabled = isBorderVisible,
			},
			{
				name = L["DataPanelBorderSize"] or "Border size",
				kind = SettingType.Slider,
				field = "borderSize",
				default = defaults.borderSize,
				minValue = 1,
				maxValue = 64,
				valueStep = 1,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
				isEnabled = isBorderVisible,
			},
			{
				name = L["DataPanelBorderOffset"] or "Border offset",
				kind = SettingType.Slider,
				field = "borderOffset",
				default = defaults.borderOffset,
				minValue = -20,
				maxValue = 20,
				valueStep = 1,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
				isEnabled = isBorderVisible,
			},
			{
				name = L["DataPanelBorderColor"] or "Border color",
				kind = SettingType.Color,
				field = "borderColor",
				default = defaults.borderColor,
				hasOpacity = true,
				get = function(layoutName)
					if EditMode and EditMode.GetValue then return EditMode:GetValue(id, "borderColor", layoutName) end
					return panel.info and panel.info.borderColor or defaults.borderColor
				end,
				set = function(layoutName, value)
					if EditMode and EditMode.SetValue then
						EditMode:SetValue(id, "borderColor", value, layoutName)
					elseif panel.info then
						panel.info.borderColor = normalizeColorTable(value, DEFAULT_BORDER_COLOR)
						panel:ApplyBackdropAlpha()
					end
				end,
				isEnabled = isBorderVisible,
			},
			{
				name = L["DataPanelClickThrough"] or "Click-through",
				kind = SettingType.Checkbox,
				field = "clickThrough",
				default = defaults.clickThrough,
			},
			{
				name = L["DataPanelShowTooltips"] or "Show tooltips",
				kind = SettingType.Checkbox,
				field = "showTooltips",
				default = defaults.showTooltips,
				isEnabled = function(layoutName) return not isClickThrough(layoutName) end,
			},
			{
				name = L["DataPanelStrata"],
				kind = SettingType.Dropdown,
				field = "strata",
				default = defaults.strata,
				values = STRATA_DROPDOWN_VALUES,
			},
			{
				name = L["DataPanelStreams"],
				kind = SettingType.Dropdown,
				field = "streams",
				default = copyList(defaults.streams),
				height = 240,
				get = function() return copyList(panel.info.streams) end,
				set = function(_, value)
					panel.applyingFromEditMode = true
					panel:ApplyStreams(copyList(value) or {})
					panel.applyingFromEditMode = nil
				end,
				generator = function(_, rootDescription)
					for _, streamName in ipairs(sortedStreams()) do
						rootDescription:CreateCheckbox(streamDisplayName(streamName), function() return panel.info.streamSet and panel.info.streamSet[streamName] end, function()
							local enabled = panel.info.streamSet and panel.info.streamSet[streamName]
							if enabled then
								panel:RemoveStream(streamName)
							else
								panel:AddStream(streamName)
							end
						end)
					end
				end,
			},
			{
				name = L["DataPanelStreamGap"] or "Stream gap",
				kind = SettingType.Slider,
				field = "streamGap",
				default = defaults.streamGap,
				minValue = 0,
				maxValue = 100,
				valueStep = 1,
			},
			{
				name = L["DataPanelContentAlignment"] or "Content alignment",
				kind = SettingType.Dropdown,
				field = "contentAnchor",
				default = defaults.contentAnchor,
				get = function(layoutName)
					if EditMode and EditMode.GetValue then return EditMode:GetValue(id, "contentAnchor", layoutName) end
					return panel.info and panel.info.contentAnchor or defaults.contentAnchor
				end,
				set = function(layoutName, value)
					if EditMode and EditMode.SetValue then
						EditMode:SetValue(id, "contentAnchor", value, layoutName)
					elseif panel.info then
						panel.info.contentAnchor = normalizeContentAnchor(value, panel.info.contentAnchor)
						panel:Refresh()
					end
				end,
				generator = function(_, rootDescription, data)
					for _, option in ipairs(CONTENT_ANCHOR_OPTIONS) do
						rootDescription:CreateRadio(option.label, function() return data.get and data.get(nil) == option.value end, function()
							if data.set then data.set(nil, option.value) end
						end)
					end
				end,
			},
			{
				name = L["DataPanelFontFace"] or "Font",
				kind = SettingType.Dropdown,
				field = "fontFace",
				default = defaults.fontFace,
				height = 200,
				get = function(layoutName)
					if EditMode and EditMode.GetValue then return EditMode:GetValue(id, "fontFace", layoutName) end
					return panel.info and panel.info.fontFace or defaults.fontFace
				end,
				set = function(layoutName, value)
					if EditMode and EditMode.SetValue then
						EditMode:SetValue(id, "fontFace", value, layoutName)
					elseif panel.info then
						panel.info.fontFace = normalizeFontFace(value) or defaultFontFace()
						panel:ApplyTextStyle()
					end
				end,
				generator = function(_, rootDescription, data)
					for _, option in ipairs(fontFaceOptions()) do
						rootDescription:CreateRadio(option.label, function() return data.get and data.get(nil) == option.value end, function()
							if data.set then data.set(nil, option.value) end
						end)
					end
				end,
			},
			{
				name = L["DataPanelTextOutline"] or "Text outline",
				kind = SettingType.Checkbox,
				field = "fontOutline",
				default = defaults.fontOutline,
			},
			{
				name = L["DataPanelTextShadow"] or "Text shadow",
				kind = SettingType.Checkbox,
				field = "fontShadow",
				default = defaults.fontShadow,
			},
			{
				name = L["DataPanelTextScale"] or "Text scale",
				kind = SettingType.Slider,
				field = "streamFontScale",
				default = defaults.streamFontScale,
				minValue = 50,
				maxValue = 200,
				valueStep = 1,
				formatter = function(value) return string.format("%d%%", math.floor((tonumber(value) or 100) + 0.5)) end,
			},
			{
				name = L["DataPanelUseClassTextColor"] or "Use class text color",
				kind = SettingType.Checkbox,
				field = "useClassTextColor",
				default = defaults.useClassTextColor,
			},
			{
				name = L["DataPanelOpacityInCombat"] or "Opacity in combat",
				kind = SettingType.Slider,
				field = "textAlphaInCombat",
				default = defaults.textAlphaInCombat,
				minValue = 0,
				maxValue = 100,
				valueStep = 1,
				formatter = function(value) return string.format("%d%%", math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = L["DataPanelOpacityOutOfCombat"] or "Opacity out of combat",
				kind = SettingType.Slider,
				field = "textAlphaOutOfCombat",
				default = defaults.textAlphaOutOfCombat,
				minValue = 0,
				maxValue = 100,
				valueStep = 1,
				formatter = function(value) return string.format("%d%%", math.floor((tonumber(value) or 0) + 0.5)) end,
			},
		}
	end

	local buttons = {
		{
			text = DELETE_BUTTON_LABEL,
			click = function() DataPanel:PromptDelete(panel) end,
		},
	}

	EditMode:RegisterFrame(id, {
		frame = panel.frame,
		title = panel.name,
		layoutDefaults = defaults,
		onApply = function(_, _, data) panel:ApplyEditMode(data or {}) end,
		onPositionChanged = function(_, _, data) panel:UpdatePositionInfo(data) end,
		settings = settings,
		buttons = buttons,
		showOutsideEditMode = true,
		enableOverlayToggle = true,
		showReset = false,
		showSettingsReset = false,
	})
	panel.editModeRegistered = true
	panel.editModeId = id
end

function DataPanel.SetShowOptionsHint(val)
	addon.db = addon.db or {}
	addon.db.dataPanelsOptions = addon.db.dataPanelsOptions or {}
	if val then
		addon.db.dataPanelsOptions.hideRightClickHint = nil
	else
		addon.db.dataPanelsOptions.hideRightClickHint = true
	end
end

local function getMenuModifierSetting()
	local opts = addon.db and addon.db.dataPanelsOptions
	return (opts and opts.menuModifier) or "NONE"
end

local function isModifierDown(mod)
	if mod == "SHIFT" then
		return IsShiftKeyDown()
	elseif mod == "CTRL" then
		return IsControlKeyDown()
	elseif mod == "ALT" then
		return IsAltKeyDown()
	end
	return true
end

function DataPanel.GetMenuModifier() return getMenuModifierSetting() end

function DataPanel.SetMenuModifier(mod)
	addon.db = addon.db or {}
	addon.db.dataPanelsOptions = addon.db.dataPanelsOptions or {}
	if not mod or not (mod == "NONE" or mod == "SHIFT" or mod == "CTRL" or mod == "ALT") then mod = "NONE" end
	addon.db.dataPanelsOptions.menuModifier = mod
end

function DataPanel.IsMenuModifierActive(btn)
	if btn and btn ~= "RightButton" then return true end
	local mod = getMenuModifierSetting()
	if mod == "NONE" then return true end
	return isModifierDown(mod)
end

function DataPanel:PromptDelete(target)
	local panel = target
	if type(panel) ~= "table" or not panel.id then panel = panels[tostring(target)] end
	if not panel or not panel.id then return end
	if InCombatLockdown and InCombatLockdown() then
		if UIErrorsFrame and ERR_NOT_IN_COMBAT then UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT) end
		return
	end
	local dialog = StaticPopup_Show(DELETE_PANEL_POPUP, panel.name or panel.id)
	if dialog then dialog.data = panel.id end
end

local function ensureSettings(id, name)
	id = tostring(id)
	addon.db = addon.db or {}
	addon.db.dataPanels = addon.db.dataPanels or {}
	local info = addon.db.dataPanels[id] or addon.db.dataPanels[tonumber(id)]
	if not info then
		info = {
			point = "CENTER",
			x = 0,
			y = 0,
			width = 300,
			height = 40,
			streams = {},
			streamSet = {},
			name = name or ((L["Panel"] or "Panel") .. " " .. id),
			hideBorder = false,
			clickThrough = false,
			strata = "MEDIUM",
			contentAnchor = "LEFT",
			streamGap = DEFAULT_STREAM_GAP,
			fontOutline = DEFAULT_FONT_OUTLINE,
			fontShadow = DEFAULT_FONT_SHADOW,
			streamFontScale = DEFAULT_STREAM_FONT_SCALE,
			useClassTextColor = false,
			fontFace = defaultFontFace(),
			backgroundTexture = "DEFAULT",
			backgroundColor = { r = 0, g = 0, b = 0, a = DEFAULT_BACKDROP_ALPHA },
			borderTexture = "DEFAULT",
			borderColor = { r = 1, g = 1, b = 1, a = DEFAULT_BORDER_ALPHA },
			borderSize = DEFAULT_BORDER_SIZE,
			borderOffset = DEFAULT_BORDER_OFFSET,
			showTooltips = true,
			textAlphaInCombat = DEFAULT_TEXT_ALPHA,
			textAlphaOutOfCombat = DEFAULT_TEXT_ALPHA,
		}
	else
		info.streams = info.streams or {}
		info.streamSet = info.streamSet or {}
		info.name = info.name or name or ((L["Panel"] or "Panel") .. " " .. id)
		if info.hideBorder == nil then
			if info.noBorder ~= nil then
				info.hideBorder = info.noBorder and true or false
				if info.noBorder then
					info.backgroundColor = normalizeColorTable(info.backgroundColor, DEFAULT_BACKDROP_COLOR)
					info.backgroundColor.a = 0
				end
			else
				info.hideBorder = false
			end
		end
		info.noBorder = nil
		if info.clickThrough == nil then info.clickThrough = false end
		info.strata = normalizeStrata(info.strata, "MEDIUM")
		info.contentAnchor = normalizeContentAnchor(info.contentAnchor, "LEFT")
		info.streamGap = normalizeStreamGap(info.streamGap, DEFAULT_STREAM_GAP)
		if info.fontOutline == nil then info.fontOutline = DEFAULT_FONT_OUTLINE end
		if info.fontShadow == nil then info.fontShadow = DEFAULT_FONT_SHADOW end
		info.streamFontScale = normalizeStreamFontScale(info.streamFontScale, DEFAULT_STREAM_FONT_SCALE)
		if info.useClassTextColor == nil then info.useClassTextColor = false end
		if not info.fontFace or info.fontFace == "" then info.fontFace = defaultFontFace() end
		info.backgroundTexture = normalizeMediaKey(info.backgroundTexture, "DEFAULT")
		info.backgroundColor = normalizeColorTable(info.backgroundColor, DEFAULT_BACKDROP_COLOR)
		info.borderTexture = normalizeMediaKey(info.borderTexture, "DEFAULT")
		info.borderColor = normalizeColorTable(info.borderColor, DEFAULT_BORDER_COLOR)
		info.borderSize = normalizeBorderSize(info.borderSize, DEFAULT_BORDER_SIZE)
		info.borderOffset = normalizeBorderOffset(info.borderOffset, DEFAULT_BORDER_OFFSET)
		if info.showTooltips == nil then info.showTooltips = true end
		info.textAlphaInCombat = normalizePercent(info.textAlphaInCombat, DEFAULT_TEXT_ALPHA)
		info.textAlphaOutOfCombat = normalizePercent(info.textAlphaOutOfCombat, info.textAlphaInCombat)
	end

	addon.db.dataPanels[id] = info
	if addon.db.dataPanels[tonumber(id)] then addon.db.dataPanels[tonumber(id)] = nil end

	for _, n in ipairs(info.streams) do
		info.streamSet[n] = true
	end

	return info
end

local function round2(v) return math.floor(v * 100 + 0.5) / 100 end

local function savePosition(frame, id)
	id = tostring(id)
	-- Do not recreate database entries when saving position.
	-- Only persist if the panel still exists in the DB.
	if not addon.db or not addon.db.dataPanels or not addon.db.dataPanels[id] then return end
	local info = addon.db.dataPanels[id]
	info.point, _, _, info.x, info.y = frame:GetPoint()
	info.width = round2(frame:GetWidth())
	info.height = round2(frame:GetHeight())
	local panel = panels[id]
	if panel then
		panel:SyncEditModePosition(info.point, info.x, info.y)
		panel:SyncEditModeValue("width", info.width)
		panel:SyncEditModeValue("height", info.height)
	end
end

function DataPanel.Create(id, name, existingOnly)
	addon.db = addon.db or {}
	addon.db.dataPanels = addon.db.dataPanels or {}
	addon.db.dataPanelsOptions = addon.db.dataPanelsOptions or {}
	addon.db.dataPanelsOptions.menuModifier = addon.db.dataPanelsOptions.menuModifier or "NONE"
	if not addon.db.nextPanelId then
		addon.db.nextPanelId = 1
		for k in pairs(addon.db.dataPanels) do
			local num = tonumber(k)
			if num and num >= addon.db.nextPanelId then addon.db.nextPanelId = num + 1 end
		end
	end
	if not id then
		id = tostring(addon.db.nextPanelId)
		addon.db.nextPanelId = addon.db.nextPanelId + 1
	else
		id = tostring(id)
	end
	if panels[id] then return panels[id] end

	-- If we are asked to only use existing panels, do not implicitly
	-- create a new database entry for unknown IDs.
	if existingOnly and not addon.db.dataPanels[id] and not addon.db.dataPanels[tonumber(id)] then return nil end

	local info = ensureSettings(id, name)
	local frame = CreateFrame("Frame", addonName .. "DataPanel" .. id, UIParent, "BackdropTemplate")
	frame:SetSize(info.width, info.height)
	frame:SetPoint(info.point, info.x, info.y)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:EnableMouse(true)
	local initialStrata = normalizeStrata(info.strata, frame:GetFrameStrata())
	info.strata = initialStrata
	if frame:GetFrameStrata() ~= initialStrata then frame:SetFrameStrata(initialStrata) end

	local panel = { frame = frame, id = id, name = info.name, streams = {}, order = {}, info = info }

	frame:SetScript("OnSizeChanged", function(f)
		savePosition(f, id)
		for _, data in pairs(panel.streams) do
			data.button:SetHeight(f:GetHeight())
		end
		if panel.Refresh then panel:Refresh() end
	end)

	function panel:ApplyBorder()
		local i = self.info
		if self.frame and self.frame.SetBackdrop then self.frame:SetBackdrop(nil) end
		if not self.frame.bg or not self.frame.border then
			local level = (self.frame and self.frame.GetFrameLevel and self.frame:GetFrameLevel()) or 0
			local borderLevel = math.max(level - 1, 0)
			local bgLevel = math.max(borderLevel - 1, 0)
			local bgFrame = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
			bgFrame:SetFrameLevel(bgLevel)
			bgFrame:SetAllPoints(self.frame)
			self.frame.bg = bgFrame
			local borderFrame = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
			borderFrame:SetFrameLevel(borderLevel)
			self.frame.border = borderFrame
		end
		local bgFrame = self.frame.bg
		local borderFrame = self.frame.border
		if bgFrame and bgFrame.SetBackdrop then
			bgFrame:SetBackdrop({
				bgFile = resolveBackgroundTexture(i and i.backgroundTexture),
				edgeFile = nil,
				tile = true,
				tileSize = 16,
				insets = { left = BACKDROP_INSET, right = BACKDROP_INSET, top = BACKDROP_INSET, bottom = BACKDROP_INSET },
			})
			if bgFrame.SetBackdropBorderColor then bgFrame:SetBackdropBorderColor(0, 0, 0, 0) end
			bgFrame:Show()
		end
		if borderFrame and borderFrame.SetBackdrop then
			if i and i.hideBorder then
				borderFrame:Hide()
			else
				local borderSize = normalizeBorderSize(i and i.borderSize, DEFAULT_BORDER_SIZE)
				local borderOffset = normalizeBorderOffset(i and i.borderOffset, DEFAULT_BORDER_OFFSET)
				borderFrame:SetBackdrop({
					bgFile = nil,
					edgeFile = resolveBorderTexture(i and i.borderTexture),
					tile = false,
					edgeSize = borderSize,
					insets = { left = 0, right = 0, top = 0, bottom = 0 },
				})
				if borderFrame.SetBackdropColor then borderFrame:SetBackdropColor(0, 0, 0, 0) end
				borderFrame:ClearAllPoints()
				borderFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", -borderOffset, borderOffset)
				borderFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", borderOffset, -borderOffset)
				borderFrame:Show()
			end
		end
		self:ApplyBackdropAlpha(InCombatLockdown and InCombatLockdown() or false)
		self:SyncEditModeValue("hideBorder", i and i.hideBorder or false)
		self:SyncEditModeValue("backgroundTexture", i and i.backgroundTexture or "DEFAULT")
		self:SyncEditModeValue("backgroundColor", i and i.backgroundColor or DEFAULT_BACKDROP_COLOR)
		self:SyncEditModeValue("borderTexture", i and i.borderTexture or "DEFAULT")
		self:SyncEditModeValue("borderColor", i and i.borderColor or DEFAULT_BORDER_COLOR)
		self:SyncEditModeValue("borderSize", i and i.borderSize or DEFAULT_BORDER_SIZE)
		self:SyncEditModeValue("borderOffset", i and i.borderOffset or DEFAULT_BORDER_OFFSET)
	end

	function panel:ApplyClickThroughToData(data)
		local enabled = not (self.info and self.info.clickThrough)
		if data and data.button and data.button.EnableMouse then data.button:EnableMouse(enabled) end
		if data and data.parts then
			for _, child in ipairs(data.parts) do
				if child and child.EnableMouse then child:EnableMouse(enabled) end
			end
		end
	end

	function panel:ApplyClickThrough()
		local enabled = not (self.info and self.info.clickThrough)
		if self.frame and self.frame.EnableMouse then self.frame:EnableMouse(enabled) end
		for _, data in pairs(self.streams) do
			self:ApplyClickThroughToData(data)
		end
		self:SyncEditModeValue("clickThrough", self.info and self.info.clickThrough or false)
	end

	function panel:ApplyStrata(strata)
		local fallback = (self.info and self.info.strata) or (self.frame and self.frame:GetFrameStrata())
		local normalized = normalizeStrata(strata, fallback)
		if self.info then self.info.strata = normalized end
		if self.frame and self.frame:GetFrameStrata() ~= normalized then self.frame:SetFrameStrata(normalized) end
		updateSelectionStrata(self, normalized)
		self:SyncEditModeValue("strata", normalized)
	end

	function panel:GetFontFlags()
		if self.info and self.info.fontOutline == false then return "" end
		return "OUTLINE"
	end

	function panel:GetFontFace() return (self.info and self.info.fontFace) or defaultFontFace() end

	function panel:ApplyFontStyle(fontString, font, size)
		if not fontString or not fontString.SetFont or not font or not size then return end
		fontString:SetFont(font, size, self:GetFontFlags())
		if fontString.SetShadowColor then
			if self.info and self.info.fontShadow then
				fontString:SetShadowColor(0, 0, 0, SHADOW_ALPHA)
				fontString:SetShadowOffset(SHADOW_OFFSET_X, SHADOW_OFFSET_Y)
			else
				fontString:SetShadowColor(0, 0, 0, 0)
				fontString:SetShadowOffset(0, 0)
			end
		end
	end

	function panel:GetStreamFontScale() return normalizeStreamFontScale(self.info and self.info.streamFontScale, DEFAULT_STREAM_FONT_SCALE) end

	function panel:GetClassTextColorHex()
		if not (self.info and self.info.useClassTextColor) then return nil end
		local classToken = UnitClass and select(2, UnitClass("player"))
		if not classToken then return nil end
		local color = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS) and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classToken]
		if not color then return nil end
		return string.format("%02x%02x%02x", math.floor((color.r or 1) * 255 + 0.5), math.floor((color.g or 1) * 255 + 0.5), math.floor((color.b or 1) * 255 + 0.5))
	end

	function panel:ApplyClassTextColor(text, skip)
		if skip or type(text) ~= "string" or text == "" then return text end
		local hex = self:GetClassTextColorHex()
		if not hex then return text end
		return "|cff" .. hex .. text .. "|r"
	end

	function panel:ApplyStreamFontScale(size)
		local baseSize = tonumber(size) or 14
		local scale = self:GetStreamFontScale() / 100
		return math.max(6, math.floor(baseSize * scale + 0.5))
	end

	function panel:ReapplyPayloads()
		for _, data in pairs(self.streams) do
			if data and data.applyPayload and data.lastPayload then data.applyPayload(data.lastPayload, true) end
		end
	end

	function panel:GetTextAlpha(inCombat)
		local info = self.info or {}
		local value = (inCombat or false) and info.textAlphaInCombat or info.textAlphaOutOfCombat
		return normalizePercent(value, DEFAULT_TEXT_ALPHA) / 100
	end

	function panel:ApplyBackdropAlpha(inCombat)
		if not self.frame then return end
		local bgFrame = self.frame.bg
		local borderFrame = self.frame.border
		if not bgFrame or not borderFrame then return end
		local alpha = self:GetTextAlpha(inCombat)
		local bg = normalizeColorTable(self.info and self.info.backgroundColor, DEFAULT_BACKDROP_COLOR)
		local bc = normalizeColorTable(self.info and self.info.borderColor, DEFAULT_BORDER_COLOR)
		if bgFrame.SetBackdropColor then bgFrame:SetBackdropColor(bg.r or 0, bg.g or 0, bg.b or 0, (bg.a or DEFAULT_BACKDROP_ALPHA) * alpha) end
		if borderFrame.SetBackdropBorderColor then borderFrame:SetBackdropBorderColor(bc.r or 1, bc.g or 1, bc.b or 1, (bc.a or DEFAULT_BORDER_ALPHA) * alpha) end
	end

	function panel:ApplyAlpha(inCombat)
		local alpha = self:GetTextAlpha(inCombat)
		for _, data in pairs(self.streams) do
			if data and data.button and data.button.SetAlpha then data.button:SetAlpha(alpha) end
		end
		self:ApplyBackdropAlpha(inCombat)
	end

	function panel:ApplyTextStyle()
		local font = self:GetFontFace()
		local fontFlags = self:GetFontFlags()
		local fontShadow = self.info and self.info.fontShadow == true
		local changed = false

		for _, data in pairs(self.streams) do
			if data.text then
				local _, size = data.text:GetFont()
				if font and size then
					self:ApplyFontStyle(data.text, font, size)
					data.fontFlags = fontFlags
					data.fontShadow = fontShadow
				end
			end

			if data.parts then
				data.partsFont = font
				data.partsFontFlags = fontFlags
				data.partsFontShadow = fontShadow
				local total = 0
				local visibleCount = 0
				for _, child in ipairs(data.parts) do
					if child and child.text then
						local _, size = child.text:GetFont()
						if font and size then self:ApplyFontStyle(child.text, font, size) end
						if child:IsShown() and not child.usingIcons then
							local width = child.text:GetStringWidth()
							if width ~= child.lastWidth then
								child.lastWidth = width
								child:SetWidth(width)
							end
						end
					end
					if child and child:IsShown() then
						local width = child.lastWidth or 0
						if visibleCount > 0 then total = total + 5 end
						total = total + width
						visibleCount = visibleCount + 1
					end
				end
				if data.usingParts and total ~= data.lastWidth then
					data.lastWidth = total
					if data.button then data.button:SetWidth(total) end
					changed = true
				end
			end

			if not data.usingParts and data.text then
				local width = data.text:GetStringWidth()
				if width ~= data.lastWidth then
					data.lastWidth = width
					if data.button then data.button:SetWidth(width) end
					changed = true
				end
			end
		end

		if changed then self:Refresh() end
	end

	function panel:ScheduleTextReflow()
		if self._eqolTextReflowScheduled then return end
		if not C_Timer or not C_Timer.After then return end
		self._eqolTextReflowScheduled = true
		C_Timer.After(0.05, function()
			if panels[id] ~= panel then return end
			panel._eqolTextReflowScheduled = nil
			if panel.ApplyTextStyle then panel:ApplyTextStyle() end
		end)
	end

	function panel:SyncEditModeValue(field, value)
		if not EditMode or not self.editModeId or self.suspendEditSync or self.applyingFromEditMode then return end
		self.suspendEditSync = true
		if
			field == "width"
			or field == "height"
			or field == "hideBorder"
			or field == "clickThrough"
			or field == "streams"
			or field == "strata"
			or field == "contentAnchor"
			or field == "streamGap"
			or field == "fontFace"
			or field == "fontOutline"
			or field == "fontShadow"
			or field == "streamFontScale"
			or field == "useClassTextColor"
			or field == "showTooltips"
			or field == "textAlphaInCombat"
			or field == "textAlphaOutOfCombat"
			or field == "backgroundTexture"
			or field == "backgroundColor"
			or field == "borderTexture"
			or field == "borderColor"
			or field == "borderSize"
			or field == "borderOffset"
		then
			EditMode:SetValue(self.editModeId, field, value)
		end
		self.suspendEditSync = nil
	end

	function panel:SyncEditModePosition(point, x, y)
		if not EditMode or not self.editModeId or self.suspendEditSync then return end
		self.suspendEditSync = true
		EditMode:SetFramePosition(self.editModeId, point, x, y)
		self.suspendEditSync = nil
	end

	function panel:SyncEditModeStreams()
		if not EditMode or not self.editModeId then return end
		self:SyncEditModeValue("streams", copyList(self.info.streams))
	end

	function panel:SyncEditModeStrata()
		if not EditMode or not self.editModeId then return end
		self:SyncEditModeValue("strata", self.info and self.info.strata or "MEDIUM")
	end

	function panel:UpdatePositionInfo(data)
		if not data then return end
		local info = self.info
		if not info then return end
		if data.point then info.point = data.point end
		if data.x then info.x = data.x end
		if data.y then info.y = data.y end
	end

	function panel:ApplyStreams(streamList)
		self.suspendEditSync = true
		local desired = {}
		for _, name in ipairs(streamList or {}) do
			desired[name] = true
		end
		for existing in pairs(self.streams) do
			if not desired[existing] then self:RemoveStream(existing) end
		end
		for _, name in ipairs(streamList or {}) do
			if not self.streams[name] then self:AddStream(name) end
		end
		self.order = {}
		self.info.streams = {}
		self.info.streamSet = {}
		for _, name in ipairs(streamList or {}) do
			if self.streams[name] then
				self.order[#self.order + 1] = name
				self.info.streams[#self.info.streams + 1] = name
				self.info.streamSet[name] = true
			end
		end
		self:Refresh()
		self.suspendEditSync = nil
		if not self.applyingFromEditMode then self:SyncEditModeStreams() end
	end

	function panel:ApplyEditMode(data)
		self.suspendEditSync = true
		local info = self.info
		local alphaChanged = false
		local fontStyleChanged = false
		local fontFaceChanged = false
		local payloadStyleChanged = false
		local backdropChanged = false
		local backdropColorChanged = false
		local layoutChanged = false
		if data.width then
			info.width = round2(data.width)
			self.frame:SetWidth(info.width)
		end
		if data.height then
			info.height = round2(data.height)
			self.frame:SetHeight(info.height)
		end
		if data.hideBorder ~= nil then
			info.hideBorder = data.hideBorder and true or false
			self:ApplyBorder()
		end
		if data.backgroundTexture ~= nil then
			local desired = normalizeMediaKey(data.backgroundTexture, "DEFAULT")
			if info.backgroundTexture ~= desired then
				info.backgroundTexture = desired
				backdropChanged = true
			end
		end
		if data.borderTexture ~= nil then
			local desired = normalizeMediaKey(data.borderTexture, "DEFAULT")
			if info.borderTexture ~= desired then
				info.borderTexture = desired
				backdropChanged = true
			end
		end
		if data.borderSize ~= nil then
			local desired = normalizeBorderSize(data.borderSize, info.borderSize)
			if info.borderSize ~= desired then
				info.borderSize = desired
				backdropChanged = true
			end
		end
		if data.borderOffset ~= nil then
			local desired = normalizeBorderOffset(data.borderOffset, info.borderOffset)
			if info.borderOffset ~= desired then
				info.borderOffset = desired
				backdropChanged = true
			end
		end
		if data.backgroundColor ~= nil then
			local desired = normalizeColorTable(data.backgroundColor, DEFAULT_BACKDROP_COLOR)
			if not colorsEqual(info.backgroundColor, desired) then
				info.backgroundColor = desired
				backdropColorChanged = true
			end
		end
		if data.borderColor ~= nil then
			local desired = normalizeColorTable(data.borderColor, DEFAULT_BORDER_COLOR)
			if not colorsEqual(info.borderColor, desired) then
				info.borderColor = desired
				backdropColorChanged = true
			end
		end
		if data.clickThrough ~= nil then
			local desired = data.clickThrough and true or false
			if info.clickThrough ~= desired then
				info.clickThrough = desired
				self:ApplyClickThrough()
			end
		end
		if data.strata then self:ApplyStrata(data.strata) end
		if data.contentAnchor then
			local anchor = normalizeContentAnchor(data.contentAnchor, info.contentAnchor)
			if info.contentAnchor ~= anchor then
				info.contentAnchor = anchor
				layoutChanged = true
			end
		end
		if data.streamGap ~= nil then
			local value = normalizeStreamGap(data.streamGap, info.streamGap)
			if info.streamGap ~= value then
				info.streamGap = value
				layoutChanged = true
			end
		end
		if data.fontFace ~= nil then
			local desired = normalizeFontFace(data.fontFace) or defaultFontFace()
			if info.fontFace ~= desired then
				info.fontFace = desired
				fontFaceChanged = true
			end
		end
		if data.fontOutline ~= nil then
			local desired = data.fontOutline and true or false
			if info.fontOutline ~= desired then
				info.fontOutline = desired
				fontStyleChanged = true
			end
		end
		if data.fontShadow ~= nil then
			local desired = data.fontShadow and true or false
			if info.fontShadow ~= desired then
				info.fontShadow = desired
				fontStyleChanged = true
			end
		end
		if data.streamFontScale ~= nil then
			local desired = normalizeStreamFontScale(data.streamFontScale, info.streamFontScale)
			if info.streamFontScale ~= desired then
				info.streamFontScale = desired
				payloadStyleChanged = true
			end
		end
		if data.useClassTextColor ~= nil then
			local desired = data.useClassTextColor and true or false
			if info.useClassTextColor ~= desired then
				info.useClassTextColor = desired
				payloadStyleChanged = true
			end
		end
		if data.showTooltips ~= nil then
			local desired = data.showTooltips and true or false
			if info.showTooltips ~= desired then
				info.showTooltips = desired
				if not desired then GameTooltip:Hide() end
			end
		end
		if data.textAlphaInCombat ~= nil then
			local value = normalizePercent(data.textAlphaInCombat, info.textAlphaInCombat)
			if info.textAlphaInCombat ~= value then
				info.textAlphaInCombat = value
				alphaChanged = true
			end
		end
		if data.textAlphaOutOfCombat ~= nil then
			local value = normalizePercent(data.textAlphaOutOfCombat, info.textAlphaOutOfCombat)
			if info.textAlphaOutOfCombat ~= value then
				info.textAlphaOutOfCombat = value
				alphaChanged = true
			end
		end
		if data.streams then
			self.applyingFromEditMode = true
			self:ApplyStreams(data.streams)
			self.applyingFromEditMode = nil
		end
		if payloadStyleChanged then self:ReapplyPayloads() end
		if fontStyleChanged or fontFaceChanged or payloadStyleChanged then self:ApplyTextStyle() end
		if backdropChanged then
			self:ApplyBorder()
		elseif backdropColorChanged then
			self:ApplyBackdropAlpha()
		end
		if alphaChanged then self:ApplyAlpha() end
		if layoutChanged then self:Refresh() end
		self.suspendEditSync = nil
	end

	function panel:Refresh(force)
		local visible = {}
		for _, name in ipairs(self.order) do
			local data = self.streams[name]
			if data then
				if data.hidden then
					data.button:Hide()
				else
					visible[#visible + 1] = name
				end
			end
		end

		local frameWidth = self.frame and self.frame.GetWidth and self.frame:GetWidth() or 0
		local contentAnchor = normalizeContentAnchor(self.info and self.info.contentAnchor, "LEFT")
		local spacing = normalizeStreamGap(self.info and self.info.streamGap, DEFAULT_STREAM_GAP)
		local changed = force and true or self.lastLayoutAnchor ~= contentAnchor or self.lastLayoutWidth ~= frameWidth or self.lastLayoutSpacing ~= spacing
		if not self.lastOrder or #self.lastOrder ~= #visible then
			changed = true
		else
			for i, name in ipairs(visible) do
				local data = self.streams[name]
				if self.lastOrder[i] ~= name or (self.lastWidths and self.lastWidths[name] ~= (data.lastWidth or 0)) then
					changed = true
					break
				end
			end
		end
		if not changed then return end

		local padding = 5
		local totalWidth = 0
		for i, name in ipairs(visible) do
			local data = self.streams[name]
			local width = (data and data.lastWidth) or 0
			if i > 1 then totalWidth = totalWidth + spacing end
			totalWidth = totalWidth + width
		end
		local startX = padding
		if contentAnchor == "CENTER" then
			local available = frameWidth - (padding * 2)
			startX = padding + (available - totalWidth) / 2
		elseif contentAnchor == "RIGHT" then
			startX = frameWidth - padding - totalWidth
		end

		local prev
		for _, name in ipairs(visible) do
			local data = self.streams[name]
			local btn = data.button
			btn:Show()
			btn:ClearAllPoints()
			btn:SetWidth(data.lastWidth or 0)
			if prev then
				btn:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
			else
				btn:SetPoint("LEFT", self.frame, "LEFT", startX, 0)
			end
			prev = btn
		end

		self.lastOrder = {}
		self.lastWidths = {}
		for i, name in ipairs(visible) do
			self.lastOrder[i] = name
			self.lastWidths[name] = self.streams[name].lastWidth or 0
		end
		self.lastLayoutAnchor = contentAnchor
		self.lastLayoutWidth = frameWidth
		self.lastLayoutSpacing = spacing
	end

	function panel:AddStream(name)
		if self.streams[name] then return end
		local button = CreateFrame("Button", nil, self.frame)
		button:SetHeight(self.frame:GetHeight())
		local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		text:SetAllPoints()
		text:SetJustifyH("LEFT")
		local data = { button = button, text = text, lastWidth = text:GetStringWidth(), lastText = "", panel = self }
		button.slot = data
		button:SetScript("OnEnter", function(b)
			local s = b.slot
			if slotTooltipsEnabled(s) then
				if s.tooltip then
					GameTooltip:SetOwner(b, "ANCHOR_TOPLEFT")
					GameTooltip:SetText(s.tooltip)
					GameTooltip:Show()
				end
				if s.OnMouseEnter then s.OnMouseEnter(b) end
			end
		end)
		button:SetScript("OnLeave", function(b)
			local s = b.slot
			if slotTooltipsEnabled(s) and s.OnMouseLeave then s.OnMouseLeave(b) end
			GameTooltip:Hide()
		end)
		button:RegisterForClicks("AnyUp")
		button:SetScript("OnClick", function(b, btn, ...)
			local s = b.slot
			if btn == "RightButton" and not (s and s.ignoreMenuModifier) and not DataPanel.IsMenuModifierActive(btn) then return end
			local fn = s and s.OnClick
			if type(fn) == "table" then fn = fn[btn] end
			if fn then fn(b, btn, ...) end
		end)

		self:ApplyClickThroughToData(data)

		self.order[#self.order + 1] = name

		local function cb(payload)
			payload = payload or {}
			data.lastPayload = payload
			local layoutNeedsRefresh = false
			local hasSecureParts = payloadHasSecureParts(payload)
			if hasSecureParts then data.secureParts = true end
			if hasSecureParts and InCombatLockdown and InCombatLockdown() and not data.secureInitialized then
				data.pendingPayload = payload
				queueSecureUpdate(data)
				return
			end
			local font = panel:GetFontFace() or select(1, data.text:GetFont())
			local baseSize = payload.fontSize or data.fontSize or 14
			local size = panel:ApplyStreamFontScale(baseSize)
			local fontFlags = panel:GetFontFlags()
			local fontShadow = panel.info and panel.info.fontShadow == true
			local clickEnabled = not (panel.info and panel.info.clickThrough)

			if payload.hidden then
				data.button:Hide()
				if not data.hidden then
					data.hidden = true
					data.lastWidth = 0
					data.lastText = ""
					if data.parts then
						for _, child in ipairs(data.parts) do
							child:Hide()
						end
					end
					data.text:SetText("")
					self:Refresh()
				end
				data.tooltip = nil
				data.perCurrency = nil
				data.showDescription = nil
				data.hover = nil
				data.OnMouseEnter = nil
				data.OnMouseLeave = nil
				data.ignoreMenuModifier = payload.ignoreMenuModifier
				if payload.OnClick ~= nil then data.OnClick = payload.OnClick end
				return
			elseif data.hidden then
				data.hidden = nil
				data.button:Show()
				self:Refresh()
			end

			local wasParts = data.usingParts
			if payload.parts then
				data.usingParts = true
				data.text:SetText("")
				data.text:Hide()
				data.parts = data.parts or {}
				local partsFontChanged = data.partsFont ~= font or data.partsFontSize ~= size or data.partsFontFlags ~= fontFlags or data.partsFontShadow ~= fontShadow
				if partsFontChanged then
					data.partsFont = font
					data.partsFontSize = size
					data.partsFontFlags = fontFlags
					data.partsFontShadow = fontShadow
				end
				local buttonHeight = button:GetHeight()
				local heightChanged = data.partsHeight ~= buttonHeight
				if heightChanged then data.partsHeight = buttonHeight end
				local partSpacing = tonumber(payload.partSpacing)
				if not partSpacing then partSpacing = 5 end
				if partSpacing < 0 then partSpacing = 0 end
				local spacingChanged = data.partsSpacing ~= partSpacing
				if spacingChanged then data.partsSpacing = partSpacing end
				local totalWidth = 0
				for i, part in ipairs(payload.parts) do
					local secureSpec = part and part.secure
					local isSecure = secureSpec ~= nil
					local secureTemplate
					local secureAttributes
					local secureClicks
					local secureKey
					if isSecure and type(secureSpec) == "table" then
						secureTemplate = secureSpec.template
						secureAttributes = secureSpec.attributes
						secureClicks = secureSpec.registerClicks
						secureKey = secureSpec.key
					end
					if isSecure and not secureTemplate then secureTemplate = "SecureActionButtonTemplate" end

					local child = data.parts[i]
					local isNew = false
					local needsRebuild = false
					if child then
						if isSecure ~= (child.isSecure == true) then
							needsRebuild = true
						elseif isSecure and child.secureTemplate ~= secureTemplate then
							needsRebuild = true
						end
					end
					if needsRebuild then
						if InCombatLockdown and InCombatLockdown() then
							data.pendingPayload = payload
							queueSecureUpdate(data)
							return
						end
						child:Hide()
						child:SetParent(nil)
						data.parts[i] = nil
						child = nil
					end
					if not child then
						if isSecure and InCombatLockdown and InCombatLockdown() then
							data.pendingPayload = payload
							queueSecureUpdate(data)
							return
						end
						if isSecure then
							child = CreateFrame("Button", nil, button, secureTemplate)
							child.isSecure = true
							child.secureTemplate = secureTemplate
							child:RegisterForClicks(secureClicks or "AnyDown", "AnyUp")
							child:SetAttribute("pressAndHoldAction", false)
						else
							child = CreateFrame("Button", nil, button)
							child:RegisterForClicks("AnyUp")
							child:SetScript("OnClick", partsOnClick)
						end
						if child.EnableMouse then child:EnableMouse(clickEnabled) end
						child.text = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
						child.text:SetAllPoints()
						child.slot = data
						child:SetScript("OnEnter", partsOnEnter)
						child:SetScript("OnLeave", partsOnLeave)
						data.parts[i] = child
						isNew = true
					end
					if isNew or spacingChanged then
						child:ClearAllPoints()
						if i == 1 then
							child:SetPoint("LEFT", button, "LEFT", 0, 0)
						else
							child:SetPoint("LEFT", data.parts[i - 1], "RIGHT", partSpacing, 0)
						end
					end
					child.slot = data
					child:Show()
					local backdropSpec = part.backdrop
					if backdropSpec then
						local backdrop = child.eqolBackdrop
						if not backdrop then
							backdrop = CreateFrame("Frame", nil, child, "BackdropTemplate")
							backdrop:SetFrameStrata(child:GetFrameStrata())
							backdrop:SetFrameLevel(math.max((child:GetFrameLevel() or 1) - 1, 0))
							child.eqolBackdrop = backdrop
						end
						local bgFile = backdropSpec.bgFile or "Interface\\Buttons\\WHITE8x8"
						local edgeFile = backdropSpec.edgeFile or "Interface\\Buttons\\WHITE8x8"
						local edgeSize = tonumber(backdropSpec.edgeSize) or 1
						if edgeSize < 0.5 then edgeSize = 0.5 end
						if backdrop.eqolBgFile ~= bgFile or backdrop.eqolEdgeFile ~= edgeFile or backdrop.eqolEdgeSize ~= edgeSize then
							backdrop:SetBackdrop({
								bgFile = bgFile,
								edgeFile = edgeFile,
								edgeSize = edgeSize,
								insets = { left = 0, right = 0, top = 0, bottom = 0 },
							})
							backdrop.eqolBgFile = bgFile
							backdrop.eqolEdgeFile = edgeFile
							backdrop.eqolEdgeSize = edgeSize
						end
						local offset = tonumber(backdropSpec.offset) or 0
						backdrop:ClearAllPoints()
						backdrop:SetPoint("TOPLEFT", child, "TOPLEFT", -offset, offset)
						backdrop:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", offset, -offset)
						local bgColor = backdropSpec.bgColor or { 0, 0, 0, 0.5 }
						local borderColor = backdropSpec.borderColor or { 1, 1, 1, 0.7 }
						backdrop:SetBackdropColor(bgColor[1] or bgColor.r or 0, bgColor[2] or bgColor.g or 0, bgColor[3] or bgColor.b or 0, bgColor[4] or bgColor.a or 0.5)
						backdrop:SetBackdropBorderColor(
							borderColor[1] or borderColor.r or 1,
							borderColor[2] or borderColor.g or 1,
							borderColor[3] or borderColor.b or 1,
							borderColor[4] or borderColor.a or 0.7
						)
						backdrop:Show()
					elseif child.eqolBackdrop then
						child.eqolBackdrop:Hide()
					end
					if isSecure then
						local needsSecureConfig = not child.secureConfigured or (secureKey and child.secureKey ~= secureKey)
						if needsSecureConfig then
							if InCombatLockdown and InCombatLockdown() then
								data.pendingPayload = payload
								queueSecureUpdate(data)
								return
							end
							if secureAttributes then
								for key, value in pairs(secureAttributes) do
									child:SetAttribute(key, value)
								end
							end
							if secureSpec and secureSpec.forwardRightClick then
								if not (secureAttributes and secureAttributes.type2) then child:SetAttribute("type2", "click") end
								if not (secureAttributes and secureAttributes.clickbutton2) then child:SetAttribute("clickbutton2", button) end
							end
							child.secureConfigured = true
							child.secureKey = secureKey
						end
					end
					local partHeight = tonumber(part.height)
					if not partHeight then partHeight = tonumber(part.iconHeight) or tonumber(part.iconSize) or tonumber(part.iconWidth) or buttonHeight end
					if partHeight < buttonHeight then partHeight = buttonHeight end
					if isNew or heightChanged or child.lastHeight ~= partHeight then
						child.lastHeight = partHeight
						child:SetHeight(partHeight)
					end
					if isNew or partsFontChanged then panel:ApplyFontStyle(child.text, font, size) end
					local iconSpec = part.icon
					local overlaySpec = part.iconOverlay
					local useIcons = iconSpec ~= nil or overlaySpec ~= nil
					if useIcons then
						child.usingIcons = true
						child.text:SetText("")
						child.text:Hide()

						local function applyIcon(tex, spec, sublevel, defaultSize)
							if spec == nil then
								if tex then tex:Hide() end
								return tex
							end
							if not tex then tex = child:CreateTexture(nil, "ARTWORK", nil, sublevel) end
							local tc = spec.texCoord
							if spec.atlas then
								tex:SetAtlas(spec.atlas, true)
								if type(tc) == "table" then
									local l = tc[1] or 0
									local r = tc[2] or 1
									local t = tc[3] or 0
									local b = tc[4] or 1
									tex:SetTexCoord(l, r, t, b)
								else
									tex:SetTexCoord(0, 1, 0, 1)
								end
							elseif spec.texture then
								tex:SetTexture(spec.texture)
								if type(tc) == "table" then
									local l = tc[1] or 0
									local r = tc[2] or 1
									local t = tc[3] or 0
									local b = tc[4] or 1
									tex:SetTexCoord(l, r, t, b)
								else
									tex:SetTexCoord(0, 1, 0, 1)
								end
							end
							local color = spec.vertexColor or spec.color
							if type(color) == "table" then
								local r = color.r or color[1] or 1
								local g = color.g or color[2] or 1
								local b = color.b or color[3] or 1
								local a = color.a or color[4] or 1
								tex:SetVertexColor(r, g, b, a)
							else
								tex:SetVertexColor(1, 1, 1, 1)
							end
							if spec.desaturate ~= nil then
								tex:SetDesaturated(spec.desaturate and true or false)
							else
								tex:SetDesaturated(false)
							end
							local iconSize = spec.size or defaultSize
							tex:SetSize(iconSize, iconSize)
							tex:SetPoint("CENTER", child, "CENTER", spec.offsetX or 0, spec.offsetY or 0)
							tex:Show()
							return tex
						end

						local baseSize = part.iconSize or size
						child.icon = applyIcon(child.icon, iconSpec, 0, baseSize)
						child.iconOverlay = applyIcon(child.iconOverlay, overlaySpec, 1, baseSize)
						local iconWidth = part.iconWidth or baseSize
						if child.lastWidth ~= iconWidth then
							child.lastWidth = iconWidth
							child:SetWidth(iconWidth)
						end
					else
						if child.usingIcons then
							child.usingIcons = nil
							if child.icon then child.icon:Hide() end
							if child.iconOverlay then child.iconOverlay:Hide() end
							child.text:Show()
						end
						local rawText = part.text or ""
						local text = panel:ApplyClassTextColor(rawText, part.skipPanelClassColor == true or payload.skipPanelClassColor == true)
						local textChanged = text ~= child.lastText
						if isNew or textChanged then
							child.text:SetText(text)
							child.lastText = text
						end
						if isNew or textChanged or partsFontChanged then
							local w = child.text:GetStringWidth()
							child.lastWidth = w
							child:SetWidth(w)
						end
						if (isNew or textChanged or partsFontChanged) and hasInlineTexture(rawText) then panel:ScheduleTextReflow() end
					end
					child.currencyID = part.id
					totalWidth = totalWidth + (child.lastWidth or 0) + (i > 1 and partSpacing or 0)
				end
				if data.parts then
					for i = #payload.parts + 1, #data.parts do
						data.parts[i]:Hide()
					end
				end
				if totalWidth ~= data.lastWidth then
					data.lastWidth = totalWidth
					data.button:SetWidth(totalWidth)
					if self.lastWidths and self.lastWidths[name] then self.lastWidths[name] = totalWidth end
					layoutNeedsRefresh = true
				end
			else
				data.usingParts = nil
				if data.parts then
					for _, child in ipairs(data.parts) do
						child:Hide()
					end
				end
				data.text:Show()
				local rawText = payload.text or ""
				local text = panel:ApplyClassTextColor(rawText, payload.skipPanelClassColor == true)
				local textChanged = text ~= data.lastText
				if textChanged or wasParts then
					data.text:SetText(text)
					data.lastText = text
					textChanged = true
				end
				local newSize = panel:ApplyStreamFontScale(payload.fontSize or data.fontSize or 14)
				local fontChanged = newSize and (data.fontSize ~= newSize or data.fontFlags ~= fontFlags or data.fontShadow ~= fontShadow)
				if fontChanged then
					panel:ApplyFontStyle(data.text, font, newSize)
					data.fontSize = newSize
					data.fontFlags = fontFlags
					data.fontShadow = fontShadow
				end
				if textChanged or fontChanged or wasParts then
					local width = data.text:GetStringWidth()
					if width ~= data.lastWidth then
						data.lastWidth = width
						data.button:SetWidth(width)
						if self.lastWidths and self.lastWidths[name] then self.lastWidths[name] = width end
						layoutNeedsRefresh = true
					end
					if hasInlineTexture(rawText) then panel:ScheduleTextReflow() end
				end
			end
			if payload.parts then
				local newSize = panel:ApplyStreamFontScale(payload.fontSize or data.fontSize or 14)
				if newSize and (data.fontSize ~= newSize or data.fontFlags ~= fontFlags or data.fontShadow ~= fontShadow) then
					panel:ApplyFontStyle(data.text, font, newSize)
					data.fontSize = newSize
					data.fontFlags = fontFlags
					data.fontShadow = fontShadow
				end
			end
			local textAlpha = payload.textAlpha
			if textAlpha == nil then textAlpha = 1 end
			if data.textAlpha ~= textAlpha then
				data.textAlpha = textAlpha
				if data.text and data.text.SetAlpha then data.text:SetAlpha(textAlpha) end
				if data.parts then
					for _, child in ipairs(data.parts) do
						if child and child.SetAlpha then child:SetAlpha(textAlpha) end
					end
				end
			end
			data.tooltip = payload.tooltip
			data.perCurrency = payload.perCurrency
			data.showDescription = payload.showDescription
			data.hover = payload.hover
			data.OnMouseEnter = payload.OnMouseEnter
			data.OnMouseLeave = payload.OnMouseLeave
			data.ignoreMenuModifier = payload.ignoreMenuModifier
			if payload.OnClick ~= nil then data.OnClick = payload.OnClick end
			if hasSecureParts then data.secureInitialized = true end
			if data.pendingPayload then
				data.pendingPayload = nil
				pendingSecure[data] = nil
			end
			if layoutNeedsRefresh then self:Refresh(true) end
		end

		data.applyPayload = cb
		data.unsub = DataHub:Subscribe(name, cb)
		self.streams[name] = data
		if data.button and data.button.SetAlpha then data.button:SetAlpha(self:GetTextAlpha()) end

		local streams = self.info.streams
		local streamSet = self.info.streamSet
		if not streamSet[name] then
			streamSet[name] = true
			streams[#streams + 1] = name
		end
		self:SyncEditModeStreams()
	end

	function panel:RemoveStream(name)
		local info = self.streams[name]
		if not info then return end
		if info.unsub then info.unsub() end
		info.button:Hide()
		info.button:SetParent(nil)
		self.streams[name] = nil
		for i, n in ipairs(self.order) do
			if n == name then
				table.remove(self.order, i)
				break
			end
		end
		self:Refresh()

		local streams = self.info.streams
		local streamSet = self.info.streamSet
		if streamSet[name] then
			streamSet[name] = nil
			for i, s in ipairs(streams) do
				if s == name then
					table.remove(streams, i)
					break
				end
			end
		end
		self:SyncEditModeStreams()
	end

	panels[id] = panel

	if info.streams then
		for _, name in ipairs(info.streams) do
			panel:AddStream(name)
		end
	end

	registerEditModePanel(panel)
	panel:SyncEditModeStreams()
	panel:SyncEditModeStrata()
	updateSelectionStrata(panel, info.strata)
	ensureFadeWatcher()
	panel:ApplyClickThrough()
	panel:ApplyBorder()
	panel:ApplyAlpha()

	return panel
end

function DataPanel.Get(id)
	id = tostring(id)
	return panels[id]
end

function DataPanel.AddStream(id, name)
	id = tostring(id)
	local panel = panels[id] or panels[tonumber(id)]
	if panel then panel:AddStream(name) end
end

function DataPanel.RemoveStream(id, name)
	id = tostring(id)
	local panel = panels[id]
	if panel then panel:RemoveStream(name) end
end

function DataPanel.Move(id, point, x, y)
	id = tostring(id)
	local panel = panels[id]
	if panel then
		panel.frame:ClearAllPoints()
		panel.frame:SetPoint(point, x, y)
		savePosition(panel.frame, id)
	end
end

function DataPanel.List()
	addon.db = addon.db or {}
	addon.db.dataPanels = addon.db.dataPanels or {}
	local result = {}
	for id, info in pairs(addon.db.dataPanels) do
		id = tostring(id)
		local entry = { list = {}, set = {} }
		result[id] = entry
		if info.streams then
			for _, stream in ipairs(info.streams) do
				if not entry.set[stream] then
					entry.set[stream] = true
					entry.list[#entry.list + 1] = stream
				end
			end
		end
	end
	for id, panel in pairs(panels) do
		id = tostring(id)
		local entry = result[id]
		if not entry then
			entry = { list = {}, set = {} }
			result[id] = entry
		end
		for _, stream in ipairs(panel.order) do
			if not entry.set[stream] then
				entry.set[stream] = true
				entry.list[#entry.list + 1] = stream
			end
		end
	end
	for id, info in pairs(result) do
		result[id] = info.list
	end
	return result
end

function DataPanel.Delete(id)
	id = tostring(id)
	local panel = panels[id] or panels[tonumber(id)]
	-- Always remove the database entry first so a partial failure in
	-- UI cleanup never re-saves an empty leftover panel on reload.
	if addon.db and addon.db.dataPanels then
		local named = panel and panel.name
		-- primary key cleanup
		addon.db.dataPanels[id] = nil
		if addon.db.dataPanels[tonumber(id)] then addon.db.dataPanels[tonumber(id)] = nil end
		-- defensive sweep: remove any entries that accidentally reference the same panel
		for k, info in pairs(addon.db.dataPanels) do
			if tostring(k) == id then
				addon.db.dataPanels[k] = nil
			elseif type(info) == "table" then
				if info.name == id or (named and info.name == named) then addon.db.dataPanels[k] = nil end
			end
		end
	end

	if panel then
		if EditMode and panel.editModeId then
			local ok, err = pcall(function() EditMode:UnregisterFrame(panel.editModeId) end)
			if not ok then geterrorhandler()(err) end
			panel.editModeRegistered = nil
			panel.editModeId = nil
		end
		-- Unsubscribe and detach all streams safely
		for i = #panel.order, 1, -1 do
			local ok = pcall(function() panel:RemoveStream(panel.order[i]) end)
			if not ok then
				-- continue cleanup even if a single stream removal fails
			end
		end
		if panel.frame then
			-- Prevent savePosition from firing during teardown
			panel.frame:SetScript("OnSizeChanged", nil)
			panel.frame:Hide()
			panel.frame:SetParent(nil)
		end
		panels[id] = nil
		if panels[tonumber(id)] then panels[tonumber(id)] = nil end
	end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("UI_SCALE_CHANGED")
initFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
initFrame:SetScript("OnEvent", function(self, event)
	if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
		scheduleInlineReflowAll()
		return
	end
	addon.db = addon.db or {}
	local panelsDB = addon.db.dataPanels or {}
	addon.db.dataPanels = panelsDB

	for id in pairs(panelsDB) do
		DataPanel.Create(id, nil, true)
	end

	self:UnregisterEvent("PLAYER_LOGIN")
	scheduleInlineReflowAll()
	if C_Timer and C_Timer.After then C_Timer.After(0.1, scheduleInlineReflowAll) end
end)

return DataPanel
