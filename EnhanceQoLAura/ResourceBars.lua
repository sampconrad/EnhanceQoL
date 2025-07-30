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
local lastTabIndex

function addon.Aura.functions.addResourceFrame(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)

	local data = {
		{
			text = "Enable Resource frame",
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
		local data = {
			{
				text = "Healthbar Width",
				var = "personalResourceBarHealthWidth",
				func = function(self, _, value)
					addon.db["personalResourceBarHealthWidth"] = value
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.SetHealthBarSize then
						addon.Aura.ResourceBars.SetHealthBarSize(addon.db["personalResourceBarHealthWidth"], addon.db["personalResourceBarHealthHeight"])
					end
				end,
				min = 1,
				max = 2000,
			},
			{
				text = "Healthbar Height",
				var = "personalResourceBarHealthHeight",
				func = function(self, _, value)
					addon.db["personalResourceBarHealthHeight"] = value
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.SetHealthBarSize then
						addon.Aura.ResourceBars.SetHealthBarSize(addon.db["personalResourceBarHealthWidth"], addon.db["personalResourceBarHealthHeight"])
					end
				end,
				min = 1,
				max = 2000,
			},
			{
				text = "Manabar Width",
				var = "personalResourceBarManaWidth",
				func = function(self, _, value)
					addon.db["personalResourceBarManaWidth"] = value
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.SetPowerBarSize then
						addon.Aura.ResourceBars.SetPowerBarSize(addon.db["personalResourceBarManaWidth"], addon.db["personalResourceBarManaHeight"])
					end
				end,
				min = 1,
				max = 2000,
			},
			{
				text = "Manabar Height",
				var = "personalResourceBarManaHeight",
				func = function(self, _, value)
					addon.db["personalResourceBarManaHeight"] = value
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.SetPowerBarSize then
						addon.Aura.ResourceBars.SetPowerBarSize(addon.db["personalResourceBarManaWidth"], addon.db["personalResourceBarManaHeight"])
					end
				end,
				min = 1,
				max = 100,
			},
		}

		for _, cbData in ipairs(data) do
			local uFunc = function(self, _, value) addon.db[cbData.var] = value end
			if cbData.func then uFunc = cbData.func end

			local healthBarWidth = addon.functions.createSliderAce(cbData.text, addon.db[cbData.var], cbData.min, cbData.max, 1, uFunc)
			healthBarWidth:SetFullWidth(true)
			groupCore:AddChild(healthBarWidth)

			groupCore:AddChild(addon.functions.createSpacerAce())
		end

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

		local function addAnchorOptions(barType, parent, info, frameList)
			info = info or {}
			frameList = frameList or baseFrameList

			local header = addon.functions.createLabelAce(barType .. " Anchor")
			parent:AddChild(header)

			local dropFrame = addon.functions.createDropdownAce("Relative Frame", frameList, nil, function(self, _, val)
				info.relativeFrame = val
				if addon.Aura.ResourceBars then addon.Aura.ResourceBars.Refresh() end
			end)
			dropFrame:SetValue(info.relativeFrame or "UIParent")
			parent:AddChild(dropFrame)

			local dropPoint = addon.functions.createDropdownAce("Point", anchorPoints, anchorOrder, function(self, _, val)
				info.point = val
				if addon.Aura.ResourceBars then addon.Aura.ResourceBars.Refresh() end
			end)
			dropPoint:SetValue(info.point or "TOPLEFT")
			parent:AddChild(dropPoint)

			local dropRelPoint = addon.functions.createDropdownAce("Relative Point", anchorPoints, anchorOrder, function(self, _, val)
				info.relativePoint = val
				if addon.Aura.ResourceBars then addon.Aura.ResourceBars.Refresh() end
			end)
			dropRelPoint:SetValue(info.relativePoint or info.point or "TOPLEFT")
			parent:AddChild(dropRelPoint)

			local editX = addon.functions.createEditboxAce("X", tostring(info.x or 0), function(self)
				info.x = tonumber(self:GetText()) or 0
				if addon.Aura.ResourceBars then addon.Aura.ResourceBars.Refresh() end
			end)
			parent:AddChild(editX)

			local editY = addon.functions.createEditboxAce("Y", tostring(info.y or 0), function(self)
				info.y = tonumber(self:GetText()) or 0
				if addon.Aura.ResourceBars then addon.Aura.ResourceBars.Refresh() end
			end)
			parent:AddChild(editY)

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

			for _, pType in ipairs(addon.Aura.ResourceBars.classPowerTypes) do
				local real
				if specInfo.MAIN == pType then
					real = specInfo.MAIN
				elseif specInfo[pType] then
					real = pType
				end
				if real then
					dbSpec[real] = dbSpec[real]
						or {
							enabled = true,
							width = addon.db["personalResourceBarManaWidth"],
							height = addon.db["personalResourceBarManaHeight"],
							textStyle = real == "MANA" and "PERCENT" or "CURMAX",
							fontSize = 16,
						}
					dbSpec[real].anchor = dbSpec[real].anchor or {}

					local cfg = dbSpec[real]
					local label = _G[real] or real
					local cb = addon.functions.createCheckboxAce(label, cfg.enabled, function(self, _, val)
						if cfg.enabled and not val then addon.Aura.ResourceBars.DetachAnchorsFrom(real, specIndex) end
						cfg.enabled = val
						addon.Aura.ResourceBars.Refresh()
						tabGroup:ReleaseChildren()
						tabGroup:SetTabs(specTabs)
						tabGroup:SelectTab(lastTabIndex or addon.variables.unitSpec or specTabs[1].value)
					end)
					container:AddChild(cb)

					if cfg.enabled then
						local sw = addon.functions.createSliderAce("Width", cfg.width, 1, 2000, 1, function(self, _, val)
							cfg.width = val
							addon.Aura.ResourceBars.SetPowerBarSize(val, cfg.height, real)
						end)
						container:AddChild(sw)
						local sh = addon.functions.createSliderAce("Height", cfg.height, 1, 2000, 1, function(self, _, val)
							cfg.height = val
							addon.Aura.ResourceBars.SetPowerBarSize(cfg.width, val, real)
						end)
						container:AddChild(sh)

						local tList = { PERCENT = "Percentage", CURMAX = "Current/Max", CURRENT = "Current" }
						local tOrder = { "PERCENT", "CURMAX", "CURRENT" }
						local drop = addon.functions.createDropdownAce("Text", tList, tOrder, function(self, _, key)
							cfg.textStyle = key
							addon.Aura.ResourceBars.Refresh()
						end)
						drop:SetValue(cfg.textStyle)
						container:AddChild(drop)

						local sFont = addon.functions.createSliderAce("Text Size", cfg.fontSize or 16, 6, 64, 1, function(self, _, val)
							cfg.fontSize = val
							addon.Aura.ResourceBars.Refresh()
						end)
						container:AddChild(sFont)

						local frames = {}
						for k, v in pairs(baseFrameList) do
							frames[k] = v
						end
						frames.EQOLHealthBar = "EQOLHealthBar"
						for _, t in ipairs(addon.Aura.ResourceBars.classPowerTypes) do
							if t ~= real and dbSpec[t] and dbSpec[t].enabled ~= false then frames["EQOL" .. t .. "Bar"] = "EQOL" .. t .. "Bar" end
						end

						addAnchorOptions(real, container, cfg.anchor, frames)
					end
					container:AddChild(addon.functions.createSpacerAce())
				end
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

		local percent = (curHealth / maxHealth) * 100
		local percentStr = string.format("%.0f", percent)
		healthBar:SetMinMaxValues(0, maxHealth)
		healthBar:SetValue(curHealth)
		if healthBar.text then healthBar.text:SetText(percentStr) end
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

local function getAnchor(name, spec)
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
	if not frame or frame == UIParent then return frame or UIParent end

	local visited = {}
	local check = frame
	local limit = 10

	while check and check.GetName and check ~= UIParent and limit > 0 do
		local fname = check:GetName()
		if visited[fname] then
			print("|cff00ff98Enhance QoL|r: " .. L["AnchorLoop"]:format(fname))
			return UIParent
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
		return UIParent
	end
	return frame or UIParent
end

local function createHealthBar()
	if mainFrame then
		mainFrame:Show()
		healthBar:Show()
		return
	end

	mainFrame = CreateFrame("frame", "EQOLResourceFrame", UIParent)
	healthBar = CreateFrame("StatusBar", "EQOLHealthBar", mainFrame, "BackdropTemplate")
	healthBar:SetSize(addon.db["personalResourceBarHealthWidth"], addon.db["personalResourceBarHealthHeight"])
	healthBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
	local anchor = getAnchor("HEALTH", addon.variables.unitSpec)
	local rel = resolveAnchor(anchor)
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
		info.point = point
		info.relativeFrame = rel and rel:GetName() or "UIParent"
		info.relativePoint = relPoint
		info.x = xOfs
		info.y = yOfs
	end)

	local absorbBar = CreateFrame("StatusBar", "EQOLAbsorbBar", healthBar)
	absorbBar:SetAllPoints(healthBar)
	absorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
	absorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
	absorbBar:SetStatusBarColor(0.8, 0.8, 0.8, 0.8)
	healthBar.absorbBar = absorbBar

	updateHealthBar()
end

local powertypeClasses = {
	DRUID = {
		[1] = { MAIN = "LUNAR_POWER", RAGE = true, ENERGY = true, MANA = true },
		[2] = { MAIN = "ENERGY", COMBO_POINTS = true, RAGE = true, MANA = true, LUNAR_POWER = true },
		[3] = { MAIN = "RAGE", ENERGY = true, MANA = true, LUNAR_POWER = true },
		[4] = { MAIN = "MANA", RAGE = true, ENERGY = true, LUNAR_POWER = true },
	},
	DEMONHUNTER = {
		[1] = { MAIN = "FURY" },
		[2] = { MAIN = "FURY" },
	},
	DEATHKNIGHT = {
		[1] = { MAIN = "RUNIC_POWER" },
		[2] = { MAIN = "RUNIC_POWER" },
		[3] = { MAIN = "RUNIC_POWER" },
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

		local text
		if style == "PERCENT" then
			text = string.format("%.0f", (curPower / maxPower) * 100)
		elseif style == "CURRENT" then
			text = tostring(curPower)
		else -- CURMAX
			text = curPower .. " / " .. maxPower
		end

		local bar = powerbar[type]
		bar:SetMinMaxValues(0, maxPower)
		bar:SetValue(curPower)
		if bar.text then bar.text:SetText(text) end
	end
end

local function createPowerBar(type, anchor)
	if powerbar[type] then
		powerbar[type]:Hide()
		powerbar[type]:SetParent(nil)
		powerbar[type] = nil
	end

	local bar = CreateFrame("StatusBar", "EQOL" .. type .. "Bar", mainFrame, "BackdropTemplate")
	local settings = getBarSettings(type)
	local w = settings and settings.width or addon.db["personalResourceBarManaWidth"]
	local h = settings and settings.height or addon.db["personalResourceBarManaHeight"]
	bar:SetSize(w, h)
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
	local a = getAnchor(type, addon.variables.unitSpec)
	local allowMove = true
	if a.point then
		local rel = resolveAnchor(a, type)
		if rel and rel:GetName() ~= "UIParent" then allowMove = false end
		bar:SetPoint(a.point, rel, a.relativePoint or a.point, a.x or 0, a.y or 0)
	elseif anchor then
		bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 0)
	else
		bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -40)
	end
	bar:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 3,
		insets = { left = 0, right = 0, top = 0, bottom = 0 },
	})
	bar:SetBackdropColor(0, 0, 0, 0.8)
	bar:SetBackdropBorderColor(0, 0, 0, 0)
	local fontSize = settings and settings.fontSize or 16

	bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	bar.text:SetFont(addon.variables.defaultFont, fontSize, "OUTLINE")
	bar.text:SetPoint("CENTER", bar, "CENTER", 3, 0)
	bar:SetStatusBarColor(getPowerBarColor(type))

	bar:SetMovable(allowMove)
	bar:EnableMouse(allowMove)
	if allowMove then
		bar:RegisterForDrag("LeftButton")
		bar:SetScript("OnDragStart", function(self)
			if IsShiftKeyDown() then self:StartMoving() end
		end)
		bar:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			local point, rel, relPoint, xOfs, yOfs = self:GetPoint()
			local info = getAnchor(type, addon.variables.unitSpec)
			info.point = point
			info.relativeFrame = rel and rel:GetName() or "UIParent"
			info.relativePoint = relPoint
			info.x = xOfs
			info.y = yOfs
		end)
	end
	powerbar[type] = bar
	bar:Show()
	updatePowerBar(type)
end

local eventsToRegister = {
	"UNIT_HEALTH",
	"UNIT_MAXHEALTH",
	"UNIT_ABSORB_AMOUNT_CHANGED",
	"UNIT_POWER_UPDATE",
	"UNIT_POWER_FREQUENT",
	"UNIT_DISPLAYPOWER",
	"UNIT_MAXPOWER",
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
		if not specCfg or not specCfg[mType] or specCfg[mType].enabled ~= false then
			createPowerBar(mType, EQOLHealthBar)
			mainPowerBar = mType
			lastBar = mainPowerBar
			if powerbar[mainPowerBar] then powerbar[mainPowerBar]:Show() end
		end
	end

	for _, pType in ipairs(classPowerTypes) do
		if powerbar[pType] then powerbar[pType]:Hide() end

		local shouldShow = false
		if mainPowerBar == pType then
			shouldShow = true
		elseif
			powertypeClasses[addon.variables.unitClass]
			and powertypeClasses[addon.variables.unitClass][addon.variables.unitSpec]
			and powertypeClasses[addon.variables.unitClass][addon.variables.unitSpec][pType]
		then
			shouldShow = true
		end

		if shouldShow then
			if specCfg and specCfg[pType] and specCfg[pType].enabled == false then shouldShow = false end
		end

		if shouldShow then
			if addon.variables.unitClass == "DRUID" then
				if pType == mainPowerBar and powerbar[pType] then powerbar[pType]:Show() end
				powerfrequent[pType] = true
				if pType ~= mainPowerBar and pType == "MANA" then
					createPowerBar(pType, powerbar[lastBar] or EQOLHealthBar)
					lastBar = pType
					if powerbar[pType] then powerbar[pType]:Show() end
				elseif powerToken ~= mainPowerBar then
					if powerToken == pType then
						createPowerBar(pType, powerbar[lastBar] or EQOLHealthBar)
						lastBar = pType
						if powerbar[pType] then powerbar[pType]:Show() end
					end
				end
			else
				powerfrequent[pType] = true
				if mainPowerBar ~= pType then
					createPowerBar(pType, powerbar[lastBar] or EQOLHealthBar)
					lastBar = pType
				end
				if powerbar[pType] then powerbar[pType]:Show() end
			end
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
		C_Timer.After(0.2, function() setPowerbars() end)
	elseif event == "PLAYER_ENTERING_WORLD" then
		updateHealthBar()
		setPowerbars()
	elseif (event == "UNIT_MAXHEALTH" or event == "UNIT_HEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED") and healthBar and healthBar:IsShown() then
		updateHealthBar()
	elseif event == "UNIT_POWER_UPDATE" and powerbar[arg1] and powerbar[arg1]:IsShown() and not powerfrequent[arg1] then
		updatePowerBar(arg1)
	elseif event == "UNIT_POWER_FREQUENT" and powerbar[arg1] and powerbar[arg1]:IsShown() and powerfrequent[arg1] then
		updatePowerBar(arg1)
	elseif event == "UNIT_MAXPOWER" and powerbar[arg1] and powerbar[arg1]:IsShown() then
		updatePowerBar(arg1)
	end
end

function ResourceBars.EnableResourceBars()
	if not frameAnchor then
		frameAnchor = CreateFrame("Frame")
		addon.Aura.anchorFrame = frameAnchor
	end
	for _, event in ipairs(eventsToRegister) do
		frameAnchor:RegisterUnitEvent(event, "player")
	end
	frameAnchor:RegisterEvent("PLAYER_ENTERING_WORLD")
	frameAnchor:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
	frameAnchor:RegisterEvent("TRAIT_CONFIG_UPDATED")
	frameAnchor:SetScript("OnEvent", eventHandler)
	frameAnchor:Hide()

	createHealthBar()
	-- setPowerbars()
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
		end
		powerbar[pType] = nil
	end
	powerbar = {}
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

	for pType, cfg in pairs(specCfg) do
		if pType ~= disabledType and cfg.anchor and cfg.anchor.relativeFrame == targetName then
			local frame = _G[getFrameName(pType)]
			if frame then
				cfg.anchor.point = "BOTTOMLEFT"
				cfg.anchor.relativeFrame = "UIParent"
				cfg.anchor.relativePoint = "BOTTOMLEFT"
				cfg.anchor.x = frame:GetLeft() or 0
				cfg.anchor.y = frame:GetBottom() or 0
			else
				cfg.anchor.relativeFrame = "UIParent"
			end
		end
	end
end

function ResourceBars.SetHealthBarSize(w, h)
	if healthBar then healthBar:SetSize(w, h) end
end

function ResourceBars.SetPowerBarSize(w, h, pType)
	local changed = {}
	if pType then
		if powerbar[pType] then
			powerbar[pType]:SetSize(w, h)
			changed[getFrameName(pType)] = true
		end
	else
		for t, bar in pairs(powerbar) do
			bar:SetSize(w, h)
			changed[getFrameName(t)] = true
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
					frame:SetPoint(anchor.point or "CENTER", rel, anchor.relativePoint or anchor.point or "CENTER", anchor.x or 0, anchor.y or 0)
				end
			end
		end
	end
end

function ResourceBars.Refresh() setPowerbars() end

return ResourceBars
--@end-debug@
