-- luacheck: globals EnhanceQoL
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.difficulty = addon.db.datapanel.difficulty or {}
	db = addon.db.datapanel.difficulty
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

local I_DUNGEON = "|TInterface\\Addons\\EnhanceQoL\\Icons\\Dungeon:%d:%d:0:0|t"
local I_RAID = "|TInterface\\Addons\\EnhanceQoL\\Icons\\Raid:14:14:0:0|t"

local function getShortLabel(difficultyID)
	if difficultyID == 1 or difficultyID == 3 or difficultyID == 4 or difficultyID == 14 or difficultyID == 33 or difficultyID == 150 then
		return "NM"
	elseif difficultyID == 2 or difficultyID == 5 or difficultyID == 6 or difficultyID == 15 or difficultyID == 205 or difficultyID == 230 then
		return "HC"
	elseif difficultyID == 16 or difficultyID == 23 then
		return "M"
	elseif difficultyID == 8 then
		return "M+"
	elseif difficultyID == 7 or difficultyID == 17 or difficultyID == 151 then
		return "LFR"
	elseif difficultyID == 24 then
		return "TW"
	end
	return "NM"
end

local function checkDifficulty(stream)
	ensureDB()
	local dg = getShortLabel(GetDungeonDifficultyID())
	local raid = getShortLabel(GetRaidDifficultyID())

	local size = db and db.fontSize or 14
	local iconD = (I_DUNGEON):format(size, size)
	local iconR = (I_RAID):format(size, size)
	stream.snapshot.fontSize = size

	stream.snapshot.text = I_DUNGEON .. " " .. dg .. " " .. I_RAID .. " " .. raid
	if not stream.snapshot.tooltip then stream.snapshot.tooltip = L["Right-Click for options"] end
end

local provider = {
	id = "difficulty",
	version = 1,
	title = LFG_LIST_DIFFICULTY,
	update = checkDifficulty,
	events = {
		PLAYER_DIFFICULTY_CHANGED = function(stream) addon.DataHub:RequestUpdate(stream) end,
		PLAYER_LOGIN = function(stream) addon.DataHub:RequestUpdate(stream) end,
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
