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

local EditMode = addon.EditMode
local EDITMODE_ID = "containerActionsButton"

local BUTTON_SIZE = 48
local PREVIEW_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local DEFAULT_ANCHOR = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -200 }

local ITEM_CLASS = Enum and Enum.ItemClass
local MISC_SUBCLASS = Enum and Enum.ItemMiscellaneousSubclass
local TOOLTIP_CLASS_FILTER = {}
local CCont = C_Container
local GetContainerNumSlots = CCont and CCont.GetContainerNumSlots
local GetContainerItemInfo = CCont and CCont.GetContainerItemInfo
local GetContainerItemLink = CCont and CCont.GetContainerItemLink
local CTooltip = C_TooltipInfo
local GetBagItemTooltip = CTooltip and CTooltip.GetBagItem

if ITEM_CLASS then
	if ITEM_CLASS.Consumable then TOOLTIP_CLASS_FILTER[ITEM_CLASS.Consumable] = true end
	if ITEM_CLASS.Container then TOOLTIP_CLASS_FILTER[ITEM_CLASS.Container] = true end
	if ITEM_CLASS.Miscellaneous then
		if MISC_SUBCLASS then
			local whitelist = {}
			if MISC_SUBCLASS.Other then whitelist[MISC_SUBCLASS.Other] = true end
			if MISC_SUBCLASS.Junk then whitelist[MISC_SUBCLASS.Junk] = true end
			if MISC_SUBCLASS.Holiday then whitelist[MISC_SUBCLASS.Holiday] = true end
			if MISC_SUBCLASS.Reagent then whitelist[MISC_SUBCLASS.Reagent] = true end
			if next(whitelist) then
				TOOLTIP_CLASS_FILTER[ITEM_CLASS.Miscellaneous] = whitelist
			else
				TOOLTIP_CLASS_FILTER[ITEM_CLASS.Miscellaneous] = true
			end
		else
			TOOLTIP_CLASS_FILTER[ITEM_CLASS.Miscellaneous] = true
		end
	end
end

local function InCombat() return InCombatLockdown and InCombatLockdown() end

local function CopyAnchorConfig(source)
	source = source or {}
	return {
		point = source.point or DEFAULT_ANCHOR.point,
		relativePoint = source.relativePoint or source.point or DEFAULT_ANCHOR.relativePoint,
		x = source.x ~= nil and source.x or DEFAULT_ANCHOR.x,
		y = source.y ~= nil and source.y or DEFAULT_ANCHOR.y,
	}
end

local function FormatAnchorPoint(data)
	data = data or {}
	data.point = data.point or DEFAULT_ANCHOR.point
	data.relativePoint = data.relativePoint or DEFAULT_ANCHOR.relativePoint
	if data.x == nil then data.x = DEFAULT_ANCHOR.x end
	if data.y == nil then data.y = DEFAULT_ANCHOR.y end
	return data
end

local function BuildAnchorLayoutSnapshot(layoutName)
	local layout = EditMode and EditMode:GetLayoutData(EDITMODE_ID, layoutName)
	if layout then return CopyAnchorConfig(layout) end
	addon.db.containerActionAnchor = FormatAnchorPoint(addon.db.containerActionAnchor)
	return CopyAnchorConfig(addon.db.containerActionAnchor)
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

local AREA_BLOCKS = {
	dungeon = { labelConst = "LFG_TYPE_DUNGEON", labelFallback = "Dungeons", types = { party = true } },
	raid = { labelConst = "LFG_TYPE_RAID", labelFallback = "Raids", types = { raid = true } },
	arena = { labelConst = "ARENA", labelFallback = "Arena", types = { arena = true } },
	battleground = { labelConst = "BATTLEFIELDS", labelFallback = "Battlegrounds", types = { pvp = true } },
	scenario = { labelConst = "SCENARIOS", labelFallback = "Scenarios", types = { scenario = true } },
	outdoor = { labelConst = "WORLD", labelFallback = "World", types = { none = true } },
}

local AREA_BLOCK_ORDER = { "dungeon", "raid", "arena", "battleground", "scenario", "outdoor" }

local function GetCurrentInstanceType()
	if not GetInstanceInfo then return "none" end
	local ok, _, instanceType = pcall(GetInstanceInfo)
	if not ok then return "none" end
	instanceType = instanceType or "none"
	if instanceType == "" then instanceType = "none" end
	return instanceType
end

function ContainerActions:IsEnabled()
	local enabled = addon.db and addon.db["automaticallyOpenContainer"]
	if not enabled then return false end
	if self.challengeModeActive == nil then self.challengeModeActive = self:IsChallengeModeActive() end
	return not self.challengeModeActive
end

local function GetAreaDisplayName(key)
	local def = AREA_BLOCKS[key]
	if not def then return key end
	if def.label then return def.label end
	if def.labelConst and _G and type(_G[def.labelConst]) == "string" and _G[def.labelConst] ~= "" then return _G[def.labelConst] end
	if def.labelFallback then return def.labelFallback end
	if def.labelKey and L and L[def.labelKey] then return L[def.labelKey] end
	return def.labelConst or def.labelKey or key
end

function ContainerActions:GetAnchorConfig(layoutName)
	local snapshot = BuildAnchorLayoutSnapshot(layoutName)
	return FormatAnchorPoint(snapshot)
end

function ContainerActions:GetLayoutAreaBlocks(layoutName)
	local targetLayout = layoutName or (EditMode and EditMode:GetActiveLayoutName()) or "_Global"
	addon.db.containerActionLayouts = addon.db.containerActionLayouts or {}
	local layoutData = addon.db.containerActionLayouts[targetLayout]
	if not layoutData then
		local copySource = addon.db.containerActionAreaBlocks
		layoutData = {
			areaBlocks = copySource and CopyTable(copySource) or {},
		}
		addon.db.containerActionLayouts[targetLayout] = layoutData
	end
	layoutData.areaBlocks = layoutData.areaBlocks or {}
	return layoutData.areaBlocks
end

function ContainerActions:SetAreaBlock(layoutName, key, enabled)
	layoutName = layoutName or (EditMode and EditMode:GetActiveLayoutName()) or "_Global"
	local areaBlocks = self:GetLayoutAreaBlocks(layoutName)
	if enabled then
		areaBlocks[key] = true
	else
		areaBlocks[key] = nil
	end
	addon.db.containerActionAreaBlocks = CopyTable(areaBlocks)
	self:OnAreaBlockSettingChanged()
end

function ContainerActions:ApplyAnchorLayout(data)
	local cfg = CopyAnchorConfig(data)
	addon.db.containerActionAnchor = CopyAnchorConfig(cfg)

	if InCombat() then
		self.pendingAnchorLayout = cfg
		return
	end

	self.pendingAnchorLayout = nil
	local anchor = self.anchor
	if anchor then
		anchor:ClearAllPoints()
		anchor:SetPoint(cfg.point, UIParent, cfg.relativePoint, cfg.x, cfg.y)
	end
	if self.button then
		self.button:ClearAllPoints()
		self.button:SetPoint("CENTER", self:EnsureAnchor(), "CENTER", 0, 0)
	end
end

function ContainerActions:EnsureAnchor()
	if self.anchor then return self.anchor end

	local anchor = CreateFrame("Frame", "EnhanceQoLContainerActionAnchor", UIParent, "BackdropTemplate")
	anchor:SetSize(BUTTON_SIZE + 12, BUTTON_SIZE + 12)
	anchor:SetFrameStrata("MEDIUM")
	anchor:SetClampedToScreen(true)
	anchor:EnableMouse(false)
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

	local label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("CENTER", 0, 0)
	label:SetText(L["containerActionsAnchorLabel"] or "Container Button")

	self.anchor = anchor
	self.anchorLabel = label

	if EditMode and EditMode.IsAvailable and EditMode:IsAvailable() and not self.anchorRegistered then
		local defaults = BuildAnchorLayoutSnapshot()
		local dropdownSetting
		local settingType = EditMode.lib and EditMode.lib.SettingType
		if settingType then
			dropdownSetting = {
				name = L["containerActionsAreaHeader"],
				kind = settingType.Dropdown,
				height = 180,
				default = {},
				set = function() end,
				generator = function(_, rootDescription)
					for _, areaKey in ipairs(AREA_BLOCK_ORDER) do
						local key = areaKey
						rootDescription:CreateCheckbox(GetAreaDisplayName(key), function()
							local layoutName = EditMode and EditMode:GetActiveLayoutName()
							local cfg = ContainerActions:GetLayoutAreaBlocks(layoutName)
							return not not cfg[key]
						end, function()
							local layoutName = EditMode and EditMode:GetActiveLayoutName()
							local cfg = ContainerActions:GetLayoutAreaBlocks(layoutName)
							local newState = not not cfg[key]
							ContainerActions:SetAreaBlock(layoutName, key, not newState)
						end)
					end
				end,
			}
		end

		EditMode:RegisterFrame(EDITMODE_ID, {
			frame = anchor,
			title = L["containerActionsAnchorLabel"] or "Container Button",
			layoutDefaults = defaults,
			isEnabled = function() return ContainerActions:IsEnabled() end,
			onApply = function(_, layoutName, data) ContainerActions:ApplyAnchorLayout(data) end,
			settings = dropdownSetting and { dropdownSetting } or nil,
		})
		self.anchorRegistered = true
	end
	self:ApplyAnchorLayout(BuildAnchorLayoutSnapshot())

	return anchor
end

function ContainerActions:EnsureButtonVisibilityWatcher()
	if self._buttonVisibilityWatcher then return end
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	watcher:SetScript("OnEvent", function(frame)
		if InCombatLockdown and InCombatLockdown() then return end
		frame:UnregisterAllEvents()
		frame:SetScript("OnEvent", nil)
		ContainerActions._buttonVisibilityWatcher = nil
		if ContainerActions._pendingButtonVisibilityDriver then
			ContainerActions:EnsureButtonVisibilityDriver()
		end
	end)
	self._buttonVisibilityWatcher = watcher
end

function ContainerActions:EnsureButtonVisibilityDriver()
	if not self.button or not RegisterStateDriver then return end
	if InCombatLockdown and InCombatLockdown() then
		self._pendingButtonVisibilityDriver = true
		self:EnsureButtonVisibilityWatcher()
		return
	end
	local ok = pcall(RegisterStateDriver, self.button, "visibility", "[combat] hide; show")
	if ok then self._pendingButtonVisibilityDriver = nil end
end

function ContainerActions:EnsureButton()
	if self.button then return self.button end

	local button = CreateFrame("Button", "EnhanceQoLContainerActionButton", UIParent, "ActionButtonTemplate,SecureActionButtonTemplate")
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
	button:SetAttribute("pressAndHoldAction", false) -- verhindert Wiederholen beim Halten
	button:SetAttribute("*type*", nil)
	SetButtonIconTexCoord(button, 0.08, 0.92, 0.08, 0.92)
	if button.HotKey then button.HotKey:SetText("") end
	if button.Name then button.Name:Hide() end
	button:SetPoint("CENTER", self:EnsureAnchor(), "CENTER")
	button:Hide()

	button:SetScript("OnEnter", function(btn)
		if EditMode and EditMode:IsInEditMode() then
			GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
			GameTooltip:SetText(L["containerActionsAnchorHelp"] or "")
			GameTooltip:Show()
			return
		end
		if not ContainerActions:IsEnabled() or not btn:IsMouseEnabled() or btn:IsForbidden() then return end
		if btn.entry then
			GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
			GameTooltip:SetBagItem(btn.entry.bag, btn.entry.slot)
			local extra = L["containerActionsButtonTooltip"]
			if extra and extra ~= "" then GameTooltip:AddLine(extra, 0.9, 0.9, 0.9, true) end
			local hint = L["containerActionsBanTooltip"]
			if hint and hint ~= "" then GameTooltip:AddLine(hint, 0.4, 0.8, 0.4, true) end
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
	button:SetScript("OnMouseUp", function(_, mouseButton)
		if mouseButton == "RightButton" and IsShiftKeyDown() then ContainerActions:TryBlacklistCurrentEntry() end
	end)

	self.button = button
	self.buttonIcon = GetButtonIcon(button)
	self:EnsureButtonVisibilityDriver()

	self:ApplyAnchorLayout(BuildAnchorLayoutSnapshot())
	return button
end

function ContainerActions:Init()
	if self.initialized then return end
	self.initialized = true
	self.itemCache = self.itemCache or {}
	self.secureItems = {}
	self.openableCache = self.openableCache or {}
	self.mountCache = self.mountCache or {}
	self.visibilityBlocks = self.visibilityBlocks or {}
	self._safe = self._safe or {}
	self._secure = self._secure or {}
	self.pendingItem = nil
	self.pendingAnchorLayout = nil
	self.pendingVisibility = nil
	self.awaitingRefresh = nil
	self.desiredVisibility = nil
	self:EnsureAnchor()
	self:EnsureButton()

	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	frame:RegisterEvent("UNIT_ENTERED_VEHICLE")
	frame:RegisterEvent("UNIT_EXITED_VEHICLE")
	frame:RegisterEvent("CHALLENGE_MODE_START")
	frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
	frame:RegisterEvent("ZONE_CHANGED")
	frame:RegisterEvent("ZONE_CHANGED_INDOORS")
	frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:SetScript("OnEvent", function(_, event, ...)
		if event == "PLAYER_REGEN_DISABLED" then
			ContainerActions:OnCombatStart()
		elseif event == "PLAYER_REGEN_ENABLED" then
			ContainerActions:OnCombatEnd()
		elseif event == "UNIT_ENTERED_VEHICLE" then
			ContainerActions:OnUnitEnteredVehicle(...)
		elseif event == "UNIT_EXITED_VEHICLE" then
			ContainerActions:OnUnitExitedVehicle(...)
		elseif event == "CHALLENGE_MODE_START" then
			ContainerActions:OnChallengeModeStart()
		elseif event == "CHALLENGE_MODE_COMPLETED" then
			ContainerActions:OnChallengeModeCompleted()
		elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
			ContainerActions:UpdateVehicleState()
			ContainerActions:UpdateChallengeModeState()
			ContainerActions:UpdateAreaBlocks()
		elseif event == "PLAYER_ENTERING_WORLD" then
			ContainerActions:UpdateVehicleState()
			ContainerActions:UpdateChallengeModeState()
			ContainerActions:UpdateAreaBlocks()
		end
	end)
	self.eventFrame = frame
	self:UpdateVehicleState()
	self:UpdateChallengeModeState()
	self:UpdateAreaBlocks()
end

function ContainerActions:OnCombatStart() end

function ContainerActions:OnCombatEnd()
	if self.pendingAnchorLayout then
		local pending = self.pendingAnchorLayout
		self.pendingAnchorLayout = nil
		self:ApplyAnchorLayout(pending)
	end
	if self.pendingVisibility ~= nil then
		local desired = self.pendingVisibility
		self.pendingVisibility = nil
		self:RequestVisibility(desired, true)
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
	if self.pendingVisibility == nil and self.desiredVisibility ~= nil then self:RequestVisibility(self.desiredVisibility) end
	self:FlushDeferredEditRefresh()
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
	local total = self:GetTotalItemCount()
	if not self.button.Count then return end
	if total > 1 then
		self.button.Count:SetText(total)
	else
		self.button.Count:SetText("")
	end
end

function ContainerActions:RememberItemInfo(itemID, config, info, overrides, noLookup)
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
	if not noLookup then
		local name, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
		if not icon or icon == 0 then
			local _, _, _, _, _, iconInstant = C_Item.GetItemInfoInstant(itemID)
			icon = iconInstant or icon
		end
		if name and name ~= "" then entry.name = name end
		if icon and icon ~= 0 then entry.icon = icon end
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
	end
	if not entry.name then entry.name = ("item:%d"):format(itemID) end
	return entry
end

function ContainerActions:IsItemEnabled(itemID) return not self:IsItemBlacklisted(itemID) end

function ContainerActions:IsItemBlacklisted(itemID)
	local disabled = addon.db and addon.db.containerAutoOpenDisabled
	return disabled and disabled[itemID] and true or false
end

function ContainerActions:EnsureBlacklistTable()
	addon.db.containerAutoOpenDisabled = addon.db.containerAutoOpenDisabled or {}
	return addon.db.containerAutoOpenDisabled
end

function ContainerActions:GetItemDisplayName(itemID)
	if not itemID then return ("item:%s"):format(tostring(itemID or "?")) end
	local cache = self.itemCache and self.itemCache[itemID]
	if cache and cache.name then return cache.name end
	local name = C_Item.GetItemInfo(itemID)
	if not name or name == "" then
		local instantName = select(1, C_Item.GetItemInfoInstant(itemID))
		if instantName and instantName ~= "" then name = instantName end
	end
	if name and name ~= "" then return name end
	local entry = self:RememberItemInfo(itemID)
	if entry and entry.name then return entry.name end
	return ("item:%d"):format(itemID)
end

local function PrintMessage(message)
	if not message or message == "" then return end
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99EnhanceQoL|r: " .. message)
	else
		print("|cff33ff99EnhanceQoL|r: " .. message)
	end
end

function ContainerActions:AddItemToBlacklist(itemID, quiet)
	itemID = tonumber(itemID)
	if not itemID then return false, "invalid" end
	if InCombat() then return false, "combat" end
	local tbl = self:EnsureBlacklistTable()
	if tbl[itemID] then return false, "exists" end
	tbl[itemID] = true
	self:RememberItemInfo(itemID)
	if not quiet then
		local msg = L["containerActionsBlacklistAdded"]
		if msg and msg ~= "" then
			PrintMessage(msg:format(self:GetItemDisplayName(itemID), itemID))
		else
			PrintMessage(("Blocked %s (%d)."):format(self:GetItemDisplayName(itemID), itemID))
		end
	end
	self:OnBlacklistChanged()
	return true
end

function ContainerActions:RemoveItemFromBlacklist(itemID, quiet)
	itemID = tonumber(itemID)
	if not itemID then return false, "invalid" end
	if InCombat() then return false, "combat" end
	local tbl = addon.db and addon.db.containerAutoOpenDisabled
	if not tbl or not tbl[itemID] then return false, "missing" end
	tbl[itemID] = nil
	if not quiet then
		local msg = L["containerActionsBlacklistRemoved"]
		if msg and msg ~= "" then
			PrintMessage(msg:format(self:GetItemDisplayName(itemID), itemID))
		else
			PrintMessage(("Unblocked %s (%d)."):format(self:GetItemDisplayName(itemID), itemID))
		end
	end
	self:OnBlacklistChanged()
	return true
end

function ContainerActions:OnBlacklistChanged()
	if addon.functions and addon.functions.checkForContainer then addon.functions.checkForContainer() end
end

function ContainerActions:HandleBlacklistError(reason, itemID)
	local msg
	if reason == "combat" then
		msg = L["containerActionsBlacklistCombat"]
	elseif reason == "exists" then
		msg = L["containerActionsBlacklistExists"]
	elseif reason == "invalid" then
		msg = L["containerActionsBlacklistInvalid"]
	elseif reason == "missing" then
		msg = L["containerActionsBlacklistMissing"]
	end
	if msg and msg ~= "" then
		if itemID and msg:find("%%") then
			PrintMessage(msg:format(self:GetItemDisplayName(itemID), itemID))
		else
			PrintMessage(msg)
		end
	elseif reason then
		PrintMessage(("Blacklist operation failed (%s)."):format(reason))
	end
end

function ContainerActions:ParseInputToItemID(input)
	if type(input) == "number" then return input end
	if type(input) == "table" and input.itemID then return tonumber(input.itemID) end
	if type(input) ~= "string" then return nil end
	local trimmed = input:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed == "" then return nil end
	local linkID = trimmed:match("item:(%d+)")
	if linkID then return tonumber(linkID) end
	local directID = trimmed:match("^(%d+)$")
	if directID then return tonumber(directID) end
	return nil
end

function ContainerActions:GetBlacklistEntries()
	local entries = {}
	local tbl = addon.db and addon.db.containerAutoOpenDisabled
	if not tbl then return entries end
	for itemID in pairs(tbl) do
		local cache = self:RememberItemInfo(itemID)
		entries[#entries + 1] = {
			itemID = itemID,
			name = cache and cache.name or self:GetItemDisplayName(itemID),
			icon = cache and cache.icon,
		}
	end
	table.sort(entries, function(a, b)
		if a.name == b.name then return a.itemID < b.itemID end
		return a.name < b.name
	end)
	return entries
end

function ContainerActions:TryBlacklistCurrentEntry()
	if EditMode and EditMode:IsInEditMode() then return end
	local entry = self.currentEntry
	if not entry or not entry.itemID then return end
	local ok, reason = self:AddItemToBlacklist(entry.itemID)
	if not ok then self:HandleBlacklistError(reason, entry.itemID) end
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

function ContainerActions:GetAreaBlockOptions()
	local list = {}
	for _, key in ipairs(AREA_BLOCK_ORDER) do
		local def = AREA_BLOCKS[key]
		if def then
			local text
			if def.label then
				text = def.label
			elseif def.labelConst and _G and type(_G[def.labelConst]) == "string" and _G[def.labelConst] ~= "" then
				text = _G[def.labelConst]
			elseif def.labelFallback then
				text = def.labelFallback
			elseif def.labelKey and L then
				text = L[def.labelKey]
			else
				text = def.labelConst or def.labelKey or key
			end
			list[#list + 1] = { key = key, label = text }
		end
	end
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
		local prev = button.entry
		local changed = (not prev) or (prev.bag ~= entry.bag) or (prev.slot ~= entry.slot)

		button.entry = entry
		SetButtonIconTexture(button, entry.icon or PREVIEW_ICON)

		if changed then
			if GetContainerItemLink then
				button.itemLink = GetContainerItemLink(entry.bag, entry.slot)
			else
				button.itemLink = nil
			end
			local macroText = ("/use %d %d"):format(entry.bag, entry.slot)
			button:SetAttribute("*type*", "macro")
			button:SetAttribute("macrotext", macroText)
			button:SetAttribute("item", nil) -- Sicherheitsreset
		end
	else
		button.entry = nil
		SetButtonIconTexture(button, nil)
		button.itemLink = nil
		button:SetAttribute("macrotext", nil)
		button:SetAttribute("*type*", nil)
		button:SetAttribute("item", nil)
	end
	self:UpdateCount()
end

function ContainerActions:HasVisibilityBlock() return self.visibilityBlocks and next(self.visibilityBlocks) ~= nil end

function ContainerActions:SetVisibilityBlock(reason, blocked)
	if not reason then return end
	self.visibilityBlocks = self.visibilityBlocks or {}
	local shouldBlock = blocked and true or false
	if shouldBlock then
		if self.visibilityBlocks[reason] then return end
		self.visibilityBlocks[reason] = true
		self:RequestVisibility(false, true)
	else
		if not self.visibilityBlocks[reason] then return end
		self.visibilityBlocks[reason] = nil
		if self:HasVisibilityBlock() then
			self:RequestVisibility(false, true)
		else
			local shouldShow = self.desiredVisibility
			if shouldShow == nil then
				local hasItems = type(self.secureItems) == "table" and #self.secureItems > 0
				shouldShow = self:IsEnabled() and hasItems
			end
			shouldShow = shouldShow and true or false
			self:RequestVisibility(shouldShow, true)
		end
	end
end

function ContainerActions:RequestVisibility(show, skipDesiredUpdate)
	self.visibilityBlocks = self.visibilityBlocks or {}
	if not skipDesiredUpdate then self.desiredVisibility = show and true or false end
	local button = self:EnsureButton()
	local desired = show and true or false
	if self:HasVisibilityBlock() then desired = false end
	button:SetAlpha(desired and 1 or 0)
	if InCombat() then
		self.pendingVisibility = desired
		return
	end
	if desired then
		if not button:IsShown() then button:Show() end
		if not button:IsMouseEnabled() then button:EnableMouse(true) end
	else
		if button:IsShown() then button:Hide() end
		if button:IsMouseEnabled() then button:EnableMouse(false) end
	end
end

function ContainerActions:UpdateItems(list, dirtyBags)
	self:Init()

	local source = type(list) == "table" and list or {}
	local secureItems = self.secureItems
	if type(secureItems) ~= "table" then
		secureItems = {}
		self.secureItems = secureItems
	end

	local dirtySet
	if type(dirtyBags) == "table" then
		local hasDirty = false
		dirtySet = self._dirtyBagSet or {}
		self._dirtyBagSet = dirtySet
		if next(dirtySet) then wipe(dirtySet) end
		for _, bag in ipairs(dirtyBags) do
			if type(bag) == "number" then
				dirtySet[bag] = true
				hasDirty = true
			end
		end
		if not hasDirty then
			for bag, flag in pairs(dirtyBags) do
				if flag and type(bag) == "number" and not dirtySet[bag] then
					dirtySet[bag] = true
					hasDirty = true
				end
			end
		end
		if not hasDirty then dirtySet = nil end
	end

	if dirtySet then
		local write = 1
		for read = 1, #secureItems do
			local entry = secureItems[read]
			if entry and not dirtySet[entry.bag] then
				secureItems[write] = entry
				write = write + 1
			end
		end
		for i = write, #secureItems do
			secureItems[i] = nil
		end
		for i = 1, #source do
			secureItems[#secureItems + 1] = source[i]
		end
	else
		if #secureItems > 0 then wipe(secureItems) end
		for i = 1, #source do
			secureItems[i] = source[i]
		end
	end

	if #secureItems > 1 then table.sort(secureItems, SecureSort) end
	if not self:IsEnabled() then
		self:ApplyButtonEntry(nil)
		self:RequestVisibility(false)
		return
	end
	if #secureItems == 0 then
		self:ApplyButtonEntry(nil)
		self:RequestVisibility(false)
	else
		self:ApplyButtonEntry(secureItems[1])
		self:RequestVisibility(true)
	end
end

function ContainerActions:UpdateAreaBlocks()
	local layoutName = EditMode and EditMode:GetActiveLayoutName()
	local config
	if layoutName then
		config = self:GetLayoutAreaBlocks(layoutName)
	else
		config = addon.db and addon.db.containerActionAreaBlocks or {}
	end
	local instanceType = GetCurrentInstanceType()
	for _, key in ipairs(AREA_BLOCK_ORDER) do
		local def = AREA_BLOCKS[key]
		if def then
			local reason = "area:" .. key
			local matches = def.types and def.types[instanceType]
			local shouldBlock = matches and config[key]
			self:SetVisibilityBlock(reason, shouldBlock and true or false)
		end
	end
end

function ContainerActions:OnAreaBlockSettingChanged()
	self:UpdateAreaBlocks()
	if EditMode and EditMode.RefreshFrame then
		if InCombatLockdown and InCombatLockdown() then
			self.deferEditModeRefresh = true
		else
			EditMode:RefreshFrame(EDITMODE_ID)
		end
	end
end

function ContainerActions:FlushDeferredEditRefresh()
	if self.deferEditModeRefresh and EditMode and EditMode.RefreshFrame then
		self.deferEditModeRefresh = nil
		EditMode:RefreshFrame(EDITMODE_ID)
	end
end

function ContainerActions:OnUnitEnteredVehicle(unit)
	if unit ~= "player" then return end
	self:SetVisibilityBlock("vehicle", true)
end

function ContainerActions:OnUnitExitedVehicle(unit)
	if unit ~= "player" then return end
	self:SetVisibilityBlock("vehicle", false)
end

function ContainerActions:UpdateVehicleState()
	local inVehicle = false
	if UnitHasVehicleUI then
		inVehicle = UnitHasVehicleUI("player") == true
	elseif UnitInVehicle then
		inVehicle = UnitInVehicle("player") == true
	end
	self:SetVisibilityBlock("vehicle", inVehicle)
end

function ContainerActions:SetChallengeModeActive(active)
	active = active and true or false
	local previous = self.challengeModeActive
	if previous == active then
		self:SetVisibilityBlock("challengeMode", active)
		return
	end

	self.challengeModeActive = active
	if active then self:ApplyButtonEntry(nil) end
	self:SetVisibilityBlock("challengeMode", active)

	if previous ~= nil and addon.functions and addon.functions.checkForContainer then addon.functions.checkForContainer() end
end

function ContainerActions:OnChallengeModeStart()
	self:SetChallengeModeActive(true)
	self:UpdateAreaBlocks()
end

function ContainerActions:OnChallengeModeCompleted()
	-- falls der Abschluss noch als aktiv markiert ist, korrigiert UpdateChallengeModeState dies
	self:SetChallengeModeActive(false)
	self:UpdateChallengeModeState()
	self:UpdateAreaBlocks()
end

function ContainerActions:IsChallengeModeActive()
	if not C_ChallengeMode or not C_ChallengeMode.IsChallengeModeActive then return false end
	local active = C_ChallengeMode.IsChallengeModeActive()
	return active == true
end

function ContainerActions:UpdateChallengeModeState() self:SetChallengeModeActive(self:IsChallengeModeActive()) end

function ContainerActions:ShouldInspectTooltip(itemID)
	if not itemID then return false end
	if not ITEM_CLASS then return true end

	local classID, subclassID, _
	if C_Item and C_Item.GetItemInfoInstant then
		_, _, _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	end
	if (not classID or not subclassID) and GetItemInfoInstant then
		_, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)
	end

	if not classID then return true end

	local rule = TOOLTIP_CLASS_FILTER[classID]
	if not rule then return false end
	if rule == true then return true end
	if type(rule) == "table" then
		if not next(rule) then return true end
		if not subclassID then return true end
		return rule[subclassID] == true
	end
	return false
end

function ContainerActions:IsTooltipOpenable(bag, slot, info)
	info = info or (GetContainerItemInfo and GetContainerItemInfo(bag, slot))
	if not info or not info.itemID then return false end

	local itemID = info.itemID
	if self.openableCache[itemID] ~= nil then return self.openableCache[itemID] end
	if not self:ShouldInspectTooltip(itemID) then return false end
	if self._tooltipScanBudget and self._tooltipScanBudget <= 0 then return false end
	if self._tooltipScanBudget then self._tooltipScanBudget = self._tooltipScanBudget - 1 end

	local tooltip = GetBagItemTooltip and GetBagItemTooltip(bag, slot)
	if not tooltip or not tooltip.lines then return false end
	for _, line in ipairs(tooltip.lines) do
		if line and line.leftText then
			if line.leftText == ITEM_COSMETIC_LEARN or line.leftText == ITEM_OPENABLE then
				self.openableCache[itemID] = true
				return true
			end
		end
	end
	self.openableCache[itemID] = false
	return false
end

function ContainerActions:IsCollectibleMount(info)
	if not info or not info.itemID then return false end
	if not C_MountJournal or not C_MountJournal.GetMountFromItem then return false end

	local itemID = info.itemID
	local classID, subclassID
	if C_Item and C_Item.GetItemInfoInstant then
		local _, _, _, _, _, classValue, subclassValue = C_Item.GetItemInfoInstant(itemID)
		classID, subclassID = classValue, subclassValue
	elseif GetItemInfoInstant then
		local _, _, _, _, _, _, _, _, _, _, _, classValue, subclassValue = GetItemInfoInstant(itemID)
		classID, subclassID = classValue, subclassValue
	end
	local miscClassID = (ITEM_CLASS and ITEM_CLASS.Miscellaneous) or (type(LE_ITEM_CLASS_MISCELLANEOUS) == "number" and LE_ITEM_CLASS_MISCELLANEOUS) or nil
	local mountSubclassID = (MISC_SUBCLASS and MISC_SUBCLASS.Mount) or (type(LE_ITEM_MISCELLANEOUS_MOUNT) == "number" and LE_ITEM_MISCELLANEOUS_MOUNT) or nil
	if classID and subclassID and miscClassID and mountSubclassID then
		if classID ~= miscClassID or subclassID ~= mountSubclassID then
			if self.mountCache then self.mountCache[itemID] = false end
			return false
		end
	end

	local cache = self.mountCache and self.mountCache[itemID]
	local mountID = cache ~= nil and cache or nil
	if cache == false then return false end
	if not mountID then
		mountID = C_MountJournal.GetMountFromItem(itemID)
		if not mountID then
			if self.mountCache then self.mountCache[itemID] = false end
			return false
		end
		if self.mountCache then self.mountCache[itemID] = mountID end
	end

	local hasMount = false
	if C_MountJournal.PlayerHasMount then
		hasMount = C_MountJournal.PlayerHasMount(mountID) == true
	elseif C_MountJournal.GetMountInfoByID then
		local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
		hasMount = isCollected == true
	end

	if hasMount then return false end
	return true, mountID
end

function ContainerActions:BuildEntry(bag, slot, info, overrides)
	overrides = overrides or {}
	self:RememberItemInfo(info.itemID, overrides.meta, info, overrides, true)
	return {
		bag = bag,
		slot = slot,
		itemID = info.itemID,
		icon = info.iconFileID,
		count = overrides.count or info.stackCount or 1,
		stackCount = info.stackCount or 1,
		chunk = overrides.chunk,
		meta = overrides.meta,
	}
end

function ContainerActions:ScanBags(bags)
	self:Init()
	self._tooltipScanBudget = (addon.db and addon.db.containerActionTooltipBudget) or 4
	local scanOpenables = (addon.db and addon.db.containerActionScanOpenables) ~= false
	local safeItems, secureItems = self._safe, self._secure
	if #safeItems > 0 then wipe(safeItems) end
	if #secureItems > 0 then wipe(secureItems) end
	if not self:IsEnabled() then return safeItems, secureItems end
	local function ScanBag(bag)
		local slotCount = GetContainerNumSlots and GetContainerNumSlots(bag)
		if slotCount and slotCount > 0 then
			for slot = 1, slotCount do
				local info = GetContainerItemInfo and GetContainerItemInfo(bag, slot)
				if info and info.itemID and not info.isLocked then
					local autoConfig = addon.general and addon.general.variables and addon.general.variables.autoOpen and addon.general.variables.autoOpen[info.itemID]
					local isBlacklisted = self:IsItemBlacklisted(info.itemID)
					if isBlacklisted then
						self:RememberItemInfo(info.itemID, nil, info, nil, true)
					elseif autoConfig then
						self:RememberItemInfo(info.itemID, autoConfig, info, nil, true)
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
						local isCollectibleMount, mountID = self:IsCollectibleMount(info)
						if isCollectibleMount then
							local overrides = { meta = { type = "mount", mountID = mountID } }
							table.insert(secureItems, self:BuildEntry(bag, slot, info, overrides))
						elseif scanOpenables and self:IsTooltipOpenable(bag, slot, info) then
							safeItems[#safeItems + 1] = { bag = bag, slot = slot }
						end
					end
				end
			end
		end
	end
	local processedBags = {}
	local usedSpecificBags = false
	if type(bags) == "table" then
		for _, bag in ipairs(bags) do
			if type(bag) == "number" and not processedBags[bag] then
				processedBags[bag] = true
				ScanBag(bag)
				usedSpecificBags = true
			end
		end
	end
	if not usedSpecificBags then
		for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
			ScanBag(bag)
		end
	end
	return safeItems, secureItems
end

function ContainerActions:OnSettingChanged(enabled)
	self:Init()
	if not enabled then
		self:UpdateItems({})
	else
		self:ApplyAnchorLayout(BuildAnchorLayoutSnapshot())
		self:UpdateAreaBlocks()
		if addon.functions and addon.functions.checkForContainer then addon.functions.checkForContainer() end
	end
	if EditMode and EditMode.RefreshFrame then EditMode:RefreshFrame(EDITMODE_ID) end
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
