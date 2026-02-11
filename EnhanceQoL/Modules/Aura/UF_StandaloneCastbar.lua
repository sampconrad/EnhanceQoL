-- luacheck: globals Enum
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Aura = addon.Aura or {}
addon.Aura.Castbar = addon.Aura.Castbar or addon.Aura.UFStandaloneCastbar or {}
addon.Aura.UFStandaloneCastbar = addon.Aura.Castbar
local Castbar = addon.Aura.Castbar
local UFHelper = addon.Aura.UFHelper
if not UFHelper then return end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")
local After = C_Timer and C_Timer.After
local issecretvalue = _G.issecretvalue
local UNIT = "player"
local EDITMODE_FRAME_ID = "EQOL_Castbar"
local EDITMODE_SETTINGS_MAX_HEIGHT = 900
local MIN_CASTBAR_WIDTH = 50
local CASTBAR_CONFIG_VERSION = 1
local DEFAULT_NOT_INTERRUPTIBLE_COLOR = { 204 / 255, 204 / 255, 204 / 255, 1 }
local RELATIVE_ANCHOR_FRAME_MAP = {
	PlayerFrame = { uf = "EQOLUFPlayerFrame", blizz = "PlayerFrame", ufKey = "player" },
	EQOLUFPlayerFrame = { uf = "EQOLUFPlayerFrame", blizz = "PlayerFrame", ufKey = "player" },
	TargetFrame = { uf = "EQOLUFTargetFrame", blizz = "TargetFrame", ufKey = "target" },
	EQOLUFTargetFrame = { uf = "EQOLUFTargetFrame", blizz = "TargetFrame", ufKey = "target" },
	TargetFrameToT = { uf = "EQOLUFToTFrame", blizz = "TargetFrameToT", ufKey = "targettarget" },
	EQOLUFToTFrame = { uf = "EQOLUFToTFrame", blizz = "TargetFrameToT", ufKey = "targettarget" },
	FocusFrame = { uf = "EQOLUFFocusFrame", blizz = "FocusFrame", ufKey = "focus" },
	EQOLUFFocusFrame = { uf = "EQOLUFFocusFrame", blizz = "FocusFrame", ufKey = "focus" },
	PetFrame = { uf = "EQOLUFPetFrame", blizz = "PetFrame", ufKey = "pet" },
	EQOLUFPetFrame = { uf = "EQOLUFPetFrame", blizz = "PetFrame", ufKey = "pet" },
	BossTargetFrameContainer = { uf = "EQOLUFBossContainer", blizz = "BossTargetFrameContainer", ufKey = "boss" },
	EQOLUFBossContainer = { uf = "EQOLUFBossContainer", blizz = "BossTargetFrameContainer", ufKey = "boss" },
}
local VALID_ANCHOR_POINTS = {
	TOPLEFT = true,
	TOP = true,
	TOPRIGHT = true,
	LEFT = true,
	CENTER = true,
	RIGHT = true,
	BOTTOMLEFT = true,
	BOTTOM = true,
	BOTTOMRIGHT = true,
}

local state = Castbar._state or {}
Castbar._state = state
local onUpdateActive = false

local fallbackCastDefaults = {
	enabled = false,
	width = 220,
	height = 16,
	anchor = "BOTTOM",
	offset = { x = 0, y = -4 },
	backdrop = { enabled = true, color = { 0, 0, 0, 0.6 } },
	border = {
		enabled = false,
		color = { 0, 0, 0, 0.8 },
		texture = "DEFAULT",
		edgeSize = 1,
		offset = 1,
	},
	showName = true,
	nameMaxChars = 0,
	showCastTarget = false,
	nameOffset = { x = 6, y = 0 },
	showDuration = true,
	durationFormat = "REMAINING",
	durationOffset = { x = -6, y = 0 },
	font = nil,
	fontSize = 12,
	showIcon = true,
	iconSize = 22,
	iconOffset = { x = -4, y = 0 },
	texture = "DEFAULT",
	color = { 0.9, 0.7, 0.2, 1 },
	useClassColor = false,
	notInterruptibleColor = DEFAULT_NOT_INTERRUPTIBLE_COLOR,
	showInterruptFeedback = true,
}

local function copyValue(value)
	if type(value) ~= "table" then return value end
	if addon.functions and addon.functions.copyTable then return addon.functions.copyTable(value) end
	return CopyTable(value)
end

local function mergeDefaults(target, defaults)
	for key, value in pairs(defaults or {}) do
		if target[key] == nil then
			target[key] = copyValue(value)
		elseif type(target[key]) == "table" and type(value) == "table" then
			mergeDefaults(target[key], value)
		end
	end
end

local function normalizeAnchorPoint(value, fallback)
	local point = tostring(value or fallback or "CENTER"):upper()
	if VALID_ANCHOR_POINTS[point] then return point end
	return tostring(fallback or "CENTER"):upper()
end

local function legacyAnchorToPoints(anchorValue)
	local anchor = type(anchorValue) == "string" and anchorValue:upper() or "BOTTOM"
	if anchor == "TOP" then return "BOTTOM", "CENTER" end
	if anchor == "BOTTOM" then return "TOP", "CENTER" end
	return "CENTER", "CENTER"
end

local function ensureAnchorConfig(castCfg, castDefaults)
	castCfg = castCfg or {}
	castDefaults = castDefaults or fallbackCastDefaults
	local anchorValue = castCfg.anchor
	local defaultsAnchorValue = castDefaults.anchor
	local legacyAnchor = (type(anchorValue) == "string" and anchorValue) or (type(defaultsAnchorValue) == "string" and defaultsAnchorValue) or "BOTTOM"
	local fallbackPoint, fallbackRelativePoint = legacyAnchorToPoints(legacyAnchor)
	local fallbackOffset = castCfg.offset or castDefaults.offset or { x = 0, y = -4 }
	local fallbackX = tonumber(fallbackOffset and fallbackOffset.x) or 0
	local fallbackY = tonumber(fallbackOffset and fallbackOffset.y) or 0

	if type(anchorValue) ~= "table" then
		anchorValue = {
			point = fallbackPoint,
			relativePoint = fallbackRelativePoint,
			relativeFrame = "UIParent",
			x = fallbackX,
			y = fallbackY,
		}
		castCfg.anchor = anchorValue
	end

	anchorValue.point = normalizeAnchorPoint(anchorValue.point, fallbackPoint)
	anchorValue.relativePoint = normalizeAnchorPoint(anchorValue.relativePoint, anchorValue.point or fallbackRelativePoint)
	if anchorValue.x == nil then
		anchorValue.x = fallbackX
	else
		anchorValue.x = tonumber(anchorValue.x) or fallbackX
	end
	if anchorValue.y == nil then
		anchorValue.y = fallbackY
	else
		anchorValue.y = tonumber(anchorValue.y) or fallbackY
	end
	if type(anchorValue.relativeFrame) ~= "string" or anchorValue.relativeFrame == "" then anchorValue.relativeFrame = "UIParent" end
	if (anchorValue.relativeFrame or "UIParent") == "UIParent" then anchorValue.matchRelativeWidth = nil end
	return anchorValue
end

local function anchorUsesUIParent(castCfg, castDefaults)
	local anchor = ensureAnchorConfig(castCfg, castDefaults)
	return (anchor.relativeFrame or "UIParent") == "UIParent"
end

local function wantsRelativeFrameWidthMatch(anchor) return anchor and (anchor.relativeFrame or "UIParent") ~= "UIParent" and anchor.matchRelativeWidth == true end

local function isMappedUFEnabled(ufKey)
	local ufCfg = addon.db and addon.db.ufFrames
	local cfg = ufCfg and ufCfg[ufKey]
	return cfg and cfg.enabled == true
end

local function resolveRelativeFrameByName(relativeName)
	if not relativeName or relativeName == "" or relativeName == "UIParent" then return UIParent end
	local mapped = RELATIVE_ANCHOR_FRAME_MAP[relativeName]
	if mapped then
		if mapped.ufKey and isMappedUFEnabled(mapped.ufKey) then
			local ufFrame = _G[mapped.uf]
			if ufFrame then return ufFrame end
		end
		local blizzFrame = _G[mapped.blizz]
		if blizzFrame then return blizzFrame end
	end
	return _G[relativeName] or UIParent
end

local function getRelativeFrameHookTargets(relativeName)
	local targets = {}
	local seen = {}
	local function add(name)
		if type(name) ~= "string" or name == "" or seen[name] then return end
		seen[name] = true
		targets[#targets + 1] = name
	end
	local mapped = RELATIVE_ANCHOR_FRAME_MAP[relativeName]
	if mapped then
		add(mapped.blizz)
		add(mapped.uf)
	end
	add(relativeName)
	return targets
end

local function resolveRelativeFrame(anchor)
	local relativeName = anchor and anchor.relativeFrame or "UIParent"
	return resolveRelativeFrameByName(relativeName)
end

local function getIconLayoutInfo(castCfg, castDefaults, barHeight)
	local showIcon = castCfg.showIcon
	if showIcon == nil then showIcon = castDefaults.showIcon ~= false end
	local iconSize = tonumber(castCfg.iconSize or castDefaults.iconSize or barHeight or 22) or 22
	if iconSize < 1 then iconSize = 1 end
	local iconOffset = castCfg.iconOffset or castDefaults.iconOffset or { x = -4, y = 0 }
	local iconOffsetX
	if type(iconOffset) == "table" then
		iconOffsetX = tonumber(iconOffset.x) or -4
	else
		iconOffsetX = tonumber(iconOffset) or -4
	end
	return showIcon == true, iconSize, iconOffsetX
end

local function getIconOverlapWithBar(castCfg, castDefaults, barHeight, barWidth)
	local showIcon, iconSize, iconOffsetX = getIconLayoutInfo(castCfg, castDefaults, barHeight)
	if not showIcon then return 0 end
	local width = tonumber(barWidth) or 0
	if width <= 0 then return 0 end
	local iconLeft = iconOffsetX - iconSize
	local iconRight = iconOffsetX
	local overlap = math.min(width, iconRight) - math.max(0, iconLeft)
	if overlap < 0 then overlap = 0 end
	return overlap
end

local function getHorizontalAnchorFactor(point)
	point = tostring(point or "CENTER"):upper()
	if point:find("LEFT", 1, true) then return 0 end
	if point:find("RIGHT", 1, true) then return 1 end
	return 0.5
end

local function getBarHorizontalOutsets(castCfg, castDefaults)
	local left = 0
	local right = 0

	local texKey = castCfg.texture
	if texKey == nil then texKey = castDefaults.texture end
	local useDefaultArt = not texKey or texKey == "" or texKey == "DEFAULT"
	local backdrop = castCfg.backdrop
	if backdrop == nil then backdrop = castDefaults.backdrop end
	if type(backdrop) == "table" and backdrop.enabled ~= false and useDefaultArt then
		left = math.max(left, 1)
		right = math.max(right, 1)
	end

	local border = castCfg.border
	if border == nil then border = castDefaults.border end
	if type(border) == "table" and border.enabled ~= false then
		local offset = tonumber(border.offset)
		if offset == nil then
			local defBorder = castDefaults.border
			offset = type(defBorder) == "table" and tonumber(defBorder.offset) or nil
		end
		offset = math.max(0, offset or 1)

		local edgeSize = tonumber(border.edgeSize)
		if edgeSize == nil then
			local defBorder = castDefaults.border
			edgeSize = type(defBorder) == "table" and tonumber(defBorder.edgeSize) or nil
		end
		edgeSize = math.max(0, edgeSize or 1)

		local borderOutset = offset + edgeSize
		left = math.max(left, borderOutset)
		right = math.max(right, borderOutset)
	end

	return left, right
end

local function getVisualHorizontalBounds(castCfg, castDefaults, barHeight, barWidth)
	local width = tonumber(barWidth) or 0
	if width < 0 then width = 0 end
	local barLeftOutset, barRightOutset = getBarHorizontalOutsets(castCfg, castDefaults)
	local minX = -barLeftOutset
	local maxX = width + barRightOutset
	local showIcon, iconSize, iconOffsetX = getIconLayoutInfo(castCfg, castDefaults, barHeight)
	if showIcon then
		local iconLeft = iconOffsetX - iconSize
		local iconRight = iconOffsetX
		if iconLeft < minX then minX = iconLeft end
		if iconRight > maxX then maxX = iconRight end
	end
	return minX, maxX
end

local function getEffectiveScale(frame)
	if frame and frame.GetEffectiveScale then
		local scale = frame:GetEffectiveScale()
		if type(scale) == "number" and scale > 0 then return scale end
	end
	return 1
end

local function computeBarWidthForAnchorMatch(targetWidth, castCfg, castDefaults, barHeight)
	local desiredTotal = tonumber(targetWidth) or MIN_CASTBAR_WIDTH
	if desiredTotal < MIN_CASTBAR_WIDTH then desiredTotal = MIN_CASTBAR_WIDTH end

	local barLeftOutset, barRightOutset = getBarHorizontalOutsets(castCfg, castDefaults)
	local minX = -barLeftOutset
	local iconRight
	local showIcon, iconSize, iconOffsetX = getIconLayoutInfo(castCfg, castDefaults, barHeight)
	if showIcon then
		local iconLeft = iconOffsetX - iconSize
		if iconLeft < minX then minX = iconLeft end
		iconRight = iconOffsetX
	end

	local barWidth = desiredTotal + minX - barRightOutset
	if iconRight and iconRight > (barWidth + barRightOutset) then barWidth = iconRight - barRightOutset end
	if barWidth < MIN_CASTBAR_WIDTH then barWidth = MIN_CASTBAR_WIDTH end
	return barWidth
end

local function computeAnchorMatchXAdjustment(castCfg, castDefaults, barHeight, barWidth, point)
	local width = tonumber(barWidth) or 0
	if width <= 0 then return 0 end
	local minX, maxX = getVisualHorizontalBounds(castCfg, castDefaults, barHeight, width)
	local visualWidth = maxX - minX
	local anchorFactor = getHorizontalAnchorFactor(point)
	-- Shift bar anchor so the configured anchor point targets the visual bounds,
	-- not only the statusbar rectangle.
	return -minX - anchorFactor * (visualWidth - width)
end

local relativeFrameWidthHooked = Castbar._relativeFrameWidthHooked or {}
local pendingRelativeFrameHookRetry = Castbar._pendingRelativeFrameHookRetry or {}
Castbar._relativeFrameWidthHooked = relativeFrameWidthHooked
Castbar._pendingRelativeFrameHookRetry = pendingRelativeFrameHookRetry
local relativeWidthSyncPending = false

local function scheduleRelativeFrameWidthSync()
	if relativeWidthSyncPending then return end
	if not After then
		Castbar.Refresh()
		return
	end
	relativeWidthSyncPending = true
	After(0.15, function()
		relativeWidthSyncPending = false
		Castbar.Refresh()
	end)
end

local function onRelativeFrameGeometryChanged() scheduleRelativeFrameWidthSync() end

local function ensureRelativeFrameHooks(frameName)
	if not frameName or frameName == "" or frameName == "UIParent" then return end
	local foundFrame = false
	for _, targetName in ipairs(getRelativeFrameHookTargets(frameName)) do
		local frame = _G[targetName]
		if frame then
			foundFrame = true
			if not relativeFrameWidthHooked[targetName] and frame.HookScript then
				local okSize = pcall(frame.HookScript, frame, "OnSizeChanged", onRelativeFrameGeometryChanged)
				local okShow = pcall(frame.HookScript, frame, "OnShow", onRelativeFrameGeometryChanged)
				local okHide = pcall(frame.HookScript, frame, "OnHide", onRelativeFrameGeometryChanged)
				if okSize or okShow or okHide then
					relativeFrameWidthHooked[targetName] = true
					scheduleRelativeFrameWidthSync()
				end
			end
		end
	end
	if foundFrame then return end
	if not foundFrame then
		if After and not pendingRelativeFrameHookRetry[frameName] then
			pendingRelativeFrameHookRetry[frameName] = true
			After(1, function()
				pendingRelativeFrameHookRetry[frameName] = nil
				ensureRelativeFrameHooks(frameName)
			end)
		end
		return
	end
end

local function resolveCastbarWidth(castCfg, castDefaults, barHeight)
	local width = tonumber(castCfg.width or castDefaults.width or 220) or 220
	if width < MIN_CASTBAR_WIDTH then width = MIN_CASTBAR_WIDTH end
	local anchor = ensureAnchorConfig(castCfg, castDefaults)
	if not wantsRelativeFrameWidthMatch(anchor) then return width end
	ensureRelativeFrameHooks(anchor.relativeFrame)
	local relFrame = resolveRelativeFrame(anchor)
	if not relFrame or relFrame == UIParent or not relFrame.GetWidth then return width end
	local relWidth = relFrame:GetWidth() or 0
	if relWidth <= 0 then return width end
	local relScale = getEffectiveScale(relFrame)
	local castScale = getEffectiveScale(state.castBar)
	local visualWidth = relWidth * relScale
	local targetWidth = visualWidth / castScale
	return computeBarWidthForAnchorMatch(targetWidth, castCfg, castDefaults, barHeight)
end

local function getCastDefaults() return fallbackCastDefaults end

local function ensureCastConfig()
	addon.db = addon.db or {}
	local castDefaults = getCastDefaults()
	addon.db.castbar = type(addon.db.castbar) == "table" and addon.db.castbar or {}
	local castCfg = addon.db.castbar

	local version = tonumber(castCfg.__version) or 0
	if version ~= CASTBAR_CONFIG_VERSION then
		mergeDefaults(castCfg, castDefaults)
		castCfg.__version = CASTBAR_CONFIG_VERSION
	end

	if castCfg.enabled == nil then castCfg.enabled = false end
	local anchor = castCfg.anchor
	if type(anchor) ~= "table" or anchor.point == nil or anchor.relativePoint == nil or anchor.x == nil or anchor.y == nil or type(anchor.relativeFrame) ~= "string" or anchor.relativeFrame == "" then
		ensureAnchorConfig(castCfg, castDefaults)
	end
	return castCfg, castDefaults
end

local function isCastbarEnabled()
	local castCfg = ensureCastConfig()
	return castCfg.enabled == true
end

local function shouldShowSampleCast()
	local lib = addon.EditModeLib
	return lib and lib.IsInEditMode and lib:IsInEditMode()
end

local function ensureCastBorderFrame()
	if not state.castBar then return nil end
	local border = state.castBorder
	if not border then
		border = CreateFrame("Frame", nil, state.castBar, "BackdropTemplate")
		border:EnableMouse(false)
		state.castBorder = border
	end
	border:SetFrameStrata(state.castBar:GetFrameStrata())
	local baseLevel = state.castBar:GetFrameLevel() or 0
	border:SetFrameLevel(baseLevel + 3)
	return border
end

local function applyCastBorder(castCfg, castDefaults)
	if not state.castBar then return end
	local borderCfg = (castCfg and castCfg.border) or (castDefaults and castDefaults.border) or {}
	if borderCfg.enabled == true then
		local border = ensureCastBorderFrame()
		if not border then return end
		local size = tonumber(borderCfg.edgeSize) or 1
		if size < 1 then size = 1 end
		local offset = borderCfg.offset
		if offset == nil then offset = size end
		offset = math.max(0, tonumber(offset) or 0)
		border:ClearAllPoints()
		border:SetPoint("TOPLEFT", state.castBar, "TOPLEFT", -offset, offset)
		border:SetPoint("BOTTOMRIGHT", state.castBar, "BOTTOMRIGHT", offset, -offset)
		border:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = UFHelper.resolveBorderTexture(borderCfg.texture),
			edgeSize = size,
			insets = { left = size, right = size, top = size, bottom = size },
		})
		border:SetBackdropColor(0, 0, 0, 0)
		local color = borderCfg.color or { 0, 0, 0, 0.8 }
		border:SetBackdropBorderColor(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
		border:Show()
	else
		local border = state.castBorder
		if border then
			border:SetBackdrop(nil)
			border:Hide()
		end
	end
end

local function ensureFrame()
	if state.castBar then return end
	state.frame = CreateFrame("Frame", "EQOLPlayerCastFrame", UIParent)
	state.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
	state.frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
	state.frame:EnableMouse(false)
	state.frame:SetMovable(false)
	state.frame:Show()

	state.castBar = CreateFrame("StatusBar", "EQOLPlayerCastBar", state.frame, "BackdropTemplate")
	state.castBar:SetMovable(true)
	state.castBar:SetClampedToScreen(true)
	state.castBar:SetStatusBarDesaturated(true)
	state.castBar:SetMinMaxValues(0, 1)
	state.castBar:SetValue(0)
	state.castBar:Hide()

	state.castTextLayer = CreateFrame("Frame", nil, state.castBar)
	state.castTextLayer:SetAllPoints(state.castBar)
	state.castIconLayer = CreateFrame("Frame", nil, state.castBar)
	state.castIconLayer:SetAllPoints(state.castBar)
	state.castIconLayer:EnableMouse(false)

	state.castName = state.castTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	state.castDuration = state.castTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	state.castIcon = state.castIconLayer:CreateTexture(nil, "ARTWORK")
	state.castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

local function roundNumber(value)
	value = tonumber(value) or 0
	if value >= 0 then return math.floor(value + 0.5) end
	return math.ceil(value - 0.5)
end

local function updateAnchorFromFrame(frame, layoutData)
	local castCfg, castDefaults = ensureCastConfig()
	local anchor = ensureAnchorConfig(castCfg, castDefaults)
	if (anchor.relativeFrame or "UIParent") ~= "UIParent" then return end

	if type(layoutData) == "table" and layoutData.point then
		anchor.point = normalizeAnchorPoint(layoutData.point, anchor.point or "CENTER")
		anchor.relativePoint = normalizeAnchorPoint(layoutData.relativePoint or layoutData.point, anchor.point)
		anchor.x = roundNumber(layoutData.x or 0)
		anchor.y = roundNumber(layoutData.y or 0)
		return
	end

	if not frame or not frame.GetPoint then return end
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	anchor.point = normalizeAnchorPoint(point, anchor.point or "CENTER")
	anchor.relativePoint = normalizeAnchorPoint(relativePoint or point, anchor.point)
	anchor.x = roundNumber(x or 0)
	anchor.y = roundNumber(y or 0)
end

local function ensureEditModeCallbacks()
	if Castbar._editModeCallbacksRegistered then return end
	local lib = addon.EditModeLib
	if not (lib and lib.RegisterCallback) then return end
	Castbar._editModeCallbacksRegistered = true
	lib:RegisterCallback("enter", function() Castbar.Refresh() end)
	lib:RegisterCallback("exit", function() Castbar.Refresh() end)
end

local function tryRegisterEditModeSettings()
	if Castbar._editModeSettingsApplied then return end
	if not Castbar._editModeRegistered then return end
	local settings = Castbar._editModeSettings
	if type(settings) ~= "table" or #settings == 0 then return end
	local editMode = addon.EditMode
	if not (editMode and editMode.RegisterSettings) then return end
	editMode:RegisterSettings(EDITMODE_FRAME_ID, settings)
	Castbar._editModeSettingsApplied = true
	if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RefreshSettings then addon.EditModeLib.internal:RefreshSettings() end
	if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RefreshSettingValues then addon.EditModeLib.internal:RefreshSettingValues() end
end

local function ensureEditModeRegistration()
	if Castbar._editModeRegistered then return end
	local editMode = addon.EditMode
	if not (editMode and editMode.RegisterFrame) then return end
	ensureFrame()

	local castCfg, castDefaults = ensureCastConfig()
	local anchorCfg = ensureAnchorConfig(castCfg, castDefaults)
	local width = castCfg.width or castDefaults.width or 220
	local height = castCfg.height or castDefaults.height or 16

	editMode:RegisterFrame(EDITMODE_FRAME_ID, {
		frame = state.castBar,
		title = L["UFStandaloneCastbar"] or L["CastBar"] or "Castbar",
		enableOverlayToggle = true,
		allowDrag = function()
			local cfg, defs = ensureCastConfig()
			return (isCastbarEnabled() or shouldShowSampleCast()) and anchorUsesUIParent(cfg, defs)
		end,
		managePosition = false,
		settingsMaxHeight = EDITMODE_SETTINGS_MAX_HEIGHT,
		layoutDefaults = {
			point = anchorCfg.point or "CENTER",
			relativePoint = anchorCfg.relativePoint or anchorCfg.point or "CENTER",
			x = anchorCfg.x or 0,
			y = anchorCfg.y or 0,
			width = width,
			height = height,
		},
		onPositionChanged = function(frame, _, data)
			updateAnchorFromFrame(frame, data)
			Castbar.Refresh()
		end,
		isEnabled = function() return isCastbarEnabled() or shouldShowSampleCast() end,
		settings = Castbar._editModeSettings,
		showOutsideEditMode = false,
		showReset = false,
	})

	if addon.EditModeLib and addon.EditModeLib.SetFrameSettingsResetVisible then addon.EditModeLib:SetFrameSettingsResetVisible(state.castBar, false) end
	Castbar._editModeRegistered = true
	Castbar._editModeSettingsApplied = false
	tryRegisterEditModeSettings()
end

function Castbar.SetEditModeSettings(settings)
	Castbar._editModeSettings = type(settings) == "table" and settings or nil
	Castbar._editModeSettingsApplied = false
	tryRegisterEditModeSettings()
end

function Castbar.GetConfig()
	local castCfg, castDefaults = ensureCastConfig()
	return castCfg, castDefaults
end

function Castbar.GetDefaults() return copyValue(getCastDefaults() or fallbackCastDefaults) end

local function getClassColor(class)
	if not class then return nil end
	local fallback = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
	if fallback then return fallback.r or fallback[1], fallback.g or fallback[2], fallback.b or fallback[3], fallback.a or fallback[4] or 1 end
	return nil
end

local function clearCastInterruptState()
	if state.castInterruptAnim then state.castInterruptAnim:Stop() end
	if state.castInterruptGlowAnim then state.castInterruptGlowAnim:Stop() end
	if state.castInterruptGlow then state.castInterruptGlow:Hide() end
	UFHelper.hideCastSpark(state)
	if state.castBar then state.castBar:SetAlpha(1) end
	state.castInterruptActive = nil
	state.castInterruptToken = (state.castInterruptToken or 0) + 1
end

local function stopCast()
	if not state.castBar then return end
	clearCastInterruptState()
	UFHelper.clearEmpowerStages(state)
	UFHelper.hideCastSpark(state)
	state.castBar:Hide()
	if state.castName then state.castName:SetText("") end
	if state.castDuration then state.castDuration:SetText("") end
	if state.castIcon then state.castIcon:Hide() end
	state.castIconTexture = nil
	state.castTarget = nil
	state.castInfo = nil
	state.castBarDuration = nil
	if onUpdateActive then
		state.castBar:SetScript("OnUpdate", nil)
		onUpdateActive = false
	end
end

local function applyCastLayout(castCfg, castDefaults)
	ensureFrame()
	castCfg = castCfg or {}
	castDefaults = castDefaults or fallbackCastDefaults
	local height = castCfg.height or castDefaults.height or 16
	local width = resolveCastbarWidth(castCfg, castDefaults, height)
	if width < MIN_CASTBAR_WIDTH then width = MIN_CASTBAR_WIDTH end
	state.castBar:SetSize(width, height)

	local anchor = ensureAnchorConfig(castCfg, castDefaults)
	if (anchor.relativeFrame or "UIParent") ~= "UIParent" then ensureRelativeFrameHooks(anchor.relativeFrame) end
	local relativeFrame = resolveRelativeFrame(anchor)
	local point = anchor.point or "CENTER"
	local relativePoint = anchor.relativePoint or point
	local ox = anchor.x or 0
	local oy = anchor.y or 0
	if wantsRelativeFrameWidthMatch(anchor) then
		local castScale = getEffectiveScale(state.castBar)
		local relativeScale = getEffectiveScale(relativeFrame)
		local xAdjust = computeAnchorMatchXAdjustment(castCfg, castDefaults, height, width, point)
		ox = ox + (xAdjust * (castScale / relativeScale))
	end
	state.castBar:ClearAllPoints()
	state.castBar:SetPoint(point, relativeFrame, relativePoint, ox, oy)

	if state.castName then
		local nameOff = castCfg.nameOffset or castDefaults.nameOffset or { x = 6, y = 0 }
		state.castName:ClearAllPoints()
		state.castName:SetPoint("LEFT", state.castBar, "LEFT", nameOff.x or 0, nameOff.y or 0)
		state.castName:SetShown(castCfg.showName ~= false)
	end
	if state.castDuration then
		local durOff = castCfg.durationOffset or castDefaults.durationOffset or { x = -6, y = 0 }
		state.castDuration:ClearAllPoints()
		state.castDuration:SetPoint("RIGHT", state.castBar, "RIGHT", durOff.x or 0, durOff.y or 0)
		state.castDuration:SetShown(castCfg.showDuration ~= false)
		if state.castDuration.SetWordWrap then state.castDuration:SetWordWrap(false) end
		if state.castDuration.SetJustifyH then state.castDuration:SetJustifyH("RIGHT") end
	end
	if state.castIcon then
		local size = castCfg.iconSize or castDefaults.iconSize or height
		local iconOff = castCfg.iconOffset or castDefaults.iconOffset or { x = -4, y = 0 }
		if type(iconOff) ~= "table" then iconOff = { x = iconOff, y = 0 } end
		state.castIcon:SetSize(size, size)
		state.castIcon:ClearAllPoints()
		state.castIcon:SetPoint("RIGHT", state.castBar, "LEFT", iconOff.x or -4, iconOff.y or 0)
		state.castIcon:SetShown(castCfg.showIcon ~= false)
	end

	local texKey = castCfg.texture or castDefaults.texture or "DEFAULT"
	local useDefaultArt = not texKey or texKey == "" or texKey == "DEFAULT"
	local castTexture = UFHelper.resolveCastTexture(texKey)
	state.castBar:SetStatusBarTexture(castTexture)
	state.castUseDefaultArt = useDefaultArt

	do -- Cast backdrop
		local bd = castCfg.backdrop or castDefaults.backdrop or { enabled = true, color = { 0, 0, 0, 0.6 } }
		if state.castBar.SetBackdrop then state.castBar:SetBackdrop(nil) end
		local bg = state.castBar.backdropTexture
		if bd.enabled == false then
			if bg then bg:Hide() end
		else
			if not bg then
				bg = state.castBar:CreateTexture(nil, "BACKGROUND")
				state.castBar.backdropTexture = bg
			end
			local col = bd.color or { 0, 0, 0, 0.6 }
			bg:ClearAllPoints()
			if useDefaultArt and bg.SetAtlas then
				bg:SetAtlas("ui-castingbar-background", false)
				bg:SetPoint("TOPLEFT", state.castBar, "TOPLEFT", -1, 1)
				bg:SetPoint("BOTTOMRIGHT", state.castBar, "BOTTOMRIGHT", 1, -1)
			else
				bg:SetTexture(castTexture)
				bg:SetAllPoints(state.castBar)
			end
			bg:SetVertexColor(col[1] or 0, col[2] or 0, col[3] or 0, col[4] or 0.6)
			bg:Show()
		end
	end
	applyCastBorder(castCfg, castDefaults)

	if state.castName then
		local iconSpace = getIconOverlapWithBar(castCfg, castDefaults, height, width)
		if iconSpace > 0 then iconSpace = iconSpace + 4 end
		local durationSpace = (castCfg.showDuration ~= false) and 60 or 0
		local available = (width or 0) - iconSpace - durationSpace - 6
		if available < 0 then available = 0 end
		local maxChars = castCfg.nameMaxChars
		if maxChars == nil then maxChars = castDefaults.nameMaxChars end
		maxChars = tonumber(maxChars) or 0
		if maxChars > 0 and UFHelper.getNameLimitWidth then
			local castFont = castCfg.font or castDefaults.font
			local castFontSize = castCfg.fontSize or castDefaults.fontSize or 12
			local castOutline = castCfg.fontOutline or castDefaults.fontOutline or "OUTLINE"
			local maxWidth = UFHelper.getNameLimitWidth(castFont, castFontSize, castOutline, maxChars)
			if maxWidth and maxWidth > 0 then available = maxWidth end
		end
		state.castName:SetWidth(available)
		if state.castName.SetWordWrap then state.castName:SetWordWrap(false) end
		if state.castName.SetMaxLines then state.castName:SetMaxLines(1) end
		if state.castName.SetJustifyH then state.castName:SetJustifyH("LEFT") end
	end
	if state.castEmpower and state.castEmpower.stagePercents then UFHelper.layoutEmpowerStages(state) end
end

local function applyCastFont(castCfg, castDefaults)
	local castFont = castCfg.font or castDefaults.font
	local castFontSize = castCfg.fontSize or castDefaults.fontSize or 12
	local castOutline = castCfg.fontOutline or castDefaults.fontOutline or "OUTLINE"
	UFHelper.applyFont(state.castName, castFont, castFontSize, castOutline)
	UFHelper.applyFont(state.castDuration, castFont, castFontSize, castOutline)
	local castFontColor = castCfg.fontColor or castDefaults.fontColor
	if castFontColor then
		local r = castFontColor.r or castFontColor[1] or 1
		local g = castFontColor.g or castFontColor[2] or 1
		local b = castFontColor.b or castFontColor[3] or 1
		local a = castFontColor.a or castFontColor[4] or 1
		if state.castName then state.castName:SetTextColor(r, g, b, a) end
		if state.castDuration then state.castDuration:SetTextColor(r, g, b, a) end
	end
end

local function configureCastStatic(castCfg, castDefaults)
	if not state.castBar or not state.castInfo then return end
	local clr = castCfg.color or castDefaults.color or { 0.9, 0.7, 0.2, 1 }
	local useClassColor = castCfg.useClassColor
	if useClassColor == nil then useClassColor = castDefaults.useClassColor end
	if useClassColor == true then
		local class = select(2, UnitClass(UNIT))
		local cr, cg, cb, ca = getClassColor(class)
		if cr then clr = { cr, cg, cb, ca or 1 } end
	end
	if state.castInfo.notInterruptible then
		clr = castCfg.notInterruptibleColor or castDefaults.notInterruptibleColor or clr
		state.castBar:SetStatusBarDesaturated(true)
	else
		state.castBar:SetStatusBarDesaturated(false)
	end
	state.castBar:SetStatusBarColor(clr[1] or 0.9, clr[2] or 0.7, clr[3] or 0.2, clr[4] or 1)
	local duration = (state.castInfo.endTime or 0) - (state.castInfo.startTime or 0)
	local maxValue = duration and duration > 0 and duration / 1000 or 1
	state.castInfo.maxValue = maxValue
	state.castBar:SetMinMaxValues(0, maxValue)
	if state.castName then
		local showName = castCfg.showName ~= false
		state.castName:SetShown(showName)
		local nameText = showName and (state.castInfo.name or "") or ""
		if showName and UFHelper.formatCastName then
			local showTarget = castCfg.showCastTarget
			if showTarget == nil then showTarget = castDefaults.showCastTarget end
			nameText = UFHelper.formatCastName(nameText, state.castTarget, showTarget == true)
		end
		state.castName:SetText(nameText)
	end
	if state.castIcon then
		local showIcon = castCfg.showIcon ~= false and state.castInfo.texture ~= nil
		state.castIcon:SetShown(showIcon)
		if showIcon then
			state.castIcon:SetTexture(state.castInfo.texture)
			state.castIconTexture = state.castInfo.texture
		end
	end
	if state.castDuration then state.castDuration:SetShown(castCfg.showDuration ~= false) end
	state.castBar:Show()
end

local function updateCastBar()
	local castCfg, castDefaults = ensureCastConfig()
	local info = state.castInfo
	if not state.castBar or not info or castCfg.enabled == false then
		stopCast()
		return
	end
	if not info.startTime or not info.endTime then
		stopCast()
		return
	end
	if issecretvalue and (issecretvalue(info.startTime) or issecretvalue(info.endTime)) then
		stopCast()
		return
	end

	local nowMs = GetTime() * 1000
	local startMs = info.startTime or 0
	local endMs = info.endTime or 0
	local duration = endMs - startMs
	if not duration or duration <= 0 then
		stopCast()
		return
	end

	if nowMs >= endMs then
		if shouldShowSampleCast() then
			-- Keep a preview while in Edit Mode.
			local sampleDuration = 2
			state.castInfo = {
				name = L["Sample Cast"] or "Sample Cast",
				texture = 136243,
				startTime = nowMs,
				endTime = nowMs + sampleDuration * 1000,
				notInterruptible = false,
				isChannel = false,
				maxValue = sampleDuration,
			}
			configureCastStatic(castCfg, castDefaults)
		else
			stopCast()
		end
		return
	end

	local elapsedMs = info.isChannel and (endMs - nowMs) or (nowMs - startMs)
	if elapsedMs < 0 then elapsedMs = 0 end
	local value = elapsedMs / 1000
	state.castBar:SetValue(value)

	if info.isEmpowered then
		local maxValue = info.maxValue
		if not maxValue then
			local _, maxVal = state.castBar:GetMinMaxValues()
			maxValue = maxVal
		end
		if maxValue and maxValue > 0 and (not issecretvalue or (not issecretvalue(value) and not issecretvalue(maxValue))) then UFHelper.updateEmpowerStageFromProgress(state, value / maxValue) end
		UFHelper.updateCastSpark(state, "empowered")
	else
		UFHelper.hideCastSpark(state)
	end

	if state.castDuration then
		if castCfg.showDuration ~= false then
			local durationFormat = castCfg.durationFormat or castDefaults.durationFormat or "REMAINING"
			if durationFormat == "ELAPSED_TOTAL" then
				local total = duration / 1000
				local elapsed = (nowMs - startMs) / 1000
				if elapsed < 0 then elapsed = 0 end
				if elapsed > total then elapsed = total end
				state.castDuration:SetText(("%.1f / %.1f"):format(elapsed, total))
			elseif durationFormat == "REMAINING_TOTAL" then
				local total = duration / 1000
				local remaining = (endMs - nowMs) / 1000
				if remaining < 0 then remaining = 0 end
				state.castDuration:SetText(("%.1f / %.1f"):format(remaining, total))
			else
				local remaining = (endMs - nowMs) / 1000
				if remaining < 0 then remaining = 0 end
				state.castDuration:SetText(("%.1f"):format(remaining))
			end
			state.castDuration:Show()
		else
			state.castDuration:SetText("")
			state.castDuration:Hide()
		end
	end
end

local function setSampleCast()
	local castCfg, castDefaults = ensureCastConfig()
	if castCfg.enabled == false then
		stopCast()
		return
	end
	applyCastLayout(castCfg, castDefaults)
	applyCastFont(castCfg, castDefaults)
	local nowMs = GetTime() * 1000
	local sampleDuration = 2
	state.castInfo = {
		name = L["Sample Cast"] or "Sample Cast",
		texture = 136243,
		startTime = nowMs,
		endTime = nowMs + sampleDuration * 1000,
		notInterruptible = false,
		isChannel = false,
		maxValue = sampleDuration,
	}
	configureCastStatic(castCfg, castDefaults)
	if not onUpdateActive then
		state.castBar:SetScript("OnUpdate", updateCastBar)
		onUpdateActive = true
	end
	updateCastBar()
end

local function shouldIgnoreCastFail(castGUID, spellId)
	if UnitChannelInfo then
		local channelName = UnitChannelInfo(UNIT)
		if channelName then return true end
	end
	local info = state.castInfo
	if not info then return false end
	if info.castGUID and castGUID then
		if not (issecretvalue and (issecretvalue(info.castGUID) or issecretvalue(castGUID))) and info.castGUID ~= castGUID then return true end
	end
	if info.spellId and spellId and info.castGUID then
		if not (issecretvalue and (issecretvalue(info.spellId) or issecretvalue(spellId))) and info.spellId ~= spellId then return true end
	end
	return false
end

local function showCastInterrupt(event)
	local castCfg, castDefaults = ensureCastConfig()
	local showInterruptFeedback = castCfg.showInterruptFeedback
	if showInterruptFeedback == nil then showInterruptFeedback = castDefaults.showInterruptFeedback ~= false end
	if showInterruptFeedback == false then
		stopCast()
		if shouldShowSampleCast() then setSampleCast() end
		return
	end

	clearCastInterruptState()
	state.castInterruptActive = true
	local token = state.castInterruptToken or 0
	if onUpdateActive then
		state.castBar:SetScript("OnUpdate", nil)
		onUpdateActive = false
	end

	applyCastLayout(castCfg, castDefaults)
	applyCastFont(castCfg, castDefaults)

	local texKey = castCfg.interruptTexture or castCfg.texture or castDefaults.interruptTexture or castDefaults.texture
	local interruptTex = UFHelper.resolveCastTexture(texKey)
	if interruptTex then state.castBar:SetStatusBarTexture(interruptTex) end
	if state.castBar.SetStatusBarDesaturated then state.castBar:SetStatusBarDesaturated(false) end
	if event == "UNIT_SPELLCAST_FAILED" then
		state.castBar:SetStatusBarColor(1, 1, 1, 1)
	else
		state.castBar:SetStatusBarColor(0.85, 0.12, 0.12, 1)
	end
	state.castBar:SetMinMaxValues(0, 1)
	state.castBar:SetValue(1)
	if state.castDuration then
		state.castDuration:SetText("")
		state.castDuration:Hide()
	end
	if state.castName then
		local label = (event == "UNIT_SPELLCAST_FAILED") and FAILED or INTERRUPTED
		state.castName:SetText(label)
		state.castName:SetShown(castCfg.showName ~= false)
	end
	if state.castIcon then
		local iconTexture = (state.castInfo and state.castInfo.texture) or state.castIconTexture
		local showIcon = castCfg.showIcon ~= false and iconTexture ~= nil
		state.castIcon:SetShown(showIcon)
		if showIcon then
			state.castIcon:SetTexture(iconTexture)
			state.castIconTexture = iconTexture
		end
	end
	UFHelper.hideCastSpark(state)

	local glowAlpha = 0.8
	if not state.castInterruptGlow then
		state.castInterruptGlow = state.castBar:CreateTexture(nil, "OVERLAY")
		if state.castInterruptGlow.SetAtlas then
			state.castInterruptGlow:SetAtlas("cast_interrupt_outerglow", true)
		else
			state.castInterruptGlow:SetTexture("Interface\\CastingBar\\UI-CastingBar-Border")
		end
		if state.castInterruptGlow.SetBlendMode then state.castInterruptGlow:SetBlendMode("ADD") end
		state.castInterruptGlow:SetPoint("CENTER", state.castBar, "CENTER", 0, 0)
		state.castInterruptGlow:SetAlpha(0)
	end
	do
		local w, h = state.castBar:GetSize()
		if state.castInterruptGlow.SetSize then state.castInterruptGlow:SetSize(w + (h * 0.5), h * 2.2) end
	end
	if not state.castInterruptGlowAnim then
		state.castInterruptGlowAnim = state.castInterruptGlow:CreateAnimationGroup()
		local fade = state.castInterruptGlowAnim:CreateAnimation("Alpha")
		fade:SetOrder(1)
		fade:SetDuration(0.35)
		fade:SetFromAlpha(glowAlpha)
		fade:SetToAlpha(0)
		state.castInterruptGlowAnim.fade = fade
		state.castInterruptGlowAnim:SetScript("OnFinished", function()
			if state.castInterruptGlow then state.castInterruptGlow:Hide() end
		end)
	elseif state.castInterruptGlowAnim.fade and state.castInterruptGlowAnim.fade.SetFromAlpha then
		state.castInterruptGlowAnim.fade:SetFromAlpha(glowAlpha)
	end
	state.castInterruptGlow:SetAlpha(glowAlpha)
	state.castInterruptGlow:Show()
	state.castInterruptGlowAnim:Stop()
	state.castInterruptGlowAnim:Play()

	if not state.castInterruptAnim then
		state.castInterruptAnim = state.castBar:CreateAnimationGroup()
		local hold = state.castInterruptAnim:CreateAnimation("Alpha")
		hold:SetOrder(1)
		hold:SetDuration(0.25)
		hold:SetFromAlpha(1)
		hold:SetToAlpha(1)
		state.castInterruptAnim.hold = hold
		local fade = state.castInterruptAnim:CreateAnimation("Alpha")
		fade:SetOrder(2)
		fade:SetDuration(0.25)
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0)
		state.castInterruptAnim.fade = fade
	end
	state.castBar:SetAlpha(1)
	state.castBar:Show()
	state.castInterruptAnim:Stop()
	state.castInterruptAnim:SetScript("OnFinished", function()
		if state.castInterruptToken ~= token then return end
		stopCast()
		if shouldShowSampleCast() then setSampleCast() end
	end)
	state.castInterruptAnim:Play()
end

local function setCastInfoFromUnit()
	local castCfg, castDefaults = ensureCastConfig()
	if not isCastbarEnabled() then
		stopCast()
		return
	end
	clearCastInterruptState()
	if castCfg.enabled == false then
		stopCast()
		return
	end

	local name, text, texture, startTimeMS, endTimeMS, _, notInterruptible, spellId, isEmpowered, numEmpowerStages = UnitChannelInfo(UNIT)
	local isChannel = true
	local castGUID
	if not name then
		name, text, texture, startTimeMS, endTimeMS, _, castGUID, notInterruptible, spellId = UnitCastingInfo(UNIT)
		isChannel = false
		isEmpowered = nil
		numEmpowerStages = nil
	end
	if not name then
		if shouldShowSampleCast() then
			setSampleCast()
		else
			stopCast()
		end
		return
	end

	applyCastLayout(castCfg, castDefaults)
	applyCastFont(castCfg, castDefaults)

	local isEmpoweredCast = isChannel and (issecretvalue and not issecretvalue(isEmpowered)) and isEmpowered and numEmpowerStages and numEmpowerStages > 0
	if isEmpoweredCast and startTimeMS and endTimeMS and (not issecretvalue or (not issecretvalue(startTimeMS) and not issecretvalue(endTimeMS))) then
		local totalMs = UFHelper.getEmpoweredChannelDurationMilliseconds and UFHelper.getEmpoweredChannelDurationMilliseconds(UNIT)
		if totalMs and totalMs > 0 and (not issecretvalue or not issecretvalue(totalMs)) then
			endTimeMS = startTimeMS + totalMs
		else
			local hold = UFHelper.getEmpowerHoldMilliseconds and UFHelper.getEmpowerHoldMilliseconds(UNIT)
			if hold and (not issecretvalue or not issecretvalue(hold)) then endTimeMS = endTimeMS + hold end
		end
	end

	if issecretvalue and ((startTimeMS and issecretvalue(startTimeMS)) or (endTimeMS and issecretvalue(endTimeMS))) then
		stopCast()
		return
	end
	local duration = (endTimeMS or 0) - (startTimeMS or 0)
	if not duration or duration <= 0 then
		stopCast()
		return
	end

	state.castInfo = {
		name = text or name,
		texture = texture,
		startTime = startTimeMS,
		endTime = endTimeMS,
		notInterruptible = notInterruptible,
		isChannel = isChannel,
		isEmpowered = isEmpowered,
		numEmpowerStages = numEmpowerStages,
		castGUID = castGUID,
		spellId = spellId,
	}
	configureCastStatic(castCfg, castDefaults)
	if isEmpowered then
		UFHelper.setupEmpowerStages(state, UNIT, numEmpowerStages)
	else
		UFHelper.clearEmpowerStages(state)
	end
	if not onUpdateActive then
		state.castBar:SetScript("OnUpdate", updateCastBar)
		onUpdateActive = true
	end
	updateCastBar()
end

function Castbar.Refresh()
	ensureCastConfig()
	ensureFrame()
	ensureEditModeCallbacks()
	ensureEditModeRegistration()
	tryRegisterEditModeSettings()
	local editMode = addon.EditMode
	if editMode and editMode.IsInEditMode and editMode:IsInEditMode() and editMode.RefreshFrame then editMode:RefreshFrame(EDITMODE_FRAME_ID) end
	if not isCastbarEnabled() then
		if shouldShowSampleCast() then
			setSampleCast()
			return
		end
		stopCast()
		return
	end
	setCastInfoFromUnit()
end

local eventFrame = Castbar._eventFrame
if not eventFrame then
	eventFrame = CreateFrame("Frame")
	Castbar._eventFrame = eventFrame
	eventFrame:RegisterEvent("PLAYER_LOGIN")
	eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
	eventFrame:RegisterEvent("UNIT_SPELLCAST_SENT")
	eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
	eventFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
	eventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
	eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
	eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
	eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
	eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
	eventFrame:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START")
	eventFrame:RegisterEvent("UNIT_SPELLCAST_EMPOWER_UPDATE")
	eventFrame:RegisterEvent("UNIT_SPELLCAST_DELAYED")
	eventFrame:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
end

eventFrame:SetScript("OnEvent", function(_, event, unit, ...)
	if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" or event == "EDIT_MODE_LAYOUTS_UPDATED" then
		Castbar.Refresh()
		return
	end

	if unit ~= UNIT then return end
	if not isCastbarEnabled() then return end

	if event == "UNIT_SPELLCAST_SENT" then
		state.castTarget = ...
	elseif
		event == "UNIT_SPELLCAST_START"
		or event == "UNIT_SPELLCAST_CHANNEL_START"
		or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
		or event == "UNIT_SPELLCAST_EMPOWER_START"
		or event == "UNIT_SPELLCAST_EMPOWER_UPDATE"
		or event == "UNIT_SPELLCAST_DELAYED"
	then
		setCastInfoFromUnit()
	elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
		local castGUID, spellId = ...
		if not shouldIgnoreCastFail(castGUID, spellId) then showCastInterrupt(event) end
	elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
		showCastInterrupt("UNIT_SPELLCAST_INTERRUPTED")
	elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if not state.castInterruptActive then
			stopCast()
			if shouldShowSampleCast() then setSampleCast() end
		end
	end
end)
