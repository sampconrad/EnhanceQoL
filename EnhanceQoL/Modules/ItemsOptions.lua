local addonName, addon = ...

local L = addon.L
local AceGUI = addon.AceGUI
local math = math
local UnitClass = UnitClass

local headerClassInfo = L["headerClassInfo"]:format(select(1, UnitClass("player")))

local function ensureDisplayDB()
	if addon.functions and addon.functions.ensureDisplayDB then addon.functions.ensureDisplayDB() end
end

local function refreshCharFrame()
	if addon.functions and addon.functions.setCharFrame then addon.functions.setCharFrame() end
end

local function recalcDurability()
	if addon.functions and addon.functions.calculateDurability then addon.functions.calculateDurability() end
end

local function refreshLootToast()
	if addon.functions and addon.functions.initLootToast then addon.functions.initLootToast() end
end

local function showBagIgnoreWarning()
	if addon.functions and addon.functions.checkBagIgnoreJunk then addon.functions.checkBagIgnoreJunk() end
end

local onInspect = addon.functions and addon.functions.onInspect

local function addVendorMainFrame2(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)
	local function doLayout()
		if scroll and scroll.DoLayout then scroll:DoLayout() end
	end
	wrapper:PauseLayout()

	local groups = {}
	local ahCore

	local function ensureGroup(key, title)
		local g, known
		if groups[key] then
			g = groups[key]
			groups[key]:PauseLayout()
			groups[key]:ReleaseChildren()
			known = true
		else
			g = addon.functions.createContainer("InlineGroup", "List")
			g:SetTitle(title)
			wrapper:AddChild(g)
			groups[key] = g
		end

		return g, known
	end

	local function buildAHCore()
		local g, known = ensureGroup("ahcore", BUTTON_LAG_AUCTIONHOUSE)
		local items = {
			{
				text = L["persistAuctionHouseFilter"],
				var = "persistAuctionHouseFilter",
				func = function(_, _, v) addon.db["persistAuctionHouseFilter"] = v end,
			},
			{
				text = (function()
					local label = _G["AUCTION_HOUSE_FILTER_CURRENTEXPANSION_ONLY"] or "Current Expansion Only"
					return L["alwaysUserCurExpAuctionHouse"]:format(label)
				end)(),
				var = "alwaysUserCurExpAuctionHouse",
				func = function(_, _, v) addon.db["alwaysUserCurExpAuctionHouse"] = v end,
			},
		}
		table.sort(items, function(a, b) return a.text < b.text end)
		for _, it in ipairs(items) do
			local w = addon.functions.createCheckboxAce(it.text, addon.db[it.var], it.func, it.desc)
			g:AddChild(w)
		end
		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildConvenience()
		local g, known = ensureGroup("conv", L["Convenience"])
		local checkboxes = {}
		local items = {
			{
				var = "autoRepair",
				text = L["autoRepair"],
				func = function(_, _, v)
					addon.db["autoRepair"] = v
					if checkboxes["autoRepairGuildBank"] then
						checkboxes["autoRepairGuildBank"]:SetDisabled(not v)
						if not v and addon.db["autoRepairGuildBank"] then
							addon.db["autoRepairGuildBank"] = false
							checkboxes["autoRepairGuildBank"]:SetValue(false)
						end
					end
				end,
				desc = L["autoRepairDesc"],
			},
			{
				var = "autoRepairGuildBank",
				text = L["autoRepairGuildBank"],
				func = function(_, _, v) addon.db["autoRepairGuildBank"] = v end,
				desc = L["autoRepairGuildBankDesc"],
			},
			{
				var = "sellAllJunk",
				text = L["sellAllJunk"],
				func = function(_, _, v)
					addon.db["sellAllJunk"] = v
					if v then showBagIgnoreWarning() end
				end,
				desc = L["sellAllJunkDesc"],
			},
		}
		for _, it in ipairs(items) do
			local w = addon.functions.createCheckboxAce(it.text, addon.db[it.var], it.func, it.desc)
			if it.var == "autoRepairGuildBank" then w:SetDisabled(not addon.db["autoRepair"]) end
			g:AddChild(w)
			checkboxes[it.var] = w
		end

		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildMerchant()
		local g, known = ensureGroup("merchant", MERCHANT)
		local w = addon.functions.createCheckboxAce(L["enableExtendedMerchant"], addon.db["enableExtendedMerchant"], function(_, _, value)
			addon.db["enableExtendedMerchant"] = value
			if addon.Merchant then
				if value and addon.Merchant.Enable then
					addon.Merchant:Enable()
				elseif not value and addon.Merchant.Disable then
					addon.Merchant:Disable()
					addon.variables.requireReload = true
					addon.functions.checkReloadFrame()
				end
			end
		end, L["enableExtendedMerchantDesc"])
		g:AddChild(w)

		local highlightKnownCheckbox = addon.functions.createCheckboxAce(L["markKnownOnMerchant"], addon.db["markKnownOnMerchant"], function(_, _, value)
			addon.db["markKnownOnMerchant"] = value
			if MerchantFrame and MerchantFrame:IsShown() then
				if MerchantFrame.selectedTab == 2 then
					if MerchantFrame_UpdateBuybackInfo then MerchantFrame_UpdateBuybackInfo() end
				else
					if MerchantFrame_UpdateMerchantInfo then MerchantFrame_UpdateMerchantInfo() end
				end
			end
		end, L["markKnownOnMerchantDesc"])
		g:AddChild(highlightKnownCheckbox)

		local highlightCollectedPetsCheckbox = addon.functions.createCheckboxAce(L["markCollectedPetsOnMerchant"], addon.db["markCollectedPetsOnMerchant"], function(_, _, value)
			addon.db["markCollectedPetsOnMerchant"] = value
			if MerchantFrame and MerchantFrame:IsShown() then
				if MerchantFrame.selectedTab == 2 then
					if MerchantFrame_UpdateBuybackInfo then MerchantFrame_UpdateBuybackInfo() end
				else
					if MerchantFrame_UpdateMerchantInfo then MerchantFrame_UpdateMerchantInfo() end
				end
			end
		end, L["markCollectedPetsOnMerchantDesc"])
		g:AddChild(highlightCollectedPetsCheckbox)

		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildMailbox()
		local g, known = ensureGroup("mail", MINIMAP_TRACKING_MAILBOX)
		local w = addon.functions.createCheckboxAce(L["enableMailboxAddressBook"], addon.db["enableMailboxAddressBook"], function(_, _, value)
			addon.db["enableMailboxAddressBook"] = value
			if addon.Mailbox then
				if addon.Mailbox.SetEnabled then addon.Mailbox:SetEnabled(value) end
				if value and addon.Mailbox.AddSelfToContacts then addon.Mailbox:AddSelfToContacts() end
				if value and addon.Mailbox.RefreshList then addon.Mailbox:RefreshList() end
			end
			buildMailbox()
		end, L["enableMailboxAddressBookDesc"])
		g:AddChild(w)

		if addon.db["enableMailboxAddressBook"] then
			local sub = addon.functions.createContainer("InlineGroup", "List")
			sub:SetTitle(L["mailboxRemoveHeader"])
			g:AddChild(sub)

			local tList = {}
			for key, rec in pairs(addon.db["mailboxContacts"]) do
				local class = rec and rec.class
				local col = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class or ""] or { r = 1, g = 1, b = 1 }
				tList[key] = string.format("|cff%02x%02x%02x%s|r", col.r * 255, col.g * 255, col.b * 255, key)
			end
			local list, order = addon.functions.prepareListForDropdown(tList)
			local drop = addon.functions.createDropdownAce(L["mailboxRemoveSelect"], list, order, nil)
			sub:AddChild(drop)

			local btn = addon.functions.createButtonAce(REMOVE, 120, function()
				local selected = drop:GetValue()
				if selected and addon.db["mailboxContacts"][selected] then
					addon.db["mailboxContacts"][selected] = nil
					local refresh = {}
					for key, rec in pairs(addon.db["mailboxContacts"]) do
						local class = rec and rec.class
						local col = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class or ""] or { r = 1, g = 1, b = 1 }
						refresh[key] = string.format("|cff%02x%02x%02x%s|r", col.r * 255, col.g * 255, col.b * 255, key)
					end
					local nl, no = addon.functions.prepareListForDropdown(refresh)
					drop:SetList(nl, no)
					drop:SetValue(nil)
					if addon.Mailbox and addon.Mailbox.RefreshList then addon.Mailbox:RefreshList() end
				end
			end)
			sub:AddChild(btn)
		end
		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildMoney()
		local g, known = ensureGroup("money", MONEY)

		local cbEnable = addon.functions.createCheckboxAce(L["enableMoneyTracker"], addon.db["enableMoneyTracker"], function(_, _, v)
			addon.db["enableMoneyTracker"] = v
			buildMoney()
		end, L["enableMoneyTrackerDesc"])
		g:AddChild(cbEnable)

		if addon.db["enableMoneyTracker"] then
			local sub = addon.functions.createContainer("InlineGroup", "List")
			g:AddChild(sub)

			local cbGoldOnly = addon.functions.createCheckboxAce(L["showOnlyGoldOnMoney"], addon.db["showOnlyGoldOnMoney"], function(_, _, v) addon.db["showOnlyGoldOnMoney"] = v end)
			sub:AddChild(cbGoldOnly)

			local tList = {}
			for guid, v in pairs(addon.db["moneyTracker"]) do
				if guid ~= UnitGUID("player") then
					local col = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[v.class] or { r = 1, g = 1, b = 1 }
					local displayName = string.format("|cff%02x%02x%02x%s-%s|r", (col.r or 1) * 255, (col.g or 1) * 255, (col.b or 1) * 255, v.name or "?", v.realm or "?")
					tList[guid] = displayName
				end
			end

			local list, order = addon.functions.prepareListForDropdown(tList)
			local dropRemove = addon.functions.createDropdownAce(L["moneyTrackerRemovePlayer"], list, order, nil)
			local btnRemove = addon.functions.createButtonAce(REMOVE, 100, function()
				local sel = dropRemove:GetValue()
				if sel and addon.db["moneyTracker"][sel] then
					addon.db["moneyTracker"][sel] = nil
					local tList2 = {}
					for guid, v in pairs(addon.db["moneyTracker"]) do
						if guid ~= UnitGUID("player") then
							local col = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[v.class] or { r = 1, g = 1, b = 1 }
							local displayName = string.format("|cff%02x%02x%02x%s-%s|r", (col.r or 1) * 255, (col.g or 1) * 255, (col.b or 1) * 255, v.name or "?", v.realm or "?")
							tList2[guid] = displayName
						end
					end
					local nl, no = addon.functions.prepareListForDropdown(tList2)
					dropRemove:SetList(nl, no)
					dropRemove:SetValue(nil)
				end
			end)
			sub:AddChild(dropRemove)
			sub:AddChild(btnRemove)
		end
		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	buildAHCore()
	buildConvenience()
	buildMerchant()
	buildMailbox()
	-- TODO bug in midnight beta - need to remove as we can't handle tooltip
	if not addon.variables.isMidnight then buildMoney() end
	wrapper:ResumeLayout()
	doLayout()
end

local function addCharacterFrame(container)
	local posList = {
		TOPLEFT = L["topLeft"],
		TOPRIGHT = L["topRight"],
		BOTTOMLEFT = L["bottomLeft"],
		BOTTOMRIGHT = L["bottomRight"],
	}
	local posOrder = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }

	-- Base layout
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	wrapper:SetFullWidth(true)
	scroll:AddChild(wrapper)

	-- Multi-dropdowns (Character/Inspect)
	ensureDisplayDB()
	local ddGroup = addon.functions.createContainer("InlineGroup", "List")
	ddGroup:SetTitle(L["Character & Inspect Info"] or "Character & Inspect Info")
	wrapper:AddChild(ddGroup)

	local AceGUI = addon.AceGUI
	local optionsList = {
		ilvl = STAT_AVERAGE_ITEM_LEVEL or "Item Level",
		gems = AUCTION_CATEGORY_GEMS or "Gems",
		enchants = ENCHANTS or "Enchants",
		gemtip = L["Gem slot tooltip"] or "Gem slot tooltip",
		durability = DURABILITY or "Durability",
		catalyst = L["Catalyst Charges"] or "Catalyst Charges",
	}

	local ddChar = AceGUI:Create("Dropdown")
	ddChar:SetLabel(L["Show on Character Frame"] or "Show on Character Frame")
	ddChar:SetMultiselect(true)
	ddChar:SetFullWidth(true)
	ddChar:SetList(optionsList)
	for k in pairs(optionsList) do
		if k == "durability" then
			ddChar:SetItemValue(k, addon.db and addon.db["showDurabilityOnCharframe"] == true)
		elseif k == "catalyst" then
			ddChar:SetItemValue(k, addon.db and addon.db["showCatalystChargesOnCharframe"] == true)
		else
			local t = addon.db.charDisplayOptions or {}
			ddChar:SetItemValue(k, t[k] == true)
		end
	end
	ddChar:SetCallback("OnValueChanged", function(_, _, key, val)
		ensureDisplayDB()
		local b = val and true or false
		if key == "durability" then
			addon.db["showDurabilityOnCharframe"] = b
			if addon.general and addon.general.durabilityIconFrame then
				if b and not addon.functions.IsTimerunner() then
					recalcDurability()
					addon.general.durabilityIconFrame:Show()
				else
					addon.general.durabilityIconFrame:Hide()
				end
			end
			addon.db.charDisplayOptions.durability = b
		elseif key == "catalyst" then
			addon.db["showCatalystChargesOnCharframe"] = b
			if addon.general and addon.general.iconFrame then
				if b and addon.variables and addon.variables.catalystID and not addon.functions.IsTimerunner() then
					local c = C_CurrencyInfo.GetCurrencyInfo(addon.variables.catalystID)
					if c then addon.general.iconFrame.count:SetText(c.quantity) end
					addon.general.iconFrame:Show()
				else
					addon.general.iconFrame:Hide()
				end
			end
			addon.db.charDisplayOptions.catalyst = b
		else
			addon.db.charDisplayOptions[key] = b
			refreshCharFrame()
		end
	end)
	ddGroup:AddChild(ddChar)

	local ddInsp = AceGUI:Create("Dropdown")
	ddInsp:SetLabel(L["Show on Inspect Frame"] or "Show on Inspect Frame")
	ddInsp:SetMultiselect(true)
	ddInsp:SetFullWidth(true)
	local inspOptionsList = {
		ilvl = STAT_AVERAGE_ITEM_LEVEL or "Item Level",
		gems = AUCTION_CATEGORY_GEMS or "Gems",
		enchants = ENCHANTS or "Enchants",
		gemtip = L["Gem slot tooltip"] or "Gem slot tooltip",
	}
	ddInsp:SetList(inspOptionsList)
	for k in pairs(inspOptionsList) do
		local t = addon.db.inspectDisplayOptions or {}
		ddInsp:SetItemValue(k, t[k] == true)
	end
	ddInsp:SetCallback("OnValueChanged", function(_, _, key, val)
		ensureDisplayDB()
		addon.db.inspectDisplayOptions[key] = val and true or false
		if InspectFrame and InspectFrame:IsShown() and InspectFrame.unit then
			local guid = UnitGUID(InspectFrame.unit)
			if guid then onInspect(guid) end
		end
	end)
	ddGroup:AddChild(ddInsp)

	-- Info group
	local groupInfo = addon.functions.createContainer("InlineGroup", "List")
	groupInfo:SetTitle(INFO)
	wrapper:AddChild(groupInfo)

	-- TODO remove on midnight release
	if not addon.variables.isMidnight then
		local cbCloak = addon.functions.createCheckboxAce(L["showCloakUpgradeButton"], addon.db["showCloakUpgradeButton"], function(_, _, value)
			addon.db["showCloakUpgradeButton"] = value
			if addon.functions.updateCloakUpgradeButton then addon.functions.updateCloakUpgradeButton() end
		end)
		groupInfo:AddChild(cbCloak)
	end

	local cbInstant = addon.functions.createCheckboxAce(L["instantCatalystEnabled"], addon.db["instantCatalystEnabled"], function(_, _, value)
		addon.db["instantCatalystEnabled"] = value
		addon.functions.toggleInstantCatalystButton(value)
	end, L["instantCatalystEnabledDesc"])
	groupInfo:AddChild(cbInstant)

	local cbMovementSpeed = addon.functions.createCheckboxAce(L["MovementSpeedInfo"]:format(STAT_MOVEMENT_SPEED), addon.db["movementSpeedStatEnabled"], function(_, _, value)
		addon.db["movementSpeedStatEnabled"] = value
		if value then
			if addon.MovementSpeedStat and addon.MovementSpeedStat.Refresh then addon.MovementSpeedStat.Refresh() end
		else
			addon.MovementSpeedStat.Disable()
		end
	end)
	groupInfo:AddChild(cbMovementSpeed)

	local cbOpenChar = addon.functions.createCheckboxAce(L["openCharframeOnUpgrade"], addon.db["openCharframeOnUpgrade"], function(_, _, value) addon.db["openCharframeOnUpgrade"] = value end)
	groupInfo:AddChild(cbOpenChar)

	-- Ilvl position group
	local groupIlvl = addon.functions.createContainer("InlineGroup", "List")
	groupIlvl:SetTitle(LFG_LIST_ITEM_LEVEL_INSTR_SHORT)
	wrapper:AddChild(groupIlvl)
	local dropIlvl = addon.functions.createDropdownAce(L["charIlvlPosition"], posList, posOrder, function(self, _, value)
		addon.db["charIlvlPosition"] = value
		refreshCharFrame()
	end)
	dropIlvl:SetValue(addon.db["charIlvlPosition"])
	dropIlvl:SetRelativeWidth(0.4)
	groupIlvl:AddChild(dropIlvl)

	-- Gems group
	local groupGems = addon.functions.createContainer("InlineGroup", "List")
	groupGems:SetTitle(AUCTION_CATEGORY_GEMS)
	wrapper:AddChild(groupGems)
	local cbGemHelper = addon.functions.createCheckboxAce(L["enableGemHelper"], addon.db["enableGemHelper"], function(_, _, value)
		addon.db["enableGemHelper"] = value
		if not value and EnhanceQoLGemHelper then
			EnhanceQoLGemHelper:Hide()
			EnhanceQoLGemHelper = nil
		end
	end, L["enableGemHelperDesc"])
	groupGems:AddChild(cbGemHelper)

	-- Class specific
	local classname = select(2, UnitClass("player"))
	local groupClass = addon.functions.createContainer("InlineGroup", "List")
	groupClass:SetTitle(headerClassInfo)
	wrapper:AddChild(groupClass)

	local function addTotemCheckbox(dbKey)
		local cb = addon.functions.createCheckboxAce(L["shaman_HideTotem"], addon.db[dbKey], function(_, _, value)
			addon.db[dbKey] = value
			if value then
				if TotemFrame then TotemFrame:Hide() end
			else
				if TotemFrame then TotemFrame:Show() end
			end
		end)
		groupClass:AddChild(cb)
	end

	if classname == "DEATHKNIGHT" then
		local cb = addon.functions.createCheckboxAce(L["deathknight_HideRuneFrame"], addon.db["deathknight_HideRuneFrame"], function(_, _, value)
			addon.db["deathknight_HideRuneFrame"] = value
			if value then
				if RuneFrame then RuneFrame:Hide() end
			else
				if RuneFrame then RuneFrame:Show() end
			end
		end)
		groupClass:AddChild(cb)
		addTotemCheckbox("deathknight_HideTotemBar")
	elseif classname == "DRUID" then
		addTotemCheckbox("druid_HideTotemBar")
		local cb = addon.functions.createCheckboxAce(L["druid_HideComboPoint"], addon.db["druid_HideComboPoint"], function(_, _, value)
			addon.db["druid_HideComboPoint"] = value
			if value then
				if DruidComboPointBarFrame then DruidComboPointBarFrame:Hide() end
			else
				if DruidComboPointBarFrame then DruidComboPointBarFrame:Show() end
			end
		end)
		groupClass:AddChild(cb)
	elseif classname == "EVOKER" then
		local cb = addon.functions.createCheckboxAce(L["evoker_HideEssence"], addon.db["evoker_HideEssence"], function(_, _, value)
			addon.db["evoker_HideEssence"] = value
			if value then
				if EssencePlayerFrame then EssencePlayerFrame:Hide() end
			else
				if EssencePlayerFrame then EssencePlayerFrame:Show() end
			end
		end)
		groupClass:AddChild(cb)
	elseif classname == "MAGE" then
		addTotemCheckbox("mage_HideTotemBar")
	elseif classname == "MONK" then
		local cb = addon.functions.createCheckboxAce(L["monk_HideHarmonyBar"], addon.db["monk_HideHarmonyBar"], function(_, _, value)
			addon.db["monk_HideHarmonyBar"] = value
			if value then
				if MonkHarmonyBarFrame then MonkHarmonyBarFrame:Hide() end
			else
				if MonkHarmonyBarFrame then MonkHarmonyBarFrame:Show() end
			end
		end)
		groupClass:AddChild(cb)
		addTotemCheckbox("monk_HideTotemBar")
	elseif classname == "PRIEST" then
		addTotemCheckbox("priest_HideTotemBar")
	elseif classname == "SHAMAN" then
		addTotemCheckbox("shaman_HideTotem")
	elseif classname == "ROGUE" then
		local cb = addon.functions.createCheckboxAce(L["rogue_HideComboPoint"], addon.db["rogue_HideComboPoint"], function(_, _, value)
			addon.db["rogue_HideComboPoint"] = value
			if value then
				if RogueComboPointBarFrame then RogueComboPointBarFrame:Hide() end
			else
				if RogueComboPointBarFrame then RogueComboPointBarFrame:Show() end
			end
		end)
		groupClass:AddChild(cb)
	elseif classname == "PALADIN" then
		local cb = addon.functions.createCheckboxAce(L["paladin_HideHolyPower"], addon.db["paladin_HideHolyPower"], function(_, _, value)
			addon.db["paladin_HideHolyPower"] = value
			if value then
				if PaladinPowerBarFrame then PaladinPowerBarFrame:Hide() end
			else
				if PaladinPowerBarFrame then PaladinPowerBarFrame:Show() end
			end
		end)
		groupClass:AddChild(cb)
		addTotemCheckbox("paladin_HideTotemBar")
	elseif classname == "WARLOCK" then
		local cb = addon.functions.createCheckboxAce(L["warlock_HideSoulShardBar"], addon.db["warlock_HideSoulShardBar"], function(_, _, value)
			addon.db["warlock_HideSoulShardBar"] = value
			if value then
				if WarlockPowerFrame then WarlockPowerFrame:Hide() end
			else
				if WarlockPowerFrame then WarlockPowerFrame:Show() end
			end
		end)
		groupClass:AddChild(cb)
		addTotemCheckbox("warlock_HideTotemBar")
	end

	scroll:DoLayout()
	wrapper:DoLayout()
end

-- Check if a misc option exists (avoids empty debug-only pages)

local function addLootFrame(container, d)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)

	local data = {
		{
			parent = "",
			var = "autoQuickLoot",
			desc = L["autoQuickLootDesc"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["autoQuickLoot"] = value
				container:ReleaseChildren()
				addLootFrame(container)
			end,
		},
		{
			parent = "",
			var = "autoHideBossBanner",
			text = L["autoHideBossBanner"],
			desc = L["autoHideBossBannerDesc"],
			type = "CheckBox",
			callback = function(self, _, value) addon.db["autoHideBossBanner"] = value end,
		},
		{
			parent = "",
			var = "hideAzeriteToast",
			text = L["hideAzeriteToast"],
			desc = L["hideAzeriteToastDesc"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["hideAzeriteToast"] = value
				if value then
					if AzeriteLevelUpToast then
						AzeriteLevelUpToast:UnregisterAllEvents()
						AzeriteLevelUpToast:Hide()
					end
				else
					addon.variables.requireReload = true
					addon.functions.checkReloadFrame()
				end
			end,
		},
	}

	table.sort(data, function(a, b)
		local textA = a.text or L[a.var]
		local textB = b.text or L[b.var]
		return textA < textB
	end)

	for _, checkboxData in ipairs(data) do
		local desc
		if checkboxData.desc then desc = checkboxData.desc end
		local text
		if checkboxData.text then
			text = checkboxData.text
		else
			text = L[checkboxData.var]
		end
		local uFunc = function(self, _, value) addon.db[checkboxData.var] = value end
		if checkboxData.callback then uFunc = checkboxData.callback end
		local cb = addon.functions.createCheckboxAce(text, addon.db[checkboxData.var], uFunc, desc)
		groupCore:AddChild(cb)
	end

	if addon.db["autoQuickLoot"] then
		local cbShift = addon.functions.createCheckboxAce(L["autoQuickLootWithShift"], addon.db["autoQuickLootWithShift"], function(self, _, value) addon.db["autoQuickLootWithShift"] = value end)
		groupCore:AddChild(cbShift)
	end

	local groupRollGroup = addon.functions.createContainer("InlineGroup", "List")
	groupRollGroup:SetTitle(L["groupLootRollFrames"] or L["groupLootAnchorLabel"] or "Group loot roll frames")
	wrapper:AddChild(groupRollGroup)

	local groupRollToggle = addon.functions.createCheckboxAce(
		L["enableGroupLootAnchorOption"] or L["groupLootAnchorLabel"] or "Move group loot roll frames",
		addon.db.enableGroupLootAnchor,
		function(_, _, value)
			addon.db.enableGroupLootAnchor = value and true or false
			if addon.LootToast and addon.LootToast.OnGroupRollAnchorOptionChanged then addon.LootToast:OnGroupRollAnchorOptionChanged(addon.db.enableGroupLootAnchor) end
			refreshLootToast()
			container:ReleaseChildren()
			addLootFrame(container)
		end,
		L["enableGroupLootAnchorDesc"]
	)
	groupRollGroup:AddChild(groupRollToggle)

	if addon.db.enableGroupLootAnchor then
		local layout = addon.db.groupLootLayout or {}
		local currentScale = layout.scale or 1
		local sliderLabel = string.format("%s: %.2f", L["groupLootScale"] or "Loot roll frame scale", currentScale)
		local sliderScale = addon.functions.createSliderAce(sliderLabel, currentScale, 0.5, 3.0, 0.05, function(self, _, val)
			val = math.max(0.5, math.min(3.0, val or 1))
			val = math.floor(val * 100 + 0.5) / 100
			layout.scale = val
			addon.db.groupLootLayout = layout
			self:SetLabel(string.format("%s: %.2f", L["groupLootScale"] or "Loot roll frame scale", val))
			if addon.LootToast and addon.LootToast.ApplyGroupLootLayout then addon.LootToast:ApplyGroupLootLayout() end
		end)
		groupRollGroup:AddChild(sliderScale)
	end

	local lootToastGroup = addon.functions.createContainer("InlineGroup", "List")
	lootToastGroup:SetTitle(L["lootToastSectionTitle"])
	wrapper:AddChild(lootToastGroup)

	local anchorToggle = addon.functions.createCheckboxAce(L["moveLootToast"], addon.db.enableLootToastAnchor, function(self, _, value)
		addon.db.enableLootToastAnchor = value
		if addon.LootToast and addon.LootToast.OnAnchorOptionChanged then addon.LootToast:OnAnchorOptionChanged(value) end
		refreshLootToast()
		container:ReleaseChildren()
		addLootFrame(container)
	end, L["moveLootToastDesc"])
	lootToastGroup:AddChild(anchorToggle)

	local editModeAvailable = addon.EditMode and addon.EditMode.IsAvailable and addon.EditMode:IsAvailable()
	if editModeAvailable then
		local anchorHint = addon.functions.createLabelAce("", nil, nil, 12)
		anchorHint:SetFullWidth(true)
		local hintText = L["lootToastAnchorEditModeHint"] or L["lootToastAnchorLabel"] or ""
		if addon.db.enableLootToastAnchor then
			anchorHint:SetText("|cffffd700" .. hintText .. "|r")
		else
			anchorHint:SetText("|cff999999" .. hintText .. "|r")
		end
		lootToastGroup:AddChild(anchorHint)
	else
		local anchorButton = addon.functions.createButtonAce(L["lootToastAnchorButton"] or "", 200, function()
			if not addon.db.enableLootToastAnchor then return end
			addon.LootToast:ToggleAnchorPreview()
		end)
		anchorButton:SetFullWidth(true)
		anchorButton:SetDisabled(not addon.db.enableLootToastAnchor)
		lootToastGroup:AddChild(anchorButton)

		local anchorLabel = addon.functions.createLabelAce("", nil, nil, 12)
		anchorLabel:SetFullWidth(true)
		local manualHint = L["lootToastAnchorManualHint"] or L["lootToastAnchorLabel"] or ""
		if addon.db.enableLootToastAnchor then
			anchorLabel:SetText("|cffffd700" .. manualHint .. "|r")
		else
			anchorLabel:SetText("|cff999999" .. manualHint .. "|r")
		end
		lootToastGroup:AddChild(anchorLabel)
	end

	local filterToggle = addon.functions.createCheckboxAce(L["enableLootToastFilter"], addon.db.enableLootToastFilter, function(self, _, value)
		addon.db.enableLootToastFilter = value
		refreshLootToast()
		container:ReleaseChildren()
		addLootFrame(container)
	end, L["enableLootToastFilterDesc"])
	lootToastGroup:AddChild(filterToggle)

	if addon.db.enableLootToastFilter then
		local filterGroup = addon.functions.createContainer("InlineGroup", "List")
		filterGroup:SetTitle(L["lootToastFilterSettings"])
		lootToastGroup:AddChild(filterGroup)

		local tabs = {
			{ text = ITEM_QUALITY3_DESC, value = tostring(Enum.ItemQuality.Rare) },
			{ text = ITEM_QUALITY4_DESC, value = tostring(Enum.ItemQuality.Epic) },
			{ text = ITEM_QUALITY5_DESC, value = tostring(Enum.ItemQuality.Legendary) },
			{ text = L["Include"], value = "include" },
		}

		local function buildTab(tabContainer, rarity)
			tabContainer:ReleaseChildren()
			if rarity == "include" then
				local eBox
				local dropIncludeList

				local function addInclude(input)
					local id = tonumber(input)
					if not id then id = tonumber(string.match(tostring(input), "item:(%d+)")) end
					if not id then
						print("|cffff0000Invalid input!|r")
						eBox:SetText("")
						return
					end
					local eItem
					if type(input) == "string" and input:find("|Hitem:") then
						eItem = Item:CreateFromItemLink(input)
					else
						eItem = Item:CreateFromItemID(id)
					end
					if eItem and not eItem:IsItemEmpty() then
						eItem:ContinueOnItemLoad(function()
							local name = eItem:GetItemName()
							if not name then
								print(L["Item id does not exist"])
								eBox:SetText("")
								return
							end
							if not addon.db.lootToastIncludeIDs[eItem:GetItemID()] then
								addon.db.lootToastIncludeIDs[eItem:GetItemID()] = string.format("%s (%d)", name, eItem:GetItemID())
								local list, order = addon.functions.prepareListForDropdown(addon.db.lootToastIncludeIDs)
								dropIncludeList:SetList(list, order)
								dropIncludeList:SetValue(nil)
								print(L["lootToastItemAdded"]:format(name, eItem:GetItemID()))
							end
							eBox:SetText("")
						end)
					else
						print(L["Item id does not exist"])
						eBox:SetText("")
					end
				end

				eBox = addon.functions.createEditboxAce(L["Item id or drag item"], nil, function(self, _, txt)
					if txt ~= "" and txt ~= L["Item id or drag item"] then addInclude(txt) end
				end)
				tabContainer:AddChild(eBox)

				local list, order = addon.functions.prepareListForDropdown(addon.db.lootToastIncludeIDs)
				dropIncludeList = addon.functions.createDropdownAce(L["IncludeVendorList"], list, order, nil)
				local btnRemove = addon.functions.createButtonAce(REMOVE, 100, function()
					local sel = dropIncludeList:GetValue()
					if sel then
						addon.db.lootToastIncludeIDs[sel] = nil
						local l, o = addon.functions.prepareListForDropdown(addon.db.lootToastIncludeIDs)
						dropIncludeList:SetList(l, o)
						dropIncludeList:SetValue(nil)
					end
				end)
				local label = addon.functions.createLabelAce("", nil, nil, 14)
				label:SetFullWidth(true)
				tabContainer:AddChild(label)
				label:SetText("|cffffd700" .. L["includeInfoLoot"] .. "|r")
				tabContainer:AddChild(dropIncludeList)
				tabContainer:AddChild(btnRemove)
			else
				local q = tonumber(rarity)
				local filter = addon.db.lootToastFilters[q]
				local label = addon.functions.createLabelAce("", nil, nil, 14)
				label:SetFullWidth(true)
				tabContainer:AddChild(label)

				local function refreshLabel()
					local text
					if rarity ~= "include" then
						local extras = {}
						if filter.mounts then table.insert(extras, MOUNTS:lower()) end
						if filter.pets then table.insert(extras, PETS:lower()) end
						if filter.upgrade then table.insert(extras, L["lootToastExtrasUpgrades"]) end
						local eText = ""
						if #extras > 0 then eText = L["alwaysShow"] .. table.concat(extras, " " .. L["andWord"] .. " ") end
						if filter.ilvl then
							text = L["lootToastSummaryIlvl"]:format(addon.db.lootToastItemLevels[q], eText)
						else
							text = L["lootToastSummaryNoIlvl"]:format(eText)
						end
					else
						text = L["lootToastExplanation"]
					end
					label:SetText("|cffffd700" .. text .. "|r")
				end

				tabContainer:AddChild(addon.functions.createCheckboxAce(L["lootToastCheckIlvl"], filter.ilvl, function(self, _, v)
					addon.db.lootToastFilters[q].ilvl = v
					filter.ilvl = v
					refreshLabel()
				end))
				local slider = addon.functions.createSliderAce(L["lootToastItemLevel"] .. ": " .. addon.db.lootToastItemLevels[q], addon.db.lootToastItemLevels[q], 0, 1000, 1, function(self, _, val)
					addon.db.lootToastItemLevels[q] = val
					self:SetLabel(L["lootToastItemLevel"] .. ": " .. val)
					refreshLabel()
				end)
				tabContainer:AddChild(slider)

				local alwaysList = {
					mounts = L["lootToastAlwaysShowMounts"],
					pets = L["lootToastAlwaysShowPets"],
					upgrade = L["lootToastAlwaysShowUpgrades"],
				}
				local alwaysOrder = { "mounts", "pets", "upgrade" }
				local dropdownAlways = addon.functions.createDropdownAce(L["lootToastAlwaysShow"], alwaysList, alwaysOrder, function(self, _, key, checked)
					if not key then return end
					local isChecked = checked and true or false
					if addon.db.lootToastFilters[q][key] ~= nil then
						addon.db.lootToastFilters[q][key] = isChecked
						filter[key] = isChecked
						self:SetItemValue(key, isChecked)
						refreshLabel()
					end
				end)
				dropdownAlways:SetMultiselect(true)
				for _, key in ipairs(alwaysOrder) do
					dropdownAlways:SetItemValue(key, not not filter[key])
				end
				tabContainer:AddChild(dropdownAlways)

				refreshLabel()
			end
			scroll:DoLayout()
		end

		local cbSound = addon.functions.createCheckboxAce(L["enableLootToastCustomSound"], addon.db.lootToastUseCustomSound, function(self, _, v)
			addon.db.lootToastUseCustomSound = v
			container:ReleaseChildren()
			addLootFrame(container)
		end)
		filterGroup:AddChild(cbSound)

		if addon.db.lootToastUseCustomSound then
			if addon.ChatIM and addon.ChatIM.BuildSoundTable and not addon.ChatIM.availableSounds then addon.ChatIM:BuildSoundTable() end
			local soundList = {}
			for name in pairs(addon.ChatIM.availableSounds or {}) do
				soundList[name] = name
			end
			local list, order = addon.functions.prepareListForDropdown(soundList)
			local dropSound = addon.functions.createDropdownAce(L["lootToastCustomSound"], list, order, function(self, _, val)
				addon.db.lootToastCustomSoundFile = val
				self:SetValue(val)
				local file = addon.ChatIM.availableSounds and addon.ChatIM.availableSounds[val]
				if file then PlaySoundFile(file, "Master") end
			end)
			dropSound:SetValue(addon.db.lootToastCustomSoundFile)
			filterGroup:AddChild(dropSound)
		end

		local tabGroup = addon.functions.createContainer("TabGroup", "Flow")
		tabGroup:SetTabs(tabs)
		tabGroup:SetCallback("OnGroupSelected", function(tabContainer, _, groupVal) buildTab(tabContainer, groupVal) end)
		filterGroup:AddChild(tabGroup)
		tabGroup:SelectTab(tabs[1].value)
	end

	local lootSpecGroup = addon.functions.createContainer("InlineGroup", "List")
	lootSpecGroup:SetTitle(L["dungeonJournalLootSpecIcons"])
	lootSpecGroup:SetFullWidth(true)
	wrapper:AddChild(lootSpecGroup)

	local function rebuildDungeonJournalLootSpec()
		lootSpecGroup:ReleaseChildren()

		local toggle = addon.functions.createCheckboxAce(L["dungeonJournalLootSpecIcons"], addon.db["dungeonJournalLootSpecIcons"], function(_, _, value)
			addon.db["dungeonJournalLootSpecIcons"] = value
			if addon.DungeonJournalLootSpec and addon.DungeonJournalLootSpec.SetEnabled then addon.DungeonJournalLootSpec:SetEnabled(value) end
			rebuildDungeonJournalLootSpec()
		end, L["dungeonJournalLootSpecIconsDesc"])
		if toggle.SetFullWidth then toggle:SetFullWidth(true) end
		lootSpecGroup:AddChild(toggle)

		if not addon.db["dungeonJournalLootSpecIcons"] then
			if scroll.DoLayout then scroll:DoLayout() end
			return
		end

		local anchorOptions = {
			["1"] = L["dungeonJournalLootSpecAnchorTop"],
			["2"] = L["dungeonJournalLootSpecAnchorBottom"],
		}

		local anchorRow = addon.functions.createContainer("InlineGroup", "Flow")
		anchorRow:SetFullWidth(true)

		local anchorDropdown = addon.functions.createDropdownAce(L["dungeonJournalLootSpecAnchor"], anchorOptions, { "1", "2" }, function(_, _, key)
			addon.db["dungeonJournalLootSpecAnchor"] = tonumber(key) or 1
			if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
		end)
		anchorDropdown:SetValue(tostring(addon.db["dungeonJournalLootSpecAnchor"] or 1))
		if anchorDropdown.SetRelativeWidth then anchorDropdown:SetRelativeWidth(0.5) end
		anchorRow:AddChild(anchorDropdown)

		local sliderOffsetX = addon.functions.createSliderAce(
			L["dungeonJournalLootSpecOffsetX"] .. ": " .. addon.db["dungeonJournalLootSpecOffsetX"],
			addon.db["dungeonJournalLootSpecOffsetX"],
			-200,
			200,
			1,
			function(self, _, val)
				addon.db["dungeonJournalLootSpecOffsetX"] = val
				self:SetLabel(L["dungeonJournalLootSpecOffsetX"] .. ": " .. tostring(val))
				if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
			end
		)
		if sliderOffsetX.SetRelativeWidth then sliderOffsetX:SetRelativeWidth(0.5) end
		anchorRow:AddChild(sliderOffsetX)
		lootSpecGroup:AddChild(anchorRow)

		local offsetRow = addon.functions.createContainer("InlineGroup", "Flow")
		offsetRow:SetFullWidth(true)

		local sliderOffsetY = addon.functions.createSliderAce(
			L["dungeonJournalLootSpecOffsetY"] .. ": " .. addon.db["dungeonJournalLootSpecOffsetY"],
			addon.db["dungeonJournalLootSpecOffsetY"],
			-200,
			200,
			1,
			function(self, _, val)
				addon.db["dungeonJournalLootSpecOffsetY"] = val
				self:SetLabel(L["dungeonJournalLootSpecOffsetY"] .. ": " .. tostring(val))
				if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
			end
		)
		if sliderOffsetY.SetRelativeWidth then sliderOffsetY:SetRelativeWidth(0.5) end
		offsetRow:AddChild(sliderOffsetY)

		local sliderSpacing = addon.functions.createSliderAce(
			L["dungeonJournalLootSpecSpacing"] .. ": " .. addon.db["dungeonJournalLootSpecSpacing"],
			addon.db["dungeonJournalLootSpecSpacing"],
			0,
			40,
			1,
			function(self, _, val)
				addon.db["dungeonJournalLootSpecSpacing"] = val
				self:SetLabel(L["dungeonJournalLootSpecSpacing"] .. ": " .. tostring(val))
				if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
			end
		)
		if sliderSpacing.SetRelativeWidth then sliderSpacing:SetRelativeWidth(0.5) end
		offsetRow:AddChild(sliderSpacing)
		lootSpecGroup:AddChild(offsetRow)

		local scaleRow = addon.functions.createContainer("InlineGroup", "Flow")
		scaleRow:SetFullWidth(true)

		local sliderScale = addon.functions.createSliderAce(
			L["dungeonJournalLootSpecScale"] .. ": " .. string.format("%.2f", addon.db["dungeonJournalLootSpecScale"]),
			addon.db["dungeonJournalLootSpecScale"],
			0.5,
			2,
			0.05,
			function(self, _, val)
				addon.db["dungeonJournalLootSpecScale"] = val
				self:SetLabel(L["dungeonJournalLootSpecScale"] .. ": " .. string.format("%.2f", val))
				if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
			end
		)
		if sliderScale.SetRelativeWidth then sliderScale:SetRelativeWidth(0.5) end
		scaleRow:AddChild(sliderScale)

		local sliderZoom = addon.functions.createSliderAce(
			L["dungeonJournalLootSpecIconPadding"] .. ": " .. string.format("%.2f", addon.db["dungeonJournalLootSpecIconPadding"]),
			addon.db["dungeonJournalLootSpecIconPadding"],
			0,
			0.2,
			0.01,
			function(self, _, val)
				addon.db["dungeonJournalLootSpecIconPadding"] = val
				self:SetLabel(L["dungeonJournalLootSpecIconPadding"] .. ": " .. string.format("%.2f", val))
				if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
			end
		)
		if sliderZoom.SetRelativeWidth then sliderZoom:SetRelativeWidth(0.5) end
		scaleRow:AddChild(sliderZoom)
		lootSpecGroup:AddChild(scaleRow)

		local showAll = addon.functions.createCheckboxAce(L["dungeonJournalLootSpecShowAll"], addon.db["dungeonJournalLootSpecShowAll"], function(_, _, value)
			addon.db["dungeonJournalLootSpecShowAll"] = value
			if addon.DungeonJournalLootSpec then addon.DungeonJournalLootSpec:Refresh() end
		end, L["dungeonJournalLootSpecShowAllDesc"])
		if showAll.SetFullWidth then showAll:SetFullWidth(true) end
		lootSpecGroup:AddChild(showAll)

		if scroll.DoLayout then scroll:DoLayout() end
	end

	rebuildDungeonJournalLootSpec()

	scroll:DoLayout()
end

if addon.functions and addon.functions.RegisterOptionsPage then
	addon.functions.RegisterOptionsPage("items\001loot", addLootFrame)
	addon.functions.RegisterOptionsPage("items\001gear", addCharacterFrame)
	addon.functions.RegisterOptionsPage("items\001economy", addVendorMainFrame2)
end
