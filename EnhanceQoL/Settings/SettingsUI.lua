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
hooksecurefunc(SettingsSliderControlMixin, "Init", function(self)
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
			elseif v.sType == "colorpicker" then
				addon.functions.SettingsCreateColorPicker(cat, v)
			elseif v.sType == "button" then
				addon.functions.SettingsCreateButton(cat, v)
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
	if cbData.notify then addon.functions.SettingsCreateNotify(setting, cbData.notify) end
end

function addon.functions.SettingsCreateButton(cat, cbData)
	cbData.searchtags = cbData.searchtags or false
	local btn = CreateSettingsButtonInitializer("", cbData.text, cbData.func, cbData.desc, cbData.searchtags)
	SettingsPanel:GetLayout(cat):AddInitializer(btn)
	addon.SettingsLayout.elements[cbData.var] = { element = btn }
	if cbData.parent then btn:SetParentInitializer(cbData.element, cbData.parentCheck) end
end

local function SortMixedKeys(keys)
	table.sort(keys, function(a, b)
		local ta, tb = type(a), type(b)
		if ta == tb then
			if ta == "number" then return a < b end
			if ta == "string" then return a < b end
			return tostring(a) < tostring(b)
		end
		if ta == "number" then return true end
		if tb == "number" then return false end
		return tostring(a) < tostring(b)
	end)
	return keys
end

function addon.functions.SettingsCreateMultiDropdown(cat, cbData)
	addon.db = addon.db or {}
	addon.db[cbData.var] = addon.db[cbData.var] or {}

	-- Setting nur als „Träger“ im Settings-System (kannst du auch weglassen)
	local setting = Settings.RegisterProxySetting(cat, "EQOL_" .. cbData.var, Settings.VarType.String, cbData.text, "", function()
		-- Summary-String (für Settings-System, wenn du willst)
		local t = addon.db[cbData.var]
		if type(t) ~= "table" then t = {} end
		local keys = {}
		for k, v in pairs(t) do
			if v then table.insert(keys, k) end
		end
		SortMixedKeys(keys)
		return table.concat(keys, ",")
	end, function(_, _, value) end)

	local initializer = Settings.CreateElementInitializer("EQOL_MultiDropdownTemplate", {
		var = cbData.var,
		subvar = cbData.subvar,
		label = cbData.text,
		options = cbData.options,
		optionfunc = cbData.optionfunc,
		isSelectedFunc = cbData.isSelectedFunc,
		setSelectedFunc = cbData.setSelectedFunc,
		db = addon.db,
		callback = cbData.callback,
	})
	initializer:SetSetting(setting)
	if cbData.parent then initializer:SetParentInitializer(cbData.element, cbData.parentCheck) end

	local layout = SettingsPanel:GetLayout(cat)
	layout:AddInitializer(initializer)

	addon.SettingsLayout = addon.SettingsLayout or {}
	addon.SettingsLayout.elements = addon.SettingsLayout.elements or {}
	addon.SettingsLayout.elements[cbData.var] = { setting = setting, initializer = initializer }

	return setting, initializer
end

function addon.functions.SettingsCreateColorPicker(cat, cbData)
	local colorPicker = Settings.CreateElementInitializer("EQOL_ColorOverridesPanelNoHead", {
		categoryID = cat:GetID(),
		entries = {
			{ key = cbData.var, label = cbData.text, tooltip = cbData.tooltip },
		},
		getColor = function()
			local db = addon.db[cbData.var]
			if cbData.subvar then db = addon.db[cbData.var][cbData.subvar] end
			local col = db or { r = 0, g = 0, b = 0 }
			return col.r or 0, col.g or 0, col.b or 0
		end,
		setColor = function(_, r, g, b)
			if cbData.subvar then
				addon.db[cbData.var][cbData.subvar] = { r = r, g = g, b = b }
			else
				addon.db[cbData.var] = { r = r, g = g, b = b }
			end
			if cbData.callback then cbData.callback(r, g, b, 1) end
		end,
		getDefaultColor = function() return 1, 1, 1 end,
		parentCheck = cbData.parentCheck,
	})
	Settings.RegisterInitializer(cat, colorPicker)
	if cbData.parent then colorPicker:SetParentInitializer(cbData.element, cbData.parentCheck) end

	addon.SettingsLayout = addon.SettingsLayout or {}
	addon.SettingsLayout.elements = addon.SettingsLayout.elements or {}
	addon.SettingsLayout.elements[cbData.var] = { element = colorPicker }
end

local cat, layout = Settings.RegisterVerticalLayoutCategory(addonName)
cat:SetShouldSortAlphabetically(true)

Settings.RegisterAddOnCategory(cat)
addon.SettingsLayout.rootCategory = cat
addon.SettingsLayout.rootLayout = layout
