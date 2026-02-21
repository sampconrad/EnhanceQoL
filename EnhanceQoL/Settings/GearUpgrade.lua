local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local wipe = wipe

local cGearUpgrade = addon.SettingsLayout.rootGENERAL
local expandable = addon.functions.SettingsCreateExpandableSection(cGearUpgrade, {
	name = L["GearUpgrades"],
	newTagID = "GearUpgrades",
	expanded = false,
	colorizeTitle = false,
})
addon.SettingsLayout.gearUpgradeCategory = cGearUpgrade

addon.functions.SettingsCreateHeadline(cGearUpgrade, L["Show on Character Frame"], { parentSection = expandable })

local function ensureDisplayOptions()
	if addon.functions and addon.functions.ensureDisplayDB then
		addon.functions.ensureDisplayDB()
	else
		addon.db.charDisplayOptions = addon.db.charDisplayOptions or {}
		addon.db.inspectDisplayOptions = addon.db.inspectDisplayOptions or {}
	end
end

local function refreshItemLevelDisplays()
	if addon.functions and addon.functions.refreshItemLevelDisplays then
		addon.functions.refreshItemLevelDisplays()
	elseif addon.functions and addon.functions.setCharFrame then
		addon.functions.setCharFrame()
	end
end

local function isCharDisplaySelected(key)
	ensureDisplayOptions()
	local t = addon.db.charDisplayOptions
	if key == "ilvl" then return t.ilvl == true end
	if key == "gems" then return t.gems == true end
	if key == "enchants" then return t.enchants == true end
	if key == "gemtip" then return t.gemtip == true end
	if key == "durability" then return addon.db["showDurabilityOnCharframe"] == true end
	if key == "catalyst" then return addon.db["showCatalystChargesOnCharframe"] == true end
	if key == "movementspeed" then return addon.db["movementSpeedStatEnabled"] == true end
	if key == "statsformat" then return addon.db["characterStatsFormattingEnabled"] == true end
	return false
end

local function setCharDisplayOption(key, value)
	ensureDisplayOptions()
	local enabled = value and true or false
	if key == "ilvl" or key == "gems" or key == "enchants" or key == "gemtip" then
		addon.db.charDisplayOptions[key] = enabled
		addon.functions.setCharFrame()
	elseif key == "durability" then
		addon.db["showDurabilityOnCharframe"] = enabled
		addon.functions.calculateDurability()
	elseif key == "catalyst" then
		addon.db["showCatalystChargesOnCharframe"] = enabled
	elseif key == "movementspeed" then
		addon.db["movementSpeedStatEnabled"] = enabled
		if enabled then
			if addon.MovementSpeedStat and addon.MovementSpeedStat.Refresh then addon.MovementSpeedStat.Refresh() end
		else
			addon.MovementSpeedStat.Disable()
		end
	elseif key == "statsformat" then
		addon.db["characterStatsFormattingEnabled"] = enabled
		if addon.CharacterStatsFormatting and addon.CharacterStatsFormatting.Refresh then addon.CharacterStatsFormatting.Refresh() end
	end
end

local function applyCharDisplaySelection(selection)
	selection = selection or {}
	ensureDisplayOptions()
	addon.db.charDisplayOptions.ilvl = selection.ilvl == true
	addon.db.charDisplayOptions.gems = selection.gems == true
	addon.db.charDisplayOptions.enchants = selection.enchants == true
	addon.db.charDisplayOptions.gemtip = selection.gemtip == true
	addon.db["showDurabilityOnCharframe"] = selection.durability == true
	addon.db["showCatalystChargesOnCharframe"] = selection.catalyst == true
	addon.db["movementSpeedStatEnabled"] = selection.movementspeed == true
	addon.db["characterStatsFormattingEnabled"] = selection.statsformat == true
	addon.functions.setCharFrame()
	addon.functions.calculateDurability()
	if addon.db["movementSpeedStatEnabled"] then
		if addon.MovementSpeedStat and addon.MovementSpeedStat.Refresh then addon.MovementSpeedStat.Refresh() end
	else
		addon.MovementSpeedStat.Disable()
	end
	if addon.CharacterStatsFormatting and addon.CharacterStatsFormatting.Refresh then addon.CharacterStatsFormatting.Refresh() end
end

local ilvlFontOrder = {}
local ilvlOutlineOrder = { "NONE", "OUTLINE", "THICKOUTLINE", "MONOCHROMEOUTLINE" }
local ilvlOutlineOptions = {
	NONE = L["fontOutlineNone"] or NONE,
	OUTLINE = L["fontOutlineThin"] or "Outline",
	THICKOUTLINE = L["fontOutlineThick"] or "Thick Outline",
	MONOCHROMEOUTLINE = L["fontOutlineMono"] or "Monochrome Outline",
}

local function buildIlvlFontDropdown()
	local map = {
		[addon.variables.defaultFont] = L["actionBarFontDefault"] or "Blizzard font",
	}
	local LSM = LibStub("LibSharedMedia-3.0", true)
	if LSM and LSM.HashTable then
		for name, path in pairs(LSM:HashTable("font") or {}) do
			if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
		end
	end
	local list, order = addon.functions.prepareListForDropdown(map)
	wipe(ilvlFontOrder)
	for i, key in ipairs(order) do
		ilvlFontOrder[i] = key
	end
	return list
end

local charDisplayDropdown = addon.functions.SettingsCreateMultiDropdown(cGearUpgrade, {
	var = "charframe_display",
	text = L["gearDisplayElements"] or "Elements",
	options = {
		{ value = "ilvl", text = STAT_AVERAGE_ITEM_LEVEL, tooltip = L["gearDisplayOptionItemLevelDesc"] },
		{ value = "gems", text = AUCTION_CATEGORY_GEMS, tooltip = L["gearDisplayOptionGemsDesc"] },
		{ value = "enchants", text = ENCHANTS, tooltip = L["gearDisplayOptionEnchantsDesc"] },
		{ value = "gemtip", text = L["Gem slot tooltip"], tooltip = L["gearDisplayOptionGemTooltipDesc"] },
		{ value = "durability", text = DURABILITY, tooltip = L["gearDisplayOptionDurabilityDesc"] },
		{ value = "catalyst", text = L["Catalyst Charges"], tooltip = L["gearDisplayOptionCatalystDesc"] },
		{ value = "movementspeed", text = STAT_MOVEMENT_SPEED, tooltip = L["gearDisplayOptionMovementSpeedDesc"] },
		{ value = "statsformat", text = L["gearDisplayOptionStatsFormat"] or "Stat formatting", tooltip = L["gearDisplayOptionStatsFormatDesc"] },
	},
	isSelectedFunc = function(key) return isCharDisplaySelected(key) end,
	setSelectedFunc = function(key, selected) setCharDisplayOption(key, selected) end,
	setSelection = applyCharDisplaySelection,
	parentSection = expandable,
	notify = "showMissingEnchantOverlayOnCharframe",
})

local missingOverlayCheckbox = addon.functions.SettingsCreateCheckbox(cGearUpgrade, {
	var = "showMissingEnchantOverlayOnCharframe",
	text = L["gearDisplayOptionMissingEnchantOverlay"] or "Show missing enchant overlay",
	func = function(value) addon.db["showMissingEnchantOverlayOnCharframe"] = value and true or false end,
	default = true,
	parent = charDisplayDropdown,
	parentCheck = function() return isCharDisplaySelected("enchants") end,
	parentSection = expandable,
})

addon.functions.SettingsCreateColorPicker(cGearUpgrade, {
	var = "missingEnchantOverlayColor",
	text = L["gearDisplayOptionMissingEnchantOverlayColor"] or "Missing enchant overlay color",
	hasOpacity = true,
	element = missingOverlayCheckbox and missingOverlayCheckbox.element,
	parentCheck = function() return isCharDisplaySelected("enchants") and addon.db["showMissingEnchantOverlayOnCharframe"] == true end,
	parentSection = expandable,
})

addon.functions.SettingsCreateDropdown(cGearUpgrade, {
	list = {
		TOPLEFT = L["topLeft"],
		TOP = L["top"],
		TOPRIGHT = L["topRight"],
		LEFT = L["left"],
		CENTER = L["center"],
		RIGHT = L["right"],
		BOTTOMLEFT = L["bottomLeft"],
		BOTTOM = L["bottom"],
		BOTTOMRIGHT = L["bottomRight"],
		OUTSIDE = L["outsideNearGems"] or "Outside (next to gems)",
	},
	text = L["charIlvlPosition"],
	get = function() return addon.db["charIlvlPosition"] or "TOPRIGHT" end,
	set = function(key)
		addon.db["charIlvlPosition"] = key
		refreshItemLevelDisplays()
	end,
	parent = charDisplayDropdown,
	parentCheck = function() return isCharDisplaySelected("ilvl") end,
	default = "TOPRIGHT",
	var = "charIlvlPosition",
	type = Settings.VarType.String,
	parentSection = expandable,
})

addon.functions.SettingsCreateHeadline(cGearUpgrade, L["ilvlTextStyleHeader"] or "Item level text style", { parentSection = expandable })

local ilvlQualityColorCheckbox = addon.functions.SettingsCreateCheckbox(cGearUpgrade, {
	var = "ilvlUseItemQualityColor",
	text = L["ilvlUseQualityColor"] or "Use item-quality colors",
	func = function(value)
		addon.db["ilvlUseItemQualityColor"] = value and true or false
		refreshItemLevelDisplays()
	end,
	default = true,
	parentSection = expandable,
})

addon.functions.SettingsCreateColorPicker(cGearUpgrade, {
	var = "ilvlTextColor",
	text = L["ilvlCustomColor"] or "Custom item level color",
	hasOpacity = true,
	element = ilvlQualityColorCheckbox and ilvlQualityColorCheckbox.element,
	parentCheck = function() return addon.db["ilvlUseItemQualityColor"] ~= true end,
	callback = function() refreshItemLevelDisplays() end,
	parentSection = expandable,
})

addon.functions.SettingsCreateScrollDropdown(cGearUpgrade, {
	var = "ilvlFontFace",
	text = L["ilvlFontLabel"] or "Item level font",
	listFunc = buildIlvlFontDropdown,
	order = ilvlFontOrder,
	default = addon.variables.defaultFont,
	get = function()
		local current = addon.db.ilvlFontFace or addon.variables.defaultFont
		local list = buildIlvlFontDropdown()
		if not list[current] then current = addon.variables.defaultFont end
		return current
	end,
	set = function(key)
		addon.db.ilvlFontFace = key
		refreshItemLevelDisplays()
	end,
	parentSection = expandable,
})

addon.functions.SettingsCreateSlider(cGearUpgrade, {
	var = "ilvlFontSize",
	text = L["ilvlFontSize"] or "Item level font size",
	min = 8,
	max = 32,
	step = 1,
	default = 14,
	get = function()
		local value = tonumber(addon.db.ilvlFontSize) or 14
		if value < 8 then value = 8 end
		if value > 32 then value = 32 end
		return value
	end,
	set = function(value)
		value = math.floor((tonumber(value) or 14) + 0.5)
		if value < 8 then value = 8 end
		if value > 32 then value = 32 end
		addon.db.ilvlFontSize = value
		refreshItemLevelDisplays()
	end,
	parentSection = expandable,
})

addon.functions.SettingsCreateDropdown(cGearUpgrade, {
	var = "ilvlFontOutline",
	text = L["ilvlFontOutline"] or "Item level font outline",
	list = ilvlOutlineOptions,
	order = ilvlOutlineOrder,
	default = "OUTLINE",
	get = function() return addon.db.ilvlFontOutline or "OUTLINE" end,
	set = function(key)
		addon.db.ilvlFontOutline = key
		refreshItemLevelDisplays()
	end,
	parentSection = expandable,
})

addon.functions.SettingsCreateHeadline(cGearUpgrade, L["Show on Inspect Frame"], { parentSection = expandable })

local function isInspectDisplaySelected(key)
	ensureDisplayOptions()
	local t = addon.db.inspectDisplayOptions
	if key == "ilvl" then return t.ilvl == true end
	if key == "gems" then return t.gems == true end
	if key == "enchants" then return t.enchants == true end
	if key == "gemtip" then return t.gemtip == true end
	return false
end

local function setInspectDisplayOption(key, value)
	ensureDisplayOptions()
	addon.db.inspectDisplayOptions[key] = value and true or false
	refreshItemLevelDisplays()
end

local function applyInspectDisplaySelection(selection)
	selection = selection or {}
	ensureDisplayOptions()
	addon.db.inspectDisplayOptions.ilvl = selection.ilvl == true
	addon.db.inspectDisplayOptions.gems = selection.gems == true
	addon.db.inspectDisplayOptions.enchants = selection.enchants == true
	addon.db.inspectDisplayOptions.gemtip = selection.gemtip == true
	refreshItemLevelDisplays()
end

addon.functions.SettingsCreateMultiDropdown(cGearUpgrade, {
	var = "inspectframe_display",
	text = L["gearDisplayElements"] or "Elements",
	options = {
		{ value = "ilvl", text = STAT_AVERAGE_ITEM_LEVEL, tooltip = L["gearDisplayOptionItemLevelDesc"] },
		{ value = "gems", text = AUCTION_CATEGORY_GEMS, tooltip = L["gearDisplayOptionGemsDesc"] },
		{ value = "enchants", text = ENCHANTS, tooltip = L["gearDisplayOptionEnchantsDesc"] },
		{ value = "gemtip", text = L["Gem slot tooltip"], tooltip = L["gearDisplayOptionGemTooltipDesc"] },
	},
	isSelectedFunc = function(key) return isInspectDisplaySelected(key) end,
	setSelectedFunc = function(key, selected) setInspectDisplayOption(key, selected) end,
	setSelection = applyInspectDisplaySelection,
	parentSection = expandable,
})

addon.functions.SettingsCreateHeadline(cGearUpgrade, AUCTION_CATEGORY_GEMS, { parentSection = expandable })

local data = {
	{
		var = "enableGemHelper",
		text = L["enableGemHelper"],
		func = function(value)
			addon.db["enableGemHelper"] = value and true or false
			if not value and EnhanceQoLGemHelper then EnhanceQoLGemHelper:Hide() end
			local tracker = _G.EnhanceQoLGemTracker
			if not value and tracker then tracker:Hide() end
			if value and addon.GemHelper and addon.GemHelper.UpdateTracker then addon.GemHelper.UpdateTracker() end
		end,
		get = function() return addon.db["enableGemHelper"] end,
		desc = L["enableGemHelperDesc"],
		parentSection = expandable,
	},
	{
		var = "hideGemHelperTracker",
		text = L["gemHelperHideTracker"],
		func = function(value)
			addon.db["hideGemHelperTracker"] = value and true or false
			if addon.GemHelper and addon.GemHelper.UpdateTracker then
				addon.GemHelper.UpdateTracker()
			else
				local tracker = _G.EnhanceQoLGemTracker
				if tracker and addon.db["hideGemHelperTracker"] then tracker:Hide() end
			end
		end,
		get = function() return addon.db["hideGemHelperTracker"] end,
		desc = L["gemHelperHideTrackerDesc"],
		parentSection = expandable,
	},
}
addon.functions.SettingsCreateCheckboxes(cGearUpgrade, data)

addon.functions.SettingsCreateHeadline(cGearUpgrade, AUCTION_CATEGORY_MISCELLANEOUS, { parentSection = expandable })

data = {
	{
		var = "instantCatalystEnabled",
		text = L["instantCatalystEnabled"],
		func = function(value)
			addon.db["instantCatalystEnabled"] = value and true or false
			addon.functions.toggleInstantCatalystButton(value)
		end,
		get = function() return addon.db["instantCatalystEnabled"] end,
		desc = L["instantCatalystEnabledDesc"],
		parentSection = expandable,
	},
	{
		var = "openCharframeOnUpgrade",
		text = L["openCharframeOnUpgrade"],
		func = function(value) addon.db["openCharframeOnUpgrade"] = value and true or false end,
		get = function() return addon.db["openCharframeOnUpgrade"] end,
		desc = L["openCharframeOnUpgradeDesc"],
		parentSection = expandable,
	},
}

table.sort(data, function(a, b) return a.text < b.text end)

addon.functions.SettingsCreateCheckboxes(cGearUpgrade, data)

----- REGION END

function addon.functions.initGearUpgrade()
	addon.functions.InitDBValue("charDisplayOptions", {})
	addon.functions.InitDBValue("inspectDisplayOptions", {})
	addon.functions.InitDBValue("missingEnchantOverlayColor", { r = 1, g = 0, b = 0, a = 0.6 })
	addon.functions.InitDBValue("ilvlUseItemQualityColor", true)
	addon.functions.InitDBValue("ilvlTextColor", { r = 1, g = 1, b = 1, a = 1 })
	addon.functions.InitDBValue("ilvlFontFace", addon.variables.defaultFont)
	addon.functions.InitDBValue("ilvlFontSize", 14)
	addon.functions.InitDBValue("ilvlFontOutline", "OUTLINE")
end

local eventHandlers = {}

local function registerEvents(frame)
	for event in pairs(eventHandlers) do
		frame:RegisterEvent(event)
	end
end

local function eventHandler(self, event, ...)
	if eventHandlers[event] then eventHandlers[event](...) end
end

local frameLoad = CreateFrame("Frame")

registerEvents(frameLoad)
frameLoad:SetScript("OnEvent", eventHandler)
