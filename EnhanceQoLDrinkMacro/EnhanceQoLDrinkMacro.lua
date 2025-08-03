local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
local drinkMacroName = "EnhanceQoLDrinkMacro"

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_DrinkMacro")
local LSM = LibStub("LibSharedMedia-3.0")

local function createMacroIfMissing()
	if GetMacroInfo(drinkMacroName) == nil then CreateMacro(drinkMacroName, "INV_Misc_QuestionMark") end
end

local function buildMacroString(item)
	local resetType = "combat"
	if item == nil then
		return "#showtooltip"
	else
		return "#showtooltip \n/castsequence reset=" .. resetType .. " " .. item
	end
end

local function unitHasMana()
	local maxMana = UnitPowerMax("Player", Enum.PowerType.Mana)
	return maxMana > 0
end

local lastItemPlaced
local function addDrinks()
	local foundItem = nil
	for _, value in ipairs(addon.Drinks.filteredDrinks) do
		if value.getCount() > 0 then
			foundItem = value.getId()
			break
			-- We only need the highest manadrink
		end
	end
	if foundItem ~= lastItemPlaced then
		EditMacro(drinkMacroName, drinkMacroName, nil, buildMacroString(foundItem))
		lastItemPlaced = foundItem
	end
end

function addon.functions.updateAvailableDrinks(ignoreCombat)
	if (UnitAffectingCombat("Player") and ignoreCombat == false) or unitHasMana() == false then -- on Combat do nothing, when no manaclass do nothing
		return
	end
	createMacroIfMissing()
	addDrinks()
end

local initialValue = 50
if addon.db["minManaFoodValue"] then
	initialValue = addon.db["minManaFoodValue"]
else
	addon.db["minManaFoodValue"] = initialValue
end

addon.functions.InitDBValue("preferMageFood", true)
addon.functions.InitDBValue("ignoreBuffFood", true)
addon.functions.InitDBValue("ignoreGemsEarthen", true)
addon.functions.InitDBValue("allowRecuperate", true)
addon.functions.updateAllowedDrinks()

local frameLoad = CreateFrame("Frame")
-- Registriere das Event
frameLoad:RegisterEvent("PLAYER_LOGIN")
frameLoad:RegisterEvent("PLAYER_REGEN_ENABLED")
frameLoad:RegisterEvent("PLAYER_LEVEL_UP")
frameLoad:RegisterEvent("BAG_UPDATE_DELAYED")
-- Funktion zum Umgang mit Events
local function eventHandler(self, event, arg1, arg2, arg3, arg4)
	if event == "BAG_UPDATE_DELAYED" then
		addon.functions.updateAvailableDrinks(false)
	elseif event == "PLAYER_LOGIN" then
		-- on login always load the macro
		addon.functions.updateAllowedDrinks()
		addon.functions.updateAvailableDrinks(false)
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- PLAYER_REGEN_ENABLED always load, because we don't know if something changed in Combat
		addon.functions.updateAvailableDrinks(true)
	elseif event == "PLAYER_LEVEL_UP" and UnitAffectingCombat("player") == false then
		-- on level up, reload the complete list of allowed drinks
		addon.functions.updateAllowedDrinks()
		addon.functions.updateAvailableDrinks(true)
	end
end
-- Setze den Event-Handler
frameLoad:SetScript("OnEvent", eventHandler)

addon.functions.addToTree(nil, {
	value = "drink",
	text = L["Drink Macro"],
})

local function addDrinkFrame(container)
	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	container:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)

	local data = {
		{ text = L["Prefer mage food"], var = "preferMageFood" },
		{ text = L["Ignore bufffood"], var = "ignoreBuffFood" },
		{ text = L["ignoreGemsEarthen"], var = "ignoreGemsEarthen" },
		{ text = L["allowRecuperate"], var = "allowRecuperate", desc = L["allowRecuperateDesc"] },
		{
			text = L["mageFoodReminder"],
			var = "mageFoodReminder",
			desc = L["mageFoodReminderDesc2"],
			func = function(self, _, value)
				addon.db["mageFoodReminder"] = value
				addon.Drinks.functions.updateRole()
			end,
		},
		{
			text = L["mageFoodReminderSound"],
			var = "mageFoodReminderSound",
			func = function(self, _, value)
				addon.db["mageFoodReminderSound"] = value
				addon.Drinks.functions.updateRole()
				container:ReleaseChildren()
				addDrinkFrame(container)
			end,
		},
	}

	table.sort(data, function(a, b) return a.text < b.text end)

	for _, cbData in ipairs(data) do
		local uFunc = function(self, _, value)
			addon.db[cbData.var] = value
			addon.functions.updateAllowedDrinks()
			addon.functions.updateAvailableDrinks(false)
		end
		if cbData.func then uFunc = cbData.func end
		local cbElement = addon.functions.createCheckboxAce(cbData.text, addon.db[cbData.var], uFunc, cbData.desc)
		groupCore:AddChild(cbElement)
	end

	if addon.db["mageFoodReminderSound"] then
		local cbCustomReminderSound = addon.functions.createCheckboxAce(L["mageFoodReminderUseCustomSound"], addon.db["mageFoodReminderUseCustomSound"], function(self, _, value)
			addon.db["mageFoodReminderUseCustomSound"] = value
			container:ReleaseChildren()
			addDrinkFrame(container)
		end)
		groupCore:AddChild(cbCustomReminderSound)

		if addon.db["mageFoodReminderUseCustomSound"] then
			local soundList = {}
			if addon.ChatIM and addon.ChatIM.BuildSoundTable and not addon.ChatIM.availableSounds then addon.ChatIM:BuildSoundTable() end
			local soundTable = (addon.ChatIM and addon.ChatIM.availableSounds) or LSM:HashTable("sound")
			for name in pairs(soundTable or {}) do
				soundList[name] = name
			end
			local list, order = addon.functions.prepareListForDropdown(soundList)
			local dropJoin = addon.functions.createDropdownAce(L["mageFoodReminderJoinSound"], list, order, function(self, _, val)
				addon.db["mageFoodReminderJoinSoundFile"] = val
				self:SetValue(val)
				local file = soundTable and soundTable[val]
				if file then PlaySoundFile(file, "Master") end
			end)
			dropJoin:SetValue(addon.db["mageFoodReminderJoinSoundFile"])
			groupCore:AddChild(dropJoin)

			local dropLeave = addon.functions.createDropdownAce(L["mageFoodReminderLeaveSound"], list, order, function(self, _, val)
				addon.db["mageFoodReminderLeaveSoundFile"] = val
				self:SetValue(val)
				local file = soundTable and soundTable[val]
				if file then PlaySoundFile(file, "Master") end
			end)
			dropLeave:SetValue(addon.db["mageFoodReminderLeaveSoundFile"])
			groupCore:AddChild(dropLeave)

			groupCore:AddChild(addon.functions.createSpacerAce())
		end
	end

	local sliderManaMinimum = addon.functions.createSliderAce(
		L["Minimum mana restore for food"] .. ": " .. addon.db["minManaFoodValue"] .. "%",
		addon.db["minManaFoodValue"],
		0,
		100,
		1,
		function(self, _, value2)
			addon.db["minManaFoodValue"] = value2
			addon.functions.updateAllowedDrinks()
			addon.functions.updateAvailableDrinks(false)
			self:SetLabel(L["Minimum mana restore for food"] .. ": " .. value2 .. "%")
		end
	)
	groupCore:AddChild(sliderManaMinimum)

	local sliderReminderSize = addon.functions.createSliderAce(
		L["mageFoodReminderSize"] .. ": " .. addon.db["mageFoodReminderScale"],
		addon.db["mageFoodReminderScale"],
		0.5,
		2,
		0.05,
		function(self, _, value2)
			addon.db["mageFoodReminderScale"] = value2
			addon.Drinks.functions.updateRole()
			self:SetLabel(L["mageFoodReminderSize"] .. ": " .. value2)
		end
	)
	groupCore:AddChild(sliderReminderSize)

	local resetReminderPos = addon.functions.createButtonAce(L["mageFoodReminderReset"], 150, function()
		addon.db["mageFoodReminderPos"] = { point = "TOP", x = 0, y = -100 }
		addon.Drinks.functions.updateRole()
	end)
	groupCore:AddChild(resetReminderPos)
end

function addon.Drinks.functions.treeCallback(container, group)
	container:ReleaseChildren() -- Entfernt vorherige Inhalte
	-- Prüfen, welche Gruppe ausgewählt wurde
	if group == "drink" then addDrinkFrame(container) end
end
