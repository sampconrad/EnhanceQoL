-- Example file
-- luacheck: globals AUCTION_HOUSE_HEADER_ITEM NEED SEARCH

local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local AceGUI = addon.AceGUI
local f = CreateFrame("Frame")

addon.Vendor = addon.Vendor or {}
addon.Vendor.CraftShopper = addon.Vendor.CraftShopper or {}
addon.Vendor.CraftShopper.items = addon.Vendor.CraftShopper.items or {}

local RANK_TO_USE = 3 -- 1-3: gewünschter Qualitätsrang
local isRecraftTbl = { false, true } -- erst normale, dann Recrafts

local SCAN_DELAY = 0.3
local pendingScan
local scanRunning
local pendingPurchase -- data for a running AH commodities purchase
local ahCache = {} -- [itemID] = true/false

local function isAHBuyable(itemID)
	if ahCache[itemID] ~= nil then return ahCache[itemID] end
	local buyable = true
	local data = C_TooltipInfo.GetItemByID(itemID)
	if data and data.lines then
		for _, line in ipairs(data.lines) do
			if (line.type == 20 and line.leftText == ITEM_BIND_ON_EQUIP) or (line.type == 0 and line.leftText == ITEM_CONJURED) then
				buyable = false
				break
			end
		end
	end
	ahCache[itemID] = buyable
	return buyable
end
local schemCache = {} -- [recipeID] = schematic
local schemCacheRecraft = {} -- [recipeID] = schematic

local function getSchematic(recipeID, isRecraft)
	if isRecraft and schemCacheRecraft[recipeID] then return schemCacheRecraft[recipeID] end
	if not isRecraft and schemCache[recipeID] then return schemCache[recipeID] end
	local s = C_TradeSkillUI.GetRecipeSchematic(recipeID, isRecraft)
	if isRecraft then
		schemCacheRecraft[recipeID] = s
	else
		schemCache[recipeID] = s
	end
	return s
end

local function BuildShoppingList()
	local need = {} -- [itemID] = fehlende Menge

	for _, isRecraft in ipairs(isRecraftTbl) do
		for _, recipeID in ipairs(C_TradeSkillUI.GetRecipesTracked(isRecraft)) do
			local schem = getSchematic(recipeID, isRecraft)
			if schem and schem.reagentSlotSchematics then
				for _, slot in ipairs(schem.reagentSlotSchematics) do
					-- Nur Pflicht-Reagenzien, optional/finishing überspringen:
					if slot.reagentType == Enum.CraftingReagentType.Basic then
						local reqQty = slot.quantityRequired
						-- gewünschte Qualitäts-ID holen:
						local reagent = slot.reagents[RANK_TO_USE]
						local id
						if reagent and reagent.itemID ~= 0 then
							id = reagent.itemID
							need[id] = need[id] or {}
							need[id].qty = (need[id].qty or 0) + reqQty
						else
							-- Fallback: Basis-ItemID (Qualität egal)
							id = slot.reagents[1].itemID
							need[id] = need[id] or {}
							need[id].qty = (need[id].qty or 0) + reqQty
						end
						need[id].canAHBuy = isAHBuyable(id)
					end
				end
			end
		end
	end

	local items = {}
	for itemID, want in pairs(need) do
		local owned = C_Item.GetItemCount(itemID, true) -- inkl. Bank
		local missing = math.max(want.qty - owned, 0)
		if missing > 0 then table.insert(items, {
			itemID = itemID,
			qtyNeeded = want.qty,
			owned = owned,
			missing = missing,
			ahBuyable = want.canAHBuy,
			hidden = false,
		}) end
	end
	return items
end

local function Rescan()
	if scanRunning then return end
	scanRunning = true
	pendingScan = nil
	if not IsResting() then
		scanRunning = false
		return
	end
	addon.Vendor.CraftShopper.items = BuildShoppingList()
	if addon.Vendor.CraftShopper.frame then addon.Vendor.CraftShopper.frame:Refresh() end
	scanRunning = false
end

local function ScheduleRescan()
	if pendingScan or scanRunning then return end
	pendingScan = C_Timer.NewTimer(SCAN_DELAY, Rescan)
end

local mapQuality = {
	[0] = Enum.AuctionHouseFilter.PoorQuality,
	[1] = Enum.AuctionHouseFilter.CommonQuality,
	[2] = Enum.AuctionHouseFilter.UncommonQuality,
	[3] = Enum.AuctionHouseFilter.RareQuality,
	[4] = Enum.AuctionHouseFilter.EpicQuality,
	[5] = Enum.AuctionHouseFilter.LegendaryQuality,
}

-- Shows a small confirmation window for a pending commodity purchase.
-- Displays a spinner and countdown while waiting for the price from the server.
-- When the price is known, the user can confirm or cancel the buy.
local function ShowPurchasePopup(item, buyWidget)
	if pendingPurchase then return end -- do not allow multiple parallel purchases
	buyWidget:SetDisabled(true)

	local popup = AceGUI:Create("Window")
	popup:SetTitle("Confirm purchase")
	popup:SetWidth(250)
	popup:SetHeight(150)
	popup:SetLayout("List")
	popup:EnableResize(false)
	popup.frame:SetFrameStrata("TOOLTIP")

	local text = AceGUI:Create("Label")
	text:SetFullWidth(true)
	text:SetJustifyH("CENTER")
	text:SetText("Waiting for price...")
	popup:AddChild(text)
	popup.text = text

	local timerLabel = AceGUI:Create("Label")
	timerLabel:SetFullWidth(true)
	timerLabel:SetJustifyH("CENTER")
	popup:AddChild(timerLabel)
	popup.timerLabel = timerLabel

	local btnGroup = AceGUI:Create("SimpleGroup")
	btnGroup:SetFullWidth(true)
	btnGroup:SetLayout("Flow")
	popup:AddChild(btnGroup)

	local buyBtn = AceGUI:Create("Button")
	buyBtn:SetText("Buy now")
	buyBtn:SetRelativeWidth(0.5)
	buyBtn:SetDisabled(true)
	btnGroup:AddChild(buyBtn)
	popup.buyBtn = buyBtn

	local cancelBtn = AceGUI:Create("Button")
	cancelBtn:SetText("Cancel")
	cancelBtn:SetRelativeWidth(0.5)
	btnGroup:AddChild(cancelBtn)

	local spinner = CreateFrame("Frame", nil, popup.frame, "LoadingSpinnerTemplate")
	spinner:SetPoint("TOP", popup.frame, "TOP", 0, -25)
	spinner:SetSize(24, 24)
	spinner:Show()
	popup.spinner = spinner

	popup.remaining = 15
	timerLabel:SetText(("Time remaining: %ds"):format(popup.remaining))
	popup.ticker = C_Timer.NewTicker(1, function()
		popup.remaining = popup.remaining - 1
		if popup.remaining <= 0 then
			cancelBtn:Fire("OnClick")
		else
			timerLabel:SetText(("Time remaining: %ds"):format(popup.remaining))
		end
	end)

	buyBtn:SetCallback("OnClick", function()
		C_AuctionHouse.ConfirmCommoditiesPurchase(item.itemID, item.missing)
		if popup.ticker then popup.ticker:Cancel() end
		popup.frame:Hide()
		AceGUI:Release(popup)
		pendingPurchase = nil
		item.hidden = true
		if addon.Vendor.CraftShopper.frame then addon.Vendor.CraftShopper.frame:Refresh() end
		buyWidget:SetDisabled(false)
	end)

	cancelBtn:SetCallback("OnClick", function()
		C_AuctionHouse.CancelCommoditiesPurchase(item.itemID)
		if popup.ticker then popup.ticker:Cancel() end
		popup.frame:Hide()
		AceGUI:Release(popup)
		pendingPurchase = nil
		buyWidget:SetDisabled(false)
	end)

	pendingPurchase = {
		item = item,
		popup = popup,
		buyWidget = buyWidget,
	}
end

local function UpdatePurchasePopup(pricePer, total)
	if not pendingPurchase then return end
	f:UnregisterEvent("COMMODITY_PRICE_UPDATED")

	pendingPurchase.popup.text:SetText(("%s x%d\n%s"):format(pendingPurchase.item.name, pendingPurchase.item.missing, GetMoneyString(total)))
	pendingPurchase.popup.buyBtn:SetDisabled(false)
	if pendingPurchase.popup.spinner then pendingPurchase.popup.spinner:Hide() end
end

local function CreateCraftShopperFrame()
	if addon.Vendor.CraftShopper.frame then return addon.Vendor.CraftShopper.frame end
	local frame = AceGUI:Create("Window")
	frame:SetTitle("Craft Shopper")
	frame:SetWidth(300)
	frame:SetHeight(400)
	frame:SetLayout("List")
	frame.frame:Hide()

	local search = AceGUI:Create("EditBox")
	search:SetLabel(SEARCH)
	search:SetFullWidth(true)
	search:SetCallback("OnTextChanged", function() frame:Refresh() end)
	frame.search = search
	frame:AddChild(search)

	local filterGroup = AceGUI:Create("SimpleGroup")
	filterGroup:SetFullWidth(true)
	filterGroup:SetLayout("Flow")
	frame:AddChild(filterGroup)

	local missingCheck = AceGUI:Create("CheckBox")
	missingCheck:SetLabel("Missing only")
	missingCheck:SetCallback("OnValueChanged", function() frame:Refresh() end)
	missingCheck:SetRelativeWidth(0.5)
	frame.missingOnly = missingCheck
	filterGroup:AddChild(missingCheck)

	local ahCheck = AceGUI:Create("CheckBox")
	ahCheck:SetLabel("AH Buyable")
	ahCheck:SetRelativeWidth(0.5)
	ahCheck:SetCallback("OnValueChanged", function() frame:Refresh() end)
	frame.ahBuyable = ahCheck
	filterGroup:AddChild(ahCheck)

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	scroll:SetLayout("List")
	frame.scroll = scroll
	frame:AddChild(scroll)

	function frame:Refresh()
		scroll:ReleaseChildren()

		local normalFont, _, normalFlags = GameFontNormal:GetFont()
		local headerFont, _, headerFlags = GameFontNormalLarge:GetFont()

		local rowHeader = AceGUI:Create("SimpleGroup")
		rowHeader:SetFullWidth(true)
		rowHeader:SetLayout("Flow")
		local label = AceGUI:Create("Label")
		label:SetText(AUCTION_HOUSE_HEADER_ITEM)
		label:SetFont(headerFont, 16, headerFlags)
		label:SetRelativeWidth(0.55)
		rowHeader:AddChild(label)

		local label2 = AceGUI:Create("Label")
		label2:SetText(NEED)
		label2:SetFont(headerFont, 16, headerFlags)
		label2:SetRelativeWidth(0.25)
		rowHeader:AddChild(label2)

		local label3 = AceGUI:Create("Label")
		label3:SetText("")
		label3:SetFont(headerFont, 16, headerFlags)
		label3:SetRelativeWidth(0.1)
		rowHeader:AddChild(label3)

		local label4 = AceGUI:Create("Label")
		label4:SetText("")
		label4:SetFont(headerFont, 16, headerFlags)
		label4:SetRelativeWidth(0.1)
		rowHeader:AddChild(label4)
		scroll:AddChild(rowHeader)
		local searchText = (search:GetText() or ""):lower()
		for _, item in ipairs(addon.Vendor.CraftShopper.items) do
			if not item.hidden and (not missingCheck:GetValue() or item.missing > 0) and (not ahCheck:GetValue() or item.ahBuyable) then
				local name, _, quality = C_Item.GetItemInfo(item.itemID)
				name = name or ("item:" .. item.itemID)
				item.name = name
				if searchText == "" or name:lower():find(searchText, 1, true) then
					local row = AceGUI:Create("SimpleGroup")
					row:SetFullWidth(true)
					row:SetLayout("Flow")

					local label = AceGUI:Create("InteractiveLabel")
					local color = select(4, GetItemQualityColor(quality or 1))
					label:SetText(("|c%s%s|r"):format(color, name))
					label:SetFont(normalFont, 14, normalFlags)
					label:SetCallback("OnEnter", function(widget)
						GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
						GameTooltip:SetItemByID(item.itemID)
						GameTooltip:Show()
					end)
					label:SetRelativeWidth(0.45)
					label:SetCallback("OnLeave", function() GameTooltip:Hide() end)
					row:AddChild(label)

					local qty = AceGUI:Create("Label")
					qty:SetText(("%d"):format(item.missing))
					qty:SetFont(normalFont, 14, normalFlags)
					qty:SetRelativeWidth(0.25)
					row:AddChild(qty)

					local searchBtn = AceGUI:Create("Icon")
					searchBtn:SetRelativeWidth(0.1)
					searchBtn:SetImage("Interface\\AddOns\\" .. addonName .. "\\Icons\\search.tga")
					searchBtn:SetImageSize(20, 20)
					searchBtn:SetCallback("OnClick", function()
						local itemName, _, quality, _, _, _, _, _, itemEquipLoc, _, _, classID, subclassID = C_Item.GetItemInfo(item.itemID)
						local qualityFilter = { mapQuality[quality], Enum.AuctionHouseFilter.ExactMatch }
						if not itemName then return end
						local query = {
							searchString = itemName,
							sorts = {
								{ sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = false },
								{ sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
							},
							filters = qualityFilter,
							itemClassFilters = {
								classID = classID,
								subClassID = subclassID,
								inventoryType = itemEquipLoc,
							},
						}
						C_AuctionHouse.SendBrowseQuery(query)
						AuctionHouseFrame:Show()
						AuctionHouseFrame:Raise()
					end)
					row:AddChild(searchBtn)

					local buy = AceGUI:Create("Icon")
					buy:SetRelativeWidth(0.1)
					buy:SetImage("Interface\\AddOns\\" .. addonName .. "\\Icons\\buy.tga")
					buy:SetImageSize(20, 20)
					buy:SetCallback("OnClick", function()
						if pendingPurchase then return end
						f:RegisterEvent("COMMODITY_PRICE_UPDATED")
						ShowPurchasePopup(item, buy)
						C_AuctionHouse.StartCommoditiesPurchase(item.itemID, item.missing)
					end)
					row:AddChild(buy)

					local remove = AceGUI:Create("Icon")
					remove:SetRelativeWidth(0.1)
					remove:SetImage("Interface\\AddOns\\" .. addonName .. "\\Icons\\delete.tga")
					remove:SetImageSize(20, 20)
					remove:SetCallback("OnClick", function()
						item.hidden = true
						frame:Refresh()
					end)
					row:AddChild(remove)

					scroll:AddChild(row)
				end
			end
		end
	end

	addon.Vendor.CraftShopper.frame = frame
	return frame
end

f:RegisterEvent("TRACKED_RECIPE_UPDATE") -- parameter 1: ID of recipe - parameter 2: tracked true/false
f:RegisterEvent("BAG_UPDATE_DELAYED") -- verzögerter Scan, um Event-Flut zu vermeiden
f:RegisterEvent("CRAFTINGORDERS_ORDER_PLACEMENT_RESPONSE") -- arg1: error code, 0 on success
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:RegisterEvent("AUCTION_HOUSE_CLOSED")

f:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "BAG_UPDATE_DELAYED" then
		ScheduleRescan()
	elseif event == "CRAFTINGORDERS_ORDER_PLACEMENT_RESPONSE" then
		if arg1 == 0 and not scanRunning then Rescan() end
	elseif event == "AUCTION_HOUSE_SHOW" then
		local ui = CreateCraftShopperFrame()
		ui.frame:ClearAllPoints()
		ui.frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 5, 0)
		ui.frame:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMRIGHT", 5, 0)
		ui.frame:SetWidth(300)
		ui.ahBuyable:SetValue(true)
		ui.frame:Show()
		ui:Refresh()
	elseif event == "AUCTION_HOUSE_CLOSED" then
		if addon.Vendor.CraftShopper.frame then
			addon.Vendor.CraftShopper.frame.frame:Hide()
			f:UnregisterEvent("COMMODITY_PRICE_UPDATED")
		end
	elseif event == "COMMODITY_PRICE_UPDATED" then
		UpdatePurchasePopup(arg1, arg2)
	else
		Rescan()
	end
end)

function addon.Vendor.functions.checkList()
	Rescan()
	for _, item in ipairs(addon.Vendor.CraftShopper.items) do
		if item.ahBuyable then
			local info = C_Item.GetItemInfo(item.itemID)
			print(("[%s]   fehlt: %d - Buy in AH"):format(info or ("ItemID " .. item.itemID), item.missing))
		end
	end
end
