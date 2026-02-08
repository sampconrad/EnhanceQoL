local addonName, addon = ...

local AceGUI = LibStub("AceGUI-3.0")

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")

local GetContainerItemInfo = C_Container.GetContainerItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetItemInfo = C_Item.GetItemInfo
local GetBagItem = C_TooltipInfo.GetBagItem
local IsEquippableItem = C_Item.IsEquippableItem
local UnitInParty = UnitInParty
local UnitInRaid = UnitInRaid
addon.functions = addon.functions or {}

local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax
local UnitHealthPercent = UnitHealthPercent
local UnitPowerPercent = UnitPowerPercent

function addon.functions.InitDBValue(key, defaultValue)
	if addon.db[key] == nil then addon.db[key] = defaultValue end
end

function addon.functions.getIDFromGUID(unitId)
	if not unitId then return nil end
	if issecretvalue(unitId) then return nil end
	if type(unitId) ~= "string" then return nil end
	local _, _, _, _, _, npcID = strsplit("-", unitId)
	return tonumber(npcID)
end

-- Global helper: detect Timerunner (Timerunning Season active)
-- Safe-guard for older clients without the API
function addon.functions.IsTimerunner()
	local fn = _G and _G.PlayerGetTimerunningSeasonID
	if type(fn) == "function" then return fn() ~= nil end
	return false
end

local function canChangeProtectedVisibility(frame)
	if not frame then return false end
	if InCombatLockdown and InCombatLockdown() then
		if frame.IsProtected and frame:IsProtected() then return false end
	end
	return true
end

function addon.functions.toggleRaidTools(value, self)
	if not self then return end
	local inParty = UnitInParty("player")
	local inRaid = UnitInRaid("player")
	local inGroup = inParty or inRaid
	local hideInParty = value == true and inParty and not inRaid

	if not inGroup then
		if self._eqolRaidToolsAlphaHidden and self.SetAlpha then
			self._eqolRaidToolsAlphaHidden = nil
			self:SetAlpha(1)
		end
		return
	end

	if hideInParty then
		if canChangeProtectedVisibility(self) then
			if self.Hide then self:Hide() end
		elseif self.SetAlpha then
			self._eqolRaidToolsAlphaHidden = true
			self:SetAlpha(0)
		end
	else
		if self._eqolRaidToolsAlphaHidden and self.SetAlpha then
			self._eqolRaidToolsAlphaHidden = nil
			self:SetAlpha(1)
		end
		if canChangeProtectedVisibility(self) then
			if self.Show then self:Show() end
		elseif self.SetAlpha then
			self:SetAlpha(1)
		end
	end
end

function addon.functions.updateRaidToolsHook()
	local manager = _G.CompactRaidFrameManager
	if not manager or not manager.SetScript then return end
	if addon.db and addon.db["hideRaidTools"] then
		if not manager._eqolRaidToolsOnShowHooked then
			manager:SetScript("OnShow", function(self) addon.functions.toggleRaidTools(addon.db["hideRaidTools"], self) end)
			manager._eqolRaidToolsOnShowHooked = true
		end
		addon.functions.toggleRaidTools(addon.db["hideRaidTools"], manager)
	elseif manager._eqolRaidToolsOnShowHooked then
		manager:SetScript("OnShow", nil)
		manager._eqolRaidToolsOnShowHooked = nil
		if manager._eqolRaidToolsAlphaHidden and manager.SetAlpha then
			manager._eqolRaidToolsAlphaHidden = nil
			manager:SetAlpha(1)
		end
	end
end

local function safeUnitHealthPercent(unit, usePredicted, curve)
	if not UnitHealthPercent or not unit then return nil end
	local predicted = usePredicted
	if predicted == nil then predicted = true end
	curve = curve or (CurveConstants and CurveConstants.ScaleTo100)
	if curve then
		local ok, pct = pcall(UnitHealthPercent, unit, predicted, curve)
		if ok and pct ~= nil then return pct end
	end
	local ok, pct = pcall(UnitHealthPercent, unit, predicted)
	if ok and pct ~= nil then return pct end
	return nil
end

function addon.functions.GetHealthPercent(unit, cur, max, usePredicted, curve)
	if not unit then return 0 end
	local pct = safeUnitHealthPercent(unit, usePredicted, curve)
	if pct ~= nil then return pct end
	cur = cur or (UnitHealth and UnitHealth(unit)) or 0
	max = max or (UnitHealthMax and UnitHealthMax(unit)) or 0
	if max > 0 then return (cur / max) * 100 end
	return 0
end

local function safeUnitPowerPercent(unit, powerType, useUnmodified, curve)
	if not UnitPowerPercent or not unit then return nil end
	local unmodified = useUnmodified
	if unmodified == nil then unmodified = true end
	powerType = powerType or 0
	curve = curve or (CurveConstants and CurveConstants.ScaleTo100)
	if curve then
		local ok, pct = pcall(UnitPowerPercent, unit, powerType, unmodified, curve)
		if ok and pct ~= nil then return pct end
	end
	local ok, pct = pcall(UnitPowerPercent, unit, powerType, unmodified)
	if ok and pct ~= nil then return pct end
	return nil
end

function addon.functions.GetPowerPercent(unit, powerType, cur, max, useUnmodified, curve)
	if not unit then return 0 end
	powerType = powerType or 0
	local pct = safeUnitPowerPercent(unit, powerType, useUnmodified, curve)
	if pct ~= nil then return pct end
	cur = cur or (UnitPower and UnitPower(unit, powerType)) or 0
	max = max or (UnitPowerMax and UnitPowerMax(unit, powerType)) or 0
	if max > 0 then return (cur / max) * 100 end
	return 0
end

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

function addon.functions.formatMoney(copper, type)
	local COPPER_PER_SILVER = 100
	local COPPER_PER_GOLD = 10000

	local gold = math.floor(copper / COPPER_PER_GOLD)
	local silver = math.floor((copper % COPPER_PER_GOLD) / COPPER_PER_SILVER)
	local bronze = copper % COPPER_PER_SILVER

	local parts = {}

	if gold > 0 then table.insert(parts, string.format("%s%s", BreakUpLargeNumbers(gold), GOLD_ICON)) end
	if nil == type or (type and type == "tracker" and addon.db["showOnlyGoldOnMoney"] == false) then
		if gold > 0 or silver > 0 then table.insert(parts, string.format("%02d%s", silver, SILVER_ICON)) end
		table.insert(parts, string.format("%02d%s", bronze, COPPER_ICON))
	end

	return table.concat(parts, " ")
end

function addon.functions.toggleLandingPageButton(title, state)
	local button = _G["ExpansionLandingPageMinimapButton"] -- Hole den Button
	if not button then return end

	-- Prüfen, ob der Button zu der gewünschten ID passt
	if button.title == title then
		if state then
			button:Hide()
		else
			button:Show()
		end
	end
end

function addon.functions.prepareListForDropdown(tList, sortKey)
	local order = {}
	local sortedList = {}
	-- Tabelle in eine Liste umwandeln
	for key, value in pairs(tList) do
		table.insert(sortedList, { key = key, value = value })
	end
	-- Sortieren nach `value`
	if sortKey then
		table.sort(sortedList, function(a, b) return a.key < b.key end)
	else
		table.sort(sortedList, function(a, b) return a.value < b.value end)
	end
	-- Zurückkonvertieren für SetList
	local dropdownList = {}
	for _, item in ipairs(sortedList) do
		dropdownList[item.key] = item.value
		table.insert(order, item.key)
	end
	return dropdownList, order
end

function addon.functions.createContainer(type, layout)
	local element = AceGUI:Create(type)
	element:SetFullWidth(true)
	if layout then element:SetLayout(layout) end
	return element
end

function addon.functions.createCheckboxAce(text, value, callBack, description)
	local checkbox = AceGUI:Create("CheckBox")

	checkbox:SetLabel(text)
	checkbox:SetValue(value)
	checkbox:SetCallback("OnValueChanged", callBack)
	checkbox:SetFullWidth(true)
	if description then checkbox:SetDescription("|cffffd700" .. tostring(description) .. "|r ") end

	return checkbox
end

function addon.functions.createEditboxAce(label, text, OnEnterPressed, OnTextChanged)
	local editbox = AceGUI:Create("EditBox")

	editbox:SetLabel(label)
	if text then editbox:SetText(text) end
	if OnEnterPressed then editbox:SetCallback("OnEnterPressed", OnEnterPressed) end
	if OnTextChanged then editbox:SetCallback("OnTextChanged", OnTextChanged) end
	return editbox
end

function addon.functions.createSliderAce(text, value, min, max, step, callBack)
	local slider = AceGUI:Create("Slider")

	slider:SetLabel(text)
	slider:SetValue(value)
	slider:SetSliderValues(min, max, step)
	if callBack then slider:SetCallback("OnValueChanged", callBack) end
	slider:SetFullWidth(true)

	return slider
end

function addon.functions.createSpacerAce()
	local spacer = addon.functions.createLabelAce(" ")
	spacer:SetFullWidth(true)
	return spacer
end

function addon.functions.getHeightOffset(element)
	local _, _, _, _, headerY = element:GetPoint()
	return headerY - element:GetHeight()
end

function addon.functions.createLabelAce(text, color, font, fontSize)
	if nil == fontSize then fontSize = 12 end
	local label = AceGUI:Create("Label")

	label:SetText(text)
	if color then label:SetColor(color.r, color.g, color.b) end

	label:SetFont(font or addon.variables.defaultFont, fontSize, "OUTLINE")
	return label
end

function addon.functions.createButtonAce(text, width, callBack)
	local button = AceGUI:Create("Button")
	button:SetText(text)
	button:SetWidth(width or 100)
	if callBack then button:SetCallback("OnClick", callBack) end
	return button
end

function addon.functions.createDropdownAce(text, list, order, callBack)
	local dropdown = AceGUI:Create("Dropdown")
	dropdown:SetLabel(text or "")

	if order then
		dropdown:SetList(list, order)
	else
		dropdown:SetList(list)
	end
	dropdown:SetFullWidth(true)
	if callBack then dropdown:SetCallback("OnValueChanged", callBack) end
	return dropdown
end

function addon.functions.createWrapperData(data, container, L)
	local sortedParents = {}
	for _, checkbox in ipairs(data) do
		if not sortedParents[checkbox.parent] then sortedParents[checkbox.parent] = {} end
		table.insert(sortedParents[checkbox.parent], checkbox)
	end

	local sortedParentKeys = {}
	for parent in pairs(sortedParents) do
		table.insert(sortedParentKeys, parent)
	end
	table.sort(sortedParentKeys)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Fill")
	wrapper:SetFullWidth(true)
	wrapper:SetFullHeight(true)
	container:AddChild(wrapper)

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	wrapper:AddChild(scroll)

	local scrollInner = addon.functions.createContainer("SimpleGroup", "Flow")
	scrollInner:SetFullWidth(true)
	scrollInner:SetFullHeight(true)
	scroll:AddChild(scrollInner)

	for _, parent in ipairs(sortedParentKeys) do
		local groupData = sortedParents[parent]

		table.sort(groupData, function(a, b)
			local textA = a.text or L[a.var]
			local textB = b.text or L[b.var]
			return textA < textB
		end)

		local group = AceGUI:Create("InlineGroup")
		group:SetLayout("List")
		group:SetFullWidth(true)
		group:SetTitle(parent)
		scrollInner:AddChild(group)

		-- Stable ordering: prefer displayOrder if provided, else by label text
		table.sort(groupData, function(a, b)
			local ao, bo = a.displayOrder, b.displayOrder
			if ao ~= nil or bo ~= nil then
				if ao == nil then ao = math.huge end
				if bo == nil then bo = math.huge end
				if ao ~= bo then return ao < bo end
			end
			local textA = a.text or L[a.var] or ""
			local textB = b.text or L[b.var] or ""
			return textA < textB
		end)

		for _, checkboxData in ipairs(groupData) do
			local widget = AceGUI:Create(checkboxData.type)

			if checkboxData.type == "CheckBox" then
				widget:SetLabel(checkboxData.text or L[checkboxData.var])
				widget:SetValue(checkboxData.value or addon.db[checkboxData.var])
				widget:SetCallback("OnValueChanged", checkboxData.callback)
				widget:SetFullWidth(true)
				group:AddChild(widget)

				if checkboxData.desc then
					local subtext = AceGUI:Create("Label")
					subtext:SetText(string.format("|cffffd700" .. checkboxData.desc .. "|r "))
					subtext:SetFont(addon.variables.defaultFont, 10, "OUTLINE")
					subtext:SetFullWidth(true)
					subtext:SetColor(1, 1, 1)
					group:AddChild(subtext)
				end
			elseif checkboxData.type == "Button" then
				widget:SetText(checkboxData.text)
				widget:SetWidth(checkboxData.width or 100)
				if checkboxData.callback then widget:SetCallback("OnClick", checkboxData.callback) end
				group:AddChild(widget)
			elseif checkboxData.type == "Label" then
				widget = AceGUI:Create("Label")
				widget:SetText(checkboxData.text or (checkboxData.var and L[checkboxData.var]) or "")
				widget:SetFont(addon.variables.defaultFont, 12, "OUTLINE")
				widget:SetFullWidth(true)
				group:AddChild(widget)
			elseif checkboxData.type == "Dropdown" then
				widget:SetLabel(checkboxData.text or "")
				if checkboxData.order then
					widget:SetList(checkboxData.list, checkboxData.order)
				else
					widget:SetList(checkboxData.list)
				end
				widget:SetFullWidth(true)
				if checkboxData.callback then widget:SetCallback("OnValueChanged", checkboxData.callback) end
				group:AddChild(widget)
				if checkboxData.value then widget:SetValue(checkboxData.value) end
				if checkboxData.relWidth then widget:SetRelativeWidth(checkboxData.relWidth) end
			elseif checkboxData.type == "ColorPicker" then
				widget = AceGUI:Create("ColorPicker")
				widget:SetLabel(checkboxData.text or "")
				local c = checkboxData.value or { r = 1, g = 1, b = 1 }
				widget:SetColor(c.r or 1, c.g or 1, c.b or 1)
				widget:SetCallback("OnValueChanged", function(_, _, r, g, b)
					if checkboxData.callback then checkboxData.callback(r, g, b) end
				end)
				group:AddChild(widget)
			elseif checkboxData.type == "Slider" then
				widget = AceGUI:Create("Slider")
				local value = checkboxData.value or 0
				local labelBase = checkboxData.text or ""
				local labelFormatter = checkboxData.labelFormatter
				local function setLabel(val)
					if checkboxData.showValue == false then
						widget:SetLabel(labelBase)
					else
						local formatted = val
						if labelFormatter then formatted = labelFormatter(val) end
						widget:SetLabel(string.format("%s: %s", labelBase, tostring(formatted)))
					end
				end
				setLabel(value)
				widget:SetValue(value)
				widget:SetSliderValues(checkboxData.min or 0, checkboxData.max or 100, checkboxData.step or 1)
				widget:SetFullWidth(true)
				widget:SetCallback("OnValueChanged", function(self, _, val)
					setLabel(val)
					if checkboxData.callback then checkboxData.callback(self, _, val) end
				end)
				group:AddChild(widget)
			end
			if checkboxData.gv then addon.elements[checkboxData.gv] = widget end
		end
	end
	scroll:DoLayout()
	scrollInner:DoLayout()
	return wrapper
end

local tooltipCache = {}
function addon.functions.clearTooltipCache() wipe(tooltipCache) end
local function getTooltipInfo(bag, slot, classID, tBindType)
	local key = bag .. "_" .. slot
	local cached = tooltipCache[key]
	if cached then return cached[1], cached[2], cached[3], cached[4] end

	local bType, bKey, upgradeKey, bAuc
	local data = C_TooltipInfo.GetBagItem(bag, slot)
	if data and data.lines then
		for i, v in pairs(data.lines) do
			if v.type == 20 then
				bAuc = true
				if v.leftText == ITEM_BIND_ON_EQUIP then
					bType = "BoE"
					bKey = "boe"
					bAuc = false
				elseif v.leftText == ITEM_ACCOUNTBOUND_UNTIL_EQUIP or v.leftText == ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP then
					bType = "WuE"
					bKey = "wue"
				elseif v.leftText == ITEM_ACCOUNTBOUND or v.leftText == ITEM_BIND_TO_BNETACCOUNT then
					bType = "WB"
					bKey = "wb"
				end
			elseif v.type == 42 then
				local text = v.rightText or v.leftText
				if text then
					local tier = text:gsub(".+:%s?", ""):gsub("%s?%d/%d", "")
					if tier then upgradeKey = string.lower(tier) end
				end
			elseif v.type == 0 and v.leftText == ITEM_CONJURED then
				bAuc = true
			end
		end
	end

	-- Check for recipe
	if classID == 9 and (bAuc == true and tBindType == 0) then bAuc = false end

	tooltipCache[key] = { bType, bKey, upgradeKey, bAuc }
	return bType, bKey, upgradeKey, bAuc
end

local bagIlvlAnchors = {
	TOPLEFT = { point = "TOPLEFT", x = 2, y = -2 },
	TOP = { point = "TOP", x = 0, y = -2 },
	TOPRIGHT = { point = "TOPRIGHT", x = 0, y = -2 },
	LEFT = { point = "LEFT", x = 2, y = 0 },
	CENTER = { point = "CENTER", x = 0, y = 0 },
	RIGHT = { point = "RIGHT", x = 0, y = 0 },
	BOTTOMLEFT = { point = "BOTTOMLEFT", x = 2, y = 2 },
	BOTTOM = { point = "BOTTOM", x = 0, y = 2 },
	BOTTOMRIGHT = { point = "BOTTOMRIGHT", x = 0, y = 2 },
}

local bagUpgradeAnchors = {
	TOPLEFT = { point = "TOPLEFT", x = 1, y = -1 },
	TOPRIGHT = { point = "TOPRIGHT", x = -1, y = -1 },
	BOTTOMLEFT = { point = "BOTTOMLEFT", x = 1, y = 1 },
	BOTTOMRIGHT = { point = "BOTTOMRIGHT", x = -1, y = 1 },
}

local UPGRADE_ICON_PATH = "Interface\\AddOns\\EnhanceQoL\\Icons\\upgradeilvl.tga"
local UPGRADE_ICON_SIZE = 22
local UPGRADE_ICON_GLOW_SIZE = 24

function addon.functions.ApplyBagItemLevelPosition(target, anchorFrame, position)
	if not target or not anchorFrame then return end
	local anchor = bagIlvlAnchors[position] or bagIlvlAnchors.TOPRIGHT
	target:ClearAllPoints()
	target:SetPoint(anchor.point, anchorFrame, anchor.point, anchor.x, anchor.y)
end

local function resolveBoundAnchor(position)
	if position == "BOTTOMLEFT" then
		return "TOPLEFT"
	elseif position == "BOTTOMRIGHT" then
		return "TOPRIGHT"
	elseif position == "BOTTOM" then
		return "TOP"
	elseif position == "LEFT" then
		return "TOPRIGHT"
	elseif position == "TOPLEFT" or position == "TOPRIGHT" or position == "TOP" then
		return "BOTTOMLEFT"
	elseif position == "RIGHT" then
		return "BOTTOMLEFT"
	else
		return "BOTTOMLEFT"
	end
end

function addon.functions.ApplyBagBoundPosition(target, anchorFrame, position)
	if not target or not anchorFrame then return end
	local anchor = bagIlvlAnchors[resolveBoundAnchor(position)] or bagIlvlAnchors.BOTTOMLEFT
	target:ClearAllPoints()
	target:SetPoint(anchor.point, anchorFrame, anchor.point, anchor.x, anchor.y)
end

function addon.functions.ApplyBagUpgradeIconPosition(target, anchorFrame, position)
	if not target or not anchorFrame then return end
	local anchor = bagUpgradeAnchors[position] or bagUpgradeAnchors.BOTTOMRIGHT
	target:ClearAllPoints()
	target:SetPoint(anchor.point, anchorFrame, anchor.point, anchor.x, anchor.y)
end

function addon.functions.AlignUpgradeIconGlow(glow, icon)
	if not glow or not icon then return end
	glow:ClearAllPoints()
	glow:SetPoint("CENTER", icon, "CENTER", 0, 0)
end

function addon.functions.EnsureBagUpgradeIcon(button)
	if not button then return end
	if not button.ItemUpgradeIcon then
		button.ItemUpgradeIcon = button:CreateTexture(nil, "ARTWORK")
		button.ItemUpgradeIcon:SetDrawLayer("ARTWORK", 2)
	end
	if not button.ItemUpgradeIconGlow then
		button.ItemUpgradeIconGlow = button:CreateTexture(nil, "ARTWORK")
		button.ItemUpgradeIconGlow:SetDrawLayer("ARTWORK", 1)
	end
	button.ItemUpgradeIcon:SetTexture(UPGRADE_ICON_PATH)
	button.ItemUpgradeIcon:SetSize(UPGRADE_ICON_SIZE, UPGRADE_ICON_SIZE)
	button.ItemUpgradeIcon:SetVertexColor(0, 1, 0, 1)
	button.ItemUpgradeIconGlow:SetTexture(UPGRADE_ICON_PATH)
	button.ItemUpgradeIconGlow:SetSize(UPGRADE_ICON_GLOW_SIZE, UPGRADE_ICON_GLOW_SIZE)
	button.ItemUpgradeIconGlow:SetVertexColor(0, 0, 0, 0.9)
end

local function getEquipSlotsFor(equipLoc)
	if equipLoc == "INVTYPE_FINGER" then
		return { 11, 12 }
	elseif equipLoc == "INVTYPE_TRINKET" then
		return { 13, 14 }
	elseif equipLoc == "INVTYPE_HEAD" then
		return { 1 }
	elseif equipLoc == "INVTYPE_NECK" then
		return { 2 }
	elseif equipLoc == "INVTYPE_SHOULDER" then
		return { 3 }
	elseif equipLoc == "INVTYPE_CLOAK" then
		return { 15 }
	elseif equipLoc == "INVTYPE_CHEST" or equipLoc == "INVTYPE_ROBE" then
		return { 5 }
	elseif equipLoc == "INVTYPE_WRIST" then
		return { 9 }
	elseif equipLoc == "INVTYPE_HAND" then
		return { 10 }
	elseif equipLoc == "INVTYPE_WAIST" then
		return { 6 }
	elseif equipLoc == "INVTYPE_LEGS" then
		return { 7 }
	elseif equipLoc == "INVTYPE_FEET" then
		return { 8 }
	elseif equipLoc == "INVTYPE_WEAPONMAINHAND" or equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" then
		return { 16 }
	elseif equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_HOLDABLE" or equipLoc == "INVTYPE_SHIELD" then
		return { 17 }
	elseif equipLoc == "INVTYPE_WEAPON" then
		-- One-hand weapon: compare against both if present
		return { 16, 17 }
	end
	return nil
end

local cachedUnitClass, cachedUnitSpec, cachedSpecFilters
local function getCurrentSpecFilters()
	local unitClass = addon.variables.unitClass
	local unitSpec = addon.variables.unitSpec
	if not unitClass or not unitSpec then
		cachedUnitClass, cachedUnitSpec, cachedSpecFilters = nil, nil, nil
		return nil
	end
	if unitClass ~= cachedUnitClass or unitSpec ~= cachedUnitSpec then
		cachedUnitClass, cachedUnitSpec = unitClass, unitSpec
		local classFilters = addon.itemBagFilterTypes and addon.itemBagFilterTypes[unitClass]
		cachedSpecFilters = classFilters and classFilters[unitSpec] or nil
	end
	return cachedSpecFilters
end

local function isItemRecommendedForSpec(itemLink, itemEquipLoc, classID, subclassID)
	if not itemLink then return false end
	if not IsEquippableItem(itemLink) then return false end

	if itemEquipLoc == nil or classID == nil or subclassID == nil then
		local _, _, _, equipLoc, _, instantClassID, instantSubclassID = GetItemInfoInstant(itemLink)
		itemEquipLoc = itemEquipLoc or equipLoc
		if classID == nil then classID = instantClassID end
		if subclassID == nil then subclassID = instantSubclassID end
	end

	if not itemEquipLoc or classID == nil or subclassID == nil then return false end
	if itemEquipLoc == "INVTYPE_TABARD" then return false end
	if itemEquipLoc == "INVTYPE_CLOAK" then return true end

	local specFilters = getCurrentSpecFilters()
	if not specFilters then return false end
	local classEntry = specFilters[classID]
	local value = classEntry and classEntry[subclassID]
	return value ~= nil and value ~= false
end

local function isBagItemUpgrade(itemLink, itemEquipLoc, itemLevel)
	if not itemLink or not itemEquipLoc then return false end
	local slots = getEquipSlotsFor(itemEquipLoc)
	if not slots or #slots == 0 then return false end

	local itemLevelText = itemLevel
	if itemLevelText == nil then itemLevelText = C_Item.GetDetailedItemLevelInfo(itemLink) end
	local numericLevel = tonumber(itemLevelText)
	if not numericLevel then return false end

	local baseline
	for _, invSlot in ipairs(slots) do
		local link = GetInventoryItemLink("player", invSlot)
		local eqIlvl = link and (C_Item.GetDetailedItemLevelInfo(link) or 0) or 0
		if baseline == nil then
			baseline = eqIlvl
		else
			baseline = math.min(baseline, eqIlvl) -- favor upgrade vs the worse of two (rings/trinkets/1H weapons)
		end
	end

	if baseline == nil then return false end
	return numericLevel > baseline
end

local function updateBagRarityGlow(itemButton, itemQuality, dimmed)
	if not itemButton then return end
	if not addon.db or addon.db["enhancedRarityGlow"] ~= true then
		if itemButton.EQOLRarityGlow then itemButton.EQOLRarityGlow:Hide() end
		return
	end
	if not itemQuality or itemQuality < 2 then
		if itemButton.EQOLRarityGlow then itemButton.EQOLRarityGlow:Hide() end
		return
	end
	local glow = itemButton.EQOLRarityGlow
	if not glow then
		glow = itemButton:CreateTexture(nil, "BORDER")
		glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		glow:SetBlendMode("ADD")
		glow:SetPoint("CENTER", itemButton, "CENTER", 0, 0)
		itemButton.EQOLRarityGlow = glow
	end
	local w, h = itemButton:GetSize()
	if w and h and w > 0 and h > 0 then
		glow:SetSize(w + 20, h + 20)
	else
		glow:SetSize(64, 64)
	end
	local r, g, b = C_Item.GetItemQualityColor(itemQuality)
	glow:SetVertexColor(r, g, b)
	glow:SetAlpha(dimmed and 0.1 or 0.9)
	glow:Show()
end

local function updateButtonInfo(itemButton, bag, slot, frameName)
	itemButton:SetAlpha(1)
	if itemButton.EQOLFilterOverlay then
		itemButton.EQOLFilterOverlay:SetAlpha(1)
		itemButton.EQOLFilterOverlay:Hide()
	end

	if itemButton.ItemLevelText then
		itemButton.ItemLevelText:SetAlpha(1)
		itemButton.ItemLevelText:Hide()
	end
	if itemButton.ItemBoundType then
		itemButton.ItemBoundType:SetAlpha(1)
		itemButton.ItemBoundType:SetText("")
	end
	-- Reset upgrade marker each update to avoid stale icons when buttons are recycled
	if itemButton.ItemUpgradeArrow then
		itemButton.ItemUpgradeArrow:SetAlpha(1)
		itemButton.ItemUpgradeArrow:Hide()
	end
	if itemButton.ItemUpgradeIcon then
		itemButton.ItemUpgradeIcon:SetAlpha(1)
		itemButton.ItemUpgradeIcon:Hide()
	end
	if itemButton.ItemUpgradeIconGlow then
		itemButton.ItemUpgradeIconGlow:SetAlpha(1)
		itemButton.ItemUpgradeIconGlow:Hide()
	end
	local itemLink = C_Container.GetContainerItemLink(bag, slot)
	if itemLink then
		local _, _, itemQuality, _, _, _, _, _, itemEquipLoc, _, sellPrice, classID, subclassID, tBindType, expId = GetItemInfo(itemLink)
		if itemQuality == nil and GetContainerItemInfo then
			local containerInfo = GetContainerItemInfo(bag, slot)
			if containerInfo and containerInfo.quality ~= nil then itemQuality = containerInfo.quality end
		end

		local bType, bKey, upgradeKey, bAuc
		local data
		if addon.db["showBindOnBagItems"] or addon.itemBagFilters["bind"] or addon.itemBagFilters["upgrade"] or addon.itemBagFilters["misc_auctionhouse_sellable"] then
			bType, bKey, upgradeKey, bAuc = getTooltipInfo(bag, slot, classID, tBindType)
		end
		local setVisibility
		local isUpgrade = nil

		if addon.filterFrame then
			if classID == 15 and subclassID == 0 then bAuc = true end -- ignore lockboxes etc.
			if not itemButton.matchesSearch then setVisibility = true end
			if addon.filterFrame:IsVisible() then
				if addon.itemBagFilters["rarity"] then
					if nil == addon.itemBagFiltersQuality[itemQuality] or addon.itemBagFiltersQuality[itemQuality] == false then setVisibility = true end
				end
				local cilvl = C_Item.GetDetailedItemLevelInfo(itemLink)
				if addon.itemBagFilters["minLevel"] and (not cilvl or cilvl < addon.itemBagFilters["minLevel"] or (nil == itemEquipLoc or addon.variables.ignoredEquipmentTypes[itemEquipLoc])) then
					setVisibility = true
				end
				if addon.itemBagFilters["maxLevel"] and (not cilvl or cilvl > addon.itemBagFilters["maxLevel"] or (nil == itemEquipLoc or addon.variables.ignoredEquipmentTypes[itemEquipLoc])) then
					setVisibility = true
				end
				if addon.itemBagFilters["currentExpension"] and LE_EXPANSION_LEVEL_CURRENT ~= expId then setVisibility = true end
				if addon.itemBagFilters["equipment"] and (nil == itemEquipLoc or addon.variables.ignoredEquipmentTypes[itemEquipLoc]) then setVisibility = true end
				if addon.itemBagFilters["upgradeOnly"] then
					if isUpgrade == nil then isUpgrade = isBagItemUpgrade(itemLink, itemEquipLoc) end
					if not isUpgrade then setVisibility = true end
				end
				if addon.itemBagFilters["bind"] then
					if nil == addon.itemBagFiltersBound[bKey] or addon.itemBagFiltersBound[bKey] == false then setVisibility = true end
				end
				if addon.itemBagFilters["misc_auctionhouse_sellable"] then
					if bAuc then setVisibility = true end
				end
				if addon.itemBagFilters["upgrade"] then
					if nil == addon.itemBagFiltersUpgrade[upgradeKey] or addon.itemBagFiltersUpgrade[upgradeKey] == false then setVisibility = true end
				end
				if addon.itemBagFilters["misc_sellable"] then
					if addon.itemBagFilters["misc_sellable"] == true and (not sellPrice or sellPrice == 0) then setVisibility = true end
				end
				if
					addon.itemBagFilters["usableOnly"]
					and (
						IsEquippableItem(itemLink) == false
						or (
							(
								nil == addon.itemBagFilterTypes[addon.variables.unitClass]
								or nil == addon.itemBagFilterTypes[addon.variables.unitClass][addon.variables.unitSpec]
								or nil == addon.itemBagFilterTypes[addon.variables.unitClass][addon.variables.unitSpec][classID]
								or nil == addon.itemBagFilterTypes[addon.variables.unitClass][addon.variables.unitSpec][classID][subclassID]
								or itemEquipLoc == "INVTYPE_TABARD" -- ignore Tabards
							) and itemEquipLoc ~= "INVTYPE_CLOAK" -- ignore Cloaks
						)
					)
				then
					setVisibility = true
				end
			end
		end

		if
			(itemEquipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" or (classID == 4 and subclassID == 0)) and not (classID == 4 and subclassID == 5) -- Cosmetic
		then
			if not itemButton.OverlayFilter then itemButton.OverlayFilter = itemButton:CreateFontString(nil, "ARTWORK") end
			if not itemButton.ItemLevelText then
				-- Create behind Blizzard's search overlay so it fades automatically
				itemButton.ItemLevelText = itemButton:CreateFontString(nil, "ARTWORK")
				itemButton.ItemLevelText:SetDrawLayer("ARTWORK", 1)
				itemButton.ItemLevelText:SetFont(addon.variables.defaultFont, 13, "OUTLINE")
				itemButton.ItemLevelText:SetShadowOffset(2, -2)
				itemButton.ItemLevelText:SetShadowColor(0, 0, 0, 1)
			end

			itemButton.ItemLevelText:ClearAllPoints()
			local pos = addon.db["bagIlvlPosition"] or "TOPRIGHT"
			addon.functions.ApplyBagItemLevelPosition(itemButton.ItemLevelText, itemButton, pos)
			if nil ~= addon.variables.allowedEquipSlotsBagIlvl[itemEquipLoc] then
				local r, g, b = C_Item.GetItemQualityColor(itemQuality)
				local itemLevelText = C_Item.GetCurrentItemLevel(ItemLocation:CreateFromBagAndSlot(bag, slot))

				itemButton.ItemLevelText:SetFormattedText(itemLevelText)
				itemButton.ItemLevelText:SetTextColor(r, g, b, 1)

				itemButton.ItemLevelText:Show()

				-- Upgrade arrow (bag): indicate if this item is higher ilvl than equipped
				if addon.db["showUpgradeArrowOnBagItems"] then
					local isRecommended = isItemRecommendedForSpec(itemLink, itemEquipLoc, classID, subclassID)
					if isRecommended and isUpgrade == nil then isUpgrade = isBagItemUpgrade(itemLink, itemEquipLoc, itemLevelText) end
					if isRecommended and isUpgrade then
						addon.functions.EnsureBagUpgradeIcon(itemButton)
						local posUp = addon.db["bagUpgradeIconPosition"] or "BOTTOMRIGHT"
						addon.functions.ApplyBagUpgradeIconPosition(itemButton.ItemUpgradeIcon, itemButton, posUp)
						addon.functions.AlignUpgradeIconGlow(itemButton.ItemUpgradeIconGlow, itemButton.ItemUpgradeIcon)
						itemButton.ItemUpgradeIconGlow:Show()
						itemButton.ItemUpgradeIcon:Show()
					else
						if itemButton.ItemUpgradeIcon then itemButton.ItemUpgradeIcon:Hide() end
						if itemButton.ItemUpgradeIconGlow then itemButton.ItemUpgradeIconGlow:Hide() end
					end
				else
					if itemButton.ItemUpgradeIcon then itemButton.ItemUpgradeIcon:Hide() end
					if itemButton.ItemUpgradeIconGlow then itemButton.ItemUpgradeIconGlow:Hide() end
				end

				if addon.db["showBindOnBagItems"] and bType then
					if not itemButton.ItemBoundType then
						-- Position behind Blizzard's overlay
						itemButton.ItemBoundType = itemButton:CreateFontString(nil, "ARTWORK")
						itemButton.ItemBoundType:SetDrawLayer("ARTWORK", 1)
						itemButton.ItemBoundType:SetFont(addon.variables.defaultFont, 10, "OUTLINE")
						itemButton.ItemBoundType:SetShadowOffset(2, 2)
						itemButton.ItemBoundType:SetShadowColor(0, 0, 0, 1)
					end

					itemButton.ItemBoundType:ClearAllPoints()
					addon.functions.ApplyBagBoundPosition(itemButton.ItemBoundType, itemButton, addon.db["bagIlvlPosition"])
					itemButton.ItemBoundType:SetFormattedText(bType)
					itemButton.ItemBoundType:Show()
				elseif itemButton.ItemBoundType then
					itemButton.ItemBoundType:Hide()
				end
			elseif itemButton.ItemLevelText then
				if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
				if itemButton.ItemUpgradeIcon then itemButton.ItemUpgradeIcon:Hide() end
				itemButton.ItemLevelText:Hide()
			end
		end

		if setVisibility then
			itemButton:SetAlpha(0.1)
			if not itemButton.EQOLFilterOverlay then
				itemButton.EQOLFilterOverlay = itemButton:CreateTexture(nil, "ARTWORK")
				itemButton.EQOLFilterOverlay:SetColorTexture(0, 0, 0, 0.8)
				itemButton.EQOLFilterOverlay:SetAllPoints()
			end
			itemButton.EQOLFilterOverlay:Show()

			if itemButton.ItemLevelText then itemButton.ItemLevelText:SetAlpha(0.1) end
			if itemButton.ItemBoundType then itemButton.ItemBoundType:SetAlpha(0.1) end
			if itemButton.ItemUpgradeIcon then itemButton.ItemUpgradeIcon:SetAlpha(0.1) end
			if itemButton.ProfessionQualityOverlay and addon.db["fadeBagQualityIcons"] then itemButton.ProfessionQualityOverlay:SetAlpha(0.1) end
		else
			itemButton:SetAlpha(1)
			if itemButton.EQOLFilterOverlay then itemButton.EQOLFilterOverlay:Hide() end
			if itemButton.ItemLevelText then itemButton.ItemLevelText:SetAlpha(1) end
			if itemButton.ItemBoundType then itemButton.ItemBoundType:SetAlpha(1) end
			if itemButton.ItemUpgradeIcon then itemButton.ItemUpgradeIcon:SetAlpha(1) end
			if itemButton.ProfessionQualityOverlay and addon.db["fadeBagQualityIcons"] then itemButton.ProfessionQualityOverlay:SetAlpha(1) end
		end
		updateBagRarityGlow(itemButton, itemQuality, setVisibility == true)
		-- end)
	else
		if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
		if itemButton.ItemUpgradeIcon then itemButton.ItemUpgradeIcon:Hide() end
		if itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
		updateBagRarityGlow(itemButton, nil, false)
	end
end

function addon.functions.updateBank(itemButton, bag, slot) updateButtonInfo(itemButton, bag, slot) end

local filterData = {
	{
		label = BAG_FILTER_EQUIPMENT,
		child = {
			{ type = "CheckBox", key = "equipment", label = L["bagFilterEquip"] },
			{ type = "CheckBox", key = "upgradeOnly", label = L["bagFilterUpgradeOnly"] },
			{ type = "CheckBox", key = "usableOnly", label = L["bagFilterSpec"] },
		},
	},
	{
		label = AUCTION_HOUSE_FILTER_DROP_DOWN_LEVEL_RANGE,
		child = {
			{ type = "EditBox", key = "minLevel", label = MINIMUM },
			{ type = "EditBox", key = "maxLevel", label = MAXIMUM },
		},
		ignoreSort = true,
	},
	{
		label = EXPANSION_FILTER_TEXT,
		child = {
			{ type = "CheckBox", key = "currentExpension", label = REFORGE_CURRENT, tooltip = L["currentExpensionMythicPlusWarning"] },
		},
	},
	{
		label = L["bagFilterBindType"],
		child = {
			{ type = "CheckBox", key = "boe", label = ITEM_BIND_ON_EQUIP, bFilter = "boe" },
			{ type = "CheckBox", key = "wue", label = ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP, bFilter = "wue" },
			{ type = "CheckBox", key = "wb", label = ITEM_BIND_TO_ACCOUNT, bFilter = "wb" },
		},
	},
	{
		label = L["bagFilterUpgradeLevel"],
		child = {
			{ type = "CheckBox", key = "upgrade_veteran", label = L["upgradeLevelVeteran"], uFilter = L["upgradeLevelVeteran"] },
			{ type = "CheckBox", key = "upgrade_champion", label = L["upgradeLevelChampion"], uFilter = L["upgradeLevelChampion"] },
			{ type = "CheckBox", key = "upgrade_hero", label = L["upgradeLevelHero"], uFilter = L["upgradeLevelHero"] },
			{ type = "CheckBox", key = "upgrade_mythic", label = L["upgradeLevelMythic"], uFilter = L["upgradeLevelMythic"] },
		},
	},
	{
		label = RARITY,
		child = {
			{ type = "CheckBox", key = "poor", label = "|cff9d9d9d" .. ITEM_QUALITY0_DESC, qFilter = 0 },
			{ type = "CheckBox", key = "common", label = "|cffffffff" .. ITEM_QUALITY1_DESC, qFilter = 1 },
			{ type = "CheckBox", key = "uncommon", label = "|cff1eff00" .. ITEM_QUALITY2_DESC, qFilter = 2 },
			{ type = "CheckBox", key = "rare", label = "|cff0070dd" .. ITEM_QUALITY3_DESC, qFilter = 3 },
			{ type = "CheckBox", key = "epic", label = "|cffa335ee" .. ITEM_QUALITY4_DESC, qFilter = 4 },
			{ type = "CheckBox", key = "legendary", label = "|cffff8000" .. ITEM_QUALITY5_DESC, qFilter = 5 },
			{ type = "CheckBox", key = "artifact", label = "|cffe6cc80" .. ITEM_QUALITY6_DESC, qFilter = 6 },
			{ type = "CheckBox", key = "heirloom", label = "|cff00ccff" .. ITEM_QUALITY7_DESC, qFilter = 7 },
		},
	},
	{
		label = HUD_EDIT_MODE_SETTINGS_CATEGORY_TITLE_MISC,
		child = {
			{ type = "CheckBox", key = "misc_sellable", label = L["misc_sellable"] },
			{ type = "CheckBox", key = "misc_auctionhouse_sellable", label = L["misc_auctionhouse_sellable"] },
		},
	},
}
table.sort(filterData, function(a, b)
	if a.ignoreSort and not b.ignoreSort then return true end
	if b.ignoreSort and not a.ignoreSort then return false end
	return a.label < b.label
end)

local function checkActiveQualityFilter()
	for _, value in pairs(addon.itemBagFiltersQuality) do
		if value == true then
			addon.itemBagFilters["rarity"] = true
			return
		end
	end
	addon.itemBagFilters["rarity"] = false
end

local function checkActiveBindFilter()
	for _, value in pairs(addon.itemBagFiltersBound) do
		if value == true then
			addon.itemBagFilters["bind"] = true
			return
		end
	end
	addon.itemBagFilters["bind"] = false
end

local function checkActiveUpgradeFilter()
	for _, value in pairs(addon.itemBagFiltersUpgrade) do
		if value == true then
			addon.itemBagFilters["upgrade"] = true
			return
		end
	end
	addon.itemBagFilters["upgrade"] = false
end

local function CreateFilterMenu()
	local frame = CreateFrame("Frame", "InventoryFilterPanel", ContainerFrameCombinedBags, "BackdropTemplate")
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	frame:Hide() -- Standardmäßig ausblenden
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if addon.db["bagFilterDockFrame"] then return end
		if not IsShiftKeyDown() then return end
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- Position speichern
		local point, _, parentPoint, xOfs, yOfs = self:GetPoint()
		addon.db["bagFilterFrameData"].point = point
		addon.db["bagFilterFrameData"].parentPoint = parentPoint
		addon.db["bagFilterFrameData"].x = xOfs
		addon.db["bagFilterFrameData"].y = yOfs
	end)
	if
		not addon.db["bagFilterDockFrame"]
		and addon.db["bagFilterFrameData"].point
		and addon.db["bagFilterFrameData"].parentPoint
		and addon.db["bagFilterFrameData"].x
		and addon.db["bagFilterFrameData"].y
	then
		frame:SetPoint(addon.db["bagFilterFrameData"].point, UIParent, addon.db["bagFilterFrameData"].parentPoint, addon.db["bagFilterFrameData"].x, addon.db["bagFilterFrameData"].y)
	else
		frame:SetPoint("TOPRIGHT", ContainerFrameCombinedBags, "TOPLEFT", -10, 0)
	end

	-- Scrollbarer Bereich
	local scrollContainer = AceGUI:Create("ScrollFrame")
	scrollContainer:SetLayout("Flow")
	scrollContainer:SetFullWidth(true)
	scrollContainer:SetFullHeight(true)

	scrollContainer.frame:SetParent(frame)
	scrollContainer.frame:ClearAllPoints()
	scrollContainer.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
	scrollContainer.frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
	scrollContainer.frame:Show()
	frame.widgets = {}

	local function AnyFilterActive()
		for _, v in pairs(addon.itemBagFilters) do
			if v then return true end
		end
		for _, tbl in ipairs({ addon.itemBagFiltersQuality, addon.itemBagFiltersBound, addon.itemBagFiltersUpgrade }) do
			for _, v in pairs(tbl) do
				if v then return true end
			end
		end
		return false
	end

	local function UpdateResetButton()
		if frame.btnReset then
			if AnyFilterActive() then
				frame.btnReset:Show()
			else
				frame.btnReset:Hide()
			end
		end
	end

	local longestWidth = 200
	local math_max = math.max
	-- Dynamisch die UI-Elemente aus `filterData` erstellen
	for _, section in ipairs(filterData) do
		-- Überschrift für jede Sektion
		local label = AceGUI:Create("Label")
		label:SetText("|cffffd100" .. section.label .. "|r") -- Goldene Überschrift
		label:SetFont(addon.variables.defaultFont, 12, "OUTLINE")
		label:SetFullWidth(true)
		scrollContainer:AddChild(label)

		longestWidth = math_max(label.label:GetStringWidth(), longestWidth)

		-- Füge die Kind-Elemente hinzu
		for _, item in ipairs(section.child) do
			local widget

			if item.type == "CheckBox" then
				widget = AceGUI:Create("CheckBox")
				widget:SetLabel(item.label)
				widget:SetValue(addon.itemBagFilters[item.key])
				widget:SetCallback("OnValueChanged", function(_, _, value)
					addon.itemBagFilters[item.key] = value
					if item.qFilter then
						addon.itemBagFiltersQuality[item.qFilter] = value
						checkActiveQualityFilter()
					end
					if item.bFilter then
						addon.itemBagFiltersBound[item.bFilter] = value
						checkActiveBindFilter()
					end
					if item.uFilter then
						addon.itemBagFiltersUpgrade[string.lower(item.uFilter)] = value
						checkActiveUpgradeFilter()
					end
					-- Hier könnte man die Filterlogik triggern, z. B.:
					-- UpdateInventoryDisplay()
					addon.functions.updateBags(ContainerFrameCombinedBags)
					for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
						addon.functions.updateBags(frame)
					end

					if _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end

					UpdateResetButton()
				end)
				if item.tooltip then
					widget:SetCallback("OnEnter", function(self)
						GameTooltip:SetOwner(self.frame, "ANCHOR_RIGHT")
						GameTooltip:ClearLines()
						GameTooltip:AddLine(item.tooltip)
						GameTooltip:Show()
					end)
					widget:SetCallback("OnLeave", function(self) GameTooltip:Hide() end)
				end
			elseif item.type == "EditBox" then
				-- separate label so it aligns nicely above half‑width boxes
				local eLabel = AceGUI:Create("Label")
				eLabel:SetText(item.label)
				eLabel:SetRelativeWidth(0.48)
				scrollContainer:AddChild(eLabel)
				widget = AceGUI:Create("EditBox")
				-- widget:SetLabel(item.label) -- REMOVED: label now handled by separate label above
				widget:SetWidth(50)
				widget:SetText(addon.itemBagFilters[item.key] or "")
				-- Show Min/Max boxes side‑by‑side, half width each
				if item.key == "minLevel" or item.key == "maxLevel" then
					-- keep some margin, 0.48 looks good in Flow layout
					widget:SetRelativeWidth(0.48)
				end

				widget:SetCallback("OnTextChanged", function(self, _, text)
					local caret = self.editbox:GetCursorPosition()
					local numeric = text:gsub("%D", "")
					if numeric ~= text then
						self:SetText(numeric)
						local newPos = math.max(0, caret - (text:len() - numeric:len()))
						self.editbox:SetCursorPosition(newPos)
					end
				end)

				widget:SetCallback("OnEnterPressed", function(self, _, text)
					addon.itemBagFilters[item.key] = tonumber(text)
					addon.functions.updateBags(ContainerFrameCombinedBags)
					for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
						addon.functions.updateBags(frame)
					end

					if _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end

					UpdateResetButton()
					self:ClearFocus()
				end)
			end

			if widget then
				if item.type ~= "EditBox" or (item.key ~= "minLevel" and item.key ~= "maxLevel") then widget:SetFullWidth(true) end
				scrollContainer:AddChild(widget)
				table.insert(frame.widgets, widget)
				if widget.text and widget.text.GetStringWidth then longestWidth = math_max(widget.text:GetStringWidth(), longestWidth) end
			end
		end
	end
	frame:SetSize(longestWidth + 60, 280) -- Feste Größe

	local btnDock = CreateFrame("Button", "InventoryFilterPanelDock", frame)
	btnDock:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -5)
	btnDock:SetText("Dock")
	btnDock.isDocked = addon.db["bagFilterDockFrame"]
	btnDock:SetScript("OnClick", function(self)
		self.isDocked = not self.isDocked
		addon.db["bagFilterDockFrame"] = self.isDocked
		if self.isDocked then
			frame:ClearAllPoints()
			frame:SetPoint("TOPRIGHT", ContainerFrameCombinedBags, "TOPLEFT", -10, 0)
			self.icon:SetTexture("Interface\\Addons\\EnhanceQoL\\Icons\\ClosedLock.tga")
		else
			self.icon:SetTexture("Interface\\Addons\\EnhanceQoL\\Icons\\OpenLock.tga")
		end
	end)
	btnDock:SetSize(16, 16)
	btnDock:Show()

	local icon = btnDock:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(btnDock)
	if addon.db["bagFilterDockFrame"] then
		icon:SetTexture("Interface\\Addons\\EnhanceQoL\\Icons\\ClosedLock.tga")
	else
		icon:SetTexture("Interface\\Addons\\EnhanceQoL\\Icons\\OpenLock.tga")
	end
	btnDock.icon = icon
	-- Tooltip: zeigt dem Spieler, was der Button macht
	btnDock:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.isDocked then
			GameTooltip:SetText(L["bagFilterDockFrameUnlock"])
		else
			GameTooltip:SetText(L["bagFilterDockFrameLock"])
		end
		GameTooltip:Show()
	end)
	btnDock:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local btnReset = CreateFrame("Button", "InventoryFilterPanelReset", frame)
	btnReset:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -50, -5)
	btnReset:SetSize(16, 16)
	btnReset:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
	btnReset:Hide()
	frame.btnReset = btnReset
	btnReset:SetScript("OnClick", function()
		addon.itemBagFilters = {}
		addon.itemBagFiltersQuality = {}
		addon.itemBagFiltersBound = {}
		addon.itemBagFiltersUpgrade = {}

		for _, widget in ipairs(frame.widgets) do
			if widget.SetValue then widget:SetValue(false) end
			if widget.SetText then widget:SetText("") end
		end

		addon.functions.updateBags(ContainerFrameCombinedBags)
		for _, cframe in ipairs(ContainerFrameContainer.ContainerFrames) do
			addon.functions.updateBags(cframe)
		end

		if _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end

		UpdateResetButton()
	end)
	btnReset:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["bagFilterResetFilters"])
		GameTooltip:Show()
	end)
	btnReset:SetScript("OnLeave", function() GameTooltip:Hide() end)

	UpdateResetButton()
	return frame
end

local function ToggleFilterMenu(self)
	if not addon.filterFrame then addon.filterFrame = CreateFilterMenu() end
	addon.filterFrame:Show()

	addon.functions.updateBags(ContainerFrameCombinedBags)
	for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
		addon.functions.updateBags(frame)
	end

	if _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end
end

local function InitializeFilterUI()
	if nil == addon.filterFrame then ToggleFilterMenu() end
end

function addon.functions.updateBags(frame)
	if addon.db["showBagFilterMenu"] then
		InitializeFilterUI()
	elseif addon.filterFrame then
		addon.filterFrame:SetParent(nil)
		addon.filterFrame:Hide()
		addon.filterFrame = nil
		addon.itemBagFilters = {}
		addon.itemBagFiltersQuality = {}
		addon.itemBagFiltersBound = {}
		addon.itemBagFiltersUpgrade = {}
	end
	if not frame:IsShown() then return end

	if frame:GetName() == "BankPanel" then
		for itemButton in frame:EnumerateValidItems() do
			if addon.db["showIlvlOnBankFrame"] then
				local bag = itemButton:GetBankTabID()
				local slot = itemButton:GetContainerSlotID()
				if bag and slot then updateButtonInfo(itemButton, bag, slot, frame:GetName()) end
			elseif itemButton.ItemLevelText then
				itemButton.ItemLevelText:Hide()
			end
		end
	else
		for _, itemButton in frame:EnumerateValidItems() do
			if itemButton then
				if addon.db["showIlvlOnBagItems"] then
					updateButtonInfo(itemButton, itemButton:GetBagID(), itemButton:GetID(), frame:GetName())
				elseif itemButton.ItemLevelText then
					itemButton.ItemLevelText:Hide()
				end
			end
		end
	end
end

function addon.functions.IsQuestRepeatableType(questID)
	if C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then return true end
	if C_QuestLog.IsRepeatableQuest and C_QuestLog.IsRepeatableQuest(questID) then return true end
	local classification
	if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification then classification = C_QuestInfoSystem.GetQuestClassification(questID) end
	return classification == Enum.QuestClassification.Recurring or classification == Enum.QuestClassification.Calling
end

local function handleWayCommand(msg)
	local args = {}
	msg = (msg or ""):gsub(",", " ")
	for token in string.gmatch(msg, "%S+") do
		table.insert(args, token)
	end

	local mapID, x, y
	if #args >= 2 then
		local first = args[1]
		if first:sub(1, 1) == "#" then first = first:sub(2) end
		local firstNumber = tonumber(first)
		local secondNumber = tonumber(args[2])
		local thirdNumber = tonumber(args[3])

		if firstNumber and secondNumber and thirdNumber then
			mapID = firstNumber
			x = secondNumber
			y = thirdNumber
		else
			x = firstNumber
			y = secondNumber
			mapID = C_Map.GetBestMapForUnit("player")
		end
	end

	if not mapID or not x or not y then
		print("|cff00ff98Enhance QoL|r: " .. L["wayUsage"])
		return
	end

	local mInfo = C_Map.GetMapInfo(mapID)
	if not mInfo or nil == mInfo then
		print("|cff00ff98Enhance QoL|r: " .. L["wayError"]:format(mapID))
		return
	end

	if not C_Map.CanSetUserWaypointOnMap(mapID) then
		print("|cff00ff98Enhance QoL|r: " .. L["wayErrorPlacePing"])
		return
	end

	x = x / 100
	y = y / 100

	local point = UiMapPoint.CreateFromCoordinates(mapID, x, y)
	C_Map.SetUserWaypoint(point)
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)

	print("|cff00ff98Enhance QoL|r: " .. string.format(L["waySet"], mInfo.name, x * 100, y * 100))
end

function addon.functions.registerWayCommand()
	if SlashCmdList["WAY"] or _G.SLASH_WAY1 then return end
	SLASH_EQOLWAY1 = "/way"
	SlashCmdList["EQOLWAY"] = handleWayCommand
end

local function isSlashCommandRegistered(command)
	if not command then return false end
	command = command:lower()
	for key, value in pairs(_G) do
		if type(key) == "string" and key:match("^SLASH_") and type(value) == "string" then
			if value:lower() == command then return true end
		end
	end
	return false
end

local function isSlashCommandOwnedByEQOL(command, listName, prefix, maxIndex)
	if not SlashCmdList or not listName or not prefix then return false end
	if not SlashCmdList[listName] then return false end
	local cmd = command and command:lower()
	if not cmd then return false end
	for i = 1, maxIndex or 1 do
		local val = _G["SLASH_" .. prefix .. i]
		if type(val) == "string" and val:lower() == cmd then return true end
	end
	return false
end

local function getPullCountdownSeconds(msg)
	local number = tonumber(msg and msg:match("(%d+)") or "")
	if not number then number = (addon.db and addon.db["pullTimerLongTime"]) or 10 end
	if number < 0 then number = 0 end
	local maxSeconds = (Constants and Constants.PartyCountdownConstants and Constants.PartyCountdownConstants.MaxCountdownSeconds) or 3600
	if number > maxSeconds then number = maxSeconds end
	return number
end

local function toggleCooldownViewerSettings()
	if InCombatLockdown and InCombatLockdown() then return end
	local frame = _G.CooldownViewerSettings
	if not frame then
		local loader = (C_AddOns and C_AddOns.LoadAddOn) or _G.UIParentLoadAddOn
		if loader then
			loader("Blizzard_CooldownViewer")
			frame = _G.CooldownViewerSettings
		end
	end
	if not frame then return end
	if frame.TogglePanel then
		frame:TogglePanel()
	elseif frame.ShowUIPanel then
		if frame:IsShown() then
			frame:Hide()
		else
			frame:ShowUIPanel()
		end
	else
		frame:SetShown(not frame:IsShown())
	end
end

local function toggleEditMode()
	if InCombatLockdown and InCombatLockdown() then return end
	local frame = _G.EditModeManagerFrame
	if not frame then
		local loader = (C_AddOns and C_AddOns.LoadAddOn) or _G.UIParentLoadAddOn
		if loader then
			loader("Blizzard_EditMode")
			frame = _G.EditModeManagerFrame
		end
	end
	if not frame then return end
	if frame.CanEnterEditMode and not frame:CanEnterEditMode() then return end
	if frame:IsShown() then
		if HideUIPanel then
			HideUIPanel(frame)
		else
			frame:Hide()
		end
	else
		if ShowUIPanel then
			ShowUIPanel(frame)
		else
			frame:Show()
		end
	end
end

local function toggleQuickKeybindMode()
	if InCombatLockdown and InCombatLockdown() then return end
	local frame = _G.QuickKeybindFrame
	if not frame then
		local loader = (C_AddOns and C_AddOns.LoadAddOn) or _G.UIParentLoadAddOn
		if loader then
			loader("Blizzard_QuickKeybind")
			frame = _G.QuickKeybindFrame
		end
	end
	if not frame then return end
	frame:SetShown(not frame:IsShown())
end

function addon.functions.registerCooldownManagerSlashCommand()
	if not SlashCmdList then return end
	local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
	local waLoaded = isLoaded and isLoaded("WeakAuras") or false

	local commands = {}
	local function canClaim(command) return isSlashCommandOwnedByEQOL(command, "EQOLCDMSC", "EQOLCDMSC", 2) or not isSlashCommandRegistered(command) end
	if canClaim("/cdm") then commands[#commands + 1] = "/cdm" end
	if not waLoaded and canClaim("/wa") then commands[#commands + 1] = "/wa" end

	if #commands == 0 then return end
	_G.SLASH_EQOLCDMSC1 = commands[1]
	_G.SLASH_EQOLCDMSC2 = commands[2]
	SlashCmdList["EQOLCDMSC"] = function() toggleCooldownViewerSettings() end
end

function addon.functions.registerPullTimerSlashCommand()
	if not SlashCmdList then return end
	local function canClaim(command) return isSlashCommandOwnedByEQOL(command, "EQOLPULL", "EQOLPULL", 1) or not isSlashCommandRegistered(command) end
	if not canClaim("/pull") then return end
	_G.SLASH_EQOLPULL1 = "/pull"
	SlashCmdList["EQOLPULL"] = function(msg)
		local seconds = getPullCountdownSeconds(msg)
		if C_PartyInfo and C_PartyInfo.DoCountdown then C_PartyInfo.DoCountdown(seconds) end
	end
end

function addon.functions.registerEditModeSlashCommand()
	if not SlashCmdList then return end
	local commands = {}
	local function canClaim(command) return isSlashCommandOwnedByEQOL(command, "EQOLEM", "EQOLEM", 3) or not isSlashCommandRegistered(command) end
	if canClaim("/em") then commands[#commands + 1] = "/em" end
	if canClaim("/edit") then commands[#commands + 1] = "/edit" end
	if canClaim("/editmode") then commands[#commands + 1] = "/editmode" end
	if #commands == 0 then return end
	_G.SLASH_EQOLEM1 = commands[1]
	_G.SLASH_EQOLEM2 = commands[2]
	_G.SLASH_EQOLEM3 = commands[3]
	SlashCmdList["EQOLEM"] = function() toggleEditMode() end
end

function addon.functions.registerQuickKeybindSlashCommand()
	if not SlashCmdList then return end
	local function canClaim(command) return isSlashCommandOwnedByEQOL(command, "EQOLKB", "EQOLKB", 1) or not isSlashCommandRegistered(command) end
	if not canClaim("/kb") then return end
	_G.SLASH_EQOLKB1 = "/kb"
	SlashCmdList["EQOLKB"] = function() toggleQuickKeybindMode() end
end

function addon.functions.registerReloadUISlashCommand()
	if not SlashCmdList then return end
	local function canClaim(command) return isSlashCommandOwnedByEQOL(command, "EQOLRL", "EQOLRL", 1) or not isSlashCommandRegistered(command) end
	if not canClaim("/rl") then return end
	_G.SLASH_EQOLRL1 = "/rl"
	SlashCmdList["EQOLRL"] = function()
		if ReloadUI then ReloadUI() end
	end
end

function addon.functions.catalystChecks()
	-- No catalyst charges exist for Timerunners; ensure hidden
	if addon.functions.IsTimerunner() then
		addon.variables.catalystID = nil
		if addon.general and addon.general.iconFrame then addon.general.iconFrame:Hide() end
		return
	end

	local mId = C_MythicPlus.GetCurrentSeason()
	if mId == -1 then
		C_MythicPlus.RequestMapInfo()
		C_Timer.After(0.1, function() addon.functions.catalystChecks() end)
		return
	end
	if not mId or mId < 0 then
		-- Patch fallback (if the season ID is unavailable):
		-- 1) Add timestamps in addon.variables.patchInformations (Init.lua).
		-- 2) Use addon.functions.IsPatchLive(...) here to map to a season ID.
		addon.variables.catalystID = nil
		return
	end

	if mId == 15 then
		-- TWW Season 3 - Ethereal Voidsplinter
		addon.variables.catalystID = 3269
	elseif mId == 17 then
		addon.variables.catalystID = 3378
	end
	addon.functions.createCatalystFrame()
end

function addon.functions.fmtToPattern(fmt)
	local pat = fmt:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
	pat = pat:gsub("%%%%d", "%%d+") -- "%d" -> "%d+"
	pat = pat:gsub("%%%%s", ".+") -- "%s" -> ".+"
	return "^" .. pat .. "$"
end

addon.functions.FindBindingIndex = function(data)
	local found = {}
	if not type(data) == "table" then return end

	for i = 1, GetNumBindings() do
		local command = GetBinding(i)
		if data[command] then found[command] = i end
	end
	return found
end

function addon.functions.isRestrictedContent(ignoreMap)
	local restrictionTypes = Enum and Enum.AddOnRestrictionType
	local restrictedActions = _G.C_RestrictedActions
	if not (restrictionTypes and restrictedActions and restrictedActions.GetAddOnRestrictionState) then return false end
	for _, v in pairs(restrictionTypes) do
		if ignoreMap and v ~= 4 or not ignoreMap then
			if restrictedActions.GetAddOnRestrictionState(v) == 2 then return true end
		end
	end
	return false
end
