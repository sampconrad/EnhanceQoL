local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_LayoutTools")
local db = addon.db["eqolLayoutTools"]

local function buildSettings()
	local categoryLabel = L["Layout Tools"] or L["Move"] or "Layout Tools"
	local cLayout = addon.functions.SettingsCreateCategory(nil, categoryLabel, nil, "LayoutTools")
	addon.SettingsLayout.layoutToolsCategory = cLayout

	local sectionGeneral = addon.functions.SettingsCreateExpandableSection(cLayout, {
		name = L["Global Settings"] or "General",
		expanded = true,
	})

	local settings = addon.LayoutTools.variables.settings or {}
	for _, def in ipairs(settings) do
		local kind = def.type or "checkbox"
		local data = {}
		for key, value in pairs(def) do
			if key ~= "type" and key ~= "dbKey" and key ~= "init" then data[key] = value end
		end
		data.parentSection = data.parentSection or sectionGeneral
		if kind == "checkbox" then
			addon.functions.SettingsCreateCheckbox(cLayout, data)
		elseif kind == "dropdown" then
			addon.functions.SettingsCreateDropdown(cLayout, data)
		elseif kind == "slider" then
			addon.functions.SettingsCreateSlider(cLayout, data)
		end
	end

	for _, group in ipairs(addon.LayoutTools.functions.GetGroups()) do
		local section = addon.functions.SettingsCreateExpandableSection(cLayout, {
			name = group.label or group.id,
			expanded = group.expanded,
		})

		for _, entry in ipairs(addon.LayoutTools.functions.GetEntriesForGroup(group.id)) do
			local e = entry
			addon.functions.SettingsCreateCheckbox(cLayout, {
				var = e.settingKey or e.id,
				text = e.label or e.id,
				default = e.defaultEnabled ~= false,
				get = function() return addon.LayoutTools.functions.IsFrameEnabled(e) end,
				set = function(value)
					addon.LayoutTools.functions.SetFrameEnabled(e, value)
					addon.LayoutTools.functions.RefreshEntry(e)
				end,
				parentSection = section,
				parentCheck = function() return db.enabled end,
			})
		end
	end
end

buildSettings()

function addon.LayoutTools.functions.treeCallback(container, group)
	if addon.SettingsLayout.layoutToolsCategory then Settings.OpenToCategory(addon.SettingsLayout.layoutToolsCategory:GetID()) end
end
