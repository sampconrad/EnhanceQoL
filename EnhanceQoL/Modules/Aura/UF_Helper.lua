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
local abs = math.abs
local floor = math.floor

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

local nameWidthCache = {}

function H.clamp(value, minV, maxV)
	if value < minV then return minV end
	if value > maxV then return maxV end
	return value
end

function H.trim(str)
	if type(str) ~= "string" then return "" end
	return str:match("^%s*(.-)%s*$")
end

function H.getFont(path)
	if path and path ~= "" then return path end
	return addon.variables and addon.variables.defaultFont or (LSM and LSM:Fetch("font", LSM.DefaultMedia.font)) or STANDARD_TEXT_FONT
end

function H.applyFont(fs, fontPath, size, outline)
	if not fs then return end
	fs:SetFont(H.getFont(fontPath), size or 14, outline or "OUTLINE")
	fs:SetShadowColor(0, 0, 0, 0.5)
	fs:SetShadowOffset(0.5, -0.5)
end

function H.resolveBorderTexture(key)
	if not key or key == "" or key == "DEFAULT" then return "Interface\\Buttons\\WHITE8x8" end
	if LSM then
		local tex = LSM:Fetch("border", key)
		if tex and tex ~= "" then return tex end
	end
	return key
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

function H.configureSpecialTexture(bar, pType, texKey, cfg)
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

function H.resolveTextDelimiter(delimiter)
	if delimiter == nil or delimiter == "" then delimiter = " " end
	if delimiter == " " then return " " end
	return " " .. tostring(delimiter) .. " "
end

function H.shortValue(val)
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

function H.textModeUsesLevel(mode) return type(mode) == "string" and mode:find("LEVEL", 1, true) ~= nil end

function H.getUnitLevelText(unit)
	if not unit then return "??" end
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
	return levelText
end

function H.formatText(mode, cur, maxv, useShort, percentValue, delimiter, hidePercentSymbol, levelText)
	if mode == "NONE" then return "" end
	local join = H.resolveTextDelimiter(delimiter)
	local percentSuffix = hidePercentSymbol and "" or "%"
	if levelText == nil or levelText == "" then levelText = "??" end
	local isPercentMode = type(mode) == "string" and mode:find("PERCENT", 1, true) ~= nil
	local function formatPercentMode(curText, maxText, percentText)
		if not percentText then return "" end
		if mode == "PERCENT" then return percentText end
		if mode == "CURPERCENT" or mode == "CURPERCENTDASH" then return table.concat({ curText, percentText }, join) end
		if mode == "CURMAXPERCENT" then return table.concat({ curText, maxText, percentText }, join) end
		if mode == "MAXPERCENT" then return table.concat({ maxText, percentText }, join) end
		if mode == "PERCENTMAX" then return table.concat({ percentText, maxText }, join) end
		if mode == "PERCENTCUR" then return table.concat({ percentText, curText }, join) end
		if mode == "PERCENTCURMAX" then return table.concat({ percentText, curText, maxText }, join) end
		if mode == "LEVELPERCENT" then return table.concat({ levelText, percentText }, join) end
		if mode == "LEVELPERCENTMAX" then return table.concat({ levelText, percentText, maxText }, join) end
		if mode == "LEVELPERCENTCUR" then return table.concat({ levelText, percentText, curText }, join) end
		if mode == "LEVELPERCENTCURMAX" then return table.concat({ levelText, percentText, curText, maxText }, join) end
		return ""
	end
	if addon.variables and addon.variables.isMidnight and issecretvalue then
		if (cur and issecretvalue(cur)) or (maxv and issecretvalue(maxv)) then
			local scur = useShort and H.shortValue(cur) or BreakUpLargeNumbers(cur)
			local smax = useShort and H.shortValue(maxv) or BreakUpLargeNumbers(maxv)
			local percentText
			if percentValue ~= nil then percentText = ("%s%s"):format(tostring(AbbreviateLargeNumbers(percentValue)), percentSuffix) end

			if mode == "CURRENT" then return tostring(scur) end
			if mode == "MAX" then return tostring(smax) end
			if mode == "CURMAX" then return ("%s/%s"):format(tostring(scur), tostring(smax)) end
			if isPercentMode then return formatPercentMode(tostring(scur), tostring(smax), percentText) end
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
		return ("%s/%s"):format(curText, maxText)
	end
	if isPercentMode then
		local curText = useShort == false and tostring(cur or 0) or H.shortValue(cur or 0)
		local maxText = useShort == false and tostring(maxv or 0) or H.shortValue(maxv or 0)
		return formatPercentMode(curText, maxText, percentText)
	end
	if useShort == false then return tostring(cur or 0) end
	return H.shortValue(cur or 0)
end

function H.getNameLimitWidth(fontPath, fontSize, fontOutline, maxChars)
	if not maxChars or maxChars <= 0 then return nil end
	local font = H.getFont(fontPath)
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

function H.getTextDelimiter(cfg, def)
	local defaultDelim = (def and def.textDelimiter) or " "
	local delimiter = cfg and cfg.textDelimiter
	if delimiter == nil or delimiter == "" then delimiter = defaultDelim end
	return delimiter
end

function H.getPowerColor(pToken)
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

function H.isPowerDesaturated(pToken)
	if not pToken then return false end
	local overrides = addon.db and addon.db.ufPowerColorOverrides
	return overrides and overrides[pToken] ~= nil
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
