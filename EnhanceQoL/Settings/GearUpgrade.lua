local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local cGearUpgrade = addon.functions.SettingsCreateCategory(nil, L["GearUpgrades"], nil, "GearUpgrade")
addon.SettingsLayout.gearUpgradeCategory = cGearUpgrade

addon.functions.SettingsCreateHeadline(cGearUpgrade, L["Show on Character Frame"])

local data = {
	{
		var = "charframe_ilvl",
		text = STAT_AVERAGE_ITEM_LEVEL,
		func = function(value)
			addon.db.charDisplayOptions["ilvl"] = value and true or false
			addon.functions.setCharFrame()
		end,
		get = function() return addon.db.charDisplayOptions["ilvl"] end,
		children = {
			{
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
				},
				text = L["charIlvlPosition"],
				get = function() return addon.db["charIlvlPosition"] or "BOTTOMLEFT" end,
				set = function(key)
					addon.db["charIlvlPosition"] = key
					addon.functions.setCharFrame()
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["charframe_ilvl"]
						and addon.SettingsLayout.elements["charframe_ilvl"].setting
						and addon.SettingsLayout.elements["charframe_ilvl"].setting:GetValue() == true
				end,
				parent = true,
				default = "BOTTOMLEFT",
				var = "charIlvlPosition",
				type = Settings.VarType.String,
				sType = "dropdown",
			},
		},
	},
	{
		var = "charframe_movementspeed",
		text = STAT_MOVEMENT_SPEED,
		func = function(value)
			addon.db["movementSpeedStatEnabled"] = value and true or false
			if value then
				if addon.MovementSpeedStat and addon.MovementSpeedStat.Refresh then addon.MovementSpeedStat.Refresh() end
			else
				addon.MovementSpeedStat.Disable()
			end
		end,
		get = function() return addon.db["movementSpeedStatEnabled"] end,
	},
	{
		var = "charframe_gems",
		text = AUCTION_CATEGORY_GEMS,
		func = function(value) addon.db.charDisplayOptions["gems"] = value and true or false end,
		get = function() return addon.db.charDisplayOptions["gems"] end,
	},
	{
		var = "charframe_enchants",
		text = ENCHANTS,
		func = function(value) addon.db.charDisplayOptions["enchants"] = value and true or false end,
		get = function() return addon.db.charDisplayOptions["enchants"] end,
	},
	{
		var = "charframe_gemtip",
		text = L["Gem slot tooltip"],
		func = function(value) addon.db.charDisplayOptions["gemtip"] = value and true or false end,
		get = function() return addon.db.charDisplayOptions["gemtip"] end,
	},
	{
		var = "charframe_durability",
		text = DURABILITY,
		func = function(value)
			addon.db["showDurabilityOnCharframe"] = value and true or false
			addon.functions.calculateDurability()
		end,
		get = function() return addon.db["showDurabilityOnCharframe"] end,
	},
	{
		var = "charframe_catalyst",
		text = L["Catalyst Charges"],
		func = function(value) addon.db["showCatalystChargesOnCharframe"] = value and true or false end,
		get = function() return addon.db["showCatalystChargesOnCharframe"] end,
	},
}
table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cGearUpgrade, data)

addon.functions.SettingsCreateHeadline(cGearUpgrade, L["Show on Inspect Frame"])

data = {
	{
		var = "inspect_ilvl",
		text = STAT_AVERAGE_ITEM_LEVEL,
		func = function(value) addon.db.inspectDisplayOptions["ilvl"] = value and true or false end,
		get = function() return addon.db.inspectDisplayOptions["ilvl"] end,
	},
	{
		var = "inspect_gems",
		text = AUCTION_CATEGORY_GEMS,
		func = function(value) addon.db.inspectDisplayOptions["gems"] = value and true or false end,
		get = function() return addon.db.inspectDisplayOptions["gems"] end,
	},
	{
		var = "inspect_enchants",
		text = ENCHANTS,
		func = function(value) addon.db.inspectDisplayOptions["enchants"] = value and true or false end,
		get = function() return addon.db.inspectDisplayOptions["enchants"] end,
	},
	{
		var = "inspect_gemtip",
		text = L["Gem slot tooltip"],
		func = function(value) addon.db.inspectDisplayOptions["gemtip"] = value and true or false end,
		get = function() return addon.db.inspectDisplayOptions["gemtip"] end,
	},
}
table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cGearUpgrade, data)

addon.functions.SettingsCreateHeadline(cGearUpgrade, AUCTION_CATEGORY_GEMS)

data = {
	{
		var = "enableGemHelper",
		text = L["enableGemHelper"],
		func = function(value)
			addon.db["enableGemHelper"] = value and true or false
			if not value and EnhanceQoLGemHelper then
				EnhanceQoLGemHelper:Hide()
				EnhanceQoLGemHelper = nil
			end
		end,
		get = function() return addon.db["enableGemHelper"] end,
		desc = L["enableGemHelperDesc"],
	},
}
addon.functions.SettingsCreateCheckboxes(cGearUpgrade, data)

addon.functions.SettingsCreateHeadline(cGearUpgrade, AUCTION_CATEGORY_MISCELLANEOUS)

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
	},
	{
		var = "openCharframeOnUpgrade",
		text = L["openCharframeOnUpgrade"],
		func = function(value) addon.db["openCharframeOnUpgrade"] = value and true or false end,
		get = function() return addon.db["openCharframeOnUpgrade"] end,
	},
}

table.sort(data, function(a, b) return a.text < b.text end)

addon.functions.SettingsCreateCheckboxes(cGearUpgrade, data)

----- REGION END

function addon.functions.initGearUpgrade()
	addon.functions.InitDBValue("charDisplayOptions", {})
	addon.functions.InitDBValue("inspectDisplayOptions", {})
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
