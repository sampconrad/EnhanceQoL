-- luacheck: globals RegisterStateDriver UnregisterStateDriver RegisterUnitWatch
local parentAddonName = "EnhanceQoL"
local addon = select(2, ...)

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
local EMPTY = {}
local getCfg

local UFHelper = addon.Aura.UFHelper
local AuraUtil = UF.AuraUtil
local EditMode = addon.EditMode
local SettingType = EditMode and EditMode.lib and EditMode.lib.SettingType
local DispelOverlayOrientation = EnumUtil and EnumUtil.MakeEnum("VerticalTopToBottom", "VerticalBottomToTop", "HorizontalLeftToRight")

local PowerBarColor = PowerBarColor
local LSM = LibStub and LibStub("LibSharedMedia-3.0")
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
local DISPEL_GLOW_KEY = "EQOL_DISPEL"

local GFH = UF.GroupFramesHelper
local clampNumber = GFH.ClampNumber
local copySelectionMap = GFH.CopySelectionMap
local roleOptions = GFH.roleOptions
local defaultRoleSelection = GFH.DefaultRoleSelection
local defaultSpecSelection = GFH.DefaultSpecSelection
local auraAnchorOptions = GFH.auraAnchorOptions
local anchorOptions9 = GFH.anchorOptions9 or GFH.auraAnchorOptions
local textModeOptions = GFH.textModeOptions
local healthTextModeOptions = GFH.healthTextModeOptions or GFH.textModeOptions
local delimiterOptions = GFH.delimiterOptions
local outlineOptions = GFH.outlineOptions
local ensureAuraConfig = GFH.EnsureAuraConfig
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")

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
local min = math.min
local floor = math.floor
local ceil = math.ceil
local hooksecurefunc = hooksecurefunc
local BAR_TEX_INHERIT = "__PER_BAR__"
local EDIT_MODE_SAMPLE_MAX = 100
local AURA_FILTERS = GFH.AuraFilters
local SECRET_TEXT_UPDATE_INTERVAL = 0.1
local FONT_DROPDOWN_SCROLL_HEIGHT = 220

local function queryAuraSlots(unit, filter, maxCount)
	if not filter then return nil end
	if maxCount then return { C_UnitAuras.GetAuraSlots(unit, filter, maxCount) } end
	return { C_UnitAuras.GetAuraSlots(unit, filter) }
end

local PREVIEW_SAMPLES = GFH.PREVIEW_SAMPLES or { party = {}, raid = {}, mt = {}, ma = {} }
local groupNumberFormatOptions = GFH.GROUP_NUMBER_FORMAT_OPTIONS or {}
local groupNumberFormatTokens = {}
local groupNumberFormatByText = {}
local groupNumberFormatLabelByValue = {}
do
	for _, option in ipairs(groupNumberFormatOptions) do
		if option then
			local value = option.value
			if value ~= nil then
				groupNumberFormatTokens[value] = true
				if groupNumberFormatLabelByValue[value] == nil then groupNumberFormatLabelByValue[value] = option.label or option.text or tostring(value) end
			end
			if option.text ~= nil then groupNumberFormatByText[option.text] = value end
			if option.label ~= nil then groupNumberFormatByText[option.label] = value end
		end
	end
end

local function normalizeGroupNumberFormat(format)
	if format == nil then return nil end
	if groupNumberFormatTokens[format] then return format end
	local text = tostring(format)
	local mapped = groupNumberFormatByText[text]
	if mapped then return mapped end
	local upper = text:upper()
	if groupNumberFormatTokens[upper] then return upper end
	mapped = groupNumberFormatByText[upper]
	if mapped then return mapped end
	return text
end
local function hideDispelTint(st)
	if not (st and st.dispelTint) then return end
	if st._dispelTintShown == false then return end
	st._dispelTintShown = false
	st.dispelTint:Hide()
end
local function applyDispelTint(st, r, g, b, alpha, fr, fg, fb, bgAlpha)
	if not (st and st.dispelTint) then return end
	st._dispelTintShown = true

	local bg = st.dispelTint.Background
	if bg then
		if bg.SetColorTexture then
			bg:SetColorTexture(fr, fg, fb, 1)
		elseif bg.SetVertexColor then
			bg:SetVertexColor(fr, fg, fb, 1)
		end
		if bg.SetAlpha then bg:SetAlpha(bgAlpha) end
		if bg.SetShown then bg:SetShown(bgAlpha > 0) end
	end
	local grad = st.dispelTint.Gradient
	if grad then grad:SetVertexColor(r, g, b, alpha) end
	local border = st.dispelTint.Border
	if border then border:SetVertexColor(r, g, b, alpha) end
	if st.dispelTint.SetAlpha then st.dispelTint:SetAlpha(1) end
	st.dispelTint:Show()
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
			tile = false,
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
	if type(color) ~= "table" then color = GFH.COLOR_WHITE end
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
		tile = false,
		edgeSize = size,
		insets = { left = size, right = size, top = size, bottom = size },
	})
	frame:SetBackdropColor(0, 0, 0, 0)
	local color = cfg.color or GFH.COLOR_WHITE
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
	local enabled = bd.enabled ~= false
	local col = bd.color or { 0, 0, 0, 0.6 }
	local r = col[1] or 0
	local g = col[2] or 0
	local b = col[3] or 0
	local a = col[4] or 0.6

	if not enabled then
		if bar._eqolBackdropEnabled == false then return end
		bar:SetBackdrop(nil)
		bar._eqolBackdropEnabled = false
		bar._eqolBackdropR, bar._eqolBackdropG, bar._eqolBackdropB, bar._eqolBackdropA = nil, nil, nil, nil
		bar._eqolBackdropConfigured = nil
		return
	end
	if bar._eqolBackdropEnabled == true and bar._eqolBackdropConfigured == true and bar._eqolBackdropR == r and bar._eqolBackdropG == g and bar._eqolBackdropB == b and bar._eqolBackdropA == a then
		return
	end

	if bar._eqolBackdropConfigured ~= true then
		bar:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = nil,
			tile = false,
		})
		bar._eqolBackdropConfigured = true
	end
	bar:SetBackdropColor(r, g, b, a)
	bar._eqolBackdropEnabled = true
	bar._eqolBackdropR, bar._eqolBackdropG, bar._eqolBackdropB, bar._eqolBackdropA = r, g, b, a
end

local function getEffectiveBarTexture(cfg, barCfg)
	local tex = cfg and cfg.barTexture
	if tex == nil or tex == "" then tex = barCfg and barCfg.texture end
	return tex
end

local function stabilizeStatusBarTexture(bar)
	if not bar then return end
	if bar.SetSnapToPixelGrid then bar:SetSnapToPixelGrid(false) end
	if bar.SetTexelSnappingBias then bar:SetTexelSnappingBias(0) end
	if not bar.GetStatusBarTexture then return end
	local t = bar:GetStatusBarTexture()
	if not t then return end
	if t.SetHorizTile then t:SetHorizTile(false) end
	if t.SetVertTile then t:SetVertTile(false) end
	if t.SetTexCoord then t:SetTexCoord(0, 1, 0, 1) end
	if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
	if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
end

local roundToPixel = GFH.RoundToPixel

local function roundToEvenPixel(value, scale) return roundToPixel(value, scale) end

local layoutTexts = GFH.LayoutTexts

local function setFrameLevelAbove(child, parent, offset)
	if not child or not parent then return end
	if child.SetFrameStrata and parent.GetFrameStrata then child:SetFrameStrata(parent:GetFrameStrata()) end
	if child.SetFrameLevel and parent.GetFrameLevel then child:SetFrameLevel((parent:GetFrameLevel() or 0) + (offset or 1)) end
end

local function syncTextFrameLevels(st)
	if not st then return end
	setFrameLevelAbove(st.healthTextLayer, st.health, 5)
	setFrameLevelAbove(st.powerTextLayer, st.power, 5)
	if st.statusIconLayer then
		local parent = st.healthTextLayer or st.health or st.barGroup or st.frame
		setFrameLevelAbove(st.statusIconLayer, parent, 6)
		if st.barGroup and st.statusIconLayer.SetAllPoints then st.statusIconLayer:SetAllPoints(st.barGroup) end
	end
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

local function getUnitClassToken(unit)
	if not unit then return nil end
	local _, class = UnitClass(unit)
	if issecretvalue and issecretvalue(class) then class = nil end
	if class and class ~= "" then return tostring(class) end
	if UnitInRaid and GetRaidRosterInfo then
		local raidIndex = UnitInRaid(unit)
		if raidIndex and not (issecretvalue and issecretvalue(raidIndex)) then
			local _, _, _, _, _, classFile = GetRaidRosterInfo(raidIndex)
			if not (issecretvalue and issecretvalue(classFile)) and classFile and classFile ~= "" then return tostring(classFile) end
		end
	end
	if UnitGUID and GetPlayerInfoByGUID then
		local guid = UnitGUID(unit)
		if not (issecretvalue and issecretvalue(guid)) and guid and guid ~= "" then
			local _, classFile = GetPlayerInfoByGUID(guid)
			if not (issecretvalue and issecretvalue(classFile)) and classFile and classFile ~= "" then return tostring(classFile) end
		end
	end
	return nil
end

local function unpackColor(color, fallback)
	if not color then color = fallback end
	if not color then return 1, 1, 1, 1 end
	if color.r then return color.r, color.g, color.b, color.a or 1 end
	return color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
end

local function formatGroupNumber(subgroup, format)
	local num = tonumber(subgroup)
	if not num then return nil end
	local fmt = normalizeGroupNumberFormat(format) or "GROUP"
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

local function getGroupNumberConfig(cfg, def)
	local sc = cfg and cfg.status or {}
	local us = sc.unitStatus or {}
	local gn = sc.groupNumber or {}
	local defStatus = def and def.status or {}
	local defUS = defStatus.unitStatus or {}
	local defGN = defStatus.groupNumber or {}
	return sc, us, gn, defUS, defGN
end

local function resolveGroupByValue(cfg, def)
	local groupBy = (cfg and cfg.groupBy) or (def and def.groupBy)
	local v = tostring(groupBy or "GROUP"):upper()
	if v == "ROLE" then v = "ASSIGNEDROLE" end
	if v == "CLASS" then v = "GROUP" end
	if v == "GROUP" or v == "ASSIGNEDROLE" then return v end
	return nil
end

local function resolveSortMethod(cfg)
	local raw = cfg and cfg.sortMethod
	local v = tostring(raw or ""):upper()
	if v == "CUSTOM" then v = "NAMELIST" end
	if GFH and GFH.NormalizeSortMethod then
		v = GFH.NormalizeSortMethod(v)
	elseif v ~= "NAME" and v ~= "INDEX" and v ~= "NAMELIST" then
		v = "INDEX"
	end
	local custom = cfg and GFH and GFH.EnsureCustomSortConfig and GFH.EnsureCustomSortConfig(cfg)
	if v ~= "NAMELIST" and custom and custom.enabled == true then
		if raw == nil or raw == "" or tostring(raw):upper() == "CUSTOM" then v = "NAMELIST" end
	end
	return v
end

local function isGroupByGroup(cfg, def) return resolveGroupByValue(cfg, def) == "GROUP" end

local EMPTY_NAMELIST_TOKEN = "__EQOL_EMPTY__"

local function isGroupCustomLayout(cfg)
	if not cfg then return false end
	if resolveSortMethod(cfg) ~= "NAMELIST" then return false end
	local rawGroupBy = cfg.groupBy
	local normalized = resolveGroupByValue(cfg, DEFAULTS.raid) or "GROUP"
	if normalized ~= "GROUP" then return false end
	if rawGroupBy and tostring(rawGroupBy):upper() == "CLASS" then return false end
	return true
end

function GF:IsRaidGroupedLayout(cfg)
	if not cfg then return false end
	local rawGroupBy = cfg.groupBy
	local normalized = resolveGroupByValue(cfg, DEFAULTS.raid) or "GROUP"
	if normalized ~= "GROUP" then return false end
	if rawGroupBy and tostring(rawGroupBy):upper() == "CLASS" then return false end
	return true
end

function GF:BuildDenseCustomGroupSpecs(cfg)
	if not (GFH and GFH.BuildCustomSortNameListsByGroup) then return {} end
	local sparseLists = GFH.BuildCustomSortNameListsByGroup(cfg) or {}

	local function trimCsvToken(token)
		local normalized = tostring(token or "")
		normalized = normalized:gsub("^%s+", "")
		normalized = normalized:gsub("%s+$", "")
		return normalized
	end

	local function buildOrderedGroups(onlyExisting)
		local ordering = (cfg and cfg.groupingOrder) or (GFH and GFH.GROUP_ORDER) or "1,2,3,4,5,6,7,8"
		local groups, seen = {}, {}
		if type(ordering) == "string" and ordering ~= "" then
			for token in ordering:gmatch("[^,]+") do
				local num = tonumber(trimCsvToken(token))
				if num and num >= 1 and num <= 8 and not seen[num] then
					seen[num] = true
					groups[#groups + 1] = num
				end
			end
		end
		if #groups == 0 then
			for i = 1, 8 do
				groups[#groups + 1] = i
				seen[i] = true
			end
		else
			for i = 1, 8 do
				if not seen[i] then groups[#groups + 1] = i end
			end
		end

		local numericFilter, hasNumericFilter = {}, false
		if cfg and type(cfg.groupFilter) == "string" and cfg.groupFilter ~= "" then
			for token in cfg.groupFilter:gmatch("[^,]+") do
				local num = tonumber(trimCsvToken(token))
				if num and num >= 1 and num <= 8 then
					numericFilter[num] = true
					hasNumericFilter = true
				end
			end
		end

		local existing
		if onlyExisting then
			existing = {}
			if IsInRaid and IsInRaid() and GetNumGroupMembers and GetRaidRosterInfo then
				for i = 1, GetNumGroupMembers() do
					local _, _, subgroup = GetRaidRosterInfo(i)
					subgroup = tonumber(subgroup)
					if subgroup and subgroup >= 1 and subgroup <= 8 then existing[subgroup] = true end
				end
			end
		end

		local ordered = {}
		for _, group in ipairs(groups) do
			local allowed = (not hasNumericFilter) or numericFilter[group]
			local present = (not onlyExisting) or (existing and existing[group])
			if allowed and present then ordered[#ordered + 1] = group end
		end
		return ordered
	end

	local orderedGroups = buildOrderedGroups(true)
	if #orderedGroups == 0 then orderedGroups = buildOrderedGroups(false) end
	local fallbackLists = {}
	local fallbackGroups = {}
	if IsInRaid and IsInRaid() and GetNumGroupMembers and GetRaidRosterInfo then
		for i = 1, GetNumGroupMembers() do
			local name, _, subgroup = GetRaidRosterInfo(i)
			subgroup = tonumber(subgroup)
			if subgroup and subgroup >= 1 and subgroup <= 8 then
				fallbackGroups[subgroup] = true
				if name then
					fallbackLists[subgroup] = fallbackLists[subgroup] or {}
					fallbackLists[subgroup][#fallbackLists[subgroup] + 1] = name
				end
			end
		end
	end
	local specs = {}
	for _, group in ipairs(orderedGroups) do
		local nameList = sparseLists[group]
		if (type(nameList) ~= "string" or nameList == "") and fallbackLists[group] then nameList = table.concat(fallbackLists[group], ",") end
		if type(nameList) == "string" and nameList ~= "" then
			specs[#specs + 1] = {
				group = group,
				sortMethod = "NAMELIST",
				nameList = nameList,
			}
		elseif fallbackGroups[group] then
			-- Fallback while custom namelists are still warming up (for example right after login/reload).
			specs[#specs + 1] = {
				group = group,
				sortMethod = "INDEX",
				nameList = nil,
			}
		end
	end
	return specs
end

function GF:BuildRaidGroupHeaderSpecs(cfg, sortMethod, useCustomSort)
	if useCustomSort then return GF:BuildDenseCustomGroupSpecs(cfg) end

	local method = tostring(sortMethod or "INDEX"):upper()
	if method ~= "NAME" and method ~= "INDEX" then method = "INDEX" end

	local function trimCsvToken(token)
		local normalized = tostring(token or "")
		normalized = normalized:gsub("^%s+", "")
		normalized = normalized:gsub("%s+$", "")
		return normalized
	end

	local ordering = (cfg and cfg.groupingOrder) or (GFH and GFH.GROUP_ORDER) or "1,2,3,4,5,6,7,8"
	local groups, seen = {}, {}
	if type(ordering) == "string" and ordering ~= "" then
		for token in ordering:gmatch("[^,]+") do
			local num = tonumber(trimCsvToken(token))
			if num and num >= 1 and num <= 8 and not seen[num] then
				seen[num] = true
				groups[#groups + 1] = num
			end
		end
	end
	if #groups == 0 then
		for i = 1, 8 do
			groups[#groups + 1] = i
			seen[i] = true
		end
	else
		for i = 1, 8 do
			if not seen[i] then groups[#groups + 1] = i end
		end
	end

	local numericFilter, hasNumericFilter = {}, false
	if cfg and type(cfg.groupFilter) == "string" and cfg.groupFilter ~= "" then
		for token in cfg.groupFilter:gmatch("[^,]+") do
			local num = tonumber(trimCsvToken(token))
			if num and num >= 1 and num <= 8 then
				numericFilter[num] = true
				hasNumericFilter = true
			end
		end
	end

	local existing = {}
	if IsInRaid and IsInRaid() and GetNumGroupMembers and GetRaidRosterInfo then
		for i = 1, GetNumGroupMembers() do
			local _, _, subgroup = GetRaidRosterInfo(i)
			subgroup = tonumber(subgroup)
			if subgroup and subgroup >= 1 and subgroup <= 8 then existing[subgroup] = true end
		end
	end

	local specs = {}
	for _, group in ipairs(groups) do
		local allowed = (not hasNumericFilter) or numericFilter[group]
		local present = existing[group]
		if allowed and present then specs[#specs + 1] = {
			group = group,
			sortMethod = method,
		} end
	end

	if #specs == 0 then
		for _, group in ipairs(groups) do
			local allowed = (not hasNumericFilter) or numericFilter[group]
			if allowed then specs[#specs + 1] = {
				group = group,
				sortMethod = method,
			} end
		end
	end

	return specs
end

local function resolveGroupNumberSettingEnabled(cfg, def)
	local _, us, gn, defUS, defGN = getGroupNumberConfig(cfg, def)
	local enabled = gn.enabled
	if enabled == nil then enabled = us.showGroup end
	if enabled == nil then enabled = defGN.enabled end
	if enabled == nil then enabled = defUS.showGroup end
	return enabled == true
end

local function resolveGroupNumberEnabled(cfg, def)
	local enabled = resolveGroupNumberSettingEnabled(cfg, def)
	if enabled == true and cfg and cfg.groupIndicator and cfg.groupIndicator.hidePerFrame == true and isGroupByGroup(cfg, def) then
		local gi = cfg.groupIndicator or {}
		local defGI = def and def.groupIndicator or {}
		local giEnabled = gi.enabled
		if giEnabled == nil then giEnabled = defGI.enabled end
		if giEnabled == true then return false end
	end
	return enabled == true
end

local function resolveGroupNumberFormat(cfg, def)
	local _, us, gn, defUS, defGN = getGroupNumberConfig(cfg, def)
	local fmt = gn.format or us.groupFormat or defGN.format or defUS.groupFormat or "GROUP"
	return normalizeGroupNumberFormat(fmt) or "GROUP"
end

local function resolveStatusTextStyle(cfg, def, hc)
	local sc = cfg and cfg.status or {}
	local us = sc.unitStatus or {}
	local defStatus = def and def.status or {}
	local defUS = defStatus.unitStatus or {}
	local defH = (def and def.health) or {}
	return {
		font = us.font or defUS.font or hc.font or defH.font,
		fontSize = us.fontSize or defUS.fontSize or hc.fontSize or defH.fontSize or 12,
		fontOutline = us.fontOutline or defUS.fontOutline or hc.fontOutline or defH.fontOutline or "OUTLINE",
		color = us.color or defUS.color or { 1, 1, 1, 1 },
		anchor = us.anchor or defUS.anchor or "CENTER",
		offset = us.offset or defUS.offset or {},
	}
end

local function resolveGroupNumberStyle(cfg, def, hc)
	local _, us, gn, defUS, defGN = getGroupNumberConfig(cfg, def)
	local defH = (def and def.health) or {}
	return {
		font = gn.font or defGN.font or us.font or defUS.font or hc.font or defH.font,
		fontSize = gn.fontSize or defGN.fontSize or us.fontSize or defUS.fontSize or hc.fontSize or defH.fontSize or 12,
		fontOutline = gn.fontOutline or defGN.fontOutline or us.fontOutline or defUS.fontOutline or hc.fontOutline or defH.fontOutline or "OUTLINE",
		color = gn.color or defGN.color or us.color or defUS.color or { 1, 1, 1, 1 },
		anchor = gn.anchor or defGN.anchor or us.anchor or defUS.anchor or "CENTER",
		offset = gn.offset or defGN.offset or us.offset or defUS.offset or {},
	}
end

local function getGroupIndicatorConfig(cfg, def)
	local gi = cfg and cfg.groupIndicator or {}
	local defGI = def and def.groupIndicator or {}
	return gi, defGI
end

local function resolveGroupIndicatorEnabled(cfg, def)
	local gi, defGI = getGroupIndicatorConfig(cfg, def)
	local enabled = gi.enabled
	if enabled == nil then enabled = defGI.enabled end
	return enabled == true
end

local function resolveGroupIndicatorFormat(cfg, def)
	local gi, defGI = getGroupIndicatorConfig(cfg, def)
	local fmt = gi.format or defGI.format or "GROUP"
	return normalizeGroupNumberFormat(fmt) or "GROUP"
end

local function resolveGroupIndicatorStyle(cfg, def, hc)
	local gi, defGI = getGroupIndicatorConfig(cfg, def)
	local defH = (def and def.health) or {}
	return {
		font = gi.font or defGI.font or hc.font or defH.font,
		fontSize = gi.fontSize or defGI.fontSize or hc.fontSize or defH.fontSize or 12,
		fontOutline = gi.fontOutline or defGI.fontOutline or hc.fontOutline or defH.fontOutline or "OUTLINE",
		color = gi.color or defGI.color or { 1, 1, 1, 1 },
		anchor = gi.anchor or defGI.anchor or "TOPLEFT",
		offset = gi.offset or defGI.offset or {},
	}
end

local function isGroupIndicatorAvailable(cfg, def)
	if not isGroupByGroup(cfg, def) then return false end
	return true
end

local function resolveStatusTextAnchor(anchor)
	local a = tostring(anchor or "CENTER"):upper()
	if a == "LEFT" then return "LEFT", "LEFT", "LEFT" end
	if a == "RIGHT" then return "RIGHT", "RIGHT", "RIGHT" end
	if a == "TOP" then return "TOP", "TOP", "CENTER" end
	if a == "BOTTOM" then return "BOTTOM", "BOTTOM", "CENTER" end
	if a == "TOPLEFT" then return "TOPLEFT", "TOPLEFT", "LEFT" end
	if a == "TOPRIGHT" then return "TOPRIGHT", "TOPRIGHT", "RIGHT" end
	if a == "BOTTOMLEFT" then return "BOTTOMLEFT", "BOTTOMLEFT", "LEFT" end
	if a == "BOTTOMRIGHT" then return "BOTTOMRIGHT", "BOTTOMRIGHT", "RIGHT" end
	return "CENTER", "CENTER", "CENTER"
end

local function applyStatusTextAnchor(st, anchor, offset, scale, parent, fs)
	local target = fs or (st and st.statusText)
	if not target then return end
	local point, relPoint, justify = resolveStatusTextAnchor(anchor)
	local off = offset or {}
	target:ClearAllPoints()
	target:SetPoint(point, parent, relPoint, roundToPixel(off.x or 0, scale), roundToPixel(off.y or 0, scale))
	if justify and target.SetJustifyH then target:SetJustifyH(justify) end
end

local function applyGroupIndicatorAnchor(fs, anchor, offset, scale, parent)
	if not (fs and parent) then return end
	local point, relPoint
	if GFH and GFH.GetOuterAnchorPoint then
		point, relPoint = GFH.GetOuterAnchorPoint(anchor)
	else
		point, relPoint = resolveStatusTextAnchor(anchor)
	end
	local _, _, justify = resolveStatusTextAnchor(anchor)
	local off = offset or {}
	fs:ClearAllPoints()
	fs:SetPoint(point, parent, relPoint, roundToPixel(off.x or 0, scale), roundToPixel(off.y or 0, scale))
	if justify and fs.SetJustifyH then fs:SetJustifyH(justify) end
end

local function stopDispelGlow(frame)
	if not (LCG and frame) then return end
	if LCG.PixelGlow_Stop then LCG.PixelGlow_Stop(frame, DISPEL_GLOW_KEY) end
	if LCG.AutoCastGlow_Stop then LCG.AutoCastGlow_Stop(frame, DISPEL_GLOW_KEY) end
	if LCG.ProcGlow_Stop then LCG.ProcGlow_Stop(frame, DISPEL_GLOW_KEY) end
	if LCG.ButtonGlow_Stop then LCG.ButtonGlow_Stop(frame) end
end
local function stopDispelGlowIfActive(st, frame)
	if not (st and st._dispelGlowActive) then return end
	st._dispelGlowActive = nil
	stopDispelGlow(frame)
end

local function resolveDispelIndicatorEnabled(cfg, kind)
	local sc = cfg and cfg.status or {}
	local dt = sc.dispelTint or {}
	local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
	local overlay = dt.enabled
	if overlay == nil then overlay = def.enabled ~= false end
	local glow = dt.glowEnabled
	if glow == nil then glow = def.glowEnabled == true end
	return overlay == true or glow == true
end

local function setTextSlot(st, fs, cacheKey, mode, cur, maxv, useShort, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText, missingValue)
	if not (st and fs) then return end
	if fs.SetAlpha then
		if mode == "DEFICIT" then
			local alpha = missingValue
			if issecretvalue and issecretvalue(alpha) then
				fs:SetAlpha(alpha)
			else
				if alpha == nil then alpha = 0 end
				if type(alpha) ~= "number" then alpha = tonumber(alpha) or 0 end
				fs:SetAlpha(alpha)
			end
		else
			fs:SetAlpha(1)
		end
	end
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
		text = UFHelper.formatText(mode, cur, maxv, useShort, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText, missingValue)
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

local isEditModeActive

local function shouldShowPowerForUnit(pcfg, unit, st)
	if not pcfg then return true end
	local roleMode = GFH.SelectionMode(pcfg.showRoles)
	local specMode = GFH.SelectionMode(pcfg.showSpecs)

	if roleMode == "some" then
		local roleKey = getUnitRoleKey(unit)
		if st and st._previewRole and isEditModeActive() then roleKey = st._previewRole end
		return GFH.SelectionContains(pcfg.showRoles, roleKey)
	end

	if roleMode == "none" then
		if specMode ~= "some" then return false end
		local specId = getPlayerSpecId()
		if not specId then return true end
		return GFH.SelectionContains(pcfg.showSpecs, specId)
	end

	if specMode == "some" then
		local specId = getPlayerSpecId()
		if not specId then return true end
		return GFH.SelectionContains(pcfg.showSpecs, specId)
	end
	if specMode == "none" then return false end
	return true
end

local function canShowPowerBySelection(pcfg)
	if not pcfg then return true end
	local roleMode = GFH.SelectionMode(pcfg.showRoles)
	local specMode = GFH.SelectionMode(pcfg.showSpecs)
	if roleMode == "some" then return true end
	if roleMode == "none" then return specMode == "some" end

	if specMode == "none" then return false end
	return true
end

isEditModeActive = function()
	local lib = addon.EditModeLib
	return lib and lib.IsInEditMode and lib:IsInEditMode()
end

local DEFAULTS = {
	party = {
		enabled = false,
		showPlayer = true,
		showSolo = false,
		hideInClientScene = true,
		tooltip = {
			mode = "OFF",
			modifier = "ALT",
		},
		width = 180,
		height = 100,
		powerHeight = 6,
		spacing = 1,
		point = "TOPLEFT",
		relativePoint = "TOPLEFT",
		relativeTo = "UIParent",
		x = 500,
		y = -300,
		customSort = {
			enabled = false,
			separateMeleeRanged = false,
			roleOrder = GFH.ROLE_TOKENS or { "TANK", "HEALER", "DAMAGER" },
			classOrder = GFH.CLASS_TOKENS,
		},
		sortMethod = "INDEX",
		sortDir = "ASC",
		growth = "RIGHT",
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
			nameNoEllipsis = false,
			showHealthPercent = true,
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
				size = 12,
				point = "TOPLEFT",
				relativePoint = "TOPLEFT",
				x = 18,
				y = -2,
			},
			readyCheckIcon = {
				enabled = true,
				sample = false,
				size = 16,
				point = "CENTER",
				relativePoint = "CENTER",
				x = 0,
				y = 0,
			},
			summonIcon = {
				enabled = true,
				sample = false,
				size = 16,
				point = "CENTER",
				relativePoint = "CENTER",
				x = 0,
				y = 0,
			},
			resurrectIcon = {
				enabled = true,
				sample = false,
				size = 16,
				point = "CENTER",
				relativePoint = "CENTER",
				x = 0,
				y = 0,
			},
			phaseIcon = {
				enabled = false,
				sample = false,
				size = 14,
				point = "TOPLEFT",
				relativePoint = "TOPLEFT",
				x = 0,
				y = 0,
			},
			unitStatus = {
				enabled = true,
				font = nil,
				fontSize = 12,
				fontOutline = "OUTLINE",
				color = { 1, 1, 1, 1 },
				anchor = "CENTER",
				offset = { x = 0, y = 0 },
				showOffline = true,
				showAFK = false,
				showDND = false,
				hideHealthTextWhenOffline = false,
				showGroup = false,
				groupFormat = "GROUP",
			},
			groupNumber = {
				enabled = false,
				format = "GROUP",
				font = nil,
				fontSize = 12,
				fontOutline = "OUTLINE",
				color = { 1, 1, 1, 1 },
				anchor = "CENTER",
				offset = { x = 0, y = 0 },
			},
			rangeFade = {
				enabled = true,
				alpha = 0.55,
				offlineAlpha = 0.4,
			},
			dispelTint = {
				enabled = true,
				alpha = 0.25,
				showSample = false,
				fillEnabled = true,
				fillAlpha = 0.2,
				fillColor = { 0, 0, 0, 1 },
				glowEnabled = false,
				glowColorMode = "DISPEL",
				glowColor = { 1, 1, 1, 1 },
				glowEffect = "PIXEL",
				glowFrequency = 0.25,
				glowX = 0,
				glowY = 0,
				glowLines = 8,
				glowThickness = 3,
			},
		},
		groupIndicator = {
			enabled = false,
			hidePerFrame = false,
			format = "GROUP",
			font = nil,
			fontSize = 12,
			fontOutline = "OUTLINE",
			color = { 1, 1, 1, 1 },
			anchor = "TOPLEFT",
			offset = { x = 0, y = 0 },
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
		privateAuras = {
			enabled = false,
			countdownFrame = true,
			countdownNumbers = false,
			showDispelType = false,
			icon = {
				amount = 2,
				size = 20,
				point = "LEFT",
				offset = 2,
				borderScale = nil,
			},
			parent = {
				point = "CENTER",
				offsetX = 0,
				offsetY = 0,
			},
			duration = {
				enable = false,
				point = "BOTTOM",
				offsetX = 0,
				offsetY = -1,
			},
		},
		auras = {
			enabled = false,
			buff = {
				enabled = false,
				size = 26,
				perRow = 3,
				max = 6,
				spacing = 0,
				anchorPoint = "TOPLEFT",
				growth = "DOWNRIGHT",
				growthX = "RIGHT",
				growthY = "DOWN",
				x = 0,
				y = 0,
				showTooltip = false,
				showCooldown = true,
				showCooldownText = false,
				cooldownAnchor = "CENTER",
				cooldownOffset = { x = 0, y = 0 },
				textFont = "Friz Quadrata TT",
				textOutline = "OUTLINE",
				cooldownFont = nil,
				cooldownFontSize = 8,
				cooldownFontOutline = "OUTLINE",
				showStacks = true,
				countAnchor = "BOTTOMRIGHT",
				countOffset = { x = 4, y = 2 },
				countFont = nil,
				countFontSize = 12,
				countFontOutline = "OUTLINE",
			},
			debuff = {
				enabled = false,
				size = 26,
				perRow = 3,
				max = 6,
				spacing = 0,
				anchorPoint = "BOTTOMLEFT",
				growth = "DOWNRIGHT",
				growthX = "RIGHT",
				growthY = "DOWN",
				x = 0,
				y = 0,
				showTooltip = false,
				showCooldown = true,
				showDispelIcon = true,
				showCooldownText = false,
				cooldownAnchor = "CENTER",
				cooldownOffset = { x = 0, y = 0 },
				textFont = "Friz Quadrata TT",
				textOutline = "OUTLINE",
				cooldownFont = nil,
				cooldownFontSize = 8,
				cooldownFontOutline = "OUTLINE",
				showStacks = true,
				countAnchor = "BOTTOMRIGHT",
				countOffset = { x = 4, y = 2 },
				countFont = nil,
				countFontSize = 12,
				countFontOutline = "OUTLINE",
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
				showTooltip = false,
				showCooldown = true,
				showCooldownText = true,
				cooldownAnchor = "CENTER",
				cooldownOffset = { x = 0, y = 0 },
				textFont = "Friz Quadrata TT",
				textOutline = "OUTLINE",
				cooldownFont = nil,
				cooldownFontSize = 12,
				cooldownFontOutline = "OUTLINE",
				showStacks = false,
				countAnchor = "BOTTOMRIGHT",
				countOffset = { x = 4, y = 2 },
				countFont = nil,
				countFontSize = 12,
				countFontOutline = "OUTLINE",
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
		hideInClientScene = true,
		tooltip = {
			mode = "OFF",
			modifier = "ALT",
		},
		width = 100,
		height = 80,
		powerHeight = 4,
		spacing = 0,
		point = "TOPLEFT",
		relativePoint = "TOPLEFT",
		relativeTo = "UIParent",
		x = 500,
		y = -300,
		groupBy = "GROUP",
		groupingOrder = GFH.GROUP_ORDER,
		groupFilter = nil,
		customSort = {
			enabled = false,
			separateMeleeRanged = false,
			roleOrder = GFH.ROLE_TOKENS or { "TANK", "HEALER", "DAMAGER" },
			classOrder = GFH.CLASS_TOKENS,
		},
		sortMethod = "INDEX",
		sortDir = "ASC",
		unitsPerColumn = 5,
		maxColumns = 4,
		growth = "RIGHT",
		groupGrowth = "DOWN",
		barTexture = "SOLID",
		columnSpacing = 8,
		border = {
			enabled = true,
			texture = "SOLID",
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
			absorbUseCustomColor = true,
			showSampleAbsorb = false,
			absorbColor = { 1.0, 0.8196, 0.1490, 1.0 },
			absorbTexture = "EQOL: Absorb",
			absorbReverseFill = false,
			healAbsorbEnabled = true,
			healAbsorbUseCustomColor = false,
			showSampleHealAbsorb = false,
			healAbsorbColor = { 1.0, 0.3, 0.3, 0.7 },
			healAbsorbTexture = "SOLID",
			healAbsorbReverseFill = true,
			textLeft = "NONE",
			textCenter = "PERCENT",
			textRight = "NONE",
			textColor = { 1, 1, 1, 1 },
			textDelimiter = " ",
			textDelimiterSecondary = " ",
			textDelimiterTertiary = " ",
			useShortNumbers = true,
			hidePercentSymbol = false,
			offsetLeft = { x = 5, y = 0 },
			offsetCenter = { x = 0, y = 20 },
			offsetRight = { x = 0, y = 0 },
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
			nameAnchor = "CENTER",
			nameMaxChars = 15,
			nameNoEllipsis = true,
			showHealthPercent = false,
			showPowerPercent = false,
			useClassColor = true,
			font = nil,
			fontSize = 15,
			fontOutline = "OUTLINE",
			nameOffset = { x = 0, y = 0 },
		},
		status = {
			nameColorMode = "CLASS",
			nameColor = { 1, 1, 1, 1 },
			levelEnabled = false,
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
				size = 18,
				point = "TOPRIGHT",
				relativePoint = "TOPRIGHT",
				x = 6,
				y = 10,
			},
			assistIcon = {
				enabled = false,
				size = 10,
				point = "TOPLEFT",
				relativePoint = "TOPLEFT",
				x = 14,
				y = -1,
			},
			readyCheckIcon = {
				enabled = true,
				sample = false,
				size = 16,
				point = "CENTER",
				relativePoint = "CENTER",
				x = 0,
				y = 0,
			},
			summonIcon = {
				enabled = true,
				sample = false,
				size = 16,
				point = "CENTER",
				relativePoint = "CENTER",
				x = 0,
				y = 0,
			},
			resurrectIcon = {
				enabled = true,
				sample = false,
				size = 16,
				point = "CENTER",
				relativePoint = "CENTER",
				x = 0,
				y = 0,
			},
			phaseIcon = {
				enabled = false,
				sample = false,
				size = 14,
				point = "TOPLEFT",
				relativePoint = "TOPLEFT",
				x = 0,
				y = 0,
			},
			unitStatus = {
				enabled = true,
				font = nil,
				fontSize = 12,
				fontOutline = "OUTLINE",
				color = { 1, 1, 1, 1 },
				anchor = "CENTER",
				offset = { x = 0, y = 0 },
				showOffline = true,
				showAFK = false,
				showDND = false,
				hideHealthTextWhenOffline = false,
				showGroup = false,
				groupFormat = "GROUP",
			},
			groupNumber = {
				enabled = false,
				format = "GROUP",
				font = nil,
				fontSize = 12,
				fontOutline = "OUTLINE",
				color = { 1, 1, 1, 1 },
				anchor = "CENTER",
				offset = { x = 0, y = 0 },
			},
			rangeFade = {
				enabled = true,
				alpha = 0.55,
				offlineAlpha = 0.4,
			},
			dispelTint = {
				enabled = true,
				alpha = 0.25,
				showSample = false,
				fillEnabled = true,
				fillAlpha = 0.2,
				fillColor = { 0, 0, 0, 1 },
				glowEnabled = false,
				glowColorMode = "DISPEL",
				glowColor = { 1, 1, 1, 1 },
				glowEffect = "PIXEL",
				glowFrequency = 0.25,
				glowX = 0,
				glowY = 0,
				glowLines = 8,
				glowThickness = 3,
			},
		},
		roleIcon = {
			enabled = false,
			size = 16,
			point = "TOPLEFT",
			relativePoint = "TOPLEFT",
			x = 2,
			y = -2,
			spacing = 2,
			style = "TINY",
			showRoles = { TANK = true, HEALER = true, DAMAGER = false },
		},
		privateAuras = {
			enabled = false,
			countdownFrame = true,
			countdownNumbers = false,
			showDispelType = false,
			icon = {
				amount = 2,
				size = 18,
				point = "LEFT",
				offset = 2,
				borderScale = nil,
			},
			parent = {
				point = "CENTER",
				offsetX = 0,
				offsetY = 0,
			},
			duration = {
				enable = false,
				point = "BOTTOM",
				offsetX = 0,
				offsetY = -1,
			},
		},
		auras = {
			enabled = false,
			buff = {
				enabled = false,
				size = 20,
				perRow = 5,
				max = 5,
				spacing = 0,
				anchorPoint = "TOPLEFT",
				growth = "RIGHTDOWN",
				growthX = "RIGHT",
				growthY = "DOWN",
				x = 0,
				y = 0,
				showTooltip = false,
				showCooldown = true,
				showDispelIcon = true,
				showCooldownText = false,
				cooldownAnchor = "CENTER",
				cooldownOffset = { x = 0, y = 0 },
				textFont = "Friz Quadrata TT",
				textOutline = "OUTLINE",
				cooldownFont = nil,
				cooldownFontSize = 8,
				cooldownFontOutline = "OUTLINE",
				showStacks = true,
				countAnchor = "CENTER",
				countOffset = { x = 0, y = 0 },
				countFont = nil,
				countFontSize = 12,
				countFontOutline = "OUTLINE",
			},
			debuff = {
				enabled = false,
				size = 26,
				perRow = 3,
				max = 6,
				spacing = 0,
				anchorPoint = "BOTTOMLEFT",
				growth = "DOWNRIGHT",
				growthX = "RIGHT",
				growthY = "DOWN",
				x = 0,
				y = 0,
				showTooltip = false,
				showCooldown = true,
				showCooldownText = false,
				cooldownAnchor = "CENTER",
				cooldownOffset = { x = 0, y = 0 },
				textFont = "Friz Quadrata TT",
				textOutline = "OUTLINE",
				cooldownFont = nil,
				cooldownFontSize = 8,
				cooldownFontOutline = "OUTLINE",
				showStacks = true,
				countAnchor = "BOTTOMRIGHT",
				countOffset = { x = 4, y = 2 },
				countFont = nil,
				countFontSize = 12,
				countFontOutline = "OUTLINE",
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
				showTooltip = false,
				showCooldown = true,
				showCooldownText = true,
				cooldownAnchor = "CENTER",
				cooldownOffset = { x = 0, y = 0 },
				textFont = "Friz Quadrata TT",
				textOutline = "OUTLINE",
				cooldownFont = nil,
				cooldownFontSize = 12,
				cooldownFontOutline = "OUTLINE",
				showStacks = false,
				countAnchor = "BOTTOMRIGHT",
				countOffset = { x = 4, y = 2 },
				countFont = nil,
				countFontSize = 12,
				countFontOutline = "OUTLINE",
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

local function copyDefaultsTable(src)
	if type(src) ~= "table" then return src end
	if addon.functions and addon.functions.copyTable then return addon.functions.copyTable(src) end
	if CopyTable then return CopyTable(src) end
	local out = {}
	for k, v in pairs(src) do
		if type(v) == "table" then
			out[k] = copyDefaultsTable(v)
		else
			out[k] = v
		end
	end
	return out
end

do
	local mtDefaults = copyDefaultsTable(DEFAULTS.raid)
	mtDefaults.enabled = false
	mtDefaults.sortMethod = "NAME"
	mtDefaults.sortDir = "ASC"
	mtDefaults.groupBy = nil
	mtDefaults.groupingOrder = nil
	mtDefaults.groupFilter = nil
	mtDefaults.unitsPerColumn = 2
	mtDefaults.maxColumns = 1
	mtDefaults.growth = "DOWN"
	mtDefaults.point = "TOPLEFT"
	mtDefaults.relativePoint = "TOPLEFT"
	mtDefaults.relativeTo = "UIParent"
	mtDefaults.x = 500
	mtDefaults.y = -120
	DEFAULTS.mt = mtDefaults

	local maDefaults = copyDefaultsTable(DEFAULTS.raid)
	maDefaults.enabled = false
	maDefaults.sortMethod = "NAME"
	maDefaults.sortDir = "ASC"
	maDefaults.groupBy = nil
	maDefaults.groupingOrder = nil
	maDefaults.groupFilter = nil
	maDefaults.unitsPerColumn = 2
	maDefaults.maxColumns = 1
	maDefaults.growth = "DOWN"
	maDefaults.point = "TOPLEFT"
	maDefaults.relativePoint = "TOPLEFT"
	maDefaults.relativeTo = "UIParent"
	maDefaults.x = 700
	maDefaults.y = -120
	DEFAULTS.ma = maDefaults
end

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
	-- Always merge defaults so newly introduced kinds/fields are backfilled
	-- for existing profiles that already have _eqolInited = true.
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
		if kind == "party" then
			-- Legacy party defaults grouped by role; clear persisted values so INDEX uses party unit index order.
			t.groupBy = nil
			t.groupingOrder = nil
		end
	end
	db._eqolInited = true
	DB = db
	return db
end

getCfg = function(kind)
	local db = DB or ensureDB()
	if db[kind] == nil then
		local def = DEFAULTS[kind]
		if type(def) == "table" then
			if addon.functions and addon.functions.copyTable then
				db[kind] = addon.functions.copyTable(def)
			else
				db[kind] = CopyTable(def)
			end
		else
			return def
		end
	end
	return db[kind]
end

local function isFeatureEnabled()
	local db = DB or ensureDB()
	local partyEnabled = db and db.party and db.party.enabled == true
	local raidEnabled = db and db.raid and db.raid.enabled == true
	return partyEnabled or raidEnabled
end

local hiddenParent
local function getHiddenParent()
	if hiddenParent then return hiddenParent end
	hiddenParent = CreateFrame("Frame")
	hiddenParent:Hide()
	return hiddenParent
end

local function hideFrameLocked(frame)
	if not frame or frame._eqolHidden then return end

	local function enforceHidden(target)
		if not target then return end
		local canHide = true
		if InCombatLockdown and InCombatLockdown() then
			if target.IsProtected and target:IsProtected() then canHide = false end
		end
		if canHide then
			if target.Hide then pcall(target.Hide, target) end
		elseif target.SetAlpha then
			target:SetAlpha(0)
			target._eqolAlphaHidden = true
		end
	end

	if frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
	enforceHidden(frame)
	frame._eqolHidden = true
	if frame.SetParent then pcall(frame.SetParent, frame, getHiddenParent()) end
	if not frame._eqolHiddenHooks then
		frame._eqolHiddenHooks = true
		if frame.Show then hooksecurefunc(frame, "Show", function(f) enforceHidden(f) end) end
		if frame.SetShown then hooksecurefunc(frame, "SetShown", function(f, shown)
			if shown then enforceHidden(f) end
		end) end
	end
end

function GF:DisableBlizzardFrames()
	local db = DB or ensureDB()
	local wantParty = db and db.party and db.party.enabled == true
	local wantRaid = db and db.raid and db.raid.enabled == true
	if InCombatLockdown and InCombatLockdown() then
		GF._pendingBlizzardDisable = { party = wantParty, raid = wantRaid }
		return
	end
	local pending = GF._pendingBlizzardDisable or {}
	GF._pendingBlizzardDisable = nil
	if wantParty or pending.party then
		hideFrameLocked(_G.PartyFrame)
		hideFrameLocked(_G.CompactPartyFrame)
		hideFrameLocked(_G.CompactPartyFrameTitle)
	end
	if wantRaid or pending.raid then
		hideFrameLocked(_G.CompactRaidFrameContainer)
		hideFrameLocked(_G.CompactRaidFrameManager)
		if CompactRaidFrameManager_SetSetting then pcall(CompactRaidFrameManager_SetSetting, "IsShown", "0") end
	end
end

function GF:GetConfig(kind) return getCfg(kind) end

function GF:IsFeatureEnabled() return isFeatureEnabled() end

function GF:EnsureDB() return ensureDB() end

GF.headers = GF.headers or {}
GF.anchors = GF.anchors or {}
GF._pendingRefresh = GF._pendingRefresh or false
GF._pendingHeaderKinds = GF._pendingHeaderKinds or {}
GF._pendingDisable = GF._pendingDisable or false
GF._clientSceneActive = GF._clientSceneActive or false

local registerFeatureEvents
local unregisterFeatureEvents

function GF:MarkPendingHeaderRefresh(kind)
	GF._pendingRefresh = true
	GF._pendingHeaderKinds = GF._pendingHeaderKinds or {}
	if kind then GF._pendingHeaderKinds[kind] = true end
end

function GF:SetHeaderAttributeIfChanged(header, key, value)
	if not (header and header.SetAttribute) then return false end
	local cache = header._eqolAttrCache
	if not cache then
		cache = {}
		header._eqolAttrCache = cache
	end
	local normalized = value
	if normalized == nil then
		GF._eqolAttrNilToken = GF._eqolAttrNilToken or {}
		normalized = GF._eqolAttrNilToken
	end
	if cache[key] == normalized then return false end
	header:SetAttribute(key, value)
	cache[key] = normalized
	return true
end

function GF:ApplyPendingHeaderKinds()
	local pending = GF._pendingHeaderKinds
	if not pending then return false end
	GF._pendingHeaderKinds = {}
	local applied = false

	if pending.party then
		GF:ApplyHeaderAttributes("party")
		applied = true
	end
	if pending.raid then
		GF:ApplyHeaderAttributes("raid")
		applied = true
	end
	if pending.mt then
		GF:ApplyHeaderAttributes("mt")
		applied = true
	end
	if pending.ma then
		GF:ApplyHeaderAttributes("ma")
		applied = true
	end

	for kind in pairs(pending) do
		if kind ~= "party" and kind ~= "raid" and kind ~= "mt" and kind ~= "ma" then
			GF:ApplyHeaderAttributes(kind)
			applied = true
		end
	end

	return applied
end

local function getUnit(self) return (self and (self.unit or (self.GetAttribute and self:GetAttribute("unit")))) end

local function getState(self)
	local st = self and self._eqolUFState
	if not st then
		st = { frame = self }
		self._eqolUFState = st
	end
	return st
end

local function isTooltipModifierPressed(modifier)
	local mod = tostring(modifier or "ALT"):upper()
	if mod == "SHIFT" then return IsShiftKeyDown and IsShiftKeyDown() end
	if mod == "CTRL" or mod == "CONTROL" then return IsControlKeyDown and IsControlKeyDown() end
	return IsAltKeyDown and IsAltKeyDown()
end

local function shouldShowTooltip(self)
	local st = self and self._eqolUFState or nil
	local mode = st and st._tooltipMode or nil
	local modifier = st and st._tooltipModifier or nil

	if not mode then
		local kind = (self and self._eqolGroupKind) or "party"
		local cfg = (self and (self._eqolCfg or getCfg(kind))) or getCfg(kind)
		local tc = cfg and cfg.tooltip or nil
		local def = (DEFAULTS[kind] and DEFAULTS[kind].tooltip) or (DEFAULTS.party and DEFAULTS.party.tooltip) or nil
		mode = tostring((tc and tc.mode) or (def and def.mode) or "OFF"):upper()
		modifier = tostring((tc and tc.modifier) or (def and def.modifier) or "ALT"):upper()
	else
		mode = tostring(mode):upper()
		modifier = tostring(modifier or "ALT"):upper()
	end

	if mode == "OFF" then return false end
	if mode == "ALWAYS" then return true end
	if mode == "OUT_OF_COMBAT" or mode == "OOC" then return not (InCombatLockdown and InCombatLockdown()) end
	if mode == "MODIFIER" then return isTooltipModifierPressed(modifier) end
	return false
end

function GF:UpdateAbsorbCache(self, which, unit, st)
	unit = unit or getUnit(self)
	st = st or getState(self)
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
	st._wantsStatusText = scfg and scfg.unitStatus and scfg.unitStatus.enabled ~= false
	st._wantsRangeFade = scfg and scfg.rangeFade and scfg.rangeFade.enabled ~= false
	st._wantsDispelTint = resolveDispelIndicatorEnabled(cfg, self._eqolGroupKind or "party")

	local tooltipCfg = cfg.tooltip or {}
	local tooltipDef = (DEFAULTS[self._eqolGroupKind or "party"] and DEFAULTS[self._eqolGroupKind or "party"].tooltip) or (DEFAULTS.party and DEFAULTS.party.tooltip) or {}
	local tooltipMode = tostring(tooltipCfg.mode or tooltipDef.mode or "OFF"):upper()
	if tooltipMode == "OOC" then tooltipMode = "OUT_OF_COMBAT" end
	st._tooltipMode = tooltipMode
	st._tooltipModifier = tostring(tooltipCfg.modifier or tooltipDef.modifier or "ALT"):upper()

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
	if issecretvalue and issecretvalue(guid) then guid = nil end

	local cachedGuid = st._guid
	if issecretvalue and issecretvalue(cachedGuid) then
		cachedGuid = nil
		st._guid = nil
	end

	if cachedGuid == guid and st._unitToken == unit then
		if st._class and not (self._eqolPreview and isEditModeActive()) then return end
	end
	st._guid = guid
	st._unitToken = unit

	local class = getUnitClassToken(unit)
	if isEditModeActive() and self._eqolPreview and st._previewClass then class = st._previewClass end
	st._class = class
	if class then
		st._classR, st._classG, st._classB, st._classA = getClassColor(class)
	else
		st._classR, st._classG, st._classB, st._classA = nil, nil, nil, nil
	end
end

function GF:EnsureUnitClassColor(frame, st, unit)
	st = st or getState(frame)
	if not st then return false end
	if st._classR then return true end

	unit = unit or getUnit(frame)
	if not unit then return false end

	local class = st._class
	if isEditModeActive() and frame and frame._eqolPreview and st._previewClass then class = st._previewClass end
	if not class then class = getUnitClassToken(unit) end
	if not class then return false end

	st._class = class
	local r, g, b, a = getClassColor(class)
	if not r then return false end
	st._classR, st._classG, st._classB, st._classA = r, g, b, a or 1
	return true
end

function GF:NeedsClassColor(frame, st, cfg)
	if not frame then return false end
	cfg = cfg or frame._eqolCfg or getCfg(frame._eqolGroupKind or "party")
	local hc = cfg and cfg.health or {}
	local tc = cfg and cfg.text or {}
	local sc = cfg and cfg.status or {}

	if hc.useClassColor == true then return true end

	local nameMode = sc.nameColorMode
	if nameMode == nil then nameMode = (tc.useClassColor ~= false) and "CLASS" or "CUSTOM" end
	if (st == nil or st._wantsName ~= false) and nameMode == "CLASS" then return true end

	if (st == nil or st._wantsLevel ~= false) and sc.levelColorMode == "CLASS" then return true end

	return false
end

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

	if self.RegisterForClicks then self:RegisterForClicks("AnyUp") end

	_G.ClickCastFrames = _G.ClickCastFrames or {}
	_G.ClickCastFrames[self] = true

	if not st.barGroup then
		st.barGroup = CreateFrame("Frame", nil, self, "BackdropTemplate")
		st.barGroup:EnableMouse(false)
	end
	st.barGroup:SetAllPoints(self)

	setBackdrop(st.barGroup, cfg.border)
	if not st.dispelTint then
		st.dispelTint = CreateFrame("Frame", nil, st.barGroup, "CompactUnitFrameDispelOverlayTemplate")
		st.dispelTint:SetAllPoints(st.barGroup)
		st.dispelTint:Hide()

		if st.dispelTint.SetDispelType then st.dispelTint.SetDispelType = nil end
	end

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

	if not st.healthTextLayer then
		st.healthTextLayer = CreateFrame("Frame", nil, st.health)
		st.healthTextLayer:SetAllPoints(st.health)
	end
	if not st.powerTextLayer then
		st.powerTextLayer = CreateFrame("Frame", nil, st.power)
		st.powerTextLayer:SetAllPoints(st.power)
	end
	if not st.statusIconLayer then
		st.statusIconLayer = CreateFrame("Frame", nil, st.barGroup)
		st.statusIconLayer:SetAllPoints(st.barGroup)
		st.statusIconLayer:EnableMouse(false)
	end
	if st.statusIconLayer.GetParent and st.statusIconLayer:GetParent() ~= st.barGroup then st.statusIconLayer:SetParent(st.barGroup) end
	if st.dispelTint then
		if st.dispelTint.GetParent and st.dispelTint:GetParent() ~= st.healthTextLayer then st.dispelTint:SetParent(st.healthTextLayer) end
		if st.dispelTint.SetFrameLevel and st.healthTextLayer then
			local lvl = st.healthTextLayer:GetFrameLevel() or 0
			st.dispelTint:SetFrameLevel(lvl)
		end
		st.dispelTint:SetAllPoints(st.barGroup)
	end

	if not st.healthTextLeft then st.healthTextLeft = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	if not st.healthTextCenter then st.healthTextCenter = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	if not st.healthTextRight then st.healthTextRight = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	if not st.powerTextLeft then st.powerTextLeft = st.powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	if not st.powerTextCenter then st.powerTextCenter = st.powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	if not st.powerTextRight then st.powerTextRight = st.powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end

	if not st.nameText then st.nameText = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	st.name = st.nameText
	if not st.levelText then st.levelText = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	if not st.statusText then st.statusText = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	if not st.groupNumberText then st.groupNumberText = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	if not st.privateAuras then
		st.privateAuras = CreateFrame("Frame", nil, st.health or st.barGroup or self)
		st.privateAuras:EnableMouse(false)
	end
	local privateAuraParent = st.health or st.barGroup or self
	if st.privateAuras.GetParent and privateAuraParent and st.privateAuras:GetParent() ~= privateAuraParent then st.privateAuras:SetParent(privateAuraParent) end

	local indicatorLayer = st.statusIconLayer or st.healthTextLayer
	if not st.leaderIcon then st.leaderIcon = indicatorLayer:CreateTexture(nil, "OVERLAY", nil, 7) end
	if not st.assistIcon then st.assistIcon = indicatorLayer:CreateTexture(nil, "OVERLAY", nil, 7) end
	if not st.raidIcon then
		st.raidIcon = indicatorLayer:CreateTexture(nil, "OVERLAY", nil, 7)
		st.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
		st.raidIcon:SetSize(18, 18)
		st.raidIcon:Hide()
	end
	if not st.readyCheckIcon then
		st.readyCheckIcon = indicatorLayer:CreateTexture(nil, "OVERLAY", nil, 7)
		st.readyCheckIcon:SetTexture(GFH.STATUS_ICON_CONST.waiting)
		st.readyCheckIcon:SetSize(16, 16)
		st.readyCheckIcon:Hide()
	end
	if not st.summonIcon then
		st.summonIcon = indicatorLayer:CreateTexture(nil, "OVERLAY", nil, 7)
		st.summonIcon:SetSize(16, 16)
		st.summonIcon:Hide()
	end
	if not st.resurrectIcon then
		st.resurrectIcon = indicatorLayer:CreateTexture(nil, "OVERLAY", nil, 7)
		st.resurrectIcon:SetTexture(GFH.STATUS_ICON_CONST.resurrect)
		st.resurrectIcon:SetSize(16, 16)
		st.resurrectIcon:Hide()
	end
	if not st.phaseIcon then
		st.phaseIcon = indicatorLayer:CreateTexture(nil, "OVERLAY", nil, 7)
		st.phaseIcon:SetTexture(GFH.STATUS_ICON_CONST.phase)
		st.phaseIcon:SetSize(14, 14)
		st.phaseIcon:Hide()
	end
	if st.leaderIcon.GetParent and st.leaderIcon:GetParent() ~= indicatorLayer then st.leaderIcon:SetParent(indicatorLayer) end
	if st.assistIcon.GetParent and st.assistIcon:GetParent() ~= indicatorLayer then st.assistIcon:SetParent(indicatorLayer) end
	if st.raidIcon.GetParent and st.raidIcon:GetParent() ~= indicatorLayer then st.raidIcon:SetParent(indicatorLayer) end
	if st.readyCheckIcon.GetParent and st.readyCheckIcon:GetParent() ~= indicatorLayer then st.readyCheckIcon:SetParent(indicatorLayer) end
	if st.summonIcon.GetParent and st.summonIcon:GetParent() ~= indicatorLayer then st.summonIcon:SetParent(indicatorLayer) end
	if st.resurrectIcon.GetParent and st.resurrectIcon:GetParent() ~= indicatorLayer then st.resurrectIcon:SetParent(indicatorLayer) end
	if st.phaseIcon.GetParent and st.phaseIcon:GetParent() ~= indicatorLayer then st.phaseIcon:SetParent(indicatorLayer) end
	if st.leaderIcon.SetDrawLayer then st.leaderIcon:SetDrawLayer("OVERLAY", 7) end
	if st.assistIcon.SetDrawLayer then st.assistIcon:SetDrawLayer("OVERLAY", 7) end
	if st.raidIcon.SetDrawLayer then st.raidIcon:SetDrawLayer("OVERLAY", 7) end
	if st.readyCheckIcon.SetDrawLayer then st.readyCheckIcon:SetDrawLayer("OVERLAY", 7) end
	if st.summonIcon.SetDrawLayer then st.summonIcon:SetDrawLayer("OVERLAY", 7) end
	if st.resurrectIcon.SetDrawLayer then st.resurrectIcon:SetDrawLayer("OVERLAY", 7) end
	if st.phaseIcon.SetDrawLayer then st.phaseIcon:SetDrawLayer("OVERLAY", 7) end

	if UFHelper and UFHelper.applyFont then
		UFHelper.applyFont(st.healthTextLeft, hc.font, hc.fontSize or 12, hc.fontOutline)
		UFHelper.applyFont(st.healthTextCenter, hc.font, hc.fontSize or 12, hc.fontOutline)
		UFHelper.applyFont(st.healthTextRight, hc.font, hc.fontSize or 12, hc.fontOutline)
		UFHelper.applyFont(st.powerTextLeft, pcfg.font, pcfg.fontSize or 10, pcfg.fontOutline)
		UFHelper.applyFont(st.powerTextCenter, pcfg.font, pcfg.fontSize or 10, pcfg.fontOutline)
		UFHelper.applyFont(st.powerTextRight, pcfg.font, pcfg.fontSize or 10, pcfg.fontOutline)
		UFHelper.applyFont(st.nameText, tc.font or hc.font, tc.fontSize or hc.fontSize or 12, tc.fontOutline or hc.fontOutline)
	end

	if not st._sizeHooked then
		st._sizeHooked = true
		self:HookScript("OnSizeChanged", function(btn) GF:LayoutButton(btn) end)
	end

	self:SetClampedToScreen(true)
	self:SetScript("OnMouseDown", nil)

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

	local kind = self._eqolGroupKind
	local cfg = self._eqolCfg or getCfg(kind or "party")
	local def = DEFAULTS[kind] or {}
	local hc = cfg.health or {}
	local defH = def.health or {}

	local scale = GFH.GetEffectiveScale(self)
	if not scale or scale <= 0 then scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1 end

	local powerH = tonumber(cfg.powerHeight)
	if powerH == nil then powerH = tonumber(def.powerHeight) or 6 end
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
	borderOffset = roundToPixel(borderOffset, scale)

	local availH = h - borderOffset * 2
	if availH < 1 then availH = 1 end
	if powerH > availH - 4 then powerH = math.max(0, availH * 0.25) end
	powerH = roundToEvenPixel(max(0, powerH), scale)
	if powerH > availH then powerH = availH end

	local negBorderOffset = roundToPixel(-borderOffset, scale)
	local healthBottomOffset = roundToPixel(powerH + borderOffset, scale)

	st.barGroup:SetAllPoints(self)
	setBackdrop(st.barGroup, cfg.border)

	st._highlightHoverCfg = buildHighlightConfig(cfg, def, "highlightHover")
	st._highlightTargetCfg = buildHighlightConfig(cfg, def, "highlightTarget")
	applyHighlightStyle(st, st._highlightHoverCfg, "hover")
	applyHighlightStyle(st, st._highlightTargetCfg, "target")

	st.power:ClearAllPoints()
	st.power:SetPoint("BOTTOMLEFT", st.barGroup, "BOTTOMLEFT", borderOffset, borderOffset)
	st.power:SetPoint("BOTTOMRIGHT", st.barGroup, "BOTTOMRIGHT", negBorderOffset, borderOffset)
	st.power:SetHeight(powerH)

	st.health:ClearAllPoints()
	st.health:SetPoint("TOPLEFT", st.barGroup, "TOPLEFT", borderOffset, negBorderOffset)
	st.health:SetPoint("BOTTOMRIGHT", st.barGroup, "BOTTOMRIGHT", negBorderOffset, healthBottomOffset)
	applyBarBackdrop(st.health, hc)
	applyBarBackdrop(st.power, cfg.power or {})

	self.powerBarUsedHeight = powerH > 0 and powerH or 0
	if st.dispelTint and st.dispelTint.SetOrientation and DispelOverlayOrientation then st.dispelTint:SetOrientation(self, DispelOverlayOrientation.VerticalTopToBottom, 0, 0) end

	if UFHelper and UFHelper.applyFont then
		UFHelper.applyFont(st.healthTextLeft, hc.font, hc.fontSize or 12, hc.fontOutline)
		UFHelper.applyFont(st.healthTextCenter, hc.font, hc.fontSize or 12, hc.fontOutline)
		UFHelper.applyFont(st.healthTextRight, hc.font, hc.fontSize or 12, hc.fontOutline)
		local pcfgLocal = cfg.power or {}
		UFHelper.applyFont(st.powerTextLeft, pcfgLocal.font, pcfgLocal.fontSize or 10, pcfgLocal.fontOutline)
		UFHelper.applyFont(st.powerTextCenter, pcfgLocal.font, pcfgLocal.fontSize or 10, pcfgLocal.fontOutline)
		UFHelper.applyFont(st.powerTextRight, pcfgLocal.font, pcfgLocal.fontSize or 10, pcfgLocal.fontOutline)
		if st.statusText then
			local scfg = cfg.status or {}
			local us = scfg.unitStatus or {}
			UFHelper.applyFont(st.statusText, us.font or hc.font, us.fontSize or hc.fontSize or 12, us.fontOutline or hc.fontOutline)
		end
		if st.groupNumberText then
			local style = resolveGroupNumberStyle(cfg, def, hc)
			UFHelper.applyFont(st.groupNumberText, style.font, style.fontSize or 12, style.fontOutline)
		end
	end
	layoutTexts(st.health, st.healthTextLeft, st.healthTextCenter, st.healthTextRight, cfg.health, scale)
	layoutTexts(st.power, st.powerTextLeft, st.powerTextCenter, st.powerTextRight, cfg.power, scale)
	if st.statusText then
		local scfg = cfg.status or {}
		local us = scfg.unitStatus or {}
		local defStatus = def.status or {}
		local defUS = defStatus.unitStatus or {}
		applyStatusTextAnchor(st, us.anchor or defUS.anchor or "CENTER", us.offset or defUS.offset or {}, scale, st.barGroup or self)
	end
	if st.groupNumberText then
		local style = resolveGroupNumberStyle(cfg, def, hc)
		applyStatusTextAnchor(st, style.anchor, style.offset, scale, st.barGroup or self, st.groupNumberText)
	end

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

	local tc = cfg.text or {}
	local rc = cfg.roleIcon or {}
	local sc = cfg.status or {}
	local rolePad = 0
	local roleEnabled = rc.enabled ~= false
	if roleEnabled and type(rc.showRoles) == "table" and not GFH.SelectionHasAny(rc.showRoles) then roleEnabled = false end
	if roleEnabled then
		local indicatorLayer = st.statusIconLayer or st.healthTextLayer or st.health
		if not st.roleIcon then st.roleIcon = indicatorLayer:CreateTexture(nil, "OVERLAY", nil, 7) end
		if st.roleIcon.GetParent and st.roleIcon:GetParent() ~= indicatorLayer then st.roleIcon:SetParent(indicatorLayer) end
		if st.roleIcon.SetDrawLayer then st.roleIcon:SetDrawLayer("OVERLAY", 7) end
		local size = rc.size or 14
		local point = rc.point or "LEFT"
		local relPoint = rc.relativePoint or "LEFT"
		local ox = roundToPixel(rc.x or 2, scale)
		local oy = roundToPixel(rc.y or 0, scale)
		st.roleIcon:ClearAllPoints()
		st.roleIcon:SetPoint(point, st.health, relPoint, ox, oy)
		st.roleIcon:SetSize(size, size)
		rolePad = size + (rc.spacing or 2)
	else
		if st.roleIcon then st.roleIcon:Hide() end
	end

	if st.nameText then
		if st.nameText.SetWordWrap then st.nameText:SetWordWrap(false) end
		if st.nameText.SetNonSpaceWrap then st.nameText:SetNonSpaceWrap(false) end
		if st.nameText.SetMaxLines then st.nameText:SetMaxLines(1) end
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
		if GFH and GFH.SnapPointOffsets then
			nameX, nameY = GFH.SnapPointOffsets(st.health, nameAnchor, nameX, nameY, scale)
		else
			nameX, nameY = roundToPixel(nameX, scale), roundToPixel(nameY, scale)
		end
		local nameMaxChars = tonumber(tc.nameMaxChars) or 0
		st.nameText:ClearAllPoints()
		if nameMaxChars <= 0 then
			local vert = "CENTER"
			if nameAnchor and nameAnchor:find("TOP") then
				vert = "TOP"
			elseif nameAnchor and nameAnchor:find("BOTTOM") then
				vert = "BOTTOM"
			end
			local leftPoint = (vert == "CENTER") and "LEFT" or (vert .. "LEFT")
			local rightPoint = (vert == "CENTER") and "RIGHT" or (vert .. "RIGHT")
			local leftX, leftY
			local rightX, rightY
			if GFH and GFH.SnapPointOffsets then
				leftX, leftY = GFH.SnapPointOffsets(st.health, leftPoint, nameX, nameY, scale)
				rightX, rightY = GFH.SnapPointOffsets(st.health, rightPoint, -4, nameY, scale)
			else
				leftX, leftY = roundToPixel(nameX, scale), roundToPixel(nameY, scale)
				rightX, rightY = roundToPixel(-4, scale), roundToPixel(nameY, scale)
			end
			st.nameText:SetPoint(leftPoint, st.health, leftPoint, leftX, leftY)
			st.nameText:SetPoint(rightPoint, st.health, rightPoint, rightX, rightY)
		else
			st.nameText:SetPoint(nameAnchor, st.health, nameAnchor, nameX, nameY)
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
		if st.levelText.SetWordWrap then st.levelText:SetWordWrap(false) end
		if st.levelText.SetNonSpaceWrap then st.levelText:SetNonSpaceWrap(false) end
		if st.levelText.SetMaxLines then st.levelText:SetMaxLines(1) end
		if UFHelper and UFHelper.applyFont then
			local hc = cfg.health or {}
			local levelFont = sc.levelFont or tc.font or hc.font
			local levelFontSize = sc.levelFontSize or tc.fontSize or hc.fontSize or 12
			local levelOutline = sc.levelFontOutline or tc.fontOutline or hc.fontOutline
			UFHelper.applyFont(st.levelText, levelFont, levelFontSize, levelOutline)
		end
		local anchor = sc.levelAnchor or "RIGHT"
		local levelOffset = sc.levelOffset or {}
		if st.levelText.SetWidth then st.levelText:SetWidth(roundToPixel((sc.levelWidth or 26), scale)) end
		local levelX, levelY
		if GFH and GFH.SnapPointOffsets then
			levelX, levelY = GFH.SnapPointOffsets(st.health, anchor, levelOffset.x or 0, levelOffset.y or 0, scale)
		else
			levelX, levelY = roundToPixel(levelOffset.x or 0, scale), roundToPixel(levelOffset.y or 0, scale)
		end
		st.levelText:ClearAllPoints()
		st.levelText:SetPoint(anchor, st.health, anchor, levelX, levelY)
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
		local indicatorLayer = st.statusIconLayer or st.healthTextLayer or st.health
		if st.raidIcon.GetParent and st.raidIcon:GetParent() ~= indicatorLayer then st.raidIcon:SetParent(indicatorLayer) end
		if st.raidIcon.SetDrawLayer then st.raidIcon:SetDrawLayer("OVERLAY", 7) end
		if ric.enabled ~= false then
			local size = ric.size or 18
			st.raidIcon:ClearAllPoints()
			st.raidIcon:SetPoint(ric.point or "TOP", st.barGroup, ric.relativePoint or ric.point or "TOP", roundToPixel(ric.x or 0, scale), roundToPixel(ric.y or -2, scale))
			st.raidIcon:SetSize(size, size)
		else
			st.raidIcon:Hide()
		end
	end

	if st.healthTextLeft or st.healthTextCenter or st.healthTextRight then
		local r, g, b, a = unpackColor(hc.textColor, defH.textColor or GFH.COLOR_WHITE)
		if st._lastHealthTextR ~= r or st._lastHealthTextG ~= g or st._lastHealthTextB ~= b or st._lastHealthTextA ~= a then
			st._lastHealthTextR, st._lastHealthTextG, st._lastHealthTextB, st._lastHealthTextA = r, g, b, a
			if st.healthTextLeft then st.healthTextLeft:SetTextColor(r, g, b, a) end
			if st.healthTextCenter then st.healthTextCenter:SetTextColor(r, g, b, a) end
			if st.healthTextRight then st.healthTextRight:SetTextColor(r, g, b, a) end
		end
	end

	if st.leaderIcon then
		local lc = sc.leaderIcon or {}
		local indicatorLayer = st.statusIconLayer or st.healthTextLayer or st.health
		if st.leaderIcon.GetParent and st.leaderIcon:GetParent() ~= indicatorLayer then st.leaderIcon:SetParent(indicatorLayer) end
		if st.leaderIcon.SetDrawLayer then st.leaderIcon:SetDrawLayer("OVERLAY", 7) end
		if lc.enabled ~= false then
			local size = lc.size or 12
			st.leaderIcon:ClearAllPoints()
			st.leaderIcon:SetPoint(lc.point or "TOPLEFT", st.health, lc.relativePoint or "TOPLEFT", roundToPixel(lc.x or 0, scale), roundToPixel(lc.y or 0, scale))
			st.leaderIcon:SetSize(size, size)
		else
			st.leaderIcon:Hide()
		end
	end

	if st.assistIcon then
		local acfg = sc.assistIcon or {}
		local indicatorLayer = st.statusIconLayer or st.healthTextLayer or st.health
		if st.assistIcon.GetParent and st.assistIcon:GetParent() ~= indicatorLayer then st.assistIcon:SetParent(indicatorLayer) end
		if st.assistIcon.SetDrawLayer then st.assistIcon:SetDrawLayer("OVERLAY", 7) end
		if acfg.enabled ~= false then
			local size = acfg.size or 12
			st.assistIcon:ClearAllPoints()
			st.assistIcon:SetPoint(acfg.point or "TOPLEFT", st.health, acfg.relativePoint or "TOPLEFT", roundToPixel(acfg.x or 0, scale), roundToPixel(acfg.y or 0, scale))
			st.assistIcon:SetSize(size, size)
		else
			st.assistIcon:Hide()
		end
	end

	if st.readyCheckIcon then
		local rcfg = GF:GetStatusIconCfg(self, "readyCheckIcon")
		local indicatorLayer = st.statusIconLayer or st.healthTextLayer or st.health
		if st.readyCheckIcon.GetParent and st.readyCheckIcon:GetParent() ~= indicatorLayer then st.readyCheckIcon:SetParent(indicatorLayer) end
		if st.readyCheckIcon.SetDrawLayer then st.readyCheckIcon:SetDrawLayer("OVERLAY", 7) end
		if rcfg.enabled ~= false then
			local size = rcfg.size or 16
			st.readyCheckIcon:ClearAllPoints()
			st.readyCheckIcon:SetPoint(rcfg.point or "CENTER", st.barGroup, rcfg.relativePoint or rcfg.point or "CENTER", roundToPixel(rcfg.x or 0, scale), roundToPixel(rcfg.y or 0, scale))
			st.readyCheckIcon:SetSize(size, size)
		else
			st.readyCheckIcon:Hide()
		end
	end

	if st.summonIcon then
		local scfg = GF:GetStatusIconCfg(self, "summonIcon")
		local indicatorLayer = st.statusIconLayer or st.healthTextLayer or st.health
		if st.summonIcon.GetParent and st.summonIcon:GetParent() ~= indicatorLayer then st.summonIcon:SetParent(indicatorLayer) end
		if st.summonIcon.SetDrawLayer then st.summonIcon:SetDrawLayer("OVERLAY", 7) end
		if scfg.enabled ~= false then
			local size = scfg.size or 16
			st.summonIcon:ClearAllPoints()
			st.summonIcon:SetPoint(scfg.point or "CENTER", st.barGroup, scfg.relativePoint or scfg.point or "CENTER", roundToPixel(scfg.x or 0, scale), roundToPixel(scfg.y or 0, scale))
			st.summonIcon:SetSize(size, size)
		else
			st.summonIcon:Hide()
		end
	end

	if st.resurrectIcon then
		local rcfg = GF:GetStatusIconCfg(self, "resurrectIcon")
		local indicatorLayer = st.statusIconLayer or st.healthTextLayer or st.health
		if st.resurrectIcon.GetParent and st.resurrectIcon:GetParent() ~= indicatorLayer then st.resurrectIcon:SetParent(indicatorLayer) end
		if st.resurrectIcon.SetDrawLayer then st.resurrectIcon:SetDrawLayer("OVERLAY", 7) end
		if rcfg.enabled ~= false then
			local size = rcfg.size or 16
			st.resurrectIcon:ClearAllPoints()
			st.resurrectIcon:SetPoint(rcfg.point or "CENTER", st.barGroup, rcfg.relativePoint or rcfg.point or "CENTER", roundToPixel(rcfg.x or 0, scale), roundToPixel(rcfg.y or 0, scale))
			st.resurrectIcon:SetSize(size, size)
		else
			st.resurrectIcon:Hide()
		end
	end

	if st.phaseIcon then
		local pcfg = GF:GetStatusIconCfg(self, "phaseIcon")
		local indicatorLayer = st.statusIconLayer or st.healthTextLayer or st.health
		if st.phaseIcon.GetParent and st.phaseIcon:GetParent() ~= indicatorLayer then st.phaseIcon:SetParent(indicatorLayer) end
		if st.phaseIcon.SetDrawLayer then st.phaseIcon:SetDrawLayer("OVERLAY", 7) end
		if pcfg.enabled ~= false then
			local size = pcfg.size or 14
			st.phaseIcon:ClearAllPoints()
			st.phaseIcon:SetPoint(pcfg.point or "TOPLEFT", st.barGroup, pcfg.relativePoint or pcfg.point or "TOPLEFT", roundToPixel(pcfg.x or 0, scale), roundToPixel(pcfg.y or 0, scale))
			st.phaseIcon:SetSize(size, size)
		else
			st.phaseIcon:Hide()
		end
	end

	local baseLevel = (st.barGroup:GetFrameLevel() or 0)
	st.health:SetFrameLevel(baseLevel + 1)
	st.power:SetFrameLevel(baseLevel + 1)
	syncTextFrameLevels(st)

	st._lastHealthPx = nil
	st._lastHealthBarW = nil
	st._lastPowerPx = nil
	st._lastPowerBarW = nil

	GF:UpdateHighlightState(self)
	GF:UpdatePrivateAuras(self)
end

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
	local base = st.statusIconLayer or st.healthTextLayer or st.barGroup or st.frame or st[key]:GetParent()
	if base then
		if st[key].SetFrameStrata and base.GetFrameStrata then st[key]:SetFrameStrata(base:GetFrameStrata()) end
		if st[key].SetFrameLevel and base.GetFrameLevel then st[key]:SetFrameLevel((base:GetFrameLevel() or 0) + 10) end
	end
	return st[key]
end

local function hideAuraButtons(buttons, startIndex)
	if not buttons then return end
	for i = startIndex, #buttons do
		local btn = buttons[i]
		if btn then
			btn._showTooltip = false
			if btn.SetMouseClickEnabled then btn:SetMouseClickEnabled(false) end
			if btn.SetMouseMotionEnabled then btn:SetMouseMotionEnabled(false) end
			if btn.EnableMouse then
				btn._eqolAuraMouseEnabled = false
				btn:EnableMouse(false)
			end
			btn:Hide()
		end
	end
end

local function setAuraTooltipState(btn, style)
	if not (btn and style) then return end
	local show = style.showTooltip == true
	if btn._showTooltip ~= show then btn._showTooltip = show end
	if btn.SetMouseClickEnabled then btn:SetMouseClickEnabled(show) end
	if btn.SetMouseMotionEnabled then btn:SetMouseMotionEnabled(show) end
	if btn.EnableMouse then
		if btn._eqolAuraMouseEnabled ~= show then btn._eqolAuraMouseEnabled = show end
		btn:EnableMouse(show)
	end
	if not show and GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
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
	local scale = GFH.GetEffectiveScale(container)
	local step = size + spacing
	local x = roundToPixel(col * step * xSign, scale)
	local y = roundToPixel(row * step * ySign, scale)
	btn:ClearAllPoints()
	btn:SetPoint(basePoint, container, basePoint, x, y)
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

function GF:GetStatusIconCfg(self, key)
	local kind = (self and self._eqolGroupKind) or "party"
	local cfg = (self and self._eqolCfg) or getCfg(kind)
	return GFH.GetStatusIconCfg(kind, cfg, DEFAULTS, key)
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
	local indicatorLayer = st.statusIconLayer or st.healthTextLayer or st.health or st.barGroup or st.frame
	if not st.roleIcon then st.roleIcon = indicatorLayer:CreateTexture(nil, "OVERLAY", nil, 7) end
	if st.roleIcon.GetParent and st.roleIcon:GetParent() ~= indicatorLayer then st.roleIcon:SetParent(indicatorLayer) end
	if st.roleIcon.SetDrawLayer then st.roleIcon:SetDrawLayer("OVERLAY", 7) end
	local roleKey = getUnitRoleKey(unit)
	if isEditModeActive() and st._previewRole then roleKey = st._previewRole end
	if roleKey == "NONE" and isEditModeActive() then roleKey = "DAMAGER" end
	local selection = rc.showRoles
	if type(selection) == "table" then
		if not GFH.SelectionHasAny(selection) then
			st._lastRoleAtlas = nil
			st.roleIcon:Hide()
			return
		end
		if roleKey == "NONE" or not GFH.SelectionContains(selection, roleKey) then
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

	local acfg = scfg.assistIcon or {}
	if self._eqolGroupKind == "party" or acfg.enabled == false then
		st.assistIcon:Hide()
	else
		local raidRole = getUnitRaidRole(unit)
		local isMainAssist = raidRole == "MAINASSIST"
		local isAssistant = unit and UnitIsGroupAssistant and UnitIsGroupAssistant(unit)
		local showAssist = isMainAssist or isAssistant
		if not showAssist and isEditModeActive() then showAssist = true end
		if showAssist then
			if isMainAssist or isEditModeActive() then
				st.assistIcon:SetAtlas("RaidFrame-Icon-MainAssist", false)
			else
				st.assistIcon:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon")
			end
			st.assistIcon:Show()
		else
			st.assistIcon:Hide()
		end
	end
end

function GF:UpdateReadyCheckIcon(self, event)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st and st.readyCheckIcon) then return end

	local rcfg = GF:GetStatusIconCfg(self, "readyCheckIcon")
	if rcfg.enabled == false then
		GFH.CancelReadyCheckIconTimer(st)
		st._lastReadyCheckStatus = nil
		st.readyCheckIcon:Hide()
		return
	end

	if isEditModeActive() and st._preview then
		GFH.CancelReadyCheckIconTimer(st)
		st.readyCheckIcon:SetTexture(GFH.STATUS_ICON_CONST.waiting)
		st.readyCheckIcon:Show()
		return
	end

	local sampleActive = rcfg.sample == true and isEditModeActive()
	local status = GetReadyCheckStatus and GetReadyCheckStatus(unit) or nil
	if status == "ready" then
		GFH.CancelReadyCheckIconTimer(st)
		st.readyCheckIcon:SetTexture(GFH.STATUS_ICON_CONST.ready)
		st.readyCheckIcon:Show()
	elseif status == "notready" then
		GFH.CancelReadyCheckIconTimer(st)
		st.readyCheckIcon:SetTexture(GFH.STATUS_ICON_CONST.notReady)
		st.readyCheckIcon:Show()
	elseif status == "waiting" then
		GFH.CancelReadyCheckIconTimer(st)
		st.readyCheckIcon:SetTexture(GFH.STATUS_ICON_CONST.waiting)
		st.readyCheckIcon:Show()
	elseif sampleActive then
		GFH.CancelReadyCheckIconTimer(st)
		st.readyCheckIcon:SetTexture(GFH.STATUS_ICON_CONST.waiting)
		st.readyCheckIcon:Show()
	elseif event ~= "READY_CHECK_FINISHED" then
		GFH.CancelReadyCheckIconTimer(st)
		st.readyCheckIcon:Hide()
	end

	if event == "READY_CHECK_FINISHED" and st.readyCheckIcon:IsShown() and not sampleActive then GFH.ScheduleReadyCheckIconHide(st, st.readyCheckIcon, 6) end
	st._lastReadyCheckStatus = status
end

function GF:UpdateSummonIcon(self)
	local st = getState(self)
	if not (st and st.summonIcon) then return end

	local function setSummonVisual(texturePath)
		if st._lastSummonAtlas ~= texturePath then
			st._lastSummonAtlas = texturePath
			st.summonIcon:SetTexture(texturePath)
			if st.summonIcon.SetTexCoord then st.summonIcon:SetTexCoord(0, 1, 0, 1) end
		end
	end

	local scfg = GF:GetStatusIconCfg(self, "summonIcon")
	if scfg.enabled == false then
		st._summonActiveReal = false
		st.summonIcon:Hide()
		return
	end

	local sampleActive = scfg.sample == true and isEditModeActive()
	if sampleActive then
		st._summonActiveReal = false
		setSummonVisual(GFH.STATUS_ICON_CONST.summonPending)
		st.summonIcon:Show()
		return
	end

	local unit = getUnit(self)
	if not unit then
		st._lastSummonAtlas = nil
		st._summonActiveReal = false
		st.summonIcon:Hide()
		return
	end
	local summonStatus = (C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus) and C_IncomingSummon.IncomingSummonStatus(unit) or GFH.STATUS_ICON_CONST.summonStatusNone
	local texture
	if summonStatus == GFH.STATUS_ICON_CONST.summonStatusPending then
		texture = GFH.STATUS_ICON_CONST.summonPending
	elseif summonStatus == GFH.STATUS_ICON_CONST.summonStatusAccepted then
		texture = GFH.STATUS_ICON_CONST.summonAccepted
	elseif summonStatus == GFH.STATUS_ICON_CONST.summonStatusDeclined then
		texture = GFH.STATUS_ICON_CONST.summonDeclined
	end

	if texture then
		st._summonActiveReal = true
		setSummonVisual(texture)
		st.summonIcon:Show()
	else
		st._lastSummonAtlas = nil
		st._summonActiveReal = false
		st.summonIcon:Hide()
	end
end

function GF:UpdateResurrectIcon(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st and st.resurrectIcon) then return end

	local rcfg = GF:GetStatusIconCfg(self, "resurrectIcon")
	if rcfg.enabled == false then
		st.resurrectIcon:Hide()
		return
	end

	if st._summonActiveReal then
		st.resurrectIcon:Hide()
		return
	end

	local showResurrect = UnitHasIncomingResurrection and UnitHasIncomingResurrection(unit)
	if not showResurrect and isEditModeActive() and st._preview then showResurrect = true end
	if not showResurrect and rcfg.sample == true and isEditModeActive() then showResurrect = true end

	if showResurrect then
		st.resurrectIcon:SetTexture(GFH.STATUS_ICON_CONST.resurrect)
		st.resurrectIcon:Show()
	else
		st.resurrectIcon:Hide()
	end
end

function GF:UpdatePhaseIcon(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st and st.phaseIcon) then return end

	local pcfg = GF:GetStatusIconCfg(self, "phaseIcon")
	if pcfg.enabled == false then
		st._phaseReason = nil
		st.phaseIcon:Hide()
		return
	end

	local reason = (UnitIsPlayer and UnitIsPlayer(unit) and UnitIsConnected and UnitIsConnected(unit) and UnitPhaseReason) and UnitPhaseReason(unit) or nil
	if not reason and isEditModeActive() and st._preview then reason = 1 end
	if not reason and pcfg.sample == true and isEditModeActive() then reason = 1 end
	st._phaseReason = reason

	if reason then
		st.phaseIcon:SetTexture(GFH.STATUS_ICON_CONST.phase)
		st.phaseIcon:Show()
	else
		st.phaseIcon:Hide()
	end
end

function GF:UpdateStatusIcons(self, event)
	GF:UpdateReadyCheckIcon(self, event)
	GF:UpdateSummonIcon(self)
	GF:UpdateResurrectIcon(self)
	GF:UpdatePhaseIcon(self)
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
			local color = targetCfg.color or GFH.COLOR_WHITE
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
			local color = hoverCfg.color or GFH.COLOR_WHITE
			hoverFrame:SetBackdropBorderColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
			hoverFrame:Show()
		end
	else
		if hoverFrame then hoverFrame:Hide() end
	end
end

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

local AURA_KIND_HELPFUL = 1
local AURA_KIND_HARMFUL = 2
local AURA_KIND_EXTERNAL = 4
local AURA_KIND_DISPEL = 8

local function setAuraFlag(flags, flag)
	if not flags then return flag end
	if flags % (flag * 2) >= flag then return flags end
	return flags + flag
end

local function hasAuraFlag(flags, flag) return flags and flags % (flag * 2) >= flag end

local function clearDispelAuraState(st)
	if not st then return end
	st._dispelAuraId = nil
	st._dispelAuraIdDirty = nil
end

local function markDispelAuraDirty(st, auraId)
	if not st then return end
	if auraId == nil or st._dispelAuraId == auraId then
		st._dispelAuraId = nil
		st._dispelAuraIdDirty = true
	end
end

local function clearAuraKinds(st)
	if not st then return end
	st._auraKindById = st._auraKindById or {}
	local flagsById = st._auraKindById
	for k in pairs(flagsById) do
		flagsById[k] = nil
	end
	clearDispelAuraState(st)
end

local function isAuraFilteredIn(unit, auraInstanceID, filter)
	if not auraInstanceID then return false end
	if filter then return not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, filter) end
	return false
end

local function getAuraKindFlags(unit, aura, helpfulFilter, harmfulFilter, externalFilter, dispelFilter, wantBuff, wantDebuff, wantExternals, wantsDispel)
	if not (unit and aura and aura.auraInstanceID) then return nil end
	local auraId = aura.auraInstanceID
	local flags
	local harmfulMatch, helpfulMatch

	if wantBuff then
		helpfulMatch = isAuraFilteredIn(unit, auraId, helpfulFilter)
		if helpfulMatch then flags = setAuraFlag(flags, AURA_KIND_HELPFUL) end
	end

	if (wantDebuff or wantsDispel) and not helpfulMatch then
		harmfulMatch = isAuraFilteredIn(unit, auraId, harmfulFilter)
		if wantDebuff and harmfulMatch then flags = setAuraFlag(flags, AURA_KIND_HARMFUL) end
	end

	if wantExternals and not harmfulMatch and isAuraFilteredIn(unit, auraId, externalFilter) then flags = setAuraFlag(flags, AURA_KIND_EXTERNAL) end
	if wantsDispel and harmfulMatch and isAuraFilteredIn(unit, auraId, dispelFilter) then flags = setAuraFlag(flags, AURA_KIND_DISPEL) end

	return flags
end

local function removeAuraFromGroupStore(cache, flagsById, auraId)
	if not (cache and auraId) then return end
	cache.auras[auraId] = nil
	if cache.indexById then cache.indexById[auraId] = nil end
	cache._orderDirty = true
	if flagsById then flagsById[auraId] = nil end
end

local function compactAuraOrder(cache)
	if not (cache and cache._orderDirty and cache.order and cache.indexById and cache.auras) then return end
	local order = cache.order
	local indexById = cache.indexById
	local auras = cache.auras
	for k in pairs(indexById) do
		indexById[k] = nil
	end
	local write = 1
	for read = 1, #order do
		local auraId = order[read]
		if auraId and auras[auraId] and not indexById[auraId] then
			order[write] = auraId
			indexById[auraId] = write
			write = write + 1
		end
	end
	for i = write, #order do
		order[i] = nil
	end
	cache._orderDirty = nil
end

local function cacheAuraWithFlags(cache, flagsById, aura, flags, st)
	if not (cache and aura and aura.auraInstanceID) then return end
	local auraId = aura.auraInstanceID
	local prevFlags = flagsById and flagsById[auraId]
	if flags then
		cache.auras[auraId] = aura
		if AuraUtil and AuraUtil.addAuraToOrder then
			AuraUtil.addAuraToOrder(cache, auraId)
		else
			if not cache.indexById[auraId] then
				cache.order[#cache.order + 1] = auraId
				cache.indexById[auraId] = #cache.order
			end
		end
		if flagsById then flagsById[auraId] = flags end
		if st then
			local hadDispel = hasAuraFlag(prevFlags, AURA_KIND_DISPEL)
			local hasDispel = hasAuraFlag(flags, AURA_KIND_DISPEL)
			if st._dispelAuraId == auraId and not hasDispel then
				st._dispelAuraId = nil
				st._dispelAuraIdDirty = true
			elseif (not st._dispelAuraId) and hasDispel then
				st._dispelAuraId = auraId
				st._dispelAuraIdDirty = nil
			elseif hadDispel and not hasDispel and not st._dispelAuraId then
				st._dispelAuraIdDirty = true
			end
		end
	else
		markDispelAuraDirty(st, auraId)
		removeAuraFromGroupStore(cache, flagsById, auraId)
	end
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
	},
}

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
	GFH.SyncAurasEnabled(cfg)
	local wantsAuras = (ac.buff and ac.buff.enabled) or (ac.debuff and ac.debuff.enabled) or (ac.externals and ac.externals.enabled)
	if not wantsAuras then return end

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
			local scale = GFH.GetEffectiveScale(parent)
			size = roundToPixel(size, scale)
			spacing = roundToPixel(spacing, scale)
			x = roundToPixel(x, scale)
			y = roundToPixel(y, scale)

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
					-- If we anchor the container via a centered point (e.g. CENTER/TOP/BOTTOM/LEFT/RIGHT),
					-- make sure its size is even in pixel-space to avoid half-pixel jitter.
					local centerX = anchorPoint and (not anchorPoint:find("LEFT") and not anchorPoint:find("RIGHT"))
					local centerY = anchorPoint and (not anchorPoint:find("TOP") and not anchorPoint:find("BOTTOM"))
					if centerX then
						w = roundToEvenPixel(w, scale)
					else
						w = roundToPixel(w, scale)
					end
					if centerY then
						h = roundToEvenPixel(h, scale)
					else
						h = roundToPixel(h, scale)
					end
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
			style.blizzardDispelBorder = typeCfg.showDispelIcon == true
			if typeCfg.showCooldownText ~= nil then style.showCooldownText = typeCfg.showCooldownText end
			style.cooldownAnchor = typeCfg.cooldownAnchor
			style.cooldownOffset = typeCfg.cooldownOffset
			style.cooldownFont = typeCfg.cooldownFont
			style.countFont = typeCfg.countFont
			style.countFontSize = typeCfg.countFontSize
			style.countFontOutline = typeCfg.countFontOutline
			style.cooldownFontSize = typeCfg.cooldownFontSize
			style.cooldownFontOutline = typeCfg.cooldownFontOutline
			if typeCfg.showStacks ~= nil then style.showStacks = typeCfg.showStacks end
			style.countAnchor = typeCfg.countAnchor
			style.countOffset = typeCfg.countOffset
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

local function updateAuraType(self, unit, st, ac, kindKey, cache, changed)
	local meta = AURA_TYPE_META[kindKey]
	if not meta then return end
	local typeCfg = (ac and ac[kindKey]) or EMPTY
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
	local flags = st._auraKindById
	local externalsEnabled = ac and ac.externals and ac.externals.enabled ~= false
	local shown = 0
	local maxCount = layout.maxCount or 0
	for i = 1, #order do
		if shown >= maxCount then break end
		local auraId = order[i]
		local aura = auraId and auras[auraId]
		if aura then
			local auraFlags = flags and flags[auraId]
			local match = false
			if kindKey == "debuff" then
				match = hasAuraFlag(auraFlags, AURA_KIND_HARMFUL)
			elseif kindKey == "buff" then
				match = hasAuraFlag(auraFlags, AURA_KIND_HELPFUL)
				if match and externalsEnabled and hasAuraFlag(auraFlags, AURA_KIND_EXTERNAL) then match = false end
			elseif kindKey == "externals" then
				match = hasAuraFlag(auraFlags, AURA_KIND_EXTERNAL)
			end
			if match then
				shown = shown + 1
				local btn = buttons and buttons[shown]
				if not btn then btn = AuraUtil.ensureAuraButton(container, buttons, shown, style) end
				local auraIdForBtn = aura.auraInstanceID or auraId
				if btn.unitToken ~= unit or btn.auraInstanceID ~= auraIdForBtn or (changed and auraIdForBtn and changed[auraIdForBtn]) then
					AuraUtil.applyAuraToButton(btn, aura, style, meta.isDebuff, unit)
				end
				setAuraTooltipState(btn, style)
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
		local scale = GFH.GetEffectiveScale(container)
		w = roundToEvenPixel(w, scale)
		h = roundToEvenPixel(h, scale)
		if container._eqolAuraCenterW ~= w or container._eqolAuraCenterH ~= h then
			container:SetSize(w, h)
			container._eqolAuraCenterW = w
			container._eqolAuraCenterH = h
		end
	end
	hideAuraButtons(buttons, shown + 1)
end

local function fullScanGroupAuras(unit, st, cache, helpfulFilter, harmfulFilter, externalFilter, dispelFilter, wantBuff, wantDebuff, wantExternals, wantsDispel, queryMax)
	if not (unit and st and cache and C_UnitAuras) then return end
	resetAuraCache(cache)
	clearAuraKinds(st)
	local flagsById = st._auraKindById
	local seen = {}

	local function storeAura(aura)
		local auraId = aura and aura.auraInstanceID
		if not auraId or seen[auraId] then return end
		seen[auraId] = true
		local flags = getAuraKindFlags(unit, aura, helpfulFilter, harmfulFilter, externalFilter, dispelFilter, wantBuff, wantDebuff, wantExternals, wantsDispel)
		cacheAuraWithFlags(cache, flagsById, aura, flags, st)
	end

	if wantBuff and helpfulFilter then
		local helpfulSlots = queryAuraSlots(unit, helpfulFilter, queryMax and queryMax.helpful)
		for i = 2, (helpfulSlots and #helpfulSlots or 0) do
			local aura = C_UnitAuras.GetAuraDataBySlot(unit, helpfulSlots[i])
			if aura then storeAura(aura) end
		end
	end
	if (wantDebuff or wantsDispel) and harmfulFilter then
		local harmfulSlots = queryAuraSlots(unit, harmfulFilter, queryMax and queryMax.harmful)
		for i = 2, (harmfulSlots and #harmfulSlots or 0) do
			local aura = C_UnitAuras.GetAuraDataBySlot(unit, harmfulSlots[i])
			if aura then storeAura(aura) end
		end
	end
	if wantExternals and externalFilter then
		local externalSlots = queryAuraSlots(unit, externalFilter, queryMax and queryMax.external)
		for i = 2, (externalSlots and #externalSlots or 0) do
			local aura = C_UnitAuras.GetAuraDataBySlot(unit, externalSlots[i])
			if aura then storeAura(aura) end
		end
	end
end

local function updateGroupAuraCache(unit, st, updateInfo, ac, helpfulFilter, harmfulFilter, externalFilter, dispelFilter)
	if not (unit and st and updateInfo) then return end

	local wantBuff = ac and (ac.buff and ac.buff.enabled ~= false) or false
	local wantDebuff = ac and (ac.debuff and ac.debuff.enabled ~= false) or false
	local wantExternals = ac and (ac.externals and ac.externals.enabled ~= false) or false
	local wantsDispel = st._wantsDispelTint == true
	local wantsAny = wantBuff or wantDebuff or wantExternals or wantsDispel
	local cache = getAuraCache(st, "all")

	st._auraKindById = st._auraKindById or {}
	local flagsById = st._auraKindById

	if not wantsAny then
		resetAuraCache(cache)
		clearAuraKinds(st)
		return
	end

	if updateInfo.removedAuraInstanceIDs then
		for i = 1, #updateInfo.removedAuraInstanceIDs do
			local auraId = updateInfo.removedAuraInstanceIDs[i]
			markDispelAuraDirty(st, auraId)
			removeAuraFromGroupStore(cache, flagsById, auraId)
		end
	end

	if updateInfo.addedAuras then
		for i = 1, #updateInfo.addedAuras do
			local aura = updateInfo.addedAuras[i]
			local flags = getAuraKindFlags(unit, aura, helpfulFilter, harmfulFilter, externalFilter, dispelFilter, wantBuff, wantDebuff, wantExternals, wantsDispel)
			cacheAuraWithFlags(cache, flagsById, aura, flags, st)
		end
	end

	if updateInfo.updatedAuraInstanceIDs and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
		for i = 1, #updateInfo.updatedAuraInstanceIDs do
			local auraId = updateInfo.updatedAuraInstanceIDs[i]
			local isKnown = auraId and ((flagsById and flagsById[auraId]) or (cache.auras and cache.auras[auraId]))
			if isKnown then
				local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraId)
				if aura then
					local flags = getAuraKindFlags(unit, aura, helpfulFilter, harmfulFilter, externalFilter, dispelFilter, wantBuff, wantDebuff, wantExternals, wantsDispel)
					cacheAuraWithFlags(cache, flagsById, aura, flags, st)
				else
					markDispelAuraDirty(st, auraId)
					removeAuraFromGroupStore(cache, flagsById, auraId)
				end
			end
		end
	end

	compactAuraOrder(cache)
end

function GF:UpdateAuras(self, updateInfo)
	local st = getState(self)
	if not (st and AuraUtil) then return end
	local unit = getUnit(self)
	local inEditMode = isEditModeActive()
	if inEditMode then
		if GF and GF._editModeSampleAuras == false then
			if st.buffContainer then st.buffContainer:Hide() end
			if st.debuffContainer then st.debuffContainer:Hide() end
			if st.externalContainer then st.externalContainer:Hide() end
			hideAuraButtons(st.buffButtons, 1)
			hideAuraButtons(st.debuffButtons, 1)
			hideAuraButtons(st.externalButtons, 1)
			st._auraSampleActive = nil
			GF:UpdateDispelTint(self, nil, nil)
			return
		end
		GF:UpdateSampleAuras(self)
		return
	elseif self._eqolPreview then
		if st.buffContainer then st.buffContainer:Hide() end
		if st.debuffContainer then st.debuffContainer:Hide() end
		if st.externalContainer then st.externalContainer:Hide() end
		hideAuraButtons(st.buffButtons, 1)
		hideAuraButtons(st.debuffButtons, 1)
		hideAuraButtons(st.externalButtons, 1)
		st._auraSampleActive = nil
		GF:UpdateDispelTint(self, nil, nil)
		return
	end
	if not (unit and C_UnitAuras) then
		GF:UpdateDispelTint(self, nil, nil)
		return
	end
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local ac = (cfg and cfg.auras) or EMPTY
	if cfg then GFH.SyncAurasEnabled(cfg) end
	local wantsAuras = st._wantsAuras
	if wantsAuras == nil then wantsAuras = ((ac.buff and ac.buff.enabled) or (ac.debuff and ac.debuff.enabled) or (ac.externals and ac.externals.enabled)) or false end
	local wantsDispelTint = st._wantsDispelTint == true
	if wantsAuras == false and not wantsDispelTint then
		if st.buffContainer then st.buffContainer:Hide() end
		if st.debuffContainer then st.debuffContainer:Hide() end
		if st.externalContainer then st.externalContainer:Hide() end
		hideAuraButtons(st.buffButtons, 1)
		hideAuraButtons(st.debuffButtons, 1)
		hideAuraButtons(st.externalButtons, 1)
		return
	end
	if wantsAuras == false then
		if st.buffContainer then st.buffContainer:Hide() end
		if st.debuffContainer then st.debuffContainer:Hide() end
		if st.externalContainer then st.externalContainer:Hide() end
		hideAuraButtons(st.buffButtons, 1)
		hideAuraButtons(st.debuffButtons, 1)
		hideAuraButtons(st.externalButtons, 1)
	end

	st._auraSampleActive = nil

	local wantBuff = wantsAuras and ac.buff and ac.buff.enabled ~= false
	local wantDebuff = wantsAuras and ac.debuff and ac.debuff.enabled ~= false
	local wantExternals = wantsAuras and ac.externals and ac.externals.enabled ~= false
	if wantsAuras then
		if
			not st._auraLayout
			or (wantBuff and not (st._auraLayout.buff and st._auraLayout.buff.key))
			or (wantDebuff and not (st._auraLayout.debuff and st._auraLayout.debuff.key))
			or (wantExternals and not (st._auraLayout.externals and st._auraLayout.externals.key))
		then
			GF:LayoutAuras(self)
		end
	end
	local helpfulFilter = AURA_FILTERS.helpful
	local harmfulFilter = AURA_FILTERS.harmful
	local dispelFilter = AURA_FILTERS.dispellable
	local externalFilter = AURA_FILTERS.bigDefensive
	local auraQueryMax = st._auraQueryMax
	if not auraQueryMax then
		auraQueryMax = {}
		st._auraQueryMax = auraQueryMax
	end
	local function normalizeMax(value)
		value = floor(tonumber(value) or 0)
		if value < 1 then return nil end
		return value
	end
	local buffMax = normalizeMax(st._auraLayout and st._auraLayout.buff and st._auraLayout.buff.maxCount)
	local debuffMax = normalizeMax(st._auraLayout and st._auraLayout.debuff and st._auraLayout.debuff.maxCount)
	local externalMax = normalizeMax(st._auraLayout and st._auraLayout.externals and st._auraLayout.externals.maxCount)
	if wantBuff and buffMax then
		local extra = (wantExternals and externalMax) or 0
		local helpfulMax = normalizeMax(buffMax + extra)
		auraQueryMax.helpful = helpfulMax or buffMax
	else
		auraQueryMax.helpful = nil
	end
	local scanHarmful = wantDebuff or wantsDispelTint
	if scanHarmful then
		-- Dispel tint is derived from the harmful scan; keep it unbounded for correctness.
		auraQueryMax.harmful = wantsDispelTint and nil or debuffMax
	else
		auraQueryMax.harmful = nil
	end
	auraQueryMax.external = wantExternals and externalMax or nil
	local allCache = getAuraCache(st, "all")
	st._auraKindById = st._auraKindById or {}
	if not updateInfo or updateInfo.isFullUpdate then
		fullScanGroupAuras(unit, st, allCache, helpfulFilter, harmfulFilter, externalFilter, dispelFilter, wantBuff, wantDebuff, wantExternals, wantsDispelTint, auraQueryMax)
		if wantsAuras then
			if wantBuff then updateAuraType(self, unit, st, ac, "buff", allCache) end
			if wantDebuff then updateAuraType(self, unit, st, ac, "debuff", allCache) end
			if wantExternals then updateAuraType(self, unit, st, ac, "externals", allCache) end
		end
		if wantsDispelTint then
			GF:UpdateDispelTint(self, allCache, dispelFilter, nil, AURA_KIND_DISPEL)
		else
			GF:UpdateDispelTint(self, nil, nil)
		end
		return
	end
	local touchBuff, touchDebuff, touchExternals
	local function markKinds(flags)
		if not flags then return end
		if hasAuraFlag(flags, AURA_KIND_HELPFUL) then touchBuff = true end
		if hasAuraFlag(flags, AURA_KIND_HARMFUL) then touchDebuff = true end
		if hasAuraFlag(flags, AURA_KIND_EXTERNAL) then touchExternals = true end
	end
	if updateInfo then
		local preFlags = st._auraKindById
		local removed = updateInfo.removedAuraInstanceIDs
		local updated = updateInfo.updatedAuraInstanceIDs
		if removed or updated then
			if preFlags then
				if removed then
					for i = 1, #removed do
						markKinds(preFlags[removed[i]])
					end
				end
				if updated then
					for i = 1, #updated do
						markKinds(preFlags[updated[i]])
					end
				end
			else
				touchBuff = wantBuff
				touchDebuff = wantDebuff
				touchExternals = wantExternals
			end
		end
	end

	updateGroupAuraCache(unit, st, updateInfo, ac, helpfulFilter, harmfulFilter, externalFilter, dispelFilter)
	local changed = st._auraChanged
	if updateInfo then
		if not changed then
			changed = {}
			st._auraChanged = changed
		elseif wipe then
			wipe(changed)
		else
			for k in pairs(changed) do
				changed[k] = nil
			end
		end
		local added = updateInfo.addedAuras
		if added then
			for i = 1, #added do
				local aura = added[i]
				local id = aura and aura.auraInstanceID
				if id then changed[id] = true end
			end
		end
		local updated = updateInfo.updatedAuraInstanceIDs
		if updated then
			for i = 1, #updated do
				local id = updated[i]
				if id then changed[id] = true end
			end
		end
		local flags = st._auraKindById
		if not flags then
			if not (touchBuff or touchDebuff or touchExternals) then
				touchBuff = wantBuff
				touchDebuff = wantDebuff
				touchExternals = wantExternals
			end
		else
			if added then
				for i = 1, #added do
					local aura = added[i]
					local id = aura and aura.auraInstanceID
					if id then markKinds(flags[id]) end
				end
			end
			if updated then
				for i = 1, #updated do
					local id = updated[i]
					if id then markKinds(flags[id]) end
				end
			end
		end
	end
	if wantsAuras then
		if wantBuff and touchBuff then updateAuraType(self, unit, st, ac, "buff", allCache, changed) end
		if wantDebuff and touchDebuff then updateAuraType(self, unit, st, ac, "debuff", allCache, changed) end
		if wantExternals and touchExternals then updateAuraType(self, unit, st, ac, "externals", allCache, changed) end
	end
	if wantsDispelTint then
		GF:UpdateDispelTint(self, allCache, dispelFilter, nil, AURA_KIND_DISPEL)
	else
		GF:UpdateDispelTint(self, nil, nil)
	end
end

function GF:UpdateSampleAuras(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (st and AuraUtil) then return end
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local ac = (cfg and cfg.auras) or EMPTY
	local scfg = (cfg and cfg.status) or EMPTY
	local wantsDispelTint = resolveDispelIndicatorEnabled(cfg, self._eqolGroupKind or "party")
	st._wantsDispelTint = wantsDispelTint
	if cfg then GFH.SyncAurasEnabled(cfg) end
	local wantsAuras = ((ac.buff and ac.buff.enabled) or (ac.debuff and ac.debuff.enabled) or (ac.externals and ac.externals.enabled)) or false
	if ac.enabled == true then wantsAuras = true end
	st._wantsAuras = wantsAuras
	if wantsAuras == false then
		if st.buffContainer then st.buffContainer:Hide() end
		if st.debuffContainer then st.debuffContainer:Hide() end
		if st.externalContainer then st.externalContainer:Hide() end
		hideAuraButtons(st.buffButtons, 1)
		hideAuraButtons(st.debuffButtons, 1)
		hideAuraButtons(st.externalButtons, 1)
		st._auraSampleActive = nil
		if wantsDispelTint then
			GF:UpdateDispelTint(self, nil, nil, true)
		else
			GF:UpdateDispelTint(self, nil, nil)
		end
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
		local typeCfg = (ac and ac[kindKey]) or EMPTY
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
			setAuraTooltipState(btn, sampleStyle)
			if btn._auraLayoutKey ~= layout.key then
				positionAuraButton(btn, container, layout.primary, layout.secondary, i, layout.perRow, layout.size, layout.spacing)
				btn._auraLayoutKey = layout.key
			end
			btn:Show()
		end
		if kindKey == "externals" and layout.anchorPoint == "CENTER" and container then
			local w, h = calcAuraGridSize(shown, layout.perRow, layout.size, layout.spacing, layout.primary)
			local scale = GFH.GetEffectiveScale(container)
			w = roundToEvenPixel(w, scale)
			h = roundToEvenPixel(h, scale)
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
	if wantsDispelTint then
		GF:UpdateDispelTint(self, nil, nil, true)
	else
		GF:UpdateDispelTint(self, nil, nil)
	end
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
	local kind = self._eqolGroupKind or "party"
	local cfg = self._eqolCfg or getCfg(kind)
	local tc = cfg and cfg.text or {}
	local sc = cfg and cfg.status or {}
	local connected = UnitIsConnected and GFH.UnsecretBool(UnitIsConnected(unit))
	local displayName = name or ""
	if isEditModeActive() and self._eqolPreview and st._previewName then displayName = st._previewName end
	local maxChars = tonumber(tc.nameMaxChars) or 0
	local noEllipsis = tc.nameNoEllipsis
	if noEllipsis == nil then noEllipsis = (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.nameNoEllipsis) == true end
	if noEllipsis and maxChars > 0 and UFHelper and UFHelper.getNameLimitWidth and UFHelper.truncateTextToWidth then
		local hc = cfg and cfg.health or {}
		local font = tc.font or hc.font
		local fontSize = tc.fontSize or hc.fontSize or 12
		local fontOutline = tc.fontOutline or hc.fontOutline or "OUTLINE"
		local maxWidth = UFHelper.getNameLimitWidth(font, fontSize, fontOutline, maxChars)
		if maxWidth and maxWidth > 0 then displayName = UFHelper.truncateTextToWidth(font, fontSize, fontOutline, displayName, maxWidth) end
	end
	if connected == false then displayName = (displayName and displayName ~= "") and (displayName .. " |cffff6666DC|r") or "|cffff6666DC|r" end
	displayName = displayName or ""
	if st._lastName ~= displayName then
		fs:SetText(displayName)
		st._lastName = displayName
	end

	local r, g, b, a = 1, 1, 1, 1
	local nameMode = sc.nameColorMode
	if nameMode == nil then nameMode = (tc.useClassColor ~= false) and "CLASS" or "CUSTOM" end
	if nameMode == "CUSTOM" then
		r, g, b, a = unpackColor(sc.nameColor, GFH.COLOR_WHITE)
	elseif nameMode == "CLASS" then
		if not st._classR then GF:EnsureUnitClassColor(self, st, unit) end
		if st._classR then
			r, g, b, a = st._classR, st._classG, st._classB, st._classA or 1
		end
	end
	if connected == false then
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

local function getRaidSubgroupForUnit(unit)
	if not unit then return nil end
	local idx
	if UnitInRaid then idx = UnitInRaid(unit) end
	if (not idx) and type(unit) == "string" then
		local raidIndex = unit:match("^raid(%d+)$")
		if raidIndex then idx = tonumber(raidIndex) end
	end
	if not idx then return nil end
	if not GetRaidRosterInfo then return nil end
	local _, _, subgroup = GetRaidRosterInfo(idx)
	if issecretvalue and issecretvalue(subgroup) then return nil end
	return tonumber(subgroup)
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
		r, g, b, a = unpackColor(scfg.levelColor, GFH.COLOR_LEVEL)
	elseif scfg.levelColorMode == "CLASS" then
		if not st._classR then GF:EnsureUnitClassColor(self, st, unit) end
		if st._classR then
			r, g, b, a = st._classR, st._classG, st._classB, st._classA or 1
		end
	end
	if st._lastLevelR ~= r or st._lastLevelG ~= g or st._lastLevelB ~= b or st._lastLevelA ~= a then
		st._lastLevelR, st._lastLevelG, st._lastLevelB, st._lastLevelA = r, g, b, a
		st.levelText:SetTextColor(r, g, b, a)
	end
end

function GF:UpdateStatusText(self)
	local st = getState(self)
	local unit = getUnit(self)
	if not st then return end
	local statusFs = st.statusText
	local groupFs = st.groupNumberText
	if not (statusFs or groupFs) then return end
	local kind = self._eqolGroupKind or "party"
	local cfg = self._eqolCfg or getCfg(kind)
	local def = DEFAULTS[kind] or {}
	local scfg = cfg and cfg.status or {}
	local us = scfg.unitStatus or {}
	local hc = cfg and cfg.health or {}
	if st._wantsStatusText == false or us.enabled == false then
		if statusFs then
			statusFs:SetText("")
			statusFs:Hide()
		end
		if groupFs then
			groupFs:SetText("")
			groupFs:Hide()
		end
		return
	end
	local inEditMode = isEditModeActive()
	if inEditMode and GF and GF._editModeSampleStatusText == false then
		if statusFs then
			statusFs:SetText("")
			statusFs:Hide()
		end
		if groupFs then
			groupFs:SetText("")
			groupFs:Hide()
		end
		return
	end
	local allowSample = inEditMode and self._eqolPreview
	if UnitExists and unit and not UnitExists(unit) and not allowSample then
		if statusFs then
			statusFs:SetText("")
			statusFs:Hide()
		end
		if groupFs then
			groupFs:SetText("")
			groupFs:Hide()
		end
		return
	end
	local statusTag
	local showOffline = us.showOffline
	if showOffline == nil then showOffline = true end
	local showAFK = us.showAFK == true
	local showDND = us.showDND == true
	local connected = unit and UnitIsConnected and GFH.UnsecretBool(UnitIsConnected(unit)) or nil
	local isAFK = unit and UnitIsAFK and GFH.UnsecretBool(UnitIsAFK(unit)) or nil
	local isDND = unit and UnitIsDND and GFH.UnsecretBool(UnitIsDND(unit)) or nil
	local isDead = unit and UnitIsDeadOrGhost and GFH.UnsecretBool(UnitIsDeadOrGhost(unit)) or nil
	local isGhost = unit and UnitIsGhost and GFH.UnsecretBool(UnitIsGhost(unit)) or nil
	if connected == false then
		if showOffline then statusTag = PLAYER_OFFLINE or "Offline" end
	elseif isDead == true then
		if isGhost == true then
			statusTag = GHOST or "Ghost"
		else
			statusTag = DEAD or "Dead"
		end
	elseif isDND == true then
		if showDND then statusTag = DEFAULT_DND_MESSAGE or "DND" end
	end
	if not statusTag and isAFK == true then
		if showAFK then statusTag = DEFAULT_AFK_MESSAGE or "AFK" end
	end

	local groupTag
	if resolveGroupNumberEnabled(cfg, def) then
		local subgroup = getRaidSubgroupForUnit(unit)
		if not subgroup and allowSample then subgroup = st._previewGroup or 1 end
		if subgroup then groupTag = formatGroupNumber(subgroup, resolveGroupNumberFormat(cfg, def)) end
	end
	if not statusTag and allowSample then
		if showOffline then statusTag = PLAYER_OFFLINE or "Offline" end
		if not statusTag and showDND then statusTag = DEFAULT_DND_MESSAGE or "DND" end
		if not statusTag and showAFK then statusTag = DEFAULT_AFK_MESSAGE or "AFK" end
	end
	local scale = GFH.GetEffectiveScale(self)
	if not scale or scale <= 0 then scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1 end

	if statusFs then
		if statusTag then
			local style = resolveStatusTextStyle(cfg, def, hc)
			if UFHelper and UFHelper.applyFont then UFHelper.applyFont(statusFs, style.font, style.fontSize or 12, style.fontOutline) end
			applyStatusTextAnchor(st, style.anchor, style.offset, scale, st.barGroup or self, statusFs)
			local r, g, b, a = unpackColor(style.color, GFH.COLOR_WHITE)
			statusFs:SetText(statusTag)
			statusFs:SetTextColor(r, g, b, a)
			statusFs:Show()
		else
			statusFs:SetText("")
			statusFs:Hide()
		end
	end

	if groupFs then
		if groupTag then
			local style = resolveGroupNumberStyle(cfg, def, hc)
			if UFHelper and UFHelper.applyFont then UFHelper.applyFont(groupFs, style.font, style.fontSize or 12, style.fontOutline) end
			applyStatusTextAnchor(st, style.anchor, style.offset, scale, st.barGroup or self, groupFs)
			local r, g, b, a = unpackColor(style.color, GFH.COLOR_WHITE)
			groupFs:SetText(groupTag)
			groupFs:SetTextColor(r, g, b, a)
			groupFs:Show()
		else
			groupFs:SetText("")
			groupFs:Hide()
		end
	end
end

local function hideGroupIndicators(container)
	if not container then return end
	local indicators = container._eqolGroupIndicators
	if not indicators then return end
	for _, fs in pairs(indicators) do
		if fs then
			fs:SetText("")
			fs:Hide()
		end
	end
end

local function updateGroupIndicatorsForFrames(container, frames, cfg, def, isPreview, fixedSubgroup)
	if not container then return end
	if not (cfg and resolveGroupIndicatorEnabled(cfg, def) and isGroupIndicatorAvailable(cfg, def)) then
		hideGroupIndicators(container)
		return
	end
	if not (frames and #frames > 0) then
		hideGroupIndicators(container)
		return
	end

	local candidates = {}

	local fixedGroup = tonumber(fixedSubgroup)
	if fixedGroup and fixedGroup >= 1 and fixedGroup <= 8 then
		for visualIndex, frame in ipairs(frames) do
			if frame and frame.IsShown and frame:IsShown() then
				candidates[fixedGroup] = { frame = frame, key = visualIndex }
				break
			end
		end
	else
		for visualIndex, frame in ipairs(frames) do
			if frame and frame.IsShown and frame:IsShown() then
				local st = getState(frame)
				local subgroup
				if isPreview then
					if st then subgroup = st._previewGroup end
				else
					local unit = getUnit(frame)
					if unit then subgroup = getRaidSubgroupForUnit(unit) end
				end

				if subgroup then
					subgroup = tonumber(subgroup) or subgroup
					local current = candidates[subgroup]
					if not current or visualIndex < current.key then candidates[subgroup] = { frame = frame, key = visualIndex } end
				end
			end
		end
	end

	if not next(candidates) then
		hideGroupIndicators(container)
		return
	end

	local indicators = container._eqolGroupIndicators
	if not indicators then
		indicators = {}
		container._eqolGroupIndicators = indicators
	end
	local style = resolveGroupIndicatorStyle(cfg, def, (cfg and cfg.health) or {})
	local format = resolveGroupIndicatorFormat(cfg, def)
	local scale = GFH.GetEffectiveScale(container)
	if not scale or scale <= 0 then scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1 end
	local used = {}

	for subgroup, entry in pairs(candidates) do
		local fs = indicators[subgroup]
		if not fs and container.CreateFontString then
			fs = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			indicators[subgroup] = fs
		end
		if fs and entry and entry.frame then
			local target = entry.frame
			local st = target and getState(target)
			local anchorTarget = (st and st.barGroup) or target
			if anchorTarget then
				if fs.GetParent and fs:GetParent() ~= container then fs:SetParent(container) end
				if fs.SetDrawLayer then fs:SetDrawLayer("OVERLAY", 7) end
				if UFHelper and UFHelper.applyFont then UFHelper.applyFont(fs, style.font, style.fontSize or 12, style.fontOutline) end
				applyGroupIndicatorAnchor(fs, style.anchor, style.offset, scale, anchorTarget)
				local r, g, b, a = unpackColor(style.color, GFH.COLOR_WHITE)
				fs:SetText(formatGroupNumber(subgroup, format))
				fs:SetTextColor(r, g, b, a)
				fs:Show()
				used[subgroup] = true
			else
				fs:SetText("")
				fs:Hide()
			end
		end
	end

	for subgroup, fs in pairs(indicators) do
		if not used[subgroup] then
			fs:SetText("")
			fs:Hide()
		end
	end
end

function GF:UpdateDispelTint(self, cache, dispelFilter, allowSample, requiredFlag)
	local st = getState(self)
	if not st then return end
	local kind = self._eqolGroupKind or "party"
	local cfg = self._eqolCfg or getCfg(kind)
	local scfg = cfg and cfg.status or {}
	local dcfg = scfg.dispelTint or {}
	local defDispel = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
	local overlayEnabled = dcfg.enabled
	if overlayEnabled == nil then overlayEnabled = defDispel.enabled ~= false end
	local glowEnabled = dcfg.glowEnabled
	if glowEnabled == nil then glowEnabled = defDispel.glowEnabled == true end
	if not overlayEnabled and not glowEnabled then
		hideDispelTint(st)
		stopDispelGlowIfActive(st, st.barGroup or self)
		return
	end
	if allowSample then
		local showSample = dcfg.showSample
		if showSample == nil then showSample = defDispel.showSample == true end
		if not showSample then
			hideDispelTint(st)
			stopDispelGlowIfActive(st, st.barGroup or self)
			return
		end
	end
	local alpha = dcfg.alpha
	if alpha == nil then alpha = defDispel.alpha or 0.25 end
	local fillEnabled = dcfg.fillEnabled
	if fillEnabled == nil then fillEnabled = defDispel.fillEnabled ~= false end
	local fillAlpha = dcfg.fillAlpha
	if fillAlpha == nil then fillAlpha = defDispel.fillAlpha or 0.2 end
	local fillColor = dcfg.fillColor or defDispel.fillColor or GFH.COLOR_BLACK
	local fr, fg, fb, fa = unpackColor(fillColor, GFH.COLOR_BLACK)
	if not fillEnabled then fillAlpha = 0 end
	local bgAlpha = fillAlpha * (fa or 1)

	local r, g, b
	local colorKey
	if allowSample then
		r, g, b = GFH.GetDebuffColorFromName("Magic")
		colorKey = "Magic"
	else
		local unit = getUnit(self)
		if unit and cache and cache.order and cache.auras then
			local auras = cache.auras
			local order = cache.order
			local flagsById = st._auraKindById
			local dispelAuraId = st._dispelAuraId
			local dispelAura
			local needsScan = st._dispelAuraIdDirty or not dispelAuraId
			if not needsScan then
				dispelAura = auras[dispelAuraId]
				if not dispelAura then
					needsScan = true
				elseif requiredFlag and not hasAuraFlag(flagsById and flagsById[dispelAuraId], requiredFlag) then
					needsScan = true
				end
			end
			if needsScan then
				dispelAuraId = nil
				dispelAura = nil
				for i = 1, #order do
					local auraId = order[i]
					local aura = auraId and auras[auraId]
					local match = true
					if requiredFlag then
						local auraKey = (aura and aura.auraInstanceID) or auraId
						match = auraKey and hasAuraFlag(flagsById and flagsById[auraKey], requiredFlag)
					end
					if aura and match then
						dispelAura = aura
						dispelAuraId = aura.auraInstanceID or auraId
						break
					end
				end
				st._dispelAuraId = dispelAuraId
				st._dispelAuraIdDirty = nil
			end
			if dispelAura then
				local auraId = dispelAura.auraInstanceID or dispelAuraId
				if auraId and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor and GFH and GFH.DispelColorCurve then
					local color = C_UnitAuras.GetAuraDispelTypeColor(unit, auraId, GFH.DispelColorCurve)
					if color then
						if color.GetRGBA then
							r, g, b = color:GetRGBA()
						elseif color.r then
							r, g, b = color.r, color.g, color.b
						end
						colorKey = auraId
					end
				end
				if not r then
					local dispelName = dispelAura.dispelName
					if not (issecretvalue and issecretvalue(dispelName)) and dispelName and dispelName ~= "" then
						colorKey = dispelName
						r, g, b = GFH.GetDebuffColorFromName(dispelName)
					end
				end
			end
		end
	end

	if r and not colorKey then colorKey = "UNKNOWN" end

	if overlayEnabled then
		if r then
			applyDispelTint(st, r, g or 0, b or 0, alpha, fr, fg, fb, bgAlpha)
		else
			hideDispelTint(st)
		end
	else
		hideDispelTint(st)
	end

	if glowEnabled then
		GF:UpdateDispelGlow(self, r, g, b, colorKey)
	else
		stopDispelGlowIfActive(st, st.barGroup or self)
	end
end

function GF:UpdateDispelGlow(self, r, g, b, colorKey)
	local st = getState(self)
	if not st then return end
	if not (LCG and LCG.PixelGlow_Start) then return end
	local kind = self._eqolGroupKind or "party"
	local cfg = self._eqolCfg or getCfg(kind)
	local scfg = cfg and cfg.status or {}
	local dcfg = scfg.dispelTint or {}
	local defDispel = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
	local glowEnabled = dcfg.glowEnabled
	if glowEnabled == nil then glowEnabled = defDispel.glowEnabled == true end
	if not glowEnabled then
		stopDispelGlowIfActive(st, st.barGroup or self)
		return
	end
	if not (r and g and b) then
		stopDispelGlowIfActive(st, st.barGroup or self)
		return
	end

	local colorMode = dcfg.glowColorMode or defDispel.glowColorMode or "DISPEL"
	local cr, cg, cb = r, g, b
	if colorMode == "CUSTOM" then
		local col = dcfg.glowColor or defDispel.glowColor or GFH.COLOR_WHITE
		cr, cg, cb = unpackColor(col, GFH.COLOR_WHITE)
	end
	local lines = clampNumber(dcfg.glowLines or defDispel.glowLines or 8, 1, 20, 8)
	local freq = clampNumber(dcfg.glowFrequency or defDispel.glowFrequency or 0.25, -1.5, 1.5, 0.25)
	local thickness = clampNumber(dcfg.glowThickness or defDispel.glowThickness or 3, 1, 10, 3)
	local xoff = clampNumber(dcfg.glowX or defDispel.glowX or 0, -10, 10, 0)
	local yoff = clampNumber(dcfg.glowY or defDispel.glowY or 0, -10, 10, 0)
	local effect = dcfg.glowEffect or defDispel.glowEffect or "PIXEL"
	if effect ~= "PIXEL" and effect ~= "SHINE" and effect ~= "BLIZZARD" then effect = "PIXEL" end
	local scale = thickness / 3
	if scale < 0.5 then
		scale = 0.5
	elseif scale > 4 then
		scale = 4
	end

	if
		st._dispelGlowActive
		and st._dispelGlowLines == lines
		and st._dispelGlowFreq == freq
		and st._dispelGlowThickness == thickness
		and st._dispelGlowX == xoff
		and st._dispelGlowY == yoff
		and st._dispelGlowEffect == effect
		and colorKey
		and st._dispelGlowKey == colorKey
	then
		return
	end

	local target = st.barGroup or self
	stopDispelGlowIfActive(st, target)
	local glowColor = st._dispelGlowColor
	if not glowColor then
		glowColor = { 1, 1, 1, 1 }
		st._dispelGlowColor = glowColor
	end
	glowColor[1], glowColor[2], glowColor[3], glowColor[4] = cr, cg, cb, 1
	if effect == "SHINE" and LCG.AutoCastGlow_Start then
		LCG.AutoCastGlow_Start(target, glowColor, lines, freq, scale, xoff, yoff, DISPEL_GLOW_KEY)
	elseif effect == "BLIZZARD" and LCG.ButtonGlow_Start then
		LCG.ButtonGlow_Start(target, glowColor, freq)
	else
		LCG.PixelGlow_Start(target, glowColor, lines, freq, nil, thickness, xoff, yoff, nil, DISPEL_GLOW_KEY)
	end
	st._dispelGlowActive = true
	st._dispelGlowLines = lines
	st._dispelGlowFreq = freq
	st._dispelGlowThickness = thickness
	st._dispelGlowX, st._dispelGlowY = xoff, yoff
	st._dispelGlowEffect = effect
	st._dispelGlowKey = colorKey
end

function GF:UpdateRange(self, inRange)
	local st = getState(self)
	if not st then return end
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local scfg = cfg and cfg.status or {}
	local rcfg = scfg.rangeFade or {}
	if rcfg.enabled == false then
		if st.frame and st.frame.SetAlpha then st.frame:SetAlpha(1) end
		return
	end
	if IsInGroup and IsInRaid then
		local inGroup = IsInGroup()
		local inRaid = IsInRaid()
		if not inGroup and not inRaid then
			if st.frame and st.frame.SetAlpha then st.frame:SetAlpha(1) end
			return
		end
	end
	local unit = getUnit(self)
	local connected = unit and UnitIsConnected and GFH.UnsecretBool(UnitIsConnected(unit)) or nil
	if connected == false then
		local offA = rcfg.offlineAlpha or rcfg.alpha or 0.55
		if st.frame and st.frame.SetAlpha then st.frame:SetAlpha(offA) end
		return
	end
	if inRange == nil and unit and UnitInRange then inRange = UnitInRange(unit) end
	if type(inRange) ~= "nil" then
		if st.frame and st.frame.SetAlphaFromBoolean then st.frame:SetAlphaFromBoolean(inRange, 1, rcfg.alpha or 0.55) end
	end
end

function GF:UpdatePrivateAuras(self)
	if not (self and UFHelper and UFHelper.ApplyPrivateAuras) then return end
	local st = getState(self)
	if not st then return end
	local kind = self._eqolGroupKind or "party"
	local cfg = self._eqolCfg or getCfg(kind)
	local def = DEFAULTS[kind] or {}
	local pcfg = (cfg and cfg.privateAuras) or def.privateAuras
	local privateAuraParent = st.health or st.barGroup or self
	local privateAuraLevelParent = st.statusIconLayer or st.healthTextLayer or st.health or st.barGroup or self
	if not st.privateAuras then
		if not (pcfg and pcfg.enabled == true) then return end
		st.privateAuras = CreateFrame("Frame", nil, privateAuraParent)
		st.privateAuras:EnableMouse(false)
	end
	if st.privateAuras.GetParent and privateAuraParent and st.privateAuras:GetParent() ~= privateAuraParent then st.privateAuras:SetParent(privateAuraParent) end
	if not (pcfg and pcfg.enabled == true) then
		if UFHelper and UFHelper.RemovePrivateAuras then UFHelper.RemovePrivateAuras(st.privateAuras) end
		if UFHelper and UFHelper.UpdatePrivateAuraSound then UFHelper.UpdatePrivateAuraSound(st.privateAuras, nil, pcfg or {}) end
		if st.privateAuras and st.privateAuras.Hide then st.privateAuras:Hide() end
		return
	end
	local inEditMode = isEditModeActive()
	local showSample = inEditMode == true and GF._editModeSampleAuras ~= false
	if inEditMode and showSample == false then
		if UFHelper and UFHelper.RemovePrivateAuras then UFHelper.RemovePrivateAuras(st.privateAuras) end
		if UFHelper and UFHelper.UpdatePrivateAuraSound then UFHelper.UpdatePrivateAuraSound(st.privateAuras, nil, pcfg or {}) end
		if st.privateAuras and st.privateAuras.Hide then st.privateAuras:Hide() end
		return
	end
	UFHelper.ApplyPrivateAuras(st.privateAuras, self.unit, pcfg, privateAuraParent, privateAuraLevelParent, showSample)
end

function GF:UpdateHealthValue(self, unit, st)
	unit = unit or getUnit(self)
	st = st or getState(self)
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

	local leftMode = (hc.textLeft ~= nil) and hc.textLeft or defH.textLeft or "NONE"
	local centerMode = (hc.textCenter ~= nil) and hc.textCenter or defH.textCenter or "NONE"
	local rightMode = (hc.textRight ~= nil) and hc.textRight or defH.textRight or "NONE"
	local hasText = (leftMode ~= "NONE") or (centerMode ~= "NONE") or (rightMode ~= "NONE")
	local scfg = cfg and cfg.status or {}
	local us = scfg.unitStatus or {}
	local hideTextOffline = us.hideHealthTextWhenOffline == true
	local connected = unit and UnitIsConnected and GFH.UnsecretBool(UnitIsConnected(unit)) or nil
	local isDead = unit and UnitIsDeadOrGhost and GFH.UnsecretBool(UnitIsDeadOrGhost(unit)) or nil
	if hideTextOffline and connected == false then
		if st.healthTextLeft then st.healthTextLeft:SetText("") end
		if st.healthTextCenter then st.healthTextCenter:SetText("") end
		if st.healthTextRight then st.healthTextRight:SetText("") end
		st._lastHealthTextLeft, st._lastHealthTextCenter, st._lastHealthTextRight = nil, nil, nil
		st._nextHealthTextUpdateAt = nil
		return
	end
	if isDead == true then
		if st.healthTextLeft then st.healthTextLeft:SetText("") end
		if st.healthTextCenter then st.healthTextCenter:SetText("") end
		if st.healthTextRight then st.healthTextRight:SetText("") end
		st._lastHealthTextLeft, st._lastHealthTextCenter, st._lastHealthTextRight = nil, nil, nil
		st._nextHealthTextUpdateAt = nil
		return
	end
	if hasText and (st.healthTextLeft or st.healthTextCenter or st.healthTextRight) then
		local allowSecretText = secretHealth and addon.variables and addon.variables.isMidnight
		if secretHealth and not allowSecretText then
			if st.healthTextLeft then st.healthTextLeft:SetText("") end
			if st.healthTextCenter then st.healthTextCenter:SetText("") end
			if st.healthTextRight then st.healthTextRight:SetText("") end
			st._lastHealthTextLeft, st._lastHealthTextCenter, st._lastHealthTextRight = nil, nil, nil
			st._nextHealthTextUpdateAt = nil
		else
			local allowTextRefresh = true
			if secretHealth then
				local now = GetTime and GetTime() or 0
				local nextAt = st._nextHealthTextUpdateAt or 0
				if now < nextAt then
					allowTextRefresh = false
				else
					st._nextHealthTextUpdateAt = now + SECRET_TEXT_UPDATE_INTERVAL
				end
			else
				st._nextHealthTextUpdateAt = nil
			end
			if allowTextRefresh then
				local delimiter = (UFHelper and UFHelper.getTextDelimiter and UFHelper.getTextDelimiter(hc, defH)) or (hc.textDelimiter or defH.textDelimiter or " ")
				local delimiter2 = (UFHelper and UFHelper.getTextDelimiterSecondary and UFHelper.getTextDelimiterSecondary(hc, defH, delimiter))
					or (hc.textDelimiterSecondary or defH.textDelimiterSecondary or delimiter)
				local delimiter3 = (UFHelper and UFHelper.getTextDelimiterTertiary and UFHelper.getTextDelimiterTertiary(hc, defH, delimiter, delimiter2))
					or (hc.textDelimiterTertiary or defH.textDelimiterTertiary or delimiter2)
				local useShort = hc.useShortNumbers ~= false
				local hidePercentSymbol = hc.hidePercentSymbol == true
				local percentVal
				if GFH.TextModeUsesPercent(leftMode) or GFH.TextModeUsesPercent(centerMode) or GFH.TextModeUsesPercent(rightMode) then
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
				local missingValue
				if GFH.TextModeUsesDeficit(leftMode) or GFH.TextModeUsesDeficit(centerMode) or GFH.TextModeUsesDeficit(rightMode) then
					if UnitHealthMissing then missingValue = UnitHealthMissing(unit) end
					if not (issecretvalue and issecretvalue(missingValue)) then
						if missingValue == nil and not secretHealth then
							if type(cur) == "number" and type(maxv) == "number" then missingValue = maxv - cur end
						end
					end
				end
				setTextSlot(st, st.healthTextLeft, "_lastHealthTextLeft", leftMode, cur, maxv, useShort, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText, missingValue)
				setTextSlot(
					st,
					st.healthTextCenter,
					"_lastHealthTextCenter",
					centerMode,
					cur,
					maxv,
					useShort,
					percentVal,
					delimiter,
					delimiter2,
					delimiter3,
					hidePercentSymbol,
					levelText,
					missingValue
				)
				setTextSlot(st, st.healthTextRight, "_lastHealthTextRight", rightMode, cur, maxv, useShort, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText, missingValue)
			end
		end
	elseif st.healthTextLeft or st.healthTextCenter or st.healthTextRight then
		if st.healthTextLeft then st.healthTextLeft:SetText("") end
		if st.healthTextCenter then st.healthTextCenter:SetText("") end
		if st.healthTextRight then st.healthTextRight:SetText("") end
		st._lastHealthTextLeft, st._lastHealthTextCenter, st._lastHealthTextRight = nil, nil, nil
		st._nextHealthTextUpdateAt = nil
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
		r, g, b, a = unpackColor(hc.color, defH.color or GFH.COLOR_HEALTH_DEFAULT)
	elseif hc.useClassColor == true then
		if not st._classR then GF:EnsureUnitClassColor(self, st, unit) end
		if st._classR then
			r, g, b, a = st._classR, st._classG, st._classB, st._classA or 1
		else
			r, g, b, a = unpackColor(hc.color, defH.color or GFH.COLOR_HEALTH_DEFAULT)
		end
	else
		r, g, b, a = unpackColor(hc.color, defH.color or GFH.COLOR_HEALTH_DEFAULT)
	end

	local connected = UnitIsConnected and GFH.UnsecretBool(UnitIsConnected(unit))
	if connected == false then
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
	local showPower = shouldShowPowerForUnit(pcfg, unit, st)
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

function GF:UpdatePowerValue(self, unit, st)
	unit = unit or getUnit(self)
	st = st or getState(self)
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
				if GFH.TextModeUsesPercent(leftMode) or GFH.TextModeUsesPercent(centerMode) or GFH.TextModeUsesPercent(rightMode) then
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

	if UFHelper and UFHelper.configureSpecialTexture then
		local needsAtlas = (powerTexKey == nil or powerTexKey == "" or powerTexKey == "DEFAULT")
		if st._lastPowerToken ~= powerKey or texChanged or needsAtlas then UFHelper.configureSpecialTexture(st.power, powerKey, powerTexKey, pcfg, powerType) end
	end
	st._lastPowerToken = powerKey
	st._lastPowerTexture = powerTexKey
	stabilizeStatusBarTexture(st.power)
	if st.power.SetStatusBarDesaturated and UFHelper and UFHelper.isPowerDesaturated then
		local desat = UFHelper.isPowerDesaturated(powerType, powerToken)
		if st._lastPowerDesat ~= desat then
			st._lastPowerDesat = desat
			st.power:SetStatusBarDesaturated(desat)
		end
	end
	local pr, pg, pb, pa
	if UFHelper and UFHelper.getPowerColor then
		pr, pg, pb, pa = UFHelper.getPowerColor(powerType, powerToken)
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
	GF:UpdateStatusText(self)
	GF:UpdateLevel(self)
	GF:UpdateHealth(self)
	GF:UpdatePower(self)
	GF:UpdateRoleIcon(self)
	GF:UpdateRaidIcon(self)
	GF:UpdateGroupIcons(self)
	GF:UpdateStatusIcons(self)
	GF:UpdateAuras(self)
	GF:UpdateRange(self)
	GF:UpdateHighlightState(self)
end

GF._dropdown = GF._dropdown or nil

local function ensureDropDown()
	if GF._dropdown and GF._dropdown.GetName then return GF._dropdown end
	GF._dropdown = CreateFrame("Frame", "EQOLUFGroupDropDown", UIParent, "UIDropDownMenuTemplate")
	return GF._dropdown
end

local function resolveMenuType(unit)
	if unit == "player" then return "SELF" end
	if UnitIsUnit and UnitIsUnit(unit, "player") then return "SELF" end
	if UnitInRaid and UnitInRaid(unit) then return "RAID_PLAYER" end
	if UnitInParty and UnitInParty(unit) then return "PARTY" end
	return "RAID_PLAYER"
end

function GF:OpenUnitMenu(self)
	local unit = getUnit(self)
	if not unit then return end

	if UnitPopup_OpenMenu then
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

function GF.UnitButton_OnLoad(self)
	local parent = self and self.GetParent and self:GetParent()
	if parent and parent._eqolKind then self._eqolGroupKind = parent._eqolKind end

	GF:BuildButton(self)

	local unit = getUnit(self)
	if unit then
		GF:UnitButton_SetUnit(self, unit)
	else
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
		st._auraQueryMax = nil
		clearDispelAuraState(st)
	end
	GF:CacheUnitStatic(self)

	GF:UnitButton_RegisterUnitEvents(self, unit)
	if self._eqolUFState and self._eqolUFState._wantsAbsorb then GF:UpdateAbsorbCache(self) end
	GF:UpdatePrivateAuras(self)

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
		GFH.CancelReadyCheckIconTimer(st)
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
		st._auraQueryMax = nil
		st._lastSummonAtlas = nil
		st._summonActiveReal = false
		st._phaseReason = nil
		clearDispelAuraState(st)
	end
	if st and st.privateAuras and UFHelper then
		if UFHelper.RemovePrivateAuras then UFHelper.RemovePrivateAuras(st.privateAuras) end
		if UFHelper.UpdatePrivateAuraSound then UFHelper.UpdatePrivateAuraSound(st.privateAuras, nil, (self._eqolCfg and self._eqolCfg.privateAuras) or {}) end
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
	if self._eqolUFState and self._eqolUFState._wantsStatusText then reg("UNIT_FLAGS") end
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

	if self._eqolUFState and (self._eqolUFState._wantsAuras or self._eqolUFState._wantsDispelTint) then reg("UNIT_AURA") end
	if self._eqolUFState and self._eqolUFState._wantsRangeFade then reg("UNIT_IN_RANGE_UPDATE") end
	reg("INCOMING_SUMMON_CHANGED")
	reg("INCOMING_RESURRECT_CHANGED")
	reg("UNIT_PHASE")
end

function GF.UnitButton_OnAttributeChanged(self, name, value)
	if name ~= "unit" then return end
	if value == nil or value == "" then
		GF:UnitButton_ClearUnit(self)
		GF:UpdateAll(self)
		return
	end
	if self.unit == value then return end
	GF:UnitButton_SetUnit(self, value)
end

local function dispatchUnitHealth(btn, unit)
	local st = getState(btn)
	GF:UpdateHealthValue(btn, unit, st)
	GF:UpdateStatusText(btn, unit, st)
end
local function dispatchUnitAbsorb(btn, unit)
	local st = getState(btn)
	GF:UpdateAbsorbCache(btn, "absorb", unit, st)
	GF:UpdateHealthValue(btn, unit, st)
end
local function dispatchUnitHealAbsorb(btn, unit)
	local st = getState(btn)
	GF:UpdateAbsorbCache(btn, "heal", unit, st)
	GF:UpdateHealthValue(btn, unit, st)
end
local function dispatchUnitPower(btn, unit)
	local st = getState(btn)
	GF:UpdatePowerValue(btn, unit, st)
end
local function dispatchUnitDisplayPower(btn) GF:UpdatePower(btn) end
local function dispatchUnitName(btn)
	GF:CacheUnitStatic(btn)
	GF:UpdateName(btn)
	GF:UpdateHealthStyle(btn)
	GF:UpdateLevel(btn)
end
local function dispatchUnitLevel(btn, unit)
	local st = getState(btn)
	GF:UpdateLevel(btn, unit, st)
	GF:UpdateHealthValue(btn, unit, st)
	GF:UpdatePowerValue(btn, unit, st)
end
local function dispatchUnitConnection(btn, unit)
	local st = getState(btn)
	GF:CacheUnitStatic(btn)
	GF:UpdateHealthStyle(btn, unit, st)
	GF:UpdateHealthValue(btn, unit, st)
	GF:UpdatePowerValue(btn, unit, st)
	GF:UpdateName(btn, unit, st)
	GF:UpdateStatusText(btn, unit, st)
	GF:UpdateLevel(btn, unit, st)
	GF:UpdateRange(btn, nil, unit, st)
end
local function dispatchUnitFlags(btn) GF:UpdateStatusText(btn) end
local function dispatchUnitRange(btn, _, inRange) GF:UpdateRange(btn, inRange) end
local function dispatchUnitAura(btn, _, updateInfo) GF:RequestAuraUpdate(btn, updateInfo) end

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
	UNIT_FLAGS = dispatchUnitFlags,
	UNIT_IN_RANGE_UPDATE = dispatchUnitRange,
	UNIT_AURA = dispatchUnitAura,
	INCOMING_SUMMON_CHANGED = function(btn)
		GF:UpdateSummonIcon(btn)
		GF:UpdateResurrectIcon(btn)
	end,
	INCOMING_RESURRECT_CHANGED = function(btn) GF:UpdateResurrectIcon(btn) end,
	UNIT_PHASE = function(btn) GF:UpdatePhaseIcon(btn) end,
}

function GF.UnitButton_OnEvent(self, event, unit, ...)
	if not isFeatureEnabled() then return end
	local u = getUnit(self)
	if not u or (unit and unit ~= u) then return end

	local fn = UNIT_DISPATCH[event]
	if fn then fn(self, u, ...) end
end

function GF.UnitButton_OnEnter(self)
	local st = getState(self)
	if st then
		st._hovered = true
		GF:UpdateHighlightState(self)
	end
	if not shouldShowTooltip(self) then return end
	local unit = getUnit(self)
	if not unit then return end
	if not GameTooltip or GameTooltip:IsForbidden() then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetUnit(unit)
	GameTooltip:Show()
end

function GF.UnitButton_OnLeave(self)
	local st = getState(self)
	if st then
		st._hovered = false
		GF:UpdateHighlightState(self)
	end
	if GameTooltip and not GameTooltip:IsForbidden() then GameTooltip:Hide() end
end

local setPointFromCfg = GFH.SetPointFromCfg

local function cancelQueuedGroupIndicatorRefresh()
	local timer = GF._groupIndicatorRefreshTimer
	if timer and timer.Cancel then timer:Cancel() end
	GF._groupIndicatorRefreshTimer = nil
end

local function queueGroupIndicatorRefresh(delay, repeats)
	if not isFeatureEnabled() then return end
	cancelQueuedGroupIndicatorRefresh()
	local wait = tonumber(delay) or 0
	local remaining = tonumber(repeats) or 1
	if remaining < 1 then remaining = 1 end

	local function run()
		GF._groupIndicatorRefreshTimer = nil
		if not isFeatureEnabled() then return end
		if InCombatLockdown and InCombatLockdown() then
			GF._pendingRefresh = true
			return
		end
		GF:RefreshGroupIndicators()
		remaining = remaining - 1
		if remaining > 0 and C_Timer and C_Timer.NewTimer then GF._groupIndicatorRefreshTimer = C_Timer.NewTimer(0.12, run) end
	end

	if C_Timer and C_Timer.NewTimer then
		GF._groupIndicatorRefreshTimer = C_Timer.NewTimer(wait, run)
	else
		run()
	end
end

local function nudgeHeaderLayout(header)
	if not header or not header.SetAttribute then return end
	if InCombatLockdown and InCombatLockdown() then
		header._eqolPendingLayout = true
		return
	end
	local nonce = (header:GetAttribute("eqolLayoutNonce") or 0) + 1
	header:SetAttribute("eqolLayoutNonce", nonce)
	header._eqolPendingLayout = nil
	if header._eqolKind == "raid" then queueGroupIndicatorRefresh(0, 4) end
end

local getGrowthStartPoint = GFH.GetGrowthStartPoint

local function isRaidLikeKind(kind) return kind == "raid" or kind == "mt" or kind == "ma" end

local function isSplitRoleKind(kind) return kind == "mt" or kind == "ma" end

local function getSplitRoleFilter(kind)
	if kind == "mt" then return "MAINTANK" end
	if kind == "ma" then return "MAINASSIST" end
	return nil
end

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
	elseif kind == "mt" then
		name = "EQOLUFMTAnchor"
	elseif kind == "ma" then
		name = "EQOLUFMAAnchor"
	end
	if not name then return nil end

	anchor = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
	anchor._eqolKind = kind
	anchor:EnableMouse(false)
	anchor:SetFrameStrata("MEDIUM")
	anchor:SetFrameLevel(1)

	if anchor.SetBackdrop then
		anchor:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			tile = false,
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

	local scale = GFH.GetEffectiveScale(UIParent)

	local w = clampNumber(tonumber(cfg.width) or 100, 40, 600, 100)
	local h = clampNumber(tonumber(cfg.height) or 24, 10, 200, 24)
	w = roundToEvenPixel(w, scale)
	h = roundToEvenPixel(h, scale)

	local spacing = roundToPixel(clampNumber(tonumber(cfg.spacing) or 0, 0, 40, 0), scale)
	local columnSpacing = spacing
	if isRaidLikeKind(kind) then columnSpacing = roundToPixel(clampNumber(tonumber(cfg.columnSpacing) or spacing, 0, 40, spacing), scale) end
	local growth = (cfg.growth or "DOWN"):upper()

	local unitsPer = 5
	local columns = 1
	if isRaidLikeKind(kind) then
		unitsPer = max(1, floor(clampNumber(tonumber(cfg.unitsPerColumn) or 5, 1, 10, 5) + 0.5))
		columns = max(1, floor(clampNumber(tonumber(cfg.maxColumns) or 8, 1, 10, 8) + 0.5))
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

	totalW = roundToEvenPixel(totalW, scale)
	totalH = roundToEvenPixel(totalH, scale)

	anchor:SetSize(totalW, totalH)
end

local function applyVisibility(header, kind, cfg)
	if not header or not cfg then return end
	local def = DEFAULTS[kind]
	local hideInClientScene = GFH and GFH.ShouldHideInClientScene and GFH.ShouldHideInClientScene(cfg, def)
	local inEdit = isEditModeActive and isEditModeActive()
	local forceClientSceneHide = not inEdit and hideInClientScene and GF._clientSceneActive == true
	if GFH and GFH.ApplyClientSceneAlphaToFrame then GFH.ApplyClientSceneAlphaToFrame(header, forceClientSceneHide) end
	if not RegisterStateDriver then return end
	if InCombatLockdown and InCombatLockdown() then return end

	if UnregisterStateDriver then UnregisterStateDriver(header, "visibility") end

	if cfg.enabled ~= true then
		RegisterStateDriver(header, "visibility", "hide")
		header._eqolVisibilityCond = "hide"
		return
	end

	local cond = "hide"
	if header._eqolForceHide or header._eqolSpecialHide or forceClientSceneHide then
		cond = "hide"
	elseif header._eqolForceShow then
		cond = "show"
	elseif kind == "party" then
		if cfg.showSolo then
			cond = "[group:raid] hide; show"
		else
			cond = "[group:raid] hide; [group:party] show; hide"
		end
	elseif isRaidLikeKind(kind) then
		cond = "[group:raid] show; hide"
	end

	RegisterStateDriver(header, "visibility", cond)
	header._eqolVisibilityCond = cond
end

local function getRaidGroupHeaderKey(index) return "raidGroup" .. tostring(index) end

function GF:EnsureRaidGroupHeaders()
	GF._raidGroupHeaders = GF._raidGroupHeaders or {}
	local parent = _G.PetBattleFrameHider or UIParent
	for i = 1, 8 do
		local header = GF._raidGroupHeaders[i]
		if not header then
			header = CreateFrame("Frame", "EQOLUFRaidGroupHeader" .. i, parent, "SecureGroupHeaderTemplate")
			header._eqolKind = "raid"
			header._eqolGroupIndex = i
			header:Hide()
			GF._raidGroupHeaders[i] = header
			GF.headers[getRaidGroupHeaderKey(i)] = header
		end
		if header and not header._eqolLayoutHooked then
			header._eqolLayoutHooked = true
			header:HookScript("OnShow", function(self)
				if self._eqolPendingLayout then nudgeHeaderLayout(self) end
			end)
		end
	end
	return GF._raidGroupHeaders
end

function GF:EnsurePreviewFrames(kind)
	if kind ~= "party" and kind ~= "raid" and kind ~= "mt" and kind ~= "ma" then return nil end
	local cfg = getCfg(kind)
	if not (cfg and cfg.enabled == true) then return nil end
	local samples = PREVIEW_SAMPLES[kind]
	if not (samples and #samples > 0) then return nil end
	if InCombatLockdown and InCombatLockdown() then return nil end
	local anchor = GF.anchors and GF.anchors[kind]
	if not anchor then return nil end
	GF._previewFrames = GF._previewFrames or {}
	local frames = GF._previewFrames[kind]
	if not frames then frames = {} end
	GF._previewFrames[kind] = frames
	for i = 1, #samples do
		local btn = frames[i]
		if not btn then
			btn = CreateFrame("Button", nil, anchor, "EQOLUFGroupUnitButtonTemplate")
			frames[i] = btn
		end
		btn._eqolGroupKind = kind
		btn._eqolPreview = true
		btn._eqolPreviewIndex = i
		btn:SetFrameStrata(anchor:GetFrameStrata())
		btn:SetFrameLevel((anchor:GetFrameLevel() or 1) + 1)
		local st = getState(btn)
		local sample = samples[i] or {}
		st._previewRole = sample.role or "DAMAGER"
		st._previewClass = sample.class
		st._previewName = sample.name or sample.class or "Unit"
		st._previewGroup = sample.group
		st._previewIndex = i
		GF:UnitButton_SetUnit(btn, "player")
	end
	for i = #samples + 1, #frames do
		local btn = frames[i]
		if btn then
			GF:UnitButton_ClearUnit(btn)
			btn:Hide()
		end
		frames[i] = nil
	end
	return frames
end

function GF:UpdatePreviewLayout(kind)
	local frames = GF._previewFrames and GF._previewFrames[kind]
	local anchor = GF.anchors and GF.anchors[kind]
	if not (frames and anchor) then return end
	local cfg = getCfg(kind)
	if not (cfg and cfg.enabled == true) then
		GF:ShowPreviewFrames(kind, false)
		return
	end
	local raidStyle = isRaidLikeKind(kind)
	local sampleLimit = (kind == "raid" and ((GF._previewSampleSize and GF._previewSampleSize[kind]) or 10)) or nil
	local samples = (GFH.BuildPreviewSampleList and GFH.BuildPreviewSampleList(kind, cfg, PREVIEW_SAMPLES[kind], sampleLimit, 2, 3)) or (PREVIEW_SAMPLES[kind] or {})
	GF._previewSampleCount = GF._previewSampleCount or {}
	GF._previewSampleCount[kind] = #samples

	local scale = GFH.GetEffectiveScale(UIParent)

	-- Keep preview frames pixel-perfect as well (otherwise sample-mode text can jitter / drift).
	local w = clampNumber(tonumber(cfg.width) or 100, 40, 600, 100)
	local h = clampNumber(tonumber(cfg.height) or 24, 10, 200, 24)
	w = roundToEvenPixel(w, scale)
	h = roundToEvenPixel(h, scale)

	local spacing = clampNumber(tonumber(cfg.spacing) or 0, 0, 40, 0)
	local growth = (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(cfg.growth, "DOWN")) or "DOWN"
	spacing = roundToPixel(spacing, scale)

	local startPoint = getGrowthStartPoint(growth)
	local isHorizontal = (growth == "RIGHT" or growth == "LEFT")
	local xSign = (growth == "LEFT") and -1 or 1
	local ySign = (growth == "UP") and 1 or -1
	local unitsPerColumn = 1
	local maxColumns = 1
	local viewportColumns = 1
	local columnSpacing = spacing
	local useGroupedPreview = false
	local groupedPreviewEntries
	local groupGrowth
	local previewScale = 1
	if raidStyle then
		unitsPerColumn = max(1, floor(clampNumber(tonumber(cfg.unitsPerColumn) or 5, 1, 10, 5) + 0.5))
		maxColumns = max(1, floor(clampNumber(tonumber(cfg.maxColumns) or 8, 1, 10, 8) + 0.5))
		viewportColumns = maxColumns
		columnSpacing = roundToPixel(clampNumber(tonumber(cfg.columnSpacing) or spacing, 0, 40, spacing), scale)
		if kind == "raid" then
			local sortMethod = resolveSortMethod(cfg)
			local customSort = GFH and GFH.EnsureCustomSortConfig and GFH.EnsureCustomSortConfig(cfg)
			useGroupedPreview = GF:IsRaidGroupedLayout(cfg) and (sortMethod ~= "NAMELIST" or (customSort and customSort.enabled == true))
			if useGroupedPreview then
				local defaultGroupGrowth = DEFAULTS and DEFAULTS.raid and DEFAULTS.raid.groupGrowth
				if GFH.ResolveGroupGrowthDirection then
					groupGrowth = GFH.ResolveGroupGrowthDirection(cfg and cfg.groupGrowth, growth, defaultGroupGrowth)
				else
					groupGrowth = (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(cfg and cfg.groupGrowth, nil)) or ((growth == "RIGHT" or growth == "LEFT") and "DOWN" or "RIGHT")
				end
				startPoint = (GFH.GetGroupGrowthStartPoint and GFH.GetGroupGrowthStartPoint(groupGrowth)) or getGrowthStartPoint(groupGrowth)
			end
		end
	end
	local maxShown
	if raidStyle and useGroupedPreview then
		local buckets = {}
		local seenGroups = {}
		for _, sample in ipairs(samples) do
			local group = tonumber(sample and sample.group)
			if group and group >= 1 and group <= 8 then
				local bucket = buckets[group]
				if not bucket then
					bucket = {}
					buckets[group] = bucket
				end
				bucket[#bucket + 1] = sample
				seenGroups[group] = true
			end
		end
		local orderedGroups = {}
		local added = {}
		local ordering = (cfg and cfg.groupingOrder) or (GFH and GFH.GROUP_ORDER) or "1,2,3,4,5,6,7,8"
		if type(ordering) == "string" and ordering ~= "" then
			for token in ordering:gmatch("[^,]+") do
				local group = tonumber((tostring(token):gsub("^%s+", ""):gsub("%s+$", "")))
				if group and seenGroups[group] and not added[group] then
					added[group] = true
					orderedGroups[#orderedGroups + 1] = group
				end
			end
		end
		for group = 1, 8 do
			if seenGroups[group] and not added[group] then
				added[group] = true
				orderedGroups[#orderedGroups + 1] = group
			end
		end
		local blockCount = #orderedGroups
		local perGroupWidth, perGroupHeight
		if isHorizontal then
			perGroupWidth = w * unitsPerColumn + spacing * max(0, unitsPerColumn - 1)
			perGroupHeight = h
		else
			perGroupWidth = w
			perGroupHeight = h * unitsPerColumn + spacing * max(0, unitsPerColumn - 1)
		end
		previewScale = (GFH.GetRaidViewportScaleForGroups and GFH.GetRaidViewportScaleForGroups(groupGrowth, perGroupWidth, perGroupHeight, columnSpacing, viewportColumns, blockCount)) or 1
		groupedPreviewEntries = {}
		for blockIndex = 1, blockCount do
			local group = orderedGroups[blockIndex]
			local bucket = buckets[group]
			if bucket then
				for unitIndex = 1, min(#bucket, unitsPerColumn) do
					groupedPreviewEntries[#groupedPreviewEntries + 1] = {
						sample = bucket[unitIndex],
						group = group,
						groupIndex = blockIndex,
						unitIndex = unitIndex,
					}
				end
			end
		end
		maxShown = min(#frames, #groupedPreviewEntries)
	elseif raidStyle then
		local limit = #samples
		if kind == "raid" then limit = tonumber(GF._previewSampleSize and GF._previewSampleSize[kind]) or 10 end
		maxShown = min(#frames, limit, #samples)
		local requiredColumns = max(1, ceil(maxShown / max(1, unitsPerColumn)))
		previewScale = (GFH.GetRaidViewportScaleForColumns and GFH.GetRaidViewportScaleForColumns(growth, w, h, spacing, columnSpacing, viewportColumns, requiredColumns)) or 1
	else
		maxShown = min(#frames, #samples)
	end
	local visualScale = previewScale
	if visualScale <= 0 then visualScale = 1 end
	local visualW, visualH = w, h
	local visualSpacing = spacing
	local visualColumnSpacing = columnSpacing
	if visualScale < 1 then
		if isHorizontal then
			visualW = w / visualScale
		else
			visualH = h / visualScale
		end
		visualSpacing = spacing / visualScale
	end
	visualW = roundToEvenPixel(max(1, visualW), scale)
	visualH = roundToEvenPixel(max(1, visualH), scale)
	visualSpacing = roundToPixel(visualSpacing, scale)
	visualColumnSpacing = roundToPixel(visualColumnSpacing, scale)
	for i, btn in ipairs(frames) do
		if btn then
			local groupedEntry = groupedPreviewEntries and groupedPreviewEntries[i]
			local sample = groupedEntry and groupedEntry.sample or samples[i]
			if i > maxShown or not sample then
				if btn.SetScale then btn:SetScale(1) end
				btn:Hide()
			else
				local st = getState(btn)
				if st then
					st._previewRole = sample.role or "DAMAGER"
					st._previewClass = sample.class
					st._previewName = sample.name or sample.class or "Unit"
					st._previewGroup = (groupedEntry and groupedEntry.group) or sample.group
					st._previewIndex = (groupedEntry and groupedEntry.unitIndex) or i
				end
				btn._eqolGroupKind = kind
				btn._eqolCfg = cfg
				updateButtonConfig(btn, cfg)
				btn:SetSize(visualW, visualH)
				if btn.SetScale then btn:SetScale(visualScale) end
				btn:ClearAllPoints()
				if raidStyle and groupedEntry then
					local groupIndex = groupedEntry.groupIndex - 1
					local unitIndex = groupedEntry.unitIndex - 1
					local groupOffsetX, groupOffsetY = 0, 0
					local groupWidth, groupHeight
					if isHorizontal then
						groupWidth = visualW * unitsPerColumn + visualSpacing * max(0, unitsPerColumn - 1)
						groupHeight = visualH
					else
						groupWidth = visualW
						groupHeight = visualH * unitsPerColumn + visualSpacing * max(0, unitsPerColumn - 1)
					end
					groupWidth = roundToPixel(groupWidth, scale)
					groupHeight = roundToPixel(groupHeight, scale)
					if groupGrowth == "LEFT" then
						groupOffsetX = roundToPixel(groupIndex * (groupWidth + visualColumnSpacing) * -1, scale)
					elseif groupGrowth == "UP" then
						groupOffsetY = roundToPixel(groupIndex * (groupHeight + visualColumnSpacing), scale)
					elseif groupGrowth == "RIGHT" then
						groupOffsetX = roundToPixel(groupIndex * (groupWidth + visualColumnSpacing), scale)
					else
						groupOffsetY = roundToPixel(groupIndex * (groupHeight + visualColumnSpacing) * -1, scale)
					end
					local unitOffsetX, unitOffsetY = 0, 0
					if isHorizontal then
						unitOffsetX = roundToPixel(unitIndex * (visualW + visualSpacing) * xSign, scale)
					else
						unitOffsetY = roundToPixel(unitIndex * (visualH + visualSpacing) * ySign, scale)
					end
					btn:SetPoint(startPoint, anchor, startPoint, groupOffsetX + unitOffsetX, groupOffsetY + unitOffsetY)
				elseif raidStyle then
					local idx = i - 1
					local row = idx % unitsPerColumn
					local col = floor(idx / unitsPerColumn)
					if isHorizontal then
						btn:SetPoint(startPoint, anchor, startPoint, roundToPixel(row * (visualW + visualSpacing) * xSign, scale), roundToPixel(col * (visualH + visualColumnSpacing) * -1, scale))
					else
						btn:SetPoint(startPoint, anchor, startPoint, roundToPixel(col * (visualW + visualColumnSpacing), scale), roundToPixel(row * (visualH + visualSpacing) * ySign, scale))
					end
				else
					if isHorizontal then
						btn:SetPoint(startPoint, anchor, startPoint, roundToPixel((i - 1) * (visualW + visualSpacing) * xSign, scale), 0)
					else
						btn:SetPoint(startPoint, anchor, startPoint, 0, roundToPixel((i - 1) * (visualH + visualSpacing) * ySign, scale))
					end
				end
				GF:CacheUnitStatic(btn)
				GF:LayoutAuras(btn)
				if btn.unit then GF:UnitButton_RegisterUnitEvents(btn, btn.unit) end
				if btn._eqolUFState then
					GF:LayoutButton(btn)
					GF:UpdateAll(btn)
					if btn._eqolPreview then GF:UpdateAuras(btn) end
				end
				btn:Show()
			end
		end
	end
	if kind == "raid" then GF:RefreshGroupIndicators() end
end

function GF:ShowPreviewFrames(kind, show)
	local frames = GF._previewFrames and GF._previewFrames[kind]
	if not frames then return end
	local maxShown = #frames
	if kind == "raid" then maxShown = min(maxShown, tonumber(GF._previewSampleSize and GF._previewSampleSize[kind]) or 10) end
	local sampleCount = GF._previewSampleCount and GF._previewSampleCount[kind]
	if sampleCount then maxShown = min(maxShown, sampleCount) end
	for i, btn in ipairs(frames) do
		if btn then
			if show and i <= maxShown then
				if not btn.unit then GF:UnitButton_SetUnit(btn, "player") end
				btn:Show()
			else
				GF:UnitButton_ClearUnit(btn)
				btn:Hide()
			end
		end
	end
	if kind == "raid" then GF:RefreshGroupIndicators() end
end

local function getCustomSortEditor()
	if GF._customSortEditor then return GF._customSortEditor end
	if not (GFH and GFH.CreateCustomSortEditor) then return nil end
	local function getEditorKind()
		local kind = GF._customSortEditorKind
		if kind ~= "party" and kind ~= "raid" then kind = "raid" end
		return kind
	end
	GF._customSortEditor = GFH.CreateCustomSortEditor({
		roleTokens = GFH.ROLE_TOKENS,
		classTokens = GFH.CLASS_TOKENS,
		subtitle = "Drag entries to reorder. Applies to Party and Raid custom sorting.",
		getOrders = function()
			local cfg = getCfg(getEditorKind())
			local custom = GFH.EnsureCustomSortConfig(cfg)
			return custom and custom.roleOrder, custom and custom.classOrder
		end,
		onReorder = function(listKey, order)
			local kind = getEditorKind()
			local cfg = getCfg(kind)
			local custom = GFH.EnsureCustomSortConfig(cfg)
			if not custom then return end
			if listKey == "role" then
				custom.roleOrder = order
			else
				custom.classOrder = order
			end
			GF:ApplyHeaderAttributes(kind)
			GF:RefreshCustomSortNameList(kind)
			if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end
		end,
	})
	return GF._customSortEditor
end

function GF:ToggleCustomSortEditor(kind)
	if not isEditModeActive() and not (EditMode and EditMode.IsAvailable and EditMode:IsAvailable()) then return end
	kind = tostring(kind or "raid"):lower()
	if kind ~= "party" and kind ~= "raid" then kind = "raid" end
	GF._customSortEditorKind = kind
	local cfg = getCfg(kind)
	if not cfg then return end
	local custom = GFH.EnsureCustomSortConfig(cfg)
	if custom and (custom.enabled ~= true or resolveSortMethod(cfg) ~= "NAMELIST") then
		custom.enabled = true
		cfg.sortMethod = "NAMELIST"
		if EditMode and EditMode.SetValue then
			local editModeId = EDITMODE_IDS and EDITMODE_IDS[kind] or nil
			if editModeId then
				EditMode:SetValue(editModeId, "sortMethod", "CUSTOM", nil, true)
				EditMode:SetValue(editModeId, "customSortEnabled", true, nil, true)
			end
		end
		GF:ApplyHeaderAttributes(kind)
		GF:RefreshCustomSortNameList(kind)
		if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end
		if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RequestRefreshSettings then addon.EditModeLib.internal:RequestRefreshSettings() end
	end

	local editor = getCustomSortEditor()
	if not editor then return end
	if editor.Title and editor.Title.SetText then
		local label = (kind == "party" and (PARTY or "Party")) or (RAID or "Raid")
		editor.Title:SetText("Custom Sort Order (" .. label .. ")")
	end
	local sameKind = editor._eqolKind == kind
	editor._eqolKind = kind
	if editor:IsShown() and sameKind then
		editor:Hide()
	else
		editor:Refresh()
		editor:Show()
	end
	if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RequestRefreshSettings then addon.EditModeLib.internal:RequestRefreshSettings() end
end

function GF:SetEditModeSampleFrames(kind, show)
	if kind ~= "party" and kind ~= "raid" and kind ~= "mt" and kind ~= "ma" then return end
	GF._editModeSampleFrames = GF._editModeSampleFrames or {}
	local enabled = show == true
	if GF._editModeSampleFrames[kind] == enabled then return end
	GF._editModeSampleFrames[kind] = enabled
	if not isEditModeActive() then return end
	GF:EnsureHeaders()
	local header = GF.headers and GF.headers[kind]
	if not header then return end
	if enabled and not (InCombatLockdown and InCombatLockdown()) then
		if kind == "raid" then
			GF._previewSampleSize = GF._previewSampleSize or {}
			if not GF._previewSampleSize[kind] then GF._previewSampleSize[kind] = 10 end
		end
		header._eqolForceShow = nil
		header._eqolForceHide = true
		GF._previewActive = GF._previewActive or {}
		GF._previewActive[kind] = true
		GF:EnsurePreviewFrames(kind)
		GF:UpdatePreviewLayout(kind)
		GF:ShowPreviewFrames(kind, true)
	else
		if GF._previewActive then GF._previewActive[kind] = nil end
		GF:ShowPreviewFrames(kind, false)
		header._eqolForceHide = nil
		header._eqolForceShow = true
	end
	GF:ApplyHeaderAttributes(kind)
end

function GF:ToggleEditModeSampleFrames(kind)
	local enabled = GF._editModeSampleFrames and GF._editModeSampleFrames[kind]
	GF:SetEditModeSampleFrames(kind, enabled ~= true)
end

function GF:CycleEditModeSampleSize(kind)
	if kind ~= "raid" then return end
	local sizes = { 10, 20, 30, 40 }
	GF._previewSampleSize = GF._previewSampleSize or {}
	local current = tonumber(GF._previewSampleSize[kind]) or 0
	local idx = 0
	for i, size in ipairs(sizes) do
		if size == current then
			idx = i
			break
		end
	end
	local nextSize = sizes[(idx % #sizes) + 1]
	GF._previewSampleSize[kind] = nextSize
	if isEditModeActive() and GF._previewActive and GF._previewActive[kind] then
		GF:EnsurePreviewFrames(kind)
		GF:UpdatePreviewLayout(kind)
		GF:ShowPreviewFrames(kind, true)
	end
end

local function forEachChild(header, fn)
	if not header or not fn then return end
	if not header.GetAttribute then return end

	local index = 1
	local child = header:GetAttribute("child" .. index)
	while child do
		fn(child, index)
		index = index + 1
		child = header:GetAttribute("child" .. index)
	end
end

local function syncHeaderChild(child, kind, cfg, frameW, frameH)
	if not (child and cfg) then return end

	child._eqolGroupKind = kind
	child._eqolCfg = cfg
	updateButtonConfig(child, cfg)
	if frameW and frameH and child.SetSize then
		local inCombat = InCombatLockdown and InCombatLockdown()
		if not inCombat then
			local w = tonumber(frameW) or 0
			local h = tonumber(frameH) or 0
			if w > 0 and h > 0 then
				local cw, ch = child:GetSize()
				if abs((cw or 0) - w) > 0.01 or abs((ch or 0) - h) > 0.01 then child:SetSize(w, h) end
			end
		end
	end
	GF:LayoutAuras(child)
	if child.unit then GF:UnitButton_RegisterUnitEvents(child, child.unit) end
	if child._eqolUFState then
		GF:CacheUnitStatic(child)
		GF:LayoutButton(child)
		GF:UpdateAll(child)
	end
end

local function refreshAllAuras()
	for _, header in pairs(GF.headers or {}) do
		forEachChild(header, function(child)
			if child then GF:UpdateAuras(child) end
		end)
	end
	if GF._previewFrames then
		for _, frames in pairs(GF._previewFrames) do
			for _, btn in ipairs(frames) do
				if btn then GF:UpdateAuras(btn) end
			end
		end
	end
end

local function refreshAllPrivateAuras()
	for _, header in pairs(GF.headers or {}) do
		forEachChild(header, function(child)
			if child then GF:UpdatePrivateAuras(child) end
		end)
	end
	if GF._previewFrames then
		for _, frames in pairs(GF._previewFrames) do
			for _, btn in ipairs(frames) do
				if btn then GF:UpdatePrivateAuras(btn) end
			end
		end
	end
end

function GF:SetEditModeSampleAuras(show)
	local enabled = show ~= false
	if GF._editModeSampleAuras == enabled then return end
	GF._editModeSampleAuras = enabled
	if not isEditModeActive() then return end
	refreshAllAuras()
	refreshAllPrivateAuras()
end

function GF:ToggleEditModeSampleAuras() GF:SetEditModeSampleAuras(GF._editModeSampleAuras == false) end

function GF:SetEditModeStatusText(show)
	local enabled = show ~= false
	if GF._editModeSampleStatusText == enabled then return end
	GF._editModeSampleStatusText = enabled
	if not isEditModeActive() then return end
	for _, header in pairs(GF.headers or {}) do
		forEachChild(header, function(child)
			if child then GF:UpdateStatusText(child) end
		end)
	end
	if GF._previewFrames then
		for _, frames in pairs(GF._previewFrames) do
			for _, btn in ipairs(frames) do
				if btn then GF:UpdateStatusText(btn) end
			end
		end
	end
end

function GF:ToggleEditModeStatusText() GF:SetEditModeStatusText(GF._editModeSampleStatusText == false) end

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

function GF:RefreshStatusText()
	if not isFeatureEnabled() then return end
	for _, header in pairs(GF.headers or {}) do
		forEachChild(header, function(child)
			if child then GF:UpdateStatusText(child) end
		end)
	end
	if GF._previewFrames then
		for _, frames in pairs(GF._previewFrames) do
			for _, btn in ipairs(frames) do
				if btn then GF:UpdateStatusText(btn) end
			end
		end
	end
end

function GF:RefreshGroupIndicators()
	if not isFeatureEnabled() then return end
	local cfg = getCfg("raid")
	if not cfg then return end
	local def = DEFAULTS.raid or {}
	local header = GF.headers and GF.headers.raid
	local sortMethod = resolveSortMethod(cfg)
	local customSort = GFH and GFH.EnsureCustomSortConfig and GFH.EnsureCustomSortConfig(cfg)
	local useGroupedHeaders = GF:IsRaidGroupedLayout(cfg) and (sortMethod ~= "NAMELIST" or (customSort and customSort.enabled == true))
	if useGroupedHeaders and GF._raidGroupHeaders then
		for _, gh in ipairs(GF._raidGroupHeaders) do
			if gh and not gh._eqolSpecialHide then
				local frames = {}
				forEachChild(gh, function(child)
					if child then frames[#frames + 1] = child end
				end)
				updateGroupIndicatorsForFrames(gh, frames, cfg, def, false, gh._eqolDisplayGroup)
			end
		end
	elseif header then
		local frames = {}
		forEachChild(header, function(child)
			if child then frames[#frames + 1] = child end
		end)
		updateGroupIndicatorsForFrames(header, frames, cfg, def, false)
	end
	if GF._previewFrames and GF._previewFrames.raid then
		local parent = (GF.anchors and GF.anchors.raid) or header
		if parent then updateGroupIndicatorsForFrames(parent, GF._previewFrames.raid, cfg, def, true) end
	end
end

function GF:RefreshDispelTint()
	if not isFeatureEnabled() then return end
	local inEdit = isEditModeActive()
	for _, header in pairs(GF.headers or {}) do
		forEachChild(header, function(child)
			if child then
				if inEdit or child._eqolPreview then
					GF:UpdateDispelTint(child, nil, nil, true)
				else
					local st = getState(child)
					local cache = st and getAuraCache(st, "all")
					GF:UpdateDispelTint(child, cache, AURA_FILTERS.dispellable, nil, AURA_KIND_DISPEL)
				end
			end
		end)
	end
	if GF._previewFrames then
		for _, frames in pairs(GF._previewFrames) do
			for _, btn in ipairs(frames) do
				if btn then GF:UpdateDispelTint(btn, nil, nil, true) end
			end
		end
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
	GF:RefreshGroupIndicators()
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

function GF:RefreshStatusIcons(event)
	if not isFeatureEnabled() then return end
	for _, header in pairs(GF.headers or {}) do
		forEachChild(header, function(child)
			if child then GF:UpdateStatusIcons(child, event) end
		end)
	end
	if GF._previewFrames then
		for _, frames in pairs(GF._previewFrames) do
			for _, btn in ipairs(frames) do
				if btn then GF:UpdateStatusIcons(btn, event) end
			end
		end
	end
end

function GF:RefreshReadyCheckIcons(event)
	if not isFeatureEnabled() then return end
	for _, header in pairs(GF.headers or {}) do
		forEachChild(header, function(child)
			if child then GF:UpdateReadyCheckIcon(child, event) end
		end)
	end
	if GF._previewFrames then
		for _, frames in pairs(GF._previewFrames) do
			for _, btn in ipairs(frames) do
				if btn then GF:UpdateReadyCheckIcon(btn, event) end
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

function GF:RefreshClientSceneVisibility()
	local pendingCombatRefresh = InCombatLockdown and InCombatLockdown()
	for kind, header in pairs(GF.headers or {}) do
		local cfg = getCfg(kind)
		if header and cfg then applyVisibility(header, kind, cfg) end
	end
	if GF._raidGroupHeaders then
		local cfg = getCfg("raid")
		for _, header in ipairs(GF._raidGroupHeaders) do
			if header and cfg then applyVisibility(header, "raid", cfg) end
		end
	end
	if pendingCombatRefresh then
		GF:MarkPendingHeaderRefresh("party")
		GF:MarkPendingHeaderRefresh("raid")
		GF:MarkPendingHeaderRefresh("mt")
		GF:MarkPendingHeaderRefresh("ma")
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

function GF:RefreshCustomSortNameList(kind)
	if not isFeatureEnabled() then return end
	kind = kind or "raid"
	if kind ~= "raid" and kind ~= "party" then return end
	local cfg = getCfg(kind)
	local header = GF.headers and GF.headers[kind]
	if not header then return end
	if InCombatLockdown and InCombatLockdown() then
		GF:MarkPendingHeaderRefresh(kind)
		return
	end
	local sortMethod = resolveSortMethod(cfg)
	if sortMethod ~= "NAMELIST" then
		GF:SetHeaderAttributeIfChanged(header, "nameList", nil)
		if kind == "raid" and GF._raidGroupHeaders then
			for _, gh in ipairs(GF._raidGroupHeaders) do
				if gh then GF:SetHeaderAttributeIfChanged(gh, "nameList", nil) end
			end
		end
		return
	end
	if kind == "party" then
		local nameList = GFH.BuildCustomSortNameList(cfg, "party")
		if nameList == "" then nameList = nil end
		GF:SetHeaderAttributeIfChanged(header, "nameList", nameList)
		return
	end
	local customSort = GFH and GFH.EnsureCustomSortConfig and GFH.EnsureCustomSortConfig(cfg)
	local useGroupedCustom = isGroupCustomLayout(cfg) and customSort and customSort.enabled == true
	if useGroupedCustom then
		local specs = GF:BuildDenseCustomGroupSpecs(cfg)
		if not GF._raidGroupHeaders then GF:EnsureRaidGroupHeaders() end
		if GF._raidGroupHeaders then
			for i, gh in ipairs(GF._raidGroupHeaders) do
				if gh then
					local spec = specs[i]
					local nameList = spec and spec.nameList
					if not nameList or nameList == "" then nameList = EMPTY_NAMELIST_TOKEN end
					GF:SetHeaderAttributeIfChanged(gh, "nameList", nameList)
				end
			end
		end
		GF:SetHeaderAttributeIfChanged(header, "nameList", nil)
	else
		local nameList = GFH.BuildCustomSortNameList(cfg, "raid")
		if nameList == "" then nameList = nil end
		GF:SetHeaderAttributeIfChanged(header, "nameList", nameList)
	end
end

local function syncRaidGroupHeaderChildren(header, cfg, layout)
	forEachChild(header, function(child) syncHeaderChild(child, "raid", cfg, layout and layout.w, layout and layout.h) end)
end

local function applyRaidGroupHeaders(cfg, layout, groupSpecs, forceShow, forceHide, maxGroups)
	local headers = GF:EnsureRaidGroupHeaders()
	local anchor = GF.anchors and GF.anchors.raid
	if not (headers and anchor) then return end
	groupSpecs = groupSpecs or {}
	local maxIndex = tonumber(maxGroups)
	if maxIndex == nil then maxIndex = #groupSpecs end
	if maxIndex < 0 then maxIndex = 0 end
	if maxIndex > 8 then maxIndex = 8 end
	if maxIndex > #groupSpecs then maxIndex = #groupSpecs end
	local groupScale = tonumber(layout and layout.groupScale) or 1
	if groupScale <= 0 then groupScale = 1 end

	for i = 1, 8 do
		local header = headers[i]
		if header then
			local spec = groupSpecs[i]
			local active = (i <= maxIndex) and (spec ~= nil)
			header._eqolForceShow = forceShow
			header._eqolForceHide = forceHide
			header._eqolSpecialHide = not active

			if active then
				local function setAttr(key, value) GF:SetHeaderAttributeIfChanged(header, key, value) end
				local specSortMethod = tostring(spec.sortMethod or "INDEX"):upper()
				header._eqolDisplayGroup = tonumber(spec.group) or i
				setAttr("showParty", false)
				setAttr("showRaid", true)
				setAttr("showPlayer", true)
				setAttr("showSolo", false)
				setAttr("groupBy", nil)
				setAttr("sortDir", cfg.sortDir or "ASC")
				setAttr("unitsPerColumn", layout.unitsPerColumn)
				setAttr("maxColumns", 1)
				setAttr("minWidth", layout.minWidth)
				setAttr("minHeight", layout.minHeight)

				if specSortMethod == "NAMELIST" then
					local nameList = spec.nameList
					if not nameList or nameList == "" then nameList = EMPTY_NAMELIST_TOKEN end
					setAttr("groupFilter", nil)
					setAttr("roleFilter", nil)
					setAttr("strictFiltering", false)
					setAttr("sortMethod", "NAMELIST")
					setAttr("nameList", nameList)
				else
					local roleFilter = cfg.roleFilter
					if roleFilter == "" then roleFilter = nil end
					if specSortMethod ~= "NAME" and specSortMethod ~= "INDEX" then specSortMethod = "INDEX" end
					setAttr("groupFilter", tostring(spec.group or i))
					setAttr("roleFilter", roleFilter)
					setAttr("strictFiltering", cfg.strictFiltering == true)
					setAttr("sortMethod", specSortMethod)
					setAttr("nameList", nil)
				end

				setAttr("point", layout.point)
				setAttr("xOffset", layout.xOffset)
				setAttr("yOffset", layout.yOffset)
				setAttr("columnSpacing", layout.columnSpacing)
				setAttr("columnAnchorPoint", layout.columnAnchorPoint)
				setAttr("template", "EQOLUFGroupUnitButtonTemplate")
				setAttr("initialConfigFunction", layout.initConfigFunction)

				header:ClearAllPoints()
				local unitGrowth = (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(layout.growth, "DOWN")) or "DOWN"
				local defaultGroupGrowth = DEFAULTS and DEFAULTS.raid and DEFAULTS.raid.groupGrowth
				local groupGrowth
				if GFH.ResolveGroupGrowthDirection then
					groupGrowth = GFH.ResolveGroupGrowthDirection(layout.groupGrowth, unitGrowth, defaultGroupGrowth)
				else
					groupGrowth = (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(layout.groupGrowth, nil)) or ((unitGrowth == "RIGHT" or unitGrowth == "LEFT") and "DOWN" or "RIGHT")
				end
				local groupStartPoint = (GFH.GetGroupGrowthStartPoint and GFH.GetGroupGrowthStartPoint(groupGrowth)) or getGrowthStartPoint(groupGrowth)
				if i == 1 then
					header:SetPoint(groupStartPoint, anchor, groupStartPoint, 0, 0)
				else
					local previous = headers[i - 1]
					if previous and previous._eqolSpecialHide ~= true then
						local spacing = roundToPixel((layout.columnSpacing or 0) * groupScale, layout.scale)
						if groupGrowth == "LEFT" then
							header:SetPoint("TOPRIGHT", previous, "TOPLEFT", -spacing, 0)
						elseif groupGrowth == "UP" then
							header:SetPoint("BOTTOMLEFT", previous, "TOPLEFT", 0, spacing)
						elseif groupGrowth == "RIGHT" then
							header:SetPoint("TOPLEFT", previous, "TOPRIGHT", spacing, 0)
						else
							header:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -spacing)
						end
					else
						header:SetPoint(groupStartPoint, anchor, groupStartPoint, 0, 0)
					end
				end
			end

			if header.SetScale then header:SetScale(groupScale) end

			applyVisibility(header, "raid", cfg)

			if active and header.IsShown and header:IsShown() and header.Show then header:Show() end

			if active then syncRaidGroupHeaderChildren(header, cfg, layout) end

			if header.IsShown and header:IsShown() then
				nudgeHeaderLayout(header)
			else
				header._eqolPendingLayout = true
			end

			if not active and header.Hide then header:Hide() end
			if not active then header._eqolDisplayGroup = nil end
		end
	end
end

function GF:ApplyHeaderAttributes(kind)
	local cfg = getCfg(kind)
	local header = GF.headers[kind]
	if not header then return end
	if not isFeatureEnabled() then return end
	if InCombatLockdown and InCombatLockdown() then
		GF:MarkPendingHeaderRefresh(kind)
		return
	end

	local spacing = clampNumber(tonumber(cfg.spacing) or 0, 0, 40, 0)
	local growth = (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(cfg.growth, "DOWN")) or "DOWN"
	if cfg.growth ~= growth then cfg.growth = growth end
	local scale = GFH.GetEffectiveScale(UIParent)
	spacing = roundToPixel(spacing, scale)
	local raidUnitsPerColumn
	local raidMaxColumns
	local raidRuntimeMaxColumns
	local raidViewportScale = 1
	local raidGroupSpecs
	local useGroupHeaders = false
	local useGroupedCustomSort = false
	local sortMethod
	local rawGroupBy
	local db = DB or ensureDB()
	local raidFramesEnabled = db and db.raid and db.raid.enabled == true
	local function setAttr(key, value) GF:SetHeaderAttributeIfChanged(header, key, value) end

	if kind == "party" then
		cfg.groupBy = nil
		cfg.groupingOrder = nil
		setAttr("showParty", true)
		setAttr("showRaid", false)
		setAttr("showPlayer", cfg.showPlayer and true or false)
		setAttr("showSolo", cfg.showSolo and true or false)
		setAttr("groupBy", nil)
		setAttr("groupingOrder", nil)
		setAttr("groupFilter", nil)
		setAttr("roleFilter", nil)
		setAttr("strictFiltering", false)
		sortMethod = resolveSortMethod(cfg)
		local sortDir = (GFH and GFH.NormalizeSortDir and GFH.NormalizeSortDir(cfg.sortDir)) or "ASC"
		setAttr("sortMethod", sortMethod)
		setAttr("sortDir", sortDir)
		if sortMethod == "NAMELIST" then
			local nameList = GFH.BuildCustomSortNameList(cfg, "party")
			if nameList == "" then nameList = nil end
			setAttr("nameList", nameList)
		else
			setAttr("nameList", nil)
		end
		setAttr("maxColumns", 1)
		setAttr("unitsPerColumn", 5)
	elseif kind == "raid" then
		setAttr("showParty", false)
		setAttr("showRaid", true)
		setAttr("showPlayer", true)
		setAttr("showSolo", false)
		local groupingOrder = cfg.groupingOrder
		if groupingOrder == "" then groupingOrder = nil end
		rawGroupBy = cfg.groupBy
		local normalizedGroupBy = resolveGroupByValue(cfg, DEFAULTS.raid) or "GROUP"
		if rawGroupBy and tostring(rawGroupBy):upper() == "CLASS" then groupingOrder = nil end
		setAttr("groupingOrder", groupingOrder or GFH.GROUP_ORDER)
		local groupFilter = cfg.groupFilter
		if groupFilter == "" then groupFilter = nil end
		if rawGroupBy and tostring(rawGroupBy):upper() == "CLASS" then groupFilter = nil end
		setAttr("groupFilter", groupFilter)
		local roleFilter = cfg.roleFilter
		if roleFilter == "" then roleFilter = nil end
		setAttr("roleFilter", roleFilter)
		setAttr("strictFiltering", cfg.strictFiltering == true)
		sortMethod = resolveSortMethod(cfg)
		local customSort = GFH and GFH.EnsureCustomSortConfig and GFH.EnsureCustomSortConfig(cfg)
		useGroupedCustomSort = (sortMethod == "NAMELIST") and (customSort and customSort.enabled == true)
		setAttr("sortMethod", sortMethod)
		setAttr("sortDir", cfg.sortDir or "ASC")
		if sortMethod == "NAMELIST" then
			local nameList = GFH.BuildCustomSortNameList(cfg, "raid")
			if nameList == "" then nameList = nil end
			setAttr("nameList", nameList)
		else
			setAttr("nameList", nil)
		end
		setAttr("groupBy", normalizedGroupBy)
		raidUnitsPerColumn = clampNumber(tonumber(cfg.unitsPerColumn) or 5, 1, 10, 5)
		raidMaxColumns = clampNumber(tonumber(cfg.maxColumns) or 8, 1, 10, 8)
		setAttr("unitsPerColumn", raidUnitsPerColumn)
		raidRuntimeMaxColumns = raidMaxColumns
		setAttr("maxColumns", raidRuntimeMaxColumns)
		useGroupHeaders = GF:IsRaidGroupedLayout(cfg) and (sortMethod ~= "NAMELIST" or useGroupedCustomSort)
		local defaultGroupGrowth = DEFAULTS and DEFAULTS.raid and DEFAULTS.raid.groupGrowth
		if GFH.ResolveGroupGrowthDirection then
			cfg.groupGrowth = GFH.ResolveGroupGrowthDirection(cfg.groupGrowth, growth, defaultGroupGrowth)
		else
			cfg.groupGrowth = (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(cfg.groupGrowth, nil)) or ((growth == "RIGHT" or growth == "LEFT") and "DOWN" or "RIGHT")
		end
	elseif isSplitRoleKind(kind) then
		setAttr("showParty", false)
		setAttr("showRaid", true)
		setAttr("showPlayer", true)
		setAttr("showSolo", false)
		setAttr("groupingOrder", nil)
		setAttr("groupFilter", nil)
		setAttr("groupBy", nil)
		setAttr("nameList", nil)
		setAttr("roleFilter", getSplitRoleFilter(kind))
		setAttr("strictFiltering", true)
		setAttr("sortMethod", "NAME")
		setAttr("sortDir", "ASC")
		raidUnitsPerColumn = clampNumber(tonumber(cfg.unitsPerColumn) or ((DEFAULTS[kind] and DEFAULTS[kind].unitsPerColumn) or 2), 1, 10, 2)
		raidMaxColumns = clampNumber(tonumber(cfg.maxColumns) or ((DEFAULTS[kind] and DEFAULTS[kind].maxColumns) or 1), 1, 10, 1)
		setAttr("unitsPerColumn", raidUnitsPerColumn)
		setAttr("maxColumns", raidMaxColumns)
	end

	if header._eqolForceShow then
		setAttr("showParty", true)
		setAttr("showRaid", true)
		setAttr("showPlayer", true)
		setAttr("showSolo", true)
	end

	local layoutPoint, layoutXOffset, layoutYOffset, layoutColumnSpacing, layoutColumnAnchorPoint
	if growth == "RIGHT" or growth == "LEFT" then
		local xOff = (growth == "LEFT") and -spacing or spacing
		local point = (growth == "LEFT") and "RIGHT" or "LEFT"
		layoutPoint = point
		layoutXOffset = roundToPixel(xOff, scale)
		layoutYOffset = 0
		setAttr("point", layoutPoint)
		setAttr("xOffset", layoutXOffset)
		setAttr("yOffset", layoutYOffset)
		if kind == "party" then
			layoutColumnSpacing = spacing
			setAttr("columnSpacing", layoutColumnSpacing)
		else
			local columnSpacing = clampNumber(tonumber(cfg.columnSpacing) or spacing, 0, 40, spacing)
			layoutColumnSpacing = roundToPixel(columnSpacing, scale)
			setAttr("columnSpacing", layoutColumnSpacing)
		end

		layoutColumnAnchorPoint = "TOP"
		setAttr("columnAnchorPoint", layoutColumnAnchorPoint)
	else
		local yOff = (growth == "UP") and spacing or -spacing
		local point = (growth == "UP") and "BOTTOM" or "TOP"
		layoutPoint = point
		layoutXOffset = 0
		layoutYOffset = roundToPixel(yOff, scale)
		setAttr("point", layoutPoint)
		setAttr("xOffset", layoutXOffset)
		setAttr("yOffset", layoutYOffset)
		local columnSpacing = clampNumber(tonumber(cfg.columnSpacing) or spacing, 0, 40, spacing)
		layoutColumnSpacing = roundToPixel(columnSpacing, scale)
		setAttr("columnSpacing", layoutColumnSpacing)
		layoutColumnAnchorPoint = "LEFT"
		setAttr("columnAnchorPoint", layoutColumnAnchorPoint)
	end

	setAttr("template", "EQOLUFGroupUnitButtonTemplate")

	-- Pixel-perfect size: snap width/height to (even) screen pixels to avoid half-pixel centers -> text jitter.
	local w = clampNumber(tonumber(cfg.width) or 100, 40, 600, 100)
	local h = clampNumber(tonumber(cfg.height) or 24, 10, 200, 24)
	w = roundToEvenPixel(w, scale)
	h = roundToEvenPixel(h, scale)
	local renderW, renderH = w, h
	local renderXOffset, renderYOffset = layoutXOffset, layoutYOffset

	if kind == "raid" then
		if useGroupHeaders then
			raidGroupSpecs = GF:BuildRaidGroupHeaderSpecs(cfg, sortMethod, useGroupedCustomSort)
		else
			local raidCount = (GFH.GetCurrentRaidUnitCount and GFH.GetCurrentRaidUnitCount()) or 0
			local requiredColumns = raidMaxColumns or 1
			if raidCount > 0 then requiredColumns = max(requiredColumns, ceil(raidCount / max(1, raidUnitsPerColumn or 1))) end
			raidRuntimeMaxColumns = requiredColumns
			raidViewportScale = (
				GFH.GetRaidViewportScaleForColumns and GFH.GetRaidViewportScaleForColumns(growth, w, h, spacing, layoutColumnSpacing or spacing, raidMaxColumns or 1, raidRuntimeMaxColumns)
			) or 1
			setAttr("maxColumns", raidRuntimeMaxColumns)
			if raidViewportScale < 1 then
				if growth == "RIGHT" or growth == "LEFT" then
					renderW = w / raidViewportScale
					renderXOffset = layoutXOffset / raidViewportScale
				else
					renderH = h / raidViewportScale
					renderYOffset = layoutYOffset / raidViewportScale
				end
				renderW = roundToEvenPixel(renderW, scale)
				renderH = roundToEvenPixel(renderH, scale)
				renderXOffset = roundToPixel(renderXOffset, scale)
				renderYOffset = roundToPixel(renderYOffset, scale)
				setAttr("xOffset", renderXOffset)
				setAttr("yOffset", renderYOffset)
			end
		end
	end

	local wStr = ("%.3f"):format(renderW)
	local hStr = ("%.3f"):format(renderH)

	local initConfigFunction = string.format(
		[[
		self:ClearAllPoints()
		self:SetWidth(%s)
		self:SetHeight(%s)
		self:SetAttribute('*type1','target')
		self:SetAttribute('*type2','togglemenu')
		RegisterUnitWatch(self)
	]],
		wStr,
		hStr
	)
	setAttr("initialConfigFunction", initConfigFunction)

	local function syncHeaderChildren()
		forEachChild(header, function(child) syncHeaderChild(child, kind, cfg, renderW, renderH) end)
	end

	if header.SetScale then
		if kind == "raid" and not useGroupHeaders then
			header:SetScale(raidViewportScale or 1)
		else
			header:SetScale(1)
		end
	end

	syncHeaderChildren()

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

	local forceHide = header._eqolForceHide
	local forceShow = header._eqolForceShow
	if kind == "raid" then
		header._eqolSpecialHide = useGroupHeaders == true
	elseif isSplitRoleKind(kind) then
		header._eqolSpecialHide = raidFramesEnabled ~= true
	else
		header._eqolSpecialHide = nil
	end
	applyVisibility(header, kind, cfg)

	if kind == "raid" then
		if useGroupHeaders then
			local isHorizontal = (growth == "RIGHT" or growth == "LEFT")
			local unitsPer = raidUnitsPerColumn or 5
			local groupSpecs = raidGroupSpecs or GF:BuildRaidGroupHeaderSpecs(cfg, sortMethod, useGroupedCustomSort)
			local perHeaderW, perHeaderH
			if isHorizontal then
				perHeaderW = w * unitsPer + spacing * max(0, unitsPer - 1)
				perHeaderH = h
			else
				perHeaderW = w
				perHeaderH = h * unitsPer + spacing * max(0, unitsPer - 1)
			end
			perHeaderW = roundToPixel(perHeaderW, scale)
			perHeaderH = roundToPixel(perHeaderH, scale)
			local runtimeGroupCount = #groupSpecs
			local viewportGroupCount = max(1, floor((tonumber(raidMaxColumns) or 1) + 0.5))
			local groupViewportScale = (
				GFH.GetRaidViewportScaleForGroups
				and GFH.GetRaidViewportScaleForGroups(cfg.groupGrowth, perHeaderW, perHeaderH, layoutColumnSpacing or spacing, viewportGroupCount, runtimeGroupCount)
			) or 1
			local groupRenderW, groupRenderH = w, h
			local groupXOffset, groupYOffset = layoutXOffset, layoutYOffset
			if groupViewportScale < 1 then
				if growth == "RIGHT" or growth == "LEFT" then
					groupRenderW = w / groupViewportScale
					groupXOffset = layoutXOffset / groupViewportScale
				else
					groupRenderH = h / groupViewportScale
					groupYOffset = layoutYOffset / groupViewportScale
				end
			end
			groupRenderW = roundToEvenPixel(groupRenderW, scale)
			groupRenderH = roundToEvenPixel(groupRenderH, scale)
			groupXOffset = roundToPixel(groupXOffset, scale)
			groupYOffset = roundToPixel(groupYOffset, scale)
			local groupInitConfigFunction = string.format(
				[[
		self:ClearAllPoints()
		self:SetWidth(%s)
		self:SetHeight(%s)
		self:SetAttribute('*type1','target')
		self:SetAttribute('*type2','togglemenu')
		RegisterUnitWatch(self)
	]],
				("%.3f"):format(groupRenderW),
				("%.3f"):format(groupRenderH)
			)
			local layout = {
				scale = scale,
				w = groupRenderW,
				h = groupRenderH,
				point = layoutPoint,
				xOffset = groupXOffset,
				yOffset = groupYOffset,
				columnSpacing = layoutColumnSpacing or spacing,
				columnAnchorPoint = layoutColumnAnchorPoint or "LEFT",
				unitsPerColumn = unitsPer,
				perHeaderW = perHeaderW,
				perHeaderH = perHeaderH,
				minWidth = isHorizontal and perHeaderW or w,
				minHeight = isHorizontal and h or perHeaderH,
				startPoint = getGrowthStartPoint(growth),
				growth = growth,
				groupGrowth = cfg.groupGrowth,
				groupScale = groupViewportScale,
				initConfigFunction = groupInitConfigFunction,
			}

			applyRaidGroupHeaders(cfg, layout, groupSpecs, forceShow, forceHide, runtimeGroupCount)
		elseif GF._raidGroupHeaders then
			local layout = {
				scale = scale,
				w = w,
				h = h,
				point = layoutPoint,
				xOffset = layoutXOffset,
				yOffset = layoutYOffset,
				columnSpacing = layoutColumnSpacing or spacing,
				columnAnchorPoint = layoutColumnAnchorPoint or "LEFT",
				unitsPerColumn = raidUnitsPerColumn or 5,
				perHeaderW = w,
				perHeaderH = h,
				minWidth = w,
				minHeight = h,
				startPoint = getGrowthStartPoint(growth),
				growth = growth,
				groupGrowth = cfg.groupGrowth,
				initConfigFunction = initConfigFunction,
			}
			applyRaidGroupHeaders(cfg, layout, nil, forceShow, forceHide, 0)
		end
	end
	if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end

	if header.IsShown and header:IsShown() and header.Show then header:Show() end

	if header.IsShown and header:IsShown() then
		nudgeHeaderLayout(header)
	else
		header._eqolPendingLayout = true
	end

	if kind == "raid" then GF:RefreshGroupIndicators() end
end

function GF:EnsureHeaders()
	if not isFeatureEnabled() then return end
	if GF.headers.party and GF.headers.raid and GF.headers.mt and GF.headers.ma and GF.anchors.party and GF.anchors.raid and GF.anchors.mt and GF.anchors.ma then return end

	local parent = _G.PetBattleFrameHider or UIParent

	if not GF.anchors.party then ensureAnchor("party", parent) end
	if not GF.anchors.raid then ensureAnchor("raid", parent) end
	if not GF.anchors.mt then ensureAnchor("mt", parent) end
	if not GF.anchors.ma then ensureAnchor("ma", parent) end

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

	if not GF.headers.mt then
		GF.headers.mt = CreateFrame("Frame", "EQOLUFMTHeader", parent, "SecureGroupHeaderTemplate")
		GF.headers.mt._eqolKind = "mt"
		GF.headers.mt:Hide()
	end

	if not GF.headers.ma then
		GF.headers.ma = CreateFrame("Frame", "EQOLUFMAHeader", parent, "SecureGroupHeaderTemplate")
		GF.headers.ma._eqolKind = "ma"
		GF.headers.ma:Hide()
	end

	for kind, header in pairs(GF.headers) do
		if header and not header._eqolLayoutHooked then
			header._eqolLayoutHooked = true
			header:HookScript("OnShow", function(self)
				if self._eqolPendingLayout then nudgeHeaderLayout(self) end
			end)
		end
		local a = GF.anchors and GF.anchors[kind]
		if header and a then
			header:ClearAllPoints()
			local cfg = getCfg(kind)
			local p = cfg and (cfg.point or "CENTER") or "CENTER"
			header:SetPoint(p, a, p, 0, 0)
		end
	end

	GF:ApplyHeaderAttributes("party")
	GF:ApplyHeaderAttributes("raid")
	GF:ApplyHeaderAttributes("mt")
	GF:ApplyHeaderAttributes("ma")
end

function GF:EnableFeature()
	registerFeatureEvents(GF._eventFrame)
	GF:EnsureHeaders()
	GF.Refresh()
	GF:DisableBlizzardFrames()
	GF:EnsureEditMode()
end

function GF:DisableFeature()
	if InCombatLockdown and InCombatLockdown() then
		GF._pendingDisable = true
		return
	end
	cancelQueuedGroupIndicatorRefresh()
	GF._pendingDisable = nil
	GF:CancelPostEnterWorldRefreshTicker()
	unregisterFeatureEvents(GF._eventFrame)

	if EditMode and EditMode.UnregisterFrame and type(EDITMODE_IDS) == "table" then
		for _, id in pairs(EDITMODE_IDS) do
			pcall(EditMode.UnregisterFrame, EditMode, id)
		end
	end
	GF._editModeRegistered = nil

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

function GF.Enable(self, kind)
	if type(self) == "string" and kind == nil then kind = self end
	if type(kind) ~= "string" then return end
	local cfg = getCfg(kind)
	if not cfg then return end
	cfg.enabled = true
	GF:EnsureHeaders()
	GF:ApplyHeaderAttributes(kind)
	GF:EnableFeature()
	GF:DisableBlizzardFrames()
end

function GF.Disable(self, kind)
	if type(self) == "string" and kind == nil then kind = self end
	if type(kind) ~= "string" then return end
	local cfg = getCfg(kind)
	if not cfg then return end
	cfg.enabled = false
	GF:EnsureHeaders()
	local header = GF.headers and GF.headers[kind]
	if header then
		header._eqolForceShow = nil
		header._eqolForceHide = nil
	end
	if GF._previewActive then GF._previewActive[kind] = nil end
	GF:ShowPreviewFrames(kind, false)
	GF:ApplyHeaderAttributes(kind)
	if not isFeatureEnabled() then GF:DisableFeature() end
end

function GF:DidRosterStateChange()
	local state = self._rosterState
	if not state then
		state = { guids = {}, present = {}, mode = nil, count = nil }
		self._rosterState = state
	end

	local guids = state.guids
	local present = state.present
	local changed = false
	local modeChanged = false
	local countChanged = false

	local function visit(unit)
		present[unit] = true
		local guid = UnitGUID and UnitGUID(unit) or nil
		if issecretvalue and issecretvalue(guid) then guid = nil end
		local cachedGuid = guids[unit]
		if issecretvalue and issecretvalue(cachedGuid) then
			cachedGuid = nil
			guids[unit] = nil
		end
		if cachedGuid ~= guid then
			guids[unit] = guid
			changed = true
		end
	end

	local mode, count
	if IsInRaid and IsInRaid() then
		mode = "raid"
		count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
		for i = 1, count do
			visit("raid" .. i)
		end
	elseif IsInGroup and IsInGroup() then
		mode = "party"
		count = (GetNumSubgroupMembers and GetNumSubgroupMembers()) or 0
		visit("player")
		for i = 1, count do
			visit("party" .. i)
		end
	else
		mode = "solo"
		count = 0
		visit("player")
	end

	if state.mode ~= mode then
		state.mode = mode
		changed = true
		modeChanged = true
	end
	if state.count ~= count then
		state.count = count
		changed = true
		countChanged = true
	end

	for unit in pairs(guids) do
		if not present[unit] then
			guids[unit] = nil
			changed = true
		end
	end

	if wipe then
		wipe(present)
	else
		for k in pairs(present) do
			present[k] = nil
		end
	end

	return changed, modeChanged, countChanged
end

function GF:RefreshChangedUnitButtons()
	local updated = 0
	local seen = {}

	local function syncChild(child)
		if not child or seen[child] then return end
		seen[child] = true

		local st = getState(child)
		if not st then return end

		local unit = getUnit(child)
		if unit == nil or unit == "" then
			if child.unit then
				GF:UnitButton_ClearUnit(child)
				GF:UpdateAll(child)
				updated = updated + 1
			end
			return
		end

		local guid = UnitGUID and UnitGUID(unit) or nil
		if issecretvalue and issecretvalue(guid) then guid = nil end
		local cachedGuid = st._guid
		if issecretvalue and issecretvalue(cachedGuid) then
			cachedGuid = nil
			st._guid = nil
		end
		if cachedGuid == guid and st._unitToken == unit and child.unit == unit then
			local cfg = child._eqolCfg or getCfg(child._eqolGroupKind or "party")
			if st._classR == nil and GF:NeedsClassColor(child, st, cfg) then
				GF:CacheUnitStatic(child)
				GF:EnsureUnitClassColor(child, st, unit)
				GF:UpdateHealthStyle(child)
				GF:UpdateName(child)
				GF:UpdateLevel(child)
				updated = updated + 1
			end
			return
		end

		if child.unit ~= unit then
			GF:UnitButton_SetUnit(child, unit)
			updated = updated + 1
			return
		end

		st._auraCache = nil
		st._auraCacheByKey = nil
		st._auraKindById = nil
		st._auraChanged = nil
		st._auraQueryMax = nil
		clearDispelAuraState(st)
		GF:CacheUnitStatic(child)
		GF:UnitButton_RegisterUnitEvents(child, unit)
		if st._wantsAbsorb then GF:UpdateAbsorbCache(child, nil, unit, st) end
		GF:UpdatePrivateAuras(child)
		GF:UpdateAll(child)
		updated = updated + 1
	end

	for _, header in pairs(self.headers or {}) do
		forEachChild(header, syncChild)
	end
	if self._raidGroupHeaders then
		for _, header in ipairs(self._raidGroupHeaders) do
			if header then forEachChild(header, syncChild) end
		end
	end

	return updated
end

function GF.Refresh(kind)
	if not isFeatureEnabled() then return end
	GF:EnsureHeaders()
	if kind then
		GF:ApplyHeaderAttributes(kind)
	else
		GF:ApplyHeaderAttributes("party")
		GF:ApplyHeaderAttributes("raid")
		GF:ApplyHeaderAttributes("mt")
		GF:ApplyHeaderAttributes("ma")
	end
end

local EDITMODE_IDS = {
	party = "EQOL_UF_GROUP_PARTY",
	raid = "EQOL_UF_GROUP_RAID",
	mt = "EQOL_UF_GROUP_MT",
	ma = "EQOL_UF_GROUP_MA",
}

local function anchorUsesUIParent(kind)
	local cfg = getCfg(kind)
	local rel = cfg and cfg.relativeTo
	return rel == nil or rel == "" or rel == "UIParent"
end

function GF.ReadStatusIconField(kind, key, field, fallback)
	local cfg = getCfg(kind)
	local iconCfg = cfg and cfg.status and cfg.status[key]
	if iconCfg and iconCfg[field] ~= nil then return iconCfg[field] end
	local defCfg = DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status[key]
	if defCfg and defCfg[field] ~= nil then return defCfg[field] end
	return fallback
end

function GF.SetStatusIconField(kind, key, field, value)
	local cfg = getCfg(kind)
	if not cfg then return nil end
	cfg.status = cfg.status or {}
	cfg.status[key] = cfg.status[key] or {}
	cfg.status[key][field] = value
	return cfg.status[key][field]
end

function GF:AppendStatusIconSettings(settings, kind, editModeId, insertIndex)
	local iconMeta = GFH.STATUS_ICON_EDITMODE_META
	if not (settings and SettingType and iconMeta and iconMeta[1]) then return end
	local iconLabelByKey = {
		readyCheckIcon = L["UFGroupStatusIconReadyCheck"] or "Ready check icon",
		summonIcon = L["UFGroupStatusIconSummon"] or "Summon icon",
		resurrectIcon = L["UFGroupStatusIconResurrect"] or "Resurrect icon",
		phaseIcon = L["UFGroupStatusIconPhase"] or "Phasing icon",
	}
	local showFormat = L["UFGroupStatusIconsShowFormat"] or "Show %s"
	local sampleFormat = L["UFGroupStatusIconsSampleFormat"] or "%s sample"
	local sizeFormat = L["UFGroupStatusIconsSizeFormat"] or "%s size"
	local anchorFormat = L["UFGroupStatusIconsAnchorFormat"] or "%s anchor"
	local offsetXFormat = L["UFGroupStatusIconsOffsetXFormat"] or "%s offset X"
	local offsetYFormat = L["UFGroupStatusIconsOffsetYFormat"] or "%s offset Y"
	local function push(entry)
		if insertIndex and insertIndex > 0 then
			table.insert(settings, insertIndex, entry)
			insertIndex = insertIndex + 1
		else
			settings[#settings + 1] = entry
		end
	end

	push({
		name = L["UFGroupStatusIcons"] or "Status icons",
		kind = SettingType.Collapsible,
		id = "statusicons",
		defaultCollapsed = true,
	})

	for index, meta in ipairs(iconMeta) do
		if index > 1 then push({ name = "", kind = SettingType.Divider, parentId = "statusicons" }) end
		local key = meta.key
		local label = iconLabelByKey[key] or meta.name or key
		local defaultPoint = meta.defaultPoint or "CENTER"
		local defaultSize = tonumber(meta.defaultSize) or 16
		local enabledField = key .. "Enabled"
		local sampleField = key .. "Sample"
		local sizeField = key .. "Size"
		local pointField = key .. "Point"
		local offsetXField = key .. "OffsetX"
		local offsetYField = key .. "OffsetY"

		push({
			name = showFormat:format(label),
			kind = SettingType.Checkbox,
			field = enabledField,
			parentId = "statusicons",
			get = function() return GF.ReadStatusIconField(kind, key, "enabled", true) ~= false end,
			set = function(_, value)
				local stored = GF.SetStatusIconField(kind, key, "enabled", value and true or false)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, enabledField, stored, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end
				GF:RefreshStatusIcons()
			end,
		})
		push({
			name = sampleFormat:format(label),
			kind = SettingType.Checkbox,
			field = sampleField,
			parentId = "statusicons",
			get = function() return GF.ReadStatusIconField(kind, key, "sample", false) == true end,
			set = function(_, value)
				local stored = GF.SetStatusIconField(kind, key, "sample", value and true or false)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, sampleField, stored, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end
				GF:RefreshStatusIcons()
			end,
			isEnabled = function() return GF.ReadStatusIconField(kind, key, "enabled", true) ~= false end,
		})
		push({
			name = sizeFormat:format(label),
			kind = SettingType.Slider,
			allowInput = true,
			field = sizeField,
			parentId = "statusicons",
			minValue = 8,
			maxValue = 40,
			valueStep = 1,
			get = function() return GF.ReadStatusIconField(kind, key, "size", defaultSize) end,
			set = function(_, value)
				local current = GF.ReadStatusIconField(kind, key, "size", defaultSize)
				local stored = GF.SetStatusIconField(kind, key, "size", clampNumber(value, 8, 40, current))
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, sizeField, stored, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end
				GF:RefreshStatusIcons()
			end,
			isEnabled = function() return GF.ReadStatusIconField(kind, key, "enabled", true) ~= false end,
		})
		push({
			name = anchorFormat:format(label),
			kind = SettingType.Dropdown,
			field = pointField,
			parentId = "statusicons",
			values = anchorOptions9,
			height = 180,
			get = function() return GF.ReadStatusIconField(kind, key, "point", defaultPoint) end,
			set = function(_, value)
				local stored = GF.SetStatusIconField(kind, key, "point", value)
				GF.SetStatusIconField(kind, key, "relativePoint", value)
				local storedX = GF.SetStatusIconField(kind, key, "x", 0)
				local storedY = GF.SetStatusIconField(kind, key, "y", 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, pointField, stored, nil, true) end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, offsetXField, storedX, nil, true) end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, offsetYField, storedY, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end
				GF:RefreshStatusIcons()
			end,
			isEnabled = function() return GF.ReadStatusIconField(kind, key, "enabled", true) ~= false end,
		})
		push({
			name = offsetXFormat:format(label),
			kind = SettingType.Slider,
			allowInput = true,
			field = offsetXField,
			parentId = "statusicons",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function() return GF.ReadStatusIconField(kind, key, "x", 0) end,
			set = function(_, value)
				local current = GF.ReadStatusIconField(kind, key, "x", 0)
				local stored = GF.SetStatusIconField(kind, key, "x", clampNumber(value, -200, 200, current))
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, offsetXField, stored, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end
				GF:RefreshStatusIcons()
			end,
			isEnabled = function() return GF.ReadStatusIconField(kind, key, "enabled", true) ~= false end,
		})
		push({
			name = offsetYFormat:format(label),
			kind = SettingType.Slider,
			allowInput = true,
			field = offsetYField,
			parentId = "statusicons",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function() return GF.ReadStatusIconField(kind, key, "y", 0) end,
			set = function(_, value)
				local current = GF.ReadStatusIconField(kind, key, "y", 0)
				local stored = GF.SetStatusIconField(kind, key, "y", clampNumber(value, -200, 200, current))
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, offsetYField, stored, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end
				GF:RefreshStatusIcons()
			end,
			isEnabled = function() return GF.ReadStatusIconField(kind, key, "enabled", true) ~= false end,
		})
	end
end

local function buildEditModeSettings(kind, editModeId)
	if not SettingType then return nil end

	local widthLabel = HUD_EDIT_MODE_SETTING_CHAT_FRAME_WIDTH or "Width"
	local heightLabel = HUD_EDIT_MODE_SETTING_CHAT_FRAME_HEIGHT or "Height"
	local raidLikeKind = isRaidLikeKind(kind)
	local raidKind = kind == "raid"
	local specOptions = GFH.BuildSpecOptions()
	local tooltipModeOptions = {
		{ value = "OFF", label = "Off" },
		{ value = "ALWAYS", label = "Always" },
		{ value = "OUT_OF_COMBAT", label = "Out of combat" },
		{ value = "MODIFIER", label = "Only with modifier" },
	}
	local tooltipModifierOptions = {
		{ value = "ALT", label = "Alt" },
		{ value = "SHIFT", label = "Shift" },
		{ value = "CTRL", label = "Ctrl" },
	}
	local function getTooltipModeValue()
		local cfg = getCfg(kind)
		local tc = cfg and cfg.tooltip or {}
		return tc.mode or (DEFAULTS[kind] and DEFAULTS[kind].tooltip and DEFAULTS[kind].tooltip.mode) or "OFF"
	end
	local function getTooltipModeLabel()
		local mode = tostring(getTooltipModeValue() or "OFF"):upper()
		for _, option in ipairs(tooltipModeOptions) do
			if option.value == mode then return option.label end
		end
		return mode
	end
	local function getTooltipModifierValue()
		local cfg = getCfg(kind)
		local tc = cfg and cfg.tooltip or {}
		return tc.modifier or (DEFAULTS[kind] and DEFAULTS[kind].tooltip and DEFAULTS[kind].tooltip.modifier) or "ALT"
	end
	local function getTooltipModifierLabel()
		local modifier = tostring(getTooltipModifierValue() or "ALT"):upper()
		for _, option in ipairs(tooltipModifierOptions) do
			if option.value == modifier then return option.label end
		end
		return modifier
	end
	local function tooltipModeGenerator()
		return function(_, root, data)
			for _, option in ipairs(tooltipModeOptions) do
				root:CreateRadio(option.label, function() return data.get and data.get() == option.value end, function()
					if data.set then data.set(nil, option.value) end
					data.customDefaultText = option.label
					if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RequestRefreshSettings then addon.EditModeLib.internal:RequestRefreshSettings() end
				end)
			end
		end
	end
	local function tooltipModifierGenerator()
		return function(_, root, data)
			for _, option in ipairs(tooltipModifierOptions) do
				root:CreateRadio(option.label, function() return data.get and data.get() == option.value end, function()
					if data.set then data.set(nil, option.value) end
					data.customDefaultText = option.label
					if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RequestRefreshSettings then addon.EditModeLib.internal:RequestRefreshSettings() end
				end)
			end
		end
	end
	local sortGroupOptions = {
		{ value = "GROUP", label = "Group" },
		{ value = "ASSIGNEDROLE", label = "Role" },
	}
	local sortMethodOptions = {
		{ value = "INDEX", label = "Index" },
		{ value = "NAME", label = "Name" },
		{ value = "CUSTOM", label = "Custom" },
	}
	local sortDirOptions = {
		{ value = "ASC", label = "Ascending" },
		{ value = "DESC", label = "Descending" },
	}
	local privateAuraPointOptions = {
		{ value = "LEFT", label = "Left", text = "Left" },
		{ value = "RIGHT", label = "Right", text = "Right" },
		{ value = "TOP", label = "Top", text = "Top" },
		{ value = "BOTTOM", label = "Bottom", text = "Bottom" },
	}
	local defPrivateAuras = (DEFAULTS[kind] and DEFAULTS[kind].privateAuras) or {}
	local function ensurePrivateAuraConfig(cfg)
		if not cfg then return nil end
		cfg.privateAuras = cfg.privateAuras or {}
		cfg.privateAuras.icon = cfg.privateAuras.icon or {}
		cfg.privateAuras.parent = cfg.privateAuras.parent or {}
		cfg.privateAuras.duration = cfg.privateAuras.duration or {}
		return cfg.privateAuras
	end
	local function isPrivateAurasEnabled()
		local cfg = getCfg(kind)
		local pcfg = cfg and cfg.privateAuras or {}
		if pcfg.enabled == nil then return defPrivateAuras.enabled == true end
		return pcfg.enabled == true
	end
	local function normalizeGroupBy(value)
		if value == nil then return nil end
		local v = tostring(value):upper()
		if v == "ROLE" then v = "ASSIGNEDROLE" end
		if v == "CLASS" then return "GROUP" end
		if v == "GROUP" or v == "ASSIGNEDROLE" then return v end
		return nil
	end
	local function getGroupByValue()
		local cfg = getCfg(kind)
		return normalizeGroupBy(cfg and cfg.groupBy) or (DEFAULTS[kind] and DEFAULTS[kind].groupBy) or "GROUP"
	end
	local function isCustomSortingEnabled()
		if kind ~= "raid" and kind ~= "party" then return false end
		local cfg = getCfg(kind)
		return resolveSortMethod(cfg) == "NAMELIST"
	end
	local function isCustomSortEditorOpen() return GF._customSortEditor and GF._customSortEditor.IsShown and GF._customSortEditor:IsShown() end
	local function getGroupByLabel()
		local mode = getGroupByValue()
		for _, option in ipairs(sortGroupOptions) do
			if option.value == mode then return option.label end
		end
		return mode
	end
	local function applyGroupByPreset(value)
		local cfg = getCfg(kind)
		if not cfg then return end
		local groupBy = normalizeGroupBy(value) or "GROUP"
		cfg.groupBy = groupBy
		if groupBy == "ASSIGNEDROLE" then
			cfg.groupingOrder = GFH.ROLE_ORDER
			cfg.groupFilter = nil
		else
			cfg.groupingOrder = GFH.GROUP_ORDER
			cfg.groupFilter = nil
		end
		if EditMode and EditMode.SetValue then
			EditMode:SetValue(editModeId, "groupBy", cfg.groupBy, nil, true)
			EditMode:SetValue(editModeId, "groupingOrder", cfg.groupingOrder, nil, true)
			EditMode:SetValue(editModeId, "groupFilter", cfg.groupFilter, nil, true)
			local sortMethodValue = resolveSortMethod(cfg)
			if sortMethodValue == "NAMELIST" then sortMethodValue = "CUSTOM" end
			EditMode:SetValue(editModeId, "sortMethod", sortMethodValue or "INDEX", nil, true)
		end
		GF:ApplyHeaderAttributes(kind)
		if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end
		if kind == "raid" then GF:RefreshGroupIndicators() end
	end
	local function getSortMethodValue()
		local cfg = getCfg(kind)
		local v = resolveSortMethod(cfg)
		if v == "NAMELIST" then return "CUSTOM" end
		if v == "NAME" or v == "INDEX" then return v end
		return "INDEX"
	end
	local function getSortMethodLabel()
		local mode = getSortMethodValue()
		for _, option in ipairs(sortMethodOptions) do
			if option.value == mode then return option.label end
		end
		return mode
	end
	local function getSortDirValue()
		local cfg = getCfg(kind)
		return (cfg and cfg.sortDir) or (DEFAULTS[kind] and DEFAULTS[kind].sortDir) or "ASC"
	end
	local function getSortDirLabel()
		local mode = getSortDirValue()
		for _, option in ipairs(sortDirOptions) do
			if option.value == mode then return option.label end
		end
		return mode
	end
	local function getGroupNumberEnabledValue()
		local cfg = getCfg(kind)
		local def = DEFAULTS[kind] or {}
		return resolveGroupNumberSettingEnabled(cfg, def)
	end
	local function getGroupFormatValue()
		local cfg = getCfg(kind)
		local def = DEFAULTS[kind] or {}
		return resolveGroupNumberFormat(cfg, def)
	end
	local function getGroupFormatLabel()
		local fmt = getGroupFormatValue()
		return groupNumberFormatLabelByValue[fmt] or tostring(fmt)
	end
	local function isStatusTextEnabled()
		local cfg = getCfg(kind)
		local sc = cfg and cfg.status or {}
		local us = sc.unitStatus or {}
		return us.enabled ~= false
	end
	local function isGroupNumberSettingsEnabled() return isStatusTextEnabled() and getGroupNumberEnabledValue() end
	local function isGroupIndicatorShown()
		if kind ~= "raid" then return false end
		return getGroupByValue() == "GROUP"
	end
	local function getGroupIndicatorEnabledValue()
		local cfg = getCfg(kind)
		local def = DEFAULTS[kind] or {}
		return resolveGroupIndicatorEnabled(cfg, def)
	end
	local function getGroupIndicatorFormatValue()
		local cfg = getCfg(kind)
		local def = DEFAULTS[kind] or {}
		return resolveGroupIndicatorFormat(cfg, def)
	end
	local function getGroupIndicatorFormatLabel()
		local fmt = getGroupIndicatorFormatValue()
		return groupNumberFormatLabelByValue[fmt] or tostring(fmt)
	end
	local function isGroupIndicatorSettingsEnabled() return isGroupIndicatorShown() and getGroupIndicatorEnabledValue() end
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
			local opts = GFH.auraGrowthOptions or GFH.auraGrowthXOptions
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
			name = L["Anchor point"] or "Anchor point",
			kind = SettingType.Dropdown,
			field = "point",
			parentId = "frame",
			values = anchorOptions9,
			height = 180,
			default = (DEFAULTS[kind] and DEFAULTS[kind].point) or "CENTER",
			get = function()
				local cfg = getCfg(kind)
				return (cfg and cfg.point) or (DEFAULTS[kind] and DEFAULTS[kind].point) or "CENTER"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg or not value then return end
				cfg.point = tostring(value):upper()
				if not cfg.relativePoint or cfg.relativePoint == "" then cfg.relativePoint = cfg.point end
				if not cfg.relativeTo or cfg.relativeTo == "" then cfg.relativeTo = "UIParent" end
				if EditMode and EditMode.SetValue then
					EditMode:SetValue(editModeId, "point", cfg.point, nil, true)
					EditMode:SetValue(editModeId, "relativePoint", cfg.relativePoint, nil, true)
				end
				if EditMode and EditMode.RefreshFrame then
					if EditMode.EnsureLayoutData and EditMode.GetActiveLayoutName then
						local layoutName = EditMode:GetActiveLayoutName()
						if layoutName then
							local def = DEFAULTS[kind] or {}
							local data = EditMode:EnsureLayoutData(editModeId, layoutName)
							if data then
								data.point = cfg.point or def.point or "CENTER"
								data.relativePoint = cfg.relativePoint or cfg.point or def.relativePoint or def.point or "CENTER"
								data.x = cfg.x or def.x or 0
								data.y = cfg.y or def.y or 0
							end
						end
					end
					EditMode:RefreshFrame(editModeId)
				end
				GF:ApplyHeaderAttributes(kind)
				if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RefreshSettingValues then addon.EditModeLib.internal:RefreshSettingValues() end
			end,
		},
		{
			name = L["Relative point"] or "Relative point",
			kind = SettingType.Dropdown,
			field = "relativePoint",
			parentId = "frame",
			values = anchorOptions9,
			height = 180,
			default = (DEFAULTS[kind] and (DEFAULTS[kind].relativePoint or DEFAULTS[kind].point)) or "CENTER",
			get = function()
				local cfg = getCfg(kind)
				return (cfg and (cfg.relativePoint or cfg.point)) or (DEFAULTS[kind] and (DEFAULTS[kind].relativePoint or DEFAULTS[kind].point)) or "CENTER"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg or not value then return end
				cfg.relativePoint = tostring(value):upper()
				if not cfg.point or cfg.point == "" then cfg.point = cfg.relativePoint end
				if not cfg.relativeTo or cfg.relativeTo == "" then cfg.relativeTo = "UIParent" end
				if EditMode and EditMode.SetValue then
					EditMode:SetValue(editModeId, "relativePoint", cfg.relativePoint, nil, true)
					EditMode:SetValue(editModeId, "point", cfg.point, nil, true)
				end
				if EditMode and EditMode.RefreshFrame then
					if EditMode.EnsureLayoutData and EditMode.GetActiveLayoutName then
						local layoutName = EditMode:GetActiveLayoutName()
						if layoutName then
							local def = DEFAULTS[kind] or {}
							local data = EditMode:EnsureLayoutData(editModeId, layoutName)
							if data then
								data.point = cfg.point or def.point or "CENTER"
								data.relativePoint = cfg.relativePoint or cfg.point or def.relativePoint or def.point or "CENTER"
								data.x = cfg.x or def.x or 0
								data.y = cfg.y or def.y or 0
							end
						end
					end
					EditMode:RefreshFrame(editModeId)
				end
				GF:ApplyHeaderAttributes(kind)
				if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RefreshSettingValues then addon.EditModeLib.internal:RefreshSettingValues() end
			end,
		},
		{
			name = L["Offset X"] or "Offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "x",
			minValue = -4000,
			maxValue = 4000,
			valueStep = 1,
			default = (DEFAULTS[kind] and DEFAULTS[kind].x) or 0,
			parentId = "frame",
			get = function()
				local cfg = getCfg(kind)
				return (cfg and cfg.x) or (DEFAULTS[kind] and DEFAULTS[kind].x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				if not cfg.relativeTo or cfg.relativeTo == "" then cfg.relativeTo = "UIParent" end
				local raw = clampNumber(value, -4000, 4000, cfg.x or 0)
				cfg.x = roundToPixel(raw, 1)
				local v = cfg.x
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "x", v, nil, true) end
				if EditMode and EditMode.RefreshFrame then
					if EditMode.EnsureLayoutData and EditMode.GetActiveLayoutName then
						local layoutName = EditMode:GetActiveLayoutName()
						if layoutName then
							local def = DEFAULTS[kind] or {}
							local data = EditMode:EnsureLayoutData(editModeId, layoutName)
							if data then
								data.point = cfg.point or def.point or "CENTER"
								data.relativePoint = cfg.relativePoint or cfg.point or def.relativePoint or def.point or "CENTER"
								data.x = cfg.x or def.x or 0
								data.y = cfg.y or def.y or 0
							end
						end
					end
					EditMode:RefreshFrame(editModeId)
				end
				GF:ApplyHeaderAttributes(kind)
				if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RefreshSettingValues then addon.EditModeLib.internal:RefreshSettingValues() end
			end,
		},
		{
			name = L["Offset Y"] or "Offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "y",
			minValue = -4000,
			maxValue = 4000,
			valueStep = 1,
			default = (DEFAULTS[kind] and DEFAULTS[kind].y) or 0,
			parentId = "frame",
			get = function()
				local cfg = getCfg(kind)
				return (cfg and cfg.y) or (DEFAULTS[kind] and DEFAULTS[kind].y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				if not cfg.relativeTo or cfg.relativeTo == "" then cfg.relativeTo = "UIParent" end
				local raw = clampNumber(value, -4000, 4000, cfg.y or 0)
				cfg.y = roundToPixel(raw, 1)
				local v = cfg.y
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "y", v, nil, true) end
				if EditMode and EditMode.RefreshFrame then
					if EditMode.EnsureLayoutData and EditMode.GetActiveLayoutName then
						local layoutName = EditMode:GetActiveLayoutName()
						if layoutName then
							local def = DEFAULTS[kind] or {}
							local data = EditMode:EnsureLayoutData(editModeId, layoutName)
							if data then
								data.point = cfg.point or def.point or "CENTER"
								data.relativePoint = cfg.relativePoint or cfg.point or def.relativePoint or def.point or "CENTER"
								data.x = cfg.x or def.x or 0
								data.y = cfg.y or def.y or 0
							end
						end
					end
					EditMode:RefreshFrame(editModeId)
				end
				GF:ApplyHeaderAttributes(kind)
				if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RefreshSettingValues then addon.EditModeLib.internal:RefreshSettingValues() end
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
			name = L["UFHideInClientScene"] or "Hide in client scenes",
			kind = SettingType.Checkbox,
			field = "hideInClientScene",
			parentId = "frame",
			default = (DEFAULTS[kind] and DEFAULTS[kind].hideInClientScene) ~= false,
			get = function()
				local cfg = getCfg(kind)
				local value = cfg and cfg.hideInClientScene
				if value == nil then value = DEFAULTS[kind] and DEFAULTS[kind].hideInClientScene end
				if value == nil then value = true end
				return value == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.hideInClientScene = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "hideInClientScene", cfg.hideInClientScene, nil, true) end
				GF:RefreshClientSceneVisibility()
			end,
		},
		{
			name = "Tooltip",
			kind = SettingType.Dropdown,
			field = "tooltipMode",
			parentId = "frame",
			default = (DEFAULTS[kind] and DEFAULTS[kind].tooltip and DEFAULTS[kind].tooltip.mode) or "OFF",
			customDefaultText = getTooltipModeLabel(),
			get = function() return getTooltipModeValue() end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg or not value then return end
				cfg.tooltip = cfg.tooltip or {}
				cfg.tooltip.mode = tostring(value):upper()
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "tooltipMode", cfg.tooltip.mode, nil, true) end
			end,
			generator = tooltipModeGenerator(),
		},
		{
			name = "Tooltip modifier",
			kind = SettingType.Dropdown,
			field = "tooltipModifier",
			parentId = "frame",
			default = (DEFAULTS[kind] and DEFAULTS[kind].tooltip and DEFAULTS[kind].tooltip.modifier) or "ALT",
			customDefaultText = getTooltipModifierLabel(),
			get = function() return getTooltipModifierValue() end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg or not value then return end
				cfg.tooltip = cfg.tooltip or {}
				cfg.tooltip.modifier = tostring(value):upper()
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "tooltipModifier", cfg.tooltip.modifier, nil, true) end
			end,
			generator = tooltipModifierGenerator(),
			isEnabled = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.tooltip or {}
				local mode = tc.mode or (DEFAULTS[kind] and DEFAULTS[kind].tooltip and DEFAULTS[kind].tooltip.mode) or "OFF"
				return mode == "MODIFIER"
			end,
		},
		{
			name = "Show tooltip for auras",
			kind = SettingType.Checkbox,
			field = "tooltipAuras",
			parentId = "frame",
			default = false,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.showTooltip == true and ac.debuff.showTooltip == true and ac.externals.showTooltip == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				local enabled = value and true or false
				ac.buff.showTooltip = enabled
				ac.debuff.showTooltip = enabled
				ac.externals.showTooltip = enabled
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "tooltipAuras", enabled, nil, true) end
				refreshAllAuras()
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
				if raidKind then
					local defaultGroupGrowth = DEFAULTS and DEFAULTS.raid and DEFAULTS.raid.groupGrowth
					if GFH.ResolveGroupGrowthDirection then
						cfg.groupGrowth = GFH.ResolveGroupGrowthDirection(cfg.groupGrowth, cfg.growth, defaultGroupGrowth)
					else
						cfg.groupGrowth = (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(cfg.groupGrowth, nil))
							or ((cfg.growth == "RIGHT" or cfg.growth == "LEFT") and "DOWN" or "RIGHT")
					end
					if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupGrowth", cfg.groupGrowth, nil, true) end
				end
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
						if raidKind then
							local defaultGroupGrowth = DEFAULTS and DEFAULTS.raid and DEFAULTS.raid.groupGrowth
							if GFH.ResolveGroupGrowthDirection then
								cfg.groupGrowth = GFH.ResolveGroupGrowthDirection(cfg.groupGrowth, cfg.growth, defaultGroupGrowth)
							else
								cfg.groupGrowth = (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(cfg.groupGrowth, nil))
									or ((cfg.growth == "RIGHT" or cfg.growth == "LEFT") and "DOWN" or "RIGHT")
							end
							if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupGrowth", cfg.groupGrowth, nil, true) end
						end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = L["Group Growth"] or "Group Growth",
			kind = SettingType.Dropdown,
			field = "groupGrowth",
			parentId = "layout",
			default = (DEFAULTS.raid and DEFAULTS.raid.groupGrowth) or "DOWN",
			get = function()
				if not raidKind then return "DOWN" end
				local cfg = getCfg(kind)
				local growth = (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(cfg and cfg.growth, "DOWN")) or "DOWN"
				local defaultGroupGrowth = DEFAULTS and DEFAULTS.raid and DEFAULTS.raid.groupGrowth
				if GFH.ResolveGroupGrowthDirection then return GFH.ResolveGroupGrowthDirection(cfg and cfg.groupGrowth, growth, defaultGroupGrowth) end
				return (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(cfg and cfg.groupGrowth, nil)) or ((growth == "RIGHT" or growth == "LEFT") and "DOWN" or "RIGHT")
			end,
			set = function(_, value)
				if not raidKind then return end
				local cfg = getCfg(kind)
				if not cfg or not value then return end
				local growth = (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(cfg.growth, "DOWN")) or "DOWN"
				local defaultGroupGrowth = DEFAULTS and DEFAULTS.raid and DEFAULTS.raid.groupGrowth
				if GFH.ResolveGroupGrowthDirection then
					cfg.groupGrowth = GFH.ResolveGroupGrowthDirection(value, growth, defaultGroupGrowth)
				else
					cfg.groupGrowth = (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(value, nil)) or ((growth == "RIGHT" or growth == "LEFT") and "DOWN" or "RIGHT")
				end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupGrowth", cfg.groupGrowth, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end
			end,
			isShown = function() return raidKind end,
			isEnabled = function()
				local cfg = getCfg(kind)
				return raidKind and GF:IsRaidGroupedLayout(cfg)
			end,
			generator = function(_, root)
				local cfg = getCfg(kind)
				local growth = (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(cfg and cfg.growth, "DOWN")) or "DOWN"
				local optionA, optionB
				if GFH.GetAllowedGroupGrowthDirections then
					optionA, optionB = GFH.GetAllowedGroupGrowthDirections(growth)
				end
				if not optionA or not optionB then
					if growth == "RIGHT" or growth == "LEFT" then
						optionA, optionB = "DOWN", "UP"
					else
						optionA, optionB = "RIGHT", "LEFT"
					end
				end
				local function toGrowthLabel(value)
					if value == "UP" then return L["Up"] or "Up" end
					if value == "DOWN" then return L["Down"] or "Down" end
					if value == "LEFT" then return L["Left"] or "Left" end
					if value == "RIGHT" then return L["Right"] or "Right" end
					return value
				end
				local options = {
					{ value = optionA, label = toGrowthLabel(optionA) },
					{ value = optionB, label = toGrowthLabel(optionB) },
				}
				for _, option in ipairs(options) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local growth = (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(cfg and cfg.growth, "DOWN")) or "DOWN"
						local defaultGroupGrowth = DEFAULTS and DEFAULTS.raid and DEFAULTS.raid.groupGrowth
						local current
						if GFH.ResolveGroupGrowthDirection then
							current = GFH.ResolveGroupGrowthDirection(cfg and cfg.groupGrowth, growth, defaultGroupGrowth)
						else
							current = (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(cfg and cfg.groupGrowth, nil)) or ((growth == "RIGHT" or growth == "LEFT") and "DOWN" or "RIGHT")
						end
						return current == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						local defaultGroupGrowth = DEFAULTS and DEFAULTS.raid and DEFAULTS.raid.groupGrowth
						local growth = (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(cfg.growth, "DOWN")) or "DOWN"
						if GFH.ResolveGroupGrowthDirection then
							cfg.groupGrowth = GFH.ResolveGroupGrowthDirection(option.value, growth, defaultGroupGrowth)
						else
							cfg.groupGrowth = option.value
						end
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupGrowth", cfg.groupGrowth, nil, true) end
						GF:ApplyHeaderAttributes(kind)
						if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end
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
			default = (DEFAULTS[kind] and DEFAULTS[kind].highlightHover and DEFAULTS[kind].highlightHover.color) or GFH.COLOR_WHITE_90,
			get = function()
				local hcfg, def = getHighlightCfg("highlightHover")
				local r, g, b, a = unpackColor(hcfg.color, def.color or GFH.COLOR_WHITE_90)
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
			default = (DEFAULTS[kind] and DEFAULTS[kind].highlightTarget and DEFAULTS[kind].highlightTarget.color) or GFH.COLOR_YELLOW,
			get = function()
				local hcfg, def = getHighlightCfg("highlightTarget")
				local r, g, b, a = unpackColor(hcfg.color, def.color or GFH.COLOR_YELLOW)
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
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameColorMode", cfg.status.nameColorMode, nil, true) end
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
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameColorMode", "CUSTOM", nil, true) end
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
				GF:RefreshNames()
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				return tc.showName ~= false
			end,
		},
		{
			name = "Hide ellipsis",
			kind = SettingType.Checkbox,
			field = "nameNoEllipsis",
			parentId = "text",
			get = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.nameNoEllipsis) or false
				if tc.nameNoEllipsis == nil then return def == true end
				return tc.nameNoEllipsis == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.text = cfg.text or {}
				cfg.text.nameNoEllipsis = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameNoEllipsis", cfg.text.nameNoEllipsis, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				GF:RefreshNames()
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				local maxChars = tonumber(tc.nameMaxChars) or 0
				return tc.showName ~= false and maxChars > 0
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
			height = FONT_DROPDOWN_SCROLL_HEIGHT,
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
				for _, option in ipairs(healthTextModeOptions) do
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
				for _, option in ipairs(healthTextModeOptions) do
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
				for _, option in ipairs(healthTextModeOptions) do
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
			height = FONT_DROPDOWN_SCROLL_HEIGHT,
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
			height = FONT_DROPDOWN_SCROLL_HEIGHT,
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
			name = "Status text",
			kind = SettingType.Collapsible,
			id = "statustext",
			defaultCollapsed = true,
		},
		{
			name = "Show status text",
			kind = SettingType.Checkbox,
			field = "statusTextEnabled",
			parentId = "statustext",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				return us.enabled ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.unitStatus = cfg.status.unitStatus or {}
				cfg.status.unitStatus.enabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "statusTextEnabled", cfg.status.unitStatus.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Show offline",
			kind = SettingType.Checkbox,
			field = "statusTextShowOffline",
			parentId = "statustext",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				local def = DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.unitStatus or {}
				if us.showOffline == nil then return def.showOffline ~= false end
				return us.showOffline == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.unitStatus = cfg.status.unitStatus or {}
				cfg.status.unitStatus.showOffline = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "statusTextShowOffline", cfg.status.unitStatus.showOffline, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				return us.enabled ~= false
			end,
		},
		{
			name = "Show AFK",
			kind = SettingType.Checkbox,
			field = "statusTextShowAFK",
			parentId = "statustext",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				local def = DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.unitStatus or {}
				if us.showAFK == nil then return def.showAFK == true end
				return us.showAFK == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.unitStatus = cfg.status.unitStatus or {}
				cfg.status.unitStatus.showAFK = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "statusTextShowAFK", cfg.status.unitStatus.showAFK, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				return us.enabled ~= false
			end,
		},
		{
			name = "Show DND",
			kind = SettingType.Checkbox,
			field = "statusTextShowDND",
			parentId = "statustext",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				local def = DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.unitStatus or {}
				if us.showDND == nil then return def.showDND == true end
				return us.showDND == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.unitStatus = cfg.status.unitStatus or {}
				cfg.status.unitStatus.showDND = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "statusTextShowDND", cfg.status.unitStatus.showDND, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				return us.enabled ~= false
			end,
		},
		{
			name = "Hide health text when offline",
			kind = SettingType.Checkbox,
			field = "statusTextHideHealthTextOffline",
			parentId = "statustext",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				local def = DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.unitStatus or {}
				if us.hideHealthTextWhenOffline == nil then return def.hideHealthTextWhenOffline == true end
				return us.hideHealthTextWhenOffline == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.unitStatus = cfg.status.unitStatus or {}
				cfg.status.unitStatus.hideHealthTextWhenOffline = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "statusTextHideHealthTextOffline", cfg.status.unitStatus.hideHealthTextWhenOffline, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				return us.enabled ~= false
			end,
		},
		{
			name = "Color",
			kind = SettingType.Color,
			field = "statusTextColor",
			parentId = "statustext",
			hasOpacity = true,
			default = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.unitStatus and DEFAULTS[kind].status.unitStatus.color) or { 1, 1, 1, 1 },
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.unitStatus and DEFAULTS[kind].status.unitStatus.color) or { 1, 1, 1, 1 }
				local r, g, b, a = unpackColor(us.color, def)
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.status = cfg.status or {}
				cfg.status.unitStatus = cfg.status.unitStatus or {}
				cfg.status.unitStatus.color = { value.r or 1, value.g or 1, value.b or 1, value.a or 1 }
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "statusTextColor", cfg.status.unitStatus.color, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				return us.enabled ~= false
			end,
		},
		{
			name = "Font size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "statusTextFontSize",
			parentId = "statustext",
			minValue = 8,
			maxValue = 100,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				local hc = cfg and cfg.health or {}
				local defH = (DEFAULTS[kind] and DEFAULTS[kind].health) or {}
				return us.fontSize or hc.fontSize or defH.fontSize or 12
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.unitStatus = cfg.status.unitStatus or {}
				cfg.status.unitStatus.fontSize = clampNumber(value, 8, 100, cfg.status.unitStatus.fontSize or 12)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "statusTextFontSize", cfg.status.unitStatus.fontSize, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				return us.enabled ~= false
			end,
		},
		{
			name = "Font",
			kind = SettingType.Dropdown,
			field = "statusTextFont",
			height = FONT_DROPDOWN_SCROLL_HEIGHT,
			parentId = "statustext",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				local hc = cfg and cfg.health or {}
				local defH = (DEFAULTS[kind] and DEFAULTS[kind].health) or {}
				return us.font or hc.font or defH.font or nil
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.unitStatus = cfg.status.unitStatus or {}
				cfg.status.unitStatus.font = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "statusTextFont", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(fontOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local sc = cfg and cfg.status or {}
						local us = sc.unitStatus or {}
						local hc = cfg and cfg.health or {}
						local defH = (DEFAULTS[kind] and DEFAULTS[kind].health) or {}
						return (us.font or hc.font or defH.font or nil) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.status = cfg.status or {}
						cfg.status.unitStatus = cfg.status.unitStatus or {}
						cfg.status.unitStatus.font = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "statusTextFont", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				return us.enabled ~= false
			end,
		},
		{
			name = "Font outline",
			kind = SettingType.Dropdown,
			field = "statusTextFontOutline",
			parentId = "statustext",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				local hc = cfg and cfg.health or {}
				local defH = (DEFAULTS[kind] and DEFAULTS[kind].health) or {}
				return us.fontOutline or hc.fontOutline or defH.fontOutline or "OUTLINE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.unitStatus = cfg.status.unitStatus or {}
				cfg.status.unitStatus.fontOutline = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "statusTextFontOutline", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(outlineOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local sc = cfg and cfg.status or {}
						local us = sc.unitStatus or {}
						local hc = cfg and cfg.health or {}
						local defH = (DEFAULTS[kind] and DEFAULTS[kind].health) or {}
						return (us.fontOutline or hc.fontOutline or defH.fontOutline or "OUTLINE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.status = cfg.status or {}
						cfg.status.unitStatus = cfg.status.unitStatus or {}
						cfg.status.unitStatus.fontOutline = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "statusTextFontOutline", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				return us.enabled ~= false
			end,
		},
		{
			name = "Anchor",
			kind = SettingType.Dropdown,
			field = "statusTextAnchor",
			parentId = "statustext",
			values = anchorOptions9,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				return us.anchor or "CENTER"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.unitStatus = cfg.status.unitStatus or {}
				cfg.status.unitStatus.anchor = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "statusTextAnchor", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				return us.enabled ~= false
			end,
		},
		{
			name = "Offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "statusTextOffsetX",
			parentId = "statustext",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				return (us.offset and us.offset.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.unitStatus = cfg.status.unitStatus or {}
				cfg.status.unitStatus.offset = cfg.status.unitStatus.offset or {}
				cfg.status.unitStatus.offset.x = clampNumber(value, -200, 200, (cfg.status.unitStatus.offset and cfg.status.unitStatus.offset.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "statusTextOffsetX", cfg.status.unitStatus.offset.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				return us.enabled ~= false
			end,
		},
		{
			name = "Offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "statusTextOffsetY",
			parentId = "statustext",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				return (us.offset and us.offset.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.unitStatus = cfg.status.unitStatus or {}
				cfg.status.unitStatus.offset = cfg.status.unitStatus.offset or {}
				cfg.status.unitStatus.offset.y = clampNumber(value, -200, 200, (cfg.status.unitStatus.offset and cfg.status.unitStatus.offset.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "statusTextOffsetY", cfg.status.unitStatus.offset.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local us = sc.unitStatus or {}
				return us.enabled ~= false
			end,
		},
		{
			name = "",
			kind = SettingType.Divider,
			parentId = "statustext",
			isShown = function() return kind == "raid" end,
		},
		{
			name = "Show",
			kind = SettingType.Checkbox,
			field = "statusTextShowGroup",
			parentId = "statustext",
			get = function() return getGroupNumberEnabledValue() end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.groupNumber = cfg.status.groupNumber or {}
				cfg.status.groupNumber.enabled = value and true or false
				cfg.status.unitStatus = cfg.status.unitStatus or {}
				cfg.status.unitStatus.showGroup = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "statusTextShowGroup", cfg.status.groupNumber.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isStatusTextEnabled() end,
			isShown = function() return kind == "raid" end,
		},
		{
			name = "Format",
			kind = SettingType.Dropdown,
			field = "statusTextGroupFormat",
			parentId = "statustext",
			customDefaultText = getGroupFormatLabel(),
			get = function() return getGroupFormatValue() end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.groupNumber = cfg.status.groupNumber or {}
				cfg.status.groupNumber.format = normalizeGroupNumberFormat(value) or "GROUP"
				cfg.status.unitStatus = cfg.status.unitStatus or {}
				cfg.status.unitStatus.groupFormat = cfg.status.groupNumber.format
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "statusTextGroupFormat", cfg.status.groupNumber.format, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root, data)
				for _, option in ipairs(groupNumberFormatOptions) do
					local value = option and option.value
					if value ~= nil then
						local label = option.label or option.text or tostring(value)
						root:CreateRadio(label, function() return getGroupFormatValue() == value end, function()
							local cfg = getCfg(kind)
							if not cfg then return end
							cfg.status = cfg.status or {}
							cfg.status.groupNumber = cfg.status.groupNumber or {}
							cfg.status.groupNumber.format = value
							cfg.status.unitStatus = cfg.status.unitStatus or {}
							cfg.status.unitStatus.groupFormat = value
							if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "statusTextGroupFormat", value, nil, true) end
							data.customDefaultText = label
							if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RequestRefreshSettings then addon.EditModeLib.internal:RequestRefreshSettings() end
							GF:ApplyHeaderAttributes(kind)
						end)
					end
				end
			end,
			isEnabled = function() return isGroupNumberSettingsEnabled() end,
			isShown = function() return kind == "raid" end,
		},
		{
			name = "Color",
			kind = SettingType.Color,
			field = "groupNumberColor",
			parentId = "statustext",
			hasOpacity = true,
			default = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.groupNumber and DEFAULTS[kind].status.groupNumber.color) or { 1, 1, 1, 1 },
			get = function()
				local cfg = getCfg(kind)
				local def = DEFAULTS[kind] or {}
				local style = resolveGroupNumberStyle(cfg, def, (cfg and cfg.health) or {})
				local r, g, b, a = unpackColor(style.color, GFH.COLOR_WHITE)
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.status = cfg.status or {}
				cfg.status.groupNumber = cfg.status.groupNumber or {}
				cfg.status.groupNumber.color = { value.r or 1, value.g or 1, value.b or 1, value.a or 1 }
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupNumberColor", cfg.status.groupNumber.color, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isGroupNumberSettingsEnabled() end,
			isShown = function() return kind == "raid" end,
		},
		{
			name = "Font size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "groupNumberFontSize",
			parentId = "statustext",
			minValue = 8,
			maxValue = 100,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local def = DEFAULTS[kind] or {}
				local style = resolveGroupNumberStyle(cfg, def, (cfg and cfg.health) or {})
				return style.fontSize or 12
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.groupNumber = cfg.status.groupNumber or {}
				cfg.status.groupNumber.fontSize = clampNumber(value, 8, 100, cfg.status.groupNumber.fontSize or 12)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupNumberFontSize", cfg.status.groupNumber.fontSize, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isGroupNumberSettingsEnabled() end,
			isShown = function() return kind == "raid" end,
		},
		{
			name = "Font",
			kind = SettingType.Dropdown,
			field = "groupNumberFont",
			height = FONT_DROPDOWN_SCROLL_HEIGHT,
			parentId = "statustext",
			get = function()
				local cfg = getCfg(kind)
				local def = DEFAULTS[kind] or {}
				local style = resolveGroupNumberStyle(cfg, def, (cfg and cfg.health) or {})
				return style.font or nil
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.groupNumber = cfg.status.groupNumber or {}
				cfg.status.groupNumber.font = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupNumberFont", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(fontOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local def = DEFAULTS[kind] or {}
						local style = resolveGroupNumberStyle(cfg, def, (cfg and cfg.health) or {})
						return (style.font or nil) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.status = cfg.status or {}
						cfg.status.groupNumber = cfg.status.groupNumber or {}
						cfg.status.groupNumber.font = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupNumberFont", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function() return isGroupNumberSettingsEnabled() end,
			isShown = function() return kind == "raid" end,
		},
		{
			name = "Font outline",
			kind = SettingType.Dropdown,
			field = "groupNumberFontOutline",
			parentId = "statustext",
			get = function()
				local cfg = getCfg(kind)
				local def = DEFAULTS[kind] or {}
				local style = resolveGroupNumberStyle(cfg, def, (cfg and cfg.health) or {})
				return style.fontOutline or "OUTLINE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.groupNumber = cfg.status.groupNumber or {}
				cfg.status.groupNumber.fontOutline = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupNumberFontOutline", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(outlineOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local def = DEFAULTS[kind] or {}
						local style = resolveGroupNumberStyle(cfg, def, (cfg and cfg.health) or {})
						return (style.fontOutline or "OUTLINE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.status = cfg.status or {}
						cfg.status.groupNumber = cfg.status.groupNumber or {}
						cfg.status.groupNumber.fontOutline = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupNumberFontOutline", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function() return isGroupNumberSettingsEnabled() end,
			isShown = function() return kind == "raid" end,
		},
		{
			name = "Anchor",
			kind = SettingType.Dropdown,
			field = "groupNumberAnchor",
			parentId = "statustext",
			values = anchorOptions9,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local def = DEFAULTS[kind] or {}
				local style = resolveGroupNumberStyle(cfg, def, (cfg and cfg.health) or {})
				return style.anchor or "CENTER"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.groupNumber = cfg.status.groupNumber or {}
				cfg.status.groupNumber.anchor = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupNumberAnchor", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isGroupNumberSettingsEnabled() end,
			isShown = function() return kind == "raid" end,
		},
		{
			name = "Offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "groupNumberOffsetX",
			parentId = "statustext",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local def = DEFAULTS[kind] or {}
				local style = resolveGroupNumberStyle(cfg, def, (cfg and cfg.health) or {})
				local off = style.offset or {}
				return off.x or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.groupNumber = cfg.status.groupNumber or {}
				cfg.status.groupNumber.offset = cfg.status.groupNumber.offset or {}
				cfg.status.groupNumber.offset.x = clampNumber(value, -200, 200, (cfg.status.groupNumber.offset and cfg.status.groupNumber.offset.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupNumberOffsetX", cfg.status.groupNumber.offset.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isGroupNumberSettingsEnabled() end,
			isShown = function() return kind == "raid" end,
		},
		{
			name = "Offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "groupNumberOffsetY",
			parentId = "statustext",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local def = DEFAULTS[kind] or {}
				local style = resolveGroupNumberStyle(cfg, def, (cfg and cfg.health) or {})
				local off = style.offset or {}
				return off.y or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.groupNumber = cfg.status.groupNumber or {}
				cfg.status.groupNumber.offset = cfg.status.groupNumber.offset or {}
				cfg.status.groupNumber.offset.y = clampNumber(value, -200, 200, (cfg.status.groupNumber.offset and cfg.status.groupNumber.offset.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupNumberOffsetY", cfg.status.groupNumber.offset.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isGroupNumberSettingsEnabled() end,
			isShown = function() return kind == "raid" end,
		},
		{
			name = "Dispel indicator",
			kind = SettingType.Collapsible,
			id = "dispeltint",
			defaultCollapsed = true,
		},
		{
			name = "Enable overlay",
			kind = SettingType.Checkbox,
			field = "dispelTintEnabled",
			parentId = "dispeltint",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				if dt.enabled == nil then return def.enabled ~= false end
				return dt.enabled == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.dispelTint = cfg.status.dispelTint or {}
				cfg.status.dispelTint.enabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "dispelTintEnabled", cfg.status.dispelTint.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				GF:RefreshDispelTint()
			end,
		},
		{
			name = "Background color change",
			kind = SettingType.Checkbox,
			field = "dispelTintFillEnabled",
			parentId = "dispeltint",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				if dt.fillEnabled == nil then return def.fillEnabled ~= false end
				return dt.fillEnabled == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.dispelTint = cfg.status.dispelTint or {}
				cfg.status.dispelTint.fillEnabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "dispelTintFillEnabled", cfg.status.dispelTint.fillEnabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				GF:RefreshDispelTint()
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				if dt.enabled == nil then return def.enabled ~= false end
				return dt.enabled == true
			end,
		},
		{
			name = "Background color",
			kind = SettingType.Color,
			field = "dispelTintFillColor",
			parentId = "dispeltint",
			hasOpacity = false,
			default = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint and DEFAULTS[kind].status.dispelTint.fillColor) or { 0, 0, 0, 1 },
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint and DEFAULTS[kind].status.dispelTint.fillColor) or { 0, 0, 0, 1 }
				local r, g, b, a = unpackColor(dt.fillColor, def)
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.status = cfg.status or {}
				cfg.status.dispelTint = cfg.status.dispelTint or {}
				cfg.status.dispelTint.fillColor = { value.r or 0, value.g or 0, value.b or 0, 1 }
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "dispelTintFillColor", cfg.status.dispelTint.fillColor, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				GF:RefreshDispelTint()
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				local enabled = dt.enabled
				if enabled == nil then enabled = def.enabled ~= false end
				local fillEnabled = dt.fillEnabled
				if fillEnabled == nil then fillEnabled = def.fillEnabled ~= false end
				return enabled and fillEnabled
			end,
		},
		{
			name = "Background alpha",
			kind = SettingType.Slider,
			allowInput = true,
			field = "dispelTintFillAlpha",
			parentId = "dispeltint",
			minValue = 0,
			maxValue = 1,
			valueStep = 0.01,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				return dt.fillAlpha or def.fillAlpha or 0.2
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.dispelTint = cfg.status.dispelTint or {}
				cfg.status.dispelTint.fillAlpha = clampNumber(value, 0, 1, cfg.status.dispelTint.fillAlpha or 0.2)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "dispelTintFillAlpha", cfg.status.dispelTint.fillAlpha, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				GF:RefreshDispelTint()
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				local enabled = dt.enabled
				if enabled == nil then enabled = def.enabled ~= false end
				local fillEnabled = dt.fillEnabled
				if fillEnabled == nil then fillEnabled = def.fillEnabled ~= false end
				return enabled and fillEnabled
			end,
		},
		{
			name = "Tint alpha",
			kind = SettingType.Slider,
			allowInput = true,
			field = "dispelTintAlpha",
			parentId = "dispeltint",
			minValue = 0,
			maxValue = 1,
			valueStep = 0.01,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				return dt.alpha or def.alpha or 0.25
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.dispelTint = cfg.status.dispelTint or {}
				cfg.status.dispelTint.alpha = clampNumber(value, 0, 1, cfg.status.dispelTint.alpha or 0.25)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "dispelTintAlpha", cfg.status.dispelTint.alpha, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				GF:RefreshDispelTint()
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				if dt.enabled == nil then return def.enabled ~= false end
				return dt.enabled == true
			end,
		},
		{
			name = "Show sample",
			kind = SettingType.Checkbox,
			field = "dispelTintSample",
			parentId = "dispeltint",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				if dt.showSample == nil then return def.showSample == true end
				return dt.showSample == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.dispelTint = cfg.status.dispelTint or {}
				cfg.status.dispelTint.showSample = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "dispelTintSample", cfg.status.dispelTint.showSample, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				GF:RefreshDispelTint()
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				local overlayEnabled = dt.enabled
				if overlayEnabled == nil then overlayEnabled = def.enabled ~= false end
				local glowEnabled = dt.glowEnabled
				if glowEnabled == nil then glowEnabled = def.glowEnabled == true end
				return overlayEnabled == true or glowEnabled == true
			end,
		},
		{
			name = "",
			kind = SettingType.Divider,
			parentId = "dispeltint",
		},
		{
			name = "Enable glow",
			kind = SettingType.Checkbox,
			field = "dispelTintGlowEnabled",
			parentId = "dispeltint",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				if dt.glowEnabled == nil then return def.glowEnabled == true end
				return dt.glowEnabled == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.dispelTint = cfg.status.dispelTint or {}
				cfg.status.dispelTint.glowEnabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "dispelTintGlowEnabled", cfg.status.dispelTint.glowEnabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				GF:RefreshDispelTint()
			end,
		},
		{
			name = "Glow color",
			kind = SettingType.Dropdown,
			field = "dispelTintGlowColorMode",
			parentId = "dispeltint",
			generator = function(_, root, data)
				root:CreateRadio("Dispell color", function() return data.get and data.get() == "DISPEL" end, function()
					if data.set then data.set(nil, "DISPEL") end
					if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RequestRefreshSettings then addon.EditModeLib.internal:RequestRefreshSettings() end
				end)
				root:CreateRadio("Custom color", function() return data.get and data.get() == "CUSTOM" end, function()
					if data.set then data.set(nil, "CUSTOM") end
					if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RequestRefreshSettings then addon.EditModeLib.internal:RequestRefreshSettings() end
				end)
			end,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				return dt.glowColorMode or def.glowColorMode or "DISPEL"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.dispelTint = cfg.status.dispelTint or {}
				cfg.status.dispelTint.glowColorMode = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "dispelTintGlowColorMode", value, nil, true) end
				GF:RefreshDispelTint()
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				local glowEnabled = dt.glowEnabled
				if glowEnabled == nil then glowEnabled = def.glowEnabled == true end
				return glowEnabled == true
			end,
		},
		{
			name = "Custom glow color",
			kind = SettingType.Color,
			field = "dispelTintGlowColor",
			parentId = "dispeltint",
			hasOpacity = false,
			default = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint and DEFAULTS[kind].status.dispelTint.glowColor) or { 1, 1, 1, 1 },
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint and DEFAULTS[kind].status.dispelTint.glowColor) or { 1, 1, 1, 1 }
				local r, g, b, a = unpackColor(dt.glowColor, def)
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.status = cfg.status or {}
				cfg.status.dispelTint = cfg.status.dispelTint or {}
				cfg.status.dispelTint.glowColor = { value.r or 1, value.g or 1, value.b or 1, 1 }
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "dispelTintGlowColor", cfg.status.dispelTint.glowColor, nil, true) end
				GF:RefreshDispelTint()
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				local mode = dt.glowColorMode or def.glowColorMode or "DISPEL"
				return mode == "CUSTOM"
			end,
		},
		{
			name = "Glow effect",
			kind = SettingType.Dropdown,
			field = "dispelTintGlowEffect",
			parentId = "dispeltint",
			generator = function(_, root, data)
				local options = {
					{ value = "PIXEL", label = "Pixel" },
					{ value = "SHINE", label = "Shine" },
					{ value = "BLIZZARD", label = "Blizzard" },
				}
				for _, option in ipairs(options) do
					root:CreateRadio(option.label, function() return data.get and data.get() == option.value end, function()
						if data.set then data.set(nil, option.value) end
						if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RequestRefreshSettings then addon.EditModeLib.internal:RequestRefreshSettings() end
					end)
				end
			end,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				return dt.glowEffect or def.glowEffect or "PIXEL"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.dispelTint = cfg.status.dispelTint or {}
				cfg.status.dispelTint.glowEffect = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "dispelTintGlowEffect", value, nil, true) end
				GF:RefreshDispelTint()
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				local glowEnabled = dt.glowEnabled
				if glowEnabled == nil then glowEnabled = def.glowEnabled == true end
				return glowEnabled == true
			end,
		},
		{
			name = "Animation speed",
			kind = SettingType.Slider,
			allowInput = true,
			field = "dispelTintGlowFrequency",
			parentId = "dispeltint",
			minValue = -1.5,
			maxValue = 1.5,
			valueStep = 0.25,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				return dt.glowFrequency or def.glowFrequency or 0.25
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.dispelTint = cfg.status.dispelTint or {}
				cfg.status.dispelTint.glowFrequency = clampNumber(value, -1.5, 1.5, cfg.status.dispelTint.glowFrequency or 0.25)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "dispelTintGlowFrequency", cfg.status.dispelTint.glowFrequency, nil, true) end
				GF:RefreshDispelTint()
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				local glowEnabled = dt.glowEnabled
				if glowEnabled == nil then glowEnabled = def.glowEnabled == true end
				return glowEnabled == true
			end,
		},
		{
			name = "X Offset",
			kind = SettingType.Slider,
			allowInput = true,
			field = "dispelTintGlowX",
			parentId = "dispeltint",
			minValue = -10,
			maxValue = 10,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				return dt.glowX or def.glowX or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.dispelTint = cfg.status.dispelTint or {}
				cfg.status.dispelTint.glowX = clampNumber(value, -10, 10, cfg.status.dispelTint.glowX or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "dispelTintGlowX", cfg.status.dispelTint.glowX, nil, true) end
				GF:RefreshDispelTint()
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				local glowEnabled = dt.glowEnabled
				if glowEnabled == nil then glowEnabled = def.glowEnabled == true end
				return glowEnabled == true
			end,
		},
		{
			name = "Y Offset",
			kind = SettingType.Slider,
			allowInput = true,
			field = "dispelTintGlowY",
			parentId = "dispeltint",
			minValue = -10,
			maxValue = 10,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				return dt.glowY or def.glowY or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.dispelTint = cfg.status.dispelTint or {}
				cfg.status.dispelTint.glowY = clampNumber(value, -10, 10, cfg.status.dispelTint.glowY or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "dispelTintGlowY", cfg.status.dispelTint.glowY, nil, true) end
				GF:RefreshDispelTint()
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				local glowEnabled = dt.glowEnabled
				if glowEnabled == nil then glowEnabled = def.glowEnabled == true end
				return glowEnabled == true
			end,
		},
		{
			name = "Number of lines",
			kind = SettingType.Slider,
			allowInput = true,
			field = "dispelTintGlowLines",
			parentId = "dispeltint",
			minValue = 1,
			maxValue = 20,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				return dt.glowLines or def.glowLines or 8
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.dispelTint = cfg.status.dispelTint or {}
				cfg.status.dispelTint.glowLines = clampNumber(value, 1, 20, cfg.status.dispelTint.glowLines or 8)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "dispelTintGlowLines", cfg.status.dispelTint.glowLines, nil, true) end
				GF:RefreshDispelTint()
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				local glowEnabled = dt.glowEnabled
				if glowEnabled == nil then glowEnabled = def.glowEnabled == true end
				return glowEnabled == true
			end,
		},
		{
			name = "Thickness",
			kind = SettingType.Slider,
			allowInput = true,
			field = "dispelTintGlowThickness",
			parentId = "dispeltint",
			minValue = 1,
			maxValue = 10,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				return dt.glowThickness or def.glowThickness or 3
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.dispelTint = cfg.status.dispelTint or {}
				cfg.status.dispelTint.glowThickness = clampNumber(value, 1, 10, cfg.status.dispelTint.glowThickness or 3)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "dispelTintGlowThickness", cfg.status.dispelTint.glowThickness, nil, true) end
				GF:RefreshDispelTint()
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local dt = sc.dispelTint or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.dispelTint) or {}
				local glowEnabled = dt.glowEnabled
				if glowEnabled == nil then glowEnabled = def.glowEnabled == true end
				return glowEnabled == true
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
				return GFH.SelectionContains(selection, value)
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
				return GFH.SelectionContains(selection, value)
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
						if opt.value ~= "__ALL__" and not GFH.SelectionContains(selection, opt.value) then return false end
					end
					return true
				end
				if type(selection) ~= "table" then return true end
				return GFH.SelectionContains(selection, value)
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
			height = FONT_DROPDOWN_SCROLL_HEIGHT,
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
				GFH.SyncAurasEnabled(cfg)
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
			name = "",
			kind = SettingType.Divider,
			parentId = "buffs",
		},
		{
			name = "Show cooldown text",
			kind = SettingType.Checkbox,
			field = "buffCooldownTextEnabled",
			parentId = "buffs",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				local def = (DEFAULTS[kind] and DEFAULTS[kind].auras and DEFAULTS[kind].auras.buff) or {}
				if ac.buff.showCooldownText == nil then return def.showCooldownText ~= false end
				return ac.buff.showCooldownText ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.buff.showCooldownText = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffCooldownTextEnabled", ac.buff.showCooldownText, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Cooldown text anchor",
			kind = SettingType.Dropdown,
			field = "buffCooldownTextAnchor",
			parentId = "buffs",
			values = anchorOptions9,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.cooldownAnchor or "CENTER"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.buff.cooldownAnchor = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffCooldownTextAnchor", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Cooldown text offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "buffCooldownTextOffsetX",
			parentId = "buffs",
			minValue = -50,
			maxValue = 50,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return (ac.buff.cooldownOffset and ac.buff.cooldownOffset.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.buff.cooldownOffset = ac.buff.cooldownOffset or {}
				ac.buff.cooldownOffset.x = clampNumber(value, -50, 50, (ac.buff.cooldownOffset and ac.buff.cooldownOffset.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffCooldownTextOffsetX", ac.buff.cooldownOffset.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Cooldown text offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "buffCooldownTextOffsetY",
			parentId = "buffs",
			minValue = -50,
			maxValue = 50,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return (ac.buff.cooldownOffset and ac.buff.cooldownOffset.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.buff.cooldownOffset = ac.buff.cooldownOffset or {}
				ac.buff.cooldownOffset.y = clampNumber(value, -50, 50, (ac.buff.cooldownOffset and ac.buff.cooldownOffset.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffCooldownTextOffsetY", ac.buff.cooldownOffset.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Cooldown text size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "buffCooldownTextSize",
			parentId = "buffs",
			minValue = 6,
			maxValue = 30,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.cooldownFontSize or 12
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.buff.cooldownFontSize = clampNumber(value, 6, 30, ac.buff.cooldownFontSize or 12)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffCooldownTextSize", ac.buff.cooldownFontSize, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Cooldown text font",
			kind = SettingType.Dropdown,
			field = "buffCooldownTextFont",
			height = FONT_DROPDOWN_SCROLL_HEIGHT,
			parentId = "buffs",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.cooldownFont or nil
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.buff.cooldownFont = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffCooldownTextFont", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(fontOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local ac = ensureAuraConfig(cfg)
						return (ac.buff.cooldownFont or nil) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						local ac = ensureAuraConfig(cfg)
						ac.buff.cooldownFont = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffCooldownTextFont", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Cooldown text outline",
			kind = SettingType.Dropdown,
			field = "buffCooldownTextOutline",
			parentId = "buffs",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.cooldownFontOutline or "OUTLINE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.buff.cooldownFontOutline = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffCooldownTextOutline", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(outlineOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local ac = ensureAuraConfig(cfg)
						return (ac.buff.cooldownFontOutline or "OUTLINE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						local ac = ensureAuraConfig(cfg)
						ac.buff.cooldownFontOutline = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffCooldownTextOutline", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "",
			kind = SettingType.Divider,
			parentId = "buffs",
		},
		{
			name = "Show stacks",
			kind = SettingType.Checkbox,
			field = "buffStackTextEnabled",
			parentId = "buffs",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				local def = (DEFAULTS[kind] and DEFAULTS[kind].auras and DEFAULTS[kind].auras.buff) or {}
				if ac.buff.showStacks == nil then return def.showStacks ~= false end
				return ac.buff.showStacks ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.buff.showStacks = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffStackTextEnabled", ac.buff.showStacks, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Stack anchor",
			kind = SettingType.Dropdown,
			field = "buffStackAnchor",
			parentId = "buffs",
			values = anchorOptions9,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.countAnchor or "BOTTOMRIGHT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.buff.countAnchor = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffStackAnchor", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Stack offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "buffStackOffsetX",
			parentId = "buffs",
			minValue = -50,
			maxValue = 50,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return (ac.buff.countOffset and ac.buff.countOffset.x) or -2
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.buff.countOffset = ac.buff.countOffset or {}
				ac.buff.countOffset.x = clampNumber(value, -50, 50, (ac.buff.countOffset and ac.buff.countOffset.x) or -2)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffStackOffsetX", ac.buff.countOffset.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Stack offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "buffStackOffsetY",
			parentId = "buffs",
			minValue = -50,
			maxValue = 50,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return (ac.buff.countOffset and ac.buff.countOffset.y) or 2
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.buff.countOffset = ac.buff.countOffset or {}
				ac.buff.countOffset.y = clampNumber(value, -50, 50, (ac.buff.countOffset and ac.buff.countOffset.y) or 2)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffStackOffsetY", ac.buff.countOffset.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Stack size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "buffStackSize",
			parentId = "buffs",
			minValue = 6,
			maxValue = 30,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.countFontSize or 12
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.buff.countFontSize = clampNumber(value, 6, 30, ac.buff.countFontSize or 12)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffStackSize", ac.buff.countFontSize, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Stack font",
			kind = SettingType.Dropdown,
			field = "buffStackFont",
			height = FONT_DROPDOWN_SCROLL_HEIGHT,
			parentId = "buffs",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.countFont or nil
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.buff.countFont = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffStackFont", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(fontOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local ac = ensureAuraConfig(cfg)
						return (ac.buff.countFont or nil) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						local ac = ensureAuraConfig(cfg)
						ac.buff.countFont = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffStackFont", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Stack outline",
			kind = SettingType.Dropdown,
			field = "buffStackOutline",
			parentId = "buffs",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.countFontOutline or "OUTLINE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.buff.countFontOutline = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffStackOutline", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(outlineOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local ac = ensureAuraConfig(cfg)
						return (ac.buff.countFontOutline or "OUTLINE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						local ac = ensureAuraConfig(cfg)
						ac.buff.countFontOutline = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffStackOutline", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
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
				GFH.SyncAurasEnabled(cfg)
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
			name = "Show dispel icon",
			kind = SettingType.Checkbox,
			field = "debuffShowDispelIcon",
			parentId = "debuffs",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				local def = (DEFAULTS[kind] and DEFAULTS[kind].auras and DEFAULTS[kind].auras.debuff) or {}
				if ac.debuff.showDispelIcon == nil then return def.showDispelIcon ~= false end
				return ac.debuff.showDispelIcon ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.debuff.showDispelIcon = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffShowDispelIcon", ac.debuff.showDispelIcon, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "",
			kind = SettingType.Divider,
			parentId = "debuffs",
		},
		{
			name = "Show cooldown text",
			kind = SettingType.Checkbox,
			field = "debuffCooldownTextEnabled",
			parentId = "debuffs",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				local def = (DEFAULTS[kind] and DEFAULTS[kind].auras and DEFAULTS[kind].auras.debuff) or {}
				if ac.debuff.showCooldownText == nil then return def.showCooldownText ~= false end
				return ac.debuff.showCooldownText ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.debuff.showCooldownText = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffCooldownTextEnabled", ac.debuff.showCooldownText, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Cooldown text anchor",
			kind = SettingType.Dropdown,
			field = "debuffCooldownTextAnchor",
			parentId = "debuffs",
			values = anchorOptions9,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.cooldownAnchor or "CENTER"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.debuff.cooldownAnchor = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffCooldownTextAnchor", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Cooldown text offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "debuffCooldownTextOffsetX",
			parentId = "debuffs",
			minValue = -50,
			maxValue = 50,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return (ac.debuff.cooldownOffset and ac.debuff.cooldownOffset.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.debuff.cooldownOffset = ac.debuff.cooldownOffset or {}
				ac.debuff.cooldownOffset.x = clampNumber(value, -50, 50, (ac.debuff.cooldownOffset and ac.debuff.cooldownOffset.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffCooldownTextOffsetX", ac.debuff.cooldownOffset.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Cooldown text offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "debuffCooldownTextOffsetY",
			parentId = "debuffs",
			minValue = -50,
			maxValue = 50,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return (ac.debuff.cooldownOffset and ac.debuff.cooldownOffset.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.debuff.cooldownOffset = ac.debuff.cooldownOffset or {}
				ac.debuff.cooldownOffset.y = clampNumber(value, -50, 50, (ac.debuff.cooldownOffset and ac.debuff.cooldownOffset.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffCooldownTextOffsetY", ac.debuff.cooldownOffset.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Cooldown text size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "debuffCooldownTextSize",
			parentId = "debuffs",
			minValue = 6,
			maxValue = 30,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.cooldownFontSize or 12
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.debuff.cooldownFontSize = clampNumber(value, 6, 30, ac.debuff.cooldownFontSize or 12)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffCooldownTextSize", ac.debuff.cooldownFontSize, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Cooldown text font",
			kind = SettingType.Dropdown,
			field = "debuffCooldownTextFont",
			height = FONT_DROPDOWN_SCROLL_HEIGHT,
			parentId = "debuffs",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.cooldownFont or nil
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.debuff.cooldownFont = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffCooldownTextFont", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(fontOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local ac = ensureAuraConfig(cfg)
						return (ac.debuff.cooldownFont or nil) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						local ac = ensureAuraConfig(cfg)
						ac.debuff.cooldownFont = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffCooldownTextFont", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Cooldown text outline",
			kind = SettingType.Dropdown,
			field = "debuffCooldownTextOutline",
			parentId = "debuffs",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.cooldownFontOutline or "OUTLINE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.debuff.cooldownFontOutline = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffCooldownTextOutline", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(outlineOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local ac = ensureAuraConfig(cfg)
						return (ac.debuff.cooldownFontOutline or "OUTLINE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						local ac = ensureAuraConfig(cfg)
						ac.debuff.cooldownFontOutline = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffCooldownTextOutline", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "",
			kind = SettingType.Divider,
			parentId = "debuffs",
		},
		{
			name = "Show stacks",
			kind = SettingType.Checkbox,
			field = "debuffStackTextEnabled",
			parentId = "debuffs",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				local def = (DEFAULTS[kind] and DEFAULTS[kind].auras and DEFAULTS[kind].auras.debuff) or {}
				if ac.debuff.showStacks == nil then return def.showStacks ~= false end
				return ac.debuff.showStacks ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.debuff.showStacks = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffStackTextEnabled", ac.debuff.showStacks, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Stack anchor",
			kind = SettingType.Dropdown,
			field = "debuffStackAnchor",
			parentId = "debuffs",
			values = anchorOptions9,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.countAnchor or "BOTTOMRIGHT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.debuff.countAnchor = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffStackAnchor", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Stack offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "debuffStackOffsetX",
			parentId = "debuffs",
			minValue = -50,
			maxValue = 50,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return (ac.debuff.countOffset and ac.debuff.countOffset.x) or -2
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.debuff.countOffset = ac.debuff.countOffset or {}
				ac.debuff.countOffset.x = clampNumber(value, -50, 50, (ac.debuff.countOffset and ac.debuff.countOffset.x) or -2)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffStackOffsetX", ac.debuff.countOffset.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Stack offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "debuffStackOffsetY",
			parentId = "debuffs",
			minValue = -50,
			maxValue = 50,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return (ac.debuff.countOffset and ac.debuff.countOffset.y) or 2
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.debuff.countOffset = ac.debuff.countOffset or {}
				ac.debuff.countOffset.y = clampNumber(value, -50, 50, (ac.debuff.countOffset and ac.debuff.countOffset.y) or 2)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffStackOffsetY", ac.debuff.countOffset.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Stack size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "debuffStackSize",
			parentId = "debuffs",
			minValue = 6,
			maxValue = 30,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.countFontSize or 12
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.debuff.countFontSize = clampNumber(value, 6, 30, ac.debuff.countFontSize or 12)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffStackSize", ac.debuff.countFontSize, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Stack font",
			kind = SettingType.Dropdown,
			field = "debuffStackFont",
			height = FONT_DROPDOWN_SCROLL_HEIGHT,
			parentId = "debuffs",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.countFont or nil
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.debuff.countFont = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffStackFont", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(fontOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local ac = ensureAuraConfig(cfg)
						return (ac.debuff.countFont or nil) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						local ac = ensureAuraConfig(cfg)
						ac.debuff.countFont = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffStackFont", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Stack outline",
			kind = SettingType.Dropdown,
			field = "debuffStackOutline",
			parentId = "debuffs",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.countFontOutline or "OUTLINE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.debuff.countFontOutline = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffStackOutline", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(outlineOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local ac = ensureAuraConfig(cfg)
						return (ac.debuff.countFontOutline or "OUTLINE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						local ac = ensureAuraConfig(cfg)
						ac.debuff.countFontOutline = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffStackOutline", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
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
				GFH.SyncAurasEnabled(cfg)
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
			name = "",
			kind = SettingType.Divider,
			parentId = "externals",
		},
		{
			name = "Show cooldown text",
			kind = SettingType.Checkbox,
			field = "externalCooldownTextEnabled",
			parentId = "externals",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				local def = (DEFAULTS[kind] and DEFAULTS[kind].auras and DEFAULTS[kind].auras.externals) or {}
				if ac.externals.showCooldownText == nil then return def.showCooldownText ~= false end
				return ac.externals.showCooldownText ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.externals.showCooldownText = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalCooldownTextEnabled", ac.externals.showCooldownText, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Cooldown text anchor",
			kind = SettingType.Dropdown,
			field = "externalCooldownTextAnchor",
			parentId = "externals",
			values = anchorOptions9,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.cooldownAnchor or "CENTER"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.externals.cooldownAnchor = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalCooldownTextAnchor", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Cooldown text offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalCooldownTextOffsetX",
			parentId = "externals",
			minValue = -50,
			maxValue = 50,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return (ac.externals.cooldownOffset and ac.externals.cooldownOffset.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.externals.cooldownOffset = ac.externals.cooldownOffset or {}
				ac.externals.cooldownOffset.x = clampNumber(value, -50, 50, (ac.externals.cooldownOffset and ac.externals.cooldownOffset.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalCooldownTextOffsetX", ac.externals.cooldownOffset.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Cooldown text offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalCooldownTextOffsetY",
			parentId = "externals",
			minValue = -50,
			maxValue = 50,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return (ac.externals.cooldownOffset and ac.externals.cooldownOffset.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.externals.cooldownOffset = ac.externals.cooldownOffset or {}
				ac.externals.cooldownOffset.y = clampNumber(value, -50, 50, (ac.externals.cooldownOffset and ac.externals.cooldownOffset.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalCooldownTextOffsetY", ac.externals.cooldownOffset.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Cooldown text size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalCooldownTextSize",
			parentId = "externals",
			minValue = 6,
			maxValue = 30,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.cooldownFontSize or 12
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.externals.cooldownFontSize = clampNumber(value, 6, 30, ac.externals.cooldownFontSize or 12)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalCooldownTextSize", ac.externals.cooldownFontSize, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Cooldown text font",
			kind = SettingType.Dropdown,
			field = "externalCooldownTextFont",
			height = FONT_DROPDOWN_SCROLL_HEIGHT,
			parentId = "externals",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.cooldownFont or nil
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.externals.cooldownFont = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalCooldownTextFont", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(fontOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local ac = ensureAuraConfig(cfg)
						return (ac.externals.cooldownFont or nil) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						local ac = ensureAuraConfig(cfg)
						ac.externals.cooldownFont = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalCooldownTextFont", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Cooldown text outline",
			kind = SettingType.Dropdown,
			field = "externalCooldownTextOutline",
			parentId = "externals",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.cooldownFontOutline or "OUTLINE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.externals.cooldownFontOutline = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalCooldownTextOutline", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(outlineOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local ac = ensureAuraConfig(cfg)
						return (ac.externals.cooldownFontOutline or "OUTLINE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						local ac = ensureAuraConfig(cfg)
						ac.externals.cooldownFontOutline = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalCooldownTextOutline", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "",
			kind = SettingType.Divider,
			parentId = "externals",
		},
		{
			name = "Show stacks",
			kind = SettingType.Checkbox,
			field = "externalStackTextEnabled",
			parentId = "externals",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				local def = (DEFAULTS[kind] and DEFAULTS[kind].auras and DEFAULTS[kind].auras.externals) or {}
				if ac.externals.showStacks == nil then return def.showStacks ~= false end
				return ac.externals.showStacks ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.externals.showStacks = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalStackTextEnabled", ac.externals.showStacks, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Stack anchor",
			kind = SettingType.Dropdown,
			field = "externalStackAnchor",
			parentId = "externals",
			values = anchorOptions9,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.countAnchor or "BOTTOMRIGHT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.externals.countAnchor = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalStackAnchor", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Stack offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalStackOffsetX",
			parentId = "externals",
			minValue = -50,
			maxValue = 50,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return (ac.externals.countOffset and ac.externals.countOffset.x) or -2
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.externals.countOffset = ac.externals.countOffset or {}
				ac.externals.countOffset.x = clampNumber(value, -50, 50, (ac.externals.countOffset and ac.externals.countOffset.x) or -2)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalStackOffsetX", ac.externals.countOffset.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Stack offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalStackOffsetY",
			parentId = "externals",
			minValue = -50,
			maxValue = 50,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return (ac.externals.countOffset and ac.externals.countOffset.y) or 2
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.externals.countOffset = ac.externals.countOffset or {}
				ac.externals.countOffset.y = clampNumber(value, -50, 50, (ac.externals.countOffset and ac.externals.countOffset.y) or 2)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalStackOffsetY", ac.externals.countOffset.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Stack size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalStackSize",
			parentId = "externals",
			minValue = 6,
			maxValue = 30,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.countFontSize or 12
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.externals.countFontSize = clampNumber(value, 6, 30, ac.externals.countFontSize or 12)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalStackSize", ac.externals.countFontSize, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Stack font",
			kind = SettingType.Dropdown,
			field = "externalStackFont",
			height = FONT_DROPDOWN_SCROLL_HEIGHT,
			parentId = "externals",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.countFont or nil
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.externals.countFont = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalStackFont", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(fontOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local ac = ensureAuraConfig(cfg)
						return (ac.externals.countFont or nil) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						local ac = ensureAuraConfig(cfg)
						ac.externals.countFont = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalStackFont", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Stack outline",
			kind = SettingType.Dropdown,
			field = "externalStackOutline",
			parentId = "externals",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.countFontOutline or "OUTLINE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local ac = ensureAuraConfig(cfg)
				ac.externals.countFontOutline = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalStackOutline", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(outlineOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local ac = ensureAuraConfig(cfg)
						return (ac.externals.countFontOutline or "OUTLINE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						local ac = ensureAuraConfig(cfg)
						ac.externals.countFontOutline = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalStackOutline", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
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
			height = FONT_DROPDOWN_SCROLL_HEIGHT,
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
		{
			name = "Private Auras",
			kind = SettingType.Collapsible,
			id = "privateAuras",
			defaultCollapsed = true,
		},
		{
			name = "Enable private auras",
			kind = SettingType.Checkbox,
			field = "privateAurasEnabled",
			parentId = "privateAuras",
			get = function() return isPrivateAurasEnabled() end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = ensurePrivateAuraConfig(cfg)
				if not pcfg then return end
				pcfg.enabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "privateAurasEnabled", pcfg.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Amount",
			kind = SettingType.Slider,
			allowInput = true,
			field = "privateAurasAmount",
			parentId = "privateAuras",
			minValue = 1,
			maxValue = 10,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.privateAuras or {}
				local icon = pcfg.icon or {}
				local defIcon = defPrivateAuras.icon or {}
				return icon.amount or defIcon.amount or 2
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = ensurePrivateAuraConfig(cfg)
				if not pcfg then return end
				pcfg.icon.amount = clampNumber(value, 1, 10, pcfg.icon.amount or 2)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "privateAurasAmount", pcfg.icon.amount, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = isPrivateAurasEnabled,
		},
		{
			name = "Icon size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "privateAurasSize",
			parentId = "privateAuras",
			minValue = 8,
			maxValue = 60,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.privateAuras or {}
				local icon = pcfg.icon or {}
				local defIcon = defPrivateAuras.icon or {}
				return icon.size or defIcon.size or 20
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = ensurePrivateAuraConfig(cfg)
				if not pcfg then return end
				pcfg.icon.size = clampNumber(value, 8, 60, pcfg.icon.size or 20)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "privateAurasSize", pcfg.icon.size, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = isPrivateAurasEnabled,
		},
		{
			name = "Icon direction",
			kind = SettingType.Dropdown,
			field = "privateAurasPoint",
			parentId = "privateAuras",
			values = privateAuraPointOptions,
			height = 120,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.privateAuras or {}
				local icon = pcfg.icon or {}
				local defIcon = defPrivateAuras.icon or {}
				return icon.point or defIcon.point or "LEFT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = ensurePrivateAuraConfig(cfg)
				if not pcfg then return end
				pcfg.icon.point = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "privateAurasPoint", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = isPrivateAurasEnabled,
		},
		{
			name = "Icon spacing",
			kind = SettingType.Slider,
			allowInput = true,
			field = "privateAurasOffset",
			parentId = "privateAuras",
			minValue = 0,
			maxValue = 20,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.privateAuras or {}
				local icon = pcfg.icon or {}
				local defIcon = defPrivateAuras.icon or {}
				return icon.offset or defIcon.offset or 2
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = ensurePrivateAuraConfig(cfg)
				if not pcfg then return end
				pcfg.icon.offset = clampNumber(value, 0, 20, pcfg.icon.offset or 2)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "privateAurasOffset", pcfg.icon.offset, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = isPrivateAurasEnabled,
		},
		{
			name = "Anchor point",
			kind = SettingType.Dropdown,
			field = "privateAurasParentPoint",
			parentId = "privateAuras",
			values = auraAnchorOptions,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.privateAuras or {}
				local parentCfg = pcfg.parent or {}
				local defParent = defPrivateAuras.parent or {}
				return parentCfg.point or defParent.point or "CENTER"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = ensurePrivateAuraConfig(cfg)
				if not pcfg then return end
				pcfg.parent.point = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "privateAurasParentPoint", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = isPrivateAurasEnabled,
		},
		{
			name = "Anchor offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "privateAurasParentOffsetX",
			parentId = "privateAuras",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.privateAuras or {}
				local parentCfg = pcfg.parent or {}
				local defParent = defPrivateAuras.parent or {}
				return parentCfg.offsetX or defParent.offsetX or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = ensurePrivateAuraConfig(cfg)
				if not pcfg then return end
				pcfg.parent.offsetX = clampNumber(value, -200, 200, pcfg.parent.offsetX or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "privateAurasParentOffsetX", pcfg.parent.offsetX, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = isPrivateAurasEnabled,
		},
		{
			name = "Anchor offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "privateAurasParentOffsetY",
			parentId = "privateAuras",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.privateAuras or {}
				local parentCfg = pcfg.parent or {}
				local defParent = defPrivateAuras.parent or {}
				return parentCfg.offsetY or defParent.offsetY or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = ensurePrivateAuraConfig(cfg)
				if not pcfg then return end
				pcfg.parent.offsetY = clampNumber(value, -200, 200, pcfg.parent.offsetY or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "privateAurasParentOffsetY", pcfg.parent.offsetY, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = isPrivateAurasEnabled,
		},
		{
			name = "Show countdown frame",
			kind = SettingType.Checkbox,
			field = "privateAurasCountdownFrame",
			parentId = "privateAuras",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.privateAuras or {}
				local defValue = defPrivateAuras.countdownFrame ~= false
				if pcfg.countdownFrame == nil then return defValue end
				return pcfg.countdownFrame ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = ensurePrivateAuraConfig(cfg)
				if not pcfg then return end
				pcfg.countdownFrame = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "privateAurasCountdownFrame", pcfg.countdownFrame, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = isPrivateAurasEnabled,
		},
		{
			name = "Show countdown numbers",
			kind = SettingType.Checkbox,
			field = "privateAurasCountdownNumbers",
			parentId = "privateAuras",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.privateAuras or {}
				local defValue = defPrivateAuras.countdownNumbers ~= false
				if pcfg.countdownNumbers == nil then return defValue end
				return pcfg.countdownNumbers ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = ensurePrivateAuraConfig(cfg)
				if not pcfg then return end
				pcfg.countdownNumbers = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "privateAurasCountdownNumbers", pcfg.countdownNumbers, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = isPrivateAurasEnabled,
		},
		{
			name = "Show dispel type",
			kind = SettingType.Checkbox,
			field = "privateAurasShowDispelType",
			parentId = "privateAuras",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.privateAuras or {}
				local defValue = defPrivateAuras.showDispelType == true
				if pcfg.showDispelType == nil then return defValue end
				return pcfg.showDispelType == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = ensurePrivateAuraConfig(cfg)
				if not pcfg then return end
				pcfg.showDispelType = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "privateAurasShowDispelType", pcfg.showDispelType, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = isPrivateAurasEnabled,
		},
		{
			name = "Show duration",
			kind = SettingType.Checkbox,
			field = "privateAurasDurationEnabled",
			parentId = "privateAuras",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.privateAuras or {}
				local durationCfg = pcfg.duration or {}
				local defDuration = defPrivateAuras.duration or {}
				if durationCfg.enable == nil then return defDuration.enable == true end
				return durationCfg.enable == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = ensurePrivateAuraConfig(cfg)
				if not pcfg then return end
				pcfg.duration.enable = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "privateAurasDurationEnabled", pcfg.duration.enable, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = isPrivateAurasEnabled,
		},
		{
			name = "Duration anchor",
			kind = SettingType.Dropdown,
			field = "privateAurasDurationPoint",
			parentId = "privateAuras",
			values = auraAnchorOptions,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.privateAuras or {}
				local durationCfg = pcfg.duration or {}
				local defDuration = defPrivateAuras.duration or {}
				return durationCfg.point or defDuration.point or "BOTTOM"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = ensurePrivateAuraConfig(cfg)
				if not pcfg then return end
				pcfg.duration.point = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "privateAurasDurationPoint", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				return isPrivateAurasEnabled() and (getCfg(kind) and getCfg(kind).privateAuras and getCfg(kind).privateAuras.duration and getCfg(kind).privateAuras.duration.enable == true)
			end,
		},
		{
			name = "Duration offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "privateAurasDurationOffsetX",
			parentId = "privateAuras",
			minValue = -50,
			maxValue = 50,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.privateAuras or {}
				local durationCfg = pcfg.duration or {}
				local defDuration = defPrivateAuras.duration or {}
				return durationCfg.offsetX or defDuration.offsetX or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = ensurePrivateAuraConfig(cfg)
				if not pcfg then return end
				pcfg.duration.offsetX = clampNumber(value, -50, 50, pcfg.duration.offsetX or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "privateAurasDurationOffsetX", pcfg.duration.offsetX, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				return isPrivateAurasEnabled() and (getCfg(kind) and getCfg(kind).privateAuras and getCfg(kind).privateAuras.duration and getCfg(kind).privateAuras.duration.enable == true)
			end,
		},
		{
			name = "Duration offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "privateAurasDurationOffsetY",
			parentId = "privateAuras",
			minValue = -50,
			maxValue = 50,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.privateAuras or {}
				local durationCfg = pcfg.duration or {}
				local defDuration = defPrivateAuras.duration or {}
				return durationCfg.offsetY or defDuration.offsetY or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = ensurePrivateAuraConfig(cfg)
				if not pcfg then return end
				pcfg.duration.offsetY = clampNumber(value, -50, 50, pcfg.duration.offsetY or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "privateAurasDurationOffsetY", pcfg.duration.offsetY, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				return isPrivateAurasEnabled() and (getCfg(kind) and getCfg(kind).privateAuras and getCfg(kind).privateAuras.duration and getCfg(kind).privateAuras.duration.enable == true)
			end,
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
		settings[#settings + 1] = {
			name = "Sort method",
			kind = SettingType.Dropdown,
			field = "sortMethod",
			parentId = "party",
			default = (DEFAULTS.party and DEFAULTS.party.sortMethod) or "INDEX",
			customDefaultText = getSortMethodLabel(),
			get = function() return getSortMethodValue() end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg or not value then return end
				local v = tostring(value):upper()
				local custom = GFH.EnsureCustomSortConfig(cfg)
				if v == "CUSTOM" then
					custom.enabled = true
					cfg.sortMethod = "NAMELIST"
					if EditMode and EditMode.SetValue then
						EditMode:SetValue(editModeId, "sortMethod", "CUSTOM", nil, true)
						EditMode:SetValue(editModeId, "customSortEnabled", true, nil, true)
					end
				else
					custom.enabled = false
					cfg.sortMethod = v
					if EditMode and EditMode.SetValue then
						EditMode:SetValue(editModeId, "sortMethod", cfg.sortMethod, nil, true)
						EditMode:SetValue(editModeId, "customSortEnabled", false, nil, true)
					end
				end
				GF:ApplyHeaderAttributes(kind)
				GF:RefreshCustomSortNameList(kind)
				if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end
				if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RequestRefreshSettings then addon.EditModeLib.internal:RequestRefreshSettings() end
			end,
			generator = function(_, root, data)
				for _, option in ipairs(sortMethodOptions) do
					root:CreateRadio(option.label, function() return getSortMethodValue() == option.value end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						local v = tostring(option.value):upper()
						local custom = GFH.EnsureCustomSortConfig(cfg)
						if v == "CUSTOM" then
							custom.enabled = true
							cfg.sortMethod = "NAMELIST"
							if EditMode and EditMode.SetValue then
								EditMode:SetValue(editModeId, "sortMethod", "CUSTOM", nil, true)
								EditMode:SetValue(editModeId, "customSortEnabled", true, nil, true)
							end
						else
							custom.enabled = false
							cfg.sortMethod = v
							if EditMode and EditMode.SetValue then
								EditMode:SetValue(editModeId, "sortMethod", cfg.sortMethod, nil, true)
								EditMode:SetValue(editModeId, "customSortEnabled", false, nil, true)
							end
						end
						GF:ApplyHeaderAttributes(kind)
						GF:RefreshCustomSortNameList(kind)
						if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end
						data.customDefaultText = option.label
						if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RequestRefreshSettings then addon.EditModeLib.internal:RequestRefreshSettings() end
					end)
				end
			end,
		}
		settings[#settings + 1] = {
			name = "Sort direction",
			kind = SettingType.Dropdown,
			field = "sortDir",
			parentId = "party",
			default = (DEFAULTS.party and DEFAULTS.party.sortDir) or "ASC",
			customDefaultText = getSortDirLabel(),
			get = function() return getSortDirValue() end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg or not value then return end
				cfg.sortDir = tostring(value):upper()
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "sortDir", cfg.sortDir, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end
			end,
			generator = function(_, root, data)
				for _, option in ipairs(sortDirOptions) do
					root:CreateRadio(option.label, function() return getSortDirValue() == option.value end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.sortDir = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "sortDir", cfg.sortDir, nil, true) end
						GF:ApplyHeaderAttributes(kind)
						if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end
						data.customDefaultText = option.label
						if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RequestRefreshSettings then addon.EditModeLib.internal:RequestRefreshSettings() end
					end)
				end
			end,
		}
	elseif raidLikeKind then
		local raidSectionName = (kind == "mt" and "Main Tank") or (kind == "ma" and "Main Assist") or (RAID or "Raid")
		settings[#settings + 1] = {
			name = raidSectionName,
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
			default = (DEFAULTS[kind] and DEFAULTS[kind].unitsPerColumn) or (DEFAULTS.raid and DEFAULTS.raid.unitsPerColumn) or 5,
			parentId = "raid",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.unitsPerColumn or (DEFAULTS[kind] and DEFAULTS[kind].unitsPerColumn) or (DEFAULTS.raid and DEFAULTS.raid.unitsPerColumn) or 5
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
			default = (DEFAULTS[kind] and DEFAULTS[kind].maxColumns) or (DEFAULTS.raid and DEFAULTS.raid.maxColumns) or 8,
			parentId = "raid",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.maxColumns or (DEFAULTS[kind] and DEFAULTS[kind].maxColumns) or (DEFAULTS.raid and DEFAULTS.raid.maxColumns) or 8
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
			default = (DEFAULTS[kind] and DEFAULTS[kind].columnSpacing) or (DEFAULTS.raid and DEFAULTS.raid.columnSpacing) or 0,
			parentId = "raid",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.columnSpacing or (DEFAULTS[kind] and DEFAULTS[kind].columnSpacing) or (DEFAULTS.raid and DEFAULTS.raid.columnSpacing) or 0
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
		settings[#settings + 1] = {
			name = "Group by",
			kind = SettingType.Dropdown,
			field = "groupBy",
			parentId = "raid",
			default = (DEFAULTS.raid and DEFAULTS.raid.groupBy) or "GROUP",
			customDefaultText = getGroupByLabel(),
			get = function() return getGroupByValue() end,
			set = function(_, value)
				if not value then return end
				applyGroupByPreset(value)
			end,
			isShown = function() return raidKind end,
			isEnabled = function() return not isCustomSortEditorOpen() end,
			generator = function(_, root, data)
				for _, option in ipairs(sortGroupOptions) do
					root:CreateRadio(option.label, function() return getGroupByValue() == option.value end, function()
						applyGroupByPreset(option.value)
						data.customDefaultText = option.label
						if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RequestRefreshSettings then addon.EditModeLib.internal:RequestRefreshSettings() end
					end)
				end
			end,
		}
		settings[#settings + 1] = {
			name = "Sort method",
			kind = SettingType.Dropdown,
			field = "sortMethod",
			parentId = "raid",
			default = (DEFAULTS.raid and DEFAULTS.raid.sortMethod) or "INDEX",
			customDefaultText = getSortMethodLabel(),
			get = function() return getSortMethodValue() end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg or not value then return end
				local v = tostring(value):upper()
				local custom = GFH.EnsureCustomSortConfig(cfg)
				if v == "CUSTOM" then
					custom.enabled = true
					cfg.sortMethod = "NAMELIST"
					if EditMode and EditMode.SetValue then
						EditMode:SetValue(editModeId, "sortMethod", "CUSTOM", nil, true)
						EditMode:SetValue(editModeId, "customSortEnabled", true, nil, true)
					end
				else
					custom.enabled = false
					cfg.sortMethod = v
					if EditMode and EditMode.SetValue then
						EditMode:SetValue(editModeId, "sortMethod", cfg.sortMethod, nil, true)
						EditMode:SetValue(editModeId, "customSortEnabled", false, nil, true)
					end
					if GF._customSortEditor and GF._customSortEditor.IsShown and GF._customSortEditor:IsShown() then GF._customSortEditor:Hide() end
				end
				GF:ApplyHeaderAttributes(kind)
				if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end
				if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RequestRefreshSettings then addon.EditModeLib.internal:RequestRefreshSettings() end
			end,
			isShown = function() return raidKind end,
			generator = function(_, root, data)
				for _, option in ipairs(sortMethodOptions) do
					root:CreateRadio(option.label, function() return getSortMethodValue() == option.value end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						local v = tostring(option.value):upper()
						local custom = GFH.EnsureCustomSortConfig(cfg)
						if v == "CUSTOM" then
							custom.enabled = true
							cfg.sortMethod = "NAMELIST"
							if EditMode and EditMode.SetValue then
								EditMode:SetValue(editModeId, "sortMethod", "CUSTOM", nil, true)
								EditMode:SetValue(editModeId, "customSortEnabled", true, nil, true)
							end
						else
							custom.enabled = false
							cfg.sortMethod = v
							if EditMode and EditMode.SetValue then
								EditMode:SetValue(editModeId, "sortMethod", cfg.sortMethod, nil, true)
								EditMode:SetValue(editModeId, "customSortEnabled", false, nil, true)
							end
							if GF._customSortEditor and GF._customSortEditor.IsShown and GF._customSortEditor:IsShown() then GF._customSortEditor:Hide() end
						end
						GF:ApplyHeaderAttributes(kind)
						if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end
						data.customDefaultText = option.label
						if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RequestRefreshSettings then addon.EditModeLib.internal:RequestRefreshSettings() end
					end)
				end
			end,
		}
		settings[#settings + 1] = {
			name = "Sort direction",
			kind = SettingType.Dropdown,
			field = "sortDir",
			parentId = "raid",
			default = (DEFAULTS.raid and DEFAULTS.raid.sortDir) or "ASC",
			customDefaultText = getSortDirLabel(),
			get = function() return getSortDirValue() end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg or not value then return end
				cfg.sortDir = tostring(value):upper()
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "sortDir", cfg.sortDir, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isShown = function() return raidKind end,
			generator = function(_, root, data)
				for _, option in ipairs(sortDirOptions) do
					root:CreateRadio(option.label, function() return getSortDirValue() == option.value end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.sortDir = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "sortDir", cfg.sortDir, nil, true) end
						GF:ApplyHeaderAttributes(kind)
						data.customDefaultText = option.label
						if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RequestRefreshSettings then addon.EditModeLib.internal:RequestRefreshSettings() end
					end)
				end
			end,
		}
		settings[#settings + 1] = {
			name = "Separate Melee & Ranged DPS",
			kind = SettingType.Checkbox,
			field = "customSortSeparateMeleeRanged",
			parentId = "raid",
			default = false,
			get = function()
				local cfg = getCfg(kind)
				local custom = cfg and GFH.EnsureCustomSortConfig(cfg)
				return custom and custom.separateMeleeRanged == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local custom = GFH.EnsureCustomSortConfig(cfg)
				custom.separateMeleeRanged = value and true or false
				if custom.separateMeleeRanged then
					custom.roleOrder = GFH.ExpandRoleOrder(custom.roleOrder, true)
				else
					custom.roleOrder = GFH.CollapseRoleOrder(custom.roleOrder)
				end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "customSortSeparateMeleeRanged", custom.separateMeleeRanged, nil, true) end
				GF:ApplyHeaderAttributes(kind)
				GF:RefreshCustomSortNameList(kind)
				if GF._previewActive and GF._previewActive[kind] then GF:UpdatePreviewLayout(kind) end
				if GF._customSortEditor and GF._customSortEditor.Refresh then GF._customSortEditor:Refresh() end
			end,
			isShown = function() return raidKind end,
			isEnabled = function() return isCustomSortingEnabled() end,
		}
		settings[#settings + 1] = {
			name = "",
			kind = SettingType.Divider,
			parentId = "raid",
			isShown = function() return isGroupIndicatorShown() end,
		}
		settings[#settings + 1] = {
			name = "Show indicator",
			kind = SettingType.Checkbox,
			field = "groupIndicatorEnabled",
			parentId = "raid",
			get = function() return getGroupIndicatorEnabledValue() end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.groupIndicator = cfg.groupIndicator or {}
				cfg.groupIndicator.enabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupIndicatorEnabled", cfg.groupIndicator.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isShown = function() return isGroupIndicatorShown() end,
		}
		settings[#settings + 1] = {
			name = "Hide Group number per Frame",
			kind = SettingType.Checkbox,
			field = "groupIndicatorHidePerFrame",
			parentId = "raid",
			get = function()
				local cfg = getCfg(kind)
				local def = DEFAULTS[kind] or {}
				local gi = cfg and cfg.groupIndicator or {}
				local defGI = def.groupIndicator or {}
				if gi.hidePerFrame == nil then return defGI.hidePerFrame == true end
				return gi.hidePerFrame == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.groupIndicator = cfg.groupIndicator or {}
				cfg.groupIndicator.hidePerFrame = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupIndicatorHidePerFrame", cfg.groupIndicator.hidePerFrame, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isGroupIndicatorSettingsEnabled() end,
			isShown = function() return isGroupIndicatorShown() end,
		}
		settings[#settings + 1] = {
			name = "Format",
			kind = SettingType.Dropdown,
			field = "groupIndicatorFormat",
			parentId = "raid",
			customDefaultText = getGroupIndicatorFormatLabel(),
			get = function() return getGroupIndicatorFormatValue() end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.groupIndicator = cfg.groupIndicator or {}
				cfg.groupIndicator.format = normalizeGroupNumberFormat(value) or "GROUP"
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupIndicatorFormat", cfg.groupIndicator.format, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root, data)
				for _, option in ipairs(groupNumberFormatOptions) do
					local value = option and option.value
					if value ~= nil then
						local label = option.label or option.text or tostring(value)
						root:CreateRadio(label, function() return getGroupIndicatorFormatValue() == value end, function()
							local cfg = getCfg(kind)
							if not cfg then return end
							cfg.groupIndicator = cfg.groupIndicator or {}
							cfg.groupIndicator.format = value
							if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupIndicatorFormat", value, nil, true) end
							data.customDefaultText = label
							if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RequestRefreshSettings then addon.EditModeLib.internal:RequestRefreshSettings() end
							GF:ApplyHeaderAttributes(kind)
						end)
					end
				end
			end,
			isEnabled = function() return isGroupIndicatorSettingsEnabled() end,
			isShown = function() return isGroupIndicatorShown() end,
		}
		settings[#settings + 1] = {
			name = "Color",
			kind = SettingType.Color,
			field = "groupIndicatorColor",
			parentId = "raid",
			hasOpacity = true,
			default = (DEFAULTS[kind] and DEFAULTS[kind].groupIndicator and DEFAULTS[kind].groupIndicator.color) or { 1, 1, 1, 1 },
			get = function()
				local cfg = getCfg(kind)
				local def = DEFAULTS[kind] or {}
				local style = resolveGroupIndicatorStyle(cfg, def, (cfg and cfg.health) or {})
				local r, g, b, a = unpackColor(style.color, GFH.COLOR_WHITE)
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.groupIndicator = cfg.groupIndicator or {}
				cfg.groupIndicator.color = { value.r or 1, value.g or 1, value.b or 1, value.a or 1 }
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupIndicatorColor", cfg.groupIndicator.color, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isGroupIndicatorSettingsEnabled() end,
			isShown = function() return isGroupIndicatorShown() end,
		}
		settings[#settings + 1] = {
			name = "Font size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "groupIndicatorFontSize",
			parentId = "raid",
			minValue = 8,
			maxValue = 100,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local def = DEFAULTS[kind] or {}
				local style = resolveGroupIndicatorStyle(cfg, def, (cfg and cfg.health) or {})
				return style.fontSize or 12
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.groupIndicator = cfg.groupIndicator or {}
				cfg.groupIndicator.fontSize = clampNumber(value, 8, 100, cfg.groupIndicator.fontSize or 12)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupIndicatorFontSize", cfg.groupIndicator.fontSize, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isGroupIndicatorSettingsEnabled() end,
			isShown = function() return isGroupIndicatorShown() end,
		}
		settings[#settings + 1] = {
			name = "Font",
			kind = SettingType.Dropdown,
			field = "groupIndicatorFont",
			height = FONT_DROPDOWN_SCROLL_HEIGHT,
			parentId = "raid",
			get = function()
				local cfg = getCfg(kind)
				local def = DEFAULTS[kind] or {}
				local style = resolveGroupIndicatorStyle(cfg, def, (cfg and cfg.health) or {})
				return style.font or nil
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.groupIndicator = cfg.groupIndicator or {}
				cfg.groupIndicator.font = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupIndicatorFont", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(fontOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local def = DEFAULTS[kind] or {}
						local style = resolveGroupIndicatorStyle(cfg, def, (cfg and cfg.health) or {})
						return (style.font or nil) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.groupIndicator = cfg.groupIndicator or {}
						cfg.groupIndicator.font = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupIndicatorFont", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function() return isGroupIndicatorSettingsEnabled() end,
			isShown = function() return isGroupIndicatorShown() end,
		}
		settings[#settings + 1] = {
			name = "Font outline",
			kind = SettingType.Dropdown,
			field = "groupIndicatorFontOutline",
			parentId = "raid",
			get = function()
				local cfg = getCfg(kind)
				local def = DEFAULTS[kind] or {}
				local style = resolveGroupIndicatorStyle(cfg, def, (cfg and cfg.health) or {})
				return style.fontOutline or "OUTLINE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.groupIndicator = cfg.groupIndicator or {}
				cfg.groupIndicator.fontOutline = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupIndicatorFontOutline", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(outlineOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local def = DEFAULTS[kind] or {}
						local style = resolveGroupIndicatorStyle(cfg, def, (cfg and cfg.health) or {})
						return (style.fontOutline or "OUTLINE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.groupIndicator = cfg.groupIndicator or {}
						cfg.groupIndicator.fontOutline = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupIndicatorFontOutline", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function() return isGroupIndicatorSettingsEnabled() end,
			isShown = function() return isGroupIndicatorShown() end,
		}
		settings[#settings + 1] = {
			name = "Anchor",
			kind = SettingType.Dropdown,
			field = "groupIndicatorAnchor",
			parentId = "raid",
			values = anchorOptions9,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local def = DEFAULTS[kind] or {}
				local style = resolveGroupIndicatorStyle(cfg, def, (cfg and cfg.health) or {})
				return style.anchor or "TOPLEFT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.groupIndicator = cfg.groupIndicator or {}
				cfg.groupIndicator.anchor = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupIndicatorAnchor", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isGroupIndicatorSettingsEnabled() end,
			isShown = function() return isGroupIndicatorShown() end,
		}
		settings[#settings + 1] = {
			name = "Offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "groupIndicatorOffsetX",
			parentId = "raid",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local def = DEFAULTS[kind] or {}
				local style = resolveGroupIndicatorStyle(cfg, def, (cfg and cfg.health) or {})
				local off = style.offset or {}
				return off.x or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.groupIndicator = cfg.groupIndicator or {}
				cfg.groupIndicator.offset = cfg.groupIndicator.offset or {}
				cfg.groupIndicator.offset.x = clampNumber(value, -200, 200, (cfg.groupIndicator.offset and cfg.groupIndicator.offset.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupIndicatorOffsetX", cfg.groupIndicator.offset.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isGroupIndicatorSettingsEnabled() end,
			isShown = function() return isGroupIndicatorShown() end,
		}
		settings[#settings + 1] = {
			name = "Offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "groupIndicatorOffsetY",
			parentId = "raid",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local def = DEFAULTS[kind] or {}
				local style = resolveGroupIndicatorStyle(cfg, def, (cfg and cfg.health) or {})
				local off = style.offset or {}
				return off.y or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.groupIndicator = cfg.groupIndicator or {}
				cfg.groupIndicator.offset = cfg.groupIndicator.offset or {}
				cfg.groupIndicator.offset.y = clampNumber(value, -200, 200, (cfg.groupIndicator.offset and cfg.groupIndicator.offset.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "groupIndicatorOffsetY", cfg.groupIndicator.offset.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function() return isGroupIndicatorSettingsEnabled() end,
			isShown = function() return isGroupIndicatorShown() end,
		}
	end

	if kind == "party" or raidLikeKind then
		local raidMarkerIndex
		for i, setting in ipairs(settings) do
			if setting and setting.id == "raidmarker" then
				raidMarkerIndex = i
				break
			end
		end
		GF:AppendStatusIconSettings(settings, kind, editModeId, raidMarkerIndex)
	end

	return settings
end

local function applyEditModeData(kind, data)
	if not data then return end
	local cfg = getCfg(kind)
	if not cfg then return end

	local positionChanged = false
	if data.point or data.relativePoint or data.x ~= nil or data.y ~= nil then
		cfg.point = tostring(data.point or cfg.point or "CENTER"):upper()
		cfg.relativePoint = tostring(data.relativePoint or cfg.point):upper()
		if not cfg.relativeTo or cfg.relativeTo == "" then cfg.relativeTo = "UIParent" end
		cfg.x = roundToPixel(clampNumber((data.x ~= nil and data.x or cfg.x) or 0, -4000, 4000, cfg.x or 0), 1)
		cfg.y = roundToPixel(clampNumber((data.y ~= nil and data.y or cfg.y) or 0, -4000, 4000, cfg.y or 0), 1)
		if data.point ~= cfg.point then
			data.point = cfg.point
			positionChanged = true
			if EditMode and EditMode.SetValue then EditMode:SetValue(EDITMODE_IDS[kind], "point", cfg.point, nil, true) end
		end
		if data.relativePoint ~= cfg.relativePoint then
			data.relativePoint = cfg.relativePoint
			positionChanged = true
			if EditMode and EditMode.SetValue then EditMode:SetValue(EDITMODE_IDS[kind], "relativePoint", cfg.relativePoint, nil, true) end
		end
		if data.x ~= cfg.x then
			data.x = cfg.x
			positionChanged = true
			if EditMode and EditMode.SetValue then EditMode:SetValue(EDITMODE_IDS[kind], "x", cfg.x, nil, true) end
		end
		if data.y ~= cfg.y then
			data.y = cfg.y
			positionChanged = true
			if EditMode and EditMode.SetValue then EditMode:SetValue(EDITMODE_IDS[kind], "y", cfg.y, nil, true) end
		end
	end

	local refreshAuras = false
	if data.width ~= nil then cfg.width = clampNumber(data.width, 40, 600, cfg.width or 100) end
	if data.height ~= nil then cfg.height = clampNumber(data.height, 10, 200, cfg.height or 24) end
	if data.powerHeight ~= nil then cfg.powerHeight = clampNumber(data.powerHeight, 0, 50, cfg.powerHeight or 6) end
	if data.tooltipMode ~= nil or data.tooltipModifier ~= nil then cfg.tooltip = cfg.tooltip or {} end
	if data.tooltipMode ~= nil then cfg.tooltip.mode = tostring(data.tooltipMode):upper() end
	if data.tooltipModifier ~= nil then cfg.tooltip.modifier = tostring(data.tooltipModifier):upper() end
	if data.hideInClientScene ~= nil then cfg.hideInClientScene = data.hideInClientScene and true or false end
	if data.tooltipAuras ~= nil then
		local ac = ensureAuraConfig(cfg)
		local enabled = data.tooltipAuras and true or false
		ac.buff.showTooltip = enabled
		ac.debuff.showTooltip = enabled
		ac.externals.showTooltip = enabled
		refreshAuras = true
	end
	if data.spacing ~= nil then cfg.spacing = clampNumber(data.spacing, 0, 40, cfg.spacing or 0) end
	if data.growth then
		cfg.growth = (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(data.growth, (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(cfg.growth, "DOWN")) or "DOWN"))
			or "DOWN"
	end
	if kind == "raid" and data.groupGrowth then
		local growth = (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(cfg.growth, "DOWN")) or "DOWN"
		local defaultGroupGrowth = DEFAULTS and DEFAULTS.raid and DEFAULTS.raid.groupGrowth
		if GFH.ResolveGroupGrowthDirection then
			cfg.groupGrowth = GFH.ResolveGroupGrowthDirection(data.groupGrowth, growth, defaultGroupGrowth)
		else
			cfg.groupGrowth = (GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(data.groupGrowth, nil)) or ((growth == "RIGHT" or growth == "LEFT") and "DOWN" or "RIGHT")
		end
	end
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
	if data.nameNoEllipsis ~= nil then
		cfg.text = cfg.text or {}
		cfg.text.nameNoEllipsis = data.nameNoEllipsis and true or false
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
		or data.statusTextEnabled ~= nil
		or data.statusTextColor ~= nil
		or data.statusTextFontSize ~= nil
		or data.statusTextFont ~= nil
		or data.statusTextFontOutline ~= nil
		or data.statusTextAnchor ~= nil
		or data.statusTextOffsetX ~= nil
		or data.statusTextOffsetY ~= nil
		or data.statusTextShowGroup ~= nil
		or data.statusTextGroupFormat ~= nil
		or data.groupNumberColor ~= nil
		or data.groupNumberFontSize ~= nil
		or data.groupNumberFont ~= nil
		or data.groupNumberFontOutline ~= nil
		or data.groupNumberAnchor ~= nil
		or data.groupNumberOffsetX ~= nil
		or data.groupNumberOffsetY ~= nil
		or data.dispelTintEnabled ~= nil
		or data.dispelTintAlpha ~= nil
		or data.dispelTintFillEnabled ~= nil
		or data.dispelTintFillAlpha ~= nil
		or data.dispelTintFillColor ~= nil
		or data.dispelTintSample ~= nil
		or data.dispelTintGlowEnabled ~= nil
		or data.dispelTintGlowColorMode ~= nil
		or data.dispelTintGlowColor ~= nil
		or data.dispelTintGlowEffect ~= nil
		or data.dispelTintGlowFrequency ~= nil
		or data.dispelTintGlowX ~= nil
		or data.dispelTintGlowY ~= nil
		or data.dispelTintGlowLines ~= nil
		or data.dispelTintGlowThickness ~= nil
	then
		cfg.status = cfg.status or {}
	end
	if data.nameColorMode ~= nil and data.nameClassColor == nil then
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
	if
		data.statusTextEnabled ~= nil
		or data.statusTextColor ~= nil
		or data.statusTextFontSize ~= nil
		or data.statusTextFont ~= nil
		or data.statusTextFontOutline ~= nil
		or data.statusTextAnchor ~= nil
		or data.statusTextOffsetX ~= nil
		or data.statusTextOffsetY ~= nil
		or data.statusTextShowOffline ~= nil
		or data.statusTextShowAFK ~= nil
		or data.statusTextShowDND ~= nil
		or data.statusTextShowGroup ~= nil
		or data.statusTextGroupFormat ~= nil
		or data.statusTextHideHealthTextOffline ~= nil
	then
		cfg.status.unitStatus = cfg.status.unitStatus or {}
		if data.statusTextEnabled ~= nil then cfg.status.unitStatus.enabled = data.statusTextEnabled and true or false end
		if data.statusTextColor ~= nil then cfg.status.unitStatus.color = data.statusTextColor end
		if data.statusTextFontSize ~= nil then cfg.status.unitStatus.fontSize = data.statusTextFontSize end
		if data.statusTextFont ~= nil then cfg.status.unitStatus.font = data.statusTextFont end
		if data.statusTextFontOutline ~= nil then cfg.status.unitStatus.fontOutline = data.statusTextFontOutline end
		if data.statusTextAnchor ~= nil then cfg.status.unitStatus.anchor = data.statusTextAnchor end
		if data.statusTextOffsetX ~= nil or data.statusTextOffsetY ~= nil then
			cfg.status.unitStatus.offset = cfg.status.unitStatus.offset or {}
			if data.statusTextOffsetX ~= nil then cfg.status.unitStatus.offset.x = data.statusTextOffsetX end
			if data.statusTextOffsetY ~= nil then cfg.status.unitStatus.offset.y = data.statusTextOffsetY end
		end
		if data.statusTextShowOffline ~= nil then cfg.status.unitStatus.showOffline = data.statusTextShowOffline and true or false end
		if data.statusTextShowAFK ~= nil then cfg.status.unitStatus.showAFK = data.statusTextShowAFK and true or false end
		if data.statusTextShowDND ~= nil then cfg.status.unitStatus.showDND = data.statusTextShowDND and true or false end
		if data.statusTextShowGroup ~= nil then cfg.status.unitStatus.showGroup = data.statusTextShowGroup and true or false end
		if data.statusTextGroupFormat ~= nil then cfg.status.unitStatus.groupFormat = data.statusTextGroupFormat end
		if data.statusTextHideHealthTextOffline ~= nil then cfg.status.unitStatus.hideHealthTextWhenOffline = data.statusTextHideHealthTextOffline and true or false end
	end
	if
		data.statusTextShowGroup ~= nil
		or data.statusTextGroupFormat ~= nil
		or data.groupNumberColor ~= nil
		or data.groupNumberFontSize ~= nil
		or data.groupNumberFont ~= nil
		or data.groupNumberFontOutline ~= nil
		or data.groupNumberAnchor ~= nil
		or data.groupNumberOffsetX ~= nil
		or data.groupNumberOffsetY ~= nil
	then
		cfg.status.groupNumber = cfg.status.groupNumber or {}
		if data.statusTextShowGroup ~= nil then cfg.status.groupNumber.enabled = data.statusTextShowGroup and true or false end
		if data.statusTextGroupFormat ~= nil then cfg.status.groupNumber.format = normalizeGroupNumberFormat(data.statusTextGroupFormat) or "GROUP" end
		if data.groupNumberColor ~= nil then cfg.status.groupNumber.color = data.groupNumberColor end
		if data.groupNumberFontSize ~= nil then cfg.status.groupNumber.fontSize = data.groupNumberFontSize end
		if data.groupNumberFont ~= nil then cfg.status.groupNumber.font = data.groupNumberFont end
		if data.groupNumberFontOutline ~= nil then cfg.status.groupNumber.fontOutline = data.groupNumberFontOutline end
		if data.groupNumberAnchor ~= nil then cfg.status.groupNumber.anchor = data.groupNumberAnchor end
		if data.groupNumberOffsetX ~= nil or data.groupNumberOffsetY ~= nil then
			cfg.status.groupNumber.offset = cfg.status.groupNumber.offset or {}
			if data.groupNumberOffsetX ~= nil then cfg.status.groupNumber.offset.x = data.groupNumberOffsetX end
			if data.groupNumberOffsetY ~= nil then cfg.status.groupNumber.offset.y = data.groupNumberOffsetY end
		end
	end
	if
		data.groupIndicatorEnabled ~= nil
		or data.groupIndicatorHidePerFrame ~= nil
		or data.groupIndicatorFormat ~= nil
		or data.groupIndicatorColor ~= nil
		or data.groupIndicatorFontSize ~= nil
		or data.groupIndicatorFont ~= nil
		or data.groupIndicatorFontOutline ~= nil
		or data.groupIndicatorAnchor ~= nil
		or data.groupIndicatorOffsetX ~= nil
		or data.groupIndicatorOffsetY ~= nil
	then
		cfg.groupIndicator = cfg.groupIndicator or {}
		if data.groupIndicatorEnabled ~= nil then cfg.groupIndicator.enabled = data.groupIndicatorEnabled and true or false end
		if data.groupIndicatorHidePerFrame ~= nil then cfg.groupIndicator.hidePerFrame = data.groupIndicatorHidePerFrame and true or false end
		if data.groupIndicatorFormat ~= nil then cfg.groupIndicator.format = normalizeGroupNumberFormat(data.groupIndicatorFormat) or "GROUP" end
		if data.groupIndicatorColor ~= nil then cfg.groupIndicator.color = data.groupIndicatorColor end
		if data.groupIndicatorFontSize ~= nil then cfg.groupIndicator.fontSize = data.groupIndicatorFontSize end
		if data.groupIndicatorFont ~= nil then cfg.groupIndicator.font = data.groupIndicatorFont end
		if data.groupIndicatorFontOutline ~= nil then cfg.groupIndicator.fontOutline = data.groupIndicatorFontOutline end
		if data.groupIndicatorAnchor ~= nil then cfg.groupIndicator.anchor = data.groupIndicatorAnchor end
		if data.groupIndicatorOffsetX ~= nil or data.groupIndicatorOffsetY ~= nil then
			cfg.groupIndicator.offset = cfg.groupIndicator.offset or {}
			if data.groupIndicatorOffsetX ~= nil then cfg.groupIndicator.offset.x = data.groupIndicatorOffsetX end
			if data.groupIndicatorOffsetY ~= nil then cfg.groupIndicator.offset.y = data.groupIndicatorOffsetY end
		end
	end
	if
		data.dispelTintEnabled ~= nil
		or data.dispelTintAlpha ~= nil
		or data.dispelTintFillEnabled ~= nil
		or data.dispelTintFillAlpha ~= nil
		or data.dispelTintFillColor ~= nil
		or data.dispelTintSample ~= nil
		or data.dispelTintGlowEnabled ~= nil
		or data.dispelTintGlowColorMode ~= nil
		or data.dispelTintGlowColor ~= nil
		or data.dispelTintGlowEffect ~= nil
		or data.dispelTintGlowFrequency ~= nil
		or data.dispelTintGlowX ~= nil
		or data.dispelTintGlowY ~= nil
		or data.dispelTintGlowLines ~= nil
		or data.dispelTintGlowThickness ~= nil
	then
		cfg.status.dispelTint = cfg.status.dispelTint or {}
		if data.dispelTintEnabled ~= nil then cfg.status.dispelTint.enabled = data.dispelTintEnabled and true or false end
		if data.dispelTintAlpha ~= nil then cfg.status.dispelTint.alpha = clampNumber(data.dispelTintAlpha, 0, 1, cfg.status.dispelTint.alpha or 0.25) end
		if data.dispelTintFillEnabled ~= nil then cfg.status.dispelTint.fillEnabled = data.dispelTintFillEnabled and true or false end
		if data.dispelTintFillAlpha ~= nil then cfg.status.dispelTint.fillAlpha = clampNumber(data.dispelTintFillAlpha, 0, 1, cfg.status.dispelTint.fillAlpha or 0.2) end
		if data.dispelTintFillColor ~= nil then cfg.status.dispelTint.fillColor = data.dispelTintFillColor end
		if data.dispelTintSample ~= nil then cfg.status.dispelTint.showSample = data.dispelTintSample and true or false end
		if data.dispelTintGlowEnabled ~= nil then cfg.status.dispelTint.glowEnabled = data.dispelTintGlowEnabled and true or false end
		if data.dispelTintGlowColorMode ~= nil then cfg.status.dispelTint.glowColorMode = data.dispelTintGlowColorMode end
		if data.dispelTintGlowColor ~= nil then cfg.status.dispelTint.glowColor = data.dispelTintGlowColor end
		if data.dispelTintGlowEffect ~= nil then cfg.status.dispelTint.glowEffect = data.dispelTintGlowEffect end
		if data.dispelTintGlowFrequency ~= nil then cfg.status.dispelTint.glowFrequency = clampNumber(data.dispelTintGlowFrequency, -1.5, 1.5, cfg.status.dispelTint.glowFrequency or 0.25) end
		if data.dispelTintGlowX ~= nil then cfg.status.dispelTint.glowX = clampNumber(data.dispelTintGlowX, -10, 10, cfg.status.dispelTint.glowX or 0) end
		if data.dispelTintGlowY ~= nil then cfg.status.dispelTint.glowY = clampNumber(data.dispelTintGlowY, -10, 10, cfg.status.dispelTint.glowY or 0) end
		if data.dispelTintGlowLines ~= nil then cfg.status.dispelTint.glowLines = clampNumber(data.dispelTintGlowLines, 1, 20, cfg.status.dispelTint.glowLines or 8) end
		if data.dispelTintGlowThickness ~= nil then cfg.status.dispelTint.glowThickness = clampNumber(data.dispelTintGlowThickness, 1, 10, cfg.status.dispelTint.glowThickness or 3) end
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
	for _, meta in ipairs(GFH.STATUS_ICON_EDITMODE_META or EMPTY) do
		local iconKey = meta and meta.key
		if iconKey then
			local enabled = data[iconKey .. "Enabled"]
			local sample = data[iconKey .. "Sample"]
			local size = data[iconKey .. "Size"]
			local point = data[iconKey .. "Point"]
			local relativePoint = data[iconKey .. "RelativePoint"]
			local offsetX = data[iconKey .. "OffsetX"]
			local offsetY = data[iconKey .. "OffsetY"]
			if enabled ~= nil or sample ~= nil or size ~= nil or point ~= nil or relativePoint ~= nil or offsetX ~= nil or offsetY ~= nil then
				cfg.status[iconKey] = cfg.status[iconKey] or {}
				local iconCfg = cfg.status[iconKey]
				local defIconCfg = DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status[iconKey] or EMPTY
				local defaultSize = defIconCfg.size or 16
				if enabled ~= nil then iconCfg.enabled = enabled and true or false end
				if sample ~= nil then iconCfg.sample = sample and true or false end
				if size ~= nil then iconCfg.size = clampNumber(size, 8, 40, iconCfg.size or defaultSize) end
				if point ~= nil then
					iconCfg.point = point
					if relativePoint == nil then iconCfg.relativePoint = point end
				end
				if relativePoint ~= nil then iconCfg.relativePoint = relativePoint end
				if offsetX ~= nil then iconCfg.x = clampNumber(offsetX, -200, 200, iconCfg.x or 0) end
				if offsetY ~= nil then iconCfg.y = clampNumber(offsetY, -200, 200, iconCfg.y or 0) end
			end
		end
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
	if data.buffCooldownTextEnabled ~= nil then ac.buff.showCooldownText = data.buffCooldownTextEnabled and true or false end
	if data.buffCooldownTextAnchor ~= nil then ac.buff.cooldownAnchor = data.buffCooldownTextAnchor end
	if data.buffCooldownTextOffsetX ~= nil or data.buffCooldownTextOffsetY ~= nil then
		ac.buff.cooldownOffset = ac.buff.cooldownOffset or {}
		if data.buffCooldownTextOffsetX ~= nil then ac.buff.cooldownOffset.x = data.buffCooldownTextOffsetX end
		if data.buffCooldownTextOffsetY ~= nil then ac.buff.cooldownOffset.y = data.buffCooldownTextOffsetY end
	end
	if data.buffCooldownTextSize ~= nil then ac.buff.cooldownFontSize = data.buffCooldownTextSize end
	if data.buffCooldownTextFont ~= nil then ac.buff.cooldownFont = data.buffCooldownTextFont end
	if data.buffCooldownTextOutline ~= nil then ac.buff.cooldownFontOutline = data.buffCooldownTextOutline end
	if data.buffStackTextEnabled ~= nil then ac.buff.showStacks = data.buffStackTextEnabled and true or false end
	if data.buffStackAnchor ~= nil then ac.buff.countAnchor = data.buffStackAnchor end
	if data.buffStackOffsetX ~= nil or data.buffStackOffsetY ~= nil then
		ac.buff.countOffset = ac.buff.countOffset or {}
		if data.buffStackOffsetX ~= nil then ac.buff.countOffset.x = data.buffStackOffsetX end
		if data.buffStackOffsetY ~= nil then ac.buff.countOffset.y = data.buffStackOffsetY end
	end
	if data.buffStackSize ~= nil then ac.buff.countFontSize = data.buffStackSize end
	if data.buffStackFont ~= nil then ac.buff.countFont = data.buffStackFont end
	if data.buffStackOutline ~= nil then ac.buff.countFontOutline = data.buffStackOutline end

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
	if data.debuffShowDispelIcon ~= nil then ac.debuff.showDispelIcon = data.debuffShowDispelIcon and true or false end
	if data.debuffCooldownTextEnabled ~= nil then ac.debuff.showCooldownText = data.debuffCooldownTextEnabled and true or false end
	if data.debuffCooldownTextAnchor ~= nil then ac.debuff.cooldownAnchor = data.debuffCooldownTextAnchor end
	if data.debuffCooldownTextOffsetX ~= nil or data.debuffCooldownTextOffsetY ~= nil then
		ac.debuff.cooldownOffset = ac.debuff.cooldownOffset or {}
		if data.debuffCooldownTextOffsetX ~= nil then ac.debuff.cooldownOffset.x = data.debuffCooldownTextOffsetX end
		if data.debuffCooldownTextOffsetY ~= nil then ac.debuff.cooldownOffset.y = data.debuffCooldownTextOffsetY end
	end
	if data.debuffCooldownTextSize ~= nil then ac.debuff.cooldownFontSize = data.debuffCooldownTextSize end
	if data.debuffCooldownTextFont ~= nil then ac.debuff.cooldownFont = data.debuffCooldownTextFont end
	if data.debuffCooldownTextOutline ~= nil then ac.debuff.cooldownFontOutline = data.debuffCooldownTextOutline end
	if data.debuffStackTextEnabled ~= nil then ac.debuff.showStacks = data.debuffStackTextEnabled and true or false end
	if data.debuffStackAnchor ~= nil then ac.debuff.countAnchor = data.debuffStackAnchor end
	if data.debuffStackOffsetX ~= nil or data.debuffStackOffsetY ~= nil then
		ac.debuff.countOffset = ac.debuff.countOffset or {}
		if data.debuffStackOffsetX ~= nil then ac.debuff.countOffset.x = data.debuffStackOffsetX end
		if data.debuffStackOffsetY ~= nil then ac.debuff.countOffset.y = data.debuffStackOffsetY end
	end
	if data.debuffStackSize ~= nil then ac.debuff.countFontSize = data.debuffStackSize end
	if data.debuffStackFont ~= nil then ac.debuff.countFont = data.debuffStackFont end
	if data.debuffStackOutline ~= nil then ac.debuff.countFontOutline = data.debuffStackOutline end

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
	if data.externalCooldownTextEnabled ~= nil then ac.externals.showCooldownText = data.externalCooldownTextEnabled and true or false end
	if data.externalCooldownTextAnchor ~= nil then ac.externals.cooldownAnchor = data.externalCooldownTextAnchor end
	if data.externalCooldownTextOffsetX ~= nil or data.externalCooldownTextOffsetY ~= nil then
		ac.externals.cooldownOffset = ac.externals.cooldownOffset or {}
		if data.externalCooldownTextOffsetX ~= nil then ac.externals.cooldownOffset.x = data.externalCooldownTextOffsetX end
		if data.externalCooldownTextOffsetY ~= nil then ac.externals.cooldownOffset.y = data.externalCooldownTextOffsetY end
	end
	if data.externalCooldownTextSize ~= nil then ac.externals.cooldownFontSize = data.externalCooldownTextSize end
	if data.externalCooldownTextFont ~= nil then ac.externals.cooldownFont = data.externalCooldownTextFont end
	if data.externalCooldownTextOutline ~= nil then ac.externals.cooldownFontOutline = data.externalCooldownTextOutline end
	if data.externalStackTextEnabled ~= nil then ac.externals.showStacks = data.externalStackTextEnabled and true or false end
	if data.externalStackAnchor ~= nil then ac.externals.countAnchor = data.externalStackAnchor end
	if data.externalStackOffsetX ~= nil or data.externalStackOffsetY ~= nil then
		ac.externals.countOffset = ac.externals.countOffset or {}
		if data.externalStackOffsetX ~= nil then ac.externals.countOffset.x = data.externalStackOffsetX end
		if data.externalStackOffsetY ~= nil then ac.externals.countOffset.y = data.externalStackOffsetY end
	end
	if data.externalStackSize ~= nil then ac.externals.countFontSize = data.externalStackSize end
	if data.externalStackFont ~= nil then ac.externals.countFont = data.externalStackFont end
	if data.externalStackOutline ~= nil then ac.externals.countFontOutline = data.externalStackOutline end
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
	GFH.SyncAurasEnabled(cfg)
	if
		data.privateAurasEnabled ~= nil
		or data.privateAurasAmount ~= nil
		or data.privateAurasSize ~= nil
		or data.privateAurasPoint ~= nil
		or data.privateAurasOffset ~= nil
		or data.privateAurasParentPoint ~= nil
		or data.privateAurasParentOffsetX ~= nil
		or data.privateAurasParentOffsetY ~= nil
		or data.privateAurasCountdownFrame ~= nil
		or data.privateAurasCountdownNumbers ~= nil
		or data.privateAurasShowDispelType ~= nil
		or data.privateAurasDurationEnabled ~= nil
		or data.privateAurasDurationPoint ~= nil
		or data.privateAurasDurationOffsetX ~= nil
		or data.privateAurasDurationOffsetY ~= nil
	then
		cfg.privateAuras = cfg.privateAuras or {}
		cfg.privateAuras.icon = cfg.privateAuras.icon or {}
		cfg.privateAuras.parent = cfg.privateAuras.parent or {}
		cfg.privateAuras.duration = cfg.privateAuras.duration or {}
		if data.privateAurasEnabled ~= nil then cfg.privateAuras.enabled = data.privateAurasEnabled and true or false end
		if data.privateAurasAmount ~= nil then cfg.privateAuras.icon.amount = data.privateAurasAmount end
		if data.privateAurasSize ~= nil then cfg.privateAuras.icon.size = data.privateAurasSize end
		if data.privateAurasPoint ~= nil then cfg.privateAuras.icon.point = data.privateAurasPoint end
		if data.privateAurasOffset ~= nil then cfg.privateAuras.icon.offset = data.privateAurasOffset end
		if data.privateAurasParentPoint ~= nil then cfg.privateAuras.parent.point = data.privateAurasParentPoint end
		if data.privateAurasParentOffsetX ~= nil then cfg.privateAuras.parent.offsetX = data.privateAurasParentOffsetX end
		if data.privateAurasParentOffsetY ~= nil then cfg.privateAuras.parent.offsetY = data.privateAurasParentOffsetY end
		if data.privateAurasCountdownFrame ~= nil then cfg.privateAuras.countdownFrame = data.privateAurasCountdownFrame and true or false end
		if data.privateAurasCountdownNumbers ~= nil then cfg.privateAuras.countdownNumbers = data.privateAurasCountdownNumbers and true or false end
		if data.privateAurasShowDispelType ~= nil then cfg.privateAuras.showDispelType = data.privateAurasShowDispelType and true or false end
		if data.privateAurasDurationEnabled ~= nil then cfg.privateAuras.duration.enable = data.privateAurasDurationEnabled and true or false end
		if data.privateAurasDurationPoint ~= nil then cfg.privateAuras.duration.point = data.privateAurasDurationPoint end
		if data.privateAurasDurationOffsetX ~= nil then cfg.privateAuras.duration.offsetX = data.privateAurasDurationOffsetX end
		if data.privateAurasDurationOffsetY ~= nil then cfg.privateAuras.duration.offsetY = data.privateAurasDurationOffsetY end
	end

	if kind == "party" then
		if data.showPlayer ~= nil then cfg.showPlayer = data.showPlayer and true or false end
		if data.showSolo ~= nil then cfg.showSolo = data.showSolo and true or false end
		local custom = GFH.EnsureCustomSortConfig(cfg)
		if data.sortMethod ~= nil then
			local sortMethod = tostring(data.sortMethod):upper()
			if sortMethod == "CUSTOM" then sortMethod = "NAMELIST" end
			if sortMethod ~= "INDEX" and sortMethod ~= "NAME" and sortMethod ~= "NAMELIST" then sortMethod = (DEFAULTS.party and DEFAULTS.party.sortMethod) or "INDEX" end
			cfg.sortMethod = sortMethod
			if custom then custom.enabled = sortMethod == "NAMELIST" end
		end
		if data.sortDir ~= nil then
			local sortDir = tostring(data.sortDir):upper()
			cfg.sortDir = (GFH and GFH.NormalizeSortDir and GFH.NormalizeSortDir(sortDir)) or ((sortDir == "DESC") and "DESC" or "ASC")
		end
		if data.customSortEnabled ~= nil then
			custom.enabled = data.customSortEnabled and true or false
			if custom.enabled then
				cfg.sortMethod = "NAMELIST"
			elseif resolveSortMethod(cfg) == "NAMELIST" then
				cfg.sortMethod = (DEFAULTS.party and DEFAULTS.party.sortMethod) or "INDEX"
			end
		end
	elseif isRaidLikeKind(kind) then
		if kind == "raid" then
			local custom = GFH.EnsureCustomSortConfig(cfg)
			if data.customSortEnabled ~= nil then
				custom.enabled = data.customSortEnabled and true or false
				if custom.enabled then
					cfg.sortMethod = "NAMELIST"
				else
					local current = tostring(cfg.sortMethod or ""):upper()
					if current == "NAMELIST" or current == "CUSTOM" then cfg.sortMethod = (DEFAULTS.raid and DEFAULTS.raid.sortMethod) or "INDEX" end
				end
			elseif EditMode and EditMode.SetValue then
				EditMode:SetValue(EDITMODE_IDS[kind], "customSortEnabled", custom and custom.enabled == true, nil, true)
			end
			if data.customSortSeparateMeleeRanged ~= nil then
				custom.separateMeleeRanged = data.customSortSeparateMeleeRanged and true or false
				if custom.separateMeleeRanged then
					custom.roleOrder = GFH.ExpandRoleOrder(custom.roleOrder, true)
				else
					custom.roleOrder = GFH.CollapseRoleOrder(custom.roleOrder)
				end
			elseif EditMode and EditMode.SetValue then
				EditMode:SetValue(EDITMODE_IDS[kind], "customSortSeparateMeleeRanged", custom and custom.separateMeleeRanged == true, nil, true)
			end
		end
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

	local refreshNames = data.showName ~= nil
		or data.nameAnchor ~= nil
		or data.nameOffsetX ~= nil
		or data.nameOffsetY ~= nil
		or data.nameMaxChars ~= nil
		or data.nameNoEllipsis ~= nil
		or data.nameFontSize ~= nil
		or data.nameFont ~= nil
		or data.nameFontOutline ~= nil
		or data.nameClassColor ~= nil
		or data.nameColor ~= nil

	GF:ApplyHeaderAttributes(kind)
	if data.hideInClientScene ~= nil then GF:RefreshClientSceneVisibility() end
	if refreshNames then GF:RefreshNames() end
	if refreshAuras then refreshAllAuras() end
	if positionChanged and addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RefreshSettingValues then addon.EditModeLib.internal:RefreshSettingValues() end
	if positionChanged and EditMode and EditMode.RefreshFrame and not GF._syncingGroupFrameEditModePosition then
		local editModeId = EDITMODE_IDS and EDITMODE_IDS[kind]
		if editModeId then
			GF._syncingGroupFrameEditModePosition = true
			EditMode:RefreshFrame(editModeId)
			GF._syncingGroupFrameEditModePosition = false
		end
	end
end

function GF:EnsureEditMode()
	if GF._editModeRegistered then return end
	if not isFeatureEnabled() then return end
	if not (EditMode and EditMode.RegisterFrame and EditMode.IsAvailable and EditMode:IsAvailable()) then return end

	GF:EnsureHeaders()

	for _, kind in ipairs({ "party", "raid", "mt", "ma" }) do
		local anchor = GF.anchors and GF.anchors[kind]
		if anchor then
			GF:UpdateAnchorSize(kind)
			local cfg = getCfg(kind)
			local ac = ensureAuraConfig(cfg)
			local pcfg = cfg.power or {}
			local rc = cfg.roleIcon or {}
			local tcfg = cfg.tooltip or {}
			local sc = cfg.status or {}
			local gn = sc.groupNumber or {}
			local gi = cfg.groupIndicator or {}
			local lc = sc.leaderIcon or {}
			local acfg = sc.assistIcon or {}
			local hc = cfg.health or {}
			local def = DEFAULTS[kind] or {}
			local defStatus = def.status or {}
			local defUS = defStatus.unitStatus or {}
			local defGN = defStatus.groupNumber or {}
			local defGI = def.groupIndicator or {}
			local defTooltip = def.tooltip or {}
			local defH = def.health or {}
			local defP = def.power or {}
			local defAuras = def.auras or {}
			local defPrivate = def.privateAuras or {}
			local defBuff = defAuras.buff or {}
			local defDebuff = defAuras.debuff or {}
			local defExt = defAuras.externals or {}
			local pa = cfg.privateAuras or {}
			local paIcon = pa.icon or {}
			local paParent = pa.parent or {}
			local paDuration = pa.duration or {}
			local defPrivateIcon = defPrivate.icon or {}
			local defPrivateParent = defPrivate.parent or {}
			local defPrivateDuration = defPrivate.duration or {}
			local defDispel = def.status and def.status.dispelTint or {}
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
				groupGrowth = (kind == "raid") and ((GFH.ResolveGroupGrowthDirection and GFH.ResolveGroupGrowthDirection(
					cfg.groupGrowth,
					(GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(cfg.growth, "DOWN")) or "DOWN",
					DEFAULTS and DEFAULTS.raid and DEFAULTS.raid.groupGrowth
				)) or ((GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(cfg.groupGrowth, nil)) or ((((GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(
					cfg.growth,
					"DOWN"
				)) or "DOWN") == "RIGHT" or ((GFH.NormalizeGrowthDirection and GFH.NormalizeGrowthDirection(cfg.growth, "DOWN")) or "DOWN") == "LEFT") and "DOWN" or "RIGHT"))) or nil,
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
				tooltipMode = tcfg.mode or defTooltip.mode or "OFF",
				tooltipModifier = tcfg.modifier or defTooltip.modifier or "ALT",
				tooltipAuras = ac.buff.showTooltip == true and ac.debuff.showTooltip == true and ac.externals.showTooltip == true,
				showPlayer = cfg.showPlayer == true,
				showSolo = cfg.showSolo == true,
				hideInClientScene = (cfg.hideInClientScene ~= nil and cfg.hideInClientScene == true) or ((cfg.hideInClientScene == nil) and (def.hideInClientScene ~= false)),
				unitsPerColumn = cfg.unitsPerColumn or (DEFAULTS[kind] and DEFAULTS[kind].unitsPerColumn) or (DEFAULTS.raid and DEFAULTS.raid.unitsPerColumn) or 5,
				maxColumns = cfg.maxColumns or (DEFAULTS[kind] and DEFAULTS[kind].maxColumns) or (DEFAULTS.raid and DEFAULTS.raid.maxColumns) or 8,
				columnSpacing = cfg.columnSpacing or (DEFAULTS[kind] and DEFAULTS[kind].columnSpacing) or (DEFAULTS.raid and DEFAULTS.raid.columnSpacing) or 0,
				customSortEnabled = resolveSortMethod(cfg) == "NAMELIST",
				customSortSeparateMeleeRanged = (cfg.customSort and cfg.customSort.separateMeleeRanged) == true,
				showName = (cfg.text and cfg.text.showName) ~= false,
				nameClassColor = (cfg.text and cfg.text.useClassColor) ~= false,
				nameAnchor = (cfg.text and cfg.text.nameAnchor) or (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.nameAnchor) or "LEFT",
				nameOffsetX = (cfg.text and cfg.text.nameOffset and cfg.text.nameOffset.x) or 0,
				nameOffsetY = (cfg.text and cfg.text.nameOffset and cfg.text.nameOffset.y) or 0,
				nameMaxChars = (cfg.text and cfg.text.nameMaxChars) or (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.nameMaxChars) or 0,
				nameNoEllipsis = (cfg.text and cfg.text.nameNoEllipsis ~= nil) and (cfg.text.nameNoEllipsis == true)
					or ((cfg.text == nil or cfg.text.nameNoEllipsis == nil) and (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.nameNoEllipsis) == true),
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
				nameColorMode = sc.nameColorMode or (((cfg.text and cfg.text.useClassColor) ~= false) and "CLASS" or "CUSTOM"),
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
				statusTextEnabled = (sc.unitStatus and sc.unitStatus.enabled) ~= false,
				statusTextColor = (sc.unitStatus and sc.unitStatus.color) or (def.status and def.status.unitStatus and def.status.unitStatus.color) or { 1, 1, 1, 1 },
				statusTextFontSize = (sc.unitStatus and sc.unitStatus.fontSize) or (cfg.health and cfg.health.fontSize) or (defH and defH.fontSize) or 12,
				statusTextFont = (sc.unitStatus and sc.unitStatus.font) or (cfg.health and cfg.health.font) or (defH and defH.font) or nil,
				statusTextFontOutline = (sc.unitStatus and sc.unitStatus.fontOutline) or (cfg.health and cfg.health.fontOutline) or (defH and defH.fontOutline) or "OUTLINE",
				statusTextAnchor = (sc.unitStatus and sc.unitStatus.anchor) or (def.status and def.status.unitStatus and def.status.unitStatus.anchor) or "CENTER",
				statusTextOffsetX = (sc.unitStatus and sc.unitStatus.offset and sc.unitStatus.offset.x) or 0,
				statusTextOffsetY = (sc.unitStatus and sc.unitStatus.offset and sc.unitStatus.offset.y) or 0,
				statusTextShowOffline = (sc.unitStatus and sc.unitStatus.showOffline) or (def.status and def.status.unitStatus and def.status.unitStatus.showOffline) or true,
				statusTextShowAFK = (sc.unitStatus and sc.unitStatus.showAFK) or (def.status and def.status.unitStatus and def.status.unitStatus.showAFK) or false,
				statusTextShowDND = (sc.unitStatus and sc.unitStatus.showDND) or (def.status and def.status.unitStatus and def.status.unitStatus.showDND) or false,
				statusTextShowGroup = (gn.enabled ~= nil and gn.enabled) or (sc.unitStatus and sc.unitStatus.showGroup) or (defGN.enabled ~= nil and defGN.enabled) or defUS.showGroup or false,
				statusTextGroupFormat = gn.format or (sc.unitStatus and sc.unitStatus.groupFormat) or defGN.format or defUS.groupFormat or "GROUP",
				groupNumberColor = gn.color or defGN.color or (sc.unitStatus and sc.unitStatus.color) or defUS.color or { 1, 1, 1, 1 },
				groupNumberFontSize = gn.fontSize
					or defGN.fontSize
					or (sc.unitStatus and sc.unitStatus.fontSize)
					or defUS.fontSize
					or (cfg.health and cfg.health.fontSize)
					or (defH and defH.fontSize)
					or 12,
				groupNumberFont = gn.font or defGN.font or (sc.unitStatus and sc.unitStatus.font) or defUS.font or (cfg.health and cfg.health.font) or (defH and defH.font) or nil,
				groupNumberFontOutline = gn.fontOutline
					or defGN.fontOutline
					or (sc.unitStatus and sc.unitStatus.fontOutline)
					or defUS.fontOutline
					or (cfg.health and cfg.health.fontOutline)
					or (defH and defH.fontOutline)
					or "OUTLINE",
				groupNumberAnchor = gn.anchor or defGN.anchor or (sc.unitStatus and sc.unitStatus.anchor) or defUS.anchor or "CENTER",
				groupNumberOffsetX = (gn.offset and gn.offset.x)
					or (defGN.offset and defGN.offset.x)
					or (sc.unitStatus and sc.unitStatus.offset and sc.unitStatus.offset.x)
					or (defUS.offset and defUS.offset.x)
					or 0,
				groupNumberOffsetY = (gn.offset and gn.offset.y)
					or (defGN.offset and defGN.offset.y)
					or (sc.unitStatus and sc.unitStatus.offset and sc.unitStatus.offset.y)
					or (defUS.offset and defUS.offset.y)
					or 0,
				groupIndicatorEnabled = (gi.enabled ~= nil and gi.enabled == true) or ((gi.enabled == nil) and (defGI.enabled == true)),
				groupIndicatorHidePerFrame = (gi.hidePerFrame ~= nil and gi.hidePerFrame == true) or ((gi.hidePerFrame == nil) and (defGI.hidePerFrame == true)),
				groupIndicatorFormat = gi.format or defGI.format or "GROUP",
				groupIndicatorColor = gi.color or defGI.color or { 1, 1, 1, 1 },
				groupIndicatorFontSize = gi.fontSize or defGI.fontSize or (cfg.health and cfg.health.fontSize) or (defH and defH.fontSize) or 12,
				groupIndicatorFont = gi.font or defGI.font or (cfg.health and cfg.health.font) or (defH and defH.font) or nil,
				groupIndicatorFontOutline = gi.fontOutline or defGI.fontOutline or (cfg.health and cfg.health.fontOutline) or (defH and defH.fontOutline) or "OUTLINE",
				groupIndicatorAnchor = gi.anchor or defGI.anchor or "TOPLEFT",
				groupIndicatorOffsetX = (gi.offset and gi.offset.x) or (defGI.offset and defGI.offset.x) or 0,
				groupIndicatorOffsetY = (gi.offset and gi.offset.y) or (defGI.offset and defGI.offset.y) or 0,
				statusTextHideHealthTextOffline = (sc.unitStatus and sc.unitStatus.hideHealthTextWhenOffline)
					or (def.status and def.status.unitStatus and def.status.unitStatus.hideHealthTextWhenOffline)
					or false,
				dispelTintEnabled = (sc.dispelTint and sc.dispelTint.enabled ~= nil) and (sc.dispelTint.enabled ~= false)
					or ((sc.dispelTint == nil or sc.dispelTint.enabled == nil) and defDispel.enabled ~= false),
				dispelTintAlpha = (sc.dispelTint and sc.dispelTint.alpha) or defDispel.alpha or 0.25,
				dispelTintFillEnabled = (sc.dispelTint and sc.dispelTint.fillEnabled ~= nil) and (sc.dispelTint.fillEnabled == true)
					or ((sc.dispelTint == nil or sc.dispelTint.fillEnabled == nil) and defDispel.fillEnabled ~= false),
				dispelTintFillAlpha = (sc.dispelTint and sc.dispelTint.fillAlpha) or defDispel.fillAlpha or 0.2,
				dispelTintFillColor = (sc.dispelTint and sc.dispelTint.fillColor) or defDispel.fillColor or { 0, 0, 0, 1 },
				dispelTintSample = (sc.dispelTint and sc.dispelTint.showSample ~= nil) and (sc.dispelTint.showSample == true)
					or ((sc.dispelTint == nil or sc.dispelTint.showSample == nil) and defDispel.showSample == true),
				dispelTintGlowEnabled = (sc.dispelTint and sc.dispelTint.glowEnabled ~= nil) and (sc.dispelTint.glowEnabled == true)
					or ((sc.dispelTint == nil or sc.dispelTint.glowEnabled == nil) and defDispel.glowEnabled == true),
				dispelTintGlowColorMode = (sc.dispelTint and sc.dispelTint.glowColorMode) or defDispel.glowColorMode or "DISPEL",
				dispelTintGlowColor = (sc.dispelTint and sc.dispelTint.glowColor) or defDispel.glowColor or { 1, 1, 1, 1 },
				dispelTintGlowEffect = (sc.dispelTint and sc.dispelTint.glowEffect) or defDispel.glowEffect or "PIXEL",
				dispelTintGlowFrequency = (sc.dispelTint and sc.dispelTint.glowFrequency) or defDispel.glowFrequency or 0.25,
				dispelTintGlowX = (sc.dispelTint and sc.dispelTint.glowX) or defDispel.glowX or 0,
				dispelTintGlowY = (sc.dispelTint and sc.dispelTint.glowY) or defDispel.glowY or 0,
				dispelTintGlowLines = (sc.dispelTint and sc.dispelTint.glowLines) or defDispel.glowLines or 8,
				dispelTintGlowThickness = (sc.dispelTint and sc.dispelTint.glowThickness) or defDispel.glowThickness or 3,
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
				readyCheckIconEnabled = (sc.readyCheckIcon and sc.readyCheckIcon.enabled) ~= false,
				readyCheckIconSample = (sc.readyCheckIcon and sc.readyCheckIcon.sample) == true,
				readyCheckIconSize = (sc.readyCheckIcon and sc.readyCheckIcon.size) or (def.status and def.status.readyCheckIcon and def.status.readyCheckIcon.size) or 16,
				readyCheckIconPoint = (sc.readyCheckIcon and sc.readyCheckIcon.point) or (def.status and def.status.readyCheckIcon and def.status.readyCheckIcon.point) or "CENTER",
				readyCheckIconRelativePoint = (sc.readyCheckIcon and sc.readyCheckIcon.relativePoint)
					or (sc.readyCheckIcon and sc.readyCheckIcon.point)
					or (def.status and def.status.readyCheckIcon and def.status.readyCheckIcon.relativePoint)
					or (def.status and def.status.readyCheckIcon and def.status.readyCheckIcon.point)
					or "CENTER",
				readyCheckIconOffsetX = (sc.readyCheckIcon and sc.readyCheckIcon.x) or (def.status and def.status.readyCheckIcon and def.status.readyCheckIcon.x) or 0,
				readyCheckIconOffsetY = (sc.readyCheckIcon and sc.readyCheckIcon.y) or (def.status and def.status.readyCheckIcon and def.status.readyCheckIcon.y) or 0,
				summonIconEnabled = (sc.summonIcon and sc.summonIcon.enabled) ~= false,
				summonIconSample = (sc.summonIcon and sc.summonIcon.sample) == true,
				summonIconSize = (sc.summonIcon and sc.summonIcon.size) or (def.status and def.status.summonIcon and def.status.summonIcon.size) or 16,
				summonIconPoint = (sc.summonIcon and sc.summonIcon.point) or (def.status and def.status.summonIcon and def.status.summonIcon.point) or "CENTER",
				summonIconRelativePoint = (sc.summonIcon and sc.summonIcon.relativePoint)
					or (sc.summonIcon and sc.summonIcon.point)
					or (def.status and def.status.summonIcon and def.status.summonIcon.relativePoint)
					or (def.status and def.status.summonIcon and def.status.summonIcon.point)
					or "CENTER",
				summonIconOffsetX = (sc.summonIcon and sc.summonIcon.x) or (def.status and def.status.summonIcon and def.status.summonIcon.x) or 0,
				summonIconOffsetY = (sc.summonIcon and sc.summonIcon.y) or (def.status and def.status.summonIcon and def.status.summonIcon.y) or 0,
				resurrectIconEnabled = (sc.resurrectIcon and sc.resurrectIcon.enabled) ~= false,
				resurrectIconSample = (sc.resurrectIcon and sc.resurrectIcon.sample) == true,
				resurrectIconSize = (sc.resurrectIcon and sc.resurrectIcon.size) or (def.status and def.status.resurrectIcon and def.status.resurrectIcon.size) or 16,
				resurrectIconPoint = (sc.resurrectIcon and sc.resurrectIcon.point) or (def.status and def.status.resurrectIcon and def.status.resurrectIcon.point) or "CENTER",
				resurrectIconRelativePoint = (sc.resurrectIcon and sc.resurrectIcon.relativePoint)
					or (sc.resurrectIcon and sc.resurrectIcon.point)
					or (def.status and def.status.resurrectIcon and def.status.resurrectIcon.relativePoint)
					or (def.status and def.status.resurrectIcon and def.status.resurrectIcon.point)
					or "CENTER",
				resurrectIconOffsetX = (sc.resurrectIcon and sc.resurrectIcon.x) or (def.status and def.status.resurrectIcon and def.status.resurrectIcon.x) or 0,
				resurrectIconOffsetY = (sc.resurrectIcon and sc.resurrectIcon.y) or (def.status and def.status.resurrectIcon and def.status.resurrectIcon.y) or 0,
				phaseIconEnabled = (sc.phaseIcon and sc.phaseIcon.enabled) == true,
				phaseIconSample = (sc.phaseIcon and sc.phaseIcon.sample) == true,
				phaseIconSize = (sc.phaseIcon and sc.phaseIcon.size) or (def.status and def.status.phaseIcon and def.status.phaseIcon.size) or 14,
				phaseIconPoint = (sc.phaseIcon and sc.phaseIcon.point) or (def.status and def.status.phaseIcon and def.status.phaseIcon.point) or "TOPLEFT",
				phaseIconRelativePoint = (sc.phaseIcon and sc.phaseIcon.relativePoint)
					or (sc.phaseIcon and sc.phaseIcon.point)
					or (def.status and def.status.phaseIcon and def.status.phaseIcon.relativePoint)
					or (def.status and def.status.phaseIcon and def.status.phaseIcon.point)
					or "TOPLEFT",
				phaseIconOffsetX = (sc.phaseIcon and sc.phaseIcon.x) or (def.status and def.status.phaseIcon and def.status.phaseIcon.x) or 0,
				phaseIconOffsetY = (sc.phaseIcon and sc.phaseIcon.y) or (def.status and def.status.phaseIcon and def.status.phaseIcon.y) or 0,
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
				privateAurasEnabled = (pa.enabled ~= nil) and (pa.enabled == true) or ((pa.enabled == nil) and defPrivate.enabled == true),
				privateAurasAmount = paIcon.amount or defPrivateIcon.amount or 2,
				privateAurasSize = paIcon.size or defPrivateIcon.size or 20,
				privateAurasPoint = paIcon.point or defPrivateIcon.point or "LEFT",
				privateAurasOffset = paIcon.offset or defPrivateIcon.offset or 2,
				privateAurasParentPoint = paParent.point or defPrivateParent.point or "CENTER",
				privateAurasParentOffsetX = paParent.offsetX or defPrivateParent.offsetX or 0,
				privateAurasParentOffsetY = paParent.offsetY or defPrivateParent.offsetY or 0,
				privateAurasCountdownFrame = (pa.countdownFrame ~= nil) and (pa.countdownFrame ~= false) or ((pa.countdownFrame == nil) and defPrivate.countdownFrame ~= false),
				privateAurasCountdownNumbers = (pa.countdownNumbers ~= nil) and (pa.countdownNumbers ~= false) or ((pa.countdownNumbers == nil) and defPrivate.countdownNumbers ~= false),
				privateAurasShowDispelType = (pa.showDispelType ~= nil) and (pa.showDispelType == true) or ((pa.showDispelType == nil) and defPrivate.showDispelType == true),
				privateAurasDurationEnabled = (paDuration.enable ~= nil) and (paDuration.enable == true) or ((paDuration.enable == nil) and defPrivateDuration.enable == true),
				privateAurasDurationPoint = paDuration.point or defPrivateDuration.point or "BOTTOM",
				privateAurasDurationOffsetX = paDuration.offsetX or defPrivateDuration.offsetX or 0,
				privateAurasDurationOffsetY = paDuration.offsetY or defPrivateDuration.offsetY or 0,
				buffsEnabled = ac.buff.enabled == true,
				buffAnchor = buffAnchor,
				buffGrowth = buffGrowth,
				buffOffsetX = ac.buff.x or 0,
				buffOffsetY = ac.buff.y or 0,
				buffSize = ac.buff.size or 16,
				buffPerRow = ac.buff.perRow or 6,
				buffMax = ac.buff.max or 6,
				buffSpacing = ac.buff.spacing or 2,
				buffCooldownTextEnabled = (ac.buff.showCooldownText ~= nil and ac.buff.showCooldownText ~= false) or (ac.buff.showCooldownText == nil and defBuff.showCooldownText ~= false),
				buffCooldownTextAnchor = ac.buff.cooldownAnchor or defBuff.cooldownAnchor or "CENTER",
				buffCooldownTextOffsetX = (ac.buff.cooldownOffset and ac.buff.cooldownOffset.x) or (defBuff.cooldownOffset and defBuff.cooldownOffset.x) or 0,
				buffCooldownTextOffsetY = (ac.buff.cooldownOffset and ac.buff.cooldownOffset.y) or (defBuff.cooldownOffset and defBuff.cooldownOffset.y) or 0,
				buffCooldownTextSize = ac.buff.cooldownFontSize or defBuff.cooldownFontSize or 12,
				buffCooldownTextFont = ac.buff.cooldownFont or defBuff.cooldownFont or nil,
				buffCooldownTextOutline = ac.buff.cooldownFontOutline or defBuff.cooldownFontOutline or "OUTLINE",
				buffStackTextEnabled = (ac.buff.showStacks ~= nil and ac.buff.showStacks ~= false) or (ac.buff.showStacks == nil and defBuff.showStacks ~= false),
				buffStackAnchor = ac.buff.countAnchor or defBuff.countAnchor or "BOTTOMRIGHT",
				buffStackOffsetX = (ac.buff.countOffset and ac.buff.countOffset.x) or (defBuff.countOffset and defBuff.countOffset.x) or -2,
				buffStackOffsetY = (ac.buff.countOffset and ac.buff.countOffset.y) or (defBuff.countOffset and defBuff.countOffset.y) or 2,
				buffStackSize = ac.buff.countFontSize or defBuff.countFontSize or 12,
				buffStackFont = ac.buff.countFont or defBuff.countFont or nil,
				buffStackOutline = ac.buff.countFontOutline or defBuff.countFontOutline or "OUTLINE",
				debuffsEnabled = ac.debuff.enabled == true,
				debuffAnchor = debuffAnchor,
				debuffGrowth = debuffGrowth,
				debuffOffsetX = ac.debuff.x or 0,
				debuffOffsetY = ac.debuff.y or 0,
				debuffSize = ac.debuff.size or 16,
				debuffPerRow = ac.debuff.perRow or 6,
				debuffMax = ac.debuff.max or 6,
				debuffSpacing = ac.debuff.spacing or 2,
				debuffShowDispelIcon = (ac.debuff.showDispelIcon ~= nil and ac.debuff.showDispelIcon ~= false) or (ac.debuff.showDispelIcon == nil and defDebuff.showDispelIcon ~= false),
				debuffCooldownTextEnabled = (ac.debuff.showCooldownText ~= nil and ac.debuff.showCooldownText ~= false) or (ac.debuff.showCooldownText == nil and defDebuff.showCooldownText ~= false),
				debuffCooldownTextAnchor = ac.debuff.cooldownAnchor or defDebuff.cooldownAnchor or "CENTER",
				debuffCooldownTextOffsetX = (ac.debuff.cooldownOffset and ac.debuff.cooldownOffset.x) or (defDebuff.cooldownOffset and defDebuff.cooldownOffset.x) or 0,
				debuffCooldownTextOffsetY = (ac.debuff.cooldownOffset and ac.debuff.cooldownOffset.y) or (defDebuff.cooldownOffset and defDebuff.cooldownOffset.y) or 0,
				debuffCooldownTextSize = ac.debuff.cooldownFontSize or defDebuff.cooldownFontSize or 12,
				debuffCooldownTextFont = ac.debuff.cooldownFont or defDebuff.cooldownFont or nil,
				debuffCooldownTextOutline = ac.debuff.cooldownFontOutline or defDebuff.cooldownFontOutline or "OUTLINE",
				debuffStackTextEnabled = (ac.debuff.showStacks ~= nil and ac.debuff.showStacks ~= false) or (ac.debuff.showStacks == nil and defDebuff.showStacks ~= false),
				debuffStackAnchor = ac.debuff.countAnchor or defDebuff.countAnchor or "BOTTOMRIGHT",
				debuffStackOffsetX = (ac.debuff.countOffset and ac.debuff.countOffset.x) or (defDebuff.countOffset and defDebuff.countOffset.x) or -2,
				debuffStackOffsetY = (ac.debuff.countOffset and ac.debuff.countOffset.y) or (defDebuff.countOffset and defDebuff.countOffset.y) or 2,
				debuffStackSize = ac.debuff.countFontSize or defDebuff.countFontSize or 12,
				debuffStackFont = ac.debuff.countFont or defDebuff.countFont or nil,
				debuffStackOutline = ac.debuff.countFontOutline or defDebuff.countFontOutline or "OUTLINE",
				externalsEnabled = ac.externals.enabled == true,
				externalAnchor = externalAnchor,
				externalGrowth = externalGrowth,
				externalOffsetX = ac.externals.x or 0,
				externalOffsetY = ac.externals.y or 0,
				externalSize = ac.externals.size or 16,
				externalPerRow = ac.externals.perRow or 6,
				externalMax = ac.externals.max or 4,
				externalSpacing = ac.externals.spacing or 2,
				externalCooldownTextEnabled = (ac.externals.showCooldownText ~= nil and ac.externals.showCooldownText ~= false)
					or (ac.externals.showCooldownText == nil and defExt.showCooldownText ~= false),
				externalCooldownTextAnchor = ac.externals.cooldownAnchor or defExt.cooldownAnchor or "CENTER",
				externalCooldownTextOffsetX = (ac.externals.cooldownOffset and ac.externals.cooldownOffset.x) or (defExt.cooldownOffset and defExt.cooldownOffset.x) or 0,
				externalCooldownTextOffsetY = (ac.externals.cooldownOffset and ac.externals.cooldownOffset.y) or (defExt.cooldownOffset and defExt.cooldownOffset.y) or 0,
				externalCooldownTextSize = ac.externals.cooldownFontSize or defExt.cooldownFontSize or 12,
				externalCooldownTextFont = ac.externals.cooldownFont or defExt.cooldownFont or nil,
				externalCooldownTextOutline = ac.externals.cooldownFontOutline or defExt.cooldownFontOutline or "OUTLINE",
				externalStackTextEnabled = (ac.externals.showStacks ~= nil and ac.externals.showStacks ~= false) or (ac.externals.showStacks == nil and defExt.showStacks ~= false),
				externalStackAnchor = ac.externals.countAnchor or defExt.countAnchor or "BOTTOMRIGHT",
				externalStackOffsetX = (ac.externals.countOffset and ac.externals.countOffset.x) or (defExt.countOffset and defExt.countOffset.x) or -2,
				externalStackOffsetY = (ac.externals.countOffset and ac.externals.countOffset.y) or (defExt.countOffset and defExt.countOffset.y) or 2,
				externalStackSize = ac.externals.countFontSize or defExt.countFontSize or 12,
				externalStackFont = ac.externals.countFont or defExt.countFont or nil,
				externalStackOutline = ac.externals.countFontOutline or defExt.countFontOutline or "OUTLINE",
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
				title = (kind == "party" and (PARTY or "Party")) or (kind == "raid" and (RAID or "Raid")) or (kind == "mt" and "Main Tank") or (kind == "ma" and "Main Assist") or tostring(kind),
				layoutDefaults = defaults,
				settings = buildEditModeSettings(kind, EDITMODE_IDS[kind]),
				onApply = function(_, _, data) applyEditModeData(kind, data) end,
				onPositionChanged = function(_, _, dataOrPoint, x, y)
					if type(dataOrPoint) == "table" then
						applyEditModeData(kind, dataOrPoint)
					else
						applyEditModeData(kind, {
							point = dataOrPoint,
							relativePoint = dataOrPoint,
							x = x,
							y = y,
						})
					end
				end,
				onEnter = function() GF:OnEnterEditMode(kind) end,
				onExit = function() GF:OnExitEditMode(kind) end,
				isEnabled = function()
					local cfg = getCfg(kind)
					if not (cfg and cfg.enabled == true) then return false end
					if isSplitRoleKind(kind) then
						local db = DB or ensureDB()
						return db and db.raid and db.raid.enabled == true
					end
					return true
				end,
				allowDrag = function() return anchorUsesUIParent(kind) end,
				showOutsideEditMode = false,
				showReset = false,
				showSettingsReset = false,
				enableOverlayToggle = true,
				collapseExclusive = true,
				settingsMaxHeight = 700,
			})

			if EditMode and EditMode.RegisterButtons then
				local buttons = {
					{
						text = "Toggle sample frames",
						click = function() GF:ToggleEditModeSampleFrames(kind) end,
					},
					{
						text = "Toggle sample auras",
						click = function() GF:ToggleEditModeSampleAuras() end,
					},
					{
						text = "Toggle status text",
						click = function() GF:ToggleEditModeStatusText() end,
					},
				}
				if kind == "raid" or kind == "party" then table.insert(buttons, 1, {
					text = "Edit custom sort order",
					click = function() GF:ToggleCustomSortEditor(kind) end,
				}) end
				if kind == "raid" then table.insert(buttons, 2, {
					text = "Cycle sample size (10/20/30/40)",
					click = function() GF:CycleEditModeSampleSize(kind) end,
				}) end
				EditMode:RegisterButtons(EDITMODE_IDS[kind], buttons)
			end

			if addon.EditModeLib and addon.EditModeLib.SetFrameResetVisible then addon.EditModeLib:SetFrameResetVisible(anchor, false) end
		end
	end

	GF._editModeRegistered = true
	if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RefreshSettingValues then addon.EditModeLib.internal:RefreshSettingValues() end
end

function GF:OnEnterEditMode(kind)
	if not isFeatureEnabled() then return end
	local cfg = getCfg(kind)
	if not (cfg and cfg.enabled == true) then return end
	if GF._editModeSampleAuras == nil then GF._editModeSampleAuras = true end
	if GF._editModeSampleStatusText == nil then GF._editModeSampleStatusText = true end
	if GF._editModeSampleFrames == nil then GF._editModeSampleFrames = { party = false, raid = false, mt = false, ma = false } end
	if GF._previewSampleSize == nil then GF._previewSampleSize = { raid = 10 } end
	GF:EnsureHeaders()
	local header = GF.headers and GF.headers[kind]
	if not header then return end
	local wantSamples = GF._editModeSampleFrames and GF._editModeSampleFrames[kind] == true
	if wantSamples and not (InCombatLockdown and InCombatLockdown()) then
		header._eqolForceShow = nil
		header._eqolForceHide = true
		GF._previewActive = GF._previewActive or {}
		GF._previewActive[kind] = true
		GF:EnsurePreviewFrames(kind)
		GF:UpdatePreviewLayout(kind)
		GF:ShowPreviewFrames(kind, true)
	else
		if GF._previewActive then GF._previewActive[kind] = nil end
		GF:ShowPreviewFrames(kind, false)
		header._eqolForceHide = nil
		header._eqolForceShow = true
	end
	GF:ApplyHeaderAttributes(kind)
end

function GF:OnExitEditMode(kind)
	if not isFeatureEnabled() then return end
	local cfg = getCfg(kind)
	if not (cfg and cfg.enabled == true) then return end
	GF:EnsureHeaders()
	local header = GF.headers and GF.headers[kind]
	if not header then return end
	if GF._previewActive then GF._previewActive[kind] = nil end
	GF:ShowPreviewFrames(kind, false)
	header._eqolForceHide = nil
	header._eqolForceShow = nil
	if GF._customSortEditor and GF._customSortEditor.IsShown and GF._customSortEditor:IsShown() then GF._customSortEditor:Hide() end
	GF:ApplyHeaderAttributes(kind)
end

registerFeatureEvents = function(frame)
	if not frame then return end
	if frame.RegisterEvent then
		frame:RegisterEvent("PLAYER_ENTERING_WORLD")
		frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		frame:RegisterEvent("PLAYER_FLAGS_CHANGED")
		frame:RegisterEvent("GROUP_ROSTER_UPDATE")
		frame:RegisterEvent("UNIT_NAME_UPDATE")
		frame:RegisterEvent("PARTY_LEADER_CHANGED")
		frame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
		frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		frame:RegisterEvent("INSPECT_READY")
		frame:RegisterEvent("RAID_TARGET_UPDATE")
		frame:RegisterEvent("PLAYER_TARGET_CHANGED")
		frame:RegisterEvent("READY_CHECK")
		frame:RegisterEvent("READY_CHECK_CONFIRM")
		frame:RegisterEvent("READY_CHECK_FINISHED")
	end
end

unregisterFeatureEvents = function(frame)
	if not frame then return end
	if frame.UnregisterEvent then
		frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
		frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
		frame:UnregisterEvent("PLAYER_FLAGS_CHANGED")
		frame:UnregisterEvent("GROUP_ROSTER_UPDATE")
		frame:UnregisterEvent("UNIT_NAME_UPDATE")
		frame:UnregisterEvent("PARTY_LEADER_CHANGED")
		frame:UnregisterEvent("PLAYER_ROLES_ASSIGNED")
		frame:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		frame:UnregisterEvent("INSPECT_READY")
		frame:UnregisterEvent("RAID_TARGET_UPDATE")
		frame:UnregisterEvent("PLAYER_TARGET_CHANGED")
		frame:UnregisterEvent("READY_CHECK")
		frame:UnregisterEvent("READY_CHECK_CONFIRM")
		frame:UnregisterEvent("READY_CHECK_FINISHED")
	end
end

function GF:CancelPostEnterWorldRefreshTicker()
	local ticker = self._postEnterWorldTicker
	if ticker and ticker.Cancel then ticker:Cancel() end
	self._postEnterWorldTicker = nil
	self._postEnterWorldRefreshPasses = nil
end

function GF:RunPostEnterWorldRefreshPass()
	if not isFeatureEnabled() then return end
	self:EnsureHeaders()
	self.Refresh()
	self:RefreshRoleIcons()
	self:RefreshGroupIcons()
	self:RefreshStatusIcons()
	self:RefreshStatusText()
	self:RefreshGroupIndicators()
	self:RefreshCustomSortNameList("raid")
	self:RefreshCustomSortNameList("party")
	queueGroupIndicatorRefresh(0.05, 4)
end

function GF:SchedulePostEnterWorldRefresh()
	self:CancelPostEnterWorldRefreshTicker()
	if not (C_Timer and C_Timer.NewTicker) then
		self:RunPostEnterWorldRefreshPass()
		return
	end
	self._postEnterWorldRefreshPasses = 0
	self._postEnterWorldTicker = C_Timer.NewTicker(0.25, function()
		GF._postEnterWorldRefreshPasses = (GF._postEnterWorldRefreshPasses or 0) + 1
		if not isFeatureEnabled() then
			GF:CancelPostEnterWorldRefreshTicker()
			return
		end
		if not (InCombatLockdown and InCombatLockdown()) then GF:RunPostEnterWorldRefreshPass() end
		if (GF._postEnterWorldRefreshPasses or 0) >= 8 then GF:CancelPostEnterWorldRefreshTicker() end
	end)
end

do
	GF._eventFrame = CreateFrame("Frame")
	GF._eventFrame:RegisterEvent("PLAYER_LOGIN")
	GF._eventFrame:RegisterEvent("CLIENT_SCENE_OPENED")
	GF._eventFrame:RegisterEvent("CLIENT_SCENE_CLOSED")
	GF._eventFrame:SetScript("OnEvent", function(_, event, ...)
		if event == "PLAYER_LOGIN" then
			if isFeatureEnabled() then
				registerFeatureEvents(_)
				GF:EnsureHeaders()
				GF.Refresh()
				GF:DisableBlizzardFrames()
				GF:EnsureEditMode()
			end
		elseif event == "PLAYER_ENTERING_WORLD" then
			GF:RunPostEnterWorldRefreshPass()
			GF:SchedulePostEnterWorldRefresh()
		elseif event == "PLAYER_REGEN_ENABLED" then
			if GF._pendingDisable then
				GF._pendingDisable = nil
				GF:DisableFeature()
			elseif GF._pendingBlizzardDisable then
				GF:DisableBlizzardFrames()
			elseif GF._pendingRefresh then
				GF._pendingRefresh = false
				local applied = GF:ApplyPendingHeaderKinds()
				if not applied then GF.Refresh() end
			end
		elseif event == "CLIENT_SCENE_OPENED" then
			local sceneType = ...
			GF._clientSceneActive = (sceneType == 1)
			if isFeatureEnabled() then GF:RefreshClientSceneVisibility() end
		elseif event == "CLIENT_SCENE_CLOSED" then
			GF._clientSceneActive = false
			if isFeatureEnabled() then GF:RefreshClientSceneVisibility() end
		elseif not isFeatureEnabled() then
			return
		elseif event == "RAID_TARGET_UPDATE" then
			GF:RefreshRaidIcons()
		elseif event == "READY_CHECK" or event == "READY_CHECK_CONFIRM" or event == "READY_CHECK_FINISHED" then
			GF:RefreshReadyCheckIcons(event)
		elseif event == "PLAYER_TARGET_CHANGED" then
			GF:RefreshTargetHighlights()
		elseif event == "PLAYER_FLAGS_CHANGED" then
			GF:RefreshStatusText()
		elseif event == "INSPECT_READY" then
			if GFH and GFH.OnInspectReady then
				local updated = GFH.OnInspectReady(...)
				if updated then
					GF:RefreshCustomSortNameList("raid")
					if GF._previewActive and GF._previewActive.raid then GF:UpdatePreviewLayout("raid") end
				end
			end
		elseif event == "GROUP_ROSTER_UPDATE" then
			local rosterChanged, modeChanged, countChanged = GF:DidRosterStateChange()
			if not rosterChanged then return end
			local needsFullRefresh = modeChanged
			local cfg = getCfg("raid")
			local custom = cfg and GFH and GFH.EnsureCustomSortConfig and GFH.EnsureCustomSortConfig(cfg)
			local sortMethod = cfg and resolveSortMethod(cfg) or "INDEX"
			local useGroupedHeaders = cfg and GF:IsRaidGroupedLayout(cfg) and (sortMethod ~= "NAMELIST" or (custom and custom.enabled == true))
			if not needsFullRefresh and useGroupedHeaders and countChanged then needsFullRefresh = true end
			local updatedCount = 0
			if needsFullRefresh then
				GF.Refresh()
				updatedCount = 1
			else
				updatedCount = GF:RefreshChangedUnitButtons()
			end
			if sortMethod == "NAMELIST" then GF:RefreshCustomSortNameList("raid") end
			local partyCfg = getCfg("party")
			if partyCfg and resolveSortMethod(partyCfg) == "NAMELIST" then GF:RefreshCustomSortNameList("party") end
			if needsFullRefresh or updatedCount > 0 then
				GF:RefreshStatusIcons()
				GF:RefreshGroupIndicators()
				queueGroupIndicatorRefresh(0, 4)
			end
			if custom and custom.separateMeleeRanged == true and sortMethod == "NAMELIST" and GFH and GFH.QueueInspectGroup then GFH.QueueInspectGroup() end
		elseif event == "PLAYER_ROLES_ASSIGNED" then
			GF:RefreshRoleIcons()
			GF:RefreshCustomSortNameList("raid")
			GF:RefreshCustomSortNameList("party")
			local cfg = getCfg("raid")
			local custom = cfg and GFH and GFH.EnsureCustomSortConfig and GFH.EnsureCustomSortConfig(cfg)
			if custom and custom.separateMeleeRanged == true and resolveSortMethod(cfg) == "NAMELIST" and GFH and GFH.QueueInspectGroup then GFH.QueueInspectGroup() end
		elseif event == "PARTY_LEADER_CHANGED" then
			GF:RefreshGroupIcons()
			GF:RefreshStatusText()
		elseif event == "UNIT_NAME_UPDATE" then
			GF:RefreshGroupIndicators()
		elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
			GF:RefreshPowerVisibility()
			GF:RefreshCustomSortNameList("raid")
			GF:RefreshCustomSortNameList("party")
			local cfg = getCfg("raid")
			local custom = cfg and GFH and GFH.EnsureCustomSortConfig and GFH.EnsureCustomSortConfig(cfg)
			if custom and custom.separateMeleeRanged == true and resolveSortMethod(cfg) == "NAMELIST" and GFH and GFH.QueueInspectGroup then GFH.QueueInspectGroup() end
		end
	end)
end
