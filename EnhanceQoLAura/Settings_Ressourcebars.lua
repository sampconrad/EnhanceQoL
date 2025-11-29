local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")
local EditMode = addon.EditMode

local ResourceBars = addon.Aura and addon.Aura.ResourceBars
if not ResourceBars then return end

local specSettingVars = {}

local function notifyResourceBarSettings()
	if not Settings or not Settings.NotifyUpdate then return end
	Settings.NotifyUpdate("EQOL_enableResourceFrame")
	Settings.NotifyUpdate("EQOL_resourceBarsHideOutOfCombat")
	Settings.NotifyUpdate("EQOL_resourceBarsHideMounted")
	Settings.NotifyUpdate("EQOL_resourceBarsHideVehicle")
	for var in pairs(specSettingVars) do
		Settings.NotifyUpdate("EQOL_" .. var)
	end
end
local function ensureSpecCfg(specIndex)
	local class = addon.variables.unitClass
	if not class or not specIndex then return end
	addon.db.personalResourceBarSettings = addon.db.personalResourceBarSettings or {}
	addon.db.personalResourceBarSettings[class] = addon.db.personalResourceBarSettings[class] or {}
	addon.db.personalResourceBarSettings[class][specIndex] = addon.db.personalResourceBarSettings[class][specIndex] or {}
	return addon.db.personalResourceBarSettings[class][specIndex]
end

local function setBarEnabled(specIndex, barType, enabled)
	local specCfg = ensureSpecCfg(specIndex)
	if not specCfg then return end
	specCfg[barType] = specCfg[barType] or {}
	specCfg[barType].enabled = enabled and true or false
	if barType == "HEALTH" then
		if enabled then
			ResourceBars.SetHealthBarSize(specCfg[barType].width or ResourceBars.DEFAULT_HEALTH_WIDTH or 200, specCfg[barType].height or ResourceBars.DEFAULT_HEALTH_HEIGHT or 20)
		else
			ResourceBars.DetachAnchorsFrom("HEALTH", specIndex)
		end
	else
		if enabled then
			ResourceBars.SetPowerBarSize(specCfg[barType].width or ResourceBars.DEFAULT_POWER_WIDTH or 200, specCfg[barType].height or ResourceBars.DEFAULT_POWER_HEIGHT or 20, barType)
		else
			ResourceBars.DetachAnchorsFrom(barType, specIndex)
		end
	end
	if ResourceBars.QueueRefresh then ResourceBars.QueueRefresh(specIndex) end
	if ResourceBars.MaybeRefreshActive then ResourceBars.MaybeRefreshActive(specIndex) end
	if EditMode and EditMode:IsInEditMode() then
		if ResourceBars.Refresh then ResourceBars.Refresh() end
		if ResourceBars.ReanchorAll then ResourceBars.ReanchorAll() end
	end
end

local function registerEditModeBars()
	if not EditMode or not EditMode.RegisterFrame then return end
	local registered = 0

	local function registerBar(idSuffix, frameName, barType, widthDefault, heightDefault)
		local frame = _G[frameName]
		if not frame then return end
		local cfg = ResourceBars and ResourceBars.getBarSettings and ResourceBars.getBarSettings(barType) or ResourceBars and ResourceBars.GetBarSettings and ResourceBars.GetBarSettings(barType)
		local anchor = ResourceBars and ResourceBars.getAnchor and ResourceBars.getAnchor(barType, addon.variables.unitSpec)
		local function curSpecCfg()
			local spec = addon.variables.unitSpec
			local specCfg = ensureSpecCfg(spec)
			if not specCfg then return nil end
			specCfg[barType] = specCfg[barType] or {}
			return specCfg[barType]
		end
		local function queueRefresh()
			if ResourceBars.QueueRefresh then ResourceBars.QueueRefresh(addon.variables.unitSpec) end
			if ResourceBars.MaybeRefreshActive then ResourceBars.MaybeRefreshActive(addon.variables.unitSpec) end
			if EditMode and EditMode:IsInEditMode() and addon.variables.unitSpec then
				if ResourceBars.Refresh then ResourceBars.Refresh() end
				if ResourceBars.ReanchorAll then ResourceBars.ReanchorAll() end
			end
		end
		local settingType = EditMode.lib and EditMode.lib.SettingType
		local settingsList
		if settingType then
			settingsList = {
				{
					name = HUD_EDIT_MODE_SETTING_CHAT_FRAME_WIDTH,
					kind = settingType.Slider,
					field = "width",
					minValue = 50,
					maxValue = 600,
					valueStep = 1,
					default = cfg and cfg.width or widthDefault or 200,
					get = function()
						local c = curSpecCfg()
						return c and c.width or widthDefault or 200
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.width = value
						queueRefresh()
					end,
				},
				{
					name = HUD_EDIT_MODE_SETTING_CHAT_FRAME_HEIGHT,
					kind = settingType.Slider,
					field = "height",
					minValue = 6,
					maxValue = 80,
					valueStep = 1,
					default = cfg and cfg.height or heightDefault or 20,
					get = function()
						local c = curSpecCfg()
						return c and c.height or heightDefault or 20
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.height = value
						queueRefresh()
					end,
				},
			}

			if barType ~= "RUNES" then
				local function defaultStyle()
					if barType == "HEALTH" then return "PERCENT" end
					if barType == "MANA" then return "PERCENT" end
					return "CURMAX"
				end
				settingsList[#settingsList + 1] = {
					name = L["Text"] or STATUS_TEXT,
					kind = settingType.Dropdown,
					field = "textStyle",
					values = {
						{ value = "PERCENT", label = STATUS_TEXT_PERCENT },
						{ value = "CURMAX", label = L["Current/Max"] },
						{ value = "CURRENT", label = L["Current"] },
						{ value = "NONE", label = NONE },
					},
					get = function()
						local c = curSpecCfg()
						return (c and c.textStyle) or defaultStyle()
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.textStyle = value
						queueRefresh()
					end,
					default = cfg and cfg.textStyle or defaultStyle(),
				}

				settingsList[#settingsList + 1] = {
					name = HUD_EDIT_MODE_SETTING_OBJECTIVE_TRACKER_TEXT_SIZE,
					kind = settingType.Slider,
					field = "fontSize",
					minValue = 6,
					maxValue = 64,
					valueStep = 1,
					get = function()
						local c = curSpecCfg()
						return c and c.fontSize or 16
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.fontSize = value
						queueRefresh()
					end,
					default = cfg and cfg.fontSize or 16,
				}

				settingsList[#settingsList + 1] = {
					name = L["Text Offset X"] or "Text Offset X",
					kind = settingType.Slider,
					field = "textOffsetX",
					minValue = -100,
					maxValue = 100,
					valueStep = 1,
					get = function()
						local c = curSpecCfg()
						local off = c and c.textOffset
						return off and off.x or 0
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.textOffset = c.textOffset or { x = 0, y = 0 }
						c.textOffset.x = value or 0
						queueRefresh()
					end,
					default = 0,
				}

				settingsList[#settingsList + 1] = {
					name = L["Text Offset Y"] or "Text Offset Y",
					kind = settingType.Slider,
					field = "textOffsetY",
					minValue = -100,
					maxValue = 100,
					valueStep = 1,
					get = function()
						local c = curSpecCfg()
						local off = c and c.textOffset
						return off and off.y or 0
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.textOffset = c.textOffset or { x = 0, y = 0 }
						c.textOffset.y = value or 0
						queueRefresh()
					end,
					default = 0,
				}
			end
		end

		EditMode:RegisterFrame("resourceBar_" .. idSuffix, {
			frame = frame,
			title = L["Resource Bars"],
			layoutDefaults = {
				point = anchor and anchor.point or "CENTER",
				relativePoint = anchor and anchor.relativePoint or "CENTER",
				x = anchor and anchor.x or 0,
				y = anchor and anchor.y or 0,
				width = cfg and cfg.width or widthDefault or frame:GetWidth() or 200,
				height = cfg and cfg.height or heightDefault or frame:GetHeight() or 20,
			},
			onApply = function(_, _, data)
				local spec = addon.variables.unitSpec
				local specCfg = ensureSpecCfg(spec)
				if not specCfg then return end
				specCfg[barType] = specCfg[barType] or {}
				local bcfg = specCfg[barType]
				bcfg.anchor = bcfg.anchor or {}
				if data.point then
					bcfg.anchor.point = data.point
					bcfg.anchor.relativePoint = data.relativePoint or data.point
					bcfg.anchor.x = data.x or 0
					bcfg.anchor.y = data.y or 0
					bcfg.anchor.relativeFrame = "UIParent"
				end
				bcfg.width = data.width or bcfg.width
				bcfg.height = data.height or bcfg.height
				if barType == "HEALTH" then
					ResourceBars.SetHealthBarSize(bcfg.width, bcfg.height)
				else
					ResourceBars.SetPowerBarSize(bcfg.width, bcfg.height, barType)
				end
				if ResourceBars.ReanchorAll then ResourceBars.ReanchorAll() end
					if ResourceBars.Refresh then ResourceBars.Refresh() end
				end,
				settings = settingsList,
			showOutsideEditMode = true,
		})
		registered = registered + 1
	end

	registerBar("HEALTH", "EQOLHealthBar", "HEALTH", ResourceBars.DEFAULT_HEALTH_WIDTH, ResourceBars.DEFAULT_HEALTH_HEIGHT)
	for _, pType in ipairs(ResourceBars.classPowerTypes or {}) do
		local frameName = "EQOL" .. pType .. "Bar"
		registerBar(pType, frameName, pType, ResourceBars.DEFAULT_POWER_WIDTH, ResourceBars.DEFAULT_POWER_HEIGHT)
	end

	if registered > 0 then ResourceBars._editModeRegistered = true end
end

ResourceBars.RegisterEditModeFrames = registerEditModeBars

local function buildSpecToggles(specIndex, specName, available)
	local specCfg = ensureSpecCfg(specIndex)
	if not specCfg then return nil end

	local options = {}
	local added = {}

	-- Main resource from spec definition (e.g., LUNAR_POWER for Balance)
	local mainType = available.MAIN
	if mainType then
		specCfg[mainType] = specCfg[mainType] or {}
		local cfg = specCfg[mainType]
		options[#options + 1] = {
			value = mainType,
			text = _G["POWER_TYPE_" .. mainType] or _G[mainType] or mainType,
			enabled = cfg.enabled == true,
		}
		added[mainType] = true
	end

	for _, pType in ipairs(ResourceBars.classPowerTypes or {}) do
		if available[pType] and not added[pType] then
			specCfg[pType] = specCfg[pType] or {}
			local cfg = specCfg[pType]
			local label = _G["POWER_TYPE_" .. pType] or _G[pType] or pType
			options[#options + 1] = {
				value = pType,
				text = label,
				enabled = cfg.enabled == true,
			}
			added[pType] = true
		end
	end

	-- Add health entry first
	local hCfg = specCfg.HEALTH or {}
	table.insert(options, 1, { value = "HEALTH", text = HEALTH, enabled = hCfg.enabled == true })

	if #options == 0 then return nil end

	local varKey = ("rb_spec_%s"):format(specIndex)
	specSettingVars[varKey] = true
	local class = addon.variables.unitClass

	return {
		sType = "multidropdown",
		var = varKey,
		text = specName,
		options = options,
		isSelectedFunc = function(key)
			local class = addon.variables.unitClass
			if not class or not specIndex then return false end
			return addon.db.personalResourceBarSettings
					and addon.db.personalResourceBarSettings[class]
					and addon.db.personalResourceBarSettings[class][specIndex]
					and addon.db.personalResourceBarSettings[class][specIndex]
					and addon.db.personalResourceBarSettings[class][specIndex][key]
					and addon.db.personalResourceBarSettings[class][specIndex][key].enabled
				or false
		end,
		setSelectedFunc = function(key, shouldSelect)
			addon.db.personalResourceBarSettings[class][specIndex][key] = addon.db.personalResourceBarSettings[class][specIndex][key] or {}
			addon.db.personalResourceBarSettings[class][specIndex][key].enabled = shouldSelect and true or false
			setBarEnabled(specIndex, key, shouldSelect)
		end,
		parent = true,
		parentCheck = function() return addon.db["enableResourceFrame"] == true end,
	}
end

local function buildSettings()
	local cat = addon.functions.SettingsCreateCategory(nil, L["Resource Bars"], nil, "ResourceBars")
	if not cat then return end

	local data = {
		{
			var = "enableResourceFrame",
			text = L["Resource Bars"],
			desc = L["Resource Bars"],
			get = function() return addon.db["enableResourceFrame"] end,
			func = function(val)
				addon.db["enableResourceFrame"] = val and true or false
				if val and ResourceBars.EnableResourceBars then
					ResourceBars.EnableResourceBars()
				elseif ResourceBars.DisableResourceBars then
					ResourceBars.DisableResourceBars()
				end
			end,
			default = false,
			children = {
				{
					var = "resourceBarsHideOutOfCombat",
					text = L["Hide out of combat"],
					get = function() return addon.db["resourceBarsHideOutOfCombat"] end,
					func = function(val)
						addon.db["resourceBarsHideOutOfCombat"] = val and true or false
						if ResourceBars.ApplyVisibilityPreference then ResourceBars.ApplyVisibilityPreference("settings") end
					end,
					parent = true,
					parentCheck = function() return addon.db["enableResourceFrame"] == true end,
					sType = "checkbox",
				},
				{
					var = "resourceBarsHideMounted",
					text = L["Hide when mounted"],
					get = function() return addon.db["resourceBarsHideMounted"] end,
					func = function(val)
						addon.db["resourceBarsHideMounted"] = val and true or false
						if ResourceBars.ApplyVisibilityPreference then ResourceBars.ApplyVisibilityPreference("settings") end
					end,
					parent = true,
					parentCheck = function() return addon.db["enableResourceFrame"] == true end,
					sType = "checkbox",
				},
				{
					var = "resourceBarsHideVehicle",
					text = L["Hide in vehicles"],
					get = function() return addon.db["resourceBarsHideVehicle"] end,
					func = function(val)
						addon.db["resourceBarsHideVehicle"] = val and true or false
						if ResourceBars.ApplyVisibilityPreference then ResourceBars.ApplyVisibilityPreference("settings") end
					end,
					parent = true,
					parentCheck = function() return addon.db["enableResourceFrame"] == true end,
					sType = "checkbox",
				},
			},
		},
	}

	local class = addon.variables.unitClassID
	if class and ResourceBars.powertypeClasses and ResourceBars.powertypeClasses[addon.variables.unitClass] then
		for specIndex = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(class) do
			local specID, specName = GetSpecializationInfoForClassID(class, specIndex)
			local available = ResourceBars.powertypeClasses[addon.variables.unitClass][specIndex] or {}
			if specID and specName then
				local entry = buildSpecToggles(specIndex, specName, available)
				if entry then table.insert(data[1].children, entry) end
			end
		end
	end

	addon.functions.SettingsCreateCheckboxes(cat, data)

	do -- Profile export/import
		local classKey = addon.variables.unitClass or "UNKNOWN"
		addon.db.resourceBarsProfileScope = addon.db.resourceBarsProfileScope or {}
		local function getScope()
			local cur = addon.db.resourceBarsProfileScope[classKey]
			if not cur then cur = "ALL" end
			return cur
		end
		local function setScope(val) addon.db.resourceBarsProfileScope[classKey] = val end

		local scopeList, scopeOrder = { ALL = L["All specs"] or "All specs" }, { "ALL" }
		if class and ResourceBars.powertypeClasses and ResourceBars.powertypeClasses[addon.variables.unitClass] then
			for specIndex = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(class) do
				local _, specName = GetSpecializationInfoForClassID(class, specIndex)
				if specName then
					scopeList[tostring(specIndex)] = specName
					scopeOrder[#scopeOrder + 1] = tostring(specIndex)
				end
			end
		end

		addon.functions.SettingsCreateHeadline(cat, L["Profiles"])
		addon.functions.SettingsCreateDropdown(cat, {
			var = "resourceBarsProfileScope",
			text = L["ProfileScope"] or (L["Apply to"] or "Apply to"),
			list = scopeList,
			get = getScope,
			set = setScope,
			default = "ALL",
		})

		addon.functions.SettingsCreateButton(cat, {
			var = "resourceBarsExport",
			text = L["Export"] or EXPORT,
			func = function()
				local scopeKey = getScope() or "ALL"
				local code, reason = ResourceBars.ExportProfile and ResourceBars.ExportProfile(scopeKey)
				if not code then
					local msg = ResourceBars.ExportErrorMessage and ResourceBars.ExportErrorMessage(reason) or (L["ExportProfileFailed"] or "Export failed.")
					print("|cff00ff98Enhance QoL|r: " .. tostring(msg))
					return
				end
				StaticPopupDialogs["EQOL_RESOURCEBAR_EXPORT_SETTINGS"] = StaticPopupDialogs["EQOL_RESOURCEBAR_EXPORT_SETTINGS"]
					or {
						text = L["ExportProfileTitle"] or "Export Resource Bars",
						button1 = CLOSE,
						hasEditBox = true,
						editBoxWidth = 320,
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						preferredIndex = 3,
					}
				StaticPopupDialogs["EQOL_RESOURCEBAR_EXPORT_SETTINGS"].OnShow = function(self)
					self:SetFrameStrata("TOOLTIP")
					local editBox = self.editBox or self:GetEditBox()
					editBox:SetText(code)
					editBox:HighlightText()
					editBox:SetFocus()
				end
				StaticPopup_Show("EQOL_RESOURCEBAR_EXPORT_SETTINGS")
			end,
		})

		addon.functions.SettingsCreateButton(cat, {
			var = "resourceBarsImport",
			text = L["Import"] or IMPORT,
			func = function()
				StaticPopupDialogs["EQOL_RESOURCEBAR_IMPORT_SETTINGS"] = StaticPopupDialogs["EQOL_RESOURCEBAR_IMPORT_SETTINGS"]
					or {
						text = L["ImportProfileTitle"] or "Import Resource Bars",
						button1 = OKAY,
						button2 = CANCEL,
						hasEditBox = true,
						editBoxWidth = 320,
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						preferredIndex = 3,
					}
				StaticPopupDialogs["EQOL_RESOURCEBAR_IMPORT_SETTINGS"].OnShow = function(self)
					self:SetFrameStrata("TOOLTIP")
					local editBox = self.editBox or self:GetEditBox()
					editBox:SetText("")
					editBox:SetFocus()
				end
				StaticPopupDialogs["EQOL_RESOURCEBAR_IMPORT_SETTINGS"].EditBoxOnEnterPressed = function(editBox)
					local parent = editBox:GetParent()
					if parent and parent.button1 then parent.button1:Click() end
				end
				StaticPopupDialogs["EQOL_RESOURCEBAR_IMPORT_SETTINGS"].OnAccept = function(self)
					local editBox = self.editBox or self:GetEditBox()
					local input = editBox:GetText() or ""
					local scopeKey = getScope() or "ALL"
					local ok, applied, enableState = addon.Aura.functions.importResourceProfile(input, scopeKey)
					if not ok then
						local msg = ResourceBars.ImportErrorMessage and ResourceBars.ImportErrorMessage(applied, enableState) or (L["ImportProfileFailed"] or "Import failed.")
						print("|cff00ff98Enhance QoL|r: " .. tostring(msg))
						return
					end
					if enableState ~= nil and scopeKey == "ALL" then
						local prev = addon.db["enableResourceFrame"]
						addon.db["enableResourceFrame"] = enableState and true or false
						if enableState and prev ~= true and addon.Aura.ResourceBars and addon.Aura.ResourceBars.EnableResourceBars then
							addon.Aura.ResourceBars.EnableResourceBars()
						elseif not enableState and prev ~= false and addon.Aura.ResourceBars and addon.Aura.ResourceBars.DisableResourceBars then
							addon.Aura.ResourceBars.DisableResourceBars()
						end
					end
					if applied then
						for _, specIndex in ipairs(applied) do
							addon.Aura.functions.requestActiveRefresh(specIndex)
						end
					end
					notifyResourceBarSettings()
					if applied and #applied > 0 then
						local specNames = {}
						for _, specIndex in ipairs(applied) do
							specNames[#specNames + 1] = ResourceBars.SpecNameByIndex and ResourceBars.SpecNameByIndex(specIndex) or tostring(specIndex)
						end
						local msg = (L["ImportProfileSuccess"] or "Resource Bars updated for: %s"):format(table.concat(specNames, ", "))
						print("|cff00ff98Enhance QoL|r: " .. msg)
					else
						local msg = L["ImportProfileSuccessGeneric"] or "Resource Bars profile imported."
						print("|cff00ff98Enhance QoL|r: " .. msg)
					end
					Settings.NotifyUpdate("EQOL_" .. "enableResourceFrame")
				end
				StaticPopup_Show("EQOL_RESOURCEBAR_IMPORT_SETTINGS")
			end,
		})
	end

	registerEditModeBars()
end

buildSettings()
