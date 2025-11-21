local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local cContainer, cLayout = addon.functions.SettingsCreateCategory(nil, L["ContainerActions"], nil, "ContainerAction")
addon.SettingsLayout.containerActionCategory = cContainer
local wOpen = false -- Variable to ignore multiple checks for openItems
local function openItems(items)
	local function openNextItem()
		if #items == 0 then
			addon.functions.checkForContainer()
			return
		end

		if not MerchantFrame:IsShown() then
			local item = table.remove(items, 1)
			local iLoc = ItemLocation:CreateFromBagAndSlot(item.bag, item.slot)
			C_Timer.After(0.15, function()
				C_Container.UseContainerItem(item.bag, item.slot)
				C_Timer.After(0.4, openNextItem) -- 400ms Pause zwischen den boxen
			end)
		end
	end
	openNextItem()
end
function addon.functions.checkForContainer(bags)
	if not addon.db["automaticallyOpenContainer"] then
		if addon.ContainerActions and addon.ContainerActions.UpdateItems then addon.ContainerActions:UpdateItems({}) end
		wOpen = false
		return
	end

	local safeItems, secureItems = {}, {}
	if addon.ContainerActions and addon.ContainerActions.ScanBags then
		safeItems, secureItems = addon.ContainerActions:ScanBags(bags)
	end

	if addon.ContainerActions and addon.ContainerActions.UpdateItems then addon.ContainerActions:UpdateItems(secureItems, bags) end

	if #safeItems > 0 then
		openItems(safeItems)
	else
		wOpen = false
	end
end

local data = {

	var = "automaticallyOpenContainer",
	text = L["automaticallyOpenContainer"],
	func = function(value) addon.db["automaticallyOpenContainer"] = value and true or false end,
	desc = L["containerActionsFeatureDesc2"],
}

addon.functions.SettingsCreateText(cContainer, L["containerActionsFeatureDesc2"])
addon.functions.SettingsCreateCheckbox(cContainer, data)
addon.functions.SettingsCreateText(cContainer, L["containerActionsEditModeHint"] .. "\n" .. "|cff99e599" .. L["containerActionsBlacklistHint"] .. "|r")

data = {
	listFunc = function()
		if not addon.ContainerActions then return end
		local entries = addon.ContainerActions:GetBlacklistEntries()
		local list = {}
		list[""] = ""
		local entryFormat = L["containerActionsBlacklistEntry"] or "%s - %d"
		for _, data in ipairs(entries) do
			local displayName = data.name or ("item:" .. data.itemID)
			local ok, line = pcall(string.format, entryFormat, displayName, data.itemID)
			if not ok then line = ("%s - %d"):format(displayName, data.itemID) end
			local key = tostring(data.itemID)
			list[key] = line
		end
		return list
	end,
	text = L["containerActionsBlacklistLabel"],
	parentCheck = function() return addon.SettingsLayout.elements["automaticallyOpenContainer"].setting and addon.SettingsLayout.elements["automaticallyOpenContainer"].setting:GetValue() == true end,
	element = addon.SettingsLayout.elements["automaticallyOpenContainer"].element,
	get = function() return "" end,
	set = function(value)
		if not addon.ContainerActions then return end
		local itemID = tonumber(value)
		if not itemID then return end

		local dialogKey = "EQOL_CONTAINER_BLACKLIST_REMOVE"
		local itemName = addon.ContainerActions:GetItemDisplayName(itemID)

		StaticPopupDialogs[dialogKey] = StaticPopupDialogs[dialogKey]
			or {
				text = L["containerActionsBlacklistRemoveConfirm"],
				button1 = ACCEPT,
				button2 = CANCEL,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
			}

		StaticPopupDialogs[dialogKey].OnAccept = function()
			local ok, reason = addon.ContainerActions:RemoveItemFromBlacklist(itemID)
			if not ok then
				addon.ContainerActions:HandleBlacklistError(reason, itemID)
			end
		end

		StaticPopup_Show(dialogKey, itemName or ("item:" .. itemID), itemID)
	end,
	parent = true,
	default = "",
	var = "containerActionsBlacklistLabel",
}

addon.functions.SettingsCreateDropdown(cContainer, data)

local eventHandlers = {
	["BAG_UPDATE"] = function(bag)
		addon._bagsDirty = addon._bagsDirty or {}
		if type(bag) == "number" then addon._bagsDirty[bag] = true end
	end,
	["BAG_UPDATE_DELAYED"] = function()
		if addon.functions.clearTooltipCache then
			local now = GetTime()
			if not addon._ttCacheLastClear or (now - addon._ttCacheLastClear) > 0.25 then
				addon._ttCacheLastClear = now
				addon.functions.clearTooltipCache()
			end
		end

		if not addon.db["automaticallyOpenContainer"] then return end
		if wOpen or addon._bagScanScheduled then return end

		addon._bagScanScheduled = true
		C_Timer.After(0, function()
			addon._bagScanScheduled = nil
			if wOpen or not addon.db["automaticallyOpenContainer"] then return end

			wOpen = true

			local bags
			if addon._bagsDirty and next(addon._bagsDirty) then
				bags = {}
				for b in pairs(addon._bagsDirty) do
					if type(b) == "number" then table.insert(bags, b) end
				end
				addon._bagsDirty = nil
			end

			addon.functions.checkForContainer(bags)
		end)
	end,
}

function addon.functions.initContainerAction()
	addon.functions.InitDBValue("automaticallyOpenContainer", false)
	addon.functions.InitDBValue("containerActionAnchor", { point = "CENTER", relativePoint = "CENTER", x = 0, y = -200 })
	addon.functions.InitDBValue("containerAutoOpenDisabled", {})
	addon.functions.InitDBValue("containerActionAreaBlocks", {})

	if addon.ContainerActions and addon.ContainerActions.Init then
		addon.ContainerActions:Init()
		if addon.ContainerActions.OnSettingChanged then addon.ContainerActions:OnSettingChanged(addon.db["automaticallyOpenContainer"]) end
	end
end

local function registerEvents(frame)
	for event in pairs(eventHandlers) do
		frame:RegisterEvent(event)
	end
end

local function eventHandler(self, event, ...)
	if eventHandlers[event] then eventHandlers[event](...) end
end

local frameLoad = CreateFrame("Frame")

registerEvents(frameLoad)
frameLoad:SetScript("OnEvent", eventHandler)
