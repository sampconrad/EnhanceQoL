local addonName, addon = ...

addon.SettingsLayout = {}
addon.SettingsLayout.elements = {}

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
	addon.SettingsLayout.elements[cbData.var] = { setting = setting, element = element }
	if cbData.parent then element:SetParentInitializer(cbData.element, cbData.parentCheck) end

	if cbData.children then
		for _, v in pairs(cbData.children) do
			v.element = element
			if v.sType == "dropdown" then addon.functions.SettingsCreateDropdown(cat, v) end
		end
	end
	return addon.SettingsLayout.elements[cbData.var]
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

function addon.functions.SettingsCreateDropdown(cat, cbData, searchtags)
	local options = function()
		local container = Settings.CreateControlTextContainer()
		for key, value in pairs(cbData.list or {}) do
			container:Add(key, value)
		end
		return container:GetData()
	end

	local setting = Settings.RegisterProxySetting(cat, "EQOL_" .. cbData.var, cbData.type or Settings.VarType.String, cbData.text, cbData.default, cbData.get, cbData.set)

	local dropdown = Settings.CreateDropdown(cat, setting, options, cbData.desc)
	if cbData.parent then dropdown:SetParentInitializer(cbData.element, cbData.parentCheck) end
end

local cat, layout = Settings.RegisterVerticalLayoutCategory(addonName)
cat:SetShouldSortAlphabetically(true)

Settings.RegisterAddOnCategory(cat)
addon.SettingsLayout.rootCategory = cat
addon.SettingsLayout.rootLayout = layout
