local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Vendor = addon.Vendor or {}
addon.Vendor.Autoscrap = addon.Vendor.Autoscrap or {}

local Autoscrap = addon.Vendor.Autoscrap

local tinsert = table.insert

local RunNextFrame = _G.RunNextFrame
local C_ScrappingMachineUI = _G.C_ScrappingMachineUI

local MAX_SCRAP_SLOTS = 9
local MAX_ACTIVATION_ATTEMPTS = 60

local INV_TYPE_TO_SLOT = {}

do
	local invType = Enum and Enum.InventoryType
	if invType then
		local function assign(invKey, slot)
			if invKey then INV_TYPE_TO_SLOT[invKey] = slot end
		end

		assign(invType.IndexHeadType, INVSLOT_HEAD)
		assign(invType.IndexNeckType, INVSLOT_NECK)
		assign(invType.IndexShoulderType, INVSLOT_SHOULDER)
		assign(invType.IndexBodyType, INVSLOT_BODY) -- shirt slot
		assign(invType.IndexChestType, INVSLOT_CHEST)
		assign(invType.IndexRobeType, INVSLOT_CHEST)
		assign(invType.IndexWaistType, INVSLOT_WAIST)
		assign(invType.IndexLegsType, INVSLOT_LEGS)
		assign(invType.IndexFeetType, INVSLOT_FEET)
		assign(invType.IndexWristType, INVSLOT_WRIST)
		assign(invType.IndexHandType, INVSLOT_HAND)
		assign(invType.IndexCloakType, INVSLOT_BACK)

		if invType.IndexFingerType then assign(invType.IndexFingerType, { INVSLOT_FINGER1, INVSLOT_FINGER2 }) end
		if invType.IndexTrinketType then assign(invType.IndexTrinketType, { INVSLOT_TRINKET1, INVSLOT_TRINKET2 }) end

		assign(invType.IndexWeaponType, INVSLOT_MAINHAND)
		assign(invType.Index2HweaponType, INVSLOT_MAINHAND)
		assign(invType.IndexWeaponMainHandType, INVSLOT_MAINHAND)
		assign(invType.IndexWeaponOffHandType, INVSLOT_OFFHAND)
		assign(invType.IndexHoldableType, INVSLOT_OFFHAND)
		assign(invType.IndexShieldType, INVSLOT_OFFHAND)
		assign(invType.IndexRangedType, INVSLOT_MAINHAND)
		assign(invType.IndexRangedrightType, INVSLOT_MAINHAND)
		assign(invType.IndexRelicType, INVSLOT_MAINHAND)
		assign(invType.IndexThTabardType, INVSLOT_TABARD)
	end
end

local function deferExecution(callback)
	if type(RunNextFrame) == "function" then
		RunNextFrame(callback)
	else
		C_Timer.After(0, callback)
	end
end

Autoscrap.frame = Autoscrap.frame or CreateFrame("Frame")
Autoscrap.cachedPending = nil
Autoscrap.scrappingMachine = nil
Autoscrap.waitingForScrapAddon = false
Autoscrap.active = false
Autoscrap.activationAttempts = 0
Autoscrap.pendingActivationCheck = false
Autoscrap.monitoringEnteringWorld = false
Autoscrap.machineHooksSet = false

local function isAutomationEnabled() return addon.db and addon.db["vendorScrapAuto"] end

local function isTimerunnerEligible()
	if addon.functions and addon.functions.IsTimerunner then return addon.functions.IsTimerunner() end
	return false
end

function Autoscrap:StartEnteringWorldWatch()
	if self.monitoringEnteringWorld then return end
	self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	self.monitoringEnteringWorld = true
end

function Autoscrap:StopEnteringWorldWatch()
	if not self.monitoringEnteringWorld then return end
	self.frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
	self.monitoringEnteringWorld = false
end

function Autoscrap:IsActive() return self.active end

function Autoscrap:ScheduleActivationRetry()
	if self:IsActive() then return end
	if self.pendingActivationCheck then return end
	if self.activationAttempts >= MAX_ACTIVATION_ATTEMPTS then return end
	self.pendingActivationCheck = true
	self.activationAttempts = self.activationAttempts + 1
	C_Timer.After(2, function()
		self.pendingActivationCheck = false
		if self:IsActive() then return end
		self:EvaluateActivation()
	end)
end

function Autoscrap:EvaluateActivation()
	local playerEligible = isTimerunnerEligible()

	if not playerEligible then
		if self.active then
			self.active = false
			self.cachedPending = nil
			self.frame:UnregisterEvent("BAG_UPDATE_DELAYED")
		end

		self:StartEnteringWorldWatch()
		self:ScheduleActivationRetry()
		return
	end

	if not self.active then
		self.active = true
		self.activationAttempts = 0
		self.pendingActivationCheck = false
		self:StopEnteringWorldWatch()
		self.cachedPending = nil
		self:IdentifyMachine()
	end

	if isAutomationEnabled() then
		self.frame:RegisterEvent("BAG_UPDATE_DELAYED")
		if self.scrappingMachine and self.scrappingMachine:IsShown() then self:ProcessAutomation() end
	else
		self.frame:UnregisterEvent("BAG_UPDATE_DELAYED")
	end
end

function Autoscrap:GetMaxScrapQuality() return addon.db["vendorScrapMaxQuality"] or Enum.ItemQuality.Rare end

function Autoscrap:SetMaxScrapQuality(value)
	local quality = tonumber(value)
	if not quality then return end
	addon.db["vendorScrapMaxQuality"] = quality
	if self.scrappingMachine and self.scrappingMachine:IsShown() then
		self.cachedPending = nil
		self:ProcessAutomation()
	end
end

function Autoscrap:GetMinLevelDifference() return addon.db["vendorScrapMinLevelDiff"] or 0 end

function Autoscrap:SetMinLevelDifference(value)
	local numeric = math.max(tonumber(value) or 0, 0)
	addon.db["vendorScrapMinLevelDiff"] = numeric
	if self.scrappingMachine and self.scrappingMachine:IsShown() then
		self.cachedPending = nil
		self:ProcessAutomation()
	end
end

function Autoscrap:SetAutoScrap(value)
	local enabled = value and true or false
	addon.db["vendorScrapAuto"] = enabled

	if self:IsActive() then
		if enabled then
			self.frame:RegisterEvent("BAG_UPDATE_DELAYED")
		else
			self.frame:UnregisterEvent("BAG_UPDATE_DELAYED")
		end
	end

	if enabled and self:IsActive() and self.scrappingMachine and self.scrappingMachine:IsShown() then
		self.cachedPending = nil
		self:ProcessAutomation()
	end

	self:EvaluateActivation()
end

function Autoscrap:GetAutoScrap() return addon.db["vendorScrapAuto"] or false end

local function isItemLocationUsable(itemLoc) return itemLoc and itemLoc:IsValid() end

local function encodeBagSlot(bagID, slotID)
	if not bagID or not slotID then return end
	return string.format("%d:%d", bagID, slotID)
end

function Autoscrap:BuildPendingIndex()
	if not self:IsActive() then return {} end
	local lookup = {}
	for _, location in ipairs(self:CollectPendingItemLocations()) do
		local bagID, slotID = location:GetBagAndSlot()
		local key = encodeBagSlot(bagID, slotID)
		if key then lookup[key] = true end
	end
	return lookup
end

function Autoscrap:CollectPendingItemLocations()
	if not self:IsActive() then return {} end
	local pending = {}
	if not C_ScrappingMachineUI or not C_ScrappingMachineUI.HasScrappableItems then return pending end
	for slotIndex = 0, MAX_SCRAP_SLOTS - 1 do
		local location = C_ScrappingMachineUI.GetCurrentPendingScrapItemLocationByIndex(slotIndex)
		if isItemLocationUsable(location) then pending[#pending + 1] = location end
	end
	return pending
end

function Autoscrap:IsLocationQueued(itemLoc)
	if not self:IsActive() then return false end
	if not isItemLocationUsable(itemLoc) then return false end
	if not self.cachedPending then self.cachedPending = self:BuildPendingIndex() end
	local bagID, slotID = itemLoc:GetBagAndSlot()
	local key = encodeBagSlot(bagID, slotID)
	if not key then return false end
	return self.cachedPending[key] or false
end

function Autoscrap:GetEquippedReferenceLevel(invType)
	local mappedSlots = INV_TYPE_TO_SLOT[invType]
	if not mappedSlots then return end

	local function readSlotLevel(slotID)
		local location = ItemLocation:CreateFromEquipmentSlot(slotID)
		if not isItemLocationUsable(location) then return end
		return C_Item.GetCurrentItemLevel(location)
	end

	if type(mappedSlots) == "table" then
		local lowest
		for index = 1, #mappedSlots do
			local level = readSlotLevel(mappedSlots[index])
			if level and (not lowest or level < lowest) then lowest = level end
		end
		return lowest
	end

	return readSlotLevel(mappedSlots)
end

function Autoscrap:ScanBagsForScrap()
	if not self:IsActive() then return {} end
	local results = {}
	for bagID = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		local totalSlots = C_Container.GetContainerNumSlots(bagID) or 0
		for slotIndex = totalSlots, 1, -1 do
			local location = ItemLocation:CreateFromBagAndSlot(bagID, slotIndex)
			if isItemLocationUsable(location) and C_Item.CanScrapItem(location) then
				results[#results + 1] = {
					bagID = bagID,
					slotID = slotIndex,
					level = C_Item.GetCurrentItemLevel(location),
					icon = C_Item.GetItemIcon(location),
					invType = C_Item.GetItemInventoryType(location),
					quality = C_Item.GetItemQuality(location),
					link = C_Item.GetItemLink(location),
					location = location,
				}
			end
		end
	end
	return results
end

function Autoscrap:SelectItemsToQueue(limit)
	if not self:IsActive() then return {} end
	local minimumDifference = self:GetMinLevelDifference() or 0
	local qualityThreshold = self:GetMaxScrapQuality() or Enum.ItemQuality.Rare

	local candidates = self:ScanBagsForScrap()
	local selections = {}
	local cap = limit and math.max(limit, 0) or nil

	for index = 1, #candidates do
		local item = candidates[index]
		if item.level and item.quality and item.quality <= qualityThreshold then
			local equippedLevel = self:GetEquippedReferenceLevel(item.invType)
			if equippedLevel and (equippedLevel - item.level) >= minimumDifference then
				selections[#selections + 1] = item
				if cap and #selections >= cap then break end
			end
		end
	end

	return selections
end

function Autoscrap:CountMachineAssignments(maxSlots)
	if not self:IsActive() then return 0 end
	if not C_ScrappingMachineUI or not C_ScrappingMachineUI.HasScrappableItems then return 0 end
	if not C_ScrappingMachineUI.HasScrappableItems() then return 0 end

	local limit = math.min(maxSlots or MAX_SCRAP_SLOTS, MAX_SCRAP_SLOTS)
	local active = 0

	for slotIndex = 0, limit - 1 do
		if C_ScrappingMachineUI.GetCurrentPendingScrapItemLocationByIndex(slotIndex) then active = active + 1 end
	end

	return active
end

function Autoscrap:QueueItemOnMachine(bagID, slotID)
	if not self:IsActive() then return false end
	if not self.scrappingMachine then return false end
	if not C_ScrappingMachineUI then return false end

	C_Container.PickupContainerItem(bagID, slotID)
	local slotsParent = self.scrappingMachine.ItemSlots
	if not slotsParent then
		ClearCursor()
		return false
	end
	local slots = { slotsParent:GetChildren() }
	local openIndex
	for searchIndex = 0, MAX_SCRAP_SLOTS - 1 do
		if not C_ScrappingMachineUI.GetCurrentPendingScrapItemLocationByIndex(searchIndex) then
			openIndex = searchIndex + 1
			break
		end
	end
	if openIndex and slots[openIndex] then
		slots[openIndex]:Click()
		return true
	end
	ClearCursor()
	return false
end

function Autoscrap:PushQueuedBatch()
	if not self:IsActive() then return end
	if not C_ScrappingMachineUI then return end
	local itemsToScrap = self:SelectItemsToQueue(MAX_SCRAP_SLOTS)
	if #itemsToScrap == 0 then return end

	if #itemsToScrap < MAX_SCRAP_SLOTS then
		if self:CountMachineAssignments(MAX_SCRAP_SLOTS) >= #itemsToScrap then return end
	end

	if C_ScrappingMachineUI.HasScrappableItems() then return end

	C_ScrappingMachineUI.RemoveAllScrapItems()
	for index = 1, #itemsToScrap do
		local item = itemsToScrap[index]
		self:QueueItemOnMachine(item.bagID, item.slotID)
	end
end

function Autoscrap:ProcessAutomation()
	if not self:IsActive() then return end
	if not self.scrappingMachine or not self.scrappingMachine:IsShown() then return end
	if not isAutomationEnabled() then return end
	if not C_ScrappingMachineUI or C_ScrappingMachineUI.HasScrappableItems() then return end

	deferExecution(function() self:PushQueuedBatch() end)
end

function Autoscrap:HandleMachineOpened()
	if not self:IsActive() then return end
	self.cachedPending = nil
	if isAutomationEnabled() then deferExecution(function() self:PushQueuedBatch() end) end
end

function Autoscrap:HandleMachineClosed()
	if not self:IsActive() then return end
	self.cachedPending = nil
end

function Autoscrap:HandlePendingItemChange()
	if not self:IsActive() then return end
	if not self.scrappingMachine or not self.scrappingMachine:IsShown() then return end
	self.cachedPending = nil
	if not isAutomationEnabled() then return end
	self.cachedPending = self:BuildPendingIndex()
	self:ProcessAutomation()
end

function Autoscrap:HandleBagUpdate()
	if not self:IsActive() then return end
	if not self.scrappingMachine or not self.scrappingMachine:IsShown() then return end
	if not isAutomationEnabled() then return end
	self.cachedPending = nil
	self:ProcessAutomation()
end

function Autoscrap:IdentifyMachine()
	if self.scrappingMachine then return end
	local frame = _G.ScrappingMachineFrame
	if not frame then
		if not self.waitingForScrapAddon then
			self.waitingForScrapAddon = true
			self.frame:RegisterEvent("ADDON_LOADED")
		end
		return
	end

	self.scrappingMachine = frame
	self.waitingForScrapAddon = false
	self.frame:UnregisterEvent("ADDON_LOADED")

	if not self.machineHooksSet then
		self.machineHooksSet = true
		frame:HookScript("OnShow", function() self:HandleMachineOpened() end)

		frame:HookScript("OnHide", function() self:HandleMachineClosed() end)
	end

	if frame:IsShown() then self:HandleMachineOpened() end
end

function Autoscrap:HandleAddonLoaded(addonName)
	if addonName == "Blizzard_ScrappingMachineUI" then self:IdentifyMachine() end
end

function Autoscrap:Init()
	local frame = self.frame
	frame:SetScript("OnEvent", function(_, event, ...)
		if event == "PLAYER_LOGIN" then
			self.activationAttempts = 0
			self.pendingActivationCheck = false
			self:EvaluateActivation()
		elseif event == "PLAYER_ENTERING_WORLD" then
			if self:IsActive() then
				self:StopEnteringWorldWatch()
			else
				self.activationAttempts = 0
				self.pendingActivationCheck = false
				self:EvaluateActivation()
			end
		elseif event == "ADDON_LOADED" then
			self:HandleAddonLoaded(...)
		elseif self:IsActive() then
			if event == "SCRAPPING_MACHINE_PENDING_ITEM_CHANGED" then
				self:HandlePendingItemChange()
			elseif event == "BAG_UPDATE_DELAYED" then
				self:HandleBagUpdate()
			end
		end
	end)

	frame:RegisterEvent("PLAYER_LOGIN")
	frame:RegisterEvent("SCRAPPING_MACHINE_PENDING_ITEM_CHANGED")

	self:StartEnteringWorldWatch()
	self:EvaluateActivation()
end

Autoscrap:Init()
