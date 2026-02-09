local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
local drinkMacroName = "EnhanceQoLDrinkMacro"

local UnitAffectingCombat = UnitAffectingCombat
local InCombatLockdown = InCombatLockdown
local UnitPowerMax = UnitPowerMax
local UnitLevel = UnitLevel
local GetMacroInfo = GetMacroInfo
local EditMacro = EditMacro
local CreateMacro = CreateMacro

-- Recuperate info is shared via addon.Recuperate (Init.lua)

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_DrinkMacro")
local LSM = LibStub("LibSharedMedia-3.0")

local function isDrinkMacroEnabled() return addon.db and addon.db.drinkMacroEnabled == true end
local function isMageFoodReminderEnabled() return addon.db and addon.db.mageFoodReminder == true end
local function shouldBuildDrinkData() return isDrinkMacroEnabled() or isMageFoodReminderEnabled() end

local function shouldUpdateRecuperateForDrinks() return isDrinkMacroEnabled() and addon.db.allowRecuperate == true end

local function createMacroIfMissing()
	-- Respect enable toggle and guard against protected calls while in combat lockdown
	if not addon.db.drinkMacroEnabled then return end
	if InCombatLockdown and InCombatLockdown() then return end
	if GetMacroInfo(drinkMacroName) == nil then CreateMacro(drinkMacroName, "INV_Misc_QuestionMark") end
end

-- Find first available mana potion from user-defined list (preserves user order)
local function findBestManaPotion()
	if not addon.db or not addon.db.useManaPotionInCombat then return nil end
	local list = (addon.Drinks and addon.Drinks.manaPotions) or {}
	local playerLevel = UnitLevel("player")
	for i = 1, #list do
		local e = list[i]
		if e and e.id and (e.requiredLevel or 1) <= playerLevel then
			if (C_Item.GetItemCount(e.id, false, false) or 0) > 0 then return "item:" .. e.id end
		end
	end
	return nil
end

local function buildMacroString(drinkItem, manaPotionItem)
	local resetType = "combat"
	local recuperateString = ""

	if addon.db.allowRecuperate and addon.Recuperate and addon.Recuperate.name and addon.Recuperate.known then recuperateString = "\n/cast " .. addon.Recuperate.name end

	local parts = { "#showtooltip" }

	-- Use mana potion during combat, if enabled and found
	if manaPotionItem then table.insert(parts, string.format("/use [combat] %s", manaPotionItem)) end

	if drinkItem == nil then
		if recuperateString ~= "" then table.insert(parts, recuperateString) end
		return table.concat(parts, "\n")
	else
		-- Keep legacy behavior: castsequence for drinks, optional recuperate
		table.insert(parts, string.format("/castsequence reset=%s %s", resetType, drinkItem))
		if recuperateString ~= "" then table.insert(parts, recuperateString) end
		return table.concat(parts, "\n")
	end
end

local function unitHasMana()
	local maxMana = UnitPowerMax("player", Enum.PowerType.Mana)
	return maxMana > 0
end

local lastItemPlaced
local lastManaPotionPlaced
local lastAllowRecuperate
local lastUseRecuperate
local function addDrinks()
	-- Determine best available drink (may be nil) and optional mana potion for combat
	local foundItem = nil
	for _, value in ipairs(addon.Drinks.filteredDrinks or {}) do
		if value.getCount() > 0 then
			foundItem = value.getId()
			break
			-- We only need the highest manadrink
		end
	end

	local manaItem = nil
	if addon.db.useManaPotionInCombat and unitHasMana() then manaItem = findBestManaPotion() end

	if foundItem ~= lastItemPlaced or manaItem ~= lastManaPotionPlaced or addon.db.allowRecuperate ~= lastAllowRecuperate or addon.db.allowRecuperate ~= lastUseRecuperate then
		-- Avoid protected EditMacro during combat lockdown
		if InCombatLockdown and InCombatLockdown() then return end
		EditMacro(drinkMacroName, drinkMacroName, nil, buildMacroString(foundItem, manaItem))
		lastItemPlaced = foundItem
		lastManaPotionPlaced = manaItem
		lastAllowRecuperate = addon.db.allowRecuperate
		lastUseRecuperate = addon.db.allowRecuperate
	end
end

function addon.functions.updateAvailableDrinks(ignoreCombat)
	if not addon.db.drinkMacroEnabled then return end
	if UnitAffectingCombat("player") and ignoreCombat == false then return end
	if unitHasMana() == false and not addon.db.allowRecuperate then return end
	createMacroIfMissing()
	addDrinks()
end

function addon.Drinks.functions.InitDrinkMacro()
	if not addon.db or not addon.functions or not addon.functions.InitDBValue then return end
	local init = addon.functions.InitDBValue
	init("minManaFoodValue", 50)
	init("preferMageFood", true)
	init("drinkMacroEnabled", false)
	init("allowRecuperate", true)
	init("useManaPotionInCombat", false)
	if addon.functions.updateAllowedDrinks then addon.functions.updateAllowedDrinks() end
end

local frameLoad = CreateFrame("Frame")
-- Registriere das Event
frameLoad:RegisterEvent("PLAYER_LOGIN")
frameLoad:RegisterEvent("PLAYER_REGEN_ENABLED")
frameLoad:RegisterEvent("PLAYER_LEVEL_UP")
frameLoad:RegisterEvent("BAG_UPDATE_DELAYED")
frameLoad:RegisterEvent("SPELLS_CHANGED")
frameLoad:RegisterEvent("PLAYER_TALENT_UPDATE")
-- Funktion zum Umgang mit Events
local pendingUpdate = false
local function eventHandler(self, event, arg1, arg2, arg3, arg4)
	if event == "PLAYER_LOGIN" then
		local macroEnabled = isDrinkMacroEnabled()
		if shouldUpdateRecuperateForDrinks() and addon.Recuperate and addon.Recuperate.Update then addon.Recuperate.Update() end
		-- Keep drink data in sync when either macro or mage food reminder is enabled.
		if shouldBuildDrinkData() and addon.functions.updateAllowedDrinks then addon.functions.updateAllowedDrinks() end
		if macroEnabled and addon.functions.updateAvailableDrinks then addon.functions.updateAvailableDrinks(false) end
		return
	end

	local macroEnabled = isDrinkMacroEnabled()
	local reminderEnabled = isMageFoodReminderEnabled()
	if not macroEnabled and not reminderEnabled then return end

	if event == "BAG_UPDATE_DELAYED" then
		if macroEnabled and not pendingUpdate then
			pendingUpdate = true
			C_Timer.After(0.05, function()
				addon.functions.updateAvailableDrinks(false)
				pendingUpdate = false
			end)
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- PLAYER_REGEN_ENABLED always load, because we don't know if something changed in Combat
		if macroEnabled then addon.functions.updateAvailableDrinks(true) end
	elseif event == "PLAYER_LEVEL_UP" and UnitAffectingCombat("player") == false then
		-- On level up, reload allowed drink data and macro if active.
		if addon.functions.updateAllowedDrinks then addon.functions.updateAllowedDrinks() end
		if macroEnabled then addon.functions.updateAvailableDrinks(true) end
	elseif event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
		if macroEnabled and addon.db.allowRecuperate and addon.Recuperate and addon.Recuperate.Update then addon.Recuperate.Update() end
		if addon.functions.updateAllowedDrinks then addon.functions.updateAllowedDrinks() end
		if macroEnabled then addon.functions.updateAvailableDrinks(false) end
	end
end
-- Setze den Event-Handler
frameLoad:SetScript("OnEvent", eventHandler)
