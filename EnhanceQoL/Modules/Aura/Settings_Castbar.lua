local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Aura = addon.Aura or {}
addon.Aura.SettingsCastbar = addon.Aura.SettingsCastbar or {}
local CastbarSettings = addon.Aura.SettingsCastbar

function CastbarSettings.BuildStandaloneCastbarSettings(ctx)
	ctx = type(ctx) == "table" and ctx or {}
	local L = ctx.L or LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")
	local settingType = ctx.settingType
	local getCastbarModule = ctx.getCastbarModule
	local toRGBA = ctx.toRGBA
	local refreshSettingsUI = ctx.refreshSettingsUI
	local textureOptions = ctx.textureOptions
	local borderOptions = ctx.borderOptions
	local fontOptions = ctx.fontOptions
	local outlineOptions = ctx.outlineOptions
	local strataOptionsWithDefault = ctx.strataOptionsWithDefault
	local OFFSET_RANGE = tonumber(ctx.OFFSET_RANGE) or 3000
	local checkbox = ctx.checkbox
	local slider = ctx.slider
	local radioDropdown = ctx.radioDropdown
	local checkboxDropdown = ctx.checkboxDropdown
	local checkboxColor = ctx.checkboxColor

	if not (settingType and getCastbarModule and toRGBA and refreshSettingsUI and textureOptions and borderOptions and fontOptions and outlineOptions and strataOptionsWithDefault) then return {} end
	if not (checkbox and slider and radioDropdown and checkboxDropdown and checkboxColor) then return {} end

	addon.db = addon.db or {}
	local castCfg, castDef
	local CastbarModule = getCastbarModule()
	if CastbarModule and CastbarModule.GetConfig then
		castCfg, castDef = CastbarModule.GetConfig()
	end
	if type(castCfg) ~= "table" then
		addon.db.castbar = type(addon.db.castbar) == "table" and addon.db.castbar or {}
		castCfg = addon.db.castbar
	end
	if type(castDef) ~= "table" then
		if CastbarModule and CastbarModule.GetDefaults then
			castDef = CastbarModule.GetDefaults()
		else
			castDef = {}
		end
	end

	local function getCast(path, fallback)
		local cur = castCfg
		for i = 2, #path do
			if not cur then return fallback end
			cur = cur[path[i]]
			if cur == nil then return fallback end
		end
		return cur
	end

	local function setCast(path, value)
		local cur = castCfg
		for i = 2, #path - 1 do
			local key = path[i]
			if type(cur[key]) ~= "table" then cur[key] = {} end
			cur = cur[key]
		end
		cur[path[#path]] = value
	end

	local function setCastColor(path, r, g, b, a)
		local _, _, _, curA = toRGBA(getCast(path))
		setCast(path, { r or 1, g or 1, b or 1, a or curA or 1 })
	end

	local function refreshCastbar()
		local mod = getCastbarModule()
		if mod and mod.Refresh then mod.Refresh() end
	end

	local list = {}
	local textureOpts = textureOptions
	local section = {
		layout = "castLayout",
		anchor = "castAnchor",
		icon = "castIcon",
		spellName = "castSpellName",
		duration = "castDuration",
		barAppearance = "castBarAppearance",
		frameAppearance = "castFrameAppearance",
		colors = "castColors",
	}

	local function isCastEnabled() return true end
	local function isCastIconEnabled() return getCast({ "cast", "showIcon" }, castDef.showIcon ~= false) ~= false end
	local function isCastNameEnabled() return getCast({ "cast", "showName" }, castDef.showName ~= false) ~= false end
	local function isCastDurationEnabled() return getCast({ "cast", "showDuration" }, castDef.showDuration ~= false) ~= false end
	local anchorPointOptions = {
		{ value = "TOPLEFT", label = "TOPLEFT" },
		{ value = "TOP", label = "TOP" },
		{ value = "TOPRIGHT", label = "TOPRIGHT" },
		{ value = "LEFT", label = "LEFT" },
		{ value = "CENTER", label = "CENTER" },
		{ value = "RIGHT", label = "RIGHT" },
		{ value = "BOTTOMLEFT", label = "BOTTOMLEFT" },
		{ value = "BOTTOM", label = "BOTTOM" },
		{ value = "BOTTOMRIGHT", label = "BOTTOMRIGHT" },
	}
	local validAnchorPoints = {}
	for _, entry in ipairs(anchorPointOptions) do
		validAnchorPoints[entry.value] = true
	end
	local function normalizeAnchorPoint(value, fallback)
		local point = tostring(value or fallback or "CENTER"):upper()
		if validAnchorPoints[point] then return point end
		return tostring(fallback or "CENTER"):upper()
	end
	local function legacyAnchorToPoint(value)
		local anchor = type(value) == "string" and value:upper() or "BOTTOM"
		if anchor == "TOP" then return "BOTTOM", "CENTER" end
		if anchor == "BOTTOM" then return "TOP", "CENTER" end
		return "CENTER", "CENTER"
	end
	local function ensureCastAnchor()
		local anchor = getCast({ "cast", "anchor" })
		local defAnchor = castDef and castDef.anchor
		local legacyAnchor = (type(anchor) == "string" and anchor) or (type(defAnchor) == "string" and defAnchor) or "BOTTOM"
		local fallbackPoint, fallbackRelativePoint = legacyAnchorToPoint(legacyAnchor)
		local fallbackOffset = getCast({ "cast", "offset" }, castDef.offset or { x = 0, y = -4 })
		local fallbackX = tonumber(fallbackOffset and fallbackOffset.x) or 0
		local fallbackY = tonumber(fallbackOffset and fallbackOffset.y) or 0

		if type(anchor) ~= "table" then
			anchor = {
				point = fallbackPoint,
				relativePoint = fallbackRelativePoint,
				relativeFrame = "UIParent",
				x = fallbackX,
				y = fallbackY,
			}
			setCast({ "cast", "anchor" }, anchor)
		end

		anchor.point = normalizeAnchorPoint(anchor.point, fallbackPoint)
		anchor.relativePoint = normalizeAnchorPoint(anchor.relativePoint, anchor.point)
		anchor.relativeFrame = (type(anchor.relativeFrame) == "string" and anchor.relativeFrame ~= "") and anchor.relativeFrame or "UIParent"
		if anchor.x == nil then
			anchor.x = fallbackX
		else
			anchor.x = tonumber(anchor.x) or fallbackX
		end
		if anchor.y == nil then
			anchor.y = fallbackY
		else
			anchor.y = tonumber(anchor.y) or fallbackY
		end
		if anchor.relativeFrame == "UIParent" then anchor.matchRelativeWidth = nil end
		return anchor
	end
	local function anchorUsesUIParent()
		local anchor = ensureCastAnchor()
		return (anchor.relativeFrame or "UIParent") == "UIParent"
	end
	local function isCastWidthMatchedToAnchor()
		local anchor = ensureCastAnchor()
		return not anchorUsesUIParent() and anchor.matchRelativeWidth == true
	end
	local function relativeFrameEntries()
		local entries = {}
		local seen = {}
		local function add(key, label)
			if not key or key == "" or seen[key] then return end
			seen[key] = true
			entries[#entries + 1] = { value = key, label = label or key }
		end

		add("UIParent", "UIParent")
		add("EssentialCooldownViewer", "Essential Cooldown Viewer")
		add("UtilityCooldownViewer", "Utility Cooldown Viewer")
		add("BuffBarCooldownViewer", "Buff Bar Cooldowns")
		add("BuffIconCooldownViewer", "Buff Icon Cooldowns")
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

		local dataPanel = addon.DataPanel
		if dataPanel and dataPanel.List then
			local ids = {}
			for id in pairs(dataPanel.List() or {}) do
				ids[#ids + 1] = tostring(id)
			end
			table.sort(ids, function(a, b)
				local na, nb = tonumber(a), tonumber(b)
				if na and nb then return na < nb end
				return tostring(a) < tostring(b)
			end)
			for _, id in ipairs(ids) do
				local panel = dataPanel.Get and dataPanel.Get(id)
				local frameName = panel and panel.frame and panel.frame.GetName and panel.frame:GetName() or nil
				if not frameName or frameName == "" then frameName = parentAddonName .. "DataPanel" .. tostring(id) end
				local panelName = panel and panel.name
				local label = (type(panelName) == "string" and panelName ~= "") and ("Data Panel: " .. panelName) or ("Data Panel " .. tostring(id))
				add(frameName, label)
			end
		end

		if _G.EQOLHealthBar then add("EQOLHealthBar", HEALTH or "Health") end
		local resourceBars = addon.Aura and addon.Aura.ResourceBars
		local classPowerTypes = resourceBars and resourceBars.classPowerTypes or {}
		local powerLabels = resourceBars and resourceBars.PowerLabels or {}
		if type(classPowerTypes) == "table" then
			for _, powerType in ipairs(classPowerTypes) do
				local frameName = "EQOL" .. tostring(powerType) .. "Bar"
				if _G[frameName] then
					local label = powerLabels[powerType] or _G["POWER_TYPE_" .. tostring(powerType)] or tostring(powerType):gsub("_", " ")
					add(frameName, tostring(label))
				end
			end
		end

		local anchor = ensureCastAnchor()
		local currentRelative = anchor and anchor.relativeFrame
		if currentRelative and not seen[currentRelative] then add(currentRelative, currentRelative) end
		return entries
	end
	local function validateRelativeFrame(anchor)
		local target = anchor and anchor.relativeFrame or "UIParent"
		local entries = relativeFrameEntries()
		for _, entry in ipairs(entries) do
			if entry.value == target then return target end
		end
		if anchor then
			anchor.relativeFrame = "UIParent"
			anchor.matchRelativeWidth = nil
		end
		return "UIParent"
	end

	list[#list + 1] = { name = L["Layout"] or "Layout", kind = settingType.Collapsible, id = section.layout, defaultCollapsed = false }

	local castWidth = slider(L["UFWidth"] or "Frame width", 50, 800, 1, function() return getCast({ "cast", "width" }, castDef.width or 220) end, function(val)
		setCast({ "cast", "width" }, math.max(50, val or 50))
		refreshCastbar()
	end, castDef.width or 220, section.layout, true)
	castWidth.isEnabled = function() return isCastEnabled() and not isCastWidthMatchedToAnchor() end
	list[#list + 1] = castWidth

	local castHeight = slider(L["Cast bar height"] or "Cast bar height", 6, 40, 1, function() return getCast({ "cast", "height" }, castDef.height or 16) end, function(val)
		setCast({ "cast", "height" }, val or castDef.height or 16)
		refreshCastbar()
	end, castDef.height or 16, section.layout, true)
	castHeight.isEnabled = isCastEnabled
	list[#list + 1] = castHeight

	local castStrata = radioDropdown(L["UFCastStrata"] or "Castbar strata", strataOptionsWithDefault, function() return getCast({ "cast", "strata" }, castDef.strata or "") end, function(val)
		setCast({ "cast", "strata" }, (val and val ~= "") and val or nil)
		refreshCastbar()
	end, castDef.strata or "", section.layout)
	castStrata.isEnabled = isCastEnabled
	list[#list + 1] = castStrata

	local castFrameLevelOffset = slider(L["UFCastFrameLevelOffset"] or "Castbar frame level offset", -20, 50, 1, function()
		local fallback = castDef.frameLevelOffset
		if fallback == nil then fallback = 1 end
		return getCast({ "cast", "frameLevelOffset" }, fallback)
	end, function(val)
		setCast({ "cast", "frameLevelOffset" }, val)
		refreshCastbar()
	end, (castDef.frameLevelOffset == nil) and 1 or castDef.frameLevelOffset, section.layout, true)
	castFrameLevelOffset.isEnabled = isCastEnabled
	list[#list + 1] = castFrameLevelOffset

	list[#list + 1] = { name = L["Anchor"] or "Anchor", kind = settingType.Collapsible, id = section.anchor, defaultCollapsed = true }

	local castRelativeFrame = radioDropdown("Relative frame", relativeFrameEntries, function()
		local anchor = ensureCastAnchor()
		return validateRelativeFrame(anchor)
	end, function(value)
		local anchor = ensureCastAnchor()
		local target = value or "UIParent"
		local validTarget = false
		for _, entry in ipairs(relativeFrameEntries()) do
			if entry.value == target then
				validTarget = true
				break
			end
		end
		if not validTarget then target = "UIParent" end
		anchor.relativeFrame = target
		if target == "UIParent" then
			anchor.point = normalizeAnchorPoint(anchor.point, "CENTER")
			anchor.relativePoint = normalizeAnchorPoint(anchor.relativePoint, anchor.point)
			anchor.matchRelativeWidth = nil
		else
			anchor.point = normalizeAnchorPoint(anchor.point, "TOPLEFT")
			anchor.relativePoint = normalizeAnchorPoint(anchor.relativePoint, "BOTTOMLEFT")
		end
		refreshCastbar()
		refreshSettingsUI()
	end, "UIParent", section.anchor)
	castRelativeFrame.isEnabled = isCastEnabled
	list[#list + 1] = castRelativeFrame

	local castAnchorPoint = radioDropdown("Anchor point", anchorPointOptions, function()
		local anchor = ensureCastAnchor()
		return anchor.point or "CENTER"
	end, function(value)
		local anchor = ensureCastAnchor()
		anchor.point = normalizeAnchorPoint(value, anchor.point or "CENTER")
		refreshCastbar()
	end, "CENTER", section.anchor)
	castAnchorPoint.isEnabled = isCastEnabled
	list[#list + 1] = castAnchorPoint

	local castAnchorRelativePoint = radioDropdown("Anchor target point", anchorPointOptions, function()
		local anchor = ensureCastAnchor()
		return anchor.relativePoint or anchor.point or "CENTER"
	end, function(value)
		local anchor = ensureCastAnchor()
		anchor.relativePoint = normalizeAnchorPoint(value, anchor.point or "CENTER")
		refreshCastbar()
	end, "CENTER", section.anchor)
	castAnchorRelativePoint.isEnabled = isCastEnabled
	list[#list + 1] = castAnchorRelativePoint

	local castOffsetX = slider(L["Offset X"] or "Offset X", -OFFSET_RANGE, OFFSET_RANGE, 1, function()
		local anchor = ensureCastAnchor()
		return anchor.x or 0
	end, function(val)
		local anchor = ensureCastAnchor()
		anchor.x = tonumber(val) or 0
		refreshCastbar()
	end, 0, section.anchor, true)
	castOffsetX.isEnabled = isCastEnabled
	list[#list + 1] = castOffsetX

	local castOffsetY = slider(L["Offset Y"] or "Offset Y", -OFFSET_RANGE, OFFSET_RANGE, 1, function()
		local anchor = ensureCastAnchor()
		return anchor.y or 0
	end, function(val)
		local anchor = ensureCastAnchor()
		anchor.y = tonumber(val) or 0
		refreshCastbar()
	end, 0, section.anchor, true)
	castOffsetY.isEnabled = isCastEnabled
	list[#list + 1] = castOffsetY

	list[#list + 1] = checkbox("Match width of anchor", function()
		local anchor = ensureCastAnchor()
		return (anchor.relativeFrame or "UIParent") ~= "UIParent" and anchor.matchRelativeWidth == true
	end, function(val)
		local anchor = ensureCastAnchor()
		if (anchor.relativeFrame or "UIParent") == "UIParent" then
			anchor.matchRelativeWidth = nil
		else
			anchor.matchRelativeWidth = val and true or nil
		end
		refreshCastbar()
		refreshSettingsUI()
	end, false, section.anchor, function() return isCastEnabled() and not anchorUsesUIParent() end)

	list[#list + 1] = { name = L["Icon"] or "Icon", kind = settingType.Collapsible, id = section.icon, defaultCollapsed = true }

	list[#list + 1] = checkbox(L["Show spell icon"] or "Show spell icon", function() return getCast({ "cast", "showIcon" }, castDef.showIcon ~= false) ~= false end, function(val)
		setCast({ "cast", "showIcon" }, val and true or false)
		refreshCastbar()
		refreshSettingsUI()
	end, castDef.showIcon ~= false, section.icon, isCastEnabled)

	local castIconSize = slider(L["Icon size"] or "Icon size", 8, 64, 1, function() return getCast({ "cast", "iconSize" }, castDef.iconSize or 22) end, function(val)
		setCast({ "cast", "iconSize" }, val or castDef.iconSize or 22)
		refreshCastbar()
	end, castDef.iconSize or 22, section.icon, true)
	castIconSize.isEnabled = isCastIconEnabled
	list[#list + 1] = castIconSize

	local castIconOffsetX = slider(
		L["Icon X Offset"] or "Icon X Offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return getCast({ "cast", "iconOffset", "x" }, (castDef.iconOffset and castDef.iconOffset.x) or -4) end,
		function(val)
			setCast({ "cast", "iconOffset", "x" }, val or -4)
			refreshCastbar()
		end,
		(castDef.iconOffset and castDef.iconOffset.x) or -4,
		section.icon,
		true
	)
	castIconOffsetX.isEnabled = isCastIconEnabled
	list[#list + 1] = castIconOffsetX

	list[#list + 1] = { name = L["Spell name"] or "Spell Name", kind = settingType.Collapsible, id = section.spellName, defaultCollapsed = true }

	list[#list + 1] = checkbox(L["Show spell name"] or "Show spell name", function() return getCast({ "cast", "showName" }, castDef.showName ~= false) ~= false end, function(val)
		setCast({ "cast", "showName" }, val and true or false)
		refreshCastbar()
		refreshSettingsUI()
	end, castDef.showName ~= false, section.spellName, isCastEnabled)

	list[#list + 1] = checkbox(L["Show cast target"] or "Show cast target", function() return getCast({ "cast", "showCastTarget" }, castDef.showCastTarget == true) == true end, function(val)
		setCast({ "cast", "showCastTarget" }, val and true or false)
		refreshCastbar()
		refreshSettingsUI()
	end, castDef.showCastTarget == true, section.spellName, isCastNameEnabled)

	local castNameX = slider(
		L["Name X Offset"] or "Name X Offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return getCast({ "cast", "nameOffset", "x" }, (castDef.nameOffset and castDef.nameOffset.x) or 6) end,
		function(val)
			setCast({ "cast", "nameOffset", "x" }, val or 0)
			refreshCastbar()
		end,
		(castDef.nameOffset and castDef.nameOffset.x) or 6,
		section.spellName,
		true
	)
	castNameX.isEnabled = isCastNameEnabled
	list[#list + 1] = castNameX

	local castNameY = slider(
		L["Name Y Offset"] or "Name Y Offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return getCast({ "cast", "nameOffset", "y" }, (castDef.nameOffset and castDef.nameOffset.y) or 0) end,
		function(val)
			setCast({ "cast", "nameOffset", "y" }, val or 0)
			refreshCastbar()
		end,
		(castDef.nameOffset and castDef.nameOffset.y) or 0,
		section.spellName,
		true
	)
	castNameY.isEnabled = isCastNameEnabled
	list[#list + 1] = castNameY

	local function getCastFont() return getCast({ "cast", "font" }, castDef.font or "") end
	local castNameFont = {
		name = L["Font"] or "Font",
		kind = settingType.DropdownColor,
		height = 180,
		parentId = section.spellName,
		default = castDef.font or "",
		generator = function(_, root)
			local opts = fontOptions()
			if type(opts) ~= "table" then return end
			for _, opt in ipairs(opts) do
				local value = opt.value
				local label = opt.label
				root:CreateCheckbox(label, function() return getCastFont() == value end, function()
					if getCastFont() ~= value then
						setCast({ "cast", "font" }, value)
						refreshCastbar()
					end
				end)
			end
		end,
		colorDefault = { r = 1, g = 1, b = 1, a = 1 },
		colorGet = function()
			local fallback = castDef.fontColor or { 1, 1, 1, 1 }
			local r, g, b, a = toRGBA(getCast({ "cast", "fontColor" }, castDef.fontColor), fallback)
			return { r = r, g = g, b = b, a = a }
		end,
		colorSet = function(_, color)
			setCastColor({ "cast", "fontColor" }, color.r, color.g, color.b, color.a)
			refreshCastbar()
		end,
		hasOpacity = true,
	}
	castNameFont.isEnabled = isCastNameEnabled
	list[#list + 1] = castNameFont

	local castNameFontOutline = checkboxDropdown(
		L["Font outline"] or "Font outline",
		outlineOptions,
		function() return getCast({ "cast", "fontOutline" }, castDef.fontOutline or "OUTLINE") end,
		function(val)
			setCast({ "cast", "fontOutline" }, val)
			refreshCastbar()
		end,
		castDef.fontOutline or "OUTLINE",
		section.spellName
	)
	castNameFontOutline.isEnabled = isCastNameEnabled
	list[#list + 1] = castNameFontOutline

	local castNameFontSize = slider(L["FontSize"] or "Font size", 8, 30, 1, function() return getCast({ "cast", "fontSize" }, castDef.fontSize or 12) end, function(val)
		setCast({ "cast", "fontSize" }, val or 12)
		refreshCastbar()
	end, castDef.fontSize or 12, section.spellName, true)
	castNameFontSize.isEnabled = isCastNameEnabled
	list[#list + 1] = castNameFontSize

	local castNameMaxCharsSetting = slider(
		L["UFCastNameMaxChars"] or "Cast name max width",
		0,
		100,
		1,
		function() return getCast({ "cast", "nameMaxChars" }, castDef.nameMaxChars or 0) end,
		function(val)
			setCast({ "cast", "nameMaxChars" }, val or 0)
			refreshCastbar()
		end,
		castDef.nameMaxChars or 0,
		section.spellName,
		true
	)
	castNameMaxCharsSetting.isEnabled = isCastNameEnabled
	list[#list + 1] = castNameMaxCharsSetting

	list[#list + 1] = { name = L["Duration"] or "Duration", kind = settingType.Collapsible, id = section.duration, defaultCollapsed = true }

	list[#list + 1] = checkbox(L["Show cast duration"] or "Show cast duration", function() return getCast({ "cast", "showDuration" }, castDef.showDuration ~= false) ~= false end, function(val)
		setCast({ "cast", "showDuration" }, val and true or false)
		refreshCastbar()
		refreshSettingsUI()
	end, castDef.showDuration ~= false, section.duration, isCastEnabled)

	local castDurationFormatOptions = {
		{ value = "REMAINING", label = L["UFCastDurationRemaining"] or "Remaining" },
		{ value = "REMAINING_TOTAL", label = L["UFCastDurationRemainingTotal"] or "Remaining/Total" },
		{ value = "ELAPSED_TOTAL", label = L["UFCastDurationElapsedTotal"] or "Elapsed/Total" },
	}
	local castDurationFormat = checkboxDropdown(
		L["UFCastDurationFormat"] or "Cast duration format",
		castDurationFormatOptions,
		function() return getCast({ "cast", "durationFormat" }, castDef.durationFormat or "REMAINING") end,
		function(val)
			setCast({ "cast", "durationFormat" }, val or "REMAINING")
			refreshCastbar()
		end,
		castDef.durationFormat or "REMAINING",
		section.duration
	)
	castDurationFormat.isEnabled = isCastDurationEnabled
	list[#list + 1] = castDurationFormat

	local castDurX = slider(
		L["Duration X Offset"] or "Duration X Offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return getCast({ "cast", "durationOffset", "x" }, (castDef.durationOffset and castDef.durationOffset.x) or -6) end,
		function(val)
			setCast({ "cast", "durationOffset", "x" }, val or 0)
			refreshCastbar()
		end,
		(castDef.durationOffset and castDef.durationOffset.x) or -6,
		section.duration,
		true
	)
	castDurX.isEnabled = isCastDurationEnabled
	list[#list + 1] = castDurX

	local castDurY = slider(
		L["Duration Y Offset"] or "Duration Y Offset",
		-OFFSET_RANGE,
		OFFSET_RANGE,
		1,
		function() return getCast({ "cast", "durationOffset", "y" }, (castDef.durationOffset and castDef.durationOffset.y) or 0) end,
		function(val)
			setCast({ "cast", "durationOffset", "y" }, val or 0)
			refreshCastbar()
		end,
		(castDef.durationOffset and castDef.durationOffset.y) or 0,
		section.duration,
		true
	)
	castDurY.isEnabled = isCastDurationEnabled
	list[#list + 1] = castDurY

	list[#list + 1] = { name = L["Bar style"] or "Bar Style", kind = settingType.Collapsible, id = section.barAppearance, defaultCollapsed = true }

	local castTexture = checkboxDropdown(L["Cast texture"] or "Cast texture", textureOpts, function() return getCast({ "cast", "texture" }, castDef.texture or "DEFAULT") end, function(val)
		setCast({ "cast", "texture" }, val)
		refreshCastbar()
	end, castDef.texture or "DEFAULT", section.barAppearance)
	castTexture.isEnabled = isCastEnabled
	list[#list + 1] = castTexture

	list[#list + 1] = { name = L["Border & backdrop"] or "Border & Backdrop", kind = settingType.Collapsible, id = section.frameAppearance, defaultCollapsed = true }

	local castBackdrop = checkboxColor({
		name = L["UFBarBackdrop"] or "Show bar backdrop",
		parentId = section.frameAppearance,
		defaultChecked = (castDef.backdrop and castDef.backdrop.enabled) ~= false,
		isChecked = function() return getCast({ "cast", "backdrop", "enabled" }, (castDef.backdrop and castDef.backdrop.enabled) ~= false) ~= false end,
		onChecked = function(val)
			setCast({ "cast", "backdrop", "enabled" }, val and true or false)
			refreshCastbar()
			refreshSettingsUI()
		end,
		getColor = function() return toRGBA(getCast({ "cast", "backdrop", "color" }, castDef.backdrop and castDef.backdrop.color), castDef.backdrop and castDef.backdrop.color or { 0, 0, 0, 0.6 }) end,
		onColor = function(color)
			setCastColor({ "cast", "backdrop", "color" }, color.r, color.g, color.b, color.a)
			refreshCastbar()
		end,
		colorDefault = { r = 0, g = 0, b = 0, a = 0.6 },
		isEnabled = isCastEnabled,
	})
	castBackdrop.isEnabled = isCastEnabled
	list[#list + 1] = castBackdrop

	local function isCastBorderEnabled() return getCast({ "cast", "border", "enabled" }, (castDef.border and castDef.border.enabled) == true) == true end
	list[#list + 1] = checkboxColor({
		name = L["Cast bar border"] or "Cast bar border",
		parentId = section.frameAppearance,
		defaultChecked = (castDef.border and castDef.border.enabled) == true,
		isChecked = function() return isCastBorderEnabled() end,
		onChecked = function(val)
			setCast({ "cast", "border", "enabled" }, val and true or false)
			if val and not getCast({ "cast", "border", "color" }) then setCast({ "cast", "border", "color" }, (castDef.border and castDef.border.color) or { 0, 0, 0, 0.8 }) end
			refreshCastbar()
			refreshSettingsUI()
		end,
		getColor = function()
			local fallback = (castDef.border and castDef.border.color) or { 0, 0, 0, 0.8 }
			return toRGBA(getCast({ "cast", "border", "color" }, castDef.border and castDef.border.color), fallback)
		end,
		onColor = function(color)
			setCastColor({ "cast", "border", "color" }, color.r, color.g, color.b, color.a)
			setCast({ "cast", "border", "enabled" }, true)
			refreshCastbar()
		end,
		colorDefault = {
			r = (castDef.border and castDef.border.color and castDef.border.color[1]) or 0,
			g = (castDef.border and castDef.border.color and castDef.border.color[2]) or 0,
			b = (castDef.border and castDef.border.color and castDef.border.color[3]) or 0,
			a = (castDef.border and castDef.border.color and castDef.border.color[4]) or 0.8,
		},
		isEnabled = isCastEnabled,
	})

	local castBorderTexture = checkboxDropdown(
		L["Border texture"] or "Border texture",
		borderOptions,
		function() return getCast({ "cast", "border", "texture" }, (castDef.border and castDef.border.texture) or "DEFAULT") end,
		function(val)
			setCast({ "cast", "border", "texture" }, val or "DEFAULT")
			refreshCastbar()
		end,
		(castDef.border and castDef.border.texture) or "DEFAULT",
		section.frameAppearance
	)
	castBorderTexture.isEnabled = isCastBorderEnabled
	list[#list + 1] = castBorderTexture

	local castBorderSize = slider(L["Border size"] or "Border size", 1, 64, 1, function()
		local border = getCast({ "cast", "border" }, castDef.border or {})
		return border.edgeSize or 1
	end, function(val)
		local border = getCast({ "cast", "border" }, castDef.border or {})
		border.edgeSize = val or 1
		setCast({ "cast", "border" }, border)
		refreshCastbar()
	end, (castDef.border and castDef.border.edgeSize) or 1, section.frameAppearance, true)
	castBorderSize.isEnabled = isCastBorderEnabled
	list[#list + 1] = castBorderSize

	local castBorderOffset = slider(L["Border offset"] or "Border offset", 0, 64, 1, function()
		local border = getCast({ "cast", "border" }, castDef.border or {})
		if border.offset == nil then return border.edgeSize or 1 end
		return border.offset
	end, function(val)
		local border = getCast({ "cast", "border" }, castDef.border or {})
		border.offset = val or 0
		setCast({ "cast", "border" }, border)
		refreshCastbar()
	end, (castDef.border and castDef.border.offset) or (castDef.border and castDef.border.edgeSize) or 1, section.frameAppearance, true)
	castBorderOffset.isEnabled = isCastBorderEnabled
	list[#list + 1] = castBorderOffset

	list[#list + 1] = { name = L["Colors"] or "Colors", kind = settingType.Collapsible, id = section.colors, defaultCollapsed = true }

	local function isCastColorEnabled() return isCastEnabled() and getCast({ "cast", "useClassColor" }, castDef.useClassColor == true) ~= true end
	list[#list + 1] = {
		name = L["Cast color"] or "Cast color",
		kind = settingType.Color,
		parentId = section.colors,
		isEnabled = isCastColorEnabled,
		get = function() return getCast({ "cast", "color" }, castDef.color or { 0.9, 0.7, 0.2, 1 }) end,
		set = function(_, color)
			setCastColor({ "cast", "color" }, color.r, color.g, color.b, color.a)
			refreshCastbar()
		end,
		colorGet = function() return getCast({ "cast", "color" }, castDef.color or { 0.9, 0.7, 0.2, 1 }) end,
		colorSet = function(_, color)
			setCastColor({ "cast", "color" }, color.r, color.g, color.b, color.a)
			refreshCastbar()
		end,
		colorDefault = {
			r = (castDef.color and castDef.color[1]) or 0.9,
			g = (castDef.color and castDef.color[2]) or 0.7,
			b = (castDef.color and castDef.color[3]) or 0.2,
			a = (castDef.color and castDef.color[4]) or 1,
		},
		hasOpacity = true,
	}

	list[#list + 1] = checkbox(L["Use class color"] or "Use class color", function() return getCast({ "cast", "useClassColor" }, castDef.useClassColor == true) == true end, function(val)
		setCast({ "cast", "useClassColor" }, val and true or false)
		refreshCastbar()
		refreshSettingsUI()
	end, castDef.useClassColor == true, section.colors, isCastEnabled)

	local function isCastGradientEnabled() return getCast({ "cast", "useGradient" }, castDef.useGradient == true) == true end
	list[#list + 1] = checkbox(L["Use gradient"] or "Use gradient", isCastGradientEnabled, function(val)
		setCast({ "cast", "useGradient" }, val and true or false)
		refreshCastbar()
		refreshSettingsUI()
	end, castDef.useGradient == true, section.colors, isCastEnabled)

	local castGradientModeOptions = {
		{ value = "CASTBAR", label = L["Gradient with castbar"] or "Gradient with castbar" },
		{ value = "BAR_END", label = L["Gradient at end of bar"] or "Gradient at end of bar" },
	}
	local castGradientMode = checkboxDropdown(
		L["Gradient mode"] or "Gradient mode",
		castGradientModeOptions,
		function() return getCast({ "cast", "gradientMode" }, castDef.gradientMode or "CASTBAR") end,
		function(val)
			setCast({ "cast", "gradientMode" }, val or "CASTBAR")
			refreshCastbar()
		end,
		castDef.gradientMode or "CASTBAR",
		section.colors
	)
	castGradientMode.isEnabled = function() return isCastEnabled() and isCastGradientEnabled() end
	list[#list + 1] = castGradientMode

	list[#list + 1] = {
		name = L["Gradient start color"] or "Gradient start color",
		kind = settingType.Color,
		parentId = section.colors,
		isEnabled = function() return isCastEnabled() and isCastGradientEnabled() end,
		get = function() return getCast({ "cast", "gradientStartColor" }, castDef.gradientStartColor or { 1, 1, 1, 1 }) end,
		set = function(_, color)
			setCastColor({ "cast", "gradientStartColor" }, color.r, color.g, color.b, color.a)
			refreshCastbar()
		end,
		colorGet = function() return getCast({ "cast", "gradientStartColor" }, castDef.gradientStartColor or { 1, 1, 1, 1 }) end,
		colorSet = function(_, color)
			setCastColor({ "cast", "gradientStartColor" }, color.r, color.g, color.b, color.a)
			refreshCastbar()
		end,
		colorDefault = {
			r = (castDef.gradientStartColor and castDef.gradientStartColor[1]) or 1,
			g = (castDef.gradientStartColor and castDef.gradientStartColor[2]) or 1,
			b = (castDef.gradientStartColor and castDef.gradientStartColor[3]) or 1,
			a = (castDef.gradientStartColor and castDef.gradientStartColor[4]) or 1,
		},
		hasOpacity = true,
	}

	list[#list + 1] = {
		name = L["Gradient end color"] or "Gradient end color",
		kind = settingType.Color,
		parentId = section.colors,
		isEnabled = function() return isCastEnabled() and isCastGradientEnabled() end,
		get = function() return getCast({ "cast", "gradientEndColor" }, castDef.gradientEndColor or { 1, 1, 1, 1 }) end,
		set = function(_, color)
			setCastColor({ "cast", "gradientEndColor" }, color.r, color.g, color.b, color.a)
			refreshCastbar()
		end,
		colorGet = function() return getCast({ "cast", "gradientEndColor" }, castDef.gradientEndColor or { 1, 1, 1, 1 }) end,
		colorSet = function(_, color)
			setCastColor({ "cast", "gradientEndColor" }, color.r, color.g, color.b, color.a)
			refreshCastbar()
		end,
		colorDefault = {
			r = (castDef.gradientEndColor and castDef.gradientEndColor[1]) or 1,
			g = (castDef.gradientEndColor and castDef.gradientEndColor[2]) or 1,
			b = (castDef.gradientEndColor and castDef.gradientEndColor[3]) or 1,
			a = (castDef.gradientEndColor and castDef.gradientEndColor[4]) or 1,
		},
		hasOpacity = true,
	}

	list[#list + 1] = { name = "", kind = settingType.Divider, parentId = section.colors }

	list[#list + 1] = {
		name = L["Not interruptible color"] or "Not interruptible color",
		kind = settingType.Color,
		parentId = section.colors,
		isEnabled = isCastEnabled,
		get = function() return getCast({ "cast", "notInterruptibleColor" }, castDef.notInterruptibleColor or { 204 / 255, 204 / 255, 204 / 255, 1 }) end,
		set = function(_, color)
			setCastColor({ "cast", "notInterruptibleColor" }, color.r, color.g, color.b, color.a)
			refreshCastbar()
		end,
		colorGet = function() return getCast({ "cast", "notInterruptibleColor" }, castDef.notInterruptibleColor or { 204 / 255, 204 / 255, 204 / 255, 1 }) end,
		colorSet = function(_, color)
			setCastColor({ "cast", "notInterruptibleColor" }, color.r, color.g, color.b, color.a)
			refreshCastbar()
		end,
		colorDefault = {
			r = (castDef.notInterruptibleColor and castDef.notInterruptibleColor[1]) or (204 / 255),
			g = (castDef.notInterruptibleColor and castDef.notInterruptibleColor[2]) or (204 / 255),
			b = (castDef.notInterruptibleColor and castDef.notInterruptibleColor[3]) or (204 / 255),
			a = (castDef.notInterruptibleColor and castDef.notInterruptibleColor[4]) or 1,
		},
		hasOpacity = true,
	}

	list[#list + 1] = checkbox(
		L["Show interrupt feedback"] or "Show interrupt feedback",
		function() return getCast({ "cast", "showInterruptFeedback" }, castDef.showInterruptFeedback ~= false) ~= false end,
		function(val)
			setCast({ "cast", "showInterruptFeedback" }, val and true or false)
			refreshCastbar()
		end,
		castDef.showInterruptFeedback ~= false,
		section.colors,
		isCastEnabled
	)

	return list
end
