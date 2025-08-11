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
local specIcons = {}

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

		bar.name:SetTextColor(1, 1, 1)
		bar.damage:SetTextColor(1, 1, 1)
		bar.healing:SetTextColor(1, 1, 1)

		local size = config["combatMeterFontSize"]
		bar.name:SetFont(addon.variables.defaultFont, size, "OUTLINE")
		bar.damage:SetFont(addon.variables.defaultFont, size, "OUTLINE")
		bar.healing:SetFont(addon.variables.defaultFont, size, "OUTLINE")

		bars[index] = bar
	end
	return bar
end

local function setFontSize(size)
	for _, bar in ipairs(bars) do
		bar.name:SetFont(addon.variables.defaultFont, size, "OUTLINE")
		bar.damage:SetFont(addon.variables.defaultFont, size, "OUTLINE")
		bar.healing:SetFont(addon.variables.defaultFont, size, "OUTLINE")
	end
end
addon.CombatMeter.functions.setFontSize = setFontSize

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

	local groupUnits = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local unit = "raid" .. i
			local guid = UnitGUID(unit)
			if guid then groupUnits[guid] = unit end
		end
	else
		for i = 1, GetNumGroupMembers() do
			local unit = "party" .. i
			local guid = UnitGUID(unit)
			if guid then groupUnits[guid] = unit end
		end
		local playerGUID = UnitGUID("player")
		if playerGUID then groupUnits[playerGUID] = "player" end
	end

	local list = {}
	local maxValue = 0
	for guid, data in pairs(addon.CombatMeter.players) do
		local unit = groupUnits[guid]
		if unit then
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

		local unit = groupUnits[p.guid]
		local icon = specIcons[p.guid]
		if not icon and unit then
			local specID = GetInspectSpecialization(unit)
			if specID and specID > 0 then
				icon = select(4, GetSpecializationInfoByID(specID))
				specIcons[p.guid] = icon
			end
		end
		bar.icon:SetTexture(icon)

		bar.name:SetText(abbreviateName(p.name))
		bar.damage:SetText(BreakUpLargeNumbers(math.floor(p.dps)))
		bar.healing:SetText(BreakUpLargeNumbers(math.floor(p.hps)))
	end

	for i = #list + 1, #bars do
		if bars[i] then bars[i]:Hide() end
	end

	frame:SetHeight(16 + #list * barHeight)
end

addon.CombatMeter.functions.UpdateBars = UpdateBars

frame:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_REGEN_DISABLED" or event == "ENCOUNTER_START" then
		if ticker then ticker:Cancel() end
		ticker = C_Timer.NewTicker(config["combatMeterUpdateRate"], UpdateBars)
		addon.CombatMeter.ticker = ticker
		C_Timer.After(0, UpdateBars)
	else
		if ticker then
			ticker:Cancel()
			ticker = nil
			addon.CombatMeter.ticker = nil
		end
		C_Timer.After(0, UpdateBars)
	end
end)

function addon.CombatMeter.functions.setUpdateRate(rate)
	if ticker then
		ticker:Cancel()
		ticker = C_Timer.NewTicker(rate, UpdateBars)
		addon.CombatMeter.ticker = ticker
	end
end

addon.CombatMeter.functions.toggle(addon.db["combatMeterEnabled"])
