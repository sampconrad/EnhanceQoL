-- luacheck: globals GenericTraitUI_LoadUI GenericTraitFrame

local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local LFGListFrame = _G.LFGListFrame
local GetContainerItemInfo = C_Container.GetContainerItemInfo
local SetSortBagsRightToLeft = C_Container.SetSortBagsRightToLeft
local SetInsertItemsLeftToRight = C_Container.SetInsertItemsLeftToRight
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
local inspectItemLinks = {}
local inspectSlotOrder = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17 }
local inspectSlotFrameNames = {
	[1] = "InspectHeadSlot",
	[2] = "InspectNeckSlot",
	[3] = "InspectShoulderSlot",
	[15] = "InspectBackSlot",
	[5] = "InspectChestSlot",
	[9] = "InspectWristSlot",
	[10] = "InspectHandsSlot",
	[6] = "InspectWaistSlot",
	[7] = "InspectLegsSlot",
	[8] = "InspectFeetSlot",
	[11] = "InspectFinger0Slot",
	[12] = "InspectFinger1Slot",
	[13] = "InspectTrinket0Slot",
	[14] = "InspectTrinket1Slot",
	[16] = "InspectMainHandSlot",
	[17] = "InspectSecondaryHandSlot",
}
addon.enchantTextCache = addon.enchantTextCache or {}
local MAX_ENCHANT_LINK_CACHE = 2048
local enchantTextLinkCache = {}
local enchantTextLinkCacheCount = 0
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

local charIlvlAnchors = {
	TOPLEFT = { bgPoint = "TOPLEFT", bgX = -1, bgY = 1, textPoint = "TOPLEFT", textX = 1, textY = -2 },
	TOP = { bgPoint = "TOP", bgX = 0, bgY = 1, textPoint = "TOP", textX = 0, textY = -2 },
	TOPRIGHT = { bgPoint = "TOPRIGHT", bgX = 1, bgY = 1, textPoint = "TOPRIGHT", textX = -1, textY = -2 },
	LEFT = { bgPoint = "LEFT", bgX = -1, bgY = 0, textPoint = "LEFT", textX = 1, textY = 0 },
	CENTER = { bgPoint = "CENTER", bgX = 0, bgY = 0, textPoint = "CENTER", textX = 0, textY = 0 },
	RIGHT = { bgPoint = "RIGHT", bgX = 1, bgY = 0, textPoint = "RIGHT", textX = -1, textY = 0 },
	BOTTOMLEFT = { bgPoint = "BOTTOMLEFT", bgX = -1, bgY = -1, textPoint = "BOTTOMLEFT", textX = 1, textY = 1 },
	BOTTOM = { bgPoint = "BOTTOM", bgX = 0, bgY = -1, textPoint = "BOTTOM", textX = 0, textY = 1 },
	BOTTOMRIGHT = { bgPoint = "BOTTOMRIGHT", bgX = 1, bgY = -1, textPoint = "BOTTOMRIGHT", textX = -1, textY = 1 },
}

local function applyCharIlvlPosition(element)
	if not element or not element.ilvlBackground or not element.ilvl then return end
	local pos = addon.db["charIlvlPosition"] or "TOPRIGHT"
	local anchor = charIlvlAnchors[pos] or charIlvlAnchors.TOPRIGHT
	element.ilvlBackground:ClearAllPoints()
	element.ilvl:ClearAllPoints()
	element.ilvlBackground:SetPoint(anchor.bgPoint, element, anchor.bgPoint, anchor.bgX, anchor.bgY)
	element.ilvl:SetPoint(anchor.textPoint, element.ilvlBackground, anchor.textPoint, anchor.textX, anchor.textY)
end

local function getMissingEnchantOverlayColor()
	local c = addon.db and addon.db["missingEnchantOverlayColor"]
	local r = (c and c.r) or 1
	local g = (c and c.g) or 0
	local b = (c and c.b) or 0
	local a = (c and c.a)
	if a == nil then a = 0.6 end
	return r, g, b, a
end

local function applyMissingEnchantOverlayStyle(texture)
	if not texture then return end
	local r, g, b, a = getMissingEnchantOverlayColor()
	texture:SetColorTexture(r, g, b, a)
	local topAlpha = math.min(1, a + 0.35)
	local bottomAlpha = math.max(0, a - 0.15)
	if texture.SetGradientAlpha then texture:SetGradientAlpha("VERTICAL", r, g, b, topAlpha, r, g, b, bottomAlpha) end
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
					GameTooltip:SetOwner(self, anchor, xOffset, yOffset)
					GameTooltip:SetHyperlink(gemLink)
					GameTooltip:Show()
				end
			end)
		else
			-- Wiederhole die Überprüfung nach einer Verzögerung, wenn der Edelstein noch nicht geladen ist
			C_Timer.After(0.1, function() CheckItemGems(element, itemLink, emptySocketsCount, key, pdElement, attempts + 1) end)
			return -- Abbrechen, damit wir auf die nächste Überprüfung warten
		end
	end
end

local function setEnchantTextLinkCache(link, value)
	if enchantTextLinkCache[link] == nil then
		enchantTextLinkCacheCount = enchantTextLinkCacheCount + 1
		if enchantTextLinkCacheCount > MAX_ENCHANT_LINK_CACHE then
			enchantTextLinkCache = {}
			enchantTextLinkCacheCount = 1
		end
	end
	enchantTextLinkCache[link] = value
end

local function getTooltipInfoFromLink(link)
	if not link then return nil end

	local cached = enchantTextLinkCache[link]
	if cached ~= nil then
		if cached == false then return nil end
		return cached
	end

	local enchantID = tonumber(link:match("item:%d+:(%d+)") or 0)
	local enchantText = nil

	if enchantID and enchantID > 0 then
		enchantText = addon.enchantTextCache[enchantID]
		if enchantText == false then enchantText = nil end
	end

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
	end

	setEnchantTextLinkCache(link, enchantText or false)
	return enchantText
end

local function removeInspectElements()
	if nil == InspectPaperDollFrame then return end
	if InspectPaperDollFrame.ilvl then InspectPaperDollFrame.ilvl:SetText("") end
	for _, key in ipairs(inspectSlotOrder) do
		local frameName = inspectSlotFrameNames[key]
		local element = frameName and _G[frameName]
		if element then
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
	end
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
			inspectItemLinks = {}
			removeInspectElements()
		end)
	end
	if inspectUnit ~= InspectFrame.unit then
		inspectUnit = InspectFrame.unit
		inspectDone = {}
		inspectItemLinks = {}
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

		if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
			local ilvl = C_PaperDollInfo.GetInspectItemLevel(unit)
			if ilvl then pdElement.ilvl:SetFormattedText(string.format("%.1f", ilvl)) end
		else
			pdElement.ilvl:SetFormattedText("")
		end
		pdElement.ilvl:SetTextColor(1, 1, 1, 1)

		local textWidth = pdElement.ilvl:GetStringWidth()
		pdElement.ilvlBackground:SetSize(textWidth + 6, pdElement.ilvl:GetStringHeight() + 4) -- Mehr Padding für bessere Lesbarkeit
	end
	for _, key in ipairs(inspectSlotOrder) do
		local frameName = inspectSlotFrameNames[key]
		local element = frameName and _G[frameName]
		if element then
			if element.borderGradient then applyMissingEnchantOverlayStyle(element.borderGradient) end
			local itemLink = GetInventoryItemLink(unit, key)
			if inspectItemLinks[key] ~= itemLink then
				inspectItemLinks[key] = itemLink
				inspectDone[key] = nil
			end
			if inspectDone[key] ~= true and inspectDone[key] ~= "pending" then
				if element.ilvl then element.ilvl:SetFormattedText("") end
				if element.ilvlBackground then element.ilvlBackground:Hide() end
				if element.enchant then element.enchant:SetText("") end
				if itemLink then
					local eItem = Item:CreateFromItemLink(itemLink)
					if eItem and not eItem:IsItemEmpty() then
						inspectDone[key] = "pending"
						eItem:ContinueOnItemLoad(function()
							-- Link changed while item was loading; skip stale callback work.
							if inspectItemLinks[key] ~= itemLink then
								if inspectDone[key] == "pending" then inspectDone[key] = nil end
								return
							end
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
								if not element.ilvlBackground then
									element.ilvlBackground = element:CreateTexture(nil, "BACKGROUND")
									element.ilvlBackground:SetColorTexture(0, 0, 0, 0.8) -- Schwarzer Hintergrund mit 80% Transparenz
									element.ilvl = element:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
									element.ilvl:SetFont(addon.variables.defaultFont, 14, "OUTLINE") -- Setzt die Schriftart, -größe und -stil (OUTLINE)
								end

								applyCharIlvlPosition(element)
								element.ilvlBackground:SetSize(30, 16) -- Größe des Hintergrunds (muss ggf. angepasst werden)

								local color = eItem:GetItemQualityColor()

								local itemLevelText

								local ttData = C_TooltipInfo.GetInventoryItem(unit, key, true)
								if ttData and ttData.lines then
									for i, v in pairs(ttData.lines) do
										if v.type == 41 then itemLevelText = v.itemLevel end
									end
								end
								if not itemLevelText then itemLevelText = eItem:GetCurrentItemLevel() end

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
										applyMissingEnchantOverlayStyle(element.borderGradient)
										element.borderGradient:Hide()
									end
									element.enchant:SetFont(addon.variables.defaultFont, 12, "OUTLINE")
								end
								if element.borderGradient then
									applyMissingEnchantOverlayStyle(element.borderGradient)
									element.borderGradient:Hide()
									local showMissingOverlay = addon.db["showMissingEnchantOverlayOnCharframe"] ~= false
									local enchantText = getTooltipInfoFromLink(itemLink)
									local foundEnchant = enchantText ~= nil
									if foundEnchant then
										element.enchant:SetFormattedText(enchantText)
										if element.borderGradient then element.borderGradient:Hide() end
									end

									if not foundEnchant and UnitLevel(inspectUnit) == addon.variables.maxLevel then
										element.enchant:SetText("")
										if
											nil == addon.variables.shouldEnchantedChecks[key]
											or (nil ~= addon.variables.shouldEnchantedChecks[key] and addon.variables.shouldEnchantedChecks[key].func(eItem:GetCurrentItemLevel()))
										then
											if key == 17 then
												local _, _, _, _, _, _, _, _, itemEquipLoc = C_Item.GetItemInfoInstant(itemLink)
												if addon.variables.allowedEnchantTypesForOffhand[itemEquipLoc] then
													if showMissingOverlay then
														element.borderGradient:Show()
													else
														element.borderGradient:Hide()
													end
													element.enchant:SetFormattedText(("|cff%02x%02x%02x"):format(255, 0, 0) .. L["MissingEnchant"] .. "|r")
												end
											else
												if showMissingOverlay then
													element.borderGradient:Show()
												else
													element.borderGradient:Hide()
												end
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
					else
						inspectDone[key] = true
					end
				else
					inspectDone[key] = true
				end
			end
		end
	end

	if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
		local ilvl = C_PaperDollInfo.GetInspectItemLevel(unit)
		if ilvl then pdElement.ilvl:SetFormattedText(string.format("%.1f", ilvl)) end
	else
		pdElement.ilvl:SetFormattedText("")
	end
end

addon.functions.onInspect = onInspect

local function ensureRarityGlow(element)
	if not element then return nil end
	if element.rarityGlow then return element.rarityGlow end
	local glow = element:CreateTexture(nil, "BORDER")
	glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	glow:SetBlendMode("ADD")
	glow:SetAlpha(0.9)
	glow:SetPoint("CENTER", element, "CENTER", 0, 0)
	element.rarityGlow = glow
	return glow
end

local function updateCharRarityGlow(element, itemQuality)
	if not element then return end
	if not addon.db["enhancedRarityGlow"] then
		if element.rarityGlow then element.rarityGlow:Hide() end
		return
	end
	if not itemQuality or itemQuality < 2 then
		if element.rarityGlow then element.rarityGlow:Hide() end
		return
	end
	local glow = ensureRarityGlow(element)
	if not glow then return end
	local w, h = element:GetSize()
	if w and h and w > 0 and h > 0 then
		glow:SetSize(w + 26, h + 26)
	else
		glow:SetSize(64, 64)
	end
	local r, g, b = C_Item.GetItemQualityColor(itemQuality)
	glow:SetVertexColor(r, g, b)
	glow:Show()
end

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
			if not addon.db["enhancedRarityGlow"] then return end
		end

		local eItem = Item:CreateFromEquipmentSlot(slot)
		if eItem and not eItem:IsItemEmpty() then
			eItem:ContinueOnItemLoad(function()
				local link = eItem:GetItemLink()
				local itemQuality = link and select(3, GetItemInfo(link)) or nil
				updateCharRarityGlow(element, itemQuality)
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

					applyCharIlvlPosition(element)

					element.ilvl:SetFormattedText(itemLevelText)
					element.ilvl:SetTextColor(color.r, color.g, color.b, 1)

					local textWidth = element.ilvl:GetStringWidth()
					element.ilvlBackground:SetSize(textWidth + 6, element.ilvl:GetStringHeight() + 4) -- Mehr Padding für bessere Lesbarkeit
				else
					element.ilvl:SetFormattedText("")
					element.ilvlBackground:Hide()
				end

				if CharOpt("enchants") and element.borderGradient then
					applyMissingEnchantOverlayStyle(element.borderGradient)
					element.borderGradient:Hide()
					local showMissingOverlay = addon.db["showMissingEnchantOverlayOnCharframe"] ~= false
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
									if showMissingOverlay then element.borderGradient:Show() end
									element.enchant:SetFormattedText(("|cff%02x%02x%02x"):format(255, 0, 0) .. L["MissingEnchant"] .. "|r")
								end
							else
								if showMissingOverlay then element.borderGradient:Show() end
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
			updateCharRarityGlow(element, nil)
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
	local statFrame = CharacterStatsPane and CharacterStatsPane.ItemLevelFrame
	if not (statFrame and statFrame.Value and GetAverageItemLevel) then return end

	if not CharOpt("ilvl") then return end

	local avgItemLevel, equippedItemLevel = GetAverageItemLevel()
	if not avgItemLevel or not equippedItemLevel then return end

	local equippedText = string.format("%.2f", equippedItemLevel)
	local avgText = string.format("%.2f", avgItemLevel)
	if avgText ~= equippedText then
		statFrame.Value:SetText(equippedText .. "/" .. avgText)
	else
		statFrame.Value:SetText(equippedText)
	end

	if GetItemLevelColor then
		local r, g, b = GetItemLevelColor()
		if r and g and b then statFrame.Value:SetTextColor(r, g, b) end
	end
end
hooksecurefunc("PaperDollFrame_SetItemLevel", function(statFrame, unit) UpdateItemLevel() end)

local function setCharFrame()
	if InCombatLockdown and InCombatLockdown() then
		addon.variables = addon.variables or {}
		addon.variables.pendingCharFrameUpdate = true
		return
	end
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
		if button.ItemUpgradeIconGlow then button.ItemUpgradeIconGlow:Hide() end
		local location = button.location
		if not location then return end

		-- TODO 12.0: EquipmentManager_UnpackLocation will change once Void Storage is removed
		local itemLink, _, _, bags, _, slot, bag, itemLevel
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
					if bags then
						local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
						if loc then itemLevel = C_Item.GetCurrentItemLevel(loc) end
					elseif slot then
						local loc = ItemLocation:CreateFromEquipmentSlot(slot)
						if loc then itemLevel = C_Item.GetCurrentItemLevel(loc) end
					end
					if not itemLevel then itemLevel = eItem:GetCurrentItemLevel() end
					local quality = eItem:GetItemQualityColor()

					if not button.ItemLevelText then
						button.ItemLevelText = button:CreateFontString(nil, "OVERLAY")
						button.ItemLevelText:SetFont(addon.variables.defaultFont, 16, "OUTLINE")
					end
					addon.functions.ApplyBagItemLevelPosition(button.ItemLevelText, button, addon.db["bagIlvlPosition"])

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
							addon.functions.EnsureBagUpgradeIcon(button)
							local posUp = addon.db["bagUpgradeIconPosition"] or "BOTTOMRIGHT"
							addon.functions.ApplyBagUpgradeIconPosition(button.ItemUpgradeIcon, button, posUp)
							addon.functions.AlignUpgradeIconGlow(button.ItemUpgradeIconGlow, button.ItemUpgradeIcon)
							button.ItemUpgradeIconGlow:Show()
							button.ItemUpgradeIcon:Show()
						elseif button.ItemUpgradeIcon then
							button.ItemUpgradeIcon:Hide()
							if button.ItemUpgradeIconGlow then button.ItemUpgradeIconGlow:Hide() end
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
						addon.functions.ApplyBagBoundPosition(button.ItemBoundType, button, addon.db["bagIlvlPosition"])
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
			if button.ItemUpgradeIconGlow then button.ItemUpgradeIconGlow:Hide() end
			button.ItemLevelText:Hide()
		end
	elseif button.ItemLevelText then
		if button.ItemBoundType then button.ItemBoundType:Hide() end
		if button.ItemUpgradeArrow then button.ItemUpgradeArrow:Hide() end
		if button.ItemUpgradeIcon then button.ItemUpgradeIcon:Hide() end
		if button.ItemUpgradeIconGlow then button.ItemUpgradeIconGlow:Hide() end
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
				if itemButton.ItemUpgradeIconGlow then itemButton.ItemUpgradeIconGlow:Hide() end
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
				if itemButton.ItemUpgradeIconGlow then itemButton.ItemUpgradeIconGlow:Hide() end
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
				if itemButton.ItemUpgradeIconGlow then itemButton.ItemUpgradeIconGlow:Hide() end
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
							addon.functions.ApplyBagItemLevelPosition(itemButton.ItemLevelText, itemButton, addon.db["bagIlvlPosition"])

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
									addon.functions.EnsureBagUpgradeIcon(itemButton)
									local posUp = addon.db["bagUpgradeIconPosition"] or "BOTTOMRIGHT"
									addon.functions.ApplyBagUpgradeIconPosition(itemButton.ItemUpgradeIcon, itemButton, posUp)
									addon.functions.AlignUpgradeIconGlow(itemButton.ItemUpgradeIconGlow, itemButton.ItemUpgradeIcon)
									itemButton.ItemUpgradeIconGlow:Show()
									itemButton.ItemUpgradeIcon:Show()
								elseif itemButton.ItemUpgradeIcon then
									itemButton.ItemUpgradeIcon:Hide()
									if itemButton.ItemUpgradeIconGlow then itemButton.ItemUpgradeIconGlow:Hide() end
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
								addon.functions.ApplyBagBoundPosition(itemButton.ItemBoundType, itemButton, addon.db["bagIlvlPosition"])
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
						addon.functions.ApplyBagItemLevelPosition(itemButton.ItemLevelText, itemButton, addon.db["bagIlvlPosition"])

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
							addon.functions.ApplyBagBoundPosition(itemButton.ItemBoundType, itemButton, addon.db["bagIlvlPosition"])
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

local function applyBagSortOrder()
	if not SetSortBagsRightToLeft or not addon.db then return end
	if addon.db["bagSortOrderEnabled"] then
		local direction = addon.db["bagSortOrderDirection"] or "DEFAULT"
		SetSortBagsRightToLeft(direction == "REVERSE")
	end
end

local function applyLootOrder()
	if not SetInsertItemsLeftToRight or not addon.db then return end
	if addon.db["bagLootOrderEnabled"] then
		local direction = addon.db["bagLootOrderDirection"] or "DEFAULT"
		SetInsertItemsLeftToRight(direction == "REVERSE")
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
	addon.functions.InitDBValue("enhancedRarityGlow", false)
	addon.functions.InitDBValue("showGemsOnCharframe", false)
	addon.functions.InitDBValue("showGemsTooltipOnCharframe", false)
	addon.functions.InitDBValue("showEnchantOnCharframe", false)
	addon.functions.InitDBValue("showMissingEnchantOverlayOnCharframe", true)
	addon.functions.InitDBValue("missingEnchantOverlayColor", { r = 1, g = 0, b = 0, a = 0.6 })
	addon.functions.InitDBValue("showCatalystChargesOnCharframe", false)
	addon.functions.InitDBValue("movementSpeedStatEnabled", false)
	addon.functions.InitDBValue("characterStatsFormattingEnabled", false)
	addon.functions.InitDBValue("bagFilterFrameData", {})
	addon.functions.InitDBValue("closeBagsOnAuctionHouse", false)
	addon.functions.InitDBValue("showDurabilityOnCharframe", false)
	addon.functions.InitDBValue("bagSortOrderEnabled", false)
	addon.functions.InitDBValue("bagSortOrderDirection", "DEFAULT")
	addon.functions.InitDBValue("bagLootOrderEnabled", false)
	addon.functions.InitDBValue("bagLootOrderDirection", "DEFAULT")

	applyBagSortOrder()
	applyLootOrder()

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
	if addon.CharacterStatsFormatting and addon.CharacterStatsFormatting.Refresh then addon.CharacterStatsFormatting.Refresh() end
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
			applyMissingEnchantOverlayStyle(value.borderGradient)
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
end

---- END REGION

---- REGION SETTINGS

local cInventory = addon.SettingsLayout.rootGENERAL

local expandable = addon.functions.SettingsCreateExpandableSection(cInventory, {
	name = L["ItemsInventory"],
	expanded = false,
	colorizeTitle = false,
})

addon.functions.SettingsCreateHeadline(cInventory, BAGSLOT, { parentSection = expandable })

local function refreshBagFrames(includeBankPanel)
	for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
		if frame:IsShown() then addon.functions.updateBags(frame) end
	end
	if ContainerFrameCombinedBags:IsShown() then addon.functions.updateBags(ContainerFrameCombinedBags) end
	if includeBankPanel and _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end
end

local function refreshBankSlots(showIlvl)
	if not BankFrame or not BankFrame:IsShown() then return end
	for slot = 1, C_Container.GetContainerNumSlots(BANK_CONTAINER) do
		local itemButton = _G["BankFrameItem" .. slot]
		if itemButton then
			if showIlvl then
				addon.functions.updateBank(itemButton, -1, slot)
			elseif itemButton.ItemLevelText then
				itemButton.ItemLevelText:Hide()
			end
		end
	end
end

local function refreshMerchantButtons()
	if MerchantFrame and MerchantFrame:IsShown() then
		updateMerchantButtonInfo()
		updateBuybackButtonInfo()
	end
end

local function isBagDisplaySelected(key)
	if key == "ilvl" then return addon.db["showIlvlOnBagItems"] == true end
	if key == "upgrade" then return addon.db["showUpgradeArrowOnBagItems"] == true end
	if key == "bind" then return addon.db["showBindOnBagItems"] == true end
	return false
end

local function setBagDisplayOption(key, value)
	local enabled = value and true or false
	if key == "ilvl" then
		addon.db["showIlvlOnBagItems"] = enabled
		refreshBagFrames(false)
	elseif key == "upgrade" then
		addon.db["showUpgradeArrowOnBagItems"] = enabled
		refreshBagFrames(true)
	elseif key == "bind" then
		addon.db["showBindOnBagItems"] = enabled
		refreshBagFrames(false)
	end
end

local function applyBagDisplaySelection(selection)
	selection = selection or {}
	addon.db["showIlvlOnBagItems"] = selection.ilvl == true
	addon.db["showUpgradeArrowOnBagItems"] = selection.upgrade == true
	addon.db["showBindOnBagItems"] = selection.bind == true
	refreshBagFrames(true)
end

local bindDesc = L["showBindOnBagItemsDesc"]
if bindDesc then bindDesc = bindDesc:format(_G.ITEM_BIND_ON_EQUIP, _G.ITEM_ACCOUNTBOUND_UNTIL_EQUIP, _G.ITEM_BNETACCOUNTBOUND) end

local bagDisplayDropdown = addon.functions.SettingsCreateMultiDropdown(cInventory, {
	var = "bagDisplayOptions",
	text = L["bagDisplayElements"] or "Bag indicators",
	options = {
		{ value = "ilvl", text = L["showIlvlOnBagItems"], tooltip = L["showIlvlOnBagItemsDesc"] },
		{ value = "upgrade", text = L["showUpgradeArrowOnBagItems"], tooltip = L["showUpgradeArrowOnBagItemsDesc"] },
		{ value = "bind", text = L["showBindOnBagItems"], tooltip = bindDesc },
	},
	isSelectedFunc = function(key) return isBagDisplaySelected(key) end,
	setSelectedFunc = function(key, selected) setBagDisplayOption(key, selected) end,
	setSelection = applyBagDisplaySelection,
	parentSection = expandable,
})

addon.functions.SettingsCreateDropdown(cInventory, {
	list = {
		TOPLEFT = L["topLeft"],
		TOP = L["top"],
		TOPRIGHT = L["topRight"],
		LEFT = L["left"],
		CENTER = L["center"],
		RIGHT = L["right"],
		BOTTOMLEFT = L["bottomLeft"],
		BOTTOM = L["bottom"],
		BOTTOMRIGHT = L["bottomRight"],
	},
	text = L["bagIlvlPosition"],
	get = function() return addon.db["bagIlvlPosition"] or "TOPLEFT" end,
	set = function(key) addon.db["bagIlvlPosition"] = key end,
	parent = bagDisplayDropdown,
	parentCheck = function() return isBagDisplaySelected("ilvl") end,
	default = "BOTTOMLEFT",
	var = "bagIlvlPosition",
	type = Settings.VarType.String,
	parentSection = expandable,
})

addon.functions.SettingsCreateDropdown(cInventory, {
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
	parent = bagDisplayDropdown,
	parentCheck = function() return isBagDisplaySelected("upgrade") end,
	default = "TOPRIGHT",
	var = "bagUpgradeIconPosition",
	type = Settings.VarType.String,
	parentSection = expandable,
})

local function isBagItemLevelTargetSelected(key)
	if key == "bank" then return addon.db["showIlvlOnBankFrame"] == true end
	if key == "merchant" then return addon.db["showIlvlOnMerchantframe"] == true end
	return false
end

local function setBagItemLevelTarget(key, value)
	local enabled = value and true or false
	if key == "bank" then
		addon.db["showIlvlOnBankFrame"] = enabled
		refreshBankSlots(enabled)
		if _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end
	elseif key == "merchant" then
		addon.db["showIlvlOnMerchantframe"] = enabled
		refreshMerchantButtons()
	end
end

local function applyBagItemLevelTargets(selection)
	selection = selection or {}
	addon.db["showIlvlOnBankFrame"] = selection.bank == true
	addon.db["showIlvlOnMerchantframe"] = selection.merchant == true
	refreshBankSlots(addon.db["showIlvlOnBankFrame"])
	if _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end
	refreshMerchantButtons()
end

addon.functions.SettingsCreateMultiDropdown(cInventory, {
	var = "bagItemLevelTargets",
	text = L["bagItemLevelTargets"] or "Item level targets",
	options = {
		{ value = "bank", text = L["showIlvlOnBankFrame"], tooltip = L["showIlvlOnBankFrameDesc"] },
		{ value = "merchant", text = L["showIlvlOnMerchantframe"], tooltip = L["showIlvlOnMerchantframeDesc"] },
	},
	isSelectedFunc = function(key) return isBagItemLevelTargetSelected(key) end,
	setSelectedFunc = function(key, selected) setBagItemLevelTarget(key, selected) end,
	setSelection = applyBagItemLevelTargets,
	parentSection = expandable,
})

addon.functions.SettingsCreateCheckbox(cInventory, {
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
	parentSection = expandable,
})

addon.functions.SettingsCreateCheckbox(cInventory, {
	var = "fadeBagQualityIcons",
	text = L["fadeBagQualityIcons"],
	desc = L["fadeBagQualityIconsDesc"],
	func = function(value)
		addon.db["fadeBagQualityIcons"] = value
		for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
			if frame:IsShown() then addon.functions.updateBags(frame) end
		end
		if ContainerFrameCombinedBags:IsShown() then addon.functions.updateBags(ContainerFrameCombinedBags) end
		if _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end
	end,
	parentSection = expandable,
})

addon.functions.SettingsCreateCheckbox(cInventory, {
	var = "enhancedRarityGlow",
	text = L["enhancedRarityGlow"] or "Greater rarity glow",
	desc = L["enhancedRarityGlowDesc"] or "Adds a stronger item-quality border to bags and the character panel.",
	func = function(value)
		addon.db["enhancedRarityGlow"] = value
		refreshBagFrames(true)
		if addon.functions and addon.functions.setCharFrame then addon.functions.setCharFrame() end
	end,
	parentSection = expandable,
})

addon.functions.SettingsCreateHeadline(cInventory, L["bagOrderHeader"] or "Bag sort & loot order", { parentSection = expandable })
addon.functions.SettingsCreateText(cInventory, L["bagOrderHint"] or "These options only change which bag position sorting/looting starts in. Bags still fill top-left to bottom-right.", {
	parentSection = expandable,
})

addon.functions.SettingsCreateCheckbox(cInventory, {
	var = "bagSortOrderEnabled",
	text = L["bagSortOrderEnabled"] or "Change sort order",
	desc = L["bagSortOrderEnabledDesc"] or "Overrides the clean-up bags start position when enabled.",
	func = function(value)
		addon.db["bagSortOrderEnabled"] = value
		if value then applyBagSortOrder() end
	end,
	parentSection = expandable,
})

local sortOrderParent = addon.SettingsLayout.elements["bagSortOrderEnabled"] and addon.SettingsLayout.elements["bagSortOrderEnabled"].element
addon.functions.SettingsCreateDropdown(cInventory, {
	list = {
		DEFAULT = L["bagSortOrderDefault"] or "Default (Left-to-Right)",
		REVERSE = L["bagSortOrderReverse"] or "Reverse (Right-to-Left)",
	},
	text = L["bagSortOrderDirection"] or "Sort order direction",
	get = function() return addon.db["bagSortOrderDirection"] or "DEFAULT" end,
	set = function(key)
		addon.db["bagSortOrderDirection"] = key
		if addon.db["bagSortOrderEnabled"] then applyBagSortOrder() end
	end,
	parent = sortOrderParent,
	parentCheck = function() return addon.db["bagSortOrderEnabled"] == true end,
	default = "DEFAULT",
	var = "bagSortOrderDirection",
	type = Settings.VarType.String,
	parentSection = expandable,
})

addon.functions.SettingsCreateCheckbox(cInventory, {
	var = "bagLootOrderEnabled",
	text = L["bagLootOrderEnabled"] or "Change loot order",
	desc = L["bagLootOrderEnabledDesc"] or "Overrides the loot start position when enabled.",
	func = function(value)
		addon.db["bagLootOrderEnabled"] = value
		if value then applyLootOrder() end
	end,
	parentSection = expandable,
})

local lootOrderParent = addon.SettingsLayout.elements["bagLootOrderEnabled"] and addon.SettingsLayout.elements["bagLootOrderEnabled"].element
addon.functions.SettingsCreateDropdown(cInventory, {
	list = {
		DEFAULT = L["bagLootOrderDefault"] or "Default (Right-to-Left)",
		REVERSE = L["bagLootOrderReverse"] or "Reverse (Left-to-Right)",
	},
	text = L["bagLootOrderDirection"] or "Loot order direction",
	get = function() return addon.db["bagLootOrderDirection"] or "DEFAULT" end,
	set = function(key)
		addon.db["bagLootOrderDirection"] = key
		if addon.db["bagLootOrderEnabled"] then applyLootOrder() end
	end,
	parent = lootOrderParent,
	parentCheck = function() return addon.db["bagLootOrderEnabled"] == true end,
	default = "DEFAULT",
	var = "bagLootOrderDirection",
	type = Settings.VarType.String,
	parentSection = expandable,
})
-- moved Money Tracker to Vendors & Economy → Money

---- REGION END

local function ensureCharFrameOnShowHook()
	if addon.variables and addon.variables.eqolCharFrameHooked then return end
	if not _G.PaperDollFrame then return end
	addon.variables = addon.variables or {}
	addon.variables.eqolCharFrameHooked = true
	_G.PaperDollFrame:HookScript("OnShow", function()
		if InCombatLockdown and InCombatLockdown() then
			addon.variables.pendingCharFrameUpdate = true
			return
		end
		setCharFrame()
	end)
end

local eventHandlers = {
	["ADDON_LOADED"] = function(arg1)
		if arg1 ~= "Blizzard_UIPanels_Game" then return end
		ensureCharFrameOnShowHook()
		if InCombatLockdown and InCombatLockdown() then
			addon.variables.pendingCharFrameUpdate = true
			return
		end
		setCharFrame()
	end,
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
		if addon.variables and addon.variables.pendingCharFrameUpdate and _G.PaperDollFrame and _G.PaperDollFrame:IsShown() then
			addon.variables.pendingCharFrameUpdate = nil
			setCharFrame()
		end
	end,
	["PLAYER_UNGHOST"] = function()
		if addon.db["showDurabilityOnCharframe"] then calculateDurability() end
	end,
	["SOCKET_INFO_UPDATE"] = function()
		if PaperDollFrame:IsShown() and CharOpt("gems") then C_Timer.After(0.5, function() setCharFrame() end) end
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

-- If Blizzard_UIPanels_Game is already loaded, wire up immediately.
if _G.PaperDollFrame then ensureCharFrameOnShowHook() end
