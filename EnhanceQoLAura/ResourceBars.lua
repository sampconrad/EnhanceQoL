--@debug@
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Aura = addon.Aura or {}
local ResourceBars = {}
addon.Aura.ResourceBars = ResourceBars

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")
local AceGUI = addon.AceGUI

local frameAnchor
local mainFrame
local healthBar
local powerbar = {}
local powerfrequent = {}
local getBarSettings
local getAnchor
local layoutRunes
local updatePowerBar
local lastTabIndex
local lastBarSelectionPerSpec = {}
local BAR_STACK_SPACING = -1
local SEPARATOR_THICKNESS = 1
-- Fixed, non-DB defaults
local DEFAULT_HEALTH_WIDTH = 200
local DEFAULT_HEALTH_HEIGHT = 20
local DEFAULT_POWER_WIDTH = 200
local DEFAULT_POWER_HEIGHT = 20

function addon.Aura.functions.addResourceFrame(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	groupCore:SetTitle(L["Resource Bars"])
	wrapper:AddChild(groupCore)

	local data = {
		{
			text = L["Enable Resource frame"],
			var = "enableResourceFrame",
			func = function(self, _, value)
				addon.db["enableResourceFrame"] = value
				if value then
					addon.Aura.ResourceBars.EnableResourceBars()
				elseif addon.Aura.ResourceBars and addon.Aura.ResourceBars.DisableResourceBars then
					addon.Aura.ResourceBars.DisableResourceBars()
				end
				-- Rebuild the options UI to reflect enabled/disabled state
				if container and container.ReleaseChildren then
					container:ReleaseChildren()
					-- Defer rebuild slightly to ensure enable/disable side effects settle
					if C_Timer and C_Timer.After then
						C_Timer.After(0, function()
							if addon and addon.Aura and addon.Aura.functions and addon.Aura.functions.addResourceFrame then addon.Aura.functions.addResourceFrame(container) end
						end)
					else
						if addon and addon.Aura and addon.Aura.functions and addon.Aura.functions.addResourceFrame then addon.Aura.functions.addResourceFrame(container) end
					end
				end
			end,
		},
	}

	table.sort(data, function(a, b) return a.text < b.text end)

	for _, cbData in ipairs(data) do
		local uFunc = function(self, _, value) addon.db[cbData.var] = value end
		if cbData.func then uFunc = cbData.func end
		local cbElement = addon.functions.createCheckboxAce(cbData.text, addon.db[cbData.var], uFunc)
		groupCore:AddChild(cbElement)
	end

	if addon.db["enableResourceFrame"] then
		-- No global defaults; everything is per-spec and per-bar below

		local anchorPoints = {
			TOPLEFT = "TOPLEFT",
			TOP = "TOP",
			TOPRIGHT = "TOPRIGHT",
			LEFT = "LEFT",
			CENTER = "CENTER",
			RIGHT = "RIGHT",
			BOTTOMLEFT = "BOTTOMLEFT",
			BOTTOM = "BOTTOM",
			BOTTOMRIGHT = "BOTTOMRIGHT",
		}
		local anchorOrder = {
			"TOPLEFT",
			"TOP",
			"TOPRIGHT",
			"LEFT",
			"CENTER",
			"RIGHT",
			"BOTTOMLEFT",
			"BOTTOM",
			"BOTTOMRIGHT",
		}

		local baseFrameList = {
			UIParent = "UIParent",
			PlayerFrame = "PlayerFrame",
			TargetFrame = "TargetFrame",
		}

		local function displayNameForBarType(pType)
			if pType == "HEALTH" then return HEALTH end
			local s = _G["POWER_TYPE_" .. pType] or _G[pType]
			if type(s) == "string" and s ~= "" then return s end
			return pType
		end

		local function addAnchorOptions(barType, parent, info, frameList, specIndex)
			info = info or {}
			frameList = frameList or baseFrameList

			local header = addon.functions.createLabelAce(string.format("%s %s", displayNameForBarType(barType), L["Anchor"]))
			parent:AddChild(header)

			-- Filter choices to avoid creating loops
			local function frameNameToBarType(fname)
				if fname == "EQOLHealthBar" then return "HEALTH" end
				return type(fname) == "string" and fname:match("^EQOL(.+)Bar$") or nil
			end
			local function wouldCauseLoop(fromType, candidateName)
				-- Always safe: UIParent and non-EQOL frames
				if candidateName == "UIParent" then return false end
				local candType = frameNameToBarType(candidateName)
				if not candType then return false end
				-- Direct self-reference
				if candType == fromType then return true end
				-- Follow anchors from candidate; if we reach fromType's frame, it would loop
				local seen = {}
				local name = candidateName
				local limit = 10
				local targetFrameName = (fromType == "HEALTH") and "EQOLHealthBar" or ("EQOL" .. fromType .. "Bar")
				while name and name ~= "UIParent" and limit > 0 do
					if seen[name] then break end
					seen[name] = true
					if name == targetFrameName then return true end
					local bt = frameNameToBarType(name)
					if not bt then break end
					local anch = getAnchor(bt, addon.variables.unitSpec)
					name = anch and anch.relativeFrame or "UIParent"
					limit = limit - 1
				end
				return false
			end

			local filtered = {}
			for k, v in pairs(frameList) do
				if not wouldCauseLoop(barType, k) then filtered[k] = v end
			end
			-- Ensure UIParent is always present
			filtered.UIParent = frameList.UIParent or "UIParent"

			-- Sub-group we can rebuild when relative frame changes
			local anchorSub = addon.functions.createContainer("SimpleGroup", "Flow")
			parent:AddChild(anchorSub)

			local function buildAnchorSub()
				anchorSub:ReleaseChildren()

				-- Row for Relative Frame, Point, Relative Point (each 33%)
				local row = addon.functions.createContainer("SimpleGroup", "Flow")
				row:SetFullWidth(true)

				local initial = info.relativeFrame or "UIParent"
				if not filtered[initial] then initial = "UIParent" end
				-- Ensure DB reflects a valid selection
				info.relativeFrame = initial
				local dropFrame = addon.functions.createDropdownAce(L["Relative Frame"], filtered, nil, nil)
				dropFrame:SetValue(initial)
				dropFrame:SetFullWidth(false)
				dropFrame:SetRelativeWidth(0.333)
				row:AddChild(dropFrame)

				local relName = info.relativeFrame or "UIParent"
				if relName ~= "UIParent" then
					local dropPoint = addon.functions.createDropdownAce(RESAMPLE_QUALITY_POINT, anchorPoints, anchorOrder, function(self, _, val)
						info.point = val
						if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
					end)
					dropPoint:SetValue(info.point or "TOPLEFT")
					dropPoint:SetFullWidth(false)
					dropPoint:SetRelativeWidth(0.333)
					row:AddChild(dropPoint)

					local dropRelPoint = addon.functions.createDropdownAce(L["Relative Point"], anchorPoints, anchorOrder, function(self, _, val)
						info.relativePoint = val
						if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
					end)
					dropRelPoint:SetValue(info.relativePoint or info.point or "TOPLEFT")
					dropRelPoint:SetFullWidth(false)
					dropRelPoint:SetRelativeWidth(0.333)
					row:AddChild(dropRelPoint)
				end

				anchorSub:AddChild(row)

				-- X / Y row (50% / 50%) when anchored to a frame
				if (info.relativeFrame or "UIParent") ~= "UIParent" then
					local editX = addon.functions.createEditboxAce("X", tostring(info.x or 0), function(self)
						info.x = tonumber(self:GetText()) or 0
						if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
					end)
					editX:SetFullWidth(false)
					editX:SetRelativeWidth(0.5)
					anchorSub:AddChild(editX)

					local editY = addon.functions.createEditboxAce("Y", tostring(info.y or 0), function(self)
						info.y = tonumber(self:GetText()) or 0
						if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
					end)
					editY:SetFullWidth(false)
					editY:SetRelativeWidth(0.5)
					anchorSub:AddChild(editY)
				else
					info.point = "TOPLEFT"
					info.relativePoint = "TOPLEFT"
					local hint = addon.functions.createLabelAce(L["Movable while holding SHIFT"], nil, nil, 10)
					anchorSub:AddChild(hint)
				end

				-- Callback for Relative Frame change (rebuild the sub UI on selection)
				local function onFrameChanged(self, _, val)
					local prev = info.relativeFrame or "UIParent"
					info.relativeFrame = val
					if val ~= "UIParent" then
						info.point = "TOPLEFT"
						info.relativePoint = "BOTTOMLEFT"
						info.x = 0
						info.y = 0
					end
					if val == "UIParent" and prev ~= "UIParent" then
						local cfg = getBarSettings(barType)
						local defaultW = barType == "HEALTH" and DEFAULT_HEALTH_WIDTH or DEFAULT_POWER_WIDTH
						local defaultH = barType == "HEALTH" and DEFAULT_HEALTH_HEIGHT or DEFAULT_POWER_HEIGHT
						local w = (cfg and cfg.width) or defaultW or 0
						local h = (cfg and cfg.height) or defaultH or 0
						local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
						local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
						info.point = "TOPLEFT"
						info.relativePoint = "TOPLEFT"
						info.x = (pw - w) / 2
						info.y = (h - ph) / 2
					end
					buildAnchorSub()
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end

				dropFrame:SetCallback("OnValueChanged", onFrameChanged)
			end

			-- Initial build
			buildAnchorSub()

			parent:AddChild(addon.functions.createSpacerAce())
		end

		local specTabs = {}
		for i = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(addon.variables.unitClassID) do
			local _, specName = GetSpecializationInfoForClassID(addon.variables.unitClassID, i)
			table.insert(specTabs, { text = specName, value = i })
		end

		local tabGroup = addon.functions.createContainer("TabGroup", "Flow")
		local function buildSpec(container, specIndex)
			container:ReleaseChildren()
			if not addon.Aura.ResourceBars.powertypeClasses[addon.variables.unitClass] then return end
			local specInfo = addon.Aura.ResourceBars.powertypeClasses[addon.variables.unitClass][specIndex]
			if not specInfo then return end

			addon.db.personalResourceBarSettings[addon.variables.unitClass] = addon.db.personalResourceBarSettings[addon.variables.unitClass] or {}
			addon.db.personalResourceBarSettings[addon.variables.unitClass][specIndex] = addon.db.personalResourceBarSettings[addon.variables.unitClass][specIndex] or {}
			local dbSpec = addon.db.personalResourceBarSettings[addon.variables.unitClass][specIndex]

			-- Gather available bars
			local available = { HEALTH = true }
			for _, pType in ipairs(addon.Aura.ResourceBars.classPowerTypes) do
				if specInfo.MAIN == pType or specInfo[pType] then available[pType] = true end
			end

			-- Ensure DB defaults
			for pType in pairs(available) do
				if pType ~= "HEALTH" then
					dbSpec[pType] = dbSpec[pType]
						or {
							enabled = false,
							width = DEFAULT_POWER_WIDTH,
							height = DEFAULT_POWER_HEIGHT,
							textStyle = pType == "MANA" and "PERCENT" or "CURMAX",
							fontSize = 16,
							showSeparator = false,
							separatorColor = { 1, 1, 1, 0.5 },
							showCooldownText = false,
							cooldownTextFontSize = 16,
						}
					dbSpec[pType].anchor = dbSpec[pType].anchor or {}
				end
			end

			-- Compact toggles (including Health)
			local groupToggles = addon.functions.createContainer("InlineGroup", "Flow")
			groupToggles:SetTitle(L["Bars to show"])
			container:AddChild(groupToggles)
			-- Ensure HEALTH spec config exists
			dbSpec.HEALTH = dbSpec.HEALTH
				or {
					enabled = false,
					width = DEFAULT_HEALTH_WIDTH,
					height = DEFAULT_HEALTH_HEIGHT,
					textStyle = "PERCENT",
					fontSize = 16,
					anchor = {},
				}
			do
				local hcfg = dbSpec.HEALTH
				local cbH = addon.functions.createCheckboxAce(HEALTH, hcfg.enabled == true, function(self, _, val)
					if (hcfg.enabled == true) and not val then addon.Aura.ResourceBars.DetachAnchorsFrom("HEALTH", specIndex) end
					hcfg.enabled = val
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
					buildSpec(container, specIndex)
				end)
				cbH:SetFullWidth(false)
				cbH:SetRelativeWidth(0.33)
				groupToggles:AddChild(cbH)
			end
			for pType in pairs(available) do
				if pType ~= "HEALTH" then
					local cfg = dbSpec[pType]
					local label = _G["POWER_TYPE_" .. pType] or _G[pType] or pType
					local cb = addon.functions.createCheckboxAce(label, cfg.enabled == true, function(self, _, val)
						if (cfg.enabled == true) and not val then addon.Aura.ResourceBars.DetachAnchorsFrom(pType, specIndex) end
						cfg.enabled = val
						if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
						buildSpec(container, specIndex)
					end)
					cb:SetFullWidth(false)
					cb:SetRelativeWidth(0.33)
					groupToggles:AddChild(cb)
				end
			end

			-- Selection dropdown for configuring a single bar
			local cfgList, cfgOrder = {}, {}
			if dbSpec.HEALTH.enabled == true then
				cfgList.HEALTH = HEALTH
				table.insert(cfgOrder, "HEALTH")
			end
			for _, pType in ipairs(addon.Aura.ResourceBars.classPowerTypes) do
				if available[pType] then
					local cfg = dbSpec[pType]
					if cfg and cfg.enabled == true then
						cfgList[pType] = _G["POWER_TYPE_" .. pType] or _G[pType] or pType
						table.insert(cfgOrder, pType)
					end
				end
			end

			local specKey = tostring(specIndex)
			if not lastBarSelectionPerSpec[specKey] or not cfgList[lastBarSelectionPerSpec[specKey]] then
				lastBarSelectionPerSpec[specKey] = (specInfo.MAIN and cfgList[specInfo.MAIN]) and specInfo.MAIN or (cfgList.HEALTH and "HEALTH" or next(cfgList))
			end

			local groupConfig = addon.functions.createContainer("InlineGroup", "List")
			groupConfig:SetTitle(DELVES_CONFIGURE_BUTTON)
			container:AddChild(groupConfig)

			if #cfgOrder == 0 then
				local hint = addon.functions.createLabelAce(L["Enable a bar above to configure options."])
				groupConfig:AddChild(hint)
				return
			end

			local dropCfg = addon.functions.createDropdownAce(L["Bar"], cfgList, cfgOrder, function(self, _, val)
				lastBarSelectionPerSpec[specKey] = val
				buildSpec(container, specIndex)
			end)
			dropCfg:SetValue(lastBarSelectionPerSpec[specKey])
			groupConfig:AddChild(dropCfg)

			local sel = lastBarSelectionPerSpec[specKey]
			local frames = {}
			for k, v in pairs(baseFrameList) do
				frames[k] = v
			end
			-- Only list bars that are valid for this spec and enabled by user
			if dbSpec.HEALTH and dbSpec.HEALTH.enabled == true then frames.EQOLHealthBar = (displayNameForBarType and displayNameForBarType("HEALTH") or HEALTH) .. " " .. L["BarSuffix"] end
			for _, t in ipairs(addon.Aura.ResourceBars.classPowerTypes) do
				if t ~= sel and available[t] and dbSpec[t] and dbSpec[t].enabled == true then
					frames["EQOL" .. t .. "Bar"] = (displayNameForBarType and displayNameForBarType(t) or (_G[t] or t)) .. " " .. L["BarSuffix"]
				end
			end

			if sel == "HEALTH" then
				local hCfg = dbSpec.HEALTH
				-- Size row (50%/50%)
				local sizeRow = addon.functions.createContainer("SimpleGroup", "Flow")
				sizeRow:SetFullWidth(true)
				local sw = addon.functions.createSliderAce(HUD_EDIT_MODE_SETTING_CHAT_FRAME_WIDTH, hCfg.width or DEFAULT_HEALTH_WIDTH, 1, 2000, 1, function(self, _, val)
					hCfg.width = val
					if specIndex == addon.variables.unitSpec then addon.Aura.ResourceBars.SetHealthBarSize(hCfg.width, hCfg.height or DEFAULT_HEALTH_HEIGHT) end
				end)
				sw:SetFullWidth(false)
				sw:SetRelativeWidth(0.5)
				sizeRow:AddChild(sw)
				local sh = addon.functions.createSliderAce(HUD_EDIT_MODE_SETTING_CHAT_FRAME_HEIGHT, hCfg.height or DEFAULT_HEALTH_HEIGHT, 1, 2000, 1, function(self, _, val)
					hCfg.height = val
					if specIndex == addon.variables.unitSpec then addon.Aura.ResourceBars.SetHealthBarSize(hCfg.width or DEFAULT_HEALTH_WIDTH, hCfg.height) end
				end)
				sh:SetFullWidth(false)
				sh:SetRelativeWidth(0.5)
				sizeRow:AddChild(sh)
				groupConfig:AddChild(sizeRow)

				-- Text + Size row (hide size when NONE)
				local healthTextRow = addon.functions.createContainer("SimpleGroup", "Flow")
				healthTextRow:SetFullWidth(true)
				groupConfig:AddChild(healthTextRow)
				local function buildHealthTextRow()
					healthTextRow:ReleaseChildren()
					local tList = { PERCENT = STATUS_TEXT_PERCENT, CURMAX = L["Current/Max"], CURRENT = L["Current"], NONE = NONE }
					local tOrder = { "PERCENT", "CURMAX", "CURRENT", "NONE" }
					local dropT = addon.functions.createDropdownAce(L["Text"], tList, tOrder, function(self, _, key)
						hCfg.textStyle = key
						if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
						buildHealthTextRow()
					end)
					dropT:SetValue(hCfg.textStyle or "PERCENT")
					dropT:SetFullWidth(false)
					dropT:SetRelativeWidth(0.5)
					healthTextRow:AddChild(dropT)
					if (hCfg.textStyle or "PERCENT") ~= "NONE" then
						local sFont = addon.functions.createSliderAce(HUD_EDIT_MODE_SETTING_OBJECTIVE_TRACKER_TEXT_SIZE, hCfg.fontSize or 16, 6, 64, 1, function(self, _, val)
							hCfg.fontSize = val
							if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
						end)
						sFont:SetFullWidth(false)
						sFont:SetRelativeWidth(0.5)
						healthTextRow:AddChild(sFont)
					end
				end
				buildHealthTextRow()

				addAnchorOptions("HEALTH", groupConfig, hCfg.anchor, frames, specIndex)
			else
				local cfg = dbSpec[sel] or {}
				local defaultW = DEFAULT_POWER_WIDTH
				local defaultH = DEFAULT_POWER_HEIGHT
				local curW = cfg.width or defaultW
				local curH = cfg.height or defaultH
				local defaultStyle = (sel == "MANA") and "PERCENT" or "CURMAX"
				local curStyle = cfg.textStyle or defaultStyle
				local curFont = cfg.fontSize or 16

				-- Size row (50%/50%)
				local sizeRow2 = addon.functions.createContainer("SimpleGroup", "Flow")
				sizeRow2:SetFullWidth(true)
				local sw = addon.functions.createSliderAce(HUD_EDIT_MODE_SETTING_CHAT_FRAME_WIDTH, curW, 1, 2000, 1, function(self, _, val)
					cfg.width = val
					if specIndex == addon.variables.unitSpec then addon.Aura.ResourceBars.SetPowerBarSize(val, cfg.height or defaultH, sel) end
				end)
				sw:SetFullWidth(false)
				sw:SetRelativeWidth(0.5)
				sizeRow2:AddChild(sw)
				local sh = addon.functions.createSliderAce(HUD_EDIT_MODE_SETTING_CHAT_FRAME_HEIGHT, curH, 1, 2000, 1, function(self, _, val)
					cfg.height = val
					if specIndex == addon.variables.unitSpec then addon.Aura.ResourceBars.SetPowerBarSize(cfg.width or defaultW, val, sel) end
				end)
				sh:SetFullWidth(false)
				sh:SetRelativeWidth(0.5)
				sizeRow2:AddChild(sh)
				groupConfig:AddChild(sizeRow2)

				if sel ~= "RUNES" then
					-- Text + Size row (50%/50%), hide size when NONE
					local textRow = addon.functions.createContainer("SimpleGroup", "Flow")
					textRow:SetFullWidth(true)
					groupConfig:AddChild(textRow)
					local function buildTextRow()
						textRow:ReleaseChildren()
						local tList = { PERCENT = STATUS_TEXT_PERCENT, CURMAX = L["Current/Max"], CURRENT = L["Current"], NONE = NONE }
						local tOrder = { "PERCENT", "CURMAX", "CURRENT", "NONE" }
						local drop = addon.functions.createDropdownAce(L["Text"], tList, tOrder, function(self, _, key)
							cfg.textStyle = key
							if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
							buildTextRow()
						end)
						drop:SetValue(cfg.textStyle or curStyle)
						drop:SetFullWidth(false)
						drop:SetRelativeWidth(0.5)
						textRow:AddChild(drop)
						if (cfg.textStyle or curStyle) ~= "NONE" then
							local sFont = addon.functions.createSliderAce(HUD_EDIT_MODE_SETTING_OBJECTIVE_TRACKER_TEXT_SIZE, cfg.fontSize or curFont, 6, 64, 1, function(self, _, val)
								cfg.fontSize = val
								if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
							end)
							sFont:SetFullWidth(false)
							sFont:SetRelativeWidth(0.5)
							textRow:AddChild(sFont)
						end
					end
					buildTextRow()
				else
					-- RUNES specific options
					local cbRT = addon.functions.createCheckboxAce(L["Show cooldown text"], cfg.showCooldownText == true, function(self, _, val)
						cfg.showCooldownText = val and true or false
						if powerbar["RUNES"] then
							layoutRunes(powerbar["RUNES"])
							updatePowerBar("RUNES")
						end
					end)
					groupConfig:AddChild(cbRT)

					local sRTFont = addon.functions.createSliderAce(L["Cooldown Text Size"], cfg.cooldownTextFontSize or 16, 6, 64, 1, function(self, _, val)
						cfg.cooldownTextFontSize = val
						if powerbar["RUNES"] then
							layoutRunes(powerbar["RUNES"])
							updatePowerBar("RUNES")
						end
					end)
					groupConfig:AddChild(sRTFont)
				end

				-- Separator toggle + color picker row (eligible bars only)
				local eligible = addon.Aura.ResourceBars.separatorEligible
				if eligible and eligible[sel] then
					local sepRow = addon.functions.createContainer("SimpleGroup", "Flow")
					sepRow:SetFullWidth(true)
					local sepColor
					local cbSep = addon.functions.createCheckboxAce(L["Show separator"], cfg.showSeparator == true, function(self, _, val)
						cfg.showSeparator = val and true or false
						if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
						if sepColor then sepColor:SetDisabled(not cfg.showSeparator) end
					end)
					cbSep:SetFullWidth(false)
					cbSep:SetRelativeWidth(0.5)
					sepRow:AddChild(cbSep)
					sepColor = AceGUI:Create("ColorPicker")
					sepColor:SetLabel(L["Separator Color"] or "Separator Color")
					local sc = cfg.separatorColor or { 1, 1, 1, 0.5 }
					sepColor:SetColor(sc[1] or 1, sc[2] or 1, sc[3] or 1, sc[4] or 0.5)
					sepColor:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
						cfg.separatorColor = { r, g, b, a }
						if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
					end)
					sepColor:SetFullWidth(false)
					sepColor:SetRelativeWidth(0.5)
					sepColor:SetDisabled(not (cfg.showSeparator == true))
					sepRow:AddChild(sepColor)
					groupConfig:AddChild(sepRow)
				end

				-- Druid: Show in forms (per bar), skip for COMBO_POINTS (always Cat)
				if addon.variables.unitClass == "DRUID" and sel ~= "COMBO_POINTS" then
					groupConfig:AddChild(addon.functions.createSpacerAce())
					cfg.showForms = cfg.showForms or {}
					local formsRow = addon.functions.createContainer("SimpleGroup", "Flow")
					formsRow:SetFullWidth(true)
					local label = addon.functions.createLabelAce(L["Show in"])
					label:SetFullWidth(true)
					groupConfig:AddChild(label)
					local function mkCb(key, text)
						local cb = addon.functions.createCheckboxAce(text, cfg.showForms[key] ~= false, function(self, _, val)
							cfg.showForms[key] = val and true or false
							if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
						end)
						cb:SetFullWidth(false)
						cb:SetRelativeWidth(0.25)
						formsRow:AddChild(cb)
					end
					if sel == "COMBO_POINTS" then
						-- Combo points only in Cat; default only Cat true
						if cfg.showForms.CAT == nil then cfg.showForms.CAT = true end
						cfg.showForms.HUMANOID = cfg.showForms.HUMANOID or false
						cfg.showForms.BEAR = cfg.showForms.BEAR or false
						cfg.showForms.TRAVEL = cfg.showForms.TRAVEL or false
						cfg.showForms.MOONKIN = cfg.showForms.MOONKIN or false
						cfg.showForms.TREANT = cfg.showForms.TREANT or false
						cfg.showForms.STAG = cfg.showForms.STAG or false
						mkCb("CAT", L["Cat"])
					else
						if cfg.showForms.HUMANOID == nil then cfg.showForms.HUMANOID = true end
						if cfg.showForms.BEAR == nil then cfg.showForms.BEAR = true end
						if cfg.showForms.CAT == nil then cfg.showForms.CAT = true end
						if cfg.showForms.TRAVEL == nil then cfg.showForms.TRAVEL = true end
						if cfg.showForms.MOONKIN == nil then cfg.showForms.MOONKIN = true end
						if cfg.showForms.TREANT == nil then cfg.showForms.TREANT = true end
						if cfg.showForms.STAG == nil then cfg.showForms.STAG = true end
						mkCb("HUMANOID", L["Humanoid"])
						mkCb("BEAR", L["Bear"])
						mkCb("CAT", L["Cat"])
						mkCb("TRAVEL", L["Travel"])
						mkCb("MOONKIN", L["Moonkin"])
						mkCb("TREANT", L["Treant"])
						mkCb("STAG", L["Stag"])
					end
					groupConfig:AddChild(formsRow)
				end
				groupConfig:AddChild(addon.functions.createSpacerAce())

				addAnchorOptions(sel, groupConfig, cfg.anchor, frames, specIndex)
			end
		end

		tabGroup:SetTabs(specTabs)
		tabGroup:SetCallback("OnGroupSelected", function(tabContainer, _, val)
			lastTabIndex = val
			buildSpec(tabContainer, val)
		end)
		wrapper:AddChild(tabGroup)
		tabGroup:SelectTab(addon.variables.unitSpec or specTabs[1].value)
	end
	scroll:DoLayout()
end

local function getPowerBarColor(type)
	local powerKey = string.upper(type)
	local color = PowerBarColor[powerKey]
	if color then return color.r, color.g, color.b end
	return 1, 1, 1
end

local function updateHealthBar()
	if healthBar and healthBar:IsVisible() then
		local maxHealth = healthBar._lastMax
		if not maxHealth then
			maxHealth = UnitHealthMax("player")
			healthBar._lastMax = maxHealth
			healthBar:SetMinMaxValues(0, maxHealth)
		end
		local curHealth = UnitHealth("player")
		local absorb = UnitGetTotalAbsorbs("player") or 0

		-- Only push values to the bar if changed
		if healthBar._lastVal ~= curHealth then
			healthBar:SetValue(curHealth)
			healthBar._lastVal = curHealth
		end

		local percent = (curHealth / math.max(maxHealth, 1)) * 100
		local percentStr = tostring(math.floor(percent + 0.5))
		if healthBar.text then
			local settings = getBarSettings("HEALTH")
			local style = settings and settings.textStyle or "PERCENT"
			if style == "NONE" then
				healthBar.text:SetText("")
				healthBar.text:Hide()
			else
				local text
				if style == "PERCENT" then
					text = percentStr
				elseif style == "CURRENT" then
					text = tostring(curHealth)
				else -- CURMAX
					text = curHealth .. " / " .. maxHealth
				end
				if healthBar._lastText ~= text then
					healthBar.text:SetText(text)
					healthBar._lastText = text
				end
				healthBar.text:Show()
			end
		end
		local bracket, r, g, b
		if percent >= 60 then
			bracket, r, g, b = 3, 0, 0.7, 0
		elseif percent >= 40 then
			bracket, r, g, b = 2, 0.7, 0.7, 0
		else
			bracket, r, g, b = 1, 0.7, 0, 0
		end
		if healthBar._lastBracket ~= bracket then
			healthBar:SetStatusBarColor(r, g, b)
			healthBar._lastBracket = bracket
		end

		local combined = absorb
		if combined > maxHealth then combined = maxHealth end
		healthBar.absorbBar:SetMinMaxValues(0, maxHealth)
		healthBar.absorbBar:SetValue(combined)
	end
end

function getAnchor(name, spec)
	local class = addon.variables.unitClass
	spec = spec or addon.variables.unitSpec
	addon.db.personalResourceBarSettings = addon.db.personalResourceBarSettings or {}
	addon.db.personalResourceBarSettings[class] = addon.db.personalResourceBarSettings[class] or {}
	addon.db.personalResourceBarSettings[class][spec] = addon.db.personalResourceBarSettings[class][spec] or {}
	addon.db.personalResourceBarSettings[class][spec][name] = addon.db.personalResourceBarSettings[class][spec][name] or {}
	local cfg = addon.db.personalResourceBarSettings[class][spec][name]
	cfg.anchor = cfg.anchor or {}
	return cfg.anchor
end

local function resolveAnchor(info, type)
	local frame = _G[info and info.relativeFrame]
	if not frame or frame == UIParent then return frame or UIParent, false end

	local visited = {}
	local check = frame
	local limit = 10

	while check and check.GetName and check ~= UIParent and limit > 0 do
		local fname = check:GetName()
		if visited[fname] then
			print("|cff00ff98Enhance QoL|r: " .. L["AnchorLoop"]:format(fname))
			return UIParent, true
		end
		visited[fname] = true

		local bType
		if fname == "EQOLHealthBar" then
			bType = "HEALTH"
		else
			bType = fname:match("^EQOL(.+)Bar$")
		end

		if not bType then break end
		local anch = getAnchor(bType, addon.variables.unitSpec)
		check = _G[anch and anch.relativeFrame]
		if check == nil or check == UIParent then break end
		limit = limit - 1
	end

	if limit <= 0 then
		print("|cff00ff98Enhance QoL|r: " .. L["AnchorLoop"]:format(info.relativeFrame or ""))
		return UIParent, true
	end
	return frame or UIParent, false
end

local function createHealthBar()
	if mainFrame then
		-- Ensure correct parent when re-enabling
		if mainFrame:GetParent() ~= UIParent then mainFrame:SetParent(UIParent) end
		if healthBar and healthBar.GetParent and healthBar:GetParent() ~= UIParent then healthBar:SetParent(UIParent) end
		mainFrame:Show()
		healthBar:Show()
		return
	end

	-- Reuse existing named frames if they still exist from a previous enable
	mainFrame = _G["EQOLResourceFrame"] or CreateFrame("frame", "EQOLResourceFrame", UIParent)
	if mainFrame:GetParent() ~= UIParent then mainFrame:SetParent(UIParent) end
	healthBar = _G["EQOLHealthBar"] or CreateFrame("StatusBar", "EQOLHealthBar", UIParent, "BackdropTemplate")
	if healthBar:GetParent() ~= UIParent then healthBar:SetParent(UIParent) end
	do
		local cfg = getBarSettings("HEALTH")
		local w = (cfg and cfg.width) or DEFAULT_HEALTH_WIDTH
		local h = (cfg and cfg.height) or DEFAULT_HEALTH_HEIGHT
		healthBar:SetSize(w, h)
	end
	healthBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
	healthBar:SetClampedToScreen(true)
	local anchor = getAnchor("HEALTH", addon.variables.unitSpec)
	local rel, looped = resolveAnchor(anchor, "HEALTH")
	-- If we had to fallback due to a loop, recenter on UIParent using TOPLEFT/TOPLEFT
	if looped and (anchor.relativeFrame or "UIParent") ~= "UIParent" then
		local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
		local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
		local w = healthBar:GetWidth() or DEFAULT_HEALTH_WIDTH
		local h = healthBar:GetHeight() or DEFAULT_HEALTH_HEIGHT
		anchor.point = "TOPLEFT"
		anchor.relativeFrame = "UIParent"
		anchor.relativePoint = "TOPLEFT"
		anchor.x = (pw - w) / 2
		anchor.y = (h - ph) / 2
		rel = UIParent
	end
	-- If first run and anchored to UIParent with no persisted offsets yet, persist centered offsets
	if (anchor.relativeFrame or "UIParent") == "UIParent" and (anchor.x == nil or anchor.y == nil) then
		local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
		local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
		local w = healthBar:GetWidth() or DEFAULT_HEALTH_WIDTH
		local h = healthBar:GetHeight() or DEFAULT_HEALTH_HEIGHT
		anchor.point = anchor.point or "TOPLEFT"
		anchor.relativePoint = anchor.relativePoint or "TOPLEFT"
		anchor.x = (pw - w) / 2
		anchor.y = (h - ph) / 2
		rel = UIParent
	end
	healthBar:ClearAllPoints()
	healthBar:SetPoint(anchor.point or "TOPLEFT", rel, anchor.relativePoint or anchor.point or "TOPLEFT", anchor.x or 0, anchor.y or 0)
	healthBar:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 3,
		insets = { left = 0, right = 0, top = 0, bottom = 0 },
	})
	healthBar:SetBackdropColor(0, 0, 0, 0.8)
	healthBar:SetBackdropBorderColor(0, 0, 0, 0)
	local settings = getBarSettings("HEALTH")
	local fontSize = settings and settings.fontSize or 16

	healthBar.text = healthBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	healthBar.text:SetFont(addon.variables.defaultFont, fontSize, "OUTLINE")
	healthBar.text:SetPoint("CENTER", healthBar, "CENTER", 3, 0)

	healthBar:SetMovable(true)
	healthBar:EnableMouse(true)
	healthBar:RegisterForDrag("LeftButton")
	healthBar:SetScript("OnDragStart", function(self)
		if IsShiftKeyDown() then self:StartMoving() end
	end)
	healthBar:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, rel, relPoint, xOfs, yOfs = self:GetPoint()
		local info = getAnchor("HEALTH", addon.variables.unitSpec)
		local relName = rel and rel.GetName and rel:GetName() or "UIParent"
		if relName == "UIParent" then
			local lx = (self:GetLeft() or 0) - (UIParent:GetLeft() or 0)
			local ly = (self:GetTop() or 0) - (UIParent:GetTop() or 0)
			self:ClearAllPoints()
			self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", lx, ly)
			info.point = "TOPLEFT"
			info.relativeFrame = "UIParent"
			info.relativePoint = "TOPLEFT"
			info.x = lx
			info.y = ly
		else
			info.point = point
			info.relativeFrame = relName
			info.relativePoint = relPoint
			info.x = xOfs
			info.y = yOfs
		end
	end)

	local absorbBar = CreateFrame("StatusBar", "EQOLAbsorbBar", healthBar)
	absorbBar:SetAllPoints(healthBar)
	absorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
	absorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
	absorbBar:SetStatusBarColor(0.8, 0.8, 0.8, 0.8)
	healthBar.absorbBar = absorbBar

	updateHealthBar()

	-- Ensure any bars anchored to Health get reanchored when Health changes size
	healthBar:SetScript("OnSizeChanged", function()
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorDependentsOf then addon.Aura.ResourceBars.ReanchorDependentsOf("EQOLHealthBar") end
	end)
end

local powertypeClasses = {
	DRUID = {
		[1] = { MAIN = "LUNAR_POWER", RAGE = true, ENERGY = true, MANA = true, COMBO_POINTS = true }, -- Balance (combo in Cat)
		[2] = { MAIN = "ENERGY", COMBO_POINTS = true, RAGE = true, MANA = true }, -- Feral (no Astral Power)
		[3] = { MAIN = "RAGE", ENERGY = true, MANA = true, COMBO_POINTS = true }, -- Guardian (no Astral Power)
		[4] = { MAIN = "MANA", RAGE = true, ENERGY = true, COMBO_POINTS = true }, -- Restoration (combo when in cat)
	},
	DEMONHUNTER = {
		[1] = { MAIN = "FURY" },
		[2] = { MAIN = "FURY" },
	},
	DEATHKNIGHT = {
		[1] = { MAIN = "RUNIC_POWER", RUNES = true },
		[2] = { MAIN = "RUNIC_POWER", RUNES = true },
		[3] = { MAIN = "RUNIC_POWER", RUNES = true },
	},
	PALADIN = {
		[1] = { MAIN = "HOLY_POWER", MANA = true },
		[2] = { MAIN = "HOLY_POWER", MANA = true },
		[3] = { MAIN = "HOLY_POWER", MANA = true },
	},
	HUNTER = {
		[1] = { MAIN = "FOCUS" },
		[2] = { MAIN = "FOCUS" },
		[3] = { MAIN = "FOCUS" },
	},
	ROGUE = {
		[1] = { MAIN = "ENERGY", COMBO_POINTS = true },
		[2] = { MAIN = "ENERGY", COMBO_POINTS = true },
		[3] = { MAIN = "ENERGY", COMBO_POINTS = true },
	},
	PRIEST = {
		[1] = { MAIN = "MANA" },
		[2] = { MAIN = "MANA" },
		[3] = { MAIN = "INSANITY", MANA = true },
	},
	SHAMAN = {
		[1] = { MAIN = "MAELSTROM", MANA = true },
		[2] = { MANA = true },
		[3] = { MAIN = "MANA" },
	},
	MAGE = {
		[1] = { MAIN = "ARCANE_CHARGES", MANA = true },
		[2] = { MAIN = "MANA" },
		[3] = { MAIN = "MANA" },
	},
	WARLOCK = {
		[1] = { MAIN = "SOUL_SHARDS", MANA = true },
		[2] = { MAIN = "SOUL_SHARDS", MANA = true },
		[3] = { MAIN = "SOUL_SHARDS", MANA = true },
	},
	MONK = {
		[1] = { MAIN = "ENERGY", MANA = true },
		[2] = { MAIN = "MANA" },
		[3] = { MAIN = "CHI", ENERGY = true, MANA = true },
	},
	EVOKER = {
		[1] = { MAIN = "ESSENCE", MANA = true },
		[2] = { MAIN = "MANA", ESSENCE = true },
		[3] = { MAIN = "ESSENCE", MANA = true },
	},
	WARRIOR = {
		[1] = { MAIN = "RAGE" },
		[2] = { MAIN = "RAGE" },
		[3] = { MAIN = "RAGE" },
	},
}

local powerTypeEnums = {}
for i, v in pairs(Enum.PowerType) do
	powerTypeEnums[i:upper()] = v
end

local classPowerTypes = {
	"RAGE",
	"ESSENCE",
	"FOCUS",
	"ENERGY",
	"FURY",
	"COMBO_POINTS",
	"RUNIC_POWER",
	"RUNES",
	"SOUL_SHARDS",
	"LUNAR_POWER",
	"HOLY_POWER",
	"MAELSTROM",
	"CHI",
	"INSANITY",
	"ARCANE_CHARGES",
	"MANA",
}

ResourceBars.powertypeClasses = powertypeClasses
ResourceBars.classPowerTypes = classPowerTypes
ResourceBars.separatorEligible = {
	HOLY_POWER = true,
	SOUL_SHARDS = true,
	ESSENCE = true,
	ARCANE_CHARGES = true,
	CHI = true,
	COMBO_POINTS = true,
}

function getBarSettings(pType)
	local class = addon.variables.unitClass
	local spec = addon.variables.unitSpec
	if addon.db.personalResourceBarSettings and addon.db.personalResourceBarSettings[class] and addon.db.personalResourceBarSettings[class][spec] then
		return addon.db.personalResourceBarSettings[class][spec][pType]
	end
	return nil
end

function updatePowerBar(type, runeSlot)
	if powerbar[type] and powerbar[type]:IsVisible() then
		-- Special handling for DK Runes: six sub-bars that fill as cooldown progresses
		if type == "RUNES" then
			local bar = powerbar[type]
			local spec = GetSpecialization() or addon.variables.unitSpec
			local r, g, b = 0.8, 0.1, 0.1 -- Blood default
			if spec == 2 then
				r, g, b = 0.2, 0.6, 1.0
			end -- Frost
			if spec == 3 then
				r, g, b = 0.0, 0.9, 0.3
			end -- Unholy
			local grey = 0.35
			bar._rune = bar._rune or {}
			bar._runeOrder = bar._runeOrder or {}
			bar._charging = bar._charging or {}
			local charging = bar._charging
			if runeSlot then
				local count = 0
				for i = 1, 6 do
					local start, duration, readyFlag = GetRuneCooldown(i)
					bar._rune[i] = bar._rune[i] or {}
					bar._rune[i].start = start or 0
					bar._rune[i].duration = duration or 0
					bar._rune[i].ready = readyFlag
					if not readyFlag then
						count = count + 1
						charging[count] = i
					end
				end
				for i = count + 1, #charging do
					charging[i] = nil
				end
				table.sort(charging, function(a, b)
					local ra = bar._rune[a].start + bar._rune[a].duration
					local rb = bar._rune[b].start + bar._rune[b].duration
					return ra < rb
				end)
			else
				local i = 1
				while i <= #charging do
					local idx = charging[i]
					local start, duration, readyFlag = GetRuneCooldown(idx)
					bar._rune[idx] = bar._rune[idx] or {}
					bar._rune[idx].start = start or 0
					bar._rune[idx].duration = duration or 0
					bar._rune[idx].ready = readyFlag
					if readyFlag then
						table.remove(charging, i)
					else
						i = i + 1
					end
				end
			end
			local chargingMap = bar._chargingMap or {}
			bar._chargingMap = chargingMap
			for i = 1, 6 do
				chargingMap[i] = nil
			end
			for _, idx in ipairs(charging) do
				chargingMap[idx] = true
			end
			local pos = 1
			for i = 1, 6 do
				if not chargingMap[i] then
					bar._runeOrder[pos] = i
					pos = pos + 1
				end
			end
			for _, idx in ipairs(charging) do
				bar._runeOrder[pos] = idx
				pos = pos + 1
			end
			for i = pos, #bar._runeOrder do
				bar._runeOrder[i] = nil
			end

			local cfg = getBarSettings("RUNES") or {}
			local anyActive = #charging > 0
			local now = GetTime()
			for i = 1, 6 do
				local runeIndex = bar._runeOrder[i]
				local info = runeIndex and bar._rune[runeIndex]
				local sb = bar.runes and bar.runes[i]
				if sb and info then
					sb:SetMinMaxValues(0, 1)
					local prog = info.ready and 1 or math.min(1, math.max(0, (now - info.start) / math.max(info.duration, 1)))
					sb:SetValue(prog)
					if info.ready or prog >= 1 then
						sb:SetStatusBarColor(r, g, b)
					else
						sb:SetStatusBarColor(grey, grey, grey)
					end
					if sb.fs then
						if cfg.showCooldownText then
							local remain = math.ceil((info.start + info.duration) - now)
							if remain > 0 and not info.ready then
								sb.fs:SetText(tostring(remain))
							else
								sb.fs:SetText("")
							end
						else
							sb.fs:SetText("")
						end
					end
				end
			end

			if anyActive then
				bar._runesAnimating = true
				bar._runeAccum = 0
				local cfgOnUpdate = cfg
				bar:SetScript("OnUpdate", function(self, elapsed)
					self._runeAccum = (self._runeAccum or 0) + (elapsed or 0)
					if self._runeAccum > 0.08 then
						self._runeAccum = 0
						local n = GetTime()
						local allReady = true
						for pos = 1, 6 do
							local ri = self._runeOrder and self._runeOrder[pos]
							local data = ri and self._rune and self._rune[ri]
							local sb = self.runes and self.runes[pos]
							if data and sb then
								local prog
								if data.ready then
									prog = 1
								else
									prog = math.min(1, math.max(0, (n - data.start) / math.max(data.duration, 1)))
									if prog >= 1 then
										updatePowerBar("RUNES")
										return
									end
									allReady = false
								end
								sb:SetValue(prog)
								if sb.fs then
									if cfgOnUpdate.showCooldownText and not data.ready then
										local remain = math.ceil((data.start + data.duration) - n)
										if remain > 0 then
											sb.fs:SetText(tostring(remain))
										else
											sb.fs:SetText("")
										end
									else
										sb.fs:SetText("")
									end
								end
							end
						end
						if allReady then
							self._runesAnimating = false
							self:SetScript("OnUpdate", nil)
						end
					end
				end)
			else
				bar._runesAnimating = false
				bar:SetScript("OnUpdate", nil)
			end
			if bar.text then bar.text:SetText("") end
			return
		end
		local bar = powerbar[type]
		local pType = powerTypeEnums[type:gsub("_", "")]
		local maxPower = bar._lastMax
		if not maxPower then
			maxPower = UnitPowerMax("player", pType)
			bar._lastMax = maxPower
			bar:SetMinMaxValues(0, maxPower)
		end
		local curPower = UnitPower("player", pType)

		local settings = getBarSettings(type)
		local style = settings and settings.textStyle

		if not style then
			if type == "MANA" then
				style = "PERCENT"
			else
				style = "CURMAX"
			end
		end

		if bar._lastVal ~= curPower then
			bar:SetValue(curPower)
			bar._lastVal = curPower
		end
		if bar.text then
			if style == "NONE" then
				bar.text:SetText("")
				bar.text:Hide()
			else
				local text
				if style == "PERCENT" then
					text = tostring(math.floor(((curPower / math.max(maxPower, 1)) * 100) + 0.5))
				elseif style == "CURRENT" then
					text = tostring(curPower)
				else -- CURMAX
					text = curPower .. " / " .. maxPower
				end
				if bar._lastText ~= text then
					bar.text:SetText(text)
					bar._lastText = text
				end
				bar.text:Show()
			end
		end
	end
end

-- Create/update separator ticks for a given bar type if enabled
local function updateBarSeparators(pType)
	local eligible = ResourceBars.separatorEligible
	if not eligible or not eligible[pType] then return end
	local bar = powerbar[pType]
	if not bar then return end
	local cfg = getBarSettings(pType)
	if not (cfg and cfg.showSeparator) then
		if bar.separatorMarks then
			for _, tx in ipairs(bar.separatorMarks) do
				tx:Hide()
			end
		end
		return
	end

	local segments
	if pType == "ENERGY" then
		segments = 10
	elseif pType == "RUNES" then
		segments = 6
	else
		local enumId = powerTypeEnums[pType:gsub("_", "")]
		segments = enumId and UnitPowerMax("player", enumId) or 0
	end
	if not segments or segments < 2 then
		-- Nothing to separate
		if bar.separatorMarks then
			for _, tx in ipairs(bar.separatorMarks) do
				tx:Hide()
			end
		end
		return
	end

	bar.separatorMarks = bar.separatorMarks or {}
	local needed = segments - 1
	local w = math.max(1, bar:GetWidth() or 0)
	local h = math.max(1, bar:GetHeight() or 0)
	local sc = (cfg and cfg.separatorColor) or { 1, 1, 1, 0.5 }
	local r, g, b, a = sc[1] or 1, sc[2] or 1, sc[3] or 1, sc[4] or 0.5

	if bar._sepW == w and bar._sepH == h and bar._sepSegments == segments and bar._sepR == r and bar._sepG == g and bar._sepB == b and bar._sepA == a then return end

	-- Ensure we have enough textures
	for i = #bar.separatorMarks + 1, needed do
		local tx = bar:CreateTexture(nil, "OVERLAY")
		tx:SetColorTexture(r, g, b, a)
		bar.separatorMarks[i] = tx
	end
	-- Position visible separators
	for i = 1, needed do
		local tx = bar.separatorMarks[i]
		tx:ClearAllPoints()
		local frac = i / segments
		local x = math.floor(w * frac + 0.5)
		local half = math.floor(SEPARATOR_THICKNESS * 0.5)
		tx:SetPoint("LEFT", bar, "LEFT", x - math.max(0, half), 0)
		tx:SetSize(SEPARATOR_THICKNESS, h)
		tx:SetColorTexture(r, g, b, a)
		tx:Show()
	end
	-- Hide extras
	for i = needed + 1, #bar.separatorMarks do
		bar.separatorMarks[i]:Hide()
	end
	bar._sepW, bar._sepH, bar._sepSegments, bar._sepR, bar._sepG, bar._sepB, bar._sepA = w, h, segments, r, g, b, a
end

-- Layout helper for DK RUNES: create or resize 6 child statusbars
function layoutRunes(bar)
	if not bar then return end
	bar.runes = bar.runes or {}
	local count = 6
	local gap = 2
	local w = math.max(1, bar:GetWidth() or 0)
	local h = math.max(1, bar:GetHeight() or 0)
	local segW = math.max(1, math.floor((w - gap * (count - 1)) / count + 0.5))
	for i = 1, count do
		local sb = bar.runes[i]
		if not sb then
			sb = CreateFrame("StatusBar", bar:GetName() .. "Rune" .. i, bar)
			sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
			sb:SetMinMaxValues(0, 1)
			sb:Show()
			bar.runes[i] = sb
		end
		sb:ClearAllPoints()
		sb:SetSize(segW, h)
		if i == 1 then
			sb:SetPoint("LEFT", bar, "LEFT", 0, 0)
		else
			sb:SetPoint("LEFT", bar.runes[i - 1], "RIGHT", gap, 0)
		end
		-- cooldown text per segment
		if not sb.fs then
			sb.fs = sb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			sb.fs:SetPoint("CENTER", sb, "CENTER", 0, 0)
		end
		local cfg = getBarSettings("RUNES") or {}
		local show = cfg.showCooldownText == true
		local size = cfg.cooldownTextFontSize or 16
		sb.fs:SetFont(addon.variables.defaultFont, size, "OUTLINE")
		if show then
			sb.fs:Show()
		else
			sb.fs:Hide()
		end
	end
end

local function createPowerBar(type, anchor)
	-- Reuse existing bar if present; avoid destroying frames to preserve anchors
	local bar = powerbar[type] or _G["EQOL" .. type .. "Bar"]
	local isNew = false
	if not bar then
		bar = CreateFrame("StatusBar", "EQOL" .. type .. "Bar", UIParent, "BackdropTemplate")
		isNew = true
	end
	-- Ensure a valid parent when reusing frames after disable
	if bar:GetParent() ~= UIParent then bar:SetParent(UIParent) end

	local settings = getBarSettings(type)
	local w = settings and settings.width or DEFAULT_POWER_WIDTH
	local h = settings and settings.height or DEFAULT_POWER_HEIGHT
	bar:SetSize(w, h)
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
	bar:SetClampedToScreen(true)

	-- Anchor handling: only use fallback anchor if no explicit DB anchor exists
	local a = getAnchor(type, addon.variables.unitSpec)
	local allowMove = true
	if a.point then
		local rel, looped = resolveAnchor(a, type)
		if looped and (a.relativeFrame or "UIParent") ~= "UIParent" then
			-- Loop fallback: recenter on UIParent
			local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
			local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
			a.point = "TOPLEFT"
			a.relativeFrame = "UIParent"
			a.relativePoint = "TOPLEFT"
			a.x = (pw - w) / 2
			a.y = (h - ph) / 2
			rel = UIParent
		end
		if rel and rel.GetName and rel:GetName() ~= "UIParent" then allowMove = false end
		bar:ClearAllPoints()
		bar:SetPoint(a.point, rel or UIParent, a.relativePoint or a.point, a.x or 0, a.y or 0)
	elseif anchor then
		-- Default stack below provided anchor and persist default anchor in DB
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, BAR_STACK_SPACING)
		a.point = "TOPLEFT"
		a.relativeFrame = anchor:GetName() or "UIParent"
		a.relativePoint = "BOTTOMLEFT"
		a.x = 0
		a.y = BAR_STACK_SPACING
	else
		-- No anchor in DB and no previous anchor in code path; default: center on UIParent
		bar:ClearAllPoints()
		local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
		local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
		local cx = (pw - w) / 2
		local cy = (h - ph) / 2
		bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", cx, cy)
		a.point = "TOPLEFT"
		a.relativeFrame = "UIParent"
		a.relativePoint = "TOPLEFT"
		a.x = cx
		a.y = cy
	end

	-- Visuals and text
	bar:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 3,
		insets = { left = 0, right = 0, top = 0, bottom = 0 },
	})
	bar:SetBackdropColor(0, 0, 0, 0.8)
	bar:SetBackdropBorderColor(0, 0, 0, 0)

	local fontSize = settings and settings.fontSize or 16
	if type ~= "RUNES" then
		if not bar.text then bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
		bar.text:SetFont(addon.variables.defaultFont, fontSize, "OUTLINE")
		bar.text:SetPoint("CENTER", bar, "CENTER", 3, 0)
		bar.text:Show()
	else
		if bar.text then
			bar.text:SetText("")
			bar.text:Hide()
		end
		-- Hide parent statusbar texture; we render child rune bars
		local tex = bar:GetStatusBarTexture()
		if tex then tex:SetAlpha(0) end
		layoutRunes(bar)
	end
	bar:SetStatusBarColor(getPowerBarColor(type))

	-- Dragging only when not anchored to another EQOL bar
	bar:SetMovable(allowMove)
	bar:EnableMouse(allowMove)
	if isNew then bar:RegisterForDrag("LeftButton") end
	bar:SetScript("OnDragStart", function(self)
		local ai = getAnchor(type, addon.variables.unitSpec)
		local canMove = (not ai) or ((ai.relativeFrame or "UIParent") == "UIParent")
		if IsShiftKeyDown() and canMove then self:StartMoving() end
	end)
	bar:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, rel, relPoint, xOfs, yOfs = self:GetPoint()
		local info = getAnchor(type, addon.variables.unitSpec)
		local relName = rel and rel.GetName and rel:GetName() or "UIParent"
		if relName == "UIParent" then
			local lx = (self:GetLeft() or 0) - (UIParent:GetLeft() or 0)
			local ly = (self:GetTop() or 0) - (UIParent:GetTop() or 0)
			self:ClearAllPoints()
			self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", lx, ly)
			info.point = "TOPLEFT"
			info.relativeFrame = "UIParent"
			info.relativePoint = "TOPLEFT"
			info.x = lx
			info.y = ly
		else
			info.point = point
			info.relativeFrame = relName
			info.relativePoint = relPoint
			info.x = xOfs
			info.y = yOfs
		end
	end)

	powerbar[type] = bar
	bar:Show()
	updatePowerBar(type)
	updateBarSeparators(type)

	-- Ensure dependents re-anchor when this bar changes size
	bar:SetScript("OnSizeChanged", function()
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorDependentsOf then addon.Aura.ResourceBars.ReanchorDependentsOf("EQOL" .. type .. "Bar") end
		if type == "RUNES" then
			layoutRunes(bar)
		else
			updateBarSeparators(type)
		end
	end)
end

local eventsToRegister = {
	"UNIT_HEALTH",
	"UNIT_MAXHEALTH",
	"UNIT_ABSORB_AMOUNT_CHANGED",
	"UNIT_POWER_UPDATE",
	"UNIT_POWER_FREQUENT",
	"UNIT_DISPLAYPOWER",
	"UNIT_MAXPOWER",
	"UPDATE_SHAPESHIFT_FORM",
}

local function setPowerbars()
	local _, powerToken = UnitPowerType("player")
	powerfrequent = {}
	local isDruid = addon.variables.unitClass == "DRUID"
	local function mapFormNameToKey(name)
		if not name then return nil end
		name = tostring(name):lower()
		if name:find("bear") then return "BEAR" end
		if name:find("cat") then return "CAT" end
		if name:find("travel") or name:find("aquatic") or name:find("flight") or name:find("flight form") then return "TRAVEL" end
		if name:find("moonkin") or name:find("owl") then return "MOONKIN" end
		if name:find("treant") then return "TREANT" end
		if name:find("stag") then return "STAG" end
		return nil
	end
	local function currentDruidForm()
		if not isDruid then return nil end
		local idx = GetShapeshiftForm() or 0
		if idx == 0 then return "HUMANOID" end
		-- Try to resolve by form name at this index
		local name
		if GetShapeshiftFormInfo then
			-- Retail returns (icon, name, isActive, isCastable) or similar; pick second as name if present
			local r1, r2 = GetShapeshiftFormInfo(idx)
			if type(r1) == "string" then
				name = r1
			elseif type(r2) == "string" then
				name = r2
			end
		end
		local key = mapFormNameToKey(name)
		if key then return key end
		-- Fallback to index mapping rules
		if idx == 1 then return "BEAR" end
		if idx == 2 then return "CAT" end
		if idx == 3 then return "TRAVEL" end
		-- 4..6: ordered among Moonkin, Treant, Stag – default mapping
		if idx == 4 then return "MOONKIN" end
		if idx == 5 then return "TREANT" end
		if idx == 6 then return "STAG" end
		return "HUMANOID"
	end
	local druidForm = currentDruidForm()
	local mainPowerBar
	local lastBar
	local specCfg = addon.db.personalResourceBarSettings
		and addon.db.personalResourceBarSettings[addon.variables.unitClass]
		and addon.db.personalResourceBarSettings[addon.variables.unitClass][addon.variables.unitSpec]

	if
		powertypeClasses[addon.variables.unitClass]
		and powertypeClasses[addon.variables.unitClass][addon.variables.unitSpec]
		and powertypeClasses[addon.variables.unitClass][addon.variables.unitSpec].MAIN
	then
		local mType = powertypeClasses[addon.variables.unitClass][addon.variables.unitSpec].MAIN
		-- Only show if explicitly enabled
		if specCfg and specCfg[mType] and specCfg[mType].enabled == true then
			createPowerBar(mType, ((specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true) and EQOLHealthBar or nil))
			mainPowerBar = mType
			lastBar = mainPowerBar
			if powerbar[mainPowerBar] then powerbar[mainPowerBar]:Show() end
		end
	end

	for _, pType in ipairs(classPowerTypes) do
		if powerbar[pType] then powerbar[pType]:Hide() end

		local shouldShow = false
		if specCfg and specCfg[pType] and specCfg[pType].enabled == true then
			if mainPowerBar == pType then
				shouldShow = true
			elseif
				powertypeClasses[addon.variables.unitClass]
				and powertypeClasses[addon.variables.unitClass][addon.variables.unitSpec]
				and powertypeClasses[addon.variables.unitClass][addon.variables.unitSpec][pType]
			then
				shouldShow = true
			end
		end

		if shouldShow then
			-- Per-form filter for Druid
			local formAllowed = true
			if isDruid and specCfg and specCfg[pType] and specCfg[pType].showForms then
				local allowed = specCfg[pType].showForms
				if druidForm and allowed[druidForm] == false then formAllowed = false end
			end
			if formAllowed and addon.variables.unitClass == "DRUID" then
				powerfrequent[pType] = true
				-- Always show main power bar when enabled
				if pType == mainPowerBar then
					if powerbar[pType] then powerbar[pType]:Show() end
				-- Always allow MANA bar (secondary mana)
				elseif pType == "MANA" then
					createPowerBar(pType, powerbar[lastBar] or ((specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true) and EQOLHealthBar or nil))
					lastBar = pType
					if powerbar[pType] then powerbar[pType]:Show() end
				-- Show COMBO_POINTS in Cat form
				elseif pType == "COMBO_POINTS" and druidForm == "CAT" then
					createPowerBar(pType, powerbar[lastBar] or ((specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true) and EQOLHealthBar or nil))
					lastBar = pType
					if powerbar[pType] then powerbar[pType]:Show() end
				-- Otherwise, show if current power token matches (e.g., ENERGY/RAGE/LUNAR_POWER)
				elseif powerToken == pType and powerToken ~= mainPowerBar then
					createPowerBar(pType, powerbar[lastBar] or ((specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true) and EQOLHealthBar or nil))
					lastBar = pType
					if powerbar[pType] then powerbar[pType]:Show() end
				end
			elseif formAllowed then
				powerfrequent[pType] = true
				if mainPowerBar ~= pType then
					createPowerBar(pType, powerbar[lastBar] or ((specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true) and EQOLHealthBar or nil))
					lastBar = pType
				end
				if powerbar[pType] then powerbar[pType]:Show() end
			end
		end
	end

	-- Toggle Health visibility according to config
	if healthBar then
		if specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true then
			healthBar:Show()
		else
			healthBar:Hide()
		end
	end
end

local resourceBarsLoaded = addon.Aura.ResourceBars ~= nil
local function LoadResourceBars()
	if not resourceBarsLoaded then
		addon.Aura.ResourceBars = addon.Aura.ResourceBars or {}
		resourceBarsLoaded = true
	end
end

if addon.db["enableResourceFrame"] then
	local frameLogin = CreateFrame("Frame")
	frameLogin:RegisterEvent("PLAYER_LOGIN")
	frameLogin:SetScript("OnEvent", function(self, event)
		if event == "PLAYER_LOGIN" then
			if addon.db["enableResourceFrame"] then
				LoadResourceBars()
				addon.Aura.ResourceBars.EnableResourceBars()
			end
			frameLogin:UnregisterAllEvents()
			frameLogin:SetScript("OnEvent", nil)
			frameLogin = nil
		end
	end)
end

local function eventHandler(self, event, unit, arg1)
	if event == "UNIT_DISPLAYPOWER" and unit == "player" then
		setPowerbars()
	elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
		C_Timer.After(0.2, function()
			setPowerbars()
			-- Re-anchor once all bars exist, in case of inter-bar dependencies
			C_Timer.After(0.05, function()
				if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorAll then addon.Aura.ResourceBars.ReanchorAll() end
				if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
			end)
		end)
	elseif event == "PLAYER_ENTERING_WORLD" then
		updateHealthBar()
		setPowerbars()
	elseif event == "UPDATE_SHAPESHIFT_FORM" then
		setPowerbars()
		-- After initial creation, run a re-anchor pass to ensure all dependent anchors resolve
		C_Timer.After(0.05, function()
			if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorAll then addon.Aura.ResourceBars.ReanchorAll() end
			if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
		end)
	elseif (event == "UNIT_MAXHEALTH" or event == "UNIT_HEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED") and healthBar and healthBar:IsShown() then
		if event == "UNIT_MAXHEALTH" then
			local max = UnitHealthMax("player")
			healthBar._lastMax = max
			healthBar:SetMinMaxValues(0, max)
		end
		updateHealthBar()
	elseif event == "UNIT_POWER_UPDATE" and powerbar[arg1] and powerbar[arg1]:IsShown() and not powerfrequent[arg1] then
		updatePowerBar(arg1)
	elseif event == "UNIT_POWER_FREQUENT" and powerbar[arg1] and powerbar[arg1]:IsShown() and powerfrequent[arg1] then
		updatePowerBar(arg1)
	elseif event == "UNIT_MAXPOWER" and powerbar[arg1] and powerbar[arg1]:IsShown() then
		local enum = powerTypeEnums[arg1:gsub("_", "")]
		local bar = powerbar[arg1]
		if enum and bar then
			local max = UnitPowerMax("player", enum)
			bar._lastMax = max
			bar:SetMinMaxValues(0, max)
		end
		updatePowerBar(arg1)
		updateBarSeparators(arg1)
	elseif event == "RUNE_POWER_UPDATE" then
		if powerbar["RUNES"] and powerbar["RUNES"]:IsShown() then updatePowerBar("RUNES", arg1) end
	end
end

function ResourceBars.EnableResourceBars()
	if not frameAnchor then
		frameAnchor = CreateFrame("Frame")
		addon.Aura.anchorFrame = frameAnchor
	end
	for _, event in ipairs(eventsToRegister) do
		-- Register unit vs non-unit events correctly
		if event == "UPDATE_SHAPESHIFT_FORM" then
			frameAnchor:RegisterEvent(event)
		else
			frameAnchor:RegisterUnitEvent(event, "player")
		end
	end
	frameAnchor:RegisterEvent("PLAYER_ENTERING_WORLD")
	frameAnchor:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
	frameAnchor:RegisterEvent("TRAIT_CONFIG_UPDATED")
	frameAnchor:SetScript("OnEvent", eventHandler)
	frameAnchor:Hide()

	createHealthBar()
	-- Build bars and anchor immediately; no deferred timers needed
	if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.Refresh then
		addon.Aura.ResourceBars.Refresh()
	else
		if setPowerbars then setPowerbars() end
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorAll then addon.Aura.ResourceBars.ReanchorAll() end
	end
	if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
end

function ResourceBars.DisableResourceBars()
	if frameAnchor then
		frameAnchor:UnregisterAllEvents()
		frameAnchor:SetScript("OnEvent", nil)
		frameAnchor = nil
		addon.Aura.anchorFrame = nil
	end
	if mainFrame then
		mainFrame:Hide()
		-- Keep parent to preserve frame and anchors for reuse
		mainFrame = nil
	end
	if healthBar then
		healthBar:Hide()
		-- Keep parent to preserve frame and anchors for reuse
		healthBar = nil
	end
	for pType, bar in pairs(powerbar) do
		if bar then
			bar:Hide()
			if pType == "RUNES" then
				bar:SetScript("OnUpdate", nil)
				bar._runesAnimating = false
			end
		end
		powerbar[pType] = nil
	end
	powerbar = {}
end

-- Register/unregister DK rune event depending on class and user config
function ResourceBars.UpdateRuneEventRegistration()
	if not frameAnchor then return end
	local isDK = addon.variables.unitClass == "DEATHKNIGHT"
	local spec = addon.variables.unitSpec
	local cfg = addon.db.personalResourceBarSettings and addon.db.personalResourceBarSettings[addon.variables.unitClass] and addon.db.personalResourceBarSettings[addon.variables.unitClass][spec]
	local enabled = isDK and cfg and cfg.RUNES and (cfg.RUNES.enabled == true)
	if enabled and not frameAnchor._runeEvtRegistered then
		frameAnchor:RegisterEvent("RUNE_POWER_UPDATE")
		frameAnchor._runeEvtRegistered = true
	elseif (not enabled) and frameAnchor._runeEvtRegistered then
		frameAnchor:UnregisterEvent("RUNE_POWER_UPDATE")
		frameAnchor._runeEvtRegistered = false
		if powerbar and powerbar.RUNES then
			powerbar.RUNES:SetScript("OnUpdate", nil)
			powerbar.RUNES._runesAnimating = false
		end
	end
end

local function getFrameName(pType)
	if pType == "HEALTH" then return "EQOLHealthBar" end
	return "EQOL" .. pType .. "Bar"
end

function ResourceBars.DetachAnchorsFrom(disabledType, specIndex)
	local class = addon.variables.unitClass
	local spec = specIndex or addon.variables.unitSpec

	if not addon.db.personalResourceBarSettings or not addon.db.personalResourceBarSettings[class] or not addon.db.personalResourceBarSettings[class][spec] then return end

	local specCfg = addon.db.personalResourceBarSettings[class][spec]
	local targetName = getFrameName(disabledType)
	local disabledAnchor = getAnchor(disabledType, spec)
	local upstreamName = disabledAnchor and disabledAnchor.relativeFrame or "UIParent"

	for pType, cfg in pairs(specCfg) do
		if pType ~= disabledType and cfg.anchor and cfg.anchor.relativeFrame == targetName then
			local depFrame = _G[getFrameName(pType)]
			local upstream = _G[upstreamName]
			if upstreamName ~= "UIParent" and upstream then
				-- Reattach below the disabled bar's upstream anchor target for intuitive stacking
				cfg.anchor.point = "TOPLEFT"
				cfg.anchor.relativeFrame = upstreamName
				cfg.anchor.relativePoint = "BOTTOMLEFT"
				cfg.anchor.x = 0
				cfg.anchor.y = 0
			else
				-- Fallback to centered on UIParent (TOPLEFT/TOPLEFT offsets to center)
				local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
				local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
				-- Determine dependent frame size (fallback to defaults by bar type)
				local cfgDep = getBarSettings(pType)
				local defaultW = (pType == "HEALTH") and DEFAULT_HEALTH_WIDTH or DEFAULT_POWER_WIDTH
				local defaultH = (pType == "HEALTH") and DEFAULT_HEALTH_HEIGHT or DEFAULT_POWER_HEIGHT
				local w = (depFrame and depFrame.GetWidth and depFrame:GetWidth()) or (cfgDep and cfgDep.width) or defaultW or 0
				local h = (depFrame and depFrame.GetHeight and depFrame:GetHeight()) or (cfgDep and cfgDep.height) or defaultH or 0
				cfg.anchor.point = "TOPLEFT"
				cfg.anchor.relativeFrame = "UIParent"
				cfg.anchor.relativePoint = "TOPLEFT"
				cfg.anchor.x = (pw - w) / 2
				cfg.anchor.y = (h - ph) / 2
			end
		end
	end
end

function ResourceBars.SetHealthBarSize(w, h)
	if healthBar then healthBar:SetSize(w, h) end
end

function ResourceBars.SetPowerBarSize(w, h, pType)
	local changed = {}
	-- Ensure sane defaults if nil provided
	if pType then
		local s = getBarSettings(pType)
		local defaultW = DEFAULT_POWER_WIDTH
		local defaultH = DEFAULT_POWER_HEIGHT
		w = w or (s and s.width) or defaultW
		h = h or (s and s.height) or defaultH
	end
	if pType then
		if powerbar[pType] then
			powerbar[pType]:SetSize(w, h)
			changed[getFrameName(pType)] = true
			updateBarSeparators(pType)
		end
	else
		for t, bar in pairs(powerbar) do
			bar:SetSize(w, h)
			changed[getFrameName(t)] = true
			updateBarSeparators(t)
		end
	end

	local class = addon.variables.unitClass
	local spec = addon.variables.unitSpec
	local specCfg = addon.db.personalResourceBarSettings and addon.db.personalResourceBarSettings[class] and addon.db.personalResourceBarSettings[class][spec]

	if specCfg then
		for bType, cfg in pairs(specCfg) do
			local anchor = cfg.anchor
			if anchor and changed[anchor.relativeFrame] then
				local frame = bType == "HEALTH" and healthBar or powerbar[bType]
				if frame then
					local rel = _G[anchor.relativeFrame] or UIParent
					-- Ensure we don't accumulate multiple points to stale relatives
					frame:ClearAllPoints()
					frame:SetPoint(anchor.point or "CENTER", rel, anchor.relativePoint or anchor.point or "CENTER", anchor.x or 0, anchor.y or 0)
				end
			end
		end
	end
end

-- Re-apply anchors for any bars that currently reference a given frame name
function ResourceBars.ReanchorDependentsOf(frameName)
	local class = addon.variables.unitClass
	local spec = addon.variables.unitSpec
	local specCfg = addon.db.personalResourceBarSettings and addon.db.personalResourceBarSettings[class] and addon.db.personalResourceBarSettings[class][spec]
	if not specCfg then return end

	for bType, cfg in pairs(specCfg) do
		local anch = cfg and cfg.anchor
		if anch and anch.relativeFrame == frameName then
			local frame = (bType == "HEALTH") and healthBar or powerbar[bType]
			if frame then
				local rel = _G[anch.relativeFrame] or UIParent
				frame:ClearAllPoints()
				frame:SetPoint(anch.point or "TOPLEFT", rel, anch.relativePoint or anch.point or "TOPLEFT", anch.x or 0, anch.y or 0)
			end
		end
	end
end

function ResourceBars.Refresh()
	setPowerbars()
	-- Re-apply anchors so option changes take effect immediately
	if healthBar then
		local a = getAnchor("HEALTH", addon.variables.unitSpec)
		if (a.relativeFrame or "UIParent") == "UIParent" then
			a.point = a.point or "TOPLEFT"
			a.relativePoint = a.relativePoint or "TOPLEFT"
			if a.x == nil or a.y == nil then
				local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
				local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
				local w = healthBar:GetWidth() or DEFAULT_HEALTH_WIDTH
				local h = healthBar:GetHeight() or DEFAULT_HEALTH_HEIGHT
				a.x = (pw - w) / 2
				a.y = (h - ph) / 2
			end
		end
		local rel, looped = resolveAnchor(a, "HEALTH")
		if looped and (a.relativeFrame or "UIParent") ~= "UIParent" then
			local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
			local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
			local w = healthBar:GetWidth() or DEFAULT_HEALTH_WIDTH
			local h = healthBar:GetHeight() or DEFAULT_HEALTH_HEIGHT
			a.point = "TOPLEFT"
			a.relativeFrame = "UIParent"
			a.relativePoint = "TOPLEFT"
			a.x = (pw - w) / 2
			a.y = (h - ph) / 2
			rel = UIParent
		end
		healthBar:ClearAllPoints()
		healthBar:SetPoint(a.point or "TOPLEFT", rel, a.relativePoint or a.point or "TOPLEFT", a.x or 0, a.y or 0)
	end
	for pType, bar in pairs(powerbar) do
		if bar then
			local a = getAnchor(pType, addon.variables.unitSpec)
			if (a.relativeFrame or "UIParent") == "UIParent" then
				a.point = a.point or "TOPLEFT"
				a.relativePoint = a.relativePoint or "TOPLEFT"
				if a.x == nil or a.y == nil then
					local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
					local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
					local w = bar:GetWidth() or DEFAULT_POWER_WIDTH
					local h = bar:GetHeight() or DEFAULT_POWER_HEIGHT
					a.x = (pw - w) / 2
					a.y = (h - ph) / 2
				end
			end
			local rel, looped = resolveAnchor(a, pType)
			if looped and (a.relativeFrame or "UIParent") ~= "UIParent" then
				local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
				local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
				local w = bar:GetWidth() or DEFAULT_POWER_WIDTH
				local h = bar:GetHeight() or DEFAULT_POWER_HEIGHT
				a.point = "TOPLEFT"
				a.relativeFrame = "UIParent"
				a.relativePoint = "TOPLEFT"
				a.x = (pw - w) / 2
				a.y = (h - ph) / 2
				rel = UIParent
			end
			bar:ClearAllPoints()
			bar:SetPoint(a.point or "TOPLEFT", rel, a.relativePoint or a.point or "TOPLEFT", a.x or 0, a.y or 0)
			-- Update movability based on anchor target (only movable when relative to UIParent)
			local isUI = (a.relativeFrame or "UIParent") == "UIParent"
			bar:SetMovable(isUI)
			bar:EnableMouse(isUI)
			if pType == "RUNES" then
				layoutRunes(bar)
				updatePowerBar("RUNES")
			else
				updateBarSeparators(pType)
			end
		end
	end
	-- Apply text font sizes without forcing full rebuild
	local class = addon.variables.unitClass
	local spec = addon.variables.unitSpec
	local specCfg = addon.db.personalResourceBarSettings and addon.db.personalResourceBarSettings[class] and addon.db.personalResourceBarSettings[class][spec]

	if healthBar and healthBar.text then
		local hCfg = specCfg and specCfg.HEALTH
		local fs = hCfg and hCfg.fontSize or 16
		healthBar.text:SetFont(addon.variables.defaultFont, fs, "OUTLINE")
	end

	for pType, bar in pairs(powerbar) do
		if bar and bar.text then
			local cfg = specCfg and specCfg[pType]
			local fs = cfg and cfg.fontSize or 16
			bar.text:SetFont(addon.variables.defaultFont, fs, "OUTLINE")
		end
	end
	updateHealthBar()
	if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
	-- Ensure RUNES animation stops when not visible/enabled
	local spec = addon.variables.unitSpec
	local cfg = addon.db.personalResourceBarSettings and addon.db.personalResourceBarSettings[addon.variables.unitClass] and addon.db.personalResourceBarSettings[addon.variables.unitClass][spec]
	local runesEnabled = cfg and cfg.RUNES and (cfg.RUNES.enabled == true)
	if powerbar and powerbar.RUNES and (not powerbar.RUNES:IsShown() or not runesEnabled) then
		powerbar.RUNES:SetScript("OnUpdate", nil)
		powerbar.RUNES._runesAnimating = false
	end
end

-- Only refresh live bars when editing the active spec
function ResourceBars.MaybeRefreshActive(specIndex)
	if specIndex == addon.variables.unitSpec then ResourceBars.Refresh() end
end

-- Re-anchor pass only: reapplies anchor points without rebuilding bars
function ResourceBars.ReanchorAll()
	-- Health first
	if healthBar then
		local a = getAnchor("HEALTH", addon.variables.unitSpec)
		if (a.relativeFrame or "UIParent") == "UIParent" then
			a.point = a.point or "TOPLEFT"
			a.relativePoint = a.relativePoint or "TOPLEFT"
			if a.x == nil or a.y == nil then
				local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
				local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
				local w = healthBar:GetWidth() or DEFAULT_HEALTH_WIDTH
				local h = healthBar:GetHeight() or DEFAULT_HEALTH_HEIGHT
				a.x = (pw - w) / 2
				a.y = (h - ph) / 2
			end
		end
		local rel, looped = resolveAnchor(a, "HEALTH")
		if looped and (a.relativeFrame or "UIParent") ~= "UIParent" then
			local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
			local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
			local w = healthBar:GetWidth() or DEFAULT_HEALTH_WIDTH
			local h = healthBar:GetHeight() or DEFAULT_HEALTH_HEIGHT
			a.point = "TOPLEFT"
			a.relativeFrame = "UIParent"
			a.relativePoint = "TOPLEFT"
			a.x = (pw - w) / 2
			a.y = (h - ph) / 2
			rel = UIParent
		end
		healthBar:ClearAllPoints()
		healthBar:SetPoint(a.point or "TOPLEFT", rel, a.relativePoint or a.point or "TOPLEFT", a.x or 0, a.y or 0)
	end

	-- Then power bars
	for pType, bar in pairs(powerbar) do
		if bar then
			local a = getAnchor(pType, addon.variables.unitSpec)
			if (a.relativeFrame or "UIParent") == "UIParent" then
				a.point = a.point or "TOPLEFT"
				a.relativePoint = a.relativePoint or "TOPLEFT"
				if a.x == nil or a.y == nil then
					local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
					local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
					local w = bar:GetWidth() or DEFAULT_POWER_WIDTH
					local h = bar:GetHeight() or DEFAULT_POWER_HEIGHT
					a.x = (pw - w) / 2
					a.y = (h - ph) / 2
				end
			end
			local rel, looped = resolveAnchor(a, pType)
			if looped and (a.relativeFrame or "UIParent") ~= "UIParent" then
				local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
				local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
				local w = bar:GetWidth() or DEFAULT_POWER_WIDTH
				local h = bar:GetHeight() or DEFAULT_POWER_HEIGHT
				a.point = "TOPLEFT"
				a.relativeFrame = "UIParent"
				a.relativePoint = "TOPLEFT"
				a.x = (pw - w) / 2
				a.y = (h - ph) / 2
				rel = UIParent
			end
			bar:ClearAllPoints()
			bar:SetPoint(a.point or "TOPLEFT", rel, a.relativePoint or a.point or "TOPLEFT", a.x or 0, a.y or 0)
			-- Movability based on anchor
			local isUI = (a.relativeFrame or "UIParent") == "UIParent"
			bar:SetMovable(isUI)
			bar:EnableMouse(isUI)
		end
	end

	updateHealthBar()
end

-- Debug helper: prints current anchor DB and effective point info
function ResourceBars.DebugAnchors()
	local class = addon.variables.unitClass
	local spec = addon.variables.unitSpec
	local specCfg = addon.db.personalResourceBarSettings and addon.db.personalResourceBarSettings[class] and addon.db.personalResourceBarSettings[class][spec]
	if not specCfg then
		print("EQOL: no specCfg")
		return
	end
	local function dumpOne(name, frame)
		local cfg = specCfg[name]
		local a = cfg and cfg.anchor or {}
		local rp = a.relativeFrame or "UIParent"
		local p, r, rp2, x, y = frame and frame:GetPoint() or nil
		local rn = (r and r.GetName and r:GetName()) or "?"
		print(
			string.format(
				"%s: DB-> %s %s/%s %+d %+d | RT-> %s %s/%s %+d %+d",
				name,
				tostring(a.point or "?"),
				tostring(rp),
				tostring(a.relativePoint or a.point or "?"),
				tonumber(a.x or 0),
				tonumber(a.y or 0),
				tostring(p or "?"),
				tostring(rn or "?"),
				tostring(rp2 or "?"),
				tonumber(x or 0),
				tonumber(y or 0)
			)
		)
	end
	dumpOne("HEALTH", _G["EQOLHealthBar"])
	for _, pType in ipairs(classPowerTypes) do
		dumpOne(pType, _G[getFrameName(pType)])
	end
end

return ResourceBars
--@end-debug@
