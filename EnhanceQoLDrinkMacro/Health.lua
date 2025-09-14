local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local UnitLevel = UnitLevel
local UnitHealthMax = UnitHealthMax
local newItem = addon.functions.newItem
local insert = table.insert
local sort = table.sort

-- Cache for O(1) checks
addon.Health.cache = addon.Health.cache or {}
addon.Health.cache.isWarlock = (addon.variables and addon.variables.unitClass == "WARLOCK") or false
addon.Health.cache.hasDemonicTalent = false

local function checkForTalent(spellID)
	-- Be defensive: during login/loads the trait config may not be ready yet
	if not C_ClassTalents or not C_Traits or not C_Traits.GetConfigInfo then return false end

	local configID = C_ClassTalents.GetActiveConfigID()
	if not configID then return false end

	local cfg = C_Traits.GetConfigInfo(configID)
	if not cfg or not cfg.treeIDs or not cfg.treeIDs[1] then return false end
	local treeID = cfg.treeIDs[1]

	local nodes = C_Traits.GetTreeNodes(treeID) or {}
	for _, nodeID in ipairs(nodes) do
		local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
		if nodeInfo and nodeInfo.activeEntry and (nodeInfo.ranksPurchased or 0) > 0 then
			local entryInfo = C_Traits.GetEntryInfo(configID, nodeInfo.activeEntry.entryID)
			if entryInfo and entryInfo.definitionID then
				local def = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
				if def and def.spellID == spellID then return true end
			end
		end
	end
	return false
end

local function GetPotionHeal(totalHealth)
	local raw = totalHealth * 0.25
	local heal = raw - (raw % 50)
	return heal
end

local function GetStoneHeal(totalHealth) return (totalHealth or 0) * 0.25 end

-- Health items master list. Each entry has:
-- key, id, requiredLevel, heal (relative ranking), type: "stone"|"potion"|"other"
addon.Health.healthList = {
	-- Healthstones (Warlock)
	{ key = "Healthstone", id = 5512, requiredLevel = 5, healFunc = function(maxHP) return GetStoneHeal(maxHP) end, type = "stone" },
	{ key = "DemonicHealthstone", id = 224464, requiredLevel = 5, healFunc = function(maxHP) return GetStoneHeal(maxHP) end, type = "stone" },

	-- The War Within: Cavedweller's Delight (Qualities 1-3)
	{ key = "CavedwellerDelight1", id = 212242, requiredLevel = 71, heal = 2574750, type = "potion", isCombatPotion = true },
	{ key = "CavedwellerDelight2", id = 212243, requiredLevel = 71, heal = 2685000, type = "potion", isCombatPotion = true },
	{ key = "CavedwellerDelight3", id = 212244, requiredLevel = 71, heal = 2799950, type = "potion", isCombatPotion = true },

	-- The War Within: Invigorating Healing Potion (Qualities 1-3)
	{ key = "InvigoratingHealingPotion1", id = 244835, requiredLevel = 71, heal = 5100000, type = "potion" },
	{ key = "InvigoratingHealingPotion2", id = 244838, requiredLevel = 71, heal = 5300000, type = "potion" },
	{ key = "InvigoratingHealingPotion3", id = 244839, requiredLevel = 71, heal = 6400000, type = "potion" },

	-- Khaz Algar: Algari Healing Potion (Qualities 1-3)
	{ key = "AlgariHealingPotion1", id = 211878, requiredLevel = 71, heal = 3500000, type = "potion" },
	{ key = "AlgariHealingPotion2", id = 211879, requiredLevel = 71, heal = 3600000, type = "potion" },
	{ key = "AlgariHealingPotion3", id = 211880, requiredLevel = 71, heal = 3800000, type = "potion" },

	-- Dragonflight: Refreshing Healing Potion (Qualities 1-3) - kept for completeness
	{ key = "RefreshingHealingPotion1", id = 207023, requiredLevel = 70, heal = 159194, type = "potion" },
	{ key = "RefreshingHealingPotion2", id = 207022, requiredLevel = 70, heal = 136368, type = "potion" },
	{ key = "RefreshingHealingPotion3", id = 207021, requiredLevel = 70, heal = 116788, type = "potion" },

	-- Dragonflight: Refreshing Healing Potion (Qualities 1-3) - kept for completeness
	{ key = "RefreshingHealingPotion1", id = 191378, requiredLevel = 61, heal = 118950, type = "potion" },
	{ key = "RefreshingHealingPotion2", id = 191379, requiredLevel = 61, heal = 139050, type = "potion" },
	{ key = "RefreshingHealingPotion3", id = 191380, requiredLevel = 61, heal = 162500, type = "potion" },

	-- Shadowlands
	{ key = "SpiritualHealingPotion", id = 171267, requiredLevel = 51, heal = 36000, type = "potion" },

	-- Battle for Azeroth
	{ key = "CoastalHealingPotion", id = 152615, requiredLevel = 40, heal = 8000, type = "potion" },
	{ key = "AbyssalHealingPotion", id = 169451, requiredLevel = 40, heal = 16000, type = "potion" },

	-- Legion
	{ key = "AncientHealingPotion", id = 127834, requiredLevel = 40, heal = 6000, type = "potion" },
	{ key = "AgedHealingPotion", id = 136569, requiredLevel = 40, heal = 6000, type = "potion" },

	-- Warlords of Draenor
	{ key = "HealingTonic", id = 109223, requiredLevel = 35, heal = 3400, type = "potion" },
	{ key = "MasterHealingPotion", id = 76097, requiredLevel = 32, heal = 2200, type = "potion" },
	{ key = "MysticalHealingPotion", id = 57191, requiredLevel = 30, heal = 1000, type = "potion" },

	-- Wrath of the Lich King
	{ key = "RunicHealingPotion", id = 33447, requiredLevel = 27, heal = 1200, type = "potion" },

	{ key = "SurvivalistsHealingPotion", id = 224021, requiredLevel = 5, type = "potion", healFunc = function(maxHP) return GetPotionHeal(maxHP or 0) end },

	-- Other healing items (examples; toggleable)
	-- Add additional healing clickies here if desired
}

-- Prepared lists and best-of per type
addon.Health.filteredHealth = {}
addon.Health.bestStone = nil
addon.Health.bestPotion = nil
addon.Health.bestOther = nil

addon.Health._wrapped = addon.Health._wrapped or {}
local function wrapItem(entry, maxHP)
	local obj = addon.Health._wrapped[entry.id]
	if not obj then
		obj = newItem(entry.id, nil, false)
		addon.Health._wrapped[entry.id] = obj
	end
	obj.requiredLevel = entry.requiredLevel or 1
	obj.type = entry.type or "potion"
	obj.key = entry.key
	if entry.healFunc then
		obj.heal = entry.healFunc(maxHP)
	else
		obj.heal = entry.heal or 0
	end
	return obj
end

function addon.Health.functions.updateAllowedHealth()
	local playerLevel = UnitLevel("player")
	local maxHP = UnitHealthMax("player") or 0
	local filtered = {}
	local bestStone, bestPotion, bestOther
	local cache = addon.Health.cache or {}

	for i = 1, #addon.Health.healthList do
		local e = addon.Health.healthList[i]
		if (e.requiredLevel or 1) <= playerLevel then
			local w = wrapItem(e, maxHP)
			insert(filtered, w)
			if w.type == "stone" then
				if not bestStone or (w.heal > bestStone.heal) then bestStone = w end
			elseif w.type == "potion" then
				if not bestPotion or (w.heal > bestPotion.heal) then bestPotion = w end
			else
				if not bestOther or (w.heal > bestOther.heal) then bestOther = w end
			end
		end
	end

	sort(filtered, function(a, b)
		if a.heal == b.heal then return a.requiredLevel > b.requiredLevel end
		return a.heal > b.heal
	end)

	addon.Health.filteredHealth = filtered
	addon.Health.bestStone = bestStone
	addon.Health.bestPotion = bestPotion
	addon.Health.bestOther = bestOther
end

-- Refresh cached availability flags for talents/classes once per event
function addon.Health.functions.refreshTalentCache()
	local c = addon.Health.cache
	c.isWarlock = addon.variables and addon.variables.unitClass == "WARLOCK" or false
	c.hasDemonicTalent = c.isWarlock and checkForTalent(386689) or false
end

function addon.Health.functions.isDemonicAvailable() return addon.Health.cache.hasDemonicTalent end
