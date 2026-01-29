-- luacheck: globals RegisterStateDriver UnregisterStateDriver RegisterUnitWatch
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

--[[
	EQoL Group Unit Frames (Party/Raid) - SecureGroupHeaderTemplate scaffold

	Goal of this file:
	- Create secure party + raid headers
	- Provide a unit-button template hook (defined in UF_GroupFrames.xml)
	- Build a simple unit frame (health/power/name) on top of your existing UF style
	- Keep everything extendable (more widgets, auras, indicators, sorting, etc.)

	Notes about secure headers:
	- Changing header attributes (layout, filters, visibility) is forbidden in combat.
	- Frames are spawned by the header. You must use an XML template for the unit buttons.
	- Use RegisterStateDriver for visibility, and guard everything with InCombatLockdown().
--]]

addon.Aura = addon.Aura or {}
addon.Aura.UF = addon.Aura.UF or {}
local UF = addon.Aura.UF

UF.GroupFrames = UF.GroupFrames or {}
local GF = UF.GroupFrames

local UFHelper = addon.Aura.UFHelper
local AuraUtil = UF.AuraUtil
local EditMode = addon.EditMode
local SettingType = EditMode and EditMode.lib and EditMode.lib.SettingType

local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitName = UnitName
local UnitClass = UnitClass
local UnitIsConnected = UnitIsConnected
local UnitIsPlayer = UnitIsPlayer
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitGroupRolesAssignedEnum = UnitGroupRolesAssignedEnum
local GetSpecialization = GetSpecialization
local GetNumSpecializations = GetNumSpecializations
local GetSpecializationInfo = GetSpecializationInfo
local InCombatLockdown = InCombatLockdown
local RegisterStateDriver = RegisterStateDriver
local UnregisterStateDriver = UnregisterStateDriver
local issecretvalue = _G.issecretvalue
local C_UnitAuras = C_UnitAuras
local Enum = Enum

local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local PowerBarColor = PowerBarColor

-- ----------------------------------------------------------------------------
-- Small subset of UF.lua helpers (kept local here)
-- ----------------------------------------------------------------------------

local max = math.max
local floor = math.floor
local hooksecurefunc = hooksecurefunc

local function ensureBorderFrame(frame)
	if not frame then return nil end
	local border = frame._ufBorder
	if not border then
		border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		border:EnableMouse(false)
		frame._ufBorder = border
	end
	border:SetFrameStrata(frame:GetFrameStrata())
	local baseLevel = frame:GetFrameLevel() or 0
	border:SetFrameLevel(baseLevel + 3)
	border:ClearAllPoints()
	border:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	return border
end

local function setBackdrop(frame, borderCfg)
	if not frame then return end
	if borderCfg and borderCfg.enabled then
		if frame.SetBackdrop then frame:SetBackdrop(nil) end
		local borderFrame = ensureBorderFrame(frame)
		if not borderFrame then return end
		local color = borderCfg.color or { 0, 0, 0, 0.8 }
		local insetVal = borderCfg.inset
		if insetVal == nil then insetVal = borderCfg.edgeSize or 1 end
		local edgeFile = (UFHelper and UFHelper.resolveBorderTexture and UFHelper.resolveBorderTexture(borderCfg.texture)) or "Interface\\Buttons\\WHITE8x8"
		borderFrame:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = edgeFile,
			edgeSize = borderCfg.edgeSize or 1,
			insets = { left = insetVal, right = insetVal, top = insetVal, bottom = insetVal },
		})
		borderFrame:SetBackdropColor(0, 0, 0, 0)
		borderFrame:SetBackdropBorderColor(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
		borderFrame:Show()
	else
		if frame.SetBackdrop then frame:SetBackdrop(nil) end
		local borderFrame = frame._ufBorder
		if borderFrame then
			borderFrame:SetBackdrop(nil)
			borderFrame:Hide()
		end
	end
end

local function applyBarBackdrop(bar, cfg)
	if not bar or not bar.SetBackdrop then return end
	cfg = cfg or {}
	local bd = cfg.backdrop or {}
	if bd.enabled == false then
		bar:SetBackdrop(nil)
		return
	end
	local col = bd.color or { 0, 0, 0, 0.6 }
	bar:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = nil,
		tile = false,
	})
	bar:SetBackdropColor(col[1] or 0, col[2] or 0, col[3] or 0, col[4] or 0.6)
end

local function layoutTexts(bar, leftFS, centerFS, rightFS, cfg)
	if not bar then return end
	local leftCfg = (cfg and cfg.offsetLeft) or { x = 6, y = 0 }
	local centerCfg = (cfg and cfg.offsetCenter) or { x = 0, y = 0 }
	local rightCfg = (cfg and cfg.offsetRight) or { x = -6, y = 0 }
	if leftFS then
		leftFS:ClearAllPoints()
		leftFS:SetPoint("LEFT", bar, "LEFT", leftCfg.x or 0, leftCfg.y or 0)
		leftFS:SetJustifyH("LEFT")
	end
	if centerFS then
		centerFS:ClearAllPoints()
		centerFS:SetPoint("CENTER", bar, "CENTER", centerCfg.x or 0, centerCfg.y or 0)
		centerFS:SetJustifyH("CENTER")
	end
	if rightFS then
		rightFS:ClearAllPoints()
		rightFS:SetPoint("RIGHT", bar, "RIGHT", rightCfg.x or 0, rightCfg.y or 0)
		rightFS:SetJustifyH("RIGHT")
	end
end

local function setFrameLevelAbove(child, parent, offset)
	if not child or not parent then return end
	if child.SetFrameStrata and parent.GetFrameStrata then child:SetFrameStrata(parent:GetFrameStrata()) end
	if child.SetFrameLevel and parent.GetFrameLevel then child:SetFrameLevel((parent:GetFrameLevel() or 0) + (offset or 1)) end
end

local function syncTextFrameLevels(st)
	if not st then return end
	setFrameLevelAbove(st.healthTextLayer, st.health, 5)
	setFrameLevelAbove(st.powerTextLayer, st.power, 5)
end

local function hookTextFrameLevels(st)
	if not st or not hooksecurefunc then return end
	st._textLevelHooks = st._textLevelHooks or {}
	local function hookFrame(frame)
		if not frame or st._textLevelHooks[frame] then return end
		st._textLevelHooks[frame] = true
		if frame.SetFrameLevel then hooksecurefunc(frame, "SetFrameLevel", function() syncTextFrameLevels(st) end) end
		if frame.SetFrameStrata then hooksecurefunc(frame, "SetFrameStrata", function() syncTextFrameLevels(st) end) end
	end
	hookFrame(st.frame)
	hookFrame(st.barGroup)
	hookFrame(st.health)
	hookFrame(st.power)
	syncTextFrameLevels(st)
end

local function getClassColor(class)
	if not class then return nil end
	if addon.db and addon.db.ufUseCustomClassColors then
		local overrides = addon.db.ufClassColors
		local custom = overrides and overrides[class]
		if custom then
			if custom.r then return custom.r, custom.g, custom.b, custom.a or 1 end
			if custom[1] then return custom[1], custom[2], custom[3], custom[4] or 1 end
		end
	end
	local fallback = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
	if fallback then return fallback.r or fallback[1], fallback.g or fallback[2], fallback.b or fallback[3], fallback.a or fallback[4] or 1 end
	return nil
end

local function selectionHasAny(selection)
	if type(selection) ~= "table" then return false end
	for _, value in pairs(selection) do
		if value then return true end
	end
	return false
end

local function getUnitRoleKey(unit)
	local roleEnum
	if UnitGroupRolesAssignedEnum then
		roleEnum = UnitGroupRolesAssignedEnum(unit)
	end
	if roleEnum and Enum and Enum.LFGRole then
		if roleEnum == Enum.LFGRole.Tank then return "TANK" end
		if roleEnum == Enum.LFGRole.Healer then return "HEALER" end
		if roleEnum == Enum.LFGRole.Damage then return "DAMAGER" end
	end
	local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
	if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
	return "NONE"
end

local function shouldShowPowerForRole(pcfg, unit)
	if not pcfg then return true end
	local selection = pcfg.showRoles
	if type(selection) ~= "table" then return true end
	if not selectionHasAny(selection) then return false end
	local roleKey = getUnitRoleKey(unit)
	return selection[roleKey] == true
end

local function shouldShowPowerForSpec(pcfg)
	if not pcfg then return true end
	local selection = pcfg.showSpecs
	if type(selection) ~= "table" then return true end
	if not selectionHasAny(selection) then return false end
	local specIndex = GetSpecialization and GetSpecialization()
	if not specIndex then return true end
	local specId = GetSpecializationInfo and select(1, GetSpecializationInfo(specIndex))
	if not specId then return true end
	return selection[specId] == true
end

-- -----------------------------------------------------------------------------
-- Defaults / DB helpers
-- -----------------------------------------------------------------------------

local DEFAULTS = {
	party = {
		enabled = false,
		showPlayer = false,
		showSolo = false,
		width = 140,
		height = 30,
		powerHeight = 6,
		spacing = 4,
		point = "TOPLEFT",
		relativePoint = "TOPLEFT",
		relativeTo = "UIParent",
		x = 500,
		y = -300,
		growth = "DOWN", -- DOWN or RIGHT
		border = {
			enabled = true,
			texture = "DEFAULT",
			color = { 0, 0, 0, 0.8 },
			edgeSize = 1,
			inset = 0,
		},
		highlight = {
			enabled = false,
			mouseover = true,
			aggro = false,
			texture = "DEFAULT",
			size = 2,
			color = { 1, 0, 0, 1 },
		},
		health = {
			texture = "DEFAULT",
			font = nil,
			fontSize = 12,
			fontOutline = "OUTLINE",
			useClassColor = false,
			offsetLeft = { x = 6, y = 0 },
			offsetCenter = { x = 0, y = 0 },
			offsetRight = { x = -6, y = 0 },
			backdrop = { enabled = true, color = { 0, 0, 0, 0.6 } },
		},
		power = {
			texture = "DEFAULT",
			font = nil,
			fontSize = 10,
			fontOutline = "OUTLINE",
			offsetLeft = { x = 6, y = 0 },
			offsetCenter = { x = 0, y = 0 },
			offsetRight = { x = -6, y = 0 },
			backdrop = { enabled = true, color = { 0, 0, 0, 0.6 } },
		},
		text = {
			nameMaxChars = 18,
			showHealthPercent = true,
			showPowerPercent = false,
			useClassColor = true,
			font = nil,
			fontSize = 12,
			fontOutline = "OUTLINE",
			nameOffset = { x = 6, y = 0 },
		},
		roleIcon = {
			enabled = true,
			size = 14,
			point = "LEFT",
			relativePoint = "LEFT",
			x = 2,
			y = 0,
			spacing = 2,
		},
		auras = {
			enabled = false,
			buff = {
				enabled = false,
				size = 16,
				perRow = 6,
				max = 6,
				spacing = 2,
				anchorPoint = "TOPLEFT",
				x = 0,
				y = 4,
				showTooltip = true,
				showCooldown = true,
			},
			debuff = {
				enabled = false,
				size = 16,
				perRow = 6,
				max = 6,
				spacing = 2,
				anchorPoint = "BOTTOMLEFT",
				x = 0,
				y = -4,
				showTooltip = true,
				showCooldown = true,
			},
			externals = {
				enabled = false,
				size = 16,
				perRow = 6,
				max = 4,
				spacing = 2,
				anchorPoint = "TOPRIGHT",
				x = 0,
				y = 4,
				showTooltip = true,
				showCooldown = true,
			},
		},
	},
	raid = {
		enabled = false,
		width = 100,
		height = 24,
		powerHeight = 5,
		spacing = 3,
		point = "TOPLEFT",
		relativePoint = "TOPLEFT",
		relativeTo = "UIParent",
		x = 500,
		y = -300,
		groupBy = "GROUP",
		groupingOrder = "1,2,3,4,5,6,7,8",
		sortMethod = "INDEX",
		sortDir = "ASC",
		unitsPerColumn = 5,
		maxColumns = 8,
		growth = "RIGHT", -- RIGHT or DOWN
		columnSpacing = 8,
		border = {
			enabled = true,
			texture = "DEFAULT",
			color = { 0, 0, 0, 0.8 },
			edgeSize = 1,
			inset = 0,
		},
		highlight = {
			enabled = false,
			mouseover = true,
			aggro = false,
			texture = "DEFAULT",
			size = 2,
			color = { 1, 0, 0, 1 },
		},
		health = {
			texture = "DEFAULT",
			font = nil,
			fontSize = 11,
			fontOutline = "OUTLINE",
			useClassColor = false,
			offsetLeft = { x = 5, y = 0 },
			offsetCenter = { x = 0, y = 0 },
			offsetRight = { x = -5, y = 0 },
			backdrop = { enabled = true, color = { 0, 0, 0, 0.6 } },
		},
		power = {
			texture = "DEFAULT",
			font = nil,
			fontSize = 9,
			fontOutline = "OUTLINE",
			offsetLeft = { x = 5, y = 0 },
			offsetCenter = { x = 0, y = 0 },
			offsetRight = { x = -5, y = 0 },
			backdrop = { enabled = true, color = { 0, 0, 0, 0.6 } },
		},
		text = {
			nameMaxChars = 12,
			showHealthPercent = false,
			showPowerPercent = false,
			useClassColor = true,
			font = nil,
			fontSize = 10,
			fontOutline = "OUTLINE",
			nameOffset = { x = 5, y = 0 },
		},
		roleIcon = {
			enabled = true,
			size = 12,
			point = "LEFT",
			relativePoint = "LEFT",
			x = 2,
			y = 0,
			spacing = 2,
		},
		auras = {
			enabled = false,
			buff = {
				enabled = false,
				size = 14,
				perRow = 6,
				max = 6,
				spacing = 2,
				anchorPoint = "TOPLEFT",
				x = 0,
				y = 3,
				showTooltip = true,
				showCooldown = true,
			},
			debuff = {
				enabled = false,
				size = 14,
				perRow = 6,
				max = 6,
				spacing = 2,
				anchorPoint = "BOTTOMLEFT",
				x = 0,
				y = -3,
				showTooltip = true,
				showCooldown = true,
			},
			externals = {
				enabled = false,
				size = 14,
				perRow = 6,
				max = 4,
				spacing = 2,
				anchorPoint = "TOPRIGHT",
				x = 0,
				y = 3,
				showTooltip = true,
				showCooldown = true,
			},
		},
	},
}

local function ensureDB()
	addon.db = addon.db or {}
	addon.db.ufGroupFrames = addon.db.ufGroupFrames or {}
	local db = addon.db.ufGroupFrames
	for kind, def in pairs(DEFAULTS) do
		db[kind] = db[kind] or {}
		local t = db[kind]
		for k, v in pairs(def) do
			if t[k] == nil then
				if type(v) == "table" then
					if addon.functions and addon.functions.copyTable then
						t[k] = addon.functions.copyTable(v)
					else
						t[k] = CopyTable(v)
					end
				else
					t[k] = v
				end
			end
		end
	end
	return db
end

local function getCfg(kind)
	local db = ensureDB()
	return db[kind] or DEFAULTS[kind]
end

local function isFeatureEnabled()
	return addon.db and addon.db.ufEnableGroupFrames == true
end

-- Expose config for Settings / Edit Mode integration
function GF:GetConfig(kind)
	return getCfg(kind)
end

function GF:IsFeatureEnabled()
	return isFeatureEnabled()
end

function GF:EnsureDB()
	return ensureDB()
end


-- -----------------------------------------------------------------------------
-- Internal state
-- -----------------------------------------------------------------------------

GF.headers = GF.headers or {}
GF.anchors = GF.anchors or {}
GF._pendingRefresh = GF._pendingRefresh or false
GF._pendingDisable = GF._pendingDisable or false

local function getUnit(self)
	-- Secure headers set the "unit" attribute on the button.
	return (self and (self.unit or (self.GetAttribute and self:GetAttribute("unit"))))
end

local function getState(self)
	local st = self and self._eqolUFState
	if not st then
		st = { frame = self }
		self._eqolUFState = st
	end
	return st
end

-- -----------------------------------------------------------------------------
-- Unit button construction
-- -----------------------------------------------------------------------------
function GF:BuildButton(self)
	if not self then return end
	local st = getState(self)

	local kind = self._eqolGroupKind or "party"
	local cfg = getCfg(kind)
	local hc = cfg.health or {}
	local pcfg = cfg.power or {}
	local tc = cfg.text or {}

	-- Basic secure click setup (safe even if header also sets it).
	if self.RegisterForClicks then self:RegisterForClicks("AnyUp") end
	-- Setting protected attributes is combat-locked. The header's initialConfigFunction
	-- already sets these, so we only do it out of combat as a safety net.
	if (not InCombatLockdown or not InCombatLockdown()) and self.SetAttribute then
		self:SetAttribute("*type1", "target")
		self:SetAttribute("*type2", "togglemenu")
	end

	-- Clique compatibility (your UF.lua already does this too).
	_G.ClickCastFrames = _G.ClickCastFrames or {}
	_G.ClickCastFrames[self] = true

	-- Root visual group (mirrors your UF.lua structure)
	if not st.barGroup then
		st.barGroup = CreateFrame("Frame", nil, self, "BackdropTemplate")
		st.barGroup:EnableMouse(false)
	end
	st.barGroup:SetAllPoints(self)
	-- Border handling (same pattern as UF.lua: border lives on a dedicated child frame)
	setBackdrop(st.barGroup, cfg.border)

	-- Health bar
	if not st.health then
		st.health = CreateFrame("StatusBar", nil, st.barGroup, "BackdropTemplate")
		st.health:SetMinMaxValues(0, 1)
		st.health:SetValue(0)
		if st.health.SetStatusBarDesaturated then st.health:SetStatusBarDesaturated(true) end
	end
	if st.health.SetStatusBarTexture and UFHelper and UFHelper.resolveTexture then
		st.health:SetStatusBarTexture(UFHelper.resolveTexture(hc.texture))
		if UFHelper.configureSpecialTexture then UFHelper.configureSpecialTexture(st.health, "HEALTH", hc.texture, hc) end
	end
	applyBarBackdrop(st.health, hc)

	-- Power bar
	if not st.power then
		st.power = CreateFrame("StatusBar", nil, st.barGroup, "BackdropTemplate")
		st.power:SetMinMaxValues(0, 1)
		st.power:SetValue(0)
	end
	if st.power.SetStatusBarTexture and UFHelper and UFHelper.resolveTexture then
		st.power:SetStatusBarTexture(UFHelper.resolveTexture(pcfg.texture))
	end
	applyBarBackdrop(st.power, pcfg)
	if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated(false) end

	-- Text layers (kept as separate frames so we can force proper frame levels)
	if not st.healthTextLayer then
		st.healthTextLayer = CreateFrame("Frame", nil, st.health)
		st.healthTextLayer:SetAllPoints(st.health)
	end
	if not st.powerTextLayer then
		st.powerTextLayer = CreateFrame("Frame", nil, st.power)
		st.powerTextLayer:SetAllPoints(st.power)
	end

	-- Mirror your UF.lua text triplets (Left/Center/Right) so you can expand easily.
	if not st.healthTextLeft then st.healthTextLeft = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	if not st.healthTextCenter then st.healthTextCenter = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	if not st.healthTextRight then st.healthTextRight = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	if not st.powerTextLeft then st.powerTextLeft = st.powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	if not st.powerTextCenter then st.powerTextCenter = st.powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	if not st.powerTextRight then st.powerTextRight = st.powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end

	if not st.nameText then st.nameText = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	st.name = st.nameText

	-- Apply fonts (uses your existing UFHelper logic + default font media)
	if UFHelper and UFHelper.applyFont then
		UFHelper.applyFont(st.healthTextLeft, hc.font, hc.fontSize or 12, hc.fontOutline)
		UFHelper.applyFont(st.healthTextCenter, hc.font, hc.fontSize or 12, hc.fontOutline)
		UFHelper.applyFont(st.healthTextRight, hc.font, hc.fontSize or 12, hc.fontOutline)
		UFHelper.applyFont(st.powerTextLeft, pcfg.font, pcfg.fontSize or 10, pcfg.fontOutline)
		UFHelper.applyFont(st.powerTextCenter, pcfg.font, pcfg.fontSize or 10, pcfg.fontOutline)
		UFHelper.applyFont(st.powerTextRight, pcfg.font, pcfg.fontSize or 10, pcfg.fontOutline)
		UFHelper.applyFont(st.nameText, tc.font or hc.font, tc.fontSize or hc.fontSize or 12, tc.fontOutline or hc.fontOutline)
	end

	-- Highlight style (same system as your UF.lua)
	st._highlightCfg = (UFHelper and UFHelper.buildHighlightConfig) and UFHelper.buildHighlightConfig(cfg, DEFAULTS[kind]) or nil
	if UFHelper and UFHelper.applyHighlightStyle then UFHelper.applyHighlightStyle(st, st._highlightCfg) end

	-- Layout updates on resize
	if not st._sizeHooked then
		st._sizeHooked = true
		self:HookScript("OnSizeChanged", function(btn)
			GF:LayoutButton(btn)
		end)
	end

	self:SetClampedToScreen(true)
	self:SetScript("OnMouseDown", nil) -- keep clean; secure click handles targeting.

	-- Menu function used by the secure "togglemenu" click.
	if not st._menuHooked then
		st._menuHooked = true
		self.menu = function(btn)
			GF:OpenUnitMenu(btn)
		end
	end

	hookTextFrameLevels(st)
	GF:LayoutButton(self)
end

function GF:LayoutButton(self)
	if not self then return end
	local st = getState(self)
	if not (st and st.barGroup and st.health and st.power) then return end

	local kind = self._eqolGroupKind -- set by header helper
	local cfg = getCfg(kind or "party")
	local powerH = tonumber(cfg.powerHeight) or 5
	if st._powerHidden then powerH = 0 end
	local w, h = self:GetSize()
	if not w or not h then return end
	if powerH > h - 4 then powerH = math.max(3, h * 0.25) end

	st.barGroup:SetAllPoints(self)

	st.power:ClearAllPoints()
	st.power:SetPoint("BOTTOMLEFT", st.barGroup, "BOTTOMLEFT", 1, 1)
	st.power:SetPoint("BOTTOMRIGHT", st.barGroup, "BOTTOMRIGHT", -1, 1)
	st.power:SetHeight(powerH)

	st.health:ClearAllPoints()
	st.health:SetPoint("TOPLEFT", st.barGroup, "TOPLEFT", 1, -1)
	st.health:SetPoint("BOTTOMRIGHT", st.barGroup, "BOTTOMRIGHT", -1, powerH + 1)

	-- Text layout (mirrors UF.lua positioning logic)
	layoutTexts(st.health, st.healthTextLeft, st.healthTextCenter, st.healthTextRight, cfg.health)
	layoutTexts(st.power, st.powerTextLeft, st.powerTextCenter, st.powerTextRight, cfg.power)

	-- Name + role icon layout
	local tc = cfg.text or {}
	local rc = cfg.roleIcon or {}
	local rolePad = 0
	if rc.enabled ~= false then
		if not st.roleIcon then
			st.roleIcon = st.health:CreateTexture(nil, "OVERLAY")
		end
		local size = rc.size or 14
		local point = rc.point or "LEFT"
		local relPoint = rc.relativePoint or "LEFT"
		local ox = rc.x or 2
		local oy = rc.y or 0
		st.roleIcon:ClearAllPoints()
		st.roleIcon:SetPoint(point, st.health, relPoint, ox, oy)
		st.roleIcon:SetSize(size, size)
		rolePad = size + (rc.spacing or 2)
	else
		if st.roleIcon then st.roleIcon:Hide() end
	end

	if st.nameText then
		if UFHelper and UFHelper.applyFont then
			local hc = cfg.health or {}
			UFHelper.applyFont(st.nameText, tc.font or hc.font, tc.fontSize or hc.fontSize or 12, tc.fontOutline or hc.fontOutline)
		end
		local nameOffset = tc.nameOffset or {}
		local baseOffset = (cfg.health and cfg.health.offsetLeft) or {}
		local nameX = (nameOffset.x ~= nil and nameOffset.x or baseOffset.x or 6) + rolePad
		local nameY = nameOffset.y ~= nil and nameOffset.y or baseOffset.y or 0
		st.nameText:ClearAllPoints()
		st.nameText:SetPoint("LEFT", st.health, "LEFT", nameX, nameY)
		st.nameText:SetPoint("RIGHT", st.health, "RIGHT", -4, nameY)
		st.nameText:SetJustifyH("LEFT")
	end

	-- Keep text above bars
	local baseLevel = (st.barGroup:GetFrameLevel() or 0)
	st.health:SetFrameLevel(baseLevel + 1)
	st.power:SetFrameLevel(baseLevel + 1)
	syncTextFrameLevels(st)
end

-- -----------------------------------------------------------------------------
-- Updates
-- -----------------------------------------------------------------------------

local function resolveAuraGrowth(anchorPoint, growthX, growthY)
	local anchor = (anchorPoint or "TOPLEFT"):upper()
	if not growthX then
		if anchor:find("RIGHT", 1, true) then
			growthX = "LEFT"
		else
			growthX = "RIGHT"
		end
	end
	if not growthY then
		if anchor:find("BOTTOM", 1, true) then
			growthY = "UP"
		else
			growthY = "DOWN"
		end
	end
	return anchor, growthX, growthY
end

local function ensureAuraContainer(st, key)
	if not st then return nil end
	if not st[key] then
		st[key] = CreateFrame("Frame", nil, st.barGroup or st.frame)
		st[key]:EnableMouse(false)
	end
	return st[key]
end

local function hideAuraButtons(buttons, startIndex)
	if not buttons then return end
	for i = startIndex, #buttons do
		local btn = buttons[i]
		if btn then btn:Hide() end
	end
end

local function positionAuraButton(btn, container, anchorPoint, index, perRow, size, spacing, growthX, growthY)
	if not (btn and container) then return end
	perRow = perRow or 1
	if perRow < 1 then perRow = 1 end
	local col = (index - 1) % perRow
	local row = math.floor((index - 1) / perRow)
	local xSign = (growthX == "LEFT") and -1 or 1
	local ySign = (growthY == "UP") and 1 or -1
	local stepX = (size + spacing) * xSign
	local stepY = (size + spacing) * ySign
	btn:ClearAllPoints()
	btn:SetPoint(anchorPoint, container, anchorPoint, col * stepX, row * stepY)
end

function GF:UpdateRoleIcon(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st) then return end
	local cfg = getCfg(self._eqolGroupKind or "party")
	local rc = cfg and cfg.roleIcon or {}
	if rc.enabled == false then
		if st.roleIcon then st.roleIcon:Hide() end
		return
	end
	if not st.roleIcon then
		st.roleIcon = (st.health or st.barGroup or st.frame):CreateTexture(nil, "OVERLAY")
	end
	local roleEnum
	if UnitGroupRolesAssignedEnum then
		roleEnum = UnitGroupRolesAssignedEnum(unit)
	end
	local atlas
	if roleEnum and Enum and Enum.LFGRole then
		if roleEnum == Enum.LFGRole.Tank then
			atlas = "roleicon-tiny-tank"
		elseif roleEnum == Enum.LFGRole.Healer then
			atlas = "roleicon-tiny-healer"
		elseif roleEnum == Enum.LFGRole.Damage then
			atlas = "roleicon-tiny-dps"
		end
	else
		local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
		if role == "TANK" then
			atlas = "roleicon-tiny-tank"
		elseif role == "HEALER" then
			atlas = "roleicon-tiny-healer"
		elseif role == "DAMAGER" then
			atlas = "roleicon-tiny-dps"
		end
	end
	if atlas then
		if st._lastRoleAtlas ~= atlas then
			st._lastRoleAtlas = atlas
			st.roleIcon:SetAtlas(atlas, true)
		end
		st.roleIcon:Show()
	else
		st._lastRoleAtlas = nil
		st.roleIcon:Hide()
	end
end

function GF:UpdateAuras(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st and C_UnitAuras and AuraUtil) then return end
	local cfg = getCfg(self._eqolGroupKind or "party")
	local ac = cfg and cfg.auras or {}
	if ac.enabled == false then
		if st.buffContainer then st.buffContainer:Hide() end
		if st.debuffContainer then st.debuffContainer:Hide() end
		if st.externalContainer then st.externalContainer:Hide() end
		hideAuraButtons(st.buffButtons, 1)
		hideAuraButtons(st.debuffButtons, 1)
		hideAuraButtons(st.externalButtons, 1)
		return
	end

	local parent = st.barGroup or st.frame

	local function updateAuraType(kindKey, isDebuff, predicate)
		local typeCfg = ac and ac[kindKey] or {}
		if typeCfg.enabled == false then
			if kindKey == "buff" then
				if st.buffContainer then st.buffContainer:Hide() end
				hideAuraButtons(st.buffButtons, 1)
			elseif kindKey == "debuff" then
				if st.debuffContainer then st.debuffContainer:Hide() end
				hideAuraButtons(st.debuffButtons, 1)
			else
				if st.externalContainer then st.externalContainer:Hide() end
				hideAuraButtons(st.externalButtons, 1)
			end
			return
		end

		local anchorPoint, growthX, growthY = resolveAuraGrowth(typeCfg.anchorPoint, typeCfg.growthX, typeCfg.growthY)
		local size = tonumber(typeCfg.size) or 16
		local spacing = tonumber(typeCfg.spacing) or 2
		local perRow = tonumber(typeCfg.perRow) or tonumber(typeCfg.max) or 6
		if perRow < 1 then perRow = 1 end
		local maxCount = tonumber(typeCfg.max) or perRow
		if maxCount < 0 then maxCount = 0 end

		local containerKey = "buffContainer"
		local buttonsKey = "buffButtons"
		if kindKey == "debuff" then
			containerKey = "debuffContainer"
			buttonsKey = "debuffButtons"
		elseif kindKey == "externals" then
			containerKey = "externalContainer"
			buttonsKey = "externalButtons"
		end
		local container = ensureAuraContainer(st, containerKey)
		if not container then return end
		container:ClearAllPoints()
		container:SetPoint(anchorPoint, parent, anchorPoint, typeCfg.x or 0, typeCfg.y or 0)
		container:Show()

		local buttons = st[buttonsKey]
		if not buttons then
			buttons = {}
			st[buttonsKey] = buttons
		end

		local filter = isDebuff and "HARMFUL" or "HELPFUL"
		local shown = 0
		local auraStyle = {
			size = size,
			padding = spacing,
			showTooltip = typeCfg.showTooltip ~= false,
			showCooldown = typeCfg.showCooldown ~= false,
			countFont = typeCfg.countFont,
			countFontSize = typeCfg.countFontSize,
			countFontOutline = typeCfg.countFontOutline,
			cooldownFontSize = typeCfg.cooldownFontSize,
		}

		local scanIndex = 1
		while shown < maxCount do
			local aura = C_UnitAuras.GetAuraDataByIndex(unit, scanIndex, filter)
			if not aura then break end
			scanIndex = scanIndex + 1
			if predicate and not predicate(aura) then
				-- skip non-matching aura
			else
				shown = shown + 1
				local btn = AuraUtil.ensureAuraButton(container, buttons, shown, auraStyle)
				btn:SetSize(size, size)
				AuraUtil.applyAuraToButton(btn, aura, auraStyle, isDebuff, unit)
				positionAuraButton(btn, container, anchorPoint, shown, perRow, size, spacing, growthX, growthY)
				btn:Show()
			end
		end

		hideAuraButtons(buttons, shown + 1)
	end

	updateAuraType("buff", false)
	updateAuraType("debuff", true)
	updateAuraType("externals", false, function(aura)
		return aura and aura.sourceUnit and aura.sourceUnit ~= unit
	end)
end

function GF:UpdateName(self)
	local unit = getUnit(self)
	local st = getState(self)
	local fs = st and (st.nameText or st.name)
	if not (unit and st and fs) then return end
	if UnitExists and not UnitExists(unit) then
		fs:SetText("")
		return
	end
	local name = UnitName and UnitName(unit) or ""
	local cfg = getCfg(self._eqolGroupKind or "party")
	local tc = cfg and cfg.text or {}
	local maxChars = cfg and cfg.text and cfg.text.nameMaxChars
	maxChars = tonumber(maxChars)
	if maxChars and maxChars > 0 and name and #name > maxChars then
		name = name:sub(1, maxChars)
	end
	if UnitIsConnected and not UnitIsConnected(unit) then
		name = (name and name ~= "") and (name .. " |cffff6666DC|r") or "|cffff6666DC|r"
	end
	name = name or ""
	if st._lastName ~= name then
		fs:SetText(name)
		st._lastName = name
	end

	-- Name coloring (simple: class color for players, grey if offline)
	local r, g, b, a = 1, 1, 1, 1
	if tc.useClassColor ~= false and UnitIsPlayer and UnitIsPlayer(unit) and UnitClass then
		local _, class = UnitClass(unit)
		local cr, cg, cb, ca = getClassColor(class)
		if cr then r, g, b, a = cr, cg, cb, ca or 1 end
	end
	if UnitIsConnected and not UnitIsConnected(unit) then
		r, g, b, a = 0.7, 0.7, 0.7, 1
	end
	local colorKey = tostring(r) .. "|" .. tostring(g) .. "|" .. tostring(b) .. "|" .. tostring(a)
	if st._lastNameColor ~= colorKey then
		st._lastNameColor = colorKey
		if fs.SetTextColor then fs:SetTextColor(r, g, b, a) end
	end
end

function GF:UpdateHealth(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st and st.health) then return end
	if UnitExists and not UnitExists(unit) then
		st.health:SetMinMaxValues(0, 1)
		st.health:SetValue(0)
		return
	end
	local cur = UnitHealth and UnitHealth(unit)
	if cur == nil then cur = 0 end
	local maxv = UnitHealthMax and UnitHealthMax(unit)
	if maxv == nil then maxv = 1 end
	local maxForValue = 1
	if issecretvalue and issecretvalue(maxv) then
		maxForValue = maxv
	elseif maxv and maxv > 0 then
		maxForValue = maxv
	end
	local secretHealth = issecretvalue and (issecretvalue(cur) or issecretvalue(maxv))
	if secretHealth then
		st.health:SetMinMaxValues(0, maxForValue)
		st.health:SetValue(cur or 0)
	else
		if st._lastHealthMax ~= maxForValue then
			st.health:SetMinMaxValues(0, maxForValue)
			st._lastHealthMax = maxForValue
		end
		if st._lastHealthCur ~= cur then
			st.health:SetValue(cur)
			st._lastHealthCur = cur
		end
	end

	-- Simple coloring: class color for players, green fallback.
	local r, g, b = 0.2, 1, 0.2
	local cfg = getCfg(self._eqolGroupKind or "party")
	local hc = cfg and cfg.health or {}
	if hc.useClassColor == true and UnitIsPlayer and UnitIsPlayer(unit) and UnitClass then
		local _, class = UnitClass(unit)
		local cr, cg, cb = getClassColor(class)
		if cr then r, g, b = cr, cg, cb end
	end
	if UnitIsConnected and not UnitIsConnected(unit) then
		r, g, b = 0.5, 0.5, 0.5
	end
	local colorKey = tostring(r) .. "|" .. tostring(g) .. "|" .. tostring(b)
	if st._lastHealthColor ~= colorKey then
		st._lastHealthColor = colorKey
		st.health:SetStatusBarColor(r, g, b, 1)
	end

	-- Optional: health percent on the right (kept simple but matches your text slots)
	local showPct = cfg and cfg.text and cfg.text.showHealthPercent
	if st.healthTextRight then
		local canShowPct = false
		if showPct then
			if not issecretvalue or (not issecretvalue(cur) and not issecretvalue(maxv)) then
				if maxv and maxv > 0 then
					canShowPct = true
				end
			end
		end
		if canShowPct then
			local pct = floor((cur / maxv) * 100 + 0.5)
			local pctText = pct .. "%"
			if st._lastHealthPct ~= pctText then
				st._lastHealthPct = pctText
				st.healthTextRight:SetText(pctText)
			end
		else
			if st._lastHealthPct ~= "" then
				st._lastHealthPct = ""
				st.healthTextRight:SetText("")
			end
		end
	end
end

function GF:UpdatePower(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st and st.power) then return end
	if UnitExists and not UnitExists(unit) then
		st.power:SetMinMaxValues(0, 1)
		st.power:SetValue(0)
		return
	end
	local kind = self._eqolGroupKind or "party"
	local cfg = getCfg(kind)
	local pcfg = cfg and cfg.power or {}
	local showPower = shouldShowPowerForRole(pcfg, unit) and shouldShowPowerForSpec(pcfg)
	if not showPower then
		if st.powerTextLeft then st.powerTextLeft:SetText("") end
		if st.powerTextCenter then st.powerTextCenter:SetText("") end
		if st.powerTextRight then st.powerTextRight:SetText("") end
		if st.power:IsShown() then st.power:Hide() end
		if not st._powerHidden then
			st._powerHidden = true
			GF:LayoutButton(self)
		end
		return
	end
	if st._powerHidden then
		st._powerHidden = nil
		GF:LayoutButton(self)
	end
	if not st.power:IsShown() then st.power:Show() end

	local powerType, powerToken = UnitPowerType and UnitPowerType(unit)
	local cur = UnitPower and UnitPower(unit, powerType)
	if cur == nil then cur = 0 end
	local maxv = UnitPowerMax and UnitPowerMax(unit, powerType)
	if maxv == nil then maxv = 1 end
	local maxForValue = 1
	if issecretvalue and issecretvalue(maxv) then
		maxForValue = maxv
	elseif maxv and maxv > 0 then
		maxForValue = maxv
	end
	local secretPower = issecretvalue and (issecretvalue(cur) or issecretvalue(maxv))
	if secretPower then
		st.power:SetMinMaxValues(0, maxForValue)
		st.power:SetValue(cur or 0)
	else
		if st._lastPowerMax ~= maxForValue then
			st.power:SetMinMaxValues(0, maxForValue)
			st._lastPowerMax = maxForValue
		end
		if st._lastPowerCur ~= cur then
			st.power:SetValue(cur)
			st._lastPowerCur = cur
		end
	end

	local powerKey = powerToken or powerType or "MANA"
	-- Apply special atlas textures for default texture keys (mirrors UF.lua behavior)
	if UFHelper and UFHelper.configureSpecialTexture then
		if st._lastPowerToken ~= powerKey or st._lastPowerTexture ~= pcfg.texture then
			UFHelper.configureSpecialTexture(st.power, powerKey, pcfg.texture, pcfg)
			st._lastPowerToken = powerKey
			st._lastPowerTexture = pcfg.texture
		end
	end
	if st.power.SetStatusBarDesaturated and UFHelper and UFHelper.isPowerDesaturated then
		local desat = UFHelper.isPowerDesaturated(powerKey)
		if st._lastPowerDesat ~= desat then
			st._lastPowerDesat = desat
			st.power:SetStatusBarDesaturated(desat)
		end
	end
	local pr, pg, pb, pa
	if UFHelper and UFHelper.getPowerColor then
		pr, pg, pb, pa = UFHelper.getPowerColor(powerKey)
	else
		local c = PowerBarColor and (PowerBarColor[powerKey] or PowerBarColor[powerType] or PowerBarColor["MANA"])
		if c then
			pr, pg, pb, pa = c.r or c[1] or 0, c.g or c[2] or 0, c.b or c[3] or 1, c.a or c[4] or 1
		end
	end
	if not pr then pr, pg, pb, pa = 0, 0.5, 1, 1 end
	local colorKey = tostring(pr) .. "|" .. tostring(pg) .. "|" .. tostring(pb) .. "|" .. tostring(pa)
	if st._lastPowerColor ~= colorKey then
		st._lastPowerColor = colorKey
		st.power:SetStatusBarColor(pr, pg, pb, pa or 1)
	end

	-- Optional: power percent on the right
	local showPct = cfg and cfg.text and cfg.text.showPowerPercent
	if st.powerTextRight then
		local canShowPct = false
		if showPct then
			if not issecretvalue or (not issecretvalue(cur) and not issecretvalue(maxv)) then
				if maxv and maxv > 0 then
					canShowPct = true
				end
			end
		end
		if canShowPct then
			local pct = floor((cur / maxv) * 100 + 0.5)
			local pctText = pct .. "%"
			if st._lastPowerPct ~= pctText then
				st._lastPowerPct = pctText
				st.powerTextRight:SetText(pctText)
			end
		else
			if st._lastPowerPct ~= "" then
				st._lastPowerPct = ""
				st.powerTextRight:SetText("")
			end
		end
	end
end

function GF:UpdateAll(self)
	GF:UpdateName(self)
	GF:UpdateHealth(self)
	GF:UpdatePower(self)
	GF:UpdateRoleIcon(self)
	GF:UpdateAuras(self)
end

-- -----------------------------------------------------------------------------
-- Unit menu (right click)
-- -----------------------------------------------------------------------------

GF._dropdown = GF._dropdown or nil

local function ensureDropDown()
	if GF._dropdown and GF._dropdown.GetName then return GF._dropdown end
	GF._dropdown = CreateFrame("Frame", "EQOLUFGroupDropDown", UIParent, "UIDropDownMenuTemplate")
	return GF._dropdown
end

local function resolveMenuType(unit)
	-- Best-effort: Blizzard has multiple menu variants. These are the most common keys.
	if unit == "player" then return "SELF" end
	if UnitIsUnit and UnitIsUnit(unit, "player") then return "SELF" end
	if UnitInRaid and UnitInRaid(unit) then return "RAID_PLAYER" end
	if UnitInParty and UnitInParty(unit) then return "PARTY" end
	return "RAID_PLAYER"
end

function GF:OpenUnitMenu(self)
	local unit = getUnit(self)
	if not unit then return end

	-- Dragonflight+ has UnitPopup_OpenMenu, but it is not 100% consistent across versions.
	-- We fall back to UnitPopup_ShowMenu + a shared dropdown.
	if UnitPopup_OpenMenu then
		-- Try the modern API signature first.
		pcall(function()
			UnitPopup_OpenMenu(resolveMenuType(unit), { unit = unit })
		end)
		return
	end

	if UnitPopup_ShowMenu then
		local dd = ensureDropDown()
		local which = resolveMenuType(unit)
		local name = (UnitName and UnitName(unit))
		UnitPopup_ShowMenu(dd, which, unit, name)
	end
end

-- -----------------------------------------------------------------------------
-- XML template script handlers
-- -----------------------------------------------------------------------------

function GF.UnitButton_OnLoad(self)
	-- Detect whether this button belongs to the party or raid header.
	-- (The secure header is the parent; we tag headers with _eqolKind.)
	local parent = self and self.GetParent and self:GetParent()
	if parent and parent._eqolKind then
		self._eqolGroupKind = parent._eqolKind
	end

	GF:BuildButton(self)

	-- The unit attribute may already exist when the button is created.
	local unit = getUnit(self)
	if unit then
		GF:UnitButton_SetUnit(self, unit)
	else
		-- Keep it blank until we get a unit.
		GF:UpdateAll(self)
	end
end

function GF:UnitButton_SetUnit(self, unit)
	if not self then return end
	self.unit = unit

	-- Re-register unit events for the new unit.
	if self.UnregisterAllEvents then
		self:UnregisterAllEvents()
	end

	-- Important: some events should *not* be unit-filtered, but for the scaffold
	-- we keep it simple and just register a few relevant unit events.
	self:RegisterUnitEvent("UNIT_HEALTH", unit)
	self:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
	self:RegisterUnitEvent("UNIT_POWER_UPDATE", unit)
	self:RegisterUnitEvent("UNIT_MAXPOWER", unit)
	self:RegisterUnitEvent("UNIT_DISPLAYPOWER", unit)
	self:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
	self:RegisterUnitEvent("UNIT_CONNECTION", unit)
	self:RegisterUnitEvent("UNIT_AURA", unit)

	GF:UpdateAll(self)
end

function GF.UnitButton_OnAttributeChanged(self, name, value)
	if name ~= "unit" then return end
	if value == nil or value == "" then
		-- Unit cleared
		self.unit = nil
		GF:UpdateAll(self)
		return
	end
	GF:UnitButton_SetUnit(self, value)
end

function GF.UnitButton_OnEvent(self, event, arg1)
	if not isFeatureEnabled() then return end
	-- If we're using the non-RegisterUnitEvent fallback, filter by unit.
	local unit = getUnit(self)
	if arg1 and unit and arg1 ~= unit then return end

	if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
		GF:UpdateHealth(self)
	elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
		GF:UpdatePower(self)
	elseif event == "UNIT_NAME_UPDATE" then
		GF:UpdateName(self)
	elseif event == "UNIT_CONNECTION" then
		GF:UpdateAll(self)
	elseif event == "UNIT_AURA" then
		GF:UpdateAuras(self)
	end
end

function GF.UnitButton_OnEnter(self)
	local unit = getUnit(self)
	if not unit then return end
	local st = getState(self)
	if st then
		st._hovered = true
		if UFHelper and UFHelper.updateHighlight then UFHelper.updateHighlight(st, unit, "player") end
	end
	if not GameTooltip or GameTooltip:IsForbidden() then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetUnit(unit)
	GameTooltip:Show()
end

function GF.UnitButton_OnLeave(self)
	local unit = getUnit(self)
	local st = getState(self)
	if st then
		st._hovered = false
		if UFHelper and UFHelper.updateHighlight and unit then UFHelper.updateHighlight(st, unit, "player") end
	end
	if GameTooltip and not GameTooltip:IsForbidden() then GameTooltip:Hide() end
end

-- -----------------------------------------------------------------------------
-- Header creation / layout
-- -----------------------------------------------------------------------------

local function setPointFromCfg(frame, cfg)
	if not frame or not cfg then return end
	frame:ClearAllPoints()
	local rel = cfg.relativeTo and _G[cfg.relativeTo] or UIParent
	local p = cfg.point or "CENTER"
	local rp = cfg.relativePoint or p
	frame:SetPoint(p, rel, rp, tonumber(cfg.x) or 0, tonumber(cfg.y) or 0)
end

-- -----------------------------------------------------------------------------
-- Anchor frames (Edit Mode)
-- -----------------------------------------------------------------------------
local function ensureAnchor(kind, parent)
	if not kind then return nil end
	GF.anchors = GF.anchors or {}
	local anchor = GF.anchors[kind]
	if anchor then return anchor end

	local name
	if kind == "party" then
		name = "EQOLUFPartyAnchor"
	elseif kind == "raid" then
		name = "EQOLUFRaidAnchor"
	end
	if not name then return nil end

	anchor = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
	anchor._eqolKind = kind
	anchor:EnableMouse(false)
	anchor:SetFrameStrata("MEDIUM")
	anchor:SetFrameLevel(1)

	-- A tiny backdrop so you can see the area while positioning in edit mode.
	-- The selection overlay will still be the primary indicator.
	if anchor.SetBackdrop then
		anchor:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
			insets = { left = 0, right = 0, top = 0, bottom = 0 },
		})
		anchor:SetBackdropColor(0, 0, 0, 0.08)
		anchor:SetBackdropBorderColor(0, 0, 0, 0.6)
	end

	anchor:Hide()
	GF.anchors[kind] = anchor
	return anchor
end

function GF:UpdateAnchorSize(kind)
	local cfg = getCfg(kind)
	local anchor = GF.anchors and GF.anchors[kind]
	if not (cfg and anchor) then return end

	local w = floor((tonumber(cfg.width) or 100) + 0.5)
	local h = floor((tonumber(cfg.height) or 24) + 0.5)
	local spacing = tonumber(cfg.spacing) or 0
	local columnSpacing = tonumber(cfg.columnSpacing) or spacing
	local growth = (cfg.growth or "DOWN"):upper()

	local unitsPer = 5
	local columns = 1
	if kind == "raid" then
		unitsPer = max(1, floor((tonumber(cfg.unitsPerColumn) or 5) + 0.5))
		columns = max(1, floor((tonumber(cfg.maxColumns) or 8) + 0.5))
	elseif kind == "party" and growth == "RIGHT" then
		unitsPer = 1
		columns = 5
	end

	local totalW, totalH
	if growth == "RIGHT" then
		totalW = w * unitsPer + spacing * max(0, unitsPer - 1)
		totalH = h * columns + columnSpacing * max(0, columns - 1)
	else
		totalW = w * columns + columnSpacing * max(0, columns - 1)
		totalH = h * unitsPer + spacing * max(0, unitsPer - 1)
	end

	if totalW < w then totalW = w end
	if totalH < h then totalH = h end

	anchor:SetSize(totalW, totalH)
end

local function applyVisibility(header, kind, cfg)
	if not header or not cfg or not RegisterStateDriver then return end
	if InCombatLockdown and InCombatLockdown() then return end

	if UnregisterStateDriver then
		UnregisterStateDriver(header, "visibility")
	end

	local cond = "hide"
	if header._eqolForceShow then
		cond = "show"
	elseif cfg.enabled then
		if kind == "party" then
			if cfg.showSolo then
				cond = "[group:raid] hide; show"
			else
				cond = "[group:raid] hide; [group:party] show; hide"
			end
		elseif kind == "raid" then
			cond = "[group:raid] show; hide"
		end
	end

	RegisterStateDriver(header, "visibility", cond)
	header._eqolVisibilityCond = cond
end

local function forEachChild(header, fn)
	if not header or not fn then return end
	local children = { header:GetChildren() }
	for _, child in ipairs(children) do
		fn(child)
	end
end

function GF:RefreshRoleIcons()
	if not isFeatureEnabled() then return end
	for _, header in pairs(GF.headers or {}) do
		forEachChild(header, function(child)
			if child then GF:UpdateRoleIcon(child) end
		end)
	end
end

function GF:RefreshPowerVisibility()
	if not isFeatureEnabled() then return end
	for _, header in pairs(GF.headers or {}) do
		forEachChild(header, function(child)
			if child then GF:UpdatePower(child) end
		end)
	end
end

function GF:ApplyHeaderAttributes(kind)
	local cfg = getCfg(kind)
	local header = GF.headers[kind]
	if not header then return end
	if not isFeatureEnabled() then return end
	if InCombatLockdown and InCombatLockdown() then
		GF._pendingRefresh = true
		return
	end

	local spacing = tonumber(cfg.spacing) or 0
	local growth = (cfg.growth or "DOWN"):upper()

	-- Core header settings
	if kind == "party" then
		header:SetAttribute("showParty", true)
		header:SetAttribute("showRaid", false)
		header:SetAttribute("showPlayer", cfg.showPlayer and true or false)
		header:SetAttribute("showSolo", cfg.showSolo and true or false)
		header:SetAttribute("sortMethod", "INDEX")
		header:SetAttribute("sortDir", "ASC")
		if growth == "RIGHT" then
			header:SetAttribute("maxColumns", 5)
			header:SetAttribute("unitsPerColumn", 1)
		else
			header:SetAttribute("maxColumns", 1)
			header:SetAttribute("unitsPerColumn", 5)
		end
	elseif kind == "raid" then
		header:SetAttribute("showParty", false)
		header:SetAttribute("showRaid", true)
		header:SetAttribute("showPlayer", true) -- most raid layouts include player
		header:SetAttribute("showSolo", false)
		header:SetAttribute("groupBy", cfg.groupBy or "GROUP")
		header:SetAttribute("groupingOrder", cfg.groupingOrder or "1,2,3,4,5,6,7,8")
		header:SetAttribute("sortMethod", cfg.sortMethod or "INDEX")
		header:SetAttribute("sortDir", cfg.sortDir or "ASC")
		header:SetAttribute("unitsPerColumn", tonumber(cfg.unitsPerColumn) or 5)
		header:SetAttribute("maxColumns", tonumber(cfg.maxColumns) or 8)
	end


	-- Edit mode preview override: keep the header visible for positioning.
	if header._eqolForceShow then
		header:SetAttribute("showParty", true)
		header:SetAttribute("showRaid", true)
		header:SetAttribute("showPlayer", true)
		header:SetAttribute("showSolo", true)
	end


	-- Growth / spacing
	if growth == "RIGHT" then
		if kind == "party" then
			header:SetAttribute("point", "TOP")
			header:SetAttribute("xOffset", 0)
			header:SetAttribute("yOffset", 0)
			header:SetAttribute("columnSpacing", spacing)
			header:SetAttribute("columnAnchorPoint", "LEFT")
		else
			header:SetAttribute("point", "LEFT")
			header:SetAttribute("xOffset", spacing)
			header:SetAttribute("yOffset", 0)
			header:SetAttribute("columnSpacing", tonumber(cfg.columnSpacing) or spacing)
			header:SetAttribute("columnAnchorPoint", "TOP")
		end
	else
		header:SetAttribute("point", "TOP")
		header:SetAttribute("xOffset", 0)
		header:SetAttribute("yOffset", -spacing)
		header:SetAttribute("columnSpacing", tonumber(cfg.columnSpacing) or spacing)
		header:SetAttribute("columnAnchorPoint", "LEFT")
	end

	-- Child template + secure per-button init
	-- NOTE: initialConfigFunction runs only when a button is created.
	-- If you change size later, also resize existing children (below).
	header:SetAttribute("template", "EQOLUFGroupUnitButtonTemplate")
	local w = tonumber(cfg.width) or 100
	local h = tonumber(cfg.height) or 24
	w = floor(w + 0.5)
	h = floor(h + 0.5)
	header:SetAttribute("initialConfigFunction", string.format([[
		self:SetWidth(%d)
		self:SetHeight(%d)
		self:SetAttribute('*type1','target')
		self:SetAttribute('*type2','togglemenu')
		RegisterUnitWatch(self)
	]], w, h))

	-- Also apply size to existing children.
	forEachChild(header, function(child)
		child._eqolGroupKind = kind
		child:SetSize(w, h)
		if child._eqolUFState then
			GF:LayoutButton(child)
			GF:UpdateAll(child)
		end
	end)

	local anchor = GF.anchors and GF.anchors[kind]
	if anchor then
		setPointFromCfg(anchor, cfg)
		GF:UpdateAnchorSize(kind)
		header:ClearAllPoints()
		local p = cfg.point or "CENTER"
		header:SetPoint(p, anchor, p, 0, 0)
	else
		setPointFromCfg(header, cfg)
	end
	applyVisibility(header, kind, cfg)
end

function GF:EnsureHeaders()
	if not isFeatureEnabled() then return end
	if GF.headers.party and GF.headers.raid and GF.anchors.party and GF.anchors.raid then return end

	-- Parent to PetBattleFrameHider so frames disappear in pet battles
	local parent = _G.PetBattleFrameHider or UIParent

	-- Movers (for Edit Mode positioning)
	if not GF.anchors.party then
		ensureAnchor("party", parent)
	end
	if not GF.anchors.raid then
		ensureAnchor("raid", parent)
	end

	if not GF.headers.party then
		GF.headers.party = CreateFrame("Frame", "EQOLUFPartyHeader", parent, "SecureGroupHeaderTemplate")
		GF.headers.party._eqolKind = "party"
		GF.headers.party:Hide()
	end

	if not GF.headers.raid then
		GF.headers.raid = CreateFrame("Frame", "EQOLUFRaidHeader", parent, "SecureGroupHeaderTemplate")
		GF.headers.raid._eqolKind = "raid"
		GF.headers.raid:Hide()
	end

	-- Anchor headers to their movers (so we can drag the mover in edit mode)
	for kind, header in pairs(GF.headers) do
		local a = GF.anchors and GF.anchors[kind]
		if header and a then
			header:ClearAllPoints()
			local cfg = getCfg(kind)
			local p = cfg and (cfg.point or "CENTER") or "CENTER"
			header:SetPoint(p, a, p, 0, 0)
		end
	end

	-- Apply layout once
	GF:ApplyHeaderAttributes("party")
	GF:ApplyHeaderAttributes("raid")
end

-- -----------------------------------------------------------------------------
-- Public API (call these from Settings later)
-- -----------------------------------------------------------------------------

function GF:EnableFeature()
	addon.db = addon.db or {}
	addon.db.ufEnableGroupFrames = true
	GF:EnsureHeaders()
	GF.Refresh()
	GF:EnsureEditMode()
end

function GF:DisableFeature()
	addon.db = addon.db or {}
	addon.db.ufEnableGroupFrames = false
	if InCombatLockdown and InCombatLockdown() then
		GF._pendingDisable = true
		return
	end
	GF._pendingDisable = nil

	-- Unregister Edit Mode frames
	if EditMode and EditMode.UnregisterFrame then
		for _, id in pairs(EDITMODE_IDS) do
			pcall(EditMode.UnregisterFrame, EditMode, id)
		end
	end
	GF._editModeRegistered = nil

	-- Hide headers + anchors
	if GF.headers then
		for _, header in pairs(GF.headers) do
			if UnregisterStateDriver then UnregisterStateDriver(header, "visibility") end
			if RegisterStateDriver then RegisterStateDriver(header, "visibility", "hide") end
			if header.Hide then header:Hide() end
		end
	end
	if GF.anchors then
		for _, anchor in pairs(GF.anchors) do
			if anchor.Hide then anchor:Hide() end
		end
	end
end

function GF.Enable(kind)
	local cfg = getCfg(kind)
	cfg.enabled = true
	GF:EnsureHeaders()
	GF:ApplyHeaderAttributes(kind)
end

function GF.Disable(kind)
	local cfg = getCfg(kind)
	cfg.enabled = false
	GF:EnsureHeaders()
	GF:ApplyHeaderAttributes(kind)
end

function GF.Refresh(kind)
	if not isFeatureEnabled() then return end
	GF:EnsureHeaders()
	if kind then
		GF:ApplyHeaderAttributes(kind)
	else
		GF:ApplyHeaderAttributes("party")
		GF:ApplyHeaderAttributes("raid")
	end
end

-- -----------------------------------------------------------------------------
-- Edit Mode integration helpers
-- -----------------------------------------------------------------------------
local EDITMODE_IDS = {
	party = "EQOL_UF_GROUP_PARTY",
	raid = "EQOL_UF_GROUP_RAID",
}

local function anchorUsesUIParent(kind)
	local cfg = getCfg(kind)
	local rel = cfg and cfg.relativeTo
	return rel == nil or rel == "" or rel == "UIParent"
end

local function clampNumber(value, minValue, maxValue, fallback)
	local v = tonumber(value)
	if v == nil then return fallback end
	if minValue ~= nil and v < minValue then v = minValue end
	if maxValue ~= nil and v > maxValue then v = maxValue end
	return v
end

local function copySelectionMap(selection)
	local copy = {}
	if type(selection) ~= "table" then return copy end
	if #selection > 0 then
		for _, value in ipairs(selection) do
			if value ~= nil and (type(value) == "string" or type(value) == "number") then
				copy[value] = true
			end
		end
		return copy
	end
	for key, value in pairs(selection) do
		if value and (type(key) == "string" or type(key) == "number") then
			copy[key] = true
		end
	end
	return copy
end

local roleOptions = {
	{ value = "TANK", label = TANK or "Tank" },
	{ value = "HEALER", label = HEALER or "Healer" },
	{ value = "DAMAGER", label = DAMAGER or "DPS" },
}

local function defaultRoleSelection()
	local sel = {}
	for _, opt in ipairs(roleOptions) do
		sel[opt.value] = true
	end
	return sel
end

local function buildSpecOptions()
	local opts = {}
	if GetNumSpecializations and GetSpecializationInfo then
		for i = 1, GetNumSpecializations() do
			local specId, name = GetSpecializationInfo(i)
			if specId and name then
				opts[#opts + 1] = { value = specId, label = name }
			end
		end
	end
	return opts
end

local function defaultSpecSelection()
	local sel = {}
	if GetNumSpecializations and GetSpecializationInfo then
		for i = 1, GetNumSpecializations() do
			local specId = GetSpecializationInfo(i)
			if specId then sel[specId] = true end
		end
	end
	return sel
end

local auraAnchorOptions = {
	{ value = "TOPLEFT", label = "TOPLEFT" },
	{ value = "TOP", label = "TOP" },
	{ value = "TOPRIGHT", label = "TOPRIGHT" },
	{ value = "LEFT", label = "LEFT" },
	{ value = "CENTER", label = "CENTER" },
	{ value = "RIGHT", label = "RIGHT" },
	{ value = "BOTTOMLEFT", label = "BOTTOMLEFT" },
	{ value = "BOTTOM", label = "BOTTOM" },
	{ value = "BOTTOMRIGHT", label = "BOTTOMRIGHT" },
}

local function ensureAuraConfig(cfg)
	cfg.auras = cfg.auras or {}
	cfg.auras.buff = cfg.auras.buff or {}
	cfg.auras.debuff = cfg.auras.debuff or {}
	cfg.auras.externals = cfg.auras.externals or {}
	return cfg.auras
end

local function syncAurasEnabled(cfg)
	local ac = ensureAuraConfig(cfg)
	local enabled = false
	if ac.buff.enabled then enabled = true end
	if ac.debuff.enabled then enabled = true end
	if ac.externals.enabled then enabled = true end
	ac.enabled = enabled
end

local function buildEditModeSettings(kind, editModeId)
	if not SettingType then return nil end

	local widthLabel = HUD_EDIT_MODE_SETTING_CHAT_FRAME_WIDTH or "Width"
	local heightLabel = HUD_EDIT_MODE_SETTING_CHAT_FRAME_HEIGHT or "Height"
	local specOptions = buildSpecOptions()
	local settings = {
		{
			name = "Frame",
			kind = SettingType.Collapsible,
			id = "frame",
			defaultCollapsed = false,
		},
		{
			name = "Enabled",
			kind = SettingType.Checkbox,
			field = "enabled",
			default = (DEFAULTS[kind] and DEFAULTS[kind].enabled) or false,
			parentId = "frame",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.enabled == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.enabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "enabled", cfg.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = widthLabel,
			kind = SettingType.Slider,
			allowInput = true,
			field = "width",
			minValue = 40,
			maxValue = 600,
			valueStep = 1,
			default = (DEFAULTS[kind] and DEFAULTS[kind].width) or 100,
			parentId = "frame",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.width or (DEFAULTS[kind] and DEFAULTS[kind].width) or 100
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local v = clampNumber(value, 40, 600, cfg.width or 100)
				cfg.width = v
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "width", v, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = heightLabel,
			kind = SettingType.Slider,
			allowInput = true,
			field = "height",
			minValue = 10,
			maxValue = 200,
			valueStep = 1,
			default = (DEFAULTS[kind] and DEFAULTS[kind].height) or 24,
			parentId = "frame",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.height or (DEFAULTS[kind] and DEFAULTS[kind].height) or 24
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local v = clampNumber(value, 10, 200, cfg.height or 24)
				cfg.height = v
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "height", v, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Power height",
			kind = SettingType.Slider,
			allowInput = true,
			field = "powerHeight",
			minValue = 0,
			maxValue = 50,
			valueStep = 1,
			default = (DEFAULTS[kind] and DEFAULTS[kind].powerHeight) or 6,
			parentId = "frame",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.powerHeight or (DEFAULTS[kind] and DEFAULTS[kind].powerHeight) or 6
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local v = clampNumber(value, 0, 50, cfg.powerHeight or 6)
				cfg.powerHeight = v
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerHeight", v, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Layout",
			kind = SettingType.Collapsible,
			id = "layout",
			defaultCollapsed = false,
		},
		{
			name = "Spacing",
			kind = SettingType.Slider,
			allowInput = true,
			field = "spacing",
			minValue = 0,
			maxValue = 40,
			valueStep = 1,
			default = (DEFAULTS[kind] and DEFAULTS[kind].spacing) or 0,
			parentId = "layout",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.spacing or (DEFAULTS[kind] and DEFAULTS[kind].spacing) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local v = clampNumber(value, 0, 40, cfg.spacing or 0)
				cfg.spacing = v
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "spacing", v, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Growth",
			kind = SettingType.Dropdown,
			field = "growth",
			parentId = "layout",
			get = function()
				local cfg = getCfg(kind)
				return (cfg and cfg.growth) or (DEFAULTS[kind] and DEFAULTS[kind].growth) or "DOWN"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg or not value then return end
				cfg.growth = tostring(value):upper()
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "growth", cfg.growth, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				local options = {
					{ value = "DOWN", label = "Down" },
					{ value = "RIGHT", label = "Right" },
				}
				for _, option in ipairs(options) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						return (cfg and cfg.growth) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.growth = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "growth", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Text",
			kind = SettingType.Collapsible,
			id = "text",
			defaultCollapsed = true,
		},
		{
			name = "Name class color",
			kind = SettingType.Checkbox,
			field = "nameClassColor",
			parentId = "text",
			get = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				return tc.useClassColor ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.text = cfg.text or {}
				cfg.text.useClassColor = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameClassColor", cfg.text.useClassColor, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Health class color",
			kind = SettingType.Checkbox,
			field = "healthClassColor",
			parentId = "text",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.useClassColor == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.useClassColor = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthClassColor", cfg.health.useClassColor, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Power",
			kind = SettingType.Collapsible,
			id = "power",
			defaultCollapsed = true,
		},
		{
			name = "Show power for roles",
			kind = SettingType.MultiDropdown,
			field = "powerRoles",
			height = 140,
			values = roleOptions,
			parentId = "power",
			isSelected = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				local selection = pcfg.showRoles
				if type(selection) ~= "table" then return true end
				return selection[value] == true
			end,
			setSelected = function(_, value, state)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				local selection = cfg.power.showRoles
				if type(selection) ~= "table" then
					selection = defaultRoleSelection()
					cfg.power.showRoles = selection
				end
				if state then
					selection[value] = true
				else
					selection[value] = nil
				end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerRoles", copySelectionMap(selection), nil, true) end
				GF:RefreshPowerVisibility()
			end,
		},
		{
			name = "Show power for specs",
			kind = SettingType.MultiDropdown,
			field = "powerSpecs",
			height = 160,
			values = specOptions,
			parentId = "power",
			isSelected = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				local selection = pcfg.showSpecs
				if type(selection) ~= "table" then return true end
				return selection[value] == true
			end,
			setSelected = function(_, value, state)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				local selection = cfg.power.showSpecs
				if type(selection) ~= "table" then
					selection = defaultSpecSelection()
					cfg.power.showSpecs = selection
				end
				if state then
					selection[value] = true
				else
					selection[value] = nil
				end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerSpecs", copySelectionMap(selection), nil, true) end
				GF:RefreshPowerVisibility()
			end,
		},
		{
			name = "Buffs",
			kind = SettingType.Collapsible,
			id = "buffs",
			defaultCollapsed = true,
		},
		{
			name = "Enable buffs",
			kind = SettingType.Checkbox,
			field = "buffsEnabled",
			parentId = "buffs",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.enabled == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.buff.enabled = value and true or false
				syncAurasEnabled(cfg)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffsEnabled", ac.buff.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Buff anchor",
			kind = SettingType.Dropdown,
			field = "buffAnchor",
			parentId = "buffs",
			values = auraAnchorOptions,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.anchorPoint or "TOPLEFT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.buff.anchorPoint = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffAnchor", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Buff offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "buffOffsetX",
			parentId = "buffs",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.x or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.buff.x = clampNumber(value, -200, 200, ac.buff.x or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffOffsetX", ac.buff.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Buff offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "buffOffsetY",
			parentId = "buffs",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.y or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.buff.y = clampNumber(value, -200, 200, ac.buff.y or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffOffsetY", ac.buff.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Buff size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "buffSize",
			parentId = "buffs",
			minValue = 8,
			maxValue = 60,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.size or 16
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.buff.size = clampNumber(value, 8, 60, ac.buff.size or 16)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffSize", ac.buff.size, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Buff per row",
			kind = SettingType.Slider,
			allowInput = true,
			field = "buffPerRow",
			parentId = "buffs",
			minValue = 1,
			maxValue = 12,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.perRow or 6
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.buff.perRow = clampNumber(value, 1, 12, ac.buff.perRow or 6)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffPerRow", ac.buff.perRow, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Buff max",
			kind = SettingType.Slider,
			allowInput = true,
			field = "buffMax",
			parentId = "buffs",
			minValue = 0,
			maxValue = 20,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.max or 6
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.buff.max = clampNumber(value, 0, 20, ac.buff.max or 6)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffMax", ac.buff.max, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Buff spacing",
			kind = SettingType.Slider,
			allowInput = true,
			field = "buffSpacing",
			parentId = "buffs",
			minValue = 0,
			maxValue = 10,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.spacing or 2
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.buff.spacing = clampNumber(value, 0, 10, ac.buff.spacing or 2)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffSpacing", ac.buff.spacing, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Debuffs",
			kind = SettingType.Collapsible,
			id = "debuffs",
			defaultCollapsed = true,
		},
		{
			name = "Enable debuffs",
			kind = SettingType.Checkbox,
			field = "debuffsEnabled",
			parentId = "debuffs",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.enabled == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.debuff.enabled = value and true or false
				syncAurasEnabled(cfg)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffsEnabled", ac.debuff.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Debuff anchor",
			kind = SettingType.Dropdown,
			field = "debuffAnchor",
			parentId = "debuffs",
			values = auraAnchorOptions,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.anchorPoint or "BOTTOMLEFT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.debuff.anchorPoint = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffAnchor", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Debuff offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "debuffOffsetX",
			parentId = "debuffs",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.x or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.debuff.x = clampNumber(value, -200, 200, ac.debuff.x or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffOffsetX", ac.debuff.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Debuff offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "debuffOffsetY",
			parentId = "debuffs",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.y or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.debuff.y = clampNumber(value, -200, 200, ac.debuff.y or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffOffsetY", ac.debuff.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Debuff size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "debuffSize",
			parentId = "debuffs",
			minValue = 8,
			maxValue = 60,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.size or 16
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.debuff.size = clampNumber(value, 8, 60, ac.debuff.size or 16)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffSize", ac.debuff.size, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Debuff per row",
			kind = SettingType.Slider,
			allowInput = true,
			field = "debuffPerRow",
			parentId = "debuffs",
			minValue = 1,
			maxValue = 12,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.perRow or 6
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.debuff.perRow = clampNumber(value, 1, 12, ac.debuff.perRow or 6)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffPerRow", ac.debuff.perRow, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Debuff max",
			kind = SettingType.Slider,
			allowInput = true,
			field = "debuffMax",
			parentId = "debuffs",
			minValue = 0,
			maxValue = 20,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.max or 6
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.debuff.max = clampNumber(value, 0, 20, ac.debuff.max or 6)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffMax", ac.debuff.max, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Debuff spacing",
			kind = SettingType.Slider,
			allowInput = true,
			field = "debuffSpacing",
			parentId = "debuffs",
			minValue = 0,
			maxValue = 10,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.spacing or 2
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.debuff.spacing = clampNumber(value, 0, 10, ac.debuff.spacing or 2)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffSpacing", ac.debuff.spacing, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Externals",
			kind = SettingType.Collapsible,
			id = "externals",
			defaultCollapsed = true,
		},
		{
			name = "Enable externals",
			kind = SettingType.Checkbox,
			field = "externalsEnabled",
			parentId = "externals",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.enabled == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.enabled = value and true or false
				syncAurasEnabled(cfg)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalsEnabled", ac.externals.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "External anchor",
			kind = SettingType.Dropdown,
			field = "externalAnchor",
			parentId = "externals",
			values = auraAnchorOptions,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.anchorPoint or "TOPRIGHT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.anchorPoint = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalAnchor", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "External offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalOffsetX",
			parentId = "externals",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.x or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.x = clampNumber(value, -200, 200, ac.externals.x or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalOffsetX", ac.externals.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "External offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalOffsetY",
			parentId = "externals",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.y or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.y = clampNumber(value, -200, 200, ac.externals.y or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalOffsetY", ac.externals.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "External size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalSize",
			parentId = "externals",
			minValue = 8,
			maxValue = 60,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.size or 16
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.size = clampNumber(value, 8, 60, ac.externals.size or 16)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalSize", ac.externals.size, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "External per row",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalPerRow",
			parentId = "externals",
			minValue = 1,
			maxValue = 12,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.perRow or 6
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.perRow = clampNumber(value, 1, 12, ac.externals.perRow or 6)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalPerRow", ac.externals.perRow, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "External max",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalMax",
			parentId = "externals",
			minValue = 0,
			maxValue = 20,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.max or 4
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.max = clampNumber(value, 0, 20, ac.externals.max or 4)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalMax", ac.externals.max, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "External spacing",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalSpacing",
			parentId = "externals",
			minValue = 0,
			maxValue = 10,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.spacing or 2
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.spacing = clampNumber(value, 0, 10, ac.externals.spacing or 2)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalSpacing", ac.externals.spacing, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
	}

	if kind == "party" then
		settings[#settings + 1] = {
			name = "Party",
			kind = SettingType.Collapsible,
			id = "party",
			defaultCollapsed = false,
		}
		settings[#settings + 1] = {
			name = "Show player",
			kind = SettingType.Checkbox,
			field = "showPlayer",
			default = (DEFAULTS.party and DEFAULTS.party.showPlayer) or false,
			parentId = "party",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.showPlayer == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.showPlayer = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "showPlayer", cfg.showPlayer, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		}
		settings[#settings + 1] = {
			name = "Show solo",
			kind = SettingType.Checkbox,
			field = "showSolo",
			default = (DEFAULTS.party and DEFAULTS.party.showSolo) or false,
			parentId = "party",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.showSolo == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.showSolo = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "showSolo", cfg.showSolo, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		}
	elseif kind == "raid" then
		settings[#settings + 1] = {
			name = "Raid",
			kind = SettingType.Collapsible,
			id = "raid",
			defaultCollapsed = false,
		}
		settings[#settings + 1] = {
			name = "Units per column",
			kind = SettingType.Slider,
			allowInput = true,
			field = "unitsPerColumn",
			minValue = 1,
			maxValue = 10,
			valueStep = 1,
			default = (DEFAULTS.raid and DEFAULTS.raid.unitsPerColumn) or 5,
			parentId = "raid",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.unitsPerColumn or (DEFAULTS.raid and DEFAULTS.raid.unitsPerColumn) or 5
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local v = clampNumber(value, 1, 10, cfg.unitsPerColumn or 5)
				v = floor(v + 0.5)
				cfg.unitsPerColumn = v
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "unitsPerColumn", v, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		}
		settings[#settings + 1] = {
			name = "Max columns",
			kind = SettingType.Slider,
			allowInput = true,
			field = "maxColumns",
			minValue = 1,
			maxValue = 10,
			valueStep = 1,
			default = (DEFAULTS.raid and DEFAULTS.raid.maxColumns) or 8,
			parentId = "raid",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.maxColumns or (DEFAULTS.raid and DEFAULTS.raid.maxColumns) or 8
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local v = clampNumber(value, 1, 10, cfg.maxColumns or 8)
				v = floor(v + 0.5)
				cfg.maxColumns = v
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "maxColumns", v, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		}
		settings[#settings + 1] = {
			name = "Column spacing",
			kind = SettingType.Slider,
			allowInput = true,
			field = "columnSpacing",
			minValue = 0,
			maxValue = 40,
			valueStep = 1,
			default = (DEFAULTS.raid and DEFAULTS.raid.columnSpacing) or 0,
			parentId = "raid",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.columnSpacing or (DEFAULTS.raid and DEFAULTS.raid.columnSpacing) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local v = clampNumber(value, 0, 40, cfg.columnSpacing or 0)
				cfg.columnSpacing = v
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "columnSpacing", v, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		}
	end

	return settings
end

local function applyEditModeData(kind, data)
	if not data then return end
	local cfg = getCfg(kind)
	if not cfg then return end

	if data.point then
		cfg.point = data.point
		cfg.relativePoint = data.relativePoint or data.point
		cfg.x = data.x or 0
		cfg.y = data.y or 0
		if not cfg.relativeTo or cfg.relativeTo == "" then cfg.relativeTo = "UIParent" end
	end

	if data.width ~= nil then
		cfg.width = clampNumber(data.width, 40, 600, cfg.width or 100)
	end
	if data.height ~= nil then
		cfg.height = clampNumber(data.height, 10, 200, cfg.height or 24)
	end
	if data.powerHeight ~= nil then
		cfg.powerHeight = clampNumber(data.powerHeight, 0, 50, cfg.powerHeight or 6)
	end
	if data.spacing ~= nil then
		cfg.spacing = clampNumber(data.spacing, 0, 40, cfg.spacing or 0)
	end
	if data.growth then
		cfg.growth = tostring(data.growth):upper()
	end
	if data.enabled ~= nil then
		cfg.enabled = data.enabled and true or false
	end
	if data.nameClassColor ~= nil then
		cfg.text = cfg.text or {}
		cfg.text.useClassColor = data.nameClassColor and true or false
	end
	if data.healthClassColor ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.useClassColor = data.healthClassColor and true or false
	end
	if data.powerRoles ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.showRoles = copySelectionMap(data.powerRoles)
	end
	if data.powerSpecs ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.showSpecs = copySelectionMap(data.powerSpecs)
	end

	local ac = ensureAuraConfig(cfg)
	if data.buffsEnabled ~= nil then ac.buff.enabled = data.buffsEnabled and true or false end
	if data.buffAnchor ~= nil then ac.buff.anchorPoint = data.buffAnchor end
	if data.buffOffsetX ~= nil then ac.buff.x = data.buffOffsetX end
	if data.buffOffsetY ~= nil then ac.buff.y = data.buffOffsetY end
	if data.buffSize ~= nil then ac.buff.size = data.buffSize end
	if data.buffPerRow ~= nil then ac.buff.perRow = data.buffPerRow end
	if data.buffMax ~= nil then ac.buff.max = data.buffMax end
	if data.buffSpacing ~= nil then ac.buff.spacing = data.buffSpacing end

	if data.debuffsEnabled ~= nil then ac.debuff.enabled = data.debuffsEnabled and true or false end
	if data.debuffAnchor ~= nil then ac.debuff.anchorPoint = data.debuffAnchor end
	if data.debuffOffsetX ~= nil then ac.debuff.x = data.debuffOffsetX end
	if data.debuffOffsetY ~= nil then ac.debuff.y = data.debuffOffsetY end
	if data.debuffSize ~= nil then ac.debuff.size = data.debuffSize end
	if data.debuffPerRow ~= nil then ac.debuff.perRow = data.debuffPerRow end
	if data.debuffMax ~= nil then ac.debuff.max = data.debuffMax end
	if data.debuffSpacing ~= nil then ac.debuff.spacing = data.debuffSpacing end

	if data.externalsEnabled ~= nil then ac.externals.enabled = data.externalsEnabled and true or false end
	if data.externalAnchor ~= nil then ac.externals.anchorPoint = data.externalAnchor end
	if data.externalOffsetX ~= nil then ac.externals.x = data.externalOffsetX end
	if data.externalOffsetY ~= nil then ac.externals.y = data.externalOffsetY end
	if data.externalSize ~= nil then ac.externals.size = data.externalSize end
	if data.externalPerRow ~= nil then ac.externals.perRow = data.externalPerRow end
	if data.externalMax ~= nil then ac.externals.max = data.externalMax end
	if data.externalSpacing ~= nil then ac.externals.spacing = data.externalSpacing end
	syncAurasEnabled(cfg)

	if kind == "party" then
		if data.showPlayer ~= nil then cfg.showPlayer = data.showPlayer and true or false end
		if data.showSolo ~= nil then cfg.showSolo = data.showSolo and true or false end
	elseif kind == "raid" then
		if data.unitsPerColumn ~= nil then
			local v = clampNumber(data.unitsPerColumn, 1, 10, cfg.unitsPerColumn or 5)
			cfg.unitsPerColumn = floor(v + 0.5)
		end
		if data.maxColumns ~= nil then
			local v = clampNumber(data.maxColumns, 1, 10, cfg.maxColumns or 8)
			cfg.maxColumns = floor(v + 0.5)
		end
		if data.columnSpacing ~= nil then
			cfg.columnSpacing = clampNumber(data.columnSpacing, 0, 40, cfg.columnSpacing or 0)
		end
	end

	GF:ApplyHeaderAttributes(kind)
end

function GF:EnsureEditMode()
	if GF._editModeRegistered then return end
	if not isFeatureEnabled() then return end
	if not (EditMode and EditMode.RegisterFrame and EditMode.IsAvailable and EditMode:IsAvailable()) then return end

	GF:EnsureHeaders()

	for _, kind in ipairs({ "party", "raid" }) do
		local anchor = GF.anchors and GF.anchors[kind]
		if anchor then
			GF:UpdateAnchorSize(kind)
			local cfg = getCfg(kind)
			local ac = ensureAuraConfig(cfg)
			local pcfg = cfg.power or {}
			local defaults = {
				point = cfg.point or "CENTER",
				relativePoint = cfg.relativePoint or cfg.point or "CENTER",
				x = cfg.x or 0,
				y = cfg.y or 0,
				width = cfg.width or (DEFAULTS[kind] and DEFAULTS[kind].width) or 100,
				height = cfg.height or (DEFAULTS[kind] and DEFAULTS[kind].height) or 24,
				powerHeight = cfg.powerHeight or (DEFAULTS[kind] and DEFAULTS[kind].powerHeight) or 6,
				spacing = cfg.spacing or (DEFAULTS[kind] and DEFAULTS[kind].spacing) or 0,
				growth = cfg.growth or (DEFAULTS[kind] and DEFAULTS[kind].growth) or "DOWN",
				enabled = cfg.enabled == true,
				showPlayer = cfg.showPlayer == true,
				showSolo = cfg.showSolo == true,
				unitsPerColumn = cfg.unitsPerColumn or (DEFAULTS.raid and DEFAULTS.raid.unitsPerColumn) or 5,
				maxColumns = cfg.maxColumns or (DEFAULTS.raid and DEFAULTS.raid.maxColumns) or 8,
				columnSpacing = cfg.columnSpacing or (DEFAULTS.raid and DEFAULTS.raid.columnSpacing) or 0,
				nameClassColor = (cfg.text and cfg.text.useClassColor) ~= false,
				healthClassColor = (cfg.health and cfg.health.useClassColor) == true,
				powerRoles = (type(pcfg.showRoles) == "table") and copySelectionMap(pcfg.showRoles) or defaultRoleSelection(),
				powerSpecs = (type(pcfg.showSpecs) == "table") and copySelectionMap(pcfg.showSpecs) or defaultSpecSelection(),
				buffsEnabled = ac.buff.enabled == true,
				buffAnchor = ac.buff.anchorPoint or "TOPLEFT",
				buffOffsetX = ac.buff.x or 0,
				buffOffsetY = ac.buff.y or 0,
				buffSize = ac.buff.size or 16,
				buffPerRow = ac.buff.perRow or 6,
				buffMax = ac.buff.max or 6,
				buffSpacing = ac.buff.spacing or 2,
				debuffsEnabled = ac.debuff.enabled == true,
				debuffAnchor = ac.debuff.anchorPoint or "BOTTOMLEFT",
				debuffOffsetX = ac.debuff.x or 0,
				debuffOffsetY = ac.debuff.y or 0,
				debuffSize = ac.debuff.size or 16,
				debuffPerRow = ac.debuff.perRow or 6,
				debuffMax = ac.debuff.max or 6,
				debuffSpacing = ac.debuff.spacing or 2,
				externalsEnabled = ac.externals.enabled == true,
				externalAnchor = ac.externals.anchorPoint or "TOPRIGHT",
				externalOffsetX = ac.externals.x or 0,
				externalOffsetY = ac.externals.y or 0,
				externalSize = ac.externals.size or 16,
				externalPerRow = ac.externals.perRow or 6,
				externalMax = ac.externals.max or 4,
				externalSpacing = ac.externals.spacing or 2,
			}

			EditMode:RegisterFrame(EDITMODE_IDS[kind], {
				frame = anchor,
				title = (kind == "party") and (PARTY or "Party") or (RAID or "Raid"),
				layoutDefaults = defaults,
				settings = buildEditModeSettings(kind, EDITMODE_IDS[kind]),
				onApply = function(_, _, data) applyEditModeData(kind, data) end,
				onPositionChanged = function(_, _, data) applyEditModeData(kind, data) end,
				onEnter = function() GF:OnEnterEditMode(kind) end,
				onExit = function() GF:OnExitEditMode(kind) end,
				isEnabled = function() return true end,
				allowDrag = function() return anchorUsesUIParent(kind) end,
				showOutsideEditMode = false,
				showReset = false,
				showSettingsReset = false,
				enableOverlayToggle = true,
			})

			if addon.EditModeLib and addon.EditModeLib.SetFrameResetVisible then
				addon.EditModeLib:SetFrameResetVisible(anchor, false)
			end
		end
	end

	GF._editModeRegistered = true
	if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RefreshSettingValues then
		addon.EditModeLib.internal:RefreshSettingValues()
	end
end

function GF:OnEnterEditMode(kind)
	if not isFeatureEnabled() then return end
	GF:EnsureHeaders()
	local header = GF.headers and GF.headers[kind]
	if not header then return end
	header._eqolForceShow = true
	GF:ApplyHeaderAttributes(kind)
end

function GF:OnExitEditMode(kind)
	if not isFeatureEnabled() then return end
	GF:EnsureHeaders()
	local header = GF.headers and GF.headers[kind]
	if not header then return end
	header._eqolForceShow = nil
	GF:ApplyHeaderAttributes(kind)
end

-- -----------------------------------------------------------------------------
-- Bootstrap
-- -----------------------------------------------------------------------------

do
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:RegisterEvent("GROUP_ROSTER_UPDATE")
	f:RegisterEvent("PLAYER_ROLES_ASSIGNED")
	f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	f:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_LOGIN" then
			if isFeatureEnabled() then
				GF:EnsureHeaders()
				GF.Refresh()
				GF:EnsureEditMode()
			end
		elseif event == "PLAYER_REGEN_ENABLED" then
			if GF._pendingDisable then
				GF._pendingDisable = nil
				GF:DisableFeature()
			elseif GF._pendingRefresh then
				GF._pendingRefresh = false
				GF.Refresh()
			end
		elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
			GF:RefreshRoleIcons()
		elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
			GF:RefreshPowerVisibility()
		end
	end)
end
