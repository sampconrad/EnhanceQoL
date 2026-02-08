-- luacheck: globals EnhanceQoL GetFramerate GetNetStats GAMEMENU_OPTIONS MAINMENUBAR_FPS_LABEL MAINMENUBAR_LATENCY_LABEL NORMAL_FONT_COLOR
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

-- Micro-optimizations: localize frequently used globals
local floor = math.floor
local min = math.min
local format = string.format
local GetTime = GetTime
local GetFramerate = GetFramerate
local GetNetStats = GetNetStats

-- Runtime state for smoothing and cadence
local lastPingUpdate = 0
local pingHome, pingWorld = nil, nil
local emaFPS -- exponential moving average for FPS
-- Change detection cache (declare early so callbacks see locals, not globals)
local lastFps, lastHome, lastWorld, lastPingMode, lastDisplay

-- Color helpers (hex without leading #)
local function fpsColorHex(v)
	if v >= 60 then
		return "00ff00" -- green
	elseif v >= 30 then
		return "ffff00" -- yellow
	else
		return "ff0000"
	end -- red
end

local function colorToHex(color)
	local r = (color and color.r) or 1
	local g = (color and color.g) or 1
	local b = (color and color.b) or 1
	return format("%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

local function pingColorHex(v)
	local low = tonumber(db and db.pingThresholdLow) or 50
	local mid = tonumber(db and db.pingThresholdMid) or 150
	if low < 0 then low = 0 end
	if mid < low then mid = low end

	if v <= low then return colorToHex(db and db.pingColorLow) end
	if v <= mid then return colorToHex(db and db.pingColorMid) end
	return colorToHex(db and db.pingColorHigh)
end

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.latency = addon.db.datapanel.latency or {}
	db = addon.db.datapanel.latency

	db.fontSize = db.fontSize or 14
	db.displayMode = db.displayMode or "both"
	if not db.textColor then
		local r, g, b = 1, 0.82, 0
		if NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.GetRGB then
			r, g, b = NORMAL_FONT_COLOR:GetRGB()
		end
		db.textColor = { r = r, g = g, b = b }
	end
	-- Cadence (seconds)
	db.fpsInterval = db.fpsInterval or 0.25 -- 4x/s
	db.pingInterval = db.pingInterval or 1.0 -- 1x/s
	-- Smoothing window (seconds); 0 disables smoothing
	if db.fpsSmoothWindow == nil then db.fpsSmoothWindow = 0.75 end
	-- Ping display mode: "max" or "split"
	db.pingMode = db.pingMode or "max"
	-- Ping thresholds + colors
	db.pingThresholdLow = db.pingThresholdLow or 50
	db.pingThresholdMid = db.pingThresholdMid or 150
	db.pingColorLow = db.pingColorLow or { r = 0, g = 1, b = 0 }
	db.pingColorMid = db.pingColorMid or { r = 1, g = 0.65, b = 0 }
	db.pingColorHigh = db.pingColorHigh or { r = 1, g = 0, b = 0 }
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
	frame:SetWidth(360)
	frame:SetHeight(420)
	frame:SetLayout("Fill")

	frame.frame:SetScript("OnShow", function(self) RestorePosition(self) end)
	frame.frame:SetScript("OnHide", function(self)
		local point, _, _, xOfs, yOfs = self:GetPoint()
		db.point = point
		db.x = xOfs
		db.y = yOfs
	end)

	-- Debounce RequestUpdate calls while dragging sliders
	local sliderTimer
	local function scheduleUpdate()
		if sliderTimer then sliderTimer:Cancel() end
		sliderTimer = C_Timer.NewTimer(0.05, function()
			sliderTimer = nil
			if stream then addon.DataHub:RequestUpdate(stream) end
		end)
	end

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("List")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	frame:AddChild(scroll)

	local fontSize = AceGUI:Create("Slider")
	fontSize:SetLabel(FONT_SIZE)
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		scheduleUpdate()
	end)
	scroll:AddChild(fontSize)

	local textColor = AceGUI:Create("ColorPicker")
	textColor:SetLabel(L["Text color"] or "Text color")
	textColor:SetColor(db.textColor.r, db.textColor.g, db.textColor.b)
	textColor:SetCallback("OnValueChanged", function(_, _, r, g, b)
		db.textColor = { r = r, g = g, b = b }
		lastDisplay = nil
		lastFps = nil
		lastHome, lastWorld = nil, nil
		lastPingMode = nil
		scheduleUpdate()
	end)
	scroll:AddChild(textColor)

	local display = AceGUI:Create("Dropdown")
	display:SetLabel(L["latencyPanelDisplay"] or "Panel display")
	display:SetList({
		both = L["latencyPanelDisplayBoth"] or "FPS + Latency",
		ping = L["latencyPanelDisplayPing"] or "Latency only",
		fps = L["latencyPanelDisplayFPS"] or "FPS only",
	})
	display:SetValue(db.displayMode)
	display:SetCallback("OnValueChanged", function(_, _, key)
		db.displayMode = key or "both"
		lastDisplay = nil
		lastFps = nil
		lastHome, lastWorld = nil, nil
		lastPingMode = nil
		pingHome, pingWorld = nil, nil
		emaFPS = nil
		scheduleUpdate()
	end)
	scroll:AddChild(display)

	local fpsRate = AceGUI:Create("Slider")
	fpsRate:SetLabel(L["FPS update interval (s)"] or "FPS update interval (s)")
	fpsRate:SetSliderValues(0.10, 1.00, 0.05)
	fpsRate:SetValue(db.fpsInterval)
	fpsRate:SetCallback("OnValueChanged", function(_, _, val)
		db.fpsInterval = val
		if stream then stream.interval = val end -- driver picks up new cadence
		-- Reset EMA so the new cadence takes immediate effect visually
		emaFPS = nil
		lastFps = nil
		scheduleUpdate()
	end)
	scroll:AddChild(fpsRate)

	local smooth = AceGUI:Create("Slider")
	smooth:SetLabel(L["FPS smoothing window (s)"] or "FPS smoothing window (s)")
	smooth:SetSliderValues(0.00, 1.50, 0.05)
	smooth:SetValue(db.fpsSmoothWindow)
	smooth:SetCallback("OnValueChanged", function(_, _, val)
		db.fpsSmoothWindow = val
		-- Reset EMA for a fresh smoothing window
		emaFPS = nil
		lastFps = nil
		scheduleUpdate()
	end)
	scroll:AddChild(smooth)

	local pingRate = AceGUI:Create("Slider")
	pingRate:SetLabel(L["Ping update interval (s)"] or "Ping update interval (s)")
	pingRate:SetSliderValues(0.50, 3.00, 0.25)
	pingRate:SetValue(db.pingInterval)
	pingRate:SetCallback("OnValueChanged", function(_, _, val)
		db.pingInterval = val
		scheduleUpdate()
	end)
	scroll:AddChild(pingRate)

	local mode = AceGUI:Create("Dropdown")
	mode:SetLabel(L["Ping display"] or "Ping display")
	mode:SetList({
		max = L["Max(home, world)"] or "Max(home, world)",
		split = L["home|world"] or "Home + World",
		split_vertical = L["latencyPingModeVertical"] or "Home + World (vertical)",
		home = _G["HOME"] or "Home",
		world = _G["WORLD"] or "World",
	})
	mode:SetValue(db.pingMode)
	mode:SetCallback("OnValueChanged", function(_, _, key)
		db.pingMode = key or "max"
		-- Invalidate cache to force re-render even if values are equal
		lastPingMode = nil
		lastHome, lastWorld = nil, nil
		scheduleUpdate()
	end)
	scroll:AddChild(mode)

	local pingColors = AceGUI:Create("InlineGroup")
	pingColors:SetTitle(L["latencyPingColorSection"] or "Ping colors")
	pingColors:SetFullWidth(true)
	pingColors:SetLayout("List")

	local midThreshold

	local lowThreshold = AceGUI:Create("Slider")
	lowThreshold:SetLabel(L["latencyPingLowThreshold"] or "Low threshold (ms)")
	lowThreshold:SetSliderValues(0, 1000, 1)
	lowThreshold:SetValue(db.pingThresholdLow)
	lowThreshold:SetCallback("OnValueChanged", function(_, _, val)
		db.pingThresholdLow = floor(val + 0.5)
		if db.pingThresholdMid < db.pingThresholdLow then
			db.pingThresholdMid = db.pingThresholdLow
			if midThreshold then midThreshold:SetValue(db.pingThresholdMid) end
		end
		lastHome, lastWorld = nil, nil
		scheduleUpdate()
	end)
	pingColors:AddChild(lowThreshold)

	midThreshold = AceGUI:Create("Slider")
	midThreshold:SetLabel(L["latencyPingMidThreshold"] or "Mid threshold (ms)")
	midThreshold:SetSliderValues(0, 1000, 1)
	midThreshold:SetValue(db.pingThresholdMid)
	midThreshold:SetCallback("OnValueChanged", function(_, _, val)
		db.pingThresholdMid = floor(val + 0.5)
		if db.pingThresholdMid < db.pingThresholdLow then
			db.pingThresholdLow = db.pingThresholdMid
			lowThreshold:SetValue(db.pingThresholdLow)
		end
		lastHome, lastWorld = nil, nil
		scheduleUpdate()
	end)
	pingColors:AddChild(midThreshold)

	local lowColor = AceGUI:Create("ColorPicker")
	lowColor:SetLabel(L["latencyPingLowColor"] or "Low ping color")
	lowColor:SetColor(db.pingColorLow.r, db.pingColorLow.g, db.pingColorLow.b)
	lowColor:SetCallback("OnValueChanged", function(_, _, r, g, b)
		db.pingColorLow = { r = r, g = g, b = b }
		lastHome, lastWorld = nil, nil
		scheduleUpdate()
	end)
	pingColors:AddChild(lowColor)

	local midColor = AceGUI:Create("ColorPicker")
	midColor:SetLabel(L["latencyPingMidColor"] or "Mid ping color")
	midColor:SetColor(db.pingColorMid.r, db.pingColorMid.g, db.pingColorMid.b)
	midColor:SetCallback("OnValueChanged", function(_, _, r, g, b)
		db.pingColorMid = { r = r, g = g, b = b }
		lastHome, lastWorld = nil, nil
		scheduleUpdate()
	end)
	pingColors:AddChild(midColor)

	local highColor = AceGUI:Create("ColorPicker")
	highColor:SetLabel(L["latencyPingHighColor"] or "High ping color")
	highColor:SetColor(db.pingColorHigh.r, db.pingColorHigh.g, db.pingColorHigh.b)
	highColor:SetCallback("OnValueChanged", function(_, _, r, g, b)
		db.pingColorHigh = { r = r, g = g, b = b }
		lastHome, lastWorld = nil, nil
		scheduleUpdate()
	end)
	pingColors:AddChild(highColor)

	scroll:AddChild(pingColors)

	frame.frame:Show()
end

-- EMA-based smoothing (no tables, constant work per tick)
local function smoothFPS(current, interval, window)
	if (window or 0) <= 0 then
		emaFPS = current
		return current
	end
	local alpha = min(1, (interval or 0.25) / window)
	emaFPS = emaFPS and (emaFPS + alpha * (current - emaFPS)) or current
	return emaFPS
end

-- (declared above)

local function updateLatency(s)
	s = s or stream
	ensureDB()
	local baseHex = colorToHex(db and db.textColor)
	local function base(text) return format("|cff%s%s|r", baseHex, text or "") end

	local displayMode = db.displayMode or "both"
	local showFps = displayMode ~= "ping"
	local showPing = displayMode ~= "fps"

	-- Keep the hub driver cadence in sync with the current display mode
	local desiredInterval = db.fpsInterval
	if displayMode == "ping" then desiredInterval = db.pingInterval end
	if s and desiredInterval and s.interval ~= desiredInterval then s.interval = desiredInterval end

	local size = db.fontSize or 14
	s.snapshot.tooltip = getOptionsHint()

	local now = GetTime()

	local fpsValue
	if showFps then
		-- FPS sampling + smoothing
		local fpsNow = GetFramerate() or 0
		local fpsAvg = smoothFPS(fpsNow, db.fpsInterval or 0.25, db.fpsSmoothWindow or 0)
		fpsValue = floor(fpsAvg + 0.5)
	end

	if showPing then
		-- Ping sampling (gated)
		if (now - (lastPingUpdate or 0)) >= (db.pingInterval or 1.0) or not pingHome or not pingWorld then
			local _, _, home, world = GetNetStats()
			pingHome, pingWorld = home or 0, world or 0
			lastPingUpdate = now
		end
	end

	local needsUpdate = displayMode ~= lastDisplay
	if showFps and fpsValue ~= lastFps then needsUpdate = true end
	if showPing and ((pingHome or 0) ~= (lastHome or -1) or (pingWorld or 0) ~= (lastWorld or -1) or db.pingMode ~= lastPingMode) then needsUpdate = true end

	if needsUpdate then
		local pingText
		if showPing then
			if db.pingMode == "split" then
				local ph = pingHome or 0
				local pw = pingWorld or 0
				pingText = base("H ") .. format("|cff%s%d|r", pingColorHex(ph), ph) .. base(" / W ") .. format("|cff%s%d|r", pingColorHex(pw), pw) .. base(" ms")
			elseif db.pingMode == "split_vertical" then
				local ph = pingHome or 0
				local pw = pingWorld or 0
				local homeLabel = _G["HOME"] or "Home"
				local worldLabel = _G["WORLD"] or "World"
				pingText = base(homeLabel .. ": ")
					.. format("|cff%s%d|r", pingColorHex(ph), ph)
					.. base(" ms\n")
					.. base(worldLabel .. ": ")
					.. format("|cff%s%d|r", pingColorHex(pw), pw)
					.. base(" ms")
			elseif db.pingMode == "home" then
				local ph = pingHome or 0
				pingText = format("|cff%s%d|r", pingColorHex(ph), ph) .. base(" ms")
			elseif db.pingMode == "world" then
				local pw = pingWorld or 0
				pingText = format("|cff%s%d|r", pingColorHex(pw), pw) .. base(" ms")
			else
				local p = pingHome or 0
				if pingWorld and pingWorld > p then p = pingWorld end
				pingText = format("|cff%s%d|r", pingColorHex(p), p) .. base(" ms")
			end
		end

		local text
		if displayMode == "ping" then
			text = pingText or ""
		elseif displayMode == "fps" then
			text = base("FPS ") .. format("|cff%s%d|r", fpsColorHex(fpsValue or 0), fpsValue or 0)
		else
			local fpsText = base("FPS ") .. format("|cff%s%d|r", fpsColorHex(fpsValue or 0), fpsValue or 0)
			if pingText and pingText:find("\n", 1, true) then
				text = fpsText .. "\n" .. pingText
			else
				text = fpsText .. base(" | ") .. (pingText or "")
			end
		end

		s.snapshot.text = text
		lastDisplay = displayMode
		lastFps = showFps and fpsValue or nil
		lastHome = showPing and (pingHome or 0) or nil
		lastWorld = showPing and (pingWorld or 0) or nil
		lastPingMode = showPing and db.pingMode or nil
	end

	-- Only touch fontSize if actually changed
	if s.snapshot._fs ~= size then
		s.snapshot.fontSize = size
		s.snapshot._fs = size
	end
end

local provider = {
	id = "latency",
	version = 1,
	title = L["Latency"] or "Latency",
	poll = 0.25, -- default FPS cadence; kept in sync with db.fpsInterval at runtime
	update = updateLatency,
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
	OnMouseEnter = function(btn)
		ensureDB()
		local tip = GameTooltip
		tip:ClearLines()
		tip:SetOwner(btn, "ANCHOR_TOPLEFT")

		local displayMode = db.displayMode or "both"
		local showFps = displayMode ~= "ping"
		local showPing = displayMode ~= "fps"

		local lines = {}
		if showFps then
			local fps = floor((GetFramerate() or 0) + 0.5)
			-- Build FPS line using the global format, coloring only the value
			local fpsFmt = (MAINMENUBAR_FPS_LABEL or "Framerate: %.0f fps"):gsub("%%%.0f", "%%s")
			lines[#lines + 1] = fpsFmt:format(format("|cff%s%.0f|r", fpsColorHex(fps), fps))
		end

		if showPing then
			local _, _, home, world = GetNetStats()
			home = home or 0
			world = world or 0
			-- Build Latency block using the global format, coloring each value
			local latFmt = (MAINMENUBAR_LATENCY_LABEL or "Latency:\n%.0f ms (home)\n%.0f ms (world)")
			latFmt = latFmt:gsub("%%%.0f", "%%s")
			local latencyBlock = latFmt:format(format("|cff%s%.0f|r", pingColorHex(home), home), format("|cff%s%.0f|r", pingColorHex(world), world))
			for line in latencyBlock:gmatch("[^\n]+") do
				lines[#lines + 1] = line
			end
		end

		if lines[1] then
			tip:SetText(lines[1])
			for i = 2, #lines do
				tip:AddLine(lines[i])
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
