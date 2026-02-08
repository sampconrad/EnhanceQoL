-- luacheck: globals EnhanceQoL DifficultyUtil MenuResponse SetRaidDifficulties
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
local function showDifficultyMenu(owner)
	if not MenuUtil or not MenuUtil.CreateContextMenu then return end
	local ids = DifficultyUtil and DifficultyUtil.ID or {}
	local dungeonDifficulties = {
		{ id = ids.DungeonNormal or 1, text = PLAYER_DIFFICULTY1 },
		{ id = ids.DungeonHeroic or 2, text = PLAYER_DIFFICULTY2 },
		{ id = ids.DungeonMythic or 23, text = PLAYER_DIFFICULTY6 },
	}
	local raidDifficulties = {
		{ id = ids.PrimaryRaidNormal or 14, text = PLAYER_DIFFICULTY1 },
		{ id = ids.PrimaryRaidHeroic or 15, text = PLAYER_DIFFICULTY2 },
		{ id = ids.PrimaryRaidMythic or 16, text = PLAYER_DIFFICULTY6 },
	}

	MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
		rootDescription:SetTag("MENU_EQOL_DIFFICULTY")

		rootDescription:CreateTitle(DUNGEON_DIFFICULTY or "Dungeon Difficulty")
		local function IsDungeonSelected(difficultyID) return GetDungeonDifficultyID() == difficultyID end
		local function SetDungeonSelected(difficultyID)
			SetDungeonDifficultyID(difficultyID)
			return MenuResponse and MenuResponse.Close
		end
		for _, data in ipairs(dungeonDifficulties) do
			local radio = rootDescription:CreateRadio(data.text, IsDungeonSelected, SetDungeonSelected, data.id)
			if DifficultyUtil and DifficultyUtil.IsDungeonDifficultyEnabled then radio:SetEnabled(DifficultyUtil.IsDungeonDifficultyEnabled(data.id)) end
		end

		rootDescription:CreateDivider()
		rootDescription:CreateTitle(RAID_DIFFICULTY or "Raid Difficulty")
		local function IsRaidSelected(difficultyID)
			if DifficultyUtil and DifficultyUtil.DoesCurrentRaidDifficultyMatch then return DifficultyUtil.DoesCurrentRaidDifficultyMatch(difficultyID) end
			return GetRaidDifficultyID() == difficultyID
		end
		local function SetRaidSelected(difficultyID)
			if SetRaidDifficulties then
				SetRaidDifficulties(true, difficultyID)
			else
				SetRaidDifficultyID(difficultyID)
			end
			return MenuResponse and MenuResponse.Close
		end
		for _, data in ipairs(raidDifficulties) do
			local radio = rootDescription:CreateRadio(data.text, IsRaidSelected, SetRaidSelected, data.id)
			if DifficultyUtil and DifficultyUtil.IsRaidDifficultyEnabled then radio:SetEnabled(DifficultyUtil.IsRaidDifficultyEnabled(data.id)) end
		end
	end)
end

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
	local hint = getOptionsHint()
	local clickHint = L["Difficulty menu click hint"] or "Left-click to change difficulty"
	if hint then
		stream.snapshot.tooltip = clickHint .. "\n" .. hint
	else
		stream.snapshot.tooltip = clickHint
	end
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
	OnClick = function(button, btn)
		if btn == "RightButton" then
			createAceWindow()
		else
			showDifficultyMenu(button)
		end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
