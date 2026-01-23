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

Helper.PANEL_LAYOUT_DEFAULTS = {
	iconSize = 36,
	spacing = 2,
	direction = "RIGHT",
	wrapCount = 0,
	wrapDirection = "DOWN",
	strata = "MEDIUM",
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
	cooldownDrawEdge = true,
	cooldownDrawBling = true,
	cooldownDrawSwipe = true,
	cooldownGcdDrawEdge = false,
	cooldownGcdDrawBling = false,
	cooldownGcdDrawSwipe = false,
	showTooltips = false,
}

Helper.ENTRY_DEFAULTS = {
	alwaysShow = true,
	showCooldown = true,
	showCooldownText = true,
	showCharges = false,
	showStacks = false,
	showWhenEmpty = false,
	showWhenNoCooldown = false,
	glowReady = false,
	glowDuration = 0,
	soundReady = false,
	soundReadyFile = "None",
}

local function spellHasCharges(spellId)
	if not spellId then return false end
	if not (C_Spell and C_Spell.GetSpellCharges) then return false end
	local info = C_Spell.GetSpellCharges(spellId)
	if info == nil then return false end
	local issecretvalue = _G.issecretvalue
	if issecretvalue and issecretvalue(info) then return false end
	return true
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
	entry.alwaysShow = true
	entry.showCooldown = true
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
