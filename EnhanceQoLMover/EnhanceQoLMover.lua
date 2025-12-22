local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Mover")
local db = addon.Mover.db

local function buildSettings()
	local categoryLabel = L["Move"] or "Mover"
	local cLayout = addon.functions.SettingsCreateCategory(nil, categoryLabel, nil, "Mover")
	addon.SettingsLayout.moverCategory = cLayout

	local sectionGeneral = addon.functions.SettingsCreateExpandableSection(cLayout, {
		name = L["Global Settings"] or "General",
		expanded = true,
	})

	local rootSettingKey = "moverEnabled"
	local rootElement

	local settings = addon.Mover.variables.settings or {}
	for _, def in ipairs(settings) do
		local kind = def.type or "checkbox"
		local data = {}
		for key, value in pairs(def) do
			if key ~= "type" and key ~= "dbKey" and key ~= "init" then data[key] = value end
		end
		data.parentSection = data.parentSection or sectionGeneral
		if def.var ~= rootSettingKey and rootElement then
			local originalParentCheck = data.parentCheck
			data.element = rootElement
			data.parent = true
			data.parentCheck = function() return db.enabled and (originalParentCheck == nil or originalParentCheck()) end
		end
		if kind == "checkbox" then
			local created = addon.functions.SettingsCreateCheckbox(cLayout, data)
			if def.var == rootSettingKey then rootElement = created and created.element or rootElement end
		elseif kind == "dropdown" then
			addon.functions.SettingsCreateDropdown(cLayout, data)
		elseif kind == "slider" then
			addon.functions.SettingsCreateSlider(cLayout, data)
		end
	end

	for _, group in ipairs(addon.Mover.functions.GetGroups()) do
		local enableElement = rootElement
		local section = addon.functions.SettingsCreateExpandableSection(cLayout, {
			name = group.label or group.id,
			expanded = group.expanded,
		})

		for _, entry in ipairs(addon.Mover.functions.GetEntriesForGroup(group.id)) do
			local e = entry
			addon.functions.SettingsCreateCheckbox(cLayout, {
				var = e.settingKey or e.id,
				text = e.label or e.id,
				default = e.defaultEnabled ~= false,
				get = function() return addon.Mover.functions.IsFrameEnabled(e) end,
				set = function(value)
					addon.Mover.functions.SetFrameEnabled(e, value)
					addon.Mover.functions.RefreshEntry(e)
				end,
				element = enableElement,
				parent = true,
				parentSection = section,
				parentCheck = function() return db.enabled end,
			})
		end
	end
end

buildSettings()

function addon.Mover.functions.treeCallback(container, group)
	if addon.SettingsLayout.moverCategory then Settings.OpenToCategory(addon.SettingsLayout.moverCategory:GetID()) end
end
