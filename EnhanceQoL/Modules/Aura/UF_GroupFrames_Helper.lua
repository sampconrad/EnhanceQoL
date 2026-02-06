local parentAddonName = "EnhanceQoL"
local addon = _G[parentAddonName]
if not addon then return end

addon.Aura = addon.Aura or {}
addon.Aura.UF = addon.Aura.UF or {}
local UF = addon.Aura.UF
UF.GroupFramesHelper = UF.GroupFramesHelper or {}
local H = UF.GroupFramesHelper

H.COLOR_WHITE = { 1, 1, 1, 1 }
H.COLOR_WHITE_90 = { 1, 1, 1, 0.9 }
H.COLOR_BLACK = { 0, 0, 0, 1 }
H.COLOR_LEVEL = { 1, 0.85, 0, 1 }
H.COLOR_HEALTH_DEFAULT = { 0, 0.8, 0, 1 }
H.COLOR_YELLOW = { 1, 1, 0, 1 }

H.GROUP_ORDER = "1,2,3,4,5,6,7,8"
H.ROLE_TOKENS = { "TANK", "HEALER", "DAMAGER" }
H.ROLE_TOKENS_CORE = { "TANK", "HEALER" }
H.ROLE_ORDER = table.concat(H.ROLE_TOKENS, ",")
H.ROLE_LABELS = {
	TANK = TANK or "Tank",
	HEALER = HEALER or "Healer",
	DAMAGER = DAMAGER or "DPS",
	MELEE = "Melee DPS",
	RANGED = "Ranged DPS",
}
H.ROLE_COLORS = {
	TANK = { 0.2, 0.6, 1.0 },
	HEALER = { 0.2, 1.0, 0.4 },
	DAMAGER = { 1.0, 0.2, 0.2 },
	MELEE = { 0.82, 0.65, 0.47 },
	RANGED = { 0.6, 0.6, 1.0 },
}
H.CUSTOM_SORT_ROW_HEIGHT = 22
H.CUSTOM_SORT_ROW_WIDTH = 170
H.CUSTOM_SORT_EDITOR_SIZE = { w = 420, h = 520 }
H.CLASS_TOKENS = {
	"DEATHKNIGHT",
	"DEMONHUNTER",
	"DRUID",
	"EVOKER",
	"HUNTER",
	"MAGE",
	"MONK",
	"PALADIN",
	"PRIEST",
	"ROGUE",
	"SHAMAN",
	"WARLOCK",
	"WARRIOR",
}
H.CLASS_ORDER = table.concat(H.CLASS_TOKENS, ",")
H.PREVIEW_SAMPLES = {
	party = {
		{ name = "Tank", class = "WARRIOR", role = "TANK", group = 1 },
		{ name = "Healer", class = "PRIEST", role = "HEALER", group = 1 },
		{ name = "DPS", class = "MAGE", role = "DAMAGER", group = 1 },
		{ name = "DPS", class = "HUNTER", role = "DAMAGER", group = 1 },
		{ name = "DPS", class = "ROGUE", role = "DAMAGER", group = 1 },
	},
	raid = nil,
}

H.GROUP_NUMBER_FORMAT_OPTIONS = {
	{ value = "GROUP", label = "Group 1", text = "Group 1" },
	{ value = "G", label = "G1", text = "G1" },
	{ value = "G_SPACE", label = "G 1", text = "G 1" },
	{ value = "NUMBER", label = "1", text = "1" },
	{ value = "PARENS", label = "(1)", text = "(1)" },
	{ value = "BRACKETS", label = "[1]", text = "[1]" },
	{ value = "BRACES", label = "{1}", text = "{1}" },
	{ value = "ANGLE", label = "<1>", text = "<1>" },
	{ value = "PIPE", label = "|| 1 ||", text = "|| 1 ||" },
	{ value = "HASH", label = "#1", text = "#1" },
}

function H.FormatGroupNumber(subgroup, format)
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

function H.GetUnitSubgroup(unit)
	if not (unit and UnitInRaid and GetRaidRosterInfo) then return nil end
	local idx = UnitInRaid(unit)
	if not idx then return nil end
	local _, _, raidSubgroup = GetRaidRosterInfo(idx)
	if issecretvalue and issecretvalue(raidSubgroup) then return nil end
	return raidSubgroup
end

H.MELEE_SPECS = {
	-- Death Knight (all melee)
	[250] = true,
	[251] = true,
	[252] = true,
	-- Demon Hunter (all melee)
	[577] = true,
	[581] = true,
	-- Druid (Feral, Guardian)
	[103] = true,
	[104] = true,
	-- Evoker (Augmentation is melee-range)
	[1473] = true,
	-- Hunter (Survival)
	[255] = true,
	-- Monk (Brewmaster, Windwalker)
	[268] = true,
	[269] = true,
	-- Paladin (Protection, Retribution)
	[66] = true,
	[70] = true,
	-- Rogue (all melee)
	[259] = true,
	[260] = true,
	[261] = true,
	-- Shaman (Enhancement)
	[263] = true,
	-- Warrior (all melee)
	[71] = true,
	[72] = true,
	[73] = true,
}

H.MELEE_DPS_CLASSES = {
	WARRIOR = true,
	ROGUE = true,
	DEATHKNIGHT = true,
	DEMONHUNTER = true,
	MONK = true,
	PALADIN = true,
}

H.RANGED_DPS_CLASSES = {
	MAGE = true,
	WARLOCK = true,
	PRIEST = true,
	EVOKER = true,
}

local UnitSex = UnitSex
local GetNumClasses = GetNumClasses
local GetClassInfo = GetClassInfo
local GetSpecializationInfo = GetSpecializationInfo
local GetNumSpecializations = GetNumSpecializations
local GetSpecializationInfoForClassID = GetSpecializationInfoForClassID
local GetNumSpecializationsForClassID = GetNumSpecializationsForClassID
local GetInspectSpecialization = GetInspectSpecialization
local NotifyInspect = NotifyInspect
local ClearInspectPlayer = ClearInspectPlayer
local C_SpecializationInfo = C_SpecializationInfo
local C_CreatureInfo = C_CreatureInfo
local floor = math.floor
local UnitIsUnit = UnitIsUnit
local UnitExists = UnitExists
local UnitIsPlayer = UnitIsPlayer
local UnitGUID = UnitGUID
local InCombatLockdown = InCombatLockdown
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local GetNumGroupMembers = GetNumGroupMembers
local C_Timer = C_Timer
local strlower = string.lower
local CreateFrame = CreateFrame
local UIParent = UIParent
local LOCALIZED_CLASS_NAMES_MALE = LOCALIZED_CLASS_NAMES_MALE

function H.GetEffectiveScale(frame)
	if frame and frame.GetEffectiveScale then
		local scale = frame:GetEffectiveScale()
		if scale and scale > 0 then return scale end
	end
	local ui = UIParent
	if ui and ui.GetEffectiveScale then
		local scale = ui:GetEffectiveScale()
		if scale and scale > 0 then return scale end
	end
	return 1
end

function H.RoundToPixel(value, scale)
	value = tonumber(value) or 0
	scale = scale or 1
	if scale <= 0 then return value end
	return (math.floor((value * scale) + 0.5) / scale)
end

function H.LayoutTexts(bar, leftFS, centerFS, rightFS, cfg, scale)
	if not bar then return end
	local leftCfg = (cfg and cfg.offsetLeft) or { x = 6, y = 0 }
	local centerCfg = (cfg and cfg.offsetCenter) or { x = 0, y = 0 }
	local rightCfg = (cfg and cfg.offsetRight) or { x = -6, y = 0 }
	local lx = H.RoundToPixel(leftCfg.x or 0, scale)
	local ly = H.RoundToPixel(leftCfg.y or 0, scale)
	local cx = H.RoundToPixel(centerCfg.x or 0, scale)
	local cy = H.RoundToPixel(centerCfg.y or 0, scale)
	local rx = H.RoundToPixel(rightCfg.x or 0, scale)
	local ry = H.RoundToPixel(rightCfg.y or 0, scale)
	if leftFS then
		leftFS:ClearAllPoints()
		leftFS:SetPoint("LEFT", bar, "LEFT", lx, ly)
		leftFS:SetJustifyH("LEFT")
	end
	if centerFS then
		centerFS:ClearAllPoints()
		centerFS:SetPoint("CENTER", bar, "CENTER", cx, cy)
		centerFS:SetJustifyH("CENTER")
	end
	if rightFS then
		rightFS:ClearAllPoints()
		rightFS:SetPoint("RIGHT", bar, "RIGHT", rx, ry)
		rightFS:SetJustifyH("RIGHT")
	end
end

local OUTER_ANCHOR_MAP = {
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

function H.GetOuterAnchorPoint(anchor)
	local a = (anchor or "CENTER"):upper()
	local point = OUTER_ANCHOR_MAP[a] or "CENTER"
	return point, a
end

function H.GetGrowthStartPoint(growth)
	local g = (growth or "DOWN"):upper()
	if g == "LEFT" then return "TOPRIGHT" end
	if g == "UP" then return "BOTTOMLEFT" end
	return "TOPLEFT"
end

function H.SetPointFromCfg(frame, cfg)
	if not frame or not cfg then return end
	frame:ClearAllPoints()
	local rel = cfg.relativeTo and _G[cfg.relativeTo] or UIParent
	local p = cfg.point or "CENTER"
	local rp = cfg.relativePoint or p
	local scale = H.GetEffectiveScale(rel)
	local x = H.RoundToPixel(tonumber(cfg.x) or 0, scale)
	local y = H.RoundToPixel(tonumber(cfg.y) or 0, scale)
	frame:SetPoint(p, rel, rp, x, y)
end
local LOCALIZED_CLASS_NAMES_FEMALE = LOCALIZED_CLASS_NAMES_FEMALE
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

local function trim(value)
	if value == nil then return "" end
	return tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalizeToken(token, upper)
	local t = trim(token)
	if t == "" then return nil end
	if upper then t = t:upper() end
	local num = tonumber(t)
	if num then return num end
	return t
end

local function fillTableFromCsv(tbl, csv, upper)
	if type(csv) ~= "string" then return end
	for token in csv:gmatch("[^,]+") do
		local key = normalizeToken(token, upper)
		if key ~= nil then tbl[key] = true end
	end
end

local function buildOrderMap(order)
	local map = {}
	if type(order) ~= "string" then return map end
	local idx = 0
	for token in order:gmatch("[^,]+") do
		local key = normalizeToken(token, true)
		if key ~= nil then
			idx = idx + 1
			map[key] = idx
		end
	end
	return map
end

local function normalizeGroupBy(value)
	local v = trim(value):upper()
	if v == "" then return nil end
	if v == "ROLE" then v = "ASSIGNEDROLE" end
	if v == "GROUP" or v == "CLASS" or v == "ASSIGNEDROLE" then return v end
	return nil
end

function H.NormalizeSortMethod(value)
	local v = trim(value):upper()
	if v == "NAME" then return "NAME" end
	if v == "NAMELIST" then return "NAMELIST" end
	return "INDEX"
end

function H.NormalizeSortDir(value)
	local v = trim(value):upper()
	if v == "DESC" then return "DESC" end
	return "ASC"
end

function H.IsBetterSortKey(key, currentKey, sortDir)
	if currentKey == nil then return true end
	if sortDir == "DESC" then return key > currentKey end
	return key < currentKey
end

function H.ParseCsvSet(value, upper)
	local set = {}
	if type(value) ~= "string" then return set end
	for token in value:gmatch("[^,]+") do
		local key = normalizeToken(token, upper == true)
		if key ~= nil then set[key] = true end
	end
	return set
end

function H.BuildCsvFromSet(set, order)
	if type(set) ~= "table" then return nil end
	local list = {}
	if type(order) == "table" then
		for _, token in ipairs(order) do
			if set[token] then list[#list + 1] = tostring(token) end
		end
	else
		for token in pairs(set) do
			if set[token] then list[#list + 1] = tostring(token) end
		end
		table.sort(list, function(a, b) return tostring(a) < tostring(b) end)
	end
	if #list == 0 then return nil end
	return table.concat(list, ",")
end

function H.IsSetFull(set, order)
	if type(set) ~= "table" or type(order) ~= "table" then return false end
	for _, token in ipairs(order) do
		if not set[token] then return false end
	end
	return true
end

function H.GetLocalizedClassName(token)
	if not token then return "" end
	if LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token] then return LOCALIZED_CLASS_NAMES_MALE[token] end
	if LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[token] then return LOCALIZED_CLASS_NAMES_FEMALE[token] end
	return token
end

function H.GetClassColor(token)
	local color = RAID_CLASS_COLORS and token and RAID_CLASS_COLORS[token]
	if not color then return nil end
	return { color.r, color.g, color.b }
end

function H.CreateCustomSortEditor(opts)
	opts = opts or {}
	local roleTokens = opts.roleTokens or H.ROLE_TOKENS or {}
	local classTokens = opts.classTokens or H.CLASS_TOKENS or {}
	local roleLabels = opts.roleLabels or H.ROLE_LABELS or {}
	local roleColors = opts.roleColors or H.ROLE_COLORS or {}
	local rowHeight = opts.rowHeight or H.CUSTOM_SORT_ROW_HEIGHT or 22
	local rowWidth = opts.rowWidth or H.CUSTOM_SORT_ROW_WIDTH or 170
	local size = opts.size or H.CUSTOM_SORT_EDITOR_SIZE or { w = 420, h = 520 }
	local getOrders = opts.getOrders
	local onReorder = opts.onReorder
	local getClassLabel = opts.getClassLabel or H.GetLocalizedClassName
	local getClassColor = opts.getClassColor or H.GetClassColor
	local titleText = opts.title or "Custom Sort Order"
	local subtitleText = opts.subtitle or "Drag entries to reorder. Applies to Raid custom sorting."

	local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	frame:SetSize(size.w or 420, size.h or 520)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 24,
		insets = { left = 6, right = 6, top = 6, bottom = 6 },
	})
	frame:SetBackdropColor(0, 0, 0, 1)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetFrameStrata("TOOLTIP")
	frame:SetClampedToScreen(true)
	frame:SetPoint("CENTER")
	frame:Hide()

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(titleText)
	frame.Title = title

	local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	subtitle:SetText(subtitleText)
	frame.Subtitle = subtitle

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)
	close:SetScript("OnClick", function() frame:Hide() end)
	frame.CloseButton = close

	local roleHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	roleHeader:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
	roleHeader:SetText("Role Priority")
	frame.RoleHeader = roleHeader

	local roleContainer = CreateFrame("Frame", nil, frame)
	roleContainer:SetPoint("TOPLEFT", roleHeader, "BOTTOMLEFT", 0, -6)
	roleContainer:SetSize(rowWidth, rowHeight * #roleTokens)
	frame.RoleContainer = roleContainer

	local classHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	classHeader:SetPoint("TOPLEFT", roleContainer, "BOTTOMLEFT", 0, -16)
	classHeader:SetText("Class Priority")
	frame.ClassHeader = classHeader

	local classContainer = CreateFrame("Frame", nil, frame)
	classContainer:SetPoint("TOPLEFT", classHeader, "BOTTOMLEFT", 0, -6)
	classContainer:SetSize(rowWidth, rowHeight * #classTokens)
	frame.ClassContainer = classContainer

	frame.roleRows = {}
	frame.classRows = {}
	frame._dragList = nil
	frame._dragIndex = nil

	local function createRow(parent)
		local row = CreateFrame("Button", nil, parent, "UIMenuButtonStretchTemplate")
		row:SetSize(rowWidth, rowHeight)
		row:RegisterForDrag("LeftButton")
		row.Highlight = row:GetHighlightTexture()
		if row.Highlight then row.Highlight:SetAlpha(0.2) end
		row.Label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.Label:SetPoint("LEFT", 6, 0)
		row.Label:SetJustifyH("LEFT")
		row.Label:SetWidth(rowWidth - 12)
		return row
	end

	local function setRowColor(row, color)
		if not row or not row.Label then return end
		if color then
			row.Label:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1)
		else
			row.Label:SetTextColor(1, 1, 1)
		end
	end

	local function reorderList(list, from, to)
		if not list or from == to then return end
		local item = table.remove(list, from)
		if item == nil then return end
		table.insert(list, to, item)
	end

	function frame:RefreshList(listKey, container, rows, order, labelFunc, colorFunc)
		local count = #order
		for i = 1, count do
			local row = rows[i]
			if not row then
				row = createRow(container)
				rows[i] = row
				row:SetScript("OnDragStart", function(self)
					frame._dragList = self._listKey
					frame._dragIndex = self._index
					self:SetAlpha(0.6)
				end)
				row:SetScript("OnDragStop", function(self)
					self:SetAlpha(1)
					if frame._dragList ~= self._listKey then
						frame._dragList = nil
						frame._dragIndex = nil
						return
					end
					local dropIndex
					for idx, candidate in ipairs(rows) do
						if candidate:IsShown() and candidate:IsMouseOver() then
							dropIndex = idx
							break
						end
					end
					local dragIndex = frame._dragIndex
					frame._dragList = nil
					frame._dragIndex = nil
					if not dropIndex or not dragIndex or dropIndex == dragIndex then return end
					reorderList(order, dragIndex, dropIndex)
					if onReorder then onReorder(listKey, order) end
					frame:Refresh()
				end)
				row:SetScript("OnEnter", function(self)
					if frame._dragList == self._listKey and self.Highlight then
						self.Highlight:SetAlpha(0.35)
						self.Highlight:Show()
					end
				end)
				row:SetScript("OnLeave", function(self)
					if self.Highlight then
						self.Highlight:SetAlpha(0.2)
						self.Highlight:Hide()
					end
				end)
			end
			row._listKey = listKey
			row._index = i
			row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -((i - 1) * (rowHeight + 2)))
			local token = order[i]
			row.Label:SetText(labelFunc(token))
			setRowColor(row, colorFunc(token))
			row:Show()
		end
		for i = count + 1, #rows do
			rows[i]:Hide()
		end
	end

	function frame:Refresh()
		local roleOrder, classOrder = nil, nil
		if getOrders then
			roleOrder, classOrder = getOrders()
		end
		roleOrder = H.NormalizeOrderList(roleOrder, nil)
		if #roleOrder == 0 then roleOrder = H.NormalizeOrderList(nil, roleTokens) end
		classOrder = H.NormalizeOrderList(classOrder, nil)
		if #classOrder == 0 then classOrder = H.NormalizeOrderList(nil, classTokens) end
		if self.RoleContainer then self.RoleContainer:SetSize(rowWidth, rowHeight * #roleOrder) end
		if self.ClassContainer then self.ClassContainer:SetSize(rowWidth, rowHeight * #classOrder) end
		self.roleOrder = roleOrder
		self.classOrder = classOrder
		self:RefreshList("role", self.RoleContainer, self.roleRows, roleOrder, function(token) return roleLabels[token] or token or "" end, function(token) return roleColors[token] end)
		self:RefreshList("class", self.ClassContainer, self.classRows, classOrder, function(token) return getClassLabel(token) end, function(token) return getClassColor(token) end)
	end

	return frame
end

function H.NormalizeOrderList(list, fallback)
	local out = {}
	local seen = {}
	if type(list) == "table" then
		for _, token in ipairs(list) do
			if token ~= nil and not seen[token] then
				seen[token] = true
				out[#out + 1] = token
			end
		end
	end
	if type(fallback) == "table" then
		for _, token in ipairs(fallback) do
			if token ~= nil and not seen[token] then
				seen[token] = true
				out[#out + 1] = token
			end
		end
	end
	return out
end

function H.ExpandRoleOrder(roleOrder, separateMeleeRanged, meleeBeforeRanged)
	local fallback = separateMeleeRanged and H.ROLE_TOKENS_CORE or H.ROLE_TOKENS
	local order = H.NormalizeOrderList(roleOrder, fallback)
	if not separateMeleeRanged then return order end

	local expanded = {}
	local hasMelee = false
	local hasRanged = false
	local meleeFirst = (meleeBeforeRanged ~= false)
	for _, role in ipairs(order) do
		if role == "MELEE" then
			hasMelee = true
			expanded[#expanded + 1] = role
		elseif role == "RANGED" then
			hasRanged = true
			expanded[#expanded + 1] = role
		elseif role == "DAMAGER" then
			if meleeFirst then
				expanded[#expanded + 1] = "MELEE"
				expanded[#expanded + 1] = "RANGED"
			else
				expanded[#expanded + 1] = "RANGED"
				expanded[#expanded + 1] = "MELEE"
			end
		else
			expanded[#expanded + 1] = role
		end
	end
	if not hasMelee and not hasRanged then
		if meleeFirst then
			expanded[#expanded + 1] = "MELEE"
			expanded[#expanded + 1] = "RANGED"
		else
			expanded[#expanded + 1] = "RANGED"
			expanded[#expanded + 1] = "MELEE"
		end
	elseif not hasMelee then
		expanded[#expanded + 1] = "MELEE"
	elseif not hasRanged then
		expanded[#expanded + 1] = "RANGED"
	end
	return expanded
end

function H.CollapseRoleOrder(roleOrder)
	local order = H.NormalizeOrderList(roleOrder, H.ROLE_TOKENS)
	local collapsed = {}
	local seen = {}
	local insertedDamager = false
	for _, role in ipairs(order) do
		local token = role
		if token == "MELEE" or token == "RANGED" then
			if not insertedDamager then
				token = "DAMAGER"
				insertedDamager = true
			else
				token = nil
			end
		end
		if token and not seen[token] then
			seen[token] = true
			collapsed[#collapsed + 1] = token
		end
	end
	if not seen.DAMAGER then collapsed[#collapsed + 1] = "DAMAGER" end
	return H.NormalizeOrderList(collapsed, H.ROLE_TOKENS)
end

function H.BuildOrderMapFromList(list)
	local map = {}
	if type(list) ~= "table" then return map end
	for i, token in ipairs(list) do
		if token ~= nil and map[token] == nil then map[token] = i end
	end
	return map
end

function H.EnsureCustomSortConfig(cfg)
	if not cfg then return nil end
	cfg.customSort = cfg.customSort or {}
	local custom = cfg.customSort
	if custom.enabled == nil then custom.enabled = false end
	if custom.separateMeleeRanged == nil then custom.separateMeleeRanged = false end
	if custom.separateMeleeRanged == true then
		custom.roleOrder = H.ExpandRoleOrder(custom.roleOrder, true)
	else
		custom.roleOrder = H.CollapseRoleOrder(custom.roleOrder)
	end
	custom.classOrder = H.NormalizeOrderList(custom.classOrder, H.CLASS_TOKENS)
	return custom
end

function H.GetUnitSpecId(unit)
	if not unit then return nil end
	if UnitIsUnit and UnitIsUnit(unit, "player") then
		local specIndex = GetSpecialization and GetSpecialization()
		if specIndex and GetSpecializationInfo then
			local specId = GetSpecializationInfo(specIndex)
			if specId and specId > 0 then return specId end
		end
	end
	if GetInspectSpecialization then
		local specId = GetInspectSpecialization(unit)
		if specId and specId > 0 then return specId end
	end
	return nil
end

H.specCache = H.specCache or {}
H.inspectQueue = H.inspectQueue or {}
H.inspectInProgress = H.inspectInProgress or false
H.inspectUnit = H.inspectUnit or nil
H.inspectGuid = H.inspectGuid or nil

function H.CacheUnitSpec(unit, specId)
	if not unit or not specId or specId <= 0 then return false end
	local name = H.GetUnitFullName(unit)
	if not name or name == "" then return false end
	H.specCache[name] = specId
	return true
end

function H.GetCachedSpecId(unit)
	local name = H.GetUnitFullName(unit)
	if not name or name == "" then return nil end
	return H.specCache[name]
end

function H.GetUnitSpecIdCached(unit)
	local cached = H.GetCachedSpecId(unit)
	if cached and cached > 0 then return cached end
	local specId = H.GetUnitSpecId(unit)
	if specId and specId > 0 then
		H.CacheUnitSpec(unit, specId)
		return specId
	end
	return nil
end

function H.QueueInspect(unit)
	if not (UnitExists and UnitExists(unit)) then return end
	if UnitIsPlayer and not UnitIsPlayer(unit) then return end
	if UnitIsUnit and UnitIsUnit(unit, "player") then return end
	if InCombatLockdown and InCombatLockdown() then return end
	local name = H.GetUnitFullName(unit)
	if name and H.specCache[name] then return end
	local guid = UnitGUID and UnitGUID(unit)
	if not guid or guid == "" then return end
	if H.inspectQueue[guid] then return end
	H.inspectQueue[guid] = unit
	H.ProcessInspectQueue()
end

function H.ProcessInspectQueue()
	if H.inspectInProgress then return end
	if InCombatLockdown and InCombatLockdown() then return end
	local guid, unit = next(H.inspectQueue)
	if not guid then return end
	if not (UnitExists and UnitExists(unit)) then
		H.inspectQueue[guid] = nil
		if C_Timer and C_Timer.After then C_Timer.After(0.1, function() H.ProcessInspectQueue() end) end
		return
	end
	local unitGuid = UnitGUID and UnitGUID(unit)
	if unitGuid and unitGuid ~= guid then
		H.inspectQueue[guid] = nil
		if C_Timer and C_Timer.After then C_Timer.After(0.1, function() H.ProcessInspectQueue() end) end
		return
	end
	if InspectFrame and InspectFrame.IsShown and InspectFrame:IsShown() then
		if C_Timer and C_Timer.After then C_Timer.After(2, function() H.ProcessInspectQueue() end) end
		return
	end
	H.inspectInProgress = true
	H.inspectGuid = guid
	H.inspectUnit = unit
	if NotifyInspect then NotifyInspect(unit) end
end

function H.OnInspectReady(guid)
	if not H.inspectInProgress then return false end
	local issecret = _G.issecretvalue
	local guidSecret = issecret and issecret(guid)
	local restricted = addon and addon.functions and addon.functions.isRestrictedContent and addon.functions.isRestrictedContent(true) == true
	local unit
	if restricted or guidSecret then
		unit = H.inspectUnit
	else
		if H.inspectGuid and guid == H.inspectGuid then
			unit = H.inspectUnit
		elseif guid and H.inspectQueue[guid] then
			unit = H.inspectQueue[guid]
		end
	end
	if not unit or not (UnitExists and UnitExists(unit)) then
		H.inspectInProgress = false
		H.inspectGuid = nil
		H.inspectUnit = nil
		return false
	end
	local specId = GetInspectSpecialization and GetInspectSpecialization(unit)
	local updated = false
	if specId and specId > 0 then updated = H.CacheUnitSpec(unit, specId) end
	if H.inspectGuid then H.inspectQueue[H.inspectGuid] = nil end
	if guid and H.inspectQueue[guid] then H.inspectQueue[guid] = nil end
	H.inspectInProgress = false
	H.inspectGuid = nil
	H.inspectUnit = nil
	if ClearInspectPlayer then ClearInspectPlayer() end
	if C_Timer and C_Timer.After then C_Timer.After(0.5, function() H.ProcessInspectQueue() end) end
	return updated
end

function H.QueueInspectGroup()
	if InCombatLockdown and InCombatLockdown() then return end
	local playerSpec = GetSpecialization and GetSpecialization()
	if playerSpec and GetSpecializationInfo then
		local specId = GetSpecializationInfo(playerSpec)
		if specId and specId > 0 then H.CacheUnitSpec("player", specId) end
	end
	if IsInRaid and IsInRaid() then
		local total = GetNumGroupMembers and GetNumGroupMembers() or 0
		for i = 1, total do
			local unit = "raid" .. i
			if UnitExists and UnitExists(unit) then H.QueueInspect(unit) end
		end
	elseif IsInGroup and IsInGroup() then
		for i = 1, 4 do
			local unit = "party" .. i
			if UnitExists and UnitExists(unit) then H.QueueInspect(unit) end
		end
	end
end

function H.GetDpsRangeRole(specId, classToken)
	if specId and H.MELEE_SPECS[specId] then return "MELEE" end
	if specId and specId > 0 then return "RANGED" end
	if classToken and H.MELEE_DPS_CLASSES[classToken] then return "MELEE" end
	if classToken and H.RANGED_DPS_CLASSES[classToken] then return "RANGED" end
	return "RANGED"
end

function H.GetUnitFullName(unit)
	if not unit or not UnitName then return nil end
	local name, realm = UnitName(unit)
	if not name or name == "" then return nil end
	if realm and realm ~= "" then return name .. "-" .. realm end
	return name
end

function H.BuildCustomSortNameList(cfg)
	local custom = H.EnsureCustomSortConfig(cfg)
	if not (custom and custom.enabled == true) then return "" end

	local separate = custom.separateMeleeRanged == true
	local roleOrder = H.ExpandRoleOrder(custom.roleOrder, separate)
	local classOrder = custom.classOrder or H.CLASS_TOKENS
	local roleMap = H.BuildOrderMapFromList(roleOrder)
	local classMap = H.BuildOrderMapFromList(classOrder)

	local entries = {}
	local num = (GetNumGroupMembers and GetNumGroupMembers()) or 0
	for i = 1, num do
		local unit = "raid" .. i
		if UnitExists and UnitExists(unit) then
			local name = H.GetUnitFullName(unit)
			if name then
				local _, classToken = UnitClass(unit)
				local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or nil
				if role == "NONE" or role == nil then role = "DAMAGER" end
				local sortRole = role
				if separate and role == "DAMAGER" then
					local specId = H.GetUnitSpecIdCached(unit)
					sortRole = H.GetDpsRangeRole(specId, classToken)
				end
				entries[#entries + 1] = {
					name = name,
					role = role,
					sortRole = sortRole,
					class = classToken,
				}
			end
		end
	end

	table.sort(entries, function(a, b)
		local roleA = roleMap[a.sortRole or a.role] or 999
		local roleB = roleMap[b.sortRole or b.role] or 999
		if roleA ~= roleB then return roleA < roleB end
		local classA = classMap[a.class] or 999
		local classB = classMap[b.class] or 999
		if classA ~= classB then return classA < classB end
		return tostring(a.name or "") < tostring(b.name or "")
	end)

	local names = {}
	local seen = {}
	for _, entry in ipairs(entries) do
		local name = entry.name
		if name and not seen[name] then
			seen[name] = true
			names[#names + 1] = name
		end
	end
	if #names == 0 then return "" end
	return table.concat(names, ",")
end

local function applyRoleQuotaWithLimit(list, limit, maxTanks, maxHealers)
	local limitCount = tonumber(limit)
	local limitT = tonumber(maxTanks) or 0
	local limitH = tonumber(maxHealers) or 0
	if limitCount == nil or limitCount <= 0 then return list end
	if limitT <= 0 and limitH <= 0 then
		if #list > limitCount then
			local result = {}
			for i = 1, limitCount do
				result[#result + 1] = list[i]
			end
			return result
		end
		return list
	end

	-- mark required entries (first N tanks / first N healers in current order)
	local required = {}
	local remainingT = limitT
	for i, entry in ipairs(list) do
		if remainingT <= 0 then break end
		local role = entry.sample and entry.sample.role
		if role == "TANK" then
			required[i] = true
			remainingT = remainingT - 1
		end
	end
	local remainingH = limitH
	for i, entry in ipairs(list) do
		if remainingH <= 0 then break end
		if not required[i] then
			local role = entry.sample and entry.sample.role
			if role == "HEALER" then
				required[i] = true
				remainingH = remainingH - 1
			end
		end
	end

	local requiredSuffix = {}
	local running = 0
	for i = #list, 1, -1 do
		if required[i] then running = running + 1 end
		requiredSuffix[i] = running
	end

	local result = {}
	for i, entry in ipairs(list) do
		if #result >= limitCount then break end
		local role = entry.sample and entry.sample.role
		if required[i] then
			result[#result + 1] = entry
		else
			if role ~= "TANK" and role ~= "HEALER" then
				local remainingSlots = limitCount - #result
				local requiredRemaining = requiredSuffix[i]
				if remainingSlots > requiredRemaining then result[#result + 1] = entry end
			end
		end
	end

	return result
end

function H.BuildRaidPreviewSamples(count)
	local samples = {}
	local classCounts = {}
	local function addSample(class, role)
		classCounts[class] = (classCounts[class] or 0) + 1
		local suffix = classCounts[class]
		local name = (suffix > 1) and (class .. " " .. tostring(suffix)) or class
		local idx = #samples + 1
		samples[idx] = {
			name = name,
			class = class,
			role = role,
			group = floor((idx - 1) / 5) + 1,
		}
	end

	local tanks = { "WARRIOR", "PALADIN" }
	local healers = { "PRIEST", "DRUID", "SHAMAN", "MONK", "EVOKER", "PALADIN" }
	for _, class in ipairs(tanks) do
		addSample(class, "TANK")
	end
	for _, class in ipairs(healers) do
		addSample(class, "HEALER")
	end

	local i = 1
	while #samples < (tonumber(count) or 0) do
		local class = H.CLASS_TOKENS[((i - 1) % #H.CLASS_TOKENS) + 1]
		addSample(class, "DAMAGER")
		i = i + 1
	end

	return samples
end

if not H.PREVIEW_SAMPLES.raid or #H.PREVIEW_SAMPLES.raid == 0 then H.PREVIEW_SAMPLES.raid = H.BuildRaidPreviewSamples(40) or {} end

function H.BuildPreviewSampleList(kind, cfg, baseSamples, limit, quotaTanks, quotaHealers)
	local base = baseSamples or {}
	if kind ~= "raid" then return base end

	local customSort = cfg and cfg.customSort
	if customSort and customSort.enabled == true then
		local separate = customSort.separateMeleeRanged == true
		local roleOrder = H.ExpandRoleOrder(customSort.roleOrder, separate)
		local classOrder = H.NormalizeOrderList(customSort.classOrder, H.CLASS_TOKENS)
		local roleMap = buildOrderMap(table.concat(roleOrder, ","))
		local classMap = buildOrderMap(table.concat(classOrder, ","))
		local sortDir = H.NormalizeSortDir(cfg and cfg.sortDir)
		local list = {}
		for i, sample in ipairs(base) do
			list[#list + 1] = { sample = sample, index = i }
		end
		table.sort(list, function(a, b)
			local roleA = a.sample and (a.sample.assignedRole or a.sample.role) or nil
			local roleB = b.sample and (b.sample.assignedRole or b.sample.role) or nil
			if separate and roleA == "DAMAGER" then roleA = H.GetDpsRangeRole(nil, a.sample and a.sample.class) end
			if separate and roleB == "DAMAGER" then roleB = H.GetDpsRangeRole(nil, b.sample and b.sample.class) end
			local orderA = roleMap[roleA] or 999
			local orderB = roleMap[roleB] or 999
			if orderA ~= orderB then return orderA < orderB end
			local classA = a.sample and a.sample.class or nil
			local classB = b.sample and b.sample.class or nil
			local classOrderA = classMap[classA] or 999
			local classOrderB = classMap[classB] or 999
			if classOrderA ~= classOrderB then return classOrderA < classOrderB end
			return (a.sample.name or "") < (b.sample.name or "")
		end)
		if sortDir == "DESC" then
			for i = 1, floor(#list / 2) do
				local j = #list - i + 1
				list[i], list[j] = list[j], list[i]
			end
		end
		list = applyRoleQuotaWithLimit(list, limit, quotaTanks or 0, quotaHealers or 0)
		local result = {}
		for _, entry in ipairs(list) do
			result[#result + 1] = entry.sample
		end
		return result
	end

	local groupFilter = cfg and cfg.groupFilter
	local roleFilter = cfg and cfg.roleFilter
	local nameList = cfg and cfg.nameList
	local strictFiltering = cfg and cfg.strictFiltering
	local sortMethod = H.NormalizeSortMethod(cfg and cfg.sortMethod)
	local sortDir = H.NormalizeSortDir(cfg and cfg.sortDir)
	local groupBy = normalizeGroupBy(cfg and cfg.groupBy)
	local groupingOrder = cfg and cfg.groupingOrder

	if not groupFilter and not roleFilter and not nameList then groupFilter = H.GROUP_ORDER end

	local list = {}
	local nameOrder = {}

	if groupFilter or roleFilter then
		local tokenTable = {}
		if groupFilter and not roleFilter then
			fillTableFromCsv(tokenTable, groupFilter, true)
			if strictFiltering then fillTableFromCsv(tokenTable, "MAINTANK,MAINASSIST,TANK,HEALER,DAMAGER,NONE", true) end
		elseif roleFilter and not groupFilter then
			fillTableFromCsv(tokenTable, roleFilter, true)
			if strictFiltering then
				fillTableFromCsv(tokenTable, H.GROUP_ORDER, false)
				for _, class in ipairs(H.CLASS_TOKENS) do
					tokenTable[class] = true
				end
			end
		else
			fillTableFromCsv(tokenTable, groupFilter, true)
			fillTableFromCsv(tokenTable, roleFilter, true)
		end

		for i, sample in ipairs(base) do
			local subgroup = tonumber(sample.group) or 1
			local className = sample.class
			local role = sample.role
			local assignedRole = sample.assignedRole or role or "NONE"
			local include
			if not strictFiltering then
				include = tokenTable[subgroup] or tokenTable[className] or (role and tokenTable[role]) or tokenTable[assignedRole]
			else
				include = tokenTable[subgroup] and tokenTable[className] and ((role and tokenTable[role]) or tokenTable[assignedRole])
			end
			if include then list[#list + 1] = { sample = sample, index = i } end
		end
	else
		if nameList then
			local idx = 0
			for token in tostring(nameList):gmatch("[^,]+") do
				local name = trim(token)
				if name ~= "" then
					idx = idx + 1
					nameOrder[name] = idx
				end
			end
		end
		for i, sample in ipairs(base) do
			if not nameList or nameOrder[sample.name or ""] then list[#list + 1] = { sample = sample, index = i } end
		end
	end

	if groupBy then
		if not groupingOrder or groupingOrder == "" then
			if groupBy == "CLASS" then
				groupingOrder = H.CLASS_ORDER
			elseif groupBy == "ROLE" or groupBy == "ASSIGNEDROLE" then
				groupingOrder = H.ROLE_ORDER
			else
				groupingOrder = H.GROUP_ORDER
			end
		end
		local orderMap = buildOrderMap(groupingOrder)

		local function groupKey(sample)
			if groupBy == "GROUP" then
				return tonumber(sample.group) or 1
			elseif groupBy == "CLASS" then
				return sample.class
			elseif groupBy == "ROLE" then
				return sample.role
			elseif groupBy == "ASSIGNEDROLE" then
				return sample.assignedRole or sample.role
			end
			return nil
		end

		if sortMethod == "NAME" then
			table.sort(list, function(a, b)
				local order1 = orderMap[groupKey(a.sample)]
				local order2 = orderMap[groupKey(b.sample)]
				if order1 then
					if not order2 then return true end
					if order1 == order2 then return (a.sample.name or "") < (b.sample.name or "") end
					return order1 < order2
				else
					if order2 then return false end
					return (a.sample.name or "") < (b.sample.name or "")
				end
			end)
		else
			table.sort(list, function(a, b)
				local order1 = orderMap[groupKey(a.sample)]
				local order2 = orderMap[groupKey(b.sample)]
				if order1 then
					if not order2 then return true end
					if order1 == order2 then return a.index < b.index end
					return order1 < order2
				else
					if order2 then return false end
					return a.index < b.index
				end
			end)
		end
	elseif sortMethod == "NAME" then
		table.sort(list, function(a, b) return (a.sample.name or "") < (b.sample.name or "") end)
	elseif sortMethod == "NAMELIST" and next(nameOrder) then
		table.sort(list, function(a, b) return (nameOrder[a.sample.name or ""] or 0) < (nameOrder[b.sample.name or ""] or 0) end)
	end

	if sortDir == "DESC" then
		for i = 1, floor(#list / 2) do
			local j = #list - i + 1
			list[i], list[j] = list[j], list[i]
		end
	end
	local qT = quotaTanks or 0
	local qH = quotaHealers or 0
	list = applyRoleQuotaWithLimit(list, limit, qT, qH)

	local result = {}
	for _, entry in ipairs(list) do
		result[#result + 1] = entry.sample
	end
	return result
end

function H.ClampNumber(value, minValue, maxValue, fallback)
	local v = tonumber(value)
	if v == nil then return fallback end
	if minValue ~= nil and v < minValue then v = minValue end
	if maxValue ~= nil and v > maxValue then v = maxValue end
	return v
end

function H.CopySelectionMap(selection)
	local copy = {}
	if type(selection) ~= "table" then return copy end
	if #selection > 0 then
		for _, value in ipairs(selection) do
			if value ~= nil and (type(value) == "string" or type(value) == "number") then copy[value] = true end
		end
		return copy
	end
	for key, value in pairs(selection) do
		if value and (type(key) == "string" or type(key) == "number") then copy[key] = true end
	end
	return copy
end

H.roleOptions = {
	{ value = "TANK", label = TANK or "Tank" },
	{ value = "HEALER", label = HEALER or "Healer" },
	{ value = "DAMAGER", label = DAMAGER or "DPS" },
}

function H.DefaultRoleSelection()
	local sel = {}
	for _, opt in ipairs(H.roleOptions) do
		sel[opt.value] = true
	end
	return sel
end

local function getClassInfoById(classId)
	if GetClassInfo then return GetClassInfo(classId) end
	if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
		local info = C_CreatureInfo.GetClassInfo(classId)
		if info then return info.className, info.classFile, info.classID end
	end
	return nil
end

local function forEachSpec(callback)
	local getSpecCount = (C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID) or GetNumSpecializationsForClassID
	if not getSpecCount or not GetSpecializationInfoForClassID or not GetNumClasses then return false end
	local sex = UnitSex and UnitSex("player") or nil
	local numClasses = GetNumClasses() or 0
	local found = false
	for classIndex = 1, numClasses do
		local className, classTag, classID = getClassInfoById(classIndex)
		if classID then
			local specCount = getSpecCount(classID) or 0
			for specIndex = 1, specCount do
				local specID, specName = GetSpecializationInfoForClassID(classID, specIndex, sex)
				if specID then
					found = true
					callback(specID, specName, className, classTag, classID)
				end
			end
		end
	end
	return found
end

function H.BuildSpecOptions()
	local opts = {}
	local entries = {}
	local found = forEachSpec(function(specId, specName, className, classTag)
		local label = specName or ("Spec " .. tostring(specId))
		local classLabel = className or classTag
		local classNameText = classLabel or ""
		if classLabel and classLabel ~= "" then label = label .. " (" .. classLabel .. ")" end
		entries[#entries + 1] = {
			value = specId,
			label = label,
			className = classNameText,
			specName = specName or "",
		}
	end)
	if not found and GetNumSpecializations and GetSpecializationInfo then
		for i = 1, GetNumSpecializations() do
			local specId, name = GetSpecializationInfo(i)
			if specId and name then entries[#entries + 1] = { value = specId, label = name, className = "", specName = name } end
		end
	end
	table.sort(entries, function(a, b)
		local ac = tostring(a.className or "")
		local bc = tostring(b.className or "")
		if ac ~= bc then return ac < bc end
		return tostring(a.specName or "") < tostring(b.specName or "")
	end)
	local allLabel = ALL or "All"
	opts[#opts + 1] = { value = "__ALL__", label = allLabel }
	for _, entry in ipairs(entries) do
		opts[#opts + 1] = { value = entry.value, label = entry.label }
	end
	return opts
end

function H.DefaultSpecSelection()
	local sel = {}
	local found = forEachSpec(function(specId)
		if specId then sel[specId] = true end
	end)
	if not found and GetNumSpecializations and GetSpecializationInfo then
		for i = 1, GetNumSpecializations() do
			local specId = GetSpecializationInfo(i)
			if specId then sel[specId] = true end
		end
	end
	return sel
end

H.auraAnchorOptions = {
	{ value = "TOPLEFT", label = "TOPLEFT", text = "TOPLEFT" },
	{ value = "TOP", label = "TOP", text = "TOP" },
	{ value = "TOPRIGHT", label = "TOPRIGHT", text = "TOPRIGHT" },
	{ value = "LEFT", label = "LEFT", text = "LEFT" },
	{ value = "CENTER", label = "CENTER", text = "CENTER" },
	{ value = "RIGHT", label = "RIGHT", text = "RIGHT" },
	{ value = "BOTTOMLEFT", label = "BOTTOMLEFT", text = "BOTTOMLEFT" },
	{ value = "BOTTOM", label = "BOTTOM", text = "BOTTOM" },
	{ value = "BOTTOMRIGHT", label = "BOTTOMRIGHT", text = "BOTTOMRIGHT" },
}

H.textAnchorOptions = {
	{ value = "LEFT", label = "LEFT", text = "LEFT" },
	{ value = "CENTER", label = "CENTER", text = "CENTER" },
	{ value = "RIGHT", label = "RIGHT", text = "RIGHT" },
}

H.anchorOptions9 = H.auraAnchorOptions

H.textModeOptions = {
	{ value = "PERCENT", label = "Percent", text = "Percent" },
	{ value = "CURMAX", label = "Current/Max", text = "Current/Max" },
	{ value = "CURRENT", label = "Current", text = "Current" },
	{ value = "MAX", label = "Max", text = "Max" },
	{ value = "CURPERCENT", label = "Current / Percent", text = "Current / Percent" },
	{ value = "CURMAXPERCENT", label = "Current/Max Percent", text = "Current/Max Percent" },
	{ value = "MAXPERCENT", label = "Max / Percent", text = "Max / Percent" },
	{ value = "PERCENTMAX", label = "Percent / Max", text = "Percent / Max" },
	{ value = "PERCENTCUR", label = "Percent / Current", text = "Percent / Current" },
	{ value = "PERCENTCURMAX", label = "Percent / Current / Max", text = "Percent / Current / Max" },
	{ value = "LEVELPERCENT", label = "Level / Percent", text = "Level / Percent" },
	{ value = "LEVELPERCENTMAX", label = "Level / Percent / Max", text = "Level / Percent / Max" },
	{ value = "LEVELPERCENTCUR", label = "Level / Percent / Current", text = "Level / Percent / Current" },
	{ value = "LEVELPERCENTCURMAX", label = "Level / Percent / Current / Max", text = "Level / Percent / Current / Max" },
	{ value = "NONE", label = "None", text = "None" },
}

H.healthTextModeOptions = {
	{ value = "PERCENT", label = "Percent", text = "Percent" },
	{ value = "CURMAX", label = "Current/Max", text = "Current/Max" },
	{ value = "CURRENT", label = "Current", text = "Current" },
	{ value = "MAX", label = "Max", text = "Max" },
	{ value = "DEFICIT", label = "Deficit", text = "Deficit" },
	{ value = "CURPERCENT", label = "Current / Percent", text = "Current / Percent" },
	{ value = "CURMAXPERCENT", label = "Current/Max Percent", text = "Current/Max Percent" },
	{ value = "MAXPERCENT", label = "Max / Percent", text = "Max / Percent" },
	{ value = "PERCENTMAX", label = "Percent / Max", text = "Percent / Max" },
	{ value = "PERCENTCUR", label = "Percent / Current", text = "Percent / Current" },
	{ value = "PERCENTCURMAX", label = "Percent / Current / Max", text = "Percent / Current / Max" },
	{ value = "NONE", label = "None", text = "None" },
}

H.delimiterOptions = {
	{ value = " ", label = "Space", text = "Space" },
	{ value = "  ", label = "Double space", text = "Double space" },
	{ value = "/", label = "/", text = "/" },
	{ value = ":", label = ":", text = ":" },
	{ value = "-", label = "-", text = "-" },
	{ value = "|", label = "|", text = "|" },
}

H.outlineOptions = {
	{ value = "NONE", label = "None", text = "None" },
	{ value = "OUTLINE", label = "Outline", text = "Outline" },
	{ value = "THICKOUTLINE", label = "Thick Outline", text = "Thick Outline" },
	{ value = "MONOCHROMEOUTLINE", label = "Monochrome Outline", text = "Monochrome Outline" },
	{ value = "DROPSHADOW", label = "Drop shadow", text = "Drop shadow" },
	{ value = "STRONGDROPSHADOW", label = "Strong drop shadow", text = "Strong drop shadow" },
}

H.auraGrowthXOptions = {
	{ value = "LEFT", label = "Left", text = "Left" },
	{ value = "RIGHT", label = "Right", text = "Right" },
}

H.auraGrowthYOptions = {
	{ value = "UP", label = "Up", text = "Up" },
	{ value = "DOWN", label = "Down", text = "Down" },
}

do
	local upLabel = HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_UP or "Up"
	local downLabel = HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_DOWN or "Down"
	local leftLabel = HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_LEFT or "Left"
	local rightLabel = HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_RIGHT or "Right"
	local function growthLabel(first, second) return ("%s %s"):format(first, second) end
	H.auraGrowthOptions = {
		{ value = "UPRIGHT", label = growthLabel(upLabel, rightLabel), text = growthLabel(upLabel, rightLabel) },
		{ value = "UPLEFT", label = growthLabel(upLabel, leftLabel), text = growthLabel(upLabel, leftLabel) },
		{ value = "RIGHTUP", label = growthLabel(rightLabel, upLabel), text = growthLabel(rightLabel, upLabel) },
		{ value = "RIGHTDOWN", label = growthLabel(rightLabel, downLabel), text = growthLabel(rightLabel, downLabel) },
		{ value = "LEFTUP", label = growthLabel(leftLabel, upLabel), text = growthLabel(leftLabel, upLabel) },
		{ value = "LEFTDOWN", label = growthLabel(leftLabel, downLabel), text = growthLabel(leftLabel, downLabel) },
		{ value = "DOWNLEFT", label = growthLabel(downLabel, leftLabel), text = growthLabel(downLabel, leftLabel) },
		{ value = "DOWNRIGHT", label = growthLabel(downLabel, rightLabel), text = growthLabel(downLabel, rightLabel) },
	}
end

function H.TextureOptions(LSM)
	local list = {}
	local seen = {}
	local function add(value, label)
		local lv = tostring(value or ""):lower()
		if lv == "" or seen[lv] then return end
		seen[lv] = true
		list[#list + 1] = { value = value, label = label }
	end
	add("DEFAULT", "Default (Blizzard)")
	add("SOLID", "Solid")
	if not LSM then return list end
	local hash = LSM:HashTable("statusbar") or {}
	for name, path in pairs(hash) do
		if type(path) == "string" and path ~= "" then add(name, tostring(name)) end
	end
	table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return list
end

function H.FontOptions(LSM)
	local list = {}
	local seen = {}
	local function add(value, label)
		local lv = tostring(value or ""):lower()
		if lv == "" or seen[lv] then return end
		seen[lv] = true
		list[#list + 1] = { value = value, label = label }
	end
	if not LSM then return list end
	local hash = LSM:HashTable("font") or {}
	for name, path in pairs(hash) do
		if type(path) == "string" and path ~= "" then add(name, tostring(name)) end
	end
	table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return list
end

function H.EnsureAuraConfig(cfg)
	cfg.auras = cfg.auras or {}
	cfg.auras.buff = cfg.auras.buff or {}
	cfg.auras.debuff = cfg.auras.debuff or {}
	cfg.auras.externals = cfg.auras.externals or {}
	return cfg.auras
end

function H.SyncAurasEnabled(cfg)
	local ac = H.EnsureAuraConfig(cfg)
	local enabled = false
	if ac.buff.enabled then enabled = true end
	if ac.debuff.enabled then enabled = true end
	if ac.externals.enabled then enabled = true end
	ac.enabled = enabled
end

H.AuraFilters = {
	helpful = "HELPFUL|INCLUDE_NAME_PLATE_ONLY|RAID_IN_COMBAT|PLAYER",
	harmful = "HARMFUL|INCLUDE_NAME_PLATE_ONLY",
	dispellable = "HARMFUL|INCLUDE_NAME_PLATE_ONLY|RAID_PLAYER_DISPELLABLE",
	bigDefensive = "HELPFUL|BIG_DEFENSIVE",
}

H.AuraCacheOptions = {
	helpful = { showHelpful = true, showHarmful = false, helpfulFilter = nil },
	harmful = { showHelpful = false, showHarmful = true, harmfulFilter = nil },
	external = { showHelpful = true, showHarmful = false, helpfulFilter = H.AuraFilters.bigDefensive },
	dispel = { showHelpful = false, showHarmful = true, harmfulFilter = H.AuraFilters.dispellable },
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

function H.GetDebuffColorFromName(name)
	local idx = dispelIndexByName[name] or 0
	local col = debuffinfo[idx] or debuffinfo[0]
	if not col then return nil end
	if col.GetRGBA then return col:GetRGBA() end
	if col.GetRGB then return col:GetRGB() end
	if col.r then return col.r, col.g, col.b, col.a end
	return col[1], col[2], col[3], col[4]
end

function H.SelectionHasAny(selection)
	if type(selection) ~= "table" then return false end
	for _, value in pairs(selection) do
		if value then return true end
	end
	return false
end

function H.SelectionContains(selection, key)
	if type(selection) ~= "table" or key == nil then return false end
	if selection[key] == true then return true end
	if #selection > 0 then
		for _, value in ipairs(selection) do
			if value == key then return true end
		end
	end
	return false
end

function H.SelectionMode(selection)
	if type(selection) ~= "table" then return "all" end
	if H.SelectionHasAny(selection) then return "some" end
	return "none"
end

function H.TextModeUsesPercent(mode) return type(mode) == "string" and mode:find("PERCENT", 1, true) ~= nil end
function H.TextModeUsesDeficit(mode) return mode == "DEFICIT" end

function H.UnsecretBool(value)
	local issecretvalue = _G.issecretvalue
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end

H.DispelColorCurve = C_CurveUtil and C_CurveUtil.CreateColorCurve() or nil
if H.DispelColorCurve and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
	H.DispelColorCurve:SetType(Enum.LuaCurveType.Step)
	for dispeltype, v in pairs(debuffinfo) do
		H.DispelColorCurve:AddPoint(dispeltype, v)
	end
end
