-- luacheck: globals C_GameRules GetIconForRole
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Aura = addon.Aura or {}
addon.Aura.UFHelper = addon.Aura.UFHelper or {}
local H = addon.Aura.UFHelper

addon.variables = addon.variables or {}

local LSM = LibStub("LibSharedMedia-3.0")
local CASTING_BAR_TYPES = _G.CASTING_BAR_TYPES
local EnumPowerType = Enum and Enum.PowerType
local BLIZZARD_TEX = "Interface\\TargetingFrame\\UI-StatusBar"
local DEFAULT_AURA_BORDER_TEX = "Interface\\Buttons\\UI-Debuff-Overlays"
local DEFAULT_AURA_BORDER_COORDS = { 0.296875, 0.5703125, 0, 0.515625 }
local CombatFeedback_Initialize = _G.CombatFeedback_Initialize
local CombatFeedback_OnCombatEvent = _G.CombatFeedback_OnCombatEvent
local CombatFeedback_OnUpdate = _G.CombatFeedback_OnUpdate
local NewTicker = C_Timer and C_Timer.NewTicker
local GetTime = _G.GetTime
local COMBAT_FEEDBACK_THROTTLE = 0.1
local abs = math.abs
local floor = math.floor
local UnitThreatSituation = UnitThreatSituation
local UnitExists = UnitExists
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitHealthPercent = UnitHealthPercent
local C_UnitAuras = C_UnitAuras
local UIParent = UIParent

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

local npcColorDefaults = {
	enemy = { 0.95, 0.15, 0.15, 1 },
	neutral = { 1, 1, 0, 1 },
	friendly = { 0.2, 1, 0.2, 1 },
}

local debuffinfo = {
	[1] = DEBUFF_TYPE_MAGIC_COLOR,
	[2] = DEBUFF_TYPE_CURSE_COLOR,
	[3] = DEBUFF_TYPE_DISEASE_COLOR,
	[4] = DEBUFF_TYPE_POISON_COLOR,
	[5] = DEBUFF_TYPE_BLEED_COLOR,
	[0] = DEBUFF_TYPE_NONE_COLOR,
}
local dispelIndexByName = {
	Magic = 1,
	Curse = 2,
	Disease = 3,
	Poison = 4,
	Bleed = 5,
	None = 0,
}

local function getDebuffColorFromName(name)
	local idx = dispelIndexByName[name] or 0
	local col = debuffinfo[idx] or debuffinfo[0]
	if not col then return nil end
	if col.GetRGBA then return col:GetRGBA() end
	if col.GetRGB then return col:GetRGB() end
	if col.r then return col.r, col.g, col.b, col.a end
	return col[1], col[2], col[3], col[4]
end

H.getDebuffColorFromName = getDebuffColorFromName

local debuffColorCurve = C_CurveUtil and C_CurveUtil.CreateColorCurve() or nil
if debuffColorCurve and Enum.LuaCurveType and Enum.LuaCurveType.Step then
	debuffColorCurve:SetType(Enum.LuaCurveType.Step)
	for dispeltype, v in pairs(debuffinfo) do
		debuffColorCurve:AddPoint(dispeltype, v)
	end
end

H.debuffColorCurve = debuffColorCurve

local absorbFullCurve = C_CurveUtil and C_CurveUtil.CreateCurve() or nil
if absorbFullCurve and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
	absorbFullCurve:SetType(Enum.LuaCurveType.Step)
	absorbFullCurve:AddPoint(1.0, 1)
	absorbFullCurve:AddPoint(0.9, 0)
end

local absorbNotFullCurve = C_CurveUtil and C_CurveUtil.CreateCurve() or nil
if absorbNotFullCurve and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
	absorbNotFullCurve:SetType(Enum.LuaCurveType.Step)
	absorbNotFullCurve:AddPoint(1.0, 0)
	absorbNotFullCurve:AddPoint(0.9, 1)
end

H.absorbFullCurve = absorbFullCurve
H.absorbNotFullCurve = absorbNotFullCurve

local npcColorUnits = {
	target = true,
	targettarget = true,
	focus = true,
	boss = true,
}
for i = 1, (MAX_BOSS_FRAMES or 5) do
	npcColorUnits["boss" .. i] = true
end

local selectionKeyByType = {
	[0] = "enemy",
	[1] = "enemy",
	[2] = "neutral",
	[3] = "friendly",
}

function H.getNPCSelectionKey(unit)
	if not npcColorUnits[unit] then return nil end
	if UnitIsPlayer and UnitIsPlayer(unit) then return nil end
	local t = UnitSelectionType and UnitSelectionType(unit)
	return selectionKeyByType[t]
end

function H.getNPCOverrideColor(unit)
	local overrides = addon.db and addon.db.ufNPCColorOverrides
	if not overrides then return nil end

	local key = H.getNPCSelectionKey(unit)
	if not key then return nil end
	local override = overrides[key]
	if override then
		if override.r then return override.r, override.g, override.b, override.a or 1 end
		if override[1] then return override[1], override[2], override[3], override[4] or 1 end
	end
	return nil
end

function H.getNPCHealthColor(unit)
	local key = H.getNPCSelectionKey(unit)
	if not key then return nil end
	return H.getNPCColor(key)
end

local nameWidthCache = {}
local DROP_SHADOW_FLAG = "DROPSHADOW"

local function utf8Iter(str) return (str or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") end

local function utf8Len(str)
	local len = 0
	for _ in utf8Iter(str) do
		len = len + 1
	end
	return len
end

local function utf8Sub(str, i, j)
	str = str or ""
	if str == "" then return "" end
	i = i or 1
	j = j or -1
	if i < 1 then i = 1 end
	local len = utf8Len(str)
	if j < 0 then j = len + j + 1 end
	if j > len then j = len end
	if i > j then return "" end
	local pos = 1
	local startByte, endByte
	local idx = 0
	for char in utf8Iter(str) do
		idx = idx + 1
		if idx == i then startByte = pos end
		if idx == j then
			endByte = pos + #char - 1
			break
		end
		pos = pos + #char
	end
	return str:sub(startByte or 1, endByte or #str)
end

local function normalizeFontOutline(outline)
	if outline == nil then return "OUTLINE" end
	if outline == "" or outline == "NONE" or outline == DROP_SHADOW_FLAG then return nil end
	return outline
end

local function wantsDropShadow(outline) return outline == DROP_SHADOW_FLAG end

function H.clamp(value, minV, maxV)
	if value < minV then return minV end
	if value > maxV then return maxV end
	return value
end

function H.ClampNumber(value, minValue, maxValue, fallback)
	local v = tonumber(value)
	if v == nil then return fallback end
	if minValue ~= nil and v < minValue then v = minValue end
	if maxValue ~= nil and v > maxValue then v = maxValue end
	return v
end

function H.shouldHideInClientScene(cfg, def)
	local value = cfg and cfg.hideInClientScene
	if value == nil then value = def and def.hideInClientScene end
	if value == nil then value = true end
	return value == true
end

function H.applyClientSceneAlphaOverride(st, forceHide)
	if not (st and st.frame and st.frame.SetAlpha) then return end
	if forceHide then
		st._eqolClientSceneAlphaHidden = true
		if st.frame.GetAlpha and st.frame:GetAlpha() ~= 0 then st.frame:SetAlpha(0) end
	elseif st._eqolClientSceneAlphaHidden then
		st._eqolClientSceneAlphaHidden = nil
		if st.frame.GetAlpha and st.frame:GetAlpha() == 0 then st.frame:SetAlpha(1) end
	end
end

function H.getClampedAbsorbAmount(unit) return UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0 end

function H.getHealthCurveValue(unit, curve)
	if not curve or not unit then return nil end
	return UnitHealthPercent(unit, true, curve)
end

function H.setupAbsorbClamp(health, absorb)
	if not (health and absorb) then return end

	if not health.absorbClip then
		local clip = CreateFrame("Frame", nil, health)
		clip:SetAllPoints(health)
		clip:SetClipsChildren(true)
		clip:SetFrameLevel(health:GetFrameLevel() + 5)
		health.absorbClip = clip
	end

	local clip = health.absorbClip

	absorb:SetParent(clip)
	absorb:ClearAllPoints()

	local htex = health:GetStatusBarTexture()

	absorb:SetPoint("TOPLEFT", htex, "TOPRIGHT", 0, 0)
	absorb:SetPoint("BOTTOMLEFT", htex, "BOTTOMRIGHT", 0, 0)

	absorb:SetWidth(health:GetWidth())
	absorb:SetHeight(health:GetHeight())
end

function H.setupAbsorbClampReverseAware(health, absorb)
	H.setupAbsorbClamp(health, absorb)

	local htex = health:GetStatusBarTexture()
	absorb:ClearAllPoints()

	local reverse = false
	if health.GetFillStyle and Enum and Enum.StatusBarFillStyle then
		reverse = health:GetFillStyle() == Enum.StatusBarFillStyle.Reverse
	elseif health.GetReverseFill then
		reverse = health:GetReverseFill() == true
	end

	H.applyStatusBarReverseFill(absorb, reverse)

	if reverse then
		absorb:SetPoint("TOPRIGHT", htex, "TOPLEFT", 0, 0)
		absorb:SetPoint("BOTTOMRIGHT", htex, "BOTTOMLEFT", 0, 0)
	else
		absorb:SetPoint("TOPLEFT", htex, "TOPRIGHT", 0, 0)
		absorb:SetPoint("BOTTOMLEFT", htex, "BOTTOMRIGHT", 0, 0)
	end

	absorb:SetWidth(health:GetWidth())
	absorb:SetHeight(health:GetHeight())
end

function H.setupAbsorbOverShift(healthBar, overAbsorbBar, height, maxHeight)
	if not (healthBar and overAbsorbBar) then return end

	local htex = healthBar:GetStatusBarTexture()

	if not healthBar._healthFillClip then
		local clip = CreateFrame("Frame", nil, healthBar)
		clip:SetClipsChildren(true)
		clip:SetFrameLevel(healthBar:GetFrameLevel() + 6)
		healthBar._healthFillClip = clip
	end

	local clip = healthBar._healthFillClip
	clip:ClearAllPoints()

	if healthBar:GetReverseFill() then
		clip:SetPoint("TOPLEFT", htex, "TOPLEFT", 0, 0)
		clip:SetPoint("BOTTOMLEFT", htex, "BOTTOMLEFT", 0, 0)
		clip:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
		clip:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
	else
		clip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
		clip:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
		clip:SetPoint("TOPRIGHT", htex, "TOPRIGHT", 0, 0)
		clip:SetPoint("BOTTOMRIGHT", htex, "BOTTOMRIGHT", 0, 0)
	end

	overAbsorbBar:SetParent(clip)
	overAbsorbBar:ClearAllPoints()

	local desired = tonumber(height)
	local limit = tonumber(maxHeight)
	if not limit or limit <= 0 then limit = healthBar.GetHeight and healthBar:GetHeight() or 0 end
	if not desired or desired <= 0 then
		overAbsorbBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
		overAbsorbBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
	else
		if limit and limit > 0 and desired > limit then desired = limit end
		overAbsorbBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
		overAbsorbBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
		overAbsorbBar:SetHeight(desired)
	end

	overAbsorbBar:SetOrientation("HORIZONTAL")

	overAbsorbBar:SetReverseFill(not healthBar:GetReverseFill())
end

function H.applyAbsorbClampLayout(bar, healthBar, height, maxHeight, reverseHealth)
	if not bar or not healthBar then return end
	bar:ClearAllPoints()
	local anchor = (healthBar.GetStatusBarTexture and healthBar:GetStatusBarTexture()) or healthBar
	local bottomPoint = reverseHealth and "BOTTOMRIGHT" or "BOTTOMLEFT"
	local bottomAnchor = reverseHealth and "BOTTOMLEFT" or "BOTTOMRIGHT"
	local topPoint = reverseHealth and "TOPRIGHT" or "TOPLEFT"
	local topAnchor = reverseHealth and "TOPLEFT" or "TOPRIGHT"
	bar:SetPoint(bottomPoint, anchor, bottomAnchor, 0, 0)
	local desired = tonumber(height)
	local limit = tonumber(maxHeight)
	if not limit or limit <= 0 then limit = healthBar.GetHeight and healthBar:GetHeight() or 0 end
	if not desired or desired <= 0 then
		bar:SetPoint(topPoint, anchor, topAnchor, 0, 0)
	else
		if limit and limit > 0 and desired > limit then desired = limit end
		bar:SetHeight(desired)
	end
	if healthBar.GetWidth then bar:SetWidth(healthBar:GetWidth() or 0) end
end

function H.trim(str)
	if type(str) ~= "string" then return "" end
	return str:match("^%s*(.-)%s*$")
end

function H.getFont(path)
	if type(path) == "string" and path ~= "" then
		local lower = path:lower()
		if path:find("\\") or path:find("/") or lower:find(".ttf", 1, true) or lower:find(".otf", 1, true) or lower:find(".ttc", 1, true) then return path end
		if LSM and LSM.Fetch then
			local fetched = LSM:Fetch("font", path, true)
			if type(fetched) == "string" and fetched ~= "" then return fetched end
		end
		return path
	end
	return addon.variables and addon.variables.defaultFont or (LSM and LSM:Fetch("font", LSM.DefaultMedia.font)) or STANDARD_TEXT_FONT
end

function H.applyFont(fs, fontPath, size, outline)
	if not fs then return end
	local flags = normalizeFontOutline(outline)
	local fontFile = H.getFont(fontPath)
	if size == nil or size <= 0 then size = 1 end
	local ok = fs.SetFont and fs:SetFont(fontFile, size or 14, flags)
	if not ok and fontPath and fontPath ~= "" then fs:SetFont(H.getFont(nil), size or 14, flags) end
	if wantsDropShadow(outline) then
		fs:SetShadowColor(0, 0, 0, 0.5)
		fs:SetShadowOffset(0.5, -0.5)
	else
		fs:SetShadowColor(0, 0, 0, 0)
		fs:SetShadowOffset(0, 0)
	end
end

local function ensureCooldownFontDefault(cooldown, fontString)
	if not cooldown or not fontString or cooldown._eqolCooldownFontDefault then return end
	local fontFile, fontSize, fontFlags = fontString:GetFont()
	if not fontFile or not fontSize then return end
	cooldown._eqolCooldownFontDefault = {
		font = fontFile,
		size = fontSize,
		flags = fontFlags,
	}
end

function H.applyCooldownTextStyle(cooldown, size)
	if not cooldown or not cooldown.GetCountdownFontString then return end
	local fontString = cooldown:GetCountdownFontString()
	if not fontString or not fontString.GetFont or not fontString.SetFont then return end
	ensureCooldownFontDefault(cooldown, fontString)
	local def = cooldown._eqolCooldownFontDefault
	if not def or not def.font or not def.size then return end
	local desired = tonumber(size) or 0
	local flags = def.flags or ""
	if desired > 0 then
		local key = def.font .. "|" .. tostring(desired) .. "|" .. tostring(flags)
		if cooldown._eqolCooldownFontKey == key then return end
		fontString:SetFont(def.font, desired, flags)
		cooldown._eqolCooldownFontKey = key
	else
		local key = "default|" .. def.font .. "|" .. tostring(def.size) .. "|" .. tostring(flags)
		if cooldown._eqolCooldownFontKey == key then return end
		fontString:SetFont(def.font, def.size, flags)
		cooldown._eqolCooldownFontKey = key
	end
end

function H.resolveBorderTexture(key)
	if not key or key == "" or key == "DEFAULT" then return "Interface\\Buttons\\WHITE8x8" end
	if LSM then
		local tex = LSM:Fetch("border", key)
		if tex and tex ~= "" then return tex end
	end
	return key
end

function H.resolveAuraBorderTexture(key)
	if not key or key == "" or key == "DEFAULT" then return DEFAULT_AURA_BORDER_TEX, DEFAULT_AURA_BORDER_COORDS, false end
	if LSM then
		local tex = LSM:Fetch("border", key)
		if tex and tex ~= "" then return tex, nil, true end
	end
	return key, nil, false
end

function H.ensureAuraBorderFrame(btn)
	if not btn then return nil end
	local border = btn._eqolAuraBorder
	if not border then
		border = CreateFrame("Frame", nil, btn.overlay or btn, "BackdropTemplate")
		border:EnableMouse(false)
		btn._eqolAuraBorder = border
	end
	local parent = btn.overlay or btn
	border:SetParent(parent)
	border:SetFrameStrata(parent:GetFrameStrata() or btn:GetFrameStrata())
	local baseLevel = parent:GetFrameLevel() or btn:GetFrameLevel() or 0
	border:SetFrameLevel(baseLevel + 1)
	border:ClearAllPoints()
	border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
	border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
	return border
end

function H.hideAuraBorderFrame(btn)
	local border = btn and btn._eqolAuraBorder
	if border then border:Hide() end
end

function H.calcAuraBorderSize(btn, ac)
	local baseSize = (btn and btn.GetWidth and btn:GetWidth()) or (ac and ac.size) or 24
	local size = floor((baseSize or 24) * 0.08 + 0.5)
	if size < 1 then size = 1 end
	if size > 6 then size = 6 end
	return size
end

local PRIVATE_AURA_INVERSE_POINTS = {
	TOP = "BOTTOM",
	BOTTOM = "TOP",
	LEFT = "RIGHT",
	RIGHT = "LEFT",
	TOPLEFT = "BOTTOMLEFT",
	TOPRIGHT = "BOTTOMRIGHT",
	BOTTOMLEFT = "TOPLEFT",
	BOTTOMRIGHT = "TOPRIGHT",
	CENTER = "CENTER",
}

local function inversePoint(point)
	if not point then return "CENTER" end
	local key = tostring(point):upper()
	return PRIVATE_AURA_INVERSE_POINTS[key] or "CENTER"
end

local function resolvePrivateAuraOffset(point, offset)
	local p = tostring(point or "RIGHT"):upper()
	local off = tonumber(offset) or 0
	if p == "LEFT" then return -off, 0 end
	if p == "TOP" then return 0, off end
	if p == "BOTTOM" then return 0, -off end
	return off, 0
end

local function resolvePrivateAuraUnitToken(unit)
	if type(unit) ~= "string" then return unit end
	if unit ~= "player" and UnitIsUnit then
		local ok, isPlayer = pcall(UnitIsUnit, unit, "player")
		if ok and isPlayer then return "player" end
	end
	return unit
end

local PRIVATE_AURA_SAMPLE_ICON_ID = 237555

local function ensurePrivateAuraSampleTexture(anchor)
	if not anchor then return nil end
	local tex = anchor._eqolPrivateAuraSample
	if not tex then
		tex = anchor:CreateTexture(nil, "OVERLAY")
		tex:SetAllPoints(anchor)
		tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		tex:SetTexture(PRIVATE_AURA_SAMPLE_ICON_ID)
		anchor._eqolPrivateAuraSample = tex
	end
	return tex
end

local privateAuraArgs = {
	unitToken = "player",
	parent = UIParent,
	auraIndex = 1,
	showCountdownFrame = true,
	showCountdownNumbers = true,
	iconInfo = {
		iconWidth = 32,
		iconHeight = 32,
		iconAnchor = {
			point = "CENTER",
			relativePoint = "CENTER",
			offsetX = 0,
			offsetY = 0,
		},
	},
}

local privateAuraDuration = {
	point = "CENTER",
	relativePoint = "CENTER",
	offsetX = 0,
	offsetY = 0,
}

local privateAuraShowDispelType = false
local privateAuraShowDispelCount = 0

local function removePrivateAuraAnchor(anchor)
	if anchor and anchor.anchorID and C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor then
		pcall(C_UnitAuras.RemovePrivateAuraAnchor, anchor.anchorID)
		anchor.anchorID = nil
	end
end

local function buildPrivateAuraAnchor(anchor, unit, index, size, borderScale, showFrame, showNumbers, durationEnabled, durationPoint, durationOffsetX, durationOffsetY)
	if not (C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor and anchor and unit and index) then return nil end
	privateAuraArgs.unitToken = unit
	privateAuraArgs.parent = anchor
	privateAuraArgs.auraIndex = index
	privateAuraArgs.showCountdownFrame = showFrame == true
	privateAuraArgs.showCountdownNumbers = showNumbers == true

	local icon = privateAuraArgs.iconInfo
	icon.iconWidth = size
	icon.iconHeight = size
	icon.borderScale = borderScale
	local iconAnchor = icon.iconAnchor
	iconAnchor.relativeTo = anchor
	iconAnchor.point = "CENTER"
	iconAnchor.relativePoint = "CENTER"
	iconAnchor.offsetX = 0
	iconAnchor.offsetY = 0

	if durationEnabled then
		privateAuraDuration.relativeTo = anchor
		privateAuraDuration.point = inversePoint(durationPoint)
		privateAuraDuration.relativePoint = tostring(durationPoint or "CENTER"):upper()
		privateAuraDuration.offsetX = durationOffsetX or 0
		privateAuraDuration.offsetY = durationOffsetY or 0
		privateAuraArgs.durationAnchor = privateAuraDuration
	else
		privateAuraArgs.durationAnchor = nil
	end

	local ok, anchorID = pcall(C_UnitAuras.AddPrivateAuraAnchor, privateAuraArgs)
	if ok then return anchorID end
	return nil
end

local function updatePrivateAuraShowDispelType(container, enabled)
	local want = enabled == true
	if not (C_UnitAuras and C_UnitAuras.TriggerPrivateAuraShowDispelType) then
		if container then container._eqolPrivateAuraShowDispelType = want end
		return
	end
	local prev = container and container._eqolPrivateAuraShowDispelType == true
	if prev == want then return end
	if container then container._eqolPrivateAuraShowDispelType = want end
	if want then
		privateAuraShowDispelCount = privateAuraShowDispelCount + 1
	else
		privateAuraShowDispelCount = privateAuraShowDispelCount - 1
		if privateAuraShowDispelCount < 0 then privateAuraShowDispelCount = 0 end
	end
	local show = privateAuraShowDispelCount > 0
	if privateAuraShowDispelType ~= show then
		privateAuraShowDispelType = show
		C_UnitAuras.TriggerPrivateAuraShowDispelType(show)
	end
end

local function ensurePrivateAuraSampleCooldown(anchor)
	if not anchor then return nil end
	local cd = anchor._eqolPrivateAuraSampleCooldown
	if not cd then
		cd = CreateFrame("Cooldown", nil, anchor, "CooldownFrameTemplate")
		cd:SetAllPoints(anchor)
		anchor._eqolPrivateAuraSampleCooldown = cd
	end
	return cd
end

local function ensurePrivateAuraSampleDuration(anchor)
	if not anchor then return nil end
	local fs = anchor._eqolPrivateAuraSampleDuration
	if not fs then
		fs = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		anchor._eqolPrivateAuraSampleDuration = fs
	end
	return fs
end

local function stripCooldownEdge(anchor)
	if not anchor or not anchor.GetRegions then return end
	for _, region in ipairs({ anchor:GetRegions() }) do
		if region and region.GetTexture and region.SetAlpha then
			local tex = region:GetTexture()
			if type(tex) == "string" and tex:find("Cooldown") and tex:find("edge") then region:SetAlpha(0) end
		end
	end
end

local function ensurePrivateAuraMousePassthrough(anchor)
	if not anchor then return nil end
	local blocker = anchor._eqolPrivateAuraBlocker
	if not blocker then
		blocker = CreateFrame("Button", nil, anchor)
		blocker:EnableMouse(true)
		if blocker.SetMouseClickEnabled then
			blocker:SetMouseClickEnabled(false)
		elseif blocker.SetPropagateMouseClicks then
			blocker:SetPropagateMouseClicks(true)
		end
		if blocker.SetScript then
			blocker:SetScript("OnEnter", function()
				if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
			end)
			blocker:SetScript("OnLeave", function()
				if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
			end)
		end
		if blocker.SetAllPoints then blocker:SetAllPoints(anchor) end
		anchor._eqolPrivateAuraBlocker = blocker
	end
	if blocker.GetParent and blocker:GetParent() ~= anchor then blocker:SetParent(anchor) end
	if blocker.SetFrameStrata and anchor.GetFrameStrata then blocker:SetFrameStrata(anchor:GetFrameStrata()) end
	if blocker.SetFrameLevel and anchor.GetFrameLevel then blocker:SetFrameLevel((anchor:GetFrameLevel() or 0) + 30) end
	if blocker.SetMouseClickEnabled then
		blocker:SetMouseClickEnabled(false)
	elseif blocker.SetPropagateMouseClicks then
		blocker:SetPropagateMouseClicks(true)
	end
	if blocker.SetScript then
		blocker:SetScript("OnEnter", function()
			if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
		end)
		blocker:SetScript("OnLeave", function()
			if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
		end)
	end
	if blocker.ClearAllPoints and blocker.SetPoint then
		blocker:ClearAllPoints()
		blocker:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
		blocker:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
	end
	blocker:Show()
	return blocker
end

function H.RemovePrivateAuras(container)
	if not container then return end
	updatePrivateAuraShowDispelType(container, false)
	if container._eqolPrivateAuraFrames then
		for _, anchor in ipairs(container._eqolPrivateAuraFrames) do
			removePrivateAuraAnchor(anchor)
			if anchor._eqolPrivateAuraBlocker and anchor._eqolPrivateAuraBlocker.Hide then anchor._eqolPrivateAuraBlocker:Hide() end
			if anchor.Hide then anchor:Hide() end
		end
	end
	container._eqolPrivateAuraState = nil
end

function H.ApplyPrivateAuras(container, unit, cfg, parent, levelFrame, showSample, inverseAnchor)
	if not container then return end
	if not (C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor) then return end
	cfg = cfg or {}
	local enabled = cfg.enabled == true
	if not enabled or not unit then
		H.RemovePrivateAuras(container)
		if container.Hide then container:Hide() end
		return
	end
	if unit == "target" then
		H.RemovePrivateAuras(container)
		if container.Hide then container:Hide() end
		return
	end
	if UnitExists and not showSample and not UnitExists(unit) then
		H.RemovePrivateAuras(container)
		if container.Hide then container:Hide() end
		return
	end

	local effectiveUnit = resolvePrivateAuraUnitToken(unit)
	local cacheState = unit == "player" or unit == "focus"

	local iconCfg = cfg.icon or {}
	local parentCfg = cfg.parent or {}
	local durationCfg = cfg.duration or {}

	local amount = floor(tonumber(iconCfg.amount) or 1)
	if amount < 1 then amount = 1 end
	local size = floor(tonumber(iconCfg.size) or 24)
	if size > 30 then size = 30 end
	if size < 4 then size = 4 end
	local iconPoint = tostring(iconCfg.point or "RIGHT"):upper()
	local iconOffset = tonumber(iconCfg.offset or iconCfg.spacing or 2) or 0
	local borderScale = tonumber(iconCfg.borderScale)
	if borderScale == nil then borderScale = 1 end

	local showFrame = cfg.countdownFrame ~= false
	local showNumbers = cfg.countdownNumbers ~= false
	local durationEnabled = durationCfg.enable == true
	local durationPoint = tostring(durationCfg.point or "CENTER"):upper()
	local durationOffsetX = tonumber(durationCfg.offsetX) or 0
	local durationOffsetY = tonumber(durationCfg.offsetY) or 0

	local parentPoint = tostring(parentCfg.point or "CENTER"):upper()
	local parentOffsetX = tonumber(parentCfg.offsetX) or 0
	local parentOffsetY = tonumber(parentCfg.offsetY) or 0
	local useInverse = inverseAnchor ~= false
	local anchorPoint = useInverse and inversePoint(parentPoint) or parentPoint

	if parent and container.GetParent and container:GetParent() ~= parent then container:SetParent(parent) end
	if container.SetFrameStrata and parent and parent.GetFrameStrata then container:SetFrameStrata(parent:GetFrameStrata()) end
	if levelFrame and container.SetFrameLevel and levelFrame.GetFrameLevel then container:SetFrameLevel((levelFrame:GetFrameLevel() or 0) + 5) end
	container:ClearAllPoints()
	container:SetPoint(anchorPoint, parent or container:GetParent() or UIParent, parentPoint, parentOffsetX, parentOffsetY)
	container:SetSize(size, size)
	container:Show()

	local state = cacheState and (container._eqolPrivateAuraState or {}) or {}
	local changed = not cacheState
		or state.unitToken ~= unit
		or state.effectiveUnit ~= effectiveUnit
		or state.amount ~= amount
		or state.size ~= size
		or state.countdownFrame ~= showFrame
		or state.countdownNumbers ~= showNumbers
		or state.borderScale ~= borderScale
		or state.durationEnabled ~= durationEnabled
		or state.durationPoint ~= durationPoint
		or state.durationOffsetX ~= durationOffsetX
		or state.durationOffsetY ~= durationOffsetY

	if cacheState then
		state.unitToken = unit
		state.effectiveUnit = effectiveUnit
		state.amount = amount
		state.size = size
		state.countdownFrame = showFrame
		state.countdownNumbers = showNumbers
		state.borderScale = borderScale
		state.durationEnabled = durationEnabled
		state.durationPoint = durationPoint
		state.durationOffsetX = durationOffsetX
		state.durationOffsetY = durationOffsetY
		container._eqolPrivateAuraState = state
	else
		container._eqolPrivateAuraState = nil
	end

	updatePrivateAuraShowDispelType(container, cfg.showDispelType == true)

	container._eqolPrivateAuraFrames = container._eqolPrivateAuraFrames or {}
	local anchors = container._eqolPrivateAuraFrames
	local attachPoint = inversePoint(iconPoint)
	local ox, oy = resolvePrivateAuraOffset(iconPoint, iconOffset)

	for i = 1, amount do
		local anchor = anchors[i]
		if not anchor then
			anchor = CreateFrame("Frame", nil, container)
			anchor:EnableMouse(false)
			anchors[i] = anchor
		end
		anchor:ClearAllPoints()
		if i == 1 then
			anchor:SetPoint("CENTER", container, "CENTER", 0, 0)
		else
			anchor:SetPoint(attachPoint, anchors[i - 1], iconPoint, ox, oy)
		end
		anchor:SetSize(size, size)
		anchor:Show()
		ensurePrivateAuraMousePassthrough(anchor)
		if showSample then
			local tex = ensurePrivateAuraSampleTexture(anchor)
			if tex then tex:Show() end
			local cd = ensurePrivateAuraSampleCooldown(anchor)
			if cd then
				cd:SetAllPoints(anchor)
				if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(not showNumbers) end
				local start = (GetTime and GetTime() or 0) - 10
				if CooldownFrame_Set then
					CooldownFrame_Set(cd, start, 30, true)
				elseif cd.SetCooldown then
					cd:SetCooldown(start, 30)
				end
				cd:SetShown(showFrame == true)
			end
			local dur = ensurePrivateAuraSampleDuration(anchor)
			if dur then
				if durationEnabled then
					dur:ClearAllPoints()
					dur:SetPoint(inversePoint(durationPoint), anchor, durationPoint, durationOffsetX, durationOffsetY)
					dur:SetText("12s")
					dur:Show()
				else
					dur:Hide()
				end
			end
		elseif anchor._eqolPrivateAuraSample then
			anchor._eqolPrivateAuraSample:Hide()
			if anchor._eqolPrivateAuraSampleCooldown then anchor._eqolPrivateAuraSampleCooldown:Hide() end
			if anchor._eqolPrivateAuraSampleDuration then anchor._eqolPrivateAuraSampleDuration:Hide() end
		end
		if changed or not anchor.anchorID then
			removePrivateAuraAnchor(anchor)
			anchor.anchorID = buildPrivateAuraAnchor(anchor, effectiveUnit, i, size, borderScale, showFrame, showNumbers, durationEnabled, durationPoint, durationOffsetX, durationOffsetY)
		end
		stripCooldownEdge(anchor)
	end
	for i = amount + 1, #anchors do
		removePrivateAuraAnchor(anchors[i])
		if anchors[i]._eqolPrivateAuraBlocker and anchors[i]._eqolPrivateAuraBlocker.Hide then anchors[i]._eqolPrivateAuraBlocker:Hide() end
		if anchors[i].Hide then anchors[i]:Hide() end
	end
end

local function ensureHighlightFrame(frame)
	if not frame then return nil end
	local highlight = frame._ufHighlight
	if not highlight then
		highlight = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		highlight:EnableMouse(false)
		frame._ufHighlight = highlight
	end
	highlight:SetFrameStrata(frame:GetFrameStrata())
	local baseLevel = frame:GetFrameLevel() or 0
	highlight:SetFrameLevel(baseLevel + 4)
	highlight:ClearAllPoints()
	highlight:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	highlight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	return highlight
end

function H.buildHighlightConfig(cfg, def)
	local hcfg = (cfg and cfg.highlight) or {}
	local hdef = (def and def.highlight) or {}
	local enabled = hcfg.enabled
	if enabled == nil then enabled = hdef.enabled end
	if enabled ~= true then return nil end
	local mouseover = hcfg.mouseover
	if mouseover == nil then mouseover = hdef.mouseover end
	if mouseover == nil then mouseover = true end
	local aggro = hcfg.aggro
	if aggro == nil then aggro = hdef.aggro end
	if aggro == nil then aggro = true end
	local texture = hcfg.texture or hdef.texture or "DEFAULT"
	local size = hcfg.size
	if size == nil then size = hdef.size end
	size = tonumber(size) or 1
	if size < 1 then size = 1 end
	local color = hcfg.color
	if type(color) ~= "table" then color = hdef.color end
	if type(color) ~= "table" then color = { 1, 0, 0, 1 } end
	return {
		enabled = true,
		mouseover = mouseover == true,
		aggro = aggro == true,
		texture = texture,
		size = size,
		color = color,
	}
end

function H.applyHighlightStyle(st, highlightCfg)
	if not st or not st.barGroup then return end
	if not highlightCfg or highlightCfg.enabled ~= true then
		local highlight = st.barGroup._ufHighlight
		if highlight then
			highlight:SetBackdrop(nil)
			highlight:Hide()
		end
		st._highlightFrame = nil
		return
	end
	local highlight = ensureHighlightFrame(st.barGroup)
	if not highlight then return end
	st._highlightFrame = highlight
	local size = highlightCfg.size or 1
	if size < 1 then size = 1 end
	local insetVal = highlightCfg.inset
	if insetVal == nil then insetVal = size end
	local color = highlightCfg.color or { 1, 0, 0, 1 }
	highlight:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = H.resolveBorderTexture(highlightCfg.texture),
		edgeSize = size,
		insets = { left = insetVal, right = insetVal, top = insetVal, bottom = insetVal },
	})
	highlight:SetBackdropColor(0, 0, 0, 0)
	highlight:SetBackdropBorderColor(color[1] or 1, color[2] or 0, color[3] or 0, color[4] or 1)
	highlight:Hide()
end

local function hasAggro(unit)
	if not UnitThreatSituation or not unit then return false end
	if UnitExists and not UnitExists(unit) then return false end
	local threat = UnitThreatSituation(unit)
	return threat and threat >= 2
end

function H.updateHighlight(st, unit, playerUnit)
	if not st or not st.barGroup then return end
	local cfg = st._highlightCfg
	local highlight = st.barGroup._ufHighlight
	if not cfg or cfg.enabled ~= true then
		if highlight then highlight:Hide() end
		return
	end
	if not highlight then
		H.applyHighlightStyle(st, cfg)
		highlight = st.barGroup._ufHighlight
		if not highlight then return end
	end
	local show = false
	if cfg.mouseover and st._hovered then
		show = true
	elseif cfg.aggro and (unit == (playerUnit or "player") or unit == "pet") and hasAggro(unit) then
		show = true
	end
	if show then
		local color = cfg.color or { 1, 0, 0, 1 }
		highlight:SetBackdropBorderColor(color[1] or 1, color[2] or 0, color[3] or 0, color[4] or 1)
		highlight:Show()
	else
		highlight:Hide()
	end
end

function H.updateAllHighlights(states, unitTokens, maxBossFrames)
	if type(states) ~= "table" or type(unitTokens) ~= "table" then return end
	local playerUnit = unitTokens.PLAYER or "player"
	H.updateHighlight(states[playerUnit], playerUnit, playerUnit)
	if unitTokens.TARGET then H.updateHighlight(states[unitTokens.TARGET], unitTokens.TARGET, playerUnit) end
	if unitTokens.TARGET_TARGET then H.updateHighlight(states[unitTokens.TARGET_TARGET], unitTokens.TARGET_TARGET, playerUnit) end
	if unitTokens.FOCUS then H.updateHighlight(states[unitTokens.FOCUS], unitTokens.FOCUS, playerUnit) end
	if unitTokens.PET then H.updateHighlight(states[unitTokens.PET], unitTokens.PET, playerUnit) end
	local maxBoss = tonumber(maxBossFrames) or 0
	for i = 1, maxBoss do
		local unit = "boss" .. i
		H.updateHighlight(states[unit], unit, playerUnit)
	end
end

function H.resolveTexture(key)
	if key == "SOLID" then return "Interface\\Buttons\\WHITE8x8" end
	if not key or key == "DEFAULT" then return BLIZZARD_TEX end
	if LSM then
		local tex = LSM:Fetch("statusbar", key)
		if tex then return tex end
	end
	return key
end

function H.resolveSeparatorTexture(key)
	if not key or key == "" or key == "SOLID" then return "Interface\\Buttons\\WHITE8x8" end
	if key == "DEFAULT" then return BLIZZARD_TEX end
	if LSM then
		local tex = LSM:Fetch("statusbar", key)
		if tex then return tex end
	end
	return key
end

function H.resolveCastTexture(key)
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

local function normalizePowerToken(powerToken)
	if type(powerToken) ~= "string" then return powerToken end
	if powerToken:sub(1, 11) == "POWER_TYPE_" then return powerToken:sub(12) end
	return powerToken
end

local canonicalPowerTokenByEnum = {
	[0] = "MANA",
	[1] = "RAGE",
	[2] = "FOCUS",
	[3] = "ENERGY",
	[4] = "CHI",
	[5] = "RUNES",
	[6] = "RUNIC_POWER",
	[7] = "SOUL_SHARDS",
	[8] = "LUNAR_POWER",
	[9] = "HOLY_POWER",
	[11] = "MAELSTROM",
	[13] = "INSANITY",
	[17] = "FURY",
	[18] = "PAIN",
}

local function getCanonicalPowerToken(powerEnum, powerToken)
	local enumKey = tonumber(powerEnum)
	if enumKey ~= nil then
		local canonical = canonicalPowerTokenByEnum[enumKey]
		if canonical and canonical ~= "" then return canonical end
	end
	local token = normalizePowerToken(powerToken)
	if type(token) == "string" and token ~= "" then return token end
	return nil
end

local function getPowerColorEntry(powerEnum, powerToken)
	if not PowerBarColor then return nil end
	local canonicalToken = getCanonicalPowerToken(powerEnum, powerToken)
	if canonicalToken then
		local entry = PowerBarColor[canonicalToken]
		if entry then return entry end
		entry = PowerBarColor["POWER_TYPE_" .. canonicalToken]
		if entry then return entry end
	end
	local enumKey = tonumber(powerEnum)
	if enumKey ~= nil then
		local entry = PowerBarColor[enumKey] or PowerBarColor[tostring(enumKey)]
		if entry then return entry end
	end
	local token = normalizePowerToken(powerToken)
	if type(token) == "string" and token ~= "" and token ~= canonicalToken then
		local entry = PowerBarColor[token]
		if entry then return entry end
		entry = PowerBarColor["POWER_TYPE_" .. token]
		if entry then return entry end
	end
	return nil
end

local function getPowerOverrideEntry(overrides, powerEnum, powerToken)
	if not overrides then return nil end
	local enumKey = tonumber(powerEnum)
	if enumKey ~= nil then
		local override = overrides[enumKey] or overrides[tostring(enumKey)]
		if override then return override end
	end
	local canonicalToken = getCanonicalPowerToken(powerEnum, powerToken)
	if type(canonicalToken) == "string" and canonicalToken ~= "" then
		local override = overrides[canonicalToken]
		if override then return override end
		override = overrides["POWER_TYPE_" .. canonicalToken]
		if override then return override end
	end
	local token = normalizePowerToken(powerToken)
	if type(token) == "string" and token ~= "" and token ~= canonicalToken then
		local override = overrides[token]
		if override then return override end
		override = overrides["POWER_TYPE_" .. token]
		if override then return override end
	end
	return nil
end

function H.configureSpecialTexture(bar, pType, texKey, cfg, powerEnum)
	if not bar then return end
	if not pType and powerEnum == nil then return end
	local resolvedToken = getCanonicalPowerToken(powerEnum, pType)
	local atlas = atlasByPower[resolvedToken]
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

H.getCanonicalPowerToken = getCanonicalPowerToken

local reverseStyle = Enum.StatusBarFillStyle and Enum.StatusBarFillStyle.Reverse or "REVERSE"
local standardStyle = Enum.StatusBarFillStyle and Enum.StatusBarFillStyle.Standard or "STANDARD"
function H.applyStatusBarReverseFill(bar, reverse)
	if not bar then return end
	if bar.SetFillStyle then
		bar:SetFillStyle(reverse and reverseStyle or standardStyle)
	elseif bar.SetReverseFill then
		bar:SetReverseFill(reverse and true or false)
	end
end

function H.shouldUseDefaultCastArt(st) return st and st.castUseDefaultArt == true end

local CAST_SPARK_WIDTH = 8
local CAST_SPARK_HEIGHT = 20
local CAST_SPARK_LAYER_DEFAULT = 3
local CAST_SPARK_LAYER_CUSTOM = 7
local EMPOWER_PIP_LAYER_DEFAULT = 2
local EMPOWER_PIP_LAYER_CUSTOM = 6
local EMPOWER_CUSTOM_PIP_MIN_WIDTH = 3
local EMPOWER_CUSTOM_PIP_MAX_WIDTH = 6
local EMPOWER_CUSTOM_PIP_ALPHA = 0.9
local EMPOWER_CUSTOM_PIP_LINE_SUBLEVEL = 5
local EMPOWER_CUSTOM_PIP_FX_SUBLEVEL = 7

local function getCustomPipDimensions(barHeight)
	local baseHeight = barHeight or 0
	if baseHeight <= 0 then baseHeight = 16 end
	local lineHeight = baseHeight
	local width = floor(baseHeight * 0.18)
	if width < EMPOWER_CUSTOM_PIP_MIN_WIDTH then width = EMPOWER_CUSTOM_PIP_MIN_WIDTH end
	if width > EMPOWER_CUSTOM_PIP_MAX_WIDTH then width = EMPOWER_CUSTOM_PIP_MAX_WIDTH end
	return width, lineHeight
end

local function setPipFxLayer(pip, layer, sublevel)
	if not pip then return end
	if pip.PipGlow and pip.PipGlow.SetDrawLayer then pip.PipGlow:SetDrawLayer(layer, sublevel) end
	if pip.FlakesBottom and pip.FlakesBottom.SetDrawLayer then pip.FlakesBottom:SetDrawLayer(layer, sublevel) end
	if pip.FlakesTop and pip.FlakesTop.SetDrawLayer then pip.FlakesTop:SetDrawLayer(layer, sublevel) end
	if pip.FlakesTop02 and pip.FlakesTop02.SetDrawLayer then pip.FlakesTop02:SetDrawLayer(layer, sublevel) end
	if pip.FlakesBottom02 and pip.FlakesBottom02.SetDrawLayer then pip.FlakesBottom02:SetDrawLayer(layer, sublevel) end
end

local function ensureCastSparkTextures(st)
	if not st or not st.castBar then return nil end
	local bar = st.castBar
	if not st.castSparkLayer then
		st.castSparkLayer = CreateFrame("Frame", nil, bar)
		st.castSparkLayer:SetAllPoints(bar)
		st.castSparkLayer:EnableMouse(false)
	end
	if st.castSparkLayer:GetParent() ~= bar then st.castSparkLayer:SetParent(bar) end
	st.castSparkLayer:SetFrameStrata(bar:GetFrameStrata())
	local baseLevel = bar:GetFrameLevel() or 0
	local layerOffset = H.shouldUseDefaultCastArt(st) and CAST_SPARK_LAYER_DEFAULT or CAST_SPARK_LAYER_CUSTOM
	st.castSparkLayer:SetFrameLevel(baseLevel + layerOffset)
	local layer = st.castSparkLayer
	local spark = st.castSpark
	if not spark then
		spark = layer:CreateTexture(nil, "OVERLAY", nil, 2)
		if spark.SetAtlas then spark:SetAtlas("ui-castingbar-pip", false) end
		spark:SetSize(CAST_SPARK_WIDTH, CAST_SPARK_HEIGHT)
		spark.offsetY = 0
		spark:Hide()
		st.castSpark = spark
	end
	if not st.castSparkGlow then
		local glow = layer:CreateTexture(nil, "OVERLAY", nil, 3)
		if glow.SetBlendMode then glow:SetBlendMode("ADD") end
		glow:Hide()
		st.castSparkGlow = glow
	end
	if not st.castSparkShadow then
		local shadow = layer:CreateTexture(nil, "OVERLAY", nil, 3)
		shadow:Hide()
		st.castSparkShadow = shadow
	end
	return spark
end

local function setSparkAtlas(spark, atlas)
	if not spark then return end
	if spark.SetAtlas then
		local current = spark.GetAtlas and spark:GetAtlas()
		if current ~= atlas then spark:SetAtlas(atlas, false) end
	end
end

local function updateSparkFx(st, barType)
	if not st then return end
	local glow = st.castSparkGlow
	local shadow = st.castSparkShadow
	if glow then glow:Hide() end
	if shadow then shadow:Hide() end
	if not st.castSpark then return end

	if barType == "channel" then
		if shadow and shadow.SetAtlas then shadow:SetAtlas("cast_channel_pipshadow", true) end
		if shadow then
			shadow:ClearAllPoints()
			shadow:SetPoint("RIGHT", st.castSpark, "LEFT", 1, 0)
			shadow:Show()
		end
		return
	end

	if not glow then return end
	if barType ~= "interrupted" and barType ~= "empowered" then
		if glow.SetAtlas then glow:SetAtlas("cast_standard_pipglow", true) end
		if glow.SetScale then glow:SetScale(1) end
		glow:ClearAllPoints()
		glow:SetPoint("RIGHT", st.castSpark, "LEFT", 2, 0)
		glow:Show()
	end
end

function H.hideCastSpark(st)
	if not st then return end
	if st.castSpark then st.castSpark:Hide() end
	if st.castSparkGlow then st.castSparkGlow:Hide() end
	if st.castSparkShadow then st.castSparkShadow:Hide() end
end

function H.updateCastSpark(st, overrideType)
	if not st or not st.castBar then return end
	local barType = overrideType
	if not barType then
		if st.castInterruptActive then
			barType = "interrupted"
		elseif st.castInfo then
			if st.castInfo.isEmpowered then
				barType = "empowered"
			elseif st.castInfo.isChannel then
				barType = "channel"
			else
				barType = "standard"
			end
		end
	end
	if not barType then
		H.hideCastSpark(st)
		return
	end
	local spark = ensureCastSparkTextures(st)
	if not spark then return end

	if barType == "interrupted" then
		setSparkAtlas(spark, "ui-castingbar-pip-red")
	elseif barType == "empowered" then
		setSparkAtlas(spark, "ui-castingbar-empower-cursor")
	else
		setSparkAtlas(spark, "ui-castingbar-pip")
	end
	spark:Show()
	updateSparkFx(st, barType)

	local barHeight = st.castBar:GetHeight()
	local sparkHeight = CAST_SPARK_HEIGHT
	if barHeight and barHeight > 0 then
		sparkHeight = barHeight + 8
		if sparkHeight < CAST_SPARK_HEIGHT then sparkHeight = CAST_SPARK_HEIGHT end
	end
	spark:SetSize(CAST_SPARK_WIDTH, sparkHeight)
	local extra = (barHeight and barHeight > 0) and (sparkHeight - barHeight) or 0
	if barType == "empowered" then
		spark.offsetY = (extra > 0) and (extra * 0.5) or 0
	else
		spark.offsetY = 0
	end

	local minVal, maxVal = st.castBar:GetMinMaxValues()
	local value = st.castBar:GetValue()
	if value == nil or maxVal == nil then
		H.hideCastSpark(st)
		return
	end
	if issecretvalue and ((minVal and issecretvalue(minVal)) or issecretvalue(value) or issecretvalue(maxVal)) then
		H.hideCastSpark(st)
		return
	end
	local range = (maxVal or 0) - (minVal or 0)
	if not range or range == 0 then
		H.hideCastSpark(st)
		return
	end
	local width = st.castBar:GetWidth()
	if not width or width <= 0 then return end
	local progress = (value - (minVal or 0)) / range
	if progress < 0 then
		progress = 0
	elseif progress > 1 then
		progress = 1
	end
	local offset = width * progress
	spark:SetPoint("CENTER", st.castBar, "LEFT", offset, spark.offsetY or 0)
end

local After = C_Timer and C_Timer.After
local UnitEmpoweredChannelDuration = _G.UnitEmpoweredChannelDuration
local UnitEmpoweredStagePercentages = _G.UnitEmpoweredStagePercentages
local UnitEmpoweredStageDurations = _G.UnitEmpoweredStageDurations
local GetUnitEmpowerHoldAtMaxTime = _G.GetUnitEmpowerHoldAtMaxTime
local GetUnitEmpowerStageDuration = _G.GetUnitEmpowerStageDuration

local function normalizeStageValues(...)
	local count = select("#", ...)
	if count == 1 and type((...)) == "table" then
		local src = ...
		local values = {}
		for i = 1, #src do
			values[i] = src[i]
		end
		return values
	end
	local values = {}
	for i = 1, count do
		local val = select(i, ...)
		if val ~= nil then values[#values + 1] = val end
	end
	return values
end

local function normalizeDurationMilliseconds(value)
	if type(value) ~= "number" then return nil end
	if issecretvalue and issecretvalue(value) then return nil end
	if value < 0 then return nil end
	if value > 20 then return value end
	return value * 1000
end

H.normalizeDurationMilliseconds = normalizeDurationMilliseconds

local function durationToMilliseconds(duration)
	if type(duration) == "number" then return normalizeDurationMilliseconds(duration) end
	if type(duration) ~= "table" then return nil end
	if duration.GetMilliseconds then
		local ms = duration:GetMilliseconds()
		if issecretvalue and issecretvalue(ms) then return nil end
		return ms
	end
	if duration.GetSeconds then
		local seconds = duration:GetSeconds()
		if issecretvalue and issecretvalue(seconds) then return nil end
		return normalizeDurationMilliseconds(seconds)
	end
	if duration.GetDuration then
		local value = duration:GetDuration()
		if issecretvalue and issecretvalue(value) then return nil end
		if type(value) == "number" then return normalizeDurationMilliseconds(value) end
	end
	if duration.GetTime then
		local value = duration:GetTime()
		if issecretvalue and issecretvalue(value) then return nil end
		if type(value) == "number" then return normalizeDurationMilliseconds(value) end
	end
	return nil
end

H.getDurationMilliseconds = durationToMilliseconds

function H.getEmpoweredChannelDurationMilliseconds(unit)
	if not unit or not UnitEmpoweredChannelDuration then return nil end
	local duration = UnitEmpoweredChannelDuration(unit, true)
	return durationToMilliseconds(duration)
end

function H.getEmpowerHoldMilliseconds(unit)
	if not unit or not GetUnitEmpowerHoldAtMaxTime then return nil end
	local hold = GetUnitEmpowerHoldAtMaxTime(unit)
	return normalizeDurationMilliseconds(hold)
end

local function normalizeStagePercents(values, numStages)
	if type(values) ~= "table" then return nil end
	local cleaned = {}
	local scale = 1
	for i = 1, #values do
		local val = values[i]
		if type(val) == "number" and (not issecretvalue or not issecretvalue(val)) then
			if val > 1 then scale = 100 end
		end
	end
	local last = -1
	for i = 1, #values do
		local val = values[i]
		if type(val) == "number" and (not issecretvalue or not issecretvalue(val)) then
			if scale == 100 then val = val / 100 end
			if val < 0 then
				val = 0
			elseif val > 1 then
				val = 1
			end
			if val > last then
				cleaned[#cleaned + 1] = val
				last = val
			end
		end
		if numStages and #cleaned >= numStages then break end
	end
	if #cleaned == 0 then return nil end
	return cleaned
end

local function buildStagePercentsFromPercentages(values, numStages)
	if type(values) ~= "table" then return nil end
	local cleaned = {}
	local scale = 1
	local hasSecret = false
	for i = 1, #values do
		local val = values[i]
		if type(val) == "number" then
			if issecretvalue and issecretvalue(val) then
				hasSecret = true
			elseif val > 1 then
				scale = 100
			end
		end
	end
	if hasSecret then return nil end
	for i = 1, #values do
		local val = values[i]
		if type(val) == "number" then
			if scale == 100 then val = val / 100 end
			if val < 0 then
				val = 0
			elseif val > 1 then
				val = 1
			end
			cleaned[#cleaned + 1] = val
		end
	end
	if #cleaned == 0 then return nil end
	if numStages and #cleaned > numStages then
		while #cleaned > numStages do
			table.remove(cleaned)
		end
	end
	if numStages and #cleaned < numStages then return nil end
	if #cleaned == 0 then return nil end
	local sum = 0
	for i = 1, #cleaned do
		sum = sum + cleaned[i]
	end
	local assumeCumulative = #cleaned > 1 and sum > 1.02
	if assumeCumulative then return normalizeStagePercents(cleaned, numStages) end
	local cumulative = {}
	local running = 0
	for i = 1, #cleaned do
		running = running + cleaned[i]
		cumulative[i] = running
	end
	return normalizeStagePercents(cumulative, numStages)
end

local function buildEmpowerStagePercents(unit, numStages)
	if not numStages or numStages <= 0 then return nil end
	if UnitEmpoweredStagePercentages then
		local percents = normalizeStageValues(UnitEmpoweredStagePercentages(unit, true))
		percents = buildStagePercentsFromPercentages(percents, numStages)
		if percents then return percents end
	end
	local durations
	if UnitEmpoweredStageDurations then
		durations = normalizeStageValues(UnitEmpoweredStageDurations(unit))
	elseif GetUnitEmpowerStageDuration then
		durations = {}
		for i = 1, numStages do
			durations[i] = GetUnitEmpowerStageDuration(unit, i - 1)
		end
	end
	if type(durations) ~= "table" or #durations < numStages then return nil end
	local hold = GetUnitEmpowerHoldAtMaxTime and GetUnitEmpowerHoldAtMaxTime(unit)
	if hold ~= nil then
		hold = durationToMilliseconds(hold)
		if hold == nil then return nil end
	end
	local total = hold or 0
	local percents = {}
	local sum = 0
	for i = 1, numStages do
		local ms = durationToMilliseconds(durations[i])
		if not ms then return nil end
		sum = sum + ms
		total = total + ms
		percents[i] = sum
	end
	if not total or total <= 0 then return nil end
	for i = 1, numStages do
		percents[i] = percents[i] / total
	end
	return normalizeStagePercents(percents, numStages)
end

local function ensureEmpowerState(st)
	if not st or not st.castBar then return nil end
	if not st.castEmpower then st.castEmpower = { pips = {}, tiers = {} } end
	local emp = st.castEmpower
	if not emp.container then
		emp.container = CreateFrame("Frame", nil, st.castBar)
		emp.container:SetAllPoints(st.castBar)
		emp.container:EnableMouse(false)
	end
	if emp.container:GetParent() ~= st.castBar then emp.container:SetParent(st.castBar) end
	emp.container:SetFrameStrata(st.castBar:GetFrameStrata())
	local baseLevel = st.castBar:GetFrameLevel() or 0
	local layerOffset = H.shouldUseDefaultCastArt(st) and EMPOWER_PIP_LAYER_DEFAULT or EMPOWER_PIP_LAYER_CUSTOM
	emp.container:SetFrameLevel(baseLevel + layerOffset)
	return emp
end

local function addAlphaAnim(group, target, fromAlpha, toAlpha, duration, order, startDelay, smoothing)
	local anim = group:CreateAnimation("Alpha")
	anim:SetTarget(target)
	anim:SetFromAlpha(fromAlpha or 0)
	anim:SetToAlpha(toAlpha or 0)
	anim:SetDuration(duration or 0)
	anim:SetOrder(order or 1)
	if startDelay and startDelay > 0 then anim:SetStartDelay(startDelay) end
	if smoothing then anim:SetSmoothing(smoothing) end
	return anim
end

local function addTranslationAnim(group, target, offsetX, offsetY, duration, order, smoothing)
	local anim = group:CreateAnimation("Translation")
	anim:SetTarget(target)
	anim:SetOffset(offsetX or 0, offsetY or 0)
	anim:SetDuration(duration or 0)
	anim:SetOrder(order or 1)
	if smoothing then anim:SetSmoothing(smoothing) end
	return anim
end

local function addRotationAnim(group, target, degrees, duration, order, smoothing)
	local anim = group:CreateAnimation("Rotation")
	anim:SetTarget(target)
	anim:SetDegrees(degrees or 0)
	anim:SetDuration(duration or 0)
	anim:SetOrder(order or 1)
	if smoothing then anim:SetSmoothing(smoothing) end
	if anim.SetOrigin then anim:SetOrigin("CENTER", 0, 0) end
	return anim
end

local function ensureEmpowerPip(emp, index)
	local pip = emp.pips[index]
	if pip then return pip end
	pip = CreateFrame("Frame", nil, emp.container)
	pip:SetSize(7, 10)
	pip.BasePip = pip:CreateTexture(nil, "ARTWORK", nil, 2)
	if pip.BasePip.SetAtlas then pip.BasePip:SetAtlas("ui-castingbar-empower-pip", true) end
	pip.BasePip:SetPoint("CENTER")
	pip.PipGlow = pip:CreateTexture(nil, "OVERLAY", nil, 2)
	if pip.PipGlow.SetAtlas then pip.PipGlow:SetAtlas("cast-empowered-pipflare", true) end
	pip.PipGlow:SetAlpha(0)
	pip.PipGlow:SetPoint("CENTER")
	if pip.PipGlow.SetScale then pip.PipGlow:SetScale(0.5) end

	pip.FlakesBottom = pip:CreateTexture(nil, "OVERLAY", nil, 2)
	if pip.FlakesBottom.SetAtlas then pip.FlakesBottom:SetAtlas("Cast_Empowered_FlakesS01", true) end
	if pip.FlakesBottom.SetScale then pip.FlakesBottom:SetScale(0.5) end
	pip.FlakesBottom:SetAlpha(0)
	pip.FlakesBottom:SetPoint("CENTER")

	pip.FlakesTop = pip:CreateTexture(nil, "OVERLAY", nil, 2)
	if pip.FlakesTop.SetAtlas then pip.FlakesTop:SetAtlas("Cast_Empowered_FlakesS02", true) end
	if pip.FlakesTop.SetScale then pip.FlakesTop:SetScale(0.5) end
	pip.FlakesTop:SetAlpha(0)
	pip.FlakesTop:SetPoint("CENTER")

	pip.FlakesTop02 = pip:CreateTexture(nil, "OVERLAY", nil, 2)
	if pip.FlakesTop02.SetAtlas then pip.FlakesTop02:SetAtlas("Cast_Empowered_FlakesS03", true) end
	if pip.FlakesTop02.SetScale then pip.FlakesTop02:SetScale(0.5) end
	pip.FlakesTop02:SetAlpha(0)
	pip.FlakesTop02:SetPoint("CENTER")

	pip.FlakesBottom02 = pip:CreateTexture(nil, "OVERLAY", nil, 2)
	if pip.FlakesBottom02.SetAtlas then pip.FlakesBottom02:SetAtlas("Cast_Empowered_FlakesS03", true) end
	if pip.FlakesBottom02.SetScale then pip.FlakesBottom02:SetScale(0.5) end
	pip.FlakesBottom02:SetAlpha(0)
	pip.FlakesBottom02:SetPoint("CENTER")

	pip.StageAnim = pip:CreateAnimationGroup()
	pip.StageAnim:SetLooping("NONE")
	if pip.StageAnim.SetToFinalAlpha then pip.StageAnim:SetToFinalAlpha(true) end

	addAlphaAnim(pip.StageAnim, pip.PipGlow, 0, 0, 0, 1, nil, "NONE")
	addAlphaAnim(pip.StageAnim, pip.PipGlow, 0.1, 1, 0.1, 1, 0, "NONE")
	addAlphaAnim(pip.StageAnim, pip.PipGlow, 1, 0, 0.25, 1, 0.1, "OUT")

	addTranslationAnim(pip.StageAnim, pip.FlakesBottom, 0, -30, 0.3, 1, "OUT")
	addRotationAnim(pip.StageAnim, pip.FlakesBottom, 90, 0.3, 1, "OUT")
	addAlphaAnim(pip.StageAnim, pip.FlakesBottom, 0.1, 1, 0.1, 1, 0, "NONE")
	addAlphaAnim(pip.StageAnim, pip.FlakesBottom, 1, 0, 0.25, 1, 0.1, "NONE")

	addTranslationAnim(pip.StageAnim, pip.FlakesTop, 0, 30, 0.3, 1, "OUT")
	addRotationAnim(pip.StageAnim, pip.FlakesTop, -90, 0.3, 1, "OUT")
	addAlphaAnim(pip.StageAnim, pip.FlakesTop, 0.1, 1, 0.1, 1, 0, "NONE")
	addAlphaAnim(pip.StageAnim, pip.FlakesTop, 1, 0, 0.25, 1, 0.1, "NONE")

	addTranslationAnim(pip.StageAnim, pip.FlakesTop02, 0, 35, 0.3, 1, "IN")
	addRotationAnim(pip.StageAnim, pip.FlakesTop02, 60, 0.3, 1, "OUT")
	addAlphaAnim(pip.StageAnim, pip.FlakesTop02, 0.1, 1, 0.1, 1, 0, "NONE")
	addAlphaAnim(pip.StageAnim, pip.FlakesTop02, 1, 0, 0.25, 1, 0.1, "NONE")

	addTranslationAnim(pip.StageAnim, pip.FlakesBottom02, 0, -35, 0.3, 1, "IN")
	addRotationAnim(pip.StageAnim, pip.FlakesBottom02, -60, 0.3, 1, "OUT")
	addAlphaAnim(pip.StageAnim, pip.FlakesBottom02, 0.1, 1, 0.1, 1, 0, "NONE")
	addAlphaAnim(pip.StageAnim, pip.FlakesBottom02, 1, 0, 0.25, 1, 0.1, "NONE")

	emp.pips[index] = pip
	return pip
end

local function ensureEmpowerTier(emp, index)
	local tier = emp.tiers[index]
	if tier then return tier end
	tier = CreateFrame("Frame", nil, emp.container)
	tier.Normal = tier:CreateTexture(nil, "BACKGROUND", nil, 4)
	tier.Disabled = tier:CreateTexture(nil, "BACKGROUND", nil, 4)
	tier.Glow = tier:CreateTexture(nil, "BACKGROUND", nil, 5)
	tier.Normal:SetAllPoints(tier)
	tier.Disabled:SetAllPoints(tier)
	tier.Glow:SetAllPoints(tier)
	if tier.Glow.SetBlendMode then tier.Glow:SetBlendMode("ADD") end
	tier.Glow:SetAlpha(0)
	tier.GlowAnim = tier.Glow:CreateAnimationGroup()
	local fadeIn = tier.GlowAnim:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(0.1)
	fadeIn:SetOrder(1)
	local fadeOut = tier.GlowAnim:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetDuration(0.5)
	fadeOut:SetOrder(2)
	emp.tiers[index] = tier
	return tier
end

function H.clearEmpowerStages(st)
	local emp = st and st.castEmpower
	if not emp then return end
	emp.stagePercents = nil
	emp.stageCount = 0
	emp.currentStage = 0
	emp.layoutToken = (emp.layoutToken or 0) + 1
	if emp.container then emp.container:Hide() end
	for _, pip in pairs(emp.pips) do
		if pip.StageAnim then pip.StageAnim:Stop() end
		if pip.PipGlow then pip.PipGlow:SetAlpha(0) end
		if pip.FlakesBottom then pip.FlakesBottom:SetAlpha(0) end
		if pip.FlakesTop then pip.FlakesTop:SetAlpha(0) end
		if pip.FlakesTop02 then pip.FlakesTop02:SetAlpha(0) end
		if pip.FlakesBottom02 then pip.FlakesBottom02:SetAlpha(0) end
		pip:Hide()
	end
	for _, tier in pairs(emp.tiers) do
		if tier.GlowAnim then tier.GlowAnim:Stop() end
		tier:Hide()
	end
end

function H.layoutEmpowerStages(st)
	local emp = st and st.castEmpower
	if not st or not st.castBar or not emp or not emp.stagePercents then return end
	local baseLevel = st.castBar:GetFrameLevel() or 0
	local layerOffset = H.shouldUseDefaultCastArt(st) and EMPOWER_PIP_LAYER_DEFAULT or EMPOWER_PIP_LAYER_CUSTOM
	if emp.container then emp.container:SetFrameLevel(baseLevel + layerOffset) end
	local barLeft = st.castBar:GetLeft()
	local barRight = st.castBar:GetRight()
	if not barLeft or not barRight then
		if After then
			emp.layoutToken = (emp.layoutToken or 0) + 1
			local token = emp.layoutToken
			After(0, function()
				local st2 = st
				local emp2 = st2 and st2.castEmpower
				if emp2 and emp2.layoutToken == token then H.layoutEmpowerStages(st2) end
			end)
		end
		return
	end
	local barWidth = barRight - barLeft
	if not barWidth or barWidth <= 0 then return end
	local count = emp.stageCount or #emp.stagePercents
	if count <= 0 then return end
	local showTiers = H.shouldUseDefaultCastArt(st)
	local container = emp.container or ensureEmpowerState(st).container
	if container then container:Show() end
	local barHeight = st.castBar:GetHeight() or 0

	for i = 1, count do
		local percent = emp.stagePercents[i]
		local pip = ensureEmpowerPip(emp, i)
		pip:ClearAllPoints()
		local offset = barWidth * percent
		if showTiers then
			pip:SetSize(7, 10)
			pip:SetPoint("TOP", st.castBar, "TOPLEFT", offset, -1)
			pip:SetPoint("BOTTOM", st.castBar, "BOTTOMLEFT", offset, 1)
			if pip.BasePip then
				if pip.BasePip.SetAtlas then pip.BasePip:SetAtlas("ui-castingbar-empower-pip", true) end
				if pip.BasePip.SetDrawLayer then pip.BasePip:SetDrawLayer("ARTWORK", 2) end
				if pip.BasePip.SetVertexColor then pip.BasePip:SetVertexColor(1, 1, 1, 1) end
				pip.BasePip:ClearAllPoints()
				pip.BasePip:SetPoint("CENTER")
			end
			setPipFxLayer(pip, "OVERLAY", 2)
		else
			local lineWidth, lineHeight = getCustomPipDimensions(barHeight)
			pip:SetHeight(lineHeight)
			pip:SetWidth(lineWidth)
			pip:SetPoint("TOP", st.castBar, "TOPLEFT", offset, 0)
			pip:SetPoint("BOTTOM", st.castBar, "BOTTOMLEFT", offset, 0)
			if pip.BasePip then
				if pip.BasePip.SetDrawLayer then pip.BasePip:SetDrawLayer("OVERLAY", EMPOWER_CUSTOM_PIP_LINE_SUBLEVEL) end
				pip.BasePip:ClearAllPoints()
				pip.BasePip:SetAllPoints(pip)
				if pip.BasePip.SetColorTexture then
					pip.BasePip:SetColorTexture(1, 1, 1, EMPOWER_CUSTOM_PIP_ALPHA)
				else
					pip.BasePip:SetTexture("Interface\\Buttons\\WHITE8x8")
					if pip.BasePip.SetVertexColor then pip.BasePip:SetVertexColor(1, 1, 1, EMPOWER_CUSTOM_PIP_ALPHA) end
				end
			end
			setPipFxLayer(pip, "OVERLAY", EMPOWER_CUSTOM_PIP_FX_SUBLEVEL)
		end
		if pip.BasePip then pip.BasePip:Show() end
		pip:Show()
	end
	for i = count + 1, #emp.pips do
		emp.pips[i]:Hide()
	end

	if showTiers then
		for i = 1, count do
			local tier = ensureEmpowerTier(emp, i)
			tier:ClearAllPoints()
			local leftStagePip = emp.pips[i]
			local rightStagePip = emp.pips[i + 1]
			if leftStagePip then tier:SetPoint("TOPLEFT", leftStagePip, "TOP", 0, 0) end
			if rightStagePip then
				tier:SetPoint("BOTTOMRIGHT", rightStagePip, "BOTTOM", 0, 0)
			else
				tier:SetPoint("BOTTOMRIGHT", st.castBar, "BOTTOMRIGHT", 0, 1)
			end

			local tierLeft = tier:GetLeft()
			local tierRight = tier:GetRight()
			if tierLeft and tierRight then
				local texLeft = (tierLeft - barLeft) / barWidth
				local texRight = 1.0 - ((barRight - tierRight) / barWidth)
				tier.Normal:SetTexCoord(texLeft, texRight, 0, 1)
				tier.Disabled:SetTexCoord(texLeft, texRight, 0, 1)
				tier.Glow:SetTexCoord(texLeft, texRight, 0, 1)
			end

			if tier.Normal.SetAtlas then tier.Normal:SetAtlas(("ui-castingbar-tier%d-empower"):format(i), true) end
			if tier.Disabled.SetAtlas then tier.Disabled:SetAtlas(("ui-castingbar-disabled-tier%d-empower"):format(i), true) end
			if tier.Glow.SetAtlas then tier.Glow:SetAtlas(("ui-castingbar-glow-tier%d-empower"):format(i), true) end

			tier.Normal:SetShown(false)
			tier.Disabled:SetShown(true)
			tier.Glow:SetAlpha(0)
			tier:Show()
		end
		for i = count + 1, #emp.tiers do
			emp.tiers[i]:Hide()
		end
	else
		for _, tier in pairs(emp.tiers) do
			tier:Hide()
		end
	end
end

function H.updateEmpowerStageFromProgress(st, progress)
	local emp = st and st.castEmpower
	if not emp or not emp.stagePercents or not emp.stageCount then return end
	if issecretvalue and issecretvalue(progress) then return end
	local maxStage = 0
	for i = 1, emp.stageCount do
		local pct = emp.stagePercents[i]
		if type(pct) == "number" and progress >= pct then
			maxStage = i
		else
			break
		end
	end
	if maxStage <= emp.currentStage then return end
	local showTiers = H.shouldUseDefaultCastArt(st)
	for i = emp.currentStage + 1, maxStage do
		local pip = emp.pips[i]
		if pip and pip.StageAnim then
			pip.StageAnim:Stop()
			pip.StageAnim:Play()
		elseif pip and pip.PipGlowAnim then
			pip.PipGlowAnim:Stop()
			pip.PipGlowAnim:Play()
		end
		local tier = emp.tiers[i]
		if showTiers and tier then
			tier.Normal:SetShown(true)
			tier.Disabled:SetShown(false)
			if tier.GlowAnim then
				tier.GlowAnim:Stop()
				tier.GlowAnim:Play()
			end
		end
	end
	emp.currentStage = maxStage
end

function H.updateEmpowerStageFromBar(st)
	if not st or not st.castBar then return end
	local emp = st.castEmpower
	if not emp or not emp.stagePercents then return end
	local _, maxVal = st.castBar:GetMinMaxValues()
	local value = st.castBar:GetValue()
	if not maxVal or maxVal == 0 or value == nil then return end
	if issecretvalue and (issecretvalue(value) or issecretvalue(maxVal)) then return end
	H.updateEmpowerStageFromProgress(st, value / maxVal)
end

function H.setupEmpowerStages(st, unit, numStages)
	H.clearEmpowerStages(st)
	if not st or not unit or not numStages or numStages <= 0 then return end
	local percents = buildEmpowerStagePercents(unit, numStages)
	if not percents then return end
	local emp = ensureEmpowerState(st)
	if not emp then return end
	emp.stagePercents = percents
	emp.stageCount = #percents
	emp.currentStage = 0
	H.layoutEmpowerStages(st)
end

local WrapString = _G.C_StringUtil and _G.C_StringUtil.WrapString
local TruncateWhenZero = _G.C_StringUtil and _G.C_StringUtil.TruncateWhenZero

function H.formatCastName(nameText, castTarget, showTarget)
	if not showTarget or type(castTarget) == "nil" then return nameText end
	if WrapString then return WrapString(castTarget, nameText .. " --> ") or nameText end
	if not castTarget or castTarget == "" then return nameText end
	return nameText .. " --> " .. castTarget
end

function H.resolveTextDelimiter(delimiter)
	if delimiter == nil or delimiter == "" then delimiter = " " end
	delimiter = tostring(delimiter)
	if delimiter:find("%s") then return delimiter end
	return " " .. delimiter .. " "
end

function H.resolveTextDelimiters(primary, secondary, tertiary)
	local primaryResolved = H.resolveTextDelimiter(primary)
	if secondary == nil or secondary == "" then secondary = primary end
	local secondaryResolved = H.resolveTextDelimiter(secondary)
	if tertiary == nil or tertiary == "" then tertiary = secondary end
	local tertiaryResolved = H.resolveTextDelimiter(tertiary)
	return primaryResolved, secondaryResolved, tertiaryResolved
end

local function join2(a, b, sep) return a .. sep .. b end

local function join3(a, b, c, sep1, sep2) return a .. sep1 .. b .. sep2 .. c end

local function join4(a, b, c, d, sep1, sep2, sep3) return a .. sep1 .. b .. sep2 .. c .. sep3 .. d end

local function formatPercentModeText(mode, curText, maxText, percentText, levelText, joinPrimary, joinSecondary, joinTertiary)
	if not percentText then return "" end
	if mode == "PERCENT" then return percentText end
	if mode == "CURPERCENT" or mode == "CURPERCENTDASH" then return join2(curText, percentText, joinPrimary) end
	if mode == "CURMAXPERCENT" then return join3(curText, maxText, percentText, joinPrimary, joinSecondary) end
	if mode == "MAXPERCENT" then return join2(maxText, percentText, joinPrimary) end
	if mode == "PERCENTMAX" then return join2(percentText, maxText, joinPrimary) end
	if mode == "PERCENTCUR" then return join2(percentText, curText, joinPrimary) end
	if mode == "PERCENTCURMAX" then return join3(percentText, curText, maxText, joinPrimary, joinSecondary) end
	if mode == "LEVELPERCENT" then return join2(levelText, percentText, joinPrimary) end
	if mode == "LEVELPERCENTMAX" then return join3(levelText, percentText, maxText, joinPrimary, joinSecondary) end
	if mode == "LEVELPERCENTCUR" then return join3(levelText, percentText, curText, joinPrimary, joinSecondary) end
	if mode == "LEVELPERCENTCURMAX" then return join4(levelText, percentText, curText, maxText, joinPrimary, joinSecondary, joinTertiary) end
	return ""
end

function H.shortValue(val)
	if val == nil then return "" end
	return AbbreviateNumbers(val)
end

function H.textModeUsesLevel(mode) return type(mode) == "string" and mode:find("LEVEL", 1, true) ~= nil end
function H.textModeUsesDeficit(mode) return mode == "DEFICIT" end

function H.getUnitLevelText(unit, levelOverride, hideClassificationText)
	if not unit then return "??" end
	local rawLevel = tonumber(levelOverride) or UnitLevel(unit) or 0
	local levelText = rawLevel > 0 and tostring(rawLevel) or "??"
	local classification = UnitClassification and UnitClassification(unit)
	if classification == "worldboss" then
		levelText = "??"
	elseif classification == "elite" then
		if not hideClassificationText then levelText = levelText .. "+" end
	elseif classification == "rareelite" then
		if not hideClassificationText then levelText = levelText .. " R+" end
	elseif classification == "rare" then
		if not hideClassificationText then levelText = levelText .. " R" end
	elseif classification == "trivial" or classification == "minus" then
		levelText = levelText .. "-"
	end
	return levelText
end

function H.formatText(mode, cur, maxv, useShort, percentValue, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText, missingValue, roundPercent, delimitersResolved)
	if mode == "NONE" then return "" end
	local joinPrimary, joinSecondary, joinTertiary
	if delimitersResolved then
		joinPrimary = delimiter
		joinSecondary = delimiter2
		joinTertiary = delimiter3
	else
		joinPrimary, joinSecondary, joinTertiary = H.resolveTextDelimiters(delimiter, delimiter2, delimiter3)
	end
	if joinPrimary == nil then joinPrimary = " " end
	if joinSecondary == nil then joinSecondary = joinPrimary end
	if joinTertiary == nil then joinTertiary = joinSecondary end
	local percentSuffix = hidePercentSymbol and "" or "%"
	if levelText == nil or levelText == "" then levelText = "??" end
	local isPercentMode = type(mode) == "string" and mode:find("PERCENT", 1, true) ~= nil
	if mode == "DEFICIT" then
		if issecretvalue and issecretvalue(missingValue) then
			local infix = useShort and H.shortValue(missingValue) or BreakUpLargeNumbers(missingValue)
			return "-" .. infix
		end
		if missingValue == nil then return "" end
		local missNum = tonumber(missingValue) or 0
		if missNum <= 0 then return "" end
		local infix = useShort == false and tostring(missNum) or (AbbreviateNumbers and AbbreviateNumbers(missNum) or H.shortValue(missNum))
		return "-" .. infix
	end
	if addon.variables and addon.variables.isMidnight and issecretvalue then
		if (cur and issecretvalue(cur)) or (maxv and issecretvalue(maxv)) then
			local scur = useShort and H.shortValue(cur) or BreakUpLargeNumbers(cur)
			local smax = useShort and H.shortValue(maxv) or BreakUpLargeNumbers(maxv)
			local percentText
			if percentValue ~= nil then
				if roundPercent then
					percentText = ("%s%s"):format(tostring(C_StringUtil.RoundToNearestString(percentValue)), percentSuffix)
				else
					percentText = ("%s%s"):format(tostring(AbbreviateLargeNumbers(percentValue)), percentSuffix)
				end
			end

			if mode == "CURRENT" then return tostring(scur) end
			if mode == "MAX" then return tostring(smax) end
			if mode == "CURMAX" then return join2(tostring(scur), tostring(smax), joinPrimary) end
			if isPercentMode then return formatPercentModeText(mode, tostring(scur), tostring(smax), percentText, levelText, joinPrimary, joinSecondary, joinTertiary) end
			return ""
		end
	end
	local percentText
	if isPercentMode then
		if percentValue ~= nil then
			percentText = ("%d%s"):format(floor(percentValue + 0.5), percentSuffix)
		elseif not maxv or maxv == 0 then
			percentText = "0" .. percentSuffix
		else
			percentText = ("%d%s"):format(floor((cur or 0) / maxv * 100 + 0.5), percentSuffix)
		end
	end
	if mode == "MAX" then
		local maxText = useShort == false and tostring(maxv or 0) or H.shortValue(maxv or 0)
		return maxText
	end
	if mode == "CURMAX" then
		local curText = useShort == false and tostring(cur or 0) or H.shortValue(cur or 0)
		local maxText = useShort == false and tostring(maxv or 0) or H.shortValue(maxv or 0)
		return join2(curText, maxText, joinPrimary)
	end
	if isPercentMode then
		local curText = useShort == false and tostring(cur or 0) or H.shortValue(cur or 0)
		local maxText = useShort == false and tostring(maxv or 0) or H.shortValue(maxv or 0)
		return formatPercentModeText(mode, curText, maxText, percentText, levelText, joinPrimary, joinSecondary, joinTertiary)
	end
	if useShort == false then return tostring(cur or 0) end
	return H.shortValue(cur or 0)
end

function H.getNameLimitWidth(fontPath, fontSize, fontOutline, maxChars)
	if not maxChars or maxChars <= 0 then return nil end
	local font = H.getFont(fontPath)
	local size = fontSize or 14
	local outline = normalizeFontOutline(fontOutline)
	local key = tostring(font) .. "|" .. tostring(size) .. "|" .. tostring(outline or "") .. "|" .. tostring(maxChars)
	if nameWidthCache[key] then return nameWidthCache[key] end
	if not nameWidthCache._measure and UIParent and UIParent.CreateFontString then
		nameWidthCache._measure = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		if nameWidthCache._measure then nameWidthCache._measure:Hide() end
	end
	local measure = nameWidthCache._measure
	if not measure then return nil end
	local ok = measure.SetFont and measure:SetFont(font, size, outline)
	if not ok then
		local fallback = H.getFont(nil)
		measure:SetFont(fallback, size, outline)
	end
	measure:SetText(string.rep("i", maxChars))
	local width = measure:GetStringWidth() or 0
	nameWidthCache[key] = width
	return width
end

function H.applyNameCharLimit(st, scfg, defStatus)
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
	local width = H.getNameLimitWidth(scfg and scfg.font, scfg and scfg.fontSize or 14, scfg and scfg.fontOutline or "OUTLINE", maxChars)
	if width and width > 0 then st.nameText:SetWidth(width) end
end

function H.truncateTextToWidth(fontPath, fontSize, fontOutline, text, maxWidth)
	if not text or text == "" or maxWidth <= 0 then return text or "" end
	if not nameWidthCache._measure and UIParent and UIParent.CreateFontString then
		nameWidthCache._measure = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		if nameWidthCache._measure then nameWidthCache._measure:Hide() end
	end
	local measure = nameWidthCache._measure
	if not measure then return text end
	local size = fontSize or 14
	local outline = fontOutline or "OUTLINE"
	local ok = measure.SetFont and measure:SetFont(H.getFont(fontPath), size, outline)
	if ok == false then measure:SetFont(H.getFont(nil), size, outline) end
	measure:SetText(text)
	if measure:GetStringWidth() <= maxWidth then return text end
	local length = utf8Len(text)
	local low, high = 1, length
	local best = ""
	while low <= high do
		local mid = math.floor((low + high) / 2)
		local candidate = utf8Sub(text, 1, mid)
		measure:SetText(candidate)
		if measure:GetStringWidth() <= maxWidth then
			best = candidate
			low = mid + 1
		else
			high = mid - 1
		end
	end
	return best
end

function H.getTextDelimiter(cfg, def)
	local defaultDelim = (def and def.textDelimiter) or " "
	local delimiter = cfg and cfg.textDelimiter
	if delimiter == nil or delimiter == "" then delimiter = defaultDelim end
	return delimiter
end

function H.getTextDelimiterSecondary(cfg, def, primary)
	local delimiter = cfg and cfg.textDelimiterSecondary
	if delimiter == nil or delimiter == "" then delimiter = def and def.textDelimiterSecondary end
	if delimiter == nil or delimiter == "" then delimiter = primary end
	return delimiter
end

function H.getTextDelimiterTertiary(cfg, def, primary, secondary)
	local delimiter = cfg and cfg.textDelimiterTertiary
	if delimiter == nil or delimiter == "" then delimiter = def and def.textDelimiterTertiary end
	if delimiter == nil or delimiter == "" then delimiter = secondary or primary end
	return delimiter
end

local function resolvePvPAtlas(unit)
	if C_GameRules and C_GameRules.IsGameRuleActive and Enum and Enum.GameRule then
		if C_GameRules.IsGameRuleActive(Enum.GameRule.UnitFramePvPContextualDisabled) then return nil end
	end
	if UnitIsPVPFreeForAll and UnitIsPVPFreeForAll(unit) then return "UI-HUD-UnitFrame-Player-PVP-FFAIcon" end
	local factionGroup = UnitFactionGroup and UnitFactionGroup(unit)
	if factionGroup and factionGroup ~= "Neutral" and UnitIsPVP and UnitIsPVP(unit) then
		if UnitIsMercenary and UnitIsMercenary(unit) then
			if factionGroup == "Horde" then
				factionGroup = "Alliance"
			elseif factionGroup == "Alliance" then
				factionGroup = "Horde"
			end
		end
		if factionGroup == "Horde" then
			return "UI-HUD-UnitFrame-Player-PVP-HordeIcon"
		elseif factionGroup == "Alliance" then
			return "UI-HUD-UnitFrame-Player-PVP-AllianceIcon"
		end
	end
	return nil
end

local function resolveRoleAtlas(role)
	if not role or role == "NONE" then return nil end
	if GetIconForRole then return GetIconForRole(role, false) end
	if role == "TANK" then return "UI-LFG-RoleIcon-Tank" end
	if role == "HEALER" then return "UI-LFG-RoleIcon-Healer" end
	if role == "DAMAGER" then return "UI-LFG-RoleIcon-DPS" end
	return nil
end

local function resolveClassificationAtlas(classification)
	if classification == "elite" or classification == "worldboss" then
		return "nameplates-icon-elite-gold"
	elseif classification == "rare" then
		return "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star"
	elseif classification == "rareelite" then
		return "nameplates-icon-elite-silver"
	end
	return nil
end

function H.updatePvPIndicator(st, unit, cfg, def, skipDisabled)
	if unit ~= "player" and unit ~= "target" and unit ~= "focus" then return end
	if not st or not st.pvpIcon then return end
	def = def or {}
	local pcfg = (cfg and cfg.pvpIndicator) or (def and def.pvpIndicator) or {}
	local enabled = pcfg.enabled == true and not (cfg and cfg.enabled == false)
	if not enabled and skipDisabled then return end

	local offsetDef = def and def.pvpIndicator and def.pvpIndicator.offset or {}
	local sizeDef = def and def.pvpIndicator and def.pvpIndicator.size or 20
	local size = H.clamp(pcfg.size or sizeDef or 20, 10, 40)
	local ox = (pcfg.offset and pcfg.offset.x) or offsetDef.x or 0
	local oy = (pcfg.offset and pcfg.offset.y) or offsetDef.y or -2
	local centerOffset = (st and st._portraitCenterOffset) or 0
	st.pvpIcon:ClearAllPoints()
	st.pvpIcon:SetSize(size, size)
	st.pvpIcon:SetPoint("TOP", st.frame, "TOP", (ox or 0) + centerOffset, oy)

	if not enabled then
		st.pvpIcon:Hide()
		return
	end

	local inEditMode = addon.EditModeLib and addon.EditModeLib:IsInEditMode()
	local atlas = resolvePvPAtlas(unit)
	if not atlas and inEditMode then
		local sampleFaction = UnitFactionGroup and UnitFactionGroup("player")
		if sampleFaction == "Horde" then
			atlas = "UI-HUD-UnitFrame-Player-PVP-HordeIcon"
		else
			atlas = "UI-HUD-UnitFrame-Player-PVP-AllianceIcon"
		end
	end
	if atlas then
		st.pvpIcon:SetAtlas(atlas)
		st.pvpIcon:Show()
	else
		st.pvpIcon:Hide()
	end
end

function H.updateRoleIndicator(st, unit, cfg, def, skipDisabled)
	if unit ~= "player" and unit ~= "target" and unit ~= "focus" then return end
	if not st or not st.roleIcon then return end
	def = def or {}
	local rcfg = (cfg and cfg.roleIndicator) or (def and def.roleIndicator) or {}
	local enabled = rcfg.enabled == true and not (cfg and cfg.enabled == false)
	if not enabled and skipDisabled then return end

	local offsetDef = def and def.roleIndicator and def.roleIndicator.offset or {}
	local sizeDef = def and def.roleIndicator and def.roleIndicator.size or 18
	local size = H.clamp(rcfg.size or sizeDef or 18, 10, 40)
	local ox = (rcfg.offset and rcfg.offset.x) or offsetDef.x or 0
	local oy = (rcfg.offset and rcfg.offset.y) or offsetDef.y or -2
	local centerOffset = (st and st._portraitCenterOffset) or 0
	st.roleIcon:ClearAllPoints()
	st.roleIcon:SetSize(size, size)
	st.roleIcon:SetPoint("TOP", st.frame, "TOP", (ox or 0) + centerOffset, oy)

	if not enabled then
		st.roleIcon:Hide()
		return
	end

	local inEditMode = addon.EditModeLib and addon.EditModeLib:IsInEditMode()
	local inGroup = IsInGroup and IsInGroup() or false
	local role = inGroup and UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or nil
	if role == "NONE" then role = nil end
	if not role and inEditMode then role = "DAMAGER" end

	local atlas = resolveRoleAtlas(role)
	if atlas then
		st.roleIcon:SetAtlas(atlas)
		st.roleIcon:Show()
	else
		st.roleIcon:Hide()
	end
end

function H.updateLeaderIndicator(st, unit, cfg, def, skipDisabled)
	if unit ~= "player" and unit ~= "target" and unit ~= "focus" then return end
	if not st or not st.leaderIcon then return end
	def = def or {}
	local lcfg = (cfg and cfg.leaderIcon) or (def and def.leaderIcon) or {}
	local enabled = lcfg.enabled == true and not (cfg and cfg.enabled == false)
	if not enabled and skipDisabled then return end

	local offsetDef = def and def.leaderIcon and def.leaderIcon.offset or {}
	local sizeDef = def and def.leaderIcon and def.leaderIcon.size or 12
	local size = H.clamp(lcfg.size or sizeDef or 12, 8, 40)
	local ox = (lcfg.offset and lcfg.offset.x) or offsetDef.x or 0
	local oy = (lcfg.offset and lcfg.offset.y) or offsetDef.y or 0
	local anchor = st.health or st.frame
	st.leaderIcon:ClearAllPoints()
	if anchor then
		st.leaderIcon:SetPoint("TOPLEFT", anchor, "TOPLEFT", ox, oy)
	else
		st.leaderIcon:SetPoint("TOPLEFT", st.frame, "TOPLEFT", ox, oy)
	end
	st.leaderIcon:SetSize(size, size)

	if not enabled then
		st.leaderIcon:Hide()
		return
	end

	local inEditMode = addon.EditModeLib and addon.EditModeLib:IsInEditMode()
	local showLeader = UnitIsGroupLeader and UnitIsGroupLeader(unit)
	if not showLeader and inEditMode then showLeader = true end
	if showLeader then
		st.leaderIcon:SetAtlas("UI-HUD-UnitFrame-Player-Group-LeaderIcon", false)
		st.leaderIcon:Show()
	else
		st.leaderIcon:Hide()
	end
end

function H.updateClassificationIndicator(st, unit, cfg, def, skipDisabled)
	if unit == "player" then
		if st and st.classificationIcon then st.classificationIcon:Hide() end
		return
	end
	if not st or not st.classificationIcon then return end
	def = def or {}
	local scfg = (cfg and cfg.status) or {}
	local defStatus = def.status or {}
	local icfg = scfg.classificationIcon or defStatus.classificationIcon or {}
	local enabled = icfg.enabled == true and not (cfg and cfg.enabled == false)
	if not enabled and skipDisabled then return end

	local sizeDef = defStatus.classificationIcon and defStatus.classificationIcon.size or 16
	local offsetDef = (defStatus.classificationIcon and defStatus.classificationIcon.offset) or { x = -4, y = 0 }
	local size = H.clamp(icfg.size or sizeDef or 16, 8, 40)
	local ox = (icfg.offset and icfg.offset.x) or offsetDef.x or 0
	local oy = (icfg.offset and icfg.offset.y) or offsetDef.y or 0

	st.classificationIcon:ClearAllPoints()
	local anchorFrame = st.statusTextLayer or st.status
	if anchorFrame then st.classificationIcon:SetPoint("RIGHT", anchorFrame, "RIGHT", ox or 0, oy) end
	st.classificationIcon:SetSize(size, size)

	if not enabled then
		st.classificationIcon:Hide()
		return
	end

	local classification = UnitClassification and UnitClassification(unit)
	local atlas = resolveClassificationAtlas(classification)
	local inEditMode = addon.EditModeLib and addon.EditModeLib:IsInEditMode()
	if not atlas and inEditMode then atlas = resolveClassificationAtlas("rareelite") end
	if atlas then
		st.classificationIcon:SetAtlas(atlas)
		st.classificationIcon:Show()
	else
		st.classificationIcon:Hide()
	end
end

local function getCombatFeedbackConfig(cfg, def)
	local c = (cfg and cfg.combatFeedback) or {}
	local d = (def and def.combatFeedback) or {}
	return c, d
end

local function resolveCombatFeedbackParent(st, location)
	if not st then return nil end
	if location == "HEALTH" then return st.healthTextLayer or st.health or st.barGroup or st.frame end
	if location == "POWER" then return st.powerTextLayer or st.power or st.barGroup or st.frame end
	if location == "STATUS" then return st.statusTextLayer or st.status or st.frame end
	return st.frame
end

local function getCombatFeedbackLayer(st)
	if not st or not st.frame then return nil end
	if not st.combatFeedbackLayer then
		st.combatFeedbackLayer = CreateFrame("Frame", nil, st.frame)
		st.combatFeedbackLayer:SetAllPoints(st.frame)
	end
	local layer = st.combatFeedbackLayer
	if layer.SetFrameStrata and st.frame.GetFrameStrata then layer:SetFrameStrata(st.frame:GetFrameStrata()) end
	local maxLevel = 0
	local function consider(frame)
		if not frame or not frame.GetFrameLevel then return end
		local level = frame:GetFrameLevel() or 0
		if level > maxLevel then maxLevel = level end
	end
	consider(st.healthTextLayer)
	consider(st.powerTextLayer)
	consider(st.statusTextLayer)
	consider(st.health and st.health.absorbClip)
	consider(st.health and st.health._healthFillClip)
	consider(st.health)
	consider(st.status)
	consider(st.power)
	if layer.SetFrameLevel then layer:SetFrameLevel(maxLevel + 5) end
	return layer
end

function H.syncCombatFeedbackLayer(st)
	local layer = getCombatFeedbackLayer(st)
	if not layer then return end
	if st.combatFeedback then
		if st.combatFeedback.GetParent and st.combatFeedback:GetParent() ~= layer then st.combatFeedback:SetParent(layer) end
		if st.combatFeedback.SetFrameStrata and layer.GetFrameStrata then st.combatFeedback:SetFrameStrata(layer:GetFrameStrata()) end
		if st.combatFeedback.SetFrameLevel and layer.GetFrameLevel then st.combatFeedback:SetFrameLevel((layer:GetFrameLevel() or 0) + 1) end
	end
	if st.combatFeedbackText and st.combatFeedbackText.GetParent and st.combatFeedbackText:GetParent() ~= layer then st.combatFeedbackText:SetParent(layer) end
end

local function resolveCombatFeedbackTextParent(st, location)
	if not st then return nil end
	if location == "HEALTH" then return st.healthTextLayer or st.health or st.barGroup or st.frame end
	if location == "POWER" then return st.powerTextLayer or st.power or st.barGroup or st.frame end
	if location == "STATUS" then return st.statusTextLayer or st.status or st.frame end
	return st.frame
end

local function combatFeedbackHasEvents(events)
	if type(events) ~= "table" then return true end
	for _, enabled in pairs(events) do
		if enabled then return true end
	end
	return false
end

local function combatFeedbackJustify(anchor)
	if type(anchor) ~= "string" then return "CENTER" end
	local upper = anchor:upper()
	if upper:find("LEFT", 1, true) then return "LEFT" end
	if upper:find("RIGHT", 1, true) then return "RIGHT" end
	return "CENTER"
end

function H.combatFeedbackIsEnabled(cfg, def)
	if cfg and cfg.enabled == false then return false end
	if not CombatFeedback_OnCombatEvent then return false end
	local c, d = getCombatFeedbackConfig(cfg, def)
	local enabled = c.enabled
	if enabled == nil then enabled = d.enabled end
	if enabled ~= true then return false end
	local events = c.events
	if events == nil then events = d.events end
	return combatFeedbackHasEvents(events)
end

function H.combatFeedbackShouldShowEvent(cfg, def, event)
	if not event then return false end
	local c, d = getCombatFeedbackConfig(cfg, def)
	local events = c.events
	if events == nil then events = d.events end
	if type(events) ~= "table" then return true end
	local val = events[event]
	if val == nil and type(d.events) == "table" then val = d.events[event] end
	if val == nil then return true end
	return val == true
end

local function getCombatFeedbackSampleConfig(cfg, def)
	local c, d = getCombatFeedbackConfig(cfg, def)
	local sampleEnabled = c.sample
	if sampleEnabled == nil then sampleEnabled = d.sample end
	sampleEnabled = sampleEnabled == true
	local sampleEvent = c.sampleEvent or d.sampleEvent or "WOUND"
	local sampleAmount = tonumber(c.sampleAmount or d.sampleAmount) or 12345
	if sampleAmount < 0 then sampleAmount = 0 end
	if sampleAmount == 0 then sampleAmount = 1 end
	return sampleEnabled, sampleEvent, sampleAmount
end

function H.ensureCombatFeedbackElements(st)
	if not st or not st.frame then return nil end
	if not st.combatFeedback then st.combatFeedback = CreateFrame("Frame", nil, st.frame) end
	if not st.combatFeedbackText then
		local parent = st.statusTextLayer or st.status or st.frame
		st.combatFeedbackText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		st.combatFeedbackText:Hide()
	end
	st.combatFeedback.feedbackText = st.combatFeedbackText
	return st.combatFeedback, st.combatFeedbackText
end

local function stopCombatFeedbackSample(st)
	if not st then return end
	local ticker = st._combatFeedbackSampleTicker
	if ticker and ticker.Cancel then ticker:Cancel() end
	st._combatFeedbackSampleTicker = nil
	if st._combatFeedbackSampleActive then
		st._combatFeedbackSampleActive = nil
		if st.combatFeedbackText then st.combatFeedbackText:Hide() end
	end
end

function H.applyCombatFeedbackStyle(st, cfg, def)
	if not st then return end
	local c, d = getCombatFeedbackConfig(cfg, def)
	local font = c.font or d.font
	local fontSize = tonumber(c.fontSize or d.fontSize) or 30
	if fontSize <= 0 then fontSize = 30 end
	local anchor = c.anchor or d.anchor or "CENTER"
	local location = c.location or d.location or "STATUS"
	local off = c.offset or d.offset or {}
	local ox = off.x or 0
	local oy = off.y or 0
	local key = tostring(font) .. "|" .. tostring(fontSize) .. "|" .. tostring(anchor) .. "|" .. tostring(location) .. "|" .. tostring(ox) .. "|" .. tostring(oy)
	if st._combatFeedbackStyleKey == key then return end
	st._combatFeedbackStyleKey = key

	local frame, text = H.ensureCombatFeedbackElements(st)
	if not frame or not text then return end
	H.applyFont(text, font, fontSize, nil)
	H.syncCombatFeedbackLayer(st)
	local textParent = getCombatFeedbackLayer(st) or resolveCombatFeedbackTextParent(st, location) or st.frame
	if text.GetParent and text:GetParent() ~= textParent then text:SetParent(textParent) end
	if text.SetDrawLayer then text:SetDrawLayer("OVERLAY", 7) end
	text:ClearAllPoints()
	local parent = resolveCombatFeedbackParent(st, location) or st.frame
	text:SetPoint(anchor, parent, anchor, ox, oy)
	if text.SetJustifyH then text:SetJustifyH(combatFeedbackJustify(anchor)) end
	if text.SetWordWrap then text:SetWordWrap(false) end
	if text.SetMaxLines then text:SetMaxLines(1) end

	if CombatFeedback_Initialize then
		CombatFeedback_Initialize(frame, text, fontSize)
	else
		frame.feedbackText = text
		frame.feedbackFontHeight = fontSize
	end
end

function H.showCombatFeedbackSample(st, cfg, def)
	if not st or not CombatFeedback_OnCombatEvent then return end
	local enabled, sampleEvent, sampleAmount = getCombatFeedbackSampleConfig(cfg, def)
	if not enabled then return end
	local frame, text = H.ensureCombatFeedbackElements(st)
	if not frame or not text then return end
	H.applyCombatFeedbackStyle(st, cfg, def)
	if CombatFeedback_OnUpdate and frame.GetScript and frame:GetScript("OnUpdate") == nil then frame:SetScript("OnUpdate", CombatFeedback_OnUpdate) end
	CombatFeedback_OnCombatEvent(frame, sampleEvent, "", sampleAmount, 1)
	st._combatFeedbackSampleActive = true
end

function H.handleCombatFeedbackEvent(st, cfg, def, event, flags, amount, schoolMask)
	if not st or not CombatFeedback_OnCombatEvent then return end
	if not H.combatFeedbackIsEnabled(cfg, def) then return end
	if not H.combatFeedbackShouldShowEvent(cfg, def, event) then return end
	if issecretvalue and (issecretvalue(event) or issecretvalue(flags) or issecretvalue(amount) or issecretvalue(schoolMask)) then return end
	if GetTime then
		local now = GetTime()
		local last = st._combatFeedbackLastAt
		if last and (now - last) < COMBAT_FEEDBACK_THROTTLE then return end
		st._combatFeedbackLastAt = now
	end
	local frame, text = H.ensureCombatFeedbackElements(st)
	if not frame or not text then return end
	H.applyCombatFeedbackStyle(st, cfg, def)
	if CombatFeedback_OnUpdate and frame.GetScript and frame:GetScript("OnUpdate") == nil then frame:SetScript("OnUpdate", CombatFeedback_OnUpdate) end
	CombatFeedback_OnCombatEvent(frame, event, flags, amount, schoolMask)
end

function H.updateCombatFeedback(st, unit, cfg, def)
	if not st then return end
	st._combatFeedbackDef = def
	if not H.combatFeedbackIsEnabled(cfg, def) then
		if st._combatFeedbackEventFrame and st._combatFeedbackEventFrame.UnregisterEvent then st._combatFeedbackEventFrame:UnregisterEvent("UNIT_COMBAT") end
		if st.combatFeedback and st.combatFeedback.SetScript then st.combatFeedback:SetScript("OnUpdate", nil) end
		if st.combatFeedback then st.combatFeedback:Hide() end
		if st.combatFeedbackText then st.combatFeedbackText:Hide() end
		stopCombatFeedbackSample(st)
		return
	end
	if not unit then return end
	H.applyCombatFeedbackStyle(st, cfg, def)
	local frame = st.combatFeedback
	if frame then frame:Show() end
	if frame and CombatFeedback_OnUpdate and frame.GetScript and frame:GetScript("OnUpdate") == nil then frame:SetScript("OnUpdate", CombatFeedback_OnUpdate) end
	local evt = st._combatFeedbackEventFrame
	if not evt then
		evt = CreateFrame("Frame")
		st._combatFeedbackEventFrame = evt
		evt:SetScript("OnEvent", function(_, _, unitTarget, eventName, flagText, amount, schoolMask)
			if unitTarget ~= unit then return end
			local activeCfg = st.cfg or cfg
			local activeDef = st._combatFeedbackDef or def
			H.handleCombatFeedbackEvent(st, activeCfg, activeDef, eventName, flagText, amount, schoolMask)
		end)
	end
	if evt.UnregisterEvent then evt:UnregisterEvent("UNIT_COMBAT") end
	if evt.RegisterUnitEvent then
		evt:RegisterUnitEvent("UNIT_COMBAT", unit)
	elseif evt.RegisterEvent then
		evt:RegisterEvent("UNIT_COMBAT")
	end

	stopCombatFeedbackSample(st)
	local sampleEnabled = getCombatFeedbackSampleConfig(cfg, def)
	local inEditMode = addon.EditModeLib and addon.EditModeLib.IsInEditMode and addon.EditModeLib:IsInEditMode()
	if sampleEnabled and inEditMode then
		H.showCombatFeedbackSample(st, cfg, def)
		if NewTicker then
			st._combatFeedbackSampleTicker = NewTicker(1.2, function()
				local activeCfg = st.cfg or cfg
				local activeDef = st._combatFeedbackDef or def
				H.showCombatFeedbackSample(st, activeCfg, activeDef)
			end)
		end
	else
		stopCombatFeedbackSample(st)
	end
end

function H.stopCombatFeedbackSample(st) stopCombatFeedbackSample(st) end

function H.disableCombatFeedbackAll(states)
	if type(states) ~= "table" then return end
	for _, st in pairs(states) do
		if st and st._combatFeedbackEventFrame and st._combatFeedbackEventFrame.UnregisterEvent then st._combatFeedbackEventFrame:UnregisterEvent("UNIT_COMBAT") end
		if st and st.combatFeedback and st.combatFeedback.SetScript then st.combatFeedback:SetScript("OnUpdate", nil) end
		if st and st.combatFeedback then st.combatFeedback:Hide() end
		if st and st.combatFeedbackText then st.combatFeedbackText:Hide() end
		stopCombatFeedbackSample(st)
	end
end

function H.getPowerColor(powerEnum, powerToken)
	if powerToken == nil and type(powerEnum) == "string" then
		powerToken = powerEnum
		powerEnum = nil
	end
	if powerEnum == nil and powerToken == nil then
		powerEnum = EnumPowerType and EnumPowerType.MANA or nil
		powerToken = "MANA"
	end
	local overrides = addon.db and addon.db.ufPowerColorOverrides
	local override = getPowerOverrideEntry(overrides, powerEnum, powerToken)
	if override then
		if override.r then return override.r, override.g, override.b, override.a or 1 end
		if override[1] then return override[1], override[2], override[3], override[4] or 1 end
	end
	local c = getPowerColorEntry(powerEnum, powerToken)
	if c then
		if c.r then return c.r, c.g, c.b, c.a or 1 end
		if c[1] then return c[1], c[2], c[3], c[4] or 1 end
	end
	local manaColor = getPowerColorEntry(EnumPowerType and EnumPowerType.MANA or nil, "MANA")
	if manaColor then
		if manaColor.r then return manaColor.r, manaColor.g, manaColor.b, manaColor.a or 1 end
		if manaColor[1] then return manaColor[1], manaColor[2], manaColor[3], manaColor[4] or 1 end
	end
	return 0.1, 0.45, 1, 1
end

function H.isPowerDesaturated(powerEnum, powerToken)
	if powerToken == nil and type(powerEnum) == "string" then
		powerToken = powerEnum
		powerEnum = nil
	end
	local overrides = addon.db and addon.db.ufPowerColorOverrides
	return getPowerOverrideEntry(overrides, powerEnum, powerToken) ~= nil
end

function H.getAbsorbColor(hc, defH)
	local defaultAbsorb = (defH and defH.absorbColor) or { 0.85, 0.95, 1, 0.7 }
	if hc and hc.absorbUseCustomColor and hc.absorbColor then
		return hc.absorbColor[1] or defaultAbsorb[1], hc.absorbColor[2] or defaultAbsorb[2], hc.absorbColor[3] or defaultAbsorb[3], hc.absorbColor[4] or defaultAbsorb[4]
	end
	return defaultAbsorb[1], defaultAbsorb[2], defaultAbsorb[3], defaultAbsorb[4]
end

function H.getHealAbsorbColor(hc, defH)
	local defaultAbsorb = (defH and defH.healAbsorbColor) or { 1, 0.3, 0.3, 0.7 }
	if hc and hc.healAbsorbUseCustomColor and hc.healAbsorbColor then
		return hc.healAbsorbColor[1] or defaultAbsorb[1], hc.healAbsorbColor[2] or defaultAbsorb[2], hc.healAbsorbColor[3] or defaultAbsorb[3], hc.healAbsorbColor[4] or defaultAbsorb[4]
	end
	return defaultAbsorb[1], defaultAbsorb[2], defaultAbsorb[3], defaultAbsorb[4]
end

function H.getNPCColorDefault(key)
	local c = key and npcColorDefaults[key]
	if not c then return nil end
	return c[1], c[2], c[3], c[4]
end

function H.getNPCColor(key)
	if not key then return nil end
	local overrides = addon.db and addon.db.ufNPCColorOverrides
	local override = overrides and overrides[key]
	if override then
		if override.r then return override.r, override.g, override.b, override.a or 1 end
		if override[1] then return override[1], override[2], override[3], override[4] or 1 end
	end
	return H.getNPCColorDefault(key)
end

local EnableSpellRangeCheck = C_Spell and C_Spell.EnableSpellRangeCheck
local GetSpellIDForSpellIdentifier = C_Spell and C_Spell.GetSpellIDForSpellIdentifier
local GetSpellName = C_Spell and C_Spell.GetSpellName
local GetSpellInfo = _G.GetSpellInfo
local SpellBook = _G.C_SpellBook
local SpellBookItemType = Enum and Enum.SpellBookItemType
local SpellBookSpellBank = Enum and Enum.SpellBookSpellBank
local UnitClass = _G.UnitClass
local GetSpecialization = _G.GetSpecialization
local GetSpecializationInfo = _G.GetSpecializationInfo
local GetSpecializationInfoForClassID = _G.GetSpecializationInfoForClassID
local GetNumSpecializationsForClassID = _G.GetNumSpecializationsForClassID
local GetNumClasses = _G.GetNumClasses
local GetClassInfo = _G.GetClassInfo
local IsHelpfulSpell = _G.IsHelpfulSpell
local IsHarmfulSpell = _G.IsHarmfulSpell
local C_CreatureInfo = _G.C_CreatureInfo
local wipeTable = wipe or (table and table.wipe)
local tinsert = table.insert
local tsort = table.sort

local rangeFadeClassDefaultSpells = {
	DEATHKNIGHT = { friendly = 47541, enemy = 49576 },
	DEMONHUNTER = { friendly = nil, enemy = 278326 },
	DRUID = { friendly = 8936, enemy = 8921 },
	EVOKER = { friendly = 355913, enemy = 362969 },
	HUNTER = { friendly = nil, enemy = 75 },
	MAGE = { friendly = 1459, enemy = 2139 },
	MONK = { friendly = 116670, enemy = 115546 },
	PALADIN = { friendly = 85673, enemy = 20271 },
	PRIEST = { friendly = 17, enemy = 589 },
	ROGUE = { friendly = nil, enemy = 36554 },
	SHAMAN = { friendly = 8004, enemy = 8042 },
	WARLOCK = { friendly = 5697, enemy = 234153 },
	WARRIOR = { friendly = nil, enemy = 355 },
}

local rangeFadeSpecOptionsCache
local rangeFadeSpellOptionCache = { friendly = {}, enemy = {} }
local rangeFadeClassSpellOptions = {
	DEATHKNIGHT = {
		friendly = {},
		enemy = { 49576, 47541 },
	},
	DEMONHUNTER = {
		friendly = {},
		enemy = { 185123, 183752, 204021 },
	},
	DRUID = {
		friendly = { 8936, 774, 2782, 88423 },
		enemy = { 5176, 339, 6795, 33786, 22568, 8921 },
	},
	EVOKER = {
		friendly = { 355913, 361469, 360823 },
		enemy = { 362969 },
	},
	HUNTER = {
		friendly = {},
		enemy = { 75 },
	},
	MAGE = {
		friendly = { 1459, 475 },
		enemy = { 44614, 118, 116, 133, 44425 },
	},
	MONK = {
		friendly = { 115450, 115546, 116670 },
		enemy = { 115546, 115078, 100780, 117952 },
	},
	PALADIN = {
		friendly = { 19750, 85673, 4987, 213644 },
		enemy = { 853, 35395, 62124, 183218, 20271, 20473 },
	},
	PRIEST = {
		friendly = { 21562, 17, 527, 2061 },
		enemy = { 589, 8092, 585 },
	},
	ROGUE = {
		friendly = { 36554, 921 },
		enemy = { 185565, 36554, 185763, 2094, 921 },
	},
	SHAMAN = {
		friendly = { 546, 8004, 188070 },
		enemy = { 370, 8042, 117014, 188196, 73899 },
	},
	WARLOCK = {
		friendly = { 20707, 5697 },
		enemy = { 234153, 198590, 232670, 686, 5782 },
	},
	WARRIOR = {
		friendly = {},
		enemy = { 355, 5246, 100 },
	},
}

local rangeFadeHandlers = {}
local rangeFadeState = {
	activeSpells = {},
	spellStates = {},
	numChecked = 0,
	numInRange = 0,
	inRange = true,
	configDirty = true,
	configValid = false,
	enabled = false,
	alpha = 1,
	ignoreUnlimited = true,
	spellListDirty = true,
	spellListCache = nil,
}
local rangeFadeIgnoredSpells = {
	[2096] = true, -- Mind Vision (unlimited range)
}

local getRangeFadeConfig

local function isRangeFadeIgnored(spellId, actionId)
	local _, _, ignoreUnlimited = getRangeFadeConfig()
	if ignoreUnlimited == false then return false end
	if spellId and rangeFadeIgnoredSpells[spellId] then return true end
	if actionId and rangeFadeIgnoredSpells[actionId] then return true end
	return false
end

local function clearTable(tbl)
	if not tbl then return end
	if wipeTable then
		wipeTable(tbl)
	else
		for k in pairs(tbl) do
			tbl[k] = nil
		end
	end
end

local function getRangeFadeClassInfo()
	if not UnitClass then return nil, nil end
	local _, classToken, classID = UnitClass("player")
	return classToken, classID
end

local function getClassInfoById(classId)
	if GetClassInfo then return GetClassInfo(classId) end
	if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
		local info = C_CreatureInfo.GetClassInfo(classId)
		if info then return info.className, info.classFile, info.classID end
	end
	return nil, nil, nil
end

local getCurrentSpecId

local function buildRangeFadeSpecEntries()
	local entries = {}
	local bySpecId = {}
	local sex = UnitSex and UnitSex("player") or nil

	if GetNumClasses and GetNumSpecializationsForClassID and GetSpecializationInfoForClassID then
		local numClasses = GetNumClasses() or 0
		for classIndex = 1, numClasses do
			local className, classToken, classID = getClassInfoById(classIndex)
			if classID then
				local specCount = GetNumSpecializationsForClassID(classID) or 0
				for specIndex = 1, specCount do
					local specID, specName = GetSpecializationInfoForClassID(classID, specIndex, sex)
					if specID then
						local label = specName or ("Spec " .. tostring(specID))
						local classLabel = className or classToken
						if classLabel and classLabel ~= "" then label = classLabel .. " - " .. label end
						local entry = {
							value = specID,
							label = label,
							specName = specName or ("Spec " .. tostring(specID)),
							className = className or classToken,
							classToken = classToken,
							classID = classID,
						}
						tinsert(entries, entry)
						bySpecId[specID] = entry
					end
				end
			end
		end
	end

	if #entries == 0 then
		local specID = getCurrentSpecId()
		if specID then
			local classToken, classID = getRangeFadeClassInfo()
			local entry = {
				value = specID,
				label = "Spec " .. tostring(specID),
				specName = "Spec " .. tostring(specID),
				className = classToken,
				classToken = classToken,
				classID = classID,
			}
			tinsert(entries, entry)
			bySpecId[specID] = entry
		end
	end

	tsort(entries, function(a, b)
		local aClass = tostring((a and a.className) or "")
		local bClass = tostring((b and b.className) or "")
		if aClass ~= bClass then return aClass < bClass end
		local aSpec = tostring((a and a.specName) or "")
		local bSpec = tostring((b and b.specName) or "")
		if aSpec ~= bSpec then return aSpec < bSpec end
		return (tonumber(a and a.value) or 0) < (tonumber(b and b.value) or 0)
	end)

	return entries, bySpecId
end

getCurrentSpecId = function()
	if not (GetSpecialization and GetSpecializationInfo) then return nil end
	local specIndex = GetSpecialization()
	if not specIndex then return nil end
	local specID = GetSpecializationInfo(specIndex)
	if not specID or specID <= 0 then return nil end
	return specID
end

local function getRangeFadeSpellDisplayName(spellId, includeId)
	local id = tonumber(spellId)
	if not id or id <= 0 then return nil end
	local name = GetSpellName and GetSpellName(id) or nil
	if (not name or name == "") and GetSpellInfo then name = GetSpellInfo(id) end
	if not name or name == "" then name = tostring(id) end
	if includeId then return string.format("%s (%d)", tostring(name), id) end
	return tostring(name)
end

local function normalizeConfiguredSpellId(value)
	if value == false or value == 0 or value == "0" then return false end
	local id = tonumber(value)
	if not id or id <= 0 then return nil end
	return floor(id)
end

function H.RangeFadeGetDefaultSpellPair(specValue)
	local specId = tonumber(specValue)
	local classToken
	if specId and specId > 0 then
		H.RangeFadeGetSpecOptions()
		local cache = rangeFadeSpecOptionsCache
		if cache and cache.bySpecId and cache.bySpecId[specId] then classToken = cache.bySpecId[specId].classToken end
	end
	if not classToken then classToken = getRangeFadeClassInfo() end
	local defaults = classToken and rangeFadeClassDefaultSpells[classToken] or nil
	if not defaults then return nil, nil end
	return defaults.friendly, defaults.enemy
end

function H.RangeFadeGetCurrentSpecId() return getCurrentSpecId() end

function H.RangeFadeGetSpecOptions()
	if rangeFadeSpecOptionsCache and rangeFadeSpecOptionsCache.entries then return rangeFadeSpecOptionsCache.entries end
	local entries, bySpecId = buildRangeFadeSpecEntries()
	rangeFadeSpecOptionsCache = {
		entries = entries,
		bySpecId = bySpecId,
	}
	return entries
end

function H.RangeFadeResolveSpellPair(rangeFadeConfig, specId)
	local spec = tonumber(specId)
	if not spec or spec <= 0 then spec = getCurrentSpecId() end
	local defaultsFriendly, defaultsEnemy = H.RangeFadeGetDefaultSpellPair(spec)

	local specEntry
	if type(rangeFadeConfig) == "table" and spec then
		local bySpec = rangeFadeConfig.specSpells
		if type(bySpec) == "table" then specEntry = bySpec[spec] end
	end

	local configuredFriendly = specEntry and normalizeConfiguredSpellId(specEntry.friendly)
	local configuredEnemy = specEntry and normalizeConfiguredSpellId(specEntry.enemy)

	local friendly
	if configuredFriendly == false then
		friendly = nil
	elseif type(configuredFriendly) == "number" then
		friendly = configuredFriendly
	else
		friendly = defaultsFriendly
	end

	local enemy
	if configuredEnemy == false then
		enemy = nil
	elseif type(configuredEnemy) == "number" then
		enemy = configuredEnemy
	else
		enemy = defaultsEnemy
	end

	return friendly, enemy
end

function H.RangeFadeBuildSpellListForConfig(rangeFadeConfig, specId)
	local friendly, enemy = H.RangeFadeResolveSpellPair(rangeFadeConfig, specId)
	local list = {}
	if friendly then list[#list + 1] = friendly end
	if enemy and enemy ~= friendly then list[#list + 1] = enemy end
	return list
end

function H.RangeFadeGetSpellLabel(spellId, includeId) return getRangeFadeSpellDisplayName(spellId, includeId == true) end

local function buildRangeFadeSpellOptionsFromIds(spellIds)
	local options = {}
	local seen = {}
	if type(spellIds) ~= "table" then return options end
	for i = 1, #spellIds do
		local spellId = tonumber(spellIds[i])
		if spellId and spellId > 0 and not seen[spellId] then
			seen[spellId] = true
			tinsert(options, {
				value = spellId,
				label = getRangeFadeSpellDisplayName(spellId, true) or tostring(spellId),
			})
		end
	end
	tsort(options, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return options
end

local function buildRangeFadeSpellOptionsFromSpellBook(kind)
	local options = {}
	local seen = {}
	if not (SpellBook and SpellBook.GetNumSpellBookSkillLines and SpellBook.GetSpellBookSkillLineInfo and SpellBook.GetSpellBookItemInfo) then return options end
	local bank = SpellBookSpellBank and SpellBookSpellBank.Player or 0
	local spellType = (SpellBookItemType and SpellBookItemType.Spell) or 1
	local numLines = SpellBook.GetNumSpellBookSkillLines() or 0
	for line = 1, numLines do
		local lineInfo = SpellBook.GetSpellBookSkillLineInfo(line)
		local offset = lineInfo and lineInfo.itemIndexOffset or 0
		local count = lineInfo and lineInfo.numSpellBookItems or 0
		for slot = offset + 1, offset + count do
			local info = SpellBook.GetSpellBookItemInfo(slot, bank)
			if info and info.itemType == spellType and info.isPassive ~= true then
				local spellId = info.spellID or info.actionID
				local include = spellId and not seen[spellId]
				if include and kind == "friendly" and IsHelpfulSpell then include = IsHelpfulSpell(spellId) == true end
				if include and kind == "enemy" and IsHarmfulSpell then include = IsHarmfulSpell(spellId) == true end
				if include and spellId then
					seen[spellId] = true
					tinsert(options, {
						value = spellId,
						label = getRangeFadeSpellDisplayName(spellId, true) or tostring(spellId),
					})
				end
			end
		end
	end
	tsort(options, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return options
end

function H.RangeFadeGetSpellOptions(kind, classToken)
	local key = (kind == "enemy") and "enemy" or "friendly"
	local cache = rangeFadeSpellOptionCache[key]
	if type(cache) ~= "table" then
		cache = {}
		rangeFadeSpellOptionCache[key] = cache
	end

	local currentClassToken = getRangeFadeClassInfo()
	local normalizedClassToken = type(classToken) == "string" and classToken or currentClassToken
	if cache[normalizedClassToken] then return cache[normalizedClassToken] end

	local classLists = rangeFadeClassSpellOptions[normalizedClassToken]
	local options
	if classLists and type(classLists[key]) == "table" then
		options = buildRangeFadeSpellOptionsFromIds(classLists[key])
	elseif normalizedClassToken == currentClassToken then
		options = buildRangeFadeSpellOptionsFromSpellBook(key)
	else
		options = {}
	end
	cache[normalizedClassToken] = options
	return options
end

local function normalizeRangeFadeConfig(enabled, alpha, ignoreUnlimited)
	enabled = enabled == true
	alpha = tonumber(alpha)
	if alpha == nil then alpha = 1 end
	if alpha < 0 then alpha = 0 end
	if alpha > 1 then alpha = 1 end
	if ignoreUnlimited == nil then
		ignoreUnlimited = true
	else
		ignoreUnlimited = ignoreUnlimited == true
	end
	return enabled, alpha, ignoreUnlimited
end

local function syncRangeFadeConfig()
	local fn = rangeFadeHandlers.getConfig
	local enabled, alpha, ignoreUnlimited
	if fn then
		enabled, alpha, ignoreUnlimited = fn()
	else
		enabled, alpha, ignoreUnlimited = false, 1, true
	end
	enabled, alpha, ignoreUnlimited = normalizeRangeFadeConfig(enabled, alpha, ignoreUnlimited)

	if rangeFadeState.configValid and rangeFadeState.ignoreUnlimited ~= ignoreUnlimited then rangeFadeState.spellListDirty = true end

	rangeFadeState.enabled = enabled
	rangeFadeState.alpha = alpha
	rangeFadeState.ignoreUnlimited = ignoreUnlimited
	rangeFadeState.configValid = true
	rangeFadeState.configDirty = false
end

getRangeFadeConfig = function()
	if rangeFadeState.configDirty or not rangeFadeState.configValid then syncRangeFadeConfig() end
	return rangeFadeState.enabled, rangeFadeState.alpha, rangeFadeState.ignoreUnlimited
end

local function applyRangeFadeAlpha(inRange, force)
	local applyFn = rangeFadeHandlers.applyAlpha
	if not applyFn then return end
	local enabled, alpha = getRangeFadeConfig()
	local targetAlpha = (enabled and not inRange) and alpha or 1
	applyFn(targetAlpha, force)
end

local function removeRangeFadeSpellState(spellId)
	local oldState = rangeFadeState.spellStates[spellId]
	if oldState == nil then return false end
	rangeFadeState.spellStates[spellId] = nil
	if oldState == true then rangeFadeState.numInRange = math.max(0, (rangeFadeState.numInRange or 0) - 1) end
	rangeFadeState.numChecked = math.max(0, (rangeFadeState.numChecked or 0) - 1)
	return true
end

local function setRangeFadeSpellState(spellId, inRange)
	local newState = (inRange == true)
	local oldState = rangeFadeState.spellStates[spellId]
	if oldState == nil then
		rangeFadeState.spellStates[spellId] = newState
		rangeFadeState.numChecked = (rangeFadeState.numChecked or 0) + 1
		if newState then rangeFadeState.numInRange = (rangeFadeState.numInRange or 0) + 1 end
		return true
	end
	if oldState == newState then return false end
	rangeFadeState.spellStates[spellId] = newState
	if oldState == true then rangeFadeState.numInRange = math.max(0, (rangeFadeState.numInRange or 0) - 1) end
	if newState then rangeFadeState.numInRange = (rangeFadeState.numInRange or 0) + 1 end
	return true
end

local function recomputeRangeFade()
	local numChecked = rangeFadeState.numChecked or 0
	local numInRange = rangeFadeState.numInRange or 0
	rangeFadeState.inRange = (numChecked == 0) or (numInRange > 0)
	applyRangeFadeAlpha(rangeFadeState.inRange)
end

local function buildRangeFadeSpellList()
	local list = {}
	local spellListFn = rangeFadeHandlers.getSpells
	if spellListFn then
		local explicit = spellListFn()
		if type(explicit) == "table" then
			for key, value in pairs(explicit) do
				local spellId
				if type(key) == "number" and value == true then
					spellId = key
				else
					spellId = value
				end
				spellId = tonumber(spellId)
				if spellId and spellId > 0 and not isRangeFadeIgnored(spellId) then list[spellId] = true end
			end
		end
		return list
	end

	if not (EnableSpellRangeCheck and SpellBook and SpellBook.GetNumSpellBookSkillLines and SpellBook.GetSpellBookSkillLineInfo and SpellBook.GetSpellBookItemInfo) then return list end
	local bank = SpellBookSpellBank and SpellBookSpellBank.Player or 0
	local spellType = (SpellBookItemType and SpellBookItemType.Spell) or 1
	local numLines = SpellBook.GetNumSpellBookSkillLines() or 0
	for line = 1, numLines do
		local lineInfo = SpellBook.GetSpellBookSkillLineInfo(line)
		local offset = lineInfo and lineInfo.itemIndexOffset or 0
		local count = lineInfo and lineInfo.numSpellBookItems or 0
		for slot = offset + 1, offset + count do
			local info = SpellBook.GetSpellBookItemInfo(slot, bank)
			if info and info.itemType == spellType and info.isPassive ~= true then
				if not isRangeFadeIgnored(info.spellID, info.actionID) then
					local spellId = info.spellID or info.actionID
					if spellId then list[spellId] = true end
				end
			end
		end
	end
	return list
end

function H.RangeFadeRegister(getConfigFn, applyAlphaFn, getSpellListFn)
	rangeFadeHandlers.getConfig = getConfigFn
	rangeFadeHandlers.applyAlpha = applyAlphaFn
	rangeFadeHandlers.getSpells = getSpellListFn
	rangeFadeState.configDirty = true
	rangeFadeState.spellListDirty = true
	rangeFadeState.spellListCache = nil
	rangeFadeSpellOptionCache.friendly = {}
	rangeFadeSpellOptionCache.enemy = {}
end

function H.RangeFadeReset()
	clearTable(rangeFadeState.spellStates)
	rangeFadeState.numChecked = 0
	rangeFadeState.numInRange = 0
	rangeFadeState.inRange = true
	applyRangeFadeAlpha(true, true)
end

function H.RangeFadeApplyCurrent(force) applyRangeFadeAlpha(rangeFadeState.inRange, force) end

function H.RangeFadeMarkConfigDirty() rangeFadeState.configDirty = true end

function H.RangeFadeMarkSpellListDirty()
	rangeFadeState.spellListDirty = true
	rangeFadeState.spellListCache = nil
	rangeFadeSpellOptionCache.friendly = {}
	rangeFadeSpellOptionCache.enemy = {}
	rangeFadeSpecOptionsCache = nil
end

function H.RangeFadeUpdateFromEvent(spellIdentifier, isInRange, checksRange)
	local enabled = getRangeFadeConfig()
	if not enabled then return end
	local id = tonumber(spellIdentifier)
	if not id and GetSpellIDForSpellIdentifier then id = GetSpellIDForSpellIdentifier(spellIdentifier) end
	if isRangeFadeIgnored(id) then return end
	if not id or not rangeFadeState.activeSpells[id] then return end
	if checksRange then
		setRangeFadeSpellState(id, isInRange == true)
	else
		removeRangeFadeSpellState(id)
	end
	recomputeRangeFade()
end

function H.RangeFadeUpdateSpells()
	if not EnableSpellRangeCheck then return end
	local enabled = getRangeFadeConfig()
	if not enabled then
		for spellId in pairs(rangeFadeState.activeSpells) do
			EnableSpellRangeCheck(spellId, false)
		end
		clearTable(rangeFadeState.activeSpells)
		H.RangeFadeReset()
		return
	end
	if rangeFadeState.spellListDirty or not rangeFadeState.spellListCache then
		rangeFadeState.spellListCache = buildRangeFadeSpellList()
		rangeFadeState.spellListDirty = false
	end
	local wanted = rangeFadeState.spellListCache or {}
	for spellId in pairs(rangeFadeState.activeSpells) do
		if not wanted[spellId] then
			EnableSpellRangeCheck(spellId, false)
			rangeFadeState.activeSpells[spellId] = nil
			removeRangeFadeSpellState(spellId)
		end
	end
	for spellId in pairs(wanted) do
		if not rangeFadeState.activeSpells[spellId] then
			EnableSpellRangeCheck(spellId, true)
			rangeFadeState.activeSpells[spellId] = true
		end
	end
	recomputeRangeFade()
end
