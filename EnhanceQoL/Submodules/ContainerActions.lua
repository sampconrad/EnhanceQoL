local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.ContainerActions = addon.ContainerActions or {}
local ContainerActions = addon.ContainerActions

local L = LibStub("AceLocale-3.0"):GetLocale(parentAddonName)

local BUTTON_SIZE = 48
local PREVIEW_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local DEFAULT_ANCHOR = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -200 }

local function InCombat() return InCombatLockdown and InCombatLockdown() end

local function FormatAnchorPoint(data)
	data = data or {}
	data.point = data.point or DEFAULT_ANCHOR.point
	data.relativePoint = data.relativePoint or DEFAULT_ANCHOR.relativePoint
	if data.x == nil then data.x = DEFAULT_ANCHOR.x end
	if data.y == nil then data.y = DEFAULT_ANCHOR.y end
	return data
end

local function SecureSort(a, b)
	if a.bag == b.bag then return a.slot < b.slot end
	return a.bag < b.bag
end

local function GetButtonIcon(button)
	if not button then return nil end
	return button.Icon or button.icon or button:GetNormalTexture()
end

local function SetButtonIconTexture(button, texture)
	local icon = GetButtonIcon(button)
	if icon and icon.SetTexture then
		icon:SetTexture(texture)
	elseif button and button.SetNormalTexture then
		button:SetNormalTexture(texture or "")
	end
end

local function SetButtonIconTexCoord(button, ...)
	local icon = GetButtonIcon(button)
	if icon and icon.SetTexCoord then icon:SetTexCoord(...) end
end

function ContainerActions:IsEnabled() return addon.db and addon.db["automaticallyOpenContainer"] end

function ContainerActions:GetAnchorConfig()
	addon.db.containerActionAnchor = FormatAnchorPoint(addon.db.containerActionAnchor)
	return addon.db.containerActionAnchor
end

function ContainerActions:EnsureAnchor()
	if self.anchor then return self.anchor end

	local anchor = CreateFrame("Frame", "EnhanceQoLContainerActionAnchor", UIParent, "BackdropTemplate")
	anchor:SetSize(BUTTON_SIZE + 12, BUTTON_SIZE + 12)
	anchor:SetFrameStrata("MEDIUM")
	anchor:SetClampedToScreen(true)
	anchor:SetMovable(true)
	anchor:EnableMouse(true)
	anchor:RegisterForDrag("LeftButton")
	anchor:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	anchor:SetBackdropColor(0.05, 0.05, 0.05, 0.6)
	anchor:SetBackdropBorderColor(1, 0.82, 0, 0.9)
	anchor:Hide()

	anchor:SetScript("OnDragStart", function(f)
		if InCombat() then return end
		f:StartMoving()
	end)
	anchor:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		ContainerActions:SaveAnchorPosition()
		ContainerActions:ApplyAnchorPosition()
	end)
	anchor:SetScript("OnHide", function(f) f:StopMovingOrSizing() end)

	local label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("CENTER", 0, 0)
	label:SetText(L["containerActionsAnchorLabel"] or "Container Button")

	self.anchor = anchor
	self.anchorLabel = label
	self:ApplyAnchorPosition()
	return anchor
end

function ContainerActions:SaveAnchorPosition()
	if not self.anchor then return end
	local point, _, relativePoint, x, y = self.anchor:GetPoint(1)
	addon.db.containerActionAnchor = {
		point = point,
		relativePoint = relativePoint,
		x = x,
		y = y,
	}
end

function ContainerActions:ApplyAnchorPosition()
	local anchor = self:EnsureAnchor()
	local cfg = self:GetAnchorConfig()
	anchor:ClearAllPoints()
	anchor:SetPoint(cfg.point or "CENTER", UIParent, cfg.relativePoint or "CENTER", cfg.x or 0, cfg.y or 0)
	if self.button then
		self.button:ClearAllPoints()
		self.button:SetPoint("CENTER", anchor, "CENTER", 0, 0)
	end
end

function ContainerActions:EnsureButton()
	if self.button then return self.button end

	local button = CreateFrame("Button", "EnhanceQoLContainerActionButton", UIParent, "ActionButtonTemplate,SecureActionButtonTemplate")
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetAttribute("pressAndHoldAction", false) -- verhindert Wiederholen beim Halten
	button:SetAttribute("*type*", nil)
	SetButtonIconTexCoord(button, 0.08, 0.92, 0.08, 0.92)
	if button.HotKey then button.HotKey:SetText("") end
	if button.Name then button.Name:Hide() end
	button:SetPoint("CENTER", self:EnsureAnchor(), "CENTER")
	button:Hide()

	button:SetScript("OnEnter", function(btn)
		if ContainerActions.previewActive then
			GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
			GameTooltip:SetText(L["containerActionsAnchorHelp"] or "")
			GameTooltip:Show()
			return
		end
		if not ContainerActions:IsEnabled() then return end
		if btn.entry then
			GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
			GameTooltip:SetBagItem(btn.entry.bag, btn.entry.slot)
			local extra = L["containerActionsButtonTooltip"]
			if extra and extra ~= "" then GameTooltip:AddLine(extra, 0.9, 0.9, 0.9, true) end
			GameTooltip:Show()
		else
			local text = L["containerActionsNoItems"] or ""
			if text ~= "" then
				GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
				GameTooltip:SetText(text)
				GameTooltip:Show()
			end
		end
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("PostClick", function() ContainerActions:OnPostClick() end)

	RegisterStateDriver(button, "visibility", "[combat] hide; show")

	self.button = button
	self.buttonIcon = GetButtonIcon(button)
	self:ApplyAnchorPosition()
	return button
end

function ContainerActions:Init()
	if self.initialized then return end
	self.initialized = true
	self.itemCache = self.itemCache or {}
	self.secureItems = {}
	self.pendingItem = nil
	self.pendingVisibility = nil
	self.awaitingRefresh = nil
	self.previewActive = false
	self.previewRestoreAfterCombat = nil
	self.desiredVisibility = nil
	self:EnsureAnchor()
	self:EnsureButton()

	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	frame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			ContainerActions:OnCombatStart()
		else
			ContainerActions:OnCombatEnd()
		end
	end)
	self.eventFrame = frame
end

function ContainerActions:OnCombatStart()
	if self.previewActive then
		self.previewRestoreAfterCombat = true
		self:HideAnchorPreview(true)
	end
end

function ContainerActions:OnCombatEnd()
	if self.pendingVisibility ~= nil then
		local desired = self.pendingVisibility
		self.pendingVisibility = nil
		self:RequestVisibility(desired)
	end
	if self.pendingItem ~= nil then
		local entry = self.pendingItem
		self.pendingItem = nil
		if entry then
			self:ApplyButtonEntry(entry)
		else
			self:ApplyButtonEntry(nil)
		end
	end
	if self.previewRestoreAfterCombat then
		self.previewRestoreAfterCombat = nil
		self:ShowAnchorPreview()
	end
	if self.pendingVisibility == nil and self.desiredVisibility ~= nil then self:RequestVisibility(self.desiredVisibility) end
end

function ContainerActions:ShowAnchorPreview()
	if InCombat() then
		local msg = L["containerActionsAnchorLockedCombat"]
		if msg and msg ~= "" then print("|cffff2020" .. msg .. "|r") end
		return
	end
	local anchor = self:EnsureAnchor()
	self.previewActive = true
	anchor:Show()
	self:ApplyAnchorPosition()

	local button = self:EnsureButton()
	button:SetAlpha(0.8)
	SetButtonIconTexture(button, PREVIEW_ICON)
	if button.Count then button.Count:SetText("") end
	if button:GetAttribute("item") then button:SetAttribute("item", nil) end
	button:SetAttribute("macrotext", nil)
	button:SetAttribute("type1", nil)
	button:SetAttribute("macrotext1", nil)
	button:SetAttribute("type", nil)
	button:SetAttribute("*type*", nil)
	button:SetAttribute("macrotext2", nil)
	button:SetAttribute("type2", nil)
	button.entry = nil
	self:RequestVisibility(true)
end

function ContainerActions:HideAnchorPreview(skipVisibility)
	self.previewActive = false
	if self.anchor then self.anchor:Hide() end
	local button = self.button
	if button then button:SetAlpha(1) end
	if skipVisibility then return end
	if not self:IsEnabled() or #self.secureItems == 0 then
		self:ApplyButtonEntry(nil)
		self:RequestVisibility(false)
	else
		self:ApplyButtonEntry(self.secureItems[1])
		self:RequestVisibility(true)
	end
end

function ContainerActions:ToggleAnchorPreview()
	if self.previewActive then
		self:HideAnchorPreview()
	else
		self:ShowAnchorPreview()
	end
end

function ContainerActions:GetTotalItemCount()
	local total = 0
	for _, entry in ipairs(self.secureItems or {}) do
		total = total + (entry.count or 1)
	end
	return total
end

function ContainerActions:UpdateCount()
	if not self.button then return end
	if self.previewActive then
		if self.button.Count then self.button.Count:SetText("") end
		return
	end
	local total = self:GetTotalItemCount()
	if not self.button.Count then return end
	if total > 1 then
		self.button.Count:SetText(total)
	else
		self.button.Count:SetText("")
	end
end

function ContainerActions:RememberItemInfo(itemID, config, info, overrides)
	self.itemCache = self.itemCache or {}
	local entry = self.itemCache[itemID]
	if not entry then
		entry = { itemID = itemID }
		self.itemCache[itemID] = entry
	end
	if info and info.iconFileID and info.iconFileID ~= 0 then entry.icon = info.iconFileID end
	if overrides and overrides.chunk then entry.chunk = overrides.chunk end
	if config and type(config) == "table" then
		local chunk = config.chunk or config.stackSize or config.minStack
		if chunk and chunk > 0 then entry.chunk = chunk end
	end
	local name, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
	if not icon or icon == 0 then
		local _, _, _, _, _, iconInstant = C_Item.GetItemInfoInstant(itemID)
		icon = iconInstant or icon
	end
	if name and name ~= "" then entry.name = name end
	if icon and icon ~= 0 then entry.icon = icon end
	if not entry.name then entry.name = ("item:%d"):format(itemID) end
	if (not name or name == "") and not entry.loading then
		entry.loading = true
		local itemObj = Item:CreateFromItemID(itemID)
		if itemObj and itemObj.ContinueOnItemLoad then
			itemObj:ContinueOnItemLoad(function()
				local data = ContainerActions.itemCache and ContainerActions.itemCache[itemID]
				if not data then return end
				local loadedName = select(1, C_Item.GetItemInfo(itemID)) or select(1, C_Item.GetItemInfoInstant(itemID))
				if loadedName and loadedName ~= "" then data.name = loadedName end
				data.loading = nil
			end)
		else
			entry.loading = nil
		end
	end
	return entry
end

function ContainerActions:IsItemEnabled(itemID)
	local disabled = addon.db and addon.db.containerAutoOpenDisabled
	return not (disabled and disabled[itemID])
end

function ContainerActions:GetManagedItemList()
	self:Init()
	local list = {}
	local source = addon.general and addon.general.variables and addon.general.variables.autoOpen or {}
	for itemID, config in pairs(source) do
		local overrides
		if type(config) == "table" then overrides = { chunk = config.chunk or config.minStack, meta = config } end
		local cache = self:RememberItemInfo(itemID, config, nil, overrides)
		table.insert(list, {
			itemID = itemID,
			name = cache.name or ("item:" .. itemID),
			chunk = cache.chunk,
			icon = cache.icon,
		})
	end
	table.sort(list, function(a, b)
		if a.name == b.name then return a.itemID < b.itemID end
		return a.name < b.name
	end)
	return list
end

function ContainerActions:OnItemToggle(itemID, enabled)
	self:Init()
	if addon.functions and addon.functions.checkForContainer then addon.functions.checkForContainer() end
end

function ContainerActions:ApplyButtonEntry(entry)
	self.currentEntry = entry
	local button = self:EnsureButton()
	if InCombat() then
		self.pendingItem = entry or false
		return
	end
	if entry then
		button.entry = entry
		SetButtonIconTexture(button, entry.icon or PREVIEW_ICON)
		button.itemLink = entry.link

		if not button.entry or button.entry.bag ~= entry.bag or button.entry.slot ~= entry.slot then
			local macroText = string.format("/use %d %d", entry.bag, entry.slot)

			button:SetAttribute("*type*", "macro") -- wirkt auf alle Maustasten
			button:SetAttribute("macrotext", macroText) -- eine Quelle reicht
			local macroText = ("/use %d %d"):format(entry.bag, entry.slot)
		end

		button:SetAttribute("item", nil) -- (Sicherheits-)Reset
	else
		button.entry = nil
		SetButtonIconTexture(button, nil)
		button.itemLink = nil
		button:SetAttribute("macrotext", nil)
		button:SetAttribute("macrotext1", nil)
		button:SetAttribute("macrotext2", nil)
		button:SetAttribute("type", nil)
		button:SetAttribute("type1", nil)
		button:SetAttribute("type2", nil)
		button:SetAttribute("*type*", nil)
		button:SetAttribute("item", nil)
	end
	self:UpdateCount()
end

function ContainerActions:RequestVisibility(show)
	self.desiredVisibility = show and true or false
	local button = self:EnsureButton()
	if self.previewActive then show = true end
	if InCombat() then
		self.pendingVisibility = show and true or false
		if not show and not self.previewActive then button:SetAlpha(0) end
		return
	end
	if show then
		if not self.previewActive then button:SetAlpha(1) end
		if not button:IsShown() then button:Show() end
	else
		if not self.previewActive then button:SetAlpha(0) end
		if button:IsShown() then button:Hide() end
	end
end

function ContainerActions:UpdateItems(list)
	self:Init()
	self.secureItems = list or {}
	table.sort(self.secureItems, SecureSort)
	if not self:IsEnabled() then
		self:ApplyButtonEntry(nil)
		self:RequestVisibility(false)
		return
	end
	if #self.secureItems == 0 then
		self:ApplyButtonEntry(nil)
		self:RequestVisibility(false)
	else
		self:ApplyButtonEntry(self.secureItems[1])
		self:RequestVisibility(true)
	end
end

function ContainerActions:IsTooltipOpenable(bag, slot)
	local tooltip = C_TooltipInfo.GetBagItem(bag, slot)
	if not tooltip or not tooltip.lines then return false end
	for _, line in ipairs(tooltip.lines) do
		if line and line.leftText then
			if line.leftText == ITEM_COSMETIC_LEARN or line.leftText == ITEM_OPENABLE then return true end
		end
	end
	return false
end

function ContainerActions:BuildEntry(bag, slot, info, overrides)
	overrides = overrides or {}
	self:RememberItemInfo(info.itemID, overrides.meta, info, overrides)
	return {
		bag = bag,
		slot = slot,
		itemID = info.itemID,
		icon = info.iconFileID,
		count = overrides.count or info.stackCount or 1,
		stackCount = info.stackCount or 1,
		chunk = overrides.chunk,
		meta = overrides.meta,
		link = C_Container.GetContainerItemLink(bag, slot),
	}
end

function ContainerActions:ScanBags()
	self:Init()
	local safeItems, secureItems = {}, {}
	if not self:IsEnabled() then return safeItems, secureItems end
	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		local slotCount = C_Container.GetContainerNumSlots(bag)
		if slotCount and slotCount > 0 then
			for slot = 1, slotCount do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if info and info.itemID and not info.isLocked then
					local autoConfig = addon.general and addon.general.variables and addon.general.variables.autoOpen and addon.general.variables.autoOpen[info.itemID]
					if autoConfig then
						self:RememberItemInfo(info.itemID, autoConfig, info)
						if self:IsItemEnabled(info.itemID) then
							if type(autoConfig) == "table" then
								local chunk = autoConfig.chunk or autoConfig.stackSize or autoConfig.minStack or 1
								local minStack = autoConfig.minStack or chunk
								local stack = info.stackCount or 1
								local uses = 0
								if stack >= (minStack or 1) and chunk and chunk > 0 then uses = math.floor(stack / chunk) end
								if uses > 0 then table.insert(secureItems, self:BuildEntry(bag, slot, info, { count = uses, chunk = chunk, meta = autoConfig })) end
							else
								table.insert(secureItems, self:BuildEntry(bag, slot, info))
							end
						end
					else
						if self:IsTooltipOpenable(bag, slot) then table.insert(safeItems, { bag = bag, slot = slot }) end
					end
				end
			end
		end
	end
	return safeItems, secureItems
end

function ContainerActions:OnSettingChanged(enabled)
	self:Init()
	if not enabled then
		self:HideAnchorPreview()
		self:UpdateItems({})
	else
		self:ApplyAnchorPosition()
		if addon.functions and addon.functions.checkForContainer then addon.functions.checkForContainer() end
	end
end

function ContainerActions:OnPostClick()
	if not self:IsEnabled() then return end
	if self.awaitingRefresh then return end
	self.awaitingRefresh = true
	C_Timer.After(0.5, function()
		ContainerActions.awaitingRefresh = nil
		if addon.functions and addon.functions.checkForContainer then addon.functions.checkForContainer() end
	end)
end
