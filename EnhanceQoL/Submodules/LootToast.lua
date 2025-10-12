-- luacheck: globals AlertFrame LootAlertSystem
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = addon.L

-- example
-- /run LootAlertSystem:AddAlert(select(2,C_Item.GetItemInfo(246205)), 1, nil, nil, 504, nil, nil, nil, false, true, false)

local LootToast = addon.LootToast or {}
addon.LootToast = LootToast
LootToast.enabled = false
LootToast.frame = LootToast.frame or CreateFrame("Frame")

local function slots(...)
	local tbl = {}
	for i = 1, select("#", ...) do
		local slotID = select(i, ...)
		if slotID then tbl[#tbl + 1] = slotID end
	end
	return tbl
end

local function getItemLevelFromLink(link)
	if not link then return nil end
	if GetDetailedItemLevelInfo then
		local level = GetDetailedItemLevelInfo(link)
		if level then return level end
	end
	return select(4, GetItemInfo(link))
end

local EQUIP_LOC_TO_SLOTS = {
	INVTYPE_HEAD = slots(INVSLOT_HEAD),
	INVTYPE_NECK = slots(INVSLOT_NECK),
	INVTYPE_SHOULDER = slots(INVSLOT_SHOULDER),
	INVTYPE_CLOAK = slots(INVSLOT_BACK),
	INVTYPE_CHEST = slots(INVSLOT_CHEST),
	INVTYPE_ROBE = slots(INVSLOT_CHEST),
	INVTYPE_BODY = slots(INVSLOT_BODY),
	INVTYPE_TABARD = slots(INVSLOT_TABARD),
	INVTYPE_WRIST = slots(INVSLOT_WRIST),
	INVTYPE_HAND = slots(INVSLOT_HAND),
	INVTYPE_WAIST = slots(INVSLOT_WAIST),
	INVTYPE_LEGS = slots(INVSLOT_LEGS),
	INVTYPE_FEET = slots(INVSLOT_FEET),
	INVTYPE_FINGER = slots(INVSLOT_FINGER1, INVSLOT_FINGER2),
	INVTYPE_TRINKET = slots(INVSLOT_TRINKET1, INVSLOT_TRINKET2),
	INVTYPE_WEAPON = slots(INVSLOT_MAINHAND, INVSLOT_OFFHAND),
	INVTYPE_WEAPONMAINHAND = slots(INVSLOT_MAINHAND),
	INVTYPE_WEAPONOFFHAND = slots(INVSLOT_OFFHAND),
	INVTYPE_2HWEAPON = slots(INVSLOT_MAINHAND),
	INVTYPE_SHIELD = slots(INVSLOT_OFFHAND),
	INVTYPE_HOLDABLE = slots(INVSLOT_OFFHAND),
}

do
	local rangedSlots
	if INVSLOT_RANGED then
		rangedSlots = slots(INVSLOT_RANGED)
	else
		rangedSlots = slots(INVSLOT_MAINHAND)
	end
	EQUIP_LOC_TO_SLOTS.INVTYPE_RANGED = rangedSlots
	EQUIP_LOC_TO_SLOTS.INVTYPE_RANGEDRIGHT = rangedSlots
	EQUIP_LOC_TO_SLOTS.INVTYPE_GUN = rangedSlots
	EQUIP_LOC_TO_SLOTS.INVTYPE_CROSSBOW = rangedSlots
	EQUIP_LOC_TO_SLOTS.INVTYPE_BOW = rangedSlots
	EQUIP_LOC_TO_SLOTS.INVTYPE_THROWN = rangedSlots
	EQUIP_LOC_TO_SLOTS.INVTYPE_WAND = rangedSlots
end

local function isPet(classID, subClassID)
	if classID == 17 then return true end
	if classID == 15 and subClassID == 2 then return true end

	return false
end

local function isItemAllowedForPlayer(classID, subclassID)
	if not classID or not subclassID then return false end
	if not addon.variables then return false end
	local className = addon.variables.unitClass
	local specIndex = addon.variables.unitSpec
	if not className or not specIndex then return false end
	local classFilters = addon.itemBagFilterTypes and addon.itemBagFilterTypes[className]
	if not classFilters then return false end
	local specFilters = classFilters[specIndex]
	if not specFilters then return false end
	local classEntry = specFilters[classID]
	if not classEntry then return false end
	if classEntry[subclassID] then return true end
	if classEntry[0] then return true end
	return false
end

local function getItemLevelSafe(item)
	local level = item:GetCurrentItemLevel()
	if not level or level == 0 then level = getItemLevelFromLink(item:GetItemLink()) end
	return level
end

local function isUpgradeForPlayer(item, itemEquipLoc, classID, subclassID)
	if not itemEquipLoc or itemEquipLoc == "" then return false end
	local slotsForLoc = EQUIP_LOC_TO_SLOTS[itemEquipLoc]
	if not slotsForLoc or #slotsForLoc == 0 then return false end
	if not isItemAllowedForPlayer(classID, subclassID) then return false end

	local newItemLevel = getItemLevelSafe(item)
	if not newItemLevel then return false end

	local hasComparableItem = false
	local lowestEquippedLevel

	for _, slotID in ipairs(slotsForLoc) do
		local link = GetInventoryItemLink("player", slotID)
		if not link then return true end
		hasComparableItem = true
		local equippedLevel = getItemLevelFromLink(link)
		if equippedLevel then
			if not lowestEquippedLevel or equippedLevel < lowestEquippedLevel then lowestEquippedLevel = equippedLevel end
		end
	end

	if not hasComparableItem then return true end
	if not lowestEquippedLevel then return false end

	return newItemLevel > lowestEquippedLevel
end

local function passesFilters(item)
	local _, _, quality, _, _, _, _, _, itemEquipLoc, _, _, classID, subclassID = C_Item.GetItemInfo(item:GetItemLink())

	local filter = addon.db.lootToastFilters and addon.db.lootToastFilters[quality]
	if not filter then return false end

	local has = filter.ilvl or filter.mounts or filter.pets or filter.upgrade
	if not has then return true end

	if filter.mounts and classID == 15 and subclassID == 5 then return true end
	if filter.pets and isPet(classID, subclassID) then return true end
	if filter.upgrade and isUpgradeForPlayer(item, itemEquipLoc, classID, subclassID) then return true end

	if filter.ilvl then
		local thresholds = addon.db.lootToastItemLevels or {}
		local limit = thresholds[quality] or addon.db.lootToastItemLevel
		if limit and item:GetCurrentItemLevel() >= limit then return true end
	end

	return false
end

local function shouldShowToast(item)
	if not addon.db.enableLootToastFilter then return true end
	return passesFilters(item)
end

local ITEM_LINK_PATTERN = "|Hitem:.-|h%[.-%]|h|r"
local myGUID = UnitGUID("player")

function LootToast:OnEvent(_, event, ...)
	if event == "SHOW_LOOT_TOAST" then
		local typeIdentifier, itemLink, quantity, specID, _, _, _, lessAwesome, isUpgraded, isCorrupted = ...
		if typeIdentifier ~= "item" then return end
		local item = Item:CreateFromItemLink(itemLink)
		if not item or item:IsItemEmpty() then return end
		item:ContinueOnItemLoad(function()
			if shouldShowToast(item) then
				LootAlertSystem:AddAlert(itemLink, quantity, nil, nil, specID, nil, nil, nil, lessAwesome, isUpgraded, isCorrupted)
				local file = addon.ChatIM and addon.ChatIM.availableSounds and addon.ChatIM.availableSounds[addon.db.lootToastCustomSoundFile]
				if addon.db.lootToastUseCustomSound and file then PlaySoundFile(file, "Master") end
			end
		end)
	elseif event == "CHAT_MSG_LOOT" then
		if ItemUpgradeFrame and ItemUpgradeFrame:IsShown() then return end
		local msg, _, _, _, _, _, _, _, _, _, _, guid = ...
		if guid ~= myGUID then return end
		local itemLink = msg:match(ITEM_LINK_PATTERN)
		if not itemLink then return end
		local quantity = tonumber(msg:match("x(%d+)")) or 1
		local itemID = tonumber(itemLink:match("item:(%d+)"))

		if addon.db.lootToastIncludeIDs and addon.db.lootToastIncludeIDs[itemID] then
			LootAlertSystem:AddAlert(itemLink, quantity, nil, nil, 0, nil, nil, nil, false, false, false)
			local file = addon.ChatIM and addon.ChatIM.availableSounds and addon.ChatIM.availableSounds[addon.db.lootToastCustomSoundFile]
			if addon.db.lootToastUseCustomSound and file then PlaySoundFile(file, "Master") end
		end
	end
end

local BLACKLISTED_EVENTS = {
	LOOT_ITEM_ROLL_WON = false,
	LOOT_ITEM_ROLL_SELF = false,
	LOOT_ITEM_ROLL_NEED = false,
	LOOT_ITEM_ROLL_GREED = false,
	LOOT_ITEM_ROLL_PASS = false,
	SHOW_LOOT_TOAST = true,
	SHOW_LOOT_TOAST_UPGRADE = false,
	SHOW_LOOT_TOAST_LEGENDARY = false,
}

function LootToast:Enable()
	if self.enabled then return end
	self.enabled = true
	self.frame:RegisterEvent("SHOW_LOOT_TOAST")
	self.frame:RegisterEvent("CHAT_MSG_LOOT")
	self.frame:SetScript("OnEvent", function(...) self:OnEvent(...) end)
	-- disable default toast

	for event, state in pairs(BLACKLISTED_EVENTS) do
		if state and AlertFrame:IsEventRegistered(event) then AlertFrame:UnregisterEvent(event) end
	end
	hooksecurefunc(AlertFrame, "RegisterEvent", function(selfFrame, event)
		if LootToast.enabled and BLACKLISTED_EVENTS[event] then xpcall(selfFrame.UnregisterEvent, selfFrame, event) end
	end)
	if addon.db.enableLootToastAnchor then self:ApplyAnchorPosition() end
end

function LootToast:Disable()
	if not self.enabled then return end
	self.enabled = false
	self.frame:UnregisterEvent("SHOW_LOOT_TOAST")
	self.frame:UnregisterEvent("CHAT_MSG_LOOT")
	self.frame:SetScript("OnEvent", nil)
	AlertFrame:RegisterEvent("SHOW_LOOT_TOAST")
	self:RestoreDefaultAnchors()
end

local DEFAULT_ANCHOR = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 240 }
LootToast.anchorFrame = LootToast.anchorFrame
LootToast.defaultAlertAnchor = LootToast.defaultAlertAnchor
LootToast.defaultGroupLootAnchor = LootToast.defaultGroupLootAnchor

local function RememberDefaultAnchors()
	if not LootToast.defaultAlertAnchor then
		local point, relativeTo, relativePoint, x, y = AlertFrame:GetPoint()
		if point then LootToast.defaultAlertAnchor = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y } end
	end
	if GroupLootContainer and not LootToast.defaultGroupLootAnchor then
		local point, relativeTo, relativePoint, x, y = GroupLootContainer:GetPoint()
		if point then LootToast.defaultGroupLootAnchor = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y } end
	end
end

function LootToast:RestoreDefaultAnchors()
	if self.anchorFrame then self.anchorFrame:Hide() end
	local alert = self.defaultAlertAnchor
	if alert and alert.point then
		AlertFrame:ClearAllPoints()
		AlertFrame:SetPoint(alert.point, alert.relativeTo, alert.relativePoint, alert.x, alert.y)
	end
	if GroupLootContainer then
		local container = self.defaultGroupLootAnchor
		if container and container.point then
			GroupLootContainer:ClearAllPoints()
			GroupLootContainer:SetPoint(container.point, container.relativeTo, container.relativePoint, container.x, container.y)
		end
	end
end

local function GetAnchorConfig()
	addon.db.lootToastAnchor = addon.db.lootToastAnchor or {}
	local cfg = addon.db.lootToastAnchor

	cfg.point = cfg.point or DEFAULT_ANCHOR.point
	cfg.relativePoint = cfg.relativePoint or DEFAULT_ANCHOR.relativePoint
	cfg.x = cfg.x or DEFAULT_ANCHOR.x
	cfg.y = cfg.y or DEFAULT_ANCHOR.y
	return cfg
end

local function SaveAnchor(frame)
	local point, _, relativePoint, x, y = frame:GetPoint()
	local cfg = GetAnchorConfig()
	cfg.point = point
	cfg.relativePoint = relativePoint or point
	cfg.x = x
	cfg.y = y
end

function LootToast:GetAnchorFrame()
	if self.anchorFrame then return self.anchorFrame end

	local frame = CreateFrame("Frame", "EnhanceQoL_LootToastAnchor", UIParent, "BackdropTemplate")
	frame:SetSize(240, 40)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(anchor)
		anchor:StopMovingOrSizing()
		SaveAnchor(anchor)
		LootToast:ApplyAnchorPosition()
	end)

	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	frame:SetBackdropColor(0.05, 0.2, 0.6, 0.35)
	frame:SetBackdropBorderColor(0.1, 0.3, 0.7, 0.9)

	local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("CENTER")
	label:SetText(L["lootToastAnchorLabel"])
	frame.label = label

	frame:Hide()
	self.anchorFrame = frame
	return frame
end

function LootToast:ApplyAnchorPosition()
	if not addon.db.enableLootToastAnchor then
		self:RestoreDefaultAnchors()
		return
	end

	RememberDefaultAnchors()
	local cfg = GetAnchorConfig()
	local anchor = self:GetAnchorFrame()
	anchor:ClearAllPoints()
	anchor:SetPoint(cfg.point, UIParent, cfg.relativePoint, cfg.x, cfg.y)
	if anchor.label then anchor.label:SetText(L["lootToastAnchorLabel"]) end

	AlertFrame:ClearAllPoints()
	AlertFrame:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 0)
	if GroupLootContainer then
		GroupLootContainer:ClearAllPoints()
		GroupLootContainer:SetPoint("BOTTOM", anchor, "TOP", 0, 8)
	end
end

function LootToast:ToggleAnchorPreview()
	if not addon.db.enableLootToastAnchor then return end
	local anchor = self:GetAnchorFrame()
	if anchor:IsShown() then
		anchor:Hide()
	else
		self:ApplyAnchorPosition()
		anchor:Show()
	end
end

function LootToast:OnAnchorOptionChanged(enabled)
	if not enabled then
		if self.anchorFrame then self.anchorFrame:Hide() end
		self:RestoreDefaultAnchors()
	else
		self:ApplyAnchorPosition()
	end
end

local function ReanchorAlerts()
	if addon.db.enableLootToastAnchor then
		LootToast:ApplyAnchorPosition()
	elseif LootToast.defaultAlertAnchor then
		LootToast:RestoreDefaultAnchors()
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UI_SCALE_CHANGED")
f:RegisterEvent("DISPLAY_SIZE_CHANGED")
local anchorsHooked = false
f:SetScript("OnEvent", function()
	RememberDefaultAnchors()
	if not anchorsHooked then
		hooksecurefunc(AlertFrame, "UpdateAnchors", ReanchorAlerts)
		anchorsHooked = true
	end
	ReanchorAlerts()
end)
