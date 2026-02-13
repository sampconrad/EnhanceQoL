local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local getCVarOptionState = addon.functions.GetCVarOptionState or function() return false end
local setCVarOptionState = addon.functions.SetCVarOptionState or function() end

local cUnitFrame = addon.SettingsLayout.rootUI

local expandable = addon.functions.SettingsCreateExpandableSection(cUnitFrame, {
	name = UNITFRAME_LABEL,
	expanded = false,
	colorizeTitle = false,
})
addon.SettingsLayout.expUnitFrames = expandable

local function isEQoLUnitEnabled(unit)
	local db = addon.db and addon.db.ufFrames
	if not db then return false end
	if unit == "boss" then
		for i = 1, 5 do
			local cfg = db["boss" .. i]
			if cfg and cfg.enabled then return true end
		end
		return false
	end
	local cfg = db[unit]
	return cfg and cfg.enabled == true
end

local function expandWith(predicate)
	return function()
		if expandable and expandable.IsExpanded and expandable:IsExpanded() == false then return false end
		return predicate()
	end
end

addon.functions.SettingsCreateHeadline(cUnitFrame, COMBAT_TEXT_LABEL, { parentSection = expandable })

local data = {
	{
		var = "hideHitIndicatorPlayer",
		text = L["hideHitIndicatorPlayer"],
		func = function(v)
			addon.db["hideHitIndicatorPlayer"] = v
			if v then
				PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator:Hide()
			else
				PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator:Show()
			end
		end,
		parentSection = expandable,
	},
	{
		var = "hideHitIndicatorPet",
		text = L["hideHitIndicatorPet"],
		func = function(v)
			addon.db["hideHitIndicatorPet"] = v
			if v and PetHitIndicator then PetHitIndicator:Hide() end
		end,
		parentSection = expandable,
	},
	{
		var = "floatingCombatTextCombatDamage_v2",
		text = L["floatingCombatTextCombatDamage_v2"],
		get = function() return getCVarOptionState("floatingCombatTextCombatDamage_v2") end,
		func = function(value) setCVarOptionState("floatingCombatTextCombatDamage_v2", value) end,
		default = false,
		parentSection = expandable,
	},
	{
		var = "floatingCombatTextCombatHealing_v2",
		text = L["floatingCombatTextCombatHealing_v2"],
		get = function() return getCVarOptionState("floatingCombatTextCombatHealing_v2") end,
		func = function(value) setCVarOptionState("floatingCombatTextCombatHealing_v2", value) end,
		default = false,
		parentSection = expandable,
	},
}
addon.functions.SettingsCreateCheckboxes(cUnitFrame, data)

local function shouldShowHealthTextSection() return not isEQoLUnitEnabled("player") or not isEQoLUnitEnabled("target") or not isEQoLUnitEnabled("boss") end

addon.functions.SettingsCreateHeadline(cUnitFrame, L["Health Text"], {
	parentSection = expandWith(shouldShowHealthTextSection),
})

addon.functions.SettingsCreateText(cUnitFrame, "|cff99e599" .. string.format(L["HealthTextExplain2"], VIDEO_OPTIONS_DISABLED) .. "|r", { parentSection = expandWith(shouldShowHealthTextSection) })

local healthTextOrder = { "OFF", "PERCENT", "ABS", "BOTH", "CURMAX", "CURMAXPERCENT" }
local healthTextOptions = {
	OFF = VIDEO_OPTIONS_DISABLED,
	PERCENT = STATUS_TEXT_PERCENT,
	ABS = STATUS_TEXT_VALUE,
	BOTH = STATUS_TEXT_BOTH,
	CURMAX = L["Current/Max"] or "Current/Max",
	CURMAXPERCENT = L["Current/Max Percent"] or "Current/Max (percent)",
}

addon.functions.SettingsCreateDropdown(cUnitFrame, {
	list = healthTextOptions,
	order = healthTextOrder,
	text = L["PlayerHealthText"],
	get = function() return addon.db["healthTextPlayerMode"] or "OFF" end,
	set = function(key)
		addon.db["healthTextPlayerMode"] = key
		if addon.HealthText and addon.HealthText.SetMode then addon.HealthText:SetMode("player", addon.db["healthTextPlayerMode"]) end
	end,
	default = "OFF",
	var = "healthTextPlayerMode",
	type = Settings.VarType.String,
	sType = "dropdown",
	parentSection = expandWith(function() return not isEQoLUnitEnabled("player") end),
})
addon.functions.SettingsCreateDropdown(cUnitFrame, {
	list = healthTextOptions,
	order = healthTextOrder,
	text = L["TargetHealthText"],
	get = function() return addon.db["healthTextTargetMode"] or "OFF" end,
	set = function(key)
		addon.db["healthTextTargetMode"] = key
		if addon.HealthText and addon.HealthText.SetMode then addon.HealthText:SetMode("target", addon.db["healthTextTargetMode"]) end
	end,
	default = "OFF",
	var = "healthTextTargetMode",
	type = Settings.VarType.String,
	sType = "dropdown",
	parentSection = expandWith(function() return not isEQoLUnitEnabled("target") end),
})
addon.functions.SettingsCreateDropdown(cUnitFrame, {
	list = healthTextOptions,
	order = healthTextOrder,
	text = L["BossHealthText"],
	get = function() return addon.db["healthTextBossMode"] or "OFF" end,
	set = function(key)
		addon.db["healthTextBossMode"] = key
		if addon.HealthText and addon.HealthText.SetMode then addon.HealthText:SetMode("boss", addon.db["healthTextBossMode"]) end
	end,
	default = "OFF",
	var = "healthTextBossMode",
	type = Settings.VarType.String,
	sType = "dropdown",
	parentSection = expandWith(function() return not isEQoLUnitEnabled("boss") end),
})

addon.functions.SettingsCreateHeadline(cUnitFrame, (L["UnitFrameUFExplain"]:format(_G.RAID or "RAID", _G.PARTY or "Party", _G.PLAYER or "Player")), {
	parentSection = expandable,
})

data = {
	{
		var = "raidFramesDisplayClassColor",
		text = L["raidFramesDisplayClassColor"],
		get = function() return getCVarOptionState("raidFramesDisplayClassColor") end,
		func = function(value) setCVarOptionState("raidFramesDisplayClassColor", value) end,
		default = false,
		parentSection = expandable,
	},
	{
		var = "hidePartyFrameTitle",
		text = L["hidePartyFrameTitle"],
		func = function(v)
			addon.db["hidePartyFrameTitle"] = v
			addon.functions.togglePartyFrameTitle(v)
		end,
		parentSection = expandable,
	},
	{
		var = "pvpFramesDisplayClassColor",
		text = L["pvpFramesDisplayClassColor"],
		get = function() return getCVarOptionState("pvpFramesDisplayClassColor") end,
		func = function(value) setCVarOptionState("pvpFramesDisplayClassColor", value) end,
		default = false,
		parentSection = expandable,
	},
	{
		var = "hideRestingGlow",
		text = L["hideRestingGlow"],
		func = function(v)
			addon.db["hideRestingGlow"] = v
			if addon.functions.ApplyRestingVisuals then addon.functions.ApplyRestingVisuals() end
		end,
		parentSection = expandable,
	},
	{
		var = "unitFrameScaleEnabled",
		text = L["unitFrameScaleEnable"],
		func = function(v)
			addon.db["unitFrameScaleEnabled"] = v
			addon.functions.updatePartyFrameScale()
			if not v then CompactPartyFrame:SetScale(1) end
		end,
		parentSection = expandable,
		children = {
			{
				var = "unitFrameScale",
				text = L["unitFrameScale"],
				get = function() return addon.db and addon.db.unitFrameScale or 1 end,
				set = function(val)
					addon.db["unitFrameScale"] = val
					addon.functions.updatePartyFrameScale()
				end,
				min = 0.5,
				max = 3,
				step = 0.05,
				default = 1,
				sType = "slider",
				parent = true,
				parentCheck = function()
					return addon.SettingsLayout.elements["unitFrameScaleEnabled"]
						and addon.SettingsLayout.elements["unitFrameScaleEnabled"].setting
						and addon.SettingsLayout.elements["unitFrameScaleEnabled"].setting:GetValue() == true
				end,
				parentSection = expandable,
			},
		},
	},
}
table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cUnitFrame, data)

----- REGION END

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
