-- luacheck: globals COMBATLOG_OBJECT_TYPE_TOTEM COMBATLOG_OBJECT_TYPE_VEHICLE
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
cm.prePullBuffer = cm.prePullBuffer or {}
cm.prePullHead = cm.prePullHead or 1
cm.prePullTail = cm.prePullTail or 0

cm.MAX_HISTORY = cm.MAX_HISTORY or 30
cm.historySelection = cm.historySelection or nil
cm.historyUnits = cm.historyUnits or {}

local petOwner = cm.petOwner or {}
cm.petOwner = petOwner
local ownerPets = cm.ownerPets or {}
cm.ownerPets = ownerPets
local ownerMainPet = cm.ownerMainPet or {}
cm.ownerMainPet = ownerMainPet
local ownerNameCache = cm.ownerNameCache or {}
cm.ownerNameCache = ownerNameCache
local unitAffiliation = cm.unitAffiliation or {}
cm.unitAffiliation = unitAffiliation

local groupMask = bor(COMBATLOG_OBJECT_AFFILIATION_MINE, COMBATLOG_OBJECT_AFFILIATION_PARTY, COMBATLOG_OBJECT_AFFILIATION_RAID)

local PETMASK = bor(COMBATLOG_OBJECT_TYPE_PET or 0, COMBATLOG_OBJECT_TYPE_GUARDIAN or 0, COMBATLOG_OBJECT_TYPE_TOTEM or 0, COMBATLOG_OBJECT_TYPE_VEHICLE or 0)

local function resolveOwner(srcGUID, srcName, srcFlags)
	if srcGUID and srcFlags then unitAffiliation[srcGUID] = srcFlags end
	if srcGUID then
		local owner = petOwner[srcGUID]
		if owner then
			if not ownerNameCache[owner] then
				local oname = select(6, GPIG(owner))
				if oname then ownerNameCache[owner] = oname end
			end
			return owner, (ownerNameCache[owner] or srcName), unitAffiliation[owner]
		end
	end
	if band(srcFlags or 0, PETMASK) ~= 0 and srcGUID then
		local owner = petOwner[srcGUID]
		if owner then
			if not ownerNameCache[owner] then
				local oname = select(6, GPIG(owner))
				if oname then ownerNameCache[owner] = oname end
			end
			return owner, (ownerNameCache[owner] or srcName), unitAffiliation[owner]
		end
	end
	if srcGUID and not ownerNameCache[srcGUID] then
		local sname = select(6, GPIG(srcGUID))
		if sname then ownerNameCache[srcGUID] = sname end
	end
	return srcGUID, (ownerNameCache[srcGUID] or srcName), unitAffiliation[srcGUID]
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
		player.damageTaken = 0
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
		wipe(player)
		pool[#pool + 1] = player
		players[guid] = nil
	end
end

local function resetMeter()
	releasePlayers(cm.players)
	releasePlayers(cm.overallPlayers)
	cm.overallDuration = 0
	cm.fightDuration = 0
	cm.inCombat = false
	cm.fightStartTime = 0
	cm.prePullHead = 1
	cm.prePullTail = 0
	wipe(cm.prePullBuffer)
end
cm.resetMeter = resetMeter

local function fullRebuildPetOwners()
	local activeGUIDs = {}
	local groupGUIDs = {}

	local function handleUnit(unit)
		local owner = UnitGUID(unit)
		if not owner then return end
		groupGUIDs[owner] = true
		activeGUIDs[owner] = true
		local newMain = UnitGUID(unit .. "pet")
		local oldMain = ownerMainPet[owner]
		if oldMain and oldMain ~= newMain then
			petOwner[oldMain] = nil
			local pets = ownerPets[owner]
			if pets then
				pets[oldMain] = nil
				if not next(pets) then ownerPets[owner] = nil end
			end
		end
		if newMain then
			petOwner[newMain] = owner
			ownerPets[owner] = ownerPets[owner] or {}
			ownerPets[owner][newMain] = true
			ownerMainPet[owner] = newMain
			activeGUIDs[newMain] = true
		else
			ownerMainPet[owner] = nil
		end
	end

	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			handleUnit("raid" .. i)
		end
	else
		for i = 1, GetNumGroupMembers() do
			handleUnit("party" .. i)
		end
	end

	handleUnit("player")

	local toDrop = {}
	for owner, pets in pairs(ownerPets) do
		if not groupGUIDs[owner] then
			toDrop[#toDrop + 1] = owner
		else
			for pguid in pairs(pets) do
				activeGUIDs[pguid] = true
			end
		end
	end
	for _, owner in ipairs(toDrop) do
		for pguid in pairs(ownerPets[owner]) do
			petOwner[pguid] = nil
		end
		ownerPets[owner] = nil
		ownerMainPet[owner] = nil
	end

	cm.groupGUIDs = groupGUIDs
	for guid in pairs(ownerNameCache) do
		if not activeGUIDs[guid] then ownerNameCache[guid] = nil end
	end
	for guid in pairs(unitAffiliation) do
		if not activeGUIDs[guid] then unitAffiliation[guid] = nil end
	end
end

local function updatePetOwner(unit)
	if not unit then return end
	local owner = UnitGUID(unit)
	if not owner then return end
	local newMain = UnitGUID(unit .. "pet")
	local pets = ownerPets[owner]
	local oldMain = ownerMainPet[owner]
	if oldMain and oldMain ~= newMain then
		petOwner[oldMain] = nil
		if pets then
			pets[oldMain] = nil
			if not next(pets) then
				ownerPets[owner] = nil
				pets = nil
			end
		end
	end
	if newMain then
		petOwner[newMain] = owner
		pets = pets or {}
		pets[newMain] = true
		ownerPets[owner] = pets
		ownerMainPet[owner] = newMain
	else
		ownerMainPet[owner] = nil
		if pets and next(pets) then
			ownerPets[owner] = pets
		else
			ownerPets[owner] = nil
		end
	end
end

local function addPrePull(ownerGUID, ownerName, damage, healing)
	local buf = cm.prePullBuffer
	local now = GetTime()
	local tail = cm.prePullTail + 1
	buf[tail] = { t = now, guid = ownerGUID, name = ownerName, damage = damage or 0, healing = healing or 0 }
	cm.prePullTail = tail
	local cutoff = now - (addon.db["combatMeterPrePullWindow"] or 4)
	local head = cm.prePullHead
	while head <= tail do
		local e = buf[head]
		if not e or e.t >= cutoff then break end
		buf[head] = nil
		head = head + 1
	end
	if head > tail then
		head = 1
		tail = 0
	end
	cm.prePullHead = head
	cm.prePullTail = tail
end

local function mergePrePull()
	local buf = cm.prePullBuffer
	local head = cm.prePullHead
	local tail = cm.prePullTail
	if not buf or head > tail then return end
	local cutoff = GetTime() - (addon.db["combatMeterPrePullWindow"] or 4)
	for i = head, tail do
		local e = buf[i]
		if e and e.t >= cutoff then
			local ownerGUID, ownerName = resolveOwner(e.guid, e.name, unitAffiliation[e.guid])
			e.guid = ownerGUID
			e.name = ownerName
			local p = acquirePlayer(cm.players, ownerGUID, ownerName)
			p._first = p._first or e.t
			p._last = e.t
			local o = acquirePlayer(cm.overallPlayers, ownerGUID, ownerName)
			if e.damage and e.damage > 0 then
				p.damage = p.damage + e.damage
				o.damage = o.damage + e.damage
			end
			if e.healing and e.healing > 0 then
				p.healing = p.healing + e.healing
				o.healing = o.healing + e.healing
			end
		end
	end
	cm.prePullHead = 1
	cm.prePullTail = 0
	wipe(buf)
end

local frame = CreateFrame("Frame")
cm.frame = frame

local dmgIdx = {
	SWING_DAMAGE = 1,
	RANGE_DAMAGE = 4,
	SPELL_DAMAGE = 4,
	SPELL_PERIODIC_DAMAGE = 4,
	DAMAGE_SHIELD = 4,
}

local function handleEvent(self, event, unit)
	if event == "PLAYER_REGEN_DISABLED" or event == "ENCOUNTER_START" then
		if cm.inCombat then return end
		cm.inCombat = true
		cm.fightStartTime = GetTime()
		cm.historySelection = nil
		cm.historyUnits = nil
		releasePlayers(cm.players)
		fullRebuildPetOwners()
		if addon.db["combatMeterPrePullCapture"] then mergePrePull() end
	elseif event == "PLAYER_REGEN_ENABLED" or event == "ENCOUNTER_END" then
		if not cm.inCombat then return end
		cm.inCombat = false
		cm.fightDuration = GetTime() - cm.fightStartTime
		cm.overallDuration = cm.overallDuration + cm.fightDuration
		for guid, data in pairs(cm.players) do
			local o = acquirePlayer(cm.overallPlayers, guid, data.name)
			local start = cm.fightStartTime
			local finish = start + cm.fightDuration
			local first = data._first or start
			local last = data._last or start
			local active = math.max(0, math.min(last, finish) - math.max(first, start))
			o.time = (o.time or 0) + active
		end
		local fight = { duration = cm.fightDuration, players = {} }
		for guid, data in pairs(cm.players) do
			fight.players[guid] = {
				guid = guid,
				name = data.name,
				class = data.class,
				damage = data.damage,
				healing = data.healing,
				damageTaken = data.damageTaken,
			}
		end
		addon.db["combatMeterHistory"] = addon.db["combatMeterHistory"] or {}
		local hist = addon.db["combatMeterHistory"]
		-- hist[#hist + 1] = fight is required to keep trimming O(1) for inserts
		hist[#hist + 1] = fight
		if #hist > cm.MAX_HISTORY then table.remove(hist, 1) end
	elseif event == "CHALLENGE_MODE_START" then
		if addon.db["combatMeterResetOnChallengeStart"] then resetMeter() end
	elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
		fullRebuildPetOwners()
	elseif event == "UNIT_PET" then
		updatePetOwner(unit)
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		local inCombat = cm.inCombat
		local pre = addon.db["combatMeterPrePullCapture"]
		local _, sub, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23 = CLEU()
		if sub == "ENVIRONMENTAL_DAMAGE" then return end

		-- Maintain pet/guardian owner mapping via CLEU
		if sub == "SPELL_SUMMON" or sub == "SPELL_CREATE" then
			if destGUID and sourceGUID then
				petOwner[destGUID] = sourceGUID
				ownerPets[sourceGUID] = ownerPets[sourceGUID] or {}
				ownerPets[sourceGUID][destGUID] = true
			end
			return
		elseif sub == "UNIT_DIED" or sub == "UNIT_DESTROYED" then
			if destGUID then
				local owner = petOwner[destGUID]
				if owner then
					local pets = ownerPets[owner]
					if pets then
						pets[destGUID] = nil
						if not next(pets) then ownerPets[owner] = nil end
					end
					if ownerMainPet[owner] == destGUID then ownerMainPet[owner] = nil end
				end
				petOwner[destGUID] = nil
			end
			return
		elseif not (dmgIdx[sub] or sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" or sub == "SPELL_ABSORBED" or sub == "DAMAGE_SPLIT") then
			-- Note: We intentionally ignore *_MISSED ABSORB to avoid double-counting with SPELL_ABSORBED (matches Details behavior)
			return
		end
		if not inCombat and not pre then return end

		local idx = dmgIdx[sub]
		if idx then
			if not sourceGUID then return end
			local ownerGUID, ownerName, ownerFlags = resolveOwner(sourceGUID, sourceName, sourceFlags)
			if not ownerFlags and cm.groupGUIDs and cm.groupGUIDs[ownerGUID] then ownerFlags = COMBATLOG_OBJECT_AFFILIATION_RAID end
			if band(ownerFlags or 0, groupMask) == 0 then return end
			local amount = (idx == 1 and a12) or a15 or 0
			if amount <= 0 then return end
			if inCombat then
				local player = acquirePlayer(cm.players, ownerGUID, ownerName)
				local overall = acquirePlayer(cm.overallPlayers, ownerGUID, ownerName)
				local now = GetTime()
				player._first = player._first or now
				player._last = now
				player.damage = player.damage + amount
				overall.damage = overall.damage + amount
			else
				addPrePull(ownerGUID, ownerName, amount, 0)
			end
			return
		end

		if sub == "DAMAGE_SPLIT" then
			if not inCombat then return end
			if not sourceGUID then return end
			local ownerGUID, ownerName, ownerFlags = resolveOwner(sourceGUID, sourceName, sourceFlags)
			if not ownerFlags and cm.groupGUIDs and cm.groupGUIDs[ownerGUID] then ownerFlags = COMBATLOG_OBJECT_AFFILIATION_RAID end
			if band(ownerFlags or 0, groupMask) == 0 then return end
			local amount = a15 or 0
			if amount <= 0 then return end
			local player = acquirePlayer(cm.players, ownerGUID, ownerName)
			local overall = acquirePlayer(cm.overallPlayers, ownerGUID, ownerName)
			local now = GetTime()
			player._first = player._first or now
			player._last = now
			player.damageTaken = player.damageTaken + amount
			overall.damageTaken = overall.damageTaken + amount
			return
		end

		if sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" then
			if not sourceGUID then return end
			local ownerGUID, ownerName, ownerFlags = resolveOwner(sourceGUID, sourceName, sourceFlags)
			if not ownerFlags and cm.groupGUIDs and cm.groupGUIDs[ownerGUID] then ownerFlags = COMBATLOG_OBJECT_AFFILIATION_RAID end
			if band(ownerFlags or 0, groupMask) == 0 then return end
			local amount = (a15 or 0) - (a16 or 0)
			if amount <= 0 then return end
			if inCombat then
				local player = acquirePlayer(cm.players, ownerGUID, ownerName)
				local overall = acquirePlayer(cm.overallPlayers, ownerGUID, ownerName)
				local now = GetTime()
				player._first = player._first or now
				player._last = now
				player.healing = player.healing + amount
				overall.healing = overall.healing + amount
			else
				addPrePull(ownerGUID, ownerName, 0, amount)
			end
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
			if not absorberGUID or type(absorberFlags) ~= "number" then return end
			local ownerGUID, ownerName, ownerFlags = resolveOwner(absorberGUID, absorberName, absorberFlags)
			if not ownerFlags and cm.groupGUIDs and cm.groupGUIDs[ownerGUID] then ownerFlags = COMBATLOG_OBJECT_AFFILIATION_RAID end
			if band(ownerFlags or 0, groupMask) == 0 then return end
			if not absorbedAmount or absorbedAmount <= 0 then return end
			if inCombat then
				local p = acquirePlayer(cm.players, ownerGUID, ownerName)
				local o = acquirePlayer(cm.overallPlayers, ownerGUID, ownerName)
				local now = GetTime()
				p._first = p._first or now
				p._last = now
				p.healing = p.healing + absorbedAmount
				o.healing = o.healing + absorbedAmount
			else
				addPrePull(ownerGUID, ownerName, 0, absorbedAmount)
			end
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
		player.damageTaken = p.damageTaken or 0
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
		if addon.db["combatMeterResetOnChallengeStart"] then frame:RegisterEvent("CHALLENGE_MODE_START") end
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
		resetMeter()
		frame:UnregisterEvent("CHALLENGE_MODE_START")
		frame:UnregisterAllEvents()
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
		resetMeter()
	end
end
