local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local cMapNav = addon.functions.SettingsCreateCategory(nil, L["MapNavigation"], nil, "MapNavigation")
addon.SettingsLayout.mapNavigationCategory = cMapNav

addon.functions.SettingsCreateHeadline(cMapNav, MINIMAP_LABEL)

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
	},
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
		children = {
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
				default = false,
				sType = "colorpicker",
				notify = "enableSquareMinimap",
				callback = function()
					if addon.functions.applySquareMinimapBorder then addon.functions.applySquareMinimapBorder() end
				end,
			},
		},
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cMapNav, data)

addon.functions.SettingsCreateMultiDropdown(cMapNav, {
	var = "hiddenMinimapElements",
	text = L["minimapHideElements"],
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

addon.functions.SettingsCreateHeadline(cMapNav, SPECIALIZATION)

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
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cMapNav, data)

addon.functions.SettingsCreateHeadline(cMapNav, L["MinimapButtonSinkGroup"])

data = {
	{
		var = "enableMinimapButtonBin",
		text = L["enableMinimapButtonBin"],
		desc = L["enableMinimapButtonBin"],
		func = function(key)
			addon.db["enableMinimapButtonBin"] = key
			addon.functions.toggleButtonSink()
		end,
		default = false,
		children = {
			{
				var = "useMinimapButtonBinIcon",
				text = L["useMinimapButtonBinIcon"],
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
			},
			{
				var = "useMinimapButtonBinMouseover",
				text = L["useMinimapButtonBinMouseover"],
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
			},
			{
				var = "lockMinimapButtonBin",
				text = L["lockMinimapButtonBin"],
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
			},
			{
				var = "minimapButtonBinHideBorder",
				text = L["minimapButtonBinHideBorder"],
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
			},
			{
				var = "minimapButtonBinHideBackground",
				text = L["minimapButtonBinHideBackground"],
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
			},
			{
				var = "minimapButtonBinColumns",
				text = L["minimapButtonBinColumns"],
				set = function(val)
					val = math.floor(val + 0.5)
					if val < 1 then
						val = 1
					elseif val > 10 then
						val = 10
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
				max = 10,
				step = 1,
				default = 4,
			},
			{
				text = "|cff99e599" .. L["ignoreMinimapSinkHole"] .. "|r",
				sType = "hint",
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
	text = IGNORE,
	parent = true,
	element = addon.SettingsLayout.elements["enableMinimapButtonBin"] and addon.SettingsLayout.elements["enableMinimapButtonBin"].element,
	parentCheck = isMinimapButtonBinEnabled,
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

addon.functions.SettingsCreateHeadline(cMapNav, L["LandingPage"])

data = {
	{
		var = "enableLandingPageMenu",
		text = L["enableLandingPageMenu"],
		desc = L["enableLandingPageMenuDesc"],
		func = function(key) addon.db["enableLandingPageMenu"] = key end,
		default = false,
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cMapNav, data)

addon.functions.SettingsCreateText(cMapNav, "|cff99e599" .. L["landingPageHide"] .. "|r")

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

addon.functions.SettingsCreateHeadline(cMapNav, L["showInstanceDifficulty"])

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
			},
			{
				var = "instanceDifficultyColors",
				subvar = "LFR",
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
			},
			{
				var = "instanceDifficultyColors",
				subvar = "NM",
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
			},
			{
				var = "instanceDifficultyColors",
				subvar = "HC",
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
			},
			{
				var = "instanceDifficultyColors",
				subvar = "M",
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
			},
			{
				var = "instanceDifficultyColors",
				subvar = "MPLUS",
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
			},
			{
				var = "instanceDifficultyColors",
				subvar = "TW",
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
			},
		},
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cMapNav, data)

----- REGION END

function addon.functions.initMapNav() end

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
