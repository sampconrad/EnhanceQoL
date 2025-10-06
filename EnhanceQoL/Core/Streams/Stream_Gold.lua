-- luacheck: globals EnhanceQoL
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.gold = addon.db.datapanel.gold or {}
	db = addon.db.datapanel.gold
	db.fontSize = db.fontSize or 14
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
local GetMoney = GetMoney

local COPPER_PER_GOLD = 10000

local function formatGoldString(copper)
	local g = floor(copper / COPPER_PER_GOLD)
	local s = floor((copper % COPPER_PER_GOLD) / 100)
	local c = copper % 100
	local gText = (BreakUpLargeNumbers and BreakUpLargeNumbers(g)) or tostring(g)
	return gText, s, c
end

local function checkMoney(stream)
	ensureDB()
	local money = GetMoney() or 0
	local gText, s, c = formatGoldString(money)
	local size = db and db.fontSize or 12
	stream.snapshot.fontSize = size
	stream.snapshot.text = ("|TInterface\\MoneyFrame\\UI-GoldIcon:%d:%d:0:0|t %s"):format(size, size, gText)
	if not stream.snapshot.tooltip then stream.snapshot.tooltip = L["Right-Click for options"] end
end

local provider = {
	id = "gold",
	version = 1,
	title = WORLD_QUEST_REWARD_FILTERS_GOLD,
	update = checkMoney,
	events = {
		PLAYER_MONEY = function(stream) addon.DataHub:RequestUpdate(stream) end,
		PLAYER_LOGIN = function(stream) addon.DataHub:RequestUpdate(stream) end,
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
