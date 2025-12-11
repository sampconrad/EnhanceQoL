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

local sectionBuff = addon.functions.SettingsCreateExpandableSection(cTooltip, {
	name = L["Buff_Debuff"],
	expanded = true,
	colorizeTitle = false,
})

local data = {
	list = { [1] = L["TooltipOFF"], [2] = L["TooltipON"] },
	text = L["TooltipBuffHideType"],
	get = function() return addon.db.TooltipBuffHideType or 1 end,
	set = function(key) addon.db.TooltipBuffHideType = key end,
	default = 1,
	var = "TooltipBuffHideType",
	type = Settings.VarType.Number,
	parentSection = sectionBuff,
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
		parentSection = sectionBuff,
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
		parentSection = sectionBuff,
	},
}
table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cTooltip, data)

local sectionItem = addon.functions.SettingsCreateExpandableSection(cTooltip, {
	name = AUCTION_HOUSE_HEADER_ITEM,
	expanded = true,
	colorizeTitle = false,
})

data = {
	list = { [1] = L["TooltipOFF"], [2] = L["TooltipON"] },
	text = L["TooltipItemHideType"],
	get = function() return addon.db.TooltipItemHideType or 1 end,
	set = function(key) addon.db.TooltipItemHideType = key end,
	default = 1,
	var = "TooltipItemHideType",
	type = Settings.VarType.Number,
	parentSection = sectionItem,
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
		parentSection = sectionItem,
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
		parentSection = sectionItem,
	},
	{
		var = "TooltipShowItemID",
		text = L["TooltipShowItemID"],
		func = function(v) addon.db["TooltipShowItemID"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = sectionItem,
	},
	{
		var = "TooltipShowItemIcon",
		text = L["TooltipShowItemIcon"],
		func = function(v) addon.db["TooltipShowItemIcon"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = sectionItem,
		children = {

			{
				var = "TooltipItemIconSize",
				text = L["TooltipItemIconSize"],
				get = function() return addon.db and addon.db["TooltipItemIconSize"] or 16 end,
				set = function(v) addon.db["TooltipItemIconSize"] = v end,
				min = 10,
				max = 30,
				step = 1,
				default = 20,
				sType = "slider",
				parent = true,
				parentCheck = function()
					return addon.SettingsLayout.elements["TooltipShowItemIcon"]
						and addon.SettingsLayout.elements["TooltipShowItemIcon"].setting
						and addon.SettingsLayout.elements["TooltipShowItemIcon"].setting:GetValue() == true
				end,
				element = addon.SettingsLayout.elements["TooltipShowItemIcon"] and addon.SettingsLayout.elements["TooltipShowItemIcon"].element,
				parentSection = sectionItem,
			},
		},
	},
	{
		var = "TooltipShowItemIcon",
		text = L["TooltipShowItemIcon"],
		func = function(v) addon.db["TooltipShowItemIcon"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		children = {

			{
				var = "TooltipItemIconSize",
				text = L["TooltipItemIconSize"],
				get = function() return addon.db and addon.db["TooltipItemIconSize"] or 16 end,
				set = function(v) addon.db["TooltipItemIconSize"] = v end,
				min = 10,
				max = 30,
				step = 1,
				default = 20,
				sType = "slider",
				parent = true,
				parentCheck = function()
					return addon.SettingsLayout.elements["TooltipShowItemIcon"]
						and addon.SettingsLayout.elements["TooltipShowItemIcon"].setting
						and addon.SettingsLayout.elements["TooltipShowItemIcon"].setting:GetValue() == true
				end,
				element = addon.SettingsLayout.elements["TooltipShowItemIcon"] and addon.SettingsLayout.elements["TooltipShowItemIcon"].element,
			},
		},
	},
	{
		var = "TooltipShowTempEnchant",
		text = L["TooltipShowTempEnchant"],
		desc = L["TooltipShowTempEnchantDesc"],
		func = function(v) addon.db["TooltipShowTempEnchant"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = sectionItem,
	},
	{
		var = "TooltipShowItemCount",
		text = L["TooltipShowItemCount"],
		func = function(v) addon.db["TooltipShowItemCount"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = sectionItem,
	},
	{
		var = "TooltipShowSeperateItemCount",
		text = L["TooltipShowSeperateItemCount"],
		func = function(v) addon.db["TooltipShowSeperateItemCount"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = sectionItem,
	},
	{
		var = "TooltipHousingAutoPreview",
		text = L["TooltipHousingAutoPreview"],
		desc = L["TooltipHousingAutoPreviewDesc"],
		func = function(v) addon.db["TooltipHousingAutoPreview"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = sectionItem,
	},
}
table.sort(data, function(a, b) return a.text < b.text end)

addon.functions.SettingsCreateCheckboxes(cTooltip, data)

---- Spell

local sectionSpell = addon.functions.SettingsCreateExpandableSection(cTooltip, {
	name = STAT_CATEGORY_SPELL,
	expanded = true,
	colorizeTitle = false,
})

data = {
	list = { [1] = L["TooltipOFF"], [2] = L["TooltipON"] },
	text = L["TooltipSpellHideType"],
	get = function() return addon.db.TooltipSpellHideType or 1 end,
	set = function(key) addon.db.TooltipSpellHideType = key end,
	default = 1,
	var = "TooltipSpellHideType",
	type = Settings.VarType.Number,
	parentSection = sectionSpell,
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
		parentSection = sectionSpell,
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
		parentSection = sectionSpell,
	},
	{
		var = "TooltipShowSpellID",
		text = L["TooltipShowSpellID"],
		func = function(v) addon.db["TooltipShowSpellID"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = sectionSpell,
	},
	{
		var = "TooltipShowSpellIcon",
		text = L["TooltipShowSpellIcon"],
		func = function(v) addon.db["TooltipShowSpellIcon"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = sectionSpell,
	},
	{
		var = "TooltipShowSpellIconInline",
		text = L["TooltipShowSpellIconInline"],
		func = function(v) addon.db["TooltipShowSpellIconInline"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = sectionSpell,
	},
}
table.sort(data, function(a, b) return a.text < b.text end)

addon.functions.SettingsCreateCheckboxes(cTooltip, data)

-- Quest

local sectionQuest = addon.functions.SettingsCreateExpandableSection(cTooltip, {
	name = LOOT_JOURNAL_LEGENDARIES_SOURCE_QUEST,
	expanded = true,
	colorizeTitle = false,
})

data = {
	{
		var = "TooltipShowQuestID",
		text = L["TooltipShowQuestID"],
		func = function(v) addon.db["TooltipShowQuestID"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = sectionQuest,
	},
}
table.sort(data, function(a, b) return a.text < b.text end)

addon.functions.SettingsCreateCheckboxes(cTooltip, data)

-- Unit

local sectionUnit = addon.functions.SettingsCreateExpandableSection(cTooltip, {
	name = GROUPMANAGER_UNIT_MARKER,
	expanded = true,
	colorizeTitle = false,
})

data = {
	list = { [1] = NONE, [2] = L["Enemies"], [3] = L["Friendly"], [4] = L["Both"] },
	text = L["TooltipUnitHideType"],
	get = function() return addon.db.TooltipUnitHideType or 1 end,
	set = function(key) addon.db.TooltipUnitHideType = key end,
	default = 1,
	var = "TooltipUnitHideType",
	type = Settings.VarType.Number,
	parentSection = sectionUnit,
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
		parentSection = sectionUnit,
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
		parentSection = sectionUnit,
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
		parentSection = sectionUnit,
	},
	{
		var = "TooltipUnitHideRightClickInstruction",
		text = L["TooltipUnitHideRightClickInstruction"]:format(UNIT_POPUP_RIGHT_CLICK),
		func = function(v) addon.db["TooltipUnitHideRightClickInstruction"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = sectionUnit,
	},
	{
		var = "TooltipHideFaction",
		text = L["TooltipHideFaction"],
		func = function(v) addon.db["TooltipHideFaction"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = sectionUnit,
	},
	{
		var = "TooltipHidePVP",
		text = L["TooltipHidePVP"],
		func = function(v) addon.db["TooltipHidePVP"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = sectionUnit,
	},
	{
		var = "TooltipShowGuildRank",
		text = L["TooltipShowGuildRank"],
		func = function(v) addon.db["TooltipShowGuildRank"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = sectionUnit,
		children = {
			{
				var = "TooltipGuildRankColor",
				text = L["TooltipGuildRankColor"],
				parent = true,
				parentCheck = function()
					return addon.SettingsLayout.elements["TooltipShowGuildRank"]
						and addon.SettingsLayout.elements["TooltipShowGuildRank"].setting
						and addon.SettingsLayout.elements["TooltipShowGuildRank"].setting:GetValue() == true
				end,
				colorizeLabel = true,
				sType = "colorpicker",
				parentSection = sectionUnit,
			},
		},
	},
	{
		var = "TooltipColorGuildName",
		text = L["TooltipColorGuildName"],
		func = function(v) addon.db["TooltipColorGuildName"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = sectionUnit,
		children = {
			{
				var = "TooltipGuildNameColor",
				text = L["TooltipGuildNameColor"],
				parent = true,
				parentCheck = function()
					return addon.SettingsLayout.elements["TooltipColorGuildName"]
						and addon.SettingsLayout.elements["TooltipColorGuildName"].setting
						and addon.SettingsLayout.elements["TooltipColorGuildName"].setting:GetValue() == true
				end,
				colorizeLabel = true,
				sType = "colorpicker",
				parentSection = sectionUnit,
			},
		},
	},
	{
		var = "TooltipHideFaction",
		text = L["TooltipHideFaction"],
		func = function(v) addon.db["TooltipHideFaction"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
	},
	{
		var = "TooltipHidePVP",
		text = L["TooltipHidePVP"],
		func = function(v) addon.db["TooltipHidePVP"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
	},
	{
		var = "TooltipShowGuildRank",
		text = L["TooltipShowGuildRank"],
		func = function(v) addon.db["TooltipShowGuildRank"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		children = {
			{
				var = "TooltipGuildRankColor",
				text = L["TooltipGuildRankColor"],
				parent = true,
				parentCheck = function()
					return addon.SettingsLayout.elements["TooltipShowGuildRank"]
						and addon.SettingsLayout.elements["TooltipShowGuildRank"].setting
						and addon.SettingsLayout.elements["TooltipShowGuildRank"].setting:GetValue() == true
				end,
				colorizeLabel = true,
				sType = "colorpicker",
			},
		},
	},
	{
		var = "TooltipColorGuildName",
		text = L["TooltipColorGuildName"],
		func = function(v) addon.db["TooltipColorGuildName"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		children = {
			{
				var = "TooltipGuildNameColor",
				text = L["TooltipGuildNameColor"],
				parent = true,
				parentCheck = function()
					return addon.SettingsLayout.elements["TooltipColorGuildName"]
						and addon.SettingsLayout.elements["TooltipColorGuildName"].setting
						and addon.SettingsLayout.elements["TooltipColorGuildName"].setting:GetValue() == true
				end,
				colorizeLabel = true,
				sType = "colorpicker",
			},
		},
	},
}
table.sort(data, function(a, b) return a.text < b.text end)

addon.functions.SettingsCreateCheckboxes(cTooltip, data)

local guildRankToggle = addon.SettingsLayout.elements["TooltipShowGuildRank"]

-- Player

local sectionPlayer = addon.functions.SettingsCreateExpandableSection(cTooltip, {
	name = PLAYER,
	expanded = true,
	colorizeTitle = false,
})

local function TooltipPlayerHasMythicDetails() return addon.db["TooltipShowMythicScore"] and true or false end

local function TooltipPlayerHasInspectDetails() return (addon.db["TooltipUnitShowSpec"] or addon.db["TooltipUnitShowItemLevel"]) and true or false end

local function BuildTooltipPlayerDetailOptions()
	return {
		{ value = "mythic", text = L["TooltipShowMythicScore"]:format(DUNGEON_SCORE) },
		{ value = "spec", text = L["TooltipUnitShowSpec"] },
		{ value = "ilvl", text = L["TooltipUnitShowItemLevel"] },
		{ value = "classColor", text = L["TooltipShowClassColor"] },
	}
end

local function IsTooltipPlayerDetailSelected(key)
	if not key then return false end
	if key == "mythic" then return addon.db["TooltipShowMythicScore"] and true or false end
	if key == "spec" then return (addon.db["TooltipUnitShowSpec"] and true or false) end
	if key == "ilvl" then return (addon.db["TooltipUnitShowItemLevel"] and true or false) end
	if key == "classColor" then return addon.db["TooltipShowClassColor"] and true or false end
	return false
end

local function SetTooltipPlayerDetailSelected(key, shouldSelect)
	if not key then return end
	local enabled = shouldSelect and true or false

	if key == "mythic" then
		addon.db["TooltipShowMythicScore"] = enabled
	elseif key == "spec" then
		addon.db["TooltipUnitShowSpec"] = enabled
	elseif key == "ilvl" then
		addon.db["TooltipUnitShowItemLevel"] = enabled
	elseif key == "classColor" then
		addon.db["TooltipShowClassColor"] = enabled
	else
		return
	end

	if (key == "spec" or key == "ilvl") and addon.functions.UpdateInspectEventRegistration then addon.functions.UpdateInspectEventRegistration() end
end

local function BuildMythicScorePartsOptions()
	return {
		{ value = "score", text = DUNGEON_SCORE },
		{ value = "best", text = L["BestMythic+run"] },
		{ value = "dungeons", text = L["SeasonDungeons"] or "Season dungeons" },
	}
end

local function IsMythicScorePartSelected(key)
	local parts = addon.db["TooltipMythicScoreParts"] or {}
	return parts[key] and true or false
end

local function SetMythicScorePartSelected(key, shouldSelect)
	if not key then return end
	addon.db["TooltipMythicScoreParts"] = addon.db["TooltipMythicScoreParts"] or { score = true, best = true, dungeons = true }
	if shouldSelect then
		addon.db["TooltipMythicScoreParts"][key] = true
	else
		addon.db["TooltipMythicScoreParts"][key] = nil
	end
end

addon.functions.SettingsCreateMultiDropdown(cTooltip, {
	var = "TooltipPlayerDetailsLabel",
	text = L["TooltipPlayerDetailsLabel"],
	options = BuildTooltipPlayerDetailOptions(),
	optionfunc = BuildTooltipPlayerDetailOptions,
	isSelectedFunc = IsTooltipPlayerDetailSelected,
	setSelectedFunc = SetTooltipPlayerDetailSelected,
	parentSection = sectionPlayer,
})

local playerDetailsElement = addon.SettingsLayout.elements["TooltipPlayerDetailsLabel"]
local playerDetailsInitializer = playerDetailsElement and playerDetailsElement.initializer

addon.functions.SettingsCreateCheckbox(cTooltip, {
	var = "TooltipMythicScoreRequireModifier",
	text = L["TooltipMythicScoreRequireModifier"]:format(DUNGEON_SCORE),
	func = function(value) addon.db["TooltipMythicScoreRequireModifier"] = value and true or false end,
	default = false,
	parent = true,
	element = playerDetailsInitializer,
	parentCheck = TooltipPlayerHasMythicDetails,
	notify = "TooltipPlayerDetailsLabel",
	parentSection = sectionPlayer,
})

addon.functions.SettingsCreateCheckbox(cTooltip, {
	var = "TooltipUnitInspectRequireModifier",
	text = L["TooltipUnitInspectRequireModifier"],
	func = function(value)
		addon.db["TooltipUnitInspectRequireModifier"] = value and true or false
		if addon.functions.UpdateInspectEventRegistration then addon.functions.UpdateInspectEventRegistration() end
	end,
	default = false,
	parent = true,
	element = playerDetailsInitializer,
	parentCheck = TooltipPlayerHasInspectDetails,
	notify = "TooltipPlayerDetailsLabel",
	parentSection = sectionPlayer,
})

local modifierList = {
	SHIFT = SHIFT_KEY_TEXT,
	ALT = ALT_KEY_TEXT,
	CTRL = CTRL_KEY_TEXT,
}
local modifierListOrder = { "SHIFT", "ALT", "CTRL" }

addon.functions.SettingsCreateDropdown(cTooltip, {
	var = "TooltipMythicScoreModifier",
	text = MODIFIERS_COLON,
	list = modifierList,
	order = modifierListOrder,
	get = function() return addon.db["TooltipMythicScoreModifier"] or "SHIFT" end,
	set = function(value) addon.db["TooltipMythicScoreModifier"] = value end,
	default = "SHIFT",
	parent = true,
	element = playerDetailsInitializer,
	parentCheck = function()
		return (
			addon.SettingsLayout.elements["TooltipUnitInspectRequireModifier"]
				and addon.SettingsLayout.elements["TooltipUnitInspectRequireModifier"].setting
				and addon.SettingsLayout.elements["TooltipUnitInspectRequireModifier"].setting:GetValue() == true
				and (addon.db["TooltipUnitShowSpec"] or addon.db["TooltipUnitShowItemLevel"])
			or addon.SettingsLayout.elements["TooltipMythicScoreRequireModifier"]
				and addon.SettingsLayout.elements["TooltipMythicScoreRequireModifier"].setting
				and addon.SettingsLayout.elements["TooltipMythicScoreRequireModifier"].setting:GetValue() == true
				and addon.db["TooltipShowMythicScore"]
		)
	end,
	parentSection = sectionPlayer,
})

addon.functions.SettingsCreateMultiDropdown(cTooltip, {
	var = "TooltipMythicScoreParts",
	text = L["MythicScorePartsLabel"] or "Mythic+ details to show",
	options = BuildMythicScorePartsOptions(),
	optionfunc = BuildMythicScorePartsOptions,
	isSelectedFunc = IsMythicScorePartSelected,
	setSelectedFunc = SetMythicScorePartSelected,
	parent = true,
	element = playerDetailsInitializer,
	parentCheck = TooltipPlayerHasMythicDetails,
	parentSection = sectionPlayer,
})

local sectionNPC = addon.functions.SettingsCreateExpandableSection(cTooltip, {
	name = L["TooltipUnitNPCGroup"],
	expanded = true,
	colorizeTitle = false,
})

addon.functions.SettingsCreateCheckbox(cTooltip, {
	var = "TooltipShowNPCID",
	text = L["TooltipShowNPCID"],
	func = function(value) addon.db["TooltipShowNPCID"] = value and true or false end,
	default = false,
	parentSection = sectionNPC,
})
addon.functions.SettingsCreateCheckbox(cTooltip, {
	var = "TooltipShowNPCWowheadLink",
	text = L["TooltipShowNPCWowheadLink"],
	func = function(value) addon.db["TooltipShowNPCWowheadLink"] = value and true or false end,
	default = false,
	desc = L["TooltipShowNPCWowheadLink_desc"],
	parentSection = sectionNPC,
})

local sectionGeneral = addon.functions.SettingsCreateExpandableSection(cTooltip, {
	name = GENERAL,
	expanded = true,
	colorizeTitle = false,
})

data = {
	list = { [1] = DEFAULT, [2] = L["CursorCenter"], [3] = L["CursorLeft"], [4] = L["CursorRight"] },
	text = L["TooltipAnchorType"],
	get = function() return addon.db.TooltipAnchorType or 1 end,
	set = function(key) addon.db.TooltipAnchorType = key end,
	default = 1,
	var = "TooltipAnchorType",
	type = Settings.VarType.Number,
	parentSection = sectionGeneral,
}
addon.functions.SettingsCreateDropdown(cTooltip, data)

data = {
	var = "TooltipAnchorOffsetX",
	text = L["TooltipAnchorOffsetX"],
	get = function() return addon.db and addon.db.TooltipAnchorOffsetX or 0 end,
	set = function(v) addon.db["TooltipAnchorOffsetX"] = v end,
	parentCheck = function()
		return addon.SettingsLayout.elements["TooltipAnchorType"]
			and addon.SettingsLayout.elements["TooltipAnchorType"].setting
			and addon.SettingsLayout.elements["TooltipAnchorType"].setting:GetValue() > 2
	end,
	min = -300,
	max = 300,
	step = 1,
	parent = true,
	element = addon.SettingsLayout.elements["TooltipAnchorType"].element,
	default = 0,
	parentSection = sectionGeneral,
}
addon.functions.SettingsCreateSlider(cTooltip, data)

data = {
	var = "TooltipAnchorOffsetY",
	text = L["TooltipAnchorOffsetY"],
	get = function() return addon.db and addon.db.TooltipAnchorOffsetY or 0 end,
	set = function(v) addon.db["TooltipAnchorOffsetY"] = v end,
	parentCheck = function()
		return addon.SettingsLayout.elements["TooltipAnchorType"]
			and addon.SettingsLayout.elements["TooltipAnchorType"].setting
			and addon.SettingsLayout.elements["TooltipAnchorType"].setting:GetValue() > 2
	end,
	min = -300,
	max = 300,
	step = 1,
	parent = true,
	element = addon.SettingsLayout.elements["TooltipAnchorType"].element,
	default = 0,
	parentSection = sectionGeneral,
}
addon.functions.SettingsCreateSlider(cTooltip, data)

addon.functions.SettingsCreateSlider(cTooltip, {
	var = "TooltipScale",
	text = L["TooltipScale"],
	get = function() return addon.db and addon.db["TooltipScale"] or 1 end,
	set = function(v)
		addon.db["TooltipScale"] = v
		if addon.Tooltip and addon.Tooltip.ApplyScale then addon.Tooltip.ApplyScale() end
	end,
	min = 0.5,
	max = 1.5,
	step = 0.05,
	default = 1,
	parentSection = sectionGeneral,
})

local sectionCurrency = addon.functions.SettingsCreateExpandableSection(cTooltip, {
	name = CURRENCY,
	expanded = true,
	colorizeTitle = false,
})
data = {
	{
		var = "TooltipShowCurrencyAccountWide",
		text = L["TooltipShowCurrencyAccountWide"],
		func = function(v) addon.db["TooltipShowCurrencyAccountWide"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = sectionCurrency,
	},
	{
		var = "TooltipShowCurrencyID",
		text = L["TooltipShowCurrencyID"],
		func = function(v) addon.db["TooltipShowCurrencyID"] = v end,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = sectionCurrency,
	},
}
table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cTooltip, data)

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
