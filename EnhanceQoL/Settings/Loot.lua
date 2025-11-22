local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local cLoot = addon.functions.SettingsCreateCategory(nil, L["Loot"], nil, "Loot")
addon.SettingsLayout.vendorEconomyCalootCategorytegory = cLoot

addon.functions.SettingsCreateHeadline(cLoot, L["LootPopups"])

local data = {
	{
		var = "autoQuickLoot",
		text = L["autoQuickLoot"],
		desc = L["autoQuickLootDesc"],
		func = function(value) addon.db["autoQuickLoot"] = value end,
		children = {
			{

				var = "autoQuickLootWithShift",
				text = L["autoQuickLootWithShift"],
				func = function(v) addon.db["autoQuickLootWithShift"] = v end,
				parentCheck = function()
					return addon.SettingsLayout.elements["autoQuickLoot"]
						and addon.SettingsLayout.elements["autoQuickLoot"].setting
						and addon.SettingsLayout.elements["autoQuickLoot"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
			},
		},
	},
	{
		var = "autoHideBossBanner",
		text = L["autoHideBossBanner"],
		desc = L["autoHideBossBannerDesc"],
		func = function(value) addon.db["autoHideBossBanner"] = value end,
	},
	{
		var = "hideAzeriteToast",
		text = L["hideAzeriteToast"],
		desc = L["hideAzeriteToastDesc"],
		func = function(value)
			addon.db["hideAzeriteToast"] = value
			if value then
				if AzeriteLevelUpToast then
					AzeriteLevelUpToast:UnregisterAllEvents()
					AzeriteLevelUpToast:Hide()
				end
			else
				addon.variables.requireReload = true
				addon.functions.checkReloadFrame()
			end
		end,
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cLoot, data)

addon.functions.SettingsCreateHeadline(cLoot, L["groupLootRollFrames"])

data = {
	{
		var = "enableGroupLootAnchor",
		text = L["enableGroupLootAnchorOption"],
		desc = L["enableGroupLootAnchorDesc"],
		func = function(value)
			addon.db.enableGroupLootAnchor = value and true or false
			if addon.LootToast and addon.LootToast.OnGroupRollAnchorOptionChanged then addon.LootToast:OnGroupRollAnchorOptionChanged(addon.db.enableGroupLootAnchor) end
			addon.functions.initLootToast()
		end,
		children = {
			{
				var = "groupLootScale",
				text = L["groupLootScale"],
				func = function(v) addon.db["groupLootScale"] = v end,
				parentCheck = function()
					return addon.SettingsLayout.elements["enableGroupLootAnchor"]
						and addon.SettingsLayout.elements["enableGroupLootAnchor"].setting
						and addon.SettingsLayout.elements["enableGroupLootAnchor"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.groupLootLayout and addon.db.groupLootLayout.scale or 1 end,
				set = function(value)
					value = math.max(0.5, math.min(3.0, value or 1))
					value = math.floor(value * 100 + 0.5) / 100
					addon.db.groupLootLayout.scale = value
					addon.LootToast:ApplyGroupLootLayout()
				end,
				min = 0.5,
				max = 3,
				step = 0.05,
				parent = true,
				default = 1,
				sType = "slider",
			},
		},
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cLoot, data)

addon.functions.SettingsCreateHeadline(cLoot, L["lootToastSectionTitle"])

data = {
	{
		var = "enableLootToastAnchor",
		text = L["moveLootToast"],
		desc = L["moveLootToastDesc"],
		func = function(value)
			addon.db.enableGroupLootAnchor = value and true or false
			if addon.LootToast and addon.LootToast.OnGroupRollAnchorOptionChanged then addon.LootToast:OnGroupRollAnchorOptionChanged(addon.db.enableGroupLootAnchor) end
			addon.functions.initLootToast()
		end,
		children = {
			{
				text = "|cffffd700" .. L["lootToastAnchorEditModeHint"] .. "|r",
				sType = "hint",
			},
		},
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cLoot, data)

addon.functions.SettingsCreateHeadline(cLoot, L["lootToastFilterSettings"])

data = {
	{
		var = "enableLootToastFilter",
		text = L["enableLootToastFilter"],
		desc = L["enableLootToastFilterDesc"],
		func = function(value)
			addon.db.enableLootToastFilter = value and true or false
			addon.functions.initLootToast()
		end,
		children = {
			{
				var = "enableLootToastCustomSound",
				text = L["enableLootToastCustomSound"],
				get = function() return addon.db["lootToastUseCustomSound"] or false end,
				func = function(v) addon.db["lootToastUseCustomSound"] = v end,
				parentCheck = function()
					return addon.SettingsLayout.elements["enableLootToastFilter"]
						and addon.SettingsLayout.elements["enableLootToastFilter"].setting
						and addon.SettingsLayout.elements["enableLootToastFilter"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
				children = {
					{
						listFunc = function()
							if addon.ChatIM and addon.ChatIM.BuildSoundTable and not addon.ChatIM.availableSounds then addon.ChatIM:BuildSoundTable() end
							local tList = { [""] = "" }
							for name in pairs(addon.ChatIM.availableSounds or {}) do
								tList[name] = name
							end
							return tList
						end,
						text = L["lootToastCustomSound"],
						get = function() return addon.db.lootToastCustomSoundFile or "" end,
						set = function(key)
							addon.db.lootToastCustomSoundFile = key
							local file = addon.ChatIM.availableSounds and addon.ChatIM.availableSounds[key]
							if file then PlaySoundFile(file, "Master") end
						end,
						parentCheck = function()
							return addon.SettingsLayout.elements["enableLootToastFilter"]
								and addon.SettingsLayout.elements["enableLootToastFilter"].setting
								and addon.SettingsLayout.elements["enableLootToastFilter"].setting:GetValue() == true
								and addon.SettingsLayout.elements["enableLootToastCustomSound"]
								and addon.SettingsLayout.elements["enableLootToastCustomSound"].setting
								and addon.SettingsLayout.elements["enableLootToastCustomSound"].setting:GetValue() == true
						end,
						parent = true,
						default = "",
						var = "lootToastCustomSound",
						type = Settings.VarType.String,
						sType = "dropdown",
						-- TODO notify geht nicht
						notify = "enableLootToastFilter",
					},
				},
			},
		},
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cLoot, data)

addon.functions.SettingsCreateText(cLoot, "|c" .. ITEM_QUALITY_COLORS[3].color:GenerateHexColor() .. ITEM_QUALITY3_DESC .. "|r")

data = {
	{
		var = "lootToastCheckIlvl_rare",
		text = L["lootToastCheckIlvl"],
		get = function() return addon.db.lootToastFilters[3].ilvl or false end,
		func = function(value) addon.db.lootToastFilters[3].ilvl = value end,
		children = {
			{
				var = "lootToastItemLevel_rare",
				text = L["lootToastItemLevel"],
				parentCheck = function()
					return addon.SettingsLayout.elements["enableLootToastFilter"]
						and addon.SettingsLayout.elements["enableLootToastFilter"].setting
						and addon.SettingsLayout.elements["enableLootToastFilter"].setting:GetValue() == true
						and addon.SettingsLayout.elements["lootToastCheckIlvl_rare"]
						and addon.SettingsLayout.elements["lootToastCheckIlvl_rare"].setting
						and addon.SettingsLayout.elements["lootToastCheckIlvl_rare"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.lootToastItemLevels and addon.db.lootToastItemLevels[3] or 0 end,
				set = function(value) addon.db.lootToastItemLevels[3] = value end,
				min = 0,
				max = 1000,
				step = 1,
				element = addon.SettingsLayout.elements["enableLootToastFilter"].element,
				parent = true,
				default = 0,
				sType = "slider",
			},
		},
		parent = true,
		element = addon.SettingsLayout.elements["enableLootToastFilter"].element,
		parentCheck = function()
			return addon.SettingsLayout.elements["enableLootToastFilter"]
				and addon.SettingsLayout.elements["enableLootToastFilter"].setting
				and addon.SettingsLayout.elements["enableLootToastFilter"].setting:GetValue() == true
		end,
		notify = "enableLootToastFilter",
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cLoot, data)

addon.functions.SettingsCreateHeadline(cLoot, L["dungeonJournalLootSpecIcons"])

data = {
	{
		var = "dungeonJournalLootSpecIcons",
		text = L["dungeonJournalLootSpecIcons"],
		desc = L["dungeonJournalLootSpecIconsDesc"],
		func = function(value)
			addon.db["dungeonJournalLootSpecIcons"] = value
			if addon.DungeonJournalLootSpec and addon.DungeonJournalLootSpec.SetEnabled then addon.DungeonJournalLootSpec:SetEnabled(value) end
		end,
		children = {
			{
				list = {
					[1] = L["dungeonJournalLootSpecAnchorTop"],
					[2] = L["dungeonJournalLootSpecAnchorBottom"],
				},
				text = L["dungeonJournalLootSpecAnchor"],
				get = function() return addon.db["dungeonJournalLootSpecAnchor"] end,
				set = function(key)
					addon.db["dungeonJournalLootSpecAnchor"] = tonumber(key) or 1
					if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"]
						and addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"].setting
						and addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"].setting:GetValue() == true
				end,
				parent = true,
				default = 1,
				var = "dungeonJournalLootSpecAnchor",
				type = Settings.VarType.Number,
				sType = "dropdown",
			},
			{
				var = "dungeonJournalLootSpecOffsetX",
				text = L["dungeonJournalLootSpecOffsetX"],
				parentCheck = function()
					return addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"]
						and addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"].setting
						and addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.dungeonJournalLootSpecOffsetX or 0 end,
				set = function(value)
					addon.db["dungeonJournalLootSpecOffsetX"] = value
					if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
				end,
				min = -200,
				max = 200,
				step = 1,
				parent = true,
				default = 0,
				sType = "slider",
			},
			{
				var = "dungeonJournalLootSpecOffsetY",
				text = L["dungeonJournalLootSpecOffsetY"],
				parentCheck = function()
					return addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"]
						and addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"].setting
						and addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.dungeonJournalLootSpecOffsetY or 0 end,
				set = function(value)
					addon.db["dungeonJournalLootSpecOffsetY"] = value
					if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
				end,
				min = -200,
				max = 200,
				step = 1,
				parent = true,
				default = 0,
				sType = "slider",
			},
			{
				var = "dungeonJournalLootSpecSpacing",
				text = L["dungeonJournalLootSpecSpacing"],
				parentCheck = function()
					return addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"]
						and addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"].setting
						and addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.dungeonJournalLootSpecSpacing or 0 end,
				set = function(value)
					addon.db["dungeonJournalLootSpecSpacing"] = value
					if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
				end,
				min = 0,
				max = 40,
				step = 1,
				parent = true,
				default = 0,
				sType = "slider",
			},
			{
				var = "dungeonJournalLootSpecScale",
				text = L["dungeonJournalLootSpecScale"],
				parentCheck = function()
					return addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"]
						and addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"].setting
						and addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.dungeonJournalLootSpecScale or 0 end,
				set = function(value)
					addon.db["dungeonJournalLootSpecScale"] = value
					if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
				end,
				min = 0.5,
				max = 2,
				step = 0.05,
				parent = true,
				default = 0,
				sType = "slider",
			},
			{
				var = "dungeonJournalLootSpecIconPadding",
				text = L["dungeonJournalLootSpecIconPadding"],
				parentCheck = function()
					return addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"]
						and addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"].setting
						and addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.dungeonJournalLootSpecIconPadding or 0 end,
				set = function(value)
					addon.db["dungeonJournalLootSpecIconPadding"] = value
					if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
				end,
				min = 0,
				max = 0.2,
				step = 0.01,
				parent = true,
				default = 0,
				sType = "slider",
			},
			{

				var = "dungeonJournalLootSpecShowAll",
				text = L["dungeonJournalLootSpecShowAll"],
				desc = L["dungeonJournalLootSpecShowAllDesc"],
				func = function(v) addon.db["dungeonJournalLootSpecShowAll"] = v end,
				parentCheck = function()
					return addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"]
						and addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"].setting
						and addon.SettingsLayout.elements["dungeonJournalLootSpecIcons"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
			},
		},
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cLoot, data)
----- REGION END

function addon.functions.initLootFrame() end

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
