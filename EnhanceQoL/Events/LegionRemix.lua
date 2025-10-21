local PARENT_ADDON = "EnhanceQoL"
local addonName, addon = ...

if _G[PARENT_ADDON] then
	addon = _G[PARENT_ADDON]
else
	error("LegionRemix module requires EnhanceQoL to be loaded first.")
end

addon.Events = addon.Events or {}
addon.Events.LegionRemix = addon.Events.LegionRemix or {}
local LegionRemix = addon.Events.LegionRemix

local AceGUI = LibStub("AceGUI-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(PARENT_ADDON)

local DEFAULT_PHASE_KEYS = { "mount", "item", "toy", "pet", "achievement", "title", "rare_appearance", "cloaks" }
local PHASE_LOOKUP = _G.EnhanceQoLLegionRemixPhaseData or {}
for _, key in ipairs(DEFAULT_PHASE_KEYS) do
	if type(PHASE_LOOKUP[key]) ~= "table" then PHASE_LOOKUP[key] = {} end
end

LegionRemix.phaseLookup = PHASE_LOOKUP

LegionRemix.phaseAchievements = LegionRemix.phaseAchievements or {}
for achievementID, phase in pairs(PHASE_LOOKUP.achievement) do
	local list = LegionRemix.phaseAchievements[phase]
	if not list then
		list = {}
		LegionRemix.phaseAchievements[phase] = list
	end
	table.insert(list, achievementID)
end
for _, list in pairs(LegionRemix.phaseAchievements) do
	table.sort(list)
end
LegionRemix.phaseTotals = LegionRemix.phaseTotals or {}
LegionRemix.eventsRegistered = LegionRemix.eventsRegistered or false
LegionRemix.active = LegionRemix.active or false

function LegionRemix:GetAllPhases()
	if self.cachedPhases then return self.cachedPhases end
	local seen = {}
	for _, mapping in pairs(PHASE_LOOKUP) do
		for _, phase in pairs(mapping) do
			if phase then seen[phase] = true end
		end
	end
	local phases = {}
	for phase in pairs(seen) do
		table.insert(phases, phase)
	end
	table.sort(phases)
	self.cachedPhases = phases
	return phases
end

function LegionRemix:GetPhaseReleaseTimes()
	local releaseTimes = {}
	local patchInfo = addon and addon.variables and addon.variables.patchInformations
	if type(patchInfo) == "table" then
		for key, value in pairs(patchInfo) do
			local phase = key:match("^legionRemixPhase(%d+)$")
			if phase then releaseTimes[tonumber(phase)] = value end
		end
	end
	return releaseTimes
end

function LegionRemix:GetCurrentPhase()
	local releaseTimes = self:GetPhaseReleaseTimes()
	if not releaseTimes then return nil end
	local now = type(GetServerTime) == "function" and GetServerTime() or time()
	local activePhase
	for phase, timestamp in pairs(releaseTimes) do
		if timestamp and now >= timestamp then
			if not activePhase or phase > activePhase then activePhase = phase end
		end
	end
	return activePhase
end

function LegionRemix:GetPhaseFilterMode()
	local db = self:GetDB()
	if not db then return "all" end
	local filters = db.phaseFilters or {}
	local mode = filters.mode
	if mode == "current" then return "current" end
	return "all"
end

function LegionRemix:SetPhaseFilterMode(mode)
	local db = self:GetDB()
	if not db then return end
	db.phaseFilters = db.phaseFilters or {}
	if mode ~= "current" then mode = "all" end
	if db.phaseFilters.mode == mode then return end
	db.phaseFilters.mode = mode
	self:RefreshData()
end

function LegionRemix:GetActivePhaseFilterSet()
	local mode = self:GetPhaseFilterMode()
	local phases = self:GetAllPhases()
	local set = {}
	if mode == "current" then
		local currentPhase = self:GetCurrentPhase()
		local releaseTimes = self:GetPhaseReleaseTimes()
		local now = type(GetServerTime) == "function" and GetServerTime() or time()
		for _, phase in ipairs(phases) do
			if currentPhase then
				if phase <= currentPhase then set[phase] = true end
			else
				local release = releaseTimes and releaseTimes[phase]
				if release and now >= release then set[phase] = true end
			end
		end
		return set, false
	end
	for _, phase in ipairs(phases) do
		set[phase] = true
	end
	return set, true
end

function LegionRemix:IsPhaseActive(phase)
	local active, allActive = self:GetActivePhaseFilterSet()
	if allActive then return true end
	return active[phase] or false
end

function LegionRemix:SetPhaseFilter(phase, enabled)
	if phase == "all" then
		self:SetPhaseFilterMode("all")
		return
	end
	if phase == "current" then
		self:SetPhaseFilterMode(enabled and "current" or "all")
		return
	end
	if enabled then
		self:SetPhaseFilterMode("current")
	else
		self:SetPhaseFilterMode("all")
	end
end

function LegionRemix:TogglePhaseFilter(phase)
	if phase == "current" then
		if self:GetPhaseFilterMode() == "current" then
			self:SetPhaseFilterMode("all")
		else
			self:SetPhaseFilterMode("current")
		end
		return
	end
	if self:GetPhaseFilterMode() == "current" then
		self:SetPhaseFilterMode("all")
	else
		self:SetPhaseFilterMode("current")
	end
end

function LegionRemix:ResetPhaseFilters() self:SetPhaseFilterMode("all") end

function LegionRemix:SetFilterButtonActive(button, active)
	if not button then return end
	button.active = active and true or false
	if button.active then
		button:SetBackdropColor(0.14, 0.36, 0.66, 0.9)
		button:SetBackdropBorderColor(0.18, 0.48, 0.82, 0.9)
		button.label:SetTextColor(1, 1, 1)
	else
		button:SetBackdropColor(0.06, 0.06, 0.1, 0.6)
		button:SetBackdropBorderColor(0.16, 0.28, 0.45, 0.6)
		button.label:SetTextColor(0.82, 0.84, 0.9)
	end
end

function LegionRemix:BuildFilterButtons()
	if not self.overlay or not self.overlay.filterBar then return end
	local bar = self.overlay.filterBar
	bar.hasButtons = false
	if bar.buttons then
		for _, btn in ipairs(bar.buttons) do
			btn:Hide()
			btn:SetParent(nil)
		end
	end
	bar.buttons = {}
	self.filterButtons = {}

	local phases = self:GetAllPhases()
	if #phases == 0 then
		bar:Hide()
		return
	end
	bar:Show()
	bar.hasButtons = true

	local function createButton(key, label, onClick, mode)
		local btn = CreateFrame("Button", nil, bar, "BackdropTemplate")
		btn:SetHeight(22)
		btn:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
			insets = { left = 1, right = 1, top = 1, bottom = 1 },
		})
		btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		btn.label:SetPoint("CENTER")
		btn.label:SetText(label)
		local width = math.max(56, btn.label:GetStringWidth() + 20)
		btn:SetWidth(width)
		btn:SetScript("OnClick", onClick)
		btn:SetScript("OnEnter", function(self)
			if not self.active then self:SetBackdropColor(0.09, 0.09, 0.14, 0.75) end
		end)
		btn:SetScript("OnLeave", function(self)
			if not self.active then LegionRemix:SetFilterButtonActive(self, false) end
		end)
		table.insert(bar.buttons, btn)
		self.filterButtons[key] = btn
		btn.mode = mode
		return btn
	end

	createButton("all", ALL, function() LegionRemix:ResetPhaseFilters() end, "all")
	createButton("current", L["Current Available"], function() LegionRemix:SetPhaseFilterMode("current") end, "current")

	self:LayoutFilterButtons()
	if C_Timer then C_Timer.After(0, function() LegionRemix:LayoutFilterButtons() end) end
end

function LegionRemix:UpdateFilterButtons()
	if not self.filterButtons then return end
	local mode = self:GetPhaseFilterMode()
	for _, btn in pairs(self.filterButtons) do
		if btn.mode == "all" then
			self:SetFilterButtonActive(btn, mode == "all")
		elseif btn.mode == "current" then
			self:SetFilterButtonActive(btn, mode == "current")
		end
	end
end

local BRONZE_CURRENCY_ID = 3252
local DEFAULTS = {
	overlayEnabled = false,
	overlayHidden = false,
	locked = false,
	collapsed = false,
	classOnly = false,
	enhancedTracking = true,
	overlayScale = 1,
	itemNameCache = {},
	categoryFilters = {},
	hideCompleteCategories = false,
	zoneFilters = {},
	phaseFilters = { mode = "all" },
	anchor = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 0, y = -120 },
}

local EVENT_LIST = {
	"PLAYER_ENTERING_WORLD",
	"NEW_MOUNT_ADDED",
	"MOUNT_JOURNAL_USABILITY_CHANGED",
	"TOYS_UPDATED",
	"PET_JOURNAL_LIST_UPDATE",
	"TRANSMOG_COLLECTION_UPDATED",
	"TRANSMOG_COLLECTION_SOURCE_ADDED",
	"TRANSMOG_COLLECTION_SOURCE_REMOVED",
	"TRANSMOG_SETS_UPDATE_FAVORITE",
	"PLAYER_SPECIALIZATION_CHANGED",
	"CURRENCY_DISPLAY_UPDATE",
}

local CLASS_MASKS = {
	WARRIOR = 1,
	PALADIN = 2,
	HUNTER = 4,
	ROGUE = 8,
	PRIEST = 16,
	DEATHKNIGHT = 32,
	SHAMAN = 64,
	MAGE = 128,
	WARLOCK = 256,
	MONK = 512,
	DRUID = 1024,
	DEMONHUNTER = 2048,
	EVOKER = 4096,
}

local SUPPORTED_ZONE_TYPES = { "world", "dungeon", "raid" }
local SUPPORTED_ZONE_LOOKUP = {}
for _, key in ipairs(SUPPORTED_ZONE_TYPES) do
	SUPPORTED_ZONE_LOOKUP[key] = true
end

local INSTANCE_DIFFICULTY_GROUPS = {
	world = { ids = { 0 } },
	dungeon = { ids = { 1, 2, 8, 23, 24, 33, 150 } },
	raid = { ids = { 3, 4, 5, 6, 7, 9, 14, 15, 16, 17, 151 } },
}

local DIFFICULTY_TO_ZONE_KEY = {}
for zoneKey, data in pairs(INSTANCE_DIFFICULTY_GROUPS) do
	for _, difficultyID in ipairs(data.ids) do
		DIFFICULTY_TO_ZONE_KEY[difficultyID] = zoneKey
	end
end

local INSTANCE_TYPE_ZONE_FALLBACK = {
	none = "world",
	party = "dungeon",
	scenario = "dungeon",
	raid = "raid",
	pvp = "other",
	arena = "other",
}

local CATEGORY_DATA = {
	{
		key = "mounts",
		label = MOUNTS,
		groups = {
			{
				type = "mount",
				cost = 10000,
				items = {
					2653,
					2671,
					2672,
					2673,
					2674,
					2665,
					2675,
					2676,
					2677,
					2678,
					2705,
					2706,
					2593,
					2660,
					2661,
					2662,
					2542,
					2544,
					2546,
					2663,
					2664,
					2666,
					2574,
					2670,
					2679,
					2681,
					2682,
					2683,
					2686,
					2688,
					2689,
					2690,
					2691,
				},
			},
			{ type = "mount", cost = 20000, items = { 802, 943, 941, 905, 944, 942, 983, 984, 985, 838 } },
			{ type = "mount", cost = 20000, items = { 2726, 2731, 2720, 2723, 2728, 2725, 2721, 2727, 2730, 2724, 2729 } },
			{ type = "mount", cost = 40000, items = { 656, 779, 981, 980, 979, 955, 906, 973, 975, 976, 974, 970 } },
			{ type = "mount", cost = 100000, items = { 847, 875, 791, 633, 899, 971, 954 } },
		},
	},
	{
		key = "toys",
		label = TOY,
		groups = {
			{ type = "toy", cost = 10000, items = { 129165, 130169, 131717, 131724, 142528, 142529, 142530, 143662, 153193, 153204 } },
			{ type = "toy", cost = 20000, items = { 140363 } },
			{ type = "toy", cost = 25000, items = { 141862, 153126, 153179, 153180, 153181, 153182, 153194, 153253, 153293 } },
			{ type = "toy", cost = 35000, items = { 142265, 147843, 147867, 153124 } },
			{ type = "toy", cost = 80000, items = { 140160, 152982, 153183 } },
			{ type = "toy", cost = 100000, items = { 119211, 143544, 153004 } },
		},
	},
	{
		key = "pets",
		label = AUCTION_CATEGORY_BATTLE_PETS,
		groups = {
			{ type = "pet", cost = 5000, items = { 4802, 4801, 1751 } },
			{ type = "pet", cost = 10000, items = { 1887, 2115, 2136, 1926, 1928, 1929 } },
			{ type = "pet", cost = 20000, items = { 2120, 2118, 2119 } },
			{ type = "pet", cost = 35000, items = { 2135, 2022, 2050, 1718 } },
			{ type = "pet", cost = 80000, items = { 1723, 2071, 2072, 2042 } },
			{ type = "pet", cost = 100000, items = { 1803, 1937, 1719 } },
		},
	},
	{
		key = "titles",
		label = UNIT_NAME_PLAYER_TITLE,
		groups = {
			{
				type = "title",
				cost = 0,
				items = {
					{ id = 825, achievementId = 42301, name = "Timerunner" },
					{ id = 971, achievementId = 61079, name = "of the Infinite Chaos" },
					{ id = 926, achievementId = 60935, name = "Chronoscholar" },
				},
			},
		},
	},
	{
		key = "achievements",
		label = TRANSMOG_SOURCE_5,
		groups = {
			{
				type = "set_achievement",
				cost = 0,
				items = { 177, 185, 181, 173, 5278, 5280, 5279, 5286, 5281 },
				requirements = {
					[177] = 61026,
					[185] = 61024,
					[181] = 61025,
					[173] = 61027,
					[5278] = 61337,
					[5279] = 61078,
					[5280] = 42690,
					[5281] = 61070,
					[5286] = 42605,
				},
			},
			{
				type = "set_achievement_item",
				cost = 0,
				items = {
					253285,
					--293195,
					253229,
					253220,
				},
				requirements = {
					[253285] = 42583,
					[253229] = 42666,
					[253220] = 42549,
					-- [293195] = 42582 -- actually not implemented?
				},
			},
			{
				type = "set_achievement_pet",
				cost = 0,
				items = { 4901, 4854 },
				requirements = {
					[4901] = 42319,
					[4854] = 42541,
				},
			},
		},
	},
	{
		key = "rare_appearance",
		label = L["Rare Appearance"],
		groups = {
			{ type = "transmog", cost = 30000, items = { 242368, 151524, 255006, 253273 } },
		},
	},
	{
		key = "raidfinder",
		label = PLAYER_DIFFICULTY3,
		groups = {
			{ type = "set_mixed", cost = 20000, items = { 186, 182, 178, 174 } },
		},
	},
	{
		key = "mythic",
		label = PLAYER_DIFFICULTY6,
		groups = {
			{
				type = "set_per_class",
				cost = 30000,
				itemsByClass = {
					DEATHKNIGHT = { 1004, 1338, 1474 },
					DEMONHUNTER = { 1000, 1334, 1478 },
					DRUID = { 996, 1330, 1482 },
					HUNTER = { 992, 1326, 1486 },
					MAGE = { 998, 1322, 1490 },
					MONK = { 984, 1318, 1494 },
					PALADIN = { 980, 1314, 1498 },
					PRIEST = { 311, 1310, 1502 },
					ROGUE = { 944, 1308, 1506 },
					SHAMAN = { 935, 1304, 1510 },
					WARLOCK = { 321, 1299, 1514 },
					WARRIOR = { 939, 1295, 1518 },
				},
			},
		},
	},
	{
		key = "dungeon",
		label = DUNGEONS,
		groups = {
			{ type = "set_mixed", cost = 15000, items = { 4403, 4414, 4415, 4416 } },
			{ type = "set_mixed", cost = 15000, items = { 4406, 4417, 4418, 4419 } },
			{ type = "set_mixed", cost = 15000, items = { 4420, 4421, 4422, 4408 } },
			{ type = "set_mixed", cost = 15000, items = { 4411, 4423, 4424, 4425 } },
		},
	},
	{
		key = "world",
		label = WORLD,
		groups = {
			{ type = "set_mixed", cost = 15000, items = { 160, 4402, 4404, 4465, 4466, 4467, 4468, 4485, 4330, 4481 } },
			{ type = "set_mixed", cost = 15000, items = { 159, 4405, 4407, 4469, 4470, 4471, 4472, 4486, 4399, 4482, 4458 } },
			{ type = "set_mixed", cost = 15000, items = { 158, 4409, 4410, 4473, 4474, 4475, 4476, 4487, 4400, 4483 } },
			{ type = "set_mixed", cost = 15000, items = { 157, 4412, 4413, 4477, 4478, 4479, 4480, 4488, 4401, 4490, 4484, 5301, 5300, 5302, 5303, 5304 } },
		},
	},
	{
		key = "unique",
		label = L["Remix Exclusives"],
		groups = {
			{ type = "set_mixed", cost = 7500, items = { 4427, 4428, 4429, 4430, 4431, 4432, 4489, 4491 } },
			{ type = "set_mixed", cost = 7500, items = { 4433, 4434, 4435, 4436, 4437, 4457, 2337 } },
			{ type = "set_mixed", cost = 7500, items = { 4443, 4444, 4447, 4448, 4450, 4459 } },
			{ type = "set_mixed", cost = 7500, items = { 4452, 4453, 4460, 2656, 5270 } },
			{ type = "set_mixed", cost = 2500, items = { 5294 } },
			{ type = "set_mixed", cost = 7500, items = { 4331, 4462, 4463, 4464 } },
			{ type = "set_mixed", cost = 2500, items = { 5291, 5295, 5296, 5297, 5298 } },
			{ type = "set_mixed", cost = 7500, items = { 5292, 5293 } },
			-- Gems of the Lightforged Draenei not yet implemented
			-- { type = "set_mixed", cost = 7500, items = { 5299 } },
			-- Odyns Spear has no appearanceID the items are: 255153, 255152
		},
	},
	{
		key = "cloaks",
		label = BACKSLOT,
		groups = {
			{ type = "set_achievement_item", cost = 2000, items = { 241944, 241667 }, mod = 0 },
			{ type = "set_achievement_item", cost = 4000, items = { 242213, 241804, 251539, 242105 }, mod = 0 },
			{ type = "set_achievement_item", cost = 6000, items = { 251876, 241820, 241879, 241767, 241690, 239846, 241749 }, mod = 0 },
			{ type = "set_achievement_item", cost = 8000, items = { 241790, 242002, 242070, 242121, 251874 }, mod = 0 },
		},
	},
	{
		key = "lostfound",
		label = AUCTION_CATEGORY_MISCELLANEOUS,
		groups = {
			{ type = "set_mixed", cost = 15000, items = { 4440, 4442, 4446, 4449, 4454, 4456, 4492 } },
		},
	},
}

local function normalizePhaseKind(kind)
	if kind == "mount" then return "mount" end
	if kind == "achievement" then return "achievement" end
	if kind == "title" then return "title" end
	if kind == "toy" then return "toy" end
	if kind == "pet" then return "pet" end
	if kind == "transmog" or kind == "item" then return "item" end
	if kind == "set" then return "set" end
	return nil
end

function LegionRemix:GetPhaseFor(kind, id)
	if not id then return nil end
	local normalized = normalizePhaseKind(kind)
	if not normalized then return nil end
	local map = PHASE_LOOKUP[normalized]
	return map and map[id] or nil
end

function LegionRemix:GetPhaseLookup() return PHASE_LOOKUP end

function LegionRemix:GetPhaseAchievements() return self.phaseAchievements end

local ZONE_TYPE_LABELS = {
	world = WORLD,
	dungeon = LFG_TYPE_DUNGEON,
	raid = LFG_TYPE_RAID,
	other = OTHER,
}

function LegionRemix:GetZoneTypeLabel(key) return ZONE_TYPE_LABELS[key] or key end

local function deepMerge(target, source)
	if type(target) ~= "table" then target = {} end
	for key, value in pairs(source) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then target[key] = {} end
			deepMerge(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
	return target
end

local function formatBronze(value)
	if not value or value <= 0 then return "0" end
	if AbbreviateLargeNumbers then return AbbreviateLargeNumbers(value) end
	return BreakUpLargeNumbers(math.floor(value + 0.5))
end

local function getProfile()
	if not addon or not addon.db then return nil end
	addon.db.legionRemix = deepMerge(addon.db.legionRemix, DEFAULTS)
	return addon.db.legionRemix
end

LegionRemix.cache = LegionRemix.cache or {}
LegionRemix.cache.names = LegionRemix.cache.names or {}
LegionRemix.cache.achievements = LegionRemix.cache.achievements or {}
LegionRemix.cache.achievementInfo = LegionRemix.cache.achievementInfo or {}
LegionRemix.cache.titles = LegionRemix.cache.titles or {}
LegionRemix.rows = LegionRemix.rows or {}

local function clearTable(tbl)
	if not tbl then return end
	for k in pairs(tbl) do
		tbl[k] = nil
	end
end

function LegionRemix:InvalidateAllCaches()
	self.cache.sets = {}
	self.cache.mounts = {}
	self.cache.toys = {}
	self.cache.pets = {}
	self.cache.titles = {}
	self.cache.transmog = {}
	self.cache.names = {}
	self.cache.slotGrid = {}
	self.cache.achievements = {}
	self.cache.achievementInfo = {}
end

function LegionRemix:GetPersistentNameCache()
	local db = self:GetDB()
	if not db then return nil end
	db.itemNameCache = db.itemNameCache or {}
	return db.itemNameCache
end

function LegionRemix:GetCachedItemName(kind, id)
	if not kind or not id then return nil end
	self.cache.names = self.cache.names or {}
	local runtime = self.cache.names[kind]
	if runtime and runtime[id] then return runtime[id] end
	local persistent = self:GetPersistentNameCache()
	if persistent and persistent[kind] and persistent[kind][id] then
		runtime = runtime or {}
		self.cache.names[kind] = runtime
		runtime[id] = persistent[kind][id]
		return runtime[id]
	end
	return nil
end

function LegionRemix:SetCachedItemName(kind, id, name)
	if not kind or not id or not name or name == "" then return end
	self.cache.names = self.cache.names or {}
	local runtime = self.cache.names[kind]
	if not runtime then
		runtime = {}
		self.cache.names[kind] = runtime
	end
	runtime[id] = name
	local persistent = self:GetPersistentNameCache()
	if persistent then
		persistent[kind] = persistent[kind] or {}
		persistent[kind][id] = name
	end
end

function LegionRemix:ClearPersistentNameCache()
	self.cache.names = {}
	local db = self:GetDB()
	if not db or not db.itemNameCache then return end
	clearTable(db.itemNameCache)
end

local function ensureTable(tbl) return tbl or {} end

function LegionRemix:GetPlayerClass()
	if not self.playerClass then
		local _, class = UnitClass("player")
		self.playerClass = class
	end
	return self.playerClass
end

function LegionRemix:GetDB()
	local db = getProfile()
	self:EnsurePhaseFilterDefaults(db)
	self:EnsureCategoryFilterDefaults(db)
	self:EnsureZoneFilterDefaults(db)
	return db
end

function LegionRemix:EnsurePhaseFilterDefaults(db)
	if not db then return end
	local filters = db.phaseFilters
	if type(filters) ~= "table" then
		filters = {}
		db.phaseFilters = filters
	end
	local hasNumeric = false
	for key in pairs(filters) do
		if type(key) == "number" then
			hasNumeric = true
			break
		end
	end
	if hasNumeric then
		filters = { mode = "all" }
		db.phaseFilters = filters
	end
	local mode = filters.mode
	if mode ~= "current" and mode ~= "all" then filters.mode = "all" end
end

function LegionRemix:EnsureCategoryFilterDefaults(db)
	db = db or self:GetDB()
	if not db then return end
	db.categoryFilters = db.categoryFilters or {}
	for _, category in ipairs(CATEGORY_DATA) do
		if db.categoryFilters[category.key] == true then db.categoryFilters[category.key] = nil end
	end
end

function LegionRemix:EnsureZoneFilterDefaults(db)
	db = db or self:GetDB()
	if not db then return end
	local filters = db.zoneFilters or {}
	db.zoneFilters = filters
	if filters.any then
		db.zoneFilters = {}
		filters = db.zoneFilters
	end
	for key, value in pairs(filters) do
		if not SUPPORTED_ZONE_LOOKUP[key] or value ~= true then filters[key] = nil end
	end
	self:InitializeZoneTypes()
end

function LegionRemix:GetCategoryOptions()
	local options = {}
	for _, category in ipairs(CATEGORY_DATA) do
		options[category.key] = category.label
	end
	return options
end

function LegionRemix:IsCategoryVisible(key)
	local db = self:GetDB()
	if not db then return true end
	local filters = db.categoryFilters or {}
	if filters[key] == nil then return true end
	return filters[key]
end

function LegionRemix:SetCategoryVisibility(key, visible)
	local db = self:GetDB()
	if not db then return end
	db.categoryFilters = db.categoryFilters or {}
	if visible then
		db.categoryFilters[key] = nil
	else
		db.categoryFilters[key] = false
	end
	self:RefreshData()
end

function LegionRemix:ResetCategoryFilters()
	local db = self:GetDB()
	if not db then return end
	db.categoryFilters = {}
	self:EnsureCategoryFilterDefaults(db)
	self:RefreshData()
end

function LegionRemix:GetZoneCategory()
	local instanceType, difficultyID
	if type(GetInstanceInfo) == "function" then
		local _, instType, diffID = GetInstanceInfo()
		instanceType = instType
		difficultyID = diffID
	end

	local key = difficultyID and DIFFICULTY_TO_ZONE_KEY[difficultyID] or nil
	if not key and instanceType then key = INSTANCE_TYPE_ZONE_FALLBACK[instanceType] end
	if not key then key = "other" end

	self.zoneTypeLabels = self.zoneTypeLabels or {}
	self.zoneTypeLabels[key] = self:GetZoneTypeLabel(key)
	return key
end

function LegionRemix:InitializeZoneTypes()
	self.zoneTypeLabels = self.zoneTypeLabels or {}
	for _, key in ipairs(SUPPORTED_ZONE_TYPES) do
		self.zoneTypeLabels[key] = self:GetZoneTypeLabel(key)
	end
	self.zoneTypeLabels.other = self:GetZoneTypeLabel("other")
end

function LegionRemix:GetZoneFilterOptions()
	self:InitializeZoneTypes()
	local options = {}
	for _, key in ipairs(SUPPORTED_ZONE_TYPES) do
		options[key] = self:GetZoneTypeLabel(key)
	end
	return options
end

function LegionRemix:GetZoneFilterOrder()
	local order = {}
	for _, key in ipairs(SUPPORTED_ZONE_TYPES) do
		table.insert(order, key)
	end
	return order
end

function LegionRemix:GetActiveZoneFilters()
	local db = self:GetDB()
	local filters = {}
	for key, enabled in pairs(db.zoneFilters or {}) do
		if enabled and SUPPORTED_ZONE_LOOKUP[key] then filters[key] = true end
	end
	return filters, next(filters) ~= nil
end

function LegionRemix:IsZoneFilterEnabled(key)
	local db = self:GetDB()
	local filters = db.zoneFilters or {}
	if not SUPPORTED_ZONE_LOOKUP[key] then return false end
	if not next(filters) then return false end
	return filters[key] and true or false
end

function LegionRemix:SetZoneFilter(key, enabled)
	if not SUPPORTED_ZONE_LOOKUP[key] then return end
	local db = self:GetDB()
	if not db then return end
	db.zoneFilters = db.zoneFilters or {}
	if enabled then
		db.zoneFilters[key] = true
	else
		db.zoneFilters[key] = nil
	end
	self:UpdateOverlay()
end

function LegionRemix:ResetZoneFilters()
	local db = self:GetDB()
	if not db then return end
	db.zoneFilters = {}
	self:EnsureZoneFilterDefaults(db)
	self:UpdateOverlay()
end

function LegionRemix:LayoutFilterButtons()
	if not self.overlay or not self.overlay.filterBar then return end
	local bar = self.overlay.filterBar
	local buttons = bar.buttons
	if not buttons or #buttons == 0 then
		bar:SetHeight(0)
		bar.hasButtons = false
		return
	end

	local width = bar:GetWidth()
	if width <= 0 and self.overlay then width = self.overlay:GetWidth() - 32 end
	if width <= 0 then width = 280 end

	local spacing = 6
	local x, y = 0, 0
	local rowHeight = 0
	local rows = 1

	for _, btn in ipairs(buttons) do
		btn:ClearAllPoints()
		local btnWidth = btn:GetWidth()
		local btnHeight = btn:GetHeight()
		rowHeight = math.max(rowHeight, btnHeight)
		if x > 0 and (x + btnWidth) > width then
			x = 0
			y = y - (rowHeight + spacing)
			rows = rows + 1
		end
		btn:SetPoint("TOPLEFT", bar, "TOPLEFT", x, y)
		x = x + btnWidth + spacing
	end

	local newHeight = rows * rowHeight + (rows - 1) * spacing
	bar:SetHeight(newHeight)
	bar.hasButtons = true

	if self.overlay and self.overlay.content then
		self.overlay.content:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -10)
		self.overlay.content:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -10)
	end
end

function LegionRemix:UpdateContentWidth()
	if not self.overlay or not self.overlay.scrollFrame or not self.overlay.content then return end
	local width = self.overlay.scrollFrame:GetWidth()
	if width <= 0 then width = (self.overlay:GetWidth() or 0) - 32 end
	if width < 100 then width = 100 end
	self.overlay.content:SetWidth(width)
end

function LegionRemix:RefreshLockButton()
	if not self.overlay or not self.overlay.lockButton then return end
	local db = self:GetDB()
	local locked = db and db.locked
	local iconPath = locked and "Interface\\AddOns\\EnhanceQoL\\Icons\\ClosedLock.tga" or "Interface\\AddOns\\EnhanceQoL\\Icons\\OpenLock.tga"
	self.overlay.lockButton.icon:SetTexture(iconPath)
	self.overlay.lockButton.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	self.overlay.lockButton:SetBackdropColor(locked and 0.12 or 0.05, 0.15, locked and 0.04 or 0.06, 0.88)
	self.overlay.lockButton:SetBackdropBorderColor(locked and 0.32 or 0.18, locked and 0.52 or 0.48, 0.12, 0.75)
	self.overlay.lockButton.tooltipText = locked and UNLOCK or LOCK
end

function LegionRemix:PlayerHasMount(mountId)
	if not mountId then return false end
	local cache = ensureTable(self.cache.mounts)
	self.cache.mounts = cache
	if cache[mountId] ~= nil then return cache[mountId] end
	local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountId)
	cache[mountId] = isCollected and true or false
	return cache[mountId]
end

function LegionRemix:PlayerHasToy(itemId)
	if not itemId then return false end
	local cache = ensureTable(self.cache.toys)
	self.cache.toys = cache
	if cache[itemId] ~= nil then return cache[itemId] end
	cache[itemId] = PlayerHasToy(itemId) and true or false
	return cache[itemId]
end

function LegionRemix:PlayerHasPet(speciesId)
	if not speciesId then return false end
	local cache = ensureTable(self.cache.pets)
	self.cache.pets = cache
	if cache[speciesId] ~= nil then return cache[speciesId] end
	local collected = C_PetJournal.GetNumCollectedInfo(speciesId)
	cache[speciesId] = (collected and collected > 0) and true or false
	return cache[speciesId]
end

function LegionRemix:PlayerHasTitle(titleId)
	if not titleId then return false end
	local cache = ensureTable(self.cache.titles)
	self.cache.titles = cache
	if cache[titleId] ~= nil then return cache[titleId] end
	local known = false
	if IsTitleKnown then known = IsTitleKnown(titleId) end
	cache[titleId] = known and true or false
	return cache[titleId]
end

function LegionRemix:PlayerHasAchievement(achievementId)
	if not achievementId then return false end
	local cache = ensureTable(self.cache.achievements)
	self.cache.achievements = cache
	if cache[achievementId] ~= nil then return cache[achievementId] end
	local _, _, _, completed = GetAchievementInfo(achievementId)
	cache[achievementId] = completed and true or false
	return cache[achievementId]
end

function LegionRemix:GetAchievementDetails(achievementId)
	if not achievementId then return nil end
	self.cache.achievementInfo = self.cache.achievementInfo or {}
	local info = self.cache.achievementInfo[achievementId]
	if info then
		if info.completed == nil then info.completed = self:PlayerHasAchievement(achievementId) end
		return info.name, info.completed
	end
	local _, name, _, completed = GetAchievementInfo(achievementId)
	if not name or name == "" then name = string.format(L["Achievement #%d"], achievementId) end
	info = { name = name, completed = completed and true or false }
	self.cache.achievementInfo[achievementId] = info
	self.cache.achievements = ensureTable(self.cache.achievements)
	self.cache.achievements[achievementId] = info.completed
	return info.name, info.completed
end

function LegionRemix:CollectSlotGrid(setId)
	local cache = ensureTable(self.cache.slotGrid)
	self.cache.slotGrid = cache
	if cache[setId] then return cache[setId] end
	local grid = {}
	local setSourceIds = C_TransmogSets.GetAllSourceIDs(setId)
	if setSourceIds then
		for _, sourceID in ipairs(setSourceIds) do
			local categoryID, _, _, _, isCollected = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
			if categoryID then
				if isCollected then
					grid[categoryID] = true
				elseif grid[categoryID] == nil then
					grid[categoryID] = false
				end
			end
		end
	end
	cache[setId] = grid
	return grid
end

function LegionRemix:IsSetUsable(setId)
	local _, className = UnitClass("player")
	if not className or not setId then return false end
	local info = C_TransmogSets.GetSetInfo(setId)
	if not info then return false end
	local mask = CLASS_MASKS[className]
	if not mask then return false end
	return bit.band(info.classMask or 0, mask) ~= 0
end

function LegionRemix:PlayerHasSet(setId)
	if not setId then return false end
	local cache = ensureTable(self.cache.sets)
	self.cache.sets = cache
	if cache[setId] ~= nil then return cache[setId] end

	local setInfo = C_TransmogSets.GetSetInfo(setId)
	if setInfo and setInfo.collected then
		cache[setId] = true
		return true
	end

	local primaryAppearances = C_TransmogSets.GetSetPrimaryAppearances(setId)
	if not primaryAppearances or #primaryAppearances == 0 then
		cache[setId] = false
		return false
	end

	local missingSlots = {}
	for _, appearance in ipairs(primaryAppearances) do
		local categoryID, _, _, _, isCollected = C_TransmogCollection.GetAppearanceSourceInfo(appearance.appearanceID)
		if not isCollected then table.insert(missingSlots, categoryID) end
	end

	if #missingSlots == 0 then
		cache[setId] = true
		return true
	end

	local db = self:GetDB()
	if not (db and db.enhancedTracking) then
		cache[setId] = false
		return false
	end

	local slotInfo = self:CollectSlotGrid(setId)
	for _, slot in ipairs(missingSlots) do
		if not slotInfo[slot] then
			cache[setId] = false
			return false
		end
	end

	cache[setId] = true
	return true
end

function LegionRemix:PlayerHasTransmog(itemId, mod)
	if not itemId then return false end
	if nil == mod then mod = 1 end
	local cache = ensureTable(self.cache.transmog)
	self.cache.transmog = cache
	if cache[itemId] ~= nil then return cache[itemId] end
	cache[itemId] = C_TransmogCollection.PlayerHasTransmog(itemId, mod) and true or false
	return cache[itemId]
end

local function accumulatePhase(target, phase, cost, owned)
	if not phase or not target then return end
	local bucket = target[phase]
	if not bucket then
		bucket = { totalCost = 0, collectedCost = 0, totalCount = 0, collectedCount = 0 }
		target[phase] = bucket
	end
	bucket.totalCost = bucket.totalCost + cost
	bucket.totalCount = bucket.totalCount + 1
	if owned then
		bucket.collectedCost = bucket.collectedCost + cost
		bucket.collectedCount = bucket.collectedCount + 1
	end
end

local function addItemResult(result, owned, cost, entry)
	result.totalCost = result.totalCost + cost
	result.totalCount = result.totalCount + 1
	local phaseKind = entry.phaseKind or entry.kind
	local phaseId = entry.phaseId or entry.id
	local phase = LegionRemix:GetPhaseFor(phaseKind, phaseId)
	if phase then
		result.phaseTotals = result.phaseTotals or {}
		accumulatePhase(result.phaseTotals, phase, cost, owned)
		LegionRemix.phaseTotals = LegionRemix.phaseTotals or {}
		accumulatePhase(LegionRemix.phaseTotals, phase, cost, owned)
	end
	if owned then
		result.collectedCost = result.collectedCost + cost
		result.collectedCount = result.collectedCount + 1
	else
		entry.cost = cost
		entry.phase = phase
		table.insert(result.missing, entry)
	end
end

function LegionRemix:ProcessSetList(result, list, cost, requirements)
	if not list or #list == 0 then return end
	for _, setId in ipairs(list) do
		local owned = self:PlayerHasSet(setId)
		local entry = { kind = "set", id = setId }
		if requirements then
			local requiredAchievement = requirements[setId]
			if requiredAchievement then
				entry.requiredAchievement = requiredAchievement
				entry.requirementComplete = self:PlayerHasAchievement(requiredAchievement)
			end
		end
		addItemResult(result, owned, cost, entry)
	end
end

function LegionRemix:ProcessGroup(categoryResult, group)
	if group.type == "set_achievement" then
		local cost = group.cost or 0
		local db = self:GetDB()
		local requirements = group.requirements
		if db and db.classOnly then
			local filtered = {}
			for _, setId in ipairs(group.items or {}) do
				if self:IsSetUsable(setId) then table.insert(filtered, setId) end
			end
			self:ProcessSetList(categoryResult, filtered, cost, requirements)
		else
			self:ProcessSetList(categoryResult, group.items or {}, cost, requirements)
		end
		return
	end
	if group.type == "set_achievement_item" then
		local cost = group.cost or 0
		local requirements = group.requirements
		local itemAppearanceModID = group.mod or 1
		for _, itemId in ipairs(group.items) do
			local entry = { kind = "transmog", id = itemId }
			if requirements then
				local requiredAchievement = requirements[itemId]
				if requiredAchievement then
					entry.requiredAchievement = requiredAchievement
					entry.requirementComplete = self:PlayerHasAchievement(requiredAchievement)
				end
			end
			local owned = self:PlayerHasTransmog(itemId, itemAppearanceModID)
			addItemResult(categoryResult, owned, cost, entry)
		end
		return
	end

	if group.type == "set_achievement_pet" then
		local cost = group.cost or 0
		local requirements = group.requirements
		for _, speciesId in ipairs(group.items) do
			local entry = { kind = "pet", id = speciesId }
			local owned = self:PlayerHasPet(speciesId)
			if requirements then
				local requiredAchievement = requirements[speciesId]
				if requiredAchievement then
					entry.requiredAchievement = requiredAchievement
					entry.requirementComplete = self:PlayerHasAchievement(requiredAchievement)
				end
			end
			addItemResult(categoryResult, owned, cost, entry)
		end
		return
	end

	if group.type == "achievement" then
		local cost = group.cost or 0
		local items = group.items or {}
		if type(items) ~= "table" then return end
		for _, achievementData in ipairs(items) do
			local achievementId = achievementData
			local entryOptions = nil
			if type(achievementData) == "table" then
				entryOptions = achievementData
				achievementId = achievementData.id or achievementData.achievementId or achievementData.achievementID or achievementData.achievement
			end
			if achievementId then
				achievementId = tonumber(achievementId) or achievementId
				local owned = self:PlayerHasAchievement(achievementId)
				local entry = { kind = "achievement", id = achievementId }
				if entryOptions then
					if entryOptions.phaseKind then entry.phaseKind = entryOptions.phaseKind end
					if entryOptions.phaseId ~= nil then
						local phaseId = tonumber(entryOptions.phaseId) or entryOptions.phaseId
						entry.phaseId = phaseId
					end
				end
				addItemResult(categoryResult, owned, cost, entry)
			end
		end
		return
	end

	if group.type == "title" then
		local cost = group.cost or 0
		local items = group.items or {}
		if type(items) ~= "table" then return end
		for _, titleData in ipairs(items) do
			local titleId = titleData
			local name
			local achievementId, phaseKindOverride, phaseIdOverride
			if type(titleData) == "table" then
				titleId = titleData.id or titleData.titleId or titleData.titleID
				achievementId = titleData.achievementId or titleData.achievementID or titleData.achievement
				name = titleData.name or titleId
				if titleData.phaseKind then phaseKindOverride = titleData.phaseKind end
				if titleData.phaseId then phaseIdOverride = titleData.phaseId end
			end
			if titleId then
				titleId = tonumber(titleId) or titleId
				local owned = self:PlayerHasTitle(titleId)
				local entry = { kind = "title", id = titleId, name = name }
				if achievementId then
					achievementId = tonumber(achievementId)
					if achievementId then
						entry.requiredAchievement = achievementId
						entry.requirementComplete = self:PlayerHasAchievement(achievementId)
						if entry.requirementComplete then owned = true end
						entry.phaseKind = entry.phaseKind or "achievement"
						entry.phaseId = entry.phaseId or achievementId
					end
				end
				if phaseKindOverride then entry.phaseKind = phaseKindOverride end
				if phaseIdOverride ~= nil then
					local phaseIdValue = tonumber(phaseIdOverride) or phaseIdOverride
					entry.phaseId = phaseIdValue
				end
				addItemResult(categoryResult, owned, cost, entry)
			end
		end
		return
	end

	local cost = group.cost or 0
	if cost <= 0 then return end

	if group.type == "mount" then
		for _, mountId in ipairs(group.items) do
			local owned = self:PlayerHasMount(mountId)
			addItemResult(categoryResult, owned, cost, { kind = "mount", id = mountId })
		end
	elseif group.type == "toy" then
		for _, toyId in ipairs(group.items) do
			local owned = self:PlayerHasToy(toyId)
			addItemResult(categoryResult, owned, cost, { kind = "toy", id = toyId })
		end
	elseif group.type == "pet" then
		for _, speciesId in ipairs(group.items) do
			local owned = self:PlayerHasPet(speciesId)
			addItemResult(categoryResult, owned, cost, { kind = "pet", id = speciesId })
		end
	elseif group.type == "transmog" then
		for _, itemId in ipairs(group.items) do
			local owned = self:PlayerHasTransmog(itemId)
			addItemResult(categoryResult, owned, cost, { kind = "transmog", id = itemId })
		end
	elseif group.type == "set_per_class" then
		local db = self:GetDB()
		local itemsByClass = group.itemsByClass or group.items
		if db and db.classOnly then
			local className = self:GetPlayerClass()
			self:ProcessSetList(categoryResult, itemsByClass and itemsByClass[className], cost, group.requirements)
		else
			for _, list in pairs(itemsByClass) do
				self:ProcessSetList(categoryResult, list, cost, group.requirements)
			end
		end
	elseif group.type == "set_mixed" then
		local db = self:GetDB()
		if db and db.classOnly then
			local filtered = {}
			for _, setId in ipairs(group.items) do
				if self:IsSetUsable(setId) then table.insert(filtered, setId) end
			end
			self:ProcessSetList(categoryResult, filtered, cost, group.requirements)
		else
			self:ProcessSetList(categoryResult, group.items, cost, group.requirements)
		end
	end
end

function LegionRemix:BuildCategoryData(category)
	local result = {
		key = category.key,
		label = category.label,
		collectedCost = 0,
		totalCost = 0,
		collectedCount = 0,
		totalCount = 0,
		missing = {},
	}
	for _, group in ipairs(category.groups or {}) do
		self:ProcessGroup(result, group)
	end
	result.remainingCost = result.totalCost - result.collectedCost
	if result.remainingCost < 0 then result.remainingCost = 0 end
	table.sort(result.missing, function(a, b)
		if a.cost == b.cost then return (a.id or 0) < (b.id or 0) end
		return a.cost > b.cost
	end)
	if result.phaseTotals and not next(result.phaseTotals) then result.phaseTotals = nil end
	return result
end

function LegionRemix:BuildCategoryDisplay(categoryData)
	local filters, allActive = self:GetActivePhaseFilterSet()
	local display = {
		key = categoryData.key,
		label = categoryData.label,
		phaseTotals = categoryData.phaseTotals,
		original = categoryData,
		missing = categoryData.missing,
	}

	if allActive or not categoryData.phaseTotals then
		display.collectedCost = categoryData.collectedCost
		display.totalCost = categoryData.totalCost
		display.collectedCount = categoryData.collectedCount
		display.totalCount = categoryData.totalCount
		display.filteredMissing = categoryData.missing
		display.showAllPhases = true
		return display
	end

	local collectedCost, totalCost, collectedCount, totalCount = 0, 0, 0, 0
	for phase, totals in pairs(categoryData.phaseTotals) do
		if filters[phase] then
			collectedCost = collectedCost + (totals.collectedCost or 0)
			totalCost = totalCost + (totals.totalCost or 0)
			collectedCount = collectedCount + (totals.collectedCount or 0)
			totalCount = totalCount + (totals.totalCount or 0)
		end
	end

	local filteredMissing = {}
	for _, entry in ipairs(categoryData.missing or {}) do
		if not entry.phase or filters[entry.phase] then table.insert(filteredMissing, entry) end
	end

	display.collectedCost = collectedCost
	display.totalCost = totalCost
	display.collectedCount = collectedCount
	display.totalCount = totalCount
	display.filteredMissing = filteredMissing
	display.showAllPhases = false
	return display
end

function LegionRemix:IsCategoryCompleteForDisplay(display)
	if not display then return false end
	local missing = display.filteredMissing
	if missing then
		if next(missing) ~= nil then return false end
	else
		missing = display.missing
		if missing and next(missing) ~= nil then return false end
	end
	local totalCount = display.totalCount or 0
	local collectedCount = display.collectedCount or 0
	if totalCount > 0 and collectedCount < totalCount then return false end
	local totalCost = display.totalCost or 0
	local collectedCost = display.collectedCost or 0
	if totalCost > 0 and collectedCost < totalCost then return false end
	return true
end

function LegionRemix:GetFilteredOverallTotals()
	local filters, allActive = self:GetActivePhaseFilterSet()
	if allActive or not self.phaseTotals then return self.totalCollected or 0, self.totalCost or 0 end
	local collected, total = 0, 0
	for phase, totals in pairs(self.phaseTotals) do
		if filters[phase] then
			collected = collected + (totals.collectedCost or 0)
			total = total + (totals.totalCost or 0)
		end
	end
	return collected, total
end

function LegionRemix:RefreshData()
	if not addon.db then return end
	local db = self:GetDB()
	if not self:IsActive(db) then
		self.phaseTotals = {}
		LegionRemix.phaseTotals = self.phaseTotals
		self.latestCategories = {}
		self.totalCost = 0
		self.totalCollected = 0
		self:UpdateOverlay()
		return
	end
	self.phaseTotals = {}
	LegionRemix.phaseTotals = self.phaseTotals
	local categories = {}
	local totalCost, totalCollected = 0, 0
	for _, category in ipairs(CATEGORY_DATA) do
		if self:IsCategoryVisible(category.key) then
			local data = self:BuildCategoryData(category)
			table.insert(categories, data)
			totalCost = totalCost + data.totalCost
			totalCollected = totalCollected + data.collectedCost
		end
	end
	self.latestCategories = categories
	self.totalCost = totalCost
	self.totalCollected = totalCollected
	self:UpdateOverlay()
end

function LegionRemix:GetBronzeCurrency()
	local info = C_CurrencyInfo.GetCurrencyInfo(BRONZE_CURRENCY_ID)
	return info and info.quantity or 0
end

function LegionRemix:IsInLegionRemixZone()
	local filters, hasSelection = self:GetActiveZoneFilters()
	if not hasSelection then return true end
	local zoneType = self:GetZoneCategory()
	if not zoneType then return false end
	return filters[zoneType] and true or false
end

function LegionRemix:IsTimerunner() return addon and addon.functions and addon.functions.IsTimerunner and addon.functions.IsTimerunner() or false end

function LegionRemix:IsOverlaySettingEnabled(db)
	db = db or self:GetDB()
	return db and db.overlayEnabled and true or false
end

function LegionRemix:IsActive(db)
	db = db or self:GetDB()
	if not self:IsOverlaySettingEnabled(db) then return false end
	if not self:IsTimerunner() then return false end
	return true
end

function LegionRemix:UpdateActivationState()
	if not addon or not addon.db then return end
	local db = self:GetDB()
	local shouldActivate = self:IsActive(db)
	if shouldActivate then
		if not self.eventsRegistered then self:RegisterEvents() end
		if not self.active then
			self.active = true
			self:InvalidateAllCaches()
			self:RefreshData()
		else
			self:UpdateOverlay()
		end
	else
		if self.eventsRegistered then self:UnregisterEvents() end
		if self.active then self.active = false end
		if self.overlay then self.overlay:Hide() end
	end
end

function LegionRemix:ShouldOverlayBeVisible()
	local db = self:GetDB()
	if not self:IsActive(db) then return false end
	if db.overlayHidden then return false end
	return self:IsInLegionRemixZone()
end

local function resolveParentPointCoordinates(left, bottom, width, height, point)
	if point == "TOPLEFT" then
		return left, bottom + height
	elseif point == "TOP" then
		return left + (width * 0.5), bottom + height
	elseif point == "TOPRIGHT" then
		return left + width, bottom + height
	elseif point == "LEFT" then
		return left, bottom + (height * 0.5)
	elseif point == "CENTER" then
		return left + (width * 0.5), bottom + (height * 0.5)
	elseif point == "RIGHT" then
		return left + width, bottom + (height * 0.5)
	elseif point == "BOTTOMLEFT" then
		return left, bottom
	elseif point == "BOTTOM" then
		return left + (width * 0.5), bottom
	elseif point == "BOTTOMRIGHT" then
		return left + width, bottom
	end
	return left + (width * 0.5), bottom + (height * 0.5)
end

local function resolveFrameAnchorOffset(point, width, height)
	if point == "TOPLEFT" then
		return 0, 0
	elseif point == "TOP" then
		return width * 0.5, 0
	elseif point == "TOPRIGHT" then
		return width, 0
	elseif point == "LEFT" then
		return 0, height * 0.5
	elseif point == "CENTER" then
		return width * 0.5, height * 0.5
	elseif point == "RIGHT" then
		return width, height * 0.5
	elseif point == "BOTTOMLEFT" then
		return 0, height
	elseif point == "BOTTOM" then
		return width * 0.5, height
	elseif point == "BOTTOMRIGHT" then
		return width, height
	end
	return width * 0.5, height * 0.5
end

local function computeTopLeftOffset(frame, parent, point, relativePoint, offsetX, offsetY)
	if not (frame and parent) then return nil, nil end

	point = point or "TOPLEFT"
	relativePoint = relativePoint or point

	local parentScale = parent.GetEffectiveScale and parent:GetEffectiveScale() or 1
	local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
	if not parentScale or parentScale == 0 then parentScale = 1 end
	if not frameScale or frameScale == 0 then frameScale = 1 end

	local parentLeft = (parent.GetLeft and parent:GetLeft() or 0) * parentScale
	local parentBottom = (parent.GetBottom and parent:GetBottom() or 0) * parentScale
	local parentWidth = (parent.GetWidth and parent:GetWidth() or 0) * parentScale
	local parentHeight = (parent.GetHeight and parent:GetHeight() or 0) * parentScale
	if parentWidth == 0 or parentHeight == 0 then return nil, nil end

	local baseX, baseY = resolveParentPointCoordinates(parentLeft, parentBottom, parentWidth, parentHeight, relativePoint)

	local anchorX = (baseX or 0) + (offsetX or 0) * parentScale
	local anchorY = (baseY or 0) + (offsetY or 0) * parentScale

	local frameWidth = (frame.GetWidth and frame:GetWidth() or 0) * frameScale
	local frameHeight = (frame.GetHeight and frame:GetHeight() or 0) * frameScale
	local anchorOffsetX, anchorOffsetY = resolveFrameAnchorOffset(point, frameWidth, frameHeight)

	local topLeftX = anchorX - anchorOffsetX
	local topLeftY = anchorY + anchorOffsetY

	local parentTopLeftX = parentLeft
	local parentTopLeftY = parentBottom + parentHeight

	local finalX = (topLeftX - parentTopLeftX) / parentScale
	local finalY = (topLeftY - parentTopLeftY) / parentScale

	return finalX, finalY
end

function LegionRemix:ApplyAnchor(frame)
	local db = self:GetDB()
	if not (frame and db) then return end
	db.anchor = db.anchor or CopyTable(DEFAULTS.anchor)

	local parent = UIParent

	if db.anchor.point ~= "TOPLEFT" or db.anchor.relativePoint ~= "TOPLEFT" then
		local convertedX, convertedY = computeTopLeftOffset(frame, parent, db.anchor.point, db.anchor.relativePoint, db.anchor.x or 0, db.anchor.y or 0)
		if convertedX and convertedY then
			db.anchor.point = "TOPLEFT"
			db.anchor.relativePoint = "TOPLEFT"
			db.anchor.x = convertedX
			db.anchor.y = convertedY
		end
	end

	frame:ClearAllPoints()
	if db.anchor.point == "TOPLEFT" and db.anchor.relativePoint == "TOPLEFT" then
		frame:SetPoint("TOPLEFT", parent, "TOPLEFT", db.anchor.x or 0, db.anchor.y or 0)
	else
		local point = db.anchor.point or "CENTER"
		local relativePoint = db.anchor.relativePoint or point
		frame:SetPoint(point, parent, relativePoint, db.anchor.x or 0, db.anchor.y or 0)
	end
end

function LegionRemix:SaveAnchor(frame)
	if not frame then return end
	local db = self:GetDB()
	if not db then return end

	db.anchor = db.anchor or {}

	local point, relativeTo, relativePoint, x, y = frame:GetPoint()
	local parent = relativeTo or frame:GetParent() or UIParent
	if parent ~= UIParent then parent = UIParent end

	local convertedX, convertedY = computeTopLeftOffset(frame, parent, point, relativePoint, x or 0, y or 0)
	if convertedX and convertedY then
		db.anchor.point = "TOPLEFT"
		db.anchor.relativePoint = "TOPLEFT"
		db.anchor.x = convertedX
		db.anchor.y = convertedY
	else
		db.anchor.point = point or "TOPLEFT"
		db.anchor.relativePoint = relativePoint or db.anchor.point
		db.anchor.x = x or 0
		db.anchor.y = y or 0
	end
end

local function setButtonTexture(button, collapsed)
	if not button then return end
	if not button.icon then return end
	if collapsed then
		button.icon:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
	else
		button.icon:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
	end
	button.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
end

function LegionRemix:CreateCategoryRow(parent)
	local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
	row:SetHeight(42)
	row:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		tile = false,
		edgeSize = 1,
		insets = { left = 0, right = 0, top = 0, bottom = 0 },
	})
	row:SetBackdropColor(0.04, 0.06, 0.1, 0.65)
	row:SetBackdropBorderColor(0.18, 0.48, 0.82, 0.35)

	local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("TOPLEFT", 6, -6)
	label:SetPoint("RIGHT", -6, 0)
	label:SetJustifyH("LEFT")

	local count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	count:SetPoint("TOPRIGHT", -6, -6)
	count:SetWidth(90)
	count:SetJustifyH("RIGHT")
	count:SetWordWrap(false)

	local status = CreateFrame("StatusBar", nil, row)
	status:SetPoint("BOTTOMLEFT", 6, 6)
	status:SetPoint("BOTTOMRIGHT", -6, 6)
	status:SetHeight(16)
	status:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
	status:GetStatusBarTexture():SetHorizTile(false)
	status:SetMinMaxValues(0, 1)
	status:SetValue(0)
	status:SetStatusBarColor(0.18, 0.52, 0.9, 0.9)

	local statusBg = status:CreateTexture(nil, "BACKGROUND")
	statusBg:SetAllPoints()
	statusBg:SetColorTexture(0.02, 0.03, 0.06, 0.85)

	local metric = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	metric:SetPoint("CENTER", 0, 0)
	metric:SetWordWrap(false)

	row.label = label
	row.count = count
	row.status = status
	row.metric = metric

	row:SetScript("OnEnter", function(btn)
		btn:SetBackdropColor(0.08, 0.12, 0.17, 0.75)
		LegionRemix:ShowCategoryTooltip(btn)
	end)
	row:SetScript("OnLeave", function(btn)
		btn:SetBackdropColor(0.04, 0.06, 0.1, 0.65)
		GameTooltip_Hide()
	end)
	return row
end

function LegionRemix:GetRow(index, parent)
	self.rows = self.rows or {}
	local row = self.rows[index]
	if not row then
		row = self:CreateCategoryRow(parent)
		if index == 1 then
			row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
			row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
		else
			row:SetPoint("TOPLEFT", self.rows[index - 1], "BOTTOMLEFT", 0, -6)
			row:SetPoint("TOPRIGHT", self.rows[index - 1], "BOTTOMRIGHT", 0, -6)
		end
		self.rows[index] = row
	end
	row:Show()
	return row
end

local function round(value) return math.floor((value or 0) + 0.5) end

function LegionRemix:UpdateRow(row, data)
	row.displayData = data
	row.label:SetText(data.label or "")
	row.count:SetText(string.format("%s / %s", data.collectedCount or 0, data.totalCount or 0))

	local useCounts = (data.totalCost or 0) <= 0
	if useCounts then
		local totalCount = (data.totalCount or 0)
		if totalCount <= 0 then totalCount = 1 end
		row.status:SetMinMaxValues(0, totalCount)
		row.status:SetValue(data.collectedCount or 0)
		row.metric:SetText(string.format("%d / %d", data.collectedCount or 0, data.totalCount or 0))
	else
		local totalCost = data.totalCost > 0 and data.totalCost or 1
		row.status:SetMinMaxValues(0, totalCost)
		row.status:SetValue(data.collectedCost or 0)
		row.metric:SetText(string.format("%s / %s", formatBronze(data.collectedCost), formatBronze(data.totalCost)))
	end
	local metricWidth = row.status:GetWidth() - 4
	if metricWidth < 60 then metricWidth = 60 end
	row.metric:SetWidth(metricWidth)
end

function LegionRemix:HideUnusedRows(fromIndex)
	if not self.rows then return end
	for i = fromIndex, #self.rows do
		if self.rows[i] then self.rows[i]:Hide() end
	end
end

function LegionRemix:GetItemName(entry)
	if not entry then return UNKNOWN end
	local kind = entry.kind
	local id = entry.id
	local cached = self:GetCachedItemName(kind, id)
	if cached then return cached end

	if kind == "mount" then
		local name = C_MountJournal.GetMountInfoByID(id or 0)
		if name and name ~= "" then
			self:SetCachedItemName(kind, id, name)
			return name
		end
		return ("Mount #" .. tostring(id or "?"))
	elseif kind == "toy" then
		local name = select(2, C_ToyBox.GetToyInfo(id or 0))
		if name and name ~= "" then
			self:SetCachedItemName(kind, id, name)
			return name
		end
		local itemName = GetItemInfo(id or 0)
		if itemName and itemName ~= "" then
			self:SetCachedItemName(kind, id, itemName)
			return itemName
		end
		itemName = C_Item.GetItemNameByID(id or 0)
		if itemName and itemName ~= "" then
			self:SetCachedItemName(kind, id, itemName)
			return itemName
		end
		C_Item.RequestLoadItemDataByID(id or 0)
		return ("Toy #" .. tostring(id or "?"))
	elseif kind == "pet" then
		local name = select(1, C_PetJournal.GetPetInfoBySpeciesID(id or 0))
		if name and name ~= "" then
			self:SetCachedItemName(kind, id, name)
			return name
		end
		return ("Pet #" .. tostring(id or "?"))
	elseif kind == "achievement" then
		local achievementId = tonumber(id) or id
		if achievementId then
			local name = select(1, self:GetAchievementDetails(achievementId))
			if name and name ~= "" then
				self:SetCachedItemName(kind, id, name)
				return name
			end
			local _, fallback = GetAchievementInfo(achievementId)
			if fallback and fallback ~= "" then
				self:SetCachedItemName(kind, id, fallback)
				return fallback
			end
		end
		return ("Achievement #" .. tostring(id or "?"))
	elseif kind == "title" then
		local titleId = tonumber(id) or id
		local name
		if entry.name then
			name = entry.name
		else
			if titleId then
				if C_TitleManager and C_TitleManager.GetTitleName then
					name = C_TitleManager.GetTitleName(titleId)
				elseif GetTitleName then
					name = GetTitleName(titleId)
				end
			end
		end
		if name and name ~= "" then
			self:SetCachedItemName(kind, id, name)
			return name
		end
		return ("Title #" .. tostring(id or "?"))
	elseif kind == "set" then
		local info = C_TransmogSets.GetSetInfo(id or 0)
		if info and info.name and info.name ~= "" then
			self:SetCachedItemName(kind, id, info.name)
			return info.name
		end
		return ("Set #" .. tostring(id or "?"))
	elseif kind == "transmog" then
		local name = GetItemInfo(id or 0)
		if name and name ~= "" then
			self:SetCachedItemName(kind, id, name)
			return name
		end
		local itemName = C_Item.GetItemNameByID(id or 0)
		if itemName and itemName ~= "" then
			self:SetCachedItemName(kind, id, itemName)
			return itemName
		end
		C_Item.RequestLoadItemDataByID(id or 0)
		return ("Item #" .. tostring(id or "?"))
	end
	return UNKNOWN
end

function LegionRemix:ShowCategoryTooltip(row)
	if not row or not row:IsVisible() then return end
	local data = row.displayData or row.data
	if not data then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(data.label or "")
	GameTooltip:AddDoubleLine(ITEMS, string.format("%d / %d", data.collectedCount or 0, data.totalCount or 0), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
	GameTooltip:AddDoubleLine(L["Bronze"], string.format("%s / %s", formatBronze(data.collectedCost), formatBronze(data.totalCost)), 0.8, 0.8, 0.8, 0.9, 0.9, 0.9)
	GameTooltip:AddLine(" ")
	local missing = data.filteredMissing or data.missing or {}
	if #missing == 0 then
		GameTooltip:AddLine(L["All items collected."], 0.4, 1, 0.4)
	else
		GameTooltip:AddLine(L["Missing items:"], 1, 0.82, 0)
		local maxEntries = 12
		for i = 1, math.min(maxEntries, #missing) do
			local entry = missing[i]
			local label = self:GetItemName(entry)
			if entry.phase then label = string.format("%s (%s)", label, string.format(L["Phase %d"], entry.phase)) end
			local costDisplay = (entry.cost and entry.cost > 0) and formatBronze(entry.cost) or ""
			GameTooltip:AddDoubleLine(label, costDisplay, 0.9, 0.9, 0.9, 0.7, 0.9, 0.7)
			if entry.requiredAchievement then
				local achievementName, completed = self:GetAchievementDetails(entry.requiredAchievement)
				if not achievementName or achievementName == "" then achievementName = string.format(L["Achievement #%d"], entry.requiredAchievement) end
				local requirementLabel = string.format(L["Requires: %s"], achievementName)
				local statusText = completed and CRITERIA_COMPLETED or CRITERIA_NOT_COMPLETED
				local statusR, statusG, statusB
				if completed then
					statusR, statusG, statusB = 0.4, 1, 0.4
				else
					statusR, statusG, statusB = 1, 0.45, 0.45
				end
				GameTooltip:AddDoubleLine("  " .. requirementLabel, statusText, 0.7, 0.85, 1, statusR, statusG, statusB)
			end
		end
		if #missing > maxEntries then GameTooltip:AddLine(string.format(L["+ %d more..."], #missing - maxEntries), 0.5, 0.5, 0.5) end
	end
	GameTooltip:Show()
end

function LegionRemix:CreateOverlay()
	if self.overlay then return self.overlay end

	local frame = CreateFrame("Frame", "EnhanceQoLLegionRemixOverlay", UIParent, "BackdropTemplate")
	frame:SetSize(360, 520)
	frame.expandedHeight = 520
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0.018, 0.02, 0.04, 0.92)
	frame:SetBackdropBorderColor(0.12, 0.32, 0.62, 0.85)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(f)
		local db = LegionRemix:GetDB()
		if db and db.locked then return end
		f:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		LegionRemix:SaveAnchor(f)
	end)
	local scale = tonumber(self:GetOverlayScale()) or DEFAULTS.overlayScale or 1
	if scale <= 0 then scale = DEFAULTS.overlayScale or 1 end
	frame:SetScale(scale)
	frame:SetFrameStrata("HIGH")

	local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	header:SetPoint("TOPLEFT", 10, -10)
	header:SetPoint("TOPRIGHT", -10, -10)
	header:SetHeight(52)
	header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	header:SetBackdropColor(0.06, 0.07, 0.12, 0.95)

	local title = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	title:SetPoint("TOPLEFT", 12, -8)
	title:SetJustifyH("LEFT")
	title:SetText(L["Legion Remix Collection"])

	local bronzeText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bronzeText:SetPoint("BOTTOMLEFT", 12, 10)
	bronzeText:SetJustifyH("LEFT")
	bronzeText:SetWordWrap(false)

	local remainingText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	remainingText:SetPoint("BOTTOMRIGHT", -12, 10)
	remainingText:SetJustifyH("RIGHT")
	remainingText:SetWordWrap(false)

	local function createHeaderButton(width, height)
		local btn = CreateFrame("Button", nil, header, "BackdropTemplate")
		btn:SetSize(width, height)
		btn:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
			insets = { left = 1, right = 1, top = 1, bottom = 1 },
		})
		btn:SetBackdropColor(0.05, 0.06, 0.1, 0.88)
		btn:SetBackdropBorderColor(0.18, 0.48, 0.82, 0.7)
		btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		local icon = btn:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("CENTER")
		icon:SetSize(width - 6, height - 6)
		btn.icon = icon
		return btn
	end

	local closeButton = createHeaderButton(26, 26)
	closeButton:SetPoint("TOPRIGHT", -4, -4)
	closeButton.icon:SetTexture("Interface\\Buttons\\UI-StopButton")
	closeButton.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
	closeButton.tooltipText = CLOSE
	closeButton:SetScript("OnClick", function()
		local db = LegionRemix:GetDB()
		if db then db.overlayHidden = true end
		LegionRemix:UpdateOverlay()
	end)
	closeButton:SetScript("OnEnter", function(btn)
		GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
		GameTooltip:SetText(btn.tooltipText or CLOSE)
	end)
	closeButton:SetScript("OnLeave", GameTooltip_Hide)

	local lockButton = createHeaderButton(28, 26)
	lockButton:SetPoint("RIGHT", closeButton, "LEFT", -6, 0)
	lockButton.tooltipText = LOCK
	lockButton:SetScript("OnEnter", function(btn)
		GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
		GameTooltip:SetText(btn.tooltipText or LOCK)
	end)
	lockButton:SetScript("OnLeave", GameTooltip_Hide)
	lockButton:SetScript("OnClick", function()
		local db = LegionRemix:GetDB()
		if not db then return end
		db.locked = not db.locked
		LegionRemix:RefreshLockButton()
	end)

	local collapse = createHeaderButton(26, 26)
	collapse:SetPoint("RIGHT", lockButton, "LEFT", -6, 0)
	collapse.tooltipText = HERO_TALENTS_COLLAPSE
	collapse:SetScript("OnEnter", function(btn)
		GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
		GameTooltip:SetText(btn.tooltipText or HERO_TALENTS_COLLAPSE)
	end)
	collapse:SetScript("OnLeave", GameTooltip_Hide)
	collapse:SetScript("OnClick", function()
		local db = LegionRemix:GetDB()
		if not db then return end
		db.collapsed = not db.collapsed
		setButtonTexture(collapse, db.collapsed)
		LegionRemix:UpdateOverlay()
	end)

	local filterBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	filterBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
	filterBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -6)
	filterBar:SetHeight(24)
	filterBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	filterBar:SetBackdropColor(0.03, 0.03, 0.06, 0.78)

	local content = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	content:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -10)
	content:SetPoint("TOPRIGHT", filterBar, "BOTTOMRIGHT", 0, -10)
	content:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 16)
	content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 16)

	-- local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	-- scrollFrame:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -10)
	-- scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 16)
	-- scrollFrame:SetClipsChildren(true)
	-- scrollFrame:HookScript("OnSizeChanged", function() LegionRemix:UpdateContentWidth() end)
	-- scrollFrame.ScrollBar:Hide()

	-- local content = CreateFrame("Frame", nil, scrollFrame)
	-- content:SetPoint("TOPLEFT")
	-- content:SetSize(1, 1)
	-- scrollFrame:SetScrollChild(content)

	frame.collapsedHeight = header:GetHeight() + 20
	frame.header = header
	frame.title = title
	frame.bronzeText = bronzeText
	frame.remainingText = remainingText
	frame.collapseButton = collapse
	frame.closeButton = closeButton
	frame.lockButton = lockButton
	frame.filterBar = filterBar
	-- frame.scrollFrame = scrollFrame
	frame.content = content

	self.overlay = frame
	self:ApplyAnchor(frame)
	self:BuildFilterButtons()
	self:UpdateFilterButtons()
	self:RefreshLockButton()
	self:UpdateContentWidth()
	frame:SetScript("OnSizeChanged", function()
		LegionRemix:UpdateContentWidth()
		LegionRemix:LayoutFilterButtons()
	end)
	self:LayoutFilterButtons()
	return frame
end

function LegionRemix:UpdateOverlay()
	if not self:ShouldOverlayBeVisible() then
		if self.overlay then self.overlay:Hide() end
		return
	end

	local frame = self:CreateOverlay()
	if not frame then return end

	local db = self:GetDB()
	frame:Show()
	if frame.collapseButton then frame.collapseButton.tooltipText = db and db.collapsed and HERO_TALENTS_EXPAND or HERO_TALENTS_COLLAPSE end
	setButtonTexture(frame.collapseButton, db and db.collapsed)
	if frame.lockButton then frame.lockButton.tooltipText = db and db.locked and UNLOCK or LOCK end
	self:RefreshLockButton()

	local activeSet, allActive = self:GetActivePhaseFilterSet()
	self:UpdateFilterButtons()

	local bronze = self:GetBronzeCurrency()
	local collected, total = self:GetFilteredOverallTotals()
	local remaining = math.max(total - collected, 0)
	local availableWidth = (frame:GetWidth() or 360) - 40
	if availableWidth < 200 then availableWidth = 200 end
	frame.bronzeText:SetWidth(availableWidth * 0.45)
	frame.remainingText:SetWidth(availableWidth * 0.55)

	frame.bronzeText:SetFormattedText("%s: %s", CURRENCY, formatBronze(bronze))
	frame.remainingText:SetFormattedText("%s: %s", L["Total Remaining"], formatBronze(remaining))

	if db and db.collapsed then
		if frame.filterBar and frame.filterBar.hasButtons then frame.filterBar:Hide() end
		if frame.scrollFrame then frame.scrollFrame:Hide() end
		if frame.content then frame.content:Hide() end
		frame:SetHeight(frame.collapsedHeight or 80)
		return
	else
		if frame.content then frame.content:Show() end
	end

	frame:SetHeight(frame.expandedHeight or 520)
	if frame.filterBar then
		if frame.filterBar.hasButtons then
			frame.filterBar:Show()
		else
			frame.filterBar:Hide()
		end
	end
	if frame.scrollFrame then frame.scrollFrame:Show() end
	self:LayoutFilterButtons()
	self:UpdateContentWidth()

	local categories = self.latestCategories or {}
	local hideComplete = db and db.hideCompleteCategories
	local visibleIndex = 0
	local dynHeight = 0
	for _, data in ipairs(categories) do
		local display = self:BuildCategoryDisplay(data)
		local hasCost = (display.totalCost or 0) > 0
		local hasEntries = (display.totalCount or 0) > 0
		if (hasCost or hasEntries) and (not hideComplete or not self:IsCategoryCompleteForDisplay(display)) then
			visibleIndex = visibleIndex + 1
			local row = self:GetRow(visibleIndex, frame.content)
			dynHeight = dynHeight + row:GetHeight()
			self:UpdateRow(row, display)
		end
	end
	self.overlay:SetHeight(110 + dynHeight + ((visibleIndex - 1) * 6))
	self:HideUnusedRows(visibleIndex + 1)
end

function LegionRemix:SetOverlayEnabled(value)
	local db = self:GetDB()
	if not db then return end
	db.overlayEnabled = value and true or false
	if value then db.overlayHidden = false end
	self:UpdateActivationState()
	self:RefreshLockButton()
end

function LegionRemix:SetCollapsed(value)
	local db = self:GetDB()
	if not db then return end
	db.collapsed = value and true or false
	self:UpdateOverlay()
end

function LegionRemix:GetOverlayScale()
	local db = self:GetDB()
	local scale = DEFAULTS.overlayScale
	if db and db.overlayScale then scale = tonumber(db.overlayScale) or scale end
	if not scale or scale <= 0 then scale = DEFAULTS.overlayScale end
	return scale
end

function LegionRemix:SetOverlayScale(value)
	local db = self:GetDB()
	if not db then return end
	local scale = tonumber(value)
	if not scale then scale = DEFAULTS.overlayScale end
	if scale < 0.6 then scale = 0.6 end
	if scale > 1.6 then scale = 1.6 end
	db.overlayScale = scale
	if self.overlay then
		local ok = pcall(self.overlay.SetScale, self.overlay, scale)
		if not ok then self.overlay:SetScale(DEFAULTS.overlayScale or 1) end
		self:UpdateContentWidth()
		self:LayoutFilterButtons()
	end
end

function LegionRemix:SetClassOnly(value)
	local db = self:GetDB()
	if not db then return end
	db.classOnly = value and true or false
	self:InvalidateAllCaches()
	self:RefreshData()
end

function LegionRemix:SetEnhancedTracking(value)
	local db = self:GetDB()
	if not db then return end
	db.enhancedTracking = value and true or false
	self:InvalidateAllCaches()
	self:RefreshData()
end

function LegionRemix:IsHidingCompleteCategories()
	local db = self:GetDB()
	if not db then return false end
	return db.hideCompleteCategories and true or false
end

function LegionRemix:SetHideCompleteCategories(value)
	local db = self:GetDB()
	if not db then return end
	local enabled = value and true or false
	if db.hideCompleteCategories == enabled then return end
	db.hideCompleteCategories = enabled
	self:UpdateOverlay()
end

function LegionRemix:ResetPosition()
	local db = self:GetDB()
	if not db then return end
	db.anchor = CopyTable(DEFAULTS.anchor)
	self:ApplyAnchor(self.overlay)
end

function LegionRemix:SetHidden(value)
	local db = self:GetDB()
	if not db then return end
	db.overlayHidden = value and true or false
	self:UpdateOverlay()
end

LegionRemix.refreshPending = false
LegionRemix.overlayPending = false

function LegionRemix:RequestRefresh(delay)
	if not self:IsActive() or self.refreshPending then return end
	self.refreshPending = true
	C_Timer.After(delay or 0.5, function()
		self.refreshPending = false
		self:RefreshData()
	end)
end

function LegionRemix:RequestOverlayUpdate(delay)
	if self.overlayPending then return end
	self.overlayPending = true
	C_Timer.After(delay or 0.2, function()
		self.overlayPending = false
		self:UpdateOverlay()
	end)
end

local EVENT_TO_CACHE = {
	NEW_MOUNT_ADDED = { "mounts" },
	MOUNT_JOURNAL_USABILITY_CHANGED = { "mounts" },
	TOYS_UPDATED = { "toys" },
	PET_JOURNAL_LIST_UPDATE = { "pets" },
	TRANSMOG_COLLECTION_SOURCE_ADDED = { "sets", "slotGrid", "transmog" },
	TRANSMOG_COLLECTION_SOURCE_REMOVED = { "sets", "slotGrid", "transmog" },
	TRANSMOG_COLLECTION_UPDATED = { "sets", "slotGrid", "transmog" },
	TRANSMOG_SETS_UPDATE_FAVORITE = { "sets" },
	PLAYER_SPECIALIZATION_CHANGED = { "sets" },
}

function LegionRemix:OnEvent(event, arg1)
	if not self:IsActive() then
		self:UpdateActivationState()
		return
	end

	if event == "PLAYER_ENTERING_WORLD" then
		self.playerClass = nil
		self:InvalidateAllCaches()
		self:RequestRefresh()
		return
	end

	if event == "CURRENCY_DISPLAY_UPDATE" then
		if not arg1 or arg1 == BRONZE_CURRENCY_ID then self:RequestOverlayUpdate() end
		return
	end

	if event == "MOUNT_JOURNAL_USABILITY_CHANGED" then
		self:RequestOverlayUpdate()
		return
	end

	local cacheKey = EVENT_TO_CACHE[event]
	if cacheKey then
		if type(cacheKey) == "table" then
			for _, key in ipairs(cacheKey) do
				self.cache[key] = {}
			end
		else
			self.cache[cacheKey] = {}
		end
		self:RequestRefresh(0.25)
		return
	end

	self:InvalidateAllCaches()
	self:RequestRefresh(0.75)
end

function LegionRemix:RegisterEvents()
	if self.eventsRegistered then return end
	local frame = self.eventFrame
	if not frame then
		frame = CreateFrame("Frame")
		self.eventFrame = frame
		frame:SetScript("OnEvent", function(_, event, ...) LegionRemix:OnEvent(event, ...) end)
	end
	for _, eventName in ipairs(EVENT_LIST) do
		frame:RegisterEvent(eventName)
	end
	self.eventsRegistered = true
end

function LegionRemix:UnregisterEvents()
	if not self.eventFrame or not self.eventsRegistered then return end
	for _, eventName in ipairs(EVENT_LIST) do
		self.eventFrame:UnregisterEvent(eventName)
	end
	self.eventsRegistered = false
end

function LegionRemix:Init()
	if self.initialized then
		self:UpdateActivationState()
		return
	end
	if not addon.db then return end
	self:GetDB()
	self:InitializeZoneTypes()
	self:InvalidateAllCaches()
	self.initialized = true
	self:UpdateActivationState()
end

local function addSpacer(container)
	local spacer = AceGUI:Create("Label")
	spacer:SetFullWidth(true)
	spacer:SetText(" ")
	container:AddChild(spacer)
end

local function addCheckbox(container, text, getter, setter)
	local checkbox = AceGUI:Create("CheckBox")
	checkbox:SetLabel(text)
	checkbox:SetValue(getter())
	checkbox:SetFullWidth(true)
	checkbox:SetCallback("OnValueChanged", function(_, _, val) setter(val and true or false) end)
	container:AddChild(checkbox)
	return checkbox
end

function LegionRemix:BuildOptionsUI(container)
	container:ReleaseChildren()
	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("List")
	container:AddChild(scroll)

	local intro = AceGUI:Create("Label")
	intro:SetFullWidth(true)
	intro:SetText(L["Track your Legion Remix Bronze collection"])
	scroll:AddChild(intro)

	addSpacer(scroll)

	addCheckbox(scroll, L["Enable overlay"], function()
		local db = LegionRemix:GetDB()
		return db and db.overlayEnabled
	end, function(value)
		LegionRemix:SetOverlayEnabled(value)
		container:ReleaseChildren()
		LegionRemix:BuildOptionsUI(container)
	end)

	if LegionRemix:GetDB().overlayEnabled then
		addCheckbox(scroll, L["Collapse progress list by default"], function()
			local db = LegionRemix:GetDB()
			return db and db.collapsed
		end, function(value) LegionRemix:SetCollapsed(value) end)

		addCheckbox(scroll, L["Lock overlay position"], function()
			local db = LegionRemix:GetDB()
			return db and db.locked
		end, function(value)
			local db = LegionRemix:GetDB()
			if db then
				db.locked = value
				LegionRemix:RefreshLockButton()
			end
		end)

		addSpacer(scroll)

		local scaleSlider = AceGUI:Create("Slider")
		scaleSlider:SetLabel(L["Overlay Scale"])
		scaleSlider:SetSliderValues(0.6, 1.6, 0.05)
		local initialScale = LegionRemix:GetOverlayScale()
		if type(initialScale) ~= "number" then initialScale = DEFAULTS.overlayScale or 1 end
		scaleSlider:SetValue(initialScale)
		scaleSlider:SetFullWidth(true)
		scaleSlider:SetCallback("OnValueChanged", function(_, _, val)
			if type(val) ~= "number" then return end
			LegionRemix:SetOverlayScale(val)
		end)
		scroll:AddChild(scaleSlider)

		addSpacer(scroll)

		local zoneDropdown = AceGUI:Create("Dropdown")
		zoneDropdown:SetLabel(L["Show overlay in"])
		zoneDropdown:SetMultiselect(true)
		zoneDropdown:SetFullWidth(true)
		local zoneOptions = LegionRemix:GetZoneFilterOptions()
		zoneDropdown:SetList(zoneOptions, LegionRemix:GetZoneFilterOrder())
		local function refreshZoneDropdown()
			local refreshed = LegionRemix:GetZoneFilterOptions()
			zoneDropdown:SetList(refreshed, LegionRemix:GetZoneFilterOrder())
			for _, key in ipairs(LegionRemix:GetZoneFilterOrder()) do
				zoneDropdown:SetItemValue(key, LegionRemix:IsZoneFilterEnabled(key))
			end
		end
		zoneDropdown:SetCallback("OnValueChanged", function(_, _, key, state) LegionRemix:SetZoneFilter(key, state) end)
		scroll:AddChild(zoneDropdown)
		refreshZoneDropdown()

		addSpacer(scroll)

		addCheckbox(scroll, L["Only consider sets wearable by the current character"], function()
			local db = LegionRemix:GetDB()
			return db and db.classOnly
		end, function(value) LegionRemix:SetClassOnly(value) end)

		addCheckbox(scroll, L["Enhanced transmog tracking (slower on login)"], function()
			local db = LegionRemix:GetDB()
			return db and db.enhancedTracking
		end, function(value) LegionRemix:SetEnhancedTracking(value) end)

		addCheckbox(scroll, L["Hide complete categories"], function() return LegionRemix:IsHidingCompleteCategories() end, function(value) LegionRemix:SetHideCompleteCategories(value) end)

		addSpacer(scroll)

		local categoryDropdown = AceGUI:Create("Dropdown")
		categoryDropdown:SetLabel(L["Visible categories"])
		categoryDropdown:SetMultiselect(true)
		categoryDropdown:SetFullWidth(true)
		local categoryOptions = LegionRemix:GetCategoryOptions()
		local categoryOrder = {}
		for _, category in ipairs(CATEGORY_DATA) do
			categoryOrder[#categoryOrder + 1] = category.key
		end
		categoryDropdown:SetList(categoryOptions, categoryOrder)
		local function refreshCategoryDropdown()
			categoryDropdown:SetList(LegionRemix:GetCategoryOptions(), categoryOrder)
			for _, category in ipairs(CATEGORY_DATA) do
				categoryDropdown:SetItemValue(category.key, LegionRemix:IsCategoryVisible(category.key))
			end
		end
		categoryDropdown:SetCallback("OnValueChanged", function(_, _, key, state) LegionRemix:SetCategoryVisibility(key, state) end)
		scroll:AddChild(categoryDropdown)
		refreshCategoryDropdown()

		local categoryButtons = AceGUI:Create("SimpleGroup")
		categoryButtons:SetLayout("Flow")
		categoryButtons:SetFullWidth(true)
		local showAllCategories = AceGUI:Create("Button")
		showAllCategories:SetText(L["Show all categories"])
		showAllCategories:SetWidth(180)
		showAllCategories:SetCallback("OnClick", function()
			LegionRemix:ResetCategoryFilters()
			refreshCategoryDropdown()
		end)
		categoryButtons:AddChild(showAllCategories)
		scroll:AddChild(categoryButtons)

		addSpacer(scroll)

		local buttonsGroup = AceGUI:Create("SimpleGroup")
		buttonsGroup:SetLayout("Flow")
		buttonsGroup:SetFullWidth(true)
		scroll:AddChild(buttonsGroup)

		local showBtn = AceGUI:Create("Button")
		showBtn:SetText(L["Show overlay"])
		showBtn:SetWidth(160)
		showBtn:SetCallback("OnClick", function()
			LegionRemix:SetHidden(false)
			LegionRemix:SetOverlayEnabled(true)
		end)
		buttonsGroup:AddChild(showBtn)

		local hideBtn = AceGUI:Create("Button")
		hideBtn:SetText(L["Hide overlay"])
		hideBtn:SetWidth(160)
		hideBtn:SetCallback("OnClick", function() LegionRemix:SetHidden(true) end)
		buttonsGroup:AddChild(hideBtn)

		local resetBtn = AceGUI:Create("Button")
		resetBtn:SetText(RESET_POSITION)
		resetBtn:SetWidth(160)
		resetBtn:SetCallback("OnClick", function() LegionRemix:ResetPosition() end)
		buttonsGroup:AddChild(resetBtn)

		local refreshBtn = AceGUI:Create("Button")
		refreshBtn:SetText(REFRESH)
		refreshBtn:SetWidth(160)
		refreshBtn:SetCallback("OnClick", function() LegionRemix:RefreshData() end)
		buttonsGroup:AddChild(refreshBtn)
	end
end

LegionRemix.functions = LegionRemix.functions or {}

function LegionRemix.functions.treeCallback(container, group)
	LegionRemix:Init()
	LegionRemix:BuildOptionsUI(container)
end

local activationEvents = {
	"PLAYER_LOGIN",
	"PLAYER_ENTERING_WORLD",
	"ZONE_CHANGED_NEW_AREA",
	"ZONE_CHANGED",
	"ZONE_CHANGED_INDOORS",
}

local activationWatcher = CreateFrame("Frame")
for _, eventName in ipairs(activationEvents) do
	activationWatcher:RegisterEvent(eventName)
end

activationWatcher:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		LegionRemix:OnEvent(event, ...)
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		LegionRemix:UpdateActivationState()
		return
	end
	if event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
		LegionRemix:RequestOverlayUpdate()
		return
	end
end)
