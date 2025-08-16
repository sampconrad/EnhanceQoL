local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_MythicPlus")

addon.functions.InitDBValue("mythicPlusDungeonFilters", {})
if addon.db["mythicPlusDungeonFilters"][UnitGUID("player")] == nil then addon.db["mythicPlusDungeonFilters"][UnitGUID("player")] = {} end

local pDb = addon.db["mythicPlusDungeonFilters"][UnitGUID("player")]

local appliedLookup = {}

local ACTIVE_STATUS = {
	applied = true,
	invited = true,
	inviteaccepted = true,
	pending = true,
}

local function UpdateAppliedCache()
	wipe(appliedLookup)
	for _, appID in ipairs(C_LFGList.GetApplications()) do
		local resultID, status = C_LFGList.GetApplicationInfo(appID)
		if resultID and ACTIVE_STATUS[status] then appliedLookup[resultID] = true end
	end
end

local LUST_CLASSES = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true }
local BR_CLASSES = { DRUID = true, WARLOCK = true, DEATHKNIGHT = true, PALADIN = true }

local SearchInfoCache = {}

local scanGen = 0 -- generation counter for pruning the cache
local toRemove = {} -- reusable array to avoid reallocations

local function CacheResultInfo(resultID)
	local info = C_LFGList.GetSearchResultInfo(resultID)
	if not info then
		SearchInfoCache[resultID] = nil
		return
	end
	local cached = SearchInfoCache[resultID] or {}
	cached.searchResultID = resultID
	cached.numMembers = info.numMembers
	-- Reset calculated extras for this generation
	cached.extraCalculated = nil
	cached.groupTankCount, cached.groupHealerCount, cached.groupDPSCount = nil, nil, nil
	cached.hasLust, cached.hasBR, cached.hasSameSpec = nil, nil, nil
	cached._gen = scanGen
	SearchInfoCache[resultID] = cached
end

local function EnsureExtraInfo(resultID, needRoles, needLust, needBR, needSameSpec)
	local info = SearchInfoCache[resultID]
	if not info then return nil end
	-- Wenn schon alles berechnet wurde, spar dir die Arbeit
	if info.extraCalculated then return info end

	local tank, healer, dps = 0, 0, 0
	local lust, br, sameSpec = false, false, false

	-- Wenn nichts benötigt wird, markiere als berechnet und beende
	if not (needRoles or needLust or needBR or needSameSpec) then
		info.extraCalculated = true
		return info
	end

	for i = 1, info.numMembers do
		local m = C_LFGList.GetSearchResultPlayerInfo(resultID, i)
		if m then
			if needRoles and m.assignedRole then
				if m.assignedRole == "TANK" then
					tank = tank + 1
				elseif m.assignedRole == "HEALER" then
					healer = healer + 1
				elseif m.assignedRole == "DAMAGER" then
					dps = dps + 1
				end
			end
			if (needLust or needBR) and m.classFilename then
				if needLust and LUST_CLASSES[m.classFilename] then lust = true end
				if needBR and BR_CLASSES[m.classFilename] then br = true end
			end
			if needSameSpec and m.classFilename == addon.variables.unitClass and m.specName == addon.variables.unitSpecName then sameSpec = true end
			-- Early exit: wenn alle angeforderten Infos schon feststehen
			local rolesDone = (not needRoles) or ((tank + healer + dps) >= info.numMembers)
			if rolesDone and (not needLust or lust) and (not needBR or br) and (not needSameSpec or sameSpec) then break end
		end
	end

	if needRoles then
		info.groupTankCount = tank
		info.groupHealerCount = healer
		info.groupDPSCount = dps
	end
	if needLust then info.hasLust = lust end
	if needBR then info.hasBR = br end
	if needSameSpec then info.hasSameSpec = sameSpec end
	-- Einmal berechnet reicht pro Generation
	info.extraCalculated = true
	return info
end

local playerIsLust = LUST_CLASSES[addon.variables.unitClass]
local playerIsBR = BR_CLASSES[addon.variables.unitClass]

local drop = LFGListFrame.SearchPanel.FilterButton
local originalSetupGen
local initialAllEntries = {}

local titleScore1 = LFGListFrame:CreateFontString(nil, "OVERLAY")
titleScore1:SetFont(addon.variables.defaultFont, 13, "OUTLINE")
titleScore1:SetPoint("TOPRIGHT", PVEFrameLeftInset, "TOPRIGHT", -10, -5)
titleScore1:Hide()

drop:HookScript("OnHide", function()
	originalSetupGen = nil
	titleScore1:Hide()
	wipe(SearchInfoCache)
	wipe(initialAllEntries)
end)

local function EQOL_AddLFGEntries(owner, root, ctx)
	if not addon.db["mythicPlusEnableDungeonFilter"] then return end
	local panel = LFGListFrame.SearchPanel
	if panel.categoryID ~= 2 then return end
	root:CreateTitle("")

	root:CreateTitle(addonName)
	root:CreateCheckbox(L["Partyfit"], function() return pDb["partyFit"] end, function() pDb["partyFit"] = not pDb["partyFit"] end)
	if not playerIsLust then root:CreateCheckbox(L["BloodlustAvailable"], function() return pDb["bloodlustAvailable"] end, function() pDb["bloodlustAvailable"] = not pDb["bloodlustAvailable"] end) end
	if playerIsLust then root:CreateCheckbox(L["NoBloodlust"], function() return pDb["NoBloodlust"] end, function() pDb["NoBloodlust"] = not pDb["NoBloodlust"] end) end
	if not playerIsBR then root:CreateCheckbox(L["BattleResAvailable"], function() return pDb["battleResAvailable"] end, function() pDb["battleResAvailable"] = not pDb["battleResAvailable"] end) end
	if addon.variables.unitRole == "DAMAGER" then
		root:CreateCheckbox(
			(L["NoSameSpec"]):format(addon.variables.unitSpecName .. " " .. select(1, UnitClass("player"))),
			function() return pDb["NoSameSpec"] end,
			function() pDb["NoSameSpec"] = not pDb["NoSameSpec"] end
		)
	end
end

if Menu and Menu.ModifyMenu then Menu.ModifyMenu("MENU_LFG_FRAME_SEARCH_FILTER", EQOL_AddLFGEntries) end

local function MyCustomFilter(info)
	if appliedLookup[info.searchResultID] then return true end
	if info.numMembers == 5 then return false end

	-- Party capabilities (für LUST/BR-Needs)
	local partyHasLust, partyHasBR = false, false
	for i = 1, GetNumGroupMembers() do
		local unit = (i == 1) and "player" or ("party" .. (i - 1))
		local _, class = UnitClass(unit)
		if class and LUST_CLASSES[class] then partyHasLust = true end
		if class and BR_CLASSES[class] then partyHasBR = true end
	end

	-- Welche Details brauchen wir wirklich?
	local NEED_SAMESPEC = (addon.variables.unitRole == "DAMAGER") and pDb["NoSameSpec"] or false
	local NEED_LUST = (pDb["bloodlustAvailable"] and not partyHasLust) or pDb["NoBloodlust"]
	local NEED_BR = pDb["battleResAvailable"] and not partyHasBR
	local NEED_ROLES = pDb["partyFit"]

	if NEED_SAMESPEC or NEED_LUST or NEED_BR or NEED_ROLES then info = EnsureExtraInfo(info.searchResultID, NEED_ROLES, NEED_LUST, NEED_BR, NEED_SAMESPEC) or info end

	local groupTankCount = info.groupTankCount or 0
	local groupHealerCount = info.groupHealerCount or 0
	local groupDPSCount = info.groupDPSCount or 0
	local hasLust = info.hasLust or false
	local hasBR = info.hasBR or false
	local hasSameSpec = info.hasSameSpec or false

	if NEED_SAMESPEC and hasSameSpec then return false end
	if pDb["NoBloodlust"] and hasLust then return false end

	if pDb["partyFit"] then
		-- Party-queue role availability check
		local needTanks, needHealers, needDPS = 0, 0, 0
		local partySize = GetNumGroupMembers()
		if partySize > 1 then
			for i = 1, partySize do
				local unit = (i == 1) and "player" or ("party" .. (i - 1))
				local role = UnitGroupRolesAssigned(unit)
				if role == "TANK" then
					needTanks = needTanks + 1
				elseif role == "HEALER" then
					needHealers = needHealers + 1
				elseif role == "DAMAGER" then
					needDPS = needDPS + 1
				end
			end
		else
			local role = addon.variables.unitRole
			if role == "TANK" then
				needTanks = needTanks + 1
			elseif role == "HEALER" then
				needHealers = needHealers + 1
			elseif role == "DAMAGER" then
				needDPS = needDPS + 1
			end
		end

		-- basic group requirement
		if needTanks > 1 or needHealers > 1 or needDPS > 3 then return false end

		if (1 - groupTankCount) < needTanks then return false end
		if (1 - groupHealerCount) < needHealers then return false end
		if (3 - groupDPSCount) < needDPS then return false end
		local freeSlots = 5 - info.numMembers
		if freeSlots < partySize then return false end
	end

	local missingProviders = 0
	if pDb["bloodlustAvailable"] then
		if not hasLust and not partyHasLust then
			if groupTankCount == 0 then missingProviders = missingProviders + 1 end
			missingProviders = missingProviders + 1
		end
	end
	if pDb["battleResAvailable"] then
		if not hasBR and not partyHasBR then missingProviders = missingProviders + 1 end
	end

	local slotsAfterJoin = 5 - info.numMembers - 1
	if slotsAfterJoin < missingProviders then return false end
	return true
end

local _eqolFiltering = false

local function ApplyEQOLFilters(isInitial)
	if _eqolFiltering then return end
	_eqolFiltering = true

	scanGen = scanGen + 1
	wipe(toRemove)

	-- Basic guards
	if not drop or not drop:IsVisible() then
		_eqolFiltering = false
		return
	end
	if not addon.db["mythicPlusEnableDungeonFilter"] then
		_eqolFiltering = false
		return
	end

	local panel = LFGListFrame and LFGListFrame.SearchPanel
	if not panel or panel.categoryID ~= 2 then
		titleScore1:Hide()
		_eqolFiltering = false
		return
	end
	local dp = panel.ScrollBox and panel.ScrollBox:GetDataProvider()
	if not dp then
		_eqolFiltering = false
		return
	end

	-- Fast exit if nothing to filter (mirrors the old conditions)
	local needFilter = false
	if pDb["bloodlustAvailable"] and not playerIsLust then needFilter = true end
	if pDb["NoBloodlust"] and playerIsLust then needFilter = true end
	if pDb["battleResAvailable"] and not playerIsBR then needFilter = true end
	if pDb["partyFit"] then needFilter = true end
	if pDb["NoSameSpec"] and addon.variables.unitRole == "DAMAGER" then needFilter = true end
	if not needFilter then
		titleScore1:Hide()
		_eqolFiltering = false
		return
	end

	-- On initial call, record the current set of entries
	if isInitial or not next(initialAllEntries) then
		wipe(initialAllEntries)
		for _, element in dp:EnumerateEntireRange() do
			local resultID = element.resultID or element.id
			if resultID then initialAllEntries[resultID] = true end
		end
	end

	-- Build removal list without mutating the provider during enumeration
	for _, element in dp:EnumerateEntireRange() do
		local resultID = element.resultID or element.id
		if resultID then
			if not SearchInfoCache[resultID] then
				CacheResultInfo(resultID)
			else
				SearchInfoCache[resultID]._gen = scanGen
				SearchInfoCache[resultID].extraCalculated = nil -- Details können sich geändert haben
			end
			local info = SearchInfoCache[resultID]
			if info and not MyCustomFilter(info) then toRemove[#toRemove + 1] = { elem = element, id = resultID } end
		end
	end

	local didRemove = (#toRemove > 0)
	for i = 1, #toRemove do
		local r = toRemove[i]
		dp:Remove(r.elem)
		initialAllEntries[r.id] = false
	end

	local removedCount = 0
	for _, v in pairs(initialAllEntries) do
		if v == false then removedCount = removedCount + 1 end
	end

	if removedCount > 0 then
		titleScore1:SetFormattedText((L["filteredTextEntries"]):format(removedCount))
		titleScore1:Show()
	else
		titleScore1:Hide()
	end

	-- Refresh the scrollbox nur wenn etwas entfernt wurde (be tolerant if constants differ)
	if didRemove and panel.ScrollBox and panel.ScrollBox.FullUpdate then
		if ScrollBoxConstants and ScrollBoxConstants.UpdateImmediately then
			panel.ScrollBox:FullUpdate(ScrollBoxConstants.UpdateImmediately)
		else
			panel.ScrollBox:FullUpdate()
		end
	end

	-- Prune alte Cache-Einträge, die in diesem Pass nicht gesehen wurden
	for id, c in pairs(SearchInfoCache) do
		if c._gen ~= scanGen then SearchInfoCache[id] = nil end
	end

	_eqolFiltering = false
end

-- Coalesce frequent events to a single filter pass
local _filterScheduled = false
local _lastInitial = false
local function ScheduleFilters(initial)
	if initial then _lastInitial = true end
	if _filterScheduled then return end
	_filterScheduled = true
	C_Timer.After(0, function()
		_filterScheduled = false
		ApplyEQOLFilters(_lastInitial)
		_lastInitial = false
	end)
end

function addon.MythicPlus.functions.addDungeonFilter()
	if LFGListFrame.SearchPanel.FilterButton:IsShown() then
		LFGListFrame:Hide()
		LFGListFrame:Show()
	end
	f = CreateFrame("Frame")
	UpdateAppliedCache()
	f:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
	f:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
	f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	f:RegisterEvent("LFG_LIST_AVAILABILITY_UPDATE")
	f:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
	f:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED")
	f:RegisterEvent("LFG_LIST_ENTRY_EXPIRED_TOO_MANY_PLAYERS")
	f:SetScript("OnEvent", function(_, event, ...)
		if not drop:IsVisible() then return end
		if not addon.db["mythicPlusEnableDungeonFilter"] then return end
		if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
			ScheduleFilters(true)
		elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
			local resultID = ...
			if resultID then CacheResultInfo(resultID) end
			ScheduleFilters(false)
		elseif event == "LFG_LIST_AVAILABILITY_UPDATE" then
			ScheduleFilters(true)
		elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
			if drop then drop.eqolWrapped = nil end
		elseif event == "LFG_LIST_APPLICANT_LIST_UPDATED" or event == "LFG_LIST_APPLICATION_STATUS_UPDATED" or event == "LFG_LIST_ENTRY_EXPIRED_TOO_MANY_PLAYERS" then
			UpdateAppliedCache()
			ScheduleFilters(false) -- filter next frame, aber ohne erneutes 'initial'; reduziert Flackern
		end
	end)
end

function addon.MythicPlus.functions.removeDungeonFilter()
	if f then
		f:UnregisterAllEvents()
		f:Hide()
		f:SetScript("OnEvent", nil)
		f = nil
		wipe(SearchInfoCache)
		titleScore1:Hide()
		if LFGListFrame.SearchPanel.FilterButton:IsShown() then
			LFGListFrame:Hide()
			LFGListFrame:Show()
		end
	end
end

LFGListFrame.SearchPanel.FilterButton.ResetButton:HookScript("OnClick", function()
	if not addon.db["mythicPlusEnableDungeonFilter"] then return end
	if not addon.db["mythicPlusEnableDungeonFilterClearReset"] then return end
	pDb["bloodlustAvailable"] = false
	pDb["NoBloodlust"] = false
	pDb["battleResAvailable"] = false
	pDb["partyFit"] = false
	pDb["NoSameSpec"] = false
end)
