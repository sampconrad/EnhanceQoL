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

local petOwner = cm.petOwner or {}
cm.petOwner = petOwner
local ownerNameCache = cm.ownerNameCache or {}
cm.ownerNameCache = ownerNameCache

local groupMask = bor(COMBATLOG_OBJECT_AFFILIATION_MINE, COMBATLOG_OBJECT_AFFILIATION_PARTY, COMBATLOG_OBJECT_AFFILIATION_RAID)

local PETMASK = bor(COMBATLOG_OBJECT_TYPE_PET or 0, COMBATLOG_OBJECT_TYPE_GUARDIAN or 0, COMBATLOG_OBJECT_TYPE_TOTEM or 0, COMBATLOG_OBJECT_TYPE_VEHICLE or 0)

local function resolveOwner(srcGUID, srcName, srcFlags)
	if band(srcFlags or 0, PETMASK) ~= 0 and srcGUID then
		local owner = petOwner[srcGUID]
		if owner then
			if not ownerNameCache[owner] then
				local oname = GetPlayerInfoByGUID(owner)
				if oname then ownerNameCache[owner] = oname end
			end
			return owner, (ownerNameCache[owner] or srcName)
		end
	end
	if srcGUID and not ownerNameCache[srcGUID] then
		local sname = GetPlayerInfoByGUID(srcGUID)
		if sname then ownerNameCache[srcGUID] = sname end
	end
	return srcGUID, (ownerNameCache[srcGUID] or srcName)
end

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

local function rebuildPetOwnerFromRoster()
	wipe(petOwner)
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local owner = UnitGUID("raid" .. i)
			local pguid = UnitGUID("raid" .. i .. "pet")
			if owner and pguid then petOwner[pguid] = owner end
		end
	else
		for i = 1, GetNumGroupMembers() do
			local owner = UnitGUID("party" .. i)
			local pguid = UnitGUID("party" .. i .. "pet")
			if owner and pguid then petOwner[pguid] = owner end
		end
		local me = UnitGUID("player")
		local mypet = UnitGUID("pet")
		if me and mypet then petOwner[mypet] = me end
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

local function handleEvent(self, event)
	if event == "PLAYER_REGEN_DISABLED" or event == "ENCOUNTER_START" then
		cm.inCombat = true
		cm.fightStartTime = GetTime()
		releasePlayers(cm.players)
		rebuildPetOwnerFromRoster()
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
		if #hist > MAX then table.remove(hist, 1) end
	elseif event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" or event == "PLAYER_ENTERING_WORLD" then
		rebuildPetOwnerFromRoster()
        elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
                if not cm.inCombat then return end
                local info = { CombatLogGetCurrentEventInfo() }
                local subevent = info[2]
                local sourceGUID, sourceName, sourceFlags = info[4], info[5], info[6]
                local destGUID = info[8]

                -- Maintain pet/guardian owner mapping via CLEU
                if subevent == "SPELL_SUMMON" or subevent == "SPELL_CREATE" then
                        if destGUID and sourceGUID then petOwner[destGUID] = sourceGUID end
                        return
                elseif subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
                        if destGUID then petOwner[destGUID] = nil end
                        return
                end

                -- Note: We intentionally ignore *_MISSED ABSORB to avoid double-counting with SPELL_ABSORBED (matches Details behavior)
                if not (dmgIdx[subevent] or healIdx[subevent] or subevent == "SPELL_ABSORBED") then return end

                local idx = dmgIdx[subevent]
                if idx then
                        if not sourceGUID or band(sourceFlags or 0, groupMask) == 0 then return end
                        local amount = info[11 + idx]
                        if not amount or amount <= 0 then return end
                        local ownerGUID, ownerName = resolveOwner(sourceGUID, sourceName, sourceFlags)
                        local player = acquirePlayer(cm.players, ownerGUID, ownerName)
                        local overall = acquirePlayer(cm.overallPlayers, ownerGUID, ownerName)
                        player.damage = player.damage + amount
                        overall.damage = overall.damage + amount
                        return
                end

                local hidx = healIdx[subevent]
                if hidx then
                        if not sourceGUID or band(sourceFlags or 0, groupMask) == 0 then return end
                        local amount = (info[11 + hidx[1]] or 0) - (info[11 + hidx[2]] or 0)
                        if not amount or amount <= 0 then return end
                        local ownerGUID, ownerName = resolveOwner(sourceGUID, sourceName, sourceFlags)
                        local player = acquirePlayer(cm.players, ownerGUID, ownerName)
                        local overall = acquirePlayer(cm.overallPlayers, ownerGUID, ownerName)
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
                        local varargCount = #info - 11
                        local start = varargCount - 8
                        local base = 11 + start
                        local absorberGUID = info[base]
                        local absorberName = info[base + 1]
                        local absorberFlags = info[base + 2]
                        local spellName = info[base + 4]
                        local absorbedAmount = info[base + 7]
                        local absorbedCritical = info[base + 8]
                        if not absorberGUID or type(absorberFlags) ~= "number" or band(absorberFlags, groupMask) == 0 then return end
                        if not absorbedAmount or absorbedAmount <= 0 then return end
                        local ownerGUID, ownerName = resolveOwner(absorberGUID, absorberName, absorberFlags)
                        local p = acquirePlayer(cm.players, ownerGUID, ownerName)
                        local o = acquirePlayer(cm.overallPlayers, ownerGUID, ownerName)
                        p.healing = p.healing + absorbedAmount
                        o.healing = o.healing + absorbedAmount
                        return
                end
        end
end

frame:SetScript("OnEvent", handleEvent)

function cm.functions.getOverallStats()
	local duration = cm.overallDuration
	if duration <= 0 then duration = 1 end
	return cm.overallPlayers, duration
end

function cm.functions.toggle(enabled)
	if enabled then
		frame:RegisterEvent("PLAYER_REGEN_DISABLED")
		frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		frame:RegisterEvent("ENCOUNTER_START")
		frame:RegisterEvent("ENCOUNTER_END")
		frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		frame:RegisterEvent("GROUP_ROSTER_UPDATE")
		frame:RegisterEvent("UNIT_PET")
		frame:RegisterEvent("PLAYER_ENTERING_WORLD")
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
