local addonName, addon = ...

addon.SettingsLayout = {}
addon.SettingsLayout.elements = {}
addon.SettingsLayout.knownCategoryID = {}

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

hooksecurefunc(SettingsCategoryListButtonMixin, "Init", function(self, initializer)
	local category = initializer.data.category
	if not category._EQOL_NewTagID or not addon.SettingsLayout.knownCategoryID[category:GetID()] or not addon.variables.NewVersionTableEQOL[category._EQOL_NewTagID] then return end

	if self.NewFeature then self.NewFeature:SetShown(true) end
end)

hooksecurefunc(SettingsCheckboxControlMixin, "Init", function(self)
	local setting = self.GetSetting and self:GetSetting()
	if not setting or not setting.variable or not addon.variables.NewVersionTableEQOL[setting.variable] then return end
	if self.NewFeature then self.NewFeature:SetShown(true) end
end)
hooksecurefunc(SettingsDropdownControlMixin, "Init", function(self)
	local setting = self.GetSetting and self:GetSetting()
	if not setting or not setting.variable or not addon.variables.NewVersionTableEQOL[setting.variable] then return end
	if self.NewFeature then self.NewFeature:SetShown(true) end
end)

function addon.functions.SettingsCreateCategory(parent, treeName, sort, newTagID)
	if nil == parent then parent = addon.SettingsLayout.rootCategory end
	local cat, layout = Settings.RegisterVerticalLayoutSubcategory(parent, treeName)
	Settings.RegisterAddOnCategory(cat)
	addon.SettingsLayout.knownCategoryID[cat:GetID()] = true
	cat._EQOL_NewTagID = newTagID
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

function addon.functions.SettingsCreateText(cat, text)
	local charHeader = Settings.CreateElementInitializer("EQOL_SettingsListSectionHintTemplate", { name = text })
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
		local list = cbData.list
		if cbData.listFunc then list = cbData.listFunc() end
		for key, value in pairs(list or {}) do
			container:Add(key, value)
		end
		return container:GetData()
	end

	local setting = Settings.RegisterProxySetting(cat, "EQOL_" .. cbData.var, cbData.type or Settings.VarType.String, cbData.text, cbData.default, cbData.get, cbData.set)

	local dropdown = Settings.CreateDropdown(cat, setting, options, cbData.desc)
	if cbData.parent then dropdown:SetParentInitializer(cbData.element, cbData.parentCheck) end
end

function addon.functions.SettingsCreateButton(layout, text, func, tooltip, searchtags)
	local btn = CreateSettingsButtonInitializer("", text, func, tooltip, searchtags)
	layout:AddInitializer(btn)
	addon.SettingsLayout.elements[text] = { element = btn }
end

local cat, layout = Settings.RegisterVerticalLayoutCategory(addonName)
cat:SetShouldSortAlphabetically(true)

Settings.RegisterAddOnCategory(cat)
addon.SettingsLayout.rootCategory = cat
addon.SettingsLayout.rootLayout = layout
