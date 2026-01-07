local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.ActionTracker = addon.ActionTracker or {}
local ActionTracker = addon.ActionTracker

local L = LibStub("AceLocale-3.0"):GetLocale(parentAddonName)
local EditMode = addon.EditMode
local SettingType = EditMode and EditMode.lib and EditMode.lib.SettingType

local EDITMODE_ID = "actionTracker"
local MAX_ICONS_LIMIT = 10
local FADE_TICK = 0.05

ActionTracker.defaults = ActionTracker.defaults or {
	maxIcons = 5,
	iconSize = 48,
	spacing = 0,
	direction = "RIGHT",
	fadeDuration = 0,
}

local defaults = ActionTracker.defaults

local DB_ENABLED = "actionTrackerEnabled"
local DB_MAX_ICONS = "actionTrackerMaxIcons"
local DB_ICON_SIZE = "actionTrackerIconSize"
local DB_SPACING = "actionTrackerSpacing"
local DB_DIRECTION = "actionTrackerDirection"
local DB_FADE = "actionTrackerFadeDuration"

local VALID_DIRECTIONS = {
	RIGHT = true,
	LEFT = true,
	UP = true,
	DOWN = true,
}

ActionTracker.entries = ActionTracker.entries or {}

local function getValue(key, fallback)
	if not addon.db then return fallback end
	local value = addon.db[key]
	if value == nil then return fallback end
	return value
end

local function normalizeDirection(direction)
	if VALID_DIRECTIONS[direction] then return direction end
	return defaults.direction
end

function ActionTracker:GetIconSize()
	local size = tonumber(getValue(DB_ICON_SIZE, defaults.iconSize)) or defaults.iconSize
	if size < 16 then size = 16 end
	return size
end

function ActionTracker:GetMaxIcons()
	local maxIcons = tonumber(getValue(DB_MAX_ICONS, defaults.maxIcons)) or defaults.maxIcons
	maxIcons = math.floor(maxIcons + 0.5)
	if maxIcons < 1 then maxIcons = 1 end
	if maxIcons > MAX_ICONS_LIMIT then maxIcons = MAX_ICONS_LIMIT end
	return maxIcons
end

function ActionTracker:GetSpacing()
	local spacing = tonumber(getValue(DB_SPACING, defaults.spacing)) or defaults.spacing
	if spacing < 0 then spacing = 0 end
	return spacing
end

function ActionTracker:GetDirection() return normalizeDirection(getValue(DB_DIRECTION, defaults.direction)) end

function ActionTracker:GetFadeDuration()
	local fade = tonumber(getValue(DB_FADE, defaults.fadeDuration)) or defaults.fadeDuration
	if fade < 0 then fade = 0 end
	return fade
end

function ActionTracker:GetEntryAlpha(entry, now, fade)
	local duration = fade
	if duration == nil then duration = self:GetFadeDuration() end
	if duration <= 0 then return 1 end
	local age = (now or GetTime()) - (entry.time or 0)
	if age >= duration then return 0 end
	return 1 - (age / duration)
end

function ActionTracker:TrimEntries()
	local maxIcons = self:GetMaxIcons()
	while #self.entries > maxIcons do
		table.remove(self.entries, 1)
	end
end

local function applyIconSize(icon, size)
	icon:SetSize(size, size)
	if icon.texture then icon.texture:SetAllPoints(icon) end
	if icon.cooldown then icon.cooldown:SetAllPoints(icon) end
end

function ActionTracker:EnsureFrame()
	if self.frame then return self.frame end

	local frame = CreateFrame("Frame", "EQOL_ActionTrackerFrame", UIParent)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame.icons = {}

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(frame)
	bg:SetColorTexture(0.1, 0.6, 0.6, 0.2)
	bg:Hide()
	frame.bg = bg

	local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("CENTER")
	label:SetText(L["ActionTracker"] or "Action Tracker")
	label:Hide()
	frame.label = label

	for i = 1, MAX_ICONS_LIMIT do
		local icon = CreateFrame("Frame", nil, frame)
		icon:SetAlpha(0)
		icon:Hide()

		icon.texture = icon:CreateTexture(nil, "ARTWORK")
		icon.texture:SetAllPoints(icon)

		icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
		icon.cooldown:SetAllPoints(icon)

		icon:SetScript("OnEnter", function(selfIcon)
			if not selfIcon.spellID then return end
			GameTooltip:SetOwner(selfIcon, "ANCHOR_RIGHT")
			GameTooltip:SetSpellByID(selfIcon.spellID)
			GameTooltip:Show()
		end)
		icon:SetScript("OnLeave", GameTooltip_Hide)

		frame.icons[i] = icon
	end

	self.frame = frame
	self:UpdateLayout()
	self:RefreshIcons()

	return frame
end

function ActionTracker:ShowEditModeHint(show)
	if not self.frame then return end
	if show then
		self.frame.bg:Show()
		self.frame.label:Show()
	else
		self.frame.bg:Hide()
		self.frame.label:Hide()
	end
end

function ActionTracker:UpdateLayout()
	local frame = self.frame
	if not frame then return end

	local iconSize = self:GetIconSize()
	local maxIcons = self:GetMaxIcons()
	local spacing = self:GetSpacing()
	local direction = self:GetDirection()

	local total = (iconSize * maxIcons) + (spacing * (maxIcons - 1))
	if direction == "LEFT" or direction == "RIGHT" then
		frame:SetSize(total, iconSize)
	else
		frame:SetSize(iconSize, total)
	end

	for i = 1, MAX_ICONS_LIMIT do
		local icon = frame.icons[i]
		local offset = (i - 1) * (iconSize + spacing)

		applyIconSize(icon, iconSize)
		icon:ClearAllPoints()
		if direction == "RIGHT" then
			icon:SetPoint("LEFT", frame, "LEFT", offset, 0)
		elseif direction == "LEFT" then
			icon:SetPoint("RIGHT", frame, "RIGHT", -offset, 0)
		elseif direction == "DOWN" then
			icon:SetPoint("TOP", frame, "TOP", 0, -offset)
		else
			icon:SetPoint("BOTTOM", frame, "BOTTOM", 0, offset)
		end
	end
end

function ActionTracker:RefreshIcons()
	local frame = self.frame
	if not frame then return end

	local entries = self.entries
	local maxIcons = self:GetMaxIcons()
	local now = GetTime()
	local fade = self:GetFadeDuration()

	self:TrimEntries()

	for i = 1, MAX_ICONS_LIMIT do
		local icon = frame.icons[i]
		local entry = i <= maxIcons and entries[i] or nil
		if entry then
			local texture = entry.texture or (entry.spellID and C_Spell.GetSpellTexture(entry.spellID))
			icon.texture:SetTexture(texture)
			icon.spellID = entry.spellID

			if entry.cooldownStart and entry.cooldownDuration then
				icon.cooldown:SetCooldown(entry.cooldownStart, entry.cooldownDuration)
			else
				icon.cooldown:Clear()
			end

			icon:SetAlpha(self:GetEntryAlpha(entry, now, fade))
			icon:Show()
		else
			icon.spellID = nil
			icon.texture:SetTexture(nil)
			icon.cooldown:Clear()
			icon:SetAlpha(0)
			icon:Hide()
		end
	end
end

function ActionTracker:StartFadeUpdate()
	if self.fadeTicker or not self.frame then return end
	local tracker = self
	self.fadeTicker = C_Timer.NewTicker(FADE_TICK, function() tracker:UpdateFade() end)
end

function ActionTracker:StopFadeUpdate()
	if self.fadeTicker then
		self.fadeTicker:Cancel()
		self.fadeTicker = nil
	end
end

function ActionTracker:UpdateFade()
	local fade = self:GetFadeDuration()
	if fade <= 0 then
		self:StopFadeUpdate()
		return
	end

	local now = GetTime()
	local removed
	for i = #self.entries, 1, -1 do
		if (now - (self.entries[i].time or 0)) >= fade then
			table.remove(self.entries, i)
			removed = true
		end
	end

	if removed then
		self:RefreshIcons()
	else
		for i, entry in ipairs(self.entries) do
			local icon = self.frame and self.frame.icons and self.frame.icons[i]
			if icon then icon:SetAlpha(self:GetEntryAlpha(entry, now, fade)) end
		end
	end

	if #self.entries == 0 then self:StopFadeUpdate() end
end

function ActionTracker:UpdateFadeState(skipRefresh)
	local fade = self:GetFadeDuration()
	self:TrimEntries()
	if fade <= 0 or #self.entries == 0 then
		self:StopFadeUpdate()
		if not skipRefresh then self:RefreshIcons() end
		return
	end
	self:StartFadeUpdate()
	if not skipRefresh then self:RefreshIcons() end
end

function ActionTracker:ClearEntries()
	wipe(self.entries)
	self:StopFadeUpdate()
	self:RefreshIcons()
end

function ActionTracker:AddEntry(spellID)
	if not spellID then return end

	local texture = C_Spell.GetSpellTexture(spellID)
	if not texture then return end

	local entry = {
		spellID = spellID,
		texture = texture,
		time = GetTime(),
	}

	local start, duration, enabled = C_Spell.GetSpellCooldown(spellID)
	if enabled == 1 and duration and duration > 1.5 then
		entry.cooldownStart = start
		entry.cooldownDuration = duration
	end

	self.entries[#self.entries + 1] = entry
	local maxIcons = self:GetMaxIcons()
	while #self.entries > maxIcons do
		table.remove(self.entries, 1)
	end

	self:RefreshIcons()
	self:UpdateFadeState(true)
end

function ActionTracker:OnEvent(event, unit, arg2, arg3, arg4)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		local spellID = arg3
		self:AddEntry(spellID)
	end
end

function ActionTracker:RegisterEvents()
	if self.eventsRegistered then return end
	local frame = self:EnsureFrame()
	frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	frame:SetScript("OnEvent", function(_, event, ...) ActionTracker:OnEvent(event, ...) end)
	self.eventsRegistered = true
end

function ActionTracker:UnregisterEvents()
	if not self.eventsRegistered or not self.frame then return end
	self.frame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	self.frame:SetScript("OnEvent", nil)
	self.eventsRegistered = false
end

local editModeRegistered = false

function ActionTracker:ApplyLayoutData(data)
	if not data or not addon.db then return end

	local size = tonumber(data.size) or defaults.iconSize
	if size < 16 then size = 16 end

	local maxIcons = tonumber(data.maxIcons) or self:GetMaxIcons()
	maxIcons = math.floor(maxIcons + 0.5)
	if maxIcons < 1 then maxIcons = 1 end
	if maxIcons > MAX_ICONS_LIMIT then maxIcons = MAX_ICONS_LIMIT end

	local spacing = tonumber(data.spacing) or defaults.spacing
	if spacing < 0 then spacing = 0 end

	local direction = normalizeDirection(data.direction)
	local fade = tonumber(data.fade) or defaults.fadeDuration
	if fade < 0 then fade = 0 end

	addon.db[DB_MAX_ICONS] = maxIcons
	addon.db[DB_ICON_SIZE] = size
	addon.db[DB_SPACING] = spacing
	addon.db[DB_DIRECTION] = direction
	addon.db[DB_FADE] = fade

	self:TrimEntries()
	self:UpdateLayout()
	self:RefreshIcons()
	self:UpdateFadeState(true)
end

local function applySetting(field, value)
	if not addon.db then return end

	if field == "maxIcons" then
		local maxIcons = tonumber(value) or defaults.maxIcons
		maxIcons = math.floor(maxIcons + 0.5)
		if maxIcons < 1 then maxIcons = 1 end
		if maxIcons > MAX_ICONS_LIMIT then maxIcons = MAX_ICONS_LIMIT end
		addon.db[DB_MAX_ICONS] = maxIcons
		value = maxIcons
	elseif field == "size" then
		local size = tonumber(value) or defaults.iconSize
		if size < 16 then size = 16 end
		addon.db[DB_ICON_SIZE] = size
		value = size
	elseif field == "spacing" then
		local spacing = tonumber(value) or defaults.spacing
		if spacing < 0 then spacing = 0 end
		addon.db[DB_SPACING] = spacing
		value = spacing
	elseif field == "direction" then
		local direction = normalizeDirection(value)
		addon.db[DB_DIRECTION] = direction
		value = direction
	elseif field == "fade" then
		local fade = tonumber(value) or defaults.fadeDuration
		if fade < 0 then fade = 0 end
		addon.db[DB_FADE] = fade
		value = fade
	end

	if EditMode and EditMode.SetValue then EditMode:SetValue(EDITMODE_ID, field, value, nil, true) end
	ActionTracker:TrimEntries()
	ActionTracker:UpdateLayout()
	ActionTracker:RefreshIcons()
	ActionTracker:UpdateFadeState(true)
end

function ActionTracker:RegisterEditMode()
	if editModeRegistered or not EditMode or not EditMode.RegisterFrame then return end

	local directionOptions = {
		{ value = "RIGHT", label = L["actionTrackerDirectionRight"] or "Right" },
		{ value = "LEFT", label = L["actionTrackerDirectionLeft"] or "Left" },
		{ value = "UP", label = L["actionTrackerDirectionUp"] or "Up" },
		{ value = "DOWN", label = L["actionTrackerDirectionDown"] or "Down" },
	}

	local settings
	if SettingType then
		settings = {
			{
				name = L["actionTrackerMaxIcons"] or "Max icons",
				kind = SettingType.Slider,
				field = "maxIcons",
				default = defaults.maxIcons,
				minValue = 1,
				maxValue = MAX_ICONS_LIMIT,
				valueStep = 1,
				get = function() return ActionTracker:GetMaxIcons() end,
				set = function(_, value) applySetting("maxIcons", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = L["actionTrackerIconSize"] or "Icon size",
				kind = SettingType.Slider,
				field = "size",
				default = defaults.iconSize,
				minValue = 16,
				maxValue = 128,
				valueStep = 1,
				get = function() return ActionTracker:GetIconSize() end,
				set = function(_, value) applySetting("size", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = L["actionTrackerSpacing"] or "Icon spacing",
				kind = SettingType.Slider,
				field = "spacing",
				default = defaults.spacing,
				minValue = 0,
				maxValue = 50,
				valueStep = 1,
				get = function() return ActionTracker:GetSpacing() end,
				set = function(_, value) applySetting("spacing", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = L["actionTrackerDirection"] or "Icon direction",
				kind = SettingType.Dropdown,
				field = "direction",
				height = 120,
				get = function() return ActionTracker:GetDirection() end,
				set = function(_, value) applySetting("direction", value) end,
				generator = function(_, root)
					for _, option in ipairs(directionOptions) do
						root:CreateRadio(option.label, function() return ActionTracker:GetDirection() == option.value end, function() applySetting("direction", option.value) end)
					end
				end,
			},
			{
				name = L["actionTrackerFadeDuration"] or "Fade duration",
				kind = SettingType.Slider,
				field = "fade",
				default = defaults.fadeDuration,
				minValue = 0,
				maxValue = 10,
				valueStep = 1,
				get = function() return ActionTracker:GetFadeDuration() end,
				set = function(_, value) applySetting("fade", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
		}
	end

	EditMode:RegisterFrame(EDITMODE_ID, {
		frame = self:EnsureFrame(),
		title = L["ActionTracker"] or "Action Tracker",
		layoutDefaults = {
			point = "CENTER",
			relativePoint = "CENTER",
			x = 0,
			y = -200,
			maxIcons = self:GetMaxIcons(),
			size = self:GetIconSize(),
			spacing = self:GetSpacing(),
			direction = self:GetDirection(),
			fade = self:GetFadeDuration(),
		},
		onApply = function(_, _, data) ActionTracker:ApplyLayoutData(data) end,
		onEnter = function() ActionTracker:ShowEditModeHint(true) end,
		onExit = function() ActionTracker:ShowEditModeHint(false) end,
		isEnabled = function() return addon.db and addon.db[DB_ENABLED] end,
		settings = settings,
		showOutsideEditMode = true,
	})

	editModeRegistered = true
end

function ActionTracker:OnSettingChanged(enabled)
	if enabled then
		self:EnsureFrame()
		self:RegisterEditMode()
		self:RegisterEvents()
		self:UpdateLayout()
		self:RefreshIcons()
		self:UpdateFadeState(true)
	else
		self:UnregisterEvents()
		self:ClearEntries()
		if self.frame then self.frame:Hide() end
	end

	if EditMode and EditMode.RefreshFrame then EditMode:RefreshFrame(EDITMODE_ID) end
end
