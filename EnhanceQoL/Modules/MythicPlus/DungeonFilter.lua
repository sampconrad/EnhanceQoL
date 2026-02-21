local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_MythicPlus")

addon.MythicPlus = addon.MythicPlus or {}
addon.MythicPlus.functions = addon.MythicPlus.functions or {}
addon.MythicPlus.variables = addon.MythicPlus.variables or {}

local pDb

local function eqolDbg(msg)
	if addon.db and addon.db.debugDungeonFilter then DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[EQOL:DF]|r " .. msg) end
end

local LUST_CLASSES = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true }
local BR_CLASSES = { DRUID = true, WARLOCK = true, DEATHKNIGHT = true, PALADIN = true }
local playerIsLust
local playerIsBR

local function ensureDungeonFilterDB()
	if not addon.db then return end
	addon.db["mythicPlusDungeonFilters"] = addon.db["mythicPlusDungeonFilters"] or {}
	local guid = UnitGUID("player")
	if guid then
		if addon.db["mythicPlusDungeonFilters"][guid] == nil then addon.db["mythicPlusDungeonFilters"][guid] = {} end
		pDb = addon.db["mythicPlusDungeonFilters"][guid]
	end
end

local function refreshPlayerFlags()
	local _, class = UnitClass("player")
	playerIsLust = class and LUST_CLASSES[class] or false
	playerIsBR = class and BR_CLASSES[class] or false
end

local RefreshVisibleEntries

local function AnyFilterActive()
	if not pDb then return false end
	if pDb["partyFit"] then return true end
	if pDb["NoSameSpec"] and addon.variables.unitRole == "DAMAGER" then return true end
	if (not playerIsLust and pDb["bloodlustAvailable"]) or (playerIsLust and pDb["NoBloodlust"]) then return true end
	if not playerIsBR and pDb["battleResAvailable"] then return true end
	return false
end

local function EQOL_AddLFGEntries(owner, root, ctx)
	if not pDb then return end
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

-- === Visual highlight for entries that fail our filter (PGF-style, taint-safe) ===
local function EQOL_SetTextGrey(widget, grey)
	if not widget or not widget.SetTextColor then return end
	-- Cache original color once
	if not widget._eqolOrigColor then
		local r, g, b, a = 1, 1, 1, 1
		if widget.GetTextColor then
			r, g, b, a = widget:GetTextColor()
		end
		widget._eqolOrigColor = { r, g, b, a }
	end
	if grey then
		widget:SetTextColor(0.6, 0.6, 0.6, 1)
	else
		local c = widget._eqolOrigColor
		if c then widget:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
	end
end

local function EQOL_RestoreEntryVisuals(entry)
	if entry._eqolOrigAlpha then entry:SetAlpha(entry._eqolOrigAlpha) end
	-- Try common fontstrings on the entry; restore if we changed them before
	local labels = { "Name", "ActivityName", "Members", "Comment", "VoiceChat", "LeaderName", "ListingName" }
	for _, k in ipairs(labels) do
		local w = entry[k]
		if w and w._eqolOrigColor then EQOL_SetTextGrey(w, false) end
	end
end

local function EQOL_ApplyEntryVisuals(entry, dim, skipGrey)
	-- Alpha grey-out is robust across templates; also grey some labels if present
	if not entry._eqolOrigAlpha then entry._eqolOrigAlpha = entry:GetAlpha() or 1 end
	entry:SetAlpha(dim and 0.45 or entry._eqolOrigAlpha)
	if skipGrey then return end
	local labels = { "Name", "ActivityName", "Members", "Comment", "VoiceChat", "LeaderName", "ListingName" }
	for _, k in ipairs(labels) do
		local w = entry[k]
		EQOL_SetTextGrey(w, dim)
	end
end

local function EQOL_HighlightSearchEntry(entry)
	-- Only decorate in our use-case
	if not addon.db["mythicPlusEnableDungeonFilter"] then return end
	local panel = LFGListFrame and LFGListFrame.SearchPanel
	if not panel or panel.categoryID ~= 2 then return end

	local resultID = entry and (entry.resultID or entry.id or entry.searchResultID)
	if not resultID then
		EQOL_RestoreEntryVisuals(entry)
		return
	end

	local info = C_LFGList.GetSearchResultInfo(resultID)
	local ignored = false
	if addon.db.enableIgnore and addon.Ignore and addon.Ignore.CheckIgnore and info and info.leaderName then ignored = addon.Ignore:CheckIgnore(info.leaderName) and true or false end

	-- If no filters active, restore visuals and exit unless the entry is ignored
	if not AnyFilterActive() then
		if ignored then
			EQOL_ApplyEntryVisuals(entry, false, true)
		else
			EQOL_RestoreEntryVisuals(entry)
		end
		return
	end

	-- Keep selected/applied entries normal unless ignored
	local selectedID = (type(LFGListSearchPanel_GetSelectedResult) == "function" and LFGListSearchPanel_GetSelectedResult(panel)) or panel.selectedResultID or panel.selectedResult
	if selectedID and selectedID == resultID then
		if ignored then
			EQOL_ApplyEntryVisuals(entry, false, true)
		else
			EQOL_RestoreEntryVisuals(entry)
		end
		return
	end

	local _, appStatus, pendingStatus = C_LFGList.GetApplicationInfo(resultID)
	if (appStatus and appStatus ~= "none") or pendingStatus then
		if ignored then
			EQOL_ApplyEntryVisuals(entry, false, true)
		else
			EQOL_RestoreEntryVisuals(entry)
		end
		return
	end

	local pass = info and EntryPassesFilter(info)

	EQOL_ApplyEntryVisuals(entry, pass == false, ignored)
end

local function FilterResults(panel)
	if not addon.db["mythicPlusEnableDungeonFilter"] then return end
	if not panel or panel.categoryID ~= 2 then return end

	-- Use the results prepared by Blizzard for this panel/update cycle.
	local baseResults = panel.results or select(2, C_LFGList.GetSearchResults())
	if not baseResults or #baseResults == 0 then return end

	-- If nothing to filter, keep Blizzard's list untouched to minimize taint risk.
	if not AnyFilterActive() then return end

	-- Preserve the currently selected entry, even if it wouldn't pass our filter.
	local selectedID = (type(LFGListSearchPanel_GetSelectedResult) == "function" and LFGListSearchPanel_GetSelectedResult(panel)) or panel.selectedResultID or panel.selectedResult

	local filtered = {}
	for _, resultID in ipairs(baseResults) do
		-- Always keep the selected entry and active applications.
		local _, appStatus, pendingStatus = C_LFGList.GetApplicationInfo(resultID)
		local isApplied = (appStatus and appStatus ~= "none") or pendingStatus

		if (selectedID and resultID == selectedID) or isApplied then
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
	local panel = LFGListFrame and LFGListFrame.SearchPanel
	if panel and type(LFGListSearchPanel_UpdateResultList) == "function" then LFGListSearchPanel_UpdateResultList(panel) end
end

local hooked = false

function addon.MythicPlus.functions.addDungeonFilter()
	if not hooked then
		hooksecurefunc("LFGListSearchPanel_UpdateResultList", FilterResults)
		hooksecurefunc("LFGListSearchEntry_Update", EQOL_HighlightSearchEntry)
		hooked = true
		if LFGList_ReportAdvertisement then
			function LFGList_ReportAdvertisement(searchResultID, leaderName)
				local info = ReportInfo:CreateReportInfoFromType(Enum.ReportType.GroupFinderPosting)
				info:SetGroupFinderSearchResultID(searchResultID)
				local sendReportWithoutDialog = false
				ReportFrame:InitiateReport(info, leaderName, nil, nil, sendReportWithoutDialog)
			end
		end
	end
	if addon.functions.isRestrictedContent(true) then return end
	-- Force one refresh so our filter runs once immediately.
	RefreshVisibleEntries()
end

function addon.MythicPlus.functions.removeDungeonFilter()
	addon.variables.requireReload = true
	-- No-op: the feature is gated by addon.db["mythicPlusEnableDungeonFilter"]; the secure hook remains harmless.
end

function addon.MythicPlus.functions.InitDungeonFilter()
	if addon.MythicPlus.variables.dungeonFilterInitialized then return end
	if not addon.db then return end
	addon.MythicPlus.variables.dungeonFilterInitialized = true

	ensureDungeonFilterDB()
	refreshPlayerFlags()

	if Menu and Menu.ModifyMenu then Menu.ModifyMenu("MENU_LFG_FRAME_SEARCH_FILTER", EQOL_AddLFGEntries) end

	local resetButton = LFGListFrame
		and LFGListFrame.SearchPanel
		and LFGListFrame.SearchPanel.FilterButton
		and LFGListFrame.SearchPanel.FilterButton.ResetButton

	if resetButton and resetButton.HookScript and not resetButton._eqolDungeonFilterHook then
		resetButton:HookScript("OnClick", function()
			if not addon.db["mythicPlusEnableDungeonFilter"] then return end
			if not addon.db["mythicPlusEnableDungeonFilterClearReset"] then return end
			if not pDb then return end
			pDb["bloodlustAvailable"] = false
			pDb["NoBloodlust"] = false
			pDb["battleResAvailable"] = false
			pDb["partyFit"] = false
			pDb["NoSameSpec"] = false
			RefreshVisibleEntries()
		end)
		resetButton._eqolDungeonFilterHook = true
	end
end
