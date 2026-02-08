-- luacheck: globals EnhanceQoL C_Map IsInInstance GAMEMENU_OPTIONS FONT_SIZE UIParent C_Timer
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
	addon.db.datapanel.coordinates = addon.db.datapanel.coordinates or {}
	db = addon.db.datapanel.coordinates
	db.fontSize = db.fontSize or 14
	db.updateInterval = db.updateInterval or 0.2
	if db.hideInInstance == nil then db.hideInInstance = true end
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
	frame:SetWidth(320)
	frame:SetHeight(260)
	frame:SetLayout("List")

	frame.frame:SetScript("OnShow", function(self) RestorePosition(self) end)
	frame.frame:SetScript("OnHide", function(self)
		local point, _, _, xOfs, yOfs = self:GetPoint()
		db.point = point
		db.x = xOfs
		db.y = yOfs
	end)

	local updateTimer
	local function scheduleUpdate()
		if updateTimer then updateTimer:Cancel() end
		updateTimer = C_Timer.NewTimer(0.05, function()
			updateTimer = nil
			if stream then addon.DataHub:RequestUpdate(stream) end
		end)
	end

	local fontSize = AceGUI:Create("Slider")
	fontSize:SetLabel(FONT_SIZE)
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		scheduleUpdate()
	end)
	frame:AddChild(fontSize)

	local interval = AceGUI:Create("Slider")
	interval:SetLabel(L["Coordinates update interval (s)"] or "Coordinates update interval (s)")
	interval:SetSliderValues(0.10, 1.00, 0.05)
	interval:SetValue(db.updateInterval)
	interval:SetCallback("OnValueChanged", function(_, _, val)
		db.updateInterval = val
		if stream then stream.interval = val end
		scheduleUpdate()
	end)
	frame:AddChild(interval)

	local hideInstance = AceGUI:Create("CheckBox")
	hideInstance:SetLabel(L["Hide coordinates in instances"] or "Hide coordinates in instances")
	hideInstance:SetValue(db.hideInInstance and true or false)
	hideInstance:SetCallback("OnValueChanged", function(_, _, val)
		db.hideInInstance = val and true or false
		scheduleUpdate()
	end)
	frame:AddChild(hideInstance)

	frame.frame:Show()
end

local format = string.format

local function formatCoords(x, y)
	if not x or not y then return nil end
	return format("%.2f, %.2f", x * 100, y * 100)
end

local function getPlayerCoords()
	if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return nil end
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then return nil end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return nil end
	return pos.x, pos.y
end

local function updateCoordinates(s)
	s = s or stream
	ensureDB()

	if s and s.interval ~= db.updateInterval then s.interval = db.updateInterval end

	if db.hideInInstance and IsInInstance and IsInInstance() then
		s.snapshot.text = " "
	else
		local px, py = getPlayerCoords()
		local playerText = formatCoords(px, py)
		s.snapshot.text = playerText or "0, 0"
	end

	s.snapshot.fontSize = db.fontSize or 14
	s.snapshot.tooltip = getOptionsHint()
end

local provider = {
	id = "coordinates",
	version = 1,
	title = L["Coordinates"] or "Coordinates",
	poll = 0.2,
	update = updateCoordinates,
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
