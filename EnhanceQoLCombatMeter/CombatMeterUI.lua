local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local config = addon.db
local bars = {}
local barHeight = 20

local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
addon.CombatMeter.uiFrame = frame
frame:SetSize(220, barHeight)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:Hide()
local ticker

local dragHandle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
dragHandle:SetHeight(16)
dragHandle:SetPoint("TOPLEFT")
dragHandle:SetPoint("TOPRIGHT")
dragHandle:EnableMouse(true)
dragHandle:RegisterForDrag("LeftButton")
dragHandle:SetScript("OnDragStart", function(self) self:GetParent():StartMoving() end)
dragHandle:SetScript("OnDragStop", function(self)
	local parent = self:GetParent()
	parent:StopMovingOrSizing()
	local point, _, _, xOfs, yOfs = parent:GetPoint()
	config["combatMeterFramePoint"] = point
	config["combatMeterFrameX"] = xOfs
	config["combatMeterFrameY"] = yOfs
end)

dragHandle.text = dragHandle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
dragHandle.text:SetPoint("CENTER")
dragHandle.text:SetText("Combat Meter")

local function restorePosition()
	frame:ClearAllPoints()
	frame:SetPoint(config["combatMeterFramePoint"], UIParent, config["combatMeterFramePoint"], config["combatMeterFrameX"], config["combatMeterFrameY"])
end
restorePosition()

local function getBar(index)
	local bar = bars[index]
	if not bar then
		bar = CreateFrame("StatusBar", nil, frame, "BackdropTemplate")
		bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
		bar:SetHeight(barHeight)
		bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(16 + (index - 1) * barHeight))
		bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(16 + (index - 1) * barHeight))

		bar.icon = bar:CreateTexture(nil, "ARTWORK")
		bar.icon:SetSize(barHeight, barHeight)
		bar.icon:SetPoint("LEFT", bar, "LEFT")

		bar.name = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		bar.name:SetPoint("LEFT", bar.icon, "RIGHT", 2, 0)

		bar.healing = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		bar.damage = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		bar.damage:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
		bar.healing:SetPoint("RIGHT", bar.damage, "LEFT", -5, 0)

		bars[index] = bar
	end
	return bar
end

local function abbreviateName(name)
	name = name or ""
	name = name:match("^[^-]+") or name
	if #name > 12 then name = name:sub(1, 12) end
	return name
end

local function UpdateBars()
	if not (addon.CombatMeter.inCombat or config["combatMeterAlwaysShow"]) then
		frame:Hide()
		return
	end
	frame:Show()

	local duration
	if addon.CombatMeter.inCombat then
		duration = GetTime() - addon.CombatMeter.fightStartTime
	else
		duration = addon.CombatMeter.fightDuration
	end
	if duration <= 0 then duration = 1 end

	local groupGUID = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local guid = UnitGUID("raid" .. i)
			if guid then groupGUID[guid] = true end
		end
	else
		for i = 1, GetNumGroupMembers() do
			local guid = UnitGUID("party" .. i)
			if guid then groupGUID[guid] = true end
		end
		local playerGUID = UnitGUID("player")
		if playerGUID then groupGUID[playerGUID] = true end
	end

	local list = {}
	local maxValue = 0
	for guid, data in pairs(addon.CombatMeter.players) do
		if groupGUID[guid] then
			data.dps = data.damage / duration
			data.hps = data.healing / duration
			table.insert(list, data)
			local value = math.max(data.dps, data.hps)
			if value > maxValue then maxValue = value end
		end
	end
	if maxValue == 0 then maxValue = 1 end
	table.sort(list, function(a, b) return math.max(a.dps, a.hps) > math.max(b.dps, b.hps) end)

	for i, p in ipairs(list) do
		local bar = getBar(i)
		bar:Show()
		bar:SetMinMaxValues(0, maxValue)
		bar:SetValue(math.max(p.dps, p.hps))

		local _, _, class, _, _, classFile = GetPlayerInfoByGUID(p.guid)
		local color = RAID_CLASS_COLORS[classFile] or NORMAL_FONT_COLOR
		bar:SetStatusBarColor(color.r, color.g, color.b)
		bar.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
		local coords = CLASS_ICON_TCOORDS[classFile]
		if coords then bar.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) end

		bar.name:SetText(abbreviateName(p.name))
		bar.damage:SetText(BreakUpLargeNumbers(math.floor(p.dps)))
		bar.healing:SetText(BreakUpLargeNumbers(math.floor(p.hps)))
	end

	for i = #list + 1, #bars do
		if bars[i] then bars[i]:Hide() end
	end

	frame:SetHeight(16 + #list * barHeight)
end

frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("ENCOUNTER_START")
frame:RegisterEvent("ENCOUNTER_END")
frame:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_REGEN_DISABLED" or event == "ENCOUNTER_START" then
		if ticker then ticker:Cancel() end
		ticker = C_Timer.NewTicker(config["combatMeterUpdateRate"], UpdateBars)
		C_Timer.After(0, UpdateBars)
	else
		if ticker then
			ticker:Cancel()
			ticker = nil
		end
		C_Timer.After(0, UpdateBars)
	end
end)
