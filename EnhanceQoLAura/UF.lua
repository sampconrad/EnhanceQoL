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

local shouldShowSampleCast
local setSampleCast
local applyFont

local PLAYER_UNIT = "player"
local TARGET_UNIT = "target"
local TARGET_TARGET_UNIT = "targettarget"
local FOCUS_UNIT = "focus"
local FRAME_NAME = "EQOLUFPlayerFrame"
local HEALTH_NAME = "EQOLUFPlayerHealth"
local POWER_NAME = "EQOLUFPlayerPower"
local STATUS_NAME = "EQOLUFPlayerStatus"
local TARGET_FRAME_NAME = "EQOLUFTargetFrame"
local TARGET_HEALTH_NAME = "EQOLUFTargetHealth"
local TARGET_POWER_NAME = "EQOLUFTargetPower"
local TARGET_STATUS_NAME = "EQOLUFTargetStatus"
local TARGET_TARGET_FRAME_NAME = "EQOLUFToTFrame"
local TARGET_TARGET_HEALTH_NAME = "EQOLUFToTHealth"
local TARGET_TARGET_POWER_NAME = "EQOLUFToTPower"
local TARGET_TARGET_STATUS_NAME = "EQOLUFToTStatus"
local FOCUS_FRAME_NAME = "EQOLUFFocusFrame"
local FOCUS_HEALTH_NAME = "EQOLUFFocusHealth"
local FOCUS_POWER_NAME = "EQOLUFFocusPower"
local FOCUS_STATUS_NAME = "EQOLUFFocusStatus"
local PET_UNIT = "pet"
local PET_FRAME_NAME = "EQOLUFPetFrame"
local PET_HEALTH_NAME = "EQOLUFPetHealth"
local PET_POWER_NAME = "EQOLUFPetPower"
local PET_STATUS_NAME = "EQOLUFPetStatus"
local BLIZZ_PLAYER_FRAME_NAME = "PlayerFrame"
local BLIZZ_TARGET_FRAME_NAME = "TargetFrame"
local BLIZZ_TARGET_TARGET_FRAME_NAME = "TargetFrameToT"
local BLIZZ_FOCUS_FRAME_NAME = "FocusFrame"
local BLIZZ_PET_FRAME_NAME = "PetFrame"
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
		unit = "player",
		frameName = FRAME_NAME,
		healthName = HEALTH_NAME,
		powerName = POWER_NAME,
		statusName = STATUS_NAME,
		dropdown = function(self) ToggleDropDownMenu(1, nil, PlayerFrameDropDown, self, 0, 0) end,
	},
	target = {
		unit = "target",
		frameName = TARGET_FRAME_NAME,
		healthName = TARGET_HEALTH_NAME,
		powerName = TARGET_POWER_NAME,
		statusName = TARGET_STATUS_NAME,
		dropdown = function(self) ToggleDropDownMenu(1, nil, TargetFrameDropDown, self, 0, 0) end,
	},
	targettarget = {
		unit = "targettarget",
		frameName = TARGET_TARGET_FRAME_NAME,
		healthName = TARGET_TARGET_HEALTH_NAME,
		powerName = TARGET_TARGET_POWER_NAME,
		statusName = TARGET_TARGET_STATUS_NAME,
		dropdown = function(self) ToggleDropDownMenu(1, nil, TargetFrameDropDown, self, 0, 0) end,
	},
	focus = {
		unit = FOCUS_UNIT,
		frameName = FOCUS_FRAME_NAME,
		healthName = FOCUS_HEALTH_NAME,
		powerName = FOCUS_POWER_NAME,
		statusName = FOCUS_STATUS_NAME,
		dropdown = function(self) ToggleDropDownMenu(1, nil, FocusFrameDropDown, self, 0, 0) end,
	},
	pet = {
		unit = PET_UNIT,
		frameName = PET_FRAME_NAME,
		healthName = PET_HEALTH_NAME,
		powerName = PET_POWER_NAME,
		statusName = PET_STATUS_NAME,
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
		border = { enabled = true, color = { 0, 0, 0, 0.8 }, edgeSize = 1, inset = 0 },
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
			notInterruptibleColor = { 0.6, 0.6, 0.6, 1 },
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
	checkRaidTargetIcon(PLAYER_UNIT, states[PLAYER_UNIT])
	checkRaidTargetIcon(TARGET_UNIT, states[TARGET_UNIT])
	checkRaidTargetIcon(TARGET_TARGET_UNIT, states[TARGET_TARGET_UNIT])
	checkRaidTargetIcon(PET_UNIT, states[PET_UNIT])
	checkRaidTargetIcon(FOCUS_UNIT, states[FOCUS_UNIT])
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
	if applyClassResourceLayout then applyClassResourceLayout(states[PLAYER_UNIT] and states[PLAYER_UNIT].cfg or ensureDB(PLAYER_UNIT)) end
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
	local st = states[PLAYER_UNIT]
	if not st or not st.frame then return end
	local def = defaultsFor(PLAYER_UNIT)
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
	targetAuras[aura.auraInstanceID] = {
		auraInstanceID = aura.auraInstanceID,
		spellId = aura.spellId,
		name = aura.name,
		icon = aura.icon,
		isHelpful = aura.isHelpful,
		isHarmful = aura.isHarmful,
		applications = aura.applications,
		duration = aura.duration,
		expirationTime = aura.expirationTime,
		sourceUnit = aura.sourceUnit,
	}
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
	if issecretvalue and issecretvalue(duration) then return false end
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

	if issecretvalue and issecretvalue(isDebuff) then isDebuff = not C_UnitAuras.IsAuraFilteredOutByInstanceID("target", aura.auraInstanceID, "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY") end
	unitToken = unitToken or "target"
	btn.spellId = aura.spellId
	btn._showTooltip = ac.showTooltip ~= false
	btn.icon:SetTexture(aura.icon or "")
	btn.cd:Clear()
	if issecretvalue and issecretvalue(aura.duration) then
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
			btn.border:SetVertexColor(1, 0.25, 0.25, 1)
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

	local width = st.frame:GetWidth() or 0
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
		local helpful = C_UnitAuras.GetUnitAuras("target", "HELPFUL|CANCELABLE")
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
	unit = unit or PLAYER_UNIT
	local enumId, token = UnitPowerType(unit)
	if unit == PLAYER_UNIT then
		mainPowerEnum, mainPowerToken = enumId, token
	end
	return enumId, token
end
local function getMainPower(unit)
	if unit and unit ~= PLAYER_UNIT then return UnitPowerType(unit) end
	if not mainPowerEnum or not mainPowerToken then return refreshMainPower(PLAYER_UNIT) end
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
	elseif unit == TARGET_UNIT then
		cond = "[@target,exists] show; hide"
	elseif unit == TARGET_TARGET_UNIT then
		cond = "[@targettarget,exists] show; hide"
	elseif unit == FOCUS_UNIT then
		cond = "[@focus,exists] show; hide"
	elseif unit == PET_UNIT then
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
		if frameName == TARGET_TARGET_FRAME_NAME then
			info = { name = TARGET_TARGET_FRAME_NAME, var = "unitframeSettingTargetTargetFrame", unitToken = TARGET_TARGET_UNIT }
		else
			return
		end
	end
	local function frameNameFor(unitToken)
		if unitToken == PLAYER_UNIT then return BLIZZ_PLAYER_FRAME_NAME end
		if unitToken == TARGET_UNIT then return BLIZZ_TARGET_FRAME_NAME end
		if unitToken == TARGET_TARGET_UNIT then return BLIZZ_TARGET_TARGET_FRAME_NAME end
		if unitToken == FOCUS_UNIT then return BLIZZ_FOCUS_FRAME_NAME end
		if unitToken == PET_UNIT then return BLIZZ_PET_FRAME_NAME end
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
	if PowerBarColor then
		local c = PowerBarColor[pToken]
		if c then
			if c.r then return c.r, c.g, c.b, c.a or 1 end
			if c[1] then return c[1], c[2], c[3], c[4] or 1 end
		end
	end
	return 0.1, 0.45, 1, 1
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

do
	local targetDefaults = CopyTable(defaults.player)
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
	st.castBar:ClearAllPoints()
	if anchor == "TOP" then
		st.castBar:SetPoint("BOTTOM", st.frame, "TOP", off.x or 0, off.y or 0)
	else
		st.castBar:SetPoint("TOP", st.frame, "BOTTOM", off.x or 0, off.y or 0)
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
	st.castBar:SetStatusBarTexture(resolveCastTexture(texKey))
	if st.castBar.SetStatusBarDesaturated then st.castBar:SetStatusBarDesaturated(false) end
	do -- Cast backdrop
		local bd = (ccfg and ccfg.backdrop) or (defc and defc.backdrop) or { enabled = true, color = { 0, 0, 0, 0.6 } }
		if bd.enabled == false then
			if st.castBar.SetBackdrop then st.castBar:SetBackdrop(nil) end
		elseif st.castBar.SetBackdrop then
			st.castBar:SetBackdrop({
				bgFile = "Interface\\Buttons\\WHITE8x8",
				edgeFile = nil,
				tile = false,
			})
			local col = bd.color or { 0, 0, 0, 0.6 }
			if st.castBar.SetBackdropColor then st.castBar:SetBackdropColor(col[1] or 0, col[2] or 0, col[3] or 0, col[4] or 0.6) end
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
	if st.castInfo.notInterruptible then clr = ccfg.notInterruptibleColor or defc.notInterruptibleColor or clr end
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
	local name, text, texture, startTimeMS, endTimeMS, _, _, notInterruptible, _, isEmpowered, numEmpowerStages = UnitChannelInfo(unit)
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

			local durObj
			if isChannel then
				durObj = UnitChannelDuration(unit)
			else
				durObj = UnitCastingDuration(unit)
			end
			st.castBar:SetTimerDuration(durObj)
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
			-- TODO: replace this interruptible-event workaround once C_CurveUtil.EvaluateColorFromBoolean and C_CurveUtil.EvaluateColorValueFromBoolean are available.
			local np = C_NamePlate.GetNamePlateForUnit(unit)

			if np and np.UnitFrame and np.UnitFrame.castBar and np.UnitFrame.castBar.barType then
				notInterruptible = np.UnitFrame.castBar.barType ~= "standard" and np.UnitFrame.castBar.barType ~= "channel"
			end
			local clr = ccfg.color or defc.color or { 0.9, 0.7, 0.2, 1 }
			if not issecretvalue(notInterruptible) and notInterruptible then
				clr = ccfg.notInterruptibleColor or defc.notInterruptibleColor or clr
			else
				clr = ccfg.color or defc.color or { 0.9, 0.7, 0.2, 1 }
			end
			st.castBar:SetStatusBarColor(clr[1] or 0.9, clr[2] or 0.7, clr[3] or 0.2, clr[4] or 1)
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
		local def = defaultsFor(unit) or {}
		local defH = def.health or {}
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
	if st.healthTextLeft then st.healthTextLeft:SetText(formatText(hc.textLeft or "PERCENT", cur, maxv, hc.useShortNumbers ~= false, percentVal)) end
	if st.healthTextRight then st.healthTextRight:SetText(formatText(hc.textRight or "CURMAX", cur, maxv, hc.useShortNumbers ~= false, percentVal)) end
end

local function updatePower(cfg, unit)
	cfg = cfg or (states[unit] and states[unit].cfg) or ensureDB(unit)
	local st = states[unit]
	if not st then return end
	local bar = st.power
	if not bar then return end
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
	local cr, cg, cb, ca
	if pcfg.useCustomColor and pcfg.color and pcfg.color[1] then
		cr, cg, cb, ca = pcfg.color[1], pcfg.color[2], pcfg.color[3], pcfg.color[4] or 1
	else
		cr, cg, cb, ca = getPowerColor(powerToken)
	end
	bar:SetStatusBarColor(cr or 0.1, cg or 0.45, cb or 1, ca or 1)
	if st.powerTextLeft then
		if (issecretvalue and not issecretvalue(maxv) and maxv == 0) or (not addon.variables.isMidnight and maxv == 0) then
			st.powerTextLeft:SetText("")
		else
			st.powerTextLeft:SetText(formatText(pcfg.textLeft or "PERCENT", cur, maxv, pcfg.useShortNumbers ~= false, percentVal))
		end
	end
	if (issecretvalue and not issecretvalue(maxv) and maxv == 0) or (not addon.variables.isMidnight and maxv == 0) then
		st.powerTextRight:SetText("")
	else
		if st.powerTextRight then st.powerTextRight:SetText(formatText(pcfg.textRight or "CURMAX", cur, maxv, pcfg.useShortNumbers ~= false, percentVal)) end
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

local function updateStatus(cfg, unit)
	cfg = cfg or (states[unit] and states[unit].cfg) or ensureDB(unit)
	local st = states[unit]
	if not st or not st.status then return end
	local scfg = cfg.status or {}
	local def = defaultsFor(unit)
	local defStatus = def.status or {}
	local ciCfg = scfg.combatIndicator or defStatus.combatIndicator or {}
	local showName = scfg.enabled ~= false
	local showLevel = scfg.levelEnabled ~= false
	local showStatus = showName or showLevel or (unit == PLAYER_UNIT and ciCfg.enabled ~= false)
	local statusHeight = showStatus and (cfg.statusHeight or def.statusHeight) or 0.001
	st.status:SetHeight(statusHeight)
	st.status:SetShown(showStatus)
	if st.nameText then
		applyFont(st.nameText, scfg.font, scfg.fontSize or 14, scfg.fontOutline)
		st.nameText:ClearAllPoints()
		st.nameText:SetPoint(scfg.nameAnchor or "LEFT", st.status, scfg.nameAnchor or "LEFT", (scfg.nameOffset and scfg.nameOffset.x) or 0, (scfg.nameOffset and scfg.nameOffset.y) or 0)
		st.nameText:SetShown(showName)
	end
	if st.levelText then
		applyFont(st.levelText, scfg.font, scfg.fontSize or 14, scfg.fontOutline)
		st.levelText:ClearAllPoints()
		st.levelText:SetPoint(scfg.levelAnchor or "RIGHT", st.status, scfg.levelAnchor or "RIGHT", (scfg.levelOffset and scfg.levelOffset.x) or 0, (scfg.levelOffset and scfg.levelOffset.y) or 0)
		st.levelText:SetShown(showStatus and showLevel)
	end
end

local function updateCombatIndicator(cfg)
	local st = states[PLAYER_UNIT]
	if not st or not st.combatIcon or not st.status then return end
	local scfg = (cfg and cfg.status) or (defaultsFor(PLAYER_UNIT) and defaultsFor(PLAYER_UNIT).status) or {}
	local ccfg = scfg.combatIndicator or {}
	if ccfg.enabled == false then
		st.combatIcon:Hide()
		return
	end
	st.combatIcon:SetTexture("Interface\\Addons\\EnhanceQoLAura\\Icons\\CombatIndicator.tga")
	st.combatIcon:SetSize(ccfg.size or 18, ccfg.size or 18)
	st.combatIcon:ClearAllPoints()
	st.combatIcon:SetPoint("TOP", st.status, "TOP", (ccfg.offset and ccfg.offset.x) or -8, (ccfg.offset and ccfg.offset.y) or 0)
	if (UnitAffectingCombat and UnitAffectingCombat(PLAYER_UNIT)) or addon.EditModeLib:IsInEditMode() then
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
	local st = states[PLAYER_UNIT]
	if not st or not st.restLoop then return end
	local def = defaultsFor(PLAYER_UNIT)
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
	local st = states[PLAYER_UNIT]
	if not st or not st.restLoop then return end
	local def = defaultsFor(PLAYER_UNIT)
	local rdef = def and def.resting or {}
	local rcfg = (cfg and cfg.resting) or rdef
	if not cfg or cfg.enabled == false or rcfg.enabled == false then
		if st.restLoopAnim and st.restLoopAnim:IsPlaying() then st.restLoopAnim:Stop() end
		st.restLoop:Hide()
		return
	end
	applyRestLoopLayout(cfg)
	local resting = (IsResting and IsResting()) or (UnitIsResting and UnitIsResting(PLAYER_UNIT))
	if resting then
		st.restLoop:Show()
		if st.restLoopAnim and not st.restLoopAnim:IsPlaying() then st.restLoopAnim:Play() end
	else
		if st.restLoopAnim and st.restLoopAnim:IsPlaying() then st.restLoopAnim:Stop() end
		st.restLoop:Hide()
	end
end

local function layoutFrame(cfg, unit)
	local st = states[unit]
	if not st or not st.frame then return end
	local def = defaultsFor(unit)
	local scfg = cfg.status or {}
	local defStatus = def.status or {}
	local ciCfg = scfg.combatIndicator or defStatus.combatIndicator or {}
	local showName = scfg.enabled ~= false
	local showLevel = scfg.levelEnabled ~= false
	local showStatus = showName or showLevel or (unit == PLAYER_UNIT and ciCfg.enabled ~= false)
	local pcfg = cfg.power or {}
	local powerEnabled = pcfg.enabled ~= false
	local width = max(MIN_WIDTH, cfg.width or def.width)
	local statusHeight = showStatus and (cfg.statusHeight or def.statusHeight) or 0
	local healthHeight = cfg.healthHeight or def.healthHeight
	local powerHeight = powerEnabled and (cfg.powerHeight or def.powerHeight) or 0
	local barGap = powerEnabled and (cfg.barGap or def.barGap or 0) or 0
	local borderInset = 0
	if cfg.border and cfg.border.enabled then borderInset = (cfg.border.edgeSize or 1) end
	st.frame:SetWidth(width + borderInset * 2)
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
		st.status:SetPoint("TOPLEFT", st.frame, "TOPLEFT", 0, 0)
		st.status:SetPoint("TOPRIGHT", st.frame, "TOPRIGHT", 0, 0)
		y = -statusHeight
	else
		st.status:SetPoint("TOPLEFT", st.frame, "TOPLEFT", 0, 0)
		st.status:SetPoint("TOPRIGHT", st.frame, "TOPRIGHT", 0, 0)
	end
	-- Bars container sits below status; border applied here, not on status
	local barsHeight = healthHeight + powerHeight + barGap + borderInset * 2
	if st.barGroup then
		st.barGroup:SetWidth(width + borderInset * 2)
		st.barGroup:SetHeight(barsHeight)
		st.barGroup:SetPoint("TOPLEFT", st.frame, "TOPLEFT", 0, y)
		st.barGroup:SetPoint("TOPRIGHT", st.frame, "TOPRIGHT", 0, y)
	end

	st.health:SetPoint("TOPLEFT", st.barGroup or st.frame, "TOPLEFT", borderInset, -borderInset)
	st.health:SetPoint("TOPRIGHT", st.barGroup or st.frame, "TOPRIGHT", -borderInset, -borderInset)
	st.power:SetPoint("TOPLEFT", st.health, "BOTTOMLEFT", 0, -barGap)
	st.power:SetPoint("TOPRIGHT", st.health, "BOTTOMRIGHT", 0, -barGap)

	local totalHeight = statusHeight + barsHeight
	st.frame:SetHeight(totalHeight)

	layoutTexts(st.health, st.healthTextLeft, st.healthTextRight, cfg.health, width)
	layoutTexts(st.power, st.powerTextLeft, st.powerTextRight, cfg.power, width)
	if st.castBar and unit == TARGET_UNIT then applyCastLayout(cfg, unit) end

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
		st.auraContainer:SetWidth(width + borderInset * 2)

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
				st.debuffContainer:SetWidth(width + borderInset * 2)
			else
				-- If not separating, keep the debuff container collapsed
				st.debuffContainer:SetPoint("TOPLEFT", st.auraContainer, "TOPLEFT", 0, 0)
				st.debuffContainer:SetWidth(0.001)
				st.debuffContainer:SetHeight(0.001)
				st.debuffContainer:Hide()
			end
		end
	end
	if unit == PLAYER_UNIT then applyClassResourceLayout(cfg) end
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
	if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated(false) end

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
	if (unit == TARGET_UNIT or unit == FOCUS_UNIT or isBossUnit(unit)) and not st.castBar then
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
	st.raidIcon = st.statusTextLayer:CreateTexture(nil, "OVERLAY", nil, 7)
	st.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	st.raidIcon:SetSize(18, 18)
	st.raidIcon:SetPoint("TOP", st.frame, "TOP", 0, -2)
	st.raidIcon:Hide()
	if unit == PLAYER_UNIT then
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
		if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated(pcfg.useCustomColor == true) end
		if unit == PLAYER_UNIT then refreshMainPower(unit) end
		local _, powerToken = getMainPower(unit)
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
	if st.castBar and (unit == TARGET_UNIT or unit == FOCUS_UNIT or isBossUnit(unit)) then
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
		end
		applyVisibilityDriver(unit, false)
		if unit == PLAYER_UNIT then applyFrameRuleOverride(BLIZZ_PLAYER_FRAME_NAME, false) end
		if unit == TARGET_UNIT then applyFrameRuleOverride(BLIZZ_TARGET_FRAME_NAME, false) end
		if unit == TARGET_TARGET_UNIT then applyFrameRuleOverride(BLIZZ_TARGET_TARGET_FRAME_NAME, false) end
		if unit == FOCUS_UNIT then applyFrameRuleOverride(BLIZZ_FOCUS_FRAME_NAME, false) end
		if unit == PET_UNIT then applyFrameRuleOverride(BLIZZ_PET_FRAME_NAME, false) end
		if unit == PLAYER_UNIT then restoreClassResourceFrames() end
		if unit == "target" then resetTargetAuras() end
		if unit == PLAYER_UNIT then updateRestingIndicator(cfg) end
		return
	end
	ensureFrames(unit)
	st = states[unit]
	st.cfg = cfg
	applyVisibilityDriver(unit, cfg.enabled)
	if unit == PLAYER_UNIT then applyFrameRuleOverride(BLIZZ_PLAYER_FRAME_NAME, true) end
	if unit == TARGET_UNIT then applyFrameRuleOverride(BLIZZ_TARGET_FRAME_NAME, true) end
	if unit == TARGET_TARGET_UNIT then applyFrameRuleOverride(BLIZZ_TARGET_TARGET_FRAME_NAME, true) end
	if unit == FOCUS_UNIT then applyFrameRuleOverride(BLIZZ_FOCUS_FRAME_NAME, true) end
	if unit == PET_UNIT then applyFrameRuleOverride(BLIZZ_PET_FRAME_NAME, true) end
	applyBars(cfg, unit)
	if not InCombatLockdown() then layoutFrame(cfg, unit) end
	updateStatus(cfg, unit)
	updateNameAndLevel(cfg, unit)
	updateHealth(cfg, unit)
	updatePower(cfg, unit)
	checkRaidTargetIcon(unit, st)
	if unit == PLAYER_UNIT then
		updateCombatIndicator(cfg)
		updateRestingIndicator(cfg)
	end
	-- if unit == "target" then hideBlizzardTargetFrame() end
	if st and st.frame then
		if st.barGroup then st.barGroup:Show() end
		if st.status then st.status:Show() end
	end
	if unit == TARGET_UNIT and st.castBar then
		if cfg.cast and cfg.cast.enabled ~= false and UnitExists(TARGET_UNIT) then
			if shouldShowSampleCast(unit) and (not st.castInfo or not UnitCastingInfo or not UnitCastingInfo(unit)) then setSampleCast(unit) end
			st.castBar:Show()
		else
			stopCast(TARGET_UNIT)
			st.castBar:Hide()
		end
	end
	if isBossUnit(unit) and st.castBar then
		if cfg.cast and cfg.cast.enabled ~= false and UnitExists(unit) then
			st.castBar:Show()
		else
			stopCast(unit)
			st.castBar:Hide()
		end
	end
	if unit == TARGET_UNIT and states[unit] and states[unit].auraContainer then updateTargetAuraIcons(1) end
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
	local hc = cfg.health or def.health or {}
	local pcfg = cfg.power or def.power or {}
	local cdef = cfg.cast or def.cast or {}

	local cur = UnitHealth("player") or 1
	local maxv = UnitHealthMax("player") or cur or 1
	st.health:SetMinMaxValues(0, maxv)
	st.health:SetValue(cur)
	local color = hc.color or (def.health and def.health.color) or { 0, 0.8, 0, 1 }
	st.health:SetStatusBarColor(color[1] or 0, color[2] or 0.8, color[3] or 0, color[4] or 1)
	if st.healthTextLeft then st.healthTextLeft:SetText(formatText(hc.textLeft or "PERCENT", cur, maxv, hc.useShortNumbers ~= false)) end
	if st.healthTextRight then st.healthTextRight:SetText(formatText(hc.textRight or "CURMAX", cur, maxv, hc.useShortNumbers ~= false)) end

	local powerEnabled = pcfg.enabled ~= false
	if st.power then
		if powerEnabled then
			local enumId, token = getMainPower("player")
			local pCur = UnitPower("player", enumId or 0) or 0
			local pMax = UnitPowerMax("player", enumId or 0) or 0
			st.power:SetMinMaxValues(0, pMax > 0 and pMax or 1)
			st.power:SetValue(pCur)
			local pr, pg, pb, pa
			if pcfg.useCustomColor and pcfg.color then
				pr, pg, pb, pa = pcfg.color[1], pcfg.color[2], pcfg.color[3], pcfg.color[4] or 1
			else
				pr, pg, pb, pa = getPowerColor(token)
			end
			st.power:SetStatusBarColor(pr or 0.1, pg or 0.45, pb or 1, pa or 1)
			if st.powerTextLeft then st.powerTextLeft:SetText(formatText(pcfg.textLeft or "PERCENT", pCur, pMax, pcfg.useShortNumbers ~= false)) end
			if st.powerTextRight then st.powerTextRight:SetText(formatText(pcfg.textRight or "CURMAX", pCur, pMax, pcfg.useShortNumbers ~= false)) end
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
						st.castBar:Show()
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
	"PLAYER_UPDATE_RESTING",
	"UNIT_PET",
	"PLAYER_FOCUS_CHANGED",
	"INSTANCE_ENCOUNTER_ENGAGE_UNIT",
	"ENCOUNTER_START",
	"ENCOUNTER_END",
	"RAID_TARGET_UPDATE",
}

local eventFrame

local function anyUFEnabled()
	local p = ensureDB("player").enabled
	local t = ensureDB("target").enabled
	local tt = ensureDB(TARGET_TARGET_UNIT).enabled
	local pet = ensureDB(PET_UNIT).enabled
	local focus = ensureDB(FOCUS_UNIT).enabled
	local boss = ensureDB("boss").enabled
	return p or t or tt or pet or focus or boss
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
		local st = states[TARGET_TARGET_UNIT]
		local cfg = st and st.cfg
		if not cfg or not cfg.enabled then return end
		local pcfg = cfg.power or {}
		local powerEnabled = pcfg.enabled ~= false
		if not UnitExists(TARGET_TARGET_UNIT) or not st.frame or not st.frame:IsShown() then return end
		if powerEnabled then
			local _, powerToken = UnitPowerType(TARGET_TARGET_UNIT)
			if st.power and powerToken and powerToken ~= st._lastPowerToken then
				if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated((cfg.power or {}).useCustomColor == true) end
				configureSpecialTexture(st.power, powerToken, (cfg.power or {}).texture, cfg.power)
				st._lastPowerToken = powerToken
			end
		else
			if st.power then st.power:Hide() end
		end
		updateHealth(cfg, TARGET_TARGET_UNIT)
		updatePower(cfg, TARGET_TARGET_UNIT)
	end)
end

local function updateTargetTargetFrame(cfg, forceApply)
	cfg = cfg or ensureDB(TARGET_TARGET_UNIT)
	local st = states[TARGET_TARGET_UNIT]
	if not cfg.enabled then
		stopToTTicker()
		if st then
			if st.barGroup then st.barGroup:Hide() end
			if st.status then st.status:Hide() end
		end
		return
	end
	if forceApply or not st or not st.frame then
		applyConfig(TARGET_TARGET_UNIT)
		st = states[TARGET_TARGET_UNIT]
	end
	if st then st.cfg = st.cfg or cfg end
	local lHealth = UnitHealth("target")
	if UnitExists("target") and UnitExists(TARGET_TARGET_UNIT) and (issecretvalue and issecretvalue(lHealth) or lHealth > 0) then
		if st then
			if st.barGroup then st.barGroup:Show() end
			if st.status then st.status:Show() end
			local pcfg = cfg.power or {}
			local powerEnabled = pcfg.enabled ~= false
			updateNameAndLevel(cfg, TARGET_TARGET_UNIT)
			updateHealth(cfg, TARGET_TARGET_UNIT)
			if st.power and powerEnabled then
				local _, powerToken = getMainPower(TARGET_TARGET_UNIT)
				if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated((cfg.power or {}).useCustomColor == true) end
				configureSpecialTexture(st.power, powerToken, (cfg.power or {}).texture, cfg.power)
				st._lastPowerToken = powerToken
			elseif st.power then
				st.power:Hide()
			end
			updatePower(cfg, TARGET_TARGET_UNIT)
			checkRaidTargetIcon(TARGET_TARGET_UNIT, st)
		end
	else
		if st then
			if st.barGroup then st.barGroup:Hide() end
			if st.status then st.status:Hide() end
		end
	end
	checkRaidTargetIcon(TARGET_TARGET_UNIT, st)
	ensureToTTicker()
end

local function updateFocusFrame(cfg, forceApply)
	cfg = cfg or ensureDB(FOCUS_UNIT)
	local st = states[FOCUS_UNIT]
	if not cfg.enabled then
		if applyFrameRuleOverride then applyFrameRuleOverride(BLIZZ_FOCUS_FRAME_NAME, false) end
		if st then
			if st.barGroup then st.barGroup:Hide() end
			if st.status then st.status:Hide() end
		end
		return
	end
	if applyFrameRuleOverride then applyFrameRuleOverride(BLIZZ_FOCUS_FRAME_NAME, true) end
	if forceApply or not st or not st.frame then
		applyConfig(FOCUS_UNIT)
		st = states[FOCUS_UNIT]
	end
	if st then st.cfg = st.cfg or cfg end
	if UnitExists(FOCUS_UNIT) then
		if st then
			if st.barGroup then st.barGroup:Show() end
			if st.status then st.status:Show() end
			local pcfg = cfg.power or {}
			local powerEnabled = pcfg.enabled ~= false
			updateNameAndLevel(cfg, FOCUS_UNIT)
			updateHealth(cfg, FOCUS_UNIT)
			if st.power and powerEnabled then
				local _, powerToken = getMainPower(FOCUS_UNIT)
				if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated((cfg.power or {}).useCustomColor == true) end
				configureSpecialTexture(st.power, powerToken, (cfg.power or {}).texture, cfg.power)
				st._lastPowerToken = powerToken
			elseif st.power then
				st.power:Hide()
			end
			updatePower(cfg, FOCUS_UNIT)
			if st.castBar then setCastInfoFromUnit(FOCUS_UNIT) end
			checkRaidTargetIcon(FOCUS_UNIT, st)
		end
	else
		if st then
			if st.barGroup then st.barGroup:Hide() end
			if st.status then st.status:Hide() end
			if st.castBar then stopCast(FOCUS_UNIT) end
		end
	end
	checkRaidTargetIcon(FOCUS_UNIT, st)
end

local function onEvent(self, event, unit, arg1)
	if unitEventsMap[event] and unit and not (allowedEventUnit[unit] or isBossUnit(unit)) then return end
	local playerCfg = (states[PLAYER_UNIT] and states[PLAYER_UNIT].cfg) or ensureDB("player")
	local targetCfg = (states[TARGET_UNIT] and states[TARGET_UNIT].cfg) or ensureDB("target")
	local totCfg = (states[TARGET_TARGET_UNIT] and states[TARGET_TARGET_UNIT].cfg) or ensureDB(TARGET_TARGET_UNIT)
	local petCfg = (states[PET_UNIT] and states[PET_UNIT].cfg) or ensureDB(PET_UNIT)
	local focusCfg = (states[FOCUS_UNIT] and states[FOCUS_UNIT].cfg) or ensureDB(FOCUS_UNIT)
	local bossCfg = ensureDB("boss")
	if event == "PLAYER_ENTERING_WORLD" then
		refreshMainPower(PLAYER_UNIT)
		applyConfig("player")
		applyConfig("target")
		updateTargetTargetFrame(totCfg, true)
		if focusCfg.enabled then updateFocusFrame(focusCfg, true) end
		if petCfg.enabled then applyConfig(PET_UNIT) end
		updateCombatIndicator(playerCfg)
		updateRestingIndicator(playerCfg)
		updateAllRaidTargetIcons()
		if bossCfg.enabled then
			updateBossFrames(true)
		else
			hideBossFrames()
		end
	elseif event == "PLAYER_DEAD" then
		if states.player and states.player.health then states.player.health:SetValue(0) end
		updateHealth(playerCfg, "player")
	elseif event == "PLAYER_ALIVE" then
		refreshMainPower(PLAYER_UNIT)
		updateHealth(playerCfg, "player")
		updatePower(playerCfg, "player")
		updateCombatIndicator(playerCfg)
		updateRestingIndicator(playerCfg)
	elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
		updateCombatIndicator(playerCfg)
		if event == "PLAYER_REGEN_ENABLED" then
			if bossLayoutDirty then layoutBossFrames() end
			if bossHidePending then hideBossFrames(true) end
			if bossShowPending or bossInitPending then updateBossFrames(true) end
			bossLayoutDirty, bossHidePending, bossShowPending, bossInitPending = nil, nil, nil, nil
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		local unitToken = TARGET_UNIT
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
		if totCfg.enabled then updateTargetTargetFrame(totCfg) end
		if focusCfg.enabled then updateFocusFrame(focusCfg) end
	elseif event == "UNIT_AURA" and unit == "target" then
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
		local width = st.frame and st.frame:GetWidth() or 0
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
		if unit == PLAYER_UNIT then updateHealth(playerCfg, "player") end
		if unit == "target" then updateHealth(targetCfg, "target") end
		if unit == PET_UNIT then updateHealth(petCfg, PET_UNIT) end
		if bossCfg.enabled and isBossUnit(unit) then updateHealth(bossCfg, unit) end
	elseif event == "UNIT_MAXPOWER" then
		if unit == PLAYER_UNIT then updatePower(playerCfg, "player") end
		if unit == "target" then updatePower(targetCfg, "target") end
		if unit == PET_UNIT then updatePower(petCfg, PET_UNIT) end
		if unit == FOCUS_UNIT then updatePower(focusCfg, FOCUS_UNIT) end
		if bossCfg.enabled and isBossUnit(unit) then updatePower(bossCfg, unit) end
	elseif event == "UNIT_DISPLAYPOWER" then
		if unit == PLAYER_UNIT then
			refreshMainPower(unit)
			local st = states[unit]
			local pcfg = playerCfg.power or {}
			if st and st.power and pcfg.enabled ~= false then
				local _, powerToken = getMainPower(unit)
				configureSpecialTexture(st.power, powerToken, (playerCfg.power or {}).texture, playerCfg.power)
			elseif st and st.power then
				st.power:Hide()
			end
			updatePower(playerCfg, "player")
		elseif unit == "target" then
			local st = states[unit]
			local pcfg = targetCfg.power or {}
			if st and st.power and pcfg.enabled ~= false then
				local _, powerToken = getMainPower(unit)
				configureSpecialTexture(st.power, powerToken, (targetCfg.power or {}).texture, targetCfg.power)
			elseif st and st.power then
				st.power:Hide()
			end
			updatePower(targetCfg, "target")
		elseif unit == FOCUS_UNIT then
			local st = states[unit]
			local pcfg = focusCfg.power or {}
			if st and st.power and pcfg.enabled ~= false then
				local _, powerToken = getMainPower(unit)
				configureSpecialTexture(st.power, powerToken, (focusCfg.power or {}).texture, focusCfg.power)
			elseif st and st.power then
				st.power:Hide()
			end
			updatePower(focusCfg, FOCUS_UNIT)
		elseif unit == PET_UNIT then
			local st = states[unit]
			local pcfg = petCfg.power or {}
			if st and st.power and pcfg.enabled ~= false then
				local _, powerToken = getMainPower(unit)
				configureSpecialTexture(st.power, powerToken, (petCfg.power or {}).texture, petCfg.power)
			elseif st and st.power then
				st.power:Hide()
			end
			updatePower(petCfg, PET_UNIT)
		elseif bossCfg.enabled and isBossUnit(unit) then
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
	elseif event == "UNIT_POWER_UPDATE" and not FREQUENT[arg1] then
		if unit == PLAYER_UNIT then updatePower(playerCfg, "player") end
		if unit == "target" then updatePower(targetCfg, "target") end
		if unit == PET_UNIT then updatePower(petCfg, PET_UNIT) end
		if unit == FOCUS_UNIT then updatePower(focusCfg, FOCUS_UNIT) end
		if bossCfg.enabled and isBossUnit(unit) then updatePower(bossCfg, unit) end
	elseif event == "UNIT_POWER_FREQUENT" and FREQUENT[arg1] then
		if unit == PLAYER_UNIT then updatePower(playerCfg, "player") end
		if unit == "target" then updatePower(targetCfg, "target") end
		if unit == PET_UNIT then updatePower(petCfg, PET_UNIT) end
		if unit == FOCUS_UNIT then updatePower(focusCfg, FOCUS_UNIT) end
		if bossCfg.enabled and isBossUnit(unit) then updatePower(bossCfg, unit) end
	elseif event == "UNIT_NAME_UPDATE" or event == "PLAYER_LEVEL_UP" then
		if unit == PLAYER_UNIT or event == "PLAYER_LEVEL_UP" then updateNameAndLevel(playerCfg, "player") end
		if unit == "target" then updateNameAndLevel(targetCfg, "target") end
		if unit == FOCUS_UNIT then updateNameAndLevel(focusCfg, FOCUS_UNIT) end
		if unit == PET_UNIT then updateNameAndLevel(petCfg, PET_UNIT) end
		if bossCfg.enabled and isBossUnit(unit) then updateNameAndLevel(bossCfg, unit) end
	elseif event == "UNIT_TARGET" and unit == TARGET_UNIT then
		if totCfg.enabled then updateTargetTargetFrame(totCfg) end
	elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
		if unit == TARGET_UNIT then setCastInfoFromUnit(TARGET_UNIT) end
		if unit == FOCUS_UNIT then setCastInfoFromUnit(FOCUS_UNIT) end
		if isBossUnit(unit) then setCastInfoFromUnit(unit) end
	elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if unit == TARGET_UNIT then
			stopCast(TARGET_UNIT)
			if shouldShowSampleCast(unit) then setSampleCast(unit) end
		end
		if unit == FOCUS_UNIT then
			stopCast(FOCUS_UNIT)
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
		if petCfg.enabled then
			applyConfig(PET_UNIT)
			updateNameAndLevel(petCfg, PET_UNIT)
			updateHealth(petCfg, PET_UNIT)
			updatePower(petCfg, PET_UNIT)
		end
	elseif event == "PLAYER_FOCUS_CHANGED" then
		if focusCfg.enabled then
			updateFocusFrame(focusCfg, true)
			checkRaidTargetIcon(FOCUS_UNIT, states[FOCUS_UNIT])
		end
	elseif event == "PLAYER_UPDATE_RESTING" then
		updateRestingIndicator(playerCfg)
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
		return
	end
	if eventFrame then return end
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
			updateCombatIndicator(states[PLAYER_UNIT] and states[PLAYER_UNIT].cfg or ensureDB(PLAYER_UNIT))
			ensureBossFramesReady(ensureDB("boss"))
			updateBossFrames(true)
			updateAllRaidTargetIcons()
		end)

		addon.EditModeLib:RegisterCallback("exit", function()
			updateCombatIndicator(states[PLAYER_UNIT] and states[PLAYER_UNIT].cfg or ensureDB(PLAYER_UNIT))
			hideBossFrames(true)
			if ensureDB("boss").enabled then updateBossFrames(true) end
			updateAllRaidTargetIcons()
		end)
	end
end

function UF.Enable()
	local cfg = ensureDB("player")
	cfg.enabled = true
	ensureEventHandling()
	applyConfig("player")
	if ensureDB("target").enabled then applyConfig("target") end
	local totCfg = ensureDB(TARGET_TARGET_UNIT)
	if totCfg.enabled then updateTargetTargetFrame(totCfg, true) end
	if ensureDB(FOCUS_UNIT).enabled then updateFocusFrame(ensureDB(FOCUS_UNIT), true) end
	if ensureDB(PET_UNIT).enabled then applyConfig(PET_UNIT) end
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
		return
	end
	applyConfig("player")
	applyConfig("target")
	local focusCfg = ensureDB(FOCUS_UNIT)
	if focusCfg.enabled then
		updateFocusFrame(focusCfg, true)
	elseif applyFrameRuleOverride then
		applyFrameRuleOverride(BLIZZ_FOCUS_FRAME_NAME, false)
	end
	local targetCfg = ensureDB("target")
	if targetCfg.enabled and UnitExists and UnitExists(TARGET_UNIT) and states[TARGET_UNIT] and states[TARGET_UNIT].frame then
		states[TARGET_UNIT].barGroup:Show()
		states[TARGET_UNIT].status:Show()
	end
	local totCfg = ensureDB(TARGET_TARGET_UNIT)
	updateTargetTargetFrame(totCfg, true)
	if ensureDB(PET_UNIT).enabled then
		applyConfig(PET_UNIT)
	elseif applyFrameRuleOverride then
		applyFrameRuleOverride(BLIZZ_PET_FRAME_NAME, false)
	end
	if bossCfg.enabled then
		ensureBossFramesReady(bossCfg)
		updateBossFrames(true)
	else
		hideBossFrames()
	end
end

function UF.RefreshUnit(unit)
	ensureEventHandling()
	if not anyUFEnabled() then return end
	if unit == TARGET_TARGET_UNIT then
		local totCfg = ensureDB(TARGET_TARGET_UNIT)
		updateTargetTargetFrame(totCfg, true)
		ensureToTTicker()
	elseif unit == TARGET_UNIT then
		applyConfig(TARGET_UNIT)
		local targetCfg = ensureDB("target")
		if targetCfg.enabled and UnitExists and UnitExists(TARGET_UNIT) and states[TARGET_UNIT] and states[TARGET_UNIT].frame then
			states[TARGET_UNIT].barGroup:Show()
			states[TARGET_UNIT].status:Show()
		end
	elseif unit == FOCUS_UNIT then
		local focusCfg = ensureDB(FOCUS_UNIT)
		if focusCfg.enabled then
			updateFocusFrame(focusCfg, true)
		elseif applyFrameRuleOverride then
			applyFrameRuleOverride(BLIZZ_FOCUS_FRAME_NAME, false)
		end
	elseif unit == PET_UNIT then
		if ensureDB(PET_UNIT).enabled then
			applyConfig(PET_UNIT)
		elseif applyFrameRuleOverride then
			applyFrameRuleOverride(BLIZZ_PET_FRAME_NAME, false)
		end
	elseif isBossUnit(unit) then
		updateBossFrames(true)
	else
		applyConfig(PLAYER_UNIT)
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
	local ttc = ensureDB(TARGET_TARGET_UNIT)
	if ttc.enabled then
		ensureEventHandling()
		updateTargetTargetFrame(ttc, true)
		ensureToTTicker()
	end
	local pcfg = ensureDB(PET_UNIT)
	if pcfg.enabled then
		ensureEventHandling()
		applyConfig(PET_UNIT)
	elseif applyFrameRuleOverride then
		applyFrameRuleOverride(BLIZZ_PET_FRAME_NAME, false)
	end
	local fcfg = ensureDB(FOCUS_UNIT)
	if fcfg.enabled then
		ensureEventHandling()
		updateFocusFrame(fcfg, true)
	elseif applyFrameRuleOverride then
		applyFrameRuleOverride(BLIZZ_FOCUS_FRAME_NAME, false)
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
