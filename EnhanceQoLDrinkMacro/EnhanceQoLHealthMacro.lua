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

local function isOffCooldown(item)
	if not item then return false end
	local itemID = numericId(item)
	if not itemID then return true end
	local start, duration, enable = GetItemCooldown(itemID)
	if not start or start == 0 then return true end
	if duration == 0 then return true end
	local now = GetTime()
	return (start + duration) <= now
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
	local useBoth = addon.db.healthUseBoth
	local preferStone = addon.db.healthPreferStoneFirst

    local stone = getBestAvailableByType("stone")
    local nonCombatPotion = getBestNonCombatPotion()
    local combatPotion = addon.db.healthUseCombatPotions and getBestCombatPotion() or nil

    -- optionally include other healing items
    local other
    if addon.db.healthAllowOther then other = getBestAvailableByType("other") end

    local first, second

    if addon.db.healthUseCombatPotions then
        -- When combat potions are enabled, always try to pair one normal heal (stone or non-combat potion)
        -- with one combat potion, if both are available.
        local normal
        -- Choose normal according to preference and availability
        if preferStone and stone then
            normal = stone
        else
            -- pick the stronger of stone vs nonCombatPotion if preference not forcing stone
            if stone and nonCombatPotion then
                if (stone.heal or 0) >= (nonCombatPotion.heal or 0) then normal = stone else normal = nonCombatPotion end
            else
                normal = stone or nonCombatPotion
            end
        end

        -- Fallback to 'other' if configured and no normal found
        if not normal and addon.db.healthAllowOther then normal = other end

        if normal and combatPotion then
            local nReady = isOffCooldown(normal)
            local cReady = isOffCooldown(combatPotion)
            if addon.db.healthReorderByCooldown and (nReady ~= cReady) then
                if nReady then first, second = normal, combatPotion else first, second = combatPotion, normal end
            else
                -- If preference is stone-first and our normal is stone, keep it first; otherwise default to normal first
                if preferStone and normal == stone then
                    first, second = normal, combatPotion
                else
                    -- default order: higher heal first
                    if (normal.heal or 0) >= (combatPotion.heal or 0) then
                        first, second = normal, combatPotion
                    else
                        first, second = combatPotion, normal
                    end
                end
            end
        else
            -- Only one of them available
            first = normal or combatPotion or other
        end
    else
        -- Original behavior when combat potions are not enabled
        local potion = nonCombatPotion -- only non-combat potions

        if useBoth then
            -- fallback: if one is missing, try other (avoid duplicates)
            if not stone and addon.db.healthAllowOther then stone = other end
            if not potion and addon.db.healthAllowOther then
                local sid = numericId(stone)
                local oid = numericId(other)
                if not sid or not oid or sid ~= oid then potion = other end
            end

            -- decide order based on availability, cooldown, then healing amount unless explicitly preferring stone
            if stone and potion then
                local stoneReady = isOffCooldown(stone)
                local potionReady = isOffCooldown(potion)
                if addon.db.healthReorderByCooldown and (stoneReady ~= potionReady) then
                    if stoneReady then first, second = stone, potion else first, second = potion, stone end
                else
                    if preferStone then
                        first, second = stone, potion
                    else
                        local hS = stone.heal or 0
                        local hP = potion.heal or 0
                        if hS >= hP then first, second = stone, potion else first, second = potion, stone end
                    end
                end
            else
                first = stone or potion or other
            end
        else
            -- pick the single best by heal value among available
            local candidates = {}
            if stone then table.insert(candidates, stone) end
            if potion then table.insert(candidates, potion) end
            if addon.db.healthAllowOther and other then table.insert(candidates, other) end
            table.sort(candidates, function(a, b) return (a.heal or 0) > (b.heal or 0) end)
            first = candidates[1] or getBestAvailableAny()
        end
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
	if first and second then
		-- castsequence (always using item: ids); ensure not identical
		local function toUse(v) return v and v.getId() or nil end
		local a = toUse(first)
		local b = toUse(second)
		if a and b and a == b then
			local parts = { "#showtooltip" }
			if recuperateLine ~= "" then table.insert(parts, recuperateLine) end
			if a then
				if recuperateLine ~= "" then
					table.insert(parts, string.format("/use [combat] %s", a))
				else
					table.insert(parts, string.format("/use %s", a))
				end
			end
			macroBody = table.concat(parts, "\n")
			key = string.format("single:%s%s", a or "", recuperateKey)
		else
			local parts = { "#showtooltip" }
			if recuperateLine ~= "" then table.insert(parts, recuperateLine) end
			if recuperateLine ~= "" then
				table.insert(parts, string.format("/castsequence [combat] reset=%s %s, %s", resetType, a or "", b or ""))
			else
				table.insert(parts, string.format("/castsequence reset=%s %s, %s", resetType, a or "", b or ""))
			end
			macroBody = table.concat(parts, "\n")
			key = string.format("seq:%s|%s|%s%s", a or "", b or "", resetType, recuperateKey)
		end
	elseif first then
		-- single use: use the actual item found
		local parts = { "#showtooltip" }
		if recuperateLine ~= "" then table.insert(parts, recuperateLine) end
		if recuperateLine ~= "" then
			table.insert(parts, string.format("/use [combat] %s", first.getId()))
		else
			table.insert(parts, string.format("/use %s", first.getId()))
		end
		macroBody = table.concat(parts, "\n")
		key = string.format("single:%s%s", first.getId(), recuperateKey)
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

	local cbBoth = addon.functions.createCheckboxAce(L["Use Healthstone and Potion"], addon.db["healthUseBoth"], function(_, _, value)
		addon.db["healthUseBoth"] = value
		addon.Health.functions.updateHealthMacro(false)
		container:ReleaseChildren()
		addon.Health.functions.addHealthFrame(container)
	end)
	group:AddChild(cbBoth)

	-- Recuperate option (casts Recuperate out of combat)
	local cbRecup = addon.functions.createCheckboxAce(L["Use Recuperate out of combat"], addon.db["healthUseRecuperate"], function(_, _, value)
		addon.db["healthUseRecuperate"] = value
		addon.Health.functions.updateHealthMacro(false)
	end)
	group:AddChild(cbRecup)

	-- Allow using combat-only healing potions (from Health.lua entries flagged isCombatPotion)
    local cbCombatPot = addon.functions.createCheckboxAce(
        L["Use Combat potions for health macro"],
        addon.db["healthUseCombatPotions"],
        function(_, _, value)
            addon.db["healthUseCombatPotions"] = value
            addon.Health.functions.updateHealthMacro(false)
        end
    )
	group:AddChild(cbCombatPot)

	if addon.db["healthUseBoth"] then
		local cbPrefer = addon.functions.createCheckboxAce(L["Prefer Healthstone first"], addon.db["healthPreferStoneFirst"], function(_, _, value)
			addon.db["healthPreferStoneFirst"] = value
			addon.Health.functions.updateHealthMacro(false)
		end)
		group:AddChild(cbPrefer)
	end

	-- local cbOther = addon.functions.createCheckboxAce(L["Allow other healing items"], addon.db["healthAllowOther"], function(_, _, value)
	-- 	addon.db["healthAllowOther"] = value
	-- 	addon.Health.functions.updateHealthMacro(false)
	-- end)
	-- group:AddChild(cbOther)

	local cbReorder = addon.functions.createCheckboxAce(L["Reorder by cooldown on combat end"], addon.db["healthReorderByCooldown"], function(_, _, value)
		addon.db["healthReorderByCooldown"] = value
		addon.Health.functions.updateHealthMacro(false)
	end)
	group:AddChild(cbReorder)

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
	local hint = addon.functions.createLabelAce(L["healthMacroBestFirst"], gold, nil, 14)
	hint:SetFullWidth(true)
	group:AddChild(hint)

	if addon.variables.unitClass == "WARLOCK" then
		group:AddChild(addon.functions.createSpacerAce())
		local tip = addon.functions.createLabelAce(L["healthMacroTipReset"], nil, nil, 12)
		tip:SetFullWidth(true)
		group:AddChild(tip)
	end
end
