local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Aura = addon.Aura or {}
addon.Aura.CooldownPanels = addon.Aura.CooldownPanels or {}
local CooldownPanels = addon.Aura.CooldownPanels
CooldownPanels.helper = CooldownPanels.helper or {}
local Helper = CooldownPanels.helper
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")
local LSM = LibStub("LibSharedMedia-3.0", true)

Helper.Api = Helper.Api or {}
local Api = Helper.Api

Api.GetItemInfoInstantFn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
Api.GetItemIconByID = C_Item and C_Item.GetItemIconByID
Api.GetItemCooldownFn = (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
Api.GetItemSpell = C_Item and C_Item.GetItemSpell
Api.GetInventoryItemID = GetInventoryItemID
Api.GetInventoryItemCooldown = GetInventoryItemCooldown
Api.GetInventorySlotInfo = GetInventorySlotInfo
Api.GetActionInfo = GetActionInfo
Api.GetCursorInfo = GetCursorInfo
Api.GetCursorPosition = GetCursorPosition
Api.ClearCursor = ClearCursor
Api.DoesSpellExist = C_Spell and C_Spell.DoesSpellExist
Api.GetSpellInfoFn = GetSpellInfo
Api.GetSpellCooldownInfo = C_Spell and C_Spell.GetSpellCooldown or GetSpellCooldown
Api.GetSpellCooldownDuration = C_Spell and C_Spell.GetSpellCooldownDuration
Api.GetSpellChargesInfo = C_Spell and C_Spell.GetSpellCharges
Api.GetBaseSpell = C_Spell and C_Spell.GetBaseSpell
Api.GetOverrideSpell = C_Spell and C_Spell.GetOverrideSpell
Api.GetSpellPowerCost = C_Spell and C_Spell.GetSpellPowerCost
Api.EnableSpellRangeCheck = C_Spell and C_Spell.EnableSpellRangeCheck
Api.IsSpellUsableFn = C_Spell and C_Spell.IsSpellUsable or IsUsableSpell
Api.IsSpellPassiveFn = C_Spell and C_Spell.IsSpellPassive or IsPassiveSpell
Api.IsSpellKnown = C_SpellBook.IsSpellInSpellBook
Api.IsEquippedItem = C_Item.IsEquippedItem
Api.GetTime = GetTime
Api.MenuUtil = MenuUtil
Api.issecretvalue = _G.issecretvalue
Api.DurationModifierRealTime = Enum and Enum.DurationTimeModifier and Enum.DurationTimeModifier.RealTime

function Api.GetItemCount(itemID, includeBank, includeUses, includeReagentBank, includeAccountBank)
	if not itemID then return 0 end
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemID, includeBank, includeUses, includeReagentBank, includeAccountBank) end
	if GetItemCount then return GetItemCount(itemID, includeBank) end
	return 0
end

Helper.DirectionOptions = {
	{ value = "LEFT", label = _G.HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_LEFT or _G.LEFT or "Left" },
	{ value = "RIGHT", label = _G.HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_RIGHT or _G.RIGHT or "Right" },
	{ value = "UP", label = _G.HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_UP or _G.UP or "Up" },
	{ value = "DOWN", label = _G.HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_DOWN or _G.DOWN or "Down" },
}
Helper.LayoutModeOptions = {
	{ value = "GRID", label = L["CooldownPanelLayoutModeGrid"] or "Grid" },
	{ value = "RADIAL", label = L["CooldownPanelLayoutModeRadial"] or "Radial" },
}
Helper.AnchorOptions = {
	{ value = "TOPLEFT", label = L["Top Left"] or "Top Left" },
	{ value = "TOP", label = L["Top"] or "Top" },
	{ value = "TOPRIGHT", label = L["Top Right"] or "Top Right" },
	{ value = "LEFT", label = L["Left"] or "Left" },
	{ value = "CENTER", label = L["Center"] or "Center" },
	{ value = "RIGHT", label = L["Right"] or "Right" },
	{ value = "BOTTOMLEFT", label = L["Bottom Left"] or "Bottom Left" },
	{ value = "BOTTOM", label = L["Bottom"] or "Bottom" },
	{ value = "BOTTOMRIGHT", label = L["Bottom Right"] or "Bottom Right" },
}
Helper.GrowthPointOptions = {
	{ value = "TOPLEFT", label = L["Left"] or "Left" },
	{ value = "TOP", label = L["Center"] or "Center" },
	{ value = "TOPRIGHT", label = L["Right"] or "Right" },
}
Helper.FontStyleOptions = {
	{ value = "NONE", label = L["None"] or "None" },
	{ value = "OUTLINE", label = L["Outline"] or "Outline" },
	{ value = "THICKOUTLINE", label = L["Thick Outline"] or "Thick Outline" },
	{ value = "MONOCHROMEOUTLINE", label = L["Monochrome Outline"] or "Monochrome Outline" },
}

Helper.PANEL_LAYOUT_DEFAULTS = {
	iconSize = 36,
	spacing = 2,
	layoutMode = "GRID",
	direction = "RIGHT",
	wrapCount = 0,
	wrapDirection = "DOWN",
	growthPoint = "TOPLEFT",
	radialRadius = 80,
	radialRotation = 0,
	strata = "MEDIUM",
	rangeOverlayEnabled = false,
	rangeOverlayColor = { 1, 0.1, 0.1, 0.35 },
	checkPower = false,
	powerTintColor = { 0.5, 0.5, 1, 1 },
	unusableTintColor = { 0.6, 0.6, 0.6, 1 },
	opacityOutOfCombat = 1,
	opacityInCombat = 1,
	hideInVehicle = false,
	hideInPetBattle = false,
	hideInClientScene = true,
	hideOnCooldown = false,
	showOnCooldown = false,
	showIconTexture = true,
	stackAnchor = "BOTTOMRIGHT",
	stackX = -1,
	stackY = 1,
	stackFontSize = 12,
	stackFontStyle = "OUTLINE",
	chargesAnchor = "TOP",
	chargesX = 0,
	chargesY = -1,
	chargesFontSize = 12,
	chargesFontStyle = "OUTLINE",
	keybindsEnabled = false,
	keybindsIgnoreItems = false,
	keybindAnchor = "TOPLEFT",
	keybindX = 2,
	keybindY = -2,
	keybindFontSize = 10,
	keybindFontStyle = "OUTLINE",
	cooldownDrawEdge = true,
	cooldownDrawBling = true,
	cooldownDrawSwipe = true,
	cooldownGcdDrawEdge = false,
	cooldownGcdDrawBling = false,
	cooldownGcdDrawSwipe = false,
	showChargesCooldown = false,
	showTooltips = false,
}

Helper.ENTRY_DEFAULTS = {
	alwaysShow = true,
	showCooldown = true,
	showCooldownText = true,
	showCharges = false,
	showStacks = false,
	showItemUses = false,
	showWhenEmpty = false,
	showWhenNoCooldown = false,
	glowReady = false,
	glowDuration = 0,
	soundReady = false,
	soundReadyFile = "None",
	staticText = "",
	staticTextShowOnCooldown = false,
	staticTextFont = "",
	staticTextSize = 12,
	staticTextStyle = "OUTLINE",
	staticTextAnchor = "CENTER",
	staticTextX = 0,
	staticTextY = 0,
}

Helper.DEFAULT_PREVIEW_COUNT = 6
Helper.MAX_PREVIEW_COUNT = 12
Helper.PREVIEW_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
Helper.PREVIEW_ICON_SIZE = 36
Helper.PREVIEW_COUNT_FONT_MIN = 12
Helper.OFFSET_RANGE = 200
Helper.RADIAL_RADIUS_RANGE = 600
Helper.RADIAL_ROTATION_RANGE = 360
Helper.EXAMPLE_COOLDOWN_PERCENT = 0.55
Helper.VALID_DIRECTIONS = {
	RIGHT = true,
	LEFT = true,
	UP = true,
	DOWN = true,
}
Helper.VALID_LAYOUT_MODES = {
	GRID = true,
	RADIAL = true,
}
local STRATA_ORDER = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
Helper.STRATA_ORDER = STRATA_ORDER
Helper.VALID_STRATA = {}
for _, strata in ipairs(STRATA_ORDER) do
	Helper.VALID_STRATA[strata] = true
end
Helper.VALID_ANCHORS = {
	TOPLEFT = true,
	TOP = true,
	TOPRIGHT = true,
	LEFT = true,
	CENTER = true,
	RIGHT = true,
	BOTTOMLEFT = true,
	BOTTOM = true,
	BOTTOMRIGHT = true,
}
Helper.VALID_FONT_STYLE = {
	NONE = true,
	OUTLINE = true,
	THICKOUTLINE = true,
	MONOCHROMEOUTLINE = true,
}
Helper.GENERIC_ANCHORS = {
	EQOL_ANCHOR_PLAYER = {
		label = L["UFPlayerFrame"] or _G.HUD_EDIT_MODE_PLAYER_FRAME_LABEL or "Player Frame",
		blizz = "PlayerFrame",
		uf = "EQOLUFPlayerFrame",
		ufKey = "player",
	},
	EQOL_ANCHOR_TARGET = {
		label = L["UFTargetFrame"] or _G.HUD_EDIT_MODE_TARGET_FRAME_LABEL or "Target Frame",
		blizz = "TargetFrame",
		uf = "EQOLUFTargetFrame",
		ufKey = "target",
	},
	EQOL_ANCHOR_TARGETTARGET = {
		label = L["UFToTFrame"] or "Target of Target",
		blizz = "TargetFrameToT",
		uf = "EQOLUFToTFrame",
		ufKey = "targettarget",
	},
	EQOL_ANCHOR_FOCUS = {
		label = L["UFFocusFrame"] or _G.HUD_EDIT_MODE_FOCUS_FRAME_LABEL or "Focus Frame",
		blizz = "FocusFrame",
		uf = "EQOLUFFocusFrame",
		ufKey = "focus",
	},
	EQOL_ANCHOR_PET = {
		label = L["UFPetFrame"] or _G.HUD_EDIT_MODE_PET_FRAME_LABEL or "Pet Frame",
		blizz = "PetFrame",
		uf = "EQOLUFPetFrame",
		ufKey = "pet",
	},
	EQOL_ANCHOR_BOSS = {
		label = L["UFBossFrame"] or _G.HUD_EDIT_MODE_BOSS_FRAMES_LABEL or "Boss Frame",
		blizz = "BossTargetFrameContainer",
		uf = "EQOLUFBossContainer",
		ufKey = "boss",
	},
}
Helper.GENERIC_ANCHOR_ORDER = {
	"EQOL_ANCHOR_PLAYER",
	"EQOL_ANCHOR_TARGET",
	"EQOL_ANCHOR_TARGETTARGET",
	"EQOL_ANCHOR_FOCUS",
	"EQOL_ANCHOR_PET",
	"EQOL_ANCHOR_BOSS",
}
Helper.GENERIC_ANCHOR_BY_FRAME = {
	PlayerFrame = "EQOL_ANCHOR_PLAYER",
	EQOLUFPlayerFrame = "EQOL_ANCHOR_PLAYER",
	TargetFrame = "EQOL_ANCHOR_TARGET",
	EQOLUFTargetFrame = "EQOL_ANCHOR_TARGET",
	TargetFrameToT = "EQOL_ANCHOR_TARGETTARGET",
	EQOLUFToTFrame = "EQOL_ANCHOR_TARGETTARGET",
	FocusFrame = "EQOL_ANCHOR_FOCUS",
	EQOLUFFocusFrame = "EQOL_ANCHOR_FOCUS",
	PetFrame = "EQOL_ANCHOR_PET",
	EQOLUFPetFrame = "EQOL_ANCHOR_PET",
	BossTargetFrameContainer = "EQOL_ANCHOR_BOSS",
	EQOLUFBossContainer = "EQOL_ANCHOR_BOSS",
}

function Helper.ClampNumber(value, minValue, maxValue, fallback)
	local num = tonumber(value)
	if num == nil then return fallback end
	if minValue ~= nil and num < minValue then return minValue end
	if maxValue ~= nil and num > maxValue then return maxValue end
	return num
end

function Helper.ClampInt(value, minValue, maxValue, fallback)
	local num = Helper.ClampNumber(value, minValue, maxValue, fallback)
	if num == nil then return nil end
	return math.floor(num + 0.5)
end

function Helper.NormalizeDirection(direction, fallback)
	if direction and Helper.VALID_DIRECTIONS[direction] then return direction end
	if fallback and Helper.VALID_DIRECTIONS[fallback] then return fallback end
	return "RIGHT"
end

function Helper.NormalizeLayoutMode(value, fallback)
	if type(value) == "string" then
		local upper = string.upper(value)
		if Helper.VALID_LAYOUT_MODES[upper] then return upper end
	end
	if type(fallback) == "string" then
		local upper = string.upper(fallback)
		if Helper.VALID_LAYOUT_MODES[upper] then return upper end
	end
	return "GRID"
end

function Helper.NormalizeStrata(strata, fallback)
	if type(strata) == "string" then
		local upper = string.upper(strata)
		if Helper.VALID_STRATA[upper] then return upper end
	end
	if type(fallback) == "string" then
		local upper = string.upper(fallback)
		if Helper.VALID_STRATA[upper] then return upper end
	end
	return "MEDIUM"
end

function Helper.NormalizeColor(value, fallback)
	local ref = fallback or { 1, 1, 1, 1 }
	if type(value) ~= "table" then return { ref[1], ref[2], ref[3], ref[4] } end
	local r = value.r or value[1] or ref[1] or 1
	local g = value.g or value[2] or ref[2] or 1
	local b = value.b or value[3] or ref[3] or 1
	local a = value.a
	if a == nil then a = value[4] end
	if a == nil then a = ref[4] end
	if a == nil then a = 1 end
	if r < 0 then
		r = 0
	elseif r > 1 then
		r = 1
	end
	if g < 0 then
		g = 0
	elseif g > 1 then
		g = 1
	end
	if b < 0 then
		b = 0
	elseif b > 1 then
		b = 1
	end
	if a < 0 then
		a = 0
	elseif a > 1 then
		a = 1
	end
	return { r, g, b, a }
end

function Helper.ResolveColor(value, fallback)
	local ref = fallback or { 1, 1, 1, 1 }
	local r, g, b, a
	if type(value) == "table" then
		r = value.r or value[1] or ref[1] or 1
		g = value.g or value[2] or ref[2] or 1
		b = value.b or value[3] or ref[3] or 1
		a = value.a
		if a == nil then a = value[4] end
	else
		r = ref[1] or 1
		g = ref[2] or 1
		b = ref[3] or 1
		a = ref[4]
	end
	if a == nil then a = ref[4] end
	if a == nil then a = 1 end
	if r < 0 then
		r = 0
	elseif r > 1 then
		r = 1
	end
	if g < 0 then
		g = 0
	elseif g > 1 then
		g = 1
	end
	if b < 0 then
		b = 0
	elseif b > 1 then
		b = 1
	end
	if a < 0 then
		a = 0
	elseif a > 1 then
		a = 1
	end
	return r, g, b, a
end

function Helper.NormalizeAnchor(anchor, fallback)
	if anchor and Helper.VALID_ANCHORS[anchor] then return anchor end
	if fallback and Helper.VALID_ANCHORS[fallback] then return fallback end
	return "CENTER"
end

function Helper.NormalizeGrowthPoint(value, fallback)
	local anchor = Helper.NormalizeAnchor(value, fallback)
	if anchor == "TOP" or anchor == "CENTER" or anchor == "BOTTOM" then return "TOP" end
	if anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then return "TOPRIGHT" end
	return "TOPLEFT"
end

function Helper.NormalizeRelativeFrameName(value)
	if type(value) ~= "string" or value == "" then return "UIParent" end
	if Helper.GENERIC_ANCHORS[value] then return value end
	local mapped = Helper.GENERIC_ANCHOR_BY_FRAME[value]
	if mapped then return mapped end
	return value
end

function Helper.NormalizeFontStyle(style, fallback)
	if style == nil then style = fallback end
	if style == nil then return nil end
	if style == "" or style == "NONE" then return "" end
	if style == "MONOCHROMEOUTLINE" or style == "OUTLINE,MONOCHROME" or style == "MONOCHROME,OUTLINE" then return "OUTLINE,MONOCHROME" end
	return style
end

function Helper.NormalizeFontStyleChoice(style, fallback)
	if style == nil then style = fallback end
	if style == nil or style == "" then return "NONE" end
	if style == "OUTLINE,MONOCHROME" or style == "MONOCHROME,OUTLINE" then return "MONOCHROMEOUTLINE" end
	if Helper.VALID_FONT_STYLE[style] then return style end
	return "NONE"
end

function Helper.NormalizeOpacity(value, fallback)
	local resolvedFallback = fallback
	if resolvedFallback == nil then resolvedFallback = 1 end
	local num = Helper.ClampNumber(value, 0, 1, resolvedFallback)
	if num == nil then return resolvedFallback end
	return num
end

function Helper.ResolveFontPath(value, fallback)
	if type(value) == "string" and value ~= "" then return value end
	if type(fallback) == "string" and fallback ~= "" then return fallback end
	return STANDARD_TEXT_FONT
end

function Helper.GetCountFontDefaults(frame)
	if frame then
		local icon = frame.icons and frame.icons[1]
		if icon and icon.count and icon.count.GetFont then return icon.count:GetFont() end
	end
	local fallback = (addon.variables and addon.variables.defaultFont) or (LSM and LSM:Fetch("font", LSM.DefaultMedia.font)) or STANDARD_TEXT_FONT
	return fallback, 12, "OUTLINE"
end

function Helper.GetChargesFontDefaults(frame)
	if frame then
		local icon = frame.icons and frame.icons[1]
		if icon and icon.charges and icon.charges.GetFont then return icon.charges:GetFont() end
	end
	return Helper.GetCountFontDefaults()
end

function Helper.GetFontOptions(defaultPath)
	local list = {}
	local seen = {}
	local function add(path, label)
		if type(path) ~= "string" or path == "" then return end
		local key = string.lower(path)
		if seen[key] then return end
		seen[key] = true
		list[#list + 1] = { value = path, label = label }
	end
	if LSM and LSM.HashTable then
		for name, path in pairs(LSM:HashTable("font") or {}) do
			add(path, tostring(name))
		end
	end
	if defaultPath then add(defaultPath, DEFAULT) end
	table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return list
end

function Helper.Utf8Iter(str) return (str or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") end

function Helper.Utf8Len(str)
	local len = 0
	for _ in Helper.Utf8Iter(str) do
		len = len + 1
	end
	return len
end

function Helper.Utf8Sub(str, i, j)
	str = str or ""
	if str == "" then return "" end
	i = i or 1
	j = j or -1
	if i < 1 then i = 1 end
	local len = Helper.Utf8Len(str)
	if j < 0 then j = len + j + 1 end
	if j > len then j = len end
	if i > j then return "" end
	local pos = 1
	local startByte, endByte
	local idx = 0
	for char in Helper.Utf8Iter(str) do
		idx = idx + 1
		if idx == i then startByte = pos end
		if idx == j then
			endByte = pos + #char - 1
			break
		end
		pos = pos + #char
	end
	return str:sub(startByte or 1, endByte or #str)
end

function Helper.EllipsizeFontString(fontString, text, maxWidth)
	if not fontString or maxWidth <= 0 then return text end
	text = text or ""
	fontString:SetText(text)
	if fontString:GetStringWidth() <= maxWidth then return text end
	local ellipsis = "..."
	fontString:SetText(ellipsis)
	if fontString:GetStringWidth() > maxWidth then return ellipsis end
	local length = Helper.Utf8Len(text)
	local low, high = 1, length
	local best = ellipsis
	while low <= high do
		local mid = math.floor((low + high) / 2)
		local candidate = Helper.Utf8Sub(text, 1, mid) .. ellipsis
		fontString:SetText(candidate)
		if fontString:GetStringWidth() <= maxWidth then
			best = candidate
			low = mid + 1
		else
			high = mid - 1
		end
	end
	return best
end

function Helper.SetButtonTextEllipsized(button, text)
	if not button then return end
	local fontString = button.Text or button:GetFontString()
	if not fontString then
		button:SetText(text or "")
		return
	end
	local maxWidth = (button:GetWidth() or 0) - 12
	if maxWidth <= 0 then
		button:SetText(text or "")
		return
	end
	fontString:SetWidth(maxWidth)
	if fontString.SetMaxLines then fontString:SetMaxLines(1) end
	if fontString.SetWordWrap then fontString:SetWordWrap(false) end
	button:SetText(Helper.EllipsizeFontString(fontString, text or "", maxWidth))
end

function Helper.CreateLabel(parent, text, size, style)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetText(text or "")
	label:SetFont((addon.variables and addon.variables.defaultFont) or label:GetFont(), size or 12, style or "OUTLINE")
	label:SetTextColor(1, 0.82, 0, 1)
	return label
end

function Helper.CreateButton(parent, text, width, height)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetText(text or "")
	btn:SetSize(width or 120, height or 22)
	return btn
end

function Helper.CreateEditBox(parent, width, height)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width or 120, height or 22)
	box:SetAutoFocus(false)
	box:SetFontObject(GameFontHighlightSmall)
	return box
end

function Helper.CreateCheck(parent, text)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb.Text:SetText(text or "")
	cb.Text:SetTextColor(1, 1, 1, 1)
	return cb
end

function Helper.CreateSlider(parent, width, minValue, maxValue, step)
	local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
	slider:SetMinMaxValues(minValue or 0, maxValue or 1)
	slider:SetValueStep(step or 1)
	slider:SetObeyStepOnDrag(true)
	slider:SetWidth(width or 180)
	if slider.Low then slider.Low:SetText(tostring(minValue or 0)) end
	if slider.High then slider.High:SetText(tostring(maxValue or 1)) end
	return slider
end

function Helper.CreateRowButton(parent, height)
	local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
	row:SetHeight(height or 28)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints(row)
	row.bg:SetColorTexture(0, 0, 0, 0.2)
	row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.highlight:SetAllPoints(row)
	row.highlight:SetColorTexture(1, 1, 1, 0.06)
	return row
end

local function spellHasCharges(spellId)
	if not spellId then return false end
	if not (C_Spell and C_Spell.GetSpellCharges) then return false end
	local info = C_Spell.GetSpellCharges(spellId)
	if type(info) ~= "table" then return false end
	local issecretvalue = _G.issecretvalue
	if issecretvalue then
		if issecretvalue(info) then return false end
		if info.currentCharges ~= nil and issecretvalue(info.currentCharges) then return false end
		if info.maxCharges ~= nil and issecretvalue(info.maxCharges) then return false end
	end
	local maxCharges = info.maxCharges
	if type(maxCharges) ~= "number" then return false end
	return maxCharges > 1
end

function Helper.CopyTableShallow(source)
	local result = {}
	if source then
		for k, v in pairs(source) do
			result[k] = v
		end
	end
	return result
end

function Helper.NormalizeBool(value, fallback)
	if value == nil then return fallback end
	return value and true or false
end

function Helper.GetNextNumericId(map, start)
	local maxId = tonumber(start) or 0
	if map then
		for key in pairs(map) do
			local num = tonumber(key)
			if num and num > maxId then maxId = num end
		end
	end
	return maxId + 1
end

function Helper.CreateRoot()
	return {
		version = 1,
		panels = {},
		order = {},
		selectedPanel = nil,
		defaults = {
			layout = Helper.CopyTableShallow(Helper.PANEL_LAYOUT_DEFAULTS),
			entry = Helper.CopyTableShallow(Helper.ENTRY_DEFAULTS),
		},
	}
end

function Helper.NormalizeRoot(root)
	if type(root) ~= "table" then return Helper.CreateRoot() end
	if type(root.version) ~= "number" then root.version = 1 end
	if type(root.panels) ~= "table" then root.panels = {} end
	if type(root.order) ~= "table" then root.order = {} end
	if type(root.defaults) ~= "table" then root.defaults = {} end
	if type(root.defaults.layout) ~= "table" then
		root.defaults.layout = Helper.CopyTableShallow(Helper.PANEL_LAYOUT_DEFAULTS)
	else
		for key, value in pairs(Helper.PANEL_LAYOUT_DEFAULTS) do
			if root.defaults.layout[key] == nil then root.defaults.layout[key] = value end
		end
	end
	if type(root.defaults.entry) ~= "table" then
		root.defaults.entry = Helper.CopyTableShallow(Helper.ENTRY_DEFAULTS)
	else
		for key, value in pairs(Helper.ENTRY_DEFAULTS) do
			if root.defaults.entry[key] == nil then root.defaults.entry[key] = value end
		end
	end
	root.defaults.entry.alwaysShow = Helper.ENTRY_DEFAULTS.alwaysShow
	root.defaults.entry.showCooldown = Helper.ENTRY_DEFAULTS.showCooldown
	root.defaults.entry.showCooldownText = Helper.ENTRY_DEFAULTS.showCooldownText
	root.defaults.entry.showCharges = Helper.ENTRY_DEFAULTS.showCharges
	root.defaults.entry.showStacks = Helper.ENTRY_DEFAULTS.showStacks
	root.defaults.entry.glowReady = Helper.ENTRY_DEFAULTS.glowReady
	root.defaults.entry.glowDuration = Helper.ENTRY_DEFAULTS.glowDuration
	root.defaults.entry.soundReady = Helper.ENTRY_DEFAULTS.soundReady
	root.defaults.entry.soundReadyFile = Helper.ENTRY_DEFAULTS.soundReadyFile
	return root
end

function Helper.NormalizePanel(panel, defaults)
	if type(panel) ~= "table" then return end
	defaults = defaults or {}
	local layoutDefaults = defaults.layout or Helper.PANEL_LAYOUT_DEFAULTS
	if type(panel.layout) ~= "table" then panel.layout = {} end
	local hadKeybindsEnabled = panel.layout.keybindsEnabled
	local hadChargesCooldown = panel.layout.showChargesCooldown
	for key, value in pairs(layoutDefaults) do
		if panel.layout[key] == nil then panel.layout[key] = value end
	end
	if type(panel.anchor) ~= "table" then panel.anchor = {} end
	local anchor = panel.anchor
	if anchor.point == nil then anchor.point = panel.point or "CENTER" end
	if anchor.relativePoint == nil then anchor.relativePoint = anchor.point end
	if anchor.x == nil then anchor.x = panel.x or 0 end
	if anchor.y == nil then anchor.y = panel.y or 0 end
	if not anchor.relativeFrame or anchor.relativeFrame == "" then anchor.relativeFrame = "UIParent" end
	if panel.point == nil then panel.point = "CENTER" end
	if panel.x == nil then panel.x = 0 end
	if panel.y == nil then panel.y = 0 end
	panel.point = anchor.point or panel.point
	panel.x = anchor.x or panel.x
	panel.y = anchor.y or panel.y
	if type(panel.entries) ~= "table" then panel.entries = {} end
	if type(panel.order) ~= "table" then panel.order = {} end
	if panel.enabled == nil then panel.enabled = true end
	if type(panel.name) ~= "string" or panel.name == "" then panel.name = "Cooldown Panel" end
	if hadKeybindsEnabled == nil or hadChargesCooldown == nil then
		for _, entry in pairs(panel.entries) do
			if entry then
				if hadKeybindsEnabled == nil and entry.showKeybinds == true then panel.layout.keybindsEnabled = true end
				if hadChargesCooldown == nil and entry.showChargesCooldown == true then panel.layout.showChargesCooldown = true end
				if (hadKeybindsEnabled ~= nil or panel.layout.keybindsEnabled == true) and (hadChargesCooldown ~= nil or panel.layout.showChargesCooldown == true) then break end
			end
		end
	end
end

function Helper.NormalizeEntry(entry, defaults)
	if type(entry) ~= "table" then return end
	local hadShowCharges = entry.showCharges ~= nil
	local hadShowStacks = entry.showStacks ~= nil
	defaults = defaults or {}
	local entryDefaults = defaults.entry or {}
	for key, value in pairs(entryDefaults) do
		if entry[key] == nil then entry[key] = value end
	end
	for key, value in pairs(Helper.ENTRY_DEFAULTS) do
		if entry[key] == nil then entry[key] = value end
	end
	if entry.alwaysShow == nil then entry.alwaysShow = true end
	if entry.showCooldown == nil then entry.showCooldown = true end
	if entry.type == "ITEM" and entry.showItemCount == nil then entry.showItemCount = true end
	if entry.type == "SPELL" then
		if not hadShowCharges then entry.showCharges = spellHasCharges(entry.spellID) end
		if not hadShowStacks then entry.showStacks = false end
	end
	local duration = tonumber(entry.glowDuration)
	if duration == nil then duration = defaults.entry and defaults.entry.glowDuration or Helper.ENTRY_DEFAULTS.glowDuration or 0 end
	if duration < 0 then duration = 0 end
	if duration > 30 then duration = 30 end
	entry.glowDuration = math.floor(duration + 0.5)
	if type(entry.soundReady) ~= "boolean" then entry.soundReady = Helper.ENTRY_DEFAULTS.soundReady end
	if type(entry.soundReadyFile) ~= "string" or entry.soundReadyFile == "" then entry.soundReadyFile = Helper.ENTRY_DEFAULTS.soundReadyFile end
	if type(entry.staticText) ~= "string" then entry.staticText = Helper.ENTRY_DEFAULTS.staticText end
	if type(entry.staticTextShowOnCooldown) ~= "boolean" then entry.staticTextShowOnCooldown = Helper.ENTRY_DEFAULTS.staticTextShowOnCooldown end
	if type(entry.staticTextFont) ~= "string" then entry.staticTextFont = Helper.ENTRY_DEFAULTS.staticTextFont end
	entry.staticTextSize = Helper.ClampInt(entry.staticTextSize, 6, 64, Helper.ENTRY_DEFAULTS.staticTextSize or 12)
	entry.staticTextStyle = Helper.NormalizeFontStyleChoice(entry.staticTextStyle, Helper.ENTRY_DEFAULTS.staticTextStyle or "OUTLINE")
	entry.staticTextAnchor = Helper.NormalizeAnchor(entry.staticTextAnchor, Helper.ENTRY_DEFAULTS.staticTextAnchor or "CENTER")
	entry.staticTextX = Helper.ClampInt(entry.staticTextX, -Helper.OFFSET_RANGE, Helper.OFFSET_RANGE, Helper.ENTRY_DEFAULTS.staticTextX or 0)
	entry.staticTextY = Helper.ClampInt(entry.staticTextY, -Helper.OFFSET_RANGE, Helper.OFFSET_RANGE, Helper.ENTRY_DEFAULTS.staticTextY or 0)
end

function Helper.SyncOrder(order, map)
	if type(order) ~= "table" or type(map) ~= "table" then return end
	local cleaned = {}
	local seen = {}
	for _, id in ipairs(order) do
		if map[id] and not seen[id] then
			seen[id] = true
			cleaned[#cleaned + 1] = id
		end
	end
	for id in pairs(map) do
		if not seen[id] then cleaned[#cleaned + 1] = id end
	end
	for i = 1, #order do
		order[i] = nil
	end
	for i = 1, #cleaned do
		order[i] = cleaned[i]
	end
end

function Helper.CreatePanel(name, defaults)
	defaults = defaults or {}
	local layoutDefaults = defaults.layout or Helper.PANEL_LAYOUT_DEFAULTS
	return {
		name = (type(name) == "string" and name ~= "" and name) or "Cooldown Panel",
		enabled = true,
		point = "CENTER",
		x = 0,
		y = 0,
		anchor = {
			point = "CENTER",
			relativePoint = "CENTER",
			relativeFrame = "UIParent",
			x = 0,
			y = 0,
		},
		layout = Helper.CopyTableShallow(layoutDefaults),
		entries = {},
		order = {},
	}
end

function Helper.CreateEntry(entryType, idValue, defaults)
	defaults = defaults or {}
	local entryDefaults = defaults.entry or {}
	local entry = Helper.CopyTableShallow(entryDefaults)
	for key, value in pairs(Helper.ENTRY_DEFAULTS) do
		if entry[key] == nil then entry[key] = value end
	end
	entry.type = entryType
	if entryType == "SPELL" then
		entry.spellID = tonumber(idValue)
		entry.showCharges = spellHasCharges(entry.spellID)
		entry.showStacks = false
	elseif entryType == "ITEM" then
		entry.itemID = tonumber(idValue)
		if entry.showItemCount == nil then entry.showItemCount = true end
	elseif entryType == "SLOT" then
		entry.slotID = tonumber(idValue)
	end
	return entry
end

function Helper.GetEntryKey(panelId, entryId) return tostring(panelId) .. ":" .. tostring(entryId) end

function Helper.NormalizeDisplayCount(value)
	if value == nil then return nil end
	if issecretvalue and issecretvalue(value) then return value end
	if value == "" then return nil end
	return value
end

function Helper.HasDisplayCount(value)
	if value == nil then return false end
	if issecretvalue and issecretvalue(value) then return true end
	return value ~= ""
end

Helper.Keybinds = Helper.Keybinds or {}
local Keybinds = Helper.Keybinds

local DEFAULT_ACTION_BUTTON_NAMES = {
	"ActionButton",
	"MultiBarBottomLeftButton",
	"MultiBarBottomRightButton",
	"MultiBarLeftButton",
	"MultiBarRightButton",
	"MultiBar5Button",
	"MultiBar6Button",
	"MultiBar7Button",
}

local GetItemInfoInstantFn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetOverrideSpell = C_Spell and C_Spell.GetOverrideSpell
local GetInventoryItemID = GetInventoryItemID
local GetActionDisplayCount = C_ActionBar and C_ActionBar.GetActionDisplayCount
local FindSpellActionButtons = C_ActionBar and C_ActionBar.FindSpellActionButtons
local issecretvalue = _G.issecretvalue

local function getEffectiveSpellId(spellId)
	local id = tonumber(spellId)
	if not id then return nil end
	if GetOverrideSpell then
		local overrideId = GetOverrideSpell(id)
		if type(overrideId) == "number" and overrideId > 0 then return overrideId end
	end
	return id
end

local function getRoot()
	if CooldownPanels and CooldownPanels.GetRoot then return CooldownPanels:GetRoot() end
	return nil
end

local function getRuntime(panelId)
	CooldownPanels.runtime = CooldownPanels.runtime or {}
	local runtime = CooldownPanels.runtime[panelId]
	if not runtime then
		runtime = {}
		CooldownPanels.runtime[panelId] = runtime
	end
	return runtime
end

local function getActionSlotForSpell(spellId)
	if not spellId then return nil end
	if ActionButtonUtil and ActionButtonUtil.GetActionButtonBySpellID then
		local button = ActionButtonUtil.GetActionButtonBySpellID(spellId, false, false)
		if button and button.action then return button.action end
	end
	if FindSpellActionButtons then
		local slots = FindSpellActionButtons(spellId)
		if type(slots) == "table" and slots[1] then return slots[1] end
	end
	return nil
end

local function getActionDisplayCountForSpell(spellId)
	if not GetActionDisplayCount then return nil end
	local slot = getActionSlotForSpell(spellId)
	if not slot then return nil end
	return GetActionDisplayCount(slot)
end

function Helper.UpdateActionDisplayCountsForSpell(spellId, baseSpellId)
	if not GetActionDisplayCount then return false end
	local id = tonumber(spellId)
	local baseId = tonumber(baseSpellId)
	local runtime = CooldownPanels.runtime
	local index = runtime and runtime.spellIndex
	if not index then return false end

	local panels = {}
	if id and index[id] then
		for panelId in pairs(index[id]) do
			panels[panelId] = true
		end
	end
	if baseId and index[baseId] then
		for panelId in pairs(index[baseId]) do
			panels[panelId] = true
		end
	end
	if not next(panels) then return false end

	runtime.actionDisplayCounts = runtime.actionDisplayCounts or {}
	local cache = runtime.actionDisplayCounts

	for panelId in pairs(panels) do
		local panel = CooldownPanels:GetPanel(panelId)
		if panel and panel.entries then
			local runtimePanel = getRuntime(panelId)
			local entryToIcon = runtimePanel.entryToIcon
			local needsRefresh = false
			for entryId, entry in pairs(panel.entries) do
				if entry and entry.type == "SPELL" and entry.showStacks == true and entry.spellID then
					local entrySpellId = entry.spellID
					local effectiveId = getEffectiveSpellId(entrySpellId)
					local matches = (id and (entrySpellId == id or effectiveId == id)) or (baseId and (entrySpellId == baseId or effectiveId == baseId))
					if matches then
						local displayCount = getActionDisplayCountForSpell(effectiveId) or (effectiveId ~= entrySpellId and getActionDisplayCountForSpell(entrySpellId) or nil)
						displayCount = Helper.NormalizeDisplayCount(displayCount)
						cache[Helper.GetEntryKey(panelId, entryId)] = displayCount

						local icon = entryToIcon and entryToIcon[entryId]
						if icon then
							if displayCount ~= nil then
								icon.count:SetText(displayCount)
								icon.count:Show()
							else
								icon.count:Hide()
								needsRefresh = true
							end
						else
							if displayCount ~= nil then needsRefresh = true end
						end
					end
				end
			end
			if needsRefresh then
				if CooldownPanels:GetPanel(panelId) then CooldownPanels:RefreshPanel(panelId) end
			end
		end
	end
	return true
end

local function getActionButtonSlotMap()
	local runtime = CooldownPanels.runtime or {}
	if runtime._eqolActionButtonSlotMap then return runtime._eqolActionButtonSlotMap end
	local map = {}
	local buttonNames = (ActionButtonUtil and ActionButtonUtil.ActionBarButtonNames) or DEFAULT_ACTION_BUTTON_NAMES
	local buttonCount = NUM_ACTIONBAR_BUTTONS or 12
	for _, prefix in ipairs(buttonNames) do
		for i = 1, buttonCount do
			local btn = _G[prefix .. i]
			local action = btn and btn.action
			if action and map[action] == nil then map[action] = btn end
		end
	end
	runtime._eqolActionButtonSlotMap = map
	CooldownPanels.runtime = runtime
	return map
end

local function getBindingTextForButton(button)
	if not button or not GetBindingKey then return nil end
	local key = nil
	if button.bindingAction then key = GetBindingKey(button.bindingAction) end
	if button:GetName() == "MultiBarBottomLeftButton6" then
	end
	if not key and button.GetName then key = GetBindingKey("CLICK " .. button:GetName() .. ":LeftButton") end
	local text = key and GetBindingText and GetBindingText(key, 1)
	if text == "" then text = nil end
	return text
end

local function formatKeybindText(text)
	if type(text) ~= "string" or text == "" then return text end
	local labels = addon and addon.ActionBarLabels
	if labels and labels.ShortenHotkeyText then return labels.ShortenHotkeyText(text) end
	return text
end

local function getBindingTextForActionSlot(slot)
	if not slot then return nil end
	local map = getActionButtonSlotMap()
	local text = map and getBindingTextForButton(map[slot])
	if text then return text end
	if GetBindingKey then
		local buttons = NUM_ACTIONBAR_BUTTONS or 12
		local index = ((slot - 1) % buttons) + 1
		local key = GetBindingKey("ACTIONBUTTON" .. index)
		text = key and GetBindingText and GetBindingText(key, 1)
		if text == "" then text = nil end
		return text
	end
	return nil
end

local function buildKeybindLookup()
	local runtime = CooldownPanels.runtime or {}
	if runtime._eqolKeybindLookup then return runtime._eqolKeybindLookup end
	local lookup = {
		item = {},
	}
	local buttonNames = (ActionButtonUtil and ActionButtonUtil.ActionBarButtonNames) or DEFAULT_ACTION_BUTTON_NAMES
	local buttonCount = NUM_ACTIONBAR_BUTTONS or 12
	local getMacroItem = GetMacroItem

	for _, prefix in ipairs(buttonNames) do
		for i = 1, buttonCount do
			local btn = _G[prefix .. i]
			local slot = btn and btn.action
			if slot then
				local keyText = getBindingTextForButton(btn)
				if not keyText and GetBindingKey then
					local buttons = NUM_ACTIONBAR_BUTTONS or 12
					local index = ((slot - 1) % buttons) + 1
					local key = GetBindingKey("ACTIONBUTTON" .. index)
					keyText = key and GetBindingText and GetBindingText(key, 1)
					if keyText == "" then keyText = nil end
				end
				if keyText and GetActionInfo then
					local actionType, actionId = GetActionInfo(slot)
					if actionType == "item" and actionId then
						if not lookup.item[actionId] then lookup.item[actionId] = keyText end
					elseif actionType == "macro" and actionId then
						if getMacroItem then
							local macroItem = getMacroItem(actionId)
							if macroItem then
								local itemId
								if type(macroItem) == "number" then
									itemId = macroItem
								elseif GetItemInfoInstantFn then
									itemId = GetItemInfoInstantFn(macroItem)
								end
								if itemId and not lookup.item[itemId] then lookup.item[itemId] = keyText end
							end
						end
					end
				end
			end
		end
	end

	runtime._eqolKeybindLookup = lookup
	CooldownPanels.runtime = runtime
	return lookup
end

function Keybinds.InvalidateCache()
	if not CooldownPanels.runtime then return end
	CooldownPanels.runtime._eqolActionButtonSlotMap = nil
	CooldownPanels.runtime._eqolKeybindLookup = nil
	CooldownPanels.runtime._eqolKeybindCache = nil
end

function Keybinds.MarkPanelsDirty()
	CooldownPanels.runtime = CooldownPanels.runtime or {}
	CooldownPanels.runtime.keybindPanelsDirty = true
end

function Keybinds.RebuildPanels()
	local root = getRoot()
	if not root or not root.panels then return nil end
	CooldownPanels.runtime = CooldownPanels.runtime or {}
	local runtime = CooldownPanels.runtime
	local panels = {}
	for panelId, panel in pairs(root.panels) do
		local layout = panel and panel.layout
		if panel and panel.enabled ~= false and layout and layout.keybindsEnabled == true then panels[panelId] = true end
	end
	runtime.keybindPanels = panels
	runtime.keybindPanelsDirty = nil
	return panels
end

function Keybinds.HasPanels()
	local runtime = CooldownPanels.runtime
	if not runtime then return false end
	local panels = (runtime.keybindPanelsDirty or runtime.keybindPanels == nil) and Keybinds.RebuildPanels() or runtime.keybindPanels
	return panels ~= nil and next(panels) ~= nil
end

function Keybinds.RefreshPanels()
	local runtime = CooldownPanels.runtime
	if not runtime then return false end
	local panels = (runtime.keybindPanelsDirty or not runtime.keybindPanels) and Keybinds.RebuildPanels() or runtime.keybindPanels
	if not panels or not next(panels) then return false end
	for panelId in pairs(panels) do
		if CooldownPanels.GetPanel and CooldownPanels.RefreshPanel then
			if CooldownPanels:GetPanel(panelId) then CooldownPanels:RefreshPanel(panelId) end
		end
	end
	return true
end

function Keybinds.RequestRefresh(cause)
	local runtime = CooldownPanels.runtime
	if not runtime then return end
	if not Keybinds.HasPanels() then return end
	if cause then runtime.keybindRefreshCause = cause end
	if runtime.keybindRefreshPending then return end
	runtime.keybindRefreshPending = true
	C_Timer.After(0.1, function()
		runtime.keybindRefreshPending = nil
		if not Keybinds.HasPanels() then return end
		runtime.keybindRefreshCauseActive = runtime.keybindRefreshCause
		runtime.keybindRefreshCause = nil
		Keybinds.InvalidateCache()
		Keybinds.RefreshPanels()
		runtime.keybindRefreshCauseActive = nil
	end)
end

function Keybinds.GetEntryKeybindText(entry, layout)
	if not entry then return nil end
	if layout and layout.keybindsIgnoreItems == true and (entry.type == "ITEM" or entry.type == "SLOT") then return nil end
	local runtime = CooldownPanels.runtime or {}
	runtime._eqolKeybindCache = runtime._eqolKeybindCache or {}
	local slotItemId
	if entry.type == "SLOT" and entry.slotID then slotItemId = GetInventoryItemID and GetInventoryItemID("player", entry.slotID) end
	local effectiveSpellId = entry.type == "SPELL" and getEffectiveSpellId(entry.spellID) or nil
	local cacheKey = tostring(entry.type) .. ":" .. tostring(effectiveSpellId or entry.spellID or entry.itemID or entry.slotID or "") .. ":" .. tostring(slotItemId or "")
	local cached = runtime._eqolKeybindCache[cacheKey]
	if cached ~= nil then return cached or nil end

	local text = nil
	if entry.type == "SPELL" and entry.spellID then
		local spellId = effectiveSpellId or entry.spellID
		-- if C_ActionBar and C_ActionBar.FindSpellActionButtons then
		-- 	local slots = C_ActionBar.FindSpellActionButtons(spellId)
		-- 	if type(slots) == "table" then
		-- 		for _, slot in ipairs(slots) do
		-- 			text = getBindingTextForActionSlot(slot)
		-- 			if text then break end
		-- 		end
		-- 	end
		-- end
		if not text and ActionButtonUtil and ActionButtonUtil.GetActionButtonBySpellID then text = getBindingTextForButton(ActionButtonUtil.GetActionButtonBySpellID(spellId, false, false)) end
		if not text and effectiveSpellId and effectiveSpellId ~= entry.spellID then
			-- if C_ActionBar and C_ActionBar.FindSpellActionButtons then
			-- 	local slots = C_ActionBar.FindSpellActionButtons(entry.spellID)
			-- 	if type(slots) == "table" then
			-- 		for _, slot in ipairs(slots) do
			-- 			text = getBindingTextForActionSlot(slot)
			-- 			if text then break end
			-- 		end
			-- 	end
			-- end
			if not text and ActionButtonUtil and ActionButtonUtil.GetActionButtonBySpellID then
				text = getBindingTextForButton(ActionButtonUtil.GetActionButtonBySpellID(entry.spellID, false, false))
			end
		end
	elseif entry.type == "ITEM" and entry.itemID then
		local lookup = buildKeybindLookup()
		text = lookup.item and lookup.item[entry.itemID]
	elseif entry.type == "SLOT" and slotItemId then
		local lookup = buildKeybindLookup()
		text = lookup.item and lookup.item[slotItemId]
	end

	text = formatKeybindText(text)
	runtime._eqolKeybindCache[cacheKey] = text or false
	CooldownPanels.runtime = runtime
	return text
end

function CooldownPanels:RequestPanelRefresh(panelId)
	if not panelId then return end
	self.runtime = self.runtime or {}
	local rt = self.runtime

	rt._eqolPanelRefreshQueue = rt._eqolPanelRefreshQueue or {}
	rt._eqolPanelRefreshQueue[panelId] = true

	if rt._eqolPanelRefreshPending then return end
	rt._eqolPanelRefreshPending = true

	C_Timer.After(0, function()
		local runtime = CooldownPanels.runtime
		if not runtime then return end
		runtime._eqolPanelRefreshPending = nil

		local q = runtime._eqolPanelRefreshQueue
		if not q then return end

		for id in pairs(q) do
			q[id] = nil
			if CooldownPanels:GetPanel(id) then CooldownPanels:RefreshPanel(id) end
		end
	end)
end
