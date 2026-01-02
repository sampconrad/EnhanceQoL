local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local LMP = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_MythicPlus")
local LSM = LibStub("LibSharedMedia-3.0")
local wipe = wipe

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

	local sectionMarkers = addon.SettingsLayout.gameplayMarkersSection
	if addon.variables.keybindFindings and next(addon.variables.keybindFindings) then
		if not sectionMarkers then
			sectionMarkers = addon.functions.SettingsCreateExpandableSection(addon.SettingsLayout.characterInspectCategory, {
				name = L["Markers"],
				expanded = false,
				colorizeTitle = false,
			})
			addon.SettingsLayout.gameplayMarkersSection = sectionMarkers
		end
		addon.functions.SettingsCreateHeadline(addon.SettingsLayout.characterInspectCategory, L["WorldMarkers"], {
			parentSection = sectionMarkers,
		})
		addon.functions.SettingsCreateText(addon.SettingsLayout.characterInspectCategory, "|cff99e599" .. L["WorldMarkerCycle"] .. "|r", { parentSection = sectionMarkers })
	end
	for _, v in pairs(addon.variables.keybindFindings) do
		addon.functions.SettingsCreateKeybind(addon.SettingsLayout.characterInspectCategory, v, sectionMarkers)
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

	local expandable = addon.functions.SettingsCreateExpandableSection(addon.SettingsLayout.characterInspectCategory, {
		name = L["Convenience"],
		expanded = false,
		colorizeTitle = false,
	})

	local classTag = (addon.variables and addon.variables.unitClass) or select(2, UnitClass("player"))
	if classTag == "DRUID" then
		addon.functions.SettingsCreateHeadline(addon.SettingsLayout.characterInspectCategory, select(1, UnitClass("player")), { parentSection = expandable })

		local data = {
			{
				var = "autoCancelDruidFlightForm",
				text = L["autoCancelDruidFlightForm"],
				desc = L["autoCancelDruidFlightFormDesc"],
				func = function(value)
					addon.db["autoCancelDruidFlightForm"] = value and true or false
					if addon.functions.updateDruidFlightFormWatcher then addon.functions.updateDruidFlightFormWatcher() end
				end,
				parentSection = expandable,
			},
		}

		addon.functions.SettingsCreateCheckboxes(addon.SettingsLayout.characterInspectCategory, data)
	end
end

---- END REGION

---- REGION SETTINGS
local cChar = addon.SettingsLayout.rootGAMEPLAY
addon.SettingsLayout.characterInspectCategory = cChar
local data

-- Dungeons & Mythic+
local sectionDungeon = addon.SettingsLayout.gameplayDungeonsMythicSection
if not sectionDungeon then
	sectionDungeon = addon.functions.SettingsCreateExpandableSection(cChar, {
		name = L["DungeonsMythicPlus"],
		expanded = false,
		colorizeTitle = false,
	})
	addon.SettingsLayout.gameplayDungeonsMythicSection = sectionDungeon
end

-- Potion Tracker (Combat & Dungeon)
if cChar and sectionDungeon and not addon.variables.isMidnight then
	addon.functions.SettingsCreateHeadline(cChar, LMP["Potion Tracker"], { parentSection = sectionDungeon })
	if LMP["potionTrackerMidnightWarning"] then addon.functions.SettingsCreateText(cChar, LMP["potionTrackerMidnightWarning"], { parentSection = sectionDungeon }) end

	local potionEnable = addon.functions.SettingsCreateCheckbox(cChar, {
		var = "potionTracker",
		text = LMP["potionTracker"],
		desc = LMP["potionTrackerHeadline"],
		func = function(v)
			addon.db["potionTracker"] = v
			if v then
				if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.updateBars then addon.MythicPlus.functions.updateBars() end
			else
				if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.resetCooldownBars then addon.MythicPlus.functions.resetCooldownBars() end
				if addon.MythicPlus and addon.MythicPlus.anchorFrame and addon.MythicPlus.anchorFrame.Hide then addon.MythicPlus.anchorFrame:Hide() end
			end
		end,
		parentSection = sectionDungeon,
	})

	local function isPotionEnabled() return potionEnable and potionEnable.setting and potionEnable.setting:GetValue() == true end

	local potionOptions = {
		{
			var = "potionTrackerUpwardsBar",
			text = LMP["potionTrackerUpwardsBar"],
			func = function(v)
				addon.db["potionTrackerUpwardsBar"] = v
				if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.updateBars then addon.MythicPlus.functions.updateBars() end
			end,
			parentSection = sectionDungeon,
		},
		{
			var = "potionTrackerClassColor",
			text = LMP["potionTrackerClassColor"],
			func = function(v) addon.db["potionTrackerClassColor"] = v end,
			parentSection = sectionDungeon,
		},
		{
			var = "potionTrackerDisableRaid",
			text = LMP["potionTrackerDisableRaid"],
			func = function(v)
				addon.db["potionTrackerDisableRaid"] = v
				if v == true and UnitInRaid("player") and addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.resetCooldownBars then
					addon.MythicPlus.functions.resetCooldownBars()
				end
			end,
			parentSection = sectionDungeon,
		},
		{
			var = "potionTrackerShowTooltip",
			text = LMP["potionTrackerShowTooltip"],
			func = function(v) addon.db["potionTrackerShowTooltip"] = v end,
			parentSection = sectionDungeon,
		},
		{
			var = "potionTrackerHealingPotions",
			text = LMP["potionTrackerHealingPotions"],
			func = function(v) addon.db["potionTrackerHealingPotions"] = v end,
			parentSection = sectionDungeon,
		},
		{
			var = "potionTrackerOffhealing",
			text = LMP["potionTrackerOffhealing"],
			func = function(v) addon.db["potionTrackerOffhealing"] = v end,
			parentSection = sectionDungeon,
		},
	}

	for _, entry in ipairs(potionOptions) do
		entry.parent = true
		entry.element = potionEnable.element
		entry.parentCheck = isPotionEnabled
		addon.functions.SettingsCreateCheckbox(cChar, entry)
	end

	local potionTextureOrder = {}
	local function buildPotionTextureOptions()
		local map = {
			["DEFAULT"] = DEFAULT,
			["Interface\\TargetingFrame\\UI-StatusBar"] = "Blizzard: UI-StatusBar",
			["Interface\\Buttons\\WHITE8x8"] = "Flat (white, tintable)",
			["Interface\\Tooltips\\UI-Tooltip-Background"] = "Dark Flat (Tooltip bg)",
		}
		for name, path in pairs(LSM and LSM:HashTable("statusbar") or {}) do
			if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
		end
		local noDefault = {}
		for k, v in pairs(map) do
			if k ~= "DEFAULT" then noDefault[k] = v end
		end
		local sorted, order = addon.functions.prepareListForDropdown(noDefault)
		sorted["DEFAULT"] = DEFAULT
		table.insert(order, 1, "DEFAULT")
		wipe(potionTextureOrder)
		for i, key in ipairs(order) do
			potionTextureOrder[i] = key
		end
		return sorted
	end

	addon.functions.SettingsCreateScrollDropdown(cChar, {
		var = "potionTrackerBarTexture",
		text = LMP["Bar Texture"],
		default = "DEFAULT",
		listFunc = buildPotionTextureOptions,
		order = potionTextureOrder,
		get = function()
			local cur = (addon.db and addon.db["potionTrackerBarTexture"]) or "DEFAULT"
			local list = buildPotionTextureOptions()
			if not list[cur] then cur = "DEFAULT" end
			return cur
		end,
		set = function(key)
			addon.db["potionTrackerBarTexture"] = key
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.applyPotionBarTexture then addon.MythicPlus.functions.applyPotionBarTexture() end
		end,
		parent = true,
		element = potionEnable.element,
		parentCheck = isPotionEnabled,
		parentSection = sectionDungeon,
	})

	addon.functions.SettingsCreateButton(cChar, {
		var = "potionTrackerAnchor",
		text = LMP["Toggle Anchor"],
		func = function()
			local anchor = addon.MythicPlus and addon.MythicPlus.anchorFrame
			if not anchor then return end
			if anchor:IsShown() then
				anchor:Hide()
			else
				anchor:Show()
			end
		end,
		parent = true,
		element = potionEnable.element,
		parentCheck = isPotionEnabled,
		parentSection = sectionDungeon,
	})
end

-- Mythic+ & Raid (Combat & Dungeon)
local keystoneEnable
local function isKeystoneEnabled() return keystoneEnable and keystoneEnable.setting and keystoneEnable.setting:GetValue() == true end

if cChar and sectionDungeon then
	addon.functions.SettingsCreateHeadline(cChar, PLAYER_DIFFICULTY_MYTHIC_PLUS .. " & " .. RAID, { parentSection = sectionDungeon })

	-- Keystone Helper
	keystoneEnable = addon.functions.SettingsCreateCheckbox(cChar, {
		var = "enableKeystoneHelper",
		text = LMP["enableKeystoneHelper"],
		desc = LMP["enableKeystoneHelperDesc"],
		func = function(v)
			addon.db["enableKeystoneHelper"] = v
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.toggleFrame then addon.MythicPlus.functions.toggleFrame() end
		end,
		parentSection = sectionDungeon,
	})

	local keystoneChildren = {
		{ var = "autoInsertKeystone", text = LMP["Automatically insert keystone"], func = function(v) addon.db["autoInsertKeystone"] = v end, parentSection = sectionDungeon },
		{ var = "closeBagsOnKeyInsert", text = LMP["Close all bags on keystone insert"], func = function(v) addon.db["closeBagsOnKeyInsert"] = v end, parentSection = sectionDungeon },
		{ var = "autoKeyStart", text = LMP["autoKeyStart"], func = function(v) addon.db["autoKeyStart"] = v end, parentSection = sectionDungeon },
		{
			var = "mythicPlusShowChestTimers",
			text = LMP["mythicPlusShowChestTimers"],
			desc = LMP["mythicPlusShowChestTimersDesc"],
			func = function(v) addon.db["mythicPlusShowChestTimers"] = v end,
			parentSection = sectionDungeon,
		},
	}
	for _, entry in ipairs(keystoneChildren) do
		entry.parent = true
		entry.element = keystoneEnable.element
		entry.parentCheck = isKeystoneEnabled
		addon.functions.SettingsCreateCheckbox(cChar, entry)
	end

	local listPull, orderPull = addon.functions.prepareListForDropdown({
		[1] = LMP["None"],
		[2] = LMP["Blizzard Pull Timer"],
		[3] = LMP["DBM / BigWigs Pull Timer"],
		[4] = LMP["Both"],
	})
	addon.functions.SettingsCreateDropdown(cChar, {
		var = "PullTimerType",
		text = LMP["PullTimer"],
		type = Settings.VarType.Number,
		default = 2,
		list = listPull,
		order = orderPull,
		get = function() return (addon.db and addon.db["PullTimerType"]) or 1 end,
		set = function(value) addon.db["PullTimerType"] = value end,
		parent = true,
		element = keystoneEnable.element,
		parentCheck = isKeystoneEnabled,
		parentSection = sectionDungeon,
	})

	addon.functions.SettingsCreateCheckbox(cChar, {
		var = "noChatOnPullTimer",
		text = LMP["noChatOnPullTimer"],
		func = function(v) addon.db["noChatOnPullTimer"] = v end,
		parent = true,
		element = keystoneEnable.element,
		parentCheck = isKeystoneEnabled,
		parentSection = sectionDungeon,
	})

	addon.functions.SettingsCreateSlider(cChar, {
		var = "pullTimerLongTime",
		text = LMP["sliderLongTime"],
		min = 0,
		max = 60,
		step = 1,
		default = 10,
		get = function() return (addon.db and addon.db["pullTimerLongTime"]) or 10 end,
		set = function(val) addon.db["pullTimerLongTime"] = val end,
		parent = true,
		element = keystoneEnable.element,
		parentCheck = isKeystoneEnabled,
		parentSection = sectionDungeon,
	})

	addon.functions.SettingsCreateSlider(cChar, {
		var = "pullTimerShortTime",
		text = LMP["sliderShortTime"],
		min = 0,
		max = 60,
		step = 1,
		default = 5,
		get = function() return (addon.db and addon.db["pullTimerShortTime"]) or 5 end,
		set = function(val) addon.db["pullTimerShortTime"] = val end,
		parent = true,
		element = keystoneEnable.element,
		parentCheck = isKeystoneEnabled,
		parentSection = sectionDungeon,
	})

	-- Objective Tracker
	local objEnable = addon.functions.SettingsCreateCheckbox(cChar, {
		var = "mythicPlusEnableObjectiveTracker",
		text = LMP["mythicPlusEnableObjectiveTracker"],
		desc = LMP["mythicPlusEnableObjectiveTrackerDesc"],
		func = function(v)
			addon.db["mythicPlusEnableObjectiveTracker"] = v
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.setObjectiveFrames then addon.MythicPlus.functions.setObjectiveFrames() end
		end,
		parentSection = sectionDungeon,
	})
	local function isObjectiveEnabled() return objEnable and objEnable.setting and objEnable.setting:GetValue() == true end

	local listObj, orderObj = addon.functions.prepareListForDropdown({ [1] = LMP["HideTracker"], [2] = LMP["collapse"] })
	addon.functions.SettingsCreateDropdown(cChar, {
		var = "mythicPlusObjectiveTrackerSetting",
		text = LMP["mythicPlusObjectiveTrackerSetting"],
		type = Settings.VarType.Number,
		default = (addon.db and addon.db["mythicPlusObjectiveTrackerSetting"]) or 1,
		list = listObj,
		order = orderObj,
		get = function() return (addon.db and addon.db["mythicPlusObjectiveTrackerSetting"]) or 1 end,
		set = function(value)
			addon.db["mythicPlusObjectiveTrackerSetting"] = value
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.setObjectiveFrames then addon.MythicPlus.functions.setObjectiveFrames() end
		end,
		parent = true,
		element = objEnable.element,
		parentCheck = isObjectiveEnabled,
		parentSection = sectionDungeon,
	})

	-- BR Tracker
	addon.functions.SettingsCreateCheckbox(cChar, {
		var = "mythicPlusBRTrackerEnabled",
		text = LMP["mythicPlusBRTrackerEnabled"],
		desc = LMP["mythicPlusBRTrackerEditModeHint"],
		func = function(v)
			addon.db["mythicPlusBRTrackerEnabled"] = v
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.createBRFrame then
				addon.MythicPlus.functions.createBRFrame()
			elseif addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.setObjectiveFrames then
				addon.MythicPlus.functions.setObjectiveFrames()
			end
		end,
		parentSection = sectionDungeon,
	})
end

data = {
	{
		var = "autoChooseDelvePower",
		text = L["autoChooseDelvePower"],
		func = function(self, _, value) addon.db["autoChooseDelvePower"] = value end,
		parentSection = sectionDungeon,
	},
}
table.sort(data, function(a, b) return a.text < b.text end)

addon.functions.SettingsCreateHeadline(cChar, DELVES_LABEL, { parentSection = sectionDungeon })
addon.functions.SettingsCreateCheckboxes(cChar, data)

-- Group Finder
local sectionGroupFinder = addon.SettingsLayout.gameplayGroupFinderSection
if not sectionGroupFinder then
	sectionGroupFinder = addon.functions.SettingsCreateExpandableSection(cChar, {
		name = L["GroupFinder"],
		expanded = false,
		colorizeTitle = false,
	})
	addon.SettingsLayout.gameplayGroupFinderSection = sectionGroupFinder
end

data = {
	{
		text = L["groupfinderAppText"],
		var = "groupfinderAppText",
		func = function(value)
			addon.db["groupfinderAppText"] = value
			toggleGroupApplication(value)
		end,
		parentSection = sectionGroupFinder,
	},
	{
		text = L["groupfinderMoveResetButton"],
		var = "groupfinderMoveResetButton",
		func = function(value)
			addon.db["groupfinderMoveResetButton"] = value
			toggleLFGFilterPosition()
		end,
		parentSection = sectionGroupFinder,
	},
	{
		text = L["groupfinderSkipRoleSelect"],
		var = "groupfinderSkipRoleSelect",
		func = function(value) addon.db["groupfinderSkipRoleSelect"] = value end,
		desc = L["interruptWithShift"],
		parentSection = sectionGroupFinder,
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
				parentSection = sectionGroupFinder,
			},
		},
	},
	{
		var = "persistSignUpNote",
		text = L["Persist LFG signup note"],
		func = function(value) addon.db["persistSignUpNote"] = value end,
		parentSection = sectionGroupFinder,
	},
	{
		var = "skipSignUpDialog",
		text = L["Quick signup"],
		func = function(value) addon.db["skipSignUpDialog"] = value end,
		parentSection = sectionGroupFinder,
	},
	{
		var = "lfgSortByRio",
		text = L["lfgSortByRio"],
		func = function(value) addon.db["lfgSortByRio"] = value end,
		parentSection = sectionGroupFinder,
	},
	{
		var = "enableChatIMRaiderIO",
		text = L["enableChatIMRaiderIO"],
		func = function(value) addon.db["enableChatIMRaiderIO"] = value end,
		parentSection = sectionGroupFinder,
	},
}

if keystoneEnable then
	table.insert(data, {
		var = "groupfinderShowPartyKeystone",
		text = LMP["groupfinderShowPartyKeystone"],
		desc = LMP["groupfinderShowPartyKeystoneDesc"],
		func = function(v)
			addon.db["groupfinderShowPartyKeystone"] = v
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.togglePartyKeystone then addon.MythicPlus.functions.togglePartyKeystone() end
		end,
		parent = true,
		element = keystoneEnable.element,
		parentCheck = isKeystoneEnabled,
		parentSection = sectionGroupFinder,
	})
end

table.insert(data, {
	var = "groupfinderShowDungeonScoreFrame",
	text = LMP["groupfinderShowDungeonScoreFrame"]:format(DUNGEON_SCORE),
	func = function(v)
		addon.db["groupfinderShowDungeonScoreFrame"] = v
		if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.toggleFrame then addon.MythicPlus.functions.toggleFrame() end
	end,
	parentSection = sectionGroupFinder,
})

table.insert(data, {
	var = "mythicPlusEnableDungeonFilter",
	text = LMP["mythicPlusEnableDungeonFilter"],
	desc = LMP["mythicPlusEnableDungeonFilterDesc"]:format(REPORT_GROUP_FINDER_ADVERTISEMENT),
	func = function(v)
		addon.db["mythicPlusEnableDungeonFilter"] = v
		if addon.MythicPlus and addon.MythicPlus.functions then
			if v and addon.MythicPlus.functions.addDungeonFilter then
				addon.MythicPlus.functions.addDungeonFilter()
			elseif not v and addon.MythicPlus.functions.removeDungeonFilter then
				addon.MythicPlus.functions.removeDungeonFilter()
			end
		end
	end,
	parentSection = sectionGroupFinder,
	children = {
		{
			var = "mythicPlusEnableDungeonFilterClearReset",
			text = LMP["mythicPlusEnableDungeonFilterClearReset"],
			func = function(v) addon.db["mythicPlusEnableDungeonFilterClearReset"] = v end,
			parentCheck = function()
				return addon.SettingsLayout.elements["mythicPlusEnableDungeonFilter"]
					and addon.SettingsLayout.elements["mythicPlusEnableDungeonFilter"].setting
					and addon.SettingsLayout.elements["mythicPlusEnableDungeonFilter"].setting:GetValue() == true
			end,
			parent = true,
			default = false,
			type = Settings.VarType.Boolean,
			sType = "checkbox",
			parentSection = sectionGroupFinder,
		},
	},
})

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cChar, data)

-- Death & Resurrect
local sectionDeathRes = addon.SettingsLayout.gameplayDeathResSection
if not sectionDeathRes then
	sectionDeathRes = addon.functions.SettingsCreateExpandableSection(cChar, {
		name = L["DeathResurrect"],
		expanded = false,
		colorizeTitle = false,
	})
	addon.SettingsLayout.gameplayDeathResSection = sectionDeathRes
end

-- GENERAL

data = {
	var = "timeoutRelease",
	text = L["timeoutRelease"],
	func = function(value) addon.db["timeoutRelease"] = value end,
	parentSection = sectionDeathRes,
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
	parentSection = sectionDeathRes,
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
	parentSection = sectionDeathRes,
})

local function isAutoAcceptResurrectionEnabled()
	return addon.SettingsLayout.elements["autoAcceptResurrection"]
		and addon.SettingsLayout.elements["autoAcceptResurrection"].setting
		and addon.SettingsLayout.elements["autoAcceptResurrection"].setting:GetValue() == true
end

addon.functions.SettingsCreateCheckbox(cChar, {
	var = "autoAcceptResurrection",
	text = L["autoAcceptResurrection"],
	desc = L["autoAcceptResurrectionDesc"],
	func = function(value) addon.db["autoAcceptResurrection"] = value end,
	parentSection = sectionDeathRes,
	children = {
		{
			var = "autoAcceptResurrectionExcludeCombat",
			text = L["autoAcceptResurrectionExcludeCombat"],
			func = function(v) addon.db["autoAcceptResurrectionExcludeCombat"] = v end,
			parentCheck = isAutoAcceptResurrectionEnabled,
			parent = true,
			default = true,
			type = Settings.VarType.Boolean,
			sType = "checkbox",
			parentSection = sectionDeathRes,
		},
		{
			var = "autoAcceptResurrectionExcludeAfterlife",
			text = L["autoAcceptResurrectionExcludeAfterlife"],
			func = function(v) addon.db["autoAcceptResurrectionExcludeAfterlife"] = v end,
			parentCheck = isAutoAcceptResurrectionEnabled,
			parent = true,
			default = true,
			type = Settings.VarType.Boolean,
			sType = "checkbox",
			parentSection = sectionDeathRes,
		},
	},
})

local function isAutoReleasePvPEnabled()
	return addon.SettingsLayout.elements["autoReleasePvP"] and addon.SettingsLayout.elements["autoReleasePvP"].setting and addon.SettingsLayout.elements["autoReleasePvP"].setting:GetValue() == true
end

addon.functions.SettingsCreateCheckbox(cChar, {
	var = "autoReleasePvP",
	text = L["autoReleasePvP"],
	desc = L["autoReleasePvPDesc"],
	func = function(value) addon.db["autoReleasePvP"] = value end,
	parentSection = sectionDeathRes,
	children = {
		{
			var = "autoReleasePvPDelay",
			text = L["autoReleasePvPDelay"],
			desc = L["autoReleasePvPDelayDesc"],
			get = function() return addon.db and addon.db.autoReleasePvPDelay or 0 end,
			set = function(value) addon.db["autoReleasePvPDelay"] = value end,
			min = 0,
			max = 3000,
			step = 100,
			parentCheck = isAutoReleasePvPEnabled,
			parent = true,
			default = 0,
			sType = "slider",
			parentSection = sectionDeathRes,
		},
		{
			var = "autoReleasePvPExcludeAlterac",
			text = L["autoReleasePvPExcludeAlterac"],
			func = function(v) addon.db["autoReleasePvPExcludeAlterac"] = v end,
			parentCheck = isAutoReleasePvPEnabled,
			parent = true,
			default = false,
			type = Settings.VarType.Boolean,
			sType = "checkbox",
			parentSection = sectionDeathRes,
		},
		{
			var = "autoReleasePvPExcludeWintergrasp",
			text = L["autoReleasePvPExcludeWintergrasp"],
			func = function(v) addon.db["autoReleasePvPExcludeWintergrasp"] = v end,
			parentCheck = isAutoReleasePvPEnabled,
			parent = true,
			default = false,
			type = Settings.VarType.Boolean,
			sType = "checkbox",
			parentSection = sectionDeathRes,
		},
		{
			var = "autoReleasePvPExcludeTolBarad",
			text = L["autoReleasePvPExcludeTolBarad"],
			func = function(v) addon.db["autoReleasePvPExcludeTolBarad"] = v end,
			parentCheck = isAutoReleasePvPEnabled,
			parent = true,
			default = false,
			type = Settings.VarType.Boolean,
			sType = "checkbox",
			parentSection = sectionDeathRes,
		},
		{
			var = "autoReleasePvPExcludeAshran",
			text = L["autoReleasePvPExcludeAshran"],
			func = function(v) addon.db["autoReleasePvPExcludeAshran"] = v end,
			parentCheck = isAutoReleasePvPEnabled,
			parent = true,
			default = false,
			type = Settings.VarType.Boolean,
			sType = "checkbox",
			parentSection = sectionDeathRes,
		},
	},
})

-- Markers
local sectionMarkers = addon.SettingsLayout.gameplayMarkersSection
if not sectionMarkers then
	sectionMarkers = addon.functions.SettingsCreateExpandableSection(cChar, {
		name = L["Markers"],
		expanded = false,
		colorizeTitle = false,
	})
	addon.SettingsLayout.gameplayMarkersSection = sectionMarkers
end

-- Auto Marker (Combat & Dungeon)
if cChar and sectionMarkers and not addon.variables.isMidnight then
	-- TODO remove in midnight
	local cAuto = cChar
	local sectionAuto = sectionMarkers
	addon.functions.SettingsCreateHeadline(cAuto, LMP["AutoMark"], { parentSection = sectionAuto })
	if LMP["autoMarkMidnightWarning"] then addon.functions.SettingsCreateText(cAuto, LMP["autoMarkMidnightWarning"], { parentSection = sectionAuto }) end
	if LMP["autoMarkTankExplanation"] then
		addon.functions.SettingsCreateText(cAuto, "|cffffd700" .. LMP["autoMarkTankExplanation"]:format(TANK, COMMUNITY_MEMBER_ROLE_NAME_LEADER, TANK) .. "|r", { parentSection = sectionAuto })
	end

	local autoMarkTank = addon.functions.SettingsCreateCheckbox(cAuto, {
		var = "autoMarkTankInDungeon",
		text = LMP["autoMarkTankInDungeon"]:format(TANK),
		func = function(v) addon.db["autoMarkTankInDungeon"] = v end,
		parentSection = sectionAuto,
	})
	local function isTankEnabled() return autoMarkTank and autoMarkTank.setting and autoMarkTank.setting:GetValue() == true end

	local raidIconList = {
		[1] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:20|t",
		[2] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_2:20|t",
		[3] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:20|t",
		[4] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_4:20|t",
		[5] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_5:20|t",
		[6] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_6:20|t",
		[7] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:20|t",
		[8] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:20|t",
	}
	local iconOrder = { 1, 2, 3, 4, 5, 6, 7, 8 }

	addon.functions.SettingsCreateDropdown(cAuto, {
		var = "autoMarkTankInDungeonMarker",
		text = LMP["autoMarkTankInDungeonMarker"],
		type = Settings.VarType.Number,
		list = raidIconList,
		listOrder = iconOrder,
		default = (addon.db and addon.db["autoMarkTankInDungeonMarker"]) or 6,
		get = function() return (addon.db and addon.db["autoMarkTankInDungeonMarker"]) or 1 end,
		set = function(value)
			if value == addon.db["autoMarkHealerInDungeonMarker"] then
				print("|cff00ff98Enhance QoL|r: " .. LMP["markerAlreadyUsed"]:format(HEALER))
				return
			end
			addon.db["autoMarkTankInDungeonMarker"] = value
		end,
		parent = true,
		element = autoMarkTank.element,
		parentCheck = isTankEnabled,
		parentSection = sectionAuto,
	})

	local autoMarkHealer = addon.functions.SettingsCreateCheckbox(cAuto, {
		var = "autoMarkHealerInDungeon",
		text = LMP["autoMarkHealerInDungeon"]:format(HEALER),
		func = function(v) addon.db["autoMarkHealerInDungeon"] = v end,
		notify = "autoMarkTankInDungeon",
		parentSection = sectionAuto,
	})
	local function isHealerEnabled() return autoMarkHealer and autoMarkHealer.setting and autoMarkHealer.setting:GetValue() == true end

	addon.functions.SettingsCreateDropdown(cAuto, {
		var = "autoMarkHealerInDungeonMarker",
		text = LMP["autoMarkHealerInDungeonMarker"],
		type = Settings.VarType.Number,
		list = raidIconList,
		listOrder = iconOrder,
		default = (addon.db and addon.db["autoMarkHealerInDungeonMarker"]) or 5,
		get = function() return (addon.db and addon.db["autoMarkHealerInDungeonMarker"]) or 8 end,
		set = function(value)
			if value == addon.db["autoMarkTankInDungeonMarker"] then
				print("|cff00ff98Enhance QoL|r: " .. LMP["markerAlreadyUsed"]:format(TANK))
				return
			end
			addon.db["autoMarkHealerInDungeonMarker"] = value
		end,
		parent = true,
		element = autoMarkHealer.element,
		parentCheck = isHealerEnabled,
		parentSection = sectionAuto,
	})

	addon.functions.SettingsCreateCheckbox(cAuto, {
		var = "mythicPlusNoHealerMark",
		text = LMP["mythicPlusNoHealerMark"],
		func = function(v) addon.db["mythicPlusNoHealerMark"] = v end,
		parentSection = sectionAuto,
	})

	local excludeOptions = {
		{ value = "normal", text = PLAYER_DIFFICULTY1, db = "mythicPlusIgnoreNormal" },
		{ value = "heroic", text = PLAYER_DIFFICULTY2, db = "mythicPlusIgnoreHeroic" },
		{ value = "mythic", text = PLAYER_DIFFICULTY6, db = "mythicPlusIgnoreMythic" },
		{ value = "timewalking", text = PLAYER_DIFFICULTY_TIMEWALKER, db = "mythicPlusIgnoreTimewalking" },
		{ value = "event", text = BATTLE_PET_SOURCE_7, db = "mythicPlusIgnoreEvent" },
	}

	addon.functions.SettingsCreateMultiDropdown(cAuto, {
		var = "autoMarkIgnoreDifficulties",
		text = LMP["Exclude"] or "Exclude",
		options = excludeOptions,
		isSelectedFunc = function(key)
			for _, opt in ipairs(excludeOptions) do
				if opt.value == key then return addon.db[opt.db] == true end
			end
			return false
		end,
		setSelectedFunc = function(key, shouldSelect)
			for _, opt in ipairs(excludeOptions) do
				if opt.value == key then
					addon.db[opt.db] = shouldSelect and true or false
					break
				end
			end
		end,
		parent = true,
		parentCheck = function()
			return addon.SettingsLayout.elements["autoMarkHealerInDungeon"]
					and addon.SettingsLayout.elements["autoMarkHealerInDungeon"].setting
					and addon.SettingsLayout.elements["autoMarkHealerInDungeon"].setting:GetValue() == true
				or addon.SettingsLayout.elements["autoMarkTankInDungeon"]
					and addon.SettingsLayout.elements["autoMarkTankInDungeon"].setting
					and addon.SettingsLayout.elements["autoMarkTankInDungeon"].setting:GetValue() == true
		end,
		element = addon.SettingsLayout.elements["autoMarkTankInDungeon"].element,
		parentSection = sectionAuto,
	})
end

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
