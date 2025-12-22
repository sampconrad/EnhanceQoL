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
			addon.db.enableLootToastAnchor = value and true or false
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
		notify = "enableLootToastCustomSound",
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
						optionfunc = function()
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
						sType = "sounddropdown",
					},
				},
			},
		},
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cLoot, data)

for i = 3, 5 do
	addon.functions.SettingsCreateText(cLoot, "|c" .. ITEM_QUALITY_COLORS[i].color:GenerateHexColor() .. _G["ITEM_QUALITY" .. i .. "_DESC"] .. "|r")

	data = {
		{
			var = "lootToastCheckIlvl_" .. i,
			text = L["lootToastCheckIlvl"],
			get = function() return addon.db.lootToastFilters and addon.db.lootToastFilters[i] and addon.db.lootToastFilters[i].ilvl or false end,
			func = function(value)
				addon.db.lootToastFilters = addon.db.lootToastFilters or {}
				addon.db.lootToastFilters[i] = addon.db.lootToastFilters[i] or {}
				addon.db.lootToastFilters[i].ilvl = value
			end,
			children = {
				{
					var = "lootToastItemLevel_" .. i,
					text = L["lootToastItemLevel"],
					parentCheck = function()
						return addon.SettingsLayout.elements["enableLootToastFilter"]
							and addon.SettingsLayout.elements["enableLootToastFilter"].setting
							and addon.SettingsLayout.elements["enableLootToastFilter"].setting:GetValue() == true
							and addon.SettingsLayout.elements["lootToastCheckIlvl_" .. i]
							and addon.SettingsLayout.elements["lootToastCheckIlvl_" .. i].setting
							and addon.SettingsLayout.elements["lootToastCheckIlvl_" .. i].setting:GetValue() == true
					end,
					get = function() return addon.db and addon.db.lootToastItemLevels and addon.db.lootToastItemLevels[i] or 0 end,
					set = function(value)
						addon.db.lootToastItemLevels = addon.db.lootToastItemLevels or {}
						addon.db.lootToastItemLevels[i] = addon.db.lootToastItemLevels[i] or {}
						addon.db.lootToastItemLevels[i] = value
					end,
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

	addon.functions.SettingsCreateMultiDropdown(cLoot, {
		var = "lootToastFilters_" .. i,
		subvar = i,
		text = L["lootToastAlwaysShow"],
		parent = true,
		element = addon.SettingsLayout.elements["enableLootToastFilter"].element,
		parentCheck = function()
			return addon.SettingsLayout.elements["enableLootToastFilter"]
				and addon.SettingsLayout.elements["enableLootToastFilter"].setting
				and addon.SettingsLayout.elements["enableLootToastFilter"].setting:GetValue() == true
		end,
		options = {
			{ value = "mounts", text = L["lootToastAlwaysShowMounts"] },
			{ value = "pets", text = L["lootToastAlwaysShowPets"] },
			{ value = "upgrade", text = L["lootToastAlwaysShowUpgrades"] },
		},
	})
end

local function isLootToastFilterEnabled()
	return addon.SettingsLayout.elements["enableLootToastFilter"]
		and addon.SettingsLayout.elements["enableLootToastFilter"].setting
		and addon.SettingsLayout.elements["enableLootToastFilter"].setting:GetValue() == true
end

addon.db.lootToastIncludeIDs = addon.db.lootToastIncludeIDs or {}

local function addInclude(input, editBox)
	local rawInput = strtrim(tostring(input or ""))
	if rawInput == "" then
		if editBox then editBox:SetText("") end
		return
	end

	local id = tonumber(rawInput)
	if not id then id = tonumber(string.match(rawInput, "item:(%d+)")) end
	if not id then
		print("|cffff0000Invalid input!|r")
		if editBox then editBox:SetText("") end
		return
	end

	local eItem
	if type(rawInput) == "string" and rawInput:find("|Hitem:") then
		eItem = Item:CreateFromItemLink(rawInput)
	else
		eItem = Item:CreateFromItemID(id)
	end

	if eItem and not eItem:IsItemEmpty() then
		eItem:ContinueOnItemLoad(function()
			local name = eItem:GetItemName()
			local itemID = eItem:GetItemID()
			if not name or not itemID then
				print(L["Item id does not exist"])
				if editBox then editBox:SetText("") end
				return
			end

			if not addon.db.lootToastIncludeIDs[itemID] then
				addon.db.lootToastIncludeIDs[itemID] = string.format("%s (%d)", name, itemID)
				print(L["lootToastItemAdded"]:format(name, itemID))
			end

			if editBox then editBox:SetText("") end
			Settings.NotifyUpdate("EQOL_lootToastIncludeRemove")
		end)
	else
		print(L["Item id does not exist"])
		if editBox then editBox:SetText("") end
	end
end

local includeDialogKey = "EQOL_LOOT_INCLUDE_ADD"
StaticPopupDialogs[includeDialogKey] = StaticPopupDialogs[includeDialogKey]
	or {
		text = L["Include"],
		button1 = ACCEPT,
		button2 = CANCEL,
		hasEditBox = true,
		editBoxWidth = 280,
		enterClicksFirstButton = true,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
StaticPopupDialogs[includeDialogKey].OnShow = function(self)
	local editBox = self.editBox or self:GetEditBox()
	editBox:SetText("")
	editBox:SetFocus()
end
StaticPopupDialogs[includeDialogKey].OnAccept = function(self)
	local editBox = self.editBox or self:GetEditBox()
	addInclude(editBox:GetText(), editBox)
end
StaticPopupDialogs[includeDialogKey].EditBoxOnEnterPressed = function(editBox)
	local parent = editBox:GetParent()
	if parent and parent.button1 then parent.button1:Click() end
end

addon.functions.SettingsCreateHeadline(cLoot, L["Include"])

local lootLayout = SettingsPanel:GetLayout(cLoot)
local includeButton = CreateSettingsButtonInitializer("", L["Include"], function() StaticPopup_Show(includeDialogKey) end, L["includeInfoLoot"], true)
includeButton:SetParentInitializer(addon.SettingsLayout.elements["enableLootToastFilter"].element, isLootToastFilterEnabled)
lootLayout:AddInitializer(includeButton)

local function buildIncludeDropdownList()
	addon.db.lootToastIncludeIDs = addon.db.lootToastIncludeIDs or {}
	local list = {}
	list[""] = ""
	for i, v in pairs(addon.db.lootToastIncludeIDs) do
		local key = tostring(i)
		list[key] = v
	end
	return list
end

local function clearIncludeDropdownSelection()
	local entry = addon.SettingsLayout.elements["lootToastIncludeRemove"]
	if entry and entry.setting then entry.setting:SetValue("") end
end

local function removeIncludeEntry(key)
	if not key or key == "" then return end
	addon.db.lootToastIncludeIDs = addon.db.lootToastIncludeIDs or {}
	local index = tonumber(key) or key
	if not addon.db.lootToastIncludeIDs[index] then return end
	addon.db.lootToastIncludeIDs[index] = nil
	Settings.NotifyUpdate("EQOL_lootToastIncludeRemove")
	clearIncludeDropdownSelection()
end

local includeRemoveDialogKey = "EQOL_LOOT_INCLUDE_REMOVE"
StaticPopupDialogs[includeRemoveDialogKey] = StaticPopupDialogs[includeRemoveDialogKey]
	or {
		text = L["lootToastIncludeRemoveConfirm"],
		button1 = ACCEPT,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
StaticPopupDialogs[includeRemoveDialogKey].OnAccept = function(_, data) removeIncludeEntry(data) end

addon.functions.SettingsCreateDropdown(cLoot, {
	var = "lootToastIncludeRemove",
	text = string.format("%s %s", REMOVE, L["Include"]),
	listFunc = buildIncludeDropdownList,
	get = function() return "" end,
	set = function(key)
		if not key or key == "" then return end
		local index = tonumber(key) or key
		addon.db.lootToastIncludeIDs = addon.db.lootToastIncludeIDs or {}
		local label = addon.db.lootToastIncludeIDs[index] or tostring(index)
		StaticPopup_Show(includeRemoveDialogKey, label, nil, index)
		clearIncludeDropdownSelection()
	end,
	parent = true,
	element = addon.SettingsLayout.elements["enableLootToastFilter"].element,
	parentCheck = isLootToastFilterEnabled,
	default = "",
	type = Settings.VarType.String,
})

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
				get = function()
					local value = addon.db and addon.db.dungeonJournalLootSpecScale or 1
					if value <= 0 then value = 1 end
					return value
				end,
				set = function(value)
					addon.db["dungeonJournalLootSpecScale"] = value
					if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
				end,
				min = 0.5,
				max = 2,
				step = 0.05,
				parent = true,
				default = 1,
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
