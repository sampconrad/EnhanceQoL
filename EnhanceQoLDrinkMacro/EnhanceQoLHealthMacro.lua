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

local function numericId(v)
	if not v or not v.getId then return nil end
	local s = v.getId()
	if not s then return nil end
	return tonumber(string.match(s, "%d+"))
end

local function isOffCooldown(entry)
	if not entry then return false end
	-- Spells: check spell cooldown if known
	if entry.isSpell then
		if not C_SpellBook.IsSpellInSpellBook(entry.id) then return false end
		local cd = C_Spell.GetSpellCooldown(entry.id)
		if not cd or not cd.startTime or cd.startTime == 0 then return true end
		if not cd.duration or cd.duration == 0 then return true end
		local now = GetTime()
		return (cd.startTime + cd.duration) <= now
	end
	-- Items
	local itemID = numericId(entry)
	if not itemID then return true end
	local start, duration, enable = GetItemCooldown(itemID)
	if not start or start == 0 then return true end
	if duration == 0 then return true end
	local now = GetTime()
	return (start + duration) <= now
end

local function cooldownRemaining(entry)
	if not entry then return math.huge end
	if entry.isSpell then
		if not C_SpellBook.IsSpellInSpellBook(entry.id) then return math.huge end
		local cd = C_Spell.GetSpellCooldown(entry.id)
		if not cd or not cd.startTime or cd.startTime == 0 or not cd.duration or cd.duration == 0 then return 0 end
		local remain = (cd.startTime + cd.duration) - GetTime()
		if remain < 0 then return 0 end
		return remain
	end
	local itemID = numericId(entry)
	if not itemID then return 0 end
	local start, duration, enable = GetItemCooldown(itemID)
	if not start or start == 0 or not duration or duration == 0 then return 0 end
	local remain = (start + duration) - GetTime()
	if remain < 0 then return 0 end
	return remain
end

local function getKnownCustomSpells()
	local list = {}
	if not addon.db.healthUseCustomSpells then return list end
	local ids = addon.db.healthCustomSpells or {}
	for _, sid in ipairs(ids) do
		local info = C_Spell.GetSpellInfo(sid)
		if info and info.name and C_SpellBook.IsSpellInSpellBook(sid) then
			local obj = addon.functions.newItem(sid, info.name, true)
			obj.type = "spell"
			obj.heal = 0 -- unknown; ordering handled by preferences
			table.insert(list, obj)
		end
	end
	return list
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
	if not id or not addon.Health or not addon.Health.healthList then return false end
	for _, e in ipairs(addon.Health.healthList) do
		if e.id == id then return e.isCombatPotion == true end
	end
	return false
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
	local stone = getBestAvailableByType("stone")
	local nonCombatPotion = getBestNonCombatPotion()
	local combatPotion = addon.db.healthUseCombatPotions and getBestCombatPotion() or nil
	local spells = getKnownCustomSpells()

	-- Priority-based sequence (always)
	local seqCandidates = {}

	local function bestOf(list)
		if not list or #list == 0 then return nil end
		table.sort(list, function(a, b)
			local ra, rb = cooldownRemaining(a), cooldownRemaining(b)
			if ra ~= rb then return ra < rb end
			return (a.heal or 0) > (b.heal or 0)
		end)
		return list[1]
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

	local function normalizeOrder(order)
		local seen, out = {}, {}
		for i = 1, 4 do
			local c = order and order[i] or nil
			if c and c ~= "none" and not seen[c] then
				table.insert(out, c)
				seen[c] = true
			end
		end
		-- fill remaining with none
		for i = #out + 1, 4 do
			out[i] = "none"
		end
		return out
	end

	local order = addon.db.healthPriorityOrder
	-- default order similar to old behavior
	if not order then order = { "stone", "potion", addon.db.healthUseCombatPotions and "combatpotion" or "none", "none" } end
	order = normalizeOrder(order)
	addon.db.healthPriorityOrder = order

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

function addon.Health.functions.updateHealthMacro(ignoreCombat)
	if not addon.db.healthMacroEnabled then return end
	if UnitAffectingCombat("player") and ignoreCombat == false then return end
	createMacroIfMissing()
	addon.Health.functions.updateAllowedHealth()
	buildMacro()
end

-- Events + throttle similar to drinks
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("PLAYER_TALENT_UPDATE")
frame:RegisterEvent("UNIT_MAXHEALTH")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("BAG_UPDATE_COOLDOWN")

local pendingUpdate = false
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
		if addon.Recuperate and addon.Recuperate.Update then addon.Recuperate.Update() end
		if addon.Health and addon.Health.functions and addon.Health.functions.refreshTalentCache then addon.Health.functions.refreshTalentCache() end
		addon.Health.functions.updateAllowedHealth()
		addon.Health.functions.updateHealthMacro(false)
	elseif event == "PLAYER_REGEN_ENABLED" then
		if addon.Health and addon.Health.functions and addon.Health.functions.refreshTalentCache then addon.Health.functions.refreshTalentCache() end
		addon.Health.functions.updateAllowedHealth()
		addon.Health.functions.updateHealthMacro(true)
	elseif event == "BAG_UPDATE_DELAYED" then
		if not pendingUpdate then
			pendingUpdate = true
			C_Timer.After(0.15, function()
				addon.Health.functions.updateHealthMacro(false)
				pendingUpdate = false
			end)
		end
	elseif event == "PLAYER_LEVEL_UP" then
		addon.Health.functions.updateAllowedHealth()
		if not UnitAffectingCombat("player") then addon.Health.functions.updateHealthMacro(true) end
	elseif event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
		if addon.Recuperate and addon.Recuperate.Update then addon.Recuperate.Update() end
		if addon.Health and addon.Health.functions and addon.Health.functions.refreshTalentCache then addon.Health.functions.refreshTalentCache() end
		addon.Health.functions.updateAllowedHealth()
		addon.Health.functions.updateHealthMacro(false)
	elseif event == "UNIT_MAXHEALTH" then
		if arg1 == "player" then
			addon.Health.functions.updateAllowedHealth()
			addon.Health.functions.updateHealthMacro(false)
		end
	elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_UPDATE_COOLDOWN" then
		addon.Health.functions.updateAllowedHealth()
		addon.Health.functions.updateHealthMacro(false)
	end
end)

-- UI section for Health Macro (mounted under Drink Macro)
function addon.Health.functions.addHealthFrame(container)
	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	container:AddChild(wrapper)

	local group = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(group)

	local cb = addon.functions.createCheckboxAce(L["Enable Health Macro"], addon.db["healthMacroEnabled"], function(_, _, value)
		addon.db["healthMacroEnabled"] = value
		addon.Health.functions.updateHealthMacro(false)
		container:ReleaseChildren()
		addon.Health.functions.addHealthFrame(container)
	end)
	group:AddChild(cb)

	-- If disabled, render nothing else
	if not addon.db["healthMacroEnabled"] then return end

	-- Use Healthstone and Potion is superseded by priority UI; hidden

	-- Recuperate option (casts Recuperate out of combat)
	local cbRecup = addon.functions.createCheckboxAce(L["Use Recuperate out of combat"], addon.db["healthUseRecuperate"], function(_, _, value)
		addon.db["healthUseRecuperate"] = value
		addon.Health.functions.updateHealthMacro(false)
	end)
	group:AddChild(cbRecup)

	-- Allow using combat-only healing potions (from Health.lua entries flagged isCombatPotion)
	local cbCombatPot = addon.functions.createCheckboxAce(L["Use Combat potions for health macro"], addon.db["healthUseCombatPotions"], function(_, _, value)
		addon.db["healthUseCombatPotions"] = value
		-- Auto-add/remove category in priority when toggled
		addon.db.healthPriorityOrder = addon.db.healthPriorityOrder or { "stone", "potion", value and "combatpotion" or "none", "none" }
		if value then
			local exists = false
			for i = 1, 4 do
				if addon.db.healthPriorityOrder[i] == "combatpotion" then
					exists = true
					break
				end
			end
			if not exists then
				for i = 1, 4 do
					if addon.db.healthPriorityOrder[i] == "none" then
						addon.db.healthPriorityOrder[i] = "combatpotion"
						break
					end
				end
			end
		else
			for i = 1, 4 do
				if addon.db.healthPriorityOrder[i] == "combatpotion" then addon.db.healthPriorityOrder[i] = "none" end
			end
		end
		addon.Health.functions.updateHealthMacro(false)
	end)
	group:AddChild(cbCombatPot)

	-- Priority ordering UI (overrides legacy preferences/useBoth when set)
	do
		local labels = {
			spell = L["CategoryCustomSpells"] or (L["Custom Spells"] or "Custom Spells"),
			stone = L["CategoryHealthstones"] or (L["Prefer Healthstone first"] or "Healthstones"),
			potion = L["CategoryPotions"] or "Potions",
			combatpotion = L["CategoryCombatPotions"] or (L["Use Combat potions for health macro"] or "Combat potions"),
			none = L["None"] or "None",
		}
		local baseOrder = { "stone", "potion", "combatpotion", "spell" }

		-- Ensure DB exists
		addon.db.healthPriorityOrder = addon.db.healthPriorityOrder or { "stone", "potion", addon.db.healthUseCombatPotions and "combatpotion" or "none", "none" }

		local function availableFor(slot)
			local used = {}
			for i = 1, slot - 1 do
				local c = addon.db.healthPriorityOrder[i]
				if c and c ~= "none" then used[c] = true end
			end
			local list, order = {}, {}
			-- Add categories except used, and respecting feature toggles
			for _, k in ipairs(baseOrder) do
				if not used[k] then
					if k == "spell" and not addon.db.healthUseCustomSpells then
						-- skip when custom spells disabled
					elseif k == "combatpotion" and not addon.db.healthUseCombatPotions then
						-- skip when combat potions disabled
					else
						list[k] = labels[k]
						table.insert(order, k)
					end
				end
			end
			-- Always include none
			list["none"] = labels.none
			table.insert(order, "none")
			return list, order
		end

		local function onPick(self, _, val, idx)
			addon.db.healthPriorityOrder[idx] = val
			-- Remove duplicates in later slots
			if val ~= "none" then
				for j = 1, 4 do
					if j ~= idx and addon.db.healthPriorityOrder[j] == val then addon.db.healthPriorityOrder[j] = "none" end
				end
			end
			addon.Health.functions.updateHealthMacro(false)
			container:ReleaseChildren()
			addon.Health.functions.addHealthFrame(container)
		end

		local header = addon.functions.createLabelAce(L["PriorityOrder"] or "Priority order", nil, nil, 12)
		header:SetFullWidth(true)
		group:AddChild(header)

		for i = 1, 4 do
			local list, order = availableFor(i)
			local lbl = (L["PrioritySlot"] or "Priority %d"):format(i)
			local drop = addon.functions.createDropdownAce(lbl, list, order, function(self, _, val) onPick(self, _, val, i) end)
			local cur = addon.db.healthPriorityOrder[i] or "none"
			if not list[cur] then cur = "none" end
			drop:SetValue(cur)
			drop:SetFullWidth(false)
			drop:SetWidth(260)
			group:AddChild(drop)
		end
	end

	-- local cbOther = addon.functions.createCheckboxAce(L["Allow other healing items"], addon.db["healthAllowOther"], function(_, _, value)
	-- 	addon.db["healthAllowOther"] = value
	-- 	addon.Health.functions.updateHealthMacro(false)
	-- end)
	-- group:AddChild(cbOther)

	-- Reorder by cooldown is always enforced now (option removed)

	local resetList = { combat = L["Reset: Combat"], target = L["Reset: Target"], ["10"] = L["Reset: 10s"], ["30"] = L["Reset: 30s"], ["60"] = L["Reset: 60s"] }
	local order = { "combat", "target", "10", "30", "60" }
	local dropReset = addon.functions.createDropdownAce(L["Reset condition"], resetList, order, function(self, _, val)
		addon.db["healthReset"] = val
		self:SetValue(val)
		addon.Health.functions.updateHealthMacro(false)
	end)
	dropReset:SetValue(addon.db["healthReset"])
	group:AddChild(dropReset)

	group:AddChild(addon.functions.createSpacerAce())
	local label = addon.functions.createLabelAce(string.format(L["healthMacroPlaceOnBar"], healthMacroName), nil, nil, 12)
	label:SetFullWidth(true)
	group:AddChild(label)

	group:AddChild(addon.functions.createSpacerAce())
	local gold = { r = 1, g = 0.843, b = 0 }
	local function buildPriorityHint()
		local labels = {
			spell = L["CategoryCustomSpells"] or (L["Custom Spells"] or "Custom Spells"),
			stone = L["CategoryHealthstones"] or (L["Prefer Healthstone first"] or "Healthstones"),
			potion = L["CategoryPotions"] or "Potions",
			combatpotion = L["CategoryCombatPotions"] or (L["Use Combat potions for health macro"] or "Combat potions"),
		}
		local order = addon.db.healthPriorityOrder or {}
		local parts = {}
		for i = 1, 4 do
			local c = order[i]
			if c and c ~= "none" then
				if c == "spell" and not addon.db.healthUseCustomSpells then
					-- skip when custom spells disabled
				elseif c == "combatpotion" and not addon.db.healthUseCombatPotions then
					-- skip when combat potions disabled
				else
					table.insert(parts, labels[c] or c)
				end
			end
		end
		if #parts == 0 then return (L["healthMacroWillUse"] or "Will use (in order): %s"):format(L["None"] or "None") end
		return (L["healthMacroWillUse"] or "Will use (in order): %s"):format(table.concat(parts, ", "))
	end
	local hint = addon.functions.createLabelAce(buildPriorityHint(), gold, nil, 14)
	hint:SetFullWidth(true)
	group:AddChild(hint)

	if addon.variables.unitClass == "WARLOCK" then
		group:AddChild(addon.functions.createSpacerAce())
		local tip = addon.functions.createLabelAce(L["healthMacroTipReset"], nil, nil, 12)
		tip:SetFullWidth(true)
		group:AddChild(tip)
	end

	-- Custom spells UI
	group:AddChild(addon.functions.createSpacerAce())
	local cbUseSpells = addon.functions.createCheckboxAce(L["Use custom spells"] or "Use custom spells", addon.db["healthUseCustomSpells"], function(_, _, value)
		addon.db["healthUseCustomSpells"] = value
		-- Auto-add/remove 'spell' in priority list when toggled
		addon.db.healthPriorityOrder = addon.db.healthPriorityOrder or { "stone", "potion", addon.db.healthUseCombatPotions and "combatpotion" or "none", "none" }
		if value then
			local exists = false
			for i = 1, 4 do
				if addon.db.healthPriorityOrder[i] == "spell" then
					exists = true
					break
				end
			end
			if not exists then
				for i = 1, 4 do
					if addon.db.healthPriorityOrder[i] == "none" then
						addon.db.healthPriorityOrder[i] = "spell"
						break
					end
				end
			end
		else
			for i = 1, 4 do
				if addon.db.healthPriorityOrder[i] == "spell" then addon.db.healthPriorityOrder[i] = "none" end
			end
		end
		addon.Health.functions.updateHealthMacro(false)
		container:ReleaseChildren()
		addon.Health.functions.addHealthFrame(container)
	end)
	group:AddChild(cbUseSpells)

	if addon.db["healthUseCustomSpells"] then
		-- Add editbox for entering a SpellID
		local edit = addon.functions.createEditboxAce(L["Add SpellID"] or "Add SpellID", nil, function(self, _, text)
			local sid = tonumber(text)
			if sid then
				local info = C_Spell.GetSpellInfo(sid)
				if info and info.name then
					addon.db.healthCustomSpells = addon.db.healthCustomSpells or {}
					local exists = false
					for _, v in ipairs(addon.db.healthCustomSpells) do
						if v == sid then
							exists = true
							break
						end
					end
					if not exists then table.insert(addon.db.healthCustomSpells, sid) end
					self:SetText("")
					addon.Health.functions.updateHealthMacro(false)
					container:ReleaseChildren()
					addon.Health.functions.addHealthFrame(container)
				end
			end
		end)
		group:AddChild(edit)

		-- List saved spells with names and remove buttons
		local spells = addon.db.healthCustomSpells or {}
		for _, sid in ipairs(spells) do
			local row = addon.functions.createContainer("SimpleGroup", "Flow")
			row:SetFullWidth(true)
			local lbl = addon.functions.createLabelAce("", nil, nil, 12)
			local info = C_Spell.GetSpellInfo(sid)
			if info and info.name then
				lbl:SetText((L["Custom Spells"] and "" or "") .. info.name .. " (" .. sid .. ")")
			else
				lbl:SetText((L["Custom Spells"] and "" or "") .. "Unknown" .. " (" .. sid .. ")")
			end
			lbl:SetRelativeWidth(0.8)
			row:AddChild(lbl)

			local removeIcon = LibStub("AceGUI-3.0"):Create("Icon")
			removeIcon:SetLabel("")
			removeIcon:SetImage("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
			removeIcon:SetImageSize(16, 16)
			removeIcon:SetRelativeWidth(0.2)
			removeIcon:SetHeight(16)
			removeIcon:SetCallback("OnClick", function()
				for i, v in ipairs(addon.db.healthCustomSpells) do
					if v == sid then
						table.remove(addon.db.healthCustomSpells, i)
						break
					end
				end
				addon.Health.functions.updateHealthMacro(false)
				container:ReleaseChildren()
				addon.Health.functions.addHealthFrame(container)
			end)
			row:AddChild(removeIcon)
			group:AddChild(row)
		end
	end
end
