local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local cQuest = addon.functions.SettingsCreateCategory(nil, L["Quest"], nil, "Quest")
addon.SettingsLayout.questCategory = cQuest

local REMOVE_IGNORED_QUEST_NPC_DIALOG = addonName .. "QuestIgnoredNPCRemove"

local QUEST_TRACKER_QUEST_COUNT_COLOR = { r = 1, g = 210 / 255, b = 0 }
local questTrackerQuestCountFrame
local questTrackerQuestCountText
local questTrackerQuestCountWatcher

local function GetQuestTrackerQuestCountText()
	if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then return "" end
	local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
	if not numQuests then numQuests = 0 end
	local maxQuests = C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()
	if not maxQuests or maxQuests <= 0 then
		if numQuests <= 0 then return "" end
		return tostring(numQuests)
	end
	return string.format("%d/%d", numQuests, maxQuests)
end

local function PositionQuestTrackerQuestCount()
	if not questTrackerQuestCountFrame or not addon or not addon.db then return end
	local header = _G.QuestObjectiveTracker and _G.QuestObjectiveTracker.Header
	if not header then return end
	questTrackerQuestCountFrame:ClearAllPoints()
	local x = addon.db.questTrackerQuestCountOffsetX or 0
	local y = addon.db.questTrackerQuestCountOffsetY or 0
	questTrackerQuestCountFrame:SetPoint("CENTER", header, "CENTER", x, y)
end

local function EnsureQuestTrackerQuestCountFrame()
	local header = _G.QuestObjectiveTracker and _G.QuestObjectiveTracker.Header
	if not header then return nil end
	if not questTrackerQuestCountFrame then
		questTrackerQuestCountFrame = CreateFrame("Frame", nil, header)
		questTrackerQuestCountFrame:SetSize(1, 1)
	end
	questTrackerQuestCountFrame:SetParent(header)
	if not questTrackerQuestCountText then
		questTrackerQuestCountText = questTrackerQuestCountFrame:CreateFontString(nil, "OVERLAY")
		questTrackerQuestCountText:SetPoint("TOPLEFT")
		questTrackerQuestCountText:SetJustifyH("LEFT")
		questTrackerQuestCountText:SetJustifyV("TOP")
	end
	local referenceFont = header.Text and header.Text:GetFontObject()
	if referenceFont then
		questTrackerQuestCountText:SetFontObject(referenceFont)
	else
		questTrackerQuestCountText:SetFont(addon.variables.defaultFont or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	end
	questTrackerQuestCountText:SetTextColor(QUEST_TRACKER_QUEST_COUNT_COLOR.r, QUEST_TRACKER_QUEST_COUNT_COLOR.g, QUEST_TRACKER_QUEST_COUNT_COLOR.b)
	return questTrackerQuestCountFrame
end

local function UpdateQuestTrackerQuestCountPosition()
	if not addon or not addon.db then return end
	if not questTrackerQuestCountFrame or not questTrackerQuestCountFrame:IsShown() then
		if addon.db.questTrackerShowQuestCount then addon.functions.UpdateQuestTrackerQuestCount() end
		return
	end
	PositionQuestTrackerQuestCount()
end
addon.functions.UpdateQuestTrackerQuestCountPosition = UpdateQuestTrackerQuestCountPosition

local function UpdateQuestTrackerQuestCount()
	if not addon or not addon.db or not addon.db.questTrackerShowQuestCount then
		if questTrackerQuestCountFrame then questTrackerQuestCountFrame:Hide() end
		return
	end
	local header = _G.QuestObjectiveTracker and _G.QuestObjectiveTracker.Header
	if not header then
		if questTrackerQuestCountFrame then questTrackerQuestCountFrame:Hide() end
		return
	end
	local container = EnsureQuestTrackerQuestCountFrame()
	if not container or not questTrackerQuestCountText then return end
	PositionQuestTrackerQuestCount()
	local textValue = GetQuestTrackerQuestCountText()
	if textValue == "" then
		questTrackerQuestCountFrame:Hide()
		return
	end
	questTrackerQuestCountText:SetText(textValue)
	questTrackerQuestCountFrame:SetSize(math.max(1, questTrackerQuestCountText:GetStringWidth()), math.max(1, questTrackerQuestCountText:GetStringHeight()))
	questTrackerQuestCountFrame:Show()
	questTrackerQuestCountText:Show()
end
addon.functions.UpdateQuestTrackerQuestCount = UpdateQuestTrackerQuestCount

local function EnsureQuestTrackerQuestCountWatcher()
	if questTrackerQuestCountWatcher then return end
	questTrackerQuestCountWatcher = CreateFrame("Frame")
	local events = { "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_REMOVED" }
	for _, evt in ipairs(events) do
		questTrackerQuestCountWatcher:RegisterEvent(evt)
	end
	questTrackerQuestCountWatcher:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_ENTERING_WORLD" then
			C_Timer.After(0.5, UpdateQuestTrackerQuestCount)
		else
			UpdateQuestTrackerQuestCount()
		end
	end)
end

local function ShowRemoveIgnoredQuestNPCDialog(selectionKey)
	if not selectionKey or selectionKey == "" then return end
	if not addon.db or not addon.db["ignoredQuestNPC"] then return end

	local npcID = tonumber(selectionKey) or selectionKey
	local npcName = addon.db["ignoredQuestNPC"][npcID]
	if not npcName then
		local asString = tostring(selectionKey)
		if addon.db["ignoredQuestNPC"][asString] then
			npcID = asString
			npcName = addon.db["ignoredQuestNPC"][asString]
		end
	end
	if not npcName then return end

	StaticPopupDialogs[REMOVE_IGNORED_QUEST_NPC_DIALOG] = StaticPopupDialogs[REMOVE_IGNORED_QUEST_NPC_DIALOG]
		or {
			text = L["ignoredQuestNPCRemoveConfirm"],
			button1 = ACCEPT,
			button2 = CANCEL,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
		}

	StaticPopupDialogs[REMOVE_IGNORED_QUEST_NPC_DIALOG].OnAccept = function(_, data)
		if not data or data == "" or not addon.db or not addon.db["ignoredQuestNPC"] then return end
		if addon.db["ignoredQuestNPC"][data] then addon.db["ignoredQuestNPC"][data] = nil end
		local numericID = tonumber(data)
		if numericID and addon.db["ignoredQuestNPC"][numericID] then addon.db["ignoredQuestNPC"][numericID] = nil end
		local stringKey = tostring(data)
		if addon.db["ignoredQuestNPC"][stringKey] then addon.db["ignoredQuestNPC"][stringKey] = nil end
	end

	StaticPopup_Show(REMOVE_IGNORED_QUEST_NPC_DIALOG, npcName or tostring(npcID), nil, npcID)
end

local data = {
	{
		var = "autoChooseQuest",
		text = L["autoChooseQuest"],
		desc = L["interruptWithShift"],
		func = function(key) addon.db["autoChooseQuest"] = key end,
		default = false,
		children = {
			{
				var = "ignoreDailyQuests",
				text = L["ignoreDailyQuests"]:format(QUESTS_LABEL),
				func = function(key) addon.db["ignoreDailyQuests"] = key end,
				default = false,
				sType = "checkbox",
				parentCheck = function()
					return addon.SettingsLayout.elements["autoChooseQuest"]
						and addon.SettingsLayout.elements["autoChooseQuest"].setting
						and addon.SettingsLayout.elements["autoChooseQuest"].setting:GetValue() == true
				end,
				parent = true,
			},
			{
				var = "ignoreWarbandCompleted",
				text = L["ignoreWarbandCompleted"]:format(ACCOUNT_COMPLETED_QUEST_LABEL, QUESTS_LABEL),
				func = function(key) addon.db["ignoreWarbandCompleted"] = key end,
				default = false,
				sType = "checkbox",
				parentCheck = function()
					return addon.SettingsLayout.elements["autoChooseQuest"]
						and addon.SettingsLayout.elements["autoChooseQuest"].setting
						and addon.SettingsLayout.elements["autoChooseQuest"].setting:GetValue() == true
				end,
				parent = true,
			},
			{
				var = "ignoreTrivialQuests",
				text = L["ignoreTrivialQuests"]:format(QUESTS_LABEL),
				func = function(key) addon.db["ignoreTrivialQuests"] = key end,
				default = false,
				sType = "checkbox",
				parentCheck = function()
					return addon.SettingsLayout.elements["autoChooseQuest"]
						and addon.SettingsLayout.elements["autoChooseQuest"].setting
						and addon.SettingsLayout.elements["autoChooseQuest"].setting:GetValue() == true
				end,
				parent = true,
			},
			{
				text = "|cff99e599" .. L["ignoreNPCTipp"] .. "|r",
				sType = "hint",
			},
			{
				listFunc = function()
					local tList = { [""] = "" }
					for id, name in pairs(addon.db["ignoredQuestNPC"] or {}) do
						tList[id] = name
					end
					return tList
				end,
				text = REMOVE,
				get = function() return "" end,
				set = function(key)
					if not key or key == "" then return end
					ShowRemoveIgnoredQuestNPCDialog(key)
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["autoChooseQuest"]
						and addon.SettingsLayout.elements["autoChooseQuest"].setting
						and addon.SettingsLayout.elements["autoChooseQuest"].setting:GetValue() == true
				end,
				parent = true,
				var = "ignoredQuestNPC",
				type = Settings.VarType.Number,
				sType = "dropdown",
			},
		},
	},
	{
		var = "questWowheadLink",
		text = L["questWowheadLink"],
		func = function(key) addon.db["questWowheadLink"] = key end,
		default = false,
	},
	{
		var = "autoCancelCinematic",
		text = L["autoCancelCinematic"],
		desc = L["autoCancelCinematicDesc"],
		func = function(key) addon.db["autoCancelCinematic"] = key end,
		default = false,
	},
	{
		var = "questTrackerShowQuestCount",
		text = L["questTrackerShowQuestCount"],
		desc = L["questTrackerShowQuestCount_desc"],
		func = function(key)
			addon.db["questTrackerShowQuestCount"] = key
			addon.functions.UpdateQuestTrackerQuestCount()
		end,
		default = false,
		children = {
			{
				var = "questTrackerQuestCountOffsetX",
				text = L["questTrackerQuestCountOffsetX"],
				parentCheck = function()
					return addon.SettingsLayout.elements["questTrackerShowQuestCount"]
						and addon.SettingsLayout.elements["questTrackerShowQuestCount"].setting
						and addon.SettingsLayout.elements["questTrackerShowQuestCount"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.questTrackerQuestCountOffsetX or 0 end,
				set = function(value)
					addon.db["questTrackerQuestCountOffsetX"] = value
					addon.functions.UpdateQuestTrackerQuestCountPosition()
				end,
				min = -200,
				max = 200,
				step = 1,
				parent = true,
				default = 0,
				sType = "slider",
			},
			{
				var = "questTrackerQuestCountOffsetY",
				text = L["questTrackerQuestCountOffsetY"],
				parentCheck = function()
					return addon.SettingsLayout.elements["questTrackerShowQuestCount"]
						and addon.SettingsLayout.elements["questTrackerShowQuestCount"].setting
						and addon.SettingsLayout.elements["questTrackerShowQuestCount"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.questTrackerQuestCountOffsetY or 0 end,
				set = function(value)
					addon.db["questTrackerQuestCountOffsetY"] = value
					addon.functions.UpdateQuestTrackerQuestCountPosition()
				end,
				min = -200,
				max = 200,
				step = 1,
				parent = true,
				default = 0,
				sType = "slider",
			},
		},
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cQuest, data)

----- REGION END

function addon.functions.initQuest()
	addon.functions.InitDBValue("autoChooseQuest", false)
	addon.functions.InitDBValue("ignoreTrivialQuests", false)
	addon.functions.InitDBValue("ignoreDailyQuests", false)
	addon.functions.InitDBValue("questTrackerShowQuestCount", false)
	addon.functions.InitDBValue("questTrackerQuestCountOffsetX", 0)
	addon.functions.InitDBValue("questTrackerQuestCountOffsetY", 0)
	addon.functions.InitDBValue("questWowheadLink", false)
	addon.functions.InitDBValue("ignoredQuestNPC", {})
	addon.functions.InitDBValue("autogossipID", {})

	local function EQOL_GetQuestIDFromMenu(owner, ctx)
		if ctx and (ctx.questID or ctx.questId) then return ctx.questID or ctx.questId end

		addon.db.testOwner = owner

		if owner then
			if owner.questID then return owner.questID end
			if owner.GetQuestID then
				local ok, id = pcall(owner.GetQuestID, owner)
				if ok and id then return id end
			end
			if owner.questLogIndex and C_QuestLog and C_QuestLog.GetInfo then
				local info = C_QuestLog.GetInfo(owner.questLogIndex)
				if info and info.questID then return info.questID end
			end
		end
		return nil
	end

	local function EQOL_ShowCopyURL(url)
		if not StaticPopupDialogs["ENHANCEQOL_COPY_URL"] then
			StaticPopupDialogs["ENHANCEQOL_COPY_URL"] = {
				text = "Copy URL:",
				button1 = OKAY,
				hasEditBox = true,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
				OnShow = function(self, data)
					local eb = self.editBox or self.GetEditBox and self:GetEditBox()
					eb:SetAutoFocus(true)
					eb:SetText(data or "")
					eb:HighlightText()
					eb:SetCursorPosition(0)
				end,
				OnAccept = function(self) end,
				EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
			}
		end
		StaticPopup_Show("ENHANCEQOL_COPY_URL", nil, nil, url)
	end

	local function EQOL_AddQuestWowheadEntry(owner, root, ctx)
		if not addon.db["questWowheadLink"] then return end
		local qid
		if owner.GetName and owner:GetName() == "ObjectiveTrackerFrame" then
			local mFocus = GetMouseFoci()
			if mFocus and mFocus[1] and mFocus[1].GetParent then
				local pInfo = mFocus[1]:GetParent()
				if pInfo.poiQuestID then
					qid = pInfo.poiQuestID
				else
					return
				end
			end
		else
			qid = EQOL_GetQuestIDFromMenu(owner, ctx)
		end
		if not qid then return end
		root:CreateDivider()
		local btn = root:CreateButton("Copy Wowhead URL", function() EQOL_ShowCopyURL(("https://www.wowhead.com/quest=%d"):format(qid)) end)
		btn:AddInitializer(function()
			btn:SetTooltip(function(tt)
				GameTooltip_SetTitle(tt, "Wowhead")
				GameTooltip_AddNormalLine(tt, ("quest=%d"):format(qid))
			end)
		end)
	end

	-- Register for Blizzard's menu tags (provided by /etrace):
	if Menu and Menu.ModifyMenu then
		Menu.ModifyMenu("MENU_QUEST_MAP_LOG_TITLE", EQOL_AddQuestWowheadEntry)
		Menu.ModifyMenu("MENU_QUEST_OBJECTIVE_TRACKER", EQOL_AddQuestWowheadEntry)
	end

	if Menu and Menu.ModifyMenu then
		local function GetNPCIDFromGUID(guid)
			if guid then
				local type, _, _, _, _, npcID = strsplit("-", guid)
				if type == "Creature" or type == "Vehicle" then return tonumber(npcID) end
			end
			return nil
		end

		local function AddIgnoreAutoQuest(owner, root, ctx)
			if not addon.db["autoChooseQuest"] then return end

			if not UnitExists("target") or UnitPlayerControlled("target") then return end
			local npcID = GetNPCIDFromGUID(UnitGUID("target"))
			if not npcID then return end
			if issecretvalue and issecretvalue(npcID) then return end
			local name = UnitName("target")
			if not name then return end

			root:CreateDivider()
			root:CreateTitle(addonName)
			if addon.db["ignoredQuestNPC"][npcID] then
				root:CreateButton(L["SettingsQuestHeaderIgnoredNPCRemove"], function(id) addon.db["ignoredQuestNPC"][npcID] = nil end, npcID)
			else
				root:CreateButton(L["SettingsQuestHeaderIgnoredNPCAdd"], function(id) addon.db["ignoredQuestNPC"][npcID] = name end, npcID)
			end
		end

		Menu.ModifyMenu("MENU_UNIT_TARGET", AddIgnoreAutoQuest)
	end

	EnsureQuestTrackerQuestCountWatcher()
	UpdateQuestTrackerQuestCount()
end

local eventHandlers = {}

local function registerEvents(frame)
	for event in pairs(eventHandlers) do
		frame:RegisterEvent(event)
	end
end

local function eventHandler(self, event, ...)
	if eventHandlers[event] then eventHandlers[event](...) end
end

local frameLoad = CreateFrame("Frame")

registerEvents(frameLoad)
frameLoad:SetScript("OnEvent", eventHandler)
