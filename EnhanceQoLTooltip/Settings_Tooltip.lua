local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Tooltip")

local cTooltip = addon.functions.SettingsCreateCategory(nil, L["Tooltip"], nil, "Tooltip")
addon.SettingsLayout.tooltipCategory = cTooltip
addon.functions.SettingsCreateHeadline(cTooltip, L["Buff_Debuff"])

local data = {
	list = { [1] = L["TooltipOFF"], [2] = L["TooltipON"] },
	text = L["TooltipBuffHideType"],
	get = function() return addon.db.TooltipBuffHideType or 1 end,
	set = function(key) addon.db.TooltipBuffHideType = key end,
	default = 1,
	var = "TooltipBuffHideType",
	type = Settings.VarType.Number,
}
addon.functions.SettingsCreateDropdown(cTooltip, data)

data = {
	{
		var = "TooltipBuffHideInCombat",
		text = L["TooltipBuffHideInCombat"],
		func = function(v) addon.db["TooltipBuffHideInCombat"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parent = true,
		parentCheck = function()
			return addon.SettingsLayout.elements["TooltipBuffHideType"]
				and addon.SettingsLayout.elements["TooltipBuffHideType"].setting
				and addon.SettingsLayout.elements["TooltipBuffHideType"].setting:GetValue() == 2
		end,
		element = addon.SettingsLayout.elements["TooltipBuffHideType"].element,
	},
	{
		var = "TooltipBuffHideInDungeon",
		text = L["TooltipBuffHideInDungeon"],
		func = function(v) addon.db["TooltipBuffHideInDungeon"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parent = true,
		parentCheck = function()
			return addon.SettingsLayout.elements["TooltipBuffHideType"]
				and addon.SettingsLayout.elements["TooltipBuffHideType"].setting
				and addon.SettingsLayout.elements["TooltipBuffHideType"].setting:GetValue() == 2
		end,
		element = addon.SettingsLayout.elements["TooltipBuffHideType"].element,
	},
}
table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cTooltip, data)

addon.functions.SettingsCreateHeadline(cTooltip, AUCTION_HOUSE_HEADER_ITEM)

data = {
	list = { [1] = L["TooltipOFF"], [2] = L["TooltipON"] },
	text = L["TooltipItemHideType"],
	get = function() return addon.db.TooltipItemHideType or 1 end,
	set = function(key) addon.db.TooltipItemHideType = key end,
	default = 1,
	var = "TooltipItemHideType",
	type = Settings.VarType.Number,
}
addon.functions.SettingsCreateDropdown(cTooltip, data)

data = {
	{
		var = "TooltipItemHideInCombat",
		text = L["TooltipItemHideInCombat"],
		func = function(v) addon.db["TooltipItemHideInCombat"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parent = true,
		parentCheck = function()
			return addon.SettingsLayout.elements["TooltipItemHideType"]
				and addon.SettingsLayout.elements["TooltipItemHideType"].setting
				and addon.SettingsLayout.elements["TooltipItemHideType"].setting:GetValue() == 2
		end,
		element = addon.SettingsLayout.elements["TooltipItemHideType"].element,
	},
	{
		var = "TooltipItemHideInDungeon",
		text = L["TooltipItemHideInDungeon"],
		func = function(v) addon.db["TooltipItemHideInDungeon"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parent = true,
		parentCheck = function()
			return addon.SettingsLayout.elements["TooltipItemHideType"]
				and addon.SettingsLayout.elements["TooltipItemHideType"].setting
				and addon.SettingsLayout.elements["TooltipItemHideType"].setting:GetValue() == 2
		end,
		element = addon.SettingsLayout.elements["TooltipItemHideType"].element,
	},
	{
		var = "TooltipShowItemID",
		text = L["TooltipShowItemID"],
		func = function(v) addon.db["TooltipShowItemID"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
	},
	{
		var = "TooltipShowTempEnchant",
		text = L["TooltipShowTempEnchant"],
		desc = L["TooltipShowTempEnchantDesc"],
		func = function(v) addon.db["TooltipShowTempEnchant"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
	},
	{
		var = "TooltipShowItemCount",
		text = L["TooltipShowItemCount"],
		func = function(v) addon.db["TooltipShowItemCount"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
	},
	{
		var = "TooltipShowSeperateItemCount",
		text = L["TooltipShowSeperateItemCount"],
		func = function(v) addon.db["TooltipShowSeperateItemCount"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
	},
}
table.sort(data, function(a, b) return a.text < b.text end)

addon.functions.SettingsCreateCheckboxes(cTooltip, data)

---- Spell

addon.functions.SettingsCreateHeadline(cTooltip, STAT_CATEGORY_SPELL)

data = {
	list = { [1] = L["TooltipOFF"], [2] = L["TooltipON"] },
	text = L["TooltipSpellHideType"],
	get = function() return addon.db.TooltipSpellHideType or 1 end,
	set = function(key) addon.db.TooltipSpellHideType = key end,
	default = 1,
	var = "TooltipSpellHideType",
	type = Settings.VarType.Number,
}
addon.functions.SettingsCreateDropdown(cTooltip, data)

data = {
	{
		var = "TooltipSpellHideInCombat",
		text = L["TooltipSpellHideInCombat"],
		func = function(v) addon.db["TooltipSpellHideInCombat"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parent = true,
		parentCheck = function()
			return addon.SettingsLayout.elements["TooltipSpellHideType"]
				and addon.SettingsLayout.elements["TooltipSpellHideType"].setting
				and addon.SettingsLayout.elements["TooltipSpellHideType"].setting:GetValue() == 2
		end,
		element = addon.SettingsLayout.elements["TooltipSpellHideType"].element,
	},
	{
		var = "TooltipSpellHideInDungeon",
		text = L["TooltipSpellHideInDungeon"],
		func = function(v) addon.db["TooltipSpellHideInDungeon"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parent = true,
		parentCheck = function()
			return addon.SettingsLayout.elements["TooltipSpellHideType"]
				and addon.SettingsLayout.elements["TooltipSpellHideType"].setting
				and addon.SettingsLayout.elements["TooltipSpellHideType"].setting:GetValue() == 2
		end,
		element = addon.SettingsLayout.elements["TooltipSpellHideType"].element,
	},
	{
		var = "TooltipShowSpellID",
		text = L["TooltipShowSpellID"],
		func = function(v) addon.db["TooltipShowSpellID"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
	},
	{
		var = "TooltipShowSpellIcon",
		text = L["TooltipShowSpellIcon"],
		func = function(v) addon.db["TooltipShowSpellIcon"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
	},
}
table.sort(data, function(a, b) return a.text < b.text end)

addon.functions.SettingsCreateCheckboxes(cTooltip, data)

-- Quest

addon.functions.SettingsCreateHeadline(cTooltip, LOOT_JOURNAL_LEGENDARIES_SOURCE_QUEST)

data = {
	{
		var = "TooltipShowQuestID",
		text = L["TooltipShowQuestID"],
		func = function(v) addon.db["TooltipShowQuestID"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
	},
}
table.sort(data, function(a, b) return a.text < b.text end)

addon.functions.SettingsCreateCheckboxes(cTooltip, data)

-- Unit

addon.functions.SettingsCreateHeadline(cTooltip, GROUPMANAGER_UNIT_MARKER)

data = {
	list = { [1] = NONE, [2] = L["Enemies"], [3] = L["Friendly"], [4] = L["Both"] },
	text = L["TooltipUnitHideType"],
	get = function() return addon.db.TooltipUnitHideType or 1 end,
	set = function(key) addon.db.TooltipUnitHideType = key end,
	default = 1,
	var = "TooltipUnitHideType",
	type = Settings.VarType.Number,
}
addon.functions.SettingsCreateDropdown(cTooltip, data)

data = {
	{
		var = "TooltipUnitHideInCombat",
		text = L["TooltipUnitHideInCombat"],
		func = function(v) addon.db["TooltipUnitHideInCombat"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parent = true,
		parentCheck = function()
			return addon.SettingsLayout.elements["TooltipUnitHideType"]
				and addon.SettingsLayout.elements["TooltipUnitHideType"].setting
				and addon.SettingsLayout.elements["TooltipUnitHideType"].setting:GetValue() > 1
		end,
		element = addon.SettingsLayout.elements["TooltipUnitHideType"].element,
	},
	{
		var = "TooltipUnitHideInDungeon",
		text = L["TooltipUnitHideInDungeon"],
		func = function(v) addon.db["TooltipUnitHideInDungeon"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parent = true,
		parentCheck = function()
			return addon.SettingsLayout.elements["TooltipUnitHideType"]
				and addon.SettingsLayout.elements["TooltipUnitHideType"].setting
				and addon.SettingsLayout.elements["TooltipUnitHideType"].setting:GetValue() > 1
		end,
		element = addon.SettingsLayout.elements["TooltipUnitHideType"].element,
	},
}
table.sort(data, function(a, b) return a.text < b.text end)

addon.functions.SettingsCreateCheckboxes(cTooltip, data)

data = {
	{
		var = "TooltipUnitHideHealthBar",
		text = L["TooltipUnitHideHealthBar"],
		func = function(v) addon.db["TooltipUnitHideHealthBar"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
	},
	{
		var = "TooltipUnitHideRightClickInstruction",
		text = L["TooltipUnitHideRightClickInstruction"]:format(UNIT_POPUP_RIGHT_CLICK),
		func = function(v) addon.db["TooltipUnitHideRightClickInstruction"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
	},
}
table.sort(data, function(a, b) return a.text < b.text end)

addon.functions.SettingsCreateCheckboxes(cTooltip, data)

-- Player

addon.functions.SettingsCreateHeadline(cTooltip, PLAYER)

addon.functions.SettingsCreateMultiDropdown(cTooltip, {
	var = "TooltipPlayerDetailsLabel",
	text = L["TooltipPlayerDetailsLabel"],
	options = {
		{
			var = "TooltipShowMythicScore",
			value = "mythic",
			text = L["TooltipShowMythicScore"]:format(DUNGEON_SCORE),
			func = function(value) addon.db["TooltipShowMythicScore"] = value and true or false end,
			get = function() return addon.db["TooltipShowMythicScore"] or false end,
			default = false,
		},
		{
			var = "TooltipShowMythicScore",
			value = "spec",
			text = L["TooltipUnitShowSpec"],
			func = function(value) addon.db["TooltipUnitShowSpec"] = value and true or false end,
			get = function() return addon.db["TooltipUnitShowSpec"] or false end,
			default = false,
		},
	},
})

-- addon.functions.SettingsCreateHeadline(cMouse, L["mouseTrail"])
-- addon.functions.SettingsCreateText(cMouse, "|cff99e599" .. L["Trailinfo"] .. "|r")

----- REGION END

function addon.functions.initTooltip() end

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
