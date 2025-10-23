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
ResourceBars.ui = ResourceBars.ui or {}

-- forward declarations to satisfy luacheck for early function
local LSM
local BLIZZARD_TEX

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")

local function setGlow(bar, cfg, shouldShow, r, g, b)
	if not bar then return end
	cfg = cfg or {}
	if not shouldShow then
		if bar._glowTex then bar._glowTex:Hide() end
		return
	end

	local tex = bar._glowTex
	if not tex then
		tex = bar:CreateTexture(nil, "OVERLAY")
		tex:SetTexture("Interface\\Buttons\\WHITE8x8")
		tex:SetBlendMode(ADD or "ADD")
		tex:SetAllPoints()
		bar._glowTex = tex
	end

	local color = (cfg.useBarColor and cfg.barColor) or { r or 1, g or 1, b or 1, 0.35 }
	tex:SetVertexColor(color[1] or (r or 1), color[2] or (g or 1), color[3] or (b or 1), color[4] or 0.35)
	tex:Show()
end

local function getPowerBarColor(type)
	local colorTable = PowerBarColor
	if colorTable then
		local entry = colorTable[string.upper(type)]
		if entry and entry.r then return entry.r, entry.g, entry.b end
	end
	return 1, 1, 1
end

function ResourceBars.RefreshTextureDropdown()
	local dd = ResourceBars.ui and ResourceBars.ui.textureDropdown
	if not dd then return end
	-- Rebuild generic list: DEFAULT + built-ins + LSM statusbars
	local map = {
		["DEFAULT"] = DEFAULT,
		[BLIZZARD_TEX] = "Blizzard: UI-StatusBar",
		["Interface\\Buttons\\WHITE8x8"] = "Flat (white, tintable)",
		["Interface\\Tooltips\\UI-Tooltip-Background"] = "Dark Flat (Tooltip bg)",
	}
	for name, path in pairs(LSM and LSM:HashTable("statusbar") or {}) do
		if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
	end
	local noDefault = {}
	for k, v in pairs(map) do
		if k ~= "DEFAULT" then noDefault[k] = v end
	end
	local sorted, order = addon.functions.prepareListForDropdown(noDefault)
	sorted["DEFAULT"] = DEFAULT
	table.insert(order, 1, "DEFAULT")
	dd:SetList(sorted, order)
	local cfg = dd._rb_cfgRef
	local cur = (cfg and cfg.barTexture) or "DEFAULT"
	if not sorted[cur] then cur = "DEFAULT" end
	dd:SetValue(cur)
end

LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local AceGUI = addon.AceGUI
local UnitPower, UnitPowerMax, UnitHealth, UnitHealthMax, UnitGetTotalAbsorbs, GetTime = UnitPower, UnitPowerMax, UnitHealth, UnitHealthMax, UnitGetTotalAbsorbs, GetTime
local CreateFrame = CreateFrame
local PowerBarColor = PowerBarColor
local UIParent = UIParent
local GetShapeshiftForm, GetShapeshiftFormInfo = GetShapeshiftForm, GetShapeshiftFormInfo
local UnitPowerType = UnitPowerType
local GetSpecializationInfoForClassID = GetSpecializationInfoForClassID
local GetNumSpecializationsForClassID = C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID
local GetRuneCooldown = GetRuneCooldown
local IsShiftKeyDown = IsShiftKeyDown
local After = C_Timer and C_Timer.After
local EnumPowerType = Enum and Enum.PowerType
local format = string.format
local tostring = tostring
local floor, max, min, ceil, abs = math.floor, math.max, math.min, math.ceil, math.abs
local tinsert, tsort = table.insert, table.sort

local frameAnchor
local mainFrame
local healthBar
local powerbar = {}
local powerfrequent = {}
local getBarSettings
local getAnchor
local layoutRunes
local updatePowerBar
local lastBarSelectionPerSpec = {}
local DEFAULT_STACK_SPACING = 0
local SEPARATOR_THICKNESS = 1
local SEP_DEFAULT = { 1, 1, 1, 0.5 }
local DEFAULT_RB_TEX = "Interface\\Buttons\\WHITE8x8" -- historical default (Solid)
BLIZZARD_TEX = "Interface\\TargetingFrame\\UI-StatusBar"

local function isValidStatusbarPath(path)
	if not path or type(path) ~= "string" or path == "" then return false end
	if path == BLIZZARD_TEX then return true end
	if path == "Interface\\Buttons\\WHITE8x8" then return true end
	if path == "Interface\\Tooltips\\UI-Tooltip-Background" then return true end
	if LSM and LSM.HashTable then
		local ht = LSM:HashTable("statusbar")
		for _, p in pairs(ht or {}) do
			if p == path then return true end
		end
	end
	return false
end

local function resolveTexture(cfg)
	local sel = cfg and cfg.barTexture
	if sel == nil or sel == "DEFAULT" or not isValidStatusbarPath(sel) then return DEFAULT_RB_TEX end
	return sel
end

local function isEQOLFrameName(name)
	if name == "EQOLHealthBar" then return true end
	return type(name) == "string" and name:match("^EQOL.+Bar$")
end
-- Fixed, non-DB defaults
local DEFAULT_HEALTH_WIDTH = 200
local DEFAULT_HEALTH_HEIGHT = 20
local DEFAULT_POWER_WIDTH = 200
local DEFAULT_POWER_HEIGHT = 20

local function resolveFontFace(cfg)
	if cfg and cfg.fontFace and cfg.fontFace ~= "" then return cfg.fontFace end
	return addon.variables.defaultFont
end

local function resolveFontOutline(cfg)
	local outline = cfg and cfg.fontOutline
	if outline == nil then return "OUTLINE" end
	if outline == "" or outline == "NONE" then return nil end
	return outline
end

local function resolveFontColor(cfg)
	local fc = cfg and cfg.fontColor
	return fc and (fc[1] or 1) or 1, fc and (fc[2] or 1) or 1, fc and (fc[3] or 1) or 1, fc and (fc[4] or 1) or 1
end

local function setFontWithFallback(fs, face, size, outline)
	if not fs or not face then return end
	if outline == "" then outline = nil end
	if not fs:SetFont(face, size, outline) then
		local fallbackOutline = outline or "OUTLINE"
		fs:SetFont(addon.variables.defaultFont, size, fallbackOutline)
	end
end

local function applyFontToString(fs, cfg)
	if not fs then return end
	local size = (cfg and cfg.fontSize) or 16
	setFontWithFallback(fs, resolveFontFace(cfg), size, resolveFontOutline(cfg))
	local r, g, b, a = resolveFontColor(cfg)
	fs:SetTextColor(r, g, b, a)
end

local function ensureBackdropFrames(frame)
	if not frame then return nil end
	local bg = frame._rbBackground
	if not bg then
		bg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		local base = frame:GetFrameLevel() or 1
		bg:SetFrameLevel(max(base - 2, 0))
		bg:EnableMouse(false)
		frame._rbBackground = bg
	end
	local border = frame._rbBorder
	if not border then
		border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		local base = frame:GetFrameLevel() or 1
		border:SetFrameLevel(min(base + 2, 65535))
		border:EnableMouse(false)
		frame._rbBorder = border
	end
	return bg, border
end

local function applyBackdrop(frame, cfg)
	if not frame then return end
	cfg = cfg or {}
	cfg.backdrop = cfg.backdrop
		or {
			enabled = true,
			backgroundTexture = "Interface\\DialogFrame\\UI-DialogBox-Background",
			backgroundColor = { 0, 0, 0, 0.8 },
			borderTexture = "Interface\\Tooltips\\UI-Tooltip-Border",
			borderColor = { 0, 0, 0, 0 },
			edgeSize = 3,
			outset = 0,
		}
	local bd = cfg.backdrop
	local bgFrame, borderFrame = ensureBackdropFrames(frame)
	if not bgFrame or not borderFrame then return end

	if bd.enabled == false then
		bgFrame:Hide()
		borderFrame:Hide()
		return
	end

	local outset = bd.outset or 0

	bgFrame:ClearAllPoints()
	bgFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", -outset, outset)
	bgFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", outset, -outset)

	borderFrame:ClearAllPoints()
	borderFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", -outset, outset)
	borderFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", outset, -outset)

	if bgFrame.SetBackdrop then
		bgFrame:SetBackdrop({
			bgFile = bd.backgroundTexture or "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = nil,
			tile = false,
			edgeSize = 0,
			insets = { left = 0, right = 0, top = 0, bottom = 0 },
		})
		local bc = bd.backgroundColor or { 0, 0, 0, 0.8 }
		if bgFrame.SetBackdropColor then bgFrame:SetBackdropColor(bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 1) end
		if bgFrame.SetBackdropBorderColor then bgFrame:SetBackdropBorderColor(0, 0, 0, 0) end
	end
	bgFrame:Show()

	if borderFrame.SetBackdrop then
		if bd.borderTexture and bd.borderTexture ~= "" and (bd.edgeSize or 0) > 0 then
			borderFrame:SetBackdrop({
				bgFile = nil,
				edgeFile = bd.borderTexture or "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = false,
				edgeSize = bd.edgeSize or 3,
				insets = { left = 0, right = 0, top = 0, bottom = 0 },
			})
			local boc = bd.borderColor or { 0, 0, 0, 0 }
			if borderFrame.SetBackdropBorderColor then borderFrame:SetBackdropBorderColor(boc[1] or 0, boc[2] or 0, boc[3] or 0, boc[4] or 1) end
			borderFrame:Show()
		else
			borderFrame:SetBackdrop(nil)
			borderFrame:Hide()
		end
	end
end

local function ensureTextOffsetTable(cfg)
	cfg = cfg or {}
	cfg.textOffset = cfg.textOffset or { x = 0, y = 0 }
	return cfg.textOffset
end

local function applyTextPosition(bar, cfg, baseX, baseY)
	if not bar or not bar.text then return end
	local offset = ensureTextOffsetTable(cfg)
	local ox = (baseX or 0) + (offset.x or 0)
	local oy = (baseY or 0) + (offset.y or 0)
	bar.text:ClearAllPoints()
	bar.text:SetPoint("CENTER", bar, "CENTER", ox, oy)
end

local function applyBarFillColor(bar, cfg, pType)
	if not bar then return end
	cfg = cfg or {}
	local r, g, b, a
	if cfg.useBarColor then
		local color = cfg.barColor or { 1, 1, 1, 1 }
		r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
	else
		r, g, b = getPowerBarColor(pType or "MANA")
		a = (cfg.barColor and cfg.barColor[4]) or 1
	end
	bar:SetStatusBarColor(r, g, b, a or 1)
	bar._baseColor = bar._baseColor or {}
	bar._baseColor[1], bar._baseColor[2], bar._baseColor[3], bar._baseColor[4] = r, g, b, a or 1
	bar._lastColor = bar._lastColor or {}
	bar._lastColor[1], bar._lastColor[2], bar._lastColor[3], bar._lastColor[4] = r, g, b, a or 1
	bar._usingMaxColor = false
end

local function configureBarBehavior(bar, cfg, pType)
	if not bar then return end
	cfg = cfg or {}
	if bar.SetReverseFill then bar:SetReverseFill(cfg.reverseFill == true) end

	if pType ~= "RUNES" and bar.SetOrientation then bar:SetOrientation((cfg.verticalFill == true) and "VERTICAL" or "HORIZONTAL") end
	if pType == "HEALTH" and bar.absorbBar then
		local absorb = bar.absorbBar
		if absorb.SetOrientation then absorb:SetOrientation((cfg.verticalFill == true) and "VERTICAL" or "HORIZONTAL") end
		local tex = absorb:GetStatusBarTexture()
		if tex then
			if cfg and cfg.verticalFill == true then
				tex:SetRotation(math.pi / 2)
			else
				tex:SetRotation(0)
			end
		end
	end

	if pType ~= "RUNES" then
		if cfg.smoothFill then
			if not bar._smoothUpdater then
				bar._smoothUpdater = function(self, elapsed)
					local target = self._smoothTarget or self:GetValue()
					if target == nil then return end
					local current = self:GetValue()
					local diff = target - current
					if abs(diff) <= 0.5 then
						self:SetValue(target)
						return
					end
					local speed = self._smoothSpeed or 12
					local step = diff * min(1, (elapsed or 0) * speed)
					self:SetValue(current + step)
				end
			end
			bar._smoothSpeed = 12
			if bar:GetScript("OnUpdate") ~= bar._smoothUpdater then bar:SetScript("OnUpdate", bar._smoothUpdater) end
		else
			if bar._smoothUpdater and bar:GetScript("OnUpdate") == bar._smoothUpdater then bar:SetScript("OnUpdate", nil) end
		end
	else
		if bar._smoothUpdater and bar:GetScript("OnUpdate") == bar._smoothUpdater then bar:SetScript("OnUpdate", nil) end
	end
end

local function Snap(bar, off)
	local s = bar:GetEffectiveScale() or 1
	return floor(off * s + 0.5) / s
end

local FREQUENT = { ENERGY = true, FOCUS = true, RAGE = true, RUNIC_POWER = true, LUNAR_POWER = true }
local formIndexToKey = {
	[0] = "HUMANOID",
	[1] = "BEAR",
	[2] = "CAT",
	[3] = "TRAVEL",
	[4] = "MOONKIN",
	[5] = "TREANT",
	[6] = "STAG",
}
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

local DK_SPEC_COLOR = {
	[1] = { 0.8, 0.1, 0.1 },
	[2] = { 0.2, 0.6, 1.0 },
	[3] = { 0.0, 0.9, 0.3 },
}

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
					if After then
						After(0, function()
							if addon and addon.Aura and addon.Aura.functions and addon.Aura.functions.addResourceFrame then addon.Aura.functions.addResourceFrame(container) end
						end)
					else
						if addon and addon.Aura and addon.Aura.functions and addon.Aura.functions.addResourceFrame then addon.Aura.functions.addResourceFrame(container) end
					end
				end
			end,
		},
	}

	tsort(data, function(a, b) return a.text < b.text end)

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

			local header = addon.functions.createLabelAce(format("%s %s", displayNameForBarType(barType), L["Anchor"]))
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
					local anch = getAnchor(bt, specIndex)
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
				info.point = info.point or "TOPLEFT"
				info.relativePoint = info.relativePoint or info.point or "TOPLEFT"
				info.x = info.x or 0
				info.y = info.y or 0
				if (info.relativeFrame or "UIParent") == "UIParent" then info.autoSpacing = nil end

				local stackSpacing = DEFAULT_STACK_SPACING
				if info.autoSpacing and (info.relativeFrame or "UIParent") ~= "UIParent" then
					info.x = 0
					info.y = stackSpacing
				end

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
				local dropPoint = addon.functions.createDropdownAce(RESAMPLE_QUALITY_POINT, anchorPoints, anchorOrder, nil)
				dropPoint:SetValue(info.point or "TOPLEFT")
				dropPoint:SetFullWidth(false)
				dropPoint:SetRelativeWidth(0.333)
				row:AddChild(dropPoint)

				local dropRelPoint = addon.functions.createDropdownAce(L["Relative Point"], anchorPoints, anchorOrder, nil)
				dropRelPoint:SetValue(info.relativePoint or info.point or "TOPLEFT")
				dropRelPoint:SetFullWidth(false)
				dropRelPoint:SetRelativeWidth(0.333)
				row:AddChild(dropRelPoint)

				anchorSub:AddChild(row)

				-- Offset sliders (X/Y)
				local offsetRow = addon.functions.createContainer("SimpleGroup", "Flow")
				offsetRow:SetFullWidth(true)
				info.x = info.x or 0
				info.y = info.y or 0

				local sliderX = addon.functions.createSliderAce(L["X"] or "X", info.x, -1000, 1000, 1, function(_, _, val)
					info.autoSpacing = false
					info.x = val
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end)
				sliderX:SetFullWidth(false)
				sliderX:SetRelativeWidth(0.5)
				sliderX:SetValue(info.x)
				offsetRow:AddChild(sliderX)

				local sliderY = addon.functions.createSliderAce(L["Y"] or "Y", info.y, -1000, 1000, 1, function(_, _, val)
					info.autoSpacing = false
					info.y = val
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end)
				sliderY:SetFullWidth(false)
				sliderY:SetRelativeWidth(0.5)
				sliderY:SetValue(info.y)
				offsetRow:AddChild(sliderY)
				anchorSub:AddChild(offsetRow)

				if (info.relativeFrame or "UIParent") == "UIParent" then
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
						info.y = stackSpacing
						info.autoSpacing = true
					end
					if val == "UIParent" and prev ~= "UIParent" then
						local cfg = getBarSettings(barType)
						local defaultW = barType == "HEALTH" and DEFAULT_HEALTH_WIDTH or DEFAULT_POWER_WIDTH
						local defaultH = barType == "HEALTH" and DEFAULT_HEALTH_HEIGHT or DEFAULT_POWER_HEIGHT
						local w = (cfg and cfg.width) or defaultW or 0
						local h = (cfg and cfg.height) or defaultH or 0
						local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
						local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
						info.point = info.point or "TOPLEFT"
						info.relativePoint = info.relativePoint or info.point or "TOPLEFT"
						info.x = (pw - w) / 2
						info.y = (h - ph) / 2
						info.autoSpacing = nil
					end
					buildAnchorSub()
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end

				dropFrame:SetCallback("OnValueChanged", onFrameChanged)
				dropPoint:SetCallback("OnValueChanged", function(self, _, val)
					info.autoSpacing = false
					info.point = val
					info.relativePoint = info.relativePoint or val
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end)
				dropRelPoint:SetCallback("OnValueChanged", function(self, _, val)
					info.autoSpacing = false
					info.relativePoint = val
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end)
			end

			-- Initial build
			buildAnchorSub()

			parent:AddChild(addon.functions.createSpacerAce())
		end

		local specTabs = {}
		for i = 1, (GetNumSpecializationsForClassID and GetNumSpecializationsForClassID(addon.variables.unitClassID) or 0) do
			local _, specName = GetSpecializationInfoForClassID(addon.variables.unitClassID, i)
			tinsert(specTabs, { text = specName, value = i })
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
							fontFace = addon.variables.defaultFont,
							fontOutline = "OUTLINE",
							fontColor = { 1, 1, 1, 1 },
							backdrop = {
								enabled = true,
								backgroundTexture = "Interface\\DialogFrame\\UI-DialogBox-Background",
								backgroundColor = { 0, 0, 0, 0.8 },
								borderTexture = "Interface\\Tooltips\\UI-Tooltip-Border",
								borderColor = { 0, 0, 0, 0 },
								edgeSize = 3,
								outset = 0,
							},
							textOffset = { x = 0, y = 0 },
							useBarColor = false,
							barColor = { 1, 1, 1, 1 },
							useMaxColor = false,
							maxColor = { 1, 1, 1, 1 },
							showSeparator = false,
							separatorColor = { 1, 1, 1, 0.5 },
							separatorThickness = SEPARATOR_THICKNESS,
							showCooldownText = false,
							cooldownTextFontSize = 16,
							reverseFill = false,
							verticalFill = false,
							smoothFill = false,
							glowAtCap = false,
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
					fontFace = addon.variables.defaultFont,
					fontOutline = "OUTLINE",
					fontColor = { 1, 1, 1, 1 },
					backdrop = {
						enabled = true,
						backgroundTexture = "Interface\\DialogFrame\\UI-DialogBox-Background",
						backgroundColor = { 0, 0, 0, 0.8 },
						borderTexture = "Interface\\Tooltips\\UI-Tooltip-Border",
						borderColor = { 0, 0, 0, 0 },
						edgeSize = 3,
						outset = 0,
					},
					textOffset = { x = 0, y = 0 },
					useBarColor = false,
					barColor = { 1, 1, 1, 1 },
					useMaxColor = false,
					maxColor = { 1, 1, 1, 1 },
					reverseFill = false,
					verticalFill = false,
					smoothFill = false,
					glowAtCap = false,
					anchor = {},
				}
			local function fontDropdownData()
				local map = {
					[addon.variables.defaultFont] = L["Default"] or "Default",
				}
				for name, path in pairs(LSM and LSM:HashTable("font") or {}) do
					if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
				end
				return addon.functions.prepareListForDropdown(map)
			end

			local function borderDropdownData()
				local map = {
					["Interface\\Tooltips\\UI-Tooltip-Border"] = "Tooltip Border",
				}
				for name, path in pairs(LSM and LSM:HashTable("border") or {}) do
					if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
				end
				return addon.functions.prepareListForDropdown(map)
			end

			local function backgroundDropdownData()
				local map = {
					["Interface\\DialogFrame\\UI-DialogBox-Background"] = "Dialog Background",
					["Interface\\Buttons\\WHITE8x8"] = "Solid (tintable)",
				}
				for name, path in pairs(LSM and LSM:HashTable("background") or {}) do
					if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
				end
				return addon.functions.prepareListForDropdown(map)
			end

			local outlineMap = {
				NONE = L["None"] or NONE,
				OUTLINE = L["Outline"] or "Outline",
				THICKOUTLINE = L["Thick Outline"] or "Thick Outline",
				MONOCHROMEOUTLINE = L["Monochrome Outline"] or "Monochrome Outline",
			}
			local outlineOrder = { "NONE", "OUTLINE", "THICKOUTLINE", "MONOCHROMEOUTLINE" }

			local function addFontControls(parent, cfg)
				local list, order = fontDropdownData()
				local fontRow = addon.functions.createContainer("SimpleGroup", "Flow")
				fontRow:SetFullWidth(true)
				local dropFont = addon.functions.createDropdownAce(L["Font"] or "Font", list, order, function(_, _, key)
					cfg.fontFace = key
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end)
				local curFont = cfg.fontFace or addon.variables.defaultFont
				if not list[curFont] then curFont = addon.variables.defaultFont end
				dropFont:SetValue(curFont)
				dropFont:SetFullWidth(false)
				dropFont:SetRelativeWidth(0.5)
				fontRow:AddChild(dropFont)

				local dropOutline = addon.functions.createDropdownAce(L["Font outline"] or "Font outline", outlineMap, outlineOrder, function(_, _, key)
					cfg.fontOutline = key
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end)
				dropOutline:SetValue(cfg.fontOutline or "OUTLINE")
				dropOutline:SetFullWidth(false)
				dropOutline:SetRelativeWidth(0.5)
				fontRow:AddChild(dropOutline)
				parent:AddChild(fontRow)

				local colorRow = addon.functions.createContainer("SimpleGroup", "Flow")
				colorRow:SetFullWidth(true)
				local color = AceGUI:Create("ColorPicker")
				color:SetLabel(L["Font color"] or "Font color")
				color:SetHasAlpha(true)
				local fc = cfg.fontColor or { 1, 1, 1, 1 }
				color:SetColor(fc[1] or 1, fc[2] or 1, fc[3] or 1, fc[4] or 1)
				color:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
					cfg.fontColor = { r, g, b, a }
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end)
				color:SetFullWidth(false)
				color:SetRelativeWidth(0.5)
				colorRow:AddChild(color)
				parent:AddChild(colorRow)
			end

			local function addBackdropControls(parent, cfg)
				cfg.backdrop = cfg.backdrop or {}
				if cfg.backdrop.enabled == nil then cfg.backdrop.enabled = true end
				cfg.backdrop.backgroundTexture = cfg.backdrop.backgroundTexture or "Interface\\DialogFrame\\UI-DialogBox-Background"
				cfg.backdrop.backgroundColor = cfg.backdrop.backgroundColor or { 0, 0, 0, 0.8 }
				cfg.backdrop.borderTexture = cfg.backdrop.borderTexture or "Interface\\Tooltips\\UI-Tooltip-Border"
				cfg.backdrop.borderColor = cfg.backdrop.borderColor or { 0, 0, 0, 0 }
				cfg.backdrop.edgeSize = cfg.backdrop.edgeSize or 3
				cfg.backdrop.outset = cfg.backdrop.outset or 0

				local group = addon.functions.createContainer("InlineGroup", "Flow")
				group:SetTitle(L["Frame & Background"] or "Frame & Background")
				group:SetFullWidth(true)
				parent:AddChild(group)

				local dropBg, bgColor, dropBorder, borderColor, sliderEdge

				local cb = addon.functions.createCheckboxAce(L["Show backdrop"] or "Show backdrop", cfg.backdrop.enabled ~= false, function(_, _, val)
					cfg.backdrop.enabled = val and true or false
					local disable = cfg.backdrop.enabled == false
					if dropBg then dropBg:SetDisabled(disable) end
					if bgColor then bgColor:SetDisabled(disable) end
					if dropBorder then dropBorder:SetDisabled(disable) end
					if borderColor then borderColor:SetDisabled(disable) end
					if sliderEdge then sliderEdge:SetDisabled(disable) end
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end)
				cb:SetFullWidth(true)
				group:AddChild(cb)

				local bgList, bgOrder = backgroundDropdownData()
				dropBg = addon.functions.createDropdownAce(L["Background texture"] or "Background texture", bgList, bgOrder, function(_, _, key)
					cfg.backdrop.backgroundTexture = key
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end)
				local curBg = cfg.backdrop.backgroundTexture
				if not bgList[curBg] then curBg = "Interface\\DialogFrame\\UI-DialogBox-Background" end
				dropBg:SetValue(curBg)
				dropBg:SetFullWidth(false)
				dropBg:SetRelativeWidth(0.5)
				group:AddChild(dropBg)

				bgColor = AceGUI:Create("ColorPicker")
				bgColor:SetLabel(L["Background color"] or "Background color")
				bgColor:SetHasAlpha(true)
				local bc = cfg.backdrop.backgroundColor or { 0, 0, 0, 0.8 }
				bgColor:SetColor(bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 0.8)
				bgColor:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
					cfg.backdrop.backgroundColor = { r, g, b, a }
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end)
				bgColor:SetFullWidth(false)
				bgColor:SetRelativeWidth(0.5)
				group:AddChild(bgColor)

				local borderList, borderOrder = borderDropdownData()
				dropBorder = addon.functions.createDropdownAce(L["Border texture"] or "Border texture", borderList, borderOrder, function(_, _, key)
					cfg.backdrop.borderTexture = key
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end)
				local curBorder = cfg.backdrop.borderTexture
				if not borderList[curBorder] then curBorder = "Interface\\Tooltips\\UI-Tooltip-Border" end
				dropBorder:SetValue(curBorder)
				dropBorder:SetFullWidth(false)
				dropBorder:SetRelativeWidth(0.5)
				group:AddChild(dropBorder)

				borderColor = AceGUI:Create("ColorPicker")
				borderColor:SetLabel(L["Border color"] or "Border color")
				borderColor:SetHasAlpha(true)
				local boc = cfg.backdrop.borderColor or { 0, 0, 0, 0 }
				borderColor:SetColor(boc[1] or 0, boc[2] or 0, boc[3] or 0, boc[4] or 0)
				borderColor:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
					cfg.backdrop.borderColor = { r, g, b, a }
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end)
				borderColor:SetFullWidth(false)
				borderColor:SetRelativeWidth(0.5)
				group:AddChild(borderColor)

				sliderEdge = addon.functions.createSliderAce(L["Border size"] or "Border size", cfg.backdrop.edgeSize or 3, 0, 32, 1, function(_, _, val)
					cfg.backdrop.edgeSize = val
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end)
				sliderEdge:SetFullWidth(false)
				sliderEdge:SetRelativeWidth(0.5)
				group:AddChild(sliderEdge)

				local sliderOutset = addon.functions.createSliderAce(L["Border offset"] or "Border offset", cfg.backdrop.outset or 0, 0, 32, 1, function(_, _, val)
					cfg.backdrop.outset = val
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end)
				sliderOutset:SetFullWidth(false)
				sliderOutset:SetRelativeWidth(0.5)
				group:AddChild(sliderOutset)

				local disable = cfg.backdrop.enabled == false
				dropBg:SetDisabled(disable)
				bgColor:SetDisabled(disable)
				dropBorder:SetDisabled(disable)
				borderColor:SetDisabled(disable)
				sliderEdge:SetDisabled(disable)
				sliderOutset:SetDisabled(disable)
			end

			local function addTextOffsetControlsUI(parent, cfg, specIndex)
				local offsets = ensureTextOffsetTable(cfg)
				local row = addon.functions.createContainer("SimpleGroup", "Flow")
				row:SetFullWidth(true)
				local sliderX = addon.functions.createSliderAce(L["Text X Offset"] or "Text X Offset", offsets.x or 0, -200, 200, 1, function(_, _, val)
					offsets.x = val
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end)
				sliderX:SetFullWidth(false)
				sliderX:SetRelativeWidth(0.5)
				row:AddChild(sliderX)

				local sliderY = addon.functions.createSliderAce(L["Text Y Offset"] or "Text Y Offset", offsets.y or 0, -200, 200, 1, function(_, _, val)
					offsets.y = val
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end)
				sliderY:SetFullWidth(false)
				sliderY:SetRelativeWidth(0.5)
				row:AddChild(sliderY)

				parent:AddChild(row)
				return sliderX, sliderY
			end

			local function addColorControls(parent, cfg, specIndex)
				cfg.barColor = cfg.barColor or { 1, 1, 1, 1 }
				cfg.maxColor = cfg.maxColor or { 1, 1, 1, 1 }
				local group = addon.functions.createContainer("InlineGroup", "Flow")
				group:SetTitle(L["Colors"] or "Colors")
				group:SetFullWidth(true)
				parent:AddChild(group)

				local function notifyRefresh()
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end

				local colorPicker
				local maxColorPicker
				local maxColorCheckbox
				local function refreshMaxColorControls()
					local glowEnabled = cfg.glowAtCap == true
					if maxColorCheckbox then maxColorCheckbox:SetDisabled(not glowEnabled) end
					if maxColorPicker then
						local disable = not (glowEnabled and cfg.useMaxColor == true)
						maxColorPicker:SetDisabled(disable)
					end
				end

				local cb = addon.functions.createCheckboxAce(L["Use custom color"] or "Use custom color", cfg.useBarColor == true, function(_, _, val)
					cfg.useBarColor = val and true or false
					if colorPicker then colorPicker:SetDisabled(not cfg.useBarColor) end
					notifyRefresh()
				end)
				cb:SetFullWidth(true)
				group:AddChild(cb)

				colorPicker = AceGUI:Create("ColorPicker")
				colorPicker:SetLabel(L["Bar color"] or "Bar color")
				colorPicker:SetHasAlpha(true)
				local bc = cfg.barColor or { 1, 1, 1, 1 }
				colorPicker:SetColor(bc[1] or 1, bc[2] or 1, bc[3] or 1, bc[4] or 1)
				colorPicker:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
					cfg.barColor = { r, g, b, a }
					notifyRefresh()
				end)
				colorPicker:SetFullWidth(false)
				colorPicker:SetRelativeWidth(0.5)
				colorPicker:SetDisabled(not (cfg.useBarColor == true))
				group:AddChild(colorPicker)

				maxColorCheckbox = addon.functions.createCheckboxAce(L["Use max color"] or "Use max color at maximum", cfg.useMaxColor == true, function(_, _, val)
					cfg.useMaxColor = val and true or false
					refreshMaxColorControls()
					notifyRefresh()
				end)
				maxColorCheckbox:SetFullWidth(true)
				group:AddChild(maxColorCheckbox)

				maxColorPicker = AceGUI:Create("ColorPicker")
				maxColorPicker:SetLabel(L["Max color"] or "Max color")
				maxColorPicker:SetHasAlpha(true)
				local mc = cfg.maxColor or { 1, 1, 1, 1 }
				maxColorPicker:SetColor(mc[1] or 1, mc[2] or 1, mc[3] or 1, mc[4] or 1)
				maxColorPicker:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
					cfg.maxColor = { r, g, b, a }
					notifyRefresh()
				end)
				maxColorPicker:SetFullWidth(false)
				maxColorPicker:SetRelativeWidth(0.5)
				group:AddChild(maxColorPicker)

				refreshMaxColorControls()

				return {
					refreshMaxColorControls = refreshMaxColorControls,
				}
			end

			local function addBehaviorControls(parent, cfg, pType, colorHooks)
				local group = addon.functions.createContainer("InlineGroup", "Flow")
				group:SetTitle(L["Behavior"] or "Behavior")
				group:SetFullWidth(true)
				parent:AddChild(group)

				local cbReverse = addon.functions.createCheckboxAce(L["Reverse fill"] or "Reverse fill", cfg.reverseFill == true, function(_, _, val)
					cfg.reverseFill = val and true or false
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end)
				cbReverse:SetFullWidth(false)
				cbReverse:SetRelativeWidth(0.5)
				group:AddChild(cbReverse)

				if pType ~= "RUNES" then
					local cbVertical = addon.functions.createCheckboxAce(L["Vertical orientation"] or "Vertical orientation", cfg.verticalFill == true, function(_, _, val)
						cfg.verticalFill = val and true or false
						if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
						buildSpec(container, specIndex)
					end)
					cbVertical:SetFullWidth(false)
					cbVertical:SetRelativeWidth(0.5)
					group:AddChild(cbVertical)

					local cbSmooth = addon.functions.createCheckboxAce(L["Smooth fill"] or "Smooth fill", cfg.smoothFill == true, function(_, _, val)
						cfg.smoothFill = val and true or false
						if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
					end)
					cbSmooth:SetFullWidth(false)
					cbSmooth:SetRelativeWidth(0.5)
					group:AddChild(cbSmooth)

					local cbGlow = addon.functions.createCheckboxAce(L["Glow at maximum"] or "Glow at maximum", cfg.glowAtCap == true, function(_, _, val)
						cfg.glowAtCap = val and true or false
						if colorHooks and colorHooks.refreshMaxColorControls then colorHooks.refreshMaxColorControls() end
						if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
					end)
					cbGlow:SetFullWidth(false)
					cbGlow:SetRelativeWidth(0.5)
					group:AddChild(cbGlow)
				else
					-- Preserve flow layout when vertical option is hidden for RUNES
					local spacer = addon.functions.createLabelAce("")
					spacer:SetFullWidth(false)
					spacer:SetRelativeWidth(0.5)
					group:AddChild(spacer)
				end
			end
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
				tinsert(cfgOrder, "HEALTH")
			end
			for _, pType in ipairs(addon.Aura.ResourceBars.classPowerTypes) do
				if available[pType] then
					local cfg = dbSpec[pType]
					if cfg and cfg.enabled == true then
						cfgList[pType] = _G["POWER_TYPE_" .. pType] or _G[pType] or pType
						tinsert(cfgOrder, pType)
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
				local verticalHealth = hCfg.verticalFill == true
				local labelWidth = verticalHealth and (L["Bar thickness"] or "Bar thickness") or (L["Bar length"] or "Bar length")
				local labelHeight = verticalHealth and (L["Bar length"] or "Bar length") or (L["Bar thickness"] or "Bar thickness")
				local sw = addon.functions.createSliderAce(labelWidth, hCfg.width or DEFAULT_HEALTH_WIDTH, 1, 2000, 1, function(self, _, val)
					hCfg.width = val
					if specIndex == addon.variables.unitSpec then addon.Aura.ResourceBars.SetHealthBarSize(hCfg.width, hCfg.height or DEFAULT_HEALTH_HEIGHT) end
				end)
				sw:SetFullWidth(false)
				sw:SetRelativeWidth(0.5)
				sizeRow:AddChild(sw)
				local sh = addon.functions.createSliderAce(labelHeight, hCfg.height or DEFAULT_HEALTH_HEIGHT, 1, 2000, 1, function(self, _, val)
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
				local textOffsetSliders
				local function updateHealthOffsetDisabled()
					if not textOffsetSliders then return end
					local disabled = (hCfg.textStyle or "PERCENT") == "NONE"
					for _, ctrl in ipairs(textOffsetSliders) do
						if ctrl then ctrl:SetDisabled(disabled) end
					end
				end
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
					updateHealthOffsetDisabled()
				end
				buildHealthTextRow()
				textOffsetSliders = { addTextOffsetControlsUI(groupConfig, hCfg, specIndex) }
				updateHealthOffsetDisabled()
				addFontControls(groupConfig, hCfg)
				local colorControls = addColorControls(groupConfig, hCfg, specIndex)

				-- Bar Texture (Health)
				local function buildTextureOptions()
					local map = {
						["DEFAULT"] = DEFAULT,
						[BLIZZARD_TEX] = "Blizzard: UI-StatusBar",
						["Interface\\Buttons\\WHITE8x8"] = "Flat (white, tintable)",
						["Interface\\Tooltips\\UI-Tooltip-Background"] = "Dark Flat (Tooltip bg)",
						["Interface\\RaidFrame\\Raid-Bar-Hp-Fill"] = "Raid HP Fill",
						["Interface\\RaidFrame\\Raid-Bar-Resource-Fill"] = "Raid Resource Fill",
						["Interface\\TargetingFrame\\UI-StatusBar"] = "Blizzard Unit Frame",
						["Interface\\UnitPowerBarAlt\\Generic1Texture"] = "Alternate Power",
						["Interface\\PetBattles\\PetBattle-HealthBar"] = "Pet Battle",
					}
					for name, path in pairs(LSM and LSM:HashTable("statusbar") or {}) do
						if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
					end
					local noDefault = {}
					for k, v in pairs(map) do
						if k ~= "DEFAULT" then noDefault[k] = v end
					end
					local sorted, order = addon.functions.prepareListForDropdown(noDefault)
					sorted["DEFAULT"] = DEFAULT
					table.insert(order, 1, "DEFAULT")
					return sorted, order
				end

				local listTex, orderTex = buildTextureOptions()
				local dropTex = addon.functions.createDropdownAce(L["Bar Texture"], listTex, orderTex, function(_, _, key)
					hCfg.barTexture = key
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
				end)
				local cur = hCfg.barTexture or "DEFAULT"
				if not listTex[cur] then cur = "DEFAULT" end
				dropTex:SetValue(cur)
				groupConfig:AddChild(dropTex)
				ResourceBars.ui.textureDropdown = dropTex
				dropTex._rb_cfgRef = hCfg
				addBackdropControls(groupConfig, hCfg)
				addBehaviorControls(groupConfig, hCfg, "HEALTH", colorControls)

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
				local labelWidth = vertical and (L["Bar thickness"] or "Bar thickness") or (L["Bar length"] or "Bar length")
				local labelHeight = vertical and (L["Bar length"] or "Bar length") or (L["Bar thickness"] or "Bar thickness")
				local sw = addon.functions.createSliderAce(labelWidth, curW, 1, 2000, 1, function(self, _, val)
					cfg.width = val
					if specIndex == addon.variables.unitSpec then addon.Aura.ResourceBars.SetPowerBarSize(val, cfg.height or defaultH, sel) end
				end)
				sw:SetFullWidth(false)
				sw:SetRelativeWidth(0.5)
				sizeRow2:AddChild(sw)
				local sh = addon.functions.createSliderAce(labelHeight, curH, 1, 2000, 1, function(self, _, val)
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
					local textOffsetSliders
					local function updateOffsetDisabled()
						if not textOffsetSliders then return end
						local disabled = (cfg.textStyle or curStyle) == "NONE"
						for _, ctrl in ipairs(textOffsetSliders) do
							if ctrl then ctrl:SetDisabled(disabled) end
						end
					end
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
						updateOffsetDisabled()
					end
					buildTextRow()
					textOffsetSliders = { addTextOffsetControlsUI(groupConfig, cfg, specIndex) }
					updateOffsetDisabled()
					addFontControls(groupConfig, cfg)
					local colorControls = addColorControls(groupConfig, cfg, specIndex)

					-- Bar Texture (Power types incl. RUNES)
					local function buildTextureOptions2()
						local map = {
							["DEFAULT"] = DEFAULT,
							[BLIZZARD_TEX] = "Blizzard: UI-StatusBar",
							["Interface\\Buttons\\WHITE8x8"] = "Flat (white, tintable)",
							["Interface\\Tooltips\\UI-Tooltip-Background"] = "Dark Flat (Tooltip bg)",
							["Interface\\RaidFrame\\Raid-Bar-Hp-Fill"] = "Raid HP Fill",
							["Interface\\RaidFrame\\Raid-Bar-Resource-Fill"] = "Raid Resource Fill",
							["Interface\\TargetingFrame\\UI-StatusBar"] = "Blizzard Unit Frame",
							["Interface\\UnitPowerBarAlt\\Generic1Texture"] = "Alternate Power",
							["Interface\\PetBattles\\PetBattle-HealthBar"] = "Pet Battle",
						}
						for name, path in pairs(LSM and LSM:HashTable("statusbar") or {}) do
							if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
						end
						local noDefault = {}
						for k, v in pairs(map) do
							if k ~= "DEFAULT" then noDefault[k] = v end
						end
						local sorted, order = addon.functions.prepareListForDropdown(noDefault)
						sorted["DEFAULT"] = DEFAULT
						table.insert(order, 1, "DEFAULT")
						return sorted, order
					end

					local listTex2, orderTex2 = buildTextureOptions2()
					local dropTex2 = addon.functions.createDropdownAce(L["Bar Texture"], listTex2, orderTex2, function(_, _, key)
						cfg.barTexture = key
						if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
					end)
					local cur2 = cfg.barTexture or "DEFAULT"
					if not listTex2[cur2] then cur2 = "DEFAULT" end
					dropTex2:SetValue(cur2)
					groupConfig:AddChild(dropTex2)
					ResourceBars.ui.textureDropdown = dropTex2
					dropTex2._rb_cfgRef = cfg
					addBackdropControls(groupConfig, cfg)
					addBehaviorControls(groupConfig, cfg, sel, colorControls)
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
					addBackdropControls(groupConfig, cfg)
					addBehaviorControls(groupConfig, cfg, sel)
				end

				-- Separator toggle + color picker row (eligible bars only)
				local eligible = addon.Aura.ResourceBars.separatorEligible
				if eligible and eligible[sel] then
					local sepRow = addon.functions.createContainer("SimpleGroup", "Flow")
					sepRow:SetFullWidth(true)
					local sepColor
					local sepThickness
					local cbSep = addon.functions.createCheckboxAce(L["Show separator"], cfg.showSeparator == true, function(self, _, val)
						cfg.showSeparator = val and true or false
						if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
						if sepColor then sepColor:SetDisabled(not cfg.showSeparator) end
						if sepThickness then sepThickness:SetDisabled(not cfg.showSeparator) end
					end)
					cbSep:SetFullWidth(false)
					cbSep:SetRelativeWidth(0.5)
					sepRow:AddChild(cbSep)
					sepColor = AceGUI:Create("ColorPicker")
					sepColor:SetLabel(L["Separator Color"] or "Separator Color")
					local sc = cfg.separatorColor or SEP_DEFAULT
					sepColor:SetColor(sc[1] or 1, sc[2] or 1, sc[3] or 1, sc[4] or 0.5)
					sepColor:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
						cfg.separatorColor = { r, g, b, a }
						if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
					end)
					sepColor:SetFullWidth(false)
					sepColor:SetRelativeWidth(0.5)
					sepColor:SetDisabled(not (cfg.showSeparator == true))
					sepRow:AddChild(sepColor)

					sepThickness = addon.functions.createSliderAce(L["Separator thickness"] or "Separator thickness", cfg.separatorThickness or SEPARATOR_THICKNESS, 1, 10, 1, function(_, _, val)
						cfg.separatorThickness = val
						if addon.Aura.ResourceBars and addon.Aura.ResourceBars.MaybeRefreshActive then addon.Aura.ResourceBars.MaybeRefreshActive(specIndex) end
					end)
					sepThickness:SetFullWidth(false)
					sepThickness:SetRelativeWidth(0.5)
					sepThickness:SetDisabled(not (cfg.showSeparator == true))
					sepRow:AddChild(sepThickness)
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
			scroll:DoLayout()
		end

		tabGroup:SetTabs(specTabs)
		tabGroup:SetCallback("OnGroupSelected", function(tabContainer, _, val) buildSpec(tabContainer, val) end)
		wrapper:AddChild(tabGroup)
		tabGroup:SelectTab(addon.variables.unitSpec or specTabs[1].value)
	end
	scroll:DoLayout()
end

local function updateHealthBar(evt)
	if healthBar and healthBar:IsVisible() then
		local maxHealth = healthBar._lastMax
		if not maxHealth then
			maxHealth = UnitHealthMax("player")
			healthBar._lastMax = maxHealth
			healthBar:SetMinMaxValues(0, maxHealth)
		end
		local curHealth = UnitHealth("player")
		-- Always compute absorbs fresh; caching combined/lastCombined is unnecessary now
		local abs = UnitGetTotalAbsorbs("player") or 0
		if abs > maxHealth then abs = maxHealth end
		local settings = getBarSettings("HEALTH") or {}
		local smooth = settings.smoothFill == true
		if smooth then
			healthBar._smoothTarget = curHealth
			if not healthBar._smoothInitialized then
				healthBar:SetValue(curHealth)
				healthBar._smoothInitialized = true
			end
		else
			healthBar._smoothTarget = nil
			if healthBar._lastVal ~= curHealth then healthBar:SetValue(curHealth) end
			healthBar._smoothInitialized = nil
		end
		healthBar._lastVal = curHealth

		local percent = (curHealth / max(maxHealth, 1)) * 100
		local percentStr = tostring(floor(percent + 0.5))
		if healthBar.text then
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
		local baseR, baseG, baseB, baseA
		if settings.useBarColor then
			local custom = settings.barColor or { 1, 1, 1, 1 }
			baseR, baseG, baseB, baseA = custom[1] or 1, custom[2] or 1, custom[3] or 1, custom[4] or 1
		else
			if percent >= 60 then
				baseR, baseG, baseB, baseA = 0, 0.7, 0, 1
			elseif percent >= 40 then
				baseR, baseG, baseB, baseA = 0.7, 0.7, 0, 1
			else
				baseR, baseG, baseB, baseA = 0.7, 0, 0, 1
			end
		end
		healthBar._baseColor = healthBar._baseColor or {}
		healthBar._baseColor[1], healthBar._baseColor[2], healthBar._baseColor[3], healthBar._baseColor[4] = baseR, baseG, baseB, baseA

		local reachedCap = maxHealth > 0 and curHealth >= maxHealth
		local useMaxColor = settings.glowAtCap == true and settings.useMaxColor == true
		local finalR, finalG, finalB, finalA = baseR, baseG, baseB, baseA
		if useMaxColor and reachedCap then
			local maxCol = settings.maxColor or { 1, 1, 1, 1 }
			finalR, finalG, finalB, finalA = maxCol[1] or baseR, maxCol[2] or baseG, maxCol[3] or baseB, maxCol[4] or baseA
		end

		local last = healthBar._lastColor or {}
		if last[1] ~= finalR or last[2] ~= finalG or last[3] ~= finalB or last[4] ~= finalA then
			healthBar:SetStatusBarColor(finalR, finalG, finalB, finalA or 1)
			healthBar._lastColor = { finalR, finalG, finalB, finalA or 1 }
		end

		setGlow(healthBar, settings, settings.glowAtCap == true and reachedCap, finalR, finalG, finalB)

		local absorbBar = healthBar.absorbBar
		if absorbBar then
			if absorbBar._lastMax ~= maxHealth then
				absorbBar:SetMinMaxValues(0, maxHealth)
				absorbBar._lastMax = maxHealth
			end
			if absorbBar._lastVal ~= abs then
				absorbBar:SetValue(abs)
				absorbBar._lastVal = abs
			end
		end
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
		if mainFrame.SetClampedToScreen then mainFrame:SetClampedToScreen(true) end
		mainFrame:Show()
		healthBar:Show()
		return
	end

	-- Reuse existing named frames if they still exist from a previous enable
	mainFrame = _G["EQOLResourceFrame"] or CreateFrame("frame", "EQOLResourceFrame", UIParent)
	if mainFrame:GetParent() ~= UIParent then mainFrame:SetParent(UIParent) end
	if mainFrame.SetClampedToScreen then mainFrame:SetClampedToScreen(true) end
	healthBar = _G["EQOLHealthBar"] or CreateFrame("StatusBar", "EQOLHealthBar", UIParent, "BackdropTemplate")
	if healthBar:GetParent() ~= UIParent then healthBar:SetParent(UIParent) end
	do
		local cfg = getBarSettings("HEALTH")
		local w = (cfg and cfg.width) or DEFAULT_HEALTH_WIDTH
		local h = (cfg and cfg.height) or DEFAULT_HEALTH_HEIGHT
		healthBar:SetSize(w, h)
	end
	do
		local cfgTex = getBarSettings("HEALTH") or {}
		healthBar:SetStatusBarTexture(resolveTexture(cfgTex))
	end
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
		anchor.autoSpacing = nil
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
		anchor.autoSpacing = nil
		rel = UIParent
	end
	healthBar:ClearAllPoints()
	healthBar:SetPoint(anchor.point or "TOPLEFT", rel, anchor.relativePoint or anchor.point or "TOPLEFT", anchor.x or 0, anchor.y or 0)
	local settings = getBarSettings("HEALTH")
	healthBar._cfg = settings
	applyBackdrop(healthBar, settings)

	if not healthBar.text then healthBar.text = healthBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	applyFontToString(healthBar.text, settings)
	applyTextPosition(healthBar, settings, 3, 0)
	configureBarBehavior(healthBar, settings, "HEALTH")

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
		point = point or "TOPLEFT"
		info.point = point
		info.relativeFrame = relName
		info.relativePoint = relPoint or point
		info.x = Snap(self, xOfs or 0)
		info.y = Snap(self, yOfs or 0)
		info.autoSpacing = nil
		self:ClearAllPoints()
		self:SetPoint(info.point, rel or UIParent, info.relativePoint or info.point, info.x or 0, info.y or 0)
	end)

	local absorbBar = CreateFrame("StatusBar", "EQOLAbsorbBar", healthBar)
	absorbBar:SetAllPoints(healthBar)
	absorbBar:SetFrameStrata(healthBar:GetFrameStrata())
	absorbBar:SetFrameLevel((healthBar:GetFrameLevel() + 1))
	do
		local cfgTexH = getBarSettings("HEALTH") or {}
		absorbBar:SetStatusBarTexture(resolveTexture(cfgTexH))
	end
	absorbBar:SetStatusBarColor(0.8, 0.8, 0.8, 0.8)
	if settings and settings.verticalFill then
		absorbBar:SetOrientation("VERTICAL")
	else
		absorbBar:SetOrientation("HORIZONTAL")
	end
	if absorbBar.SetReverseFill then absorbBar:SetReverseFill(settings and settings.reverseFill == true) end
	local absorbTex = absorbBar:GetStatusBarTexture()
	if absorbTex then
		if settings and settings.verticalFill then
			absorbTex:SetRotation(math.pi / 2)
		else
			absorbTex:SetRotation(0)
		end
	end
	healthBar.absorbBar = absorbBar

	updateHealthBar("UNIT_ABSORB_AMOUNT_CHANGED")

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

local POWER_ENUM = {}
for k, v in pairs(EnumPowerType or {}) do
	local key = k:gsub("(%l)(%u)", "%1_%2"):upper()
	POWER_ENUM[key] = v
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
	RUNES = true,
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
			local col = bar._dkColor or DK_SPEC_COLOR[addon.variables.unitSpec] or DK_SPEC_COLOR[1]
			local r, g, b = col[1], col[2], col[3]
			local grey = 0.35
			bar._rune = bar._rune or {}
			bar._runeOrder = bar._runeOrder or {}
			bar._charging = bar._charging or {}
			local charging = bar._charging
			-- Always rescan all 6 runes (cheap + keeps cache in sync)
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
			tsort(charging, function(a, b)
				local ra = (bar._rune[a].start + bar._rune[a].duration)
				local rb = (bar._rune[b].start + bar._rune[b].duration)
				return ra < rb
			end)
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
					local prog = info.ready and 1 or min(1, max(0, (now - info.start) / max(info.duration, 1)))
					sb:SetValue(prog)
					local wantReady = info.ready or prog >= 1
					if sb._isReady ~= wantReady then
						sb._isReady = wantReady
						if wantReady then
							sb:SetStatusBarColor(r, g, b)
						else
							sb:SetStatusBarColor(grey, grey, grey)
						end
					end
					if sb.fs then
						if cfg.showCooldownText then
							local remain = ceil((info.start + info.duration) - now)
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
									prog = min(1, max(0, (n - data.start) / max(data.duration, 1)))
									if prog >= 1 then
										if not self._runeResync then
											self._runeResync = true
											if After then
												After(0, function()
													self._runeResync = false
													updatePowerBar("RUNES")
												end)
											else
												updatePowerBar("RUNES")
											end
										end
										return
									end
									allReady = false
								end
								sb:SetValue(prog)
								if sb.fs then
									if cfgOnUpdate.showCooldownText and not data.ready then
										local remain = ceil((data.start + data.duration) - n)
										if remain ~= sb._lastRemain then
											if remain > 0 then
												sb.fs:SetText(tostring(remain))
											else
												sb.fs:SetText("")
											end
											sb._lastRemain = remain
										end
										sb.fs:Show()
									else
										if sb._lastRemain ~= nil then
											sb.fs:SetText("")
											sb._lastRemain = nil
										end
										sb.fs:Hide()
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
		local pType = POWER_ENUM[type]
		local cfg = getBarSettings(type) or {}
		local maxPower = bar._lastMax
		if not maxPower then
			maxPower = UnitPowerMax("player", pType)
			bar._lastMax = maxPower
			bar:SetMinMaxValues(0, maxPower)
		end
		local curPower = UnitPower("player", pType)

		local style = bar._style or ((type == "MANA") and "PERCENT" or "CURMAX")
		local smooth = cfg.smoothFill == true
		if smooth then
			bar._smoothTarget = curPower
			if not bar._smoothInitialized then
				bar:SetValue(curPower)
				bar._smoothInitialized = true
			end
		else
			bar._smoothTarget = nil
			if bar._lastVal ~= curPower then bar:SetValue(curPower) end
			bar._smoothInitialized = nil
		end
		bar._lastVal = curPower
		if bar.text then
			if style == "NONE" then
				bar.text:SetText("")
				bar.text:Hide()
			else
				local text
				if style == "PERCENT" then
					text = tostring(floor(((curPower / max(maxPower, 1)) * 100) + 0.5))
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
		bar._baseColor = bar._baseColor or {}
		if bar._baseColor[1] == nil then
			local br, bg, bb, ba = bar:GetStatusBarColor()
			bar._baseColor[1], bar._baseColor[2], bar._baseColor[3], bar._baseColor[4] = br, bg, bb, ba or 1
		end

		local reachedCap = curPower >= max(maxPower, 1)
		local useMaxColor = cfg.glowAtCap == true and cfg.useMaxColor == true
		if useMaxColor and reachedCap then
			local maxCol = cfg.maxColor or { 1, 1, 1, 1 }
			local mr, mg, mb, ma = maxCol[1] or 1, maxCol[2] or 1, maxCol[3] or 1, maxCol[4] or (bar._baseColor[4] or 1)
			local last = bar._lastColor or {}
			if bar._usingMaxColor ~= true or last[1] ~= mr or last[2] ~= mg or last[3] ~= mb or last[4] ~= ma then
				bar:SetStatusBarColor(mr, mg, mb, ma)
				bar._lastColor = { mr, mg, mb, ma }
				bar._usingMaxColor = true
			end
		else
			local base = bar._baseColor
			if base then
				local last = bar._lastColor or {}
				if bar._usingMaxColor == true or last[1] ~= base[1] or last[2] ~= base[2] or last[3] ~= base[3] or last[4] ~= base[4] then
					bar:SetStatusBarColor(base[1] or 1, base[2] or 1, base[3] or 1, base[4] or 1)
					bar._lastColor = { base[1] or 1, base[2] or 1, base[3] or 1, base[4] or 1 }
				end
			end
			bar._usingMaxColor = false
		end

		local cr, cg, cb = bar:GetStatusBarColor()
		setGlow(bar, cfg, cfg.glowAtCap == true and reachedCap, cr, cg, cb)
	end
end

-- Create/update separator ticks for a given bar type if enabled
local function updateBarSeparators(pType)
	local eligible = ResourceBars.separatorEligible
	if pType ~= "RUNES" and (not eligible or not eligible[pType]) then return end
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
	if pType == "RUNES" then
		-- Runes don't use UnitPowerMax; always 6 segments
		segments = 6
	elseif pType == "ENERGY" then
		segments = 10
	else
		local enumId = POWER_ENUM[pType]
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

	-- Ensure we draw separators above any child frames (e.g., Rune sub-bars)
	if not bar._sepOverlay then
		bar._sepOverlay = CreateFrame("Frame", nil, bar)
		bar._sepOverlay:SetAllPoints(bar)
		bar._sepOverlay:EnableMouse(false)
	end
	-- Keep overlay on top of child frames
	local baseLevel = (bar:GetFrameLevel() or 1)
	bar._sepOverlay:SetFrameStrata(bar:GetFrameStrata())
	bar._sepOverlay:SetFrameLevel(baseLevel + 20)

	bar.separatorMarks = bar.separatorMarks or {}
	-- Ensure existing marks render on the overlay frame
	for _, tx in ipairs(bar.separatorMarks) do
		if tx and tx.GetParent and tx:GetParent() ~= bar._sepOverlay then tx:SetParent(bar._sepOverlay) end
	end
	local needed = segments - 1
	local w = max(1, bar:GetWidth() or 0)
	local h = max(1, bar:GetHeight() or 0)
	local vertical = cfg and cfg.verticalFill == true
	local span = vertical and h or w
	local desiredThickness = (cfg and cfg.separatorThickness) or SEPARATOR_THICKNESS
	local thickness
	if vertical then
		local segH = span / segments
		thickness = min(desiredThickness, max(1, floor(segH - 1)))
	else
		local segW = span / segments
		thickness = min(desiredThickness, max(1, floor(segW - 1)))
	end
	local sc = (cfg and cfg.separatorColor) or SEP_DEFAULT
	local r, g, b, a = sc[1] or 1, sc[2] or 1, sc[3] or 1, sc[4] or 0.5

	if
		bar._sepW == w
		and bar._sepH == h
		and bar._sepSegments == segments
		and bar._sepR == r
		and bar._sepG == g
		and bar._sepB == b
		and bar._sepA == a
		and bar._sepThickness == thickness
		and bar._sepVertical == vertical
	then
		return
	end

	-- Ensure we have enough textures
	for i = #bar.separatorMarks + 1, needed do
		local tx = bar._sepOverlay:CreateTexture(nil, "OVERLAY")
		tx:SetColorTexture(r, g, b, a)
		bar.separatorMarks[i] = tx
	end
	-- Position visible separators
	for i = 1, needed do
		local tx = bar.separatorMarks[i]
		tx:ClearAllPoints()
		local frac = i / segments
		local half = floor(thickness * 0.5)
		tx:SetColorTexture(r, g, b, a)
		if vertical then
			local y = Snap(bar, h * frac)
			tx:SetPoint("TOP", bar._sepOverlay, "TOP", 0, -(y - max(0, half)))
			tx:SetSize(w, thickness)
		else
			local x = Snap(bar, w * frac)
			tx:SetPoint("LEFT", bar._sepOverlay, "LEFT", x - max(0, half), 0)
			tx:SetSize(thickness, h)
		end
		tx:Show()
	end
	-- Hide extras
	for i = needed + 1, #bar.separatorMarks do
		bar.separatorMarks[i]:Hide()
	end
	-- Cache current geometry and color to fast-exit next time
	bar._sepW, bar._sepH, bar._sepSegments, bar._sepThickness = w, h, segments, thickness
	bar._sepR, bar._sepG, bar._sepB, bar._sepA = r, g, b, a
	bar._sepVertical = vertical
end

-- Layout helper for DK RUNES: create or resize 6 child statusbars
function layoutRunes(bar)
	if not bar then return end
	bar.runes = bar.runes or {}
	local count = 6
	local gap = 0
	local w = max(1, bar:GetWidth() or 0)
	local h = max(1, bar:GetHeight() or 0)
	local cfg = getBarSettings("RUNES") or {}
	local show = cfg.showCooldownText == true
	local size = cfg.cooldownTextFontSize or 16
	local fontPath = resolveFontFace(cfg)
	local fontOutline = resolveFontOutline(cfg)
	local fr, fg, fb, fa = resolveFontColor(cfg)
	local vertical = cfg.verticalFill == true
	local segPrimary
	if vertical then
		segPrimary = max(1, floor((h - gap * (count - 1)) / count + 0.5))
	else
		segPrimary = max(1, floor((w - gap * (count - 1)) / count + 0.5))
	end
	for i = 1, count do
		local sb = bar.runes[i]
		if not sb then
			sb = CreateFrame("StatusBar", bar:GetName() .. "Rune" .. i, bar)
			local cfgR = getBarSettings("RUNES") or {}
			sb:SetStatusBarTexture(resolveTexture(cfgR))
			sb:SetMinMaxValues(0, 1)
			sb:Show()
			bar.runes[i] = sb
		end
		do
			local cfgR2 = getBarSettings("RUNES") or {}
			local wantTex = resolveTexture(cfgR2)
			if sb._rb_tex ~= wantTex then
				sb:SetStatusBarTexture(wantTex)
				sb._rb_tex = wantTex
			end
		end
		sb:ClearAllPoints()
		if vertical then
			sb:SetWidth(w)
			sb:SetHeight(segPrimary)
			sb:SetOrientation("VERTICAL")
			if i == 1 then
				sb:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
			else
				sb:SetPoint("BOTTOM", bar.runes[i - 1], "TOP", 0, gap)
			end
			if i == count then sb:SetPoint("TOP", bar, "TOP", 0, 0) end
		else
			sb:SetHeight(h)
			sb:SetOrientation("HORIZONTAL")
			if i == 1 then
				sb:SetPoint("LEFT", bar, "LEFT", 0, 0)
			else
				sb:SetPoint("LEFT", bar.runes[i - 1], "RIGHT", gap, 0)
			end
			if i == count then
				sb:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
			else
				sb:SetWidth(segPrimary)
			end
		end
		-- cooldown text per segment
		if not sb.fs then
			sb.fs = sb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			sb.fs:SetPoint("CENTER", sb, "CENTER", 0, 0)
		end
		if sb._fsSize ~= size or sb._fsFont ~= fontPath or sb._fsOutline ~= fontOutline then
			setFontWithFallback(sb.fs, fontPath, size, fontOutline)
			sb._fsSize = size
			sb._fsFont = fontPath
			sb._fsOutline = fontOutline
		end
		sb.fs:SetTextColor(fr, fg, fb, fa)
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
	bar._cfg = settings
	local defaultStyle = (type == "MANA") and "PERCENT" or "CURMAX"
	bar._style = settings and settings.textStyle or defaultStyle
	bar:SetSize(w, h)
	do
		local cfg2 = getBarSettings(type) or {}
		bar:SetStatusBarTexture(resolveTexture(cfg2))
	end
	bar:SetClampedToScreen(true)
	local stackSpacing = DEFAULT_STACK_SPACING

	-- Anchor handling: during spec/trait refresh we suppress inter-bar anchoring
	local a = getAnchor(type, addon.variables.unitSpec)
	local allowMove = true
	if ResourceBars._suspendAnchors then
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", a.x or 0, a.y or 0)
	else
		if a.point then
			if
				a.autoSpacing
				or (a.autoSpacing == nil and isEQOLFrameName(a.relativeFrame) and (a.point or "TOPLEFT") == "TOPLEFT" and (a.relativePoint or "BOTTOMLEFT") == "BOTTOMLEFT" and (a.x or 0) == 0)
			then
				a.x = 0
				a.y = stackSpacing
				a.autoSpacing = true
			end
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
				a.autoSpacing = nil
				rel = UIParent
			end
			if rel and rel.GetName and rel:GetName() ~= "UIParent" then allowMove = false end
			bar:ClearAllPoints()
			bar:SetPoint(a.point, rel or UIParent, a.relativePoint or a.point, a.x or 0, a.y or 0)
		elseif anchor then
			-- Default stack below provided anchor and persist default anchor in DB
			bar:ClearAllPoints()
			bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, stackSpacing)
			a.point = "TOPLEFT"
			a.relativeFrame = anchor:GetName() or "UIParent"
			a.relativePoint = "BOTTOMLEFT"
			a.x = 0
			a.y = stackSpacing
			a.autoSpacing = true
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
	end

	-- Visuals and text
	applyBackdrop(bar, settings)
	if type ~= "RUNES" then applyBarFillColor(bar, settings, type) end

	if type ~= "RUNES" then
		if not bar.text then bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
		applyFontToString(bar.text, settings)
		applyTextPosition(bar, settings, 3, 0)
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
	configureBarBehavior(bar, settings, type)

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
		point = point or "TOPLEFT"
		local relName = rel and rel.GetName and rel:GetName() or "UIParent"
		info.point = point
		info.relativeFrame = relName
		info.relativePoint = relPoint or point
		info.x = Snap(self, xOfs or 0)
		info.y = Snap(self, yOfs or 0)
		info.autoSpacing = false
		self:ClearAllPoints()
		self:SetPoint(info.point, rel or UIParent, info.relativePoint or info.point, info.x or 0, info.y or 0)
	end)

	powerbar[type] = bar
	bar:Show()
	if type == "RUNES" then ResourceBars.ForceRuneRecolor() end
	updatePowerBar(type)
	if type == "RUNES" then
		updateBarSeparators("RUNES")
	elseif ResourceBars.separatorEligible[type] then
		updateBarSeparators(type)
	end

	-- Ensure dependents re-anchor when this bar changes size
	bar:SetScript("OnSizeChanged", function()
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorDependentsOf then addon.Aura.ResourceBars.ReanchorDependentsOf("EQOL" .. type .. "Bar") end
		if type == "RUNES" then
			layoutRunes(bar)
			updateBarSeparators("RUNES")
		elseif ResourceBars.separatorEligible[type] then
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
	local function currentDruidForm()
		if not isDruid then return nil end
		local idx = GetShapeshiftForm() or 0
		local key = formIndexToKey[idx]
		if key then return key end
		local name
		if GetShapeshiftFormInfo then
			local r1, r2 = GetShapeshiftFormInfo(idx)
			if type(r1) == "string" then
				name = r1
			elseif type(r2) == "string" then
				name = r2
			end
		end
		key = mapFormNameToKey(name)
		if key then return key end
		return "HUMANOID"
	end
	local druidForm = currentDruidForm()
	local mainPowerBar
	local lastBar
	local specCfg = addon.db.personalResourceBarSettings
		and addon.db.personalResourceBarSettings[addon.variables.unitClass]
		and addon.db.personalResourceBarSettings[addon.variables.unitClass][addon.variables.unitSpec]

	local desiredVisibility = {}

	if
		powertypeClasses[addon.variables.unitClass]
		and powertypeClasses[addon.variables.unitClass][addon.variables.unitSpec]
		and powertypeClasses[addon.variables.unitClass][addon.variables.unitSpec].MAIN
	then
		local mType = powertypeClasses[addon.variables.unitClass][addon.variables.unitSpec].MAIN
		local enabledMain = specCfg and specCfg[mType] and specCfg[mType].enabled == true
		if enabledMain then
			createPowerBar(mType, ((specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true) and EQOLHealthBar or nil))
			mainPowerBar = mType
			lastBar = mainPowerBar
		end
		desiredVisibility[mType] = enabledMain
	end

	for _, pType in ipairs(classPowerTypes) do
		local showBar = false
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
				if FREQUENT[pType] then powerfrequent[pType] = true end
				if pType == mainPowerBar then
					showBar = true
				elseif pType == "MANA" then
					createPowerBar(pType, powerbar[lastBar] or ((specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true) and EQOLHealthBar or nil))
					lastBar = pType
					showBar = true
				elseif pType == "COMBO_POINTS" and druidForm == "CAT" then
					createPowerBar(pType, powerbar[lastBar] or ((specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true) and EQOLHealthBar or nil))
					lastBar = pType
					showBar = true
				elseif powerToken == pType and powerToken ~= mainPowerBar then
					createPowerBar(pType, powerbar[lastBar] or ((specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true) and EQOLHealthBar or nil))
					lastBar = pType
					showBar = true
				end
			elseif formAllowed then
				if FREQUENT[pType] then powerfrequent[pType] = true end
				if mainPowerBar ~= pType then
					createPowerBar(pType, powerbar[lastBar] or ((specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true) and EQOLHealthBar or nil))
					lastBar = pType
				end
				showBar = true
			end
		end

		desiredVisibility[pType] = showBar
	end

	for pType, wantVisible in pairs(desiredVisibility) do
		local bar = powerbar[pType]
		if bar then
			if wantVisible then
				if not bar:IsShown() then bar:Show() end
			else
				if bar:IsShown() then bar:Hide() end
			end
		end
	end

	-- Toggle Health visibility according to config
	if healthBar then
		local showHealth = specCfg and specCfg.HEALTH and specCfg.HEALTH.enabled == true
		if showHealth then
			if not healthBar:IsShown() then healthBar:Show() end
		else
			if healthBar:IsShown() then healthBar:Hide() end
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

-- Coalesce spec/trait refreshes to avoid duplicate work or timing races
local function scheduleSpecRefresh()
	if not After then
		-- First detach all bar points to avoid transient loops
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.DetachAllBars then addon.Aura.ResourceBars.DetachAllBars() end
		ResourceBars._suspendAnchors = true
		setPowerbars()
		ResourceBars._suspendAnchors = false
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorAll then addon.Aura.ResourceBars.ReanchorAll() end
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ForceRuneRecolor then addon.Aura.ResourceBars.ForceRuneRecolor() end
		updatePowerBar("RUNES")
		return
	end
	if frameAnchor and frameAnchor._specRefreshScheduled then return end
	if frameAnchor then frameAnchor._specRefreshScheduled = true end
	After(0.08, function()
		if frameAnchor then frameAnchor._specRefreshScheduled = false end
		-- First detach all bar points to avoid transient loops
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.DetachAllBars then addon.Aura.ResourceBars.DetachAllBars() end
		ResourceBars._suspendAnchors = true
		setPowerbars()
		ResourceBars._suspendAnchors = false
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorAll then addon.Aura.ResourceBars.ReanchorAll() end
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
		if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ForceRuneRecolor then addon.Aura.ResourceBars.ForceRuneRecolor() end
		updatePowerBar("RUNES")
	end)
end

local function eventHandler(self, event, unit, arg1)
	if event == "UNIT_DISPLAYPOWER" and unit == "player" then
		setPowerbars()
	elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
		scheduleSpecRefresh()
	elseif event == "TRAIT_CONFIG_UPDATED" then
		scheduleSpecRefresh()
	elseif event == "PLAYER_ENTERING_WORLD" then
		updateHealthBar("UNIT_ABSORB_AMOUNT_CHANGED")
		setPowerbars()
	elseif event == "UPDATE_SHAPESHIFT_FORM" then
		setPowerbars()
		-- After initial creation, run a re-anchor pass to ensure all dependent anchors resolve
		if After then
			After(0.05, function()
				if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorAll then addon.Aura.ResourceBars.ReanchorAll() end
				if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
			end)
		else
			if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.ReanchorAll then addon.Aura.ResourceBars.ReanchorAll() end
			if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
		end
	elseif (event == "UNIT_MAXHEALTH" or event == "UNIT_HEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED") and healthBar and healthBar:IsShown() then
		if event == "UNIT_MAXHEALTH" then
			local max = UnitHealthMax("player")
			healthBar._lastMax = max
			healthBar:SetMinMaxValues(0, max)
		end
		updateHealthBar(event)
	elseif event == "UNIT_POWER_UPDATE" and powerbar[arg1] and powerbar[arg1]:IsShown() and not powerfrequent[arg1] then
		updatePowerBar(arg1)
	elseif event == "UNIT_POWER_FREQUENT" and powerbar[arg1] and powerbar[arg1]:IsShown() and powerfrequent[arg1] then
		updatePowerBar(arg1)
	elseif event == "UNIT_MAXPOWER" and powerbar[arg1] and powerbar[arg1]:IsShown() then
		local enum = POWER_ENUM[arg1]
		local bar = powerbar[arg1]
		if enum and bar then
			local max = UnitPowerMax("player", enum)
			bar._lastMax = max
			bar:SetMinMaxValues(0, max)
		end
		updatePowerBar(arg1)
		if ResourceBars.separatorEligible[arg1] then updateBarSeparators(arg1) end
	elseif event == "RUNE_POWER_UPDATE" then
		-- payload: runeIndex, isEnergize -> first vararg is held in 'unit' here
		if powerbar["RUNES"] and powerbar["RUNES"]:IsShown() then updatePowerBar("RUNES", unit) end
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

-- Force a recolor of rune segments (used on spec change)
function ResourceBars.ForceRuneRecolor()
	local rb = powerbar and powerbar.RUNES
	if not rb or not rb.runes then return end
	local spec = addon.variables.unitSpec
	rb._dkColor = DK_SPEC_COLOR[spec] or DK_SPEC_COLOR[1]
	for i = 1, 6 do
		local sb = rb.runes[i]
		if sb then
			sb._isReady = nil
			sb._lastRemain = nil
		end
	end
end

-- Clear all points for current bars to break transient inter-bar dependencies
function ResourceBars.DetachAllBars()
	if healthBar then healthBar:ClearAllPoints() end
	for _, bar in pairs(powerbar) do
		if bar then bar:ClearAllPoints() end
	end
end

local function getFrameName(pType)
	if pType == "HEALTH" then return "EQOLHealthBar" end
	return "EQOL" .. pType .. "Bar"
end

local function frameNameToBarType(fname)
	if fname == "EQOLHealthBar" then return "HEALTH" end
	if type(fname) ~= "string" then return nil end
	return fname:match("^EQOL(.+)Bar$")
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
	if ResourceBars._reanchoring then return end
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
		-- Apply current texture selection to health bar
		local hCfg2 = getBarSettings("HEALTH") or {}
		local hTex = resolveTexture(hCfg2)
		healthBar:SetStatusBarTexture(hTex)
		if healthBar.absorbBar then healthBar.absorbBar:SetStatusBarTexture(hTex) end
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
			if
				a.autoSpacing
				or (a.autoSpacing == nil and isEQOLFrameName(a.relativeFrame) and (a.point or "TOPLEFT") == "TOPLEFT" and (a.relativePoint or "BOTTOMLEFT") == "BOTTOMLEFT" and (a.x or 0) == 0)
			then
				a.x = 0
				a.y = DEFAULT_STACK_SPACING
				a.autoSpacing = true
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

			local cfg = getBarSettings(pType)
			bar._cfg = cfg
			local defaultStyle = (pType == "MANA") and "PERCENT" or "CURMAX"
			bar._style = (cfg and cfg.textStyle) or defaultStyle

			if pType == "RUNES" then
				layoutRunes(bar)
				updatePowerBar("RUNES")
			else
				updatePowerBar(pType)
			end
			if ResourceBars.separatorEligible[pType] then updateBarSeparators(pType) end
		end
	end
	-- Apply styling updates without forcing a full rebuild
	if healthBar then
		local hCfg = getBarSettings("HEALTH") or {}
		healthBar._cfg = hCfg
		healthBar:SetStatusBarTexture(resolveTexture(hCfg))
		applyBackdrop(healthBar, hCfg)
		if healthBar.text then applyFontToString(healthBar.text, hCfg) end
		applyTextPosition(healthBar, hCfg, 3, 0)
		configureBarBehavior(healthBar, hCfg, "HEALTH")
		if healthBar.absorbBar then
			healthBar.absorbBar:SetStatusBarTexture(resolveTexture(hCfg))
			if hCfg.verticalFill then
				healthBar.absorbBar:SetOrientation("VERTICAL")
			else
				healthBar.absorbBar:SetOrientation("HORIZONTAL")
			end
			if healthBar.absorbBar.SetReverseFill then healthBar.absorbBar:SetReverseFill(hCfg.reverseFill == true) end
		end
	end

	for pType, bar in pairs(powerbar) do
		if bar then
			local cfg = getBarSettings(pType) or {}
			bar._cfg = cfg
			if pType == "RUNES" then
				bar:SetStatusBarTexture(resolveTexture(cfg))
				local tex = bar:GetStatusBarTexture()
				if tex then tex:SetAlpha(0) end
			else
				bar:SetStatusBarTexture(resolveTexture(cfg))
			end
			applyBackdrop(bar, cfg)
			configureBarBehavior(bar, cfg, pType)
			if pType ~= "RUNES" then applyBarFillColor(bar, cfg, pType) end
			if pType ~= "RUNES" and bar.text then
				applyFontToString(bar.text, cfg)
				applyTextPosition(bar, cfg, 3, 0)
			end
			if pType == "RUNES" then layoutRunes(bar) end
		end
	end
	updateHealthBar("UNIT_ABSORB_AMOUNT_CHANGED")
	if addon and addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.UpdateRuneEventRegistration then addon.Aura.ResourceBars.UpdateRuneEventRegistration() end
	-- Ensure RUNES animation stops when not visible/enabled
	local rcfg = getBarSettings("RUNES")
	local runesEnabled = rcfg and (rcfg.enabled == true)
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
	if ResourceBars._reanchoring then return end
	ResourceBars._reanchoring = true
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

	-- Then power bars: anchor in a safe order (parents first), break cycles if detected
	local spec = addon.variables.unitSpec
	local types = {}
	for pType, bar in pairs(powerbar) do
		if bar then tinsert(types, pType) end
	end

	-- Build a graph of bar -> bar it anchors to (only EQOL bars)
	local edges = {}
	local anchors = {}
	for _, pType in ipairs(types) do
		local a = getAnchor(pType, spec)
		anchors[pType] = a
		local relType = frameNameToBarType(a and a.relativeFrame)
		if relType and powerbar[relType] then
			edges[pType] = relType
		else
			edges[pType] = nil
		end
	end

	-- DFS for ordering; break cycles by forcing current node to UIParent
	local order, visiting, visited = {}, {}, {}
	local function ensureUIParentDefaults(a, bar)
		a.point = a.point or "TOPLEFT"
		a.relativeFrame = "UIParent"
		a.relativePoint = a.relativePoint or "TOPLEFT"
		if a.x == nil or a.y == nil then
			local pw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
			local ph = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
			local w = (bar and bar.GetWidth and bar:GetWidth()) or DEFAULT_POWER_WIDTH
			local h = (bar and bar.GetHeight and bar:GetHeight()) or DEFAULT_POWER_HEIGHT
			a.x = (pw - w) / 2
			a.y = (h - ph) / 2
		end
	end

	-- Pre-detach all bars to UIParent to avoid transient cycles during reanchor
	for _, pType in ipairs(types) do
		local bar = powerbar[pType]
		local a = anchors[pType]
		if bar and a then
			if (a.relativeFrame or "UIParent") == "UIParent" then ensureUIParentDefaults(a, bar) end
			bar:ClearAllPoints()
			bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", a.x or 0, a.y or 0)
		end
	end

	local function dfs(node)
		if visited[node] then return end
		if visiting[node] then
			-- Cycle detected: break by reanchoring this node to UIParent
			local a = anchors[node]
			ensureUIParentDefaults(a, powerbar[node])
			edges[node] = nil
			visiting[node] = nil
			visited[node] = true
			tinsert(order, node)
			return
		end
		visiting[node] = true
		local to = edges[node]
		if to then dfs(to) end
		visiting[node] = nil
		visited[node] = true
		tinsert(order, node)
	end

	for _, pType in ipairs(types) do
		dfs(pType)
	end

	-- Apply anchors in computed order
	for _, pType in ipairs(order) do
		local bar = powerbar[pType]
		if bar then
			local a = anchors[pType]
			if (a.relativeFrame or "UIParent") == "UIParent" then ensureUIParentDefaults(a, bar) end
			if
				a.autoSpacing
				or (a.autoSpacing == nil and isEQOLFrameName(a.relativeFrame) and (a.point or "TOPLEFT") == "TOPLEFT" and (a.relativePoint or "BOTTOMLEFT") == "BOTTOMLEFT" and (a.x or 0) == 0)
			then
				a.x = 0
				a.y = DEFAULT_STACK_SPACING
				a.autoSpacing = true
			end
			local rel, looped = resolveAnchor(a, pType)
			if looped and (a.relativeFrame or "UIParent") ~= "UIParent" then
				ensureUIParentDefaults(a, bar)
				rel = UIParent
			end
			bar:ClearAllPoints()
			bar:SetPoint(a.point or "TOPLEFT", rel, a.relativePoint or a.point or "TOPLEFT", a.x or 0, a.y or 0)
			local isUI = (a.relativeFrame or "UIParent") == "UIParent"
			bar:SetMovable(isUI)
			bar:EnableMouse(isUI)
		end
	end

	updateHealthBar("UNIT_ABSORB_AMOUNT_CHANGED")
	ResourceBars._reanchoring = false
end

return ResourceBars
