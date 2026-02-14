-- Example file
-- luacheck: globals AUCTION_HOUSE_HEADER_ITEM NEED SEARCH

local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Vendor")
local AceGUI = addon.AceGUI
local f = CreateFrame("Frame")

addon.Vendor = addon.Vendor or {}
addon.Vendor.CraftShopper = addon.Vendor.CraftShopper or {}
addon.Vendor.CraftShopper.items = addon.Vendor.CraftShopper.items or {}
addon.Vendor.CraftShopper.multipliers = addon.Vendor.CraftShopper.multipliers or {}

local RANK_TO_USE = 3 -- 1-3: gewünschter Qualitätsrang
local isRecraftTbl = { false, true } -- erst normale, dann Recrafts

local SCAN_DELAY = 0.3
local pendingScan
local scanRunning
local pendingPurchase -- data for a running AH commodities purchase
local lastPurchaseItemID -- itemID of the last confirmed commodities purchase
local ahCache = {} -- [itemID] = true/false
local purchasedItems = {} -- [itemID] = true for items already bought via quick buy

local ShowCraftShopperFrameIfNeeded -- forward declaration
local BuildShoppingList -- forward declaration for early users
local createCrafterMultiplyFrame -- forward declaration
local craftShopperCheckboxHooksInstalled = false

local function IsCraftShopperEnabled() return addon.db and addon.db["vendorCraftShopperEnable"] end

local function GetTrackRecipeCheckbox()
	if ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm and ProfessionsFrame.CraftingPage.SchematicForm.TrackRecipeCheckbox then
		return ProfessionsFrame.CraftingPage.SchematicForm.TrackRecipeCheckbox
	end
end

local function HasTrackedRecipes()
	for _, isRecraft in ipairs(isRecraftTbl) do
		local recipes = C_TradeSkillUI.GetRecipesTracked(isRecraft)
		if recipes and #recipes > 0 then return true end
	end
	return false
end

local heavyEvents = {
	"BAG_UPDATE_DELAYED",
	"CRAFTINGORDERS_ORDER_PLACEMENT_RESPONSE",
	"AUCTION_HOUSE_SHOW",
	"AUCTION_HOUSE_CLOSED",
	"ADDON_LOADED",
}

local heavyEventsRegistered = false

local function RegisterHeavyEvents()
	if heavyEventsRegistered then return end
	heavyEventsRegistered = true
	for _, event in ipairs(heavyEvents) do
		f:RegisterEvent(event)
	end
end

-- Remove stored multipliers for recipes that are no longer tracked
local function CleanupUntrackedMultipliers()
	local tracked = {}
	for _, isRecraft in ipairs(isRecraftTbl) do
		local recipes = C_TradeSkillUI.GetRecipesTracked(isRecraft) or {}
		for _, recipeID in ipairs(recipes) do
			tracked[recipeID] = true
		end
	end
	local removed = false
	for recipeID, _ in pairs(addon.Vendor.CraftShopper.multipliers or {}) do
		if not tracked[recipeID] then
			addon.Vendor.CraftShopper.multipliers[recipeID] = nil
			removed = true
		end
	end
	if removed then
		-- Rebuild immediately (not gated by resting) to reflect changes
		addon.Vendor.CraftShopper.items = BuildShoppingList()
		if addon.Vendor.CraftShopper.frame then addon.Vendor.CraftShopper.frame:Refresh() end
		ShowCraftShopperFrameIfNeeded()
	end
end

local function UnregisterHeavyEvents()
	if not heavyEventsRegistered then return end
	heavyEventsRegistered = false
	for _, event in ipairs(heavyEvents) do
		f:UnregisterEvent(event)
	end
	f:UnregisterEvent("COMMODITY_PRICE_UPDATED")
	f:UnregisterEvent("COMMODITY_PURCHASE_FAILED")
	f:UnregisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
	f:UnregisterEvent("AUCTION_HOUSE_SHOW_ERROR")
end

-- Helpers to manage mini-frame state
local function GetCurrentRecipeID()
	local recipeID
	if
		ProfessionsFrame
		and ProfessionsFrame.CraftingPage
		and ProfessionsFrame.CraftingPage.SchematicForm
		and ProfessionsFrame.CraftingPage.SchematicForm.currentRecipeInfo
		and ProfessionsFrame.CraftingPage.SchematicForm.currentRecipeInfo.recipeID
	then
		recipeID = ProfessionsFrame.CraftingPage.SchematicForm.currentRecipeInfo.recipeID
	elseif C_TradeSkillUI and C_TradeSkillUI.GetSelectedRecipeID then
		recipeID = C_TradeSkillUI.GetSelectedRecipeID()
	end
	return recipeID
end

local function IsRecipeTrackedAny(recipeID)
	if not recipeID or not C_TradeSkillUI or not C_TradeSkillUI.IsRecipeTracked then return false end
	local ok, tracked = pcall(C_TradeSkillUI.IsRecipeTracked, recipeID, false)
	if ok and tracked then return true end
	local ok2, tracked2 = pcall(C_TradeSkillUI.IsRecipeTracked, recipeID, true)
	return ok2 and tracked2 or false
end

local function UpdateMultiplyFrameState()
	local frame = _G.EQOLCrafterMultiply
	if not frame or not frame.ok or not frame.editBox then return end
	local txt = frame.editBox:GetText() or ""
	local rid = GetCurrentRecipeID()
	local isTracked = IsRecipeTrackedAny(rid)
	if txt == "" then
		frame.ok:SetText(isTracked and PROFESSIONS_UNTRACK_RECIPE or TRACK_ACHIEVEMENT)
	else
		if frame.autoFilled then
			frame.ok:SetText(PROFESSIONS_UNTRACK_RECIPE)
		else
			frame.ok:SetText(TRACK_ACHIEVEMENT)
		end
	end
end

local function HookCraftShopperCheckboxIfNeeded()
	if craftShopperCheckboxHooksInstalled or not IsCraftShopperEnabled() then return end
	local checkbox = GetTrackRecipeCheckbox()
	if not checkbox or not checkbox.HookScript then return end

	checkbox:HookScript("OnShow", function(self)
		if not IsCraftShopperEnabled() then return end
		if EQOLCrafterMultiply then EQOLCrafterMultiply:Show() end
		self:SetAlpha(0)
		if UpdateMultiplyFrameState then UpdateMultiplyFrameState() end
	end)

	checkbox:HookScript("OnHide", function()
		if not IsCraftShopperEnabled() then return end
		if EQOLCrafterMultiply then EQOLCrafterMultiply:Hide() end
	end)

	craftShopperCheckboxHooksInstalled = true
end

local function EnsureCraftShopperProfessionsUI()
	if not IsCraftShopperEnabled() then return end
	if IsAddOnLoaded and IsAddOnLoaded("Blizzard_Professions") then
		if not EQOLCrafterMultiply and createCrafterMultiplyFrame then createCrafterMultiplyFrame() end
		HookCraftShopperCheckboxIfNeeded()
	else
		f:RegisterEvent("ADDON_LOADED")
	end
end

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

function BuildShoppingList()
	local need = {} -- [itemID] = fehlende Menge
	local multipliers = addon.Vendor.CraftShopper.multipliers or {}

	for _, isRecraft in ipairs(isRecraftTbl) do
		local recipes = C_TradeSkillUI.GetRecipesTracked(isRecraft) or {}
		for _, recipeID in ipairs(recipes) do
			local schem = getSchematic(recipeID, isRecraft)
			local mult = multipliers[recipeID] or 1
			if schem and schem.reagentSlotSchematics then
				for _, slot in ipairs(schem.reagentSlotSchematics) do
					-- Nur Pflicht-Reagenzien, optional/finishing überspringen:
					if slot.reagentType == Enum.CraftingReagentType.Basic then
						local reqQty = slot.quantityRequired * mult
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
		if purchasedItems[itemID] and owned >= want.qty then purchasedItems[itemID] = nil end
		local missing = math.max(want.qty - owned, 0)
		if missing > 0 and not purchasedItems[itemID] then
			table.insert(items, {
				itemID = itemID,
				qtyNeeded = want.qty,
				owned = owned,
				missing = missing,
				ahBuyable = want.canAHBuy,
				hidden = false,
			})
		end
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
	ShowCraftShopperFrameIfNeeded()
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
	[6] = Enum.AuctionHouseFilter.ArtifactQuality,
	[7] = Enum.AuctionHouseFilter.LegendaryCraftedItemOnly,
}

-- Only handle generic Auction House errors relevant to commodity purchases.
local purchaseErrorCodes = {
	[Enum.AuctionHouseError.NotEnoughMoney] = true,
	[Enum.AuctionHouseError.ItemNotFound] = true,
}

-- Shows a small confirmation window for a pending commodity purchase.
-- Displays a spinner and countdown while waiting for the price from the server.
-- When the price is known, the user can confirm or cancel the buy.
local function ShowPurchasePopup(item, buyWidget)
	if pendingPurchase then return end -- do not allow multiple parallel purchases
	buyWidget:SetDisabled(true)

	local popup = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
	popup:SetSize(280, 150)
	popup:SetPoint("TOP", UIParent, "TOP", 0, -200)
	popup:SetFrameStrata("TOOLTIP")
	popup:EnableMouse(true)
	popup:SetMovable(true)
	popup:RegisterForDrag("LeftButton")
	popup:SetScript("OnDragStart", popup.StartMoving)
	popup:SetScript("OnDragStop", popup.StopMovingOrSizing)

	popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	popup.title:SetPoint("CENTER", popup.TitleBg, "CENTER")
	popup.title:SetText(L["vendorCraftShopperConfirmPurchase"])
	popup.title:SetFont(addon.variables.defaultFont, 16, "OUTLINE")

	local text = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("TOP", 0, -40)
	text:SetJustifyH("CENTER")
	text:SetText(L["vendorCraftShopperWaitingForPrice"])
	text:SetFont(addon.variables.defaultFont, 14, "OUTLINE")
	popup.text = text

	local timerLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	timerLabel:SetPoint("TOP", text, "BOTTOM", 0, -10)
	timerLabel:SetJustifyH("CENTER")
	timerLabel:SetFont(addon.variables.defaultFont, 14, "OUTLINE")
	popup.timerLabel = timerLabel

	local buyBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
	buyBtn:SetSize(120, 24)
	buyBtn:SetPoint("BOTTOMLEFT", 10, 10)
	buyBtn:SetText(L["vendorCraftShopperBuyNow"])
	buyBtn:Disable()
	popup.buyBtn = buyBtn

	local cancelBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
	cancelBtn:SetSize(120, 24)
	cancelBtn:SetPoint("BOTTOMRIGHT", -10, 10)
	cancelBtn:SetText(L["vendorCraftShopperCancel"])
	popup.cancelBtn = cancelBtn

	popup.CloseButton:SetScript("OnClick", function() cancelBtn:Click() end)

	local spinner = CreateFrame("Frame", nil, popup, "LoadingSpinnerTemplate")
	spinner:SetPoint("TOP", 0, -25)
	spinner:SetSize(24, 24)
	spinner:Show()
	popup.spinner = spinner

	popup.remaining = 15
	timerLabel:SetText(L["vendorCraftShopperTimeRemaining"]:format(popup.remaining))
	popup.ticker = C_Timer.NewTicker(1, function()
		popup.remaining = popup.remaining - 1
		if popup.remaining <= 0 then
			cancelBtn:Click()
		else
			timerLabel:SetText(L["vendorCraftShopperTimeRemaining"]:format(popup.remaining))
		end
	end)

	buyBtn:SetScript("OnClick", function()
		f:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
		lastPurchaseItemID = item.itemID
		C_AuctionHouse.ConfirmCommoditiesPurchase(item.itemID, item.missing)
		if popup.ticker then popup.ticker:Cancel() end
		popup:Hide()
		pendingPurchase = nil
		buyWidget:SetDisabled(false)
	end)

	cancelBtn:SetScript("OnClick", function()
		C_AuctionHouse.CancelCommoditiesPurchase(item.itemID)
		if popup.ticker then popup.ticker:Cancel() end
		popup:Hide()
		f:UnregisterEvent("COMMODITY_PRICE_UPDATED")
		f:UnregisterEvent("COMMODITY_PURCHASE_FAILED")
		f:UnregisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
		f:UnregisterEvent("AUCTION_HOUSE_SHOW_ERROR")
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

	if pendingPurchase.popup.spinner then pendingPurchase.popup.spinner:Hide() end

	local playerMoney = GetMoney()
	if playerMoney < total then
		pendingPurchase.popup.text:SetText(L["vendorCraftShopperMissingGold"]:format(GetMoneyString(total - playerMoney)))
		pendingPurchase.popup.buyBtn:Hide()
		pendingPurchase.popup.cancelBtn:SetText(CLOSE)
		pendingPurchase.popup.cancelBtn:ClearAllPoints()
		pendingPurchase.popup.cancelBtn:SetPoint("BOTTOM", 0, 10)
	else
		pendingPurchase.popup.text:SetText(("%s x%d\n%s"):format(pendingPurchase.item.name, pendingPurchase.item.missing, GetMoneyString(total)))
		pendingPurchase.popup.buyBtn:Show()
		pendingPurchase.popup.buyBtn:Enable()
		pendingPurchase.popup.buyBtn:ClearAllPoints()
		pendingPurchase.popup.buyBtn:SetPoint("BOTTOMLEFT", 10, 10)
		pendingPurchase.popup.cancelBtn:SetText(L["vendorCraftShopperCancel"])
		pendingPurchase.popup.cancelBtn:ClearAllPoints()
		pendingPurchase.popup.cancelBtn:SetPoint("BOTTOMRIGHT", -10, 10)
	end
end

local function CreateCraftShopperFrame()
	if addon.Vendor.CraftShopper.frame then return addon.Vendor.CraftShopper.frame end
	local frame = AceGUI:Create("Window")
	frame:SetTitle(L["vendorCraftShopperTitle"])
	frame:SetWidth(300)
	frame:SetHeight(400)
	frame:SetLayout("List")
	frame.frame:Hide()
	frame.frame:SetFrameStrata(AuctionHouseFrame:GetFrameStrata())

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
	missingCheck:SetLabel(L["vendorCraftShopperMissingOnly"])
	missingCheck:SetCallback("OnValueChanged", function() frame:Refresh() end)
	missingCheck:SetRelativeWidth(0.5)
	frame.missingOnly = missingCheck
	filterGroup:AddChild(missingCheck)

	local ahCheck = AceGUI:Create("CheckBox")
	ahCheck:SetLabel(L["vendorCraftShopperAHBuyable"])
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
		label:SetRelativeWidth(0.45)
		rowHeader:AddChild(label)

		local label2 = AceGUI:Create("Label")
		label2:SetText(NEED)
		label2:SetFont(headerFont, 16, headerFlags)
		label2:SetRelativeWidth(0.25)
		rowHeader:AddChild(label2)

		for _ = 1, 3 do
			local spacer = AceGUI:Create("Label")
			spacer:SetText(" ")
			spacer:SetFont(headerFont, 16, headerFlags)
			spacer:SetRelativeWidth(0.1)
			rowHeader:AddChild(spacer)
		end
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
					local color = select(4, C_Item.GetItemQualityColor(quality or 1))
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
					searchBtn:SetCallback("OnEnter", function(widget)
						GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
						GameTooltip:SetText(L["vendorCraftShopperSearchAH"])
						GameTooltip:Show()
					end)
					searchBtn:SetCallback("OnLeave", function() GameTooltip:Hide() end)
					searchBtn:SetCallback("OnClick", function()
						local itemName, _, quality, _, _, _, _, _, itemEquipLoc, _, _, classID, subclassID = C_Item.GetItemInfo(item.itemID)
						local qualityFilter = { Enum.AuctionHouseFilter.ExactMatch }
						local mappedQuality = mapQuality[quality]
						if mappedQuality then table.insert(qualityFilter, 1, mappedQuality) end
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
					buy:SetCallback("OnEnter", function(widget)
						GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
						GameTooltip:SetText(L["vendorCraftShopperBuyItems"])
						GameTooltip:Show()
					end)
					buy:SetCallback("OnLeave", function() GameTooltip:Hide() end)
					buy:SetCallback("OnClick", function()
						if pendingPurchase then return end
						f:RegisterEvent("COMMODITY_PRICE_UPDATED")
						f:RegisterEvent("COMMODITY_PURCHASE_FAILED")
						f:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR")
						ShowPurchasePopup(item, buy)
						C_AuctionHouse.StartCommoditiesPurchase(item.itemID, item.missing)
					end)
					row:AddChild(buy)

					local remove = AceGUI:Create("Icon")
					remove:SetRelativeWidth(0.1)
					remove:SetImage("Interface\\AddOns\\" .. addonName .. "\\Icons\\delete.tga")
					remove:SetImageSize(20, 20)
					remove:SetCallback("OnEnter", function(widget)
						GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
						GameTooltip:SetText(L["vendorCraftShopperHideFromList"])
						GameTooltip:Show()
					end)
					remove:SetCallback("OnLeave", function() GameTooltip:Hide() end)
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

function ShowCraftShopperFrameIfNeeded()
	if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return end

	local hasItems = false
	for _, item in ipairs(addon.Vendor.CraftShopper.items) do
		if item.ahBuyable and item.missing > 0 then
			hasItems = true
			break
		end
	end

	if hasItems then
		local ui = CreateCraftShopperFrame()
		ui.frame:ClearAllPoints()
		ui.frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 5, 0)
		ui.frame:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMRIGHT", 5, 0)
		local width = math.max(300, AuctionHouseFrame:GetWidth() * 0.4)
		ui.frame:SetWidth(width)
		ui.ahBuyable:SetValue(true)
		ui.frame:Show()
		ui:Refresh()
	else
		if addon.Vendor.CraftShopper.frame then addon.Vendor.CraftShopper.frame.frame:Hide() end
		f:UnregisterEvent("COMMODITY_PRICE_UPDATED")
		f:UnregisterEvent("COMMODITY_PURCHASE_FAILED")
		f:UnregisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
		f:UnregisterEvent("AUCTION_HOUSE_SHOW_ERROR")
	end
end

function addon.Vendor.CraftShopper.EnableCraftShopper()
	f:RegisterEvent("TRACKED_RECIPE_UPDATE")
	EnsureCraftShopperProfessionsUI()
	if HasTrackedRecipes() then
		RegisterHeavyEvents()
		Rescan()
	else
		UnregisterHeavyEvents()
	end
	if _G.EQOLCrafterMultiply and IsCraftShopperEnabled() then
		if ProfessionsFrame and ProfessionsFrame:IsShown() then _G.EQOLCrafterMultiply:Show() end
	end
	local checkbox = GetTrackRecipeCheckbox()
	if checkbox and checkbox.SetAlpha and checkbox:IsShown() then checkbox:SetAlpha(0) end
end

function addon.Vendor.CraftShopper.DisableCraftShopper()
	f:UnregisterEvent("TRACKED_RECIPE_UPDATE")
	f:UnregisterEvent("ADDON_LOADED")
	UnregisterHeavyEvents()
	if pendingScan then
		pendingScan:Cancel()
		pendingScan = nil
	end
	if addon.Vendor.CraftShopper.frame then addon.Vendor.CraftShopper.frame.frame:Hide() end
	if _G.EQOLCrafterMultiply then _G.EQOLCrafterMultiply:Hide() end
	local checkbox = GetTrackRecipeCheckbox()
	if checkbox and checkbox.SetAlpha then checkbox:SetAlpha(1) end
end

f:RegisterEvent("PLAYER_LOGIN")

local function addToCraftShopper(el)
	if not el or not el.GetText then return end
	local txt = el:GetText()
	local count = tonumber(txt)
	if count == nil then
		el:SetText("")
		return
	end

	-- Determine current recipeID from the professions UI
	local recipeID
	if
		ProfessionsFrame
		and ProfessionsFrame.CraftingPage
		and ProfessionsFrame.CraftingPage.SchematicForm
		and ProfessionsFrame.CraftingPage.SchematicForm.currentRecipeInfo
		and ProfessionsFrame.CraftingPage.SchematicForm.currentRecipeInfo.recipeID
	then
		recipeID = ProfessionsFrame.CraftingPage.SchematicForm.currentRecipeInfo.recipeID
	end

	if not recipeID then return end

	count = math.floor(count)
	if count <= 0 then
		-- 0 => löschen: Multiplikator entfernen und Rezept untracken
		addon.Vendor.CraftShopper.multipliers[recipeID] = nil
		if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked then pcall(C_TradeSkillUI.SetRecipeTracked, recipeID, false, false) end
		el:SetText("")
	else
		-- Store multiplier and ensure recipe is tracked
		addon.Vendor.CraftShopper.multipliers[recipeID] = count
		if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked then pcall(C_TradeSkillUI.SetRecipeTracked, recipeID, true, false) end
		el:SetText("")
	end

	-- Update list immediately and show the UI
	addon.Vendor.CraftShopper.items = BuildShoppingList()
	if addon.Vendor.CraftShopper.frame then addon.Vendor.CraftShopper.frame:Refresh() end
	ShowCraftShopperFrameIfNeeded()
end

createCrafterMultiplyFrame = function()
	local fCMF = CreateFrame("frame", "EQOLCrafterMultiply", ProfessionsFrame.CraftingPage.SchematicForm, "BackdropTemplate")
	-- Compact, unobtrusive container in the top-right of the schematic form

	-- local parent = ProfessionsFrame.CraftingPage.SchematicForm.TrackRecipeCheckbox
	local parent = fCMF
	-- fCMF:SetPoint("RIGHT", ProfessionsFrame.CraftingPage.SchematicForm.TrackRecipeCheckbox, "LEFT", -5)
	fCMF:SetPoint("TOPRIGHT", ProfessionsFrame.CraftingPage.SchematicForm, "TOPRIGHT", -5)
	fCMF:SetSize(260, 32)
	fCMF:SetFrameStrata("HIGH")
	fCMF:EnableMouse(true)
	fCMF.autoFilled = false

	-- Visible, skinned OK button
	local btnOK = CreateFrame("Button", nil, fCMF, "UIPanelButtonTemplate")
	local eb = CreateFrame("EditBox", nil, fCMF, "InputBoxTemplate")
	local label = fCMF:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

	fCMF.ok = btnOK
	btnOK:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -3, -2)
	btnOK:SetSize(70, 22)
	btnOK:SetText(TRACK_ACHIEVEMENT)
	btnOK:SetScript("OnClick", function()
		if btnOK:GetText() == PROFESSIONS_UNTRACK_RECIPE then
			fCMF.autoFilled = false
			eb:SetText("0")
			addToCraftShopper(eb)
			eb:ClearFocus()
			if UpdateMultiplyFrameState then UpdateMultiplyFrameState() end
			return
		end
		if eb and eb.GetText then
			if nil == eb:GetText() or eb:GetText() == "" then
				fCMF.autoFilled = true
				eb:SetText("1")
			end
		end
		addToCraftShopper(eb)
		eb:ClearFocus()
		if UpdateMultiplyFrameState then UpdateMultiplyFrameState() end
	end)

	-- Label + edit box for quantity
	label:SetPoint("RIGHT", eb, "LEFT", -6, 0)
	label:SetText(L["vendorCraftShopperTrackQuantity"])

	fCMF.editBox = eb
	eb:SetPoint("RIGHT", btnOK, "LEFT", -3, 0)
	eb:SetAutoFocus(false)
	eb:SetHeight(22)
	eb:SetWidth(60)
	eb:SetFontObject(ChatFontNormal)
	eb:SetMaxLetters(5)

	eb:SetScript("OnEnterPressed", function(self)
		if (self:GetText() or "") == "" then
			if self:GetParent() then self:GetParent().autoFilled = true end
			self:SetText("1")
		end
		addToCraftShopper(self)
		self:ClearFocus()
		if UpdateMultiplyFrameState then UpdateMultiplyFrameState() end
	end)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnTextChanged", function(self, userInput)
		if userInput and self:GetParent() then self:GetParent().autoFilled = false end
		if UpdateMultiplyFrameState then UpdateMultiplyFrameState() end
	end)

	-- Ensure sub-widgets are visible (frame visibility controlled below)
	eb:Show()
	btnOK:Show()

	-- Track recipe changes to refresh button label
	fCMF._accum = 0
	fCMF.lastRecipeID = nil
	local function updateRecipeWatcher(self, elapsed)
		self._accum = (self._accum or 0) + elapsed
		if self._accum < 0.3 then return end
		self._accum = 0
		local rid
		if GetCurrentRecipeID then rid = GetCurrentRecipeID() end
		if rid ~= self.lastRecipeID then
			self.lastRecipeID = rid
			self.autoFilled = false
			if self.editBox and self.editBox:GetText() ~= "" then self.editBox:SetText("") end
			if UpdateMultiplyFrameState then UpdateMultiplyFrameState() end
		end
	end
	fCMF:SetScript("OnShow", function(self)
		self._accum = 0
		self:SetScript("OnUpdate", updateRecipeWatcher)
	end)
	fCMF:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

	-- Default hidden; only show when enabled and professions is visible
	fCMF:Hide()
	if addon.db and addon.db["vendorCraftShopperEnable"] and ProfessionsFrame:IsShown() then
		fCMF:Show()
		if UpdateMultiplyFrameState then UpdateMultiplyFrameState() end
	end
end

f:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "PLAYER_LOGIN" then
		if addon.db["vendorCraftShopperEnable"] then addon.Vendor.CraftShopper.EnableCraftShopper() end
	elseif event == "ADDON_LOADED" and arg1 == "Blizzard_Professions" then
		if IsCraftShopperEnabled() then
			if not EQOLCrafterMultiply then createCrafterMultiplyFrame() end
			HookCraftShopperCheckboxIfNeeded()
			local checkbox = GetTrackRecipeCheckbox()
			if checkbox and checkbox.SetAlpha and checkbox:IsShown() then checkbox:SetAlpha(0) end
		end
		-- No longer need to listen for further ADDON_LOADED
		f:UnregisterEvent("ADDON_LOADED")
	elseif event == "TRACKED_RECIPE_UPDATE" then
		CleanupUntrackedMultipliers()
		if HasTrackedRecipes() then
			RegisterHeavyEvents()
			ScheduleRescan()
		else
			UnregisterHeavyEvents()
			if pendingScan then
				pendingScan:Cancel()
				pendingScan = nil
			end
			if addon.Vendor.CraftShopper.frame then addon.Vendor.CraftShopper.frame.frame:Hide() end
		end
		if UpdateMultiplyFrameState then UpdateMultiplyFrameState() end
	elseif event == "BAG_UPDATE_DELAYED" then
		ScheduleRescan()
	elseif event == "CRAFTINGORDERS_ORDER_PLACEMENT_RESPONSE" then
		if arg1 == 0 and not scanRunning then Rescan() end
	elseif event == "AUCTION_HOUSE_SHOW" then
		Rescan()
		ShowCraftShopperFrameIfNeeded()
	elseif event == "AUCTION_HOUSE_CLOSED" then
		if addon.Vendor.CraftShopper.frame then
			addon.Vendor.CraftShopper.frame.frame:Hide()
			f:UnregisterEvent("COMMODITY_PRICE_UPDATED")
			f:UnregisterEvent("COMMODITY_PURCHASE_FAILED")
			f:UnregisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
			f:UnregisterEvent("AUCTION_HOUSE_SHOW_ERROR")
		end
	elseif event == "COMMODITY_PRICE_UPDATED" then
		UpdatePurchasePopup(arg1, arg2)
	elseif event == "COMMODITY_PURCHASE_FAILED" or (event == "AUCTION_HOUSE_SHOW_ERROR" and purchaseErrorCodes[arg1]) then
		lastPurchaseItemID = nil
		if pendingPurchase then
			f:UnregisterEvent("COMMODITY_PRICE_UPDATED")
			f:UnregisterEvent("COMMODITY_PURCHASE_FAILED")
			f:UnregisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
			f:UnregisterEvent("AUCTION_HOUSE_SHOW_ERROR")
			if pendingPurchase.popup.ticker then pendingPurchase.popup.ticker:Cancel() end
			if pendingPurchase.popup.spinner then pendingPurchase.popup.spinner:Hide() end
			pendingPurchase.popup.text:SetText(L["vendorCraftShopperPurchaseFailed"])
			pendingPurchase.popup.timerLabel:SetText("")
			pendingPurchase.popup.buyBtn:Hide()
			pendingPurchase.popup.cancelBtn:SetText(OKAY)
			pendingPurchase.popup.cancelBtn:ClearAllPoints()
			pendingPurchase.popup.cancelBtn:SetPoint("BOTTOM", 0, 10)
			pendingPurchase.buyWidget:SetDisabled(false)
		end
	elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
		f:UnregisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
		f:UnregisterEvent("AUCTION_HOUSE_SHOW_ERROR")
		f:UnregisterEvent("COMMODITY_PURCHASE_FAILED")
		local itemID = lastPurchaseItemID
		lastPurchaseItemID = nil
		if itemID then
			for _, item in ipairs(addon.Vendor.CraftShopper.items) do
				if item.itemID == itemID then
					item.hidden = true
					break
				end
			end
			purchasedItems[itemID] = true
			if addon.Vendor.CraftShopper.frame then addon.Vendor.CraftShopper.frame:Refresh() end
		end
		ScheduleRescan()
	else
		Rescan()
	end
end)

function addon.Vendor.functions.checkList()
	Rescan()
	for _, item in ipairs(addon.Vendor.CraftShopper.items) do
		if item.ahBuyable then
			local info = C_Item.GetItemInfo(item.itemID)
			print(L["vendorCraftShopperCheckListPrint"]:format(info or ("ItemID " .. item.itemID), item.missing))
		end
	end
end
