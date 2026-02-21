local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local getCVarOptionState = addon.functions.GetCVarOptionState or function() return false end
local setCVarOptionState = addon.functions.SetCVarOptionState or function() end

local cMapNav = addon.SettingsLayout.rootUI
addon.SettingsLayout.mapNavigationCategory = cMapNav

local refreshWorldMapCoordinates

local mapExpandable = addon.functions.SettingsCreateExpandableSection(cMapNav, {
	name = L["MapNavigation"],
	newTagID = "MapNavigation",
	expanded = false,
	colorizeTitle = false,
})

local function isSettingEnabled(varName)
	return addon.SettingsLayout.elements[varName] and addon.SettingsLayout.elements[varName].setting and addon.SettingsLayout.elements[varName].setting:GetValue() == true
end

local function isSquareMinimapEnabledSetting() return isSettingEnabled("enableSquareMinimap") end

local function isSquareMinimapStatsEnabledSetting() return isSquareMinimapEnabledSetting() and isSettingEnabled("enableSquareMinimapStats") end

local function isSquareMinimapStatElementEnabled(settingKey)
	return function() return isSquareMinimapStatsEnabledSetting() and isSettingEnabled(settingKey) end
end

local function applySquareMinimapStatsNow(force)
	if addon.functions and addon.functions.applySquareMinimapStats then addon.functions.applySquareMinimapStats(force) end
end

local function getSettingSelectedValue(primary, secondary)
	if secondary ~= nil then return secondary end
	return primary
end

local squareMinimapStatsFontOrder = {}
local squareMinimapStatsOutlineOrder = { "NONE", "OUTLINE", "THICKOUTLINE", "MONOCHROMEOUTLINE" }
local squareMinimapStatsOutlineOptions = {
	NONE = L["fontOutlineNone"] or NONE,
	OUTLINE = L["fontOutlineThin"] or "Outline",
	THICKOUTLINE = L["fontOutlineThick"] or "Thick Outline",
	MONOCHROMEOUTLINE = L["fontOutlineMono"] or "Monochrome Outline",
}
local squareMinimapStatsAnchorOrder = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local squareMinimapStatsAnchorOptions = {
	TOPLEFT = L["squareMinimapStatsAnchorTopLeft"] or "Top Left",
	TOP = L["squareMinimapStatsAnchorTop"] or "Top",
	TOPRIGHT = L["squareMinimapStatsAnchorTopRight"] or "Top Right",
	LEFT = L["squareMinimapStatsAnchorLeft"] or "Left",
	CENTER = L["squareMinimapStatsAnchorCenter"] or "Center",
	RIGHT = L["squareMinimapStatsAnchorRight"] or "Right",
	BOTTOMLEFT = L["squareMinimapStatsAnchorBottomLeft"] or "Bottom Left",
	BOTTOM = L["squareMinimapStatsAnchorBottom"] or "Bottom",
	BOTTOMRIGHT = L["squareMinimapStatsAnchorBottomRight"] or "Bottom Right",
}

local function normalizeSquareMinimapStatsOutlineSelection(primary, secondary)
	local outline = getSettingSelectedValue(primary, secondary)
	if outline == nil or outline == "" then return "OUTLINE" end
	if outline == "NONE" then return "NONE" end
	if squareMinimapStatsOutlineOptions[outline] then return outline end
	return "OUTLINE"
end

local function normalizeSquareMinimapAnchorSelection(primary, secondary, fallback)
	local anchor = getSettingSelectedValue(primary, secondary)
	if type(anchor) == "string" and squareMinimapStatsAnchorOptions[anchor] then return anchor end
	if type(fallback) == "string" and squareMinimapStatsAnchorOptions[fallback] then return fallback end
	return "CENTER"
end

local function normalizeSquareMinimapStatsFontSelection(primary, secondary)
	local fallback = (addon.variables and addon.variables.defaultFont) or STANDARD_TEXT_FONT
	local selected = getSettingSelectedValue(primary, secondary)
	if addon.functions and addon.functions.ResolveFontFace then return addon.functions.ResolveFontFace(selected, fallback) or fallback end
	if type(selected) == "string" and selected ~= "" then return selected end
	return fallback
end

local function buildSquareMinimapStatsFontDropdown()
	local defaultFont = (addon.variables and addon.variables.defaultFont) or STANDARD_TEXT_FONT
	local map = {
		[defaultFont] = L["actionBarFontDefault"] or "Blizzard font",
	}
	local LSM = LibStub("LibSharedMedia-3.0", true)
	if LSM and LSM.HashTable then
		for name, path in pairs(LSM:HashTable("font") or {}) do
			if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
		end
	end
	local list, order = addon.functions.prepareListForDropdown(map)
	wipe(squareMinimapStatsFontOrder)
	for i, key in ipairs(order or {}) do
		squareMinimapStatsFontOrder[i] = key
	end
	return list
end

addon.functions.SettingsCreateHeadline(cMapNav, L["MapBasics"] or "Map Basics", { parentSection = mapExpandable })

local data = {
	{
		var = "enableWayCommand",
		text = L["enableWayCommand"],
		desc = L["enableWayCommandDesc"],
		func = function(key)
			addon.db["enableWayCommand"] = key
			if key then
				addon.functions.registerWayCommand()
			else
				addon.variables.requireReload = true
			end
		end,
		default = false,
		parentSection = mapExpandable,
	},
	{
		var = "showWorldMapCoordinates",
		text = L["showWorldMapCoordinates"],
		desc = L["showWorldMapCoordinatesDesc"],
		func = function(value)
			addon.db["showWorldMapCoordinates"] = value
			if value then
				addon.functions.EnableWorldMapCoordinates()
			else
				addon.functions.DisableWorldMapCoordinates()
			end
		end,
		default = false,
		parentSection = mapExpandable,
		children = {
			{
				var = "worldMapCoordinatesUpdateInterval",
				text = L["worldMapCoordinatesUpdateInterval"] or "Coordinates update interval (s)",
				desc = L["worldMapCoordinatesUpdateIntervalDesc"],
				get = function() return addon.db and addon.db.worldMapCoordinatesUpdateInterval or 0.1 end,
				set = function(value)
					addon.db["worldMapCoordinatesUpdateInterval"] = value
					if refreshWorldMapCoordinates then refreshWorldMapCoordinates(true) end
				end,
				min = 0.01,
				max = 1.00,
				step = 0.01,
				default = 0.1,
				sType = "slider",
				parent = true,
				parentCheck = function()
					return addon.SettingsLayout.elements["showWorldMapCoordinates"]
						and addon.SettingsLayout.elements["showWorldMapCoordinates"].setting
						and addon.SettingsLayout.elements["showWorldMapCoordinates"].setting:GetValue() == true
				end,
				parentSection = mapExpandable,
			},
			{
				var = "worldMapCoordinatesHideCursor",
				text = L["worldMapCoordinatesHideCursor"] or "Hide cursor coordinates off-map",
				desc = L["worldMapCoordinatesHideCursorDesc"],
				func = function(value)
					addon.db["worldMapCoordinatesHideCursor"] = value and true or false
					if refreshWorldMapCoordinates then refreshWorldMapCoordinates() end
				end,
				default = true,
				sType = "checkbox",
				parent = true,
				parentCheck = function()
					return addon.SettingsLayout.elements["showWorldMapCoordinates"]
						and addon.SettingsLayout.elements["showWorldMapCoordinates"].setting
						and addon.SettingsLayout.elements["showWorldMapCoordinates"].setting:GetValue() == true
				end,
				parentSection = mapExpandable,
			},
		},
	},
	{
		var = "mapFade",
		text = L["mapFade"],
		get = function() return getCVarOptionState("mapFade") end,
		func = function(value) setCVarOptionState("mapFade", value) end,
		default = false,
		parentSection = mapExpandable,
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cMapNav, data)

addon.functions.SettingsCreateHeadline(cMapNav, L["SquareMinimap"] or "Square Minimap", { parentSection = mapExpandable })

data = {
	{
		var = "enableSquareMinimap",
		text = L["SquareMinimap"],
		desc = L["enableSquareMinimapDesc"],
		func = function(key)
			addon.db["enableSquareMinimap"] = key
			applySquareMinimapStatsNow(true)
			addon.variables.requireReload = true
			addon.functions.checkReloadFrame()
		end,
		default = false,
		parentSection = mapExpandable,
		children = {
			{
				var = "enableSquareMinimapLayout",
				text = L["enableSquareMinimapLayout"],
				desc = L["enableSquareMinimapLayoutDesc"],
				func = function(key)
					addon.db["enableSquareMinimapLayout"] = key
					if addon.functions.applySquareMinimapLayout then addon.functions.applySquareMinimapLayout() end
					addon.variables.requireReload = true
					addon.functions.checkReloadFrame()
				end,
				get = function() return addon.db["enableSquareMinimapLayout"] or false end,
				default = false,
				sType = "checkbox",
				parentCheck = function()
					return addon.SettingsLayout.elements["enableSquareMinimap"]
						and addon.SettingsLayout.elements["enableSquareMinimap"].setting
						and addon.SettingsLayout.elements["enableSquareMinimap"].setting:GetValue() == true
				end,
				parent = true,
				notify = "enableSquareMinimap",
				parentSection = mapExpandable,
			},
			{
				var = "enableSquareMinimapBorder",
				text = L["enableSquareMinimapBorder"],
				desc = L["enableSquareMinimapBorderDesc"],
				func = function(key)
					addon.db["enableSquareMinimapBorder"] = key
					if addon.functions.applySquareMinimapBorder then addon.functions.applySquareMinimapBorder() end
				end,
				default = false,
				sType = "checkbox",
				parentCheck = function()
					return addon.SettingsLayout.elements["enableSquareMinimap"]
						and addon.SettingsLayout.elements["enableSquareMinimap"].setting
						and addon.SettingsLayout.elements["enableSquareMinimap"].setting:GetValue() == true
				end,
				parent = true,
				notify = "enableSquareMinimap",
				parentSection = mapExpandable,
			},
			{
				var = "squareMinimapBorderSize",
				text = L["squareMinimapBorderSize"],
				parentCheck = function()
					return addon.SettingsLayout.elements["enableSquareMinimapBorder"]
						and addon.SettingsLayout.elements["enableSquareMinimapBorder"].setting
						and addon.SettingsLayout.elements["enableSquareMinimapBorder"].setting:GetValue() == true
						and addon.SettingsLayout.elements["enableSquareMinimap"]
						and addon.SettingsLayout.elements["enableSquareMinimap"].setting
						and addon.SettingsLayout.elements["enableSquareMinimap"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.squareMinimapBorderSize or 1 end,
				set = function(value)
					addon.db["squareMinimapBorderSize"] = value
					if addon.functions.applySquareMinimapBorder then addon.functions.applySquareMinimapBorder() end
				end,
				min = 1,
				max = 8,
				step = 1,
				parent = true,
				default = 1,
				sType = "slider",
				parentSection = mapExpandable,
			},
			{
				var = "squareMinimapBorderColor",
				text = L["squareMinimapBorderColor"],
				parentCheck = function()
					return addon.SettingsLayout.elements["enableSquareMinimapBorder"]
						and addon.SettingsLayout.elements["enableSquareMinimapBorder"].setting
						and addon.SettingsLayout.elements["enableSquareMinimapBorder"].setting:GetValue() == true
						and addon.SettingsLayout.elements["enableSquareMinimap"]
						and addon.SettingsLayout.elements["enableSquareMinimap"].setting
						and addon.SettingsLayout.elements["enableSquareMinimap"].setting:GetValue() == true
				end,
				parent = true,
				hasOpacity = true,
				default = false,
				sType = "colorpicker",
				notify = "enableSquareMinimap",
				callback = function()
					if addon.functions.applySquareMinimapBorder then addon.functions.applySquareMinimapBorder() end
				end,
				parentSection = mapExpandable,
			},
		},
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cMapNav, data)

addon.functions.SettingsCreateHeadline(cMapNav, L["SquareMinimapStats"] or "Square Minimap Stats", { parentSection = mapExpandable })

data = {
	{
		var = "enableSquareMinimapStats",
		text = L["enableSquareMinimapStats"] or "Enable minimap stats",
		desc = L["enableSquareMinimapStatsDesc"] or "Show configurable stats around the square minimap.",
		func = function(key)
			addon.db["enableSquareMinimapStats"] = key and true or false
			applySquareMinimapStatsNow(true)
		end,
		default = false,
		parent = true,
		parentCheck = isSquareMinimapEnabledSetting,
		notify = "enableSquareMinimap",
		parentSection = mapExpandable,
		children = {
			{
				var = "squareMinimapStatsFont",
				text = L["squareMinimapStatsFont"] or "Font (all stats)",
				listFunc = buildSquareMinimapStatsFontDropdown,
				order = squareMinimapStatsFontOrder,
				default = (addon.variables and addon.variables.defaultFont) or STANDARD_TEXT_FONT,
				get = function()
					local defaultFont = (addon.variables and addon.variables.defaultFont) or STANDARD_TEXT_FONT
					local current = addon.db and addon.db.squareMinimapStatsFont or defaultFont
					local list = buildSquareMinimapStatsFontDropdown()
					if not list[current] then current = defaultFont end
					return current
				end,
				set = function(value, maybeValue)
					addon.db["squareMinimapStatsFont"] = normalizeSquareMinimapStatsFontSelection(value, maybeValue)
					applySquareMinimapStatsNow(true)
				end,
				sType = "scrolldropdown",
				parent = true,
				parentCheck = isSquareMinimapStatsEnabledSetting,
				notify = "enableSquareMinimapStats",
				parentSection = mapExpandable,
			},
			{
				var = "squareMinimapStatsOutline",
				text = L["squareMinimapStatsOutline"] or "Outline (all stats)",
				list = squareMinimapStatsOutlineOptions,
				order = squareMinimapStatsOutlineOrder,
				get = function() return normalizeSquareMinimapStatsOutlineSelection(addon.db and addon.db.squareMinimapStatsOutline, nil) end,
				set = function(value, maybeValue)
					addon.db["squareMinimapStatsOutline"] = normalizeSquareMinimapStatsOutlineSelection(value, maybeValue)
					applySquareMinimapStatsNow(true)
				end,
				default = "OUTLINE",
				sType = "dropdown",
				parent = true,
				parentCheck = isSquareMinimapStatsEnabledSetting,
				notify = "enableSquareMinimapStats",
				parentSection = mapExpandable,
			},
			{
				text = "",
				sType = "hint",
				parentSection = mapExpandable,
			},
			{
				var = "squareMinimapStatsTime",
				text = L["squareMinimapStatsTime"] or "Time",
				func = function(key)
					addon.db["squareMinimapStatsTime"] = key and true or false
					applySquareMinimapStatsNow(true)
				end,
				default = true,
				sType = "checkbox",
				parent = true,
				parentCheck = isSquareMinimapStatsEnabledSetting,
				notify = "enableSquareMinimapStats",
				parentSection = mapExpandable,
				children = {
					{
						var = "squareMinimapStatsTimeDisplayMode",
						text = L["squareMinimapStatsTimeDisplayMode"] or "Display mode",
						list = {
							server = L["squareMinimapStatsTimeDisplayModeServer"] or "Server time",
							localTime = L["squareMinimapStatsTimeDisplayModeLocal"] or "Local time",
							both = L["squareMinimapStatsTimeDisplayModeBoth"] or "Server + Local",
						},
						get = function() return addon.db and addon.db.squareMinimapStatsTimeDisplayMode or "server" end,
						set = function(value, maybeValue)
							addon.db["squareMinimapStatsTimeDisplayMode"] = getSettingSelectedValue(value, maybeValue)
							applySquareMinimapStatsNow(true)
						end,
						default = "server",
						sType = "dropdown",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsTime"),
						notify = "squareMinimapStatsTime",
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsTimeUse24Hour",
						text = L["squareMinimapStatsTimeUse24Hour"] or "Use 24-hour format",
						func = function(value)
							addon.db["squareMinimapStatsTimeUse24Hour"] = value and true or false
							applySquareMinimapStatsNow(true)
						end,
						default = true,
						sType = "checkbox",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsTime"),
						notify = "squareMinimapStatsTime",
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsTimeShowSeconds",
						text = L["squareMinimapStatsTimeShowSeconds"] or "Show seconds",
						func = function(value)
							addon.db["squareMinimapStatsTimeShowSeconds"] = value and true or false
							applySquareMinimapStatsNow(true)
						end,
						default = false,
						sType = "checkbox",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsTime"),
						notify = "squareMinimapStatsTime",
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsTimeAnchor",
						text = L["squareMinimapStatsAnchor"] or "Anchor",
						list = squareMinimapStatsAnchorOptions,
						order = squareMinimapStatsAnchorOrder,
						get = function() return addon.db and addon.db.squareMinimapStatsTimeAnchor or "BOTTOMLEFT" end,
						set = function(value, maybeValue)
							addon.db["squareMinimapStatsTimeAnchor"] = normalizeSquareMinimapAnchorSelection(value, maybeValue, "BOTTOMLEFT")
							applySquareMinimapStatsNow(true)
						end,
						default = "BOTTOMLEFT",
						sType = "dropdown",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsTime"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsTimeOffsetX",
						text = L["squareMinimapStatsOffsetX"] or "Horizontal offset",
						get = function() return addon.db and addon.db.squareMinimapStatsTimeOffsetX or 3 end,
						set = function(value)
							addon.db["squareMinimapStatsTimeOffsetX"] = value
							applySquareMinimapStatsNow(true)
						end,
						min = -220,
						max = 220,
						step = 1,
						default = 3,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsTime"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsTimeOffsetY",
						text = L["squareMinimapStatsOffsetY"] or "Vertical offset",
						get = function() return addon.db and addon.db.squareMinimapStatsTimeOffsetY or 17 end,
						set = function(value)
							addon.db["squareMinimapStatsTimeOffsetY"] = value
							applySquareMinimapStatsNow(true)
						end,
						min = -220,
						max = 220,
						step = 1,
						default = 17,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsTime"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsTimeFontSize",
						text = L["squareMinimapStatsFontSize"] or "Font size",
						get = function() return addon.db and addon.db.squareMinimapStatsTimeFontSize or 18 end,
						set = function(value)
							addon.db["squareMinimapStatsTimeFontSize"] = value
							applySquareMinimapStatsNow(true)
						end,
						min = 8,
						max = 32,
						step = 1,
						default = 18,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsTime"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsTimeColor",
						text = L["squareMinimapStatsColor"] or "Text color",
						parent = true,
						default = false,
						sType = "colorpicker",
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsTime"),
						callback = function() applySquareMinimapStatsNow(true) end,
						parentSection = mapExpandable,
					},
				},
			},
			{
				text = "",
				sType = "hint",
				parentSection = mapExpandable,
			},
			{
				var = "squareMinimapStatsFPS",
				text = L["squareMinimapStatsFPS"] or "FPS",
				func = function(key)
					addon.db["squareMinimapStatsFPS"] = key and true or false
					applySquareMinimapStatsNow(true)
				end,
				default = true,
				sType = "checkbox",
				parent = true,
				parentCheck = isSquareMinimapStatsEnabledSetting,
				notify = "enableSquareMinimapStats",
				parentSection = mapExpandable,
				children = {
					{
						var = "squareMinimapStatsFPSUpdateInterval",
						text = L["squareMinimapStatsUpdateInterval"] or "Update interval (s)",
						get = function() return addon.db and addon.db.squareMinimapStatsFPSUpdateInterval or 0.25 end,
						set = function(value)
							addon.db["squareMinimapStatsFPSUpdateInterval"] = value
							applySquareMinimapStatsNow(true)
						end,
						min = 0.1,
						max = 2.0,
						step = 0.05,
						default = 0.25,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsFPS"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsFPSThresholdMedium",
						text = L["squareMinimapStatsFPSThresholdMedium"] or "Medium threshold (FPS)",
						get = function() return addon.db and addon.db.squareMinimapStatsFPSThresholdMedium or 30 end,
						set = function(value)
							local medium = math.floor((tonumber(value) or 30) + 0.5)
							if medium < 1 then medium = 1 end
							addon.db["squareMinimapStatsFPSThresholdMedium"] = medium
							local high = math.floor((tonumber(addon.db["squareMinimapStatsFPSThresholdHigh"]) or 60) + 0.5)
							if high < medium then addon.db["squareMinimapStatsFPSThresholdHigh"] = medium end
							applySquareMinimapStatsNow(true)
						end,
						min = 1,
						max = 240,
						step = 1,
						default = 30,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsFPS"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsFPSThresholdHigh",
						text = L["squareMinimapStatsFPSThresholdHigh"] or "High threshold (FPS)",
						get = function() return addon.db and addon.db.squareMinimapStatsFPSThresholdHigh or 60 end,
						set = function(value)
							local high = math.floor((tonumber(value) or 60) + 0.5)
							if high < 1 then high = 1 end
							addon.db["squareMinimapStatsFPSThresholdHigh"] = high
							local medium = math.floor((tonumber(addon.db["squareMinimapStatsFPSThresholdMedium"]) or 30) + 0.5)
							if medium > high then addon.db["squareMinimapStatsFPSThresholdMedium"] = high end
							applySquareMinimapStatsNow(true)
						end,
						min = 1,
						max = 240,
						step = 1,
						default = 60,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsFPS"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsFPSColorLow",
						text = L["squareMinimapStatsColorLow"] or "Low color",
						parent = true,
						default = false,
						sType = "colorpicker",
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsFPS"),
						callback = function() applySquareMinimapStatsNow(true) end,
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsFPSColorMid",
						text = L["squareMinimapStatsColorMid"] or "Medium color",
						parent = true,
						default = false,
						sType = "colorpicker",
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsFPS"),
						callback = function() applySquareMinimapStatsNow(true) end,
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsFPSColorHigh",
						text = L["squareMinimapStatsColorHigh"] or "High color",
						parent = true,
						default = false,
						sType = "colorpicker",
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsFPS"),
						callback = function() applySquareMinimapStatsNow(true) end,
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsFPSAnchor",
						text = L["squareMinimapStatsAnchor"] or "Anchor",
						list = squareMinimapStatsAnchorOptions,
						order = squareMinimapStatsAnchorOrder,
						get = function() return addon.db and addon.db.squareMinimapStatsFPSAnchor or "BOTTOMLEFT" end,
						set = function(value, maybeValue)
							addon.db["squareMinimapStatsFPSAnchor"] = normalizeSquareMinimapAnchorSelection(value, maybeValue, "BOTTOMLEFT")
							applySquareMinimapStatsNow(true)
						end,
						default = "BOTTOMLEFT",
						sType = "dropdown",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsFPS"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsFPSOffsetX",
						text = L["squareMinimapStatsOffsetX"] or "Horizontal offset",
						get = function() return addon.db and addon.db.squareMinimapStatsFPSOffsetX or 3 end,
						set = function(value)
							addon.db["squareMinimapStatsFPSOffsetX"] = value
							applySquareMinimapStatsNow(true)
						end,
						min = -220,
						max = 220,
						step = 1,
						default = 3,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsFPS"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsFPSOffsetY",
						text = L["squareMinimapStatsOffsetY"] or "Vertical offset",
						get = function() return addon.db and addon.db.squareMinimapStatsFPSOffsetY or 3 end,
						set = function(value)
							addon.db["squareMinimapStatsFPSOffsetY"] = value
							applySquareMinimapStatsNow(true)
						end,
						min = -220,
						max = 220,
						step = 1,
						default = 3,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsFPS"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsFPSFontSize",
						text = L["squareMinimapStatsFontSize"] or "Font size",
						get = function() return addon.db and addon.db.squareMinimapStatsFPSFontSize or 12 end,
						set = function(value)
							addon.db["squareMinimapStatsFPSFontSize"] = value
							applySquareMinimapStatsNow(true)
						end,
						min = 8,
						max = 32,
						step = 1,
						default = 12,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsFPS"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsFPSColor",
						text = L["squareMinimapStatsColor"] or "Text color",
						parent = true,
						default = false,
						sType = "colorpicker",
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsFPS"),
						callback = function() applySquareMinimapStatsNow(true) end,
						parentSection = mapExpandable,
					},
				},
			},
			{
				text = "",
				sType = "hint",
				parentSection = mapExpandable,
			},
			{
				var = "squareMinimapStatsLatency",
				text = L["squareMinimapStatsLatency"] or "Latency",
				func = function(key)
					addon.db["squareMinimapStatsLatency"] = key and true or false
					applySquareMinimapStatsNow(true)
				end,
				default = true,
				sType = "checkbox",
				parent = true,
				parentCheck = isSquareMinimapStatsEnabledSetting,
				notify = "enableSquareMinimapStats",
				parentSection = mapExpandable,
				children = {
					{
						var = "squareMinimapStatsLatencyMode",
						text = L["squareMinimapStatsLatencyMode"] or "Display mode",
						list = {
							max = L["squareMinimapStatsLatencyModeMax"] or "Max(home, world)",
							home = L["squareMinimapStatsLatencyModeHome"] or "Home",
							world = L["squareMinimapStatsLatencyModeWorld"] or "World",
							split = L["squareMinimapStatsLatencyModeSplit"] or "Home + World",
							split_vertical = L["squareMinimapStatsLatencyModeSplitVertical"] or "Home + World (vertical)",
						},
						get = function() return addon.db and addon.db.squareMinimapStatsLatencyMode or "max" end,
						set = function(value, maybeValue)
							addon.db["squareMinimapStatsLatencyMode"] = getSettingSelectedValue(value, maybeValue)
							applySquareMinimapStatsNow(true)
						end,
						default = "max",
						sType = "dropdown",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsLatency"),
						notify = "squareMinimapStatsLatency",
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsLatencyUpdateInterval",
						text = L["squareMinimapStatsUpdateInterval"] or "Update interval (s)",
						get = function() return addon.db and addon.db.squareMinimapStatsLatencyUpdateInterval or 1.0 end,
						set = function(value)
							addon.db["squareMinimapStatsLatencyUpdateInterval"] = value
							applySquareMinimapStatsNow(true)
						end,
						min = 0.2,
						max = 5.0,
						step = 0.1,
						default = 1.0,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsLatency"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsLatencyThresholdLow",
						text = L["squareMinimapStatsLatencyThresholdLow"] or "Low threshold (ms)",
						get = function() return addon.db and addon.db.squareMinimapStatsLatencyThresholdLow or 50 end,
						set = function(value)
							local low = math.floor((tonumber(value) or 50) + 0.5)
							if low < 0 then low = 0 end
							addon.db["squareMinimapStatsLatencyThresholdLow"] = low
							local mid = math.floor((tonumber(addon.db["squareMinimapStatsLatencyThresholdMid"]) or 150) + 0.5)
							if mid < low then addon.db["squareMinimapStatsLatencyThresholdMid"] = low end
							applySquareMinimapStatsNow(true)
						end,
						min = 0,
						max = 1000,
						step = 1,
						default = 50,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsLatency"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsLatencyThresholdMid",
						text = L["squareMinimapStatsLatencyThresholdMid"] or "Medium threshold (ms)",
						get = function() return addon.db and addon.db.squareMinimapStatsLatencyThresholdMid or 150 end,
						set = function(value)
							local mid = math.floor((tonumber(value) or 150) + 0.5)
							if mid < 0 then mid = 0 end
							addon.db["squareMinimapStatsLatencyThresholdMid"] = mid
							local low = math.floor((tonumber(addon.db["squareMinimapStatsLatencyThresholdLow"]) or 50) + 0.5)
							if low > mid then addon.db["squareMinimapStatsLatencyThresholdLow"] = mid end
							applySquareMinimapStatsNow(true)
						end,
						min = 0,
						max = 1000,
						step = 1,
						default = 150,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsLatency"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsLatencyColorLow",
						text = L["squareMinimapStatsColorLow"] or "Low color",
						parent = true,
						default = false,
						sType = "colorpicker",
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsLatency"),
						callback = function() applySquareMinimapStatsNow(true) end,
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsLatencyColorMid",
						text = L["squareMinimapStatsColorMid"] or "Medium color",
						parent = true,
						default = false,
						sType = "colorpicker",
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsLatency"),
						callback = function() applySquareMinimapStatsNow(true) end,
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsLatencyColorHigh",
						text = L["squareMinimapStatsColorHigh"] or "High color",
						parent = true,
						default = false,
						sType = "colorpicker",
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsLatency"),
						callback = function() applySquareMinimapStatsNow(true) end,
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsLatencyAnchor",
						text = L["squareMinimapStatsAnchor"] or "Anchor",
						list = squareMinimapStatsAnchorOptions,
						order = squareMinimapStatsAnchorOrder,
						get = function() return addon.db and addon.db.squareMinimapStatsLatencyAnchor or "BOTTOMRIGHT" end,
						set = function(value, maybeValue)
							addon.db["squareMinimapStatsLatencyAnchor"] = normalizeSquareMinimapAnchorSelection(value, maybeValue, "BOTTOMRIGHT")
							applySquareMinimapStatsNow(true)
						end,
						default = "BOTTOMRIGHT",
						sType = "dropdown",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsLatency"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsLatencyOffsetX",
						text = L["squareMinimapStatsOffsetX"] or "Horizontal offset",
						get = function() return addon.db and addon.db.squareMinimapStatsLatencyOffsetX or -3 end,
						set = function(value)
							addon.db["squareMinimapStatsLatencyOffsetX"] = value
							applySquareMinimapStatsNow(true)
						end,
						min = -220,
						max = 220,
						step = 1,
						default = -3,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsLatency"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsLatencyOffsetY",
						text = L["squareMinimapStatsOffsetY"] or "Vertical offset",
						get = function() return addon.db and addon.db.squareMinimapStatsLatencyOffsetY or 3 end,
						set = function(value)
							addon.db["squareMinimapStatsLatencyOffsetY"] = value
							applySquareMinimapStatsNow(true)
						end,
						min = -220,
						max = 220,
						step = 1,
						default = 3,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsLatency"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsLatencyFontSize",
						text = L["squareMinimapStatsFontSize"] or "Font size",
						get = function() return addon.db and addon.db.squareMinimapStatsLatencyFontSize or 12 end,
						set = function(value)
							addon.db["squareMinimapStatsLatencyFontSize"] = value
							applySquareMinimapStatsNow(true)
						end,
						min = 8,
						max = 32,
						step = 1,
						default = 12,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsLatency"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsLatencyColor",
						text = L["squareMinimapStatsColor"] or "Text color",
						parent = true,
						default = false,
						sType = "colorpicker",
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsLatency"),
						callback = function() applySquareMinimapStatsNow(true) end,
						parentSection = mapExpandable,
					},
				},
			},
			{
				text = "",
				sType = "hint",
				parentSection = mapExpandable,
			},
			{
				var = "squareMinimapStatsLocation",
				text = L["squareMinimapStatsLocation"] or "Location",
				func = function(key)
					addon.db["squareMinimapStatsLocation"] = key and true or false
					applySquareMinimapStatsNow(true)
				end,
				default = true,
				sType = "checkbox",
				parent = true,
				parentCheck = isSquareMinimapStatsEnabledSetting,
				notify = "enableSquareMinimapStats",
				parentSection = mapExpandable,
				children = {
					{
						var = "squareMinimapStatsLocationShowSubzone",
						text = L["squareMinimapStatsLocationShowSubzone"] or "Show subzone",
						func = function(value)
							addon.db["squareMinimapStatsLocationShowSubzone"] = value and true or false
							applySquareMinimapStatsNow(true)
						end,
						default = false,
						sType = "checkbox",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsLocation"),
						notify = "squareMinimapStatsLocation",
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsLocationUseZoneColor",
						text = L["squareMinimapStatsLocationUseZoneColor"] or "Use zone color",
						func = function(value)
							addon.db["squareMinimapStatsLocationUseZoneColor"] = value and true or false
							applySquareMinimapStatsNow(true)
						end,
						default = true,
						sType = "checkbox",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsLocation"),
						notify = "squareMinimapStatsLocation",
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsLocationAnchor",
						text = L["squareMinimapStatsAnchor"] or "Anchor",
						list = squareMinimapStatsAnchorOptions,
						order = squareMinimapStatsAnchorOrder,
						get = function() return addon.db and addon.db.squareMinimapStatsLocationAnchor or "TOP" end,
						set = function(value, maybeValue)
							addon.db["squareMinimapStatsLocationAnchor"] = normalizeSquareMinimapAnchorSelection(value, maybeValue, "TOP")
							applySquareMinimapStatsNow(true)
						end,
						default = "TOP",
						sType = "dropdown",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsLocation"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsLocationOffsetX",
						text = L["squareMinimapStatsOffsetX"] or "Horizontal offset",
						get = function() return addon.db and addon.db.squareMinimapStatsLocationOffsetX or 0 end,
						set = function(value)
							addon.db["squareMinimapStatsLocationOffsetX"] = value
							applySquareMinimapStatsNow(true)
						end,
						min = -220,
						max = 220,
						step = 1,
						default = 0,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsLocation"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsLocationOffsetY",
						text = L["squareMinimapStatsOffsetY"] or "Vertical offset",
						get = function() return addon.db and addon.db.squareMinimapStatsLocationOffsetY or -3 end,
						set = function(value)
							addon.db["squareMinimapStatsLocationOffsetY"] = value
							applySquareMinimapStatsNow(true)
						end,
						min = -220,
						max = 220,
						step = 1,
						default = -3,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsLocation"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsLocationFontSize",
						text = L["squareMinimapStatsFontSize"] or "Font size",
						get = function() return addon.db and addon.db.squareMinimapStatsLocationFontSize or 12 end,
						set = function(value)
							addon.db["squareMinimapStatsLocationFontSize"] = value
							applySquareMinimapStatsNow(true)
						end,
						min = 8,
						max = 32,
						step = 1,
						default = 12,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsLocation"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsLocationColor",
						text = L["squareMinimapStatsColor"] or "Text color",
						parent = true,
						default = false,
						sType = "colorpicker",
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsLocation"),
						callback = function() applySquareMinimapStatsNow(true) end,
						parentSection = mapExpandable,
					},
				},
			},
			{
				text = "",
				sType = "hint",
				parentSection = mapExpandable,
			},
			{
				var = "squareMinimapStatsCoordinates",
				text = L["squareMinimapStatsCoordinates"] or "Coordinates",
				func = function(key)
					addon.db["squareMinimapStatsCoordinates"] = key and true or false
					applySquareMinimapStatsNow(true)
				end,
				default = true,
				sType = "checkbox",
				parent = true,
				parentCheck = isSquareMinimapStatsEnabledSetting,
				notify = "enableSquareMinimapStats",
				parentSection = mapExpandable,
				children = {
					{
						var = "squareMinimapStatsCoordinatesHideInInstance",
						text = L["squareMinimapStatsCoordinatesHideInInstance"] or "Hide in instances",
						func = function(value)
							addon.db["squareMinimapStatsCoordinatesHideInInstance"] = value and true or false
							applySquareMinimapStatsNow(true)
						end,
						default = true,
						sType = "checkbox",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsCoordinates"),
						notify = "squareMinimapStatsCoordinates",
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsCoordinatesUpdateInterval",
						text = L["squareMinimapStatsUpdateInterval"] or "Update interval (s)",
						get = function() return addon.db and addon.db.squareMinimapStatsCoordinatesUpdateInterval or 0.2 end,
						set = function(value)
							addon.db["squareMinimapStatsCoordinatesUpdateInterval"] = value
							applySquareMinimapStatsNow(true)
						end,
						min = 0.1,
						max = 1.0,
						step = 0.05,
						default = 0.2,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsCoordinates"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsCoordinatesAnchor",
						text = L["squareMinimapStatsAnchor"] or "Anchor",
						list = squareMinimapStatsAnchorOptions,
						order = squareMinimapStatsAnchorOrder,
						get = function() return addon.db and addon.db.squareMinimapStatsCoordinatesAnchor or "TOP" end,
						set = function(value, maybeValue)
							addon.db["squareMinimapStatsCoordinatesAnchor"] = normalizeSquareMinimapAnchorSelection(value, maybeValue, "TOP")
							applySquareMinimapStatsNow(true)
						end,
						default = "TOP",
						sType = "dropdown",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsCoordinates"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsCoordinatesOffsetX",
						text = L["squareMinimapStatsOffsetX"] or "Horizontal offset",
						get = function() return addon.db and addon.db.squareMinimapStatsCoordinatesOffsetX or 0 end,
						set = function(value)
							addon.db["squareMinimapStatsCoordinatesOffsetX"] = value
							applySquareMinimapStatsNow(true)
						end,
						min = -220,
						max = 220,
						step = 1,
						default = 0,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsCoordinates"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsCoordinatesOffsetY",
						text = L["squareMinimapStatsOffsetY"] or "Vertical offset",
						get = function() return addon.db and addon.db.squareMinimapStatsCoordinatesOffsetY or -17 end,
						set = function(value)
							addon.db["squareMinimapStatsCoordinatesOffsetY"] = value
							applySquareMinimapStatsNow(true)
						end,
						min = -220,
						max = 220,
						step = 1,
						default = -17,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsCoordinates"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsCoordinatesFontSize",
						text = L["squareMinimapStatsFontSize"] or "Font size",
						get = function() return addon.db and addon.db.squareMinimapStatsCoordinatesFontSize or 12 end,
						set = function(value)
							addon.db["squareMinimapStatsCoordinatesFontSize"] = value
							applySquareMinimapStatsNow(true)
						end,
						min = 8,
						max = 32,
						step = 1,
						default = 12,
						sType = "slider",
						parent = true,
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsCoordinates"),
						parentSection = mapExpandable,
					},
					{
						var = "squareMinimapStatsCoordinatesColor",
						text = L["squareMinimapStatsColor"] or "Text color",
						parent = true,
						default = false,
						sType = "colorpicker",
						parentCheck = isSquareMinimapStatElementEnabled("squareMinimapStatsCoordinates"),
						callback = function() applySquareMinimapStatsNow(true) end,
						parentSection = mapExpandable,
					},
				},
			},
		},
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cMapNav, data)

addon.functions.SettingsCreateHeadline(cMapNav, L["MinimapButtonsAndCluster"] or "Minimap Buttons & Cluster", { parentSection = mapExpandable })

data = {
	{
		var = "minimapButtonsMouseover",
		text = L["minimapButtonsMouseover"],
		desc = L["minimapButtonsMouseoverDesc"],
		func = function(key)
			addon.db["minimapButtonsMouseover"] = key
			if addon.functions.applyMinimapButtonMouseover then addon.functions.applyMinimapButtonMouseover() end
		end,
		default = false,
		parentCheck = function()
			return not (
				addon.SettingsLayout.elements["enableMinimapButtonBin"]
				and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting
				and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting:GetValue() == true
			)
		end,
		notify = "enableMinimapButtonBin",
		parentSection = mapExpandable,
	},
	{
		var = "unclampMinimapCluster",
		text = L["unclampMinimapCluster"],
		desc = L["unclampMinimapClusterDesc"],
		func = function(key)
			addon.db["unclampMinimapCluster"] = key
			if addon.functions.applyMinimapClusterClamp then addon.functions.applyMinimapClusterClamp() end
		end,
		default = false,
		parentSection = mapExpandable,
	},
	{
		var = "enableMinimapClusterScale",
		text = L["enableMinimapClusterScale"],
		desc = L["enableMinimapClusterScaleDesc"],
		func = function(key)
			addon.db["enableMinimapClusterScale"] = key
			if addon.functions.applyMinimapClusterScale then addon.functions.applyMinimapClusterScale() end
		end,
		default = false,
		parentSection = mapExpandable,
		children = {
			{
				var = "minimapClusterScale",
				text = L["minimapClusterScale"],
				desc = L["minimapClusterScaleDesc"],
				parentCheck = function()
					return addon.SettingsLayout.elements["enableMinimapClusterScale"]
						and addon.SettingsLayout.elements["enableMinimapClusterScale"].setting
						and addon.SettingsLayout.elements["enableMinimapClusterScale"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.minimapClusterScale or 1 end,
				set = function(value)
					addon.db["minimapClusterScale"] = value
					if addon.functions.applyMinimapClusterScale then addon.functions.applyMinimapClusterScale() end
				end,
				min = 0.5,
				max = 2,
				step = 0.05,
				parent = true,
				default = 1,
				sType = "slider",
				parentSection = mapExpandable,
			},
		},
	},
	{
		var = "hideMinimapButton",
		text = L["hideMinimapButton"],
		func = function(v)
			addon.db["hideMinimapButton"] = v
			addon.functions.toggleMinimapButton(addon.db["hideMinimapButton"])
		end,
		default = false,
		parentSection = mapExpandable,
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cMapNav, data)

addon.functions.SettingsCreateMultiDropdown(cMapNav, {
	var = "hiddenMinimapElements",
	text = L["minimapHideElements"],
	parentSection = mapExpandable,
	options = {
		{ value = "Tracking", text = L["minimapHideElements_Tracking"] },
		{ value = "ZoneInfo", text = L["minimapHideElements_ZoneInfo"] },
		{ value = "Clock", text = L["minimapHideElements_Clock"] },
		{ value = "Calendar", text = L["minimapHideElements_Calendar"] },
		{ value = "Mail", text = L["minimapHideElements_Mail"] },
		{ value = "AddonCompartment", text = L["minimapHideElements_AddonCompartment"] },
	},
	callback = function()
		if addon.functions.ApplyMinimapElementVisibility then addon.functions.ApplyMinimapElementVisibility() end
	end,
})

addon.functions.SettingsCreateHeadline(cMapNav, L["LootspecAndLandingPage"] or "Lootspec & Landing Page", { parentSection = mapExpandable })

data = {
	{
		var = "enableLootspecQuickswitch",
		text = L["enableLootspecQuickswitch"],
		desc = L["enableLootspecQuickswitchDesc"],
		func = function(key)
			addon.db["enableLootspecQuickswitch"] = key
			if key then
				addon.functions.createLootspecFrame()
			else
				addon.functions.removeLootspecframe()
			end
		end,
		default = false,
		parentSection = mapExpandable,
	},
	{
		var = "enableLandingPageMenu",
		text = L["enableLandingPageMenu"],
		desc = L["enableLandingPageMenuDesc"],
		func = function(key) addon.db["enableLandingPageMenu"] = key end,
		default = false,
		parentSection = mapExpandable,
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cMapNav, data)

addon.functions.SettingsCreateText(cMapNav, "|cff99e599" .. L["landingPageHide"] .. "|r", { parentSection = mapExpandable })

local function resolveLandingPageId(value)
	if type(value) == "number" then return value end
	if type(value) == "string" then
		local reverse = addon.variables and addon.variables.landingPageReverse
		return (reverse and reverse[value]) or tonumber(value)
	end
end

local function normalizeHiddenLandingPages()
	addon.db.hiddenLandingPages = addon.db.hiddenLandingPages or {}
	local toClear = {}
	for key, flag in pairs(addon.db.hiddenLandingPages) do
		if type(key) ~= "number" then
			local resolved = resolveLandingPageId(key)
			if resolved then
				addon.db.hiddenLandingPages[resolved] = flag and true or nil
				table.insert(toClear, key)
			end
		end
	end
	for _, key in ipairs(toClear) do
		addon.db.hiddenLandingPages[key] = nil
	end
end

normalizeHiddenLandingPages()

local function getIgnoreStateLandingPage(value)
	if not value then return false end
	addon.db.hiddenLandingPages = addon.db.hiddenLandingPages or {}
	local resolved = resolveLandingPageId(value)
	if not resolved then return false end
	return addon.db.hiddenLandingPages[resolved] and true or false
end

local function setIgnoreStateLandingPage(value, shouldSelect)
	if not value then return end
	addon.db.hiddenLandingPages = addon.db.hiddenLandingPages or {}
	local resolved = resolveLandingPageId(value)
	if not resolved then return end
	if shouldSelect then
		addon.db.hiddenLandingPages[resolved] = true
	else
		addon.db.hiddenLandingPages[resolved] = nil
	end
	local page = addon.variables and addon.variables.landingPageType and addon.variables.landingPageType[resolved]
	if page and addon.functions.toggleLandingPageButton then addon.functions.toggleLandingPageButton(page.title, shouldSelect) end
end

addon.functions.SettingsCreateMultiDropdown(cMapNav, {
	var = "hiddenLandingPages",
	text = HIDE,
	parentSection = mapExpandable,
	optionfunc = function()
		local buttons = (addon.variables and addon.variables.landingPageType) or {}
		local list = {}
		for id in pairs(buttons) do
			table.insert(list, { value = id, text = buttons[id].title })
		end
		table.sort(list, function(a, b) return tostring(a.text) < tostring(b.text) end)
		return list
	end,
	isSelectedFunc = getIgnoreStateLandingPage,
	setSelectedFunc = setIgnoreStateLandingPage,
})

addon.functions.SettingsCreateHeadline(cMapNav, L["InstanceDifficultyIndicator"] or "Instance Difficulty Indicator", { parentSection = mapExpandable })

data = {
	{
		var = "showInstanceDifficulty",
		text = L["showInstanceDifficulty"],
		desc = L["showInstanceDifficultyDesc"],
		func = function(key)
			addon.db["showInstanceDifficulty"] = key
			if addon.InstanceDifficulty and addon.InstanceDifficulty.SetEnabled then addon.InstanceDifficulty:SetEnabled(key) end
		end,
		default = false,
		parentSection = mapExpandable,
		children = {
			{
				var = "instanceDifficultyFontSize",
				text = L["instanceDifficultyFontSize"],
				parentCheck = function()
					return addon.SettingsLayout.elements["showInstanceDifficulty"]
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.instanceDifficultyFontSize or 1 end,
				set = function(value)
					addon.db["instanceDifficultyFontSize"] = value
					if addon.InstanceDifficulty then addon.InstanceDifficulty:Update() end
				end,
				min = 8,
				max = 28,
				step = 1,
				parent = true,
				default = 14,
				sType = "slider",
				parentSection = mapExpandable,
			},
			{
				var = "instanceDifficultyOffsetX",
				text = L["instanceDifficultyOffsetX"],
				parentCheck = function()
					return addon.SettingsLayout.elements["showInstanceDifficulty"]
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.instanceDifficultyOffsetX or 0 end,
				set = function(value)
					addon.db["instanceDifficultyOffsetX"] = value
					if addon.InstanceDifficulty then addon.InstanceDifficulty:Update() end
				end,
				min = -400,
				max = 400,
				step = 1,
				parent = true,
				default = 0,
				sType = "slider",
				parentSection = mapExpandable,
			},
			{
				var = "instanceDifficultyOffsetY",
				text = L["instanceDifficultyOffsetY"],
				parentCheck = function()
					return addon.SettingsLayout.elements["showInstanceDifficulty"]
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.instanceDifficultyOffsetY or 0 end,
				set = function(value)
					addon.db["instanceDifficultyOffsetY"] = value
					if addon.InstanceDifficulty then addon.InstanceDifficulty:Update() end
				end,
				min = -400,
				max = 400,
				step = 1,
				parent = true,
				default = 0,
				sType = "slider",
				parentSection = mapExpandable,
			},
			{
				var = "instanceDifficultyUseColors",
				text = L["instanceDifficultyUseColors"],
				func = function(key)
					addon.db["instanceDifficultyUseColors"] = key
					if addon.InstanceDifficulty then addon.InstanceDifficulty:Update() end
				end,
				default = false,
				sType = "checkbox",
				parentCheck = function()
					return addon.SettingsLayout.elements["showInstanceDifficulty"]
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting:GetValue() == true
				end,
				parent = true,
				notify = "showInstanceDifficulty",
				parentSection = mapExpandable,
			},
			{
				var = "instanceDifficultyColors",
				subvar = "LFR",
				hasOpacity = true,
				text = _G["PLAYER_DIFFICULTY3"],
				parentCheck = function()
					return addon.SettingsLayout.elements["instanceDifficultyUseColors"]
						and addon.SettingsLayout.elements["instanceDifficultyUseColors"].setting
						and addon.SettingsLayout.elements["instanceDifficultyUseColors"].setting:GetValue() == true
						and addon.SettingsLayout.elements["showInstanceDifficulty"]
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				sType = "colorpicker",
				callback = function()
					if addon.InstanceDifficulty then addon.InstanceDifficulty:Update() end
				end,
				parentSection = mapExpandable,
			},
			{
				var = "instanceDifficultyColors",
				subvar = "NM",
				hasOpacity = true,
				text = _G["PLAYER_DIFFICULTY1"],
				parentCheck = function()
					return addon.SettingsLayout.elements["instanceDifficultyUseColors"]
						and addon.SettingsLayout.elements["instanceDifficultyUseColors"].setting
						and addon.SettingsLayout.elements["instanceDifficultyUseColors"].setting:GetValue() == true
						and addon.SettingsLayout.elements["showInstanceDifficulty"]
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				sType = "colorpicker",
				callback = function()
					if addon.InstanceDifficulty then addon.InstanceDifficulty:Update() end
				end,
				parentSection = mapExpandable,
			},
			{
				var = "instanceDifficultyColors",
				subvar = "HC",
				hasOpacity = true,
				text = _G["PLAYER_DIFFICULTY2"],
				parentCheck = function()
					return addon.SettingsLayout.elements["instanceDifficultyUseColors"]
						and addon.SettingsLayout.elements["instanceDifficultyUseColors"].setting
						and addon.SettingsLayout.elements["instanceDifficultyUseColors"].setting:GetValue() == true
						and addon.SettingsLayout.elements["showInstanceDifficulty"]
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				sType = "colorpicker",
				callback = function()
					if addon.InstanceDifficulty then addon.InstanceDifficulty:Update() end
				end,
				parentSection = mapExpandable,
			},
			{
				var = "instanceDifficultyColors",
				subvar = "M",
				hasOpacity = true,
				text = _G["PLAYER_DIFFICULTY6"],
				parentCheck = function()
					return addon.SettingsLayout.elements["instanceDifficultyUseColors"]
						and addon.SettingsLayout.elements["instanceDifficultyUseColors"].setting
						and addon.SettingsLayout.elements["instanceDifficultyUseColors"].setting:GetValue() == true
						and addon.SettingsLayout.elements["showInstanceDifficulty"]
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				sType = "colorpicker",
				callback = function()
					if addon.InstanceDifficulty then addon.InstanceDifficulty:Update() end
				end,
				parentSection = mapExpandable,
			},
			{
				var = "instanceDifficultyColors",
				subvar = "MPLUS",
				hasOpacity = true,
				text = _G["PLAYER_DIFFICULTY_MYTHIC_PLUS"],
				parentCheck = function()
					return addon.SettingsLayout.elements["instanceDifficultyUseColors"]
						and addon.SettingsLayout.elements["instanceDifficultyUseColors"].setting
						and addon.SettingsLayout.elements["instanceDifficultyUseColors"].setting:GetValue() == true
						and addon.SettingsLayout.elements["showInstanceDifficulty"]
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				sType = "colorpicker",
				callback = function()
					if addon.InstanceDifficulty then addon.InstanceDifficulty:Update() end
				end,
				parentSection = mapExpandable,
			},
			{
				var = "instanceDifficultyColors",
				subvar = "TW",
				hasOpacity = true,
				text = _G["PLAYER_DIFFICULTY_TIMEWALKER"],
				parentCheck = function()
					return addon.SettingsLayout.elements["instanceDifficultyUseColors"]
						and addon.SettingsLayout.elements["instanceDifficultyUseColors"].setting
						and addon.SettingsLayout.elements["instanceDifficultyUseColors"].setting:GetValue() == true
						and addon.SettingsLayout.elements["showInstanceDifficulty"]
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting
						and addon.SettingsLayout.elements["showInstanceDifficulty"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				sType = "colorpicker",
				callback = function()
					if addon.InstanceDifficulty then addon.InstanceDifficulty:Update() end
				end,
				parentSection = mapExpandable,
			},
		},
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cMapNav, data)

addon.functions.SettingsCreateHeadline(cMapNav, L["MinimapButtonBin"] or "Minimap Button Bin", { parentSection = mapExpandable })
local buttonSinkSection = mapExpandable

data = {
	{
		var = "enableMinimapButtonBin",
		text = L["enableMinimapButtonBin"],
		desc = L["enableMinimapButtonBinDesc"],
		func = function(key)
			addon.db["enableMinimapButtonBin"] = key
			addon.functions.toggleButtonSink()
			if addon.functions.applyMinimapButtonMouseover then addon.functions.applyMinimapButtonMouseover() end
		end,
		default = false,
		parentSection = buttonSinkSection,
		children = {
			{
				var = "useMinimapButtonBinIcon",
				text = L["useMinimapButtonBinIcon"],
				desc = L["useMinimapButtonBinIconDesc"],
				func = function(key)
					addon.db["useMinimapButtonBinIcon"] = key
					if key then addon.db["useMinimapButtonBinMouseover"] = false end
					addon.functions.toggleButtonSink()
				end,
				default = false,
				sType = "checkbox",
				parentCheck = function()
					return addon.SettingsLayout.elements["enableMinimapButtonBin"]
						and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting
						and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting:GetValue() == true
						and addon.SettingsLayout.elements["useMinimapButtonBinMouseover"]
						and addon.SettingsLayout.elements["useMinimapButtonBinMouseover"].setting
						and (
							addon.SettingsLayout.elements["useMinimapButtonBinMouseover"].setting:GetValue() == false
							or addon.SettingsLayout.elements["useMinimapButtonBinMouseover"].setting:GetValue() == nil
						)
				end,
				parent = true,
				notify = "enableMinimapButtonBin",
				parentSection = buttonSinkSection,
			},
			{
				var = "buttonSinkAnchorPreference",
				text = L["minimapButtonBinAnchor"],
				desc = L["minimapButtonBinAnchorDesc"],
				list = {
					AUTO = L["minimapButtonBinAnchor_Auto"],
					TOP = L["minimapButtonBinAnchor_Top"],
					TOPLEFT = L["minimapButtonBinAnchor_TopLeft"],
					TOPRIGHT = L["minimapButtonBinAnchor_TopRight"],
					LEFT = L["minimapButtonBinAnchor_Left"],
					RIGHT = L["minimapButtonBinAnchor_Right"],
					BOTTOMLEFT = L["minimapButtonBinAnchor_BottomLeft"],
					BOTTOMRIGHT = L["minimapButtonBinAnchor_BottomRight"],
					BOTTOM = L["minimapButtonBinAnchor_Bottom"],
				},
				order = {
					"AUTO",
					"TOPLEFT",
					"TOP",
					"TOPRIGHT",
					"LEFT",
					"RIGHT",
					"BOTTOMLEFT",
					"BOTTOM",
					"BOTTOMRIGHT",
				},
				default = "AUTO",
				get = function() return addon.db and addon.db.buttonSinkAnchorPreference or "AUTO" end,
				set = function(value)
					local valid = {
						AUTO = true,
						TOP = true,
						TOPLEFT = true,
						TOPRIGHT = true,
						LEFT = true,
						RIGHT = true,
						BOTTOMLEFT = true,
						BOTTOMRIGHT = true,
						BOTTOM = true,
					}
					if not valid[value] then value = "AUTO" end
					addon.db["buttonSinkAnchorPreference"] = value
				end,
				parent = true,
				parentCheck = function()
					return addon.SettingsLayout.elements["enableMinimapButtonBin"]
						and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting
						and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting:GetValue() == true
						and addon.SettingsLayout.elements["useMinimapButtonBinIcon"]
						and addon.SettingsLayout.elements["useMinimapButtonBinIcon"].setting
						and addon.SettingsLayout.elements["useMinimapButtonBinIcon"].setting:GetValue() == true
				end,
				notify = "enableMinimapButtonBin",
				sType = "dropdown",
				parentSection = buttonSinkSection,
			},
			{
				var = "minimapButtonBinIconClickToggle",
				text = L["minimapButtonBinIconClickToggle"],
				desc = L["minimapButtonBinIconClickToggleDesc"],
				func = function(key)
					addon.db["minimapButtonBinIconClickToggle"] = key
					addon.functions.toggleButtonSink()
				end,
				default = false,
				sType = "checkbox",
				parentCheck = function()
					return addon.SettingsLayout.elements["enableMinimapButtonBin"]
						and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting
						and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting:GetValue() == true
						and addon.SettingsLayout.elements["useMinimapButtonBinIcon"]
						and addon.SettingsLayout.elements["useMinimapButtonBinIcon"].setting
						and addon.SettingsLayout.elements["useMinimapButtonBinIcon"].setting:GetValue() == true
				end,
				parent = true,
				notify = "enableMinimapButtonBin",
				parentSection = buttonSinkSection,
			},
			{
				var = "useMinimapButtonBinMouseover",
				text = L["useMinimapButtonBinMouseover"],
				desc = L["useMinimapButtonBinMouseoverDesc"],
				func = function(key)
					addon.db["useMinimapButtonBinMouseover"] = key
					if key then addon.db["useMinimapButtonBinIcon"] = false end
					addon.functions.toggleButtonSink()
				end,
				default = false,
				sType = "checkbox",
				parentCheck = function()
					return addon.SettingsLayout.elements["enableMinimapButtonBin"]
						and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting
						and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting:GetValue() == true
						and addon.SettingsLayout.elements["useMinimapButtonBinIcon"]
						and addon.SettingsLayout.elements["useMinimapButtonBinIcon"].setting
						and (addon.SettingsLayout.elements["useMinimapButtonBinIcon"].setting:GetValue() == false or addon.SettingsLayout.elements["useMinimapButtonBinIcon"].setting:GetValue() == nil)
				end,
				parent = true,
				notify = "enableMinimapButtonBin",
				parentSection = buttonSinkSection,
			},
			{
				var = "lockMinimapButtonBin",
				text = L["lockMinimapButtonBin"],
				desc = L["lockMinimapButtonBinDesc"],
				func = function(key)
					addon.db["lockMinimapButtonBin"] = key
					addon.functions.toggleButtonSink()
				end,
				default = false,
				sType = "checkbox",
				parentCheck = function()
					return addon.SettingsLayout.elements["enableMinimapButtonBin"]
						and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting
						and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting:GetValue() == true
						and addon.SettingsLayout.elements["useMinimapButtonBinMouseover"]
						and addon.SettingsLayout.elements["useMinimapButtonBinMouseover"].setting
						and addon.SettingsLayout.elements["useMinimapButtonBinMouseover"].setting:GetValue() == true
				end,
				parent = true,
				notify = "enableMinimapButtonBin",
				parentSection = buttonSinkSection,
			},
			{
				var = "minimapButtonBinHideBorder",
				text = L["minimapButtonBinHideBorder"],
				desc = L["minimapButtonBinHideBorderDesc"],
				func = function(key)
					addon.db["minimapButtonBinHideBorder"] = key
					addon.functions.toggleButtonSink()
				end,
				default = false,
				sType = "checkbox",
				parentCheck = function()
					return addon.SettingsLayout.elements["enableMinimapButtonBin"]
						and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting
						and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting:GetValue() == true
				end,
				parent = true,
				parentSection = buttonSinkSection,
			},
			{
				var = "minimapButtonBinHideBackground",
				text = L["minimapButtonBinHideBackground"],
				desc = L["minimapButtonBinHideBackgroundDesc"],
				func = function(key)
					addon.db["minimapButtonBinHideBackground"] = key
					if addon.functions.applyButtonSinkAppearance then addon.functions.applyButtonSinkAppearance() end
				end,
				default = false,
				sType = "checkbox",
				parentCheck = function()
					return addon.SettingsLayout.elements["enableMinimapButtonBin"]
						and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting
						and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting:GetValue() == true
				end,
				parent = true,
				parentSection = buttonSinkSection,
			},
			{
				var = "minimapButtonBinColumns",
				text = L["minimapButtonBinColumns"],
				desc = L["minimapButtonBinColumnsDesc"],
				set = function(val)
					val = math.floor(val + 0.5)
					if val < 1 then
						val = 1
					elseif val > 99 then
						val = 99
					end
					addon.db["minimapButtonBinColumns"] = val
					addon.functions.LayoutButtons()
				end,
				sType = "slider",
				parentCheck = function()
					return addon.SettingsLayout.elements["enableMinimapButtonBin"]
						and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting
						and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting:GetValue() == true
				end,
				parent = true,
				min = 1,
				max = 99,
				step = 1,
				default = 4,
				parentSection = buttonSinkSection,
			},
			{
				text = "|cff99e599" .. L["ignoreMinimapSinkHole"] .. "|r",
				sType = "hint",
				parentSection = buttonSinkSection,
			},
		},
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cMapNav, data)

local function isMinimapButtonBinEnabled()
	return addon.SettingsLayout.elements["enableMinimapButtonBin"]
		and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting
		and addon.SettingsLayout.elements["enableMinimapButtonBin"].setting:GetValue() == true
end

local function isButtonSinkIconModeEnabled()
	return isMinimapButtonBinEnabled()
		and addon.SettingsLayout.elements["useMinimapButtonBinIcon"]
		and addon.SettingsLayout.elements["useMinimapButtonBinIcon"].setting
		and addon.SettingsLayout.elements["useMinimapButtonBinIcon"].setting:GetValue() == true
end

local function getIgnoreState(value)
	if not value then return false end
	return (addon.db["ignoreMinimapSinkHole_" .. value] or addon.db["ignoreMinimapButtonBin_" .. value]) and true or false
end

local function setIgnoreState(value, shouldSelect)
	if not value then return end
	if shouldSelect then
		addon.db["ignoreMinimapSinkHole_" .. value] = true
		addon.db["ignoreMinimapButtonBin_" .. value] = true
	else
		addon.db["ignoreMinimapSinkHole_" .. value] = nil
		addon.db["ignoreMinimapButtonBin_" .. value] = nil
	end
	if addon.functions.LayoutButtons then addon.functions.LayoutButtons() end
end

addon.functions.SettingsCreateMultiDropdown(cMapNav, {
	var = "ignoreMinimapSinkHole",
	text = L["minimapButtonBinIgnore"] or IGNORE,
	parent = true,
	element = addon.SettingsLayout.elements["enableMinimapButtonBin"] and addon.SettingsLayout.elements["enableMinimapButtonBin"].element,
	parentCheck = isMinimapButtonBinEnabled,
	parentSection = buttonSinkSection,
	optionfunc = function()
		local buttons = (addon.variables and addon.variables.bagButtonState) or {}
		local list = {}
		for name in pairs(buttons) do
			local label = tostring(name)
			table.insert(list, { value = name, text = label })
		end
		table.sort(list, function(a, b) return tostring(a.text) < tostring(b.text) end)
		return list
	end,
	isSelectedFunc = getIgnoreState,
	setSelectedFunc = setIgnoreState,
})

----- REGION END

local WORLD_MAP_COORD_DEFAULT_INTERVAL = 0.1

local function getWorldMapCoordInterval()
	local v = addon.db and addon.db.worldMapCoordinatesUpdateInterval
	if type(v) ~= "number" then v = WORLD_MAP_COORD_DEFAULT_INTERVAL end
	if v < 0.01 then v = 0.01 end
	if v > 1.00 then v = 1.00 end
	return v
end

local function ensureWorldMapCoordFrames()
	addon.variables = addon.variables or {}
	local container = WorldMapFrame and WorldMapFrame.BorderFrame and WorldMapFrame.BorderFrame.TitleContainer
	if not container then return nil end

	if not addon.variables.worldMapPlayerCoords then
		addon.variables.worldMapPlayerCoords = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	elseif addon.variables.worldMapPlayerCoords:GetParent() ~= container then
		addon.variables.worldMapPlayerCoords:SetParent(container)
	end

	if not addon.variables.worldMapCursorCoords then
		addon.variables.worldMapCursorCoords = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	elseif addon.variables.worldMapCursorCoords:GetParent() ~= container then
		addon.variables.worldMapCursorCoords:SetParent(container)
	end

	return true
end

local function applyWorldMapCoordLayout(showCursor)
	if not ensureWorldMapCoordFrames() then return end
	local key = tostring(showCursor)
	if addon.variables.worldMapCoordLayoutKey == key then return end
	addon.variables.worldMapCoordLayoutKey = key

	local container = WorldMapFrame and WorldMapFrame.BorderFrame and WorldMapFrame.BorderFrame.TitleContainer
	if not container then return end

	local player = addon.variables.worldMapPlayerCoords
	local cursor = addon.variables.worldMapCursorCoords
	if not player or not cursor then return end

	player:ClearAllPoints()
	cursor:ClearAllPoints()

	if showCursor then
		player:SetPoint("RIGHT", container, "RIGHT", -200, 0)
		player:SetJustifyH("LEFT")
		cursor:SetPoint("RIGHT", container, "RIGHT", -40, 0)
		cursor:SetJustifyH("RIGHT")
	else
		player:SetPoint("RIGHT", container, "RIGHT", -40, 0)
		player:SetJustifyH("RIGHT")
	end
end

local function formatCoords(x, y)
	if not x or not y then return nil end
	return string.format("%.2f, %.2f", x * 100, y * 100)
end

local function getPlayerCoords()
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then return nil end
	if IsInInstance() then return nil end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return nil end
	return pos.x, pos.y
end

local function getCursorCoords()
	if not WorldMapFrame or not WorldMapFrame.ScrollContainer or not WorldMapFrame.ScrollContainer.GetNormalizedCursorPosition then return nil end
	if addon.db and addon.db.worldMapCoordinatesHideCursor then
		if WorldMapFrame.ScrollContainer.IsMouseOver and not WorldMapFrame.ScrollContainer:IsMouseOver() then return nil end
	end
	local x, y = WorldMapFrame.ScrollContainer:GetNormalizedCursorPosition()
	if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
	return x, y
end

local function updateWorldMapCoordinates()
	if not addon.db or not addon.db["showWorldMapCoordinates"] then return end
	if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
	if not ensureWorldMapCoordFrames() then return end

	local px, py = getPlayerCoords()
	local cx, cy = getCursorCoords()

	local playerText = formatCoords(px, py)
	local cursorText = formatCoords(cx, cy)
	local showCursor = cursorText ~= nil and cursorText ~= ""

	applyWorldMapCoordLayout(showCursor)

	if addon.variables.worldMapPlayerCoords then addon.variables.worldMapPlayerCoords:SetText(playerText and (PLAYER .. ": " .. playerText) or "") end
	if addon.variables.worldMapCursorCoords then
		local cursorLabel = MOUSE_LABEL
		addon.variables.worldMapCursorCoords:SetText(showCursor and (cursorLabel .. ": " .. cursorText) or "")
	end
end

local function startWorldMapCoordinates()
	if addon.variables.worldMapCoordTicker or not addon.db or not addon.db["showWorldMapCoordinates"] then return end
	updateWorldMapCoordinates()
	addon.variables.worldMapCoordTicker = C_Timer.NewTicker(getWorldMapCoordInterval(), function()
		if not addon.db or not addon.db["showWorldMapCoordinates"] then
			addon.functions.DisableWorldMapCoordinates()
			return
		end
		if WorldMapFrame and WorldMapFrame:IsShown() then updateWorldMapCoordinates() end
	end)
end

function addon.functions.DisableWorldMapCoordinates()
	if addon.variables.worldMapCoordTicker then
		addon.variables.worldMapCoordTicker:Cancel()
		addon.variables.worldMapCoordTicker = nil
		addon.variables.worldMapCoordLayoutKey = nil
		if addon.variables.worldMapPlayerCoords then addon.variables.worldMapPlayerCoords:SetText("") end
		if addon.variables.worldMapCursorCoords then addon.variables.worldMapCursorCoords:SetText("") end
	end
end

local function ensureWorldMapHooks()
	if addon.variables.worldMapCoordsHooked or not WorldMapFrame then return end
	WorldMapFrame:HookScript("OnShow", function()
		if addon.db and addon.db["showWorldMapCoordinates"] then startWorldMapCoordinates() end
	end)
	WorldMapFrame:HookScript("OnHide", addon.functions.DisableWorldMapCoordinates)
	addon.variables.worldMapCoordsHooked = true
end

function addon.functions.EnableWorldMapCoordinates()
	if not addon.db or not addon.db["showWorldMapCoordinates"] then return end
	ensureWorldMapHooks()
	if WorldMapFrame and WorldMapFrame:IsShown() then startWorldMapCoordinates() end
end

refreshWorldMapCoordinates = function(restartTicker)
	if not addon.db or not addon.db["showWorldMapCoordinates"] then return end
	if restartTicker then
		addon.functions.DisableWorldMapCoordinates()
		addon.functions.EnableWorldMapCoordinates()
		return
	end
	if WorldMapFrame and WorldMapFrame:IsShown() then updateWorldMapCoordinates() end
end

local function applySquareMinimapLayout(self, underneath)
	if not addon.db or not addon.db.enableSquareMinimap or not addon.db.enableSquareMinimapLayout then return end
	if not Minimap or not MinimapCluster or not Minimap.ZoomIn or not Minimap.ZoomOut then return end

	local addonCompartment = _G.AddonCompartmentFrame
	local instanceDifficulty = MinimapCluster and MinimapCluster.InstanceDifficulty
	local indicatorFrame = MinimapCluster and MinimapCluster.IndicatorFrame

	local headerUnderneath = underneath
	if headerUnderneath == nil then
		if MinimapCluster.GetHeaderUnderneath then
			headerUnderneath = MinimapCluster:GetHeaderUnderneath()
		elseif MinimapCluster.headerUnderneath ~= nil then
			headerUnderneath = MinimapCluster.headerUnderneath
		end
	end

	Minimap:ClearAllPoints()
	Minimap.ZoomIn:ClearAllPoints()
	Minimap.ZoomOut:ClearAllPoints()
	if indicatorFrame then indicatorFrame:ClearAllPoints() end
	if addonCompartment then addonCompartment:ClearAllPoints() end
	if instanceDifficulty then instanceDifficulty:ClearAllPoints() end

	if not headerUnderneath then
		Minimap:SetPoint("TOP", MinimapCluster, "TOP", 14, -25)
		if instanceDifficulty then instanceDifficulty:SetPoint("TOPRIGHT", MinimapCluster, "TOPRIGHT", -16, -25) end

		Minimap.ZoomIn:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 0, 0)
		Minimap.ZoomOut:SetPoint("RIGHT", Minimap.ZoomIn, "LEFT", -6, 0)
		if addonCompartment then addonCompartment:SetPoint("BOTTOM", Minimap.ZoomIn, "BOTTOM", 0, 20) end
	else
		Minimap:SetPoint("BOTTOM", MinimapCluster, "BOTTOM", 14, 25)
		if instanceDifficulty then instanceDifficulty:SetPoint("BOTTOMRIGHT", MinimapCluster, "BOTTOMRIGHT", -16, 22) end

		Minimap.ZoomIn:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 0, 0)
		Minimap.ZoomOut:SetPoint("RIGHT", Minimap.ZoomIn, "LEFT", -6, 0)
		if addonCompartment then addonCompartment:SetPoint("TOP", Minimap.ZoomIn, "TOP", 0, -20) end
	end
	if indicatorFrame then indicatorFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 2, -2) end

	if addonCompartment then addonCompartment:SetFrameStrata("MEDIUM") end
end

function addon.functions.applySquareMinimapLayout(forceUnderneath)
	addon.variables = addon.variables or {}
	applySquareMinimapLayout(nil, forceUnderneath)
	if addon.db and addon.db.enableSquareMinimap and addon.db.enableSquareMinimapLayout and MinimapCluster and not addon.variables.squareMinimapLayoutHooked then
		hooksecurefunc(MinimapCluster, "SetHeaderUnderneath", applySquareMinimapLayout)
		addon.variables.squareMinimapLayoutHooked = true
	end
	if not addon.variables.squareMinimapIndicatorHooked and type(_G.MiniMapIndicatorFrame_UpdatePosition) == "function" then
		hooksecurefunc("MiniMapIndicatorFrame_UpdatePosition", function()
			if not addon.db or not addon.db.enableSquareMinimap or not addon.db.enableSquareMinimapLayout then return end
			if not Minimap or not MinimapCluster or not MinimapCluster.IndicatorFrame then return end
			MinimapCluster.IndicatorFrame:ClearAllPoints()
			MinimapCluster.IndicatorFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 2, -2)
		end)
		addon.variables.squareMinimapIndicatorHooked = true
	end
end

local function copyDefaultValue(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for key, subValue in pairs(value) do
		out[key] = copyDefaultValue(subValue)
	end
	return out
end

local squareMinimapStatsDefaults = {
	enableSquareMinimapStats = false,
	squareMinimapStatsFont = STANDARD_TEXT_FONT,
	squareMinimapStatsOutline = "OUTLINE",
	squareMinimapStatsTime = true,
	squareMinimapStatsTimeAnchor = "BOTTOMLEFT",
	squareMinimapStatsTimeOffsetX = 3,
	squareMinimapStatsTimeOffsetY = 17,
	squareMinimapStatsTimeFontSize = 18,
	squareMinimapStatsTimeColor = { r = 1, g = 1, b = 1, a = 1 },
	squareMinimapStatsTimeDisplayMode = "server",
	squareMinimapStatsTimeUse24Hour = true,
	squareMinimapStatsTimeShowSeconds = false,
	squareMinimapStatsFPS = true,
	squareMinimapStatsFPSAnchor = "BOTTOMLEFT",
	squareMinimapStatsFPSOffsetX = 3,
	squareMinimapStatsFPSOffsetY = 3,
	squareMinimapStatsFPSFontSize = 12,
	squareMinimapStatsFPSColor = { r = 1, g = 1, b = 1, a = 1 },
	squareMinimapStatsFPSThresholdMedium = 30,
	squareMinimapStatsFPSThresholdHigh = 60,
	squareMinimapStatsFPSColorLow = { r = 1, g = 0, b = 0, a = 1 },
	squareMinimapStatsFPSColorMid = { r = 1, g = 1, b = 0, a = 1 },
	squareMinimapStatsFPSColorHigh = { r = 0, g = 1, b = 0, a = 1 },
	squareMinimapStatsFPSUpdateInterval = 0.25,
	squareMinimapStatsLatency = true,
	squareMinimapStatsLatencyAnchor = "BOTTOMRIGHT",
	squareMinimapStatsLatencyOffsetX = -3,
	squareMinimapStatsLatencyOffsetY = 3,
	squareMinimapStatsLatencyFontSize = 12,
	squareMinimapStatsLatencyColor = { r = 1, g = 1, b = 1, a = 1 },
	squareMinimapStatsLatencyMode = "max",
	squareMinimapStatsLatencyThresholdLow = 50,
	squareMinimapStatsLatencyThresholdMid = 150,
	squareMinimapStatsLatencyColorLow = { r = 0, g = 1, b = 0, a = 1 },
	squareMinimapStatsLatencyColorMid = { r = 1, g = 0.65, b = 0, a = 1 },
	squareMinimapStatsLatencyColorHigh = { r = 1, g = 0, b = 0, a = 1 },
	squareMinimapStatsLatencyUpdateInterval = 1.0,
	squareMinimapStatsLocation = true,
	squareMinimapStatsLocationAnchor = "TOP",
	squareMinimapStatsLocationOffsetX = 0,
	squareMinimapStatsLocationOffsetY = -3,
	squareMinimapStatsLocationFontSize = 12,
	squareMinimapStatsLocationColor = { r = 1, g = 1, b = 1, a = 1 },
	squareMinimapStatsLocationShowSubzone = false,
	squareMinimapStatsLocationUseZoneColor = true,
	squareMinimapStatsCoordinates = true,
	squareMinimapStatsCoordinatesAnchor = "TOP",
	squareMinimapStatsCoordinatesOffsetX = 0,
	squareMinimapStatsCoordinatesOffsetY = -17,
	squareMinimapStatsCoordinatesFontSize = 12,
	squareMinimapStatsCoordinatesColor = { r = 1, g = 1, b = 1, a = 1 },
	squareMinimapStatsCoordinatesHideInInstance = true,
	squareMinimapStatsCoordinatesUpdateInterval = 0.2,
}

local squareMinimapStatsConfig = {
	time = {
		enabledKey = "squareMinimapStatsTime",
		anchorKey = "squareMinimapStatsTimeAnchor",
		offsetXKey = "squareMinimapStatsTimeOffsetX",
		offsetYKey = "squareMinimapStatsTimeOffsetY",
		fontSizeKey = "squareMinimapStatsTimeFontSize",
		colorKey = "squareMinimapStatsTimeColor",
		anchorPoint = "BOTTOMLEFT",
	},
	fps = {
		enabledKey = "squareMinimapStatsFPS",
		anchorKey = "squareMinimapStatsFPSAnchor",
		offsetXKey = "squareMinimapStatsFPSOffsetX",
		offsetYKey = "squareMinimapStatsFPSOffsetY",
		fontSizeKey = "squareMinimapStatsFPSFontSize",
		colorKey = "squareMinimapStatsFPSColor",
		anchorPoint = "BOTTOMLEFT",
	},
	latency = {
		enabledKey = "squareMinimapStatsLatency",
		anchorKey = "squareMinimapStatsLatencyAnchor",
		offsetXKey = "squareMinimapStatsLatencyOffsetX",
		offsetYKey = "squareMinimapStatsLatencyOffsetY",
		fontSizeKey = "squareMinimapStatsLatencyFontSize",
		colorKey = "squareMinimapStatsLatencyColor",
		anchorPoint = "BOTTOMRIGHT",
	},
	location = {
		enabledKey = "squareMinimapStatsLocation",
		anchorKey = "squareMinimapStatsLocationAnchor",
		offsetXKey = "squareMinimapStatsLocationOffsetX",
		offsetYKey = "squareMinimapStatsLocationOffsetY",
		fontSizeKey = "squareMinimapStatsLocationFontSize",
		colorKey = "squareMinimapStatsLocationColor",
		anchorPoint = "TOP",
	},
	coordinates = {
		enabledKey = "squareMinimapStatsCoordinates",
		anchorKey = "squareMinimapStatsCoordinatesAnchor",
		offsetXKey = "squareMinimapStatsCoordinatesOffsetX",
		offsetYKey = "squareMinimapStatsCoordinatesOffsetY",
		fontSizeKey = "squareMinimapStatsCoordinatesFontSize",
		colorKey = "squareMinimapStatsCoordinatesColor",
		anchorPoint = "TOP",
	},
}

local squareMinimapStatsOrder = { "time", "fps", "latency", "location", "coordinates" }

local function ensureSquareMinimapStatsDefaults()
	if not addon.db then return end
	for key, value in pairs(squareMinimapStatsDefaults) do
		if addon.db[key] == nil then addon.db[key] = copyDefaultValue(value) end
	end
	addon.db.squareMinimapStatsFont = normalizeSquareMinimapStatsFontSelection(addon.db.squareMinimapStatsFont, nil)
	addon.db.squareMinimapStatsOutline = normalizeSquareMinimapStatsOutlineSelection(addon.db.squareMinimapStatsOutline, nil)
	addon.db.squareMinimapStatsTimeAnchor = normalizeSquareMinimapAnchorSelection(addon.db.squareMinimapStatsTimeAnchor, nil, squareMinimapStatsDefaults.squareMinimapStatsTimeAnchor)
	addon.db.squareMinimapStatsFPSAnchor = normalizeSquareMinimapAnchorSelection(addon.db.squareMinimapStatsFPSAnchor, nil, squareMinimapStatsDefaults.squareMinimapStatsFPSAnchor)
	addon.db.squareMinimapStatsLatencyAnchor = normalizeSquareMinimapAnchorSelection(addon.db.squareMinimapStatsLatencyAnchor, nil, squareMinimapStatsDefaults.squareMinimapStatsLatencyAnchor)
	addon.db.squareMinimapStatsLocationAnchor = normalizeSquareMinimapAnchorSelection(addon.db.squareMinimapStatsLocationAnchor, nil, squareMinimapStatsDefaults.squareMinimapStatsLocationAnchor)
	addon.db.squareMinimapStatsCoordinatesAnchor =
		normalizeSquareMinimapAnchorSelection(addon.db.squareMinimapStatsCoordinatesAnchor, nil, squareMinimapStatsDefaults.squareMinimapStatsCoordinatesAnchor)
end

local function getSquareMinimapStatsState()
	addon.variables = addon.variables or {}
	addon.variables.squareMinimapStats = addon.variables.squareMinimapStats or {
		frames = {},
		elapsed = {},
	}
	return addon.variables.squareMinimapStats
end

local function clamp(value, minimum, maximum)
	if value < minimum then return minimum end
	if value > maximum then return maximum end
	return value
end

local function shouldShowSquareMinimapStats() return addon.db and addon.db.enableSquareMinimap and addon.db.enableSquareMinimapStats end

local function getSquareMinimapStatsColor(colorKey)
	local fallback = squareMinimapStatsDefaults[colorKey] or { r = 1, g = 1, b = 1, a = 1 }
	local color = addon.db and addon.db[colorKey]
	if type(color) ~= "table" then color = fallback end
	return clamp(tonumber(color.r) or fallback.r or 1, 0, 1),
		clamp(tonumber(color.g) or fallback.g or 1, 0, 1),
		clamp(tonumber(color.b) or fallback.b or 1, 0, 1),
		clamp(tonumber(color.a) or fallback.a or 1, 0, 1)
end

local function getSquareMinimapStatsFontPath()
	local fallback = (addon.variables and addon.variables.defaultFont) or STANDARD_TEXT_FONT
	if addon.functions and addon.functions.ResolveFontFace then return addon.functions.ResolveFontFace(addon.db and addon.db.squareMinimapStatsFont, fallback) or fallback end
	local font = addon.db and addon.db.squareMinimapStatsFont
	if type(font) ~= "string" or font == "" then font = fallback end
	return font
end

local function getSquareMinimapStatsOutlineFlag()
	local outline = normalizeSquareMinimapStatsOutlineSelection(addon.db and addon.db.squareMinimapStatsOutline, nil)
	if outline == nil or outline == "" or outline == "NONE" then return nil end
	return outline
end

local function colorizeSquareMinimapText(text, r, g, b)
	local rr = math.floor(clamp(r or 1, 0, 1) * 255 + 0.5)
	local gg = math.floor(clamp(g or 1, 0, 1) * 255 + 0.5)
	local bb = math.floor(clamp(b or 1, 0, 1) * 255 + 0.5)
	return ("|cff%02x%02x%02x%s|r"):format(rr, gg, bb, tostring(text or ""))
end

local function getSquareMinimapFPSColor(value)
	local medium = math.floor((tonumber(addon.db and addon.db.squareMinimapStatsFPSThresholdMedium) or 30) + 0.5)
	local high = math.floor((tonumber(addon.db and addon.db.squareMinimapStatsFPSThresholdHigh) or 60) + 0.5)
	if medium < 1 then medium = 1 end
	if high < medium then high = medium end
	if value >= high then return getSquareMinimapStatsColor("squareMinimapStatsFPSColorHigh") end
	if value >= medium then return getSquareMinimapStatsColor("squareMinimapStatsFPSColorMid") end
	return getSquareMinimapStatsColor("squareMinimapStatsFPSColorLow")
end

local function getSquareMinimapLatencyColor(value)
	local low = math.floor((tonumber(addon.db and addon.db.squareMinimapStatsLatencyThresholdLow) or 50) + 0.5)
	local medium = math.floor((tonumber(addon.db and addon.db.squareMinimapStatsLatencyThresholdMid) or 150) + 0.5)
	if low < 0 then low = 0 end
	if medium < low then medium = low end
	if value <= low then return getSquareMinimapStatsColor("squareMinimapStatsLatencyColorLow") end
	if value <= medium then return getSquareMinimapStatsColor("squareMinimapStatsLatencyColorMid") end
	return getSquareMinimapStatsColor("squareMinimapStatsLatencyColorHigh")
end

local function getSquareMinimapStatsZoneColor()
	local zoneType = C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo() or nil
	if zoneType == "sanctuary" then return 0.41, 0.80, 0.94 end
	if zoneType == "arena" then return 1.00, 0.10, 0.10 end
	if zoneType == "friendly" then return 0.10, 1.00, 0.10 end
	if zoneType == "hostile" then return 1.00, 0.10, 0.10 end
	if zoneType == "contested" then return 1.00, 0.70, 0.00 end
	return (NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.r) or 1, (NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.g) or 0.82, (NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.b) or 0
end

local function getSquareMinimapStatJustify(point)
	if point == "TOP" or point == "BOTTOM" or point == "CENTER" then return "CENTER" end
	if point and point:find("RIGHT", 1, true) then return "RIGHT" end
	if point and point:find("LEFT", 1, true) then return "LEFT" end
	return "CENTER"
end

local function normalizeSquareMinimapAnchor(anchor, fallback)
	if type(anchor) == "string" and squareMinimapStatsAnchorOptions[anchor] then return anchor end
	if type(fallback) == "string" and squareMinimapStatsAnchorOptions[fallback] then return fallback end
	return "CENTER"
end

local function getSquareMinimapFontStringWidth(fontString)
	if not fontString then return 0 end
	local width = fontString.GetUnboundedStringWidth and fontString:GetUnboundedStringWidth() or nil
	if not width or width <= 0 then width = fontString:GetStringWidth() or 0 end
	return width
end

local function ensureSquareMinimapStatFrame(statKey)
	local state = getSquareMinimapStatsState()
	local existing = state.frames[statKey]
	if existing and existing.text then
		if not existing.textSecondary then
			existing.textSecondary = existing:CreateFontString(nil, "OVERLAY")
			existing.textSecondary:SetWordWrap(false)
			existing.textSecondary:SetJustifyV("MIDDLE")
			existing.textSecondary:Hide()
		end
		return existing
	end
	if not Minimap then return nil end

	local frame = CreateFrame("Frame", addonName .. "SquareMinimapStat_" .. statKey, Minimap)
	frame:SetFrameStrata("HIGH")
	frame:SetFrameLevel((Minimap:GetFrameLevel() or 2) + 20)
	frame.text = frame:CreateFontString(nil, "OVERLAY")
	frame.text:SetWordWrap(false)
	frame.text:SetJustifyV("MIDDLE")
	frame.textSecondary = frame:CreateFontString(nil, "OVERLAY")
	frame.textSecondary:SetWordWrap(false)
	frame.textSecondary:SetJustifyV("MIDDLE")
	frame.textSecondary:Hide()
	frame:Hide()
	state.frames[statKey] = frame
	return frame
end

local function hideSquareMinimapStats()
	local state = getSquareMinimapStatsState()
	for _, frame in pairs(state.frames) do
		if frame then frame:Hide() end
	end
end

local function formatSquareMinimapClock(hours, minutes, seconds, use24Hour, showSeconds)
	if hours == nil or minutes == nil then return "" end
	local h = hours
	local m = minutes
	local s = seconds or 0
	local suffix = ""
	if not use24Hour then
		local isPM = h >= 12
		suffix = isPM and (TIMEMANAGER_PM or "PM") or (TIMEMANAGER_AM or "AM")
		h = h % 12
		if h == 0 then h = 12 end
	end
	if showSeconds then
		if use24Hour then return ("%02d:%02d:%02d"):format(h, m, s) end
		return ("%d:%02d:%02d %s"):format(h, m, s, suffix)
	end
	if use24Hour then return ("%02d:%02d"):format(h, m) end
	return ("%d:%02d %s"):format(h, m, suffix)
end

local function getSquareMinimapTimeText()
	local localParts = date("*t")
	local localHour = localParts and localParts.hour or nil
	local localMinute = localParts and localParts.min or nil
	local localSecond = localParts and localParts.sec or 0

	local serverHour, serverMinute = nil, nil
	if GetGameTime then
		serverHour, serverMinute = GetGameTime()
	end

	local use24Hour = addon.db.squareMinimapStatsTimeUse24Hour ~= false
	local showSeconds = addon.db.squareMinimapStatsTimeShowSeconds == true
	local mode = addon.db.squareMinimapStatsTimeDisplayMode or "server"

	local localText = formatSquareMinimapClock(localHour, localMinute, localSecond, use24Hour, showSeconds)
	local serverText = formatSquareMinimapClock(serverHour, serverMinute, localSecond, use24Hour, showSeconds)

	if mode == "localTime" then return localText end
	if mode == "both" then
		if serverText == "" then return localText end
		if localText == "" then return serverText end
		return ("%s / %s"):format(serverText, localText)
	end
	if serverText == "" then return localText end
	return serverText
end

local function getSquareMinimapLocationText()
	local zone = GetZoneText and GetZoneText() or nil
	if not zone or zone == "" then zone = GetRealZoneText and GetRealZoneText() or "" end
	local subzone = GetSubZoneText and GetSubZoneText() or ""
	local showSubzone = addon.db.squareMinimapStatsLocationShowSubzone ~= false
	if showSubzone and subzone ~= "" and subzone ~= zone then
		if zone and zone ~= "" then return zone .. " - " .. subzone end
		return subzone
	end
	if zone and zone ~= "" then return zone end
	return subzone
end

local function getSquareMinimapCoordinatesText()
	if addon.db.squareMinimapStatsCoordinatesHideInInstance and IsInInstance and IsInInstance() then return "" end
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return "" end
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then return "" end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return "" end
	return string.format("%.2f, %.2f", (pos.x or 0) * 100, (pos.y or 0) * 100)
end

local function getSquareMinimapLatencySplitTexts()
	local _, _, home, world = GetNetStats()
	home = math.floor((home or 0) + 0.5)
	world = math.floor((world or 0) + 0.5)
	local hr, hg, hb = getSquareMinimapLatencyColor(home)
	local wr, wg, wb = getSquareMinimapLatencyColor(world)
	local homeText = ("H %sms"):format(colorizeSquareMinimapText(home, hr, hg, hb))
	local worldText = ("W %sms"):format(colorizeSquareMinimapText(world, wr, wg, wb))
	return homeText, worldText, home, world
end

local function getSquareMinimapLatencyText()
	local mode = addon.db.squareMinimapStatsLatencyMode or "max"
	local homeText, worldText, home, world = getSquareMinimapLatencySplitTexts()
	if mode == "home" then return homeText end
	if mode == "world" then return worldText end
	if mode == "split" then return ("%s / %s"):format(homeText, worldText) end
	if mode == "split_vertical" then return ("%s\n%s"):format(homeText, worldText) end
	local maxValue = math.max(home, world)
	local mr, mg, mb = getSquareMinimapLatencyColor(maxValue)
	return ("MS %s"):format(colorizeSquareMinimapText(maxValue, mr, mg, mb))
end

local function getSquareMinimapStatText(statKey)
	if statKey == "time" then return getSquareMinimapTimeText() end
	if statKey == "fps" then
		local fps = math.floor((GetFramerate() or 0) + 0.5)
		local fr, fg, fb = getSquareMinimapFPSColor(fps)
		return ("FPS %s"):format(colorizeSquareMinimapText(fps, fr, fg, fb))
	end
	if statKey == "latency" then return getSquareMinimapLatencyText() end
	if statKey == "location" then return getSquareMinimapLocationText() end
	if statKey == "coordinates" then return getSquareMinimapCoordinatesText() end
	return ""
end

local function getSquareMinimapStatsInterval(statKey)
	if statKey == "time" then
		if addon.db.squareMinimapStatsTimeShowSeconds == true then return 1 end
		return 15
	end
	if statKey == "fps" then return clamp(tonumber(addon.db.squareMinimapStatsFPSUpdateInterval) or 0.25, 0.1, 2.0) end
	if statKey == "latency" then return clamp(tonumber(addon.db.squareMinimapStatsLatencyUpdateInterval) or 1.0, 0.2, 5.0) end
	if statKey == "coordinates" then return clamp(tonumber(addon.db.squareMinimapStatsCoordinatesUpdateInterval) or 0.2, 0.1, 1.0) end
	return 0.5
end

local function updateSquareMinimapStat(statKey)
	local cfg = squareMinimapStatsConfig[statKey]
	if not cfg then return end
	local frame = ensureSquareMinimapStatFrame(statKey)
	if not frame then return end

	if not shouldShowSquareMinimapStats() or addon.db[cfg.enabledKey] ~= true then
		frame:Hide()
		return
	end

	local point = normalizeSquareMinimapAnchor(addon.db[cfg.anchorKey], cfg.anchorPoint)
	local x = tonumber(addon.db[cfg.offsetXKey]) or squareMinimapStatsDefaults[cfg.offsetXKey] or 0
	local y = tonumber(addon.db[cfg.offsetYKey]) or squareMinimapStatsDefaults[cfg.offsetYKey] or 0
	local size = clamp(tonumber(addon.db[cfg.fontSizeKey]) or squareMinimapStatsDefaults[cfg.fontSizeKey] or 12, 8, 32)
	local latencyMode = statKey == "latency" and (addon.db.squareMinimapStatsLatencyMode or "max") or nil
	local useVerticalLatency = statKey == "latency" and latencyMode == "split_vertical"
	local lineGap = math.max(math.floor(size * 0.15), 2)

	frame:ClearAllPoints()
	frame:SetPoint(point, Minimap, point, x, y)

	local r, g, b, a = getSquareMinimapStatsColor(cfg.colorKey)
	if statKey == "location" and addon.db.squareMinimapStatsLocationUseZoneColor then
		r, g, b = getSquareMinimapStatsZoneColor()
		a = 1
	end

	frame.text:ClearAllPoints()
	frame.text:SetPoint(point, frame, point, 0, 0)
	frame.text:SetJustifyH(getSquareMinimapStatJustify(point))
	frame.textSecondary:ClearAllPoints()
	frame.textSecondary:SetPoint(point, frame, point, 0, 0)
	frame.textSecondary:SetJustifyH(getSquareMinimapStatJustify(point))
	frame.textSecondary:Hide()
	local fontPath = getSquareMinimapStatsFontPath()
	local outline = getSquareMinimapStatsOutlineFlag()
	local ok = frame.text:SetFont(fontPath, size, outline)
	if not ok then frame.text:SetFont((addon.variables and addon.variables.defaultFont) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, outline) end
	local okSecondary = frame.textSecondary:SetFont(fontPath, size, outline)
	if not okSecondary then frame.textSecondary:SetFont((addon.variables and addon.variables.defaultFont) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, outline) end
	frame.textSecondary:SetText("")
	frame.text:SetTextColor(r, g, b, a)
	frame.textSecondary:SetTextColor(r, g, b, a)
	if useVerticalLatency then
		local homeText, worldText = getSquareMinimapLatencySplitTexts()
		local stackUpwards = point and point:find("BOTTOM", 1, true) ~= nil
		if stackUpwards then
			frame.text:SetText(worldText)
			frame.textSecondary:SetPoint(point, frame, point, 0, size + lineGap)
			frame.textSecondary:SetText(homeText)
		else
			frame.text:SetText(homeText)
			frame.textSecondary:SetPoint(point, frame, point, 0, -(size + lineGap))
			frame.textSecondary:SetText(worldText)
		end
		frame.textSecondary:Show()
	else
		frame.text:SetText(getSquareMinimapStatText(statKey) or "")
	end

	local primaryText = frame.text:GetText() or ""
	local secondaryText = frame.textSecondary:GetText() or ""
	if primaryText == "" and secondaryText == "" then
		frame:Hide()
		return
	end

	local width = getSquareMinimapFontStringWidth(frame.text)
	local height = frame.text:GetStringHeight()
	if frame.textSecondary:IsShown() then
		width = math.max(width, getSquareMinimapFontStringWidth(frame.textSecondary))
		height = height + frame.textSecondary:GetStringHeight() + lineGap
	end
	frame:SetSize(math.max(width, 1), math.max(height, 1))
	frame:Show()
end

local function stopSquareMinimapStatsTicker()
	local state = getSquareMinimapStatsState()
	if state.ticker then
		state.ticker:Cancel()
		state.ticker = nil
	end
	state.tickerInterval = nil
end

local function isSquareMinimapStatEnabled(statKey)
	local cfg = squareMinimapStatsConfig[statKey]
	return cfg and addon.db and addon.db[cfg.enabledKey] == true
end

local function hasEnabledSquareMinimapStats()
	if not addon.db then return false end
	for _, statKey in ipairs(squareMinimapStatsOrder) do
		if isSquareMinimapStatEnabled(statKey) then return true end
	end
	return false
end

local function shouldRunSquareMinimapStats() return shouldShowSquareMinimapStats() and hasEnabledSquareMinimapStats() end

local function getSquareMinimapStatsTickInterval()
	local shortest = nil
	for _, statKey in ipairs(squareMinimapStatsOrder) do
		if isSquareMinimapStatEnabled(statKey) then
			local interval = getSquareMinimapStatsInterval(statKey)
			if interval and interval > 0 and (not shortest or interval < shortest) then shortest = interval end
		end
	end
	if not shortest then return nil end
	return clamp(shortest, 0.1, 1.0)
end

local function handleSquareMinimapStatsEvent(event)
	if not shouldRunSquareMinimapStats() then return end
	local state = getSquareMinimapStatsState()
	if event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
		if isSquareMinimapStatEnabled("location") then
			updateSquareMinimapStat("location")
			state.elapsed.location = 0
		end
		if isSquareMinimapStatEnabled("coordinates") then
			updateSquareMinimapStat("coordinates")
			state.elapsed.coordinates = 0
		end
		return
	end
	for _, statKey in ipairs(squareMinimapStatsOrder) do
		if isSquareMinimapStatEnabled(statKey) then
			updateSquareMinimapStat(statKey)
			state.elapsed[statKey] = 0
		end
	end
end

local function syncSquareMinimapStatsEvents()
	local state = getSquareMinimapStatsState()
	if not state.eventFrame then
		if not shouldRunSquareMinimapStats() then return end
		local frame = CreateFrame("Frame")
		frame:SetScript("OnEvent", function(_, event) handleSquareMinimapStatsEvent(event) end)
		state.eventFrame = frame
	end

	local frame = state.eventFrame
	if not frame then return end
	frame:UnregisterAllEvents()
	if not shouldRunSquareMinimapStats() then return end
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	if isSquareMinimapStatEnabled("location") or isSquareMinimapStatEnabled("coordinates") then
		frame:RegisterEvent("ZONE_CHANGED")
		frame:RegisterEvent("ZONE_CHANGED_INDOORS")
		frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	end
end

local function updateSquareMinimapStatsTicker(delta)
	if not shouldRunSquareMinimapStats() then
		hideSquareMinimapStats()
		stopSquareMinimapStatsTicker()
		syncSquareMinimapStatsEvents()
		return
	end

	local state = getSquareMinimapStatsState()
	for _, statKey in ipairs(squareMinimapStatsOrder) do
		if isSquareMinimapStatEnabled(statKey) then
			state.elapsed[statKey] = (state.elapsed[statKey] or 0) + delta
			local interval = getSquareMinimapStatsInterval(statKey)
			if state.elapsed[statKey] >= interval then
				state.elapsed[statKey] = 0
				updateSquareMinimapStat(statKey)
			end
		else
			state.elapsed[statKey] = 0
			local frame = state.frames[statKey]
			if frame then frame:Hide() end
		end
	end
end

local function ensureSquareMinimapStatsTicker()
	local state = getSquareMinimapStatsState()
	local desiredInterval = getSquareMinimapStatsTickInterval()
	if not desiredInterval then
		stopSquareMinimapStatsTicker()
		return
	end
	if state.ticker and state.tickerInterval and math.abs(state.tickerInterval - desiredInterval) < 0.001 then return end
	stopSquareMinimapStatsTicker()
	state.tickerInterval = desiredInterval
	state.ticker = C_Timer.NewTicker(desiredInterval, function() updateSquareMinimapStatsTicker(desiredInterval) end)
end

function addon.functions.applySquareMinimapStats(force)
	ensureSquareMinimapStatsDefaults()
	if not Minimap then return end

	local state = getSquareMinimapStatsState()
	syncSquareMinimapStatsEvents()
	if not shouldRunSquareMinimapStats() then
		hideSquareMinimapStats()
		stopSquareMinimapStatsTicker()
		return
	end

	ensureSquareMinimapStatsTicker()

	for _, statKey in ipairs(squareMinimapStatsOrder) do
		if force then state.elapsed[statKey] = 0 end
		if isSquareMinimapStatEnabled(statKey) then
			updateSquareMinimapStat(statKey)
		else
			state.elapsed[statKey] = 0
			local frame = state.frames[statKey]
			if frame then frame:Hide() end
		end
	end
end

function addon.functions.initMapNav()
	addon.functions.applySquareMinimapLayout()
	if addon.functions.applySquareMinimapStats then addon.functions.applySquareMinimapStats(true) end
	if addon.functions.applyMinimapClusterClamp then addon.functions.applyMinimapClusterClamp() end
	if addon.functions.applyMinimapButtonMouseover then addon.functions.applyMinimapButtonMouseover() end
	addon.functions.EnableWorldMapCoordinates()
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
