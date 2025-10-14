local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_DrinkMacro")

local UnitAffectingCombat = UnitAffectingCombat
local InCombatLockdown = InCombatLockdown
local GetItemCooldown = GetItemCooldown
local GetTime = GetTime
local GetMacroInfo = GetMacroInfo
local EditMacro = EditMacro
local CreateMacro = CreateMacro

local healthMacroName = "EnhanceQoLHealthMacro"

-- TODO completely remove healthAllowOther
-- TODO always reorder by cooldown and remove the setting (more convinient)
-- DB defaults
addon.functions.InitDBValue("healthMacroEnabled", false)
addon.functions.InitDBValue("healthUseBoth", false)
addon.functions.InitDBValue("healthPreferStoneFirst", true)
addon.functions.InitDBValue("healthReset", "combat")
addon.functions.InitDBValue("healthAllowOther", false)
addon.functions.InitDBValue("healthReorderByCooldown", true)
addon.functions.InitDBValue("healthUseRecuperate", false)
-- Allow using combat potions (from EnhanceQoLDrinkMacro/Health.lua entries tagged with isCombatPotion)
addon.functions.InitDBValue("healthUseCombatPotions", false)
-- Custom spells support
addon.functions.InitDBValue("healthUseCustomSpells", false)
addon.functions.InitDBValue("healthCustomSpells", {})
-- Multiselect preference for ordering (spells, stones)
-- Fallback to legacy healthPreferStoneFirst when not initialized yet
addon.functions.InitDBValue("healthPreferFirstPrefs", nil)
-- New priority-based ordering (overrides legacy prefs if set)
addon.functions.InitDBValue("healthPriorityOrder", nil)

local function createMacroIfMissing()
	if not addon.db.healthMacroEnabled then return end
	-- Avoid protected calls during combat lockdown
	if InCombatLockdown and InCombatLockdown() then return end
	if GetMacroInfo(healthMacroName) == nil then
		local macroId = CreateMacro(healthMacroName, "INV_Misc_QuestionMark")
		if not macroId then
			print(L["healthMacroLimitReached"] or "Health Macro: Macro limit reached. Please free a slot.")
			return
		end
		-- Prefill with a sensible default
		local demonicCount = C_Item.GetItemCount(224464, false, false) or 0
		local normalCount = C_Item.GetItemCount(5512, false, false) or 0
		local body = "#showtooltip"
		if demonicCount > 0 then
			body = "#showtooltip\n/use item:224464"
		elseif normalCount > 0 then
			body = "#showtooltip\n/use item:5512"
		end
		if not (InCombatLockdown and InCombatLockdown()) then EditMacro(healthMacroName, healthMacroName, nil, body) end
	end
end

local function buildMacroString(item)
	if item == nil then return "#showtooltip" end
	return "#showtooltip\n/use " .. item
end

local lastMacroKey
local wipe = table and table.wipe or nil
local function clearTable(tbl)
	if wipe then
		wipe(tbl)
	else
		for k in pairs(tbl) do
			tbl[k] = nil
		end
	end
end

local spellKnownCache = {}
local spellCooldownCache = {}
local itemCooldownCache = {}
local spellNameCache = {}
local SyncEventRegistration

local function resetCooldownCaches()
	clearTable(spellKnownCache)
	clearTable(spellCooldownCache)
	clearTable(itemCooldownCache)
end

local function numericId(v)
	if not v or not v.getId then return nil end
	local s = v.getId()
	if not s then return nil end
	return tonumber(string.match(s, "%d+"))
end

local function cooldownRemaining(entry)
	if not entry then return math.huge end
	if entry.isSpell then
		local spellId = entry.id
		if not spellId then return math.huge end
		local isKnown = spellKnownCache[spellId]
		if isKnown == nil then
			isKnown = C_SpellBook.IsSpellInSpellBook(spellId) and true or false
			spellKnownCache[spellId] = isKnown
		end
		if not isKnown then return math.huge end
		local cached = spellCooldownCache[spellId]
		local start, duration
		if cached then
			start, duration = cached.start, cached.duration
		else
			local cd = C_Spell.GetSpellCooldown(spellId)
			start = cd and cd.startTime or 0
			duration = cd and cd.duration or 0
			spellCooldownCache[spellId] = { start = start, duration = duration }
		end
		if start == 0 or duration == 0 then return 0 end
		local remain = (start + duration) - GetTime()
		if remain < 0 then return 0 end
		return remain
	end
	local itemID = numericId(entry)
	if not itemID then return 0 end
	local cached = itemCooldownCache[itemID]
	local start, duration
	if cached then
		start, duration = cached.start, cached.duration
	else
		start, duration = GetItemCooldown(itemID)
		itemCooldownCache[itemID] = { start = start or 0, duration = duration or 0 }
	end
	if not start or start == 0 or not duration or duration == 0 then return 0 end
	local remain = (start + duration) - GetTime()
	if remain < 0 then return 0 end
	return remain
end

local function createNeedsTable() return { recup = false, talent = false, allowed = false, macro = false, macroSkipAllowed = false } end

local bucketWindow = 0.20
local bucketPending = false
local needs = createNeedsTable()

local function BucketSchedule(reason)
	if reason == "macroOnly" then
		needs.macro = true
		needs.macroSkipAllowed = true
	elseif reason then
		if needs[reason] ~= nil then
			needs[reason] = true
		else
			needs.macro = true
		end
	end
	if bucketPending then return end
	bucketPending = true
	C_Timer.After(bucketWindow, function()
		bucketPending = false
		local currentNeeds = needs
		needs = createNeedsTable()

		local runRecup = currentNeeds.recup
		local runTalent = currentNeeds.talent
		local runAllowed = currentNeeds.allowed
		local runMacro = currentNeeds.macro
		local skipAllowed = runAllowed or currentNeeds.macroSkipAllowed

		if runRecup and addon.db.healthUseRecuperate and addon.Recuperate and addon.Recuperate.Update then
			addon.Recuperate.Update()
		end
		if runTalent and addon.db.healthUseCustomSpells and addon.Health and addon.Health.functions and addon.Health.functions.refreshTalentCache then
			addon.Health.functions.refreshTalentCache()
		end
		if runTalent then
			clearTable(spellNameCache)
		end
		if runAllowed and addon.Health and addon.Health.functions and addon.Health.functions.updateAllowedHealth then
			addon.Health.functions.updateAllowedHealth()
		end
		if runMacro and addon.Health and addon.Health.functions and addon.Health.functions.updateHealthMacro then
			addon.Health.functions.updateHealthMacro(false, skipAllowed)
		end
	end)
end

local function getKnownCustomSpells()
	local list = {}
	if not addon.db.healthUseCustomSpells then return list end
	local ids = addon.db.healthCustomSpells or {}
	for _, sid in ipairs(ids) do
		local inBook = spellKnownCache[sid]
		if inBook == nil then
			inBook = C_SpellBook.IsSpellInSpellBook(sid) and true or false
			spellKnownCache[sid] = inBook
		end
		if inBook then
			local spellName = spellNameCache[sid]
			if spellName == nil then
				local info = C_Spell.GetSpellInfo(sid)
				spellName = info and info.name or false
				spellNameCache[sid] = spellName
			end
			if spellName and spellName ~= false then
				local obj = addon.functions.newItem(sid, spellName, true)
				obj.type = "spell"
				obj.heal = 0 -- unknown; ordering handled by preferences
				table.insert(list, obj)
			end
		else
			if spellNameCache[sid] ~= nil then spellNameCache[sid] = nil end
		end
	end
	return list
end

local function normalizeOrder(order)
	local seen, out = {}, {}
	for i = 1, 4 do
		local c = order and order[i] or nil
		if c and c ~= "none" and not seen[c] then
			table.insert(out, c)
			seen[c] = true
		end
	end
	for i = #out + 1, 4 do
		out[i] = "none"
	end
	return out
end

local function defaultPriorityOrder()
	return { "stone", "potion", addon.db.healthUseCombatPotions and "combatpotion" or "none", "none" }
end

local function ensurePriorityOrder()
	local order = addon.db.healthPriorityOrder
	if not order or #order == 0 then
		order = defaultPriorityOrder()
	end
	addon.db.healthPriorityOrder = normalizeOrder(order)
end

local function preferCat(cat)
	local prefs = addon.db.healthPreferFirstPrefs
	if prefs == nil then
		-- migrate legacy single checkbox
		prefs = { stones = addon.db.healthPreferStoneFirst == true, spells = false }
		addon.db.healthPreferFirstPrefs = prefs
	end
	return prefs and prefs[cat] == true
end

local function getBestAvailableByType(t)
	local list = addon.Health.filteredHealth
	if not list or #list == 0 then return nil end
	for _, v in ipairs(list) do
		if v.type == t and v.getCount() > 0 then return v end
	end
	return nil
end

-- Helpers to distinguish combat vs non-combat potions
local function isCombatPotionItem(v)
	local id = numericId(v)
	if not id or not addon.Health or not addon.Health._combatPotionByID then return false end
	return addon.Health._combatPotionByID[id] == true
end

local function getBestCombatPotion()
	local list = addon.Health.filteredHealth
	if not list or #list == 0 then return nil end
	for _, v in ipairs(list) do
		if v.type == "potion" and v.getCount() > 0 and isCombatPotionItem(v) then return v end
	end
	return nil
end

local function getBestNonCombatPotion()
	local list = addon.Health.filteredHealth
	if not list or #list == 0 then return nil end
	for _, v in ipairs(list) do
		if v.type == "potion" and v.getCount() > 0 and not isCombatPotionItem(v) then return v end
	end
	return nil
end

local function getBestAvailableAny()
	local list = addon.Health.filteredHealth
	if not list or #list == 0 then return nil end
	for _, v in ipairs(list) do
		if v.getCount() > 0 then return v end
	end
	return nil
end

local function buildResetToken()
	local r = addon.db.healthReset
	if type(r) == "number" then return tostring(r) end
	if r == "10" or r == "30" or r == "60" then return r end
	if r == "target" then return "target" end
	return "combat"
end

local function buildMacro()
	resetCooldownCaches()
	local spells = getKnownCustomSpells()

	-- Priority-based sequence (always)
	local seqCandidates = {}

	local function bestOf(list)
		if not list or #list == 0 then return nil end
		local best, bestRem, bestHeal = nil, math.huge, -1
		for i = 1, #list do
			local v = list[i]
			local rem = cooldownRemaining(v)
			local heal = v.heal or 0
			if (rem < bestRem) or (rem == bestRem and heal > bestHeal) then
				best, bestRem, bestHeal = v, rem, heal
			end
		end
		return best
	end

	local function getCatList(cat)
		if cat == "spell" then
			if addon.db.healthUseCustomSpells then return spells end
			return {}
		end
		local ret = {}
		local list = addon.Health.filteredHealth
		if not list or #list == 0 then return ret end
		for _, v in ipairs(list) do
			if v.getCount() > 0 then
				if cat == "stone" and v.type == "stone" then table.insert(ret, v) end
				if cat == "potion" and v.type == "potion" and not isCombatPotionItem(v) then table.insert(ret, v) end
				if cat == "combatpotion" and v.type == "potion" and isCombatPotionItem(v) then table.insert(ret, v) end
			end
		end
		return ret
	end

	local order = addon.db.healthPriorityOrder
	if not order or #order == 0 then
		order = normalizeOrder(defaultPriorityOrder())
	else
		order = normalizeOrder(order)
	end

	-- Build according to priority order (ignore legacy useBoth/other)
	for i = 1, 4 do
		local cat = order[i]
		if cat and cat ~= "none" then
			if cat == "combatpotion" then
				if addon.db.healthUseCombatPotions then
					local cand = bestOf(getCatList(cat))
					if cand then table.insert(seqCandidates, cand) end
				end
			else
				local cand = bestOf(getCatList(cat))
				if cat == "spell" and not addon.db.healthUseCustomSpells then cand = nil end
				if cand then table.insert(seqCandidates, cand) end
			end
		end
	end

	-- Deduplicate by actual macro token (getId)
	local seen, seqList = {}, {}
	local function toUse(v) return v and v.getId() or nil end
	for _, v in ipairs(seqCandidates) do
		local t = toUse(v)
		if t and not seen[t] then
			table.insert(seqList, t)
			seen[t] = true
		end
	end

	-- Keep sequence reasonably short (max 4)
	while #seqList > 4 do
		table.remove(seqList)
	end

	local resetType = buildResetToken()

	local macroBody
	local key

	-- Optional Recuperate (out of combat) line
	local recuperateLine = ""
	local recuperateKey = ""
	if addon.db.healthUseRecuperate and addon.Recuperate and addon.Recuperate.name and addon.Recuperate.known then
		recuperateLine = string.format("/cast [nocombat] %s", addon.Recuperate.name)
		recuperateKey = "|recup"
	end
	if #seqList >= 1 then
		local parts = { "#showtooltip" }
		if recuperateLine ~= "" then table.insert(parts, recuperateLine) end
		local seqStr = table.concat(seqList, ", ")
		if recuperateLine ~= "" then
			table.insert(parts, string.format("/castsequence [combat] reset=%s %s", resetType, seqStr))
		else
			table.insert(parts, string.format("/castsequence reset=%s %s", resetType, seqStr))
		end
		macroBody = table.concat(parts, "\n")
		key = string.format("seq:%s|%s%s", table.concat(seqList, "|"), resetType, recuperateKey)
	else
		local parts = { "#showtooltip" }
		if recuperateLine ~= "" then table.insert(parts, recuperateLine) end
		macroBody = table.concat(parts, "\n")
		key = "empty" .. recuperateKey
	end

	if key ~= lastMacroKey then
		-- Final safety check to avoid protected EditMacro during combat lockdown
		if InCombatLockdown and InCombatLockdown() then return end
		if not GetMacroInfo(healthMacroName) then createMacroIfMissing() end
		if GetMacroInfo(healthMacroName) then EditMacro(healthMacroName, healthMacroName, nil, macroBody) end
		lastMacroKey = key
	end
end

function addon.Health.functions.updateHealthMacro(ignoreCombat, skipAllowedRefresh)
	if not addon.db.healthMacroEnabled then
		SyncEventRegistration()
		return
	end
	if UnitAffectingCombat("player") and ignoreCombat == false then return end
	createMacroIfMissing()
	if not skipAllowedRefresh then addon.Health.functions.updateAllowedHealth() end
	buildMacro()
end

-- Events + throttle similar to drinks
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("UNIT_MAXHEALTH")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
-- Optional spell/cooldown events are registered dynamically

SyncEventRegistration = function()
	if not addon.db then return end
	if not addon.db.healthMacroEnabled then
		frame:UnregisterEvent("SPELLS_CHANGED")
		frame:UnregisterEvent("PLAYER_TALENT_UPDATE")
		frame:UnregisterEvent("BAG_UPDATE_COOLDOWN")
		return
	end

	if addon.db.healthUseRecuperate or addon.db.healthUseCustomSpells then
		frame:RegisterEvent("SPELLS_CHANGED")
		frame:RegisterEvent("PLAYER_TALENT_UPDATE")
	else
		frame:UnregisterEvent("SPELLS_CHANGED")
		frame:UnregisterEvent("PLAYER_TALENT_UPDATE")
	end

	if addon.db.healthReorderByCooldown then
		frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
	else
		frame:UnregisterEvent("BAG_UPDATE_COOLDOWN")
	end
end

addon.Health.functions.syncEventRegistration = SyncEventRegistration
addon.Health.functions.ensurePriorityOrder = ensurePriorityOrder

frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_LOGIN" then
		-- Migrate old settings to new priority model
		local function migrateOldPriority()
			if addon.db.healthPriorityOrder ~= nil then return end
			local hasSpells = addon.db.healthUseCustomSpells == true
			local prefer = addon.db.healthPreferFirstPrefs
			local preferSpells = false
			if prefer == nil then
				-- legacy: healthPreferStoneFirst not used anymore
			else
				preferSpells = prefer.spells == true
			end
			local tmp = {}
			local function addOnce(cat)
				if not cat or cat == "none" then return end
				for _, v in ipairs(tmp) do
					if v == cat then return end
				end
				table.insert(tmp, cat)
			end
			-- Order from legacy prefs: preferSpells puts spell first
			if preferSpells and hasSpells then addOnce("spell") end
			-- default: stones, then potions
			addOnce("stone")
			addOnce("potion")
			-- include spells somewhere if enabled but not preferred first
			if hasSpells and not preferSpells then addOnce("spell") end
			-- combat potion if enabled
			if addon.db.healthUseCombatPotions then addOnce("combatpotion") end
			-- clamp to 4 slots and pad with none
			while #tmp > 4 do
				table.remove(tmp)
			end
			for i = #tmp + 1, 4 do
				tmp[i] = "none"
			end
			addon.db.healthPriorityOrder = tmp
		end
		migrateOldPriority()
		ensurePriorityOrder()
		SyncEventRegistration()
		if addon.db.healthUseRecuperate then BucketSchedule("recup") end
		if addon.db.healthUseCustomSpells then BucketSchedule("talent") end
		BucketSchedule("allowed")
		BucketSchedule("macro")
	elseif event == "PLAYER_REGEN_ENABLED" then
		if addon.db.healthUseCustomSpells then BucketSchedule("talent") end
		BucketSchedule("allowed")
		BucketSchedule("macro")
	elseif event == "BAG_UPDATE_DELAYED" then
		BucketSchedule("allowed")
		BucketSchedule("macro")
	elseif event == "PLAYER_LEVEL_UP" then
		BucketSchedule("allowed")
		if not UnitAffectingCombat("player") then BucketSchedule("macro") end
	elseif event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
		if addon.db.healthUseRecuperate then BucketSchedule("recup") end
		if addon.db.healthUseCustomSpells then
			BucketSchedule("talent")
			BucketSchedule("allowed")
			BucketSchedule("macro")
		end
	elseif event == "UNIT_MAXHEALTH" then
		if arg1 == "player" and not UnitAffectingCombat("player") then
			BucketSchedule("allowed")
			BucketSchedule("macro")
		end
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		BucketSchedule("allowed")
		BucketSchedule("macro")
	elseif event == "BAG_UPDATE_COOLDOWN" then
		if addon.db.healthReorderByCooldown then BucketSchedule("macroOnly") end
	end
end)
