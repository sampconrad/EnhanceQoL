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

local frameAnchor
local mainFrame
local healthBar
local powerbar = {}
local powerfrequent = {}
local getBarSettings
local getAnchor
local layoutRunes
local lastTabIndex
local lastBarSelectionPerSpec = {}
local BAR_STACK_SPACING = -4
local SEPARATOR_THICKNESS = 1

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
			if pType == "HEALTH" then return "Health" end
			local s = _G[pType]
			if type(s) == "string" and s ~= "" then return s end
			return pType
		end

		local function addAnchorOptions(barType, parent, info, frameList)
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

            local dropFrame = addon.functions.createDropdownAce(L["Relative Frame"], filtered, nil, nil)
			local initial = info.relativeFrame or "UIParent"
			if not filtered[initial] then initial = "UIParent" end
			dropFrame:SetValue(initial)
			parent:AddChild(dropFrame)

			-- Sub-group we can rebuild when relative frame changes
			local anchorSub = addon.functions.createContainer("SimpleGroup", "Flow")
			parent:AddChild(anchorSub)

			local function buildAnchorSub()
				anchorSub:ReleaseChildren()
				local relName = info.relativeFrame or "UIParent"
				if relName ~= "UIParent" then
                    local dropPoint = addon.functions.createDropdownAce(RESAMPLE_QUALITY_POINT, anchorPoints, anchorOrder, function(self, _, val)
						info.point = val
						if addon.Aura.ResourceBars then addon.Aura.ResourceBars.Refresh() end
					end)
					dropPoint:SetValue(info.point or "TOPLEFT")
					dropPoint:SetFullWidth(false)
					dropPoint:SetRelativeWidth(0.5)
					anchorSub:AddChild(dropPoint)

                    local dropRelPoint = addon.functions.createDropdownAce(L["Relative Point"], anchorPoints, anchorOrder, function(self, _, val)
						info.relativePoint = val
						if addon.Aura.ResourceBars then addon.Aura.ResourceBars.Refresh() end
					end)
					dropRelPoint:SetValue(info.relativePoint or info.point or "TOPLEFT")
					dropRelPoint:SetFullWidth(false)
					dropRelPoint:SetRelativeWidth(0.5)
					anchorSub:AddChild(dropRelPoint)

					local editX = addon.functions.createEditboxAce("X", tostring(info.x or 0), function(self)
						info.x = tonumber(self:GetText()) or 0
						if addon.Aura.ResourceBars then addon.Aura.ResourceBars.Refresh() end
					end)
					editX:SetFullWidth(false)
					editX:SetRelativeWidth(0.5)
					anchorSub:AddChild(editX)

					local editY = addon.functions.createEditboxAce("Y", tostring(info.y or 0), function(self)
						info.y = tonumber(self:GetText()) or 0
						if addon.Aura.ResourceBars then addon.Aura.ResourceBars.Refresh() end
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
			end

			-- Initial build
			buildAnchorSub()

			dropFrame:SetCallback("OnValueChanged", function(self, _, val)
				local prev = info.relativeFrame or "UIParent"
				info.relativeFrame = val
				-- Behavior tweaks:
				-- A) Switching TO a non-UIParent frame: default to TOPLEFT/BOTTOMLEFT just below, with 0/0 offsets.
				if val ~= "UIParent" then
					info.point = "TOPLEFT"
					info.relativePoint = "BOTTOMLEFT"
					info.x = 0
					info.y = 0
				end
				-- B) Switching TO UIParent (only if previous wasn't UIParent):
				--    compute TOPLEFT/TOPLEFT offsets so the bar appears centered on screen.
				if val == "UIParent" and prev ~= "UIParent" then
					-- Determine current (or configured) frame size to center properly
					local cfg = getBarSettings(barType)
					local defaultW = barType == "HEALTH" and addon.db.personalResourceBarHealthWidth or addon.db.personalResourceBarManaWidth
					local defaultH = barType == "HEALTH" and addon.db.personalResourceBarHealthHeight or addon.db.personalResourceBarManaHeight
					local w = (cfg and cfg.width) or defaultW or 0
					local h = (cfg and cfg.height) or defaultH or 0
					local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
					local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
					-- Centered position while using TOPLEFT/TOPLEFT anchors
					info.point = "TOPLEFT"
					info.relativePoint = "TOPLEFT"
					info.x = (pw - w) / 2
					info.y = (h - ph) / 2
				end
				buildAnchorSub()
				if addon.Aura.ResourceBars then addon.Aura.ResourceBars.Refresh() end
			end)

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
                            width = addon.db.personalResourceBarManaWidth,
                            height = addon.db.personalResourceBarManaHeight,
                            textStyle = pType == "MANA" and "PERCENT" or "CURMAX",
                            fontSize = 16,
                            showSeparator = false,
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
                    width = addon.db.personalResourceBarHealthWidth,
                    height = addon.db.personalResourceBarHealthHeight,
                    textStyle = "PERCENT",
                    fontSize = 16,
                    anchor = {},
                }
			do
				local hcfg = dbSpec.HEALTH
                local cbH = addon.functions.createCheckboxAce(HEALTH, hcfg.enabled == true, function(self, _, val)
                    if (hcfg.enabled == true) and not val then addon.Aura.ResourceBars.DetachAnchorsFrom("HEALTH", specIndex) end
                    hcfg.enabled = val
                    addon.Aura.ResourceBars.Refresh()
                    buildSpec(container, specIndex)
                end)
				cbH:SetFullWidth(false)
				cbH:SetRelativeWidth(0.33)
				groupToggles:AddChild(cbH)
			end
			for pType in pairs(available) do
				if pType ~= "HEALTH" then
					local cfg = dbSpec[pType]
					local label = _G[pType] or pType
                    local cb = addon.functions.createCheckboxAce(label, cfg.enabled == true, function(self, _, val)
                        if (cfg.enabled == true) and not val then addon.Aura.ResourceBars.DetachAnchorsFrom(pType, specIndex) end
                        cfg.enabled = val
                        addon.Aura.ResourceBars.Refresh()
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
                        cfgList[pType] = _G[pType] or pType
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
			-- Use localized display names for EQOL bars (keys remain the actual frame names)
            frames.EQOLHealthBar = (displayNameForBarType and displayNameForBarType("HEALTH") or HEALTH) .. " " .. L["BarSuffix"]
			for _, t in ipairs(addon.Aura.ResourceBars.classPowerTypes) do
				if t ~= sel and dbSpec[t] and dbSpec[t].enabled ~= false then
                    frames["EQOL" .. t .. "Bar"] = (displayNameForBarType and displayNameForBarType(t) or (_G[t] or t)) .. " " .. L["BarSuffix"]
				end
			end

			if sel == "HEALTH" then
				local hCfg = dbSpec.HEALTH
				-- Size
                local sw = addon.functions.createSliderAce(HUD_EDIT_MODE_SETTING_CHAT_FRAME_WIDTH, hCfg.width or addon.db.personalResourceBarHealthWidth, 1, 2000, 1, function(self, _, val)
					hCfg.width = val
					addon.Aura.ResourceBars.SetHealthBarSize(hCfg.width, hCfg.height or addon.db.personalResourceBarHealthHeight)
				end)
				groupConfig:AddChild(sw)
                local sh = addon.functions.createSliderAce(HUD_EDIT_MODE_SETTING_CHAT_FRAME_HEIGHT, hCfg.height or addon.db.personalResourceBarHealthHeight, 1, 2000, 1, function(self, _, val)
					hCfg.height = val
					addon.Aura.ResourceBars.SetHealthBarSize(hCfg.width or addon.db.personalResourceBarHealthWidth, hCfg.height)
				end)
				groupConfig:AddChild(sh)

				-- Text style
                local tList = { PERCENT = STATUS_TEXT_PERCENT, CURMAX = L["Current/Max"], CURRENT = L["Current"], NONE = NONE }
                local tOrder = { "PERCENT", "CURMAX", "CURRENT", "NONE" }
                local dropT = addon.functions.createDropdownAce(L["Text"], tList, tOrder, function(self, _, key)
					hCfg.textStyle = key
					addon.Aura.ResourceBars.Refresh()
				end)
				dropT:SetValue(hCfg.textStyle or "PERCENT")
				groupConfig:AddChild(dropT)

				-- Font size
                local sFont = addon.functions.createSliderAce(HUD_EDIT_MODE_SETTING_OBJECTIVE_TRACKER_TEXT_SIZE, hCfg.fontSize or 16, 6, 64, 1, function(self, _, val)
					hCfg.fontSize = val
					addon.Aura.ResourceBars.Refresh()
				end)
				groupConfig:AddChild(sFont)

				addAnchorOptions("HEALTH", groupConfig, hCfg.anchor, frames)
			else
				local cfg = dbSpec[sel] or {}
				local defaultW = addon.db.personalResourceBarManaWidth
				local defaultH = addon.db.personalResourceBarManaHeight
				local curW = cfg.width or defaultW
				local curH = cfg.height or defaultH
				local defaultStyle = (sel == "MANA") and "PERCENT" or "CURMAX"
				local curStyle = cfg.textStyle or defaultStyle
				local curFont = cfg.fontSize or 16

                local sw = addon.functions.createSliderAce(HUD_EDIT_MODE_SETTING_CHAT_FRAME_WIDTH, curW, 1, 2000, 1, function(self, _, val)
					cfg.width = val
					addon.Aura.ResourceBars.SetPowerBarSize(val, cfg.height or defaultH, sel)
				end)
				groupConfig:AddChild(sw)
                local sh = addon.functions.createSliderAce(HUD_EDIT_MODE_SETTING_CHAT_FRAME_HEIGHT, curH, 1, 2000, 1, function(self, _, val)
					cfg.height = val
					addon.Aura.ResourceBars.SetPowerBarSize(cfg.width or defaultW, val, sel)
				end)
				groupConfig:AddChild(sh)

            if sel ~= "RUNES" then
                local tList = { PERCENT = STATUS_TEXT_PERCENT, CURMAX = L["Current/Max"], CURRENT = L["Current"], NONE = NONE }
                local tOrder = { "PERCENT", "CURMAX", "CURRENT", "NONE" }
                local drop = addon.functions.createDropdownAce(L["Text"], tList, tOrder, function(self, _, key)
                    cfg.textStyle = key
                    addon.Aura.ResourceBars.Refresh()
                end)
                drop:SetValue(curStyle)
				groupConfig:AddChild(drop)

                local sFont = addon.functions.createSliderAce(HUD_EDIT_MODE_SETTING_OBJECTIVE_TRACKER_TEXT_SIZE, curFont, 6, 64, 1, function(self, _, val)
                    cfg.fontSize = val
                    addon.Aura.ResourceBars.Refresh()
                end)
                groupConfig:AddChild(sFont)
            else
                -- RUNES specific options
                local cbRT = addon.functions.createCheckboxAce(L["Show cooldown text"], cfg.showCooldownText == true, function(self, _, val)
                    cfg.showCooldownText = val and true or false
                    addon.Aura.ResourceBars.Refresh()
                end)
                groupConfig:AddChild(cbRT)

                local sRTFont = addon.functions.createSliderAce(L["Cooldown Text Size"], cfg.cooldownTextFontSize or 16, 6, 64, 1, function(self, _, val)
                    cfg.cooldownTextFontSize = val
                    addon.Aura.ResourceBars.Refresh()
                end)
                groupConfig:AddChild(sRTFont)
            end

				-- Separator toggle for eligible resource types
				local eligible = addon.Aura.ResourceBars.separatorEligible
				if eligible and eligible[sel] then
                    local cbSep = addon.functions.createCheckboxAce(L["Show separator"], cfg.showSeparator == true, function(self, _, val)
						cfg.showSeparator = val and true or false
						addon.Aura.ResourceBars.Refresh()
					end)
					groupConfig:AddChild(cbSep)
				end

				addAnchorOptions(sel, groupConfig, cfg.anchor, frames)
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
		local maxHealth = UnitHealthMax("player")
		local curHealth = UnitHealth("player")
		local absorb = UnitGetTotalAbsorbs("player") or 0

		local percent = (curHealth / math.max(maxHealth, 1)) * 100
		local percentStr = string.format("%.0f", percent)
		healthBar:SetMinMaxValues(0, maxHealth)
		healthBar:SetValue(curHealth)
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
                healthBar.text:SetText(text)
                healthBar.text:Show()
            end
        end
		if percent >= 60 then
			healthBar:SetStatusBarColor(0, 0.7, 0)
		elseif percent >= 40 then
			healthBar:SetStatusBarColor(0.7, 0.7, 0)
		else
			healthBar:SetStatusBarColor(0.7, 0, 0)
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
		mainFrame:Show()
		healthBar:Show()
		return
	end

	mainFrame = CreateFrame("frame", "EQOLResourceFrame", UIParent)
	healthBar = CreateFrame("StatusBar", "EQOLHealthBar", UIParent, "BackdropTemplate")
	do
		local cfg = getBarSettings("HEALTH")
		local w = (cfg and cfg.width) or addon.db["personalResourceBarHealthWidth"]
		local h = (cfg and cfg.height) or addon.db["personalResourceBarHealthHeight"]
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
		local w = healthBar:GetWidth() or 0
		local h = healthBar:GetHeight() or 0
		anchor.point = "TOPLEFT"
		anchor.relativeFrame = "UIParent"
		anchor.relativePoint = "TOPLEFT"
		anchor.x = (pw - w) / 2
		anchor.y = (h - ph) / 2
		rel = UIParent
	end
	healthBar:ClearAllPoints()
	healthBar:SetPoint(anchor.point or "CENTER", rel, anchor.relativePoint or anchor.point or "CENTER", anchor.x or 0, anchor.y or 0)
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
		[1] = { MAIN = "LUNAR_POWER", RAGE = true, ENERGY = true, MANA = true }, -- Balance
		[2] = { MAIN = "ENERGY", COMBO_POINTS = true, RAGE = true, MANA = true }, -- Feral (no Astral Power)
		[3] = { MAIN = "RAGE", ENERGY = true, MANA = true, COMBO_POINTS = true }, -- Guardian (no Astral Power)
		[4] = { MAIN = "MANA", RAGE = true, ENERGY = true, COMBO_POINTS = true, LUNAR_POWER = true }, -- Restoration (combo when in cat)
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
    ENERGY = true,
    HOLY_POWER = true,
    SOUL_SHARDS = true,
    ESSENCE = true,
    ARCANE_CHARGES = true,
    CHI = true,
}

function getBarSettings(pType)
	local class = addon.variables.unitClass
	local spec = addon.variables.unitSpec
	if addon.db.personalResourceBarSettings and addon.db.personalResourceBarSettings[class] and addon.db.personalResourceBarSettings[class][spec] then
		return addon.db.personalResourceBarSettings[class][spec][pType]
	end
	return nil
end

local function updatePowerBar(type)
    if powerbar[type] and powerbar[type]:IsVisible() then
        -- Special handling for DK Runes: six sub-bars that fill as cooldown progresses
        if type == "RUNES" then
            local bar = powerbar[type]
            layoutRunes(bar)
            local spec = GetSpecialization() or addon.variables.unitSpec
            local r, g, b = 0.8, 0.1, 0.1 -- Blood default
            if spec == 2 then r, g, b = 0.2, 0.6, 1.0 end -- Frost
            if spec == 3 then r, g, b = 0.0, 0.9, 0.3 end -- Unholy
            local grey = 0.35
            local now = GetTime()
            local charging = {}
            local readyCount = 0
            local anyActive = false
            for i = 1, 6 do
                local start, duration, ready = GetRuneCooldown(i)
                if ready then
                    readyCount = readyCount + 1
                else
                    local remain = 0
                    local prog = 0
                    if start and duration and duration > 0 then
                        remain = math.max(0, (start + duration) - now)
                        prog = math.min(1, math.max(0, (now - start) / duration))
                        if prog > 0 and prog < 1 then anyActive = true end
                    end
                    table.insert(charging, { remain = remain, progress = prog, duration = duration or 0, start = start or 0 })
                end
            end
            table.sort(charging, function(a, b) return a.remain < b.remain end)
            local empties = #charging
            local leftReadyEnd = 6 - empties -- positions 1..leftReadyEnd are full

            -- Fill ready segments (left side)
            for pos = 1, leftReadyEnd do
                local sb = bar.runes and bar.runes[pos]
                if sb then
                    sb:SetMinMaxValues(0, 1)
                    sb:SetValue(1)
                    sb:SetStatusBarColor(r, g, b)
                    if sb.fs then sb.fs:SetText(""); sb.fs:Hide() end
                end
            end

            -- Fill charging segments from left to right among the empty section
            local cfg = getBarSettings("RUNES") or {}
            for idx = 1, empties do
                local info = charging[idx]
                local pos = leftReadyEnd + idx
                local sb = bar.runes and bar.runes[pos]
                if sb then
                    sb:SetMinMaxValues(0, 1)
                    sb:SetValue(info.progress or 0)
                    if (info.progress or 0) >= 1 then
                        sb:SetStatusBarColor(r, g, b)
                    else
                        sb:SetStatusBarColor(grey, grey, grey)
                    end
                    if sb.fs then
                        if cfg.showCooldownText then
                            local t = math.ceil(info.remain or 0)
                            if t > 0 and (info.progress or 0) < 1 then sb.fs:SetText(tostring(t)) else sb.fs:SetText("") end
                            local size = cfg.cooldownTextFontSize or 16
                            sb.fs:SetFont(addon.variables.defaultFont, size, "OUTLINE")
                            sb.fs:Show()
                        else
                            sb.fs:Hide()
                        end
                    end
                end
            end

            -- Toggle animation only when at least one rune is actively recharging
            if anyActive and not bar._runesAnimating then
                bar._runesAnimating = true
                bar._runeAccum = 0
                bar:SetScript("OnUpdate", function(self, elapsed)
                    self._runeAccum = (self._runeAccum or 0) + (elapsed or 0)
                    if self._runeAccum > 0.08 then
                        self._runeAccum = 0
                        updatePowerBar("RUNES")
                    end
                end)
            elseif not anyActive and bar._runesAnimating then
                bar._runesAnimating = false
                bar:SetScript("OnUpdate", nil)
            end
            if bar.text then bar.text:SetText("") end
            return
        end
        local pType = powerTypeEnums[type:gsub("_", "")]
        local maxPower = UnitPowerMax("player", pType)
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

        local bar = powerbar[type]
        bar:SetMinMaxValues(0, maxPower)
        bar:SetValue(curPower)
        if bar.text then
            if style == "NONE" then
                bar.text:SetText("")
                bar.text:Hide()
            else
                local text
                if style == "PERCENT" then
                    text = string.format("%.0f", (curPower / maxPower) * 100)
                elseif style == "CURRENT" then
                    text = tostring(curPower)
                else -- CURMAX
                    text = curPower .. " / " .. maxPower
                end
                bar.text:SetText(text)
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
            for _, tx in ipairs(bar.separatorMarks) do tx:Hide() end
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
        if bar.separatorMarks then for _, tx in ipairs(bar.separatorMarks) do tx:Hide() end end
        return
    end

    bar.separatorMarks = bar.separatorMarks or {}
    local needed = segments - 1
    local w = math.max(1, bar:GetWidth() or 0)
    local h = math.max(1, bar:GetHeight() or 0)

    -- Ensure we have enough textures
    for i = #bar.separatorMarks + 1, needed do
        local tx = bar:CreateTexture(nil, "OVERLAY")
        tx:SetColorTexture(1, 1, 1, 0.5)
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
        tx:Show()
    end
    -- Hide extras
    for i = needed + 1, #bar.separatorMarks do
        bar.separatorMarks[i]:Hide()
    end
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
        if show then sb.fs:Show() else sb.fs:Hide() end
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

	local settings = getBarSettings(type)
	local w = settings and settings.width or addon.db["personalResourceBarManaWidth"]
	local h = settings and settings.height or addon.db["personalResourceBarManaHeight"]
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
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -40)
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
        if bar.text then bar.text:SetText(""); bar.text:Hide() end
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
    "RUNE_POWER_UPDATE",
}

local function setPowerbars()
	local _, powerToken = UnitPowerType("player")
	powerfrequent = {}
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
			if addon.variables.unitClass == "DRUID" then
				if pType == mainPowerBar and powerbar[pType] then powerbar[pType]:Show() end
				powerfrequent[pType] = true
				if pType ~= mainPowerBar and pType == "MANA" then
					createPowerBar(pType, powerbar[lastBar] or ((specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true) and EQOLHealthBar or nil))
					lastBar = pType
					if powerbar[pType] then powerbar[pType]:Show() end
				elseif powerToken ~= mainPowerBar then
					if powerToken == pType then
						createPowerBar(pType, powerbar[lastBar] or ((specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true) and EQOLHealthBar or nil))
						lastBar = pType
						if powerbar[pType] then powerbar[pType]:Show() end
					end
				end
			else
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
        -- After initial creation, run a re-anchor pass to ensure all dependent anchors resolve
        C_Timer.After(0.05, function()
            if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorAll then addon.Aura.ResourceBars.ReanchorAll() end
            if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
        end)
elseif (event == "UNIT_MAXHEALTH" or event == "UNIT_HEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED") and healthBar and healthBar:IsShown() then
    updateHealthBar()
elseif event == "UNIT_POWER_UPDATE" and powerbar[arg1] and powerbar[arg1]:IsShown() and not powerfrequent[arg1] then
    updatePowerBar(arg1)
elseif event == "UNIT_POWER_FREQUENT" and powerbar[arg1] and powerbar[arg1]:IsShown() and powerfrequent[arg1] then
    updatePowerBar(arg1)
    elseif event == "UNIT_MAXPOWER" and powerbar[arg1] and powerbar[arg1]:IsShown() then
        updatePowerBar(arg1)
        updateBarSeparators(arg1)
    elseif event == "RUNE_POWER_UPDATE" then
        if powerbar["RUNES"] and powerbar["RUNES"]:IsShown() then updatePowerBar("RUNES") end
    end
end

function ResourceBars.EnableResourceBars()
    if not frameAnchor then
        frameAnchor = CreateFrame("Frame")
        addon.Aura.anchorFrame = frameAnchor
    end
    for _, event in ipairs(eventsToRegister) do
        -- Generic unit events
        if event ~= "RUNE_POWER_UPDATE" then frameAnchor:RegisterUnitEvent(event, "player") end
    end
    frameAnchor:RegisterEvent("PLAYER_ENTERING_WORLD")
    frameAnchor:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    frameAnchor:RegisterEvent("TRAIT_CONFIG_UPDATED")
    frameAnchor:SetScript("OnEvent", eventHandler)
    frameAnchor:Hide()

    createHealthBar()
    -- setPowerbars()
    if addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
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
		mainFrame:SetParent(nil)
		mainFrame = nil
	end
	if healthBar then
		healthBar:Hide()
		healthBar:SetParent(nil)
		healthBar = nil
	end
    for pType, bar in pairs(powerbar) do
        if bar then
            bar:Hide()
            bar:SetParent(nil)
            if pType == "RUNES" then bar:SetScript("OnUpdate", nil); bar._runesAnimating = false end
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
    local cfg = addon.db.personalResourceBarSettings
        and addon.db.personalResourceBarSettings[addon.variables.unitClass]
        and addon.db.personalResourceBarSettings[addon.variables.unitClass][spec]
    local enabled = isDK and cfg and cfg.RUNES and (cfg.RUNES.enabled == true)
    if enabled and not frameAnchor._runeEvtRegistered then
        frameAnchor:RegisterEvent("RUNE_POWER_UPDATE")
        frameAnchor._runeEvtRegistered = true
    elseif (not enabled) and frameAnchor._runeEvtRegistered then
        frameAnchor:UnregisterEvent("RUNE_POWER_UPDATE")
        frameAnchor._runeEvtRegistered = false
        if powerbar and powerbar.RUNES then powerbar.RUNES:SetScript("OnUpdate", nil); powerbar.RUNES._runesAnimating = false end
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
				local defaultW = (pType == "HEALTH") and addon.db.personalResourceBarHealthWidth or addon.db.personalResourceBarManaWidth
				local defaultH = (pType == "HEALTH") and addon.db.personalResourceBarHealthHeight or addon.db.personalResourceBarManaHeight
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
        local defaultW = addon.db.personalResourceBarManaWidth
        local defaultH = addon.db.personalResourceBarManaHeight
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
			a.point = "TOPLEFT"
			a.relativePoint = "TOPLEFT"
		end
		local rel, looped = resolveAnchor(a, "HEALTH")
		if looped and (a.relativeFrame or "UIParent") ~= "UIParent" then
			local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
			local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
			local w = healthBar:GetWidth() or (addon.db.personalResourceBarHealthWidth or 0)
			local h = healthBar:GetHeight() or (addon.db.personalResourceBarHealthHeight or 0)
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
                a.point = "TOPLEFT"
                a.relativePoint = "TOPLEFT"
            end
            local rel, looped = resolveAnchor(a, pType)
            if looped and (a.relativeFrame or "UIParent") ~= "UIParent" then
                local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
                local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
                local w = bar:GetWidth() or (addon.db.personalResourceBarManaWidth or 0)
                local h = bar:GetHeight() or (addon.db.personalResourceBarManaHeight or 0)
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
    local cfg = addon.db.personalResourceBarSettings
        and addon.db.personalResourceBarSettings[addon.variables.unitClass]
        and addon.db.personalResourceBarSettings[addon.variables.unitClass][spec]
    local runesEnabled = cfg and cfg.RUNES and (cfg.RUNES.enabled == true)
    if powerbar and powerbar.RUNES and (not powerbar.RUNES:IsShown() or not runesEnabled) then
        powerbar.RUNES:SetScript("OnUpdate", nil)
        powerbar.RUNES._runesAnimating = false
    end
end

-- Re-anchor pass only: reapplies anchor points without rebuilding bars
function ResourceBars.ReanchorAll()
	-- Health first
	if healthBar then
		local a = getAnchor("HEALTH", addon.variables.unitSpec)
		if (a.relativeFrame or "UIParent") == "UIParent" then
			a.point = "TOPLEFT"
			a.relativePoint = "TOPLEFT"
		end
		local rel, looped = resolveAnchor(a, "HEALTH")
		if looped and (a.relativeFrame or "UIParent") ~= "UIParent" then
			local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
			local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
			local w = healthBar:GetWidth() or (addon.db.personalResourceBarHealthWidth or 0)
			local h = healthBar:GetHeight() or (addon.db.personalResourceBarHealthHeight or 0)
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
				a.point = "TOPLEFT"
				a.relativePoint = "TOPLEFT"
			end
			local rel, looped = resolveAnchor(a, pType)
			if looped and (a.relativeFrame or "UIParent") ~= "UIParent" then
				local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
				local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
				local w = bar:GetWidth() or (addon.db.personalResourceBarManaWidth or 0)
				local h = bar:GetHeight() or (addon.db.personalResourceBarManaHeight or 0)
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
