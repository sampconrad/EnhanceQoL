-- luacheck: globals EnhanceQoL GAMEMENU_OPTIONS STAT_HASTE STAT_MASTERY STAT_VERSATILITY STAT_CRITICAL_STRIKE CR_HASTE_MELEE CR_MASTERY CR_VERSATILITY_DAMAGE_DONE CR_VERSATILITY_DAMAGE_TAKEN CR_CRIT_MELEE CR_LIFESTEAL CR_BLOCK CR_PARRY CR_DODGE CR_AVOIDANCE CR_SPEED STAT_LIFESTEAL STAT_BLOCK STAT_PARRY STAT_DODGE STAT_AVOIDANCE STAT_SPEED GetLifesteal GetBlockChance GetParryChance GetDodgeChance GetAvoidance GetSpeed
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream

local idx

local STR = LE_UNIT_STAT_STRENGTH
local AGI = LE_UNIT_STAT_AGILITY
local INT = LE_UNIT_STAT_INTELLECT

local NAMES = {
	[STR] = ITEM_MOD_STRENGTH_SHORT, -- "Strength" (lokalisiert)
	[AGI] = ITEM_MOD_AGILITY_SHORT, -- "Agility"
	[INT] = ITEM_MOD_INTELLECT_SHORT, -- "Intellect"
}

local PRIMARY_TOKENS = {
	[STR] = "STRENGTH",
	[AGI] = "AGILITY",
	[INT] = "INTELLECT",
}

local STAT_TOKENS = {
	haste = "HASTE",
	mastery = "MASTERY",
	versatility = "VERSATILITY",
	crit = "CRITCHANCE",
	lifesteal = "LIFESTEAL",
	block = "BLOCK",
	parry = "PARRY",
	dodge = "DODGE",
	avoidance = "AVOIDANCE",
	speed = "SPEED",
}

local FALLBACK_ORDER = {
	primary = 1,
	haste = 2,
	mastery = 3,
	versatility = 4,
	crit = 5,
	lifesteal = 6,
	block = 7,
	parry = 8,
	dodge = 9,
	avoidance = 10,
	speed = 11,
}

local DISPLAY_MODE_LABELS = {
	percent = L["StatDisplayModePercent"] or "Percent",
	rating = L["StatDisplayModeRating"] or "Rating",
	both = L["StatDisplayModeBoth"] or "Rating + Percent",
}

local DISPLAY_MODE_ORDER = { "percent", "rating", "both" }

local VALID_DISPLAY_MODE = {
	percent = true,
	rating = true,
	both = true,
}

local SECONDARY_STATS = {
	"haste",
	"mastery",
	"versatility",
	"crit",
	"lifesteal",
	"block",
	"parry",
	"dodge",
	"avoidance",
	"speed",
}

local function normalizeMode(mode)
	if VALID_DISPLAY_MODE[mode] then return mode end
	return "percent"
end

local function formatNumber(value)
	if not value then return nil end
	local intValue = math.floor(value + 0.5)
	if BreakUpLargeNumbers then
		local ok, result = pcall(BreakUpLargeNumbers, intValue)
		if ok and result then return result end
	end
	local str = tostring(intValue)
	local sign = ""
	if str:sub(1, 1) == "-" then
		sign = "-"
		str = str:sub(2)
	end
	local formatted = str:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return sign .. formatted
end

local function formatPercent(value)
	if value == nil then return nil end
	local txt = ("%.2f"):format(value)
	txt = txt:gsub("(%..-)0+$", "%1")
	txt = txt:gsub("%.$", "")
	return txt .. "%"
end

local function formatStatText(label, mode, ratingValue, percentValue, secondaryPercent)
	mode = normalizeMode(mode)
	local ratingText = ratingValue and formatNumber(ratingValue)
	local percentText = percentValue and formatPercent(percentValue)
	local secondaryPercentText = secondaryPercent and formatPercent(secondaryPercent)

	if not ratingText and not percentText and not secondaryPercentText then return nil end

	if mode == "rating" then
		if ratingText then return ("%s: %s"):format(label, ratingText) end
		if percentText then return ("%s: %s"):format(label, percentText) end
		if secondaryPercentText then return ("%s: %s"):format(label, secondaryPercentText) end
		return nil
	elseif mode == "both" then
		if secondaryPercentText then
			local percentCombo = percentText and ("%s/%s"):format(percentText, secondaryPercentText) or secondaryPercentText
			if ratingText and percentCombo then return ("%s: %s - %s"):format(label, ratingText, percentCombo) end
			return ("%s: %s"):format(label, ratingText or percentCombo)
		else
			if ratingText and percentText then return ("%s: %s - %s"):format(label, ratingText, percentText) end
			return ("%s: %s"):format(label, ratingText or percentText)
		end
	else -- percent
		if secondaryPercentText then
			if percentText then return ("%s: %s/%s"):format(label, percentText, secondaryPercentText) end
			return ("%s: %s"):format(label, secondaryPercentText)
		end
		if percentText then return ("%s: %s"):format(label, percentText) end
		if ratingText then return ("%s: %s"):format(label, ratingText) end
		return nil
	end
end

local function GetPlayerPrimaryStatIndex()
	local spec = C_SpecializationInfo.GetSpecialization()
	if spec then
		-- 7. Rückgabewert ist der Primary-Stat (Index, passt direkt in UnitStat)
		local _, _, _, _, _, _, primaryStat = C_SpecializationInfo.GetSpecializationInfo(spec)
		if primaryStat == STR or primaryStat == AGI or primaryStat == INT then return primaryStat end
	end
	-- Fallback: nimm den höchsten von STR/AGI/INT auf dem Spieler
	local _, sSTR = UnitStat("player", STR)
	local _, sAGI = UnitStat("player", AGI)
	local _, sINT = UnitStat("player", INT)
	if sSTR >= sAGI and sSTR >= sINT then
		return STR
	elseif sAGI >= sINT then
		return AGI
	else
		return INT
	end
end

local function GetPlayerPrimaryStat()
	if not idx then idx = GetPlayerPrimaryStatIndex() end
	local base, effective = UnitStat("player", idx) -- effective enthält Buffs
	return (effective or base), idx, (NAMES[idx] or "Primary"), PRIMARY_TOKENS[idx]
end

local function getPaperdollStatOrder()
	local order = {}
	local categories = PAPERDOLL_STATCATEGORIES
	if not categories then return order end

	local index = 1
	for _, category in ipairs(categories) do
		local stats = category and category.stats
		if stats then
			for _, entry in ipairs(stats) do
				local token
				if type(entry) == "table" then
					token = entry.stat
				else
					token = entry
				end
				if token and order[token] == nil then
					order[token] = index
					index = index + 1
				end
			end
		end
	end

	return order
end

local function getOptionsHint()
	if addon.DataPanel and addon.DataPanel.GetOptionsHintText then
		local text = addon.DataPanel.GetOptionsHintText()
		if text ~= nil then return text end
		return nil
	end
	return L["Right-Click for options"]
end

local function ensureStatEntry(key, supportsMode)
	db[key] = db[key] or {}
	local entry = db[key]
	if entry.enabled == nil then entry.enabled = true end
	if supportsMode then
		if entry.mode == nil then
			if entry.rating ~= nil then
				entry.mode = entry.rating and "rating" or "percent"
			else
				entry.mode = "percent"
			end
		end
		entry.mode = normalizeMode(entry.mode)
	else
		entry.mode = nil
	end
	entry.rating = nil
	entry.color = entry.color or { r = 1, g = 1, b = 1 }
end

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.stats = addon.db.datapanel.stats or {}
	db = addon.db.datapanel.stats
	db.fontSize = db.fontSize or 14
	db.vertical = db.vertical or false
	db.primary = db.primary or {}
	if db.primary.enabled == nil then db.primary.enabled = true end
	db.primary.color = db.primary.color or { r = 1, g = 1, b = 1 }
	ensureStatEntry("primary", false)

	for _, key in ipairs(SECONDARY_STATS) do
		ensureStatEntry(key, true)
	end
end

local function RestorePosition(frame)
	if db.point and db.x and db.y then
		frame:ClearAllPoints()
		frame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
	end
end

local aceWindow
local function addStatOptions(frame, key, label, supportsMode)
	local group = AceGUI:Create("InlineGroup")
	group:SetTitle(label)
	group:SetFullWidth(true)
	group:SetLayout("List")

	local show = AceGUI:Create("CheckBox")
	show:SetLabel(SHOW)
	show:SetValue(db[key].enabled)
	show:SetCallback("OnValueChanged", function(_, _, val)
		db[key].enabled = val and true or false
		addon.DataHub:RequestUpdate(stream)
	end)
	group:AddChild(show)

	if supportsMode ~= false then
		local mode = AceGUI:Create("Dropdown")
		mode:SetLabel(L["StatDisplayMode"] or "Display mode")
		mode:SetList(DISPLAY_MODE_LABELS, DISPLAY_MODE_ORDER)
		mode:SetValue(db[key].mode or "percent")
		mode:SetCallback("OnValueChanged", function(_, _, val)
			db[key].mode = normalizeMode(val)
			addon.DataHub:RequestUpdate(stream)
		end)
		group:AddChild(mode)
	end

	local color = AceGUI:Create("ColorPicker")
	color:SetLabel(COLOR)
	local c = db[key].color
	color:SetColor(c.r, c.g, c.b)
	color:SetCallback("OnValueChanged", function(_, _, r, g, b)
		db[key].color = { r = r, g = g, b = b }
		addon.DataHub:RequestUpdate(stream)
	end)
	group:AddChild(color)

	frame:AddChild(group)
end

local function createAceWindow()
	if aceWindow then
		aceWindow:Show()
		return
	end
	ensureDB()
	local frame = AceGUI:Create("Window")
	aceWindow = frame.frame
	frame:SetTitle((addon.DataPanel and addon.DataPanel.GetStreamOptionsTitle and addon.DataPanel.GetStreamOptionsTitle(stream and stream.meta and stream.meta.title)) or GAMEMENU_OPTIONS)
	frame:SetWidth(330)
	frame:SetHeight(500)
	frame:SetLayout("List")

	frame.frame:SetScript("OnShow", function(self) RestorePosition(self) end)
	frame.frame:SetScript("OnHide", function(self)
		local point, _, _, xOfs, yOfs = self:GetPoint()
		db.point = point
		db.x = xOfs
		db.y = yOfs
	end)

	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	frame:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)

	local fontSize = AceGUI:Create("Slider")
	fontSize:SetLabel(FONT_SIZE)
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		addon.DataHub:RequestUpdate(stream)
	end)
	groupCore:AddChild(fontSize)

	local vertical = AceGUI:Create("CheckBox")
	vertical:SetLabel(L["Display vertically"] or "Display vertically")
	vertical:SetValue(db.vertical)
	vertical:SetCallback("OnValueChanged", function(_, _, val)
		db.vertical = val and true or false
		addon.DataHub:RequestUpdate(stream)
	end)
	groupCore:AddChild(vertical)

	local primaryLabel = select(3, GetPlayerPrimaryStat())
	addStatOptions(groupCore, "primary", primaryLabel or "Primary", false)
	addStatOptions(groupCore, "haste", STAT_HASTE or "Haste")
	addStatOptions(groupCore, "mastery", STAT_MASTERY or "Mastery")
	addStatOptions(groupCore, "versatility", STAT_VERSATILITY or "Versatility")
	addStatOptions(groupCore, "crit", STAT_CRITICAL_STRIKE or "Crit")
	addStatOptions(groupCore, "lifesteal", STAT_LIFESTEAL or "Leech")
	addStatOptions(groupCore, "block", STAT_BLOCK or "Block")
	addStatOptions(groupCore, "parry", STAT_PARRY or "Parry")
	addStatOptions(groupCore, "dodge", STAT_DODGE or "Dodge")
	addStatOptions(groupCore, "avoidance", STAT_AVOIDANCE or "Avoidance")
	addStatOptions(groupCore, "speed", STAT_SPEED or "Speed")

	frame.frame:Show()
	scroll:DoLayout()
end

local function colorize(text, color)
	if color and color.r and color.g and color.b then return ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, text) end
	return text
end

local function checkStats(stream)
	ensureDB()
	local sep = db.vertical and "\n" or " "
	local size = db.fontSize or 14
	stream.snapshot.fontSize = size
	stream.snapshot.tooltip = getOptionsHint()

	local orderMap = getPaperdollStatOrder()
	local entries = {}

	local function push(key, token, text, color)
		if not text then return end
		entries[#entries + 1] = {
			sort = token and orderMap[token] or nil,
			fallback = FALLBACK_ORDER[key] or (#entries + 100),
			text = colorize(text, color),
		}
	end

	local function emitStat(key, token, label, ratingValue, percentValue, extraPercentValue)
		local cfg = db[key]
		if not cfg or not cfg.enabled then return end
		local text = formatStatText(label, cfg.mode or "percent", ratingValue, percentValue, extraPercentValue)
		push(key, token, text, cfg.color)
	end

	local primaryValue, _, primaryName, primaryToken = GetPlayerPrimaryStat()
	if db.primary.enabled then
		local formattedPrimary = formatNumber(primaryValue) or (primaryValue ~= nil and tostring(primaryValue) or "")
		push("primary", primaryToken, ("%s: %s"):format(primaryName, formattedPrimary), db.primary.color)
	end

	emitStat("haste", STAT_TOKENS.haste, STAT_HASTE or "Haste", GetCombatRating(CR_HASTE_MELEE), GetHaste())
	emitStat("mastery", STAT_TOKENS.mastery, STAT_MASTERY or "Mastery", GetCombatRating(CR_MASTERY), GetMasteryEffect())

	do
		local rating = GetCombatRating(CR_VERSATILITY_DAMAGE_DONE)
		local dmg = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) + GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE)
		local red = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_TAKEN) + GetVersatilityBonus(CR_VERSATILITY_DAMAGE_TAKEN)
		emitStat("versatility", STAT_TOKENS.versatility, STAT_VERSATILITY or "Vers", rating, dmg, red)
	end

	emitStat("crit", STAT_TOKENS.crit, STAT_CRITICAL_STRIKE or "Crit", GetCombatRating(CR_CRIT_MELEE), GetCritChance())
	emitStat("lifesteal", STAT_TOKENS.lifesteal, STAT_LIFESTEAL or "Leech", GetCombatRating(CR_LIFESTEAL), GetLifesteal())
	emitStat("block", STAT_TOKENS.block, STAT_BLOCK or "Block", GetCombatRating(CR_BLOCK), GetBlockChance())
	emitStat("parry", STAT_TOKENS.parry, STAT_PARRY or "Parry", GetCombatRating(CR_PARRY), GetParryChance())
	emitStat("dodge", STAT_TOKENS.dodge, STAT_DODGE or "Dodge", GetCombatRating(CR_DODGE), GetDodgeChance())
	emitStat("avoidance", STAT_TOKENS.avoidance, STAT_AVOIDANCE or "Avoidance", GetCombatRating(CR_AVOIDANCE), GetAvoidance())
	emitStat("speed", STAT_TOKENS.speed, STAT_SPEED or "Speed", GetCombatRating(CR_SPEED), GetSpeed())

	table.sort(entries, function(a, b)
		local aOrder = a.sort or a.fallback
		local bOrder = b.sort or b.fallback
		if aOrder == bOrder then return a.fallback < b.fallback end
		return aOrder < bOrder
	end)

	local texts = {}
	for i, entry in ipairs(entries) do
		texts[i] = entry.text
	end

	stream.snapshot.text = table.concat(texts, sep)
end

local provider = {
	id = "stats",
	version = 2,
	title = PET_BATTLE_STATS_LABEL,
	update = checkStats,
	events = {
		COMBAT_RATING_UPDATE = function(stream) addon.DataHub:RequestUpdate(stream) end,
		MASTERY_UPDATE = function(stream) addon.DataHub:RequestUpdate(stream) end,
		PLAYER_EQUIPMENT_CHANGED = function(stream) addon.DataHub:RequestUpdate(stream) end,
		PLAYER_TALENT_UPDATE = function(stream) addon.DataHub:RequestUpdate(stream) end,
		ACTIVE_TALENT_GROUP_CHANGED = function(stream) addon.DataHub:RequestUpdate(stream) end,
		UPDATE_SHAPESHIFT_FORM = function(stream) addon.DataHub:RequestUpdate(stream) end,
		PLAYER_ENTERING_WORLD = function(stream) addon.DataHub:RequestUpdate(stream) end,
		PLAYER_LOGIN = function(stream)
			C_Timer.After(1, function()
				idx = GetPlayerPrimaryStatIndex()
				addon.DataHub:RequestUpdate(stream)
			end)
		end,
		ACTIVE_PLAYER_SPECIALIZATION_CHANGED = function(stream)
			C_Timer.After(1, function()
				idx = GetPlayerPrimaryStatIndex()
				addon.DataHub:RequestUpdate(stream)
			end)
		end,
	},
	eventsUnit = {
		player = {
			UNIT_SPELL_HASTE = true,
			UNIT_ATTACK_SPEED = true,
			UNIT_STATS = true,
			UNIT_AURA = function(stream)
				C_Timer.After(0.5, function() addon.DataHub:RequestUpdate(stream) end)
			end,
		},
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
