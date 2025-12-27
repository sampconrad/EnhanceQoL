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
addon.variables = addon.variables or {}
addon.variables.ufSampleAbsorb = addon.variables.ufSampleAbsorb or {}
local sampleAbsorb = addon.variables.ufSampleAbsorb
addon.variables.ufSampleCast = addon.variables.ufSampleCast or {}
local sampleCast = addon.variables.ufSampleCast
local maxBossFrames = MAX_BOSS_FRAMES or 5
local UF_PROFILE_SHARE_KIND = "EQOL_UF_PROFILE"

local throttleHook
local function DisableBossFrames()
	BossTargetFrameContainer:SetAlpha(0)
	BossTargetFrameContainer.Selection:SetAlpha(0)
	if not throttleHook then
		throttleHook = true
		hooksecurefunc(BossTargetFrameContainer, "SetAlpha", function(self, parent)
			if self:GetAlpha() ~= 0 then self:SetAlpha(0) end
		end)
	end
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")
local LSM = LibStub("LibSharedMedia-3.0")
local AceGUI = addon.AceGUI or LibStub("AceGUI-3.0")
local BLIZZARD_TEX = "Interface\\TargetingFrame\\UI-StatusBar"
local DEFAULT_NOT_INTERRUPTIBLE_COLOR = { 204 / 255, 204 / 255, 204 / 255, 1 }
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

local CASTING_BAR_TYPES = _G.CASTING_BAR_TYPES
local EnumPowerType = Enum and Enum.PowerType
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs or function() return 0 end
local RegisterStateDriver = _G.RegisterStateDriver
local UnregisterStateDriver = _G.UnregisterStateDriver
local IsResting = _G.IsResting
local UnitIsResting = _G.UnitIsResting
local After = C_Timer and C_Timer.After
local NewTicker = C_Timer and C_Timer.NewTicker
local floor = math.floor
local max = math.max
local abs = math.abs
local wipe = wipe or (table and table.wipe)
local function clamp(value, minV, maxV)
	if value < minV then return minV end
	if value > maxV then return maxV end
	return value
end
local SetFrameVisibilityOverride = addon.functions and addon.functions.SetFrameVisibilityOverride
local HasFrameVisibilityOverride = addon.functions and addon.functions.HasFrameVisibilityOverride
local NormalizeUnitFrameVisibilityConfig = addon.functions and addon.functions.NormalizeUnitFrameVisibilityConfig
local ApplyFrameVisibilityConfig = addon.functions and addon.functions.ApplyFrameVisibilityConfig

local shouldShowSampleCast
local setSampleCast
local applyFont

local UNIT = {
	PLAYER = "player",
	TARGET = "target",
	TARGET_TARGET = "targettarget",
	FOCUS = "focus",
	PET = "pet",
}

local UF_FRAME_NAMES = {
	player = {
		frame = "EQOLUFPlayerFrame",
		health = "EQOLUFPlayerHealth",
		power = "EQOLUFPlayerPower",
		status = "EQOLUFPlayerStatus",
	},
	target = {
		frame = "EQOLUFTargetFrame",
		health = "EQOLUFTargetHealth",
		power = "EQOLUFTargetPower",
		status = "EQOLUFTargetStatus",
	},
	targettarget = {
		frame = "EQOLUFToTFrame",
		health = "EQOLUFToTHealth",
		power = "EQOLUFToTPower",
		status = "EQOLUFToTStatus",
	},
	focus = {
		frame = "EQOLUFFocusFrame",
		health = "EQOLUFFocusHealth",
		power = "EQOLUFFocusPower",
		status = "EQOLUFFocusStatus",
	},
	pet = {
		frame = "EQOLUFPetFrame",
		health = "EQOLUFPetHealth",
		power = "EQOLUFPetPower",
		status = "EQOLUFPetStatus",
	},
}

local BLIZZ_FRAME_NAMES = {
	player = "PlayerFrame",
	target = "TargetFrame",
	targettarget = "TargetFrameToT",
	focus = "FocusFrame",
	pet = "PetFrame",
}
local MIN_WIDTH = 50
local classResourceFramesByClass = {
	DEATHKNIGHT = { "RuneFrame" },
	DRUID = { "DruidComboPointBarFrame" },
	EVOKER = { "EssencePlayerFrame" },
	MAGE = { "MageArcaneChargesFrame" },
	MONK = { "MonkHarmonyBarFrame" },
	PALADIN = { "PaladinPowerBarFrame" },
	ROGUE = { "RogueComboPointBarFrame" },
	WARLOCK = { "WarlockPowerFrame" },
}
local classResourceOriginalLayouts = {}
local classResourceManagedFrames = {}
local classResourceHooks = {}
local applyClassResourceLayout

local function getFont(path)
	if path and path ~= "" then return path end
	return addon.variables and addon.variables.defaultFont or (LSM and LSM:Fetch("font", LSM.DefaultMedia.font)) or STANDARD_TEXT_FONT
end
local function isBossUnit(unit)
	if type(unit) ~= "string" then return false end
	return unit == "boss" or (unit and unit:match("^boss%d+$"))
end

local UNITS = {
	player = {
		unit = UNIT.PLAYER,
		frameName = UF_FRAME_NAMES.player.frame,
		healthName = UF_FRAME_NAMES.player.health,
		powerName = UF_FRAME_NAMES.player.power,
		statusName = UF_FRAME_NAMES.player.status,
		dropdown = function(self) ToggleDropDownMenu(1, nil, PlayerFrameDropDown, self, 0, 0) end,
	},
	target = {
		unit = UNIT.TARGET,
		frameName = UF_FRAME_NAMES.target.frame,
		healthName = UF_FRAME_NAMES.target.health,
		powerName = UF_FRAME_NAMES.target.power,
		statusName = UF_FRAME_NAMES.target.status,
		dropdown = function(self) ToggleDropDownMenu(1, nil, TargetFrameDropDown, self, 0, 0) end,
	},
	targettarget = {
		unit = UNIT.TARGET_TARGET,
		frameName = UF_FRAME_NAMES.targettarget.frame,
		healthName = UF_FRAME_NAMES.targettarget.health,
		powerName = UF_FRAME_NAMES.targettarget.power,
		statusName = UF_FRAME_NAMES.targettarget.status,
		dropdown = function(self) ToggleDropDownMenu(1, nil, TargetFrameDropDown, self, 0, 0) end,
	},
	focus = {
		unit = UNIT.FOCUS,
		frameName = UF_FRAME_NAMES.focus.frame,
		healthName = UF_FRAME_NAMES.focus.health,
		powerName = UF_FRAME_NAMES.focus.power,
		statusName = UF_FRAME_NAMES.focus.status,
		dropdown = function(self) ToggleDropDownMenu(1, nil, FocusFrameDropDown, self, 0, 0) end,
	},
	pet = {
		unit = UNIT.PET,
		frameName = UF_FRAME_NAMES.pet.frame,
		healthName = UF_FRAME_NAMES.pet.health,
		powerName = UF_FRAME_NAMES.pet.power,
		statusName = UF_FRAME_NAMES.pet.status,
		dropdown = function(self) ToggleDropDownMenu(1, nil, PetFrameDropDown, self, 0, 0) end,
		disableAbsorb = true,
	},
}
for i = 1, maxBossFrames do
	local unit = "boss" .. i
	UNITS[unit] = {
		unit = unit,
		frameName = "EQOLUFBoss" .. i .. "Frame",
		healthName = "EQOLUFBoss" .. i .. "Health",
		powerName = "EQOLUFBoss" .. i .. "Power",
		statusName = "EQOLUFBoss" .. i .. "Status",
		disableAbsorb = true,
	}
end

local defaults = {
	player = {
		enabled = false,
		showTooltip = false,
		width = 220,
		healthHeight = 24,
		powerHeight = 16,
		statusHeight = 18,
		anchor = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 0, y = -200 },
		strata = nil,
		frameLevel = nil,
		barGap = 0,
		border = { enabled = true, texture = "DEFAULT", color = { 0, 0, 0, 0.8 }, edgeSize = 1, inset = 0 },
		health = {
			useCustomColor = false,
			useClassColor = false,
			color = { 0.0, 0.8, 0.0, 1 },
			absorbColor = { 0.85, 0.95, 1.0, 0.7 },
			absorbUseCustomColor = false,
			showSampleAbsorb = false,
			absorbTexture = "SOLID",
			useAbsorbGlow = true,
			backdrop = { enabled = true, color = { 0, 0, 0, 0.6 } },
			textLeft = "PERCENT",
			textRight = "CURMAX",
			textDelimiter = " ",
			fontSize = 14,
			font = nil,
			fontOutline = "OUTLINE", -- fallback to default font
			offsetLeft = { x = 6, y = 0 },
			offsetRight = { x = -6, y = 0 },
			useShortNumbers = true,
			texture = "DEFAULT",
		},
		power = {
			enabled = true,
			color = { 0.1, 0.45, 1, 1 },
			backdrop = { enabled = true, color = { 0, 0, 0, 0.6 } },
			useCustomColor = false,
			textLeft = "PERCENT",
			textRight = "CURMAX",
			textDelimiter = " ",
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
			fontOutline = "OUTLINE",
			nameColorMode = "CLASS", -- CLASS or CUSTOM
			nameColor = { 0.8, 0.8, 1, 1 },
			levelColor = { 1, 0.85, 0, 1 },
			nameOffset = { x = 0, y = 0 },
			levelOffset = { x = 0, y = 0 },
			levelEnabled = true,
			nameMaxChars = 15,
			unitStatus = {
				enabled = false,
				offset = { x = 0, y = 0 },
			},
			combatIndicator = {
				enabled = false,
				size = 18,
				offset = { x = -8, y = 0 },
				texture = "Interface\\CharacterFrame\\UI-StateIcon",
				texCoords = { 0.5, 1, 0, 0.5 }, -- combat icon region
			},
		},
		resting = {
			enabled = true,
			size = 20,
			offset = { x = 0, y = 0 },
		},
		classResource = {
			enabled = true,
			anchor = "BOTTOM",
			offset = { x = 0, y = -28 },
			scale = 1,
		},
		raidIcon = {
			enabled = true,
			size = 18,
			offset = { x = 0, y = -2 },
		},
		portrait = {
			enabled = false,
			size = 32,
			side = "LEFT",
			offset = { x = 0, y = 0 },
			squareBackground = true,
		},
	},
	target = {
		enabled = false,
		showTooltip = false,
		auraIcons = {
			size = 24,
			padding = 2,
			max = 16,
			showCooldown = true,
			showTooltip = true,
			hidePermanentAuras = false,
			anchor = "BOTTOM",
			offset = { x = 0, y = -24 },
			separateDebuffAnchor = false,
			debuffAnchor = nil, -- falls back to anchor
			debuffOffset = nil, -- falls back to offset
			countAnchor = "BOTTOMRIGHT",
			countOffset = { x = -2, y = 2 },
			countFontSize = nil,
			countFontOutline = nil,
		},
		cast = {
			enabled = true,
			width = 200,
			height = 16,
			anchor = "BOTTOM", -- or "TOP"
			offset = { x = 11, y = -4 },
			backdrop = { enabled = true, color = { 0, 0, 0, 0.6 } },
			showName = true,
			nameOffset = { x = 6, y = 0 },
			showDuration = true,
			durationOffset = { x = -6, y = 0 },
			font = nil,
			fontSize = 12,
			showIcon = true,
			iconSize = 22,
			texture = "DEFAULT",
			color = { 0.9, 0.7, 0.2, 1 },
			notInterruptibleColor = DEFAULT_NOT_INTERRUPTIBLE_COLOR,
		},
		portrait = {
			enabled = false,
			size = 32,
			side = "LEFT",
			offset = { x = 0, y = 0 },
			squareBackground = false,
		},
	},
	targettarget = {
		enabled = false,
		showTooltip = false,
		width = 180,
		healthHeight = 20,
		powerHeight = 12,
		statusHeight = 16,
		anchor = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 520, y = -200 },
		portrait = {
			enabled = false,
			size = 32,
			side = "LEFT",
			offset = { x = 0, y = 0 },
			squareBackground = false,
		},
	},
}

local function hideSettingsReset(frame)
	if frame and addon.EditModeLib and addon.EditModeLib.SetFrameResetVisible then addon.EditModeLib:SetFrameResetVisible(frame, false) end
end

local issecretvalue = _G.issecretvalue
local mainPowerEnum
local mainPowerToken
local states = {}
local targetAuras = {}
local targetAuraOrder = {}
local targetAuraIndexById = {}
local auraList = {}
local blizzardPlayerHooked = false
local blizzardTargetHooked = false
local castOnUpdateHandlers = {}
local originalFrameRules = {}
local NIL_VISIBILITY_SENTINEL = {}
local totTicker
local editModeHooked
local bossContainer
local bossLayoutDirty
local bossHidePending
local bossShowPending
local bossInitPending

local debuffinfo = {
	[1] = DEBUFF_TYPE_MAGIC_COLOR,
	[2] = DEBUFF_TYPE_CURSE_COLOR,
	[3] = DEBUFF_TYPE_DISEASE_COLOR,
	[4] = DEBUFF_TYPE_POISON_COLOR,
	[5] = DEBUFF_TYPE_BLEED_COLOR,
	[0] = DEBUFF_TYPE_NONE_COLOR,
}
local colorcurve = C_CurveUtil and C_CurveUtil.CreateColorCurve() or nil
if colorcurve and Enum.LuaCurveType and Enum.LuaCurveType.Step then
	colorcurve:SetType(Enum.LuaCurveType.Step)
	for dispeltype, v in pairs(debuffinfo) do
		colorcurve:AddPoint(dispeltype, v)
	end
end

local function defaultsFor(unit)
	if isBossUnit(unit) then return defaults.boss or defaults.target or defaults.player or {} end
	return defaults[unit] or defaults.player or {}
end

local function resetTargetAuras()
	for k in pairs(targetAuras) do
		targetAuras[k] = nil
	end
	for i = #targetAuraOrder, 1, -1 do
		targetAuraOrder[i] = nil
	end
	for k in pairs(targetAuraIndexById) do
		targetAuraIndexById[k] = nil
	end
end

local function ensureDB(unit)
	addon.db = addon.db or {}
	addon.db.ufFrames = addon.db.ufFrames or {}
	local db = addon.db.ufFrames
	local key = unit
	if isBossUnit(unit) then key = "boss" end
	if key == "boss" and not db[key] then
		for i = 1, maxBossFrames do
			if db["boss" .. i] then
				db[key] = db["boss" .. i]
				break
			end
		end
	end
	db[key] = db[key] or {}
	local udb = db[key]
	local def = defaultsFor(unit)
	for k, v in pairs(def) do
		if udb[k] == nil then
			if type(v) == "table" then
				if addon.functions.copyTable then
					udb[k] = addon.functions.copyTable(v)
				else
					udb[k] = CopyTable(v)
				end
			else
				udb[k] = v
			end
		end
	end
	return udb
end

local function copySettings(fromUnit, toUnit, opts)
	opts = opts or {}
	if not fromUnit or not toUnit or fromUnit == toUnit then return false end
	local src = ensureDB(fromUnit)
	local dest = ensureDB(toUnit)
	if not src or not dest then return false end
	local keepAnchor = opts.keepAnchor ~= false
	local keepEnabled = opts.keepEnabled ~= false
	local anchor = keepAnchor and dest.anchor and CopyTable(dest.anchor) or dest.anchor
	local enabled = keepEnabled and dest.enabled
	if wipe then wipe(dest) end
	for k, v in pairs(src) do
		if type(v) == "table" then
			dest[k] = CopyTable(v)
		else
			dest[k] = v
		end
	end
	if keepAnchor then dest.anchor = anchor end
	if keepEnabled then dest.enabled = enabled end
	return true
end

local function applyRaidIconLayout(unit, cfg)
	local st = states[unit]
	if not st or not st.raidIcon or not st.frame then return end
	local def = defaultsFor(unit)
	local rcfg = (cfg and cfg.raidIcon) or (def and def.raidIcon) or {}
	local offsetDef = def and def.raidIcon and def.raidIcon.offset or {}
	local sizeDef = def and def.raidIcon and def.raidIcon.size or 18
	local enabled = rcfg.enabled ~= false
	local size = clamp(rcfg.size or sizeDef or 18, 10, 30)
	local ox = (rcfg.offset and rcfg.offset.x) or offsetDef.x or 0
	local oy = (rcfg.offset and rcfg.offset.y) or offsetDef.y or -2
	st.raidIcon:ClearAllPoints()
	st.raidIcon:SetSize(size, size)
	st.raidIcon:SetPoint("TOP", st.frame, "TOP", ox, oy)
	if not enabled then st.raidIcon:Hide() end
end

local function hardHideBlizzFrame(frameName)
	local frame = frameName and _G[frameName]
	if frame and frame.SetAlpha then frame:SetAlpha(0) end
end

local function checkRaidTargetIcon(unitToken, st)
	if not st or not st.raidIcon then return end
	local cfg = st.cfg or ensureDB(unitToken)
	applyRaidIconLayout(unitToken, cfg)
	local def = defaultsFor(unitToken)
	local rcfg = (cfg and cfg.raidIcon) or (def and def.raidIcon) or {}
	if (cfg and cfg.enabled == false) or rcfg.enabled == false then
		st.raidIcon:Hide()
		return
	end
	if addon.EditModeLib and addon.EditModeLib:IsInEditMode() then
		SetRaidTargetIconTexture(st.raidIcon, 8)
		st.raidIcon:Show()
		return
	end
	local idx = GetRaidTargetIndex(unitToken)
	if idx then
		SetRaidTargetIconTexture(st.raidIcon, idx)
		st.raidIcon:Show()
	else
		st.raidIcon:Hide()
	end
end
local function updateAllRaidTargetIcons()
	checkRaidTargetIcon(UNIT.PLAYER, states[UNIT.PLAYER])
	checkRaidTargetIcon(UNIT.TARGET, states[UNIT.TARGET])
	checkRaidTargetIcon(UNIT.TARGET_TARGET, states[UNIT.TARGET_TARGET])
	checkRaidTargetIcon(UNIT.PET, states[UNIT.PET])
	checkRaidTargetIcon(UNIT.FOCUS, states[UNIT.FOCUS])
	for i = 1, maxBossFrames do
		local u = "boss" .. i
		if states[u] then checkRaidTargetIcon(u, states[u]) end
	end
end

local function getClassResourceFrames()
	local classKey = addon.variables and addon.variables.unitClass
	local names = classKey and classResourceFramesByClass[classKey]
	if not names then return nil end
	local frames = {}
	for _, name in ipairs(names) do
		local frame = _G[name]
		if frame then frames[#frames + 1] = frame end
	end
	return frames
end

local function storeClassResourceDefaults(frame)
	if not frame or classResourceOriginalLayouts[frame] then return end
	local info = {
		parent = frame:GetParent(),
		scale = frame:GetScale(),
		strata = frame:GetFrameStrata(),
		level = frame:GetFrameLevel(),
		ignoreFramePositionManager = frame.ignoreFramePositionManager,
		points = {},
	}
	for i = 1, frame:GetNumPoints() do
		local point, rel, relPoint, x, y = frame:GetPoint(i)
		info.points[#info.points + 1] = { point = point, relativeTo = rel, relativePoint = relPoint, x = x, y = y }
	end
	classResourceOriginalLayouts[frame] = info
end

local function restoreClassResourceFrame(frame)
	if not frame then return end
	local info = classResourceOriginalLayouts[frame]
	classResourceManagedFrames[frame] = nil
	if not info then return end
	if frame.SetParent and info.parent then frame:SetParent(info.parent) end
	frame:ClearAllPoints()
	if info.points and #info.points > 0 then
		for _, pt in ipairs(info.points) do
			frame:SetPoint(pt.point, pt.relativeTo, pt.relativePoint, pt.x or 0, pt.y or 0)
		end
	end
	if info.scale and frame.SetScale then frame:SetScale(info.scale) end
	if info.strata and frame.SetFrameStrata then frame:SetFrameStrata(info.strata) end
	if info.level and frame.SetFrameLevel then frame:SetFrameLevel(info.level) end
	if info.ignoreFramePositionManager ~= nil then frame.ignoreFramePositionManager = info.ignoreFramePositionManager end
end

local function restoreClassResourceFrames()
	for frame in pairs(classResourceManagedFrames) do
		restoreClassResourceFrame(frame)
	end
end

local function onClassResourceShow()
	if applyClassResourceLayout then applyClassResourceLayout(states[UNIT.PLAYER] and states[UNIT.PLAYER].cfg or ensureDB(UNIT.PLAYER)) end
end

local function hookClassResourceFrame(frame)
	if not frame or classResourceHooks[frame] then return end
	classResourceHooks[frame] = true
	frame:HookScript("OnShow", onClassResourceShow)
end

applyClassResourceLayout = function(cfg)
	local classKey = addon.variables and addon.variables.unitClass
	if not classKey or not classResourceFramesByClass[classKey] then
		restoreClassResourceFrames()
		return
	end
	local frames = getClassResourceFrames()
	if not frames or #frames == 0 then
		restoreClassResourceFrames()
		return
	end
	local st = states[UNIT.PLAYER]
	if not st or not st.frame then return end
	local def = defaultsFor(UNIT.PLAYER)
	local rcfg = (cfg and cfg.classResource) or (def and def.classResource) or {}
	if rcfg.enabled == false then
		restoreClassResourceFrames()
		return
	end
	if InCombatLockdown and InCombatLockdown() then return end

	local anchor = rcfg.anchor or (def.classResource and def.classResource.anchor) or "TOP"
	local offsetX = (rcfg.offset and rcfg.offset.x) or 0
	local offsetY = (rcfg.offset and rcfg.offset.y)
	if offsetY == nil then offsetY = anchor == "TOP" and -5 or 5 end
	local scale = rcfg.scale or (def.classResource and def.classResource.scale) or 1

	for _, frame in ipairs(frames) do
		storeClassResourceDefaults(frame)
		hookClassResourceFrame(frame)
		classResourceManagedFrames[frame] = true
		frame.ignoreFramePositionManager = true
		frame:ClearAllPoints()
		frame:SetPoint(anchor, st.frame, anchor, offsetX, offsetY)
		frame:SetParent(st.frame)
		if frame.SetScale then frame:SetScale(scale) end
		if frame.SetFrameStrata and st.frame.GetFrameStrata then frame:SetFrameStrata(st.frame:GetFrameStrata()) end
		if frame.SetFrameLevel and st.frame.GetFrameLevel then frame:SetFrameLevel((st.frame:GetFrameLevel() or 0) + 5) end
	end
end

local function trim(str)
	if type(str) ~= "string" then return "" end
	return str:match("^%s*(.-)%s*$")
end

local function normalizeScopeKey(scopeKey)
	if not scopeKey or scopeKey == "" then return "ALL" end
	if scopeKey == "ALL" then return "ALL" end
	if isBossUnit(scopeKey) then return "boss" end
	return scopeKey
end

local function exportUnitFrameProfile(scopeKey)
	scopeKey = normalizeScopeKey(scopeKey)
	addon.db = addon.db or {}
	addon.db.ufFrames = addon.db.ufFrames or {}
	local cfg = addon.db.ufFrames
	if type(cfg) ~= "table" then return nil, "NO_DATA" end

	local payload = {
		kind = UF_PROFILE_SHARE_KIND,
		version = 1,
		frames = {},
	}

	if scopeKey == "ALL" then
		if not next(cfg) then return nil, "EMPTY" end
		payload.frames = CopyTable(cfg)
	else
		local src = cfg[scopeKey]
		if type(src) ~= "table" then return nil, "SCOPE_EMPTY" end
		payload.frames[scopeKey] = CopyTable(src)
	end

	local serializer = LibStub("AceSerializer-3.0")
	local deflate = LibStub("LibDeflate")
	local serialized = serializer:Serialize(payload)
	local compressed = deflate:CompressDeflate(serialized)
	return deflate:EncodeForPrint(compressed)
end

local function importUnitFrameProfile(encoded, scopeKey)
	scopeKey = normalizeScopeKey(scopeKey)
	encoded = trim(encoded or "")
	if not encoded or encoded == "" then return false, "NO_INPUT" end

	local deflate = LibStub("LibDeflate")
	local serializer = LibStub("AceSerializer-3.0")
	local decoded = deflate:DecodeForPrint(encoded) or deflate:DecodeForWoWChatChannel(encoded) or deflate:DecodeForWoWAddonChannel(encoded)
	if not decoded then return false, "DECODE" end
	local decompressed = deflate:DecompressDeflate(decoded)
	if not decompressed then return false, "DECOMPRESS" end
	local ok, data = serializer:Deserialize(decompressed)
	if not ok or type(data) ~= "table" then return false, "DESERIALIZE" end

	if data.kind ~= UF_PROFILE_SHARE_KIND then return false, "WRONG_KIND" end
	if type(data.frames) ~= "table" then return false, "NO_FRAMES" end

	addon.db = addon.db or {}
	addon.db.ufFrames = addon.db.ufFrames or {}
	local target = addon.db.ufFrames
	local applied = {}

	if scopeKey == "ALL" then
		for unit, frameCfg in pairs(data.frames) do
			if type(frameCfg) == "table" then
				local key = normalizeScopeKey(unit)
				target[key] = CopyTable(frameCfg)
				applied[#applied + 1] = key
			end
		end
		if #applied == 0 then return false, "NO_FRAMES" end
	else
		local key = scopeKey
		local source = data.frames[key] or data.frames[normalizeScopeKey(key)]
		if not source and isBossUnit(key) then source = data.frames["boss1"] or data.frames["boss"] end
		if type(source) ~= "table" then return false, "SCOPE_MISSING" end
		target[key] = CopyTable(source)
		applied[#applied + 1] = key
	end

	table.sort(applied, function(a, b) return tostring(a) < tostring(b) end)
	addon.variables.requireReload = true
	return true, applied
end

local function exportProfileErrorMessage(reason)
	if reason == "NO_DATA" or reason == "EMPTY" then return L["UFExportProfileEmpty"] or "No unit frame settings to export." end
	if reason == "SCOPE_EMPTY" then return L["UFExportProfileScopeEmpty"] or "No saved settings for that frame yet." end
	return L["UFExportProfileFailed"] or "Could not create a Unit Frame export code."
end

local function importProfileErrorMessage(reason)
	if reason == "NO_INPUT" then return L["UFImportProfileEmpty"] or "Please enter a code to import." end
	if reason == "DECODE" or reason == "DECOMPRESS" or reason == "DESERIALIZE" or reason == "WRONG_KIND" then return L["UFImportProfileInvalid"] or "The code could not be read." end
	if reason == "NO_FRAMES" then return L["UFImportProfileNoFrames"] or "The code does not contain any Unit Frame settings." end
	if reason == "SCOPE_MISSING" then return L["UFImportProfileMissingScope"] or "The code does not contain settings for that frame." end
	return L["UFImportProfileFailed"] or "Could not import the Unit Frame profile."
end

local function anchorBossContainer(cfg)
	if not bossContainer then return end
	if InCombatLockdown() then
		bossLayoutDirty = true
		return
	end
	cfg = cfg or ensureDB("boss")
	local def = defaultsFor("boss")
	local anchor = (cfg and cfg.anchor) or (def and def.anchor) or { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 0, y = 0 }
	bossContainer:ClearAllPoints()
	bossContainer:SetPoint(anchor.point or "CENTER", _G[anchor.relativeTo] or UIParent, anchor.relativePoint or anchor.point or "CENTER", anchor.x or 0, anchor.y or 0)
end

local function ensureBossContainer()
	if bossContainer then return bossContainer end
	bossContainer = CreateFrame("Frame", "EQOLUFBossContainer", UIParent, "BackdropTemplate")
	bossContainer:SetSize(220, 200)
	bossContainer:SetClampedToScreen(true)
	bossContainer:SetMovable(true)
	bossContainer:RegisterForDrag("LeftButton")
	bossContainer:Hide()
	anchorBossContainer()
	return bossContainer
end

local function cacheTargetAura(aura)
	if not aura or not aura.auraInstanceID then return end
	local id = aura.auraInstanceID
	local t = targetAuras[id]
	if not t then
		t = {}
		targetAuras[id] = t
	end
	t.auraInstanceID = id
	t.spellId = aura.spellId
	t.name = aura.name
	t.icon = aura.icon
	t.isHelpful = aura.isHelpful
	t.isHarmful = aura.isHarmful
	t.applications = aura.applications
	t.duration = aura.duration
	t.expirationTime = aura.expirationTime
	t.sourceUnit = aura.sourceUnit
end

local function addTargetAuraToOrder(auraInstanceID)
	if not auraInstanceID or targetAuraIndexById[auraInstanceID] then return end
	local idx = #targetAuraOrder + 1
	targetAuraOrder[idx] = auraInstanceID
	targetAuraIndexById[auraInstanceID] = idx
	return idx
end

local function reindexTargetAuraOrder(startIndex)
	for i = startIndex or 1, #targetAuraOrder do
		targetAuraIndexById[targetAuraOrder[i]] = i
	end
end

local function removeTargetAuraFromOrder(auraInstanceID)
	local idx = targetAuraIndexById[auraInstanceID]
	if not idx then return nil end
	table.remove(targetAuraOrder, idx)
	targetAuraIndexById[auraInstanceID] = nil
	reindexTargetAuraOrder(idx)
	return idx
end

local function isPermanentAura(aura, unitToken)
	if not aura then return false end
	local duration = aura.duration
	local expiration = aura.expirationTime
	unitToken = unitToken or "target"

	if C_UnitAuras.DoesAuraHaveExpirationTime then
		local tmpDurRes = C_UnitAuras.DoesAuraHaveExpirationTime(unitToken, aura.auraInstanceID)
		if issecretvalue(tmpDurRes) then return false end
		return not tmpDurRes
	end
	if issecretvalue and (issecretvalue(duration) or issecretvalue(expiration)) then return false end
	if duration and duration > 0 then return false end
	if expiration and expiration > 0 then return false end
	return true
end

local function ensureAuraButton(container, icons, index, ac)
	if not container then return nil end
	icons = icons or {}
	local btn = icons[index]
	if not btn then
		btn = CreateFrame("Button", nil, container, "BackdropTemplate")
		btn:SetSize(ac.size, ac.size)
		btn.icon = btn:CreateTexture(nil, "ARTWORK")
		btn.icon:SetAllPoints(btn)
		btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
		btn.cd:SetAllPoints(btn)
		-- Keep the count on a sibling overlay so it is not hidden by the cooldown frame
		btn.overlay = CreateFrame("Frame", nil, btn)
		btn.overlay:SetAllPoints(btn)
		btn.overlay:SetFrameStrata(btn.cd:GetFrameStrata())
		btn.overlay:SetFrameLevel(btn.cd:GetFrameLevel() + 5)

		btn.count = btn.overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		btn.count:SetPoint("BOTTOMRIGHT", btn.overlay, "BOTTOMRIGHT", -2, 2)
		btn.count:SetDrawLayer("OVERLAY", 2)
		btn.border = btn:CreateTexture(nil, "OVERLAY")
		btn.border:SetAllPoints(btn)
		btn.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625) -- debuff overlay segment
		btn.cd:SetReverse(true)
		btn.cd:SetDrawEdge(true)
		btn.cd:SetDrawSwipe(true)
		btn:SetScript("OnEnter", function(self)
			if not self._showTooltip then return end
			local spellId = self.spellId
			if not spellId or (issecretvalue and issecretvalue(spellId)) then return end
			if GameTooltip then
				GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
				GameTooltip:SetSpellByID(spellId)
				GameTooltip:Show()
			end
		end)
		btn:SetScript("OnLeave", function()
			if GameTooltip then GameTooltip:Hide() end
		end)
		icons[index] = btn
	else
		btn:SetSize(ac.size, ac.size)
		if btn.overlay and btn.cd then
			btn.overlay:SetFrameStrata(btn.cd:GetFrameStrata())
			btn.overlay:SetFrameLevel(btn.cd:GetFrameLevel() + 5)
		end
	end
	return btn, icons
end

local function styleAuraCount(btn, ac)
	if not btn or not btn.count then return end
	ac = ac or {}
	local anchor = ac.countAnchor or "BOTTOMRIGHT"
	local off = ac.countOffset or { x = -2, y = 2 }
	btn.count:ClearAllPoints()
	btn.count:SetPoint(anchor, btn.overlay or btn, anchor, off.x or 0, off.y or 0)
	local fontPath = ac.countFont and getFont(ac.countFont) or nil
	local _, curSize, curFlags = btn.count:GetFont()
	local size = ac.countFontSize or curSize or 14
	local flags = ac.countFontOutline or curFlags
	if fontPath or size or flags then btn.count:SetFont(fontPath or getFont(), size, flags) end
end

local function applyAuraToButton(btn, aura, ac, isDebuff, unitToken)
	if not btn or not aura then return end
	local issecretAura = false
	if issecretvalue and issecretvalue(isDebuff) then
		issecretAura = true
		isDebuff = not C_UnitAuras.IsAuraFilteredOutByInstanceID("target", aura.auraInstanceID, "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY")
	end
	unitToken = unitToken or "target"
	btn.spellId = aura.spellId
	btn._showTooltip = ac.showTooltip ~= false
	btn.icon:SetTexture(aura.icon or "")
	btn.cd:Clear()
	if issecretvalue and (issecretvalue(aura.duration) or issecretvalue(aura.expirationTime)) then
		btn.cd:SetCooldownFromExpirationTime(aura.expirationTime, aura.duration, aura.timeMod)
	elseif aura.duration and aura.duration > 0 and aura.expirationTime then
		btn.cd:SetCooldown(aura.expirationTime - aura.duration, aura.duration, aura.timeMod)
	end
	btn.cd:SetHideCountdownNumbers(ac.showCooldown == false)
	styleAuraCount(btn, ac)
	if issecretvalue and issecretvalue(aura.applications) or aura.applications and aura.applications > 1 then
		local appStacks = aura.applications
		if C_UnitAuras.GetAuraApplicationDisplayCount then
			appStacks = C_UnitAuras.GetAuraApplicationDisplayCount(unitToken, aura.auraInstanceID, 2, 1000) -- TODO actual 4th param is required because otherwise it's always "*" this always get's the right stack shown
		end

		btn.count:SetText(appStacks)
		btn.count:Show()
	else
		btn.count:SetText("")
		btn.count:Hide()
	end
	if btn.border then
		if isDebuff then
			btn.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
			local color = { r = 1, g = 0.25, b = 0.25 }
			if issecretAura then
				color = C_UnitAuras.GetAuraDispelTypeColor(unitToken, aura.auraInstanceID, colorcurve)
			elseif _G.DebuffTypeColor then
				if aura.dispelName then
					color = DebuffTypeColor[aura.dispelName]
				else
					color = DebuffTypeColor["none"]
				end
			end
			btn.border:SetVertexColor(color.r, color.g, color.b, 1)
			btn.border:Show()
		else
			btn.border:SetTexture(nil)
			btn.border:Hide()
		end
	end
	btn:Show()
end

local function anchorAuraButton(btn, container, index, ac, perRow, anchor)
	if not btn or not container then return end
	local row = math.floor((index - 1) / perRow)
	local col = (index - 1) % perRow
	btn:ClearAllPoints()
	if anchor == "TOP" then
		btn:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", col * (ac.size + ac.padding), row * (ac.size + ac.padding))
	else
		btn:SetPoint("TOPLEFT", container, "TOPLEFT", col * (ac.size + ac.padding), -row * (ac.size + ac.padding))
	end
end

local function updateAuraContainerSize(container, shown, ac, perRow)
	if not container then return end
	local rows = math.ceil(shown / perRow)
	container:SetHeight(rows > 0 and (rows * (ac.size + ac.padding) - ac.padding) or 0.001)
	container:SetShown(shown > 0)
end

local function updateTargetAuraIcons(startIndex)
	local st = states.target
	if not st or not st.auraContainer or not st.frame then return end
	local cfg = ensureDB("target")
	local ac = cfg.auraIcons or defaults.target.auraIcons or { size = 24, padding = 2, max = 16, showCooldown = true }
	ac.size = ac.size or 24
	ac.padding = ac.padding or 0
	ac.max = ac.max or 16
	if ac.showTooltip == nil then ac.showTooltip = true end
	if ac.max < 1 then ac.max = 1 end

	local width = (st.auraContainer and st.auraContainer:GetWidth()) or (st.barGroup and st.barGroup:GetWidth()) or (st.frame and st.frame:GetWidth()) or 0
	local perRow = math.max(1, math.floor((width + ac.padding) / (ac.size + ac.padding)))
	local useSeparateDebuffs = ac.separateDebuffAnchor == true
	if useSeparateDebuffs and not st.debuffContainer then useSeparateDebuffs = false end

	-- Combined layout (default, backward compatible)
	if not useSeparateDebuffs then
		local icons = st.auraButtons or {}
		st.auraButtons = icons
		local shown = math.min(#targetAuraOrder, ac.max)
		local startIdx = startIndex or 1
		if startIdx < 1 then startIdx = 1 end
		local i = startIdx
		while i <= shown do
			local auraId = targetAuraOrder[i]
			local aura = auraId and targetAuras[auraId]
			if not aura then
				table.remove(targetAuraOrder, i)
				targetAuraIndexById[auraId] = nil
				reindexTargetAuraOrder(i)
				shown = math.min(#targetAuraOrder, ac.max)
			else
				local btn
				btn, st.auraButtons = ensureAuraButton(st.auraContainer, st.auraButtons, i, ac)
				applyAuraToButton(btn, aura, ac, aura.isHarmful, "target")
				anchorAuraButton(btn, st.auraContainer, i, ac, perRow, ac.anchor or "BOTTOM")
				targetAuraIndexById[auraId] = i
				i = i + 1
			end
		end
		for idx = shown + 1, #(st.auraButtons or {}) do
			if st.auraButtons[idx] then st.auraButtons[idx]:Hide() end
		end
		if st.debuffButtons then
			for idx = 1, #st.debuffButtons do
				if st.debuffButtons[idx] then st.debuffButtons[idx]:Hide() end
			end
		end
		if st.debuffContainer then
			st.debuffContainer:SetHeight(0.001)
			st.debuffContainer:SetShown(false)
		end
		updateAuraContainerSize(st.auraContainer, shown, ac, perRow)
		return
	end

	-- Separate buff/debuff anchors
	local buffButtons = st.auraButtons or {}
	local debuffButtons = st.debuffButtons or {}
	local buffCount = 0
	local debuffCount = 0
	local shownTotal = 0
	local debAnchor = ac.debuffAnchor or ac.anchor or "BOTTOM"
	local perRowDebuff = perRow
	local i = 1
	while i <= #targetAuraOrder do
		local auraId = targetAuraOrder[i]
		local aura = auraId and targetAuras[auraId]
		if not aura then
			table.remove(targetAuraOrder, i)
			targetAuraIndexById[auraId] = nil
			reindexTargetAuraOrder(i)
		else
			local isDebuff
			if issecretvalue and issecretvalue(aura.isHarmful) then
				isDebuff = not C_UnitAuras.IsAuraFilteredOutByInstanceID("target", aura.auraInstanceID, "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY")
			else
				isDebuff = aura.isHarmful == true
			end
			if shownTotal < ac.max then
				shownTotal = shownTotal + 1
				if isDebuff then
					debuffCount = debuffCount + 1
					local btn
					btn, debuffButtons = ensureAuraButton(st.debuffContainer, debuffButtons, debuffCount, ac)
					applyAuraToButton(btn, aura, ac, true, "target")
					anchorAuraButton(btn, st.debuffContainer, debuffCount, ac, perRowDebuff, debAnchor)
				else
					buffCount = buffCount + 1
					local btn
					btn, buffButtons = ensureAuraButton(st.auraContainer, buffButtons, buffCount, ac)
					applyAuraToButton(btn, aura, ac, false, "target")
					anchorAuraButton(btn, st.auraContainer, buffCount, ac, perRow, ac.anchor or "BOTTOM")
				end
			end
			targetAuraIndexById[auraId] = i
			i = i + 1
		end
	end

	st.auraButtons = buffButtons
	st.debuffButtons = debuffButtons

	for idx = buffCount + 1, #buffButtons do
		if buffButtons[idx] then buffButtons[idx]:Hide() end
	end
	for idx = debuffCount + 1, #debuffButtons do
		if debuffButtons[idx] then debuffButtons[idx]:Hide() end
	end

	updateAuraContainerSize(st.auraContainer, math.min(buffCount, ac.max), ac, perRow)
	updateAuraContainerSize(st.debuffContainer, math.min(debuffCount, ac.max), ac, perRowDebuff)
end

local function fullScanTargetAuras()
	resetTargetAuras()
	if not UnitExists or not UnitExists("target") then return end
	local cfg = ensureDB("target")
	local ac = cfg.auraIcons or defaults.target.auraIcons or {}
	local hidePermanent = ac.hidePermanentAuras == true or ac.hidePermanent == true
	if C_UnitAuras and C_UnitAuras.GetUnitAuras then
		local helpful = C_UnitAuras.GetUnitAuras("target", "HELPFUL|INCLUDE_NAME_PLATE_ONLY")
		for i = 1, #helpful do
			local aura = helpful[i]
			if aura and (not hidePermanent or not isPermanentAura(aura, "target")) then
				cacheTargetAura(aura)
				addTargetAuraToOrder(aura.auraInstanceID)
			end
		end
		local harmful = C_UnitAuras.GetUnitAuras("target", "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY")
		for i = 1, #harmful do
			local aura = harmful[i]
			if aura and (not hidePermanent or not isPermanentAura(aura, "target")) then
				cacheTargetAura(aura)
				addTargetAuraToOrder(aura.auraInstanceID)
			end
		end
	elseif C_UnitAuras and C_UnitAuras.GetAuraSlots then
		local helpful = { C_UnitAuras.GetAuraSlots("target", "HELPFUL|CANCELABLE") }
		for i = 2, #helpful do
			local slot = helpful[i]
			local aura = C_UnitAuras.GetAuraDataBySlot("target", slot)
			if aura and (not hidePermanent or not isPermanentAura(aura, "target")) then
				cacheTargetAura(aura)
				addTargetAuraToOrder(aura.auraInstanceID)
			end
		end
		local harmful = { C_UnitAuras.GetAuraSlots("target", "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY") }
		for i = 2, #harmful do
			local slot = harmful[i]
			local aura = C_UnitAuras.GetAuraDataBySlot("target", slot)
			if aura and (not hidePermanent or not isPermanentAura(aura, "target")) then
				cacheTargetAura(aura)
				addTargetAuraToOrder(aura.auraInstanceID)
			end
		end
	end
	updateTargetAuraIcons()
end

local function refreshMainPower(unit)
	unit = unit or UNIT.PLAYER
	local enumId, token = UnitPowerType(unit)
	if unit == UNIT.PLAYER then
		mainPowerEnum, mainPowerToken = enumId, token
	end
	return enumId, token
end
local function getMainPower(unit)
	if unit and unit ~= UNIT.PLAYER then return UnitPowerType(unit) end
	if not mainPowerEnum or not mainPowerToken then return refreshMainPower(UNIT.PLAYER) end
	return mainPowerEnum, mainPowerToken
end
local function findTreeNode(path)
	if not addon.treeGroupData or type(path) ~= "string" then return nil end
	local segments = {}
	for seg in string.gmatch(path, "[^\001]+") do
		segments[#segments + 1] = seg
	end
	local function search(children, idx)
		if not children then return nil end
		for _, node in ipairs(children) do
			if node.value == segments[idx] then
				if idx == #segments then return node end
				return search(node.children, idx + 1)
			end
		end
		return nil
	end
	return search(addon.treeGroupData, 1)
end

local function getFrameInfo(frameName)
	if not addon.variables or not addon.variables.unitFrameNames then return nil end
	for _, info in ipairs(addon.variables.unitFrameNames) do
		if info.name == frameName then return info end
	end
	return nil
end

local function applyVisibilityDriver(unit, enabled)
	if InCombatLockdown() then return end
	local st = states[unit]
	if not st or not st.frame or not RegisterStateDriver then return end
	local cond
	if not enabled then
		cond = "hide"
	elseif unit == UNIT.TARGET then
		cond = "[@target,exists] show; hide"
	elseif unit == UNIT.TARGET_TARGET then
		cond = "[@targettarget,exists] show; hide"
	elseif unit == UNIT.FOCUS then
		cond = "[@focus,exists] show; hide"
	elseif unit == UNIT.PET then
		cond = "[@pet,exists] show; hide"
	elseif isBossUnit(unit) then
		cond = ("[@%s,exists] show; hide"):format(unit)
	end
	if cond == st._visibilityCond then return end
	if not cond then
		if UnregisterStateDriver then UnregisterStateDriver(st.frame, "visibility") end
		st._visibilityCond = nil
		return
	end
	if UnregisterStateDriver then UnregisterStateDriver(st.frame, "visibility") end
	st.frame:SetAttribute("state-visibility", nil)
	RegisterStateDriver(st.frame, "visibility", cond)
	st._visibilityCond = cond
end

local function applyFrameRuleOverride(frameName, enabled)
	if not frameName then return end
	local info = getFrameInfo(frameName)
	if not info then
		if frameName == UF_FRAME_NAMES.targettarget.frame then
			info = { name = UF_FRAME_NAMES.targettarget.frame, var = "unitframeSettingTargetTargetFrame", unitToken = UNIT.TARGET_TARGET }
		else
			return
		end
	end
	local function frameNameFor(unitToken)
		if unitToken == UNIT.PLAYER then return BLIZZ_FRAME_NAMES.player end
		if unitToken == UNIT.TARGET then return BLIZZ_FRAME_NAMES.target end
		if unitToken == UNIT.TARGET_TARGET then return BLIZZ_FRAME_NAMES.targettarget end
		if unitToken == UNIT.FOCUS then return BLIZZ_FRAME_NAMES.focus end
		if unitToken == UNIT.PET then return BLIZZ_FRAME_NAMES.pet end
	end
	local NormalizeUnitFrameVisibilityConfig = addon.functions and addon.functions.NormalizeUnitFrameVisibilityConfig
	local UpdateUnitFrameMouseover = addon.functions and addon.functions.UpdateUnitFrameMouseover
	if not NormalizeUnitFrameVisibilityConfig or not UpdateUnitFrameMouseover then return end
	addon.db = addon.db or {}
	local key = info.var
	if enabled then
		if originalFrameRules[key] == nil then
			local cur = addon.db[key]
			if cur == nil then
				originalFrameRules[key] = NIL_VISIBILITY_SENTINEL
			else
				originalFrameRules[key] = cur
			end
		end
		if SetFrameVisibilityOverride then
			SetFrameVisibilityOverride(key, { ALWAYS_HIDDEN = true })
		else
			NormalizeUnitFrameVisibilityConfig(key, { ALWAYS_HIDDEN = true })
		end
	else
		if SetFrameVisibilityOverride then SetFrameVisibilityOverride(key, nil) end
		if originalFrameRules[key] ~= nil then
			local prev = originalFrameRules[key]
			if prev == NIL_VISIBILITY_SENTINEL then
				addon.db[key] = nil
			else
				addon.db[key] = prev
			end
			originalFrameRules[key] = nil
		elseif not HasFrameVisibilityOverride or not HasFrameVisibilityOverride(key) then
			NormalizeUnitFrameVisibilityConfig(key, nil)
		end
	end
	UpdateUnitFrameMouseover(info.name, info)
	if enabled then hardHideBlizzFrame(info.name or frameNameFor(info.unitToken)) end
end

local function normalizeVisibilityConfig(config)
	if NormalizeUnitFrameVisibilityConfig then return NormalizeUnitFrameVisibilityConfig(nil, config, { skipSave = true, ignoreOverride = true }) end
	if type(config) == "table" then return config end
	return nil
end

local function applyVisibilityRules(unit)
	if not ApplyFrameVisibilityConfig then return end
	local cfg = ensureDB(unit)
	if unit == UNIT.PLAYER and cfg and type(cfg.visibility) == "table" and cfg.visibility.PLAYER_HEALTH_NOT_FULL then
		cfg.visibility.PLAYER_HEALTH_NOT_FULL = nil
		if not next(cfg.visibility) then cfg.visibility = nil end
	end
	local inEdit = addon.EditModeLib and addon.EditModeLib.IsInEditMode and addon.EditModeLib:IsInEditMode()
	local useConfig = (not inEdit and cfg and cfg.enabled) and normalizeVisibilityConfig(cfg.visibility) or nil
	local opts = { noStateDriver = true }
	if unit == "boss" then
		for i = 1, maxBossFrames do
			local info = UNITS["boss" .. i]
			if info and info.frameName then ApplyFrameVisibilityConfig(info.frameName, { unitToken = "boss" }, useConfig, opts) end
		end
		return
	end
	local info = UNITS[unit]
	if info and info.frameName then ApplyFrameVisibilityConfig(info.frameName, { unitToken = info.unit }, useConfig, opts) end
end

local function applyVisibilityRulesAll()
	applyVisibilityRules("player")
	applyVisibilityRules("target")
	applyVisibilityRules(UNIT.TARGET_TARGET)
	applyVisibilityRules("focus")
	applyVisibilityRules("pet")
	applyVisibilityRules("boss")
end

local function addTreeNode(path, node, parentPath)
	if not addon.functions or not addon.functions.addToTree then return end
	if findTreeNode(path) then return end
	addon.functions.addToTree(parentPath, node, true)
end

local function removeTreeNode(path)
	if not addon.treeGroupData or not addon.treeGroup then return end
	local segments = {}
	for seg in string.gmatch(path, "[^\001]+") do
		segments[#segments + 1] = seg
	end
	if #segments == 0 then return end
	local function remove(children, idx)
		if not children then return false end
		for i, node in ipairs(children) do
			if node.value == segments[idx] then
				if idx == #segments then
					table.remove(children, i)
					if addon.treeGroup.SetTree then addon.treeGroup:SetTree(addon.treeGroupData) end
					if addon.treeGroup.RefreshTree then addon.treeGroup:RefreshTree() end
					return true
				elseif node.children then
					local removed = remove(node.children, idx + 1)
					if removed and #node.children == 0 then node.children = nil end
					return removed
				end
			end
		end
		return false
	end
	remove(addon.treeGroupData, 1)
end

local function ensureRootNode() addTreeNode("ufplus", { value = "ufplus", text = L["UFPlusRoot"] or "UF Plus" }, nil) end

local function getPowerColor(pToken)
	if not pToken then pToken = EnumPowerType.MANA end
	local overrides = addon.db and addon.db.ufPowerColorOverrides
	local override = overrides and overrides[pToken]
	if override then
		if override.r then return override.r, override.g, override.b, override.a or 1 end
		if override[1] then return override[1], override[2], override[3], override[4] or 1 end
	end
	if PowerBarColor then
		local c = PowerBarColor[pToken]
		if c then
			if c.r then return c.r, c.g, c.b, c.a or 1 end
			if c[1] then return c[1], c[2], c[3], c[4] or 1 end
		end
	end
	return 0.1, 0.45, 1, 1
end

local function isPowerDesaturated(pToken)
	if not pToken then return false end
	local overrides = addon.db and addon.db.ufPowerColorOverrides
	return overrides and overrides[pToken] ~= nil
end

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

local function hideBlizzardPlayerFrame()
	if not _G.PlayerFrame then return end
	if not InCombatLockdown() and ensureDB("player").enabled then _G.PlayerFrame:Hide() end
	if not blizzardPlayerHooked then
		_G.PlayerFrame:HookScript("OnShow", function(frame)
			if ensureDB("player").enabled then
				frame:Hide()
			else
				frame:Show()
			end
		end)
		blizzardPlayerHooked = true
	end
end

local function hideBlizzardTargetFrame()
	if not _G.TargetFrame then return end
	if not InCombatLockdown() and ensureDB("target").enabled then _G.TargetFrame:Hide() end
	if not blizzardTargetHooked then
		_G.TargetFrame:HookScript("OnShow", function(frame)
			if ensureDB("target").enabled then
				frame:Hide()
			else
				frame:Show()
			end
		end)
		blizzardTargetHooked = true
	end
end

local function mergeDefaults(base, override)
	local merged = CopyTable(base or {})
	if type(override) ~= "table" then return merged end
	for k, v in pairs(override) do
		if type(v) == "table" and type(merged[k]) == "table" then
			merged[k] = mergeDefaults(merged[k], v)
		elseif type(v) == "table" then
			merged[k] = CopyTable(v)
		else
			merged[k] = v
		end
	end
	return merged
end

do
	local targetDefaults = mergeDefaults(defaults.player, defaults.target)
	targetDefaults.enabled = false
	targetDefaults.anchor = targetDefaults.anchor and CopyTable(targetDefaults.anchor) or { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 0, y = -200 }
	targetDefaults.anchor.x = (targetDefaults.anchor.x or 0) + 260
	targetDefaults.auraIcons = {
		size = 24,
		padding = 2,
		max = 16,
		showCooldown = true,
		showTooltip = true,
		hidePermanentAuras = false,
		anchor = "BOTTOM",
		offset = { x = 0, y = -5 },
		separateDebuffAnchor = false,
		debuffAnchor = nil,
		debuffOffset = nil,
		countAnchor = "BOTTOMRIGHT",
		countOffset = { x = -2, y = 2 },
		countFontSize = nil,
		countFontOutline = nil,
	}
	defaults.target = targetDefaults

	local totDefaults = CopyTable(targetDefaults)
	totDefaults.enabled = false
	totDefaults.auraIcons = nil
	totDefaults.width = 180
	totDefaults.healthHeight = 20
	totDefaults.powerHeight = 12
	totDefaults.statusHeight = 16
	totDefaults.anchor = totDefaults.anchor and CopyTable(totDefaults.anchor) or { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 0, y = -200 }
	totDefaults.anchor.x = (totDefaults.anchor.x or 0) + 260
	defaults.targettarget = totDefaults

	local focusDefaults = CopyTable(targetDefaults)
	focusDefaults.enabled = false
	focusDefaults.anchor = focusDefaults.anchor and CopyTable(focusDefaults.anchor) or { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 0, y = -200 }
	focusDefaults.anchor.x = (focusDefaults.anchor.x or 0) - 260
	defaults.focus = focusDefaults

	local petDefaults = CopyTable(defaults.player)
	petDefaults.enabled = false
	petDefaults.anchor = petDefaults.anchor and CopyTable(petDefaults.anchor) or { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 0, y = -200 }
	petDefaults.anchor.x = (petDefaults.anchor.x or 0) - 260
	petDefaults.width = 200
	petDefaults.healthHeight = 20
	petDefaults.powerHeight = 12
	petDefaults.statusHeight = 16
	petDefaults.health.absorbUseCustomColor = false
	petDefaults.health.useAbsorbGlow = false
	petDefaults.health.showSampleAbsorb = false
	if petDefaults.status and petDefaults.status.combatIndicator then petDefaults.status.combatIndicator.enabled = false end
	defaults.pet = petDefaults

	local bossDefaults = CopyTable(defaults.target)
	bossDefaults.enabled = false
	bossDefaults.anchor = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 400, y = 200 }
	bossDefaults.width = 220
	bossDefaults.healthHeight = 20
	bossDefaults.powerHeight = 10
	bossDefaults.statusHeight = 16
	bossDefaults.barGap = 0
	bossDefaults.spacing = 4
	bossDefaults.growth = "DOWN"
	bossDefaults.health.useClassColor = false
	bossDefaults.health.useCustomColor = false
	bossDefaults.health.useAbsorbGlow = false
	bossDefaults.health.showSampleAbsorb = false
	bossDefaults.health.absorbUseCustomColor = false
	if bossDefaults.status then bossDefaults.status.nameColorMode = "CUSTOM" end
	defaults.boss = bossDefaults
end

local function resolveBorderTexture(key)
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
	border:SetFrameLevel(baseLevel + 2)
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
		borderFrame:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = resolveBorderTexture(borderCfg.texture),
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

local function resolveTexture(key)
	if key == "SOLID" then return "Interface\\Buttons\\WHITE8x8" end
	if not key or key == "DEFAULT" then return BLIZZARD_TEX end
	if LSM then
		local tex = LSM:Fetch("statusbar", key)
		if tex then return tex end
	end
	return key
end

local function resolveCastTexture(key)
	if key == "SOLID" then return "Interface\\Buttons\\WHITE8x8" end
	if not key or key == "DEFAULT" then
		if CASTING_BAR_TYPES and CASTING_BAR_TYPES.standard and CASTING_BAR_TYPES.standard.full then return CASTING_BAR_TYPES.standard.full end
		return BLIZZARD_TEX
	end
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

local function resolveTextDelimiter(delimiter)
	if delimiter == nil or delimiter == "" then delimiter = " " end
	if delimiter == " " then return " " end
	return " " .. tostring(delimiter) .. " "
end

local function formatText(mode, cur, maxv, useShort, percentValue, delimiter)
	if mode == "NONE" then return "" end
	local join = resolveTextDelimiter(delimiter)
	if addon.variables and addon.variables.isMidnight and issecretvalue then
		if (cur and issecretvalue(cur)) or (maxv and issecretvalue(maxv)) then
			local scur = useShort and shortValue(cur) or BreakUpLargeNumbers(cur)
			local smax = useShort and shortValue(maxv) or BreakUpLargeNumbers(maxv)
			local percentText
			if percentValue ~= nil then percentText = ("%s%%"):format(tostring(AbbreviateLargeNumbers(percentValue))) end

			if mode == "CURRENT" then return tostring(scur) end
			if mode == "CURMAX" then return ("%s/%s"):format(tostring(scur), tostring(smax)) end
			if mode == "PERCENT" then return percentText or "" end
			if mode == "CURPERCENT" or mode == "CURPERCENTDASH" then return percentText and ("%s%s%s"):format(tostring(scur), join, percentText) or "" end
			if mode == "CURMAXPERCENT" then return percentText and ("%s/%s%s%s"):format(tostring(scur), tostring(smax), join, percentText) or "" end
			return ""
		end
	end
	local percentText
	if mode == "PERCENT" or mode == "CURPERCENT" or mode == "CURPERCENTDASH" or mode == "CURMAXPERCENT" then
		if percentValue ~= nil then
			percentText = ("%d%%"):format(floor(percentValue + 0.5))
		elseif not maxv or maxv == 0 then
			percentText = "0%"
		else
			percentText = ("%d%%"):format(floor((cur or 0) / maxv * 100 + 0.5))
		end
	end
	if mode == "PERCENT" then return percentText end
	if mode == "CURMAX" then
		local curText = useShort == false and tostring(cur or 0) or shortValue(cur or 0)
		local maxText = useShort == false and tostring(maxv or 0) or shortValue(maxv or 0)
		return ("%s/%s"):format(curText, maxText)
	end
	if mode == "CURPERCENT" or mode == "CURPERCENTDASH" then
		if not percentText then return "" end
		local curText = useShort == false and tostring(cur or 0) or shortValue(cur or 0)
		return ("%s%s%s"):format(curText, join, percentText)
	end
	if mode == "CURMAXPERCENT" then
		if not percentText then return "" end
		local curText = useShort == false and tostring(cur or 0) or shortValue(cur or 0)
		local maxText = useShort == false and tostring(maxv or 0) or shortValue(maxv or 0)
		return ("%s/%s%s%s"):format(curText, maxText, join, percentText)
	end
	if useShort == false then return tostring(cur or 0) end
	return shortValue(cur or 0)
end

local nameWidthCache = {}

local function getNameLimitWidth(fontPath, fontSize, fontOutline, maxChars)
	if not maxChars or maxChars <= 0 then return nil end
	local font = getFont(fontPath)
	local size = fontSize or 14
	local outline = fontOutline or "OUTLINE"
	local key = tostring(font) .. "|" .. tostring(size) .. "|" .. tostring(outline) .. "|" .. tostring(maxChars)
	if nameWidthCache[key] then return nameWidthCache[key] end
	if not nameWidthCache._measure and UIParent and UIParent.CreateFontString then
		nameWidthCache._measure = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		if nameWidthCache._measure then nameWidthCache._measure:Hide() end
	end
	local measure = nameWidthCache._measure
	if not measure then return nil end
	measure:SetFont(font, size, outline)
	measure:SetText(string.rep("i", maxChars))
	local width = measure:GetStringWidth() or 0
	nameWidthCache[key] = width
	return width
end

local function applyNameCharLimit(st, scfg, defStatus)
	if not st or not st.nameText then return end
	local maxChars = scfg and scfg.nameMaxChars
	if maxChars == nil and defStatus then maxChars = defStatus.nameMaxChars end
	maxChars = tonumber(maxChars) or 0
	if maxChars <= 0 then
		if st.nameText.SetMaxLines then st.nameText:SetMaxLines(1) end
		if st.nameText.SetWordWrap then st.nameText:SetWordWrap(false) end
		st.nameText:SetWidth(0)
		return
	end
	if st.nameText.SetMaxLines then st.nameText:SetMaxLines(1) end
	if st.nameText.SetWordWrap then st.nameText:SetWordWrap(false) end
	local width = getNameLimitWidth(scfg and scfg.font, scfg and scfg.fontSize or 14, scfg and scfg.fontOutline or "OUTLINE", maxChars)
	if width and width > 0 then st.nameText:SetWidth(width) end
end

local function getTextDelimiter(cfg, def)
	local defaultDelim = (def and def.textDelimiter) or " "
	local delimiter = cfg and cfg.textDelimiter
	if delimiter == nil or delimiter == "" then delimiter = defaultDelim end
	return delimiter
end

local function getAbsorbColor(hc, unit)
	local def = defaultsFor(unit)
	local defaultAbsorb = (def.health and def.health.absorbColor) or { 0.85, 0.95, 1, 0.7 }
	if hc and hc.absorbUseCustomColor and hc.absorbColor then
		return hc.absorbColor[1] or defaultAbsorb[1], hc.absorbColor[2] or defaultAbsorb[2], hc.absorbColor[3] or defaultAbsorb[3], hc.absorbColor[4] or defaultAbsorb[4]
	end
	return defaultAbsorb[1], defaultAbsorb[2], defaultAbsorb[3], defaultAbsorb[4]
end

local function shouldShowSampleAbsorb(unit) return sampleAbsorb and sampleAbsorb[unit] == true end

local function stopCast(unit)
	local st = states[unit]
	if not st or not st.castBar then return end
	st.castBar:Hide()
	if st.castName then st.castName:SetText("") end
	if st.castDuration then st.castDuration:SetText("") end
	if st.castIcon then st.castIcon:Hide() end
	st.castInfo = nil
	if castOnUpdateHandlers[unit] then
		st.castBar:SetScript("OnUpdate", nil)
		castOnUpdateHandlers[unit] = nil
	end
end

local function applyCastLayout(cfg, unit)
	local st = states[unit]
	if not st or not st.castBar then return end
	local def = defaultsFor(unit)
	local ccfg = (cfg and cfg.cast) or {}
	local defc = (def and def.cast) or {}
	local width = ccfg.width or (cfg and cfg.width) or defc.width or (def and def.width) or 220
	local height = ccfg.height or defc.height or 16
	st.castBar:SetSize(width, height)
	local anchor = (ccfg.anchor or defc.anchor or "BOTTOM")
	local off = ccfg.offset or defc.offset or { x = 0, y = -4 }
	local anchorFrame = st.barGroup or st.frame
	st.castBar:ClearAllPoints()
	if anchor == "TOP" then
		st.castBar:SetPoint("BOTTOM", anchorFrame, "TOP", off.x or 0, off.y or 0)
	else
		st.castBar:SetPoint("TOP", anchorFrame, "BOTTOM", off.x or 0, off.y or 0)
	end
	if st.castName then
		local nameOff = ccfg.nameOffset or defc.nameOffset or { x = 6, y = 0 }
		st.castName:ClearAllPoints()
		st.castName:SetPoint("LEFT", st.castBar, "LEFT", nameOff.x or 0, nameOff.y or 0)
		st.castName:SetShown(ccfg.showName ~= false)
	end
	if st.castDuration then
		local durOff = ccfg.durationOffset or defc.durationOffset or { x = -6, y = 0 }
		st.castDuration:ClearAllPoints()
		st.castDuration:SetPoint("RIGHT", st.castBar, "RIGHT", durOff.x or 0, durOff.y or 0)
		st.castDuration:SetShown(ccfg.showDuration ~= false)
		if st.castDuration.SetWordWrap then st.castDuration:SetWordWrap(false) end
		if st.castDuration.SetJustifyH then st.castDuration:SetJustifyH("RIGHT") end
	end
	if st.castIcon then
		local size = ccfg.iconSize or defc.iconSize or height
		st.castIcon:SetSize(size, size)
		st.castIcon:ClearAllPoints()
		st.castIcon:SetPoint("RIGHT", st.castBar, "LEFT", -4, 0)
		st.castIcon:SetShown(ccfg.showIcon ~= false)
	end
	local texKey = ccfg.texture or defc.texture or "DEFAULT"
	local castTexture = resolveCastTexture(texKey)
	st.castBar:SetStatusBarTexture(castTexture)
	do -- Cast backdrop
		local bd = (ccfg and ccfg.backdrop) or (defc and defc.backdrop) or { enabled = true, color = { 0, 0, 0, 0.6 } }
		if st.castBar.SetBackdrop then st.castBar:SetBackdrop(nil) end
		local bg = st.castBar.backdropTexture
		if bd.enabled == false then
			if bg then bg:Hide() end
		else
			if not bg then
				bg = st.castBar:CreateTexture(nil, "BACKGROUND")
				st.castBar.backdropTexture = bg
			end
			local col = bd.color or { 0, 0, 0, 0.6 }
			bg:ClearAllPoints()
			local useBlizzBackdrop = not texKey or texKey == "" or texKey == "DEFAULT"
			if useBlizzBackdrop and bg.SetAtlas then
				bg:SetAtlas("ui-castingbar-background", false)
				bg:SetPoint("TOPLEFT", st.castBar, "TOPLEFT", -1, 1)
				bg:SetPoint("BOTTOMRIGHT", st.castBar, "BOTTOMRIGHT", 1, -1)
			else
				bg:SetTexture(castTexture)
				bg:SetAllPoints(st.castBar)
			end
			bg:SetVertexColor(col[1] or 0, col[2] or 0, col[3] or 0, col[4] or 0.6)
			bg:Show()
		end
	end
	-- Limit cast name width so long names don't overlap duration text
	if st.castName then
		local iconSize = (ccfg.iconSize or defc.iconSize or height) + 4
		if ccfg.showIcon == false then iconSize = 0 end
		local durationSpace = (ccfg.showDuration ~= false) and 60 or 0
		local available = (width or 0) - iconSize - durationSpace - 6
		if available < 0 then available = 0 end
		st.castName:SetWidth(available)
		if st.castName.SetWordWrap then st.castName:SetWordWrap(false) end
		if st.castName.SetMaxLines then st.castName:SetMaxLines(1) end
		if st.castName.SetJustifyH then st.castName:SetJustifyH("LEFT") end
	end
end

local function configureCastStatic(unit, ccfg, defc)
	local st = states[unit]
	if not st or not st.castBar or not st.castInfo then return end
	ccfg = ccfg or st.castCfg or {}
	defc = defc or (defaultsFor(unit) and defaultsFor(unit).cast) or {}
	local clr = ccfg.color or defc.color or { 0.9, 0.7, 0.2, 1 }
	if st.castInfo.notInterruptible then
		clr = ccfg.notInterruptibleColor or defc.notInterruptibleColor or clr
		st.castBar:SetStatusBarDesaturated(true)
	end
	st.castBar:SetStatusBarColor(clr[1] or 0.9, clr[2] or 0.7, clr[3] or 0.2, clr[4] or 1)
	local duration = (st.castInfo.endTime or 0) - (st.castInfo.startTime or 0)
	local maxValue = duration and duration > 0 and duration / 1000 or 1
	if st.castBar.SetReverseFill then st.castBar:SetReverseFill(st.castInfo.isChannel == true) end
	st.castBar:SetMinMaxValues(0, maxValue)
	if st.castName then
		local showName = ccfg.showName ~= false
		st.castName:SetShown(showName)
		st.castName:SetText(showName and (st.castInfo.name or "") or "")
	end
	if st.castIcon then
		local showIcon = ccfg.showIcon ~= false and st.castInfo.texture ~= nil
		st.castIcon:SetShown(showIcon)
		if showIcon then st.castIcon:SetTexture(st.castInfo.texture) end
	end
	if st.castDuration then st.castDuration:SetShown(ccfg.showDuration ~= false) end
	st.castBar:Show()
end

local function updateCastBar(unit)
	local st = states[unit]
	local ccfg = st and st.castCfg
	if not st or not st.castBar or not st.castInfo or not st.castInfo.startTime or not st.castInfo.endTime or not ccfg then
		stopCast(unit)
		return
	end
	if issecretvalue and (issecretvalue(st.castInfo.startTime) or issecretvalue(st.castInfo.endTime)) then
		stopCast(unit)
		return
	end
	local nowMs = GetTime() * 1000
	local startMs = st.castInfo.startTime or 0
	local endMs = st.castInfo.endTime or 0
	local duration = endMs - startMs
	if not duration or duration <= 0 then
		stopCast(unit)
		return
	end
	if nowMs >= endMs then
		if shouldShowSampleCast(unit) then
			setSampleCast(unit)
		else
			stopCast(unit)
		end
		return
	end
	local elapsedMs = st.castInfo.isChannel and (endMs - nowMs) or (nowMs - startMs)
	if elapsedMs < 0 then elapsedMs = 0 end
	local value = elapsedMs / 1000
	st.castBar:SetValue(value)
	if st.castDuration then
		if ccfg.showDuration ~= false then
			local remaining = (endMs - nowMs) / 1000
			if remaining < 0 then remaining = 0 end
			st.castDuration:SetText(("%.1f"):format(remaining))
			st.castDuration:Show()
		else
			st.castDuration:SetText("")
			st.castDuration:Hide()
		end
	end
end

shouldShowSampleCast = function(unit)
	if not (addon.EditModeLib and addon.EditModeLib:IsInEditMode()) then return false end
	local key = isBossUnit(unit) and "boss" or unit
	return sampleCast and sampleCast[key] == true
end

setSampleCast = function(unit)
	local key = isBossUnit(unit) and "boss" or unit
	local st = states[unit]
	if not st or not st.castBar then return end
	local cfg = (st and st.cfg) or ensureDB(key or unit)
	local ccfg = (cfg or {}).cast or {}
	local def = defaultsFor(unit)
	local defc = (def and def.cast) or {}
	if ccfg.enabled == false then
		stopCast(unit)
		return
	end
	local resolvedCfg = ccfg or defc or {}
	st.castCfg = resolvedCfg
	local nowMs = GetTime() * 1000
	st.castInfo = {
		name = L["Sample Cast"] or "Sample Cast",
		texture = 136235, -- lightning icon as placeholder
		startTime = nowMs,
		endTime = nowMs + 3000,
		notInterruptible = false,
		isChannel = false,
	}
	applyCastLayout(cfg, unit)
	configureCastStatic(unit, resolvedCfg, defc)
	if not castOnUpdateHandlers[unit] then
		st.castBar:SetScript("OnUpdate", function() updateCastBar(unit) end)
		castOnUpdateHandlers[unit] = true
	end
	updateCastBar(unit)
end

local function setCastInfoFromUnit(unit)
	local key = isBossUnit(unit) and "boss" or unit
	local st = states[unit]
	if not st or not st.castBar then return end
	local cfg = (st and st.cfg) or ensureDB(key or unit)
	local ccfg = (cfg or {}).cast or {}
	local defc = (defaultsFor(unit) and defaultsFor(unit).cast) or {}
	if ccfg.enabled == false then
		stopCast(unit)
		return
	end
	local name, text, texture, startTimeMS, endTimeMS, _, notInterruptible, _, isEmpowered, numEmpowerStages = UnitChannelInfo(unit)
	local isChannel = true
	if not name then
		name, text, texture, startTimeMS, endTimeMS, _, _, notInterruptible = UnitCastingInfo(unit)
		isChannel = false
	end
	if not name then
		if shouldShowSampleCast(unit) then
			setSampleCast(unit)
		else
			stopCast(unit)
		end
		return
	end

	if issecretvalue and ((startTimeMS and issecretvalue(startTimeMS)) or (endTimeMS and issecretvalue(endTimeMS))) then
		if type(startTimeMS) ~= "nil" and type(endTimeMS) ~= "nil" then
			st.castBar:Show()

			local durObj, direction
			if isChannel then
				durObj = UnitChannelDuration(unit)
				direction = Enum.StatusBarTimerDirection.RemainingTime
			else
				durObj = UnitCastingDuration(unit)
				direction = Enum.StatusBarTimerDirection.ElapsedTime
			end
			st.castBar:SetTimerDuration(durObj, Enum.StatusBarInterpolation.Immediate, direction)
			if st.castName then
				local showName = ccfg.showName ~= false
				st.castName:SetShown(showName)
				st.castName:SetText(showName and (text or name or "") or "")
			end
			if st.castIcon then
				local showIcon = ccfg.showIcon ~= false and texture ~= nil
				st.castIcon:SetShown(showIcon)
				if showIcon then st.castIcon:SetTexture(texture) end
			end
			local clr = ccfg.color or defc.color or { 0.9, 0.7, 0.2, 1 }
			local nclr = ccfg.notInterruptibleColor or defc.notInterruptibleColor or { 204 / 255, 204 / 255, 204 / 255, 1 }
			st.castBar:GetStatusBarTexture():SetVertexColorFromBoolean(
				notInterruptible,
				CreateColor(nclr[1] or 0.9, nclr[2] or 0.7, nclr[3] or 0.2, nclr[4] or 1),
				CreateColor(clr[1] or 0.9, clr[2] or 0.7, clr[3] or 0.2, clr[4] or 1)
			)
			st.castBar:SetStatusBarDesaturated(true)
		else
			stopCast(unit)
		end
		return
	end
	local duration = (endTimeMS or 0) - (startTimeMS or 0)
	if not duration or duration <= 0 then
		stopCast(unit)
		return
	end
	local resolvedCfg = ccfg or defc or {}
	st.castCfg = resolvedCfg
	st.castInfo = {
		name = text or name,
		texture = texture,
		startTime = startTimeMS,
		endTime = endTimeMS,
		notInterruptible = notInterruptible,
		isChannel = isChannel,
	}
	applyCastLayout(cfg, unit)
	configureCastStatic(unit, resolvedCfg, defc)
	if not castOnUpdateHandlers[unit] then
		st.castBar:SetScript("OnUpdate", function() updateCastBar(unit) end)
		castOnUpdateHandlers[unit] = true
	end
	updateCastBar(unit)
end

local function getHealthPercent(unit, cur, maxv)
	if addon.functions and addon.functions.GetHealthPercent then return addon.functions.GetHealthPercent(unit, cur, maxv, true) end
	if maxv and maxv > 0 then return (cur or 0) / maxv * 100 end
	return nil
end

local function getPowerPercent(unit, powerEnum, cur, maxv)
	if addon.functions and addon.functions.GetPowerPercent then return addon.functions.GetPowerPercent(unit, powerEnum, cur, maxv, true) end
	if maxv and maxv > 0 then return (cur or 0) / maxv * 100 end
	return nil
end

local function updateHealth(cfg, unit)
	cfg = cfg or (states[unit] and states[unit].cfg) or ensureDB(unit)
	local st = states[unit]
	if not st or not st.health or not st.frame then return end
	local info = UNITS[unit]
	local allowAbsorb = not (info and info.disableAbsorb)
	local def = defaultsFor(unit) or {}
	local defH = def.health or {}
	local cur = UnitHealth(unit)
	local maxv = UnitHealthMax(unit)
	if issecretvalue and issecretvalue(maxv) then
		st.health:SetMinMaxValues(0, maxv or 1)
	else
		st.health:SetMinMaxValues(0, maxv > 0 and maxv or 1)
	end
	st.health:SetValue(cur or 0)
	local hc = cfg.health or {}
	local percentVal
	if addon.variables and addon.variables.isMidnight then
		percentVal = getHealthPercent(unit, cur, maxv)
	elseif not issecretvalue or (not issecretvalue(cur) and not issecretvalue(maxv)) then
		percentVal = getHealthPercent(unit, cur, maxv)
	end
	local hr, hg, hb, ha
	if hc.useCustomColor and hc.color then
		hr, hg, hb, ha = hc.color[1], hc.color[2], hc.color[3], hc.color[4] or 1
	elseif hc.useClassColor then
		local class = select(2, UnitClass(unit))
		local c = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
		if c then
			hr, hg, hb, ha = c.r or c[1], c.g or c[2], c.b or c[3], c.a or c[4]
		end
	end
	if not hr then
		local color = defH.color or { 0, 0.8, 0, 1 }
		hr, hg, hb, ha = color[1] or 0, color[2] or 0.8, color[3] or 0, color[4] or 1
	end
	st.health:SetStatusBarColor(hr or 0, hg or 0.8, hb or 0, ha or 1)
	if allowAbsorb and st.absorb then
		local abs = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0
		local maxForValue
		if issecretvalue and issecretvalue(maxv) then
			maxForValue = maxv or 1
		else
			maxForValue = (maxv and maxv > 0) and maxv or 1
		end
		st.absorb:SetMinMaxValues(0, maxForValue or 1)
		local hasVisibleAbsorb = abs and (not issecretvalue or not issecretvalue(abs)) and abs > 0
		if shouldShowSampleAbsorb(unit) and not hasVisibleAbsorb and (not issecretvalue or not issecretvalue(maxForValue)) then abs = (maxForValue or 1) * 0.6 end
		st.absorb:SetValue(abs or 0)
		local ar, ag, ab, aa = getAbsorbColor(hc, unit)
		st.absorb:SetStatusBarColor(ar or 0.85, ag or 0.95, ab or 1, aa or 0.7)
		if st.overAbsorbGlow then
			local showGlow = hc.useAbsorbGlow ~= false and ((C_StringUtil and not C_StringUtil.TruncateWhenZero(abs)) or (not issecretvalue and abs > 0))
			-- (not (C_StringUtil and C_StringUtil.TruncateWhenZero(abs)) or (not addon.variables.isMidnight and abs))
			if showGlow then
				st.overAbsorbGlow:Show()
			else
				st.overAbsorbGlow:Hide()
			end
		end
	end
	local leftMode = hc.textLeft or "PERCENT"
	local rightMode = hc.textRight or "CURMAX"
	local leftDelimiter = getTextDelimiter(hc, defH)
	local rightDelimiter = getTextDelimiter(hc, defH)
	if st.healthTextLeft then st.healthTextLeft:SetText(formatText(leftMode, cur, maxv, hc.useShortNumbers ~= false, percentVal, leftDelimiter)) end
	if st.healthTextRight then st.healthTextRight:SetText(formatText(rightMode, cur, maxv, hc.useShortNumbers ~= false, percentVal, rightDelimiter)) end
end

local function updatePower(cfg, unit)
	cfg = cfg or (states[unit] and states[unit].cfg) or ensureDB(unit)
	local st = states[unit]
	if not st then return end
	local bar = st.power
	if not bar then return end
	local def = defaultsFor(unit) or {}
	local defP = def.power or {}
	local pcfg = cfg.power or {}
	if pcfg.enabled == false then
		bar:Hide()
		bar:SetValue(0)
		if st.powerTextLeft then st.powerTextLeft:SetText("") end
		if st.powerTextRight then st.powerTextRight:SetText("") end
		return
	end
	bar:Show()
	local powerEnum, powerToken = getMainPower(unit)
	powerEnum = powerEnum or 0
	local cur = UnitPower(unit, powerEnum)
	local maxv = UnitPowerMax(unit, powerEnum)
	if issecretvalue and issecretvalue(maxv) then
		bar:SetMinMaxValues(0, maxv or 1)
	else
		bar:SetMinMaxValues(0, maxv > 0 and maxv or 1)
	end
	bar:SetValue(cur or 0)
	local percentVal
	if addon.variables and addon.variables.isMidnight then
		percentVal = getPowerPercent(unit, powerEnum, cur, maxv)
	elseif not issecretvalue or (not issecretvalue(cur) and not issecretvalue(maxv)) then
		percentVal = getPowerPercent(unit, powerEnum, cur, maxv)
	end
	local cr, cg, cb, ca = getPowerColor(powerToken)
	bar:SetStatusBarColor(cr or 0.1, cg or 0.45, cb or 1, ca or 1)
	if bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(isPowerDesaturated(powerToken)) end
	if st.powerTextLeft then
		if (issecretvalue and not issecretvalue(maxv) and maxv == 0) or (not addon.variables.isMidnight and maxv == 0) then
			st.powerTextLeft:SetText("")
		else
			local leftMode = pcfg.textLeft or "PERCENT"
			local leftDelimiter = getTextDelimiter(pcfg, defP)
			st.powerTextLeft:SetText(formatText(leftMode, cur, maxv, pcfg.useShortNumbers ~= false, percentVal, leftDelimiter))
		end
	end
	if (issecretvalue and not issecretvalue(maxv) and maxv == 0) or (not addon.variables.isMidnight and maxv == 0) then
		st.powerTextRight:SetText("")
	else
		if st.powerTextRight then
			local rightMode = pcfg.textRight or "CURMAX"
			local rightDelimiter = getTextDelimiter(pcfg, defP)
			st.powerTextRight:SetText(formatText(rightMode, cur, maxv, pcfg.useShortNumbers ~= false, percentVal, rightDelimiter))
		end
	end
end

applyFont = function(fs, fontPath, size, outline)
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

local function setFrameLevelAbove(child, parent, offset)
	if not child or not parent then return end
	child:SetFrameStrata(parent:GetFrameStrata())
	child:SetFrameLevel((parent:GetFrameLevel() or 0) + (offset or 1))
end

local function syncTextFrameLevels(st)
	if not st then return end
	setFrameLevelAbove(st.healthTextLayer, st.health, 2)
	setFrameLevelAbove(st.powerTextLayer, st.power, 2)
	setFrameLevelAbove(st.statusTextLayer, st.status, 2)
	if st.restLoop and st.statusTextLayer then setFrameLevelAbove(st.restLoop, st.statusTextLayer, 3) end
	if st.castTextLayer then setFrameLevelAbove(st.castTextLayer, st.castBar, 2) end
end

local function hookTextFrameLevels(st)
	if not st then return end
	st._textLevelHooks = st._textLevelHooks or {}
	local function hookFrame(frame)
		if not frame or st._textLevelHooks[frame] then return end
		st._textLevelHooks[frame] = true
		if hooksecurefunc then
			hooksecurefunc(frame, "SetFrameLevel", function() syncTextFrameLevels(st) end)
			hooksecurefunc(frame, "SetFrameStrata", function() syncTextFrameLevels(st) end)
		end
	end
	hookFrame(st.frame)
	hookFrame(st.barGroup)
	hookFrame(st.health)
	hookFrame(st.power)
	hookFrame(st.status)
	syncTextFrameLevels(st)
end

local function updateUnitStatusIndicator(cfg, unit)
	cfg = cfg or (states[unit] and states[unit].cfg) or ensureDB(unit)
	local st = states[unit]
	if not st or not st.unitStatusText then return end
	if cfg.enabled == false then
		st.unitStatusText:SetText("")
		st.unitStatusText:Hide()
		return
	end
	local def = defaultsFor(unit) or {}
	local defStatus = def.status or {}
	local scfg = cfg.status or {}
	local usDef = defStatus.unitStatus or {}
	local usCfg = scfg.unitStatus or usDef or {}
	if usCfg.enabled ~= true then
		st.unitStatusText:SetText("")
		st.unitStatusText:Hide()
		return
	end
	if UnitExists and not UnitExists(unit) then
		st.unitStatusText:SetText("")
		st.unitStatusText:Hide()
		return
	end
	local tag
	if UnitIsConnected and UnitIsConnected(unit) == false then
		tag = PLAYER_OFFLINE or "Offline"
	elseif UnitIsAFK and UnitIsAFK(unit) then
		tag = DEFAULT_AFK_MESSAGE or "AFK"
	elseif UnitIsDND and UnitIsDND(unit) then
		tag = DEFAULT_DND_MESSAGE or "DND"
	end
	st.unitStatusText:SetText(tag or "")
	st.unitStatusText:SetShown(tag ~= nil)
end

local function updateStatus(cfg, unit)
	cfg = cfg or (states[unit] and states[unit].cfg) or ensureDB(unit)
	local st = states[unit]
	if not st or not st.status then return end
	local scfg = cfg.status or {}
	local def = defaultsFor(unit)
	local defStatus = def.status or {}
	local ciCfg = scfg.combatIndicator or defStatus.combatIndicator or {}
	local usDef = defStatus.unitStatus or {}
	local usCfg = scfg.unitStatus or usDef or {}
	local showName = scfg.enabled ~= false
	local showLevel = scfg.levelEnabled ~= false
	local showUnitStatus = usCfg.enabled == true
	local showStatus = showName or showLevel or showUnitStatus or (unit == UNIT.PLAYER and ciCfg.enabled ~= false)
	local statusHeight = showStatus and (cfg.statusHeight or def.statusHeight) or 0.001
	st.status:SetHeight(statusHeight)
	st.status:SetShown(showStatus)
	if st.nameText then
		applyFont(st.nameText, scfg.font, scfg.fontSize or 14, scfg.fontOutline)
		st.nameText:ClearAllPoints()
		st.nameText:SetPoint(scfg.nameAnchor or "LEFT", st.status, scfg.nameAnchor or "LEFT", (scfg.nameOffset and scfg.nameOffset.x) or 0, (scfg.nameOffset and scfg.nameOffset.y) or 0)
		st.nameText:SetShown(showName)
		applyNameCharLimit(st, scfg, defStatus)
	end
	if st.levelText then
		applyFont(st.levelText, scfg.font, scfg.fontSize or 14, scfg.fontOutline)
		st.levelText:ClearAllPoints()
		st.levelText:SetPoint(scfg.levelAnchor or "RIGHT", st.status, scfg.levelAnchor or "RIGHT", (scfg.levelOffset and scfg.levelOffset.x) or 0, (scfg.levelOffset and scfg.levelOffset.y) or 0)
		st.levelText:SetShown(showStatus and showLevel)
	end
	if st.unitStatusText then
		applyFont(st.unitStatusText, scfg.font, scfg.fontSize or 14, scfg.fontOutline)
		local off = usCfg.offset or usDef.offset or {}
		st.unitStatusText:ClearAllPoints()
		st.unitStatusText:SetPoint("CENTER", st.status, "CENTER", off.x or 0, off.y or 0)
		if st.unitStatusText.SetJustifyH then st.unitStatusText:SetJustifyH("CENTER") end
		if st.unitStatusText.SetWordWrap then st.unitStatusText:SetWordWrap(false) end
		if st.unitStatusText.SetMaxLines then st.unitStatusText:SetMaxLines(1) end
	end
	updateUnitStatusIndicator(cfg, unit)
end

local function updateCombatIndicator(cfg)
	local st = states[UNIT.PLAYER]
	if not st or not st.combatIcon or not st.status then return end
	local scfg = (cfg and cfg.status) or (defaultsFor(UNIT.PLAYER) and defaultsFor(UNIT.PLAYER).status) or {}
	local ccfg = scfg.combatIndicator or {}
	if ccfg.enabled == false then
		st.combatIcon:Hide()
		return
	end
	st.combatIcon:SetTexture("Interface\\Addons\\EnhanceQoLAura\\Icons\\CombatIndicator.tga")
	st.combatIcon:SetSize(ccfg.size or 18, ccfg.size or 18)
	st.combatIcon:ClearAllPoints()
	st.combatIcon:SetPoint("TOP", st.status, "TOP", (ccfg.offset and ccfg.offset.x) or -8, (ccfg.offset and ccfg.offset.y) or 0)
	if (UnitAffectingCombat and UnitAffectingCombat(UNIT.PLAYER)) or addon.EditModeLib:IsInEditMode() then
		st.combatIcon:Show()
	else
		st.combatIcon:Hide()
	end
end

local function ensureRestLoop(st)
	if not st or st.restLoop or not st.frame then return end
	local loop = CreateFrame("Frame", nil, st.frame)
	loop:Hide()
	local tex = loop:CreateTexture(nil, "OVERLAY")
	if tex.SetAtlas then
		tex:SetAtlas("UI-HUD-UnitFrame-Player-Rest-Flipbook", true)
	else
		tex:SetTexture("Interface\\PlayerFrame\\UI-Player-Status")
	end
	tex:SetPoint("CENTER")
	loop.restTexture = tex
	local anim = loop:CreateAnimationGroup()
	anim:SetLooping("REPEAT")
	anim:SetToFinalAlpha(true)
	local flip = anim:CreateAnimation("FlipBook")
	flip:SetTarget(tex)
	flip:SetDuration(1.5)
	flip:SetOrder(1)
	if flip.SetSmoothing then flip:SetSmoothing("NONE") end
	if flip.SetFlipBookRows then flip:SetFlipBookRows(7) end
	if flip.SetFlipBookColumns then flip:SetFlipBookColumns(6) end
	if flip.SetFlipBookFrames then flip:SetFlipBookFrames(42) end
	if flip.SetFlipBookFrameWidth then flip:SetFlipBookFrameWidth(0) end
	if flip.SetFlipBookFrameHeight then flip:SetFlipBookFrameHeight(0) end
	st.restLoop = loop
	st.restLoopAnim = anim
end

local function applyRestLoopLayout(cfg)
	local st = states[UNIT.PLAYER]
	if not st or not st.restLoop then return end
	local def = defaultsFor(UNIT.PLAYER)
	local rdef = def and def.resting or {}
	local rcfg = (cfg and cfg.resting) or rdef
	local size = max(10, rcfg.size or rdef.size or 20)
	local ox = (rcfg.offset and rcfg.offset.x) or (rdef.offset and rdef.offset.x) or 0
	local oy = (rcfg.offset and rcfg.offset.y) or (rdef.offset and rdef.offset.y) or 0
	local texSize = max(1, size * 1.5)
	st.restLoop:ClearAllPoints()
	st.restLoop:SetPoint("CENTER", st.barGroup or st.frame, "CENTER", ox, oy)
	st.restLoop:SetSize(size, size)
	if st.restLoop.restTexture then st.restLoop.restTexture:SetSize(texSize, texSize) end
	if st.statusTextLayer then setFrameLevelAbove(st.restLoop, st.statusTextLayer, 3) end
end

local function updateRestingIndicator(cfg)
	local st = states[UNIT.PLAYER]
	if not st or not st.restLoop then return end
	local def = defaultsFor(UNIT.PLAYER)
	local rdef = def and def.resting or {}
	local rcfg = (cfg and cfg.resting) or rdef
	if not cfg or cfg.enabled == false or rcfg.enabled == false then
		if st.restLoopAnim and st.restLoopAnim:IsPlaying() then st.restLoopAnim:Stop() end
		st.restLoop:Hide()
		return
	end
	applyRestLoopLayout(cfg)
	local resting = (IsResting and IsResting()) or (UnitIsResting and UnitIsResting(UNIT.PLAYER))
	if resting then
		st.restLoop:Show()
		if st.restLoopAnim and not st.restLoopAnim:IsPlaying() then st.restLoopAnim:Play() end
	else
		if st.restLoopAnim and st.restLoopAnim:IsPlaying() then st.restLoopAnim:Stop() end
		st.restLoop:Hide()
	end
end

local function getPortraitConfig(cfg, unit)
	local def = defaultsFor(unit)
	local pdef = def and def.portrait or {}
	local pcfg = (cfg and cfg.portrait) or {}
	local enabled = pcfg.enabled
	if enabled == nil then enabled = pdef.enabled end
	local size = pcfg.size or pdef.size or 32
	local side = (pcfg.side or pdef.side or "LEFT"):upper()
	if side ~= "RIGHT" then side = "LEFT" end
	local offx = (pcfg.offset and pcfg.offset.x) or (pdef.offset and pdef.offset.x) or 0
	local offy = (pcfg.offset and pcfg.offset.y) or (pdef.offset and pdef.offset.y) or 0
	local squareBackground = pcfg.squareBackground
	if squareBackground == nil then squareBackground = pdef.squareBackground end
	return enabled == true, max(1, size or 1), side, offx, offy, squareBackground == true
end

local function updatePortrait(cfg, unit)
	cfg = cfg or (states[unit] and states[unit].cfg) or ensureDB(unit)
	local st = states[unit]
	if not st or not st.portrait then return end
	local enabled, _, _, _, _, squareBackground = getPortraitConfig(cfg, unit)
	if not enabled or cfg.enabled == false then
		st.portrait:Hide()
		st.portrait:SetTexture(nil)
		if st.portraitBg then st.portraitBg:Hide() end
		return
	end
	if UnitExists and not UnitExists(unit) then
		st.portrait:Hide()
		st.portrait:SetTexture(nil)
		if st.portraitBg then st.portraitBg:Hide() end
		return
	end
	SetPortraitTexture(st.portrait, unit)
	st.portrait:Show()
	if st.portraitBg then
		if squareBackground == true then
			st.portraitBg:Show()
		else
			st.portraitBg:Hide()
		end
	end
end

local function layoutFrame(cfg, unit)
	local st = states[unit]
	if not st or not st.frame then return end
	local def = defaultsFor(unit)
	local scfg = cfg.status or {}
	local defStatus = def.status or {}
	local ciCfg = scfg.combatIndicator or defStatus.combatIndicator or {}
	local usDef = defStatus.unitStatus or {}
	local usCfg = scfg.unitStatus or usDef or {}
	local showName = scfg.enabled ~= false
	local showLevel = scfg.levelEnabled ~= false
	local showUnitStatus = usCfg.enabled == true
	local showStatus = showName or showLevel or showUnitStatus or (unit == UNIT.PLAYER and ciCfg.enabled ~= false)
	local pcfg = cfg.power or {}
	local powerEnabled = pcfg.enabled ~= false
	local width = max(MIN_WIDTH, cfg.width or def.width)
	local statusHeight = showStatus and (cfg.statusHeight or def.statusHeight) or 0
	local healthHeight = cfg.healthHeight or def.healthHeight
	local powerHeight = powerEnabled and (cfg.powerHeight or def.powerHeight) or 0
	local barGap = powerEnabled and (cfg.barGap or def.barGap or 0) or 0
	local borderOffset = 0
	if cfg.border and cfg.border.enabled then
		borderOffset = cfg.border.offset
		if borderOffset == nil then borderOffset = cfg.border.edgeSize or 1 end
		borderOffset = max(0, borderOffset or 0)
	end
	local portraitEnabled, portraitSize, portraitSide, portraitOffsetX, portraitOffsetY, portraitSquareBackground = getPortraitConfig(cfg, unit)
	local portraitWidth = portraitEnabled and portraitSize or 0
	local barOffsetLeft = (portraitEnabled and portraitSide == "LEFT") and portraitWidth or 0
	local barOffsetRight = (portraitEnabled and portraitSide == "RIGHT") and -portraitWidth or 0
	st.frame:SetWidth(width + borderOffset * 2 + portraitWidth)
	if cfg.strata then
		st.frame:SetFrameStrata(cfg.strata)
	else
		local pf = _G.PlayerFrame
		if pf and pf.GetFrameStrata then st.frame:SetFrameStrata(pf:GetFrameStrata()) end
	end
	if cfg.frameLevel then
		st.frame:SetFrameLevel(cfg.frameLevel)
	else
		local pf = _G.PlayerFrame
		if pf and pf.GetFrameLevel then st.frame:SetFrameLevel(pf:GetFrameLevel()) end
	end
	st.status:SetHeight(statusHeight)
	st.health:SetSize(width, healthHeight)
	st.power:SetSize(width, powerHeight)
	st.power:SetShown(powerEnabled)

	st.status:ClearAllPoints()
	if st.barGroup then st.barGroup:ClearAllPoints() end
	st.health:ClearAllPoints()
	st.power:ClearAllPoints()

	local anchor = cfg.anchor or def.anchor or defaults.player.anchor
	if isBossUnit(unit) then
		local container = ensureBossContainer() or UIParent
		if st.frame.SetParent then st.frame:SetParent(container) end
		if st.frame:GetNumPoints() == 0 then st.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0) end
	else
		local rel = (anchor and _G[anchor.relativeTo]) or UIParent
		st.frame:ClearAllPoints()
		st.frame:SetPoint(anchor.point or "CENTER", rel or UIParent, anchor.relativePoint or anchor.point or "CENTER", anchor.x or 0, anchor.y or 0)
	end

	local y = 0
	if statusHeight > 0 then
		st.status:SetPoint("TOPLEFT", st.frame, "TOPLEFT", barOffsetLeft, 0)
		st.status:SetPoint("TOPRIGHT", st.frame, "TOPRIGHT", barOffsetRight, 0)
		y = -statusHeight
	else
		st.status:SetPoint("TOPLEFT", st.frame, "TOPLEFT", barOffsetLeft, 0)
		st.status:SetPoint("TOPRIGHT", st.frame, "TOPRIGHT", barOffsetRight, 0)
	end
	-- Bars container sits below status; border applied here, not on status
	local barsHeight = healthHeight + powerHeight + barGap + borderOffset * 2
	if st.barGroup then
		st.barGroup:SetWidth(width + borderOffset * 2)
		st.barGroup:SetHeight(barsHeight)
		st.barGroup:SetPoint("TOPLEFT", st.frame, "TOPLEFT", barOffsetLeft, y)
		st.barGroup:SetPoint("TOPRIGHT", st.frame, "TOPRIGHT", barOffsetRight, y)
	end

	st.health:SetPoint("TOPLEFT", st.barGroup or st.frame, "TOPLEFT", borderOffset, -borderOffset)
	st.health:SetPoint("TOPRIGHT", st.barGroup or st.frame, "TOPRIGHT", -borderOffset, -borderOffset)
	st.power:SetPoint("TOPLEFT", st.health, "BOTTOMLEFT", 0, -barGap)
	st.power:SetPoint("TOPRIGHT", st.health, "BOTTOMRIGHT", 0, -barGap)

	if st.portrait then
		if portraitEnabled then
			st.portrait:SetSize(portraitSize, portraitSize)
			st.portrait:ClearAllPoints()
			if portraitSide == "RIGHT" then
				st.portrait:SetPoint("CENTER", st.barGroup or st.frame, "RIGHT", (portraitSize / 2) + portraitOffsetX, portraitOffsetY)
			else
				st.portrait:SetPoint("CENTER", st.barGroup or st.frame, "LEFT", -(portraitSize / 2) + portraitOffsetX, portraitOffsetY)
			end
			if st.portraitBg then
				if portraitSquareBackground == true then
					st.portraitBg:ClearAllPoints()
					st.portraitBg:SetAllPoints(st.portrait)
					st.portraitBg:Show()
				else
					st.portraitBg:Hide()
				end
			end
		else
			st.portrait:Hide()
			if st.portraitBg then st.portraitBg:Hide() end
		end
	end

	local totalHeight = statusHeight + barsHeight
	st.frame:SetHeight(totalHeight)
	if st.raidIcon then
		st.raidIcon:ClearAllPoints()
		st.raidIcon:SetPoint("TOP", st.barGroup or st.frame, "TOP", 0, -2)
	end

	layoutTexts(st.health, st.healthTextLeft, st.healthTextRight, cfg.health, width)
	layoutTexts(st.power, st.powerTextLeft, st.powerTextRight, cfg.power, width)
	if st.castBar and unit == UNIT.TARGET then applyCastLayout(cfg, unit) end

	-- Apply border only around the bar region wrapper
	if st.barGroup then setBackdrop(st.barGroup, cfg.border) end

	if unit == "target" and st.auraContainer then
		st.auraContainer:ClearAllPoints()
		local acfg = cfg.auraIcons or def.auraIcons or defaults.target.auraIcons or {}
		local ax = (acfg.offset and acfg.offset.x) or 0
		local ay = (acfg.offset and acfg.offset.y) or (acfg.anchor == "TOP" and 5 or -5)
		local anchor = acfg.anchor or "BOTTOM"
		if anchor == "TOP" then
			st.auraContainer:SetPoint("BOTTOMLEFT", st.barGroup, "TOPLEFT", ax, ay)
		else
			st.auraContainer:SetPoint("TOPLEFT", st.barGroup, "BOTTOMLEFT", ax, ay)
		end
		st.auraContainer:SetWidth(width + borderOffset * 2)

		if st.debuffContainer then
			st.debuffContainer:ClearAllPoints()
			local useSeparateDebuffs = acfg.separateDebuffAnchor == true
			local dax = (acfg.debuffOffset and acfg.debuffOffset.x) or ax
			local day = (acfg.debuffOffset and acfg.debuffOffset.y)
			local danchor = acfg.debuffAnchor or anchor
			if day == nil then day = (danchor == "TOP" and 5 or -5) end
			if useSeparateDebuffs then
				if danchor == "TOP" then
					st.debuffContainer:SetPoint("BOTTOMLEFT", st.barGroup, "TOPLEFT", dax, day)
				else
					st.debuffContainer:SetPoint("TOPLEFT", st.barGroup, "BOTTOMLEFT", dax, day)
				end
				st.debuffContainer:SetWidth(width + borderOffset * 2)
			else
				-- If not separating, keep the debuff container collapsed
				st.debuffContainer:SetPoint("TOPLEFT", st.auraContainer, "TOPLEFT", 0, 0)
				st.debuffContainer:SetWidth(0.001)
				st.debuffContainer:SetHeight(0.001)
				st.debuffContainer:Hide()
			end
		end
	end
	if unit == UNIT.PLAYER then applyClassResourceLayout(cfg) end
	syncTextFrameLevels(st)
end

local function ensureFrames(unit)
	local info = UNITS[unit]
	if not info then return end
	states[unit] = states[unit] or {}
	local st = states[unit]
	addon.variables.states = states
	if st.frame then return end
	local parent = UIParent
	if isBossUnit(unit) then parent = ensureBossContainer() or UIParent end
	st.frame = _G[info.frameName] or CreateFrame("Button", info.frameName, parent, "BackdropTemplate,SecureUnitButtonTemplate")
	_G.ClickCastFrames = _G.ClickCastFrames or {}
	_G.ClickCastFrames[st.frame] = true
	if st.frame.SetParent then st.frame:SetParent(parent) end
	st.frame:SetAttribute("unit", info.unit)
	st.frame:SetAttribute("type1", "target")
	st.frame:SetAttribute("type2", "togglemenu")
	st.frame:HookScript("OnEnter", function(self)
		local cfg = ensureDB(unit)
		if not (cfg and cfg.showTooltip) then return end
		if not GameTooltip or GameTooltip:IsForbidden() then return end
		if info and info.unit then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetUnit(info.unit)
			GameTooltip:Show()
		end
	end)
	st.frame:HookScript("OnLeave", function()
		if GameTooltip and not GameTooltip:IsForbidden() then GameTooltip:Hide() end
	end)
	st.frame:RegisterForClicks("AnyUp")
	st.frame:Hide()
	hideSettingsReset(st.frame)

	if info.dropdown then st.frame.menu = info.dropdown end
	st.frame:SetClampedToScreen(true)
	st.status = _G[info.statusName] or CreateFrame("Frame", info.statusName, st.frame)
	st.barGroup = st.barGroup or CreateFrame("Frame", nil, st.frame, "BackdropTemplate")
	st.health = _G[info.healthName] or CreateFrame("StatusBar", info.healthName, st.barGroup, "BackdropTemplate")
	if st.health.SetStatusBarDesaturated then st.health:SetStatusBarDesaturated(false) end
	st.power = _G[info.powerName] or CreateFrame("StatusBar", info.powerName, st.barGroup, "BackdropTemplate")
	local _, powerToken = getMainPower(unit)
	if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated(isPowerDesaturated(powerToken)) end
	if not st.portrait then
		st.portrait = st.frame:CreateTexture(nil, "ARTWORK")
		st.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		st.portrait:Hide()
	end
	if not st.portraitBg then
		st.portraitBg = st.frame:CreateTexture(nil, "BACKGROUND")
		st.portraitBg:SetColorTexture(0, 0, 0, 1)
		st.portraitBg:Hide()
	end

	local allowAbsorb = not (info and info.disableAbsorb)
	if allowAbsorb then
		st.absorb = st.absorb or CreateFrame("StatusBar", info.healthName .. "Absorb", st.health, "BackdropTemplate")
		if st.absorb.SetStatusBarDesaturated then st.absorb:SetStatusBarDesaturated(false) end
		st.overAbsorbGlow = st.overAbsorbGlow or st.health:CreateTexture(nil, "ARTWORK", "OverAbsorbGlowTemplate")
		if st.absorb then st.absorb.overAbsorbGlow = st.overAbsorbGlow end
		if not st.overAbsorbGlow then st.overAbsorbGlow = st.health:CreateTexture(nil, "ARTWORK") end
		if st.overAbsorbGlow then
			st.overAbsorbGlow:SetTexture(798066)
			st.overAbsorbGlow:SetBlendMode("ADD")
			st.overAbsorbGlow:SetAlpha(0.8)
			st.overAbsorbGlow:Hide()
		end
	else
		if st.absorb then st.absorb:Hide() end
		st.absorb = nil
		if st.overAbsorbGlow then st.overAbsorbGlow:Hide() end
	end
	if (unit == UNIT.TARGET or unit == UNIT.FOCUS or isBossUnit(unit)) and not st.castBar then
		st.castBar = CreateFrame("StatusBar", info.healthName .. "Cast", st.frame, "BackdropTemplate")
		st.castBar:SetStatusBarDesaturated(true)
		st.castTextLayer = CreateFrame("Frame", nil, st.castBar)
		st.castTextLayer:SetAllPoints(st.castBar)
		st.castName = st.castTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		st.castDuration = st.castTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		st.castIcon = st.castBar:CreateTexture(nil, "ARTWORK")
		st.castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		st.castBar:SetMinMaxValues(0, 1)
		st.castBar:SetValue(0)
		st.castBar:Hide()
	end

	st.healthTextLayer = st.healthTextLayer or CreateFrame("Frame", nil, st.health)
	st.healthTextLayer:SetAllPoints(st.health)
	st.powerTextLayer = st.powerTextLayer or CreateFrame("Frame", nil, st.power)
	st.powerTextLayer:SetAllPoints(st.power)
	st.statusTextLayer = st.statusTextLayer or CreateFrame("Frame", nil, st.status)
	st.statusTextLayer:SetAllPoints(st.status)

	st.healthTextLeft = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.healthTextRight = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.powerTextLeft = st.powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.powerTextRight = st.powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.nameText = st.statusTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.levelText = st.statusTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.unitStatusText = st.statusTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.raidIcon = st.statusTextLayer:CreateTexture(nil, "OVERLAY", nil, 7)
	st.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	st.raidIcon:SetSize(18, 18)
	st.raidIcon:SetPoint("TOP", st.frame, "TOP", 0, -2)
	st.raidIcon:Hide()
	if unit == UNIT.PLAYER then
		st.combatIcon = st.statusTextLayer:CreateTexture("EQOLUFPlayerCombatIcon", "OVERLAY")
		ensureRestLoop(st)
	end

	if unit == "target" then
		st.auraContainer = CreateFrame("Frame", nil, st.frame)
		st.debuffContainer = CreateFrame("Frame", nil, st.frame)
		st.auraButtons = {}
		st.debuffButtons = {}
	end

	st.frame:SetMovable(true)
	st.frame:EnableMouse(true)
	st.frame:RegisterForDrag("LeftButton")
	hookTextFrameLevels(st)
end

local function applyBars(cfg, unit)
	local st = states[unit]
	if not st or not st.health or not st.power then return end
	local info = UNITS[unit]
	local allowAbsorb = not (info and info.disableAbsorb)
	local hc = cfg.health or {}
	local pcfg = cfg.power or {}
	local powerEnabled = pcfg.enabled ~= false
	st.health:SetStatusBarTexture(resolveTexture(hc.texture))
	if st.health.SetStatusBarDesaturated then st.health:SetStatusBarDesaturated(false) end
	configureSpecialTexture(st.health, "HEALTH", hc.texture, hc)
	applyBarBackdrop(st.health, hc)
	if powerEnabled then
		st.power:SetStatusBarTexture(resolveTexture(pcfg.texture))
		if unit == UNIT.PLAYER then refreshMainPower(unit) end
		local _, powerToken = getMainPower(unit)
		if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated(isPowerDesaturated(powerToken)) end
		configureSpecialTexture(st.power, powerToken, pcfg.texture, pcfg)
		applyBarBackdrop(st.power, pcfg)
		st.power:Show()
	else
		st.power:Hide()
		if st.powerTextLeft then st.powerTextLeft:SetText("") end
		if st.powerTextRight then st.powerTextRight:SetText("") end
	end
	if allowAbsorb and st.absorb then
		local absorbTextureKey = hc.absorbTexture or hc.texture
		st.absorb:SetStatusBarTexture(resolveTexture(absorbTextureKey))
		if st.absorb.SetStatusBarDesaturated then st.absorb:SetStatusBarDesaturated(false) end
		configureSpecialTexture(st.absorb, "HEALTH", absorbTextureKey, hc)
		st.absorb:SetAllPoints(st.health)
		st.absorb:SetFrameLevel(st.health:GetFrameLevel() + 1)
		st.absorb:SetMinMaxValues(0, 1)
		st.absorb:SetValue(0)
		if st.overAbsorbGlow then
			st.overAbsorbGlow:ClearAllPoints()
			st.overAbsorbGlow:SetPoint("TOPLEFT", st.health, "TOPRIGHT", -7, 0)
			st.overAbsorbGlow:SetPoint("BOTTOMLEFT", st.health, "BOTTOMRIGHT", -7, 0)
		end
		if st.overAbsorbGlow then st.overAbsorbGlow:Hide() end
	elseif st.overAbsorbGlow then
		st.overAbsorbGlow:Hide()
	end
	if st.castBar and (unit == UNIT.TARGET or unit == UNIT.FOCUS or isBossUnit(unit)) then
		local defc = (defaultsFor(unit) and defaultsFor(unit).cast) or {}
		local ccfg = cfg.cast or defc
		st.castBar:SetStatusBarTexture(resolveCastTexture((ccfg.texture or defc.texture or "DEFAULT")))
		st.castBar:SetMinMaxValues(0, 1)
		st.castBar:SetValue(0)
		applyCastLayout(cfg, unit)
		local castFont = ccfg.font or defc.font or hc.font
		local castFontSize = ccfg.fontSize or defc.fontSize or hc.fontSize or 12
		local castOutline = hc.fontOutline or "OUTLINE"
		applyFont(st.castName, castFont, castFontSize, castOutline)
		applyFont(st.castDuration, castFont, castFontSize, castOutline)
	end

	applyFont(st.healthTextLeft, hc.font, hc.fontSize or 14)
	applyFont(st.healthTextRight, hc.font, hc.fontSize or 14)
	applyFont(st.powerTextLeft, pcfg.font, pcfg.fontSize or 14)
	applyFont(st.powerTextRight, pcfg.font, pcfg.fontSize or 14)
	syncTextFrameLevels(st)
end

local function updateNameAndLevel(cfg, unit)
	cfg = cfg or (states[unit] and states[unit].cfg) or ensureDB(unit)
	local st = states[unit]
	if not st then return end
	if st.nameText then
		local scfg = cfg.status or {}
		local class = select(2, UnitClass(unit))
		local nc
		if scfg.nameColorMode == "CUSTOM" then
			nc = scfg.nameColor or { 1, 1, 1, 1 }
		else
			nc = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
		end
		st.nameText:SetText(UnitName(unit) or "")
		st.nameText:SetTextColor(nc and (nc.r or nc[1]) or 1, nc and (nc.g or nc[2]) or 1, nc and (nc.b or nc[3]) or 1, nc and (nc.a or nc[4]) or 1)
	end
	if st.levelText then
		local scfg = cfg.status or {}
		local enabled = scfg.levelEnabled ~= false
		st.levelText:SetShown(enabled)
		if enabled then
			local lc
			if scfg.levelColorMode == "CUSTOM" then
				lc = scfg.levelColor or { 1, 0.85, 0, 1 }
			else
				local class = select(2, UnitClass(unit))
				lc = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
				if not lc then lc = { 1, 0.85, 0, 1 } end
			end
			local rawLevel = UnitLevel(unit) or 0
			local levelText = rawLevel > 0 and tostring(rawLevel) or "??"
			local classification = UnitClassification and UnitClassification(unit)
			if classification == "worldboss" then
				levelText = "??"
			elseif classification == "elite" then
				levelText = levelText .. "+"
			elseif classification == "rareelite" then
				levelText = levelText .. " R+"
			elseif classification == "rare" then
				levelText = levelText .. " R"
			elseif classification == "trivial" or classification == "minus" then
				levelText = levelText .. "-"
			end
			st.levelText:SetText(levelText)
			st.levelText:SetTextColor(lc[1] or 1, lc[2] or 0.85, lc[3] or 0, lc[4] or 1)
		end
	end
end

local function applyConfig(unit)
	local cfg = ensureDB(unit)
	states[unit] = states[unit] or {}
	local st = states[unit]
	st.cfg = cfg
	if not cfg.enabled then
		if st and st.frame then
			if st.barGroup then st.barGroup:Hide() end
			if st.status then st.status:Hide() end
			if st.portrait then st.portrait:Hide() end
		end
		applyVisibilityDriver(unit, false)
		if unit == UNIT.PLAYER then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.player, false) end
		if unit == UNIT.TARGET then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.target, false) end
		if unit == UNIT.TARGET_TARGET then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.targettarget, false) end
		if unit == UNIT.FOCUS then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.focus, false) end
		if unit == UNIT.PET then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.pet, false) end
		if unit == UNIT.PLAYER then restoreClassResourceFrames() end
		if unit == "target" then resetTargetAuras() end
		if unit == UNIT.PLAYER then updateRestingIndicator(cfg) end
		if not isBossUnit(unit) then applyVisibilityRules(unit) end
		return
	end
	ensureFrames(unit)
	st = states[unit]
	st.cfg = cfg
	applyVisibilityDriver(unit, cfg.enabled)
	if unit == UNIT.PLAYER then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.player, true) end
	if unit == UNIT.TARGET then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.target, true) end
	if unit == UNIT.TARGET_TARGET then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.targettarget, true) end
	if unit == UNIT.FOCUS then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.focus, true) end
	if unit == UNIT.PET then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.pet, true) end
	applyBars(cfg, unit)
	if not InCombatLockdown() then layoutFrame(cfg, unit) end
	updateStatus(cfg, unit)
	updateNameAndLevel(cfg, unit)
	updateHealth(cfg, unit)
	updatePower(cfg, unit)
	updatePortrait(cfg, unit)
	checkRaidTargetIcon(unit, st)
	if unit == UNIT.PLAYER then
		updateCombatIndicator(cfg)
		updateRestingIndicator(cfg)
	end
	-- if unit == "target" then hideBlizzardTargetFrame() end
	if st and st.frame then
		if st.barGroup then st.barGroup:Show() end
		if st.status then st.status:Show() end
	end
	if unit == UNIT.TARGET and st.castBar then
		if cfg.cast and cfg.cast.enabled ~= false and UnitExists(UNIT.TARGET) then
			setCastInfoFromUnit(UNIT.TARGET)
		else
			stopCast(UNIT.TARGET)
			st.castBar:Hide()
		end
	end
	if isBossUnit(unit) and st.castBar then
		if cfg.cast and cfg.cast.enabled ~= false and UnitExists(unit) then
			setCastInfoFromUnit(unit)
		else
			stopCast(unit)
			st.castBar:Hide()
		end
	end
	if unit == UNIT.TARGET and states[unit] and states[unit].auraContainer then updateTargetAuraIcons(1) end
	if not isBossUnit(unit) then applyVisibilityRules(unit) end
end

local function layoutBossFrames(cfg)
	if not bossContainer then return end
	if InCombatLockdown() then
		bossLayoutDirty = true
		return
	end
	bossLayoutDirty = false
	cfg = cfg or ensureDB("boss")
	anchorBossContainer(cfg)
	local def = defaultsFor("boss")
	local spacing = cfg.spacing
	if spacing == nil and def then spacing = def.spacing end
	if spacing == nil then spacing = 4 end
	local growth = (cfg.growth or (def and def.growth) or "DOWN"):upper()
	local last
	local shown = 0
	local maxWidth = 0
	local frameHeight = 0
	for i = 1, maxBossFrames do
		local unit = "boss" .. i
		local st = states[unit]
		if st and st.frame then
			st.frame:ClearAllPoints()
			if not last then
				st.frame:SetPoint("TOPLEFT", bossContainer, "TOPLEFT", 0, 0)
			else
				if growth == "UP" then
					st.frame:SetPoint("BOTTOMLEFT", last.frame, "TOPLEFT", 0, spacing)
				else
					st.frame:SetPoint("TOPLEFT", last.frame, "BOTTOMLEFT", 0, -spacing)
				end
			end
			last = st
			shown = shown + 1
			maxWidth = math.max(maxWidth, st.frame:GetWidth() or 0)
			frameHeight = st.frame:GetHeight() or frameHeight
		end
	end
	if shown > 0 then
		local totalHeight = frameHeight * shown + spacing * (shown - 1)
		bossContainer:SetHeight(totalHeight)
		bossContainer:SetWidth(maxWidth)
	end
end

local function hideBossFrames(forceHide)
	for i = 1, maxBossFrames do
		local st = states["boss" .. i]
		if st and st.frame then applyVisibilityDriver("boss" .. i, false) end
	end
	bossLayoutDirty = false
	if addon.EditModeLib and addon.EditModeLib:IsInEditMode() and ensureDB("boss").enabled and not forceHide then
		-- Keep container visible in edit mode for positioning
		if bossContainer then bossContainer:Show() end
		return
	end
	if InCombatLockdown() then
		bossHidePending = true
		bossShowPending = nil
		return
	end
	bossHidePending = nil
	bossShowPending = nil
	if bossContainer then
		if forceHide or not ensureDB("boss").enabled then
			bossContainer:Hide()
		else
			bossContainer:Show()
		end
	end
end

local function applyBossEditSample(idx, cfg)
	cfg = cfg or ensureDB("boss")
	local unit = "boss" .. idx
	local st = states[unit]
	if not st or not st.frame then return end
	local def = defaultsFor("boss")
	local defH = def.health or {}
	local defP = def.power or {}
	local hc = cfg.health or defH or {}
	local pcfg = cfg.power or defP or {}
	local cdef = cfg.cast or def.cast or {}

	local cur = UnitHealth("player") or 1
	local maxv = UnitHealthMax("player") or cur or 1
	st.health:SetMinMaxValues(0, maxv)
	st.health:SetValue(cur)
	local color = hc.color or (def.health and def.health.color) or { 0, 0.8, 0, 1 }
	st.health:SetStatusBarColor(color[1] or 0, color[2] or 0.8, color[3] or 0, color[4] or 1)
	local leftMode = hc.textLeft or "PERCENT"
	local rightMode = hc.textRight or "CURMAX"
	local leftDelimiter = getTextDelimiter(hc, defH)
	local rightDelimiter = getTextDelimiter(hc, defH)
	if st.healthTextLeft then st.healthTextLeft:SetText(formatText(leftMode, cur, maxv, hc.useShortNumbers ~= false, nil, leftDelimiter)) end
	if st.healthTextRight then st.healthTextRight:SetText(formatText(rightMode, cur, maxv, hc.useShortNumbers ~= false, nil, rightDelimiter)) end

	local powerEnabled = pcfg.enabled ~= false
	if st.power then
		if powerEnabled then
			local enumId, token = getMainPower("player")
			local pCur = UnitPower("player", enumId or 0) or 0
			local pMax = UnitPowerMax("player", enumId or 0) or 0
			st.power:SetMinMaxValues(0, pMax > 0 and pMax or 1)
			st.power:SetValue(pCur)
			local pr, pg, pb, pa = getPowerColor(token)
			st.power:SetStatusBarColor(pr or 0.1, pg or 0.45, pb or 1, pa or 1)
			if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated(isPowerDesaturated(token)) end
			local pLeftMode = pcfg.textLeft or "PERCENT"
			local pRightMode = pcfg.textRight or "CURMAX"
			local pLeftDelimiter = getTextDelimiter(pcfg, defP)
			local pRightDelimiter = getTextDelimiter(pcfg, defP)
			if st.powerTextLeft then st.powerTextLeft:SetText(formatText(pLeftMode, pCur, pMax, pcfg.useShortNumbers ~= false, nil, pLeftDelimiter)) end
			if st.powerTextRight then st.powerTextRight:SetText(formatText(pRightMode, pCur, pMax, pcfg.useShortNumbers ~= false, nil, pRightDelimiter)) end
			st.power:Show()
		else
			st.power:SetValue(0)
			if st.powerTextLeft then st.powerTextLeft:SetText("") end
			if st.powerTextRight then st.powerTextRight:SetText("") end
			st.power:Hide()
		end
	end
	if st.nameText then st.nameText:SetText((L["UFBossFrame"] or "Boss Frame") .. " " .. idx) end
	if st.levelText then
		st.levelText:SetText("??")
		st.levelText:Show()
	end
	if st.castBar and cdef.enabled ~= false then setSampleCast(unit) end
end

local function updateBossFrames(force)
	local cfg = ensureDB("boss")
	if not cfg.enabled then
		hideBossFrames(true)
		applyVisibilityRules("boss")
		return
	end
	if not bossContainer then ensureBossContainer() end
	DisableBossFrames()
	local inEdit = addon.EditModeLib and addon.EditModeLib:IsInEditMode()
	for i = 1, maxBossFrames do
		local unit = "boss" .. i
		if force or not states[unit] or not states[unit].frame or inEdit then applyConfig(unit) end
		local st = states[unit]
		if st then st.cfg = cfg end
		if st and st.frame then
			if inEdit then
				if not InCombatLockdown() then
					if UnregisterStateDriver then UnregisterStateDriver(st.frame, "visibility") end
					if st.frame.SetAttribute then st.frame:SetAttribute("state-visibility", nil) end
					if st.frame.SetAttribute then st.frame:SetAttribute("unit", "player") end
					st.frame:Show()
				else
					bossInitPending = true
				end
				if st.barGroup then st.barGroup:Show() end
				if st.status then st.status:Show() end
				applyBossEditSample(i, cfg)
			else
				local exists = UnitExists and UnitExists(unit)
				if not InCombatLockdown() then
					if st.frame.SetAttribute then st.frame:SetAttribute("unit", unit) end
					applyVisibilityDriver(unit, cfg.enabled)
				else
					if exists then
						bossShowPending = true
						bossHidePending = nil
					else
						bossHidePending = true
						bossShowPending = nil
					end
				end
				if exists then
					if st.barGroup then st.barGroup:Show() end
					if st.status then st.status:Show() end
					updateNameAndLevel(cfg, unit)
					updateHealth(cfg, unit)
					updatePower(cfg, unit)
					checkRaidTargetIcon(unit, st)
					if st.castBar and cfg.cast and cfg.cast.enabled ~= false then
						setCastInfoFromUnit(unit)
						if shouldShowSampleCast(unit) and (not st.castInfo or not UnitCastingInfo or (UnitCastingInfo and not UnitCastingInfo(unit))) then setSampleCast(unit) end
					elseif st.castBar then
						stopCast(unit)
						st.castBar:Hide()
					end
				else
					if st.barGroup then st.barGroup:Hide() end
					if st.status then st.status:Hide() end
					if st.castBar then
						stopCast(unit)
						st.castBar:Hide()
					end
				end
			end
		end
	end
	anchorBossContainer(cfg)
	layoutBossFrames(cfg)
	if not InCombatLockdown() then
		if bossContainer then bossContainer:Show() end
		bossShowPending = nil
		bossHidePending = nil
	else
		bossShowPending = true
		bossHidePending = nil
	end
	applyVisibilityRules("boss")
end

local unitEvents = {
	"UNIT_HEALTH",
	"UNIT_MAXHEALTH",
	"UNIT_ABSORB_AMOUNT_CHANGED",
	"UNIT_POWER_UPDATE",
	"UNIT_POWER_FREQUENT",
	"UNIT_MAXPOWER",
	"UNIT_DISPLAYPOWER",
	"UNIT_NAME_UPDATE",
	"UNIT_FLAGS",
	"UNIT_CONNECTION",
	"UNIT_AURA",
	"UNIT_TARGET",
	"UNIT_SPELLCAST_START",
	"UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_CHANNEL_UPDATE",
}
local unitEventsMap = {}
for _, evt in ipairs(unitEvents) do
	unitEventsMap[evt] = true
end
local portraitEvents = {
	"UNIT_PORTRAIT_UPDATE",
	"UNIT_MODEL_CHANGED",
	"UNIT_ENTERED_VEHICLE",
	"UNIT_EXITED_VEHICLE",
	"UNIT_EXITING_VEHICLE",
}
local portraitEventsMap = {}
for _, evt in ipairs(portraitEvents) do
	portraitEventsMap[evt] = true
end
local FREQUENT = { ENERGY = true, FOCUS = true, RAGE = true, RUNIC_POWER = true, LUNAR_POWER = true }

local generalEvents = {
	"PLAYER_ENTERING_WORLD",
	"PLAYER_LEVEL_UP",
	"PLAYER_DEAD",
	"PLAYER_ALIVE",
	"PLAYER_TARGET_CHANGED",
	"PLAYER_LOGIN",
	"PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED",
	"PLAYER_FLAGS_CHANGED",
	"PLAYER_UPDATE_RESTING",
	"UNIT_PET",
	"PLAYER_FOCUS_CHANGED",
	"INSTANCE_ENCOUNTER_ENGAGE_UNIT",
	"ENCOUNTER_START",
	"ENCOUNTER_END",
	"RAID_TARGET_UPDATE",
}

local eventFrame
local portraitEventsActive

local function anyUFEnabled()
	local p = ensureDB("player").enabled
	local t = ensureDB("target").enabled
	local tt = ensureDB(UNIT.TARGET_TARGET).enabled
	local pet = ensureDB(UNIT.PET).enabled
	local focus = ensureDB(UNIT.FOCUS).enabled
	local boss = ensureDB("boss").enabled
	return p or t or tt or pet or focus or boss
end

local function portraitEnabledFor(unit)
	local cfg = ensureDB(unit)
	if not cfg or cfg.enabled == false then return false end
	local def = defaultsFor(unit)
	local pdef = def and def.portrait or {}
	local pcfg = cfg.portrait or {}
	local enabled = pcfg.enabled
	if enabled == nil then enabled = pdef.enabled end
	return enabled == true
end

local function anyPortraitEnabled()
	if portraitEnabledFor(UNIT.PLAYER) then return true end
	if portraitEnabledFor(UNIT.TARGET) then return true end
	if portraitEnabledFor(UNIT.TARGET_TARGET) then return true end
	if portraitEnabledFor(UNIT.FOCUS) then return true end
	if portraitEnabledFor(UNIT.PET) then return true end
	if portraitEnabledFor("boss") then return true end
	return false
end

local function updatePortraitEventRegistration()
	if not eventFrame then return end
	local shouldRegister = anyPortraitEnabled()
	if shouldRegister and not portraitEventsActive then
		for _, evt in ipairs(portraitEvents) do
			eventFrame:RegisterEvent(evt)
		end
		portraitEventsActive = true
	elseif not shouldRegister and portraitEventsActive then
		for _, evt in ipairs(portraitEvents) do
			eventFrame:UnregisterEvent(evt)
		end
		portraitEventsActive = false
	end
end

local function ensureBossFramesReady(cfg)
	cfg = cfg or ensureDB("boss")
	if not cfg.enabled then return end
	if InCombatLockdown() then
		bossInitPending = true
		return
	end
	for i = 1, maxBossFrames do
		local unit = "boss" .. i
		applyConfig(unit)
		if addon.EditModeLib and addon.EditModeLib:IsInEditMode() then
			local st = states[unit]
			if st and st.frame then
				if UnregisterStateDriver then UnregisterStateDriver(st.frame, "visibility") end
				st.frame:SetAttribute("state-visibility", nil)
				st.frame:Show()
			end
		else
			applyVisibilityDriver(unit, cfg.enabled)
		end
	end
	if bossContainer then bossContainer:Show() end
	bossInitPending = nil
end

local function isBossFrameSettingEnabled()
	if not maxBossFrames or maxBossFrames <= 0 then return false end
	local cfg = ensureDB("boss")
	return cfg and cfg.enabled == true
end

local allowedEventUnit = {
	["target"] = true,
	["player"] = true,
	["targettarget"] = true,
	["focus"] = true,
	["pet"] = true,
}
for i = 1, maxBossFrames do
	allowedEventUnit["boss" .. i] = true
end

local function stopToTTicker()
	if totTicker and totTicker.Cancel then totTicker:Cancel() end
	totTicker = nil
end

local function ensureToTTicker()
	if totTicker or not NewTicker then return end
	totTicker = NewTicker(0.2, function()
		local st = states[UNIT.TARGET_TARGET]
		local cfg = st and st.cfg
		if not cfg or not cfg.enabled then return end
		local pcfg = cfg.power or {}
		local powerEnabled = pcfg.enabled ~= false
		if not UnitExists(UNIT.TARGET_TARGET) or not st.frame or not st.frame:IsShown() then return end
		if powerEnabled then
			local _, powerToken = UnitPowerType(UNIT.TARGET_TARGET)
			if st.power and powerToken and powerToken ~= st._lastPowerToken then
				if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated(isPowerDesaturated(powerToken)) end
				configureSpecialTexture(st.power, powerToken, (cfg.power or {}).texture, cfg.power)
				st._lastPowerToken = powerToken
			end
		else
			if st.power then st.power:Hide() end
		end
		updateHealth(cfg, UNIT.TARGET_TARGET)
		updatePower(cfg, UNIT.TARGET_TARGET)
	end)
end

local function updateTargetTargetFrame(cfg, forceApply)
	cfg = cfg or ensureDB(UNIT.TARGET_TARGET)
	local st = states[UNIT.TARGET_TARGET]
	if not cfg.enabled then
		stopToTTicker()
		if st then
			if st.barGroup then st.barGroup:Hide() end
			if st.status then st.status:Hide() end
		end
		updatePortrait(cfg, UNIT.TARGET_TARGET)
		applyVisibilityRules(UNIT.TARGET_TARGET)
		return
	end
	if forceApply or not st or not st.frame then
		applyConfig(UNIT.TARGET_TARGET)
		st = states[UNIT.TARGET_TARGET]
	end
	if st then st.cfg = st.cfg or cfg end
	local lHealth = UnitHealth("target")
	if UnitExists("target") and UnitExists(UNIT.TARGET_TARGET) and (issecretvalue and issecretvalue(lHealth) or lHealth > 0) then
		if st then
			if st.barGroup then st.barGroup:Show() end
			if st.status then st.status:Show() end
			local pcfg = cfg.power or {}
			local powerEnabled = pcfg.enabled ~= false
			updateNameAndLevel(cfg, UNIT.TARGET_TARGET)
			updateHealth(cfg, UNIT.TARGET_TARGET)
			if st.power and powerEnabled then
				local _, powerToken = getMainPower(UNIT.TARGET_TARGET)
				if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated(isPowerDesaturated(powerToken)) end
				configureSpecialTexture(st.power, powerToken, (cfg.power or {}).texture, cfg.power)
				st._lastPowerToken = powerToken
			elseif st.power then
				st.power:Hide()
			end
			updatePower(cfg, UNIT.TARGET_TARGET)
			checkRaidTargetIcon(UNIT.TARGET_TARGET, st)
		end
	else
		if st then
			if st.barGroup then st.barGroup:Hide() end
			if st.status then st.status:Hide() end
		end
	end
	checkRaidTargetIcon(UNIT.TARGET_TARGET, st)
	updateUnitStatusIndicator(cfg, UNIT.TARGET_TARGET)
	updatePortrait(cfg, UNIT.TARGET_TARGET)
	ensureToTTicker()
	applyVisibilityRules(UNIT.TARGET_TARGET)
end

local function updateFocusFrame(cfg, forceApply)
	cfg = cfg or ensureDB(UNIT.FOCUS)
	local st = states[UNIT.FOCUS]
	if not cfg.enabled then
		if applyFrameRuleOverride then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.focus, false) end
		if st then
			if st.barGroup then st.barGroup:Hide() end
			if st.status then st.status:Hide() end
		end
		updatePortrait(cfg, UNIT.FOCUS)
		applyVisibilityRules(UNIT.FOCUS)
		return
	end
	if applyFrameRuleOverride then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.focus, true) end
	if forceApply or not st or not st.frame then
		applyConfig(UNIT.FOCUS)
		st = states[UNIT.FOCUS]
	end
	if st then st.cfg = st.cfg or cfg end
	if UnitExists(UNIT.FOCUS) then
		if st then
			if st.barGroup then st.barGroup:Show() end
			if st.status then st.status:Show() end
			local pcfg = cfg.power or {}
			local powerEnabled = pcfg.enabled ~= false
			updateNameAndLevel(cfg, UNIT.FOCUS)
			updateHealth(cfg, UNIT.FOCUS)
			if st.power and powerEnabled then
				local _, powerToken = getMainPower(UNIT.FOCUS)
				if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated(isPowerDesaturated(powerToken)) end
				configureSpecialTexture(st.power, powerToken, (cfg.power or {}).texture, cfg.power)
				st._lastPowerToken = powerToken
			elseif st.power then
				st.power:Hide()
			end
			updatePower(cfg, UNIT.FOCUS)
			if st.castBar then setCastInfoFromUnit(UNIT.FOCUS) end
			checkRaidTargetIcon(UNIT.FOCUS, st)
		end
	else
		if st then
			if st.barGroup then st.barGroup:Hide() end
			if st.status then st.status:Hide() end
			if st.castBar then stopCast(UNIT.FOCUS) end
		end
	end
	checkRaidTargetIcon(UNIT.FOCUS, st)
	updateUnitStatusIndicator(cfg, UNIT.FOCUS)
	updatePortrait(cfg, UNIT.FOCUS)
	applyVisibilityRules(UNIT.FOCUS)
end

local function getCfg(unit)
	local st = states[unit]
	if st and st.cfg then return st.cfg end
	return ensureDB(unit)
end

local function onEvent(self, event, unit, arg1)
	if (unitEventsMap[event] or portraitEventsMap[event]) and unit and not allowedEventUnit[unit] then return end
	if event == "PLAYER_ENTERING_WORLD" then
		local playerCfg = getCfg(UNIT.PLAYER)
		local targetCfg = getCfg(UNIT.TARGET)
		local totCfg = getCfg(UNIT.TARGET_TARGET)
		local petCfg = getCfg(UNIT.PET)
		local focusCfg = getCfg(UNIT.FOCUS)
		local bossCfg = getCfg("boss")
		refreshMainPower(UNIT.PLAYER)
		applyConfig("player")
		applyConfig("target")
		updateTargetTargetFrame(totCfg, true)
		if focusCfg.enabled then updateFocusFrame(focusCfg, true) end
		if petCfg.enabled then applyConfig(UNIT.PET) end
		updateCombatIndicator(playerCfg)
		updateRestingIndicator(playerCfg)
		updateUnitStatusIndicator(playerCfg, UNIT.PLAYER)
		updateUnitStatusIndicator(targetCfg, UNIT.TARGET)
		updateUnitStatusIndicator(totCfg, UNIT.TARGET_TARGET)
		updateUnitStatusIndicator(focusCfg, UNIT.FOCUS)
		updateUnitStatusIndicator(petCfg, UNIT.PET)
		updateAllRaidTargetIcons()
		if bossCfg.enabled then
			updateBossFrames(true)
		else
			hideBossFrames()
		end
	elseif event == "PLAYER_DEAD" then
		local playerCfg = getCfg(UNIT.PLAYER)
		if states.player and states.player.health then states.player.health:SetValue(0) end
		updateHealth(playerCfg, UNIT.PLAYER)
	elseif event == "PLAYER_ALIVE" then
		local playerCfg = getCfg(UNIT.PLAYER)
		refreshMainPower(UNIT.PLAYER)
		updateHealth(playerCfg, UNIT.PLAYER)
		updatePower(playerCfg, UNIT.PLAYER)
		updateCombatIndicator(playerCfg)
		updateRestingIndicator(playerCfg)
		updateUnitStatusIndicator(playerCfg, UNIT.PLAYER)
	elseif event == "PLAYER_FLAGS_CHANGED" then
		if unit and allowedEventUnit[unit] then
			updateUnitStatusIndicator(getCfg(unit), unit)
		else
			updateUnitStatusIndicator(getCfg(UNIT.PLAYER), UNIT.PLAYER)
		end
		if allowedEventUnit[UNIT.TARGET_TARGET] then updateUnitStatusIndicator(getCfg(UNIT.TARGET_TARGET), UNIT.TARGET_TARGET) end
	elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
		local playerCfg = getCfg(UNIT.PLAYER)
		updateCombatIndicator(playerCfg)
		if event == "PLAYER_REGEN_ENABLED" then
			if bossLayoutDirty then layoutBossFrames() end
			if bossHidePending then hideBossFrames(true) end
			if bossShowPending or bossInitPending then updateBossFrames(true) end
			bossLayoutDirty, bossHidePending, bossShowPending, bossInitPending = nil, nil, nil, nil
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		local targetCfg = getCfg(UNIT.TARGET)
		local totCfg = getCfg(UNIT.TARGET_TARGET)
		local focusCfg = getCfg(UNIT.FOCUS)
		local unitToken = UNIT.TARGET
		local st = states[unitToken]
		if not st or not st.frame then
			resetTargetAuras()
			updateTargetAuraIcons()
			if totCfg.enabled then updateTargetTargetFrame(totCfg) end
			if focusCfg.enabled then updateFocusFrame(focusCfg) end
			return
		end
		if UnitExists(unitToken) then
			refreshMainPower(unitToken)
			fullScanTargetAuras()
			local pcfg = targetCfg.power or {}
			local powerEnabled = pcfg.enabled ~= false
			updateNameAndLevel(targetCfg, unitToken)
			updateHealth(targetCfg, unitToken)
			if st.power and powerEnabled then
				local _, powerToken = getMainPower(unitToken)
				configureSpecialTexture(st.power, powerToken, (targetCfg.power or {}).texture, targetCfg.power)
			elseif st.power then
				st.power:Hide()
			end
			updatePower(targetCfg, unitToken)
			st.barGroup:Show()
			st.status:Show()
			setCastInfoFromUnit(unitToken)
		else
			resetTargetAuras()
			updateTargetAuraIcons()
			st.barGroup:Hide()
			st.status:Hide()
			stopCast(unitToken)
		end
		checkRaidTargetIcon(unitToken, st)
		updatePortrait(targetCfg, unitToken)
		if totCfg.enabled then updateTargetTargetFrame(totCfg) end
		if focusCfg.enabled then updateFocusFrame(focusCfg) end
		updateUnitStatusIndicator(targetCfg, UNIT.TARGET)
		updateUnitStatusIndicator(totCfg, UNIT.TARGET_TARGET)
	elseif event == "UNIT_AURA" and unit == "target" then
		local targetCfg = getCfg(UNIT.TARGET)
		local eventInfo = arg1
		if not UnitExists("target") then
			resetTargetAuras()
			updateTargetAuraIcons()
			return
		end
		if not eventInfo or eventInfo.isFullUpdate then
			fullScanTargetAuras()
			return
		end
		local cfg = targetCfg
		local ac = cfg.auraIcons or defaults.target.auraIcons or { size = 24, padding = 2, max = 16, showCooldown = true }
		ac.size = ac.size or 24
		ac.padding = ac.padding or 0
		ac.max = ac.max or 16
		if ac.max < 1 then ac.max = 1 end
		local hidePermanent = ac.hidePermanentAuras == true or ac.hidePermanent == true
		local st = states.target
		if not st or not st.auraContainer then return end
		local width = (st.auraContainer and st.auraContainer:GetWidth()) or (st.barGroup and st.barGroup:GetWidth()) or (st.frame and st.frame:GetWidth()) or 0
		local perRow = math.max(1, math.floor((width + ac.padding) / (ac.size + ac.padding)))
		local firstChanged
		if eventInfo.addedAuras then
			for _, aura in ipairs(eventInfo.addedAuras) do
				if aura and hidePermanent and isPermanentAura(aura, unit) then
					if targetAuras[aura.auraInstanceID] then
						targetAuras[aura.auraInstanceID] = nil
						local idx = removeTargetAuraFromOrder(aura.auraInstanceID)
						if idx and idx <= (ac.max + 1) then
							if not firstChanged or idx < firstChanged then firstChanged = idx end
						end
					end
				elseif aura and not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, aura.auraInstanceID, "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY") then
					cacheTargetAura(aura)
					local idx = addTargetAuraToOrder(aura.auraInstanceID)
					if idx and idx <= ac.max then
						if not firstChanged or idx < firstChanged then firstChanged = idx end
					end
				elseif aura and not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, aura.auraInstanceID, "HELPFUL|CANCELABLE") then
					cacheTargetAura(aura)
					local idx = addTargetAuraToOrder(aura.auraInstanceID)
					if idx and idx <= ac.max then
						if not firstChanged or idx < firstChanged then firstChanged = idx end
					end
				end
			end
		end
		if eventInfo.updatedAuraInstanceIDs and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
			for _, inst in ipairs(eventInfo.updatedAuraInstanceIDs) do
				if targetAuras[inst] then
					local data = C_UnitAuras.GetAuraDataByAuraInstanceID("target", inst)
					if data then cacheTargetAura(data) end
				end
				local idx = targetAuraIndexById[inst]
				if idx and idx <= ac.max then
					if not firstChanged or idx < firstChanged then firstChanged = idx end
				end
			end
		end
		if eventInfo.removedAuraInstanceIDs then
			for _, inst in ipairs(eventInfo.removedAuraInstanceIDs) do
				targetAuras[inst] = nil
				local idx = removeTargetAuraFromOrder(inst)
				if idx and idx <= (ac.max + 1) then -- +1 to relayout if we pulled a hidden aura into view
					if not firstChanged or idx < firstChanged then firstChanged = idx end
				end
			end
		end
		if firstChanged then updateTargetAuraIcons(firstChanged) end
	elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
		if unit == UNIT.PLAYER then updateHealth(getCfg(UNIT.PLAYER), UNIT.PLAYER) end
		if unit == UNIT.TARGET then updateHealth(getCfg(UNIT.TARGET), UNIT.TARGET) end
		if unit == UNIT.PET then updateHealth(getCfg(UNIT.PET), UNIT.PET) end
		if unit == UNIT.FOCUS then updateHealth(getCfg(UNIT.FOCUS), UNIT.FOCUS) end
		if isBossUnit(unit) then
			local bossCfg = getCfg(unit)
			if bossCfg.enabled then updateHealth(bossCfg, unit) end
		end
	elseif event == "UNIT_MAXPOWER" then
		if unit == UNIT.PLAYER then updatePower(getCfg(UNIT.PLAYER), UNIT.PLAYER) end
		if unit == UNIT.TARGET then updatePower(getCfg(UNIT.TARGET), UNIT.TARGET) end
		if unit == UNIT.PET then updatePower(getCfg(UNIT.PET), UNIT.PET) end
		if unit == UNIT.FOCUS then updatePower(getCfg(UNIT.FOCUS), UNIT.FOCUS) end
		if isBossUnit(unit) then
			local bossCfg = getCfg(unit)
			if bossCfg.enabled then updatePower(bossCfg, unit) end
		end
	elseif event == "UNIT_DISPLAYPOWER" then
		if unit == UNIT.PLAYER then
			local playerCfg = getCfg(UNIT.PLAYER)
			refreshMainPower(unit)
			local st = states[unit]
			local pcfg = playerCfg.power or {}
			if st and st.power and pcfg.enabled ~= false then
				local _, powerToken = getMainPower(unit)
				configureSpecialTexture(st.power, powerToken, (playerCfg.power or {}).texture, playerCfg.power)
			elseif st and st.power then
				st.power:Hide()
			end
			updatePower(playerCfg, UNIT.PLAYER)
		elseif unit == UNIT.TARGET then
			local targetCfg = getCfg(UNIT.TARGET)
			local st = states[unit]
			local pcfg = targetCfg.power or {}
			if st and st.power and pcfg.enabled ~= false then
				local _, powerToken = getMainPower(unit)
				configureSpecialTexture(st.power, powerToken, (targetCfg.power or {}).texture, targetCfg.power)
			elseif st and st.power then
				st.power:Hide()
			end
			updatePower(targetCfg, UNIT.TARGET)
		elseif unit == UNIT.FOCUS then
			local focusCfg = getCfg(UNIT.FOCUS)
			local st = states[unit]
			local pcfg = focusCfg.power or {}
			if st and st.power and pcfg.enabled ~= false then
				local _, powerToken = getMainPower(unit)
				configureSpecialTexture(st.power, powerToken, (focusCfg.power or {}).texture, focusCfg.power)
			elseif st and st.power then
				st.power:Hide()
			end
			updatePower(focusCfg, UNIT.FOCUS)
		elseif unit == UNIT.PET then
			local petCfg = getCfg(UNIT.PET)
			local st = states[unit]
			local pcfg = petCfg.power or {}
			if st and st.power and pcfg.enabled ~= false then
				local _, powerToken = getMainPower(unit)
				configureSpecialTexture(st.power, powerToken, (petCfg.power or {}).texture, petCfg.power)
			elseif st and st.power then
				st.power:Hide()
			end
			updatePower(petCfg, UNIT.PET)
		elseif isBossUnit(unit) then
			local bossCfg = getCfg(unit)
			if bossCfg.enabled then
				local st = states[unit]
				local pcfg = bossCfg.power or {}
				if st and st.power and pcfg.enabled ~= false then
					local _, powerToken = getMainPower(unit)
					configureSpecialTexture(st.power, powerToken, (bossCfg.power or {}).texture, bossCfg.power)
				elseif st and st.power then
					st.power:Hide()
				end
				updatePower(bossCfg, unit)
			end
		end
	elseif event == "UNIT_POWER_UPDATE" and not FREQUENT[arg1] then
		if unit == UNIT.PLAYER then updatePower(getCfg(UNIT.PLAYER), UNIT.PLAYER) end
		if unit == UNIT.TARGET then updatePower(getCfg(UNIT.TARGET), UNIT.TARGET) end
		if unit == UNIT.PET then updatePower(getCfg(UNIT.PET), UNIT.PET) end
		if unit == UNIT.FOCUS then updatePower(getCfg(UNIT.FOCUS), UNIT.FOCUS) end
		if isBossUnit(unit) then
			local bossCfg = getCfg(unit)
			if bossCfg.enabled then updatePower(bossCfg, unit) end
		end
	elseif event == "UNIT_POWER_FREQUENT" and FREQUENT[arg1] then
		if unit == UNIT.PLAYER then updatePower(getCfg(UNIT.PLAYER), UNIT.PLAYER) end
		if unit == UNIT.TARGET then updatePower(getCfg(UNIT.TARGET), UNIT.TARGET) end
		if unit == UNIT.PET then updatePower(getCfg(UNIT.PET), UNIT.PET) end
		if unit == UNIT.FOCUS then updatePower(getCfg(UNIT.FOCUS), UNIT.FOCUS) end
		if isBossUnit(unit) then
			local bossCfg = getCfg(unit)
			if bossCfg.enabled then updatePower(bossCfg, unit) end
		end
	elseif event == "UNIT_NAME_UPDATE" or event == "PLAYER_LEVEL_UP" then
		if unit == UNIT.PLAYER or event == "PLAYER_LEVEL_UP" then updateNameAndLevel(getCfg(UNIT.PLAYER), UNIT.PLAYER) end
		if unit == UNIT.TARGET then updateNameAndLevel(getCfg(UNIT.TARGET), UNIT.TARGET) end
		if unit == UNIT.FOCUS then updateNameAndLevel(getCfg(UNIT.FOCUS), UNIT.FOCUS) end
		if unit == UNIT.PET then updateNameAndLevel(getCfg(UNIT.PET), UNIT.PET) end
		if isBossUnit(unit) then
			local bossCfg = getCfg(unit)
			if bossCfg.enabled then updateNameAndLevel(bossCfg, unit) end
		end
	elseif event == "UNIT_FLAGS" then
		updateUnitStatusIndicator(getCfg(unit), unit)
		if allowedEventUnit[UNIT.TARGET_TARGET] then updateUnitStatusIndicator(getCfg(UNIT.TARGET_TARGET), UNIT.TARGET_TARGET) end
	elseif event == "UNIT_CONNECTION" then
		updateUnitStatusIndicator(getCfg(unit), unit)
		if allowedEventUnit[UNIT.TARGET_TARGET] then updateUnitStatusIndicator(getCfg(UNIT.TARGET_TARGET), UNIT.TARGET_TARGET) end
		if unit == UNIT.PLAYER then updatePortrait(getCfg(UNIT.PLAYER), UNIT.PLAYER) end
		if unit == UNIT.TARGET then updatePortrait(getCfg(UNIT.TARGET), UNIT.TARGET) end
		if unit == UNIT.TARGET_TARGET then updatePortrait(getCfg(UNIT.TARGET_TARGET), UNIT.TARGET_TARGET) end
		if unit == UNIT.FOCUS then updatePortrait(getCfg(UNIT.FOCUS), UNIT.FOCUS) end
		if unit == UNIT.PET then updatePortrait(getCfg(UNIT.PET), UNIT.PET) end
		if isBossUnit(unit) then
			local bossCfg = getCfg(unit)
			if bossCfg.enabled then updatePortrait(bossCfg, unit) end
		end
	elseif portraitEventsMap[event] then
		if unit == UNIT.PLAYER then updatePortrait(getCfg(UNIT.PLAYER), UNIT.PLAYER) end
		if unit == UNIT.TARGET then updatePortrait(getCfg(UNIT.TARGET), UNIT.TARGET) end
		if unit == UNIT.TARGET_TARGET then updatePortrait(getCfg(UNIT.TARGET_TARGET), UNIT.TARGET_TARGET) end
		if unit == UNIT.FOCUS then updatePortrait(getCfg(UNIT.FOCUS), UNIT.FOCUS) end
		if unit == UNIT.PET then updatePortrait(getCfg(UNIT.PET), UNIT.PET) end
		if isBossUnit(unit) then
			local bossCfg = getCfg(unit)
			if bossCfg.enabled then updatePortrait(bossCfg, unit) end
		end
	elseif event == "UNIT_TARGET" and unit == UNIT.TARGET then
		local totCfg = getCfg(UNIT.TARGET_TARGET)
		if totCfg.enabled then updateTargetTargetFrame(totCfg) end
	elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
		if unit == UNIT.TARGET then setCastInfoFromUnit(UNIT.TARGET) end
		if unit == UNIT.FOCUS then setCastInfoFromUnit(UNIT.FOCUS) end
		if isBossUnit(unit) then setCastInfoFromUnit(unit) end
	elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if unit == UNIT.TARGET then
			stopCast(UNIT.TARGET)
			if shouldShowSampleCast(unit) then setSampleCast(unit) end
		end
		if unit == UNIT.FOCUS then
			stopCast(UNIT.FOCUS)
			if shouldShowSampleCast(unit) then setSampleCast(unit) end
		end
		if isBossUnit(unit) then stopCast(unit) end
	elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
		updateBossFrames(true)
	elseif event == "ENCOUNTER_START" then
		updateBossFrames(true)
	elseif event == "ENCOUNTER_END" then
		hideBossFrames()
	elseif event == "UNIT_PET" and unit == "player" then
		local petCfg = getCfg(UNIT.PET)
		if petCfg.enabled then
			applyConfig(UNIT.PET)
			updateNameAndLevel(petCfg, UNIT.PET)
			updateHealth(petCfg, UNIT.PET)
			updatePower(petCfg, UNIT.PET)
		end
	elseif event == "PLAYER_FOCUS_CHANGED" then
		local focusCfg = getCfg(UNIT.FOCUS)
		if focusCfg.enabled then
			updateFocusFrame(focusCfg, true)
			checkRaidTargetIcon(UNIT.FOCUS, states[UNIT.FOCUS])
		end
		updateUnitStatusIndicator(focusCfg, UNIT.FOCUS)
	elseif event == "PLAYER_UPDATE_RESTING" then
		updateRestingIndicator(getCfg(UNIT.PLAYER))
	elseif event == "RAID_TARGET_UPDATE" then
		updateAllRaidTargetIcons()
	end
end

local function ensureEventHandling()
	if not anyUFEnabled() then
		hideBossFrames()
		if eventFrame and eventFrame.UnregisterAllEvents then eventFrame:UnregisterAllEvents() end
		if eventFrame then eventFrame:SetScript("OnEvent", nil) end
		eventFrame = nil
		portraitEventsActive = nil
		return
	end
	if not eventFrame then
		eventFrame = CreateFrame("Frame")
		for _, evt in ipairs(unitEvents) do
			eventFrame:RegisterEvent(evt)
		end
		for _, evt in ipairs(generalEvents) do
			eventFrame:RegisterEvent(evt)
		end
		eventFrame:SetScript("OnEvent", onEvent)
		if not editModeHooked then
			editModeHooked = true

			addon.EditModeLib:RegisterCallback("enter", function()
				updateCombatIndicator(states[UNIT.PLAYER] and states[UNIT.PLAYER].cfg or ensureDB(UNIT.PLAYER))
				ensureBossFramesReady(ensureDB("boss"))
				updateBossFrames(true)
				updateAllRaidTargetIcons()
				applyVisibilityRulesAll()
			end)

			addon.EditModeLib:RegisterCallback("exit", function()
				updateCombatIndicator(states[UNIT.PLAYER] and states[UNIT.PLAYER].cfg or ensureDB(UNIT.PLAYER))
				hideBossFrames(true)
				if ensureDB("boss").enabled then updateBossFrames(true) end
				updateAllRaidTargetIcons()
				applyVisibilityRulesAll()
			end)
		end
	end
	updatePortraitEventRegistration()
end

function UF.Enable()
	local cfg = ensureDB("player")
	cfg.enabled = true
	ensureEventHandling()
	applyConfig("player")
	if ensureDB("target").enabled then applyConfig("target") end
	local totCfg = ensureDB(UNIT.TARGET_TARGET)
	if totCfg.enabled then updateTargetTargetFrame(totCfg, true) end
	if ensureDB(UNIT.FOCUS).enabled then updateFocusFrame(ensureDB(UNIT.FOCUS), true) end
	if ensureDB(UNIT.PET).enabled then applyConfig(UNIT.PET) end
	local bossCfg = ensureDB("boss")
	if bossCfg.enabled then
		ensureBossFramesReady(bossCfg)
		updateBossFrames(true)
	end
	-- hideBlizzardPlayerFrame()
	-- hideBlizzardTargetFrame()
end

function UF.Disable()
	local cfg = ensureDB("player")
	cfg.enabled = false
	if states.player and states.player.frame then states.player.frame:Hide() end
	restoreClassResourceFrames()
	stopToTTicker()
	applyVisibilityRules("player")
	addon.variables.requireReload = true
	if addon.functions and addon.functions.checkReloadFrame then addon.functions.checkReloadFrame() end
	if _G.PlayerFrame and not InCombatLockdown() then
		_G.PlayerFrame:SetAlpha(1)
		_G.PlayerFrame:Show()
	end
	ensureEventHandling()
end

function UF.Refresh()
	local bossCfg = ensureDB("boss")
	if bossCfg.enabled then DisableBossFrames() end
	ensureEventHandling()
	if not anyUFEnabled() then
		hideBossFrames()
		applyVisibilityRulesAll()
		return
	end
	applyConfig("player")
	applyConfig("target")
	local focusCfg = ensureDB(UNIT.FOCUS)
	if focusCfg.enabled then
		updateFocusFrame(focusCfg, true)
	elseif applyFrameRuleOverride then
		applyFrameRuleOverride(BLIZZ_FRAME_NAMES.focus, false)
		applyVisibilityRules(UNIT.FOCUS)
	end
	local targetCfg = ensureDB("target")
	if targetCfg.enabled and UnitExists and UnitExists(UNIT.TARGET) and states[UNIT.TARGET] and states[UNIT.TARGET].frame then
		states[UNIT.TARGET].barGroup:Show()
		states[UNIT.TARGET].status:Show()
	end
	local totCfg = ensureDB(UNIT.TARGET_TARGET)
	updateTargetTargetFrame(totCfg, true)
	if ensureDB(UNIT.PET).enabled then
		applyConfig(UNIT.PET)
	elseif applyFrameRuleOverride then
		applyFrameRuleOverride(BLIZZ_FRAME_NAMES.pet, false)
		applyVisibilityRules(UNIT.PET)
	end
	if bossCfg.enabled then
		ensureBossFramesReady(bossCfg)
		updateBossFrames(true)
	else
		hideBossFrames()
		applyVisibilityRules("boss")
	end
end

function UF.RefreshUnit(unit)
	ensureEventHandling()
	if not anyUFEnabled() then return end
	if unit == UNIT.TARGET_TARGET then
		local totCfg = ensureDB(UNIT.TARGET_TARGET)
		updateTargetTargetFrame(totCfg, true)
		ensureToTTicker()
	elseif unit == UNIT.TARGET then
		applyConfig(UNIT.TARGET)
		local targetCfg = ensureDB("target")
		if targetCfg.enabled and UnitExists and UnitExists(UNIT.TARGET) and states[UNIT.TARGET] and states[UNIT.TARGET].frame then
			states[UNIT.TARGET].barGroup:Show()
			states[UNIT.TARGET].status:Show()
		end
	elseif unit == UNIT.FOCUS then
		local focusCfg = ensureDB(UNIT.FOCUS)
		if focusCfg.enabled then
			updateFocusFrame(focusCfg, true)
		elseif applyFrameRuleOverride then
			applyFrameRuleOverride(BLIZZ_FRAME_NAMES.focus, false)
			applyVisibilityRules(UNIT.FOCUS)
		end
	elseif unit == UNIT.PET then
		if ensureDB(UNIT.PET).enabled then
			applyConfig(UNIT.PET)
		elseif applyFrameRuleOverride then
			applyFrameRuleOverride(BLIZZ_FRAME_NAMES.pet, false)
			applyVisibilityRules(UNIT.PET)
		end
	elseif isBossUnit(unit) then
		updateBossFrames(true)
	else
		applyConfig(UNIT.PLAYER)
	end
end

-- Auto-enable on load when configured
if not addon.Aura.UFInitialized then
	addon.Aura.UFInitialized = true
	local cfg = ensureDB("player")
	if cfg.enabled then After(0.1, function() UF.Enable() end) end
	local tc = ensureDB("target")
	if tc.enabled then
		ensureEventHandling()
		applyConfig("target")
		-- hideBlizzardTargetFrame()
	end
	local ttc = ensureDB(UNIT.TARGET_TARGET)
	if ttc.enabled then
		ensureEventHandling()
		updateTargetTargetFrame(ttc, true)
		ensureToTTicker()
	end
	local pcfg = ensureDB(UNIT.PET)
	if pcfg.enabled then
		ensureEventHandling()
		applyConfig(UNIT.PET)
	elseif applyFrameRuleOverride then
		applyFrameRuleOverride(BLIZZ_FRAME_NAMES.pet, false)
	end
	local fcfg = ensureDB(UNIT.FOCUS)
	if fcfg.enabled then
		ensureEventHandling()
		updateFocusFrame(fcfg, true)
	elseif applyFrameRuleOverride then
		applyFrameRuleOverride(BLIZZ_FRAME_NAMES.focus, false)
	end
	local bcfg = ensureDB("boss")
	if bcfg.enabled then
		ensureEventHandling()
		ensureBossFramesReady(bcfg)
		updateBossFrames(true)
	end
end
if isBossFrameSettingEnabled() then DisableBossFrames() end

UF.targetAuras = targetAuras
UF.defaults = defaults
UF.GetDefaults = function(unit) return defaultsFor(unit) end
UF.EnsureDB = ensureDB
UF.GetConfig = ensureDB
UF.EnsureFrames = ensureFrames
UF.ApplyVisibilityRules = applyVisibilityRules
UF.ApplyVisibilityRulesAll = applyVisibilityRulesAll
UF.StopEventsIfInactive = function() ensureEventHandling() end
UF.UpdateBossFrames = updateBossFrames
UF.HideBossFrames = hideBossFrames
UF.FullScanTargetAuras = fullScanTargetAuras
UF.CopySettings = copySettings
UF.ExportProfile = exportUnitFrameProfile
UF.ImportProfile = importUnitFrameProfile
UF.ExportErrorMessage = exportProfileErrorMessage
UF.ImportErrorMessage = importProfileErrorMessage
addon.Aura.functions = addon.Aura.functions or {}
addon.Aura.functions.importUFProfile = importUnitFrameProfile
addon.Aura.functions.exportUFProfile = exportUnitFrameProfile
