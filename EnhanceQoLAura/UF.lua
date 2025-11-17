local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Aura = addon.Aura or {}
local UF = {}
addon.Aura.UF = UF
UF.ui = UF.ui or {}

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")
local LSM = LibStub("LibSharedMedia-3.0")
local AceGUI = addon.AceGUI or LibStub("AceGUI-3.0")
local BLIZZARD_TEX = "Interface\\TargetingFrame\\UI-StatusBar"
local atlasByPower = {
	LUNAR_POWER = "Unit_Druid_AstralPower_Fill",
	MAELSTROM = "Unit_Shaman_Maelstrom_Fill",
	INSANITY = "Unit_Priest_Insanity_Fill",
	FURY = "Unit_DemonHunter_Fury_Fill",
	RUNIC_POWER = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-RunicPower",
	ENERGY = "UI-HUD-UnitFrame-Player-PortraitOn-ClassResource-Bar-Energy",
	FOCUS = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Focus",
	RAGE = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Rage",
	MANA = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana",
	HEALTH = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health",
}

local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitPower, UnitPowerMax, UnitPowerType = UnitPower, UnitPowerMax, UnitPowerType
local UnitName, UnitClass, UnitLevel = UnitName, UnitClass, UnitLevel
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs or function() return 0 end
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local CUSTOM_CLASS_COLORS = CUSTOM_CLASS_COLORS
local CopyTable = CopyTable
local UIParent = UIParent
local CreateFrame = CreateFrame
local IsShiftKeyDown = IsShiftKeyDown
local After = C_Timer and C_Timer.After
local floor = math.floor
local max = math.max
local abs = math.abs

local PLAYER_UNIT = "player"
local FRAME_NAME = "EQOLUFPlayerFrame"
local HEALTH_NAME = "EQOLUFPlayerHealth"
local POWER_NAME = "EQOLUFPlayerPower"
local STATUS_NAME = "EQOLUFPlayerStatus"
local MIN_WIDTH = 50

local issecretvalue = _G.issecretvalue

local function shortValue(val)
	if val == nil then return "" end
	if addon.variables and addon.variables.isMidnight then return AbbreviateNumbers(val) end
	local absVal = abs(val)
	if absVal >= 1e9 then
		return ("%.1fB"):format(val / 1e9):gsub("%.0B", "B")
	elseif absVal >= 1e6 then
		return ("%.1fM"):format(val / 1e6):gsub("%.0M", "M")
	elseif absVal >= 1e3 then
		return ("%.1fK"):format(val / 1e3):gsub("%.0K", "K")
	end
	return tostring(floor(val + 0.5))
end

local defaults = {
	player = {
		enabled = true,
		width = 220,
		healthHeight = 24,
		powerHeight = 16,
		statusHeight = 18,
		anchor = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 0, y = -200 },
		strata = nil,
		frameLevel = nil,
		barGap = 0,
		border = { enabled = true, color = { 0, 0, 0, 0.8 }, edgeSize = 1, inset = 0 },
		health = {
			useClassColor = true,
			color = { 0.0, 0.8, 0.0, 1 },
			absorbColor = { 0.85, 0.95, 1.0, 0.7 },
			backdrop = { enabled = true, color = { 0, 0, 0, 0.6 } },
			textLeft = "PERCENT",
			textRight = "CURMAX",
			fontSize = 14,
			font = nil,
			fontOutline = "OUTLINE", -- fallback to default font
			fontOutline = "OUTLINE",
			offsetLeft = { x = 6, y = 0 },
			offsetRight = { x = -6, y = 0 },
			useShortNumbers = true,
			texture = "DEFAULT",
		},
		power = {
			color = { 0.1, 0.45, 1, 1 },
			backdrop = { enabled = true, color = { 0, 0, 0, 0.6 } },
			textLeft = "PERCENT",
			textRight = "CURMAX",
			fontSize = 14,
			font = nil,
			offsetLeft = { x = 6, y = 0 },
			offsetRight = { x = -6, y = 0 },
			useShortNumbers = true,
			texture = "DEFAULT",
		},
		status = {
			enabled = true,
			fontSize = 14,
			font = nil,
			nameColorMode = "CLASS", -- CLASS or CUSTOM
			nameColor = { 0.8, 0.8, 1, 1 },
			levelColor = { 1, 0.85, 0, 1 },
			nameOffset = { x = 0, y = 0 },
			levelOffset = { x = 0, y = 0 },
			levelEnabled = true,
		},
	},
}

local state = {
	frame = nil,
	health = nil,
	power = nil,
	absorb = nil,
	status = nil,
	nameText = nil,
	levelText = nil,
	healthTextLeft = nil,
	healthTextRight = nil,
	powerTextLeft = nil,
	powerTextRight = nil,
}

local function ensureDB(unit)
	addon.db = addon.db or {}
	addon.db.ufFrames = addon.db.ufFrames or {}
	local db = addon.db.ufFrames
	db[unit] = db[unit] or {}
	local udb = db[unit]
	-- seed defaults
	for k, v in pairs(defaults.player) do
		if udb[k] == nil then
			udb[k] = type(v) == "table" and addon.functions.copyTable and addon.functions.copyTable(v) or (type(v) == "table" and CopyTable(v) or v)
			if not udb[k] and type(v) == "table" then udb[k] = CopyTable(v) end
		end
	end
	return udb
end

local function getFont(path)
	if path and path ~= "" then return path end
	return addon.variables and addon.variables.defaultFont or (LSM and LSM:Fetch("font", LSM.DefaultMedia.font)) or STANDARD_TEXT_FONT
end

local function setBackdrop(frame, borderCfg)
	if not frame then return end
	if borderCfg and borderCfg.enabled then
		local color = borderCfg.color or { 0, 0, 0, 0.8 }
		local insetVal = borderCfg.inset
		if insetVal == nil then insetVal = borderCfg.edgeSize or 1 end
		frame:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = borderCfg.edgeSize or 1,
			insets = { left = insetVal, right = insetVal, top = insetVal, bottom = insetVal },
		})
		frame:SetBackdropColor(0, 0, 0, 0)
		frame:SetBackdropBorderColor(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
	else
		frame:SetBackdrop(nil)
	end
end

local function applyBarBackdrop(bar, cfg)
	if not bar then return end
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

local UnitHealthPercent = UnitHealthPercent
local UnitPowerPercent = UnitPowerPercent

local function resolveTexture(key)
	if not key or key == "DEFAULT" then return BLIZZARD_TEX end
	if LSM then
		local tex = LSM:Fetch("statusbar", key)
		if tex then return tex end
	end
	return key
end

local function configureSpecialTexture(bar, pType, texKey, cfg)
	if not bar or not pType then return end
	local atlas = atlasByPower[pType]
	if not atlas then return end
	if texKey and texKey ~= "" and texKey ~= "DEFAULT" then return end
	cfg = cfg or bar._cfg
	local tex = bar:GetStatusBarTexture()
	if tex and tex.SetAtlas then
		local currentAtlas = tex.GetAtlas and tex:GetAtlas()
		if currentAtlas ~= atlas then tex:SetAtlas(atlas, true) end
		if tex.SetHorizTile then tex:SetHorizTile(false) end
		if tex.SetVertTile then tex:SetVertTile(false) end
	end
end

local function formatText(mode, cur, maxv, useShort, percentValue)
	if mode == "NONE" then return "" end
	if addon.variables and addon.variables.isMidnight and issecretvalue then
		if (cur and issecretvalue(cur)) or (maxv and issecretvalue(maxv)) then
			local scur = useShort and shortValue(cur) or BreakUpLargeNumbers(cur)
			local smax = useShort and shortValue(maxv) or BreakUpLargeNumbers(maxv)

			if mode == "CURRENT" then return tostring(scur) end
			if mode == "CURMAX" then return ("%s / %s"):format(tostring(scur), tostring(smax)) end
			if mode == "PERCENT" then
				if percentValue ~= nil then return ("%s%%"):format(tostring(AbbreviateLargeNumbers(percentValue))) end
			end
			return ""
		end
	end
	if mode == "PERCENT" then
		if percentValue ~= nil then return ("%d%%"):format(floor(percentValue + 0.5)) end
		if not maxv or maxv == 0 then return "0%" end
		return ("%d%%"):format(floor((cur or 0) / maxv * 100 + 0.5))
	end
	if mode == "CURMAX" then
		if useShort == false then return ("%s / %s"):format(tostring(cur or 0), tostring(maxv or 0)) end
		return ("%s / %s"):format(shortValue(cur or 0), shortValue(maxv or 0))
	end
	if useShort == false then return tostring(cur or 0) end
	return shortValue(cur or 0)
end

local function updateHealth(cfg)
	if not state.health or not state.frame then return end
	local cur = UnitHealth(PLAYER_UNIT)
	local maxv = UnitHealthMax(PLAYER_UNIT)
	state.health:SetMinMaxValues(0, maxv > 0 and maxv or 1)
	state.health:SetValue(cur or 0)
	local hc = cfg.health or {}
	configureSpecialTexture(state.health, "HEALTH", hc.texture, hc)
	local percentVal
	if addon.variables and addon.variables.isMidnight and UnitHealthPercent then
		percentVal = UnitHealthPercent(PLAYER_UNIT, true, true)
	else
		if (not addon.variables or not addon.variables.isMidnight or not issecretvalue or (not issecretvalue(cur) and not issecretvalue(maxv))) and maxv and maxv > 0 then
			percentVal = (cur or 0) / maxv * 100
		end
	end
	local hr, hg, hb, ha
	if hc.useClassColor then
		local class = select(2, UnitClass(PLAYER_UNIT))
		local c = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
		if c then
			hr, hg, hb, ha = c.r or c[1], c.g or c[2], c.b or c[3], c.a or c[4]
		end
	end
	if not hr then
		local color = hc.color or { 0, 0.8, 0, 1 }
		hr, hg, hb, ha = color[1] or 0, color[2] or 0.8, color[3] or 0, color[4] or 1
	end
	state.health:SetStatusBarColor(hr or 0, hg or 0.8, hb or 0, ha or 1)
	if hc.useClassColor then
		if state.health.SetStatusBarDesaturated then state.health:SetStatusBarDesaturated(true) end
	else
		if state.health.SetStatusBarDesaturated then state.health:SetStatusBarDesaturated(false) end
	end
	if state.absorb then
		local abs = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(PLAYER_UNIT) or 0
		state.absorb:SetMinMaxValues(0, maxv > 0 and maxv or 1)
		state.absorb:SetValue(abs or 0)
		local ac = hc.absorbColor or { 0.85, 0.95, 1, 0.7 }
		state.absorb:SetStatusBarColor(ac[1] or 0.85, ac[2] or 0.95, ac[3] or 1, ac[4] or 0.7)
	end
	if state.healthTextLeft then state.healthTextLeft:SetText(formatText(hc.textLeft or "PERCENT", cur, maxv, hc.useShortNumbers ~= false, percentVal)) end
	if state.healthTextRight then state.healthTextRight:SetText(formatText(hc.textRight or "CURMAX", cur, maxv, hc.useShortNumbers ~= false, percentVal)) end
end

local function updatePower(cfg)
	local bar = state.power
	if not bar then return end
	local cur = UnitPower(PLAYER_UNIT)
	local maxv = UnitPowerMax(PLAYER_UNIT)
	bar:SetMinMaxValues(0, maxv > 0 and maxv or 1)
	bar:SetValue(cur or 0)
	local pcfg = cfg.power or {}
	local _, powerToken = UnitPowerType(PLAYER_UNIT)
	configureSpecialTexture(bar, powerToken, pcfg.texture, pcfg)
	local percentVal
	if addon.variables and addon.variables.isMidnight and UnitPowerPercent then
		percentVal = UnitPowerPercent(PLAYER_UNIT, nil, true, true)
	else
		if (not addon.variables or not addon.variables.isMidnight or not issecretvalue or (not issecretvalue(cur) and not issecretvalue(maxv))) and maxv and maxv > 0 then
			percentVal = (cur or 0) / maxv * 100
		end
	end
	local c = pcfg.color or { 0.1, 0.45, 1, 1 }
	bar:SetStatusBarColor(c[1] or 0.1, c[2] or 0.45, c[3] or 1, c[4] or 1)
	if state.powerTextLeft then state.powerTextLeft:SetText(formatText(pcfg.textLeft or "PERCENT", cur, maxv, pcfg.useShortNumbers ~= false, percentVal)) end
	if state.powerTextRight then state.powerTextRight:SetText(formatText(pcfg.textRight or "CURMAX", cur, maxv, pcfg.useShortNumbers ~= false, percentVal)) end
end

local function applyFont(fs, fontPath, size, outline)
	if not fs then return end
	fs:SetFont(getFont(fontPath), size or 14, outline or "OUTLINE")
	fs:SetShadowColor(0, 0, 0, 0.5)
	fs:SetShadowOffset(0.5, -0.5)
end

local function layoutTexts(bar, leftFS, rightFS, cfg, width)
	if not bar then return end
	local leftCfg = (cfg and cfg.offsetLeft) or { x = 6, y = 0 }
	local rightCfg = (cfg and cfg.offsetRight) or { x = -6, y = 0 }
	if leftFS then
		leftFS:ClearAllPoints()
		leftFS:SetPoint("LEFT", bar, "LEFT", leftCfg.x or 0, leftCfg.y or 0)
	end
	if rightFS then
		rightFS:ClearAllPoints()
		rightFS:SetPoint("RIGHT", bar, "RIGHT", rightCfg.x or 0, rightCfg.y or 0)
	end
end

local function updateStatus(cfg)
	if not state.status then return end
	local scfg = cfg.status or {}
	state.status:SetHeight((cfg.status and cfg.status.enabled) and (cfg.statusHeight or defaults.player.statusHeight) or 0.001)
	state.status:SetShown(scfg.enabled ~= false)
	if state.nameText then
	applyFont(state.nameText, scfg.font, scfg.fontSize or 14, scfg.fontOutline)
		local class = select(2, UnitClass(PLAYER_UNIT))
		local nc
		if scfg.nameColorMode == "CLASS" then
			nc = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
		else
			nc = scfg.nameColor or { 1, 1, 1, 1 }
		end
		state.nameText:SetText(UnitName(PLAYER_UNIT) or "")
		state.nameText:SetTextColor(nc and (nc.r or nc[1] or 1) or 1, nc and (nc.g or nc[2] or 1) or 1, nc and (nc.b or nc[3] or 1) or 1, nc and (nc.a or nc[4] or 1) or 1)
		state.nameText:ClearAllPoints()
		state.nameText:SetPoint(scfg.nameAnchor or "LEFT", state.status, scfg.nameAnchor or "LEFT", (scfg.nameOffset and scfg.nameOffset.x) or 0, (scfg.nameOffset and scfg.nameOffset.y) or 0)
		state.nameText:SetShown(scfg.enabled ~= false)
	end
	if state.levelText then
	applyFont(state.levelText, scfg.font, scfg.fontSize or 14, scfg.fontOutline)
		local lc = scfg.levelColor or { 1, 0.85, 0, 1 }
		state.levelText:SetText(UnitLevel(PLAYER_UNIT) or "")
		state.levelText:SetTextColor(lc[1] or 1, lc[2] or 0.85, lc[3] or 0, lc[4] or 1)
		state.levelText:ClearAllPoints()
		state.levelText:SetPoint(scfg.levelAnchor or "RIGHT", state.status, scfg.levelAnchor or "RIGHT", (scfg.levelOffset and scfg.levelOffset.x) or 0, (scfg.levelOffset and scfg.levelOffset.y) or 0)
		state.levelText:SetShown(scfg.enabled ~= false and scfg.levelEnabled ~= false)
	end
end

local function layoutFrame(cfg)
	if not state.frame then return end
	local width = max(MIN_WIDTH, cfg.width or defaults.player.width)
	local statusHeight = (cfg.status and cfg.status.enabled == false) and 0 or (cfg.statusHeight or defaults.player.statusHeight)
	local healthHeight = cfg.healthHeight or defaults.player.healthHeight
	local powerHeight = cfg.powerHeight or defaults.player.powerHeight
	local barGap = cfg.barGap or 0
	local borderInset = 0
	if cfg.border and cfg.border.enabled then borderInset = (cfg.border.edgeSize or 1) end
	state.frame:SetWidth(width + borderInset * 2)
	if cfg.strata then
		state.frame:SetFrameStrata(cfg.strata)
	else
		local pf = _G.PlayerFrame
		if pf and pf.GetFrameStrata then state.frame:SetFrameStrata(pf:GetFrameStrata()) end
	end
	if cfg.frameLevel then
		state.frame:SetFrameLevel(cfg.frameLevel)
	else
		local pf = _G.PlayerFrame
		if pf and pf.GetFrameLevel then state.frame:SetFrameLevel(pf:GetFrameLevel()) end
	end
	state.status:SetHeight(statusHeight)
	state.health:SetSize(width, healthHeight)
	state.power:SetSize(width, powerHeight)

	state.status:ClearAllPoints()
	if state.barGroup then state.barGroup:ClearAllPoints() end
	state.health:ClearAllPoints()
	state.power:ClearAllPoints()

	local anchor = cfg.anchor or defaults.player.anchor
	local rel = (anchor and _G[anchor.relativeTo]) or UIParent
	state.frame:ClearAllPoints()
	state.frame:SetPoint(anchor.point or "CENTER", rel or UIParent, anchor.relativePoint or anchor.point or "CENTER", anchor.x or 0, anchor.y or 0)

	local y = 0
	if statusHeight > 0 then
		state.status:SetPoint("TOPLEFT", state.frame, "TOPLEFT", 0, 0)
		state.status:SetPoint("TOPRIGHT", state.frame, "TOPRIGHT", 0, 0)
		y = -statusHeight
	else
		state.status:SetPoint("TOPLEFT", state.frame, "TOPLEFT", 0, 0)
		state.status:SetPoint("TOPRIGHT", state.frame, "TOPRIGHT", 0, 0)
	end
	-- Bars container sits below status; border applied here, not on status
	local barsHeight = healthHeight + powerHeight + barGap + borderInset * 2
	if state.barGroup then
		state.barGroup:SetWidth(width + borderInset * 2)
		state.barGroup:SetHeight(barsHeight)
		state.barGroup:SetPoint("TOPLEFT", state.frame, "TOPLEFT", 0, y)
		state.barGroup:SetPoint("TOPRIGHT", state.frame, "TOPRIGHT", 0, y)
	end

	state.health:SetPoint("TOPLEFT", state.barGroup or state.frame, "TOPLEFT", borderInset, -borderInset)
	state.health:SetPoint("TOPRIGHT", state.barGroup or state.frame, "TOPRIGHT", -borderInset, -borderInset)
	state.power:SetPoint("TOPLEFT", state.health, "BOTTOMLEFT", 0, -barGap)
	state.power:SetPoint("TOPRIGHT", state.health, "BOTTOMRIGHT", 0, -barGap)

	local totalHeight = statusHeight + barsHeight
	state.frame:SetHeight(totalHeight)

	layoutTexts(state.health, state.healthTextLeft, state.healthTextRight, cfg.health, width)
	layoutTexts(state.power, state.powerTextLeft, state.powerTextRight, cfg.power, width)

	-- Apply border only around the bar region wrapper
	if state.barGroup then setBackdrop(state.barGroup, cfg.border) end
end

local function ensureFrames()
	if state.frame then return end
	state.frame = _G[FRAME_NAME] or CreateFrame("Button", FRAME_NAME, UIParent, "BackdropTemplate,SecureUnitButtonTemplate")
	state.frame:SetAttribute("unit", "player")
	state.frame:SetAttribute("type1", "target")
	state.frame:SetAttribute("type2", "togglemenu")
	state.frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	state.frame.menu = function(self) ToggleDropDownMenu(1, nil, PlayerFrameDropDown, self, 0, 0) end
	state.frame:SetClampedToScreen(true)
	state.status = _G[STATUS_NAME] or CreateFrame("Frame", STATUS_NAME, state.frame)
	state.barGroup = state.barGroup or CreateFrame("Frame", nil, state.frame, "BackdropTemplate")
	state.health = _G[HEALTH_NAME] or CreateFrame("StatusBar", HEALTH_NAME, state.barGroup, "BackdropTemplate")
	state.power = _G[POWER_NAME] or CreateFrame("StatusBar", POWER_NAME, state.barGroup, "BackdropTemplate")
	state.absorb = CreateFrame("StatusBar", HEALTH_NAME .. "Absorb", state.health, "BackdropTemplate")

	state.healthTextLeft = state.health:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	state.healthTextRight = state.health:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	state.powerTextLeft = state.power:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	state.powerTextRight = state.power:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	state.nameText = state.status:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	state.levelText = state.status:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

	state.frame:SetMovable(true)
	state.frame:EnableMouse(true)
	state.frame:RegisterForDrag("LeftButton")
	state.frame:SetScript("OnDragStart", function(self)
		if InCombatLockdown() then return end
		if IsShiftKeyDown() then self:StartMoving() end
	end)
	state.frame:SetScript("OnDragStop", function(self)
		if InCombatLockdown() then return end
		self:StopMovingOrSizing()
		local point, rel, relPoint, x, y = self:GetPoint(1)
		local cfg = ensureDB("player")
		cfg.anchor = cfg.anchor or {}
		cfg.anchor.point = point
		cfg.anchor.relativeTo = (rel and rel.GetName and rel:GetName()) or "UIParent"
		cfg.anchor.relativePoint = relPoint
		cfg.anchor.x = x
		cfg.anchor.y = y
	end)
end

local function applyBars(cfg)
	local hc = cfg.health or {}
	local pcfg = cfg.power or {}
	state.health:SetStatusBarTexture(resolveTexture(hc.texture))
	configureSpecialTexture(state.health, "HEALTH", hc.texture, hc)
	applyBarBackdrop(state.health, hc)
	state.power:SetStatusBarTexture(resolveTexture(pcfg.texture))
	local _, powerToken = UnitPowerType(PLAYER_UNIT)
	configureSpecialTexture(state.power, powerToken, pcfg.texture, pcfg)
	applyBarBackdrop(state.power, pcfg)
	state.absorb:SetStatusBarTexture(LSM and LSM:Fetch("statusbar", "Blizzard") or BLIZZARD_TEX)
	state.absorb:SetAllPoints(state.health)
	state.absorb:SetFrameLevel(state.health:GetFrameLevel() + 1)
	state.absorb:SetMinMaxValues(0, 1)
	state.absorb:SetValue(0)
	state.absorb:SetStatusBarColor(0.8, 0.8, 0.9, 0.6)

	applyFont(state.healthTextLeft, hc.font, hc.fontSize or 14)
	applyFont(state.healthTextRight, hc.font, hc.fontSize or 14)
	applyFont(state.powerTextLeft, pcfg.font, pcfg.fontSize or 14)
	applyFont(state.powerTextRight, pcfg.font, pcfg.fontSize or 14)
	applyFont(state.nameText, cfg.status.font, cfg.status.fontSize or 14, cfg.status.fontOutline)
	applyFont(state.levelText, cfg.status.font, cfg.status.fontSize or 14, cfg.status.fontOutline)
end

local function updateNameAndLevel(cfg)
	if state.nameText then
		local scfg = cfg.status or {}
		local class = select(2, UnitClass(PLAYER_UNIT))
		local nc
		if scfg.nameColorMode == "CLASS" then
			nc = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
		else
			nc = scfg.nameColor or { 1, 1, 1, 1 }
		end
		state.nameText:SetText(UnitName(PLAYER_UNIT) or "")
		state.nameText:SetTextColor(nc and (nc.r or nc[1]) or 1, nc and (nc.g or nc[2]) or 1, nc and (nc.b or nc[3]) or 1, nc and (nc.a or nc[4]) or 1)
	end
	if state.levelText then
		local scfg = cfg.status or {}
		local enabled = scfg.levelEnabled ~= false
		state.levelText:SetShown(enabled)
		if enabled then
			local lc = scfg.levelColor or { 1, 0.85, 0, 1 }
			state.levelText:SetText(UnitLevel(PLAYER_UNIT) or "")
			state.levelText:SetTextColor(lc[1] or 1, lc[2] or 0.85, lc[3] or 0, lc[4] or 1)
		end
	end
end

local function applyConfig()
	local cfg = ensureDB("player")
	if not cfg.enabled then
		if state.frame then state.frame:Hide() end
		return
	end
	ensureFrames()
	applyBars(cfg)
	layoutFrame(cfg)
	updateStatus(cfg)
	updateNameAndLevel(cfg)
	updateHealth(cfg)
	updatePower(cfg)
	state.frame:Show()
end

local function hideBlizzardPlayerFrame()
	if not _G.PlayerFrame then return end
	_G.PlayerFrame:Hide()
	_G.PlayerFrame:HookScript("OnShow", _G.PlayerFrame.Hide)
end

local unitEvents = {
	"UNIT_HEALTH",
	"UNIT_MAXHEALTH",
	"UNIT_ABSORB_AMOUNT_CHANGED",
	"UNIT_POWER_UPDATE",
	"UNIT_MAXPOWER",
	"UNIT_DISPLAYPOWER",
	"UNIT_NAME_UPDATE",
}

local generalEvents = {
	"PLAYER_ENTERING_WORLD",
	"PLAYER_LEVEL_UP",
	"PLAYER_DEAD",
	"PLAYER_ALIVE",
}

local eventFrame

local function onEvent(self, event, unit)
	if event == "PLAYER_ENTERING_WORLD" then
		applyConfig()
		hideBlizzardPlayerFrame()
	elseif event == "PLAYER_DEAD" then
		state.health:SetValue(0)
		updateHealth(ensureDB("player"))
	elseif event == "PLAYER_ALIVE" then
		updateHealth(ensureDB("player"))
		updatePower(ensureDB("player"))
	elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
		if unit == PLAYER_UNIT then updateHealth(ensureDB("player")) end
	elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
		if unit == PLAYER_UNIT then updatePower(ensureDB("player")) end
	elseif event == "UNIT_NAME_UPDATE" or event == "PLAYER_LEVEL_UP" then
		updateNameAndLevel(ensureDB("player"))
	end
end

function UF.Enable()
	local cfg = ensureDB("player")
	cfg.enabled = true
	applyConfig()
	if not eventFrame then
		eventFrame = CreateFrame("Frame")
		for _, evt in ipairs(unitEvents) do
			eventFrame:RegisterUnitEvent(evt, PLAYER_UNIT)
		end
		for _, evt in ipairs(generalEvents) do
			eventFrame:RegisterEvent(evt)
		end
		eventFrame:SetScript("OnEvent", onEvent)
	end
	hideBlizzardPlayerFrame()
end

function UF.Disable()
	local cfg = ensureDB("player")
	cfg.enabled = false
	if state.frame then state.frame:Hide() end
	if eventFrame then
		eventFrame:UnregisterAllEvents()
		eventFrame:SetScript("OnEvent", nil)
		eventFrame = nil
	end
end

function UF.Refresh() applyConfig() end

local function addOptions(container, skipClear)
	local cfg = ensureDB("player")
	if not skipClear and container and container.ReleaseChildren then container:ReleaseChildren() end

	local parent = container
	if not skipClear then
		parent = addon.functions.createContainer("ScrollFrame", "Flow")
		parent:SetFullWidth(true)
		parent:SetFullHeight(true)
		container:AddChild(parent)
	end

	local function addColorPicker(parent, label, color, callback)
		local cp = AceGUI:Create("ColorPicker")
		cp:SetLabel(label)
		cp:SetHasAlpha(true)
		cp:SetColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
		cp:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
			color[1], color[2], color[3], color[4] = r, g, b, a
			if callback then callback() end
		end)
		cp:SetFullWidth(false)
		cp:SetRelativeWidth(0.33)
		parent:AddChild(cp)
		return cp
	end
	local enableCB = addon.functions.createCheckboxAce(L["UFPlayerEnable"] or "Enable custom player frame", cfg.enabled == true, function(_, _, val)
		cfg.enabled = val and true or false
		if cfg.enabled then
			UF.Enable()
		else
			UF.Disable()
		end
	end)
	enableCB:SetFullWidth(true)
	parent:AddChild(enableCB)

	local sizeRow = addon.functions.createContainer("SimpleGroup", "Flow")
	sizeRow:SetFullWidth(true)
	parent:AddChild(sizeRow)
	local sw = addon.functions.createSliderAce(L["UFWidth"] or "Frame width", cfg.width or defaults.player.width, MIN_WIDTH, 800, 1, function(_, _, val)
		cfg.width = max(MIN_WIDTH, val or MIN_WIDTH)
		UF.Refresh()
	end)
	sw:SetRelativeWidth(0.5)
	sizeRow:AddChild(sw)
	local shHealth = addon.functions.createSliderAce(L["UFHealthHeight"] or "Health height", cfg.healthHeight or defaults.player.healthHeight, 8, 80, 1, function(_, _, val)
		cfg.healthHeight = val
		UF.Refresh()
	end)
	shHealth:SetRelativeWidth(0.25)
	sizeRow:AddChild(shHealth)
	local shPower = addon.functions.createSliderAce(L["UFPowerHeight"] or "Power height", cfg.powerHeight or defaults.player.powerHeight, 6, 60, 1, function(_, _, val)
		cfg.powerHeight = val
		UF.Refresh()
	end)
	shPower:SetRelativeWidth(0.25)
	sizeRow:AddChild(shPower)

	local gapRow = addon.functions.createContainer("SimpleGroup", "Flow")
	gapRow:SetFullWidth(true)
	parent:AddChild(gapRow)
	local gapSlider = addon.functions.createSliderAce(L["UFBarGap"] or "Gap between bars", cfg.barGap or defaults.player.barGap or 0, 0, 10, 1, function(_, _, val)
		cfg.barGap = val or 0
		UF.Refresh()
	end)
	gapSlider:SetFullWidth(true)
	gapRow:AddChild(gapSlider)

	local strataRow = addon.functions.createContainer("SimpleGroup", "Flow")
	strataRow:SetFullWidth(true)
	parent:AddChild(strataRow)
	local strataList = {
		"BACKGROUND",
		"LOW",
		"MEDIUM",
		"HIGH",
		"DIALOG",
		"FULLSCREEN",
		"FULLSCREEN_DIALOG",
		"TOOLTIP",
	}
	local strataMap = {}
	for _, k in ipairs(strataList) do
		strataMap[k] = k
	end
	local ddStrata = addon.functions.createDropdownAce(L["UFStrata"] or "Frame strata", strataMap, strataList, function(_, _, key)
		cfg.strata = key ~= "" and key or nil
		UF.Refresh()
	end)
	ddStrata:SetRelativeWidth(0.5)
	local defaultStrata = (_G.PlayerFrame and _G.PlayerFrame.GetFrameStrata and _G.PlayerFrame:GetFrameStrata()) or ""
	ddStrata:SetValue(cfg.strata or defaultStrata or "")
	strataRow:AddChild(ddStrata)

	local defaultLevel = (_G.PlayerFrame and _G.PlayerFrame.GetFrameLevel and _G.PlayerFrame:GetFrameLevel()) or 0
	local levelSlider = addon.functions.createSliderAce(L["UFFrameLevel"] or "Frame level", cfg.frameLevel or defaultLevel, 0, 50, 1, function(_, _, val)
		cfg.frameLevel = val
		UF.Refresh()
	end)
	levelSlider:SetRelativeWidth(0.5)
	strataRow:AddChild(levelSlider)

	local cbClassColor = addon.functions.createCheckboxAce(L["UFUseClassColor"] or "Use class color (health)", cfg.health.useClassColor == true, function(_, _, val)
		cfg.health.useClassColor = val and true or false
		UF.Refresh()
		if UF.ui and UF.ui.healthColorPicker then UF.ui.healthColorPicker:SetDisabled(cfg.health.useClassColor == true) end
	end)
	cbClassColor:SetFullWidth(true)
	parent:AddChild(cbClassColor)

	local colorRow = addon.functions.createContainer("SimpleGroup", "Flow")
	colorRow:SetFullWidth(true)
	parent:AddChild(colorRow)
	UF.ui = UF.ui or {}
	UF.ui.healthColorPicker = addColorPicker(colorRow, L["UFHealthColor"] or "Health color", cfg.health.color or defaults.player.health.color, function() UF.Refresh() end)
	if UF.ui.healthColorPicker then UF.ui.healthColorPicker:SetDisabled(cfg.health.useClassColor == true) end
	addColorPicker(colorRow, L["UFPowerColor"] or "Power color", cfg.power.color or defaults.player.power.color, function() UF.Refresh() end)

	local function textureDropdown(parent, sec)
		if not parent then return end
		local list = { DEFAULT = "Default (Blizzard)" }
		local order = { "DEFAULT" }
		for name, path in pairs(LSM and LSM:HashTable("statusbar") or {}) do
			if type(path) == "string" and path ~= "" then
				list[name] = tostring(name)
				table.insert(order, name)
			end
		end
		table.sort(order, function(a, b) return tostring(list[a]) < tostring(list[b]) end)
		local dd = addon.functions.createDropdownAce(L["Bar Texture"] or "Bar Texture", list, order, function(_, _, key)
			sec.texture = key
			UF.Refresh()
		end)
		local cur = sec.texture or "DEFAULT"
		if not list[cur] then cur = "DEFAULT" end
		dd:SetValue(cur)
		dd:SetFullWidth(true)
		parent:AddChild(dd)
	end

	local function addTextControls(label, sectionKey, fsLeft, fsRight)
		local sec = cfg[sectionKey] or {}
		local group = addon.functions.createContainer("InlineGroup", "Flow")
		group:SetTitle(label)
		group:SetFullWidth(true)
		parent:AddChild(group)

		local list = { PERCENT = L["PERCENT"] or "Percent", CURMAX = L["Current/Max"] or "Current/Max", CURRENT = L["Current"] or "Current", NONE = L["None"] or "None" }
		local order = { "PERCENT", "CURMAX", "CURRENT", "NONE" }

		local row = addon.functions.createContainer("SimpleGroup", "Flow")
		row:SetFullWidth(true)
		group:AddChild(row)

		local dl = addon.functions.createDropdownAce(L["TextLeft"] or "Left text", list, order, function(_, _, key)
			sec.textLeft = key
			UF.Refresh()
		end)
		dl:SetValue(sec.textLeft or "PERCENT")
		dl:SetRelativeWidth(0.5)
		row:AddChild(dl)

		local dr = addon.functions.createDropdownAce(L["TextRight"] or "Right text", list, order, function(_, _, key)
			sec.textRight = key
			UF.Refresh()
		end)
		dr:SetValue(sec.textRight or "CURMAX")
		dr:SetRelativeWidth(0.5)
		row:AddChild(dr)

		local fontRow = addon.functions.createContainer("SimpleGroup", "Flow")
		fontRow:SetFullWidth(true)
		group:AddChild(fontRow)

		local fontList = {}
		local fontOrder = {}
		for name, path in pairs(LSM and LSM:HashTable("font") or {}) do
			fontList[path] = name
			table.insert(fontOrder, path)
		end
		table.sort(fontOrder, function(a, b) return tostring(fontList[a]) < tostring(fontList[b]) end)

		local fdd = addon.functions.createDropdownAce(L["Font"] or "Font", fontList, fontOrder, function(_, _, key)
			sec.font = key
			UF.Refresh()
		end)
		fdd:SetValue(sec.font or "")
		fdd:SetRelativeWidth(0.5)
		fontRow:AddChild(fdd)

		local fs = addon.functions.createSliderAce(L["FontSize"] or "Font size", sec.fontSize or 14, 8, 30, 1, function(_, _, val)
			sec.fontSize = val
			UF.Refresh()
		end)
		fs:SetRelativeWidth(0.5)
		fontRow:AddChild(fs)

		local shortRow = addon.functions.createContainer("SimpleGroup", "Flow")
		shortRow:SetFullWidth(true)
		group:AddChild(shortRow)
		local cbShort = addon.functions.createCheckboxAce(L["Use short numbers"] or "Use short numbers", sec.useShortNumbers ~= false, function(_, _, v)
			sec.useShortNumbers = v and true or false
			UF.Refresh()
		end)
		cbShort:SetFullWidth(true)
		shortRow:AddChild(cbShort)

		local offsets1 = addon.functions.createContainer("SimpleGroup", "Flow")
		offsets1:SetFullWidth(true)
		group:AddChild(offsets1)

		local leftX = addon.functions.createSliderAce(L["Left X Offset"] or "Left X Offset", (sec.offsetLeft and sec.offsetLeft.x) or 0, -100, 100, 1, function(_, _, val)
			sec.offsetLeft = sec.offsetLeft or {}
			sec.offsetLeft.x = val
			UF.Refresh()
		end)
		leftX:SetRelativeWidth(0.25)
		offsets1:AddChild(leftX)

		local leftY = addon.functions.createSliderAce(L["Left Y Offset"] or "Left Y Offset", (sec.offsetLeft and sec.offsetLeft.y) or 0, -100, 100, 1, function(_, _, val)
			sec.offsetLeft = sec.offsetLeft or {}
			sec.offsetLeft.y = val
			UF.Refresh()
		end)
		leftY:SetRelativeWidth(0.25)
		offsets1:AddChild(leftY)

		local rightX = addon.functions.createSliderAce(L["Right X Offset"] or "Right X Offset", (sec.offsetRight and sec.offsetRight.x) or 0, -100, 100, 1, function(_, _, val)
			sec.offsetRight = sec.offsetRight or {}
			sec.offsetRight.x = val
			UF.Refresh()
		end)
		rightX:SetRelativeWidth(0.25)
		offsets1:AddChild(rightX)

		local rightY = addon.functions.createSliderAce(L["Right Y Offset"] or "Right Y Offset", (sec.offsetRight and sec.offsetRight.y) or 0, -100, 100, 1, function(_, _, val)
			sec.offsetRight = sec.offsetRight or {}
			sec.offsetRight.y = val
			UF.Refresh()
		end)
		rightY:SetRelativeWidth(0.25)
		offsets1:AddChild(rightY)

		local bdRow = addon.functions.createContainer("SimpleGroup", "Flow")
		bdRow:SetFullWidth(true)
		group:AddChild(bdRow)
		local cbBd = addon.functions.createCheckboxAce(L["UFBarBackdrop"] or "Show bar backdrop", (sec.backdrop and sec.backdrop.enabled) ~= false, function(_, _, v)
			sec.backdrop = sec.backdrop or {}
			sec.backdrop.enabled = v and true or false
			UF.Refresh()
		end)
		cbBd:SetRelativeWidth(0.5)
		bdRow:AddChild(cbBd)
		sec.backdrop = sec.backdrop or {}
		sec.backdrop.color = sec.backdrop.color or { 0, 0, 0, 0.6 }
		local bdColor = addColorPicker(bdRow, L["UFBarBackdropColor"] or "Backdrop color", sec.backdrop.color, function() UF.Refresh() end)
		bdColor:SetRelativeWidth(0.5)

		textureDropdown(group, sec)
	end

	addTextControls(L["HealthBar"] or "Health Bar", "health")
	addTextControls(L["PowerBar"] or "Power Bar", "power")

	local borderGroup = addon.functions.createContainer("InlineGroup", "Flow")
	borderGroup:SetTitle(L["UFBorder"] or "Border")
	borderGroup:SetFullWidth(true)
	parent:AddChild(borderGroup)
	local cbBorder = addon.functions.createCheckboxAce(L["UFBorderEnable"] or "Show border", cfg.border.enabled ~= false, function(_, _, v)
		cfg.border.enabled = v and true or false
		UF.Refresh()
	end)
	cbBorder:SetFullWidth(true)
	borderGroup:AddChild(cbBorder)
	addColorPicker(borderGroup, L["UFBorderColor"] or "Border color", cfg.border.color or defaults.player.border.color, function() UF.Refresh() end)
	local edge = addon.functions.createSliderAce(L["UFBorderThickness"] or "Border size", cfg.border.edgeSize or defaults.player.border.edgeSize, 0, 8, 0.5, function(_, _, val)
		cfg.border.edgeSize = val
		UF.Refresh()
	end)
	edge:SetFullWidth(true)
	borderGroup:AddChild(edge)

	local statusGroup = addon.functions.createContainer("InlineGroup", "Flow")
	statusGroup:SetTitle(L["UFStatusLine"] or "Status line")
	statusGroup:SetFullWidth(true)
	parent:AddChild(statusGroup)

	local cbStatus = addon.functions.createCheckboxAce(L["UFStatusEnable"] or "Show status line", cfg.status.enabled ~= false, function(_, _, v)
		cfg.status.enabled = v and true or false
		UF.Refresh()
	end)
	cbStatus:SetFullWidth(true)
	statusGroup:AddChild(cbStatus)

	local cbLevel = addon.functions.createCheckboxAce(L["UFShowLevel"] or "Show level", cfg.status.levelEnabled ~= false, function(_, _, v)
		cfg.status.levelEnabled = v and true or false
		UF.Refresh()
	end)
	cbLevel:SetFullWidth(true)
	statusGroup:AddChild(cbLevel)

	local colorRowStatus = addon.functions.createContainer("SimpleGroup", "Flow")
	colorRowStatus:SetFullWidth(true)
	statusGroup:AddChild(colorRowStatus)
	local nameColorMode = addon.functions.createDropdownAce(
		L["UFNameColorMode"] or "Name color",
		{ CLASS = L["ClassColor"] or "Class color", CUSTOM = L["Custom"] or "Custom" },
		{ "CLASS", "CUSTOM" },
		function(_, _, key)
			cfg.status.nameColorMode = key
			UF.Refresh()
			if UF.ui and UF.ui.nameColorPicker then UF.ui.nameColorPicker:SetDisabled(key == "CLASS") end
		end
	)
	nameColorMode:SetValue(cfg.status.nameColorMode or "CLASS")
	nameColorMode:SetRelativeWidth(0.33)
	colorRowStatus:AddChild(nameColorMode)
	UF.ui = UF.ui or {}
	UF.ui.nameColorPicker = addColorPicker(colorRowStatus, L["UFNameColor"] or "Name color", cfg.status.nameColor or defaults.player.status.nameColor, function() UF.Refresh() end)
	if UF.ui.nameColorPicker then UF.ui.nameColorPicker:SetDisabled((cfg.status.nameColorMode or "CLASS") == "CLASS") end
	addColorPicker(colorRowStatus, L["UFLevelColor"] or "Level color", cfg.status.levelColor or defaults.player.status.levelColor, function() UF.Refresh() end)

	local sFont = addon.functions.createSliderAce(L["FontSize"] or "Font size", cfg.status.fontSize or 14, 8, 30, 1, function(_, _, val)
		cfg.status.fontSize = val
		UF.Refresh()
	end)
	sFont:SetFullWidth(true)
	statusGroup:AddChild(sFont)

	local fontRow = addon.functions.createContainer("SimpleGroup", "Flow")
	fontRow:SetFullWidth(true)
	statusGroup:AddChild(fontRow)
	local fontList = {}
	local fontOrder = {}
	for name, path in pairs(LSM and LSM:HashTable("font") or {}) do
		if type(path) == "string" and path ~= "" then
			fontList[path] = name
			table.insert(fontOrder, path)
		end
	end
	table.sort(fontOrder, function(a, b) return tostring(fontList[a]) < tostring(fontList[b]) end)
	local fdd = addon.functions.createDropdownAce(L["Font"] or "Font", fontList, fontOrder, function(_, _, key)
		cfg.status.font = key
		UF.Refresh()
	end)
	fdd:SetRelativeWidth(0.5)
	fdd:SetValue(cfg.status.font or "")
	fontRow:AddChild(fdd)

	local outlineMap = {
		NONE = L["None"] or "None",
		OUTLINE = L["Outline"] or "Outline",
		THICKOUTLINE = L["Thick Outline"] or "Thick Outline",
		MONOCHROMEOUTLINE = L["Monochrome Outline"] or "Monochrome Outline",
	}
	local outlineOrder = { "NONE", "OUTLINE", "THICKOUTLINE", "MONOCHROMEOUTLINE" }
	local fdo = addon.functions.createDropdownAce(L["Font outline"] or "Font outline", outlineMap, outlineOrder, function(_, _, key)
		cfg.status.fontOutline = key
		UF.Refresh()
	end)
	fdo:SetRelativeWidth(0.5)
	fdo:SetValue(cfg.status.fontOutline or "OUTLINE")
	fontRow:AddChild(fdo)

	local statusOffsets = addon.functions.createContainer("SimpleGroup", "Flow")
	statusOffsets:SetFullWidth(true)
	statusGroup:AddChild(statusOffsets)

	local anchorList = { LEFT = "LEFT", CENTER = "CENTER", RIGHT = "RIGHT" }
	local anchorOrder = { "LEFT", "CENTER", "RIGHT" }
	local nameAnchor = addon.functions.createDropdownAce(L["UFNameAnchor"] or "Name anchor", anchorList, anchorOrder, function(_, _, key)
		cfg.status.nameAnchor = key
		UF.Refresh()
	end)
	nameAnchor:SetRelativeWidth(0.25)
	nameAnchor:SetValue(cfg.status.nameAnchor or "LEFT")
	statusOffsets:AddChild(nameAnchor)

	local nameX = addon.functions.createSliderAce(L["UFNameX"] or "Name X offset", (cfg.status.nameOffset and cfg.status.nameOffset.x) or 0, -200, 200, 1, function(_, _, val)
		cfg.status.nameOffset = cfg.status.nameOffset or {}
		cfg.status.nameOffset.x = val
		UF.Refresh()
	end)
	nameX:SetRelativeWidth(0.25)
	statusOffsets:AddChild(nameX)
	local nameY = addon.functions.createSliderAce(L["UFNameY"] or "Name Y offset", (cfg.status.nameOffset and cfg.status.nameOffset.y) or 0, -200, 200, 1, function(_, _, val)
		cfg.status.nameOffset = cfg.status.nameOffset or {}
		cfg.status.nameOffset.y = val
		UF.Refresh()
	end)
	nameY:SetRelativeWidth(0.25)
	statusOffsets:AddChild(nameY)

	local levelAnchor = addon.functions.createDropdownAce(L["UFLevelAnchor"] or "Level anchor", anchorList, anchorOrder, function(_, _, key)
		cfg.status.levelAnchor = key
		UF.Refresh()
	end)
	levelAnchor:SetRelativeWidth(0.25)
	levelAnchor:SetValue(cfg.status.levelAnchor or "RIGHT")
	statusOffsets:AddChild(levelAnchor)

	local lvlX = addon.functions.createSliderAce(L["UFLevelX"] or "Level X offset", (cfg.status.levelOffset and cfg.status.levelOffset.x) or 0, -200, 200, 1, function(_, _, val)
		cfg.status.levelOffset = cfg.status.levelOffset or {}
		cfg.status.levelOffset.x = val
		UF.Refresh()
	end)
	lvlX:SetRelativeWidth(0.25)
	statusOffsets:AddChild(lvlX)
	local lvlY = addon.functions.createSliderAce(L["UFLevelY"] or "Level Y offset", (cfg.status.levelOffset and cfg.status.levelOffset.y) or 0, -200, 200, 1, function(_, _, val)
		cfg.status.levelOffset = cfg.status.levelOffset or {}
		cfg.status.levelOffset.y = val
		UF.Refresh()
	end)
	lvlY:SetRelativeWidth(0.25)
	statusOffsets:AddChild(lvlY)

	parent:DoLayout()
end

if addon.functions and addon.functions.RegisterOptionsPage then
	addon.functions.RegisterOptionsPage("ufplus", function(container)
		container:ReleaseChildren()
		local lbl = addon.functions.createLabelAce(L["UFPlusRoot"] or "UF Plus")
		lbl:SetFullWidth(true)
		container:AddChild(lbl)
	end)
	addon.functions.RegisterOptionsPage("ufplus\001player", function(container) addOptions(container, false) end)
	if addon.functions.addToTree then
		addon.functions.addToTree(nil, {
			value = "ufplus",
			text = L["UFPlusRoot"] or "UF Plus",
			children = {
				{ value = "player", text = L["UFPlayerFrame"] or PLAYER },
			},
		}, true)
	end
end

function UF.treeCallback(container, group)
	if not container then return end
	container:ReleaseChildren()
	print(group)
	if group == "ufplus" then
		local lbl = addon.functions.createLabelAce(L["UFPlusRoot"] or "UF Plus")
		lbl:SetFullWidth(true)
		container:AddChild(lbl)
	elseif group == "ufplus\001player" then
		addOptions(container, false)
	end
end

-- Auto-enable on load when configured
if not addon.Aura.UFInitialized then
	addon.Aura.UFInitialized = true
	local cfg = ensureDB("player")
	if cfg.enabled then After(0.1, function() UF.Enable() end) end
end

return UF
