local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Vendor = addon.Vendor or {}
addon.Vendor.functions = addon.Vendor.functions or {}
addon.Vendor.variables = addon.Vendor.variables or {}

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Vendor")
local lastEbox = nil
local sellMoreButton
local hasMoreItems = false
local sellMarkLookup = {}
local destroyMarkLookup = {}
local updateSellMarks
local updateDestroyUI
local updateDestroyButtonState
local tooltipCache = {}
local destroyState = {
	queue = {},
	rows = {},
	pendingUpdate = false,
	pendingQueue = nil,
	hideTimer = nil,
}

local function ensureDestroyListFrame()
	if destroyState.list and destroyState.list:IsObjectType("Frame") then return destroyState.list end
	if InCombatLockdown and InCombatLockdown() then return nil end
	local button = destroyState.button
	if not button then return nil end

	local frame = CreateFrame("Frame", addonName .. "_DestroyList", button, "BackdropTemplate")
	frame:SetFrameStrata("HIGH")
	frame:SetFrameLevel((destroyState.button and destroyState.button:GetFrameLevel() or 5) + 10)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	frame:SetBackdropColor(0, 0, 0, 0.85)
	frame:SetBackdropBorderColor(0.9, 0.2, 0.2, 1)
	frame:SetSize(220, 40)
	frame:EnableMouse(true)
	frame:SetScript("OnLeave", function()
		C_Timer.After(0.05, function()
			if destroyState.button and destroyState.button:IsMouseOver() then return end
			if frame:IsMouseOver() then return end
			frame:Hide()
		end)
	end)
	destroyState.list = frame
	destroyState.rows = {}

	local emptyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	emptyLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
	emptyLabel:SetWidth(200)
	emptyLabel:SetJustifyH("LEFT")
	emptyLabel:SetText(L["vendorDestroyListEmpty"])
	frame.emptyLabel = emptyLabel

	return frame
end

local destroyProtected = {
	[169223] = true, -- Legion artifact weapon
	[200710] = true, -- Legion artifact weapon
}

local pendingSellMarksUpdate = false
local pendingSellMarksReset = false
local pendingDestroyButtonUpdate = false

local function scheduleDestroyButtonUpdate()
	if pendingDestroyButtonUpdate then return end
	pendingDestroyButtonUpdate = true
	C_Timer.After(0.1, function()
		pendingDestroyButtonUpdate = false
		updateDestroyButtonState()
	end)
end

local function getDestroyProtectionReason(itemID, bagInfo, quality)
	if destroyProtected[itemID] then return L["vendorDestroyProtected"] end
	local q = quality
	if not q and bagInfo then q = bagInfo.quality end
	if not q and itemID then
		local _, _, itemQuality = C_Item.GetItemInfo(itemID)
		if not itemQuality then C_Item.RequestLoadItemDataByID(itemID) end
		q = itemQuality
	end
	if q == Enum.ItemQuality.Artifact or q == Enum.ItemQuality.WoWToken then return L["vendorDestroyProtectedQuality"] end
	return nil
end

local function notifyDestroyProtection(itemID, descriptor, reason)
	if addon.db and addon.db["vendorDestroyShowMessages"] == false then return end
	local label = descriptor or ("Item #" .. tostring(itemID or "?"))
	print(string.format("%s: %s", label, reason or L["vendorDestroyProtected"]))
end

local function inventoryOpen()
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then return true end
	local frames = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames or {}
	for _, frame in ipairs(frames) do
		if frame and frame:IsShown() then return true end
	end
	return false
end

local function createDestroyEntry(bag, slot, itemID, itemName, info)
	info = info or C_Container.GetContainerItemInfo(bag, slot)
	local count = info and info.stackCount or 1
	local icon = info and info.iconFileID or nil
	if not itemName then
		local instantName = C_Item.GetItemInfoInstant and select(1, C_Item.GetItemInfoInstant(itemID))
		if instantName then itemName = instantName end
	end
	return {
		bag = bag,
		slot = slot,
		itemID = itemID,
		name = itemName or ("Item #" .. tostring(itemID)),
		count = count,
		icon = icon,
	}
end

local function copyDestroyQueue(source)
	local result = {}
	for index = 1, #source do
		local entry = source[index]
		result[index] = {
			bag = entry.bag,
			slot = entry.slot,
			itemID = entry.itemID,
			name = entry.name,
			count = entry.count,
			icon = entry.icon,
		}
	end
	return result
end

local function destroyQueuesEqual(a, b)
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	if #a ~= #b then return false end
	for i = 1, #a do
		local lhs = a[i]
		local rhs = b[i]
		if not lhs or not rhs then return false end
		if lhs.itemID ~= rhs.itemID or lhs.bag ~= rhs.bag or lhs.slot ~= rhs.slot or lhs.count ~= rhs.count then return false end
	end
	return true
end

local function extractItemID(input, clearCursor)
	if type(input) == "number" then return input end
	if type(input) == "table" then
		if input.itemID then return tonumber(input.itemID) end
		if input.link then input = input.link end
	end
	if type(input) == "string" then
		local id = tonumber(input)
		if id then return id end
		local linkID = input:match("item:(%d+)")
		if linkID then return tonumber(linkID) end
	end
	if clearCursor then
		local cursorType, itemID = GetCursorInfo()
		if cursorType == "item" and itemID then
			ClearCursor()
			return tonumber(itemID)
		end
	end
	return nil
end

local function anchorDestroyButton(button)
	if not button then return end
	local searchBox = _G.BagItemSearchBox
	if searchBox and searchBox.GetParent then
		button:SetParent(searchBox:GetParent() or UIParent)
		button:ClearAllPoints()
		button:SetPoint("RIGHT", searchBox, "LEFT", -6, 0)
	elseif ContainerFrameCombinedBags then
		button:SetParent(ContainerFrameCombinedBags)
		button:ClearAllPoints()
		button:SetPoint("TOPRIGHT", ContainerFrameCombinedBags, "TOPRIGHT", -36, -32)
	else
		button:SetParent(UIParent)
		button:ClearAllPoints()
		button:SetPoint("CENTER")
	end
end

local function removeDestroyItem(itemID)
	if not itemID then return end
	local list = addon.db["vendorIncludeDestroyList"]
	if not list or not list[itemID] then return end
	local name = list[itemID]
	list[itemID] = nil
	print(string.format(L["vendorDestroyRemoved"], name or ("Item #" .. tostring(itemID)), itemID))
	updateSellMarks(nil, true)
end

local function destroyRefreshList()
	local listFrame = ensureDestroyListFrame()
	if not listFrame then return end
	local queue = destroyState.queue or {}
	local rows = destroyState.rows or {}
	local total = #queue

	if total == 0 then
		listFrame.emptyLabel:Show()
	else
		listFrame.emptyLabel:Hide()
	end

	for index = 1, math.max(total, #rows) do
		local row = rows[index]
		if index > total then
			if row then row:Hide() end
		else
			local entry = queue[index]
			if not row then
				row = CreateFrame("Button", nil, listFrame)
				row:SetSize(204, 20)
				row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 8, -6 - (index - 1) * 22)
				row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
				row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")

				row.icon = row:CreateTexture(nil, "ARTWORK")
				row.icon:SetSize(18, 18)
				row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)

				row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
				row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
				row.text:SetJustifyH("LEFT")

				row:SetScript("OnClick", function(self, button)
					if button == "RightButton" and self.entry and self.entry.itemID then removeDestroyItem(self.entry.itemID) end
				end)

				rows[index] = row
			end

			row.entry = entry
			row.icon:SetTexture(entry.icon or 134400)
			if entry.name then
				if (entry.count or 1) > 1 then
					row.text:SetText(string.format("%s x%d", entry.name, entry.count or 1))
				else
					row.text:SetText(entry.name)
				end
			else
				row.text:SetText(entry.itemID and ("Item #" .. entry.itemID) or "")
			end
			row:Show()
		end
	end

	local height = total > 0 and (total * 22 + 14) or 36
	listFrame:SetHeight(height)
	destroyState.rows = rows
end

local function destroyHideList()
	if destroyState.list and destroyState.list:IsShown() then destroyState.list:Hide() end
end

local function applySellDestroyOverlaysToFrame(frame)
	if not frame or not frame:IsShown() then return end
	local overlaySell = addon.db["vendorShowSellOverlay"]
	local overlayDestroy = addon.db["vendorDestroyEnable"] and addon.db["vendorShowDestroyOverlay"]

	for _, itemButton in frame:EnumerateValidItems() do
		local bag = itemButton:GetBagID()
		local slot = itemButton:GetID()
		local key = bag .. "_" .. slot
		local isDestroy = destroyMarkLookup[key]
		local showSell = overlaySell and sellMarkLookup[key] and not isDestroy
		local showDestroy = overlayDestroy and isDestroy

		if showSell then
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

		if showDestroy then
			if not itemButton.ItemMarkDestroy then
				itemButton.ItemMarkDestroy = itemButton:CreateTexture(nil, "OVERLAY", nil, 7)
				itemButton.ItemMarkDestroy:SetTexture("Interface\\Buttons\\UI-GroupLoot-DE-Up")
				itemButton.ItemMarkDestroy:SetSize(16, 16)
				itemButton.ItemMarkDestroy:SetPoint("BOTTOMLEFT", itemButton, "BOTTOMLEFT", 0, -1)
				itemButton.DestroyOverlay = itemButton:CreateTexture(nil, "OVERLAY", nil, 6)
				itemButton.DestroyOverlay:SetAllPoints()
				itemButton.DestroyOverlay:SetColorTexture(0.85, 0.1, 0.1, 0.45)
			end
			itemButton.ItemMarkDestroy:Show()
			if addon.db["vendorShowSellHighContrast"] and itemButton.DestroyOverlay then
				itemButton.DestroyOverlay:Show()
			elseif itemButton.DestroyOverlay then
				itemButton.DestroyOverlay:Hide()
			end
			if not itemButton.matchesSearch then
				itemButton.ItemMarkDestroy:SetAlpha(0.1)
				if itemButton.DestroyOverlay then itemButton.DestroyOverlay:Hide() end
			else
				itemButton.ItemMarkDestroy:SetAlpha(1)
				if addon.db["vendorShowSellHighContrast"] and itemButton.DestroyOverlay then itemButton.DestroyOverlay:Show() end
			end
			if itemButton.ItemMarkSell then
				itemButton.ItemMarkSell:Hide()
				itemButton.SellOverlay:Hide()
			end
		elseif itemButton.ItemMarkDestroy then
			itemButton.ItemMarkDestroy:Hide()
			if itemButton.DestroyOverlay then itemButton.DestroyOverlay:Hide() end
		end
	end
end

local function setDestroyButtonVisibility(button, visible)
	if not button then return end
	local inCombat = InCombatLockdown and InCombatLockdown() or false
	if visible then
		button:SetAlpha(1)
		if not inCombat then
			button:Enable()
			button:EnableMouse(true)
		end
	else
		button:SetAlpha(0)
		if not inCombat then
			button:Disable()
			button:EnableMouse(false)
		end
		destroyHideList()
	end
end

local function ensureDestroyButton()
	if destroyState.button and destroyState.button:IsObjectType("Button") then return destroyState.button end
	if InCombatLockdown and InCombatLockdown() then
		destroyState.pendingUpdate = true
		return nil
	end

	local parent = _G.BagItemSearchBox and _G.BagItemSearchBox:GetParent() or ContainerFrameCombinedBags or UIParent
	local button = CreateFrame("Button", addonName .. "_DestroyButton", parent, "InsecureActionButtonTemplate")
	button:SetSize(28, 28)
	button:RegisterForClicks("LeftButtonUp")
	button:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-DE-Up")
	button:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-DE-Down")
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetScript("OnEnter", function(self)
		if not addon.db["vendorDestroyEnable"] then return end
		local queue = destroyState.queue or {}
		if #queue > 0 then
			destroyRefreshList()
			local list = ensureDestroyListFrame()
			if list then
				list:ClearAllPoints()
				list:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -4)
				list:Show()
			end
		else
			destroyHideList()
		end
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(L["vendorDestroyButtonTooltip"])
			GameTooltip:Show()
		end
	end)
	button:SetScript("OnLeave", function(self)
		if GameTooltip then GameTooltip:Hide() end
		C_Timer.After(0.05, function()
			if self:IsMouseOver() then return end
			if destroyState.list and destroyState.list:IsShown() and destroyState.list:IsMouseOver() then return end
			destroyHideList()
		end)
	end)
	button:SetScript("OnHide", destroyHideList)
	button:SetScript("OnClick", function()
		if not addon.db["vendorDestroyEnable"] then return end
		local queue = destroyState.queue or {}
		local entry = queue[1]
		if not entry then
			print(L["vendorDestroyEmpty"] or "Nothing queued for destruction.")
			return
		end
		if InCombatLockdown and InCombatLockdown() then
			print(L["vendorDestroyCombat"] or "Cannot destroy items while in combat.")
			return
		end

		local bag, slot = entry.bag, entry.slot
		if bag == nil or slot == nil then
			table.remove(queue, 1)
			updateDestroyUI(copyDestroyQueue(queue))
			return
		end

		local info = C_Container.GetContainerItemInfo(bag, slot)
		if not info then
			print(L["vendorDestroyMissing"] or "Queued item is no longer in your bags.")
			table.remove(queue, 1)
			updateDestroyUI(copyDestroyQueue(queue))
			scheduleDestroyButtonUpdate()
			return
		end

		local link = C_Container.GetContainerItemLink(bag, slot)
		if not link and entry.itemID then link = C_Item.GetItemLink(entry.itemID) end
		if not link then link = entry.name or ("Item #" .. tostring(entry.itemID or "?")) end
		link = tostring(link)

		local reason = getDestroyProtectionReason(entry.itemID, info)
		if reason then
			notifyDestroyProtection(entry.itemID, link, reason)
			if addon.db["vendorIncludeDestroyList"] then addon.db["vendorIncludeDestroyList"][entry.itemID] = nil end
			table.remove(queue, 1)
			updateDestroyUI(copyDestroyQueue(queue))
			scheduleDestroyButtonUpdate()
			return
		end

		if info.isLocked then
			print(L["vendorDestroyLocked"] or "Item is locked.")
			return
		end

		local count = info.stackCount or entry.count or 1

		C_Container.PickupContainerItem(bag, slot)
		if not CursorHasItem() then
			print(L["vendorDestroyFailed"] or "Unable to pick up item for deletion.")
			return
		end

		DeleteCursorItem()
		if CursorHasItem() then
			ClearCursor()
			print(L["vendorDestroyConfirm"] or "Item requires manual confirmation to delete.")
			return
		end

		table.remove(queue, 1)
		if addon.db["vendorDestroyShowMessages"] ~= false then print(string.format(L["vendorDestroyDestroyed"] or "Destroyed: %s", link .. (count > 1 and (" x" .. count) or ""))) end
		updateDestroyUI(copyDestroyQueue(queue))
		updateSellMarks(nil, true)
	end)
	setDestroyButtonVisibility(button, false)
	anchorDestroyButton(button)

	local count = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
	count:SetJustifyH("RIGHT")
	button.count = count

	destroyState.button = button
	return button
end

updateDestroyButtonState = function()
	if destroyState.pendingQueue then
		destroyState.queue = destroyState.pendingQueue
		destroyState.pendingQueue = nil
	end

	if not addon.db["vendorDestroyEnable"] or not inventoryOpen() then
		if destroyState.button then setDestroyButtonVisibility(destroyState.button, false) end
		destroyHideList()
		destroyState.pendingUpdate = false
		return
	end

	if InCombatLockdown and InCombatLockdown() then
		destroyState.pendingUpdate = true
		return
	end

	local button = ensureDestroyButton()
	if not button then
		destroyState.pendingUpdate = true
		return
	end

	local queue = destroyState.queue or {}
	while #queue > 0 do
		local first = queue[1]
		local info = first and C_Container.GetContainerItemInfo(first.bag, first.slot)
		local reason = first and getDestroyProtectionReason(first.itemID, info)
		if not reason then break end
		local descriptor = (info and C_Container.GetContainerItemLink(first.bag, first.slot)) or first.name or ("Item #" .. tostring(first.itemID or "?"))
		descriptor = tostring(descriptor)
		notifyDestroyProtection(first.itemID, descriptor, reason)
		if addon.db["vendorIncludeDestroyList"] then addon.db["vendorIncludeDestroyList"][first.itemID] = nil end
		table.remove(queue, 1)
	end
	if not inventoryOpen() or #queue == 0 then
		setDestroyButtonVisibility(button, false)
		if button.count then button.count:SetText("") end
		destroyHideList()
		destroyState.pendingUpdate = false
		return
	end

	local entry = queue[1]
	local info = entry and C_Container.GetContainerItemInfo(entry.bag, entry.slot)
	local inCombat = InCombatLockdown and InCombatLockdown() or false
	if not inCombat then
		if info and info.isLocked then
			button:Disable()
		else
			button:Enable()
		end
	end

	setDestroyButtonVisibility(button, true)
	if button.count then button.count:SetText(#queue) end
	if destroyState.list and destroyState.list:IsShown() then
		destroyRefreshList()
		destroyState.list:ClearAllPoints()
		destroyState.list:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -4)
	end
	destroyState.pendingUpdate = false
end

function updateDestroyUI(queue)
	queue = queue or {}
	if destroyQueuesEqual(destroyState.queue, queue) then
		if destroyState.pendingUpdate then scheduleDestroyButtonUpdate() end
		return
	end

	destroyState.pendingQueue = copyDestroyQueue(queue)
	if InCombatLockdown and InCombatLockdown() then
		destroyState.pendingUpdate = true
		return
	end

	scheduleDestroyButtonUpdate()
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
	if not addon.aceFrame or not addon.aceFrame:IsShown() or nil == addon.Vendor.variables["labelExplained" .. value .. "line"] then return end
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

local function lookupDestroyItemsFast()
	local itemsToDestroy = {}
	local includeDestroy = addon.db["vendorIncludeDestroyList"]
	local includeSell = addon.db["vendorIncludeSellList"]

	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		local numSlots = C_Container.GetContainerNumSlots(bag)
		if numSlots and numSlots > 0 then
			for slot = 1, numSlots do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				local itemID = info and info.itemID or C_Container.GetContainerItemID(bag, slot)
				if itemID and info then
					local inDestroy = includeDestroy and includeDestroy[itemID]
					local inSell = includeSell and includeSell[itemID]

					if info.hasNoValue and (inDestroy or inSell) then
						if not getDestroyProtectionReason(itemID, info, info.quality) then table.insert(itemsToDestroy, createDestroyEntry(bag, slot, itemID, info.itemName, info)) end
					elseif inDestroy then
						if not getDestroyProtectionReason(itemID, info, info.quality) then table.insert(itemsToDestroy, createDestroyEntry(bag, slot, itemID, info.itemName, info)) end
					elseif inSell then
						local sellPrice = select(11, C_Item.GetItemInfo(itemID)) or 0
						if sellPrice <= 0 and not getDestroyProtectionReason(itemID, info, info.quality) then
							table.insert(itemsToDestroy, createDestroyEntry(bag, slot, itemID, info.itemName, info))
						end
					end
				end
			end
		end
	end

	return itemsToDestroy
end

local function lookupItems()
	local _, avgItemLevelEquipped = GetAverageItemLevel()
	local itemsToSell = {}
	local itemsToDestroy = {}
	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local itemID = C_Container.GetContainerItemID(bag, slot)
			if itemID then
				local bagInfo = C_Container.GetContainerItemInfo(bag, slot)
				local itemLink = (bagInfo and bagInfo.hyperlink) or C_Container.GetContainerItemLink(bag, slot)
				local itemNameFromBag = bagInfo and bagInfo.itemName
				local hasNoValue = bagInfo and bagInfo.hasNoValue
				local qualityFromBag = bagInfo and bagInfo.quality

				local inDestroyList = addon.db["vendorIncludeDestroyList"] and addon.db["vendorIncludeDestroyList"][itemID]
				local inSellList = addon.db["vendorIncludeSellList"] and addon.db["vendorIncludeSellList"][itemID]

				local processed = false
				if hasNoValue and (inDestroyList or inSellList) then
					local reason = getDestroyProtectionReason(itemID, bagInfo, qualityFromBag)
					if reason then
						notifyDestroyProtection(itemID, itemLink or itemNameFromBag, reason)
						if inDestroyList and addon.db["vendorIncludeDestroyList"] then addon.db["vendorIncludeDestroyList"][itemID] = nil end
						if inSellList and addon.db["vendorIncludeSellList"] then addon.db["vendorIncludeSellList"][itemID] = nil end
					else
						local displayName = itemNameFromBag or (itemLink and itemLink:match("%[(.+)%]")) or ("Item #" .. tostring(itemID))
						table.insert(itemsToDestroy, createDestroyEntry(bag, slot, itemID, displayName, bagInfo))
					end
					processed = true
				end

				if not processed then
					local itemName, _, quality, itemLevel, _, _, _, _, _, _, sellPrice, classID, subclassID, bindType, expansionID = C_Item.GetItemInfo(itemLink)
					if not itemName then
						C_Item.RequestLoadItemDataByID(itemID)
					else
						local resolvedName = itemNameFromBag or itemName
						local reason

						if inDestroyList then
							reason = getDestroyProtectionReason(itemID, bagInfo, quality)
							if reason then
								notifyDestroyProtection(itemID, itemLink or resolvedName, reason)
								if addon.db["vendorIncludeDestroyList"] then addon.db["vendorIncludeDestroyList"][itemID] = nil end
							else
								table.insert(itemsToDestroy, createDestroyEntry(bag, slot, itemID, resolvedName, bagInfo))
							end
						elseif addon.db["vendorExcludeSellList"][itemID] then
							-- skip
						elseif inSellList then
							if sellPrice and sellPrice > 0 then
								table.insert(itemsToSell, { bag = bag, slot = slot, itemID = itemID })
							else
								reason = getDestroyProtectionReason(itemID, bagInfo, quality)
								if reason then
									notifyDestroyProtection(itemID, itemLink or resolvedName, reason)
									if addon.db["vendorIncludeSellList"] then addon.db["vendorIncludeSellList"][itemID] = nil end
								else
									table.insert(itemsToDestroy, createDestroyEntry(bag, slot, itemID, resolvedName, bagInfo))
								end
							end
						elseif sellPrice and sellPrice > 0 then
							if classID == 4 and subclassID == 5 and not C_TransmogCollection.PlayerHasTransmog(itemID) then
								-- do not sell appearances
							elseif classID == 7 and addon.Vendor.variables.itemQualityFilter[quality] then
								local expTable = addon.db["vendor" .. addon.Vendor.variables.tabNames[quality] .. "CraftingExpansions"]
								if expTable and expTable[expansionID] then table.insert(itemsToSell, { bag = bag, slot = slot, itemID = itemID }) end
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
										if effectiveILvl <= rIlvl then table.insert(itemsToSell, { bag = bag, slot = slot, itemID = itemID }) end
									end
								end
							end
						end
					end
				end
			end
		end
	end
	return itemsToSell, itemsToDestroy
end

local function checkItem()
	hasMoreItems = false
	updateSellMoreButton()
	local _, avgItemLevelEquipped = GetAverageItemLevel()
	local itemsToSell = select(1, lookupItems()) or {}

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
		updateSellMarks(nil, true)
		if addon.db["vendorDestroyEnable"] then scheduleDestroyButtonUpdate() end
	end,
	["BAG_UPDATE_DELAYED"] = function()
		wipe(tooltipCache)
		updateSellMarks(nil, true)
		if addon.db["vendorDestroyEnable"] then scheduleDestroyButtonUpdate() end
	end,
	["ITEM_DATA_LOAD_RESULT"] = function(arg1, arg2)
		if arg2 == false and addon.aceFrame and addon.aceFrame:IsShown() and lastEbox then
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
		applySellDestroyOverlaysToFrame(ContainerFrameCombinedBags)
		local frames = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames or {}
		for _, frame in ipairs(frames) do
			applySellDestroyOverlaysToFrame(frame)
		end
	end,
	["PLAYER_REGEN_ENABLED"] = function()
		if destroyState.pendingQueue then
			destroyState.queue = destroyState.pendingQueue
			destroyState.pendingQueue = nil
		end
		destroyState.pendingUpdate = false
		if addon.db["vendorDestroyEnable"] then scheduleDestroyButtonUpdate() end
	end,
	["PLAYER_REGEN_DISABLED"] = function() destroyHideList() end,
}
local function registerEvents(frame)
	for event in pairs(eventHandlers) do
		frame:RegisterEvent(event)
	end
end

local function eventHandler(self, event, ...)
	if eventHandlers[event] then eventHandlers[event](...) end
end

local function addVendorFrame(container, type)
	local text = {}
	local uText = {} -- Text for upgrade track
	local value = addon.Vendor.variables.tabNames[type]
	local labelHeadlineExplain

	local scroll = addon.functions.createContainer("ScrollFrame", "List")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)
	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local iqColor = ITEM_QUALITY_COLORS[type].hex .. _G["ITEM_QUALITY" .. type .. "_DESC"] .. "|r"

	local function updateLegend(sValue, sValue2)
		if not addon.aceFrame or not addon.aceFrame:IsShown() then return end
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
		if type == 0 and checked then addon.db["sellAllJunk"] = false end

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
		if type > 1 then
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

		if type > 0 then
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
		end

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
	scroll:DoLayout()
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
		local id = extractItemID(input, true)

		if not id then
			print("|cffff0000Invalid input! Please provide a valid Item ID or drag an item.|r")
			eBox:SetText("")
			return
		end

		local eItem = Item:CreateFromItemID(tonumber(id))
		if eItem and not eItem:IsItemEmpty() then
			eItem:ContinueOnItemLoad(function()
				local itemID = eItem:GetItemID()
				local itemName = eItem:GetItemName()
				if not addon.db[dbValue][itemID] then
					addon.db[dbValue][itemID] = itemName
					if addon.db["vendorIncludeDestroyList"] then addon.db["vendorIncludeDestroyList"][itemID] = nil end
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

local function addDestroyFrame(container)
	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	container:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	groupCore:SetTitle(L["vendorDestroy"])
	wrapper:AddChild(groupCore)

	local cbEnable = addon.functions.createCheckboxAce(L["vendorDestroyEnable"], addon.db["vendorDestroyEnable"], function(_, _, checked)
		addon.db["vendorDestroyEnable"] = checked and true or false
		updateSellMarks(nil, true)
		updateDestroyButtonState()
	end, L["vendorDestroyEnableDesc"])
	groupCore:AddChild(cbEnable)

	local cbOverlay = addon.functions.createCheckboxAce(L["vendorShowDestroyOverlay"], addon.db["vendorShowDestroyOverlay"], function(_, _, checked)
		addon.db["vendorShowDestroyOverlay"] = checked and true or false
		updateSellMarks(nil, true)
	end)
	groupCore:AddChild(cbOverlay)

	local cbMessages = addon.functions.createCheckboxAce(
		L["vendorDestroyShowMessages"],
		addon.db["vendorDestroyShowMessages"] ~= false,
		function(_, _, checked) addon.db["vendorDestroyShowMessages"] = checked and true or false end,
		L["vendorDestroyShowMessagesDesc"]
	)
	groupCore:AddChild(cbMessages)

	local hint = addon.functions.createLabelAce(L["vendorDestroyManualHint"], nil, nil, 11)
	hint:SetFullWidth(true)
	groupCore:AddChild(hint)

	local groupList = addon.functions.createContainer("InlineGroup", "List")
	groupList:SetTitle(L["vendorDestroyList"])
	wrapper:AddChild(groupList)

	local destroyBox
	local dropDestroyList

	local function refreshDestroyDropdown()
		local list, order = addon.functions.prepareListForDropdown(addon.db["vendorIncludeDestroyList"] or {})
		dropDestroyList:SetList(list, order)
		dropDestroyList:SetValue(nil)
	end

	local function addDestroyItemFromInput(input)
		local id = extractItemID(input, true)
		if not id then
			print("|cffff0000Invalid input! Please provide a valid Item ID or drag an item.|r")
			if destroyBox then destroyBox:SetText("") end
			return
		end

		local item = Item:CreateFromItemID(id)
		if item and not item:IsItemEmpty() then
			item:ContinueOnItemLoad(function()
				local name = item:GetItemName()
				local quality = item.GetItemQuality and item:GetItemQuality()
				local reason = getDestroyProtectionReason(id, nil, quality)
				if reason then
					notifyDestroyProtection(id, item:GetItemLink() or name, reason)
					if destroyBox then destroyBox:SetText("") end
					return
				end
				if not addon.db["vendorIncludeDestroyList"][id] then
					addon.db["vendorIncludeDestroyList"][id] = name or ("Item #" .. tostring(id))
					if addon.db["vendorIncludeSellList"] then addon.db["vendorIncludeSellList"][id] = nil end
					print(string.format(L["vendorDestroyAdded"], name or ("Item #" .. tostring(id)), id))
					refreshDestroyDropdown()
					updateSellMarks(nil, true)
				end
				if destroyBox then destroyBox:SetText("") end
			end)
		end
	end

	destroyBox = addon.functions.createEditboxAce(L["Item id or drag item"], nil, function(_, _, text)
		if text and text ~= "" and text ~= L["Item id or drag item"] then addDestroyItemFromInput(text) end
	end, nil)
	groupList:AddChild(destroyBox)
	lastEbox = destroyBox

	local list, order = addon.functions.prepareListForDropdown(addon.db["vendorIncludeDestroyList"] or {})
	dropDestroyList = addon.functions.createDropdownAce(L["vendorDestroyListLabel"], list, order, nil)
	groupList:AddChild(dropDestroyList)

	local btnRemove = addon.functions.createButtonAce(L["vendorDestroyRemove"], 140, function()
		local selectedValue = dropDestroyList:GetValue()
		if not selectedValue then return end
		local id = tonumber(selectedValue)
		if not id then return end
		if addon.db["vendorIncludeDestroyList"][id] then
			local name = addon.db["vendorIncludeDestroyList"][id]
			addon.db["vendorIncludeDestroyList"][id] = nil
			print(string.format(L["vendorDestroyRemoved"], name or ("Item #" .. tostring(id)), id))
			refreshDestroyDropdown()
			updateSellMarks(nil, true)
		end
	end)
	groupList:AddChild(btnRemove)
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
	}
	table.insert(data, {
		text = L["vendorShowSellTooltip"],
		var = "vendorShowSellTooltip",
		func = function(self, _, checked)
			addon.db["vendorShowSellTooltip"] = checked
			if inventoryOpen() then updateSellMarks(nil, true) end
		end,
	})

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

	-- Integrate Craft Shopper directly into Selling root
	local groupCS = addon.functions.createContainer("InlineGroup", "List")
	groupCS:SetTitle(L["vendorCraftShopperTitle"])
	wrapper:AddChild(groupCS)

	local cbCS = addon.functions.createCheckboxAce(L["vendorCraftShopperEnable"], addon.db["vendorCraftShopperEnable"], function(_, _, checked)
		addon.db["vendorCraftShopperEnable"] = checked
		if checked then
			addon.Vendor.CraftShopper.EnableCraftShopper()
		else
			addon.Vendor.CraftShopper.DisableCraftShopper()
		end
	end, L["vendorCraftShopperEnableDesc"])
	groupCS:AddChild(cbCS)

	scroll:DoLayout()
end

-- Expose helpers for external settings UI
function addon.Vendor.functions.refreshSellMarks()
	if updateSellMarks then updateSellMarks(nil, true) end
end

function addon.Vendor.functions.refreshDestroyButton()
	if updateDestroyButtonState then updateDestroyButtonState() end
end

-- Integrate Vendor into Items -> Vendors & Economy -> Selling (Auto‑Sell)
-- addon.variables.statusTable.groups["items\001economy"] = true
-- addon.variables.statusTable.groups["items\001economy\001selling"] = true
local function performUpdateSellMarks(resetCache)
	if resetCache then wipe(tooltipCache) end

	local overlaySell = addon.db["vendorShowSellOverlay"]
	local overlayDestroy = addon.db["vendorDestroyEnable"] and addon.db["vendorShowDestroyOverlay"]
	local tooltip = addon.db["vendorShowSellTooltip"]
	local frames = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames or {}

	local function clearFrame(frame)
		if frame and frame:IsShown() then
			for _, itemButton in frame:EnumerateValidItems() do
				if itemButton.ItemMarkSell then
					itemButton.ItemMarkSell:Hide()
					itemButton.SellOverlay:Hide()
				end
				if itemButton.ItemMarkDestroy then
					itemButton.ItemMarkDestroy:Hide()
					if itemButton.DestroyOverlay then itemButton.DestroyOverlay:Hide() end
				end
			end
		end
	end

	if not overlaySell and not overlayDestroy and not tooltip then
		-- Keep the destroy queue in sync even when overlays/tooltips are off
		if addon.db["vendorDestroyEnable"] and inventoryOpen() then
			local itemsToDestroy = lookupDestroyItemsFast()
			updateDestroyUI(itemsToDestroy or {})
		else
			-- No need to scan; make sure the button hides
			updateDestroyUI({})
		end

		clearFrame(ContainerFrameCombinedBags)
		for _, frame in ipairs(frames) do
			clearFrame(frame)
		end
		wipe(sellMarkLookup)
		wipe(destroyMarkLookup)
		return
	end

	wipe(sellMarkLookup)
	wipe(destroyMarkLookup)

	local itemsToSell, itemsToDestroy = lookupItems()
	itemsToSell = itemsToSell or {}
	itemsToDestroy = itemsToDestroy or {}
	updateDestroyUI(itemsToDestroy)

	for _, v in ipairs(itemsToSell) do
		sellMarkLookup[v.bag .. "_" .. v.slot] = true
	end
	for _, v in ipairs(itemsToDestroy) do
		destroyMarkLookup[v.bag .. "_" .. v.slot] = v
	end

	applySellDestroyOverlaysToFrame(ContainerFrameCombinedBags)
	for _, frame in ipairs(frames) do
		applySellDestroyOverlaysToFrame(frame)
	end
end

function updateSellMarks(_, resetCache)
	if resetCache then pendingSellMarksReset = true end
	if pendingSellMarksUpdate then return end
	pendingSellMarksUpdate = true
	C_Timer.After(0.05, function()
		local doReset = pendingSellMarksReset
		pendingSellMarksReset = false
		pendingSellMarksUpdate = false
		performUpdateSellMarks(doReset)
	end)
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
					local info = C_Container.GetContainerItemInfo(bag, slot)
					local shouldDestroy = info and info.hasNoValue
					if not shouldDestroy then
						local sellPrice = select(11, C_Item.GetItemInfo(eItem:GetItemLink()))
						if (sellPrice or 0) <= 0 then shouldDestroy = true end
					end
					if shouldDestroy then
						local reason = getDestroyProtectionReason(id, info)
						if reason then
							local linkText = eItem:GetItemLink() or name
							notifyDestroyProtection(id, linkText, reason)
							return
						end
						if not addon.db["vendorIncludeDestroyList"][id] then
							addon.db["vendorIncludeDestroyList"][id] = name
							if addon.db["vendorIncludeSellList"] then addon.db["vendorIncludeSellList"][id] = nil end
							print(string.format(L["vendorDestroyAdded"], name, id))
						end
					else
						if not addon.db["vendorIncludeSellList"][id] then
							addon.db["vendorIncludeSellList"][id] = name
							if addon.db["vendorIncludeDestroyList"] then addon.db["vendorIncludeDestroyList"][id] = nil end
							print(ADD .. ":", id, name)
							if MerchantFrame and MerchantFrame:IsShown() then
								hasMoreItems = true
								updateSellMoreButton()
							end
						end
					end
				elseif button == "RightButton" then
					if addon.db["vendorIncludeSellList"][id] then
						addon.db["vendorIncludeSellList"][id] = nil
						print(REMOVE .. ":", id, name)
					end
					if addon.db["vendorIncludeDestroyList"] and addon.db["vendorIncludeDestroyList"][id] then
						addon.db["vendorIncludeDestroyList"][id] = nil
						print(string.format(L["vendorDestroyRemoved"], name or ("Item #" .. tostring(id)), id))
					end
				end
				updateSellMarks(nil, true)
			end)
		end
	end
end

local function hookBagFrame(frame)
	if not frame then return end
	if frame._EnhanceQoLVendorDestroyHook then return end
	frame._EnhanceQoLVendorDestroyHook = true
	hooksecurefunc(frame, "UpdateItems", function(self) applySellDestroyOverlaysToFrame(self) end)
	frame:HookScript("OnShow", function()
		if destroyState.button and (not InCombatLockdown or not InCombatLockdown()) then anchorDestroyButton(destroyState.button) end
		updateSellMarks(nil, true)
		if addon.db["vendorDestroyEnable"] then scheduleDestroyButtonUpdate() end
	end)
	frame:HookScript("OnHide", function() destroyHideList() end)
end

function addon.Vendor.functions.InitState()
	if addon.Vendor.variables.vendorInitialized then return end
	if not addon.db then return end
	addon.Vendor.variables.vendorInitialized = true

	registerEvents(frameLoad)
	frameLoad:SetScript("OnEvent", eventHandler)

	if _G.ContainerFrameItemButtonMixin then hooksecurefunc(_G.ContainerFrameItemButtonMixin, "OnModifiedClick", AltClickHook) end

	if ContainerFrameCombinedBags then hookBagFrame(ContainerFrameCombinedBags) end
	local frames = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames or {}
	for _, frame in ipairs(frames) do
		hookBagFrame(frame)
	end

	-- ! STILL BUGGY 2026-01-25
	-- TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
	-- 	if not addon.db or not addon.db["vendorShowSellTooltip"] then return end
	-- 	if not data or not tooltip.GetOwner then return end
	-- 	local oTooltip = tooltip.GetOwner and tooltip:GetOwner()
	-- 	if not oTooltip or not oTooltip.GetBagID or not oTooltip.GetID then return end
	-- 	local bagID = oTooltip:GetBagID()
	-- 	local slotIndex = oTooltip:GetID()
	-- 	if bagID and slotIndex then
	-- 		local key = bagID .. "_" .. slotIndex
	-- 		if sellMarkLookup[key] then
	-- 			tooltip:AddLine(L["vendorWillBeSold"], 1, 0, 0)
	-- 		elseif destroyMarkLookup[key] then
	-- 			tooltip:AddLine(L["vendorWillBeDestroyed"], 1, 0.3, 0.1)
	-- 		end
	-- 	end
	-- end)
end
