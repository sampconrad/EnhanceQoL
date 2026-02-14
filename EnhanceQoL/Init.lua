local addonName, addon = ...
_G[addonName] = addon
addon.saveVariables = {} -- Cross-Module variables for DB Save
addon.saveVariables["hidePartyFrameTitle"] = false -- Default for hiding party frame title
addon.saveVariables["unitFrameScaleEnabled"] = false -- Default for scaling compact unit frames
addon.saveVariables["unitFrameScale"] = 1 -- Default scale for compact party frames
addon.gossip = {}
addon.gossip.variables = {}
addon.variables = {}
addon.functions = {}
addon.general = {}
addon.general.variables = {}
-- addon.L = {} -- Language
addon.general.variables.autoOpen = {
	[249783] = true, -- Nightfallen insignia (2k rep)
	[249780] = true, -- Army of the Light Champion's Insignia (2k Rep)
	[249787] = true, -- Court of Farondis Champion's Insignia (2k Rep)
	[249788] = true, -- Argussian Reach Champion's Insignia (2k Rep)
	[249782] = true, -- Valarjar Champion's Insignia (2k Rep)
	[249785] = true, -- Highmountain Tribe Champion's Insignia (2k Rep)
	[249786] = true, -- Dreamweaver Champion's Insignia (2k Rep)
	[253756] = true, -- Insignia of the Broken Isles (1,5k Rep all)
	[249781] = true, -- Wardens Champion's Insignia (2k Rep)
	[146897] = true, -- Farondis Chest (Paragon)
	[146898] = true, -- Dreamweaver Cache (Paragon)
	[146899] = true, -- Highmountain Supplies (Paragon)
	[146900] = true, -- Nightfallen Cache (Paragon)
	[146901] = true, -- Valarjar Strongbox (Paragon)
	[146902] = true, -- Warden's Supply Kit (Paragon)
	[147361] = true, -- Legionsfall Chest (Paragon)
	[152923] = true, -- Gleaming Footlocker (Paragon)
	[152922] = true, -- Brittle Krokul Chest (Paragon)
}

local AceLocale = LibStub("AceLocale-3.0")
addon.L = AceLocale:GetLocale(addonName)
_G["BINDING_NAME_EQOL_TOGGLE_FRIENDLY_NPCS"] = _G.UNIT_NAMEPLATES_SHOW_FRIENDLY_NPCS
addon.elements = {}
addon.itemBagFilters = {}
addon.itemBagFiltersQuality = {}
addon.itemBagFiltersBound = {}
addon.itemBagFiltersUpgrade = {}
addon.itemBagFilterTypes = {
	DEATHKNIGHT = {
		[1] = { --Blood
			[2] = { -- Weapon
				[8] = true, -- Sword 2h
				[5] = true, -- Mace 2h
				[1] = true, -- Axe 2h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[4] = true, -- Plate
			},
		},
		[2] = { --Frost
			[2] = { -- Weapon
				[7] = true, -- Sword 1h
				[4] = true, -- Mace 1h
				[0] = true, -- Axe 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[4] = true, -- Plate
			},
		},
		[3] = { --Unholy
			[2] = { -- Weapon
				[8] = true, -- Sword 2h
				[5] = true, -- Mace 2h
				[1] = true, -- Axe 2h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[4] = true, -- Plate
				[6] = true, -- Shield
			},
		},
	},
	WARRIOR = {
		[1] = { --Arms
			[2] = { -- Weapon
				[8] = true, -- Sword 2h
				[5] = true, -- Mace 2h
				[1] = true, -- Axe 2h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[4] = true, -- Plate
			},
		},
		[2] = { --Fury
			[2] = { -- Weapon
				[8] = true, -- Sword 2h
				[5] = true, -- Mace 2h
				[1] = true, -- Axe 2h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[4] = true, -- Plate
			},
		},
		[3] = { --Protection
			[2] = { -- Weapon
				[7] = true, -- Sword 1h
				[4] = true, -- Mace 1h
				[0] = true, -- Axe 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[4] = true, -- Plate
				[6] = true, -- Shield
			},
		},
	},
	PALADIN = {
		[1] = { --Holy
			[2] = { -- Weapon
				[7] = true, -- Sword 1h
				[4] = true, -- Mace 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[4] = true, -- Plate
				[6] = true, -- Shield
			},
		},
		[2] = { --Protection
			[2] = { -- Weapon
				[7] = true, -- Sword 1h
				[4] = true, -- Mace 1h
				[0] = true, -- Axe 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[4] = true, -- Plate
				[6] = true, -- Shield
			},
		},
		[3] = { --Retribution
			[2] = { -- Weapon
				[8] = true, -- Sword 2h
				[5] = true, -- Mace 2h
				[1] = true, -- Axe 2h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[4] = true, -- Plate
			},
		},
	},
	HUNTER = {
		[1] = { --Beast Mastery
			[2] = { -- Weapon
				[2] = true, -- Bows
				[3] = true, -- Guns
				[18] = true, -- Crossbows
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[3] = true, -- Mail
			},
		},
		[2] = { --Marksmanship
			[2] = { -- Weapon
				[2] = true, -- Bows
				[3] = true, -- Guns
				[18] = true, -- Crossbows
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[3] = true, -- Mail
			},
		},
		[3] = { --Survival
			[2] = { -- Weapon
				[6] = true, -- Polearm
				[10] = true, -- Staff
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[3] = true, -- Mail
			},
		},
	},
	DRUID = {
		[1] = { --Balance
			[2] = { -- Weapon
				[10] = true, -- Staff
				[15] = true, -- Daggers
				[4] = true, -- Mace 1h
				[5] = true, -- Mace 2h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[2] = true, -- Leather
				[6] = true, -- Shield
			},
		},
		[2] = { --Feral
			[2] = { -- Weapon
				[10] = true, -- Staff
				[6] = true, -- Polearm
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[2] = true, -- Leather
			},
		},
		[3] = { --Guardian
			[2] = { -- Weapon
				[10] = true, -- Staff
				[6] = true, -- Polearm
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[2] = true, -- Leather
			},
		},
		[4] = { --Restoration
			[2] = { -- Weapon
				[10] = true, -- Staff
				[15] = true, -- Daggers
				[4] = true, -- Mace 1h
				[5] = true, -- Mace 2h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[2] = true, -- Leather
				[6] = true, -- Shield
			},
		},
	},
	DEMONHUNTER = {
		[1] = { --Havoc
			[2] = { -- Weapon
				[9] = true, -- Warglaive
				[7] = true, -- Sword 1h
				[13] = true, -- Fist Weapon
				[0] = true, -- Axe 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[2] = true, -- Leather
			},
		},
		[2] = { --Vengeance
			[2] = { -- Weapon
				[9] = true, -- Warglaive
				[7] = true, -- Sword 1h
				[13] = true, -- Fist Weapon
				[0] = true, -- Axe 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[2] = true, -- Leather
			},
		},
		[3] = { --Devourer
			[2] = { -- Weapon
				[9] = true, -- Warglaive
				[7] = true, -- Sword 1h
				[0] = true, -- Axe 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[2] = true, -- Leather
			},
		},
	},
	ROGUE = {
		[1] = { --Assassination
			[2] = { -- Weapon
				[15] = true, -- Daggers
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[2] = true, -- Leather
			},
		},
		[2] = { --Outlaw
			[2] = { -- Weapon
				[4] = true, -- Maces 1h
				[7] = true, -- Sword 1h
				[13] = true, -- Fist Weapon
				[0] = true, -- Axe 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[2] = true, -- Leather
			},
		},
		[3] = { --Subtlety
			[2] = { -- Weapon
				[15] = true, -- Daggers
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[2] = true, -- Leather
			},
		},
	},
	PRIEST = {
		[1] = { --Discipline
			[2] = { -- Weapon
				[15] = true, -- Daggers
				[10] = true, -- Staff
				[19] = true, -- Wand
				[4] = true, -- Maces 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[1] = true, -- Cloth
			},
		},
		[2] = { --Holy
			[2] = { -- Weapon
				[15] = true, -- Daggers
				[10] = true, -- Staff
				[19] = true, -- Wand
				[4] = true, -- Maces 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[1] = true, -- Cloth
			},
		},
		[3] = { --Shadow
			[2] = { -- Weapon
				[15] = true, -- Daggers
				[10] = true, -- Staff
				[19] = true, -- Wand
				[4] = true, -- Maces 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[1] = true, -- Cloth
			},
		},
	},
	SHAMAN = {
		[1] = { --Elemental
			[2] = { -- Weapon
				[15] = true, -- Daggers
				[4] = true, -- Maces 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[3] = true, -- Mail
				[6] = true, -- Shield
			},
		},
		[2] = { --Enhancement
			[2] = { -- Weapon
				[4] = true, -- Maces 1h
				[13] = true, -- Fist Weapon
				[0] = true, -- Axe 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[3] = true, -- Mail
			},
		},
		[3] = { --Restoration
			[2] = { -- Weapon
				[15] = true, -- Daggers
				[4] = true, -- Maces 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[3] = true, -- Mail
				[6] = true, -- Shield
			},
		},
	},
	MAGE = {
		[1] = { --Arcane
			[2] = { -- Weapon
				[15] = true, -- Daggers
				[10] = true, -- Staff
				[19] = true, -- Wand
				[7] = true, -- Sword 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[1] = true, -- Cloth
			},
		},
		[2] = { --Fire
			[2] = { -- Weapon
				[15] = true, -- Daggers
				[10] = true, -- Staff
				[19] = true, -- Wand
				[7] = true, -- Sword 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[1] = true, -- Cloth
			},
		},
		[3] = { --Frost
			[2] = { -- Weapon
				[15] = true, -- Daggers
				[10] = true, -- Staff
				[19] = true, -- Wand
				[7] = true, -- Sword 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[1] = true, -- Cloth
			},
		},
	},
	WARLOCK = {
		[1] = { --Affliction
			[2] = { -- Weapon
				[15] = true, -- Daggers
				[10] = true, -- Staff
				[19] = true, -- Wand
				[7] = true, -- Sword 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[1] = true, -- Cloth
			},
		},
		[2] = { --Demonology
			[2] = { -- Weapon
				[15] = true, -- Daggers
				[10] = true, -- Staff
				[19] = true, -- Wand
				[7] = true, -- Sword 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[1] = true, -- Cloth
			},
		},
		[3] = { --Destruction
			[2] = { -- Weapon
				[15] = true, -- Daggers
				[10] = true, -- Staff
				[19] = true, -- Wand
				[7] = true, -- Sword 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[1] = true, -- Cloth
			},
		},
	},
	MONK = {
		[1] = { --Brewmaster
			[2] = { -- Weapon
				[6] = true, -- Polearm
				[10] = true, -- Staff
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[2] = true, -- Leather
			},
		},
		[2] = { --Mistweaver
			[2] = { -- Weapon
				[7] = true, -- Sword 1h
				[10] = true, -- Staff
				[4] = true, -- Maces 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[2] = true, -- Leather
			},
		},
		[3] = { --Windwalker
			[2] = { -- Weapon
				[13] = true, -- Fist Weapon
				[0] = true, -- Axe 1h
				[4] = true, -- Maces 1h
				[7] = true, -- Sword 1h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[2] = true, -- Leather
			},
		},
	},
	EVOKER = {
		[1] = { --Devastation
			[2] = { -- Weapon
				[10] = true, -- Staff
				[7] = true, -- Sword 1h
				[8] = true, -- Sword 2h
				[15] = true, -- Daggers
				[4] = true, -- Maces 1h
				[5] = true, -- Maces 2h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[3] = true, -- Mail
			},
		},
		[2] = { --Preservation
			[2] = { -- Weapon
				[10] = true, -- Staff
				[7] = true, -- Sword 1h
				[8] = true, -- Sword 2h
				[15] = true, -- Daggers
				[4] = true, -- Maces 1h
				[5] = true, -- Maces 2h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[3] = true, -- Mail
			},
		},
		[3] = { --Augmentation
			[2] = { -- Weapon
				[10] = true, -- Staff
				[7] = true, -- Sword 1h
				[8] = true, -- Sword 2h
				[15] = true, -- Daggers
				[4] = true, -- Maces 1h
				[5] = true, -- Maces 2h
			},
			[4] = { -- Armor
				[0] = true, -- Generic
				[3] = true, -- Mail
			},
		},
	},
}

addon.variables.unitClass = select(2, UnitClass("player"))
addon.variables.unitClassID = select(3, UnitClass("player"))
addon.variables.unitPlayerGUID = UnitGUID("player")
addon.variables.unitSpec = C_SpecializationInfo.GetSpecialization()
addon.variables.unitSpecId = nil
addon.variables.unitSpecName = nil
addon.variables.unitRole = nil
if addon.variables.unitSpec then
	local specId, specName = C_SpecializationInfo.GetSpecializationInfo(addon.variables.unitSpec)
	addon.variables.unitSpecName = specName
	addon.variables.unitRole = GetSpecializationRole(C_SpecializationInfo.GetSpecialization())
	addon.variables.unitSpecId = specId
end
addon.variables.unitRace = select(2, UnitRace("player"))
addon.variables.unitName = select(1, UnitName("player"))

addon.variables.requireReload = false
addon.variables.catalystID = nil -- Change to get the actual cataclyst charges in char frame
addon.variables.durabilityIcon = 136241 -- Anvil Symbol
addon.variables.durabilityCount = 0
addon.variables.hookedOrderHall = false
addon.variables.unitFrameScale = 1 -- default scale value
addon.variables.maxLevel = GetMaxLevelForPlayerExpansion()
addon.variables.statusTable = { groups = {} }

addon.variables.enchantString = ENCHANTED_TOOLTIP_LINE:gsub("%%s", "(.+)")

addon.variables.itemSlots = {
	[1] = CharacterHeadSlot,
	[2] = CharacterNeckSlot,
	[3] = CharacterShoulderSlot,
	[15] = CharacterBackSlot,
	[5] = CharacterChestSlot,
	[9] = CharacterWristSlot,
	[10] = CharacterHandsSlot,
	[6] = CharacterWaistSlot,
	[7] = CharacterLegsSlot,
	[8] = CharacterFeetSlot,
	[11] = CharacterFinger0Slot,
	[12] = CharacterFinger1Slot,
	[13] = CharacterTrinket0Slot,
	[14] = CharacterTrinket1Slot,
	[16] = CharacterMainHandSlot,
	[17] = CharacterSecondaryHandSlot,
}

addon.variables.regionCode = GetCurrentRegion()

function addon.functions.PatchTS(y, m, dUS, dEU, h)
	local day = (addon.variables.regionCode == 3) and dEU or dUS
	return time({ year = y, month = m, day = day, hour = h })
end
function addon.functions.IsPatchLive(key)
	local ts = addon.variables.patchInformations and addon.variables.patchInformations[key]
	if not ts then return false end
	return GetServerTime() >= ts
end

addon.variables.isMidnight = select(4, GetBuildInfo()) >= 120000

local playerLevel = UnitLevel("player") or 0
local useMidnightEnchantRules = playerLevel >= 81

if useMidnightEnchantRules then
	addon.variables.shouldEnchanted = { [1] = true, [5] = true, [7] = true, [8] = true, [11] = true, [12] = true, [3] = true, [16] = true, [17] = true }
else
	addon.variables.shouldEnchanted = { [15] = true, [5] = true, [9] = true, [7] = true, [8] = true, [11] = true, [12] = true, [16] = true, [17] = true }
end
addon.variables.patchInformations = {
	-- Add patch timestamps here when you need time-based fallbacks.
	-- Example: examplePatch = addon.functions.PatchTS(2025, 8, 5, 6, 6),
}

addon.variables.shouldEnchantedChecks = {
	-- Head
	-- [1] = {
	-- 	func = function(ilvl)
	-- 		-- Example: gate a seasonal enchant to a patch window.
	-- 		-- if ilvl >= 350 and addon.functions.IsPatchLive("examplePatchStart") and not addon.functions.IsPatchLive("examplePatchEnd") then
	-- 		-- 	return true
	-- 		-- end
	-- 		return false
	-- 	end,
	-- },
}
addon.variables.shouldSocketed = {
	[1] = 1,
	[2] = 2,
	[6] = 1,
	[9] = 1,
	[11] = 2,
	[12] = 2,
}
addon.variables.shouldSocketedChecks = {
	-- Helm - can be bought for PvP with Honor (farmable)
	[1] = {
		func = function(cSeason, isPvP)
			if not cSeason then return false end
			if isPvP then return true end
			return false
		end,
	},
	[2] = {
		func = function(cSeason, isPvP)
			if not cSeason then return false end
			-- item for PvE and PvP is purchaseble
			return true
		end,
	},
	[6] = {
		func = function(cSeason, isPvP)
			if not cSeason then return false end
			if isPvP then return true end
			return false
		end,
	},
	[9] = {
		func = function(cSeason, isPvP)
			if not cSeason then return false end
			if isPvP then return true end
			return false
		end,
	},
	[11] = {
		func = function(cSeason, isPvP)
			if not cSeason then return false end
			-- item for PvE and PvP is purchaseble
			return true
		end,
	},
	[12] = {
		func = function(cSeason, isPvP)
			if not cSeason then return false end
			-- item for PvE and PvP is purchaseble
			return true
		end,
	},
}

addon.variables.landingPageType = {
	[3] = { title = ORDER_HALL_LANDING_PAGE_TITLE, checkbox = EXPANSION_NAME6 },
	[10] = { title = GARRISON_LANDING_PAGE_TITLE, checkbox = GARRISON_LOCATION_TOOLTIP },
	[20] = { title = GARRISON_TYPE_9_0_LANDING_PAGE_TITLE, checkbox = EXPANSION_NAME8 },
	[30] = { title = DRAGONFLIGHT_LANDING_PAGE_TITLE, checkbox = EXPANSION_NAME9 },
	[40] = { title = WAR_WITHIN_LANDING_PAGE_TITLE, checkbox = EXPANSION_NAME10 },
}
addon.variables.landingPageReverse = {} -- Used for onShow Method of LandingPage
for id, data in pairs(addon.variables.landingPageType) do
	addon.variables.landingPageReverse[data.title] = id
end

addon.variables.allowedEnchantTypesForOffhand = { ["INVTYPE_WEAPON"] = true, ["INVTYPE_WEAPONOFFHAND"] = true }

addon.variables.itemSlotSide = { -- 0 = Text to right side, 1 = Text to left side
	[1] = 0,
	[2] = 0,
	[3] = 0,
	[15] = 0,
	[5] = 0,
	[9] = 0,
	[10] = 1,
	[6] = 1,
	[7] = 1,
	[8] = 1,
	[11] = 1,
	[12] = 1,
	[13] = 1,
	[14] = 1,
	[16] = 1,
	[17] = 2,
}
addon.variables.itemLevelPattern = ITEM_LEVEL:gsub("%%d", "(%%d+)")
addon.variables.allowedSockets = {
	["EMPTY_SOCKET_BLUE"] = true,
	["EMPTY_SOCKET_COGWHEEL"] = true,
	["EMPTY_SOCKET_CYPHER"] = true,
	["EMPTY_SOCKET_DOMINATION"] = true,
	["EMPTY_SOCKET_HYDRAULIC"] = true,
	["EMPTY_SOCKET_META"] = true,
	["EMPTY_SOCKET_NO_COLOR"] = true,
	["EMPTY_SOCKET_PRIMORDIAL"] = true,
	["EMPTY_SOCKET_PRISMATIC"] = true,
	["EMPTY_SOCKET_PUNCHCARDBLUE"] = true,
	["EMPTY_SOCKET_PUNCHCARDRED"] = true,
	["EMPTY_SOCKET_PUNCHCARDYELLOW"] = true,
	["EMPTY_SOCKET_RED"] = true,
	["EMPTY_SOCKET_TINKER"] = true,
	["EMPTY_SOCKET_YELLOW"] = true,
	["EMPTY_SOCKET_SINGINGSEA"] = true,
	["EMPTY_SOCKET_SINGINGTHUNDER"] = true,
	["EMPTY_SOCKET_SINGINGWIND"] = true,
	["EMPTY_SOCKET_FIBER"] = true,
}

addon.variables.allowBagIlvlClassID = { [2] = true, [4] = true }
addon.variables.denyBagIlvlClassSubClassID = { [4] = { [5] = true } }
addon.variables.allowedEquipSlotsBagIlvl = {
	["INVTYPE_NON_EQUIP_IGNORE"] = true,
	["INVTYPE_HEAD"] = true,
	["INVTYPE_NECK"] = true,
	["INVTYPE_SHOULDER"] = true,
	["INVTYPE_BODY"] = true,
	["INVTYPE_CHEST"] = true,
	["INVTYPE_WAIST"] = true,
	["INVTYPE_LEGS"] = true,
	["INVTYPE_FEET"] = true,
	["INVTYPE_WRIST"] = true,
	["INVTYPE_HAND"] = true,
	["INVTYPE_FINGER"] = true,
	["INVTYPE_TRINKET"] = true,
	["INVTYPE_WEAPON"] = true,
	["INVTYPE_SHIELD"] = true,
	["INVTYPE_RANGED"] = true,
	["INVTYPE_CLOAK"] = true,
	["INVTYPE_2HWEAPON"] = true, -- ["INVTYPE_BAG"] = true,
	-- ["INVTYPE_TABARD"] = true,
	["INVTYPE_ROBE"] = true,
	["INVTYPE_WEAPONMAINHAND"] = true,
	["INVTYPE_WEAPONOFFHAND"] = true,
	["INVTYPE_HOLDABLE"] = true,
	-- ["INVTYPE_AMMO"] = true,
	-- ["INVTYPE_THROWN"] = true,
	-- ["INVTYPE_RANGEDRIGHT"] = true,
	-- ["INVTYPE_QUIVER"] = true,
	-- ["INVTYPE_RELIC"] = true,
	["INVTYPE_PROFESSION_TOOL"] = true,
	["INVTYPE_PROFESSION_GEAR"] = true,
}
addon.variables.ignoredEquipmentTypes = {
	["INVTYPE_NON_EQUIP_IGNORE"] = true,
	["INVTYPE_BAG"] = true,
	["INVTYPE_PROFESSION_TOOL"] = true,
}

-- Actionbars
addon.variables.actionBarNames = {
	{ name = "MultiBarBottomLeft", var = "mouseoverActionBar2", text = BINDING_HEADER_ACTIONBAR2 },
	{ name = "MultiBarBottomRight", var = "mouseoverActionBar3", text = BINDING_HEADER_ACTIONBAR3 },
	{ name = "MultiBarRight", var = "mouseoverActionBar4", text = BINDING_HEADER_ACTIONBAR4 },
	{ name = "MultiBarLeft", var = "mouseoverActionBar5", text = BINDING_HEADER_ACTIONBAR5 },
	{ name = "MultiBar5", var = "mouseoverActionBar6", text = BINDING_HEADER_ACTIONBAR6 },
	{ name = "MultiBar6", var = "mouseoverActionBar7", text = BINDING_HEADER_ACTIONBAR7 },
	{ name = "MultiBar7", var = "mouseoverActionBar8", text = BINDING_HEADER_ACTIONBAR8 },
	{ name = "PetActionBar", var = "mouseoverActionBarPet", text = TUTORIAL_TITLE61_HUNTER },
	{ name = "StanceBar", var = "mouseoverActionBarStanceBar", text = HUD_EDIT_MODE_STANCE_BAR_LABEL },
}
if _G.MainMenuBar then table.insert(addon.variables.actionBarNames, { name = "MainMenuBar", var = "mouseoverActionBar1", text = BINDING_HEADER_ACTIONBAR }) end
if _G.MainActionBar then table.insert(addon.variables.actionBarNames, { name = "MainActionBar", var = "mouseoverActionBar1", text = BINDING_HEADER_ACTIONBAR }) end

local petChildren
do
	local mana = _G.PetFrameManaBar
	local health = _G.PetFrameHealthBar
	if mana or health then
		petChildren = {}
		if mana then table.insert(petChildren, mana) end
		if health then table.insert(petChildren, health) end
	end
end

addon.variables.unitFrameNames = {
	{ name = "PlayerFrame", var = "unitframeSettingPlayerFrame", text = HUD_EDIT_MODE_PLAYER_FRAME_LABEL, unitToken = "player" },
	{
		name = "BossTargetFrameContainer",
		var = "unitframeSettingBossTargetFrame",
		text = HUD_EDIT_MODE_BOSS_FRAMES_LABEL,
		allowedVisibility = { "NONE", "MOUSEOVER", "HIDE" },
		onlyChildren = { "Boss1TargetFrame", "Boss2TargetFrame", "Boss3TargetFrame", "Boss4TargetFrame", "Boss5TargetFrame" },
	},
	{ name = "TargetFrame", var = "unitframeSettingTargetFrame", text = HUD_EDIT_MODE_TARGET_FRAME_LABEL },
	{
		name = "FocusFrame",
		var = "unitframeSettingFocusFrame",
		text = _G.HUD_EDIT_MODE_FOCUS_FRAME_LABEL or "Focus Frame",
		allowedVisibility = { "NONE", "MOUSEOVER", "HIDE" },
	},
	{
		name = "PetFrame",
		var = "unitframeSettingPetFrame",
		text = _G.HUD_EDIT_MODE_PET_FRAME_LABEL or "Pet Frame",
		children = petChildren or {},
		revealAllChilds = true,
	},
	{
		name = "MicroMenu",
		var = "unitframeSettingMicroMenu",
		text = addon.L["MicroMenu"],
		allowedVisibility = { "NONE", "MOUSEOVER", "HIDE" },
		children = { MicroMenu:GetChildren() },
		revealAllChilds = true,
	},
	{
		name = "BagsBar",
		var = "unitframeSettingBagsBar",
		text = addon.L["BagsBar"],
		allowedVisibility = { "NONE", "MOUSEOVER", "HIDE" },
		children = { BagsBar:GetChildren() },
		revealAllChilds = true,
	},
}

table.sort(addon.variables.actionBarNames, function(a, b) return a.text < b.text end)

addon.variables.defaultFont = "Fonts\\FRIZQT__.TTF"
if (GAME_LOCALE or GetLocale()) == "ruRU" then
	addon.variables.defaultFont = "Fonts\\ARIALN.TTF"
elseif (GAME_LOCALE or GetLocale()) == "koKR" then
	addon.variables.defaultFont = "Fonts\\2002.ttf"
elseif (GAME_LOCALE or GetLocale()) == "zhTW" then
	addon.variables.defaultFont = "Fonts\\bLEI00D.TTF"
elseif (GAME_LOCALE or GetLocale()) == "zhCN" then
	addon.variables.defaultFont = "Fonts\\ARKai_T.ttf"
end

addon.variables.cvarOptions = {
	["autoDismount"] = {
		trueValue = "1",
		falseValue = "0",
		description = addon.L["autoDismount"],
		category = "cvarCategoryMovementInput",
	},
	["autoDismountFlying"] = {
		trueValue = "1",
		falseValue = "0",
		description = addon.L["autoDismountFlying"],
		category = "cvarCategoryMovementInput",
	},
	["chatMouseScroll"] = {
		trueValue = "1",
		falseValue = "0",
		description = addon.L["chatMouseScroll"],
		category = "cvarCategoryMovementInput",
	},
	["WholeChatWindowClickable"] = {
		trueValue = "1",
		falseValue = "0",
		description = addon.L["WholeChatWindowClickable"],
		category = "cvarCategoryMovementInput",
	},
	["enableMouseoverCast"] = {
		trueValue = "1",
		falseValue = "0",
		description = addon.L["enableMouseoverCast"],
		persistent = true,
		category = "cvarCategoryUtility",
	},
	["mapFade"] = {
		trueValue = "1",
		falseValue = "0",
		description = addon.L["mapFade"],
		category = "cvarCategoryDisplay",
	},
	["ShowClassColorInNameplate"] = {
		trueValue = "1",
		falseValue = "0",
		description = addon.L["ShowClassColorInNameplate"],
		category = "cvarCategoryDisplay",
	},
	["nameplateUseClassColorForFriendlyPlayerUnitNames"] = {
		trueValue = "1",
		falseValue = "0",
		description = addon.L["ShowClassColorInNameplate"],
		category = "cvarCategoryDisplay",
	},
	["ShowTargetCastbar"] = {
		trueValue = "1",
		falseValue = "0",
		description = addon.L["ShowTargetCastbar"],
		category = "cvarCategoryDisplay",
	},
	["raidFramesDisplayClassColor"] = {
		trueValue = "1",
		falseValue = "0",
		description = addon.L["raidFramesDisplayClassColor"],
		category = "cvarCategoryDisplay",
	},
	["pvpFramesDisplayClassColor"] = {
		trueValue = "1",
		falseValue = "0",
		description = addon.L["pvpFramesDisplayClassColor"],
		category = "cvarCategoryDisplay",
	},
	["UnitNamePlayerGuild"] = {
		trueValue = "1",
		falseValue = "0",
		description = addon.L["UnitNamePlayerGuild"],
		category = "cvarCategoryDisplay",
	},
	["UnitNamePlayerPVPTitle"] = {
		trueValue = "1",
		falseValue = "0",
		description = addon.L["UnitNamePlayerPVPTitle"],
		category = "cvarCategoryDisplay",
	},
	["floatingCombatTextCombatDamage_v2"] = {
		trueValue = "1",
		falseValue = "0",
		description = addon.L["floatingCombatTextCombatDamage_v2"],
		category = "cvarCategoryDisplay",
	},
	["floatingCombatTextCombatHealing_v2"] = {
		trueValue = "1",
		falseValue = "0",
		description = addon.L["floatingCombatTextCombatHealing_v2"],
		category = "cvarCategoryDisplay",
	},
	["ffxDeath"] = {
		trueValue = "0",
		falseValue = "1",
		description = addon.L["ffxDeath"],
		category = "cvarCategoryDisplay",
	},
	["scriptErrors"] = {
		trueValue = "1",
		falseValue = "0",
		description = addon.L["scriptErrors"],
		category = "cvarCategorySystem",
	},
	["showTutorials"] = {
		trueValue = "0",
		falseValue = "1",
		description = addon.L["showTutorials"],
		category = "cvarCategorySystem",
	},
	["UberTooltips"] = {
		trueValue = "1",
		falseValue = "0",
		description = addon.L["UberTooltips"],
		category = "cvarCategorySystem",
	},
	["AutoPushSpellToActionBar"] = {
		trueValue = "1",
		falseValue = "0",
		description = addon.L["AutoPushSpellToActionBar"],
		persistent = true,
		category = "cvarCategoryUtility",
	},
}
