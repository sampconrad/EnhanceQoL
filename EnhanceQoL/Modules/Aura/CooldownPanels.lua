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
local Helper = CooldownPanels.helper
local EditMode = addon.EditMode
local SettingType = EditMode and EditMode.lib and EditMode.lib.SettingType
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")
local LSM = LibStub("LibSharedMedia-3.0", true)
local Masque

CooldownPanels.ENTRY_TYPE = {
	SPELL = "SPELL",
	ITEM = "ITEM",
	SLOT = "SLOT",
}

_G["BINDING_NAME_EQOL_TOGGLE_COOLDOWN_PANELS"] = L["CooldownPanelBindingToggle"] or "Toggle Cooldown Panel Editor"

CooldownPanels.runtime = CooldownPanels.runtime or {}

local curveDesat = C_CurveUtil.CreateCurve()
curveDesat:SetType(Enum.LuaCurveType.Step)
curveDesat:AddPoint(0, 0)
curveDesat:AddPoint(0.1, 1)

local DEFAULT_PREVIEW_COUNT = 6
local MAX_PREVIEW_COUNT = 12
local PREVIEW_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local PREVIEW_ICON_SIZE = 36
local PREVIEW_COUNT_FONT_MIN = 12
local OFFSET_RANGE = 200
local EXAMPLE_COOLDOWN_PERCENT = 0.55
local VALID_DIRECTIONS = {
	RIGHT = true,
	LEFT = true,
	UP = true,
	DOWN = true,
}
local STRATA_ORDER = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
local VALID_STRATA = {}
for _, strata in ipairs(STRATA_ORDER) do
	VALID_STRATA[strata] = true
end
local VALID_ANCHORS = {
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
local VALID_FONT_STYLE = {
	NONE = true,
	OUTLINE = true,
	THICKOUTLINE = true,
	MONOCHROMEOUTLINE = true,
}
local GENERIC_ANCHORS = {
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
local GENERIC_ANCHOR_ORDER = {
	"EQOL_ANCHOR_PLAYER",
	"EQOL_ANCHOR_TARGET",
	"EQOL_ANCHOR_TARGETTARGET",
	"EQOL_ANCHOR_FOCUS",
	"EQOL_ANCHOR_PET",
	"EQOL_ANCHOR_BOSS",
}
local GENERIC_ANCHOR_BY_FRAME = {
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

local GetItemInfoInstantFn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemIconByID = C_Item and C_Item.GetItemIconByID
local GetItemCooldownFn = (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
local GetItemCountFn = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetItemSpell = C_Item and C_Item.GetItemSpell
local GetInventoryItemID = GetInventoryItemID
local GetInventoryItemCooldown = GetInventoryItemCooldown
local GetInventorySlotInfo = GetInventorySlotInfo
local GetActionInfo = GetActionInfo
local GetCursorInfo = GetCursorInfo
local GetCursorPosition = GetCursorPosition
local ClearCursor = ClearCursor
local GetSpellCooldownInfo = C_Spell and C_Spell.GetSpellCooldown or GetSpellCooldown
local GetSpellCooldownDuration = C_Spell and C_Spell.GetSpellCooldownDuration
local GetSpellChargesInfo = C_Spell and C_Spell.GetSpellCharges
local GetPlayerAuraBySpellID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
local IsSpellKnown = C_SpellBook.IsSpellInSpellBook
local IsEquippedItem = C_Item.IsEquippedItem
local GetTime = GetTime
local MenuUtil = MenuUtil
local issecretvalue = _G.issecretvalue
local DurationModifierRealTime = Enum and Enum.DurationTimeModifier and Enum.DurationTimeModifier.RealTime

local directionOptions = {
	{ value = "LEFT", label = _G.HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_LEFT or _G.LEFT or "Left" },
	{ value = "RIGHT", label = _G.HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_RIGHT or _G.RIGHT or "Right" },
	{ value = "UP", label = _G.HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_UP or _G.UP or "Up" },
	{ value = "DOWN", label = _G.HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_DOWN or _G.DOWN or "Down" },
}
local anchorOptions = {
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
local fontStyleOptions = {
	{ value = "NONE", label = L["None"] or "None" },
	{ value = "OUTLINE", label = L["Outline"] or "Outline" },
	{ value = "THICKOUTLINE", label = L["Thick Outline"] or "Thick Outline" },
	{ value = "MONOCHROMEOUTLINE", label = L["Monochrome Outline"] or "Monochrome Outline" },
}

local function normalizeId(value)
	local num = tonumber(value)
	if num then return num end
	return value
end

local function getRuntime(panelId)
	local runtime = CooldownPanels.runtime[panelId]
	if not runtime then
		runtime = {}
		CooldownPanels.runtime[panelId] = runtime
	end
	return runtime
end

local function refreshEditModeSettingValues()
	if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RefreshSettingValues then addon.EditModeLib.internal:RefreshSettingValues() end
end

local function getMasqueGroup()
	if not Masque and LibStub then Masque = LibStub("Masque", true) end
	if not Masque then return nil end
	CooldownPanels.runtime = CooldownPanels.runtime or {}
	if not CooldownPanels.runtime.masqueGroup then CooldownPanels.runtime.masqueGroup = Masque:Group(parentAddonName, "Cooldown Panels", "CooldownPanels") end
	return CooldownPanels.runtime.masqueGroup
end

function CooldownPanels:RegisterMasqueButtons()
	local group = getMasqueGroup()
	if not group then return end
	for _, runtime in pairs(self.runtime or {}) do
		local frame = runtime and runtime.frame
		if frame and frame._eqolPanelFrame and frame.icons then
			for _, icon in ipairs(frame.icons) do
				if icon and not icon._eqolMasqueAdded then
					local regions = {
						Icon = icon.texture,
						Cooldown = icon.cooldown,
						Normal = icon.msqNormal,
					}
					group:AddButton(icon, regions, "Action", true)
					icon._eqolMasqueAdded = true
				end
			end
		end
	end
end

function CooldownPanels:ReskinMasque()
	local group = getMasqueGroup()
	if group and group.ReSkin then group:ReSkin() end
end

local getEditor

local function clampNumber(value, minValue, maxValue, fallback)
	local num = tonumber(value)
	if not num then return fallback end
	if minValue and num < minValue then return minValue end
	if maxValue and num > maxValue then return maxValue end
	return num
end

local function clampInt(value, minValue, maxValue, fallback)
	local num = clampNumber(value, minValue, maxValue, fallback)
	if num == nil then return nil end
	return math.floor(num + 0.5)
end

local function normalizeDirection(direction, fallback)
	if direction and VALID_DIRECTIONS[direction] then return direction end
	if fallback and VALID_DIRECTIONS[fallback] then return fallback end
	return "RIGHT"
end

local function normalizeStrata(strata, fallback)
	if type(strata) == "string" then
		local upper = string.upper(strata)
		if VALID_STRATA[upper] then return upper end
	end
	if type(fallback) == "string" then
		local upper = string.upper(fallback)
		if VALID_STRATA[upper] then return upper end
	end
	return "MEDIUM"
end

local function normalizeAnchor(anchor, fallback)
	if anchor and VALID_ANCHORS[anchor] then return anchor end
	if fallback and VALID_ANCHORS[fallback] then return fallback end
	return "CENTER"
end

local function normalizeRelativeFrameName(value)
	if type(value) ~= "string" or value == "" then return "UIParent" end
	if GENERIC_ANCHORS[value] then return value end
	local mapped = GENERIC_ANCHOR_BY_FRAME[value]
	if mapped then return mapped end
	return value
end

local function ensurePanelAnchor(panel)
	if not panel then return nil end
	panel.anchor = panel.anchor or {}
	local anchor = panel.anchor
	if anchor.point == nil then anchor.point = panel.point or "CENTER" end
	if anchor.relativePoint == nil then anchor.relativePoint = anchor.point end
	if anchor.x == nil then anchor.x = panel.x or 0 end
	if anchor.y == nil then anchor.y = panel.y or 0 end
	anchor.relativeFrame = normalizeRelativeFrameName(anchor.relativeFrame)
	panel.point = anchor.point or panel.point
	panel.x = anchor.x or panel.x
	panel.y = anchor.y or panel.y
	return anchor
end

local function anchorUsesUIParent(anchor) return not anchor or (anchor.relativeFrame or "UIParent") == "UIParent" end

local function resolveAnchorFrame(anchor)
	local relativeName = normalizeRelativeFrameName(anchor and anchor.relativeFrame)
	if relativeName == "UIParent" then return UIParent end
	local generic = GENERIC_ANCHORS[relativeName]
	if generic then
		local ufCfg = addon.db and addon.db.ufFrames
		if ufCfg and generic.ufKey and ufCfg[generic.ufKey] and ufCfg[generic.ufKey].enabled then
			local ufFrame = _G[generic.uf]
			if ufFrame then return ufFrame end
		end
		local blizzFrame = _G[generic.blizz]
		if blizzFrame then return blizzFrame end
	end
	local anchorHelper = CooldownPanels.AnchorHelper
	if anchorHelper and anchorHelper.ResolveExternalFrame then
		local externalFrame = anchorHelper:ResolveExternalFrame(relativeName)
		if externalFrame then return externalFrame end
	end
	local frame = _G[relativeName]
	if frame then return frame end
	return UIParent
end

local function panelFrameName(panelId) return "EQOL_CooldownPanel" .. tostring(panelId) end

local function frameNameToPanelId(frameName)
	if type(frameName) ~= "string" then return nil end
	local id = frameName:match("^EQOL_CooldownPanel(%d+)$")
	return id and tonumber(id) or nil
end

local function normalizeFontStyle(style, fallback)
	if style == nil then style = fallback end
	if style == nil then return nil end
	if style == "" or style == "NONE" then return "" end
	if style == "MONOCHROMEOUTLINE" or style == "OUTLINE,MONOCHROME" or style == "MONOCHROME,OUTLINE" then return "OUTLINE,MONOCHROME" end
	return style
end

local function normalizeFontStyleChoice(style, fallback)
	if style == nil then style = fallback end
	if style == nil or style == "" then return "NONE" end
	if style == "OUTLINE,MONOCHROME" or style == "MONOCHROME,OUTLINE" then return "MONOCHROMEOUTLINE" end
	if VALID_FONT_STYLE[style] then return style end
	return "NONE"
end

local function normalizeOpacity(value, fallback)
	local resolvedFallback = fallback
	if resolvedFallback == nil then resolvedFallback = 1 end
	local num = clampNumber(value, 0, 1, resolvedFallback)
	if num == nil then return resolvedFallback end
	return num
end

local function resolveFontPath(value, fallback)
	if type(value) == "string" and value ~= "" then return value end
	if type(fallback) == "string" and fallback ~= "" then return fallback end
	return STANDARD_TEXT_FONT
end

local function getCountFontDefaults(frame)
	if frame then
		local icon = frame.icons and frame.icons[1]
		if icon and icon.count and icon.count.GetFont then return icon.count:GetFont() end
	end
	local fallback = (addon.variables and addon.variables.defaultFont) or (LSM and LSM:Fetch("font", LSM.DefaultMedia.font)) or STANDARD_TEXT_FONT
	return fallback, 12, "OUTLINE"
end

local function getChargesFontDefaults(frame)
	if frame then
		local icon = frame.icons and frame.icons[1]
		if icon and icon.charges and icon.charges.GetFont then return icon.charges:GetFont() end
	end
	return getCountFontDefaults()
end

local function getFontOptions(defaultPath)
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
	if defaultPath then add(defaultPath, L["Default"] or "Default") end
	table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return list
end

local function normalizeSoundName(value)
	if type(value) ~= "string" or value == "" then return (Helper and Helper.ENTRY_DEFAULTS and Helper.ENTRY_DEFAULTS.soundReadyFile) or "None" end
	return value
end

local function getSoundLabel(value)
	local soundName = normalizeSoundName(value)
	if soundName == "None" then return L["None"] or _G.NONE or "None" end
	return soundName
end

local function getSoundButtonText(value) return (L["CooldownPanelSound"] or "Sound") .. ": " .. getSoundLabel(value) end

local function getSoundOptions()
	local list = {}
	local seen = {}
	local function add(name)
		if type(name) ~= "string" or name == "" then return end
		local key = string.lower(name)
		if seen[key] then return end
		seen[key] = true
		list[#list + 1] = name
	end
	if LSM and LSM.HashTable then
		for name in pairs(LSM:HashTable("sound") or {}) do
			add(name)
		end
	end
	add((LSM and LSM.DefaultMedia and LSM.DefaultMedia.sound) or nil)
	add((Helper and Helper.ENTRY_DEFAULTS and Helper.ENTRY_DEFAULTS.soundReadyFile) or nil)
	table.sort(list, function(a, b) return tostring(a) < tostring(b) end)
	for i, name in ipairs(list) do
		if name == "None" then
			table.remove(list, i)
			table.insert(list, 1, name)
			break
		end
	end
	return list
end

local function resolveSoundFile(soundName)
	local value = normalizeSoundName(soundName)
	if value == "None" then return nil end
	if LSM and LSM.Fetch then
		local file = LSM:Fetch("sound", value, true)
		if file then return file end
	end
	return value
end

local function playReadySound(soundName)
	if not soundName or soundName == "" then return end
	local numeric = tonumber(soundName)
	if numeric and PlaySound then
		PlaySound(numeric, "Master")
		return
	end
	local file = resolveSoundFile(soundName)
	if file and PlaySoundFile then PlaySoundFile(file, "Master") end
end

local function setExampleCooldown(cooldown)
	if not cooldown then return end
	local setAsPercent = _G.CooldownFrame_SetDisplayAsPercentage
	if setAsPercent then
		setAsPercent(cooldown, EXAMPLE_COOLDOWN_PERCENT)
	elseif cooldown.SetCooldown and GetTime then
		local duration = 100
		cooldown:SetCooldown(GetTime() - (duration * EXAMPLE_COOLDOWN_PERCENT), duration, 1)
	end
end

local function getPreviewCount(panel)
	if not panel or type(panel.order) ~= "table" then return DEFAULT_PREVIEW_COUNT end
	local count = #panel.order
	if count <= 0 then return DEFAULT_PREVIEW_COUNT end
	if count > MAX_PREVIEW_COUNT then return MAX_PREVIEW_COUNT end
	return count
end

local function getEditorPreviewCount(panel, previewFrame, baseLayout)
	if not panel or type(panel.order) ~= "table" then return DEFAULT_PREVIEW_COUNT end
	local count = #panel.order
	if count <= 0 then return DEFAULT_PREVIEW_COUNT end
	if not previewFrame then return count end

	local spacing = clampInt((baseLayout and baseLayout.spacing) or 0, 0, 50, Helper.PANEL_LAYOUT_DEFAULTS.spacing)
	local step = PREVIEW_ICON_SIZE + spacing
	if step <= 0 then return count end
	local width = previewFrame:GetWidth() or 0
	local height = previewFrame:GetHeight() or 0
	if width <= 0 or height <= 0 then return count end

	local cols = math.floor((width + spacing) / step)
	local rows = math.floor((height + spacing) / step)
	if cols < 1 then cols = 1 end
	if rows < 1 then rows = 1 end
	local capacity = cols * rows
	if capacity <= 0 then return count end
	return math.min(count, capacity)
end

local function getEntryIcon(entry)
	if not entry or type(entry) ~= "table" then return PREVIEW_ICON end
	if entry.type == "SPELL" and entry.spellID then return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.spellID)) or PREVIEW_ICON end
	if entry.type == "ITEM" and entry.itemID then
		if GetItemIconByID then
			local icon = GetItemIconByID(entry.itemID)
			if icon then return icon end
		end
		if GetItemInfoInstantFn then
			local _, _, _, _, icon = GetItemInfoInstantFn(entry.itemID)
			if icon then return icon end
		end
	end
	if entry.type == "SLOT" and entry.slotID and GetInventoryItemID then
		local itemID = GetInventoryItemID("player", entry.slotID)
		if itemID then
			if GetItemIconByID then
				local icon = GetItemIconByID(itemID)
				if icon then return icon end
			end
			if GetItemInfoInstantFn then
				local _, _, _, _, icon = GetItemInfoInstantFn(itemID)
				if icon then return icon end
			end
		end
	end
	return PREVIEW_ICON
end

local SLOT_LABELS = {}
local SLOT_MENU_ENTRIES
local SLOT_DEFS = {
	{ name = "HeadSlot", label = _G.HEADSLOT or "Head" },
	{ name = "NeckSlot", label = _G.NECKSLOT or "Neck" },
	{ name = "ShoulderSlot", label = _G.SHOULDERSLOT or "Shoulder" },
	{ name = "BackSlot", label = _G.BACKSLOT or "Back" },
	{ name = "ChestSlot", label = _G.CHESTSLOT or "Chest" },
	{ name = "ShirtSlot", label = _G.SHIRTSLOT or "Shirt" },
	{ name = "TabardSlot", label = _G.TABARDSLOT or "Tabard" },
	{ name = "WristSlot", label = _G.WRISTSLOT or "Wrist" },
	{ name = "HandsSlot", label = _G.HANDSSLOT or "Hands" },
	{ name = "WaistSlot", label = _G.WAISTSLOT or "Waist" },
	{ name = "LegsSlot", label = _G.LEGSSLOT or "Legs" },
	{ name = "FeetSlot", label = _G.FEETSLOT or "Feet" },
	{ name = "Finger0Slot", label = string.format("%s 1", _G.FINGER0SLOT or "Finger") },
	{ name = "Finger1Slot", label = string.format("%s 2", _G.FINGER1SLOT or "Finger") },
	{ name = "Trinket0Slot", label = string.format("%s 1", _G.TRINKET0SLOT or "Trinket") },
	{ name = "Trinket1Slot", label = string.format("%s 2", _G.TRINKET1SLOT or "Trinket") },
	{ name = "MainHandSlot", label = _G.MAINHANDSLOT or "Main Hand" },
	{ name = "SecondaryHandSlot", label = _G.SECONDARYHANDSLOT or "Off Hand" },
	{ name = "RangedSlot", label = _G.RANGEDSLOT or "Ranged" },
}

local function getSlotMenuEntries()
	if SLOT_MENU_ENTRIES then return SLOT_MENU_ENTRIES end
	SLOT_MENU_ENTRIES = {}
	if not GetInventorySlotInfo then return SLOT_MENU_ENTRIES end
	for _, def in ipairs(SLOT_DEFS) do
		local ok, slotId = pcall(GetInventorySlotInfo, def.name)
		if ok and slotId then
			local label = def.label or def.name
			SLOT_LABELS[slotId] = label
			SLOT_MENU_ENTRIES[#SLOT_MENU_ENTRIES + 1] = { id = slotId, label = label }
		end
	end
	return SLOT_MENU_ENTRIES
end

local function getSlotLabel(slotId)
	if not next(SLOT_LABELS) then getSlotMenuEntries() end
	return SLOT_LABELS[slotId] or ("Slot " .. tostring(slotId))
end

local function getSpellName(spellId)
	if not spellId then return nil end
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(spellId)
		if info and info.name then return info.name end
	end
	if GetSpellInfo then
		local name = GetSpellInfo(spellId)
		if name then return name end
	end
	return nil
end

local function getItemName(itemId)
	if not itemId then return nil end
	if C_Item and C_Item.GetItemNameByID then
		local name = C_Item.GetItemNameByID(itemId)
		if name then return name end
	end
	if GetItemInfo then
		local name = GetItemInfo(itemId)
		if name then return name end
	end
	return nil
end

local function getEntryName(entry)
	if not entry then return "" end
	if entry.type == "SPELL" then
		local name = getSpellName(entry.spellID)
		return name or ("Spell " .. tostring(entry.spellID or ""))
	end
	if entry.type == "ITEM" then
		local name = getItemName(entry.itemID)
		return name or ("Item " .. tostring(entry.itemID or ""))
	end
	if entry.type == "SLOT" then return getSlotLabel(entry.slotID) end
	return "Entry"
end

local function getEntryTypeLabel(entryType)
	local key = entryType and tostring(entryType):upper() or nil
	if key == "SPELL" then return _G.STAT_CATEGORY_SPELL or _G.SPELLS or "Spell" end
	if key == "ITEM" then return _G.AUCTION_HOUSE_HEADER_ITEM or _G.ITEMS or "Item" end
	if key == "SLOT" then return L["CooldownPanelSlotType"] or "Slot" end
	return entryType or ""
end

local function isSpellKnownSafe(spellId)
	if not spellId then return false end
	if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
		local known = C_SpellBook.IsSpellInSpellBook(spellId)
		return known and true or false
	end
	return true
end

local function showErrorMessage(msg)
	if UIErrorsFrame and msg then UIErrorsFrame:AddMessage(msg, 1, 0.2, 0.2, 1) end
end

local function ensureRoot()
	if not addon.db then return nil end
	if type(addon.db.cooldownPanels) ~= "table" then
		addon.db.cooldownPanels = Helper.CreateRoot()
	else
		Helper.NormalizeRoot(addon.db.cooldownPanels)
	end
	return addon.db.cooldownPanels
end

function CooldownPanels:EnsureDB() return ensureRoot() end

function CooldownPanels:GetRoot() return ensureRoot() end

function CooldownPanels:GetPanel(panelId)
	local root = ensureRoot()
	if not root then return nil end
	panelId = normalizeId(panelId)
	local panel = root.panels and root.panels[panelId]
	if panel then Helper.NormalizePanel(panel, root.defaults) end
	return panel
end

function CooldownPanels:GetPanelOrder()
	local root = ensureRoot()
	if not root then return nil end
	return root.order
end

function CooldownPanels:SetPanelOrder(order)
	local root = ensureRoot()
	if not root or type(order) ~= "table" then return end
	root.order = order
	Helper.SyncOrder(root.order, root.panels)
end

function CooldownPanels:SetSelectedPanel(panelId)
	local root = ensureRoot()
	if not root then return end
	panelId = normalizeId(panelId)
	if root.panels and root.panels[panelId] then root.selectedPanel = panelId end
end

function CooldownPanels:GetSelectedPanel()
	local root = ensureRoot()
	if not root then return nil end
	return root.selectedPanel
end

function CooldownPanels:CreatePanel(name)
	local root = ensureRoot()
	if not root then return nil end
	local id = Helper.GetNextNumericId(root.panels)
	local panel = Helper.CreatePanel(name, root.defaults)
	panel.id = id
	root.panels[id] = panel
	root.order[#root.order + 1] = id
	if not root.selectedPanel then root.selectedPanel = id end
	self:RegisterEditModePanel(id)
	self:RefreshPanel(id)
	return id, panel
end

function CooldownPanels:DeletePanel(panelId)
	local root = ensureRoot()
	panelId = normalizeId(panelId)
	if not root or not root.panels or not root.panels[panelId] then return end
	root.panels[panelId] = nil
	Helper.SyncOrder(root.order, root.panels)
	if root.selectedPanel == panelId then root.selectedPanel = root.order[1] end
	local runtime = CooldownPanels.runtime and CooldownPanels.runtime[panelId]
	if runtime then
		if runtime.editModeId and EditMode and EditMode.UnregisterFrame then pcall(EditMode.UnregisterFrame, EditMode, runtime.editModeId) end
		if runtime.frame then
			runtime.frame:Hide()
			runtime.frame:SetParent(nil)
			runtime.frame = nil
		end
		CooldownPanels.runtime[panelId] = nil
	end
	self:RebuildSpellIndex()
end

function CooldownPanels:AddEntry(panelId, entryType, idValue, overrides)
	local root = ensureRoot()
	if not root then return nil end
	panelId = normalizeId(panelId)
	local panel = self:GetPanel(panelId)
	if not panel then return nil end
	local typeKey = entryType and tostring(entryType):upper() or nil
	if typeKey ~= "SPELL" and typeKey ~= "ITEM" and typeKey ~= "SLOT" then return nil end
	local numericValue = tonumber(idValue)
	if not numericValue then return nil end
	local entryId = Helper.GetNextNumericId(panel.entries)
	local entry = Helper.CreateEntry(typeKey, numericValue, root.defaults)
	entry.id = entryId
	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			entry[key] = value
		end
	end
	panel.entries[entryId] = entry
	panel.order[#panel.order + 1] = entryId
	self:RebuildSpellIndex()
	self:RefreshPanel(panelId)
	return entryId, entry
end

function CooldownPanels:FindEntryByValue(panelId, entryType, idValue)
	panelId = normalizeId(panelId)
	local panel = self:GetPanel(panelId)
	if not panel then return nil end
	local typeKey = entryType and tostring(entryType):upper() or nil
	local numericValue = tonumber(idValue)
	if typeKey ~= "SPELL" and typeKey ~= "ITEM" and typeKey ~= "SLOT" then return nil end
	for entryId, entry in pairs(panel.entries or {}) do
		if entry and entry.type == typeKey then
			if typeKey == "SPELL" and entry.spellID == numericValue then return entryId, entry end
			if typeKey == "ITEM" and entry.itemID == numericValue then return entryId, entry end
			if typeKey == "SLOT" and entry.slotID == numericValue then return entryId, entry end
		end
	end
	return nil
end

function CooldownPanels:RemoveEntry(panelId, entryId)
	panelId = normalizeId(panelId)
	entryId = normalizeId(entryId)
	local panel = self:GetPanel(panelId)
	if not panel or not panel.entries or not panel.entries[entryId] then return end
	panel.entries[entryId] = nil
	Helper.SyncOrder(panel.order, panel.entries)
	self:RebuildSpellIndex()
	self:RefreshPanel(panelId)
end

function CooldownPanels:RebuildSpellIndex()
	local root = ensureRoot()
	local index = {}
	if root and root.panels then
		for panelId, panel in pairs(root.panels) do
			for _, entry in pairs(panel.entries or {}) do
				if entry and entry.type == "SPELL" and entry.spellID then
					local spellId = tonumber(entry.spellID)
					if spellId then
						index[spellId] = index[spellId] or {}
						index[spellId][panelId] = true
					end
				end
			end
		end
	end
	self.runtime = self.runtime or {}
	self.runtime.spellIndex = index
	return index
end

function CooldownPanels:NormalizeAll()
	local root = ensureRoot()
	if not root then return end
	Helper.NormalizeRoot(root)
	Helper.SyncOrder(root.order, root.panels)
	for panelId, panel in pairs(root.panels) do
		if panel and panel.id == nil then panel.id = panelId end
		Helper.NormalizePanel(panel, root.defaults)
		Helper.SyncOrder(panel.order, panel.entries)
		for entryId, entry in pairs(panel.entries) do
			if entry and entry.id == nil then entry.id = entryId end
			Helper.NormalizeEntry(entry, root.defaults)
		end
	end
	self:RebuildSpellIndex()
end

function CooldownPanels:AddEntrySafe(panelId, entryType, idValue, overrides)
	local typeKey = entryType and tostring(entryType):upper() or nil
	local numericValue = tonumber(idValue)
	if typeKey == "SPELL" and numericValue and not isSpellKnownSafe(numericValue) then
		showErrorMessage(SPELL_FAILED_NOT_KNOWN or "Spell not known.")
		return nil
	end
	if self:FindEntryByValue(panelId, typeKey, numericValue) then
		showErrorMessage(L["CooldownPanelEntry"] and (L["CooldownPanelEntry"] .. " already exists.") or "Entry already exists.")
		return nil
	end
	return self:AddEntry(panelId, typeKey, numericValue, overrides)
end

function CooldownPanels:HandleCursorDrop(panelId)
	panelId = normalizeId(panelId or self:GetSelectedPanel())
	if not panelId then return false end
	local cursorType, cursorId, _, cursorSpellId = GetCursorInfo()
	if not cursorType then return false end

	local added = false
	if cursorType == "spell" then
		local spellId = cursorSpellId or cursorId
		if spellId then added = self:AddEntrySafe(panelId, "SPELL", spellId) ~= nil end
	elseif cursorType == "item" then
		if cursorId then added = self:AddEntrySafe(panelId, "ITEM", cursorId) ~= nil end
	elseif cursorType == "action" and GetActionInfo then
		local actionType, actionId = GetActionInfo(cursorId)
		if actionType == "spell" then
			added = self:AddEntrySafe(panelId, "SPELL", actionId) ~= nil
		elseif actionType == "item" then
			added = self:AddEntrySafe(panelId, "ITEM", actionId) ~= nil
		end
	end

	if added then ClearCursor() end
	return added
end

function CooldownPanels:SelectPanel(panelId)
	local root = ensureRoot()
	if not root then return end
	panelId = normalizeId(panelId)
	if not root.panels or not root.panels[panelId] then return end
	root.selectedPanel = panelId
	local editor = getEditor()
	if editor then
		editor.selectedPanelId = panelId
		editor.selectedEntryId = nil
	end
	self:RefreshEditor()
end

function CooldownPanels:SelectEntry(entryId)
	entryId = normalizeId(entryId)
	local editor = getEditor()
	if not editor then return end
	editor.selectedEntryId = entryId
	self:RefreshEditor()
end

local function showIconTooltip(self)
	if not self or not self._eqolTooltipEnabled then return end
	local entry = self._eqolTooltipEntry
	if not entry or not GameTooltip then return end

	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if entry.type == "SPELL" and entry.spellID and GameTooltip.SetSpellByID then
		GameTooltip:SetSpellByID(entry.spellID)
	elseif entry.type == "ITEM" and entry.itemID and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(entry.itemID)
	elseif entry.type == "SLOT" and entry.slotID then
		local shown = false
		if GameTooltip.SetInventoryItem then shown = GameTooltip:SetInventoryItem("player", entry.slotID) end
		if not shown then GameTooltip:SetText(getSlotLabel(entry.slotID)) end
	else
		return
	end
	GameTooltip:Show()
end

local function hideIconTooltip()
	if GameTooltip then GameTooltip:Hide() end
end

local function applyIconTooltip(icon, entry, enabled)
	if not icon then return end
	icon._eqolTooltipEntry = entry
	local allow = enabled and entry ~= nil
	if icon._eqolTooltipEnabled ~= allow then
		icon._eqolTooltipEnabled = allow
		if icon.EnableMouse then icon:EnableMouse(allow) end
	end
end

local function createIconFrame(parent)
	local icon = CreateFrame("Frame", nil, parent)
	icon:Hide()
	icon:EnableMouse(false)
	icon:SetScript("OnEnter", showIconTooltip)
	icon:SetScript("OnLeave", hideIconTooltip)

	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetAllPoints(icon)

	icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
	icon.cooldown:SetAllPoints(icon)
	icon.cooldown:SetHideCountdownNumbers(true)

	icon.overlay = CreateFrame("Frame", nil, icon)
	icon.overlay:SetAllPoints(icon)
	icon.overlay:SetFrameStrata(icon.cooldown:GetFrameStrata() or icon:GetFrameStrata())
	icon.overlay:SetFrameLevel((icon.cooldown:GetFrameLevel() or icon:GetFrameLevel()) + 5)
	icon.overlay:EnableMouse(false)

	icon.count = icon.overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	icon.count:SetPoint("BOTTOMRIGHT", icon.overlay, "BOTTOMRIGHT", -1, 1)
	icon.count:Hide()

	icon.charges = icon.overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	icon.charges:SetPoint("TOP", icon.overlay, "TOP", 0, -1)
	icon.charges:Hide()

	icon.msqNormal = icon:CreateTexture(nil, "OVERLAY")
	icon.msqNormal:SetAllPoints(icon)
	icon.msqNormal:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	icon.msqNormal:Hide()

	icon.previewGlow = icon:CreateTexture(nil, "OVERLAY")
	icon.previewGlow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	icon.previewGlow:SetVertexColor(1, 0.82, 0.2, 1)
	icon.previewGlow:SetBlendMode("ADD")
	icon.previewGlow:SetAlpha(0.6)
	icon.previewGlow:Hide()

	icon.previewBling = icon:CreateTexture(nil, "OVERLAY")
	icon.previewBling:SetTexture("Interface\\Cooldown\\star4")
	icon.previewBling:SetVertexColor(0.3, 0.6, 1, 0.9)
	icon.previewBling:SetBlendMode("ADD")
	icon.previewBling:Hide()

	icon.previewSoundBorder = CreateFrame("Frame", nil, icon.overlay, "BackdropTemplate")
	icon.previewSoundBorder:SetSize(14, 14)
	icon.previewSoundBorder:SetPoint("TOPRIGHT", icon.overlay, "TOPRIGHT", -1, -1)
	icon.previewSoundBorder:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	icon.previewSoundBorder:SetBackdropColor(0, 0, 0, 0.55)
	icon.previewSoundBorder:SetBackdropBorderColor(0.9, 0.9, 0.9, 0.9)
	icon.previewSoundBorder:Hide()

	icon.previewSound = icon.previewSoundBorder:CreateTexture(nil, "OVERLAY")
	icon.previewSound:SetTexture("Interface\\Common\\VoiceChat-Speaker")
	icon.previewSound:SetSize(12, 12)
	icon.previewSound:SetPoint("CENTER", icon.previewSoundBorder, "CENTER", 0, 0)
	icon.previewSound:SetAlpha(0.95)

	if not (parent and parent._eqolIsPreview) then
		local group = getMasqueGroup()
		if group then
			local regions = {
				Icon = icon.texture,
				Cooldown = icon.cooldown,
				Normal = icon.msqNormal,
			}
			group:AddButton(icon, regions, "Action", true)
			icon._eqolMasqueAdded = true
			icon._eqolMasqueNeedsReskin = true
		end
	end

	return icon
end

local function ensureIconCount(frame, count)
	frame.icons = frame.icons or {}
	for i = 1, count do
		if not frame.icons[i] then frame.icons[i] = createIconFrame(frame) end
		frame.icons[i]:Show()
	end
	for i = count + 1, #frame.icons do
		frame.icons[i]:Hide()
	end
end

local function setGlow(frame, enabled)
	if frame._glow == enabled then return end
	frame._glow = enabled
	local alertManager = _G.ActionButtonSpellAlertManager
	if not alertManager then return end
	if enabled then
		alertManager:ShowAlert(frame)
	else
		alertManager:HideAlert(frame)
	end
end

local function onCooldownDone(self)
	if self and self._eqolSoundReady then
		playReadySound(self._eqolSoundName)
		self._eqolSoundReady = nil
	end
	if CooldownPanels and CooldownPanels.RequestUpdate then CooldownPanels:RequestUpdate() end
end

local function isSafeNumber(value) return type(value) == "number" and (not issecretvalue or not issecretvalue(value)) end

local function isSafeGreaterThan(value, threshold)
	if not isSafeNumber(value) or not isSafeNumber(threshold) then return false end
	return value > threshold
end

local function isSafeLessThan(a, b)
	if not isSafeNumber(a) or not isSafeNumber(b) then return false end
	return a < b
end

local function isSafeNotFalse(value)
	if issecretvalue and issecretvalue(value) then return true end
	return value ~= false
end

local function isCooldownActive(startTime, duration)
	if not isSafeNumber(startTime) or not isSafeNumber(duration) then return false end
	if duration <= 0 or startTime <= 0 then return false end
	if not GetTime then return false end
	return (startTime + duration) > GetTime()
end

local function getDurationRemaining(duration)
	if not duration then return nil end
	local remaining = duration.GetRemainingDuration(duration, DurationModifierRealTime)
	if isSafeNumber(remaining) then return remaining end
	return nil
end

local function getSpellCooldownInfo(spellID)
	if not spellID or not GetSpellCooldownInfo then return 0, 0, false, 1 end
	local a, b, c, d = GetSpellCooldownInfo(spellID)
	if type(a) == "table" then return a.startTime or 0, a.duration or 0, a.isEnabled, a.modRate or 1, a.isOnGCD or nil end
	return a or 0, b or 0, c, d or 1
end

local function getItemCooldownInfo(itemID, slotID)
	if slotID and GetInventoryItemCooldown then
		local start, duration, enabled = GetInventoryItemCooldown("player", slotID)
		if start and duration then return start, duration, enabled end
	end
	if not itemID or not GetItemCooldownFn then return 0, 0, false end
	local start, duration, enabled = GetItemCooldownFn(itemID)
	return start or 0, duration or 0, enabled
end

local function getSpellCooldownDurationObject(spellID)
	if not spellID or not GetSpellCooldownDuration then return nil end
	return GetSpellCooldownDuration(spellID)
end

local function hasItem(itemID)
	if not itemID then return false end
	if IsEquippedItem and IsEquippedItem(itemID) then return true end
	if GetItemCountFn then
		local count = GetItemCountFn(itemID, true)
		if count and count > 0 then return true end
	end
	return false
end

local function itemHasUseSpell(itemID)
	if not itemID or not GetItemSpell then return false end
	local _, spellId = GetItemSpell(itemID)
	return spellId ~= nil
end

local function createPanelFrame(panelId, panel)
	local frame = CreateFrame("Button", "EQOL_CooldownPanel" .. tostring(panelId), UIParent)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame.panelId = panelId
	frame.icons = {}
	frame._eqolPanelFrame = true

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(frame)
	bg:SetColorTexture(0.1, 0.6, 0.6, 0.2)
	bg:Hide()
	frame.bg = bg

	local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("CENTER")
	label:SetText(panel and panel.name or "Cooldown Panel")
	label:Hide()
	frame.label = label

	frame:RegisterForClicks("LeftButtonUp")
	frame:SetScript("OnReceiveDrag", function(self)
		if not (CooldownPanels and CooldownPanels.IsInEditMode and CooldownPanels:IsInEditMode()) then return end
		if CooldownPanels:HandleCursorDrop(self.panelId) then
			CooldownPanels:RefreshPanel(self.panelId)
			if CooldownPanels:IsEditorOpen() then CooldownPanels:RefreshEditor() end
		end
	end)
	frame:SetScript("OnMouseUp", function(self, btn)
		if btn ~= "LeftButton" then return end
		if not (CooldownPanels and CooldownPanels.IsInEditMode and CooldownPanels:IsInEditMode()) then return end
		if CooldownPanels:HandleCursorDrop(self.panelId) then
			CooldownPanels:RefreshPanel(self.panelId)
			if CooldownPanels:IsEditorOpen() then CooldownPanels:RefreshEditor() end
		end
	end)

	return frame
end

local function getGridDimensions(count, wrapCount, primaryHorizontal)
	if count < 1 then count = 1 end
	if wrapCount and wrapCount > 0 then
		if primaryHorizontal then
			local cols = math.min(count, wrapCount)
			local rows = math.floor((count + wrapCount - 1) / wrapCount)
			return cols, rows
		end
		local rows = math.min(count, wrapCount)
		local cols = math.floor((count + wrapCount - 1) / wrapCount)
		return cols, rows
	end
	if primaryHorizontal then return count, 1 end
	return 1, count
end

local function containsId(list, id)
	if type(list) ~= "table" then return false end
	for _, value in ipairs(list) do
		if value == id then return true end
	end
	return false
end

local function setCooldownDrawState(cooldown, drawEdge, drawBling, drawSwipe)
	if not cooldown then return end
	if cooldown.SetDrawEdge and cooldown._eqolDrawEdge ~= drawEdge then
		cooldown:SetDrawEdge(drawEdge)
		cooldown._eqolDrawEdge = drawEdge
	end
	if cooldown.SetDrawBling and cooldown._eqolDrawBling ~= drawBling then
		cooldown:SetDrawBling(drawBling)
		cooldown._eqolDrawBling = drawBling
	end
	if cooldown.SetDrawSwipe and cooldown._eqolDrawSwipe ~= drawSwipe then
		cooldown:SetDrawSwipe(drawSwipe)
		cooldown._eqolDrawSwipe = drawSwipe
	end
end

local function applyIconLayout(frame, count, layout)
	if not frame then return end
	local iconSize = clampInt(layout.iconSize, 12, 128, Helper.PANEL_LAYOUT_DEFAULTS.iconSize)
	local spacing = clampInt(layout.spacing, 0, 50, Helper.PANEL_LAYOUT_DEFAULTS.spacing)
	local direction = normalizeDirection(layout.direction, Helper.PANEL_LAYOUT_DEFAULTS.direction)
	local wrapCount = clampInt(layout.wrapCount, 0, 40, Helper.PANEL_LAYOUT_DEFAULTS.wrapCount or 0)
	local wrapDirection = normalizeDirection(layout.wrapDirection, Helper.PANEL_LAYOUT_DEFAULTS.wrapDirection or "DOWN")
	local primaryHorizontal = direction == "LEFT" or direction == "RIGHT"
	local stackAnchor = normalizeAnchor(layout.stackAnchor, Helper.PANEL_LAYOUT_DEFAULTS.stackAnchor)
	local stackX = clampInt(layout.stackX, -OFFSET_RANGE, OFFSET_RANGE, Helper.PANEL_LAYOUT_DEFAULTS.stackX)
	local stackY = clampInt(layout.stackY, -OFFSET_RANGE, OFFSET_RANGE, Helper.PANEL_LAYOUT_DEFAULTS.stackY)
	local chargesAnchor = normalizeAnchor(layout.chargesAnchor, Helper.PANEL_LAYOUT_DEFAULTS.chargesAnchor)
	local chargesX = clampInt(layout.chargesX, -OFFSET_RANGE, OFFSET_RANGE, Helper.PANEL_LAYOUT_DEFAULTS.chargesX)
	local chargesY = clampInt(layout.chargesY, -OFFSET_RANGE, OFFSET_RANGE, Helper.PANEL_LAYOUT_DEFAULTS.chargesY)
	local drawEdge = layout.cooldownDrawEdge ~= false
	local drawBling = layout.cooldownDrawBling ~= false
	local drawSwipe = layout.cooldownDrawSwipe ~= false

	local cols, rows = getGridDimensions(count, wrapCount, primaryHorizontal)
	local step = iconSize + spacing
	local width = (cols * iconSize) + ((cols - 1) * spacing)
	local height = (rows * iconSize) + ((rows - 1) * spacing)

	frame:SetSize(width > 0 and width or iconSize, height > 0 and height or iconSize)
	ensureIconCount(frame, count)
	local fontPath, fontSize, fontStyle = getCountFontDefaults(frame)
	local countFontPath = resolveFontPath(layout.stackFont, fontPath)
	local countFontSize = clampInt(layout.stackFontSize, 6, 64, fontSize or 12)
	local countFontStyle = normalizeFontStyle(layout.stackFontStyle, fontStyle)
	local chargesFontPath, chargesFontSize, chargesFontStyle = getChargesFontDefaults(frame)
	local chargesPath = resolveFontPath(layout.chargesFont, chargesFontPath)
	local chargesSize = clampInt(layout.chargesFontSize, 6, 64, chargesFontSize or 12)
	local chargesStyle = normalizeFontStyle(layout.chargesFontStyle, chargesFontStyle)

	for i = 1, count do
		local icon = frame.icons[i]
		local primaryIndex = i - 1
		local secondaryIndex = 0
		if wrapCount and wrapCount > 0 then
			primaryIndex = (i - 1) % wrapCount
			secondaryIndex = math.floor((i - 1) / wrapCount)
		end

		local col, row
		if primaryHorizontal then
			col = primaryIndex
			row = secondaryIndex
		else
			row = primaryIndex
			col = secondaryIndex
		end

		if primaryHorizontal and direction == "LEFT" then
			col = (cols - 1) - col
		elseif (not primaryHorizontal) and direction == "UP" then
			row = (rows - 1) - row
		end

		if primaryHorizontal then
			if wrapDirection == "UP" then row = (rows - 1) - row end
		else
			if wrapDirection == "LEFT" then col = (cols - 1) - col end
		end

		icon:SetSize(iconSize, iconSize)
		if icon._eqolMasqueNeedsReskin then
			local group = getMasqueGroup()
			if group and group.ReSkin then group:ReSkin(icon) end
			icon._eqolMasqueNeedsReskin = nil
		end
		if icon.count then
			icon.count:ClearAllPoints()
			icon.count:SetPoint(stackAnchor, icon, stackAnchor, stackX, stackY)
			icon.count:SetFont(countFontPath, countFontSize, countFontStyle)
		end
		if icon.charges then
			icon.charges:ClearAllPoints()
			icon.charges:SetPoint(chargesAnchor, icon, chargesAnchor, chargesX, chargesY)
			icon.charges:SetFont(chargesPath, chargesSize, chargesStyle)
		end
		setCooldownDrawState(icon.cooldown, drawEdge, drawBling, drawSwipe)
		if icon.previewGlow then
			icon.previewGlow:ClearAllPoints()
			icon.previewGlow:SetPoint("CENTER", icon, "CENTER", 0, 0)
			icon.previewGlow:SetSize(iconSize * 1.8, iconSize * 1.8)
		end
		if icon.previewBling then
			icon.previewBling:ClearAllPoints()
			icon.previewBling:SetPoint("CENTER", icon, "CENTER", 0, 0)
			icon.previewBling:SetSize(iconSize * 1.5, iconSize * 1.5)
		end
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", frame, "TOPLEFT", col * step, -row * step)
	end
end

local function applyPanelBorder(frame)
	local borderLayer, borderSubLevel = "BORDER", 0
	local borderPath = "Interface\\AddOns\\EnhanceQoL\\Assets\\PanelBorder_"
	local cornerSize = 70
	local edgeThickness = 70
	local cornerOffsets = 13

	local function makeTex(key, layer, subLevel)
		local tex = frame:CreateTexture(nil, layer or borderLayer, nil, subLevel or borderSubLevel)
		tex:SetTexture(borderPath .. key .. ".tga")
		tex:SetAlpha(0.95)
		return tex
	end

	local tl = makeTex("tl", borderLayer, borderSubLevel + 1)
	tl:SetSize(cornerSize, cornerSize)
	tl:SetPoint("TOPLEFT", frame, "TOPLEFT", -cornerOffsets, cornerOffsets)

	local tr = makeTex("tr", borderLayer, borderSubLevel + 1)
	tr:SetSize(cornerSize, cornerSize)
	tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", cornerOffsets + 8, cornerOffsets)

	local bl = makeTex("bl", borderLayer, borderSubLevel + 1)
	bl:SetSize(cornerSize, cornerSize)
	bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -cornerOffsets, -cornerOffsets)

	local br = makeTex("br", borderLayer, borderSubLevel + 1)
	br:SetSize(cornerSize, cornerSize)
	br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", cornerOffsets + 8, -cornerOffsets)

	local top = makeTex("t", borderLayer, borderSubLevel)
	top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
	top:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0)
	top:SetHeight(edgeThickness)
	top:SetHorizTile(true)

	local bottom = makeTex("b", borderLayer, borderSubLevel)
	bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT", 0, 0)
	bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
	bottom:SetHeight(edgeThickness)
	bottom:SetHorizTile(true)

	local left = makeTex("l", borderLayer, borderSubLevel)
	left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT", 0, 0)
	left:SetWidth(edgeThickness)
	left:SetVertTile(true)

	local right = makeTex("r", borderLayer, borderSubLevel)
	right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0)
	right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
	right:SetWidth(edgeThickness)
	right:SetVertTile(true)
end

local function applyInsetBorder(frame, offset)
	if not frame then return end
	offset = offset or 10

	local layer, subLevel = "BORDER", 2
	local path = "Interface\\AddOns\\EnhanceQoL\\Assets\\border_round_"
	local cornerSize = 36
	local edgeSize = 36

	frame.eqolInsetParts = frame.eqolInsetParts or {}
	local parts = frame.eqolInsetParts

	local function tex(name)
		if not parts[name] then parts[name] = frame:CreateTexture(nil, layer, nil, subLevel) end
		local t = parts[name]
		t:SetAlpha(0.7)
		t:SetTexture(path .. name .. ".tga")
		t:SetDrawLayer(layer, subLevel)
		return t
	end

	local tl = tex("tl")
	tl:SetSize(cornerSize, cornerSize)
	tl:ClearAllPoints()
	tl:SetPoint("TOPLEFT", frame, "TOPLEFT", offset, -offset)

	local tr = tex("tr")
	tr:SetSize(cornerSize, cornerSize)
	tr:ClearAllPoints()
	tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -offset, -offset)

	local bl = tex("bl")
	bl:SetSize(cornerSize, cornerSize)
	bl:ClearAllPoints()
	bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", offset, offset)

	local br = tex("br")
	br:SetSize(cornerSize, cornerSize)
	br:ClearAllPoints()
	br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -offset, offset)

	local top = tex("t")
	top:ClearAllPoints()
	top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
	top:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0)
	top:SetHeight(edgeSize)
	top:SetHorizTile(true)

	local bottom = tex("b")
	bottom:ClearAllPoints()
	bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT", 0, 0)
	bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
	bottom:SetHeight(edgeSize)
	bottom:SetHorizTile(true)

	local left = tex("l")
	left:ClearAllPoints()
	left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT", 0, 0)
	left:SetWidth(edgeSize)
	left:SetVertTile(true)

	local right = tex("r")
	right:ClearAllPoints()
	right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0)
	right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
	right:SetWidth(edgeSize)
	right:SetVertTile(true)
end

local function createLabel(parent, text, size, style)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetText(text or "")
	label:SetFont((addon.variables and addon.variables.defaultFont) or label:GetFont(), size or 12, style or "OUTLINE")
	label:SetTextColor(1, 0.82, 0, 1)
	return label
end

local function createButton(parent, text, width, height)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetText(text or "")
	btn:SetSize(width or 120, height or 22)
	return btn
end

local function createEditBox(parent, width, height)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width or 120, height or 22)
	box:SetAutoFocus(false)
	box:SetFontObject(GameFontHighlightSmall)
	return box
end

local function createCheck(parent, text)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb.Text:SetText(text or "")
	cb.Text:SetTextColor(1, 1, 1, 1)
	return cb
end

local function createSlider(parent, width, minValue, maxValue, step)
	local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
	slider:SetMinMaxValues(minValue or 0, maxValue or 1)
	slider:SetValueStep(step or 1)
	slider:SetObeyStepOnDrag(true)
	slider:SetWidth(width or 180)
	if slider.Low then slider.Low:SetText(tostring(minValue or 0)) end
	if slider.High then slider.High:SetText(tostring(maxValue or 1)) end
	return slider
end

local function createRowButton(parent, height)
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

local function showEditorDragIcon(editor, texture)
	if not editor then return end
	if not editor.dragIcon then
		local frame = CreateFrame("Frame", nil, UIParent)
		frame:SetSize(34, 34)
		frame:SetFrameStrata("TOOLTIP")
		frame.texture = frame:CreateTexture(nil, "OVERLAY")
		frame.texture:SetAllPoints()
		editor.dragIcon = frame
	end
	editor.dragIcon.texture:SetTexture(texture or PREVIEW_ICON)
	editor.dragIcon:SetScript("OnUpdate", function(f)
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		f:ClearAllPoints()
		f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	end)
	editor.dragIcon:Show()
end

local function hideEditorDragIcon(editor)
	if not editor or not editor.dragIcon then return end
	editor.dragIcon:SetScript("OnUpdate", nil)
	editor.dragIcon:Hide()
end

local function showSlotMenu(owner, panelId)
	if not panelId or not MenuUtil or not MenuUtil.CreateContextMenu then return end
	local entries = getSlotMenuEntries()
	if not entries or #entries == 0 then return end
	MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
		rootDescription:SetTag("MENU_EQOL_COOLDOWN_PANEL_SLOTS")
		rootDescription:CreateTitle(L["CooldownPanelAddSlot"] or "Add Slot")
		for _, slot in ipairs(entries) do
			rootDescription:CreateButton(slot.label, function()
				CooldownPanels:AddEntrySafe(panelId, "SLOT", slot.id)
				CooldownPanels:RefreshEditor()
			end)
		end
	end)
end

local function showSoundMenu(owner, panelId, entryId)
	if not panelId or not entryId or not MenuUtil or not MenuUtil.CreateContextMenu then return end
	local panel = CooldownPanels:GetPanel(panelId)
	local entry = panel and panel.entries and panel.entries[entryId]
	if not entry then return end
	local options = getSoundOptions()
	if not options or #options == 0 then return end
	MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
		rootDescription:SetTag("MENU_EQOL_COOLDOWN_PANEL_SOUND")
		if rootDescription.SetScrollMode then rootDescription:SetScrollMode(260) end
		rootDescription:CreateTitle(L["CooldownPanelSoundReady"] or "Sound when ready")
		for _, soundName in ipairs(options) do
			local label = getSoundLabel(soundName)
			rootDescription:CreateRadio(label, function() return normalizeSoundName(entry.soundReadyFile) == soundName end, function()
				entry.soundReadyFile = soundName
				playReadySound(soundName)
				CooldownPanels:RefreshPanel(panelId)
				CooldownPanels:RefreshEditor()
			end)
		end
	end)
end

getEditor = function()
	local runtime = CooldownPanels.runtime and CooldownPanels.runtime["editor"]
	return runtime and runtime.editor or nil
end

local function applyEditorPosition(frame)
	if not frame or not addon or not addon.db then return end
	local point = addon.db.cooldownPanelsEditorPoint
	local x = addon.db.cooldownPanelsEditorX
	local y = addon.db.cooldownPanelsEditorY
	if not point or x == nil or y == nil then return end
	frame:ClearAllPoints()
	frame:SetPoint(point, UIParent, point, x, y)
end

local function saveEditorPosition(frame)
	if not frame or not addon or not addon.db then return end
	local point, _, _, x, y = frame:GetPoint()
	if not point or x == nil or y == nil then return end
	addon.db.cooldownPanelsEditorPoint = point
	addon.db.cooldownPanelsEditorX = x
	addon.db.cooldownPanelsEditorY = y
end

local ensureDeletePopup

local function ensureEditor()
	local runtime = getRuntime("editor")
	if runtime.editor then return runtime.editor end

	local frame = CreateFrame("Frame", "EQOL_CooldownPanelsEditor", UIParent, "BackdropTemplate")
	frame:SetSize(980, 560)
	frame:SetPoint("CENTER")
	applyEditorPosition(frame)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetFrameStrata("DIALOG")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		saveEditorPosition(self)
	end)
	frame:Hide()

	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
	frame.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 10)
	frame.bg:SetTexture("Interface\\AddOns\\EnhanceQoL\\Assets\\background_dark.tga")
	frame.bg:SetAlpha(0.9)
	applyPanelBorder(frame)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -12)
	frame.title:SetText(L["CooldownPanelEditor"] or "Cooldown Panel Editor")
	frame.title:SetFont((addon.variables and addon.variables.defaultFont) or frame.title:GetFont(), 16, "OUTLINE")

	frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.subtitle:SetPoint("TOP", frame, "TOP", 0, -12)
	frame.subtitle:SetJustifyH("CENTER")
	frame.subtitle:SetText(L["CooldownPanelEditModeHeader"] or "Configure the Panels in Edit Mode")
	frame.subtitle:SetTextColor(0.8, 0.8, 0.8, 1)

	frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 20, 13)

	local left = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	left:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -44)
	left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
	left:SetWidth(220)
	left.bg = left:CreateTexture(nil, "BACKGROUND")
	left.bg:SetAllPoints(left)
	left.bg:SetTexture("Interface\\AddOns\\EnhanceQoL\\Assets\\background_gray.tga")
	left.bg:SetAlpha(0.85)
	applyInsetBorder(left, -4)
	frame.left = left

	local panelTitle = createLabel(left, L["CooldownPanelPanels"] or "Panels", 12, "OUTLINE")
	panelTitle:SetPoint("TOPLEFT", left, "TOPLEFT", 12, -12)

	local panelScroll = CreateFrame("ScrollFrame", nil, left, "UIPanelScrollFrameTemplate")
	panelScroll:SetPoint("TOPLEFT", panelTitle, "BOTTOMLEFT", 0, -8)
	panelScroll:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -26, 44)
	local panelContent = CreateFrame("Frame", nil, panelScroll)
	panelContent:SetSize(1, 1)
	panelScroll:SetScrollChild(panelContent)
	panelContent:SetWidth(panelScroll:GetWidth() or 1)
	panelScroll:SetScript("OnSizeChanged", function(self) panelContent:SetWidth(self:GetWidth() or 1) end)

	local addPanel = createButton(left, L["CooldownPanelAddPanel"] or "Add Panel", 96, 22)
	addPanel:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 12, 12)

	local deletePanel = createButton(left, L["CooldownPanelDeletePanel"] or "Delete Panel", 96, 22)
	deletePanel:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -12, 12)

	local right = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -44)
	right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
	right:SetWidth(260)
	right.bg = right:CreateTexture(nil, "BACKGROUND")
	right.bg:SetAllPoints(right)
	right.bg:SetTexture("Interface\\AddOns\\EnhanceQoL\\Assets\\background_gray.tga")
	right.bg:SetAlpha(0.85)
	applyInsetBorder(right, -4)
	frame.right = right

	local panelHeader = createLabel(right, L["CooldownPanelPanels"] or "Panels", 12, "OUTLINE")
	panelHeader:SetPoint("TOPLEFT", right, "TOPLEFT", 12, -12)
	panelHeader:SetTextColor(0.9, 0.9, 0.9, 1)

	local panelNameLabel = createLabel(right, L["CooldownPanelPanelName"] or "Panel name", 11, "OUTLINE")
	panelNameLabel:SetPoint("TOPLEFT", panelHeader, "BOTTOMLEFT", 0, -8)
	panelNameLabel:SetTextColor(0.9, 0.9, 0.9, 1)

	local panelNameBox = createEditBox(right, 200, 20)
	panelNameBox:SetPoint("TOPLEFT", panelNameLabel, "BOTTOMLEFT", 0, -4)

	local panelEnabled = createCheck(right, L["CooldownPanelEnabled"] or "Enabled")
	panelEnabled:SetPoint("TOPLEFT", panelNameBox, "BOTTOMLEFT", -2, -6)

	local entryHeader = createLabel(right, L["CooldownPanelEntry"] or "Entry", 12, "OUTLINE")
	entryHeader:SetPoint("TOPLEFT", panelEnabled, "BOTTOMLEFT", 2, -16)
	entryHeader:SetTextColor(0.9, 0.9, 0.9, 1)

	local entryIcon = right:CreateTexture(nil, "ARTWORK")
	entryIcon:SetSize(36, 36)
	entryIcon:SetPoint("TOPLEFT", entryHeader, "BOTTOMLEFT", 0, -6)
	entryIcon:SetTexture(PREVIEW_ICON)

	local entryName = right:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	entryName:SetPoint("LEFT", entryIcon, "RIGHT", 8, 8)
	entryName:SetWidth(180)
	entryName:SetJustifyH("LEFT")
	entryName:SetTextColor(1, 1, 1, 1)

	local entryType = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	entryType:SetPoint("TOPLEFT", entryName, "BOTTOMLEFT", 0, -2)
	entryType:SetJustifyH("LEFT")

	local entryIdBox = createEditBox(right, 120, 20)
	entryIdBox:SetPoint("TOPLEFT", entryIcon, "BOTTOMLEFT", 0, -8)
	entryIdBox:SetNumeric(true)

	local cbCooldownText = createCheck(right, L["CooldownPanelShowCooldownText"] or "Show cooldown text")
	cbCooldownText:SetPoint("TOPLEFT", entryIdBox, "BOTTOMLEFT", -2, -6)

	local cbCharges = createCheck(right, L["CooldownPanelShowCharges"] or "Show charges")
	cbCharges:SetPoint("TOPLEFT", cbCooldownText, "BOTTOMLEFT", 0, -4)

	local cbStacks = createCheck(right, L["CooldownPanelShowStacks"] or "Show stack count")
	cbStacks:SetPoint("TOPLEFT", cbCharges, "BOTTOMLEFT", 0, -4)

	local cbItemCount = createCheck(right, L["CooldownPanelShowItemCount"] or "Show item count")
	cbItemCount:SetPoint("TOPLEFT", cbCooldownText, "BOTTOMLEFT", 0, -4)

	local cbShowWhenEmpty = createCheck(right, L["CooldownPanelShowWhenEmpty"] or "Show when empty")
	cbShowWhenEmpty:SetPoint("TOPLEFT", cbItemCount, "BOTTOMLEFT", 0, -4)

	local cbShowWhenNoCooldown = createCheck(right, L["CooldownPanelShowWhenNoCooldown"] or "Show even without cooldown")
	cbShowWhenNoCooldown:SetPoint("TOPLEFT", cbShowWhenEmpty, "BOTTOMLEFT", 0, -4)

	local cbGlow = createCheck(right, L["CooldownPanelGlowReady"] or "Glow when ready")
	cbGlow:SetPoint("TOPLEFT", cbStacks, "BOTTOMLEFT", 0, -4)

	local glowDuration = createSlider(right, 180, 0, 30, 1)
	glowDuration:SetPoint("TOPLEFT", cbGlow, "BOTTOMLEFT", 18, -8)

	local cbSound = createCheck(right, L["CooldownPanelSoundReady"] or "Sound when ready")
	cbSound:SetPoint("TOPLEFT", glowDuration, "BOTTOMLEFT", -18, -6)

	local soundButton = createButton(right, "", 180, 20)
	soundButton:SetPoint("TOPLEFT", cbSound, "BOTTOMLEFT", 18, -6)

	local removeEntry = createButton(right, L["CooldownPanelRemoveEntry"] or "Remove entry", 180, 22)
	removeEntry:SetPoint("BOTTOM", right, "BOTTOM", 0, 14)

	local middle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	middle:SetPoint("TOPLEFT", left, "TOPRIGHT", 16, 0)
	middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", -16, 0)
	middle.bg = middle:CreateTexture(nil, "BACKGROUND")
	middle.bg:SetAllPoints(middle)
	middle.bg:SetTexture("Interface\\AddOns\\EnhanceQoL\\Assets\\background_gray.tga")
	middle.bg:SetAlpha(0.85)
	applyInsetBorder(middle, -4)
	frame.middle = middle

	local previewTitle = createLabel(middle, L["CooldownPanelPreview"] or "Preview", 12, "OUTLINE")
	previewTitle:SetPoint("TOPLEFT", middle, "TOPLEFT", 12, -12)

	local previewFrame = CreateFrame("Frame", nil, middle, "BackdropTemplate")
	previewFrame:SetPoint("TOPLEFT", middle, "TOPLEFT", 12, -36)
	previewFrame:SetPoint("TOPRIGHT", middle, "TOPRIGHT", -12, -36)
	previewFrame:SetHeight(190)
	previewFrame:SetClipsChildren(true)
	previewFrame.bg = previewFrame:CreateTexture(nil, "BACKGROUND")
	previewFrame.bg:SetAllPoints(previewFrame)
	previewFrame.bg:SetColorTexture(0, 0, 0, 0.3)
	applyInsetBorder(previewFrame, -6)

	local previewCanvas = CreateFrame("Frame", nil, previewFrame)
	previewCanvas._eqolIsPreview = true
	previewCanvas:SetPoint("CENTER", previewFrame, "CENTER")
	previewFrame.canvas = previewCanvas

	local previewHint = previewFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	previewHint:SetPoint("CENTER", previewFrame, "CENTER")
	previewHint:SetText(L["CooldownPanelDropHint"] or "Drop spells or items here")
	previewHint:SetTextColor(0.7, 0.7, 0.7, 1)
	previewFrame.dropHint = previewHint

	local dropZone = CreateFrame("Button", nil, previewFrame)
	dropZone:SetAllPoints(previewFrame)
	dropZone:RegisterForClicks("LeftButtonUp")
	dropZone:SetScript("OnReceiveDrag", function()
		if CooldownPanels:HandleCursorDrop(runtime.editor and runtime.editor.selectedPanelId) then CooldownPanels:RefreshEditor() end
	end)
	dropZone:SetScript("OnMouseUp", function(_, btn)
		if btn == "LeftButton" then
			if CooldownPanels:HandleCursorDrop(runtime.editor and runtime.editor.selectedPanelId) then CooldownPanels:RefreshEditor() end
		end
	end)
	dropZone.highlight = dropZone:CreateTexture(nil, "HIGHLIGHT")
	dropZone.highlight:SetAllPoints(dropZone)
	dropZone.highlight:SetColorTexture(0.2, 0.6, 0.6, 0.15)
	previewFrame.dropZone = dropZone
	local previewHintLabel = middle:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	previewHintLabel:SetPoint("BOTTOMRIGHT", previewFrame, "TOPRIGHT", -2, 6)
	previewHintLabel:SetJustifyH("RIGHT")
	previewHintLabel:SetText(L["CooldownPanelPreviewHint"] or "Drag spells/items here to add")

	local entryTitle = createLabel(middle, L["CooldownPanelEntries"] or "Entries", 12, "OUTLINE")
	entryTitle:SetPoint("TOPLEFT", previewFrame, "BOTTOMLEFT", 0, -12)

	local entryScroll = CreateFrame("ScrollFrame", nil, middle, "UIPanelScrollFrameTemplate")
	entryScroll:SetPoint("TOPLEFT", entryTitle, "BOTTOMLEFT", 0, -8)
	entryScroll:SetPoint("BOTTOMRIGHT", middle, "BOTTOMRIGHT", -26, 80)
	local entryContent = CreateFrame("Frame", nil, entryScroll)
	entryContent:SetSize(1, 1)
	entryScroll:SetScrollChild(entryContent)
	entryContent:SetWidth(entryScroll:GetWidth() or 1)
	entryScroll:SetScript("OnSizeChanged", function(self) entryContent:SetWidth(self:GetWidth() or 1) end)

	local entryHint = middle:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	entryHint:SetPoint("BOTTOMRIGHT", entryScroll, "TOPRIGHT", -2, 6)
	entryHint:SetJustifyH("RIGHT")
	entryHint:SetText(L["CooldownPanelEntriesHint"] or "Drag entries to reorder")

	local addSpellLabel = createLabel(middle, L["CooldownPanelAddSpellID"] or "Add Spell ID", 11, "OUTLINE")
	addSpellLabel:SetPoint("BOTTOMLEFT", middle, "BOTTOMLEFT", 12, 46)
	addSpellLabel:SetTextColor(0.9, 0.9, 0.9, 1)

	local addSpellBox = createEditBox(middle, 80, 20)
	addSpellBox:SetPoint("LEFT", addSpellLabel, "RIGHT", 6, 0)
	addSpellBox:SetNumeric(true)

	local addItemLabel = createLabel(middle, L["CooldownPanelAddItemID"] or "Add Item ID", 11, "OUTLINE")
	addItemLabel:SetPoint("BOTTOMLEFT", middle, "BOTTOMLEFT", 12, 20)
	addItemLabel:SetTextColor(0.9, 0.9, 0.9, 1)

	local addItemBox = createEditBox(middle, 80, 20)
	addItemBox:SetPoint("LEFT", addItemLabel, "RIGHT", 6, 0)
	addItemBox:SetNumeric(true)

	local editModeButton = createButton(middle, _G.HUD_EDIT_MODE_MENU or L["CooldownPanelEditModeButton"] or "Edit Mode", 110, 20)
	editModeButton:SetPoint("LEFT", addItemBox, "RIGHT", 12, 0)

	local slotButton = createButton(middle, L["CooldownPanelAddSlot"] or "Add Slot", 120, 20)
	slotButton:SetPoint("LEFT", editModeButton, "RIGHT", 12, 0)

	local function updateEditModeButton()
		if not editModeButton then return end
		if InCombatLockdown and InCombatLockdown() or addon.functions.isRestrictedContent() then
			editModeButton:Disable()
		else
			editModeButton:Enable()
		end
	end

	editModeButton:SetScript("OnClick", function()
		if InCombatLockdown and InCombatLockdown() or addon.functions.isRestrictedContent() then return end
		if EditModeManagerFrame and ShowUIPanel then ShowUIPanel(EditModeManagerFrame) end
	end)

	frame:SetScript("OnShow", function()
		frame:RegisterEvent("PLAYER_REGEN_DISABLED")
		frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		updateEditModeButton()
		CooldownPanels:RefreshEditor()
	end)
	frame:SetScript("OnHide", function()
		frame:UnregisterEvent("PLAYER_REGEN_DISABLED")
		frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
		saveEditorPosition(frame)
		if runtime and runtime.editor then
			hideEditorDragIcon(runtime.editor)
			runtime.editor.draggingEntry = nil
			runtime.editor.dragEntryId = nil
			runtime.editor.dragTargetId = nil
		end
	end)
	frame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then updateEditModeButton() end
	end)

	runtime.editor = {
		frame = frame,
		selectedPanelId = nil,
		selectedEntryId = nil,
		panelRows = {},
		entryRows = {},
		panelList = { scroll = panelScroll, content = panelContent },
		entryList = { scroll = entryScroll, content = entryContent },
		previewFrame = previewFrame,
		previewHintLabel = previewHintLabel,
		addPanel = addPanel,
		deletePanel = deletePanel,
		addSpellBox = addSpellBox,
		addItemBox = addItemBox,
		slotButton = slotButton,
		inspector = {
			panelName = panelNameBox,
			panelEnabled = panelEnabled,
			entryIcon = entryIcon,
			entryName = entryName,
			entryType = entryType,
			entryId = entryIdBox,
			cbCooldownText = cbCooldownText,
			cbCharges = cbCharges,
			cbStacks = cbStacks,
			cbItemCount = cbItemCount,
			cbShowWhenEmpty = cbShowWhenEmpty,
			cbShowWhenNoCooldown = cbShowWhenNoCooldown,
			cbGlow = cbGlow,
			cbSound = cbSound,
			glowDuration = glowDuration,
			soundButton = soundButton,
			removeEntry = removeEntry,
		},
	}

	local editor = runtime.editor

	addPanel:SetScript("OnClick", function()
		local newName = L["CooldownPanelNewPanel"] or "New Panel"
		local panelId = CooldownPanels:CreatePanel(newName)
		if panelId then CooldownPanels:SelectPanel(panelId) end
	end)

	deletePanel:SetScript("OnClick", function()
		local panelId = editor.selectedPanelId
		if not panelId then return end
		local panel = CooldownPanels:GetPanel(panelId)
		ensureDeletePopup()
		StaticPopup_Show("EQOL_COOLDOWN_PANEL_DELETE", panel and panel.name or nil, nil, { panelId = panelId })
	end)

	addSpellBox:SetScript("OnEnterPressed", function(self)
		local panelId = editor.selectedPanelId
		local value = tonumber(self:GetText())
		if panelId and value then CooldownPanels:AddEntrySafe(panelId, "SPELL", value) end
		self:SetText("")
		self:ClearFocus()
		CooldownPanels:RefreshEditor()
	end)

	addItemBox:SetScript("OnEnterPressed", function(self)
		local panelId = editor.selectedPanelId
		local value = tonumber(self:GetText())
		if panelId and value then CooldownPanels:AddEntrySafe(panelId, "ITEM", value) end
		self:SetText("")
		self:ClearFocus()
		CooldownPanels:RefreshEditor()
	end)

	slotButton:SetScript("OnClick", function(self) showSlotMenu(self, editor.selectedPanelId) end)

	panelNameBox:SetScript("OnEnterPressed", function(self)
		local panelId = editor.selectedPanelId
		local panel = panelId and CooldownPanels:GetPanel(panelId)
		local text = self:GetText()
		if panel and text and text ~= "" then
			panel.name = text
			CooldownPanels:RefreshPanel(panelId)
			local runtimePanel = CooldownPanels.runtime and CooldownPanels.runtime[panelId]
			if runtimePanel and runtimePanel.editModeId and EditMode and EditMode.RefreshFrame then EditMode:RefreshFrame(runtimePanel.editModeId) end
		end
		self:ClearFocus()
		CooldownPanels:RefreshEditor()
	end)
	panelNameBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		CooldownPanels:RefreshEditor()
	end)

	panelEnabled:SetScript("OnClick", function(self)
		local panelId = editor.selectedPanelId
		local panel = panelId and CooldownPanels:GetPanel(panelId)
		if panel then
			panel.enabled = self:GetChecked() and true or false
			CooldownPanels:RefreshPanel(panelId)
			CooldownPanels:RefreshEditor()
		end
	end)

	entryIdBox:SetScript("OnEnterPressed", function(self)
		local panelId = editor.selectedPanelId
		local entryId = editor.selectedEntryId
		local panel = panelId and CooldownPanels:GetPanel(panelId)
		local entry = panel and panel.entries and panel.entries[entryId]
		local value = tonumber(self:GetText())
		if not panel or not entry or not value then
			self:ClearFocus()
			CooldownPanels:RefreshEditor()
			return
		end
		if entry.type == "SPELL" and not isSpellKnownSafe(value) then
			showErrorMessage(SPELL_FAILED_NOT_KNOWN or "Spell not known.")
			self:ClearFocus()
			CooldownPanels:RefreshEditor()
			return
		end
		local existingId = CooldownPanels:FindEntryByValue(panelId, entry.type, value)
		if existingId and existingId ~= entryId then
			showErrorMessage("Entry already exists.")
			self:ClearFocus()
			CooldownPanels:RefreshEditor()
			return
		end
		if entry.type == "SPELL" then
			entry.spellID = value
		elseif entry.type == "ITEM" then
			entry.itemID = value
		elseif entry.type == "SLOT" then
			entry.slotID = value
		end
		self:ClearFocus()
		CooldownPanels:RebuildSpellIndex()
		CooldownPanels:RefreshPanel(panelId)
		CooldownPanels:RefreshEditor()
	end)
	entryIdBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		CooldownPanels:RefreshEditor()
	end)

	local function bindEntryToggle(cb, field)
		cb:SetScript("OnClick", function(self)
			local panelId = editor.selectedPanelId
			local entryId = editor.selectedEntryId
			local panel = panelId and CooldownPanels:GetPanel(panelId)
			local entry = panel and panel.entries and panel.entries[entryId]
			if not entry then return end
			entry[field] = self:GetChecked() and true or false
			CooldownPanels:RefreshPanel(panelId)
			CooldownPanels:RefreshEditor()
		end)
	end

	local function bindEntrySlider(slider, field, minValue, maxValue)
		slider:SetScript("OnValueChanged", function(self, value)
			if self._suspend then return end
			local panelId = editor.selectedPanelId
			local entryId = editor.selectedEntryId
			local panel = panelId and CooldownPanels:GetPanel(panelId)
			local entry = panel and panel.entries and panel.entries[entryId]
			if not entry then return end
			local clamped = clampInt(value, minValue, maxValue, entry[field] or 0)
			entry[field] = clamped
			if self.Text then self.Text:SetText((L["CooldownPanelGlowDuration"] or "Glow duration") .. ": " .. tostring(clamped) .. "s") end
			CooldownPanels:RefreshPanel(panelId)
		end)
	end

	bindEntryToggle(cbCharges, "showCharges")
	bindEntryToggle(cbStacks, "showStacks")
	bindEntryToggle(cbCooldownText, "showCooldownText")
	bindEntryToggle(cbItemCount, "showItemCount")
	bindEntryToggle(cbShowWhenEmpty, "showWhenEmpty")
	bindEntryToggle(cbShowWhenNoCooldown, "showWhenNoCooldown")
	bindEntryToggle(cbGlow, "glowReady")
	bindEntryToggle(cbSound, "soundReady")
	bindEntrySlider(glowDuration, "glowDuration", 0, 30)

	soundButton:SetScript("OnClick", function(self)
		local panelId = editor.selectedPanelId
		local entryId = editor.selectedEntryId
		if panelId and entryId then showSoundMenu(self, panelId, entryId) end
	end)

	removeEntry:SetScript("OnClick", function()
		local panelId = editor.selectedPanelId
		local entryId = editor.selectedEntryId
		if panelId and entryId then
			CooldownPanels:RemoveEntry(panelId, entryId)
			editor.selectedEntryId = nil
			CooldownPanels:RefreshEditor()
		end
	end)

	return runtime.editor
end

ensureDeletePopup = function()
	if StaticPopupDialogs["EQOL_COOLDOWN_PANEL_DELETE"] then return end
	StaticPopupDialogs["EQOL_COOLDOWN_PANEL_DELETE"] = {
		text = L["CooldownPanelDeletePanel"] or "Delete Panel?",
		button1 = YES,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
		OnAccept = function(self, data)
			if not data or not data.panelId then return end
			CooldownPanels:DeletePanel(data.panelId)
			CooldownPanels:RefreshEditor()
		end,
	}
end

local function updateRowVisual(row, selected)
	if not row or not row.bg then return end
	if selected then
		row.bg:SetColorTexture(0.1, 0.6, 0.6, 0.35)
	else
		row.bg:SetColorTexture(0, 0, 0, 0.2)
	end
end

local function refreshPanelList(editor, root)
	local list = editor.panelList
	if not list then return end
	local content = list.content
	local rowHeight = 28
	local spacing = 4
	local index = 0

	for _, panelId in ipairs(root.order or {}) do
		local panel = root.panels and root.panels[panelId]
		if panel then
			index = index + 1
			local row = editor.panelRows[index]
			if not row then
				row = createRowButton(content, rowHeight)
				row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
				row.label:SetTextColor(1, 1, 1, 1)

				row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
				row.count:SetPoint("RIGHT", row, "RIGHT", -8, 0)
				editor.panelRows[index] = row
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((index - 1) * (rowHeight + spacing)))
			row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -((index - 1) * (rowHeight + spacing)))

			row.panelId = panelId
			row.label:SetText(panel.name or ("Panel " .. tostring(panelId)))
			local entryCount = panel.order and #panel.order or 0
			row.count:SetText(entryCount)
			row:Show()

			updateRowVisual(row, panelId == editor.selectedPanelId)
			row:SetScript("OnClick", function() CooldownPanels:SelectPanel(panelId) end)
		end
	end

	for i = index + 1, #editor.panelRows do
		editor.panelRows[i]:Hide()
	end

	local totalHeight = index * (rowHeight + spacing)
	content:SetHeight(totalHeight > 1 and totalHeight or 1)
end

local function moveEntryInOrder(panel, entryId, targetEntryId)
	if not panel or not panel.order then return false end
	if not entryId or not targetEntryId or entryId == targetEntryId then return false end
	local fromIndex, toIndex
	for i, id in ipairs(panel.order) do
		if id == entryId then fromIndex = i end
		if id == targetEntryId then toIndex = i end
	end
	if not fromIndex or not toIndex then return false end
	table.remove(panel.order, fromIndex)
	if fromIndex < toIndex then toIndex = toIndex - 1 end
	table.insert(panel.order, toIndex, entryId)
	return true
end

local function refreshEntryList(editor, panel)
	local list = editor.entryList
	if not list then return end
	local content = list.content
	local rowHeight = 30
	local spacing = 4
	local index = 0

	if panel and panel.order then
		for _, entryId in ipairs(panel.order or {}) do
			local entry = panel.entries and panel.entries[entryId]
			if entry then
				index = index + 1
				local row = editor.entryRows[index]
				if not row then
					row = createRowButton(content, rowHeight)
					row.icon = row:CreateTexture(nil, "ARTWORK")
					row.icon:SetSize(22, 22)
					row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)

					row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
					row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
					row.label:SetTextColor(1, 1, 1, 1)

					row.kind = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
					row.kind:SetPoint("RIGHT", row, "RIGHT", -6, 0)
					row:RegisterForDrag("LeftButton")
					row:SetScript("OnDragStart", function(self)
						if not editor.selectedPanelId then return end
						editor.dragEntryId = self.entryId
						editor.dragTargetId = nil
						editor.draggingEntry = true
						showEditorDragIcon(editor, self.icon and self.icon:GetTexture())
						self:SetAlpha(0.6)
					end)
					row:SetScript("OnDragStop", function(self)
						self:SetAlpha(1)
						if not editor.draggingEntry then return end
						editor.draggingEntry = nil
						hideEditorDragIcon(editor)
						local fromId = editor.dragEntryId
						local targetId = editor.dragTargetId
						editor.dragEntryId = nil
						editor.dragTargetId = nil
						if not fromId or not targetId or fromId == targetId then
							CooldownPanels:RefreshEditor()
							return
						end
						local panelId = editor.selectedPanelId
						local activePanel = panelId and CooldownPanels:GetPanel(panelId) or nil
						if activePanel and moveEntryInOrder(activePanel, fromId, targetId) then CooldownPanels:RefreshPanel(panelId) end
						CooldownPanels:RefreshEditor()
					end)
					row:SetScript("OnEnter", function(self)
						if editor.draggingEntry then
							editor.dragTargetId = self.entryId
							if self.bg then self.bg:SetColorTexture(0.2, 0.7, 0.2, 0.35) end
						end
					end)
					row:SetScript("OnLeave", function(self)
						if editor.draggingEntry then updateRowVisual(self, self.entryId == editor.selectedEntryId) end
					end)
					editor.entryRows[index] = row
				end
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((index - 1) * (rowHeight + spacing)))
				row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -((index - 1) * (rowHeight + spacing)))

				row.entryId = entryId
				row.icon:SetTexture(getEntryIcon(entry))
				row.label:SetText(getEntryName(entry))
				row.kind:SetText(getEntryTypeLabel(entry.type))
				row:Show()

				updateRowVisual(row, entryId == editor.selectedEntryId)
				row:SetScript("OnClick", function() CooldownPanels:SelectEntry(entryId) end)
			end
		end
	end

	for i = index + 1, #editor.entryRows do
		editor.entryRows[i]:Hide()
	end

	local totalHeight = index * (rowHeight + spacing)
	content:SetHeight(totalHeight > 1 and totalHeight or 1)
end

local function getPreviewLayout(panel, previewFrame, count)
	local baseLayout = (panel and panel.layout) or Helper.PANEL_LAYOUT_DEFAULTS
	local previewLayout = Helper.CopyTableShallow(baseLayout)
	previewLayout.iconSize = PREVIEW_ICON_SIZE
	local stackSize = tonumber(previewLayout.stackFontSize or Helper.PANEL_LAYOUT_DEFAULTS.stackFontSize) or Helper.PANEL_LAYOUT_DEFAULTS.stackFontSize
	previewLayout.stackFontSize = math.max(stackSize, PREVIEW_COUNT_FONT_MIN)
	local chargesSize = tonumber(previewLayout.chargesFontSize or Helper.PANEL_LAYOUT_DEFAULTS.chargesFontSize) or Helper.PANEL_LAYOUT_DEFAULTS.chargesFontSize
	previewLayout.chargesFontSize = math.max(chargesSize, PREVIEW_COUNT_FONT_MIN)

	if not previewFrame or not count or count < 1 then return previewLayout end

	local iconSize = PREVIEW_ICON_SIZE
	local spacing = clampInt(baseLayout.spacing, 0, 50, Helper.PANEL_LAYOUT_DEFAULTS.spacing)
	local direction = normalizeDirection(baseLayout.direction, Helper.PANEL_LAYOUT_DEFAULTS.direction)
	local wrapCount = clampInt(baseLayout.wrapCount, 0, 40, Helper.PANEL_LAYOUT_DEFAULTS.wrapCount or 0)

	local width = previewFrame:GetWidth() or 0
	local height = previewFrame:GetHeight() or 0
	local step = iconSize + spacing
	if width <= 0 or height <= 0 or step <= 0 then return previewLayout end

	local primaryHorizontal = direction == "LEFT" or direction == "RIGHT"
	local available = primaryHorizontal and width or height
	local maxPrimary = math.floor((available + spacing) / step)
	if maxPrimary < 1 then maxPrimary = 1 end

	if wrapCount == 0 then
		if count > maxPrimary then previewLayout.wrapCount = maxPrimary end
	else
		previewLayout.wrapCount = math.min(wrapCount, maxPrimary)
	end

	return previewLayout
end

local function refreshPreview(editor, panel)
	if not editor.previewFrame then return end
	local preview = editor.previewFrame
	local canvas = preview.canvas or preview
	if not panel then
		if editor.previewHintLabel then editor.previewHintLabel:Hide() end
		applyIconLayout(canvas, DEFAULT_PREVIEW_COUNT, Helper.PANEL_LAYOUT_DEFAULTS)
		canvas:ClearAllPoints()
		canvas:SetPoint("CENTER", preview, "CENTER")
		for i = 1, DEFAULT_PREVIEW_COUNT do
			local icon = canvas.icons[i]
			icon.texture:SetTexture(PREVIEW_ICON)
			icon.entryId = nil
			if icon.previewSoundBorder then icon.previewSoundBorder:Hide() end
		end
		if preview.dropHint then
			preview.dropHint:SetText(L["CooldownPanelSelectPanel"] or "Select a panel to edit.")
			preview.dropHint:Show()
		end
		return
	end

	if editor.previewHintLabel then editor.previewHintLabel:Show() end
	local baseLayout = (panel and panel.layout) or Helper.PANEL_LAYOUT_DEFAULTS
	local count = getEditorPreviewCount(panel, preview, baseLayout)
	local layout = getPreviewLayout(panel, preview, count)
	applyIconLayout(canvas, count, layout)
	canvas:ClearAllPoints()
	canvas:SetPoint("CENTER", preview, "CENTER")

	preview.entryByIndex = preview.entryByIndex or {}
	for i = 1, count do
		local entryId = panel.order and panel.order[i]
		local entry = entryId and panel.entries and panel.entries[entryId] or nil
		local icon = canvas.icons[i]
		icon.texture:SetTexture(getEntryIcon(entry))
		icon.entryId = entryId
		icon.count:Hide()
		icon.charges:Hide()
		if icon.previewGlow then icon.previewGlow:Hide() end
		if icon.previewSoundBorder then icon.previewSoundBorder:Hide() end
		if entry then
			if entry.type == "SPELL" then
				if entry.showCharges then
					icon.charges:SetText("2")
					icon.charges:Show()
				end
				if entry.showStacks then
					icon.count:SetText("3")
					icon.count:Show()
				end
			elseif entry.type == "ITEM" then
				if entry.showItemCount ~= false then
					icon.count:SetText("20")
					icon.count:Show()
				end
			end
			if entry.glowReady and icon.previewGlow then icon.previewGlow:Show() end
			if entry.soundReady and icon.previewSoundBorder then icon.previewSoundBorder:Show() end
		end
	end

	if preview.dropHint then
		preview.dropHint:SetText(L["CooldownPanelDropHint"] or "Drop spells or items here")
		preview.dropHint:SetShown((panel.order and #panel.order or 0) == 0)
	end
end

local function layoutInspectorToggles(inspector, entry)
	if not inspector then return end
	local function hideToggle(cb)
		if not cb then return end
		cb:Hide()
		cb:Disable()
		cb:SetChecked(false)
	end
	local function hideControl(control)
		if not control then return end
		control:Hide()
		if control.Disable then control:Disable() end
	end
	if not entry then
		hideToggle(inspector.cbCooldownText)
		hideToggle(inspector.cbCharges)
		hideToggle(inspector.cbStacks)
		hideToggle(inspector.cbItemCount)
		hideToggle(inspector.cbShowWhenEmpty)
		hideToggle(inspector.cbShowWhenNoCooldown)
		hideToggle(inspector.cbGlow)
		hideToggle(inspector.cbSound)
		hideControl(inspector.glowDuration)
		hideControl(inspector.soundButton)
		return
	end

	local prev = inspector.entryId
	local function place(control, show, offsetX, offsetY)
		if not control then return end
		control:ClearAllPoints()
		control:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", offsetX or -2, offsetY or -6)
		if show then
			control:Show()
			if control.Enable then control:Enable() end
			prev = control
		else
			control:Hide()
			if control.Disable then control:Disable() end
		end
	end

	place(inspector.cbCooldownText, true)
	if entry.type == "SPELL" then
		place(inspector.cbCharges, true)
		place(inspector.cbStacks, true)
		place(inspector.cbItemCount, false)
		place(inspector.cbShowWhenEmpty, false)
		place(inspector.cbShowWhenNoCooldown, false)
	elseif entry.type == "ITEM" then
		place(inspector.cbCharges, false)
		place(inspector.cbStacks, false)
		place(inspector.cbItemCount, true)
		place(inspector.cbShowWhenEmpty, true)
		place(inspector.cbShowWhenNoCooldown, false)
	elseif entry.type == "SLOT" then
		place(inspector.cbCharges, false)
		place(inspector.cbStacks, false)
		place(inspector.cbItemCount, false)
		place(inspector.cbShowWhenEmpty, false)
		place(inspector.cbShowWhenNoCooldown, true)
	else
		place(inspector.cbCharges, false)
		place(inspector.cbStacks, false)
		place(inspector.cbItemCount, false)
		place(inspector.cbShowWhenEmpty, false)
		place(inspector.cbShowWhenNoCooldown, false)
	end
	place(inspector.cbGlow, true)
	if inspector.glowDuration then
		inspector.glowDuration:ClearAllPoints()
		inspector.glowDuration:SetPoint("TOPLEFT", inspector.cbGlow, "BOTTOMLEFT", 18, -8)
		if entry.glowReady then
			inspector.glowDuration:Show()
			inspector.glowDuration:Enable()
			prev = inspector.glowDuration
		else
			inspector.glowDuration:Hide()
			inspector.glowDuration:Disable()
		end
	end
	local soundOffsetX = -2
	if inspector.glowDuration and entry.glowReady then soundOffsetX = -20 end
	place(inspector.cbSound, true, soundOffsetX, -6)
	if inspector.soundButton then
		inspector.soundButton:ClearAllPoints()
		inspector.soundButton:SetPoint("TOPLEFT", inspector.cbSound, "BOTTOMLEFT", 18, -6)
		if entry.soundReady then
			inspector.soundButton:Show()
			inspector.soundButton:Enable()
			prev = inspector.soundButton
		else
			inspector.soundButton:Hide()
			inspector.soundButton:Disable()
		end
	end
end

local function refreshInspector(editor, panel, entry)
	local inspector = editor.inspector
	if not inspector then return end

	if panel then
		inspector.panelName:SetText(panel.name or "")
		inspector.panelEnabled:SetChecked(panel.enabled ~= false)
		inspector.panelName:Enable()
		inspector.panelEnabled:Enable()
	else
		inspector.panelName:SetText("")
		inspector.panelName:Disable()
		inspector.panelEnabled:SetChecked(false)
		inspector.panelEnabled:Disable()
	end

	if entry then
		inspector.entryIcon:SetTexture(getEntryIcon(entry))
		inspector.entryName:SetText(getEntryName(entry))
		inspector.entryType:SetText(getEntryTypeLabel(entry.type))
		inspector.entryId:SetText(tostring(entry.spellID or entry.itemID or entry.slotID or ""))

		inspector.cbCooldownText:SetChecked(entry.showCooldownText ~= false)
		inspector.cbCharges:SetChecked(entry.showCharges and true or false)
		inspector.cbStacks:SetChecked(entry.showStacks and true or false)
		inspector.cbItemCount:SetChecked(entry.type == "ITEM" and entry.showItemCount ~= false)
		inspector.cbShowWhenEmpty:SetChecked(entry.type == "ITEM" and entry.showWhenEmpty == true)
		inspector.cbShowWhenNoCooldown:SetChecked(entry.type == "SLOT" and entry.showWhenNoCooldown == true)
		inspector.cbGlow:SetChecked(entry.glowReady and true or false)
		inspector.cbSound:SetChecked(entry.soundReady and true or false)
		if inspector.soundButton then inspector.soundButton:SetText(getSoundButtonText(entry.soundReadyFile)) end
		if inspector.glowDuration then
			local duration = clampInt(entry.glowDuration, 0, 30, 0)
			inspector.glowDuration._suspend = true
			inspector.glowDuration:SetValue(duration)
			inspector.glowDuration._suspend = nil
			if inspector.glowDuration.Text then inspector.glowDuration.Text:SetText((L["CooldownPanelGlowDuration"] or "Glow duration") .. ": " .. tostring(duration) .. "s") end
			if inspector.glowDuration.Low then inspector.glowDuration.Low:SetText("0s") end
			if inspector.glowDuration.High then inspector.glowDuration.High:SetText("30s") end
		end

		inspector.entryId:Enable()
		inspector.removeEntry:Enable()
		layoutInspectorToggles(inspector, entry)
	else
		inspector.entryIcon:SetTexture(PREVIEW_ICON)
		inspector.entryName:SetText(L["CooldownPanelSelectEntry"] or "Select an entry.")
		inspector.entryType:SetText("")
		inspector.entryId:SetText("")

		inspector.entryId:Disable()
		inspector.removeEntry:Disable()
		if inspector.soundButton then inspector.soundButton:SetText(getSoundButtonText(nil)) end
		layoutInspectorToggles(inspector, nil)
	end
end

function CooldownPanels:RefreshEditor()
	local editor = getEditor()
	if not editor or not editor.frame or not editor.frame:IsShown() then return end
	local root = ensureRoot()
	if not root then return end

	self:NormalizeAll()
	Helper.SyncOrder(root.order, root.panels)

	local panelId = editor.selectedPanelId or root.selectedPanel or (root.order and root.order[1])
	if panelId and (not root.panels or not root.panels[panelId]) then panelId = root.order and root.order[1] or nil end
	editor.selectedPanelId = panelId
	root.selectedPanel = panelId

	local panel = panelId and root.panels and root.panels[panelId] or nil
	if panel then Helper.NormalizePanel(panel, root.defaults) end

	refreshPanelList(editor, root)
	refreshEntryList(editor, panel)
	refreshPreview(editor, panel)

	local panelActive = panel ~= nil
	if editor.deletePanel then
		if panelActive then
			editor.deletePanel:Enable()
		else
			editor.deletePanel:Disable()
		end
	end
	if editor.addSpellBox then
		if panelActive then
			editor.addSpellBox:Enable()
		else
			editor.addSpellBox:Disable()
		end
	end
	if editor.addItemBox then
		if panelActive then
			editor.addItemBox:Enable()
		else
			editor.addItemBox:Disable()
		end
	end
	if editor.slotButton then
		if panelActive then
			editor.slotButton:Enable()
		else
			editor.slotButton:Disable()
		end
	end

	local entryId = editor.selectedEntryId
	if panel and entryId and not (panel.entries and panel.entries[entryId]) then entryId = nil end
	editor.selectedEntryId = entryId
	local entry = panel and entryId and panel.entries and panel.entries[entryId] or nil
	refreshInspector(editor, panel, entry)
end

function CooldownPanels:OpenEditor()
	local editor = ensureEditor()
	if not editor then return end
	editor.frame:Show()
	self:RefreshEditor()
end

function CooldownPanels:CloseEditor()
	local editor = getEditor()
	if not editor then return end
	editor.frame:Hide()
end

function CooldownPanels:ToggleEditor()
	local editor = getEditor()
	if not editor then
		self:OpenEditor()
		return
	end
	if editor.frame:IsShown() then
		self:CloseEditor()
	else
		self:OpenEditor()
	end
end

function CooldownPanels:IsEditorOpen()
	local editor = getEditor()
	return editor and editor.frame and editor.frame:IsShown()
end

function CooldownPanels:EnsurePanelFrame(panelId)
	local panel = self:GetPanel(panelId)
	if not panel then return nil end
	local runtime = getRuntime(panelId)
	if runtime.frame then return runtime.frame end
	local frame = createPanelFrame(panelId, panel)
	runtime.frame = frame
	self:ApplyPanelPosition(panelId)
	self:ApplyLayout(panelId)
	self:UpdatePreviewIcons(panelId)
	return frame
end

function CooldownPanels:ApplyLayout(panelId, countOverride)
	local panel = self:GetPanel(panelId)
	if not panel then return end
	local runtime = getRuntime(panelId)
	local frame = runtime.frame
	if not frame then return end
	panel.layout = panel.layout or Helper.CopyTableShallow(Helper.PANEL_LAYOUT_DEFAULTS)
	local layout = panel.layout

	local count = countOverride or getPreviewCount(panel)
	applyIconLayout(frame, count, layout)

	frame:SetFrameStrata(normalizeStrata(layout.strata, Helper.PANEL_LAYOUT_DEFAULTS.strata))
	if frame.label then frame.label:SetText(panel.name or "Cooldown Panel") end
end

function CooldownPanels:UpdatePreviewIcons(panelId, countOverride)
	local panel = self:GetPanel(panelId)
	if not panel then return end
	local runtime = getRuntime(panelId)
	local frame = runtime.frame
	if not frame then return end
	panel.layout = panel.layout or Helper.CopyTableShallow(Helper.PANEL_LAYOUT_DEFAULTS)
	local layout = panel.layout
	local showTooltips = layout.showTooltips == true
	local count = countOverride or getPreviewCount(panel)
	ensureIconCount(frame, count)

	for i = 1, count do
		local entryId = panel.order and panel.order[i]
		local entry = entryId and panel.entries and panel.entries[entryId] or nil
		local icon = frame.icons[i]
		local showCooldown = entry and entry.showCooldown ~= false
		local showCooldownText = entry and entry.showCooldownText ~= false
		local showCharges = entry and entry.type == "SPELL" and entry.showCharges == true
		local showStacks = entry and entry.type == "SPELL" and entry.showStacks == true
		local showItemCount = entry and entry.type == "ITEM" and entry.showItemCount ~= false
		icon.texture:SetTexture(getEntryIcon(entry))
		icon.cooldown:SetHideCountdownNumbers(not showCooldownText)
		icon.cooldown:Clear()
		if icon.cooldown.SetScript then icon.cooldown:SetScript("OnCooldownDone", nil) end
		icon.count:Hide()
		icon.charges:Hide()
		if icon.previewGlow then icon.previewGlow:Hide() end
		if icon.previewBling then icon.previewBling:Hide() end
		setGlow(icon, false)
		if showCooldown then
			setExampleCooldown(icon.cooldown)
			icon.texture:SetDesaturated(true)
			icon.texture:SetAlpha(0.6)
			if icon.previewBling then icon.previewBling:SetShown(layout.cooldownDrawBling ~= false) end
		else
			icon.texture:SetDesaturated(false)
			icon.texture:SetAlpha(1)
		end
		if showCharges then
			icon.charges:SetText("2")
			icon.charges:Show()
		end
		if showStacks then
			icon.count:SetText("3")
			icon.count:Show()
		elseif showItemCount then
			local countValue
			if entry and entry.itemID and GetItemCountFn then countValue = GetItemCountFn(entry.itemID, true) end
			if isSafeGreaterThan(countValue, 0) then
				icon.count:SetText(countValue)
			else
				icon.count:SetText("20")
			end
			icon.count:Show()
		end
		applyIconTooltip(icon, entry, showTooltips)
	end
end

function CooldownPanels:UpdateRuntimeIcons(panelId)
	local panel = self:GetPanel(panelId)
	if not panel then return end
	local runtime = getRuntime(panelId)
	local frame = runtime.frame
	if not frame then return end
	panel.layout = panel.layout or Helper.CopyTableShallow(Helper.PANEL_LAYOUT_DEFAULTS)
	local layout = panel.layout
	local showTooltips = layout.showTooltips == true
	local drawEdge = layout.cooldownDrawEdge ~= false
	local drawBling = layout.cooldownDrawBling ~= false
	local drawSwipe = layout.cooldownDrawSwipe ~= false
	local gcdDrawEdge = layout.cooldownGcdDrawEdge == true
	local gcdDrawBling = layout.cooldownGcdDrawBling == true
	local gcdDrawSwipe = layout.cooldownGcdDrawSwipe == true

	local visible = runtime.visibleEntries
	if not visible then
		visible = {}
		runtime.visibleEntries = visible
	end
	local visibleCount = 0

	local order = panel.order or {}
	runtime.readyState = runtime.readyState or {}
	runtime.readyAt = runtime.readyAt or {}
	runtime.glowTimers = runtime.glowTimers or {}
	local glowTimers = runtime.glowTimers
	local initialPass = runtime.initialized ~= true
	for _, entryId in ipairs(order) do
		local entry = panel.entries and panel.entries[entryId]
		if entry then
			local showCooldown = entry.showCooldown ~= false
			local showCooldownText = entry.showCooldownText ~= false
			local showCharges = entry.showCharges == true
			local showStacks = entry.showStacks == true
			local showItemCount = entry.type == "ITEM" and entry.showItemCount ~= false
			local showWhenEmpty = entry.type == "ITEM" and entry.showWhenEmpty == true
			local showWhenNoCooldown = entry.type == "SLOT" and entry.showWhenNoCooldown == true
			local alwaysShow = entry.alwaysShow ~= false
			local glowReady = entry.glowReady ~= false
			local glowDuration = clampInt(entry.glowDuration, 0, 30, 0)
			local soundReady = entry.soundReady == true
			local soundName = normalizeSoundName(entry.soundReadyFile)

			local iconTexture = getEntryIcon(entry)
			local stackCount
			local itemCount
			local chargesInfo
			local cooldownDurationObject
			local cooldownRemaining
			local cooldownStart, cooldownDuration, cooldownEnabled, cooldownRate, cooldownGCD
			local show = false
			local readyNow = false
			local cooldownEnabledOk = true
			local cooldownActive = false
			local emptyItem = false

			if entry.type == "SPELL" and entry.spellID then
				if IsSpellKnown and not IsSpellKnown(entry.spellID) then
					show = false
				else
					if showCharges and GetSpellChargesInfo then chargesInfo = GetSpellChargesInfo(entry.spellID) end
					if showCooldown then
						cooldownDurationObject = getSpellCooldownDurationObject(entry.spellID)
						cooldownRemaining = getDurationRemaining(cooldownDurationObject)
						if cooldownRemaining ~= nil and cooldownRemaining <= 0 then
							cooldownDurationObject = nil
							cooldownRemaining = nil
						end
					end
					if (showCooldown or (showCharges and chargesInfo)) and not cooldownDurationObject then
						cooldownStart, cooldownDuration, cooldownEnabled, cooldownRate, cooldownGCD = getSpellCooldownInfo(entry.spellID)
					elseif cooldownDurationObject then
						_, _, _, _, cooldownGCD = getSpellCooldownInfo(entry.spellID)
					end
					if showStacks and GetPlayerAuraBySpellID then
						local aura = GetPlayerAuraBySpellID(entry.spellID)
						if aura and isSafeGreaterThan(aura.applications, 1) then stackCount = aura.applications end
					end
					cooldownEnabledOk = isSafeNotFalse(cooldownEnabled)
					local durationActive = cooldownDurationObject ~= nil and (cooldownRemaining == nil or cooldownRemaining > 0)
					cooldownActive = showCooldown and (durationActive or (cooldownEnabledOk and isCooldownActive(cooldownStart, cooldownDuration)))
					if showCharges and chargesInfo then
						if issecretvalue and issecretvalue(chargesInfo.currentCharges) then
							readyNow = false
						else
							readyNow = isSafeGreaterThan(chargesInfo.currentCharges, 0)
						end
					else
						readyNow = showCooldown and (cooldownGCD == true or not cooldownActive)
					end
					show = alwaysShow
					if not show and showCooldown and ((cooldownDurationObject ~= nil) or (cooldownEnabledOk and isCooldownActive(cooldownStart, cooldownDuration))) then show = true end
					if not show and showCharges and chargesInfo and isSafeLessThan(chargesInfo.currentCharges, chargesInfo.maxCharges) then show = true end
					if not show and showStacks and stackCount then show = true end
				end
			elseif entry.type == "ITEM" and entry.itemID then
				local ownsItem = hasItem(entry.itemID)
				emptyItem = showWhenEmpty and not ownsItem
				if (ownsItem or showWhenEmpty) and itemHasUseSpell(entry.itemID) then
					if showCooldown and ownsItem then
						cooldownStart, cooldownDuration, cooldownEnabled = getItemCooldownInfo(entry.itemID)
					end
					if showItemCount and GetItemCountFn then
						local count = GetItemCountFn(entry.itemID, true) or 0
						if isSafeGreaterThan(count, 0) then
							itemCount = count
						elseif showWhenEmpty then
							itemCount = 0
						end
					end
					cooldownEnabledOk = isSafeNotFalse(cooldownEnabled)
					cooldownActive = showCooldown and cooldownEnabledOk and isCooldownActive(cooldownStart, cooldownDuration)
					readyNow = showCooldown and ownsItem and not cooldownActive
					show = alwaysShow or showWhenEmpty
					if not show and showCooldown and cooldownEnabledOk and isCooldownActive(cooldownStart, cooldownDuration) then show = true end
				end
			elseif entry.type == "SLOT" and entry.slotID then
				local itemId = GetInventoryItemID and GetInventoryItemID("player", entry.slotID) or nil
				if itemId then
					iconTexture = GetItemIconByID and GetItemIconByID(itemId) or iconTexture
					if itemHasUseSpell(itemId) then
						if showCooldown then
							cooldownStart, cooldownDuration, cooldownEnabled = getItemCooldownInfo(itemId, entry.slotID)
						end
						cooldownEnabledOk = isSafeNotFalse(cooldownEnabled)
						cooldownActive = showCooldown and cooldownEnabledOk and isCooldownActive(cooldownStart, cooldownDuration)
						readyNow = showCooldown and not cooldownActive
						show = alwaysShow or showWhenNoCooldown
						if not show and showCooldown and cooldownEnabledOk and isCooldownActive(cooldownStart, cooldownDuration) then show = true end
					elseif showWhenNoCooldown then
						show = true
					end
				end
			end

			if show then
				local hadState = runtime.readyState[entryId] ~= nil
				local wasReady = runtime.readyState[entryId] == true
				if readyNow and not wasReady then
					if not initialPass or hadState then
						local now = GetTime and GetTime() or 0
						runtime.readyAt[entryId] = now
						if glowDuration > 0 and C_Timer and C_Timer.NewTimer then
							if glowTimers[entryId] and glowTimers[entryId].Cancel then glowTimers[entryId]:Cancel() end
							glowTimers[entryId] = C_Timer.NewTimer(glowDuration, function()
								if runtime.readyAt and runtime.readyAt[entryId] == now then runtime.readyAt[entryId] = nil end
								glowTimers[entryId] = nil
								CooldownPanels:RequestUpdate()
							end)
						end
					end
				elseif not readyNow then
					runtime.readyAt[entryId] = nil
					if glowTimers[entryId] and glowTimers[entryId].Cancel then glowTimers[entryId]:Cancel() end
					glowTimers[entryId] = nil
				end
				runtime.readyState[entryId] = readyNow
				visibleCount = visibleCount + 1
				local data = visible[visibleCount]
				if not data then
					data = {}
					visible[visibleCount] = data
				end
				data.icon = iconTexture or PREVIEW_ICON
				data.showCooldown = showCooldown
				data.showCooldownText = showCooldownText
				data.showCharges = showCharges
				data.showStacks = showStacks
				data.showItemCount = showItemCount
				data.entry = entry
				data.glowReady = glowReady
				data.glowDuration = glowDuration
				data.soundReady = soundReady
				data.soundName = soundName
				data.readyNow = readyNow
				data.readyAt = runtime.readyAt[entryId]
				data.stackCount = stackCount
				data.itemCount = itemCount
				data.emptyItem = emptyItem
				data.chargesInfo = chargesInfo
				data.cooldownDurationObject = cooldownDurationObject
				data.cooldownRemaining = cooldownRemaining
				data.cooldownStart = cooldownStart or 0
				data.cooldownDuration = cooldownDuration or 0
				data.cooldownEnabled = cooldownEnabled
				data.cooldownRate = cooldownRate or 1
				data.cooldownGCD = cooldownGCD or nil
			end
		end
	end

	for i = visibleCount + 1, #visible do
		visible[i] = nil
	end

	local count = visibleCount
	local layoutCount = count > 0 and count or 1
	if runtime._eqolLastLayoutCount ~= layoutCount then
		self:ApplyLayout(panelId, layoutCount)
		runtime._eqolLastLayoutCount = layoutCount
	end
	ensureIconCount(frame, count)

	for i = 1, count do
		local data = visible[i]
		local icon = frame.icons[i]
		icon.texture:SetTexture(data.icon or PREVIEW_ICON)
		applyIconTooltip(icon, data.entry, showTooltips)
		icon.cooldown:SetHideCountdownNumbers(not data.showCooldownText)
		icon.cooldown._eqolSoundReady = data.soundReady and not data.cooldownGCD
		icon.cooldown._eqolSoundName = data.soundName
		if icon.cooldown.Resume then icon.cooldown:Resume() end
		if icon.previewGlow then icon.previewGlow:Hide() end
		if icon.previewBling then icon.previewBling:Hide() end

		local cooldownStart = data.cooldownStart or 0
		local cooldownDuration = data.cooldownDuration or 0
		local cooldownRate = data.cooldownRate or 1
		local cooldownDurationObject = data.cooldownDurationObject
		local cooldownEnabledOk = isSafeNotFalse(data.cooldownEnabled)
		local cooldownRemaining = data.cooldownRemaining
		local durationActive = cooldownDurationObject ~= nil and (cooldownRemaining == nil or cooldownRemaining > 0)
		local cooldownActive = data.showCooldown and (durationActive or (cooldownEnabledOk and isCooldownActive(cooldownStart, cooldownDuration)))
		local usingCooldown = false
		local desaturate = false

		if data.showCharges and data.chargesInfo and data.chargesInfo.maxCharges ~= nil then
			if data.chargesInfo.currentCharges ~= nil then
				icon.charges:SetText(data.chargesInfo.currentCharges)
				icon.charges:Show()
			else
				icon.charges:Hide()
			end
			if data.showCooldown then
				local chargesSecret = issecretvalue and (issecretvalue(data.chargesInfo.currentCharges) or issecretvalue(data.chargesInfo.maxCharges))
				if chargesSecret or isSafeLessThan(data.chargesInfo.currentCharges, data.chargesInfo.maxCharges) then
					cooldownStart = data.chargesInfo.cooldownStartTime or cooldownStart
					cooldownDuration = data.chargesInfo.cooldownDuration or cooldownDuration
					cooldownRate = data.chargesInfo.chargeModRate or cooldownRate
					cooldownActive = true
					usingCooldown = true
				end
			end
			if usingCooldown then
				if isSafeNumber(data.chargesInfo.currentCharges) then
					desaturate = data.chargesInfo.currentCharges == 0
				else
					-- TODO need to find a way for charges = 0 in secret to make it desaturated
					-- print(data.chargesInfo.currentCharges, issecretvalue(data.chargesInfo.currentCharges))
					-- icon.texture:SetDesaturation(data.chargesInfo.currentCharges)
				end
			end
		else
			icon.charges:Hide()
		end

		if data.emptyItem then desaturate = true end

		if not isSafeNumber(cooldownRate) then cooldownRate = 1 end
		icon.texture:SetDesaturated(desaturate)
		if data.showCooldown then
			if usingCooldown then
				icon.cooldown:SetCooldown(cooldownStart, cooldownDuration, cooldownRate)
				setCooldownDrawState(icon.cooldown, drawEdge, drawBling, drawSwipe)
				if icon.cooldown.SetScript then icon.cooldown:SetScript("OnCooldownDone", onCooldownDone) end
			elseif durationActive then
				icon.cooldown:SetCooldownFromDurationObject(cooldownDurationObject)
				if data.cooldownGCD then
					icon.texture:SetDesaturation(0)
					desaturate = false
					setCooldownDrawState(icon.cooldown, gcdDrawEdge, gcdDrawBling, gcdDrawSwipe)
				else
					setCooldownDrawState(icon.cooldown, drawEdge, drawBling, drawSwipe)

					local desat = cooldownDurationObject:EvaluateRemainingDuration(curveDesat)
					icon.texture:SetDesaturation(desat)
				end
				if icon.cooldown.SetScript then icon.cooldown:SetScript("OnCooldownDone", onCooldownDone) end
			elseif cooldownActive then
				icon.cooldown:SetCooldown(cooldownStart, cooldownDuration, cooldownRate)
				desaturate = true
				icon.texture:SetDesaturated(desaturate)
				setCooldownDrawState(icon.cooldown, drawEdge, drawBling, drawSwipe)
				if icon.cooldown.SetScript then icon.cooldown:SetScript("OnCooldownDone", onCooldownDone) end
			else
				setCooldownDrawState(icon.cooldown, drawEdge, drawBling, drawSwipe)
				icon.cooldown:Clear()
				if icon.cooldown.SetScript then icon.cooldown:SetScript("OnCooldownDone", nil) end
			end
		else
			setCooldownDrawState(icon.cooldown, drawEdge, drawBling, drawSwipe)
			icon.cooldown:Clear()
			if icon.cooldown.SetScript then icon.cooldown:SetScript("OnCooldownDone", nil) end
		end
		icon.texture:SetAlphaFromBoolean(desaturate, 0.5, 1)

		if data.showItemCount and data.itemCount ~= nil then
			icon.count:SetText(data.itemCount)
			icon.count:Show()
		elseif data.showStacks and data.stackCount then
			icon.count:SetText(data.stackCount)
			icon.count:Show()
		else
			icon.count:Hide()
		end

		if data.glowReady then
			local ready = false
			local duration = tonumber(data.glowDuration) or 0
			if duration > 0 then
				if data.readyAt and GetTime then ready = (GetTime() - data.readyAt) <= duration end
			else
				if data.showCharges and data.chargesInfo and data.chargesInfo.currentCharges then
					ready = isSafeGreaterThan(data.chargesInfo.currentCharges, 0)
				elseif data.showCooldown then
					ready = (not cooldownActive) or data.cooldownGCD == true
				end
			end
			setGlow(icon, ready)
		else
			setGlow(icon, false)
		end
	end

	for i = count + 1, #frame.icons do
		local icon = frame.icons[i]
		if icon then
			icon.cooldown:Clear()
			icon.cooldown._eqolSoundReady = nil
			icon.cooldown._eqolSoundName = nil
			if icon.cooldown.SetScript then icon.cooldown:SetScript("OnCooldownDone", nil) end
			if icon.cooldown.Resume then icon.cooldown:Resume() end
			icon.count:Hide()
			icon.charges:Hide()
			if icon.previewBling then icon.previewBling:Hide() end
			icon.texture:SetDesaturated(false)
			icon.texture:SetAlpha(1)
			setGlow(icon, false)
		end
	end

	runtime.visibleCount = count
	runtime.initialized = true
end

function CooldownPanels:ApplyPanelPosition(panelId)
	local panel = self:GetPanel(panelId)
	if not panel then return end
	local runtime = getRuntime(panelId)
	local frame = runtime.frame
	if not frame then return end
	local anchor = ensurePanelAnchor(panel)
	local point = normalizeAnchor(anchor and anchor.point, panel.point or "CENTER")
	local relativePoint = normalizeAnchor(anchor and anchor.relativePoint, point)
	local x = tonumber(anchor and anchor.x) or 0
	local y = tonumber(anchor and anchor.y) or 0
	local relativeFrame = resolveAnchorFrame(anchor)
	frame:ClearAllPoints()
	frame:SetPoint(point, relativeFrame, relativePoint, x, y)
end

function CooldownPanels:HandlePositionChanged(panelId, data)
	local panel = self:GetPanel(panelId)
	if not panel or type(data) ~= "table" then return end
	local runtime = getRuntime(panelId)
	if runtime.suspendEditSync then return end
	local anchor = ensurePanelAnchor(panel)
	if not anchor or not anchorUsesUIParent(anchor) then return end
	anchor.point = data.point or anchor.point or "CENTER"
	anchor.relativePoint = data.relativePoint or anchor.relativePoint or anchor.point
	if data.x ~= nil then anchor.x = data.x end
	if data.y ~= nil then anchor.y = data.y end
	panel.point = anchor.point or panel.point or "CENTER"
	panel.x = anchor.x or panel.x or 0
	panel.y = anchor.y or panel.y or 0
end

function CooldownPanels:IsInEditMode() return EditMode and EditMode.IsInEditMode and EditMode:IsInEditMode() end

function CooldownPanels:ShouldShowPanel(panelId)
	local panel = self:GetPanel(panelId)
	if not panel or panel.enabled == false then return false end
	if self:IsInEditMode() == true then return true end
	local runtime = getRuntime(panelId)
	return runtime.visibleCount and runtime.visibleCount > 0
end

function CooldownPanels:UpdatePanelOpacity(panelId)
	local panel = self:GetPanel(panelId)
	if not panel then return end
	local runtime = getRuntime(panelId)
	local frame = runtime.frame
	if not frame then return end
	panel.layout = panel.layout or Helper.CopyTableShallow(Helper.PANEL_LAYOUT_DEFAULTS)
	local layout = panel.layout
	local fallbackOut = Helper.PANEL_LAYOUT_DEFAULTS.opacityOutOfCombat
	local fallbackIn = Helper.PANEL_LAYOUT_DEFAULTS.opacityInCombat
	local outAlpha = normalizeOpacity(layout.opacityOutOfCombat, fallbackOut)
	local inAlpha = normalizeOpacity(layout.opacityInCombat, fallbackIn)
	local alpha
	if self:IsInEditMode() == true then
		alpha = 1
	else
		local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
		alpha = inCombat and inAlpha or outAlpha
	end
	if alpha == nil then alpha = 1 end
	if frame._eqolAlpha ~= alpha then
		frame._eqolAlpha = alpha
		frame:SetAlpha(alpha)
	end
end

function CooldownPanels:UpdateVisibility(panelId)
	local runtime = getRuntime(panelId)
	local frame = runtime.frame
	if not frame then return end
	frame:SetShown(self:ShouldShowPanel(panelId))
	self:UpdatePanelOpacity(panelId)
	self:UpdatePanelMouseState(panelId)
end

function CooldownPanels:UpdatePanelMouseState(panelId)
	local runtime = getRuntime(panelId)
	local frame = runtime.frame
	if not frame then return end
	local enable = self:IsInEditMode() == true
	if frame._mouseEnabled ~= enable then
		frame._mouseEnabled = enable
		frame:EnableMouse(enable)
	end
end

function CooldownPanels:ShowEditModeHint(panelId, show)
	local runtime = getRuntime(panelId)
	local frame = runtime.frame
	if not frame then return end
	if show then
		if frame.bg then frame.bg:Show() end
		if frame.label then frame.label:Show() end
	else
		if frame.bg then frame.bg:Hide() end
		if frame.label then frame.label:Hide() end
	end
end

function CooldownPanels:RefreshPanel(panelId)
	if not self:GetPanel(panelId) then return end
	self:EnsurePanelFrame(panelId)
	if self:IsInEditMode() then
		self:ApplyLayout(panelId)
		self:UpdatePreviewIcons(panelId)
	else
		self:UpdateRuntimeIcons(panelId)
	end
	self:UpdateVisibility(panelId)
end

function CooldownPanels:RefreshAllPanels()
	local root = ensureRoot()
	if not root then return end
	Helper.SyncOrder(root.order, root.panels)
	for _, panelId in ipairs(root.order) do
		self:RefreshPanel(panelId)
	end
	for panelId in pairs(root.panels) do
		if not containsId(root.order, panelId) then self:RefreshPanel(panelId) end
	end
end

local function syncEditModeValue(panelId, field, value)
	local runtime = getRuntime(panelId)
	if not runtime or runtime.applyingFromEditMode then return end
	if runtime.editModeId and EditMode and EditMode.SetValue then EditMode:SetValue(runtime.editModeId, field, value, nil, true) end
end

local function applyEditLayout(panelId, field, value, skipRefresh)
	local panel = CooldownPanels:GetPanel(panelId)
	if not panel then return end
	panel.layout = panel.layout or {}
	local layout = panel.layout

	if field == "iconSize" then
		layout.iconSize = clampInt(value, 12, 128, layout.iconSize)
	elseif field == "spacing" then
		layout.spacing = clampInt(value, 0, 50, layout.spacing)
	elseif field == "direction" then
		layout.direction = normalizeDirection(value, layout.direction)
	elseif field == "wrapCount" then
		layout.wrapCount = clampInt(value, 0, 40, layout.wrapCount)
	elseif field == "wrapDirection" then
		layout.wrapDirection = normalizeDirection(value, layout.wrapDirection)
	elseif field == "strata" then
		layout.strata = normalizeStrata(value, layout.strata)
	elseif field == "stackAnchor" then
		layout.stackAnchor = normalizeAnchor(value, layout.stackAnchor or Helper.PANEL_LAYOUT_DEFAULTS.stackAnchor)
	elseif field == "stackX" then
		layout.stackX = clampInt(value, -OFFSET_RANGE, OFFSET_RANGE, layout.stackX or Helper.PANEL_LAYOUT_DEFAULTS.stackX)
	elseif field == "stackY" then
		layout.stackY = clampInt(value, -OFFSET_RANGE, OFFSET_RANGE, layout.stackY or Helper.PANEL_LAYOUT_DEFAULTS.stackY)
	elseif field == "stackFont" then
		if type(value) == "string" and value ~= "" then layout.stackFont = value end
	elseif field == "stackFontSize" then
		layout.stackFontSize = clampInt(value, 6, 64, layout.stackFontSize or Helper.PANEL_LAYOUT_DEFAULTS.stackFontSize)
	elseif field == "stackFontStyle" then
		layout.stackFontStyle = normalizeFontStyleChoice(value, layout.stackFontStyle or Helper.PANEL_LAYOUT_DEFAULTS.stackFontStyle)
	elseif field == "chargesAnchor" then
		layout.chargesAnchor = normalizeAnchor(value, layout.chargesAnchor or Helper.PANEL_LAYOUT_DEFAULTS.chargesAnchor)
	elseif field == "chargesX" then
		layout.chargesX = clampInt(value, -OFFSET_RANGE, OFFSET_RANGE, layout.chargesX or Helper.PANEL_LAYOUT_DEFAULTS.chargesX)
	elseif field == "chargesY" then
		layout.chargesY = clampInt(value, -OFFSET_RANGE, OFFSET_RANGE, layout.chargesY or Helper.PANEL_LAYOUT_DEFAULTS.chargesY)
	elseif field == "chargesFont" then
		if type(value) == "string" and value ~= "" then layout.chargesFont = value end
	elseif field == "chargesFontSize" then
		layout.chargesFontSize = clampInt(value, 6, 64, layout.chargesFontSize or Helper.PANEL_LAYOUT_DEFAULTS.chargesFontSize)
	elseif field == "chargesFontStyle" then
		layout.chargesFontStyle = normalizeFontStyleChoice(value, layout.chargesFontStyle or Helper.PANEL_LAYOUT_DEFAULTS.chargesFontStyle)
	elseif field == "cooldownDrawEdge" then
		layout.cooldownDrawEdge = value ~= false
	elseif field == "cooldownDrawBling" then
		layout.cooldownDrawBling = value ~= false
	elseif field == "cooldownDrawSwipe" then
		layout.cooldownDrawSwipe = value ~= false
	elseif field == "cooldownGcdDrawEdge" then
		layout.cooldownGcdDrawEdge = value == true
	elseif field == "cooldownGcdDrawBling" then
		layout.cooldownGcdDrawBling = value == true
	elseif field == "cooldownGcdDrawSwipe" then
		layout.cooldownGcdDrawSwipe = value == true
	elseif field == "showTooltips" then
		layout.showTooltips = value == true
	elseif field == "opacityOutOfCombat" then
		layout.opacityOutOfCombat = normalizeOpacity(value, layout.opacityOutOfCombat or Helper.PANEL_LAYOUT_DEFAULTS.opacityOutOfCombat)
	elseif field == "opacityInCombat" then
		layout.opacityInCombat = normalizeOpacity(value, layout.opacityInCombat or Helper.PANEL_LAYOUT_DEFAULTS.opacityInCombat)
	end

	if field == "iconSize" then CooldownPanels:ReskinMasque() end

	syncEditModeValue(panelId, field, layout[field])

	if not skipRefresh then
		CooldownPanels:ApplyLayout(panelId)
		CooldownPanels:UpdatePreviewIcons(panelId)
		CooldownPanels:UpdateVisibility(panelId)
	end
end

function CooldownPanels:ApplyEditMode(panelId, data)
	local panel = self:GetPanel(panelId)
	if not panel or type(data) ~= "table" then return end
	local runtime = getRuntime(panelId)
	runtime.applyingFromEditMode = true

	applyEditLayout(panelId, "iconSize", data.iconSize, true)
	applyEditLayout(panelId, "spacing", data.spacing, true)
	applyEditLayout(panelId, "direction", data.direction, true)
	applyEditLayout(panelId, "wrapCount", data.wrapCount, true)
	applyEditLayout(panelId, "wrapDirection", data.wrapDirection, true)
	applyEditLayout(panelId, "strata", data.strata, true)
	applyEditLayout(panelId, "stackAnchor", data.stackAnchor, true)
	applyEditLayout(panelId, "stackX", data.stackX, true)
	applyEditLayout(panelId, "stackY", data.stackY, true)
	applyEditLayout(panelId, "stackFont", data.stackFont, true)
	applyEditLayout(panelId, "stackFontSize", data.stackFontSize, true)
	applyEditLayout(panelId, "stackFontStyle", data.stackFontStyle, true)
	applyEditLayout(panelId, "chargesAnchor", data.chargesAnchor, true)
	applyEditLayout(panelId, "chargesX", data.chargesX, true)
	applyEditLayout(panelId, "chargesY", data.chargesY, true)
	applyEditLayout(panelId, "chargesFont", data.chargesFont, true)
	applyEditLayout(panelId, "chargesFontSize", data.chargesFontSize, true)
	applyEditLayout(panelId, "chargesFontStyle", data.chargesFontStyle, true)
	applyEditLayout(panelId, "cooldownDrawEdge", data.cooldownDrawEdge, true)
	applyEditLayout(panelId, "cooldownDrawBling", data.cooldownDrawBling, true)
	applyEditLayout(panelId, "cooldownDrawSwipe", data.cooldownDrawSwipe, true)
	applyEditLayout(panelId, "cooldownGcdDrawEdge", data.cooldownGcdDrawEdge, true)
	applyEditLayout(panelId, "cooldownGcdDrawBling", data.cooldownGcdDrawBling, true)
	applyEditLayout(panelId, "cooldownGcdDrawSwipe", data.cooldownGcdDrawSwipe, true)
	applyEditLayout(panelId, "showTooltips", data.showTooltips, true)
	applyEditLayout(panelId, "opacityOutOfCombat", data.opacityOutOfCombat, true)
	applyEditLayout(panelId, "opacityInCombat", data.opacityInCombat, true)

	runtime.applyingFromEditMode = nil
	self:ApplyLayout(panelId)
	self:UpdatePreviewIcons(panelId)
	self:UpdateVisibility(panelId)
	if self:IsEditorOpen() then self:RefreshEditor() end
end

function CooldownPanels:RegisterEditModePanel(panelId)
	local panel = self:GetPanel(panelId)
	if not panel then return end
	local runtime = getRuntime(panelId)
	if runtime.editModeRegistered then
		if runtime.editModeId and EditMode and EditMode.RefreshFrame then EditMode:RefreshFrame(runtime.editModeId) end
		return
	end
	if not EditMode or not EditMode.RegisterFrame then return end

	local frame = self:EnsurePanelFrame(panelId)
	if not frame then return end

	local editModeId = "cooldownPanel:" .. tostring(panelId)
	runtime.editModeId = editModeId

	panel.layout = panel.layout or Helper.CopyTableShallow(Helper.PANEL_LAYOUT_DEFAULTS)
	local layout = panel.layout
	local anchor = ensurePanelAnchor(panel)
	local panelKey = normalizeId(panelId)
	local countFontPath, countFontSize, countFontStyle = getCountFontDefaults(frame)
	local chargesFontPath, chargesFontSize, chargesFontStyle = getChargesFontDefaults(frame)
	local fontOptions = getFontOptions(countFontPath)
	local chargesFontOptions = getFontOptions(chargesFontPath)
	local function ensureAnchorTable() return ensurePanelAnchor(panel) end
	local function syncPanelPositionFromAnchor()
		local a = ensureAnchorTable()
		if not a then return end
		panel.point = a.point or panel.point or "CENTER"
		panel.x = a.x or panel.x or 0
		panel.y = a.y or panel.y or 0
	end
	local function syncEditModeLayoutFromAnchor()
		if not (EditMode and EditMode.EnsureLayoutData and EditMode.GetActiveLayoutName) then return end
		local a = ensureAnchorTable()
		if not a then return end
		local layoutName = EditMode:GetActiveLayoutName()
		local data = EditMode:EnsureLayoutData(editModeId, layoutName)
		if not data then return end
		data.point = a.point or "CENTER"
		data.relativePoint = a.relativePoint or data.point
		data.x = a.x or 0
		data.y = a.y or 0
	end
	local function applyAnchorPosition()
		syncPanelPositionFromAnchor()
		syncEditModeLayoutFromAnchor()
		CooldownPanels:ApplyPanelPosition(panelId)
		CooldownPanels:UpdateVisibility(panelId)
		if EditMode and EditMode.RefreshFrame then EditMode:RefreshFrame(editModeId) end
		refreshEditModeSettingValues()
	end
	local function wouldCauseLoop(candidateName)
		local targetId = frameNameToPanelId(candidateName)
		if not targetId then return false end
		if targetId == panelKey then return true end
		local seen = {}
		local currentId = targetId
		local limit = 20
		while currentId and limit > 0 do
			if seen[currentId] then break end
			seen[currentId] = true
			if currentId == panelKey then return true end
			local other = CooldownPanels:GetPanel(currentId)
			local otherAnchor = other and ensurePanelAnchor(other)
			currentId = frameNameToPanelId(otherAnchor and otherAnchor.relativeFrame)
			limit = limit - 1
		end
		return false
	end
	local function applyAnchorDefaults(a, target)
		if not a then return end
		if target == "UIParent" then
			a.point = "CENTER"
			a.relativePoint = "CENTER"
			a.x = 0
			a.y = 0
		else
			a.point = "TOPLEFT"
			a.relativePoint = "BOTTOMLEFT"
			a.x = 0
			a.y = 0
		end
	end
	local settings
	if SettingType then
		local function relativeFrameEntries()
			local entries = {}
			local seen = {}
			local function add(key, label)
				if not key or key == "" or seen[key] then return end
				if wouldCauseLoop(key) then return end
				seen[key] = true
				entries[#entries + 1] = { key = key, label = label or key }
			end

			add("UIParent", "UIParent")
			for _, key in ipairs(GENERIC_ANCHOR_ORDER) do
				local info = GENERIC_ANCHORS[key]
				if info then add(key, info.label) end
			end

			local anchorHelper = CooldownPanels.AnchorHelper
			if anchorHelper and anchorHelper.CollectAnchorEntries then anchorHelper:CollectAnchorEntries(entries, seen) end

			local root = CooldownPanels:GetRoot()
			if root and root.panels then
				for id, other in pairs(root.panels) do
					local otherId = normalizeId(id)
					if otherId ~= panelKey then
						local label = string.format("Panel %s: %s", tostring(otherId), other and other.name or "Cooldown Panel")
						add(panelFrameName(otherId), label)
					end
				end
			end

			local a = ensureAnchorTable()
			local cur = a and a.relativeFrame
			if cur and not seen[cur] then
				local anchorHelper = CooldownPanels.AnchorHelper
				local label = anchorHelper and anchorHelper.GetAnchorLabel and anchorHelper:GetAnchorLabel(cur)
				add(cur, label or cur)
			end

			return entries
		end

		local function validateRelativeFrame(a)
			if not a then return "UIParent" end
			local cur = normalizeRelativeFrameName(a.relativeFrame)
			local entries = relativeFrameEntries()
			for _, entry in ipairs(entries) do
				if entry.key == cur then return cur end
			end
			a.relativeFrame = "UIParent"
			return "UIParent"
		end

		settings = {
			{
				name = "Anchor",
				kind = SettingType.Collapsible,
				id = "cooldownPanelAnchor",
				defaultCollapsed = false,
			},
			{
				name = "Relative frame",
				kind = SettingType.Dropdown,
				field = "anchorRelativeFrame",
				parentId = "cooldownPanelAnchor",
				height = 200,
				get = function()
					local a = ensureAnchorTable()
					return validateRelativeFrame(a)
				end,
				set = function(_, value)
					local a = ensureAnchorTable()
					if not a then return end
					local target = normalizeRelativeFrameName(value)
					if wouldCauseLoop(target) then target = "UIParent" end
					a.relativeFrame = target
					applyAnchorDefaults(a, target)
					applyAnchorPosition()
					local anchorHelper = CooldownPanels.AnchorHelper
					if anchorHelper and anchorHelper.MaybeScheduleRefresh then anchorHelper:MaybeScheduleRefresh(target) end
				end,
				generator = function(_, root)
					local entries = relativeFrameEntries()
					for _, entry in ipairs(entries) do
						root:CreateRadio(entry.label, function()
							local a = ensureAnchorTable()
							return validateRelativeFrame(a) == entry.key
						end, function()
							local a = ensureAnchorTable()
							if not a then return end
							local target = entry.key
							if wouldCauseLoop(target) then target = "UIParent" end
							a.relativeFrame = target
							applyAnchorDefaults(a, target)
							applyAnchorPosition()
							local anchorHelper = CooldownPanels.AnchorHelper
							if anchorHelper and anchorHelper.MaybeScheduleRefresh then anchorHelper:MaybeScheduleRefresh(target) end
						end)
					end
				end,
				default = "UIParent",
			},
			{
				name = "Anchor point",
				kind = SettingType.Dropdown,
				field = "anchorPoint",
				parentId = "cooldownPanelAnchor",
				height = 160,
				get = function()
					local a = ensureAnchorTable()
					return normalizeAnchor(a and a.point, "CENTER")
				end,
				set = function(_, value)
					local a = ensureAnchorTable()
					if not a then return end
					a.point = normalizeAnchor(value, a.point or "CENTER")
					if not a.relativePoint then a.relativePoint = a.point end
					applyAnchorPosition()
				end,
				generator = function(_, root)
					for _, option in ipairs(anchorOptions) do
						root:CreateRadio(option.label, function()
							local a = ensureAnchorTable()
							return normalizeAnchor(a and a.point, "CENTER") == option.value
						end, function()
							local a = ensureAnchorTable()
							if not a then return end
							a.point = option.value
							if not a.relativePoint then a.relativePoint = option.value end
							applyAnchorPosition()
						end)
					end
				end,
			},
			{
				name = "Relative point",
				kind = SettingType.Dropdown,
				field = "anchorRelativePoint",
				parentId = "cooldownPanelAnchor",
				height = 160,
				get = function()
					local a = ensureAnchorTable()
					return normalizeAnchor(a and a.relativePoint, a and a.point or "CENTER")
				end,
				set = function(_, value)
					local a = ensureAnchorTable()
					if not a then return end
					a.relativePoint = normalizeAnchor(value, a.relativePoint or "CENTER")
					applyAnchorPosition()
				end,
				generator = function(_, root)
					for _, option in ipairs(anchorOptions) do
						root:CreateRadio(option.label, function()
							local a = ensureAnchorTable()
							return normalizeAnchor(a and a.relativePoint, a and a.point or "CENTER") == option.value
						end, function()
							local a = ensureAnchorTable()
							if not a then return end
							a.relativePoint = option.value
							applyAnchorPosition()
						end)
					end
				end,
			},
			{
				name = "X Offset",
				kind = SettingType.Slider,
				allowInput = true,
				field = "anchorOffsetX",
				parentId = "cooldownPanelAnchor",
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
					local new = tonumber(value) or 0
					if a.x == new then return end
					a.x = new
					applyAnchorPosition()
				end,
				default = 0,
			},
			{
				name = "Y Offset",
				kind = SettingType.Slider,
				allowInput = true,
				field = "anchorOffsetY",
				parentId = "cooldownPanelAnchor",
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
					local new = tonumber(value) or 0
					if a.y == new then return end
					a.y = new
					applyAnchorPosition()
				end,
				default = 0,
			},
			{
				name = "Icon size",
				kind = SettingType.Slider,
				field = "iconSize",
				default = layout.iconSize,
				minValue = 12,
				maxValue = 128,
				valueStep = 1,
				get = function() return layout.iconSize end,
				set = function(_, value) applyEditLayout(panelId, "iconSize", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = "Spacing",
				kind = SettingType.Slider,
				field = "spacing",
				default = layout.spacing,
				minValue = 0,
				maxValue = 50,
				valueStep = 1,
				get = function() return layout.spacing end,
				set = function(_, value) applyEditLayout(panelId, "spacing", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = "Direction",
				kind = SettingType.Dropdown,
				field = "direction",
				height = 120,
				get = function() return normalizeDirection(layout.direction, Helper.PANEL_LAYOUT_DEFAULTS.direction) end,
				set = function(_, value) applyEditLayout(panelId, "direction", value) end,
				generator = function(_, root)
					for _, option in ipairs(directionOptions) do
						root:CreateRadio(
							option.label,
							function() return normalizeDirection(layout.direction, Helper.PANEL_LAYOUT_DEFAULTS.direction) == option.value end,
							function() applyEditLayout(panelId, "direction", option.value) end
						)
					end
				end,
			},
			{
				name = "Wrap",
				kind = SettingType.Slider,
				field = "wrapCount",
				default = layout.wrapCount or 0,
				minValue = 0,
				maxValue = 40,
				valueStep = 1,
				get = function() return layout.wrapCount or 0 end,
				set = function(_, value) applyEditLayout(panelId, "wrapCount", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = "Wrap direction",
				kind = SettingType.Dropdown,
				field = "wrapDirection",
				height = 120,
				get = function() return normalizeDirection(layout.wrapDirection, Helper.PANEL_LAYOUT_DEFAULTS.wrapDirection or "DOWN") end,
				set = function(_, value) applyEditLayout(panelId, "wrapDirection", value) end,
				generator = function(_, root)
					for _, option in ipairs(directionOptions) do
						root:CreateRadio(
							option.label,
							function() return normalizeDirection(layout.wrapDirection, Helper.PANEL_LAYOUT_DEFAULTS.wrapDirection or "DOWN") == option.value end,
							function() applyEditLayout(panelId, "wrapDirection", option.value) end
						)
					end
				end,
			},
			{
				name = "Strata",
				kind = SettingType.Dropdown,
				field = "strata",
				height = 200,
				get = function() return normalizeStrata(layout.strata, Helper.PANEL_LAYOUT_DEFAULTS.strata) end,
				set = function(_, value) applyEditLayout(panelId, "strata", value) end,
				generator = function(_, root)
					for _, option in ipairs(STRATA_ORDER) do
						root:CreateRadio(
							option,
							function() return normalizeStrata(layout.strata, Helper.PANEL_LAYOUT_DEFAULTS.strata) == option end,
							function() applyEditLayout(panelId, "strata", option) end
						)
					end
				end,
			},
			{
				name = L["CooldownPanelShowTooltips"] or "Show tooltips",
				kind = SettingType.Checkbox,
				field = "showTooltips",
				default = layout.showTooltips == true,
				get = function() return layout.showTooltips == true end,
				set = function(_, value) applyEditLayout(panelId, "showTooltips", value) end,
			},
			{
				name = L["CooldownPanelOpacityOutOfCombat"] or "Opacity (out of combat)",
				kind = SettingType.Slider,
				field = "opacityOutOfCombat",
				default = normalizeOpacity(layout.opacityOutOfCombat, Helper.PANEL_LAYOUT_DEFAULTS.opacityOutOfCombat),
				minValue = 0,
				maxValue = 1,
				valueStep = 0.05,
				allowInput = true,
				get = function() return normalizeOpacity(layout.opacityOutOfCombat, Helper.PANEL_LAYOUT_DEFAULTS.opacityOutOfCombat) end,
				set = function(_, value) applyEditLayout(panelId, "opacityOutOfCombat", value) end,
				formatter = function(value)
					local num = tonumber(value) or 0
					return tostring(math.floor((num * 100) + 0.5)) .. "%"
				end,
			},
			{
				name = L["CooldownPanelOpacityInCombat"] or "Opacity (in combat)",
				kind = SettingType.Slider,
				field = "opacityInCombat",
				default = normalizeOpacity(layout.opacityInCombat, Helper.PANEL_LAYOUT_DEFAULTS.opacityInCombat),
				minValue = 0,
				maxValue = 1,
				valueStep = 0.05,
				allowInput = true,
				get = function() return normalizeOpacity(layout.opacityInCombat, Helper.PANEL_LAYOUT_DEFAULTS.opacityInCombat) end,
				set = function(_, value) applyEditLayout(panelId, "opacityInCombat", value) end,
				formatter = function(value)
					local num = tonumber(value) or 0
					return tostring(math.floor((num * 100) + 0.5)) .. "%"
				end,
			},
			{
				name = L["CooldownPanelStacksHeader"] or "Stacks / Item Count",
				kind = SettingType.Collapsible,
				id = "cooldownPanelStacks",
				defaultCollapsed = true,
			},
			{
				name = L["CooldownPanelCountAnchor"] or "Count anchor",
				kind = SettingType.Dropdown,
				field = "stackAnchor",
				parentId = "cooldownPanelStacks",
				height = 160,
				get = function() return normalizeAnchor(layout.stackAnchor, Helper.PANEL_LAYOUT_DEFAULTS.stackAnchor) end,
				set = function(_, value) applyEditLayout(panelId, "stackAnchor", value) end,
				generator = function(_, root)
					for _, option in ipairs(anchorOptions) do
						root:CreateRadio(
							option.label,
							function() return normalizeAnchor(layout.stackAnchor, Helper.PANEL_LAYOUT_DEFAULTS.stackAnchor) == option.value end,
							function() applyEditLayout(panelId, "stackAnchor", option.value) end
						)
					end
				end,
			},
			{
				name = L["CooldownPanelCountOffsetX"] or "Count X",
				kind = SettingType.Slider,
				field = "stackX",
				parentId = "cooldownPanelStacks",
				default = layout.stackX or Helper.PANEL_LAYOUT_DEFAULTS.stackX,
				minValue = -OFFSET_RANGE,
				maxValue = OFFSET_RANGE,
				valueStep = 1,
				get = function() return layout.stackX or Helper.PANEL_LAYOUT_DEFAULTS.stackX end,
				set = function(_, value) applyEditLayout(panelId, "stackX", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = L["CooldownPanelCountOffsetY"] or "Count Y",
				kind = SettingType.Slider,
				field = "stackY",
				parentId = "cooldownPanelStacks",
				default = layout.stackY or Helper.PANEL_LAYOUT_DEFAULTS.stackY,
				minValue = -OFFSET_RANGE,
				maxValue = OFFSET_RANGE,
				valueStep = 1,
				get = function() return layout.stackY or Helper.PANEL_LAYOUT_DEFAULTS.stackY end,
				set = function(_, value) applyEditLayout(panelId, "stackY", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = L["Font"] or "Font",
				kind = SettingType.Dropdown,
				field = "stackFont",
				parentId = "cooldownPanelStacks",
				height = 220,
				get = function() return layout.stackFont or countFontPath end,
				set = function(_, value) applyEditLayout(panelId, "stackFont", value) end,
				generator = function(_, root)
					for _, option in ipairs(fontOptions) do
						root:CreateRadio(option.label, function() return (layout.stackFont or countFontPath) == option.value end, function() applyEditLayout(panelId, "stackFont", option.value) end)
					end
				end,
			},
			{
				name = L["CooldownPanelFontStyle"] or "Font style",
				kind = SettingType.Dropdown,
				field = "stackFontStyle",
				parentId = "cooldownPanelStacks",
				height = 120,
				get = function() return normalizeFontStyleChoice(layout.stackFontStyle, countFontStyle) end,
				set = function(_, value) applyEditLayout(panelId, "stackFontStyle", value) end,
				generator = function(_, root)
					for _, option in ipairs(fontStyleOptions) do
						root:CreateRadio(
							option.label,
							function() return normalizeFontStyleChoice(layout.stackFontStyle, countFontStyle) == option.value end,
							function() applyEditLayout(panelId, "stackFontStyle", option.value) end
						)
					end
				end,
			},
			{
				name = L["FontSize"] or "Font size",
				kind = SettingType.Slider,
				field = "stackFontSize",
				parentId = "cooldownPanelStacks",
				default = layout.stackFontSize or countFontSize or 12,
				minValue = 6,
				maxValue = 64,
				valueStep = 1,
				get = function() return layout.stackFontSize or countFontSize or 12 end,
				set = function(_, value) applyEditLayout(panelId, "stackFontSize", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = L["CooldownPanelChargesHeader"] or "Charges",
				kind = SettingType.Collapsible,
				id = "cooldownPanelCharges",
				defaultCollapsed = true,
			},
			{
				name = L["CooldownPanelChargesAnchor"] or "Charges anchor",
				kind = SettingType.Dropdown,
				field = "chargesAnchor",
				parentId = "cooldownPanelCharges",
				height = 160,
				get = function() return normalizeAnchor(layout.chargesAnchor, Helper.PANEL_LAYOUT_DEFAULTS.chargesAnchor) end,
				set = function(_, value) applyEditLayout(panelId, "chargesAnchor", value) end,
				generator = function(_, root)
					for _, option in ipairs(anchorOptions) do
						root:CreateRadio(
							option.label,
							function() return normalizeAnchor(layout.chargesAnchor, Helper.PANEL_LAYOUT_DEFAULTS.chargesAnchor) == option.value end,
							function() applyEditLayout(panelId, "chargesAnchor", option.value) end
						)
					end
				end,
			},
			{
				name = L["CooldownPanelChargesOffsetX"] or "Charges X",
				kind = SettingType.Slider,
				field = "chargesX",
				parentId = "cooldownPanelCharges",
				default = layout.chargesX or Helper.PANEL_LAYOUT_DEFAULTS.chargesX,
				minValue = -OFFSET_RANGE,
				maxValue = OFFSET_RANGE,
				valueStep = 1,
				get = function() return layout.chargesX or Helper.PANEL_LAYOUT_DEFAULTS.chargesX end,
				set = function(_, value) applyEditLayout(panelId, "chargesX", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = L["CooldownPanelChargesOffsetY"] or "Charges Y",
				kind = SettingType.Slider,
				field = "chargesY",
				parentId = "cooldownPanelCharges",
				default = layout.chargesY or Helper.PANEL_LAYOUT_DEFAULTS.chargesY,
				minValue = -OFFSET_RANGE,
				maxValue = OFFSET_RANGE,
				valueStep = 1,
				get = function() return layout.chargesY or Helper.PANEL_LAYOUT_DEFAULTS.chargesY end,
				set = function(_, value) applyEditLayout(panelId, "chargesY", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = L["Font"] or "Font",
				kind = SettingType.Dropdown,
				field = "chargesFont",
				parentId = "cooldownPanelCharges",
				height = 220,
				get = function() return layout.chargesFont or chargesFontPath end,
				set = function(_, value) applyEditLayout(panelId, "chargesFont", value) end,
				generator = function(_, root)
					for _, option in ipairs(chargesFontOptions) do
						root:CreateRadio(
							option.label,
							function() return (layout.chargesFont or chargesFontPath) == option.value end,
							function() applyEditLayout(panelId, "chargesFont", option.value) end
						)
					end
				end,
			},
			{
				name = L["CooldownPanelFontStyle"] or "Font style",
				kind = SettingType.Dropdown,
				field = "chargesFontStyle",
				parentId = "cooldownPanelCharges",
				height = 120,
				get = function() return normalizeFontStyleChoice(layout.chargesFontStyle, chargesFontStyle) end,
				set = function(_, value) applyEditLayout(panelId, "chargesFontStyle", value) end,
				generator = function(_, root)
					for _, option in ipairs(fontStyleOptions) do
						root:CreateRadio(
							option.label,
							function() return normalizeFontStyleChoice(layout.chargesFontStyle, chargesFontStyle) == option.value end,
							function() applyEditLayout(panelId, "chargesFontStyle", option.value) end
						)
					end
				end,
			},
			{
				name = L["FontSize"] or "Font size",
				kind = SettingType.Slider,
				field = "chargesFontSize",
				parentId = "cooldownPanelCharges",
				default = layout.chargesFontSize or chargesFontSize or 12,
				minValue = 6,
				maxValue = 64,
				valueStep = 1,
				get = function() return layout.chargesFontSize or chargesFontSize or 12 end,
				set = function(_, value) applyEditLayout(panelId, "chargesFontSize", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = L["CooldownPanelCooldownHeader"] or "Cooldown",
				kind = SettingType.Collapsible,
				id = "cooldownPanelCooldown",
				defaultCollapsed = true,
			},
			{
				name = L["CooldownPanelDrawEdge"] or "Draw edge",
				kind = SettingType.Checkbox,
				field = "cooldownDrawEdge",
				parentId = "cooldownPanelCooldown",
				default = layout.cooldownDrawEdge ~= false,
				get = function() return layout.cooldownDrawEdge ~= false end,
				set = function(_, value) applyEditLayout(panelId, "cooldownDrawEdge", value) end,
			},
			{
				name = L["CooldownPanelDrawBling"] or "Draw bling",
				kind = SettingType.Checkbox,
				field = "cooldownDrawBling",
				parentId = "cooldownPanelCooldown",
				default = layout.cooldownDrawBling ~= false,
				get = function() return layout.cooldownDrawBling ~= false end,
				set = function(_, value) applyEditLayout(panelId, "cooldownDrawBling", value) end,
			},
			{
				name = L["CooldownPanelDrawSwipe"] or "Draw swipe",
				kind = SettingType.Checkbox,
				field = "cooldownDrawSwipe",
				parentId = "cooldownPanelCooldown",
				default = layout.cooldownDrawSwipe ~= false,
				get = function() return layout.cooldownDrawSwipe ~= false end,
				set = function(_, value) applyEditLayout(panelId, "cooldownDrawSwipe", value) end,
			},
			{
				name = L["CooldownPanelDrawEdgeGcd"] or "Draw edge on GCD",
				kind = SettingType.Checkbox,
				field = "cooldownGcdDrawEdge",
				parentId = "cooldownPanelCooldown",
				default = layout.cooldownGcdDrawEdge == true,
				get = function() return layout.cooldownGcdDrawEdge == true end,
				set = function(_, value) applyEditLayout(panelId, "cooldownGcdDrawEdge", value) end,
			},
			{
				name = L["CooldownPanelDrawBlingGcd"] or "Draw bling on GCD",
				kind = SettingType.Checkbox,
				field = "cooldownGcdDrawBling",
				parentId = "cooldownPanelCooldown",
				default = layout.cooldownGcdDrawBling == true,
				get = function() return layout.cooldownGcdDrawBling == true end,
				set = function(_, value) applyEditLayout(panelId, "cooldownGcdDrawBling", value) end,
			},
			{
				name = L["CooldownPanelDrawSwipeGcd"] or "Draw swipe on GCD",
				kind = SettingType.Checkbox,
				field = "cooldownGcdDrawSwipe",
				parentId = "cooldownPanelCooldown",
				default = layout.cooldownGcdDrawSwipe == true,
				get = function() return layout.cooldownGcdDrawSwipe == true end,
				set = function(_, value) applyEditLayout(panelId, "cooldownGcdDrawSwipe", value) end,
			},
		}
	end

	EditMode:RegisterFrame(editModeId, {
		frame = frame,
		title = panel.name or "Cooldown Panel",
		layoutDefaults = {
			point = (anchor and anchor.point) or panel.point or "CENTER",
			relativePoint = (anchor and anchor.relativePoint) or (anchor and anchor.point) or panel.point or "CENTER",
			x = (anchor and anchor.x) or panel.x or 0,
			y = (anchor and anchor.y) or panel.y or 0,
			iconSize = layout.iconSize,
			spacing = layout.spacing,
			direction = normalizeDirection(layout.direction, Helper.PANEL_LAYOUT_DEFAULTS.direction),
			wrapCount = layout.wrapCount or 0,
			wrapDirection = normalizeDirection(layout.wrapDirection, Helper.PANEL_LAYOUT_DEFAULTS.wrapDirection or "DOWN"),
			strata = normalizeStrata(layout.strata, Helper.PANEL_LAYOUT_DEFAULTS.strata),
			stackAnchor = normalizeAnchor(layout.stackAnchor, Helper.PANEL_LAYOUT_DEFAULTS.stackAnchor),
			stackX = layout.stackX or Helper.PANEL_LAYOUT_DEFAULTS.stackX,
			stackY = layout.stackY or Helper.PANEL_LAYOUT_DEFAULTS.stackY,
			stackFont = layout.stackFont or countFontPath,
			stackFontSize = layout.stackFontSize or countFontSize or 12,
			stackFontStyle = normalizeFontStyleChoice(layout.stackFontStyle, countFontStyle),
			chargesAnchor = normalizeAnchor(layout.chargesAnchor, Helper.PANEL_LAYOUT_DEFAULTS.chargesAnchor),
			chargesX = layout.chargesX or Helper.PANEL_LAYOUT_DEFAULTS.chargesX,
			chargesY = layout.chargesY or Helper.PANEL_LAYOUT_DEFAULTS.chargesY,
			chargesFont = layout.chargesFont or chargesFontPath,
			chargesFontSize = layout.chargesFontSize or chargesFontSize or 12,
			chargesFontStyle = normalizeFontStyleChoice(layout.chargesFontStyle, chargesFontStyle),
			cooldownDrawEdge = layout.cooldownDrawEdge ~= false,
			cooldownDrawBling = layout.cooldownDrawBling ~= false,
			cooldownDrawSwipe = layout.cooldownDrawSwipe ~= false,
			cooldownGcdDrawEdge = layout.cooldownGcdDrawEdge == true,
			cooldownGcdDrawBling = layout.cooldownGcdDrawBling == true,
			cooldownGcdDrawSwipe = layout.cooldownGcdDrawSwipe == true,
			opacityOutOfCombat = normalizeOpacity(layout.opacityOutOfCombat, Helper.PANEL_LAYOUT_DEFAULTS.opacityOutOfCombat),
			opacityInCombat = normalizeOpacity(layout.opacityInCombat, Helper.PANEL_LAYOUT_DEFAULTS.opacityInCombat),
			showTooltips = layout.showTooltips == true,
		},
		onApply = function(_, _, data)
			local a = ensureAnchorTable()
			if a and anchorUsesUIParent(a) and data and data.point then
				a.point = data.point or a.point or "CENTER"
				a.relativePoint = data.relativePoint or a.relativePoint or a.point
				a.x = data.x or a.x or 0
				a.y = data.y or a.y or 0
				syncPanelPositionFromAnchor()
			elseif a and data and data.point then
				syncEditModeLayoutFromAnchor()
			end
			self:ApplyEditMode(panelId, data)
			refreshEditModeSettingValues()
		end,
		onPositionChanged = function(_, _, data) self:HandlePositionChanged(panelId, data) end,
		onEnter = function() self:ShowEditModeHint(panelId, true) end,
		onExit = function() self:ShowEditModeHint(panelId, false) end,
		isEnabled = function() return panel.enabled ~= false end,
		relativeTo = function() return resolveAnchorFrame(ensureAnchorTable()) end,
		allowDrag = function() return anchorUsesUIParent(ensureAnchorTable()) end,
		settings = settings,
		showOutsideEditMode = true,
	})

	runtime.editModeRegistered = true
	self:UpdateVisibility(panelId)
end

function CooldownPanels:EnsureEditMode()
	local root = ensureRoot()
	if not root then return end
	Helper.SyncOrder(root.order, root.panels)
	for _, panelId in ipairs(root.order) do
		self:RegisterEditModePanel(panelId)
	end
	for panelId in pairs(root.panels) do
		if not containsId(root.order, panelId) then self:RegisterEditModePanel(panelId) end
	end
end

local editModeCallbacksRegistered = false
local function registerEditModeCallbacks()
	if editModeCallbacksRegistered then return end
	if addon.EditModeLib and addon.EditModeLib.RegisterCallback then
		addon.EditModeLib:RegisterCallback("enter", function() CooldownPanels:RefreshAllPanels() end)
		addon.EditModeLib:RegisterCallback("exit", function() CooldownPanels:RefreshAllPanels() end)
	end
	editModeCallbacksRegistered = true
end

local function refreshPanelsForSpell(spellId)
	local id = tonumber(spellId)
	if not id then return false end
	local index = CooldownPanels.runtime and CooldownPanels.runtime.spellIndex
	local panels = index and index[id]
	if not panels then return false end
	for panelId in pairs(panels) do
		if CooldownPanels:GetPanel(panelId) then CooldownPanels:RefreshPanel(panelId) end
	end
	return true
end

local function ensureUpdateFrame()
	if CooldownPanels.runtime and CooldownPanels.runtime.updateFrame then return end
	local frame = CreateFrame("Frame")
	frame:SetScript("OnEvent", function(_, event, ...)
		if event == "ADDON_LOADED" then
			local name = ...
			local anchorHelper = CooldownPanels.AnchorHelper
			if anchorHelper and anchorHelper.HandleAddonLoaded then anchorHelper:HandleAddonLoaded(name) end
			if name == "Masque" then
				CooldownPanels:RegisterMasqueButtons()
				CooldownPanels:ReskinMasque()
			end
			return
		end
		if event == "PLAYER_LOGIN" then
			local anchorHelper = CooldownPanels.AnchorHelper
			if anchorHelper and anchorHelper.HandlePlayerLogin then anchorHelper:HandlePlayerLogin() end
			return
		end
		if event == "UNIT_AURA" then
			local unit = ...
			if unit ~= "player" then return end
		end
		if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
			if refreshPanelsForSpell(...) then return end
		end
		CooldownPanels:RequestUpdate()
	end)
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:RegisterEvent("ADDON_LOADED")
	frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	frame:RegisterEvent("SPELL_UPDATE_CHARGES")
	frame:RegisterEvent("SPELLS_CHANGED")
	frame:RegisterEvent("UNIT_AURA")
	frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	frame:RegisterEvent("BAG_UPDATE_DELAYED")
	frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
	frame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	CooldownPanels.runtime = CooldownPanels.runtime or {}
	CooldownPanels.runtime.updateFrame = frame
end

function CooldownPanels:RequestUpdate()
	self.runtime = self.runtime or {}
	if self.runtime.updatePending then return end
	self.runtime.updatePending = true
	C_Timer.After(0, function()
		self.runtime.updatePending = nil
		CooldownPanels:RefreshAllPanels()
	end)
end

function CooldownPanels:Init()
	self:NormalizeAll()
	self:EnsureEditMode()
	self:RefreshAllPanels()
	ensureUpdateFrame()
	registerEditModeCallbacks()
end

function addon.Aura.functions.InitCooldownPanels()
	if CooldownPanels and CooldownPanels.Init then CooldownPanels:Init() end
end
