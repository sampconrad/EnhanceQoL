local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_MythicPlus")
local LSM = LibStub("LibSharedMedia-3.0")
local wipe = wipe

local cTeleports = addon.functions.SettingsCreateCategory(nil, L["Teleports"], nil, "Teleports")
addon.SettingsLayout.teleportsCategory = cTeleports

local data = {
	{
		var = "teleportFrame",
		text = L["teleportEnabled"],
		desc = L["teleportEnabledDesc"],
		func = function(v)
			addon.db["teleportFrame"] = v
			addon.MythicPlus.functions.toggleFrame()
		end,
	},
	{
		var = "teleportsWorldMapEnabled",
		text = L["teleportsWorldMapEnabled"],
		desc = L["teleportsWorldMapEnabledDesc"],
		func = function(v) addon.db["teleportsWorldMapEnabled"] = v end,
		children = {
			{
				text = "|cffffd700" .. L["teleportsWorldMapHelp"] .. "|r",
				sType = "hint",
			},
		},
	},
	{
		var = "teleportsWorldMapShowSeason",
		text = L["teleportsWorldMapShowSeason"],
		desc = L["teleportsWorldMapShowSeasonDesc"],
		func = function(v) addon.db["teleportsWorldMapShowSeason"] = v end,
	},
	{
		var = "portalHideMissing",
		text = L["portalHideMissing"],
		func = function(v) addon.db["portalHideMissing"] = v end,
	},
}
-- TODO bug in tooltip in midnight beta - remove for now
if not addon.variables.isMidnight then table.insert(data, {
	text = L["portalShowTooltip"],
	var = "portalShowTooltip",
	func = function(value) addon.db["portalShowTooltip"] = value end,
}) end
table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cTeleports, data)

-- Potion Tracker (Combat & Dungeon)
local cPotion = addon.SettingsLayout.characterInspectCategory
if cPotion then
	addon.functions.SettingsCreateHeadline(cPotion, L["Potion Tracker"])
	if L["potionTrackerMidnightWarning"] then addon.functions.SettingsCreateText(cPotion, L["potionTrackerMidnightWarning"]) end

	local potionEnable = addon.functions.SettingsCreateCheckbox(cPotion, {
		var = "potionTracker",
		text = L["potionTracker"],
		desc = L["potionTrackerHeadline"],
		func = function(v)
			addon.db["potionTracker"] = v
			if v then
				if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.updateBars then addon.MythicPlus.functions.updateBars() end
			else
				if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.resetCooldownBars then addon.MythicPlus.functions.resetCooldownBars() end
				if addon.MythicPlus and addon.MythicPlus.anchorFrame and addon.MythicPlus.anchorFrame.Hide then addon.MythicPlus.anchorFrame:Hide() end
			end
		end,
	})

	local function isPotionEnabled() return potionEnable and potionEnable.setting and potionEnable.setting:GetValue() == true end

	local potionOptions = {
		{
			var = "potionTrackerUpwardsBar",
			text = L["potionTrackerUpwardsBar"],
			func = function(v)
				addon.db["potionTrackerUpwardsBar"] = v
				if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.updateBars then addon.MythicPlus.functions.updateBars() end
			end,
		},
		{
			var = "potionTrackerClassColor",
			text = L["potionTrackerClassColor"],
			func = function(v) addon.db["potionTrackerClassColor"] = v end,
		},
		{
			var = "potionTrackerDisableRaid",
			text = L["potionTrackerDisableRaid"],
			func = function(v)
				addon.db["potionTrackerDisableRaid"] = v
				if v == true and UnitInRaid("player") and addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.resetCooldownBars then
					addon.MythicPlus.functions.resetCooldownBars()
				end
			end,
		},
		{
			var = "potionTrackerShowTooltip",
			text = L["potionTrackerShowTooltip"],
			func = function(v) addon.db["potionTrackerShowTooltip"] = v end,
		},
		{
			var = "potionTrackerHealingPotions",
			text = L["potionTrackerHealingPotions"],
			func = function(v) addon.db["potionTrackerHealingPotions"] = v end,
		},
		{
			var = "potionTrackerOffhealing",
			text = L["potionTrackerOffhealing"],
			func = function(v) addon.db["potionTrackerOffhealing"] = v end,
		},
	}

	for _, entry in ipairs(potionOptions) do
		entry.parent = true
		entry.element = potionEnable.element
		entry.parentCheck = isPotionEnabled
		addon.functions.SettingsCreateCheckbox(cPotion, entry)
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

	addon.functions.SettingsCreateDropdown(cPotion, {
		var = "potionTrackerBarTexture",
		text = L["Bar Texture"],
		default = "DEFAULT",
		listFunc = buildPotionTextureOptions,
		order = potionTextureOrder,
		get = function()
			local cur = addon.db["potionTrackerBarTexture"] or "DEFAULT"
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
	})

	addon.functions.SettingsCreateButton(cPotion, {
		var = "potionTrackerAnchor",
		text = L["Toggle Anchor"],
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
	})
end

-- Mythic+ & Raid (Combat & Dungeon)
local cMythic = addon.SettingsLayout.characterInspectCategory
if cMythic then
	addon.functions.SettingsCreateHeadline(cMythic, PLAYER_DIFFICULTY_MYTHIC_PLUS .. " & " .. RAID)

	-- Keystone Helper
	local keystoneEnable = addon.functions.SettingsCreateCheckbox(cMythic, {
		var = "enableKeystoneHelper",
		text = L["enableKeystoneHelper"],
		desc = L["enableKeystoneHelperDesc"],
		func = function(v)
			addon.db["enableKeystoneHelper"] = v
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.toggleFrame then addon.MythicPlus.functions.toggleFrame() end
		end,
	})
	local function isKeystoneEnabled() return keystoneEnable and keystoneEnable.setting and keystoneEnable.setting:GetValue() == true end

	local keystoneChildren = {
		{ var = "autoInsertKeystone", text = L["Automatically insert keystone"], func = function(v) addon.db["autoInsertKeystone"] = v end },
		{ var = "closeBagsOnKeyInsert", text = L["Close all bags on keystone insert"], func = function(v) addon.db["closeBagsOnKeyInsert"] = v end },
		{ var = "autoKeyStart", text = L["autoKeyStart"], func = function(v) addon.db["autoKeyStart"] = v end },
		{
			var = "groupfinderShowPartyKeystone",
			text = L["groupfinderShowPartyKeystone"],
			desc = L["groupfinderShowPartyKeystoneDesc"],
			func = function(v)
				addon.db["groupfinderShowPartyKeystone"] = v
				if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.togglePartyKeystone then addon.MythicPlus.functions.togglePartyKeystone() end
			end,
		},
		{
			var = "mythicPlusShowChestTimers",
			text = L["mythicPlusShowChestTimers"],
			desc = L["mythicPlusShowChestTimersDesc"],
			func = function(v) addon.db["mythicPlusShowChestTimers"] = v end,
		},
	}
	for _, entry in ipairs(keystoneChildren) do
		entry.parent = true
		entry.element = keystoneEnable.element
		entry.parentCheck = isKeystoneEnabled
		addon.functions.SettingsCreateCheckbox(cMythic, entry)
	end

	local listPull, orderPull = addon.functions.prepareListForDropdown({
		[1] = L["None"],
		[2] = L["Blizzard Pull Timer"],
		[3] = L["DBM / BigWigs Pull Timer"],
		[4] = L["Both"],
	})
	addon.functions.SettingsCreateDropdown(cMythic, {
		var = "PullTimerType",
		text = L["PullTimer"],
		type = Settings.VarType.Number,
		default = 2,
		list = listPull,
		order = orderPull,
		get = function() return addon.db["PullTimerType"] or 1 end,
		set = function(value) addon.db["PullTimerType"] = value end,
		parent = true,
		element = keystoneEnable.element,
		parentCheck = isKeystoneEnabled,
	})

	addon.functions.SettingsCreateCheckbox(cMythic, {
		var = "noChatOnPullTimer",
		text = L["noChatOnPullTimer"],
		func = function(v) addon.db["noChatOnPullTimer"] = v end,
		parent = true,
		element = keystoneEnable.element,
		parentCheck = isKeystoneEnabled,
	})

	addon.functions.SettingsCreateSlider(cMythic, {
		var = "pullTimerLongTime",
		text = L["sliderLongTime"],
		min = 0,
		max = 60,
		step = 1,
		default = 10,
		get = function() return addon.db["pullTimerLongTime"] or 10 end,
		set = function(val) addon.db["pullTimerLongTime"] = val end,
		parent = true,
		element = keystoneEnable.element,
		parentCheck = isKeystoneEnabled,
	})

	addon.functions.SettingsCreateSlider(cMythic, {
		var = "pullTimerShortTime",
		text = L["sliderShortTime"],
		min = 0,
		max = 60,
		step = 1,
		default = 5,
		get = function() return addon.db["pullTimerShortTime"] or 5 end,
		set = function(val) addon.db["pullTimerShortTime"] = val end,
		parent = true,
		element = keystoneEnable.element,
		parentCheck = isKeystoneEnabled,
	})

	-- Objective Tracker
	local objEnable = addon.functions.SettingsCreateCheckbox(cMythic, {
		var = "mythicPlusEnableObjectiveTracker",
		text = L["mythicPlusEnableObjectiveTracker"],
		desc = L["mythicPlusEnableObjectiveTrackerDesc"],
		func = function(v)
			addon.db["mythicPlusEnableObjectiveTracker"] = v
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.setObjectiveFrames then addon.MythicPlus.functions.setObjectiveFrames() end
		end,
	})
	local function isObjectiveEnabled() return objEnable and objEnable.setting and objEnable.setting:GetValue() == true end

	local listObj, orderObj = addon.functions.prepareListForDropdown({ [1] = L["HideTracker"], [2] = L["collapse"] })
	addon.functions.SettingsCreateDropdown(cMythic, {
		var = "mythicPlusObjectiveTrackerSetting",
		text = L["mythicPlusObjectiveTrackerSetting"],
		type = Settings.VarType.Number,
		default = addon.db["mythicPlusObjectiveTrackerSetting"] or 1,
		list = listObj,
		order = orderObj,
		get = function() return addon.db["mythicPlusObjectiveTrackerSetting"] or 1 end,
		set = function(value)
			addon.db["mythicPlusObjectiveTrackerSetting"] = value
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.setObjectiveFrames then addon.MythicPlus.functions.setObjectiveFrames() end
		end,
		parent = true,
		element = objEnable.element,
		parentCheck = isObjectiveEnabled,
	})

	-- Dungeon Score next to Group Finder
	addon.functions.SettingsCreateCheckbox(cMythic, {
		var = "groupfinderShowDungeonScoreFrame",
		text = L["groupfinderShowDungeonScoreFrame"]:format(DUNGEON_SCORE),
		func = function(v)
			addon.db["groupfinderShowDungeonScoreFrame"] = v
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.toggleFrame then addon.MythicPlus.functions.toggleFrame() end
		end,
	})

	-- BR Tracker
	addon.functions.SettingsCreateCheckbox(cMythic, {
		var = "mythicPlusBRTrackerEnabled",
		text = L["mythicPlusBRTrackerEnabled"],
		desc = L["mythicPlusBRTrackerEditModeHint"],
		func = function(v)
			addon.db["mythicPlusBRTrackerEnabled"] = v
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.createBRFrame then
				addon.MythicPlus.functions.createBRFrame()
			elseif addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.setObjectiveFrames then
				addon.MythicPlus.functions.setObjectiveFrames()
			end
		end,
	})

	-- Talent Reminder (own group)
	local cTalent = addon.functions.SettingsCreateCategory(nil, L["TalentReminder"], nil, "TalentReminder")
	if cTalent then
		addon.functions.SettingsCreateHeadline(cTalent, L["TalentReminder"])

		addon.MythicPlus.functions.getAllLoadouts()
		if #addon.MythicPlus.variables.seasonMapInfo == 0 then addon.MythicPlus.functions.createSeasonInfo() end

		local function ensureTalentSettings(specID)
			local guid = addon.variables.unitPlayerGUID
			if not guid or not specID then return end
			addon.db["talentReminderSettings"] = addon.db["talentReminderSettings"] or {}
			addon.db["talentReminderSettings"][guid] = addon.db["talentReminderSettings"][guid] or {}
			addon.db["talentReminderSettings"][guid][specID] = addon.db["talentReminderSettings"][guid][specID] or {}
			return addon.db["talentReminderSettings"][guid][specID]
		end

		local talentLoadoutOrders = {}
		local function buildTalentLoadoutList(specID)
			local source = (specID and addon.MythicPlus.variables.knownLoadout and addon.MythicPlus.variables.knownLoadout[specID]) or {}
			local normalized = {}
			for key, value in pairs(source) do
				normalized[tostring(key)] = value
			end
			if not normalized["0"] then normalized["0"] = "" end
			local list, order = addon.functions.prepareListForDropdown(normalized)
			local orderTarget = talentLoadoutOrders[specID]
			if orderTarget then
				wipe(orderTarget)
			else
				orderTarget = {}
				talentLoadoutOrders[specID] = orderTarget
			end
			for i, key in ipairs(order) do
				orderTarget[i] = key
			end
			return list
		end

		local function buildTalentSoundOptions()
			local soundList = {}
			if addon.ChatIM and addon.ChatIM.BuildSoundTable and not addon.ChatIM.availableSounds then addon.ChatIM:BuildSoundTable() end
			local soundTable = (addon.ChatIM and addon.ChatIM.availableSounds) or (LSM and LSM:HashTable("sound"))
			for name, file in pairs(soundTable or {}) do
				if type(name) == "string" and name ~= "" then soundList[name] = { value = name, label = name, file = file } end
			end
			return soundList
		end

		local talentEnable = addon.functions.SettingsCreateCheckbox(cTalent, {
			var = "talentReminderEnabled",
			text = L["talentReminderEnabled"],
			desc = L["talentReminderEnabledDesc"]:format(PLAYER_DIFFICULTY6, PLAYER_DIFFICULTY_MYTHIC_PLUS),
			func = function(v)
				addon.db["talentReminderEnabled"] = v
				addon.MythicPlus.functions.checkLoadout()
				addon.MythicPlus.functions.updateActiveTalentText()
			end,
		})
		local function isTalentReminderEnabled() return talentEnable and talentEnable.setting and talentEnable.setting:GetValue() == true end

		addon.functions.SettingsCreateCheckbox(cTalent, {
			var = "talentReminderLoadOnReadyCheck",
			text = L["talentReminderLoadOnReadyCheck"]:format(READY_CHECK),
			func = function(v)
				addon.db["talentReminderLoadOnReadyCheck"] = v
				addon.MythicPlus.functions.checkLoadout()
			end,
			parent = true,
			element = talentEnable.element,
			parentCheck = isTalentReminderEnabled,
		})

		local soundDifference = addon.functions.SettingsCreateCheckbox(cTalent, {
			var = "talentReminderSoundOnDifference",
			text = L["talentReminderSoundOnDifference"],
			func = function(v)
				addon.db["talentReminderSoundOnDifference"] = v
				addon.MythicPlus.functions.checkLoadout()
			end,
			parent = true,
			element = talentEnable.element,
			parentCheck = isTalentReminderEnabled,
		})
		local function isSoundReminderEnabled() return soundDifference and soundDifference.setting and soundDifference.setting:GetValue() == true end

		local customSound = addon.functions.SettingsCreateCheckbox(cTalent, {
			var = "talentReminderUseCustomSound",
			text = L["talentReminderUseCustomSound"],
			func = function(v) addon.db["talentReminderUseCustomSound"] = v end,
			parent = true,
			element = soundDifference.element,
			parentCheck = function()
				return addon.SettingsLayout.elements["talentReminderEnabled"]
					and addon.SettingsLayout.elements["talentReminderEnabled"].setting
					and addon.SettingsLayout.elements["talentReminderEnabled"].setting:GetValue() == true
					and addon.SettingsLayout.elements["talentReminderSoundOnDifference"]
					and addon.SettingsLayout.elements["talentReminderSoundOnDifference"].setting
					and addon.SettingsLayout.elements["talentReminderSoundOnDifference"].setting:GetValue() == true
			end,
		})

		addon.functions.SettingsCreateSoundDropdown(cTalent, {
			var = "talentReminderCustomSoundFile",
			text = L["talentReminderCustomSound"],
			listFunc = buildTalentSoundOptions,
			default = "",
			get = function()
				local value = addon.db["talentReminderCustomSoundFile"]
				return value ~= nil and value or ""
			end,
			set = function(value) addon.db["talentReminderCustomSoundFile"] = value end,
			callback = function(value)
				local soundTable = (addon.ChatIM and addon.ChatIM.availableSounds) or (LSM and LSM:HashTable("sound"))
				local file = soundTable and soundTable[value]
				if file then PlaySoundFile(file, "Master") end
			end,
			parent = true,
			element = customSound.element,
			parentCheck = function() return isTalentReminderEnabled() and isSoundReminderEnabled() and addon.db["talentReminderUseCustomSound"] == true end,
		})

		local showActiveBuild = addon.functions.SettingsCreateCheckbox(cTalent, {
			var = "talentReminderShowActiveBuild",
			text = L["talentReminderShowActiveBuild"],
			func = function(v)
				addon.db["talentReminderShowActiveBuild"] = v
				addon.MythicPlus.functions.updateActiveTalentText()
			end,
			parent = true,
			element = talentEnable.element,
			parentCheck = isTalentReminderEnabled,
		})

		addon.functions.SettingsAttachNotify(talentEnable.setting, "talentReminderSoundOnDifference")
		addon.functions.SettingsAttachNotify(talentEnable.setting, "talentReminderUseCustomSound")
		addon.functions.SettingsAttachNotify(soundDifference.setting, "talentReminderUseCustomSound")

		addon.functions.SettingsCreateText(cTalent, "|cff99e599" .. L["talentReminderHint"]:format(CRF_EDIT_MODE) .. "|r")

		if TalentLoadoutEx then
			addon.functions.SettingsCreateText(cTalent, "|cffffd700" .. L["labelExplainedlineTLE"] .. "|r")
			addon.functions.SettingsCreateButton(cTalent, {
				var = "talentReminderReloadLoadouts",
				text = L["ReloadLoadouts"],
				func = function()
					addon.MythicPlus.functions.getAllLoadouts()
					addon.MythicPlus.functions.checkRemovedLoadout()
				end,
				parent = true,
				element = talentEnable.element,
				parentCheck = isTalentReminderEnabled,
			})
		end

		if #addon.MythicPlus.variables.specNames > 0 and #addon.MythicPlus.variables.seasonMapInfo > 0 then
			for _, specData in ipairs(addon.MythicPlus.variables.specNames) do
				local orderTable = talentLoadoutOrders[specData.value] or {}
				talentLoadoutOrders[specData.value] = orderTable
				local specSection = addon.functions.SettingsCreateExpandableSection(cTalent, {
					name = specData.text,
					expanded = false,
				})
				for _, mapData in ipairs(addon.MythicPlus.variables.seasonMapInfo) do
					addon.functions.SettingsCreateDropdown(cTalent, {
						var = string.format("talentReminder_%s_%s", specData.value, mapData.id),
						text = mapData.name,
						type = Settings.VarType.String,
						default = "0",
						listFunc = function() return buildTalentLoadoutList(specData.value) end,
						order = orderTable,
						get = function()
							local specSettings = ensureTalentSettings(specData.value)
							local current = specSettings and specSettings[mapData.id]
							if type(current) == "number" then return tostring(current) end
							if current == nil then return "0" end
							return current
						end,
						set = function(value)
							local specSettings = ensureTalentSettings(specData.value)
							if not specSettings then return end
							local converted = tonumber(value)
							if converted ~= nil then
								specSettings[mapData.id] = converted
							else
								specSettings[mapData.id] = value
							end
							C_Timer.After(1, function() addon.MythicPlus.functions.checkLoadout() end)
						end,
						parent = true,
						element = talentEnable.element,
						parentCheck = isTalentReminderEnabled,
						parentSection = specSection,
					})
				end
			end
		end
	end

	-- Dungeon Finder filters
	local filterEnable = addon.functions.SettingsCreateCheckbox(cMythic, {
		var = "mythicPlusEnableDungeonFilter",
		text = L["mythicPlusEnableDungeonFilter"],
		desc = L["mythicPlusEnableDungeonFilterDesc"]:format(REPORT_GROUP_FINDER_ADVERTISEMENT),
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
	})
	local function isFilterEnabled() return filterEnable and filterEnable.setting and filterEnable.setting:GetValue() == true end

	addon.functions.SettingsCreateCheckbox(cMythic, {
		var = "mythicPlusEnableDungeonFilterClearReset",
		text = L["mythicPlusEnableDungeonFilterClearReset"],
		func = function(v) addon.db["mythicPlusEnableDungeonFilterClearReset"] = v end,
		parent = true,
		element = filterEnable.element,
		parentCheck = isFilterEnabled,
	})
end

-- Auto Marker (Combat & Dungeon)
if addon.SettingsLayout.characterInspectCategory and not addon.variables.isMidnight then
	-- TODO remove in midnight
	local cAuto = addon.SettingsLayout.characterInspectCategory
	addon.functions.SettingsCreateHeadline(cAuto, L["AutoMark"])
	if L["autoMarkMidnightWarning"] then addon.functions.SettingsCreateText(cAuto, L["autoMarkMidnightWarning"]) end
	if L["autoMarkTankExplanation"] then addon.functions.SettingsCreateText(cAuto, "|cffffd700" .. L["autoMarkTankExplanation"]:format(TANK, COMMUNITY_MEMBER_ROLE_NAME_LEADER, TANK) .. "|r") end

	local autoMarkTank = addon.functions.SettingsCreateCheckbox(cAuto, {
		var = "autoMarkTankInDungeon",
		text = L["autoMarkTankInDungeon"]:format(TANK),
		func = function(v) addon.db["autoMarkTankInDungeon"] = v end,
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
		text = L["autoMarkTankInDungeonMarker"],
		type = Settings.VarType.Number,
		list = raidIconList,
		listOrder = iconOrder,
		default = addon.db["autoMarkTankInDungeonMarker"],
		get = function() return addon.db["autoMarkTankInDungeonMarker"] or 1 end,
		set = function(value)
			if value == addon.db["autoMarkHealerInDungeonMarker"] then
				print("|cff00ff98Enhance QoL|r: " .. L["markerAlreadyUsed"]:format(HEALER))
				return
			end
			addon.db["autoMarkTankInDungeonMarker"] = value
		end,
		parent = true,
		element = autoMarkTank.element,
		parentCheck = isTankEnabled,
	})

	local autoMarkHealer = addon.functions.SettingsCreateCheckbox(cAuto, {
		var = "autoMarkHealerInDungeon",
		text = L["autoMarkHealerInDungeon"]:format(HEALER),
		func = function(v) addon.db["autoMarkHealerInDungeon"] = v end,
		notify = "autoMarkTankInDungeon",
	})
	local function isHealerEnabled() return autoMarkHealer and autoMarkHealer.setting and autoMarkHealer.setting:GetValue() == true end

	addon.functions.SettingsCreateDropdown(cAuto, {
		var = "autoMarkHealerInDungeonMarker",
		text = L["autoMarkHealerInDungeonMarker"],
		type = Settings.VarType.Number,
		list = raidIconList,
		listOrder = iconOrder,
		default = addon.db["autoMarkHealerInDungeonMarker"],
		get = function() return addon.db["autoMarkHealerInDungeonMarker"] or 8 end,
		set = function(value)
			if value == addon.db["autoMarkTankInDungeonMarker"] then
				print("|cff00ff98Enhance QoL|r: " .. L["markerAlreadyUsed"]:format(TANK))
				return
			end
			addon.db["autoMarkHealerInDungeonMarker"] = value
		end,
		parent = true,
		element = autoMarkHealer.element,
		parentCheck = isHealerEnabled,
	})

	addon.functions.SettingsCreateCheckbox(cAuto, {
		var = "mythicPlusNoHealerMark",
		text = L["mythicPlusNoHealerMark"],
		func = function(v) addon.db["mythicPlusNoHealerMark"] = v end,
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
		text = L["Exclude"] or "Exclude",
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
	})
end

----- REGION END

function addon.functions.initTeleports() end

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
