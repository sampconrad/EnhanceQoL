local addonName, addon = ...

addon.CharacterStatsFormatting = addon.CharacterStatsFormatting or {}
local CharacterStatsFormatting = addon.CharacterStatsFormatting

local hooked = false

local function isEnabled() return addon.db and addon.db.characterStatsFormattingEnabled end

local function formatRating(value)
	if value == nil then return nil end
	if BreakUpLargeNumbers then
		local ok, formatted = pcall(BreakUpLargeNumbers, value)
		if ok and formatted then return formatted end
	end
	return tostring(value)
end

local function formatPercent(value)
	if type(value) ~= "number" then return nil end
	return string.format("%.2f %%", value)
end

local function getCritRating()
	-- Mirror PaperDollFrame_SetCritChance selection to match the displayed crit type.
	if not (GetCombatRating and GetSpellCritChance and GetRangedCritChance and GetCritChance) then return nil end
	local spellCrit = GetSpellCritChance(2)
	if type(spellCrit) ~= "number" then return GetCombatRating(_G.CR_CRIT_MELEE) end

	if MAX_SPELL_SCHOOLS then
		for i = 3, MAX_SPELL_SCHOOLS do
			local crit = GetSpellCritChance(i)
			if type(crit) == "number" and crit < spellCrit then spellCrit = crit end
		end
	end

	local rangedCrit = GetRangedCritChance()
	local meleeCrit = GetCritChance()

	if spellCrit >= rangedCrit and spellCrit >= meleeCrit then return GetCombatRating(_G.CR_CRIT_SPELL) end
	if rangedCrit >= meleeCrit then return GetCombatRating(_G.CR_CRIT_RANGED) end
	return GetCombatRating(_G.CR_CRIT_MELEE)
end

local function getStatRating(label)
	if label == STAT_CRITICAL_STRIKE then return getCritRating() end
	if label == STAT_HASTE then return GetCombatRating(_G.CR_HASTE_MELEE) end
	if label == STAT_MASTERY then return GetCombatRating(_G.CR_MASTERY) end
	if label == STAT_SPEED then return GetCombatRating(_G.CR_SPEED) end
	if label == STAT_LIFESTEAL then return GetCombatRating(_G.CR_LIFESTEAL) end
	if label == STAT_AVOIDANCE then return GetCombatRating(_G.CR_AVOIDANCE) end
	if label == STAT_VERSATILITY then return GetCombatRating(_G.CR_VERSATILITY_DAMAGE_DONE) end
	return nil
end

local function updateStatDisplay(statFrame, label, text, isPercentage, numericValue)
	if not isEnabled() then return end
	if not (statFrame and statFrame.Value) then return end

	local rating = getStatRating(label)
	if not rating then return end

	local ratingText = formatRating(rating)
	local percentText = formatPercent(numericValue)
	if not ratingText or not percentText then return end

	statFrame.Value:SetText(string.format("%s | %s", ratingText, percentText))
end

local function refreshStats()
	if _G.PaperDollFrame_UpdateStats then _G.PaperDollFrame_UpdateStats() end
end

function CharacterStatsFormatting.Enable()
	if hooked then
		refreshStats()
		return
	end
	if type(_G.PaperDollFrame_SetLabelAndText) ~= "function" then return end
	hooksecurefunc("PaperDollFrame_SetLabelAndText", updateStatDisplay)
	hooked = true
	refreshStats()
end

function CharacterStatsFormatting.Disable()
	if hooked then
		addon.variables = addon.variables or {}
		addon.variables.requireReload = true
	end
	refreshStats()
end

function CharacterStatsFormatting.Refresh()
	if isEnabled() then
		CharacterStatsFormatting.Enable()
	elseif hooked then
		CharacterStatsFormatting.Disable()
	end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(_, event, name)
	if event == "PLAYER_LOGIN" then
		CharacterStatsFormatting.Refresh()
		return
	end
	if event == "ADDON_LOADED" and (name == "Blizzard_CharacterUI" or name == "Blizzard_UIPanels_Game") then CharacterStatsFormatting.Refresh() end
end)
