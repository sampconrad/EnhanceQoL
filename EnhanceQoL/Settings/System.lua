local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local getCVarOptionState = addon.functions.GetCVarOptionState or function() return false end
local setCVarOptionState = addon.functions.SetCVarOptionState or function() end

local function applyParentSection(entries, section)
	for _, entry in ipairs(entries or {}) do
		entry.parentSection = section
		if entry.children then applyParentSection(entry.children, section) end
	end
end

local cGeneral = addon.SettingsLayout.rootGENERAL
addon.SettingsLayout.systemCategory = cGeneral

local movementExpandable = addon.functions.SettingsCreateExpandableSection(cGeneral, {
	name = L["cvarCategoryMovementInput"] or "Movement & Input",
	expanded = false,
	colorizeTitle = false,
})

local movementData = {
	{
		var = "autoDismount",
		text = L["autoDismount"],
		get = function() return getCVarOptionState("autoDismount") end,
		func = function(value) setCVarOptionState("autoDismount", value) end,
		default = false,
	},
	{
		var = "autoDismountFlying",
		text = L["autoDismountFlying"],
		get = function() return getCVarOptionState("autoDismountFlying") end,
		func = function(value) setCVarOptionState("autoDismountFlying", value) end,
		default = false,
	},
}

table.sort(movementData, function(a, b) return a.text < b.text end)
applyParentSection(movementData, movementExpandable)
addon.functions.SettingsCreateCheckboxes(cGeneral, movementData)

local dialogExpandable = addon.functions.SettingsCreateExpandableSection(cGeneral, {
	name = L["DialogsAndConfirmations"] or "Dialogs & Confirmations",
	expanded = false,
	colorizeTitle = false,
})

addon.functions.SettingsCreateCheckbox(cGeneral, {
	var = "deleteItemFillDialog",
	text = L["deleteItemFillDialog"]:format(DELETE_ITEM_CONFIRM_STRING),
	desc = L["deleteItemFillDialogDesc"],
	func = function(value) addon.db["deleteItemFillDialog"] = value end,
	parentSection = dialogExpandable,
})

local function isDialogConfirmSelected(key)
	if key == "patron" then return addon.db["confirmPatronOrderDialog"] == true end
	if key == "trade" then return addon.db["confirmTimerRemovalTrade"] == true end
	if key == "enchant" then return addon.db["confirmReplaceEnchant"] == true end
	if key == "socket" then return addon.db["confirmSocketReplace"] == true end
	if key == "token" then return addon.db["confirmPurchaseTokenItem"] == true end
	if key == "highcost" then return addon.db["confirmHighCostItem"] == true end
	return false
end

local function setDialogConfirmOption(key, value)
	local enabled = value and true or false
	if key == "patron" then
		addon.db["confirmPatronOrderDialog"] = enabled
	elseif key == "trade" then
		addon.db["confirmTimerRemovalTrade"] = enabled
	elseif key == "enchant" then
		addon.db["confirmReplaceEnchant"] = enabled
	elseif key == "socket" then
		addon.db["confirmSocketReplace"] = enabled
	elseif key == "token" then
		addon.db["confirmPurchaseTokenItem"] = enabled
	elseif key == "highcost" then
		addon.db["confirmHighCostItem"] = enabled
	end
end

local function applyDialogConfirmSelection(selection)
	selection = selection or {}
	addon.db["confirmPatronOrderDialog"] = selection.patron == true
	addon.db["confirmTimerRemovalTrade"] = selection.trade == true
	addon.db["confirmReplaceEnchant"] = selection.enchant == true
	addon.db["confirmSocketReplace"] = selection.socket == true
	addon.db["confirmPurchaseTokenItem"] = selection.token == true
	addon.db["confirmHighCostItem"] = selection.highcost == true
end

addon.functions.SettingsCreateMultiDropdown(cGeneral, {
	var = "dialogAutoConfirm",
	text = L["dialogAutoConfirm"] or "Auto-confirm dialogs",
	options = {
		{
			value = "patron",
			text = (L["confirmPatronOrderDialog"]):format(PROFESSIONS_CRAFTER_ORDER_TAB_NPC),
			tooltip = L["confirmPatronOrderDialogDesc"],
		},
		{
			value = "trade",
			text = L["confirmTimerRemovalTrade"],
			tooltip = L["confirmTimerRemovalTradeDesc"],
		},
		{
			value = "enchant",
			text = L["confirmReplaceEnchant"],
			tooltip = L["confirmReplaceEnchantDesc"],
		},
		{
			value = "socket",
			text = L["confirmSocketReplace"],
			tooltip = L["confirmSocketReplaceDesc"],
		},
		{
			value = "token",
			text = L["confirmPurchaseTokenItem"],
			tooltip = L["confirmPurchaseTokenItemDesc"],
		},
		{
			value = "highcost",
			text = L["confirmHighCostItem"],
			tooltip = L["confirmHighCostItemDesc"],
		},
	},
	isSelectedFunc = function(key) return isDialogConfirmSelected(key) end,
	setSelectedFunc = function(key, selected) setDialogConfirmOption(key, selected) end,
	setSelection = applyDialogConfirmSelection,
	parentSection = dialogExpandable,
})

local utilitiesExpandable = addon.functions.SettingsCreateExpandableSection(cGeneral, {
	name = L["UIUtilities"] or "UI Utilities",
	expanded = false,
	colorizeTitle = false,
})

addon.functions.SettingsCreateCheckbox(cGeneral, {
	var = "autoUnwrapMounts",
	text = L["autoUnwrapMounts"],
	desc = L["autoUnwrapMountsDesc"],
	func = function(v)
		addon.db["autoUnwrapMounts"] = v
		if addon.functions.UpdateAutoUnwrapWatcher then addon.functions.UpdateAutoUnwrapWatcher() end
	end,
	parentSection = utilitiesExpandable,
})

addon.functions.SettingsCreateCheckbox(cGeneral, {
	var = "showTrainAllButton",
	text = L["showTrainAllButton"],
	desc = L["showTrainAllButtonDesc"],
	func = function(v)
		addon.db["showTrainAllButton"] = v
		if addon.functions.applyTrainAllButton then addon.functions.applyTrainAllButton() end
	end,
	parentSection = utilitiesExpandable,
})

addon.functions.SettingsCreateCheckbox(cGeneral, {
	var = "hideScreenshotStatus",
	text = L["hideScreenshotStatus"],
	desc = L["hideScreenshotStatusDesc"],
	func = function(v)
		addon.db["hideScreenshotStatus"] = v
		if addon.functions.toggleScreenshotStatus then addon.functions.toggleScreenshotStatus(v) end
	end,
	parentSection = utilitiesExpandable,
})

addon.functions.SettingsCreateCheckbox(cGeneral, {
	var = "enableCooldownManagerSlashCommand",
	text = L["enableCooldownManagerSlashCommand"],
	desc = L["enableCooldownManagerSlashCommandDesc"],
	func = function(value)
		addon.db["enableCooldownManagerSlashCommand"] = value
		if value then
			addon.functions.registerCooldownManagerSlashCommand()
		else
			addon.variables.requireReload = true
		end
	end,
	default = false,
	parentSection = utilitiesExpandable,
})
addon.functions.SettingsCreateCheckbox(cGeneral, {
	var = "enablePullTimerSlashCommand",
	text = L["enablePullTimerSlashCommand"],
	desc = L["enablePullTimerSlashCommandDesc"],
	func = function(value)
		addon.db["enablePullTimerSlashCommand"] = value
		if value then
			addon.functions.registerPullTimerSlashCommand()
		else
			addon.variables.requireReload = true
		end
	end,
	default = false,
	parentSection = utilitiesExpandable,
})
addon.functions.SettingsCreateCheckbox(cGeneral, {
	var = "enableEditModeSlashCommand",
	text = L["enableEditModeSlashCommand"],
	desc = L["enableEditModeSlashCommandDesc"],
	func = function(value)
		addon.db["enableEditModeSlashCommand"] = value
		if value then
			addon.functions.registerEditModeSlashCommand()
		else
			addon.variables.requireReload = true
		end
	end,
	default = false,
	parentSection = utilitiesExpandable,
})
addon.functions.SettingsCreateCheckbox(cGeneral, {
	var = "enableQuickKeybindSlashCommand",
	text = L["enableQuickKeybindSlashCommand"],
	desc = L["enableQuickKeybindSlashCommandDesc"],
	func = function(value)
		addon.db["enableQuickKeybindSlashCommand"] = value
		if value then
			addon.functions.registerQuickKeybindSlashCommand()
		else
			addon.variables.requireReload = true
		end
	end,
	default = false,
	parentSection = utilitiesExpandable,
})
addon.functions.SettingsCreateCheckbox(cGeneral, {
	var = "enableReloadUISlashCommand",
	text = L["enableReloadUISlashCommand"],
	desc = L["enableReloadUISlashCommandDesc"],
	func = function(value)
		addon.db["enableReloadUISlashCommand"] = value
		if value then
			addon.functions.registerReloadUISlashCommand()
		else
			addon.variables.requireReload = true
		end
	end,
	default = false,
	parentSection = utilitiesExpandable,
})

local systemExpandable = addon.functions.SettingsCreateExpandableSection(cGeneral, {
	name = L["SystemAndDebug"] or "System & Debug",
	expanded = false,
	colorizeTitle = false,
})

local systemData = {
	{
		var = "cvarPersistenceEnabled",
		text = L["cvarPersistence"],
		desc = L["cvarPersistenceDesc"],
		func = function(key)
			addon.db["cvarPersistenceEnabled"] = key
			if addon.functions.initializePersistentCVars then addon.functions.initializePersistentCVars() end
		end,
		default = false,
	},
	{
		var = "scriptErrors",
		text = L["scriptErrors"],
		get = function() return getCVarOptionState("scriptErrors") end,
		func = function(value) setCVarOptionState("scriptErrors", value) end,
		default = false,
	},
	{
		var = "showTutorials",
		text = L["showTutorials"],
		get = function() return getCVarOptionState("showTutorials") end,
		func = function(value) setCVarOptionState("showTutorials", value) end,
		default = false,
	},
	{
		var = "UberTooltips",
		text = L["UberTooltips"],
		get = function() return getCVarOptionState("UberTooltips") end,
		func = function(value) setCVarOptionState("UberTooltips", value) end,
		default = false,
	},
}

applyParentSection(systemData, systemExpandable)
addon.functions.SettingsCreateCheckboxes(cGeneral, systemData)

----- REGION END

function addon.functions.initSystem() end

local eventHandlers = {}

local function registerEvents(frame)
	for event in pairs(eventHandlers) do
		frame:RegisterEvent(event)
	end
end

local function eventHandler(self, event, ...)
	if eventHandlers[event] then eventHandlers[event](...) end
end

local frameLoad = CreateFrame("Frame")

registerEvents(frameLoad)
frameLoad:SetScript("OnEvent", eventHandler)
