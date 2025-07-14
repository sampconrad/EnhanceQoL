local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")

addon.Aura.unitFrame = {}

local trackerTreeGroup
local selectedTracker = addon.db.unitFrameAuraSelectedTracker or 1

local ICON_SIZE = 20
local ICON_SPACING = 2
local timeTicker

local function ensureIcon(frame, tracker, index)
	frame.EQOLTrackedAura = frame.EQOLTrackedAura or {}
	frame.EQOLTrackedAura[tracker] = frame.EQOLTrackedAura[tracker] or {}
	local pool = frame.EQOLTrackedAura[tracker]
	if not pool[index] then
		local iconFrame = CreateFrame("Frame", nil, frame)
		iconFrame:SetSize(addon.db.unitFrameAuraIconSize or ICON_SIZE, addon.db.unitFrameAuraIconSize or ICON_SIZE)
		iconFrame:SetFrameLevel(frame:GetFrameLevel() + 10)
		local tex = iconFrame:CreateTexture(nil, "OVERLAY")
		tex:SetAllPoints(iconFrame)
		iconFrame.icon = tex
		local timer = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		timer:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
		timer:SetTextColor(1, 1, 1)
		timer:SetShadowOffset(1, -1)
		iconFrame.time = timer
		pool[index] = iconFrame
	end
	pool[index]:SetSize(addon.db.unitFrameAuraIconSize or ICON_SIZE, addon.db.unitFrameAuraIconSize or ICON_SIZE)
	return pool[index]
end

local function hideUnusedIcons(frame, tracker, used)
	if not frame.EQOLTrackedAura or not frame.EQOLTrackedAura[tracker] then return end
	for i = used + 1, #frame.EQOLTrackedAura[tracker] do
		frame.EQOLTrackedAura[tracker][i]:Hide()
	end
end

local function layoutIcons(frame, tracker, count)
	if not frame.EQOLTrackedAura or not frame.EQOLTrackedAura[tracker] then return end
	local size = addon.db.unitFrameAuraIconSize or ICON_SIZE
	local trackerData = addon.db.unitFrameAuraTrackers and addon.db.unitFrameAuraTrackers[tracker] or {}
	local anchor = trackerData.anchor or "CENTER"
	local dir = trackerData.direction or "RIGHT"
	local step = size + ICON_SPACING
	for i = 1, count do
		local icon = frame.EQOLTrackedAura[tracker][i]
		icon:ClearAllPoints()
		local offsetX, offsetY = 0, 0
		if anchor == "CENTER" then
			if dir == "LEFT" or dir == "RIGHT" then
				local mult = (i - (count + 1) / 2) * step
				if dir == "LEFT" then mult = -mult end
				offsetX = mult
			else
				local mult = (i - (count + 1) / 2) * step
				if dir == "DOWN" then mult = -mult end
				offsetY = mult
			end
		else
			local mult = (i - 1) * step
			if dir == "LEFT" then
				offsetX = -mult
			elseif dir == "RIGHT" then
				offsetX = mult
			elseif dir == "UP" then
				offsetY = mult
			elseif dir == "DOWN" then
				offsetY = -mult
			end
		end
		icon:SetPoint(anchor, frame, anchor, offsetX, offsetY)
	end
end

local function UpdateTrackedBuffs(frame, unit)
	if not frame or not unit or not addon.db.unitFrameAuraTrackers then return end

	for tId, tracker in pairs(addon.db.unitFrameAuraTrackers) do
		local index = 0
		local showTime = addon.db.unitFrameAuraShowTime
		AuraUtil.ForEachAura(unit, "HELPFUL", nil, function(aura)
			local spellId = aura.spellId
			if (tracker.spells and tracker.spells[spellId]) or addon.Aura.defaults.defensiveSpellIDs[spellId] then
				index = index + 1
				local iconFrame = ensureIcon(frame, tId, index)
				iconFrame.icon:SetTexture(aura.icon)
				iconFrame.expirationTime = aura.expirationTime
				if showTime and aura.expirationTime and aura.duration and aura.duration > 0 then
					local remain = math.floor(aura.expirationTime - GetTime())
					iconFrame.time:SetText(remain)
					iconFrame.time:Show()
				else
					iconFrame.time:Hide()
				end
				iconFrame:Show()
			end
		end, true)

		hideUnusedIcons(frame, tId, index)
		if index > 0 then layoutIcons(frame, tId, index) end
	end
end

addon.Aura.unitFrame.Update = UpdateTrackedBuffs

local function updateFrameTimes(frame)
	if not frame or not frame.EQOLTrackedAura then return end
	for _, trackerPool in pairs(frame.EQOLTrackedAura) do
		for _, icon in ipairs(trackerPool) do
			if icon:IsShown() and icon.expirationTime and addon.db.unitFrameAuraShowTime then
				local remain = math.floor(icon.expirationTime - GetTime())
				if remain > 0 then
					icon.time:SetText(remain)
					icon.time:Show()
				else
					icon.time:Hide()
				end
			elseif icon.time then
				icon.time:Hide()
			end
		end
	end
end

local function manageTicker()
	if timeTicker then
		timeTicker:Cancel()
		timeTicker = nil
	end
	if addon.db.unitFrameAuraShowTime then
		timeTicker = C_Timer.NewTicker(1, function()
			if CompactRaidFrameContainer and CompactRaidFrameContainer.GetFrames then
				for frame in CompactRaidFrameContainer:GetFrames() do
					updateFrameTimes(frame)
				end
			end
			for i = 1, 5 do
				local f = _G["CompactPartyFrameMember" .. i]
				if f then updateFrameTimes(f) end
			end
		end)
	end
end

local function RefreshAll()
	manageTicker()
	if CompactRaidFrameContainer and CompactRaidFrameContainer.GetFrames then
		for frame in CompactRaidFrameContainer:GetFrames() do
			UpdateTrackedBuffs(frame, frame.unit)
		end
	end
	for i = 1, 5 do
		local f = _G["CompactPartyFrameMember" .. i]
		if f then UpdateTrackedBuffs(f, f.unit) end
	end
end

addon.Aura.unitFrame.RefreshAll = RefreshAll

local function getMergedAuraIDs()
	local merged = {}
	for id, name in pairs(addon.Aura.defaults.defensiveSpellIDs or {}) do
		local info = C_Spell.GetSpellInfo(id)
		merged[id] = string.format("%s (%d)", info.name or name or "Spell", id)
	end
	for _, tracker in pairs(addon.db.unitFrameAuraTrackers or {}) do
		for id, val in pairs(tracker.spells or {}) do
			merged[id] = val
		end
	end
	return merged
end

-- Hook the global update function once; Blizzard calls this for every CompactUnitFrame
hooksecurefunc("CompactUnitFrame_UpdateAuras", function(frame)
	-- 'displayedUnit' is the unit token Blizzard uses; fall back to frame.unit
	local unit = frame and frame.displayedUnit or frame.unit
	if unit then UpdateTrackedBuffs(frame, unit) end
end)
manageTicker()

local function getTrackerTree()
	local tree = {}
	for id, tracker in pairs(addon.db.unitFrameAuraTrackers or {}) do
		table.insert(tree, { value = id, text = tracker.name or ("Tracker " .. id) })
	end
	table.sort(tree, function(a, b) return a.value < b.value end)
	table.insert(tree, { value = "ADD_TRACKER", text = "|cff00ff00+ " .. (L["AddTracker"] or "Add Tracker") })
	return tree
end

local function refreshTree(selectValue)
	if not trackerTreeGroup then return end
	trackerTreeGroup:SetTree(getTrackerTree())
	if selectValue then trackerTreeGroup:SelectByValue(tostring(selectValue)) end
end

local function buildTrackerOptions(container, id)
	local tracker = addon.db.unitFrameAuraTrackers[id]
	if not tracker then return end

	local core = addon.functions.createContainer("InlineGroup", "Flow")
	container:AddChild(core)

	local anchorDrop = addon.functions.createDropdownAce(
		L["AnchorPoint"],
		{
			TOPLEFT = "TOPLEFT",
			TOP = "TOP",
			TOPRIGHT = "TOPRIGHT",
			LEFT = "LEFT",
			CENTER = "CENTER",
			RIGHT = "RIGHT",
			BOTTOMLEFT = "BOTTOMLEFT",
			BOTTOM = "BOTTOM",
			BOTTOMRIGHT = "BOTTOMRIGHT",
		},
		nil,
		function(_, _, val)
			tracker.anchor = val
			RefreshAll()
		end
	)
	anchorDrop:SetValue(tracker.anchor or "CENTER")
	core:AddChild(anchorDrop)

	local dirDrop = addon.functions.createDropdownAce(L["GrowthDirection"], { LEFT = "LEFT", RIGHT = "RIGHT", UP = "UP", DOWN = "DOWN" }, nil, function(_, _, val)
		tracker.direction = val
		RefreshAll()
	end)
	dirDrop:SetValue(tracker.direction or "RIGHT")
	core:AddChild(dirDrop)

	local drop
	local function refresh()
		local list, order = addon.functions.prepareListForDropdown(tracker.spells)
		drop:SetList(list, order)
		drop:SetValue(nil)
		RefreshAll()
	end

	local edit = addon.functions.createEditboxAce(L["AddSpellID"], nil, function(self, _, text)
		local id = tonumber(text)
		if id then
			local info = C_Spell.GetSpellInfo(id)
			if info then
				tracker.spells[id] = string.format("%s (%d)", info.name, id)
				refresh()
			end
		end
		self:SetText("")
	end)
	core:AddChild(edit)

	local list, order = addon.functions.prepareListForDropdown(tracker.spells)
	drop = addon.functions.createDropdownAce(L["TrackedAuras"], list, order, nil)
	core:AddChild(drop)

	local btn = addon.functions.createButtonAce(REMOVE, 100, function()
		local sel = drop:GetValue()
		if sel then
			tracker.spells[sel] = nil
			refresh()
		end
	end)
	core:AddChild(btn)

	local nameEdit = addon.functions.createEditboxAce(L["TrackerName"], tracker.name, function(_, _, text)
		if text ~= "" then tracker.name = text end
		refreshTree(id)
	end)
	core:AddChild(nameEdit)

	local delBtn = addon.functions.createButtonAce(L["DeleteTracker"], 150, function()
		addon.db.unitFrameAuraTrackers[id] = nil
		selectedTracker = next(addon.db.unitFrameAuraTrackers) or 1
		addon.db.unitFrameAuraSelectedTracker = selectedTracker
		refreshTree(selectedTracker)
		RefreshAll()
	end)
	core:AddChild(delBtn)
end

function addon.Aura.functions.addUnitFrameAuraOptions(container)
	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	wrapper:SetFullHeight(true)
	container:AddChild(wrapper)

	trackerTreeGroup = AceGUI:Create("TreeGroup")
	trackerTreeGroup:SetFullHeight(true)
	trackerTreeGroup:SetFullWidth(true)
	trackerTreeGroup:SetTreeWidth(200, true)
	trackerTreeGroup:SetTree(getTrackerTree())
	trackerTreeGroup:SetCallback("OnGroupSelected", function(widget, _, value)
		if value == "ADD_TRACKER" then
			local newId = (#addon.db.unitFrameAuraTrackers or 0) + 1
			addon.db.unitFrameAuraTrackers[newId] = { name = "Tracker " .. newId, anchor = "CENTER", direction = "RIGHT", spells = {} }
			selectedTracker = newId
			addon.db.unitFrameAuraSelectedTracker = newId
			refreshTree(newId)
			return
		end

		local id = tonumber(value)
		selectedTracker = id
		addon.db.unitFrameAuraSelectedTracker = id
		widget:ReleaseChildren()

		local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
		scroll:SetFullWidth(true)
		scroll:SetFullHeight(true)
		widget:AddChild(scroll)
		buildTrackerOptions(scroll, id)
	end)

	wrapper:AddChild(trackerTreeGroup)

	local global = addon.functions.createContainer("InlineGroup", "Flow")
	wrapper:AddChild(global)

	local sizeSlider = addon.functions.createSliderAce(
		L["buffTrackerIconSizeHeadline"] .. ": " .. (addon.db.unitFrameAuraIconSize or ICON_SIZE),
		addon.db.unitFrameAuraIconSize or ICON_SIZE,
		8,
		64,
		1,
		function(self, _, val)
			addon.db.unitFrameAuraIconSize = val
			self:SetLabel(L["buffTrackerIconSizeHeadline"] .. ": " .. val)
			RefreshAll()
		end
	)
	global:AddChild(sizeSlider)

	local timeCB = addon.functions.createCheckboxAce(L["ShowTimeRemaining"], addon.db.unitFrameAuraShowTime, function(_, _, val)
		addon.db.unitFrameAuraShowTime = val
		RefreshAll()
	end)
	global:AddChild(timeCB)

	trackerTreeGroup:SelectByValue(tostring(selectedTracker))
end
