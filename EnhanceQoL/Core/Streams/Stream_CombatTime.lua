-- luacheck: globals EnhanceQoL UIParent GAMEMENU_OPTIONS FONT_SIZE C_Timer InCombatLockdown IsEncounterInProgress UnitExists UnitAffectingCombat
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream

local combatActive = false
local bossActive = false
local combatStart
local bossStart
local bossElapsed = 0

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
	addon.db.datapanel.combatTime = addon.db.datapanel.combatTime or {}
	db = addon.db.datapanel.combatTime
	db.fontSize = db.fontSize or 14
	if db.showBoss == nil then db.showBoss = true end
	if db.showLabels == nil then db.showLabels = true end
	if db.stack == nil then db.stack = false end
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
	frame:SetHeight(220)
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

	local showBoss = AceGUI:Create("CheckBox")
	showBoss:SetLabel(L["combatTimeShowBoss"] or "Show boss timer")
	showBoss:SetValue(db.showBoss and true or false)
	showBoss:SetCallback("OnValueChanged", function(_, _, val)
		db.showBoss = val and true or false
		scheduleUpdate()
	end)
	frame:AddChild(showBoss)

	local showLabels = AceGUI:Create("CheckBox")
	showLabels:SetLabel(L["combatTimeShowLabels"] or "Show labels")
	showLabels:SetValue(db.showLabels and true or false)
	showLabels:SetCallback("OnValueChanged", function(_, _, val)
		db.showLabels = val and true or false
		scheduleUpdate()
	end)
	frame:AddChild(showLabels)

	local stacked = AceGUI:Create("CheckBox")
	stacked:SetLabel(L["combatTimeStacked"] or "Stack timers")
	stacked:SetValue(db.stack and true or false)
	stacked:SetCallback("OnValueChanged", function(_, _, val)
		db.stack = val and true or false
		scheduleUpdate()
	end)
	frame:AddChild(stacked)

	frame.frame:Show()
end

local floor = math.floor
local format = string.format
local max = math.max
local GetTime = GetTime

local function formatDuration(seconds)
	seconds = max(0, floor((seconds or 0) + 0.5))
	local h = floor(seconds / 3600)
	local m = floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then return format("%d:%02d:%02d", h, m, s) end
	return format("%d:%02d", m, s)
end

local function isBossInCombat()
	for i = 1, 5 do
		local unit = "boss" .. i
		if UnitExists(unit) and UnitAffectingCombat(unit) then return true end
	end
	return false
end

local function startCombat()
	combatActive = true
	combatStart = GetTime()
	bossActive = false
	bossStart = nil
	bossElapsed = 0
end

local function stopCombat()
	combatActive = false
	combatStart = nil
	bossActive = false
	bossStart = nil
	bossElapsed = 0
end

local function startBoss()
	if not combatActive then
		combatActive = true
		combatStart = GetTime()
	end
	bossActive = true
	bossStart = GetTime()
	bossElapsed = 0
end

local function stopBoss()
	if bossActive and bossStart then bossElapsed = GetTime() - bossStart end
	bossActive = false
	bossStart = nil
end

local function refreshBossState()
	if not combatActive then return end
	local encounterInProgress = IsEncounterInProgress and IsEncounterInProgress() or false
	local bossInCombat = isBossInCombat()
	if bossActive then
		if not encounterInProgress and not bossInCombat then stopBoss() end
	else
		if encounterInProgress or bossInCombat then startBoss() end
	end
end

local function updateCombatTime(s)
	s = s or stream
	ensureDB()

	local editModeActive = addon.EditModeLib and addon.EditModeLib:IsInEditMode()
	local inCombat = InCombatLockdown and InCombatLockdown() or false
	if inCombat and not combatActive then
		startCombat()
	elseif not inCombat and combatActive then
		stopCombat()
	end

	refreshBossState()

	local combatElapsed = 0
	if combatActive and combatStart then combatElapsed = GetTime() - combatStart end

	local bossElapsedNow = bossElapsed or 0
	if bossActive and bossStart then bossElapsedNow = GetTime() - bossStart end

	local showBossLine = (db.showBoss and bossActive) or editModeActive
	if editModeActive then
		if not combatActive then combatElapsed = 123 end
		if not bossActive then bossElapsedNow = 47 end
	end

	local combatText = formatDuration(combatElapsed)
	local bossText = formatDuration(bossElapsedNow)

	local combatLabel = L["Combat time"] or "Combat time"
	local bossLabel = L["Boss time"] or "Boss time"

	local text
	if db.showLabels then
		text = combatLabel .. ": " .. combatText
		if showBossLine then
			if db.stack then
				text = text .. "\n" .. bossLabel .. ": " .. bossText
			else
				text = text .. " / " .. bossLabel .. ": " .. bossText
			end
		end
	else
		text = combatText
		if showBossLine then
			if db.stack then
				text = text .. "\n" .. bossText
			else
				text = text .. " / " .. bossText
			end
		end
	end

	s.snapshot.text = text
	local tooltip = combatLabel .. ": " .. combatText
	if showBossLine then tooltip = tooltip .. "\n" .. bossLabel .. ": " .. bossText end
	local optionsHint = getOptionsHint()
	if optionsHint then tooltip = tooltip .. "\n" .. optionsHint end
	s.snapshot.tooltip = tooltip
	s.snapshot.fontSize = db.fontSize or 14
end

local provider = {
	id = "combat_time",
	version = 1,
	title = L["Combat time"] or "Combat time",
	poll = 1,
	update = updateCombatTime,
	events = {
		PLAYER_REGEN_DISABLED = function(s)
			if not combatActive then startCombat() end
			refreshBossState()
			addon.DataHub:RequestUpdate(s)
		end,
		PLAYER_REGEN_ENABLED = function(s)
			if combatActive then stopCombat() end
			addon.DataHub:RequestUpdate(s)
		end,
		ENCOUNTER_START = function(s)
			startBoss()
			addon.DataHub:RequestUpdate(s)
		end,
		ENCOUNTER_END = function(s)
			stopBoss()
			addon.DataHub:RequestUpdate(s)
		end,
		INSTANCE_ENCOUNTER_ENGAGE_UNIT = function(s)
			refreshBossState()
			addon.DataHub:RequestUpdate(s)
		end,
		PLAYER_ENTERING_WORLD = function(s)
			stopCombat()
			if InCombatLockdown and InCombatLockdown() then
				startCombat()
				refreshBossState()
			end
			addon.DataHub:RequestUpdate(s)
		end,
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
