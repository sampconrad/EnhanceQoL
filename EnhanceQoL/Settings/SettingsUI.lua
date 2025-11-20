local addonName, addon = ...

addon.SettingsLayout = {}

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

function addon.functions.SettingsCreateCategory(parent, treeName, sort)
	if nil == parent then parent = addon.SettingsLayout.rootCategory end
	local cat, layout = Settings.RegisterVerticalLayoutSubcategory(parent, treeName)
	Settings.RegisterAddOnCategory(cat)
	cat:SetShouldSortAlphabetically(sort or true)
	return cat, layout
end

function addon.functions.SettingsCreateCheckbox(cat, cbData)
	local setting = Settings.RegisterProxySetting(
		cat,
		"EQOL_" .. cbData.var,
		Settings.VarType.Boolean,
		cbData.text,
		false,
		cbData.get or function() return addon.db[cbData.var] end, -- Getter
		cbData.func
	)
	local element = Settings.CreateCheckbox(cat, setting, cbData.desc)
	if cbData.parent then element:SetParentInitializer(cbData.element, cbData.parentCheck) end
	return { setting = setting, element = element }
end

function addon.functions.SettingsCreateCheckboxes(cat, data)
	local rData = {}
	for _, cbData in ipairs(data) do
		rData[cbData.var] = addon.functions.SettingsCreateCheckbox(cat, cbData)
	end
	return rData
end

function addon.functions.SettingsCreateHeadline(cat, text)
	local charHeader = Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", { name = text })
	Settings.RegisterInitializer(cat, charHeader)
	charHeader:AddSearchTags(text)
end

function addon.functions.SettingsCreateButton(layout, text, func, searchtags)
	searchtags = searchtags or false
	local btn = CreateSettingsButtonInitializer("", text, func or function() end, nil, searchtags)
	layout:AddInitializer(btn)
end

local function buildHistoryOptions()
	local container = Settings.CreateControlTextContainer()
	container:Add("", L["SettingsChatHistoryPlaceholder"])
	local entries = {}
	for name in pairs(EnhanceQoL_IMHistory or {}) do
		table.insert(entries, name)
	end
	table.sort(entries, function(a, b) return string.lower(a or "") < string.lower(b or "") end)
	for _, name in ipairs(entries) do
		container:Add(name, name)
	end
	if #entries > 0 then container:Add(CLEAR_HISTORY_VALUE, L["ChatIMHistoryClearAll"]) end
	return container:GetData()
end

function addon.functions.SettingsCreateDropdown(cat, cbData, searchtags)
	local container = Settings.CreateControlTextContainer()
	local entries = {}
	for name in pairs(cbData.list or {}) do
		table.insert(entries, name)
	end
	table.sort(entries, function(a, b) return string.lower(a or "") < string.lower(b or "") end)
	for _, name in ipairs(entries) do
		container:Add(name, name)
	end

	local setting = Settings.RegisterProxySetting(cat, "EQOL_" .. cbData.var, Settings.VarType.String, cbData.text, false, cbData.get, cbData.set)

	local dropdown = Settings.CreateDropdown(cat, setting, container.GetData, cbData.desc)
	-- if historyDropdown.SetParentInitializer then historyDropdown:SetParentInitializer(imElement, isIMEnabled) end
end

local cat, layout = Settings.RegisterVerticalLayoutCategory(addonName)
cat:SetShouldSortAlphabetically(true)

Settings.RegisterAddOnCategory(cat)
addon.SettingsLayout.rootCategory = cat
addon.SettingsLayout.rootLayout = layout
