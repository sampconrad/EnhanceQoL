-- luacheck: globals EnhanceQoL GetAverageItemLevel GetItemLevelColor GetInventoryItemLink GetInventoryItemTexture C_Item GetDetailedItemLevelInfo NOT_APPLICABLE ITEM_LEVEL_ABBR STAT_AVERAGE_ITEM_LEVEL STAT_AVERAGE_ITEM_LEVEL_EQUIPPED LFG_LIST_ITEM_LEVEL_INSTR_PVP_SHORT EQUIPPED
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream

local format = string.format
local floor = math.floor

local lastAvg, lastEquipped, lastPvp

local slotIDs = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
local iconString = "|T%s:13:15:0:0:50:50:4:46:4:46|t %s"

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.itemlevel = addon.db.datapanel.itemlevel or {}
	db = addon.db.datapanel.itemlevel
	db.fontSize = db.fontSize or 14
end

local function RestorePosition(frame)
	if not db then return end
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
	fontSize:SetLabel(FONT_SIZE)
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(fontSize)

	frame.frame:Show()
end

local function getOptionsHint()
	if addon.DataPanel and addon.DataPanel.GetOptionsHintText then
		local text = addon.DataPanel.GetOptionsHintText()
		if text ~= nil then return text end
		return nil
	end
	return L["Right-Click for options"]
end

local function ensureItemLevelColorFunc()
	if GetItemLevelColor then return end
	if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.LoadAddOn then
		if not C_AddOns.IsAddOnLoaded("Blizzard_UIPanels_Game") then C_AddOns.LoadAddOn("Blizzard_UIPanels_Game") end
	elseif UIParentLoadAddOn then
		UIParentLoadAddOn("Blizzard_UIPanels_Game")
	end
end

local function getItemLevelColor()
	ensureItemLevelColorFunc()
	if GetItemLevelColor then
		local r, g, b = GetItemLevelColor()
		if r then return r, g, b end
	end
	return 1, 1, 1
end

local function toHex(r, g, b) return format("%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5)) end

local function colorizeNumber(num, r, g, b)
	if num == nil then return "" end
	return ("|cff%s%.2f|r"):format(toHex(r, g, b), num)
end

local function diffColor(diff)
	if diff == nil then return 1, 1, 1 end
	if diff >= 0 then return 0.1, 1, 0.1 end
	return 1, 0.1, 0.1
end

local function getDetailedItemLevel(link)
	if not link then return nil end
	if C_Item and C_Item.GetDetailedItemLevelInfo then return C_Item.GetDetailedItemLevelInfo(link) end
	if GetDetailedItemLevelInfo then return GetDetailedItemLevelInfo(link) end
	return nil
end

local function updateItemLevel(s)
	ensureDB()
	local avg, equipped, pvp = GetAverageItemLevel()
	if not avg then
		s.snapshot.text = NOT_APPLICABLE or "N/A"
		s.snapshot.fontSize = db.fontSize
		lastAvg, lastEquipped, lastPvp = nil, nil, nil
		return
	end

	lastAvg, lastEquipped, lastPvp = avg, equipped, pvp
	local r, g, b = getItemLevelColor()
	local label = ITEM_LEVEL_ABBR or "iLvl"
	local equippedText = colorizeNumber(equipped or avg, r, g, b)
	if equipped and avg and math.abs(avg - equipped) > 0.005 then
		local avgText = colorizeNumber(avg, r, g, b)
		s.snapshot.text = format("%s: %s / %s", label, equippedText, avgText)
	else
		s.snapshot.text = format("%s: %s", label, equippedText)
	end
	s.snapshot.fontSize = db.fontSize
end

local provider = {
	id = "itemlevel",
	version = 1,
	title = L["Item Level"] or "Item Level",
	update = updateItemLevel,
	events = {
		PLAYER_AVG_ITEM_LEVEL_UPDATE = function(s) addon.DataHub:RequestUpdate(s) end,
		PLAYER_EQUIPMENT_CHANGED = function(s) addon.DataHub:RequestUpdate(s) end,
		PLAYER_ENTERING_WORLD = function(s) addon.DataHub:RequestUpdate(s) end,
	},
	eventsUnit = {
		player = {
			UNIT_INVENTORY_CHANGED = true,
		},
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
	OnMouseEnter = function(btn)
		local tip = GameTooltip
		tip:ClearLines()
		tip:SetOwner(btn, "ANCHOR_TOPLEFT")

		if not lastAvg then
			tip:SetText(NOT_APPLICABLE or "N/A")
			tip:Show()
			return
		end

		local avgText = format("%.2f", lastAvg)
		local eqText = format("%.2f", lastEquipped or lastAvg)
		local pvpText = format("%.2f", lastPvp or 0)

		local r, g, b = getItemLevelColor()
		tip:AddDoubleLine(STAT_AVERAGE_ITEM_LEVEL or (L["Item Level"] or "Item Level"), avgText, 1, 1, 1, r, g, b)
		if lastEquipped then
			local cr, cg, cb = diffColor(lastEquipped - lastAvg)
			tip:AddDoubleLine(EQUIPPED or "Equipped", eqText, 1, 1, 1, cr, cg, cb)
		end
		if lastPvp and lastPvp > 0 then
			local cr, cg, cb = diffColor(lastPvp - lastAvg)
			tip:AddDoubleLine(LFG_LIST_ITEM_LEVEL_INSTR_PVP_SHORT or "PvP Item Level", pvpText, 1, 1, 1, cr, cg, cb)
		end

		tip:AddLine(" ")
		for _, slot in ipairs(slotIDs) do
			local link = GetInventoryItemLink("player", slot)
			if link then
				local ilvl = getDetailedItemLevel(link)
				if ilvl then
					local icon = GetInventoryItemTexture("player", slot)
					local left = link
					if icon then left = format(iconString, icon, link) end
					local cr, cg, cb = diffColor(ilvl - lastAvg)
					tip:AddDoubleLine(left, format("%d", floor(ilvl + 0.5)), 1, 1, 1, cr, cg, cb)
				end
			end
		end

		local hint = getOptionsHint()
		if hint then
			tip:AddLine(" ")
			tip:AddLine(hint)
		end
		tip:Show()
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
