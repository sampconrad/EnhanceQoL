local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local cVendorEconomy = addon.functions.SettingsCreateCategory(nil, L["VendorsEconomy"], nil, "VendorsEconomy")
addon.SettingsLayout.vendorEconomyCategory = cVendorEconomy

addon.functions.SettingsCreateHeadline(cVendorEconomy, BUTTON_LAG_AUCTIONHOUSE)

local data = {
	{
		text = L["persistAuctionHouseFilter"],
		var = "persistAuctionHouseFilter",
		func = function(value) addon.db["persistAuctionHouseFilter"] = value end,
	},
	{
		text = (function()
			local label = _G["AUCTION_HOUSE_FILTER_CURRENTEXPANSION_ONLY"]
			return L["alwaysUserCurExpAuctionHouse"]:format(label)
		end)(),
		var = "alwaysUserCurExpAuctionHouse",
		func = function(value) addon.db["alwaysUserCurExpAuctionHouse"] = value end,
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cVendorEconomy, data)

addon.functions.SettingsCreateHeadline(cVendorEconomy, L["Convenience"])

data = {
	{
		var = "autoRepair",
		text = L["autoRepair"],
		func = function(v) addon.db["autoRepair"] = v end,
		desc = L["autoRepairDesc"],
		children = {
			{

				var = "autoRepairGuildBank",
				text = L["autoRepairGuildBank"],
				func = function(v) addon.db["autoRepairGuildBank"] = v end,
				desc = L["autoRepairGuildBankDesc"],
				parentCheck = function()
					return addon.SettingsLayout.elements["autoRepair"]
						and addon.SettingsLayout.elements["autoRepair"].setting
						and addon.SettingsLayout.elements["autoRepair"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
			},
		},
	},
	{
		var = "sellAllJunk",
		text = L["sellAllJunk"],
		func = function(v)
			addon.db["sellAllJunk"] = v
			if v then addon.functions.checkBagIgnoreJunk() end
		end,
		desc = L["sellAllJunkDesc"],
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cVendorEconomy, data)

addon.functions.SettingsCreateHeadline(cVendorEconomy, MERCHANT)

data = {
	{
		var = "enableExtendedMerchant",
		text = L["enableExtendedMerchant"],
		func = function(v)
			addon.db["enableExtendedMerchant"] = v
			if addon.Merchant then
				if v and addon.Merchant.Enable then
					addon.Merchant:Enable()
				elseif not v and addon.Merchant.Disable then
					addon.Merchant:Disable()
					addon.variables.requireReload = true
					addon.functions.checkReloadFrame()
				end
			end
		end,
		desc = L["enableExtendedMerchantDesc"],
	},
	{
		var = "markKnownOnMerchant",
		text = L["markKnownOnMerchant"],
		func = function(v)
			addon.db["markKnownOnMerchant"] = v
			if MerchantFrame and MerchantFrame:IsShown() then
				if MerchantFrame.selectedTab == 2 then
					if MerchantFrame_UpdateBuybackInfo then MerchantFrame_UpdateBuybackInfo() end
				else
					if MerchantFrame_UpdateMerchantInfo then MerchantFrame_UpdateMerchantInfo() end
				end
			end
		end,
		desc = L["markKnownOnMerchantDesc"],
	},
	{
		var = "markCollectedPetsOnMerchant",
		text = L["markCollectedPetsOnMerchant"],
		func = function(v)
			addon.db["markCollectedPetsOnMerchant"] = v
			if MerchantFrame and MerchantFrame:IsShown() then
				if MerchantFrame.selectedTab == 2 then
					if MerchantFrame_UpdateBuybackInfo then MerchantFrame_UpdateBuybackInfo() end
				else
					if MerchantFrame_UpdateMerchantInfo then MerchantFrame_UpdateMerchantInfo() end
				end
			end
		end,
		desc = L["markCollectedPetsOnMerchantDesc"],
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cVendorEconomy, data)

addon.functions.SettingsCreateHeadline(cVendorEconomy, MINIMAP_TRACKING_MAILBOX)

data = {
	{
		var = "enableMailboxAddressBook",
		text = L["enableMailboxAddressBook"],
		func = function(v)
			addon.db["enableMailboxAddressBook"] = v
			if addon.Mailbox then
				if addon.Mailbox.SetEnabled then addon.Mailbox:SetEnabled(v) end
				if v and addon.Mailbox.AddSelfToContacts then addon.Mailbox:AddSelfToContacts() end
				if v and addon.Mailbox.RefreshList then addon.Mailbox:RefreshList() end
			end
		end,
		desc = L["enableMailboxAddressBookDesc"],
		children = {
			{
				listFunc = function()
					local contacts = addon.db["mailboxContacts"] or {}
					local entries, order = {}, { "" }
					local tList = { [""] = "" }

					for key, rec in pairs(contacts) do
						local class = rec and rec.class
						local col = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class or ""] or { r = 1, g = 1, b = 1 }
						local label = string.format("|cff%02x%02x%02x%s|r", (col.r or 1) * 255, (col.g or 1) * 255, (col.b or 1) * 255, key)
						local rawSort = (rec and rec.name) or key or ""
						entries[#entries + 1] = { key = key, label = label, sortKey = rawSort:lower() }
					end

					table.sort(entries, function(a, b)
						if a.sortKey == b.sortKey then return a.key < b.key end
						return a.sortKey < b.sortKey
					end)

					for _, entry in ipairs(entries) do
						tList[entry.key] = entry.label
						order[#order + 1] = entry.key
					end
					tList._order = order
					return tList
				end,
				text = L["mailboxRemoveHeader"],
				get = function() return "" end,
				set = function(key)
					if not key or key == "" then return end
					if not addon.db or not addon.db["mailboxContacts"] or not addon.db["mailboxContacts"][key] then return end

					local dialogKey = "EQOL_MAILBOX_CONTACT_REMOVE"
					StaticPopupDialogs[dialogKey] = StaticPopupDialogs[dialogKey]
						or {
							text = L["mailboxRemoveConfirm"],
							button1 = ACCEPT,
							button2 = CANCEL,
							timeout = 0,
							whileDead = true,
							hideOnEscape = true,
							preferredIndex = 3,
						}

					StaticPopupDialogs[dialogKey].OnAccept = function(_, contactKey)
						if not contactKey or not addon.db or not addon.db["mailboxContacts"] then return end
						addon.db["mailboxContacts"][contactKey] = nil
						if addon.Mailbox and addon.Mailbox.RefreshList then addon.Mailbox:RefreshList() end
					end

					StaticPopup_Show(dialogKey, key, nil, key)
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["enableMailboxAddressBook"]
						and addon.SettingsLayout.elements["enableMailboxAddressBook"].setting
						and addon.SettingsLayout.elements["enableMailboxAddressBook"].setting:GetValue() == true
				end,
				parent = true,
				default = "",
				var = "mailboxContacts",
				type = Settings.VarType.String,
				sType = "dropdown",
			},
		},
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cVendorEconomy, data)

addon.functions.SettingsCreateHeadline(cVendorEconomy, MONEY)

data = {
	{
		var = "enableMoneyTracker",
		text = L["enableMoneyTracker"],
		func = function(v) addon.db["enableMoneyTracker"] = v end,
		desc = L["enableMoneyTrackerDesc"],
		children = {
			{

				var = "showOnlyGoldOnMoney",
				text = L["showOnlyGoldOnMoney"],
				func = function(v) addon.db["showOnlyGoldOnMoney"] = v end,
				parentCheck = function()
					return addon.SettingsLayout.elements["enableMoneyTracker"]
						and addon.SettingsLayout.elements["enableMoneyTracker"].setting
						and addon.SettingsLayout.elements["enableMoneyTracker"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
			},
			{
				listFunc = function()
					local tracker = addon.db["moneyTracker"] or {}
					local entries, order = {}, { "" }
					local tList = { [""] = "" }

					for guid, v in pairs(tracker) do
						if guid ~= UnitGUID("player") then
							local col = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[v.class] or { r = 1, g = 1, b = 1 }
							local displayName = string.format("|cff%02x%02x%02x%s-%s|r", (col.r or 1) * 255, (col.g or 1) * 255, (col.b or 1) * 255, v.name or "?", v.realm or "?")
							local rawSort = string.format("%s-%s", v.name or "", v.realm or ""):lower()
							entries[#entries + 1] = { key = guid, label = displayName, sortKey = rawSort }
						end
					end

					table.sort(entries, function(a, b)
						if a.sortKey == b.sortKey then return a.key < b.key end
						return a.sortKey < b.sortKey
					end)

					for _, entry in ipairs(entries) do
						tList[entry.key] = entry.label
						order[#order + 1] = entry.key
					end
					tList._order = order
					return tList
				end,
				text = L["mailboxRemoveHeader"],
				get = function() return "" end,
				set = function(key)
					if not key or key == "" then return end
					if not addon.db or not addon.db["moneyTracker"] or not addon.db["moneyTracker"][key] then return end

					local contact = addon.db["moneyTracker"][key]
					local classColor = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[contact.class or ""] or { r = 1, g = 1, b = 1 }
					local displayName =
						string.format("|cff%02x%02x%02x%s-%s|r", (classColor.r or 1) * 255, (classColor.g or 1) * 255, (classColor.b or 1) * 255, contact.name or "?", contact.realm or "?")

					local dialogKey = "EQOL_MONEY_TRACKER_REMOVE"
					StaticPopupDialogs[dialogKey] = StaticPopupDialogs[dialogKey]
						or {
							text = L["moneyTrackerRemoveConfirm"],
							button1 = ACCEPT,
							button2 = CANCEL,
							timeout = 0,
							whileDead = true,
							hideOnEscape = true,
							preferredIndex = 3,
						}

					StaticPopupDialogs[dialogKey].OnAccept = function(_, guid)
						if not guid or not addon.db or not addon.db["moneyTracker"] then return end
						addon.db["moneyTracker"][guid] = nil
					end

					StaticPopup_Show(dialogKey, displayName or key, nil, key)
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["enableMoneyTracker"]
						and addon.SettingsLayout.elements["enableMoneyTracker"].setting
						and addon.SettingsLayout.elements["enableMoneyTracker"].setting:GetValue() == true
				end,
				parent = true,
				default = "",
				var = "moneyTracker",
				type = Settings.VarType.String,
				sType = "dropdown",
			},
		},
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cVendorEconomy, data)
----- REGION END

function addon.functions.initVendorEconomy() end

local eventHandlers = {}

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
