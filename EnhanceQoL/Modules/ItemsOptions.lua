local addonName, addon = ...

local L = addon.L
local AceGUI = addon.AceGUI
local math = math
local UnitClass = UnitClass

local headerClassInfo = L["headerClassInfo"]:format(select(1, UnitClass("player")))

local function ensureDisplayDB()
	if addon.functions and addon.functions.ensureDisplayDB then addon.functions.ensureDisplayDB() end
end

local function refreshLootToast()
	if addon.functions and addon.functions.initLootToast then addon.functions.initLootToast() end
end

local onInspect = addon.functions and addon.functions.onInspect

-- Check if a misc option exists (avoids empty debug-only pages)

local function addLootFrame(container, d)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)

	local data = {
		{
			parent = "",
			var = "autoQuickLoot",
			desc = L["autoQuickLootDesc"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["autoQuickLoot"] = value
				container:ReleaseChildren()
				addLootFrame(container)
			end,
		},
		{
			parent = "",
			var = "autoHideBossBanner",
			text = L["autoHideBossBanner"],
			desc = L["autoHideBossBannerDesc"],
			type = "CheckBox",
			callback = function(self, _, value) addon.db["autoHideBossBanner"] = value end,
		},
		{
			parent = "",
			var = "hideAzeriteToast",
			text = L["hideAzeriteToast"],
			desc = L["hideAzeriteToastDesc"],
			type = "CheckBox",
			callback = function(self, _, value)
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

	table.sort(data, function(a, b)
		local textA = a.text or L[a.var]
		local textB = b.text or L[b.var]
		return textA < textB
	end)

	for _, checkboxData in ipairs(data) do
		local desc
		if checkboxData.desc then desc = checkboxData.desc end
		local text
		if checkboxData.text then
			text = checkboxData.text
		else
			text = L[checkboxData.var]
		end
		local uFunc = function(self, _, value) addon.db[checkboxData.var] = value end
		if checkboxData.callback then uFunc = checkboxData.callback end
		local cb = addon.functions.createCheckboxAce(text, addon.db[checkboxData.var], uFunc, desc)
		groupCore:AddChild(cb)
	end

	if addon.db["autoQuickLoot"] then
		local cbShift = addon.functions.createCheckboxAce(L["autoQuickLootWithShift"], addon.db["autoQuickLootWithShift"], function(self, _, value) addon.db["autoQuickLootWithShift"] = value end)
		groupCore:AddChild(cbShift)
	end

	local groupRollGroup = addon.functions.createContainer("InlineGroup", "List")
	groupRollGroup:SetTitle(L["groupLootRollFrames"] or L["groupLootAnchorLabel"] or "Group loot roll frames")
	wrapper:AddChild(groupRollGroup)

	local groupRollToggle = addon.functions.createCheckboxAce(
		L["enableGroupLootAnchorOption"] or L["groupLootAnchorLabel"] or "Move group loot roll frames",
		addon.db.enableGroupLootAnchor,
		function(_, _, value)
			addon.db.enableGroupLootAnchor = value and true or false
			if addon.LootToast and addon.LootToast.OnGroupRollAnchorOptionChanged then addon.LootToast:OnGroupRollAnchorOptionChanged(addon.db.enableGroupLootAnchor) end
			refreshLootToast()
			container:ReleaseChildren()
			addLootFrame(container)
		end,
		L["enableGroupLootAnchorDesc"]
	)
	groupRollGroup:AddChild(groupRollToggle)

	if addon.db.enableGroupLootAnchor then
		local layout = addon.db.groupLootLayout or {}
		local currentScale = layout.scale or 1
		local sliderLabel = string.format("%s: %.2f", L["groupLootScale"] or "Loot roll frame scale", currentScale)
		local sliderScale = addon.functions.createSliderAce(sliderLabel, currentScale, 0.5, 3.0, 0.05, function(self, _, val)
			val = math.max(0.5, math.min(3.0, val or 1))
			val = math.floor(val * 100 + 0.5) / 100
			layout.scale = val
			addon.db.groupLootLayout = layout
			self:SetLabel(string.format("%s: %.2f", L["groupLootScale"] or "Loot roll frame scale", val))
			if addon.LootToast and addon.LootToast.ApplyGroupLootLayout then addon.LootToast:ApplyGroupLootLayout() end
		end)
		groupRollGroup:AddChild(sliderScale)
	end

	local lootToastGroup = addon.functions.createContainer("InlineGroup", "List")
	lootToastGroup:SetTitle(L["lootToastSectionTitle"])
	wrapper:AddChild(lootToastGroup)

	local anchorToggle = addon.functions.createCheckboxAce(L["moveLootToast"], addon.db.enableLootToastAnchor, function(self, _, value)
		addon.db.enableLootToastAnchor = value
		if addon.LootToast and addon.LootToast.OnAnchorOptionChanged then addon.LootToast:OnAnchorOptionChanged(value) end
		refreshLootToast()
		container:ReleaseChildren()
		addLootFrame(container)
	end, L["moveLootToastDesc"])
	lootToastGroup:AddChild(anchorToggle)

	local editModeAvailable = addon.EditMode and addon.EditMode.IsAvailable and addon.EditMode:IsAvailable()
	if editModeAvailable then
		local anchorHint = addon.functions.createLabelAce("", nil, nil, 12)
		anchorHint:SetFullWidth(true)
		local hintText = L["lootToastAnchorEditModeHint"] or L["lootToastAnchorLabel"] or ""
		if addon.db.enableLootToastAnchor then
			anchorHint:SetText("|cffffd700" .. hintText .. "|r")
		else
			anchorHint:SetText("|cff999999" .. hintText .. "|r")
		end
		lootToastGroup:AddChild(anchorHint)
	else
		local anchorButton = addon.functions.createButtonAce(L["lootToastAnchorButton"] or "", 200, function()
			if not addon.db.enableLootToastAnchor then return end
			addon.LootToast:ToggleAnchorPreview()
		end)
		anchorButton:SetFullWidth(true)
		anchorButton:SetDisabled(not addon.db.enableLootToastAnchor)
		lootToastGroup:AddChild(anchorButton)

		local anchorLabel = addon.functions.createLabelAce("", nil, nil, 12)
		anchorLabel:SetFullWidth(true)
		local manualHint = L["lootToastAnchorManualHint"] or L["lootToastAnchorLabel"] or ""
		if addon.db.enableLootToastAnchor then
			anchorLabel:SetText("|cffffd700" .. manualHint .. "|r")
		else
			anchorLabel:SetText("|cff999999" .. manualHint .. "|r")
		end
		lootToastGroup:AddChild(anchorLabel)
	end

	local filterToggle = addon.functions.createCheckboxAce(L["enableLootToastFilter"], addon.db.enableLootToastFilter, function(self, _, value)
		addon.db.enableLootToastFilter = value
		refreshLootToast()
		container:ReleaseChildren()
		addLootFrame(container)
	end, L["enableLootToastFilterDesc"])
	lootToastGroup:AddChild(filterToggle)

	if addon.db.enableLootToastFilter then
		local filterGroup = addon.functions.createContainer("InlineGroup", "List")
		filterGroup:SetTitle(L["lootToastFilterSettings"])
		lootToastGroup:AddChild(filterGroup)

		local tabs = {
			{ text = ITEM_QUALITY3_DESC, value = tostring(Enum.ItemQuality.Rare) },
			{ text = ITEM_QUALITY4_DESC, value = tostring(Enum.ItemQuality.Epic) },
			{ text = ITEM_QUALITY5_DESC, value = tostring(Enum.ItemQuality.Legendary) },
			{ text = L["Include"], value = "include" },
		}

		local function buildTab(tabContainer, rarity)
			tabContainer:ReleaseChildren()
			if rarity == "include" then
				local eBox
				local dropIncludeList

				local function addInclude(input)
					local id = tonumber(input)
					if not id then id = tonumber(string.match(tostring(input), "item:(%d+)")) end
					if not id then
						print("|cffff0000Invalid input!|r")
						eBox:SetText("")
						return
					end
					local eItem
					if type(input) == "string" and input:find("|Hitem:") then
						eItem = Item:CreateFromItemLink(input)
					else
						eItem = Item:CreateFromItemID(id)
					end
					if eItem and not eItem:IsItemEmpty() then
						eItem:ContinueOnItemLoad(function()
							local name = eItem:GetItemName()
							if not name then
								print(L["Item id does not exist"])
								eBox:SetText("")
								return
							end
							if not addon.db.lootToastIncludeIDs[eItem:GetItemID()] then
								addon.db.lootToastIncludeIDs[eItem:GetItemID()] = string.format("%s (%d)", name, eItem:GetItemID())
								local list, order = addon.functions.prepareListForDropdown(addon.db.lootToastIncludeIDs)
								dropIncludeList:SetList(list, order)
								dropIncludeList:SetValue(nil)
								print(L["lootToastItemAdded"]:format(name, eItem:GetItemID()))
							end
							eBox:SetText("")
						end)
					else
						print(L["Item id does not exist"])
						eBox:SetText("")
					end
				end

				eBox = addon.functions.createEditboxAce(L["Item id or drag item"], nil, function(self, _, txt)
					if txt ~= "" and txt ~= L["Item id or drag item"] then addInclude(txt) end
				end)
				tabContainer:AddChild(eBox)

				local list, order = addon.functions.prepareListForDropdown(addon.db.lootToastIncludeIDs)
				dropIncludeList = addon.functions.createDropdownAce(L["IncludeVendorList"], list, order, nil)
				local btnRemove = addon.functions.createButtonAce(REMOVE, 100, function()
					local sel = dropIncludeList:GetValue()
					if sel then
						addon.db.lootToastIncludeIDs[sel] = nil
						local l, o = addon.functions.prepareListForDropdown(addon.db.lootToastIncludeIDs)
						dropIncludeList:SetList(l, o)
						dropIncludeList:SetValue(nil)
					end
				end)
				local label = addon.functions.createLabelAce("", nil, nil, 14)
				label:SetFullWidth(true)
				tabContainer:AddChild(label)
				label:SetText("|cffffd700" .. L["includeInfoLoot"] .. "|r")
				tabContainer:AddChild(dropIncludeList)
				tabContainer:AddChild(btnRemove)
			else
				local q = tonumber(rarity)
				local filter = addon.db.lootToastFilters[q]
				local label = addon.functions.createLabelAce("", nil, nil, 14)
				label:SetFullWidth(true)
				tabContainer:AddChild(label)

				local function refreshLabel()
					local text
					if rarity ~= "include" then
						local extras = {}
						if filter.mounts then table.insert(extras, MOUNTS:lower()) end
						if filter.pets then table.insert(extras, PETS:lower()) end
						if filter.upgrade then table.insert(extras, L["lootToastExtrasUpgrades"]) end
						local eText = ""
						if #extras > 0 then eText = L["alwaysShow"] .. table.concat(extras, " " .. L["andWord"] .. " ") end
						if filter.ilvl then
							text = L["lootToastSummaryIlvl"]:format(addon.db.lootToastItemLevels[q], eText)
						else
							text = L["lootToastSummaryNoIlvl"]:format(eText)
						end
					else
						text = L["lootToastExplanation"]
					end
					label:SetText("|cffffd700" .. text .. "|r")
				end

				tabContainer:AddChild(addon.functions.createCheckboxAce(L["lootToastCheckIlvl"], filter.ilvl, function(self, _, v)
					addon.db.lootToastFilters[q].ilvl = v
					filter.ilvl = v
					refreshLabel()
				end))
				local slider = addon.functions.createSliderAce(L["lootToastItemLevel"] .. ": " .. addon.db.lootToastItemLevels[q], addon.db.lootToastItemLevels[q], 0, 1000, 1, function(self, _, val)
					addon.db.lootToastItemLevels[q] = val
					self:SetLabel(L["lootToastItemLevel"] .. ": " .. val)
					refreshLabel()
				end)
				tabContainer:AddChild(slider)

				local alwaysList = {
					mounts = L["lootToastAlwaysShowMounts"],
					pets = L["lootToastAlwaysShowPets"],
					upgrade = L["lootToastAlwaysShowUpgrades"],
				}
				local alwaysOrder = { "mounts", "pets", "upgrade" }
				local dropdownAlways = addon.functions.createDropdownAce(L["lootToastAlwaysShow"], alwaysList, alwaysOrder, function(self, _, key, checked)
					if not key then return end
					local isChecked = checked and true or false
					if addon.db.lootToastFilters[q][key] ~= nil then
						addon.db.lootToastFilters[q][key] = isChecked
						filter[key] = isChecked
						self:SetItemValue(key, isChecked)
						refreshLabel()
					end
				end)
				dropdownAlways:SetMultiselect(true)
				for _, key in ipairs(alwaysOrder) do
					dropdownAlways:SetItemValue(key, not not filter[key])
				end
				tabContainer:AddChild(dropdownAlways)

				refreshLabel()
			end
			scroll:DoLayout()
		end

		local cbSound = addon.functions.createCheckboxAce(L["enableLootToastCustomSound"], addon.db.lootToastUseCustomSound, function(self, _, v)
			addon.db.lootToastUseCustomSound = v
			container:ReleaseChildren()
			addLootFrame(container)
		end)
		filterGroup:AddChild(cbSound)

		if addon.db.lootToastUseCustomSound then
			if addon.ChatIM and addon.ChatIM.BuildSoundTable and not addon.ChatIM.availableSounds then addon.ChatIM:BuildSoundTable() end
			local soundList = {}
			for name in pairs(addon.ChatIM.availableSounds or {}) do
				soundList[name] = name
			end
			local list, order = addon.functions.prepareListForDropdown(soundList)
			local dropSound = addon.functions.createDropdownAce(L["lootToastCustomSound"], list, order, function(self, _, val)
				addon.db.lootToastCustomSoundFile = val
				self:SetValue(val)
				local file = addon.ChatIM.availableSounds and addon.ChatIM.availableSounds[val]
				if file then PlaySoundFile(file, "Master") end
			end)
			dropSound:SetValue(addon.db.lootToastCustomSoundFile)
			filterGroup:AddChild(dropSound)
		end

		local tabGroup = addon.functions.createContainer("TabGroup", "Flow")
		tabGroup:SetTabs(tabs)
		tabGroup:SetCallback("OnGroupSelected", function(tabContainer, _, groupVal) buildTab(tabContainer, groupVal) end)
		filterGroup:AddChild(tabGroup)
		tabGroup:SelectTab(tabs[1].value)
	end

	local lootSpecGroup = addon.functions.createContainer("InlineGroup", "List")
	lootSpecGroup:SetTitle(L["dungeonJournalLootSpecIcons"])
	lootSpecGroup:SetFullWidth(true)
	wrapper:AddChild(lootSpecGroup)

	local function rebuildDungeonJournalLootSpec()
		lootSpecGroup:ReleaseChildren()

		local toggle = addon.functions.createCheckboxAce(L["dungeonJournalLootSpecIcons"], addon.db["dungeonJournalLootSpecIcons"], function(_, _, value)
			addon.db["dungeonJournalLootSpecIcons"] = value
			if addon.DungeonJournalLootSpec and addon.DungeonJournalLootSpec.SetEnabled then addon.DungeonJournalLootSpec:SetEnabled(value) end
			rebuildDungeonJournalLootSpec()
		end, L["dungeonJournalLootSpecIconsDesc"])
		if toggle.SetFullWidth then toggle:SetFullWidth(true) end
		lootSpecGroup:AddChild(toggle)

		if not addon.db["dungeonJournalLootSpecIcons"] then
			if scroll.DoLayout then scroll:DoLayout() end
			return
		end

		local anchorOptions = {
			["1"] = L["dungeonJournalLootSpecAnchorTop"],
			["2"] = L["dungeonJournalLootSpecAnchorBottom"],
		}

		local anchorRow = addon.functions.createContainer("InlineGroup", "Flow")
		anchorRow:SetFullWidth(true)

		local anchorDropdown = addon.functions.createDropdownAce(L["dungeonJournalLootSpecAnchor"], anchorOptions, { "1", "2" }, function(_, _, key)
			addon.db["dungeonJournalLootSpecAnchor"] = tonumber(key) or 1
			if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
		end)
		anchorDropdown:SetValue(tostring(addon.db["dungeonJournalLootSpecAnchor"] or 1))
		if anchorDropdown.SetRelativeWidth then anchorDropdown:SetRelativeWidth(0.5) end
		anchorRow:AddChild(anchorDropdown)

		local sliderOffsetX = addon.functions.createSliderAce(
			L["dungeonJournalLootSpecOffsetX"] .. ": " .. addon.db["dungeonJournalLootSpecOffsetX"],
			addon.db["dungeonJournalLootSpecOffsetX"],
			-200,
			200,
			1,
			function(self, _, val)
				addon.db["dungeonJournalLootSpecOffsetX"] = val
				self:SetLabel(L["dungeonJournalLootSpecOffsetX"] .. ": " .. tostring(val))
				if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
			end
		)
		if sliderOffsetX.SetRelativeWidth then sliderOffsetX:SetRelativeWidth(0.5) end
		anchorRow:AddChild(sliderOffsetX)
		lootSpecGroup:AddChild(anchorRow)

		local offsetRow = addon.functions.createContainer("InlineGroup", "Flow")
		offsetRow:SetFullWidth(true)

		local sliderOffsetY = addon.functions.createSliderAce(
			L["dungeonJournalLootSpecOffsetY"] .. ": " .. addon.db["dungeonJournalLootSpecOffsetY"],
			addon.db["dungeonJournalLootSpecOffsetY"],
			-200,
			200,
			1,
			function(self, _, val)
				addon.db["dungeonJournalLootSpecOffsetY"] = val
				self:SetLabel(L["dungeonJournalLootSpecOffsetY"] .. ": " .. tostring(val))
				if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
			end
		)
		if sliderOffsetY.SetRelativeWidth then sliderOffsetY:SetRelativeWidth(0.5) end
		offsetRow:AddChild(sliderOffsetY)

		local sliderSpacing = addon.functions.createSliderAce(
			L["dungeonJournalLootSpecSpacing"] .. ": " .. addon.db["dungeonJournalLootSpecSpacing"],
			addon.db["dungeonJournalLootSpecSpacing"],
			0,
			40,
			1,
			function(self, _, val)
				addon.db["dungeonJournalLootSpecSpacing"] = val
				self:SetLabel(L["dungeonJournalLootSpecSpacing"] .. ": " .. tostring(val))
				if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
			end
		)
		if sliderSpacing.SetRelativeWidth then sliderSpacing:SetRelativeWidth(0.5) end
		offsetRow:AddChild(sliderSpacing)
		lootSpecGroup:AddChild(offsetRow)

		local scaleRow = addon.functions.createContainer("InlineGroup", "Flow")
		scaleRow:SetFullWidth(true)

		local sliderScale = addon.functions.createSliderAce(
			L["dungeonJournalLootSpecScale"] .. ": " .. string.format("%.2f", addon.db["dungeonJournalLootSpecScale"]),
			addon.db["dungeonJournalLootSpecScale"],
			0.5,
			2,
			0.05,
			function(self, _, val)
				addon.db["dungeonJournalLootSpecScale"] = val
				self:SetLabel(L["dungeonJournalLootSpecScale"] .. ": " .. string.format("%.2f", val))
				if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
			end
		)
		if sliderScale.SetRelativeWidth then sliderScale:SetRelativeWidth(0.5) end
		scaleRow:AddChild(sliderScale)

		local sliderZoom = addon.functions.createSliderAce(
			L["dungeonJournalLootSpecIconPadding"] .. ": " .. string.format("%.2f", addon.db["dungeonJournalLootSpecIconPadding"]),
			addon.db["dungeonJournalLootSpecIconPadding"],
			0,
			0.2,
			0.01,
			function(self, _, val)
				addon.db["dungeonJournalLootSpecIconPadding"] = val
				self:SetLabel(L["dungeonJournalLootSpecIconPadding"] .. ": " .. string.format("%.2f", val))
				if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
			end
		)
		if sliderZoom.SetRelativeWidth then sliderZoom:SetRelativeWidth(0.5) end
		scaleRow:AddChild(sliderZoom)
		lootSpecGroup:AddChild(scaleRow)

		local showAll = addon.functions.createCheckboxAce(L["dungeonJournalLootSpecShowAll"], addon.db["dungeonJournalLootSpecShowAll"], function(_, _, value)
			addon.db["dungeonJournalLootSpecShowAll"] = value
			if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
		end, L["dungeonJournalLootSpecShowAllDesc"])
		if showAll.SetFullWidth then showAll:SetFullWidth(true) end
		lootSpecGroup:AddChild(showAll)

		if scroll.DoLayout then scroll:DoLayout() end
	end

	rebuildDungeonJournalLootSpec()

	scroll:DoLayout()
end

if addon.functions and addon.functions.RegisterOptionsPage then
	addon.functions.RegisterOptionsPage("items\001loot", addLootFrame)
end
