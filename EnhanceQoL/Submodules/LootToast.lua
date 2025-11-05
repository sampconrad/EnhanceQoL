-- luacheck: globals AlertFrame LootAlertSystem
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = addon.L
local EditMode = addon.EditMode

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

	local hasComparableItem = false
	local lowestEquippedLevel

	for _, slotID in ipairs(slotsForLoc) do
		local link = GetInventoryItemLink("player", slotID)
		if not link or link == "" then return true end
		hasComparableItem = true
		local equippedLevel = getItemLevelFromLink(link)
		if equippedLevel then
			if not lowestEquippedLevel or equippedLevel < lowestEquippedLevel then lowestEquippedLevel = equippedLevel end
		end
	end

	if not hasComparableItem then return true end
	local newItemLevel = getItemLevelSafe(item)
	if not newItemLevel then return false end
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
	if not self.enabled then
		self.enabled = true
		if not self.alertFrameHooked then
			hooksecurefunc(AlertFrame, "RegisterEvent", function(selfFrame, event)
				if LootToast.handleToasts and BLACKLISTED_EVENTS[event] then xpcall(selfFrame.UnregisterEvent, selfFrame, event) end
			end)
			self.alertFrameHooked = true
		end
	end

	self:RefreshEventBindings()

	if addon.db.enableLootToastAnchor then
		self:ApplyAnchorPosition()
	elseif not addon.db.enableGroupLootAnchor then
		self:RestoreDefaultAnchors()
	end
	if addon.db.enableGroupLootAnchor then self:ApplyGroupLootLayout() end
end

function LootToast:Disable()
	if not self.enabled then return end
	self.enabled = false
	self.handleToasts = false
	if self.frame:IsEventRegistered("SHOW_LOOT_TOAST") then self.frame:UnregisterEvent("SHOW_LOOT_TOAST") end
	if self.frame:IsEventRegistered("CHAT_MSG_LOOT") then self.frame:UnregisterEvent("CHAT_MSG_LOOT") end
	self.frame:SetScript("OnEvent", nil)
	for event, state in pairs(BLACKLISTED_EVENTS) do
		if state and not AlertFrame:IsEventRegistered(event) then AlertFrame:RegisterEvent(event) end
	end
	self:RestoreDefaultAnchors(true)
end

function LootToast:RefreshEventBindings()
	if not self.frame then return end
	local handleToasts = addon.db and (addon.db.enableLootToastFilter == true or addon.db.enableLootToastAnchor == true) or false
	self.handleToasts = handleToasts

	if handleToasts then
		if not self.frame:IsEventRegistered("SHOW_LOOT_TOAST") then self.frame:RegisterEvent("SHOW_LOOT_TOAST") end
		if not self.frame:IsEventRegistered("CHAT_MSG_LOOT") then self.frame:RegisterEvent("CHAT_MSG_LOOT") end
		self.frame:SetScript("OnEvent", function(...) self:OnEvent(...) end)
		for event, state in pairs(BLACKLISTED_EVENTS) do
			if state and AlertFrame:IsEventRegistered(event) then AlertFrame:UnregisterEvent(event) end
		end
	else
		if self.frame:IsEventRegistered("SHOW_LOOT_TOAST") then self.frame:UnregisterEvent("SHOW_LOOT_TOAST") end
		if self.frame:IsEventRegistered("CHAT_MSG_LOOT") then self.frame:UnregisterEvent("CHAT_MSG_LOOT") end
		self.frame:SetScript("OnEvent", nil)
		for event, state in pairs(BLACKLISTED_EVENTS) do
			if state and not AlertFrame:IsEventRegistered(event) then AlertFrame:RegisterEvent(event) end
		end
	end
end

local DEFAULT_TOAST_ANCHOR = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 240 }
local DEFAULT_GROUPROLL_ANCHOR = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 300 }
local TOAST_EDITMODE_ID = "lootToastAnchor"
local GROUPROLL_EDITMODE_ID = "groupLootAnchor"
LootToast.toastAnchorFrame = LootToast.toastAnchorFrame
LootToast.groupRollAnchorFrame = LootToast.groupRollAnchorFrame
LootToast.defaultAlertAnchor = LootToast.defaultAlertAnchor
LootToast.handleToasts = LootToast.handleToasts or false
LootToast.alertFrameHooked = LootToast.alertFrameHooked
local GroupLootContainer = _G.GroupLootContainer
LootToast.defaultGroupLootAnchor = LootToast.defaultGroupLootAnchor
LootToast.defaultBonusRollAnchor = LootToast.defaultBonusRollAnchor

local DEFAULT_GROUPROLL_LAYOUT = { scale = 1, offsetX = 0, offsetY = 0, spacing = 4 }

local function FrameIsAccessible(frame)
	if not frame then return false end
	if frame.IsForbidden and frame:IsForbidden() then return false end
	return true
end

local function RememberDefaultAnchors()
	if not LootToast.defaultAlertAnchor then
		local point, relativeTo, relativePoint, x, y = AlertFrame:GetPoint()
		if point then LootToast.defaultAlertAnchor = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y } end
	end
	if GroupLootContainer and not LootToast.defaultGroupLootAnchor then
		local point, relativeTo, relativePoint, x, y = GroupLootContainer:GetPoint()
		if point then LootToast.defaultGroupLootAnchor = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y } end
	end
	if not LootToast.defaultBonusRollAnchor then
		local bonusFrame = _G.BonusRollFrame
		if FrameIsAccessible(bonusFrame) then
			local point, relativeTo, relativePoint, x, y = bonusFrame:GetPoint()
			if point then LootToast.defaultBonusRollAnchor = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y } end
		end
	end
end

function LootToast:RestoreDefaultAnchors(force)
	if force or not addon.db.enableLootToastAnchor then
		if self.toastAnchorFrame then self.toastAnchorFrame:Hide() end
		local alert = self.defaultAlertAnchor
		if alert and alert.point then
			AlertFrame:ClearAllPoints()
			AlertFrame:SetPoint(alert.point, alert.relativeTo, alert.relativePoint, alert.x, alert.y)
		end
	end

	if force or not addon.db.enableGroupLootAnchor then
		if self.groupRollAnchorFrame then self.groupRollAnchorFrame:Hide() end
		if GroupLootContainer then
			local container = self.defaultGroupLootAnchor
			if container and container.point then
				GroupLootContainer:ClearAllPoints()
				GroupLootContainer:SetPoint(container.point, container.relativeTo, container.relativePoint, container.x, container.y)
			end
			GroupLootContainer.ignoreFramePositionManager = nil
			GroupLootContainer:SetScale(1)
			for i = 1, NUM_GROUP_LOOT_FRAMES or 4 do
				local frame = _G["GroupLootFrame" .. i]
				if FrameIsAccessible(frame) then frame:SetScale(1) end
			end
		end
		local bonusFrame = _G.BonusRollFrame
		if FrameIsAccessible(bonusFrame) then
			local saved = self.defaultBonusRollAnchor
			bonusFrame:ClearAllPoints()
			if saved and saved.point then bonusFrame:SetPoint(saved.point, saved.relativeTo, saved.relativePoint, saved.x, saved.y) end
			bonusFrame:SetScale(1)
			bonusFrame.ignoreFramePositionManager = nil
		end
	end
end

local function GetToastAnchorConfig()
	addon.db.lootToastAnchor = addon.db.lootToastAnchor or {}
	local cfg = addon.db.lootToastAnchor

	cfg.point = cfg.point or DEFAULT_TOAST_ANCHOR.point
	cfg.relativePoint = cfg.relativePoint or DEFAULT_TOAST_ANCHOR.relativePoint
	cfg.x = cfg.x or DEFAULT_TOAST_ANCHOR.x
	cfg.y = cfg.y or DEFAULT_TOAST_ANCHOR.y
	return cfg
end

local function UpdateToastAnchorConfig(data)
	if not data then return end
	local cfg = GetToastAnchorConfig()
	if data.point then
		cfg.point = data.point
		cfg.relativePoint = data.point
	end
	if data.relativePoint then cfg.relativePoint = data.relativePoint end
	if data.x ~= nil then cfg.x = data.x end
	if data.y ~= nil then cfg.y = data.y end
end

local function GetGroupRollAnchorConfig()
	addon.db.groupLootAnchor = addon.db.groupLootAnchor or {}
	local cfg = addon.db.groupLootAnchor

	cfg.point = cfg.point or DEFAULT_GROUPROLL_ANCHOR.point
	cfg.relativePoint = cfg.relativePoint or DEFAULT_GROUPROLL_ANCHOR.relativePoint
	cfg.x = cfg.x or DEFAULT_GROUPROLL_ANCHOR.x
	cfg.y = cfg.y or DEFAULT_GROUPROLL_ANCHOR.y
	return cfg
end

local function UpdateGroupRollAnchorConfig(data)
	if not data then return end
	local cfg = GetGroupRollAnchorConfig()
	if data.point then
		cfg.point = data.point
		cfg.relativePoint = data.point
	end
	if data.relativePoint then cfg.relativePoint = data.relativePoint end
	if data.x ~= nil then cfg.x = data.x end
	if data.y ~= nil then cfg.y = data.y end
end

local function GetGroupLootLayoutConfig()
	addon.db.groupLootLayout = addon.db.groupLootLayout or {}
	local layout = addon.db.groupLootLayout
	if type(layout.scale) ~= "number" then layout.scale = DEFAULT_GROUPROLL_LAYOUT.scale end
	if layout.scale < 0.5 then layout.scale = 0.5 end
	if layout.scale > 3 then layout.scale = 3 end
	if layout.offsetX == nil then layout.offsetX = DEFAULT_GROUPROLL_LAYOUT.offsetX end
	if layout.offsetY == nil then layout.offsetY = DEFAULT_GROUPROLL_LAYOUT.offsetY end
	if layout.spacing == nil then layout.spacing = DEFAULT_GROUPROLL_LAYOUT.spacing end
	return layout
end

local function UpdateAnchorLabel(anchor, layout, labelKey)
	if not anchor or not anchor.label then return end
	local baseLabel = labelKey and (L[labelKey] or labelKey) or L["lootToastAnchorLabel"]
	local info = layout
	if info and info.scale and math.abs(info.scale - 1) > 0.01 then
		anchor.label:SetText(string.format("%s (x%.2f)", baseLabel, info.scale))
	else
		anchor.label:SetText(baseLabel)
	end
end

function LootToast:GetGroupLootLayout() return GetGroupLootLayoutConfig() end

function LootToast:ApplyGroupLootLayout()
	if not addon.db.enableGroupLootAnchor then
		self:RestoreDefaultAnchors()
		return
	end

	RememberDefaultAnchors()

	local layout = GetGroupLootLayoutConfig()
	local anchor = self:GetGroupRollAnchorFrame()
	local cfg = GetGroupRollAnchorConfig()

	self:RegisterGroupRollAnchorWithEditMode(anchor)
	anchor:ClearAllPoints()
	anchor:SetPoint(cfg.point, UIParent, cfg.relativePoint, cfg.x, cfg.y)
	UpdateAnchorLabel(anchor, layout, "groupLootAnchorLabel")

	if FrameIsAccessible(GroupLootContainer) then
		GroupLootContainer.ignoreFramePositionManager = true
		GroupLootContainer:EnableMouse(false)
		GroupLootContainer:ClearAllPoints()
		GroupLootContainer:SetPoint("BOTTOM", anchor, "BOTTOM", layout.offsetX, layout.offsetY)
		GroupLootContainer:SetScale(layout.scale)
	end

	local bonusFrame = _G.BonusRollFrame
	if FrameIsAccessible(bonusFrame) then
		bonusFrame.ignoreFramePositionManager = true
		bonusFrame:ClearAllPoints()
		bonusFrame:SetPoint("BOTTOM", anchor, "TOP", layout.offsetX, layout.offsetY)
		bonusFrame:SetScale(layout.scale)
	end

	self:SyncRollEditModePosition()
end

function LootToast:SyncToastEditModePosition()
	if not EditMode or not self.toastAnchorEditModeId or self.toastAnchorSuspendEditSync or self.toastAnchorApplyingFromEditMode then return end
	self.toastAnchorSuspendEditSync = true
	local cfg = GetToastAnchorConfig()
	EditMode:SetFramePosition(self.toastAnchorEditModeId, cfg.point or DEFAULT_TOAST_ANCHOR.point, cfg.x or DEFAULT_TOAST_ANCHOR.x, cfg.y or DEFAULT_TOAST_ANCHOR.y)
	self.toastAnchorSuspendEditSync = nil
end

function LootToast:SyncRollEditModePosition()
	if not EditMode or not self.groupRollAnchorEditModeId or self.groupRollAnchorSuspendEditSync or self.groupRollAnchorApplyingFromEditMode then return end
	self.groupRollAnchorSuspendEditSync = true
	local cfg = GetGroupRollAnchorConfig()
	EditMode:SetFramePosition(self.groupRollAnchorEditModeId, cfg.point or DEFAULT_GROUPROLL_ANCHOR.point, cfg.x or DEFAULT_GROUPROLL_ANCHOR.x, cfg.y or DEFAULT_GROUPROLL_ANCHOR.y)
	self.groupRollAnchorSuspendEditSync = nil
end

function LootToast:RegisterToastAnchorWithEditMode(anchor)
	if self.toastAnchorRegistered or self.toastAnchorRegistering then return end
	if not EditMode or not EditMode.RegisterFrame or not EditMode:IsAvailable() then return end

	self.toastAnchorRegistering = true

	local cfg = GetToastAnchorConfig()
	local title = L["lootToastAnchorLabel"] or "Loot Toast Anchor"
	anchor.editModeName = title

	local defaults = {
		point = cfg.point or DEFAULT_TOAST_ANCHOR.point,
		relativePoint = cfg.relativePoint or cfg.point or DEFAULT_TOAST_ANCHOR.relativePoint,
		x = cfg.x or DEFAULT_TOAST_ANCHOR.x,
		y = cfg.y or DEFAULT_TOAST_ANCHOR.y,
		width = anchor:GetWidth(),
		height = anchor:GetHeight(),
	}

	EditMode:RegisterFrame(TOAST_EDITMODE_ID, {
		frame = anchor,
		title = title,
		layoutDefaults = defaults,
		isEnabled = function() return addon.db.enableLootToastAnchor end,
		onApply = function(_, _, data)
			if not data then return end
			LootToast.toastAnchorApplyingFromEditMode = true
			UpdateToastAnchorConfig(data)
			LootToast:ApplyAnchorPosition()
			LootToast.toastAnchorApplyingFromEditMode = nil
		end,
		onPositionChanged = function(_, _, data)
			if not data then return end
			LootToast.toastAnchorApplyingFromEditMode = true
			UpdateToastAnchorConfig(data)
			LootToast:ApplyAnchorPosition()
			LootToast.toastAnchorApplyingFromEditMode = nil
		end,
	})

	self.toastAnchorEditModeId = TOAST_EDITMODE_ID
	self.toastAnchorRegistered = true
	self.toastAnchorRegistering = nil

	anchor:EnableMouse(false)
	anchor:RegisterForDrag()
	anchor:SetScript("OnDragStart", nil)
	anchor:SetScript("OnDragStop", nil)

	self:SyncToastEditModePosition()
end

function LootToast:RegisterGroupRollAnchorWithEditMode(anchor)
	if self.groupRollAnchorRegistered or self.groupRollAnchorRegistering then return end
	if not EditMode or not EditMode.RegisterFrame or not EditMode:IsAvailable() then return end

	self.groupRollAnchorRegistering = true

	local cfg = GetGroupRollAnchorConfig()
	local title = L["groupLootAnchorLabel"] or "Group Loot Anchor"
	anchor.editModeName = title

	local defaults = {
		point = cfg.point or DEFAULT_GROUPROLL_ANCHOR.point,
		relativePoint = cfg.relativePoint or cfg.point or DEFAULT_GROUPROLL_ANCHOR.relativePoint,
		x = cfg.x or DEFAULT_GROUPROLL_ANCHOR.x,
		y = cfg.y or DEFAULT_GROUPROLL_ANCHOR.y,
		width = anchor:GetWidth(),
		height = anchor:GetHeight(),
	}

	EditMode:RegisterFrame(GROUPROLL_EDITMODE_ID, {
		frame = anchor,
		title = title,
		layoutDefaults = defaults,
		isEnabled = function() return addon.db.enableGroupLootAnchor end,
		onApply = function(_, _, data)
			if not data then return end
			LootToast.groupRollAnchorApplyingFromEditMode = true
			UpdateGroupRollAnchorConfig(data)
			LootToast:ApplyGroupLootLayout()
			LootToast.groupRollAnchorApplyingFromEditMode = nil
		end,
		onPositionChanged = function(_, _, data)
			if not data then return end
			LootToast.groupRollAnchorApplyingFromEditMode = true
			UpdateGroupRollAnchorConfig(data)
			LootToast:ApplyGroupLootLayout()
			LootToast.groupRollAnchorApplyingFromEditMode = nil
		end,
	})

	self.groupRollAnchorEditModeId = GROUPROLL_EDITMODE_ID
	self.groupRollAnchorRegistered = true
	self.groupRollAnchorRegistering = nil

	anchor:EnableMouse(false)
	anchor:RegisterForDrag()
	anchor:SetScript("OnDragStart", nil)
	anchor:SetScript("OnDragStop", nil)

	self:SyncRollEditModePosition()
end

function LootToast:GetToastAnchorFrame()
	if self.toastAnchorFrame then return self.toastAnchorFrame end

	local frame = CreateFrame("Frame", "EnhanceQoL_LootToastAnchor", UIParent, "BackdropTemplate")
	frame:SetSize(240, 40)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	if EditMode and EditMode.RegisterFrame then
		frame:EnableMouse(false)
	else
		frame:EnableMouse(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", frame.StartMoving)
		frame:SetScript("OnDragStop", function(anchor)
			anchor:StopMovingOrSizing()
			local point, _, relativePoint, x, y = anchor:GetPoint()
			UpdateToastAnchorConfig({ point = point, relativePoint = relativePoint or point, x = x, y = y })
			LootToast:ApplyAnchorPosition()
		end)
	end

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
	self.toastAnchorFrame = frame
	self:RegisterToastAnchorWithEditMode(frame)
	return frame
end

function LootToast:ApplyAnchorPosition()
	if not addon.db.enableLootToastAnchor then
		self:RestoreDefaultAnchors()
		return
	end

	RememberDefaultAnchors()
	local cfg = GetToastAnchorConfig()
	local anchor = self:GetToastAnchorFrame()
	self:RegisterToastAnchorWithEditMode(anchor)
	anchor:ClearAllPoints()
	anchor:SetPoint(cfg.point, UIParent, cfg.relativePoint, cfg.x, cfg.y)
	UpdateAnchorLabel(anchor, nil, "lootToastAnchorLabel")

	AlertFrame:ClearAllPoints()
	AlertFrame:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 0)
	if addon.db.enableGroupLootAnchor then self:ApplyGroupLootLayout() end
	self:SyncToastEditModePosition()
end

function LootToast:ToggleAnchorPreview()
	if not addon.db.enableLootToastAnchor then return end
	local anchor = self:GetToastAnchorFrame()
	if anchor:IsShown() then
		anchor:Hide()
	else
		self:ApplyAnchorPosition()
		anchor:Show()
	end
end

function LootToast:OnAnchorOptionChanged(enabled)
	if not enabled then
		if self.toastAnchorFrame then self.toastAnchorFrame:Hide() end
		self:RestoreDefaultAnchors()
	else
		self:ApplyAnchorPosition()
	end
	if EditMode and EditMode.RefreshFrame then EditMode:RefreshFrame(TOAST_EDITMODE_ID) end
end

function LootToast:GetGroupRollAnchorFrame()
	if self.groupRollAnchorFrame then return self.groupRollAnchorFrame end

	local frame = CreateFrame("Frame", "EnhanceQoL_GroupLootAnchor", UIParent, "BackdropTemplate")
	local width = 277
	local height = 67
	if FrameIsAccessible(GroupLootFrame1) then
		local w = GroupLootFrame1:GetWidth()
		local h = GroupLootFrame1:GetHeight()
		if w and w > 0 then width = w end
		if h and h > 0 then height = h end
	end
	frame:SetSize(width, height)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	if EditMode and EditMode.RegisterFrame then
		frame:EnableMouse(false)
	else
		frame:EnableMouse(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", frame.StartMoving)
		frame:SetScript("OnDragStop", function(anchor)
			anchor:StopMovingOrSizing()
			local point, _, relativePoint, x, y = anchor:GetPoint()
			UpdateGroupRollAnchorConfig({ point = point, relativePoint = relativePoint or point, x = x, y = y })
			LootToast:ApplyGroupLootLayout()
		end)
	end

	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	frame:SetBackdropColor(0.05, 0.18, 0.55, 0.35)
	frame:SetBackdropBorderColor(0.12, 0.42, 0.82, 0.9)

	local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("CENTER")
	label:SetText(L["groupLootAnchorLabel"])
	frame.label = label

	frame:Hide()
	self.groupRollAnchorFrame = frame
	self:RegisterGroupRollAnchorWithEditMode(frame)
	return frame
end

function LootToast:ToggleGroupRollAnchorPreview()
	if not addon.db.enableGroupLootAnchor then return end
	local anchor = self:GetGroupRollAnchorFrame()
	if anchor:IsShown() then
		anchor:Hide()
	else
		self:ApplyGroupLootLayout()
		anchor:Show()
	end
end

function LootToast:OnGroupRollAnchorOptionChanged(enabled)
	if not enabled then
		if self.groupRollAnchorFrame then self.groupRollAnchorFrame:Hide() end
		self:RestoreDefaultAnchors()
	else
		self:ApplyGroupLootLayout()
	end
	if EditMode and EditMode.RefreshFrame then EditMode:RefreshFrame(GROUPROLL_EDITMODE_ID) end
end

local function ReanchorAlerts()
	if addon.db.enableLootToastAnchor then
		LootToast:ApplyAnchorPosition()
	elseif LootToast.defaultAlertAnchor and not addon.db.enableGroupLootAnchor then
		LootToast:RestoreDefaultAnchors()
	end
	if addon.db.enableGroupLootAnchor then LootToast:ApplyGroupLootLayout() end
end

local hookedGroupLootCallbacks = {}

local function SetupGroupLootHooks()
	local function tryHook(name)
		if hookedGroupLootCallbacks[name] then return end
		if type(_G[name]) == "function" then
			hooksecurefunc(name, function()
				if addon.db.enableGroupLootAnchor and LootToast.ApplyGroupLootLayout then LootToast:ApplyGroupLootLayout() end
			end)
			hookedGroupLootCallbacks[name] = true
		end
	end

	tryHook("GroupLootContainer_OnLoad")
	tryHook("GroupLootContainer_RemoveFrame")
	tryHook("GroupLootContainer_Update")
	tryHook("GroupLootFrame_OnShow")
	tryHook("BonusRollFrame_OnLoad")
	tryHook("BonusRollFrame_OnShow")
	tryHook("BonusRollFrame_OnUpdate")
	tryHook("BonusRollFrame_StartBonusRoll")
end

SetupGroupLootHooks()

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UI_SCALE_CHANGED")
f:RegisterEvent("DISPLAY_SIZE_CHANGED")
local anchorsHooked = false
f:SetScript("OnEvent", function()
	RememberDefaultAnchors()
	SetupGroupLootHooks()
	if not anchorsHooked then
		hooksecurefunc(AlertFrame, "UpdateAnchors", ReanchorAlerts)
		anchorsHooked = true
	end
	ReanchorAlerts()
end)
