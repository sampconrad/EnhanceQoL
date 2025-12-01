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
local UnitExists = UnitExists
local InCombatLockdown = InCombatLockdown
local BreakUpLargeNumbers = BreakUpLargeNumbers
local AbbreviateNumbers = AbbreviateNumbers
local EnumPowerType = Enum and Enum.PowerType
local PowerBarColor = PowerBarColor
local UnitName, UnitClass, UnitLevel, UnitClassification = UnitName, UnitClass, UnitLevel, UnitClassification
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs or function() return 0 end
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local CUSTOM_CLASS_COLORS = CUSTOM_CLASS_COLORS
local AuraUtil = AuraUtil
local C_UnitAuras = C_UnitAuras
local CopyTable = CopyTable
local UIParent = UIParent
local CreateFrame = CreateFrame
local IsShiftKeyDown = IsShiftKeyDown
local After = C_Timer and C_Timer.After
local floor = math.floor
local max = math.max
local abs = math.abs
local wipe = wipe or (table and table.wipe)

local PLAYER_UNIT = "player"
local TARGET_UNIT = "target"
local TARGET_TARGET_UNIT = "targettarget"
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
local MIN_WIDTH = 50

local function getFont(path)
	if path and path ~= "" then return path end
	return addon.variables and addon.variables.defaultFont or (LSM and LSM:Fetch("font", LSM.DefaultMedia.font)) or STANDARD_TEXT_FONT
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
}

local defaults = {
	player = {
		enabled = false,
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
		},
	},
	target = {
		enabled = false,
		auraIcons = { size = 24, padding = 2, max = 16, showCooldown = true },
	},
	targettarget = {
		enabled = false,
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

local function defaultsFor(unit) return defaults[unit] or defaults.player or {} end

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
	db[unit] = db[unit] or {}
	local udb = db[unit]
	local def = defaults[unit] or defaults.player or {}
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

local function ensureAuraButton(index, ac)
	local st = states.target
	if not st or not st.auraContainer then return nil end
	local icons = st.auraButtons or {}
	st.auraButtons = icons
	local btn = icons[index]
	if not btn then
		btn = CreateFrame("Button", nil, st.auraContainer)
		btn:SetSize(ac.size, ac.size)
		btn.icon = btn:CreateTexture(nil, "ARTWORK")
		btn.icon:SetAllPoints(btn)
		btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
		btn.cd:SetAllPoints(btn)
		local overlay = CreateFrame("Frame", nil, btn.cd)
		overlay:SetAllPoints(btn.cd)
		overlay:SetFrameLevel(btn.cd:GetFrameLevel() + 5)

		btn.count = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		btn.count:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -2, 2)
		btn.cd:SetReverse(true)
		btn.cd:SetDrawEdge(true)
		btn.cd:SetDrawSwipe(true)
		icons[index] = btn
	else
		btn:SetSize(ac.size, ac.size)
	end
	return btn
end

local function applyAuraToButton(btn, aura, ac)
	if not btn or not aura then return end
	btn.icon:SetTexture(aura.icon or "")
	btn.cd:Clear()
	if issecretvalue and issecretvalue(aura.duration) then
		btn.cd:SetCooldown(GetTime(), C_UnitAuras.GetAuraDurationRemainingByAuraInstanceID("target", aura.auraInstanceID), aura.timeMod)
	elseif aura.duration and aura.duration > 0 and aura.expirationTime then
		btn.cd:SetCooldown(aura.expirationTime - aura.duration, aura.duration, aura.timeMod)
	end
	btn.cd:SetHideCountdownNumbers(ac.showCooldown == false)
	if issecretvalue and issecretvalue(aura.applications) or aura.applications and aura.applications > 1 then
		btn.count:SetText(aura.applications)
		btn.count:Show()
	else
		btn.count:SetText("")
		btn.count:Hide()
	end
	btn:Show()
end

local function anchorAuraButton(btn, index, ac, perRow, st)
	if not btn or not st then return end
	local row = math.floor((index - 1) / perRow)
	local col = (index - 1) % perRow
	btn:ClearAllPoints()
	btn:SetPoint("TOPLEFT", st.auraContainer, "TOPLEFT", col * (ac.size + ac.padding), -row * (ac.size + ac.padding))
end

local function updateAuraContainerSize(shown, ac, perRow, st)
	if not st then return end
	local rows = math.ceil(shown / perRow)
	st.auraContainer:SetHeight(rows > 0 and (rows * (ac.size + ac.padding) - ac.padding) or 0.001)
	st.auraContainer:SetShown(shown > 0)
end

local function updateTargetAuraIcons(startIndex)
	local st = states.target
	if not st or not st.auraContainer or not st.frame then return end
	local icons = st.auraButtons or {}
	st.auraButtons = icons
	local cfg = ensureDB("target")
	local ac = cfg.auraIcons or defaults.target.auraIcons or { size = 24, padding = 2, max = 16, showCooldown = true }
	ac.size = ac.size or 24
	ac.padding = ac.padding or 0
	ac.max = ac.max or 16
	if ac.max < 1 then ac.max = 1 end

	local width = st.frame:GetWidth() or 0
	local perRow = math.max(1, math.floor((width + ac.padding) / (ac.size + ac.padding)))
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
			local btn = ensureAuraButton(i, ac)
			applyAuraToButton(btn, aura, ac)
			anchorAuraButton(btn, i, ac, perRow, st)
			targetAuraIndexById[auraId] = i
			i = i + 1
		end
	end

	for idx = shown + 1, #icons do
		if icons[idx] then icons[idx]:Hide() end
	end

	updateAuraContainerSize(shown, ac, perRow, st)
end

local function fullScanTargetAuras()
	resetTargetAuras()
	if not UnitExists or not UnitExists("target") then return end
	if C_UnitAuras and C_UnitAuras.GetUnitAuras then
		local helpful = C_UnitAuras.GetUnitAuras("target", "HELPFUL|CANCELABLE")
		for i = 1, #helpful do
			cacheTargetAura(helpful[i])
			addTargetAuraToOrder(helpful[i].auraInstanceID)
		end
		local harmful = C_UnitAuras.GetUnitAuras("target", "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY")
		for i = 1, #harmful do
			cacheTargetAura(harmful[i])
			addTargetAuraToOrder(harmful[i].auraInstanceID)
		end
	elseif C_UnitAuras and C_UnitAuras.GetAuraSlots then
		local helpful = { C_UnitAuras.GetAuraSlots("target", "HELPFUL|CANCELABLE") }
		for i = 2, #helpful do
			local slot = helpful[i]
			local aura = C_UnitAuras.GetAuraDataBySlot("target", slot)
			cacheTargetAura(aura)
			addTargetAuraToOrder(aura and aura.auraInstanceID)
		end
		local harmful = { C_UnitAuras.GetAuraSlots("target", "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY") }
		for i = 2, #harmful do
			local slot = harmful[i]
			local aura = C_UnitAuras.GetAuraDataBySlot("target", slot)
			cacheTargetAura(aura)
			addTargetAuraToOrder(aura and aura.auraInstanceID)
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
	targetDefaults.auraIcons = { size = 24, padding = 2, max = 16, showCooldown = true }
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

local function updateHealth(cfg, unit)
	local st = states[unit]
	if not st or not st.health or not st.frame then return end
	local cur = UnitHealth(unit)
	local maxv = UnitHealthMax(unit)
	if issecretvalue and issecretvalue(maxv) then
		st.health:SetMinMaxValues(0, maxv or 1)
	else
		st.health:SetMinMaxValues(0, maxv > 0 and maxv or 1)
	end
	st.health:SetValue(cur or 0)
	local hc = cfg.health or {}
	configureSpecialTexture(st.health, "HEALTH", hc.texture, hc)
	local percentVal
	if addon.variables and addon.variables.isMidnight and UnitHealthPercent then
		percentVal = UnitHealthPercent(unit, true, true)
	else
		if (not addon.variables or not addon.variables.isMidnight or not issecretvalue or (not issecretvalue(cur) and not issecretvalue(maxv))) and maxv and maxv > 0 then
			percentVal = (cur or 0) / maxv * 100
		end
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
	st.health:SetStatusBarDesaturated(true)
	if st.absorb then
		local abs = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0
		if issecretvalue and issecretvalue(maxv) then
			st.absorb:SetMinMaxValues(0, maxv or 1)
		else
			st.absorb:SetMinMaxValues(0, maxv > 0 and maxv or 1)
		end
		st.absorb:SetValue(abs or 0)
		local ac = hc.absorbColor or { 0.85, 0.95, 1, 0.7 }
		st.absorb:SetStatusBarColor(ac[1] or 0.85, ac[2] or 0.95, ac[3] or 1, ac[4] or 0.7)
	end
	if st.healthTextLeft then st.healthTextLeft:SetText(formatText(hc.textLeft or "PERCENT", cur, maxv, hc.useShortNumbers ~= false, percentVal)) end
	if st.healthTextRight then st.healthTextRight:SetText(formatText(hc.textRight or "CURMAX", cur, maxv, hc.useShortNumbers ~= false, percentVal)) end
end

local function updatePower(cfg, unit)
	local st = states[unit]
	if not st then return end
	local bar = st.power
	if not bar then return end
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
	local pcfg = cfg.power or {}
	configureSpecialTexture(bar, powerToken, pcfg.texture, pcfg)
	local percentVal
	if addon.variables and addon.variables.isMidnight and UnitPowerPercent then
		percentVal = UnitPowerPercent(unit, powerEnum, true, true)
	else
		if (not addon.variables or not addon.variables.isMidnight or not issecretvalue or (not issecretvalue(cur) and not issecretvalue(maxv))) and maxv and maxv > 0 then
			percentVal = (cur or 0) / maxv * 100
		end
	end
	local cr, cg, cb, ca
	if pcfg.useCustomColor and pcfg.color and pcfg.color[1] then
		cr, cg, cb, ca = pcfg.color[1], pcfg.color[2], pcfg.color[3], pcfg.color[4] or 1
	else
		cr, cg, cb, ca = getPowerColor(powerToken)
	end
	bar:SetStatusBarColor(cr or 0.1, cg or 0.45, cb or 1, ca or 1)
	if bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(pcfg.useCustomColor ~= true) end
	if st.powerTextLeft then
		if (issecretvalue and not issecretvalue(maxv)) or (not addon.variables.isMidnight and maxv == 0) then
			st.powerTextLeft:SetText("")
		else
			st.powerTextLeft:SetText(formatText(pcfg.textLeft or "PERCENT", cur, maxv, pcfg.useShortNumbers ~= false, percentVal))
		end
	end
	if (issecretvalue and not issecretvalue(maxv)) or (not addon.variables.isMidnight and maxv == 0) then
		st.powerTextRight:SetText("")
	else
		if st.powerTextRight then st.powerTextRight:SetText(formatText(pcfg.textRight or "CURMAX", cur, maxv, pcfg.useShortNumbers ~= false, percentVal)) end
	end
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

local function updateStatus(cfg, unit)
	local st = states[unit]
	if not st or not st.status then return end
	local scfg = cfg.status or {}
	local def = defaults[unit] or defaults.player or {}
	st.status:SetHeight((cfg.status and cfg.status.enabled) and (cfg.statusHeight or def.statusHeight) or 0.001)
	st.status:SetShown(scfg.enabled ~= false)
	if st.nameText then
		applyFont(st.nameText, scfg.font, scfg.fontSize or 14, scfg.fontOutline)
		local class = select(2, UnitClass(unit))
		local nc
		if scfg.nameColorMode == "CLASS" then
			nc = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
		else
			nc = scfg.nameColor or { 1, 1, 1, 1 }
		end
		st.nameText:SetText(UnitName(unit) or "")
		st.nameText:SetTextColor(nc and (nc.r or nc[1] or 1) or 1, nc and (nc.g or nc[2] or 1) or 1, nc and (nc.b or nc[3] or 1) or 1, nc and (nc.a or nc[4] or 1) or 1)
		st.nameText:ClearAllPoints()
		st.nameText:SetPoint(scfg.nameAnchor or "LEFT", st.status, scfg.nameAnchor or "LEFT", (scfg.nameOffset and scfg.nameOffset.x) or 0, (scfg.nameOffset and scfg.nameOffset.y) or 0)
		st.nameText:SetShown(scfg.enabled ~= false)
	end
	if st.levelText then
		applyFont(st.levelText, scfg.font, scfg.fontSize or 14, scfg.fontOutline)
		local lc = scfg.levelColor or { 1, 0.85, 0, 1 }
		st.levelText:SetText(UnitLevel(unit) or "")
		st.levelText:SetTextColor(lc[1] or 1, lc[2] or 0.85, lc[3] or 0, lc[4] or 1)
		st.levelText:ClearAllPoints()
		st.levelText:SetPoint(scfg.levelAnchor or "RIGHT", st.status, scfg.levelAnchor or "RIGHT", (scfg.levelOffset and scfg.levelOffset.x) or 0, (scfg.levelOffset and scfg.levelOffset.y) or 0)
		st.levelText:SetShown(scfg.enabled ~= false and scfg.levelEnabled ~= false)
	end
end

local function layoutFrame(cfg, unit)
	local st = states[unit]
	if not st or not st.frame then return end
	local def = defaults[unit] or defaults.player or {}
	local width = max(MIN_WIDTH, cfg.width or def.width)
	local statusHeight = (cfg.status and cfg.status.enabled == false) and 0 or (cfg.statusHeight or def.statusHeight)
	local healthHeight = cfg.healthHeight or def.healthHeight
	local powerHeight = cfg.powerHeight or def.powerHeight
	local barGap = cfg.barGap or def.barGap or 0
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

	st.status:ClearAllPoints()
	if st.barGroup then st.barGroup:ClearAllPoints() end
	st.health:ClearAllPoints()
	st.power:ClearAllPoints()

	local anchor = cfg.anchor or def.anchor or defaults.player.anchor
	local rel = (anchor and _G[anchor.relativeTo]) or UIParent
	st.frame:ClearAllPoints()
	st.frame:SetPoint(anchor.point or "CENTER", rel or UIParent, anchor.relativePoint or anchor.point or "CENTER", anchor.x or 0, anchor.y or 0)

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

	-- Apply border only around the bar region wrapper
	if st.barGroup then setBackdrop(st.barGroup, cfg.border) end

	if unit == "target" and st.auraContainer then
		st.auraContainer:ClearAllPoints()
		st.auraContainer:SetPoint("TOPLEFT", st.barGroup, "BOTTOMLEFT", 0, -5)
		st.auraContainer:SetWidth(width + borderInset * 2)
	end
end

local function ensureFrames(unit)
	local info = UNITS[unit]
	if not info then return end
	states[unit] = states[unit] or {}
	local st = states[unit]
	addon.variables.states = states
	if st.frame then return end
	st.frame = _G[info.frameName] or CreateFrame("Button", info.frameName, UIParent, "BackdropTemplate,SecureUnitButtonTemplate")
	st.frame:SetAttribute("unit", info.unit)
	st.frame:SetAttribute("type1", "target")
	st.frame:SetAttribute("type2", "togglemenu")
	st.frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	st.frame:Hide()
	hideSettingsReset(st.frame)

	if info.dropdown then st.frame.menu = info.dropdown end
	st.frame:SetClampedToScreen(true)
	st.status = _G[info.statusName] or CreateFrame("Frame", info.statusName, st.frame)
	st.barGroup = st.barGroup or CreateFrame("Frame", nil, st.frame, "BackdropTemplate")
	st.health = _G[info.healthName] or CreateFrame("StatusBar", info.healthName, st.barGroup, "BackdropTemplate")
	st.power = _G[info.powerName] or CreateFrame("StatusBar", info.powerName, st.barGroup, "BackdropTemplate")
	st.absorb = CreateFrame("StatusBar", info.healthName .. "Absorb", st.health, "BackdropTemplate")

	st.healthTextLeft = st.health:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.healthTextRight = st.health:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.powerTextLeft = st.power:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.powerTextRight = st.power:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.nameText = st.status:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	st.levelText = st.status:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

	if unit == "target" then
		st.auraContainer = CreateFrame("Frame", nil, st.frame)
		st.auraButtons = {}
	end

	st.frame:SetMovable(true)
	st.frame:EnableMouse(true)
	st.frame:RegisterForDrag("LeftButton")
	st.frame:SetScript("OnDragStart", function(self)
		if InCombatLockdown() then return end
		if IsShiftKeyDown() then self:StartMoving() end
	end)
	st.frame:SetScript("OnDragStop", function(self)
		if InCombatLockdown() then return end
		self:StopMovingOrSizing()
		local point, rel, relPoint, x, y = self:GetPoint(1)
		local cfg = ensureDB(unit)
		cfg.anchor = cfg.anchor or {}
		cfg.anchor.point = point
		cfg.anchor.relativeTo = (rel and rel.GetName and rel:GetName()) or "UIParent"
		cfg.anchor.relativePoint = relPoint
		cfg.anchor.x = x
		cfg.anchor.y = y
	end)
end

local function applyBars(cfg, unit)
	local st = states[unit]
	if not st or not st.health or not st.power then return end
	local hc = cfg.health or {}
	local pcfg = cfg.power or {}
	st.health:SetStatusBarTexture(resolveTexture(hc.texture))
	configureSpecialTexture(st.health, "HEALTH", hc.texture, hc)
	applyBarBackdrop(st.health, hc)
	st.power:SetStatusBarTexture(resolveTexture(pcfg.texture))
	local _, powerToken = getMainPower(unit)
	configureSpecialTexture(st.power, powerToken, pcfg.texture, pcfg)
	applyBarBackdrop(st.power, pcfg)
	st.absorb:SetStatusBarTexture(LSM and LSM:Fetch("statusbar", "Blizzard") or BLIZZARD_TEX)
	st.absorb:SetAllPoints(st.health)
	st.absorb:SetFrameLevel(st.health:GetFrameLevel() + 1)
	st.absorb:SetMinMaxValues(0, 1)
	st.absorb:SetValue(0)
	st.absorb:SetStatusBarColor(0.8, 0.8, 0.9, 0.6)

	applyFont(st.healthTextLeft, hc.font, hc.fontSize or 14)
	applyFont(st.healthTextRight, hc.font, hc.fontSize or 14)
	applyFont(st.powerTextLeft, pcfg.font, pcfg.fontSize or 14)
	applyFont(st.powerTextRight, pcfg.font, pcfg.fontSize or 14)
	applyFont(st.nameText, cfg.status.font, cfg.status.fontSize or 14, cfg.status.fontOutline)
	applyFont(st.levelText, cfg.status.font, cfg.status.fontSize or 14, cfg.status.fontOutline)
end

local function updateNameAndLevel(cfg, unit)
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
	local st = states[unit]
	if not cfg.enabled then
		if st and st.frame then st.frame:Hide() end
		if unit == "target" then resetTargetAuras() end
		return
	end
	ensureFrames(unit)
	st = states[unit]
	applyBars(cfg, unit)
	if not InCombatLockdown() then layoutFrame(cfg, unit) end
	updateStatus(cfg, unit)
	updateNameAndLevel(cfg, unit)
	updateHealth(cfg, unit)
	updatePower(cfg, unit)
	-- if unit == "target" then hideBlizzardTargetFrame() end
	if not InCombatLockdown() then
		if st and st.frame then st.frame:Show() end
	end
	if unit ~= "player" then
		st.barGroup:Hide()
		st.status:Hide()
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
}

local eventFrame

local allowedEventUnit = {
	["target"] = true,
	["player"] = true,
	["targettarget"] = true,
}

local function updateTargetTargetFrame(cfg)
	cfg = cfg or ensureDB(TARGET_TARGET_UNIT)
	local st = states[TARGET_TARGET_UNIT]
	if not cfg.enabled then
		if st and st.frame then st.frame:Hide() end
		return
	end
	if UnitExists(TARGET_TARGET_UNIT) then
		applyConfig(TARGET_TARGET_UNIT)
		st = states[TARGET_TARGET_UNIT]
		if st and st.frame then
			st.barGroup:Show()
			st.status:Show()
		end
	else
		if st and st.frame then
			if st.barGroup then st.barGroup:Hide() end
			if st.status then st.status:Hide() end
		end
	end
end

local function onEvent(self, event, unit, arg1)
	if unitEventsMap[event] and unit and not allowedEventUnit[unit] then return end
	local playerCfg = ensureDB("player")
	local targetCfg = ensureDB("target")
	local totCfg = ensureDB(TARGET_TARGET_UNIT)
	if event == "PLAYER_ENTERING_WORLD" then
		refreshMainPower(PLAYER_UNIT)
		applyConfig("player")
		applyConfig("target")
		updateTargetTargetFrame(totCfg)
		hideBlizzardPlayerFrame()
	elseif event == "PLAYER_DEAD" then
		if states.player and states.player.health then states.player.health:SetValue(0) end
		updateHealth(playerCfg, "player")
	elseif event == "PLAYER_ALIVE" then
		refreshMainPower(PLAYER_UNIT)
		updateHealth(playerCfg, "player")
		updatePower(playerCfg, "player")
	elseif event == "PLAYER_TARGET_CHANGED" then
		if UnitExists("target") then
			refreshMainPower("target")
			fullScanTargetAuras()
			applyConfig("target")
			if states and states["target"] and states["target"].frame then
				states["target"].barGroup:Show()
				states["target"].status:Show()
			end
			if totCfg.enabled then updateTargetTargetFrame(totCfg) end
		else
			resetTargetAuras()
			updateTargetAuraIcons()
			if states and states["target"] and states["target"].frame then
				states["target"].barGroup:Hide()
				states["target"].status:Hide()
			end
			updateTargetTargetFrame(totCfg)
		end
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
		local cfg = ensureDB("target")
		local ac = cfg.auraIcons or defaults.target.auraIcons or { size = 24, padding = 2, max = 16, showCooldown = true }
		ac.size = ac.size or 24
		ac.padding = ac.padding or 0
		ac.max = ac.max or 16
		if ac.max < 1 then ac.max = 1 end
		local st = states.target
		if not st or not st.auraContainer then return end
		local width = st.frame and st.frame:GetWidth() or 0
		local perRow = math.max(1, math.floor((width + ac.padding) / (ac.size + ac.padding)))
		local firstChanged
		if eventInfo.addedAuras then
			for _, aura in ipairs(eventInfo.addedAuras) do
				if not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, aura.auraInstanceID, "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY") then
					cacheTargetAura(aura)
					local idx = addTargetAuraToOrder(aura.auraInstanceID)
					if idx and idx <= ac.max then
						if not firstChanged or idx < firstChanged then firstChanged = idx end
					end
				elseif not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, aura.auraInstanceID, "HELPFUL|CANCELABLE") then
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
		if unit == TARGET_TARGET_UNIT then updateHealth(totCfg, TARGET_TARGET_UNIT) end
	elseif event == "UNIT_MAXPOWER" then
		if unit == PLAYER_UNIT then updatePower(playerCfg, "player") end
		if unit == "target" then updatePower(targetCfg, "target") end
		if unit == TARGET_TARGET_UNIT then updatePower(totCfg, TARGET_TARGET_UNIT) end
	elseif event == "UNIT_DISPLAYPOWER" then
		if unit == PLAYER_UNIT then
			refreshMainPower()
			updatePower(playerCfg, "player")
		elseif unit == "target" then
			updatePower(targetCfg, "target")
		elseif unit == TARGET_TARGET_UNIT then
			updatePower(totCfg, TARGET_TARGET_UNIT)
		end
	elseif event == "UNIT_POWER_UPDATE" and not FREQUENT[arg1] then
		if unit == PLAYER_UNIT then updatePower(playerCfg, "player") end
		if unit == "target" then updatePower(targetCfg, "target") end
		if unit == TARGET_TARGET_UNIT then updatePower(totCfg, TARGET_TARGET_UNIT) end
	elseif event == "UNIT_POWER_FREQUENT" and FREQUENT[arg1] then
		if unit == PLAYER_UNIT then updatePower(playerCfg, "player") end
		if unit == "target" then updatePower(targetCfg, "target") end
		if unit == TARGET_TARGET_UNIT then updatePower(totCfg, TARGET_TARGET_UNIT) end
	elseif event == "UNIT_NAME_UPDATE" or event == "PLAYER_LEVEL_UP" then
		if unit == PLAYER_UNIT or event == "PLAYER_LEVEL_UP" then updateNameAndLevel(playerCfg, "player") end
		if unit == "target" then updateNameAndLevel(targetCfg, "target") end
		if unit == TARGET_TARGET_UNIT then updateNameAndLevel(totCfg, TARGET_TARGET_UNIT) end
	elseif event == "UNIT_TARGET" and unit == TARGET_UNIT then
		if totCfg.enabled then updateTargetTargetFrame(totCfg) end
	end
end

local function ensureEventHandling()
	if eventFrame then return end
	eventFrame = CreateFrame("Frame")
	for _, evt in ipairs(unitEvents) do
		eventFrame:RegisterEvent(evt)
	end
	for _, evt in ipairs(generalEvents) do
		eventFrame:RegisterEvent(evt)
	end
	eventFrame:SetScript("OnEvent", onEvent)
end

function UF.Enable()
	local cfg = ensureDB("player")
	cfg.enabled = true
	ensureEventHandling()
	applyConfig("player")
	if ensureDB("target").enabled then applyConfig("target") end
	local totCfg = ensureDB(TARGET_TARGET_UNIT)
	if totCfg.enabled then updateTargetTargetFrame(totCfg) end
	hideBlizzardPlayerFrame()
	hideBlizzardTargetFrame()
end

function UF.Disable()
	local cfg = ensureDB("player")
	cfg.enabled = false
	if states.player and states.player.frame then states.player.frame:Hide() end
	addon.variables.requireReload = true
	if addon.functions and addon.functions.checkReloadFrame then addon.functions.checkReloadFrame() end
	if _G.PlayerFrame and not InCombatLockdown() then _G.PlayerFrame:Show() end
end

function UF.Refresh()
	ensureEventHandling()
	applyConfig("player")
	applyConfig("target")
	applyConfig(TARGET_TARGET_UNIT)
	local targetCfg = ensureDB("target")
	if targetCfg.enabled and UnitExists and UnitExists(TARGET_UNIT) and states[TARGET_UNIT] and states[TARGET_UNIT].frame then
		states[TARGET_UNIT].barGroup:Show()
		states[TARGET_UNIT].status:Show()
	end
	local totCfg = ensureDB(TARGET_TARGET_UNIT)
	if totCfg.enabled then updateTargetTargetFrame(totCfg) end
end

function UF.RefreshUnit(unit)
	ensureEventHandling()
	if unit == TARGET_TARGET_UNIT then
		local totCfg = ensureDB(TARGET_TARGET_UNIT)
		if totCfg.enabled then updateTargetTargetFrame(totCfg) end
	elseif unit == TARGET_UNIT then
		applyConfig(TARGET_UNIT)
		local targetCfg = ensureDB("target")
		if targetCfg.enabled and UnitExists and UnitExists(TARGET_UNIT) and states[TARGET_UNIT] and states[TARGET_UNIT].frame then
			states[TARGET_UNIT].barGroup:Show()
			states[TARGET_UNIT].status:Show()
		end
	else
		applyConfig(PLAYER_UNIT)
	end
end

local function addOptions(container, skipClear, unit)
	unit = unit or PLAYER_UNIT
	local cfg = ensureDB(unit)
	local def = defaults[unit] or defaults.player or {}
	local isPlayer = unit == PLAYER_UNIT
	local isTarget = unit == TARGET_UNIT
	local isToT = unit == TARGET_TARGET_UNIT
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
	local function refresh()
		UF.Refresh()
		if cfg.enabled then
			if isToT then
				updateTargetTargetFrame(cfg)
			elseif isTarget and UnitExists and UnitExists(TARGET_UNIT) and states[unit] and states[unit].frame then
				states[unit].barGroup:Show()
				states[unit].status:Show()
			end
		end
	end
	local enableLabel
	if isPlayer then
		enableLabel = L["UFPlayerEnable"] or "Enable custom player frame"
	elseif isTarget then
		enableLabel = L["UFTargetEnable"] or "Enable custom target frame"
	else
		enableLabel = L["UFToTEnable"] or "Enable target-of-target frame"
	end
	local enableCB = addon.functions.createCheckboxAce(enableLabel, cfg.enabled == true, function(_, _, val)
		cfg.enabled = val and true or false
		if isPlayer then
			if cfg.enabled then
				UF.Enable()
			else
				UF.Disable()
			end
		else
			ensureEventHandling()
			if cfg.enabled then
				if isToT then
					updateTargetTargetFrame(cfg)
				else
					applyConfig(unit)
					if isTarget and UnitExists and UnitExists(TARGET_UNIT) and states[unit] and states[unit].frame then
						states[unit].barGroup:Show()
						states[unit].status:Show()
					end
				end
			elseif states[unit] and states[unit].frame then
				states[unit].frame:Hide()
			end
		end
		UF.Refresh()
		if cfg.enabled then
			if isToT then
				updateTargetTargetFrame(cfg)
			elseif isTarget and UnitExists and UnitExists(TARGET_UNIT) and states[unit] and states[unit].frame then
				states[unit].barGroup:Show()
				states[unit].status:Show()
			end
		end
	end)
	enableCB:SetFullWidth(true)
	parent:AddChild(enableCB)

	local sizeRow = addon.functions.createContainer("SimpleGroup", "Flow")
	sizeRow:SetFullWidth(true)
	parent:AddChild(sizeRow)
	local sw = addon.functions.createSliderAce(L["UFWidth"] or "Frame width", cfg.width or def.width, MIN_WIDTH, 800, 1, function(_, _, val)
		cfg.width = max(MIN_WIDTH, val or MIN_WIDTH)
		refresh()
	end)
	sw:SetRelativeWidth(0.5)
	sizeRow:AddChild(sw)
	local shHealth = addon.functions.createSliderAce(L["UFHealthHeight"] or "Health height", cfg.healthHeight or def.healthHeight, 8, 80, 1, function(_, _, val)
		cfg.healthHeight = val
		refresh()
	end)
	shHealth:SetRelativeWidth(0.25)
	sizeRow:AddChild(shHealth)
	local shPower = addon.functions.createSliderAce(L["UFPowerHeight"] or "Power height", cfg.powerHeight or def.powerHeight, 6, 60, 1, function(_, _, val)
		cfg.powerHeight = val
		refresh()
	end)
	shPower:SetRelativeWidth(0.25)
	sizeRow:AddChild(shPower)

	if unit == "target" then
		local auraRow = addon.functions.createContainer("InlineGroup", "Flow")
		auraRow:SetTitle(L["Auras"] or "Auras")
		auraRow:SetFullWidth(true)
		parent:AddChild(auraRow)
		cfg.auraIcons = cfg.auraIcons or {}
		cfg.auraIcons.size = cfg.auraIcons.size or def.auraIcons.size
		cfg.auraIcons.padding = cfg.auraIcons.padding or def.auraIcons.padding
		cfg.auraIcons.max = cfg.auraIcons.max or def.auraIcons.max
		if cfg.auraIcons.showCooldown == nil then cfg.auraIcons.showCooldown = def.auraIcons.showCooldown end

		local sSize = addon.functions.createSliderAce(L["UFHealthHeight"] or "Aura size", cfg.auraIcons.size or 24, 12, 48, 1, function(_, _, val)
			cfg.auraIcons.size = val
			refresh()
		end)
		sSize:SetRelativeWidth(0.5)
		auraRow:AddChild(sSize)

		local sPad = addon.functions.createSliderAce(L["UFBarGap"] or "Aura spacing", cfg.auraIcons.padding or 2, 0, 10, 1, function(_, _, val)
			cfg.auraIcons.padding = val or 0
			refresh()
		end)
		sPad:SetRelativeWidth(0.5)
		auraRow:AddChild(sPad)

		local sMax = addon.functions.createSliderAce(L["UFFrameLevel"] or "Max auras", cfg.auraIcons.max or 16, 4, 40, 1, function(_, _, val)
			cfg.auraIcons.max = val or 16
			refresh()
		end)
		sMax:SetFullWidth(true)
		auraRow:AddChild(sMax)

		local cbCD = addon.functions.createCheckboxAce(L["Show cooldown text"] or "Show cooldown text", cfg.auraIcons.showCooldown ~= false, function(_, _, v)
			cfg.auraIcons.showCooldown = v and true or false
			refresh()
		end)
		cbCD:SetFullWidth(true)
		auraRow:AddChild(cbCD)
	end

	local gapRow = addon.functions.createContainer("SimpleGroup", "Flow")
	gapRow:SetFullWidth(true)
	parent:AddChild(gapRow)
	local gapSlider = addon.functions.createSliderAce(L["UFBarGap"] or "Gap between bars", cfg.barGap or def.barGap or 0, 0, 10, 1, function(_, _, val)
		cfg.barGap = val or 0
		refresh()
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
		refresh()
	end)
	ddStrata:SetRelativeWidth(0.5)
	local defaultStrata = (_G.PlayerFrame and _G.PlayerFrame.GetFrameStrata and _G.PlayerFrame:GetFrameStrata()) or ""
	ddStrata:SetValue(cfg.strata or defaultStrata or "")
	strataRow:AddChild(ddStrata)

	local defaultLevel = (_G.PlayerFrame and _G.PlayerFrame.GetFrameLevel and _G.PlayerFrame:GetFrameLevel()) or 0
	local levelSlider = addon.functions.createSliderAce(L["UFFrameLevel"] or "Frame level", cfg.frameLevel or defaultLevel, 0, 50, 1, function(_, _, val)
		cfg.frameLevel = val
		refresh()
	end)
	levelSlider:SetRelativeWidth(0.5)
	strataRow:AddChild(levelSlider)

	local cbClassColor = addon.functions.createCheckboxAce(L["UFUseClassColor"] or "Use class color (health)", cfg.health.useClassColor == true, function(_, _, val)
		cfg.health.useClassColor = val and true or false
		refresh()
		if UF.ui and UF.ui.healthColorPicker then UF.ui.healthColorPicker:SetDisabled(cfg.health.useClassColor == true) end
	end)
	cbClassColor:SetFullWidth(true)
	parent:AddChild(cbClassColor)

	local colorRow = addon.functions.createContainer("SimpleGroup", "Flow")
	colorRow:SetFullWidth(true)
	parent:AddChild(colorRow)
	UF.ui = UF.ui or {}
	UF.ui.healthColorPicker = addColorPicker(colorRow, L["UFHealthColor"], cfg.health.color or def.health.color, function() refresh() end)
	if UF.ui.healthColorPicker then UF.ui.healthColorPicker:SetDisabled(cfg.health.useClassColor == true) end
	local cbPowerCustom = addon.functions.createCheckboxAce(L["UFPowerColor"], cfg.power.useCustomColor == true, function(_, _, val)
		cfg.power.useCustomColor = val and true or false
		if UF.ui and UF.ui.powerColorPicker then UF.ui.powerColorPicker:SetDisabled(cfg.power.useCustomColor ~= true) end
		if val and not cfg.power.color then cfg.power.color = { getPowerColor(getMainPower()) } end
		refresh()
	end)
	cbPowerCustom:SetRelativeWidth(0.5)
	colorRow:AddChild(cbPowerCustom)

	UF.ui.powerColorPicker = addColorPicker(colorRow, L["UFPowerColor"], cfg.power.color or { getPowerColor(getMainPower()) }, function() refresh() end)
	UF.ui.powerColorPicker:SetRelativeWidth(0.5)
	if UF.ui.powerColorPicker then UF.ui.powerColorPicker:SetDisabled(cfg.power.useCustomColor ~= true) end

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
			refresh()
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
			refresh()
		end)
		dl:SetValue(sec.textLeft or "PERCENT")
		dl:SetRelativeWidth(0.5)
		row:AddChild(dl)

		local dr = addon.functions.createDropdownAce(L["TextRight"] or "Right text", list, order, function(_, _, key)
			sec.textRight = key
			refresh()
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
			refresh()
		end)
		fdd:SetValue(sec.font or "")
		fdd:SetRelativeWidth(0.5)
		fontRow:AddChild(fdd)

		local fs = addon.functions.createSliderAce(L["FontSize"] or "Font size", sec.fontSize or 14, 8, 30, 1, function(_, _, val)
			sec.fontSize = val
			refresh()
		end)
		fs:SetRelativeWidth(0.5)
		fontRow:AddChild(fs)

		local shortRow = addon.functions.createContainer("SimpleGroup", "Flow")
		shortRow:SetFullWidth(true)
		group:AddChild(shortRow)
		local cbShort = addon.functions.createCheckboxAce(L["Use short numbers"] or "Use short numbers", sec.useShortNumbers ~= false, function(_, _, v)
			sec.useShortNumbers = v and true or false
			refresh()
		end)
		cbShort:SetFullWidth(true)
		shortRow:AddChild(cbShort)

		local offsets1 = addon.functions.createContainer("SimpleGroup", "Flow")
		offsets1:SetFullWidth(true)
		group:AddChild(offsets1)

		local leftX = addon.functions.createSliderAce(L["Left X Offset"] or "Left X Offset", (sec.offsetLeft and sec.offsetLeft.x) or 0, -100, 100, 1, function(_, _, val)
			sec.offsetLeft = sec.offsetLeft or {}
			sec.offsetLeft.x = val
			refresh()
		end)
		leftX:SetRelativeWidth(0.25)
		offsets1:AddChild(leftX)

		local leftY = addon.functions.createSliderAce(L["Left Y Offset"] or "Left Y Offset", (sec.offsetLeft and sec.offsetLeft.y) or 0, -100, 100, 1, function(_, _, val)
			sec.offsetLeft = sec.offsetLeft or {}
			sec.offsetLeft.y = val
			refresh()
		end)
		leftY:SetRelativeWidth(0.25)
		offsets1:AddChild(leftY)

		local rightX = addon.functions.createSliderAce(L["Right X Offset"] or "Right X Offset", (sec.offsetRight and sec.offsetRight.x) or 0, -100, 100, 1, function(_, _, val)
			sec.offsetRight = sec.offsetRight or {}
			sec.offsetRight.x = val
			refresh()
		end)
		rightX:SetRelativeWidth(0.25)
		offsets1:AddChild(rightX)

		local rightY = addon.functions.createSliderAce(L["Right Y Offset"] or "Right Y Offset", (sec.offsetRight and sec.offsetRight.y) or 0, -100, 100, 1, function(_, _, val)
			sec.offsetRight = sec.offsetRight or {}
			sec.offsetRight.y = val
			refresh()
		end)
		rightY:SetRelativeWidth(0.25)
		offsets1:AddChild(rightY)

		local bdRow = addon.functions.createContainer("SimpleGroup", "Flow")
		bdRow:SetFullWidth(true)
		group:AddChild(bdRow)
		local cbBd = addon.functions.createCheckboxAce(L["UFBarBackdrop"] or "Show bar backdrop", (sec.backdrop and sec.backdrop.enabled) ~= false, function(_, _, v)
			sec.backdrop = sec.backdrop or {}
			sec.backdrop.enabled = v and true or false
			refresh()
		end)
		cbBd:SetRelativeWidth(0.5)
		bdRow:AddChild(cbBd)
		sec.backdrop = sec.backdrop or {}
		sec.backdrop.color = sec.backdrop.color or { 0, 0, 0, 0.6 }
		local bdColor = addColorPicker(bdRow, L["UFBarBackdropColor"] or "Backdrop color", sec.backdrop.color, function() refresh() end)
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
		refresh()
	end)
	cbBorder:SetFullWidth(true)
	borderGroup:AddChild(cbBorder)
	addColorPicker(borderGroup, L["UFBorderColor"] or "Border color", cfg.border.color or def.border.color, function() refresh() end)
	local edge = addon.functions.createSliderAce(L["UFBorderThickness"] or "Border size", cfg.border.edgeSize or def.border.edgeSize, 0, 8, 0.5, function(_, _, val)
		cfg.border.edgeSize = val
		refresh()
	end)
	edge:SetFullWidth(true)
	borderGroup:AddChild(edge)

	local statusGroup = addon.functions.createContainer("InlineGroup", "Flow")
	statusGroup:SetTitle(L["UFStatusLine"] or "Status line")
	statusGroup:SetFullWidth(true)
	parent:AddChild(statusGroup)

	local cbStatus = addon.functions.createCheckboxAce(L["UFStatusEnable"] or "Show status line", cfg.status.enabled ~= false, function(_, _, v)
		cfg.status.enabled = v and true or false
		refresh()
	end)
	cbStatus:SetFullWidth(true)
	statusGroup:AddChild(cbStatus)

	local cbLevel = addon.functions.createCheckboxAce(L["UFShowLevel"] or "Show level", cfg.status.levelEnabled ~= false, function(_, _, v)
		cfg.status.levelEnabled = v and true or false
		refresh()
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
			refresh()
			if UF.ui and UF.ui.nameColorPicker then UF.ui.nameColorPicker:SetDisabled(key == "CLASS") end
		end
	)
	nameColorMode:SetValue(cfg.status.nameColorMode or "CLASS")
	nameColorMode:SetRelativeWidth(0.33)
	colorRowStatus:AddChild(nameColorMode)
	UF.ui = UF.ui or {}
	UF.ui.nameColorPicker = addColorPicker(colorRowStatus, L["UFNameColor"] or "Name color", cfg.status.nameColor or def.status.nameColor, function() refresh() end)
	if UF.ui.nameColorPicker then UF.ui.nameColorPicker:SetDisabled((cfg.status.nameColorMode or "CLASS") == "CLASS") end
	addColorPicker(colorRowStatus, L["UFLevelColor"] or "Level color", cfg.status.levelColor or def.status.levelColor, function() refresh() end)

	local sFont = addon.functions.createSliderAce(L["FontSize"] or "Font size", cfg.status.fontSize or 14, 8, 30, 1, function(_, _, val)
		cfg.status.fontSize = val
		refresh()
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
		refresh()
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
		refresh()
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
		refresh()
	end)
	nameAnchor:SetRelativeWidth(0.25)
	nameAnchor:SetValue(cfg.status.nameAnchor or "LEFT")
	statusOffsets:AddChild(nameAnchor)

	local nameX = addon.functions.createSliderAce(L["UFNameX"] or "Name X offset", (cfg.status.nameOffset and cfg.status.nameOffset.x) or 0, -200, 200, 1, function(_, _, val)
		cfg.status.nameOffset = cfg.status.nameOffset or {}
		cfg.status.nameOffset.x = val
		refresh()
	end)
	nameX:SetRelativeWidth(0.25)
	statusOffsets:AddChild(nameX)
	local nameY = addon.functions.createSliderAce(L["UFNameY"] or "Name Y offset", (cfg.status.nameOffset and cfg.status.nameOffset.y) or 0, -200, 200, 1, function(_, _, val)
		cfg.status.nameOffset = cfg.status.nameOffset or {}
		cfg.status.nameOffset.y = val
		refresh()
	end)
	nameY:SetRelativeWidth(0.25)
	statusOffsets:AddChild(nameY)

	local levelAnchor = addon.functions.createDropdownAce(L["UFLevelAnchor"] or "Level anchor", anchorList, anchorOrder, function(_, _, key)
		cfg.status.levelAnchor = key
		refresh()
	end)
	levelAnchor:SetRelativeWidth(0.25)
	levelAnchor:SetValue(cfg.status.levelAnchor or "RIGHT")
	statusOffsets:AddChild(levelAnchor)

	local lvlX = addon.functions.createSliderAce(L["UFLevelX"] or "Level X offset", (cfg.status.levelOffset and cfg.status.levelOffset.x) or 0, -200, 200, 1, function(_, _, val)
		cfg.status.levelOffset = cfg.status.levelOffset or {}
		cfg.status.levelOffset.x = val
		refresh()
	end)
	lvlX:SetRelativeWidth(0.25)
	statusOffsets:AddChild(lvlX)
	local lvlY = addon.functions.createSliderAce(L["UFLevelY"] or "Level Y offset", (cfg.status.levelOffset and cfg.status.levelOffset.y) or 0, -200, 200, 1, function(_, _, val)
		cfg.status.levelOffset = cfg.status.levelOffset or {}
		cfg.status.levelOffset.y = val
		refresh()
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
		local playerCfg = ensureDB("player")
		local targetCfg = ensureDB("target")
		local totCfg = ensureDB(TARGET_TARGET_UNIT)
		local cbPlayer = addon.functions.createCheckboxAce(L["UFPlayerEnable"] or "Enable custom player frame", playerCfg.enabled == true, function(_, _, val)
			playerCfg.enabled = val and true or false
			if playerCfg.enabled then
				ensureRootNode()
				addTreeNode("ufplus\001player", { value = "player", text = L["UFPlayerFrame"] or PLAYER }, "ufplus")
				UF.Enable()
			else
				UF.Disable()
			end
		end)
		cbPlayer:SetFullWidth(true)
		container:AddChild(cbPlayer)

		local cbTarget = addon.functions.createCheckboxAce(L["UFTargetEnable"] or "Enable custom target frame", targetCfg.enabled == true, function(_, _, val)
			targetCfg.enabled = val and true or false
			if targetCfg.enabled then
				ensureRootNode()
				addTreeNode("ufplus\001target", { value = "target", text = L["UFTargetFrame"] or TARGET }, "ufplus")
				ensureEventHandling()
				applyConfig("target")
			end
		end)
		cbTarget:SetFullWidth(true)
		container:AddChild(cbTarget)

		local cbToT = addon.functions.createCheckboxAce(L["UFToTEnable"] or "Enable target-of-target frame", totCfg.enabled == true, function(_, _, val)
			totCfg.enabled = val and true or false
			if totCfg.enabled then
				ensureRootNode()
				addTreeNode("ufplus\001targettarget", { value = "targettarget", text = L["UFToTFrame"] or "Target of Target" }, "ufplus")
				ensureEventHandling()
				applyConfig(TARGET_TARGET_UNIT)
				updateTargetTargetFrame(totCfg)
			elseif states[TARGET_TARGET_UNIT] and states[TARGET_TARGET_UNIT].frame then
				states[TARGET_TARGET_UNIT].frame:Hide()
			end
		end)
		cbToT:SetFullWidth(true)
		container:AddChild(cbToT)
	end)
	addon.functions.RegisterOptionsPage("ufplus\001player", function(container) addOptions(container, false, "player") end)
	addon.functions.RegisterOptionsPage("ufplus\001target", function(container) addOptions(container, false, "target") end)
	addon.functions.RegisterOptionsPage("ufplus\001targettarget", function(container) addOptions(container, false, TARGET_TARGET_UNIT) end)
	ensureRootNode()
	addTreeNode("ufplus\001player", { value = "player", text = L["UFPlayerFrame"] or PLAYER }, "ufplus")
	addTreeNode("ufplus\001target", { value = "target", text = L["UFTargetFrame"] or TARGET }, "ufplus")
	addTreeNode("ufplus\001targettarget", { value = "targettarget", text = L["UFToTFrame"] or "Target of Target" }, "ufplus")
end

function UF.treeCallback(container, group)
	if not container then return end
	container:ReleaseChildren()
	if group == "ufplus" then
		if addon.functions and addon.functions.ShowOptionsPage then addon.functions.ShowOptionsPage(container, "ufplus") end
	elseif group == "ufplus\001player" then
		addOptions(container, false, "player")
	elseif group == "ufplus\001target" then
		addOptions(container, false, "target")
	elseif group == "ufplus\001targettarget" then
		addOptions(container, false, TARGET_TARGET_UNIT)
	end
end

-- Auto-enable on load when configured
if not addon.Aura.UFInitialized then
	addon.Aura.UFInitialized = true
	ensureRootNode()
	addTreeNode("ufplus\001player", { value = "player", text = L["UFPlayerFrame"] or PLAYER }, "ufplus")
	addTreeNode("ufplus\001target", { value = "target", text = L["UFTargetFrame"] or TARGET }, "ufplus")
	addTreeNode("ufplus\001targettarget", { value = "targettarget", text = L["UFToTFrame"] or "Target of Target" }, "ufplus")
	local cfg = ensureDB("player")
	if cfg.enabled then After(0.1, function() UF.Enable() end) end
	local tc = ensureDB("target")
	if tc.enabled then
		ensureEventHandling()
		applyConfig("target")
		hideBlizzardTargetFrame()
	end
	local ttc = ensureDB(TARGET_TARGET_UNIT)
	if ttc.enabled then
		ensureEventHandling()
		applyConfig(TARGET_TARGET_UNIT)
		updateTargetTargetFrame(ttc)
	end
end

UF.targetAuras = targetAuras
UF.defaults = defaults
UF.GetDefaults = function(unit) return defaults[unit] or defaults.player end
UF.EnsureDB = ensureDB
UF.GetConfig = ensureDB
UF.EnsureFrames = ensureFrames
return UF
