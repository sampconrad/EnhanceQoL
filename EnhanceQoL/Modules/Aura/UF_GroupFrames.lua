-- luacheck: globals RegisterStateDriver UnregisterStateDriver RegisterUnitWatch
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

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
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitLevel = UnitLevel
local UnitGUID = UnitGUID
local C_Timer = C_Timer
local GetTime = GetTime
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitGroupRolesAssignedEnum = UnitGroupRolesAssignedEnum
local GetRaidTargetIndex = GetRaidTargetIndex
local SetRaidTargetIconTexture = SetRaidTargetIconTexture
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitIsGroupAssistant = UnitIsGroupAssistant
local UnitInRaid = UnitInRaid
local GetRaidRosterInfo = GetRaidRosterInfo
local GetSpecialization = GetSpecialization
local GetNumSpecializations = GetNumSpecializations
local GetSpecializationInfo = GetSpecializationInfo
local InCombatLockdown = InCombatLockdown
local RegisterStateDriver = RegisterStateDriver
local UnregisterStateDriver = UnregisterStateDriver
local issecretvalue = _G.issecretvalue
local C_UnitAuras = C_UnitAuras
local Enum = Enum
local GetMicroIconForRole = GetMicroIconForRole

local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local PowerBarColor = PowerBarColor
local LSM = LibStub and LibStub("LibSharedMedia-3.0")

local GFH = UF.GroupFramesHelper
local clampNumber = GFH.ClampNumber
local copySelectionMap = GFH.CopySelectionMap
local roleOptions = GFH.roleOptions
local defaultRoleSelection = GFH.DefaultRoleSelection
local buildSpecOptions = GFH.BuildSpecOptions
local defaultSpecSelection = GFH.DefaultSpecSelection
local auraAnchorOptions = GFH.auraAnchorOptions
local textAnchorOptions = GFH.textAnchorOptions
local anchorOptions9 = GFH.anchorOptions9 or GFH.auraAnchorOptions
local textModeOptions = GFH.textModeOptions
local delimiterOptions = GFH.delimiterOptions
local outlineOptions = GFH.outlineOptions
local auraGrowthOptions = GFH.auraGrowthOptions or GFH.auraGrowthXOptions
local auraGrowthXOptions = GFH.auraGrowthXOptions
local auraGrowthYOptions = GFH.auraGrowthYOptions
local ensureAuraConfig = GFH.EnsureAuraConfig
local syncAurasEnabled = GFH.SyncAurasEnabled
local function textureOptions() return GFH.TextureOptions(LSM) end
local function fontOptions() return GFH.FontOptions(LSM) end
local function borderOptions()
	local list = {}
	local seen = {}
	local function add(value, label)
		local lv = tostring(value or ""):lower()
		if lv == "" or seen[lv] then return end
		seen[lv] = true
		list[#list + 1] = { value = value, label = label }
	end
	add("DEFAULT", "Default (Border)")
	if not LSM then return list end
	local hash = LSM:HashTable("border") or {}
	for name, path in pairs(hash) do
		if type(path) == "string" and path ~= "" then add(name, tostring(name)) end
	end
	table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return list
end

local max = math.max
local floor = math.floor
local hooksecurefunc = hooksecurefunc
local BAR_TEX_INHERIT = "__PER_BAR__"
local EDIT_MODE_SAMPLE_MAX = 100
-- local AURA_FILTER_HELPFUL = "HELPFUL|INCLUDE_NAME_PLATE_ONLY|RAID|PLAYER"
local AURA_FILTER_HELPFUL = "HELPFUL|INCLUDE_NAME_PLATE_ONLY|RAID_IN_COMBAT|PLAYER"
local AURA_FILTER_HARMFUL = "HARMFUL|INCLUDE_NAME_PLATE_ONLY"
local AURA_FILTER_HARMFUL_ALL = "HARMFUL|INCLUDE_NAME_PLATE_ONLY|RAID_PLAYER_DISPELLABLE"
local AURA_FILTER_BIG_DEFENSIVE = "HELPFUL|BIG_DEFENSIVE"
local function dprint(...)
	if not (GF and GF._debugAuras) then return end
	print("|cff00ff98EQOL GF|r:", ...)
end

local function resolveBorderTexture(key)
	if UFHelper and UFHelper.resolveBorderTexture then return UFHelper.resolveBorderTexture(key) end
	if not key or key == "" or key == "DEFAULT" then return "Interface\\Buttons\\WHITE8x8" end
	if LSM then
		local tex = LSM:Fetch("border", key)
		if tex and tex ~= "" then return tex end
	end
	return key
end

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
		local insetVal = borderCfg.offset
		if insetVal == nil then insetVal = borderCfg.inset end
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

local function ensureHighlightFrame(st, key)
	if not (st and st.barGroup) then return nil end
	st._highlightFrames = st._highlightFrames or {}
	local frame = st._highlightFrames[key]
	if not frame then
		frame = CreateFrame("Frame", nil, st.barGroup, "BackdropTemplate")
		frame:EnableMouse(false)
		st._highlightFrames[key] = frame
	end
	frame:SetFrameStrata(st.barGroup:GetFrameStrata())
	local baseLevel = st.barGroup:GetFrameLevel() or 0
	frame:SetFrameLevel(baseLevel + 4)
	return frame
end

local function buildHighlightConfig(cfg, def, key)
	local hcfg = (cfg and cfg[key]) or {}
	local hdef = (def and def[key]) or {}
	local enabled = hcfg.enabled
	if enabled == nil then enabled = hdef.enabled end
	if enabled ~= true then return nil end
	local texture = hcfg.texture or hdef.texture or "DEFAULT"
	local size = tonumber(hcfg.size or hdef.size) or 1
	if size < 1 then size = 1 end
	local color = hcfg.color
	if type(color) ~= "table" then color = hdef.color end
	if type(color) ~= "table" then color = { 1, 1, 1, 1 } end
	local offset = hcfg.offset
	if offset == nil then offset = hdef.offset end
	offset = tonumber(offset) or 0
	return {
		enabled = true,
		texture = texture,
		size = size,
		color = color,
		offset = offset,
	}
end

local function applyHighlightStyle(st, cfg, key)
	if not st then return end
	local frame = st._highlightFrames and st._highlightFrames[key]
	if not cfg or cfg.enabled ~= true then
		if frame then
			if frame.SetBackdrop then frame:SetBackdrop(nil) end
			frame:Hide()
		end
		return
	end
	frame = ensureHighlightFrame(st, key)
	if not frame then return end
	local size = cfg.size or 1
	if size < 1 then size = 1 end
	local offset = cfg.offset or 0
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = resolveBorderTexture(cfg.texture),
		edgeSize = size,
		insets = { left = size, right = size, top = size, bottom = size },
	})
	frame:SetBackdropColor(0, 0, 0, 0)
	local color = cfg.color or { 1, 1, 1, 1 }
	frame:SetBackdropBorderColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", st.barGroup, "TOPLEFT", -offset, offset)
	frame:SetPoint("BOTTOMRIGHT", st.barGroup, "BOTTOMRIGHT", offset, -offset)
	frame:Hide()
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

local function getEffectiveBarTexture(cfg, barCfg)
	local tex = cfg and cfg.barTexture
	if tex == nil or tex == "" then tex = barCfg and barCfg.texture end
	return tex
end

local function stabilizeStatusBarTexture(bar)
	if not (bar and bar.GetStatusBarTexture) then return end
	local t = bar:GetStatusBarTexture()
	if not t then return end
	if t.SetHorizTile then t:SetHorizTile(false) end
	if t.SetVertTile then t:SetVertTile(false) end
	if t.SetTexCoord then t:SetTexCoord(0, 1, 0, 1) end
	if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(true) end
	if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
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

local function selectionContains(selection, key)
	if type(selection) ~= "table" or key == nil then return false end
	if selection[key] == true then return true end
	if #selection > 0 then
		for _, value in ipairs(selection) do
			if value == key then return true end
		end
	end
	return false
end

local function unpackColor(color, fallback)
	if not color then color = fallback end
	if not color then return 1, 1, 1, 1 end
	if color.r then return color.r, color.g, color.b, color.a or 1 end
	return color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
end

local function selectionMode(selection)
	if type(selection) ~= "table" then return "all" end
	if selectionHasAny(selection) then return "some" end
	return "none"
end

local function textModeUsesPercent(mode) return type(mode) == "string" and mode:find("PERCENT", 1, true) ~= nil end

local function setTextSlot(st, fs, cacheKey, mode, cur, maxv, useShort, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText)
	if not (st and fs) then return end
	local last = st[cacheKey]
	if issecretvalue and issecretvalue(last) then last = nil end
	if mode == "NONE" then
		if last ~= "" then
			st[cacheKey] = ""
			fs:SetText("")
		end
		return
	end
	local text
	if UFHelper and UFHelper.formatText then
		text = UFHelper.formatText(mode, cur, maxv, useShort, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText)
	else
		text = tostring(cur or 0)
	end
	if issecretvalue and issecretvalue(text) then
		fs:SetText(text)
		st[cacheKey] = nil
		return
	end
	if last ~= text then
		st[cacheKey] = text
		fs:SetText(text)
	end
end

local function normalizeTextMode(value)
	if value == "CURPERCENTDASH" then return "CURPERCENT" end
	return value
end

local delimiterModeCounts = {
	CURMAX = 1,
	CURPERCENT = 1,
	MAXPERCENT = 1,
	PERCENTMAX = 1,
	PERCENTCUR = 1,
	LEVELPERCENT = 1,
	CURMAXPERCENT = 2,
	PERCENTCURMAX = 2,
	LEVELPERCENTMAX = 2,
	LEVELPERCENTCUR = 2,
	LEVELPERCENTCURMAX = 3,
}

local function textModeDelimiterCount(value)
	local mode = normalizeTextMode(value)
	if type(mode) ~= "string" then return 0 end
	if mode == "PERCENT" or mode == "CURRENT" or mode == "MAX" or mode == "NONE" then return 0 end
	return delimiterModeCounts[mode] or 0
end

local function maxDelimiterCount(leftMode, centerMode, rightMode)
	local count = textModeDelimiterCount(leftMode)
	local centerCount = textModeDelimiterCount(centerMode)
	if centerCount > count then count = centerCount end
	local rightCount = textModeDelimiterCount(rightMode)
	if rightCount > count then count = rightCount end
	return count
end

local function getHealthPercent(unit, cur, maxv)
	if addon.functions and addon.functions.GetHealthPercent then return addon.functions.GetHealthPercent(unit, cur, maxv, true) end
	if issecretvalue and ((cur and issecretvalue(cur)) or (maxv and issecretvalue(maxv))) then return nil end
	if maxv and maxv > 0 then return (cur or 0) / maxv * 100 end
	return nil
end

local function getPowerPercent(unit, powerEnum, cur, maxv)
	if addon.functions and addon.functions.GetPowerPercent then return addon.functions.GetPowerPercent(unit, powerEnum, cur, maxv, true) end
	if issecretvalue and ((cur and issecretvalue(cur)) or (maxv and issecretvalue(maxv))) then return nil end
	if maxv and maxv > 0 then return (cur or 0) / maxv * 100 end
	return nil
end

local function getSafeLevelText(unit, hideClassText)
	if not unit then return "??" end
	if UnitLevel then
		local lvl = UnitLevel(unit)
		if issecretvalue and issecretvalue(lvl) then return "??" end
		if UFHelper and UFHelper.getUnitLevelText then return UFHelper.getUnitLevelText(unit, lvl, hideClassText) end
		lvl = tonumber(lvl) or 0
		if lvl > 0 then return tostring(lvl) end
	end
	if UFHelper and UFHelper.getUnitLevelText then return UFHelper.getUnitLevelText(unit, nil, hideClassText) end
	return "??"
end

local function getUnitRoleKey(unit)
	local roleEnum
	if UnitGroupRolesAssignedEnum then roleEnum = UnitGroupRolesAssignedEnum(unit) end
	if roleEnum and Enum and Enum.LFGRole then
		if roleEnum == Enum.LFGRole.Tank then return "TANK" end
		if roleEnum == Enum.LFGRole.Healer then return "HEALER" end
		if roleEnum == Enum.LFGRole.Damage then return "DAMAGER" end
	end
	local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
	if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
	return "NONE"
end

local function getPlayerSpecId()
	if not GetSpecialization then return nil end
	local specIndex = GetSpecialization()
	if not specIndex then return nil end
	if GetSpecializationInfo then
		local specId = GetSpecializationInfo(specIndex)
		return specId
	end
	return nil
end

local function shouldShowPowerForUnit(pcfg, unit)
	if not pcfg then return true end
	local roleMode = selectionMode(pcfg.showRoles)
	local specMode = selectionMode(pcfg.showSpecs)

	if roleMode == "some" then
		local roleKey = getUnitRoleKey(unit)
		return selectionContains(pcfg.showRoles, roleKey)
	end

	if roleMode == "none" then
		if specMode ~= "some" then return false end
		local specId = getPlayerSpecId()
		if not specId then return true end
		return selectionContains(pcfg.showSpecs, specId)
	end

	-- roleMode == "all"
	if specMode == "some" then
		local specId = getPlayerSpecId()
		if not specId then return true end
		return selectionContains(pcfg.showSpecs, specId)
	end
	if specMode == "none" then return false end
	return true
end

local function canShowPowerBySelection(pcfg)
	if not pcfg then return true end
	local roleMode = selectionMode(pcfg.showRoles)
	local specMode = selectionMode(pcfg.showSpecs)
	if roleMode == "some" then return true end
	if roleMode == "none" then return specMode == "some" end
	-- roleMode == "all"
	if specMode == "none" then return false end
	return true
end

local function isEditModeActive()
	local lib = addon.EditModeLib
	return lib and lib.IsInEditMode and lib:IsInEditMode()
end

-- -----------------------------------------------------------------------------
-- Defaults / DB helpers
-- -----------------------------------------------------------------------------

local DEFAULTS = {
	party = {
		enabled = false,
		showPlayer = true,
		showSolo = false,
		width = 180,
		height = 100,
		powerHeight = 6,
		spacing = 1,
		point = "TOPLEFT",
		relativePoint = "TOPLEFT",
		relativeTo = "UIParent",
		x = 500,
		y = -300,
		growth = "RIGHT", -- DOWN/UP/LEFT/RIGHT
		barTexture = "SOLID",
		border = {
			enabled = false,
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
		highlightHover = {
			enabled = false,
			texture = "DEFAULT",
			size = 2,
			offset = 0,
			color = { 1, 1, 1, 0.9 },
		},
		highlightTarget = {
			enabled = false,
			texture = "DEFAULT",
			size = 2,
			offset = 0,
			color = { 1, 1, 0, 1 },
		},
		health = {
			texture = "DEFAULT",
			font = nil,
			fontSize = 12,
			fontOutline = "OUTLINE",
			useCustomColor = false,
			useClassColor = true,
			color = { 0.0, 0.8, 0.0, 1 },
			absorbEnabled = true,
			absorbUseCustomColor = false,
			showSampleAbsorb = false,
			absorbColor = { 0.85, 0.95, 1.0, 0.7 },
			absorbTexture = "SOLID",
			absorbReverseFill = false,
			healAbsorbEnabled = true,
			healAbsorbUseCustomColor = false,
			showSampleHealAbsorb = false,
			healAbsorbColor = { 1.0, 0.3, 0.3, 0.7 },
			healAbsorbTexture = "SOLID",
			healAbsorbReverseFill = true,
			textLeft = "NONE",
			textCenter = "PERCENT",
			textRight = "CURRENT",
			textColor = { 1, 1, 1, 1 },
			textDelimiter = " ",
			textDelimiterSecondary = " ",
			textDelimiterTertiary = " ",
			useShortNumbers = true,
			hidePercentSymbol = false,
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
			textLeft = "NONE",
			textCenter = "NONE",
			textRight = "NONE",
			textColor = { 1, 1, 1, 1 },
			textDelimiter = " ",
			textDelimiterSecondary = " ",
			textDelimiterTertiary = " ",
			useShortNumbers = true,
			hidePercentSymbol = false,
			offsetLeft = { x = 6, y = 0 },
			offsetCenter = { x = 0, y = 0 },
			offsetRight = { x = -6, y = 0 },
			backdrop = { enabled = true, color = { 0, 0, 0, 0.6 } },
			showRoles = { TANK = true, HEALER = true, DAMAGER = false },
			showSpecs = {},
		},
		text = {
			showName = true,
			nameAnchor = "TOP",
			nameMaxChars = 15,
			showHealthPercent = true,
			showPowerPercent = false,
			useClassColor = true,
			font = nil,
			fontSize = 15,
			fontOutline = "OUTLINE",
			nameOffset = { x = 0, y = -4 },
		},
		status = {
			nameColorMode = "CLASS", -- CLASS or CUSTOM
			nameColor = { 1, 1, 1, 1 },
			levelEnabled = true,
			hideLevelAtMax = true,
			levelColorMode = "CUSTOM", -- CUSTOM or CLASS
			levelColor = { 1, 0.85, 0, 1 },
			levelFont = nil,
			levelFontSize = 12,
			levelFontOutline = "OUTLINE",
			levelAnchor = "TOPRIGHT",
			levelOffset = { x = -6, y = -4 },
			raidIcon = {
				enabled = true,
				size = 18,
				point = "TOP",
				relativePoint = "TOP",
				x = 0,
				y = 12,
			},
			leaderIcon = {
				enabled = true,
				size = 19,
				point = "TOPRIGHT",
				relativePoint = "TOPRIGHT",
				x = 6,
				y = 10,
			},
			assistIcon = {
				enabled = true,
				size = 12,
				point = "TOPLEFT",
				relativePoint = "TOPLEFT",
				x = 18,
				y = -2,
			},
		},
		roleIcon = {
			enabled = true,
			size = 16,
			point = "TOPLEFT",
			relativePoint = "TOPLEFT",
			x = 2,
			y = -2,
			spacing = 2,
			style = "TINY",
			showRoles = { TANK = true, HEALER = true, DAMAGER = false },
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
				growthX = "RIGHT",
				growthY = "DOWN",
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
				growthX = "RIGHT",
				growthY = "UP",
				x = 0,
				y = -4,
				showTooltip = true,
				showCooldown = true,
			},
			externals = {
				enabled = false,
				size = 34,
				perRow = 6,
				max = 2,
				spacing = 0,
				anchorPoint = "CENTER",
				growth = "RIGHTDOWN",
				growthX = "RIGHT",
				growthY = "DOWN",
				x = 0,
				y = 0,
				showTooltip = true,
				showCooldown = true,
				showDR = false,
				drAnchor = "TOPLEFT",
				drOffset = { x = 2, y = -2 },
				drFont = nil,
				drFontSize = 10,
				drFontOutline = "OUTLINE",
				drColor = { 1, 1, 1, 1 },
			},
		},
	},
	raid = {
		enabled = false,
		width = 180,
		height = 100,
		powerHeight = 6,
		spacing = 1,
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
		growth = "RIGHT", -- DOWN/UP/LEFT/RIGHT
		barTexture = "SOLID",
		columnSpacing = 8,
		border = {
			enabled = false,
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
		highlightHover = {
			enabled = false,
			texture = "DEFAULT",
			size = 2,
			offset = 0,
			color = { 1, 1, 1, 0.9 },
		},
		highlightTarget = {
			enabled = false,
			texture = "DEFAULT",
			size = 2,
			offset = 0,
			color = { 1, 1, 0, 1 },
		},
		health = {
			texture = "DEFAULT",
			font = nil,
			fontSize = 12,
			fontOutline = "OUTLINE",
			useCustomColor = false,
			useClassColor = true,
			color = { 0.0, 0.8, 0.0, 1 },
			absorbEnabled = true,
			absorbUseCustomColor = false,
			showSampleAbsorb = false,
			absorbColor = { 0.85, 0.95, 1.0, 0.7 },
			absorbTexture = "SOLID",
			absorbReverseFill = false,
			healAbsorbEnabled = true,
			healAbsorbUseCustomColor = false,
			showSampleHealAbsorb = false,
			healAbsorbColor = { 1.0, 0.3, 0.3, 0.7 },
			healAbsorbTexture = "SOLID",
			healAbsorbReverseFill = true,
			textLeft = "NONE",
			textCenter = "PERCENT",
			textRight = "CURRENT",
			textColor = { 1, 1, 1, 1 },
			textDelimiter = " ",
			textDelimiterSecondary = " ",
			textDelimiterTertiary = " ",
			useShortNumbers = true,
			hidePercentSymbol = false,
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
			textLeft = "NONE",
			textCenter = "NONE",
			textRight = "NONE",
			textDelimiter = " ",
			textDelimiterSecondary = " ",
			textDelimiterTertiary = " ",
			useShortNumbers = true,
			hidePercentSymbol = false,
			offsetLeft = { x = 5, y = 0 },
			offsetCenter = { x = 0, y = 0 },
			offsetRight = { x = -5, y = 0 },
			backdrop = { enabled = true, color = { 0, 0, 0, 0.6 } },
			showRoles = { TANK = true, HEALER = true, DAMAGER = false },
			showSpecs = {},
		},
		text = {
			showName = true,
			nameAnchor = "TOP",
			nameMaxChars = 15,
			showHealthPercent = false,
			showPowerPercent = false,
			useClassColor = true,
			font = nil,
			fontSize = 15,
			fontOutline = "OUTLINE",
			nameOffset = { x = 0, y = -4 },
		},
		status = {
			nameColorMode = "CLASS",
			nameColor = { 1, 1, 1, 1 },
			levelEnabled = true,
			hideLevelAtMax = true,
			levelColorMode = "CUSTOM",
			levelColor = { 1, 0.85, 0, 1 },
			levelFont = nil,
			levelFontSize = 12,
			levelFontOutline = "OUTLINE",
			levelAnchor = "TOPRIGHT",
			levelOffset = { x = -6, y = -4 },
			raidIcon = {
				enabled = true,
				size = 18,
				point = "TOP",
				relativePoint = "TOP",
				x = 0,
				y = 12,
			},
			leaderIcon = {
				enabled = true,
				size = 19,
				point = "TOPRIGHT",
				relativePoint = "TOPRIGHT",
				x = 6,
				y = 10,
			},
			assistIcon = {
				enabled = true,
				size = 10,
				point = "TOPLEFT",
				relativePoint = "TOPLEFT",
				x = 14,
				y = -1,
			},
		},
		roleIcon = {
			enabled = true,
			size = 16,
			point = "TOPLEFT",
			relativePoint = "TOPLEFT",
			x = 2,
			y = -2,
			spacing = 2,
			style = "TINY",
			showRoles = { TANK = true, HEALER = true, DAMAGER = false },
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
				growthX = "RIGHT",
				growthY = "DOWN",
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
				growthX = "RIGHT",
				growthY = "UP",
				x = 0,
				y = -3,
				showTooltip = true,
				showCooldown = true,
			},
			externals = {
				enabled = false,
				size = 34,
				perRow = 6,
				max = 2,
				spacing = 0,
				anchorPoint = "CENTER",
				growth = "RIGHTDOWN",
				growthX = "RIGHT",
				growthY = "DOWN",
				x = 0,
				y = 0,
				showTooltip = true,
				showCooldown = true,
				showDR = false,
				drAnchor = "TOPLEFT",
				drOffset = { x = 2, y = -2 },
				drFont = nil,
				drFontSize = 10,
				drFontOutline = "OUTLINE",
				drColor = { 1, 1, 1, 1 },
			},
		},
	},
}

local DB

local function sanitizeHealthColorMode(cfg)
	local hc = cfg and cfg.health
	if not hc then return end
	if hc.useCustomColor then
		hc.useClassColor = false
	elseif hc.useClassColor then
		hc.useCustomColor = false
	end
end

local function ensureDB()
	addon.db = addon.db or {}
	addon.db.ufGroupFrames = addon.db.ufGroupFrames or {}
	local db = addon.db.ufGroupFrames
	if db._eqolInited then
		DB = db
		return db
	end
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
		sanitizeHealthColorMode(t)
	end
	db._eqolInited = true
	DB = db
	return db
end

local function getCfg(kind)
	local db = DB or ensureDB()
	return db[kind] or DEFAULTS[kind]
end

local function isFeatureEnabled() return addon.db and addon.db.ufEnableGroupFrames == true end

-- Expose config for Settings / Edit Mode integration
function GF:GetConfig(kind) return getCfg(kind) end

function GF:IsFeatureEnabled() return isFeatureEnabled() end

function GF:EnsureDB() return ensureDB() end

-- -----------------------------------------------------------------------------
-- Internal state
-- -----------------------------------------------------------------------------

GF.headers = GF.headers or {}
GF.anchors = GF.anchors or {}
GF._pendingRefresh = GF._pendingRefresh or false
GF._pendingDisable = GF._pendingDisable or false

local registerFeatureEvents
local unregisterFeatureEvents

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

function GF:UpdateAbsorbCache(self, which)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st) then return end
	if UnitExists and not UnitExists(unit) then
		st._absorbAmount = 0
		st._healAbsorbAmount = 0
		return
	end
	if which == nil or which == "absorb" then st._absorbAmount = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0 end
	if which == nil or which == "heal" then st._healAbsorbAmount = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit) or 0 end
end

local function updateButtonConfig(self, cfg)
	if not self then return end
	cfg = cfg or self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	self._eqolCfg = cfg
	local st = getState(self)
	if not (st and cfg) then return end

	local tc = cfg.text or {}
	local hc = cfg.health or {}
	local pcfg = cfg.power or {}
	local ac = cfg.auras
	local scfg = cfg.status or {}

	st._wantsName = tc.showName ~= false
	st._wantsLevel = scfg.levelEnabled ~= false
	st._wantsAbsorb = (hc.absorbEnabled ~= false) or (hc.healAbsorbEnabled ~= false)

	local wantsPower = true
	local powerHeight = cfg.powerHeight
	if powerHeight ~= nil and tonumber(powerHeight) <= 0 then wantsPower = false end
	if wantsPower and not canShowPowerBySelection(pcfg) then wantsPower = false end
	st._wantsPower = wantsPower

	local wantsAuras = false
	if ac then
		if ac.enabled == true then
			wantsAuras = true
		elseif ac.enabled == false then
			wantsAuras = false
		else
			wantsAuras = (ac.buff and ac.buff.enabled) or (ac.debuff and ac.debuff.enabled) or (ac.externals and ac.externals.enabled) or false
		end
	end
	st._wantsAuras = wantsAuras
end

function GF:RequestAuraUpdate(self, updateInfo)
	if not self then return end
	GF:UpdateAuras(self, updateInfo)
end

function GF:CacheUnitStatic(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st) then return end

	local guid = UnitGUID and UnitGUID(unit)
	if st._guid == guid and st._unitToken == unit then return end
	st._guid = guid
	st._unitToken = unit

	if UnitClass then
		local _, class = UnitClass(unit)
		st._class = class
		if class then
			st._classR, st._classG, st._classB, st._classA = getClassColor(class)
		else
			st._classR, st._classG, st._classB, st._classA = nil, nil, nil, nil
		end
	else
		st._class = nil
		st._classR, st._classG, st._classB, st._classA = nil, nil, nil, nil
	end
end

-- -----------------------------------------------------------------------------
-- Unit button construction
-- -----------------------------------------------------------------------------
function GF:BuildButton(self)
	if not self then return end
	local st = getState(self)

	local kind = self._eqolGroupKind or "party"
	local cfg = getCfg(kind)
	self._eqolCfg = cfg
	updateButtonConfig(self, cfg)
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
		local healthTexKey = getEffectiveBarTexture(cfg, hc)
		st.health:SetStatusBarTexture(UFHelper.resolveTexture(healthTexKey))
		if UFHelper.configureSpecialTexture then UFHelper.configureSpecialTexture(st.health, "HEALTH", healthTexKey, hc) end
		st._lastHealthTexture = healthTexKey
	end
	stabilizeStatusBarTexture(st.health)
	applyBarBackdrop(st.health, hc)

	-- Absorb overlays
	if not st.absorb then
		st.absorb = CreateFrame("StatusBar", nil, st.health, "BackdropTemplate")
		st.absorb:SetMinMaxValues(0, 1)
		st.absorb:SetValue(0)
		if st.absorb.SetStatusBarDesaturated then st.absorb:SetStatusBarDesaturated(false) end
		st.absorb:Hide()
	end
	if not st.healAbsorb then
		st.healAbsorb = CreateFrame("StatusBar", nil, st.health, "BackdropTemplate")
		st.healAbsorb:SetMinMaxValues(0, 1)
		st.healAbsorb:SetValue(0)
		if st.healAbsorb.SetStatusBarDesaturated then st.healAbsorb:SetStatusBarDesaturated(false) end
		st.healAbsorb:Hide()
	end
	-- no absorb glow in group frames

	-- Power bar
	if not st.power then
		st.power = CreateFrame("StatusBar", nil, st.barGroup, "BackdropTemplate")
		st.power:SetMinMaxValues(0, 1)
		st.power:SetValue(0)
	end
	if st.power.SetStatusBarTexture and UFHelper and UFHelper.resolveTexture then
		local powerTexKey = getEffectiveBarTexture(cfg, pcfg)
		st.power:SetStatusBarTexture(UFHelper.resolveTexture(powerTexKey))
		st._lastPowerTexture = powerTexKey
	end
	applyBarBackdrop(st.power, pcfg)
	if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated(true) end

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
	if not st.levelText then st.levelText = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end

	local indicatorLayer = st.healthTextLayer
	if not st.leaderIcon then st.leaderIcon = indicatorLayer:CreateTexture(nil, "OVERLAY", nil, 7) end
	if not st.assistIcon then st.assistIcon = indicatorLayer:CreateTexture(nil, "OVERLAY", nil, 7) end
	if not st.raidIcon then
		st.raidIcon = indicatorLayer:CreateTexture(nil, "OVERLAY", nil, 7)
		st.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
		st.raidIcon:SetSize(18, 18)
		st.raidIcon:Hide()
	end
	if st.leaderIcon.GetParent and st.leaderIcon:GetParent() ~= indicatorLayer then st.leaderIcon:SetParent(indicatorLayer) end
	if st.assistIcon.GetParent and st.assistIcon:GetParent() ~= indicatorLayer then st.assistIcon:SetParent(indicatorLayer) end
	if st.raidIcon.GetParent and st.raidIcon:GetParent() ~= indicatorLayer then st.raidIcon:SetParent(indicatorLayer) end
	if st.leaderIcon.SetDrawLayer then st.leaderIcon:SetDrawLayer("OVERLAY", 7) end
	if st.assistIcon.SetDrawLayer then st.assistIcon:SetDrawLayer("OVERLAY", 7) end
	if st.raidIcon.SetDrawLayer then st.raidIcon:SetDrawLayer("OVERLAY", 7) end

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

	-- Layout updates on resize
	if not st._sizeHooked then
		st._sizeHooked = true
		self:HookScript("OnSizeChanged", function(btn) GF:LayoutButton(btn) end)
	end

	self:SetClampedToScreen(true)
	self:SetScript("OnMouseDown", nil) -- keep clean; secure click handles targeting.

	-- Menu function used by the secure "togglemenu" click.
	if not st._menuHooked then
		st._menuHooked = true
		self.menu = function(btn) GF:OpenUnitMenu(btn) end
	end

	GF:LayoutAuras(self)
	hookTextFrameLevels(st)
	GF:LayoutButton(self)
end

function GF:LayoutButton(self)
	if not self then return end
	local st = getState(self)
	if not (st and st.barGroup and st.health and st.power) then return end

	local kind = self._eqolGroupKind -- set by header helper
	local cfg = self._eqolCfg or getCfg(kind or "party")
	local def = DEFAULTS[kind] or {}
	local hc = cfg.health or {}
	local defH = def.health or {}
	local powerH = tonumber(cfg.powerHeight) or 5
	if st._powerHidden then powerH = 0 end
	local w, h = self:GetSize()
	if not w or not h then return end
	local borderOffset = 0
	local bc = cfg.border or {}
	if bc.enabled ~= false then
		borderOffset = bc.offset
		if borderOffset == nil then borderOffset = bc.edgeSize or 1 end
		borderOffset = max(0, borderOffset or 0)
	end
	local maxOffset = floor((math.min(w, h) - 4) / 2)
	if maxOffset < 0 then maxOffset = 0 end
	if borderOffset > maxOffset then borderOffset = maxOffset end
	local availH = h - borderOffset * 2
	if availH < 1 then availH = 1 end
	if powerH > availH - 4 then powerH = math.max(0, availH * 0.25) end

	st.barGroup:SetAllPoints(self)
	setBackdrop(st.barGroup, cfg.border)

	-- Highlight borders (hover / target)
	st._highlightHoverCfg = buildHighlightConfig(cfg, def, "highlightHover")
	st._highlightTargetCfg = buildHighlightConfig(cfg, def, "highlightTarget")
	applyHighlightStyle(st, st._highlightHoverCfg, "hover")
	applyHighlightStyle(st, st._highlightTargetCfg, "target")

	st.power:ClearAllPoints()
	st.power:SetPoint("BOTTOMLEFT", st.barGroup, "BOTTOMLEFT", borderOffset, borderOffset)
	st.power:SetPoint("BOTTOMRIGHT", st.barGroup, "BOTTOMRIGHT", -borderOffset, borderOffset)
	st.power:SetHeight(powerH)

	st.health:ClearAllPoints()
	st.health:SetPoint("TOPLEFT", st.barGroup, "TOPLEFT", borderOffset, -borderOffset)
	st.health:SetPoint("BOTTOMRIGHT", st.barGroup, "BOTTOMRIGHT", -borderOffset, powerH + borderOffset)

	-- Text layout (mirrors UF.lua positioning logic)
	if UFHelper and UFHelper.applyFont then
		UFHelper.applyFont(st.healthTextLeft, hc.font, hc.fontSize or 12, hc.fontOutline)
		UFHelper.applyFont(st.healthTextCenter, hc.font, hc.fontSize or 12, hc.fontOutline)
		UFHelper.applyFont(st.healthTextRight, hc.font, hc.fontSize or 12, hc.fontOutline)
		local pcfgLocal = cfg.power or {}
		UFHelper.applyFont(st.powerTextLeft, pcfgLocal.font, pcfgLocal.fontSize or 10, pcfgLocal.fontOutline)
		UFHelper.applyFont(st.powerTextCenter, pcfgLocal.font, pcfgLocal.fontSize or 10, pcfgLocal.fontOutline)
		UFHelper.applyFont(st.powerTextRight, pcfgLocal.font, pcfgLocal.fontSize or 10, pcfgLocal.fontOutline)
	end
	layoutTexts(st.health, st.healthTextLeft, st.healthTextCenter, st.healthTextRight, cfg.health)
	layoutTexts(st.power, st.powerTextLeft, st.powerTextCenter, st.powerTextRight, cfg.power)

	local healthTexKey = getEffectiveBarTexture(cfg, hc)
	if st.health.SetStatusBarTexture and UFHelper and UFHelper.resolveTexture then
		if st._lastHealthTexture ~= healthTexKey then
			st.health:SetStatusBarTexture(UFHelper.resolveTexture(healthTexKey))
			if UFHelper.configureSpecialTexture then UFHelper.configureSpecialTexture(st.health, "HEALTH", healthTexKey, hc) end
			st._lastHealthTexture = healthTexKey
			stabilizeStatusBarTexture(st.health)
		end
	end
	local pcfg = cfg.power or {}
	local powerTexKey = getEffectiveBarTexture(cfg, pcfg)
	if st.power.SetStatusBarTexture and UFHelper and UFHelper.resolveTexture then
		if st._lastPowerTexture ~= powerTexKey then
			st.power:SetStatusBarTexture(UFHelper.resolveTexture(powerTexKey))
			st._lastPowerTexture = powerTexKey
			stabilizeStatusBarTexture(st.power)
		end
	end

	-- Absorb overlays
	if st.absorb then
		local absorbTextureKey = hc.absorbTexture or healthTexKey
		if st.absorb.SetStatusBarTexture and UFHelper and UFHelper.resolveTexture then
			st.absorb:SetStatusBarTexture(UFHelper.resolveTexture(absorbTextureKey))
			if UFHelper.configureSpecialTexture then UFHelper.configureSpecialTexture(st.absorb, "HEALTH", absorbTextureKey, hc) end
		end
		if st.absorb.SetStatusBarDesaturated then st.absorb:SetStatusBarDesaturated(false) end
		if UFHelper and UFHelper.applyStatusBarReverseFill then UFHelper.applyStatusBarReverseFill(st.absorb, hc.absorbReverseFill == true) end
		stabilizeStatusBarTexture(st.absorb)
		st.absorb:ClearAllPoints()
		st.absorb:SetAllPoints(st.health)
		setFrameLevelAbove(st.absorb, st.health, 1)
	end
	if st.healAbsorb then
		local healAbsorbTextureKey = hc.healAbsorbTexture or healthTexKey
		if st.healAbsorb.SetStatusBarTexture and UFHelper and UFHelper.resolveTexture then
			st.healAbsorb:SetStatusBarTexture(UFHelper.resolveTexture(healAbsorbTextureKey))
			if UFHelper.configureSpecialTexture then UFHelper.configureSpecialTexture(st.healAbsorb, "HEALTH", healAbsorbTextureKey, hc) end
		end
		if st.healAbsorb.SetStatusBarDesaturated then st.healAbsorb:SetStatusBarDesaturated(false) end
		if UFHelper and UFHelper.applyStatusBarReverseFill then UFHelper.applyStatusBarReverseFill(st.healAbsorb, hc.healAbsorbReverseFill == true) end
		stabilizeStatusBarTexture(st.healAbsorb)
		st.healAbsorb:ClearAllPoints()
		st.healAbsorb:SetAllPoints(st.health)
		setFrameLevelAbove(st.healAbsorb, st.absorb or st.health, 1)
	end
	-- Name + role icon layout
	local tc = cfg.text or {}
	local rc = cfg.roleIcon or {}
	local sc = cfg.status or {}
	local rolePad = 0
	local roleEnabled = rc.enabled ~= false
	if roleEnabled and type(rc.showRoles) == "table" and not selectionHasAny(rc.showRoles) then roleEnabled = false end
	if roleEnabled then
		local indicatorLayer = st.healthTextLayer or st.health
		if not st.roleIcon then st.roleIcon = indicatorLayer:CreateTexture(nil, "OVERLAY", nil, 7) end
		if st.roleIcon.GetParent and st.roleIcon:GetParent() ~= indicatorLayer then st.roleIcon:SetParent(indicatorLayer) end
		if st.roleIcon.SetDrawLayer then st.roleIcon:SetDrawLayer("OVERLAY", 7) end
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
		local nameAnchor = tc.nameAnchor or "LEFT"
		local baseOffset = (cfg.health and cfg.health.offsetLeft) or {}
		if nameAnchor and nameAnchor:find("RIGHT") then
			baseOffset = (cfg.health and cfg.health.offsetRight) or {}
		elseif nameAnchor and not nameAnchor:find("LEFT") then
			baseOffset = (cfg.health and cfg.health.offsetCenter) or {}
		end
		local nameOffset = tc.nameOffset or {}
		local namePad = (nameAnchor and nameAnchor:find("LEFT")) and rolePad or 0
		local nameX = (nameOffset.x ~= nil and nameOffset.x or baseOffset.x or 6) + namePad
		local nameY = nameOffset.y ~= nil and nameOffset.y or baseOffset.y or 0
		local nameMaxChars = tonumber(tc.nameMaxChars) or 0
		st.nameText:ClearAllPoints()
		st.nameText:SetPoint(nameAnchor, st.health, nameAnchor, nameX, nameY)
		if nameMaxChars <= 0 then
			local vert = "CENTER"
			if nameAnchor and nameAnchor:find("TOP") then
				vert = "TOP"
			elseif nameAnchor and nameAnchor:find("BOTTOM") then
				vert = "BOTTOM"
			end
			local leftPoint = (vert == "CENTER") and "LEFT" or (vert .. "LEFT")
			local rightPoint = (vert == "CENTER") and "RIGHT" or (vert .. "RIGHT")
			st.nameText:SetPoint(leftPoint, st.health, leftPoint, nameX, nameY)
			st.nameText:SetPoint(rightPoint, st.health, rightPoint, -4, nameY)
		end
		local justify = "CENTER"
		if nameAnchor and nameAnchor:find("LEFT") then
			justify = "LEFT"
		elseif nameAnchor and nameAnchor:find("RIGHT") then
			justify = "RIGHT"
		end
		st.nameText:SetJustifyH(justify)
		local showName = tc.showName ~= false
		st.nameText:SetShown(showName)
		if not showName then
			st.nameText:SetText("")
			st._lastName = nil
		end
		if UFHelper and UFHelper.applyNameCharLimit then
			local nameCfg = st._nameLimitCfg or {}
			nameCfg.nameMaxChars = tc.nameMaxChars
			nameCfg.font = tc.font or hc.font
			nameCfg.fontSize = tc.fontSize or hc.fontSize or 12
			nameCfg.fontOutline = tc.fontOutline or hc.fontOutline
			st._nameLimitCfg = nameCfg
			UFHelper.applyNameCharLimit(st, nameCfg, nil)
		end
	end

	if st.levelText then
		if UFHelper and UFHelper.applyFont then
			local hc = cfg.health or {}
			local levelFont = sc.levelFont or tc.font or hc.font
			local levelFontSize = sc.levelFontSize or tc.fontSize or hc.fontSize or 12
			local levelOutline = sc.levelFontOutline or tc.fontOutline or hc.fontOutline
			UFHelper.applyFont(st.levelText, levelFont, levelFontSize, levelOutline)
		end
		local anchor = sc.levelAnchor or "RIGHT"
		local levelOffset = sc.levelOffset or {}
		st.levelText:ClearAllPoints()
		st.levelText:SetPoint(anchor, st.health, anchor, levelOffset.x or 0, levelOffset.y or 0)
		local justify = "CENTER"
		if anchor and anchor:find("LEFT") then
			justify = "LEFT"
		elseif anchor and anchor:find("RIGHT") then
			justify = "RIGHT"
		end
		st.levelText:SetJustifyH(justify)
	end

	if st.raidIcon then
		local ric = sc.raidIcon or {}
		local indicatorLayer = st.healthTextLayer or st.health
		if st.raidIcon.GetParent and st.raidIcon:GetParent() ~= indicatorLayer then st.raidIcon:SetParent(indicatorLayer) end
		if st.raidIcon.SetDrawLayer then st.raidIcon:SetDrawLayer("OVERLAY", 7) end
		if ric.enabled ~= false then
			local size = ric.size or 18
			st.raidIcon:ClearAllPoints()
			st.raidIcon:SetPoint(ric.point or "TOP", st.barGroup, ric.relativePoint or ric.point or "TOP", ric.x or 0, ric.y or -2)
			st.raidIcon:SetSize(size, size)
		else
			st.raidIcon:Hide()
		end
	end

	-- Health text color
	if st.healthTextLeft or st.healthTextCenter or st.healthTextRight then
		local r, g, b, a = unpackColor(hc.textColor, defH.textColor or { 1, 1, 1, 1 })
		if st._lastHealthTextR ~= r or st._lastHealthTextG ~= g or st._lastHealthTextB ~= b or st._lastHealthTextA ~= a then
			st._lastHealthTextR, st._lastHealthTextG, st._lastHealthTextB, st._lastHealthTextA = r, g, b, a
			if st.healthTextLeft then st.healthTextLeft:SetTextColor(r, g, b, a) end
			if st.healthTextCenter then st.healthTextCenter:SetTextColor(r, g, b, a) end
			if st.healthTextRight then st.healthTextRight:SetTextColor(r, g, b, a) end
		end
	end

	if st.leaderIcon then
		local lc = sc.leaderIcon or {}
		local indicatorLayer = st.healthTextLayer or st.health
		if st.leaderIcon.GetParent and st.leaderIcon:GetParent() ~= indicatorLayer then st.leaderIcon:SetParent(indicatorLayer) end
		if st.leaderIcon.SetDrawLayer then st.leaderIcon:SetDrawLayer("OVERLAY", 7) end
		if lc.enabled ~= false then
			local size = lc.size or 12
			st.leaderIcon:ClearAllPoints()
			st.leaderIcon:SetPoint(lc.point or "TOPLEFT", st.health, lc.relativePoint or "TOPLEFT", lc.x or 0, lc.y or 0)
			st.leaderIcon:SetSize(size, size)
		else
			st.leaderIcon:Hide()
		end
	end

	if st.assistIcon then
		local acfg = sc.assistIcon or {}
		local indicatorLayer = st.healthTextLayer or st.health
		if st.assistIcon.GetParent and st.assistIcon:GetParent() ~= indicatorLayer then st.assistIcon:SetParent(indicatorLayer) end
		if st.assistIcon.SetDrawLayer then st.assistIcon:SetDrawLayer("OVERLAY", 7) end
		if acfg.enabled ~= false then
			local size = acfg.size or 12
			st.assistIcon:ClearAllPoints()
			st.assistIcon:SetPoint(acfg.point or "TOPLEFT", st.health, acfg.relativePoint or "TOPLEFT", acfg.x or 0, acfg.y or 0)
			st.assistIcon:SetSize(size, size)
		else
			st.assistIcon:Hide()
		end
	end

	-- Keep text above bars
	local baseLevel = (st.barGroup:GetFrameLevel() or 0)
	st.health:SetFrameLevel(baseLevel + 1)
	st.power:SetFrameLevel(baseLevel + 1)
	syncTextFrameLevels(st)

	-- Pixel quantization caches (reset on layout changes)
	st._lastHealthPx = nil
	st._lastHealthBarW = nil
	st._lastPowerPx = nil
	st._lastPowerBarW = nil

	GF:UpdateHighlightState(self)
end

-- -----------------------------------------------------------------------------
-- Updates
-- -----------------------------------------------------------------------------

local GROW_DIRS = { "UP", "DOWN", "LEFT", "RIGHT" }

local function parseAuraGrowth(growth)
	if not growth or growth == "" then return end
	local raw = tostring(growth):upper()
	local first, second = raw:match("^(%a+)[_%s]+(%a+)$")
	if not first then
		for i = 1, #GROW_DIRS do
			local dir = GROW_DIRS[i]
			if raw:sub(1, #dir) == dir then
				local rest = raw:sub(#dir + 1)
				if rest == "UP" or rest == "DOWN" or rest == "LEFT" or rest == "RIGHT" then
					first, second = dir, rest
					break
				end
			end
		end
	end
	if not first or not second then return end
	local firstVertical = first == "UP" or first == "DOWN"
	local secondVertical = second == "UP" or second == "DOWN"
	if firstVertical == secondVertical then return end
	return first, second
end

local function resolveAuraGrowth(anchorPoint, growth, growthX, growthY)
	local anchor = (anchorPoint or "TOPLEFT"):upper()
	local primary, secondary = parseAuraGrowth(growth)
	if not primary and growthX and growthY then
		local gx = tostring(growthX):upper()
		local gy = tostring(growthY):upper()
		local gxVert = gx == "UP" or gx == "DOWN"
		local gyVert = gy == "UP" or gy == "DOWN"
		if gxVert ~= gyVert then
			primary, secondary = gx, gy
		end
	end
	if not primary then
		local fallback
		if anchor:find("TOP", 1, true) then
			fallback = "RIGHTUP"
		elseif anchor:find("LEFT", 1, true) then
			fallback = "LEFTDOWN"
		else
			fallback = "RIGHTDOWN"
		end
		primary, secondary = parseAuraGrowth(fallback)
	end
	return anchor, primary, secondary
end

local function growthPairToString(primary, secondary)
	if not primary or not secondary then return nil end
	return tostring(primary):upper() .. tostring(secondary):upper()
end

local function getAuraGrowthValue(typeCfg, anchorPoint)
	if typeCfg and typeCfg.growth and typeCfg.growth ~= "" then
		local primary, secondary = parseAuraGrowth(typeCfg.growth)
		if primary then return growthPairToString(primary, secondary) end
	end
	local _, primary, secondary = resolveAuraGrowth(anchorPoint, nil, typeCfg and typeCfg.growthX, typeCfg and typeCfg.growthY)
	return growthPairToString(primary, secondary) or "RIGHTDOWN"
end

local function applyAuraGrowth(typeCfg, value)
	if not typeCfg then return end
	if value == nil or value == "" then
		typeCfg.growth = nil
		return
	end
	local primary, secondary = parseAuraGrowth(value)
	if not primary then return end
	typeCfg.growth = tostring(value):upper()
	local primaryHorizontal = primary == "LEFT" or primary == "RIGHT"
	local horizontalDir = primaryHorizontal and primary or secondary
	local verticalDir = primaryHorizontal and secondary or primary
	typeCfg.growthX = horizontalDir
	typeCfg.growthY = verticalDir
end

local function ensureAuraContainer(st, key)
	if not st then return nil end
	if not st[key] then
		st[key] = CreateFrame("Frame", nil, st.barGroup or st.frame)
		st[key]:EnableMouse(false)
	end
	local base = st.healthTextLayer or st.barGroup or st.frame or st[key]:GetParent()
	if base then
		if st[key].SetFrameStrata and base.GetFrameStrata then st[key]:SetFrameStrata(base:GetFrameStrata()) end
		if st[key].SetFrameLevel and base.GetFrameLevel then st[key]:SetFrameLevel((base:GetFrameLevel() or 0) + 5) end
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

local function calcAuraGridSize(shown, perRow, size, spacing, primary)
	if shown == nil or shown < 1 then return 0.001, 0.001 end
	perRow = perRow or 1
	if perRow < 1 then perRow = 1 end
	size = size or 16
	spacing = spacing or 0
	local primaryVertical = primary == "UP" or primary == "DOWN"
	local rows, cols
	if primaryVertical then
		rows = math.min(shown, perRow)
		cols = math.ceil(shown / perRow)
	else
		rows = math.ceil(shown / perRow)
		cols = math.min(shown, perRow)
	end
	if rows < 1 then rows = 1 end
	if cols < 1 then cols = 1 end
	local w = cols * size + spacing * max(0, cols - 1)
	local h = rows * size + spacing * max(0, rows - 1)
	if w <= 0 then w = 0.001 end
	if h <= 0 then h = 0.001 end
	return w, h
end

local function positionAuraButton(btn, container, primary, secondary, index, perRow, size, spacing)
	if not (btn and container) then return end
	perRow = perRow or 1
	if perRow < 1 then perRow = 1 end
	local primaryHorizontal = primary == "LEFT" or primary == "RIGHT"
	local row, col
	if primaryHorizontal then
		row = math.floor((index - 1) / perRow)
		col = (index - 1) % perRow
	else
		row = (index - 1) % perRow
		col = math.floor((index - 1) / perRow)
	end
	local horizontalDir = primaryHorizontal and primary or secondary
	local verticalDir = primaryHorizontal and secondary or primary
	local xSign = (horizontalDir == "RIGHT") and 1 or -1
	local ySign = (verticalDir == "UP") and 1 or -1
	local basePoint = (ySign == 1 and "BOTTOM" or "TOP") .. (xSign == 1 and "LEFT" or "RIGHT")
	btn:ClearAllPoints()
	btn:SetPoint(basePoint, container, basePoint, col * (size + spacing) * xSign, row * (size + spacing) * ySign)
end

local function resolveRoleAtlas(roleKey, style)
	if roleKey == "NONE" then return nil end
	if style == "CIRCLE" then
		if GetMicroIconForRole then return GetMicroIconForRole(roleKey) end
		if roleKey == "TANK" then return "UI-LFG-RoleIcon-Tank-Micro-GroupFinder" end
		if roleKey == "HEALER" then return "UI-LFG-RoleIcon-Healer-Micro-GroupFinder" end
		if roleKey == "DAMAGER" then return "UI-LFG-RoleIcon-DPS-Micro-GroupFinder" end
	end
	if roleKey == "TANK" then return "roleicon-tiny-tank" end
	if roleKey == "HEALER" then return "roleicon-tiny-healer" end
	if roleKey == "DAMAGER" then return "roleicon-tiny-dps" end
	return nil
end

function GF:UpdateRoleIcon(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st) then return end
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local rc = cfg and cfg.roleIcon or {}
	if rc.enabled == false then
		if st.roleIcon then st.roleIcon:Hide() end
		return
	end
	local indicatorLayer = st.healthTextLayer or st.health or st.barGroup or st.frame
	if not st.roleIcon then st.roleIcon = indicatorLayer:CreateTexture(nil, "OVERLAY", nil, 7) end
	if st.roleIcon.GetParent and st.roleIcon:GetParent() ~= indicatorLayer then st.roleIcon:SetParent(indicatorLayer) end
	if st.roleIcon.SetDrawLayer then st.roleIcon:SetDrawLayer("OVERLAY", 7) end
	local roleKey = getUnitRoleKey(unit)
	if isEditModeActive() and st._previewRole then roleKey = st._previewRole end
	if roleKey == "NONE" and isEditModeActive() then roleKey = "DAMAGER" end
	local selection = rc.showRoles
	if type(selection) == "table" then
		if not selectionHasAny(selection) then
			st._lastRoleAtlas = nil
			st.roleIcon:Hide()
			return
		end
		if roleKey == "NONE" or not selectionContains(selection, roleKey) then
			st._lastRoleAtlas = nil
			st.roleIcon:Hide()
			return
		end
	end
	local style = rc.style or "TINY"
	local atlas = resolveRoleAtlas(roleKey, style)
	if atlas then
		if st._lastRoleAtlas ~= atlas then
			st._lastRoleAtlas = atlas
			st.roleIcon:SetAtlas(atlas, false)
		end
		st.roleIcon:Show()
	else
		st._lastRoleAtlas = nil
		st.roleIcon:Hide()
	end
end

function GF:UpdateRaidIcon(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st and st.raidIcon) then return end
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local sc = cfg and cfg.status or {}
	local rcfg = sc.raidIcon or {}
	if rcfg.enabled == false then
		st.raidIcon:Hide()
		return
	end
	if isEditModeActive() then
		if SetRaidTargetIconTexture then SetRaidTargetIconTexture(st.raidIcon, 8) end
		st.raidIcon:Show()
		return
	end
	local idx = GetRaidTargetIndex and GetRaidTargetIndex(unit)
	if idx then
		if SetRaidTargetIconTexture then SetRaidTargetIconTexture(st.raidIcon, idx) end
		st.raidIcon:Show()
	else
		st.raidIcon:Hide()
	end
end

local function getUnitRaidRole(unit)
	if not (UnitInRaid and GetRaidRosterInfo and unit) then return nil end
	local raidID = UnitInRaid(unit)
	if not raidID then return nil end
	local role = select(10, GetRaidRosterInfo(raidID))
	return role
end

function GF:UpdateGroupIcons(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (st and st.leaderIcon and st.assistIcon) then return end
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local scfg = cfg and cfg.status or {}

	-- Leader icon
	local lc = scfg.leaderIcon or {}
	if lc.enabled == false then
		st.leaderIcon:Hide()
	else
		local showLeader = unit and UnitIsGroupLeader and UnitIsGroupLeader(unit)
		if not showLeader and isEditModeActive() then showLeader = true end
		if showLeader then
			st.leaderIcon:SetAtlas("UI-HUD-UnitFrame-Player-Group-LeaderIcon", false)
			st.leaderIcon:Show()
		else
			st.leaderIcon:Hide()
		end
	end

	-- Assist icon (group assistant or MAINASSIST raid role)
	local acfg = scfg.assistIcon or {}
	if self._eqolGroupKind == "party" or acfg.enabled == false then
		st.assistIcon:Hide()
	else
		local showAssist = unit and UnitIsGroupAssistant and UnitIsGroupAssistant(unit)
		if not showAssist then
			local raidRole = getUnitRaidRole(unit)
			showAssist = raidRole == "MAINASSIST"
		end
		if not showAssist and isEditModeActive() then showAssist = true end
		if showAssist then
			st.assistIcon:SetAtlas("RaidFrame-Icon-MainAssist", false)
			st.assistIcon:Show()
		else
			st.assistIcon:Hide()
		end
	end
end

function GF:UpdateHighlightState(self)
	if not self then return end
	local st = getState(self)
	if not st then return end
	local frames = st._highlightFrames
	local hoverFrame = frames and frames.hover
	local targetFrame = frames and frames.target
	local unit = getUnit(self)
	if not unit then
		if hoverFrame then hoverFrame:Hide() end
		if targetFrame then targetFrame:Hide() end
		return
	end

	local targetCfg = st._highlightTargetCfg
	local hoverCfg = st._highlightHoverCfg
	local inEditMode = isEditModeActive()
	local previewIndex = st._previewIndex or self._eqolPreviewIndex or 0
	local isTarget = UnitIsUnit and UnitIsUnit(unit, "target")
	local showTarget = false
	if targetCfg and targetCfg.enabled then
		if inEditMode and self._eqolPreview and previewIndex > 0 then
			if hoverCfg and hoverCfg.enabled then
				showTarget = previewIndex == 2
			else
				showTarget = previewIndex == 1
			end
		else
			showTarget = isTarget
		end
	end
	if showTarget then
		if targetFrame then
			local color = targetCfg.color or { 1, 1, 1, 1 }
			targetFrame:SetBackdropBorderColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
			targetFrame:Show()
		end
	else
		if targetFrame then targetFrame:Hide() end
	end

	local showHover = false
	if hoverCfg and hoverCfg.enabled then
		if inEditMode and self._eqolPreview and previewIndex > 0 then
			showHover = previewIndex == 1
		else
			showHover = st._hovered
		end
	end
	if showHover then
		if hoverFrame then
			local color = hoverCfg.color or { 1, 1, 1, 1 }
			hoverFrame:SetBackdropBorderColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
			hoverFrame:Show()
		end
	else
		if hoverFrame then hoverFrame:Hide() end
	end
end

local function externalAuraPredicate(aura, unit)
	if not aura then return false end
	if not (C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID and unit and aura.auraInstanceID) then return false end
	if C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, aura.auraInstanceID, AURA_FILTER_BIG_DEFENSIVE) then return false end
	if issecretvalue and (issecretvalue(aura.sourceUnit) or issecretvalue(unit)) then return true end
	if type(aura.sourceUnit) ~= "string" or type(unit) ~= "string" then return true end
	return aura.sourceUnit ~= unit
end

local AURA_TYPE_META = {
	buff = {
		containerKey = "buffContainer",
		buttonsKey = "buffButtons",
		filter = "HELPFUL",
		isDebuff = false,
	},
	debuff = {
		containerKey = "debuffContainer",
		buttonsKey = "debuffButtons",
		filter = "HARMFUL",
		isDebuff = true,
	},
	externals = {
		containerKey = "externalContainer",
		buttonsKey = "externalButtons",
		filter = "HELPFUL",
		isDebuff = false,
		predicate = externalAuraPredicate,
	},
}

local function getAuraCache(st, key)
	if not st then return nil end
	if key then
		st._auraCacheByKey = st._auraCacheByKey or {}
		local cache = st._auraCacheByKey[key]
		if not cache then
			cache = { auras = {}, order = {}, indexById = {} }
			st._auraCacheByKey[key] = cache
		end
		return cache
	end
	local cache = st._auraCache
	if not cache then
		cache = { auras = {}, order = {}, indexById = {} }
		st._auraCache = cache
	end
	return cache
end

local function resetAuraCache(cache)
	if not cache then return end
	local auras, order, indexById = cache.auras, cache.order, cache.indexById
	for k in pairs(auras) do
		auras[k] = nil
	end
	for i = #order, 1, -1 do
		order[i] = nil
	end
	for k in pairs(indexById) do
		indexById[k] = nil
	end
end

local function isAuraHelpful(unit, aura, helpfulFilter)
	if not (C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID and unit and aura and aura.auraInstanceID and helpfulFilter) then return false end
	return not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, aura.auraInstanceID, helpfulFilter)
end

local function isAuraHarmful(unit, aura, harmfulFilter)
	if not (C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID and unit and aura and aura.auraInstanceID and harmfulFilter) then return false end
	return not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, aura.auraInstanceID, harmfulFilter)
end

local SAMPLE_BUFF_ICONS = { 136243, 135940, 136085, 136097, 136116, 136048, 135932, 136108 }
local SAMPLE_DEBUFF_ICONS = { 136207, 136160, 136128, 135804, 136168, 132104, 136118, 136214 }
local SAMPLE_EXTERNAL_ICONS = { 135936, 136073, 135907, 135940, 136090, 135978 }
local SAMPLE_DISPEL_TYPES = { "Magic", "Curse", "Disease", "Poison" }

local function getSampleAuraData(kindKey, index, now)
	local duration
	if index % 3 == 0 then
		duration = 120
	elseif index % 3 == 1 then
		duration = 30
	else
		duration = 0
	end
	local expiration = duration > 0 and (now + duration) or nil
	local stacks
	if index % 5 == 0 then
		stacks = 5
	elseif index % 3 == 0 then
		stacks = 3
	end
	local iconList = SAMPLE_BUFF_ICONS
	if kindKey == "debuff" then
		iconList = SAMPLE_DEBUFF_ICONS
	elseif kindKey == "externals" then
		iconList = SAMPLE_EXTERNAL_ICONS
	end
	local icon = iconList[((index - 1) % #iconList) + 1]
	local dispelName = kindKey == "debuff" and SAMPLE_DISPEL_TYPES[((index - 1) % #SAMPLE_DISPEL_TYPES) + 1] or nil
	local canActivePlayerDispel = dispelName == "Magic"
	local base = (kindKey == "buff" and -100000) or (kindKey == "debuff" and -200000) or -300000
	local auraId = base - index
	local points
	if kindKey == "externals" then points = { 20 + ((index - 1) % 3) * 10 } end
	return {
		auraInstanceID = auraId,
		icon = icon,
		isHelpful = kindKey ~= "debuff",
		isHarmful = kindKey == "debuff",
		applications = stacks,
		duration = duration,
		expirationTime = expiration,
		dispelName = dispelName,
		canActivePlayerDispel = canActivePlayerDispel,
		points = points,
		isSample = true,
	}
end

local function getSampleStyle(st, kindKey, style)
	st._auraSampleStyle = st._auraSampleStyle or {}
	local sample = st._auraSampleStyle[kindKey]
	if not sample or sample._src ~= style then
		sample = {}
		sample._src = style
		st._auraSampleStyle[kindKey] = sample
	else
		for key in pairs(sample) do
			if key ~= "_src" and key ~= "showTooltip" then sample[key] = nil end
		end
	end
	for key, value in pairs(style or {}) do
		sample[key] = value
	end
	sample.showTooltip = false
	st._auraSampleStyle[kindKey] = sample
	return sample
end

function GF:LayoutAuras(self)
	local st = getState(self)
	if not st then return end
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local ac = cfg and cfg.auras
	if not ac then return end
	syncAurasEnabled(cfg)
	local wantsAuras = (ac.buff and ac.buff.enabled) or (ac.debuff and ac.debuff.enabled) or (ac.externals and ac.externals.enabled)
	if not wantsAuras then return end

	dprint(
		"LayoutAuras",
		getUnit(self) or "nil",
		"buff",
		tostring(ac.buff and ac.buff.enabled),
		"debuff",
		tostring(ac.debuff and ac.debuff.enabled),
		"externals",
		tostring(ac.externals and ac.externals.enabled)
	)

	st._auraLayout = st._auraLayout or {}
	st._auraLayoutKey = st._auraLayoutKey or {}
	st._auraStyle = st._auraStyle or {}

	local parent = st.barGroup or st.frame

	for kindKey, meta in pairs(AURA_TYPE_META) do
		local typeCfg = ac[kindKey] or {}
		if typeCfg.enabled == false then
			local container = st[meta.containerKey]
			if container then container:Hide() end
			hideAuraButtons(st[meta.buttonsKey], 1)
			st._auraLayout[kindKey] = nil
			st._auraLayoutKey[kindKey] = nil
		else
			local anchorPoint, primary, secondary = resolveAuraGrowth(typeCfg.anchorPoint, typeCfg.growth, typeCfg.growthX, typeCfg.growthY)
			local size = tonumber(typeCfg.size) or 16
			local spacing = tonumber(typeCfg.spacing) or 2
			local perRow = tonumber(typeCfg.perRow) or tonumber(typeCfg.max) or 6
			if perRow < 1 then perRow = 1 end
			local maxCount = tonumber(typeCfg.max) or perRow
			if maxCount < 0 then maxCount = 0 end
			local x = tonumber(typeCfg.x) or 0
			local y = tonumber(typeCfg.y) or 0

			local key = anchorPoint .. "|" .. tostring(primary) .. "|" .. tostring(secondary) .. "|" .. size .. "|" .. spacing .. "|" .. perRow .. "|" .. maxCount .. "|" .. x .. "|" .. y
			local layout = st._auraLayout[kindKey] or {}
			layout.anchorPoint = anchorPoint
			layout.primary = primary
			layout.secondary = secondary
			layout.size = size
			layout.spacing = spacing
			layout.perRow = perRow
			layout.maxCount = maxCount
			layout.x = x
			layout.y = y
			layout.key = key
			st._auraLayout[kindKey] = layout

			if st._auraLayoutKey[kindKey] ~= key then
				st._auraLayoutKey[kindKey] = key
				local container = ensureAuraContainer(st, meta.containerKey)
				if container then
					container:ClearAllPoints()
					container:SetPoint(anchorPoint, parent, anchorPoint, x, y)
					local primaryVertical = primary == "UP" or primary == "DOWN"
					local rows, cols
					if primaryVertical then
						rows = math.min(maxCount, perRow)
						cols = (perRow > 0) and math.ceil(maxCount / perRow) or 1
					else
						rows = (perRow > 0) and math.ceil(maxCount / perRow) or 1
						cols = math.min(maxCount, perRow)
					end
					if rows < 1 then rows = 1 end
					if cols < 1 then cols = 1 end
					local w = cols * size + spacing * max(0, cols - 1)
					local h = rows * size + spacing * max(0, rows - 1)
					container:SetSize(w > 0 and w or 0.001, h > 0 and h or 0.001)
					if container.SetClipsChildren then container:SetClipsChildren(false) end
				end
				local buttons = st[meta.buttonsKey]
				if buttons and container then
					for i, btn in ipairs(buttons) do
						if btn.SetSize then btn:SetSize(size, size) end
						positionAuraButton(btn, container, primary, secondary, i, perRow, size, spacing)
						btn._auraLayoutKey = key
					end
				end
			end

			local style = st._auraStyle[kindKey] or {}
			style.size = size
			style.padding = spacing
			style.showTooltip = typeCfg.showTooltip ~= false
			style.showCooldown = typeCfg.showCooldown ~= false
			style.countFont = typeCfg.countFont
			style.countFontSize = typeCfg.countFontSize
			style.countFontOutline = typeCfg.countFontOutline
			style.cooldownFontSize = typeCfg.cooldownFontSize
			style.showDR = typeCfg.showDR == true
			style.drAnchor = typeCfg.drAnchor
			style.drOffset = typeCfg.drOffset
			style.drFont = typeCfg.drFont
			style.drFontSize = typeCfg.drFontSize
			style.drFontOutline = typeCfg.drFontOutline
			style.drColor = typeCfg.drColor
			st._auraStyle[kindKey] = style
		end
	end
end

local function updateAuraType(self, unit, st, ac, kindKey, cache, helpfulFilter, harmfulFilter)
	local meta = AURA_TYPE_META[kindKey]
	if not meta then return end
	local typeCfg = ac and ac[kindKey] or {}
	if typeCfg.enabled == false then
		local container = st[meta.containerKey]
		if container then container:Hide() end
		hideAuraButtons(st[meta.buttonsKey], 1)
		return
	end

	local layout = st._auraLayout and st._auraLayout[kindKey]
	local style = st._auraStyle and st._auraStyle[kindKey]
	if not (layout and style) then return end

	local container = ensureAuraContainer(st, meta.containerKey)
	if not container then return end
	container:Show()

	local buttons = st[meta.buttonsKey]
	if not buttons then
		buttons = {}
		st[meta.buttonsKey] = buttons
	end
	if not cache then
		hideAuraButtons(buttons, 1)
		return
	end
	local auras = cache.auras
	local order = cache.order
	if not (auras and order) then
		hideAuraButtons(buttons, 1)
		return
	end
	local shown = 0
	local maxCount = layout.maxCount or 0
	for i = 1, #order do
		if shown >= maxCount then break end
		local auraId = order[i]
		local aura = auraId and auras[auraId]
		if aura then
			local isHelpful = isAuraHelpful(unit, aura, helpfulFilter)
			local isHarmful = isAuraHarmful(unit, aura, harmfulFilter)
			local isExternal = false
			if isHelpful and ac and ac.externals and ac.externals.enabled ~= false then isExternal = (not AURA_TYPE_META.externals.predicate or AURA_TYPE_META.externals.predicate(aura, unit)) end
			local match = false
			if kindKey == "debuff" then
				match = isHarmful
			elseif kindKey == "buff" then
				match = isHelpful and not isExternal
			elseif kindKey == "externals" then
				match = isExternal
			end
			if match then
				shown = shown + 1
				local btn = AuraUtil.ensureAuraButton(container, buttons, shown, style)
				AuraUtil.applyAuraToButton(btn, aura, style, meta.isDebuff, unit)
				if btn._auraLayoutKey ~= layout.key then
					positionAuraButton(btn, container, layout.primary, layout.secondary, shown, layout.perRow, layout.size, layout.spacing)
					btn._auraLayoutKey = layout.key
				end
				btn:Show()
			end
		end
	end
	if kindKey == "externals" and layout.anchorPoint == "CENTER" and container then
		local w, h = calcAuraGridSize(shown, layout.perRow, layout.size, layout.spacing, layout.primary)
		if container._eqolAuraCenterW ~= w or container._eqolAuraCenterH ~= h then
			container:SetSize(w, h)
			container._eqolAuraCenterW = w
			container._eqolAuraCenterH = h
		end
	end
	hideAuraButtons(buttons, shown + 1)
end

local function fullScanGroupAuras(unit, cache, helpfulFilter, harmfulFilter)
	if not (unit and cache and C_UnitAuras) then return end
	resetAuraCache(cache)
	local auras = cache.auras
	local function storeAura(aura)
		if aura and aura.auraInstanceID then
			if AuraUtil and AuraUtil.cacheAura then
				AuraUtil.cacheAura(cache, aura)
			else
				auras[aura.auraInstanceID] = aura
			end
			if AuraUtil and AuraUtil.addAuraToOrder then
				AuraUtil.addAuraToOrder(cache, aura.auraInstanceID)
			else
				cache.order[#cache.order + 1] = aura.auraInstanceID
				cache.indexById[aura.auraInstanceID] = #cache.order
			end
		end
	end
	if C_UnitAuras.GetUnitAuras then
		if helpfulFilter then
			local helpful = C_UnitAuras.GetUnitAuras(unit, helpfulFilter)
			for i = 1, (helpful and #helpful or 0) do
				storeAura(helpful[i])
			end
		end
		if harmfulFilter then
			local harmful = C_UnitAuras.GetUnitAuras(unit, harmfulFilter)
			for i = 1, (harmful and #harmful or 0) do
				storeAura(harmful[i])
			end
		end
	elseif C_UnitAuras.GetAuraSlots then
		if helpfulFilter then
			local helpful = { C_UnitAuras.GetAuraSlots(unit, helpfulFilter) }
			for i = 2, #helpful do
				local aura = C_UnitAuras.GetAuraDataBySlot(unit, helpful[i])
				storeAura(aura)
			end
		end
		if harmfulFilter then
			local harmful = { C_UnitAuras.GetAuraSlots(unit, harmfulFilter) }
			for i = 2, #harmful do
				local aura = C_UnitAuras.GetAuraDataBySlot(unit, harmful[i])
				storeAura(aura)
			end
		end
	end
end

local function updateGroupAuraCache(unit, st, updateInfo, ac, helpfulFilter, harmfulFilter)
	if not (unit and st and updateInfo and AuraUtil and AuraUtil.updateAuraCacheFromEvent) then return end
	local cache = getAuraCache(st)
	local externalCache = getAuraCache(st, "externals")
	local externalCache = getAuraCache(st, "externals")
	if not cache then return end
	local wantsHelpful = ac and (ac.buff and ac.buff.enabled ~= false) or false
	local wantsHarmful = ac and (ac.debuff and ac.debuff.enabled ~= false) or false
	local wantsExternals = ac and (ac.externals and ac.externals.enabled ~= false) or false
	dprint(
		"AuraCache:update",
		unit,
		"added",
		type(updateInfo.addedAuras) == "table" and #updateInfo.addedAuras or 0,
		"updated",
		type(updateInfo.updatedAuras) == "table" and #updateInfo.updatedAuras or 0,
		"updatedIds",
		type(updateInfo.updatedAuraInstanceIDs) == "table" and #updateInfo.updatedAuraInstanceIDs or 0,
		"removed",
		type(updateInfo.removedAuraInstanceIDs) == "table" and #updateInfo.removedAuraInstanceIDs or 0
	)
	AuraUtil.updateAuraCacheFromEvent(cache, unit, updateInfo, {
		showHelpful = wantsHelpful,
		showHarmful = wantsHarmful,
		helpfulFilter = helpfulFilter,
		harmfulFilter = harmfulFilter,
	})
	if wantsExternals then
		if externalCache then AuraUtil.updateAuraCacheFromEvent(externalCache, unit, updateInfo, {
			showHelpful = true,
			showHarmful = false,
			helpfulFilter = AURA_FILTER_BIG_DEFENSIVE,
		}) end
	end
end

function GF:UpdateAuras(self, updateInfo)
	local st = getState(self)
	if not (st and AuraUtil) then return end
	local unit = getUnit(self)
	local inEditMode = isEditModeActive()
	if inEditMode or self._eqolPreview then
		dprint("UpdateAuras", unit or "nil", "editmode", tostring(inEditMode), "preview", tostring(self._eqolPreview))
		GF:UpdateSampleAuras(self)
		return
	end
	if not (unit and C_UnitAuras) then return end
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local ac = cfg and cfg.auras or {}
	if cfg then syncAurasEnabled(cfg) end
	local wantsAuras = st._wantsAuras
	if wantsAuras == nil then wantsAuras = ((ac.buff and ac.buff.enabled) or (ac.debuff and ac.debuff.enabled) or (ac.externals and ac.externals.enabled)) or false end
	dprint("UpdateAuras", unit, "wants", tostring(wantsAuras), "enabled", tostring(ac.enabled))
	if wantsAuras == false then
		if st.buffContainer then st.buffContainer:Hide() end
		if st.debuffContainer then st.debuffContainer:Hide() end
		if st.externalContainer then st.externalContainer:Hide() end
		hideAuraButtons(st.buffButtons, 1)
		hideAuraButtons(st.debuffButtons, 1)
		hideAuraButtons(st.externalButtons, 1)
		return
	end

	st._auraSampleActive = nil

	local wantBuff = ac.buff and ac.buff.enabled ~= false
	local wantDebuff = ac.debuff and ac.debuff.enabled ~= false
	local wantExternals = ac.externals and ac.externals.enabled ~= false
	if
		not st._auraLayout
		or (wantBuff and not (st._auraLayout.buff and st._auraLayout.buff.key))
		or (wantDebuff and not (st._auraLayout.debuff and st._auraLayout.debuff.key))
		or (wantExternals and not (st._auraLayout.externals and st._auraLayout.externals.key))
	then
		GF:LayoutAuras(self)
	end
	local helpfulFilter = AURA_FILTER_HELPFUL
	local harmfulFilter = (unit == "player") and AURA_FILTER_HARMFUL_ALL or AURA_FILTER_HARMFUL
	local externalFilter = AURA_FILTER_BIG_DEFENSIVE
	local cache = getAuraCache(st)
	if not updateInfo or updateInfo.isFullUpdate then
		dprint("UpdateAuras", unit, "fullScan", true, "filters", helpfulFilter or "nil", harmfulFilter or "nil")
		fullScanGroupAuras(unit, cache, (wantBuff and helpfulFilter) or nil, (wantDebuff and harmfulFilter) or nil)
		if wantExternals and externalCache then
			fullScanGroupAuras(unit, externalCache, externalFilter, nil)
		elseif externalCache then
			resetAuraCache(externalCache)
		end
		dprint("AuraCache:full", unit, "count", cache and cache.order and #cache.order or 0)
		updateAuraType(self, unit, st, ac, "buff", cache, helpfulFilter, harmfulFilter)
		updateAuraType(self, unit, st, ac, "debuff", cache, helpfulFilter, harmfulFilter)
		updateAuraType(self, unit, st, ac, "externals", externalCache or cache, externalFilter, harmfulFilter)
		return
	end

	updateGroupAuraCache(unit, st, updateInfo, ac, helpfulFilter, harmfulFilter)
	dprint("UpdateAuras", unit, "partial", true)
	updateAuraType(self, unit, st, ac, "buff", cache, helpfulFilter, harmfulFilter)
	updateAuraType(self, unit, st, ac, "debuff", cache, helpfulFilter, harmfulFilter)
	updateAuraType(self, unit, st, ac, "externals", externalCache or cache, externalFilter, harmfulFilter)
end

function GF:UpdateSampleAuras(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (st and AuraUtil) then return end
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local ac = cfg and cfg.auras or {}
	if cfg then syncAurasEnabled(cfg) end
	local wantsAuras = ((ac.buff and ac.buff.enabled) or (ac.debuff and ac.debuff.enabled) or (ac.externals and ac.externals.enabled)) or false
	if ac.enabled == true then wantsAuras = true end
	st._wantsAuras = wantsAuras
	dprint("SampleAuras", unit or "nil", "wants", tostring(wantsAuras), "enabled", tostring(ac.enabled))
	if wantsAuras == false then
		if st.buffContainer then st.buffContainer:Hide() end
		if st.debuffContainer then st.debuffContainer:Hide() end
		if st.externalContainer then st.externalContainer:Hide() end
		hideAuraButtons(st.buffButtons, 1)
		hideAuraButtons(st.debuffButtons, 1)
		hideAuraButtons(st.externalButtons, 1)
		st._auraSampleActive = nil
		return
	end

	local wantBuff = ac.buff and ac.buff.enabled ~= false
	local wantDebuff = ac.debuff and ac.debuff.enabled ~= false
	local wantExternals = ac.externals and ac.externals.enabled ~= false
	if
		not st._auraLayout
		or (wantBuff and not (st._auraLayout.buff and st._auraLayout.buff.key))
		or (wantDebuff and not (st._auraLayout.debuff and st._auraLayout.debuff.key))
		or (wantExternals and not (st._auraLayout.externals and st._auraLayout.externals.key))
	then
		GF:LayoutAuras(self)
	end

	local function updateSampleType(kindKey)
		local meta = AURA_TYPE_META[kindKey]
		if not meta then return end
		local typeCfg = ac and ac[kindKey] or {}
		if typeCfg.enabled == false then
			local container = st[meta.containerKey]
			if container then container:Hide() end
			hideAuraButtons(st[meta.buttonsKey], 1)
			return
		end

		local layout = st._auraLayout and st._auraLayout[kindKey]
		local style = st._auraStyle and st._auraStyle[kindKey]
		if not (layout and style) then return end

		local container = ensureAuraContainer(st, meta.containerKey)
		if not container then return end
		container:Show()
		if GF and GF._debugAuras then
			local p1, rel, rp, ox, oy = container:GetPoint(1)
			dprint(
				"SampleAuras:container",
				kindKey,
				"shown",
				tostring(container:IsShown()),
				"alpha",
				tostring(container:GetAlpha()),
				"size",
				tostring(container:GetWidth()),
				tostring(container:GetHeight()),
				"point",
				tostring(p1),
				rel and rel.GetName and rel:GetName() or tostring(rel),
				tostring(rp),
				tostring(ox),
				tostring(oy)
			)
		end

		local buttons = st[meta.buttonsKey]
		if not buttons then
			buttons = {}
			st[meta.buttonsKey] = buttons
		end

		local iconList = SAMPLE_BUFF_ICONS
		if kindKey == "debuff" then
			iconList = SAMPLE_DEBUFF_ICONS
		elseif kindKey == "externals" then
			iconList = SAMPLE_EXTERNAL_ICONS
		end
		local maxCount = layout.maxCount or 0
		local shown = math.min(maxCount, #iconList)
		local now = GetTime and GetTime() or 0
		local sampleStyle = getSampleStyle(st, kindKey, style)
		local unitToken = unit or "player"
		for i = 1, shown do
			local aura = getSampleAuraData(kindKey, i, now)
			local btn = AuraUtil.ensureAuraButton(container, buttons, i, sampleStyle)
			AuraUtil.applyAuraToButton(btn, aura, sampleStyle, meta.isDebuff, unitToken)
			if btn._auraLayoutKey ~= layout.key then
				positionAuraButton(btn, container, layout.primary, layout.secondary, i, layout.perRow, layout.size, layout.spacing)
				btn._auraLayoutKey = layout.key
			end
			btn:Show()
			if GF and GF._debugAuras and i == 1 then
				local bpt, brel, brp, bx, by = btn:GetPoint(1)
				local tex = btn.icon and btn.icon.GetTexture and btn.icon:GetTexture()
				dprint(
					"SampleAuras:btn",
					kindKey,
					"size",
					tostring(btn:GetWidth()),
					tostring(btn:GetHeight()),
					"shown",
					tostring(btn:IsShown()),
					"alpha",
					tostring(btn:GetAlpha()),
					"icon",
					tostring(tex),
					"point",
					tostring(bpt),
					brel and brel.GetName and brel:GetName() or tostring(brel),
					tostring(brp),
					tostring(bx),
					tostring(by)
				)
			end
		end
		if kindKey == "externals" and layout.anchorPoint == "CENTER" and container then
			local w, h = calcAuraGridSize(shown, layout.perRow, layout.size, layout.spacing, layout.primary)
			if container._eqolAuraCenterW ~= w or container._eqolAuraCenterH ~= h then
				container:SetSize(w, h)
				container._eqolAuraCenterW = w
				container._eqolAuraCenterH = h
			end
		end
		hideAuraButtons(buttons, shown + 1)
	end

	updateSampleType("buff")
	updateSampleType("debuff")
	updateSampleType("externals")
	st._auraSampleActive = true
end

function GF:UpdateName(self)
	local unit = getUnit(self)
	local st = getState(self)
	local fs = st and (st.nameText or st.name)
	if not (unit and st and fs) then return end
	if st._wantsName == false then
		if fs.SetText then fs:SetText("") end
		if fs.SetShown then fs:SetShown(false) end
		st._lastName = nil
		return
	end
	if fs.SetShown then fs:SetShown(true) end
	if UnitExists and not UnitExists(unit) then
		fs:SetText("")
		st._lastName = nil
		return
	end
	local name = UnitName and UnitName(unit) or ""
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local tc = cfg and cfg.text or {}
	local sc = cfg and cfg.status or {}
	if UnitIsConnected and not UnitIsConnected(unit) then name = (name and name ~= "") and (name .. " |cffff6666DC|r") or "|cffff6666DC|r" end
	name = name or ""
	if st._lastName ~= name then
		fs:SetText(name)
		st._lastName = name
	end

	-- Name coloring (simple: class color for players, grey if offline)
	local r, g, b, a = 1, 1, 1, 1
	local nameMode = sc.nameColorMode
	if nameMode == nil then nameMode = (tc.useClassColor ~= false) and "CLASS" or "CUSTOM" end
	if nameMode == "CUSTOM" then
		r, g, b, a = unpackColor(sc.nameColor, { 1, 1, 1, 1 })
	elseif nameMode == "CLASS" and st._classR then
		r, g, b, a = st._classR, st._classG, st._classB, st._classA or 1
	end
	if UnitIsConnected and not UnitIsConnected(unit) then
		r, g, b, a = 0.7, 0.7, 0.7, 1
	end
	if st._lastNameR ~= r or st._lastNameG ~= g or st._lastNameB ~= b or st._lastNameA ~= a then
		st._lastNameR, st._lastNameG, st._lastNameB, st._lastNameA = r, g, b, a
		if fs.SetTextColor then fs:SetTextColor(r, g, b, a) end
	end
end

local function shouldShowLevel(scfg, unit)
	if not scfg or scfg.levelEnabled == false then return false end
	if scfg.hideLevelAtMax and addon.variables and addon.variables.isMaxLevel and UnitLevel then
		local level = UnitLevel(unit)
		if issecretvalue and issecretvalue(level) then return true end
		level = tonumber(level) or 0
		if level > 0 and addon.variables.isMaxLevel[level] then return false end
	end
	return true
end

function GF:UpdateLevel(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (st and st.levelText) then return end
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local scfg = cfg and cfg.status or {}
	local enabled = scfg.levelEnabled ~= false
	local show = enabled and unit and shouldShowLevel(scfg, unit)
	if not show and isEditModeActive() and enabled then show = true end
	st.levelText:SetShown(show)
	if not show then return end

	local levelText = "??"
	if unit and UnitExists and UnitExists(unit) then
		levelText = getSafeLevelText(unit, false)
	elseif isEditModeActive() then
		levelText = tostring(scfg.sampleLevel or 60)
	end
	st.levelText:SetText(levelText)

	local r, g, b, a = 1, 0.85, 0, 1
	if scfg.levelColorMode == "CUSTOM" then
		r, g, b, a = unpackColor(scfg.levelColor, { 1, 0.85, 0, 1 })
	elseif scfg.levelColorMode == "CLASS" and st._classR then
		r, g, b, a = st._classR, st._classG, st._classB, st._classA or 1
	end
	if st._lastLevelR ~= r or st._lastLevelG ~= g or st._lastLevelB ~= b or st._lastLevelA ~= a then
		st._lastLevelR, st._lastLevelG, st._lastLevelB, st._lastLevelA = r, g, b, a
		st.levelText:SetTextColor(r, g, b, a)
	end
end

function GF:UpdateHealthValue(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st and st.health) then return end
	if UnitExists and not UnitExists(unit) then
		st.health:SetMinMaxValues(0, 1)
		st.health:SetValue(0)
		if st.absorb then st.absorb:Hide() end
		if st.healAbsorb then st.healAbsorb:Hide() end
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
			st._lastHealthPx = nil
			st._lastHealthBarW = nil
		end
		local w = st.health:GetWidth()
		if w and w > 0 and maxForValue > 0 then
			local px = floor((cur * w) / maxForValue + 0.5)
			if st._lastHealthPx ~= px or st._lastHealthBarW ~= w then
				st._lastHealthPx = px
				st._lastHealthBarW = w
				st.health:SetValue((px / w) * maxForValue)
				st._lastHealthCur = cur
			end
		else
			if st._lastHealthCur ~= cur then
				st.health:SetValue(cur)
				st._lastHealthCur = cur
			end
		end
	end

	-- Absorb overlays
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local hc = cfg and cfg.health or {}
	local kind = self._eqolGroupKind or "party"
	local defH = (DEFAULTS[kind] and DEFAULTS[kind].health) or {}
	local absorbEnabled = hc.absorbEnabled ~= false
	local healAbsorbEnabled = hc.healAbsorbEnabled ~= false
	local curSecret = issecretvalue and issecretvalue(cur)
	local inEditMode = isEditModeActive()
	local sampleAbsorb = inEditMode and hc.showSampleAbsorb == true
	local sampleHealAbsorb = inEditMode and hc.showSampleHealAbsorb == true
	local maxIsSecret = issecretvalue and issecretvalue(maxForValue)
	local sampleMax = maxForValue
	if (sampleAbsorb or sampleHealAbsorb) and maxIsSecret then sampleMax = EDIT_MODE_SAMPLE_MAX end
	if absorbEnabled and st.absorb then
		local abs = st._absorbAmount
		if abs == nil then abs = 0 end
		local absSecret = issecretvalue and issecretvalue(abs)
		local absValue = abs
		if sampleAbsorb then
			local useSample = false
			if absSecret then
				useSample = true
			else
				absValue = tonumber(abs) or 0
				if absValue <= 0 then useSample = true end
			end
			if useSample then
				absValue = (sampleMax or 1) * 0.6
				absSecret = false
			end
		else
			if not absSecret then absValue = tonumber(abs) or 0 end
		end
		st.absorb:SetMinMaxValues(0, (sampleAbsorb and sampleMax) or maxForValue or 1)
		st.absorb:SetValue(absValue or 0)
		if absSecret then
			st.absorb:Show()
		elseif absValue and absValue > 0 then
			st.absorb:Show()
		else
			st.absorb:Hide()
		end
		local ar, ag, ab, aa
		if UFHelper and UFHelper.getAbsorbColor then
			ar, ag, ab, aa = UFHelper.getAbsorbColor(hc, defH)
		else
			ar, ag, ab, aa = 0.85, 0.95, 1, 0.7
		end
		if st._lastAbsorbR ~= ar or st._lastAbsorbG ~= ag or st._lastAbsorbB ~= ab or st._lastAbsorbA ~= aa then
			st._lastAbsorbR, st._lastAbsorbG, st._lastAbsorbB, st._lastAbsorbA = ar, ag, ab, aa
			st.absorb:SetStatusBarColor(ar or 0.85, ag or 0.95, ab or 1, aa or 0.7)
		end
	elseif st.absorb then
		st.absorb:Hide()
	end

	if healAbsorbEnabled and st.healAbsorb then
		local healAbs = st._healAbsorbAmount
		if healAbs == nil then healAbs = 0 end
		local healSecret = issecretvalue and issecretvalue(healAbs)
		local healValue = healAbs
		if sampleHealAbsorb then
			local useSample = false
			if healSecret then
				useSample = true
			else
				healValue = tonumber(healAbs) or 0
				if healValue <= 0 then useSample = true end
			end
			if useSample then
				healValue = (sampleMax or 1) * 0.35
				healSecret = false
			end
		else
			if not healSecret then healValue = tonumber(healAbs) or 0 end
		end
		st.healAbsorb:SetMinMaxValues(0, (sampleHealAbsorb and sampleMax) or maxForValue or 1)
		if not healSecret and not curSecret then
			if (cur or 0) < (healValue or 0) then healValue = cur or 0 end
		end
		st.healAbsorb:SetValue(healValue or 0)
		if healSecret then
			st.healAbsorb:Show()
		elseif healValue and healValue > 0 then
			st.healAbsorb:Show()
		else
			st.healAbsorb:Hide()
		end
		local har, hag, hab, haa
		if UFHelper and UFHelper.getHealAbsorbColor then
			har, hag, hab, haa = UFHelper.getHealAbsorbColor(hc, defH)
		else
			har, hag, hab, haa = 1, 0.3, 0.3, 0.7
		end
		if st._lastHealAbsorbR ~= har or st._lastHealAbsorbG ~= hag or st._lastHealAbsorbB ~= hab or st._lastHealAbsorbA ~= haa then
			st._lastHealAbsorbR, st._lastHealAbsorbG, st._lastHealAbsorbB, st._lastHealAbsorbA = har, hag, hab, haa
			st.healAbsorb:SetStatusBarColor(har or 1, hag or 0.3, hab or 0.3, haa or 0.7)
		end
	elseif st.healAbsorb then
		st.healAbsorb:Hide()
	end

	-- Health text slots (UF-like formatting, secret-safe)
	local leftMode = (hc.textLeft ~= nil) and hc.textLeft or defH.textLeft or "NONE"
	local centerMode = (hc.textCenter ~= nil) and hc.textCenter or defH.textCenter or "NONE"
	local rightMode = (hc.textRight ~= nil) and hc.textRight or defH.textRight or "NONE"
	local hasText = (leftMode ~= "NONE") or (centerMode ~= "NONE") or (rightMode ~= "NONE")
	if hasText and (st.healthTextLeft or st.healthTextCenter or st.healthTextRight) then
		local allowSecretText = secretHealth and addon.variables and addon.variables.isMidnight
		if secretHealth and not allowSecretText then
			if st.healthTextLeft then st.healthTextLeft:SetText("") end
			if st.healthTextCenter then st.healthTextCenter:SetText("") end
			if st.healthTextRight then st.healthTextRight:SetText("") end
			st._lastHealthTextLeft, st._lastHealthTextCenter, st._lastHealthTextRight = nil, nil, nil
		else
			local delimiter = (UFHelper and UFHelper.getTextDelimiter and UFHelper.getTextDelimiter(hc, defH)) or (hc.textDelimiter or defH.textDelimiter or " ")
			local delimiter2 = (UFHelper and UFHelper.getTextDelimiterSecondary and UFHelper.getTextDelimiterSecondary(hc, defH, delimiter))
				or (hc.textDelimiterSecondary or defH.textDelimiterSecondary or delimiter)
			local delimiter3 = (UFHelper and UFHelper.getTextDelimiterTertiary and UFHelper.getTextDelimiterTertiary(hc, defH, delimiter, delimiter2))
				or (hc.textDelimiterTertiary or defH.textDelimiterTertiary or delimiter2)
			local useShort = hc.useShortNumbers ~= false
			local hidePercentSymbol = hc.hidePercentSymbol == true
			local percentVal
			if textModeUsesPercent(leftMode) or textModeUsesPercent(centerMode) or textModeUsesPercent(rightMode) then
				if addon.variables and addon.variables.isMidnight then
					percentVal = getHealthPercent(unit, cur, maxv)
				elseif not secretHealth then
					percentVal = getHealthPercent(unit, cur, maxv)
				end
			end
			local levelText
			if UFHelper and UFHelper.textModeUsesLevel then
				if UFHelper.textModeUsesLevel(leftMode) or UFHelper.textModeUsesLevel(centerMode) or UFHelper.textModeUsesLevel(rightMode) then levelText = getSafeLevelText(unit, false) end
			end
			setTextSlot(st, st.healthTextLeft, "_lastHealthTextLeft", leftMode, cur, maxv, useShort, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText)
			setTextSlot(st, st.healthTextCenter, "_lastHealthTextCenter", centerMode, cur, maxv, useShort, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText)
			setTextSlot(st, st.healthTextRight, "_lastHealthTextRight", rightMode, cur, maxv, useShort, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText)
		end
	elseif st.healthTextLeft or st.healthTextCenter or st.healthTextRight then
		if st.healthTextLeft then st.healthTextLeft:SetText("") end
		if st.healthTextCenter then st.healthTextCenter:SetText("") end
		if st.healthTextRight then st.healthTextRight:SetText("") end
		st._lastHealthTextLeft, st._lastHealthTextCenter, st._lastHealthTextRight = nil, nil, nil
	end
end

function GF:UpdateHealthStyle(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st and st.health) then return end
	if UnitExists and not UnitExists(unit) then return end

	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local hc = cfg and cfg.health or {}
	local kind = self._eqolGroupKind or "party"
	local defH = (DEFAULTS[kind] and DEFAULTS[kind].health) or {}

	local healthTexKey = getEffectiveBarTexture(cfg, hc)
	if st.health.SetStatusBarTexture and UFHelper and UFHelper.resolveTexture then
		if st._lastHealthTexture ~= healthTexKey then
			st.health:SetStatusBarTexture(UFHelper.resolveTexture(healthTexKey))
			if UFHelper.configureSpecialTexture then UFHelper.configureSpecialTexture(st.health, "HEALTH", healthTexKey, hc) end
			st._lastHealthTexture = healthTexKey
			stabilizeStatusBarTexture(st.health)
		end
	end

	if st.health and st.health.SetStatusBarDesaturated then
		if st._lastHealthDesat ~= true then
			st._lastHealthDesat = true
			st.health:SetStatusBarDesaturated(true)
		end
	end

	local r, g, b, a
	local useCustom = hc.useCustomColor == true
	if useCustom then
		r, g, b, a = unpackColor(hc.color, defH.color or { 0, 0.8, 0, 1 })
	elseif hc.useClassColor == true and st._classR then
		r, g, b, a = st._classR, st._classG, st._classB, st._classA or 1
	else
		r, g, b, a = unpackColor(hc.color, defH.color or { 0, 0.8, 0, 1 })
	end

	if UnitIsConnected and not UnitIsConnected(unit) then
		r, g, b, a = 0.5, 0.5, 0.5, 1
	end
	if st._lastHealthR ~= r or st._lastHealthG ~= g or st._lastHealthB ~= b or st._lastHealthA ~= a then
		st._lastHealthR, st._lastHealthG, st._lastHealthB, st._lastHealthA = r, g, b, a
		st.health:SetStatusBarColor(r, g, b, a or 1)
	end
end

function GF:UpdateHealth(self)
	GF:UpdateHealthStyle(self)
	GF:UpdateHealthValue(self)
end

function GF:UpdatePowerVisibility(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st and st.power) then return false end
	local kind = self._eqolGroupKind or "party"
	local cfg = self._eqolCfg or getCfg(kind)
	local pcfg = cfg and cfg.power or {}
	if st._wantsPower == false then
		if st.powerTextLeft then st.powerTextLeft:SetText("") end
		if st.powerTextCenter then st.powerTextCenter:SetText("") end
		if st.powerTextRight then st.powerTextRight:SetText("") end
		if st.power:IsShown() then st.power:Hide() end
		if not st._powerHidden then
			st._powerHidden = true
			GF:LayoutButton(self)
		end
		return false
	end
	local showPower = shouldShowPowerForUnit(pcfg, unit)
	if not showPower then
		if st.powerTextLeft then st.powerTextLeft:SetText("") end
		if st.powerTextCenter then st.powerTextCenter:SetText("") end
		if st.powerTextRight then st.powerTextRight:SetText("") end
		if st.power:IsShown() then st.power:Hide() end
		if not st._powerHidden then
			st._powerHidden = true
			GF:LayoutButton(self)
		end
		return false
	end
	if st._powerHidden then
		st._powerHidden = nil
		GF:LayoutButton(self)
	end
	if not st.power:IsShown() then st.power:Show() end
	return true
end

function GF:UpdatePowerValue(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st and st.power) then return end
	if st._wantsPower == false or st._powerHidden then return end
	if UnitExists and not UnitExists(unit) then
		st.power:SetMinMaxValues(0, 1)
		st.power:SetValue(0)
		return
	end
	local powerType = st._powerType
	if powerType == nil and UnitPowerType then
		powerType, st._powerToken = UnitPowerType(unit)
		st._powerType = powerType
	end
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
			st._lastPowerPx = nil
			st._lastPowerBarW = nil
		end
		local w = st.power:GetWidth()
		if w and w > 0 and maxForValue > 0 then
			local px = floor((cur * w) / maxForValue + 0.5)
			if st._lastPowerPx ~= px or st._lastPowerBarW ~= w then
				st._lastPowerPx = px
				st._lastPowerBarW = w
				st.power:SetValue((px / w) * maxForValue)
				st._lastPowerCur = cur
			end
		else
			if st._lastPowerCur ~= cur then
				st.power:SetValue(cur)
				st._lastPowerCur = cur
			end
		end
	end

	-- Power text slots (UF-like formatting, secret-safe)
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local kind = self._eqolGroupKind or "party"
	local pcfg = cfg and cfg.power or {}
	local defP = (DEFAULTS[kind] and DEFAULTS[kind].power) or {}
	local leftMode = (pcfg.textLeft ~= nil) and pcfg.textLeft or defP.textLeft or "NONE"
	local centerMode = (pcfg.textCenter ~= nil) and pcfg.textCenter or defP.textCenter or "NONE"
	local rightMode = (pcfg.textRight ~= nil) and pcfg.textRight or defP.textRight or "NONE"
	local hasText = (leftMode ~= "NONE") or (centerMode ~= "NONE") or (rightMode ~= "NONE")
	if hasText and (st.powerTextLeft or st.powerTextCenter or st.powerTextRight) then
		local allowSecretText = secretPower and addon.variables and addon.variables.isMidnight
		if secretPower and not allowSecretText then
			if st.powerTextLeft then st.powerTextLeft:SetText("") end
			if st.powerTextCenter then st.powerTextCenter:SetText("") end
			if st.powerTextRight then st.powerTextRight:SetText("") end
			st._lastPowerTextLeft, st._lastPowerTextCenter, st._lastPowerTextRight = nil, nil, nil
		else
			local maxZero = (not issecretvalue or not issecretvalue(maxv)) and (maxv == 0)
			if maxZero then
				if st.powerTextLeft then st.powerTextLeft:SetText("") end
				if st.powerTextCenter then st.powerTextCenter:SetText("") end
				if st.powerTextRight then st.powerTextRight:SetText("") end
				st._lastPowerTextLeft, st._lastPowerTextCenter, st._lastPowerTextRight = nil, nil, nil
			else
				local delimiter = (UFHelper and UFHelper.getTextDelimiter and UFHelper.getTextDelimiter(pcfg, defP)) or (pcfg.textDelimiter or defP.textDelimiter or " ")
				local delimiter2 = (UFHelper and UFHelper.getTextDelimiterSecondary and UFHelper.getTextDelimiterSecondary(pcfg, defP, delimiter))
					or (pcfg.textDelimiterSecondary or defP.textDelimiterSecondary or delimiter)
				local delimiter3 = (UFHelper and UFHelper.getTextDelimiterTertiary and UFHelper.getTextDelimiterTertiary(pcfg, defP, delimiter, delimiter2))
					or (pcfg.textDelimiterTertiary or defP.textDelimiterTertiary or delimiter2)
				local useShort = pcfg.useShortNumbers ~= false
				local hidePercentSymbol = pcfg.hidePercentSymbol == true
				local percentVal
				if textModeUsesPercent(leftMode) or textModeUsesPercent(centerMode) or textModeUsesPercent(rightMode) then
					if addon.variables and addon.variables.isMidnight then
						percentVal = getPowerPercent(unit, powerType or 0, cur, maxv)
					elseif not secretPower then
						percentVal = getPowerPercent(unit, powerType or 0, cur, maxv)
					end
				end
				local levelText
				if UFHelper and UFHelper.textModeUsesLevel then
					if UFHelper.textModeUsesLevel(leftMode) or UFHelper.textModeUsesLevel(centerMode) or UFHelper.textModeUsesLevel(rightMode) then levelText = getSafeLevelText(unit, false) end
				end
				setTextSlot(st, st.powerTextLeft, "_lastPowerTextLeft", leftMode, cur, maxv, useShort, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText)
				setTextSlot(st, st.powerTextCenter, "_lastPowerTextCenter", centerMode, cur, maxv, useShort, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText)
				setTextSlot(st, st.powerTextRight, "_lastPowerTextRight", rightMode, cur, maxv, useShort, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText)
			end
		end
	elseif st.powerTextLeft or st.powerTextCenter or st.powerTextRight then
		if st.powerTextLeft then st.powerTextLeft:SetText("") end
		if st.powerTextCenter then st.powerTextCenter:SetText("") end
		if st.powerTextRight then st.powerTextRight:SetText("") end
		st._lastPowerTextLeft, st._lastPowerTextCenter, st._lastPowerTextRight = nil, nil, nil
	end
end

function GF:UpdatePowerStyle(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st and st.power) then return end
	if st._wantsPower == false or st._powerHidden then return end
	if not UnitPowerType then return end
	if st.power and st.power.SetStatusBarDesaturated then
		if st._lastPowerDesat ~= true then
			st._lastPowerDesat = true
			st.power:SetStatusBarDesaturated(true)
		end
	end
	local powerType, powerToken = UnitPowerType(unit)
	st._powerType, st._powerToken = powerType, powerToken

	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local pcfg = cfg and cfg.power or {}
	local powerTexKey = getEffectiveBarTexture(cfg, pcfg)
	local powerKey = powerToken or powerType or "MANA"
	local texChanged = st._lastPowerTexture ~= powerTexKey
	if st.power.SetStatusBarTexture and UFHelper and UFHelper.resolveTexture then
		if texChanged then
			st.power:SetStatusBarTexture(UFHelper.resolveTexture(powerTexKey))
			stabilizeStatusBarTexture(st.power)
		end
	end
	-- Apply special atlas textures for default texture keys (mirrors UF.lua behavior)
	if UFHelper and UFHelper.configureSpecialTexture then
		local needsAtlas = (powerTexKey == nil or powerTexKey == "" or powerTexKey == "DEFAULT")
		if st._lastPowerToken ~= powerKey or texChanged or needsAtlas then UFHelper.configureSpecialTexture(st.power, powerKey, powerTexKey, pcfg) end
	end
	st._lastPowerToken = powerKey
	st._lastPowerTexture = powerTexKey
	stabilizeStatusBarTexture(st.power)
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
	if not pr then
		pr, pg, pb, pa = 0, 0.5, 1, 1
	end
	local alpha = pa or 1
	if st._lastPowerR ~= pr or st._lastPowerG ~= pg or st._lastPowerB ~= pb or st._lastPowerA ~= alpha then
		st._lastPowerR, st._lastPowerG, st._lastPowerB, st._lastPowerA = pr, pg, pb, alpha
		st.power:SetStatusBarColor(pr, pg, pb, pa or 1)
	end
end

function GF:UpdatePower(self)
	if not GF:UpdatePowerVisibility(self) then return end
	GF:UpdatePowerStyle(self)
	GF:UpdatePowerValue(self)
end

function GF:UpdateAll(self)
	GF:UpdateName(self)
	GF:UpdateLevel(self)
	GF:UpdateHealth(self)
	GF:UpdatePower(self)
	GF:UpdateRoleIcon(self)
	GF:UpdateRaidIcon(self)
	GF:UpdateGroupIcons(self)
	GF:UpdateAuras(self)
	GF:UpdateHighlightState(self)
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
		pcall(function() UnitPopup_OpenMenu(resolveMenuType(unit), { unit = unit }) end)
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
	if parent and parent._eqolKind then self._eqolGroupKind = parent._eqolKind end

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
	local st = self._eqolUFState
	if st then
		st._auraCache = nil
		st._auraCacheByKey = nil
	end
	GF:CacheUnitStatic(self)

	GF:UnitButton_RegisterUnitEvents(self, unit)
	if self._eqolUFState and self._eqolUFState._wantsAbsorb then GF:UpdateAbsorbCache(self) end

	GF:UpdateAll(self)
end

function GF:UnitButton_ClearUnit(self)
	if not self then return end
	self.unit = nil
	if self._eqolRegEv then
		for ev in pairs(self._eqolRegEv) do
			if self.UnregisterEvent then self:UnregisterEvent(ev) end
			self._eqolRegEv[ev] = nil
		end
	end
	local st = self._eqolUFState
	if st then
		st._guid = nil
		st._unitToken = nil
		st._class = nil
		st._powerType = nil
		st._powerToken = nil
		st._classR, st._classG, st._classB, st._classA = nil, nil, nil, nil
		st._absorbAmount = nil
		st._healAbsorbAmount = nil
		st._auraCache = nil
		st._auraCacheByKey = nil
	end
end

function GF:UnitButton_RegisterUnitEvents(self, unit)
	if not (self and unit) then return end
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	updateButtonConfig(self, cfg)

	self._eqolRegEv = self._eqolRegEv or {}
	for ev in pairs(self._eqolRegEv) do
		if self.UnregisterEvent then self:UnregisterEvent(ev) end
		self._eqolRegEv[ev] = nil
	end

	local function reg(ev)
		self:RegisterUnitEvent(ev, unit)
		self._eqolRegEv[ev] = true
	end

	reg("UNIT_CONNECTION")
	reg("UNIT_HEALTH")
	reg("UNIT_MAXHEALTH")
	if self._eqolUFState and self._eqolUFState._wantsAbsorb then
		reg("UNIT_ABSORB_AMOUNT_CHANGED")
		reg("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
	end

	local powerH = cfg and cfg.powerHeight or 0
	local wantsPower = self._eqolUFState and self._eqolUFState._wantsPower
	if wantsPower == nil then wantsPower = true end
	if powerH and powerH > 0 and wantsPower then
		reg("UNIT_POWER_UPDATE")
		reg("UNIT_MAXPOWER")
		reg("UNIT_DISPLAYPOWER")
	end

	reg("UNIT_NAME_UPDATE")
	local wantsLevel = self._eqolUFState and self._eqolUFState._wantsLevel
	if not wantsLevel and UFHelper and UFHelper.textModeUsesLevel then
		local hc = cfg and cfg.health or {}
		local pcfg = cfg and cfg.power or {}
		if UFHelper.textModeUsesLevel(hc.textLeft) or UFHelper.textModeUsesLevel(hc.textCenter) or UFHelper.textModeUsesLevel(hc.textRight) then
			wantsLevel = true
		elseif UFHelper.textModeUsesLevel(pcfg.textLeft) or UFHelper.textModeUsesLevel(pcfg.textCenter) or UFHelper.textModeUsesLevel(pcfg.textRight) then
			wantsLevel = true
		end
	end
	if wantsLevel then reg("UNIT_LEVEL") end

	if self._eqolUFState and self._eqolUFState._wantsAuras then reg("UNIT_AURA") end
end

function GF.UnitButton_OnAttributeChanged(self, name, value)
	if name ~= "unit" then return end
	if value == nil or value == "" then
		-- Unit cleared
		GF:UnitButton_ClearUnit(self)
		GF:UpdateAll(self)
		return
	end
	if self.unit == value then return end
	GF:UnitButton_SetUnit(self, value)
end

local function dispatchUnitHealth(btn) GF:UpdateHealthValue(btn) end
local function dispatchUnitAbsorb(btn)
	GF:UpdateAbsorbCache(btn, "absorb")
	GF:UpdateHealthValue(btn)
end
local function dispatchUnitHealAbsorb(btn)
	GF:UpdateAbsorbCache(btn, "heal")
	GF:UpdateHealthValue(btn)
end
local function dispatchUnitPower(btn) GF:UpdatePowerValue(btn) end
local function dispatchUnitDisplayPower(btn) GF:UpdatePower(btn) end
local function dispatchUnitName(btn)
	GF:CacheUnitStatic(btn)
	GF:UpdateName(btn)
	GF:UpdateHealthStyle(btn)
	GF:UpdateLevel(btn)
end
local function dispatchUnitLevel(btn)
	GF:UpdateLevel(btn)
	GF:UpdateHealthValue(btn)
	GF:UpdatePowerValue(btn)
end
local function dispatchUnitConnection(btn)
	GF:UpdateHealthStyle(btn)
	GF:UpdateHealthValue(btn)
	GF:UpdatePowerValue(btn)
	GF:UpdateName(btn)
	GF:UpdateLevel(btn)
end
local function dispatchUnitAura(btn, updateInfo) GF:RequestAuraUpdate(btn, updateInfo) end

local UNIT_DISPATCH = {
	UNIT_HEALTH = dispatchUnitHealth,
	UNIT_MAXHEALTH = dispatchUnitHealth,
	UNIT_ABSORB_AMOUNT_CHANGED = dispatchUnitAbsorb,
	UNIT_HEAL_ABSORB_AMOUNT_CHANGED = dispatchUnitHealAbsorb,
	UNIT_POWER_UPDATE = dispatchUnitPower,
	UNIT_MAXPOWER = dispatchUnitPower,
	UNIT_DISPLAYPOWER = dispatchUnitDisplayPower,
	UNIT_NAME_UPDATE = dispatchUnitName,
	UNIT_LEVEL = dispatchUnitLevel,
	UNIT_CONNECTION = dispatchUnitConnection,
	UNIT_AURA = dispatchUnitAura,
}

function GF.UnitButton_OnEvent(self, event, unit, ...)
	if not isFeatureEnabled() then return end
	local u = getUnit(self)
	if not u or (unit and unit ~= u) then return end

	local fn = UNIT_DISPATCH[event]
	if fn then
		if GF and GF._debugAuras and event == "UNIT_AURA" then
			local info = ...
			local isFull = info and info.isFullUpdate
			local add = type(info and info.addedAuras) == "table" and #info.addedAuras or 0
			local upd = type(info and info.updatedAuras) == "table" and #info.updatedAuras or 0
			local updIds = type(info and info.updatedAuraInstanceIDs) == "table" and #info.updatedAuraInstanceIDs or 0
			local rem = type(info and info.removedAuraInstanceIDs) == "table" and #info.removedAuraInstanceIDs or 0
			dprint("UNIT_AURA", u, "full", tostring(isFull), "added", add, "updated", upd, "updatedIds", updIds, "removed", rem)
		end
		fn(self, ...)
	end
end

function GF.UnitButton_OnEnter(self)
	local unit = getUnit(self)
	if not unit then return end
	local st = getState(self)
	if st then
		st._hovered = true
		GF:UpdateHighlightState(self)
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
		GF:UpdateHighlightState(self)
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

local function getGrowthStartPoint(growth)
	local g = (growth or "DOWN"):upper()
	if g == "LEFT" then return "TOPRIGHT" end
	if g == "UP" then return "BOTTOMLEFT" end
	return "TOPLEFT"
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
	end

	local totalW, totalH
	if growth == "RIGHT" or growth == "LEFT" then
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

	if UnregisterStateDriver then UnregisterStateDriver(header, "visibility") end

	local cond = "hide"
	if header._eqolForceHide then
		cond = "hide"
	elseif header._eqolForceShow then
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

local previewRoles = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "DAMAGER" }

function GF:EnsurePreviewFrames(kind)
	if kind ~= "party" then return nil end
	if InCombatLockdown and InCombatLockdown() then return nil end
	local anchor = GF.anchors and GF.anchors[kind]
	if not anchor then return nil end
	GF._previewFrames = GF._previewFrames or {}
	local frames = GF._previewFrames[kind]
	if frames then return frames end

	frames = {}
	GF._previewFrames[kind] = frames
	for i = 1, 5 do
		local btn = CreateFrame("Button", nil, anchor, "EQOLUFGroupUnitButtonTemplate")
		btn._eqolGroupKind = kind
		btn._eqolPreview = true
		btn._eqolPreviewIndex = i
		btn:SetFrameStrata(anchor:GetFrameStrata())
		btn:SetFrameLevel((anchor:GetFrameLevel() or 1) + 1)
		local st = getState(btn)
		st._previewRole = previewRoles[i] or "DAMAGER"
		st._previewIndex = i
		frames[i] = btn
		GF:UnitButton_SetUnit(btn, "player")
	end
	return frames
end

function GF:UpdatePreviewLayout(kind)
	local frames = GF._previewFrames and GF._previewFrames[kind]
	local anchor = GF.anchors and GF.anchors[kind]
	if not (frames and anchor) then return end
	local cfg = getCfg(kind)
	if not cfg then return end

	local w = floor((tonumber(cfg.width) or 100) + 0.5)
	local h = floor((tonumber(cfg.height) or 24) + 0.5)
	local spacing = tonumber(cfg.spacing) or 0
	local growth = (cfg.growth or "DOWN"):upper()

	local startPoint = getGrowthStartPoint(growth)
	local isHorizontal = (growth == "RIGHT" or growth == "LEFT")
	local xSign = (growth == "LEFT") and -1 or 1
	local ySign = (growth == "UP") and 1 or -1
	for i, btn in ipairs(frames) do
		if btn then
			btn._eqolGroupKind = kind
			btn._eqolCfg = cfg
			updateButtonConfig(btn, cfg)
			btn:SetSize(w, h)
			btn:ClearAllPoints()
			if isHorizontal then
				btn:SetPoint(startPoint, anchor, startPoint, (i - 1) * (w + spacing) * xSign, 0)
			else
				btn:SetPoint(startPoint, anchor, startPoint, 0, (i - 1) * (h + spacing) * ySign)
			end
			GF:LayoutAuras(btn)
			if btn.unit then GF:UnitButton_RegisterUnitEvents(btn, btn.unit) end
			if btn._eqolUFState then
				GF:LayoutButton(btn)
				GF:UpdateAll(btn)
				if btn._eqolPreview then GF:UpdateSampleAuras(btn) end
			end
		end
	end
end

function GF:ShowPreviewFrames(kind, show)
	local frames = GF._previewFrames and GF._previewFrames[kind]
	if not frames then return end
	for _, btn in ipairs(frames) do
		if btn then
			if show then
				if not btn.unit then GF:UnitButton_SetUnit(btn, "player") end
				btn:Show()
			else
				GF:UnitButton_ClearUnit(btn)
				btn:Hide()
			end
		end
	end
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

function GF:RefreshGroupIcons()
	if not isFeatureEnabled() then return end
	for _, header in pairs(GF.headers or {}) do
		forEachChild(header, function(child)
			if child then GF:UpdateGroupIcons(child) end
		end)
	end
end

function GF:RefreshTargetHighlights()
	if not isFeatureEnabled() then return end
	for _, header in pairs(GF.headers or {}) do
		forEachChild(header, function(child)
			if child then GF:UpdateHighlightState(child) end
		end)
	end
	if GF._previewFrames then
		for _, frames in pairs(GF._previewFrames) do
			for _, btn in ipairs(frames) do
				if btn then GF:UpdateHighlightState(btn) end
			end
		end
	end
end

function GF:RefreshTextStyles()
	if not isFeatureEnabled() then return end
	for _, header in pairs(GF.headers or {}) do
		forEachChild(header, function(child)
			if child then
				updateButtonConfig(child, child._eqolCfg)
				if child._eqolUFState then
					GF:LayoutButton(child)
					GF:UpdateAll(child)
				end
			end
		end)
	end
	if GF._previewFrames then
		for _, frames in pairs(GF._previewFrames) do
			for _, btn in ipairs(frames) do
				if btn then
					updateButtonConfig(btn, btn._eqolCfg)
					if btn._eqolUFState then
						GF:LayoutButton(btn)
						GF:UpdateAll(btn)
					end
				end
			end
		end
	end
end

function GF:RefreshRaidIcons()
	if not isFeatureEnabled() then return end
	for _, header in pairs(GF.headers or {}) do
		forEachChild(header, function(child)
			if child then GF:UpdateRaidIcon(child) end
		end)
	end
	if GF._previewFrames then
		for _, frames in pairs(GF._previewFrames) do
			for _, btn in ipairs(frames) do
				if btn then GF:UpdateRaidIcon(btn) end
			end
		end
	end
end

function GF:RefreshNames()
	if not isFeatureEnabled() then return end
	for _, header in pairs(GF.headers or {}) do
		forEachChild(header, function(child)
			if child then
				updateButtonConfig(child, child._eqolCfg)
				if child._eqolUFState then
					GF:LayoutButton(child)
					GF:UpdateName(child)
				end
			end
		end)
	end
	if GF._previewFrames then
		for _, frames in pairs(GF._previewFrames) do
			for _, btn in ipairs(frames) do
				if btn then
					updateButtonConfig(btn, btn._eqolCfg)
					if btn._eqolUFState then
						GF:LayoutButton(btn)
						GF:UpdateName(btn)
					end
				end
			end
		end
	end
end

function GF:RefreshPowerVisibility()
	if not isFeatureEnabled() then return end
	for _, header in pairs(GF.headers or {}) do
		forEachChild(header, function(child)
			if child then
				updateButtonConfig(child, child._eqolCfg)
				if child.unit then GF:UnitButton_RegisterUnitEvents(child, child.unit) end
				GF:UpdatePower(child)
			end
		end)
	end
end

function GF:UpdateHealthColorMode(kind)
	if not isFeatureEnabled() then return end
	if kind then
		local cfg = getCfg(kind)
		if cfg then sanitizeHealthColorMode(cfg) end
	end
	for _, header in pairs(GF.headers or {}) do
		forEachChild(header, function(child)
			if child then GF:UpdateHealthStyle(child) end
		end)
	end
	if GF._previewFrames then
		for _, frames in pairs(GF._previewFrames) do
			for _, btn in ipairs(frames) do
				if btn then GF:UpdateHealthStyle(btn) end
			end
		end
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
		header:SetAttribute("maxColumns", 1)
		header:SetAttribute("unitsPerColumn", 5)
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
	if growth == "RIGHT" or growth == "LEFT" then
		local xOff = (growth == "LEFT") and -spacing or spacing
		local point = (growth == "LEFT") and "RIGHT" or "LEFT"
		header:SetAttribute("point", point)
		header:SetAttribute("xOffset", xOff)
		header:SetAttribute("yOffset", 0)
		if kind == "party" then
			header:SetAttribute("columnSpacing", spacing)
		else
			header:SetAttribute("columnSpacing", tonumber(cfg.columnSpacing) or spacing)
		end
		header:SetAttribute("columnAnchorPoint", "LEFT")
	else
		local yOff = (growth == "UP") and spacing or -spacing
		local point = (growth == "UP") and "BOTTOM" or "TOP"
		header:SetAttribute("point", point)
		header:SetAttribute("xOffset", 0)
		header:SetAttribute("yOffset", yOff)
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
	header:SetAttribute(
		"initialConfigFunction",
		string.format(
			[[
		self:SetWidth(%d)
		self:SetHeight(%d)
		self:SetAttribute('*type1','target')
		self:SetAttribute('*type2','togglemenu')
		RegisterUnitWatch(self)
	]],
			w,
			h
		)
	)

	-- Also apply size to existing children.
	forEachChild(header, function(child)
		child._eqolGroupKind = kind
		child._eqolCfg = cfg
		updateButtonConfig(child, cfg)
		GF:LayoutAuras(child)
		if child.unit then GF:UnitButton_RegisterUnitEvents(child, child.unit) end
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
		local p = getGrowthStartPoint(growth)
		header:SetPoint(p, anchor, p, 0, 0)
	else
		setPointFromCfg(header, cfg)
	end
	applyVisibility(header, kind, cfg)
	if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end
end

function GF:EnsureHeaders()
	if not isFeatureEnabled() then return end
	if GF.headers.party and GF.headers.raid and GF.anchors.party and GF.anchors.raid then return end

	-- Parent to PetBattleFrameHider so frames disappear in pet battles
	local parent = _G.PetBattleFrameHider or UIParent

	-- Movers (for Edit Mode positioning)
	if not GF.anchors.party then ensureAnchor("party", parent) end
	if not GF.anchors.raid then ensureAnchor("raid", parent) end

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
	registerFeatureEvents(GF._eventFrame)
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
	unregisterFeatureEvents(GF._eventFrame)

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

local function buildEditModeSettings(kind, editModeId)
	if not SettingType then return nil end

	local widthLabel = HUD_EDIT_MODE_SETTING_CHAT_FRAME_WIDTH or "Width"
	local heightLabel = HUD_EDIT_MODE_SETTING_CHAT_FRAME_HEIGHT or "Height"
	local specOptions = buildSpecOptions()
	local function getHealthTextMode(key, fallback)
		local cfg = getCfg(kind)
		local hc = cfg and cfg.health or {}
		local def = (DEFAULTS[kind] and DEFAULTS[kind].health) or {}
		return hc[key] or def[key] or fallback or "NONE"
	end
	local function isHealthTextEnabled(key, fallback) return getHealthTextMode(key, fallback) ~= "NONE" end
	local function getPowerTextMode(key, fallback)
		local cfg = getCfg(kind)
		local pcfg = cfg and cfg.power or {}
		local def = (DEFAULTS[kind] and DEFAULTS[kind].power) or {}
		return pcfg[key] or def[key] or fallback or "NONE"
	end
	local function isPowerTextEnabled(key, fallback) return getPowerTextMode(key, fallback) ~= "NONE" end
	local function anyHealthTextEnabled() return isHealthTextEnabled("textLeft") or isHealthTextEnabled("textCenter") or isHealthTextEnabled("textRight") end
	local function healthDelimiterCount() return maxDelimiterCount(getHealthTextMode("textLeft"), getHealthTextMode("textCenter"), getHealthTextMode("textRight")) end
	local function powerDelimiterCount() return maxDelimiterCount(getPowerTextMode("textLeft"), getPowerTextMode("textCenter"), getPowerTextMode("textRight")) end
	local function getHighlightCfg(key)
		local cfg = getCfg(kind)
		local hcfg = cfg and cfg[key] or {}
		local def = (DEFAULTS[kind] and DEFAULTS[kind][key]) or {}
		return hcfg, def
	end
	local function isHighlightEnabled(key)
		local hcfg, def = getHighlightCfg(key)
		local enabled = hcfg.enabled
		if enabled == nil then enabled = def.enabled end
		return enabled == true
	end
	local function auraGrowthGenerator()
		return function(_, root, data)
			local opts = auraGrowthOptions or auraGrowthXOptions
			if type(opts) ~= "table" then return end
			for _, option in ipairs(opts) do
				local label = option.label or option.text or option.value or ""
				root:CreateRadio(label, function() return data.get and data.get() == option.value end, function()
					if data.set then data.set(nil, option.value) end
					if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RequestRefreshSettings then addon.EditModeLib.internal:RequestRefreshSettings() end
				end)
			end
		end
	end
	local function isExternalDRShown()
		local cfg = getCfg(kind)
		local ac = ensureAuraConfig(cfg)
		return ac.externals and ac.externals.showDR == true
	end
	local settings = {
		{
			name = "Frame",
			kind = SettingType.Collapsible,
			id = "frame",
			defaultCollapsed = true,
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
			defaultCollapsed = true,
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
					{ value = "UP", label = "Up" },
					{ value = "LEFT", label = "Left" },
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
			name = "Frame texture",
			kind = SettingType.Dropdown,
			field = "barTexture",
			parentId = "layout",
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local tex = cfg and cfg.barTexture
				if not tex or tex == "" then return BAR_TEX_INHERIT end
				return tex
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				if value == BAR_TEX_INHERIT then
					cfg.barTexture = nil
				else
					cfg.barTexture = value
				end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "barTexture", cfg.barTexture or BAR_TEX_INHERIT, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				root:CreateRadio("Use health/power textures", function()
					local cfg = getCfg(kind)
					return not (cfg and cfg.barTexture)
				end, function()
					local cfg = getCfg(kind)
					if not cfg then return end
					cfg.barTexture = nil
					if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "barTexture", BAR_TEX_INHERIT, nil, true) end
					GF:ApplyHeaderAttributes(kind)
				end)
				for _, option in ipairs(textureOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						return (cfg and cfg.barTexture) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.barTexture = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "barTexture", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Border",
			kind = SettingType.Collapsible,
			id = "border",
			defaultCollapsed = true,
		},
		{
			name = "Show border",
			kind = SettingType.Checkbox,
			field = "borderEnabled",
			parentId = "border",
			get = function()
				local cfg = getCfg(kind)
				local bc = cfg and cfg.border or {}
				if bc.enabled == nil then return (DEFAULTS[kind] and DEFAULTS[kind].border and DEFAULTS[kind].border.enabled) ~= false end
				return bc.enabled ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.border = cfg.border or {}
				cfg.border.enabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "borderEnabled", cfg.border.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Border color",
			kind = SettingType.Color,
			field = "borderColor",
			parentId = "border",
			hasOpacity = true,
			default = (DEFAULTS[kind] and DEFAULTS[kind].border and DEFAULTS[kind].border.color) or { 0, 0, 0, 0.8 },
			get = function()
				local cfg = getCfg(kind)
				local bc = cfg and cfg.border or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].border and DEFAULTS[kind].border.color) or { 0, 0, 0, 0.8 }
				local r, g, b, a = unpackColor(bc.color, def)
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.border = cfg.border or {}
				cfg.border.color = { value.r or 0, value.g or 0, value.b or 0, value.a or 0.8 }
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "borderColor", cfg.border.color, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local bc = cfg and cfg.border or {}
				return bc.enabled ~= false
			end,
		},
		{
			name = "Border texture",
			kind = SettingType.Dropdown,
			field = "borderTexture",
			parentId = "border",
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local bc = cfg and cfg.border or {}
				return bc.texture or (DEFAULTS[kind] and DEFAULTS[kind].border and DEFAULTS[kind].border.texture) or "DEFAULT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.border = cfg.border or {}
				cfg.border.texture = value or "DEFAULT"
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "borderTexture", cfg.border.texture, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(borderOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local bc = cfg and cfg.border or {}
						return (bc.texture or (DEFAULTS[kind] and DEFAULTS[kind].border and DEFAULTS[kind].border.texture) or "DEFAULT") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.border = cfg.border or {}
						cfg.border.texture = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "borderTexture", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local bc = cfg and cfg.border or {}
				return bc.enabled ~= false
			end,
		},
		{
			name = "Border size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "borderSize",
			parentId = "border",
			minValue = 1,
			maxValue = 64,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local bc = cfg and cfg.border or {}
				return bc.edgeSize or (DEFAULTS[kind] and DEFAULTS[kind].border and DEFAULTS[kind].border.edgeSize) or 1
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.border = cfg.border or {}
				cfg.border.edgeSize = clampNumber(value, 1, 64, cfg.border.edgeSize or 1)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "borderSize", cfg.border.edgeSize, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local bc = cfg and cfg.border or {}
				return bc.enabled ~= false
			end,
		},
		{
			name = "Border offset",
			kind = SettingType.Slider,
			allowInput = true,
			field = "borderOffset",
			parentId = "border",
			minValue = 0,
			maxValue = 64,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local bc = cfg and cfg.border or {}
				if bc.offset == nil and bc.inset == nil then return bc.edgeSize or (DEFAULTS[kind] and DEFAULTS[kind].border and DEFAULTS[kind].border.edgeSize) or 1 end
				return bc.offset or bc.inset or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.border = cfg.border or {}
				cfg.border.offset = clampNumber(value, 0, 64, cfg.border.offset or cfg.border.inset or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "borderOffset", cfg.border.offset, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local bc = cfg and cfg.border or {}
				return bc.enabled ~= false
			end,
		},
		{
			name = "Hover highlight",
			kind = SettingType.Collapsible,
			id = "hoverHighlight",
			defaultCollapsed = true,
		},
		{
			name = "Enable hover highlight",
			kind = SettingType.Checkbox,
			field = "hoverHighlightEnabled",
			parentId = "hoverHighlight",
			get = function()
				local hcfg, def = getHighlightCfg("highlightHover")
				if hcfg.enabled == nil then return def.enabled == true end
				return hcfg.enabled == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.highlightHover = cfg.highlightHover or {}
				cfg.highlightHover.enabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "hoverHighlightEnabled", cfg.highlightHover.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Color",
			kind = SettingType.Color,
			field = "hoverHighlightColor",
			parentId = "hoverHighlight",
			hasOpacity = true,
			default = (DEFAULTS[kind] and DEFAULTS[kind].highlightHover and DEFAULTS[kind].highlightHover.color) or { 1, 1, 1, 0.9 },
			get = function()
				local hcfg, def = getHighlightCfg("highlightHover")
				local r, g, b, a = unpackColor(hcfg.color, def.color or { 1, 1, 1, 0.9 })
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.highlightHover = cfg.highlightHover or {}
				cfg.highlightHover.color = { value.r or 1, value.g or 1, value.b or 1, value.a or 0.9 }
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "hoverHighlightColor", cfg.highlightHover.color, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isHighlightEnabled("highlightHover") end,
		},
		{
			name = "Texture",
			kind = SettingType.Dropdown,
			field = "hoverHighlightTexture",
			parentId = "hoverHighlight",
			height = 180,
			get = function()
				local hcfg, def = getHighlightCfg("highlightHover")
				return hcfg.texture or def.texture or "DEFAULT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.highlightHover = cfg.highlightHover or {}
				cfg.highlightHover.texture = value or "DEFAULT"
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "hoverHighlightTexture", cfg.highlightHover.texture, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(borderOptions()) do
					root:CreateRadio(option.label, function()
						local hcfg, def = getHighlightCfg("highlightHover")
						return (hcfg.texture or def.texture or "DEFAULT") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.highlightHover = cfg.highlightHover or {}
						cfg.highlightHover.texture = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "hoverHighlightTexture", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function() return isHighlightEnabled("highlightHover") end,
		},
		{
			name = "Size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "hoverHighlightSize",
			parentId = "hoverHighlight",
			minValue = 1,
			maxValue = 64,
			valueStep = 1,
			get = function()
				local hcfg, def = getHighlightCfg("highlightHover")
				return hcfg.size or def.size or 2
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.highlightHover = cfg.highlightHover or {}
				cfg.highlightHover.size = clampNumber(value, 1, 64, cfg.highlightHover.size or 2)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "hoverHighlightSize", cfg.highlightHover.size, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isHighlightEnabled("highlightHover") end,
		},
		{
			name = "Offset",
			kind = SettingType.Slider,
			allowInput = true,
			field = "hoverHighlightOffset",
			parentId = "hoverHighlight",
			minValue = -64,
			maxValue = 64,
			valueStep = 1,
			get = function()
				local hcfg, def = getHighlightCfg("highlightHover")
				return hcfg.offset or def.offset or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.highlightHover = cfg.highlightHover or {}
				cfg.highlightHover.offset = clampNumber(value, -64, 64, cfg.highlightHover.offset or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "hoverHighlightOffset", cfg.highlightHover.offset, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isHighlightEnabled("highlightHover") end,
		},
		{
			name = "Target highlight",
			kind = SettingType.Collapsible,
			id = "targetHighlight",
			defaultCollapsed = true,
		},
		{
			name = "Enable target highlight",
			kind = SettingType.Checkbox,
			field = "targetHighlightEnabled",
			parentId = "targetHighlight",
			get = function()
				local hcfg, def = getHighlightCfg("highlightTarget")
				if hcfg.enabled == nil then return def.enabled == true end
				return hcfg.enabled == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.highlightTarget = cfg.highlightTarget or {}
				cfg.highlightTarget.enabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "targetHighlightEnabled", cfg.highlightTarget.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Color",
			kind = SettingType.Color,
			field = "targetHighlightColor",
			parentId = "targetHighlight",
			hasOpacity = true,
			default = (DEFAULTS[kind] and DEFAULTS[kind].highlightTarget and DEFAULTS[kind].highlightTarget.color) or { 1, 1, 0, 1 },
			get = function()
				local hcfg, def = getHighlightCfg("highlightTarget")
				local r, g, b, a = unpackColor(hcfg.color, def.color or { 1, 1, 0, 1 })
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.highlightTarget = cfg.highlightTarget or {}
				cfg.highlightTarget.color = { value.r or 1, value.g or 1, value.b or 0, value.a or 1 }
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "targetHighlightColor", cfg.highlightTarget.color, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isHighlightEnabled("highlightTarget") end,
		},
		{
			name = "Texture",
			kind = SettingType.Dropdown,
			field = "targetHighlightTexture",
			parentId = "targetHighlight",
			height = 180,
			get = function()
				local hcfg, def = getHighlightCfg("highlightTarget")
				return hcfg.texture or def.texture or "DEFAULT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.highlightTarget = cfg.highlightTarget or {}
				cfg.highlightTarget.texture = value or "DEFAULT"
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "targetHighlightTexture", cfg.highlightTarget.texture, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(borderOptions()) do
					root:CreateRadio(option.label, function()
						local hcfg, def = getHighlightCfg("highlightTarget")
						return (hcfg.texture or def.texture or "DEFAULT") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.highlightTarget = cfg.highlightTarget or {}
						cfg.highlightTarget.texture = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "targetHighlightTexture", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function() return isHighlightEnabled("highlightTarget") end,
		},
		{
			name = "Size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "targetHighlightSize",
			parentId = "targetHighlight",
			minValue = 1,
			maxValue = 64,
			valueStep = 1,
			get = function()
				local hcfg, def = getHighlightCfg("highlightTarget")
				return hcfg.size or def.size or 2
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.highlightTarget = cfg.highlightTarget or {}
				cfg.highlightTarget.size = clampNumber(value, 1, 64, cfg.highlightTarget.size or 2)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "targetHighlightSize", cfg.highlightTarget.size, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isHighlightEnabled("highlightTarget") end,
		},
		{
			name = "Offset",
			kind = SettingType.Slider,
			allowInput = true,
			field = "targetHighlightOffset",
			parentId = "targetHighlight",
			minValue = -64,
			maxValue = 64,
			valueStep = 1,
			get = function()
				local hcfg, def = getHighlightCfg("highlightTarget")
				return hcfg.offset or def.offset or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.highlightTarget = cfg.highlightTarget or {}
				cfg.highlightTarget.offset = clampNumber(value, -64, 64, cfg.highlightTarget.offset or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "targetHighlightOffset", cfg.highlightTarget.offset, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isHighlightEnabled("highlightTarget") end,
		},
		{
			name = "Name",
			kind = SettingType.Collapsible,
			id = "text",
			defaultCollapsed = true,
		},
		{
			name = "Show name",
			kind = SettingType.Checkbox,
			field = "showName",
			parentId = "text",
			get = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				return tc.showName ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.text = cfg.text or {}
				cfg.text.showName = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "showName", cfg.text.showName, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				GF:RefreshNames()
			end,
		},
		{
			name = "Name anchor",
			kind = SettingType.Dropdown,
			field = "nameAnchor",
			parentId = "text",
			values = anchorOptions9,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				return tc.nameAnchor or (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.nameAnchor) or "LEFT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.text = cfg.text or {}
				cfg.text.nameAnchor = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameAnchor", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				return tc.showName ~= false
			end,
		},
		{
			name = "Name offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "nameOffsetX",
			parentId = "text",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				return (tc.nameOffset and tc.nameOffset.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.text = cfg.text or {}
				cfg.text.nameOffset = cfg.text.nameOffset or {}
				cfg.text.nameOffset.x = clampNumber(value, -200, 200, (cfg.text.nameOffset and cfg.text.nameOffset.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameOffsetX", cfg.text.nameOffset.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				return tc.showName ~= false
			end,
		},
		{
			name = "Name offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "nameOffsetY",
			parentId = "text",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				return (tc.nameOffset and tc.nameOffset.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.text = cfg.text or {}
				cfg.text.nameOffset = cfg.text.nameOffset or {}
				cfg.text.nameOffset.y = clampNumber(value, -200, 200, (cfg.text.nameOffset and cfg.text.nameOffset.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameOffsetY", cfg.text.nameOffset.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				return tc.showName ~= false
			end,
		},
		{
			name = "Name class color",
			kind = SettingType.Checkbox,
			field = "nameClassColor",
			parentId = "text",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				if sc.nameColorMode then return sc.nameColorMode == "CLASS" end
				local tc = cfg and cfg.text or {}
				return tc.useClassColor ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.text = cfg.text or {}
				cfg.status = cfg.status or {}
				cfg.text.useClassColor = value and true or false
				cfg.status.nameColorMode = value and "CLASS" or "CUSTOM"
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameClassColor", cfg.text.useClassColor, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				return tc.showName ~= false
			end,
		},
		{
			name = "Name color",
			kind = SettingType.Color,
			field = "nameColor",
			parentId = "text",
			hasOpacity = true,
			default = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.nameColor) or { 1, 1, 1, 1 },
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.nameColor) or { 1, 1, 1, 1 }
				local r, g, b, a = unpackColor(sc.nameColor, def)
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.status = cfg.status or {}
				cfg.text = cfg.text or {}
				cfg.status.nameColor = { value.r or 1, value.g or 1, value.b or 1, value.a or 1 }
				cfg.status.nameColorMode = "CUSTOM"
				cfg.text.useClassColor = false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameColor", cfg.status.nameColor, nil, true) end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameClassColor", false, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local mode = sc.nameColorMode
				if not mode then
					local tc = cfg and cfg.text or {}
					mode = (tc.useClassColor ~= false) and "CLASS" or "CUSTOM"
				end
				local tc = cfg and cfg.text or {}
				return tc.showName ~= false and mode == "CUSTOM"
			end,
		},
		{
			name = "Name max width",
			kind = SettingType.Slider,
			allowInput = true,
			field = "nameMaxChars",
			parentId = "text",
			minValue = 0,
			maxValue = 40,
			valueStep = 1,
			default = (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.nameMaxChars) or 0,
			get = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				return tc.nameMaxChars or (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.nameMaxChars) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.text = cfg.text or {}
				cfg.text.nameMaxChars = clampNumber(value, 0, 40, cfg.text.nameMaxChars or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameMaxChars", cfg.text.nameMaxChars, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				return tc.showName ~= false
			end,
		},
		{
			name = "Name font size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "nameFontSize",
			parentId = "text",
			minValue = 8,
			maxValue = 30,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				return tc.fontSize or (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.fontSize) or 12
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.text = cfg.text or {}
				cfg.text.fontSize = clampNumber(value, 8, 30, cfg.text.fontSize or 12)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameFontSize", cfg.text.fontSize, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				return tc.showName ~= false
			end,
		},
		{
			name = "Name font",
			kind = SettingType.Dropdown,
			field = "nameFont",
			parentId = "text",
			get = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				return tc.font or (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.font) or nil
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.text = cfg.text or {}
				cfg.text.font = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameFont", cfg.text.font, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(fontOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local tc = cfg and cfg.text or {}
						return (tc.font or (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.font) or nil) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.text = cfg.text or {}
						cfg.text.font = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameFont", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				return tc.showName ~= false
			end,
		},
		{
			name = "Name font outline",
			kind = SettingType.Dropdown,
			field = "nameFontOutline",
			parentId = "text",
			get = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				return tc.fontOutline or (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.fontOutline) or "OUTLINE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.text = cfg.text or {}
				cfg.text.fontOutline = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameFontOutline", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(outlineOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local tc = cfg and cfg.text or {}
						return (tc.fontOutline or (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.fontOutline) or "OUTLINE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.text = cfg.text or {}
						cfg.text.fontOutline = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameFontOutline", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				return tc.showName ~= false
			end,
		},
		{
			name = "Health",
			kind = SettingType.Collapsible,
			id = "health",
			defaultCollapsed = true,
		},
		{
			name = "Use class color (players)",
			kind = SettingType.Checkbox,
			field = "healthClassColor",
			parentId = "health",
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
				if value then cfg.health.useCustomColor = false end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthClassColor", cfg.health.useClassColor, nil, true) end
				if EditMode and EditMode.SetValue and value then EditMode:SetValue(editModeId, "healthUseCustomColor", false, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				GF:UpdateHealthColorMode(kind)
			end,
		},
		{
			name = "Custom health color",
			kind = SettingType.Checkbox,
			field = "healthUseCustomColor",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.useCustomColor == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.useCustomColor = value and true or false
				if value then cfg.health.useClassColor = false end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthUseCustomColor", cfg.health.useCustomColor, nil, true) end
				if EditMode and EditMode.SetValue and value then EditMode:SetValue(editModeId, "healthClassColor", false, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				GF:UpdateHealthColorMode(kind)
			end,
		},
		{
			name = "Health color",
			kind = SettingType.Color,
			field = "healthColor",
			parentId = "health",
			hasOpacity = true,
			default = (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.color) or { 0, 0.8, 0, 1 },
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.color) or { 0, 0.8, 0, 1 }
				local r, g, b, a = unpackColor(hc.color, def)
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.health = cfg.health or {}
				cfg.health.color = { value.r or 0, value.g or 0.8, value.b or 0, value.a or 1 }
				cfg.health.useCustomColor = true
				cfg.health.useClassColor = false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthColor", cfg.health.color, nil, true) end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthUseCustomColor", true, nil, true) end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthClassColor", false, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.useCustomColor == true
			end,
		},
		{
			name = "Left text",
			kind = SettingType.Dropdown,
			field = "healthTextLeft",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.textLeft or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textLeft) or "NONE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.textLeft = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthTextLeft", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(textModeOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local hc = cfg and cfg.health or {}
						return (hc.textLeft or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textLeft) or "NONE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.health = cfg.health or {}
						cfg.health.textLeft = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthTextLeft", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Center text",
			kind = SettingType.Dropdown,
			field = "healthTextCenter",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.textCenter or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textCenter) or "NONE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.textCenter = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthTextCenter", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(textModeOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local hc = cfg and cfg.health or {}
						return (hc.textCenter or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textCenter) or "NONE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.health = cfg.health or {}
						cfg.health.textCenter = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthTextCenter", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Right text",
			kind = SettingType.Dropdown,
			field = "healthTextRight",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.textRight or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textRight) or "NONE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.textRight = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthTextRight", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(textModeOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local hc = cfg and cfg.health or {}
						return (hc.textRight or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textRight) or "NONE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.health = cfg.health or {}
						cfg.health.textRight = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthTextRight", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Health text color",
			kind = SettingType.Color,
			field = "healthTextColor",
			parentId = "health",
			hasOpacity = true,
			default = (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textColor) or { 1, 1, 1, 1 },
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textColor) or { 1, 1, 1, 1 }
				local r, g, b, a = unpackColor(hc.textColor, def)
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.health = cfg.health or {}
				cfg.health.textColor = { value.r or 1, value.g or 1, value.b or 1, value.a or 1 }
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthTextColor", cfg.health.textColor, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return anyHealthTextEnabled() end,
		},
		{
			name = "Hide % symbol",
			kind = SettingType.Checkbox,
			field = "healthHidePercent",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.hidePercentSymbol == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.hidePercentSymbol = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthHidePercent", cfg.health.hidePercentSymbol, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Font size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "healthFontSize",
			parentId = "health",
			minValue = 8,
			maxValue = 30,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.fontSize or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.fontSize) or 12
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.fontSize = clampNumber(value, 8, 30, cfg.health.fontSize or 12)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthFontSize", cfg.health.fontSize, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Font",
			kind = SettingType.Dropdown,
			field = "healthFont",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.font or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.font) or nil
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.font = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthFont", cfg.health.font, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(fontOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local hc = cfg and cfg.health or {}
						return (hc.font or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.font) or nil) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.health = cfg.health or {}
						cfg.health.font = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthFont", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Font outline",
			kind = SettingType.Dropdown,
			field = "healthFontOutline",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.fontOutline or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.fontOutline) or "OUTLINE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.fontOutline = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthFontOutline", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(outlineOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local hc = cfg and cfg.health or {}
						return (hc.fontOutline or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.fontOutline) or "OUTLINE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.health = cfg.health or {}
						cfg.health.fontOutline = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthFontOutline", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Use short numbers",
			kind = SettingType.Checkbox,
			field = "healthShortNumbers",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				if hc.useShortNumbers == nil then return (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.useShortNumbers) ~= false end
				return hc.useShortNumbers ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.useShortNumbers = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthShortNumbers", cfg.health.useShortNumbers, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Health delimiter",
			kind = SettingType.Dropdown,
			field = "healthDelimiter",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiter) or " "
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.textDelimiter = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthDelimiter", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(delimiterOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local hc = cfg and cfg.health or {}
						return (hc.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiter) or " ") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.health = cfg.health or {}
						cfg.health.textDelimiter = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthDelimiter", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isShown = function() return healthDelimiterCount() >= 1 end,
		},
		{
			name = "Health secondary delimiter",
			kind = SettingType.Dropdown,
			field = "healthDelimiterSecondary",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				local primary = hc.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiter) or " "
				return hc.textDelimiterSecondary or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiterSecondary) or primary
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.textDelimiterSecondary = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthDelimiterSecondary", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(delimiterOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local hc = cfg and cfg.health or {}
						local primary = hc.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiter) or " "
						return (hc.textDelimiterSecondary or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiterSecondary) or primary) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.health = cfg.health or {}
						cfg.health.textDelimiterSecondary = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthDelimiterSecondary", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isShown = function() return healthDelimiterCount() >= 2 end,
		},
		{
			name = "Health tertiary delimiter",
			kind = SettingType.Dropdown,
			field = "healthDelimiterTertiary",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				local primary = hc.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiter) or " "
				local secondary = hc.textDelimiterSecondary or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiterSecondary) or primary
				return hc.textDelimiterTertiary or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiterTertiary) or secondary
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.textDelimiterTertiary = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthDelimiterTertiary", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(delimiterOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local hc = cfg and cfg.health or {}
						local primary = hc.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiter) or " "
						local secondary = hc.textDelimiterSecondary or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiterSecondary) or primary
						return (hc.textDelimiterTertiary or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiterTertiary) or secondary) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.health = cfg.health or {}
						cfg.health.textDelimiterTertiary = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthDelimiterTertiary", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isShown = function() return healthDelimiterCount() >= 3 end,
		},
		{
			name = "Left text offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "healthLeftX",
			parentId = "health",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return (hc.offsetLeft and hc.offsetLeft.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.offsetLeft = cfg.health.offsetLeft or {}
				cfg.health.offsetLeft.x = clampNumber(value, -200, 200, (cfg.health.offsetLeft and cfg.health.offsetLeft.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthLeftX", cfg.health.offsetLeft.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isHealthTextEnabled("textLeft") end,
		},
		{
			name = "Left text offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "healthLeftY",
			parentId = "health",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return (hc.offsetLeft and hc.offsetLeft.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.offsetLeft = cfg.health.offsetLeft or {}
				cfg.health.offsetLeft.y = clampNumber(value, -200, 200, (cfg.health.offsetLeft and cfg.health.offsetLeft.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthLeftY", cfg.health.offsetLeft.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isHealthTextEnabled("textLeft") end,
		},
		{
			name = "Center text offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "healthCenterX",
			parentId = "health",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return (hc.offsetCenter and hc.offsetCenter.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.offsetCenter = cfg.health.offsetCenter or {}
				cfg.health.offsetCenter.x = clampNumber(value, -200, 200, (cfg.health.offsetCenter and cfg.health.offsetCenter.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthCenterX", cfg.health.offsetCenter.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isHealthTextEnabled("textCenter") end,
		},
		{
			name = "Center text offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "healthCenterY",
			parentId = "health",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return (hc.offsetCenter and hc.offsetCenter.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.offsetCenter = cfg.health.offsetCenter or {}
				cfg.health.offsetCenter.y = clampNumber(value, -200, 200, (cfg.health.offsetCenter and cfg.health.offsetCenter.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthCenterY", cfg.health.offsetCenter.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isHealthTextEnabled("textCenter") end,
		},
		{
			name = "Right text offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "healthRightX",
			parentId = "health",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return (hc.offsetRight and hc.offsetRight.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.offsetRight = cfg.health.offsetRight or {}
				cfg.health.offsetRight.x = clampNumber(value, -200, 200, (cfg.health.offsetRight and cfg.health.offsetRight.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthRightX", cfg.health.offsetRight.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isHealthTextEnabled("textRight") end,
		},
		{
			name = "Right text offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "healthRightY",
			parentId = "health",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return (hc.offsetRight and hc.offsetRight.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.offsetRight = cfg.health.offsetRight or {}
				cfg.health.offsetRight.y = clampNumber(value, -200, 200, (cfg.health.offsetRight and cfg.health.offsetRight.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthRightY", cfg.health.offsetRight.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isHealthTextEnabled("textRight") end,
		},
		{
			name = "Bar texture",
			kind = SettingType.Dropdown,
			field = "healthTexture",
			parentId = "health",
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.texture or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.texture) or "DEFAULT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.texture = value or "DEFAULT"
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthTexture", cfg.health.texture, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(textureOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local hc = cfg and cfg.health or {}
						return (hc.texture or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.texture) or "DEFAULT") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.health = cfg.health or {}
						cfg.health.texture = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthTexture", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				return not (cfg and cfg.barTexture)
			end,
		},
		{
			name = "Show bar backdrop",
			kind = SettingType.Checkbox,
			field = "healthBackdropEnabled",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				local def = DEFAULTS[kind] and DEFAULTS[kind].health or {}
				local defBackdrop = def and def.backdrop or {}
				if hc.backdrop and hc.backdrop.enabled ~= nil then return hc.backdrop.enabled ~= false end
				return defBackdrop.enabled ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.backdrop = cfg.health.backdrop or {}
				cfg.health.backdrop.enabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthBackdropEnabled", cfg.health.backdrop.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Backdrop color",
			kind = SettingType.Color,
			field = "healthBackdropColor",
			parentId = "health",
			hasOpacity = true,
			default = (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.backdrop and DEFAULTS[kind].health.backdrop.color) or { 0, 0, 0, 0.6 },
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.backdrop and DEFAULTS[kind].health.backdrop.color) or { 0, 0, 0, 0.6 }
				local r, g, b, a = unpackColor(hc.backdrop and hc.backdrop.color, def)
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.health = cfg.health or {}
				cfg.health.backdrop = cfg.health.backdrop or {}
				cfg.health.backdrop.color = { value.r or 0, value.g or 0, value.b or 0, value.a or 0.6 }
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthBackdropColor", cfg.health.backdrop.color, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.backdrop and hc.backdrop.enabled ~= false
			end,
		},
		{
			name = "Absorb",
			kind = SettingType.Collapsible,
			id = "absorb",
			defaultCollapsed = true,
		},
		{
			name = "Show absorb bar",
			kind = SettingType.Checkbox,
			field = "absorbEnabled",
			parentId = "absorb",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.absorbEnabled ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.absorbEnabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "absorbEnabled", cfg.health.absorbEnabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Show sample absorb",
			kind = SettingType.Checkbox,
			field = "absorbSample",
			parentId = "absorb",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.showSampleAbsorb == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.showSampleAbsorb = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "absorbSample", cfg.health.showSampleAbsorb, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.absorbEnabled ~= false
			end,
		},
		{
			name = "Absorb texture",
			kind = SettingType.Dropdown,
			field = "absorbTexture",
			parentId = "absorb",
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.absorbTexture or "SOLID"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.absorbTexture = value or "SOLID"
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "absorbTexture", cfg.health.absorbTexture, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(textureOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local hc = cfg and cfg.health or {}
						return (hc.absorbTexture or "SOLID") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.health = cfg.health or {}
						cfg.health.absorbTexture = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "absorbTexture", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.absorbEnabled ~= false
			end,
		},
		{
			name = "Absorb reverse fill",
			kind = SettingType.Checkbox,
			field = "absorbReverse",
			parentId = "absorb",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.absorbReverseFill == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.absorbReverseFill = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "absorbReverse", cfg.health.absorbReverseFill, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.absorbEnabled ~= false
			end,
		},
		{
			name = "Custom absorb color",
			kind = SettingType.Checkbox,
			field = "absorbUseCustomColor",
			parentId = "absorb",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.absorbUseCustomColor == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.absorbUseCustomColor = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "absorbUseCustomColor", cfg.health.absorbUseCustomColor, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.absorbEnabled ~= false
			end,
		},
		{
			name = "Absorb color",
			kind = SettingType.Color,
			field = "absorbColor",
			parentId = "absorb",
			hasOpacity = true,
			default = (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.absorbColor) or { 0.85, 0.95, 1, 0.7 },
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.absorbColor) or { 0.85, 0.95, 1, 0.7 }
				local r, g, b, a = unpackColor(hc.absorbColor, def)
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.health = cfg.health or {}
				cfg.health.absorbColor = { value.r or 0.85, value.g or 0.95, value.b or 1, value.a or 0.7 }
				cfg.health.absorbUseCustomColor = true
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "absorbColor", cfg.health.absorbColor, nil, true) end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "absorbUseCustomColor", true, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.absorbEnabled ~= false and hc.absorbUseCustomColor == true
			end,
		},
		{
			name = "Heal absorb",
			kind = SettingType.Collapsible,
			id = "healabsorb",
			defaultCollapsed = true,
		},
		{
			name = "Show heal absorb bar",
			kind = SettingType.Checkbox,
			field = "healAbsorbEnabled",
			parentId = "healabsorb",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.healAbsorbEnabled ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.healAbsorbEnabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healAbsorbEnabled", cfg.health.healAbsorbEnabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Show sample heal absorb",
			kind = SettingType.Checkbox,
			field = "healAbsorbSample",
			parentId = "healabsorb",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.showSampleHealAbsorb == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.showSampleHealAbsorb = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healAbsorbSample", cfg.health.showSampleHealAbsorb, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.healAbsorbEnabled ~= false
			end,
		},
		{
			name = "Heal absorb texture",
			kind = SettingType.Dropdown,
			field = "healAbsorbTexture",
			parentId = "healabsorb",
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.healAbsorbTexture or "SOLID"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.healAbsorbTexture = value or "SOLID"
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healAbsorbTexture", cfg.health.healAbsorbTexture, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(textureOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local hc = cfg and cfg.health or {}
						return (hc.healAbsorbTexture or "SOLID") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.health = cfg.health or {}
						cfg.health.healAbsorbTexture = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healAbsorbTexture", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.healAbsorbEnabled ~= false
			end,
		},
		{
			name = "Heal absorb reverse fill",
			kind = SettingType.Checkbox,
			field = "healAbsorbReverse",
			parentId = "healabsorb",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.healAbsorbReverseFill == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.healAbsorbReverseFill = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healAbsorbReverse", cfg.health.healAbsorbReverseFill, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.healAbsorbEnabled ~= false
			end,
		},
		{
			name = "Custom heal absorb color",
			kind = SettingType.Checkbox,
			field = "healAbsorbUseCustomColor",
			parentId = "healabsorb",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.healAbsorbUseCustomColor == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.healAbsorbUseCustomColor = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healAbsorbUseCustomColor", cfg.health.healAbsorbUseCustomColor, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.healAbsorbEnabled ~= false
			end,
		},
		{
			name = "Heal absorb color",
			kind = SettingType.Color,
			field = "healAbsorbColor",
			parentId = "healabsorb",
			hasOpacity = true,
			default = (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.healAbsorbColor) or { 1, 0.3, 0.3, 0.7 },
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.healAbsorbColor) or { 1, 0.3, 0.3, 0.7 }
				local r, g, b, a = unpackColor(hc.healAbsorbColor, def)
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.health = cfg.health or {}
				cfg.health.healAbsorbColor = { value.r or 1, value.g or 0.3, value.b or 0.3, value.a or 0.7 }
				cfg.health.healAbsorbUseCustomColor = true
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healAbsorbColor", cfg.health.healAbsorbColor, nil, true) end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healAbsorbUseCustomColor", true, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.healAbsorbEnabled ~= false and hc.healAbsorbUseCustomColor == true
			end,
		},
		{
			name = "Level",
			kind = SettingType.Collapsible,
			id = "level",
			defaultCollapsed = true,
		},
		{
			name = "Show level",
			kind = SettingType.Checkbox,
			field = "levelEnabled",
			parentId = "level",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.levelEnabled ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.levelEnabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "levelEnabled", cfg.status.levelEnabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Hide level at max",
			kind = SettingType.Checkbox,
			field = "hideLevelAtMax",
			parentId = "level",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.hideLevelAtMax == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.hideLevelAtMax = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "hideLevelAtMax", cfg.status.hideLevelAtMax, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.levelEnabled ~= false
			end,
		},
		{
			name = "Level class color",
			kind = SettingType.Checkbox,
			field = "levelClassColor",
			parentId = "level",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return (sc.levelColorMode or "CUSTOM") == "CLASS"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.levelColorMode = value and "CLASS" or "CUSTOM"
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "levelClassColor", value and true or false, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.levelEnabled ~= false
			end,
		},
		{
			name = "Level color",
			kind = SettingType.Color,
			field = "levelColor",
			parentId = "level",
			hasOpacity = true,
			default = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.levelColor) or { 1, 0.85, 0, 1 },
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.levelColor) or { 1, 0.85, 0, 1 }
				local r, g, b, a = unpackColor(sc.levelColor, def)
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.status = cfg.status or {}
				cfg.status.levelColor = { value.r or 1, value.g or 1, value.b or 1, value.a or 1 }
				cfg.status.levelColorMode = "CUSTOM"
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "levelColor", cfg.status.levelColor, nil, true) end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "levelClassColor", false, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.levelEnabled ~= false and (sc.levelColorMode or "CUSTOM") == "CUSTOM"
			end,
		},
		{
			name = "Level font size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "levelFontSize",
			parentId = "level",
			minValue = 8,
			maxValue = 30,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local tc = cfg and cfg.text or {}
				local hc = cfg and cfg.health or {}
				return sc.levelFontSize or tc.fontSize or hc.fontSize or 12
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.levelFontSize = clampNumber(value, 8, 30, cfg.status.levelFontSize or 12)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "levelFontSize", cfg.status.levelFontSize, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.levelEnabled ~= false
			end,
		},
		{
			name = "Level font",
			kind = SettingType.Dropdown,
			field = "levelFont",
			parentId = "level",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local tc = cfg and cfg.text or {}
				local hc = cfg and cfg.health or {}
				return sc.levelFont or tc.font or hc.font or nil
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.levelFont = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "levelFont", cfg.status.levelFont, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(fontOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local sc = cfg and cfg.status or {}
						local tc = cfg and cfg.text or {}
						local hc = cfg and cfg.health or {}
						return (sc.levelFont or tc.font or hc.font or nil) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.status = cfg.status or {}
						cfg.status.levelFont = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "levelFont", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.levelEnabled ~= false
			end,
		},
		{
			name = "Level font outline",
			kind = SettingType.Dropdown,
			field = "levelFontOutline",
			parentId = "level",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local tc = cfg and cfg.text or {}
				local hc = cfg and cfg.health or {}
				return sc.levelFontOutline or tc.fontOutline or hc.fontOutline or "OUTLINE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.levelFontOutline = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "levelFontOutline", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(outlineOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local sc = cfg and cfg.status or {}
						local tc = cfg and cfg.text or {}
						local hc = cfg and cfg.health or {}
						return (sc.levelFontOutline or tc.fontOutline or hc.fontOutline or "OUTLINE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.status = cfg.status or {}
						cfg.status.levelFontOutline = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "levelFontOutline", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.levelEnabled ~= false
			end,
		},
		{
			name = "Level anchor",
			kind = SettingType.Dropdown,
			field = "levelAnchor",
			parentId = "level",
			values = anchorOptions9,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.levelAnchor or "RIGHT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.levelAnchor = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "levelAnchor", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.levelEnabled ~= false
			end,
		},
		{
			name = "Level offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "levelOffsetX",
			parentId = "level",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return (sc.levelOffset and sc.levelOffset.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.levelOffset = cfg.status.levelOffset or {}
				cfg.status.levelOffset.x = clampNumber(value, -200, 200, (cfg.status.levelOffset and cfg.status.levelOffset.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "levelOffsetX", cfg.status.levelOffset.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.levelEnabled ~= false
			end,
		},
		{
			name = "Level offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "levelOffsetY",
			parentId = "level",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return (sc.levelOffset and sc.levelOffset.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.levelOffset = cfg.status.levelOffset or {}
				cfg.status.levelOffset.y = clampNumber(value, -200, 200, (cfg.status.levelOffset and cfg.status.levelOffset.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "levelOffsetY", cfg.status.levelOffset.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.levelEnabled ~= false
			end,
		},
		{
			name = "Group icons",
			kind = SettingType.Collapsible,
			id = "groupicons",
			defaultCollapsed = true,
		},
		{
			name = "Show leader icon",
			kind = SettingType.Checkbox,
			field = "leaderIconEnabled",
			parentId = "groupicons",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local lc = sc.leaderIcon or {}
				return lc.enabled ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.leaderIcon = cfg.status.leaderIcon or {}
				cfg.status.leaderIcon.enabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "leaderIconEnabled", cfg.status.leaderIcon.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Leader icon size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "leaderIconSize",
			parentId = "groupicons",
			minValue = 8,
			maxValue = 40,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local lc = sc.leaderIcon or {}
				return lc.size or 12
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.leaderIcon = cfg.status.leaderIcon or {}
				cfg.status.leaderIcon.size = clampNumber(value, 8, 40, cfg.status.leaderIcon.size or 12)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "leaderIconSize", cfg.status.leaderIcon.size, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local lc = sc.leaderIcon or {}
				return lc.enabled ~= false
			end,
		},
		{
			name = "Leader icon anchor",
			kind = SettingType.Dropdown,
			field = "leaderIconPoint",
			parentId = "groupicons",
			values = auraAnchorOptions,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local lc = sc.leaderIcon or {}
				return lc.point or "TOPLEFT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.leaderIcon = cfg.status.leaderIcon or {}
				cfg.status.leaderIcon.point = value
				cfg.status.leaderIcon.relativePoint = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "leaderIconPoint", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local lc = sc.leaderIcon or {}
				return lc.enabled ~= false
			end,
		},
		{
			name = "Leader icon offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "leaderIconOffsetX",
			parentId = "groupicons",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local lc = sc.leaderIcon or {}
				return lc.x or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.leaderIcon = cfg.status.leaderIcon or {}
				cfg.status.leaderIcon.x = clampNumber(value, -200, 200, cfg.status.leaderIcon.x or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "leaderIconOffsetX", cfg.status.leaderIcon.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local lc = sc.leaderIcon or {}
				return lc.enabled ~= false
			end,
		},
		{
			name = "Leader icon offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "leaderIconOffsetY",
			parentId = "groupicons",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local lc = sc.leaderIcon or {}
				return lc.y or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.leaderIcon = cfg.status.leaderIcon or {}
				cfg.status.leaderIcon.y = clampNumber(value, -200, 200, cfg.status.leaderIcon.y or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "leaderIconOffsetY", cfg.status.leaderIcon.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local lc = sc.leaderIcon or {}
				return lc.enabled ~= false
			end,
		},
		{
			name = "Show assist icon",
			kind = SettingType.Checkbox,
			field = "assistIconEnabled",
			parentId = "groupicons",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local acfg = sc.assistIcon or {}
				return acfg.enabled ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.assistIcon = cfg.status.assistIcon or {}
				cfg.status.assistIcon.enabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "assistIconEnabled", cfg.status.assistIcon.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isShown = function() return kind == "raid" end,
		},
		{
			name = "Assist icon size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "assistIconSize",
			parentId = "groupicons",
			minValue = 8,
			maxValue = 40,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local acfg = sc.assistIcon or {}
				return acfg.size or 12
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.assistIcon = cfg.status.assistIcon or {}
				cfg.status.assistIcon.size = clampNumber(value, 8, 40, cfg.status.assistIcon.size or 12)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "assistIconSize", cfg.status.assistIcon.size, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local acfg = sc.assistIcon or {}
				return acfg.enabled ~= false
			end,
			isShown = function() return kind == "raid" end,
		},
		{
			name = "Assist icon anchor",
			kind = SettingType.Dropdown,
			field = "assistIconPoint",
			parentId = "groupicons",
			values = auraAnchorOptions,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local acfg = sc.assistIcon or {}
				return acfg.point or "TOPLEFT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.assistIcon = cfg.status.assistIcon or {}
				cfg.status.assistIcon.point = value
				cfg.status.assistIcon.relativePoint = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "assistIconPoint", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local acfg = sc.assistIcon or {}
				return acfg.enabled ~= false
			end,
			isShown = function() return kind == "raid" end,
		},
		{
			name = "Assist icon offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "assistIconOffsetX",
			parentId = "groupicons",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local acfg = sc.assistIcon or {}
				return acfg.x or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.assistIcon = cfg.status.assistIcon or {}
				cfg.status.assistIcon.x = clampNumber(value, -200, 200, cfg.status.assistIcon.x or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "assistIconOffsetX", cfg.status.assistIcon.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local acfg = sc.assistIcon or {}
				return acfg.enabled ~= false
			end,
			isShown = function() return kind == "raid" end,
		},
		{
			name = "Assist icon offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "assistIconOffsetY",
			parentId = "groupicons",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local acfg = sc.assistIcon or {}
				return acfg.y or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.assistIcon = cfg.status.assistIcon or {}
				cfg.status.assistIcon.y = clampNumber(value, -200, 200, cfg.status.assistIcon.y or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "assistIconOffsetY", cfg.status.assistIcon.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local acfg = sc.assistIcon or {}
				return acfg.enabled ~= false
			end,
			isShown = function() return kind == "raid" end,
		},
		{
			name = "Raid marker",
			kind = SettingType.Collapsible,
			id = "raidmarker",
			defaultCollapsed = true,
		},
		{
			name = "Show raid marker",
			kind = SettingType.Checkbox,
			field = "raidIconEnabled",
			parentId = "raidmarker",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local rc = sc.raidIcon or {}
				return rc.enabled ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.raidIcon = cfg.status.raidIcon or {}
				cfg.status.raidIcon.enabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "raidIconEnabled", cfg.status.raidIcon.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				GF:RefreshRaidIcons()
			end,
		},
		{
			name = "Raid marker size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "raidIconSize",
			parentId = "raidmarker",
			minValue = 8,
			maxValue = 40,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local rc = sc.raidIcon or {}
				return rc.size or 18
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.raidIcon = cfg.status.raidIcon or {}
				cfg.status.raidIcon.size = clampNumber(value, 8, 40, cfg.status.raidIcon.size or 18)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "raidIconSize", cfg.status.raidIcon.size, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				GF:RefreshRaidIcons()
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local rc = sc.raidIcon or {}
				return rc.enabled ~= false
			end,
		},
		{
			name = "Raid marker anchor",
			kind = SettingType.Dropdown,
			field = "raidIconPoint",
			parentId = "raidmarker",
			values = anchorOptions9,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local rc = sc.raidIcon or {}
				return rc.point or "TOP"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.raidIcon = cfg.status.raidIcon or {}
				cfg.status.raidIcon.point = value
				cfg.status.raidIcon.relativePoint = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "raidIconPoint", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				GF:RefreshRaidIcons()
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local rc = sc.raidIcon or {}
				return rc.enabled ~= false
			end,
		},
		{
			name = "Raid marker offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "raidIconOffsetX",
			parentId = "raidmarker",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local rc = sc.raidIcon or {}
				return rc.x or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.raidIcon = cfg.status.raidIcon or {}
				cfg.status.raidIcon.x = clampNumber(value, -200, 200, cfg.status.raidIcon.x or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "raidIconOffsetX", cfg.status.raidIcon.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				GF:RefreshRaidIcons()
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local rc = sc.raidIcon or {}
				return rc.enabled ~= false
			end,
		},
		{
			name = "Raid marker offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "raidIconOffsetY",
			parentId = "raidmarker",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local rc = sc.raidIcon or {}
				return rc.y or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.raidIcon = cfg.status.raidIcon or {}
				cfg.status.raidIcon.y = clampNumber(value, -200, 200, cfg.status.raidIcon.y or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "raidIconOffsetY", cfg.status.raidIcon.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				GF:RefreshRaidIcons()
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local rc = sc.raidIcon or {}
				return rc.enabled ~= false
			end,
		},
		{
			name = "Role icons",
			kind = SettingType.Collapsible,
			id = "roleicons",
			defaultCollapsed = true,
		},
		{
			name = "Enable role icons",
			kind = SettingType.Checkbox,
			field = "roleIconEnabled",
			parentId = "roleicons",
			get = function()
				local cfg = getCfg(kind)
				local rc = cfg and cfg.roleIcon or {}
				return rc.enabled ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.roleIcon = cfg.roleIcon or {}
				cfg.roleIcon.enabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "roleIconEnabled", cfg.roleIcon.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Role icon size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "roleIconSize",
			parentId = "roleicons",
			minValue = 8,
			maxValue = 40,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local rc = cfg and cfg.roleIcon or {}
				return rc.size or 14
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.roleIcon = cfg.roleIcon or {}
				cfg.roleIcon.size = clampNumber(value, 8, 40, cfg.roleIcon.size or 14)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "roleIconSize", cfg.roleIcon.size, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local rc = cfg and cfg.roleIcon or {}
				return rc.enabled ~= false
			end,
		},
		{
			name = "Role icon anchor",
			kind = SettingType.Dropdown,
			field = "roleIconPoint",
			parentId = "roleicons",
			values = anchorOptions9,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local rc = cfg and cfg.roleIcon or {}
				return rc.point or "LEFT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.roleIcon = cfg.roleIcon or {}
				cfg.roleIcon.point = value
				cfg.roleIcon.relativePoint = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "roleIconPoint", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local rc = cfg and cfg.roleIcon or {}
				return rc.enabled ~= false
			end,
		},
		{
			name = "Role icon offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "roleIconOffsetX",
			parentId = "roleicons",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local rc = cfg and cfg.roleIcon or {}
				return rc.x or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.roleIcon = cfg.roleIcon or {}
				cfg.roleIcon.x = clampNumber(value, -200, 200, cfg.roleIcon.x or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "roleIconOffsetX", cfg.roleIcon.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local rc = cfg and cfg.roleIcon or {}
				return rc.enabled ~= false
			end,
		},
		{
			name = "Role icon offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "roleIconOffsetY",
			parentId = "roleicons",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local rc = cfg and cfg.roleIcon or {}
				return rc.y or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.roleIcon = cfg.roleIcon or {}
				cfg.roleIcon.y = clampNumber(value, -200, 200, cfg.roleIcon.y or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "roleIconOffsetY", cfg.roleIcon.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local rc = cfg and cfg.roleIcon or {}
				return rc.enabled ~= false
			end,
		},
		{
			name = "Role icon style",
			kind = SettingType.Dropdown,
			field = "roleIconStyle",
			parentId = "roleicons",
			get = function()
				local cfg = getCfg(kind)
				local rc = cfg and cfg.roleIcon or {}
				return rc.style or "TINY"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.roleIcon = cfg.roleIcon or {}
				cfg.roleIcon.style = value or "TINY"
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "roleIconStyle", cfg.roleIcon.style, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				local tinyLabel = "|A:roleicon-tiny-tank:16:16|a |A:roleicon-tiny-healer:16:16|a |A:roleicon-tiny-dps:16:16|a"
				local circleLabel = "|A:UI-LFG-RoleIcon-Tank-Micro-GroupFinder:16:16|a |A:UI-LFG-RoleIcon-Healer-Micro-GroupFinder:16:16|a |A:UI-LFG-RoleIcon-DPS-Micro-GroupFinder:16:16|a"
				local options = {
					{ value = "TINY", label = tinyLabel },
					{ value = "CIRCLE", label = circleLabel },
				}
				for _, option in ipairs(options) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local rc = cfg and cfg.roleIcon or {}
						return (rc.style or "TINY") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.roleIcon = cfg.roleIcon or {}
						cfg.roleIcon.style = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "roleIconStyle", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local rc = cfg and cfg.roleIcon or {}
				return rc.enabled ~= false
			end,
		},
		{
			name = "Show role icons for roles",
			kind = SettingType.MultiDropdown,
			field = "roleIconRoles",
			height = 120,
			values = roleOptions,
			parentId = "roleicons",
			isSelected = function(_, value)
				local cfg = getCfg(kind)
				local rc = cfg and cfg.roleIcon or {}
				local selection = rc.showRoles
				if type(selection) ~= "table" then return true end
				return selectionContains(selection, value)
			end,
			setSelected = function(_, value, state)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.roleIcon = cfg.roleIcon or {}
				local selection = cfg.roleIcon.showRoles
				if type(selection) ~= "table" then
					selection = defaultRoleSelection()
					cfg.roleIcon.showRoles = selection
				end
				if state then
					selection[value] = true
				else
					selection[value] = nil
				end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "roleIconRoles", copySelectionMap(selection), nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local rc = cfg and cfg.roleIcon or {}
				return rc.enabled ~= false
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
				return selectionContains(selection, value)
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
			height = 240,
			values = specOptions,
			parentId = "power",
			isSelected = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				local selection = pcfg.showSpecs
				if value == "__ALL__" then
					if type(selection) ~= "table" then return true end
					for _, opt in ipairs(specOptions) do
						if opt.value ~= "__ALL__" and not selectionContains(selection, opt.value) then return false end
					end
					return true
				end
				if type(selection) ~= "table" then return true end
				return selectionContains(selection, value)
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
				if value == "__ALL__" then
					for _, opt in ipairs(specOptions) do
						if opt.value ~= "__ALL__" then
							if state then
								selection[opt.value] = true
							else
								selection[opt.value] = nil
							end
						end
					end
					if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerSpecs", copySelectionMap(selection), nil, true) end
					GF:RefreshPowerVisibility()
					return
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
			name = "Power text left",
			kind = SettingType.Dropdown,
			field = "powerTextLeft",
			parentId = "power",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return pcfg.textLeft or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textLeft) or "NONE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.textLeft = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerTextLeft", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(textModeOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local pcfg = cfg and cfg.power or {}
						return (pcfg.textLeft or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textLeft) or "NONE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.power = cfg.power or {}
						cfg.power.textLeft = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerTextLeft", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Power text center",
			kind = SettingType.Dropdown,
			field = "powerTextCenter",
			parentId = "power",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return pcfg.textCenter or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textCenter) or "NONE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.textCenter = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerTextCenter", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(textModeOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local pcfg = cfg and cfg.power or {}
						return (pcfg.textCenter or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textCenter) or "NONE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.power = cfg.power or {}
						cfg.power.textCenter = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerTextCenter", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Power text right",
			kind = SettingType.Dropdown,
			field = "powerTextRight",
			parentId = "power",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return pcfg.textRight or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textRight) or "NONE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.textRight = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerTextRight", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(textModeOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local pcfg = cfg and cfg.power or {}
						return (pcfg.textRight or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textRight) or "NONE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.power = cfg.power or {}
						cfg.power.textRight = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerTextRight", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Power delimiter",
			kind = SettingType.Dropdown,
			field = "powerDelimiter",
			parentId = "power",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return pcfg.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiter) or " "
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.textDelimiter = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerDelimiter", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(delimiterOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local pcfg = cfg and cfg.power or {}
						return (pcfg.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiter) or " ") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.power = cfg.power or {}
						cfg.power.textDelimiter = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerDelimiter", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isShown = function() return powerDelimiterCount() >= 1 end,
		},
		{
			name = "Power secondary delimiter",
			kind = SettingType.Dropdown,
			field = "powerDelimiterSecondary",
			parentId = "power",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				local primary = pcfg.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiter) or " "
				return pcfg.textDelimiterSecondary or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiterSecondary) or primary
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.textDelimiterSecondary = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerDelimiterSecondary", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(delimiterOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local pcfg = cfg and cfg.power or {}
						local primary = pcfg.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiter) or " "
						return (pcfg.textDelimiterSecondary or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiterSecondary) or primary) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.power = cfg.power or {}
						cfg.power.textDelimiterSecondary = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerDelimiterSecondary", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isShown = function() return powerDelimiterCount() >= 2 end,
		},
		{
			name = "Power tertiary delimiter",
			kind = SettingType.Dropdown,
			field = "powerDelimiterTertiary",
			parentId = "power",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				local primary = pcfg.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiter) or " "
				local secondary = pcfg.textDelimiterSecondary or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiterSecondary) or primary
				return pcfg.textDelimiterTertiary or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiterTertiary) or secondary
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.textDelimiterTertiary = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerDelimiterTertiary", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(delimiterOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local pcfg = cfg and cfg.power or {}
						local primary = pcfg.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiter) or " "
						local secondary = pcfg.textDelimiterSecondary or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiterSecondary) or primary
						return (pcfg.textDelimiterTertiary or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiterTertiary) or secondary) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.power = cfg.power or {}
						cfg.power.textDelimiterTertiary = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerDelimiterTertiary", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isShown = function() return powerDelimiterCount() >= 3 end,
		},
		{
			name = "Short numbers",
			kind = SettingType.Checkbox,
			field = "powerShortNumbers",
			parentId = "power",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				if pcfg.useShortNumbers == nil then return (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.useShortNumbers) ~= false end
				return pcfg.useShortNumbers ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.useShortNumbers = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerShortNumbers", cfg.power.useShortNumbers, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Hide percent symbol",
			kind = SettingType.Checkbox,
			field = "powerHidePercent",
			parentId = "power",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return pcfg.hidePercentSymbol == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.hidePercentSymbol = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerHidePercent", cfg.power.hidePercentSymbol, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Font size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "powerFontSize",
			parentId = "power",
			minValue = 8,
			maxValue = 30,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return pcfg.fontSize or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.fontSize) or 10
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.fontSize = clampNumber(value, 8, 30, cfg.power.fontSize or 10)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerFontSize", cfg.power.fontSize, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Font",
			kind = SettingType.Dropdown,
			field = "powerFont",
			parentId = "power",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return pcfg.font or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.font) or nil
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.font = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerFont", cfg.power.font, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(fontOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local pcfg = cfg and cfg.power or {}
						return (pcfg.font or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.font) or nil) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.power = cfg.power or {}
						cfg.power.font = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerFont", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Font outline",
			kind = SettingType.Dropdown,
			field = "powerFontOutline",
			parentId = "power",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return pcfg.fontOutline or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.fontOutline) or "OUTLINE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.fontOutline = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerFontOutline", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(outlineOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local pcfg = cfg and cfg.power or {}
						return (pcfg.fontOutline or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.fontOutline) or "OUTLINE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.power = cfg.power or {}
						cfg.power.fontOutline = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerFontOutline", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Left text offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "powerLeftX",
			parentId = "power",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return (pcfg.offsetLeft and pcfg.offsetLeft.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.offsetLeft = cfg.power.offsetLeft or {}
				cfg.power.offsetLeft.x = clampNumber(value, -200, 200, (cfg.power.offsetLeft and cfg.power.offsetLeft.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerLeftX", cfg.power.offsetLeft.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isPowerTextEnabled("textLeft") end,
		},
		{
			name = "Left text offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "powerLeftY",
			parentId = "power",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return (pcfg.offsetLeft and pcfg.offsetLeft.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.offsetLeft = cfg.power.offsetLeft or {}
				cfg.power.offsetLeft.y = clampNumber(value, -200, 200, (cfg.power.offsetLeft and cfg.power.offsetLeft.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerLeftY", cfg.power.offsetLeft.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isPowerTextEnabled("textLeft") end,
		},
		{
			name = "Center text offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "powerCenterX",
			parentId = "power",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return (pcfg.offsetCenter and pcfg.offsetCenter.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.offsetCenter = cfg.power.offsetCenter or {}
				cfg.power.offsetCenter.x = clampNumber(value, -200, 200, (cfg.power.offsetCenter and cfg.power.offsetCenter.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerCenterX", cfg.power.offsetCenter.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isPowerTextEnabled("textCenter") end,
		},
		{
			name = "Center text offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "powerCenterY",
			parentId = "power",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return (pcfg.offsetCenter and pcfg.offsetCenter.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.offsetCenter = cfg.power.offsetCenter or {}
				cfg.power.offsetCenter.y = clampNumber(value, -200, 200, (cfg.power.offsetCenter and cfg.power.offsetCenter.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerCenterY", cfg.power.offsetCenter.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isPowerTextEnabled("textCenter") end,
		},
		{
			name = "Right text offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "powerRightX",
			parentId = "power",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return (pcfg.offsetRight and pcfg.offsetRight.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.offsetRight = cfg.power.offsetRight or {}
				cfg.power.offsetRight.x = clampNumber(value, -200, 200, (cfg.power.offsetRight and cfg.power.offsetRight.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerRightX", cfg.power.offsetRight.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isPowerTextEnabled("textRight") end,
		},
		{
			name = "Right text offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "powerRightY",
			parentId = "power",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return (pcfg.offsetRight and pcfg.offsetRight.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.offsetRight = cfg.power.offsetRight or {}
				cfg.power.offsetRight.y = clampNumber(value, -200, 200, (cfg.power.offsetRight and cfg.power.offsetRight.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerRightY", cfg.power.offsetRight.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isPowerTextEnabled("textRight") end,
		},
		{
			name = "Power texture",
			kind = SettingType.Dropdown,
			field = "powerTexture",
			parentId = "power",
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return pcfg.texture or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.texture) or "DEFAULT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.texture = value or "DEFAULT"
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerTexture", cfg.power.texture, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(textureOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local pcfg = cfg and cfg.power or {}
						return (pcfg.texture or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.texture) or "DEFAULT") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.power = cfg.power or {}
						cfg.power.texture = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerTexture", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				return not (cfg and cfg.barTexture)
			end,
		},
		{
			name = "Show bar backdrop",
			kind = SettingType.Checkbox,
			field = "powerBackdropEnabled",
			parentId = "power",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				local def = DEFAULTS[kind] and DEFAULTS[kind].power or {}
				local defBackdrop = def and def.backdrop or {}
				if pcfg.backdrop and pcfg.backdrop.enabled ~= nil then return pcfg.backdrop.enabled ~= false end
				return defBackdrop.enabled ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.backdrop = cfg.power.backdrop or {}
				cfg.power.backdrop.enabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerBackdropEnabled", cfg.power.backdrop.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Backdrop color",
			kind = SettingType.Color,
			field = "powerBackdropColor",
			parentId = "power",
			hasOpacity = true,
			default = (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.backdrop and DEFAULTS[kind].power.backdrop.color) or { 0, 0, 0, 0.6 },
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.backdrop and DEFAULTS[kind].power.backdrop.color) or { 0, 0, 0, 0.6 }
				local r, g, b, a = unpackColor(pcfg.backdrop and pcfg.backdrop.color, def)
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.power = cfg.power or {}
				cfg.power.backdrop = cfg.power.backdrop or {}
				cfg.power.backdrop.color = { value.r or 0, value.g or 0, value.b or 0, value.a or 0.6 }
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerBackdropColor", cfg.power.backdrop.color, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return pcfg.backdrop and pcfg.backdrop.enabled ~= false
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
			height = 180,
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
			name = "Buff growth direction",
			kind = SettingType.Dropdown,
			field = "buffGrowth",
			parentId = "buffs",
			generator = auraGrowthGenerator(),
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return getAuraGrowthValue(ac.buff, ac.buff.anchorPoint)
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				applyAuraGrowth(ac.buff, value)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffGrowth", value, nil, true) end
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
			height = 180,
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
			name = "Debuff growth direction",
			kind = SettingType.Dropdown,
			field = "debuffGrowth",
			parentId = "debuffs",
			generator = auraGrowthGenerator(),
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return getAuraGrowthValue(ac.debuff, ac.debuff.anchorPoint)
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				applyAuraGrowth(ac.debuff, value)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffGrowth", value, nil, true) end
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
			height = 180,
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
			name = "External growth direction",
			kind = SettingType.Dropdown,
			field = "externalGrowth",
			parentId = "externals",
			generator = auraGrowthGenerator(),
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return getAuraGrowthValue(ac.externals, ac.externals.anchorPoint)
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				applyAuraGrowth(ac.externals, value)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalGrowth", value, nil, true) end
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
		{
			name = "Show DR %",
			kind = SettingType.Checkbox,
			field = "externalDrEnabled",
			parentId = "externals",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.showDR == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.showDR = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalDrEnabled", ac.externals.showDR, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "DR anchor",
			kind = SettingType.Dropdown,
			field = "externalDrAnchor",
			parentId = "externals",
			values = anchorOptions9,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.drAnchor or "TOPLEFT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.drAnchor = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalDrAnchor", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = isExternalDRShown,
		},
		{
			name = "DR offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalDrOffsetX",
			parentId = "externals",
			minValue = -50,
			maxValue = 50,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return (ac.externals.drOffset and ac.externals.drOffset.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.drOffset = ac.externals.drOffset or {}
				ac.externals.drOffset.x = clampNumber(value, -50, 50, (ac.externals.drOffset and ac.externals.drOffset.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalDrOffsetX", ac.externals.drOffset.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = isExternalDRShown,
		},
		{
			name = "DR offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalDrOffsetY",
			parentId = "externals",
			minValue = -50,
			maxValue = 50,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return (ac.externals.drOffset and ac.externals.drOffset.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.drOffset = ac.externals.drOffset or {}
				ac.externals.drOffset.y = clampNumber(value, -50, 50, (ac.externals.drOffset and ac.externals.drOffset.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalDrOffsetY", ac.externals.drOffset.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = isExternalDRShown,
		},
		{
			name = "DR color",
			kind = SettingType.Color,
			field = "externalDrColor",
			parentId = "externals",
			hasOpacity = true,
			default = { 1, 1, 1, 1 },
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				local col = ac.externals.drColor or { 1, 1, 1, 1 }
				return { r = col[1] or 1, g = col[2] or 1, b = col[3] or 1, a = col[4] or 1 }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.drColor = { value.r or 1, value.g or 1, value.b or 1, value.a or 1 }
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalDrColor", ac.externals.drColor, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = isExternalDRShown,
		},
		{
			name = "DR font size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalDrFontSize",
			parentId = "externals",
			minValue = 6,
			maxValue = 24,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.drFontSize or 10
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.drFontSize = clampNumber(value, 6, 24, ac.externals.drFontSize or 10)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalDrFontSize", ac.externals.drFontSize, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = isExternalDRShown,
		},
		{
			name = "DR font",
			kind = SettingType.Dropdown,
			field = "externalDrFont",
			parentId = "externals",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.drFont
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.drFont = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalDrFont", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(fontOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local ac = ensureAuraConfig(cfg)
						return (ac.externals.drFont or nil) == option.value
					end, function()
						local cfg = getCfg(kind)
						local ac = ensureAuraConfig(cfg)
						ac.externals.drFont = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalDrFont", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = isExternalDRShown,
		},
		{
			name = "DR font outline",
			kind = SettingType.Dropdown,
			field = "externalDrFontOutline",
			parentId = "externals",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.drFontOutline or "OUTLINE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.drFontOutline = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalDrFontOutline", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(outlineOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local ac = ensureAuraConfig(cfg)
						return (ac.externals.drFontOutline or "OUTLINE") == option.value
					end, function()
						local cfg = getCfg(kind)
						local ac = ensureAuraConfig(cfg)
						ac.externals.drFontOutline = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalDrFontOutline", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = isExternalDRShown,
		},
	}

	if kind == "party" then
		settings[#settings + 1] = {
			name = "Party",
			kind = SettingType.Collapsible,
			id = "party",
			defaultCollapsed = true,
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
			defaultCollapsed = true,
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

	if data.width ~= nil then cfg.width = clampNumber(data.width, 40, 600, cfg.width or 100) end
	if data.height ~= nil then cfg.height = clampNumber(data.height, 10, 200, cfg.height or 24) end
	if data.powerHeight ~= nil then cfg.powerHeight = clampNumber(data.powerHeight, 0, 50, cfg.powerHeight or 6) end
	if data.spacing ~= nil then cfg.spacing = clampNumber(data.spacing, 0, 40, cfg.spacing or 0) end
	if data.growth then cfg.growth = tostring(data.growth):upper() end
	if data.barTexture ~= nil then
		if data.barTexture == BAR_TEX_INHERIT then
			cfg.barTexture = nil
		else
			cfg.barTexture = data.barTexture
		end
	end
	if data.borderEnabled ~= nil or data.borderColor ~= nil or data.borderTexture ~= nil or data.borderSize ~= nil or data.borderOffset ~= nil then cfg.border = cfg.border or {} end
	if data.borderEnabled ~= nil then cfg.border.enabled = data.borderEnabled and true or false end
	if data.borderColor ~= nil then cfg.border.color = data.borderColor end
	if data.borderTexture ~= nil then cfg.border.texture = data.borderTexture end
	if data.borderSize ~= nil then cfg.border.edgeSize = data.borderSize end
	if data.borderOffset ~= nil then cfg.border.offset = data.borderOffset end
	if data.hoverHighlightEnabled ~= nil or data.hoverHighlightColor ~= nil or data.hoverHighlightTexture ~= nil or data.hoverHighlightSize ~= nil or data.hoverHighlightOffset ~= nil then
		cfg.highlightHover = cfg.highlightHover or {}
	end
	if data.hoverHighlightEnabled ~= nil then cfg.highlightHover.enabled = data.hoverHighlightEnabled and true or false end
	if data.hoverHighlightColor ~= nil then cfg.highlightHover.color = data.hoverHighlightColor end
	if data.hoverHighlightTexture ~= nil then cfg.highlightHover.texture = data.hoverHighlightTexture end
	if data.hoverHighlightSize ~= nil then cfg.highlightHover.size = clampNumber(data.hoverHighlightSize, 1, 64, cfg.highlightHover.size or 2) end
	if data.hoverHighlightOffset ~= nil then cfg.highlightHover.offset = clampNumber(data.hoverHighlightOffset, -64, 64, cfg.highlightHover.offset or 0) end
	if data.targetHighlightEnabled ~= nil or data.targetHighlightColor ~= nil or data.targetHighlightTexture ~= nil or data.targetHighlightSize ~= nil or data.targetHighlightOffset ~= nil then
		cfg.highlightTarget = cfg.highlightTarget or {}
	end
	if data.targetHighlightEnabled ~= nil then cfg.highlightTarget.enabled = data.targetHighlightEnabled and true or false end
	if data.targetHighlightColor ~= nil then cfg.highlightTarget.color = data.targetHighlightColor end
	if data.targetHighlightTexture ~= nil then cfg.highlightTarget.texture = data.targetHighlightTexture end
	if data.targetHighlightSize ~= nil then cfg.highlightTarget.size = clampNumber(data.targetHighlightSize, 1, 64, cfg.highlightTarget.size or 2) end
	if data.targetHighlightOffset ~= nil then cfg.highlightTarget.offset = clampNumber(data.targetHighlightOffset, -64, 64, cfg.highlightTarget.offset or 0) end
	if data.enabled ~= nil then cfg.enabled = data.enabled and true or false end
	if data.showName ~= nil then
		cfg.text = cfg.text or {}
		cfg.text.showName = data.showName and true or false
	end
	if data.nameClassColor ~= nil then
		cfg.text = cfg.text or {}
		cfg.text.useClassColor = data.nameClassColor and true or false
		cfg.status = cfg.status or {}
		cfg.status.nameColorMode = data.nameClassColor and "CLASS" or "CUSTOM"
	end
	if data.nameAnchor ~= nil then
		cfg.text = cfg.text or {}
		cfg.text.nameAnchor = data.nameAnchor
	end
	if data.nameOffsetX ~= nil or data.nameOffsetY ~= nil then
		cfg.text = cfg.text or {}
		cfg.text.nameOffset = cfg.text.nameOffset or {}
		if data.nameOffsetX ~= nil then cfg.text.nameOffset.x = data.nameOffsetX end
		if data.nameOffsetY ~= nil then cfg.text.nameOffset.y = data.nameOffsetY end
	end
	if data.nameMaxChars ~= nil then
		cfg.text = cfg.text or {}
		cfg.text.nameMaxChars = clampNumber(data.nameMaxChars, 0, 40, cfg.text.nameMaxChars or 0)
	end
	if data.nameFontSize ~= nil then
		cfg.text = cfg.text or {}
		cfg.text.fontSize = data.nameFontSize
	end
	if data.nameFont ~= nil then
		cfg.text = cfg.text or {}
		cfg.text.font = data.nameFont
	end
	if data.nameFontOutline ~= nil then
		cfg.text = cfg.text or {}
		cfg.text.fontOutline = data.nameFontOutline
	end
	if data.healthClassColor ~= nil or data.healthUseCustomColor ~= nil then cfg.health = cfg.health or {} end
	if data.healthUseCustomColor ~= nil then cfg.health.useCustomColor = data.healthUseCustomColor and true or false end
	if data.healthClassColor ~= nil then cfg.health.useClassColor = data.healthClassColor and true or false end
	if cfg.health and cfg.health.useCustomColor and cfg.health.useClassColor then
		if data.healthClassColor then
			cfg.health.useCustomColor = false
		elseif data.healthUseCustomColor then
			cfg.health.useClassColor = false
		else
			sanitizeHealthColorMode(cfg)
		end
	end
	if data.healthColor ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.color = data.healthColor
	end
	if data.healthTextLeft ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.textLeft = data.healthTextLeft
	end
	if data.healthTextCenter ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.textCenter = data.healthTextCenter
	end
	if data.healthTextRight ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.textRight = data.healthTextRight
	end
	if data.healthTextColor ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.textColor = data.healthTextColor
	end
	if data.healthDelimiter ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.textDelimiter = data.healthDelimiter
	end
	if data.healthDelimiterSecondary ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.textDelimiterSecondary = data.healthDelimiterSecondary
	end
	if data.healthDelimiterTertiary ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.textDelimiterTertiary = data.healthDelimiterTertiary
	end
	if data.healthShortNumbers ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.useShortNumbers = data.healthShortNumbers and true or false
	end
	if data.healthHidePercent ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.hidePercentSymbol = data.healthHidePercent and true or false
	end
	if data.healthFontSize ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.fontSize = data.healthFontSize
	end
	if data.healthFont ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.font = data.healthFont
	end
	if data.healthFontOutline ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.fontOutline = data.healthFontOutline
	end
	if data.healthTexture ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.texture = data.healthTexture
	end
	if data.healthBackdropEnabled ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.backdrop = cfg.health.backdrop or {}
		cfg.health.backdrop.enabled = data.healthBackdropEnabled and true or false
	end
	if data.healthBackdropColor ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.backdrop = cfg.health.backdrop or {}
		cfg.health.backdrop.color = data.healthBackdropColor
	end
	if data.healthLeftX ~= nil or data.healthLeftY ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.offsetLeft = cfg.health.offsetLeft or {}
		if data.healthLeftX ~= nil then cfg.health.offsetLeft.x = data.healthLeftX end
		if data.healthLeftY ~= nil then cfg.health.offsetLeft.y = data.healthLeftY end
	end
	if data.healthCenterX ~= nil or data.healthCenterY ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.offsetCenter = cfg.health.offsetCenter or {}
		if data.healthCenterX ~= nil then cfg.health.offsetCenter.x = data.healthCenterX end
		if data.healthCenterY ~= nil then cfg.health.offsetCenter.y = data.healthCenterY end
	end
	if data.healthRightX ~= nil or data.healthRightY ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.offsetRight = cfg.health.offsetRight or {}
		if data.healthRightX ~= nil then cfg.health.offsetRight.x = data.healthRightX end
		if data.healthRightY ~= nil then cfg.health.offsetRight.y = data.healthRightY end
	end
	if data.absorbEnabled ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.absorbEnabled = data.absorbEnabled and true or false
	end
	if data.absorbSample ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.showSampleAbsorb = data.absorbSample and true or false
	end
	if data.absorbTexture ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.absorbTexture = data.absorbTexture
	end
	if data.absorbReverse ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.absorbReverseFill = data.absorbReverse and true or false
	end
	if data.absorbUseCustomColor ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.absorbUseCustomColor = data.absorbUseCustomColor and true or false
	end
	if data.absorbColor ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.absorbColor = data.absorbColor
	end
	if data.healAbsorbEnabled ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.healAbsorbEnabled = data.healAbsorbEnabled and true or false
	end
	if data.healAbsorbSample ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.showSampleHealAbsorb = data.healAbsorbSample and true or false
	end
	if data.healAbsorbTexture ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.healAbsorbTexture = data.healAbsorbTexture
	end
	if data.healAbsorbReverse ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.healAbsorbReverseFill = data.healAbsorbReverse and true or false
	end
	if data.healAbsorbUseCustomColor ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.healAbsorbUseCustomColor = data.healAbsorbUseCustomColor and true or false
	end
	if data.healAbsorbColor ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.healAbsorbColor = data.healAbsorbColor
	end
	if
		data.nameColorMode ~= nil
		or data.nameColor ~= nil
		or data.levelEnabled ~= nil
		or data.levelColorMode ~= nil
		or data.levelColor ~= nil
		or data.hideLevelAtMax ~= nil
		or data.levelClassColor ~= nil
	then
		cfg.status = cfg.status or {}
	end
	if data.nameColorMode ~= nil then
		cfg.status.nameColorMode = data.nameColorMode
		cfg.text = cfg.text or {}
		cfg.text.useClassColor = data.nameColorMode == "CLASS"
	end
	if data.nameColor ~= nil then cfg.status.nameColor = data.nameColor end
	if data.levelEnabled ~= nil then cfg.status.levelEnabled = data.levelEnabled and true or false end
	if data.hideLevelAtMax ~= nil then cfg.status.hideLevelAtMax = data.hideLevelAtMax and true or false end
	if data.levelClassColor ~= nil then cfg.status.levelColorMode = data.levelClassColor and "CLASS" or "CUSTOM" end
	if data.levelColorMode ~= nil then cfg.status.levelColorMode = data.levelColorMode end
	if data.levelColor ~= nil then cfg.status.levelColor = data.levelColor end
	if data.levelFontSize ~= nil then cfg.status.levelFontSize = data.levelFontSize end
	if data.levelFont ~= nil then cfg.status.levelFont = data.levelFont end
	if data.levelFontOutline ~= nil then cfg.status.levelFontOutline = data.levelFontOutline end
	if data.levelAnchor ~= nil then cfg.status.levelAnchor = data.levelAnchor end
	if data.levelOffsetX ~= nil or data.levelOffsetY ~= nil then
		cfg.status.levelOffset = cfg.status.levelOffset or {}
		if data.levelOffsetX ~= nil then cfg.status.levelOffset.x = data.levelOffsetX end
		if data.levelOffsetY ~= nil then cfg.status.levelOffset.y = data.levelOffsetY end
	end
	if data.raidIconEnabled ~= nil or data.raidIconSize ~= nil or data.raidIconPoint ~= nil or data.raidIconOffsetX ~= nil or data.raidIconOffsetY ~= nil then
		cfg.status.raidIcon = cfg.status.raidIcon or {}
		if data.raidIconEnabled ~= nil then cfg.status.raidIcon.enabled = data.raidIconEnabled and true or false end
		if data.raidIconSize ~= nil then cfg.status.raidIcon.size = data.raidIconSize end
		if data.raidIconPoint ~= nil then
			cfg.status.raidIcon.point = data.raidIconPoint
			cfg.status.raidIcon.relativePoint = data.raidIconPoint
		end
		if data.raidIconOffsetX ~= nil then cfg.status.raidIcon.x = data.raidIconOffsetX end
		if data.raidIconOffsetY ~= nil then cfg.status.raidIcon.y = data.raidIconOffsetY end
	end
	if data.leaderIconEnabled ~= nil or data.leaderIconSize ~= nil or data.leaderIconPoint ~= nil or data.leaderIconOffsetX ~= nil or data.leaderIconOffsetY ~= nil then
		cfg.status.leaderIcon = cfg.status.leaderIcon or {}
		if data.leaderIconEnabled ~= nil then cfg.status.leaderIcon.enabled = data.leaderIconEnabled and true or false end
		if data.leaderIconSize ~= nil then cfg.status.leaderIcon.size = data.leaderIconSize end
		if data.leaderIconPoint ~= nil then
			cfg.status.leaderIcon.point = data.leaderIconPoint
			cfg.status.leaderIcon.relativePoint = data.leaderIconPoint
		end
		if data.leaderIconOffsetX ~= nil then cfg.status.leaderIcon.x = data.leaderIconOffsetX end
		if data.leaderIconOffsetY ~= nil then cfg.status.leaderIcon.y = data.leaderIconOffsetY end
	end
	if data.assistIconEnabled ~= nil or data.assistIconSize ~= nil or data.assistIconPoint ~= nil or data.assistIconOffsetX ~= nil or data.assistIconOffsetY ~= nil then
		cfg.status.assistIcon = cfg.status.assistIcon or {}
		if data.assistIconEnabled ~= nil then cfg.status.assistIcon.enabled = data.assistIconEnabled and true or false end
		if data.assistIconSize ~= nil then cfg.status.assistIcon.size = data.assistIconSize end
		if data.assistIconPoint ~= nil then
			cfg.status.assistIcon.point = data.assistIconPoint
			cfg.status.assistIcon.relativePoint = data.assistIconPoint
		end
		if data.assistIconOffsetX ~= nil then cfg.status.assistIcon.x = data.assistIconOffsetX end
		if data.assistIconOffsetY ~= nil then cfg.status.assistIcon.y = data.assistIconOffsetY end
	end
	if data.roleIconEnabled ~= nil then
		cfg.roleIcon = cfg.roleIcon or {}
		cfg.roleIcon.enabled = data.roleIconEnabled and true or false
	end
	if data.roleIconSize ~= nil then
		cfg.roleIcon = cfg.roleIcon or {}
		cfg.roleIcon.size = data.roleIconSize
	end
	if data.roleIconPoint ~= nil then
		cfg.roleIcon = cfg.roleIcon or {}
		cfg.roleIcon.point = data.roleIconPoint
		cfg.roleIcon.relativePoint = data.roleIconPoint
	end
	if data.roleIconOffsetX ~= nil or data.roleIconOffsetY ~= nil then
		cfg.roleIcon = cfg.roleIcon or {}
		if data.roleIconOffsetX ~= nil then cfg.roleIcon.x = data.roleIconOffsetX end
		if data.roleIconOffsetY ~= nil then cfg.roleIcon.y = data.roleIconOffsetY end
	end
	if data.roleIconStyle ~= nil then
		cfg.roleIcon = cfg.roleIcon or {}
		cfg.roleIcon.style = data.roleIconStyle
	end
	if data.roleIconRoles ~= nil then
		cfg.roleIcon = cfg.roleIcon or {}
		cfg.roleIcon.showRoles = copySelectionMap(data.roleIconRoles)
	end
	if data.powerRoles ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.showRoles = copySelectionMap(data.powerRoles)
	end
	if data.powerSpecs ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.showSpecs = copySelectionMap(data.powerSpecs)
	end
	if data.powerTextLeft ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.textLeft = data.powerTextLeft
	end
	if data.powerTextCenter ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.textCenter = data.powerTextCenter
	end
	if data.powerTextRight ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.textRight = data.powerTextRight
	end
	if data.powerDelimiter ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.textDelimiter = data.powerDelimiter
	end
	if data.powerDelimiterSecondary ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.textDelimiterSecondary = data.powerDelimiterSecondary
	end
	if data.powerDelimiterTertiary ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.textDelimiterTertiary = data.powerDelimiterTertiary
	end
	if data.powerShortNumbers ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.useShortNumbers = data.powerShortNumbers and true or false
	end
	if data.powerHidePercent ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.hidePercentSymbol = data.powerHidePercent and true or false
	end
	if data.powerFontSize ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.fontSize = data.powerFontSize
	end
	if data.powerFont ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.font = data.powerFont
	end
	if data.powerFontOutline ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.fontOutline = data.powerFontOutline
	end
	if data.powerTexture ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.texture = data.powerTexture
	end
	if data.powerBackdropEnabled ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.backdrop = cfg.power.backdrop or {}
		cfg.power.backdrop.enabled = data.powerBackdropEnabled and true or false
	end
	if data.powerBackdropColor ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.backdrop = cfg.power.backdrop or {}
		cfg.power.backdrop.color = data.powerBackdropColor
	end
	if data.powerLeftX ~= nil or data.powerLeftY ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.offsetLeft = cfg.power.offsetLeft or {}
		if data.powerLeftX ~= nil then cfg.power.offsetLeft.x = data.powerLeftX end
		if data.powerLeftY ~= nil then cfg.power.offsetLeft.y = data.powerLeftY end
	end
	if data.powerCenterX ~= nil or data.powerCenterY ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.offsetCenter = cfg.power.offsetCenter or {}
		if data.powerCenterX ~= nil then cfg.power.offsetCenter.x = data.powerCenterX end
		if data.powerCenterY ~= nil then cfg.power.offsetCenter.y = data.powerCenterY end
	end
	if data.powerRightX ~= nil or data.powerRightY ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.offsetRight = cfg.power.offsetRight or {}
		if data.powerRightX ~= nil then cfg.power.offsetRight.x = data.powerRightX end
		if data.powerRightY ~= nil then cfg.power.offsetRight.y = data.powerRightY end
	end

	local ac = ensureAuraConfig(cfg)
	if data.buffsEnabled ~= nil then ac.buff.enabled = data.buffsEnabled and true or false end
	if data.buffAnchor ~= nil then ac.buff.anchorPoint = data.buffAnchor end
	if data.buffGrowth ~= nil then
		applyAuraGrowth(ac.buff, data.buffGrowth)
	elseif data.buffGrowthX ~= nil or data.buffGrowthY ~= nil then
		if data.buffGrowthX ~= nil then ac.buff.growthX = data.buffGrowthX end
		if data.buffGrowthY ~= nil then ac.buff.growthY = data.buffGrowthY end
	end
	if data.buffOffsetX ~= nil then ac.buff.x = data.buffOffsetX end
	if data.buffOffsetY ~= nil then ac.buff.y = data.buffOffsetY end
	if data.buffSize ~= nil then ac.buff.size = data.buffSize end
	if data.buffPerRow ~= nil then ac.buff.perRow = data.buffPerRow end
	if data.buffMax ~= nil then ac.buff.max = data.buffMax end
	if data.buffSpacing ~= nil then ac.buff.spacing = data.buffSpacing end

	if data.debuffsEnabled ~= nil then ac.debuff.enabled = data.debuffsEnabled and true or false end
	if data.debuffAnchor ~= nil then ac.debuff.anchorPoint = data.debuffAnchor end
	if data.debuffGrowth ~= nil then
		applyAuraGrowth(ac.debuff, data.debuffGrowth)
	elseif data.debuffGrowthX ~= nil or data.debuffGrowthY ~= nil then
		if data.debuffGrowthX ~= nil then ac.debuff.growthX = data.debuffGrowthX end
		if data.debuffGrowthY ~= nil then ac.debuff.growthY = data.debuffGrowthY end
	end
	if data.debuffOffsetX ~= nil then ac.debuff.x = data.debuffOffsetX end
	if data.debuffOffsetY ~= nil then ac.debuff.y = data.debuffOffsetY end
	if data.debuffSize ~= nil then ac.debuff.size = data.debuffSize end
	if data.debuffPerRow ~= nil then ac.debuff.perRow = data.debuffPerRow end
	if data.debuffMax ~= nil then ac.debuff.max = data.debuffMax end
	if data.debuffSpacing ~= nil then ac.debuff.spacing = data.debuffSpacing end

	if data.externalsEnabled ~= nil then ac.externals.enabled = data.externalsEnabled and true or false end
	if data.externalAnchor ~= nil then ac.externals.anchorPoint = data.externalAnchor end
	if data.externalGrowth ~= nil then
		applyAuraGrowth(ac.externals, data.externalGrowth)
	elseif data.externalGrowthX ~= nil or data.externalGrowthY ~= nil then
		if data.externalGrowthX ~= nil then ac.externals.growthX = data.externalGrowthX end
		if data.externalGrowthY ~= nil then ac.externals.growthY = data.externalGrowthY end
	end
	if data.externalOffsetX ~= nil then ac.externals.x = data.externalOffsetX end
	if data.externalOffsetY ~= nil then ac.externals.y = data.externalOffsetY end
	if data.externalSize ~= nil then ac.externals.size = data.externalSize end
	if data.externalPerRow ~= nil then ac.externals.perRow = data.externalPerRow end
	if data.externalMax ~= nil then ac.externals.max = data.externalMax end
	if data.externalSpacing ~= nil then ac.externals.spacing = data.externalSpacing end
	if data.externalDrEnabled ~= nil then ac.externals.showDR = data.externalDrEnabled and true or false end
	if data.externalDrAnchor ~= nil then ac.externals.drAnchor = data.externalDrAnchor end
	if data.externalDrOffsetX ~= nil or data.externalDrOffsetY ~= nil then
		ac.externals.drOffset = ac.externals.drOffset or {}
		if data.externalDrOffsetX ~= nil then ac.externals.drOffset.x = data.externalDrOffsetX end
		if data.externalDrOffsetY ~= nil then ac.externals.drOffset.y = data.externalDrOffsetY end
	end
	if data.externalDrColor ~= nil then ac.externals.drColor = data.externalDrColor end
	if data.externalDrFontSize ~= nil then ac.externals.drFontSize = data.externalDrFontSize end
	if data.externalDrFont ~= nil then ac.externals.drFont = data.externalDrFont end
	if data.externalDrFontOutline ~= nil then ac.externals.drFontOutline = data.externalDrFontOutline end
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
		if data.columnSpacing ~= nil then cfg.columnSpacing = clampNumber(data.columnSpacing, 0, 40, cfg.columnSpacing or 0) end
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
			local rc = cfg.roleIcon or {}
			local sc = cfg.status or {}
			local lc = sc.leaderIcon or {}
			local acfg = sc.assistIcon or {}
			local hc = cfg.health or {}
			local def = DEFAULTS[kind] or {}
			local defH = def.health or {}
			local defP = def.power or {}
			local defAuras = def.auras or {}
			local defExt = defAuras.externals or {}
			local hcBackdrop = hc.backdrop or {}
			local defHBackdrop = defH.backdrop or {}
			local pcfgBackdrop = pcfg.backdrop or {}
			local defPBackdrop = defP.backdrop or {}
			local buffAnchor = ac.buff.anchorPoint or "TOPLEFT"
			local _, buffPrimary, buffSecondary = resolveAuraGrowth(buffAnchor, ac.buff.growth, ac.buff.growthX, ac.buff.growthY)
			local buffGrowth = growthPairToString(buffPrimary, buffSecondary)
			local debuffAnchor = ac.debuff.anchorPoint or "BOTTOMLEFT"
			local _, debuffPrimary, debuffSecondary = resolveAuraGrowth(debuffAnchor, ac.debuff.growth, ac.debuff.growthX, ac.debuff.growthY)
			local debuffGrowth = growthPairToString(debuffPrimary, debuffSecondary)
			local externalAnchor = ac.externals.anchorPoint or "TOPRIGHT"
			local _, externalPrimary, externalSecondary = resolveAuraGrowth(externalAnchor, ac.externals.growth, ac.externals.growthX, ac.externals.growthY)
			local externalGrowth = growthPairToString(externalPrimary, externalSecondary)
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
				barTexture = cfg.barTexture or BAR_TEX_INHERIT,
				borderEnabled = (cfg.border and cfg.border.enabled) ~= false,
				borderColor = (cfg.border and cfg.border.color) or (DEFAULTS[kind] and DEFAULTS[kind].border and DEFAULTS[kind].border.color) or { 0, 0, 0, 0.8 },
				borderTexture = (cfg.border and cfg.border.texture) or (DEFAULTS[kind] and DEFAULTS[kind].border and DEFAULTS[kind].border.texture) or "DEFAULT",
				borderSize = (cfg.border and cfg.border.edgeSize) or (DEFAULTS[kind] and DEFAULTS[kind].border and DEFAULTS[kind].border.edgeSize) or 1,
				borderOffset = (cfg.border and (cfg.border.offset or cfg.border.inset))
					or (DEFAULTS[kind] and DEFAULTS[kind].border and (DEFAULTS[kind].border.offset or DEFAULTS[kind].border.inset))
					or (cfg.border and cfg.border.edgeSize)
					or (DEFAULTS[kind] and DEFAULTS[kind].border and DEFAULTS[kind].border.edgeSize)
					or 1,
				hoverHighlightEnabled = (cfg.highlightHover and cfg.highlightHover.enabled) == true,
				hoverHighlightColor = (cfg.highlightHover and cfg.highlightHover.color) or (def.highlightHover and def.highlightHover.color) or { 1, 1, 1, 0.9 },
				hoverHighlightTexture = (cfg.highlightHover and cfg.highlightHover.texture) or (def.highlightHover and def.highlightHover.texture) or "DEFAULT",
				hoverHighlightSize = (cfg.highlightHover and cfg.highlightHover.size) or (def.highlightHover and def.highlightHover.size) or 2,
				hoverHighlightOffset = (cfg.highlightHover and cfg.highlightHover.offset) or (def.highlightHover and def.highlightHover.offset) or 0,
				targetHighlightEnabled = (cfg.highlightTarget and cfg.highlightTarget.enabled) == true,
				targetHighlightColor = (cfg.highlightTarget and cfg.highlightTarget.color) or (def.highlightTarget and def.highlightTarget.color) or { 1, 1, 0, 1 },
				targetHighlightTexture = (cfg.highlightTarget and cfg.highlightTarget.texture) or (def.highlightTarget and def.highlightTarget.texture) or "DEFAULT",
				targetHighlightSize = (cfg.highlightTarget and cfg.highlightTarget.size) or (def.highlightTarget and def.highlightTarget.size) or 2,
				targetHighlightOffset = (cfg.highlightTarget and cfg.highlightTarget.offset) or (def.highlightTarget and def.highlightTarget.offset) or 0,
				enabled = cfg.enabled == true,
				showPlayer = cfg.showPlayer == true,
				showSolo = cfg.showSolo == true,
				unitsPerColumn = cfg.unitsPerColumn or (DEFAULTS.raid and DEFAULTS.raid.unitsPerColumn) or 5,
				maxColumns = cfg.maxColumns or (DEFAULTS.raid and DEFAULTS.raid.maxColumns) or 8,
				columnSpacing = cfg.columnSpacing or (DEFAULTS.raid and DEFAULTS.raid.columnSpacing) or 0,
				showName = (cfg.text and cfg.text.showName) ~= false,
				nameClassColor = (cfg.text and cfg.text.useClassColor) ~= false,
				nameAnchor = (cfg.text and cfg.text.nameAnchor) or (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.nameAnchor) or "LEFT",
				nameOffsetX = (cfg.text and cfg.text.nameOffset and cfg.text.nameOffset.x) or 0,
				nameOffsetY = (cfg.text and cfg.text.nameOffset and cfg.text.nameOffset.y) or 0,
				nameMaxChars = (cfg.text and cfg.text.nameMaxChars) or (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.nameMaxChars) or 0,
				nameFontSize = (cfg.text and cfg.text.fontSize) or (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.fontSize) or 12,
				nameFont = (cfg.text and cfg.text.font) or (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.font) or nil,
				nameFontOutline = (cfg.text and cfg.text.fontOutline) or (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.fontOutline) or "OUTLINE",
				healthClassColor = (cfg.health and cfg.health.useClassColor) == true,
				healthUseCustomColor = (cfg.health and cfg.health.useCustomColor) == true,
				healthColor = (cfg.health and cfg.health.color) or ((DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.color) or { 0, 0.8, 0, 1 }),
				healthTextLeft = (cfg.health and cfg.health.textLeft) or ((DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textLeft) or "NONE"),
				healthTextCenter = (cfg.health and cfg.health.textCenter) or ((DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textCenter) or "NONE"),
				healthTextRight = (cfg.health and cfg.health.textRight) or ((DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textRight) or "NONE"),
				healthTextColor = (cfg.health and cfg.health.textColor) or ((DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textColor) or { 1, 1, 1, 1 }),
				healthDelimiter = (cfg.health and cfg.health.textDelimiter) or ((DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiter) or " "),
				healthDelimiterSecondary = (cfg.health and cfg.health.textDelimiterSecondary)
					or ((DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiterSecondary) or ((cfg.health and cfg.health.textDelimiter) or " ")),
				healthDelimiterTertiary = (cfg.health and cfg.health.textDelimiterTertiary)
					or (
						(DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiterTertiary)
						or ((cfg.health and cfg.health.textDelimiterSecondary) or (cfg.health and cfg.health.textDelimiter) or " ")
					),
				healthShortNumbers = (cfg.health and cfg.health.useShortNumbers) ~= false,
				healthHidePercent = (cfg.health and cfg.health.hidePercentSymbol) == true,
				healthFontSize = hc.fontSize or defH.fontSize or 12,
				healthFont = hc.font or defH.font or nil,
				healthFontOutline = hc.fontOutline or defH.fontOutline or "OUTLINE",
				healthTexture = hc.texture or defH.texture or "DEFAULT",
				healthBackdropEnabled = (hcBackdrop.enabled ~= nil) and (hcBackdrop.enabled ~= false) or (defHBackdrop.enabled ~= false),
				healthBackdropColor = hcBackdrop.color or defHBackdrop.color or { 0, 0, 0, 0.6 },
				healthLeftX = (cfg.health and cfg.health.offsetLeft and cfg.health.offsetLeft.x) or 0,
				healthLeftY = (cfg.health and cfg.health.offsetLeft and cfg.health.offsetLeft.y) or 0,
				healthCenterX = (cfg.health and cfg.health.offsetCenter and cfg.health.offsetCenter.x) or 0,
				healthCenterY = (cfg.health and cfg.health.offsetCenter and cfg.health.offsetCenter.y) or 0,
				healthRightX = (cfg.health and cfg.health.offsetRight and cfg.health.offsetRight.x) or 0,
				healthRightY = (cfg.health and cfg.health.offsetRight and cfg.health.offsetRight.y) or 0,
				absorbEnabled = (cfg.health and cfg.health.absorbEnabled) ~= false,
				absorbSample = hc.showSampleAbsorb == true,
				absorbTexture = (cfg.health and cfg.health.absorbTexture) or "SOLID",
				absorbReverse = (cfg.health and cfg.health.absorbReverseFill) == true,
				absorbUseCustomColor = (cfg.health and cfg.health.absorbUseCustomColor) == true,
				absorbColor = (cfg.health and cfg.health.absorbColor) or { 0.85, 0.95, 1, 0.7 },
				healAbsorbEnabled = (cfg.health and cfg.health.healAbsorbEnabled) ~= false,
				healAbsorbSample = hc.showSampleHealAbsorb == true,
				healAbsorbTexture = (cfg.health and cfg.health.healAbsorbTexture) or "SOLID",
				healAbsorbReverse = (cfg.health and cfg.health.healAbsorbReverseFill) == true,
				healAbsorbUseCustomColor = (cfg.health and cfg.health.healAbsorbUseCustomColor) == true,
				healAbsorbColor = (cfg.health and cfg.health.healAbsorbColor) or { 1, 0.3, 0.3, 0.7 },
				nameColorMode = sc.nameColorMode or "CLASS",
				nameColor = sc.nameColor or { 1, 1, 1, 1 },
				levelEnabled = sc.levelEnabled ~= false,
				hideLevelAtMax = sc.hideLevelAtMax == true,
				levelClassColor = (sc.levelColorMode or "CUSTOM") == "CLASS",
				levelColorMode = sc.levelColorMode or "CUSTOM",
				levelColor = sc.levelColor or { 1, 0.85, 0, 1 },
				levelFontSize = sc.levelFontSize or (cfg.text and cfg.text.fontSize) or (cfg.health and cfg.health.fontSize) or 12,
				levelFont = sc.levelFont or (cfg.text and cfg.text.font) or (cfg.health and cfg.health.font) or nil,
				levelFontOutline = sc.levelFontOutline or (cfg.text and cfg.text.fontOutline) or (cfg.health and cfg.health.fontOutline) or "OUTLINE",
				levelAnchor = sc.levelAnchor or "RIGHT",
				levelOffsetX = (sc.levelOffset and sc.levelOffset.x) or 0,
				levelOffsetY = (sc.levelOffset and sc.levelOffset.y) or 0,
				raidIconEnabled = (sc.raidIcon and sc.raidIcon.enabled) ~= false,
				raidIconSize = (sc.raidIcon and sc.raidIcon.size) or 18,
				raidIconPoint = (sc.raidIcon and sc.raidIcon.point) or "TOP",
				raidIconOffsetX = (sc.raidIcon and sc.raidIcon.x) or 0,
				raidIconOffsetY = (sc.raidIcon and sc.raidIcon.y) or -2,
				leaderIconEnabled = lc.enabled ~= false,
				leaderIconSize = lc.size or 12,
				leaderIconPoint = lc.point or "TOPLEFT",
				leaderIconOffsetX = lc.x or 0,
				leaderIconOffsetY = lc.y or 0,
				assistIconEnabled = acfg.enabled ~= false,
				assistIconSize = acfg.size or 12,
				assistIconPoint = acfg.point or "TOPLEFT",
				assistIconOffsetX = acfg.x or 0,
				assistIconOffsetY = acfg.y or 0,
				roleIconEnabled = rc.enabled ~= false,
				roleIconSize = rc.size or 14,
				roleIconPoint = rc.point or "LEFT",
				roleIconOffsetX = rc.x or 0,
				roleIconOffsetY = rc.y or 0,
				roleIconStyle = rc.style or "TINY",
				roleIconRoles = (type(rc.showRoles) == "table") and copySelectionMap(rc.showRoles) or defaultRoleSelection(),
				powerRoles = (type(pcfg.showRoles) == "table") and copySelectionMap(pcfg.showRoles) or defaultRoleSelection(),
				powerSpecs = (type(pcfg.showSpecs) == "table") and copySelectionMap(pcfg.showSpecs) or defaultSpecSelection(),
				powerTextLeft = pcfg.textLeft or ((DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textLeft) or "NONE"),
				powerTextCenter = pcfg.textCenter or ((DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textCenter) or "NONE"),
				powerTextRight = pcfg.textRight or ((DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textRight) or "NONE"),
				powerDelimiter = pcfg.textDelimiter or ((DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiter) or " "),
				powerDelimiterSecondary = pcfg.textDelimiterSecondary or ((DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiterSecondary) or (pcfg.textDelimiter or " ")),
				powerDelimiterTertiary = pcfg.textDelimiterTertiary
					or ((DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiterTertiary) or (pcfg.textDelimiterSecondary or pcfg.textDelimiter or " ")),
				powerShortNumbers = pcfg.useShortNumbers ~= false,
				powerHidePercent = pcfg.hidePercentSymbol == true,
				powerFontSize = pcfg.fontSize or defP.fontSize or 10,
				powerFont = pcfg.font or defP.font or nil,
				powerFontOutline = pcfg.fontOutline or defP.fontOutline or "OUTLINE",
				powerTexture = pcfg.texture or defP.texture or "DEFAULT",
				powerBackdropEnabled = (pcfgBackdrop.enabled ~= nil) and (pcfgBackdrop.enabled ~= false) or (defPBackdrop.enabled ~= false),
				powerBackdropColor = pcfgBackdrop.color or defPBackdrop.color or { 0, 0, 0, 0.6 },
				powerLeftX = (pcfg.offsetLeft and pcfg.offsetLeft.x) or 0,
				powerLeftY = (pcfg.offsetLeft and pcfg.offsetLeft.y) or 0,
				powerCenterX = (pcfg.offsetCenter and pcfg.offsetCenter.x) or 0,
				powerCenterY = (pcfg.offsetCenter and pcfg.offsetCenter.y) or 0,
				powerRightX = (pcfg.offsetRight and pcfg.offsetRight.x) or 0,
				powerRightY = (pcfg.offsetRight and pcfg.offsetRight.y) or 0,
				buffsEnabled = ac.buff.enabled == true,
				buffAnchor = buffAnchor,
				buffGrowth = buffGrowth,
				buffOffsetX = ac.buff.x or 0,
				buffOffsetY = ac.buff.y or 0,
				buffSize = ac.buff.size or 16,
				buffPerRow = ac.buff.perRow or 6,
				buffMax = ac.buff.max or 6,
				buffSpacing = ac.buff.spacing or 2,
				debuffsEnabled = ac.debuff.enabled == true,
				debuffAnchor = debuffAnchor,
				debuffGrowth = debuffGrowth,
				debuffOffsetX = ac.debuff.x or 0,
				debuffOffsetY = ac.debuff.y or 0,
				debuffSize = ac.debuff.size or 16,
				debuffPerRow = ac.debuff.perRow or 6,
				debuffMax = ac.debuff.max or 6,
				debuffSpacing = ac.debuff.spacing or 2,
				externalsEnabled = ac.externals.enabled == true,
				externalAnchor = externalAnchor,
				externalGrowth = externalGrowth,
				externalOffsetX = ac.externals.x or 0,
				externalOffsetY = ac.externals.y or 0,
				externalSize = ac.externals.size or 16,
				externalPerRow = ac.externals.perRow or 6,
				externalMax = ac.externals.max or 4,
				externalSpacing = ac.externals.spacing or 2,
				externalDrEnabled = ac.externals.showDR == true,
				externalDrAnchor = ac.externals.drAnchor or defExt.drAnchor or "TOPLEFT",
				externalDrOffsetX = (ac.externals.drOffset and ac.externals.drOffset.x) or (defExt.drOffset and defExt.drOffset.x) or 0,
				externalDrOffsetY = (ac.externals.drOffset and ac.externals.drOffset.y) or (defExt.drOffset and defExt.drOffset.y) or 0,
				externalDrColor = ac.externals.drColor or defExt.drColor or { 1, 1, 1, 1 },
				externalDrFontSize = ac.externals.drFontSize or defExt.drFontSize or 10,
				externalDrFont = ac.externals.drFont or defExt.drFont or nil,
				externalDrFontOutline = ac.externals.drFontOutline or defExt.drFontOutline or "OUTLINE",
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
				collapseExclusive = true,
				settingsMaxHeight = 700,
			})

			if addon.EditModeLib and addon.EditModeLib.SetFrameResetVisible then addon.EditModeLib:SetFrameResetVisible(anchor, false) end
		end
	end

	GF._editModeRegistered = true
	if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RefreshSettingValues then addon.EditModeLib.internal:RefreshSettingValues() end
end

function GF:OnEnterEditMode(kind)
	if not isFeatureEnabled() then return end
	GF:EnsureHeaders()
	local header = GF.headers and GF.headers[kind]
	if not header then return end
	if kind == "party" and not (InCombatLockdown and InCombatLockdown()) then
		header._eqolForceShow = nil
		header._eqolForceHide = true
		GF._previewActive = GF._previewActive or {}
		GF._previewActive[kind] = true
		GF:EnsurePreviewFrames(kind)
		GF:UpdatePreviewLayout(kind)
		GF:ShowPreviewFrames(kind, true)
		GF:ApplyHeaderAttributes(kind)
	else
		header._eqolForceHide = nil
		header._eqolForceShow = true
		GF:ApplyHeaderAttributes(kind)
	end
end

function GF:OnExitEditMode(kind)
	if not isFeatureEnabled() then return end
	GF:EnsureHeaders()
	local header = GF.headers and GF.headers[kind]
	if not header then return end
	if kind == "party" then
		if GF._previewActive then GF._previewActive[kind] = nil end
		GF:ShowPreviewFrames(kind, false)
		header._eqolForceHide = nil
	end
	header._eqolForceShow = nil
	GF:ApplyHeaderAttributes(kind)
end

-- -----------------------------------------------------------------------------
-- Bootstrap
-- -----------------------------------------------------------------------------

registerFeatureEvents = function(frame)
	if not frame then return end
	if frame.RegisterEvent then
		frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		frame:RegisterEvent("GROUP_ROSTER_UPDATE")
		frame:RegisterEvent("PARTY_LEADER_CHANGED")
		frame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
		frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		frame:RegisterEvent("RAID_TARGET_UPDATE")
		frame:RegisterEvent("PLAYER_TARGET_CHANGED")
	end
end

unregisterFeatureEvents = function(frame)
	if not frame then return end
	if frame.UnregisterEvent then
		frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
		frame:UnregisterEvent("GROUP_ROSTER_UPDATE")
		frame:UnregisterEvent("PARTY_LEADER_CHANGED")
		frame:UnregisterEvent("PLAYER_ROLES_ASSIGNED")
		frame:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		frame:UnregisterEvent("RAID_TARGET_UPDATE")
		frame:UnregisterEvent("PLAYER_TARGET_CHANGED")
	end
end

do
	local f = CreateFrame("Frame")
	GF._eventFrame = f
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_LOGIN" then
			if isFeatureEnabled() then
				registerFeatureEvents(f)
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
		elseif not isFeatureEnabled() then
			return
		elseif event == "RAID_TARGET_UPDATE" then
			GF:RefreshRaidIcons()
		elseif event == "PLAYER_TARGET_CHANGED" then
			GF:RefreshTargetHighlights()
		elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "PARTY_LEADER_CHANGED" then
			GF:RefreshRoleIcons()
			GF:RefreshGroupIcons()
		elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
			GF:RefreshPowerVisibility()
		end
	end)
end
