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

local function eqolDbg(msg)
	if addon.db and addon.db.debugDungeonFilter then DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[EQOL:DF]|r " .. msg) end
end

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
local playerIsLust = LUST_CLASSES[addon.variables.unitClass]
local playerIsBR = BR_CLASSES[addon.variables.unitClass]

local RefreshVisibleEntries

local function AnyFilterActive()
	if pDb["partyFit"] then return true end
	if pDb["NoSameSpec"] and addon.variables.unitRole == "DAMAGER" then return true end
	if (not playerIsLust and pDb["bloodlustAvailable"]) or (playerIsLust and pDb["NoBloodlust"]) then return true end
	if not playerIsBR and pDb["battleResAvailable"] then return true end
	return false
end

local function EQOL_AddLFGEntries(owner, root, ctx)
	if not addon.db["mythicPlusEnableDungeonFilter"] then return end
	local panel = LFGListFrame.SearchPanel
	if panel.categoryID ~= 2 then return end
	root:CreateTitle("")

	root:CreateTitle(addonName)
	root:CreateCheckbox(L["Partyfit"], function() return pDb["partyFit"] end, function()
		pDb["partyFit"] = not pDb["partyFit"]
		RefreshVisibleEntries()
	end)
	if not playerIsLust then
		root:CreateCheckbox(L["BloodlustAvailable"], function() return pDb["bloodlustAvailable"] end, function()
			pDb["bloodlustAvailable"] = not pDb["bloodlustAvailable"]
			RefreshVisibleEntries()
		end)
	end
	if playerIsLust then root:CreateCheckbox(L["NoBloodlust"], function() return pDb["NoBloodlust"] end, function()
		pDb["NoBloodlust"] = not pDb["NoBloodlust"]
		RefreshVisibleEntries()
	end) end
	if not playerIsBR then
		root:CreateCheckbox(L["BattleResAvailable"], function() return pDb["battleResAvailable"] end, function()
			pDb["battleResAvailable"] = not pDb["battleResAvailable"]
			RefreshVisibleEntries()
		end)
	end
	if addon.variables.unitRole == "DAMAGER" then
		root:CreateCheckbox((L["NoSameSpec"]):format(addon.variables.unitSpecName .. " " .. select(1, UnitClass("player"))), function() return pDb["NoSameSpec"] end, function()
			pDb["NoSameSpec"] = not pDb["NoSameSpec"]
			RefreshVisibleEntries()
		end)
	end
end

if Menu and Menu.ModifyMenu then Menu.ModifyMenu("MENU_LFG_FRAME_SEARCH_FILTER", EQOL_AddLFGEntries) end

local function EntryPassesFilter(info)
	if info.numMembers == 5 then return false end

	local partyHasLust, partyHasBR = false, false
	for i = 1, GetNumGroupMembers() do
		local unit = (i == 1) and "player" or ("party" .. (i - 1))
		local _, class = UnitClass(unit)
		if class and LUST_CLASSES[class] then partyHasLust = true end
		if class and BR_CLASSES[class] then partyHasBR = true end
	end

	local NEED_SAMESPEC = (addon.variables.unitRole == "DAMAGER") and pDb["NoSameSpec"] or false
	local NEED_LUST = (pDb["bloodlustAvailable"] and not partyHasLust) or pDb["NoBloodlust"]
	local NEED_BR = pDb["battleResAvailable"] and not partyHasBR
	local NEED_ROLES = pDb["partyFit"]

	local groupTankCount, groupHealerCount, groupDPSCount = 0, 0, 0
	local hasLust, hasBR, hasSameSpec = false, false, false
	if NEED_SAMESPEC or NEED_LUST or NEED_BR or NEED_ROLES then
		for i = 1, info.numMembers do
			local m = C_LFGList.GetSearchResultPlayerInfo(info.searchResultID, i)
			if m then
				if NEED_ROLES and m.assignedRole then
					if m.assignedRole == "TANK" then
						groupTankCount = groupTankCount + 1
					elseif m.assignedRole == "HEALER" then
						groupHealerCount = groupHealerCount + 1
					elseif m.assignedRole == "DAMAGER" then
						groupDPSCount = groupDPSCount + 1
					end
				end
				if (NEED_LUST or NEED_BR) and m.classFilename then
					if NEED_LUST and LUST_CLASSES[m.classFilename] then hasLust = true end
					if NEED_BR and BR_CLASSES[m.classFilename] then hasBR = true end
				end
				if NEED_SAMESPEC and m.classFilename == addon.variables.unitClass and m.specName == addon.variables.unitSpecName then hasSameSpec = true end
			end
		end
	end

	if NEED_SAMESPEC and hasSameSpec then return false end
	if pDb["NoBloodlust"] and hasLust then return false end

	if NEED_ROLES then
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

		if needTanks > 1 or needHealers > 1 or needDPS > 3 then return false end
		if (1 - groupTankCount) < needTanks then return false end
		if (1 - groupHealerCount) < needHealers then return false end
		if (3 - groupDPSCount) < needDPS then return false end
		local freeSlots = 5 - info.numMembers
		if freeSlots < GetNumGroupMembers() then return false end
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

local function FilterResults(panel)
	if not addon.db["mythicPlusEnableDungeonFilter"] then return end
	if not panel or panel.categoryID ~= 2 then return end
	UpdateAppliedCache()
	if not AnyFilterActive() then
		-- make sure the panel uses the full unfiltered result list
		local results = select(2, C_LFGList.GetSearchResults())
		panel.results = results
		panel.totalResults = #results
		LFGListSearchPanel_UpdateResults(panel)
		return
	end
	local selectedID = (type(LFGListSearchPanel_GetSelectedResult) == "function" and LFGListSearchPanel_GetSelectedResult(panel)) or panel.selectedResultID or panel.selectedResult
	local results = select(2, C_LFGList.GetSearchResults())
	local filtered = {}
	for _, resultID in ipairs(results) do
		if appliedLookup[resultID] or (selectedID and resultID == selectedID) then
			table.insert(filtered, resultID)
		else
			local info = C_LFGList.GetSearchResultInfo(resultID)
			if info and EntryPassesFilter(info) then table.insert(filtered, resultID) end
		end
	end
	panel.results = filtered
	panel.totalResults = #filtered
	LFGListSearchPanel_UpdateResults(panel)
end

RefreshVisibleEntries = function()
	local panel = LFGListFrame.SearchPanel
	if panel then FilterResults(panel) end
end

local refreshScheduled = false
local function ScheduleRefresh()
	if refreshScheduled then return end
	refreshScheduled = true
	C_Timer.After(0.05, function()
		refreshScheduled = false
		RefreshVisibleEntries()
	end)
end

local function EventHandler(_, event)
	if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" or event == "LFG_LIST_APPLICATION_STATUS_UPDATED" or event == "LFG_LIST_APPLICANT_LIST_UPDATED" then
		UpdateAppliedCache()
		ScheduleRefresh()
	end
end

local filterFrame
local hooked = false

function addon.MythicPlus.functions.addDungeonFilter()
	if filterFrame then return end
	filterFrame = CreateFrame("Frame")
	UpdateAppliedCache()
	filterFrame:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
	filterFrame:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
	filterFrame:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED")
	filterFrame:SetScript("OnEvent", EventHandler)

	if not hooked then
		hooksecurefunc("LFGListSearchPanel_UpdateResultList", FilterResults)
		hooked = true
	end
	RefreshVisibleEntries()
end

function addon.MythicPlus.functions.removeDungeonFilter()
	if filterFrame then
		filterFrame:UnregisterAllEvents()
		filterFrame:SetScript("OnEvent", nil)
		filterFrame = nil
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
	RefreshVisibleEntries()
end)
