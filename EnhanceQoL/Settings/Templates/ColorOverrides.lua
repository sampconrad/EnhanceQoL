-- TODO - Colorpicker row has some wierd hight issue - need to correct that later

local DEFAULT_ROW_HEIGHT = 20
local DEFAULT_PADDING = 16
local DEFAULT_SPACING = 6

EQOL_ColorOverridesMixin = CreateFromMixins(SettingsListElementMixin)

local function WipeTable(tbl)
	if not tbl then return end
	for k in pairs(tbl) do
		tbl[k] = nil
	end
end

function EQOL_ColorOverridesMixin:OnLoad()
	SettingsListElementMixin.OnLoad(self)

	self.container = self.ItemQualities or self.List or self
	self.ColorOverrideFramePool = CreateFramePool("FRAME", self.container, "ColorOverrideTemplate")
	self.colorOverrideFrames = {}
end

function EQOL_ColorOverridesMixin:Init(initializer)
	SettingsListElementMixin.Init(self, initializer)

	self.categoryID = initializer.data.categoryID
	self.entries = initializer.data.entries or {}
	self.getColor = initializer.data.getColor
	self.setColor = initializer.data.setColor
	self.getDefaultColor = initializer.data.getDefaultColor
	self.headerText = initializer.data.headerText or ""
	self.rowHeight = initializer.data.rowHeight or DEFAULT_ROW_HEIGHT
	self.basePadding = initializer.data.basePadding or DEFAULT_PADDING
	self.minHeight = initializer.data.minHeight
	self.fixedHeight = initializer.data.height
	self.fixedSpacing = initializer.data.spacing
	self.parentCheck = initializer.data.parentCheck

	if self.Header then self.Header:SetText(self.headerText) end
	if self.NewFeature then self.NewFeature:SetShown(false) end

	if not self.callbacksRegistered then
		EventRegistry:RegisterCallback("Settings.Defaulted", self.ResetToDefaults, self)
		EventRegistry:RegisterCallback("Settings.CategoryDefaulted", function(_, category)
			if self.categoryID == category:GetID() then self:ResetToDefaults() end
		end, self)
		self.callbacksRegistered = true
	end

	self:RefreshRows()
end

function EQOL_ColorOverridesMixin:GetSpacing()
	local container = self.container
	if container and container.spacing then return container.spacing end
	return self.fixedSpacing or DEFAULT_SPACING
end

function EQOL_ColorOverridesMixin:RefreshRows()
	if not self.ColorOverrideFramePool then return end
	self.ColorOverrideFramePool:ReleaseAll()
	WipeTable(self.colorOverrideFrames)
	self.colorOverrideFrames = self.colorOverrideFrames or {}

	for index, entry in ipairs(self.entries or {}) do
		local frame = self.ColorOverrideFramePool:Acquire()
		frame.layoutIndex = index
		self:SetupRow(frame, entry)
		frame:Show()
		self.colorOverrideFrames[#self.colorOverrideFrames + 1] = frame
	end

	if self.container and self.container.MarkDirty then self.container:MarkDirty() end
	self:RefreshAll()
	self:EvaluateState() -- ensure fresh rows respect parent state immediately
end

function EQOL_ColorOverridesMixin:SetupRow(frame, entry)
	frame.data = entry
	if frame.Text then frame.Text:SetText(entry.label or entry.key or "?") end
	if frame.ColorSwatch then frame.ColorSwatch:SetScript("OnClick", function() self:OpenColorPicker(frame) end) end
end

function EQOL_ColorOverridesMixin:RefreshRow(frame)
	if not (self.getColor and frame.ColorSwatch and frame.ColorSwatch.Color) then return end
	local r, g, b = self.getColor(frame.data.key)
	r, g, b = r or 1, g or 1, b or 1
	frame.ColorSwatch.Color:SetVertexColor(r, g, b)
end

function EQOL_ColorOverridesMixin:RefreshAll()
	for _, frame in ipairs(self.colorOverrideFrames or {}) do
		self:RefreshRow(frame)
	end
end

function EQOL_ColorOverridesMixin:ResetToDefaults()
	if not (self.getDefaultColor and self.setColor) then return end
	for _, entry in ipairs(self.entries or {}) do
		local r, g, b = self.getDefaultColor(entry.key)
		r, g, b = r or 1, g or 1, b or 1
		self.setColor(entry.key, r, g, b)
	end
	self:RefreshAll()
end

function EQOL_ColorOverridesMixin:OpenColorPicker(frame)
	if not self.setColor then return end
	local currentR, currentG, currentB = self.getColor(frame.data.key)
	currentR, currentG, currentB = currentR or 1, currentG or 1, currentB or 1

	ColorPickerFrame:SetupColorPickerAndShow({
		r = currentR,
		g = currentG,
		b = currentB,
		hasOpacity = false,
		swatchFunc = function()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			self.setColor(frame.data.key, r, g, b)
			self:RefreshRow(frame)
		end,
		cancelFunc = function()
			local r, g, b = ColorPickerFrame:GetPreviousValues()
			r, g, b = r or currentR, g or currentG, b or currentB
			self.setColor(frame.data.key, r, g, b)
			self:RefreshRow(frame)
		end,
	})
end

function EQOL_ColorOverridesMixin:Release()
	if self.ColorOverrideFramePool then self.ColorOverrideFramePool:ReleaseAll() end
	SettingsListElementMixin.Release(self)
end

function EQOL_ColorOverridesMixin:EvaluateState()
	SettingsListElementMixin.EvaluateState(self)

	local enabled = true
	if self.parentCheck then enabled = self.parentCheck() end

	for _, frame in ipairs(self.colorOverrideFrames or {}) do
		if frame.ColorSwatch then frame.ColorSwatch:SetEnabled(enabled) end
		if frame.Text then frame.Text:SetFontObject(enabled and GameFontNormalSmall or GameFontDisableSmall) end
	end
end
