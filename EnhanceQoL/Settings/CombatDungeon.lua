local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

---- REGION Functions
local timeoutReleaseDifficultyLookup = {}

local function shouldUseTimeoutReleaseForCurrentContext()
	if not addon.db or not addon.db["timeoutRelease"] then return false end

	local selection = addon.db["timeoutReleaseDifficulties"]
	if selection == nil then return true end

	local hasSelection = false
	for key, enabled in pairs(selection) do
		if enabled then
			hasSelection = true
			break
		end
	end
	if not hasSelection then return false end

	local inInstance, instanceType = IsInInstance()
	if not inInstance or instanceType == "none" then return selection["world"] and true or false end

	local difficultyID = select(3, GetInstanceInfo())
	if difficultyID then
		local keys = timeoutReleaseDifficultyLookup[difficultyID]
		if keys then
			for _, key in ipairs(keys) do
				if selection[key] then return true end
			end
		end
	end

	if instanceType == "scenario" then return selection["scenario"] and true or false end
	if instanceType == "pvp" or instanceType == "arena" then return selection["pvp"] and true or false end
	if instanceType == "raid" then return selection["raidNormal"] or selection["raidHeroic"] or selection["raidMythic"] end
	if instanceType == "party" then return selection["dungeonNormal"] or selection["dungeonHeroic"] or selection["dungeonMythic"] or selection["dungeonMythicPlus"] or selection["dungeonFollower"] end

	return false
end

addon.functions.shouldUseTimeoutReleaseForCurrentContext = shouldUseTimeoutReleaseForCurrentContext

local TIMEOUT_RELEASE_UPDATE_INTERVAL = 0.1

local modifierCheckers = {
	SHIFT = function() return IsShiftKeyDown() end,
	CTRL = function() return IsControlKeyDown() end,
	ALT = function() return IsAltKeyDown() end,
}

local modifierDisplayNames = {
	SHIFT = SHIFT_KEY_TEXT,
	CTRL = CTRL_KEY_TEXT,
	ALT = ALT_KEY_TEXT,
}

local DEFAULT_TIMEOUT_RELEASE_HINT = "Hold %s to release"

function addon.functions.getTimeoutReleaseModifierKey()
	local modifierKey = addon.db and addon.db["timeoutReleaseModifier"] or "SHIFT"
	if not modifierCheckers[modifierKey] then modifierKey = "SHIFT" end
	return modifierKey
end

function addon.functions.isTimeoutReleaseModifierDown(modifierKey)
	local checker = modifierCheckers[modifierKey]
	return checker and checker() or false
end

function addon.functions.getTimeoutReleaseModifierDisplayName(modifierKey) return modifierDisplayNames[modifierKey] or modifierKey end

function addon.functions.showTimeoutReleaseHint(popup, modifierDisplayName)
	if not popup then return end
	local label = popup.eqolTimeoutReleaseLabel
	if not label then
		label = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetJustifyH("CENTER")
		label:SetPoint("BOTTOM", popup, "TOP", 0, 8)
		label:SetTextColor(1, 0.82, 0)
		label:SetWordWrap(true)
		popup.eqolTimeoutReleaseLabel = label
	end
	local hintTemplate = rawget(L, "timeoutReleaseHoldHint") or DEFAULT_TIMEOUT_RELEASE_HINT
	label:SetWidth(popup:GetWidth())
	label:SetText(hintTemplate:format(modifierDisplayName))
	label:Show()
end

function addon.functions.hideTimeoutReleaseHint(popup)
	local label = popup and popup.eqolTimeoutReleaseLabel
	if label then label:Hide() end
end

local function toggleGroupApplication(value)
	if value then
		-- Hide overlay and text label
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Label:Hide()
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Background:Hide()
		-- Hide the 3 animated texture icons
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Waitdot1:Hide()
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Waitdot2:Hide()
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Waitdot3:Hide()
	else
		-- Hide overlay and text label
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Label:Show()
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Background:Show()
		-- Hide the 3 animated texture icons
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Waitdot1:Show()
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Waitdot2:Show()
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Waitdot3:Show()
	end
end

local lfgPoint, lfgRelativeTo, lfgRelativePoint, lfgXOfs, lfgYOfs

local function toggleLFGFilterPosition()
	if LFGListFrame and LFGListFrame.SearchPanel and LFGListFrame.SearchPanel.FilterButton and LFGListFrame.SearchPanel.FilterButton.ResetButton then
		if addon.db["groupfinderMoveResetButton"] then
			LFGListFrame.SearchPanel.FilterButton.ResetButton:ClearAllPoints()
			LFGListFrame.SearchPanel.FilterButton.ResetButton:SetPoint("TOPLEFT", LFGListFrame.SearchPanel.FilterButton, "TOPLEFT", -7, 13)
		else
			LFGListFrame.SearchPanel.FilterButton.ResetButton:ClearAllPoints()
			LFGListFrame.SearchPanel.FilterButton.ResetButton:SetPoint(lfgPoint, lfgRelativeTo, lfgRelativePoint, lfgXOfs, lfgYOfs)
		end
	end
end

addon.functions.FindBindingIndex = function(data)
	local found = {}
	if not type(data) == "table" then return end

	for i = 1, GetNumBindings() do
		local command = GetBinding(i)
		if data[command] then found[command] = i end
	end
	return found
end

function addon.functions.initDungeonFrame()
	addon.functions.InitDBValue("autoChooseDelvePower", false)
	addon.functions.InitDBValue("lfgSortByRio", false)
	addon.functions.InitDBValue("groupfinderSkipRoleSelect", false)
	addon.functions.InitDBValue("enableChatIMRaiderIO", false)
	addon.functions.InitDBValue("timeoutReleaseDifficulties", {})

	local find = {
		["CLICK EQOLWorldMarkerCycler:LeftButton"] = true,
		["CLICK EQOLWorldMarkerCycler:RightButton"] = true,
	}
	addon.variables.keybindFindings = addon.functions.FindBindingIndex(find)

	if #addon.variables.keybindFindings then
		addon.functions.SettingsCreateHeadline(addon.SettingsLayout.characterInspectCategory, AUCTION_CATEGORY_MISCELLANEOUS, "CombatDungeon_Misc")
		addon.functions.SettingsCreateText(addon.SettingsLayout.characterInspectCategory, "|cff99e599" .. L["WorldMarkerCycle"] .. "|r", "EQOL_WorldMarkerCycle")
	end
	for i, v in pairs(addon.variables.keybindFindings) do
		addon.functions.SettingsCreateKeybind(addon.SettingsLayout.characterInspectCategory, v)
	end

	if LFGListFrame and LFGListFrame.SearchPanel and LFGListFrame.SearchPanel.FilterButton and LFGListFrame.SearchPanel.FilterButton.ResetButton then
		lfgPoint, lfgRelativeTo, lfgRelativePoint, lfgXOfs, lfgYOfs = LFGListFrame.SearchPanel.FilterButton.ResetButton:GetPoint()
	end
	if addon.db["groupfinderMoveResetButton"] then toggleLFGFilterPosition() end

	-- Add Raider.IO URL to LFG applicant member context menu
	if Menu and Menu.ModifyMenu then
		local regionTable = { "US", "KR", "EU", "TW", "CN" }
		local function AddLFGApplicantRIO(owner, root, ctx)
			if not addon.db["enableChatIMRaiderIO"] then return end

			local appID = owner and owner._eqolApplicantID or (ctx and (ctx.applicantID or ctx.appID))
			local memberIdx = owner and owner._eqolMemberIdx or (ctx and (ctx.memberIdx or ctx.memberIndex))
			if not appID or not memberIdx then return end

			local name = C_LFGList and C_LFGList.GetApplicantMemberInfo and C_LFGList.GetApplicantMemberInfo(appID, memberIdx)
			if type(name) ~= "string" or name == "" then return end

			local targetName = name
			if not targetName:find(" -", 1, true) then targetName = targetName .. " -" .. (GetRealmName() or ""):gsub("%s", "") end

			local char, realm = targetName:match("^([^%-]+)%-(.+)$")
			if not char or not realm then return end

			local regionKey = regionTable[GetCurrentRegion()] or "EU"
			local realmSlug = string.lower((realm or ""):gsub("%s+", " -"))
			local riolink = "https://raider.io/characters/" .. string.lower(regionKey) .. "/" .. realmSlug .. "/" .. char

			root:CreateDivider()
			root:CreateButton(L["RaiderIOUrl"], function(link)
				if StaticPopup_Show then StaticPopup_Show("EQOL_URL_COPY", nil, nil, link) end
			end, riolink)
		end

		Menu.ModifyMenu("MENU_LFG_FRAME_MEMBER_APPLY", AddLFGApplicantRIO)
	end

	_G["BINDING_NAME_CLICK EQOLWorldMarkerCycler:LeftButton"] = L["Cycle World Marker"]
	_G["BINDING_NAME_CLICK EQOLWorldMarkerCycler:RightButton"] = L["Clear World Marker"]

	local btn = CreateFrame("Button", "EQOLWorldMarkerCycler", UIParent, "SecureActionButtonTemplate")
	btn:SetAttribute("type", "macro")
	btn:RegisterForClicks("AnyDown")
	local body = "i = 0;order = newtable()"
	for i = 1, 8 do
		body = body .. format("\ntinsert(order, %s)", i)
	end
	SecureHandlerExecute(btn, body)

	SecureHandlerUnwrapScript(btn, "PreClick")
	-- TODO check midnight later, /cwm 0 not working for now

	SecureHandlerWrapScript(
		btn,
		"PreClick",
		btn,
		[=[ 
		if not down or not next(order) then return end
		if button == "RightButton" then
			i = 0
			self:SetAttribute("macrotext", "/cwm 1\n/cwm 2\n/cwm 3\n/cwm 4\n/cwm 5\n/cwm 6\n/cwm 7\n/cwm 8")
		else
			i = i%#order + 1
			self:SetAttribute("macrotext", "/wm [@cursor]"..order[i])
		end
	]=]
	)
end

---- END REGION

---- REGION SETTINGS
local cChar = addon.functions.SettingsCreateCategory(nil, L["CombatDungeons"], nil, "CombatDungeons")
addon.SettingsLayout.characterInspectCategory = cChar
addon.functions.SettingsCreateHeadline(cChar, DUNGEONS, "CombatDungeon_Dungeon")

local data = {
	{
		text = L["groupfinderAppText"],
		var = "groupfinderAppText",
		func = function(value)
			addon.db["groupfinderAppText"] = value
			toggleGroupApplication(value)
		end,
	},
	{
		text = L["groupfinderMoveResetButton"],
		var = "groupfinderMoveResetButton",
		func = function(value)
			addon.db["groupfinderMoveResetButton"] = value
			toggleLFGFilterPosition()
		end,
	},
	{
		text = L["groupfinderSkipRoleSelect"],
		var = "groupfinderSkipRoleSelect",
		func = function(value) addon.db["groupfinderSkipRoleSelect"] = value end,
		desc = L["interruptWithShift"],
		children = {
			{
				list = { [1] = L["groupfinderSkipRolecheckUseSpec"], [2] = L["groupfinderSkipRolecheckUseLFD"] },
				text = L["groupfinderSkipRolecheckHeadline"],
				get = function() return addon.db["groupfinderSkipRoleSelectOption"] or 1 end,
				set = function(key) addon.db["groupfinderSkipRoleSelectOption"] = key end,
				parentCheck = function()
					return addon.SettingsLayout.elements["groupfinderSkipRoleSelect"]
						and addon.SettingsLayout.elements["groupfinderSkipRoleSelect"].setting
						and addon.SettingsLayout.elements["groupfinderSkipRoleSelect"].setting:GetValue() == true
				end,
				parent = true,
				default = 1,
				var = "groupfinderSkipRoleSelectOption",
				type = Settings.VarType.Number,
				sType = "dropdown",
			},
		},
	},
	{
		var = "persistSignUpNote",
		text = L["Persist LFG signup note"],
		func = function(value) addon.db["persistSignUpNote"] = value end,
	},
	{
		var = "skipSignUpDialog",
		text = L["Quick signup"],
		func = function(value) addon.db["skipSignUpDialog"] = value end,
	},
	{
		var = "lfgSortByRio",
		text = L["lfgSortByRio"],
		func = function(value) addon.db["lfgSortByRio"] = value end,
	},
	{
		var = "enableChatIMRaiderIO",
		text = L["enableChatIMRaiderIO"],
		func = function(value) addon.db["enableChatIMRaiderIO"] = value end,
	},
}
table.sort(data, function(a, b) return a.text < b.text end)
--- DELVES
addon.functions.SettingsCreateCheckboxes(cChar, data)

addon.functions.SettingsCreateHeadline(cChar, DELVES_LABEL)

data = {
	{
		var = "autoChooseDelvePower",
		text = L["autoChooseDelvePower"],
		func = function(self, _, value) addon.db["autoChooseDelvePower"] = value end,
	},
}
table.sort(data, function(a, b) return a.text < b.text end)

addon.functions.SettingsCreateCheckboxes(cChar, data)

--- GENERAL
addon.functions.SettingsCreateHeadline(cChar, GENERAL)

data = {
	var = "timeoutRelease",
	text = L["timeoutRelease"],
	func = function(value) addon.db["timeoutRelease"] = value end,
}
table.sort(data, function(a, b) return a.text < b.text end)

local rData = addon.functions.SettingsCreateCheckbox(cChar, data)

data = {
	list = {
		SHIFT = SHIFT_KEY_TEXT,
		CTRL = CTRL_KEY_TEXT,
		ALT = ALT_KEY_TEXT,
	},
	text = L["timeoutReleaseModifierLabel"],
	get = function() return addon.db["timeoutReleaseModifier"] or "SHIFT" end,
	set = function(key) addon.db["timeoutReleaseModifier"] = key end,
	parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
	element = rData.element,
	parent = true,
	default = "SHIFT",
	var = "timeoutReleaseModifier",
}

addon.functions.SettingsCreateDropdown(cChar, data)

local timeoutReleaseGroups = {
	{
		var = "timeoutRelease_raidNormal",
		value = "raidNormal",
		text = RAID .. " - " .. PLAYER_DIFFICULTY1 .. " / " .. PLAYER_DIFFICULTY3 .. " / " .. PLAYER_DIFFICULTY_TIMEWALKER,
		func = function(value) addon.db["timeoutReleaseDifficulties"]["raidNormal"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["raidNormal"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 3, 4, 7, 9, 14, 17, 18, 33, 151, 220 },
	},
	{
		var = "timeoutRelease_raidHeroic",
		value = "raidHeroic",
		text = RAID .. " - " .. PLAYER_DIFFICULTY2,
		func = function(value) addon.db["timeoutReleaseDifficulties"]["raidHeroic"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["raidHeroic"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 5, 6, 15 },
	},
	{
		var = "timeoutRelease_raidMythic",
		value = "raidMythic",
		text = RAID .. " - " .. PLAYER_DIFFICULTY6,
		func = function(value) addon.db["timeoutReleaseDifficulties"]["raidMythic"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["raidMythic"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 16 },
	},
	{
		var = "timeoutRelease_dungeonNormal",
		value = "dungeonNormal",
		text = DUNGEONS .. " - " .. PLAYER_DIFFICULTY1 .. " / " .. PLAYER_DIFFICULTY_TIMEWALKER,
		func = function(value) addon.db["timeoutReleaseDifficulties"]["dungeonNormal"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["dungeonNormal"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 1, 24, 150, 216 },
	},
	{
		var = "timeoutRelease_dungeonHeroic",
		value = "dungeonHeroic",
		text = DUNGEONS .. " - " .. PLAYER_DIFFICULTY2,
		func = function(value) addon.db["timeoutReleaseDifficulties"]["dungeonHeroic"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["dungeonHeroic"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 2 },
	},
	{
		var = "timeoutRelease_dungeonMythic",
		value = "dungeonMythic",
		text = DUNGEONS .. " - " .. PLAYER_DIFFICULTY6,
		func = function(value) addon.db["timeoutReleaseDifficulties"]["dungeonMythic"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["dungeonMythic"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 23 },
	},
	{
		var = "timeoutRelease_dungeonMythicPlus",
		value = "dungeonMythicPlus",
		text = DUNGEONS .. " - " .. PLAYER_DIFFICULTY_MYTHIC_PLUS,
		func = function(value) addon.db["timeoutReleaseDifficulties"]["dungeonMythicPlus"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["dungeonMythicPlus"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 8 },
	},
	{
		var = "timeoutRelease_dungeonFollower",
		value = "dungeonFollower",
		text = GUILD_CHALLENGE_TYPE4 .. " - " .. L["timeoutReleasePrefixScenario"],
		func = function(value) addon.db["timeoutReleaseDifficulties"]["dungeonFollower"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["dungeonFollower"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 11, 12, 20, 30, 38, 39, 40, 147, 149, 152, 153, 167, 168, 169, 170, 171, 208 },
	},
	{
		var = "timeoutRelease_pvp",
		value = "pvp",
		text = PVP,
		func = function(value) addon.db["timeoutReleaseDifficulties"]["pvp"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["pvp"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 29, 34, 45 },
	},
	{
		var = "timeoutRelease_world",
		value = "world",
		text = WORLD,
		func = function(value) addon.db["timeoutReleaseDifficulties"]["world"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["world"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 0, 172, 192 },
	},
}

for _, group in ipairs(timeoutReleaseGroups) do
	if group.difficulties then
		group.difficultySet = {}
		for _, difficultyID in ipairs(group.difficulties) do
			group.difficultySet[difficultyID] = true
			local bucket = timeoutReleaseDifficultyLookup[difficultyID]
			if not bucket then
				timeoutReleaseDifficultyLookup[difficultyID] = { group.key }
			else
				table.insert(bucket, group.key)
			end
		end
	end
end

addon.functions.SettingsCreateMultiDropdown(cChar, {
	var = "timeoutReleaseDifficulties",
	text = L["timeoutReleaseHeadline"],
	parent = true,
	element = rData.element,
	parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
	options = timeoutReleaseGroups,
})

---- REGION END

local eventHandlers = {

	["LFG_LIST_APPLICANT_UPDATED"] = function()
		if PVEFrame:IsShown() and addon.db["lfgSortByRio"] then C_LFGList.RefreshApplicants() end
		if InCombatLockdown() then return end
		if addon.db["groupfinderAppText"] then toggleGroupApplication(true) end
	end,
	["MODIFIER_STATE_CHANGED"] = function(arg1, arg2)
		if not addon.db["timeoutRelease"] then return end
		if not UnitIsDead("player") then return end
		local modifierKey = addon.functions.getTimeoutReleaseModifierKey()
		if not (arg1 and arg1:match(modifierKey)) then return end

		local _, stp = StaticPopup_Visible("DEATH")
		if stp and stp.GetButton and addon.functions.shouldUseTimeoutReleaseForCurrentContext() then
			local btn = stp:GetButton(1)
			if btn then btn:SetAlpha(arg2 or 0) end
		end
	end,
	["PLAYER_CHOICE_UPDATE"] = function()
		if select(3, GetInstanceInfo()) == 208 and addon.db["autoChooseDelvePower"] then
			local choiceInfo = C_PlayerChoice.GetCurrentPlayerChoiceInfo()
			if choiceInfo and choiceInfo.options and #choiceInfo.options == 1 then
				C_PlayerChoice.SendPlayerChoiceResponse(choiceInfo.options[1].buttons[1].id)
				if PlayerChoiceFrame:IsShown() then PlayerChoiceFrame:Hide() end
			end
		end
	end,
}

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
