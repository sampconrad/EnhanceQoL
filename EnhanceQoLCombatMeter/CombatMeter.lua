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
		table.insert(addon.db["combatMeterHistory"], 1, fight)
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		if not addon.CombatMeter.inCombat then return end
		local _, subevent, _, sourceGUID, sourceName, sourceFlags, _, _, _, _, _, arg12, _, _, arg15 = CombatLogGetCurrentEventInfo()
		if not sourceGUID or bit_band(sourceFlags, groupMask) == 0 then return end
		local player = acquirePlayer(addon.CombatMeter.players, sourceGUID, sourceName)
		local overall = acquirePlayer(addon.CombatMeter.overallPlayers, sourceGUID, sourceName)

		local amount
		if subevent == "SWING_DAMAGE" then
			amount = arg12
			player.damage = player.damage + amount
			overall.damage = overall.damage + amount
		elseif subevent:find("_DAMAGE") then
			amount = arg15
			player.damage = player.damage + amount
			overall.damage = overall.damage + amount
		elseif subevent:find("_HEAL") then
			amount = arg15
			player.healing = player.healing + amount
			overall.healing = overall.healing + amount
		end
	end
end

frame:SetScript("OnEvent", handleEvent)

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
