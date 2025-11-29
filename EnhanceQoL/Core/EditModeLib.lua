local _, addon = ...

-- Lightweight replacement for LibEditMode with the bits we actually use
local lib = addon.EditModeLib or {}
addon.EditModeLib = lib

if lib.__initialized then return end
lib.__initialized = true

lib.internal = lib.internal or {}
local internal = lib.internal

local layoutNames = setmetatable({ "Modern", "Classic" }, {
	__index = function(t, key)
		if key > 2 then
			local layouts = C_EditMode.GetLayouts().layouts
			if (key - 2) > #layouts then
				error("index is out of bounds")
			else
				return layouts[key - 2].layoutName
			end
		else
			return rawget(t, key)
		end
	end,
})

lib.frameSelections = lib.frameSelections or {}
lib.frameCallbacks = lib.frameCallbacks or {}
lib.frameDefaults = lib.frameDefaults or {}
lib.frameSettings = lib.frameSettings or {}
lib.frameButtons = lib.frameButtons or {}

lib.anonCallbacksEnter = lib.anonCallbacksEnter or {}
lib.anonCallbacksExit = lib.anonCallbacksExit or {}
lib.anonCallbacksLayout = lib.anonCallbacksLayout or {}

-- Pools -----------------------------------------------------------------------
local pools = {}
local PoolAcquire = CreateUnsecuredObjectPool().Acquire
local function poolAcquire(self, parent)
	local obj, new = PoolAcquire(self)
	if parent then obj:SetParent(parent) end
	return obj, new
end

function internal:CreatePool(kind, creationFunc, resetterFunc)
	local pool = CreateUnsecuredObjectPool(creationFunc, resetterFunc)
	pool.Acquire = poolAcquire
	pools[kind] = pool
end

function internal:GetPool(kind) return pools[kind] end

function internal:ReleaseAllPools()
	for _, pool in next, pools do
		pool:ReleaseAll()
	end
end

lib.SettingType = CopyTable(Enum.EditModeSettingDisplayType)
lib.SettingType.Color = "Color"
lib.SettingType.CheckboxColor = "CheckboxColor"
lib.SettingType.DropdownColor = "DropdownColor"

-- Widgets ---------------------------------------------------------------------
local checkboxMixin = {}
function checkboxMixin:Setup(data)
	self.setting = data
	self.Label:SetText(data.name)

	local value = data.get(lib.activeLayoutName)
	if value == nil then value = data.default end

	self.checked = value
	self.Button:SetChecked(not not value)
end

function checkboxMixin:OnCheckButtonClick()
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	self.checked = not self.checked
	self.setting.set(lib.activeLayoutName, not not self.checked)
	internal:RefreshSettings()
end

function checkboxMixin:SetEnabled(enabled)
	self.Button:SetEnabled(enabled)
	self.Label:SetFontObject(enabled and "GameFontHighlightMedium" or "GameFontDisable")
end

internal:CreatePool(lib.SettingType.Checkbox, function()
	local frame = CreateFrame("Frame", nil, UIParent, "EditModeSettingCheckboxTemplate")
	return Mixin(frame, checkboxMixin)
end, function(_, frame)
	frame:Hide()
	frame.layoutIndex = nil
	-- frame.setting = nil
end)

local function dropdownGet(data) return data.get(lib.activeLayoutName) == data.value end

local function dropdownSet(data)
	data.set(lib.activeLayoutName, data.value)
	internal:RefreshSettings()
end

local dropdownMixin = {}
function dropdownMixin:Setup(data)
	self.setting = data
	self.Label:SetText(data.name)
	self.ignoreInLayout = nil

	if data.generator then
		self.Dropdown:SetupMenu(function(owner, rootDescription) pcall(data.generator, owner, rootDescription, data) end)
	elseif data.values then
		self.Dropdown:SetupMenu(function(_, rootDescription)
			if data.height then rootDescription:SetScrollMode(data.height) end

			for _, value in next, data.values do
				if value.isRadio then
					rootDescription:CreateRadio(value.text, dropdownGet, dropdownSet, {
						get = data.get,
						set = data.set,
						value = value.text,
					})
				else
					rootDescription:CreateCheckbox(value.text, dropdownGet, dropdownSet, {
						get = data.get,
						set = data.set,
						value = value.text,
					})
				end
			end
		end)
	end
end

function dropdownMixin:SetEnabled(enabled)
	self.Dropdown:SetEnabled(enabled)
	self.Label:SetFontObject(enabled and "GameFontHighlightMedium" or "GameFontDisable")
end

internal:CreatePool(lib.SettingType.Dropdown, function()
	local frame = CreateFrame("Frame", nil, UIParent, "ResizeLayoutFrame")
	frame.fixedHeight = 32
	Mixin(frame, dropdownMixin)

	local label = frame:CreateFontString(nil, nil, "GameFontHighlightMedium")
	label:SetPoint("LEFT")
	label:SetWidth(100)
	label:SetJustifyH("LEFT")
	frame.Label = label

	local dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
	dropdown:SetPoint("LEFT", label, "RIGHT", 5, 0)
	dropdown:SetSize(200, 30)
	frame.Dropdown = dropdown

	return frame
end, function(_, frame)
	frame:Hide()
	frame.layoutIndex = nil
	-- frame.setting = nil
	-- frame.ignoreInLayout = true
end)

local sliderMixin = {}
function sliderMixin:Setup(data)
	self.setting = data
	self.Label:SetText(data.name)

	self.initInProgress = true
	self.formatters = {}
	self.formatters[MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(MinimalSliderWithSteppersMixin.Label.Right, data.formatter)

	local stepSize = data.valueStep or 1
	local steps = (data.maxValue - data.minValue) / stepSize
	self.Slider:Init(data.get(lib.activeLayoutName) or data.default, data.minValue or 0, data.maxValue or 1, steps, self.formatters)
	self.initInProgress = false
end

function sliderMixin:OnSliderValueChanged(value)
	if not self.initInProgress then
		self.setting.set(lib.activeLayoutName, value)
		internal:RefreshSettings()
	end
end

function sliderMixin:SetEnabled(enabled)
	self.Slider:SetEnabled(enabled)
	self.Label:SetFontObject(enabled and "GameFontHighlight" or "GameFontDisable")
end

internal:CreatePool(lib.SettingType.Slider, function()
	local frame = CreateFrame("Frame", nil, UIParent, "EditModeSettingSliderTemplate")
	Mixin(frame, sliderMixin)

	frame:SetHeight(32)
	frame.Slider:SetWidth(200)
	frame.Slider.MinText:Hide()
	frame.Slider.MaxText:Hide()
	frame.Label:SetPoint("LEFT")

	frame:OnLoad()
	return frame
end, function(_, frame)
	frame:Hide()
	frame.layoutIndex = nil
	-- frame.setting = nil
	-- frame.ignoreInLayout = true
end)

local function normalizeColor(value)
	if type(value) == "table" then
		return value.r or value[1] or 1, value.g or value[2] or 1, value.b or value[3] or 1, value.a or value[4]
	elseif type(value) == "number" then
		return value, value, value
	end
	return 1, 1, 1
end

local colorMixin = {}
function colorMixin:Setup(data)
	self.setting = data
	self.Label:SetText(data.name)
	self.ignoreInLayout = nil

	local r, g, b, a = normalizeColor(data.get(lib.activeLayoutName) or data.default)
	self.hasOpacity = not not (data.hasOpacity or a)
	self:SetColor(r, g, b, a)
end

function colorMixin:SetColor(r, g, b, a)
	self.r, self.g, self.b, self.a = r, g, b, a
	self.Swatch:SetColorTexture(r, g, b, 1)
end

function colorMixin:OnClick()
	local prev = { r = self.r or 1, g = self.g or 1, b = self.b or 1, a = self.a }

	ColorPickerFrame:SetupColorPickerAndShow({
		r = prev.r,
		g = prev.g,
		b = prev.b,
		opacity = prev.a,
		hasOpacity = self.hasOpacity,
		swatchFunc = function()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			local a = self.hasOpacity and (ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or prev.a)
			self:SetColor(r, g, b, a)
			self.setting.set(lib.activeLayoutName, { r = r, g = g, b = b, a = a })
			internal:RefreshSettings()
		end,
		opacityFunc = function()
			if not self.hasOpacity then return end
			local r, g, b = ColorPickerFrame:GetColorRGB()
			local a = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or prev.a
			self:SetColor(r, g, b, a)
			self.setting.set(lib.activeLayoutName, { r = r, g = g, b = b, a = a })
			internal:RefreshSettings()
		end,
		cancelFunc = function()
			self:SetColor(prev.r, prev.g, prev.b, prev.a)
			self.setting.set(lib.activeLayoutName, { r = prev.r, g = prev.g, b = prev.b, a = prev.a })
			internal:RefreshSettings()
		end,
	})
end

function colorMixin:SetEnabled(enabled)
	if enabled then
		self.Button:Enable()
		self.Swatch:SetVertexColor(1, 1, 1, 1)
		self.Label:SetFontObject("GameFontHighlightMedium")
	else
		self.Button:Disable()
		self.Swatch:SetVertexColor(0.4, 0.4, 0.4, 1)
		self.Label:SetFontObject("GameFontDisable")
	end
end

internal:CreatePool(lib.SettingType.Color, function()
	local frame = CreateFrame("Frame", nil, UIParent, "ResizeLayoutFrame")
	frame.fixedHeight = 32
	Mixin(frame, colorMixin)

	local label = frame:CreateFontString(nil, nil, "GameFontHighlightMedium")
	label:SetPoint("LEFT")
	label:SetWidth(100)
	label:SetJustifyH("LEFT")
	frame.Label = label

	local button = CreateFrame("Button", nil, frame)
	button:SetSize(36, 22)
	button:SetPoint("LEFT", label, "RIGHT", 8, 0)

	local border = button:CreateTexture(nil, "BACKGROUND")
	border:SetColorTexture(0.7, 0.7, 0.7, 1)
	border:SetAllPoints()

	local swatch = button:CreateTexture(nil, "ARTWORK")
	swatch:SetPoint("TOPLEFT", 2, -2)
	swatch:SetPoint("BOTTOMRIGHT", -2, 2)
	swatch:SetColorTexture(1, 1, 1, 1)
	frame.Swatch = swatch

	button:SetScript("OnClick", function() frame:OnClick() end)
	frame.Button = button

	return frame
end, function(_, frame)
	frame:Hide()
	frame.layoutIndex = nil
	-- frame.setting = nil
	-- frame.ignoreInLayout = true
end)

local checkboxColorMixin = {}
function checkboxColorMixin:Setup(data)
	self.setting = data
	self.Label:SetText(data.name)
	self.ignoreInLayout = nil

	local value = data.get and data.get(lib.activeLayoutName)
	if value == nil then value = data.default end
	self.checked = not not value
	self.Check:SetChecked(self.checked)

	local colorVal
	if data.colorGet then colorVal = data.colorGet(lib.activeLayoutName) end
	if not colorVal then colorVal = data.colorDefault or { 1, 1, 1, 1 } end
	local r, g, b, a = normalizeColor(colorVal)
	self.hasOpacity = not not (data.hasOpacity or a)
	self:SetColor(r, g, b, a)
	self:UpdateColorEnabled()
end

function checkboxColorMixin:UpdateColorEnabled()
	local enabled = self.checked
	if enabled then
		self.Button:Enable()
		self.Swatch:SetVertexColor(1, 1, 1, 1)
	else
		self.Button:Disable()
		self.Swatch:SetVertexColor(0.4, 0.4, 0.4, 1)
	end
end

function checkboxColorMixin:SetColor(r, g, b, a)
	self.r, self.g, self.b, self.a = r, g, b, a
	self.Swatch:SetColorTexture(r, g, b, 1)
end

function checkboxColorMixin:OnCheckboxClick()
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	self.checked = not self.checked
	if self.setting.set then self.setting.set(lib.activeLayoutName, self.checked) end
	self:UpdateColorEnabled()
	internal:RefreshSettings()
end

function checkboxColorMixin:OnColorClick()
	local prev = { r = self.r or 1, g = self.g or 1, b = self.b or 1, a = self.a }
	local apply = self.setting.colorSet or self.setting.setColor
	if not apply then return end

	ColorPickerFrame:SetupColorPickerAndShow({
		r = prev.r,
		g = prev.g,
		b = prev.b,
		opacity = prev.a,
		hasOpacity = self.hasOpacity,
		swatchFunc = function()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			local a = self.hasOpacity and (ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or prev.a)
			self:SetColor(r, g, b, a)
			apply(lib.activeLayoutName, { r = r, g = g, b = b, a = a })
			internal:RefreshSettings()
		end,
		opacityFunc = function()
			if not self.hasOpacity then return end
			local r, g, b = ColorPickerFrame:GetColorRGB()
			local a = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or prev.a
			self:SetColor(r, g, b, a)
			apply(lib.activeLayoutName, { r = r, g = g, b = b, a = a })
			internal:RefreshSettings()
		end,
		cancelFunc = function()
			self:SetColor(prev.r, prev.g, prev.b, prev.a)
			apply(lib.activeLayoutName, { r = prev.r, g = prev.g, b = prev.b, a = prev.a })
			internal:RefreshSettings()
		end,
	})
end

function checkboxColorMixin:SetEnabled(enabled)
	self.Check:SetEnabled(enabled)
	if not enabled then
		self.Button:Disable()
		self.Swatch:SetVertexColor(0.2, 0.2, 0.2, 1)
		self.Label:SetFontObject("GameFontDisable")
	else
		self:UpdateColorEnabled()
		self.Label:SetFontObject("GameFontHighlightMedium")
	end
end

local dropdownColorMixin = {}
function dropdownColorMixin:Setup(data)
	self.setting = data
	self.Label:SetText(data.name)
	self.ignoreInLayout = nil

	local function createEntries(rootDescription)
		if data.height then rootDescription:SetScrollMode(data.height) end

		local function getCurrent() return data.get(lib.activeLayoutName) end

		local function makeSetter(value)
			return function()
				data.set(lib.activeLayoutName, value)
				internal:RefreshSettings()
			end
		end

		if data.values then
			for _, value in next, data.values do
				if value.isRadio then
					rootDescription:CreateRadio(value.text, function() return getCurrent() == value.text end, makeSetter(value.text))
				else
					rootDescription:CreateCheckbox(value.text, function() return getCurrent() == value.text end, makeSetter(value.text))
				end
			end
		end
	end

	if data.generator then
		self.Dropdown:SetupMenu(function(owner, rootDescription) pcall(data.generator, owner, rootDescription, data) end)
	elseif data.values then
		self.Dropdown:SetupMenu(function(_, rootDescription) createEntries(rootDescription) end)
	end

	local colorVal
	if data.colorGet then colorVal = data.colorGet(lib.activeLayoutName) end
	if not colorVal then colorVal = data.colorDefault or { 1, 1, 1, 1 } end
	local r, g, b, a = normalizeColor(colorVal)
	self.hasOpacity = not not (data.hasOpacity or a)
	self:SetColor(r, g, b, a)
end

function dropdownColorMixin:SetColor(r, g, b, a)
	self.r, self.g, self.b, self.a = r, g, b, a
	self.Swatch:SetColorTexture(r, g, b, 1)
end

function dropdownColorMixin:OnColorClick()
	local prev = { r = self.r or 1, g = self.g or 1, b = self.b or 1, a = self.a }
	local apply = self.setting.colorSet or self.setting.setColor
	if not apply then return end

	ColorPickerFrame:SetupColorPickerAndShow({
		r = prev.r,
		g = prev.g,
		b = prev.b,
		opacity = prev.a,
		hasOpacity = self.hasOpacity,
		swatchFunc = function()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			local a = self.hasOpacity and (ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or prev.a)
			self:SetColor(r, g, b, a)
			apply(lib.activeLayoutName, { r = r, g = g, b = b, a = a })
			internal:RefreshSettings()
		end,
		opacityFunc = function()
			if not self.hasOpacity then return end
			local r, g, b = ColorPickerFrame:GetColorRGB()
			local a = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or prev.a
			self:SetColor(r, g, b, a)
			apply(lib.activeLayoutName, { r = r, g = g, b = b, a = a })
			internal:RefreshSettings()
		end,
		cancelFunc = function()
			self:SetColor(prev.r, prev.g, prev.b, prev.a)
			apply(lib.activeLayoutName, { r = prev.r, g = prev.g, b = prev.b, a = prev.a })
			internal:RefreshSettings()
		end,
	})
end

function dropdownColorMixin:SetEnabled(enabled)
	self.Dropdown:SetEnabled(enabled)
	if enabled then
		self.Button:Enable()
		self.Swatch:SetVertexColor(1, 1, 1, 1)
		self.Label:SetFontObject("GameFontHighlightMedium")
	else
		self.Button:Disable()
		self.Swatch:SetVertexColor(0.4, 0.4, 0.4, 1)
		self.Label:SetFontObject("GameFontDisable")
	end
end

internal:CreatePool(lib.SettingType.DropdownColor, function()
	local frame = CreateFrame("Frame", nil, UIParent, "ResizeLayoutFrame")
	frame.fixedHeight = 32
	Mixin(frame, dropdownColorMixin)

	local label = frame:CreateFontString(nil, nil, "GameFontHighlightMedium")
	label:SetPoint("LEFT")
	label:SetWidth(100)
	label:SetJustifyH("LEFT")
	frame.Label = label

	local dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
	dropdown:SetPoint("LEFT", label, "RIGHT", 5, 0)
	dropdown:SetSize(200, 30)
	frame.Dropdown = dropdown

	local button = CreateFrame("Button", nil, frame)
	button:SetSize(36, 22)
	button:SetPoint("LEFT", dropdown, "RIGHT", 6, 0)

	local border = button:CreateTexture(nil, "BACKGROUND")
	border:SetColorTexture(0.7, 0.7, 0.7, 1)
	border:SetAllPoints()

	local swatch = button:CreateTexture(nil, "ARTWORK")
	swatch:SetPoint("TOPLEFT", 2, -2)
	swatch:SetPoint("BOTTOMRIGHT", -2, 2)
	swatch:SetColorTexture(1, 1, 1, 1)
	frame.Swatch = swatch

	button:SetScript("OnClick", function() frame:OnColorClick() end)
	frame.Button = button

	return frame
end, function(_, frame)
	frame:Hide()
	frame.layoutIndex = nil
end)

internal:CreatePool(lib.SettingType.CheckboxColor, function()
	local frame = CreateFrame("Frame", "EQOLCPTest", UIParent, "ResizeLayoutFrame")
	frame.fixedHeight = 32
	Mixin(frame, checkboxColorMixin)

	local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	check:SetPoint("LEFT", -5, 0) -- slight left shift to align with other rows
	check:SetScript("OnClick", function(btn) btn:GetParent():OnCheckboxClick() end)
	frame.Check = check

	local label = frame:CreateFontString(nil, nil, "GameFontHighlightMedium")
	label:SetPoint("LEFT", check, "RIGHT", 2, 0)
	label:SetWidth(175)
	label:SetJustifyH("LEFT")
	frame.Label = label

	local button = CreateFrame("Button", nil, frame)
	button:SetSize(36, 22)
	button:SetPoint("LEFT", label, "RIGHT", 4, 0)

	local border = button:CreateTexture(nil, "BACKGROUND")
	border:SetColorTexture(0.7, 0.7, 0.7, 1)
	border:SetAllPoints()

	local swatch = button:CreateTexture(nil, "ARTWORK")
	swatch:SetPoint("TOPLEFT", 2, -2)
	swatch:SetPoint("BOTTOMRIGHT", -2, 2)
	swatch:SetColorTexture(1, 1, 1, 1)
	frame.Swatch = swatch

	button:SetScript("OnClick", function() frame:OnColorClick() end)
	frame.Button = button

	return frame
end, function(_, frame)
	frame:Hide()
	frame.layoutIndex = nil
	-- frame.setting = nil
	-- frame.ignoreInLayout = true
end)

internal:CreatePool("button", function() return CreateFrame("Button", nil, UIParent, "EditModeSystemSettingsDialogExtraButtonTemplate") end, function(_, frame)
	frame:Hide()
	frame.layoutIndex = nil
	-- frame.ignoreInLayout = true
	-- frame.setting = nil
end)

-- Dialog ----------------------------------------------------------------------
local dialogMixin = {}
function dialogMixin:Update(selection)
	self.selection = selection

	self.Title:SetText(selection.parent.editModeName or selection.parent:GetName())
	self:UpdateSettings()
	self:UpdateButtons()

	if not self:IsShown() then
		self:ClearAllPoints()
		self:SetPoint("BOTTOMRIGHT", UIParent, -250, 250)
	end

	self:Show()
	self:Layout()
end

function dialogMixin:UpdateSettings()
	internal:ReleaseAllPools()

	local settings, num = internal:GetFrameSettings(self.selection.parent)
	if num > 0 then
		for index, data in next, settings do
			local pool = internal:GetPool(data.kind)
			if pool then
				local setting = pool:Acquire(self.Settings)
				setting.layoutIndex = index
				setting:Setup(data)
				if setting.SetEnabled then
					local enabled = true
					if data.isEnabled then
						local ok, result = pcall(data.isEnabled, lib.activeLayoutName)
						enabled = ok and result ~= false
					elseif data.disabled then
						local ok, result = pcall(data.disabled, lib.activeLayoutName)
						enabled = not (ok and result == true)
					end
					setting:SetEnabled(enabled)
				end
				setting:Show()
			end
		end
	end

	self.Settings.ResetButton.layoutIndex = num + 1
	self.Settings.Divider.layoutIndex = num + 2
	self.Settings.ResetButton:SetEnabled(num > 0)
end

function dialogMixin:UpdateButtons()
	local buttonPool = internal:GetPool("button")
	if buttonPool then
		buttonPool:ReleaseAll()
	end

	local anyVisible = false
	local buttons, num = internal:GetFrameButtons(self.selection.parent)
	if num > 0 then
		for index, data in next, buttons do
			local button = buttonPool:Acquire(self.Buttons)
			button.layoutIndex = index
			button:SetText(data.text)
			button:SetOnClickHandler(data.click)
			button:Show()
			anyVisible = true
		end
	end

	local showReset = true
	if lib.frameResetVisible and lib.frameResetVisible[self.selection.parent] == false then showReset = false end
	if showReset and buttonPool then
		local resetPosition = buttonPool:Acquire(self.Buttons)
		resetPosition.layoutIndex = num + 1
		resetPosition:SetText(HUD_EDIT_MODE_RESET_POSITION)
		resetPosition:SetOnClickHandler(GenerateClosure(self.ResetPosition, self))
		resetPosition:Show()
		anyVisible = true
	end

	if anyVisible then
		self.Buttons.ignoreInLayout = nil
		self.Buttons:Show()
	else
		self.Buttons.ignoreInLayout = true
		self.Buttons:Hide()
	end
end

function dialogMixin:ResetSettings()
	local settings, num = internal:GetFrameSettings(self.selection.parent)
	if num > 0 then
		for _, data in next, settings do
			data.set(lib.activeLayoutName, data.default)
			if data.kind == lib.SettingType.CheckboxColor then
				local apply = data.colorSet or data.setColor
				if apply then apply(lib.activeLayoutName, data.colorDefault or { 1, 1, 1, 1 }) end
			end
		end

		self:Update(self.selection)
	end
end

function dialogMixin:ResetPosition()
	local parent = self.selection.parent
	local pos = lib:GetFrameDefaultPosition(parent)
	if not pos then pos = {
		point = "CENTER",
		x = 0,
		y = 0,
	} end

	parent:ClearAllPoints()
	parent:SetPoint(pos.point, pos.x, pos.y)

	internal:TriggerCallback(parent, pos.point, pos.x, pos.y)
end

function internal:CreateDialog()
	local dialog = Mixin(CreateFrame("Frame", nil, UIParent, "ResizeLayoutFrame"), dialogMixin)
	dialog:SetSize(300, 350)
	dialog:SetFrameStrata("DIALOG")
	dialog:SetFrameLevel(200)
	dialog:Hide()
	dialog.widthPadding = 40
	dialog.heightPadding = 40

	dialog:EnableMouse(true)
	dialog:SetMovable(true)
	dialog:SetClampedToScreen(true)
	dialog:SetDontSavePosition(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", function() dialog:StartMoving() end)
	dialog:SetScript("OnDragStop", function() dialog:StopMovingOrSizing() end)

	local dialogTitle = dialog:CreateFontString(nil, nil, "GameFontHighlightLarge")
	dialogTitle:SetPoint("TOP", 0, -15)
	dialog.Title = dialogTitle

	local dialogBorder = CreateFrame("Frame", nil, dialog, "DialogBorderTranslucentTemplate")
	dialogBorder.ignoreInLayout = true
	dialog.Border = dialogBorder

	local dialogClose = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
	dialogClose:SetPoint("TOPRIGHT")
	dialogClose.ignoreInLayout = true
	dialog.Close = dialogClose

	local dialogSettings = CreateFrame("Frame", nil, dialog, "VerticalLayoutFrame")
	dialogSettings:SetPoint("TOP", dialogTitle, "BOTTOM", 0, -12)
	dialogSettings.spacing = 2
	dialog.Settings = dialogSettings

	local resetSettingsButton = CreateFrame("Button", nil, dialogSettings, "EditModeSystemSettingsDialogButtonTemplate")
	resetSettingsButton:SetText(RESET_TO_DEFAULT)
	resetSettingsButton:SetOnClickHandler(GenerateClosure(dialog.ResetSettings, dialog))
	dialogSettings.ResetButton = resetSettingsButton

	local divider = dialogSettings:CreateTexture(nil, "ARTWORK")
	divider:SetSize(330, 16)
	divider:SetTexture([[Interface\FriendsFrame\UI-FriendsFrame-OnlineDivider]])
	dialogSettings.Divider = divider

	local dialogButtons = CreateFrame("Frame", nil, dialog, "VerticalLayoutFrame")
	dialogButtons:SetPoint("TOP", dialogSettings, "BOTTOM", 0, -12)
	dialogButtons.spacing = 2
	dialog.Buttons = dialogButtons

	return dialog
end

-- Core ------------------------------------------------------------------------
local function resetSelection()
	if internal.dialog then internal.dialog:Hide() end

	for frame, selection in next, lib.frameSelections do
		if selection.isSelected then frame:SetMovable(false) end

		if not lib.isEditing then
			selection:Hide()
			selection.isSelected = false
		else
			selection:ShowHighlighted()
		end
	end
end

local function isInCombat() return InCombatLockdown and InCombatLockdown() end

local function onDragStart(self)
	if isInCombat() then return end
	self.parent:StartMoving()
end

local function normalizePosition(frame)
	local parent = frame:GetParent()
	if not parent then return end

	local scale = frame:GetScale()
	if not scale then return end

	local left = frame:GetLeft() * scale
	local top = frame:GetTop() * scale
	local right = frame:GetRight() * scale
	local bottom = frame:GetBottom() * scale

	local parentWidth, parentHeight = parent:GetSize()

	local x, y, point
	if left < (parentWidth - right) and left < math.abs((left + right) / 2 - parentWidth / 2) then
		x = left
		point = "LEFT"
	elseif (parentWidth - right) < math.abs((left + right) / 2 - parentWidth / 2) then
		x = right - parentWidth
		point = "RIGHT"
	else
		x = (left + right) / 2 - parentWidth / 2
		point = ""
	end

	if bottom < (parentHeight - top) and bottom < math.abs((bottom + top) / 2 - parentHeight / 2) then
		y = bottom
		point = "BOTTOM" .. point
	elseif (parentHeight - top) < math.abs((bottom + top) / 2 - parentHeight / 2) then
		y = top - parentHeight
		point = "TOP" .. point
	else
		y = (bottom + top) / 2 - parentHeight / 2
		point = "" .. point
	end

	if point == "" then point = "CENTER" end

	return point, x / scale, y / scale
end

local function adjustPosition(frame, dx, dy)
	local scale = frame:GetScale() or 1
	local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
	if not point then
		point, relativePoint, x, y = "CENTER", "CENTER", 0, 0
	end

	x = (x or 0) + dx / scale
	y = (y or 0) + dy / scale

	frame:ClearAllPoints()
	frame:SetPoint(point, relativeTo or UIParent, relativePoint or point, x, y)

	internal:TriggerCallback(frame, point, x, y)
end

local function onDragStop(self)
	local parent = self.parent
	parent:StopMovingOrSizing()

	if isInCombat() then return end

	local point, x, y = normalizePosition(parent)
	if not point then return end
	parent:ClearAllPoints()
	parent:SetPoint(point, x, y)

	internal:TriggerCallback(parent, point, x, y)
end

local function onMouseDown(self)
	if isInCombat() then return end
	resetSelection()
	if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem then EditModeManagerFrame:ClearSelectedSystem() end

	if not self.isSelected then
		self.parent:SetMovable(true)
		self:ShowSelected(true)
		self.isSelected = true
		if internal.dialog then internal.dialog:Update(self) end
	end
end

local function onEditModeEnter()
	lib.isEditing = true

	resetSelection()

	for _, callback in next, lib.anonCallbacksEnter do
		securecallfunction(callback)
	end
end

local function onEditModeExit()
	lib.isEditing = false

	resetSelection()

	for _, callback in next, lib.anonCallbacksExit do
		securecallfunction(callback)
	end
end

local function onEditModeChanged(_, layoutInfo)
	local layoutName = layoutNames[layoutInfo.activeLayout]
	if layoutName ~= lib.activeLayoutName then
		lib.activeLayoutName = layoutName

		for _, callback in next, lib.anonCallbacksLayout do
			securecallfunction(callback, layoutName)
		end
	end
end

function lib:AddFrame(frame, callback, default)
	local selection = CreateFrame("Frame", nil, frame, "EditModeSystemSelectionTemplate")
	selection:SetAllPoints()
	selection:SetScript("OnMouseDown", onMouseDown)
	selection:SetScript("OnDragStart", onDragStart)
	selection:SetScript("OnDragStop", onDragStop)
	selection:SetScript("OnKeyDown", function(self, key)
		if not self.isSelected or isInCombat() then return end
		local step = IsShiftKeyDown() and 10 or 1
		if key == "UP" then
			if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
			adjustPosition(self.parent, 0, step)
		elseif key == "DOWN" then
			if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
			adjustPosition(self.parent, 0, -step)
		elseif key == "LEFT" then
			if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
			adjustPosition(self.parent, -step, 0)
		elseif key == "RIGHT" then
			if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
			adjustPosition(self.parent, step, 0)
		else
			if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
		end
	end)
	selection:SetScript("OnKeyUp", function(self)
		if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
	end)
	selection:EnableKeyboard(true)
	if selection.SetPropagateKeyboardInput then selection:SetPropagateKeyboardInput(true) end
	selection:Hide()

	if select(4, GetBuildInfo()) >= 110200 then
		selection.system = {}
		selection.system.GetSystemName = function() return frame.editModeName or frame:GetName() end
	else
		selection.Label:SetText(frame.editModeName or frame:GetName())
	end

	lib.frameSelections[frame] = selection
	lib.frameCallbacks[frame] = callback
	lib.frameDefaults[frame] = default

	if not internal.dialog then
		internal.dialog = internal:CreateDialog()
		internal.dialog:HookScript("OnHide", function() resetSelection() end)

		local combatWatcher = CreateFrame("Frame")
		combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
		combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
		combatWatcher:SetScript("OnEvent", function(_, event)
			if event == "PLAYER_REGEN_DISABLED" then
				resetSelection()
			elseif event == "PLAYER_REGEN_ENABLED" and lib.isEditing then
				resetSelection()
			end
		end)

		EventRegistry:RegisterFrameEventAndCallback("EDIT_MODE_LAYOUTS_UPDATED", onEditModeChanged)

		EditModeManagerFrame:HookScript("OnShow", onEditModeEnter)
		EditModeManagerFrame:HookScript("OnHide", onEditModeExit)

		hooksecurefunc(EditModeManagerFrame, "SelectSystem", function() resetSelection() end)
	end
end

function lib:AddFrameSettings(frame, settings)
	if not lib.frameSelections[frame] then error("frame must be registered") end

	lib.frameSettings[frame] = settings
end

function lib:AddFrameSettingsButton(frame, data)
	if not lib.frameButtons[frame] then lib.frameButtons[frame] = {} end

	table.insert(lib.frameButtons[frame], data)
end

function lib:SetFrameResetVisible(frame, showReset)
	lib.frameResetVisible = lib.frameResetVisible or {}
	lib.frameResetVisible[frame] = not not showReset
end

function lib:RegisterCallback(event, callback)
	assert(event and type(event) == "string", "event must be a string")
	assert(callback and type(callback) == "function", "callback must be a function")

	if event == "enter" then
		table.insert(lib.anonCallbacksEnter, callback)
	elseif event == "exit" then
		table.insert(lib.anonCallbacksExit, callback)
	elseif event == "layout" then
		table.insert(lib.anonCallbacksLayout, callback)
	else
		error('invalid callback event "' .. event .. '"')
	end
end

function lib:GetActiveLayoutName() return lib.activeLayoutName end

function lib:IsInEditMode() return not not lib.isEditing end

function lib:GetFrameDefaultPosition(frame) return lib.frameDefaults[frame] end

function internal:TriggerCallback(frame, ...)
	if lib.frameCallbacks[frame] then securecallfunction(lib.frameCallbacks[frame], frame, lib.activeLayoutName, ...) end
end

function internal:GetFrameSettings(frame)
	if lib.frameSettings[frame] then
		return lib.frameSettings[frame], #lib.frameSettings[frame]
	else
		return nil, 0
	end
end

function internal:GetFrameButtons(frame)
	if lib.frameButtons[frame] then
		return lib.frameButtons[frame], #lib.frameButtons[frame]
	else
		return nil, 0
	end
end

function internal:RefreshSettings()
	if not (internal.dialog and internal.dialog:IsShown()) then return end
	local parent = internal.dialog.Settings
	if not parent then return end

	for _, child in ipairs({ parent:GetChildren() }) do
		if child.SetEnabled and child.setting then
			local data = child.setting
			local enabled = true
			if data.isEnabled then
				local ok, result = pcall(data.isEnabled, lib.activeLayoutName)
				enabled = ok and result ~= false
			elseif data.disabled then
				local ok, result = pcall(data.disabled, lib.activeLayoutName)
				enabled = not (ok and result == true)
			end
			child:SetEnabled(enabled)
		end
	end
end
