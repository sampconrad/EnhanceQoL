-- luacheck: globals EnhanceQoL UnitClass UnitExists UnitIsDeadOrGhost C_SpecializationInfo GetSpecializationInfo NORMAL_FONT_COLOR GAMEMENU_OPTIONS FONT_SIZE UIParent GetTime UnitOnTaxi UnitInVehicle UnitHasVehicleUI IsMounted C_SpellBook C_Timer
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream
local blinkStartAt
local blinkTicker
local blinkTickInterval
local DEFAULT_INTERVAL = 1.0
local DEFAULT_THROTTLE = 0.1
local BLINK_TICK = 1 / 30
local HOLD_FRACTION = 0.1
local MAX_HOLD = 0.12

local PET_SPECS = {
	[252] = true, -- Unholy DK
	[253] = true, -- Hunter: Beast Mastery
	[255] = true, -- Hunter: Survival
	[265] = true, -- Warlock: Affliction
	[266] = true, -- Warlock: Demonology
	[267] = true, -- Warlock: Destruction
}

local SPEC_MARKSMANSHIP = 254
local MARKS_PET_TALENT_ID = 1223323
local SPEC_FROST_MAGE = 64
local MAGE_PET_TALENT_ID = 31687

local PET_CLASSES = {
	HUNTER = true,
	WARLOCK = true,
}

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
	addon.db.datapanel.pettracker = addon.db.datapanel.pettracker or {}
	db = addon.db.datapanel.pettracker
	db.fontSize = db.fontSize or 14
	if not db.textColor then
		local r, g, b = 1, 0.82, 0
		if NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.GetRGB then
			r, g, b = NORMAL_FONT_COLOR:GetRGB()
		end
		db.textColor = { r = r, g = g, b = b }
	end
	if db.blinkEnabled == nil then db.blinkEnabled = false end
	db.blinkRate = db.blinkRate or 0.7
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
	frame:SetHeight(240)
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
	fontSize:SetSliderValues(8, 120, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(fontSize)

	local textColor = AceGUI:Create("ColorPicker")
	textColor:SetLabel(L["Text color"] or "Text color")
	textColor:SetColor(db.textColor.r, db.textColor.g, db.textColor.b)
	textColor:SetCallback("OnValueChanged", function(_, _, r, g, b)
		db.textColor = { r = r, g = g, b = b }
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(textColor)

	local blinkToggle = AceGUI:Create("CheckBox")
	blinkToggle:SetLabel(L["Blink"] or "Blink")
	blinkToggle:SetValue(db.blinkEnabled and true or false)
	frame:AddChild(blinkToggle)

	local blinkRate = AceGUI:Create("Slider")
	blinkRate:SetLabel(L["Blink rate (s)"] or "Blink rate (s)")
	blinkRate:SetSliderValues(0.2, 2.0, 0.05)
	blinkRate:SetValue(db.blinkRate)
	blinkRate:SetDisabled(not db.blinkEnabled)
	blinkRate:SetCallback("OnValueChanged", function(_, _, val)
		db.blinkRate = val
		blinkStartAt = nil
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(blinkRate)

	blinkToggle:SetCallback("OnValueChanged", function(_, _, val)
		db.blinkEnabled = val and true or false
		blinkRate:SetDisabled(not db.blinkEnabled)
		blinkStartAt = nil
		addon.DataHub:RequestUpdate(stream)
	end)

	frame.frame:Show()
end

local function isPetExpected()
	local specIndex = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization()
	if specIndex and GetSpecializationInfo then
		local specID = GetSpecializationInfo(specIndex)
		if specID == SPEC_FROST_MAGE then return C_SpellBook.IsSpellKnown(MAGE_PET_TALENT_ID) and true or false end
		if specID == SPEC_MARKSMANSHIP then return C_SpellBook.IsSpellKnown(MARKS_PET_TALENT_ID) and true or false end
		if PET_SPECS[specID] then return true end
		return false
	end

	local class = UnitClass and select(2, UnitClass("player"))
	if class == "MAGE" then return C_SpellBook.IsSpellKnown(MAGE_PET_TALENT_ID) and true or false end
	if class == "HUNTER" then return C_SpellBook.IsSpellKnown(MARKS_PET_TALENT_ID) and true or false end
	if class and PET_CLASSES[class] then return true end
	return false
end

local function hasActivePet()
	if not UnitExists or not UnitExists("pet") then return false end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost("pet") then return false end
	return true
end

local function isPetSuppressed()
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return true end
	if IsMounted and IsMounted() then return true end
	if UnitHasVehicleUI and UnitHasVehicleUI("player") then return true end
	if UnitInVehicle and UnitInVehicle("player") then return true end
	if UnitOnTaxi and UnitOnTaxi("player") then return true end
	if IsFlying and IsFlying() then return true end
	return false
end

local floor = math.floor
local format = string.format

local function colorToHex(color)
	local r = (color and color.r) or 1
	local g = (color and color.g) or 1
	local b = (color and color.b) or 1
	return format("%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

local function stopBlinkTicker()
	if blinkTicker then
		blinkTicker:Cancel()
		blinkTicker = nil
		blinkTickInterval = nil
	end
end

local function startBlinkTicker(stream, tick)
	if blinkTicker and blinkTickInterval == tick then return end
	stopBlinkTicker()
	blinkTickInterval = tick
	blinkTicker = C_Timer.NewTicker(tick, function()
		if not stream or not stream.subscribers or not next(stream.subscribers) then
			stopBlinkTicker()
			return
		end
		addon.DataHub:RequestUpdate(stream)
	end)
end

local function setStreamTiming(stream, interval, throttle)
	if stream.interval ~= interval then stream.interval = interval end
	if stream.throttle ~= throttle then stream.throttle = throttle end
end

local function resetBlink(stream)
	blinkStartAt = nil
	stopBlinkTicker()
	setStreamTiming(stream, DEFAULT_INTERVAL, DEFAULT_THROTTLE)
end

local function getBlinkInterval()
	local interval = tonumber(db.blinkRate) or 0.7
	if interval < 0.2 then interval = 0.2 end
	return interval
end

local function smoothstep(t)
	if t <= 0 then return 0 end
	if t >= 1 then return 1 end
	return t * t * (3 - 2 * t)
end

local function getBlinkAlpha(interval)
	local now = GetTime()
	if not blinkStartAt then blinkStartAt = now end
	local half = interval
	local period = half * 2
	local phase = (now - blinkStartAt) % period
	local hold = half * HOLD_FRACTION
	if hold > MAX_HOLD then hold = MAX_HOLD end
	local fade = half - hold
	if fade <= 0 then return (phase < half) and 1 or 0 end
	if phase < half then
		if phase < hold then return 1 end
		local t = (phase - hold) / fade
		return 1 - smoothstep(t)
	end
	phase = phase - half
	if phase < hold then return 0 end
	local t = (phase - hold) / fade
	return smoothstep(t)
end

local function update(stream)
	ensureDB()
	local editModeActive = addon.EditModeLib and addon.EditModeLib:IsInEditMode()
	local needsPet = editModeActive or isPetExpected()
	if not needsPet then
		stream.snapshot.hidden = true
		stream.snapshot.text = nil
		stream.snapshot.textAlpha = nil
		stream.snapshot.tooltip = nil
		resetBlink(stream)
		return
	end

	if not editModeActive and (hasActivePet() or isPetSuppressed()) then
		stream.snapshot.hidden = true
		stream.snapshot.text = nil
		stream.snapshot.textAlpha = nil
		stream.snapshot.tooltip = nil
		resetBlink(stream)
		return
	end

	stream.snapshot.hidden = nil
	stream.snapshot.fontSize = db.fontSize or 14
	stream.snapshot.tooltip = getOptionsHint()

	local alpha = 1
	if db.blinkEnabled and not editModeActive then
		local interval = getBlinkInterval()
		setStreamTiming(stream, DEFAULT_INTERVAL, 0)
		startBlinkTicker(stream, BLINK_TICK)
		alpha = getBlinkAlpha(interval)
	else
		resetBlink(stream)
	end

	local text = L["Pet Missing"] or "Pet Missing"
	local hex = colorToHex(db.textColor)
	stream.snapshot.text = format("|cff%s%s|r", hex, text)
	stream.snapshot.textAlpha = alpha
end

local provider = {
	id = "pettracker",
	version = 1,
	title = L["Pet Tracker"] or "Pet Tracker",
	classFilter = {
		DEATHKNIGHT = true,
		HUNTER = true,
		MAGE = true,
		WARLOCK = true,
	},
	poll = 1.0,
	update = update,
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
	events = {
		PLAYER_ENTERING_WORLD = function(s) addon.DataHub:RequestUpdate(s) end,
		ACTIVE_PLAYER_SPECIALIZATION_CHANGED = function(s) addon.DataHub:RequestUpdate(s) end,
		PLAYER_SPECIALIZATION_CHANGED = function(s, _, unit)
			if unit == nil or unit == "player" then addon.DataHub:RequestUpdate(s) end
		end,
		PLAYER_TALENT_UPDATE = function(s) addon.DataHub:RequestUpdate(s) end,
		SPELLS_CHANGED = function(s) addon.DataHub:RequestUpdate(s) end,
		TRAIT_CONFIG_UPDATED = function(s) addon.DataHub:RequestUpdate(s) end,
		PLAYER_MOUNT_DISPLAY_CHANGED = function(s) addon.DataHub:RequestUpdate(s) end,
	},
	eventsUnit = {
		player = {
			UNIT_PET = true,
		},
		pet = {
			UNIT_FLAGS = true,
		},
	},
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
