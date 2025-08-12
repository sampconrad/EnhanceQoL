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
local CLEU = CombatLogGetCurrentEventInfo
local GPIG = GetPlayerInfoByGUID

cm.inCombat = false
cm.fightStartTime = 0
cm.fightDuration = 0

cm.players = cm.players or {}
cm.overallPlayers = cm.overallPlayers or {}
cm.playerPool = cm.playerPool or {}
cm.overallDuration = cm.overallDuration or 0

cm.MAX_HISTORY = cm.MAX_HISTORY or 30
cm.historySelection = cm.historySelection or nil
cm.historyUnits = cm.historyUnits or {}

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
				local oname = select(6, GPIG(owner))
				if oname then ownerNameCache[owner] = oname end
			end
			return owner, (ownerNameCache[owner] or srcName)
		end
	end
	if srcGUID and not ownerNameCache[srcGUID] then
		local sname = select(6, GPIG(srcGUID))
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
		player.damage = 0
		player.healing = 0
		local _, class = GPIG(guid)
		player.class = class
		players[guid] = player
	end
	if name and player.name ~= name then player.name = name end
	return player
end

local function releasePlayers(players)
	local pool = cm.playerPool
	for guid in pairs(players) do
		local player = players[guid]
		player.damage = 0
		player.healing = 0
		player.name = nil
		player.class = nil
		player.guid = nil
		pool[#pool + 1] = player
		players[guid] = nil
	end
end

local function fullRebuildPetOwners()
	wipe(petOwner)
	local activeGUIDs = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local owner = UnitGUID("raid" .. i)
			local pguid = UnitGUID("raid" .. i .. "pet")
			if owner then activeGUIDs[owner] = true end
			if owner and pguid then
				petOwner[pguid] = owner
				activeGUIDs[pguid] = true
			end
		end
	else
		for i = 1, GetNumGroupMembers() do
			local owner = UnitGUID("party" .. i)
			local pguid = UnitGUID("party" .. i .. "pet")
			if owner then activeGUIDs[owner] = true end
			if owner and pguid then
				petOwner[pguid] = owner
				activeGUIDs[pguid] = true
			end
		end
		local me = UnitGUID("player")
		local mypet = UnitGUID("pet")
		if me then activeGUIDs[me] = true end
		if me and mypet then
			petOwner[mypet] = me
			activeGUIDs[mypet] = true
		end
	end
	for guid in pairs(ownerNameCache) do
		if not activeGUIDs[guid] then ownerNameCache[guid] = nil end
	end
end

local function updatePetOwner(unit)
	if not unit then return end
	local owner = UnitGUID(unit)
	if not owner then return end
	for pguid, oguid in pairs(petOwner) do
		if oguid == owner then petOwner[pguid] = nil end
	end
	local pguid = UnitGUID(unit .. "pet")
	if pguid then petOwner[pguid] = owner end
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
}

local function handleEvent(self, event, unit)
	if event == "PLAYER_REGEN_DISABLED" or event == "ENCOUNTER_START" then
		cm.inCombat = true
		cm.fightStartTime = GetTime()
		cm.historySelection = nil
		cm.historyUnits = nil
		releasePlayers(cm.players)
		fullRebuildPetOwners()
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
				class = data.class,
				damage = data.damage,
				healing = data.healing,
			}
		end
		addon.db["combatMeterHistory"] = addon.db["combatMeterHistory"] or {}
		local hist = addon.db["combatMeterHistory"]
		-- hist[#hist + 1] = fight is required to keep trimming O(1) for inserts
		hist[#hist + 1] = fight
		if #hist > cm.MAX_HISTORY then table.remove(hist, 1) end
	elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
		fullRebuildPetOwners()
	elseif event == "UNIT_PET" then
		updatePetOwner(unit)
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		if not cm.inCombat then return end

		local _, sub, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23 = CLEU()
		if sub == "ENVIRONMENTAL_DAMAGE" then return end

		-- Maintain pet/guardian owner mapping via CLEU
		if sub == "SPELL_SUMMON" or sub == "SPELL_CREATE" then
			if destGUID and sourceGUID then petOwner[destGUID] = sourceGUID end
			return
		elseif sub == "UNIT_DIED" or sub == "UNIT_DESTROYED" then
			if destGUID then petOwner[destGUID] = nil end
			return
		elseif not (dmgIdx[sub] or sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" or sub == "SPELL_ABSORBED") then
			-- Note: We intentionally ignore *_MISSED ABSORB to avoid double-counting with SPELL_ABSORBED (matches Details behavior)
			return
		end

		local idx = dmgIdx[sub]
		if idx then
			if not sourceGUID or band(sourceFlags or 0, groupMask) == 0 then return end
			local amount = (idx == 1 and a12) or a15 or 0
			if amount <= 0 then return end
			local ownerGUID, ownerName = resolveOwner(sourceGUID, sourceName, sourceFlags)
			local player = acquirePlayer(cm.players, ownerGUID, ownerName)
			local overall = acquirePlayer(cm.overallPlayers, ownerGUID, ownerName)
			player.damage = player.damage + amount
			overall.damage = overall.damage + amount
			return
		end

		if sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" then
			if not sourceGUID or band(sourceFlags or 0, groupMask) == 0 then return end
			local amount = (a15 or 0) - (a16 or 0)
			if amount <= 0 then return end
			local ownerGUID, ownerName = resolveOwner(sourceGUID, sourceName, sourceFlags)
			local player = acquirePlayer(cm.players, ownerGUID, ownerName)
			local overall = acquirePlayer(cm.overallPlayers, ownerGUID, ownerName)
			player.healing = player.healing + amount
			overall.healing = overall.healing + amount
			return
		end

		-- We count absorbs exclusively via SPELL_ABSORBED. Some clients also emit *_MISSED with ABSORB for the same event; counting both leads to double credits.
		if sub == "SPELL_ABSORBED" then
			-- Heuristics: swing variant has 8 tail fields (a23 is number); spell variant has 9 (a23 is boolean, amount in a22)
			local absorberGUID, absorberName, absorberFlags, absorbedAmount
			if type(a23) == "boolean" then
				-- Spell-Variante mit Crit-Boolean (23 Rückgabewerte)
				absorberGUID, absorberName, absorberFlags, absorbedAmount = a15, a16, a17, a22
			elseif a22 ~= nil then
				-- Spell-Variante ohne Crit (22 Rückgabewerte)
				absorberGUID, absorberName, absorberFlags, absorbedAmount = a15, a16, a17, a22
			else
				-- Swing-Variante (19/20 Rückgabewerte)
				absorberGUID, absorberName, absorberFlags, absorbedAmount = a12, a13, a14, a19
			end
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

local function loadHistory(index)
	local hist = addon.db["combatMeterHistory"]
	if not hist or not hist[index] then return end
	local fight = hist[index]
	cm.historySelection = index
	cm.historyUnits = {}
	releasePlayers(cm.players)
	cm.fightDuration = fight.duration or 0
	for guid, p in pairs(fight.players) do
		local player = acquirePlayer(cm.players, guid, p.name)
		player.damage = p.damage or 0
		player.healing = p.healing or 0
		player.class = p.class
		cm.historyUnits[guid] = p.name
	end
	if addon.CombatMeter.functions.UpdateBars then addon.CombatMeter.functions.UpdateBars() end
end
cm.functions.loadHistory = loadHistory

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
