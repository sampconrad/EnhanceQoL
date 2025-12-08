-- SettingsUI.lua (LibEQOLSettingsMode-basiert)
local addonName, addon = ...
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local SettingsLib = LibStub("LibEQOLSettingsMode-1.0")

-- Optional: Prefix für Settings-Variablen
local prefix = "EQOL_"

-- Optional: New-Badge-Resolver (Kategorie-ID oder Variablenname)
-- Ersetze addon.variables.NewVersionTableEQOL nach Bedarf
SettingsLib:SetNewTagResolverForPrefix(prefix, function(idOrVar) return addon.variables and addon.variables.NewVersionTableEQOL and addon.variables.NewVersionTableEQOL[idOrVar] end)

addon.SettingsLayout = addon.SettingsLayout or {}
addon.functions = addon.functions or {}

---------------------------------------------------------
-- Kategorien
---------------------------------------------------------
function addon.functions.SettingsCreateCategory(parent, treeName, sort, newTagID)
	if nil == parent then parent = addon.SettingsLayout.rootCategory end
	local cat, layout = SettingsLib:CreateCategory(parent, treeName, sort, newTagID, prefix)
	addon.SettingsLayout.knownCategoryID = addon.SettingsLayout.knownCategoryID or {}
	addon.SettingsLayout.knownCategoryID[cat:GetID()] = true
	return cat, layout
end

function addon.functions.SettingsCreateKeybind(cat, bindingIndex) SettingsLib:CreateKeybind(cat, { bindingIndex = bindingIndex }) end

---------------------------------------------------------
-- Checkbox
---------------------------------------------------------
function addon.functions.SettingsCreateCheckbox(cat, cbData)
	local element, setting = SettingsLib:CreateCheckbox(cat, {
		key = cbData.var,
		name = cbData.text,
		default = cbData.default or false,
		get = cbData.get or function() return addon.db[cbData.var] end,
		set = cbData.func or cbData.set or function(_, v) addon.db[cbData.var] = v end,
		desc = cbData.desc,
		searchtags = cbData.searchtags,
		parent = cbData.element,
		parentCheck = cbData.parentCheck,
		parentSection = cbData.parentSection,
		prefix = prefix,
	})
	addon.SettingsLayout.elements = addon.SettingsLayout.elements or {}
	addon.SettingsLayout.elements[cbData.var] = { setting = setting, element = element }

	if cbData.notify then SettingsLib:AttachNotify(setting, cbData.notify) end
	-- Children (rekursiv)
	if cbData.children then
		for _, v in pairs(cbData.children) do
			v.element = v.element or element
			v.parentCheck = v.parentCheck or cbData.parentCheck
			local sType = v.sType or v.type
			if sType == "dropdown" then
				addon.functions.SettingsCreateDropdown(cat, v)
			elseif sType == "checkbox" then
				addon.functions.SettingsCreateCheckbox(cat, v)
			elseif sType == "multidropdown" then
				addon.functions.SettingsCreateMultiDropdown(cat, v)
			elseif sType == "slider" then
				addon.functions.SettingsCreateSlider(cat, v)
			elseif sType == "hint" then
				addon.functions.SettingsCreateText(cat, v.text, v.parentSection)
			elseif sType == "colorpicker" then
				addon.functions.SettingsCreateColorPicker(cat, v)
			elseif sType == "button" then
				addon.functions.SettingsCreateButton(cat, v)
			elseif sType == "sounddropdown" then
				addon.functions.SettingsCreateSoundDropdown(cat, v)
			end
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

---------------------------------------------------------
-- Slider
---------------------------------------------------------
function addon.functions.SettingsCreateSlider(cat, cbData)
	local element, setting = SettingsLib:CreateSlider(cat, {
		key = cbData.var,
		name = cbData.text,
		default = cbData.default,
		min = cbData.min,
		max = cbData.max,
		step = cbData.step,
		get = cbData.get or function() return addon.db[cbData.var] or cbData.default end,
		set = cbData.set or function(_, v) addon.db[cbData.var] = v end,
		desc = cbData.desc,
		formatter = function(value)
			local s = string.format("%.2f", value)
			s = s:gsub("(%..-)0+$", "%1")
			s = s:gsub("%.$", "")
			return s
		end,
		parent = cbData.element,
		parentCheck = cbData.parentCheck,
		searchtags = cbData.searchtags,
		parentSection = cbData.parentSection,
		prefix = prefix,
	})
	addon.SettingsLayout.elements = addon.SettingsLayout.elements or {}
	addon.SettingsLayout.elements[cbData.var] = { setting = setting, element = element }
	return addon.SettingsLayout.elements[cbData.var]
end

---------------------------------------------------------
-- Dropdown
---------------------------------------------------------
function addon.functions.SettingsCreateDropdown(cat, cbData)
	local element, setting = SettingsLib:CreateDropdown(cat, {
		key = cbData.var,
		name = cbData.text,
		default = cbData.default,
		values = cbData.list or cbData.values,
		optionfunc = cbData.listFunc or cbData.optionfunc,
		order = cbData.order,
		get = cbData.get or function() return addon.db[cbData.var] end,
		set = cbData.set or function(_, v) addon.db[cbData.var] = v end,
		desc = cbData.desc,
		searchtags = cbData.searchtags,
		parent = cbData.element,
		parentCheck = cbData.parentCheck,
		parentSection = cbData.parentSection,
		prefix = prefix,
	})
	addon.SettingsLayout.elements = addon.SettingsLayout.elements or {}
	addon.SettingsLayout.elements[cbData.var] = { setting = setting, element = element }
	if cbData.notify then SettingsLib:AttachNotify(setting, cbData.notify) end
	return addon.SettingsLayout.elements[cbData.var]
end

---------------------------------------------------------
-- MultiDropdown
---------------------------------------------------------
function addon.functions.SettingsCreateMultiDropdown(cat, cbData)
	addon.db = addon.db or {}
	addon.db[cbData.var] = addon.db[cbData.var] or {}

	local function getSelection()
		local container = addon.db[cbData.var]
		if cbData.subvar then
			container = container[cbData.subvar]
			if type(container) ~= "table" then container = {} end
		end
		return container
	end

	local function setSelection(map)
		if cbData.subvar then
			addon.db[cbData.var] = addon.db[cbData.var] or {}
			addon.db[cbData.var][cbData.subvar] = map
		else
			addon.db[cbData.var] = map
		end
		if cbData.callback then cbData.callback(map) end
	end

	local initializer = SettingsLib:CreateMultiDropdown(cat, {
		key = cbData.var,
		name = cbData.text,
		values = cbData.options or cbData.list,
		optionfunc = cbData.optionfunc or cbData.listFunc,
		order = cbData.order,
		isSelected = cbData.isSelectedFunc,
		setSelected = cbData.setSelectedFunc,
		getSelection = cbData.getSelection or cbData.get or getSelection,
		setSelection = cbData.setSelection or cbData.set or setSelection,
		summary = cbData.summary,
		searchtags = cbData.searchtags,
		parent = cbData.element,
		parentCheck = cbData.parentCheck,
		notify = cbData.notify,
		parentSection = cbData.parentSection,
		isEnabled = cbData.isEnabled,
		prefix = prefix,
		hideSummary = true,
	})

	addon.SettingsLayout.elements = addon.SettingsLayout.elements or {}
	addon.SettingsLayout.elements[cbData.var] = { initializer = initializer }
	return initializer
end

---------------------------------------------------------
-- Sound Dropdown
---------------------------------------------------------
function addon.functions.SettingsCreateSoundDropdown(cat, cbData)
	local initializer, setting = SettingsLib:CreateSoundDropdown(cat, {
		key = cbData.var,
		name = cbData.text,
		values = cbData.options or cbData.list,
		optionfunc = cbData.optionfunc or cbData.listFunc,
		order = cbData.order,
		default = cbData.default,
		get = cbData.get or function() return addon.db[cbData.var] end,
		set = cbData.set or function(_, v) addon.db[cbData.var] = v end,
		callback = cbData.callback,
		soundResolver = cbData.soundResolver,
		previewSoundFunc = cbData.previewSoundFunc,
		playbackChannel = cbData.playbackChannel,
		getPlaybackChannel = cbData.getPlaybackChannel,
		placeholderText = cbData.placeholderText,
		previewTooltip = cbData.previewTooltip,
		menuHeight = cbData.menuHeight,
		frameWidth = cbData.frameWidth,
		frameHeight = cbData.frameHeight,
		parent = cbData.element,
		parentCheck = cbData.parentCheck,
		searchtags = cbData.searchtags,
		parentSection = cbData.parentSection,
		prefix = prefix,
	})
	addon.SettingsLayout.elements = addon.SettingsLayout.elements or {}
	addon.SettingsLayout.elements[cbData.var] = { initializer = initializer, setting = setting }
	if cbData.notify then SettingsLib:AttachNotify(setting, cbData.notify) end

	return initializer
end

---------------------------------------------------------
-- Color Overrides Panel
---------------------------------------------------------
function addon.functions.SettingsCreateColorOverrides(cat, cbData)
	local initializer = SettingsLib:CreateColorOverrides(cat, {
		key = cbData.var or cbData.key,
		headerText = cbData.text or cbData.name,
		entries = cbData.entries,
		getColor = cbData.getColor,
		setColor = cbData.setColor,
		getDefaultColor = cbData.getDefaultColor,
		colorizeLabel = cbData.colorizeLabel or cbData.colorizeText,
		rowHeight = cbData.rowHeight,
		basePadding = cbData.basePadding,
		minHeight = cbData.minHeight,
		height = cbData.height,
		spacing = cbData.spacing,
		parent = cbData.element,
		parentCheck = cbData.parentCheck,
		searchtags = cbData.searchtags,
		notify = cbData.notify,
		parentSection = cbData.parentSection,
		prefix = prefix,
	})
	addon.SettingsLayout.elements = addon.SettingsLayout.elements or {}
	addon.SettingsLayout.elements[cbData.var or cbData.key or "ColorOverrides"] = { initializer = initializer }
	return initializer
end

---------------------------------------------------------
-- Text / Header / Button / Notify
---------------------------------------------------------
function addon.functions.SettingsCreateHeadline(cat, text, extra) return SettingsLib:CreateHeader(cat, text, extra) end

function addon.functions.SettingsCreateText(cat, text, extra) return SettingsLib:CreateText(cat, text, extra) end

function addon.functions.SettingsCreateButton(cat, cbData)
	local btn = SettingsLib:CreateButton(cat, {
		text = cbData.text,
		func = cbData.func,
		desc = cbData.desc,
		searchtags = cbData.searchtags,
		parent = cbData.element,
		parentCheck = cbData.parentCheck,
		parentSection = cbData.parentSection,
		prefix = prefix,
	})
	addon.SettingsLayout.elements = addon.SettingsLayout.elements or {}
	addon.SettingsLayout.elements[cbData.var or cbData.text] = { element = btn }
	return btn
end

function addon.functions.SettingsCreateColorPicker(cat, cbData)
	local initializer = SettingsLib:CreateColorOverrides(cat, {
		key = cbData.var, -- eindeutiger Key
		headerText = cbData.text, -- Überschrift (optional)
		entries = { { key = cbData.var, label = cbData.text, tooltip = cbData.tooltip } },
		getColor = function(key)
			local db = addon.db[cbData.var]
			if cbData.subvar and db then db = db[cbData.subvar] end
			local col = db or { r = 0, g = 0, b = 0 }
			return col.r or 0, col.g or 0, col.b or 0
		end,
		setColor = function(key, r, g, b)
			addon.db[cbData.var] = addon.db[cbData.var] or {}
			if cbData.subvar then
				addon.db[cbData.var][cbData.subvar] = { r = r, g = g, b = b }
			else
				addon.db[cbData.var] = { r = r, g = g, b = b }
			end
			if cbData.callback then cbData.callback(r, g, b, 1) end
		end,
		getDefaultColor = function() return 1, 1, 1 end,
		parent = cbData.element,
		parentCheck = cbData.parentCheck,
		searchtags = cbData.searchtags,
		notify = cbData.notify,
		parentSection = cbData.parentSection,
		prefix = prefix,
		colorizeLabel = cbData.colorizeLabel,
	})

	addon.SettingsLayout = addon.SettingsLayout or {}
	addon.SettingsLayout.elements = addon.SettingsLayout.elements or {}
	addon.SettingsLayout.elements[cbData.var] = { initializer = initializer }
	return initializer
end

function addon.functions.SettingsCreateExpandableSection(cat, cbData)
	local section = SettingsLib:CreateExpandableSection(cat, {
		name = cbData.name,
		expanded = true,
		prefix = prefix,
	})
	if cbData.var then
		addon.SettingsLayout = addon.SettingsLayout or {}
		addon.SettingsLayout.elements = addon.SettingsLayout.elements or {}
		addon.SettingsLayout.elements[cbData.var] = { initializer = section }
	end
	return section
end

local cat, layout = SettingsLib:CreateRootCategory(addonName, true)

-- Legacy settings hint (old UI likely broken in Midnight)
addon.functions.SettingsCreateText(cat, "|cff99e599" .. L["SettingsLegacyNotice"] .. "|r")

addon.SettingsLayout.rootCategory = cat
addon.SettingsLayout.rootLayout = layout
