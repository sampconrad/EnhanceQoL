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

function addon.functions.initMapNav()
	addon.functions.applySquareMinimapLayout()
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
