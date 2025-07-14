local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")

addon.Aura.unitFrame = {}
local AceGUI = addon.AceGUI

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

		local cd = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
		cd:SetAllPoints(iconFrame)
		cd:SetDrawEdge(false)
		cd:SetDrawBling(false)
		cd:SetSwipeColor(0, 0, 0, 0.6)
		iconFrame.cd = cd

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
		AuraUtil.ForEachAura(unit, "HELPFUL", nil, function(aura)
			local spellId = aura.spellId
			local data = tracker.spells and tracker.spells[spellId]
			if data then
				index = index + 1
				local iconFrame = ensureIcon(frame, tId, index)
				iconFrame.icon:SetTexture(aura.icon)
				iconFrame.expirationTime = aura.expirationTime
				if aura.expirationTime and aura.duration and aura.duration > 0 then
					iconFrame.cd:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
				else
					iconFrame.cd:Clear()
				end

				local showTime = data.showTimer
				if showTime == nil then showTime = addon.db.unitFrameAuraShowTime end
				iconFrame.showTimer = showTime
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
			if icon:IsShown() and icon.expirationTime and icon.showTimer then
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

	local needTicker = addon.db.unitFrameAuraShowTime
	if not needTicker then
		for _, tracker in pairs(addon.db.unitFrameAuraTrackers or {}) do
			for _, data in pairs(tracker.spells or {}) do
				if data.showTimer then
					needTicker = true
					break
				end
			end
			if needTicker then break end
		end
	end

	if needTicker then
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

-- Hook the global update function once; Blizzard calls this for every CompactUnitFrame
hooksecurefunc("CompactUnitFrame_UpdateAuras", function(frame)
	-- 'displayedUnit' is the unit token Blizzard uses; fall back to frame.unit
	local unit = frame and frame.displayedUnit or frame.unit
	if unit then UpdateTrackedBuffs(frame, unit) end
end)
manageTicker()

local function addSpell(tId, spellId)
	local info = C_Spell.GetSpellInfo(spellId)
	if not info then return end

	local tracker = addon.db.unitFrameAuraTrackers[tId]
	if not tracker then return end

	tracker.spells[spellId] = tracker.spells[spellId] or { name = info.name, icon = info.iconID }

	addon.db.unitFrameAuraOrder[tId] = addon.db.unitFrameAuraOrder[tId] or {}
	if not tContains(addon.db.unitFrameAuraOrder[tId], spellId) then table.insert(addon.db.unitFrameAuraOrder[tId], spellId) end
end

local function removeSpell(tId, spellId)
	local tracker = addon.db.unitFrameAuraTrackers[tId]
	if not tracker then return end
	tracker.spells[spellId] = nil
	if addon.db.unitFrameAuraOrder[tId] then
		for i, v in ipairs(addon.db.unitFrameAuraOrder[tId]) do
			if v == spellId then
				table.remove(addon.db.unitFrameAuraOrder[tId], i)
				break
			end
		end
	end
end

local refreshTree -- forward declaration

local function handleDragDrop(src, dst)
	if not src or not dst then return end

	local sT, _, sSpell = strsplit("\001", src)
	local dT, _, dSpell = strsplit("\001", dst)
	sT = tonumber(sT)
	dT = tonumber(dT)
	if not sSpell then return end
	sSpell = tonumber(sSpell)
	if dSpell then dSpell = tonumber(dSpell) end

	local srcTracker = addon.db.unitFrameAuraTrackers[sT]
	local dstTracker = addon.db.unitFrameAuraTrackers[dT]
	if not srcTracker or not dstTracker then return end

	local data = srcTracker.spells[sSpell]
	if not data then return end

	srcTracker.spells[sSpell] = nil
	addon.db.unitFrameAuraOrder[sT] = addon.db.unitFrameAuraOrder[sT] or {}
	for i, v in ipairs(addon.db.unitFrameAuraOrder[sT]) do
		if v == sSpell then
			table.remove(addon.db.unitFrameAuraOrder[sT], i)
			break
		end
	end

	dstTracker.spells[sSpell] = data
	addon.db.unitFrameAuraOrder[dT] = addon.db.unitFrameAuraOrder[dT] or {}
	local insertPos = #addon.db.unitFrameAuraOrder[dT] + 1
	if dSpell then
		for i, v in ipairs(addon.db.unitFrameAuraOrder[dT]) do
			if v == dSpell then
				insertPos = i
				break
			end
		end
	end
	table.insert(addon.db.unitFrameAuraOrder[dT], insertPos, sSpell)

	refreshTree(selectedTracker)
	RefreshAll()
end

local function getTrackerTree()
	local tree = {}
	for id, tracker in pairs(addon.db.unitFrameAuraTrackers or {}) do
		local node = { value = id, text = tracker.name or ("Tracker " .. id), children = {} }

		local spells = {}
		for sid, info in pairs(tracker.spells or {}) do
			local name = info.name or tostring(sid)
			table.insert(spells, { id = sid, name = name, icon = info.icon or (C_Spell.GetSpellInfo(sid) or {}).iconID })
		end

		addon.db.unitFrameAuraOrder[id] = addon.db.unitFrameAuraOrder[id] or {}
		local orderIndex = {}
		for idx, sid in ipairs(addon.db.unitFrameAuraOrder[id]) do
			orderIndex[sid] = idx
		end

		table.sort(spells, function(a, b)
			local ia = orderIndex[a.id] or math.huge
			local ib = orderIndex[b.id] or math.huge
			if ia ~= ib then return ia < ib end
			return a.name < b.name
		end)

		for _, info in ipairs(spells) do
			table.insert(node.children, { value = id .. "\001" .. info.id, text = info.name, icon = info.icon })
		end

		table.insert(tree, node)
	end

	table.sort(tree, function(a, b) return a.value < b.value end)
	table.insert(tree, { value = "ADD_TRACKER", text = "|cff00ff00+ " .. (L["AddTracker"] or "Add Tracker") })
	return tree
end

function refreshTree(selectValue)
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

       local function refresh()
               RefreshAll()
               refreshTree(id)
       end

	local edit = addon.functions.createEditboxAce(L["AddSpellID"], nil, function(self, _, text)
		local sid = tonumber(text)
		if sid then
			addSpell(id, sid)
			refresh()
		end
		self:SetText("")
	end)
	core:AddChild(edit)


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

local function buildSpellOptions(container, tId, spellId)
	local tracker = addon.db.unitFrameAuraTrackers[tId]
	local info = tracker and tracker.spells and tracker.spells[spellId]
	if not info then return end

	local core = addon.functions.createContainer("InlineGroup", "Flow")
	container:AddChild(core)

	local label = AceGUI:Create("Label")
	label:SetText((info.name or "") .. " (" .. spellId .. ")")
	core:AddChild(label)

	local cb = addon.functions.createCheckboxAce(L["ShowTimeRemaining"], info.showTimer == nil and addon.db.unitFrameAuraShowTime or info.showTimer, function(_, _, val)
		info.showTimer = val
		manageTicker()
		RefreshAll()
	end)
	core:AddChild(cb)

       local delBtn = addon.functions.createButtonAce(L["DeleteAura"], 150, function()
               local auraName = info.name or tostring(spellId)
               StaticPopupDialogs["EQOL_DELETE_UNITFRAME_AURA"] = StaticPopupDialogs["EQOL_DELETE_UNITFRAME_AURA"]
                       or {
                               text = L["DeleteAuraConfirm"],
                               button1 = YES,
                               button2 = CANCEL,
                               timeout = 0,
                               whileDead = true,
                               hideOnEscape = true,
                               preferredIndex = 3,
                       }
               StaticPopupDialogs["EQOL_DELETE_UNITFRAME_AURA"].OnAccept = function()
                       removeSpell(tId, spellId)
                       refreshTree(tId)
                       container:ReleaseChildren()
               end
               StaticPopup_Show("EQOL_DELETE_UNITFRAME_AURA", auraName)
       end)
       core:AddChild(delBtn)
end

function addon.Aura.functions.addUnitFrameAuraOptions(container)
	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	wrapper:SetFullHeight(true)
	container:AddChild(wrapper)

	trackerTreeGroup = AceGUI:Create("EQOL_DragTreeGroup")
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

		local tId, _, sId = strsplit("\001", value)
		tId = tonumber(tId)
		selectedTracker = tId
		addon.db.unitFrameAuraSelectedTracker = tId
		widget:ReleaseChildren()

		local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
		scroll:SetFullWidth(true)
		scroll:SetFullHeight(true)
		widget:AddChild(scroll)

		if sId then
			buildSpellOptions(scroll, tId, tonumber(sId))
		else
			buildTrackerOptions(scroll, tId)
		end
	end)
	trackerTreeGroup:SetCallback("OnDragDrop", function(_, _, src, dst) handleDragDrop(src, dst) end)

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
