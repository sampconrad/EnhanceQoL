local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_CombatMeter")

local config = addon.db
local TEXTURE_PATH = "Interface\\AddOns\\EnhanceQoLCombatMeter\\Texture\\"
local DEFAULT_BAR_WIDTH = 210
local DEFAULT_BAR_HEIGHT = 25
local DEFAULT_MAX_BARS = 8
local DEFAULT_OVERLAY_TEXTURE = TEXTURE_PATH .. "eqol_overlay_gradient_512x64.tga"
local BLENDS = { ADD = true, BLEND = true, MOD = true }
local specIcons = {}
local pendingInspect = {}
local groupFrames = {}
local groupUnitsCached = {}
local shortNameCache = {}
local rawNameCache = {}
local ticker
local baseTickerRate = config["combatMeterUpdateRate"] or 0.3
local tickerRate = baseTickerRate
local lastMaxValue = 0
local lastTotalValue = 0
local stableTicks = 0
local STABLE_TICK_THRESHOLD = 10
local BACKOFF_FACTOR = 2
local MAX_TICKER_RATE = 1.0
local EPSILON = 0.01
local tinsert, tsort = table.insert, table.sort

local POW10 = { [0] = 1 }
for i = 1, 6 do
	POW10[i] = POW10[i - 1] * 10
end

local function sortByValueDesc(a, b) return a.value > b.value end

local function scheduleInspectRetry(guid, unit)
	C_Timer.After(1, function()
		if pendingInspect[guid] and type(unit) == "string" and (unit == "player" or unit:match("^raid%d+$") or unit:match("^party%d+$")) and CanInspect(unit) then NotifyInspect(unit) end
	end)
end

local function tableSize(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

-- font helpers ---------------------------------------------------------------
local function getOutlineFlags()
	local f = (config and config["combatMeterFontOutline"]) or "OUTLINE"
	if f == "NONE" or f == "" then return "" end
	if f == "THIN" then return "OUTLINE" end -- compat alias
	return f -- OUTLINE / THICKOUTLINE / MONOCHROME / combos
end

local NUMBER_FONT_PATH = (NumberFontNormal and select(1, NumberFontNormal:GetFont()))
	or (addon.variables and addon.variables.numberFont)
	or (addon.variables and addon.variables.defaultFont)
	or "Fonts\\FRIZQT__.TTF"

-- fixed number columns to avoid jitter
local COL_TOTAL_W = 0
local COL_RATE_W = 0
local COL_GAP = (config and config["combatMeterColumnGap"]) or 0

local widthMeasure
local function updateColumnWidths(size)
	widthMeasure = widthMeasure or UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	widthMeasure:Hide()
	widthMeasure:SetFont(NUMBER_FONT_PATH, size, getOutlineFlags())
	widthMeasure:SetText("888.88m")
	local w = math.ceil(widthMeasure:GetStringWidth() + 2)
	COL_TOTAL_W = w
	COL_RATE_W = w
end

local metricNames = {
	dps = L["DPS"],
	damageOverall = L["Damage Overall"],
	healingPerFight = L["Healing Per Fight"],
	healingOverall = L["Healing Overall"],
}

local function applyBarTexture(bar)
	if not bar then return end
	local tex = config["combatMeterBarTexture"] or (TEXTURE_PATH .. "eqol_base_flat_8x8.tga")
	local overlayTex = config["combatMeterOverlayTexture"] or DEFAULT_OVERLAY_TEXTURE
	local useOverlay = config["combatMeterUseOverlay"]
	local rounded = config["combatMeterRoundedCorners"]
	local a = tonumber(config["combatMeterOverlayAlpha"]) or 0.28
	if a < 0 then
		a = 0
	elseif a > 1 then
		a = 1
	end
	local blend = config["combatMeterOverlayBlend"]
	if not BLENDS[blend] then blend = "ADD" end

	local want = bar._skin or {}
	local need = want.tex ~= tex or want.overlay ~= useOverlay or want.ovtex ~= overlayTex or want.blend ~= blend or want.alpha ~= a or want.rounded ~= rounded
	if not need then return end

	bar:SetStatusBarTexture(tex)

	if rounded then
		if not bar.mask then
			bar.mask = bar:CreateMaskTexture()
			bar.mask:SetTexture(TEXTURE_PATH .. "eqol_mask_rounded_8px_64x64.tga")
			bar.mask:SetAllPoints(bar)
		end
		bar.mask:Show()
		if not bar._maskApplied then
			local sb = bar:GetStatusBarTexture()
			if sb then sb:AddMaskTexture(bar.mask) end
			if bar.overlay then bar.overlay:AddMaskTexture(bar.mask) end
			bar._maskApplied = true
		end
	elseif bar.mask then
		if bar._maskApplied then
			local sb = bar:GetStatusBarTexture()
			if sb then sb:RemoveMaskTexture(bar.mask) end
			if bar.overlay then bar.overlay:RemoveMaskTexture(bar.mask) end
			bar._maskApplied = nil
		end
		bar.mask:Hide()
		bar.mask = nil
	end

	if useOverlay then
		if not bar.overlay then
			bar.overlay = bar:CreateTexture(nil, "ARTWORK")
			bar.overlay:SetAllPoints(bar)
			bar.overlay:SetDrawLayer("ARTWORK", 1)
		end
		bar.overlay:SetTexture(overlayTex)
		bar.overlay:SetBlendMode(blend)
		bar.overlay:SetVertexColor(1, 1, 1, a)
		if bar.mask and bar._maskApplied then bar.overlay:AddMaskTexture(bar.mask) end
		bar.overlay:Show()
	elseif bar.overlay then
		if bar.mask and bar._maskApplied then bar.overlay:RemoveMaskTexture(bar.mask) end
		bar.overlay:Hide()
		bar.overlay = nil
	end

	bar._skin = {
		tex = tex,
		overlay = useOverlay,
		ovtex = overlayTex,
		blend = blend,
		alpha = a,
		rounded = rounded,
	}
end

local function applyBarTextures()
	for _, frame in ipairs(groupFrames) do
		for _, bar in ipairs(frame.bars) do
			applyBarTexture(bar)
		end
	end
end
addon.CombatMeter.functions.applyBarTextures = applyBarTextures

local function abbreviateName(name)
	name = name or ""
	name = name:match("^[^-]+") or name
	local maxLen = (config and config["combatMeterNameLength"]) or 12
	if #name > maxLen then name = name:sub(1, maxLen) end
	return name
end

local function abbreviateNumber(n, decimals, trimZeros)
	decimals = decimals or 2
	n = tonumber(n) or 0
	local sign = n < 0 and "-" or ""
	n = math.abs(n)

	local val, suf
	if n >= 1e9 then
		val, suf = n / 1e9, "b"
	elseif n >= 1e6 then
		val, suf = n / 1e6, "m"
	elseif n >= 1e3 then
		val, suf = n / 1e3, "k"
	else
		return sign .. tostring(math.floor(n + 0.5))
	end

	local pow = POW10[decimals] or 10 ^ decimals
	val = math.floor(val * pow + 0.5) / pow

	-- Carry: 999.995k -> 1.00m, etc.
	if val >= 1000 and suf ~= "b" then
		val = val / 1000
		suf = (suf == "k") and "m" or "b"
		val = math.floor(val * pow + 0.5) / pow
	end

	local s = string.format("%." .. decimals .. "f", val)
	if trimZeros then
		s = s:gsub("(%..-)0+$", "%1"):gsub("%.$", "") -- .00 -> "", .50 -> .5
	end
	return sign .. s .. suf
end

-- Uses modern menu API (Dragonflight+/11.x).
local function OpenHistoryMenu(owner)
	local hist = addon.db["combatMeterHistory"] or {}
	MenuUtil.CreateContextMenu(owner, function(_, root)
		if #hist == 0 then
			root:CreateTitle(L["No History"])
			return
		end
		for i = #hist, 1, -1 do
			local fight = hist[i]
			local text = string.format("%d. %ds", i, math.floor((fight and fight.duration) or 0))
			local idx = i -- capture loop variable for the closure
			root:CreateButton(text, function()
				if addon.CombatMeter and addon.CombatMeter.functions and addon.CombatMeter.functions.loadHistory then addon.CombatMeter.functions.loadHistory(idx) end
			end)
		end
	end)
end

-- Opens a metric selection menu for a group frame
local function OpenMetricMenu(owner, frame)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		for metric, name in pairs(metricNames) do
			root:CreateButton(name, function()
				frame.metric = metric
				frame.groupConfig.type = metric
				if frame.dragHandle and frame.dragHandle.text then frame.dragHandle.text:SetText(metricNames[metric]) end
				if addon.CombatMeter and addon.CombatMeter.functions and addon.CombatMeter.functions.UpdateBars then addon.CombatMeter.functions.UpdateBars() end
			end)
		end
	end)
end
local function createGroupFrame(groupConfig)
	local barHeight = groupConfig.barHeight or DEFAULT_BAR_HEIGHT
	local barWidth = groupConfig.barWidth or DEFAULT_BAR_WIDTH
	local frameWidth = barWidth + barHeight + 2

	local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	frame:SetSize(frameWidth, barHeight)
	frame._h = barHeight
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:Hide()
	frame.bars = {}
	frame.list = frame.list or {}
	frame.top = frame.top or {}
	frame.metric = groupConfig.type
	frame.groupConfig = groupConfig

	local dragHandle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	dragHandle:SetHeight(16)
	dragHandle:SetPoint("TOPLEFT")
	dragHandle:SetPoint("TOPRIGHT")
	dragHandle:EnableMouse(true)
	dragHandle:RegisterForDrag("LeftButton")
	-- Drag outline (ghost border showing the maximum footprint based on Max Bars)
	local dragOutline = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	dragOutline:EnableMouse(false)
	dragOutline:SetFrameStrata("TOOLTIP")
	dragOutline:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	dragOutline:SetBackdropColor(1, 1, 1, 0.04)
	dragOutline:SetBackdropBorderColor(1, 0.82, 0, 0.9) -- golden-ish
	dragOutline:Hide()

	local function refreshDragOutline()
		local maxBars = groupConfig.maxBars or DEFAULT_MAX_BARS
		local maxHeight = 16 + maxBars * barHeight
		dragOutline:ClearAllPoints()
		dragOutline:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
		dragOutline:SetSize(frameWidth, maxHeight)
	end

	function frame:ShowOutline()
		refreshDragOutline()
		dragOutline:Show()
	end

	function frame:HideOutline() dragOutline:Hide() end

	dragHandle:SetScript("OnDragStart", function(self)
		local parent = self:GetParent()
		addon.CombatMeter.functions.showOutlinesAll()
		parent:StartMoving()
	end)

	dragHandle:SetScript("OnDragStop", function(self)
		local parent = self:GetParent()
		parent:StopMovingOrSizing()
		addon.CombatMeter.functions.hideOutlinesAll()
		local point, _, _, xOfs, yOfs = parent:GetPoint()
		groupConfig.point = point
		groupConfig.x = xOfs
		groupConfig.y = yOfs
	end)

	local resetButton = CreateFrame("Button", nil, dragHandle)
	resetButton:SetSize(16, 16)
	resetButton:SetPoint("RIGHT", dragHandle, "RIGHT", 0, 0)

	-- Icon texture (place eqol_reset_32.tga in Interface\\AddOns\\EnhanceQoLCombatMeter\\Texture\\)
	resetButton.icon = resetButton:CreateTexture(nil, "ARTWORK")
	resetButton.icon:SetAllPoints(resetButton)
	resetButton.icon:SetTexture(TEXTURE_PATH .. "eqol_reset_64.tga")
	resetButton.icon:SetTexCoord(0, 1, 0, 1)

	-- Simple highlight when hovering
	local hl = resetButton:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(resetButton)
	hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	hl:SetBlendMode("ADD")

	-- Visual feedback when pressing
	resetButton:SetScript("OnMouseDown", function(self)
		if self.icon then self.icon:SetVertexColor(0.9, 0.9, 0.9) end
	end)
	resetButton:SetScript("OnMouseUp", function(self)
		if self.icon then self.icon:SetVertexColor(1, 1, 1) end
	end)

	-- Tooltip
	resetButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L["Reset"])
		GameTooltip:Show()
	end)
	resetButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Click handler (unchanged)
	resetButton:SetScript("OnClick", function()
		SlashCmdList["EQOLCM"]("reset")
		if addon.CombatMeter.functions.UpdateBars then addon.CombatMeter.functions.UpdateBars() end
	end)

	local historyButton = CreateFrame("Button", nil, dragHandle)
	historyButton:SetSize(16, 16)
	historyButton:SetPoint("RIGHT", resetButton, "LEFT", -2, 0)

	historyButton.icon = historyButton:CreateTexture(nil, "ARTWORK")
	historyButton.icon:SetAllPoints(historyButton)
	historyButton.icon:SetTexture(TEXTURE_PATH .. "eqol_history_64.tga")
	-- Tint the history icon in gold
	historyButton.icon:SetVertexColor(1, 0.82, 0)

	local hhl = historyButton:CreateTexture(nil, "HIGHLIGHT")
	hhl:SetAllPoints(historyButton)
	hhl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	hhl:SetBlendMode("ADD")

	historyButton:SetScript("OnMouseDown", function(self)
		if self.icon then self.icon:SetVertexColor(0.9, 0.74, 0) end
	end)
	historyButton:SetScript("OnMouseUp", function(self)
		if self.icon then self.icon:SetVertexColor(1, 0.82, 0) end
	end)

	historyButton:SetScript("OnClick", function(self) OpenHistoryMenu(self) end)

	local metricButton = CreateFrame("Button", nil, dragHandle)
	metricButton:SetSize(16, 16)
	metricButton:SetPoint("RIGHT", historyButton, "LEFT", -2, 1)

	metricButton.icon = metricButton:CreateTexture(nil, "ARTWORK")
	metricButton.icon:SetAllPoints(metricButton)
	metricButton.icon:SetTexture(TEXTURE_PATH .. "eqol_metric_64.tga")
	-- Tint the metric icon in gold
	metricButton.icon:SetVertexColor(1, 0.82, 0)

	local mhl = metricButton:CreateTexture(nil, "HIGHLIGHT")
	mhl:SetAllPoints(metricButton)
	mhl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	mhl:SetBlendMode("ADD")

	metricButton:SetScript("OnMouseDown", function(self)
		if self.icon then self.icon:SetVertexColor(0.9, 0.74, 0) end
	end)
	metricButton:SetScript("OnMouseUp", function(self)
		if self.icon then self.icon:SetVertexColor(1, 0.82, 0) end
	end)

	metricButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L["Change Metric"])
		GameTooltip:Show()
	end)
	metricButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	metricButton:SetScript("OnClick", function(self) OpenMetricMenu(self, frame) end)

	dragHandle.text = dragHandle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	dragHandle.text:SetPoint("LEFT", dragHandle, "LEFT", 2, 0)
	dragHandle.text:SetPoint("RIGHT", metricButton, "LEFT", -2, 0)
	dragHandle.text:SetJustifyH("CENTER")
	dragHandle.text:SetText(metricNames[groupConfig.type] or L["Combat Meter"])
	frame.dragHandle = dragHandle

	local function restorePosition()
		frame:ClearAllPoints()
		frame:SetPoint(groupConfig.point or "CENTER", UIParent, groupConfig.point or "CENTER", groupConfig.x or 0, groupConfig.y or 0)
	end
	restorePosition()

	local function getBar(index)
		local bar = frame.bars[index]
		if not bar then
			bar = CreateFrame("StatusBar", nil, frame, "BackdropTemplate")

			bar:SetHeight(barHeight)
			bar:SetPoint("TOPLEFT", frame, "TOPLEFT", barHeight + 2, -(16 + (index - 1) * barHeight))
			bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(16 + (index - 1) * barHeight))

			bar.icon = bar:CreateTexture(nil, "ARTWORK")
			bar.icon:SetSize(barHeight, barHeight)
			bar.icon:SetPoint("RIGHT", bar, "LEFT", -2, 0)

			-- Right-side fixed columns to keep numbers steady (no jitter)
			bar.rate = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			bar.rate:SetJustifyH("RIGHT")
			bar.rate:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
			bar.rate:SetSize(COL_RATE_W, barHeight)

			bar.total = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			bar.total:SetJustifyH("RIGHT")
			bar.total:SetPoint("RIGHT", bar.rate, "LEFT", -COL_GAP, 0)
			bar.total:SetSize(COL_TOTAL_W, barHeight)

			-- Single-value field (used for non-rate metrics); spans both columns
			bar.value = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			bar.value:SetJustifyH("RIGHT")
			bar.value:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
			bar.value:SetSize(COL_TOTAL_W + COL_GAP + COL_RATE_W, barHeight)
			bar.value:Hide()

			-- Name between icon and numeric columns
			bar.name = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			bar.name:SetPoint("LEFT", bar, "LEFT", 2, 0)
			bar.name:SetPoint("RIGHT", bar.total, "LEFT", -6, 0)
			bar.name:SetJustifyH("LEFT")
			bar.name:SetWordWrap(false)
			bar.name:SetMaxLines(1)

			bar.name:SetTextColor(1, 1, 1)
			bar.value:SetTextColor(1, 1, 1)
			bar.total:SetTextColor(1, 1, 1)
			bar.rate:SetTextColor(1, 1, 1)

			local size = config["combatMeterFontSize"]
			local outline = getOutlineFlags()
			bar.name:SetFont(addon.variables.defaultFont, size, outline)
			bar.value:SetFont(NUMBER_FONT_PATH, size, outline)
			bar.total:SetFont(NUMBER_FONT_PATH, size, outline)
			bar.rate:SetFont(NUMBER_FONT_PATH, size, outline)

			applyBarTexture(bar)

			frame.bars[index] = bar
		end
		return bar
	end

	frame.getBar = getBar

	function frame:updateColumnWidths()
		for _, bar in ipairs(self.bars) do
			if bar.rate then bar.rate:SetWidth(COL_RATE_W) end
			if bar.total then bar.total:SetWidth(COL_TOTAL_W) end
			if bar.value then bar.value:SetWidth(COL_TOTAL_W + COL_GAP + COL_RATE_W) end
		end
	end

	function frame:setFontSize(size)
		local outline = getOutlineFlags()
		for _, bar in ipairs(self.bars) do
			bar.name:SetFont(addon.variables.defaultFont, size, outline)
			bar.value:SetFont(NUMBER_FONT_PATH, size, outline)
			if bar.total then bar.total:SetFont(NUMBER_FONT_PATH, size, outline) end
			if bar.rate then bar.rate:SetFont(NUMBER_FONT_PATH, size, outline) end
		end
	end

	function frame:RefreshDragOutline()
		if dragOutline:IsShown() then refreshDragOutline() end
	end

	function frame:Update(groupUnits)
		if not (addon.CombatMeter.inCombat or config["combatMeterAlwaysShow"] or self.metric == "damageOverall" or self.metric == "healingOverall") then
			self:Hide()
			return
		end
		self:Show()
		self.list = self.list or {}
		self.top = self.top or {}
		local list = self.list
		local top = self.top
		wipe(list)
		wipe(top)
		local maxValue = 0
		if self.metric == "damageOverall" or self.metric == "healingOverall" then
			for guid, p in pairs(addon.CombatMeter.overallPlayers) do
				-- Skip players without recorded time to avoid blank bars
				if groupUnits[guid] and p.time and p.time > 0 then
					local total = (self.metric == "damageOverall") and (p.damage or 0) or (p.healing or 0)
					local value = total / p.time
					tinsert(list, { guid = guid, name = p.name, value = value, total = total, class = p.class })
					if value > maxValue then maxValue = value end
				end
			end
		else
			local duration
			if addon.CombatMeter.inCombat then
				duration = GetTime() - addon.CombatMeter.fightStartTime
			else
				duration = addon.CombatMeter.fightDuration
			end
			if duration <= 0 then duration = 1 end
			for guid, data in pairs(addon.CombatMeter.players) do
				if groupUnits[guid] then
					local value
					local total
					if self.metric == "dps" then
						value = data.damage / duration
						total = data.damage
					else
						value = data.healing / duration
						total = data.healing
					end
					tinsert(list, { guid = guid, name = data.name, value = value, total = total, class = data.class })
					if value > maxValue then maxValue = value end
				end
			end
		end

		if maxValue == 0 then maxValue = 1 end
		local maxBars = groupConfig.maxBars or DEFAULT_MAX_BARS
		local groupCount = tableSize(groupUnits)
		if groupCount > 20 and #list > maxBars then
			for _, entry in ipairs(list) do
				local inserted = false
				for i = 1, #top do
					if entry.value > top[i].value then
						tinsert(top, i, entry)
						inserted = true
						break
					end
				end
				if not inserted and #top < maxBars then top[#top + 1] = entry end
				if #top > maxBars then top[#top] = nil end
			end
			list = top
		else
			tsort(list, sortByValueDesc)
		end
		local playerGUID = UnitGUID("player")
		if groupConfig.alwaysShowSelf then
			local found = false
			for _, entry in ipairs(list) do
				if entry.guid == playerGUID then
					found = true
					break
				end
			end
			if not found then
				local name = UnitName("player")
				local value, total
				local class
				if self.metric == "damageOverall" or self.metric == "healingOverall" then
					local p = addon.CombatMeter.overallPlayers[playerGUID]
					if p and p.time and p.time > 0 then
						total = (self.metric == "damageOverall") and (p.damage or 0) or (p.healing or 0)
						value = total / p.time
						class = p.class
					end
				else
					local duration
					if addon.CombatMeter.inCombat then
						duration = GetTime() - addon.CombatMeter.fightStartTime
					else
						duration = addon.CombatMeter.fightDuration
					end
					if duration <= 0 then duration = 1 end
					local data = addon.CombatMeter.players[playerGUID]
					if data then
						if self.metric == "dps" then
							total = data.damage
							value = data.damage / duration
						else
							total = data.healing
							value = data.healing / duration
						end
						class = data.class
					else
						total = 0
						value = 0
					end
				end
				if value then
					if value > maxValue then maxValue = value end
					tinsert(list, { guid = playerGUID, name = name, value = value, total = total, class = class })
				end
			end
			if #list > maxBars then
				local playerIndex
				for i, entry in ipairs(list) do
					if entry.guid == playerGUID then
						playerIndex = i
						break
					end
				end
				if playerIndex and playerIndex > maxBars then
					list[playerIndex], list[maxBars] = list[maxBars], list[playerIndex]
				end
				while #list > maxBars do
					table.remove(list)
				end
			end
		end

		local displayCount = math.min(#list, maxBars)
		local totalValue = 0
		for i = 1, displayCount do
			local p = list[i]
			totalValue = totalValue + (p.value or 0)
			local bar = getBar(i)
			bar:Show()
			if bar._max ~= maxValue then
				bar:SetMinMaxValues(0, maxValue)
				bar._max = maxValue
			end
			bar:SetValue(p.value)

			local class = p.class or ""
			if bar._class ~= class then
				local color = RAID_CLASS_COLORS[class] or NORMAL_FONT_COLOR
				bar:SetStatusBarColor(color.r, color.g, color.b)
				bar._class = class
			end

			local unit = groupUnits[p.guid]
			local icon = specIcons[p.guid]
			if not icon and unit then
				if unit == "player" then
					local specIndex = C_SpecializationInfo.GetSpecialization()
					if specIndex then
						icon = select(4, C_SpecializationInfo.GetSpecializationInfo(specIndex))
						specIcons[p.guid] = icon
					end
				elseif type(unit) == "string" and (unit == "player" or unit:match("^raid%d+$") or unit:match("^party%d+$")) and CanInspect(unit) and not pendingInspect[p.guid] then
					NotifyInspect(unit)
					pendingInspect[p.guid] = true
					scheduleInspectRetry(p.guid, unit)
				end
			end
			if bar._icon ~= icon then
				bar.icon:SetTexture(icon)
				bar._icon = icon
			end

			local rawName = rawNameCache[p.guid]
			local shortName = shortNameCache[p.guid]
			if p.name ~= rawName then
				shortName = abbreviateName(p.name)
				shortNameCache[p.guid] = shortName
				rawNameCache[p.guid] = p.name
			end
			bar.name:SetText(shortName)
			if p.total and (self.metric == "dps" or self.metric == "healingPerFight" or self.metric == "damageOverall" or self.metric == "healingOverall") then
				local decimals = (p.value >= 1e6) and 2 or 0
				local rate = abbreviateNumber(p.value, decimals)
				local total = abbreviateNumber(p.total)
				bar.value:Hide()
				bar.total:Show()
				bar.rate:Show()
				bar.total:SetText(total)
				bar.rate:SetText(rate)
				-- ensure name anchors to total when dual columns are used
				if bar.nameRightAnchorTarget ~= bar.total then
					bar.name:ClearAllPoints()
					bar.name:SetPoint("LEFT", bar, "LEFT", 2, 0)
					bar.name:SetPoint("RIGHT", bar.total, "LEFT", -6, 0)
					bar.nameRightAnchorTarget = bar.total
				end
			else
				bar.total:Hide()
				bar.rate:Hide()
				bar.value:Show()
				bar.value:SetText(abbreviateNumber(p.value))
				if bar.nameRightAnchorTarget ~= bar.value then
					bar.name:ClearAllPoints()
					bar.name:SetPoint("LEFT", bar, "LEFT", 2, 0)
					bar.name:SetPoint("RIGHT", bar.value, "LEFT", -6, 0)
					bar.nameRightAnchorTarget = bar.value
				end
			end
		end

		for i = displayCount + 1, #self.bars do
			self.bars[i]:Hide()
		end

		local newHeight = 16 + displayCount * barHeight
		if self._h ~= newHeight then
			self:SetHeight(newHeight)
			self._h = newHeight
		end
		return maxValue, totalValue
	end

	return frame
end

local function setFontSize(size)
	updateColumnWidths(size)
	for _, frame in ipairs(groupFrames) do
		frame:updateColumnWidths()
		frame:setFontSize(size)
	end
end
addon.CombatMeter.functions.setFontSize = setFontSize

local function buildGroupUnits()
	wipe(groupUnitsCached)
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local unit = "raid" .. i
			local guid = UnitGUID(unit)
			if guid then groupUnitsCached[guid] = unit end
		end
	else
		for i = 1, GetNumGroupMembers() do
			local unit = "party" .. i
			local guid = UnitGUID(unit)
			if guid then groupUnitsCached[guid] = unit end
		end
		local playerGUID = UnitGUID("player")
		if playerGUID then groupUnitsCached[playerGUID] = "player" end
	end
	return groupUnitsCached
end

local function UpdateAllFrames()
	if #groupFrames == 0 then return end
	local units = groupUnitsCached
	if addon.CombatMeter.historySelection then
		units = addon.CombatMeter.historyUnits or units
	elseif not next(units) then
		buildGroupUnits()
		units = groupUnitsCached
	end
	local maxValue = 0
	local totalValue = 0
	for _, frame in ipairs(groupFrames) do
		local frameMax, frameTotal = frame:Update(units)
		if frameMax and frameMax > maxValue then maxValue = frameMax end
		if frameTotal then totalValue = totalValue + frameTotal end
	end
	if math.abs(maxValue - lastMaxValue) < EPSILON and math.abs(totalValue - lastTotalValue) < EPSILON then
		stableTicks = stableTicks + 1
		if stableTicks >= STABLE_TICK_THRESHOLD and tickerRate < MAX_TICKER_RATE then
			tickerRate = math.min(tickerRate * BACKOFF_FACTOR, MAX_TICKER_RATE)
			if ticker then
				ticker:Cancel()
				ticker = C_Timer.NewTicker(tickerRate, UpdateAllFrames)
				addon.CombatMeter.ticker = ticker
			end
			stableTicks = 0
		end
	else
		stableTicks = 0
		if tickerRate ~= baseTickerRate then
			tickerRate = baseTickerRate
			if ticker then
				ticker:Cancel()
				ticker = C_Timer.NewTicker(tickerRate, UpdateAllFrames)
				addon.CombatMeter.ticker = ticker
			end
		end
	end
	lastMaxValue = maxValue
	lastTotalValue = totalValue
end
addon.CombatMeter.functions.UpdateBars = UpdateAllFrames

local function showOutlinesAll()
	for _, frame in ipairs(groupFrames) do
		if frame:IsShown() and frame.ShowOutline then frame:ShowOutline() end
	end
end

local function hideOutlinesAll()
	for _, frame in ipairs(groupFrames) do
		if frame.HideOutline then frame:HideOutline() end
	end
end

addon.CombatMeter.functions.showOutlinesAll = showOutlinesAll
addon.CombatMeter.functions.hideOutlinesAll = hideOutlinesAll

local controller = CreateFrame("Frame")
addon.CombatMeter.uiFrame = controller

controller:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_REGEN_DISABLED" or event == "ENCOUNTER_START" then
		if ticker then ticker:Cancel() end
		buildGroupUnits()
		local hz = (tableSize(groupUnitsCached) > 20) and 0.3 or config["combatMeterUpdateRate"]
		baseTickerRate = hz
		tickerRate = hz
		stableTicks = 0
		lastMaxValue = 0
		lastTotalValue = 0
		ticker = C_Timer.NewTicker(hz, UpdateAllFrames)
		addon.CombatMeter.ticker = ticker
		C_Timer.After(0, UpdateAllFrames)
	elseif event == "INSPECT_READY" then
		local guid = ...
		if not next(groupUnitsCached) then buildGroupUnits() end
		local unit = groupUnitsCached[guid]
		if unit then
			local specID = GetInspectSpecialization(unit)
			if specID and specID > 0 then specIcons[guid] = select(4, GetSpecializationInfoByID(specID)) end
			pendingInspect[guid] = nil
			UpdateAllFrames()
		end
	elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
		local unit = ...
		local guid = UnitGUID(unit)
		if guid then
			specIcons[guid] = nil
			pendingInspect[guid] = nil
			if unit == "player" then
				local specIndex = GetSpecialization()
				if specIndex then specIcons[guid] = select(4, GetSpecializationInfo(specIndex)) end
				UpdateAllFrames()
			else
				if type(unit) == "string" and (unit == "player" or unit:match("^raid%d+$") or unit:match("^party%d+$")) and CanInspect(unit) and not pendingInspect[guid] then
					NotifyInspect(unit)
					pendingInspect[guid] = true
					scheduleInspectRetry(guid, unit)
				end
			end
		end
	elseif event == "GROUP_ROSTER_UPDATE" then
		buildGroupUnits()
		for guid in pairs(specIcons) do
			if not groupUnitsCached[guid] then specIcons[guid] = nil end
		end
		for guid in pairs(pendingInspect) do
			if not groupUnitsCached[guid] then pendingInspect[guid] = nil end
		end
		wipe(shortNameCache)
		wipe(rawNameCache)
		C_Timer.After(0, UpdateAllFrames)
	else
		if ticker then
			ticker:Cancel()
			ticker = nil
			addon.CombatMeter.ticker = nil
		end
		C_Timer.After(0, UpdateAllFrames)
	end
end)

function addon.CombatMeter.functions.setUpdateRate(rate)
	if ticker then
		ticker:Cancel()
		local hz = (tableSize(groupUnitsCached) > 20) and 0.3 or rate
		baseTickerRate = hz
		tickerRate = hz
		stableTicks = 0
		lastMaxValue = 0
		lastTotalValue = 0
		ticker = C_Timer.NewTicker(hz, UpdateAllFrames)
		addon.CombatMeter.ticker = ticker
	end
end

local function rebuildGroups()
	updateColumnWidths(config["combatMeterFontSize"])
	for _, frame in ipairs(groupFrames) do
		frame:Hide()
	end
	wipe(groupFrames)
	for _, cfg in ipairs(config["combatMeterGroups"]) do
		if not cfg.barWidth then cfg.barWidth = DEFAULT_BAR_WIDTH end
		if not cfg.barHeight then cfg.barHeight = DEFAULT_BAR_HEIGHT end
		if not cfg.maxBars then cfg.maxBars = DEFAULT_MAX_BARS end
		local frame = createGroupFrame(cfg)
		tinsert(groupFrames, frame)
	end
	UpdateAllFrames()
end
addon.CombatMeter.functions.rebuildGroups = rebuildGroups

local function hideAllFrames()
	for _, frame in ipairs(groupFrames) do
		frame:Hide()
	end
	wipe(specIcons)
	wipe(pendingInspect)
end
addon.CombatMeter.functions.hideAllFrames = hideAllFrames

rebuildGroups()
addon.CombatMeter.functions.toggle(addon.db["combatMeterEnabled"])
