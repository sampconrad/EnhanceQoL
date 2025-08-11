local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local cm = addon.CombatMeter
local band = bit.band
local bor = bit.bor

cm.inCombat = false
cm.fightStartTime = 0
cm.fightDuration = 0

cm.players = cm.players or {}
cm.overallPlayers = cm.overallPlayers or {}
cm.playerPool = cm.playerPool or {}
cm.overallDuration = cm.overallDuration or 0

local groupMask = bor(COMBATLOG_OBJECT_AFFILIATION_MINE, COMBATLOG_OBJECT_AFFILIATION_PARTY, COMBATLOG_OBJECT_AFFILIATION_RAID)

local lastAbsorbSourceByDest = {}

local function acquirePlayer(tbl, guid, name)
	local players = tbl
	local player = players[guid]
	if not player then
		local pool = cm.playerPool
		if #pool > 0 then
			player = table.remove(pool)
			wipe(player)
		else
			player = {}
		end
		player.guid = guid
		player.name = name
		player.damage = 0
		player.healing = 0
		players[guid] = player
	end
	return player
end

local function releasePlayers(players)
	local pool = cm.playerPool
	for guid in pairs(players) do
		local player = players[guid]
		wipe(player)
		pool[#pool + 1] = player
		players[guid] = nil
	end
end

local frame = CreateFrame("Frame")
cm.frame = frame

local dmgIdx = {
	SWING_DAMAGE = 1,
	RANGE_DAMAGE = 4,
	SPELL_DAMAGE = 4,
	SPELL_PERIODIC_DAMAGE = 4,
	DAMAGE_SHIELD = 4,
	DAMAGE_SPLIT = 4,
	ENVIRONMENTAL_DAMAGE = 2,
}
local healIdx = {
	SPELL_HEAL = { 4, 5 },
	SPELL_PERIODIC_HEAL = { 4, 5 },
}

local function handleCLEU(timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, ...)
	local argc = select("#", ...)
	-- Note: We intentionally ignore *_MISSED ABSORB to avoid double-counting with SPELL_ABSORBED (matches Details behavior)
	if not (dmgIdx[subevent] or healIdx[subevent] or subevent == "SPELL_ABSORBED") then return end

	local idx = dmgIdx[subevent]
	if idx then
		if not sourceGUID or band(sourceFlags or 0, groupMask) == 0 then return end
		local amount = select(idx, ...)
		if not amount or amount <= 0 then return end
		local player = acquirePlayer(cm.players, sourceGUID, sourceName)
		local overall = acquirePlayer(cm.overallPlayers, sourceGUID, sourceName)
		player.damage = player.damage + amount
		overall.damage = overall.damage + amount
		return
	end

	local hidx = healIdx[subevent]
	if hidx then
		if not sourceGUID or band(sourceFlags or 0, groupMask) == 0 then return end
		local amount = (select(hidx[1], ...) or 0) - (select(hidx[2], ...) or 0)
		if not amount or amount <= 0 then return end
		local player = acquirePlayer(cm.players, sourceGUID, sourceName)
		local overall = acquirePlayer(cm.overallPlayers, sourceGUID, sourceName)
		player.healing = player.healing + amount
		overall.healing = overall.healing + amount
		return
	end

	-- We count absorbs exclusively via SPELL_ABSORBED. Some clients also emit *_MISSED with ABSORB for the same event; counting both leads to double credits.
	if subevent == "SPELL_ABSORBED" then
		-- SPELL_ABSORBED tail layout has **9** stable fields:
		-- absorberGUID, absorberName, absorberFlags, absorberRaidFlags,
		-- absorbingSpellID, absorbingSpellName, absorbingSpellSchool,
		-- absorbedAmount, absorbedCritical
		local start = argc - 8
		local absorberGUID, absorberName, absorberFlags, _, spellName, _, _, absorbedAmount, absorbedCritical = select(start, ...)
		if not absorberGUID or type(absorberFlags) ~= "number" or band(absorberFlags, groupMask) == 0 then return end
		lastAbsorbSourceByDest[destGUID] = { guid = absorberGUID, name = absorberName }
		if not absorbedAmount or absorbedAmount <= 0 then return end
		local p = acquirePlayer(cm.players, absorberGUID, absorberName)
		local o = acquirePlayer(cm.overallPlayers, absorberGUID, absorberName)
		p.healing = p.healing + absorbedAmount
		o.healing = o.healing + absorbedAmount
		return
	end
end

local function handleEvent(self, event)
	if event == "PLAYER_REGEN_DISABLED" or event == "ENCOUNTER_START" then
		cm.inCombat = true
		cm.fightStartTime = GetTime()
		releasePlayers(cm.players)
		wipe(lastAbsorbSourceByDest)
	elseif event == "PLAYER_REGEN_ENABLED" or event == "ENCOUNTER_END" then
		if not cm.inCombat then return end
		cm.inCombat = false
		cm.fightDuration = GetTime() - cm.fightStartTime
		cm.overallDuration = cm.overallDuration + cm.fightDuration
		local fight = { duration = cm.fightDuration, players = {} }
		for guid, data in pairs(cm.players) do
			fight.players[guid] = {
				guid = guid,
				name = data.name,
				damage = data.damage,
				healing = data.healing,
			}
		end
		addon.db["combatMeterHistory"] = addon.db["combatMeterHistory"] or {}
		local hist = addon.db["combatMeterHistory"]
		hist[#hist + 1] = fight
		local MAX = 30
		while #hist > MAX do
			table.remove(hist, 1)
		end
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		if not cm.inCombat then return end
		handleCLEU(CombatLogGetCurrentEventInfo())
	end
end

frame:SetScript("OnEvent", handleEvent)

function cm.functions.getOverallStats()
	local duration = cm.overallDuration
	if duration <= 0 then duration = 1 end
	local results = {}
	for guid, data in pairs(cm.overallPlayers) do
		results[guid] = {
			guid = guid,
			name = data.name,
			damage = data.damage,
			healing = data.healing,
			dps = data.damage / duration,
			hps = data.healing / duration,
		}
	end
	return results, duration
end

function cm.functions.toggle(enabled)
	if enabled then
		frame:RegisterEvent("PLAYER_REGEN_DISABLED")
		frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		frame:RegisterEvent("ENCOUNTER_START")
		frame:RegisterEvent("ENCOUNTER_END")
		frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		if cm.uiFrame then
			cm.uiFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
			cm.uiFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
			cm.uiFrame:RegisterEvent("ENCOUNTER_START")
			cm.uiFrame:RegisterEvent("ENCOUNTER_END")
			cm.uiFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
			cm.uiFrame:RegisterEvent("INSPECT_READY")
			cm.uiFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		end
	else
		frame:UnregisterAllEvents()
		cm.inCombat = false
		cm.fightDuration = 0
		cm.overallDuration = 0
		releasePlayers(cm.players)
		releasePlayers(cm.overallPlayers)
		if cm.uiFrame then
			cm.uiFrame:UnregisterAllEvents()
			cm.uiFrame:Hide()
		end
		if cm.functions and cm.functions.hideAllFrames then cm.functions.hideAllFrames() end
		if cm.ticker then
			cm.ticker:Cancel()
			cm.ticker = nil
		end
	end
end

cm.functions.toggle(addon.db["combatMeterEnabled"])

SLASH_EQOLCM1 = "/eqolcm"
SlashCmdList["EQOLCM"] = function(msg)
	if msg == "reset" then
		addon.db["combatMeterHistory"] = {}
		releasePlayers(cm.players)
		releasePlayers(cm.overallPlayers)
		cm.overallDuration = 0
		cm.fightDuration = 0
		print("EnhanceQoL Combat Meter data reset.")
	end
end
