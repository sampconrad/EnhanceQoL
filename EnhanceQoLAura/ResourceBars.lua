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
local BLIZZARD_TEX

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")

local AceGUI = addon.AceGUI
local UnitPower, UnitPowerMax, UnitHealth, UnitHealthMax, UnitGetTotalAbsorbs, GetTime = UnitPower, UnitPowerMax, UnitHealth, UnitHealthMax, UnitGetTotalAbsorbs, GetTime
local CreateFrame = CreateFrame
local PowerBarColor = PowerBarColor
local UIParent = UIParent
local GetShapeshiftForm, GetShapeshiftFormInfo = GetShapeshiftForm, GetShapeshiftFormInfo
local UnitPowerType = UnitPowerType
local GetSpecializationInfoForClassID = GetSpecializationInfoForClassID
local GetNumSpecializationsForClassID = C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID
local GetRuneCooldown = GetRuneCooldown
local IsShiftKeyDown = IsShiftKeyDown
local After = C_Timer and C_Timer.After
local EnumPowerType = Enum and Enum.PowerType
local format = string.format
local CopyTable = CopyTable
local tostring = tostring
local floor, max, min, ceil, abs = math.floor, math.max, math.min, math.ceil, math.abs
local tinsert, tsort = table.insert, table.sort
local tconcat = table.concat
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local CUSTOM_CLASS_COLORS = CUSTOM_CLASS_COLORS
local RegisterStateDriver = RegisterStateDriver
local UnregisterStateDriver = UnregisterStateDriver
local InCombatLockdown = InCombatLockdown
local IsMounted = IsMounted
local UnitInVehicle = UnitInVehicle

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
local forceColorUpdate
local lastBarSelectionPerSpec = {}
local lastSpecCopySelection = {}
local lastProfileShareScope = {}
local lastSpecCopyMode = {}
local lastSpecCopyBar = {}
local lastSpecCopyCosmetic = {}
local RESOURCE_SHARE_KIND = "EQOL_RESOURCE_BAR_PROFILE"
local COOLDOWN_VIEWER_FRAME_NAME = "EssentialCooldownViewer"
local MIN_RESOURCE_BAR_WIDTH = 50
local DEFAULT_STACK_SPACING = 0
local SEPARATOR_THICKNESS = 1
local SEP_DEFAULT = { 1, 1, 1, 0.5 }
local WHITE = { 1, 1, 1, 1 }
local DEFAULT_RB_TEX = "Interface\\Buttons\\WHITE8x8" -- historical default (Solid)
BLIZZARD_TEX = "Interface\\TargetingFrame\\UI-StatusBar"
local SMOOTH_SPEED = 12
local DEFAULT_SMOOTH_DEADZONE = 0.75
local RUNE_UPDATE_INTERVAL = 0.1
local REFRESH_DEBOUNCE = 0.05
local REANCHOR_REFRESH = { reanchorOnly = true }
local OOC_VISIBILITY_DRIVER = "[combat] show; hide"
local visibilityDriverWatcher
local tryActivateSmooth
local requestActiveRefresh
local getStatusbarDropdownLists
local ensureRelativeFrameHooks
local scheduleRelativeFrameWidthSync
local COSMETIC_BAR_KEYS = {
	"barTexture",
	"width",
	"height",
	"textStyle",
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
	"reverseFill",
	"verticalFill",
	"smoothFill",
	"smoothDeadzone",
	"showSeparator",
	"separatorColor",
	"separatorThickness",
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
		if maxColor then
			curvePower[pType]:AddPoint(1.0, CreateColor(maxColor[1], maxColor[2], maxColor[3], maxColor[4])) -- sattes Grün
		else
			curvePower[pType]:AddPoint(1.0, CreateColor(0.0, 0.85, 0.0, 1)) -- sattes Grün
		end
	end
end
SetColorCurvePoints()

local function getPlayerClassColor()
	local class = addon and addon.variables and addon.variables.unitClass
	if not class then return 0, 0.7, 0, 1 end
	local color = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
	if color then return color.r or color[1] or 0, color.g or color[2] or 0.7, color.b or color[3] or 0, color.a or 1 end
	return 0, 0.7, 0, 1
end

local function setBarDesaturated(bar, flag)
	if bar and bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(flag and true or false) end
end

local function getPowerBarColor(type)
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

local function stopSmoothUpdater(bar)
	if not bar then return end
	if bar._smoothUpdater and bar:GetScript("OnUpdate") == bar._smoothUpdater then bar:SetScript("OnUpdate", nil) end
	bar._smoothActive = false
end

local function ensureSmoothUpdater(bar)
	if not bar then return end
	if not bar._smoothUpdater then
		bar._smoothUpdater = function(self, elapsed)
			if not self:IsShown() then
				stopSmoothUpdater(self)
				return
			end
			local target = self._smoothTarget
			if target == nil then
				stopSmoothUpdater(self)
				return
			end
			local current = self:GetValue() or 0
			local dz = self._smoothDeadzone or DEFAULT_SMOOTH_DEADZONE
			local diff = target - current
			if abs(diff) <= dz then
				self:SetValue(target)
				stopSmoothUpdater(self)
				return
			end
			local speed = self._smoothSpeed or SMOOTH_SPEED
			local step = diff * min(1, (elapsed or 0) * speed)
			self:SetValue(current + step)
		end
	end
end

local function ensureSmoothVisibilityHooks(bar)
	if not bar or bar._smoothVisibilityHooks then return end
	bar:HookScript("OnHide", function(self) stopSmoothUpdater(self) end)
	bar:HookScript("OnShow", function(self) tryActivateSmooth(self) end)
	bar._smoothVisibilityHooks = true
end

tryActivateSmooth = function(bar)
	if not bar or not bar._smoothEnabled then
		stopSmoothUpdater(bar)
		return
	end
	if addon.variables.isMidnight then return end
	ensureSmoothUpdater(bar)
	ensureSmoothVisibilityHooks(bar)
	bar._smoothSpeed = bar._smoothSpeed or SMOOTH_SPEED
	bar._smoothDeadzone = bar._smoothDeadzone or DEFAULT_SMOOTH_DEADZONE
	if not bar._smoothTarget then
		stopSmoothUpdater(bar)
		return
	end
	if not bar:IsShown() then return end
	local current = bar:GetValue() or 0
	local diff = bar._smoothTarget - current
	local dz = bar._smoothDeadzone or DEFAULT_SMOOTH_DEADZONE
	if abs(diff) > dz then
		if bar:GetScript("OnUpdate") ~= bar._smoothUpdater then bar:SetScript("OnUpdate", bar._smoothUpdater) end
		bar._smoothActive = true
	else
		if abs(diff) > 0 then bar:SetValue(bar._smoothTarget) end
		stopSmoothUpdater(bar)
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

local function deactivateRuneTicker(bar)
	if not bar then return end
	if bar:GetScript("OnUpdate") == bar._runeUpdater then bar:SetScript("OnUpdate", nil) end
	bar._runesAnimating = false
	bar._runeAccum = 0
	bar._runeUpdateInterval = nil
end

local textureListCache = {
	dirty = true,
}

local function markTextureListDirty() textureListCache.dirty = true end

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

local function trim(str)
	if type(str) ~= "string" then return str end
	return str:match("^%s*(.-)%s*$")
end

local function notifyUser(msg)
	if not msg or msg == "" then return end
	print("|cff00ff98Enhance QoL|r: " .. tostring(msg))
end

local function specNameByIndex(specIndex)
	local classID = addon.variables.unitClassID
	if not classID or not GetSpecializationInfoForClassID or not specIndex then return nil end
	local _, specName = GetSpecializationInfoForClassID(classID, specIndex)
	return specName
end

local function exportResourceProfile(scopeKey)
	scopeKey = scopeKey or "ALL"
	local classKey = addon.variables.unitClass
	if not classKey then return nil, "NO_CLASS" end
	addon.db.personalResourceBarSettings = addon.db.personalResourceBarSettings or {}
	local classConfig = addon.db.personalResourceBarSettings[classKey]
	if type(classConfig) ~= "table" then return nil, "NO_DATA" end

	local payload = {
		kind = RESOURCE_SHARE_KIND,
		version = 1,
		class = classKey,
		enableResourceFrame = addon.db["enableResourceFrame"] and true or false,
		specs = {},
		specNames = {},
	}

	if scopeKey == "ALL" then
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

	if data.kind ~= RESOURCE_SHARE_KIND then return false, "WRONG_KIND" end
	if data.class and data.class ~= addon.variables.unitClass then return false, "WRONG_CLASS", data.class end

	local specs = data.specs
	if type(specs) ~= "table" then return false, "NO_SPECS" end

	addon.db.personalResourceBarSettings = addon.db.personalResourceBarSettings or {}
	local classKey = addon.variables.unitClass
	addon.db.personalResourceBarSettings[classKey] = addon.db.personalResourceBarSettings[classKey] or {}
	local classConfig = addon.db.personalResourceBarSettings[classKey]
	local applied = {}

	local enableState = data.enableResourceFrame
	if scopeKey == "ALL" then
		for specIndex, specCfg in pairs(specs) do
			local idx = tonumber(specIndex)
			if idx and type(specCfg) == "table" then
				classConfig[idx] = CopyTable(specCfg)
				applied[#applied + 1] = idx
			end
		end
		if #applied == 0 then return false, "NO_SPECS" end
	else
		local targetIndex = tonumber(scopeKey)
		if not targetIndex then return false, "NO_SPEC" end
		local sourceCfg = specs[targetIndex] or specs[tostring(targetIndex)]
		if type(sourceCfg) ~= "table" then return false, "SPEC_MISMATCH" end
		classConfig[targetIndex] = CopyTable(sourceCfg)
		applied[#applied + 1] = targetIndex
	end

	tsort(applied)
	return true, applied, enableState
end

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
		[BLIZZARD_TEX] = "Blizzard: UI-StatusBar",
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
	textureListCache.noDefaultList = sortedNoDefault
	textureListCache.noDefaultOrder = orderNoDefault
	textureListCache.fullList = sortedWithDefault
	textureListCache.fullOrder = orderWithDefault
	textureListCache.dirty = false
end

getStatusbarDropdownLists = function(includeDefault)
	if textureListCache.dirty or not textureListCache.fullList then rebuildTextureCache() end
	if includeDefault then return cloneMap(textureListCache.fullList), cloneArray(textureListCache.fullOrder) end
	return cloneMap(textureListCache.noDefaultList), cloneArray(textureListCache.noDefaultOrder)
end

-- Detect Atlas: /run local t=PlayerFrame_GetManaBar():GetStatusBarTexture(); print("tex:", t:GetTexture(), "atlas:", t:GetAtlas()); local a,b,c,d,e,f,g,h=t:GetTexCoord(); print("tc:",a,b,c,d,e,f,g,h)
-- Healthbar: /run local t=PlayerFrame_GetHealthBar():GetStatusBarTexture(); print("tex:", t:GetTexture(), "atlas:", t:GetAtlas()); local a,b,c,d,e,f,g,h=t:GetTexCoord(); print("tc:",a,b,c,d,e,f,g,h)

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

local function configureSpecialTexture(bar, pType, cfg)
	if not bar then return end
	local atlas = atlasByPower[pType]
	if not atlas then return end
	cfg = cfg or bar._cfg
	if cfg and cfg.barTexture and cfg.barTexture ~= "" and cfg.barTexture ~= "DEFAULT" then return end
	local tex = bar:GetStatusBarTexture()
	if tex and tex.SetAtlas then
		local currentAtlas = tex.GetAtlas and tex:GetAtlas()
		if currentAtlas ~= atlas then tex:SetAtlas(atlas, true) end
		if tex.SetHorizTile then tex:SetHorizTile(false) end
		if tex.SetVertTile then tex:SetVertTile(false) end
		local shouldNormalize = true
		if cfg then
			if cfg.useBarColor == true then shouldNormalize = false end
			if cfg.useMaxColor == true and bar._usingMaxColor then shouldNormalize = false end
		end
		if shouldNormalize then
			bar:SetStatusBarColor(1, 1, 1, 1)
			bar._baseColor = bar._baseColor or {}
			bar._baseColor[1], bar._baseColor[2], bar._baseColor[3], bar._baseColor[4] = 1, 1, 1, 1
			bar._lastColor = bar._lastColor or {}
			bar._lastColor[1], bar._lastColor[2], bar._lastColor[3], bar._lastColor[4] = 1, 1, 1, 1
			bar._usingMaxColor = false
		end
	end
end

local function isValidStatusbarPath(path)
	if not path or type(path) ~= "string" or path == "" then return false end
	if path == BLIZZARD_TEX then return true end
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
	if sel == nil or sel == "DEFAULT" or not isValidStatusbarPath(sel) then return DEFAULT_RB_TEX end
	return sel
end

local function isEQOLFrameName(name)
	if name == "EQOLHealthBar" then return true end
	return type(name) == "string" and name:match("^EQOL.+Bar$")
end
-- Fixed, non-DB defaults
local DEFAULT_HEALTH_WIDTH = 200
local DEFAULT_HEALTH_HEIGHT = 20
local DEFAULT_POWER_WIDTH = 200
local DEFAULT_POWER_HEIGHT = 20

local function resolveFontFace(cfg)
	if cfg and cfg.fontFace and cfg.fontFace ~= "" then return cfg.fontFace end
	return addon.variables.defaultFont
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
		fs:SetFont(addon.variables.defaultFont, size, fallbackOutline)
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

-- Statusbar content inset controller
local ZERO_INSETS = { left = 0, right = 0, top = 0, bottom = 0 }

local function copyInsetValues(src, dest)
	dest = dest or {}
	dest.left = src.left or 0
	dest.right = src.right or 0
	dest.top = src.top or 0
	dest.bottom = src.bottom or 0
	return dest
end

local function resolveInnerInset(bd) return ZERO_INSETS end

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

local function applyStatusBarInsets(frame, inset, force)
	if not frame then return end
	inset = inset or ZERO_INSETS
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
		frame.absorbBar:ClearAllPoints()
		frame.absorbBar:SetPoint("TOPLEFT", inner, "TOPLEFT")
		frame.absorbBar:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT")
		alignTexture(frame.absorbBar, frame.absorbBar)
	end

	frame._rbContentInset = frame._rbContentInset or {}
	frame._rbContentInset.left = l
	frame._rbContentInset.right = r
	frame._rbContentInset.top = t
	frame._rbContentInset.bottom = b

	if frame.separatorMarks then
		frame._sepW, frame._sepH, frame._sepSegments = nil, nil, nil
	end
	if frame._rbType then updateBarSeparators(frame._rbType) end
	if frame.runes then layoutRunes(frame) end
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
	local contentInset = ZERO_INSETS
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
		if bd.borderTexture and bd.borderTexture ~= "" and (bd.edgeSize or 0) > 0 then
			local borderTexture = bd.borderTexture or "Interface\\Tooltips\\UI-Tooltip-Border"
			local edgeSize = bd.edgeSize or 3
			if state.borderTexture ~= borderTexture or state.borderEdgeSize ~= edgeSize then
				borderFrame:SetBackdrop({
					bgFile = nil,
					edgeFile = borderTexture,
					tile = false,
					edgeSize = edgeSize,
					insets = { left = 0, right = 0, top = 0, bottom = 0 },
				})
				state.borderTexture = borderTexture
				state.borderEdgeSize = edgeSize
			end
			local boc = bd.borderColor or { 0, 0, 0, 0 }
			local cr, cg, cb, ca = boc[1] or 0, boc[2] or 0, boc[3] or 0, boc[4] or 1
			if state.borderR ~= cr or state.borderG ~= cg or state.borderB ~= cb or state.borderA ~= ca then
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
	bar.text:ClearAllPoints()
	bar.text:SetPoint("CENTER", bar, "CENTER", ox, oy)
end

local function applyBarFillColor(bar, cfg, pType)
	if not bar then return end
	cfg = cfg or {}
	local r, g, b, a
	local shouldDesaturate = false
	if pType == "HEALTH" and cfg.useClassColor == true then
		r, g, b, a = getPlayerClassColor()
		a = a or (cfg.barColor and cfg.barColor[4]) or 1
		shouldDesaturate = true
	elseif cfg.useBarColor then
		local color = cfg.barColor or WHITE
		r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
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
	configureSpecialTexture(bar, pType, cfg)
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
	end

	if pType ~= "RUNES" then
		ensureSmoothVisibilityHooks(bar)
		if cfg.smoothFill then
			bar._smoothEnabled = true
			bar._smoothDeadzone = cfg.smoothDeadzone or DEFAULT_SMOOTH_DEADZONE
			bar._smoothSpeed = SMOOTH_SPEED
			ensureSmoothUpdater(bar)
		else
			bar._smoothEnabled = false
			bar._smoothDeadzone = cfg.smoothDeadzone or DEFAULT_SMOOTH_DEADZONE
			bar._smoothSpeed = SMOOTH_SPEED
			bar._smoothTarget = nil
			stopSmoothUpdater(bar)
		end
	else
		stopSmoothUpdater(bar)
	end

	if bar._rbBackdropState and bar._rbBackdropState.insets then applyStatusBarInsets(bar, bar._rbBackdropState.insets, true) end
end

local function Snap(bar, off)
	local s = bar:GetEffectiveScale() or 1
	return floor(off * s + 0.5) / s
end

local FREQUENT = { ENERGY = true, FOCUS = true, RAGE = true, RUNIC_POWER = true, LUNAR_POWER = true }
local formIndexToKey = {
	[0] = "HUMANOID",
	[1] = "BEAR",
	[2] = "CAT",
	[3] = "TRAVEL",
	[4] = "MOONKIN",
	[5] = "TREANT",
	[6] = "STAG",
}
local formKeyToIndex = {}
local druidStanceOrder = {}
for idx, key in pairs(formIndexToKey) do
	formKeyToIndex[key] = idx
	if type(idx) == "number" and idx > 0 then druidStanceOrder[#druidStanceOrder + 1] = idx end
end
tsort(druidStanceOrder)
local druidStanceString = table.concat(druidStanceOrder, "/")
local DRUID_HUMANOID_VISIBILITY_CLAUSE = (druidStanceString and druidStanceString ~= "") and ("[combat,nostance:%s] show"):format(druidStanceString) or "[combat] show"
local DRUID_FORM_SEQUENCE = { "HUMANOID", "BEAR", "CAT", "TRAVEL", "MOONKIN", "TREANT", "STAG" }
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
	if name:find("treant") then return "TREANT" end
	if name:find("stag") then return "STAG" end
	return nil
end

local DK_SPEC_COLOR = {
	[1] = { 0.8, 0.1, 0.1 },
	[2] = { 0.2, 0.6, 1.0 },
	[3] = { 0.0, 0.9, 0.3 },
}

function addon.Aura.functions.addResourceFrame(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	groupCore:SetTitle(L["Resource Bars"])
	wrapper:AddChild(groupCore)

	local data = {
		{
			text = L["Enable Resource frame"],
			var = "enableResourceFrame",
			func = function(self, _, value)
				addon.db["enableResourceFrame"] = value
				if value then
					addon.Aura.ResourceBars.EnableResourceBars()
				elseif addon.Aura.ResourceBars and addon.Aura.ResourceBars.DisableResourceBars then
					addon.Aura.ResourceBars.DisableResourceBars()
				end
				-- Rebuild the options UI to reflect enabled/disabled state
				if container and container.ReleaseChildren then
					container:ReleaseChildren()
					-- Defer rebuild slightly to ensure enable/disable side effects settle
					if After then
						After(0, function()
							if addon and addon.Aura and addon.Aura.functions and addon.Aura.functions.addResourceFrame then addon.Aura.functions.addResourceFrame(container) end
						end)
					else
						if addon and addon.Aura and addon.Aura.functions and addon.Aura.functions.addResourceFrame then addon.Aura.functions.addResourceFrame(container) end
					end
				end
			end,
		},
		{
			text = L["Hide out of combat"] or "Hide resource bars out of combat",
			var = "resourceBarsHideOutOfCombat",
			func = function(self, _, value)
				addon.db["resourceBarsHideOutOfCombat"] = value and true or false
				if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ApplyVisibilityPreference then addon.Aura.ResourceBars.ApplyVisibilityPreference() end
			end,
		},
		{
			text = L["Hide when mounted"] or "Hide resource bars while mounted",
			var = "resourceBarsHideMounted",
			func = function(self, _, value)
				addon.db["resourceBarsHideMounted"] = value and true or false
				if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ApplyVisibilityPreference then addon.Aura.ResourceBars.ApplyVisibilityPreference() end
			end,
		},
		{
			text = L["Hide in vehicles"] or "Hide resource bars in vehicles",
			var = "resourceBarsHideVehicle",
			func = function(self, _, value)
				addon.db["resourceBarsHideVehicle"] = value and true or false
				if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ApplyVisibilityPreference then addon.Aura.ResourceBars.ApplyVisibilityPreference() end
			end,
		},
	}

	tsort(data, function(a, b) return a.text < b.text end)

	for _, cbData in ipairs(data) do
		local uFunc = function(self, _, value) addon.db[cbData.var] = value end
		if cbData.func then uFunc = cbData.func end
		local cbElement = addon.functions.createCheckboxAce(cbData.text, addon.db[cbData.var], uFunc)
		groupCore:AddChild(cbElement)
	end

	local specTabs = {}
	if addon.variables.unitClassID and GetNumSpecializationsForClassID then
		for i = 1, (GetNumSpecializationsForClassID(addon.variables.unitClassID) or 0) do
			local _, specName = GetSpecializationInfoForClassID(addon.variables.unitClassID, i)
			tinsert(specTabs, { text = specName, value = i })
		end
	end

	if #specTabs > 0 then
		local classKey = addon.variables.unitClass or "UNKNOWN"
		lastProfileShareScope[classKey] = lastProfileShareScope[classKey] or "ALL"

		local scopeList, scopeOrder = {}, {}
		scopeList.ALL = L["All specs"] or "All specs"
		scopeOrder[1] = "ALL"
		for _, tab in ipairs(specTabs) do
			local key = tostring(tab.value)
			scopeList[key] = tab.text
			scopeOrder[#scopeOrder + 1] = key
		end
		if not scopeList[lastProfileShareScope[classKey]] then lastProfileShareScope[classKey] = "ALL" end

		local shareRow = addon.functions.createContainer("SimpleGroup", "Flow")
		shareRow:SetFullWidth(true)
		groupCore:AddChild(shareRow)

		local scopeDropdown = addon.functions.createDropdownAce(L["ProfileScope"] or "Apply to", scopeList, scopeOrder, function(_, _, key) lastProfileShareScope[classKey] = key end)
		scopeDropdown:SetFullWidth(false)
		scopeDropdown:SetRelativeWidth(0.5)
		scopeDropdown:SetValue(lastProfileShareScope[classKey])
		shareRow:AddChild(scopeDropdown)

		local exportBtn = addon.functions.createButtonAce(L["Export"] or "Export", 120, function()
			local scopeKey = lastProfileShareScope[classKey] or "ALL"
			local code, reason = exportResourceProfile(scopeKey)
			if not code then
				notifyUser(exportErrorMessage(reason))
				return
			end
			StaticPopupDialogs["EQOL_RESOURCEBAR_EXPORT"] = StaticPopupDialogs["EQOL_RESOURCEBAR_EXPORT"]
				or {
					text = L["ExportProfileTitle"] or "Export Resource Bars",
					button1 = CLOSE,
					hasEditBox = true,
					editBoxWidth = 320,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				}
			StaticPopupDialogs["EQOL_RESOURCEBAR_EXPORT"].OnShow = function(self)
				self:SetFrameStrata("TOOLTIP")
				local editBox = self.editBox or self:GetEditBox()
				editBox:SetText(code)
				editBox:HighlightText()
				editBox:SetFocus()
			end
			StaticPopup_Show("EQOL_RESOURCEBAR_EXPORT")
		end)
		exportBtn:SetFullWidth(false)
		exportBtn:SetRelativeWidth(0.25)
		shareRow:AddChild(exportBtn)

		local importBtn = addon.functions.createButtonAce(L["Import"] or "Import", 120, function()
			StaticPopupDialogs["EQOL_RESOURCEBAR_IMPORT"] = StaticPopupDialogs["EQOL_RESOURCEBAR_IMPORT"]
				or {
					text = L["ImportProfileTitle"] or "Import Resource Bars",
					button1 = OKAY,
					button2 = CANCEL,
					hasEditBox = true,
					editBoxWidth = 320,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				}
			StaticPopupDialogs["EQOL_RESOURCEBAR_IMPORT"].OnShow = function(self)
				self:SetFrameStrata("TOOLTIP")
				local editBox = self.editBox or self:GetEditBox()
				editBox:SetText("")
				editBox:SetFocus()
			end
			StaticPopupDialogs["EQOL_RESOURCEBAR_IMPORT"].EditBoxOnEnterPressed = function(editBox)
				local parent = editBox:GetParent()
				if parent and parent.button1 then parent.button1:Click() end
			end
			StaticPopupDialogs["EQOL_RESOURCEBAR_IMPORT"].OnAccept = function(self)
				local editBox = self.editBox or self:GetEditBox()
				local input = editBox:GetText() or ""
				local scopeKey = lastProfileShareScope[classKey] or "ALL"
				local ok, applied, enableState = importResourceProfile(input, scopeKey)
				if not ok then
					notifyUser(importErrorMessage(applied, enableState))
					return
				end
				if enableState ~= nil and scopeKey == "ALL" then
					local prev = addon.db["enableResourceFrame"]
					addon.db["enableResourceFrame"] = enableState and true or false
					if enableState and prev ~= true and addon.Aura.ResourceBars and addon.Aura.ResourceBars.EnableResourceBars then
						addon.Aura.ResourceBars.EnableResourceBars()
					elseif not enableState and prev ~= false and addon.Aura.ResourceBars and addon.Aura.ResourceBars.DisableResourceBars then
						addon.Aura.ResourceBars.DisableResourceBars()
					end
				end
				if applied then
					for _, specIndex in ipairs(applied) do
						requestActiveRefresh(specIndex)
					end
				end
				container:ReleaseChildren()
				addon.Aura.functions.addResourceFrame(container)
				if applied and #applied > 0 then
					local specNames = {}
					for _, specIndex in ipairs(applied) do
						specNames[#specNames + 1] = specNameByIndex(specIndex) or tostring(specIndex)
					end
					notifyUser((L["ImportProfileSuccess"] or "Resource Bars updated for: %s"):format(tconcat(specNames, ", ")))
				else
					notifyUser(L["ImportProfileSuccessGeneric"] or "Resource Bars profile imported.")
				end
			end
			StaticPopup_Show("EQOL_RESOURCEBAR_IMPORT")
		end)
		importBtn:SetFullWidth(false)
		importBtn:SetRelativeWidth(0.25)
		shareRow:AddChild(importBtn)
	end

	if addon.db["enableResourceFrame"] then
		-- No global defaults; everything is per-spec and per-bar below

		local anchorPoints = {
			TOPLEFT = "TOPLEFT",
			TOP = "TOP",
			TOPRIGHT = "TOPRIGHT",
			LEFT = "LEFT",
			CENTER = "CENTER",
			RIGHT = "RIGHT",
			BOTTOMLEFT = "BOTTOMLEFT",
			BOTTOM = "BOTTOM",
			BOTTOMRIGHT = "BOTTOMRIGHT",
		}
		local anchorOrder = {
			"TOPLEFT",
			"TOP",
			"TOPRIGHT",
			"LEFT",
			"CENTER",
			"RIGHT",
			"BOTTOMLEFT",
			"BOTTOM",
			"BOTTOMRIGHT",
		}

		local baseFrameList = {
			UIParent = "UIParent",
			PlayerFrame = "PlayerFrame",
			TargetFrame = "TargetFrame",
		}
		local extraAnchorFrames = {
			[COOLDOWN_VIEWER_FRAME_NAME] = COOLDOWN_VIEWER_FRAME_NAME,
			UtilityCooldownViewer = "UtilityCooldownViewer",
			BuffBarCooldownViewer = "BuffBarCooldownViewer",
			BuffIconCooldownViewer = "BuffIconCooldownViewer",
		}
		for name, label in pairs(extraAnchorFrames) do
			baseFrameList[name] = label
		end
		if addon.variables and addon.variables.actionBarNames then
			for _, info in ipairs(addon.variables.actionBarNames) do
				if info.name then baseFrameList[info.name] = info.text or info.name end
			end
		end

		local function displayNameForBarType(pType)
			if pType == "HEALTH" then return HEALTH end
			local s = _G["POWER_TYPE_" .. pType] or _G[pType]
			if type(s) == "string" and s ~= "" then return s end
			return pType
		end

		local buildSpec

		local function enforceMinWidthForSpec(barType, specIndex)
			if not barType then return nil end
			local class = addon.variables.unitClass
			local spec = specIndex or addon.variables.unitSpec
			if not class or not spec then return nil end
			addon.db.personalResourceBarSettings = addon.db.personalResourceBarSettings or {}
			addon.db.personalResourceBarSettings[class] = addon.db.personalResourceBarSettings[class] or {}
			addon.db.personalResourceBarSettings[class][spec] = addon.db.personalResourceBarSettings[class][spec] or {}
			addon.db.personalResourceBarSettings[class][spec][barType] = addon.db.personalResourceBarSettings[class][spec][barType] or {}
			local cfg = addon.db.personalResourceBarSettings[class][spec][barType]
			cfg.width = MIN_RESOURCE_BAR_WIDTH
			return cfg
		end

		local function addAnchorOptions(barType, parent, info, frameList, specIndex)
			info = info or {}
			frameList = frameList or baseFrameList

			local header = addon.functions.createLabelAce(format("%s %s", displayNameForBarType(barType), L["Anchor"]))
			parent:AddChild(header)

			-- Filter choices to avoid creating loops
			local function frameNameToBarType(fname)
				if fname == "EQOLHealthBar" then return "HEALTH" end
				return type(fname) == "string" and fname:match("^EQOL(.+)Bar$") or nil
			end
			local function wouldCauseLoop(fromType, candidateName)
				-- Always safe: UIParent and non-EQOL frames
				if candidateName == "UIParent" then return false end
				local candType = frameNameToBarType(candidateName)
				if not candType then return false end
				-- Direct self-reference
				if candType == fromType then return true end
				-- Follow anchors from candidate; if we reach fromType's frame, it would loop
				local seen = {}
				local name = candidateName
				local limit = 10
				local targetFrameName = (fromType == "HEALTH") and "EQOLHealthBar" or ("EQOL" .. fromType .. "Bar")
				while name and name ~= "UIParent" and limit > 0 do
					if seen[name] then break end
					seen[name] = true
					if name == targetFrameName then return true end
					local bt = frameNameToBarType(name)
					if not bt then break end
					local anch = getAnchor(bt, specIndex)
					name = anch and anch.relativeFrame or "UIParent"
					limit = limit - 1
				end
				return false
			end

			local filtered = {}
			for k, v in pairs(frameList) do
				if not wouldCauseLoop(barType, k) then filtered[k] = v end
			end
			-- Ensure UIParent is always present
			filtered.UIParent = frameList.UIParent or "UIParent"

			-- Sub-group we can rebuild when relative frame changes
			local anchorSub = addon.functions.createContainer("SimpleGroup", "Flow")
			parent:AddChild(anchorSub)

			local function buildAnchorSub()
				anchorSub:ReleaseChildren()
				info.point = info.point or "TOPLEFT"
				info.relativePoint = info.relativePoint or info.point or "TOPLEFT"
				info.x = info.x or 0
				info.y = info.y or 0
				if (info.relativeFrame or "UIParent") == "UIParent" then info.autoSpacing = nil end

				local stackSpacing = DEFAULT_STACK_SPACING
				if info.autoSpacing and (info.relativeFrame or "UIParent") ~= "UIParent" then
					info.x = 0
					info.y = stackSpacing
				end

				-- Row for Relative Frame, Point, Relative Point (each 33%)
				local row = addon.functions.createContainer("SimpleGroup", "Flow")
				row:SetFullWidth(true)

				local initial = info.relativeFrame or "UIParent"
				if not filtered[initial] then initial = "UIParent" end
				-- Ensure DB reflects a valid selection
				info.relativeFrame = initial
				if (info.relativeFrame or "UIParent") == "UIParent" then info.matchRelativeWidth = nil end
				local dropFrame = addon.functions.createDropdownAce(L["Relative Frame"], filtered, nil, nil)
				dropFrame:SetValue(initial)
				dropFrame:SetFullWidth(false)
				dropFrame:SetRelativeWidth(0.333)
				row:AddChild(dropFrame)

				local relName = info.relativeFrame or "UIParent"
				local dropPoint = addon.functions.createDropdownAce(RESAMPLE_QUALITY_POINT, anchorPoints, anchorOrder, nil)
				dropPoint:SetValue(info.point or "TOPLEFT")
				dropPoint:SetFullWidth(false)
				dropPoint:SetRelativeWidth(0.333)
				row:AddChild(dropPoint)

				local dropRelPoint = addon.functions.createDropdownAce(L["Relative Point"], anchorPoints, anchorOrder, nil)
				dropRelPoint:SetValue(info.relativePoint or info.point or "TOPLEFT")
				dropRelPoint:SetFullWidth(false)
				dropRelPoint:SetRelativeWidth(0.333)
				row:AddChild(dropRelPoint)

				anchorSub:AddChild(row)

				-- Offset sliders (X/Y)
				local offsetRow = addon.functions.createContainer("SimpleGroup", "Flow")
				offsetRow:SetFullWidth(true)
				info.x = info.x or 0
				info.y = info.y or 0

				local sliderX = addon.functions.createSliderAce(L["X"] or "X", info.x, -1000, 1000, 1, function(_, _, val)
					info.autoSpacing = false
					info.x = val
					requestActiveRefresh(specIndex, REANCHOR_REFRESH)
				end)
				sliderX:SetFullWidth(false)
				sliderX:SetRelativeWidth(0.5)
				sliderX:SetValue(info.x)
				offsetRow:AddChild(sliderX)

				local sliderY = addon.functions.createSliderAce(L["Y"] or "Y", info.y, -1000, 1000, 1, function(_, _, val)
					info.autoSpacing = false
					info.y = val
					requestActiveRefresh(specIndex, REANCHOR_REFRESH)
				end)
				sliderY:SetFullWidth(false)
				sliderY:SetRelativeWidth(0.5)
				sliderY:SetValue(info.y)
				offsetRow:AddChild(sliderY)
				anchorSub:AddChild(offsetRow)

				if (info.relativeFrame or "UIParent") ~= "UIParent" then
					local cbMatch = addon.functions.createCheckboxAce(L["MatchRelativeFrameWidth"] or "Match Relative Frame width", info.matchRelativeWidth == true, function(_, _, val)
						info.matchRelativeWidth = val and true or nil
						if info.matchRelativeWidth then ensureRelativeFrameHooks(info.relativeFrame) end
						if val then
							local cfg = enforceMinWidthForSpec(barType, specIndex)
							if specIndex == addon.variables.unitSpec then
								local defH = (barType == "HEALTH") and (cfg and cfg.height or DEFAULT_HEALTH_HEIGHT) or (cfg and cfg.height or DEFAULT_POWER_HEIGHT)
								if barType == "HEALTH" then
									if addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.SetHealthBarSize then
										addon.Aura.ResourceBars.SetHealthBarSize(MIN_RESOURCE_BAR_WIDTH, defH)
									end
								else
									if addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.SetPowerBarSize then
										addon.Aura.ResourceBars.SetPowerBarSize(MIN_RESOURCE_BAR_WIDTH, defH, barType)
									end
								end
							end
						end
						if
							ResourceBars
							and ResourceBars.ui
							and ResourceBars.ui.barWidthSliders
							and ResourceBars.ui.barWidthSliders[specIndex]
							and ResourceBars.ui.barWidthSliders[specIndex][barType]
						then
							local slider = ResourceBars.ui.barWidthSliders[specIndex][barType]
							slider:SetDisabled(info.matchRelativeWidth == true)
							if info.matchRelativeWidth then slider:SetValue(MIN_RESOURCE_BAR_WIDTH) end
						end
						requestActiveRefresh(specIndex, REANCHOR_REFRESH)
						if ResourceBars and ResourceBars.SyncRelativeFrameWidths then ResourceBars.SyncRelativeFrameWidths() end
					end)
					cbMatch:SetFullWidth(true)
					anchorSub:AddChild(cbMatch)
				else
					info.matchRelativeWidth = nil
				end

				if (info.relativeFrame or "UIParent") == "UIParent" then
					local hint = addon.functions.createLabelAce(L["Movable while holding SHIFT"], nil, nil, 10)
					anchorSub:AddChild(hint)
				end

				-- Callback for Relative Frame change (rebuild the sub UI on selection)
				local function onFrameChanged(self, _, val)
					local prev = info.relativeFrame or "UIParent"
					info.relativeFrame = val
					if val ~= "UIParent" then
						info.point = "TOPLEFT"
						info.relativePoint = "BOTTOMLEFT"
						info.x = 0
						info.y = stackSpacing
						info.autoSpacing = true
					end
					if val == "UIParent" and prev ~= "UIParent" then
						info.point = "CENTER"
						info.relativePoint = "CENTER"
						info.x = 0
						info.y = 0
						info.autoSpacing = nil
					end
					if val ~= "UIParent" then
						if info.matchRelativeWidth then ensureRelativeFrameHooks(val) end
					else
						info.matchRelativeWidth = nil
					end
					buildAnchorSub()
					requestActiveRefresh(specIndex, REANCHOR_REFRESH)
					if ResourceBars and ResourceBars.ui and ResourceBars.ui.barWidthSliders and ResourceBars.ui.barWidthSliders[specIndex] and ResourceBars.ui.barWidthSliders[specIndex][barType] then
						local slider = ResourceBars.ui.barWidthSliders[specIndex][barType]
						slider:SetDisabled(info.matchRelativeWidth == true)
						if info.matchRelativeWidth then slider:SetValue(MIN_RESOURCE_BAR_WIDTH) end
					end
				end

				dropFrame:SetCallback("OnValueChanged", onFrameChanged)
				dropPoint:SetCallback("OnValueChanged", function(self, _, val)
					info.autoSpacing = false
					info.point = val
					info.relativePoint = info.relativePoint or val
					requestActiveRefresh(specIndex, REANCHOR_REFRESH)
				end)
				dropRelPoint:SetCallback("OnValueChanged", function(self, _, val)
					info.autoSpacing = false
					info.relativePoint = val
					requestActiveRefresh(specIndex, REANCHOR_REFRESH)
				end)
			end

			-- Initial build
			buildAnchorSub()

			parent:AddChild(addon.functions.createSpacerAce())
		end

		local tabGroup = addon.functions.createContainer("TabGroup", "Flow")
		buildSpec = function(container, specIndex)
			container:ReleaseChildren()
			if not addon.Aura.ResourceBars.powertypeClasses[addon.variables.unitClass] then return end
			local specInfo = addon.Aura.ResourceBars.powertypeClasses[addon.variables.unitClass][specIndex]
			if not specInfo then return end

			addon.db.personalResourceBarSettings[addon.variables.unitClass] = addon.db.personalResourceBarSettings[addon.variables.unitClass] or {}
			addon.db.personalResourceBarSettings[addon.variables.unitClass][specIndex] = addon.db.personalResourceBarSettings[addon.variables.unitClass][specIndex] or {}
			local dbSpec = addon.db.personalResourceBarSettings[addon.variables.unitClass][specIndex]

			-- Gather available bars
			local available = { HEALTH = true }
			for _, pType in ipairs(addon.Aura.ResourceBars.classPowerTypes) do
				if specInfo.MAIN == pType or specInfo[pType] then available[pType] = true end
			end

			-- Ensure DB defaults
			for pType in pairs(available) do
				if pType ~= "HEALTH" then
					dbSpec[pType] = dbSpec[pType]
						or {
							enabled = false,
							width = DEFAULT_POWER_WIDTH,
							height = DEFAULT_POWER_HEIGHT,
							textStyle = pType == "MANA" and "PERCENT" or "CURMAX",
							fontSize = 16,
							fontFace = addon.variables.defaultFont,
							fontOutline = "OUTLINE",
							fontColor = { 1, 1, 1, 1 },
							backdrop = {
								enabled = true,
								backgroundTexture = "Interface\\DialogFrame\\UI-DialogBox-Background",
								backgroundColor = { 0, 0, 0, 0.8 },
								borderTexture = "Interface\\Tooltips\\UI-Tooltip-Border",
								borderColor = { 0, 0, 0, 0 },
								edgeSize = 3,
								outset = 0,
							},
							textOffset = { x = 0, y = 0 },
							useBarColor = false,
							barColor = { 1, 1, 1, 1 },
							useMaxColor = false,
							maxColor = { 1, 1, 1, 1 },
							showSeparator = false,
							separatorColor = { 1, 1, 1, 0.5 },
							separatorThickness = SEPARATOR_THICKNESS,
							showCooldownText = false,
							cooldownTextFontSize = 16,
							reverseFill = false,
							verticalFill = false,
							smoothFill = false,
						}
					dbSpec[pType].anchor = dbSpec[pType].anchor or {}
				end
			end

			-- Compact toggles (including Health)
			local groupToggles = addon.functions.createContainer("InlineGroup", "Flow")
			groupToggles:SetTitle(L["Bars to show"])
			container:AddChild(groupToggles)
			-- Ensure HEALTH spec config exists
			dbSpec.HEALTH = dbSpec.HEALTH
				or {
					enabled = false,
					width = DEFAULT_HEALTH_WIDTH,
					height = DEFAULT_HEALTH_HEIGHT,
					textStyle = "PERCENT",
					fontSize = 16,
					fontFace = addon.variables.defaultFont,
					fontOutline = "OUTLINE",
					fontColor = { 1, 1, 1, 1 },
					backdrop = {
						enabled = true,
						backgroundTexture = "Interface\\DialogFrame\\UI-DialogBox-Background",
						backgroundColor = { 0, 0, 0, 0.8 },
						borderTexture = "Interface\\Tooltips\\UI-Tooltip-Border",
						borderColor = { 0, 0, 0, 0 },
						edgeSize = 3,
						outset = 0,
					},
					textOffset = { x = 0, y = 0 },
					useBarColor = false,
					useClassColor = false,
					barColor = { 1, 1, 1, 1 },
					useMaxColor = false,
					maxColor = { 1, 1, 1, 1 },
					reverseFill = false,
					verticalFill = false,
					smoothFill = false,
					anchor = {},
				}
			local specKey = tostring(specIndex)
			local function fontDropdownData()
				local map = {
					[addon.variables.defaultFont] = L["Default"] or "Default",
				}
				for name, path in pairs(LSM and LSM:HashTable("font") or {}) do
					if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
				end
				return addon.functions.prepareListForDropdown(map)
			end

			local function borderDropdownData()
				local map = {
					["Interface\\Tooltips\\UI-Tooltip-Border"] = "Tooltip Border",
				}
				for name, path in pairs(LSM and LSM:HashTable("border") or {}) do
					if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
				end
				return addon.functions.prepareListForDropdown(map)
			end

			local function backgroundDropdownData()
				local map = {
					["Interface\\DialogFrame\\UI-DialogBox-Background"] = "Dialog Background",
					["Interface\\Buttons\\WHITE8x8"] = "Solid (tintable)",
				}
				for name, path in pairs(LSM and LSM:HashTable("background") or {}) do
					if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
				end
				return addon.functions.prepareListForDropdown(map)
			end

			local outlineMap = {
				NONE = L["None"] or NONE,
				OUTLINE = L["Outline"] or "Outline",
				THICKOUTLINE = L["Thick Outline"] or "Thick Outline",
				MONOCHROMEOUTLINE = L["Monochrome Outline"] or "Monochrome Outline",
			}
			local outlineOrder = { "NONE", "OUTLINE", "THICKOUTLINE", "MONOCHROMEOUTLINE" }

			local function addFontControls(parent, cfg)
				local list, order = fontDropdownData()
				local fontRow = addon.functions.createContainer("SimpleGroup", "Flow")
				fontRow:SetFullWidth(true)
				local dropFont = addon.functions.createDropdownAce(L["Font"] or "Font", list, order, function(_, _, key)
					cfg.fontFace = key
					requestActiveRefresh(specIndex)
				end)
				local curFont = cfg.fontFace or addon.variables.defaultFont
				if not list[curFont] then curFont = addon.variables.defaultFont end
				dropFont:SetValue(curFont)
				dropFont:SetFullWidth(false)
				dropFont:SetRelativeWidth(0.5)
				fontRow:AddChild(dropFont)

				local dropOutline = addon.functions.createDropdownAce(L["Font outline"] or "Font outline", outlineMap, outlineOrder, function(_, _, key)
					cfg.fontOutline = key
					requestActiveRefresh(specIndex)
				end)
				dropOutline:SetValue(cfg.fontOutline or "OUTLINE")
				dropOutline:SetFullWidth(false)
				dropOutline:SetRelativeWidth(0.5)
				fontRow:AddChild(dropOutline)
				parent:AddChild(fontRow)

				local colorRow = addon.functions.createContainer("SimpleGroup", "Flow")
				colorRow:SetFullWidth(true)
				local color = AceGUI:Create("ColorPicker")
				color:SetLabel(L["Font color"] or "Font color")
				color:SetHasAlpha(true)
				local fc = cfg.fontColor or { 1, 1, 1, 1 }
				color:SetColor(fc[1] or 1, fc[2] or 1, fc[3] or 1, fc[4] or 1)
				color:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
					cfg.fontColor = { r, g, b, a }
					requestActiveRefresh(specIndex)
				end)
				color:SetFullWidth(false)
				color:SetRelativeWidth(0.5)
				colorRow:AddChild(color)
				parent:AddChild(colorRow)
			end

			local function addBackdropControls(parent, cfg, pType)
				cfg.backdrop = cfg.backdrop or {}
				if cfg.backdrop.enabled == nil then cfg.backdrop.enabled = true end
				cfg.backdrop.backgroundTexture = cfg.backdrop.backgroundTexture or "Interface\\DialogFrame\\UI-DialogBox-Background"
				cfg.backdrop.backgroundColor = cfg.backdrop.backgroundColor or { 0, 0, 0, 0.8 }
				cfg.backdrop.borderTexture = cfg.backdrop.borderTexture or "Interface\\Tooltips\\UI-Tooltip-Border"
				cfg.backdrop.borderColor = cfg.backdrop.borderColor or { 0, 0, 0, 0 }
				cfg.backdrop.edgeSize = cfg.backdrop.edgeSize or 3
				cfg.backdrop.outset = cfg.backdrop.outset or 0
				cfg.backdrop.backgroundInset = max(0, cfg.backdrop.backgroundInset or 0)
				cfg.backdrop.innerPadding = nil

				local group = addon.functions.createContainer("InlineGroup", "Flow")
				group:SetTitle(L["Frame & Background"] or "Frame & Background")
				group:SetFullWidth(true)
				parent:AddChild(group)

				local dropBg, bgColor, dropBorder, borderColor, sliderEdge, sliderOutset, sliderBgInset

				local function applyInsetNow()
					if specIndex ~= addon.variables.unitSpec then return end
					if pType == "HEALTH" then
						if healthBar then applyBackdrop(healthBar, cfg) end
					elseif pType and powerbar[pType] then
						applyBackdrop(powerbar[pType], cfg)
					end
				end

				local function setDisabled(disable)
					if dropBg then dropBg:SetDisabled(disable) end
					if bgColor then bgColor:SetDisabled(disable) end
					if dropBorder then dropBorder:SetDisabled(disable) end
					if borderColor then borderColor:SetDisabled(disable) end
					if sliderEdge then sliderEdge:SetDisabled(disable) end
					if sliderOutset then sliderOutset:SetDisabled(disable) end
					if sliderBgInset then sliderBgInset:SetDisabled(disable) end
				end

				local cb = addon.functions.createCheckboxAce(L["Show backdrop"] or "Show backdrop", cfg.backdrop.enabled ~= false, function(_, _, val)
					cfg.backdrop.enabled = val and true or false
					setDisabled(cfg.backdrop.enabled == false)
					requestActiveRefresh(specIndex)
				end)
				cb:SetFullWidth(true)
				group:AddChild(cb)

				local bgList, bgOrder = backgroundDropdownData()
				dropBg = addon.functions.createDropdownAce(L["Background texture"] or "Background texture", bgList, bgOrder, function(_, _, key)
					cfg.backdrop.backgroundTexture = key
					requestActiveRefresh(specIndex)
				end)
				local curBg = cfg.backdrop.backgroundTexture
				if not bgList[curBg] then curBg = "Interface\\DialogFrame\\UI-DialogBox-Background" end
				dropBg:SetValue(curBg)
				dropBg:SetFullWidth(false)
				dropBg:SetRelativeWidth(0.5)
				group:AddChild(dropBg)

				bgColor = AceGUI:Create("ColorPicker")
				bgColor:SetLabel(L["Background color"] or "Background color")
				bgColor:SetHasAlpha(true)
				local bc = cfg.backdrop.backgroundColor or { 0, 0, 0, 0.8 }
				bgColor:SetColor(bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 0.8)
				bgColor:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
					cfg.backdrop.backgroundColor = { r, g, b, a }
					requestActiveRefresh(specIndex)
				end)
				bgColor:SetFullWidth(false)
				bgColor:SetRelativeWidth(0.5)
				group:AddChild(bgColor)

				local borderList, borderOrder = borderDropdownData()
				dropBorder = addon.functions.createDropdownAce(L["Border texture"] or "Border texture", borderList, borderOrder, function(_, _, key)
					cfg.backdrop.borderTexture = key
					requestActiveRefresh(specIndex)
				end)
				local curBorder = cfg.backdrop.borderTexture
				if not borderList[curBorder] then curBorder = "Interface\\Tooltips\\UI-Tooltip-Border" end
				dropBorder:SetValue(curBorder)
				dropBorder:SetFullWidth(false)
				dropBorder:SetRelativeWidth(0.5)
				group:AddChild(dropBorder)

				borderColor = AceGUI:Create("ColorPicker")
				borderColor:SetLabel(L["Border color"] or "Border color")
				borderColor:SetHasAlpha(true)
				local boc = cfg.backdrop.borderColor or { 0, 0, 0, 0 }
				borderColor:SetColor(boc[1] or 0, boc[2] or 0, boc[3] or 0, boc[4] or 0)
				borderColor:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
					cfg.backdrop.borderColor = { r, g, b, a }
					applyInsetNow()
					requestActiveRefresh(specIndex)
				end)
				borderColor:SetFullWidth(false)
				borderColor:SetRelativeWidth(0.5)
				group:AddChild(borderColor)

				sliderEdge = addon.functions.createSliderAce(L["Border size"] or "Border size", cfg.backdrop.edgeSize or 3, 0, 32, 1, function(_, _, val)
					cfg.backdrop.edgeSize = val
					cfg.backdrop.innerPadding = nil
					applyInsetNow()
					requestActiveRefresh(specIndex)
				end)
				sliderEdge:SetFullWidth(false)
				sliderEdge:SetRelativeWidth(0.5)
				group:AddChild(sliderEdge)

				sliderOutset = addon.functions.createSliderAce(L["Border offset"] or "Border offset", cfg.backdrop.outset or 0, 0, 32, 1, function(_, _, val)
					cfg.backdrop.outset = val
					applyInsetNow()
					requestActiveRefresh(specIndex)
				end)
				sliderOutset:SetFullWidth(false)
				sliderOutset:SetRelativeWidth(0.5)
				group:AddChild(sliderOutset)

				sliderBgInset = addon.functions.createSliderAce(L["Background inset"] or "Background inset", cfg.backdrop.backgroundInset or 0, 0, 64, 1, function(_, _, val)
					cfg.backdrop.backgroundInset = max(0, val)
					requestActiveRefresh(specIndex)
				end)
				sliderBgInset:SetFullWidth(true)
				group:AddChild(sliderBgInset)

				setDisabled(cfg.backdrop.enabled == false)
			end
			local function addTextOffsetControlsUI(parent, cfg, specIndex)
				local offsets = ensureTextOffsetTable(cfg)
				local row = addon.functions.createContainer("SimpleGroup", "Flow")
				row:SetFullWidth(true)
				local sliderX = addon.functions.createSliderAce(L["Text X Offset"] or "Text X Offset", offsets.x or 0, -200, 200, 1, function(_, _, val)
					offsets.x = val
					requestActiveRefresh(specIndex)
				end)
				sliderX:SetFullWidth(false)
				sliderX:SetRelativeWidth(0.5)
				row:AddChild(sliderX)

				local sliderY = addon.functions.createSliderAce(L["Text Y Offset"] or "Text Y Offset", offsets.y or 0, -200, 200, 1, function(_, _, val)
					offsets.y = val
					requestActiveRefresh(specIndex)
				end)
				sliderY:SetFullWidth(false)
				sliderY:SetRelativeWidth(0.5)
				row:AddChild(sliderY)

				parent:AddChild(row)
				return sliderX, sliderY
			end

			local function addColorControls(parent, cfg, specIndex, pType)
				cfg.barColor = cfg.barColor or { 1, 1, 1, 1 }
				cfg.maxColor = cfg.maxColor or { 1, 1, 1, 1 }
				local group = addon.functions.createContainer("InlineGroup", "Flow")
				group:SetTitle(L["Colors"] or "Colors")
				group:SetFullWidth(true)
				parent:AddChild(group)

				local function notifyRefresh()
					requestActiveRefresh(specIndex)
					if specIndex == addon.variables.unitSpec and forceColorUpdate then forceColorUpdate(pType) end
				end

				local colorPicker
				local maxColorPicker
				local maxColorCheckbox
				local customColorCheckbox
				local classColorCheckbox
				local suppressColorToggle = false
				local function refreshMaxColorControls()
					if maxColorPicker then maxColorPicker:SetDisabled(not (cfg.useMaxColor == true)) end
				end
				local function refreshColorPickerState()
					if colorPicker then colorPicker:SetDisabled(not (cfg.useBarColor == true) or cfg.useClassColor == true) end
				end
				local function syncCheckboxValue(widget, value)
					if not widget or not widget.GetValue or not widget.SetValue then return end
					if widget:GetValue() == value then return end
					suppressColorToggle = true
					widget:SetValue(value)
					suppressColorToggle = false
				end

				customColorCheckbox = addon.functions.createCheckboxAce(L["Use custom color"] or "Use custom color", cfg.useBarColor == true, function(_, _, val)
					if suppressColorToggle then return end
					cfg.useBarColor = val and true or false
					if cfg.useBarColor and cfg.useClassColor then
						cfg.useClassColor = false
						syncCheckboxValue(classColorCheckbox, false)
					end
					refreshColorPickerState()
					notifyRefresh()
				end)
				customColorCheckbox:SetFullWidth(true)
				group:AddChild(customColorCheckbox)

				colorPicker = AceGUI:Create("ColorPicker")
				colorPicker:SetLabel(L["Bar color"] or "Bar color")
				colorPicker:SetHasAlpha(true)
				local bc = cfg.barColor or { 1, 1, 1, 1 }
				colorPicker:SetColor(bc[1] or 1, bc[2] or 1, bc[3] or 1, bc[4] or 1)
				colorPicker:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
					cfg.barColor = { r, g, b, a }
					notifyRefresh()
				end)
				colorPicker:SetFullWidth(false)
				colorPicker:SetRelativeWidth(0.5)
				colorPicker:SetDisabled(not (cfg.useBarColor == true) or cfg.useClassColor == true)
				group:AddChild(colorPicker)

				if pType == "HEALTH" then
					classColorCheckbox = addon.functions.createCheckboxAce(L["Use class color"] or "Use class color", cfg.useClassColor == true, function(_, _, val)
						if suppressColorToggle then return end
						cfg.useClassColor = val and true or false
						if cfg.useClassColor and cfg.useBarColor then
							cfg.useBarColor = false
							syncCheckboxValue(customColorCheckbox, false)
						end
						refreshColorPickerState()
						notifyRefresh()
					end)
					classColorCheckbox:SetFullWidth(true)
					group:AddChild(classColorCheckbox)
				end

				if not addon.variables.isMidnight then
					maxColorCheckbox = addon.functions.createCheckboxAce(L["Use max color"] or "Use max color at maximum", cfg.useMaxColor == true, function(_, _, val)
						cfg.useMaxColor = val and true or false
						wasMax = nil
						refreshMaxColorControls()
						notifyRefresh()
					end)
					maxColorCheckbox:SetFullWidth(true)
					group:AddChild(maxColorCheckbox)

					maxColorPicker = AceGUI:Create("ColorPicker")
					maxColorPicker:SetLabel(L["Max color"] or "Max color")
					maxColorPicker:SetHasAlpha(true)
					local mc = cfg.maxColor or { 1, 1, 1, 1 }
					maxColorPicker:SetColor(mc[1] or 1, mc[2] or 1, mc[3] or 1, mc[4] or 1)
					maxColorPicker:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
						cfg.maxColor = { r, g, b, a }
						notifyRefresh()
					end)
					maxColorPicker:SetFullWidth(false)
					maxColorPicker:SetRelativeWidth(0.5)
					group:AddChild(maxColorPicker)

					refreshMaxColorControls()
				else
					cfg.useMaxColor = false
				end
				refreshColorPickerState()
			end

			local function addBehaviorControls(parent, cfg, pType)
				local group = addon.functions.createContainer("InlineGroup", "Flow")
				group:SetTitle(L["Behavior"] or "Behavior")
				group:SetFullWidth(true)
				parent:AddChild(group)

				local cbReverse = addon.functions.createCheckboxAce(L["Reverse fill"] or "Reverse fill", cfg.reverseFill == true, function(_, _, val)
					cfg.reverseFill = val and true or false
					requestActiveRefresh(specIndex)
				end)
				cbReverse:SetFullWidth(false)
				cbReverse:SetRelativeWidth(0.5)
				group:AddChild(cbReverse)

				if pType ~= "RUNES" then
					local cbVertical = addon.functions.createCheckboxAce(L["Vertical orientation"] or "Vertical orientation", cfg.verticalFill == true, function(_, _, val)
						local wasVertical = cfg.verticalFill == true
						local newVertical = val and true or false
						cfg.verticalFill = newVertical
						if wasVertical ~= newVertical then
							local defaultW = (pType == "HEALTH") and DEFAULT_HEALTH_WIDTH or DEFAULT_POWER_WIDTH
							local defaultH = (pType == "HEALTH") and DEFAULT_HEALTH_HEIGHT or DEFAULT_POWER_HEIGHT
							local curW = cfg.width or defaultW
							local curH = cfg.height or defaultH
							cfg.width, cfg.height = curH, curW
							if specIndex == addon.variables.unitSpec then
								if pType == "HEALTH" and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.SetHealthBarSize then
									addon.Aura.ResourceBars.SetHealthBarSize(cfg.width or defaultW, cfg.height or defaultH)
								elseif addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.SetPowerBarSize then
									addon.Aura.ResourceBars.SetPowerBarSize(cfg.width or defaultW, cfg.height or defaultH, pType)
								end
							end
						end
						requestActiveRefresh(specIndex)
						buildSpec(container, specIndex)
					end)
					cbVertical:SetFullWidth(false)
					cbVertical:SetRelativeWidth(0.5)
					group:AddChild(cbVertical)

					local cbSmooth = addon.functions.createCheckboxAce(L["Smooth fill"] or "Smooth fill", cfg.smoothFill == true, function(_, _, val)
						cfg.smoothFill = val and true or false
						requestActiveRefresh(specIndex)
					end)
					cbSmooth:SetFullWidth(false)
					cbSmooth:SetRelativeWidth(0.5)
					group:AddChild(cbSmooth)

					if (cfg.verticalFill == true) and (cfg.barTexture == nil or cfg.barTexture == "DEFAULT") then
						local warnText = L["VerticalTextureWarning"]
						local warnLabel = addon.functions.createLabelAce(warnText, nil, nil, 12)
						warnLabel:SetFullWidth(true)
						group:AddChild(warnLabel)
					end
				else
					-- Preserve flow layout when vertical option is hidden for RUNES
					local spacer = addon.functions.createLabelAce("")
					spacer:SetFullWidth(false)
					spacer:SetRelativeWidth(0.5)
					group:AddChild(spacer)
				end
			end
			do
				local hcfg = dbSpec.HEALTH
				local cbH = addon.functions.createCheckboxAce(HEALTH, hcfg.enabled == true, function(self, _, val)
					if (hcfg.enabled == true) and not val then addon.Aura.ResourceBars.DetachAnchorsFrom("HEALTH", specIndex) end
					hcfg.enabled = val
					requestActiveRefresh(specIndex)
					buildSpec(container, specIndex)
				end)
				cbH:SetFullWidth(false)
				cbH:SetRelativeWidth(0.33)
				groupToggles:AddChild(cbH)
			end
			for pType in pairs(available) do
				if pType ~= "HEALTH" then
					local cfg = dbSpec[pType]
					local label = _G["POWER_TYPE_" .. pType] or _G[pType] or pType
					local cb = addon.functions.createCheckboxAce(label, cfg.enabled == true, function(self, _, val)
						if (cfg.enabled == true) and not val then addon.Aura.ResourceBars.DetachAnchorsFrom(pType, specIndex) end
						cfg.enabled = val
						requestActiveRefresh(specIndex)
						buildSpec(container, specIndex)
					end)
					cb:SetFullWidth(false)
					cb:SetRelativeWidth(0.33)
					groupToggles:AddChild(cb)
				end
			end

			-- Copy configuration from another specialization
			local copyBarList, copyBarOrder = {}, {}
			local function registerCopyBar(pType)
				if not pType or copyBarList[pType] then return end
				copyBarList[pType] = displayNameForBarType and displayNameForBarType(pType) or (_G["POWER_TYPE_" .. pType] or _G[pType] or pType)
				copyBarOrder[#copyBarOrder + 1] = pType
			end
			registerCopyBar("HEALTH")
			for _, pType in ipairs(addon.Aura.ResourceBars.classPowerTypes) do
				if available[pType] then registerCopyBar(pType) end
			end
			if not lastSpecCopyMode[specKey] then lastSpecCopyMode[specKey] = "ALL" end
			if #copyBarOrder > 0 and (not lastSpecCopyBar[specKey] or not copyBarList[lastSpecCopyBar[specKey]]) then lastSpecCopyBar[specKey] = copyBarOrder[1] end
			if lastSpecCopyCosmetic[specKey] == nil then lastSpecCopyCosmetic[specKey] = false end

			local copyGroup = addon.functions.createContainer("InlineGroup", "Flow")
			copyGroup:SetTitle(L["Copy settings"] or "Copy settings")
			copyGroup:SetFullWidth(true)
			container:AddChild(copyGroup)

			local classKey = addon.variables.unitClass
			local classConfig = classKey and addon.db.personalResourceBarSettings[classKey]
			local copyList, copyOrder = {}, {}
			for _, tab in ipairs(specTabs) do
				local otherIndex = tab.value
				if otherIndex ~= specIndex and classConfig and classConfig[otherIndex] then
					copyList[tostring(otherIndex)] = tab.text
					copyOrder[#copyOrder + 1] = tostring(otherIndex)
				end
			end

			if #copyOrder == 0 then
				local noSpecs = addon.functions.createLabelAce(L["Copy settings unavailable"] or "Configure another specialization first to copy its settings.")
				noSpecs:SetFullWidth(true)
				copyGroup:AddChild(noSpecs)
			else
				if not lastSpecCopySelection[specKey] or not copyList[lastSpecCopySelection[specKey]] then lastSpecCopySelection[specKey] = copyOrder[1] end
				local dropBar
				local function updateDropBarState()
					if not dropBar then return end
					local mode = lastSpecCopyMode[specKey] or "ALL"
					dropBar:SetDisabled(mode ~= "BAR" or #copyBarOrder == 0)
				end
				local copyRow = addon.functions.createContainer("SimpleGroup", "Flow")
				copyRow:SetFullWidth(true)
				copyGroup:AddChild(copyRow)

				local dropCopy = addon.functions.createDropdownAce(L["Copy from spec"] or "Copy from specialization", copyList, copyOrder, function(_, _, key) lastSpecCopySelection[specKey] = key end)
				dropCopy:SetFullWidth(false)
				dropCopy:SetRelativeWidth(0.45)
				dropCopy:SetValue(lastSpecCopySelection[specKey])
				copyRow:AddChild(dropCopy)

				local scopeList = {
					ALL = L["All bars"] or "All bars",
					BAR = L["Selected bar only"] or "Selected bar only",
				}
				local scopeOrder = { "ALL", "BAR" }
				local dropScope = addon.functions.createDropdownAce(L["Copy scope"] or "Copy scope", scopeList, scopeOrder, function(_, _, key)
					lastSpecCopyMode[specKey] = key
					updateDropBarState()
				end)
				dropScope:SetFullWidth(false)
				dropScope:SetRelativeWidth(0.25)
				dropScope:SetValue(lastSpecCopyMode[specKey] or "ALL")
				copyRow:AddChild(dropScope)

				local copyButton = addon.functions.createButtonAce(L["Copy"] or "Copy", 120, function()
					local selected = lastSpecCopySelection[specKey]
					local fromSpec = selected and tonumber(selected)
					if not classConfig or not fromSpec or fromSpec == specIndex then return end
					local sourceSettings = classConfig[fromSpec]
					if not sourceSettings then return end
					classConfig[specIndex] = classConfig[specIndex] or {}
					local destSpec = classConfig[specIndex]
					local mode = lastSpecCopyMode[specKey] or "ALL"
					local cosmeticOnly = lastSpecCopyCosmetic[specKey] == true
					if mode == "ALL" then
						if cosmeticOnly then
							for _, barType in ipairs(copyBarOrder) do
								local srcBar = sourceSettings[barType]
								if type(srcBar) == "table" then
									destSpec[barType] = destSpec[barType] or {}
									copyCosmeticBarSettings(srcBar, destSpec[barType])
								end
							end
						else
							classConfig[specIndex] = CopyTable(sourceSettings)
							destSpec = classConfig[specIndex]
						end
					else
						local barType = lastSpecCopyBar[specKey]
						if not barType or not copyBarList[barType] then return end
						local srcBar = sourceSettings[barType]
						if type(srcBar) ~= "table" then
							notifyUser(L["Copy settings missing bar"] or "The selected specialization has no saved settings for that bar.")
							return
						end
						destSpec[barType] = destSpec[barType] or {}
						if cosmeticOnly then
							copyCosmeticBarSettings(srcBar, destSpec[barType])
						else
							destSpec[barType] = CopyTable(srcBar)
						end
					end
					requestActiveRefresh(specIndex)
					buildSpec(container, specIndex)
				end)
				copyButton:SetFullWidth(false)
				copyButton:SetRelativeWidth(0.3)
				copyRow:AddChild(copyButton)

				local optionsRow = addon.functions.createContainer("SimpleGroup", "Flow")
				optionsRow:SetFullWidth(true)
				copyGroup:AddChild(optionsRow)

				dropBar = addon.functions.createDropdownAce(L["Bar to copy"] or "Bar to copy", copyBarList, copyBarOrder, function(_, _, key) lastSpecCopyBar[specKey] = key end)
				dropBar:SetFullWidth(false)
				dropBar:SetRelativeWidth(0.6)
				if lastSpecCopyBar[specKey] then dropBar:SetValue(lastSpecCopyBar[specKey]) end
				optionsRow:AddChild(dropBar)

				local cbCosmetic = addon.functions.createCheckboxAce(
					L["Appearance only"] or "Appearance only",
					lastSpecCopyCosmetic[specKey] == true,
					function(_, _, val) lastSpecCopyCosmetic[specKey] = val and true or false end
				)
				cbCosmetic:SetFullWidth(false)
				cbCosmetic:SetRelativeWidth(0.4)
				optionsRow:AddChild(cbCosmetic)

				updateDropBarState()

				local info =
					addon.functions.createLabelAce(L["Copy settings info"] or "Copies settings from the selected specialization. Use scope and appearance options above to control what is copied.")
				info:SetFullWidth(true)
				copyGroup:AddChild(info)
			end

			-- Selection dropdown for configuring a single bar
			local cfgList, cfgOrder = {}, {}
			if dbSpec.HEALTH.enabled == true then
				cfgList.HEALTH = HEALTH
				tinsert(cfgOrder, "HEALTH")
			end
			for _, pType in ipairs(addon.Aura.ResourceBars.classPowerTypes) do
				if available[pType] then
					local cfg = dbSpec[pType]
					if cfg and cfg.enabled == true then
						cfgList[pType] = _G["POWER_TYPE_" .. pType] or _G[pType] or pType
						tinsert(cfgOrder, pType)
					end
				end
			end

			if not lastBarSelectionPerSpec[specKey] or not cfgList[lastBarSelectionPerSpec[specKey]] then
				lastBarSelectionPerSpec[specKey] = (specInfo.MAIN and cfgList[specInfo.MAIN]) and specInfo.MAIN or (cfgList.HEALTH and "HEALTH" or next(cfgList))
			end

			local groupConfig = addon.functions.createContainer("InlineGroup", "List")
			groupConfig:SetTitle(DELVES_CONFIGURE_BUTTON)
			container:AddChild(groupConfig)

			if #cfgOrder == 0 then
				local hint = addon.functions.createLabelAce(L["Enable a bar above to configure options."])
				groupConfig:AddChild(hint)
				return
			end

			local dropCfg = addon.functions.createDropdownAce(L["Bar"], cfgList, cfgOrder, function(self, _, val)
				lastBarSelectionPerSpec[specKey] = val
				buildSpec(container, specIndex)
			end)
			dropCfg:SetValue(lastBarSelectionPerSpec[specKey])
			groupConfig:AddChild(dropCfg)

			local sel = lastBarSelectionPerSpec[specKey]
			local frames = {}
			for k, v in pairs(baseFrameList) do
				frames[k] = v
			end
			-- Only list bars that are valid for this spec and enabled by user
			if dbSpec.HEALTH and dbSpec.HEALTH.enabled == true then frames.EQOLHealthBar = (displayNameForBarType and displayNameForBarType("HEALTH") or HEALTH) .. " " .. L["BarSuffix"] end
			for _, t in ipairs(addon.Aura.ResourceBars.classPowerTypes) do
				if t ~= sel and available[t] and dbSpec[t] and dbSpec[t].enabled == true then
					frames["EQOL" .. t .. "Bar"] = (displayNameForBarType and displayNameForBarType(t) or (_G[t] or t)) .. " " .. L["BarSuffix"]
				end
			end

			if sel == "HEALTH" then
				local hCfg = dbSpec.HEALTH
				local anchorInfo = getAnchor("HEALTH", specIndex)
				-- Size row (50%/50%)
				local sizeRow = addon.functions.createContainer("SimpleGroup", "Flow")
				sizeRow:SetFullWidth(true)
				local verticalHealth = hCfg.verticalFill == true
				local labelWidth = verticalHealth and (L["Bar thickness"] or "Bar thickness") or (L["Bar length"] or "Bar length")
				local labelHeight = verticalHealth and (L["Bar length"] or "Bar length") or (L["Bar thickness"] or "Bar thickness")
				if hCfg.width and hCfg.width < MIN_RESOURCE_BAR_WIDTH then hCfg.width = MIN_RESOURCE_BAR_WIDTH end
				local currentHealthWidth = max(MIN_RESOURCE_BAR_WIDTH, hCfg.width or DEFAULT_HEALTH_WIDTH)
				local sw = addon.functions.createSliderAce(labelWidth, currentHealthWidth, MIN_RESOURCE_BAR_WIDTH, 2000, 1, function(self, _, val)
					hCfg.width = max(MIN_RESOURCE_BAR_WIDTH, val or MIN_RESOURCE_BAR_WIDTH)
					if specIndex == addon.variables.unitSpec then addon.Aura.ResourceBars.SetHealthBarSize(hCfg.width, hCfg.height or DEFAULT_HEALTH_HEIGHT) end
				end)
				sw:SetFullWidth(false)
				sw:SetRelativeWidth(0.5)
				sw:SetDisabled(anchorInfo and anchorInfo.matchRelativeWidth == true)
				ResourceBars.ui = ResourceBars.ui or {}
				ResourceBars.ui.barWidthSliders = ResourceBars.ui.barWidthSliders or {}
				ResourceBars.ui.barWidthSliders[specIndex] = ResourceBars.ui.barWidthSliders[specIndex] or {}
				ResourceBars.ui.barWidthSliders[specIndex].HEALTH = sw
				sizeRow:AddChild(sw)
				local sh = addon.functions.createSliderAce(labelHeight, hCfg.height or DEFAULT_HEALTH_HEIGHT, 1, 2000, 1, function(self, _, val)
					hCfg.height = val
					if specIndex == addon.variables.unitSpec then addon.Aura.ResourceBars.SetHealthBarSize(hCfg.width or DEFAULT_HEALTH_WIDTH, hCfg.height) end
				end)
				sh:SetFullWidth(false)
				sh:SetRelativeWidth(0.5)
				sizeRow:AddChild(sh)
				groupConfig:AddChild(sizeRow)

				-- Text + Size row (hide size when NONE)
				local healthTextRow = addon.functions.createContainer("SimpleGroup", "Flow")
				healthTextRow:SetFullWidth(true)
				groupConfig:AddChild(healthTextRow)
				local textOffsetSliders
				local function updateHealthOffsetDisabled()
					if not textOffsetSliders then return end
					local disabled = (hCfg.textStyle or "PERCENT") == "NONE"
					for _, ctrl in ipairs(textOffsetSliders) do
						if ctrl then ctrl:SetDisabled(disabled) end
					end
				end
				local function buildHealthTextRow()
					healthTextRow:ReleaseChildren()
					local tList = { PERCENT = STATUS_TEXT_PERCENT, CURMAX = L["Current/Max"], CURRENT = L["Current"], NONE = NONE }
					local tOrder = { "PERCENT", "CURMAX", "CURRENT", "NONE" }
					local dropT = addon.functions.createDropdownAce(L["Text"], tList, tOrder, function(self, _, key)
						hCfg.textStyle = key
						requestActiveRefresh(specIndex)
						buildHealthTextRow()
					end)
					dropT:SetValue(hCfg.textStyle or "PERCENT")
					dropT:SetFullWidth(false)
					dropT:SetRelativeWidth(0.5)
					healthTextRow:AddChild(dropT)
					if (hCfg.textStyle or "PERCENT") ~= "NONE" then
						local sFont = addon.functions.createSliderAce(HUD_EDIT_MODE_SETTING_OBJECTIVE_TRACKER_TEXT_SIZE, hCfg.fontSize or 16, 6, 64, 1, function(self, _, val)
							hCfg.fontSize = val
							requestActiveRefresh(specIndex)
						end)
						sFont:SetFullWidth(false)
						sFont:SetRelativeWidth(0.5)
						healthTextRow:AddChild(sFont)
					end
					updateHealthOffsetDisabled()
				end
				buildHealthTextRow()
				textOffsetSliders = { addTextOffsetControlsUI(groupConfig, hCfg, specIndex) }
				updateHealthOffsetDisabled()
				addFontControls(groupConfig, hCfg)
				addColorControls(groupConfig, hCfg, specIndex, "HEALTH")

				-- Bar Texture (Health)
				local listTex, orderTex = getStatusbarDropdownLists(true)
				local dropTex = addon.functions.createDropdownAce(L["Bar Texture"], listTex, orderTex, function(_, _, key)
					hCfg.barTexture = key
					requestActiveRefresh(specIndex)
					buildSpec(container, specIndex)
				end)
				local cur = hCfg.barTexture or "DEFAULT"
				if not listTex[cur] then cur = "DEFAULT" end
				dropTex:SetValue(cur)
				groupConfig:AddChild(dropTex)
				ResourceBars.ui.textureDropdown = dropTex
				dropTex._rb_cfgRef = hCfg
				addBackdropControls(groupConfig, hCfg, "HEALTH")
				addBehaviorControls(groupConfig, hCfg, "HEALTH")

				addAnchorOptions("HEALTH", groupConfig, hCfg.anchor, frames, specIndex)
			else
				local cfg = dbSpec[sel] or {}
				local anchorInfo = getAnchor(sel, specIndex)
				local defaultW = DEFAULT_POWER_WIDTH
				local defaultH = DEFAULT_POWER_HEIGHT
				if cfg.width and cfg.width < MIN_RESOURCE_BAR_WIDTH then cfg.width = MIN_RESOURCE_BAR_WIDTH end
				local curW = max(MIN_RESOURCE_BAR_WIDTH, cfg.width or defaultW)
				local curH = cfg.height or defaultH
				local defaultStyle = (sel == "MANA") and "PERCENT" or "CURMAX"
				local curStyle = cfg.textStyle or defaultStyle
				local curFont = cfg.fontSize or 16
				local vertical = cfg.verticalFill == true

				-- Size row (50%/50%)
				local sizeRow2 = addon.functions.createContainer("SimpleGroup", "Flow")
				sizeRow2:SetFullWidth(true)
				local labelWidth = vertical and (L["Bar thickness"] or "Bar thickness") or (L["Bar length"] or "Bar length")
				local labelHeight = vertical and (L["Bar length"] or "Bar length") or (L["Bar thickness"] or "Bar thickness")
				local sw = addon.functions.createSliderAce(labelWidth, curW, MIN_RESOURCE_BAR_WIDTH, 2000, 1, function(self, _, val)
					local width = max(MIN_RESOURCE_BAR_WIDTH, val or MIN_RESOURCE_BAR_WIDTH)
					cfg.width = width
					if specIndex == addon.variables.unitSpec then addon.Aura.ResourceBars.SetPowerBarSize(width, cfg.height or defaultH, sel) end
				end)
				sw:SetFullWidth(false)
				sw:SetRelativeWidth(0.5)
				sw:SetDisabled(anchorInfo and anchorInfo.matchRelativeWidth == true)
				ResourceBars.ui = ResourceBars.ui or {}
				ResourceBars.ui.barWidthSliders = ResourceBars.ui.barWidthSliders or {}
				ResourceBars.ui.barWidthSliders[specIndex] = ResourceBars.ui.barWidthSliders[specIndex] or {}
				ResourceBars.ui.barWidthSliders[specIndex][sel] = sw
				sizeRow2:AddChild(sw)
				local sh = addon.functions.createSliderAce(labelHeight, curH, 1, 2000, 1, function(self, _, val)
					cfg.height = val
					if specIndex == addon.variables.unitSpec then addon.Aura.ResourceBars.SetPowerBarSize(cfg.width or defaultW, val, sel) end
				end)
				sh:SetFullWidth(false)
				sh:SetRelativeWidth(0.5)
				sizeRow2:AddChild(sh)
				groupConfig:AddChild(sizeRow2)

				if sel ~= "RUNES" then
					-- Text + Size row (50%/50%), hide size when NONE
					local textRow = addon.functions.createContainer("SimpleGroup", "Flow")
					textRow:SetFullWidth(true)
					groupConfig:AddChild(textRow)
					local textOffsetSliders
					local function updateOffsetDisabled()
						if not textOffsetSliders then return end
						local disabled = (cfg.textStyle or curStyle) == "NONE"
						for _, ctrl in ipairs(textOffsetSliders) do
							if ctrl then ctrl:SetDisabled(disabled) end
						end
					end
					local function buildTextRow()
						textRow:ReleaseChildren()
						local tList = { PERCENT = STATUS_TEXT_PERCENT, CURMAX = L["Current/Max"], CURRENT = L["Current"], NONE = NONE }
						local tOrder = { "PERCENT", "CURMAX", "CURRENT", "NONE" }
						local drop = addon.functions.createDropdownAce(L["Text"], tList, tOrder, function(self, _, key)
							cfg.textStyle = key
							requestActiveRefresh(specIndex)
							buildTextRow()
						end)
						drop:SetValue(cfg.textStyle or curStyle)
						drop:SetFullWidth(false)
						drop:SetRelativeWidth(0.5)
						textRow:AddChild(drop)
						if (cfg.textStyle or curStyle) ~= "NONE" then
							local sFont = addon.functions.createSliderAce(HUD_EDIT_MODE_SETTING_OBJECTIVE_TRACKER_TEXT_SIZE, cfg.fontSize or curFont, 6, 64, 1, function(self, _, val)
								cfg.fontSize = val
								requestActiveRefresh(specIndex)
							end)
							sFont:SetFullWidth(false)
							sFont:SetRelativeWidth(0.5)
							textRow:AddChild(sFont)
						end
						updateOffsetDisabled()
					end
					buildTextRow()
					textOffsetSliders = { addTextOffsetControlsUI(groupConfig, cfg, specIndex) }
					updateOffsetDisabled()
					addFontControls(groupConfig, cfg)
					addColorControls(groupConfig, cfg, specIndex, sel)

					-- Bar Texture (Power types incl. RUNES)
					local listTex2, orderTex2 = getStatusbarDropdownLists(true)
					local dropTex2 = addon.functions.createDropdownAce(L["Bar Texture"], listTex2, orderTex2, function(_, _, key)
						cfg.barTexture = key
						requestActiveRefresh(specIndex)
						buildSpec(container, specIndex)
					end)
					local cur2 = cfg.barTexture or "DEFAULT"
					if not listTex2[cur2] then cur2 = "DEFAULT" end
					dropTex2:SetValue(cur2)
					groupConfig:AddChild(dropTex2)
					ResourceBars.ui.textureDropdown = dropTex2
					dropTex2._rb_cfgRef = cfg
					addBackdropControls(groupConfig, cfg, sel)
					addBehaviorControls(groupConfig, cfg, sel)
				else
					-- RUNES specific options
					local cbRT = addon.functions.createCheckboxAce(L["Show cooldown text"], cfg.showCooldownText == true, function(self, _, val)
						cfg.showCooldownText = val and true or false
						if powerbar["RUNES"] then
							layoutRunes(powerbar["RUNES"])
							updatePowerBar("RUNES")
						end
					end)
					groupConfig:AddChild(cbRT)

					local sRTFont = addon.functions.createSliderAce(L["Cooldown Text Size"], cfg.cooldownTextFontSize or 16, 6, 64, 1, function(self, _, val)
						cfg.cooldownTextFontSize = val
						if powerbar["RUNES"] then
							layoutRunes(powerbar["RUNES"])
							updatePowerBar("RUNES")
						end
					end)
					groupConfig:AddChild(sRTFont)
					addBackdropControls(groupConfig, cfg, sel)
					addBehaviorControls(groupConfig, cfg, sel)
				end

				-- Separator toggle + color picker row (eligible bars only)
				local eligible = addon.Aura.ResourceBars.separatorEligible
				if eligible and eligible[sel] then
					local sepRow = addon.functions.createContainer("SimpleGroup", "Flow")
					sepRow:SetFullWidth(true)
					local sepColor
					local sepThickness
					local cbSep = addon.functions.createCheckboxAce(L["Show separator"], cfg.showSeparator == true, function(self, _, val)
						cfg.showSeparator = val and true or false
						requestActiveRefresh(specIndex)
						if sepColor then sepColor:SetDisabled(not cfg.showSeparator) end
						if sepThickness then sepThickness:SetDisabled(not cfg.showSeparator) end
					end)
					cbSep:SetFullWidth(false)
					cbSep:SetRelativeWidth(0.5)
					sepRow:AddChild(cbSep)
					sepColor = AceGUI:Create("ColorPicker")
					sepColor:SetLabel(L["Separator Color"] or "Separator Color")
					local sc = cfg.separatorColor or SEP_DEFAULT
					sepColor:SetColor(sc[1] or 1, sc[2] or 1, sc[3] or 1, sc[4] or 0.5)
					sepColor:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
						cfg.separatorColor = { r, g, b, a }
						requestActiveRefresh(specIndex)
					end)
					sepColor:SetFullWidth(false)
					sepColor:SetRelativeWidth(0.5)
					sepColor:SetDisabled(not (cfg.showSeparator == true))
					sepRow:AddChild(sepColor)

					sepThickness = addon.functions.createSliderAce(L["Separator thickness"] or "Separator thickness", cfg.separatorThickness or SEPARATOR_THICKNESS, 1, 10, 1, function(_, _, val)
						cfg.separatorThickness = val
						requestActiveRefresh(specIndex)
					end)
					sepThickness:SetFullWidth(false)
					sepThickness:SetRelativeWidth(0.5)
					sepThickness:SetDisabled(not (cfg.showSeparator == true))
					sepRow:AddChild(sepThickness)
					groupConfig:AddChild(sepRow)
				end

				-- Druid: Show in forms (per bar), skip for COMBO_POINTS (always Cat)
				if addon.variables.unitClass == "DRUID" and sel ~= "COMBO_POINTS" then
					groupConfig:AddChild(addon.functions.createSpacerAce())
					cfg.showForms = cfg.showForms or {}
					local formsRow = addon.functions.createContainer("SimpleGroup", "Flow")
					formsRow:SetFullWidth(true)
					local label = addon.functions.createLabelAce(L["Show in"])
					label:SetFullWidth(true)
					groupConfig:AddChild(label)
					local function mkCb(key, text)
						local cb = addon.functions.createCheckboxAce(text, cfg.showForms[key] ~= false, function(self, _, val)
							cfg.showForms[key] = val and true or false
							requestActiveRefresh(specIndex)
						end)
						cb:SetFullWidth(false)
						cb:SetRelativeWidth(0.25)
						formsRow:AddChild(cb)
					end
					if sel == "COMBO_POINTS" then
						-- Combo points only in Cat; default only Cat true
						if cfg.showForms.CAT == nil then cfg.showForms.CAT = true end
						cfg.showForms.HUMANOID = cfg.showForms.HUMANOID or false
						cfg.showForms.BEAR = cfg.showForms.BEAR or false
						cfg.showForms.TRAVEL = cfg.showForms.TRAVEL or false
						cfg.showForms.MOONKIN = cfg.showForms.MOONKIN or false
						cfg.showForms.TREANT = cfg.showForms.TREANT or false
						cfg.showForms.STAG = cfg.showForms.STAG or false
						mkCb("CAT", L["Cat"])
					else
						if cfg.showForms.HUMANOID == nil then cfg.showForms.HUMANOID = true end
						if cfg.showForms.BEAR == nil then cfg.showForms.BEAR = true end
						if cfg.showForms.CAT == nil then cfg.showForms.CAT = true end
						if cfg.showForms.TRAVEL == nil then cfg.showForms.TRAVEL = true end
						if cfg.showForms.MOONKIN == nil then cfg.showForms.MOONKIN = true end
						if cfg.showForms.TREANT == nil then cfg.showForms.TREANT = true end
						if cfg.showForms.STAG == nil then cfg.showForms.STAG = true end
						mkCb("HUMANOID", L["Humanoid"])
						mkCb("BEAR", L["Bear"])
						mkCb("CAT", L["Cat"])
						mkCb("TRAVEL", L["Travel"])
						mkCb("MOONKIN", L["Moonkin"])
						mkCb("TREANT", L["Treant"])
						mkCb("STAG", L["Stag"])
					end
					groupConfig:AddChild(formsRow)
				end
				groupConfig:AddChild(addon.functions.createSpacerAce())

				addAnchorOptions(sel, groupConfig, cfg.anchor, frames, specIndex)
			end
			scroll:DoLayout()
		end

		tabGroup:SetTabs(specTabs)
		tabGroup:SetCallback("OnGroupSelected", function(tabContainer, _, val) buildSpec(tabContainer, val) end)
		wrapper:AddChild(tabGroup)
		tabGroup:SelectTab(addon.variables.unitSpec or specTabs[1].value)
	end
	scroll:DoLayout()
end

function updateHealthBar(evt)
	if healthBar and healthBar:IsShown() then
		local previousMax = healthBar._lastMax or 0
		local newMax = UnitHealthMax("player") or previousMax or 1

		if previousMax ~= newMax then
			healthBar._lastMax = newMax
			healthBar:SetMinMaxValues(0, newMax)
			if not addon.variables.isMidnight then
				local currentValue = healthBar:GetValue() or 0
				if currentValue > newMax then healthBar:SetValue(newMax) end
				if healthBar._smoothTarget and healthBar._smoothTarget > newMax then
					healthBar._smoothTarget = newMax
					if healthBar._smoothEnabled then tryActivateSmooth(healthBar) end
				end
			else
				healthBar:SetValue(newMax)
			end
		end
		local maxHealth = healthBar._lastMax or newMax or 1
		local curHealth = UnitHealth("player")
		local settings = getBarSettings("HEALTH") or {}
		local smooth = settings.smoothFill == true
		if not addon.variables.isMidnight and smooth then
			healthBar._smoothTarget = curHealth
			healthBar._smoothDeadzone = settings.smoothDeadzone or healthBar._smoothDeadzone or DEFAULT_SMOOTH_DEADZONE
			healthBar._smoothSpeed = SMOOTH_SPEED
			if not healthBar._smoothInitialized then
				healthBar:SetValue(curHealth)
				healthBar._smoothInitialized = true
			end
			healthBar._smoothEnabled = true
			tryActivateSmooth(healthBar)
		else
			healthBar._smoothTarget = nil
			healthBar._smoothDeadzone = settings.smoothDeadzone or healthBar._smoothDeadzone or DEFAULT_SMOOTH_DEADZONE
			healthBar._smoothSpeed = SMOOTH_SPEED
			if not addon.variables.isMidnight and healthBar._lastVal ~= curHealth then
				healthBar:SetValue(curHealth)
			else
				healthBar:SetValue(curHealth)
			end
			healthBar._smoothInitialized = nil
			healthBar._smoothEnabled = false
			stopSmoothUpdater(healthBar)
		end
		healthBar._lastVal = curHealth

		local percent, percentStr
		if addon.variables.isMidnight then
			percent = AbbreviateLargeNumbers(UnitHealthPercent("player", true, true) or 0)
			percentStr = string.format("%s%%", percent)
		else
			percent = (curHealth / max(maxHealth, 1)) * 100
			percentStr = tostring(floor(percent + 0.5))
		end
		if healthBar.text then
			local style = settings and settings.textStyle or "PERCENT"
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
					text = AbbreviateLargeNumbers(curHealth)
				else -- CURMAX
					text = AbbreviateLargeNumbers(curHealth) .. " / " .. (AbbreviateLargeNumbers(maxHealth))
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
			local custom = settings.barColor or WHITE
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
				local maxCol = settings.maxColor or WHITE
				finalR, finalG, finalB, finalA = maxCol[1] or baseR, maxCol[2] or baseG, maxCol[3] or baseB, maxCol[4] or baseA
			end

			local lc = healthBar._lastColor or {}
			local fa = finalA or 1
			if lc[1] ~= finalR or lc[2] ~= finalG or lc[3] ~= finalB or lc[4] ~= fa then
				lc[1], lc[2], lc[3], lc[4] = finalR, finalG, finalB, fa
				healthBar._lastColor = lc
				healthBar:SetStatusBarColor(lc[1], lc[2], lc[3], lc[4])
			end
		else
			local lc = healthBar._lastColor or {}
			if lc[1] ~= baseR or lc[2] ~= baseG or lc[3] ~= baseB or lc[4] ~= baseA then
				if (settings.useBarColor or settings.useClassColor) and not settings.useMaxColor then
					healthBar._lastColor = lc
					healthBar:GetStatusBarTexture():SetVertexColor(1, 1, 1, 1)
					healthBar:SetStatusBarColor(baseR, baseG, baseB, baseA)
				else
					if wasMax ~= settings.useMaxColor then
						wasMax = settings.useMaxColor
						if settings.useMaxColor then
							SetColorCurvePoints(settings.maxColor or WHITE)
						else
							SetColorCurvePoints()
						end
					end
					local color = UnitHealthPercentColor("player", curve)
					healthBar:GetStatusBarTexture():SetVertexColor(color:GetRGB())
				end
			end
		end
		setBarDesaturated(healthBar, true)

		local absorbBar = healthBar.absorbBar
		if absorbBar then
			if not absorbBar:IsShown() or maxHealth <= 0 then
				if addon.variables.isMidnight then
					absorbBar:SetValue(0)
				else
					if absorbBar._lastVal and absorbBar._lastVal ~= 0 then
						absorbBar:SetValue(0)
						absorbBar._lastVal = 0
					end
				end
			else
				local abs = UnitGetTotalAbsorbs("player") or 0
				if addon.variables.isMidnight then
					absorbBar:SetValue(abs)
					absorbBar:SetMinMaxValues(0, maxHealth)
				else
					if abs > maxHealth then abs = maxHealth end
					if absorbBar._lastMax ~= maxHealth then
						absorbBar:SetMinMaxValues(0, maxHealth)
						absorbBar._lastMax = maxHealth
					end
					if absorbBar._lastVal ~= abs then
						absorbBar:SetValue(abs)
						absorbBar._lastVal = abs
					end
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
	return anchor
end

local function resolveAnchor(info, type)
	local frame = _G[info and info.relativeFrame]
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
		check = _G[anch and anch.relativeFrame]
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
		local w = max(MIN_RESOURCE_BAR_WIDTH, (cfg and cfg.width) or DEFAULT_HEALTH_WIDTH)
		local h = (cfg and cfg.height) or DEFAULT_HEALTH_HEIGHT
		healthBar:SetSize(w, h)
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
		local w = healthBar:GetWidth() or DEFAULT_HEALTH_WIDTH
		local h = healthBar:GetHeight() or DEFAULT_HEALTH_HEIGHT
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
		local w = healthBar:GetWidth() or DEFAULT_HEALTH_WIDTH
		local h = healthBar:GetHeight() or DEFAULT_HEALTH_HEIGHT
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

	healthBar:SetMovable(true)
	healthBar:EnableMouse(true)
	healthBar:RegisterForDrag("LeftButton")
	healthBar:SetScript("OnDragStart", function(self)
		if IsShiftKeyDown() then self:StartMoving() end
	end)
	healthBar:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, rel, relPoint, xOfs, yOfs = self:GetPoint()
		local info = getAnchor("HEALTH", addon.variables.unitSpec)
		local relName = rel and rel.GetName and rel:GetName() or "UIParent"
		point = point or "TOPLEFT"
		info.point = point
		info.relativeFrame = relName
		info.relativePoint = relPoint or point
		info.x = Snap(self, xOfs or 0)
		info.y = Snap(self, yOfs or 0)
		info.autoSpacing = nil
		self:ClearAllPoints()
		self:SetPoint(info.point, rel or UIParent, info.relativePoint or info.point, info.x or 0, info.y or 0)
	end)

	local absorbBar = CreateFrame("StatusBar", "EQOLAbsorbBar", healthBar)
	absorbBar:SetAllPoints(healthBar)
	absorbBar:SetFrameStrata(healthBar:GetFrameStrata())
	absorbBar:SetFrameLevel((healthBar:GetFrameLevel() + 1))
	do
		local cfgTexH = getBarSettings("HEALTH") or {}
		absorbBar:SetStatusBarTexture(resolveTexture(cfgTexH))
	end
	absorbBar:SetStatusBarColor(0.8, 0.8, 0.8, 0.8)
	local wantVertical = settings and settings.verticalFill == true
	if absorbBar.SetOrientation and absorbBar._isVertical ~= wantVertical then absorbBar:SetOrientation(wantVertical and "VERTICAL" or "HORIZONTAL") end
	absorbBar._isVertical = wantVertical
	if absorbBar.SetReverseFill then absorbBar:SetReverseFill(settings and settings.reverseFill == true) end
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

local powertypeClasses = {
	DRUID = {
		[1] = { MAIN = "LUNAR_POWER", RAGE = true, ENERGY = true, MANA = true, COMBO_POINTS = true }, -- Balance (combo in Cat)
		[2] = { MAIN = "ENERGY", COMBO_POINTS = true, RAGE = true, MANA = true }, -- Feral (no Astral Power)
		[3] = { MAIN = "RAGE", ENERGY = true, MANA = true, COMBO_POINTS = true }, -- Guardian (no Astral Power)
		[4] = { MAIN = "MANA", RAGE = true, ENERGY = true, COMBO_POINTS = true }, -- Restoration (combo when in cat)
	},
	DEMONHUNTER = {
		[1] = { MAIN = "FURY" },
		[2] = { MAIN = "FURY" },
		[3] = { MAIN = "FURY" },
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
		[2] = { MANA = true },
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
		[1] = { MAIN = "ENERGY", MANA = true },
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

local POWER_ENUM = {}
for k, v in pairs(EnumPowerType or {}) do
	local key = k:gsub("(%l)(%u)", "%1_%2"):upper()
	POWER_ENUM[key] = v
end

local classPowerTypes = {
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
	"CHI",
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
	RUNES = true,
}

function getBarSettings(pType)
	local class = addon.variables.unitClass
	local spec = addon.variables.unitSpec
	if addon.db.personalResourceBarSettings and addon.db.personalResourceBarSettings[class] and addon.db.personalResourceBarSettings[class][spec] then
		return addon.db.personalResourceBarSettings[class][spec][pType]
	end
	return nil
end

local function wantsRelativeFrameWidthMatch(anchor) return anchor and (anchor.relativeFrame or "UIParent") ~= "UIParent" and anchor.matchRelativeWidth == true end

local function getConfiguredBarWidth(pType)
	local cfg = getBarSettings(pType)
	local default = (pType == "HEALTH") and DEFAULT_HEALTH_WIDTH or DEFAULT_POWER_WIDTH
	local width = (cfg and type(cfg.width) == "number" and cfg.width > 0 and cfg.width) or default or MIN_RESOURCE_BAR_WIDTH
	return max(MIN_RESOURCE_BAR_WIDTH, width or MIN_RESOURCE_BAR_WIDTH)
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
	local relFrame = relativeFrameName and _G[relativeFrameName]
	if not relFrame or not relFrame.GetWidth then
		local current = frame:GetWidth() or 0
		if abs(current - baseWidth) < 0.5 then return false end
		frame:SetWidth(baseWidth)
		return true
	end
	local relWidth = relFrame:GetWidth() or 0
	local desired = max(MIN_RESOURCE_BAR_WIDTH, relWidth or 0)
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
	local frame = _G[frameName]
	if not frame then
		if After and not pendingHookRetries[frameName] then
			pendingHookRetries[frameName] = true
			After(1, function()
				pendingHookRetries[frameName] = nil
				if ensureRelativeFrameHooks then ensureRelativeFrameHooks(frameName) end
			end)
		end
		return
	end
	if widthMatchHookedFrames[frameName] then return end
	if frame.HookScript then
		local okSize = pcall(frame.HookScript, frame, "OnSizeChanged", handleRelativeFrameGeometryChanged)
		local okShow = pcall(frame.HookScript, frame, "OnShow", handleRelativeFrameGeometryChanged)
		local okHide = pcall(frame.HookScript, frame, "OnHide", handleRelativeFrameGeometryChanged)
		if okSize or okShow or okHide then widthMatchHookedFrames[frameName] = true end
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
		local col = bar._dkColor or DK_SPEC_COLOR[addon.variables.unitSpec] or DK_SPEC_COLOR[1]
		local r, g, b = col[1], col[2], col[3]
		local grey = 0.35
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

		local cfg = getBarSettings("RUNES") or {}
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
				if sb._isReady ~= wantReady then
					sb._isReady = wantReady
					if wantReady then
						sb:SetStatusBarColor(r, g, b)
					else
						sb:SetStatusBarColor(grey, grey, grey)
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
			bar._runeUpdateInterval = min(RUNE_UPDATE_INTERVAL, max(0.05, soonest))
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
					local threshold = self._runeUpdateInterval or RUNE_UPDATE_INTERVAL
					if self._runeAccum >= threshold then
						self._runeAccum = 0
						local n = GetTime()
						local cfgOnUpdate = self._runeConfig or {}
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
								if sb._isReady ~= wantReady then
									sb._isReady = wantReady
									if wantReady then
										sb:SetStatusBarColor(r, g, b)
									else
										sb:SetStatusBarColor(grey, grey, grey)
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
	local pType = POWER_ENUM[type]
	local cfg = getBarSettings(type) or {}
	local maxPower = bar._lastMax
	if not maxPower then
		maxPower = UnitPowerMax("player", pType)
		bar._lastMax = maxPower
		bar:SetMinMaxValues(0, maxPower)
	end
	local curPower = UnitPower("player", pType)

	local style = bar._style or ((type == "MANA") and "PERCENT" or "CURMAX")
	local smooth = cfg.smoothFill == true
	if not addon.variables.isMidnight and smooth then
		bar._smoothTarget = curPower
		bar._smoothDeadzone = cfg.smoothDeadzone or bar._smoothDeadzone or DEFAULT_SMOOTH_DEADZONE
		bar._smoothSpeed = SMOOTH_SPEED
		if not bar._smoothInitialized then
			bar:SetValue(curPower)
			bar._smoothInitialized = true
		end
		bar._smoothEnabled = true
		tryActivateSmooth(bar)
	else
		bar._smoothTarget = nil
		bar._smoothDeadzone = cfg.smoothDeadzone or bar._smoothDeadzone or DEFAULT_SMOOTH_DEADZONE
		bar._smoothSpeed = SMOOTH_SPEED
		if (not addon.variables.isMidnight and bar._lastVal ~= curPower) or (issecretvalue and not issecretvalue(curPower) and bar._lastVal ~= curPower) then
			bar:SetValue(curPower)
		else
			bar:SetValue(curPower)
		end
		bar._smoothInitialized = nil
		bar._smoothEnabled = false
		stopSmoothUpdater(bar)
	end
	bar._lastVal = curPower
	local percent, percentStr
	if addon.variables.isMidnight then
		percent = AbbreviateLargeNumbers(UnitPowerPercent("player", pType, true, true) or 0)
		percentStr = string.format("%s%%", percent)
	else
		percent = (curPower / max(maxPower, 1)) * 100
		percentStr = tostring(floor(percent + 0.5))
	end
	if bar.text then
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
				text = AbbreviateLargeNumbers(curPower)
				text = tostring(curPower)
			else -- CURMAX
				text = AbbreviateLargeNumbers(curPower) .. " / " .. (AbbreviateLargeNumbers(maxPower))
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
		local custom = cfg.barColor or WHITE
		bar._baseColor[1], bar._baseColor[2], bar._baseColor[3], bar._baseColor[4] = custom[1] or 1, custom[2] or 1, custom[3] or 1, custom[4] or 1
	end

	if not addon.variables.isMidnight or (issecretvalue and not issecretvalue(curPower) and not issecretvalue(maxPower)) then
		local reachedCap = curPower >= max(maxPower, 1)
		local useMaxColor = cfg.useMaxColor == true
		if useMaxColor and reachedCap then
			local maxCol = cfg.maxColor or WHITE
			local mr, mg, mb, ma = maxCol[1] or 1, maxCol[2] or 1, maxCol[3] or 1, maxCol[4] or (bar._baseColor[4] or 1)
			local lc = bar._lastColor or {}
			if bar._usingMaxColor ~= true or lc[1] ~= mr or lc[2] ~= mg or lc[3] ~= mb or lc[4] ~= ma then
				lc[1], lc[2], lc[3], lc[4] = mr, mg, mb, ma
				bar._lastColor = lc
				bar:SetStatusBarColor(lc[1], lc[2], lc[3], lc[4])
				bar._usingMaxColor = true
			end
		else
			local base = bar._baseColor
			if base then
				local lc = bar._lastColor or {}
				local br, bgc, bb, ba = base[1] or 1, base[2] or 1, base[3] or 1, base[4] or 1
				if bar._usingMaxColor == true or lc[1] ~= br or lc[2] ~= bgc or lc[3] ~= bb or lc[4] ~= ba then
					lc[1], lc[2], lc[3], lc[4] = br, bgc, bb, ba
					bar._lastColor = lc
					bar:SetStatusBarColor(lc[1], lc[2], lc[3], lc[4])
				end
			end
			bar._usingMaxColor = false
		end
	else
		local lc = bar._lastColor or {}
		local base = bar._baseColor
		if base then
			local br, bgc, bb, ba = base[1] or 1, base[2] or 1, base[3] or 1, base[4] or 1
			if lc[1] ~= br or lc[2] ~= bgc or lc[3] ~= bb or lc[4] ~= ba then
				if cfg.useBarColor and not cfg.useMaxColor then
					bar._lastColor = lc
					bar:GetStatusBarTexture():SetVertexColor(1, 1, 1, 1)
					bar:SetStatusBarColor(br, bgc, bb, ba)
				end
			end
		end
	end

	configureSpecialTexture(bar, type, cfg)
end

function forceColorUpdate(pType)
	if pType == "HEALTH" then
		updateHealthBar("FORCE_COLOR")
		return
	end

	if pType and powerbar[pType] then updatePowerBar(pType) end
end

-- Create/update separator ticks for a given bar type if enabled
updateBarSeparators = function(pType)
	local eligible = ResourceBars.separatorEligible
	if pType ~= "RUNES" and (not eligible or not eligible[pType]) then return end
	local bar = powerbar[pType]
	if not bar then return end
	local cfg = getBarSettings(pType)
	if not (cfg and cfg.showSeparator) then
		if bar.separatorMarks then
			for _, tx in ipairs(bar.separatorMarks) do
				tx:Hide()
			end
		end
		return
	end

	local segments
	if pType == "RUNES" then
		-- Runes don't use UnitPowerMax; always 6 segments
		segments = 6
	elseif pType == "ENERGY" then
		segments = 10
	else
		local enumId = POWER_ENUM[pType]
		segments = enumId and UnitPowerMax("player", enumId) or 0
	end
	if not segments or segments < 2 then
		-- Nothing to separate
		if bar.separatorMarks then
			for _, tx in ipairs(bar.separatorMarks) do
				tx:Hide()
			end
		end
		return
	end

	local inset = bar._rbContentInset or ZERO_INSETS
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
	local w = max(1, (bar:GetWidth() or 0) - (inset.left + inset.right))
	local h = max(1, (bar:GetHeight() or 0) - (inset.top + inset.bottom))
	local vertical = cfg and cfg.verticalFill == true
	local span = vertical and h or w
	local desiredThickness = (cfg and cfg.separatorThickness) or SEPARATOR_THICKNESS
	local thickness
	if vertical then
		local segH = span / segments
		thickness = min(desiredThickness, max(1, floor(segH - 1)))
	else
		local segW = span / segments
		thickness = min(desiredThickness, max(1, floor(segW - 1)))
	end
	local sc = (cfg and cfg.separatorColor) or SEP_DEFAULT
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
			local y = Snap(bar, h * frac)
			tx:SetPoint("TOP", inner, "TOP", 0, -(y - max(0, half)))
			tx:SetSize(w, thickness)
		else
			local x = Snap(bar, w * frac)
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

-- Layout helper for DK RUNES: create or resize 6 child statusbars
function layoutRunes(bar)
	if not bar then return end
	bar.runes = bar.runes or {}
	local count = 6
	local gap = 0
	local inner = bar._rbInner or bar
	local w = max(1, inner:GetWidth() or (bar:GetWidth() or 0))
	local h = max(1, inner:GetHeight() or (bar:GetHeight() or 0))
	local cfg = getBarSettings("RUNES") or {}
	local show = cfg.showCooldownText == true
	local size = cfg.cooldownTextFontSize or 16
	local fontPath = resolveFontFace(cfg)
	local fontOutline = resolveFontOutline(cfg)
	local fr, fg, fb, fa = resolveFontColor(cfg)
	local vertical = cfg.verticalFill == true
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
		if not sb.fs then
			sb.fs = sb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			sb.fs:SetPoint("CENTER", sb, "CENTER", 0, 0)
		end
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
	end
end

local function createPowerBar(type, anchor)
	-- Reuse existing bar if present; avoid destroying frames to preserve anchors
	local bar = powerbar[type] or _G["EQOL" .. type .. "Bar"]
	local isNew = false
	if not bar then
		bar = CreateFrame("StatusBar", "EQOL" .. type .. "Bar", UIParent, "BackdropTemplate")
		isNew = true
	end
	-- Ensure a valid parent when reusing frames after disable
	if bar:GetParent() ~= UIParent then bar:SetParent(UIParent) end

	local settings = getBarSettings(type)
	local w = max(MIN_RESOURCE_BAR_WIDTH, (settings and settings.width) or DEFAULT_POWER_WIDTH)
	local h = settings and settings.height or DEFAULT_POWER_HEIGHT
	bar._cfg = settings
	bar._rbType = type
	powerbar[type] = bar
	local defaultStyle = (type == "MANA") and "PERCENT" or "CURMAX"
	bar._style = settings and settings.textStyle or defaultStyle
	bar:SetSize(w, h)
	do
		local cfg2 = getBarSettings(type) or {}
		bar:SetStatusBarTexture(resolveTexture(cfg2))
		configureSpecialTexture(bar, type, cfg2)
	end
	bar:SetClampedToScreen(true)
	local stackSpacing = DEFAULT_STACK_SPACING

	-- Anchor handling: during spec/trait refresh we suppress inter-bar anchoring
	local a = getAnchor(type, addon.variables.unitSpec)
	local allowMove = true
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
			if rel and rel.GetName and rel:GetName() ~= "UIParent" then allowMove = false end
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

	if type ~= "RUNES" then
		if not bar.text then bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
		applyFontToString(bar.text, settings)
		applyTextPosition(bar, settings, 3, 0)
		bar.text:Show()
	else
		if bar.text then
			bar.text:SetText("")
			bar.text:Hide()
		end
		-- Hide parent statusbar texture; we render child rune bars
		local tex = bar:GetStatusBarTexture()
		if tex then tex:SetAlpha(0) end
		layoutRunes(bar)
	end
	if type == "RUNES" and not bar._runeVisibilityHooks then
		bar:HookScript("OnHide", function(self)
			self._pendingRuneRefresh = true
			deactivateRuneTicker(self)
		end)
		bar:HookScript("OnShow", function(self)
			if self._pendingRuneRefresh then
				self._pendingRuneRefresh = nil
				updatePowerBar("RUNES")
			end
		end)
		bar._runeVisibilityHooks = true
	end
	if type == "RUNES" then
		bar:SetStatusBarColor(getPowerBarColor(type))
	elseif not (settings and settings.useBarColor == true) then
		local dr, dg, db = getPowerBarColor(type)
		local alpha = (settings and settings.barColor and settings.barColor[4]) or 1
		bar:SetStatusBarColor(dr, dg, db, alpha)
	end
	configureBarBehavior(bar, settings, type)

	-- Dragging only when not anchored to another EQOL bar
	bar:SetMovable(allowMove)
	bar:EnableMouse(allowMove)
	if isNew then bar:RegisterForDrag("LeftButton") end
	bar:SetScript("OnDragStart", function(self)
		local ai = getAnchor(type, addon.variables.unitSpec)
		local canMove = (not ai) or ((ai.relativeFrame or "UIParent") == "UIParent")
		if IsShiftKeyDown() and canMove then self:StartMoving() end
	end)
	bar:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, rel, relPoint, xOfs, yOfs = self:GetPoint()
		local info = getAnchor(type, addon.variables.unitSpec)
		point = point or "TOPLEFT"
		local relName = rel and rel.GetName and rel:GetName() or "UIParent"
		info.point = point
		info.relativeFrame = relName
		info.relativePoint = relPoint or point
		info.x = Snap(self, xOfs or 0)
		info.y = Snap(self, yOfs or 0)
		info.autoSpacing = false
		self:ClearAllPoints()
		self:SetPoint(info.point, rel or UIParent, info.relativePoint or info.point, info.x or 0, info.y or 0)
	end)
	bar:Show()
	if type == "RUNES" then ResourceBars.ForceRuneRecolor() end
	updatePowerBar(type)
	if type == "RUNES" then
		updateBarSeparators("RUNES")
	elseif ResourceBars.separatorEligible[type] then
		updateBarSeparators(type)
	end

	-- Ensure dependents re-anchor when this bar changes size
	bar:SetScript("OnSizeChanged", function()
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorDependentsOf then addon.Aura.ResourceBars.ReanchorDependentsOf("EQOL" .. type .. "Bar") end
		if type == "RUNES" then
			layoutRunes(bar)
			updateBarSeparators("RUNES")
		elseif ResourceBars.separatorEligible[type] then
			updateBarSeparators(type)
		end
	end)
end

local eventsToRegister = {
	"UNIT_HEALTH",
	"UNIT_MAXHEALTH",
	"UNIT_ABSORB_AMOUNT_CHANGED",
	"UNIT_POWER_UPDATE",
	"UNIT_POWER_FREQUENT",
	"UNIT_DISPLAYPOWER",
	"UNIT_MAXPOWER",
	"UPDATE_SHAPESHIFT_FORM",
}

local function setPowerbars()
	local _, powerToken = UnitPowerType("player")
	powerfrequent = {}
	local isDruid = addon.variables.unitClass == "DRUID"
	local function currentDruidForm()
		if not isDruid then return nil end
		local idx = GetShapeshiftForm() or 0
		local key = formIndexToKey[idx]
		if key then return key end
		local name
		if GetShapeshiftFormInfo then
			local r1, r2 = GetShapeshiftFormInfo(idx)
			if type(r1) == "string" then
				name = r1
			elseif type(r2) == "string" then
				name = r2
			end
		end
		key = mapFormNameToKey(name)
		if key then return key end
		return "HUMANOID"
	end
	local druidForm = currentDruidForm()
	local mainPowerBar
	local lastBar
	local specCfg = addon.db.personalResourceBarSettings
		and addon.db.personalResourceBarSettings[addon.variables.unitClass]
		and addon.db.personalResourceBarSettings[addon.variables.unitClass][addon.variables.unitSpec]

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
			if formAllowed and addon.variables.unitClass == "DRUID" then
				if FREQUENT[pType] then powerfrequent[pType] = true end
				if pType == mainPowerBar then
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
				if FREQUENT[pType] then powerfrequent[pType] = true end
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

local function shouldHideResourceBarsOutOfCombat() return addon and addon.db and addon.db.resourceBarsHideOutOfCombat == true end
local function shouldHideResourceBarsMounted() return addon and addon.db and addon.db.resourceBarsHideMounted == true end
local function shouldHideResourceBarsInVehicle() return addon and addon.db and addon.db.resourceBarsHideVehicle == true end

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

local function buildDruidVisibilityExpression(cfg, hideOutOfCombat)
	if not shouldUseDruidFormDriver(cfg) then return nil end
	local showForms = cfg.showForms
	local clauses = {}
	local function appendClause(formCondition)
		local cond = formCondition
		if hideOutOfCombat then
			if cond and cond ~= "" then
				cond = "combat," .. cond
			else
				cond = "combat"
			end
		end
		if cond and cond ~= "" then clauses[#clauses + 1] = ("[%s] show"):format(cond) end
	end

	if showForms.HUMANOID ~= false then
		local humanoidCondition
		if druidStanceString and druidStanceString ~= "" then
			humanoidCondition = "nostance:" .. druidStanceString
		else
			humanoidCondition = "nostance"
		end
		appendClause(humanoidCondition)
	end
	for i = 2, #DRUID_FORM_SEQUENCE do
		local key = DRUID_FORM_SEQUENCE[i]
		if showForms[key] ~= false then
			local idx = formKeyToIndex[key]
			if idx and idx > 0 then appendClause("stance:" .. idx) end
		end
	end
	if #clauses == 0 then return "hide" end
	clauses[#clauses + 1] = "hide"
	return table.concat(clauses, "; ")
end

local function buildVisibilityDriverForBar(cfg)
	local hideOOC = shouldHideResourceBarsOutOfCombat()
	local hideMounted = shouldHideResourceBarsMounted()
	local hideVehicle = shouldHideResourceBarsInVehicle()
	cfg = cfg or {}
	local druidExpr = buildDruidVisibilityExpression(cfg, hideOOC)
	if not hideOOC and not hideMounted and not hideVehicle and not druidExpr then return nil, false end

	local clauses = {}
	if hideVehicle then clauses[#clauses + 1] = "[vehicleui] hide" end
	if hideMounted then
		clauses[#clauses + 1] = "[mounted] hide"
		if addon.variables.unitClass == "DRUID" then
			local travelIdx = formKeyToIndex.TRAVEL
			if travelIdx and travelIdx > 0 then clauses[#clauses + 1] = ("[stance:%d] hide"):format(travelIdx) end
			local stagIdx = formKeyToIndex.STAG
			if stagIdx and stagIdx > 0 then clauses[#clauses + 1] = ("[stance:%d] hide"):format(stagIdx) end
		end
	end

	if druidExpr then
		clauses[#clauses + 1] = druidExpr
	elseif hideOOC then
		clauses[#clauses + 1] = OOC_VISIBILITY_DRIVER
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
			if not shouldHideResourceBarsMounted() and not shouldHideResourceBarsInVehicle() then return end
			local mounted = IsMounted and IsMounted() or false
			if not ResourceBars._pendingVisibilityDriver and self._playerMounted == mounted then return end
			self._playerMounted = mounted
		elseif event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
			if unit and unit ~= "player" then return end
			if not shouldHideResourceBarsInVehicle() then return end
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

local function applyVisibilityDriverToFrame(frame, expression)
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
	if not canApplyVisibilityDriver() then return end
	ResourceBars._pendingVisibilityDriver = nil
	local enabled = not (addon and addon.db and addon.db.enableResourceFrame == false)
	local driverWasActive = ResourceBars._visibilityDriverActive == true
	if not enabled then
		forEachResourceBarFrame(function(frame)
			applyVisibilityDriverToFrame(frame, nil)
			if frame then frame._rbDruidFormDriver = nil end
		end)
		ResourceBars._visibilityDriverActive = false
		return
	end
	local driverActiveNow = false
	forEachResourceBarFrame(function(frame, pType)
		local cfg = resolveBarConfigForFrame(pType, frame)
		local enabled = cfg and cfg.enabled == true
		if enabled then
			local expr, hasDruidRule = buildVisibilityDriverForBar(cfg)
			if expr then driverActiveNow = true end
			applyVisibilityDriverToFrame(frame, expr)
			frame._rbDruidFormDriver = hasDruidRule or nil
		else
			applyVisibilityDriverToFrame(frame, nil)
			if frame then frame._rbDruidFormDriver = nil end
		end
	end)
	ResourceBars._visibilityDriverActive = driverActiveNow
	if driverWasActive and not driverActiveNow and context ~= "fromSetPowerbars" and frameAnchor then setPowerbars() end
end

local resourceBarsLoaded = addon.Aura.ResourceBars ~= nil
local function LoadResourceBars()
	if not resourceBarsLoaded then
		addon.Aura.ResourceBars = addon.Aura.ResourceBars or {}
		resourceBarsLoaded = true
	end
end

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

-- Coalesce spec/trait refreshes to avoid duplicate work or timing races
local function scheduleSpecRefresh()
	if not After then
		-- First detach all bar points to avoid transient loops
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.DetachAllBars then addon.Aura.ResourceBars.DetachAllBars() end
		ResourceBars._suspendAnchors = true
		setPowerbars()
		ResourceBars._suspendAnchors = false
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorAll then addon.Aura.ResourceBars.ReanchorAll() end
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ForceRuneRecolor then addon.Aura.ResourceBars.ForceRuneRecolor() end
		updatePowerBar("RUNES")
		return
	end
	if frameAnchor and frameAnchor._specRefreshScheduled then return end
	if frameAnchor then frameAnchor._specRefreshScheduled = true end
	After(0.08, function()
		if frameAnchor then frameAnchor._specRefreshScheduled = false end
		-- First detach all bar points to avoid transient loops
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.DetachAllBars then addon.Aura.ResourceBars.DetachAllBars() end
		ResourceBars._suspendAnchors = true
		setPowerbars()
		ResourceBars._suspendAnchors = false
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorAll then addon.Aura.ResourceBars.ReanchorAll() end
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ForceRuneRecolor then addon.Aura.ResourceBars.ForceRuneRecolor() end
		updatePowerBar("RUNES")
	end)
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
	elseif event == "PLAYER_ENTERING_WORLD" then
		updateHealthBar("UNIT_ABSORB_AMOUNT_CHANGED")
		setPowerbars()
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
	elseif (event == "UNIT_MAXHEALTH" or event == "UNIT_HEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED") and healthBar and healthBar:IsShown() then
		if event == "UNIT_MAXHEALTH" then
			local max = UnitHealthMax("player")
			healthBar._lastMax = max
			healthBar:SetMinMaxValues(0, max)
		end
		updateHealthBar(event)
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
	for _, event in ipairs(eventsToRegister) do
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
	if ResourceBars and ResourceBars.SyncRelativeFrameWidths then ResourceBars.SyncRelativeFrameWidths() end
	if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
end

function ResourceBars.DisableResourceBars()
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
	local spec = addon.variables.unitSpec
	rb._dkColor = DK_SPEC_COLOR[spec] or DK_SPEC_COLOR[1]
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
				local defaultW = (pType == "HEALTH") and DEFAULT_HEALTH_WIDTH or DEFAULT_POWER_WIDTH
				local defaultH = (pType == "HEALTH") and DEFAULT_HEALTH_HEIGHT or DEFAULT_POWER_HEIGHT
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
	local width = max(MIN_RESOURCE_BAR_WIDTH, w or DEFAULT_HEALTH_WIDTH)
	local height = h or DEFAULT_HEALTH_HEIGHT
	if healthBar then healthBar:SetSize(width, height) end
	if ResourceBars and ResourceBars.SyncRelativeFrameWidths then ResourceBars.SyncRelativeFrameWidths() end
end

function ResourceBars.SetPowerBarSize(w, h, pType)
	local changed = {}
	-- Ensure sane defaults if nil provided
	if pType then
		local s = getBarSettings(pType)
		local defaultW = DEFAULT_POWER_WIDTH
		local defaultH = DEFAULT_POWER_HEIGHT
		w = max(MIN_RESOURCE_BAR_WIDTH, w or (s and s.width) or defaultW)
		h = h or (s and s.height) or defaultH
	end
	if pType then
		if powerbar[pType] then
			powerbar[pType]:SetSize(w, h)
			changed[getFrameName(pType)] = true
		end
	else
		local width = max(MIN_RESOURCE_BAR_WIDTH, w or DEFAULT_POWER_WIDTH)
		local height = h or DEFAULT_POWER_HEIGHT
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
			local anchor = cfg.anchor
			if anchor and changed[anchor.relativeFrame] then
				local frame = bType == "HEALTH" and healthBar or powerbar[bType]
				if frame then
					local rel = _G[anchor.relativeFrame] or UIParent
					-- Ensure we don't accumulate multiple points to stale relatives
					frame:ClearAllPoints()
					frame:SetPoint(anchor.point or "CENTER", rel, anchor.relativePoint or anchor.point or "CENTER", anchor.x or 0, anchor.y or 0)
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
		local anch = cfg and cfg.anchor
		if anch and anch.relativeFrame == frameName then
			local frame = (bType == "HEALTH") and healthBar or powerbar[bType]
			if frame then
				local rel = _G[anch.relativeFrame] or UIParent
				frame:ClearAllPoints()
				frame:SetPoint(anch.point or "TOPLEFT", rel, anch.relativePoint or anch.point or "TOPLEFT", anch.x or 0, anch.y or 0)
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
				local w = healthBar:GetWidth() or DEFAULT_HEALTH_WIDTH
				local h = healthBar:GetHeight() or DEFAULT_HEALTH_HEIGHT
				a.x = (pw - w) / 2
				a.y = (h - ph) / 2
			end
		end
		local rel, looped = resolveAnchor(a, "HEALTH")
		if looped and (a.relativeFrame or "UIParent") ~= "UIParent" then
			local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
			local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
			local w = healthBar:GetWidth() or DEFAULT_HEALTH_WIDTH
			local h = healthBar:GetHeight() or DEFAULT_HEALTH_HEIGHT
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
					local w = bar:GetWidth() or DEFAULT_POWER_WIDTH
					local h = bar:GetHeight() or DEFAULT_POWER_HEIGHT
					a.x = (pw - w) / 2
					a.y = (h - ph) / 2
				end
			end
			if
				a.autoSpacing
				or (a.autoSpacing == nil and isEQOLFrameName(a.relativeFrame) and (a.point or "TOPLEFT") == "TOPLEFT" and (a.relativePoint or "BOTTOMLEFT") == "BOTTOMLEFT" and (a.x or 0) == 0)
			then
				a.x = 0
				a.y = DEFAULT_STACK_SPACING
				a.autoSpacing = true
			end
			local rel, looped = resolveAnchor(a, pType)
			if looped and (a.relativeFrame or "UIParent") ~= "UIParent" then
				local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
				local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
				local w = bar:GetWidth() or DEFAULT_POWER_WIDTH
				local h = bar:GetHeight() or DEFAULT_POWER_HEIGHT
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
			bar:SetMovable(isUI)
			bar:EnableMouse(isUI)

			local cfg = getBarSettings(pType)
			bar._cfg = cfg
			local defaultStyle = (pType == "MANA") and "PERCENT" or "CURMAX"
			bar._style = (cfg and cfg.textStyle) or defaultStyle

			if pType == "RUNES" then
				layoutRunes(bar)
				updatePowerBar("RUNES")
			else
				updatePowerBar(pType)
			end
			if ResourceBars.separatorEligible[pType] then updateBarSeparators(pType) end
		end
	end
	-- Apply styling updates without forcing a full rebuild
	if healthBar then
		local hCfg = getBarSettings("HEALTH") or {}
		healthBar._cfg = hCfg
		healthBar:SetStatusBarTexture(resolveTexture(hCfg))
		configureSpecialTexture(healthBar, "HEALTH", hCfg)
		applyBackdrop(healthBar, hCfg)
		if healthBar.text then applyFontToString(healthBar.text, hCfg) end
		applyTextPosition(healthBar, hCfg, 3, 0)
		configureBarBehavior(healthBar, hCfg, "HEALTH")
		if healthBar.absorbBar then
			healthBar.absorbBar:SetStatusBarTexture(resolveTexture(hCfg))
			if hCfg.verticalFill then
				healthBar.absorbBar:SetOrientation("VERTICAL")
			else
				healthBar.absorbBar:SetOrientation("HORIZONTAL")
			end
			if healthBar.absorbBar.SetReverseFill then healthBar.absorbBar:SetReverseFill(hCfg.reverseFill == true) end
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
			if pType == "RUNES" then layoutRunes(bar) end
		end
	end
	if ResourceBars and ResourceBars.SyncRelativeFrameWidths then ResourceBars.SyncRelativeFrameWidths() end
	updateHealthBar("UNIT_ABSORB_AMOUNT_CHANGED")
	if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
	-- Ensure RUNES animation stops when not visible/enabled
	local rcfg = getBarSettings("RUNES")
	local runesEnabled = rcfg and (rcfg.enabled == true)
	if powerbar and powerbar.RUNES and (not powerbar.RUNES:IsShown() or not runesEnabled) then deactivateRuneTicker(powerbar.RUNES) end
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
		entry = { mode = mode, nextRunAt = now + REFRESH_DEBOUNCE }
		pending[spec] = entry
	else
		if entry.mode ~= "full" and mode == "full" then entry.mode = "full" end
		entry.nextRunAt = now + REFRESH_DEBOUNCE
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
				local w = healthBar:GetWidth() or DEFAULT_HEALTH_WIDTH
				local h = healthBar:GetHeight() or DEFAULT_HEALTH_HEIGHT
				a.x = (pw - w) / 2
				a.y = (h - ph) / 2
			end
		end
		local rel, looped = resolveAnchor(a, "HEALTH")
		if looped and (a.relativeFrame or "UIParent") ~= "UIParent" then
			local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
			local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
			local w = healthBar:GetWidth() or DEFAULT_HEALTH_WIDTH
			local h = healthBar:GetHeight() or DEFAULT_HEALTH_HEIGHT
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
			local w = (bar and bar.GetWidth and bar:GetWidth()) or DEFAULT_POWER_WIDTH
			local h = (bar and bar.GetHeight and bar:GetHeight()) or DEFAULT_POWER_HEIGHT
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
				a.y = DEFAULT_STACK_SPACING
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
			bar:EnableMouse(isUI)
		end
	end

	updateHealthBar("UNIT_ABSORB_AMOUNT_CHANGED")
	if ResourceBars and ResourceBars.SyncRelativeFrameWidths then ResourceBars.SyncRelativeFrameWidths() end
	ResourceBars._reanchoring = false
end

return ResourceBars
