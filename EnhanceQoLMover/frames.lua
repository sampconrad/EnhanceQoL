local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Mover")
local db = addon.Mover.db

local groupOrder = {
	blizzard = 10,
}

local groups = {
	blizzard = {
		label = L["Blizzard"] or "Blizzard",
		expanded = true,
	},
}

local frames = {
	{
		id = "SettingsPanel",
		label = SETTINGS,
		group = "blizzard",
		names = { "SettingsPanel" },
		addon = "Blizzard_Settings",
		defaultEnabled = true,
	},
	{
		id = "GameMenuFrame",
		label = MAINMENU_BUTTON,
		group = "blizzard",
		names = { "GameMenuFrame" },
		addon = "Blizzard_GameMenu",
		defaultEnabled = true,
	},
	{
		id = "AchievementFrame",
		label = _G.LOOT_JOURNAL_LEGENDARIES_SOURCE_ACHIEVEMENT,
		group = "blizzard",
		names = { "AchievementFrame" },
		addon = "Blizzard_AchievementUI",
		handlesRelative = { "Header" },
		defaultEnabled = true,
	},
	{
		id = "HousingControlsFrame",
		label = _G.AUCTION_CATEGORY_HOUSING,
		group = "blizzard",
		names = { "HousingControlsFrame" },
		addon = "Blizzard_HousingControls",
		handlesRelative = { "OwnerControlFrame" },
		defaultEnabled = true,
	},
	{
		id = "CharacterFrame",
		label = CHARACTER_BUTTON,
		group = "blizzard",
		names = { "CharacterFrame" },
		defaultEnabled = true,
	},
	{
		id = "PlayerSpellsFrame",
		label = _G.INSPECT_TALENTS_BUTTON,
		group = "blizzard",
		names = { "PlayerSpellsFrame" },
		handlesRelative = { "TalentsFrame", "SpecFrame" },
		addon = "Blizzard_PlayerSpells",
		defaultEnabled = true,
	},
	{
		id = "PVEFrame",
		label = GROUP_FINDER,
		group = "blizzard",
		names = { "PVEFrame" },
		defaultEnabled = true,
	},
	{
		id = "ItemInteractionFrame",
		label = L["Catalyst"],
		group = "blizzard",
		names = { "ItemInteractionFrame" },
		addon = "Blizzard_ItemInteractionUI",
		defaultEnabled = true,
	},
	{
		id = "WorldMapFrame",
		label = WORLDMAP_BUTTON,
		group = "blizzard",
		names = { "WorldMapFrame" },
		defaultEnabled = true,
	},
	{
		id = "ContainerFrameCombinedBags",
		label = HUD_EDIT_MODE_BAGS_LABEL,
		group = "blizzard",
		names = { "ContainerFrameCombinedBags" },
		handlesRelative = { "TitleContainer" },
		defaultEnabled = true,
	},
	{
		id = "MerchantFrame",
		label = MERCHANT,
		group = "blizzard",
		names = { "MerchantFrame" },
		defaultEnabled = true,
		ignoreFramePositionManager = true,
		userPlaced = true,
	},

	{
		id = "AuctionHouseFrame",
		label = BUTTON_LAG_AUCTIONHOUSE,
		group = "blizzard",
		names = { "AuctionHouseFrame" },
		addon = "Blizzard_AuctionHouseUI",
		defaultEnabled = true,
	},
	{
		id = "MailFrame",
		label = BUTTON_LAG_MAIL,
		group = "blizzard",
		names = { "MailFrame" },
		defaultEnabled = true,
	},
}

local settings = {
	{
		type = "checkbox",
		var = "moverEnabled",
		dbKey = "enabled",
		text = L["Global Move Enabled"] or "Enable moving",
		default = false,
		get = function() return db.enabled end,
		set = function(value)
			db.enabled = value
			addon.Mover.functions.ApplyAll()
		end,
	},
	{
		type = "checkbox",
		var = "moverRequireModifier",
		dbKey = "requireModifier",
		text = L["Require Modifier For Move"] or "Require modifier to move",
		default = true,
		get = function() return db.requireModifier end,
		set = function(value) db.requireModifier = value end,
		parentCheck = function() return db.enabled end,
	},
	{
		type = "dropdown",
		var = "moverModifier",
		dbKey = "modifier",
		text = L["Move Modifier"] or (L["Scale Modifier"] or "Modifier"),
		list = { SHIFT = "SHIFT", CTRL = "CTRL", ALT = "ALT" },
		order = { "SHIFT", "CTRL", "ALT" },
		default = "SHIFT",
		get = function() return db.modifier or "SHIFT" end,
		set = function(value) db.modifier = value end,
		parentCheck = function() return db.enabled and db.requireModifier end,
	},
}

addon.Mover.variables.groupOrder = groupOrder
addon.Mover.variables.groups = groups
addon.Mover.variables.frames = frames
addon.Mover.variables.settings = settings

local function initSettingsDefaults()
	for _, def in ipairs(settings) do
		if def.dbKey and def.default ~= nil and db[def.dbKey] == nil then db[def.dbKey] = def.default end
	end
end

initSettingsDefaults()

for groupId, group in pairs(groups) do
	local order = groupOrder[groupId] or group.order
	addon.Mover.functions.RegisterGroup(groupId, group.label, {
		order = order,
		expanded = group.expanded,
	})
end

for _, def in ipairs(frames) do
	if def.group and groupOrder[def.group] and def.groupOrder == nil then def.groupOrder = groupOrder[def.group] end
	addon.Mover.functions.RegisterFrame(def)
end
