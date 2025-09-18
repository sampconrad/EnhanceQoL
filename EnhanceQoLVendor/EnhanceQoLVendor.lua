local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Vendor")
local lastEbox = nil
local sellMoreButton
local hasMoreItems = false
local sellMarkLookup = {}
local updateSellMarks
local tooltipCache = {}

local function inventoryOpen()
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then return true end
	local frames = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames or {}
	for _, frame in ipairs(frames) do
		if frame and frame:IsShown() then return true end
	end
	return false
end

local function updateSellMoreButton()
	if not sellMoreButton then return end
	if addon.db["vendorOnly12Items"] and hasMoreItems and MerchantFrame:IsShown() then
		sellMoreButton:ClearAllPoints()
		if MerchantRepairItemButton and MerchantRepairItemButton:IsShown() then
			sellMoreButton:SetPoint("TOPLEFT", MerchantRepairItemButton, "BOTTOMLEFT", 5, -5)
		elseif MerchantSellAllJunkButton and MerchantSellAllJunkButton:IsShown() then
			sellMoreButton:SetPoint("TOPRIGHT", MerchantSellAllJunkButton, "BOTTOMLEFT", -5, -5)
		else
			sellMoreButton:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 60, 60)
		end
		sellMoreButton:Show()
	else
		sellMoreButton:Hide()
	end
end

local frameLoad = CreateFrame("Frame")

local function updateLegend(value, value2)
	if not addon.aceFrame:IsShown() or nil == addon.Vendor.variables["labelExplained" .. value .. "line"] then return end
	local text = {}
	if addon.db["vendor" .. value .. "IgnoreWarbound"] then table.insert(text, L["vendorIgnoreWarbound"]) end
	if addon.db["vendor" .. value .. "IgnoreBoE"] then table.insert(text, L["vendorIgnoreBoE"]) end
	if addon.db["vendor" .. value .. "IgnoreUpgradable"] then table.insert(text, L["vendorIgnoreUpgradable"]) end

	addon.Vendor.variables["labelExplained" .. value .. "line"]:SetText(
		string.format(L["labelExplained" .. value .. "line"], (addon.Vendor.variables.avgItemLevelEquipped - value2), table.concat(text, "\n"))
	)
end

local function sellItems(items)
	local function sellNextItem()
		if not MerchantFrame:IsShown() then
			print(L["MerchantWindowClosed"])
			return
		end
		if #items == 0 then
			updateSellMoreButton()
			return
		end

		local item = table.remove(items, 1)
		C_Container.UseContainerItem(item.bag, item.slot)
		C_Timer.After(0.1, sellNextItem) -- 100ms Pause zwischen den Verkäufen
	end
	sellNextItem()
end

local function getTooltipInfo(bag, slot, quality)
	local key = bag .. "_" .. slot
	local cached = tooltipCache[key]
	if cached then return cached[1], cached[2], cached[3] end

	local bType
	local canUpgrade = false
	local isIgnoredUpgradeTrack = false
	local data = C_TooltipInfo.GetBagItem(bag, slot)
	if data then
		for _, v in pairs(data.lines) do
			if v.type == 20 then
				if v.leftText == ITEM_BIND_ON_EQUIP then
					bType = 2
				elseif v.leftText == ITEM_ACCOUNTBOUND_UNTIL_EQUIP or v.leftText == ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP then
					bType = 8
				elseif v.leftText == ITEM_ACCOUNTBOUND or v.leftText == ITEM_BIND_TO_BNETACCOUNT then
					bType = 7
				end
				break
			elseif v.type == 42 then
				local text = v.rightText or v.leftText
				if text then
					if addon.db["vendor" .. addon.Vendor.variables.tabNames[quality] .. "IgnoreUpgradable"] then
						local color = v.leftColor
						if color and color.r and color.g and color.b then
							if not (color.r > 0.5 and color.g > 0.5 and color.b > 0.5) then canUpgrade = true end
						end
					end
					local tier = text:gsub(".+:%s?", ""):gsub("%s?%d/%d", "")
					if tier then
						if
							(addon.db["vendor" .. addon.Vendor.variables.tabNames[quality] .. "IgnoreMythTrack"] and string.lower(L["upgradeLevelMythic"]) == string.lower(tier))
							or (addon.db["vendor" .. addon.Vendor.variables.tabNames[quality] .. "IgnoreHeroicTrack"] and string.lower(L["upgradeLevelHero"]) == string.lower(tier))
						then
							isIgnoredUpgradeTrack = true
						end
					end
				end
			end
		end
	end

	tooltipCache[key] = { bType, canUpgrade, isIgnoredUpgradeTrack }
	return bType, canUpgrade, isIgnoredUpgradeTrack
end
local function lookupItems()
	local _, avgItemLevelEquipped = GetAverageItemLevel()
	local itemsToSell = {}
	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local itemID = C_Container.GetContainerItemID(bag, slot)
			if itemID then
				local itemLink = C_Container.GetContainerItemLink(bag, slot)
				local itemName, _, quality, itemLevel, _, _, _, _, _, _, sellPrice, classID, subclassID, bindType, expansionID = C_Item.GetItemInfo(itemLink)
				if not itemName then
					C_Item.RequestLoadItemDataByID(itemID)
				else
					if sellPrice and sellPrice > 0 then
						if classID == 4 and subclassID == 5 and not C_TransmogCollection.PlayerHasTransmog(itemID) then
						-- Transmog not used don't sell
						elseif addon.db["vendorExcludeSellList"][itemID] then
						-- do nothing
						elseif addon.db["vendorIncludeSellList"][itemID] then
							if sellPrice > 0 then table.insert(itemsToSell, { bag = bag, slot = slot }) end
						elseif classID == 7 and addon.Vendor.variables.itemQualityFilter[quality] then
							local expTable = addon.db["vendor" .. addon.Vendor.variables.tabNames[quality] .. "CraftingExpansions"]
							if expTable and expTable[expansionID] then table.insert(itemsToSell, { bag = bag, slot = slot }) end
						elseif addon.Vendor.variables.itemQualityFilter[quality] then
							local effectiveILvl = C_Item.GetDetailedItemLevelInfo(itemLink)
							local bType, canUpgrade, isIgnoredUpgradeTrack = getTooltipInfo(bag, slot, quality)
							if bType and bindType < bType then bindType = bType end
							if not bType then bindType = 0 end
							if
								addon.Vendor.variables.itemTypeFilter[classID]
								and (not addon.Vendor.variables.itemSubTypeFilter[classID] or (addon.Vendor.variables.itemSubTypeFilter[classID] and addon.Vendor.variables.itemSubTypeFilter[classID][subclassID]))
								and addon.Vendor.variables.itemBindTypeQualityFilter[quality][bindType]
							then
								if not canUpgrade and not isIgnoredUpgradeTrack then
									local rIlvl = (avgItemLevelEquipped - addon.db["vendor" .. addon.Vendor.variables.tabNames[quality] .. "MinIlvlDif"])
									if addon.db["vendor" .. addon.Vendor.variables.tabNames[quality] .. "AbsolutIlvl"] then
										rIlvl = addon.db["vendor" .. addon.Vendor.variables.tabNames[quality] .. "MinIlvlDif"]
									end
									if effectiveILvl <= rIlvl then table.insert(itemsToSell, { bag = bag, slot = slot }) end
								end
							end
						end
					end
				end
			end
		end
	end
	return itemsToSell
end

local function checkItem()
	hasMoreItems = false
	updateSellMoreButton()
	local _, avgItemLevelEquipped = GetAverageItemLevel()
	local itemsToSell = lookupItems() or {}

	if #itemsToSell > 0 then
		if addon.db["vendorOnly12Items"] then
			if #itemsToSell > 12 then hasMoreItems = true end

			local limitedItems = {}
			for i = 1, math.min(12, #itemsToSell) do
				table.insert(limitedItems, itemsToSell[i])
			end
			itemsToSell = limitedItems
		end
		C_Timer.After(0.1, function() sellItems(itemsToSell) end)
	end
end

local function createSellMoreButton()
	if sellMoreButton then return end
	sellMoreButton = CreateFrame("Button", nil, MerchantFrame, "GameMenuButtonTemplate")
	sellMoreButton:SetSize(120, 25)

	sellMoreButton:SetText(L["vendorSellNext"])
	sellMoreButton:SetScript("OnClick", function(self)
		checkItem()
		self:Hide()
	end)
	sellMoreButton:Hide()
end

local eventHandlers = {
	["MERCHANT_SHOW"] = function()
		createSellMoreButton()
		if (IsShiftKeyDown() and addon.db["vendorSwapAutoSellShift"] == false) or (addon.db["vendorSwapAutoSellShift"] and not IsShiftKeyDown()) then
			updateSellMoreButton()
			return
		end
		checkItem()
	end,
	["MERCHANT_CLOSED"] = function()
		hasMoreItems = false
		updateSellMoreButton()
		wipe(tooltipCache)
	end,
	["BAG_UPDATE_DELAYED"] = function() wipe(tooltipCache) end,
	["ITEM_DATA_LOAD_RESULT"] = function(arg1, arg2)
		if arg2 == false and addon.aceFrame:IsShown() and lastEbox then
			StaticPopupDialogs["VendorWrongItemID"] = {
				text = L["Item id does not exist"],
				button1 = OKAY,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3, -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
			}
			StaticPopup_Show("VendorWrongItemID")
			lastEbox:SetText("")
		end
	end,
	["PLAYER_AVG_ITEM_LEVEL_UPDATE"] = function()
		local _, avgItemLevelEquipped = GetAverageItemLevel()
		addon.Vendor.variables.avgItemLevelEquipped = avgItemLevelEquipped
		for _, key in ipairs(addon.Vendor.variables.tabKeyNames) do
			local value = addon.Vendor.variables.tabNames[key]
			updateLegend(value, addon.db["vendor" .. value .. "MinIlvlDif"])
		end
	end,
	["INVENTORY_SEARCH_UPDATE"] = function()
		C_Timer.After(0, function() updateSellMarks() end)
	end,
}
local function registerEvents(frame)
	for event in pairs(eventHandlers) do
		frame:RegisterEvent(event)
	end
end

local function eventHandler(self, event, ...)
	if eventHandlers[event] then eventHandlers[event](...) end
end

registerEvents(frameLoad)
frameLoad:SetScript("OnEvent", eventHandler)

local function addVendorFrame(container, type)
	local text = {}
	local uText = {} -- Text for upgrade track
	local value = addon.Vendor.variables.tabNames[type]
	local labelHeadlineExplain
	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	container:AddChild(wrapper)

	local iqColor = ITEM_QUALITY_COLORS[type].hex .. _G["ITEM_QUALITY" .. type .. "_DESC"] .. "|r"

	local function updateLegend(sValue, sValue2)
		if not addon.aceFrame:IsShown() then return end
		local text = {}
		local uText = {}
		if addon.db["vendor" .. sValue .. "IgnoreWarbound"] then table.insert(text, L["vendorIgnoreWarbound"]) end
		if addon.db["vendor" .. sValue .. "IgnoreBoE"] then table.insert(text, L["vendorIgnoreBoE"]) end
		if addon.db["vendor" .. sValue .. "IgnoreUpgradable"] then table.insert(text, L["vendorIgnoreUpgradable"]) end

		if addon.db["vendor" .. sValue .. "IgnoreHeroicTrack"] then table.insert(uText, L["upgradeLevelHero"]) end
		if addon.db["vendor" .. sValue .. "IgnoreMythTrack"] then table.insert(uText, L["upgradeLevelMythic"]) end
		if #uText > 0 then table.insert(text, L["vendorIgnoreTrackItems"]:format(table.concat(uText, "/"))) end

		local lIlvl
		if addon.db["vendor" .. value .. "AbsolutIlvl"] then
			lIlvl = sValue2
		else
			lIlvl = addon.Vendor.variables.avgItemLevelEquipped - sValue2
		end

		labelHeadlineExplain:SetText("|cffffd700" .. L["labelExplainedline"]:format(iqColor, lIlvl, table.concat(text, " " .. L["andWord"] .. " ")) .. "|r")
		wrapper:DoLayout()
		updateSellMarks(nil, true)
	end

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)
	local labelHeadline = addon.functions.createLabelAce("|cffffd700" .. L["labelItemQualityline"]:format(iqColor), nil, nil, 14)
	groupCore:AddChild(labelHeadline)
	labelHeadline:SetFullWidth(true)

	local vendorEnable = addon.functions.createCheckboxAce(L["vendorEnable"]:format(iqColor), addon.db["vendor" .. value .. "Enable"], function(self, _, checked)
		addon.db["vendor" .. value .. "Enable"] = checked
		addon.Vendor.variables.itemQualityFilter[type] = checked

		container:ReleaseChildren()
		addVendorFrame(container, type)
	end)
	groupCore:AddChild(vendorEnable)

	if addon.Vendor.variables.itemQualityFilter[type] then
		local vendorEnable = addon.functions.createCheckboxAce(L["vendorAbsolutIlvl"], addon.db["vendor" .. value .. "AbsolutIlvl"], function(self, _, checked)
			addon.db["vendor" .. value .. "AbsolutIlvl"] = checked
			container:ReleaseChildren()
			addVendorFrame(container, type)
		end)
		groupCore:AddChild(vendorEnable)

		local data = {
			{ text = L["vendorIgnoreBoE"], var = "vendor" .. value .. "IgnoreBoE", filter = { 2 } },
			{ text = L["vendorIgnoreWarbound"], var = "vendor" .. value .. "IgnoreWarbound", filter = { 7, 8, 9 } },
		}
		if type ~= 1 then
			table.insert(data, { text = L["vendorIgnoreUpgradable"], var = "vendor" .. value .. "IgnoreUpgradable" })
			if type == 4 then
				table.insert(data, { text = L["vendorIgnoreHeroicTrack"], var = "vendor" .. value .. "IgnoreHeroicTrack" })
				table.insert(data, { text = L["vendorIgnoreMythTrack"], var = "vendor" .. value .. "IgnoreMythTrack" })
			end
		end

		table.sort(data, function(a, b) return a.text < b.text end)

		for _, cbData in ipairs(data) do
			local cbElement = addon.functions.createCheckboxAce(cbData.text, addon.db[cbData.var], function(self, _, checked)
				addon.db[cbData.var] = checked
				if cbData.filter then
					for _, v in pairs(cbData.filter) do
						addon.Vendor.variables.itemBindTypeQualityFilter[type][v] = not checked
					end
				end
				updateLegend(value, addon.db["vendor" .. value .. "MinIlvlDif"])
			end)
			groupCore:AddChild(cbElement)
		end

		local lIlvl
		local hText
		if addon.db["vendor" .. value .. "AbsolutIlvl"] then
			hText = L["vendorMinIlvl"]
			lIlvl = addon.db["vendor" .. value .. "MinIlvlDif"]
		else
			hText = L["vendorMinIlvlDif"]
			lIlvl = (addon.Vendor.variables.avgItemLevelEquipped - addon.db["vendor" .. value .. "MinIlvlDif"])
		end

		local vendorIlvl = addon.functions.createSliderAce(hText, addon.db["vendor" .. value .. "MinIlvlDif"], 1, 700, 1, function(self, _, value2)
			value2 = math.floor(value2)
			addon.db["vendor" .. value .. "MinIlvlDif"] = value2
			updateLegend(value, value2)
		end)
		groupCore:AddChild(vendorIlvl)

		local expList = {}
		for i = 0, LE_EXPANSION_LEVEL_CURRENT do
			expList[i] = _G["EXPANSION_NAME" .. i]
		end
		local list, order = addon.functions.prepareListForDropdown(expList, true)
		local dropCrafting = addon.functions.createDropdownAce(L["vendorCraftingExpansions"], list, order, function(self, event, key, checked)
			addon.db["vendor" .. value .. "CraftingExpansions"][key] = checked or nil
			updateSellMarks(nil, true)
		end)
		dropCrafting:SetMultiselect(true)
		for id, val in pairs(addon.db["vendor" .. value .. "CraftingExpansions"]) do
			if val then dropCrafting:SetItemValue(tonumber(id), true) end
		end
		groupCore:AddChild(dropCrafting)

		if addon.db["vendor" .. value .. "IgnoreWarbound"] then table.insert(text, L["vendorIgnoreWarbound"]) end
		if addon.db["vendor" .. value .. "IgnoreBoE"] then table.insert(text, L["vendorIgnoreBoE"]) end
		if addon.db["vendor" .. value .. "IgnoreUpgradable"] then table.insert(text, L["vendorIgnoreUpgradable"]) end

		if addon.db["vendor" .. value .. "IgnoreHeroicTrack"] then table.insert(uText, L["upgradeLevelHero"]) end
		if addon.db["vendor" .. value .. "IgnoreMythTrack"] then table.insert(uText, L["upgradeLevelMythic"]) end
		if #uText > 0 then table.insert(text, L["vendorIgnoreTrackItems"]:format(table.concat(uText, "/"))) end

		local groupInfo = addon.functions.createContainer("InlineGroup", "List")
		groupInfo:SetTitle(INFO)
		wrapper:AddChild(groupInfo)

		labelHeadlineExplain = addon.functions.createLabelAce("|cffffd700" .. L["labelExplainedline"]:format(iqColor, lIlvl, table.concat(text, " and ") .. "|r"), nil, nil, 14)
		groupInfo:AddChild(labelHeadlineExplain)
		groupInfo:SetFullWidth(true)
		labelHeadlineExplain:SetFullWidth(true)
	end
	updateSellMarks(nil, true)
end

local function addInExcludeFrame(container, type)
	local headText
	local dbValue
	local eBox
	local dropIncludeList
	if type == 0 then
		headText = L["vendorAddItemToExclude"]
		dbValue = "vendorExcludeSellList"
	else
		headText = L["vendorAddItemToInclude"]
		dbValue = "vendorIncludeSellList"
	end

	local function addInclude(input)
		local id = tonumber(input)

		-- Wenn keine Zahl, versuchen, die Item-ID aus einem Item-Link zu extrahieren
		if not id then id = string.match(input, "item:(%d+)") end
		if not id then
			print("|cffff0000Invalid input! Please provide a valid Item ID or drag an item.|r")
			eBox:SetText("")
			return
		end

		local eItem = Item:CreateFromItemID(tonumber(id))
		if eItem and not eItem:IsItemEmpty() then
			eItem:ContinueOnItemLoad(function()
				if not addon.db[dbValue][eItem:GetItemID()] then
					addon.db[dbValue][eItem:GetItemID()] = eItem:GetItemName()
					print(ADD .. ":", eItem:GetItemID(), eItem:GetItemName())
					local list, order = addon.functions.prepareListForDropdown(addon.db[dbValue])
					dropIncludeList:SetList(list, order)
					dropIncludeList:SetValue(nil) -- Setze die Auswahl zurück
					updateSellMarks(nil, true)
				end
				eBox:SetText("")
			end)
		end
	end

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	container:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)

	local labelHeadline = addon.functions.createLabelAce("|cffffd700" .. headText .. "|r", nil, nil, 14)
	groupCore:AddChild(labelHeadline)
	labelHeadline:SetFullWidth(true)

	eBox = addon.functions.createEditboxAce(L["Item id or drag item"], nil, function(self, _, dText)
		if dText ~= "" and dText ~= L["Item id or drag item"] then addInclude(dText) end
	end, nil)
	groupCore:AddChild(eBox)
	lastEbox = eBox

	local list, order = addon.functions.prepareListForDropdown(addon.db[dbValue])

	local groupEntries = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupEntries)

	dropIncludeList = addon.functions.createDropdownAce(L["IncludeVendorList"], list, order, nil)
	local btnRemoveItem = addon.functions.createButtonAce(REMOVE, 100, function(self, _, value)
		local selectedValue = dropIncludeList:GetValue() -- Hole den aktuellen Wert des Dropdowns
		if selectedValue then
			if addon.db[dbValue][selectedValue] then
				addon.db[dbValue][selectedValue] = nil -- Entferne aus der Datenbank
				-- Aktualisiere die Dropdown-Liste
				local list, order = addon.functions.prepareListForDropdown(addon.db[dbValue])
				dropIncludeList:SetList(list, order)
				dropIncludeList:SetValue(nil) -- Setze die Auswahl zurück
				updateSellMarks(nil, true)
			end
		end
	end)
	groupEntries:AddChild(dropIncludeList)
	groupEntries:AddChild(btnRemoveItem)
end

local function addGeneralFrame(container)
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
			text = L["vendorCraftShopperEnable"],
			var = "vendorCraftShopperEnable",
			func = function(self, _, checked)
				addon.db["vendorCraftShopperEnable"] = checked
				if checked then
					addon.Vendor.CraftShopper.EnableCraftShopper()
				else
					addon.Vendor.CraftShopper.DisableCraftShopper()
				end
			end,
			desc = L["vendorCraftShopperEnableDesc"],
		},
		{ text = L["vendorSwapAutoSellShift"], var = "vendorSwapAutoSellShift" },
		{
			text = L["vendorOnly12Items"],
			desc = L["vendorOnly12ItemsDesc"],
			var = "vendorOnly12Items",
			func = function(self, _, checked)
				addon.db["vendorOnly12Items"] = checked
				if MerchantRepairItemButton and MerchantRepairItemButton:IsShown() then createSellMoreButton() end
			end,
		},
		{
			text = L["vendorAltClickInclude"],
			desc = L["vendorAltClickIncludeDesc"],
			var = "vendorAltClickInclude",
		},
	}
	table.sort(data, function(a, b) return a.text < b.text end)

	for _, cbData in ipairs(data) do
		local func = function(self, _, checked) addon.db[cbData.var] = checked end
		if cbData.func then func = cbData.func end
		local desc
		if cbData.desc then desc = cbData.desc end
		local cbElement = addon.functions.createCheckboxAce(cbData.text, addon.db[cbData.var], func, desc)
		groupCore:AddChild(cbElement)
	end

	local groupMark = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupMark)

	data = {
		{
			text = L["vendorShowSellOverlay"],
			var = "vendorShowSellOverlay",
			func = function(self, _, checked)
				addon.db["vendorShowSellOverlay"] = checked
				if inventoryOpen() then updateSellMarks(nil, true) end
				container:ReleaseChildren()
				addGeneralFrame(container)
			end,
		},
		{
			text = L["vendorShowSellTooltip"],
			var = "vendorShowSellTooltip",
			func = function(self, _, checked)
				addon.db["vendorShowSellTooltip"] = checked
				if inventoryOpen() then updateSellMarks(nil, true) end
			end,
		},
	}

	if addon.db["vendorShowSellOverlay"] then
		table.insert(data, {
			text = L["vendorShowSellHighContrast"],
			var = "vendorShowSellHighContrast",
			func = function(self, _, checked)
				addon.db["vendorShowSellHighContrast"] = checked
				if inventoryOpen() then updateSellMarks(nil, true) end
			end,
		})
	end
	table.sort(data, function(a, b) return a.text < b.text end)

	for _, cbData in ipairs(data) do
		local func = function(self, _, checked) addon.db[cbData.var] = checked end
		if cbData.func then func = cbData.func end
		local desc
		if cbData.desc then desc = cbData.desc end
		local cbElement = addon.functions.createCheckboxAce(cbData.text, addon.db[cbData.var], func, desc)
		groupMark:AddChild(cbElement)
	end
	scroll:DoLayout()
end

addon.variables.statusTable.groups["vendor"] = true
addon.functions.addToTree(nil, {
	value = "vendor",
	text = L["Vendor"],
	children = {
		{ value = "common", text = ITEM_QUALITY_COLORS[1].hex .. _G["ITEM_QUALITY1_DESC"] .. "|r" },
		{ value = "uncommon", text = ITEM_QUALITY_COLORS[2].hex .. _G["ITEM_QUALITY2_DESC"] .. "|r" },
		{ value = "rare", text = ITEM_QUALITY_COLORS[3].hex .. _G["ITEM_QUALITY3_DESC"] .. "|r" },
		{ value = "epic", text = ITEM_QUALITY_COLORS[4].hex .. _G["ITEM_QUALITY4_DESC"] .. "|r" },
		{ value = "include", text = L["Include"] },
		{ value = "exclude", text = L["Exclude"] },
	},
}, true)

function addon.Vendor.functions.treeCallback(container, group)
	lastEbox = nil
	container:ReleaseChildren() -- Entfernt vorherige Inhalte
	local _, avgItemLevelEquipped = GetAverageItemLevel()
	addon.Vendor.variables.avgItemLevelEquipped = avgItemLevelEquipped
	-- Prüfen, welche Gruppe ausgewählt wurde
	if group == "vendor" then
		addGeneralFrame(container)
	elseif group == "vendor\001common" then
		addVendorFrame(container, 1)
	elseif group == "vendor\001uncommon" then
		addVendorFrame(container, 2)
	elseif group == "vendor\001rare" then
		addVendorFrame(container, 3)
	elseif group == "vendor\001epic" then
		addVendorFrame(container, 4)
	elseif group == "vendor\001include" then
		addInExcludeFrame(container, 1)
	elseif group == "vendor\001exclude" then
		addInExcludeFrame(container, 0)
	end
end

function updateSellMarks(_, resetCache)
	if resetCache then wipe(tooltipCache) end

	local overlay = addon.db["vendorShowSellOverlay"]
	local tooltip = addon.db["vendorShowSellTooltip"]
	local frames = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames or {}

	local function clearFrame(frame)
		if frame and frame:IsShown() then
			for _, itemButton in frame:EnumerateValidItems() do
				if itemButton.ItemMarkSell then
					itemButton.ItemMarkSell:Hide()
					itemButton.SellOverlay:Hide()
				end
			end
		end
	end

	if not overlay and not tooltip then
		clearFrame(ContainerFrameCombinedBags)
		for _, frame in ipairs(frames) do
			clearFrame(frame)
		end
		wipe(sellMarkLookup)
		return
	end

	wipe(sellMarkLookup)

	local items = lookupItems() or {}
	for _, v in ipairs(items) do
		sellMarkLookup[v.bag .. "_" .. v.slot] = true
	end

	local function processFrame(frame)
		if frame and frame:IsShown() then
			for _, itemButton in frame:EnumerateValidItems() do
				local bag = itemButton:GetBagID()
				local slot = itemButton:GetID()
				local key = bag .. "_" .. slot
				if overlay and sellMarkLookup[key] then
					if not itemButton.ItemMarkSell then
						itemButton.ItemMarkSell = itemButton:CreateTexture(nil, "OVERLAY", nil, 7)
						itemButton.ItemMarkSell:SetTexture("Interface\\buttons\\ui-grouploot-coin-up")
						itemButton.ItemMarkSell:SetSize(16, 16)
						itemButton.ItemMarkSell:SetPoint("BOTTOMLEFT", itemButton, "BOTTOMLEFT", 0, -1)
						itemButton.SellOverlay = itemButton:CreateTexture(nil, "OVERLAY", nil, 6)
						itemButton.SellOverlay:SetAllPoints()
						itemButton.SellOverlay:SetColorTexture(1, 0, 0, 0.45)
					end
					itemButton.ItemMarkSell:Show()
					if addon.db["vendorShowSellHighContrast"] then
						itemButton.SellOverlay:Show()
					else
						itemButton.SellOverlay:Hide()
					end
					if not itemButton.matchesSearch then
						itemButton.ItemMarkSell:SetAlpha(0.1)
						itemButton.SellOverlay:Hide()
					else
						if addon.db["vendorShowSellHighContrast"] then itemButton.SellOverlay:Show() end
						itemButton.ItemMarkSell:SetAlpha(1)
					end
				elseif itemButton.ItemMarkSell then
					itemButton.ItemMarkSell:Hide()
					itemButton.SellOverlay:Hide()
				end
			end
		end
	end

	processFrame(ContainerFrameCombinedBags)
	for _, frame in ipairs(frames) do
		processFrame(frame)
	end
end

local function AltClickHook(self, button)
	if not addon.db["vendorAltClickInclude"] then return end
	if not IsAltKeyDown() or not (button == "LeftButton" or button == "RightButton") then return end
	local slot, bag = self:GetSlotAndBagID()
	if slot and bag then
		local eItem = Item:CreateFromBagAndSlot(bag, slot)
		if eItem and not eItem:IsItemEmpty() then
			eItem:ContinueOnItemLoad(function()
				local name = eItem:GetItemName()
				local id = eItem:GetItemID()
				if not name or not id then return end
				if button == "LeftButton" then
					if not addon.db["vendorIncludeSellList"][id] then
						addon.db["vendorIncludeSellList"][id] = name
						print(ADD .. ":", id, name)
						if MerchantFrame and MerchantFrame:IsShown() then
							hasMoreItems = true
							updateSellMoreButton()
						end
					end
				elseif button == "RightButton" then
					if addon.db["vendorIncludeSellList"][id] then
						addon.db["vendorIncludeSellList"][id] = nil
						print(REMOVE .. ":", id, name)
					end
				end
				updateSellMarks(nil, true)
			end)
		end
	end
end

hooksecurefunc(_G.ContainerFrameItemButtonMixin, "OnModifiedClick", AltClickHook)

if ContainerFrameCombinedBags then hooksecurefunc(ContainerFrameCombinedBags, "UpdateItems", updateSellMarks) end
local frames = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames or {}
for _, frame in ipairs(frames) do
	if frame then hooksecurefunc(frame, "UpdateItems", updateSellMarks) end
end

if TooltipDataProcessor then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		if not addon.db["vendorShowSellTooltip"] then return end
		if not data or not tooltip.GetOwner then return end
		local oTooltip = tooltip.GetOwner and tooltip:GetOwner()
		if not oTooltip or not oTooltip.GetBagID or not oTooltip.GetID then return end
		local bagID = oTooltip:GetBagID()
		local slotIndex = oTooltip:GetID()
		if bagID and slotIndex then
			local key = bagID .. "_" .. slotIndex
			if sellMarkLookup[key] then tooltip:AddLine(L["vendorWillBeSold"], 1, 0, 0) end
		end
	end)
end
