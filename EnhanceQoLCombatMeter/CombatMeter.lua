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

local missAbsorbIdx = {
	SWING_MISSED = { 1, 3 },
	RANGE_MISSED = { 4, 6 },
	SPELL_MISSED = { 4, 6 },
	SPELL_PERIODIC_MISSED = { 4, 5 },
	DAMAGE_SHIELD_MISSED = { 4, 5 },
	DAMAGE_SPLIT_MISSED = { 4, 5 },
}

local function handleEvent(self, event, ...)
	if event == "PLAYER_REGEN_DISABLED" or event == "ENCOUNTER_START" then
		cm.inCombat = true
		cm.fightStartTime = GetTime()
		releasePlayers(cm.players)
		wipe(lastAbsorbSourceByDest)
	elseif event == "PLAYER_REGEN_ENABLED" or event == "ENCOUNTER_END" then
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
		local a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25 = CombatLogGetCurrentEventInfo()
		local subevent = a2
		local sourceGUID = a4
		local sourceName = a5
		local sourceFlags = a6
		local destGUID = a8
		local missIdx = missAbsorbIdx[subevent]
		if not (dmgIdx[subevent] or healIdx[subevent] or missIdx or subevent == "SPELL_ABSORBED") then return end
		if not missIdx and (not sourceGUID or band(sourceFlags or 0, groupMask) == 0) then return end

		local idx = dmgIdx[subevent]
		if idx then
			local amount = select(idx, a12, a13, a14, a15, a16, a17, a18, a19, a20)
			if amount <= 0 then return end
			local player = acquirePlayer(cm.players, sourceGUID, sourceName)
			local overall = acquirePlayer(cm.overallPlayers, sourceGUID, sourceName)
			player.damage = player.damage + amount
			overall.damage = overall.damage + amount
			return
		end

		local hidx = healIdx[subevent]
		if hidx then
			local amount = select(hidx[1], a12, a13, a14, a15, a16, a17, a18, a19, a20) - select(hidx[2], a12, a13, a14, a15, a16, a17, a18, a19, a20)
			if amount <= 0 then return end
			local player = acquirePlayer(cm.players, sourceGUID, sourceName)
			local overall = acquirePlayer(cm.overallPlayers, sourceGUID, sourceName)
			player.healing = player.healing + amount
			overall.healing = overall.healing + amount
			return
		end

		if missIdx then
			local missType = select(missIdx[1], a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25)
			if missType ~= "ABSORB" then return end
			local amount = select(missIdx[2], a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25)
			if not amount or amount <= 0 then return end
			local absorberGUID = lastAbsorbSourceByDest[destGUID]
			if not absorberGUID then return end
			local p = acquirePlayer(cm.players, absorberGUID)
			local o = acquirePlayer(cm.overallPlayers, absorberGUID)
			p.healing = p.healing + amount
			o.healing = o.healing + amount
			return
		end

		if subevent == "SPELL_ABSORBED" then
			-- Count absorbed damage as effective healing for the absorber (shield caster).
			-- SPELL_ABSORBED has variable arg layouts; the last 8 fields are stable:
			-- absorberGUID, absorberName, absorberFlags, absorberRaidFlags,
			-- absorbingSpellID, absorbingSpellName, absorbingSpellSchool, absorbedAmount
			local a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25 = CombatLogGetCurrentEventInfo()
			local n = select("#", a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25)
			local absorberGUID = select(n - 7, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25)
			local absorberName = select(n - 6, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25)
			local absorberFlags = select(n - 5, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25)
			local absorbedAmount = select(n, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25) or 0
			if absorberGUID and band(absorberFlags or 0, groupMask) ~= 0 then
				lastAbsorbSourceByDest[destGUID] = absorberGUID
				if absorbedAmount > 0 then
					local p = acquirePlayer(cm.players, absorberGUID, absorberName)
					local o = acquirePlayer(cm.overallPlayers, absorberGUID, absorberName)
					p.healing = p.healing + absorbedAmount
					o.healing = o.healing + absorbedAmount
				end
			end
		end
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
