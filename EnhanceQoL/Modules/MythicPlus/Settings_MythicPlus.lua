local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.MythicPlus = addon.MythicPlus or {}
addon.MythicPlus.functions = addon.MythicPlus.functions or {}
addon.MythicPlus.variables = addon.MythicPlus.variables or {}

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_MythicPlus")
local LSM = LibStub("LibSharedMedia-3.0")
local wipe = wipe

local function buildSettings()
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

-- Keybinding: World Map Teleport panel
if addon.functions.FindBindingIndex then
	local bind = addon.functions.FindBindingIndex({ EQOL_TOGGLE_WORLDMAP_TELEPORT = true })
	if bind and next(bind) then
		local section = addon.functions.SettingsCreateExpandableSection(cTeleports, {
			name = L["teleportsWorldMapBinding"],
			expanded = true,
			colorizeTitle = false,
		})
		for _, idx in pairs(bind) do
			addon.functions.SettingsCreateKeybind(cTeleports, idx, section)
		end
	end
end

-- Talent Reminder (own group)
local cTalent = addon.functions.SettingsCreateCategory(nil, L["TalentReminder"], nil, "TalentReminder")
if cTalent then
	local sectionTalent = addon.functions.SettingsCreateExpandableSection(cTalent, {
		name = L["TalentReminder"],
		expanded = true,
		colorizeTitle = false,
	})

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
		parentSection = sectionTalent,
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
		parentSection = sectionTalent,
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
		parentSection = sectionTalent,
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
		parentSection = sectionTalent,
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
		parentSection = sectionTalent,
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
		parentSection = sectionTalent,
	})

	addon.functions.SettingsAttachNotify(talentEnable.setting, "talentReminderSoundOnDifference")
	addon.functions.SettingsAttachNotify(talentEnable.setting, "talentReminderUseCustomSound")
	addon.functions.SettingsAttachNotify(soundDifference.setting, "talentReminderUseCustomSound")

	addon.functions.SettingsCreateText(cTalent, "|cff99e599" .. L["talentReminderHint"]:format(CRF_EDIT_MODE) .. "|r", { parentSection = sectionTalent })

	if TalentLoadoutEx then
		addon.functions.SettingsCreateText(cTalent, "|cffffd700" .. L["labelExplainedlineTLE"] .. "|r", { parentSection = sectionTalent })
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
			parentSection = sectionTalent,
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

function addon.MythicPlus.functions.InitSettings()
	if addon.MythicPlus.variables.settingsBuilt then return end
	if not addon.db or not addon.functions or not addon.functions.SettingsCreateCategory then return end
	buildSettings()
	addon.MythicPlus.variables.settingsBuilt = true
end
