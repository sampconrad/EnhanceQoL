-- luacheck: globals GenericTraitUI_LoadUI GenericTraitFrame

local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local LFGListFrame = _G.LFGListFrame
local GetContainerItemInfo = C_Container.GetContainerItemInfo
local StaticPopup_Visible = StaticPopup_Visible
local IsShiftKeyDown = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsAltKeyDown = IsAltKeyDown
local IsInGroup = IsInGroup
local math = math
local TooltipUtil = _G.TooltipUtil
local GetTime = GetTime

---- REGION Functions

local doneHook = false
local inspectDone = {}
local inspectUnit = nil
addon.enchantTextCache = addon.enchantTextCache or {}
-- New helpers for Character vs Inspect display options
local function _ensureDisplayDB()
	addon.db = addon.db or {}
	-- migrate legacy toggles to new multi-select tables once
	if not addon.db.charDisplayOptions then
		addon.db.charDisplayOptions = {}
		if addon.db["showIlvlOnCharframe"] then addon.db.charDisplayOptions.ilvl = true end
		if addon.db["showGemsOnCharframe"] then addon.db.charDisplayOptions.gems = true end
		if addon.db["showEnchantOnCharframe"] then addon.db.charDisplayOptions.enchants = true end
		if addon.db["showGemsTooltipOnCharframe"] then addon.db.charDisplayOptions.gemtip = true end
	end
	if not addon.db.inspectDisplayOptions then
		addon.db.inspectDisplayOptions = {}
		for k, v in pairs(addon.db.charDisplayOptions) do
			addon.db.inspectDisplayOptions[k] = v
		end
	end
end
addon.functions.ensureDisplayDB = _ensureDisplayDB

local function CharOpt(opt)
	_ensureDisplayDB()
	local t = addon.db.charDisplayOptions or {}
	-- Disable enchant checks entirely for Timerunners
	if opt == "enchants" and addon.functions and addon.functions.IsTimerunner and addon.functions.IsTimerunner() then return false end
	return t[opt] == true
end

local function InspectOpt(opt)
	_ensureDisplayDB()
	local t = addon.db.inspectDisplayOptions or {}
	-- Also suppress enchant checks in Inspect when player is a Timerunner
	if opt == "enchants" and addon.functions and addon.functions.IsTimerunner and addon.functions.IsTimerunner() then return false end
	return t[opt] == true
end

local function AnyInspectEnabled()
	_ensureDisplayDB()
	local t = addon.db.inspectDisplayOptions or {}
	return t.ilvl or t.gems or t.enchants or t.gemtip
end

local function CheckItemGems(element, itemLink, emptySocketsCount, key, pdElement, attempts)
	attempts = attempts or 1 -- Anzahl der Versuche
	if attempts > 10 then -- Abbruch nach 5 Versuchen, um Endlosschleifen zu vermeiden
		return
	end

	for i = 1, emptySocketsCount do
		local gemName, gemLink = C_Item.GetItemGem(itemLink, i)
		element.gems[i]:SetScript("OnEnter", nil)

		if gemName then
			local icon = C_Item.GetItemIconByID(gemLink)
			element.gems[i].icon:SetTexture(icon)
			element.gems[i].icon:SetVertexColor(1, 1, 1)
			element.gems[i]:SetScript("OnEnter", function(self)
				local showTip
				if pdElement == InspectPaperDollFrame then
					showTip = InspectOpt("gemtip")
				else
					showTip = CharOpt("gemtip")
				end
				if gemLink and showTip then
					local anchor = "ANCHOR_CURSOR"
					if addon.db["TooltipAnchorType"] == 3 then anchor = "ANCHOR_CURSOR_LEFT" end
					if addon.db["TooltipAnchorType"] == 4 then anchor = "ANCHOR_CURSOR_RIGHT" end
					local xOffset = addon.db["TooltipAnchorOffsetX"] or 0
					local yOffset = addon.db["TooltipAnchorOffsetY"] or 0
					-- TODO we can't change tooltip for now in midnight beta
					if not addon.variables.isMidnight then
						GameTooltip:SetOwner(self, anchor, xOffset, yOffset)
						GameTooltip:SetHyperlink(gemLink)
						GameTooltip:Show()
					end
				end
			end)
		else
			-- Wiederhole die Überprüfung nach einer Verzögerung, wenn der Edelstein noch nicht geladen ist
			C_Timer.After(0.1, function() CheckItemGems(element, itemLink, emptySocketsCount, key, pdElement, attempts + 1) end)
			return -- Abbrechen, damit wir auf die nächste Überprüfung warten
		end
	end
end

local function getTooltipInfoFromLink(link)
	if not link then return nil, nil end

	local enchantID = tonumber(link:match("item:%d+:(%d+)") or 0)
	local enchantText = nil

	if enchantID and enchantID > 0 then enchantText = addon.enchantTextCache[enchantID] end

	if enchantText == nil then
		local data = C_TooltipInfo.GetHyperlink(link)
		if data and data.lines then
			for _, v in pairs(data.lines) do
				if v.type == 15 then
					local r, g, b = v.leftColor:GetRGB()
					local colorHex = ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)

					local text = strmatch(gsub(gsub(gsub(v.leftText, "%s?|A.-|a", ""), "|cn.-:(.-)|r", "%1"), "[&+] ?", ""), addon.variables.enchantString)
					local icons = {}
					v.leftText:gsub("(|A.-|a)", function(iconString) table.insert(icons, iconString) end)
					text = text:gsub("(%d+)", "%1")
					text = text:gsub("(%a%a%a)%a+", "%1")
					text = text:gsub("%%", "%%%%")
					enchantText = colorHex .. text .. (icons[1] or "") .. "|r"
					break
				end
			end
		end

		if enchantID and enchantID > 0 then addon.enchantTextCache[enchantID] = enchantText or false end
	elseif enchantText == false then
		enchantText = nil
	end

	return enchantText
end

local itemCount = 0
local ilvlSum = 0

local function removeInspectElements()
	if nil == InspectPaperDollFrame then return end
	itemCount = 0
	ilvlSum = 0
	if InspectPaperDollFrame.ilvl then InspectPaperDollFrame.ilvl:SetText("") end
	local itemSlotsInspectList = {
		[1] = InspectHeadSlot,
		[2] = InspectNeckSlot,
		[3] = InspectShoulderSlot,
		[15] = InspectBackSlot,
		[5] = InspectChestSlot,
		[9] = InspectWristSlot,
		[10] = InspectHandsSlot,
		[6] = InspectWaistSlot,
		[7] = InspectLegsSlot,
		[8] = InspectFeetSlot,
		[11] = InspectFinger0Slot,
		[12] = InspectFinger1Slot,
		[13] = InspectTrinket0Slot,
		[14] = InspectTrinket1Slot,
		[16] = InspectMainHandSlot,
		[17] = InspectSecondaryHandSlot,
	}

	for key, element in pairs(itemSlotsInspectList) do
		if element.ilvl then element.ilvl:SetFormattedText("") end
		if element.ilvlBackground then element.ilvlBackground:Hide() end
		if element.enchant then element.enchant:SetText("") end
		if element.borderGradient then element.borderGradient:Hide() end
		if element.gems and #element.gems > 0 then
			for i = 1, #element.gems do
				element.gems[i]:UnregisterAllEvents()
				element.gems[i]:SetScript("OnUpdate", nil)
				element.gems[i]:Hide()
			end
		end
	end
	collectgarbage("collect")
end

local tooltipCache = {}

local pvpItemTooltip = addon.functions.fmtToPattern(PVP_ITEM_LEVEL_TOOLTIP)

local function getTooltipInfo(link)
	local key = link
	local cached = tooltipCache[key]
	if cached then return cached[1], cached[2] end

	local upgradeKey, isPVP
	local data = C_TooltipInfo.GetHyperlink(link)
	if data and data.lines then
		for i, v in pairs(data.lines) do
			if v.type == 42 then
				local text = v.rightText or v.leftText
				if text then
					local tier = text:gsub(".+:%s?", ""):gsub("%s?%d/%d", "")
					if tier then upgradeKey = string.lower(tier) end
				end
			elseif v.type == 0 and v.leftText:match(pvpItemTooltip) then
				isPVP = true
			end
		end
	end

	tooltipCache[key] = { upgradeKey, isPVP }
	return upgradeKey, isPVP
end

local function onInspect(arg1)
	if nil == InspectFrame then return end
	local unit = InspectFrame.unit
	if nil == unit then return end

	if UnitGUID(InspectFrame.unit) ~= arg1 then return end

	local pdElement = InspectPaperDollFrame
	if not doneHook then
		doneHook = true
		InspectFrame:HookScript("OnHide", function(self)
			inspectDone = {}
			removeInspectElements()
		end)
	end
	if inspectUnit ~= InspectFrame.unit then
		inspectUnit = InspectFrame.unit
		inspectDone = {}
	end
	if not InspectOpt("ilvl") and pdElement.ilvl then pdElement.ilvl:SetText("") end
	if not pdElement.ilvl and InspectOpt("ilvl") then
		pdElement.ilvlBackground = pdElement:CreateTexture(nil, "BACKGROUND")
		pdElement.ilvlBackground:SetColorTexture(0, 0, 0, 0.8) -- Schwarzer Hintergrund mit 80% Transparenz
		pdElement.ilvlBackground:SetPoint("TOPRIGHT", pdElement, "TOPRIGHT", -2, -28)
		pdElement.ilvlBackground:SetSize(20, 16) -- Größe des Hintergrunds (muss ggf. angepasst werden)

		pdElement.ilvl = pdElement:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		pdElement.ilvl:SetPoint("TOPRIGHT", pdElement.ilvlBackground, "TOPRIGHT", -1, -1) -- Position des Textes im Zentrum des Hintergrunds
		pdElement.ilvl:SetFont(addon.variables.defaultFont, 16, "OUTLINE") -- Setzt die Schriftart, -größe und -stil (OUTLINE)

		pdElement.ilvl:SetFormattedText("")
		pdElement.ilvl:SetTextColor(1, 1, 1, 1)

		local textWidth = pdElement.ilvl:GetStringWidth()
		pdElement.ilvlBackground:SetSize(textWidth + 6, pdElement.ilvl:GetStringHeight() + 4) -- Mehr Padding für bessere Lesbarkeit
	end
	local itemSlotsInspectList = {
		[1] = InspectHeadSlot,
		[2] = InspectNeckSlot,
		[3] = InspectShoulderSlot,
		[15] = InspectBackSlot,
		[5] = InspectChestSlot,
		[9] = InspectWristSlot,
		[10] = InspectHandsSlot,
		[6] = InspectWaistSlot,
		[7] = InspectLegsSlot,
		[8] = InspectFeetSlot,
		[11] = InspectFinger0Slot,
		[12] = InspectFinger1Slot,
		[13] = InspectTrinket0Slot,
		[14] = InspectTrinket1Slot,
		[16] = InspectMainHandSlot,
		[17] = InspectSecondaryHandSlot,
	}
	local twoHandLocs = {
		INVTYPE_2HWEAPON = true,
		INVTYPE_RANGED = true,
		INVTYPE_RANGEDRIGHT = true,
		INVTYPE_FISHINGPOLE = true,
	}

	for key, element in pairs(itemSlotsInspectList) do
		if nil == inspectDone[key] then
			if element.ilvl then element.ilvl:SetFormattedText("") end
			if element.ilvlBackground then element.ilvlBackground:Hide() end
			if element.enchant then element.enchant:SetText("") end
			local itemLink = GetInventoryItemLink(unit, key)
			if itemLink then
				local eItem = Item:CreateFromItemLink(itemLink)
				if eItem and not eItem:IsItemEmpty() then
					eItem:ContinueOnItemLoad(function()
						inspectDone[key] = true
						if InspectOpt("gems") then
							local itemStats = C_Item.GetItemStats(itemLink)
							local socketCount = 0
							for statName, statValue in pairs(itemStats) do
								if (statName:find("EMPTY_SOCKET") or statName:find("empty_socket")) and addon.variables.allowedSockets[statName] then socketCount = socketCount + statValue end
							end
							local neededSockets = addon.variables.shouldSocketed[key] or 0
							if neededSockets then
								local cSeason, isPvP = getTooltipInfo(itemLink)
								if addon.variables.shouldSocketedChecks[key] then
									if not addon.variables.shouldSocketedChecks[key].func(cSeason, isPvP) then neededSockets = 0 end
								end
							end
							local displayCount = math.max(socketCount, neededSockets)
							if element.gems and #element.gems > displayCount then
								for i = displayCount + 1, #element.gems do
									element.gems[i]:UnregisterAllEvents()
									element.gems[i]:SetScript("OnUpdate", nil)
									element.gems[i]:Hide()
								end
							end
							if not element.gems then element.gems = {} end
							for i = 1, displayCount do
								if not element.gems[i] then
									element.gems[i] = CreateFrame("Frame", nil, pdElement)
									element.gems[i]:SetSize(16, 16) -- Setze die Größe des Icons
									if addon.variables.itemSlotSide[key] == 0 then
										element.gems[i]:SetPoint("TOPLEFT", element, "TOPRIGHT", 5 + (i - 1) * 16, -1) -- Verschiebe jedes Icon um 20px
									elseif addon.variables.itemSlotSide[key] == 1 then
										element.gems[i]:SetPoint("TOPRIGHT", element, "TOPLEFT", -5 - (i - 1) * 16, -1)
									else
										element.gems[i]:SetPoint("BOTTOM", element, "TOPLEFT", -1, 5 + (i - 1) * 16)
									end

									element.gems[i]:SetFrameStrata("DIALOG")
									element.gems[i]:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

									element.gems[i].icon = element.gems[i]:CreateTexture(nil, "OVERLAY")
									element.gems[i].icon:SetAllPoints(element.gems[i])
								end
								element.gems[i].icon:SetTexture("Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic")
								if i > socketCount then
									element.gems[i].icon:SetVertexColor(1, 0, 0)
									element.gems[i]:SetScript("OnEnter", nil)
								else
									element.gems[i].icon:SetVertexColor(1, 1, 1)
								end
								element.gems[i]:Show()
							end
							if socketCount > 0 then CheckItemGems(element, itemLink, socketCount, key, pdElement) end
						elseif element.gems and #element.gems > 0 then
							for i = 1, #element.gems do
								element.gems[i]:UnregisterAllEvents()
								element.gems[i]:SetScript("OnUpdate", nil)
								element.gems[i]:Hide()
							end
						end

						if InspectOpt("ilvl") then
							local double = false
							if key == 16 then
								local offhandLink = GetInventoryItemLink(unit, 17)
								local _, _, _, itemEquipLoc = C_Item.GetItemInfoInstant(itemLink)
								if not offhandLink and twoHandLocs[itemEquipLoc] then double = true end
							end
							itemCount = itemCount + (double and 2 or 1)
							if not element.ilvlBackground then
								element.ilvlBackground = element:CreateTexture(nil, "BACKGROUND")
								element.ilvlBackground:SetColorTexture(0, 0, 0, 0.8) -- Schwarzer Hintergrund mit 80% Transparenz
								element.ilvl = element:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
								element.ilvl:SetFont(addon.variables.defaultFont, 14, "OUTLINE") -- Setzt die Schriftart, -größe und -stil (OUTLINE)
							end

							local cpos = addon.db["charIlvlPosition"] or "TOPRIGHT"
							element.ilvlBackground:ClearAllPoints()
							element.ilvl:ClearAllPoints()
							if cpos == "TOPLEFT" then
								element.ilvlBackground:SetPoint("TOPLEFT", element, "TOPLEFT", -1, 1)
								element.ilvl:SetPoint("TOPLEFT", element.ilvlBackground, "TOPLEFT", 1, -2)
							elseif cpos == "BOTTOMLEFT" then
								element.ilvlBackground:SetPoint("BOTTOMLEFT", element, "BOTTOMLEFT", -1, -1)
								element.ilvl:SetPoint("BOTTOMLEFT", element.ilvlBackground, "BOTTOMLEFT", 1, 1)
							elseif cpos == "BOTTOMRIGHT" then
								element.ilvlBackground:SetPoint("BOTTOMRIGHT", element, "BOTTOMRIGHT", 1, -1)
								element.ilvl:SetPoint("BOTTOMRIGHT", element.ilvlBackground, "BOTTOMRIGHT", -1, 1)
							else
								element.ilvlBackground:SetPoint("TOPRIGHT", element, "TOPRIGHT", 1, 1)
								element.ilvl:SetPoint("TOPRIGHT", element.ilvlBackground, "TOPRIGHT", -1, -2)
							end
							element.ilvlBackground:SetSize(30, 16) -- Größe des Hintergrunds (muss ggf. angepasst werden)

							local color = eItem:GetItemQualityColor()
							local itemLevelText = eItem:GetCurrentItemLevel()

							ilvlSum = ilvlSum + itemLevelText * (double and 2 or 1)
							element.ilvl:SetFormattedText(itemLevelText)
							element.ilvl:SetTextColor(color.r, color.g, color.b, 1)

							local textWidth = element.ilvl:GetStringWidth()
							element.ilvlBackground:SetSize(textWidth + 6, element.ilvl:GetStringHeight() + 4) -- Mehr Padding für bessere Lesbarkeit
						end
						if InspectOpt("enchants") then
							if not element.enchant then
								element.enchant = element:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
								if addon.variables.itemSlotSide[key] == 0 then
									element.enchant:SetPoint("BOTTOMLEFT", element, "BOTTOMRIGHT", 2, 1)
								elseif addon.variables.itemSlotSide[key] == 2 then
									element.enchant:SetPoint("TOPLEFT", element, "TOPRIGHT", 2, -1)
								else
									element.enchant:SetPoint("BOTTOMRIGHT", element, "BOTTOMLEFT", -2, 1)
								end
								if addon.variables.shouldEnchanted[key] or addon.variables.shouldEnchantedChecks[key] then
									element.borderGradient = element:CreateTexture(nil, "ARTWORK")
									element.borderGradient:SetPoint("TOPLEFT", element, "TOPLEFT", -2, 2)
									element.borderGradient:SetPoint("BOTTOMRIGHT", element, "BOTTOMRIGHT", 2, -2)
									element.borderGradient:SetColorTexture(1, 0, 0, 0.6) -- Grundfarbe Rot
									element.borderGradient:SetGradient("VERTICAL", CreateColor(1, 0, 0, 1), CreateColor(1, 0.3, 0.3, 0.5))
									element.borderGradient:Hide()
								end
								element.enchant:SetFont(addon.variables.defaultFont, 12, "OUTLINE")
							end
							if element.borderGradient then
								local enchantText = getTooltipInfoFromLink(itemLink)
								local foundEnchant = enchantText ~= nil
								if foundEnchant then element.enchant:SetFormattedText(enchantText) end

								if not foundEnchant and UnitLevel(inspectUnit) == addon.variables.maxLevel then
									element.enchant:SetText("")
									if
										nil == addon.variables.shouldEnchantedChecks[key]
										or (nil ~= addon.variables.shouldEnchantedChecks[key] and addon.variables.shouldEnchantedChecks[key].func(eItem:GetCurrentItemLevel()))
									then
										if key == 17 then
											local _, _, _, _, _, _, _, _, itemEquipLoc = C_Item.GetItemInfoInstant(itemLink)
											if addon.variables.allowedEnchantTypesForOffhand[itemEquipLoc] then
												element.borderGradient:Show()
												element.enchant:SetFormattedText(("|cff%02x%02x%02x"):format(255, 0, 0) .. L["MissingEnchant"] .. "|r")
											end
										else
											element.borderGradient:Show()
											element.enchant:SetFormattedText(("|cff%02x%02x%02x"):format(255, 0, 0) .. L["MissingEnchant"] .. "|r")
										end
									end
								end
							end
						else
							if element.borderGradient then element.borderGradient:Hide() end
							if element.enchant then element.enchant:SetText("") end
						end
					end)
				end
			end
		end
	end
	if InspectOpt("ilvl") and ilvlSum > 0 then pdElement.ilvl:SetText("" .. (math.floor((ilvlSum / 16) * 100 + 0.5) / 100)) end
end

addon.functions.onInspect = onInspect

local function setIlvlText(element, slot)
	-- Hide all gemslots
	if element then
		if element.gems then
			for i = 1, 3 do
				if element.gems[i] then
					element.gems[i]:Hide()
					element.gems[i].icon:SetTexture("Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic")
					element.gems[i]:SetScript("OnEnter", nil)
					element.gems[i].icon:SetVertexColor(1, 1, 1)
				end
			end
		end

		if element.borderGradient then element.borderGradient:Hide() end
		if not (CharOpt("gems") or CharOpt("ilvl") or CharOpt("enchants")) then
			element.ilvl:SetFormattedText("")
			element.enchant:SetText("")
			element.ilvlBackground:Hide()
			return
		end

		local eItem = Item:CreateFromEquipmentSlot(slot)
		if eItem and not eItem:IsItemEmpty() then
			eItem:ContinueOnItemLoad(function()
				local link = eItem:GetItemLink()
				local _, itemID, enchantID = string.match(link, "item:(%d+):(%d*):(%d*):(%d*):(%d*):(%d*):(%d*):(%d*):(%d*):(%d*):(%d*)")
				if CharOpt("gems") then
					local itemStats = C_Item.GetItemStats(link)
					local socketCount = 0
					for statName, statValue in pairs(itemStats) do
						if (statName:find("EMPTY_SOCKET") or statName:find("empty_socket")) and addon.variables.allowedSockets[statName] then socketCount = socketCount + statValue end
					end
					local neededSockets = addon.variables.shouldSocketed[slot] or 0
					if neededSockets then
						local cSeason, isPvP = getTooltipInfo(link)
						if addon.variables.shouldSocketedChecks[slot] then
							if not addon.variables.shouldSocketedChecks[slot].func(cSeason, isPvP) then neededSockets = 0 end
						end
					end
					local displayCount = math.max(socketCount, neededSockets)
					for i = 1, #element.gems do
						if i <= displayCount then
							element.gems[i]:Show()
							element.gems[i].icon:SetTexture("Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic")
							if i > socketCount then
								element.gems[i].icon:SetVertexColor(1, 0, 0)
								element.gems[i]:SetScript("OnEnter", nil)
							else
								element.gems[i].icon:SetVertexColor(1, 1, 1)
							end
						else
							element.gems[i]:Hide()
							element.gems[i]:SetScript("OnEnter", nil)
						end
					end
					if socketCount > 0 then CheckItemGems(element, link, socketCount, slot) end
				else
					for i = 1, #element.gems do
						element.gems[i]:Hide()
						element.gems[i]:SetScript("OnEnter", nil)
					end
				end

				local enchantText = getTooltipInfoFromLink(link)

				if CharOpt("ilvl") then
					local color = eItem:GetItemQualityColor()
					local itemLevelText = eItem:GetCurrentItemLevel()

					local cpos = addon.db["charIlvlPosition"] or "TOPRIGHT"
					element.ilvlBackground:ClearAllPoints()
					element.ilvl:ClearAllPoints()
					if cpos == "TOPLEFT" then
						element.ilvlBackground:SetPoint("TOPLEFT", element, "TOPLEFT", -1, 1)
						element.ilvl:SetPoint("TOPLEFT", element.ilvlBackground, "TOPLEFT", 1, -2)
					elseif cpos == "BOTTOMLEFT" then
						element.ilvlBackground:SetPoint("BOTTOMLEFT", element, "BOTTOMLEFT", -1, -1)
						element.ilvl:SetPoint("BOTTOMLEFT", element.ilvlBackground, "BOTTOMLEFT", 1, 1)
					elseif cpos == "BOTTOMRIGHT" then
						element.ilvlBackground:SetPoint("BOTTOMRIGHT", element, "BOTTOMRIGHT", 1, -1)
						element.ilvl:SetPoint("BOTTOMRIGHT", element.ilvlBackground, "BOTTOMRIGHT", -1, 1)
					else
						element.ilvlBackground:SetPoint("TOPRIGHT", element, "TOPRIGHT", 1, 1)
						element.ilvl:SetPoint("TOPRIGHT", element.ilvlBackground, "TOPRIGHT", -1, -2)
					end

					element.ilvl:SetFormattedText(itemLevelText)
					element.ilvl:SetTextColor(color.r, color.g, color.b, 1)

					local textWidth = element.ilvl:GetStringWidth()
					element.ilvlBackground:SetSize(textWidth + 6, element.ilvl:GetStringHeight() + 4) -- Mehr Padding für bessere Lesbarkeit
				else
					element.ilvl:SetFormattedText("")
					element.ilvlBackground:Hide()
				end

				if CharOpt("enchants") and element.borderGradient then
					local foundEnchant = enchantText ~= nil
					if foundEnchant then element.enchant:SetFormattedText(enchantText) end

					if not foundEnchant and UnitLevel("player") == addon.variables.maxLevel then
						element.enchant:SetText("")
						if
							nil == addon.variables.shouldEnchantedChecks[slot]
							or (nil ~= addon.variables.shouldEnchantedChecks[slot] and addon.variables.shouldEnchantedChecks[slot].func(eItem:GetCurrentItemLevel()))
						then
							if slot == 17 then
								local _, _, _, _, _, _, _, _, itemEquipLoc = C_Item.GetItemInfoInstant(link)
								if addon.variables.allowedEnchantTypesForOffhand[itemEquipLoc] then
									element.borderGradient:Show()
									element.enchant:SetFormattedText(("|cff%02x%02x%02x"):format(255, 0, 0) .. L["MissingEnchant"] .. "|r")
								end
							else
								element.borderGradient:Show()
								element.enchant:SetFormattedText(("|cff%02x%02x%02x"):format(255, 0, 0) .. L["MissingEnchant"] .. "|r")
							end
						end
					end
				else
					element.enchant:SetText("")
				end
			end)
		else
			element.ilvl:SetFormattedText("")
			element.ilvlBackground:Hide()
			element.enchant:SetText("")
			if element.borderGradient then element.borderGradient:Hide() end
		end
	end
end

function addon.functions.IsIndestructible(link)
	local itemParts = { strsplit(":", link) }
	for i = 13, #itemParts do
		local bonusID = tonumber(itemParts[i])
		if bonusID and bonusID == 43 then return true end
	end
	return false
end

local function calculateDurability()
	-- Timerunner gear is indestructible; hide and skip
	if addon.functions and addon.functions.IsTimerunner and addon.functions.IsTimerunner() then
		if addon.general and addon.general.durabilityIconFrame then addon.general.durabilityIconFrame:Hide() end
		return
	end
	local maxDur = 0 -- combined value of durability
	local currentDura = 0
	local critDura = 0 -- counter of items under 50%

	for key, _ in pairs(addon.variables.itemSlots) do
		local eItem = Item:CreateFromEquipmentSlot(key)
		if eItem and not eItem:IsItemEmpty() then
			eItem:ContinueOnItemLoad(function()
				local link = eItem:GetItemLink()
				if link then
					if addon.functions.IsIndestructible(link) == false then
						local current, maximum = GetInventoryItemDurability(key)
						if nil ~= current then
							local fDur = tonumber(string.format("%." .. 0 .. "f", current * 100 / maximum))
							maxDur = maxDur + maximum
							currentDura = currentDura + current
							if fDur < 50 then critDura = critDura + 1 end
						end
					end
				end
			end)
		end
	end

	-- When we only have full durable items so fake the numbers to show 100%
	if maxDur == 0 and currentDura == 0 then
		maxDur = 100
		currentDura = 100
	end

	local durValue = currentDura / maxDur * 100

	addon.variables.durabilityCount = tonumber(string.format("%." .. 0 .. "f", durValue)) .. "%"
	addon.general.durabilityIconFrame.count:SetText(addon.variables.durabilityCount)

	if tonumber(string.format("%." .. 0 .. "f", durValue)) > 80 then
		addon.general.durabilityIconFrame.count:SetTextColor(1, 1, 1)
	elseif tonumber(string.format("%." .. 0 .. "f", durValue)) > 50 then
		addon.general.durabilityIconFrame.count:SetTextColor(1, 1, 0)
	else
		addon.general.durabilityIconFrame.count:SetTextColor(1, 0, 0)
	end
end
addon.functions.calculateDurability = calculateDurability

local function UpdateItemLevel()
	local statFrame = CharacterStatsPane.ItemLevelFrame
	if statFrame and statFrame.Value then
		local avgItemLevel, equippedItemLevel = GetAverageItemLevel()
		local customItemLevel = equippedItemLevel
		statFrame.Value:SetText(string.format("%.2f", customItemLevel))
	end
end
hooksecurefunc("PaperDollFrame_SetItemLevel", function(statFrame, unit) UpdateItemLevel() end)

local function setCharFrame()
	UpdateItemLevel()
	if not addon.general.iconFrame then addon.functions.catalystChecks() end
	if addon.db["showCatalystChargesOnCharframe"] and addon.variables.catalystID and addon.general.iconFrame and not addon.functions.IsTimerunner() then
		local cataclystInfo = C_CurrencyInfo.GetCurrencyInfo(addon.variables.catalystID)
		addon.general.iconFrame.count:SetText(cataclystInfo.quantity)
	end
	if addon.db["showDurabilityOnCharframe"] and not addon.functions.IsTimerunner() then calculateDurability() end
	for key, value in pairs(addon.variables.itemSlots) do
		setIlvlText(value, key)
	end
end
addon.functions.setCharFrame = setCharFrame

function addon.functions.createCatalystFrame()
	if addon.variables.catalystID then
		if addon.general.iconFrame then return end
		local cataclystInfo = C_CurrencyInfo.GetCurrencyInfo(addon.variables.catalystID)
		if cataclystInfo then
			local iconID = cataclystInfo.iconFileID

			addon.general.iconFrame = CreateFrame("Button", nil, PaperDollFrame, "BackdropTemplate")
			addon.general.iconFrame:SetSize(32, 32)
			addon.general.iconFrame:SetPoint("BOTTOMLEFT", PaperDollSidebarTab3, "BOTTOMRIGHT", 4, 0)

			addon.general.iconFrame.icon = addon.general.iconFrame:CreateTexture(nil, "OVERLAY")
			addon.general.iconFrame.icon:SetSize(32, 32)
			addon.general.iconFrame.icon:SetPoint("CENTER", addon.general.iconFrame, "CENTER")
			addon.general.iconFrame.icon:SetTexture(iconID)

			addon.general.iconFrame.count = addon.general.iconFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
			addon.general.iconFrame.count:SetPoint("BOTTOMRIGHT", addon.general.iconFrame, "BOTTOMRIGHT", 1, 2)
			addon.general.iconFrame.count:SetFont(addon.variables.defaultFont, 14, "OUTLINE")
			addon.general.iconFrame.count:SetText(cataclystInfo.quantity)
			addon.general.iconFrame.count:SetTextColor(1, 0.82, 0)
			if addon.db["showCatalystChargesOnCharframe"] == false then addon.general.iconFrame:Hide() end
		end
	end
end

local function updateFlyoutButtonInfo(button)
	if not button then return end

	if CharOpt("ilvl") then
		-- Reset stale overlays on recycled flyout buttons
		if button.ItemUpgradeArrow then button.ItemUpgradeArrow:Hide() end
		if button.ItemUpgradeIcon then button.ItemUpgradeIcon:Hide() end
		local location = button.location
		if not location then return end

		-- TODO 12.0: EquipmentManager_UnpackLocation will change once Void Storage is removed
		local itemLink, _, _, bags, _, slot, bag
		if type(button.location) == "number" then
			local locationData = EquipmentManager_GetLocationData(location)
			bags = locationData.isBags or false
			slot = locationData.slot
			bag = locationData.bag

			if bags then
				itemLink = C_Container.GetContainerItemLink(bag, slot)
			elseif not bags then
				itemLink = GetInventoryItemLink("player", slot)
			end
		elseif button.itemLink then
			itemLink = button.itemLink
		end
		if itemLink then
			local eItem = Item:CreateFromItemLink(itemLink)
			if eItem and not eItem:IsItemEmpty() then
				eItem:ContinueOnItemLoad(function()
					local itemLevel = eItem:GetCurrentItemLevel()
					local quality = eItem:GetItemQualityColor()

					if not button.ItemLevelText then
						button.ItemLevelText = button:CreateFontString(nil, "OVERLAY")
						button.ItemLevelText:SetFont(addon.variables.defaultFont, 16, "OUTLINE")
					end
					button.ItemLevelText:ClearAllPoints()
					local pos = addon.db["bagIlvlPosition"] or "TOPRIGHT"
					if pos == "TOPLEFT" then
						button.ItemLevelText:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
					elseif pos == "BOTTOMLEFT" then
						button.ItemLevelText:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
					elseif pos == "BOTTOMRIGHT" then
						button.ItemLevelText:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 2)
					else
						button.ItemLevelText:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
					end

					-- Setze den Text und die Farbe
					button.ItemLevelText:SetText(itemLevel)
					button.ItemLevelText:SetTextColor(quality.r, quality.g, quality.b, 1)
					button.ItemLevelText:Show()

					-- Upgrade icon for Flyout items: compare against the specific slot's equipped item
					if addon.db["showUpgradeArrowOnBagItems"] and itemLink then
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
								return { 16, 17 }
							end
							return nil
						end

						local invSlot = select(4, C_Item.GetItemInfoInstant(itemLink))
						local slots = getEquipSlotsFor(invSlot)

						-- Determine the specific target slot for this flyout (e.g., 13 or 14 for trinkets)
						local flyoutFrame = _G.EquipmentFlyoutFrame
						local targetSlot = flyoutFrame and flyoutFrame.button and flyoutFrame.button.GetID and flyoutFrame.button:GetID() or nil

						local baseline
						if slots and #slots > 0 then
							local function containsSlot(tbl, val)
								for i = 1, #tbl do
									if tbl[i] == val then return true end
								end
								return false
							end
							if targetSlot and containsSlot(slots, targetSlot) then
								-- Compare only against the item in the specific flyout's slot
								local eqLink = GetInventoryItemLink("player", targetSlot)
								baseline = eqLink and (C_Item.GetDetailedItemLevelInfo(eqLink) or 0) or 0
							else
								-- Fallback: compare against the worst of the valid slots
								for _, s in ipairs(slots) do
									local eqLink = GetInventoryItemLink("player", s)
									local eqIlvl = eqLink and (C_Item.GetDetailedItemLevelInfo(eqLink) or 0) or 0
									if baseline == nil then
										baseline = eqIlvl
									else
										baseline = math.min(baseline, eqIlvl)
									end
								end
							end
						end
						local isUpgrade = baseline ~= nil and itemLevel and itemLevel > baseline
						if isUpgrade then
							if not button.ItemUpgradeIcon then
								button.ItemUpgradeIcon = button:CreateTexture(nil, "OVERLAY")
								button.ItemUpgradeIcon:SetSize(14, 14)
							end
							button.ItemUpgradeIcon:SetTexture("Interface\\AddOns\\EnhanceQoL\\Icons\\upgradeilvl.tga")
							button.ItemUpgradeIcon:ClearAllPoints()
							local posUp = addon.db["bagUpgradeIconPosition"] or "BOTTOMRIGHT"
							if posUp == "TOPRIGHT" then
								button.ItemUpgradeIcon:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -2)
							elseif posUp == "TOPLEFT" then
								button.ItemUpgradeIcon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
							elseif posUp == "BOTTOMLEFT" then
								button.ItemUpgradeIcon:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
							else
								button.ItemUpgradeIcon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 2)
							end
							button.ItemUpgradeIcon:Show()
						elseif button.ItemUpgradeIcon then
							button.ItemUpgradeIcon:Hide()
						end
					end

					local bType
					if bag and slot then
						if addon.db["showBindOnBagItems"] then
							local data = C_TooltipInfo.GetBagItem(bag, slot)
							for i, v in pairs(data.lines) do
								if v.type == 20 then
									if v.leftText == ITEM_BIND_ON_EQUIP then
										bType = "BoE"
									elseif v.leftText == ITEM_ACCOUNTBOUND_UNTIL_EQUIP or v.leftText == ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP then
										bType = "WuE"
									elseif v.leftText == ITEM_ACCOUNTBOUND or v.leftText == ITEM_BIND_TO_BNETACCOUNT then
										bType = "WB"
									end
									break
								end
							end
						end
					end
					if bType then
						if not button.ItemBoundType then
							button.ItemBoundType = button:CreateFontString(nil, "OVERLAY")
							button.ItemBoundType:SetFont(addon.variables.defaultFont, 10, "OUTLINE")
							button.ItemBoundType:SetShadowOffset(2, 2)
							button.ItemBoundType:SetShadowColor(0, 0, 0, 1)
						end
						button.ItemBoundType:ClearAllPoints()
						if addon.db["bagIlvlPosition"] == "BOTTOMLEFT" then
							button.ItemBoundType:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
						elseif addon.db["bagIlvlPosition"] == "BOTTOMRIGHT" then
							button.ItemBoundType:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -2)
						else
							button.ItemBoundType:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
						end
						button.ItemBoundType:SetFormattedText(bType)
						button.ItemBoundType:Show()
					elseif button.ItemBoundType then
						button.ItemBoundType:Hide()
					end
				end)
			end
		elseif button.ItemLevelText then
			if button.ItemBoundType then button.ItemBoundType:Hide() end
			if button.ItemUpgradeArrow then button.ItemUpgradeArrow:Hide() end
			if button.ItemUpgradeIcon then button.ItemUpgradeIcon:Hide() end
			button.ItemLevelText:Hide()
		end
	elseif button.ItemLevelText then
		if button.ItemBoundType then button.ItemBoundType:Hide() end
		if button.ItemUpgradeArrow then button.ItemUpgradeArrow:Hide() end
		if button.ItemUpgradeIcon then button.ItemUpgradeIcon:Hide() end
		button.ItemLevelText:Hide()
	end
end

local function desaturateMerchantIcon(itemButton, desaturate)
	if not itemButton then return end

	local iconTexture = itemButton.Icon or itemButton.icon or itemButton.IconTexture or itemButton:GetNormalTexture()
	if iconTexture then
		if iconTexture.SetDesaturated then iconTexture:SetDesaturated(desaturate) end
		if iconTexture.SetVertexColor then
			if desaturate then
				iconTexture:SetVertexColor(0.7, 0.7, 0.7, 1)
			else
				iconTexture:SetVertexColor(1, 1, 1, 1)
			end
		end
	end
end
local function applyKnownFontTint(fontString, state)
	if not fontString or fontString.GetObjectType and fontString:GetObjectType() ~= "FontString" then return end
	if state then
		if not fontString.__EnhanceQoLOriginalColor then
			local r, g, b, a = fontString:GetTextColor()
			if not r or not g or not b then
				r, g, b = 1, 1, 1
			end
			if not a then a = 1 end
			fontString.__EnhanceQoLOriginalColor = { r, g, b, a }
		end
		local stored = fontString.__EnhanceQoLOriginalColor
		local r, g, b = stored[1], stored[2], stored[3]
		fontString:SetTextColor(r or 1, g or 1, b or 1, 0.4)
	elseif fontString.__EnhanceQoLOriginalColor then
		local color = fontString.__EnhanceQoLOriginalColor
		fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
		fontString.__EnhanceQoLOriginalColor = nil
	end
end

local function applyKnownTextureTint(texture, state)
	if not texture or texture.GetObjectType and texture:GetObjectType() ~= "Texture" then return end
	if state then
		if not texture.__EnhanceQoLOriginalVertexColor then
			local r, g, b, a = texture:GetVertexColor()
			if not r or not g or not b then
				r, g, b = 1, 1, 1
			end
			if not a or a == 0 then a = texture:GetAlpha() or 1 end
			texture.__EnhanceQoLOriginalVertexColor = { r, g, b, a }
		end
		local stored = texture.__EnhanceQoLOriginalVertexColor
		texture:SetVertexColor(0.55, 0.55, 0.55, stored and stored[4] or texture:GetAlpha() or 1)
	else
		local color = texture.__EnhanceQoLOriginalVertexColor
		if color then
			texture:SetVertexColor(color[1], color[2], color[3], color[4] or texture:GetAlpha() or 1)
			texture.__EnhanceQoLOriginalVertexColor = nil
		end
	end
end
local function applyKnownStateToFrame(frame, state, visited)
	if not frame or visited[frame] then return end
	visited[frame] = true

	local objectType = frame.GetObjectType and frame:GetObjectType()
	if objectType == "FontString" then
		applyKnownFontTint(frame, state)
		return
	elseif objectType == "Texture" then
		applyKnownTextureTint(frame, state)
		return
	end

	if frame.GetRegions then
		local regions = { frame:GetRegions() }
		for _, region in ipairs(regions) do
			applyKnownStateToFrame(region, state, visited)
		end
	end

	if frame.GetChildren then
		local children = { frame:GetChildren() }
		for _, child in ipairs(children) do
			applyKnownStateToFrame(child, state, visited)
		end
	end
end
local function setMerchantKnownIcon(itemButton, state)
	if not itemButton then return end

	if state then
		if not itemButton.MerchantKnownIcon then
			local icon = itemButton:CreateTexture(nil, "OVERLAY", nil, 7)
			if icon.SetAtlas and icon:SetAtlas("common-icon-checkmark") then
				icon:SetTexCoord(0, 1, 0, 1)
			else
				icon:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
			end
			icon:SetSize(18, 18)
			icon:SetPoint("TOPLEFT", itemButton, "TOPLEFT", -2, 2)
			icon:SetVertexColor(0.2, 0.9, 0.2, 0.9)
			itemButton.MerchantKnownIcon = icon
		end
		itemButton.MerchantKnownIcon:Show()
		if not itemButton.MerchantKnownOverlay then
			local overlay = itemButton:CreateTexture(nil, "OVERLAY", nil, 7)
			overlay:SetAllPoints()
			overlay:SetColorTexture(0.1, 0.1, 0.1, 0.55)
			itemButton.MerchantKnownOverlay = overlay
		end
		itemButton.MerchantKnownOverlay:Show()
		desaturateMerchantIcon(itemButton, true)
		local parentFrame = itemButton:GetParent()
		if parentFrame then
			local parentName = parentFrame:GetName()
			local nameRegion = parentFrame.Name or (parentName and _G[parentName .. "Name"])
			if nameRegion then applyKnownFontTint(nameRegion, true) end

			local moneyFrame = parentFrame.MoneyFrame or (parentName and _G[parentName .. "MoneyFrame"])
			if moneyFrame then applyKnownStateToFrame(moneyFrame, true, {}) end

			local altCurrencyFrame = parentFrame.AltCurrencyFrame or (parentName and _G[parentName .. "AltCurrencyFrame"])
			if altCurrencyFrame then applyKnownStateToFrame(altCurrencyFrame, true, {}) end
		end
	else
		if itemButton.MerchantKnownIcon then itemButton.MerchantKnownIcon:Hide() end
		if itemButton.MerchantKnownOverlay then itemButton.MerchantKnownOverlay:Hide() end
		-- desaturateMerchantIcon(itemButton, false)
		local parentFrame = itemButton:GetParent()
		if parentFrame then
			local parentName = parentFrame:GetName()
			local nameRegion = parentFrame.Name or (parentName and _G[parentName .. "Name"])
			if nameRegion then applyKnownFontTint(nameRegion, false) end

			local moneyFrame = parentFrame.MoneyFrame or (parentName and _G[parentName .. "MoneyFrame"])
			if moneyFrame then applyKnownStateToFrame(moneyFrame, false, {}) end

			local altCurrencyFrame = parentFrame.AltCurrencyFrame or (parentName and _G[parentName .. "AltCurrencyFrame"])
			if altCurrencyFrame then applyKnownStateToFrame(altCurrencyFrame, false, {}) end
		end
	end
end

local function merchantItemIsKnown(itemIndex)
	if not itemIndex or itemIndex <= 0 then return false end
	if not C_TooltipInfo or (not C_TooltipInfo.GetMerchantItem and not C_TooltipInfo.GetHyperlink) then return false end

	local tooltipData
	if C_TooltipInfo.GetMerchantItem then tooltipData = C_TooltipInfo.GetMerchantItem(itemIndex) end

	if not tooltipData and C_TooltipInfo.GetHyperlink and GetMerchantItemLink then
		local itemLink = GetMerchantItemLink(itemIndex)
		if itemLink then tooltipData = C_TooltipInfo.GetHyperlink(itemLink) end
	end

	if not tooltipData then return false end
	if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(tooltipData) end
	if not tooltipData.lines then return false end
	for _, line in ipairs(tooltipData.lines) do
		if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(line) end
		local text = line.leftText or line.rightText
		if text and text:find(ITEM_SPELL_KNOWN, 1, true) then return true end
	end
	return false
end

local petCollectedCache = {}

local function clearPetCollectedCache() wipe(petCollectedCache) end

local function getPetCollectedCount(speciesID)
	if not speciesID then return 0 end
	local cached = petCollectedCache[speciesID]
	if cached ~= nil then return cached end
	if not C_PetJournal or not C_PetJournal.GetNumCollectedInfo then return 0 end
	local numCollected = C_PetJournal.GetNumCollectedInfo(speciesID) or 0
	petCollectedCache[speciesID] = numCollected
	return numCollected
end

local function IsPetAlreadyCollectedFromItem(itemID)
	if not C_PetJournal or not C_PetJournal.GetNumCollectedInfo then return false end
	if not itemID then return false end

	if not C_PetJournal.GetPetInfoByItemID then return false end

	local speciesID = select(13, C_PetJournal.GetPetInfoByItemID(itemID))
	if not speciesID then return false end

	local count = getPetCollectedCount(speciesID)
	return count > 0
end

if C_PetJournal then
	local petJournalWatcher = CreateFrame("Frame")
	petJournalWatcher:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
	petJournalWatcher:RegisterEvent("PET_JOURNAL_PET_DELETED")
	petJournalWatcher:RegisterEvent("PET_JOURNAL_PET_RESTORED")
	petJournalWatcher:RegisterEvent("NEW_PET_ADDED")
	petJournalWatcher:SetScript("OnEvent", clearPetCollectedCache)
end

local function applyMerchantButtonInfo()
	local showIlvl = addon.db["showIlvlOnMerchantframe"]
	local highlightKnown = addon.db["markKnownOnMerchant"]
	local highlightCollectedPets = addon.db["markCollectedPetsOnMerchant"]
	if not showIlvl and not highlightKnown and not highlightCollectedPets then
		local itemsPerPage = MERCHANT_ITEMS_PER_PAGE or 10
		for i = 1, itemsPerPage do
			local itemButton = _G["MerchantItem" .. i .. "ItemButton"]
			if itemButton then
				setMerchantKnownIcon(itemButton, false)
				if itemButton.ItemUpgradeIcon then itemButton.ItemUpgradeIcon:Hide() end
				if itemButton.ItemUpgradeArrow then itemButton.ItemUpgradeArrow:Hide() end
				if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
				if itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
			end
		end
		return
	end

	local itemsPerPage = MERCHANT_ITEMS_PER_PAGE or 10 -- Anzahl der Items pro Seite (Standard 10)
	local currentPage = MerchantFrame.page or 1 -- Aktuelle Seite
	local startIndex = (currentPage - 1) * itemsPerPage + 1 -- Startindex basierend auf der aktuellen Seite

	for i = 1, itemsPerPage do
		local itemButton = _G["MerchantItem" .. i .. "ItemButton"]
		if itemButton then
			if not itemButton:IsShown() then
				setMerchantKnownIcon(itemButton, false)
				if itemButton.ItemUpgradeArrow then itemButton.ItemUpgradeArrow:Hide() end
				if itemButton.ItemUpgradeIcon then itemButton.ItemUpgradeIcon:Hide() end
				if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
				if itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
			else
				local itemIndex = startIndex + i - 1
				local buttonID = itemButton:GetID()
				if buttonID and buttonID > 0 then itemIndex = buttonID end

				local itemLink = itemIndex and GetMerchantItemLink(itemIndex) or nil

				if itemLink then
					local merchantButton = itemButton:GetParent()
					if merchantButton and merchantButton.GetName and merchantButton:GetName():find("^MerchantItem%d+$") then MerchantFrameItem_UpdateQuality(merchantButton, itemLink) end
				end

				local shouldHighlight = false
				if highlightKnown and merchantItemIsKnown(itemIndex) then
					shouldHighlight = true
				elseif highlightCollectedPets and itemLink then
					local itemID, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemLink)
					if classID == 15 and subclassID == 2 then
						local collected = IsPetAlreadyCollectedFromItem(itemID)
						if collected then shouldHighlight = true end
					end
				end
				setMerchantKnownIcon(itemButton, shouldHighlight)
				-- Clear any stale overlays from recycled buttons
				if itemButton.ItemUpgradeArrow then itemButton.ItemUpgradeArrow:Hide() end
				if itemButton.ItemUpgradeIcon then itemButton.ItemUpgradeIcon:Hide() end
				if itemButton.ItemUpgradeIcon then itemButton.ItemUpgradeIcon:Hide() end
				if showIlvl and itemLink and itemLink:find("item:") then
					local eItem = Item:CreateFromItemLink(itemLink)
					eItem:ContinueOnItemLoad(function()
						-- local itemName, _, _, _, _, _, _, _, itemEquipLoc = C_Item.GetItemInfo(itemLink)
						local _, _, _, _, _, _, _, _, itemEquipLoc, _, _, classID, subclassID = C_Item.GetItemInfo(itemLink)

						if
							(itemEquipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" or (classID == 4 and subclassID == 0)) and not (classID == 4 and subclassID == 5) -- Cosmetic
						then
							local link = eItem:GetItemLink()
							local invSlot = select(4, C_Item.GetItemInfoInstant(link))
							if nil == addon.variables.allowedEquipSlotsBagIlvl[invSlot] then
								if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
								if itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
								return
							end

							if not itemButton.ItemLevelText then
								itemButton.ItemLevelText = itemButton:CreateFontString(nil, "OVERLAY")
								itemButton.ItemLevelText:SetFont(addon.variables.defaultFont, 16, "OUTLINE")
								itemButton.ItemLevelText:SetShadowOffset(1, -1)
								itemButton.ItemLevelText:SetShadowColor(0, 0, 0, 1)
							end
							itemButton.ItemLevelText:ClearAllPoints()
							local pos = addon.db["bagIlvlPosition"] or "TOPRIGHT"
							if pos == "TOPLEFT" then
								itemButton.ItemLevelText:SetPoint("TOPLEFT", itemButton, "TOPLEFT", 2, -2)
							elseif pos == "BOTTOMLEFT" then
								itemButton.ItemLevelText:SetPoint("BOTTOMLEFT", itemButton, "BOTTOMLEFT", 2, 2)
							elseif pos == "BOTTOMRIGHT" then
								itemButton.ItemLevelText:SetPoint("BOTTOMRIGHT", itemButton, "BOTTOMRIGHT", -1, 2)
							else
								itemButton.ItemLevelText:SetPoint("TOPRIGHT", itemButton, "TOPRIGHT", -1, -1)
							end

							local color = eItem:GetItemQualityColor()
							local candidateIlvl = eItem:GetCurrentItemLevel()
							itemButton.ItemLevelText:SetText(candidateIlvl)
							itemButton.ItemLevelText:SetTextColor(color.r, color.g, color.b, 1)
							itemButton.ItemLevelText:Show()
							local bType

							-- Upgrade arrow for Merchant items
							if addon.db["showUpgradeArrowOnBagItems"] then
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
										return { 16, 17 }
									end
									return nil
								end

								local invSlot = select(4, C_Item.GetItemInfoInstant(itemLink))
								local slots = getEquipSlotsFor(invSlot)
								local baseline
								if slots and #slots > 0 then
									for _, s in ipairs(slots) do
										local eqLink = GetInventoryItemLink("player", s)
										local eqIlvl = eqLink and (C_Item.GetDetailedItemLevelInfo(eqLink) or 0) or 0
										if baseline == nil then
											baseline = eqIlvl
										else
											baseline = math.min(baseline, eqIlvl)
										end
									end
								end
								local isUpgrade = baseline ~= nil and candidateIlvl and candidateIlvl > baseline
								if isUpgrade then
									if not itemButton.ItemUpgradeIcon then
										itemButton.ItemUpgradeIcon = itemButton:CreateTexture(nil, "OVERLAY")
										itemButton.ItemUpgradeIcon:SetSize(14, 14)
									end
									itemButton.ItemUpgradeIcon:SetTexture("Interface\\AddOns\\EnhanceQoL\\Icons\\upgradeilvl.tga")
									itemButton.ItemUpgradeIcon:ClearAllPoints()
									local posUp = addon.db["bagUpgradeIconPosition"] or "BOTTOMRIGHT"
									if posUp == "TOPRIGHT" then
										itemButton.ItemUpgradeIcon:SetPoint("TOPRIGHT", itemButton, "TOPRIGHT", -1, -2)
									elseif posUp == "TOPLEFT" then
										itemButton.ItemUpgradeIcon:SetPoint("TOPLEFT", itemButton, "TOPLEFT", 2, -2)
									elseif posUp == "BOTTOMLEFT" then
										itemButton.ItemUpgradeIcon:SetPoint("BOTTOMLEFT", itemButton, "BOTTOMLEFT", 2, 2)
									else
										itemButton.ItemUpgradeIcon:SetPoint("BOTTOMRIGHT", itemButton, "BOTTOMRIGHT", -1, 2)
									end
									itemButton.ItemUpgradeIcon:Show()
								elseif itemButton.ItemUpgradeIcon then
									itemButton.ItemUpgradeIcon:Hide()
								end
							end

							if addon.db["showBindOnBagItems"] then
								local data = C_TooltipInfo.GetMerchantItem(itemIndex)
								for i, v in pairs(data.lines) do
									if v.type == 20 then
										if v.leftText == ITEM_BIND_ON_EQUIP then
											bType = "BoE"
										elseif v.leftText == ITEM_ACCOUNTBOUND_UNTIL_EQUIP or v.leftText == ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP then
											bType = "WuE"
										elseif v.leftText == ITEM_ACCOUNTBOUND or v.leftText == ITEM_BIND_TO_BNETACCOUNT then
											bType = "WB"
										end
										break
									end
								end
							end
							if bType then
								if not itemButton.ItemBoundType then
									itemButton.ItemBoundType = itemButton:CreateFontString(nil, "OVERLAY")
									itemButton.ItemBoundType:SetFont(addon.variables.defaultFont, 10, "OUTLINE")
									itemButton.ItemBoundType:SetShadowOffset(2, 2)
									itemButton.ItemBoundType:SetShadowColor(0, 0, 0, 1)
								end
								itemButton.ItemBoundType:ClearAllPoints()
								if addon.db["bagIlvlPosition"] == "BOTTOMLEFT" then
									itemButton.ItemBoundType:SetPoint("TOPLEFT", itemButton, "TOPLEFT", 2, -2)
								elseif addon.db["bagIlvlPosition"] == "BOTTOMRIGHT" then
									itemButton.ItemBoundType:SetPoint("TOPRIGHT", itemButton, "TOPRIGHT", -1, -2)
								else
									itemButton.ItemBoundType:SetPoint("BOTTOMLEFT", itemButton, "BOTTOMLEFT", 2, 2)
								end
								itemButton.ItemBoundType:SetFormattedText(bType)
								itemButton.ItemBoundType:Show()
							elseif itemButton.ItemBoundType then
								itemButton.ItemBoundType:Hide()
							end
						else
							if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
							if itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
						end
					end)
				else
					if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
					if itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
				end
			end
		end
	end
end

local merchantRefreshPending = false
local function updateMerchantButtonInfo()
	if merchantRefreshPending then return end
	merchantRefreshPending = true

	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			merchantRefreshPending = false
			applyMerchantButtonInfo()
		end)
	else
		merchantRefreshPending = false
		applyMerchantButtonInfo()
	end
end

local function updateBuybackButtonInfo()
	local showIlvl = addon.db["showIlvlOnMerchantframe"]
	local highlightKnown = addon.db["markKnownOnMerchant"]
	if not showIlvl and not highlightKnown then return end

	local itemsPerPage = BUYBACK_ITEMS_PER_PAGE or 12
	for i = 1, itemsPerPage do
		local itemButton = _G["MerchantItem" .. i .. "ItemButton"]
		local itemLink = GetBuybackItemLink(i)

		if itemButton then
			setMerchantKnownIcon(itemButton, false)
			if not showIlvl then
				if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
				if itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
			elseif itemLink and itemLink:find("item:") then
				local eItem = Item:CreateFromItemLink(itemLink)
				eItem:ContinueOnItemLoad(function()
					local _, _, _, _, _, _, _, _, itemEquipLoc, _, _, classID, subclassID = C_Item.GetItemInfo(itemLink)

					if (itemEquipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" or (classID == 4 and subclassID == 0)) and not (classID == 4 and subclassID == 5) then
						local link = eItem:GetItemLink()
						local invSlot = select(4, C_Item.GetItemInfoInstant(link))
						if nil == addon.variables.allowedEquipSlotsBagIlvl[invSlot] then
							if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
							if itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
							return
						end

						if not itemButton.ItemLevelText then
							itemButton.ItemLevelText = itemButton:CreateFontString(nil, "OVERLAY")
							itemButton.ItemLevelText:SetFont(addon.variables.defaultFont, 16, "OUTLINE")
							itemButton.ItemLevelText:SetShadowOffset(1, -1)
							itemButton.ItemLevelText:SetShadowColor(0, 0, 0, 1)
						end
						itemButton.ItemLevelText:ClearAllPoints()
						local pos = addon.db["bagIlvlPosition"] or "TOPRIGHT"
						if pos == "TOPLEFT" then
							itemButton.ItemLevelText:SetPoint("TOPLEFT", itemButton, "TOPLEFT", 2, -2)
						elseif pos == "BOTTOMLEFT" then
							itemButton.ItemLevelText:SetPoint("BOTTOMLEFT", itemButton, "BOTTOMLEFT", 2, 2)
						elseif pos == "BOTTOMRIGHT" then
							itemButton.ItemLevelText:SetPoint("BOTTOMRIGHT", itemButton, "BOTTOMRIGHT", -1, 2)
						else
							itemButton.ItemLevelText:SetPoint("TOPRIGHT", itemButton, "TOPRIGHT", -1, -1)
						end

						local color = eItem:GetItemQualityColor()
						itemButton.ItemLevelText:SetText(eItem:GetCurrentItemLevel())
						itemButton.ItemLevelText:SetTextColor(color.r, color.g, color.b, 1)
						itemButton.ItemLevelText:Show()

						local bType
						if addon.db["showBindOnBagItems"] then
							local data = C_TooltipInfo.GetBuybackItem(i)
							for _, v in pairs(data.lines) do
								if v.type == 20 then
									if v.leftText == ITEM_BIND_ON_EQUIP then
										bType = "BoE"
									elseif v.leftText == ITEM_ACCOUNTBOUND_UNTIL_EQUIP or v.leftText == ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP then
										bType = "WuE"
									elseif v.leftText == ITEM_ACCOUNTBOUND or v.leftText == ITEM_BIND_TO_BNETACCOUNT then
										bType = "WB"
									end
									break
								end
							end
						end
						if bType then
							if not itemButton.ItemBoundType then
								itemButton.ItemBoundType = itemButton:CreateFontString(nil, "OVERLAY")
								itemButton.ItemBoundType:SetFont(addon.variables.defaultFont, 10, "OUTLINE")
								itemButton.ItemBoundType:SetShadowOffset(2, 2)
								itemButton.ItemBoundType:SetShadowColor(0, 0, 0, 1)
							end
							itemButton.ItemBoundType:ClearAllPoints()
							if addon.db["bagIlvlPosition"] == "BOTTOMLEFT" then
								itemButton.ItemBoundType:SetPoint("TOPLEFT", itemButton, "TOPLEFT", 2, -2)
							elseif addon.db["bagIlvlPosition"] == "BOTTOMRIGHT" then
								itemButton.ItemBoundType:SetPoint("TOPRIGHT", itemButton, "TOPRIGHT", -1, -2)
							else
								itemButton.ItemBoundType:SetPoint("BOTTOMLEFT", itemButton, "BOTTOMLEFT", 2, 2)
							end
							itemButton.ItemBoundType:SetFormattedText(bType)
							itemButton.ItemBoundType:Show()
						elseif itemButton.ItemBoundType then
							itemButton.ItemBoundType:Hide()
						end
					else
						if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
						if itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
					end
				end)
			else
				if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
				if itemButton.ItemUpgradeArrow then itemButton.ItemUpgradeArrow:Hide() end
				if itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
			end
		end
	end
end

function addon.functions.initItemInventory()
	addon.functions.InitDBValue("showIlvlOnBankFrame", false)
	addon.functions.InitDBValue("showIlvlOnMerchantframe", false)
	addon.functions.InitDBValue("markKnownOnMerchant", false)
	addon.functions.InitDBValue("markCollectedPetsOnMerchant", false)
	addon.functions.InitDBValue("showIlvlOnCharframe", false)
	addon.functions.InitDBValue("showIlvlOnBagItems", false)
	addon.functions.InitDBValue("showBagFilterMenu", false)
	addon.functions.InitDBValue("bagFilterDockFrame", true)
	addon.functions.InitDBValue("showBindOnBagItems", false)
	addon.functions.InitDBValue("showUpgradeArrowOnBagItems", false)
	addon.functions.InitDBValue("bagIlvlPosition", "TOPRIGHT")
	addon.functions.InitDBValue("bagUpgradeIconPosition", "BOTTOMRIGHT")
	addon.functions.InitDBValue("charIlvlPosition", "TOPRIGHT")
	addon.functions.InitDBValue("fadeBagQualityIcons", false)
	addon.functions.InitDBValue("showGemsOnCharframe", false)
	addon.functions.InitDBValue("showGemsTooltipOnCharframe", false)
	addon.functions.InitDBValue("showEnchantOnCharframe", false)
	addon.functions.InitDBValue("showCatalystChargesOnCharframe", false)
	addon.functions.InitDBValue("movementSpeedStatEnabled", false)
	addon.functions.InitDBValue("showCloakUpgradeButton", false)
	addon.functions.InitDBValue("bagFilterFrameData", {})
	addon.functions.InitDBValue("closeBagsOnAuctionHouse", false)
	addon.functions.InitDBValue("showDurabilityOnCharframe", false)

	hooksecurefunc(ContainerFrameCombinedBags, "UpdateItems", addon.functions.updateBags)
	for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
		hooksecurefunc(frame, "UpdateItems", addon.functions.updateBags)
	end

	hooksecurefunc("MerchantFrame_UpdateMerchantInfo", updateMerchantButtonInfo)
	hooksecurefunc("MerchantFrame_UpdateBuybackInfo", updateBuybackButtonInfo)

	local function RefreshAllFlyoutButtons()
		local f = _G.EquipmentFlyoutFrame
		if not f then return end
		-- Blizzard pflegt eine buttons-Liste, darauf verlassen wir uns:
		if f.buttons then
			for _, btn in ipairs(f.buttons) do
				if btn and btn:IsShown() then
					updateFlyoutButtonInfo(btn) -- <- deine vorhandene Routine
				end
			end
			return
		end
		-- Fallback (falls mal keine Liste existiert): Children scannen
		for i = 1, (f:GetNumChildren() or 0) do
			local child = select(i, f:GetChildren())
			if child and child:IsShown() and child.icon then updateFlyoutButtonInfo(child) end
		end
	end
	hooksecurefunc("EquipmentFlyout_UpdateItems", RefreshAllFlyoutButtons)

	if _G.BankPanel then
		hooksecurefunc(BankPanel, "GenerateItemSlotsForSelectedTab", addon.functions.updateBags)
		hooksecurefunc(BankPanel, "RefreshAllItemsForSelectedTab", addon.functions.updateBags)
		hooksecurefunc(BankPanel, "UpdateSearchResults", addon.functions.updateBags)
	end

	-- Add Cataclyst charges in char frame
	addon.functions.createCatalystFrame()
	if addon.MovementSpeedStat and addon.MovementSpeedStat.Refresh then addon.MovementSpeedStat.Refresh() end
	-- add durability icon on charframe

	addon.general.durabilityIconFrame = CreateFrame("Button", nil, PaperDollFrame, "BackdropTemplate")
	addon.general.durabilityIconFrame:SetSize(32, 32)
	addon.general.durabilityIconFrame:SetPoint("TOPLEFT", CharacterFramePortrait, "RIGHT", 4, 0)

	addon.general.durabilityIconFrame.icon = addon.general.durabilityIconFrame:CreateTexture(nil, "OVERLAY")
	addon.general.durabilityIconFrame.icon:SetSize(32, 32)
	addon.general.durabilityIconFrame.icon:SetPoint("CENTER", addon.general.durabilityIconFrame, "CENTER")
	addon.general.durabilityIconFrame.icon:SetTexture(addon.variables.durabilityIcon)

	addon.general.durabilityIconFrame.count = addon.general.durabilityIconFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	addon.general.durabilityIconFrame.count:SetPoint("BOTTOMRIGHT", addon.general.durabilityIconFrame, "BOTTOMRIGHT", 1, 2)
	addon.general.durabilityIconFrame.count:SetFont(addon.variables.defaultFont, 12, "OUTLINE")

	if addon.db["showDurabilityOnCharframe"] == false or (addon.functions and addon.functions.IsTimerunner and addon.functions.IsTimerunner()) then addon.general.durabilityIconFrame:Hide() end

	-- TODO remove on midnight release
	if not addon.variables.isMidnight then
		addon.general.cloakUpgradeFrame = CreateFrame("Button", nil, PaperDollFrame, "BackdropTemplate")
		addon.general.cloakUpgradeFrame:SetSize(32, 32)
		addon.general.cloakUpgradeFrame:SetPoint("LEFT", addon.general.durabilityIconFrame, "RIGHT", 4, 0)

		addon.general.cloakUpgradeFrame.icon = addon.general.cloakUpgradeFrame:CreateTexture(nil, "OVERLAY")
		addon.general.cloakUpgradeFrame.icon:SetSize(32, 32)
		addon.general.cloakUpgradeFrame.icon:SetPoint("CENTER", addon.general.cloakUpgradeFrame, "CENTER")
		addon.general.cloakUpgradeFrame.icon:SetTexture(addon.variables.cloakUpgradeIcon)

		addon.general.cloakUpgradeFrame:SetScript("OnClick", function()
			GenericTraitUI_LoadUI()
			GenericTraitFrame:SetSystemID(29)
			GenericTraitFrame:SetTreeID(1115)
			ToggleFrame(GenericTraitFrame)
		end)
		addon.general.cloakUpgradeFrame:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(L["cloakUpgradeTooltip"] or "Upgrade skills")
			GameTooltip:Show()
		end)
		addon.general.cloakUpgradeFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

		local function updateCloakUpgradeButton()
			if PaperDollFrame and PaperDollFrame:IsShown() then
				if addon.db["showCloakUpgradeButton"] and C_Item.IsEquippedItem(235499) then
					addon.general.cloakUpgradeFrame:Show()
				else
					addon.general.cloakUpgradeFrame:Hide()
				end
			end
		end
		addon.functions.updateCloakUpgradeButton = updateCloakUpgradeButton
		local cloakEventFrame = CreateFrame("Frame")
		cloakEventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
		cloakEventFrame:SetScript("OnEvent", updateCloakUpgradeButton)
		cloakEventFrame:Hide()
	end

	for key, value in pairs(addon.variables.itemSlots) do
		-- Hintergrund für das Item-Level
		value.ilvlBackground = value:CreateTexture(nil, "BACKGROUND")
		value.ilvlBackground:SetColorTexture(0, 0, 0, 0.8) -- Schwarzer Hintergrund mit 80% Transparenz
		value.ilvlBackground:SetPoint("TOPRIGHT", value, "TOPRIGHT", 1, 1)
		value.ilvlBackground:SetSize(30, 16) -- Größe des Hintergrunds (muss ggf. angepasst werden)

		-- Roter Rahmen mit Farbverlauf
		if addon.variables.shouldEnchanted[key] or addon.variables.shouldEnchantedChecks[key] then
			value.borderGradient = value:CreateTexture(nil, "ARTWORK")
			value.borderGradient:SetPoint("TOPLEFT", value, "TOPLEFT", -2, 2)
			value.borderGradient:SetPoint("BOTTOMRIGHT", value, "BOTTOMRIGHT", 2, -2)
			value.borderGradient:SetColorTexture(1, 0, 0, 0.6) -- Grundfarbe Rot
			value.borderGradient:SetGradient("VERTICAL", CreateColor(1, 0, 0, 1), CreateColor(1, 0.3, 0.3, 0.5))
			value.borderGradient:Hide()
		end
		-- Text für das Item-Level
		value.ilvl = value:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		value.ilvl:SetPoint("TOPRIGHT", value.ilvlBackground, "TOPRIGHT", -1, -2) -- Position des Textes im Zentrum des Hintergrunds
		value.ilvl:SetFont(addon.variables.defaultFont, 14, "OUTLINE") -- Setzt die Schriftart, -größe und -stil (OUTLINE)

		value.enchant = value:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		if addon.variables.itemSlotSide[key] == 0 then
			value.enchant:SetPoint("BOTTOMLEFT", value, "BOTTOMRIGHT", 2, 1)
		elseif addon.variables.itemSlotSide[key] == 2 then
			value.enchant:SetPoint("BOTTOMLEFT", value, "BOTTOMRIGHT", 2, 1)
		else
			value.enchant:SetPoint("BOTTOMRIGHT", value, "BOTTOMLEFT", -2, 1)
		end
		value.enchant:SetFont(addon.variables.defaultFont, 12, "OUTLINE")

		value.gems = {}
		for i = 1, 3 do
			value.gems[i] = CreateFrame("Frame", nil, PaperDollFrame)
			value.gems[i]:SetSize(16, 16) -- Setze die Größe des Icons

			if addon.variables.itemSlotSide[key] == 0 then
				value.gems[i]:SetPoint("TOPLEFT", value, "TOPRIGHT", 5 + (i - 1) * 16, -1) -- Verschiebe jedes Icon um 20px
			elseif addon.variables.itemSlotSide[key] == 1 then
				value.gems[i]:SetPoint("TOPRIGHT", value, "TOPLEFT", -5 - (i - 1) * 16, -1)
			else
				value.gems[i]:SetPoint("BOTTOM", value, "TOPLEFT", -1, 5 + (i - 1) * 16)
			end

			value.gems[i]:SetFrameStrata("HIGH")

			value.gems[i]:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

			value.gems[i].icon = value.gems[i]:CreateTexture(nil, "OVERLAY")
			value.gems[i].icon:SetAllPoints(value.gems[i])
			value.gems[i].icon:SetTexture("Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic") -- Setze die erhaltene Textur

			value.gems[i]:Hide()
		end
	end

	PaperDollFrame:HookScript("OnShow", function(self)
		addon.functions.setCharFrame()
		if not addon.variables.isMidnight then addon.functions.updateCloakUpgradeButton() end --todo remove on midnight release
	end)

	if OrderHallCommandBar then
		OrderHallCommandBar:HookScript("OnShow", function(self)
			if addon.db["hideOrderHallBar"] then
				self:Hide()
			else
				self:Show()
			end
		end)
		if addon.db["hideOrderHallBar"] then OrderHallCommandBar:Hide() end
	end
end

---- END REGION

---- REGION SETTINGS
local cInventory = addon.functions.SettingsCreateCategory(nil, L["ItemsInventory"])
addon.SettingsLayout.inventoryCategory = cInventory
addon.functions.SettingsCreateHeadline(cInventory, BAGSLOT)

local data = {
	{
		var = "showIlvlOnMerchantframe",
		text = L["showIlvlOnMerchantframe"],
		func = function(value) addon.db["showIlvlOnMerchantframe"] = value end,
	},
	{
		var = "showIlvlOnBagItems",
		text = L["showIlvlOnBagItems"],
		func = function(value)
			addon.db["showIlvlOnBagItems"] = value
			for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
				if frame:IsShown() then addon.functions.updateBags(frame) end
			end
			if ContainerFrameCombinedBags:IsShown() then addon.functions.updateBags(ContainerFrameCombinedBags) end
		end,
		children = {
			{
				list = {
					TOPLEFT = L["topLeft"],
					TOPRIGHT = L["topRight"],
					BOTTOMLEFT = L["bottomLeft"],
					BOTTOMRIGHT = L["bottomRight"],
				},
				text = L["bagIlvlPosition"],
				get = function() return addon.db["bagIlvlPosition"] or "TOPLEFT" end,
				set = function(key) addon.db["bagIlvlPosition"] = key end,
				parentCheck = function()
					return addon.SettingsLayout.elements["showIlvlOnBagItems"]
						and addon.SettingsLayout.elements["showIlvlOnBagItems"].setting
						and addon.SettingsLayout.elements["showIlvlOnBagItems"].setting:GetValue() == true
				end,
				parent = true,
				default = "BOTTOMLEFT",
				var = "bagIlvlPosition",
				type = Settings.VarType.String,
				sType = "dropdown",
			},
		},
	},
	{
		var = "showBagFilterMenu",
		text = L["showBagFilterMenu"],
		desc = (L["showBagFilterMenuDesc"]):format(SHIFT_KEY_TEXT),
		func = function(value)
			addon.db["showBagFilterMenu"] = value
			for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
				if frame:IsShown() then addon.functions.updateBags(frame) end
			end
			if ContainerFrameCombinedBags:IsShown() then addon.functions.updateBags(ContainerFrameCombinedBags) end
			if value then
				if BankFrame:IsShown() then
					for slot = 1, C_Container.GetContainerNumSlots(BANK_CONTAINER) do
						local itemButton = _G["BankFrameItem" .. slot]
						if itemButton then addon.functions.updateBank(itemButton, -1, slot) end
					end
				end
			else
				if BankFrame:IsShown() then
					for slot = 1, C_Container.GetContainerNumSlots(BANK_CONTAINER) do
						local itemButton = _G["BankFrameItem" .. slot]
						if itemButton and itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
					end
				end
			end
			if _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end
		end,
	},
	{
		var = "fadeBagQualityIcons",
		text = L["fadeBagQualityIcons"],
		func = function(value)
			addon.db["fadeBagQualityIcons"] = value
			for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
				if frame:IsShown() then addon.functions.updateBags(frame) end
			end
			if ContainerFrameCombinedBags:IsShown() then addon.functions.updateBags(ContainerFrameCombinedBags) end
			if _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end
		end,
	},
	{
		var = "showIlvlOnBankFrame",
		text = L["showIlvlOnBankFrame"],
		func = function(value)
			addon.db["showIlvlOnBankFrame"] = value
			if value then
				if BankFrame:IsShown() then
					for slot = 1, C_Container.GetContainerNumSlots(BANK_CONTAINER) do
						local itemButton = _G["BankFrameItem" .. slot]
						if itemButton then addon.functions.updateBank(itemButton, -1, slot) end
					end
				end
			else
				if BankFrame:IsShown() then
					for slot = 1, C_Container.GetContainerNumSlots(BANK_CONTAINER) do
						local itemButton = _G["BankFrameItem" .. slot]
						if itemButton and itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
					end
				end
			end
			if _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end
		end,
	},
	{
		var = "showBindOnBagItems",
		text = L["showBindOnBagItems"]:format(_G.ITEM_BIND_ON_EQUIP, _G.ITEM_ACCOUNTBOUND_UNTIL_EQUIP, _G.ITEM_BNETACCOUNTBOUND),
		func = function(value)
			addon.db["showBindOnBagItems"] = value
			for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
				if frame:IsShown() then addon.functions.updateBags(frame) end
			end
			if ContainerFrameCombinedBags:IsShown() then addon.functions.updateBags(ContainerFrameCombinedBags) end
		end,
	},
	{
		var = "showUpgradeArrowOnBagItems",
		text = L["showUpgradeArrowOnBagItems"],
		func = function(value)
			addon.db["showUpgradeArrowOnBagItems"] = value
			for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
				if frame:IsShown() then addon.functions.updateBags(frame) end
			end
			if ContainerFrameCombinedBags:IsShown() then addon.functions.updateBags(ContainerFrameCombinedBags) end
			if _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end
		end,
		children = {
			{
				list = {
					TOPLEFT = L["topLeft"],
					TOPRIGHT = L["topRight"],
					BOTTOMLEFT = L["bottomLeft"],
					BOTTOMRIGHT = L["bottomRight"],
				},
				text = L["bagUpgradeIconPosition"],
				get = function() return addon.db["bagUpgradeIconPosition"] or "TOPLEFT" end,
				set = function(key)
					addon.db["bagUpgradeIconPosition"] = key
					for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
						if frame and frame:IsShown() then addon.functions.updateBags(frame) end
					end
					if ContainerFrameCombinedBags:IsShown() then addon.functions.updateBags(ContainerFrameCombinedBags) end
					if _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end
					if MerchantFrame and MerchantFrame:IsShown() then
						if MerchantFrame_UpdateMerchantInfo then MerchantFrame_UpdateMerchantInfo() end
						if MerchantFrame_UpdateBuybackInfo then MerchantFrame_UpdateBuybackInfo() end
					end
					if EquipmentFlyoutFrame and EquipmentFlyoutFrame:IsShown() and EquipmentFlyout_UpdateItems then EquipmentFlyout_UpdateItems() end
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["showUpgradeArrowOnBagItems"]
						and addon.SettingsLayout.elements["showUpgradeArrowOnBagItems"].setting
						and addon.SettingsLayout.elements["showUpgradeArrowOnBagItems"].setting:GetValue() == true
				end,
				parent = true,
				default = "TOPRIGHT",
				var = "bagUpgradeIconPosition",
				type = Settings.VarType.String,
				sType = "dropdown",
			},
		},
	},
	{
		text = L["closeBagsOnAuctionHouse"],
		var = "closeBagsOnAuctionHouse",
		func = function(value) addon.db["closeBagsOnAuctionHouse"] = value end,
	},
	-- moved Money Tracker to Vendors & Economy → Money
}
table.sort(data, function(a, b)
	local textA = a.var
	local textB = b.var
	if a.text then
		textA = a.text
	else
		textA = L[a.var]
	end
	if b.text then
		textB = b.text
	else
		textB = L[b.var]
	end
	return textA < textB
end)

addon.functions.SettingsCreateCheckboxes(cInventory, data)

addon.functions.SettingsCreateHeadline(cInventory, ENABLE_DIALOG)

data = {
	{
		var = "deleteItemFillDialog",
		text = L["deleteItemFillDialog"]:format(DELETE_ITEM_CONFIRM_STRING),
		desc = L["deleteItemFillDialogDesc"],
		func = function(value) addon.db["deleteItemFillDialog"] = value end,
	},
	{
		var = "confirmPatronOrderDialog",
		text = (L["confirmPatronOrderDialog"]):format(PROFESSIONS_CRAFTER_ORDER_TAB_NPC),
		desc = L["confirmPatronOrderDialogDesc"],
		func = function(value) addon.db["confirmPatronOrderDialog"] = value end,
	},
	{
		var = "confirmTimerRemovalTrade",
		text = L["confirmTimerRemovalTrade"],
		desc = L["confirmTimerRemovalTradeDesc"],
		func = function(value) addon.db["confirmTimerRemovalTrade"] = value end,
	},
	{
		var = "confirmReplaceEnchant",
		text = L["confirmReplaceEnchant"],
		desc = L["confirmReplaceEnchantDesc"],
		func = function(value) addon.db["confirmReplaceEnchant"] = value end,
	},
	{
		var = "confirmSocketReplace",
		text = L["confirmSocketReplace"],
		desc = L["confirmSocketReplaceDesc"],
		func = function(value) addon.db["confirmSocketReplace"] = value end,
	},
}

table.sort(data, function(a, b)
	local textA = a.var
	local textB = b.var
	if a.text then
		textA = a.text
	else
		textA = L[a.var]
	end
	if b.text then
		textB = b.text
	else
		textB = L[b.var]
	end
	return textA < textB
end)

local rData1 = addon.functions.SettingsCreateCheckboxes(cInventory, data)

---- REGION END

local eventHandlers = {
	["CURRENCY_DISPLAY_UPDATE"] = function(arg1)
		if arg1 == addon.variables.catalystID and addon.variables.catalystID then
			local cataclystInfo = C_CurrencyInfo.GetCurrencyInfo(addon.variables.catalystID)
			addon.general.iconFrame.count:SetText(cataclystInfo.quantity)
		end
	end,
	["ENCHANT_SPELL_COMPLETED"] = function(arg1, arg2)
		if PaperDollFrame:IsShown() and CharOpt("enchants") and arg1 == true and arg2 and arg2.equipmentSlotIndex then
			C_Timer.After(1, function() setIlvlText(addon.variables.itemSlots[arg2.equipmentSlotIndex], arg2.equipmentSlotIndex) end)
		end
	end,
	["GUILDBANK_UPDATE_MONEY"] = function()
		if addon.db["showDurabilityOnCharframe"] then calculateDurability() end
	end,
	["INSPECT_READY"] = function(arg1)
		if AnyInspectEnabled() then onInspect(arg1) end
	end,
	["PLAYERBANKSLOTS_CHANGED"] = function(arg1)
		if not addon.db["showIlvlOnBankFrame"] then return end
		local itemButton = _G["BankFrameItem" .. arg1]
		if itemButton then addon.functions.updateBank(itemButton, -1, arg1) end
	end,
	["PLAYER_DEAD"] = function()
		if addon.db["showDurabilityOnCharframe"] then calculateDurability() end
	end,
	["PLAYER_EQUIPMENT_CHANGED"] = function(arg1)
		if addon.variables.itemSlots[arg1] and PaperDollFrame:IsShown() then
			if ItemInteractionFrame and ItemInteractionFrame:IsShown() then
				C_Timer.After(0.4, function() setIlvlText(addon.variables.itemSlots[arg1], arg1) end)
			else
				setIlvlText(addon.variables.itemSlots[arg1], arg1)
			end
		end
		if addon.db["showDurabilityOnCharframe"] then calculateDurability() end
	end,
	["PLAYER_MONEY"] = function()
		if addon.db["showDurabilityOnCharframe"] then calculateDurability() end
	end,
	["PLAYER_REGEN_ENABLED"] = function()
		if addon.db["showDurabilityOnCharframe"] then calculateDurability() end
	end,
	["PLAYER_UNGHOST"] = function()
		if addon.db["showDurabilityOnCharframe"] then calculateDurability() end
	end,
	["SOCKET_INFO_UPDATE"] = function()
		if PaperDollFrame:IsShown() and CharOpt("gems") then C_Timer.After(0.5, function() setCharFrame() end) end
	end,
	["ZONE_CHANGED_NEW_AREA"] = function()
		if addon.variables.hookedOrderHall == false then
			local ohcb = OrderHallCommandBar
			if ohcb then
				ohcb:HookScript("OnShow", function(self)
					if addon.db["hideOrderHallBar"] then
						self:Hide()
					else
						self:Show()
					end
				end)
				addon.variables.hookedOrderHall = true
				if addon.db["hideOrderHallBar"] then OrderHallCommandBar:Hide() end
			end
		end
	end,
}

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
