local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.CombatMeter.inCombat = false
addon.CombatMeter.fightStartTime = 0
addon.CombatMeter.fightDuration = 0

addon.CombatMeter.players = addon.CombatMeter.players or {}
addon.CombatMeter.overallPlayers = addon.CombatMeter.overallPlayers or {}
addon.CombatMeter.playerPool = addon.CombatMeter.playerPool or {}
addon.CombatMeter.overallDuration = addon.CombatMeter.overallDuration or 0

local bit_band = bit.band
local bit_bor = bit.bor
local groupMask = bit_bor(COMBATLOG_OBJECT_AFFILIATION_MINE, COMBATLOG_OBJECT_AFFILIATION_PARTY, COMBATLOG_OBJECT_AFFILIATION_RAID)

local function acquirePlayer(tbl, guid, name)
	local players = tbl
	local player = players[guid]
	if not player then
		local pool = addon.CombatMeter.playerPool
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
	local pool = addon.CombatMeter.playerPool
	for guid, player in pairs(players) do
		wipe(player)
		table.insert(pool, player)
		players[guid] = nil
	end
end

local frame = CreateFrame("Frame")
addon.CombatMeter.frame = frame

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

local function handleEvent(self, event, ...)
	if event == "PLAYER_REGEN_DISABLED" or event == "ENCOUNTER_START" then
		addon.CombatMeter.inCombat = true
		addon.CombatMeter.fightStartTime = GetTime()
		releasePlayers(addon.CombatMeter.players)
	elseif event == "PLAYER_REGEN_ENABLED" or event == "ENCOUNTER_END" then
		addon.CombatMeter.inCombat = false
		addon.CombatMeter.fightDuration = GetTime() - addon.CombatMeter.fightStartTime
		addon.CombatMeter.overallDuration = addon.CombatMeter.overallDuration + addon.CombatMeter.fightDuration
		local fight = { duration = addon.CombatMeter.fightDuration, players = {} }
		for guid, data in pairs(addon.CombatMeter.players) do
			fight.players[guid] = {
				guid = guid,
				name = data.name,
				damage = data.damage,
				healing = data.healing,
			}
		end
		addon.db["combatMeterHistory"] = addon.db["combatMeterHistory"] or {}
		table.insert(addon.db["combatMeterHistory"], 1, fight)
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		if not addon.CombatMeter.inCombat then return end
		local a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25 = CombatLogGetCurrentEventInfo()
		local subevent = a2
		local sourceGUID = a4
		local sourceName = a5
		local sourceFlags = a6
		if not dmgIdx[subevent] and not healIdx[subevent] and not subevent == "SPELL_ABSORBED" then return end
		if not sourceGUID or bit_band(sourceFlags or 0, groupMask) == 0 then return end

		local idx = dmgIdx[subevent]
		if idx then
			local amount = select(idx, a12, a13, a14, a15, a16, a17, a18, a19, a20)
			if amount <= 0 then return end
			local player = acquirePlayer(addon.CombatMeter.players, sourceGUID, sourceName)
			local overall = acquirePlayer(addon.CombatMeter.overallPlayers, sourceGUID, sourceName)
			player.damage = player.damage + amount
			overall.damage = overall.damage + amount
			return
		end

		local hidx = healIdx[subevent]
		if hidx then
			local amount = select(hidx[1], a12, a13, a14, a15, a16, a17, a18, a19, a20) - select(hidx[2], a12, a13, a14, a15, a16, a17, a18, a19, a20)
			if amount <= 0 then return end
			local player = acquirePlayer(addon.CombatMeter.players, sourceGUID, sourceName)
			local overall = acquirePlayer(addon.CombatMeter.overallPlayers, sourceGUID, sourceName)
			player.healing = player.healing + amount
			overall.healing = overall.healing + amount
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
			if absorbedAmount > 0 and absorberGUID and bit_band(absorberFlags or 0, groupMask) ~= 0 then
				local p = acquirePlayer(addon.CombatMeter.players, absorberGUID, absorberName)
				local o = acquirePlayer(addon.CombatMeter.overallPlayers, absorberGUID, absorberName)
				p.healing = p.healing + absorbedAmount
				o.healing = o.healing + absorbedAmount
			end
		end
	end
end

frame:SetScript("OnEvent", handleEvent)

function addon.CombatMeter.functions.getOverallStats()
	local duration = addon.CombatMeter.overallDuration
	if duration <= 0 then duration = 1 end
	local results = {}
	for guid, data in pairs(addon.CombatMeter.overallPlayers) do
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

function addon.CombatMeter.functions.toggle(enabled)
	if enabled then
		frame:RegisterEvent("PLAYER_REGEN_DISABLED")
		frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		frame:RegisterEvent("ENCOUNTER_START")
		frame:RegisterEvent("ENCOUNTER_END")
		frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		if addon.CombatMeter.uiFrame then
			addon.CombatMeter.uiFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
			addon.CombatMeter.uiFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
			addon.CombatMeter.uiFrame:RegisterEvent("ENCOUNTER_START")
			addon.CombatMeter.uiFrame:RegisterEvent("ENCOUNTER_END")
			addon.CombatMeter.uiFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
			addon.CombatMeter.uiFrame:RegisterEvent("INSPECT_READY")
			addon.CombatMeter.uiFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		end
	else
		frame:UnregisterAllEvents()
		addon.CombatMeter.inCombat = false
		addon.CombatMeter.fightDuration = 0
		addon.CombatMeter.overallDuration = 0
		releasePlayers(addon.CombatMeter.players)
		releasePlayers(addon.CombatMeter.overallPlayers)
		if addon.CombatMeter.uiFrame then
			addon.CombatMeter.uiFrame:UnregisterAllEvents()
			addon.CombatMeter.uiFrame:Hide()
		end
		if addon.CombatMeter.functions and addon.CombatMeter.functions.hideAllFrames then addon.CombatMeter.functions.hideAllFrames() end
		if addon.CombatMeter.ticker then
			addon.CombatMeter.ticker:Cancel()
			addon.CombatMeter.ticker = nil
		end
	end
end

addon.CombatMeter.functions.toggle(addon.db["combatMeterEnabled"])

SLASH_EQOLCM1 = "/eqolcm"
SlashCmdList["EQOLCM"] = function(msg)
	if msg == "reset" then
		addon.db["combatMeterHistory"] = {}
		releasePlayers(addon.CombatMeter.players)
		releasePlayers(addon.CombatMeter.overallPlayers)
		addon.CombatMeter.overallDuration = 0
		addon.CombatMeter.fightDuration = 0
		print("EnhanceQoL Combat Meter data reset.")
	end
end
