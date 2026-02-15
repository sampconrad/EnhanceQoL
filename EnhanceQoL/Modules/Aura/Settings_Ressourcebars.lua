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

local MIN_RESOURCE_BAR_WIDTH = (ResourceBars and ResourceBars.MIN_RESOURCE_BAR_WIDTH) or 10
local THRESHOLD_THICKNESS = (ResourceBars and ResourceBars.THRESHOLD_THICKNESS) or 1
local THRESHOLD_DEFAULT = (ResourceBars and ResourceBars.THRESHOLD_DEFAULT) or { 1, 1, 1, 0.5 }
local DEFAULT_THRESHOLDS = (ResourceBars and ResourceBars.DEFAULT_THRESHOLDS) or { 25, 50, 75, 90 }
local DEFAULT_THRESHOLD_COUNT = (ResourceBars and ResourceBars.DEFAULT_THRESHOLD_COUNT) or 3
local STAGGER_EXTRA_THRESHOLD_HIGH = (ResourceBars and ResourceBars.STAGGER_EXTRA_THRESHOLD_HIGH) or 200
local STAGGER_EXTRA_THRESHOLD_EXTREME = (ResourceBars and ResourceBars.STAGGER_EXTRA_THRESHOLD_EXTREME) or 300
local STAGGER_EXTRA_COLORS = (ResourceBars and ResourceBars.STAGGER_EXTRA_COLORS) or { high = { 0.62, 0.2, 1, 1 }, extreme = { 1, 0.2, 0.8, 1 } }
local SMF = addon.SharedMedia and addon.SharedMedia.functions
local EQOL_RUNES_BORDER = (ResourceBars and ResourceBars.RUNE_BORDER_ID) or "EQOL_BORDER_RUNES"
local EQOL_RUNES_BORDER_LABEL = (ResourceBars and ResourceBars.RUNE_BORDER_LABEL) or (SMF and SMF.GetCustomBorder and (SMF.GetCustomBorder(EQOL_RUNES_BORDER) or {}).label) or "EQOL: Runes"
local function customBorderOptions()
	if SMF and SMF.GetCustomBorderOptions then return SMF.GetCustomBorderOptions() end
	if ResourceBars and ResourceBars.GetCustomBorderOptions then return ResourceBars.GetCustomBorderOptions() end
	return nil
end
local AUTO_ENABLE_OPTIONS = {
	HEALTH = L["AutoEnableHealth"] or "Health",
	MAIN = L["AutoEnableMain"] or "Main resource",
	SECONDARY = L["AutoEnableSecondary"] or "Secondary resources",
}
local AUTO_ENABLE_ORDER = { "HEALTH", "MAIN", "SECONDARY" }

local specSettingVars = {}
local function autoEnableSelection()
	addon.db.resourceBarsAutoEnable = addon.db.resourceBarsAutoEnable or {}
	-- Migrate legacy boolean flag into the new selection map
	if addon.db.resourceBarsAutoEnableAll ~= nil then
		if addon.db.resourceBarsAutoEnableAll == true and not next(addon.db.resourceBarsAutoEnable) then addon.db.resourceBarsAutoEnable = { HEALTH = true, MAIN = true, SECONDARY = true } end
		addon.db.resourceBarsAutoEnableAll = nil
	end
	return addon.db.resourceBarsAutoEnable
end

local function shouldAutoEnableBar(pType, specInfo, selection)
	if not selection then return false end
	if pType == "HEALTH" then return selection.HEALTH == true end
	if specInfo and specInfo.MAIN == pType then return selection.MAIN == true end
	if specInfo and pType ~= specInfo.MAIN and pType ~= "HEALTH" then return specInfo[pType] == true and selection.SECONDARY == true end
	return false
end

local function maybeAutoEnableBars(specIndex, specCfg)
	if not specCfg or specCfg._autoEnabled then return end
	local selection = autoEnableSelection()
	if not selection or not (selection.HEALTH or selection.MAIN or selection.SECONDARY) then return end

	-- Skip if user already touched enable state
	for _, cfg in pairs(specCfg) do
		if type(cfg) == "table" and cfg.enabled ~= nil then return end
	end

	local class = addon.variables.unitClass
	if not class or not specIndex then return end
	local specInfo = ResourceBars and ResourceBars.powertypeClasses and ResourceBars.powertypeClasses[class] and ResourceBars.powertypeClasses[class][specIndex]
	if not specInfo then return end

	local bars = {}
	local mainType = specInfo.MAIN
	if selection.HEALTH then bars[#bars + 1] = "HEALTH" end
	if selection.MAIN and mainType then bars[#bars + 1] = mainType end
	if selection.SECONDARY then
		for _, pType in ipairs(ResourceBars.classPowerTypes or {}) do
			if specInfo[pType] and pType ~= mainType and pType ~= "HEALTH" then bars[#bars + 1] = pType end
		end
	end
	if #bars == 0 then return end

	local function frameNameFor(typeId)
		if typeId == "HEALTH" then return "EQOLHealthBar" end
		return "EQOL" .. tostring(typeId) .. "Bar"
	end

	local prevFrame = selection.HEALTH and frameNameFor("HEALTH") or nil
	local mainFrame = frameNameFor(mainType or "HEALTH")
	local applied = 0
	for _, pType in ipairs(bars) do
		if shouldAutoEnableBar(pType, specInfo, selection) then
			specCfg[pType] = specCfg[pType] or {}
			local ok = false
			if ResourceBars.ApplyGlobalProfile then ok = ResourceBars.ApplyGlobalProfile(pType, specIndex, false) end
			-- Fallback for fresh profiles/new chars without any saved global template yet.
			if not ok then
				specCfg[pType]._rbType = pType
				ok = true
			end
			if ok then
				applied = applied + 1
				specCfg[pType].enabled = true
				if pType == mainType and pType ~= "HEALTH" then
					local a = specCfg[pType].anchor or {}
					a.point = a.point or "CENTER"
					a.relativePoint = a.relativePoint or "CENTER"
					local targetFrame = a.relativeFrame or frameNameFor("HEALTH")
					if not selection.HEALTH and targetFrame == frameNameFor("HEALTH") then targetFrame = nil end
					a.relativeFrame = targetFrame
					a.x = a.x or 0
					a.y = a.y or -2
					a.autoSpacing = a.autoSpacing or nil
					a.matchRelativeWidth = a.matchRelativeWidth or true
					specCfg[pType].anchor = a
					prevFrame = frameNameFor(pType)
				elseif pType ~= "HEALTH" then
					local a = specCfg[pType].anchor or {}
					a.point = a.point or "CENTER"
					a.relativePoint = a.relativePoint or "CENTER"
					local explicitRelative = type(a.relativeFrame) == "string" and a.relativeFrame ~= ""
					local chained = false
					if not explicitRelative then
						local targetFrame = frameNameFor("HEALTH")
						if class == "DRUID" then
							if pType == "COMBO_POINTS" then
								targetFrame = frameNameFor("ENERGY")
							else
								targetFrame = prevFrame
							end
							if not targetFrame or targetFrame == "" then targetFrame = prevFrame or (selection.MAIN and mainFrame or nil) end
						else
							targetFrame = prevFrame
						end
						a.relativeFrame = targetFrame
						chained = targetFrame and targetFrame ~= ""
					end
					a.x = a.x or 0
					if chained then a.y = a.y or -2 end
					a.autoSpacing = a.autoSpacing or nil
					if chained then a.matchRelativeWidth = a.matchRelativeWidth or true end
					specCfg[pType].anchor = a
					if class ~= "DRUID" then prevFrame = frameNameFor(pType) end
				else
					prevFrame = frameNameFor(pType)
				end
			end
		end
	end

	if applied > 0 then specCfg._autoEnabled = true end
end

local function toColorComponents(c, fallback)
	c = c or fallback or {}
	if c.r then return c.r or 1, c.g or 1, c.b or 1, c.a or 1 end
	return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end

local function toColorArray(value, fallback)
	local r, g, b, a = toColorComponents(value, fallback)
	return { r, g, b, a }
end

local function toUIColor(value, fallback)
	local r, g, b, a = toColorComponents(value, fallback)
	return { r = r, g = g, b = b, a = a }
end

local function resolveStatusbarPreviewPath(key)
	if not key then return nil end
	if key == "DEFAULT" then return (ResourceBars and ResourceBars.DEFAULT_RB_TEX) or "Interface\\Buttons\\WHITE8x8" end
	return type(key) == "string" and key or nil
end

local function ensureDropdownTexturePreview(dropdown)
	if not dropdown then return end
	dropdown.texturePool = dropdown.texturePool or {}
	if dropdown._eqolTexturePreviewHooked or not dropdown.OnMenuClosed then return end
	hooksecurefunc(dropdown, "OnMenuClosed", function()
		for _, texture in pairs(dropdown.texturePool) do
			texture:Hide()
		end
	end)
	dropdown._eqolTexturePreviewHooked = true
end

local function attachDropdownTexturePreview(dropdown, button, index, texturePath)
	if not dropdown or not button or not texturePath then return end
	local tex = dropdown.texturePool[index]
	if not tex then
		tex = dropdown:CreateTexture(nil, "BACKGROUND")
		dropdown.texturePool[index] = tex
	end
	tex:SetParent(button)
	tex:SetAllPoints(button)
	tex:SetTexture(texturePath)
	tex:Show()
end

local function setIfChanged(tbl, key, value)
	if not tbl then return false end
	if tbl[key] == value then return false end
	tbl[key] = value
	return true
end

local function notifyResourceBarSettings()
	if not Settings or not Settings.NotifyUpdate then return end
	Settings.NotifyUpdate("EQOL_enableResourceFrame")
	Settings.NotifyUpdate("EQOL_resourceBarsHideOutOfCombat")
	Settings.NotifyUpdate("EQOL_resourceBarsHideMounted")
	Settings.NotifyUpdate("EQOL_resourceBarsHideVehicle")
	Settings.NotifyUpdate("EQOL_resourceBarsHidePetBattle")
	Settings.NotifyUpdate("EQOL_resourceBarsHideClientScene")
	for var in pairs(specSettingVars) do
		Settings.NotifyUpdate("EQOL_" .. var)
	end
end

local function applyResourceBarsVisibility(context)
	if ResourceBars and ResourceBars.ApplyVisibilityPreference then ResourceBars.ApplyVisibilityPreference(context or "settings") end
end
local function ensureSpecCfg(specIndex)
	local class = addon.variables.unitClass
	if not class or not specIndex then return end
	addon.db.personalResourceBarSettings = addon.db.personalResourceBarSettings or {}
	addon.db.personalResourceBarSettings[class] = addon.db.personalResourceBarSettings[class] or {}
	addon.db.personalResourceBarSettings[class][specIndex] = addon.db.personalResourceBarSettings[class][specIndex] or {}
	local specCfg = addon.db.personalResourceBarSettings[class][specIndex]
	maybeAutoEnableBars(specIndex, specCfg)
	return specCfg
end

local function refreshSettingsUI()
	local lib = addon.EditModeLib
	if lib and lib.internal and lib.internal.RefreshSettings then lib.internal:RefreshSettings() end
	if lib and lib.internal and lib.internal.RefreshSettingValues then lib.internal:RefreshSettingValues() end
end

local function setBarEnabled(specIndex, barType, enabled)
	local specCfg = ensureSpecCfg(specIndex)
	if not specCfg then return end
	specCfg[barType] = specCfg[barType] or {}
	local cfg = specCfg[barType]
	if enabled and not cfg._init and ResourceBars and ResourceBars.ApplyGlobalProfile then
		local ok = ResourceBars.ApplyGlobalProfile(barType, specIndex)
		if ok then cfg._appliedFromGlobal = true end
		cfg._init = true
	end
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
	if EditMode and EditMode.RefreshFrame then
		local curSpec = tonumber(specIndex or addon.variables.unitSpec) or 0
		local id = (ResourceBars.GetEditModeFrameId and ResourceBars.GetEditModeFrameId(barType, addon.variables.unitClass, curSpec))
			or ("resourceBar_" .. tostring(addon.variables.unitClass or "UNKNOWN") .. "_" .. tostring(curSpec) .. "_" .. tostring(barType))
		local layout = EditMode.GetActiveLayoutName and EditMode:GetActiveLayoutName()
		EditMode:RefreshFrame(id, layout)
	end
	if EditMode and EditMode:IsInEditMode() then
		if ResourceBars.Refresh then ResourceBars.Refresh() end
		if ResourceBars.ReanchorAll then ResourceBars.ReanchorAll() end
	end
end

local function registerEditModeBars()
	if not EditMode or not EditMode.RegisterFrame then return end
	local registered = 0
	local registeredFrames = ResourceBars._editModeRegisteredFrames or {}
	local registeredByBar = ResourceBars._editModeRegisteredFrameByBar or {}
	ResourceBars._editModeRegisteredFrames = registeredFrames
	ResourceBars._editModeRegisteredFrameByBar = registeredByBar

	local function registerBar(idSuffix, frameName, barType, widthDefault, heightDefault)
		local frame = _G[frameName]
		if not frame then return end
		local curSpec = tonumber(addon.variables.unitSpec) or 0
		local registeredSpec = curSpec
		local frameId = (ResourceBars.GetEditModeFrameId and ResourceBars.GetEditModeFrameId(idSuffix, addon.variables.unitClass, registeredSpec))
			or ("resourceBar_" .. tostring(addon.variables.unitClass or "UNKNOWN") .. "_" .. tostring(curSpec) .. "_" .. tostring(idSuffix))
		local prevId = registeredByBar[idSuffix]
		if prevId and prevId ~= frameId and EditMode and EditMode.UnregisterFrame then
			EditMode:UnregisterFrame(prevId)
			registeredFrames[prevId] = nil
		end
		if registeredFrames[frameId] then return end
		registeredFrames[frameId] = true
		registeredByBar[idSuffix] = frameId
		local cfg = ResourceBars and ResourceBars.getBarSettings and ResourceBars.getBarSettings(barType) or ResourceBars and ResourceBars.GetBarSettings and ResourceBars.GetBarSettings(barType)
		local anchor = ResourceBars and ResourceBars.getAnchor and ResourceBars.getAnchor(barType, addon.variables.unitSpec)
		local titleLabel = (barType == "HEALTH") and (HEALTH or "Health") or (ResourceBars.PowerLabels and ResourceBars.PowerLabels[barType]) or _G["POWER_TYPE_" .. barType] or _G[barType] or barType
		local function currentSpecInfo()
			local uc = addon.variables.unitClass
			local us = addon.variables.unitSpec
			return ResourceBars and ResourceBars.powertypeClasses and ResourceBars.powertypeClasses[uc] and ResourceBars.powertypeClasses[uc][us]
		end

		-- Ensure backdrop defaults for current spec view
		cfg = cfg or {}
		cfg.backdrop = cfg.backdrop or {}
		if cfg.backdrop.enabled == nil then cfg.backdrop.enabled = true end
		cfg.backdrop.backgroundTexture = cfg.backdrop.backgroundTexture or "Interface\\DialogFrame\\UI-DialogBox-Background"
		cfg.backdrop.backgroundColor = cfg.backdrop.backgroundColor or { 0, 0, 0, 0.8 }
		cfg.backdrop.borderTexture = cfg.backdrop.borderTexture or "Interface\\Tooltips\\UI-Tooltip-Border"
		cfg.backdrop.borderColor = cfg.backdrop.borderColor or { 0, 0, 0, 0 }
		cfg.backdrop.edgeSize = cfg.backdrop.edgeSize or 3
		cfg.backdrop.outset = cfg.backdrop.outset or 0
		cfg.backdrop.backgroundInset = max(0, cfg.backdrop.backgroundInset or 0)
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
		local function applyBarSize()
			local c = curSpecCfg()
			if not c then return end
			if barType == "HEALTH" then
				ResourceBars.SetHealthBarSize(c.width or widthDefault, c.height or heightDefault)
			else
				ResourceBars.SetPowerBarSize(c.width or widthDefault, c.height or heightDefault, barType)
			end
		end
		local function ensureBackdropTable(target)
			if not target then return nil end
			target.backdrop = target.backdrop or {}
			local bd = target.backdrop
			local base = (cfg and cfg.backdrop) or {}
			if bd.enabled == nil then
				if base.enabled ~= nil then
					bd.enabled = base.enabled
				else
					bd.enabled = true
				end
			end
			bd.backgroundTexture = bd.backgroundTexture or base.backgroundTexture or "Interface\\DialogFrame\\UI-DialogBox-Background"
			bd.backgroundColor = bd.backgroundColor or toColorArray(base.backgroundColor, { 0, 0, 0, 0.8 })
			bd.borderTexture = bd.borderTexture or base.borderTexture or "Interface\\Tooltips\\UI-Tooltip-Border"
			bd.borderColor = bd.borderColor or toColorArray(base.borderColor, { 0, 0, 0, 0 })
			bd.edgeSize = bd.edgeSize or base.edgeSize or 3
			bd.outset = bd.outset or base.outset or 0
			bd.backgroundInset = max(0, bd.backgroundInset or base.backgroundInset or 0)
			bd.innerPadding = nil
			return bd
		end
		local function ensureAnchorTable()
			local c = curSpecCfg()
			if not c then return nil end
			c.anchor = c.anchor or {}
			local a = c.anchor
			if not a.point then a.point = "CENTER" end
			if not a.relativePoint then a.relativePoint = a.point end
			if a.x == nil then a.x = 0 end
			if a.y == nil then a.y = 0 end
			if not a.relativeFrame or a.relativeFrame == "" then a.relativeFrame = "UIParent" end
			return a
		end
		local function syncEditModeLayoutFromAnchor()
			if not (EditMode and EditMode.EnsureLayoutData and EditMode.GetActiveLayoutName) then return end
			local a = ensureAnchorTable()
			if not a or (a.relativeFrame or "UIParent") ~= "UIParent" then return end
			local layout = EditMode:GetActiveLayoutName()
			local data = EditMode:EnsureLayoutData(frameId, layout)
			if not data then return end
			data.point = a.point or "CENTER"
			data.relativePoint = a.relativePoint or data.point
			data.x = a.x or 0
			data.y = a.y or 0
		end
		local function anchorUsesUIParent()
			local a = ensureAnchorTable()
			return not a or (a.relativeFrame or "UIParent") == "UIParent"
		end
		local function notify(msg)
			if not msg or msg == "" then return end
			print("|cff00ff98Enhance QoL|r: " .. tostring(msg))
		end
		local function hasGlobalProfile(targetKey)
			local store = addon.db and addon.db.globalResourceBarSettings
			if not store then return false end
			if targetKey == "MAIN" then return store.MAIN end
			if targetKey == "SECONDARY" then return store.SECONDARY end
			return store[targetKey or barType]
		end
		local function confirmSaveGlobal(targetKey, doSave)
			local specInfo = currentSpecInfo()
			if hasGlobalProfile(targetKey) then
				local key = "EQOL_SAVE_GLOBAL_RB_" .. tostring(targetKey or barType)
				local popupText
				if targetKey == "MAIN" or (not targetKey and specInfo and specInfo.MAIN == barType) then
					popupText = L["OverwriteGlobalMainProfile"] or "Overwrite global main profile?"
				else
					popupText = (L["OverwriteGlobalProfile"] or "Overwrite global profile for %s?"):format(titleLabel)
				end
				StaticPopupDialogs[key] = StaticPopupDialogs[key]
					or {
						text = popupText,
						button1 = OKAY,
						button2 = CANCEL,
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						preferredIndex = 3,
						OnAccept = function()
							if doSave then doSave() end
						end,
					}
				StaticPopup_Show(key)
			else
				if doSave then doSave() end
			end
		end
		local buttons = {}
		local function forceUIParentAnchor()
			local a = ensureAnchorTable()
			if not a then return end
			if (a.relativeFrame or "UIParent") ~= "UIParent" then
				a.relativeFrame = "UIParent"
				a.point = "CENTER"
				a.relativePoint = "CENTER"
				a.x = 0
				a.y = 0
				a.autoSpacing = nil
				a.matchRelativeWidth = nil
				refreshSettingsUI()
			end
		end
		local settingType = EditMode.lib and EditMode.lib.SettingType
		local settingsList
		if settingType then
			local function backgroundDropdownData()
				local map = {
					["Interface\\DialogFrame\\UI-DialogBox-Background"] = "Dialog Background",
					["Interface\\Buttons\\WHITE8x8"] = "Solid (tintable)",
				}
				if LibStub then
					local media = LibStub("LibSharedMedia-3.0", true)
					if media then
						for name, path in pairs(media:HashTable("background") or {}) do
							if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
						end
					end
				end
				return addon.functions.prepareListForDropdown(map)
			end

			local function borderDropdownData()
				local map = { ["Interface\\Tooltips\\UI-Tooltip-Border"] = "Tooltip Border" }
				for id, label in pairs(customBorderOptions() or {}) do
					map[id] = label
				end
				if LibStub then
					local media = LibStub("LibSharedMedia-3.0", true)
					if media then
						for name, path in pairs(media:HashTable("border") or {}) do
							if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
						end
					end
				end
				return addon.functions.prepareListForDropdown(map)
			end

			settingsList = {
				{
					name = L["Frame"] or "Frame",
					kind = settingType.Collapsible,
					id = "frame",
					defaultCollapsed = false,
				},
				{
					name = HUD_EDIT_MODE_SETTING_CHAT_FRAME_WIDTH,
					kind = settingType.Slider,
					allowInput = true,
					field = "width",
					minValue = 10,
					maxValue = 600,
					valueStep = 1,
					default = widthDefault or 200,
					parentId = "frame",
					get = function()
						local c = curSpecCfg()
						return c and c.width or widthDefault or 200
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						if not setIfChanged(c, "width", value) then return end
						if EditMode and EditMode.SetValue then EditMode:SetValue(frameId, "width", value, nil, true) end
						applyBarSize()
						queueRefresh()
					end,
					isEnabled = function()
						if anchorUsesUIParent() then return true end
						local c = curSpecCfg()
						local a = c and c.anchor
						return not (a and a.matchRelativeWidth == true)
					end,
				},
				{
					name = HUD_EDIT_MODE_SETTING_CHAT_FRAME_HEIGHT,
					kind = settingType.Slider,
					allowInput = true,
					field = "height",
					minValue = 6,
					maxValue = 600,
					valueStep = 1,
					default = heightDefault or 20,
					parentId = "frame",
					get = function()
						local c = curSpecCfg()
						return c and c.height or heightDefault or 20
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						if not setIfChanged(c, "height", value) then return end
						if EditMode and EditMode.SetValue then EditMode:SetValue(frameId, "height", value, nil, true) end
						applyBarSize()
						queueRefresh()
					end,
				},
				{
					name = L["Click-through"] or "Click-through",
					kind = settingType.Checkbox,
					field = "clickThrough",
					default = cfg and cfg.clickThrough == true,
					parentId = "frame",
					get = function()
						local c = curSpecCfg()
						return c and c.clickThrough == true
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.clickThrough = value and true or false
						queueRefresh()
					end,
					isShown = function() return barType ~= "HEALTH" end,
				},
			}
			if barType == "MAELSTROM_WEAPON" then
				settingsList[#settingsList + 1] = {
					name = "Use 10-stack bar",
					kind = settingType.Checkbox,
					field = "useMaelstromTenStacks",
					default = false,
					parentId = "frame",
					get = function()
						local c = curSpecCfg()
						return c and c.useMaelstromTenStacks == true
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.useMaelstromTenStacks = value and true or false
						if c.useMaelstromTenStacks then
							c.visualSegments = 10
						elseif c.visualSegments == 10 or c.visualSegments == nil then
							c.visualSegments = 5
						end
						queueRefresh()
					end,
				}
			end

			do -- Anchoring
				local points = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
				local function displayNameForBarType(pType)
					if pType == "HEALTH" then return HEALTH or "Health" end
					local s = (ResourceBars.PowerLabels and ResourceBars.PowerLabels[pType]) or _G["POWER_TYPE_" .. pType] or _G[pType]
					if type(s) == "string" and s ~= "" then return s end
					return pType
				end
				local function frameNameToBarType(fname)
					if fname == "EQOLHealthBar" then return "HEALTH" end
					return type(fname) == "string" and fname:match("^EQOL(.+)Bar$") or nil
				end
				local function wouldCauseLoop(fromType, candidateName)
					if candidateName == "UIParent" then return false end
					local candType = frameNameToBarType(candidateName)
					if not candType then return false end
					if candType == fromType then return true end
					local targetFrameName = (fromType == "HEALTH") and "EQOLHealthBar" or ("EQOL" .. fromType .. "Bar")
					local seen = {}
					local name = candidateName
					local spec = addon.variables.unitSpec
					local limit = 10
					while name and name ~= "UIParent" and limit > 0 do
						if seen[name] then break end
						seen[name] = true
						if name == targetFrameName then return true end
						local bt = frameNameToBarType(name)
						if not bt then break end
						local specCfg = ensureSpecCfg(spec)
						local anch = specCfg and specCfg[bt] and specCfg[bt].anchor
						name = anch and anch.relativeFrame or "UIParent"
						limit = limit - 1
					end
					return false
				end
				local function isBarEnabled(pType)
					local spec = addon.variables.unitSpec
					local specCfg = ensureSpecCfg(spec)
					return specCfg and specCfg[pType] and specCfg[pType].enabled == true
				end
				local function enforceMinWidth()
					local c = curSpecCfg()
					if not c then return end
					local minWidth = MIN_RESOURCE_BAR_WIDTH or 10
					c.width = minWidth
					if barType == "HEALTH" then
						ResourceBars.SetHealthBarSize(c.width or minWidth, c.height or heightDefault or 20)
					else
						ResourceBars.SetPowerBarSize(c.width or minWidth, c.height or heightDefault or 20, barType)
					end
				end

				local function relativeFrameEntries()
					local entries = {}
					local seen = {}
					local function add(key, label)
						if not key or key == "" or seen[key] then return end
						if wouldCauseLoop(barType, key) then return end
						seen[key] = true
						entries[#entries + 1] = { key = key, label = label or key }
					end

					add("UIParent", "UIParent")
					add("PlayerFrame", "PlayerFrame")
					add("TargetFrame", "TargetFrame")
					add("EssentialCooldownViewer", "EssentialCooldownViewer")
					add("UtilityCooldownViewer", "UtilityCooldownViewer")
					add("BuffBarCooldownViewer", "BuffBarCooldownViewer")
					add("BuffIconCooldownViewer", "BuffIconCooldownViewer")

					local cooldownPanels = addon.Aura and addon.Aura.CooldownPanels
					if cooldownPanels and cooldownPanels.GetRoot then
						local root = cooldownPanels:GetRoot()
						if root and root.panels then
							local order = root.order or {}
							local function addPanelEntry(panelId, panel)
								if not panel or panel.enabled == false then return end
								local label = string.format("Panel %s: %s", tostring(panelId), panel.name or "Cooldown Panel")
								add("EQOL_CooldownPanel" .. tostring(panelId), label)
							end
							if #order > 0 then
								for _, panelId in ipairs(order) do
									addPanelEntry(panelId, root.panels[panelId])
								end
							else
								for panelId, panel in pairs(root.panels) do
									addPanelEntry(panelId, panel)
								end
							end
						end
					end

					if addon.variables and addon.variables.actionBarNames then
						for _, info in ipairs(addon.variables.actionBarNames) do
							if info.name then add(info.name, info.text or info.name) end
						end
					end

					if isBarEnabled("HEALTH") then add("EQOLHealthBar", displayNameForBarType("HEALTH")) end
					for _, pType in ipairs(ResourceBars.classPowerTypes or {}) do
						if isBarEnabled(pType) then
							local fname = "EQOL" .. pType .. "Bar"
							add(fname, displayNameForBarType(pType))
						end
					end

					local a = ensureAnchorTable()
					local cur = a and a.relativeFrame
					if cur and not seen[cur] and not wouldCauseLoop(barType, cur) then add(cur, cur) end

					return entries
				end
				local function validateRelativeFrame(a)
					if not a then return "UIParent" end
					local cur = a.relativeFrame or "UIParent"
					local entries = relativeFrameEntries()
					local ok = false
					for _, e in ipairs(entries) do
						if e.key == cur then
							ok = true
							break
						end
					end
					if not ok then
						cur = "UIParent"
						a.relativeFrame = cur
					end
					return cur
				end
				local function applyAnchorDefaults(a, target)
					if not a then return end
					if target == "UIParent" then
						a.point = "CENTER"
						a.relativePoint = "CENTER"
						a.x = 0
						a.y = 0
						a.autoSpacing = nil
						a.matchRelativeWidth = nil
					else
						a.point = "TOPLEFT"
						a.relativePoint = "BOTTOMLEFT"
						a.x = 0
						a.y = 0
						a.autoSpacing = nil
					end
				end
				settingsList[#settingsList + 1] = {
					name = "Relative frame",
					kind = settingType.Dropdown,
					height = 180,
					field = "anchorRelativeFrame",
					generator = function(_, root)
						local entries = relativeFrameEntries()
						for _, entry in ipairs(entries) do
							root:CreateRadio(entry.label, function()
								local a = ensureAnchorTable()
								local cur = validateRelativeFrame(a)
								return cur == entry.key
							end, function()
								local a = ensureAnchorTable()
								if not a then return end
								local target = entry.key
								if wouldCauseLoop(barType, target) then target = "UIParent" end
								a.relativeFrame = target
								applyAnchorDefaults(a, target)
								if target ~= "UIParent" and a.matchRelativeWidth == true then enforceMinWidth() end
								syncEditModeLayoutFromAnchor()
								queueRefresh()
								refreshSettingsUI()
							end)
						end
					end,
					get = function()
						local a = ensureAnchorTable()
						return validateRelativeFrame(a)
					end,
					set = function(_, value)
						local a = ensureAnchorTable()
						if not a then return end
						local target = value or "UIParent"
						if wouldCauseLoop(barType, target) then target = "UIParent" end
						a.relativeFrame = target
						applyAnchorDefaults(a, target)
						if target ~= "UIParent" and a.matchRelativeWidth == true then enforceMinWidth() end
						syncEditModeLayoutFromAnchor()
						queueRefresh()
						refreshSettingsUI()
					end,
					default = "UIParent",
					parentId = "frame",
				}

				settingsList[#settingsList + 1] = {
					name = "Anchor point",
					kind = settingType.Dropdown,
					height = 180,
					field = "anchorPoint",
					generator = function(_, root)
						for _, p in ipairs(points) do
							root:CreateRadio(p, function()
								local a = ensureAnchorTable()
								return a and (a.point or "CENTER") == p
							end, function()
								local a = ensureAnchorTable()
								if not a then return end
								a.point = p
								if not a.relativePoint then a.relativePoint = p end
								syncEditModeLayoutFromAnchor()
								queueRefresh()
							end)
						end
					end,
					get = function()
						local a = ensureAnchorTable()
						return a and a.point or "CENTER"
					end,
					set = function(_, value)
						local a = ensureAnchorTable()
						if not a then return end
						a.point = value
						if not a.relativePoint then a.relativePoint = value end
						syncEditModeLayoutFromAnchor()
						queueRefresh()
					end,
					default = "CENTER",
					parentId = "frame",
				}

				settingsList[#settingsList + 1] = {
					name = "Relative point",
					kind = settingType.Dropdown,
					height = 180,
					field = "anchorRelativePoint",
					generator = function(_, root)
						for _, p in ipairs(points) do
							root:CreateRadio(p, function()
								local a = ensureAnchorTable()
								return a and (a.relativePoint or "CENTER") == p
							end, function()
								local a = ensureAnchorTable()
								if not a then return end
								a.relativePoint = p
								syncEditModeLayoutFromAnchor()
								queueRefresh()
							end)
						end
					end,
					get = function()
						local a = ensureAnchorTable()
						return a and a.relativePoint or "CENTER"
					end,
					set = function(_, value)
						local a = ensureAnchorTable()
						if not a then return end
						a.relativePoint = value
						syncEditModeLayoutFromAnchor()
						queueRefresh()
					end,
					default = "CENTER",
					parentId = "frame",
				}

				settingsList[#settingsList + 1] = {
					name = L["MatchRelativeFrameWidth"] or "Match Relative Frame width",
					kind = settingType.Checkbox,
					field = "matchRelativeWidth",
					get = function()
						local a = ensureAnchorTable()
						return a and a.matchRelativeWidth == true
					end,
					set = function(_, value)
						local a = ensureAnchorTable()
						if not a then return end
						a.matchRelativeWidth = value and true or nil
						if a.matchRelativeWidth then enforceMinWidth() end
						queueRefresh()
						refreshSettingsUI()
					end,
					isEnabled = function() return not anchorUsesUIParent() end,
					default = false,
					parentId = "frame",
				}

				settingsList[#settingsList + 1] = {
					name = "X Offset",
					kind = settingType.Slider,
					allowInput = true,
					field = "anchorOffsetX",
					minValue = -1000,
					maxValue = 1000,
					valueStep = 1,
					get = function()
						local a = ensureAnchorTable()
						return a and a.x or 0
					end,
					set = function(_, value)
						local a = ensureAnchorTable()
						if not a then return end
						local new = value or 0
						if a.x == new then return end
						a.x = new
						a.autoSpacing = false
						syncEditModeLayoutFromAnchor()
						queueRefresh()
					end,
					default = 0,
					parentId = "frame",
				}

				settingsList[#settingsList + 1] = {
					name = "Y Offset",
					kind = settingType.Slider,
					allowInput = true,
					field = "anchorOffsetY",
					minValue = -1000,
					maxValue = 1000,
					valueStep = 1,
					get = function()
						local a = ensureAnchorTable()
						return a and a.y or 0
					end,
					set = function(_, value)
						local a = ensureAnchorTable()
						if not a then return end
						local new = value or 0
						if a.y == new then return end
						a.y = new
						a.autoSpacing = false
						syncEditModeLayoutFromAnchor()
						queueRefresh()
					end,
					default = 0,
					parentId = "frame",
				}
			end

			settingsList[#settingsList + 1] = {
				name = L["Bar Texture"] or "Bar Texture",
				kind = settingType.Dropdown,
				height = 180,
				field = "barTexture",
				parentId = "frame",
				generator = function(dropdown, root)
					local listTex, orderTex = addon.Aura.functions.getStatusbarDropdownLists(true)
					if not listTex or not orderTex then
						listTex, orderTex = { DEFAULT = DEFAULT }, { "DEFAULT" }
					end
					if not listTex or not orderTex then return end
					ensureDropdownTexturePreview(dropdown)
					for index, key in ipairs(orderTex) do
						local label = listTex[key] or key
						local previewIndex = index
						local previewPath = resolveStatusbarPreviewPath(key)
						local checkbox = root:CreateCheckbox(label, function()
							local c = curSpecCfg()
							local cur = c and c.barTexture or cfg.barTexture or "DEFAULT"
							return cur == key
						end, function()
							local c = curSpecCfg()
							if not c then return end
							local cur = c.barTexture or cfg.barTexture or "DEFAULT"
							if cur == key then return end
							c.barTexture = key
							queueRefresh()
						end)
						if previewPath then checkbox:AddInitializer(function(button) attachDropdownTexturePreview(dropdown, button, previewIndex, previewPath) end) end
					end
				end,
				get = function()
					local c = curSpecCfg()
					return (c and c.barTexture) or cfg.barTexture or "DEFAULT"
				end,
				set = function(_, value)
					local c = curSpecCfg()
					if not c then return end
					c.barTexture = value
					queueRefresh()
				end,
				default = cfg and cfg.barTexture or "DEFAULT",
			}

			do -- Behavior
				local behaviorValues = ResourceBars.BehaviorOptionsForType and ResourceBars.BehaviorOptionsForType(barType)
				if not behaviorValues then
					behaviorValues = {
						{ value = "reverseFill", text = L["Reverse fill"] or "Reverse fill" },
					}
					if barType ~= "RUNES" then
						behaviorValues[#behaviorValues + 1] = { value = "verticalFill", text = L["Vertical orientation"] or "Vertical orientation" }
						behaviorValues[#behaviorValues + 1] = { value = "smoothFill", text = L["Smooth fill"] or "Smooth fill" }
					end
				end

				local function currentBehaviorSelection()
					if ResourceBars and ResourceBars.BehaviorSelectionFromConfig then return ResourceBars.BehaviorSelectionFromConfig(curSpecCfg(), barType) end
					local c = curSpecCfg()
					local map = {}
					if c then
						if c.reverseFill == true then map.reverseFill = true end
						if barType ~= "RUNES" then
							if c.verticalFill == true then map.verticalFill = true end
							if c.smoothFill == true then map.smoothFill = true end
						end
					end
					return map
				end

				local function applyBehaviorFlag(key, enabled)
					local cfg = curSpecCfg()
					if not cfg then return end
					local selection = currentBehaviorSelection()
					if key then selection[key] = enabled and true or nil end
					local swapped = false
					if ResourceBars and ResourceBars.ApplyBehaviorSelection then
						swapped = ResourceBars.ApplyBehaviorSelection(cfg, selection, barType, addon.variables.unitSpec) and true or false
					else
						cfg.reverseFill = selection.reverseFill == true
						if barType ~= "RUNES" then
							cfg.verticalFill = selection.verticalFill == true
							cfg.smoothFill = selection.smoothFill == true
						else
							cfg.verticalFill = nil
							cfg.smoothFill = nil
						end
					end
					queueRefresh()
					if swapped then refreshSettingsUI() end
				end

				if settingType.MultiDropdown and behaviorValues and #behaviorValues > 0 then
					settingsList[#settingsList + 1] = {
						name = L["Behavior"] or "Behavior",
						kind = settingType.MultiDropdown,
						height = 180,
						field = "behavior",
						default = currentBehaviorSelection(),
						values = behaviorValues,
						hideSummary = true,
						parentId = "frame",
						isSelected = function(_, value)
							local selection = currentBehaviorSelection()
							return selection[value] == true
						end,
						setSelected = function(_, value, state) applyBehaviorFlag(value, state) end,
					}
				end
			end

			-- Separator controls (eligible bars only)
			if ResourceBars.separatorEligible and ResourceBars.separatorEligible[barType] then
				settingsList[#settingsList + 1] = {
					name = L["Show separator"] or "Show separator",
					kind = settingType.CheckboxColor,
					field = "showSeparator",
					default = cfg and cfg.showSeparator == true,
					get = function()
						local c = curSpecCfg()
						return c and c.showSeparator == true
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.showSeparator = value and true or false
						queueRefresh()
					end,
					colorDefault = toUIColor(cfg and cfg.separatorColor, SEP_DEFAULT),
					colorGet = function()
						local c = curSpecCfg()
						local col = (c and c.separatorColor) or (cfg and cfg.separatorColor) or SEP_DEFAULT
						local r, g, b, a = toColorComponents(col, SEP_DEFAULT)
						return { r = r, g = g, b = b, a = a }
					end,
					colorSet = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.separatorColor = toColorArray(value, SEP_DEFAULT)
						queueRefresh()
					end,
					hasOpacity = true,
					parentId = "frame",
				}

				settingsList[#settingsList + 1] = {
					name = L["Separator thickness"] or "Separator thickness",
					kind = settingType.Slider,
					allowInput = true,
					field = "separatorThickness",
					minValue = 1,
					maxValue = 10,
					valueStep = 1,
					get = function()
						local c = curSpecCfg()
						return (c and c.separatorThickness) or SEPARATOR_THICKNESS
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						local new = value or SEPARATOR_THICKNESS
						if c.separatorThickness == new then return end
						c.separatorThickness = new
						queueRefresh()
					end,
					default = (cfg and cfg.separatorThickness) or SEPARATOR_THICKNESS,
					isEnabled = function()
						local c = curSpecCfg()
						return c and c.showSeparator == true
					end,
					parentId = "frame",
				}
			end

			-- Threshold controls (all non-health bars)
			if barType ~= "HEALTH" then
				settingsList[#settingsList + 1] = {
					name = L["Show threshold lines"] or "Show threshold lines",
					kind = settingType.CheckboxColor,
					field = "showThresholds",
					default = cfg and cfg.showThresholds == true,
					get = function()
						local c = curSpecCfg()
						return c and c.showThresholds == true
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.showThresholds = value and true or false
						queueRefresh()
					end,
					colorDefault = toUIColor(cfg and cfg.thresholdColor, THRESHOLD_DEFAULT),
					colorGet = function()
						local c = curSpecCfg()
						local col = (c and c.thresholdColor) or (cfg and cfg.thresholdColor) or THRESHOLD_DEFAULT
						local r, g, b, a = toColorComponents(col, THRESHOLD_DEFAULT)
						return { r = r, g = g, b = b, a = a }
					end,
					colorSet = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.thresholdColor = toColorArray(value, THRESHOLD_DEFAULT)
						queueRefresh()
					end,
					hasOpacity = true,
					parentId = "frame",
				}

				settingsList[#settingsList + 1] = {
					name = L["Use absolute values"] or "Use absolute values",
					kind = settingType.Checkbox,
					field = "useAbsoluteThresholds",
					default = cfg and cfg.useAbsoluteThresholds == true,
					get = function()
						local c = curSpecCfg()
						return c and c.useAbsoluteThresholds == true
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.useAbsoluteThresholds = value and true or false
						queueRefresh()
						refreshSettingsUI()
					end,
					isEnabled = function()
						local c = curSpecCfg()
						return c and c.showThresholds == true
					end,
					parentId = "frame",
				}

				settingsList[#settingsList + 1] = {
					name = L["Number of thresholds"] or "Number of thresholds",
					kind = settingType.Dropdown,
					height = 120,
					field = "thresholdCount",
					parentId = "frame",
					values = {
						{ value = 1, text = "1" },
						{ value = 2, text = "2" },
						{ value = 3, text = "3" },
						{ value = 4, text = "4" },
					},
					get = function()
						local c = curSpecCfg()
						local count = (c and c.thresholdCount) or DEFAULT_THRESHOLD_COUNT
						return tostring(count)
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						local new = tonumber(value) or DEFAULT_THRESHOLD_COUNT
						if new < 1 then new = 1 end
						if new > 4 then new = 4 end
						if c.thresholdCount == new then return end
						c.thresholdCount = new
						queueRefresh()
					end,
					default = tostring(DEFAULT_THRESHOLD_COUNT),
					isEnabled = function()
						local c = curSpecCfg()
						return c and c.showThresholds == true
					end,
				}

				settingsList[#settingsList + 1] = {
					name = L["Threshold line thickness"] or "Threshold line thickness",
					kind = settingType.Slider,
					allowInput = true,
					field = "thresholdThickness",
					minValue = 1,
					maxValue = 10,
					valueStep = 1,
					get = function()
						local c = curSpecCfg()
						return (c and c.thresholdThickness) or THRESHOLD_THICKNESS
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						local new = value or THRESHOLD_THICKNESS
						if c.thresholdThickness == new then return end
						c.thresholdThickness = new
						queueRefresh()
					end,
					default = (cfg and cfg.thresholdThickness) or THRESHOLD_THICKNESS,
					isEnabled = function()
						local c = curSpecCfg()
						return c and c.showThresholds == true
					end,
					parentId = "frame",
				}

				local thresholdMaxValue = (curSpecCfg() and curSpecCfg().useAbsoluteThresholds == true) and 1000 or 100
				local function thresholdValue(index)
					local c = curSpecCfg()
					local list = (c and c.thresholds)
					if type(list) ~= "table" then list = (cfg and cfg.thresholds) end
					if type(list) == "table" then return tonumber(list[index]) or 0 end
					return DEFAULT_THRESHOLDS[index] or 0
				end

				local function thresholdCount()
					local c = curSpecCfg()
					local count = tonumber(c and c.thresholdCount) or DEFAULT_THRESHOLD_COUNT
					if count < 1 then count = 1 end
					if count > 4 then count = 4 end
					return count
				end

				local function setThresholdValue(index, value)
					local c = curSpecCfg()
					if not c then return end
					if type(c.thresholds) ~= "table" then c.thresholds = { DEFAULT_THRESHOLDS[1], DEFAULT_THRESHOLDS[2], DEFAULT_THRESHOLDS[3], DEFAULT_THRESHOLDS[4] } end
					c.thresholds[index] = value or 0
					queueRefresh()
				end

				local thresholdLabels = {
					L["Threshold 1"] or "Threshold 1",
					L["Threshold 2"] or "Threshold 2",
					L["Threshold 3"] or "Threshold 3",
					L["Threshold 4"] or "Threshold 4",
				}

				for i = 1, #thresholdLabels do
					settingsList[#settingsList + 1] = {
						name = thresholdLabels[i],
						kind = settingType.Slider,
						allowInput = true,
						field = "threshold" .. i,
						minValue = 0,
						maxValue = thresholdMaxValue,
						valueStep = 1,
						get = function() return thresholdValue(i) end,
						set = function(_, value) setThresholdValue(i, value) end,
						default = DEFAULT_THRESHOLDS[i] or 0,
						isEnabled = function()
							local c = curSpecCfg()
							return c and c.showThresholds == true
						end,
						isShown = function() return i <= thresholdCount() end,
						parentId = "frame",
					}
				end
			end

			-- Druid: Show in (forms), exclude Health and enforced Cat-only Combo Points
			if addon.variables.unitClass == "DRUID" and barType ~= "HEALTH" and barType ~= "COMBO_POINTS" then
				local forms = { "HUMANOID", "BEAR", "CAT", "TRAVEL", "MOONKIN", "STAG" }
				local formLabels = {
					HUMANOID = L["Humanoid"] or "Humanoid",
					BEAR = L["Bear"] or "Bear",
					CAT = L["Cat"] or "Cat",
					TRAVEL = L["Travel"] or "Travel",
					MOONKIN = L["Moonkin"] or "Moonkin",
					STAG = L["Stag"] or "Stag",
				}

				local function ensureShowForms()
					local c = curSpecCfg()
					if not c then return nil end
					c.showForms = c.showForms or {}
					local sf = c.showForms
					if barType == "COMBO_POINTS" then
						if sf.CAT == nil then sf.CAT = true end
						if sf.HUMANOID == nil then sf.HUMANOID = false end
						if sf.BEAR == nil then sf.BEAR = false end
						if sf.TRAVEL == nil then sf.TRAVEL = false end
						if sf.MOONKIN == nil then sf.MOONKIN = false end
						if sf.STAG == nil then sf.STAG = false end
					else
						local specInfo = currentSpecInfo()
						local isSecondaryMana = barType == "MANA" and specInfo and specInfo.MAIN ~= "MANA"
						local isSecondaryEnergy = barType == "ENERGY" and specInfo and specInfo.MAIN ~= "ENERGY"
						if isSecondaryMana then
							if sf.HUMANOID == nil then sf.HUMANOID = true end
							if sf.BEAR == nil then sf.BEAR = false end
							if sf.CAT == nil then sf.CAT = false end
							if sf.TRAVEL == nil then sf.TRAVEL = false end
							if sf.MOONKIN == nil then sf.MOONKIN = false end
							if sf.STAG == nil then sf.STAG = false end
						elseif isSecondaryEnergy then
							if sf.HUMANOID == nil then sf.HUMANOID = false end
							if sf.BEAR == nil then sf.BEAR = false end
							if sf.CAT == nil then sf.CAT = true end
							if sf.TRAVEL == nil then sf.TRAVEL = false end
							if sf.MOONKIN == nil then sf.MOONKIN = false end
							if sf.STAG == nil then sf.STAG = false end
						else
							if sf.HUMANOID == nil then sf.HUMANOID = true end
							if sf.BEAR == nil then sf.BEAR = true end
							if sf.CAT == nil then sf.CAT = true end
							if sf.TRAVEL == nil then sf.TRAVEL = true end
							if sf.MOONKIN == nil then sf.MOONKIN = true end
							if sf.STAG == nil then sf.STAG = true end
						end
					end
					return sf
				end

				local dropdownValues = {}
				for _, key in ipairs(forms) do
					if barType ~= "COMBO_POINTS" or key == "CAT" then dropdownValues[#dropdownValues + 1] = { value = key, text = formLabels[key] or key } end
				end

				if settingType.MultiDropdown then
					settingsList[#settingsList + 1] = {
						name = L["Show in"] or "Show in",
						kind = settingType.MultiDropdown,
						field = "showForms",
						values = dropdownValues,
						hideSummary = true,
						isSelected = function(_, value)
							local sf = ensureShowForms()
							if not sf then return false end
							local cur = sf[value]
							if cur == nil then return true end
							return cur ~= false
						end,
						setSelected = function(_, value, state)
							local sf = ensureShowForms()
							if not sf then return end
							sf[value] = state and true or false
							queueRefresh()
							refreshSettingsUI()
						end,
						default = ensureShowForms(),
						parentId = "frame",
					}
				end
			end

			if barType == "HEALTH" then
				local absorbDefaultColor = { 0.8, 0.8, 0.8, 0.8 }
				settingsList[#settingsList + 1] = {
					name = L["AbsorbBar"] or "Absorb Bar",
					kind = settingType.Collapsible,
					id = "absorb",
					defaultCollapsed = true,
				}

				settingsList[#settingsList + 1] = {
					name = L["Enable absorb bar"] or "Enable absorb bar",
					kind = settingType.Checkbox,
					field = "absorbEnabled",
					parentId = "absorb",
					get = function()
						local c = curSpecCfg()
						return c and c.absorbEnabled ~= false
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.absorbEnabled = value and true or false
						queueRefresh()
					end,
					default = true,
				}

				settingsList[#settingsList + 1] = {
					name = L["Use custom absorb color"] or "Use custom absorb color",
					kind = settingType.CheckboxColor,
					field = "absorbUseCustomColor",
					parentId = "absorb",
					default = false,
					get = function()
						local c = curSpecCfg()
						return c and c.absorbUseCustomColor == true
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.absorbUseCustomColor = value and true or false
						queueRefresh()
					end,
					colorDefault = toUIColor(cfg and cfg.absorbColor, absorbDefaultColor),
					colorGet = function()
						local c = curSpecCfg()
						local col = (c and c.absorbColor) or (cfg and cfg.absorbColor) or absorbDefaultColor
						local r, g, b, a = toColorComponents(col, absorbDefaultColor)
						return { r = r, g = g, b = b, a = a }
					end,
					colorSet = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.absorbColor = toColorArray(value, absorbDefaultColor)
						c.absorbUseCustomColor = true
						queueRefresh()
					end,
					hasOpacity = true,
				}

				settingsList[#settingsList + 1] = {
					name = L["Absorb texture"] or "Absorb texture",
					kind = settingType.Dropdown,
					height = 180,
					field = "absorbTexture",
					parentId = "absorb",
					generator = function(dropdown, root)
						local listTex, orderTex = addon.Aura.functions.getStatusbarDropdownLists(true)
						if not listTex or not orderTex then
							listTex, orderTex = { DEFAULT = DEFAULT }, { "DEFAULT" }
						end
						if not listTex or not orderTex then return end
						ensureDropdownTexturePreview(dropdown)
						for index, key in ipairs(orderTex) do
							local label = listTex[key] or key
							local previewIndex = index
							local previewPath = resolveStatusbarPreviewPath(key)
							local checkbox = root:CreateCheckbox(label, function()
								local c = curSpecCfg()
								local cur = c and c.absorbTexture or cfg.absorbTexture or cfg.barTexture or "DEFAULT"
								return cur == key
							end, function()
								local c = curSpecCfg()
								if not c then return end
								local cur = c.absorbTexture or cfg.absorbTexture or cfg.barTexture or "DEFAULT"
								if cur == key then return end
								c.absorbTexture = key
								queueRefresh()
							end)
							if previewPath then checkbox:AddInitializer(function(button) attachDropdownTexturePreview(dropdown, button, previewIndex, previewPath) end) end
						end
					end,
					get = function()
						local c = curSpecCfg()
						return (c and c.absorbTexture) or cfg.absorbTexture or cfg.barTexture or "DEFAULT"
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.absorbTexture = value
						queueRefresh()
					end,
					default = cfg and (cfg.absorbTexture or cfg.barTexture) or "DEFAULT",
				}

				settingsList[#settingsList + 1] = {
					name = L["Reverse absorb fill"] or "Reverse absorb fill",
					kind = settingType.Checkbox,
					field = "absorbReverseFill",
					parentId = "absorb",
					get = function()
						local c = curSpecCfg()
						return c and c.absorbReverseFill == true
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.absorbReverseFill = value and true or false
						if c.absorbReverseFill then c.absorbOverfill = false end
						queueRefresh()
						refreshSettingsUI()
					end,
					default = false,
				}

				settingsList[#settingsList + 1] = {
					name = L["Absorb overfill"] or "Absorb overfill",
					kind = settingType.Checkbox,
					field = "absorbOverfill",
					parentId = "absorb",
					get = function()
						local c = curSpecCfg()
						return c and c.absorbOverfill == true
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.absorbOverfill = value and true or false
						if c.absorbOverfill then c.absorbReverseFill = false end
						queueRefresh()
						refreshSettingsUI()
					end,
					default = false,
				}

				settingsList[#settingsList + 1] = {
					name = L["Show sample absorb"] or "Show sample absorb",
					kind = settingType.Checkbox,
					field = "absorbSample",
					parentId = "absorb",
					get = function()
						local c = curSpecCfg()
						return c and c.absorbSample == true
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.absorbSample = value and true or false
						queueRefresh()
					end,
					default = false,
				}
			end

			settingsList[#settingsList + 1] = {
				name = LOCALE_TEXT_LABEL or L["Text"] or STATUS_TEXT,
				kind = settingType.Collapsible,
				id = "textsettings",
				defaultCollapsed = true,
			}

			if barType == "RUNES" then
				settingsList[#settingsList + 1] = {
					name = L["Show cooldown text"] or "Show cooldown text",
					kind = settingType.Checkbox,
					field = "showCooldownText",
					parentId = "textsettings",
					get = function()
						local class, specIndex = addon.variables.unitClass, addon.variables.unitSpec
						local specCfg = addon.db.personalResourceBarSettings[class][specIndex]

						return addon.db.personalResourceBarSettings[class][specIndex].RUNES.showCooldownText
					end,
					set = function(_, value)
						local class, specIndex = addon.variables.unitClass, addon.variables.unitSpec
						local specCfg = addon.db.personalResourceBarSettings[class][specIndex]

						addon.db.personalResourceBarSettings[class][specIndex].RUNES.showCooldownText = value and true or false
						queueRefresh()
					end,
					default = true,
				}

				settingsList[#settingsList + 1] = {
					name = L["Cooldown Text Size"] or "Cooldown Text Size",
					kind = settingType.Slider,
					allowInput = true,
					field = "cooldownTextFontSize",
					minValue = 6,
					maxValue = 64,
					valueStep = 1,
					parentId = "textsettings",
					get = function()
						local c = curSpecCfg()
						return c and c.cooldownTextFontSize or 16
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						if not setIfChanged(c, "cooldownTextFontSize", value) then return end
						queueRefresh()
					end,
					default = 16,
				}

				settingsList[#settingsList + 1] = {
					name = L["Font"] or "Font",
					kind = settingType.DropdownColor,
					height = 180,
					field = "fontFace",
					parentId = "textsettings",
					generator = function(_, root)
						local function currentFontPath()
							local c = curSpecCfg()
							return (c and c.fontFace) or cfg.fontFace or addon.variables.defaultFont
						end
						local currentPath = currentFontPath()
						local seen = {}
						if not LibStub then return end
						local media = LibStub("LibSharedMedia-3.0", true)
						if not media then return end
						local hash = media:HashTable("font") or {}
						for _, name in ipairs(media:List("font") or {}) do
							local path = hash[name] or name
							seen[path] = name
							root:CreateCheckbox(name, function() return currentFontPath() == path end, function()
								local c = curSpecCfg()
								if not c then return end
								if currentFontPath() == path then return end
								c.fontFace = path
								queueRefresh()
							end)
						end
						if currentPath and not seen[currentPath] then
							local label = tostring(currentPath)
							root:CreateCheckbox(label, function() return currentFontPath() == currentPath end, function()
								local c = curSpecCfg()
								if not c then return end
								if currentFontPath() == currentPath then return end
								c.fontFace = currentPath
								queueRefresh()
							end)
						end
					end,
					get = function()
						local c = curSpecCfg()
						return (c and c.fontFace) or cfg.fontFace or addon.variables.defaultFont
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.fontFace = value
						queueRefresh()
					end,
					colorDefault = { r = 1, g = 1, b = 1, a = 1 },
					colorGet = function()
						local c = curSpecCfg()
						local col = (c and c.fontColor) or (cfg and cfg.fontColor) or { 1, 1, 1, 1 }
						local r, g, b, a = toColorComponents(col, { 1, 1, 1, 1 })
						return { r = r, g = g, b = b, a = a }
					end,
					colorSet = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.fontColor = toColorArray(value, { 1, 1, 1, 1 })
						queueRefresh()
					end,
					hasOpacity = true,
					default = addon.variables.defaultFont,
				}

				local outlineOptions = {
					{ key = "NONE", label = NONE },
					{ key = "OUTLINE", label = "Outline" },
					{ key = "THICKOUTLINE", label = "Thick Outline" },
					{ key = "MONOCHROMEOUTLINE", label = "Mono Outline" },
				}
				settingsList[#settingsList + 1] = {
					name = L["Outline"],
					kind = settingType.Dropdown,
					height = 180,
					field = "fontOutline",
					parentId = "textsettings",
					generator = function(_, root)
						for _, entry in ipairs(outlineOptions) do
							root:CreateCheckbox(entry.label, function()
								local c = curSpecCfg()
								local cur = (c and c.fontOutline) or cfg.fontOutline or "OUTLINE"
								return cur == entry.key
							end, function()
								local c = curSpecCfg()
								if not c then return end
								local cur = (c and c.fontOutline) or cfg.fontOutline or "OUTLINE"
								if cur == entry.key then return end
								c.fontOutline = entry.key
								queueRefresh()
							end)
						end
					end,
					get = function()
						local c = curSpecCfg()
						return (c and c.fontOutline) or cfg.fontOutline or "OUTLINE"
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.fontOutline = value
						queueRefresh()
					end,
					default = "OUTLINE",
				}
			end

			if barType ~= "RUNES" then
				local function defaultStyle()
					if barType == "HEALTH" then return "PERCENT" end
					if barType == "MANA" or barType == "STAGGER" then return "PERCENT" end
					return "CURMAX"
				end
				local textOptions = {
					{ key = "PERCENT", label = STATUS_TEXT_PERCENT },
					{ key = "CURMAX", label = L["Current/Max"] or "Current/Max" },
					{ key = "CURRENT", label = L["Current"] or "Current" },
					{ key = "NONE", label = NONE },
				}
				settingsList[#settingsList + 1] = {
					name = L["Text"] or STATUS_TEXT,
					kind = settingType.Dropdown,
					height = 180,
					field = "textStyle",
					parentId = "textsettings",
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
					generator = function(_, root)
						for _, entry in ipairs(textOptions) do
							root:CreateRadio(entry.label, function()
								local c = curSpecCfg()
								return ((c and c.textStyle) or defaultStyle()) == entry.key
							end, function()
								local c = curSpecCfg()
								if not c then return end
								c.textStyle = entry.key
								queueRefresh()
							end)
						end
					end,
					default = defaultStyle(),
				}

				settingsList[#settingsList + 1] = {
					name = L["Use short numbers"] or "Use short numbers",
					kind = settingType.Checkbox,
					field = "shortNumbers",
					parentId = "textsettings",
					get = function()
						local c = curSpecCfg()
						return (not c) or c.shortNumbers ~= false
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.shortNumbers = value and true or false
						queueRefresh()
					end,
					default = true,
				}

				local roundingOptions = {
					{ key = "ROUND", label = L["Round to nearest"] or "Round to nearest" },
					{ key = "FLOOR", label = L["Round down"] or "Round down" },
				}
				settingsList[#settingsList + 1] = {
					name = L["Percent rounding"] or "Percent rounding",
					kind = settingType.Dropdown,
					height = 120,
					field = "percentRounding",
					parentId = "textsettings",
					get = function()
						local c = curSpecCfg()
						return (c and c.percentRounding) or "ROUND"
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.percentRounding = value
						queueRefresh()
					end,
					generator = function(_, root)
						for _, entry in ipairs(roundingOptions) do
							root:CreateRadio(entry.label, function()
								local c = curSpecCfg()
								return ((c and c.percentRounding) or "ROUND") == entry.key
							end, function()
								local c = curSpecCfg()
								if not c then return end
								c.percentRounding = entry.key
								queueRefresh()
							end)
						end
					end,
					default = "ROUND",
				}

				settingsList[#settingsList + 1] = {
					name = L["Hide percent (%)"] or "Hide percent (%)",
					kind = settingType.Checkbox,
					field = "hidePercentSign",
					parentId = "textsettings",
					get = function()
						local c = curSpecCfg()
						return c and c.hidePercentSign == true
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.hidePercentSign = value and true or false
						queueRefresh()
					end,
					default = false,
				}

				settingsList[#settingsList + 1] = {
					name = HUD_EDIT_MODE_SETTING_OBJECTIVE_TRACKER_TEXT_SIZE,
					kind = settingType.Slider,
					allowInput = true,
					field = "fontSize",
					minValue = 6,
					maxValue = 64,
					valueStep = 1,
					parentId = "textsettings",
					get = function()
						local c = curSpecCfg()
						return c and c.fontSize or 16
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						if not setIfChanged(c, "fontSize", value) then return end
						queueRefresh()
					end,
					default = 16,
				}

				settingsList[#settingsList + 1] = {
					name = L["Text X Offset"] or "Text Offset X",
					kind = settingType.Slider,
					allowInput = true,
					field = "textOffsetX",
					minValue = -500,
					maxValue = 500,
					valueStep = 1,
					parentId = "textsettings",
					get = function()
						local c = curSpecCfg()
						local off = c and c.textOffset
						return off and off.x or 0
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.textOffset = c.textOffset or { x = 0, y = 0 }
						local new = value or 0
						if c.textOffset.x == new then return end
						c.textOffset.x = new
						queueRefresh()
					end,
					default = 0,
				}

				settingsList[#settingsList + 1] = {
					name = L["Text Y Offset"] or "Text Offset Y",
					kind = settingType.Slider,
					allowInput = true,
					field = "textOffsetY",
					minValue = -500,
					maxValue = 500,
					valueStep = 1,
					parentId = "textsettings",
					get = function()
						local c = curSpecCfg()
						local off = c and c.textOffset
						return off and off.y or 0
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.textOffset = c.textOffset or { x = 0, y = 0 }
						local new = value or 0
						if c.textOffset.y == new then return end
						c.textOffset.y = new
						queueRefresh()
					end,
					default = 0,
				}

				settingsList[#settingsList + 1] = {
					name = L["Font"] or "Font",
					kind = settingType.DropdownColor,
					height = 180,
					field = "fontFace",
					parentId = "textsettings",
					generator = function(_, root)
						local function currentFontPath()
							local c = curSpecCfg()
							return (c and c.fontFace) or cfg.fontFace or addon.variables.defaultFont
						end
						local currentPath = currentFontPath()
						local seen = {}
						if not LibStub then return end
						local media = LibStub("LibSharedMedia-3.0", true)
						if not media then return end
						local hash = media:HashTable("font") or {}
						for _, name in ipairs(media:List("font") or {}) do
							local path = hash[name] or name
							seen[path] = name
							root:CreateCheckbox(name, function() return currentFontPath() == path end, function()
								local c = curSpecCfg()
								if not c then return end
								if currentFontPath() == path then return end
								c.fontFace = path
								queueRefresh()
							end)
						end
						if currentPath and not seen[currentPath] then
							local label = tostring(currentPath)
							root:CreateCheckbox(label, function() return currentFontPath() == currentPath end, function()
								local c = curSpecCfg()
								if not c then return end
								if currentFontPath() == currentPath then return end
								c.fontFace = currentPath
								queueRefresh()
							end)
						end
					end,
					get = function()
						local c = curSpecCfg()
						return (c and c.fontFace) or cfg.fontFace or addon.variables.defaultFont
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.fontFace = value
						queueRefresh()
					end,
					colorDefault = { r = 1, g = 1, b = 1, a = 1 },
					colorGet = function()
						local c = curSpecCfg()
						local col = (c and c.fontColor) or (cfg and cfg.fontColor) or { 1, 1, 1, 1 }
						local r, g, b, a = toColorComponents(col, { 1, 1, 1, 1 })
						return { r = r, g = g, b = b, a = a }
					end,
					colorSet = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.fontColor = toColorArray(value, { 1, 1, 1, 1 })
						queueRefresh()
					end,
					hasOpacity = true,
					default = addon.variables.defaultFont,
				}

				local outlineOptions = {
					{ key = "NONE", label = NONE },
					{ key = "OUTLINE", label = "Outline" },
					{ key = "THICKOUTLINE", label = "Thick Outline" },
					{ key = "MONOCHROMEOUTLINE", label = "Mono Outline" },
				}
				settingsList[#settingsList + 1] = {
					name = L["Outline"],
					kind = settingType.Dropdown,
					height = 180,
					field = "fontOutline",
					parentId = "textsettings",
					generator = function(_, root)
						for _, entry in ipairs(outlineOptions) do
							root:CreateCheckbox(entry.label, function()
								local c = curSpecCfg()
								local cur = (c and c.fontOutline) or cfg.fontOutline or "OUTLINE"
								return cur == entry.key
							end, function()
								local c = curSpecCfg()
								if not c then return end
								local cur = (c and c.fontOutline) or cfg.fontOutline or "OUTLINE"
								if cur == entry.key then return end
								c.fontOutline = entry.key
								queueRefresh()
							end)
						end
					end,
					get = function()
						local c = curSpecCfg()
						return (c and c.fontOutline) or cfg.fontOutline or "OUTLINE"
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.fontOutline = value
						queueRefresh()
					end,
					default = "OUTLINE",
				}
			end

			do -- Global profile helpers
				local function syncSizeFromConfig()
					local c = curSpecCfg()
					if not c then return end
					local w = c.width or widthDefault or 200
					local h = c.height or heightDefault or 20
					if EditMode and EditMode.SetValue and frameId then
						EditMode:SetValue(frameId, "width", w, nil, true)
						EditMode:SetValue(frameId, "height", h, nil, true)
					end
					if barType == "HEALTH" then
						ResourceBars.SetHealthBarSize(w, h)
					else
						ResourceBars.SetPowerBarSize(w, h, barType)
					end
				end

				local function saveGlobal(targetKey, label)
					local specInfo = currentSpecInfo()
					if ResourceBars.SaveGlobalProfile then
						confirmSaveGlobal(targetKey, function()
							local ok = ResourceBars.SaveGlobalProfile(barType, addon.variables.unitSpec, targetKey)
							if ok then
								if targetKey == "MAIN" or (not targetKey and specInfo and specInfo.MAIN == barType) then
									notify(L["SavedGlobalMainProfile"] or "Saved global main profile")
								else
									notify((L["SavedGlobalProfile"] or "Saved global profile for %s"):format(label or titleLabel))
								end
							else
								notify(L["GlobalProfileSaveFailed"] or "Could not save global profile.")
							end
						end)
					end
				end

				local function applyGlobal(targetKey, label)
					local specInfo = currentSpecInfo()
					if ResourceBars.ApplyGlobalProfile then
						local ok, reason = ResourceBars.ApplyGlobalProfile(barType, addon.variables.unitSpec, nil, targetKey)
						if ok then
							syncSizeFromConfig()
							queueRefresh()
							refreshSettingsUI()
							if targetKey == "MAIN" or (not targetKey and specInfo and specInfo.MAIN == barType) then
								notify(L["AppliedGlobalMainProfile"] or "Applied global main profile")
							else
								notify((L["AppliedGlobalProfile"] or "Applied global profile for %s"):format(label or titleLabel))
							end
						else
							if reason == "NO_GLOBAL" then
								notify(L["GlobalProfileMissing"] or "No global profile saved for this bar.")
							else
								notify(L["GlobalProfileApplyFailed"] or "Could not apply global profile.")
							end
						end
					end
				end

				local function globalProfileOptions()
					local opts = {}
					local specInfo = currentSpecInfo()
					local isMain = specInfo and specInfo.MAIN == barType
					local powerLabel = titleLabel
					if isMain then opts[#opts + 1] = { label = L["UseAsGlobalMainProfile"] or "Use as global main profile", action = function() saveGlobal("MAIN", powerLabel) end } end
					opts[#opts + 1] = { label = (L["UseAsGlobalProfile"] or "Use as global %s profile"):format(powerLabel), action = function() saveGlobal(barType, powerLabel) end }
					opts[#opts + 1] = { label = L["ApplyGlobalMainProfile"] or "Apply global main profile", action = function() applyGlobal("MAIN", powerLabel) end }
					opts[#opts + 1] = { label = (L["ApplyGlobalProfile"] or "Apply global %s profile"):format(powerLabel), action = function() applyGlobal(barType, powerLabel) end }
					return opts
				end

				table.insert(settingsList, 1, {
					name = SETTINGS or L["Settings"] or "Settings",
					kind = settingType.Collapsible,
					id = "profiles",
					defaultCollapsed = true,
				})

				table.insert(settingsList, 2, {
					name = SETTINGS or L["Settings"] or "Settings",
					kind = settingType.Dropdown,
					height = 180,
					hideSummary = true,
					parentId = "profiles",
					generator = function(_, root)
						for _, opt in ipairs(globalProfileOptions()) do
							root:CreateRadio(opt.label, function() return false end, opt.action)
						end
					end,
				})
			end

			if barType ~= "STAGGER" then
				settingsList[#settingsList + 1] = {
					name = COLOR,
					kind = settingType.Collapsible,
					id = "colorsetting",
					defaultCollapsed = true,
				}

				settingsList[#settingsList + 1] = {
					name = L["Custom bar color"] or "Custom bar color",
					kind = settingType.CheckboxColor,
					field = "useBarColor",
					default = false,
					get = function()
						local c = curSpecCfg()
						return c and c.useBarColor == true
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.useBarColor = value and true or false
						if c.useBarColor and c.useClassColor then c.useClassColor = false end
						queueRefresh()
						addon.EditModeLib.internal:RefreshSettings()
					end,
					colorDefault = toUIColor(cfg and cfg.barColor, { 1, 1, 1, 1 }),
					colorGet = function()
						local c = curSpecCfg()
						local col = (c and c.barColor) or (cfg and cfg.barColor) or { 1, 1, 1, 1 }
						local r, g, b, a = toColorComponents(col, { 1, 1, 1, 1 })
						return { r = r, g = g, b = b, a = a }
					end,
					colorSet = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.barColor = toColorArray(value, { 1, 1, 1, 1 })
						queueRefresh()
					end,
					isEnabled = function()
						local c = curSpecCfg()
						return not (c and c.useClassColor == true)
					end,
					hasOpacity = true,
					parentId = "colorsetting",
				}

				if barType ~= "RUNES" then
					settingsList[#settingsList + 1] = {
						name = L["Use class color"] or "Use class color",
						kind = settingType.Checkbox,
						field = "useClassColor",
						get = function()
							local c = curSpecCfg()
							return c and c.useClassColor == true
						end,
						set = function(_, value)
							local c = curSpecCfg()
							if not c then return end
							c.useClassColor = value and true or false
							if c.useClassColor and c.useBarColor then c.useBarColor = false end
							queueRefresh()
							addon.EditModeLib.internal:RefreshSettings()
						end,
						isEnabled = function()
							local c = curSpecCfg()
							return not (c and c.useBarColor == true)
						end,
						hasOpacity = true,
						default = false,
						parentId = "colorsetting",
					}
				end

				settingsList[#settingsList + 1] = {
					name = L["Use gradient"] or "Use gradient",
					kind = settingType.Checkbox,
					field = "useGradient",
					get = function()
						local c = curSpecCfg()
						return c and c.useGradient == true
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.useGradient = value and true or false
						queueRefresh()
						refreshSettingsUI()
					end,
					default = false,
					parentId = "colorsetting",
				}

				settingsList[#settingsList + 1] = {
					name = L["Gradient start color"] or "Gradient start color",
					kind = settingType.Color,
					parentId = "colorsetting",
					get = function()
						local c = curSpecCfg()
						return toUIColor((c and c.gradientStartColor) or (cfg and cfg.gradientStartColor) or { 1, 1, 1, 1 }, { 1, 1, 1, 1 })
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.gradientStartColor = toColorArray(value, { 1, 1, 1, 1 })
						queueRefresh()
					end,
					default = { r = 1, g = 1, b = 1, a = 1 },
					hasOpacity = true,
					isEnabled = function()
						local c = curSpecCfg()
						return c and c.useGradient == true
					end,
				}

				settingsList[#settingsList + 1] = {
					name = L["Gradient end color"] or "Gradient end color",
					kind = settingType.Color,
					parentId = "colorsetting",
					get = function()
						local c = curSpecCfg()
						return toUIColor((c and c.gradientEndColor) or (cfg and cfg.gradientEndColor) or { 1, 1, 1, 1 }, { 1, 1, 1, 1 })
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.gradientEndColor = toColorArray(value, { 1, 1, 1, 1 })
						queueRefresh()
					end,
					default = { r = 1, g = 1, b = 1, a = 1 },
					hasOpacity = true,
					isEnabled = function()
						local c = curSpecCfg()
						return c and c.useGradient == true
					end,
				}

				settingsList[#settingsList + 1] = {
					name = L["Gradient direction"] or "Gradient direction",
					kind = settingType.Dropdown,
					height = 80,
					field = "gradientDirection",
					parentId = "colorsetting",
					generator = function(_, root)
						local function getDir()
							local c = curSpecCfg()
							local v = (c and c.gradientDirection) or (cfg and cfg.gradientDirection) or "VERTICAL"
							if type(v) == "string" then v = v:upper() end
							return v == "HORIZONTAL" and "HORIZONTAL" or "VERTICAL"
						end
						local function setDir(value)
							local c = curSpecCfg()
							if not c then return end
							c.gradientDirection = value == "HORIZONTAL" and "HORIZONTAL" or "VERTICAL"
							queueRefresh()
						end
						root:CreateRadio(L["Vertical"] or "Vertical", function() return getDir() == "VERTICAL" end, function() setDir("VERTICAL") end)
						root:CreateRadio(L["Horizontal"] or "Horizontal", function() return getDir() == "HORIZONTAL" end, function() setDir("HORIZONTAL") end)
					end,
					get = function()
						local c = curSpecCfg()
						local v = (c and c.gradientDirection) or (cfg and cfg.gradientDirection) or "VERTICAL"
						if type(v) == "string" then v = v:upper() end
						return v == "HORIZONTAL" and "HORIZONTAL" or "VERTICAL"
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						if type(value) == "string" then value = value:upper() end
						c.gradientDirection = value == "HORIZONTAL" and "HORIZONTAL" or "VERTICAL"
						queueRefresh()
					end,
					default = "VERTICAL",
					isEnabled = function()
						local c = curSpecCfg()
						return c and c.useGradient == true
					end,
				}

				if barType == "RUNES" then
					settingsList[#settingsList + 1] = {
						name = L["Rune cooldown color"] or "Rune cooldown color",
						kind = settingType.Color,
						parentId = "colorsetting",
						get = function()
							local c = curSpecCfg()
							return toUIColor((c and c.runeCooldownColor) or (cfg and cfg.runeCooldownColor) or { 0.35, 0.35, 0.35, 1 }, { 0.35, 0.35, 0.35, 1 })
						end,
						set = function(_, value)
							local c = curSpecCfg()
							if not c then return end
							c.runeCooldownColor = toColorArray(value, { 0.35, 0.35, 0.35, 1 })
							queueRefresh()
						end,
						default = { r = 0.35, g = 0.35, b = 0.35, a = 1 },
						hasOpacity = true,
					}
				end

				if barType == "HOLY_POWER" then
					settingsList[#settingsList + 1] = {
						name = L["Use 3 HP color"] or "Use custom color at 3 Holy Power",
						kind = settingType.CheckboxColor,
						field = "useHolyThreeColor",
						default = false,
						get = function()
							local c = curSpecCfg()
							return c and c.useHolyThreeColor == true
						end,
						set = function(_, value)
							local c = curSpecCfg()
							if not c then return end
							c.useHolyThreeColor = value and true or false
							queueRefresh()
						end,
						colorDefault = toUIColor(cfg and cfg.holyThreeColor, { 1, 0.8, 0.2, 1 }),
						colorGet = function()
							local c = curSpecCfg()
							local col = (c and c.holyThreeColor) or (cfg and cfg.holyThreeColor) or { 1, 0.8, 0.2, 1 }
							local r, g, b, a = toColorComponents(col, { 1, 0.8, 0.2, 1 })
							return { r = r, g = g, b = b, a = a }
						end,
						colorSet = function(_, value)
							local c = curSpecCfg()
							if not c then return end
							c.holyThreeColor = toColorArray(value, { 1, 0.8, 0.2, 1 })
							queueRefresh()
						end,
						hasOpacity = true,
						parentId = "colorsetting",
					}
				end

				if barType == "MAELSTROM_WEAPON" then
					settingsList[#settingsList + 1] = {
						name = "Use 5-stack color",
						kind = settingType.CheckboxColor,
						field = "useMaelstromFiveColor",
						default = true,
						get = function()
							local c = curSpecCfg()
							return c and c.useMaelstromFiveColor ~= false
						end,
						set = function(_, value)
							local c = curSpecCfg()
							if not c then return end
							c.useMaelstromFiveColor = value and true or false
							queueRefresh()
						end,
						colorDefault = toUIColor(cfg and cfg.maelstromFiveColor, { 0.2, 0.7, 1, 1 }),
						colorGet = function()
							local c = curSpecCfg()
							local col = (c and c.maelstromFiveColor) or (cfg and cfg.maelstromFiveColor) or { 0.2, 0.7, 1, 1 }
							local r, g, b, a = toColorComponents(col, { 0.2, 0.7, 1, 1 })
							return { r = r, g = g, b = b, a = a }
						end,
						colorSet = function(_, value)
							local c = curSpecCfg()
							if not c then return end
							c.maelstromFiveColor = toColorArray(value, { 0.2, 0.7, 1, 1 })
							queueRefresh()
						end,
						hasOpacity = true,
						parentId = "colorsetting",
					}
				end

				settingsList[#settingsList + 1] = {
					name = L["Use max color"] or "Use max color",
					kind = settingType.CheckboxColor,
					field = "useMaxColor",
					default = barType == "MAELSTROM_WEAPON",
					get = function()
						local c = curSpecCfg()
						return c and c.useMaxColor == true
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.useMaxColor = value and true or false
						queueRefresh()
					end,
					colorDefault = toUIColor(cfg and cfg.maxColor, { 0, 1, 0, 1 }),
					colorGet = function()
						local c = curSpecCfg()
						local col = (c and c.maxColor) or (cfg and cfg.maxColor) or { 0, 1, 0, 1 }
						local r, g, b, a = toColorComponents(col, { 0, 1, 0, 1 })
						return { r = r, g = g, b = b, a = a }
					end,
					colorSet = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.maxColor = toColorArray(value, { 0, 1, 0, 1 })
						queueRefresh()
					end,
					hasOpacity = true,
					parentId = "colorsetting",
				}
			end

			if barType == "STAGGER" then
				settingsList[#settingsList + 1] = {
					name = L["Stagger colors"] or "Stagger colors",
					kind = settingType.Collapsible,
					id = "staggercolors",
					defaultCollapsed = true,
				}

				settingsList[#settingsList + 1] = {
					name = L["Use extended stagger colors"] or "Use extended stagger colors",
					kind = settingType.Checkbox,
					field = "staggerHighColors",
					parentId = "staggercolors",
					get = function()
						local c = curSpecCfg()
						return c and c.staggerHighColors == true
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.staggerHighColors = value and true or false
						queueRefresh()
					end,
					default = false,
				}

				settingsList[#settingsList + 1] = {
					name = L["Stagger high threshold"] or "Stagger high threshold (%)",
					kind = settingType.Slider,
					allowInput = true,
					field = "staggerHighThreshold",
					minValue = 100,
					maxValue = 1000,
					valueStep = 10,
					parentId = "staggercolors",
					get = function()
						local c = curSpecCfg()
						return (c and c.staggerHighThreshold) or STAGGER_EXTRA_THRESHOLD_HIGH
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.staggerHighThreshold = value
						queueRefresh()
					end,
					default = STAGGER_EXTRA_THRESHOLD_HIGH,
					isEnabled = function()
						local c = curSpecCfg()
						return c and c.staggerHighColors == true
					end,
				}

				settingsList[#settingsList + 1] = {
					name = L["Stagger high color"] or "Stagger high color",
					kind = settingType.Color,
					parentId = "staggercolors",
					get = function()
						local c = curSpecCfg()
						return toUIColor((c and c.staggerHighColor) or (STAGGER_EXTRA_COLORS and STAGGER_EXTRA_COLORS.high) or { 0.62, 0.2, 1, 1 }, { 0.62, 0.2, 1, 1 })
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.staggerHighColor = toColorArray(value, (STAGGER_EXTRA_COLORS and STAGGER_EXTRA_COLORS.high) or { 0.62, 0.2, 1, 1 })
						queueRefresh()
					end,
					default = { r = 0.62, g = 0.2, b = 1, a = 1 },
					hasOpacity = true,
					isEnabled = function()
						local c = curSpecCfg()
						return c and c.staggerHighColors == true
					end,
				}

				settingsList[#settingsList + 1] = {
					name = L["Stagger extreme threshold"] or "Stagger extreme threshold (%)",
					kind = settingType.Slider,
					allowInput = true,
					field = "staggerExtremeThreshold",
					minValue = 100,
					maxValue = 1000,
					valueStep = 10,
					parentId = "staggercolors",
					get = function()
						local c = curSpecCfg()
						return (c and c.staggerExtremeThreshold) or STAGGER_EXTRA_THRESHOLD_EXTREME
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.staggerExtremeThreshold = value
						queueRefresh()
					end,
					default = STAGGER_EXTRA_THRESHOLD_EXTREME,
					isEnabled = function()
						local c = curSpecCfg()
						return c and c.staggerHighColors == true
					end,
				}

				settingsList[#settingsList + 1] = {
					name = L["Stagger extreme color"] or "Stagger extreme color",
					kind = settingType.Color,
					parentId = "staggercolors",
					get = function()
						local c = curSpecCfg()
						return toUIColor((c and c.staggerExtremeColor) or (STAGGER_EXTRA_COLORS and STAGGER_EXTRA_COLORS.extreme) or { 1, 0.2, 0.8, 1 }, { 1, 0.2, 0.8, 1 })
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						c.staggerExtremeColor = toColorArray(value, (STAGGER_EXTRA_COLORS and STAGGER_EXTRA_COLORS.extreme) or { 1, 0.2, 0.8, 1 })
						queueRefresh()
					end,
					default = { r = 1, g = 0.2, b = 0.8, a = 1 },
					hasOpacity = true,
					isEnabled = function()
						local c = curSpecCfg()
						return c and c.staggerHighColors == true
					end,
				}
			end

			do -- Backdrop
				local function backdropEnabled()
					local c = curSpecCfg()
					local bd = ensureBackdropTable(c)
					return not (bd and bd.enabled == false)
				end

				settingsList[#settingsList + 1] = {
					name = "Backdrop",
					kind = settingType.Collapsible,
					id = "CheckboxGroup",
					defaultCollapsed = true,
				}

				settingsList[#settingsList + 1] = {
					parentId = "CheckboxGroup",
					name = L["Show backdrop"] or "Show backdrop",
					kind = settingType.Checkbox,
					field = "backdropEnabled",
					get = function()
						local c = curSpecCfg()
						local bd = ensureBackdropTable(c)
						return bd and bd.enabled ~= false
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						local bd = ensureBackdropTable(c)
						bd.enabled = value and true or false
						queueRefresh()
						if addon.EditModeLib and addon.EditModeLib.internal then addon.EditModeLib.internal:RefreshSettings() end
					end,
					default = cfg and cfg.backdrop and cfg.backdrop.enabled ~= false,
				}

				settingsList[#settingsList + 1] = {
					parentId = "CheckboxGroup",
					name = L["Background texture"],
					kind = settingType.DropdownColor,
					height = 180,
					field = "backdropBackground",
					generator = function(_, root)
						local list, order = backgroundDropdownData()
						if not list or not order then return end
						for _, key in ipairs(order) do
							local label = list[key] or key
							root:CreateCheckbox(label, function()
								local c = curSpecCfg()
								local bd = ensureBackdropTable(c)
								return bd and bd.backgroundTexture == key
							end, function()
								local c = curSpecCfg()
								if not c then return end
								local bd = ensureBackdropTable(c)
								if bd and bd.backgroundTexture == key then return end
								bd.backgroundTexture = key
								queueRefresh()
							end)
						end
					end,
					get = function()
						local c = curSpecCfg()
						local bd = ensureBackdropTable(c)
						return bd and bd.backgroundTexture or (cfg and cfg.backdrop and cfg.backdrop.backgroundTexture) or "Interface\\DialogFrame\\UI-DialogBox-Background"
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						local bd = ensureBackdropTable(c)
						bd.backgroundTexture = value
						queueRefresh()
					end,
					colorDefault = toUIColor(cfg and cfg.backdrop and cfg.backdrop.backgroundColor, { 0, 0, 0, 0.8 }),
					colorGet = function()
						local c = curSpecCfg()
						local bd = ensureBackdropTable(c)
						local col = bd and bd.backgroundColor or { 0, 0, 0, 0.8 }
						local r, g, b, a = toColorComponents(col, { 0, 0, 0, 0.8 })
						return { r = r, g = g, b = b, a = a }
					end,
					colorSet = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						local bd = ensureBackdropTable(c)
						bd.backgroundColor = toColorArray(value, { 0, 0, 0, 0.8 })
						queueRefresh()
					end,
					hasOpacity = true,
					isEnabled = backdropEnabled,
					default = (cfg and cfg.backdrop and cfg.backdrop.backgroundTexture) or "Interface\\DialogFrame\\UI-DialogBox-Background",
				}

				settingsList[#settingsList + 1] = {
					parentId = "CheckboxGroup",
					name = L["Border texture"],
					kind = settingType.DropdownColor,
					height = 180,
					field = "backdropBorder",
					generator = function(_, root)
						local list, order = borderDropdownData()
						if not list or not order then return end
						for _, key in ipairs(order) do
							local label = list[key] or key
							root:CreateCheckbox(label, function()
								local c = curSpecCfg()
								local bd = ensureBackdropTable(c)
								return bd and bd.borderTexture == key
							end, function()
								local c = curSpecCfg()
								if not c then return end
								local bd = ensureBackdropTable(c)
								if bd and bd.borderTexture == key then return end
								if customBorderOptions() and customBorderOptions()[key] then
									local col = bd.borderColor
									if not col or (col[4] or 0) <= 0 then bd.borderColor = { 1, 1, 1, 1 } end
								end
								bd.borderTexture = key
								queueRefresh()
							end)
						end
					end,
					get = function()
						local c = curSpecCfg()
						local bd = ensureBackdropTable(c)
						return bd and bd.borderTexture or (cfg and cfg.backdrop and cfg.backdrop.borderTexture) or "Interface\\Tooltips\\UI-Tooltip-Border"
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						local bd = ensureBackdropTable(c)
						if customBorderOptions() and customBorderOptions()[value] then
							local col = bd.borderColor
							if not col or (col[4] or 0) <= 0 then bd.borderColor = { 1, 1, 1, 1 } end
						end
						bd.borderTexture = value
						queueRefresh()
					end,
					colorDefault = toUIColor(cfg and cfg.backdrop and cfg.backdrop.borderColor, { 0, 0, 0, 0 }),
					colorGet = function()
						local c = curSpecCfg()
						local bd = ensureBackdropTable(c)
						local col = bd and bd.borderColor or { 0, 0, 0, 0 }
						local r, g, b, a = toColorComponents(col, { 0, 0, 0, 0 })
						return { r = r, g = g, b = b, a = a }
					end,
					colorSet = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						local bd = ensureBackdropTable(c)
						bd.borderColor = toColorArray(value, { 0, 0, 0, 0 })
						queueRefresh()
					end,
					hasOpacity = true,
					isEnabled = backdropEnabled,
					default = (cfg and cfg.backdrop and cfg.backdrop.borderTexture) or "Interface\\Tooltips\\UI-Tooltip-Border",
				}

				settingsList[#settingsList + 1] = {
					parentId = "CheckboxGroup",
					name = L["Border size"] or "Border size",
					kind = settingType.Slider,
					allowInput = true,
					field = "backdropEdgeSize",
					minValue = 0,
					maxValue = 64,
					valueStep = 1,
					get = function()
						local c = curSpecCfg()
						local bd = ensureBackdropTable(c)
						return bd and bd.edgeSize or 3
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						local bd = ensureBackdropTable(c)
						bd.edgeSize = value or 0
						queueRefresh()
					end,
					default = (cfg and cfg.backdrop and cfg.backdrop.edgeSize) or 3,
					isEnabled = backdropEnabled,
				}

				settingsList[#settingsList + 1] = {
					parentId = "CheckboxGroup",
					name = L["Border offset"] or "Border offset",
					kind = settingType.Slider,
					allowInput = true,
					field = "backdropOutset",
					minValue = 0,
					maxValue = 64,
					valueStep = 1,
					get = function()
						local c = curSpecCfg()
						local bd = ensureBackdropTable(c)
						return bd and bd.outset or 0
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						local bd = ensureBackdropTable(c)
						bd.outset = value or 0
						queueRefresh()
					end,
					default = (cfg and cfg.backdrop and cfg.backdrop.outset) or 0,
					isEnabled = backdropEnabled,
				}

				settingsList[#settingsList + 1] = {
					parentId = "CheckboxGroup",
					name = L["Background inset"] or "Background inset",
					kind = settingType.Slider,
					allowInput = true,
					field = "backdropBackgroundInset",
					minValue = 0,
					maxValue = 128,
					valueStep = 1,
					get = function()
						local c = curSpecCfg()
						local bd = ensureBackdropTable(c)
						return bd and bd.backgroundInset or 0
					end,
					set = function(_, value)
						local c = curSpecCfg()
						if not c then return end
						local bd = ensureBackdropTable(c)
						bd.backgroundInset = max(0, value or 0)
						queueRefresh()
					end,
					default = (cfg and cfg.backdrop and cfg.backdrop.backgroundInset) or 0,
					isEnabled = backdropEnabled,
				}
			end
		end

		EditMode:RegisterFrame(frameId, {
			frame = frame,
			title = titleLabel,
			enableOverlayToggle = true,
			allowDrag = function() return anchorUsesUIParent() end,
			layoutDefaults = {
				point = anchor and anchor.point or "CENTER",
				relativePoint = anchor and anchor.relativePoint or "CENTER",
				x = anchor and anchor.x or 0,
				y = anchor and anchor.y or 0,
				width = cfg and cfg.width or widthDefault or frame:GetWidth() or 200,
				height = cfg and cfg.height or heightDefault or frame:GetHeight() or 20,
			},
			onApply = function(_, _, data)
				local spec = registeredSpec or addon.variables.unitSpec
				local specCfg = ensureSpecCfg(spec)
				if not specCfg then return end
				specCfg[barType] = specCfg[barType] or {}
				local bcfg = specCfg[barType]
				bcfg.anchor = bcfg.anchor or {}
				if data.point then
					local relFrame = bcfg.anchor.relativeFrame or "UIParent"
					-- Nur UIParent-Anker von Edit Mode übernehmen; externe Anker behalten ihre Werte
					if relFrame == "UIParent" then
						bcfg.anchor.point = data.point
						bcfg.anchor.relativePoint = data.relativePoint or data.point
						bcfg.anchor.x = data.x or 0
						bcfg.anchor.y = data.y or 0
					end
					bcfg.anchor.relativeFrame = relFrame
				end
				bcfg.width = data.width or bcfg.width
				bcfg.height = data.height or bcfg.height
				if spec == addon.variables.unitSpec then
					if barType == "HEALTH" then
						ResourceBars.SetHealthBarSize(bcfg.width, bcfg.height)
					else
						ResourceBars.SetPowerBarSize(bcfg.width, bcfg.height, barType)
					end
					if ResourceBars.ReanchorAll then ResourceBars.ReanchorAll() end
					if ResourceBars.Refresh then ResourceBars.Refresh() end
					if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RefreshSettingValues then addon.EditModeLib.internal:RefreshSettingValues() end
				end
			end,
			isEnabled = function()
				local c = curSpecCfg()
				return c and c.enabled == true
			end,
			settings = settingsList,
			buttons = buttons,
			showOutsideEditMode = true,
			collapseExclusive = true,
		})
		if addon.EditModeLib and addon.EditModeLib.SetFrameResetVisible then addon.EditModeLib:SetFrameResetVisible(frame, false) end
		registeredFrames[frameId] = true
		registered = registered + 1
	end

	registerBar("HEALTH", "EQOLHealthBar", "HEALTH", ResourceBars.DEFAULT_HEALTH_WIDTH, ResourceBars.DEFAULT_HEALTH_HEIGHT)
	local classTypes = (ResourceBars.GetClassPowerTypes and ResourceBars.GetClassPowerTypes(addon.variables.unitClass)) or ResourceBars.classPowerTypes or {}
	for _, pType in ipairs(classTypes) do
		local frameName = "EQOL" .. pType .. "Bar"
		registerBar(pType, frameName, pType, ResourceBars.DEFAULT_POWER_WIDTH, ResourceBars.DEFAULT_POWER_HEIGHT)
	end

	if registered > 0 then ResourceBars._editModeRegistered = true end
end

ResourceBars.RegisterEditModeFrames = registerEditModeBars

local function buildSpecToggles(specIndex, specName, available, expandable)
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
			text = (ResourceBars.PowerLabels and ResourceBars.PowerLabels[mainType]) or _G["POWER_TYPE_" .. mainType] or _G[mainType] or mainType,
			enabled = cfg.enabled == true,
		}
		added[mainType] = true
	end

	for _, pType in ipairs(ResourceBars.classPowerTypes or {}) do
		if available[pType] and not added[pType] then
			specCfg[pType] = specCfg[pType] or {}
			local cfg = specCfg[pType]
			local label = (ResourceBars.PowerLabels and ResourceBars.PowerLabels[pType]) or _G["POWER_TYPE_" .. pType] or _G[pType] or pType
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
			local specCfg = ensureSpecCfg(specIndex)
			if not specCfg then return end
			specCfg[key] = specCfg[key] or {}
			specCfg[key].enabled = shouldSelect and true or false
			setBarEnabled(specIndex, key, shouldSelect)
		end,
		parent = true,
		parentCheck = function() return addon.db["enableResourceFrame"] == true end,
		parentSection = expandable,
	}
end

local settingsBuilt = false
local function buildSettings()
	if settingsBuilt then return end
	local cat = addon.SettingsLayout.rootUI

	if not cat then return end

	local expandable = addon.SettingsLayout.uiBarsResourcesExpandable
	if not expandable then return end

	settingsBuilt = true

	addon.functions.SettingsCreateHeadline(cat, L["Resource Bars"], { parentSection = expandable })

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
			parentSection = expandable,
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
					parentSection = expandable,
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
					parentSection = expandable,
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
					parentSection = expandable,
				},
				{
					var = "resourceBarsHidePetBattle",
					text = L["Hide in pet battles"] or "Hide in pet battles",
					get = function() return addon.db["resourceBarsHidePetBattle"] end,
					func = function(val)
						addon.db["resourceBarsHidePetBattle"] = val and true or false
						applyResourceBarsVisibility("settings")
					end,
					parent = true,
					parentCheck = function() return addon.db["enableResourceFrame"] == true end,
					sType = "checkbox",
					parentSection = expandable,
				},
				{
					var = "resourceBarsHideClientScene",
					text = L["Hide in client scenes"] or "Hide in client scenes",
					get = function()
						local value = addon.db["resourceBarsHideClientScene"]
						if value == nil then return true end
						return value == true
					end,
					func = function(val)
						addon.db["resourceBarsHideClientScene"] = val and true or false
						applyResourceBarsVisibility("settings")
					end,
					parent = true,
					parentCheck = function() return addon.db["enableResourceFrame"] == true end,
					sType = "checkbox",
					parentSection = expandable,
				},
				{
					var = "resourceBarsAutoEnable",
					text = L["AutoEnableAllBars"] or "Auto-enable bars for new characters",
					sType = "multidropdown",
					options = AUTO_ENABLE_OPTIONS,
					order = AUTO_ENABLE_ORDER,
					isSelectedFunc = function(key)
						local selection = autoEnableSelection()
						return selection and selection[key] == true
					end,
					setSelectedFunc = function(key, shouldSelect)
						local selection = autoEnableSelection()
						if shouldSelect then
							selection[key] = true
						else
							selection[key] = nil
						end
						local spec = addon.variables.unitSpec
						if spec then
							local cfg = ensureSpecCfg(spec)
							if cfg then addon.Aura.functions.requestActiveRefresh(spec) end
						end
					end,
					parent = true,
					parentCheck = function() return addon.db["enableResourceFrame"] == true end,
					parentSection = expandable,
				},
				{
					sType = "hint",
					text = "|cff99e599" .. L["ResourceBarsSpecHint"] .. "|r",
					parent = true,
					parentCheck = function() return addon.db["enableResourceFrame"] == true end,
					parentSection = expandable,
				},
			},
		},
	}

	local classID = addon.variables and addon.variables.unitClassID
	local classTag = addon.variables and addon.variables.unitClass
	if (not classID) or not classTag then
		local _, tag, id = UnitClass("player")
		if not classTag then classTag = tag end
		if not classID then classID = id end
	end
	classID = tonumber(classID)
	if classID and classID > 0 and classTag and ResourceBars.powertypeClasses and ResourceBars.powertypeClasses[classTag] then
		local specCount = C_SpecializationInfo.GetNumSpecializationsForClassID(classID)
		for specIndex = 1, (specCount or 0) do
			local specID, specName = GetSpecializationInfoForClassID(classID, specIndex)
			local available = ResourceBars.powertypeClasses[classTag][specIndex] or {}
			if specID and specName then
				local entry = buildSpecToggles(specIndex, specName, available, expandable)
				if entry then table.insert(data[1].children, entry) end
			end
		end
	end

	addon.functions.SettingsCreateCheckboxes(cat, data)

	registerEditModeBars()
end

addon.Aura.functions = addon.Aura.functions or {}
addon.Aura.functions.AddResourceBarsSettings = buildSettings
addon.Aura.functions.AddResourceBarsProfileSettings = function()
	if addon.SettingsLayout.resourceBarsProfileBuilt then return end
	addon.SettingsLayout.resourceBarsProfileBuilt = true

	local classKey = addon.variables.unitClass or "UNKNOWN"
	local function ensureProfileScope()
		addon.db = addon.db or {}
		if type(addon.db.resourceBarsProfileScope) ~= "table" then addon.db.resourceBarsProfileScope = {} end
		return addon.db.resourceBarsProfileScope
	end
	local function getScope()
		local scope = ensureProfileScope()
		local cur = scope and scope[classKey]
		if not cur then cur = "ALL" end
		return cur
	end
	local function setScope(val)
		local scope = ensureProfileScope()
		if scope then scope[classKey] = val end
	end

	local scopeList = {
		ALL = L["All specs"] or "All specs",
		ALL_CLASSES = L["All classes"] or "All classes",
	}
	local scopeOrder = { "ALL" }
	local classID = addon.variables and addon.variables.unitClassID
	local classTag = addon.variables and addon.variables.unitClass
	if (not classID) or not classTag then
		local _, tag, id = UnitClass("player")
		if not classTag then classTag = tag end
		if not classID then classID = id end
	end
	classID = tonumber(classID)
	if
		classID
		and classID > 0
		and classTag
		and C_SpecializationInfo
		and C_SpecializationInfo.GetNumSpecializationsForClassID
		and ResourceBars.powertypeClasses
		and ResourceBars.powertypeClasses[classTag]
	then
		local specCount = C_SpecializationInfo.GetNumSpecializationsForClassID(classID)
		for specIndex = 1, (specCount or 0) do
			local _, specName = GetSpecializationInfoForClassID(classID, specIndex)
			if specName then
				scopeList[tostring(specIndex)] = specName
				scopeOrder[#scopeOrder + 1] = tostring(specIndex)
			end
		end
	end
	scopeOrder[#scopeOrder + 1] = "ALL_CLASSES"

	local cProfiles = addon.SettingsLayout.rootPROFILES

	local expandableProfile = addon.functions.SettingsCreateExpandableSection(cProfiles, {
		name = L["Resource Bars"],
		expanded = false,
		colorizeTitle = false,
	})

	addon.functions.SettingsCreateDropdown(cProfiles, {
		var = "resourceBarsProfileScope",
		text = L["ProfileScope"] or (L["Apply to"] or "Apply to"),
		list = scopeList,
		get = getScope,
		set = setScope,
		default = "ALL",
		parentSection = expandableProfile,
	})

	addon.functions.SettingsCreateButton(cProfiles, {
		var = "resourceBarsExport",
		text = L["Export"] or "Export",
		func = function()
			local code
			local reason
			local scopeKey = getScope() or "ALL"
			if ResourceBars and ResourceBars.ExportProfile then
				code, reason = ResourceBars.ExportProfile(scopeKey)
			end
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
		parentSection = expandableProfile,
	})

	addon.functions.SettingsCreateButton(cProfiles, {
		var = "resourceBarsImport",
		text = L["Import"] or "Import",
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
				local ok, applied, enableState, appliedMode = addon.Aura.functions.importResourceProfile(input, scopeKey)
				if not ok then
					local msg = ResourceBars.ImportErrorMessage and ResourceBars.ImportErrorMessage(applied, enableState) or (L["ImportProfileFailed"] or "Import failed.")
					print("|cff00ff98Enhance QoL|r: " .. tostring(msg))
					return
				end
				local isAllClasses = appliedMode == "ALL_CLASSES"
				if enableState ~= nil and (scopeKey == "ALL" or scopeKey == "ALL_CLASSES" or isAllClasses) then
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
				applyResourceBarsVisibility("import")
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
				if (scopeKey == "ALL_CLASSES" or isAllClasses) and ReloadUI then ReloadUI() end
			end
			StaticPopup_Show("EQOL_RESOURCEBAR_IMPORT_SETTINGS")
		end,
		parentSection = expandableProfile,
	})
end
