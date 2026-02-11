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
local LMain = LibStub("AceLocale-3.0"):GetLocale(parentAddonName)
local wipe = wipe
local listOrders = {
	vendorIncludeSellList = {},
	vendorExcludeSellList = {},
	vendorIncludeDestroyList = {},
}

local function applyParentSection(entries, section)
	for _, entry in ipairs(entries or {}) do
		entry.parentSection = section
		if entry.children then applyParentSection(entry.children, section) end
	end
end

local function isChecked(var)
	local entry = addon.SettingsLayout.elements and addon.SettingsLayout.elements[var]
	return entry and entry.setting and entry.setting:GetValue() == true
end

local function refreshSellMarks()
	if addon.Vendor and addon.Vendor.functions and addon.Vendor.functions.refreshSellMarks then addon.Vendor.functions.refreshSellMarks() end
end

local function refreshDestroyButton()
	if addon.Vendor and addon.Vendor.functions and addon.Vendor.functions.refreshDestroyButton then addon.Vendor.functions.refreshDestroyButton() end
end

local function syncBindFilters(quality, tabName)
	addon.Vendor.variables.itemBindTypeQualityFilter[quality] = addon.Vendor.variables.itemBindTypeQualityFilter[quality]
		or {
			[0] = true,
			[1] = true,
			[2] = true,
			[3] = true,
			[4] = false,
			[5] = false,
			[6] = false,
			[7] = true,
			[8] = true,
			[9] = true,
		}
	local tbl = addon.Vendor.variables.itemBindTypeQualityFilter[quality]
	tbl[2] = not addon.db["vendor" .. tabName .. "IgnoreBoE"]
	local allowWarbound = not addon.db["vendor" .. tabName .. "IgnoreWarbound"]
	tbl[7] = allowWarbound
	tbl[8] = allowWarbound
	tbl[9] = allowWarbound
end

local function parseItemID(input)
	if type(input) == "number" then return input end
	if type(input) == "string" then
		local id = tonumber(input)
		if id then return id end
		local linkID = input:match("item:(%d+)")
		if linkID then return tonumber(linkID) end
	end
	return nil
end

local function buildList(listKey)
	local list = {}
	local order = listOrders[listKey]
	if order then
		wipe(order)
	else
		order = {}
	end
	for id, name in pairs(addon.db[listKey] or {}) do
		local key = tostring(id)
		list[key] = string.format("%s (%s)", name or key, key)
		table.insert(order, key)
	end
	table.sort(order, function(a, b) return list[a] < list[b] end)
	return list
end

local function addItemToList(listKey, id)
	if not id then return end
	addon.db[listKey] = addon.db[listKey] or {}
	local item = Item:CreateFromItemID(id)
	if not item or item:IsItemEmpty() then return end
	item:ContinueOnItemLoad(function()
		local resolvedID = item:GetItemID()
		local name = item:GetItemName() or ("Item #" .. tostring(resolvedID or id))
		addon.db[listKey][resolvedID] = name
		if listKey == "vendorIncludeSellList" and addon.db["vendorIncludeDestroyList"] then addon.db["vendorIncludeDestroyList"][resolvedID] = nil end
		if listKey == "vendorIncludeDestroyList" and addon.db["vendorIncludeSellList"] then addon.db["vendorIncludeSellList"][resolvedID] = nil end
		refreshSellMarks()
		refreshDestroyButton()
	end)
end

local function removeItemFromList(listKey, value)
	local id = tonumber(value)
	if not id then return end
	addon.db[listKey] = addon.db[listKey] or {}
	if addon.db[listKey][id] then
		addon.db[listKey][id] = nil
		refreshSellMarks()
		refreshDestroyButton()
	end
end

local function clearDropdownSelection(var)
	local entry = addon.SettingsLayout.elements and addon.SettingsLayout.elements[var]
	if entry and entry.setting then entry.setting:SetValue("") end
end

local function showAddPopup(dialogKey, prompt, listKey)
	StaticPopupDialogs[dialogKey] = StaticPopupDialogs[dialogKey]
		or {
			text = prompt,
			button1 = OKAY,
			button2 = CANCEL,
			hasEditBox = true,
			maxLetters = 10,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
			OnShow = function(self)
				local editBox = self.editBox or self.GetEditBox and self:GetEditBox()
				if editBox then
					editBox:SetText("")
					editBox:SetFocus()
				end
			end,
			OnAccept = function(self)
				local editBox = self.editBox or self.GetEditBox and self:GetEditBox()
				local text = editBox and editBox:GetText()
				local id = parseItemID(text)
				if not id then return end
				addItemToList(listKey, id)
			end,
		}
	StaticPopupDialogs[dialogKey].text = prompt
	StaticPopup_Show(dialogKey)
end

local function showRemovePopup(dialogKey, prompt, listKey, label, id)
	StaticPopupDialogs[dialogKey] = StaticPopupDialogs[dialogKey]
		or {
			text = prompt,
			button1 = ACCEPT,
			button2 = CANCEL,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
		}
	StaticPopupDialogs[dialogKey].text = prompt
	StaticPopupDialogs[dialogKey].OnAccept = function(_, data) removeItemFromList(listKey, data) end

	StaticPopup_Show(dialogKey, label, nil, id)
end

local function buildSettings()
	local cVendor = addon.SettingsLayout.rootECONOMY
	addon.SettingsLayout.vendorCategory = cVendor

	local quickActionsExpandable = addon.functions.SettingsCreateExpandableSection(cVendor, {
		name = L["vendorQuickActions"] or "Vendor - Quick Actions",
		expanded = false,
		colorizeTitle = false,
	})

	local generalCheckboxes = {
		{
			var = "sellAllJunk",
			text = (LMain and LMain["sellAllJunk"]) or "Automatically sell all junk items",
			desc = (LMain and LMain["sellAllJunkDesc"]) or "Sells all poor-quality items whenever a merchant window opens",
			func = function(value)
				addon.db["sellAllJunk"] = value and true or false
				if value then addon.functions.checkBagIgnoreJunk() end
			end,
		},
		{
			var = "vendorSwapAutoSellShift",
			text = L["vendorSwapAutoSellShift"],
			func = function(value) addon.db["vendorSwapAutoSellShift"] = value and true or false end,
		},
		{
			var = "vendorOnly12Items",
			text = L["vendorOnly12Items"],
			desc = L["vendorOnly12ItemsDesc"],
			func = function(value) addon.db["vendorOnly12Items"] = value and true or false end,
		},
		{
			var = "vendorAltClickInclude",
			text = L["vendorAltClickInclude"],
			desc = L["vendorAltClickIncludeDesc"],
			func = function(value) addon.db["vendorAltClickInclude"] = value and true or false end,
		},
		{
			var = "vendorShowSellTooltip",
			text = L["vendorShowSellTooltip"],
			func = function(value) addon.db["vendorShowSellTooltip"] = value and true or false end,
		},
		{
			var = "vendorShowSellOverlay",
			text = L["vendorShowSellOverlay"],
			func = function(value)
				addon.db["vendorShowSellOverlay"] = value and true or false
				refreshSellMarks()
			end,
			children = {
				{
					var = "vendorShowSellHighContrast",
					text = L["vendorShowSellHighContrast"],
					func = function(value)
						addon.db["vendorShowSellHighContrast"] = value and true or false
						refreshSellMarks()
					end,
					parentCheck = function() return isChecked("vendorShowSellOverlay") end,
					parent = true,
					type = Settings.VarType.Boolean,
					sType = "checkbox",
				},
			},
		},
	}
	applyParentSection(generalCheckboxes, quickActionsExpandable)
	addon.functions.SettingsCreateCheckboxes(cVendor, generalCheckboxes)

	local autoSellExpandable = addon.functions.SettingsCreateExpandableSection(cVendor, {
		name = L["vendorAutoSellRules"] or "Vendor - Auto-Sell Rules",
		expanded = false,
		colorizeTitle = false,
	})

	local qualities = {
		{ q = 0, key = "Poor" },
		{ q = 1, key = "Common" },
		{ q = 2, key = "Uncommon" },
		{ q = 3, key = "Rare" },
		{ q = 4, key = "Epic" },
	}

	local expansions = {}
	for i = 0, LE_EXPANSION_LEVEL_CURRENT do
		table.insert(expansions, { value = i, text = _G["EXPANSION_NAME" .. i] or tostring(i) })
	end

	for _, info in ipairs(qualities) do
		local quality = info.q
		local tabName = addon.Vendor.variables.tabNames[quality]
		local colorHex = ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].hex or ""
		local label = _G["ITEM_QUALITY" .. quality .. "_DESC"] or tabName
		addon.functions.SettingsCreateText(cVendor, string.format("%s%s|r", colorHex, label), { parentSection = autoSellExpandable })

		local enable = addon.functions.SettingsCreateCheckbox(cVendor, {
			var = "vendor" .. tabName .. "Enable",
			text = L["vendorEnable"]:format(colorHex .. label .. "|r"),
			func = function(value)
				addon.db["vendor" .. tabName .. "Enable"] = value and true or false
				addon.Vendor.variables.itemQualityFilter[quality] = addon.db["vendor" .. tabName .. "Enable"]
				if quality == 0 and addon.db["vendor" .. tabName .. "Enable"] then
					addon.db["sellAllJunk"] = false
					local sellAllJunkEntry = addon.SettingsLayout and addon.SettingsLayout.elements and addon.SettingsLayout.elements["sellAllJunk"]
					if sellAllJunkEntry and sellAllJunkEntry.setting then sellAllJunkEntry.setting:SetValue(false) end
				end
				refreshSellMarks()
			end,
			default = addon.db["vendor" .. tabName .. "Enable"],
			parentSection = autoSellExpandable,
		})

		local function parentCheck() return isChecked("vendor" .. tabName .. "Enable") end

		local qualityCheckboxes = {
			{
				var = "vendor" .. tabName .. "AbsolutIlvl",
				text = L["vendorAbsolutIlvl"],
				func = function(value)
					addon.db["vendor" .. tabName .. "AbsolutIlvl"] = value and true or false
					refreshSellMarks()
				end,
				parent = true,
				element = enable.element,
				parentCheck = parentCheck,
			},
			{
				var = "vendor" .. tabName .. "IgnoreBoE",
				text = L["vendorIgnoreBoE"],
				func = function(value)
					addon.db["vendor" .. tabName .. "IgnoreBoE"] = value and true or false
					syncBindFilters(quality, tabName)
					refreshSellMarks()
				end,
				parent = true,
				element = enable.element,
				parentCheck = parentCheck,
			},
			{
				var = "vendor" .. tabName .. "IgnoreWarbound",
				text = L["vendorIgnoreWarbound"],
				func = function(value)
					addon.db["vendor" .. tabName .. "IgnoreWarbound"] = value and true or false
					syncBindFilters(quality, tabName)
					refreshSellMarks()
				end,
				parent = true,
				element = enable.element,
				parentCheck = parentCheck,
			},
		}

		addon.functions.SettingsCreateSlider(cVendor, {
			var = "vendor" .. tabName .. "MinIlvlDif",
			text = addon.db["vendor" .. tabName .. "AbsolutIlvl"] and L["vendorMinIlvl"] or L["vendorMinIlvlDif"],
			get = function() return addon.db["vendor" .. tabName .. "MinIlvlDif"] or 200 end,
			set = function(value)
				value = math.floor(tonumber(value) or 0)
				addon.db["vendor" .. tabName .. "MinIlvlDif"] = value
				refreshSellMarks()
			end,
			min = 1,
			max = 700,
			step = 1,
			parent = true,
			element = enable.element,
			parentCheck = parentCheck,
			default = 200,
			parentSection = autoSellExpandable,
		})

		if quality > 1 then
			table.insert(qualityCheckboxes, {
				var = "vendor" .. tabName .. "IgnoreUpgradable",
				text = L["vendorIgnoreUpgradable"],
				func = function(value)
					addon.db["vendor" .. tabName .. "IgnoreUpgradable"] = value and true or false
					refreshSellMarks()
				end,
				parent = true,
				element = enable.element,
				parentCheck = parentCheck,
			})
		end

		if quality == 4 then
			table.insert(qualityCheckboxes, {
				var = "vendor" .. tabName .. "IgnoreHeroicTrack",
				text = L["vendorIgnoreHeroicTrack"],
				func = function(value)
					addon.db["vendor" .. tabName .. "IgnoreHeroicTrack"] = value and true or false
					refreshSellMarks()
				end,
				parent = true,
				element = enable.element,
				parentCheck = parentCheck,
			})
			table.insert(qualityCheckboxes, {
				var = "vendor" .. tabName .. "IgnoreMythTrack",
				text = L["vendorIgnoreMythTrack"],
				func = function(value)
					addon.db["vendor" .. tabName .. "IgnoreMythTrack"] = value and true or false
					refreshSellMarks()
				end,
				parent = true,
				element = enable.element,
				parentCheck = parentCheck,
			})
		end

		applyParentSection(qualityCheckboxes, autoSellExpandable)
		addon.functions.SettingsCreateCheckboxes(cVendor, qualityCheckboxes)

		if quality > 0 then
			addon.functions.SettingsCreateMultiDropdown(cVendor, {
				var = "vendor" .. tabName .. "CraftingExpansions",
				text = L["vendorCraftingExpansions"],
				parent = true,
				element = enable.element,
				parentCheck = parentCheck,
				options = expansions,
				isSelectedFunc = function(value)
					local store = addon.db["vendor" .. tabName .. "CraftingExpansions"]
					return store and store[value] == true
				end,
				setSelectedFunc = function(value, selected)
					addon.db["vendor" .. tabName .. "CraftingExpansions"] = addon.db["vendor" .. tabName .. "CraftingExpansions"] or {}
					addon.db["vendor" .. tabName .. "CraftingExpansions"][value] = selected or nil
					refreshSellMarks()
				end,
				parentSection = autoSellExpandable,
			})
		end

		syncBindFilters(quality, tabName)
		addon.Vendor.variables.itemQualityFilter[quality] = addon.db["vendor" .. tabName .. "Enable"]
	end

	local includeExcludeExpandable = addon.functions.SettingsCreateExpandableSection(cVendor, {
		name = L["vendorIncludeExclude"] or "Vendor - Include / Exclude",
		expanded = false,
		colorizeTitle = false,
	})

	addon.functions.SettingsCreateHeadline(cVendor, L["Include"] or "Include", { parentSection = includeExcludeExpandable })
	addon.functions.SettingsCreateText(cVendor, L["vendorAddItemToInclude"], { parentSection = includeExcludeExpandable })
	addon.functions.SettingsCreateButton(cVendor, {
		var = "vendorIncludeAdd",
		text = ADD,
		func = function() showAddPopup("EQOL_VENDOR_INCLUDE_ADD", L["vendorAddItemToInclude"], "vendorIncludeSellList") end,
		parentSection = includeExcludeExpandable,
	})

	addon.functions.SettingsCreateScrollDropdown(cVendor, {
		var = "vendorIncludeRemove",
		text = REMOVE,
		listFunc = function() return buildList("vendorIncludeSellList") end,
		order = listOrders.vendorIncludeSellList,
		default = "",
		get = function() return "" end,
		set = function(value)
			if not value or value == "" then return end
			local id = tonumber(value)
			if not id then return end
			addon.db.vendorIncludeSellList = addon.db.vendorIncludeSellList or {}
			local label = addon.db.vendorIncludeSellList[id] or tostring(id)
			showRemovePopup("EQOL_VENDOR_INCLUDE_REMOVE", L["vendorIncludeRemoveConfirm"], "vendorIncludeSellList", label, id)
			clearDropdownSelection("vendorIncludeRemove")
		end,
		parentSection = includeExcludeExpandable,
	})

	addon.functions.SettingsCreateHeadline(cVendor, L["Exclude"] or "Exclude", { parentSection = includeExcludeExpandable })
	addon.functions.SettingsCreateText(cVendor, L["vendorAddItemToExclude"], { parentSection = includeExcludeExpandable })
	addon.functions.SettingsCreateButton(cVendor, {
		var = "vendorExcludeAdd",
		text = ADD,
		func = function() showAddPopup("EQOL_VENDOR_EXCLUDE_ADD", L["vendorAddItemToExclude"], "vendorExcludeSellList") end,
		parentSection = includeExcludeExpandable,
	})

	addon.functions.SettingsCreateScrollDropdown(cVendor, {
		var = "vendorExcludeRemove",
		text = REMOVE,
		listFunc = function() return buildList("vendorExcludeSellList") end,
		order = listOrders.vendorExcludeSellList,
		default = "",
		get = function() return "" end,
		set = function(value)
			if not value or value == "" then return end
			local id = tonumber(value)
			if not id then return end
			addon.db.vendorExcludeSellList = addon.db.vendorExcludeSellList or {}
			local label = addon.db.vendorExcludeSellList[id] or tostring(id)
			showRemovePopup("EQOL_VENDOR_EXCLUDE_REMOVE", L["vendorExcludeRemoveConfirm"], "vendorExcludeSellList", label, id)
			clearDropdownSelection("vendorExcludeRemove")
		end,
		parentSection = includeExcludeExpandable,
	})

	local destroyQueueExpandable = addon.functions.SettingsCreateExpandableSection(cVendor, {
		name = L["vendorDestroyQueue"] or "Vendor - Destroy Queue",
		expanded = false,
		colorizeTitle = false,
	})

	local destroySection = destroyQueueExpandable

	local destroyChildren = {
		{
			var = "vendorShowDestroyOverlay",
			text = L["vendorShowDestroyOverlay"],
			func = function(value)
				addon.db["vendorShowDestroyOverlay"] = value and true or false
				refreshSellMarks()
			end,
			parent = true,
			parentCheck = function() return isChecked("vendorDestroyEnable") end,
			type = Settings.VarType.Boolean,
			sType = "checkbox",
		},
		{
			var = "vendorDestroyShowMessages",
			text = L["vendorDestroyShowMessages"],
			desc = L["vendorDestroyShowMessagesDesc"],
			func = function(value) addon.db["vendorDestroyShowMessages"] = value and true or false end,
			parent = true,
			parentCheck = function() return isChecked("vendorDestroyEnable") end,
			type = Settings.VarType.Boolean,
			sType = "checkbox",
		},
		{
			sType = "hint",
			text = L["vendorDestroyManualHint"],
			parent = true,
			parentCheck = function() return isChecked("vendorDestroyEnable") end,
		},
		{
			var = "vendorDestroyAdd",
			text = ADD,
			sType = "button",
			parent = true,
			parentCheck = function() return isChecked("vendorDestroyEnable") end,
			isEnabled = function() return isChecked("vendorDestroyEnable") end,
			func = function()
				if not isChecked("vendorDestroyEnable") then return end
				showAddPopup("EQOL_VENDOR_DESTROY_ADD", L["vendorDestroyManualHint"], "vendorIncludeDestroyList")
			end,
		},
		{
			var = "vendorDestroyRemove",
			text = L["vendorDestroyRemove"],
			sType = "scrolldropdown",
			parent = true,
			parentCheck = function() return isChecked("vendorDestroyEnable") end,
			listFunc = function() return buildList("vendorIncludeDestroyList") end,
			order = listOrders.vendorIncludeDestroyList,
			default = "",
			get = function() return "" end,
			set = function(value) removeItemFromList("vendorIncludeDestroyList", value) end,
		},
	}
	local destroyEntries = {
		{
			var = "vendorDestroyEnable",
			text = L["vendorDestroyEnable"],
			desc = L["vendorDestroyEnableDesc"],
			func = function(value)
				addon.db["vendorDestroyEnable"] = value and true or false
				refreshSellMarks()
				refreshDestroyButton()
			end,
			default = false,
			children = destroyChildren,
		},
	}
	applyParentSection(destroyEntries, destroySection)
	addon.functions.SettingsCreateCheckboxes(cVendor, destroyEntries)
end

function addon.Vendor.functions.InitSettings()
	if addon.Vendor.variables.settingsBuilt then return end
	if not addon.db or not addon.functions or not addon.functions.SettingsCreateCategory then return end
	buildSettings()
	addon.Vendor.variables.settingsBuilt = true
end
