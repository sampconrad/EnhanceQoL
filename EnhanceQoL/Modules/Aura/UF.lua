local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Aura = addon.Aura or {}
local UF = addon.Aura.UF or {}
addon.Aura.UF = UF
UF.ui = UF.ui or {}
local UFHelper = addon.Aura.UFHelper
UF.AuraUtil = UF.AuraUtil or {}
local AuraUtil = UF.AuraUtil
UF.ClassResourceUtil = UF.ClassResourceUtil or {}
local ClassResourceUtil = UF.ClassResourceUtil
UF.TotemFrameUtil = UF.TotemFrameUtil or {}
local TotemFrameUtil = UF.TotemFrameUtil
addon.variables = addon.variables or {}
addon.variables.ufSampleAbsorb = addon.variables.ufSampleAbsorb or {}
addon.variables.ufSampleHealAbsorb = addon.variables.ufSampleHealAbsorb or {}
local maxBossFrames = MAX_BOSS_FRAMES or 5
local UF_PROFILE_SHARE_KIND = "EQOL_UF_PROFILE"
local smoothFill = Enum.StatusBarInterpolation.ExponentialEaseOut
local TEXT_UPDATE_INTERVAL = 0.1
UF._clientSceneActive = false

local function getSmoothInterpolation(cfg, def)
	if not smoothFill then return nil end
	local flag = cfg and cfg.smoothFill
	if flag == nil and def then flag = def.smoothFill end
	if flag == true then return smoothFill end
	return nil
end

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
local MSQ = LibStub("Masque", true)
local MSQgroup
if MSQ then MSQgroup = MSQ:Group("EnhanceQoL", L["Unit Frame Buffs/Debuffs"]) end
local LSM = LibStub("LibSharedMedia-3.0")
local AceGUI = addon.AceGUI or LibStub("AceGUI-3.0")
local DEFAULT_NOT_INTERRUPTIBLE_COLOR = { 204 / 255, 204 / 255, 204 / 255, 1 }
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs or function() return 0 end
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs or function() return 0 end
local RegisterStateDriver = _G.RegisterStateDriver
local UnregisterStateDriver = _G.UnregisterStateDriver
local IsResting = _G.IsResting
local UnitIsResting = _G.UnitIsResting
local IsTargetLoose = _G.IsTargetLoose
local C_PlayerInteractionManager = _G.C_PlayerInteractionManager
local After = C_Timer and C_Timer.After
local NewTicker = C_Timer and C_Timer.NewTicker
local max = math.max
local wipe = wipe or (table and table.wipe)
local SetFrameVisibilityOverride = addon.functions and addon.functions.SetFrameVisibilityOverride
local HasFrameVisibilityOverride = addon.functions and addon.functions.HasFrameVisibilityOverride
local NormalizeUnitFrameVisibilityConfig = addon.functions and addon.functions.NormalizeUnitFrameVisibilityConfig
local ApplyFrameVisibilityConfig = addon.functions and addon.functions.ApplyFrameVisibilityConfig

local shouldShowSampleCast
local setSampleCast
local shouldHideClassificationText

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
local RELATIVE_ANCHOR_FRAME_MAP = {
	PlayerFrame = { uf = UF_FRAME_NAMES.player.frame, blizz = BLIZZ_FRAME_NAMES.player, ufKey = "player" },
	EQOLUFPlayerFrame = { uf = UF_FRAME_NAMES.player.frame, blizz = BLIZZ_FRAME_NAMES.player, ufKey = "player" },
	TargetFrame = { uf = UF_FRAME_NAMES.target.frame, blizz = BLIZZ_FRAME_NAMES.target, ufKey = "target" },
	EQOLUFTargetFrame = { uf = UF_FRAME_NAMES.target.frame, blizz = BLIZZ_FRAME_NAMES.target, ufKey = "target" },
	TargetFrameToT = { uf = UF_FRAME_NAMES.targettarget.frame, blizz = BLIZZ_FRAME_NAMES.targettarget, ufKey = "targettarget" },
	EQOLUFToTFrame = { uf = UF_FRAME_NAMES.targettarget.frame, blizz = BLIZZ_FRAME_NAMES.targettarget, ufKey = "targettarget" },
	FocusFrame = { uf = UF_FRAME_NAMES.focus.frame, blizz = BLIZZ_FRAME_NAMES.focus, ufKey = "focus" },
	EQOLUFFocusFrame = { uf = UF_FRAME_NAMES.focus.frame, blizz = BLIZZ_FRAME_NAMES.focus, ufKey = "focus" },
	PetFrame = { uf = UF_FRAME_NAMES.pet.frame, blizz = BLIZZ_FRAME_NAMES.pet, ufKey = "pet" },
	EQOLUFPetFrame = { uf = UF_FRAME_NAMES.pet.frame, blizz = BLIZZ_FRAME_NAMES.pet, ufKey = "pet" },
	BossTargetFrameContainer = { uf = "EQOLUFBossContainer", blizz = "BossTargetFrameContainer", ufKey = "boss" },
	EQOLUFBossContainer = { uf = "EQOLUFBossContainer", blizz = "BossTargetFrameContainer", ufKey = "boss" },
}

local function isMappedUFEnabled(ufKey)
	local ufCfg = addon.db and addon.db.ufFrames
	local cfg = ufCfg and ufCfg[ufKey]
	return cfg and cfg.enabled == true
end

local function resolveRelativeAnchorFrame(relativeName)
	if type(relativeName) ~= "string" or relativeName == "" or relativeName == "UIParent" then return UIParent end
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
local MIN_WIDTH = 50
local classResourceFramesByClass = {
	DEATHKNIGHT = { "RuneFrame" },
	DRUID = { "DruidComboPointBarFrame" },
	EVOKER = { "EssencePlayerFrame" },
	MAGE = { "MageArcaneChargesFrame" },
	MONK = { "MonkHarmonyBarFrame" },
	PALADIN = { "PaladinPowerBarFrame" },
	ROGUE = { "RogueComboPointBarFrame" },
	SHAMAN = { "ShamanMaelstromWeaponBarFrame" },
	WARLOCK = { "WarlockPowerFrame" },
}
local totemFrameClasses = {
	DEATHKNIGHT = true,
	DRUID = true,
	MAGE = true,
	MONK = true,
	PALADIN = true,
	PRIEST = true,
	SHAMAN = true,
	WARLOCK = true,
}
local classResourceOriginalLayouts = {}
local classResourceManagedFrames = {}
local classResourceHooks = {}
local applyClassResourceLayout
local totemFrameOriginalLayout
local totemFrameManaged
local totemFrameHooked
local totemFrameSample
local applyTotemFrameLayout

local bossUnitLookup = { boss = true }
for i = 1, maxBossFrames do
	bossUnitLookup["boss" .. i] = true
end

local function isBossUnit(unit) return type(unit) == "string" and bossUnitLookup[unit] == true end

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
	}
end

local defaults = {
	player = {
		enabled = false,
		hideInPetBattle = false,
		hideInClientScene = true,
		showTooltip = false,
		tooltipUseEditMode = false,
		smoothFill = false,
		width = 220,
		healthHeight = 24,
		powerHeight = 16,
		statusHeight = 18,
		anchor = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 0, y = -200 },
		strata = "LOW",
		frameLevel = nil,
		border = {
			enabled = true,
			texture = "DEFAULT",
			color = { 0, 0, 0, 0.8 },
			edgeSize = 1,
			inset = 0,
			detachedPower = false,
			detachedPowerTexture = nil,
			detachedPowerSize = nil,
			detachedPowerOffset = nil,
		},
		highlight = {
			enabled = false,
			mouseover = true,
			aggro = true,
			texture = "DEFAULT",
			size = 2,
			color = { 1, 0, 0, 1 },
		},
		health = {
			useCustomColor = false,
			useClassColor = false,
			useTapDeniedColor = true,
			color = { 0.0, 0.8, 0.0, 1 },
			tapDeniedColor = { 0.5, 0.5, 0.5, 1 },
			absorbColor = { 0.85, 0.95, 1.0, 0.7 },
			absorbEnabled = true,
			absorbUseCustomColor = false,
			showSampleAbsorb = false,
			absorbTexture = "SOLID",
			absorbReverseFill = false,
			useAbsorbGlow = true,
			healAbsorbColor = { 1.0, 0.3, 0.3, 0.7 },
			healAbsorbUseCustomColor = false,
			showSampleHealAbsorb = false,
			healAbsorbTexture = "SOLID",
			healAbsorbReverseFill = true,
			backdrop = { enabled = true, color = { 0, 0, 0, 0.6 }, useClassColor = false, clampToFill = false },
			textLeft = "PERCENT",
			textCenter = "NONE",
			textRight = "CURMAX",
			textDelimiter = " ",
			fontSize = 14,
			font = nil,
			fontOutline = "OUTLINE", -- fallback to default font
			offsetLeft = { x = 6, y = 0 },
			offsetCenter = { x = 0, y = 0 },
			offsetRight = { x = -6, y = 0 },
			useShortNumbers = true,
			hidePercentSymbol = false,
			roundPercent = false,
			texture = "DEFAULT",
			reverseFill = false,
		},
		power = {
			enabled = true,
			detached = false,
			detachedGrowFromCenter = false,
			detachedMatchHealthWidth = false,
			detachedFrameLevelOffset = 5,
			detachedStrata = nil,
			emptyMaxFallback = false,
			color = { 0.1, 0.45, 1, 1 },
			backdrop = { enabled = true, color = { 0, 0, 0, 0.6 } },
			useCustomColor = false,
			textLeft = "PERCENT",
			textCenter = "NONE",
			textRight = "CURMAX",
			textDelimiter = " ",
			fontSize = 14,
			font = nil,
			offsetLeft = { x = 6, y = 0 },
			offsetCenter = { x = 0, y = 0 },
			offsetRight = { x = -6, y = 0 },
			useShortNumbers = true,
			hidePercentSymbol = false,
			roundPercent = false,
			texture = "DEFAULT",
			reverseFill = false,
		},
		status = {
			enabled = true,
			fontSize = 14,
			font = nil,
			fontOutline = "OUTLINE",
			nameColorMode = "CLASS", -- CLASS or CUSTOM
			nameColor = { 0.8, 0.8, 1, 1 },
			nameUseReactionColor = false,
			levelColor = { 1, 0.85, 0, 1 },
			levelStrata = nil,
			levelFrameLevelOffset = 5,
			nameOffset = { x = 0, y = 0 },
			levelOffset = { x = 0, y = 0 },
			levelEnabled = true,
			hideLevelAtMax = false,
			classificationIcon = {
				enabled = false,
				hideText = false,
				size = 16,
				offset = { x = -4, y = 0 },
			},
			nameMaxChars = 0,
			unitStatus = {
				enabled = false,
				fontSize = nil,
				font = nil,
				fontOutline = nil,
				showGroup = true,
				groupFormat = "GROUP",
				groupFontSize = nil,
				groupOffset = { x = 0, y = 0 },
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
		combatFeedback = {
			enabled = false,
			font = nil,
			fontSize = 30,
			anchor = "CENTER",
			location = "STATUS",
			offset = { x = 0, y = 0 },
			sample = false,
			sampleAmount = 12345,
			sampleEvent = "WOUND",
			events = {
				WOUND = true,
				HEAL = true,
				ENERGIZE = true,
				MISS = true,
				DODGE = true,
				PARRY = true,
				BLOCK = true,
				RESIST = true,
				ABSORB = true,
				IMMUNE = true,
				DEFLECT = true,
				REFLECT = true,
				EVADE = true,
				INTERRUPT = true,
			},
		},
		cast = {
			enabled = false,
			standalone = false,
			width = 220,
			height = 16,
			strata = nil,
			frameLevelOffset = nil,
			anchor = "BOTTOM", -- or "TOP"
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
			useGradient = false,
			gradientStartColor = { 1, 1, 1, 1 },
			gradientEndColor = { 1, 1, 1, 1 },
			gradientDirection = "HORIZONTAL",
			gradientMode = "CASTBAR",
			notInterruptibleColor = DEFAULT_NOT_INTERRUPTIBLE_COLOR,
			showInterruptFeedback = true,
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
			totemFrame = {
				enabled = false,
				anchor = "BOTTOMRIGHT",
				offset = { x = 0, y = 20 },
				scale = 1,
				showSample = false,
			},
		},
		raidIcon = {
			enabled = true,
			size = 18,
			offset = { x = 0, y = -2 },
		},
		leaderIcon = {
			enabled = false,
			size = 12,
			offset = { x = 0, y = 0 },
		},
		pvpIndicator = {
			enabled = false,
			size = 20,
			offset = { x = -24, y = -2 },
		},
		roleIndicator = {
			enabled = false,
			size = 18,
			offset = { x = 24, y = -2 },
		},
		portrait = {
			enabled = false,
			side = "LEFT",
			squareBackground = true,
			separator = {
				enabled = true,
				texture = "SOLID",
			},
		},
		privateAuras = {
			enabled = false,
			countdownFrame = true,
			countdownNumbers = false,
			showDispelType = false,
			icon = {
				amount = 2,
				size = 24,
				point = "LEFT",
				offset = 3,
				borderScale = nil,
			},
			parent = {
				point = "BOTTOM",
				offsetX = 0,
				offsetY = -4,
			},
			duration = {
				enable = false,
				point = "BOTTOM",
				offsetX = 0,
				offsetY = -1,
			},
		},
	},
	target = {
		enabled = false,
		showTooltip = false,
		rangeFade = {
			enabled = true,
			alpha = 0.5,
			ignoreUnlimitedSpells = true,
		},
		auraIcons = {
			enabled = true,
			size = 24,
			debuffSize = nil,
			padding = 2,
			max = 16,
			perRow = 0,
			showCooldown = true,
			showCooldownBuffs = nil,
			showCooldownDebuffs = nil,
			showBuffs = true,
			showDebuffs = true,
			blizzardDispelBorder = false,
			blizzardDispelBorderAlpha = 1,
			blizzardDispelBorderAlphaNot = 0,
			borderTexture = "DEFAULT",
			borderRenderMode = "EDGE",
			borderSize = nil,
			borderOffset = 0,
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
			countFontSizeBuff = nil,
			countFontSizeDebuff = nil,
			countFontOutline = nil,
			cooldownFontSize = 12,
			cooldownFontSizeBuff = nil,
			cooldownFontSizeDebuff = nil,
		},
		privateAuras = {
			enabled = false,
			countdownFrame = true,
			countdownNumbers = false,
			showDispelType = false,
			icon = {
				amount = 2,
				size = 24,
				point = "LEFT",
				offset = 3,
				borderScale = nil,
			},
			parent = {
				point = "BOTTOM",
				offsetX = 0,
				offsetY = -4,
			},
			duration = {
				enable = false,
				point = "BOTTOM",
				offsetX = 0,
				offsetY = -1,
			},
		},
		cast = {
			enabled = true,
			width = 200,
			height = 16,
			strata = nil,
			frameLevelOffset = nil,
			anchor = "BOTTOM", -- or "TOP"
			offset = { x = 11, y = -4 },
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
			useGradient = false,
			gradientStartColor = { 1, 1, 1, 1 },
			gradientEndColor = { 1, 1, 1, 1 },
			gradientDirection = "HORIZONTAL",
			gradientMode = "CASTBAR",
			notInterruptibleColor = DEFAULT_NOT_INTERRUPTIBLE_COLOR,
			showInterruptFeedback = true,
		},
		portrait = {
			enabled = false,
			side = "LEFT",
			squareBackground = false,
			separator = {
				enabled = true,
				texture = "SOLID",
			},
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
			side = "LEFT",
			squareBackground = false,
			separator = {
				enabled = true,
				texture = "SOLID",
			},
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
local focusAuras = {}
local focusAuraOrder = {}
local focusAuraIndexById = {}
local playerAuras = {}
local playerAuraOrder = {}
local playerAuraIndexById = {}
local bossAuraStates = {}
local AURA_FILTER_HELPFUL = "HELPFUL|INCLUDE_NAME_PLATE_ONLY"
local AURA_FILTER_HARMFUL = "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY"
local AURA_FILTER_HARMFUL_ALL = "HARMFUL|INCLUDE_NAME_PLATE_ONLY"
local SAMPLE_BUFF_ICONS = { 136243, 135940, 136085, 136097, 136116, 136048, 135932, 136108 }
local SAMPLE_DEBUFF_ICONS = { 136207, 136160, 136128, 135804, 136168, 132104, 136118, 136214 }
local SAMPLE_DISPEL_TYPES = { "Magic", "Curse", "Disease", "Poison" }
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

local function defaultsFor(unit)
	if isBossUnit(unit) then return defaults.boss or defaults.target or defaults.player or {} end
	return defaults[unit] or defaults.player or {}
end

function AuraUtil.getAuraFilters(unit)
	if unit == UNIT.PLAYER or unit == "player" then return AURA_FILTER_HELPFUL, AURA_FILTER_HARMFUL_ALL end
	return AURA_FILTER_HELPFUL, AURA_FILTER_HARMFUL
end

function AuraUtil.isAuraIconsEnabled(ac, def)
	if ac and ac.enabled ~= nil then return ac.enabled ~= false end
	local defAc = (def and def.auraIcons) or defaults.target.auraIcons
	if defAc and defAc.enabled ~= nil then return defAc.enabled ~= false end
	return true
end

function AuraUtil.getAuraTables(unit)
	unit = unit or "target"
	if unit == UNIT.PLAYER or unit == "player" then return playerAuras, playerAuraOrder, playerAuraIndexById end
	if unit == UNIT.TARGET or unit == "target" then return targetAuras, targetAuraOrder, targetAuraIndexById end
	if unit == UNIT.FOCUS or unit == "focus" then return focusAuras, focusAuraOrder, focusAuraIndexById end
	if not isBossUnit(unit) or unit == "boss" then return nil end
	local state = bossAuraStates[unit]
	if not state then
		state = { auras = {}, order = {}, indexById = {} }
		bossAuraStates[unit] = state
	end
	return state.auras, state.order, state.indexById
end

function AuraUtil.resetTargetAuras(unit)
	local auras, order, indexById = AuraUtil.getAuraTables(unit)
	if not auras then return end
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
	UF._defaultsMerged = UF._defaultsMerged or setmetatable({}, { __mode = "k" })
	if UF._defaultsMerged[udb] then return udb end
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
	UF._defaultsMerged[udb] = true
	return udb
end

-- Shared context for external Unit Frame importers (see UF_Importers.lua).
UF._ensureDB = ensureDB
UF._defaultsFor = defaultsFor
UF._isBossUnit = isBossUnit
UF._maxBossFrames = maxBossFrames
UF._frameNames = UF_FRAME_NAMES
UF._minWidth = MIN_WIDTH
UF._unitTokens = UNIT

local function hasVisibilityRules(cfg)
	if not cfg then return false end
	local raw = cfg.visibility
	return type(raw) == "table" and next(raw) ~= nil
end

local function syncTargetRangeFadeConfig(cfg, def)
	local st = states[UNIT.TARGET]
	if not st then
		st = {}
		states[UNIT.TARGET] = st
	end
	cfg = cfg or st.cfg or ensureDB(UNIT.TARGET)
	def = def or defaultsFor(UNIT.TARGET)
	local rcfg = (cfg and cfg.rangeFade) or (def and def.rangeFade) or {}
	local blockedByVisibility = hasVisibilityRules(cfg) == true
	local enabled = (cfg and cfg.enabled ~= false) and rcfg.enabled == true and not blockedByVisibility
	local alpha = tonumber(rcfg.alpha)
	if alpha == nil then alpha = 0.5 end
	if alpha < 0 then alpha = 0 end
	if alpha > 1 then alpha = 1 end
	local ignoreUnlimited = rcfg.ignoreUnlimitedSpells
	if ignoreUnlimited == nil then
		ignoreUnlimited = true
	else
		ignoreUnlimited = ignoreUnlimited == true
	end
	st._rangeFadeEnabledCfg = enabled == true
	st._rangeFadeBlockedByVisibility = blockedByVisibility
	st._rangeFadeAlphaCfg = alpha
	st._rangeFadeIgnoreUnlimited = ignoreUnlimited
	if UFHelper and UFHelper.RangeFadeBuildSpellListForConfig then
		st._rangeFadeSpellListCfg = UFHelper.RangeFadeBuildSpellListForConfig(rcfg, UFHelper.RangeFadeGetCurrentSpecId and UFHelper.RangeFadeGetCurrentSpecId() or nil)
	else
		st._rangeFadeSpellListCfg = nil
	end
end

if UFHelper and UFHelper.RangeFadeRegister then
	UFHelper.RangeFadeRegister(function()
		local st = states[UNIT.TARGET]
		if not st then return false, 0.5, true end
		local enabled = st._rangeFadeEnabledCfg == true
		if addon.EditModeLib and addon.EditModeLib:IsInEditMode() then enabled = false end
		if st._rangeFadeBlockedByVisibility then enabled = false end
		local alpha = st._rangeFadeAlphaCfg
		if type(alpha) ~= "number" then alpha = 0.5 end
		local ignoreUnlimited = st._rangeFadeIgnoreUnlimited
		if ignoreUnlimited == nil then ignoreUnlimited = true end
		return enabled, alpha, ignoreUnlimited
	end, function(targetAlpha, force)
		local st = states[UNIT.TARGET]
		if not st or not st.frame or not st.frame.SetAlpha then return end
		if st._rangeFadeBlockedByVisibility then
			st._rangeFadeAlpha = nil
			return
		end
		if force or st._rangeFadeAlpha ~= targetAlpha then
			st._rangeFadeAlpha = targetAlpha
			st.frame:SetAlpha(targetAlpha)
		end
	end, function()
		local st = states[UNIT.TARGET]
		if not st then return nil end
		return st._rangeFadeSpellListCfg
	end)
end

local function refreshRangeFadeSpells(rebuildSpellList)
	if not UFHelper then return end
	syncTargetRangeFadeConfig(ensureDB(UNIT.TARGET), defaultsFor(UNIT.TARGET))
	if UFHelper.RangeFadeMarkConfigDirty then UFHelper.RangeFadeMarkConfigDirty() end
	if rebuildSpellList and UFHelper.RangeFadeMarkSpellListDirty then UFHelper.RangeFadeMarkSpellListDirty() end
	if UFHelper.RangeFadeUpdateSpells then UFHelper.RangeFadeUpdateSpells() end
end

local function copySettings(fromUnit, toUnit, opts)
	opts = opts or {}
	if not fromUnit or not toUnit or fromUnit == toUnit then return false end
	local src = ensureDB(fromUnit)
	local dest = ensureDB(toUnit)
	if not src or not dest then return false end
	local function cloneSettingValue(value)
		if type(value) ~= "table" then return value end
		if addon.functions and addon.functions.copyTable then return addon.functions.copyTable(value) end
		if CopyTable then return CopyTable(value) end
		local out = {}
		for key, child in pairs(value) do
			out[key] = cloneSettingValue(child)
		end
		return out
	end
	local function getPathValue(root, path)
		if type(root) ~= "table" or type(path) ~= "table" then return nil, false end
		local cur = root
		for i = 1, #path do
			if type(cur) ~= "table" then return nil, false end
			cur = cur[path[i]]
			if cur == nil then return nil, false end
		end
		return cur, true
	end
	local function clearPathValue(root, path)
		if type(root) ~= "table" or type(path) ~= "table" or #path == 0 then return end
		if #path == 1 then
			root[path[1]] = nil
			return
		end
		local cur = root
		local trail = {}
		for i = 1, #path - 1 do
			local key = path[i]
			local nxt = cur[key]
			if type(nxt) ~= "table" then return end
			trail[#trail + 1] = { parent = cur, key = key }
			cur = nxt
		end
		cur[path[#path]] = nil
		for i = #trail, 1, -1 do
			local node = trail[i]
			local child = node.parent[node.key]
			if type(child) == "table" and not next(child) then
				node.parent[node.key] = nil
			else
				break
			end
		end
	end
	local function setPathValue(root, path, value)
		if type(root) ~= "table" or type(path) ~= "table" or #path == 0 then return end
		if value == nil then
			clearPathValue(root, path)
			return
		end
		local cur = root
		for i = 1, #path - 1 do
			local key = path[i]
			if type(cur[key]) ~= "table" then cur[key] = {} end
			cur = cur[key]
		end
		cur[path[#path]] = value
	end
	local function copyPathValue(path)
		local value, exists = getPathValue(src, path)
		if exists then
			setPathValue(dest, path, cloneSettingValue(value))
		else
			clearPathValue(dest, path)
		end
	end
	local copySectionRules = {
		frame = {
			{ "showTooltip" },
			{ "tooltipUseEditMode" },
			{ "hideInVehicle" },
			{ "hideInPetBattle" },
			{ "hideInClientScene" },
			{ "visibility" },
			{ "visibilityFade" },
			{ "width" },
			{ "anchor" },
			{ "spacing" },
			{ "growth" },
			{ "strata" },
			{ "frameLevel" },
			{ "smoothFill" },
			{ "border" },
			{ "highlight" },
			{ "power", "detachedStrata" },
			{ "power", "detachedFrameLevelOffset" },
		},
		portrait = {
			{ "portrait" },
		},
		rangeFade = {
			{ "rangeFade" },
		},
		health = {
			{ "healthHeight" },
			{ "health" },
		},
		absorb = {
			{ "health", "absorbColor" },
			{ "health", "absorbUseCustomColor" },
			{ "health", "useAbsorbGlow" },
			{ "health", "absorbReverseFill" },
			{ "health", "absorbOverlayHeight" },
			{ "health", "absorbTexture" },
		},
		healAbsorb = {
			{ "health", "healAbsorbColor" },
			{ "health", "healAbsorbUseCustomColor" },
			{ "health", "healAbsorbReverseFill" },
			{ "health", "healAbsorbOverlayHeight" },
			{ "health", "healAbsorbTexture" },
		},
		power = {
			{ "powerHeight" },
			{ "power" },
		},
		classResource = {
			{ "classResource" },
		},
		totemFrame = {
			{ "classResource", "totemFrame" },
		},
		raidicon = {
			{ "raidIcon" },
		},
		cast = {
			{ "cast" },
		},
		status = {
			{ "status", "enabled" },
			{ "status", "fontSize" },
			{ "status", "font" },
			{ "status", "fontOutline" },
			{ "status", "nameColorMode" },
			{ "status", "nameColor" },
			{ "status", "nameUseReactionColor" },
			{ "status", "nameAnchor" },
			{ "status", "nameOffset" },
			{ "status", "nameMaxChars" },
			{ "status", "nameFontSize" },
			{ "status", "levelEnabled" },
			{ "status", "hideLevelAtMax" },
			{ "status", "levelColorMode" },
			{ "status", "levelColor" },
			{ "status", "levelAnchor" },
			{ "status", "levelOffset" },
			{ "status", "levelStrata" },
			{ "status", "levelFrameLevelOffset" },
			{ "status", "levelFontSize" },
			{ "status", "classificationIcon" },
		},
		unitStatus = {
			{ "status", "unitStatus" },
			{ "status", "combatIndicator" },
			{ "pvpIndicator" },
			{ "roleIndicator" },
			{ "leaderIcon" },
			{ "resting" },
		},
		combatFeedback = {
			{ "combatFeedback" },
		},
		auras = {
			{ "auraIcons" },
		},
		privateAuras = {
			{ "privateAuras" },
		},
	}
	local keepAnchor = opts.keepAnchor ~= false
	local keepEnabled = opts.keepEnabled ~= false
	local anchor = keepAnchor and dest.anchor and cloneSettingValue(dest.anchor) or dest.anchor
	local enabled = keepEnabled and dest.enabled
	local copied = false
	if type(opts.sections) == "table" then
		for _, sectionId in ipairs(opts.sections) do
			local rules = copySectionRules[sectionId]
			if type(rules) == "table" then
				for _, path in ipairs(rules) do
					copyPathValue(path)
				end
				copied = true
			end
		end
	else
		if wipe then wipe(dest) end
		for k, v in pairs(src) do
			dest[k] = cloneSettingValue(v)
		end
		copied = true
	end
	if not copied then return false end
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
	local size = UFHelper.clamp(rcfg.size or sizeDef or 18, 10, 30)
	local ox = (rcfg.offset and rcfg.offset.x) or offsetDef.x or 0
	local oy = (rcfg.offset and rcfg.offset.y) or offsetDef.y or -2
	local centerOffset = (st and st._portraitCenterOffset) or 0
	st.raidIcon:ClearAllPoints()
	st.raidIcon:SetSize(size, size)
	st.raidIcon:SetPoint("TOP", st.frame, "TOP", (ox or 0) + centerOffset, oy)
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

function ClassResourceUtil.getClassResourceFrames()
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

function ClassResourceUtil.storeClassResourceDefaults(frame)
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

function ClassResourceUtil.restoreClassResourceFrame(frame)
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

function ClassResourceUtil.restoreClassResourceFrames()
	for frame in pairs(classResourceManagedFrames) do
		ClassResourceUtil.restoreClassResourceFrame(frame)
	end
end

function ClassResourceUtil.onClassResourceShow()
	if applyClassResourceLayout then applyClassResourceLayout(states[UNIT.PLAYER] and states[UNIT.PLAYER].cfg or ensureDB(UNIT.PLAYER)) end
end

function ClassResourceUtil.SetFrameLevelHookOffset(offset)
	offset = tonumber(offset) or 0
	if offset < 0 then offset = 0 end
	ClassResourceUtil._frameLevelMinimum = 7 + offset
end

function ClassResourceUtil.hookClassResourceFrame(frame)
	if not frame or classResourceHooks[frame] then return end
	classResourceHooks[frame] = true
	frame:HookScript("OnShow", ClassResourceUtil.onClassResourceShow)
	if hooksecurefunc and frame.SetFrameLevel then
		hooksecurefunc(frame, "SetFrameLevel", function(self)
			if not classResourceManagedFrames[self] then return end
			if self._eqolClassResourceLevelHook then return end
			local minLevel = ClassResourceUtil._frameLevelMinimum or 7
			if self:GetFrameLevel() >= minLevel then return end
			self._eqolClassResourceLevelHook = true
			self:SetFrameLevel(minLevel)
			self._eqolClassResourceLevelHook = nil
		end)
	end
end

applyClassResourceLayout = function(cfg)
	local classKey = addon.variables and addon.variables.unitClass
	if not classKey or not classResourceFramesByClass[classKey] then
		ClassResourceUtil.restoreClassResourceFrames()
		return
	end
	local frames = ClassResourceUtil.getClassResourceFrames()
	if not frames or #frames == 0 then
		ClassResourceUtil.restoreClassResourceFrames()
		return
	end
	local st = states[UNIT.PLAYER]
	if not st or not st.frame then return end
	local def = defaultsFor(UNIT.PLAYER)
	local rcfg = (cfg and cfg.classResource) or (def and def.classResource) or {}
	if rcfg.enabled == false then
		ClassResourceUtil.restoreClassResourceFrames()
		return
	end
	if InCombatLockdown and InCombatLockdown() then return end

	local anchor = rcfg.anchor or (def.classResource and def.classResource.anchor) or "TOP"
	local offsetX = (rcfg.offset and rcfg.offset.x) or 0
	local offsetY = (rcfg.offset and rcfg.offset.y)
	if offsetY == nil then offsetY = anchor == "TOP" and -5 or 5 end
	local scale = rcfg.scale or (def.classResource and def.classResource.scale) or 1
	local resourceStrata = rcfg.strata
	if resourceStrata == nil then resourceStrata = def.classResource and def.classResource.strata end
	if type(resourceStrata) == "string" and resourceStrata ~= "" then
		resourceStrata = string.upper(resourceStrata)
	else
		resourceStrata = nil
	end
	local frameLevelOffset = tonumber(rcfg.frameLevelOffset)
	if frameLevelOffset == nil then frameLevelOffset = tonumber(def.classResource and def.classResource.frameLevelOffset) end
	if frameLevelOffset == nil then frameLevelOffset = 5 end
	if frameLevelOffset < 0 then frameLevelOffset = 0 end
	if ClassResourceUtil.SetFrameLevelHookOffset then ClassResourceUtil.SetFrameLevelHookOffset(frameLevelOffset) end

	for _, frame in ipairs(frames) do
		ClassResourceUtil.storeClassResourceDefaults(frame)
		ClassResourceUtil.hookClassResourceFrame(frame)
		classResourceManagedFrames[frame] = true
		frame.ignoreFramePositionManager = true
		frame:ClearAllPoints()
		frame:SetPoint(anchor, st.frame, anchor, offsetX, offsetY)
		frame:SetParent(st.frame)
		if frame.SetScale then frame:SetScale(scale) end
		if frame.SetFrameStrata and st.frame.GetFrameStrata then frame:SetFrameStrata(resourceStrata or st.frame:GetFrameStrata()) end
		if frame.SetFrameLevel and st.frame.GetFrameLevel then frame:SetFrameLevel(max(0, (st.frame:GetFrameLevel() or 0) + frameLevelOffset)) end
	end
end

function TotemFrameUtil.storeTotemFrameDefaults(frame)
	if not frame or totemFrameOriginalLayout then return end
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
	totemFrameOriginalLayout = info
end

local function normalizeTotemFrameConfig(value)
	if value == true then return { enabled = true } end
	if type(value) == "table" then return value end
	return {}
end

function TotemFrameUtil.ensureSampleFrame(parent)
	if not totemFrameSample then
		totemFrameSample = CreateFrame("Frame", nil, parent)
		totemFrameSample.ignoreFramePositionManager = true
		totemFrameSample._eqolManageVisibility = true
		totemFrameSample:SetSize(37, 37)
		totemFrameSample:EnableMouse(false)
	end
	if parent and totemFrameSample:GetParent() ~= parent then totemFrameSample:SetParent(parent) end
	return totemFrameSample
end

function TotemFrameUtil.hideSampleFrame()
	if not totemFrameSample then return end
	if totemFrameSample._eqolSampleButton then totemFrameSample._eqolSampleButton:Hide() end
	totemFrameSample:Hide()
end

function TotemFrameUtil.syncSampleFrame(sampleFrame, totemFrame, fallbackParent)
	if not sampleFrame or not totemFrame then return end
	sampleFrame:ClearAllPoints()
	local numPoints = totemFrame.GetNumPoints and totemFrame:GetNumPoints() or 0
	if numPoints > 0 then
		for i = 1, numPoints do
			sampleFrame:SetPoint(totemFrame:GetPoint(i))
		end
	elseif fallbackParent then
		sampleFrame:SetPoint("TOPRIGHT", fallbackParent, "BOTTOMRIGHT", 0, 0)
	end
	if sampleFrame.SetScale and totemFrame.GetScale then sampleFrame:SetScale(totemFrame:GetScale()) end
	if sampleFrame.SetFrameStrata and totemFrame.GetFrameStrata then sampleFrame:SetFrameStrata(totemFrame:GetFrameStrata()) end
	if sampleFrame.SetFrameLevel and totemFrame.GetFrameLevel then sampleFrame:SetFrameLevel(totemFrame:GetFrameLevel()) end
end

function TotemFrameUtil.restoreTotemFrame()
	TotemFrameUtil.hideSampleFrame()
	if not totemFrameManaged then return end
	local frame = _G.TotemFrame
	if not frame then return end
	local info = totemFrameOriginalLayout
	totemFrameManaged = nil
	if not info then return end
	if frame._eqolSampleButton then frame._eqolSampleButton:Hide() end
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

function TotemFrameUtil.onTotemFrameShow()
	if applyTotemFrameLayout then applyTotemFrameLayout(states[UNIT.PLAYER] and states[UNIT.PLAYER].cfg or ensureDB(UNIT.PLAYER)) end
end

function TotemFrameUtil.hookTotemFrame(frame)
	if not frame or totemFrameHooked then return end
	totemFrameHooked = true
	frame:HookScript("OnShow", TotemFrameUtil.onTotemFrameShow)
	if hooksecurefunc and frame.SetFrameLevel then hooksecurefunc(frame, "SetFrameLevel", function(self)
		if frame:GetFrameLevel() < 7 then frame:SetFrameLevel(7) end
	end) end
end

function TotemFrameUtil.updateSample(frame, shouldShow, activeRefFrame)
	if not frame then return end
	local manageVisibility = frame._eqolManageVisibility == true
	local refFrame = activeRefFrame or frame
	if not shouldShow then
		if frame._eqolSampleButton then frame._eqolSampleButton:Hide() end
		if manageVisibility and frame.Hide then frame:Hide() end
		return
	end
	if refFrame and refFrame.activeTotems and refFrame.activeTotems > 0 then
		if frame._eqolSampleButton then frame._eqolSampleButton:Hide() end
		if manageVisibility and frame.Hide then frame:Hide() end
		return
	end
	local button = frame._eqolSampleButton
	if not button then
		button = CreateFrame("Button", nil, frame, "TotemButtonTemplate")
		frame._eqolSampleButton = button
		button:SetAllPoints(frame)
	end
	button.layoutIndex = 1
	button.slot = 0
	if button.Icon and button.Icon.Texture then
		button.Icon.Texture:SetTexture(136099)
		button.Icon.Texture:Show()
	end
	if button.Icon and button.Icon.Cooldown then button.Icon.Cooldown:Hide() end
	if button.Duration then
		button.Duration:SetText("")
		button.Duration:Hide()
	end
	button:SetScript("OnUpdate", nil)
	button:EnableMouse(false)
	button:Show()
	if manageVisibility and frame.Show then frame:Show() end
	if frame.Layout then frame:Layout() end
end

applyTotemFrameLayout = function(cfg)
	local frame = _G.TotemFrame
	if not frame then
		TotemFrameUtil.hideSampleFrame()
		TotemFrameUtil.restoreTotemFrame()
		return
	end
	local classKey = addon.variables and addon.variables.unitClass
	if not classKey or not totemFrameClasses[classKey] then
		TotemFrameUtil.hideSampleFrame()
		TotemFrameUtil.restoreTotemFrame()
		return
	end
	local st = states[UNIT.PLAYER]
	if not st or not st.frame then
		TotemFrameUtil.hideSampleFrame()
		return
	end
	local def = defaultsFor(UNIT.PLAYER)
	local rcfg = (cfg and cfg.classResource) or (def and def.classResource) or {}
	local tcfg = normalizeTotemFrameConfig(rcfg.totemFrame)
	local tdef = normalizeTotemFrameConfig(def and def.classResource and def.classResource.totemFrame)
	local enabled = tcfg.enabled
	if enabled == nil then enabled = tdef.enabled end
	if enabled ~= true then
		TotemFrameUtil.hideSampleFrame()
		TotemFrameUtil.restoreTotemFrame()
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		TotemFrameUtil.hideSampleFrame()
		return
	end

	TotemFrameUtil.storeTotemFrameDefaults(frame)
	TotemFrameUtil.hookTotemFrame(frame)
	totemFrameManaged = true
	frame.ignoreFramePositionManager = true
	frame:ClearAllPoints()
	local anchor = tcfg.anchor or tdef.anchor
	local offsetX = (tcfg.offset and tcfg.offset.x)
	if offsetX == nil then offsetX = (tdef.offset and tdef.offset.x) end
	if offsetX == nil then offsetX = 0 end
	local offsetY = (tcfg.offset and tcfg.offset.y)
	if offsetY == nil then offsetY = (tdef.offset and tdef.offset.y) end
	if offsetY == nil then offsetY = 0 end
	if anchor then
		local info = totemFrameOriginalLayout
		local selfPoint = (info and info.points and info.points[1] and info.points[1].point) or anchor
		frame:SetPoint(selfPoint, st.frame, anchor, offsetX, offsetY)
	else
		local info = totemFrameOriginalLayout
		if info and info.points and #info.points > 0 then
			for _, pt in ipairs(info.points) do
				local rel = pt.relativeTo
				if rel == info.parent or rel == _G.PlayerFrame then rel = st.frame end
				frame:SetPoint(pt.point, rel, pt.relativePoint, pt.x or 0, pt.y or 0)
			end
		else
			frame:SetPoint("TOPRIGHT", st.frame, "BOTTOMRIGHT", offsetX, offsetY)
		end
	end
	frame:SetParent(st.frame)
	local scale = tcfg.scale
	if scale == nil then scale = tdef.scale end
	if scale == nil then scale = (totemFrameOriginalLayout and totemFrameOriginalLayout.scale) end
	if scale == nil then scale = 1 end
	if frame.SetScale then frame:SetScale(scale) end
	if frame.SetFrameStrata and st.frame.GetFrameStrata then frame:SetFrameStrata(st.frame:GetFrameStrata()) end
	if frame.SetFrameLevel and st.frame.GetFrameLevel then frame:SetFrameLevel((st.frame:GetFrameLevel() or 0) + 5) end
	local inEditMode = addon.EditModeLib and addon.EditModeLib.IsInEditMode and addon.EditModeLib:IsInEditMode()
	local showSample = tcfg.showSample
	if showSample == nil then showSample = tdef.showSample end
	showSample = inEditMode and showSample == true
	if frame._eqolSampleButton then frame._eqolSampleButton:Hide() end
	if showSample then
		local sampleFrame = TotemFrameUtil.ensureSampleFrame(st.frame)
		TotemFrameUtil.syncSampleFrame(sampleFrame, frame, st.frame)
		TotemFrameUtil.updateSample(sampleFrame, true, frame)
	else
		TotemFrameUtil.hideSampleFrame()
	end
end

local function resolveProfileDB(profileName)
	if type(profileName) == "string" and profileName ~= "" then
		local profiles = EnhanceQoLDB and EnhanceQoLDB.profiles
		if type(profiles) ~= "table" then return nil, true end
		return profiles[profileName], true
	end
	addon.db = addon.db or {}
	return addon.db, false
end

local UF_EDITMODE_FRAME_IDS = {
	player = "EQOL_UF_Player",
	target = "EQOL_UF_Target",
	targettarget = "EQOL_UF_ToT",
	focus = "EQOL_UF_Focus",
	pet = "EQOL_UF_Pet",
	boss = "EQOL_UF_Boss",
}

function UF.SyncEditModeLayoutAnchors(units)
	if type(units) ~= "table" or #units == 0 then return end
	local editMode = addon and addon.EditMode
	if not (editMode and editMode.GetActiveLayoutName) then return end
	local layoutName = editMode:GetActiveLayoutName() or "_Global"
	addon.db = addon.db or {}
	addon.db.editModeLayouts = addon.db.editModeLayouts or {}
	local layouts = addon.db.editModeLayouts
	local layout = layouts[layoutName]
	if type(layout) ~= "table" then
		layout = {}
		layouts[layoutName] = layout
	end

	for _, unit in ipairs(units) do
		local frameId = UF_EDITMODE_FRAME_IDS[unit]
		if frameId then
			local cfg = ensureDB(unit)
			local anchor = cfg and cfg.anchor
			if anchor then
				local data = layout[frameId] or {}
				data.point = anchor.point or data.point or "CENTER"
				data.relativePoint = anchor.relativePoint or anchor.point or data.relativePoint or data.point
				data.x = anchor.x or 0
				data.y = anchor.y or 0
				layout[frameId] = data
			end
		end
	end
end

function UF.ExportProfile(scopeKey, profileName)
	local function normalize(key)
		if not key or key == "" then return "ALL" end
		if key == "ALL" then return "ALL" end
		if isBossUnit(key) then return "boss" end
		return key
	end
	scopeKey = normalize(scopeKey)
	local db, externalProfile = resolveProfileDB(profileName)
	if type(db) ~= "table" then return nil, "NO_DATA" end
	local cfg = db.ufFrames
	if not cfg and not externalProfile then
		db.ufFrames = {}
		cfg = db.ufFrames
	end
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

function UF.ImportProfile(encoded, scopeKey)
	local function normalize(key)
		if not key or key == "" then return "ALL" end
		if key == "ALL" then return "ALL" end
		if isBossUnit(key) then return "boss" end
		return key
	end
	scopeKey = normalize(scopeKey)
	encoded = UFHelper.trim(encoded or "")
	if not encoded or encoded == "" then return false, "NO_INPUT" end
	if encoded:sub(1, 5) == "!UUF_" then
		if type(UF.ImportUnhaltedProfile) ~= "function" then return false, "WRONG_KIND" end
		return UF.ImportUnhaltedProfile(encoded, scopeKey)
	end

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
				local key = normalize(unit)
				target[key] = CopyTable(frameCfg)
				applied[#applied + 1] = key
			end
		end
		if #applied == 0 then return false, "NO_FRAMES" end
	else
		local key = scopeKey
		local source = data.frames[key] or data.frames[normalize(key)]
		if not source and isBossUnit(key) then source = data.frames["boss1"] or data.frames["boss"] end
		if type(source) ~= "table" then return false, "SCOPE_MISSING" end
		target[key] = CopyTable(source)
		applied[#applied + 1] = key
	end

	table.sort(applied, function(a, b) return tostring(a) < tostring(b) end)
	UF.SyncEditModeLayoutAnchors(applied)
	addon.variables.requireReload = true
	return true, applied
end

function UF.ExportErrorMessage(reason)
	if reason == "NO_DATA" or reason == "EMPTY" then return L["UFExportProfileEmpty"] or "No unit frame settings to export." end
	if reason == "SCOPE_EMPTY" then return L["UFExportProfileScopeEmpty"] or "No saved settings for that frame yet." end
	return L["UFExportProfileFailed"] or "Could not create a Unit Frame export code."
end

function UF.ImportErrorMessage(reason)
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
	bossContainer:SetPoint(anchor.point or "CENTER", resolveRelativeAnchorFrame(anchor.relativeTo), anchor.relativePoint or anchor.point or "CENTER", anchor.x or 0, anchor.y or 0)
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

function AuraUtil.cacheTargetAura(aura, unit)
	if not aura or not aura.auraInstanceID then return end
	local id = aura.auraInstanceID
	local auras = AuraUtil.getAuraTables(unit)
	if not auras then return end
	local t = auras[id]
	if not t then
		t = {}
		auras[id] = t
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
	t.dispelName = aura.dispelName
	t.canActivePlayerDispel = aura.canActivePlayerDispel
end

function AuraUtil.cacheAura(cache, aura)
	if not (cache and aura and aura.auraInstanceID) then return end
	local id = aura.auraInstanceID
	local auras = cache.auras
	if not auras then return end
	local t = auras[id]
	if not t then
		t = {}
		auras[id] = t
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
	t.dispelName = aura.dispelName
	t.canActivePlayerDispel = aura.canActivePlayerDispel
end

function AuraUtil.addTargetAuraToOrder(auraInstanceID, unit)
	local _, order, indexById = AuraUtil.getAuraTables(unit)
	if not order or not indexById then return end
	if not auraInstanceID or indexById[auraInstanceID] then return end
	local idx = #order + 1
	order[idx] = auraInstanceID
	indexById[auraInstanceID] = idx
	return idx
end

function AuraUtil.addAuraToOrder(cache, auraInstanceID)
	if not (cache and auraInstanceID) then return nil end
	local order = cache.order
	local indexById = cache.indexById
	if not (order and indexById) then return nil end
	if indexById[auraInstanceID] then return indexById[auraInstanceID] end
	local idx = #order + 1
	order[idx] = auraInstanceID
	indexById[auraInstanceID] = idx
	return idx
end

function AuraUtil.reindexTargetAuraOrder(startIndex, unit)
	local _, order, indexById = AuraUtil.getAuraTables(unit)
	if not order or not indexById then return end
	for i = startIndex or 1, #order do
		indexById[order[i]] = i
	end
end

function AuraUtil.reindexAuraOrder(cache, startIndex)
	if not cache then return end
	local order = cache.order
	local indexById = cache.indexById
	if not (order and indexById) then return end
	for i = startIndex or 1, #order do
		indexById[order[i]] = i
	end
end

function AuraUtil.removeTargetAuraFromOrder(auraInstanceID, unit)
	local _, order, indexById = AuraUtil.getAuraTables(unit)
	if not order or not indexById then return nil end
	local idx = indexById[auraInstanceID]
	if not idx then return nil end
	table.remove(order, idx)
	indexById[auraInstanceID] = nil
	AuraUtil.reindexTargetAuraOrder(idx, unit)
	return idx
end

function AuraUtil.removeAuraFromOrder(cache, auraInstanceID)
	if not (cache and auraInstanceID) then return nil end
	local order = cache.order
	local indexById = cache.indexById
	if not (order and indexById) then return nil end
	local idx = indexById[auraInstanceID]
	if not idx then return nil end
	table.remove(order, idx)
	indexById[auraInstanceID] = nil
	AuraUtil.reindexAuraOrder(cache, idx)
	return idx
end

function AuraUtil.compactAuraOrderInPlace(order, indexById, auras)
	if not (order and indexById and auras) then return false end
	local write = 1
	local changed = false
	for read = 1, #order do
		local auraId = order[read]
		if auraId and auras[auraId] then
			if write ~= read then
				order[write] = auraId
				changed = true
			end
			if indexById[auraId] ~= write then indexById[auraId] = write end
			write = write + 1
		else
			if auraId and indexById[auraId] ~= nil then indexById[auraId] = nil end
			changed = true
		end
	end
	for i = write, #order do
		order[i] = nil
	end
	return changed
end

function AuraUtil.updateAuraCacheFromEvent(cache, unit, updateInfo, opts)
	if not (cache and unit and updateInfo) then return nil end
	local auras = cache.auras
	local order = cache.order
	local indexById = cache.indexById
	if not (auras and order and indexById) then return nil end
	local showHelpful = opts and opts.showHelpful
	local showHarmful = opts and opts.showHarmful
	local helpfulFilter = opts and opts.helpfulFilter
	local harmfulFilter = opts and opts.harmfulFilter
	local hidePermanent = opts and opts.hidePermanent
	local trackFirst = opts and opts.trackFirstChanged
	local maxCount = opts and opts.maxCount
	local firstChanged

	if updateInfo.addedAuras then
		for _, aura in ipairs(updateInfo.addedAuras) do
			if aura and aura.auraInstanceID then
				if hidePermanent and not C_Secrets.ShouldAurasBeSecret() and AuraUtil.isPermanentAura(aura, unit) then
					if auras[aura.auraInstanceID] then
						auras[aura.auraInstanceID] = nil
						local idx = AuraUtil.removeAuraFromOrder(cache, aura.auraInstanceID)
						if trackFirst and idx and maxCount and idx <= (maxCount + 1) then
							if not firstChanged or idx < firstChanged then firstChanged = idx end
						end
					end
				elseif showHarmful and harmfulFilter and not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, aura.auraInstanceID, harmfulFilter) then
					AuraUtil.cacheAura(cache, aura)
					local idx = AuraUtil.addAuraToOrder(cache, aura.auraInstanceID)
					if trackFirst and idx and maxCount and idx <= maxCount then
						if not firstChanged or idx < firstChanged then firstChanged = idx end
					end
				elseif showHelpful and helpfulFilter and not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, aura.auraInstanceID, helpfulFilter) then
					AuraUtil.cacheAura(cache, aura)
					local idx = AuraUtil.addAuraToOrder(cache, aura.auraInstanceID)
					if trackFirst and idx and maxCount and idx <= maxCount then
						if not firstChanged or idx < firstChanged then firstChanged = idx end
					end
				end
			end
		end
	end

	if updateInfo.updatedAuraInstanceIDs and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
		for _, inst in ipairs(updateInfo.updatedAuraInstanceIDs) do
			if auras[inst] then
				local data = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, inst)
				if data then AuraUtil.cacheAura(cache, data) end
			end
			if trackFirst then
				local idx = indexById[inst]
				if idx and maxCount and idx <= maxCount then
					if not firstChanged or idx < firstChanged then firstChanged = idx end
				end
			end
		end
	end

	if updateInfo.removedAuraInstanceIDs then
		for _, inst in ipairs(updateInfo.removedAuraInstanceIDs) do
			auras[inst] = nil
			local idx = AuraUtil.removeAuraFromOrder(cache, inst)
			if trackFirst and idx and maxCount and idx <= (maxCount + 1) then
				if not firstChanged or idx < firstChanged then firstChanged = idx end
			end
		end
	end

	return firstChanged
end

function AuraUtil.isPermanentAura(aura, unitToken)
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

function AuraUtil.ensureAuraButton(container, icons, index, ac)
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
		btn.drText = btn.overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		btn.drText:SetPoint("TOPLEFT", btn.overlay, "TOPLEFT", 2, -2)
		btn.drText:SetDrawLayer("OVERLAY", 2)
		btn.drText:Hide()
		btn.border = btn.overlay:CreateTexture(nil, "OVERLAY")
		btn.border:SetAllPoints(btn)
		btn.border:SetDrawLayer("OVERLAY", 1)
		btn.dispelIcon = btn.overlay:CreateTexture(nil, "OVERLAY")
		btn.dispelIcon:SetTexture("Interface\\Icons\\Spell_Holy_DispelMagic")
		btn.dispelIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		btn.dispelIcon:SetDrawLayer("OVERLAY", 1)
		btn.dispelIcon:Hide()
		btn.cd:SetReverse(true)
		btn.cd:SetDrawEdge(true)
		btn.cd:SetDrawSwipe(true)
		btn:SetScript("OnEnter", function(self)
			if not self._showTooltip then return end
			local tooltip = GameTooltip
			if not tooltip or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
			local unitToken = self.unitToken
			local auraInstanceID = self.auraInstanceID
			if not unitToken or not auraInstanceID then return end
			if type(auraInstanceID) ~= "number" or auraInstanceID <= 0 then return end
			tooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
			if self.isDebuff then
				if tooltip.SetUnitDebuffByAuraInstanceID then
					tooltip:SetUnitDebuffByAuraInstanceID(unitToken, auraInstanceID)
					tooltip:Show()
				end
			else
				if tooltip.SetUnitBuffByAuraInstanceID then
					tooltip:SetUnitBuffByAuraInstanceID(unitToken, auraInstanceID)
					tooltip:Show()
				end
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
		if btn.overlay and btn.border and btn.border:GetParent() ~= btn.overlay then
			btn.border:SetParent(btn.overlay)
			btn.border:SetDrawLayer("OVERLAY", 1)
		end
		if not btn.drText then
			local parent = btn.overlay or btn
			btn.drText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			btn.drText:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -2)
			btn.drText:SetDrawLayer("OVERLAY", 2)
			btn.drText:Hide()
		end
		if btn.overlay and btn.dispelIcon and btn.dispelIcon:GetParent() ~= btn.overlay then
			btn.dispelIcon:SetParent(btn.overlay)
			btn.dispelIcon:SetDrawLayer("OVERLAY", 1)
		end
	end

	if MSQgroup then btn._eqolMasqueRegions = btn._eqolMasqueRegions or {
		Icon = btn.icon,
		Cooldown = btn.cd,
		Border = btn.border,
	} end

	return btn, icons
end

local function syncAuraMasqueButton(btn, isDebuff)
	if not (MSQgroup and btn) then return end
	btn._eqolMasqueRegions = btn._eqolMasqueRegions or {
		Icon = btn.icon,
		Cooldown = btn.cd,
		Border = btn.border,
	}
	local desiredType = (isDebuff == true) and "Debuff" or "Buff"
	if btn._eqolMasqueType ~= desiredType then
		MSQgroup:AddButton(btn, btn._eqolMasqueRegions, desiredType, true)
		btn._eqolMasqueType = desiredType
	end
end

function AuraUtil.styleAuraCount(btn, ac, countFontSizeOverride)
	if not btn or not btn.count then return end
	ac = ac or {}
	local anchor = ac.countAnchor or "BOTTOMRIGHT"
	local off = ac.countOffset
	local ox, oy
	if off then
		ox = off.x or 0
		oy = off.y or 0
	else
		ox = -2
		oy = 2
	end
	local size = countFontSizeOverride
	if size == nil then size = ac.countFontSize end
	local flags = ac.countFontOutline
	local fontKey = ac.countFont or (addon.variables and addon.variables.defaultFont) or (LSM and LSM.DefaultMedia and LSM.DefaultMedia.font) or STANDARD_TEXT_FONT
	if
		btn._countStyleAnchor == anchor
		and btn._countStyleOx == ox
		and btn._countStyleOy == oy
		and btn._countStyleFontKey == fontKey
		and btn._countStyleSize == size
		and btn._countStyleFlags == flags
	then
		return
	end
	btn._countStyleAnchor = anchor
	btn._countStyleOx = ox
	btn._countStyleOy = oy
	btn._countStyleFontKey = fontKey
	btn._countStyleSize = size
	btn._countStyleFlags = flags
	btn.count:ClearAllPoints()
	btn.count:SetPoint(anchor, btn.overlay or btn, anchor, ox, oy)
	if size == nil or flags == nil then
		local _, curSize, curFlags = btn.count:GetFont()
		if size == nil then size = curSize or 14 end
		if flags == nil then flags = curFlags end
	end
	btn.count:SetFont(UFHelper.getFont(ac.countFont), size, flags)
end

function AuraUtil.styleAuraCooldownText(btn, ac, cooldownFontSizeOverride)
	if not btn or not btn.cd then return end
	ac = ac or {}
	local fs = btn._cooldownText or (btn.cd.GetCountdownFontString and btn.cd:GetCountdownFontString())
	if not fs then return end
	btn._cooldownText = fs
	local anchor = ac.cooldownAnchor or "CENTER"
	local off = ac.cooldownOffset
	local ox = (off and off.x) or 0
	local oy = (off and off.y) or 0
	local size = cooldownFontSizeOverride
	if size == nil then size = ac.cooldownFontSize end
	local fontKey = ac.cooldownFont
	local outline = ac.cooldownFontOutline
	local curFont, curSize, curFlags = fs:GetFont()
	if size == nil then size = curSize or 12 end
	if outline == nil then outline = curFlags end
	if fontKey == nil then fontKey = curFont end
	if
		btn._cooldownStyleAnchor == anchor
		and btn._cooldownStyleOx == ox
		and btn._cooldownStyleOy == oy
		and btn._cooldownStyleFontKey == fontKey
		and btn._cooldownStyleSize == size
		and btn._cooldownStyleOutline == outline
	then
		return
	end
	btn._cooldownStyleAnchor = anchor
	btn._cooldownStyleOx = ox
	btn._cooldownStyleOy = oy
	btn._cooldownStyleFontKey = fontKey
	btn._cooldownStyleSize = size
	btn._cooldownStyleOutline = outline
	fs:ClearAllPoints()
	fs:SetPoint(anchor, btn.overlay or btn, anchor, ox, oy)
	if UFHelper and UFHelper.applyFont then
		UFHelper.applyFont(fs, fontKey, size, outline)
	elseif UFHelper and UFHelper.applyCooldownTextStyle then
		UFHelper.applyCooldownTextStyle(btn.cd, size)
	end
end

function AuraUtil.styleAuraDRText(btn, ac, drFontSizeOverride)
	if not btn or not btn.drText then return end
	ac = ac or {}
	local anchor = ac.drAnchor or "TOPLEFT"
	local off = ac.drOffset
	local ox = (off and off.x) or 2
	local oy = (off and off.y) or -2
	local size = drFontSizeOverride
	if size == nil then size = ac.drFontSize end
	local flags = ac.drFontOutline
	local fontKey = ac.drFont or (addon.variables and addon.variables.defaultFont) or (LSM and LSM.DefaultMedia and LSM.DefaultMedia.font) or STANDARD_TEXT_FONT
	if btn._drStyleAnchor == anchor and btn._drStyleOx == ox and btn._drStyleOy == oy and btn._drStyleFontKey == fontKey and btn._drStyleSize == size and btn._drStyleFlags == flags then return end
	btn._drStyleAnchor = anchor
	btn._drStyleOx = ox
	btn._drStyleOy = oy
	btn._drStyleFontKey = fontKey
	btn._drStyleSize = size
	btn._drStyleFlags = flags
	btn.drText:ClearAllPoints()
	btn.drText:SetPoint(anchor, btn.overlay or btn, anchor, ox, oy)
	if size == nil or flags == nil then
		local _, curSize, curFlags = btn.drText:GetFont()
		if size == nil then size = curSize or 12 end
		if flags == nil then flags = curFlags end
	end
	btn.drText:SetFont(UFHelper.getFont(ac.drFont), size, flags)
end

function AuraUtil.applyAuraToButton(btn, aura, ac, isDebuff, unitToken)
	if not btn or not aura then return end
	unitToken = unitToken or "target"
	if issecretvalue and issecretvalue(isDebuff) then
		local _, harmfulFilter = AuraUtil.getAuraFilters(unitToken)
		isDebuff = not C_UnitAuras.IsAuraFilteredOutByInstanceID(unitToken, aura.auraInstanceID, harmfulFilter)
	end
	btn.spellId = aura.spellId
	btn.auraInstanceID = aura.auraInstanceID
	btn.unitToken = unitToken
	btn.isDebuff = isDebuff
	syncAuraMasqueButton(btn, isDebuff)
	btn._showTooltip = ac.showTooltip ~= false
	btn.icon:SetTexture(aura.icon or "")
	btn.cd:Clear()
	if issecretvalue and (issecretvalue(aura.duration) or issecretvalue(aura.expirationTime)) then
		btn.cd:SetCooldownFromExpirationTime(aura.expirationTime, aura.duration, aura.timeMod)
	elseif aura.duration and aura.duration > 0 and aura.expirationTime then
		btn.cd:SetCooldown(aura.expirationTime - aura.duration, aura.duration, aura.timeMod)
	end
	local showCooldown = ac.showCooldown ~= false
	if isDebuff then
		if ac.showCooldownDebuffs ~= nil then showCooldown = ac.showCooldownDebuffs end
	else
		if ac.showCooldownBuffs ~= nil then showCooldown = ac.showCooldownBuffs end
	end
	local showCooldownText = ac.showCooldownText
	if showCooldownText == nil then showCooldownText = showCooldown end
	if isDebuff then
		if ac.showCooldownTextDebuffs ~= nil then showCooldownText = ac.showCooldownTextDebuffs end
	else
		if ac.showCooldownTextBuffs ~= nil then showCooldownText = ac.showCooldownTextBuffs end
	end
	local cooldownFontSize = isDebuff and ac.cooldownFontSizeDebuff or ac.cooldownFontSizeBuff
	if cooldownFontSize ~= nil and cooldownFontSize < 1 then cooldownFontSize = nil end
	if cooldownFontSize == nil then cooldownFontSize = ac.cooldownFontSize end
	local countFontSize = isDebuff and ac.countFontSizeDebuff or ac.countFontSizeBuff
	if countFontSize == nil then countFontSize = ac.countFontSize end
	btn.cd:SetHideCountdownNumbers(showCooldownText == false)
	AuraUtil.styleAuraCount(btn, ac, countFontSize)
	AuraUtil.styleAuraCooldownText(btn, ac, cooldownFontSize)
	local showStacks = ac.showStacks
	if showStacks == nil then showStacks = true end
	if showStacks and (issecretvalue and issecretvalue(aura.applications) or aura.applications and aura.applications > 1) then
		local appStacks = aura.applications
		if not aura.isSample and C_UnitAuras.GetAuraApplicationDisplayCount then
			appStacks = C_UnitAuras.GetAuraApplicationDisplayCount(unitToken, aura.auraInstanceID, 2, 1000) -- TODO actual 4th param is required because otherwise it's always "*" this always get's the right stack shown
		end

		btn.count:SetText(appStacks)
		btn.count:Show()
	else
		btn.count:SetText("")
		btn.count:Hide()
	end
	local dispelR, dispelG, dispelB
	if btn.border then
		local useMasqueBorder = btn._eqolMasqueType ~= nil
		local borderKey = ac and ac.borderTexture
		local showBorder = isDebuff == true
		if not showBorder then
			local borderKeyName = borderKey and tostring(borderKey):upper() or "DEFAULT"
			showBorder = borderKeyName ~= "" and borderKeyName ~= "DEFAULT"
		end
		if showBorder then
			local r, g, b = 1, 0.25, 0.25
			local usedApiColor
			if not aura.isSample and aura.auraInstanceID and aura.auraInstanceID > 0 and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor and UFHelper and UFHelper.debuffColorCurve then
				local color = C_UnitAuras.GetAuraDispelTypeColor(unitToken, aura.auraInstanceID, UFHelper.debuffColorCurve)
				if color then
					usedApiColor = true
					if color.GetRGBA then
						r, g, b = color:GetRGBA()
					elseif color.r then
						r, g, b = color.r, color.g, color.b
					end
				end
			end
			if not usedApiColor then
				local fr, fg, fb
				if UFHelper and UFHelper.getDebuffColorFromName then
					local dispelName = aura.dispelName
					local canActivePlayerDispel = aura.canActivePlayerDispel
					if issecretvalue and issecretvalue(canActivePlayerDispel) then canActivePlayerDispel = nil end
					if (not dispelName or dispelName == "") and canActivePlayerDispel == true then dispelName = "Magic" end
					fr, fg, fb = UFHelper.getDebuffColorFromName(dispelName or "None")
				end
				if fr then
					r, g, b = fr, fg, fb
				end
			end
			if isDebuff then
				dispelR, dispelG, dispelB = r, g, b
			end
			if useMasqueBorder then
				if UFHelper and UFHelper.hideAuraBorderFrame then UFHelper.hideAuraBorderFrame(btn) end
				btn.border:SetVertexColor(r, g, b, 1)
				btn.border:Show()
			else
				local borderMode = tostring((ac and ac.borderRenderMode) or "EDGE"):upper()
				local useOverlayBorderMode = borderMode == "OVERLAY"
				local borderTex, borderCoords, borderIsEdge
				if UFHelper and UFHelper.resolveAuraBorderTexture then
					borderTex, borderCoords, borderIsEdge = UFHelper.resolveAuraBorderTexture(borderKey)
				else
					borderTex = "Interface\\Buttons\\UI-Debuff-Overlays"
					borderCoords = { 0.296875, 0.5703125, 0, 0.515625 }
					borderIsEdge = false
				end
				local renderAsEdge = borderIsEdge and not useOverlayBorderMode
				if renderAsEdge and borderTex and borderTex ~= "" then
					local borderFrame = UFHelper and UFHelper.ensureAuraBorderFrame and UFHelper.ensureAuraBorderFrame(btn)
					if borderFrame then
						local edgeSize = (UFHelper and UFHelper.calcAuraBorderSize and UFHelper.calcAuraBorderSize(btn, ac)) or 1
						local borderOffset = tonumber(ac and ac.borderOffset) or 0
						local edgeInset = (edgeSize or 1) * 0.5
						local anchorInset = edgeInset - borderOffset
						local insetVal = edgeSize
						if borderFrame._eqolAuraBorderTex ~= borderTex or borderFrame._eqolAuraBorderEdgeSize ~= edgeSize then
							borderFrame:SetBackdrop({
								bgFile = "Interface\\Buttons\\WHITE8x8",
								edgeFile = borderTex,
								edgeSize = edgeSize,
								insets = { left = insetVal, right = insetVal, top = insetVal, bottom = insetVal },
							})
							borderFrame:SetBackdropColor(0, 0, 0, 0)
							borderFrame._eqolAuraBorderTex = borderTex
							borderFrame._eqolAuraBorderEdgeSize = edgeSize
						end
						borderFrame:ClearAllPoints()
						borderFrame:SetPoint("TOPLEFT", btn, "TOPLEFT", anchorInset, -anchorInset)
						borderFrame:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -anchorInset, anchorInset)
						borderFrame._eqolAuraBorderInset = anchorInset
						borderFrame:SetBackdropBorderColor(r, g, b, 1)
						borderFrame:Show()
					end
					btn.border:Hide()
				else
					if UFHelper and UFHelper.hideAuraBorderFrame then UFHelper.hideAuraBorderFrame(btn) end
					btn.border:SetTexture(borderTex or "")
					local useOverlayBorderGeometry = useOverlayBorderMode and not borderCoords
					if borderCoords then
						btn.border:SetTexCoord(borderCoords[1], borderCoords[2], borderCoords[3], borderCoords[4])
					else
						btn.border:SetTexCoord(0, 1, 0, 1)
					end
					if useOverlayBorderGeometry then
						local bw = btn:GetWidth()
						local bh = btn:GetHeight()
						if not bw or bw <= 0 then bw = (ac and ac.size) or 24 end
						if not bh or bh <= 0 then bh = bw end
						btn.border:ClearAllPoints()
						btn.border:SetPoint("CENTER", btn, "CENTER", 0, 0)
						btn.border:SetSize((bw or 24) + 1, (bh or 24) + 1)
					else
						btn.border:SetAllPoints(btn)
					end
					btn.border:SetVertexColor(r, g, b, 1)
					btn.border:Show()
				end
			end
		else
			if UFHelper and UFHelper.hideAuraBorderFrame then UFHelper.hideAuraBorderFrame(btn) end
			if not useMasqueBorder then btn.border:SetTexture(nil) end
			btn.border:Hide()
		end
	end
	if btn.dispelIcon then
		local showIcon = isDebuff and ac and ac.blizzardDispelBorder == true
		if showIcon then
			local baseSize = btn:GetWidth()
			if not baseSize or baseSize <= 0 then baseSize = (ac and ac.size) or 0 end
			local iconSize = baseSize and baseSize > 0 and (baseSize * 0.4) or 12
			btn.dispelIcon:ClearAllPoints()
			btn.dispelIcon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
			btn.dispelIcon:SetSize(iconSize, iconSize)
			if dispelR then
				btn.dispelIcon:SetVertexColor(dispelR, dispelG, dispelB, 1)
			else
				btn.dispelIcon:SetVertexColor(1, 1, 1, 1)
			end
			local alphaOn = (ac and ac.blizzardDispelBorderAlpha) or 1
			local alphaOff = (ac and ac.blizzardDispelBorderAlphaNot) or 0
			btn.dispelIcon:SetAlphaFromBoolean(aura.canActivePlayerDispel, alphaOn, alphaOff)
			btn.dispelIcon:Show()
		else
			btn.dispelIcon:Hide()
		end
	end
	if btn.drText then
		local showDR = ac and ac.showDR == true
		if showDR then
			local points = aura.points
			if issecretvalue and issecretvalue(points) then points = nil end
			local drValue
			if type(points) == "table" then
				local v = points[1]
				if issecretvalue and issecretvalue(v) then v = nil end
				if type(v) == "number" then drValue = v end
			end
			if drValue ~= nil then
				local text = tostring(math.floor(drValue + 0.5)) .. "%"
				if btn._lastDRText ~= text then
					btn._lastDRText = text
					btn.drText:SetText(text)
				end
				AuraUtil.styleAuraDRText(btn, ac)
				local col = ac.drColor or { 1, 1, 1, 1 }
				btn.drText:SetTextColor(col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1)
				btn.drText:Show()
			else
				if btn._lastDRText ~= "" then
					btn._lastDRText = ""
					btn.drText:SetText("")
				end
				btn.drText:Hide()
			end
		else
			if btn._lastDRText ~= "" then
				btn._lastDRText = ""
				btn.drText:SetText("")
			end
			btn.drText:Hide()
		end
	end
	btn:Show()
end

UF._auraLayout = UF._auraLayout or {}
local GROW_DIRS = { "UP", "DOWN", "LEFT", "RIGHT" }

function UF._auraLayout.parseGrowth(growth)
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

function UF._auraLayout.resolveGrowth(ac, fallbackAnchor, growthOverride)
	local anchor = fallbackAnchor or (ac and ac.anchor) or "BOTTOM"
	local fallback
	if anchor == "TOP" then
		fallback = "RIGHTUP"
	elseif anchor == "LEFT" then
		fallback = "LEFTDOWN"
	else
		fallback = "RIGHTDOWN"
	end
	local primary, secondary = UF._auraLayout.parseGrowth(growthOverride or (ac and ac.growth))
	if not primary then
		primary, secondary = UF._auraLayout.parseGrowth(fallback)
	end
	return primary, secondary
end

function UF._auraLayout.defaultOffset(anchor)
	if anchor == "TOP" then return 0, 5 end
	if anchor == "LEFT" then return -5, 0 end
	if anchor == "RIGHT" then return 5, 0 end
	return 0, -5
end

function UF._auraLayout.positionContainer(container, anchor, barGroup, ax, ay, barAreaOffsetLeft, barAreaOffsetRight)
	if not container or not barGroup then return end
	if anchor == "TOP" then
		container:SetPoint("BOTTOMLEFT", barGroup, "TOPLEFT", (ax or 0) + (barAreaOffsetLeft or 0), ay or 0)
	elseif anchor == "LEFT" then
		container:SetPoint("TOPRIGHT", barGroup, "TOPLEFT", (ax or 0) + (barAreaOffsetLeft or 0), ay or 0)
	elseif anchor == "RIGHT" then
		container:SetPoint("TOPLEFT", barGroup, "TOPRIGHT", (ax or 0) - (barAreaOffsetRight or 0), ay or 0)
	else
		container:SetPoint("TOPLEFT", barGroup, "BOTTOMLEFT", (ax or 0) + (barAreaOffsetLeft or 0), ay or 0)
	end
end

function AuraUtil.anchorAuraButton(btn, container, index, ac, perRow, primary, secondary)
	if not btn or not container then return end
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
	local xSign = horizontalDir == "RIGHT" and 1 or -1
	local ySign = verticalDir == "UP" and 1 or -1
	local basePoint = (ySign == 1 and "BOTTOM" or "TOP") .. (xSign == 1 and "LEFT" or "RIGHT")
	local x = col * (ac.size + ac.padding) * xSign
	local y = row * (ac.size + ac.padding) * ySign
	if btn._eqolAuraAnchorContainer == container and btn._eqolAuraAnchorPoint == basePoint and btn._eqolAuraAnchorX == x and btn._eqolAuraAnchorY == y then return end
	btn._eqolAuraAnchorContainer = container
	btn._eqolAuraAnchorPoint = basePoint
	btn._eqolAuraAnchorX = x
	btn._eqolAuraAnchorY = y
	btn:ClearAllPoints()
	btn:SetPoint(basePoint, container, basePoint, x, y)
end

function AuraUtil.updateAuraContainerSize(container, shown, ac, perRow, primary)
	if not container then return end
	perRow = perRow or 1
	if perRow < 1 then perRow = 1 end
	local primaryVertical = primary == "UP" or primary == "DOWN"
	local rows
	if primaryVertical then
		rows = math.min(shown, perRow)
	else
		rows = math.ceil(shown / perRow)
	end
	local height = rows > 0 and (rows * (ac.size + ac.padding) - ac.padding) or 0.001
	if container._eqolAuraHeight ~= height then
		container:SetHeight(height)
		container._eqolAuraHeight = height
	end
	local shownFlag = shown > 0
	if container._eqolAuraShown ~= shownFlag then
		container:SetShown(shownFlag)
		container._eqolAuraShown = shownFlag
	end
end

function UF._auraLayout.calcPerRow(st, ac, width, primary)
	local size = (ac.size or 24) + (ac.padding or 0)
	if size <= 0 then return 1 end
	local override = ac and tonumber(ac.perRow)
	if override and override > 0 then return math.max(1, math.floor(override + 0.5)) end
	local available = width or 0
	if primary == "UP" or primary == "DOWN" then
		local height = (st and st.barGroup and st.barGroup:GetHeight()) or (st and st.frame and st.frame:GetHeight()) or 0
		if height and height > 0 then available = height end
	end
	if available <= 0 then return 1 end
	return math.max(1, math.floor((available + (ac.padding or 0)) / size))
end

function AuraUtil.hideAuraContainers(st)
	st = st or states.target
	if not st then return end
	if st.auraButtons then
		for i = 1, #st.auraButtons do
			local btn = st.auraButtons[i]
			if btn then btn:Hide() end
		end
	end
	if st.debuffButtons then
		for i = 1, #st.debuffButtons do
			local btn = st.debuffButtons[i]
			if btn then btn:Hide() end
		end
	end
	if st.auraContainer then
		st.auraContainer:SetHeight(0.001)
		st.auraContainer:SetShown(false)
	end
	if st.debuffContainer then
		st.debuffContainer:SetHeight(0.001)
		st.debuffContainer:SetShown(false)
	end
end

function AuraUtil.fillSampleAuras(unit, ac, hidePermanent)
	local auras, order, indexById = AuraUtil.getAuraTables(unit)
	if not auras or not order or not indexById then return end
	local maxCount = ac and ac.max or 16
	if not maxCount or maxCount < 1 then maxCount = 1 end
	local showBuffs = ac and ac.showBuffs ~= false
	local showDebuffs = ac and ac.showDebuffs ~= false
	if not showBuffs and not showDebuffs then return end
	local separateDebuffs = ac and ac.separateDebuffAnchor == true
	local debuffCount
	local buffCount
	if showBuffs and showDebuffs then
		debuffCount = separateDebuffs and math.floor(maxCount * 0.4) or math.floor(maxCount * 0.3)
		if maxCount > 1 and debuffCount < 1 then debuffCount = 1 end
		if debuffCount >= maxCount then debuffCount = maxCount - 1 end
		if debuffCount < 0 then debuffCount = 0 end
		buffCount = maxCount - debuffCount
	elseif showDebuffs then
		debuffCount = maxCount
		buffCount = 0
	else
		debuffCount = 0
		buffCount = maxCount
	end
	local now = GetTime and GetTime() or 0
	local base = unit == UNIT.PLAYER and -100000 or (unit == UNIT.TARGET or unit == "target") and -200000 or -300000

	local function addSampleAura(isDebuff, idx)
		local duration
		if idx % 3 == 0 then
			duration = 120
		elseif idx % 3 == 1 then
			duration = 30
		else
			duration = 0
		end
		if hidePermanent and duration <= 0 then duration = 45 end
		local expiration = duration > 0 and (now + duration) or nil
		local stacks
		if idx % 5 == 0 then
			stacks = 5
		elseif idx % 3 == 0 then
			stacks = 3
		end
		local iconList = isDebuff and SAMPLE_DEBUFF_ICONS or SAMPLE_BUFF_ICONS
		local icon = iconList[((idx - 1) % #iconList) + 1]
		local dispelName = isDebuff and SAMPLE_DISPEL_TYPES[((idx - 1) % #SAMPLE_DISPEL_TYPES) + 1] or nil
		local canActivePlayerDispel = dispelName == "Magic"
		local auraId = base - idx
		auras[auraId] = {
			auraInstanceID = auraId,
			icon = icon,
			isHelpful = not isDebuff,
			isHarmful = isDebuff,
			applications = stacks,
			duration = duration,
			expirationTime = expiration,
			dispelName = dispelName,
			canActivePlayerDispel = canActivePlayerDispel,
			isSample = true,
		}
		order[#order + 1] = auraId
		indexById[auraId] = #order
	end

	local idx = 0
	for i = 1, debuffCount do
		idx = idx + 1
		addSampleAura(true, idx)
	end
	for i = 1, buffCount do
		idx = idx + 1
		addSampleAura(false, idx)
	end
end

function AuraUtil.updateTargetAuraIcons(startIndex, unit)
	unit = unit or "target"
	local st = states[unit]
	if not st or not st.auraContainer or not st.frame then return end
	local cfg = st.cfg or ensureDB(unit)
	local def = defaultsFor(unit)
	local ac = cfg.auraIcons or (def and def.auraIcons) or defaults.target.auraIcons or { size = 24, padding = 2, max = 16, showCooldown = true }
	if not AuraUtil.isAuraIconsEnabled(ac, def) then
		AuraUtil.hideAuraContainers(st)
		return
	end
	ac.size = ac.size or 24
	ac.padding = ac.padding or 0
	ac.max = ac.max or 16
	if ac.showTooltip == nil then ac.showTooltip = true end
	if ac.cooldownFontSize == nil or ac.cooldownFontSize < 1 then ac.cooldownFontSize = 12 end
	if ac.max < 1 then ac.max = 1 end
	local showBuffs = ac.showBuffs ~= false
	local showDebuffs = ac.showDebuffs ~= false
	if not showBuffs and not showDebuffs then
		AuraUtil.hideAuraContainers(st)
		return
	end
	local buffSize = ac.size
	local debuffSize = ac.debuffSize or buffSize
	local padding = ac.padding or 0
	local buffLayout = st._auraBuffLayout
	if not buffLayout then
		buffLayout = {}
		st._auraBuffLayout = buffLayout
	end
	buffLayout.size = buffSize
	buffLayout.padding = padding
	buffLayout.perRow = ac.perRow
	local debuffLayout = buffLayout
	if debuffSize ~= buffSize then
		debuffLayout = st._auraDebuffLayout
		if not debuffLayout then
			debuffLayout = {}
			st._auraDebuffLayout = debuffLayout
		end
		debuffLayout.size = debuffSize
		debuffLayout.padding = padding
		debuffLayout.perRow = ac.perRow
	end
	local combinedLayout = buffLayout
	if debuffSize > buffSize then combinedLayout = debuffLayout end
	if showBuffs and not showDebuffs then combinedLayout = buffLayout end
	if showDebuffs and not showBuffs then combinedLayout = debuffLayout end
	local auras, order, indexById = AuraUtil.getAuraTables(unit)
	if not auras or not order or not indexById then return end
	local _, harmfulFilter = AuraUtil.getAuraFilters(unit)
	local function isAuraDebuff(aura)
		if issecretvalue and issecretvalue(aura.isHarmful) and C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID then
			return not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, aura.auraInstanceID, harmfulFilter)
		end
		return aura.isHarmful == true
	end
	AuraUtil.compactAuraOrderInPlace(order, indexById, auras)
	local visibleIds = st._auraVisibleIds
	if not visibleIds then
		visibleIds = {}
		st._auraVisibleIds = visibleIds
	end
	local visibleIsDebuff = st._auraVisibleIsDebuff
	if not visibleIsDebuff then
		visibleIsDebuff = {}
		st._auraVisibleIsDebuff = visibleIsDebuff
	end
	local visibleCount = 0
	for i = 1, #order do
		local auraId = order[i]
		local aura = auras[auraId]
		if aura then
			local isDebuff = isAuraDebuff(aura)
			if (isDebuff and showDebuffs) or (not isDebuff and showBuffs) then
				visibleCount = visibleCount + 1
				visibleIds[visibleCount] = auraId
				visibleIsDebuff[visibleCount] = isDebuff == true
				if visibleCount >= ac.max then break end
			end
		end
	end
	local oldVisibleCount = st._auraVisibleCount or 0
	if oldVisibleCount > visibleCount then
		for i = visibleCount + 1, oldVisibleCount do
			visibleIds[i] = nil
			visibleIsDebuff[i] = nil
		end
	end
	st._auraVisibleCount = visibleCount

	local width = (st.auraContainer and st.auraContainer:GetWidth()) or (st.barGroup and st.barGroup:GetWidth()) or (st.frame and st.frame:GetWidth()) or 0
	local useSeparateDebuffs = ac.separateDebuffAnchor == true
	if useSeparateDebuffs and not st.debuffContainer then useSeparateDebuffs = false end
	local auraLayout = UF._auraLayout
	local buffPrimary, buffSecondary = auraLayout.resolveGrowth(ac, ac.anchor)
	local perRow = auraLayout.calcPerRow(st, buffLayout, width, buffPrimary)
	local perRowCombined = auraLayout.calcPerRow(st, combinedLayout, width, buffPrimary)

	-- Combined layout (default, backward compatible)
	if not useSeparateDebuffs then
		local icons = st.auraButtons or {}
		st.auraButtons = icons
		local shown = visibleCount
		startIndex = startIndex or 1
		if startIndex < 1 then startIndex = 1 end

		for i = startIndex, shown do
			local auraId = visibleIds[i]
			local aura = auraId and auras[auraId]
			if aura then
				local isDebuff = visibleIsDebuff[i] == true
				local layout = isDebuff and debuffLayout or buffLayout
				local btn
				btn, st.auraButtons = AuraUtil.ensureAuraButton(st.auraContainer, st.auraButtons, i, layout)
				AuraUtil.applyAuraToButton(btn, aura, ac, isDebuff, unit)
				AuraUtil.anchorAuraButton(btn, st.auraContainer, i, combinedLayout, perRowCombined, buffPrimary, buffSecondary)
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
		AuraUtil.updateAuraContainerSize(st.auraContainer, shown, combinedLayout, perRowCombined, buffPrimary)
		return
	end

	-- Separate buff/debuff anchors
	local buffButtons = st.auraButtons or {}
	local debuffButtons = st.debuffButtons or {}
	local buffCount = 0
	local debuffCount = 0
	local shownTotal = 0
	local debAnchor = ac.debuffAnchor or ac.anchor or "BOTTOM"
	local debPrimary, debSecondary = auraLayout.resolveGrowth(ac, debAnchor, ac.debuffGrowth)
	local perRowDebuff = auraLayout.calcPerRow(st, debuffLayout, width, debPrimary)
	for i = 1, visibleCount do
		if shownTotal >= ac.max then break end
		local auraId = visibleIds[i]
		local aura = auraId and auras[auraId]
		if aura then
			shownTotal = shownTotal + 1
			if visibleIsDebuff[i] == true then
				debuffCount = debuffCount + 1
				local btn
				btn, debuffButtons = AuraUtil.ensureAuraButton(st.debuffContainer, debuffButtons, debuffCount, debuffLayout)
				AuraUtil.applyAuraToButton(btn, aura, ac, true, unit)
				AuraUtil.anchorAuraButton(btn, st.debuffContainer, debuffCount, debuffLayout, perRowDebuff, debPrimary, debSecondary)
			else
				buffCount = buffCount + 1
				local btn
				btn, buffButtons = AuraUtil.ensureAuraButton(st.auraContainer, buffButtons, buffCount, buffLayout)
				AuraUtil.applyAuraToButton(btn, aura, ac, false, unit)
				AuraUtil.anchorAuraButton(btn, st.auraContainer, buffCount, buffLayout, perRow, buffPrimary, buffSecondary)
			end
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

	AuraUtil.updateAuraContainerSize(st.auraContainer, math.min(buffCount, ac.max), buffLayout, perRow, buffPrimary)
	AuraUtil.updateAuraContainerSize(st.debuffContainer, math.min(debuffCount, ac.max), debuffLayout, perRowDebuff, debPrimary)
end

function AuraUtil.normalizeAuraQueryLimit(value)
	value = math.floor(tonumber(value) or 0)
	if value < 1 then return nil end
	return value
end

function AuraUtil.getTargetAuraQueryLimits(ac, showBuffs, showDebuffs)
	local maxCount = AuraUtil.normalizeAuraQueryLimit(ac and ac.max) or 16
	local buffLimit
	local debuffLimit

	if showBuffs and showDebuffs and ac and ac.separateDebuffAnchor == true then
		local debuffCount = math.floor(maxCount * 0.4)
		if maxCount > 1 and debuffCount < 1 then debuffCount = 1 end
		if debuffCount >= maxCount then debuffCount = maxCount - 1 end
		if debuffCount < 0 then debuffCount = 0 end
		local buffCount = maxCount - debuffCount
		buffLimit = AuraUtil.normalizeAuraQueryLimit(buffCount + 1)
		debuffLimit = AuraUtil.normalizeAuraQueryLimit(debuffCount + 1)
	else
		local cap = maxCount + 1
		buffLimit = showBuffs and cap or nil
		debuffLimit = showDebuffs and cap or nil
	end

	return buffLimit, debuffLimit
end

function AuraUtil.scanTargetAuraSlots(unit, filter, queryLimit, hidePermanent)
	if not (unit and filter and C_UnitAuras and C_UnitAuras.GetAuraSlots and C_UnitAuras.GetAuraDataBySlot) then return end
	local slots
	if queryLimit then
		slots = { C_UnitAuras.GetAuraSlots(unit, filter, queryLimit) }
	else
		slots = { C_UnitAuras.GetAuraSlots(unit, filter) }
	end
	for i = 2, #slots do
		local aura = C_UnitAuras.GetAuraDataBySlot(unit, slots[i])
		if aura and (not hidePermanent or not AuraUtil.isPermanentAura(aura, unit)) then
			AuraUtil.cacheTargetAura(aura, unit)
			AuraUtil.addTargetAuraToOrder(aura.auraInstanceID, unit)
		end
	end
end

function AuraUtil.fullScanTargetAuras(unit)
	unit = unit or "target"
	AuraUtil.resetTargetAuras(unit)
	local st = states[unit]
	local cfg = (st and st.cfg) or ensureDB(unit)
	local def = defaultsFor(unit)
	local ac = cfg.auraIcons or (def and def.auraIcons) or defaults.target.auraIcons or {}
	if not AuraUtil.isAuraIconsEnabled(ac, def) then
		if st then st._sampleAurasActive = nil end
		AuraUtil.updateTargetAuraIcons(nil, unit)
		return
	end
	local showBuffs = ac.showBuffs ~= false
	local showDebuffs = ac.showDebuffs ~= false
	if not showBuffs and not showDebuffs then
		AuraUtil.updateTargetAuraIcons(nil, unit)
		return
	end
	if addon.EditModeLib and addon.EditModeLib:IsInEditMode() then
		local hidePermanent = ac.hidePermanentAuras == true or ac.hidePermanent == true
		if st then st._sampleAurasActive = true end
		AuraUtil.fillSampleAuras(unit, ac, hidePermanent)
		AuraUtil.updateTargetAuraIcons(nil, unit)
		return
	end
	if st then st._sampleAurasActive = nil end
	if not UnitExists or not UnitExists(unit) then
		AuraUtil.updateTargetAuraIcons(nil, unit)
		return
	end
	local helpfulFilter, harmfulFilter = AuraUtil.getAuraFilters(unit)
	local hidePermanent = ac.hidePermanentAuras == true or ac.hidePermanent == true
	local helpfulLimit, harmfulLimit = AuraUtil.getTargetAuraQueryLimits(ac, showBuffs, showDebuffs)
	if showBuffs then AuraUtil.scanTargetAuraSlots(unit, helpfulFilter, helpfulLimit, hidePermanent) end
	if showDebuffs then AuraUtil.scanTargetAuraSlots(unit, harmfulFilter, harmfulLimit, hidePermanent) end
	AuraUtil.updateTargetAuraIcons(nil, unit)
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
local function getFrameInfo(frameName)
	if not addon.variables or not addon.variables.unitFrameNames then return nil end
	for _, info in ipairs(addon.variables.unitFrameNames) do
		if info.name == frameName then return info end
	end
	return nil
end

local function shouldHideInVehicle(cfg, def)
	local value = cfg and cfg.hideInVehicle
	if value == nil then value = def and def.hideInVehicle end
	return value == true
end

local function shouldHideInPetBattle(cfg, def)
	local value = cfg and cfg.hideInPetBattle
	if value == nil then value = def and def.hideInPetBattle end
	return value == true
end

local function applyVisibilityDriver(unit, enabled)
	local st = states[unit]
	if not st or not st.frame then return end
	local cfg = ensureDB(unit)
	local def = defaultsFor(unit)
	local inEdit = addon.EditModeLib and addon.EditModeLib.IsInEditMode and addon.EditModeLib:IsInEditMode()
	local hideInClientScene = UFHelper and UFHelper.shouldHideInClientScene and UFHelper.shouldHideInClientScene(cfg, def)
	local forceClientSceneHide = enabled and not inEdit and hideInClientScene and UF._clientSceneActive == true
	if UFHelper and UFHelper.applyClientSceneAlphaOverride then UFHelper.applyClientSceneAlphaOverride(st, forceClientSceneHide) end
	if InCombatLockdown() then return end
	if not RegisterStateDriver then return end
	local hideInVehicle = enabled and shouldHideInVehicle(cfg, def)
	local hideInPetBattle = enabled and unit ~= UNIT.PLAYER and shouldHideInPetBattle(cfg, def)
	local cond
	local baseCond
	if not enabled then
		cond = "hide"
	elseif unit == UNIT.TARGET then
		baseCond = "[@target,exists] show; hide"
	elseif unit == UNIT.TARGET_TARGET then
		baseCond = "[@targettarget,exists] show; hide"
	elseif unit == UNIT.FOCUS then
		baseCond = "[@focus,exists] show; hide"
	elseif unit == UNIT.PET then
		baseCond = "[@pet,exists] show; hide"
	elseif isBossUnit(unit) then
		baseCond = ("[@%s,exists] show; hide"):format(unit)
	end
	if enabled then
		if hideInPetBattle or hideInVehicle or baseCond then
			local clauses = {}
			if hideInPetBattle then clauses[#clauses + 1] = "[petbattle] hide" end
			if hideInVehicle then clauses[#clauses + 1] = "[vehicleui] hide" end
			clauses[#clauses + 1] = baseCond or "show"
			cond = table.concat(clauses, "; ")
		end
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
	local def = defaultsFor(unit)
	local inEdit = addon.EditModeLib and addon.EditModeLib.IsInEditMode and addon.EditModeLib:IsInEditMode()
	local useConfig = (not inEdit and cfg and cfg.enabled) and normalizeVisibilityConfig(cfg.visibility) or nil
	local hideInClientScene = UFHelper and UFHelper.shouldHideInClientScene and UFHelper.shouldHideInClientScene(cfg, def)
	local forceClientSceneHide = not inEdit and cfg and cfg.enabled and hideInClientScene and UF._clientSceneActive == true
	local fadeAlpha = nil
	if not inEdit and cfg and type(cfg.visibilityFade) == "number" then
		fadeAlpha = cfg.visibilityFade
		if fadeAlpha < 0 then fadeAlpha = 0 end
		if fadeAlpha > 1 then fadeAlpha = 1 end
	end
	local opts = { noStateDriver = true, fadeAlpha = fadeAlpha }
	if unit == "boss" then
		for i = 1, maxBossFrames do
			local info = UNITS["boss" .. i]
			if info and info.frameName then ApplyFrameVisibilityConfig(info.frameName, { unitToken = "boss" }, useConfig, opts) end
			if UFHelper and UFHelper.applyClientSceneAlphaOverride then UFHelper.applyClientSceneAlphaOverride(states["boss" .. i], forceClientSceneHide) end
		end
		return
	end
	local info = UNITS[unit]
	if info and info.frameName then ApplyFrameVisibilityConfig(info.frameName, { unitToken = info.unit }, useConfig, opts) end
	if UFHelper and UFHelper.applyClientSceneAlphaOverride then UFHelper.applyClientSceneAlphaOverride(states[unit], forceClientSceneHide) end
end

local function applyVisibilityRulesAll()
	applyVisibilityRules("player")
	applyVisibilityRules("target")
	applyVisibilityRules(UNIT.TARGET_TARGET)
	applyVisibilityRules("focus")
	applyVisibilityRules("pet")
	applyVisibilityRules("boss")
end

function UF.RefreshClientSceneVisibility()
	applyVisibilityDriver(UNIT.PLAYER, ensureDB(UNIT.PLAYER).enabled)
	applyVisibilityDriver(UNIT.TARGET, ensureDB(UNIT.TARGET).enabled)
	applyVisibilityDriver(UNIT.TARGET_TARGET, ensureDB(UNIT.TARGET_TARGET).enabled)
	applyVisibilityDriver(UNIT.FOCUS, ensureDB(UNIT.FOCUS).enabled)
	applyVisibilityDriver(UNIT.PET, ensureDB(UNIT.PET).enabled)
	local bossEnabled = ensureDB("boss").enabled
	for i = 1, maxBossFrames do
		applyVisibilityDriver("boss" .. i, bossEnabled)
	end
	applyVisibilityRulesAll()
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
		enabled = true,
		size = 24,
		debuffSize = nil,
		padding = 2,
		max = 16,
		perRow = 0,
		showCooldown = true,
		showCooldownBuffs = nil,
		showCooldownDebuffs = nil,
		showTooltip = true,
		hidePermanentAuras = false,
		blizzardDispelBorder = false,
		blizzardDispelBorderAlpha = 1,
		blizzardDispelBorderAlphaNot = 0,
		borderTexture = "DEFAULT",
		borderRenderMode = "EDGE",
		borderSize = nil,
		borderOffset = 0,
		anchor = "BOTTOM",
		offset = { x = 0, y = -5 },
		growth = nil,
		separateDebuffAnchor = false,
		debuffAnchor = nil,
		debuffOffset = nil,
		debuffGrowth = nil,
		countAnchor = "BOTTOMRIGHT",
		countOffset = { x = -2, y = 2 },
		countFontSize = nil,
		countFontSizeBuff = nil,
		countFontSizeDebuff = nil,
		countFontOutline = nil,
		cooldownFontSize = 12,
		cooldownFontSizeBuff = nil,
		cooldownFontSizeDebuff = nil,
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
	petDefaults.health.healAbsorbUseCustomColor = false
	petDefaults.health.showSampleHealAbsorb = false
	if petDefaults.status and petDefaults.status.combatIndicator then petDefaults.status.combatIndicator.enabled = false end
	defaults.pet = petDefaults

	local bossDefaults = CopyTable(defaults.target)
	bossDefaults.enabled = false
	bossDefaults.anchor = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 400, y = 200 }
	bossDefaults.width = 220
	bossDefaults.healthHeight = 20
	bossDefaults.powerHeight = 10
	bossDefaults.statusHeight = 16
	bossDefaults.spacing = 4
	bossDefaults.growth = "DOWN"
	bossDefaults.health.useClassColor = false
	bossDefaults.health.useCustomColor = false
	bossDefaults.health.useAbsorbGlow = false
	bossDefaults.health.showSampleAbsorb = false
	bossDefaults.health.absorbUseCustomColor = false
	bossDefaults.health.healAbsorbUseCustomColor = false
	bossDefaults.health.showSampleHealAbsorb = false
	if bossDefaults.auraIcons then bossDefaults.auraIcons.enabled = false end
	if bossDefaults.status then bossDefaults.status.nameColorMode = "CUSTOM" end
	defaults.boss = bossDefaults
end

if not defaults.player.auraIcons and defaults.target and defaults.target.auraIcons then
	defaults.player.auraIcons = CopyTable(defaults.target.auraIcons)
	defaults.player.auraIcons.enabled = false
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

local BAR_BACKDROP_STYLE = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = nil,
	tile = false,
}

local function unpackColor(color, defaultR, defaultG, defaultB, defaultA)
	if type(color) ~= "table" then return defaultR, defaultG, defaultB, defaultA end
	return color[1] or color.r or defaultR, color[2] or color.g or defaultG, color[3] or color.b or defaultB, color[4] or color.a or defaultA
end

UF._isFrameBorderEnabled = UF._isFrameBorderEnabled
	or function(borderCfg, borderDef, fallback)
		if borderCfg == true then return true end
		if borderCfg == false then return false end

		local enabled
		if type(borderCfg) == "table" then enabled = borderCfg.enabled end

		if enabled == nil and type(borderDef) == "table" then enabled = borderDef.enabled end
		if enabled == nil then enabled = fallback end
		if enabled == nil then enabled = true end
		return enabled == true
	end

local function setBackdrop(frame, borderCfg, borderDef, fallbackEnabled)
	if not frame then return end
	if frame.SetBackdrop and not frame._ufBackdropCleared then
		frame:SetBackdrop(nil)
		frame._ufBackdropCleared = true
	end
	if UF._isFrameBorderEnabled(borderCfg, borderDef, fallbackEnabled) then
		if type(borderCfg) ~= "table" then borderCfg = {} end
		local borderFrame = ensureBorderFrame(frame)
		if not borderFrame then return end
		local colorR, colorG, colorB, colorA = unpackColor(borderCfg.color or (borderDef and borderDef.color), 0, 0, 0, 0.8)
		local edgeSize = tonumber(borderCfg.edgeSize) or 1
		if edgeSize <= 0 and borderDef then edgeSize = tonumber(borderDef.edgeSize) or 1 end
		if edgeSize <= 0 then edgeSize = 1 end
		local insetVal = borderCfg.inset
		if insetVal == nil and borderDef then insetVal = borderDef.inset end
		if insetVal == nil then insetVal = edgeSize end
		insetVal = tonumber(insetVal) or edgeSize
		local edgeFile = UFHelper.resolveBorderTexture(borderCfg.texture or (borderDef and borderDef.texture))
		local cache = borderFrame._ufBorderCache
		local styleChanged = not cache
			or cache.enabled ~= true
			or cache.edgeFile ~= edgeFile
			or cache.edgeSize ~= edgeSize
			or cache.insetVal ~= insetVal
			or cache.colorR ~= colorR
			or cache.colorG ~= colorG
			or cache.colorB ~= colorB
			or cache.colorA ~= colorA
		if styleChanged then
			local style = {
				bgFile = "Interface\\Buttons\\WHITE8x8",
				edgeFile = edgeFile,
				edgeSize = edgeSize,
				insets = { left = insetVal, right = insetVal, top = insetVal, bottom = insetVal },
			}
			borderFrame._ufBorderStyle = style
			borderFrame:SetBackdrop(style)
			borderFrame:SetBackdropColor(0, 0, 0, 0)
			borderFrame:SetBackdropBorderColor(colorR, colorG, colorB, colorA)
			cache = cache or {}
			cache.enabled = true
			cache.edgeFile = edgeFile
			cache.edgeSize = edgeSize
			cache.insetVal = insetVal
			cache.colorR = colorR
			cache.colorG = colorG
			cache.colorB = colorB
			cache.colorA = colorA
			borderFrame._ufBorderCache = cache
		end
		borderFrame:Show()
	else
		local borderFrame = frame._ufBorder
		if borderFrame then
			local cache = borderFrame._ufBorderCache
			if not cache or cache.enabled ~= false then
				borderFrame:SetBackdrop(nil)
				cache = cache or {}
				cache.enabled = false
				borderFrame._ufBorderCache = cache
			end
			borderFrame:Hide()
		end
	end
end

local function applyBarBackdrop(bar, cfg, overrideR, overrideG, overrideB, overrideA, options)
	if not bar then return end
	cfg = cfg or {}
	options = options or {}
	local bd = cfg.backdrop or {}
	local clampToFill = options.clampToFill == true
	local reverseFill = options.reverseFill == true
	local cache = bar._ufBackdropCache
	if bd.enabled == false then
		if cache and cache.enabled == false and cache.clampToFill == clampToFill and cache.reverseFill == reverseFill then return end
		if bar.SetBackdrop then bar:SetBackdrop(nil) end
		if bar._ufBackdropTexture then bar._ufBackdropTexture:Hide() end
		cache = cache or {}
		cache.enabled = false
		cache.clampToFill = clampToFill
		cache.reverseFill = reverseFill
		cache.statusTex = nil
		bar._ufBackdropCache = cache
		return
	end
	local colorR, colorG, colorB, colorA
	if overrideR ~= nil and overrideG ~= nil and overrideB ~= nil then
		colorR, colorG, colorB = overrideR, overrideG, overrideB
		colorA = overrideA
		if colorA == nil then
			local _, _, _, fallbackA = unpackColor(bd.color, 0, 0, 0, 0.6)
			colorA = fallbackA
		end
	else
		colorR, colorG, colorB, colorA = unpackColor(bd.color, 0, 0, 0, 0.6)
	end
	local currentStatusTex = (clampToFill and bar.GetStatusBarTexture and bar:GetStatusBarTexture()) or nil
	local styleChanged = not cache
		or cache.enabled ~= true
		or cache.colorR ~= colorR
		or cache.colorG ~= colorG
		or cache.colorB ~= colorB
		or cache.colorA ~= colorA
		or cache.clampToFill ~= clampToFill
		or cache.reverseFill ~= reverseFill
		or cache.statusTex ~= currentStatusTex
	if not styleChanged then return end
	if clampToFill then
		if bar.SetBackdrop then bar:SetBackdrop(nil) end
		local tex = bar._ufBackdropTexture
		if not tex then
			tex = bar:CreateTexture(nil, "BACKGROUND")
			tex:SetTexture("Interface\\Buttons\\WHITE8x8")
			bar._ufBackdropTexture = tex
		end
		local htex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
		tex:ClearAllPoints()
		if htex then
			if reverseFill then
				tex:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
				tex:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
				tex:SetPoint("TOPRIGHT", htex, "TOPLEFT", 0, 0)
				tex:SetPoint("BOTTOMRIGHT", htex, "BOTTOMLEFT", 0, 0)
			else
				tex:SetPoint("TOPLEFT", htex, "TOPRIGHT", 0, 0)
				tex:SetPoint("BOTTOMLEFT", htex, "BOTTOMRIGHT", 0, 0)
				tex:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
				tex:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
			end
		else
			tex:SetAllPoints(bar)
		end
		tex:SetColorTexture(colorR, colorG, colorB, colorA)
		tex:Show()
	else
		if bar._ufBackdropTexture then bar._ufBackdropTexture:Hide() end
		bar:SetBackdrop(BAR_BACKDROP_STYLE)
		bar:SetBackdropColor(colorR, colorG, colorB, colorA)
	end
	cache = cache or {}
	cache.enabled = true
	cache.colorR = colorR
	cache.colorG = colorG
	cache.colorB = colorB
	cache.colorA = colorA
	cache.clampToFill = clampToFill
	cache.reverseFill = reverseFill
	cache.statusTex = currentStatusTex
	bar._ufBackdropCache = cache
end

local function ensureCastBorderFrame(st)
	if not st or not st.castBar then return nil end
	local border = st.castBorder
	if not border then
		border = CreateFrame("Frame", nil, st.castBar, "BackdropTemplate")
		border:EnableMouse(false)
		st.castBorder = border
	end
	border:SetFrameStrata(st.castBar:GetFrameStrata())
	local baseLevel = st.castBar:GetFrameLevel() or 0
	border:SetFrameLevel(baseLevel + 3)
	return border
end

local function applyCastBorder(st, ccfg, defc)
	if not st or not st.castBar then return end
	local borderCfg = (ccfg and ccfg.border) or (defc and defc.border) or {}
	if borderCfg.enabled == true then
		local border = ensureCastBorderFrame(st)
		if not border then return end
		local size = tonumber(borderCfg.edgeSize) or 1
		if size < 1 then size = 1 end
		local offset = borderCfg.offset
		if offset == nil then offset = size end
		offset = math.max(0, tonumber(offset) or 0)
		border:ClearAllPoints()
		border:SetPoint("TOPLEFT", st.castBar, "TOPLEFT", -offset, offset)
		border:SetPoint("BOTTOMRIGHT", st.castBar, "BOTTOMRIGHT", offset, -offset)
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
		local border = st.castBorder
		if border then
			border:SetBackdrop(nil)
			border:Hide()
		end
	end
end

local function applyOverlayHeight(bar, anchor, height, maxHeight)
	if not bar or not anchor then return end
	bar:ClearAllPoints()
	local desired = tonumber(height)
	if not desired or desired <= 0 then
		bar:SetAllPoints(anchor)
		return
	end
	local limit = tonumber(maxHeight)
	if not limit or limit <= 0 then limit = anchor.GetHeight and anchor:GetHeight() or 0 end
	if limit and limit > 0 and desired > limit then desired = limit end
	bar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
	bar:SetHeight(desired)
end

local function shouldShowSampleAbsorb(unit)
	local samples = addon.variables.ufSampleAbsorb
	if not samples then return false end
	if samples[unit] == true then return true end
	if unit and unit:match("^boss%d+$") then return samples.boss == true end
	return false
end

local function shouldShowSampleHealAbsorb(unit)
	local samples = addon.variables.ufSampleHealAbsorb
	if not samples then return false end
	if samples[unit] == true then return true end
	if unit and unit:match("^boss%d+$") then return samples.boss == true end
	return false
end

function UF.ClearCastInterruptState(st)
	if not st then return end
	if st.castInterruptAnim then st.castInterruptAnim:Stop() end
	if st.castInterruptGlowAnim then st.castInterruptGlowAnim:Stop() end
	if st.castInterruptGlow then st.castInterruptGlow:Hide() end
	UFHelper.hideCastSpark(st)
	if st.castBar then st.castBar:SetAlpha(1) end
	st.castInterruptActive = nil
	st.castInterruptToken = (st.castInterruptToken or 0) + 1
end

local function stopCast(unit)
	local st = states[unit]
	if not st or not st.castBar then return end
	UF.ClearCastInterruptState(st)
	UFHelper.clearEmpowerStages(st)
	UFHelper.hideCastSpark(st)
	st.castBar:Hide()
	if st.castName then st.castName:SetText("") end
	if st.castDuration then st.castDuration:SetText("") end
	if st.castIcon then st.castIcon:Hide() end
	st.castIconTexture = nil
	st.castTarget = nil
	st.castInfo = nil
	if castOnUpdateHandlers[unit] then
		st.castBar:SetScript("OnUpdate", nil)
		castOnUpdateHandlers[unit] = nil
	end
end

local normalizeStrataToken

local function applyCastLayout(cfg, unit)
	local st = states[unit]
	if not st or not st.castBar then return end
	local def = defaultsFor(unit)
	local ccfg = (cfg and cfg.cast) or {}
	local defc = (def and def.cast) or {}
	local hc = (cfg and cfg.health) or {}
	local width = ccfg.width or (cfg and cfg.width) or defc.width or (def and def.width) or 220
	local height = ccfg.height or defc.height or 16
	st.castBar:SetSize(width, height)
	local anchor = (ccfg.anchor or defc.anchor or "BOTTOM")
	local off = ccfg.offset or defc.offset or { x = 0, y = -4 }
	local centerOffset = (st and st._portraitCenterOffset) or 0
	local anchorFrame = st.barGroup or st.frame
	local castStrata = normalizeStrataToken(ccfg.strata) or normalizeStrataToken(defc.strata) or ((st.frame and st.frame.GetFrameStrata and st.frame:GetFrameStrata()) or "MEDIUM")
	local castLevelOffset = tonumber(ccfg.frameLevelOffset)
	if castLevelOffset == nil then castLevelOffset = tonumber(defc.frameLevelOffset) end
	if castLevelOffset == nil then castLevelOffset = 1 end
	local baseFrameLevel = (st.frame and st.frame.GetFrameLevel and st.frame:GetFrameLevel()) or 0
	local castFrameLevel = math.max(0, baseFrameLevel + castLevelOffset)
	if st.castBar.GetFrameStrata and st.castBar.SetFrameStrata and st.castBar:GetFrameStrata() ~= castStrata then st.castBar:SetFrameStrata(castStrata) end
	if st.castBar.GetFrameLevel and st.castBar.SetFrameLevel and st.castBar:GetFrameLevel() ~= castFrameLevel then st.castBar:SetFrameLevel(castFrameLevel) end
	st.castBar:ClearAllPoints()
	if anchor == "TOP" then
		st.castBar:SetPoint("BOTTOM", anchorFrame, "TOP", (off.x or 0) + centerOffset, off.y or 0)
	else
		st.castBar:SetPoint("TOP", anchorFrame, "BOTTOM", (off.x or 0) + centerOffset, off.y or 0)
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
		local iconOff = ccfg.iconOffset or defc.iconOffset or { x = -4, y = 0 }
		if type(iconOff) ~= "table" then iconOff = { x = iconOff, y = 0 } end
		st.castIcon:SetSize(size, size)
		st.castIcon:ClearAllPoints()
		st.castIcon:SetPoint("RIGHT", st.castBar, "LEFT", iconOff.x or -4, iconOff.y or 0)
		st.castIcon:SetShown(ccfg.showIcon ~= false)
	end
	local texKey = ccfg.texture or defc.texture or "DEFAULT"
	local useDefaultArt = not texKey or texKey == "" or texKey == "DEFAULT"
	local castTexture = UFHelper.resolveCastTexture(texKey)
	st.castBar:SetStatusBarTexture(castTexture)
	st.castUseDefaultArt = useDefaultArt
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
			if useDefaultArt and bg.SetAtlas then
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
	applyCastBorder(st, ccfg, defc)
	-- Limit cast name width so long names don't overlap duration text
	if st.castName then
		local iconSize = (ccfg.iconSize or defc.iconSize or height) + 4
		if ccfg.showIcon == false then iconSize = 0 end
		local durationSpace = (ccfg.showDuration ~= false) and 60 or 0
		local available = (width or 0) - iconSize - durationSpace - 6
		if available < 0 then available = 0 end
		local maxChars = ccfg.nameMaxChars
		if maxChars == nil then maxChars = defc.nameMaxChars end
		maxChars = tonumber(maxChars) or 0
		if maxChars > 0 and UFHelper.getNameLimitWidth then
			local castFont = ccfg.font or defc.font or hc.font
			local castFontSize = ccfg.fontSize or defc.fontSize or hc.fontSize or 12
			local castOutline = ccfg.fontOutline or defc.fontOutline or hc.fontOutline or "OUTLINE"
			local maxWidth = UFHelper.getNameLimitWidth(castFont, castFontSize, castOutline, maxChars)
			if maxWidth and maxWidth > 0 then available = maxWidth end
		end
		st.castName:SetWidth(available)
		if st.castName.SetWordWrap then st.castName:SetWordWrap(false) end
		if st.castName.SetMaxLines then st.castName:SetMaxLines(1) end
		if st.castName.SetJustifyH then st.castName:SetJustifyH("LEFT") end
	end
	if st.castEmpower and st.castEmpower.stagePercents then UFHelper.layoutEmpowerStages(st) end
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

local function configureCastStatic(unit, ccfg, defc)
	local st = states[unit]
	if not st or not st.castBar or not st.castInfo then return end
	ccfg = ccfg or st.castCfg or {}
	defc = defc or (defaultsFor(unit) and defaultsFor(unit).cast) or {}
	local isEmpoweredDefault = st.castInfo.isEmpowered and st.castUseDefaultArt == true
	local clr = ccfg.color or defc.color or { 0.9, 0.7, 0.2, 1 }
	local useClassColor = ccfg.useClassColor
	if useClassColor == nil then useClassColor = defc.useClassColor end
	if useClassColor == true then
		local class
		if UnitIsPlayer and UnitIsPlayer(unit) then
			class = select(2, UnitClass(unit))
		elseif unit == UNIT.PET then
			class = select(2, UnitClass(UNIT.PLAYER))
		end
		local cr, cg, cb, ca = getClassColor(class)
		if cr then clr = { cr, cg, cb, ca or 1 } end
	end
	if isEmpoweredDefault then
		st.castBar:SetStatusBarDesaturated(false)
		UFHelper.SetCastbarColorWithGradient(st.castBar, nil, 0, 0, 0, 0)
	elseif st.castInfo.notInterruptible then
		clr = ccfg.notInterruptibleColor or defc.notInterruptibleColor or clr
		st.castBar:SetStatusBarDesaturated(true)
		UFHelper.SetCastbarColorWithGradient(st.castBar, ccfg, clr[1] or 0.9, clr[2] or 0.7, clr[3] or 0.2, clr[4] or 1)
	else
		st.castBar:SetStatusBarDesaturated(false)
		UFHelper.SetCastbarColorWithGradient(st.castBar, ccfg, clr[1] or 0.9, clr[2] or 0.7, clr[3] or 0.2, clr[4] or 1)
	end
	local duration = (st.castInfo.endTime or 0) - (st.castInfo.startTime or 0)
	local maxValue = duration and duration > 0 and duration / 1000 or 1
	st.castInfo.maxValue = maxValue
	-- UFHelper.applyStatusBarReverseFill(st.castBar, st.castInfo.isChannel == true and not st.castInfo.isEmpowered)
	st.castBar:SetMinMaxValues(0, maxValue)
	UFHelper.RefreshCastbarGradient(st.castBar, isEmpoweredDefault and nil or ccfg)
	if st.castName then
		local showName = ccfg.showName ~= false
		st.castName:SetShown(showName)
		local nameText = showName and (st.castInfo.name or "") or ""
		if showName and UFHelper.formatCastName then
			local showTarget = ccfg.showCastTarget
			if showTarget == nil then showTarget = defc.showCastTarget end
			if unit ~= UNIT.PLAYER then showTarget = false end
			nameText = UFHelper.formatCastName(nameText, st.castTarget, showTarget == true)
		end
		st.castName:SetText(nameText)
	end
	if st.castIcon then
		local iconTexture = UFHelper.resolveCastIconTexture(st.castInfo.texture)
		local showIcon = ccfg.showIcon ~= false
		st.castIcon:SetShown(showIcon)
		if showIcon then
			st.castIcon:SetTexture(iconTexture)
			st.castIconTexture = iconTexture
		end
	end
	if st.castDuration then st.castDuration:SetShown(ccfg.showDuration ~= false) end
	st.castBar:Show()
end

local function updateCastBar(unit)
	local st = states[unit]
	local ccfg = st and st.castCfg
	if not st or not st.castBar or not st.castInfo or not ccfg then
		stopCast(unit)
		return
	end
	if st.castInfo.useTimer then
		if st.castInfo.isEmpowered then
			UFHelper.updateEmpowerStageFromBar(st)
			UFHelper.updateCastSpark(st, "empowered")
		else
			UFHelper.hideCastSpark(st)
		end
		return
	end
	if not st.castInfo.startTime or not st.castInfo.endTime then
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
	local elapsedMs
	if st.castInfo.isEmpowered then
		elapsedMs = nowMs - startMs
	else
		elapsedMs = st.castInfo.isChannel and (endMs - nowMs) or (nowMs - startMs)
	end
	if elapsedMs < 0 then elapsedMs = 0 end
	local value = elapsedMs / 1000
	st.castBar:SetValue(value)
	if not (st.castInfo.isEmpowered and st.castUseDefaultArt == true) and ccfg.useGradient == true and type(ccfg.gradientMode) == "string" and ccfg.gradientMode:upper() == "BAR_END" then
		local maxValue = st.castInfo.maxValue
		local progress
		if type(maxValue) == "number" and maxValue > 0 then progress = value / maxValue end
		UFHelper.RefreshCastbarGradient(st.castBar, ccfg, nil, nil, nil, nil, progress)
	end
	if st.castInfo.isEmpowered then
		local maxValue = st.castInfo.maxValue
		if not maxValue then
			local _, maxVal = st.castBar:GetMinMaxValues()
			maxValue = maxVal
		end
		if maxValue and maxValue > 0 and (not issecretvalue or (not issecretvalue(value) and not issecretvalue(maxValue))) then UFHelper.updateEmpowerStageFromProgress(st, value / maxValue) end
		UFHelper.updateCastSpark(st, "empowered")
	else
		UFHelper.hideCastSpark(st)
	end
	if st.castDuration then
		if ccfg.showDuration ~= false then
			local durationFormat = ccfg.durationFormat or "REMAINING"
			if durationFormat == "ELAPSED_TOTAL" then
				local total = duration / 1000
				local elapsed = (nowMs - startMs) / 1000
				if elapsed < 0 then elapsed = 0 end
				if elapsed > total then elapsed = total end
				local tenths = math.floor(elapsed * 10 + 0.5)
				if st.castInfo.durationTenths ~= tenths then
					st.castInfo.durationTenths = tenths
					st.castDuration:SetText(("%.1f / %.1f"):format(elapsed, total))
				end
			elseif durationFormat == "REMAINING_TOTAL" then
				local total = duration / 1000
				local remaining = (endMs - nowMs) / 1000
				if remaining < 0 then remaining = 0 end
				if remaining > total then remaining = total end
				local tenths = math.floor(remaining * 10 + 0.5)
				if st.castInfo.durationTenths ~= tenths then
					st.castInfo.durationTenths = tenths
					st.castDuration:SetText(("%.1f / %.1f"):format(remaining, total))
				end
			else
				local remaining = (endMs - nowMs) / 1000
				if remaining < 0 then remaining = 0 end
				local tenths = math.floor(remaining * 10 + 0.5)
				if st.castInfo.durationTenths ~= tenths then
					st.castInfo.durationTenths = tenths
					st.castDuration:SetText(("%.1f"):format(remaining))
				end
			end
			st.castDuration:Show()
		else
			st.castInfo.durationTenths = nil
			st.castDuration:SetText("")
			st.castDuration:Hide()
		end
	end
end

shouldShowSampleCast = function(unit) return addon.EditModeLib and addon.EditModeLib:IsInEditMode() end

setSampleCast = function(unit)
	local key = isBossUnit(unit) and "boss" or unit
	local st = states[unit]
	if not st or not st.castBar then return end
	UF.ClearCastInterruptState(st)
	UFHelper.clearEmpowerStages(st)
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

local function shouldIgnoreCastFail(unit, castGUID, spellId)
	if UnitChannelInfo then
		local channelName = UnitChannelInfo(unit)
		if channelName then return true end
	end
	local st = states[unit]
	if not st or not st.castInfo then return false end
	if st.castInfo.castGUID and castGUID then
		if not (issecretvalue and (issecretvalue(st.castInfo.castGUID) or issecretvalue(castGUID))) and st.castInfo.castGUID ~= castGUID then return true end
	end
	if st.castInfo.spellId and spellId and st.castInfo.castGUID then
		if not (issecretvalue and (issecretvalue(st.castInfo.spellId) or issecretvalue(spellId))) and st.castInfo.spellId ~= spellId then return true end
	end
	return false
end

function UF.ShowCastInterrupt(unit, event)
	local key = isBossUnit(unit) and "boss" or unit
	local st = states[unit]
	if not st or not st.castBar then return end
	local cfg = (st and st.cfg) or ensureDB(key or unit)
	if cfg and cfg.enabled == false then return end
	local ccfg = (cfg or {}).cast or {}
	local defc = (defaultsFor(unit) and defaultsFor(unit).cast) or {}
	if ccfg.enabled == false then return end
	if not st.castBar:IsShown() and not st.castInfo then return end
	local showInterruptFeedback = ccfg.showInterruptFeedback
	if showInterruptFeedback == nil then showInterruptFeedback = defc.showInterruptFeedback end
	if showInterruptFeedback == false then
		stopCast(unit)
		if shouldShowSampleCast(unit) then setSampleCast(unit) end
		return
	end

	UF.ClearCastInterruptState(st)
	UFHelper.clearEmpowerStages(st)
	st.castInterruptActive = true
	local token = st.castInterruptToken or 0

	if castOnUpdateHandlers[unit] then
		st.castBar:SetScript("OnUpdate", nil)
		castOnUpdateHandlers[unit] = nil
	end

	applyCastLayout(cfg, unit)

	local texKey = ccfg.texture or defc.texture or "DEFAULT"
	local useDefault = not texKey or texKey == "" or texKey == "DEFAULT"
	local interruptTex
	if useDefault then
		interruptTex = (UFHelper.resolveCastInterruptTexture and UFHelper.resolveCastInterruptTexture()) or UFHelper.resolveCastTexture(texKey)
	else
		interruptTex = UFHelper.resolveCastTexture(texKey)
	end
	if interruptTex then st.castBar:SetStatusBarTexture(interruptTex) end
	if st.castBar.SetStatusBarDesaturated then st.castBar:SetStatusBarDesaturated(false) end
	if useDefault then
		UFHelper.SetCastbarColorWithGradient(st.castBar, nil, 1, 1, 1, 1)
	else
		UFHelper.SetCastbarColorWithGradient(st.castBar, nil, 0.85, 0.12, 0.12, 1)
	end
	st.castBar:SetMinMaxValues(0, 1)
	st.castBar:SetValue(1)
	if st.castDuration then
		st.castDuration:SetText("")
		st.castDuration:Hide()
	end
	if st.castName then
		local label = (event == "UNIT_SPELLCAST_FAILED") and FAILED or INTERRUPTED
		st.castName:SetText(label)
		st.castName:SetShown(ccfg.showName ~= false)
	end
	if st.castIcon then
		local iconTexture = UFHelper.resolveCastIconTexture((st.castInfo and st.castInfo.texture) or st.castIconTexture)
		local showIcon = ccfg.showIcon ~= false
		st.castIcon:SetShown(showIcon)
		if showIcon then
			st.castIcon:SetTexture(iconTexture)
			st.castIconTexture = iconTexture
		end
	end

	local glowAlpha = useDefault and 0.4 or 0.25
	if not st.castInterruptGlow then
		st.castInterruptGlow = st.castBar:CreateTexture(nil, "OVERLAY")
		if st.castInterruptGlow.SetAtlas then
			st.castInterruptGlow:SetAtlas("cast_interrupt_outerglow", true)
		else
			st.castInterruptGlow:SetTexture("Interface\\CastingBar\\UI-CastingBar-Border")
		end
		if st.castInterruptGlow.SetBlendMode then st.castInterruptGlow:SetBlendMode("ADD") end
		st.castInterruptGlow:SetPoint("CENTER", st.castBar, "CENTER", 0, 0)
		st.castInterruptGlow:SetAlpha(0)
	end
	do
		local w, h = st.castBar:GetSize()
		if w and h and w > 0 and h > 0 then
			st.castInterruptGlow:SetSize(w + (h * 0.5), h * 2.2)
			if st.castInterruptGlow.SetScale then st.castInterruptGlow:SetScale(1) end
		elseif st.castInterruptGlow.SetScale then
			st.castInterruptGlow:SetScale(0.5)
		end
	end
	if not st.castInterruptGlowAnim then
		st.castInterruptGlowAnim = st.castInterruptGlow:CreateAnimationGroup()
		local fade = st.castInterruptGlowAnim:CreateAnimation("Alpha")
		fade:SetFromAlpha(glowAlpha)
		fade:SetToAlpha(0)
		fade:SetDuration(1.0)
		st.castInterruptGlowAnim.fade = fade
		st.castInterruptGlowAnim:SetScript("OnFinished", function() st.castInterruptGlow:Hide() end)
	elseif st.castInterruptGlowAnim.fade and st.castInterruptGlowAnim.fade.SetFromAlpha then
		st.castInterruptGlowAnim.fade:SetFromAlpha(glowAlpha)
	end
	st.castInterruptGlow:SetAlpha(glowAlpha)
	st.castInterruptGlow:Show()
	st.castInterruptGlowAnim:Stop()
	st.castInterruptGlowAnim:Play()

	if not st.castInterruptAnim then
		st.castInterruptAnim = st.castBar:CreateAnimationGroup()
		local hold = st.castInterruptAnim:CreateAnimation("Alpha")
		hold:SetOrder(1)
		hold:SetFromAlpha(1)
		hold:SetToAlpha(1)
		hold:SetDuration(1.0)
		st.castInterruptAnim.hold = hold
		local fade = st.castInterruptAnim:CreateAnimation("Alpha")
		fade:SetOrder(2)
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0)
		fade:SetDuration(0.3)
		st.castInterruptAnim.fade = fade
	end
	st.castBar:SetAlpha(1)
	st.castBar:Show()
	st.castInterruptAnim:Stop()
	st.castInterruptAnim:SetScript("OnFinished", function()
		local st2 = states[unit]
		if not st2 or st2.castInterruptToken ~= token then return end
		stopCast(unit)
		if shouldShowSampleCast(unit) then setSampleCast(unit) end
	end)
	st.castInterruptAnim:Play()
end

local function setCastInfoFromUnit(unit)
	local key = isBossUnit(unit) and "boss" or unit
	local st = states[unit]
	if not st or not st.castBar then return end
	UF.ClearCastInterruptState(st)
	local cfg = (st and st.cfg) or ensureDB(key or unit)
	if cfg and cfg.enabled == false then
		stopCast(unit)
		return
	end
	local ccfg = (cfg or {}).cast or {}
	local defc = (defaultsFor(unit) and defaultsFor(unit).cast) or {}
	if ccfg.enabled == false then
		stopCast(unit)
		return
	end
	local name, text, texture, startTimeMS, endTimeMS, _, notInterruptible, spellId, isEmpowered, numEmpowerStages = UnitChannelInfo(unit)
	local isChannel = true
	local castGUID
	if not name then
		name, text, texture, startTimeMS, endTimeMS, _, castGUID, notInterruptible, spellId = UnitCastingInfo(unit)
		isChannel = false
		isEmpowered = nil
		numEmpowerStages = nil
	end
	if not name then
		if shouldShowSampleCast(unit) then
			setSampleCast(unit)
		else
			stopCast(unit)
		end
		return
	end
	applyCastLayout(cfg, unit)

	local isEmpoweredCast = isChannel and (issecretvalue and not issecretvalue(isEmpowered)) and isEmpowered and numEmpowerStages and numEmpowerStages > 0
	if isEmpoweredCast and startTimeMS and endTimeMS and (not issecretvalue or (not issecretvalue(startTimeMS) and not issecretvalue(endTimeMS))) then
		local totalMs = UFHelper.getEmpoweredChannelDurationMilliseconds and UFHelper.getEmpoweredChannelDurationMilliseconds(unit)
		if totalMs and totalMs > 0 and (not issecretvalue or not issecretvalue(totalMs)) then
			endTimeMS = startTimeMS + totalMs
		else
			local hold = UFHelper.getEmpowerHoldMilliseconds and UFHelper.getEmpowerHoldMilliseconds(unit)
			if hold and (not issecretvalue or not issecretvalue(hold)) then endTimeMS = endTimeMS + hold end
		end
	end

	if issecretvalue and ((startTimeMS and issecretvalue(startTimeMS)) or (endTimeMS and issecretvalue(endTimeMS))) then
		if type(startTimeMS) ~= "nil" and type(endTimeMS) ~= "nil" then
			st.castBar:Show()

			local durObj, direction
			-- TODO this can be made easier after ptr and beta have the same API
			if _G.UnitEmpoweredChannelDuration then
				durObj = _G.UnitEmpoweredChannelDuration(unit, true)
				direction = Enum.StatusBarTimerDirection.ElapsedTime
				if not durObj then
					if isChannel then
						durObj = UnitChannelDuration(unit)
						direction = Enum.StatusBarTimerDirection.RemainingTime
					else
						durObj = UnitCastingDuration(unit)
						direction = Enum.StatusBarTimerDirection.ElapsedTime
					end
				end
			elseif isChannel then
				durObj = UnitChannelDuration(unit)
				direction = Enum.StatusBarTimerDirection.RemainingTime
			else
				durObj = UnitCastingDuration(unit)
				direction = Enum.StatusBarTimerDirection.ElapsedTime
			end
			if not durObj then
				stopCast(unit)
				return
			end
			st.castBar:SetTimerDuration(durObj, Enum.StatusBarInterpolation.Immediate, direction)
			st.castBarDuration = durObj
			if st.castName then
				local showName = ccfg.showName ~= false
				st.castName:SetShown(showName)
				local nameText = showName and (text or name or "") or ""
				if showName and UFHelper.formatCastName then
					local showTarget = ccfg.showCastTarget
					if showTarget == nil then showTarget = defc.showCastTarget end
					if unit ~= UNIT.PLAYER then showTarget = false end
					nameText = UFHelper.formatCastName(nameText, st.castTarget, showTarget == true)
				end
				st.castName:SetText(nameText)
			end
			if st.castIcon then
				local iconTexture = UFHelper.resolveCastIconTexture(texture)
				local showIcon = ccfg.showIcon ~= false
				st.castIcon:SetShown(showIcon)
				if showIcon then
					st.castIcon:SetTexture(iconTexture)
					st.castIconTexture = iconTexture
				end
			end
			local clr = ccfg.color or defc.color or { 0.9, 0.7, 0.2, 1 }
			local nclr = ccfg.notInterruptibleColor or defc.notInterruptibleColor or { 204 / 255, 204 / 255, 204 / 255, 1 }
			local activeColor = notInterruptible and nclr or clr
			UFHelper.SetCastbarColorWithGradient(st.castBar, ccfg, activeColor[1] or 0.9, activeColor[2] or 0.7, activeColor[3] or 0.2, activeColor[4] or 1)
			st.castBar:SetStatusBarDesaturated(true)
			local usesBarEndGradient = not (isEmpowered and st.castUseDefaultArt == true)
				and ccfg.useGradient == true
				and type(ccfg.gradientMode) == "string"
				and ccfg.gradientMode:upper() == "BAR_END"
			if usesBarEndGradient then
				local totalDuration = durObj:GetTotalDuration()
				if totalDuration and totalDuration > 0 then
					local progress
					if direction == Enum.StatusBarTimerDirection.RemainingTime then
						progress = durObj:GetRemainingDuration() / totalDuration
					else
						progress = durObj:GetElapsedDuration() / totalDuration
					end
					UFHelper.RefreshCastbarGradient(st.castBar, ccfg, nil, nil, nil, nil, progress)
				else
					UFHelper.RefreshCastbarGradient(st.castBar, ccfg)
				end
			end
			local showDuration = ccfg.showDuration ~= false and st.castDuration ~= nil
			local needsOnUpdate = showDuration or usesBarEndGradient
			if not needsOnUpdate then
				if castOnUpdateHandlers[unit] then
					st.castBar:SetScript("OnUpdate", nil)
					castOnUpdateHandlers[unit] = nil
				end
				if st.castDuration then
					st.castDuration:SetText("")
					st.castDuration:Hide()
				end
			else
				if st.castDuration then
					if showDuration then
						st.castDuration:Show()
					else
						st.castDuration:SetText("")
						st.castDuration:Hide()
					end
				end
				st.castBar._eqolCastDurationElapsed = 0
				st.castBar:SetScript("OnUpdate", function(self, elapsed)
					local timerObj = st.castBarDuration
					if not timerObj then
						self:SetScript("OnUpdate", nil)
						castOnUpdateHandlers[unit] = nil
						return
					end

					self._eqolCastDurationElapsed = (self._eqolCastDurationElapsed or 0) + (elapsed or 0)
					if self._eqolCastDurationElapsed < 0.1 then return end
					self._eqolCastDurationElapsed = 0

					local totalDuration = timerObj:GetTotalDuration()
					if type(totalDuration) ~= "number" then totalDuration = 0 end
					if usesBarEndGradient and totalDuration > 0 then
						local progress
						if direction == Enum.StatusBarTimerDirection.RemainingTime then
							progress = timerObj:GetRemainingDuration() / totalDuration
						else
							progress = timerObj:GetElapsedDuration() / totalDuration
						end
						UFHelper.RefreshCastbarGradient(st.castBar, ccfg, nil, nil, nil, nil, progress)
					end

					if not showDuration or not st.castDuration then return end
					local durationFormat = ccfg.durationFormat or defc.durationFormat or "REMAINING"
					if durationFormat == "ELAPSED_TOTAL" then
						st.castDuration:SetText(("%.1f / %.1f"):format(timerObj:GetElapsedDuration(), totalDuration))
						return
					elseif durationFormat == "REMAINING_TOTAL" then
						st.castDuration:SetText(("%.1f / %.1f"):format(timerObj:GetRemainingDuration(), totalDuration))
						return
					else
						st.castDuration:SetText(("%.1f"):format(timerObj:GetRemainingDuration()))
						return
					end
				end)
				castOnUpdateHandlers[unit] = true
			end
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
		texture = UFHelper.resolveCastIconTexture(texture),
		startTime = startTimeMS,
		endTime = endTimeMS,
		notInterruptible = notInterruptible,
		isChannel = isChannel,
		isEmpowered = isEmpowered,
		numEmpowerStages = numEmpowerStages,
		castGUID = castGUID,
		spellId = spellId,
	}
	configureCastStatic(unit, resolvedCfg, defc)
	if isEmpowered then
		UFHelper.setupEmpowerStages(st, unit, numEmpowerStages)
	else
		UFHelper.clearEmpowerStages(st)
	end
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

local function ensureBossBarsVisible(unit, st)
	if not isBossUnit(unit) then return end
	if not UnitExists or not UnitExists(unit) then return end
	if st.barGroup and not st.barGroup:IsShown() then st.barGroup:Show() end
	if st.status and not st.status:IsShown() then st.status:Show() end
end

local function updateHealth(cfg, unit)
	cfg = cfg or (states[unit] and states[unit].cfg) or ensureDB(unit)
	if cfg and cfg.enabled == false then return end
	local st = states[unit]
	if not st or not st.health or not st.frame then return end
	ensureBossBarsVisible(unit, st)
	local info = UNITS[unit]
	local allowAbsorb = not (info and info.disableAbsorb)
	local def = defaultsFor(unit) or {}
	local defH = def.health or {}
	local interpolation = getSmoothInterpolation(cfg, def)
	local cur = UnitHealth(unit)
	local maxv = UnitHealthMax(unit)
	if issecretvalue and issecretvalue(maxv) then
		st.health:SetMinMaxValues(0, maxv or 1)
	else
		st.health:SetMinMaxValues(0, maxv > 0 and maxv or 1)
	end
	st.health:SetValue(cur or 0, interpolation)
	local hc = cfg.health or {}
	local cacheGuid = UnitGUID and UnitGUID(unit) or nil
	local guidComparable = cacheGuid ~= nil and not (issecretvalue and issecretvalue(cacheGuid))
	if not guidComparable then
		st._healthColorGuid = nil
		st._healthColorDirty = true
	elseif st._healthColorGuid ~= cacheGuid then
		st._healthColorGuid = cacheGuid
		st._healthColorDirty = true
	end

	local hr, hg, hb, ha = st._healthColorR, st._healthColorG, st._healthColorB, st._healthColorA
	if st._healthColorDirty or hr == nil then
		local useCustom = hc.useCustomColor == true
		local isPlayerUnit = UnitIsPlayer and UnitIsPlayer(unit)
		hr, hg, hb, ha = nil, nil, nil, nil

		if useCustom then
			if not isPlayerUnit then
				local nr, ng, nb, na
				if UFHelper and UFHelper.getNPCOverrideColor then
					nr, ng, nb, na = UFHelper.getNPCOverrideColor(unit)
				end
				if nr then
					hr, hg, hb, ha = nr, ng, nb, na
				elseif hc.color then
					hr, hg, hb, ha = hc.color[1], hc.color[2], hc.color[3], hc.color[4] or 1
				end
			elseif hc.color then
				hr, hg, hb, ha = hc.color[1], hc.color[2], hc.color[3], hc.color[4] or 1
			end
		elseif hc.useClassColor then
			local class
			if isPlayerUnit then
				class = select(2, UnitClass(unit))
			elseif unit == UNIT.PET then
				class = select(2, UnitClass(UNIT.PLAYER))
			end
			local cr, cg, cb, ca = getClassColor(class)
			if cr then
				hr, hg, hb, ha = cr, cg, cb, ca
			end
		end

		if not hr and not useCustom then
			local nr, ng, nb, na
			if UFHelper and UFHelper.getNPCHealthColor then
				nr, ng, nb, na = UFHelper.getNPCHealthColor(unit)
			end
			if nr then
				hr, hg, hb, ha = nr, ng, nb, na
			end
		end

		local useTapDenied = hc.useTapDeniedColor
		if useTapDenied == nil then useTapDenied = defH.useTapDeniedColor end
		if useTapDenied ~= false and UnitIsTapDenied and UnitPlayerControlled and not UnitPlayerControlled(unit) and UnitIsTapDenied(unit) then
			local tc = hc.tapDeniedColor or defH.tapDeniedColor or { 0.5, 0.5, 0.5, 1 }
			hr, hg, hb, ha = tc[1] or 0.5, tc[2] or 0.5, tc[3] or 0.5, tc[4] or 1
		end

		if not hr then
			local color = defH.color or { 0, 0.8, 0, 1 }
			hr, hg, hb, ha = color[1] or 0, color[2] or 0.8, color[3] or 0, color[4] or 1
		end

		st._healthColorR, st._healthColorG, st._healthColorB, st._healthColorA = hr, hg, hb, ha
		st._healthColorDirty = nil
	end
	st.health:SetStatusBarColor(hr or 0, hg or 0.8, hb or 0, ha or 1)
	if allowAbsorb and (st.absorb or st.healAbsorb) then
		local cacheGuid = UnitGUID and UnitGUID(unit) or unit
		local guidComparable = not (issecretvalue and issecretvalue(cacheGuid))
		if not guidComparable then
			st._absorbCacheGuid = nil
			st._absorbAmount = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0
			st._healAbsorbAmount = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit) or 0
		elseif st._absorbCacheGuid ~= cacheGuid then
			st._absorbCacheGuid = cacheGuid
			st._absorbAmount = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0
			st._healAbsorbAmount = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit) or 0
		end
	end
	if allowAbsorb and st.absorb then
		local abs = st._absorbAmount
		if abs == nil then
			abs = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0
			st._absorbAmount = abs
		end
		local maxForValue
		if issecretvalue and issecretvalue(maxv) then
			maxForValue = maxv or 1
		else
			maxForValue = (maxv and maxv > 0) and maxv or 1
		end
		st.absorb:SetMinMaxValues(0, maxForValue or 1)
		local hasVisibleAbsorb = abs and (not issecretvalue or not issecretvalue(abs)) and abs > 0
		if shouldShowSampleAbsorb(unit) and not hasVisibleAbsorb and (not issecretvalue or not issecretvalue(maxForValue)) then abs = (maxForValue or 1) * 0.6 end
		st.absorb:SetValue(abs or 0, interpolation)
		local reverseAbsorb = hc.absorbReverseFill
		if reverseAbsorb == nil then reverseAbsorb = defH.absorbReverseFill == true end
		if reverseAbsorb and st.absorb2 then
			local _, maxHealth = st.health:GetMinMaxValues()
			if maxHealth == nil then maxHealth = maxForValue end
			st.absorb2:SetMinMaxValues(0, maxHealth or 1)
			st.absorb2:SetValue(abs or 0, interpolation)
		end
		if reverseAbsorb and st.absorb2 then
			st.absorb2:Show()
			if st.absorb then st.absorb:Show() end
		elseif st.absorb then
			st.absorb:SetAlpha(1)
			st.absorb:Show()
			if st.absorb2 then
				st.absorb2:SetAlpha(0)
				st.absorb2:Show()
			end
		end
		local ar, ag, ab, aa = UFHelper.getAbsorbColor(hc, defH)
		st.absorb:SetStatusBarColor(ar or 0.85, ag or 0.95, ab or 1, aa or 0.7)
		if reverseAbsorb and st.absorb2 then st.absorb2:SetStatusBarColor(ar or 0.85, ag or 0.95, ab or 1, aa or 0.7) end
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
	if allowAbsorb and st.healAbsorb then
		local healAbs = st._healAbsorbAmount
		if healAbs == nil then
			healAbs = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit) or 0
			st._healAbsorbAmount = healAbs
		end
		local maxForValue
		if issecretvalue and issecretvalue(maxv) then
			maxForValue = maxv or 1
		else
			maxForValue = (maxv and maxv > 0) and maxv or 1
		end
		st.healAbsorb:SetMinMaxValues(0, maxForValue or 1)
		local hasVisibleHealAbsorb = healAbs and (not issecretvalue or not issecretvalue(healAbs)) and healAbs > 0
		if shouldShowSampleHealAbsorb(unit) and not hasVisibleHealAbsorb and (not issecretvalue or not issecretvalue(maxForValue)) then healAbs = (maxForValue or 1) * 0.6 end
		if not issecretvalue or (not issecretvalue(cur) and not issecretvalue(healAbs)) then
			if (cur or 0) < (healAbs or 0) then healAbs = cur or 0 end
		end
		st.healAbsorb:SetValue(healAbs or 0, interpolation)
		local har, hag, hab, haa = UFHelper.getHealAbsorbColor(hc, defH)
		st.healAbsorb:SetStatusBarColor(har or 1, hag or 0.3, hab or 0.3, haa or 0.7)
	end
	st._healthTextDirty = true
end

local function updatePower(cfg, unit)
	cfg = cfg or (states[unit] and states[unit].cfg) or ensureDB(unit)
	if cfg and cfg.enabled == false then return end
	local st = states[unit]
	if not st then return end
	local bar = st.power
	if not bar then return end
	local def = defaultsFor(unit) or {}
	local interpolation = getSmoothInterpolation(cfg, def)
	local pcfg = cfg.power or {}
	local powerDetached = pcfg.detached == true
	if pcfg.enabled == false then
		bar:Hide()
		bar:SetValue(0, interpolation)
		if st.powerTextLeft then st.powerTextLeft:SetText("") end
		if st.powerTextCenter then st.powerTextCenter:SetText("") end
		if st.powerTextRight then st.powerTextRight:SetText("") end
		st._powerTextDirty = nil
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
	bar:SetValue(cur or 0, interpolation)
	local powerColorDirty = st._powerColorDirty
	if not powerColorDirty and st._powerColorEnum ~= powerEnum then powerColorDirty = true end
	if not powerColorDirty and st._powerColorToken ~= powerToken then powerColorDirty = true end
	if powerColorDirty or st._powerColorR == nil then
		local cr, cg, cb, ca = UFHelper.getPowerColor(powerEnum, powerToken)
		st._powerColorR, st._powerColorG, st._powerColorB, st._powerColorA = cr, cg, cb, ca
		st._powerColorDesaturated = UFHelper.isPowerDesaturated(powerEnum, powerToken)
		st._powerColorEnum = powerEnum
		st._powerColorToken = powerToken
		st._powerColorDirty = nil
	end
	bar:SetStatusBarColor(st._powerColorR or 0.1, st._powerColorG or 0.45, st._powerColorB or 1, st._powerColorA or 1)
	if bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(st._powerColorDesaturated == true) end
	local emptyFallback = pcfg.emptyMaxFallback == true
	if emptyFallback then
		if powerDetached then
			if bar.SetAlpha then bar:SetAlpha(maxv) end
			if st.powerGroup and st.powerGroup.SetAlpha then st.powerGroup:SetAlpha(maxv) end
		end
	elseif powerDetached then
		if bar.SetAlpha then bar:SetAlpha(1) end
		if st.powerGroup and st.powerGroup.SetAlpha then st.powerGroup:SetAlpha(1) end
	end
	st._powerTextDirty = true
end

local function layoutTexts(bar, leftFS, centerFS, rightFS, cfg, width)
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
	child:SetFrameStrata(parent:GetFrameStrata())
	local level = (parent:GetFrameLevel() or 0) + (offset or 1)
	if level < 0 then level = 0 end
	child:SetFrameLevel(level)
end

function UF.syncAbsorbFrameLevels(st)
	if not st or not st.health then return end
	local health = st.health
	local healthLevel = (health.GetFrameLevel and health:GetFrameLevel()) or 0
	local overlayLevel = max(0, healthLevel + 1)
	local healthStrata = health.GetFrameStrata and health:GetFrameStrata()
	local borderFrame = st.barGroup and st.barGroup._ufBorder
	if borderFrame and borderFrame.GetFrameLevel then
		local borderLevel = borderFrame:GetFrameLevel() or (overlayLevel + 1)
		if overlayLevel >= borderLevel then overlayLevel = max(0, borderLevel - 1) end
	end
	local function apply(frame)
		if not frame then return end
		if healthStrata and frame.SetFrameStrata and frame:GetFrameStrata() ~= healthStrata then frame:SetFrameStrata(healthStrata) end
		if frame.SetFrameLevel and frame:GetFrameLevel() ~= overlayLevel then frame:SetFrameLevel(overlayLevel) end
	end
	apply(health.absorbClip)
	apply(health._healthFillClip)
	apply(st.absorb)
	apply(st.absorb2)
	apply(st.healAbsorb)
	if borderFrame and st.barGroup and borderFrame.SetFrameStrata and st.barGroup.GetFrameStrata then
		local borderStrata = st.barGroup:GetFrameStrata()
		if borderStrata and borderFrame:GetFrameStrata() ~= borderStrata then borderFrame:SetFrameStrata(borderStrata) end
	end
	if borderFrame and borderFrame.SetFrameLevel then
		local desiredBorderLevel = overlayLevel + 1
		if borderFrame:GetFrameLevel() < desiredBorderLevel then borderFrame:SetFrameLevel(desiredBorderLevel) end
	end
end

local function getHealthTextAnchor(st, includeStatus)
	if not st or not st.health then return nil end
	local anchor = st.health
	local maxLevel = (anchor.GetFrameLevel and anchor:GetFrameLevel()) or 0
	local function consider(frame)
		if not frame or not frame.GetFrameLevel then return end
		local level = frame:GetFrameLevel() or 0
		if level > maxLevel then
			maxLevel = level
			anchor = frame
		end
	end
	consider(st.health.absorbClip)
	consider(st.health._healthFillClip)
	if includeStatus then consider(st.status) end
	return anchor
end

local STRATA_ORDER = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
local STRATA_INDEX = {}
for i = 1, #STRATA_ORDER do
	STRATA_INDEX[STRATA_ORDER[i]] = i
end

normalizeStrataToken = function(value)
	if type(value) ~= "string" or value == "" then return nil end
	local token = string.upper(value)
	if STRATA_INDEX[token] then return token end
	return nil
end

local function syncTextFrameLevels(st)
	if not st then return end
	local scfg = (st.cfg and st.cfg.status) or {}
	local healthAnchor = getHealthTextAnchor(st) or st.health
	local statusAnchor = getHealthTextAnchor(st, true) or st.status or healthAnchor
	setFrameLevelAbove(st.healthTextLayer, healthAnchor, 5)
	setFrameLevelAbove(st.powerTextLayer, st.power, 5)
	setFrameLevelAbove(st.statusTextLayer, statusAnchor, 5)
	local levelLayer = st.levelTextLayer or st.statusTextLayer
	local levelOffset = tonumber(scfg.levelFrameLevelOffset)
	if levelOffset == nil then levelOffset = 5 end
	setFrameLevelAbove(levelLayer, statusAnchor, levelOffset)
	if levelLayer and levelLayer.SetFrameStrata then
		local levelStrata = normalizeStrataToken(scfg.levelStrata)
		local fallbackStrata
		if statusAnchor and statusAnchor.GetFrameStrata then fallbackStrata = statusAnchor:GetFrameStrata() end
		if not fallbackStrata and st.status and st.status.GetFrameStrata then fallbackStrata = st.status:GetFrameStrata() end
		if levelStrata or fallbackStrata then levelLayer:SetFrameStrata(levelStrata or fallbackStrata) end
	end
	if st.restLoop and st.statusTextLayer then setFrameLevelAbove(st.restLoop, st.statusTextLayer, 3) end
	if st.castTextLayer then setFrameLevelAbove(st.castTextLayer, st.castBar, 5) end
	if st.castIconLayer then setFrameLevelAbove(st.castIconLayer, st.castBar, 4) end
	if UFHelper and UFHelper.syncCombatFeedbackLayer then UFHelper.syncCombatFeedbackLayer(st) end
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
	hookFrame(st.castBar)
	syncTextFrameLevels(st)
end

local function getPlayerSubGroup()
	if not IsInRaid then return nil end
	if not IsInRaid() then return nil end
	local idx = UnitInRaid and UnitInRaid(UNIT.PLAYER)
	if not idx then return nil end
	local _, _, subgroup = GetRaidRosterInfo(idx)
	return subgroup
end

local function formatGroupNumber(subgroup, format)
	local num = tonumber(subgroup)
	if not num then return nil end
	local fmt = format or "GROUP"
	if fmt == "NUMBER" then return tostring(num) end
	if fmt == "PARENS" then return "(" .. num .. ")" end
	if fmt == "BRACKETS" then return "[" .. num .. "]" end
	if fmt == "BRACES" then return "{" .. num .. "}" end
	if fmt == "PIPE" then return "|| " .. num .. " ||" end
	if fmt == "ANGLE" then return "<" .. num .. ">" end
	if fmt == "G" then return "G" .. num end
	if fmt == "G_SPACE" then return "G " .. num end
	if fmt == "HASH" then return "#" .. num end
	return string.format(GROUP_NUMBER or "Group %d", num)
end

local function updateUnitStatusIndicator(cfg, unit)
	cfg = cfg or (states[unit] and states[unit].cfg) or ensureDB(unit)
	local st = states[unit]
	if not st or (not st.unitStatusText and not st.unitGroupText) then return end
	if cfg.enabled == false then
		if st.unitStatusText then
			st.unitStatusText:SetText("")
			st.unitStatusText:Hide()
		end
		if st.unitGroupText then
			st.unitGroupText:SetText("")
			st.unitGroupText:Hide()
		end
		return
	end
	local def = defaultsFor(unit) or {}
	local defStatus = def.status or {}
	local scfg = cfg.status or {}
	local usDef = defStatus.unitStatus or {}
	local usCfg = scfg.unitStatus or usDef or {}
	if usCfg.enabled ~= true then
		if st.unitStatusText then
			st.unitStatusText:SetText("")
			st.unitStatusText:Hide()
		end
		if st.unitGroupText then
			st.unitGroupText:SetText("")
			st.unitGroupText:Hide()
		end
		return
	end
	local inEditMode = addon.EditModeLib and addon.EditModeLib:IsInEditMode()
	local allowSample = inEditMode and not isBossUnit(unit)
	if UnitExists and not UnitExists(unit) and not allowSample then
		if st.unitStatusText then
			st.unitStatusText:SetText("")
			st.unitStatusText:Hide()
		end
		if st.unitGroupText then
			st.unitGroupText:SetText("")
			st.unitGroupText:Hide()
		end
		return
	end
	local statusTag
	local connected = UnitIsConnected and UnitIsConnected(unit)
	if issecretvalue and issecretvalue(connected) then connected = nil end
	local isAFK = UnitIsAFK and UnitIsAFK(unit)
	if issecretvalue and issecretvalue(isAFK) then isAFK = nil end
	local isDND = UnitIsDND and UnitIsDND(unit)
	if issecretvalue and issecretvalue(isDND) then isDND = nil end
	if connected == false then
		statusTag = PLAYER_OFFLINE or "Offline"
	elseif isAFK == true then
		statusTag = DEFAULT_AFK_MESSAGE or "AFK"
	elseif isDND == true then
		statusTag = DEFAULT_DND_MESSAGE or "DND"
	end
	if not statusTag and allowSample then statusTag = DEFAULT_AFK_MESSAGE or "AFK" end
	if st.unitStatusText then
		st.unitStatusText:SetText(statusTag or "")
		st.unitStatusText:SetShown(statusTag ~= nil)
	end

	local groupTag
	if unit == UNIT.PLAYER and usCfg.showGroup == true then
		local subgroup = getPlayerSubGroup()
		local groupFormat = usCfg.groupFormat or usDef.groupFormat or "GROUP"
		if subgroup then
			groupTag = formatGroupNumber(subgroup, groupFormat)
		elseif addon.EditModeLib and addon.EditModeLib:IsInEditMode() then
			groupTag = formatGroupNumber(1, groupFormat)
		end
	end
	if st.unitGroupText then
		st.unitGroupText:SetText(groupTag or "")
		st.unitGroupText:SetShown(groupTag ~= nil)
	end
end

local function shouldShowLevel(scfg, unit)
	if not scfg or scfg.levelEnabled == false then return false end
	if scfg.hideLevelAtMax and addon.variables and addon.variables.isMaxLevel then
		local level = UnitLevel(unit) or 0
		if addon.variables.isMaxLevel[level] then return false end
	end
	return true
end

shouldHideClassificationText = function(cfg, unit)
	if unit == UNIT.PLAYER or not cfg then return false end
	local scfg = cfg.status or {}
	local icfg = scfg.classificationIcon or {}
	return icfg.enabled == true and icfg.hideText == true
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
	local showLevel = shouldShowLevel(scfg, unit)
	local showUnitStatus = usCfg.enabled == true
	local showStatus = showName or showLevel or showUnitStatus or (unit == UNIT.PLAYER and ciCfg.enabled ~= false)
	local statusHeight = showStatus and (cfg.statusHeight or def.statusHeight) or 0.001
	st.status:SetHeight(statusHeight)
	st.status:SetShown(showStatus)
	local nameFontSize = scfg.nameFontSize or scfg.fontSize or 14
	local levelFontSize = scfg.levelFontSize or scfg.fontSize or 14
	local statusFontSize = scfg.fontSize or nameFontSize or levelFontSize or 14
	if st.nameText then
		UFHelper.applyFont(st.nameText, scfg.font, nameFontSize, scfg.fontOutline)
		local nameAnchor = scfg.nameAnchor or "LEFT"
		st.nameText:ClearAllPoints()
		st.nameText:SetPoint(nameAnchor, st.status, nameAnchor, (scfg.nameOffset and scfg.nameOffset.x) or 0, (scfg.nameOffset and scfg.nameOffset.y) or 0)
		if st.nameText.SetJustifyH then st.nameText:SetJustifyH(nameAnchor) end
		st.nameText:SetShown(showName)
		UFHelper.applyNameCharLimit(st, scfg, defStatus)
	end
	if st.levelText then
		UFHelper.applyFont(st.levelText, scfg.font, levelFontSize, scfg.fontOutline)
		st.levelText:ClearAllPoints()
		st.levelText:SetPoint(scfg.levelAnchor or "RIGHT", st.status, scfg.levelAnchor or "RIGHT", (scfg.levelOffset and scfg.levelOffset.x) or 0, (scfg.levelOffset and scfg.levelOffset.y) or 0)
		st.levelText:SetShown(showStatus and showLevel)
	end
	if st.unitStatusText then
		local unitStatusFont = usCfg.font or scfg.font
		local unitStatusFontSize = usCfg.fontSize or statusFontSize
		local unitStatusFontOutline = usCfg.fontOutline or scfg.fontOutline
		UFHelper.applyFont(st.unitStatusText, unitStatusFont, unitStatusFontSize, unitStatusFontOutline)
		local off = usCfg.offset or usDef.offset or {}
		st.unitStatusText:ClearAllPoints()
		st.unitStatusText:SetPoint("CENTER", st.status, "CENTER", off.x or 0, off.y or 0)
		if st.unitStatusText.SetJustifyH then st.unitStatusText:SetJustifyH("CENTER") end
		if st.unitStatusText.SetWordWrap then st.unitStatusText:SetWordWrap(false) end
		if st.unitStatusText.SetMaxLines then st.unitStatusText:SetMaxLines(1) end
	end
	if st.unitGroupText then
		local unitStatusFont = usCfg.font or scfg.font
		local unitStatusFontOutline = usCfg.fontOutline or scfg.fontOutline
		local groupFontSize = usCfg.groupFontSize or usCfg.fontSize or statusFontSize
		local groupOff = usCfg.groupOffset or usDef.groupOffset or {}
		UFHelper.applyFont(st.unitGroupText, unitStatusFont, groupFontSize, unitStatusFontOutline)
		st.unitGroupText:ClearAllPoints()
		st.unitGroupText:SetPoint("CENTER", st.status, "CENTER", groupOff.x or 0, groupOff.y or 0)
		if st.unitGroupText.SetJustifyH then st.unitGroupText:SetJustifyH("CENTER") end
		if st.unitGroupText.SetWordWrap then st.unitGroupText:SetWordWrap(false) end
		if st.unitGroupText.SetMaxLines then st.unitGroupText:SetMaxLines(1) end
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
	st.combatIcon:SetTexture("Interface\\Addons\\EnhanceQoL\\Assets\\CombatIndicator.tga")
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
	local centerOffset = (st and st._portraitCenterOffset) or 0
	st.restLoop:SetPoint("CENTER", st.barGroup or st.frame, "CENTER", (ox or 0) + centerOffset, oy)
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
	local side = (pcfg.side or pdef.side or "LEFT"):upper()
	if side ~= "RIGHT" then side = "LEFT" end
	local squareBackground = pcfg.squareBackground
	if squareBackground == nil then squareBackground = pdef.squareBackground end
	return enabled == true, side, squareBackground == true
end

local function getPortraitSeparatorConfig(cfg, unit, portraitEnabled)
	if not portraitEnabled or not cfg or cfg.enabled == false then return false, 0, "SOLID" end
	local def = defaultsFor(unit)
	local borderDef = def and def.border or {}
	local borderCfg = cfg.border or {}
	if not UF._isFrameBorderEnabled(borderCfg, borderDef, true) then return false, 0, "SOLID" end
	local pdef = def and def.portrait or {}
	local pcfg = (cfg and cfg.portrait) or {}
	local sdef = pdef.separator or {}
	local scfg = pcfg.separator or {}
	local enabled = scfg.enabled
	if enabled == nil then enabled = sdef.enabled end
	if enabled == nil then enabled = true end
	if enabled ~= true then return false, 0, "SOLID" end
	local size = scfg.size
	if size == nil then size = sdef.size end
	if not size or size <= 0 then size = borderCfg.edgeSize or 1 end
	size = max(1, size or 1)
	local texture = scfg.texture
	if not texture or texture == "" then texture = sdef.texture end
	if not texture or texture == "" then texture = "SOLID" end
	local useCustomColor = scfg.useCustomColor
	if useCustomColor == nil then useCustomColor = sdef.useCustomColor end
	local color
	if useCustomColor == true then
		color = scfg.color
		if color == nil then color = sdef.color end
	end
	if not color then color = borderCfg.color or borderDef.color or { 0, 0, 0, 0.8 } end
	return true, size, texture, color
end

local function applyPortraitSeparator(cfg, unit, st, portraitEnabled)
	if not st or not st.portraitSeparator or not st.portraitHolder then return end
	if UnitExists and not UnitExists(unit) then
		st.portraitSeparator:Hide()
		return
	end
	local separatorEnabled, separatorSize, separatorTexture, separatorColor = getPortraitSeparatorConfig(cfg, unit, portraitEnabled)
	if not separatorEnabled or not separatorSize or separatorSize <= 0 then
		st.portraitSeparator:Hide()
		return
	end
	local color = separatorColor or { 0, 0, 0, 0.8 }
	st.portraitSeparator:SetTexture(UFHelper.resolveSeparatorTexture(separatorTexture))
	st.portraitSeparator:SetVertexColor(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
	st.portraitSeparator:ClearAllPoints()
	local side = st._portraitSide or "LEFT"
	if side == "RIGHT" then
		st.portraitSeparator:SetPoint("TOP", st.portraitHolder, "TOP", 0, 0)
		st.portraitSeparator:SetPoint("BOTTOM", st.portraitHolder, "BOTTOM", 0, 0)
		st.portraitSeparator:SetPoint("RIGHT", st.portraitHolder, "LEFT", 0, 0)
	else
		st.portraitSeparator:SetPoint("TOP", st.portraitHolder, "TOP", 0, 0)
		st.portraitSeparator:SetPoint("BOTTOM", st.portraitHolder, "BOTTOM", 0, 0)
		st.portraitSeparator:SetPoint("LEFT", st.portraitHolder, "RIGHT", 0, 0)
	end
	st.portraitSeparator:SetWidth(separatorSize)
	st.portraitSeparator:Show()
end

local function updatePortrait(cfg, unit)
	cfg = cfg or (states[unit] and states[unit].cfg) or ensureDB(unit)
	local st = states[unit]
	if not st or not st.portrait then return end
	local enabled, _, squareBackground = getPortraitConfig(cfg, unit)
	if not enabled or cfg.enabled == false then
		st.portrait:Hide()
		st.portrait:SetTexture(nil)
		if st.portraitBg then st.portraitBg:Hide() end
		if st.portraitHolder then st.portraitHolder:Hide() end
		applyPortraitSeparator(cfg, unit, st, false)
		return
	end
	if UnitExists and not UnitExists(unit) then
		st.portrait:Hide()
		st.portrait:SetTexture(nil)
		if st.portraitBg then st.portraitBg:Hide() end
		if st.portraitHolder then st.portraitHolder:Hide() end
		applyPortraitSeparator(cfg, unit, st, false)
		return
	end
	SetPortraitTexture(st.portrait, unit)
	st.portrait:Show()
	if st.portraitHolder then st.portraitHolder:Show() end
	if st.portraitBg then
		if squareBackground == true then
			st.portraitBg:Show()
		else
			st.portraitBg:Hide()
		end
	end
	applyPortraitSeparator(cfg, unit, st, true)
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
	local showLevel = shouldShowLevel(scfg, unit)
	local showUnitStatus = usCfg.enabled == true
	local showStatus = showName or showLevel or showUnitStatus or (unit == UNIT.PLAYER and ciCfg.enabled ~= false)
	local pcfg = cfg.power or {}
	local powerDef = def.power or {}
	local powerEnabled = pcfg.enabled ~= false
	local powerDetached = powerEnabled and pcfg.detached == true
	local width = max(MIN_WIDTH, cfg.width or def.width)
	local statusHeight = showStatus and (cfg.statusHeight or def.statusHeight) or 0
	local healthHeight = cfg.healthHeight or def.healthHeight
	local powerHeight = powerEnabled and (cfg.powerHeight or def.powerHeight) or 0
	local stackHeight = healthHeight + (powerDetached and 0 or powerHeight)
	local borderCfg = cfg.border or {}
	local borderDef = def.border or {}
	local borderEnabled = UF._isFrameBorderEnabled(borderCfg, borderDef, true)
	local borderOffset = 0
	if borderEnabled then
		borderOffset = borderCfg.offset
		if borderOffset == nil then borderOffset = borderCfg.edgeSize or borderDef.edgeSize or 1 end
		borderOffset = max(0, borderOffset or 0)
	end
	local detachedPowerBorder = powerDetached and powerEnabled and borderCfg.detachedPower == true
	local detachedPowerOffset = 0
	if detachedPowerBorder then
		detachedPowerOffset = borderCfg.detachedPowerOffset
		if detachedPowerOffset == nil then detachedPowerOffset = borderCfg.offset end
		if detachedPowerOffset == nil then detachedPowerOffset = borderCfg.edgeSize or borderDef.edgeSize or 1 end
		detachedPowerOffset = max(0, detachedPowerOffset or 0)
	end
	local portraitEnabled, portraitSide, portraitSquareBackground = getPortraitConfig(cfg, unit)
	local portraitInnerHeight = stackHeight
	local portraitSize = portraitEnabled and max(1, portraitInnerHeight) or 0
	local separatorEnabled, separatorSize = getPortraitSeparatorConfig(cfg, unit, portraitEnabled)
	local separatorSpace = separatorEnabled and separatorSize or 0
	local portraitSpace = portraitEnabled and (portraitSize + separatorSpace) or 0
	local barAreaOffsetLeft = (portraitEnabled and portraitSide == "LEFT") and portraitSpace or 0
	local barAreaOffsetRight = (portraitEnabled and portraitSide == "RIGHT") and portraitSpace or 0
	local barCenterOffset = 0
	if portraitEnabled and portraitSpace > 0 then barCenterOffset = (portraitSide == "LEFT") and (portraitSpace / 2) or -(portraitSpace / 2) end
	local statusOffsetLeft = barAreaOffsetLeft
	local statusOffsetRight = -barAreaOffsetRight
	st._portraitSpace = portraitSpace
	st._portraitCenterOffset = barCenterOffset
	st.frame:SetWidth(width + borderOffset * 2 + portraitSpace)
	local frameStrata = normalizeStrataToken(cfg.strata) or normalizeStrataToken(def.strata) or "LOW"
	if st.frame.GetFrameStrata and st.frame:GetFrameStrata() ~= frameStrata then st.frame:SetFrameStrata(frameStrata) end
	local selection = st.frame.Selection
	if selection and selection.SetFrameStrata then
		if not st._selectionBaseStrata then
			local baseStrata = (selection.GetFrameStrata and selection:GetFrameStrata()) or "MEDIUM"
			st._selectionBaseStrata = baseStrata
			st._selectionBaseStrataIndex = STRATA_INDEX[baseStrata] or STRATA_INDEX.MEDIUM
		end
		local baseIndex = st._selectionBaseStrataIndex or STRATA_INDEX.MEDIUM
		local targetIndex = cfg.strata and STRATA_INDEX[cfg.strata]
		local targetStrata = (targetIndex and targetIndex > baseIndex) and cfg.strata or st._selectionBaseStrata
		if targetStrata and selection.GetFrameStrata and selection:GetFrameStrata() ~= targetStrata then selection:SetFrameStrata(targetStrata) end
	end
	if cfg.frameLevel then
		st.frame:SetFrameLevel(cfg.frameLevel)
	else
		local pf = _G.PlayerFrame
		if pf and pf.GetFrameLevel then st.frame:SetFrameLevel(pf:GetFrameLevel()) end
	end
	local frameLevel = (st.frame and st.frame.GetFrameLevel and st.frame:GetFrameLevel()) or 0
	if st.status.SetFrameStrata and st.status:GetFrameStrata() ~= frameStrata then st.status:SetFrameStrata(frameStrata) end
	if st.barGroup and st.barGroup.SetFrameStrata and st.barGroup:GetFrameStrata() ~= frameStrata then st.barGroup:SetFrameStrata(frameStrata) end
	if st.health.SetFrameStrata and st.health:GetFrameStrata() ~= frameStrata then st.health:SetFrameStrata(frameStrata) end
	if st.status.SetFrameLevel then st.status:SetFrameLevel(frameLevel + 1) end
	if st.barGroup and st.barGroup.SetFrameLevel then st.barGroup:SetFrameLevel(frameLevel + 1) end
	if st.health.SetFrameLevel then st.health:SetFrameLevel(frameLevel + 2) end
	st.status:SetHeight(statusHeight)
	st.health:SetSize(width, healthHeight)
	local detachedGrowFromCenter = powerDetached and pcfg.detachedGrowFromCenter == true
	local detachedMatchHealthWidth = powerDetached and pcfg.detachedMatchHealthWidth == true
	local powerWidth = width
	if powerDetached and not detachedMatchHealthWidth and pcfg.width and pcfg.width > 0 then powerWidth = pcfg.width end
	st.power:SetSize(powerWidth, powerHeight)
	st.power:SetShown(powerEnabled)

	st.status:ClearAllPoints()
	if st.barGroup then st.barGroup:ClearAllPoints() end
	st.health:ClearAllPoints()
	st.power:ClearAllPoints()
	if st.powerGroup then st.powerGroup:ClearAllPoints() end

	local anchor = cfg.anchor or def.anchor or defaults.player.anchor
	if isBossUnit(unit) then
		local container = ensureBossContainer() or UIParent
		if st.frame.SetParent then st.frame:SetParent(container) end
		if st.frame:GetNumPoints() == 0 then st.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0) end
	else
		local rel = resolveRelativeAnchorFrame(anchor and anchor.relativeTo)
		st.frame:ClearAllPoints()
		st.frame:SetPoint(anchor.point or "CENTER", rel or UIParent, anchor.relativePoint or anchor.point or "CENTER", anchor.x or 0, anchor.y or 0)
	end

	local y = 0
	if statusHeight > 0 then
		st.status:SetPoint("TOPLEFT", st.frame, "TOPLEFT", statusOffsetLeft, 0)
		st.status:SetPoint("TOPRIGHT", st.frame, "TOPRIGHT", statusOffsetRight, 0)
		y = -statusHeight
	else
		st.status:SetPoint("TOPLEFT", st.frame, "TOPLEFT", statusOffsetLeft, 0)
		st.status:SetPoint("TOPRIGHT", st.frame, "TOPRIGHT", statusOffsetRight, 0)
	end
	-- Bars container sits below status; border applied here, not on status
	local barsHeight = stackHeight + borderOffset * 2
	if st.barGroup then
		st.barGroup:SetWidth(width + borderOffset * 2 + portraitSpace)
		st.barGroup:SetHeight(barsHeight)
		st.barGroup:SetPoint("TOPLEFT", st.frame, "TOPLEFT", 0, y)
		st.barGroup:SetPoint("TOPRIGHT", st.frame, "TOPRIGHT", 0, y)
	end

	local barInsetLeft = borderOffset + barAreaOffsetLeft
	local barInsetRight = borderOffset + barAreaOffsetRight
	st.health:SetPoint("TOPLEFT", st.barGroup or st.frame, "TOPLEFT", barInsetLeft, -borderOffset)
	st.health:SetPoint("TOPRIGHT", st.barGroup or st.frame, "TOPRIGHT", -barInsetRight, -borderOffset)
	if powerDetached then
		local off = pcfg.offset or {}
		local ox = off.x or 0
		local oy = off.y or 0
		local centerOx = detachedGrowFromCenter and (ox - (st._portraitCenterOffset or 0)) or ox
		if detachedPowerBorder and st.powerGroup then
			if st.power.GetParent and st.power:GetParent() ~= st.powerGroup then st.power:SetParent(st.powerGroup) end
			st.powerGroup:Show()
			st.powerGroup:SetSize(powerWidth + detachedPowerOffset * 2, powerHeight + detachedPowerOffset * 2)
			if detachedGrowFromCenter then
				st.powerGroup:SetPoint("TOP", st.health, "BOTTOM", centerOx, oy + detachedPowerOffset)
				st.power:SetPoint("TOP", st.powerGroup, "TOP", 0, -detachedPowerOffset)
			else
				st.powerGroup:SetPoint("TOPLEFT", st.health, "BOTTOMLEFT", ox - detachedPowerOffset, oy + detachedPowerOffset)
				st.power:SetPoint("TOPLEFT", st.powerGroup, "TOPLEFT", detachedPowerOffset, -detachedPowerOffset)
			end
		else
			if st.powerGroup then st.powerGroup:Hide() end
			if st.power.GetParent and st.power:GetParent() ~= st.barGroup then st.power:SetParent(st.barGroup) end
			if detachedGrowFromCenter then
				st.power:SetPoint("TOP", st.health, "BOTTOM", centerOx, oy)
			else
				st.power:SetPoint("TOPLEFT", st.health, "BOTTOMLEFT", ox, oy)
			end
		end
	else
		if st.powerGroup then st.powerGroup:Hide() end
		if st.power.GetParent and st.power:GetParent() ~= st.barGroup then st.power:SetParent(st.barGroup) end
		st.power:SetPoint("TOPLEFT", st.health, "BOTTOMLEFT", 0, 0)
		st.power:SetPoint("TOPRIGHT", st.health, "BOTTOMRIGHT", 0, 0)
	end
	local powerStrata = frameStrata
	if powerDetached then
		local detachedStrata = pcfg.detachedStrata
		if detachedStrata == nil then detachedStrata = powerDef.detachedStrata end
		detachedStrata = normalizeStrataToken(detachedStrata)
		if detachedStrata then powerStrata = detachedStrata end
	end
	if st.power.SetFrameStrata and st.power:GetFrameStrata() ~= powerStrata then st.power:SetFrameStrata(powerStrata) end
	if st.powerGroup and st.powerGroup.SetFrameStrata and st.powerGroup:GetFrameStrata() ~= powerStrata then st.powerGroup:SetFrameStrata(powerStrata) end
	local healthLevel = (st.health and st.health.GetFrameLevel and st.health:GetFrameLevel()) or (frameLevel + 2)
	local powerLevel = healthLevel
	if powerDetached then
		local levelOffset = pcfg.detachedFrameLevelOffset
		if levelOffset == nil then levelOffset = powerDef.detachedFrameLevelOffset end
		levelOffset = levelOffset or 0
		powerLevel = max(0, frameLevel + levelOffset)
		if powerLevel <= healthLevel then powerLevel = healthLevel + 1 end
	end
	if st.power.SetFrameLevel then st.power:SetFrameLevel(powerLevel) end
	if st.powerGroup and st.powerGroup.SetFrameLevel then
		local groupLevel = powerLevel
		if powerDetached then groupLevel = max(0, powerLevel - 1) end
		st.powerGroup:SetFrameLevel(groupLevel)
	end

	st._portraitSide = portraitSide
	st._portraitSize = portraitSize
	if st.portraitHolder then
		if portraitEnabled then
			local holderParent = st.barGroup or st.frame
			local holderOffset = borderOffset + (portraitSize / 2)
			st.portraitHolder:SetSize(portraitSize, portraitSize)
			st.portraitHolder:ClearAllPoints()
			if portraitSide == "RIGHT" then
				st.portraitHolder:SetPoint("CENTER", holderParent, "RIGHT", -holderOffset, 0)
			else
				st.portraitHolder:SetPoint("CENTER", holderParent, "LEFT", holderOffset, 0)
			end
			if holderParent and holderParent.GetFrameStrata then
				st.portraitHolder:SetFrameStrata(holderParent:GetFrameStrata())
				st.portraitHolder:SetFrameLevel((holderParent:GetFrameLevel() or 0) + 1)
			end
			if st.portrait then
				st.portrait:SetSize(portraitSize, portraitSize)
				st.portrait:ClearAllPoints()
				st.portrait:SetPoint("CENTER", st.portraitHolder, "CENTER", 0, 0)
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
			if st.portrait then st.portrait:Hide() end
			if st.portraitBg then st.portraitBg:Hide() end
			st.portraitHolder:Hide()
		end
	end
	applyPortraitSeparator(cfg, unit, st, portraitEnabled)

	local totalHeight = statusHeight + barsHeight
	st.frame:SetHeight(totalHeight)
	if st.raidIcon then
		st.raidIcon:ClearAllPoints()
		st.raidIcon:SetPoint("TOP", st.barGroup or st.frame, "TOP", barCenterOffset or 0, -2)
	end

	layoutTexts(st.health, st.healthTextLeft, st.healthTextCenter, st.healthTextRight, cfg.health, width)
	layoutTexts(st.power, st.powerTextLeft, st.powerTextCenter, st.powerTextRight, cfg.power, width)
	if st.castBar and unit == UNIT.TARGET then applyCastLayout(cfg, unit) end

	-- Apply border only around the bar region wrapper
	if st.barGroup then setBackdrop(st.barGroup, cfg.border, borderDef, true) end
	if st.powerGroup then
		local showPowerBorder = detachedPowerBorder and powerEnabled
		local powerBorderCfg
		if showPowerBorder then
			local borderTexture = borderCfg.detachedPowerTexture or borderCfg.texture or borderDef.texture or "DEFAULT"
			local borderSize = borderCfg.detachedPowerSize
			if borderSize == nil then borderSize = borderCfg.edgeSize or borderDef.edgeSize or 1 end
			powerBorderCfg = {
				enabled = true,
				texture = borderTexture,
				edgeSize = borderSize,
				color = borderCfg.color or borderDef.color,
				inset = borderCfg.inset or borderDef.inset,
			}
		end
		setBackdrop(st.powerGroup, powerBorderCfg, nil, false)
	end
	UF.syncAbsorbFrameLevels(st)
	UFHelper.applyHighlightStyle(st, st._highlightCfg)

	if (unit == UNIT.PLAYER or unit == "target" or unit == UNIT.FOCUS or isBossUnit(unit)) and st.auraContainer then
		st.auraContainer:ClearAllPoints()
		local acfg = cfg.auraIcons or def.auraIcons or defaults.target.auraIcons or {}
		local anchor = acfg.anchor or "BOTTOM"
		local defAx, defAy = UF._auraLayout.defaultOffset(anchor)
		local baseAx = (acfg.offset and acfg.offset.x)
		if baseAx == nil then baseAx = defAx end
		local baseAy = (acfg.offset and acfg.offset.y)
		if baseAy == nil then baseAy = defAy end
		UF._auraLayout.positionContainer(st.auraContainer, anchor, st.barGroup, baseAx, baseAy, barAreaOffsetLeft, barAreaOffsetRight)
		st.auraContainer:SetWidth(width + borderOffset * 2)

		if st.debuffContainer then
			st.debuffContainer:ClearAllPoints()
			local useSeparateDebuffs = acfg.separateDebuffAnchor == true
			local danchor = acfg.debuffAnchor or anchor
			local defDax, defDay = UF._auraLayout.defaultOffset(danchor)
			local baseDax = (acfg.debuffOffset and acfg.debuffOffset.x)
			if baseDax == nil then baseDax = baseAx end
			if baseDax == nil then baseDax = defDax end
			local baseDay = (acfg.debuffOffset and acfg.debuffOffset.y)
			if baseDay == nil then baseDay = defDay end
			if useSeparateDebuffs then
				UF._auraLayout.positionContainer(st.debuffContainer, danchor, st.barGroup, baseDax, baseDay, barAreaOffsetLeft, barAreaOffsetRight)
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
	if unit == UNIT.PLAYER then
		applyClassResourceLayout(cfg)
		if applyTotemFrameLayout then applyTotemFrameLayout(cfg) end
	end
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
	st.frame = _G[info.frameName] or CreateFrame("Button", info.frameName, parent, "BackdropTemplate,SecureUnitButtonTemplate, PingableUnitFrameTemplate")
	_G.ClickCastFrames = _G.ClickCastFrames or {}
	_G.ClickCastFrames[st.frame] = true
	if st.frame.SetParent then st.frame:SetParent(parent) end
	st.frame:SetAttribute("unit", info.unit)
	st.frame:SetAttribute("*type1", "target")
	st.frame:SetAttribute("*type2", "togglemenu")
	st.frame:HookScript("OnEnter", function(self)
		st._hovered = true
		UFHelper.updateHighlight(st, unit, UNIT.PLAYER)
		local cfg = ensureDB(unit)
		if not (cfg and cfg.showTooltip) then return end
		if not GameTooltip or GameTooltip:IsForbidden() then return end
		if info and info.unit then
			if cfg.tooltipUseEditMode and GameTooltip_SetDefaultAnchor then
				GameTooltip_SetDefaultAnchor(GameTooltip, self)
			else
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			end
			GameTooltip:SetUnit(info.unit)
			GameTooltip:Show()
		end
	end)
	st.frame:HookScript("OnLeave", function()
		st._hovered = false
		UFHelper.updateHighlight(st, unit, UNIT.PLAYER)
		if GameTooltip and not GameTooltip:IsForbidden() then GameTooltip:Hide() end
	end)
	st.frame:HookScript("OnHide", function()
		st._hovered = false
		UFHelper.updateHighlight(st, unit, UNIT.PLAYER)
		if unit == UNIT.TARGET then
			local targetLoose = IsTargetLoose and IsTargetLoose()
			if not targetLoose and UnitExists and not UnitExists(UNIT.TARGET) then
				if PlaySound and SOUNDKIT and SOUNDKIT.INTERFACE_SOUND_LOST_TARGET_UNIT then PlaySound(SOUNDKIT.INTERFACE_SOUND_LOST_TARGET_UNIT, nil, true) end
			end
		end
	end)
	st.frame:RegisterForClicks("AnyUp")
	st.frame:Hide()
	hideSettingsReset(st.frame)

	if info.dropdown then st.frame.menu = info.dropdown end
	st.frame:SetClampedToScreen(true)
	st.status = _G[info.statusName] or CreateFrame("Frame", info.statusName, st.frame)
	st.barGroup = st.barGroup or CreateFrame("Frame", nil, st.frame, "BackdropTemplate")
	st.health = _G[info.healthName] or CreateFrame("StatusBar", info.healthName, st.barGroup, "BackdropTemplate")
	if st.health.SetStatusBarDesaturated then st.health:SetStatusBarDesaturated(true) end
	st.power = _G[info.powerName] or CreateFrame("StatusBar", info.powerName, st.barGroup, "BackdropTemplate")
	st.powerGroup = st.powerGroup or CreateFrame("Frame", nil, st.frame, "BackdropTemplate")
	st.powerGroup:Hide()
	local powerEnum, powerToken = getMainPower(unit)
	if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated(UFHelper.isPowerDesaturated(powerEnum, powerToken)) end
	if not st.portraitHolder then
		st.portraitHolder = CreateFrame("Frame", nil, st.barGroup or st.frame, "BackdropTemplate")
		st.portraitHolder:EnableMouse(false)
		st.portraitHolder:Hide()
	end
	if not st.portrait then
		st.portrait = st.portraitHolder:CreateTexture(nil, "ARTWORK")
		st.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		st.portrait:Hide()
	end
	if not st.portraitBg then
		st.portraitBg = st.portraitHolder:CreateTexture(nil, "BACKGROUND")
		st.portraitBg:SetColorTexture(0, 0, 0, 1)
		st.portraitBg:Hide()
	end
	if not st.portraitSeparator then
		st.portraitSeparator = (st.barGroup or st.frame):CreateTexture(nil, "ARTWORK")
		st.portraitSeparator:SetColorTexture(0, 0, 0, 1)
		st.portraitSeparator:Hide()
	end
	if st.portrait and st.portrait:GetParent() ~= st.portraitHolder then st.portrait:SetParent(st.portraitHolder) end
	if st.portraitBg and st.portraitBg:GetParent() ~= st.portraitHolder then st.portraitBg:SetParent(st.portraitHolder) end
	if st.portraitHolder and st.barGroup and st.portraitHolder:GetParent() ~= st.barGroup then st.portraitHolder:SetParent(st.barGroup) end
	if st.portraitSeparator and st.barGroup and st.portraitSeparator:GetParent() ~= st.barGroup then st.portraitSeparator:SetParent(st.barGroup) end

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
		st.healAbsorb = st.healAbsorb or CreateFrame("StatusBar", info.healthName .. "HealAbsorb", st.health, "BackdropTemplate")
		if st.healAbsorb.SetStatusBarDesaturated then st.healAbsorb:SetStatusBarDesaturated(false) end
	else
		if st.absorb then st.absorb:Hide() end
		st.absorb = nil
		if st.absorb2 then st.absorb2:Hide() end
		st.absorb2 = nil
		if st.overAbsorbGlow then st.overAbsorbGlow:Hide() end
		if st.healAbsorb then st.healAbsorb:Hide() end
		st.healAbsorb = nil
	end
	if (unit == UNIT.PLAYER or unit == UNIT.TARGET or unit == UNIT.FOCUS or isBossUnit(unit)) and not st.castBar then
		st.castBar = CreateFrame("StatusBar", info.healthName .. "Cast", st.frame, "BackdropTemplate")
		st.castBar:SetStatusBarDesaturated(true)
		st.castTextLayer = CreateFrame("Frame", nil, st.castBar)
		st.castTextLayer:SetAllPoints(st.castBar)
		st.castIconLayer = CreateFrame("Frame", nil, st.castBar)
		st.castIconLayer:SetAllPoints(st.castBar)
		st.castIconLayer:EnableMouse(false)
		st.castName = st.castTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		st.castDuration = st.castTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		st.castIcon = st.castIconLayer:CreateTexture(nil, "ARTWORK")
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
	st.levelTextLayer = st.levelTextLayer or CreateFrame("Frame", nil, st.status)
	st.levelTextLayer:SetAllPoints(st.status)
	if not st.privateAuras then
		st.privateAuras = CreateFrame("Frame", nil, st.frame)
		st.privateAuras:EnableMouse(false)
	end
	if st.privateAuras.GetParent and st.privateAuras:GetParent() ~= st.frame then st.privateAuras:SetParent(st.frame) end

	st.healthTextLeft = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.healthTextCenter = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.healthTextRight = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.powerTextLeft = st.powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.powerTextCenter = st.powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.powerTextRight = st.powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.nameText = st.statusTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.levelText = st.levelTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.unitStatusText = st.statusTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.unitGroupText = st.statusTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.raidIcon = st.statusTextLayer:CreateTexture(nil, "OVERLAY", nil, 7)
	st.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	st.raidIcon:SetSize(18, 18)
	st.raidIcon:SetPoint("TOP", st.frame, "TOP", 0, -2)
	st.raidIcon:Hide()
	if unit == UNIT.PLAYER or unit == UNIT.TARGET or unit == UNIT.FOCUS then
		st.leaderIcon = st.statusTextLayer:CreateTexture(nil, "OVERLAY", nil, 7)
		st.leaderIcon:SetSize(12, 12)
		st.leaderIcon:SetPoint("TOPLEFT", st.health, "TOPLEFT", 0, 0)
		st.leaderIcon:Hide()
		st.pvpIcon = st.statusTextLayer:CreateTexture(nil, "OVERLAY", nil, 7)
		st.pvpIcon:SetSize(20, 20)
		st.pvpIcon:SetPoint("TOP", st.frame, "TOP", -24, -2)
		st.pvpIcon:Hide()
		st.roleIcon = st.statusTextLayer:CreateTexture(nil, "OVERLAY", nil, 7)
		st.roleIcon:SetSize(18, 18)
		st.roleIcon:SetPoint("TOP", st.frame, "TOP", 24, -2)
		st.roleIcon:Hide()
	end
	if unit ~= UNIT.PLAYER then
		st.classificationIcon = st.classificationIcon or st.statusTextLayer:CreateTexture(nil, "OVERLAY", nil, 7)
		st.classificationIcon:SetSize(16, 16)
		st.classificationIcon:Hide()
	end
	if unit == UNIT.PLAYER then
		st.combatIcon = st.statusTextLayer:CreateTexture("EQOLUFPlayerCombatIcon", "OVERLAY")
		ensureRestLoop(st)
	end

	if unit == UNIT.PLAYER or unit == "target" or unit == UNIT.FOCUS or isBossUnit(unit) then
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
	local def = defaultsFor(unit) or {}
	local defH = def.health or {}
	local defP = def.power or {}
	local interpolation = getSmoothInterpolation(cfg, def)
	local pcfg = cfg.power or {}
	local powerEnabled = pcfg.enabled ~= false
	local healthHeight = cfg.healthHeight or def.healthHeight or (st.health.GetHeight and st.health:GetHeight()) or 0
	st.health:SetStatusBarTexture(UFHelper.resolveTexture(hc.texture))
	if st.health.SetStatusBarDesaturated then st.health:SetStatusBarDesaturated(true) end
	UFHelper.configureSpecialTexture(st.health, "HEALTH", hc.texture, hc)
	local reverseHealth = hc.reverseFill
	if reverseHealth == nil then reverseHealth = defH.reverseFill == true end
	UFHelper.applyStatusBarReverseFill(st.health, reverseHealth)
	local healthBackdropR, healthBackdropG, healthBackdropB, healthBackdropA
	local healthBackdropClampToFill
	do
		local backdropCfg = hc.backdrop or {}
		local useBackdropClassColor = backdropCfg.useClassColor
		if useBackdropClassColor == nil and defH.backdrop then useBackdropClassColor = defH.backdrop.useClassColor end
		healthBackdropClampToFill = backdropCfg.clampToFill
		if healthBackdropClampToFill == nil and defH.backdrop then healthBackdropClampToFill = defH.backdrop.clampToFill end
		if healthBackdropClampToFill == nil then healthBackdropClampToFill = false end
		if useBackdropClassColor == true then
			local class
			if UnitIsPlayer and UnitIsPlayer(unit) then
				class = select(2, UnitClass(unit))
			elseif unit == UNIT.PET then
				class = select(2, UnitClass(UNIT.PLAYER))
			end
			local cr, cg, cb = getClassColor(class)
			if cr then
				local backdropColor = backdropCfg.color or (defH.backdrop and defH.backdrop.color) or { 0, 0, 0, 0.6 }
				healthBackdropR, healthBackdropG, healthBackdropB = cr, cg, cb
				healthBackdropA = backdropColor[4]
				if healthBackdropA == nil then healthBackdropA = 0.6 end
			end
		end
	end
	applyBarBackdrop(st.health, hc, healthBackdropR, healthBackdropG, healthBackdropB, healthBackdropA, {
		clampToFill = healthBackdropClampToFill == true,
		reverseFill = reverseHealth,
	})
	if powerEnabled then
		st.power:SetStatusBarTexture(UFHelper.resolveTexture(pcfg.texture))
		if unit == UNIT.PLAYER then refreshMainPower(unit) end
		local powerEnum, powerToken = getMainPower(unit)
		if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated(UFHelper.isPowerDesaturated(powerEnum, powerToken)) end
		UFHelper.configureSpecialTexture(st.power, powerToken, pcfg.texture, pcfg, powerEnum)
		local reversePower = pcfg.reverseFill
		if reversePower == nil then reversePower = defP.reverseFill == true end
		UFHelper.applyStatusBarReverseFill(st.power, reversePower)
		applyBarBackdrop(st.power, pcfg)
		st.power:Show()
	else
		st.power:Hide()
		if st.powerTextLeft then st.powerTextLeft:SetText("") end
		if st.powerTextCenter then st.powerTextCenter:SetText("") end
		if st.powerTextRight then st.powerTextRight:SetText("") end
	end
	if allowAbsorb and st.absorb then
		local absorbTextureKey = hc.absorbTexture or hc.texture
		st.absorb:SetStatusBarTexture(UFHelper.resolveTexture(absorbTextureKey))
		if st.absorb.SetStatusBarDesaturated then st.absorb:SetStatusBarDesaturated(false) end
		UFHelper.configureSpecialTexture(st.absorb, "HEALTH", absorbTextureKey, hc)
		local reverseAbsorb = hc.absorbReverseFill
		if reverseAbsorb == nil then reverseAbsorb = defH.absorbReverseFill == true end
		UFHelper.applyStatusBarReverseFill(st.absorb, reverseAbsorb)
		if reverseAbsorb then
			st.absorb2 = st.absorb2 or CreateFrame("StatusBar", info.healthName .. "Absorb2", st.health, "BackdropTemplate")
			if st.absorb2.SetStatusBarDesaturated then st.absorb2:SetStatusBarDesaturated(false) end
			st.absorb2:Hide()
		elseif st.absorb2 then
			st.absorb2:Hide()
		end
		local absorbHeight = hc.absorbOverlayHeight
		if absorbHeight == nil then absorbHeight = defH.absorbOverlayHeight end
		applyOverlayHeight(st.absorb, st.health, absorbHeight, healthHeight)
		if reverseAbsorb and st.absorb2 then
			st.absorb2:SetStatusBarTexture(UFHelper.resolveTexture(absorbTextureKey))
			if st.absorb2.SetStatusBarDesaturated then st.absorb2:SetStatusBarDesaturated(false) end
			UFHelper.configureSpecialTexture(st.absorb2, "HEALTH", absorbTextureKey, hc)
			if st.absorb2.SetOrientation then st.absorb2:SetOrientation("HORIZONTAL") end
			if UFHelper and UFHelper.applyAbsorbClampLayout then
				if reverseHealth then
					if UFHelper.setupAbsorbClampReverseAware then UFHelper.setupAbsorbClampReverseAware(st.health, st.absorb2) end
				else
					if UFHelper.setupAbsorbClamp then UFHelper.setupAbsorbClamp(st.health, st.absorb2) end
					if UFHelper.setupAbsorbOverShift then UFHelper.setupAbsorbOverShift(st.health, st.absorb, absorbHeight, healthHeight) end
				end
				UFHelper.applyAbsorbClampLayout(st.absorb2, st.health, absorbHeight, healthHeight, reverseHealth)
				syncTextFrameLevels(st)
			end
			setFrameLevelAbove(st.absorb2, st.health, 1)
			st.absorb2:SetMinMaxValues(0, 1)
			st.absorb2:SetValue(0, interpolation)
			st.absorb2:Hide()
		end
		local borderFrame = st.barGroup and st.barGroup._ufBorder
		setFrameLevelAbove(st.absorb, st.health, 1)
		st.absorb:SetMinMaxValues(0, 1)
		st.absorb:SetValue(0, interpolation)
		if st.overAbsorbGlow then
			st.overAbsorbGlow:ClearAllPoints()
			local glowAnchor = st.absorb or st.health
			st.overAbsorbGlow:SetPoint("TOPLEFT", glowAnchor, "TOPRIGHT", -7, 0)
			st.overAbsorbGlow:SetPoint("BOTTOMLEFT", glowAnchor, "BOTTOMRIGHT", -7, 0)
		end
		if st.overAbsorbGlow then st.overAbsorbGlow:Hide() end
	elseif st.overAbsorbGlow then
		st.overAbsorbGlow:Hide()
	end
	if allowAbsorb and st.healAbsorb then
		local healAbsorbTextureKey = hc.healAbsorbTexture or hc.texture
		st.healAbsorb:SetStatusBarTexture(UFHelper.resolveTexture(healAbsorbTextureKey))
		if st.healAbsorb.SetStatusBarDesaturated then st.healAbsorb:SetStatusBarDesaturated(false) end
		UFHelper.configureSpecialTexture(st.healAbsorb, "HEALTH", healAbsorbTextureKey, hc)
		local reverseHealAbsorb = hc.healAbsorbReverseFill
		if reverseHealAbsorb == nil then reverseHealAbsorb = defH.healAbsorbReverseFill == true end
		UFHelper.applyStatusBarReverseFill(st.healAbsorb, reverseHealAbsorb)
		local healAbsorbHeight = hc.healAbsorbOverlayHeight
		if healAbsorbHeight == nil then healAbsorbHeight = defH.healAbsorbOverlayHeight end
		applyOverlayHeight(st.healAbsorb, st.health, healAbsorbHeight, healthHeight)
		local anchorBar = st.absorb or st.health
		setFrameLevelAbove(st.healAbsorb, anchorBar, 1)
		st.healAbsorb:SetMinMaxValues(0, 1)
		st.healAbsorb:SetValue(0, interpolation)
		-- no heal absorb glow
	end
	UF.syncAbsorbFrameLevels(st)
	if st.castBar and (unit == UNIT.PLAYER or unit == UNIT.TARGET or unit == UNIT.FOCUS or isBossUnit(unit)) then
		local defc = (defaultsFor(unit) and defaultsFor(unit).cast) or {}
		local ccfg = cfg.cast or defc
		st.castBar:SetStatusBarTexture(UFHelper.resolveCastTexture((ccfg.texture or defc.texture or "DEFAULT")))
		st.castBar:SetMinMaxValues(0, 1)
		st.castBar:SetValue(0)
		applyCastLayout(cfg, unit)
		local castFont = ccfg.font or defc.font or hc.font
		local castFontSize = ccfg.fontSize or defc.fontSize or hc.fontSize or 12
		local castOutline = ccfg.fontOutline or defc.fontOutline or hc.fontOutline or "OUTLINE"
		UFHelper.applyFont(st.castName, castFont, castFontSize, castOutline)
		UFHelper.applyFont(st.castDuration, castFont, castFontSize, castOutline)
		local castFontColor = ccfg.fontColor or defc.fontColor
		if castFontColor then
			local r = castFontColor.r or castFontColor[1] or 1
			local g = castFontColor.g or castFontColor[2] or 1
			local b = castFontColor.b or castFontColor[3] or 1
			local a = castFontColor.a or castFontColor[4] or 1
			if st.castName then st.castName:SetTextColor(r, g, b, a) end
			if st.castDuration then st.castDuration:SetTextColor(r, g, b, a) end
		end
	end

	UFHelper.applyFont(st.healthTextLeft, hc.font, hc.fontSize or 14, hc.fontOutline)
	UFHelper.applyFont(st.healthTextCenter, hc.font, hc.fontSize or 14, hc.fontOutline)
	UFHelper.applyFont(st.healthTextRight, hc.font, hc.fontSize or 14, hc.fontOutline)
	UFHelper.applyFont(st.powerTextLeft, pcfg.font, pcfg.fontSize or 14, pcfg.fontOutline)
	UFHelper.applyFont(st.powerTextCenter, pcfg.font, pcfg.fontSize or 14, pcfg.fontOutline)
	UFHelper.applyFont(st.powerTextRight, pcfg.font, pcfg.fontSize or 14, pcfg.fontOutline)
	syncTextFrameLevels(st)
end

local function updateNameAndLevel(cfg, unit, levelOverride)
	local st = states[unit]
	if not st then return end
	cfg = cfg or st.cfg or ensureDB(unit)
	if cfg and cfg.enabled == false then return end
	if st.nameText then
		local scfg = cfg.status or {}
		local defStatus = (defaultsFor(unit) and defaultsFor(unit).status) or {}
		local nc
		local nr, ng, nb, na
		local isPlayerUnit = UnitIsPlayer and UnitIsPlayer(unit)
		if scfg.nameColorMode == "CUSTOM" then
			nc = scfg.nameColor or { 1, 1, 1, 1 }
			nr, ng, nb, na = nc[1] or 1, nc[2] or 1, nc[3] or 1, nc[4] or 1
		else
			if isPlayerUnit then
				local class = select(2, UnitClass(unit))
				local cr, cg, cb, ca = getClassColor(class)
				if cr then
					nr, ng, nb, na = cr, cg, cb, ca
				end
			else
				local useReactionColor = scfg.nameUseReactionColor
				if useReactionColor == nil then useReactionColor = defStatus.nameUseReactionColor == true end
				if useReactionColor == true and UFHelper and UFHelper.getNPCHealthColor then
					nr, ng, nb, na = UFHelper.getNPCHealthColor(unit)
				end
				if not nr and UFHelper and UFHelper.getNPCSelectionKey and UFHelper.getNPCSelectionKey(unit) then
					local fallback = NORMAL_FONT_COLOR
					nr = (fallback and (fallback.r or fallback[1])) or 1
					ng = (fallback and (fallback.g or fallback[2])) or 0.82
					nb = (fallback and (fallback.b or fallback[3])) or 0
					na = (fallback and (fallback.a or fallback[4])) or 1
				end
			end
		end
		if not nr then
			nr, ng, nb, na = 1, 1, 1, 1
		end
		st.nameText:SetText(UnitName(unit) or "")
		st.nameText:SetTextColor(nr, ng, nb, na)
	end
	if st.levelText then
		local scfg = cfg.status or {}
		local enabled = shouldShowLevel(scfg, unit)
		local hideClassText = shouldHideClassificationText(cfg, unit)
		st.levelText:SetShown(enabled)
		if enabled then
			local lc
			if scfg.levelColorMode == "CUSTOM" then
				lc = scfg.levelColor or { 1, 0.85, 0, 1 }
			else
				local class = select(2, UnitClass(unit))
				local cr, cg, cb, ca = getClassColor(class)
				if cr then
					lc = { cr, cg, cb, ca }
				else
					lc = { 1, 0.85, 0, 1 }
				end
			end
			local levelText = UFHelper.getUnitLevelText(unit, levelOverride, hideClassText)
			st.levelText:SetText(levelText)
			st.levelText:SetTextColor(lc[1] or 1, lc[2] or 0.85, lc[3] or 0, lc[4] or 1)
		end
	end
	if UFHelper and UFHelper.updateClassificationIndicator then UFHelper.updateClassificationIndicator(st, unit, cfg, defaultsFor(unit), false) end
end

local function applyConfig(unit)
	local cfg = ensureDB(unit)
	local def = defaultsFor(unit)
	states[unit] = states[unit] or {}
	local st = states[unit]
	st.cfg = cfg
	st._healthColorDirty = true
	st._powerColorDirty = true
	st._healthTextDirty = true
	st._powerTextDirty = true
	if unit == UNIT.TARGET then syncTargetRangeFadeConfig(cfg, def) end
	if not cfg.enabled then
		if st and st.frame then
			if st.barGroup then st.barGroup:Hide() end
			if st.status then st.status:Hide() end
			if st.portrait then st.portrait:Hide() end
			if st.portraitHolder then st.portraitHolder:Hide() end
			if st.portraitSeparator then st.portraitSeparator:Hide() end
			if st.auraContainer then AuraUtil.hideAuraContainers(st) end
			if st.barGroup and st.barGroup._ufHighlight then st.barGroup._ufHighlight:Hide() end
			st._hovered = false
		end
		if st then st._highlightCfg = nil end
		if UFHelper and UFHelper.updateCombatFeedback then UFHelper.updateCombatFeedback(st, unit, cfg, def) end
		applyVisibilityDriver(unit, false)
		if unit == UNIT.PLAYER then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.player, false) end
		if unit == UNIT.TARGET then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.target, false) end
		if unit == UNIT.TARGET_TARGET then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.targettarget, false) end
		if unit == UNIT.FOCUS then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.focus, false) end
		if unit == UNIT.PET then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.pet, false) end
		if unit == UNIT.PLAYER then
			ClassResourceUtil.restoreClassResourceFrames()
			TotemFrameUtil.restoreTotemFrame()
		end
		if unit == UNIT.PLAYER or unit == "target" or unit == UNIT.FOCUS or isBossUnit(unit) then AuraUtil.resetTargetAuras(unit) end
		if unit == UNIT.PLAYER then updateRestingIndicator(cfg) end
		if not isBossUnit(unit) then applyVisibilityRules(unit) end
		if unit == UNIT.TARGET and UFHelper and UFHelper.RangeFadeReset then UFHelper.RangeFadeReset() end
		if unit == UNIT.PLAYER and addon.functions and addon.functions.ApplyCastBarVisibility then addon.functions.ApplyCastBarVisibility() end
		if st and st.privateAuras and UFHelper and UFHelper.RemovePrivateAuras then
			UFHelper.RemovePrivateAuras(st.privateAuras)
			if st.privateAuras.Hide then st.privateAuras:Hide() end
		end
		return
	end
	ensureFrames(unit)
	st = states[unit]
	st.cfg = cfg
	if UFHelper then
		local hc = (cfg and cfg.health) or {}
		local defH = (def and def.health) or {}
		local pcfg = (cfg and cfg.power) or {}
		local defP = (def and def.power) or {}

		local h1 = UFHelper.getTextDelimiter(hc, defH)
		local h2 = UFHelper.getTextDelimiterSecondary(hc, defH, h1)
		local h3 = UFHelper.getTextDelimiterTertiary(hc, defH, h1, h2)
		if UFHelper.resolveTextDelimiters then
			st._healthTextDelimiter1, st._healthTextDelimiter2, st._healthTextDelimiter3 = UFHelper.resolveTextDelimiters(h1, h2, h3)
		else
			st._healthTextDelimiter1, st._healthTextDelimiter2, st._healthTextDelimiter3 = h1, h2, h3
		end

		local p1 = UFHelper.getTextDelimiter(pcfg, defP)
		local p2 = UFHelper.getTextDelimiterSecondary(pcfg, defP, p1)
		local p3 = UFHelper.getTextDelimiterTertiary(pcfg, defP, p1, p2)
		if UFHelper.resolveTextDelimiters then
			st._powerTextDelimiter1, st._powerTextDelimiter2, st._powerTextDelimiter3 = UFHelper.resolveTextDelimiters(p1, p2, p3)
		else
			st._powerTextDelimiter1, st._powerTextDelimiter2, st._powerTextDelimiter3 = p1, p2, p3
		end
	end
	st._highlightCfg = UFHelper.buildHighlightConfig(cfg, def)
	applyVisibilityDriver(unit, cfg.enabled)
	if unit == UNIT.PLAYER then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.player, true) end
	if unit == UNIT.TARGET then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.target, true) end
	if unit == UNIT.TARGET_TARGET then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.targettarget, true) end
	if unit == UNIT.FOCUS then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.focus, true) end
	if unit == UNIT.PET then applyFrameRuleOverride(BLIZZ_FRAME_NAMES.pet, true) end
	applyBars(cfg, unit)
	if not InCombatLockdown() then
		layoutFrame(cfg, unit)
	else
		UFHelper.applyHighlightStyle(st, st._highlightCfg)
	end
	updateStatus(cfg, unit)
	if UFHelper and UFHelper.updateCombatFeedback then UFHelper.updateCombatFeedback(st, unit, cfg, def) end
	updateNameAndLevel(cfg, unit)
	updateHealth(cfg, unit)
	updatePower(cfg, unit)
	updatePortrait(cfg, unit)
	checkRaidTargetIcon(unit, st)
	UFHelper.updateLeaderIndicator(st, unit, cfg, defaultsFor(unit), false)
	UFHelper.updatePvPIndicator(st, unit, cfg, defaultsFor(unit), false)
	UFHelper.updateRoleIndicator(st, unit, cfg, defaultsFor(unit), false)
	if st.privateAuras and UFHelper and UFHelper.ApplyPrivateAuras then
		local pcfg = cfg.privateAuras or (def and def.privateAuras)
		local inEditMode = addon.EditModeLib and addon.EditModeLib.IsInEditMode and addon.EditModeLib:IsInEditMode()
		UFHelper.ApplyPrivateAuras(st.privateAuras, unit, pcfg, st.frame, st.statusTextLayer or st.frame, inEditMode == true, true)
	end
	if unit == UNIT.PLAYER then
		updateCombatIndicator(cfg)
		updateRestingIndicator(cfg)
	end
	-- if unit == "target" then hideBlizzardTargetFrame() end
	if st and st.frame then
		if st.barGroup then st.barGroup:Show() end
		if st.status then st.status:Show() end
	end
	UFHelper.updateHighlight(st, unit, UNIT.PLAYER)
	if unit == UNIT.PLAYER and st.castBar then
		if cfg.cast and cfg.cast.enabled ~= false then
			setCastInfoFromUnit(UNIT.PLAYER)
		else
			stopCast(UNIT.PLAYER)
			st.castBar:Hide()
		end
		if addon.functions and addon.functions.ApplyCastBarVisibility then addon.functions.ApplyCastBarVisibility() end
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
	if unit == UNIT.TARGET and states[unit] and states[unit].auraContainer then
		if addon.EditModeLib and addon.EditModeLib:IsInEditMode() then
			AuraUtil.fullScanTargetAuras(unit)
		else
			AuraUtil.updateTargetAuraIcons(1, unit)
		end
	elseif unit == UNIT.FOCUS and states[unit] and states[unit].auraContainer then
		AuraUtil.fullScanTargetAuras(unit)
	elseif unit == UNIT.PLAYER and states[unit] and states[unit].auraContainer then
		AuraUtil.fullScanTargetAuras(unit)
	elseif isBossUnit(unit) and states[unit] and states[unit].auraContainer then
		AuraUtil.fullScanTargetAuras(unit)
	end
	if not isBossUnit(unit) then applyVisibilityRules(unit) end
	if unit == UNIT.TARGET and UFHelper and UFHelper.RangeFadeApplyCurrent then UFHelper.RangeFadeApplyCurrent(true) end
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
				if growth == "UP" then
					st.frame:SetPoint("BOTTOMLEFT", bossContainer, "BOTTOMLEFT", 0, 0)
				else
					st.frame:SetPoint("TOPLEFT", bossContainer, "TOPLEFT", 0, 0)
				end
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
	local hideClassText = shouldHideClassificationText(cfg, unit)
	local interpolation = getSmoothInterpolation(cfg, def)

	local cur = UnitHealth("player") or 1
	local maxv = UnitHealthMax("player") or cur or 1
	local percentVal = getHealthPercent("player", cur, maxv)
	st.health:SetMinMaxValues(0, maxv)
	st.health:SetValue(cur, interpolation)
	local color = hc.color or (def.health and def.health.color) or { 0, 0.8, 0, 1 }
	st.health:SetStatusBarColor(color[1] or 0, color[2] or 0.8, color[3] or 0, color[4] or 1)
	local leftMode = hc.textLeft or "PERCENT"
	local centerMode = hc.textCenter or "NONE"
	local rightMode = hc.textRight or "CURMAX"
	local delimiter = UFHelper.getTextDelimiter(hc, defH)
	local delimiter2 = UFHelper.getTextDelimiterSecondary(hc, defH, delimiter)
	local delimiter3 = UFHelper.getTextDelimiterTertiary(hc, defH, delimiter, delimiter2)
	local hidePercentSymbol = hc.hidePercentSymbol == true
	local roundPercent = hc.roundPercent == true
	local levelText
	if UFHelper.textModeUsesLevel(leftMode) or UFHelper.textModeUsesLevel(centerMode) or UFHelper.textModeUsesLevel(rightMode) then
		levelText = UFHelper.getUnitLevelText("player", nil, hideClassText)
	end
	if st.healthTextLeft then
		if leftMode == "NONE" then
			st.healthTextLeft:SetText("")
		else
			st.healthTextLeft:SetText(
				UFHelper.formatText(leftMode, cur, maxv, hc.useShortNumbers ~= false, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText, nil, roundPercent)
			)
		end
	end
	if st.healthTextCenter then
		if centerMode == "NONE" then
			st.healthTextCenter:SetText("")
		else
			st.healthTextCenter:SetText(
				UFHelper.formatText(centerMode, cur, maxv, hc.useShortNumbers ~= false, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText, nil, roundPercent)
			)
		end
	end
	if st.healthTextRight then
		if rightMode == "NONE" then
			st.healthTextRight:SetText("")
		else
			st.healthTextRight:SetText(
				UFHelper.formatText(rightMode, cur, maxv, hc.useShortNumbers ~= false, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText, nil, roundPercent)
			)
		end
	end

	local powerEnabled = pcfg.enabled ~= false
	if st.power then
		if powerEnabled then
			local enumId, token = getMainPower("player")
			local pCur = UnitPower("player", enumId or 0) or 0
			local pMax = UnitPowerMax("player", enumId or 0) or 0
			local pPercent = getPowerPercent("player", enumId or 0, pCur, pMax)
			st.power:SetMinMaxValues(0, pMax > 0 and pMax or 1)
			st.power:SetValue(pCur, interpolation)
			local pr, pg, pb, pa = UFHelper.getPowerColor(enumId, token)
			st.power:SetStatusBarColor(pr or 0.1, pg or 0.45, pb or 1, pa or 1)
			if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated(UFHelper.isPowerDesaturated(enumId, token)) end
			local pLeftMode = pcfg.textLeft or "PERCENT"
			local pCenterMode = pcfg.textCenter or "NONE"
			local pRightMode = pcfg.textRight or "CURMAX"
			local pDelimiter = UFHelper.getTextDelimiter(pcfg, defP)
			local pDelimiter2 = UFHelper.getTextDelimiterSecondary(pcfg, defP, pDelimiter)
			local pDelimiter3 = UFHelper.getTextDelimiterTertiary(pcfg, defP, pDelimiter, pDelimiter2)
			local pHidePercentSymbol = pcfg.hidePercentSymbol == true
			local pRoundPercent = pcfg.roundPercent == true
			local pLevelText = levelText
			if not pLevelText and (UFHelper.textModeUsesLevel(pLeftMode) or UFHelper.textModeUsesLevel(pCenterMode) or UFHelper.textModeUsesLevel(pRightMode)) then
				pLevelText = UFHelper.getUnitLevelText("player", nil, hideClassText)
			end
			if st.powerTextLeft then
				if pLeftMode == "NONE" then
					st.powerTextLeft:SetText("")
				else
					st.powerTextLeft:SetText(
						UFHelper.formatText(pLeftMode, pCur, pMax, pcfg.useShortNumbers ~= false, pPercent, pDelimiter, pDelimiter2, pDelimiter3, pHidePercentSymbol, pLevelText, nil, pRoundPercent)
					)
				end
			end
			if st.powerTextCenter then
				if pCenterMode == "NONE" then
					st.powerTextCenter:SetText("")
				else
					st.powerTextCenter:SetText(
						UFHelper.formatText(pCenterMode, pCur, pMax, pcfg.useShortNumbers ~= false, pPercent, pDelimiter, pDelimiter2, pDelimiter3, pHidePercentSymbol, pLevelText, nil, pRoundPercent)
					)
				end
			end
			if st.powerTextRight then
				if pRightMode == "NONE" then
					st.powerTextRight:SetText("")
				else
					st.powerTextRight:SetText(
						UFHelper.formatText(pRightMode, pCur, pMax, pcfg.useShortNumbers ~= false, pPercent, pDelimiter, pDelimiter2, pDelimiter3, pHidePercentSymbol, pLevelText, nil, pRoundPercent)
					)
				end
			end
			st.power:Show()
		else
			st.power:SetValue(0, interpolation)
			if st.powerTextLeft then st.powerTextLeft:SetText("") end
			if st.powerTextCenter then st.powerTextCenter:SetText("") end
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
				if st.auraContainer then AuraUtil.fullScanTargetAuras(unit) end
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
					AuraUtil.fullScanTargetAuras(unit)
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
					if st.auraContainer then AuraUtil.hideAuraContainers(st) end
					AuraUtil.resetTargetAuras(unit)
					if st.castBar then
						stopCast(unit)
						st.castBar:Hide()
					end
				end
			end
		end
		UFHelper.updateHighlight(st, unit, UNIT.PLAYER)
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
	"UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
	"UNIT_POWER_UPDATE",
	"UNIT_POWER_FREQUENT",
	"UNIT_MAXPOWER",
	"UNIT_DISPLAYPOWER",
	"UNIT_NAME_UPDATE",
	"UNIT_CLASSIFICATION_CHANGED",
	"UNIT_FLAGS",
	"UNIT_CONNECTION",
	"UNIT_FACTION",
	"UNIT_THREAT_SITUATION_UPDATE",
	"UNIT_THREAT_LIST_UPDATE",
	"UNIT_AURA",
	"UNIT_TARGET",
	"UNIT_SPELLCAST_SENT",
	"UNIT_SPELLCAST_START",
	"UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_EMPOWER_START",
	"UNIT_SPELLCAST_EMPOWER_UPDATE",
	"UNIT_SPELLCAST_DELAYED",
	"UNIT_SPELLCAST_EMPOWER_STOP",
	"UNIT_PET",
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
	"SPELLS_CHANGED",
	"PLAYER_TALENT_UPDATE",
	"ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
	"TRAIT_CONFIG_UPDATED",
	"PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED",
	"PLAYER_FLAGS_CHANGED",
	"PLAYER_UPDATE_RESTING",
	"GROUP_ROSTER_UPDATE",
	"PARTY_LEADER_CHANGED",
	"PLAYER_FOCUS_CHANGED",
	"INSTANCE_ENCOUNTER_ENGAGE_UNIT",
	"ENCOUNTER_START",
	"ENCOUNTER_END",
	"RAID_TARGET_UPDATE",
	"SPELL_RANGE_CHECK_UPDATE",
	"CLIENT_SCENE_OPENED",
	"CLIENT_SCENE_CLOSED",
}

local eventFrame
UF._unitEventFrames = UF._unitEventFrames or {}
local onEvent

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

function UF._clearUnitEventFrames()
	local unitEventFrames = UF._unitEventFrames
	for i = 1, #unitEventFrames do
		local frame = unitEventFrames[i]
		if frame then
			if frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
			frame:SetScript("OnEvent", nil)
			unitEventFrames[i] = nil
		end
	end
end

function UF._buildRegisteredUnitTokens()
	local tokens = {}
	local seen = {}
	local function addToken(token)
		if token and token ~= "" and not seen[token] then
			seen[token] = true
			tokens[#tokens + 1] = token
		end
	end

	local playerCfg = ensureDB(UNIT.PLAYER)
	local targetCfg = ensureDB(UNIT.TARGET)
	local totCfg = ensureDB(UNIT.TARGET_TARGET)
	local focusCfg = ensureDB(UNIT.FOCUS)
	local petCfg = ensureDB(UNIT.PET)
	local bossCfg = ensureDB("boss")

	if playerCfg.enabled then addToken(UNIT.PLAYER) end
	if targetCfg.enabled or totCfg.enabled then addToken(UNIT.TARGET) end
	if totCfg.enabled then addToken(UNIT.TARGET_TARGET) end
	if focusCfg.enabled then addToken(UNIT.FOCUS) end
	if petCfg.enabled then
		addToken(UNIT.PET)
		addToken(UNIT.PLAYER) -- UNIT_PET uses "player" as event unit
	end
	if bossCfg.enabled then
		for i = 1, maxBossFrames do
			addToken("boss" .. i)
		end
	end

	return tokens
end

function UF._registerUnitScopedEvents(includePortraitEvents)
	UF._clearUnitEventFrames()

	local tokens = UF._buildRegisteredUnitTokens()
	if #tokens == 0 then return end

	local unitEventFrames = UF._unitEventFrames
	for i = 1, #tokens do
		local token = tokens[i]
		local frame = unitEventFrames[i]
		if not frame then
			frame = CreateFrame("Frame")
			unitEventFrames[i] = frame
		end
		for _, evt in ipairs(unitEvents) do
			frame:RegisterUnitEvent(evt, token)
		end
		if includePortraitEvents then
			for _, evt in ipairs(portraitEvents) do
				frame:RegisterUnitEvent(evt, token)
			end
		end
		frame:SetScript("OnEvent", onEvent)
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

local allowedEventUnit = {}

local function rebuildAllowedEventUnits()
	if wipe then
		wipe(allowedEventUnit)
	else
		for k in pairs(allowedEventUnit) do
			allowedEventUnit[k] = nil
		end
	end
	local playerCfg = ensureDB(UNIT.PLAYER)
	local targetCfg = ensureDB(UNIT.TARGET)
	local totCfg = ensureDB(UNIT.TARGET_TARGET)
	local focusCfg = ensureDB(UNIT.FOCUS)
	local petCfg = ensureDB(UNIT.PET)
	local bossCfg = ensureDB("boss")

	if playerCfg.enabled then allowedEventUnit[UNIT.PLAYER] = true end
	if targetCfg.enabled or totCfg.enabled then allowedEventUnit[UNIT.TARGET] = true end
	if totCfg.enabled then allowedEventUnit[UNIT.TARGET_TARGET] = true end
	if focusCfg.enabled then allowedEventUnit[UNIT.FOCUS] = true end
	if petCfg.enabled then allowedEventUnit[UNIT.PET] = true end
	if bossCfg.enabled then
		for i = 1, maxBossFrames do
			allowedEventUnit["boss" .. i] = true
		end
	end
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
			local powerEnum, powerToken = UnitPowerType(UNIT.TARGET_TARGET)
			if st.power and powerToken and powerToken ~= st._lastPowerToken then
				if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated(UFHelper.isPowerDesaturated(powerEnum, powerToken)) end
				UFHelper.configureSpecialTexture(st.power, powerToken, (cfg.power or {}).texture, cfg.power, powerEnum)
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
				local powerEnum, powerToken = getMainPower(UNIT.TARGET_TARGET)
				if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated(UFHelper.isPowerDesaturated(powerEnum, powerToken)) end
				UFHelper.configureSpecialTexture(st.power, powerToken, (cfg.power or {}).texture, cfg.power, powerEnum)
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
	UFHelper.updateHighlight(st, UNIT.TARGET_TARGET, UNIT.PLAYER)
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
			if st.auraContainer then AuraUtil.hideAuraContainers(st) end
		end
		AuraUtil.resetTargetAuras(UNIT.FOCUS)
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
				local powerEnum, powerToken = getMainPower(UNIT.FOCUS)
				if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated(UFHelper.isPowerDesaturated(powerEnum, powerToken)) end
				UFHelper.configureSpecialTexture(st.power, powerToken, (cfg.power or {}).texture, cfg.power, powerEnum)
				st._lastPowerToken = powerToken
			elseif st.power then
				st.power:Hide()
			end
			updatePower(cfg, UNIT.FOCUS)
			if st.castBar then setCastInfoFromUnit(UNIT.FOCUS) end
			checkRaidTargetIcon(UNIT.FOCUS, st)
			if st.auraContainer then AuraUtil.fullScanTargetAuras(UNIT.FOCUS) end
		end
	else
		if st then
			if st.barGroup then st.barGroup:Hide() end
			if st.status then st.status:Hide() end
			if st.castBar then stopCast(UNIT.FOCUS) end
			if st.auraContainer then AuraUtil.hideAuraContainers(st) end
		end
		AuraUtil.resetTargetAuras(UNIT.FOCUS)
	end
	checkRaidTargetIcon(UNIT.FOCUS, st)
	UFHelper.updateLeaderIndicator(st, UNIT.FOCUS, cfg, defaultsFor(UNIT.FOCUS), not forceApply)
	UFHelper.updatePvPIndicator(st, UNIT.FOCUS, cfg, defaultsFor(UNIT.FOCUS), not forceApply)
	UFHelper.updateRoleIndicator(st, UNIT.FOCUS, cfg, defaultsFor(UNIT.FOCUS), not forceApply)
	updateUnitStatusIndicator(cfg, UNIT.FOCUS)
	updatePortrait(cfg, UNIT.FOCUS)
	UFHelper.updateHighlight(st, UNIT.FOCUS, UNIT.PLAYER)
	applyVisibilityRules(UNIT.FOCUS)
end

local function getCfg(unit)
	local st = states[unit]
	if st and st.cfg then return st.cfg end
	return ensureDB(unit)
end

function UF.UpdateUnitTexts(unit, force)
	local st = states[unit]
	if not st then return end
	if not force and not (st._healthTextDirty or st._powerTextDirty) then return end

	local cfg = st.cfg or ensureDB(unit)
	if not cfg or cfg.enabled == false then
		st._healthTextDirty = nil
		st._powerTextDirty = nil
		return
	end

	local inEdit = addon.EditModeLib and addon.EditModeLib.IsInEditMode and addon.EditModeLib:IsInEditMode()
	local exists = UnitExists and UnitExists(unit)
	if not exists and not inEdit then
		if st.healthTextLeft then st.healthTextLeft:SetText("") end
		if st.healthTextCenter then st.healthTextCenter:SetText("") end
		if st.healthTextRight then st.healthTextRight:SetText("") end
		if st.powerTextLeft then st.powerTextLeft:SetText("") end
		if st.powerTextCenter then st.powerTextCenter:SetText("") end
		if st.powerTextRight then st.powerTextRight:SetText("") end
		st._healthTextDirty = nil
		st._powerTextDirty = nil
		return
	end

	local def = defaultsFor(unit) or {}

	if st._healthTextDirty and (st.healthTextLeft or st.healthTextCenter or st.healthTextRight) then
		local hc = cfg.health or {}
		local defH = def.health or {}
		local leftMode = hc.textLeft or "PERCENT"
		local centerMode = hc.textCenter or "NONE"
		local rightMode = hc.textRight or "CURMAX"
		local cur = UnitHealth(unit)
		local maxv = UnitHealthMax(unit)
		local percentVal
		if addon.variables and addon.variables.isMidnight then
			percentVal = getHealthPercent(unit, cur, maxv)
		elseif not issecretvalue or (not issecretvalue(cur) and not issecretvalue(maxv)) then
			percentVal = getHealthPercent(unit, cur, maxv)
		end

		local delimiter, delimiter2, delimiter3 = st._healthTextDelimiter1, st._healthTextDelimiter2, st._healthTextDelimiter3
		if not delimiter or not delimiter2 or not delimiter3 then
			local d1 = UFHelper.getTextDelimiter(hc, defH)
			local d2 = UFHelper.getTextDelimiterSecondary(hc, defH, d1)
			local d3 = UFHelper.getTextDelimiterTertiary(hc, defH, d1, d2)
			if UFHelper.resolveTextDelimiters then
				delimiter, delimiter2, delimiter3 = UFHelper.resolveTextDelimiters(d1, d2, d3)
			else
				delimiter, delimiter2, delimiter3 = d1, d2, d3
			end
		end

		local hidePercentSymbol = hc.hidePercentSymbol == true
		local roundPercent = hc.roundPercent == true
		local levelText
		if UFHelper.textModeUsesLevel(leftMode) or UFHelper.textModeUsesLevel(centerMode) or UFHelper.textModeUsesLevel(rightMode) then
			levelText = UFHelper.getUnitLevelText(unit, nil, shouldHideClassificationText(cfg, unit))
		end

		if st.healthTextLeft then
			if leftMode == "NONE" then
				st.healthTextLeft:SetText("")
			else
				st.healthTextLeft:SetText(
					UFHelper.formatText(leftMode, cur, maxv, hc.useShortNumbers ~= false, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText, nil, roundPercent, true)
				)
			end
		end
		if st.healthTextCenter then
			if centerMode == "NONE" then
				st.healthTextCenter:SetText("")
			else
				st.healthTextCenter:SetText(
					UFHelper.formatText(centerMode, cur, maxv, hc.useShortNumbers ~= false, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText, nil, roundPercent, true)
				)
			end
		end
		if st.healthTextRight then
			if rightMode == "NONE" then
				st.healthTextRight:SetText("")
			else
				st.healthTextRight:SetText(
					UFHelper.formatText(rightMode, cur, maxv, hc.useShortNumbers ~= false, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText, nil, roundPercent, true)
				)
			end
		end

		st._healthTextDirty = nil
	end

	if st._powerTextDirty and (st.powerTextLeft or st.powerTextCenter or st.powerTextRight) then
		local pcfg = cfg.power or {}
		if pcfg.enabled == false then
			if st.powerTextLeft then st.powerTextLeft:SetText("") end
			if st.powerTextCenter then st.powerTextCenter:SetText("") end
			if st.powerTextRight then st.powerTextRight:SetText("") end
			st._powerTextDirty = nil
			return
		end

		local defP = def.power or {}
		local leftMode = pcfg.textLeft or "PERCENT"
		local centerMode = pcfg.textCenter or "NONE"
		local rightMode = pcfg.textRight or "CURMAX"
		local powerEnum = (getMainPower(unit) or 0)
		local cur = UnitPower(unit, powerEnum)
		local maxv = UnitPowerMax(unit, powerEnum)
		local percentVal
		if addon.variables and addon.variables.isMidnight then
			percentVal = getPowerPercent(unit, powerEnum, cur, maxv)
		elseif not issecretvalue or (not issecretvalue(cur) and not issecretvalue(maxv)) then
			percentVal = getPowerPercent(unit, powerEnum, cur, maxv)
		end

		local delimiter, delimiter2, delimiter3 = st._powerTextDelimiter1, st._powerTextDelimiter2, st._powerTextDelimiter3
		if not delimiter or not delimiter2 or not delimiter3 then
			local d1 = UFHelper.getTextDelimiter(pcfg, defP)
			local d2 = UFHelper.getTextDelimiterSecondary(pcfg, defP, d1)
			local d3 = UFHelper.getTextDelimiterTertiary(pcfg, defP, d1, d2)
			if UFHelper.resolveTextDelimiters then
				delimiter, delimiter2, delimiter3 = UFHelper.resolveTextDelimiters(d1, d2, d3)
			else
				delimiter, delimiter2, delimiter3 = d1, d2, d3
			end
		end

		local maxZero = false
		if not (issecretvalue and issecretvalue(maxv)) then maxZero = (maxv == 0) end
		local hidePercentSymbol = pcfg.hidePercentSymbol == true
		local roundPercent = pcfg.roundPercent == true
		local levelText
		if UFHelper.textModeUsesLevel(leftMode) or UFHelper.textModeUsesLevel(centerMode) or UFHelper.textModeUsesLevel(rightMode) then
			levelText = UFHelper.getUnitLevelText(unit, nil, shouldHideClassificationText(cfg, unit))
		end

		if st.powerTextLeft then
			if maxZero or leftMode == "NONE" then
				st.powerTextLeft:SetText("")
			else
				st.powerTextLeft:SetText(
					UFHelper.formatText(leftMode, cur, maxv, pcfg.useShortNumbers ~= false, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText, nil, roundPercent, true)
				)
			end
		end
		if st.powerTextCenter then
			if maxZero or centerMode == "NONE" then
				st.powerTextCenter:SetText("")
			else
				st.powerTextCenter:SetText(
					UFHelper.formatText(centerMode, cur, maxv, pcfg.useShortNumbers ~= false, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText, nil, roundPercent, true)
				)
			end
		end
		if st.powerTextRight then
			if maxZero or rightMode == "NONE" then
				st.powerTextRight:SetText("")
			else
				st.powerTextRight:SetText(
					UFHelper.formatText(rightMode, cur, maxv, pcfg.useShortNumbers ~= false, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText, nil, roundPercent, true)
				)
			end
		end

		st._powerTextDirty = nil
	end
end

function UF.UpdateAllTexts(force)
	UF.UpdateUnitTexts(UNIT.PLAYER, force)
	UF.UpdateUnitTexts(UNIT.TARGET, force)
	UF.UpdateUnitTexts(UNIT.TARGET_TARGET, force)
	UF.UpdateUnitTexts(UNIT.FOCUS, force)
	UF.UpdateUnitTexts(UNIT.PET, force)
	for i = 1, maxBossFrames do
		UF.UpdateUnitTexts("boss" .. i, force)
	end
end

function UF.EnsureTextTicker()
	if UF._textTicker or not NewTicker then return end
	UF._textTicker = NewTicker(TEXT_UPDATE_INTERVAL, function()
		if not anyUFEnabled() then return end
		UF.UpdateAllTexts(false)
	end)
end

function UF.CancelTextTicker()
	if UF._textTicker and UF._textTicker.Cancel then UF._textTicker:Cancel() end
	UF._textTicker = nil
end

function UF.UpdateAllPvPIndicators()
	UFHelper.updatePvPIndicator(states[UNIT.PLAYER], UNIT.PLAYER, getCfg(UNIT.PLAYER), defaultsFor(UNIT.PLAYER), false)
	UFHelper.updatePvPIndicator(states[UNIT.TARGET], UNIT.TARGET, getCfg(UNIT.TARGET), defaultsFor(UNIT.TARGET), false)
	UFHelper.updatePvPIndicator(states[UNIT.FOCUS], UNIT.FOCUS, getCfg(UNIT.FOCUS), defaultsFor(UNIT.FOCUS), false)
end

function UF.UpdateAllRoleIndicators(skipDisabled)
	UFHelper.updateRoleIndicator(states[UNIT.PLAYER], UNIT.PLAYER, getCfg(UNIT.PLAYER), defaultsFor(UNIT.PLAYER), skipDisabled)
	UFHelper.updateRoleIndicator(states[UNIT.TARGET], UNIT.TARGET, getCfg(UNIT.TARGET), defaultsFor(UNIT.TARGET), skipDisabled)
	UFHelper.updateRoleIndicator(states[UNIT.FOCUS], UNIT.FOCUS, getCfg(UNIT.FOCUS), defaultsFor(UNIT.FOCUS), skipDisabled)
end

function UF.UpdateAllLeaderIndicators(skipDisabled)
	UFHelper.updateLeaderIndicator(states[UNIT.PLAYER], UNIT.PLAYER, getCfg(UNIT.PLAYER), defaultsFor(UNIT.PLAYER), skipDisabled)
	UFHelper.updateLeaderIndicator(states[UNIT.TARGET], UNIT.TARGET, getCfg(UNIT.TARGET), defaultsFor(UNIT.TARGET), skipDisabled)
	UFHelper.updateLeaderIndicator(states[UNIT.FOCUS], UNIT.FOCUS, getCfg(UNIT.FOCUS), defaultsFor(UNIT.FOCUS), skipDisabled)
end

onEvent = function(self, event, unit, ...)
	local arg1 = ...
	if
		(unitEventsMap[event] or portraitEventsMap[event])
		and unit
		and not allowedEventUnit[unit]
		and event ~= "UNIT_THREAT_SITUATION_UPDATE"
		and event ~= "UNIT_THREAT_LIST_UPDATE"
		and event ~= "UNIT_PET"
	then
		return
	end
	if (unitEventsMap[event] or portraitEventsMap[event]) and unit and isBossUnit(unit) and not isBossFrameSettingEnabled() then return end
	if event == "SPELL_RANGE_CHECK_UPDATE" then
		local spellIdentifier = unit
		local isInRange, checksRange = ...
		if UFHelper and UFHelper.RangeFadeUpdateFromEvent then UFHelper.RangeFadeUpdateFromEvent(spellIdentifier, isInRange, checksRange) end
		return
	end
	if event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" or event == "TRAIT_CONFIG_UPDATED" then
		refreshRangeFadeSpells(true)
		return
	end
	if event == "PLAYER_LOGIN" then
		updateNameAndLevel(getCfg(UNIT.PLAYER), UNIT.PLAYER)
	elseif event == "PLAYER_ENTERING_WORLD" then
		local playerCfg = getCfg(UNIT.PLAYER)
		local targetCfg = getCfg(UNIT.TARGET)
		local totCfg = getCfg(UNIT.TARGET_TARGET)
		local petCfg = getCfg(UNIT.PET)
		local focusCfg = getCfg(UNIT.FOCUS)
		local bossCfg = getCfg("boss")
		refreshRangeFadeSpells(true)
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
		UF.UpdateAllPvPIndicators()
		UF.UpdateAllRoleIndicators(false)
		UF.UpdateAllLeaderIndicators(false)
		UFHelper.updateAllHighlights(states, UNIT, maxBossFrames)
		updateAllRaidTargetIcons()
		if bossCfg.enabled then
			updateBossFrames(true)
		else
			hideBossFrames()
		end
	elseif event == "PLAYER_DEAD" then
		local playerCfg = getCfg(UNIT.PLAYER)
		local interpolation = getSmoothInterpolation(playerCfg, defaultsFor(UNIT.PLAYER))
		if states.player and states.player.health then states.player.health:SetValue(0, interpolation) end
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
		UFHelper.updatePvPIndicator(states[UNIT.PLAYER], UNIT.PLAYER, getCfg(UNIT.PLAYER), defaultsFor(UNIT.PLAYER), true)
		UFHelper.updateLeaderIndicator(states[UNIT.PLAYER], UNIT.PLAYER, getCfg(UNIT.PLAYER), defaultsFor(UNIT.PLAYER), true)
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
		if UFHelper and UFHelper.RangeFadeReset then UFHelper.RangeFadeReset() end
		local targetCfg = getCfg(UNIT.TARGET)
		local totCfg = getCfg(UNIT.TARGET_TARGET)
		local focusCfg = getCfg(UNIT.FOCUS)
		local unitToken = UNIT.TARGET
		local st = states[unitToken]
		if not st or not st.frame then
			AuraUtil.resetTargetAuras()
			AuraUtil.updateTargetAuraIcons()
			if totCfg.enabled then updateTargetTargetFrame(totCfg) end
			if focusCfg.enabled then updateFocusFrame(focusCfg) end
			return
		end
		if UnitExists(unitToken) then
			if not C_PlayerInteractionManager.IsReplacingUnit() then
				if UnitIsEnemy(unitToken, "player") then
					PlaySound(SOUNDKIT.IG_CREATURE_AGGRO_SELECT)
				elseif UnitIsFriend("player", unitToken) then
					PlaySound(SOUNDKIT.IG_CHARACTER_NPC_SELECT)
				else
					PlaySound(SOUNDKIT.IG_CREATURE_NEUTRAL_SELECT)
				end
			end

			refreshMainPower(unitToken)
			AuraUtil.fullScanTargetAuras()
			local pcfg = targetCfg.power or {}
			local powerEnabled = pcfg.enabled ~= false
			updateNameAndLevel(targetCfg, unitToken)
			updateHealth(targetCfg, unitToken)
			if st.power and powerEnabled then
				local powerEnum, powerToken = getMainPower(unitToken)
				UFHelper.configureSpecialTexture(st.power, powerToken, (targetCfg.power or {}).texture, targetCfg.power, powerEnum)
			elseif st.power then
				st.power:Hide()
			end
			updatePower(targetCfg, unitToken)
			st.barGroup:Show()
			st.status:Show()
			setCastInfoFromUnit(unitToken)
			if st.privateAuras and UFHelper and UFHelper.RemovePrivateAuras and UFHelper.ApplyPrivateAuras then
				UFHelper.RemovePrivateAuras(st.privateAuras)
				if st.privateAuras.Hide then st.privateAuras:Hide() end
				local pcfg = targetCfg.privateAuras or (defaultsFor(unitToken) and defaultsFor(unitToken).privateAuras)
				local function applyPrivate()
					if not states[unitToken] or states[unitToken] ~= st then return end
					if not UnitExists(unitToken) then return end
					UFHelper.ApplyPrivateAuras(st.privateAuras, unitToken, pcfg, st.frame, st.statusTextLayer or st.frame, addon.EditModeLib and addon.EditModeLib:IsInEditMode(), true)
				end
				if After then
					After(0, applyPrivate)
				else
					applyPrivate()
				end
			end
		else
			AuraUtil.resetTargetAuras()
			AuraUtil.updateTargetAuraIcons()
			st.barGroup:Hide()
			st.status:Hide()
			stopCast(unitToken)
			if st.privateAuras and UFHelper and UFHelper.RemovePrivateAuras then
				UFHelper.RemovePrivateAuras(st.privateAuras)
				if st.privateAuras.Hide then st.privateAuras:Hide() end
			end
		end
		checkRaidTargetIcon(unitToken, st)
		updatePortrait(targetCfg, unitToken)
		UFHelper.updateHighlight(st, unitToken, UNIT.PLAYER)
		if totCfg.enabled then updateTargetTargetFrame(totCfg) end
		if focusCfg.enabled then updateFocusFrame(focusCfg) end
		updateUnitStatusIndicator(targetCfg, UNIT.TARGET)
		UFHelper.updateLeaderIndicator(states[UNIT.TARGET], UNIT.TARGET, targetCfg, defaultsFor(UNIT.TARGET), true)
		UFHelper.updatePvPIndicator(states[UNIT.TARGET], UNIT.TARGET, targetCfg, defaultsFor(UNIT.TARGET), true)
		UFHelper.updateRoleIndicator(states[UNIT.TARGET], UNIT.TARGET, targetCfg, defaultsFor(UNIT.TARGET), true)
		updateUnitStatusIndicator(totCfg, UNIT.TARGET_TARGET)
	elseif event == "UNIT_AURA" and (unit == "target" or unit == UNIT.PLAYER or unit == UNIT.FOCUS or isBossUnit(unit)) then
		local cfg = getCfg(unit)
		if not cfg or cfg.enabled == false then return end
		local def = defaultsFor(unit)
		local ac = cfg.auraIcons or (def and def.auraIcons) or defaults.target.auraIcons or { size = 24, padding = 2, max = 16, showCooldown = true }
		if not AuraUtil.isAuraIconsEnabled(ac, def) then return end
		local showBuffs = ac.showBuffs ~= false
		local showDebuffs = ac.showDebuffs ~= false
		if not showBuffs and not showDebuffs then
			AuraUtil.resetTargetAuras(unit)
			AuraUtil.updateTargetAuraIcons(nil, unit)
			return
		end
		if addon.EditModeLib and addon.EditModeLib:IsInEditMode() then
			local st = states[unit]
			if st and st._sampleAurasActive then return end
			AuraUtil.fullScanTargetAuras(unit)
			return
		end
		local helpfulFilter, harmfulFilter = AuraUtil.getAuraFilters(unit)
		local eventInfo = arg1
		if not UnitExists(unit) then
			AuraUtil.resetTargetAuras(unit)
			AuraUtil.updateTargetAuraIcons(nil, unit)
			return
		end
		if not eventInfo or eventInfo.isFullUpdate then
			AuraUtil.fullScanTargetAuras(unit)
			return
		end
		ac.size = ac.size or 24
		ac.padding = ac.padding or 0
		ac.max = ac.max or 16
		if ac.max < 1 then ac.max = 1 end
		local hidePermanent = ac.hidePermanentAuras == true or ac.hidePermanent == true
		local st = states[unit]
		if not st or not st.auraContainer then return end
		local auras, order, indexById = AuraUtil.getAuraTables(unit)
		if not auras or not order or not indexById then return end
		local firstChanged
		if eventInfo.addedAuras then
			for _, aura in ipairs(eventInfo.addedAuras) do
				if aura and hidePermanent and AuraUtil.isPermanentAura(aura, unit) then
					if auras[aura.auraInstanceID] then
						auras[aura.auraInstanceID] = nil
						local idx = AuraUtil.removeTargetAuraFromOrder(aura.auraInstanceID, unit)
						if idx and idx <= (ac.max + 1) then
							if not firstChanged or idx < firstChanged then firstChanged = idx end
						end
					end
				elseif aura and showDebuffs and not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, aura.auraInstanceID, harmfulFilter) then
					AuraUtil.cacheTargetAura(aura, unit)
					local idx = AuraUtil.addTargetAuraToOrder(aura.auraInstanceID, unit)
					if idx and idx <= ac.max then
						if not firstChanged or idx < firstChanged then firstChanged = idx end
					end
				elseif aura and showBuffs and not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, aura.auraInstanceID, helpfulFilter) then
					AuraUtil.cacheTargetAura(aura, unit)
					local idx = AuraUtil.addTargetAuraToOrder(aura.auraInstanceID, unit)
					if idx and idx <= ac.max then
						if not firstChanged or idx < firstChanged then firstChanged = idx end
					end
				end
			end
		end
		if eventInfo.updatedAuraInstanceIDs and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
			for _, inst in ipairs(eventInfo.updatedAuraInstanceIDs) do
				if auras[inst] then
					local data = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, inst)
					if data then AuraUtil.cacheTargetAura(data, unit) end
				end
				local idx = indexById[inst]
				if idx and idx <= ac.max then
					if not firstChanged or idx < firstChanged then firstChanged = idx end
				end
			end
		end
		if eventInfo.removedAuraInstanceIDs then
			for _, inst in ipairs(eventInfo.removedAuraInstanceIDs) do
				auras[inst] = nil
				local idx = AuraUtil.removeTargetAuraFromOrder(inst, unit)
				if idx and idx <= (ac.max + 1) then -- +1 to relayout if we pulled a hidden aura into view
					if not firstChanged or idx < firstChanged then firstChanged = idx end
				end
			end
		end
		if firstChanged then AuraUtil.updateTargetAuraIcons(firstChanged, unit) end
	elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
		if event == "UNIT_ABSORB_AMOUNT_CHANGED" and unit then
			local st = states[unit]
			if st then
				local guid = UnitGUID and UnitGUID(unit) or unit
				if issecretvalue and issecretvalue(guid) then
					st._absorbCacheGuid = nil
				else
					st._absorbCacheGuid = guid
				end
				st._absorbAmount = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0
			end
		elseif event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" and unit then
			local st = states[unit]
			if st then
				local guid = UnitGUID and UnitGUID(unit) or unit
				if issecretvalue and issecretvalue(guid) then
					st._absorbCacheGuid = nil
				else
					st._absorbCacheGuid = guid
				end
				st._healAbsorbAmount = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit) or 0
			end
		end
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
			if playerCfg.enabled == false then return end
			refreshMainPower(unit)
			local st = states[unit]
			local pcfg = playerCfg.power or {}
			if st and st.power and pcfg.enabled ~= false then
				local powerEnum, powerToken = getMainPower(unit)
				UFHelper.configureSpecialTexture(st.power, powerToken, (playerCfg.power or {}).texture, playerCfg.power, powerEnum)
			elseif st and st.power then
				st.power:Hide()
			end
			updatePower(playerCfg, UNIT.PLAYER)
		elseif unit == UNIT.TARGET then
			local targetCfg = getCfg(UNIT.TARGET)
			if targetCfg.enabled == false then return end
			local st = states[unit]
			local pcfg = targetCfg.power or {}
			if st and st.power and pcfg.enabled ~= false then
				local powerEnum, powerToken = getMainPower(unit)
				UFHelper.configureSpecialTexture(st.power, powerToken, (targetCfg.power or {}).texture, targetCfg.power, powerEnum)
			elseif st and st.power then
				st.power:Hide()
			end
			updatePower(targetCfg, UNIT.TARGET)
		elseif unit == UNIT.FOCUS then
			local focusCfg = getCfg(UNIT.FOCUS)
			if focusCfg.enabled == false then return end
			local st = states[unit]
			local pcfg = focusCfg.power or {}
			if st and st.power and pcfg.enabled ~= false then
				local powerEnum, powerToken = getMainPower(unit)
				UFHelper.configureSpecialTexture(st.power, powerToken, (focusCfg.power or {}).texture, focusCfg.power, powerEnum)
			elseif st and st.power then
				st.power:Hide()
			end
			updatePower(focusCfg, UNIT.FOCUS)
		elseif unit == UNIT.PET then
			local petCfg = getCfg(UNIT.PET)
			if petCfg.enabled == false then return end
			local st = states[unit]
			local pcfg = petCfg.power or {}
			if st and st.power and pcfg.enabled ~= false then
				local powerEnum, powerToken = getMainPower(unit)
				UFHelper.configureSpecialTexture(st.power, powerToken, (petCfg.power or {}).texture, petCfg.power, powerEnum)
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
					local powerEnum, powerToken = getMainPower(unit)
					UFHelper.configureSpecialTexture(st.power, powerToken, (bossCfg.power or {}).texture, bossCfg.power, powerEnum)
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
		if event == "PLAYER_LEVEL_UP" then
			updateNameAndLevel(getCfg(UNIT.PLAYER), UNIT.PLAYER, unit)
		elseif unit == UNIT.PLAYER then
			updateNameAndLevel(getCfg(UNIT.PLAYER), UNIT.PLAYER)
		end
		if unit == UNIT.TARGET then updateNameAndLevel(getCfg(UNIT.TARGET), UNIT.TARGET) end
		if unit == UNIT.FOCUS then updateNameAndLevel(getCfg(UNIT.FOCUS), UNIT.FOCUS) end
		if unit == UNIT.PET then updateNameAndLevel(getCfg(UNIT.PET), UNIT.PET) end
		if isBossUnit(unit) then
			local bossCfg = getCfg(unit)
			if bossCfg.enabled then updateNameAndLevel(bossCfg, unit) end
		end
	elseif event == "UNIT_CLASSIFICATION_CHANGED" then
		if unit and states[unit] then UFHelper.updateClassificationIndicator(states[unit], unit, getCfg(unit), defaultsFor(unit), true) end
	elseif event == "UNIT_FLAGS" then
		updateUnitStatusIndicator(getCfg(unit), unit)
		UFHelper.updateLeaderIndicator(states[unit], unit, getCfg(unit), defaultsFor(unit), true)
		UFHelper.updatePvPIndicator(states[unit], unit, getCfg(unit), defaultsFor(unit), true)
		if states[unit] then states[unit]._healthColorDirty = true end
		if unit == UNIT.TARGET then updateHealth(getCfg(UNIT.TARGET), UNIT.TARGET) end
		if unit == UNIT.TARGET_TARGET then updateHealth(getCfg(UNIT.TARGET_TARGET), UNIT.TARGET_TARGET) end
		if unit == UNIT.FOCUS then updateHealth(getCfg(UNIT.FOCUS), UNIT.FOCUS) end
		if isBossUnit(unit) then
			local bossCfg = getCfg(unit)
			if bossCfg.enabled then updateHealth(bossCfg, unit) end
		end
		if allowedEventUnit[UNIT.TARGET_TARGET] then updateUnitStatusIndicator(getCfg(UNIT.TARGET_TARGET), UNIT.TARGET_TARGET) end
	elseif event == "UNIT_CONNECTION" then
		updateUnitStatusIndicator(getCfg(unit), unit)
		if states[unit] then states[unit]._healthColorDirty = true end
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
	elseif event == "UNIT_FACTION" then
		UFHelper.updatePvPIndicator(states[unit], unit, getCfg(unit), defaultsFor(unit), true)
		if states[unit] then states[unit]._healthColorDirty = true end
		if unit == UNIT.TARGET then updateHealth(getCfg(UNIT.TARGET), UNIT.TARGET) end
		if unit == UNIT.TARGET_TARGET then updateHealth(getCfg(UNIT.TARGET_TARGET), UNIT.TARGET_TARGET) end
		if unit == UNIT.FOCUS then updateHealth(getCfg(UNIT.FOCUS), UNIT.FOCUS) end
		if isBossUnit(unit) then
			local bossCfg = getCfg(unit)
			if bossCfg.enabled then updateHealth(bossCfg, unit) end
		end
	elseif event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" then
		if unit ~= "player" and unit ~= "pet" then return end
		UFHelper.updateHighlight(states[UNIT.PLAYER], UNIT.PLAYER, UNIT.PLAYER)
		UFHelper.updateHighlight(states[UNIT.PET], UNIT.PET, UNIT.PLAYER)
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
	elseif event == "UNIT_SPELLCAST_SENT" then
		if unit == UNIT.PLAYER then
			local st = states[unit]
			if st then st.castTarget = arg1 end
		end
	elseif
		event == "UNIT_SPELLCAST_START"
		or event == "UNIT_SPELLCAST_CHANNEL_START"
		or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
		or event == "UNIT_SPELLCAST_EMPOWER_START"
		or event == "UNIT_SPELLCAST_EMPOWER_UPDATE"
		or event == "UNIT_SPELLCAST_DELAYED"
	then
		if unit == UNIT.PLAYER then setCastInfoFromUnit(UNIT.PLAYER) end
		if unit == UNIT.TARGET then setCastInfoFromUnit(UNIT.TARGET) end
		if unit == UNIT.FOCUS then setCastInfoFromUnit(UNIT.FOCUS) end
		if isBossUnit(unit) then setCastInfoFromUnit(unit) end
	elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
		local castGUID, spellId = ...
		if unit == UNIT.PLAYER and not shouldIgnoreCastFail(UNIT.PLAYER, castGUID, spellId) then UF.ShowCastInterrupt(UNIT.PLAYER, event) end
		if unit == UNIT.TARGET and not shouldIgnoreCastFail(UNIT.TARGET, castGUID, spellId) then UF.ShowCastInterrupt(UNIT.TARGET, event) end
		if unit == UNIT.FOCUS and not shouldIgnoreCastFail(UNIT.FOCUS, castGUID, spellId) then UF.ShowCastInterrupt(UNIT.FOCUS, event) end
		if isBossUnit(unit) and not shouldIgnoreCastFail(unit, castGUID, spellId) then UF.ShowCastInterrupt(unit, event) end
	elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
		if unit == UNIT.PLAYER then
			if not (states[UNIT.PLAYER] and states[UNIT.PLAYER].castInterruptActive) then
				stopCast(UNIT.PLAYER)
				if shouldShowSampleCast(unit) then setSampleCast(unit) end
			end
		end
		if unit == UNIT.TARGET then
			if not (states[UNIT.TARGET] and states[UNIT.TARGET].castInterruptActive) then
				stopCast(UNIT.TARGET)
				if shouldShowSampleCast(unit) then setSampleCast(unit) end
			end
		end
		if unit == UNIT.FOCUS then
			if not (states[UNIT.FOCUS] and states[UNIT.FOCUS].castInterruptActive) then
				stopCast(UNIT.FOCUS)
				if shouldShowSampleCast(unit) then setSampleCast(unit) end
			end
		end
		if isBossUnit(unit) then
			if not (states[unit] and states[unit].castInterruptActive) then stopCast(unit) end
		end
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
		UFHelper.updateLeaderIndicator(states[UNIT.FOCUS], UNIT.FOCUS, focusCfg, defaultsFor(UNIT.FOCUS), true)
		UFHelper.updatePvPIndicator(states[UNIT.FOCUS], UNIT.FOCUS, focusCfg, defaultsFor(UNIT.FOCUS), true)
		UFHelper.updateRoleIndicator(states[UNIT.FOCUS], UNIT.FOCUS, focusCfg, defaultsFor(UNIT.FOCUS), true)
		UFHelper.updateHighlight(states[UNIT.FOCUS], UNIT.FOCUS, UNIT.PLAYER)
	elseif event == "PLAYER_UPDATE_RESTING" then
		updateRestingIndicator(getCfg(UNIT.PLAYER))
	elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
		local playerCfg = getCfg(UNIT.PLAYER)
		local defStatus = (defaultsFor(UNIT.PLAYER) and defaultsFor(UNIT.PLAYER).status) or {}
		local usDef = defStatus.unitStatus or {}
		local usCfg = (playerCfg.status and playerCfg.status.unitStatus) or usDef or {}
		if playerCfg.enabled ~= false and usCfg.enabled == true and usCfg.showGroup == true then updateUnitStatusIndicator(playerCfg, UNIT.PLAYER) end
		UF.UpdateAllRoleIndicators(true)
		UF.UpdateAllLeaderIndicators(true)
	elseif event == "CLIENT_SCENE_OPENED" then
		local sceneType = unit
		UF._clientSceneActive = (sceneType == 1)
		UF.RefreshClientSceneVisibility()
	elseif event == "CLIENT_SCENE_CLOSED" then
		UF._clientSceneActive = false
		UF.RefreshClientSceneVisibility()
	elseif event == "RAID_TARGET_UPDATE" then
		updateAllRaidTargetIcons()
	end
end

local function ensureEventHandling()
	rebuildAllowedEventUnits()
	if not anyUFEnabled() then
		hideBossFrames()
		refreshRangeFadeSpells(true)
		UF.CancelTextTicker()
		if UFHelper and UFHelper.disableCombatFeedbackAll then UFHelper.disableCombatFeedbackAll(states) end
		if eventFrame and eventFrame.UnregisterAllEvents then eventFrame:UnregisterAllEvents() end
		if eventFrame then eventFrame:SetScript("OnEvent", nil) end
		eventFrame = nil
		UF._clearUnitEventFrames()
		return
	end
	if not eventFrame then
		eventFrame = CreateFrame("Frame")
		eventFrame:SetScript("OnEvent", onEvent)
		if not editModeHooked then
			editModeHooked = true

			addon.EditModeLib:RegisterCallback("enter", function()
				updateCombatIndicator(states[UNIT.PLAYER] and states[UNIT.PLAYER].cfg or ensureDB(UNIT.PLAYER))
				ensureBossFramesReady(ensureDB("boss"))
				updateBossFrames(true)
				updateAllRaidTargetIcons()
				UF.UpdateAllPvPIndicators()
				UF.UpdateAllRoleIndicators(false)
				UF.UpdateAllLeaderIndicators(false)
				applyVisibilityRulesAll()
				if UF.Refresh then UF.Refresh() end
				if states[UNIT.PLAYER] and states[UNIT.PLAYER].castBar then setCastInfoFromUnit(UNIT.PLAYER) end
				if states[UNIT.TARGET] and states[UNIT.TARGET].castBar then setCastInfoFromUnit(UNIT.TARGET) end
				if states[UNIT.FOCUS] and states[UNIT.FOCUS].castBar then setCastInfoFromUnit(UNIT.FOCUS) end
				refreshRangeFadeSpells(false)
			end)

			addon.EditModeLib:RegisterCallback("exit", function()
				updateCombatIndicator(states[UNIT.PLAYER] and states[UNIT.PLAYER].cfg or ensureDB(UNIT.PLAYER))
				hideBossFrames(true)
				if ensureDB("boss").enabled then updateBossFrames(true) end
				updateAllRaidTargetIcons()
				UF.UpdateAllPvPIndicators()
				UF.UpdateAllRoleIndicators(false)
				UF.UpdateAllLeaderIndicators(false)
				applyVisibilityRulesAll()
				if UF.Refresh then UF.Refresh() end
				if ensureDB("target").enabled then AuraUtil.fullScanTargetAuras(UNIT.TARGET) end
				if ensureDB(UNIT.FOCUS).enabled then AuraUtil.fullScanTargetAuras(UNIT.FOCUS) end
				if states[UNIT.PLAYER] and states[UNIT.PLAYER].castBar then setCastInfoFromUnit(UNIT.PLAYER) end
				if states[UNIT.TARGET] and states[UNIT.TARGET].castBar then setCastInfoFromUnit(UNIT.TARGET) end
				if states[UNIT.FOCUS] and states[UNIT.FOCUS].castBar then setCastInfoFromUnit(UNIT.FOCUS) end
				refreshRangeFadeSpells(false)
				if UFHelper and UFHelper.stopCombatFeedbackSample then
					for _, st in pairs(states) do
						UFHelper.stopCombatFeedbackSample(st)
					end
				end
			end)
		end
	end
	if eventFrame.UnregisterAllEvents then eventFrame:UnregisterAllEvents() end
	for _, evt in ipairs(generalEvents) do
		eventFrame:RegisterEvent(evt)
	end
	UF._registerUnitScopedEvents(anyPortraitEnabled())
	syncTargetRangeFadeConfig(ensureDB(UNIT.TARGET), defaultsFor(UNIT.TARGET))
	refreshRangeFadeSpells(false)
	UF.EnsureTextTicker()
	UF.UpdateAllTexts(true)
end

local function refreshStandaloneCastbar()
	local standalone = addon.Aura and addon.Aura.UFStandaloneCastbar
	if standalone and standalone.Refresh then standalone.Refresh() end
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
	if addon.functions and addon.functions.UpdateClassResourceVisibility then addon.functions.UpdateClassResourceVisibility() end
	-- hideBlizzardPlayerFrame()
	-- hideBlizzardTargetFrame()
	refreshStandaloneCastbar()
end

function UF.Disable()
	local cfg = ensureDB("player")
	cfg.enabled = false
	if states.player and states.player.frame then states.player.frame:Hide() end
	ClassResourceUtil.restoreClassResourceFrames()
	TotemFrameUtil.restoreTotemFrame()
	stopToTTicker()
	applyVisibilityRules("player")
	addon.variables.requireReload = true
	if addon.functions and addon.functions.checkReloadFrame then addon.functions.checkReloadFrame() end
	if _G.PlayerFrame and not InCombatLockdown() then
		_G.PlayerFrame:SetAlpha(1)
		_G.PlayerFrame:Show()
	end
	ensureEventHandling()
	if addon.functions and addon.functions.UpdateClassResourceVisibility then addon.functions.UpdateClassResourceVisibility() end
	refreshStandaloneCastbar()
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
	refreshStandaloneCastbar()
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
	if unit == nil or unit == UNIT.PLAYER then refreshStandaloneCastbar() end
end

function UF.Initialize()
	if addon.Aura.UFInitialized then return end
	if not addon.db then return end
	addon.Aura.UFInitialized = true
	if UF.RegisterSettings then UF.RegisterSettings() end
	local cfg = ensureDB("player")
	do
		local def = defaultsFor(UNIT.PLAYER)
		local rcfg = (cfg and cfg.classResource) or (def and def.classResource) or {}
		local frameLevelOffset = tonumber(rcfg.frameLevelOffset)
		if frameLevelOffset == nil then frameLevelOffset = tonumber(def and def.classResource and def.classResource.frameLevelOffset) end
		if frameLevelOffset == nil then frameLevelOffset = 5 end
		if frameLevelOffset < 0 then frameLevelOffset = 0 end
		if ClassResourceUtil.SetFrameLevelHookOffset then ClassResourceUtil.SetFrameLevelHookOffset(frameLevelOffset) end
	end
	if cfg.enabled then After(0.1, function() UF.Enable() end) end
	cfg = ensureDB("target")
	if cfg.enabled then
		ensureEventHandling()
		applyConfig("target")
		-- hideBlizzardTargetFrame()
	end
	cfg = ensureDB(UNIT.TARGET_TARGET)
	if cfg.enabled then
		ensureEventHandling()
		updateTargetTargetFrame(cfg, true)
		ensureToTTicker()
	end
	cfg = ensureDB(UNIT.PET)
	if cfg.enabled then
		ensureEventHandling()
		applyConfig(UNIT.PET)
	elseif applyFrameRuleOverride then
		applyFrameRuleOverride(BLIZZ_FRAME_NAMES.pet, false)
	end
	cfg = ensureDB(UNIT.FOCUS)
	if cfg.enabled then
		ensureEventHandling()
		updateFocusFrame(cfg, true)
	elseif applyFrameRuleOverride then
		applyFrameRuleOverride(BLIZZ_FRAME_NAMES.focus, false)
	end
	cfg = ensureDB("boss")
	if cfg.enabled then
		ensureEventHandling()
		ensureBossFramesReady(cfg)
		updateBossFrames(true)
	end
	if isBossFrameSettingEnabled() then DisableBossFrames() end
	refreshStandaloneCastbar()
end

addon.Aura.functions = addon.Aura.functions or {}
addon.Aura.functions.InitUnitFrames = function()
	if UF and UF.Initialize then UF.Initialize() end
end

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
UF.FullScanTargetAuras = AuraUtil.fullScanTargetAuras
UF.CopySettings = copySettings
addon.Aura.functions = addon.Aura.functions or {}
addon.Aura.functions.importUFProfile = UF.ImportProfile
addon.Aura.functions.exportUFProfile = UF.ExportProfile

addon.exportUFProfile = function(profileName, scopeKey) return UF.ExportProfile(scopeKey, profileName) end
addon.importUFProfile = function(encoded, scopeKey) return UF.ImportProfile(encoded, scopeKey) end
