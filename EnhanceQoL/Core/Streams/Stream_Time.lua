-- luacheck: globals EnhanceQoL GetGameTime GAMEMENU_OPTIONS FONT_SIZE UIParent TIMEMANAGER_AM TIMEMANAGER_PM C_Timer NORMAL_FONT_COLOR ToggleTimeManager
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream
local timeColorHex
local lastColorR, lastColorG, lastColorB

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
	addon.db.datapanel.time = addon.db.datapanel.time or {}
	db = addon.db.datapanel.time
	db.fontSize = db.fontSize or 14
	db.displayMode = db.displayMode or "server"
	if db.use24Hour == nil then db.use24Hour = true end
	if db.showSeconds == nil then db.showSeconds = false end
	if not db.timeColor then
		local r, g, b = 1, 1, 1
		if NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.GetRGB then
			r, g, b = NORMAL_FONT_COLOR:GetRGB()
		end
		db.timeColor = { r = r, g = g, b = b }
	end
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

	local display = AceGUI:Create("Dropdown")
	display:SetLabel(L["Time display"] or "Time display")
	display:SetList({
		server = L["Server time"] or "Server time",
		localTime = L["Local time"] or "Local time",
		both = L["Server + Local"] or "Server + Local",
	})
	display:SetValue(db.displayMode)
	display:SetCallback("OnValueChanged", function(_, _, key)
		db.displayMode = key or "server"
		scheduleUpdate()
	end)
	frame:AddChild(display)

	local use24 = AceGUI:Create("CheckBox")
	use24:SetLabel(L["24-hour format"] or "24-hour format")
	use24:SetValue(db.use24Hour and true or false)
	use24:SetCallback("OnValueChanged", function(_, _, val)
		db.use24Hour = val and true or false
		scheduleUpdate()
	end)
	frame:AddChild(use24)

	local showSeconds = AceGUI:Create("CheckBox")
	showSeconds:SetLabel(L["Show seconds"] or "Show seconds")
	showSeconds:SetValue(db.showSeconds and true or false)
	showSeconds:SetCallback("OnValueChanged", function(_, _, val)
		db.showSeconds = val and true or false
		scheduleUpdate()
	end)
	frame:AddChild(showSeconds)

	local color = AceGUI:Create("ColorPicker")
	color:SetLabel(L["Time color"] or "Time color")
	color:SetColor(db.timeColor.r, db.timeColor.g, db.timeColor.b)
	color:SetCallback("OnValueChanged", function(_, _, r, g, b)
		db.timeColor = { r = r, g = g, b = b }
		timeColorHex = nil
		scheduleUpdate()
	end)
	frame:AddChild(color)

	frame.frame:Show()
end

local function formatTime(h, m, s)
	if h == nil or m == nil then return "" end
	local showSeconds = db and db.showSeconds
	local use24 = db and db.use24Hour
	local suffix = ""
	if not use24 then
		local isPM = h >= 12
		suffix = isPM and (TIMEMANAGER_PM or "PM") or (TIMEMANAGER_AM or "AM")
		h = h % 12
		if h == 0 then h = 12 end
	end

	if showSeconds then
		s = s or 0
		if use24 then return ("%02d:%02d:%02d"):format(h, m, s) end
		return ("%d:%02d:%02d %s"):format(h, m, s, suffix)
	end

	if use24 then return ("%02d:%02d"):format(h, m) end
	return ("%d:%02d %s"):format(h, m, suffix)
end

local function getLocalTimeParts()
	local t = date("*t")
	if not t then return nil end
	return t.hour, t.min, t.sec
end

local function getServerTimeParts(fallbackSec)
	if not GetGameTime then return nil end
	local h, m = GetGameTime()
	if h == nil or m == nil then return nil end
	return h, m, fallbackSec
end

local function updateColorCache()
	local c = db and db.timeColor
	local r = (c and c.r) or 1
	local g = (c and c.g) or 1
	local b = (c and c.b) or 1
	if timeColorHex and r == lastColorR and g == lastColorG and b == lastColorB then return end
	lastColorR, lastColorG, lastColorB = r, g, b
	timeColorHex = ("%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function colorize(text)
	if not text or text == "" then return "" end
	if not timeColorHex then updateColorCache() end
	if not timeColorHex then return text end
	return ("|cff%s%s|r"):format(timeColorHex, text)
end

local function updateTime(s)
	s = s or stream
	ensureDB()
	updateColorCache()

	local lh, lm, ls = getLocalTimeParts()
	local interval
	if db.showSeconds then
		interval = 1
	else
		if ls == nil then
			interval = 30
		else
			local wait = 60 - (ls % 60)
			if wait <= 0 then wait = 60 end
			interval = wait
		end
	end
	if s.interval ~= interval then s.interval = interval end
	local sh, sm, ss = getServerTimeParts(ls)
	local mode = db.displayMode or "server"

	if mode == "localTime" then
		s.snapshot.text = colorize(formatTime(lh, lm, ls))
		s.snapshot.tooltip = getOptionsHint()
	elseif mode == "both" then
		local serverText = formatTime(sh, sm, ss)
		local localText = formatTime(lh, lm, ls)
		s.snapshot.text = colorize(serverText .. " / " .. localText)
		local tooltip = (L["Server time"] or "Server time") .. ": " .. serverText
		tooltip = tooltip .. "\n" .. (L["Local time"] or "Local time") .. ": " .. localText
		local optionsHint = getOptionsHint()
		if optionsHint then tooltip = tooltip .. "\n" .. optionsHint end
		s.snapshot.tooltip = tooltip
	else
		s.snapshot.text = colorize(formatTime(sh, sm, ss))
		s.snapshot.tooltip = getOptionsHint()
	end

	s.snapshot.fontSize = db.fontSize or 14
end

local provider = {
	id = "time",
	version = 1,
	title = L["Time"] or "Time",
	poll = 1,
	update = updateTime,
	events = {
		PLAYER_ENTERING_WORLD = function(s) addon.DataHub:RequestUpdate(s) end,
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then
			createAceWindow()
		elseif btn == "LeftButton" then
			if ToggleTimeManager then ToggleTimeManager() end
		end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
