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

addon.Vendor = addon.Vendor or {}
addon.Vendor.CraftShopper = addon.Vendor.CraftShopper or {}
addon.Vendor.CraftShopper.items = addon.Vendor.CraftShopper.items or {}

local RANK_TO_USE = 3 -- 1-3: gewünschter Qualitätsrang
local isRecraftTbl = { false, true } -- erst normale, dann Recrafts

local SCAN_DELAY = 0.3
local pendingScan
local scanRunning

local function isAHBuyable(itemID)
	if not itemID then return false end
	local data = C_TooltipInfo.GetItemByID(itemID)
	local canAHBuy = true
	if data and data.lines then
		for i, v in pairs(data.lines) do
			if v.type == 20 then
				canAHBuy = false
				if v.leftText == ITEM_BIND_ON_EQUIP then canAHBuy = false end
			elseif v.type == 0 and v.leftText == ITEM_CONJURED then
				canAHBuy = false
			end
		end
	end
	return canAHBuy
end

local function BuildShoppingList()
	local need = {} -- [itemID] = fehlende Menge

	for _, isRecraft in ipairs(isRecraftTbl) do
		for _, recipeID in ipairs(C_TradeSkillUI.GetRecipesTracked(isRecraft)) do
			local schem = C_TradeSkillUI.GetRecipeSchematic(recipeID, isRecraft)
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

		local rowHeader = AceGUI:Create("SimpleGroup")
		rowHeader:SetFullWidth(true)
		rowHeader:SetLayout("Flow")
		local label = AceGUI:Create("Label")
		label:SetText(AUCTION_HOUSE_HEADER_ITEM)
		label:SetRelativeWidth(0.55)
		rowHeader:AddChild(label)

		local label2 = AceGUI:Create("Label")
		label2:SetText(NEED)
		label2:SetRelativeWidth(0.25)
		rowHeader:AddChild(label2)

		local label3 = AceGUI:Create("Label")
		label3:SetText("")
		label3:SetRelativeWidth(0.1)
		rowHeader:AddChild(label3)

		local label4 = AceGUI:Create("Label")
		label4:SetText("")
		label4:SetRelativeWidth(0.1)
		rowHeader:AddChild(label4)
		scroll:AddChild(rowHeader)
		local searchText = (search:GetText() or ""):lower()
		for _, item in ipairs(addon.Vendor.CraftShopper.items) do
			if not item.hidden and (not missingCheck:GetValue() or item.missing > 0) and (not ahCheck:GetValue() or item.ahBuyable) then
				local name = C_Item.GetItemInfo(item.itemID) or ("item:" .. item.itemID)
				if searchText == "" or name:lower():find(searchText, 1, true) then
					local row = AceGUI:Create("SimpleGroup")
					row:SetFullWidth(true)
					row:SetLayout("Flow")

					local label = AceGUI:Create("InteractiveLabel")
					label:SetText(name)
					label:SetCallback("OnEnter", function(widget)
						GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
						GameTooltip:SetItemByID(item.itemID)
						GameTooltip:Show()
					end)
					label:SetRelativeWidth(0.55)
					label:SetCallback("OnLeave", function() GameTooltip:Hide() end)
					row:AddChild(label)

					local qty = AceGUI:Create("Label")
					qty:SetText(("%d"):format(item.missing))
					qty:SetRelativeWidth(0.25)
					row:AddChild(qty)

					local searchBtn = AceGUI:Create("Button")
					searchBtn:SetText("?")
					searchBtn:SetRelativeWidth(0.1)
					searchBtn:SetWidth(20)
					searchBtn:SetCallback("OnClick", function()
						local itemName = C_Item.GetItemInfo(item.itemID)
						if not itemName then return end
						local query = {
							searchString = itemName,
							sorts = {
								{ sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
								{ sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = false },
							},
							filters = {
								Enum.AuctionHouseFilter.PoorQuality,
								Enum.AuctionHouseFilter.CommonQuality,
								Enum.AuctionHouseFilter.UncommonQuality,
								Enum.AuctionHouseFilter.RareQuality,
								Enum.AuctionHouseFilter.EpicQuality,
							},
						}
						C_AuctionHouse.SendBrowseQuery(query)
						AuctionHouseFrame:Show()
						AuctionHouseFrame:Raise()
					end)
					row:AddChild(searchBtn)

					local remove = AceGUI:Create("Button")
					remove:SetText("X")
					remove:SetRelativeWidth(0.1)
					remove:SetWidth(20)
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

local f = CreateFrame("Frame")
f:RegisterEvent("TRACKED_RECIPE_UPDATE") -- parameter 1: ID of recipe - parameter 2: tracked true/false
f:RegisterEvent("BAG_UPDATE_DELAYED") -- verzögerter Scan, um Event-Flut zu vermeiden
f:RegisterEvent("CRAFTINGORDERS_ORDER_PLACEMENT_RESPONSE") -- arg1: error code, 0 on success
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:RegisterEvent("AUCTION_HOUSE_CLOSED")

f:SetScript("OnEvent", function(_, event, arg1)
	if event == "BAG_UPDATE_DELAYED" then
		ScheduleRescan()
	elseif event == "CRAFTINGORDERS_ORDER_PLACEMENT_RESPONSE" then
		if arg1 == 0 and not scanRunning then Rescan() end
	elseif event == "AUCTION_HOUSE_SHOW" then
		local ui = CreateCraftShopperFrame()
		ui.frame:ClearAllPoints()
		ui.frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 5, 0)
		ui.frame:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMRIGHT", 5, 0)

		ui.ahBuyable:SetValue(true)
		ui.frame:Show()
		ui:Refresh()
	elseif event == "AUCTION_HOUSE_CLOSED" then
		if addon.Vendor.CraftShopper.frame then addon.Vendor.CraftShopper.frame.frame:Hide() end
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
