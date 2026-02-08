-- luacheck: globals EnhanceQoL INVSLOT_HEAD INVSLOT_SHOULDER INVSLOT_CHEST INVSLOT_WAIST INVSLOT_LEGS INVSLOT_FEET INVSLOT_WRIST INVSLOT_HAND INVSLOT_BACK INVSLOT_MAINHAND INVSLOT_OFFHAND HEADSLOT SHOULDERSLOT CHESTSLOT WAISTSLOT LEGSLOT FEETSLOT WRISTSLOT HANDSSLOT BACKSLOT MAINHANDSLOT SECONDARYHANDSLOT NORMAL_FONT_COLOR
local addonName, addon = ...

local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream
local function getOptionsHint()
	if addon.DataPanel and addon.DataPanel.GetOptionsHintText then
		local text = addon.DataPanel.GetOptionsHintText()
		if text ~= nil then return text end
		return nil
	end
	return L["Right-Click for options"]
end

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.durability = addon.db.datapanel.durability or {}
	db = addon.db.datapanel.durability
	db.fontSize = db.fontSize or 13
	if db.showIcon == nil then db.showIcon = true end
	if db.showCritical == nil then db.showCritical = true end
	if db.useTextColor == nil then db.useTextColor = false end
	db.highColor = db.highColor or { r = 0, g = 1, b = 0 }
	db.midColor = db.midColor or { r = 1, g = 1, b = 0 }
	db.lowColor = db.lowColor or { r = 1, g = 0, b = 0 }
	if not db.textColor then
		local r, g, b = 1, 0.82, 0
		if NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.GetRGB then
			r, g, b = NORMAL_FONT_COLOR:GetRGB()
		end
		db.textColor = { r = r, g = g, b = b }
	end
end

local function RestorePosition(frame)
	if db.point and db.x and db.y then
		frame:ClearAllPoints()
		frame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
	end
end

local aceWindow
local function createAceWindow()
	if aceWindow then
		aceWindow:Show()
		return
	end
	ensureDB()
	local frame = AceGUI:Create("Window")
	aceWindow = frame.frame
	frame:SetTitle((addon.DataPanel and addon.DataPanel.GetStreamOptionsTitle and addon.DataPanel.GetStreamOptionsTitle(stream and stream.meta and stream.meta.title)) or GAMEMENU_OPTIONS)
	frame:SetWidth(300)
	frame:SetHeight(400)
	frame:SetLayout("List")

	frame.frame:SetScript("OnShow", function(self) RestorePosition(self) end)
	frame.frame:SetScript("OnHide", function(self)
		local point, _, _, xOfs, yOfs = self:GetPoint()
		db.point = point
		db.x = xOfs
		db.y = yOfs
	end)

	local fontSize = AceGUI:Create("Slider")
	fontSize:SetLabel(FONT_SIZE)
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(fontSize)

	local showIcon = AceGUI:Create("CheckBox")
	showIcon:SetLabel(L["durabilityShowIcon"] or "Show icon")
	showIcon:SetValue(db.showIcon)
	showIcon:SetCallback("OnValueChanged", function(_, _, val)
		db.showIcon = val and true or false
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(showIcon)

	local showCritical = AceGUI:Create("CheckBox")
	showCritical:SetLabel(L["durabilityShowCritical"] or "Show critical warning")
	showCritical:SetValue(db.showCritical)
	showCritical:SetCallback("OnValueChanged", function(_, _, val)
		db.showCritical = val and true or false
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(showCritical)

	local useColor = AceGUI:Create("CheckBox")
	useColor:SetLabel(L["durabilityUseTextColor"] or "Use custom text color")
	useColor:SetValue(db.useTextColor)
	useColor:SetCallback("OnValueChanged", function(_, _, val)
		db.useTextColor = val and true or false
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(useColor)

	local textColor = AceGUI:Create("ColorPicker")
	textColor:SetLabel(L["Text color"] or "Text color")
	textColor:SetColor(db.textColor.r, db.textColor.g, db.textColor.b)
	textColor:SetCallback("OnValueChanged", function(_, _, r, g, b)
		db.textColor = { r = r, g = g, b = b }
		if db.useTextColor then addon.DataHub:RequestUpdate(stream) end
	end)
	frame:AddChild(textColor)

	local highColor = AceGUI:Create("ColorPicker")
	highColor:SetLabel(L["durabilityHighColor"] or "High durability color")
	highColor:SetColor(db.highColor.r, db.highColor.g, db.highColor.b)
	highColor:SetCallback("OnValueChanged", function(_, _, r, g, b)
		db.highColor = { r = r, g = g, b = b }
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(highColor)

	local midColor = AceGUI:Create("ColorPicker")
	midColor:SetLabel(L["durabilityMidColor"] or "Medium durability color")
	midColor:SetColor(db.midColor.r, db.midColor.g, db.midColor.b)
	midColor:SetCallback("OnValueChanged", function(_, _, r, g, b)
		db.midColor = { r = r, g = g, b = b }
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(midColor)

	local lowColor = AceGUI:Create("ColorPicker")
	lowColor:SetLabel(L["durabilityLowColor"] or "Low durability color")
	lowColor:SetColor(db.lowColor.r, db.lowColor.g, db.lowColor.b)
	lowColor:SetCallback("OnValueChanged", function(_, _, r, g, b)
		db.lowColor = { r = r, g = g, b = b }
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(lowColor)

	frame.frame:Show()
end

local floor = math.floor
local GetInventoryItemDurability = GetInventoryItemDurability
local GetInventoryItemLink = GetInventoryItemLink
local GetInventoryItemID = GetInventoryItemID
local GetItemInfo = GetItemInfo
local GetItemInfoInstant = GetItemInfoInstant
local C_Item = C_Item
local GetItemQualityByID = C_Item and C_Item.GetItemQualityByID or nil
local GetItemIconByID = C_Item and C_Item.GetItemIconByID or nil

local itemSlots = {
	[1] = INVTYPE_HEAD,
	[2] = INVTYPE_NECK,
	[3] = INVTYPE_SHOULDER,
	[15] = INVTYPE_CLOAK,
	[5] = INVTYPE_CHEST,
	[9] = INVTYPE_WRIST,
	[10] = INVTYPE_HAND,
	[6] = INVTYPE_WAIST,
	[7] = INVTYPE_LEGS,
	[8] = INVTYPE_FEET,
	[11] = INVTYPE_FINGER,
	[12] = INVTYPE_FINGER,
	[13] = INVTYPE_TRINKET,
	[14] = INVTYPE_TRINKET,
	[16] = INVTYPE_WEAPONMAINHAND,
	[17] = INVTYPE_WEAPONOFFHAND,
}

local function colorToHex(color)
	local r = math.floor(((color and color.r) or 1) * 255 + 0.5)
	local g = math.floor(((color and color.g) or 1) * 255 + 0.5)
	local b = math.floor(((color and color.b) or 1) * 255 + 0.5)
	return ("%02x%02x%02x"):format(r, g, b)
end

local function getPercentColor(percent)
	local rounded = floor((percent or 0) + 0.5)
	if rounded > 80 then return colorToHex(db and db.highColor) end
	if rounded > 50 then return colorToHex(db and db.midColor) end
	return colorToHex(db and db.lowColor)
end

-- Feste Reihenfolge für den Tooltip (anpassen, wenn du willst)
local slotOrder = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17 } -- Head, Neck, Shoulder, Cloak, ...
local lines = {}
local summary = { totalPercent = 100, critCount = 0, items = 0, current = 0, max = 0 }

local function formatPercentColored(percent) return ("|cff%s%d%%|r"):format(getPercentColor(percent), percent) end

local function colorizeValue(text, color)
	if not text or text == "" then return text end
	if color and color.r and color.g and color.b then return ("|cff%02x%02x%02x%s|r"):format(floor(color.r * 255 + 0.5), floor(color.g * 255 + 0.5), floor(color.b * 255 + 0.5), text) end
	return text
end

local function colorizeText(text, quality)
	if not text then return UNKNOWN end
	if ITEM_QUALITY_COLORS and quality and ITEM_QUALITY_COLORS[quality] then
		local c = ITEM_QUALITY_COLORS[quality]
		return ("|cff%02x%02x%02x%s|r"):format((c.r or 1) * 255, (c.g or 1) * 255, (c.b or 1) * 255, text)
	end
	return text
end

local itemCache = {}

local function getCachedItemInfo(itemID, link)
	if not itemID and not link then return end
	local key = itemID or link
	local cached = itemCache[key]
	if not cached then
		cached = {}
		itemCache[key] = cached
	end

	if (not cached.name or cached.quality == nil or not cached.icon) and GetItemInfo then
		local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(link or itemID)
		if name then cached.name = name end
		if quality ~= nil then cached.quality = quality end
		if icon then cached.icon = icon end
	end
	if cached.quality == nil and itemID and GetItemQualityByID then
		local quality = GetItemQualityByID(itemID)
		if quality ~= nil then cached.quality = quality end
	end
	if not cached.icon and itemID then
		if GetItemIconByID then
			cached.icon = GetItemIconByID(itemID)
		elseif GetItemInfoInstant then
			local _, _, _, _, icon = GetItemInfoInstant(itemID)
			if icon then cached.icon = icon end
		end
	end

	return cached.name, cached.quality, cached.icon
end

local function resolveItemInfo(line)
	if not line then return end
	local name, quality, icon = getCachedItemInfo(line.itemID, line.link)
	if name then line.name = name end
	if quality ~= nil then line.quality = quality end
	if icon then line.icon = icon end
end
local function calculateDurability(stream)
	ensureDB()
	-- Hide stream entirely for Timerunners (gear is indestructible)
	if addon.functions and addon.functions.IsTimerunner and addon.functions.IsTimerunner() then
		wipe(lines)
		summary.totalPercent = 100
		summary.critCount = 0
		summary.items = 0
		summary.current = 0
		summary.max = 0
		stream.snapshot.fontSize = db and db.fontSize or 13
		stream.snapshot.text = nil
		stream.snapshot.tooltip = nil
		stream.snapshot.hidden = true
		return
	end
	stream.snapshot.hidden = nil
	local maxDur, currentDura, critDura = 0, 0, 0
	wipe(lines)
	local items = 0

	for _, slot in ipairs(slotOrder) do
		local name = itemSlots[slot]
		local cur, max = GetInventoryItemDurability(slot)
		if cur and max and max > 0 then
			local fDur = floor((cur / max) * 100 + 0.5)
			maxDur = maxDur + max
			currentDura = currentDura + cur
			if fDur < 50 then critDura = critDura + 1 end
			local link = GetInventoryItemLink("player", slot)
			local itemID = GetInventoryItemID and GetInventoryItemID("player", slot) or nil
			local itemName, quality, icon = getCachedItemInfo(itemID, link)
			lines[#lines + 1] = {
				slot = name,
				name = itemName or name,
				quality = quality,
				itemID = itemID,
				icon = icon,
				link = link,
				cur = cur,
				max = max,
				percent = fDur,
			}
			items = items + 1
		end
	end

	if maxDur == 0 then
		maxDur, currentDura = 100, 100 -- 100% anzeigen, wenn nichts messbar ist
	end

	local durValue = (currentDura / maxDur) * 100
	local color = getPercentColor(durValue)

	local useTextColor = db and db.useTextColor and db.textColor
	local critDuraText = ""
	local showCritical = db and db.showCritical ~= false
	if showCritical and critDura > 0 then
		if useTextColor then
			critDuraText = ("%d %s < 50%%"):format(critDura, ITEMS)
		else
			critDuraText = ("|cff%s%d|r %s < 50%%"):format(getPercentColor(0), critDura, ITEMS)
		end
	end

	stream.snapshot.fontSize = db and db.fontSize or 13
	local percentText
	if useTextColor then
		percentText = ("%.0f%%"):format(durValue)
	else
		percentText = ("|cff%s%.0f%%|r"):format(color, durValue)
	end
	local text = percentText
	if critDuraText ~= "" then text = text .. " " .. critDuraText end
	if useTextColor then text = colorizeValue(text, db.textColor) end
	if db.showIcon ~= false then text = ("|T136241:%d|t %s"):format(db and db.fontSize or 13, text) end
	stream.snapshot.text = text

	summary.totalPercent = durValue
	summary.critCount = critDura
	summary.items = items
	summary.current = currentDura
	summary.max = maxDur
end

local provider = {
	id = "durability",
	version = 2,
	title = DURABILITY,
	update = calculateDurability,
	events = {
		GUILDBANK_UPDATE_MONEY = function(stream) addon.DataHub:RequestUpdate(stream) end,
		PLAYER_DEAD = function(stream)
			C_Timer.After(1, function() addon.DataHub:RequestUpdate(stream) end)
		end,
		PLAYER_EQUIPMENT_CHANGED = function(stream) addon.DataHub:RequestUpdate(stream) end,
		PLAYER_MONEY = function(stream) addon.DataHub:RequestUpdate(stream) end,
		PLAYER_REGEN_ENABLED = function(stream) addon.DataHub:RequestUpdate(stream) end,
		PLAYER_UNGHOST = function(stream)
			C_Timer.After(1, function() addon.DataHub:RequestUpdate(stream) end)
		end,
		PLAYER_LOGIN = function(stream) addon.DataHub:RequestUpdate(stream) end,
	},
	OnMouseEnter = function(b)
		ensureDB()
		local tip = GameTooltip
		tip:ClearLines()
		tip:SetOwner(b, "ANCHOR_TOPLEFT")
		tip:AddLine(DURABILITY)
		local iconSize = db and db.fontSize or 13
		for _, v in ipairs(lines) do
			resolveItemInfo(v)
			local leftText = v.name or v.slot
			local left = colorizeText(leftText, v.quality)
			if v.icon then left = ("|T%s:%d:%d:0:0|t %s"):format(v.icon, iconSize, iconSize, left) end
			tip:AddDoubleLine(left, formatPercentColored(v.percent or 0))
		end
		tip:AddLine(" ")
		tip:AddDoubleLine(TOTAL or "Total", formatPercentColored(math.floor((summary.totalPercent or 0) + 0.5)))
		if db and db.showCritical ~= false and summary.critCount and summary.critCount > 0 then
			tip:AddDoubleLine(ITEMS .. " < 50%", ("|cff%s%s|r"):format(getPercentColor(0), tostring(summary.critCount)))
		end
		local hint = getOptionsHint()
		if hint then tip:AddLine(hint) end
		tip:Show()

		local name = tip:GetName()
		local left1 = _G[name .. "TextLeft1"]
		local right1 = _G[name .. "TextRight1"]
		if left1 then
			left1:SetFontObject(GameTooltipText)
			local r, g, bColor = NORMAL_FONT_COLOR:GetRGB()
			left1:SetTextColor(r, g, bColor)
		end
		if right1 then right1:SetFontObject(GameTooltipText) end
	end,
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
