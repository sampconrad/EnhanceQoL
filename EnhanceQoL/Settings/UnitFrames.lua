local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local cUnitFrame = addon.functions.SettingsCreateCategory(nil, UNITFRAME_LABEL, nil, "UnitFrame")
addon.SettingsLayout.unitFrameCategory = cUnitFrame
addon.functions.SettingsCreateHeadline(cUnitFrame, COMBAT_TEXT_LABEL)

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
	},
	{
		var = "hideHitIndicatorPet",
		text = L["hideHitIndicatorPet"],
		func = function(v)
			addon.db["hideHitIndicatorPet"] = v
			if v and PetHitIndicator then PetHitIndicator:Hide() end
		end,
	},
}
addon.functions.SettingsCreateCheckboxes(cUnitFrame, data)

addon.functions.SettingsCreateHeadline(cUnitFrame, L["Health Text"])

addon.functions.SettingsCreateText(cUnitFrame, "|cff99e599" .. string.format(L["HealthTextExplain2"], VIDEO_OPTIONS_DISABLED) .. "|r")

local healthTextOrder = { "OFF", "PERCENT", "ABS", "BOTH" }
local healthTextOptions = {
	OFF = VIDEO_OPTIONS_DISABLED,
	PERCENT = STATUS_TEXT_PERCENT,
	ABS = STATUS_TEXT_VALUE,
	BOTH = STATUS_TEXT_BOTH,
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
})

addon.functions.SettingsCreateHeadline(cUnitFrame, (L["UnitFrameUFExplain"]:format(_G.RAID or "RAID", _G.PARTY or "Party", _G.PLAYER or "Player")))

data = {
	{
		var = "showLeaderIconRaidFrame",
		text = L["showLeaderIconRaidFrame"],
		func = function(v)
			addon.db["showLeaderIconRaidFrame"] = v
			if v then
				addon.functions.setLeaderIcon()
			else
				addon.functions.removeLeaderIcon()
			end
		end,
	},
	{
		var = "hidePartyFrameTitle",
		text = L["hidePartyFrameTitle"],
		func = function(v)
			addon.db["hidePartyFrameTitle"] = v
			addon.functions.togglePartyFrameTitle(v)
		end,
	},
	{
		var = "hideRestingGlow",
		text = L["hideRestingGlow"],
		func = function(v)
			addon.db["hideRestingGlow"] = v
			if addon.functions.ApplyRestingVisuals then addon.functions.ApplyRestingVisuals() end
		end,
	},
	{
		var = "unitFrameTruncateNames",
		text = L["unitFrameTruncateNames"],
		func = function(v)
			addon.db["unitFrameTruncateNames"] = v
			addon.functions.updateUnitFrameNames()
		end,
		children = {
			{
				var = "unitFrameMaxNameLength",
				text = L["unitFrameMaxNameLength"],
				get = function() return addon.db and addon.db.unitFrameMaxNameLength or 6 end,
				set = function(val)
					addon.db["unitFrameMaxNameLength"] = val
					addon.functions.updateUnitFrameNames()
				end,
				min = 1,
				max = 20,
				step = 1,
				default = 6,
				sType = "slider",
				parent = true,
				parentCheck = function()
					return addon.SettingsLayout.elements["unitFrameTruncateNames"]
						and addon.SettingsLayout.elements["unitFrameTruncateNames"].setting
						and addon.SettingsLayout.elements["unitFrameTruncateNames"].setting:GetValue() == true
				end,
			},
		},
	},
	{
		var = "unitFrameScaleEnabled",
		text = L["unitFrameScaleEnable"],
		func = function(v)
			addon.db["unitFrameScaleEnabled"] = v
			addon.functions.updatePartyFrameScale()
			if not v then CompactPartyFrame:SetScale(1) end
		end,
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
			},
		},
	},
}
table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cUnitFrame, data)

addon.functions.SettingsCreateHeadline(cUnitFrame, L["CastBars2"])

addon.functions.SettingsCreateMultiDropdown(cUnitFrame, {
	var = "hiddenCastBars",
	text = L["castBarsToHide2"],
	options = {
		{ value = "PlayerCastingBarFrame", text = PLAYER },
		{ value = "TargetFrameSpellBar", text = TARGET },
		{ value = "FocusFrameSpellBar", text = FOCUS },
	},
	isSelectedFunc = function(key)
		if not key then return false end
		if addon.db.hiddenCastBars and addon.db.hiddenCastBars[key] then return true end

		return false
	end,
	setSelectedFunc = function(key, shouldSelect)
		addon.db.hiddenCastBars = addon.db.hiddenCastBars or {}
		addon.db.hiddenCastBars[key] = shouldSelect and true or false
		addon.functions.ApplyCastBarVisibility()
	end,
})

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
