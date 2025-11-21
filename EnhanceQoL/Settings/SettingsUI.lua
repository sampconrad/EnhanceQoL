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

	if cbData.notify then addon.functions.SettingsCreateNotify(setting, cbData.notify) end
	if cbData.children then
		for _, v in pairs(cbData.children) do
			v.element = v.element or element
			if v.sType == "dropdown" then
				addon.functions.SettingsCreateDropdown(cat, v)
			elseif v.sType == "checkbox" then
				addon.functions.SettingsCreateCheckbox(cat, v)
			elseif v.sType == "slider" then
				addon.functions.SettingsCreateSlider(cat, v)
			elseif v.sType == "hint" then
				addon.functions.SettingsCreateText(cat, v.text)
			end
		end
	end
	return addon.SettingsLayout.elements[cbData.var]
end

function addon.functions.SettingsCreateNotify(element, data)
	element:SetValueChangedCallback(function(setting, value) Settings.NotifyUpdate("EQOL_" .. data) end)
end

function addon.functions.SettingsCreateCheckboxes(cat, data)
	local rData = {}
	for _, cbData in ipairs(data) do
		rData[cbData.var] = addon.functions.SettingsCreateCheckbox(cat, cbData)
	end
	return rData
end

function addon.functions.SettingsCreateSlider(cat, cbData)
	local setting = Settings.RegisterProxySetting(
		cat,
		"EQOL_" .. cbData.var,
		Settings.VarType.Number,
		cbData.text,
		cbData.default,
		cbData.get or function() return addon.db[cbData.var] or cbData.default end,
		cbData.set
	)
	local options = Settings.CreateSliderOptions(cbData.min, cbData.max, cbData.step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		local s = string.format("%.2f", value)
		s = s:gsub("(%..-)0+$", "%1")
		s = s:gsub("%.$", "")
		return s
	end)
	local element = Settings.CreateSlider(cat, setting, options, cbData.desc)
	if cbData.parent then element:SetParentInitializer(cbData.element, cbData.parentCheck) end
	addon.SettingsLayout.elements[cbData.var] = { setting = setting, element = element }
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
		if type(list) == "table" then
			local order = rawget(list, "_order")
			if type(order) == "table" and #order > 0 then
				for _, key in ipairs(order) do
					container:Add(key, list[key])
				end
			else
				for key, value in pairs(list) do
					if key ~= "_order" then container:Add(key, value) end
				end
			end
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
