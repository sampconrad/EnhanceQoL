local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Vendor = addon.Vendor or {}
addon.LVendor = addon.LVendor or {} -- Locales for MythicPlus
addon.Vendor.functions = addon.Vendor.functions or {}

addon.Vendor.variables = addon.Vendor.variables or {}
local _, avgItemLevelEquipped = GetAverageItemLevel()
addon.Vendor.variables.avgItemLevelEquipped = avgItemLevelEquipped

addon.Vendor.variables.itemQualityFilter = addon.Vendor.variables.itemQualityFilter or {} -- Filter for Enable/Disable Qualities
addon.Vendor.variables.itemBindTypeQualityFilter = addon.Vendor.variables.itemBindTypeQualityFilter or {} -- Filter for BindType in Quality
addon.Vendor.variables.tabNames = addon.Vendor.variables.tabNames or { -- Used to create autosell tabs
	[0] = "Poor",
	[1] = "Common",
	[2] = "Uncommon",
	[3] = "Rare",
	[4] = "Epic",
}

addon.Vendor.variables.tabKeyNames = addon.Vendor.variables.tabKeyNames or {}

function addon.Vendor.functions.InitDB()
	if not addon.db or not addon.functions or not addon.functions.InitDBValue then return end
	local init = addon.functions.InitDBValue

	-- Includelist
	init("vendorIncludeSellList", {})
	init("vendorIncludeDestroyList", {})

	-- Excludelist
	init("vendorExcludeSellList", {})

	init("vendorSwapAutoSellShift", false)
	init("vendorOnly12Items", true)
	init("vendorAltClickInclude", false)
	init("vendorShowSellOverlay", false)
	init("vendorShowSellHighContrast", false)
	init("vendorShowSellTooltip", false)
	init("vendorDestroyEnable", false)
	init("vendorShowDestroyOverlay", true)
	init("vendorDestroyShowMessages", true)
	init("vendorCraftShopperEnable", false)

	for key, value in pairs(addon.Vendor.variables.tabNames) do
		init("vendor" .. value .. "Enable", false)
		init("vendor" .. value .. "MinIlvlDif", 200)
		init("vendor" .. value .. "IgnoreWarbound", true)
		init("vendor" .. value .. "IgnoreBoE", true)
		init("vendor" .. value .. "AbsolutIlvl", false)
		init("vendor" .. value .. "CraftingExpansions", {})

		if key > 1 then
			init("vendor" .. value .. "IgnoreUpgradable", false)
			if key == 4 then
				init("vendor" .. value .. "IgnoreHeroicTrack", false)
				init("vendor" .. value .. "IgnoreMythTrack", false)
			end
		end
	end
end

function addon.Vendor.functions.InitState()
	if not addon.db then return end
	local tabNames = addon.Vendor.variables.tabNames or {}
	local tabKeyNames = addon.Vendor.variables.tabKeyNames or {}
	wipe(tabKeyNames)
	for key in pairs(tabNames) do
		table.insert(tabKeyNames, key)
	end
	table.sort(tabKeyNames)

	for key, value in pairs(tabNames) do
		addon.Vendor.variables.itemQualityFilter[key] = addon.db["vendor" .. value .. "Enable"]
		addon.Vendor.variables.itemBindTypeQualityFilter[key] = {
			[0] = true, -- None
			[1] = true, -- Bind on Pickup
			[2] = not addon.db["vendor" .. value .. "IgnoreBoE"], -- Bind on Equip
			[3] = true, -- Bind on Use
			[4] = false, -- Quest item
			[5] = false, -- Unused 1
			[6] = false, -- Unused 2
			[7] = not addon.db["vendor" .. value .. "IgnoreWarbound"], -- Bind to Account
			[8] = not addon.db["vendor" .. value .. "IgnoreWarbound"], -- Bind to Warband
			[9] = not addon.db["vendor" .. value .. "IgnoreWarbound"], -- Bind to Warband
		}
	end
end

addon.Vendor.variables.itemTypeFilter = {
	[2] = true, -- Weapon
	[3] = true, -- Gems
	[4] = true, -- Armor
}

-- List to filter specific gems only
addon.Vendor.variables.itemSubTypeFilter = {
	[3] = {
		[11] = true, -- Artifact Relic
	},
}

addon.Vendor.variables.upgradePattern = ITEM_UPGRADE_TOOLTIP_FORMAT_STRING:gsub("%%s", "%%a+"):gsub("%%d", "%%d+")
