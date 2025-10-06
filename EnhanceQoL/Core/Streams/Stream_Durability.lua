-- luacheck: globals EnhanceQoL INVSLOT_HEAD INVSLOT_SHOULDER INVSLOT_CHEST INVSLOT_WAIST INVSLOT_LEGS INVSLOT_FEET INVSLOT_WRIST INVSLOT_HAND INVSLOT_BACK INVSLOT_MAINHAND INVSLOT_OFFHAND HEADSLOT SHOULDERSLOT CHESTSLOT WAISTSLOT LEGSLOT FEETSLOT WRISTSLOT HANDSSLOT BACKSLOT MAINHANDSLOT SECONDARYHANDSLOT
local addonName, addon = ...

local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.durability = addon.db.datapanel.durability or {}
	db = addon.db.datapanel.durability
	db.fontSize = db.fontSize or 13
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
	frame:SetTitle(GAMEMENU_OPTIONS)
	frame:SetWidth(300)
	frame:SetHeight(200)
	frame:SetLayout("List")

	frame.frame:SetScript("OnShow", function(self) RestorePosition(self) end)
	frame.frame:SetScript("OnHide", function(self)
		local point, _, _, xOfs, yOfs = self:GetPoint()
		db.point = point
		db.x = xOfs
		db.y = yOfs
	end)

	local fontSize = AceGUI:Create("Slider")
	fontSize:SetLabel("Font size")
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(fontSize)

	frame.frame:Show()
end

local floor = math.floor
local GetInventoryItemDurability = GetInventoryItemDurability

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

local function getPercentColor(percent)
	local color
	if tonumber(string.format("%." .. 0 .. "f", percent)) > 80 then
		color = "00FF00"
	elseif tonumber(string.format("%." .. 0 .. "f", percent)) > 50 then
		color = "FFFF00"
	else
		color = "FF0000"
	end
	return color
end

-- Feste Reihenfolge für den Tooltip (anpassen, wenn du willst)
local slotOrder = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17 } -- Head, Neck, Shoulder, Cloak, ...
local lines = {}
local function calculateDurability(stream)
	ensureDB()
	local maxDur, currentDura, critDura = 0, 0, 0
	wipe(lines)

	for _, slot in ipairs(slotOrder) do
		local name = itemSlots[slot]
		local cur, max = GetInventoryItemDurability(slot)
		if cur and max and max > 0 then
			local fDur = floor((cur / max) * 100 + 0.5)
			maxDur = maxDur + max
			currentDura = currentDura + cur
			if fDur < 50 then critDura = critDura + 1 end
			lines[#lines + 1] = { slot = name, dur = string.format("|cff%s%d%%|r", getPercentColor(fDur), fDur) }
		end
	end

	if maxDur == 0 then
		maxDur, currentDura = 100, 100 -- 100% anzeigen, wenn nichts messbar ist
	end

	local durValue = (currentDura / maxDur) * 100
	local color = getPercentColor(durValue)

	local critDuraText = ""
	if critDura > 0 then critDuraText = "|cffff0000" .. critDura .. "|r " .. ITEMS .. " < 50%" end

	stream.snapshot.fontSize = db and db.fontSize or 13
	stream.snapshot.text = ("|T136241:16|t |cff%s%.0f|r%% %s"):format(color, durValue, critDuraText)
end

local provider = {
	id = "durability",
	version = 1,
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
		local tip = GameTooltip
		tip:ClearLines()
		tip:SetOwner(b, "ANCHOR_TOPLEFT")
		for _, v in ipairs(lines) do
			local r, g, b = NORMAL_FONT_COLOR:GetRGB()
			tip:AddDoubleLine(v.slot, v.dur, r, g, b)
		end
		tip:AddLine(L["Right-Click for options"])
		tip:Show()

		local name = tip:GetName()
		local left1 = _G[name .. "TextLeft1"]
		local right1 = _G[name .. "TextRight1"]
		if left1 then
			left1:SetFontObject(GameTooltipText)
			local r, g, b = NORMAL_FONT_COLOR:GetRGB()
			left1:SetTextColor(r, g, b)
		end
		if right1 then right1:SetFontObject(GameTooltipText) end
	end,
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
