local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Aura = addon.Aura or {}
local ResourceBars = {}
addon.Aura.ResourceBars = ResourceBars
ResourceBars.ui = ResourceBars.ui or {}

-- forward declarations to satisfy luacheck for early function
local LSM = LibStub("LibSharedMedia-3.0")

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")

local UnitPower, UnitPowerMax, UnitHealth, UnitHealthMax, UnitGetTotalAbsorbs, UnitStagger, GetTime = UnitPower, UnitPowerMax, UnitHealth, UnitHealthMax, UnitGetTotalAbsorbs, UnitStagger, GetTime
local CreateFrame = CreateFrame
local After = C_Timer and C_Timer.After
local CopyTable = CopyTable
local tostring = tostring
local floor, max, min, ceil, abs = math.floor, math.max, math.min, math.ceil, math.abs
local tinsert, tsort = table.insert, table.sort
local applyVisibilityDriverToFrame
local registerEditModeCallbacks

local frameAnchor
local mainFrame
local healthBar
local powerbar = {}
local powerfrequent = {}
local getBarSettings
local getAnchor
local layoutRunes
local createHealthBar
local updateHealthBar
local updatePowerBar
local updateBarSeparators
local updateBarThresholds
local forceColorUpdate
local applyAbsorbLayout
local setParentBarTextureVisible
local getSeparatorSegmentCount
local shouldUseDiscreteSeparatorSegments
local refreshDiscreteSegmentsForBar
local ensureEditModeRegistration
local lastBarSelectionPerSpec = {}
local lastSpecCopySelection = {}
local lastProfileShareScope = {}
local lastSpecCopyMode = {}
local lastSpecCopyBar = {}
local lastSpecCopyCosmetic = {}
local visibilityDriverWatcher
local ResourcebarVars = {
	RESOURCE_SHARE_KIND = "EQOL_RESOURCE_BAR_PROFILE",
	COOLDOWN_VIEWER_FRAME_NAME = "EssentialCooldownViewer",
	MIN_RESOURCE_BAR_WIDTH = 10,
	DEFAULT_STACK_SPACING = 0,
	SEPARATOR_THICKNESS = 1,
	SEP_DEFAULT = { 1, 1, 1, 0.5 },
	THRESHOLD_THICKNESS = 1,
	THRESHOLD_DEFAULT = { 1, 1, 1, 0.5 },
	DEFAULT_THRESHOLDS = { 25, 50, 75, 90 },
	DEFAULT_THRESHOLD_COUNT = 3,
	WHITE = { 1, 1, 1, 1 },
	DEFAULT_RB_TEX = "Interface\\Buttons\\WHITE8x8", -- historical default (Solid)
	DEFAULT_HEALTH_WIDTH = 200,
	DEFAULT_HEALTH_HEIGHT = 20,
	DEFAULT_POWER_WIDTH = 200,
	DEFAULT_POWER_HEIGHT = 20,
	BLIZZARD_TEX = "Interface\\TargetingFrame\\UI-StatusBar",
	RUNE_UPDATE_INTERVAL = 0.1,
	ESSENCE_UPDATE_INTERVAL = 0.1,
	REFRESH_DEBOUNCE = 0.05,
	REANCHOR_REFRESH = { reanchorOnly = true },
	OOC_VISIBILITY_DRIVER = "[combat] show; hide",
	MAELSTROM_WEAPON_MAX_STACKS = 10,
	MAELSTROM_WEAPON_SEGMENTS = 5,
	MAELSTROM_WEAPON_SPELL_ID = 344179,
	VOID_METAMORPHOSIS_SPELL_ID = 1225789,
	VOID_META_TALENT_SOUL_GLUTTON_SPELL_ID = 1247534,
	COLLAPSING_STAR_SPELL_ID = 1227702,
	DEFAULT_MAELSTROM_WEAPON_FIVE_COLOR = { 0.10, 0.85, 0.55, 1 },
	CUSTOM_POWER_COLORS = {
		MAELSTROM_WEAPON = { 0.15, 0.45, 1.00 },
	},
	POWER_LABELS = {},
	AURA_POWER_CONFIG = {},
}
local RB = ResourcebarVars
RB.UNITFRAME_ANCHOR_MAP = {
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

function ResourceBars.IsMappedUFEnabled(ufKey)
	local ufCfg = addon.db and addon.db.ufFrames
	local cfg = ufCfg and ufCfg[ufKey]
	return cfg and cfg.enabled == true
end

function ResourceBars.ResolveRelativeFrameByName(relativeName)
	if type(relativeName) ~= "string" or relativeName == "" or relativeName == "UIParent" then return UIParent end
	local mapped = RB.UNITFRAME_ANCHOR_MAP[relativeName]
	if mapped then
		if mapped.ufKey and ResourceBars.IsMappedUFEnabled(mapped.ufKey) then
			local ufFrame = _G[mapped.uf]
			if ufFrame then return ufFrame end
		end
		local blizzFrame = _G[mapped.blizz]
		if blizzFrame then return blizzFrame end
	end
	return _G[relativeName] or UIParent
end

function ResourceBars.RelativeFrameMatchesName(relativeName, frameName)
	if not relativeName or not frameName then return false end
	if relativeName == frameName then return true end
	local mapped = RB.UNITFRAME_ANCHOR_MAP[relativeName]
	if not mapped then return false end
	return frameName == mapped.uf or frameName == mapped.blizz
end

function ResourceBars.GetRelativeFrameHookTargets(relativeName)
	local targets = {}
	local seen = {}
	local function add(name)
		if type(name) ~= "string" or name == "" or seen[name] then return end
		seen[name] = true
		targets[#targets + 1] = name
	end
	local mapped = RB.UNITFRAME_ANCHOR_MAP[relativeName]
	if mapped then
		add(mapped.blizz)
		add(mapped.uf)
	end
	add(relativeName)
	return targets
end

local requestActiveRefresh
local getStatusbarDropdownLists
local ensureRelativeFrameHooks
local scheduleRelativeFrameWidthSync
local ensureSpecCfg
local classPowerTypes
local powertypeClasses
local auraPowerState = {}
local auraInstanceToType = {}
local auraSpellToType = {}
local COSMETIC_BAR_KEYS = {
	"barTexture",
	"width",
	"height",
	"textStyle",
	"shortNumbers",
	"percentRounding",
	"hidePercentSign",
	"fontSize",
	"fontFace",
	"fontOutline",
	"fontColor",
	"textOffset",
	"useBarColor",
	"barColor",
	"useClassColor",
	"useMaxColor",
	"maxColor",
	"useGradient",
	"gradientStartColor",
	"gradientEndColor",
	"gradientDirection",
	"staggerHighColors",
	"staggerHighThreshold",
	"staggerExtremeThreshold",
	"staggerHighColor",
	"staggerExtremeColor",
	"useMaelstromFiveColor",
	"useMaelstromTenStacks",
	"maelstromFiveColor",
	"useHolyThreeColor",
	"holyThreeColor",
	"runeCooldownColor",
	"absorbEnabled",
	"absorbUseCustomColor",
	"absorbColor",
	"absorbTexture",
	"absorbSample",
	"absorbReverseFill",
	"absorbOverfill",
	"reverseFill",
	"verticalFill",
	"smoothFill",
	"showSeparator",
	"separatorColor",
	"separatorThickness",
	"showThresholds",
	"useAbsoluteThresholds",
	"thresholds",
	"thresholdColor",
	"thresholdThickness",
	"thresholdCount",
	"showCooldownText",
	"cooldownTextFontSize",
	"backdrop",
}

local wasMax = false
local wasMaxPower = {}
local curve = C_CurveUtil and C_CurveUtil.CreateColorCurve()
local curvePower = {}
local function SetColorCurvePoints(maxColor)
	if curve then
		curve = C_CurveUtil and C_CurveUtil.CreateColorCurve()
		curve:SetType(Enum.LuaCurveType.Cosine)
		if maxColor then
			curve:AddPoint(1.0, CreateColor(maxColor[1], maxColor[2], maxColor[3], maxColor[4])) -- sattes Grün
		else
			curve:AddPoint(1.0, CreateColor(0.0, 0.85, 0.0, 1)) -- sattes Grün
		end
		curve:AddPoint(0.8, CreateColor(0.6, 0.85, 0.0, 1)) -- Gelbgrün
		curve:AddPoint(0.6, CreateColor(0.9, 0.9, 0.0, 1)) -- Knallgelb
		curve:AddPoint(0.4, CreateColor(0.95, 0.6, 0.0, 1)) -- Orange
		curve:AddPoint(0.2, CreateColor(0.95, 0.25, 0.0, 1)) -- Rot-Orange
		curve:AddPoint(0.0, CreateColor(0.9, 0.0, 0.0, 1)) -- Rot
	end
end
local function SetColorCurvePointsPower(pType, maxColor, defColor)
	if curve then
		curvePower[pType] = C_CurveUtil and C_CurveUtil.CreateColorCurve()
		curvePower[pType]:SetType(Enum.LuaCurveType.Cosine)
		if maxColor then curvePower[pType]:AddPoint(1.0, CreateColor(maxColor[1], maxColor[2], maxColor[3], maxColor[4])) end
		if defColor then curvePower[pType]:AddPoint(1.0, CreateColor(defColor[1], defColor[2], defColor[3], defColor[4])) end
	end
end
SetColorCurvePoints()

local function getHealthPercent(unit, curHealth, maxHealth)
	if addon.functions and addon.functions.GetHealthPercent then return addon.functions.GetHealthPercent(unit, curHealth, maxHealth, true) end
	curHealth = curHealth or UnitHealth(unit)
	maxHealth = maxHealth or UnitHealthMax(unit)
	return (curHealth or 0) / max(maxHealth or 1, 1) * 100
end

local function getPowerPercent(unit, powerEnum, curPower, maxPower)
	if addon.functions and addon.functions.GetPowerPercent then
		return addon.functions.GetPowerPercent(unit, powerEnum, curPower, maxPower, true)
		-- Unmodified flag defaults to true for personal resource bars
	end
	curPower = curPower or UnitPower(unit, powerEnum)
	maxPower = maxPower or UnitPowerMax(unit, powerEnum)
	if maxPower and maxPower > 0 then return (curPower or 0) / maxPower * 100 end
	return 0
end

local function formatSoulShardValue(value)
	if value == nil then return "0" end
	local text = string.format("%.1f", value)
	return text:gsub("%.0$", "")
end

local function formatNumber(value, useShort)
	if value == nil then return "0" end
	if useShort then return AbbreviateNumbers(value) end
	return tostring(value)
end

local function formatPercentText(value, cfg)
	if value == nil then return "0" end
	local mode = cfg and cfg.percentRounding
	if mode == "FLOOR" then
		if C_StringUtil and C_StringUtil.FloorToNearestString then return C_StringUtil.FloorToNearestString(value) end
		return tostring(floor(value))
	end
	if C_StringUtil and C_StringUtil.RoundToNearestString then return C_StringUtil.RoundToNearestString(value) end
	return tostring(floor(value + 0.5))
end

local function formatPercentDisplay(value, cfg)
	local percentText = formatPercentText(value, cfg)
	if cfg and cfg.hidePercentSign == true then return percentText end
	return (addon.variables and addon.variables.isMidnight) and (percentText .. "%") or percentText
end

local function isSpellKnownSafe(spellId)
	if not spellId then return false end
	if issecretvalue and issecretvalue(spellId) then return false end
	if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(spellId) end
	return false
end

ResourceBars.PowerLabels = {
	MAELSTROM_WEAPON = (C_Spell.GetSpellName(RB.MAELSTROM_WEAPON_SPELL_ID)) or "Maelstrom Weapon",
	VOID_METAMORPHOSIS = (C_Spell.GetSpellName(RB.VOID_METAMORPHOSIS_SPELL_ID)) or "Void Metamorphosis",
	STAGGER = (_G and _G["STAGGER"]) or "Stagger",
}

RB.AURA_POWER_CONFIG = {
	MAELSTROM_WEAPON = {
		spellIds = { RB.MAELSTROM_WEAPON_SPELL_ID },
		maxStacks = RB.MAELSTROM_WEAPON_MAX_STACKS,
		visualSegments = RB.MAELSTROM_WEAPON_SEGMENTS,
		midColor = RB.DEFAULT_MAELSTROM_WEAPON_FIVE_COLOR,
		useMidColorKey = "useMaelstromFiveColor",
		midColorKey = "maelstromFiveColor",
		useMaxColorDefault = true,
		defaultShowSeparator = true,
	},
	VOID_METAMORPHOSIS = {
		spellIds = { RB.VOID_METAMORPHOSIS_SPELL_ID, RB.COLLAPSING_STAR_SPELL_ID },
		maxStacks = 50,
		maxStacksBySpellId = {
			[RB.COLLAPSING_STAR_SPELL_ID] = 30,
		},
		maxStacksTalent = { spellId = RB.VOID_META_TALENT_SOUL_GLUTTON_SPELL_ID, value = 35 },
		visualSegments = 0,
		defaultColor = { 0.35, 0.25, 0.73, 1 }, -- #5940BA (Blizzard voidMetamorphosisProgess)
		useMaxColorDefault = true,
		defaultShowSeparator = false,
	},
}

local function registerAuraSpellLookup()
	for pType, cfg in pairs(RB.AURA_POWER_CONFIG or {}) do
		if cfg.spellIds then
			for _, sid in ipairs(cfg.spellIds) do
				if sid then auraSpellToType[sid] = pType end
			end
		end
	end
end

local function isAuraPowerType(pType) return RB.AURA_POWER_CONFIG and RB.AURA_POWER_CONFIG[pType] ~= nil end

local function isAuraPowerSpell(spellId)
	if not spellId then return nil end
	if issecretvalue and issecretvalue(spellId) then return nil end
	return auraSpellToType[spellId]
end

registerAuraSpellLookup()

local function ensureAuraPowerState(pType)
	if not auraPowerState[pType] then auraPowerState[pType] = { instances = {}, currentInstance = nil } end
	return auraPowerState[pType]
end

local function assignAuraInstance(pType, auraInstanceID, spellId)
	local state = ensureAuraPowerState(pType)
	if auraInstanceID then
		state.instances[auraInstanceID] = true
		state.currentInstance = auraInstanceID
		state.lastSpellId = spellId or state.lastSpellId
		auraInstanceToType[auraInstanceID] = pType
	end
end

local function clearAuraInstance(pType, auraInstanceID)
	local state = ensureAuraPowerState(pType)
	if auraInstanceID then
		state.instances[auraInstanceID] = nil
		if state.currentInstance == auraInstanceID then state.currentInstance = nil end
	end
	if auraInstanceID then auraInstanceToType[auraInstanceID] = nil end
end

local function resetAuraTracking()
	for k in pairs(auraPowerState) do
		auraPowerState[k] = nil
	end
	for k in pairs(auraInstanceToType) do
		auraInstanceToType[k] = nil
	end
end

local function handleAuraEventInfo(eventInfo)
	if not eventInfo then return nil end
	local changed = {}
	for _, aura in ipairs(eventInfo.addedAuras or {}) do
		local pType = aura and aura.spellId and isAuraPowerSpell(aura.spellId)
		if pType and aura.auraInstanceID then
			assignAuraInstance(pType, aura.auraInstanceID, aura.spellId)
			changed[pType] = true
		end
	end
	for _, inst in ipairs(eventInfo.updatedAuraInstanceIDs or {}) do
		local pType = auraInstanceToType[inst]
		if not pType and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
			local data = C_UnitAuras.GetAuraDataByAuraInstanceID("player", inst)
			if data and data.spellId then pType = isAuraPowerSpell(data.spellId) end
			if pType and data then assignAuraInstance(pType, inst, data.spellId) end
		end
		if pType then changed[pType] = true end
	end
	for _, inst in ipairs(eventInfo.removedAuraInstanceIDs or {}) do
		local pType = auraInstanceToType[inst]
		if pType then
			clearAuraInstance(pType, inst)
			changed[pType] = true
		end
	end
	return changed
end
local function getAuraPowerCounts(pType)
	local cfg = RB.AURA_POWER_CONFIG[pType]
	if not cfg then return 0, 0, 0 end
	local state = ensureAuraPowerState(pType)
	local auraData
	if state.currentInstance and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
		auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", state.currentInstance)
		if not auraData then clearAuraInstance(pType, state.currentInstance) end
	end
	if not auraData then
		if addon.variables.isMidnight and C_UnitAuras and C_UnitAuras.GetUnitAuras then
			for _, v in pairs(C_UnitAuras.GetUnitAuras("player", "HELPFUL")) do
				if not (issecretvalue and issecretvalue(v.spellId)) and isAuraPowerSpell(v.spellId) == pType then
					assignAuraInstance(pType, v.auraInstanceID, v.spellId)
					auraData = v
					break
				end
			end
		elseif C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
			for _, sid in ipairs(cfg.spellIds or {}) do
				local aura = C_UnitAuras.GetPlayerAuraBySpellID(sid)
				if aura and not (issecretvalue and issecretvalue(aura.spellId)) then
					assignAuraInstance(pType, aura.auraInstanceID, aura.spellId)
					auraData = aura
					break
				end
			end
		end
	end
	if not auraData then return 0, cfg.maxStacks or 0, cfg.visualSegments or (cfg.maxStacks or 0) end
	state.currentInstance = auraData.auraInstanceID or state.currentInstance
	if state.currentInstance then
		auraInstanceToType[state.currentInstance] = pType
		state.instances[state.currentInstance] = true
	end
	local stacks = auraData.applications or auraData.charges or 0
	local logicalMax = auraData.maxCharges or auraData.pointsMax or cfg.maxStacks or stacks
	if auraData.spellId and cfg.maxStacksBySpellId and cfg.maxStacksBySpellId[auraData.spellId] then
		logicalMax = cfg.maxStacksBySpellId[auraData.spellId]
	elseif cfg.maxStacksTalent and auraData.spellId == RB.VOID_METAMORPHOSIS_SPELL_ID then
		if isSpellKnownSafe(cfg.maxStacksTalent.spellId) then logicalMax = cfg.maxStacksTalent.value or logicalMax end
	end
	local visualSegments = cfg.visualSegments or logicalMax or stacks
	return stacks or 0, logicalMax or 0, visualSegments or logicalMax
end

function ResourceBars.UpdateAuraPowerState(eventInfo)
	if not RB.AURA_POWER_CONFIG then return end
	if not eventInfo or eventInfo.isFullUpdate then
		resetAuraTracking()
		return
	end
	handleAuraEventInfo(eventInfo)
end

ResourceBars.GetAuraPowerCounts = getAuraPowerCounts

local function getPlayerClassColor()
	local class = addon and addon.variables and addon.variables.unitClass
	if not class then return 0, 0.7, 0, 1 end
	local color = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
	if color then return color.r or color[1] or 0, color.g or color[2] or 0.7, color.b or color[3] or 0, color.a or 1 end
	return 0, 0.7, 0, 1
end

local function getHolyThreeColor(cfg)
	local col = cfg and cfg.holyThreeColor or { 1, 0.8, 0.2, 1 }
	return col[1] or 1, col[2] or 0.8, col[3] or 0.2, col[4] or 1
end

local function setBarDesaturated(bar, flag)
	if bar and bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(flag and true or false) end
end

RB.STAGGER_YELLOW_THRESHOLD = 0.30
RB.STAGGER_RED_THRESHOLD = 0.60
RB.STAGGER_EXTRA_THRESHOLD_HIGH = 200
RB.STAGGER_EXTRA_THRESHOLD_EXTREME = 300
RB.STAGGER_EXTRA_COLORS = {
	high = { r = 0.62, g = 0.2, b = 1.0, a = 1 },
	extreme = { r = 1.0, g = 0.2, b = 0.8, a = 1 },
}
RB.STAGGER_FALLBACK_COLORS = {
	green = { r = 0.52, g = 1.0, b = 0.52 },
	yellow = { r = 1.0, g = 0.98, b = 0.72 },
	red = { r = 1.0, g = 0.42, b = 0.42 },
}

local function getColorComponents(color, fallback)
	color = color or fallback
	if not color then return 1, 1, 1, 1 end
	if color.r then return color.r or 1, color.g or 1, color.b or 1, color.a or 1 end
	return color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
end

local function getStaggerStateColor(percent, cfg)
	local info = (GetPowerBarColor and GetPowerBarColor("STAGGER")) or (PowerBarColor and PowerBarColor["STAGGER"])
	if cfg and cfg.staggerHighColors == true then
		local high = tonumber(cfg.staggerHighThreshold) or RB.STAGGER_EXTRA_THRESHOLD_HIGH
		local extreme = tonumber(cfg.staggerExtremeThreshold) or RB.STAGGER_EXTRA_THRESHOLD_EXTREME
		if high < 0 then high = 0 end
		if extreme < high then extreme = high end
		local highRatio = high / 100
		local extremeRatio = extreme / 100
		if percent >= extremeRatio then
			return getColorComponents(cfg.staggerExtremeColor, RB.STAGGER_EXTRA_COLORS.extreme)
		elseif percent >= highRatio then
			return getColorComponents(cfg.staggerHighColor, RB.STAGGER_EXTRA_COLORS.high)
		end
	end
	local key
	if percent >= RB.STAGGER_RED_THRESHOLD then
		key = "red"
	elseif percent >= RB.STAGGER_YELLOW_THRESHOLD then
		key = "yellow"
	else
		key = "green"
	end
	return getColorComponents((info and info[key]) or RB.STAGGER_FALLBACK_COLORS[key] or RB.STAGGER_FALLBACK_COLORS.green)
end

local function getPowerBarColor(type)
	if type == "STAGGER" then
		local r, g, b = getStaggerStateColor(0)
		return r or 1, g or 1, b or 1
	end
	if ResourcebarVars.CUSTOM_POWER_COLORS and ResourcebarVars.CUSTOM_POWER_COLORS[type] then
		local c = ResourcebarVars.CUSTOM_POWER_COLORS[type]
		return c[1] or 1, c[2] or 1, c[3] or 1
	end
	local colorTable = PowerBarColor
	if colorTable then
		local entry = colorTable[string.upper(type)]
		if entry and entry.r then return entry.r, entry.g, entry.b end
	end
	return 1, 1, 1
end

function ResourceBars.RefreshTextureDropdown()
	local dd = ResourceBars.ui and ResourceBars.ui.textureDropdown
	if not dd then return end
	local list, order = getStatusbarDropdownLists(true)
	dd:SetList(list, order)
	local cfg = dd._rb_cfgRef
	local cur = (cfg and cfg.barTexture) or "DEFAULT"
	if not list[cur] then cur = "DEFAULT" end
	dd:SetValue(cur)
end

local STATUSBAR_INTERP = Enum and Enum.StatusBarInterpolation
local INTERP_EASE = STATUSBAR_INTERP and STATUSBAR_INTERP.ExponentialEaseOut

local function setBarValue(bar, value, smooth)
	if not bar or value == nil then return end
	if smooth and INTERP_EASE then
		bar:SetValue(value, INTERP_EASE)
	else
		bar:SetValue(value)
	end
end

requestActiveRefresh = function(specIndex, opts)
	if not addon or not addon.Aura or not addon.Aura.ResourceBars then return end
	local rb = addon.Aura.ResourceBars
	if rb.QueueRefresh then
		rb.QueueRefresh(specIndex, opts)
	elseif rb.MaybeRefreshActive then
		rb.MaybeRefreshActive(specIndex)
	end
end
addon.Aura.functions.requestActiveRefresh = requestActiveRefresh

local function deactivateRuneTicker(bar)
	if not bar then return end
	if bar:GetScript("OnUpdate") == bar._runeUpdater then bar:SetScript("OnUpdate", nil) end
	bar._runesAnimating = false
	bar._runeAccum = 0
	bar._runeUpdateInterval = nil
end

RB.TEXTURE_LIST_CACHE = {
	dirty = true,
}

local function markTextureListDirty() RB.TEXTURE_LIST_CACHE.dirty = true end

ResourceBars.MarkTextureListDirty = markTextureListDirty

local function cloneMap(src)
	if not src then return {} end
	local dest = {}
	for k, v in pairs(src) do
		dest[k] = v
	end
	return dest
end

local function cloneArray(src)
	if not src then return {} end
	local dest = {}
	for i = 1, #src do
		dest[i] = src[i]
	end
	return dest
end

local function copyCosmeticBarSettings(source, dest)
	if not source or not dest then return end
	for _, key in ipairs(COSMETIC_BAR_KEYS) do
		local value = source[key]
		if type(value) == "table" then
			dest[key] = CopyTable(value)
		else
			dest[key] = value
		end
	end
end

local function ensureMaelstromWeaponDefaults(cfg)
	if not cfg then return end
	if cfg.useMaelstromFiveColor == nil then cfg.useMaelstromFiveColor = true end
	if cfg.useMaelstromTenStacks == nil then cfg.useMaelstromTenStacks = cfg.visualSegments == RB.MAELSTROM_WEAPON_MAX_STACKS end
	if cfg.useMaxColor == nil then cfg.useMaxColor = true end
	if not cfg.maxColor then cfg.maxColor = { 0, 1, 0, 1 } end
	if not cfg.maelstromFiveColor then cfg.maelstromFiveColor = CopyTable(ResourcebarVars.DEFAULT_MAELSTROM_WEAPON_FIVE_COLOR) end
	if cfg.useMaelstromTenStacks then
		cfg.visualSegments = RB.MAELSTROM_WEAPON_MAX_STACKS
	elseif cfg.visualSegments == nil or cfg.visualSegments == RB.MAELSTROM_WEAPON_MAX_STACKS then
		cfg.visualSegments = RB.MAELSTROM_WEAPON_SEGMENTS
	end
	if cfg.showSeparator == nil then cfg.showSeparator = true end
	if not cfg.separatorThickness then cfg.separatorThickness = RB.SEPARATOR_THICKNESS end
	if not cfg.separatorColor then cfg.separatorColor = CopyTable(RB.SEP_DEFAULT) end
end

local function ensureAuraPowerDefaults(pType, cfg)
	if not cfg then return end
	local def = RB.AURA_POWER_CONFIG[pType]
	if cfg.showSeparator == nil then
		if def and def.defaultShowSeparator ~= nil then
			cfg.showSeparator = def.defaultShowSeparator and true or false
		else
			cfg.showSeparator = true
		end
	end
	if not cfg.separatorThickness then cfg.separatorThickness = RB.SEPARATOR_THICKNESS end
	if not cfg.separatorColor then cfg.separatorColor = CopyTable(RB.SEP_DEFAULT) end
	if def and not cfg.visualSegments then cfg.visualSegments = def.visualSegments end
	if def and def.useMaxColorDefault and cfg.useMaxColor == nil then cfg.useMaxColor = true end
	if cfg.useMaxColor and not cfg.maxColor then cfg.maxColor = { 0, 1, 0, 1 } end
	if pType == "MAELSTROM_WEAPON" then ensureMaelstromWeaponDefaults(cfg) end
end

local function ensureGlobalStore()
	addon.db.globalResourceBarSettings = addon.db.globalResourceBarSettings or {}
	return addon.db.globalResourceBarSettings
end

local function getSpecInfo(specIndex)
	local class = addon.variables.unitClass
	local spec = specIndex or addon.variables.unitSpec
	if not class or not spec then return nil end
	return powertypeClasses[class] and powertypeClasses[class][spec]
end

function ResourceBars.IsSpecBarTypeSupported(specInfo, barType)
	if barType == "HEALTH" then return true end
	if not specInfo then return true end
	return specInfo.MAIN == barType or specInfo[barType] == true
end

function ResourceBars.IsBarTypeSupportedForClass(barType, classTag, specIndex)
	if barType == "HEALTH" then return true end
	local class = classTag or addon.variables.unitClass
	if not class or not powertypeClasses or not powertypeClasses[class] then return false end
	local classTbl = powertypeClasses[class]
	local spec = specIndex or addon.variables.unitSpec
	if spec and classTbl[spec] then return ResourceBars.IsSpecBarTypeSupported(classTbl[spec], barType) end
	for _, specInfo in pairs(classTbl) do
		if type(specInfo) == "table" and ResourceBars.IsSpecBarTypeSupported(specInfo, barType) then return true end
	end
	return false
end

function ResourceBars.GetClassPowerTypes(classTag)
	local class = classTag or addon.variables.unitClass
	local list = {}
	if not class then return list end
	for _, pType in ipairs(classPowerTypes or {}) do
		if ResourceBars.IsBarTypeSupportedForClass(pType, class, nil) then list[#list + 1] = pType end
	end
	return list
end

local function specSecondaries(specInfo)
	local list = {}
	if not specInfo then return list end
	for _, pType in ipairs(classPowerTypes) do
		if pType ~= specInfo.MAIN and specInfo[pType] then list[#list + 1] = pType end
	end
	return list
end

function ResourceBars.GetEditModeFrameId(barType, classTag)
	local class = classTag or addon.variables.unitClass or "UNKNOWN"
	return "resourceBar_" .. tostring(class) .. "_" .. tostring(barType or "")
end

local function secondaryIndex(specInfo, pType)
	if not specInfo then return nil end
	for idx, val in ipairs(specSecondaries(specInfo)) do
		if val == pType then return idx end
	end
	return nil
end

local function maybeChainSecondaryAnchor(cfg, prevType)
	if not cfg or cfg.anchor then return end
	if not prevType then return end
	cfg.anchor = {
		point = "TOP",
		relativePoint = "BOTTOM",
		relativeFrame = "EQOL" .. prevType .. "Bar",
		x = 0,
		y = -2,
	}
end

local function mainTemplateMatches(store, barType)
	if not store or not store.MAIN then return nil end
	return store.MAIN
end

local function resolveGlobalTemplate(barType, specIndex)
	if not barType then return nil end
	local store = addon.db.globalResourceBarSettings
	if store and store[barType] then return store[barType] end

	local specInfo = getSpecInfo(specIndex)
	if not specInfo then return nil end

	-- MAIN fallback
	if specInfo.MAIN == barType then
		local main = mainTemplateMatches(store, barType)
		if main then return main end
	end

	-- Secondary fallback
	local idx = secondaryIndex(specInfo, barType)
	if idx and store and store.SECONDARY then return store.SECONDARY, idx end

	return nil
end

local function saveGlobalProfile(barType, specIndex, targetKey)
	if not barType then return false, "NO_BAR" end
	local specCfg = ensureSpecCfg(specIndex or addon.variables.unitSpec)
	if not specCfg then return false, "NO_SPEC" end
	local cfg = specCfg[barType]
	if not cfg then return false, "NO_CFG" end

	local function normalizeSize(source)
		local copy = CopyTable(source or {})
		if not copy.width or not copy.height then
			local frameName = (barType == "HEALTH") and "EQOLHealthBar" or ("EQOL" .. tostring(barType) .. "Bar")
			local frame = _G[frameName]
			if frame and frame.GetWidth and frame.GetHeight then
				copy.width = copy.width or frame:GetWidth()
				copy.height = copy.height or frame:GetHeight()
			end
		end
		if not copy.width then copy.width = (barType == "HEALTH") and RB.DEFAULT_HEALTH_WIDTH or RB.DEFAULT_POWER_WIDTH end
		if not copy.height then copy.height = (barType == "HEALTH") and RB.DEFAULT_HEALTH_HEIGHT or RB.DEFAULT_POWER_HEIGHT end
		return copy
	end

	local normalized = normalizeSize(cfg)
	normalized._rbType = barType
	local store = ensureGlobalStore()
	local specInfo = getSpecInfo(specIndex)
	local function assign(key)
		if not key then return end
		if key == "MAIN" then
			store.MAIN = CopyTable(normalized)
			store._MAIN_TYPE = barType
		elseif key == "SECONDARY" then
			store.SECONDARY = CopyTable(normalized)
		else
			store[key] = normalized
		end
	end

	if targetKey then
		assign(targetKey)
	else
		store[barType] = normalized
		-- Also keep generic MAIN/SECONDARY templates for cross-bar reuse
		if specInfo then
			if specInfo.MAIN == barType then assign("MAIN") end
			local secondaries = specSecondaries(specInfo)
			if secondaries[1] == barType then assign("SECONDARY") end
		end
	end
	return true
end

local function applyGlobalProfile(barType, specIndex, cosmeticOnly, sourceKey)
	if not barType then return false, "NO_BAR" end
	local store = addon.db and addon.db.globalResourceBarSettings
	local specInfo = getSpecInfo(specIndex)
	local globalCfg
	local secondaryIdx

	local function resolveExplicit(key)
		if not key then return nil end
		if key == "MAIN" then
			-- Explicit MAIN request: allow even if stored type tag differs
			return store and store.MAIN
		end
		if key == "SECONDARY" then
			secondaryIdx = secondaryIndex(specInfo, barType)
			return store and store.SECONDARY
		end
		return store and store[key]
	end

	if sourceKey then
		globalCfg = resolveExplicit(sourceKey)
	else
		globalCfg, secondaryIdx = resolveGlobalTemplate(barType, specIndex)
		if not globalCfg then
			local main = mainTemplateMatches(store, barType)
			if main then
				globalCfg = main
				secondaryIdx = specInfo and secondaryIndex(specInfo, barType)
			end
		end
	end
	if not globalCfg then return false, "NO_GLOBAL" end
	-- Ensure size fields exist even for older saved globals
	if not globalCfg.width or not globalCfg.height then
		local frameName = (barType == "HEALTH") and "EQOLHealthBar" or ("EQOL" .. tostring(barType) .. "Bar")
		local frame = _G[frameName]
		if frame and frame.GetWidth and frame.GetHeight then
			globalCfg = CopyTable(globalCfg)
			globalCfg.width = globalCfg.width or frame:GetWidth() or ((barType == "HEALTH") and RB.DEFAULT_HEALTH_WIDTH or RB.DEFAULT_POWER_WIDTH)
			globalCfg.height = globalCfg.height or frame:GetHeight() or ((barType == "HEALTH") and RB.DEFAULT_HEALTH_HEIGHT or RB.DEFAULT_POWER_HEIGHT)
		end
	end
	local specCfg = ensureSpecCfg(specIndex or addon.variables.unitSpec)
	if not specCfg then return false, "NO_SPEC" end
	specCfg[barType] = specCfg[barType] or {}
	if cosmeticOnly then
		copyCosmeticBarSettings(globalCfg, specCfg[barType])
	else
		specCfg[barType] = CopyTable(globalCfg)
		-- Chain secondary anchors if we are applying to second or later secondary
		if secondaryIdx and secondaryIdx > 1 then
			local prevType = specSecondaries(getSpecInfo(specIndex))[secondaryIdx - 1]
			if prevType then maybeChainSecondaryAnchor(specCfg[barType], prevType) end
		end
		-- Always enable separators when applying globals for eligible bars
		if ResourceBars.separatorEligible and ResourceBars.separatorEligible[barType] then
			specCfg[barType].showSeparator = true
			if not specCfg[barType].separatorThickness then specCfg[barType].separatorThickness = globalCfg.separatorThickness or RB.SEPARATOR_THICKNESS end
			specCfg[barType].separatorColor = specCfg[barType].separatorColor or globalCfg.separatorColor or RB.SEP_DEFAULT
		end
	end
	return true
end

local function trim(str)
	if type(str) ~= "string" then return str end
	return str:match("^%s*(.-)%s*$")
end

local function notifyUser(msg)
	if not msg or msg == "" then return end
	print("|cff00ff98Enhance QoL|r: " .. tostring(msg))
end

local function autoEnableSelection()
	addon.db.resourceBarsAutoEnable = addon.db.resourceBarsAutoEnable or {}
	-- Migrate legacy boolean flag to the new map-based selection
	if addon.db.resourceBarsAutoEnableAll ~= nil then
		if addon.db.resourceBarsAutoEnableAll == true and not next(addon.db.resourceBarsAutoEnable) then
			addon.db.resourceBarsAutoEnable.HEALTH = true
			addon.db.resourceBarsAutoEnable.MAIN = true
			addon.db.resourceBarsAutoEnable.SECONDARY = true
		end
		addon.db.resourceBarsAutoEnableAll = nil
	end
	return addon.db.resourceBarsAutoEnable
end

local function shouldAutoEnableBar(pType, specInfo, selection)
	if not selection then return false end
	if pType == "HEALTH" then return selection.HEALTH == true end
	if specInfo and specInfo.MAIN == pType then return selection.MAIN == true end
	if specInfo and pType ~= specInfo.MAIN and pType ~= "HEALTH" then return specInfo[pType] == true and selection.SECONDARY == true end
	return false
end

ensureSpecCfg = function(specIndex)
	local class = addon.variables.unitClass
	local spec = specIndex or addon.variables.unitSpec
	if not class or not spec then return nil end
	addon.db.personalResourceBarSettings = addon.db.personalResourceBarSettings or {}
	addon.db.personalResourceBarSettings[class] = addon.db.personalResourceBarSettings[class] or {}
	addon.db.personalResourceBarSettings[class][spec] = addon.db.personalResourceBarSettings[class][spec] or {}
	local specCfg = addon.db.personalResourceBarSettings[class][spec]

	-- Auto-populate from global when enabled and spec has no explicit enables yet
	local function maybeAutoEnableRuntime()
		local specInfo = powertypeClasses[class] and powertypeClasses[class][spec]
		if not specInfo then return end
		local selection = autoEnableSelection()
		if not selection or not (selection.HEALTH or selection.MAIN or selection.SECONDARY) then return end
		if specCfg._autoEnabledRuntime or specCfg._autoEnableInProgress then return end
		for _, cfg in pairs(specCfg) do
			if type(cfg) == "table" and cfg.enabled ~= nil then return end
		end
		specCfg._autoEnableInProgress = true

		local bars = {}
		local mainType = specInfo.MAIN
		if selection.HEALTH then bars[#bars + 1] = "HEALTH" end
		if selection.MAIN and mainType then bars[#bars + 1] = mainType end
		if selection.SECONDARY then
			for _, pType in ipairs(classPowerTypes or {}) do
				if specInfo[pType] and pType ~= mainType and pType ~= "HEALTH" then bars[#bars + 1] = pType end
			end
		end
		if #bars == 0 then
			specCfg._autoEnableInProgress = nil
			return
		end

		local function frameNameFor(typeId)
			if typeId == "HEALTH" then return "EQOLHealthBar" end
			return "EQOL" .. tostring(typeId) .. "Bar"
		end

		local prevFrame = selection.HEALTH and frameNameFor("HEALTH") or nil
		local mainFrame = frameNameFor(mainType or "HEALTH")
		local applied = 0
		for _, pType in ipairs(bars) do
			if shouldAutoEnableBar(pType, specInfo, selection) then
				specCfg[pType] = specCfg[pType] or {}
				local ok = false
				if ResourceBars.ApplyGlobalProfile then ok = ResourceBars.ApplyGlobalProfile(pType, specIndex or spec, false) end
				if ok then
					applied = applied + 1
					specCfg[pType].enabled = true
					if pType == mainType and pType ~= "HEALTH" then
						local a = specCfg[pType].anchor or {}
						a.point = a.point or "CENTER"
						a.relativePoint = a.relativePoint or "CENTER"
						local targetFrame = a.relativeFrame or frameNameFor("HEALTH")
						if not selection.HEALTH and targetFrame == frameNameFor("HEALTH") then targetFrame = nil end
						a.relativeFrame = targetFrame
						a.x = a.x or 0
						a.y = a.y or -2
						a.autoSpacing = a.autoSpacing or nil
						a.matchRelativeWidth = a.matchRelativeWidth or true
						specCfg[pType].anchor = a
						prevFrame = frameNameFor(pType)
					elseif pType ~= "HEALTH" then
						local a = specCfg[pType].anchor or {}
						a.point = a.point or "CENTER"
						a.relativePoint = a.relativePoint or "CENTER"
						local explicitRelative = type(a.relativeFrame) == "string" and a.relativeFrame ~= ""
						local chained = false
						if not explicitRelative then
							local targetFrame = frameNameFor("HEALTH")
							if class == "DRUID" then
								if pType == "COMBO_POINTS" then
									targetFrame = frameNameFor("ENERGY")
								else
									targetFrame = prevFrame
								end
								if not targetFrame or targetFrame == "" then targetFrame = prevFrame or (selection.MAIN and mainFrame or nil) end
							else
								targetFrame = prevFrame
							end
							a.relativeFrame = targetFrame
							chained = targetFrame and targetFrame ~= ""
						end
						a.x = a.x or 0
						if chained then a.y = a.y or -2 end
						a.autoSpacing = a.autoSpacing or nil
						if chained then a.matchRelativeWidth = a.matchRelativeWidth or true end
						specCfg[pType].anchor = a
						if class ~= "DRUID" then prevFrame = frameNameFor(pType) end
					else
						prevFrame = frameNameFor(pType)
					end
				end
			end
		end

		if applied > 0 then specCfg._autoEnabledRuntime = true end
		specCfg._autoEnableInProgress = nil
	end

	maybeAutoEnableRuntime()
	return specCfg
end

local function specNameByIndex(specIndex)
	local classID = addon.variables.unitClassID
	if not classID or not GetSpecializationInfoForClassID or not specIndex then return nil end
	local _, specName = GetSpecializationInfoForClassID(classID, specIndex)
	return specName
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

local function exportResourceProfile(scopeKey, profileName)
	scopeKey = scopeKey or "ALL"
	local classKey = addon.variables.unitClass
	if not classKey then return nil, "NO_CLASS" end
	local db, externalProfile = resolveProfileDB(profileName)
	if type(db) ~= "table" then return nil, "NO_DATA" end
	if not externalProfile then db.personalResourceBarSettings = db.personalResourceBarSettings or {} end
	local classConfig = db.personalResourceBarSettings and db.personalResourceBarSettings[classKey]

	local payload = {
		kind = RB.RESOURCE_SHARE_KIND,
		version = 1,
		class = classKey,
		enableResourceFrame = db["enableResourceFrame"] and true or false,
		specs = {},
		specNames = {},
	}

	if scopeKey == "ALL_CLASSES" then
		payload.version = 2
		payload.class = "ALL"
		payload.specs = nil
		payload.specNames = nil
		if type(db.personalResourceBarSettings) ~= "table" then return nil, "EMPTY" end
		payload.classes = CopyTable(db.personalResourceBarSettings)
		do
			local globals = {}
			if type(db.resourceBarsAutoEnable) == "table" then globals.resourceBarsAutoEnable = CopyTable(db.resourceBarsAutoEnable) end
			if db.resourceBarsHideOutOfCombat ~= nil then globals.resourceBarsHideOutOfCombat = db.resourceBarsHideOutOfCombat and true or false end
			if db.resourceBarsHideMounted ~= nil then globals.resourceBarsHideMounted = db.resourceBarsHideMounted and true or false end
			if db.resourceBarsHideVehicle ~= nil then globals.resourceBarsHideVehicle = db.resourceBarsHideVehicle and true or false end
			if db.resourceBarsHidePetBattle ~= nil then globals.resourceBarsHidePetBattle = db.resourceBarsHidePetBattle and true or false end
			if db.resourceBarsHideClientScene ~= nil then globals.resourceBarsHideClientScene = db.resourceBarsHideClientScene and true or false end
			if type(db.globalResourceBarSettings) == "table" then globals.globalResourceBarSettings = CopyTable(db.globalResourceBarSettings) end
			if next(globals) then payload.globalSettings = globals end
		end
		if type(payload.classes) ~= "table" or not next(payload.classes) then return nil, "EMPTY" end
	elseif scopeKey == "ALL" then
		if type(classConfig) ~= "table" then return nil, "NO_DATA" end
		local hasData = false
		for specIndex, specCfg in pairs(classConfig) do
			if type(specCfg) == "table" then
				payload.specs[specIndex] = CopyTable(specCfg)
				local idx = tonumber(specIndex)
				if idx then
					local specName = specNameByIndex(idx)
					if specName then payload.specNames[idx] = specName end
				end
				hasData = true
			end
		end
		if not hasData then return nil, "EMPTY" end
	else
		if type(classConfig) ~= "table" then return nil, "NO_DATA" end
		local specIndex = tonumber(scopeKey)
		if not specIndex then return nil, "NO_SPEC" end
		local specCfg = classConfig[specIndex]
		if type(specCfg) ~= "table" then return nil, "SPEC_EMPTY" end
		payload.specs[specIndex] = CopyTable(specCfg)
		local specName = specNameByIndex(specIndex)
		if specName then payload.specNames[specIndex] = specName end
	end

	local serializer = LibStub("AceSerializer-3.0")
	local deflate = LibStub("LibDeflate")
	local serialized = serializer:Serialize(payload)
	local compressed = deflate:CompressDeflate(serialized)
	return deflate:EncodeForPrint(compressed)
end

local function importResourceProfile(encoded, scopeKey)
	scopeKey = scopeKey or "ALL"
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

	if data.kind ~= RB.RESOURCE_SHARE_KIND then return false, "WRONG_KIND" end
	if data.class and data.class ~= addon.variables.unitClass and data.class ~= "ALL" then return false, "WRONG_CLASS", data.class end

	local appliedMode
	if data.class == "ALL" and type(data.classes) == "table" then
		scopeKey = "ALL_CLASSES"
		appliedMode = "ALL_CLASSES"
	end

	local enableState = data.enableResourceFrame
	local applied = {}
	addon.db.personalResourceBarSettings = addon.db.personalResourceBarSettings or {}
	local classKey = addon.variables.unitClass

	local function normalizeSpecs(specs)
		if type(specs) ~= "table" then return nil end
		if type(specs.specs) == "table" then return specs.specs end
		return specs
	end

	local function normalizeClassMap(classes)
		if type(classes) ~= "table" then return nil end
		local normalized = {}
		local any = false
		for classTag, classCfg in pairs(classes) do
			local specs = normalizeSpecs(classCfg)
			if type(specs) == "table" then
				normalized[classTag] = CopyTable(specs)
				any = true
			end
		end
		if not any then return nil end
		return normalized
	end

	local function applyGlobalSettings(global)
		if type(global) ~= "table" then return end
		if type(global.resourceBarsAutoEnable) == "table" then addon.db.resourceBarsAutoEnable = CopyTable(global.resourceBarsAutoEnable) end
		if global.resourceBarsHideOutOfCombat ~= nil then addon.db.resourceBarsHideOutOfCombat = global.resourceBarsHideOutOfCombat and true or false end
		if global.resourceBarsHideMounted ~= nil then addon.db.resourceBarsHideMounted = global.resourceBarsHideMounted and true or false end
		if global.resourceBarsHideVehicle ~= nil then addon.db.resourceBarsHideVehicle = global.resourceBarsHideVehicle and true or false end
		if global.resourceBarsHidePetBattle ~= nil then addon.db.resourceBarsHidePetBattle = global.resourceBarsHidePetBattle and true or false end
		if global.resourceBarsHideClientScene ~= nil then addon.db.resourceBarsHideClientScene = global.resourceBarsHideClientScene and true or false end
		if global.resourceBarsHidePetBattle == nil and global.auraHideInPetBattle ~= nil then addon.db.resourceBarsHidePetBattle = global.auraHideInPetBattle and true or false end
		if type(global.globalResourceBarSettings) == "table" then addon.db.globalResourceBarSettings = CopyTable(global.globalResourceBarSettings) end
	end

	local function applySpecsToClass(targetClass, specs, scope)
		specs = normalizeSpecs(specs)
		if type(specs) ~= "table" then return false, "NO_SPECS" end
		addon.db.personalResourceBarSettings[targetClass] = addon.db.personalResourceBarSettings[targetClass] or {}
		local classConfig = addon.db.personalResourceBarSettings[targetClass]
		if scope == "ALL" then
			local any = false
			for specIndex, specCfg in pairs(specs) do
				local idx = tonumber(specIndex)
				if idx and type(specCfg) == "table" then
					classConfig[idx] = CopyTable(specCfg)
					if targetClass == classKey then applied[#applied + 1] = idx end
					any = true
				end
			end
			if not any then return false, "NO_SPECS" end
			return true
		end

		local targetIndex = tonumber(scope)
		if not targetIndex then return false, "NO_SPEC" end
		local sourceCfg = specs[targetIndex] or specs[tostring(targetIndex)]
		if type(sourceCfg) ~= "table" then return false, "SPEC_MISMATCH" end
		classConfig[targetIndex] = CopyTable(sourceCfg)
		if targetClass == classKey then applied[#applied + 1] = targetIndex end
		return true
	end

	if scopeKey == "ALL_CLASSES" and type(data.classes) == "table" then
		local normalized = normalizeClassMap(data.classes)
		if not normalized then return false, "NO_SPECS" end
		addon.db.personalResourceBarSettings = normalized
		applyGlobalSettings(data.globalSettings or data.global)
		return true, {}, enableState, appliedMode or "ALL_CLASSES"
	end

	if type(data.classes) == "table" then
		if scopeKey == "ALL_CLASSES" then
			local any = false
			for classTag, classCfg in pairs(data.classes) do
				local okApply = applySpecsToClass(classTag, classCfg, "ALL")
				if okApply then any = true end
			end
			if not any then return false, "NO_SPECS" end
		else
			local classCfg = data.classes[classKey]
			local okApply, reason = applySpecsToClass(classKey, classCfg, scopeKey == "ALL" and "ALL" or scopeKey)
			if not okApply then return false, reason end
		end
	else
		local specs = data.specs
		if type(specs) ~= "table" then return false, "NO_SPECS" end
		local okApply, reason = applySpecsToClass(classKey, specs, scopeKey == "ALL" and "ALL" or scopeKey)
		if not okApply then return false, reason end
	end

	tsort(applied)
	return true, applied, enableState, appliedMode or scopeKey
end
addon.Aura.functions.importResourceProfile = importResourceProfile

local function exportErrorMessage(reason)
	if reason == "NO_DATA" or reason == "EMPTY" then return L["ExportProfileEmpty"] or "Nothing to export for this selection." end
	if reason == "SPEC_EMPTY" then return L["ExportProfileSpecEmpty"] or "The selected specialization has no saved settings yet." end
	return L["ExportProfileFailed"] or "Could not create an export code."
end

local function importErrorMessage(reason, extra)
	if reason == "NO_INPUT" then return L["ImportProfileEmpty"] or "Please enter a code to import." end
	if reason == "DECODE" or reason == "DECOMPRESS" or reason == "DESERIALIZE" or reason == "WRONG_KIND" then return L["ImportProfileInvalid"] or "The code could not be read." end
	if reason == "WRONG_CLASS" then
		local className = extra or UNKNOWN or "Unknown class"
		return (L["ImportProfileWrongClass"] or "This profile belongs to %s."):format(className)
	end
	if reason == "NO_SPECS" then return L["ImportProfileNoSpecs"] or "The code does not contain any Resource Bars settings." end
	if reason == "SPEC_MISMATCH" or reason == "NO_SPEC" then return L["ImportProfileMissingSpec"] or "The code does not contain settings for that specialization." end
	if reason == "SPEC_EMPTY" then return L["ImportProfileInvalid"] or "The code could not be read." end
	return L["ImportProfileFailed"] or "Could not import the Resource Bars profile."
end

local function rebuildTextureCache()
	local map = {
		["DEFAULT"] = DEFAULT,
		[RB.BLIZZARD_TEX] = "Blizzard: UI-StatusBar",
		["Interface\\Tooltips\\UI-Tooltip-Background"] = "Dark Flat (Tooltip bg)",
		["Interface\\TargetingFrame\\UI-StatusBar"] = "Blizzard Unit Frame",
		["Interface\\UnitPowerBarAlt\\Generic1Texture"] = "Alternate Power",
	}
	for name, path in pairs(LSM and LSM:HashTable("statusbar") or {}) do
		if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
	end
	local noDefault = {}
	for k, v in pairs(map) do
		if k ~= "DEFAULT" then noDefault[k] = v end
	end
	local sortedNoDefault, orderNoDefault = addon.functions.prepareListForDropdown(noDefault)
	local sortedWithDefault = {}
	for k, v in pairs(sortedNoDefault) do
		sortedWithDefault[k] = v
	end
	sortedWithDefault["DEFAULT"] = DEFAULT
	local orderWithDefault = { "DEFAULT" }
	for i = 1, #orderNoDefault do
		orderWithDefault[#orderWithDefault + 1] = orderNoDefault[i]
	end
	RB.TEXTURE_LIST_CACHE.noDefaultList = sortedNoDefault
	RB.TEXTURE_LIST_CACHE.noDefaultOrder = orderNoDefault
	RB.TEXTURE_LIST_CACHE.fullList = sortedWithDefault
	RB.TEXTURE_LIST_CACHE.fullOrder = orderWithDefault
	RB.TEXTURE_LIST_CACHE.dirty = false
end

getStatusbarDropdownLists = function(includeDefault)
	if RB.TEXTURE_LIST_CACHE.dirty or not RB.TEXTURE_LIST_CACHE.fullList then rebuildTextureCache() end
	if includeDefault then return cloneMap(RB.TEXTURE_LIST_CACHE.fullList), cloneArray(RB.TEXTURE_LIST_CACHE.fullOrder) end
	return cloneMap(RB.TEXTURE_LIST_CACHE.noDefaultList), cloneArray(RB.TEXTURE_LIST_CACHE.noDefaultOrder)
end
addon.Aura.functions.getStatusbarDropdownLists = getStatusbarDropdownLists

-- Detect Atlas: /run local t=PlayerFrame_GetManaBar():GetStatusBarTexture(); print("tex:", t:GetTexture(), "atlas:", t:GetAtlas()); local a,b,c,d,e,f,g,h=t:GetTexCoord(); print("tc:",a,b,c,d,e,f,g,h)
-- Healthbar: /run local t=PlayerFrame_GetHealthBar():GetStatusBarTexture(); print("tex:", t:GetTexture(), "atlas:", t:GetAtlas()); local a,b,c,d,e,f,g,h=t:GetTexCoord(); print("tc:",a,b,c,d,e,f,g,h)

RB.ATLAS_BY_POWER = {
	LUNAR_POWER = "Unit_Druid_AstralPower_Fill",
	MAELSTROM = "Unit_Shaman_Maelstrom_Fill",
	INSANITY = "Unit_Priest_Insanity_Fill",
	FURY = "Unit_DemonHunter_Fury_Fill",
	VOID_METAMORPHOSIS = "UF-DDH-VoidMeta-Bar",
	RUNIC_POWER = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-RunicPower",
	ENERGY = "UI-HUD-UnitFrame-Player-PortraitOn-ClassResource-Bar-Energy",
	FOCUS = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Focus",
	RAGE = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Rage",
	MANA = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana",
	HEALTH = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health",
}

local function isDefaultTextureSelection(cfg, pType)
	local sel = cfg and cfg.barTexture
	if sel == nil or sel == "" or sel == "DEFAULT" then return true end
	if pType == "VOID_METAMORPHOSIS" and sel == RB.DEFAULT_RB_TEX then return true end
	return false
end

local function shouldNormalizeAtlasColor(cfg, pType, bar)
	if cfg then
		if cfg.useBarColor == true then return false end
		if cfg.useClassColor == true then return false end
		if cfg.useGradient == true then return false end
		if cfg.useMaxColor == true and bar and bar._usingMaxColor then return false end
	end
	local auraDef = RB.AURA_POWER_CONFIG and RB.AURA_POWER_CONFIG[pType]
	if auraDef and auraDef.defaultColor then return false end
	return true
end

local function configureSpecialTexture(bar, pType, cfg)
	if not bar then return end
	local atlas = RB.ATLAS_BY_POWER[pType]
	if not atlas then
		bar._eqolSpecialAtlas = nil
		bar._eqolSpecialAtlasNormalized = nil
		return
	end
	cfg = cfg or bar._cfg
	if not isDefaultTextureSelection(cfg, pType) then
		bar._eqolSpecialAtlas = nil
		bar._eqolSpecialAtlasNormalized = nil
		return
	end
	local shouldNormalize = shouldNormalizeAtlasColor(cfg, pType, bar)
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture() or nil
	local currentAtlas = tex and tex.GetAtlas and tex:GetAtlas() or nil
	if bar._eqolSpecialAtlas == atlas and bar._eqolSpecialAtlasNormalized == shouldNormalize and currentAtlas == atlas then return end
	if bar.SetStatusBarTexture then bar:SetStatusBarTexture(atlas) end
	tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture() or nil
	if tex and tex.SetAtlas then
		currentAtlas = tex.GetAtlas and tex:GetAtlas()
		if currentAtlas ~= atlas then tex:SetAtlas(atlas, true) end
		if tex.SetHorizTile then tex:SetHorizTile(false) end
		if tex.SetVertTile then tex:SetVertTile(false) end
		if shouldNormalize then
			bar:SetStatusBarColor(1, 1, 1, 1)
			bar._baseColor = bar._baseColor or {}
			bar._baseColor[1], bar._baseColor[2], bar._baseColor[3], bar._baseColor[4] = 1, 1, 1, 1
			bar._lastColor = bar._lastColor or {}
			bar._lastColor[1], bar._lastColor[2], bar._lastColor[3], bar._lastColor[4] = 1, 1, 1, 1
			bar._usingMaxColor = false
		end
	end
	bar._eqolSpecialAtlas = atlas
	bar._eqolSpecialAtlasNormalized = shouldNormalize
end

local function isValidStatusbarPath(path)
	if not path or type(path) ~= "string" or path == "" then return false end
	if path == RB.BLIZZARD_TEX then return true end
	if path == "Interface\\Buttons\\WHITE8x8" then return true end
	if path == "Interface\\Tooltips\\UI-Tooltip-Background" then return true end
	if LSM and LSM.HashTable then
		local ht = LSM:HashTable("statusbar")
		for _, p in pairs(ht or {}) do
			if p == path then return true end
		end
	end
	return false
end

local function resolveTexture(cfg)
	local sel = cfg and cfg.barTexture
	if sel == nil or sel == "DEFAULT" or not isValidStatusbarPath(sel) then return RB.DEFAULT_RB_TEX end
	return sel
end

local function shouldEnableBarMouse(cfg) return not (cfg and cfg.clickThrough == true) end

local function isEQOLFrameName(name)
	if name == "EQOLHealthBar" then return true end
	return type(name) == "string" and name:match("^EQOL.+Bar$")
end
-- Fixed, non-DB defaults are stored in ResourcebarVars (RB)

local function defaultFontPath() return (addon.variables and addon.variables.defaultFont) or (LSM and LSM.DefaultMedia and LSM:Fetch("font", LSM.DefaultMedia.font)) or STANDARD_TEXT_FONT end

local function resolveFontFace(cfg)
	if cfg and cfg.fontFace and cfg.fontFace ~= "" then return cfg.fontFace end
	return defaultFontPath()
end

local function resolveFontOutline(cfg)
	local outline = cfg and cfg.fontOutline
	if outline == nil then return "OUTLINE" end
	if outline == "" or outline == "NONE" then return nil end
	return outline
end

local function resolveFontColor(cfg)
	local fc = cfg and cfg.fontColor
	return fc and (fc[1] or 1) or 1, fc and (fc[2] or 1) or 1, fc and (fc[3] or 1) or 1, fc and (fc[4] or 1) or 1
end

local function setFontWithFallback(fs, face, size, outline)
	if not fs or not face then return end
	if outline == "" then outline = nil end
	if not fs:SetFont(face, size, outline) then
		local fallbackOutline = outline or "OUTLINE"
		fs:SetFont(defaultFontPath(), size, fallbackOutline)
	end
end

local function applyFontToString(fs, cfg)
	if not fs then return end
	local size = (cfg and cfg.fontSize) or 16
	setFontWithFallback(fs, resolveFontFace(cfg), size, resolveFontOutline(cfg))
	local r, g, b, a = resolveFontColor(cfg)
	fs:SetTextColor(r, g, b, a)
end

local function ensureBackdropFrames(frame)
	if not frame then return nil end
	local bg = frame._rbBackground
	if not bg then
		bg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		local base = frame:GetFrameLevel() or 1
		bg:SetFrameLevel(max(base - 2, 0))
		bg:EnableMouse(false)
		frame._rbBackground = bg
	end
	local border = frame._rbBorder
	if not border then
		border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		local base = frame:GetFrameLevel() or 1
		border:SetFrameLevel(min(base + 2, 65535))
		border:EnableMouse(false)
		frame._rbBorder = border
	end
	return bg, border
end

RB.LEGACY_CUSTOM_BORDER_IDS = {
	EQOL_BORDER_RUNES = true,
	EQOL_BORDER_GOLDEN = true,
	EQOL_BORDER_MODERN = true,
	EQOL_BORDER_CLASSIC = true,
}

local function normalizeBorderTexture(bd)
	if not bd then return nil end
	local borderTexture = bd.borderTexture
	if borderTexture and RB.LEGACY_CUSTOM_BORDER_IDS[borderTexture] then
		borderTexture = "Interface\\Tooltips\\UI-Tooltip-Border"
		bd.borderTexture = borderTexture
	end
	return borderTexture
end

-- Statusbar content inset controller
RB.ZERO_INSETS = { left = 0, right = 0, top = 0, bottom = 0 }

local function copyInsetValues(src, dest)
	dest = dest or {}
	dest.left = src.left or 0
	dest.right = src.right or 0
	dest.top = src.top or 0
	dest.bottom = src.bottom or 0
	return dest
end

local function resolveInnerInset(bd) return RB.ZERO_INSETS end

local function ensureInnerFrame(frame)
	local inner = frame._rbInner
	if not inner then
		inner = CreateFrame("Frame", nil, frame)
		inner:EnableMouse(false)
		inner:SetClipsChildren(true)
		frame._rbInner = inner
	end
	return inner
end

local function ensureTextOverlayFrame(bar)
	if not bar then return nil end
	local overlay = bar._rbTextOverlay
	if not overlay then
		overlay = CreateFrame("Frame", nil, bar)
		overlay:SetAllPoints(bar)
		overlay:EnableMouse(false)
		bar._rbTextOverlay = overlay
	end
	local baseLevel = bar:GetFrameLevel() or 1
	local borderLevel = bar._rbBorder and bar._rbBorder:GetFrameLevel() or baseLevel
	overlay:SetFrameStrata(bar:GetFrameStrata())
	overlay:SetFrameLevel(max(borderLevel + 1, baseLevel + 1))
	return overlay
end

local EnumPowerType = Enum.PowerType

local POWER_ENUM = {
	MANA = (EnumPowerType and EnumPowerType.Mana) or 0,
	RAGE = (EnumPowerType and EnumPowerType.Rage) or 1,
	FOCUS = (EnumPowerType and EnumPowerType.Focus) or 2,
	ENERGY = (EnumPowerType and EnumPowerType.Energy) or 3,
	COMBO_POINTS = (EnumPowerType and EnumPowerType.ComboPoints) or 4,
	RUNES = (EnumPowerType and EnumPowerType.Runes) or 5,
	RUNIC_POWER = (EnumPowerType and EnumPowerType.RunicPower) or 6,
	SOUL_SHARDS = (EnumPowerType and EnumPowerType.SoulShards) or 7,
	LUNAR_POWER = (EnumPowerType and EnumPowerType.LunarPower) or (EnumPowerType and EnumPowerType.Alternate) or 8,
	HOLY_POWER = (EnumPowerType and EnumPowerType.HolyPower) or 9,
	MAELSTROM = (EnumPowerType and EnumPowerType.Maelstrom) or 11,
	CHI = (EnumPowerType and EnumPowerType.Chi) or 12,
	INSANITY = (EnumPowerType and EnumPowerType.Insanity) or 13,
	ARCANE_CHARGES = (EnumPowerType and EnumPowerType.ArcaneCharges) or 16,
	FURY = (EnumPowerType and EnumPowerType.Fury) or 17,
	PAIN = (EnumPowerType and EnumPowerType.Pain) or 18,
	ESSENCE = (EnumPowerType and EnumPowerType.Essence) or 19,
}

local function applyStatusBarInsets(frame, inset, force)
	if not frame then return end
	inset = inset or RB.ZERO_INSETS
	local l = inset.left or 0
	local r = inset.right or 0
	local t = inset.top or 0
	local b = inset.bottom or 0
	frame._rbInsetState = frame._rbInsetState or {}
	local state = frame._rbInsetState
	if not force and state.left == l and state.right == r and state.top == t and state.bottom == b then
		-- no-op
	else
		state.left, state.right, state.top, state.bottom = l, r, t, b
	end

	local inner = ensureInnerFrame(frame)
	inner:ClearAllPoints()
	inner:SetPoint("TOPLEFT", frame, "TOPLEFT", l, -t)
	inner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -r, b)
	local innerLevel = (frame:GetFrameLevel() or 1)
	inner:SetFrameStrata(frame:GetFrameStrata())
	inner:SetFrameLevel(innerLevel)

	local function alignTexture(bar, target)
		if not bar then return end
		local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
		if tex then
			tex:ClearAllPoints()
			tex:SetPoint("TOPLEFT", target, "TOPLEFT")
			tex:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT")
		end
	end

	alignTexture(frame, inner)
	if frame.absorbBar then
		local cfg = frame._cfg or (frame._rbType and getBarSettings and getBarSettings(frame._rbType)) or {}
		applyAbsorbLayout(frame, cfg)
	end

	frame._rbContentInset = frame._rbContentInset or {}
	frame._rbContentInset.left = l
	frame._rbContentInset.right = r
	frame._rbContentInset.top = t
	frame._rbContentInset.bottom = b

	if frame.separatorMarks then
		frame._sepW, frame._sepH, frame._sepSegments = nil, nil, nil
	end
	if frame._rbType then
		updateBarSeparators(frame._rbType)
		updateBarThresholds(frame._rbType)
	end
	if frame.runes then layoutRunes(frame) end
	if frame.essences then
		local cfg = frame._cfg or (frame._rbType and getBarSettings(frame._rbType)) or getBarSettings("ESSENCE") or {}
		local count = POWER_ENUM and UnitPowerMax("player", POWER_ENUM.ESSENCE) or 0
		ResourceBars.LayoutEssences(frame, cfg, count, resolveTexture(cfg))
	end
end

applyAbsorbLayout = function(bar, cfg)
	if not bar or not bar.absorbBar then return end
	cfg = cfg or {}
	local absorb = bar.absorbBar
	local inner = bar._rbInner or bar
	local overfill = cfg.absorbOverfill == true
	local healthTex = overfill and bar.GetStatusBarTexture and bar:GetStatusBarTexture() or nil
	if overfill and not healthTex then overfill = false end

	absorb:ClearAllPoints()
	if overfill then
		local vertical = cfg.verticalFill == true
		local reverseHealth = cfg.reverseFill == true
		local baseW = (inner and inner.GetWidth and inner:GetWidth()) or (bar.GetWidth and bar:GetWidth()) or 0
		local baseH = (inner and inner.GetHeight and inner:GetHeight()) or (bar.GetHeight and bar:GetHeight()) or 0
		if vertical then
			absorb:SetPoint("LEFT", inner, "LEFT")
			absorb:SetPoint("RIGHT", inner, "RIGHT")
			if reverseHealth then
				absorb:SetPoint("TOP", healthTex, "BOTTOM")
			else
				absorb:SetPoint("BOTTOM", healthTex, "TOP")
			end
			if absorb._overfillHeight ~= baseH then
				absorb:SetHeight(baseH)
				absorb._overfillHeight = baseH
			end
			absorb._overfillWidth = nil
		else
			absorb:SetPoint("TOP", inner, "TOP")
			absorb:SetPoint("BOTTOM", inner, "BOTTOM")
			if reverseHealth then
				absorb:SetPoint("RIGHT", healthTex, "LEFT")
			else
				absorb:SetPoint("LEFT", healthTex, "RIGHT")
			end
			if absorb._overfillWidth ~= baseW then
				absorb:SetWidth(baseW)
				absorb._overfillWidth = baseW
			end
			absorb._overfillHeight = nil
		end
	else
		absorb:SetPoint("TOPLEFT", inner, "TOPLEFT")
		absorb:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT")
		absorb._overfillWidth = nil
		absorb._overfillHeight = nil
	end

	local tex = absorb.GetStatusBarTexture and absorb:GetStatusBarTexture()
	if tex then
		tex:ClearAllPoints()
		tex:SetPoint("TOPLEFT", absorb, "TOPLEFT")
		tex:SetPoint("BOTTOMRIGHT", absorb, "BOTTOMRIGHT")
	end
	absorb._rbOverfill = overfill and true or false
end

local function applyBackdrop(frame, cfg)
	if not frame then return end
	cfg = cfg or {}
	cfg.backdrop = cfg.backdrop
		or {
			enabled = true,
			backgroundTexture = "Interface\\DialogFrame\\UI-DialogBox-Background",
			backgroundColor = { 0, 0, 0, 0.8 },
			borderTexture = "Interface\\Tooltips\\UI-Tooltip-Border",
			borderColor = { 0, 0, 0, 0 },
			edgeSize = 3,
			outset = 0,
		}
	local bd = cfg.backdrop
	local bgFrame, borderFrame = ensureBackdropFrames(frame)
	if not bgFrame or not borderFrame then return end
	frame._rbBackdropState = frame._rbBackdropState or {}
	local state = frame._rbBackdropState
	local contentInset = RB.ZERO_INSETS
	state.insets = copyInsetValues(contentInset, state.insets)
	applyStatusBarInsets(frame, state.insets, true)

	if bd.enabled == false then
		if bgFrame:IsShown() then bgFrame:Hide() end
		if borderFrame:IsShown() then borderFrame:Hide() end
		state.enabled = false
		return
	end
	state.enabled = true

	local outset = bd.outset or 0
	local bgInset = max(0, tonumber(bd.backgroundInset) or 0)

	bgFrame:ClearAllPoints()
	bgFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", -outset + bgInset, outset - bgInset)
	bgFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", outset - bgInset, -outset + bgInset)

	if state.outset ~= outset then
		borderFrame:ClearAllPoints()
		borderFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", -outset, outset)
		borderFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", outset, -outset)
		state.outset = outset
	end

	if bgFrame.SetBackdrop then
		local bgTexture = bd.backgroundTexture or "Interface\\DialogFrame\\UI-DialogBox-Background"
		if state.bgTexture ~= bgTexture then
			bgFrame:SetBackdrop({
				bgFile = bgTexture,
				edgeFile = nil,
				tile = false,
				edgeSize = 0,
				insets = { left = 0, right = 0, top = 0, bottom = 0 },
			})
			state.bgTexture = bgTexture
		end
		local bc = bd.backgroundColor or { 0, 0, 0, 0.8 }
		local br, bgc, bb, ba = bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 1
		if state.bgR ~= br or state.bgG ~= bgc or state.bgB ~= bb or state.bgA ~= ba then
			if bgFrame.SetBackdropColor then bgFrame:SetBackdropColor(br, bgc, bb, ba) end
			state.bgR, state.bgG, state.bgB, state.bgA = br, bgc, bb, ba
		end
		if bgFrame.SetBackdropBorderColor then bgFrame:SetBackdropBorderColor(0, 0, 0, 0) end
		if not bgFrame:IsShown() then bgFrame:Show() end
	end

	if borderFrame.SetBackdrop then
		local borderTexture = normalizeBorderTexture(bd)
		if borderTexture and borderTexture ~= "" and (bd.edgeSize or 0) > 0 then
			local edgeSize = bd.edgeSize or 3
			local borderChanged = false
			if state.borderTexture ~= borderTexture or state.borderEdgeSize ~= edgeSize or (borderFrame.GetBackdrop and not borderFrame:GetBackdrop()) then
				borderFrame:SetBackdrop({
					bgFile = nil,
					edgeFile = borderTexture,
					tile = false,
					edgeSize = edgeSize,
					insets = { left = 0, right = 0, top = 0, bottom = 0 },
				})
				state.borderTexture = borderTexture
				state.borderEdgeSize = edgeSize
				borderChanged = true
			end
			local boc = bd.borderColor or { 0, 0, 0, 0 }
			local cr, cg, cb, ca = boc[1] or 0, boc[2] or 0, boc[3] or 0, boc[4] or 1
			if borderChanged or state.borderR ~= cr or state.borderG ~= cg or state.borderB ~= cb or state.borderA ~= ca then
				if borderFrame.SetBackdropBorderColor then borderFrame:SetBackdropBorderColor(cr, cg, cb, ca) end
				state.borderR, state.borderG, state.borderB, state.borderA = cr, cg, cb, ca
			end
			if not borderFrame:IsShown() then borderFrame:Show() end
		else
			if state.borderTexture or state.borderEdgeSize then
				borderFrame:SetBackdrop(nil)
				state.borderTexture = nil
				state.borderEdgeSize = nil
			end
			state.borderR, state.borderG, state.borderB, state.borderA = nil, nil, nil, nil
			if borderFrame:IsShown() then borderFrame:Hide() end
		end
	end
end

local function ensureTextOffsetTable(cfg)
	cfg = cfg or {}
	cfg.textOffset = cfg.textOffset or { x = 0, y = 0 }
	return cfg.textOffset
end

local function applyTextPosition(bar, cfg, baseX, baseY)
	if not bar or not bar.text then return end
	local offset = ensureTextOffsetTable(cfg)
	local ox = (baseX or 0) + (offset.x or 0)
	local oy = (baseY or 0) + (offset.y or 0)
	local textParent = ensureTextOverlayFrame(bar) or bar
	if bar.text:GetParent() ~= textParent then bar.text:SetParent(textParent) end
	bar.text:SetDrawLayer("OVERLAY")
	bar.text:ClearAllPoints()
	bar.text:SetPoint("CENTER", bar, "CENTER", ox, oy)
end

local function applyBarFillColor(bar, cfg, pType)
	if not bar then return end
	cfg = cfg or {}
	local r, g, b, a
	local shouldDesaturate = false
	if pType == "STAGGER" and cfg.useBarColor ~= true then
		local stagger = (UnitStagger and UnitStagger("player")) or 0
		local maxHealth = UnitHealthMax("player") or 1
		local percent = maxHealth > 0 and (stagger / maxHealth) or 0
		r, g, b, a = getStaggerStateColor(percent, cfg)
		a = a or (cfg.barColor and cfg.barColor[4]) or 1
	elseif cfg.useBarColor then
		local color = cfg.barColor or RB.WHITE
		r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
	elseif cfg.useClassColor == true then
		r, g, b, a = getPlayerClassColor()
		a = a or (cfg.barColor and cfg.barColor[4]) or 1
		if pType == "HEALTH" then shouldDesaturate = true end
	else
		r, g, b = getPowerBarColor(pType or "MANA")
		a = (cfg.barColor and cfg.barColor[4]) or 1
	end
	bar:SetStatusBarColor(r, g, b, a or 1)
	setBarDesaturated(bar, shouldDesaturate)
	bar._baseColor = bar._baseColor or {}
	bar._baseColor[1], bar._baseColor[2], bar._baseColor[3], bar._baseColor[4] = r, g, b, a or 1
	bar._lastColor = bar._lastColor or {}
	bar._lastColor[1], bar._lastColor[2], bar._lastColor[3], bar._lastColor[4] = r, g, b, a or 1
	bar._usingMaxColor = false
	if pType and pType ~= "RUNES" then SetColorCurvePointsPower(pType, cfg.maxColor, bar._baseColor) end
	configureSpecialTexture(bar, pType, cfg)
	if ResourceBars.RefreshStatusBarGradient then ResourceBars.RefreshStatusBarGradient(bar, cfg) end
end

RB.DK_SPEC_COLOR = {
	[1] = { 0.8, 0.1, 0.1 },
	[2] = { 0.2, 0.6, 1.0 },
	[3] = { 0.0, 0.9, 0.3 },
}
local function dkSpecColor()
	-- addon.variables.unitSpec uses spec index (1 Blood, 2 Frost, 3 Unholy)
	return RB.DK_SPEC_COLOR[addon.variables.unitSpec] or RB.DK_SPEC_COLOR[1]
end

local function resolveRuneReadyColor(cfg)
	cfg = cfg or {}
	if cfg.useBarColor and cfg.barColor then
		local c = cfg.barColor
		return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
	end
	local dk = dkSpecColor()
	if dk then return dk[1] or 1, dk[2] or 1, dk[3] or 1, 1 end
	local cc = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor("DEATHKNIGHT")
	if cc and cc.GetRGB then
		local cr, cg, cb = cc:GetRGB()
		return cr or 1, cg or 1, cb or 1, 1
	end
	local pr, pg, pb = getPowerBarColor("RUNES")
	return pr or 1, pg or 1, pb or 1, 1
end

local function configureBarBehavior(bar, cfg, pType)
	if not bar then return end
	cfg = cfg or {}
	if bar.SetReverseFill then bar:SetReverseFill(cfg.reverseFill == true) end

	if pType ~= "RUNES" and bar.SetOrientation then bar:SetOrientation((cfg.verticalFill == true) and "VERTICAL" or "HORIZONTAL") end
	if pType == "HEALTH" and bar.absorbBar then
		local absorb = bar.absorbBar
		local wantVertical = cfg.verticalFill == true
		if absorb.SetOrientation and absorb._isVertical ~= wantVertical then
			absorb:SetOrientation(wantVertical and "VERTICAL" or "HORIZONTAL")
			absorb._isVertical = wantVertical
		end
		local tex = absorb:GetStatusBarTexture()
		if tex then
			local desiredRotation = wantVertical and (math.pi / 2) or 0
			if absorb._texRotation ~= desiredRotation then
				tex:SetRotation(desiredRotation)
				absorb._texRotation = desiredRotation
			end
		end
		local reverseAbsorb = cfg.absorbReverseFill == true
		if cfg.absorbOverfill then reverseAbsorb = false end
		if absorb.SetReverseFill then absorb:SetReverseFill(reverseAbsorb) end
		applyAbsorbLayout(bar, cfg)
	end

	if bar._rbBackdropState and bar._rbBackdropState.insets then applyStatusBarInsets(bar, bar._rbBackdropState.insets, true) end
end

local function behaviorOptionsForType(pType)
	local opts = {
		{ value = "reverseFill", text = L["Reverse fill"] or "Reverse fill" },
	}
	if pType ~= "RUNES" then
		opts[#opts + 1] = { value = "verticalFill", text = L["Vertical orientation"] or "Vertical orientation" }
		opts[#opts + 1] = { value = "smoothFill", text = L["Smooth fill"] or "Smooth fill" }
	end
	return opts
end

local function behaviorSelectionFromConfig(cfg, pType)
	local selection = {}
	cfg = cfg or {}
	if cfg.reverseFill == true then selection.reverseFill = true end
	if pType ~= "RUNES" then
		if cfg.verticalFill == true then selection.verticalFill = true end
		if cfg.smoothFill == true then selection.smoothFill = true end
	end
	return selection
end

local function applyBehaviorSelection(cfg, selection, pType, specIndex)
	if not cfg then return false end
	selection = selection or {}
	local beforeVertical = cfg.verticalFill == true

	cfg.reverseFill = selection.reverseFill == true
	if pType ~= "RUNES" then
		cfg.verticalFill = selection.verticalFill == true
		cfg.smoothFill = selection.smoothFill == true
	else
		cfg.verticalFill = nil
		cfg.smoothFill = nil
	end

	local afterVertical = cfg.verticalFill == true
	local dimensionsChanged = beforeVertical ~= afterVertical

	if dimensionsChanged then
		local defaultW = (pType == "HEALTH") and RB.DEFAULT_HEALTH_WIDTH or RB.DEFAULT_POWER_WIDTH
		local defaultH = (pType == "HEALTH") and RB.DEFAULT_HEALTH_HEIGHT or RB.DEFAULT_POWER_HEIGHT
		local curW = cfg.width or defaultW
		local curH = cfg.height or defaultH
		cfg.width, cfg.height = curH, curW
		local activeSpec = specIndex or addon.variables.unitSpec
		if activeSpec and activeSpec == addon.variables.unitSpec then
			if pType == "HEALTH" then
				ResourceBars.SetHealthBarSize(cfg.width or defaultW, cfg.height or defaultH)
			else
				ResourceBars.SetPowerBarSize(cfg.width or defaultW, cfg.height or defaultH, pType)
			end
		end
	end

	return dimensionsChanged
end

local editModeCallbacksRegistered
registerEditModeCallbacks = function()
	if editModeCallbacksRegistered then return end
	local editMode = addon and addon.EditMode
	local lib = editMode and editMode.lib
	if not lib or not lib.RegisterCallback then return end
	lib:RegisterCallback("enter", function()
		if addon.Aura.functions.setPowerBars then addon.Aura.functions.setPowerBars() end
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorAll then addon.Aura.ResourceBars.ReanchorAll() end
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
	end)
	lib:RegisterCallback("exit", function()
		-- Re-evaluate active bars (e.g., druid forms) when leaving Edit Mode
		if addon.Aura.functions.setPowerBars then addon.Aura.functions.setPowerBars() end
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorAll then addon.Aura.ResourceBars.ReanchorAll() end
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
	end)
	editModeCallbacksRegistered = true
end

ensureEditModeRegistration = function()
	if registerEditModeCallbacks then registerEditModeCallbacks() end
	if ResourceBars and ResourceBars.RegisterEditModeFrames then ResourceBars.RegisterEditModeFrames() end
end

local function SnapFractionToSpan(bar, span, frac)
	local s = (bar and bar.GetEffectiveScale and bar:GetEffectiveScale()) or 1
	if s <= 0 then s = 1 end
	local physicalSpan = max(1, floor((span or 0) * s + 0.5))
	local physicalOffset = floor((physicalSpan * (frac or 0)) + 0.5)
	return physicalOffset / s
end

-- Pull saved Edit Mode layout coords into empty anchors.
local function backfillAnchorFromLayout(anchor, barType)
	if not anchor or (anchor.x ~= nil and anchor.y ~= nil) then return end
	if anchor.relativeFrame and anchor.relativeFrame ~= "" and anchor.relativeFrame ~= "UIParent" then return end
	local editMode = addon and addon.EditMode
	if not editMode or not editMode.GetLayoutData then return end
	local layoutName = (editMode.GetActiveLayoutName and editMode:GetActiveLayoutName()) or editMode.activeLayout
	local frameId = ResourceBars.GetEditModeFrameId(barType)
	local data = editMode:GetLayoutData(frameId, layoutName)
	if not data or data.x == nil or data.y == nil then return end
	local point = data.point or data.relativePoint
	if not point then return end
	anchor.point = anchor.point or point
	anchor.relativePoint = anchor.relativePoint or data.relativePoint or point
	anchor.relativeFrame = anchor.relativeFrame or "UIParent"
	anchor.x = data.x
	anchor.y = data.y
end

RB.FREQUENT_POWER_TYPES = { ENERGY = true, FOCUS = true, RAGE = true, RUNIC_POWER = true, LUNAR_POWER = true }
local formIndexToKey = {
	[0] = "HUMANOID",
	[1] = "BEAR",
	[2] = "CAT",
	[3] = "TRAVEL",
	[4] = "MOONKIN",
	[6] = "STAG",
}
local formIDToKey = {}
local function mapFormID(key, ...)
	for i = 1, select("#", ...) do
		local formID = select(i, ...)
		if type(formID) == "number" then formIDToKey[formID] = key end
	end
end
mapFormID("BEAR", DRUID_BEAR_FORM)
mapFormID("CAT", DRUID_CAT_FORM)
mapFormID("TRAVEL", DRUID_TRAVEL_FORM, DRUID_ACQUATIC_FORM, DRUID_FLIGHT_FORM, DRUID_SWIFT_FLIGHT_FORM)
mapFormID("MOONKIN", DRUID_MOONKIN_FORM_1, DRUID_MOONKIN_FORM_2)
mapFormID("HUMANOID", DRUID_TREE_FORM)
local formKeyToIndex = {}
for idx, key in pairs(formIndexToKey) do
	formKeyToIndex[key] = idx
end
local DRUID_FORM_SEQUENCE = { "HUMANOID", "BEAR", "CAT", "TRAVEL", "MOONKIN", "STAG" }
local function shouldUseDruidFormDriver(cfg)
	if addon.variables.unitClass ~= "DRUID" then return false end
	if type(cfg) ~= "table" then return false end
	local showForms = cfg.showForms
	if type(showForms) ~= "table" then return false end
	for _, key in ipairs(DRUID_FORM_SEQUENCE) do
		if showForms[key] == false then return true end
	end
	return false
end
ResourceBars.ShouldUseDruidFormDriver = shouldUseDruidFormDriver
local function mapFormNameToKey(name)
	if not name then return nil end
	name = tostring(name):lower()
	if name:find("bear") then return "BEAR" end
	if name:find("cat") then return "CAT" end
	if name:find("travel") or name:find("aquatic") or name:find("flight") or name:find("flight form") then return "TRAVEL" end
	if name:find("moonkin") or name:find("owl") then return "MOONKIN" end
	if name:find("treant") then return "HUMANOID" end
	if name:find("tree of life") or name:find("tree form") or name:find("treeform") then return "HUMANOID" end
	if name:find("mount") then return "STAG" end
	if name:find("stag") then return "STAG" end
	return nil
end

local function resolveFormKeyFromShapeshiftIndex(idx)
	if not idx or idx <= 0 or not GetShapeshiftFormInfo then return nil end
	local texture, _, _, spellID = GetShapeshiftFormInfo(idx)
	if spellID and C_Spell and C_Spell.GetSpellName then
		local key = mapFormNameToKey(C_Spell.GetSpellName(spellID))
		if key then return key end
	end
	if type(texture) == "string" then
		local key = mapFormNameToKey(texture)
		if key then return key end
	end
	return nil
end

local function addUniqueStanceIndex(dst, idx)
	if not dst or not idx or idx <= 0 then return end
	for i = 1, #dst do
		if dst[i] == idx then return end
	end
	dst[#dst + 1] = idx
end

local function getDruidFormStanceMap()
	local map = {}
	if addon.variables.unitClass ~= "DRUID" then return map end

	local numForms = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
	for idx = 1, numForms do
		local key = resolveFormKeyFromShapeshiftIndex(idx)
		if key then
			map[key] = map[key] or {}
			addUniqueStanceIndex(map[key], idx)
		end
	end

	local activeIdx = GetShapeshiftForm and (GetShapeshiftForm() or 0) or 0
	if activeIdx > 0 then
		local activeKey
		if GetShapeshiftFormID then activeKey = formIDToKey[GetShapeshiftFormID()] end
		if not activeKey then activeKey = resolveFormKeyFromShapeshiftIndex(activeIdx) end
		if not activeKey then activeKey = formIndexToKey[activeIdx] end
		if activeKey then
			map[activeKey] = map[activeKey] or {}
			addUniqueStanceIndex(map[activeKey], activeIdx)
		end
	end

	for _, indices in pairs(map) do
		tsort(indices)
	end

	return map
end

local function ensureDruidShowFormsDefaults(cfg, pType, specInfo)
	if addon.variables.unitClass ~= "DRUID" then return end
	if not cfg or type(cfg) ~= "table" then return end
	if pType == "HEALTH" then return end

	-- Combo points are only meaningful in Cat; force that mapping regardless of previous user input.
	if pType == "COMBO_POINTS" then
		cfg.showForms = {
			HUMANOID = false,
			BEAR = false,
			CAT = true,
			TRAVEL = false,
			MOONKIN = false,
			STAG = false,
		}
		return
	end

	-- Other bars: only set defaults if the user has not customized the forms table.
	if type(cfg.showForms) == "table" and next(cfg.showForms) ~= nil then return end
	local sf = {}
	local isSecondaryMana = pType == "MANA" and specInfo and specInfo.MAIN ~= "MANA"
	local isSecondaryEnergy = pType == "ENERGY" and specInfo and specInfo.MAIN ~= "ENERGY"
	if isSecondaryMana then
		sf.HUMANOID = true
		sf.BEAR = false
		sf.CAT = false
		sf.TRAVEL = false
		sf.MOONKIN = false
		sf.STAG = false
	elseif isSecondaryEnergy then
		sf.HUMANOID = false
		sf.BEAR = false
		sf.CAT = true
		sf.TRAVEL = false
		sf.MOONKIN = false
		sf.STAG = false
	else
		sf.HUMANOID = true
		sf.BEAR = true
		sf.CAT = true
		sf.TRAVEL = true
		sf.MOONKIN = true
		sf.STAG = true
	end
	cfg.showForms = sf
end

local function isEQOLBarFrameName(name) return type(name) == "string" and name:match("^EQOL.+Bar$") end

local function ensureRelativeFrameFallback(anchor, pType, specInfo)
	if pType == "HEALTH" then return end
	if not anchor then return end
	local rf = anchor.relativeFrame
	if not rf or rf == "" then return end
	if not isEQOLBarFrameName(rf) then return end
	local relType = (rf == "EQOLHealthBar") and "HEALTH" or rf:match("^EQOL(.+)Bar$")
	if relType and relType ~= "" then
		-- If the target bar type is valid for this spec, keep it even if the frame isn't created yet
		if relType == "HEALTH" then return end
		if specInfo and (specInfo.MAIN == relType or specInfo[relType]) then return end
	end
	if _G[rf] then return end -- relative bar already exists (e.g., created earlier)

	-- Fallback to spec MAIN bar if available; otherwise health
	local fallback
	if specInfo and specInfo.MAIN and pType ~= "HEALTH" then
		fallback = "EQOL" .. specInfo.MAIN .. "Bar"
		if fallback == ("EQOL" .. tostring(pType) .. "Bar") then fallback = nil end
	end
	if not fallback or fallback == rf then fallback = "EQOLHealthBar" end

	anchor.relativeFrame = fallback
	if not anchor.point then anchor.point = "TOP" end
	if not anchor.relativePoint then anchor.relativePoint = "BOTTOM" end
	if anchor.x == nil then anchor.x = 0 end
	if anchor.y == nil then anchor.y = -2 end
	anchor.autoSpacing = nil
	if anchor.matchRelativeWidth == nil then anchor.matchRelativeWidth = true end
end

function updateHealthBar(evt)
	if healthBar and healthBar:IsShown() then
		local previousMax = healthBar._lastMax or 0
		local newMax = UnitHealthMax("player") or previousMax or 1

		if previousMax ~= newMax then
			healthBar._lastMax = newMax
			healthBar:SetMinMaxValues(0, newMax)
			local currentValue = healthBar:GetValue()
			local canClamp = not (issecretvalue and (issecretvalue(currentValue) or issecretvalue(newMax)))
			if canClamp then
				currentValue = currentValue or 0
				if currentValue > newMax then healthBar:SetValue(newMax) end
			end
		end
		local maxHealth = healthBar._lastMax or newMax or 1
		local curHealth = UnitHealth("player")
		local settings = getBarSettings("HEALTH") or {}
		local smooth = settings.smoothFill == true
		setBarValue(healthBar, curHealth, smooth)
		healthBar._lastVal = curHealth

		local percent = getHealthPercent("player", curHealth, maxHealth)
		local percentStr = formatPercentDisplay(percent, settings)
		if healthBar.text then
			local style = settings and settings.textStyle or "PERCENT"
			local useShortNumbers = settings.shortNumbers ~= false
			if style == "NONE" then
				if healthBar._textShown then
					healthBar.text:SetText("")
					healthBar._lastText = ""
					healthBar.text:Hide()
					healthBar._textShown = false
				elseif healthBar._lastText ~= "" then
					healthBar.text:SetText("")
					healthBar._lastText = ""
				end
			else
				local text
				if style == "PERCENT" then
					text = percentStr
				elseif style == "CURRENT" then
					text = formatNumber(curHealth, useShortNumbers)
				else -- CURMAX
					text = formatNumber(curHealth, useShortNumbers) .. " / " .. formatNumber(maxHealth, useShortNumbers)
				end
				if not addon.variables.isMidnight and healthBar._lastText ~= text then
					healthBar.text:SetText(text)
					healthBar._lastText = text
				else
					healthBar.text:SetText(text)
				end
				if not healthBar._textShown then
					healthBar.text:Show()
					healthBar._textShown = true
				end
			end
		end
		local baseR, baseG, baseB, baseA
		if settings.useBarColor then
			local custom = settings.barColor or RB.WHITE
			baseR, baseG, baseB, baseA = custom[1] or 1, custom[2] or 1, custom[3] or 1, custom[4] or 1
		elseif settings.useClassColor then
			baseR, baseG, baseB, baseA = getPlayerClassColor()
		else
			if not addon.variables.isMidnight then
				if percent >= 60 then
					baseR, baseG, baseB, baseA = 0, 0.7, 0, 1
				elseif percent >= 40 then
					baseR, baseG, baseB, baseA = 0.7, 0.7, 0, 1
				else
					baseR, baseG, baseB, baseA = 0.7, 0, 0, 1
				end
			end
		end
		healthBar._baseColor = healthBar._baseColor or {}
		healthBar._baseColor[1], healthBar._baseColor[2], healthBar._baseColor[3], healthBar._baseColor[4] = baseR, baseG, baseB, baseA

		if not addon.variables.isMidnight then
			local reachedCap = maxHealth > 0 and curHealth >= maxHealth
			local useMaxColor = settings.useMaxColor == true
			local finalR, finalG, finalB, finalA = baseR, baseG, baseB, baseA
			if useMaxColor and reachedCap then
				local maxCol = settings.maxColor or RB.WHITE
				finalR, finalG, finalB, finalA = maxCol[1] or baseR, maxCol[2] or baseG, maxCol[3] or baseB, maxCol[4] or baseA
			end

			local lc = healthBar._lastColor or {}
			local fa = finalA or 1
			if lc[1] ~= finalR or lc[2] ~= finalG or lc[3] ~= finalB or lc[4] ~= fa then
				lc[1], lc[2], lc[3], lc[4] = finalR, finalG, finalB, fa
				healthBar._lastColor = lc
				if ResourceBars.SetStatusBarColorWithGradient then
					ResourceBars.SetStatusBarColorWithGradient(healthBar, settings, lc[1], lc[2], lc[3], lc[4])
				else
					healthBar:SetStatusBarColor(lc[1], lc[2], lc[3], lc[4])
				end
			end
		else
			local lc = healthBar._lastColor or {}
			if lc[1] ~= baseR or lc[2] ~= baseG or lc[3] ~= baseB or lc[4] ~= baseA then
				if (settings.useBarColor or settings.useClassColor) and not settings.useMaxColor then
					healthBar._lastColor = lc
					healthBar:GetStatusBarTexture():SetVertexColor(1, 1, 1, 1)
					if ResourceBars.SetStatusBarColorWithGradient then
						ResourceBars.SetStatusBarColorWithGradient(healthBar, settings, baseR, baseG, baseB, baseA)
					else
						healthBar:SetStatusBarColor(baseR, baseG, baseB, baseA)
					end
				else
					if wasMax ~= settings.useMaxColor then
						wasMax = settings.useMaxColor
						if settings.useMaxColor then
							SetColorCurvePoints(settings.maxColor or RB.WHITE)
						else
							SetColorCurvePoints()
						end
					end
					local color = UnitHealthPercent("player", true, curve)
					healthBar:GetStatusBarTexture():SetVertexColor(color:GetRGB())
				end
			end
		end
		if ResourceBars.RefreshStatusBarGradient then ResourceBars.RefreshStatusBarGradient(healthBar, settings) end
		setBarDesaturated(healthBar, true)

		local absorbBar = healthBar.absorbBar
		if absorbBar then
			local absorbEnabled = settings.absorbEnabled ~= false
			if not absorbEnabled or maxHealth <= 0 then
				absorbBar:Hide()
				setBarValue(absorbBar, 0, smooth)
				absorbBar._lastVal = 0
			else
				if not absorbBar:IsShown() then absorbBar:Show() end
				-- Texture
				local absorbTex = resolveTexture({ barTexture = settings.absorbTexture or settings.barTexture })
				local curTex = absorbBar:GetStatusBarTexture() and absorbBar:GetStatusBarTexture():GetTexture()
				if curTex ~= absorbTex then absorbBar:SetStatusBarTexture(absorbTex) end
				-- Color
				local defAbsorb = { 0.8, 0.8, 0.8, 0.8 }
				local col = (settings.absorbUseCustomColor and settings.absorbColor) or defAbsorb
				local ar, ag, ab, aa = col[1] or defAbsorb[1], col[2] or defAbsorb[2], col[3] or defAbsorb[3], col[4] or defAbsorb[4]
				if not absorbBar._lastColor or absorbBar._lastColor[1] ~= ar or absorbBar._lastColor[2] ~= ag or absorbBar._lastColor[3] ~= ab or absorbBar._lastColor[4] ~= aa then
					absorbBar:SetStatusBarColor(ar, ag, ab, aa)
					absorbBar._lastColor = { ar, ag, ab, aa }
				end

				local abs = UnitGetTotalAbsorbs("player") or 0
				if settings.absorbSample then abs = maxHealth * 0.6 end
				if settings.absorbOverfill then applyAbsorbLayout(healthBar, settings) end
				if addon.variables.isMidnight then
					absorbBar:SetMinMaxValues(0, maxHealth)
					setBarValue(absorbBar, abs, smooth)
				else
					if abs > maxHealth then abs = maxHealth end
					if absorbBar._lastMax ~= maxHealth then
						absorbBar:SetMinMaxValues(0, maxHealth)
						absorbBar._lastMax = maxHealth
					end
					setBarValue(absorbBar, abs, smooth)
					absorbBar._lastVal = abs
				end
			end
		end
	end
end

function getAnchor(name, spec)
	local class = addon.variables.unitClass
	spec = spec or addon.variables.unitSpec
	addon.db.personalResourceBarSettings = addon.db.personalResourceBarSettings or {}
	addon.db.personalResourceBarSettings[class] = addon.db.personalResourceBarSettings[class] or {}
	addon.db.personalResourceBarSettings[class][spec] = addon.db.personalResourceBarSettings[class][spec] or {}
	addon.db.personalResourceBarSettings[class][spec][name] = addon.db.personalResourceBarSettings[class][spec][name] or {}
	local cfg = addon.db.personalResourceBarSettings[class][spec][name]
	cfg.anchor = cfg.anchor or {}
	local anchor = cfg.anchor
	if anchor.matchRelativeWidth == nil and anchor.matchEssentialWidth ~= nil then
		anchor.matchRelativeWidth = anchor.matchEssentialWidth and true or nil
		anchor.matchEssentialWidth = nil
	end
	if (anchor.relativeFrame or "UIParent") == "UIParent" then anchor.matchRelativeWidth = nil end
	backfillAnchorFromLayout(anchor, name)
	return anchor
end

local function resolveAnchor(info, type)
	local frame = ResourceBars.ResolveRelativeFrameByName(info and info.relativeFrame)
	if not frame or frame == UIParent then return frame or UIParent, false end

	local visited = {}
	local check = frame
	local limit = 10

	while check and check.GetName and check ~= UIParent and limit > 0 do
		local fname = check:GetName()
		if visited[fname] then
			print("|cff00ff98Enhance QoL|r: " .. L["AnchorLoop"]:format(fname))
			return UIParent, true
		end
		visited[fname] = true

		local bType
		if fname == "EQOLHealthBar" then
			bType = "HEALTH"
		else
			bType = fname:match("^EQOL(.+)Bar$")
		end

		if not bType then break end
		local anch = getAnchor(bType, addon.variables.unitSpec)
		check = ResourceBars.ResolveRelativeFrameByName(anch and anch.relativeFrame)
		if check == nil or check == UIParent then break end
		limit = limit - 1
	end

	if limit <= 0 then
		print("|cff00ff98Enhance QoL|r: " .. L["AnchorLoop"]:format(info.relativeFrame or ""))
		return UIParent, true
	end
	return frame or UIParent, false
end

function createHealthBar()
	if mainFrame then
		-- Ensure correct parent when re-enabling
		if mainFrame:GetParent() ~= UIParent then mainFrame:SetParent(UIParent) end
		if healthBar and healthBar.GetParent and healthBar:GetParent() ~= UIParent then healthBar:SetParent(UIParent) end
		if mainFrame.SetClampedToScreen then mainFrame:SetClampedToScreen(true) end
		mainFrame:Show()
		healthBar:Show()
		return
	end

	-- Reuse existing named frames if they still exist from a previous enable
	mainFrame = _G["EQOLResourceFrame"] or CreateFrame("frame", "EQOLResourceFrame", UIParent)
	if mainFrame:GetParent() ~= UIParent then mainFrame:SetParent(UIParent) end
	if mainFrame.SetClampedToScreen then mainFrame:SetClampedToScreen(true) end
	healthBar = _G["EQOLHealthBar"] or CreateFrame("StatusBar", "EQOLHealthBar", UIParent, "BackdropTemplate")
	if healthBar:GetParent() ~= UIParent then healthBar:SetParent(UIParent) end
	healthBar._rbType = "HEALTH"
	do
		local cfg = getBarSettings("HEALTH")
		local w = max(RB.MIN_RESOURCE_BAR_WIDTH, (cfg and cfg.width) or RB.DEFAULT_HEALTH_WIDTH)
		local h = (cfg and cfg.height) or RB.DEFAULT_HEALTH_HEIGHT
		healthBar:SetSize(w, h)
	end
	if not healthBar._rbRefreshOnShow then
		healthBar:HookScript("OnShow", function(self) updateHealthBar("ON_SHOW") end)
		healthBar._rbRefreshOnShow = true
	end
	do
		local cfgTex = getBarSettings("HEALTH") or {}
		healthBar:SetStatusBarTexture(resolveTexture(cfgTex))
	end
	healthBar:SetClampedToScreen(true)
	local anchor = getAnchor("HEALTH", addon.variables.unitSpec)
	local rel, looped = resolveAnchor(anchor, "HEALTH")
	-- If we had to fallback due to a loop, recenter on UIParent using TOPLEFT/TOPLEFT
	if looped and (anchor.relativeFrame or "UIParent") ~= "UIParent" then
		local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
		local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
		local w = healthBar:GetWidth() or RB.DEFAULT_HEALTH_WIDTH
		local h = healthBar:GetHeight() or RB.DEFAULT_HEALTH_HEIGHT
		anchor.point = "TOPLEFT"
		anchor.relativeFrame = "UIParent"
		anchor.relativePoint = "TOPLEFT"
		anchor.x = (pw - w) / 2
		anchor.y = (h - ph) / 2
		anchor.autoSpacing = nil
		rel = UIParent
	end
	-- If first run and anchored to UIParent with no persisted offsets yet, persist centered offsets
	if (anchor.relativeFrame or "UIParent") == "UIParent" and (anchor.x == nil or anchor.y == nil) then
		local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
		local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
		local w = healthBar:GetWidth() or RB.DEFAULT_HEALTH_WIDTH
		local h = healthBar:GetHeight() or RB.DEFAULT_HEALTH_HEIGHT
		anchor.point = anchor.point or "TOPLEFT"
		anchor.relativePoint = anchor.relativePoint or "TOPLEFT"
		anchor.x = (pw - w) / 2
		anchor.y = (h - ph) / 2
		anchor.autoSpacing = nil
		rel = UIParent
	end
	healthBar:ClearAllPoints()
	healthBar:SetPoint(anchor.point or "TOPLEFT", rel, anchor.relativePoint or anchor.point or "TOPLEFT", anchor.x or 0, anchor.y or 0)
	local settings = getBarSettings("HEALTH")
	healthBar._cfg = settings
	applyBackdrop(healthBar, settings)

	if not healthBar.text then healthBar.text = healthBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	applyFontToString(healthBar.text, settings)
	applyTextPosition(healthBar, settings, 3, 0)
	configureBarBehavior(healthBar, settings, "HEALTH")

	healthBar:SetMovable(false)
	healthBar:EnableMouse(false)
	if ensureEditModeRegistration then ensureEditModeRegistration() end

	local absorbBar = CreateFrame("StatusBar", "EQOLAbsorbBar", healthBar)
	absorbBar:SetAllPoints(healthBar)
	absorbBar:SetFrameStrata(healthBar:GetFrameStrata())
	absorbBar:SetFrameLevel((healthBar:GetFrameLevel() + 1))
	do
		local cfgTexH = getBarSettings("HEALTH") or {}
		absorbBar:SetStatusBarTexture(resolveTexture({ barTexture = cfgTexH.absorbTexture or cfgTexH.barTexture }))
	end
	absorbBar:SetStatusBarColor(0.8, 0.8, 0.8, 0.8)
	local wantVertical = settings and settings.verticalFill == true
	if absorbBar.SetOrientation and absorbBar._isVertical ~= wantVertical then absorbBar:SetOrientation(wantVertical and "VERTICAL" or "HORIZONTAL") end
	absorbBar._isVertical = wantVertical
	local reverseAbsorb = settings and settings.absorbReverseFill == true
	if settings and settings.absorbOverfill then reverseAbsorb = false end
	if absorbBar.SetReverseFill then absorbBar:SetReverseFill(reverseAbsorb) end
	local absorbTex = absorbBar:GetStatusBarTexture()
	if absorbTex then
		local desiredRotation = wantVertical and (math.pi / 2) or 0
		if absorbBar._texRotation ~= desiredRotation then
			absorbTex:SetRotation(desiredRotation)
			absorbBar._texRotation = desiredRotation
		end
	end
	healthBar.absorbBar = absorbBar
	if healthBar._rbBackdropState and healthBar._rbBackdropState.insets then applyStatusBarInsets(healthBar, healthBar._rbBackdropState.insets, true) end

	updateHealthBar("UNIT_ABSORB_AMOUNT_CHANGED")

	-- Ensure any bars anchored to Health get reanchored when Health changes size
	healthBar:SetScript("OnSizeChanged", function()
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorDependentsOf then addon.Aura.ResourceBars.ReanchorDependentsOf("EQOLHealthBar") end
	end)
end

powertypeClasses = {
	DRUID = {
		[1] = { MAIN = "LUNAR_POWER", RAGE = true, ENERGY = true, MANA = true, COMBO_POINTS = true }, -- Balance (combo in Cat)
		[2] = { MAIN = "ENERGY", COMBO_POINTS = true, RAGE = true, MANA = true }, -- Feral (no Astral Power)
		[3] = { MAIN = "RAGE", ENERGY = true, MANA = true, COMBO_POINTS = true }, -- Guardian (no Astral Power)
		[4] = { MAIN = "MANA", RAGE = true, ENERGY = true, COMBO_POINTS = true }, -- Restoration (combo when in cat)
	},
	DEMONHUNTER = {
		[1] = { MAIN = "FURY" },
		[2] = { MAIN = "FURY" },
		[3] = {
			MAIN = "VOID_METAMORPHOSIS",
			FURY = true,
		},
	},
	DEATHKNIGHT = {
		[1] = { MAIN = "RUNIC_POWER", RUNES = true },
		[2] = { MAIN = "RUNIC_POWER", RUNES = true },
		[3] = { MAIN = "RUNIC_POWER", RUNES = true },
	},
	PALADIN = {
		[1] = { MAIN = "HOLY_POWER", MANA = true },
		[2] = { MAIN = "HOLY_POWER", MANA = true },
		[3] = { MAIN = "HOLY_POWER", MANA = true },
	},
	HUNTER = {
		[1] = { MAIN = "FOCUS" },
		[2] = { MAIN = "FOCUS" },
		[3] = { MAIN = "FOCUS" },
	},
	ROGUE = {
		[1] = { MAIN = "ENERGY", COMBO_POINTS = true },
		[2] = { MAIN = "ENERGY", COMBO_POINTS = true },
		[3] = { MAIN = "ENERGY", COMBO_POINTS = true },
	},
	PRIEST = {
		[1] = { MAIN = "MANA" },
		[2] = { MAIN = "MANA" },
		[3] = { MAIN = "INSANITY", MANA = true },
	},
	SHAMAN = {
		[1] = { MAIN = "MAELSTROM", MANA = true },
		[2] = { MAIN = "MAELSTROM_WEAPON", MANA = true },
		[3] = { MAIN = "MANA" },
	},
	MAGE = {
		[1] = { MAIN = "ARCANE_CHARGES", MANA = true },
		[2] = { MAIN = "MANA" },
		[3] = { MAIN = "MANA" },
	},
	WARLOCK = {
		[1] = { MAIN = "SOUL_SHARDS", MANA = true },
		[2] = { MAIN = "SOUL_SHARDS", MANA = true },
		[3] = { MAIN = "SOUL_SHARDS", MANA = true },
	},
	MONK = {
		[1] = { MAIN = "ENERGY", STAGGER = true },
		[2] = { MAIN = "MANA" },
		[3] = { MAIN = "CHI", ENERGY = true, MANA = true },
	},
	EVOKER = {
		[1] = { MAIN = "ESSENCE", MANA = true },
		[2] = { MAIN = "MANA", ESSENCE = true },
		[3] = { MAIN = "ESSENCE", MANA = true },
	},
	WARRIOR = {
		[1] = { MAIN = "RAGE" },
		[2] = { MAIN = "RAGE" },
		[3] = { MAIN = "RAGE" },
	},
}

classPowerTypes = {
	"RAGE",
	"ESSENCE",
	"FOCUS",
	"ENERGY",
	"FURY",
	"COMBO_POINTS",
	"RUNIC_POWER",
	"RUNES",
	"SOUL_SHARDS",
	"LUNAR_POWER",
	"HOLY_POWER",
	"MAELSTROM",
	"MAELSTROM_WEAPON",
	"VOID_METAMORPHOSIS",
	"CHI",
	"STAGGER",
	"INSANITY",
	"ARCANE_CHARGES",
	"MANA",
}

ResourceBars.powertypeClasses = powertypeClasses
ResourceBars.classPowerTypes = classPowerTypes
ResourceBars.separatorEligible = {
	HOLY_POWER = true,
	SOUL_SHARDS = true,
	ESSENCE = true,
	ARCANE_CHARGES = true,
	CHI = true,
	COMBO_POINTS = true,
	VOID_METAMORPHOSIS = true,
	MAELSTROM_WEAPON = true,
	RUNES = true,
}

function getBarSettings(pType)
	local class = addon.variables.unitClass
	local spec = addon.variables.unitSpec
	local specInfo = getSpecInfo(spec)
	if class and not ResourceBars.IsBarTypeSupportedForClass(pType, class, spec) then return nil end
	if not ResourceBars.IsSpecBarTypeSupported(specInfo, pType) then return nil end
	if addon.db.personalResourceBarSettings and addon.db.personalResourceBarSettings[class] and addon.db.personalResourceBarSettings[class][spec] then
		local cfg = addon.db.personalResourceBarSettings[class][spec][pType]
		if cfg then
			if isAuraPowerType and isAuraPowerType(pType) then ensureAuraPowerDefaults(pType, cfg) end
			ensureDruidShowFormsDefaults(cfg, pType, specInfo)
			ensureRelativeFrameFallback(cfg.anchor, pType, specInfo)
			return cfg
		end
	end
	if class and spec then
		local specCfg = ensureSpecCfg(spec)
		if specCfg and not specCfg[pType] then
			local globalCfg, secondaryIdx = resolveGlobalTemplate(pType, spec)
			if globalCfg then
				specCfg[pType] = CopyTable(globalCfg)
				if isAuraPowerType and isAuraPowerType(pType) then ensureAuraPowerDefaults(pType, specCfg[pType]) end
				ensureDruidShowFormsDefaults(specCfg[pType], pType, specInfo)
				ensureRelativeFrameFallback(specCfg[pType].anchor, pType, specInfo)
				if secondaryIdx and secondaryIdx > 1 then
					local prevType = specSecondaries(specInfo)[secondaryIdx - 1]
					if prevType then maybeChainSecondaryAnchor(specCfg[pType], prevType) end
				end
				return specCfg[pType]
			end
		end
	end
	return nil
end

local function wantsRelativeFrameWidthMatch(anchor) return anchor and (anchor.relativeFrame or "UIParent") ~= "UIParent" and anchor.matchRelativeWidth == true end

local function getConfiguredBarWidth(pType)
	local cfg = getBarSettings(pType)
	local default = (pType == "HEALTH") and RB.DEFAULT_HEALTH_WIDTH or RB.DEFAULT_POWER_WIDTH
	local width = (cfg and type(cfg.width) == "number" and cfg.width > 0 and cfg.width) or default or RB.MIN_RESOURCE_BAR_WIDTH
	return max(RB.MIN_RESOURCE_BAR_WIDTH, width or RB.MIN_RESOURCE_BAR_WIDTH)
end

local function syncBarWidthWithAnchor(pType)
	local frame = (pType == "HEALTH") and healthBar or powerbar[pType]
	if not frame then return false end
	local anchor = getAnchor(pType, addon.variables.unitSpec)
	local baseWidth = max(1, getConfiguredBarWidth(pType) or 0)
	if not wantsRelativeFrameWidthMatch(anchor) then
		local current = frame:GetWidth() or 0
		if abs(current - baseWidth) < 0.5 then return false end
		frame:SetWidth(baseWidth)
		return true
	end
	local relativeFrameName = anchor.relativeFrame
	ensureRelativeFrameHooks(relativeFrameName)
	local relFrame = ResourceBars.ResolveRelativeFrameByName(relativeFrameName)
	if not relFrame or relFrame == UIParent or not relFrame.GetWidth then
		local current = frame:GetWidth() or 0
		if abs(current - baseWidth) < 0.5 then return false end
		frame:SetWidth(baseWidth)
		return true
	end
	local relWidth = relFrame:GetWidth() or 0
	local desired = max(RB.MIN_RESOURCE_BAR_WIDTH, relWidth or 0)
	desired = max(desired, 1)
	local current = frame:GetWidth() or 0
	if abs(current - desired) < 0.5 then return false end
	frame:SetWidth(desired)
	return true
end

local function syncRelativeFrameWidths()
	local changed = false
	if healthBar then changed = syncBarWidthWithAnchor("HEALTH") or changed end
	for pType, bar in pairs(powerbar) do
		if bar then changed = syncBarWidthWithAnchor(pType) or changed end
	end
	return changed
end

ResourceBars.SyncRelativeFrameWidths = syncRelativeFrameWidths

local function handleRelativeFrameGeometryChanged()
	if scheduleRelativeFrameWidthSync then
		scheduleRelativeFrameWidthSync()
	elseif ResourceBars and ResourceBars.SyncRelativeFrameWidths then
		ResourceBars.SyncRelativeFrameWidths()
	end
end

local widthMatchHookedFrames = {}
local pendingHookRetries = {}

ensureRelativeFrameHooks = function(frameName)
	if not frameName or frameName == "UIParent" then return end
	local foundFrame = false
	for _, targetName in ipairs(ResourceBars.GetRelativeFrameHookTargets(frameName)) do
		local frame = _G[targetName]
		if frame then
			foundFrame = true
			if not widthMatchHookedFrames[targetName] and frame.HookScript then
				local okSize = pcall(frame.HookScript, frame, "OnSizeChanged", handleRelativeFrameGeometryChanged)
				local okShow = pcall(frame.HookScript, frame, "OnShow", handleRelativeFrameGeometryChanged)
				local okHide = pcall(frame.HookScript, frame, "OnHide", handleRelativeFrameGeometryChanged)
				if okSize or okShow or okHide then widthMatchHookedFrames[targetName] = true end
			end
		end
	end
	if foundFrame then return end
	if not foundFrame then
		if After and not pendingHookRetries[frameName] then
			pendingHookRetries[frameName] = true
			After(1, function()
				pendingHookRetries[frameName] = nil
				if ensureRelativeFrameHooks then ensureRelativeFrameHooks(frameName) end
			end)
		end
		return
	end
end

local relativeFrameWidthPending = false
scheduleRelativeFrameWidthSync = function()
	if not ResourceBars.SyncRelativeFrameWidths then return end
	if not After then
		ResourceBars.SyncRelativeFrameWidths()
		return
	end
	if relativeFrameWidthPending then return end
	relativeFrameWidthPending = true
	After(0.25, function()
		relativeFrameWidthPending = false
		ResourceBars.SyncRelativeFrameWidths()
	end)
end

function updatePowerBar(type, runeSlot)
	local bar = powerbar[type]
	if not bar or not bar:IsShown() then return end
	-- Special handling for DK RUNES: six sub-bars that fill as cooldown progresses
	if type == "RUNES" then
		local cfg = getBarSettings("RUNES") or {}
		local readyR, readyG, readyB, readyA = resolveRuneReadyColor(cfg)
		local cooldownR, cooldownG, cooldownB, cooldownA
		if ResourceBars.ResolveRuneCooldownColor then
			cooldownR, cooldownG, cooldownB, cooldownA = ResourceBars.ResolveRuneCooldownColor(cfg)
		else
			cooldownR, cooldownG, cooldownB, cooldownA = 0.35, 0.35, 0.35, 1
		end
		local readyChanged = (bar._runeReadyR ~= readyR) or (bar._runeReadyG ~= readyG) or (bar._runeReadyB ~= readyB) or (bar._runeReadyA ~= readyA)
		local cooldownChanged = (bar._runeCooldownR ~= cooldownR) or (bar._runeCooldownG ~= cooldownG) or (bar._runeCooldownB ~= cooldownB) or (bar._runeCooldownA ~= cooldownA)
		bar._runeReadyR, bar._runeReadyG, bar._runeReadyB, bar._runeReadyA = readyR, readyG, readyB, readyA
		bar._runeCooldownR, bar._runeCooldownG, bar._runeCooldownB, bar._runeCooldownA = cooldownR, cooldownG, cooldownB, cooldownA
		bar._rune = bar._rune or {}
		bar._runeOrder = bar._runeOrder or {}
		bar._charging = bar._charging or {}
		local charging = bar._charging
		-- Always rescan all 6 runes (cheap + keeps cache in sync)
		local count = 0
		for i = 1, 6 do
			local start, duration, readyFlag = GetRuneCooldown(i)
			bar._rune[i] = bar._rune[i] or {}
			bar._rune[i].start = start or 0
			bar._rune[i].duration = duration or 0
			bar._rune[i].ready = readyFlag
			if not readyFlag then
				count = count + 1
				charging[count] = i
			end
		end
		for i = count + 1, #charging do
			charging[i] = nil
		end
		if count > 1 then
			local snapshot = bar._chargingSnapshot
			if not snapshot then
				snapshot = {}
				bar._chargingSnapshot = snapshot
			end
			local needsSort = false
			if (bar._lastChargingCount or 0) ~= count then
				needsSort = true
			else
				for i = 1, count do
					if snapshot[i] ~= charging[i] then
						needsSort = true
						break
					end
				end
			end
			if needsSort then
				tsort(charging, function(a, b)
					local ra = (bar._rune[a].start + bar._rune[a].duration)
					local rb = (bar._rune[b].start + bar._rune[b].duration)
					return ra < rb
				end)
				for i = 1, count do
					snapshot[i] = charging[i]
				end
			end
			for i = count + 1, (bar._chargingSnapshot and #bar._chargingSnapshot or 0) do
				snapshot[i] = nil
			end
			bar._lastChargingCount = count
		else
			bar._lastChargingCount = count
			if bar._chargingSnapshot then
				for i = 1, #bar._chargingSnapshot do
					bar._chargingSnapshot[i] = nil
				end
			end
		end
		local chargingMap = bar._chargingMap or {}
		bar._chargingMap = chargingMap
		for i = 1, 6 do
			chargingMap[i] = nil
		end
		for _, idx in ipairs(charging) do
			chargingMap[idx] = true
		end
		local pos = 1
		for i = 1, 6 do
			if not chargingMap[i] then
				bar._runeOrder[pos] = i
				pos = pos + 1
			end
		end
		for _, idx in ipairs(charging) do
			bar._runeOrder[pos] = idx
			pos = pos + 1
		end
		for i = pos, #bar._runeOrder do
			bar._runeOrder[i] = nil
		end

		local anyActive = #charging > 0
		local now = GetTime()
		local soonest
		for i = 1, 6 do
			local runeIndex = bar._runeOrder[i]
			local info = runeIndex and bar._rune[runeIndex]
			local sb = bar.runes and bar.runes[i]
			if sb and info then
				local prog = info.ready and 1 or min(1, max(0, (now - info.start) / max(info.duration, 1)))
				sb:SetValue(prog)
				local wantReady = info.ready or prog >= 1
				local colorUpdated = false
				if sb._isReady ~= wantReady or (wantReady and readyChanged) or ((not wantReady) and cooldownChanged) then
					sb._isReady = wantReady
					if wantReady then
						if ResourceBars.SetStatusBarColorWithGradient then
							ResourceBars.SetStatusBarColorWithGradient(sb, cfg, readyR, readyG, readyB, readyA)
						else
							sb:SetStatusBarColor(readyR, readyG, readyB, readyA or 1)
						end
					else
						if ResourceBars.SetStatusBarColorWithGradient then
							ResourceBars.SetStatusBarColorWithGradient(sb, cfg, cooldownR, cooldownG, cooldownB, cooldownA)
						else
							sb:SetStatusBarColor(cooldownR, cooldownG, cooldownB, cooldownA or 1)
						end
					end
					sb._rbColorInitialized = true
					colorUpdated = true
				end
				if not colorUpdated then
					if wantReady then
						if ResourceBars.RefreshStatusBarGradient then ResourceBars.RefreshStatusBarGradient(sb, cfg, readyR, readyG, readyB, readyA) end
					else
						if ResourceBars.RefreshStatusBarGradient then ResourceBars.RefreshStatusBarGradient(sb, cfg, cooldownR, cooldownG, cooldownB, cooldownA) end
					end
				end
				if sb.fs then
					if cfg.showCooldownText then
						local remain = ceil((info.start + info.duration) - now)
						if remain > 0 and not info.ready then
							sb.fs:SetText(tostring(remain))
						else
							sb.fs:SetText("")
						end
					else
						sb.fs:SetText("")
					end
				end
			end
		end
		if anyActive then
			for _, idx in ipairs(charging) do
				local info = bar._rune[idx]
				if info and not info.ready then
					local remain = (info.start + info.duration) - now
					if remain and remain > 0 then
						if not soonest or remain < soonest then soonest = remain end
					end
				end
			end
		end

		if soonest then
			bar._runeUpdateInterval = min(RB.RUNE_UPDATE_INTERVAL, max(0.05, soonest))
		else
			bar._runeUpdateInterval = nil
		end

		bar._runeConfig = cfg
		if anyActive then
			bar._runesAnimating = true
			if not bar._runeUpdater then
				bar._runeUpdater = function(self, elapsed)
					if not self:IsShown() then
						deactivateRuneTicker(self)
						return
					end
					self._runeAccum = (self._runeAccum or 0) + (elapsed or 0)
					local threshold = self._runeUpdateInterval or RB.RUNE_UPDATE_INTERVAL
					if self._runeAccum >= threshold then
						self._runeAccum = 0
						local n = GetTime()
						local cfgOnUpdate = self._runeConfig or {}
						local rr = self._runeReadyR or readyR
						local rg = self._runeReadyG or readyG
						local rb = self._runeReadyB or readyB
						local ra = self._runeReadyA or readyA or 1
						local cr = self._runeCooldownR or cooldownR
						local cg = self._runeCooldownG or cooldownG
						local cb = self._runeCooldownB or cooldownB
						local ca = self._runeCooldownA or cooldownA or 1
						local forceReady = (self._appliedRuneReadyR ~= rr) or (self._appliedRuneReadyG ~= rg) or (self._appliedRuneReadyB ~= rb) or (self._appliedRuneReadyA ~= ra)
						local forceCooldown = (self._appliedRuneCooldownR ~= cr) or (self._appliedRuneCooldownG ~= cg) or (self._appliedRuneCooldownB ~= cb) or (self._appliedRuneCooldownA ~= ca)
						self._appliedRuneReadyR, self._appliedRuneReadyG, self._appliedRuneReadyB, self._appliedRuneReadyA = rr, rg, rb, ra
						self._appliedRuneCooldownR, self._appliedRuneCooldownG, self._appliedRuneCooldownB, self._appliedRuneCooldownA = cr, cg, cb, ca
						local allReady = true
						for pos = 1, 6 do
							local ri = self._runeOrder and self._runeOrder[pos]
							local data = ri and self._rune and self._rune[ri]
							local sb = self.runes and self.runes[pos]
							if data and sb then
								local prog
								local runeReady = data.ready
								if runeReady then
									prog = 1
								else
									prog = min(1, max(0, (n - data.start) / max(data.duration, 1)))
									if prog >= 1 then
										if not self._runeResync then
											self._runeResync = true
											if After then
												After(0, function()
													self._runeResync = false
													updatePowerBar("RUNES")
												end)
											else
												updatePowerBar("RUNES")
												self._runeResync = false
												return
											end
										end
										runeReady = true
										prog = 1
									end
								end
								sb:SetValue(prog)
								local wantReady = runeReady
								local colorUpdated = false
								if sb._isReady ~= wantReady or (wantReady and forceReady) or ((not wantReady) and forceCooldown) then
									sb._isReady = wantReady
									if wantReady then
										if ResourceBars.SetStatusBarColorWithGradient then
											ResourceBars.SetStatusBarColorWithGradient(sb, cfgOnUpdate, rr, rg, rb, ra)
										else
											sb:SetStatusBarColor(rr, rg, rb, ra or 1)
										end
									else
										if ResourceBars.SetStatusBarColorWithGradient then
											ResourceBars.SetStatusBarColorWithGradient(sb, cfgOnUpdate, cr, cg, cb, ca)
										else
											sb:SetStatusBarColor(cr, cg, cb, ca or 1)
										end
									end
									sb._rbColorInitialized = true
									colorUpdated = true
								end
								if not colorUpdated then
									if wantReady then
										if ResourceBars.RefreshStatusBarGradient then ResourceBars.RefreshStatusBarGradient(sb, cfgOnUpdate, rr, rg, rb, ra) end
									else
										if ResourceBars.RefreshStatusBarGradient then ResourceBars.RefreshStatusBarGradient(sb, cfgOnUpdate, cr, cg, cb, ca) end
									end
								end
								if sb.fs then
									if cfgOnUpdate.showCooldownText and not runeReady then
										local remain = ceil((data.start + data.duration) - n)
										if remain ~= sb._lastRemain then
											if remain > 0 then
												sb.fs:SetText(tostring(remain))
											else
												sb.fs:SetText("")
											end
											sb._lastRemain = remain
										end
										sb.fs:Show()
									else
										if sb._lastRemain ~= nil then
											sb.fs:SetText("")
											sb._lastRemain = nil
										end
										sb.fs:Hide()
									end
								end
								if not runeReady then allReady = false end
							end
						end
						if allReady then deactivateRuneTicker(self) end
					end
				end
			end
			if bar:GetScript("OnUpdate") ~= bar._runeUpdater then
				bar._runeAccum = 0
				bar:SetScript("OnUpdate", bar._runeUpdater)
			end
		else
			deactivateRuneTicker(bar)
		end
		if bar.text then bar.text:SetText("") end
		return
	end
	if type == "STAGGER" then
		local cfg = getBarSettings(type) or {}
		local maxHealth = UnitHealthMax("player") or 1
		if maxHealth <= 0 then return end
		if bar._lastMax ~= maxHealth then
			bar._lastMax = maxHealth
			bar:SetMinMaxValues(0, maxHealth)
		end
		local curPower = (UnitStagger and UnitStagger("player")) or 0

		local style = bar._style or "PERCENT"
		local smooth = cfg.smoothFill == true
		setBarValue(bar, curPower, smooth)
		bar._lastVal = curPower

		local percent = maxHealth > 0 and (curPower / maxHealth) or 0
		local percentDisplay = percent * 100
		local percentStr = formatPercentDisplay(percentDisplay, cfg)
		if bar.text then
			local useShortNumbers = cfg.shortNumbers ~= false
			if style == "NONE" then
				if bar._textShown then
					bar.text:SetText("")
					bar._lastText = ""
					bar.text:Hide()
					bar._textShown = false
				elseif bar._lastText ~= "" then
					bar.text:SetText("")
					bar._lastText = ""
				end
			else
				local text
				if style == "PERCENT" then
					text = percentStr
				elseif style == "CURRENT" then
					text = formatNumber(curPower, useShortNumbers)
				else
					text = formatNumber(curPower, useShortNumbers) .. " / " .. formatNumber(maxHealth, useShortNumbers)
				end
				if (not addon.variables.isMidnight or (issecretvalue and not issecretvalue(text))) and bar._lastText ~= text then
					bar.text:SetText(text)
					bar._lastText = text
				else
					bar.text:SetText(text)
				end
				if not bar._textShown then
					bar.text:Show()
					bar._textShown = true
				end
			end
		end

		local baseR, baseG, baseB, baseA
		if cfg.useBarColor then
			local custom = cfg.barColor or RB.WHITE
			baseR, baseG, baseB, baseA = custom[1] or 1, custom[2] or 1, custom[3] or 1, custom[4] or 1
		else
			local r, g, b, a = getStaggerStateColor(percent, cfg)
			baseR, baseG, baseB = r or 1, g or 1, b or 1
			baseA = a or (cfg.barColor and cfg.barColor[4]) or 1
		end
		bar._baseColor = bar._baseColor or {}
		bar._baseColor[1], bar._baseColor[2], bar._baseColor[3], bar._baseColor[4] = baseR, baseG, baseB, baseA

		local targetR, targetG, targetB, targetA = baseR, baseG, baseB, baseA
		local flag
		if cfg.useMaxColor == true and curPower >= max(maxHealth, 1) then
			local maxCol = cfg.maxColor or RB.WHITE
			targetR, targetG, targetB, targetA = maxCol[1] or targetR, maxCol[2] or targetG, maxCol[3] or targetB, maxCol[4] or targetA
			flag = "max"
		end
		local lc = bar._lastColor or {}
		if lc[1] ~= targetR or lc[2] ~= targetG or lc[3] ~= targetB or lc[4] ~= targetA then
			lc[1], lc[2], lc[3], lc[4] = targetR, targetG, targetB, targetA
			bar._lastColor = lc
			if ResourceBars.SetStatusBarColorWithGradient then
				ResourceBars.SetStatusBarColorWithGradient(bar, cfg, lc[1], lc[2], lc[3], lc[4])
			else
				bar:SetStatusBarColor(lc[1], lc[2], lc[3], lc[4])
			end
		end
		bar._usingMaxColor = flag == "max"
		configureSpecialTexture(bar, type, cfg)
		if ResourceBars.RefreshStatusBarGradient then ResourceBars.RefreshStatusBarGradient(bar, cfg) end
		return
	end
	if isAuraPowerType(type) then
		local cfg = getBarSettings(type) or {}
		if type == "MAELSTROM_WEAPON" then ensureMaelstromWeaponDefaults(cfg) end
		local stacks, logicalMax, visualMax = getAuraPowerCounts(type)
		local cfgDef = RB.AURA_POWER_CONFIG[type] or {}
		logicalMax = logicalMax > 0 and logicalMax or cfgDef.maxStacks or visualMax
		visualMax = visualMax > 0 and visualMax or logicalMax
		if type == "MAELSTROM_WEAPON" then
			local desiredSegments
			if cfg.useMaelstromTenStacks then
				desiredSegments = logicalMax > 0 and logicalMax or RB.MAELSTROM_WEAPON_MAX_STACKS
			else
				desiredSegments = cfg.visualSegments or RB.MAELSTROM_WEAPON_SEGMENTS
			end
			if desiredSegments and desiredSegments > 0 then visualMax = desiredSegments end
		end
		if bar._lastMax ~= visualMax then
			bar:SetMinMaxValues(0, visualMax)
			bar._lastMax = visualMax
		end

		local style = bar._style or "CURMAX"
		local smooth = cfg.smoothFill == true
		local shownStacks = (visualMax and visualMax > 0) and ((stacks <= 0) and 0 or (((stacks - 1) % visualMax) + 1)) or stacks
		setBarValue(bar, shownStacks, smooth)
		bar._lastVal = shownStacks

		local percent = logicalMax > 0 and (stacks / logicalMax * 100) or 0
		local percentStr = formatPercentDisplay(percent, cfg)

		if bar.text then
			local useShortNumbers = cfg.shortNumbers ~= false
			if style == "NONE" then
				if bar._textShown then
					bar.text:SetText("")
					bar._lastText = ""
					bar.text:Hide()
					bar._textShown = false
				elseif bar._lastText ~= "" then
					bar.text:SetText("")
					bar._lastText = ""
				end
			else
				local text
				if style == "PERCENT" then
					text = percentStr
				elseif style == "CURRENT" then
					text = formatNumber(stacks, useShortNumbers)
				else
					text = formatNumber(stacks, useShortNumbers) .. " / " .. formatNumber(logicalMax, useShortNumbers)
				end
				if (not addon.variables.isMidnight or (issecretvalue and not issecretvalue(text))) and bar._lastText ~= text then
					bar.text:SetText(text)
					bar._lastText = text
				else
					bar.text:SetText(text)
				end
				if not bar._textShown then
					bar.text:Show()
					bar._textShown = true
				end
			end
		end

		bar._baseColor = bar._baseColor or {}
		if bar._baseColor[1] == nil then
			local br, bg, bb, ba = bar:GetStatusBarColor()
			bar._baseColor[1], bar._baseColor[2], bar._baseColor[3], bar._baseColor[4] = br, bg, bb, ba or 1
		end
		if cfg.useBarColor then
			local custom = cfg.barColor or RB.WHITE
			bar._baseColor[1], bar._baseColor[2], bar._baseColor[3], bar._baseColor[4] = custom[1] or 1, custom[2] or 1, custom[3] or 1, custom[4] or 1
		elseif cfg.useClassColor == true then
			local cr, cg, cb, ca = getPlayerClassColor()
			bar._baseColor[1], bar._baseColor[2], bar._baseColor[3], bar._baseColor[4] = cr, cg, cb, ca or (cfg.barColor and cfg.barColor[4]) or 1
		elseif cfgDef and cfgDef.defaultColor then
			local c = cfgDef.defaultColor
			bar._baseColor[1], bar._baseColor[2], bar._baseColor[3], bar._baseColor[4] = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
		end

		local targetR, targetG, targetB, targetA = bar._baseColor[1] or 1, bar._baseColor[2] or 1, bar._baseColor[3] or 1, bar._baseColor[4] or 1
		local flag
		local useMaxDefault = (RB.AURA_POWER_CONFIG[type] and RB.AURA_POWER_CONFIG[type].useMaxColorDefault) or false
		if (cfg.useMaxColor ~= false and (cfg.useMaxColor or useMaxDefault)) and logicalMax > 0 and stacks >= logicalMax then
			local maxCol = cfg.maxColor or RB.WHITE
			targetR, targetG, targetB, targetA = maxCol[1] or targetR, maxCol[2] or targetG, maxCol[3] or targetB, maxCol[4] or targetA
			flag = "max"
		elseif type == "MAELSTROM_WEAPON" and cfg.useMaelstromFiveColor ~= false and stacks >= RB.MAELSTROM_WEAPON_SEGMENTS then
			local mid = cfg.maelstromFiveColor or ResourcebarVars.DEFAULT_MAELSTROM_WEAPON_FIVE_COLOR
			targetR, targetG, targetB, targetA = mid[1] or targetR, mid[2] or targetG, mid[3] or targetB, mid[4] or targetA
			flag = "mid"
		end
		local lc = bar._lastColor or {}
		if lc[1] ~= targetR or lc[2] ~= targetG or lc[3] ~= targetB or lc[4] ~= targetA then
			lc[1], lc[2], lc[3], lc[4] = targetR, targetG, targetB, targetA
			bar._lastColor = lc
			if ResourceBars.SetStatusBarColorWithGradient then
				ResourceBars.SetStatusBarColorWithGradient(bar, cfg, lc[1], lc[2], lc[3], lc[4])
			else
				bar:SetStatusBarColor(lc[1], lc[2], lc[3], lc[4])
			end
		end
		bar._usingMaxColor = flag == "max"
		bar._usingMaelstromFiveColor = flag == "mid"
		refreshDiscreteSegmentsForBar(type, bar, cfg, shownStacks, visualMax)
		configureSpecialTexture(bar, type, cfg)
		if ResourceBars.RefreshStatusBarGradient then ResourceBars.RefreshStatusBarGradient(bar, cfg) end
		return
	end
	local pType = POWER_ENUM[type]
	if not pType then return end
	local cfg = getBarSettings(type) or {}
	local cfgDef = (RB.POWER_CONFIG and RB.POWER_CONFIG[type]) or {}
	local isSoulShards = type == "SOUL_SHARDS"
	local useRaw = isSoulShards and addon.variables and addon.variables.unitClass == "WARLOCK" and addon.variables.unitSpec == 3
	local maxPower = bar._lastMax
	if not maxPower or bar._lastMaxRaw ~= useRaw then
		maxPower = UnitPowerMax("player", pType, useRaw)
		bar._lastMax = maxPower
		bar._lastMaxRaw = useRaw
		bar:SetMinMaxValues(0, maxPower)
	end
	local curPower = UnitPower("player", pType, useRaw)
	local barValue = curPower
	local essenceFraction
	local essenceSecret
	if type == "ESSENCE" then
		essenceSecret = issecretvalue and (issecretvalue(curPower) or issecretvalue(maxPower))
		if not essenceSecret and maxPower and maxPower > 0 then
			local now = GetTime()
			essenceFraction = ResourceBars.ComputeEssenceFraction(bar, curPower, maxPower, now, POWER_ENUM.ESSENCE)
			if essenceFraction and essenceFraction > 0 and curPower < maxPower then barValue = min(maxPower, curPower + essenceFraction) end
		else
			essenceFraction = 0
		end
	end
	local displayCur = curPower
	local displayMax = maxPower
	if isSoulShards and useRaw then
		displayCur = (curPower or 0) / 10
		displayMax = (maxPower or 0) / 10
	end

	local style = bar._style or ((type == "MANA") and "PERCENT" or "CURMAX")
	local smooth = cfg.smoothFill == true and type ~= "ESSENCE"
	setBarValue(bar, barValue, smooth)
	bar._lastVal = barValue
	local percent = getPowerPercent("player", pType, curPower, maxPower)
	local percentStr = formatPercentDisplay(percent, cfg)
	if bar.text then
		local useShortNumbers = cfg.shortNumbers ~= false
		if style == "NONE" then
			if bar._textShown then
				bar.text:SetText("")
				bar._lastText = ""
				bar.text:Hide()
				bar._textShown = false
			elseif bar._lastText ~= "" then
				bar.text:SetText("")
				bar._lastText = ""
			end
		else
			local text
			if style == "PERCENT" then
				text = percentStr
			elseif style == "CURRENT" then
				if isSoulShards then
					text = formatSoulShardValue(displayCur)
				else
					text = formatNumber(curPower, useShortNumbers)
				end
			else -- CURMAX
				if isSoulShards then
					text = formatSoulShardValue(displayCur) .. " / " .. formatSoulShardValue(displayMax)
				else
					text = formatNumber(curPower, useShortNumbers) .. " / " .. formatNumber(maxPower, useShortNumbers)
				end
			end
			if (not addon.variables.isMidnight or (issecretvalue and not issecretvalue(text))) and bar._lastText ~= text then
				bar.text:SetText(text)
				bar._lastText = text
			else
				bar.text:SetText(text)
			end
			if not bar._textShown then
				bar.text:Show()
				bar._textShown = true
			end
		end
	end

	bar._baseColor = bar._baseColor or {}
	if bar._baseColor[1] == nil then
		local br, bg, bb, ba = bar:GetStatusBarColor()
		bar._baseColor[1], bar._baseColor[2], bar._baseColor[3], bar._baseColor[4] = br, bg, bb, ba or 1
	end
	if cfg.useBarColor then
		local custom = cfg.barColor or RB.WHITE
		bar._baseColor[1], bar._baseColor[2], bar._baseColor[3], bar._baseColor[4] = custom[1] or 1, custom[2] or 1, custom[3] or 1, custom[4] or 1
	elseif cfg.useClassColor == true then
		local cr, cg, cb, ca = getPlayerClassColor()
		bar._baseColor[1], bar._baseColor[2], bar._baseColor[3], bar._baseColor[4] = cr, cg, cb, ca or (cfg.barColor and cfg.barColor[4]) or 1
	elseif cfgDef and cfgDef.defaultColor then
		local c = cfgDef.defaultColor
		bar._baseColor[1], bar._baseColor[2], bar._baseColor[3], bar._baseColor[4] = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
	end

	local useHolyThreeColor = (type == "HOLY_POWER") and cfg.useHolyThreeColor == true
	local holyThreeThreshold = 3
	local reachedThree = useHolyThreeColor and curPower >= holyThreeThreshold
	if not addon.variables.isMidnight or (issecretvalue and not issecretvalue(curPower) and not issecretvalue(maxPower)) then
		local reachedCap = curPower >= max(maxPower, 1)
		local useMaxColor = cfg.useMaxColor == true
		local targetR, targetG, targetB, targetA = bar._baseColor[1], bar._baseColor[2], bar._baseColor[3], bar._baseColor[4]
		local flag
		if useMaxColor and reachedCap then
			local maxCol = cfg.maxColor or RB.WHITE
			targetR, targetG, targetB, targetA = maxCol[1] or targetR, maxCol[2] or targetG, maxCol[3] or targetB, maxCol[4] or (bar._baseColor[4] or 1)
			flag = "max"
		elseif reachedThree then
			targetR, targetG, targetB, targetA = getHolyThreeColor(cfg)
			flag = "holy3"
		end
		local lc = bar._lastColor or {}
		if lc[1] ~= targetR or lc[2] ~= targetG or lc[3] ~= targetB or lc[4] ~= targetA then
			lc[1], lc[2], lc[3], lc[4] = targetR, targetG, targetB, targetA
			bar._lastColor = lc
			if ResourceBars.SetStatusBarColorWithGradient then
				ResourceBars.SetStatusBarColorWithGradient(bar, cfg, lc[1], lc[2], lc[3], lc[4])
			else
				bar:SetStatusBarColor(lc[1], lc[2], lc[3], lc[4])
			end
		end
		bar._usingMaxColor = flag == "max"
		bar._usingHolyThreeColor = flag == "holy3"
	else
		local lc = bar._lastColor or {}
		local base = bar._baseColor
		if base then
			local br, bgc, bb, ba = base[1] or 1, base[2] or 1, base[3] or 1, base[4] or 1
			local targetR, targetG, targetB, targetA = br, bgc, bb, ba
			local useMaxColor = cfg.useMaxColor == true
			local reachedCap = (issecretvalue and not issecretvalue(curPower) or not addon.variables.isMidnight) and curPower >= max(maxPower, 1)
			if useMaxColor and issecretvalue and issecretvalue(curPower) and UnitPowerPercent and curvePower[type] then
				local curveColor = UnitPowerPercent("player", pType, false, curvePower[type])
				bar:GetStatusBarTexture():SetVertexColor(curveColor:GetRGBA())
			else
				if useMaxColor and reachedCap then
					local maxCol = cfg.maxColor or RB.WHITE
					targetR, targetG, targetB, targetA = maxCol[1] or br, maxCol[2] or bgc, maxCol[3] or bb, maxCol[4] or ba
				elseif reachedThree then
					targetR, targetG, targetB, targetA = getHolyThreeColor(cfg)
				end
				if lc[1] ~= targetR or lc[2] ~= targetG or lc[3] ~= targetB or lc[4] ~= targetA then
					bar._lastColor = lc
					if cfg.useBarColor and not cfg.useMaxColor and not reachedThree then bar:GetStatusBarTexture():SetVertexColor(1, 1, 1, 1) end
					if ResourceBars.SetStatusBarColorWithGradient then
						ResourceBars.SetStatusBarColorWithGradient(bar, cfg, targetR, targetG, targetB, targetA)
					else
						bar:SetStatusBarColor(targetR, targetG, targetB, targetA)
					end
				end
			end
		end
		bar._usingMaxColor = (cfg.useMaxColor == true)
		bar._usingHolyThreeColor = reachedThree and not bar._usingMaxColor
	end

	if type == "ESSENCE" then
		local maxVal = maxPower or 0
		local essenceTexture = resolveTexture(cfg)
		if essenceSecret then
			ResourceBars.UpdateEssenceSegments(bar, cfg, 0, 0, 0, RB.WHITE, ResourceBars.LayoutEssences, essenceTexture)
			ResourceBars.DeactivateEssenceTicker(bar)
		else
			ResourceBars.UpdateEssenceSegments(bar, cfg, curPower, maxVal, essenceFraction or 0, RB.WHITE, ResourceBars.LayoutEssences, essenceTexture)
			bar._essenceConfig = cfg
			bar._essenceMaxPower = maxVal
			if maxVal > 0 and curPower < maxVal then
				bar._essenceAnimating = true
				local tick = bar._essenceTickDuration or 5
				bar._essenceUpdateInterval = min(RB.ESSENCE_UPDATE_INTERVAL, max(0.05, tick / 20))
				if not bar._essenceUpdater then
					bar._essenceUpdater = function(self, elapsed)
						if not self:IsShown() then
							ResourceBars.DeactivateEssenceTicker(self)
							return
						end
						self._essenceAccum = (self._essenceAccum or 0) + (elapsed or 0)
						local threshold = self._essenceUpdateInterval or RB.ESSENCE_UPDATE_INTERVAL
						if self._essenceAccum < threshold then return end
						self._essenceAccum = 0
						local now = GetTime()
						local current = UnitPower("player", POWER_ENUM.ESSENCE)
						local maxPower = UnitPowerMax("player", POWER_ENUM.ESSENCE)
						self._essenceMaxPower = maxPower
						local cfgOnUpdate = self._essenceConfig or {}
						local texOnUpdate = resolveTexture(cfgOnUpdate)
						if issecretvalue and (issecretvalue(current) or issecretvalue(maxPower)) then
							ResourceBars.UpdateEssenceSegments(self, cfgOnUpdate, 0, 0, 0, RB.WHITE, ResourceBars.LayoutEssences, texOnUpdate)
							ResourceBars.DeactivateEssenceTicker(self)
							return
						end
						if not maxPower or maxPower <= 0 then
							ResourceBars.DeactivateEssenceTicker(self)
							return
						end
						local fraction = ResourceBars.ComputeEssenceFraction(self, current, maxPower, now, POWER_ENUM.ESSENCE)
						if not self._essenceNextTick or current >= maxPower then
							ResourceBars.DeactivateEssenceTicker(self)
							ResourceBars.UpdateEssenceSegments(self, cfgOnUpdate, current, maxPower, 0, RB.WHITE, ResourceBars.LayoutEssences, texOnUpdate)
							return
						end
						if self._essenceNextTick <= now then
							if After then
								After(0, function() updatePowerBar("ESSENCE") end)
							else
								updatePowerBar("ESSENCE")
							end
							return
						end
						local value = current + (fraction or 0)
						if value > maxPower then value = maxPower end
						self:SetValue(value)
						self._lastVal = value
						ResourceBars.UpdateEssenceSegments(self, cfgOnUpdate, current, maxPower, fraction or 0, RB.WHITE, ResourceBars.LayoutEssences, texOnUpdate)
					end
				end
				if bar:GetScript("OnUpdate") ~= bar._essenceUpdater then
					bar._essenceAccum = 0
					bar:SetScript("OnUpdate", bar._essenceUpdater)
				end
			else
				ResourceBars.DeactivateEssenceTicker(bar)
			end
		end
	else
		local discreteCur = isSoulShards and displayCur or curPower
		local discreteMax = isSoulShards and displayMax or maxPower
		refreshDiscreteSegmentsForBar(type, bar, cfg, discreteCur, discreteMax)
	end

	configureSpecialTexture(bar, type, cfg)
	if ResourceBars.RefreshStatusBarGradient then ResourceBars.RefreshStatusBarGradient(bar, cfg) end
end

function forceColorUpdate(pType)
	if pType == "HEALTH" then
		updateHealthBar("FORCE_COLOR")
		return
	end

	if pType and powerbar[pType] then updatePowerBar(pType) end
end

setParentBarTextureVisible = function(bar, visible)
	if not bar then return end
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if tex then tex:SetAlpha(visible and 1 or 0) end
end

getSeparatorSegmentCount = function(pType, cfg)
	if pType == "RUNES" then
		return 6
	elseif pType == "ESSENCE" then
		return POWER_ENUM and UnitPowerMax("player", POWER_ENUM.ESSENCE) or 0
	elseif isAuraPowerType and isAuraPowerType(pType) then
		local auraCfg = RB.AURA_POWER_CONFIG[pType] or {}
		return (cfg and cfg.visualSegments) or auraCfg.visualSegments or auraCfg.maxStacks or 0
	end
	local enumId = POWER_ENUM[pType]
	return enumId and UnitPowerMax("player", enumId) or 0
end

shouldUseDiscreteSeparatorSegments = function(pType, cfg)
	if pType == "RUNES" or pType == "ESSENCE" then return false end
	return ResourceBars.separatorEligible and ResourceBars.separatorEligible[pType] and cfg and cfg.showSeparator == true
end

refreshDiscreteSegmentsForBar = function(pType, bar, cfg, value, maxValue)
	if not bar then return false end
	if not shouldUseDiscreteSeparatorSegments(pType, cfg) then
		if ResourceBars.HideDiscreteSegments then ResourceBars.HideDiscreteSegments(bar) end
		setParentBarTextureVisible(bar, true)
		return false
	end

	local segments = getSeparatorSegmentCount(pType, cfg)
	if not segments or segments < 2 then
		if ResourceBars.HideDiscreteSegments then ResourceBars.HideDiscreteSegments(bar) end
		setParentBarTextureVisible(bar, true)
		return false
	end

	local scaledValue = tonumber(value) or 0
	local sourceMax = tonumber(maxValue) or segments
	if sourceMax > 0 and sourceMax ~= segments then scaledValue = (scaledValue / sourceMax) * segments end

	if ResourceBars.UpdateDiscreteSegments then
		ResourceBars.UpdateDiscreteSegments(
			bar,
			cfg,
			segments,
			scaledValue,
			bar._lastColor or bar._baseColor or RB.WHITE,
			resolveTexture(cfg),
			(cfg and cfg.separatorThickness) or RB.SEPARATOR_THICKNESS,
			(cfg and cfg.separatorColor) or RB.SEP_DEFAULT
		)
		setParentBarTextureVisible(bar, false)
		return true
	end

	setParentBarTextureVisible(bar, true)
	return false
end

-- Create/update separator ticks for a given bar type if enabled
updateBarSeparators = function(pType)
	local eligible = ResourceBars.separatorEligible
	if pType ~= "RUNES" and (not eligible or not eligible[pType]) then return end
	local bar = powerbar[pType]
	if not bar then return end
	local cfg = getBarSettings(pType)
	if not (cfg and cfg.showSeparator) then
		if pType ~= "RUNES" and pType ~= "ESSENCE" then
			if ResourceBars.HideDiscreteSegments then ResourceBars.HideDiscreteSegments(bar) end
			setParentBarTextureVisible(bar, true)
		end
		if bar.separatorMarks then
			for _, tx in ipairs(bar.separatorMarks) do
				tx:Hide()
			end
		end
		return
	end

	if shouldUseDiscreteSeparatorSegments(pType, cfg) then
		local segCount = getSeparatorSegmentCount(pType, cfg)
		if ResourceBars.LayoutDiscreteSegments and segCount and segCount >= 2 then
			ResourceBars.LayoutDiscreteSegments(bar, cfg, segCount, resolveTexture(cfg), (cfg and cfg.separatorThickness) or RB.SEPARATOR_THICKNESS, (cfg and cfg.separatorColor) or RB.SEP_DEFAULT)
			setParentBarTextureVisible(bar, false)
		else
			if ResourceBars.HideDiscreteSegments then ResourceBars.HideDiscreteSegments(bar) end
			setParentBarTextureVisible(bar, true)
		end
		if bar.separatorMarks then
			for _, tx in ipairs(bar.separatorMarks) do
				tx:Hide()
			end
		end
		return
	elseif pType ~= "RUNES" and pType ~= "ESSENCE" then
		if ResourceBars.HideDiscreteSegments then ResourceBars.HideDiscreteSegments(bar) end
		setParentBarTextureVisible(bar, true)
	end

	local segments = getSeparatorSegmentCount(pType, cfg)
	if not segments or segments < 2 then
		-- Nothing to separate
		if bar.separatorMarks then
			for _, tx in ipairs(bar.separatorMarks) do
				tx:Hide()
			end
		end
		return
	end

	local inset = bar._rbContentInset or RB.ZERO_INSETS
	local inner = bar._rbInner or bar

	-- Legacy overlay cleanup: no longer needed
	if bar._sepOverlay then
		bar._sepOverlay:Hide()
		bar._sepOverlay:SetParent(nil)
		bar._sepOverlay = nil
	end

	bar.separatorMarks = bar.separatorMarks or {}

	local function AcquireMark(index)
		local tex = bar.separatorMarks[index]
		if not tex then
			tex = bar:CreateTexture(nil, "OVERLAY", nil, 7)
			bar.separatorMarks[index] = tex
		elseif tex.GetParent and tex:GetParent() ~= bar then
			tex:SetParent(bar)
		end
		if tex.SetDrawLayer then tex:SetDrawLayer("OVERLAY", 7) end
		return tex
	end

	for _, tx in ipairs(bar.separatorMarks) do
		if tx then
			if tx.GetParent and tx:GetParent() ~= bar then tx:SetParent(bar) end
			if tx.SetDrawLayer then tx:SetDrawLayer("OVERLAY", 7) end
		end
	end

	local needed = segments - 1
	local w = max(1, (inner and inner.GetWidth and inner:GetWidth()) or ((bar:GetWidth() or 0) - (inset.left + inset.right)))
	local h = max(1, (inner and inner.GetHeight and inner:GetHeight()) or ((bar:GetHeight() or 0) - (inset.top + inset.bottom)))
	local vertical = cfg and cfg.verticalFill == true
	local span = vertical and h or w
	local desiredThickness = (cfg and cfg.separatorThickness) or RB.SEPARATOR_THICKNESS
	local thickness
	if vertical then
		local segH = span / segments
		thickness = min(desiredThickness, max(1, floor(segH - 1)))
	else
		local segW = span / segments
		thickness = min(desiredThickness, max(1, floor(segW - 1)))
	end
	local sc = (cfg and cfg.separatorColor) or RB.SEP_DEFAULT
	local r, g, b, a = sc[1] or 1, sc[2] or 1, sc[3] or 1, sc[4] or 0.5

	if
		bar._sepW == w
		and bar._sepH == h
		and bar._sepSegments == segments
		and bar._sepR == r
		and bar._sepG == g
		and bar._sepB == b
		and bar._sepA == a
		and bar._sepThickness == thickness
		and bar._sepVertical == vertical
	then
		return
	end

	-- Position visible separators
	for i = 1, needed do
		local tx = AcquireMark(i)
		tx:ClearAllPoints()
		local frac = i / segments
		local half = floor(thickness * 0.5)
		tx:SetColorTexture(r, g, b, a)
		if vertical then
			local y = SnapFractionToSpan(bar, h, frac)
			tx:SetPoint("TOP", inner, "TOP", 0, -(y - max(0, half)))
			tx:SetSize(w, thickness)
		else
			local x = SnapFractionToSpan(bar, w, frac)
			tx:SetPoint("LEFT", inner, "LEFT", x - max(0, half), 0)
			tx:SetSize(thickness, h)
		end
		tx:Show()
	end
	-- Hide extras
	for i = needed + 1, #bar.separatorMarks do
		bar.separatorMarks[i]:Hide()
	end
	-- Cache current geometry and color to fast-exit next time
	bar._sepW, bar._sepH, bar._sepSegments, bar._sepThickness = w, h, segments, thickness
	bar._sepR, bar._sepG, bar._sepB, bar._sepA = r, g, b, a
	bar._sepVertical = vertical
end

local function getSafeThresholdMaxValue(bar, pType)
	local function isSecret(value) return issecretvalue and issecretvalue(value) end

	local maxValue
	if bar and bar.GetMinMaxValues then
		local _, tmpMax = bar:GetMinMaxValues()
		if tmpMax ~= nil and not isSecret(tmpMax) then maxValue = tmpMax end
	end
	if not maxValue and bar then
		local last = bar._lastMax
		if last ~= nil and not isSecret(last) then maxValue = last end
	end
	if not maxValue and pType and POWER_ENUM and UnitPowerMax then
		local useRaw = pType == "SOUL_SHARDS" and addon.variables and addon.variables.unitClass == "WARLOCK" and addon.variables.unitSpec == 3
		local tmp = UnitPowerMax("player", POWER_ENUM[pType], useRaw)
		if tmp ~= nil and not isSecret(tmp) then maxValue = tmp end
	end
	if maxValue and bar then
		bar._rbThresholdMax = maxValue
	elseif bar and bar._rbThresholdMax and not isSecret(bar._rbThresholdMax) then
		maxValue = bar._rbThresholdMax
	end
	return maxValue
end

updateBarThresholds = function(pType)
	if pType == "HEALTH" then return end
	local bar = powerbar[pType]
	if not bar then return end
	local cfg = getBarSettings(pType)
	if not (cfg and cfg.showThresholds) then
		if bar.thresholdMarks then
			for _, tx in ipairs(bar.thresholdMarks) do
				tx:Hide()
			end
		end
		return
	end

	local values = {}
	local useAbsolute = cfg.useAbsoluteThresholds == true
	local maxValue
	if useAbsolute then
		maxValue = getSafeThresholdMaxValue(bar, pType)
		if not maxValue or maxValue <= 0 then
			if bar.thresholdMarks then
				for _, tx in ipairs(bar.thresholdMarks) do
					tx:Hide()
				end
			end
			return
		end
	end
	local count = tonumber(cfg and cfg.thresholdCount) or RB.DEFAULT_THRESHOLD_COUNT or 3
	if count < 1 then count = 1 end
	if count > 4 then count = 4 end
	local list = cfg and cfg.thresholds
	local function addThresholdValue(v)
		if not v or v <= 0 then return end
		if useAbsolute then
			if maxValue and maxValue > 0 and v < maxValue then values[#values + 1] = (v / maxValue) * 100 end
		elseif v < 100 then
			values[#values + 1] = v
		end
	end
	if type(list) == "table" then
		for i = 1, min(#list, count) do
			local v = tonumber(list[i])
			addThresholdValue(v)
		end
	else
		local defaults = RB.DEFAULT_THRESHOLDS
		if type(defaults) == "table" then
			for i = 1, min(#defaults, count) do
				local v = tonumber(defaults[i])
				addThresholdValue(v)
			end
		end
	end

	if #values == 0 then
		if bar.thresholdMarks then
			for _, tx in ipairs(bar.thresholdMarks) do
				tx:Hide()
			end
		end
		return
	end

	tsort(values)
	local unique = {}
	local last
	for i = 1, #values do
		local v = values[i]
		if v ~= last then
			unique[#unique + 1] = v
			last = v
		end
	end
	values = unique
	if #values == 0 then
		if bar.thresholdMarks then
			for _, tx in ipairs(bar.thresholdMarks) do
				tx:Hide()
			end
		end
		return
	end

	local inset = bar._rbContentInset or RB.ZERO_INSETS
	local inner = bar._rbInner or bar
	bar.thresholdMarks = bar.thresholdMarks or {}

	local function AcquireMark(index)
		local tex = bar.thresholdMarks[index]
		if not tex then
			tex = bar:CreateTexture(nil, "OVERLAY", nil, 6)
			bar.thresholdMarks[index] = tex
		elseif tex.GetParent and tex:GetParent() ~= bar then
			tex:SetParent(bar)
		end
		if tex.SetDrawLayer then tex:SetDrawLayer("OVERLAY", 6) end
		return tex
	end

	for _, tx in ipairs(bar.thresholdMarks) do
		if tx then
			if tx.GetParent and tx:GetParent() ~= bar then tx:SetParent(bar) end
			if tx.SetDrawLayer then tx:SetDrawLayer("OVERLAY", 6) end
		end
	end

	local w = max(1, (inner and inner.GetWidth and inner:GetWidth()) or ((bar:GetWidth() or 0) - (inset.left + inset.right)))
	local h = max(1, (inner and inner.GetHeight and inner:GetHeight()) or ((bar:GetHeight() or 0) - (inset.top + inset.bottom)))
	local vertical = cfg and cfg.verticalFill == true
	local reverse = cfg and cfg.reverseFill == true
	local desiredThickness = (cfg and cfg.thresholdThickness) or RB.THRESHOLD_THICKNESS or RB.SEPARATOR_THICKNESS
	local thickness = min(desiredThickness, vertical and h or w)
	if thickness < 1 then thickness = 1 end
	local tc = (cfg and cfg.thresholdColor) or RB.THRESHOLD_DEFAULT or RB.SEP_DEFAULT or RB.WHITE
	local r, g, b, a
	if tc.r then
		r, g, b, a = tc.r or 1, tc.g or 1, tc.b or 1, tc.a or 0.5
	else
		r, g, b, a = tc[1] or 1, tc[2] or 1, tc[3] or 1, tc[4] or 0.5
	end

	for i = 1, #values do
		local tx = AcquireMark(i)
		tx:ClearAllPoints()
		local frac = values[i] / 100
		if reverse then frac = 1 - frac end
		local half = floor(thickness * 0.5)
		tx:SetColorTexture(r, g, b, a)
		if vertical then
			local y = SnapFractionToSpan(bar, h, frac)
			tx:SetPoint("BOTTOM", inner, "BOTTOM", 0, y - max(0, half))
			tx:SetSize(w, thickness)
		else
			local x = SnapFractionToSpan(bar, w, frac)
			tx:SetPoint("LEFT", inner, "LEFT", x - max(0, half), 0)
			tx:SetSize(thickness, h)
		end
		tx:Show()
	end
	for i = #values + 1, #bar.thresholdMarks do
		bar.thresholdMarks[i]:Hide()
	end
end

-- Layout helper for DK RUNES: create or resize 6 child statusbars
function layoutRunes(bar)
	if not bar then return end
	bar.runes = bar.runes or {}
	local count = 6
	local gap = 0
	local inner = bar._rbInner or bar
	local overlay = ensureTextOverlayFrame(bar) or bar
	local w = max(1, inner:GetWidth() or (bar:GetWidth() or 0))
	local h = max(1, inner:GetHeight() or (bar:GetHeight() or 0))
	local cfg = getBarSettings("RUNES") or {}
	if nil == cfg.showCooldownText then cfg.showCooldownText = true end
	local show = cfg.showCooldownText ~= false -- default on
	local size = cfg.cooldownTextFontSize or cfg.fontSize or 16
	local fontPath = resolveFontFace(cfg)
	local fontOutline = resolveFontOutline(cfg)
	local fr, fg, fb, fa = resolveFontColor(cfg)
	local vertical = cfg.verticalFill == true
	local readyR, readyG, readyB, readyA = resolveRuneReadyColor(cfg)
	local segPrimary
	if vertical then
		segPrimary = max(1, floor((h - gap * (count - 1)) / count + 0.5))
	else
		segPrimary = max(1, floor((w - gap * (count - 1)) / count + 0.5))
	end
	for i = 1, count do
		local sb = bar.runes[i]
		if not sb then
			sb = CreateFrame("StatusBar", bar:GetName() .. "Rune" .. i, inner)
			local cfgR = getBarSettings("RUNES") or {}
			sb:SetStatusBarTexture(resolveTexture(cfgR))
			sb:SetMinMaxValues(0, 1)
			sb:Show()
			bar.runes[i] = sb
		end
		do
			local cfgR2 = getBarSettings("RUNES") or {}
			local wantTex = resolveTexture(cfgR2)
			if sb._rb_tex ~= wantTex then
				sb:SetStatusBarTexture(wantTex)
				sb._rb_tex = wantTex
			end
		end
		sb:ClearAllPoints()
		if sb:GetParent() ~= inner then sb:SetParent(inner) end
		if vertical then
			sb:SetWidth(w)
			sb:SetHeight(segPrimary)
			sb:SetOrientation("VERTICAL")
			if i == 1 then
				sb:SetPoint("BOTTOM", inner, "BOTTOM", 0, 0)
			else
				sb:SetPoint("BOTTOM", bar.runes[i - 1], "TOP", 0, gap)
			end
			if i == count then sb:SetPoint("TOP", inner, "TOP", 0, 0) end
		else
			sb:SetHeight(h)
			sb:SetOrientation("HORIZONTAL")
			if i == 1 then
				sb:SetPoint("LEFT", inner, "LEFT", 0, 0)
			else
				sb:SetPoint("LEFT", bar.runes[i - 1], "RIGHT", gap, 0)
			end
			if i == count then
				sb:SetPoint("RIGHT", inner, "RIGHT", 0, 0)
			else
				sb:SetWidth(segPrimary)
			end
		end
		-- cooldown text per segment
		if not sb.fs then sb.fs = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
		if sb.fs:GetParent() ~= overlay then sb.fs:SetParent(overlay) end
		sb.fs:SetDrawLayer("OVERLAY")
		sb.fs:ClearAllPoints()
		sb.fs:SetPoint("CENTER", sb, "CENTER", 0, 0)
		if sb._fsSize ~= size or sb._fsFont ~= fontPath or sb._fsOutline ~= fontOutline then
			setFontWithFallback(sb.fs, fontPath, size, fontOutline)
			sb._fsSize = size
			sb._fsFont = fontPath
			sb._fsOutline = fontOutline
		end
		sb.fs:SetTextColor(fr, fg, fb, fa)
		if show then
			sb.fs:Show()
		else
			sb.fs:Hide()
		end
		if not sb._rbColorInitialized then
			if ResourceBars.SetStatusBarColorWithGradient then
				ResourceBars.SetStatusBarColorWithGradient(sb, cfg, readyR, readyG, readyB, readyA)
			else
				sb:SetStatusBarColor(readyR, readyG, readyB, readyA or 1)
			end
			sb._rbColorInitialized = true
		elseif ResourceBars.RefreshStatusBarGradient then
			ResourceBars.RefreshStatusBarGradient(sb, cfg)
		end
	end
end

local function createPowerBar(type, anchor)
	-- Reuse existing bar if present; avoid destroying frames to preserve anchors
	local bar = powerbar[type] or _G["EQOL" .. type .. "Bar"]
	if not bar then bar = CreateFrame("StatusBar", "EQOL" .. type .. "Bar", UIParent, "BackdropTemplate") end
	-- Ensure a valid parent when reusing frames after disable
	if bar:GetParent() ~= UIParent then bar:SetParent(UIParent) end

	-- Refresh bar immediately when it becomes visible (e.g. combat show via StateDriver)
	if type ~= "RUNES" and not bar._rbRefreshOnShow then
		bar:HookScript("OnShow", function(self)
			-- Force re-read of max (fixes “cap changed while hidden”)
			self._lastMax = nil
			self._lastMaxRaw = nil

			updatePowerBar(self._rbType)

			if ResourceBars.separatorEligible and ResourceBars.separatorEligible[self._rbType] then updateBarSeparators(self._rbType) end
			updateBarThresholds(self._rbType)
		end)
		bar._rbRefreshOnShow = true
	end

	local settings = getBarSettings(type)
	local w = max(RB.MIN_RESOURCE_BAR_WIDTH, (settings and settings.width) or RB.DEFAULT_POWER_WIDTH)
	local h = settings and settings.height or RB.DEFAULT_POWER_HEIGHT
	bar._cfg = settings
	bar._rbType = type
	powerbar[type] = bar
	local defaultStyle = (type == "MANA" or type == "STAGGER") and "PERCENT" or "CURMAX"
	bar._style = settings and settings.textStyle or defaultStyle
	bar:SetSize(w, h)
	do
		local cfg2 = getBarSettings(type) or {}
		bar:SetStatusBarTexture(resolveTexture(cfg2))
		configureSpecialTexture(bar, type, cfg2)
	end
	bar:SetClampedToScreen(true)
	local stackSpacing = RB.DEFAULT_STACK_SPACING

	-- Anchor handling: during spec/trait refresh we suppress inter-bar anchoring
	local a = getAnchor(type, addon.variables.unitSpec)
	if ResourceBars._suspendAnchors then
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", a.x or 0, a.y or 0)
	else
		if a.point then
			if
				a.autoSpacing
				or (a.autoSpacing == nil and isEQOLFrameName(a.relativeFrame) and (a.point or "TOPLEFT") == "TOPLEFT" and (a.relativePoint or "BOTTOMLEFT") == "BOTTOMLEFT" and (a.x or 0) == 0)
			then
				a.x = 0
				a.y = stackSpacing
				a.autoSpacing = true
			end
			local rel, looped = resolveAnchor(a, type)
			if looped and (a.relativeFrame or "UIParent") ~= "UIParent" then
				-- Loop fallback: recenter on UIParent
				local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
				local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
				a.point = "TOPLEFT"
				a.relativeFrame = "UIParent"
				a.relativePoint = "TOPLEFT"
				a.x = (pw - w) / 2
				a.y = (h - ph) / 2
				a.autoSpacing = nil
				rel = UIParent
			end
			bar:ClearAllPoints()
			bar:SetPoint(a.point, rel or UIParent, a.relativePoint or a.point, a.x or 0, a.y or 0)
		elseif anchor then
			-- Default stack below provided anchor and persist default anchor in DB
			bar:ClearAllPoints()
			bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, stackSpacing)
			a.point = "TOPLEFT"
			a.relativeFrame = anchor:GetName() or "UIParent"
			a.relativePoint = "BOTTOMLEFT"
			a.x = 0
			a.y = stackSpacing
			a.autoSpacing = true
			if a.matchRelativeWidth == nil then a.matchRelativeWidth = true end
		else
			-- No anchor in DB and no previous anchor in code path; default: center on UIParent
			bar:ClearAllPoints()
			local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
			local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
			local cx = (pw - w) / 2
			local cy = (h - ph) / 2
			bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", cx, cy)
			a.point = "TOPLEFT"
			a.relativeFrame = "UIParent"
			a.relativePoint = "TOPLEFT"
			a.x = cx
			a.y = cy
		end
	end

	-- Visuals and text
	applyBackdrop(bar, settings)
	if type ~= "RUNES" then applyBarFillColor(bar, settings, type) end

	if type == "RUNES" then
		if bar.text then
			bar.text:SetText("")
			bar.text:Hide()
		end
		-- Hide parent statusbar texture; we render child rune bars
		local tex = bar:GetStatusBarTexture()
		if tex then tex:SetAlpha(0) end
		layoutRunes(bar)
	elseif type == "ESSENCE" then
		if not bar.text then bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
		applyFontToString(bar.text, settings)
		applyTextPosition(bar, settings, 3, 0)
		bar.text:Show()
		-- Hide parent statusbar texture; we render segmented essence bars
		local tex = bar:GetStatusBarTexture()
		if tex then tex:SetAlpha(0) end
		local count = POWER_ENUM and UnitPowerMax("player", POWER_ENUM.ESSENCE) or 0
		ResourceBars.LayoutEssences(bar, settings or {}, count, resolveTexture(settings or {}))
	else
		if not bar.text then bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
		applyFontToString(bar.text, settings)
		applyTextPosition(bar, settings, 3, 0)
		bar.text:Show()
	end
	if type == "RUNES" and not bar._runeVisibilityHooks then
		bar:HookScript("OnHide", function(self)
			self._pendingRuneRefresh = true
			deactivateRuneTicker(self)
		end)
		bar:HookScript("OnShow", function(self)
			self._pendingRuneRefresh = nil
			updatePowerBar("RUNES")
		end)
		bar._runeVisibilityHooks = true
	end
	if type == "ESSENCE" and not bar._essenceVisibilityHooks then
		bar:HookScript("OnHide", function(self) ResourceBars.DeactivateEssenceTicker(self) end)
		bar._essenceVisibilityHooks = true
	end
	if type == "RUNES" then
		bar:SetStatusBarColor(getPowerBarColor(type))
	elseif not (settings and (settings.useBarColor == true or settings.useClassColor == true)) then
		local dr, dg, db = getPowerBarColor(type)
		local alpha = (settings and settings.barColor and settings.barColor[4]) or 1
		bar:SetStatusBarColor(dr, dg, db, alpha)
	end
	configureBarBehavior(bar, settings, type)

	-- Dragging disabled outside Edit Mode; positioning handled via Edit Mode
	bar:SetMovable(false)
	bar:EnableMouse(shouldEnableBarMouse(settings))
	bar:Show()
	if type == "RUNES" then ResourceBars.ForceRuneRecolor() end
	updatePowerBar(type)
	if type == "RUNES" then
		updateBarSeparators("RUNES")
	elseif ResourceBars.separatorEligible[type] then
		updateBarSeparators(type)
	end
	updateBarThresholds(type)

	-- Ensure dependents re-anchor when this bar changes size
	bar:SetScript("OnSizeChanged", function()
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorDependentsOf then addon.Aura.ResourceBars.ReanchorDependentsOf("EQOL" .. type .. "Bar") end
		if type == "RUNES" then
			layoutRunes(bar)
			updateBarSeparators("RUNES")
		elseif type == "ESSENCE" then
			local cfg = getBarSettings("ESSENCE") or {}
			local count = POWER_ENUM and UnitPowerMax("player", POWER_ENUM.ESSENCE) or 0
			ResourceBars.LayoutEssences(bar, cfg, count, resolveTexture(cfg))
			if ResourceBars.separatorEligible[type] then updateBarSeparators(type) end
		elseif ResourceBars.separatorEligible[type] then
			updateBarSeparators(type)
		end
		updateBarThresholds(type)
	end)

	if ResourceBars and ResourceBars.SyncRelativeFrameWidths then ResourceBars.SyncRelativeFrameWidths() end
	if ensureEditModeRegistration then ensureEditModeRegistration() end
end

RB.EVENTS_TO_REGISTER = {
	"UNIT_HEALTH",
	"UNIT_MAXHEALTH",
	"UNIT_ABSORB_AMOUNT_CHANGED",
	"UNIT_POWER_UPDATE",
	"UNIT_POWER_FREQUENT",
	"UNIT_DISPLAYPOWER",
	"UNIT_MAXPOWER",
	"UPDATE_SHAPESHIFT_FORM",
}
local function classUsesAuraPowers(class)
	local classTbl = powertypeClasses and powertypeClasses[class]
	if not classTbl then return false end

	for _, specInfo in pairs(classTbl) do
		if type(specInfo) == "table" then
			for pType in pairs(RB.AURA_POWER_CONFIG or {}) do
				if specInfo.MAIN == pType or specInfo[pType] then return true end
			end
		end
	end
	return false
end

local function classNeedsUnitAura(class) return classUsesAuraPowers(class) or class == "MONK" end

if classNeedsUnitAura(addon.variables.unitClass) then table.insert(RB.EVENTS_TO_REGISTER, "UNIT_AURA") end
local function setPowerbars(opts)
	local _, powerToken = UnitPowerType("player")
	powerfrequent = {}
	local isDruid = addon.variables.unitClass == "DRUID"
	local editModeActive = addon.EditMode and addon.EditMode.IsInEditMode and addon.EditMode:IsInEditMode()
	opts = opts or {}
	local forceAllDruidBars = isDruid and ((opts.forceAllDruidBars == true) or editModeActive)
	local function currentDruidForm()
		if not isDruid then return nil end
		if GetShapeshiftFormID then
			local formID = GetShapeshiftFormID()
			local key = formIDToKey[formID]
			if key then return key end
		end
		local idx = GetShapeshiftForm() or 0
		local key = resolveFormKeyFromShapeshiftIndex(idx)
		if key then return key end
		key = formIndexToKey[idx]
		if key then return key end
		return "HUMANOID"
	end
	local druidForm = currentDruidForm()
	local mainPowerBar
	local lastBar
	local specCfg = ensureSpecCfg(addon.variables.unitSpec)

	local desiredVisibility = {}

	if
		powertypeClasses[addon.variables.unitClass]
		and powertypeClasses[addon.variables.unitClass][addon.variables.unitSpec]
		and powertypeClasses[addon.variables.unitClass][addon.variables.unitSpec].MAIN
	then
		local mType = powertypeClasses[addon.variables.unitClass][addon.variables.unitSpec].MAIN
		local enabledMain = specCfg and specCfg[mType] and specCfg[mType].enabled == true
		if enabledMain then
			createPowerBar(mType, ((specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true) and EQOLHealthBar or nil))
			mainPowerBar = mType
			lastBar = mainPowerBar
		end
		desiredVisibility[mType] = enabledMain
	end

	for _, pType in ipairs(classPowerTypes) do
		local showBar = false
		local shouldShow = false
		if specCfg and specCfg[pType] and specCfg[pType].enabled == true then
			if mainPowerBar == pType then
				shouldShow = true
			elseif
				powertypeClasses[addon.variables.unitClass]
				and powertypeClasses[addon.variables.unitClass][addon.variables.unitSpec]
				and powertypeClasses[addon.variables.unitClass][addon.variables.unitSpec][pType]
			then
				shouldShow = true
			end
		end

		if shouldShow then
			-- Per-form filter for Druid
			local formAllowed = true
			local barCfg = specCfg and specCfg[pType]
			local delegateFormsToDriver = barCfg and ResourceBars.ShouldUseDruidFormDriver(barCfg)
			if isDruid and barCfg and barCfg.showForms and not delegateFormsToDriver then
				local allowed = barCfg.showForms
				if druidForm and allowed[druidForm] == false then formAllowed = false end
			end
			if forceAllDruidBars then formAllowed = true end
			if formAllowed and addon.variables.unitClass == "DRUID" then
				if RB.FREQUENT_POWER_TYPES[pType] then powerfrequent[pType] = true end
				if forceAllDruidBars then
					if mainPowerBar ~= pType then
						createPowerBar(pType, powerbar[lastBar] or ((specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true) and EQOLHealthBar or nil))
						lastBar = pType
					end
					showBar = true
				elseif pType == mainPowerBar then
					showBar = true
				elseif pType == "MANA" then
					createPowerBar(pType, powerbar[lastBar] or ((specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true) and EQOLHealthBar or nil))
					lastBar = pType
					showBar = true
				elseif pType == "COMBO_POINTS" and druidForm == "CAT" then
					createPowerBar(pType, powerbar[lastBar] or ((specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true) and EQOLHealthBar or nil))
					lastBar = pType
					showBar = true
				elseif powerToken == pType and powerToken ~= mainPowerBar then
					createPowerBar(pType, powerbar[lastBar] or ((specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true) and EQOLHealthBar or nil))
					lastBar = pType
					showBar = true
				end
			elseif formAllowed then
				if RB.FREQUENT_POWER_TYPES[pType] then powerfrequent[pType] = true end
				if mainPowerBar ~= pType then
					createPowerBar(pType, powerbar[lastBar] or ((specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true) and EQOLHealthBar or nil))
					lastBar = pType
				end
				showBar = true
			end
		end

		desiredVisibility[pType] = showBar
	end

	for pType, wantVisible in pairs(desiredVisibility) do
		local bar = powerbar[pType]
		if bar then
			if wantVisible then
				if not bar:IsShown() then bar:Show() end
			else
				if bar:IsShown() then bar:Hide() end
			end
		end
	end

	-- Toggle Health visibility according to config
	if healthBar then
		local showHealth = specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true
		if showHealth then
			if not healthBar:IsShown() then healthBar:Show() end
		else
			if healthBar:IsShown() then healthBar:Hide() end
		end
	end

	if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ApplyVisibilityPreference then addon.Aura.ResourceBars.ApplyVisibilityPreference("fromSetPowerbars") end
	if ResourceBars and ResourceBars.SyncRelativeFrameWidths then ResourceBars.SyncRelativeFrameWidths() end
end
addon.Aura.functions.setPowerBars = setPowerbars

local function forEachResourceBarFrame(callback)
	if type(callback) ~= "function" then return end
	if healthBar then callback(healthBar, "HEALTH") end
	for pType, bar in pairs(powerbar) do
		if bar then callback(bar, pType) end
	end
end

local function resolveBarConfigForFrame(pType, frame)
	local cfg = getBarSettings(pType)
	if not cfg and frame and frame._cfg then cfg = frame._cfg end
	return cfg
end

local function buildDruidVisibilityExpression(cfg, hideOutOfCombat, formStanceMap)
	if not shouldUseDruidFormDriver(cfg) then return nil end
	local showForms = cfg.showForms
	local clauses = {}
	local seen = {}
	local function appendClause(formCondition)
		local cond = formCondition
		if hideOutOfCombat then
			if cond and cond ~= "" then
				cond = "combat," .. cond
			else
				cond = "combat"
			end
		end
		if cond and cond ~= "" then
			local clause = ("[%s] show"):format(cond)
			if not seen[clause] then
				seen[clause] = true
				clauses[#clauses + 1] = clause
			end
		end
	end

	if showForms.HUMANOID ~= false then
		appendClause("nostance")
		for _, idx in ipairs((formStanceMap and formStanceMap.HUMANOID) or {}) do
			if idx and idx > 0 then appendClause("stance:" .. idx) end
		end
	end
	for i = 2, #DRUID_FORM_SEQUENCE do
		local key = DRUID_FORM_SEQUENCE[i]
		if showForms[key] ~= false then
			local indices = formStanceMap and formStanceMap[key]
			if indices and #indices > 0 then
				for _, idx in ipairs(indices) do
					if idx and idx > 0 then appendClause("stance:" .. idx) end
				end
			else
				local idx = formKeyToIndex[key]
				if idx and idx > 0 then appendClause("stance:" .. idx) end
			end
		end
	end
	if #clauses == 0 then return "hide" end
	clauses[#clauses + 1] = "hide"
	return table.concat(clauses, "; ")
end

local function buildVisibilityDriverForBar(cfg)
	local hideOOC = ResourceBars.ShouldHideOutOfCombat and ResourceBars.ShouldHideOutOfCombat()
	local hideMounted = ResourceBars.ShouldHideMounted and ResourceBars.ShouldHideMounted()
	local hideVehicle = ResourceBars.ShouldHideInVehicle and ResourceBars.ShouldHideInVehicle()
	local hidePetBattle = ResourceBars.ShouldHideInPetBattle and ResourceBars.ShouldHideInPetBattle()
	cfg = cfg or {}
	local formStanceMap = addon.variables.unitClass == "DRUID" and getDruidFormStanceMap() or nil
	local druidExpr = buildDruidVisibilityExpression(cfg, hideOOC, formStanceMap)
	if not hideOOC and not hideMounted and not hideVehicle and not hidePetBattle and not druidExpr then return nil, false end

	local clauses = {}
	if hidePetBattle then clauses[#clauses + 1] = "[petbattle] hide" end
	if hideVehicle then clauses[#clauses + 1] = "[vehicleui] hide" end
	if hideMounted then
		clauses[#clauses + 1] = "[mounted] hide"
		if addon.variables.unitClass == "DRUID" then
			local travelIdx = (formStanceMap and formStanceMap.TRAVEL and formStanceMap.TRAVEL[1]) or formKeyToIndex.TRAVEL
			if travelIdx and travelIdx > 0 then clauses[#clauses + 1] = ("[stance:%d] hide"):format(travelIdx) end
			local stagIdx = (formStanceMap and formStanceMap.STAG and formStanceMap.STAG[1]) or formKeyToIndex.STAG
			if stagIdx and stagIdx > 0 then clauses[#clauses + 1] = ("[stance:%d] hide"):format(stagIdx) end
		end
	end

	if druidExpr then
		clauses[#clauses + 1] = druidExpr
	elseif hideOOC then
		clauses[#clauses + 1] = RB.OOC_VISIBILITY_DRIVER
	else
		clauses[#clauses + 1] = "show"
	end

	return table.concat(clauses, "; "), druidExpr ~= nil
end

local function ensureVisibilityDriverWatcher()
	if visibilityDriverWatcher then return end
	visibilityDriverWatcher = CreateFrame("Frame")
	visibilityDriverWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	visibilityDriverWatcher:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
	if visibilityDriverWatcher.RegisterUnitEvent then
		visibilityDriverWatcher:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
		visibilityDriverWatcher:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
	else
		visibilityDriverWatcher:RegisterEvent("UNIT_ENTERED_VEHICLE")
		visibilityDriverWatcher:RegisterEvent("UNIT_EXITED_VEHICLE")
	end
	visibilityDriverWatcher._playerMounted = IsMounted and IsMounted() or false
	visibilityDriverWatcher._playerVehicle = UnitInVehicle and UnitInVehicle("player") or false
	visibilityDriverWatcher:SetScript("OnEvent", function(self, event, unit)
		if event == "PLAYER_REGEN_ENABLED" then
			if ResourceBars._pendingVisibilityDriver then
				ResourceBars._pendingVisibilityDriver = nil
				ResourceBars.ApplyVisibilityPreference("pending")
			end
			local pendingUpdates = ResourceBars._pendingVisibilityDriverUpdates
			if pendingUpdates then
				ResourceBars._pendingVisibilityDriverUpdates = nil
				for frame, expr in pairs(pendingUpdates) do
					if frame then
						local desired = expr
						if desired == false then desired = nil end
						applyVisibilityDriverToFrame(frame, desired)
					end
				end
			end
			return
		end

		if event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
			if not (ResourceBars.ShouldHideMounted and ResourceBars.ShouldHideMounted()) and not (ResourceBars.ShouldHideInVehicle and ResourceBars.ShouldHideInVehicle()) then return end
			local mounted = IsMounted and IsMounted() or false
			if not ResourceBars._pendingVisibilityDriver and self._playerMounted == mounted then return end
			self._playerMounted = mounted
		elseif event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
			if unit and unit ~= "player" then return end
			if not (ResourceBars.ShouldHideInVehicle and ResourceBars.ShouldHideInVehicle()) then return end
			local inVehicle = UnitInVehicle and UnitInVehicle("player") or false
			if not ResourceBars._pendingVisibilityDriver and self._playerVehicle == inVehicle then return end
			self._playerVehicle = inVehicle
		else
			return
		end

		ResourceBars.ApplyVisibilityPreference(event)
	end)
end

local function canApplyVisibilityDriver()
	if InCombatLockdown and InCombatLockdown() then
		ResourceBars._pendingVisibilityDriver = true
		ensureVisibilityDriverWatcher()
		return false
	end
	return true
end

function applyVisibilityDriverToFrame(frame, expression)
	if not frame then return end
	if InCombatLockdown and InCombatLockdown() then
		ResourceBars._pendingVisibilityDriverUpdates = ResourceBars._pendingVisibilityDriverUpdates or {}
		ResourceBars._pendingVisibilityDriverUpdates[frame] = expression == nil and false or expression
		ensureVisibilityDriverWatcher()
		return
	end
	if not expression then
		if frame._rbVisibilityDriver then
			if UnregisterStateDriver then pcall(UnregisterStateDriver, frame, "visibility") end
			frame._rbVisibilityDriver = nil
		end
		return
	end
	if frame._rbVisibilityDriver == expression then return end
	if RegisterStateDriver then
		local ok = pcall(RegisterStateDriver, frame, "visibility", expression)
		if ok then frame._rbVisibilityDriver = expression end
	end
end

function ResourceBars.ApplyVisibilityPreference(context)
	if not RegisterStateDriver or not UnregisterStateDriver then return end
	local canApplyDriver = canApplyVisibilityDriver()
	if canApplyDriver then ResourceBars._pendingVisibilityDriver = nil end
	local barsEnabled = not (addon and addon.db and addon.db.enableResourceFrame == false)
	local editModeActive = addon.EditMode and addon.EditMode.IsInEditMode and addon.EditMode:IsInEditMode()
	local hideInClientScene = not editModeActive and ResourceBars.ShouldHideInClientScene and ResourceBars.ShouldHideInClientScene() and ResourceBars._clientSceneOpen == true
	local driverWasActive = ResourceBars._visibilityDriverActive == true
	if not barsEnabled then
		forEachResourceBarFrame(function(frame)
			if canApplyDriver then applyVisibilityDriverToFrame(frame, nil) end
			if frame then frame._rbDruidFormDriver = nil end
			if ResourceBars.ApplyClientSceneAlphaToFrame then ResourceBars.ApplyClientSceneAlphaToFrame(frame, false) end
		end)
		if canApplyDriver then
			ResourceBars._visibilityDriverActive = false
		else
			ResourceBars._visibilityDriverActive = driverWasActive
		end
		return
	end
	local driverActiveNow = false
	forEachResourceBarFrame(function(frame, pType)
		local cfg = resolveBarConfigForFrame(pType, frame)
		local barEnabled = cfg and cfg.enabled == true
		if barEnabled then
			if editModeActive then
				if canApplyDriver then applyVisibilityDriverToFrame(frame, "show") end
				frame._rbDruidFormDriver = nil
				driverActiveNow = true
			else
				local expr, hasDruidRule = buildVisibilityDriverForBar(cfg)
				if expr then driverActiveNow = true end
				if canApplyDriver then applyVisibilityDriverToFrame(frame, expr) end
				frame._rbDruidFormDriver = hasDruidRule or nil
			end
			if ResourceBars.ApplyClientSceneAlphaToFrame then ResourceBars.ApplyClientSceneAlphaToFrame(frame, hideInClientScene) end
		else
			if canApplyDriver then applyVisibilityDriverToFrame(frame, nil) end
			if frame then frame._rbDruidFormDriver = nil end
			if ResourceBars.ApplyClientSceneAlphaToFrame then ResourceBars.ApplyClientSceneAlphaToFrame(frame, false) end
		end
	end)
	if canApplyDriver then
		ResourceBars._visibilityDriverActive = driverActiveNow
		if driverWasActive and not driverActiveNow and context ~= "fromSetPowerbars" and frameAnchor then setPowerbars() end
	else
		ResourceBars._visibilityDriverActive = driverWasActive
	end
end

local resourceBarsLoaded = addon.Aura.ResourceBars ~= nil
local function LoadResourceBars()
	if not resourceBarsLoaded then
		addon.Aura.ResourceBars = addon.Aura.ResourceBars or {}
		resourceBarsLoaded = true
	end
end

local function wipeTable(t)
	for k in pairs(t) do
		t[k] = nil
	end
end

-- Coalesce spec/trait refreshes to avoid duplicate work or timing races
local function scheduleSpecRefresh()
	if frameAnchor and frameAnchor._specRefreshScheduled then return end
	if frameAnchor then frameAnchor._specRefreshScheduled = true end
	After(0.2, function()
		if frameAnchor then frameAnchor._specRefreshScheduled = false end
		-- First detach all bar points to avoid transient loops
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.DetachAllBars then addon.Aura.ResourceBars.DetachAllBars() end
		ResourceBars._suspendAnchors = true
		setPowerbars()
		ResourceBars._suspendAnchors = false
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorAll then addon.Aura.ResourceBars.ReanchorAll() end
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ForceRuneRecolor then addon.Aura.ResourceBars.ForceRuneRecolor() end
		if addon.variables.unitClass == "DEATHKNIGHT" then updatePowerBar("RUNES") end
	end)
end

local function updateStaggerBarIfShown()
	if powerbar["STAGGER"] and powerbar["STAGGER"]:IsShown() then updatePowerBar("STAGGER") end
end

local function eventHandler(self, event, unit, arg1)
	if event == "UNIT_DISPLAYPOWER" and unit == "player" then
		setPowerbars()
	elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
		scheduleSpecRefresh()
		if scheduleRelativeFrameWidthSync then scheduleRelativeFrameWidthSync() end
	elseif event == "TRAIT_CONFIG_UPDATED" then
		scheduleSpecRefresh()
		if scheduleRelativeFrameWidthSync then scheduleRelativeFrameWidthSync() end
	elseif event == "CLIENT_SCENE_OPENED" then
		local sceneType = unit
		ResourceBars._clientSceneOpen = (sceneType == 1)
		ResourceBars.ApplyVisibilityPreference(event)
		return
	elseif event == "CLIENT_SCENE_CLOSED" then
		ResourceBars._clientSceneOpen = false
		ResourceBars.ApplyVisibilityPreference(event)
		return
	elseif event == "PLAYER_ENTERING_WORLD" then
		updateHealthBar("UNIT_ABSORB_AMOUNT_CHANGED")
		setPowerbars()
		if After then After(0, function()
			for pType, _ in pairs(RB.AURA_POWER_CONFIG or {}) do
				if powerbar[pType] and powerbar[pType]:IsShown() then updatePowerBar(pType) end
			end
		end) end
		if scheduleRelativeFrameWidthSync then scheduleRelativeFrameWidthSync() end
	elseif event == "UPDATE_SHAPESHIFT_FORM" then
		setPowerbars()
		-- After initial creation, run a re-anchor pass to ensure all dependent anchors resolve
		if After then
			After(0.05, function()
				if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorAll then addon.Aura.ResourceBars.ReanchorAll() end
				if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
			end)
		else
			if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorAll then addon.Aura.ResourceBars.ReanchorAll() end
			if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
		end
	elseif event == "UNIT_AURA" and unit == "player" then
		local info = arg1

		if not info or info.isFullUpdate then
			resetAuraTracking()
			for pType, _ in pairs(RB.AURA_POWER_CONFIG or {}) do
				if powerbar[pType] and powerbar[pType]:IsShown() then updatePowerBar(pType) end
			end
			updateStaggerBarIfShown()
			return
		end

		local changed = handleAuraEventInfo(info)
		if changed then
			for pType in pairs(changed) do
				if powerbar[pType] and powerbar[pType]:IsShown() then updatePowerBar(pType) end
			end
		end
		updateStaggerBarIfShown()
		return
	elseif event == "UNIT_MAXHEALTH" or event == "UNIT_HEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
		if healthBar and healthBar:IsShown() then
			if event == "UNIT_MAXHEALTH" then
				local max = UnitHealthMax("player")
				healthBar._lastMax = max
				healthBar:SetMinMaxValues(0, max)
			end
			updateHealthBar(event)
		end
		updateStaggerBarIfShown()
	elseif event == "UNIT_POWER_UPDATE" and powerbar[arg1] and powerbar[arg1]:IsShown() and not powerfrequent[arg1] then
		updatePowerBar(arg1)
	elseif event == "UNIT_POWER_FREQUENT" and powerbar[arg1] and powerbar[arg1]:IsShown() and powerfrequent[arg1] then
		updatePowerBar(arg1)
	elseif event == "UNIT_MAXPOWER" and powerbar[arg1] and powerbar[arg1]:IsShown() then
		local enum = POWER_ENUM[arg1]
		local bar = powerbar[arg1]
		if enum and bar then
			local max = UnitPowerMax("player", enum)
			bar._lastMax = max
			bar:SetMinMaxValues(0, max)
		end
		updatePowerBar(arg1)
		if ResourceBars.separatorEligible[arg1] then updateBarSeparators(arg1) end
	elseif event == "RUNE_POWER_UPDATE" then
		-- payload: runeIndex, isEnergize -> first vararg is held in 'unit' here
		if powerbar["RUNES"] and powerbar["RUNES"]:IsShown() then updatePowerBar("RUNES", unit) end
	end
end

function ResourceBars.EnableResourceBars()
	if not frameAnchor then
		frameAnchor = CreateFrame("Frame")
		addon.Aura.anchorFrame = frameAnchor
	end
	for _, event in ipairs(RB.EVENTS_TO_REGISTER) do
		-- Register unit vs non-unit events correctly
		if event == "UPDATE_SHAPESHIFT_FORM" then
			frameAnchor:RegisterEvent(event)
		else
			frameAnchor:RegisterUnitEvent(event, "player")
		end
	end
	frameAnchor:RegisterEvent("PLAYER_ENTERING_WORLD")
	frameAnchor:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
	frameAnchor:RegisterEvent("TRAIT_CONFIG_UPDATED")
	frameAnchor:RegisterEvent("CLIENT_SCENE_OPENED")
	frameAnchor:RegisterEvent("CLIENT_SCENE_CLOSED")
	frameAnchor:SetScript("OnEvent", eventHandler)
	frameAnchor:Hide()

	createHealthBar()
	-- Build bars and anchor immediately; no deferred timers needed
	if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.Refresh then
		addon.Aura.ResourceBars.Refresh()
	else
		if setPowerbars then setPowerbars() end
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorAll then addon.Aura.ResourceBars.ReanchorAll() end
	end
	if addon.variables and addon.variables.unitClass == "DRUID" and setPowerbars then
		setPowerbars({ forceAllDruidBars = true })
		setPowerbars()
	end
	if ResourceBars and ResourceBars.SyncRelativeFrameWidths then ResourceBars.SyncRelativeFrameWidths() end
	if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
	if ensureEditModeRegistration then ensureEditModeRegistration() end
end

function ResourceBars.DisableResourceBars()
	ResourceBars._clientSceneOpen = false
	if frameAnchor then
		frameAnchor:UnregisterAllEvents()
		frameAnchor:SetScript("OnEvent", nil)
		frameAnchor = nil
		addon.Aura.anchorFrame = nil
	end
	if mainFrame then
		applyVisibilityDriverToFrame(mainFrame, nil)
		mainFrame:Hide()
		-- Keep parent to preserve frame and anchors for reuse
		mainFrame = nil
	end
	if healthBar then
		applyVisibilityDriverToFrame(healthBar, nil)
		if healthBar.absorbBar then
			local absorbBar = healthBar.absorbBar
			absorbBar:SetMinMaxValues(0, 1)
			absorbBar:SetValue(0)
			absorbBar._lastVal = 0
			absorbBar._lastMax = 1
		end
		healthBar._lastMax = nil
		healthBar._lastValue = nil
		healthBar:Hide()
		-- Keep parent to preserve frame and anchors for reuse
		healthBar = nil
	end
	for pType, bar in pairs(powerbar) do
		if bar then
			applyVisibilityDriverToFrame(bar, nil)
			bar._rbDruidFormDriver = nil
			bar:Hide()
			if pType == "RUNES" then deactivateRuneTicker(bar) end
		end
		powerbar[pType] = nil
	end
	powerbar = {}
end

-- Register/unregister DK rune event depending on class and user config
function ResourceBars.UpdateRuneEventRegistration()
	if not frameAnchor then return end
	local isDK = addon.variables.unitClass == "DEATHKNIGHT"
	local spec = addon.variables.unitSpec
	local cfg = addon.db.personalResourceBarSettings and addon.db.personalResourceBarSettings[addon.variables.unitClass] and addon.db.personalResourceBarSettings[addon.variables.unitClass][spec]
	local enabled = isDK and cfg and cfg.RUNES and (cfg.RUNES.enabled == true)
	if enabled and not frameAnchor._runeEvtRegistered then
		frameAnchor:RegisterEvent("RUNE_POWER_UPDATE")
		frameAnchor._runeEvtRegistered = true
	elseif (not enabled) and frameAnchor._runeEvtRegistered then
		frameAnchor:UnregisterEvent("RUNE_POWER_UPDATE")
		frameAnchor._runeEvtRegistered = false
		if powerbar and powerbar.RUNES then deactivateRuneTicker(powerbar.RUNES) end
	end
end

-- Force a recolor of rune segments (used on spec change)
function ResourceBars.ForceRuneRecolor()
	local rb = powerbar and powerbar.RUNES
	if not rb or not rb.runes then return end
	-- Stop any stale ticker so the next update uses fresh spec colors.
	deactivateRuneTicker(rb)
	rb._runeUpdater = nil
	for i = 1, 6 do
		local sb = rb.runes[i]
		if sb then
			sb._isReady = nil
			sb._lastRemain = nil
		end
	end
end

-- Clear all points for current bars to break transient inter-bar dependencies
function ResourceBars.DetachAllBars()
	if healthBar then healthBar:ClearAllPoints() end
	for _, bar in pairs(powerbar) do
		if bar then bar:ClearAllPoints() end
	end
end

local function getFrameName(pType)
	if pType == "HEALTH" then return "EQOLHealthBar" end
	return "EQOL" .. pType .. "Bar"
end

local function frameNameToBarType(fname)
	if fname == "EQOLHealthBar" then return "HEALTH" end
	if type(fname) ~= "string" then return nil end
	return fname:match("^EQOL(.+)Bar$")
end

function ResourceBars.DetachAnchorsFrom(disabledType, specIndex)
	local class = addon.variables.unitClass
	local spec = specIndex or addon.variables.unitSpec

	if not addon.db.personalResourceBarSettings or not addon.db.personalResourceBarSettings[class] or not addon.db.personalResourceBarSettings[class][spec] then return end

	local specCfg = addon.db.personalResourceBarSettings[class][spec]
	local targetName = getFrameName(disabledType)
	local disabledAnchor = getAnchor(disabledType, spec)
	local upstreamName = disabledAnchor and disabledAnchor.relativeFrame or "UIParent"

	for pType, cfg in pairs(specCfg) do
		if pType ~= disabledType and cfg.anchor and cfg.anchor.relativeFrame == targetName then
			local depFrame = _G[getFrameName(pType)]
			local upstream = _G[upstreamName]
			if upstreamName ~= "UIParent" and upstream then
				-- Reattach below the disabled bar's upstream anchor target for intuitive stacking
				cfg.anchor.point = "TOPLEFT"
				cfg.anchor.relativeFrame = upstreamName
				cfg.anchor.relativePoint = "BOTTOMLEFT"
				cfg.anchor.x = 0
				cfg.anchor.y = 0
			else
				-- Fallback to centered on UIParent (TOPLEFT/TOPLEFT offsets to center)
				local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
				local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
				-- Determine dependent frame size (fallback to defaults by bar type)
				local cfgDep = getBarSettings(pType)
				local defaultW = (pType == "HEALTH") and RB.DEFAULT_HEALTH_WIDTH or RB.DEFAULT_POWER_WIDTH
				local defaultH = (pType == "HEALTH") and RB.DEFAULT_HEALTH_HEIGHT or RB.DEFAULT_POWER_HEIGHT
				local w = (depFrame and depFrame.GetWidth and depFrame:GetWidth()) or (cfgDep and cfgDep.width) or defaultW or 0
				local h = (depFrame and depFrame.GetHeight and depFrame:GetHeight()) or (cfgDep and cfgDep.height) or defaultH or 0
				cfg.anchor.point = "TOPLEFT"
				cfg.anchor.relativeFrame = "UIParent"
				cfg.anchor.relativePoint = "TOPLEFT"
				cfg.anchor.x = (pw - w) / 2
				cfg.anchor.y = (h - ph) / 2
			end
		end
	end
end

function ResourceBars.SetHealthBarSize(w, h)
	local width = max(RB.MIN_RESOURCE_BAR_WIDTH, w or RB.DEFAULT_HEALTH_WIDTH)
	local height = h or RB.DEFAULT_HEALTH_HEIGHT
	if healthBar then healthBar:SetSize(width, height) end
	if ResourceBars and ResourceBars.SyncRelativeFrameWidths then ResourceBars.SyncRelativeFrameWidths() end
end

function ResourceBars.SetPowerBarSize(w, h, pType)
	local changed = {}
	-- Ensure sane defaults if nil provided
	if pType then
		local s = getBarSettings(pType)
		local defaultW = RB.DEFAULT_POWER_WIDTH
		local defaultH = RB.DEFAULT_POWER_HEIGHT
		w = max(RB.MIN_RESOURCE_BAR_WIDTH, w or (s and s.width) or defaultW)
		h = h or (s and s.height) or defaultH
	end
	if pType then
		if powerbar[pType] then
			powerbar[pType]:SetSize(w, h)
			changed[getFrameName(pType)] = true
		end
	else
		local width = max(RB.MIN_RESOURCE_BAR_WIDTH, w or RB.DEFAULT_POWER_WIDTH)
		local height = h or RB.DEFAULT_POWER_HEIGHT
		for t, bar in pairs(powerbar) do
			bar:SetSize(width, height)
			changed[getFrameName(t)] = true
		end
	end

	local class = addon.variables.unitClass
	local spec = addon.variables.unitSpec
	local specCfg = addon.db.personalResourceBarSettings and addon.db.personalResourceBarSettings[class] and addon.db.personalResourceBarSettings[class][spec]

	if specCfg then
		for bType, cfg in pairs(specCfg) do
			if type(cfg) == "table" then
				local anchor = cfg.anchor
				if anchor and changed[anchor.relativeFrame] then
					local frame = bType == "HEALTH" and healthBar or powerbar[bType]
					if frame then
						local rel = ResourceBars.ResolveRelativeFrameByName(anchor.relativeFrame)
						-- Ensure we don't accumulate multiple points to stale relatives
						frame:ClearAllPoints()
						frame:SetPoint(anchor.point or "CENTER", rel, anchor.relativePoint or anchor.point or "CENTER", anchor.x or 0, anchor.y or 0)
					end
				end
			end
		end
	end
	if ResourceBars and ResourceBars.SyncRelativeFrameWidths then ResourceBars.SyncRelativeFrameWidths() end
end

-- Re-apply anchors for any bars that currently reference a given frame name
function ResourceBars.ReanchorDependentsOf(frameName)
	if ResourceBars._reanchoring then return end
	local class = addon.variables.unitClass
	local spec = addon.variables.unitSpec
	local specCfg = addon.db.personalResourceBarSettings and addon.db.personalResourceBarSettings[class] and addon.db.personalResourceBarSettings[class][spec]
	if not specCfg then return end

	for bType, cfg in pairs(specCfg) do
		if type(cfg) == "table" then
			local anch = cfg.anchor
			if anch and ResourceBars.RelativeFrameMatchesName(anch.relativeFrame, frameName) then
				local frame = (bType == "HEALTH") and healthBar or powerbar[bType]
				if frame then
					local rel = ResourceBars.ResolveRelativeFrameByName(anch.relativeFrame)
					frame:ClearAllPoints()
					frame:SetPoint(anch.point or "TOPLEFT", rel, anch.relativePoint or anch.point or "TOPLEFT", anch.x or 0, anch.y or 0)
				end
			end
		end
	end
end

function ResourceBars.Refresh()
	setPowerbars()
	-- Re-apply anchors so option changes take effect immediately
	if healthBar then
		local a = getAnchor("HEALTH", addon.variables.unitSpec)
		if (a.relativeFrame or "UIParent") == "UIParent" then
			a.point = a.point or "TOPLEFT"
			a.relativePoint = a.relativePoint or "TOPLEFT"
			if a.x == nil or a.y == nil then
				local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
				local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
				local w = healthBar:GetWidth() or RB.DEFAULT_HEALTH_WIDTH
				local h = healthBar:GetHeight() or RB.DEFAULT_HEALTH_HEIGHT
				a.x = (pw - w) / 2
				a.y = (h - ph) / 2
			end
		end
		local rel, looped = resolveAnchor(a, "HEALTH")
		if looped and (a.relativeFrame or "UIParent") ~= "UIParent" then
			local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
			local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
			local w = healthBar:GetWidth() or RB.DEFAULT_HEALTH_WIDTH
			local h = healthBar:GetHeight() or RB.DEFAULT_HEALTH_HEIGHT
			a.point = "TOPLEFT"
			a.relativeFrame = "UIParent"
			a.relativePoint = "TOPLEFT"
			a.x = (pw - w) / 2
			a.y = (h - ph) / 2
			rel = UIParent
		end
		-- Apply current texture selection to health bar
		local hCfg2 = getBarSettings("HEALTH") or {}
		local hTex = resolveTexture(hCfg2)
		healthBar:SetStatusBarTexture(hTex)
		configureSpecialTexture(healthBar, "HEALTH", hCfg2)
		if healthBar.absorbBar then healthBar.absorbBar:SetStatusBarTexture(hTex) end
		healthBar:ClearAllPoints()
		healthBar:SetPoint(a.point or "TOPLEFT", rel, a.relativePoint or a.point or "TOPLEFT", a.x or 0, a.y or 0)
	end
	for pType, bar in pairs(powerbar) do
		if bar then
			local a = getAnchor(pType, addon.variables.unitSpec)
			if (a.relativeFrame or "UIParent") == "UIParent" then
				a.point = a.point or "TOPLEFT"
				a.relativePoint = a.relativePoint or "TOPLEFT"
				if a.x == nil or a.y == nil then
					local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
					local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
					local w = bar:GetWidth() or RB.DEFAULT_POWER_WIDTH
					local h = bar:GetHeight() or RB.DEFAULT_POWER_HEIGHT
					a.x = (pw - w) / 2
					a.y = (h - ph) / 2
				end
			end
			if
				a.autoSpacing
				or (a.autoSpacing == nil and isEQOLFrameName(a.relativeFrame) and (a.point or "TOPLEFT") == "TOPLEFT" and (a.relativePoint or "BOTTOMLEFT") == "BOTTOMLEFT" and (a.x or 0) == 0)
			then
				a.x = 0
				a.y = RB.DEFAULT_STACK_SPACING
				a.autoSpacing = true
			end
			local rel, looped = resolveAnchor(a, pType)
			if looped and (a.relativeFrame or "UIParent") ~= "UIParent" then
				local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
				local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
				local w = bar:GetWidth() or RB.DEFAULT_POWER_WIDTH
				local h = bar:GetHeight() or RB.DEFAULT_POWER_HEIGHT
				a.point = "TOPLEFT"
				a.relativeFrame = "UIParent"
				a.relativePoint = "TOPLEFT"
				a.x = (pw - w) / 2
				a.y = (h - ph) / 2
				rel = UIParent
			end
			bar:ClearAllPoints()
			bar:SetPoint(a.point or "TOPLEFT", rel, a.relativePoint or a.point or "TOPLEFT", a.x or 0, a.y or 0)
			-- Update movability based on anchor target (only movable when relative to UIParent)
			local isUI = (a.relativeFrame or "UIParent") == "UIParent"
			local cfg = getBarSettings(pType)
			bar:SetMovable(isUI)
			bar:EnableMouse(shouldEnableBarMouse(cfg))

			bar._cfg = cfg
			local defaultStyle = (pType == "MANA" or pType == "STAGGER") and "PERCENT" or "CURMAX"
			bar._style = (cfg and cfg.textStyle) or defaultStyle

			if pType == "RUNES" then
				layoutRunes(bar)
				updatePowerBar("RUNES")
			elseif pType == "ESSENCE" then
				local count = POWER_ENUM and UnitPowerMax("player", POWER_ENUM.ESSENCE) or 0
				ResourceBars.LayoutEssences(bar, cfg or {}, count, resolveTexture(cfg or {}))
				updatePowerBar("ESSENCE")
			else
				updatePowerBar(pType)
			end
			if ResourceBars.separatorEligible[pType] then updateBarSeparators(pType) end
			updateBarThresholds(pType)
		end
	end
	-- Apply styling updates without forcing a full rebuild
	if healthBar then
		local hCfg = getBarSettings("HEALTH") or {}
		if hCfg.useMaxColor then
			SetColorCurvePoints(hCfg.maxColor or RB.WHITE)
		else
			SetColorCurvePoints()
		end
		wasMax = hCfg.useMaxColor == true
		healthBar._cfg = hCfg
		healthBar:SetStatusBarTexture(resolveTexture(hCfg))
		configureSpecialTexture(healthBar, "HEALTH", hCfg)
		applyBackdrop(healthBar, hCfg)
		if healthBar.text then applyFontToString(healthBar.text, hCfg) end
		applyTextPosition(healthBar, hCfg, 3, 0)
		configureBarBehavior(healthBar, hCfg, "HEALTH")
		if healthBar.absorbBar then
			local absorbBar = healthBar.absorbBar
			absorbBar:SetStatusBarTexture(resolveTexture({ barTexture = hCfg.absorbTexture or hCfg.barTexture }))
			if hCfg.verticalFill then
				absorbBar:SetOrientation("VERTICAL")
			else
				absorbBar:SetOrientation("HORIZONTAL")
			end
			local reverseAbsorb = hCfg.absorbReverseFill == true
			if hCfg.absorbOverfill then reverseAbsorb = false end
			if absorbBar.SetReverseFill then absorbBar:SetReverseFill(reverseAbsorb) end
			applyAbsorbLayout(healthBar, hCfg)
		end
	end

	for pType, bar in pairs(powerbar) do
		if bar then
			local cfg = getBarSettings(pType) or {}
			bar._cfg = cfg
			if pType == "RUNES" then
				bar:SetStatusBarTexture(resolveTexture(cfg))
				local tex = bar:GetStatusBarTexture()
				if tex then tex:SetAlpha(0) end
			elseif pType == "ESSENCE" then
				bar:SetStatusBarTexture(resolveTexture(cfg))
				local tex = bar:GetStatusBarTexture()
				if tex then tex:SetAlpha(0) end
			else
				bar:SetStatusBarTexture(resolveTexture(cfg))
				configureSpecialTexture(bar, pType, cfg)
			end
			applyBackdrop(bar, cfg)
			configureBarBehavior(bar, cfg, pType)
			if pType ~= "RUNES" then applyBarFillColor(bar, cfg, pType) end
			if pType ~= "RUNES" and bar.text then
				applyFontToString(bar.text, cfg)
				applyTextPosition(bar, cfg, 3, 0)
			end
			if pType == "RUNES" then
				layoutRunes(bar)
			elseif pType == "ESSENCE" then
				local count = POWER_ENUM and UnitPowerMax("player", POWER_ENUM.ESSENCE) or 0
				ResourceBars.LayoutEssences(bar, cfg or {}, count, resolveTexture(cfg or {}))
			end
			if pType ~= "RUNES" then updatePowerBar(pType) end
		end
	end
	if ResourceBars and ResourceBars.SyncRelativeFrameWidths then ResourceBars.SyncRelativeFrameWidths() end
	updateHealthBar("UNIT_ABSORB_AMOUNT_CHANGED")
	if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
	-- Ensure RUNES animation stops when not visible/enabled
	local rcfg = getBarSettings("RUNES")
	local runesEnabled = rcfg and (rcfg.enabled == true)
	if powerbar and powerbar.RUNES and (not powerbar.RUNES:IsShown() or not runesEnabled) then deactivateRuneTicker(powerbar.RUNES) end
	-- Ensure ESSENCE animation stops when not visible/enabled
	local ecfg = getBarSettings("ESSENCE")
	local essenceEnabled = ecfg and (ecfg.enabled == true)
	if powerbar and powerbar.ESSENCE and (not powerbar.ESSENCE:IsShown() or not essenceEnabled) then ResourceBars.DeactivateEssenceTicker(powerbar.ESSENCE) end
end

ResourceBars._pendingRefresh = ResourceBars._pendingRefresh or {}

function ResourceBars.QueueRefresh(specIndex, opts)
	local spec = specIndex or addon.variables.unitSpec
	if not spec then return end
	local now = GetTime and GetTime() or 0
	local mode = (opts and opts.reanchorOnly) and "reanchor" or "full"
	local pending = ResourceBars._pendingRefresh
	local entry = pending[spec]
	if not entry then
		entry = { mode = mode, nextRunAt = now + RB.REFRESH_DEBOUNCE }
		pending[spec] = entry
	else
		if entry.mode ~= "full" and mode == "full" then entry.mode = "full" end
		entry.nextRunAt = now + RB.REFRESH_DEBOUNCE
	end
	if not After then
		pending[spec] = nil
		if spec ~= addon.variables.unitSpec then return end
		if entry.mode == "full" then
			ResourceBars.Refresh()
		else
			ResourceBars.ReanchorAll()
		end
		return
	end
	if entry.timerActive then return end
	entry.timerActive = true

	local function pump()
		local current = pending[spec]
		if not current then return end
		local target = current.nextRunAt or 0
		local nowTime = GetTime and GetTime() or target
		if nowTime < target then
			local delay = target - nowTime
			if delay < 0.01 then delay = 0.01 end
			After(delay, pump)
			return
		end
		current.timerActive = nil
		pending[spec] = nil
		if spec ~= addon.variables.unitSpec then return end
		if current.mode == "full" then
			ResourceBars.Refresh()
		else
			ResourceBars.ReanchorAll()
		end
	end

	local initialDelay = entry.nextRunAt - now
	if initialDelay < 0.01 then initialDelay = 0.01 end
	After(initialDelay, pump)
end

-- Only refresh live bars when editing the active spec
function ResourceBars.MaybeRefreshActive(specIndex)
	if specIndex ~= addon.variables.unitSpec then return end
	if ResourceBars.QueueRefresh then
		ResourceBars.QueueRefresh(specIndex)
	else
		ResourceBars.Refresh()
	end
end

-- Re-anchor pass only: reapplies anchor points without rebuilding bars
function ResourceBars.ReanchorAll()
	if ResourceBars._reanchoring then return end
	ResourceBars._reanchoring = true
	-- Health first
	if healthBar then
		local a = getAnchor("HEALTH", addon.variables.unitSpec)
		if (a.relativeFrame or "UIParent") == "UIParent" then
			a.point = a.point or "TOPLEFT"
			a.relativePoint = a.relativePoint or "TOPLEFT"
			if a.x == nil or a.y == nil then
				local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
				local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
				local w = healthBar:GetWidth() or RB.DEFAULT_HEALTH_WIDTH
				local h = healthBar:GetHeight() or RB.DEFAULT_HEALTH_HEIGHT
				a.x = (pw - w) / 2
				a.y = (h - ph) / 2
			end
		end
		local rel, looped = resolveAnchor(a, "HEALTH")
		if looped and (a.relativeFrame or "UIParent") ~= "UIParent" then
			local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
			local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
			local w = healthBar:GetWidth() or RB.DEFAULT_HEALTH_WIDTH
			local h = healthBar:GetHeight() or RB.DEFAULT_HEALTH_HEIGHT
			a.point = "TOPLEFT"
			a.relativeFrame = "UIParent"
			a.relativePoint = "TOPLEFT"
			a.x = (pw - w) / 2
			a.y = (h - ph) / 2
			rel = UIParent
		end
		healthBar:ClearAllPoints()
		healthBar:SetPoint(a.point or "TOPLEFT", rel, a.relativePoint or a.point or "TOPLEFT", a.x or 0, a.y or 0)
	end

	-- Then power bars: anchor in a safe order (parents first), break cycles if detected
	local spec = addon.variables.unitSpec
	local types = {}
	for pType, bar in pairs(powerbar) do
		if bar then tinsert(types, pType) end
	end

	-- Build a graph of bar -> bar it anchors to (only EQOL bars)
	local edges = {}
	local anchors = {}
	for _, pType in ipairs(types) do
		local a = getAnchor(pType, spec)
		anchors[pType] = a
		local relType = frameNameToBarType(a and a.relativeFrame)
		if relType and powerbar[relType] then
			edges[pType] = relType
		else
			edges[pType] = nil
		end
	end

	-- DFS for ordering; break cycles by forcing current node to UIParent
	local order, visiting, visited = {}, {}, {}
	local function ensureUIParentDefaults(a, bar)
		a.point = a.point or "TOPLEFT"
		a.relativeFrame = "UIParent"
		a.relativePoint = a.relativePoint or "TOPLEFT"
		if a.x == nil or a.y == nil then
			local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
			local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
			local w = (bar and bar.GetWidth and bar:GetWidth()) or RB.DEFAULT_POWER_WIDTH
			local h = (bar and bar.GetHeight and bar:GetHeight()) or RB.DEFAULT_POWER_HEIGHT
			a.x = (pw - w) / 2
			a.y = (h - ph) / 2
		end
	end

	-- Pre-detach all bars to UIParent to avoid transient cycles during reanchor
	for _, pType in ipairs(types) do
		local bar = powerbar[pType]
		local a = anchors[pType]
		if bar and a then
			if (a.relativeFrame or "UIParent") == "UIParent" then ensureUIParentDefaults(a, bar) end
			bar:ClearAllPoints()
			bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", a.x or 0, a.y or 0)
		end
	end

	local function dfs(node)
		if visited[node] then return end
		if visiting[node] then
			-- Cycle detected: break by reanchoring this node to UIParent
			local a = anchors[node]
			ensureUIParentDefaults(a, powerbar[node])
			edges[node] = nil
			visiting[node] = nil
			visited[node] = true
			tinsert(order, node)
			return
		end
		visiting[node] = true
		local to = edges[node]
		if to then dfs(to) end
		visiting[node] = nil
		visited[node] = true
		tinsert(order, node)
	end

	for _, pType in ipairs(types) do
		dfs(pType)
	end

	-- Apply anchors in computed order
	for _, pType in ipairs(order) do
		local bar = powerbar[pType]
		if bar then
			local a = anchors[pType]
			if (a.relativeFrame or "UIParent") == "UIParent" then ensureUIParentDefaults(a, bar) end
			if
				a.autoSpacing
				or (a.autoSpacing == nil and isEQOLFrameName(a.relativeFrame) and (a.point or "TOPLEFT") == "TOPLEFT" and (a.relativePoint or "BOTTOMLEFT") == "BOTTOMLEFT" and (a.x or 0) == 0)
			then
				a.x = 0
				a.y = RB.DEFAULT_STACK_SPACING
				a.autoSpacing = true
			end
			local rel, looped = resolveAnchor(a, pType)
			if looped and (a.relativeFrame or "UIParent") ~= "UIParent" then
				ensureUIParentDefaults(a, bar)
				rel = UIParent
			end
			bar:ClearAllPoints()
			bar:SetPoint(a.point or "TOPLEFT", rel, a.relativePoint or a.point or "TOPLEFT", a.x or 0, a.y or 0)
			local isUI = (a.relativeFrame or "UIParent") == "UIParent"
			bar:SetMovable(isUI)
			local cfg = getBarSettings(pType)
			bar:EnableMouse(shouldEnableBarMouse(cfg))
		end
	end

	updateHealthBar("UNIT_ABSORB_AMOUNT_CHANGED")
	if ResourceBars and ResourceBars.SyncRelativeFrameWidths then ResourceBars.SyncRelativeFrameWidths() end
	ResourceBars._reanchoring = false
end

ResourceBars.DEFAULT_HEALTH_WIDTH = RB.DEFAULT_HEALTH_WIDTH
ResourceBars.DEFAULT_HEALTH_HEIGHT = RB.DEFAULT_HEALTH_HEIGHT
ResourceBars.DEFAULT_POWER_WIDTH = RB.DEFAULT_POWER_WIDTH
ResourceBars.DEFAULT_POWER_HEIGHT = RB.DEFAULT_POWER_HEIGHT or RB.DEFAULT_HEALTH_HEIGHT
ResourceBars.MIN_RESOURCE_BAR_WIDTH = RB.MIN_RESOURCE_BAR_WIDTH
ResourceBars.THRESHOLD_THICKNESS = RB.THRESHOLD_THICKNESS
ResourceBars.THRESHOLD_DEFAULT = RB.THRESHOLD_DEFAULT
ResourceBars.DEFAULT_THRESHOLDS = RB.DEFAULT_THRESHOLDS
ResourceBars.DEFAULT_THRESHOLD_COUNT = RB.DEFAULT_THRESHOLD_COUNT
ResourceBars.STAGGER_EXTRA_THRESHOLD_HIGH = RB.STAGGER_EXTRA_THRESHOLD_HIGH
ResourceBars.STAGGER_EXTRA_THRESHOLD_EXTREME = RB.STAGGER_EXTRA_THRESHOLD_EXTREME
ResourceBars.STAGGER_EXTRA_COLORS = RB.STAGGER_EXTRA_COLORS
ResourceBars.getBarSettings = getBarSettings
ResourceBars.getAnchor = getAnchor
ResourceBars.BehaviorOptionsForType = behaviorOptionsForType
ResourceBars.BehaviorSelectionFromConfig = behaviorSelectionFromConfig
ResourceBars.ApplyBehaviorSelection = applyBehaviorSelection
ResourceBars.ExportProfile = exportResourceProfile
ResourceBars.ImportProfile = importResourceProfile
ResourceBars.ExportErrorMessage = exportErrorMessage
ResourceBars.ImportErrorMessage = importErrorMessage
ResourceBars.SpecNameByIndex = specNameByIndex
ResourceBars.SaveGlobalProfile = saveGlobalProfile
ResourceBars.ApplyGlobalProfile = applyGlobalProfile

addon.exportResourceProfile = function(profileName, scopeKey) return ResourceBars.ExportProfile(scopeKey, profileName) end
addon.importResourceProfile = function(encoded, scopeKey) return ResourceBars.ImportProfile(encoded, scopeKey) end

function addon.Aura.functions.InitResourceBars()
	if addon.db["enableResourceFrame"] then
		local frameLogin = CreateFrame("Frame")
		frameLogin:RegisterEvent("PLAYER_LOGIN")
		frameLogin:SetScript("OnEvent", function(self, event)
			if event == "PLAYER_LOGIN" then
				if addon.db["enableResourceFrame"] then
					LoadResourceBars()
					addon.Aura.ResourceBars.EnableResourceBars()
				end
				frameLogin:UnregisterAllEvents()
				frameLogin:SetScript("OnEvent", nil)
				frameLogin = nil
			end
		end)
	end
end
