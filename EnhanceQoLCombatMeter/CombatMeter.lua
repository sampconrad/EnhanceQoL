-- luacheck: globals COMBATLOG_OBJECT_TYPE_TOTEM COMBATLOG_OBJECT_TYPE_VEHICLE
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end
if addon.variables.isMidnight then return end

local cm = addon.CombatMeter
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_CombatMeter")
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local TEXTURE_PATH = "Interface\\AddOns\\EnhanceQoLCombatMeter\\Texture\\"
local wipe = wipe
local barTextureOrder = {}

-- TODO remove Combat Meter settings when WoW Midnight launches
if addon.SettingsLayout and addon.SettingsLayout.characterInspectCategory then
	local cCM = addon.SettingsLayout.characterInspectCategory
	local sectionCM = addon.functions.SettingsCreateExpandableSection(cCM, {
		name = L["Combat Meter"],
		expanded = true,
		colorizeTitle = false,
	})

	if L["combatMeterMidnightWarning"] then addon.functions.SettingsCreateText(cCM, L["combatMeterMidnightWarning"], { parentSection = sectionCM }) end

	local cmEnable = addon.functions.SettingsCreateCheckbox(cCM, {
		var = "combatMeterEnabled",
		text = L["Enabled"],
		func = function(v)
			addon.db["combatMeterEnabled"] = v
			if addon.CombatMeter and addon.CombatMeter.functions and addon.CombatMeter.functions.toggle then addon.CombatMeter.functions.toggle(v) end
		end,
		parentSection = sectionCM,
	})
	local function cmEnabled() return cmEnable and cmEnable.setting and cmEnable.setting:GetValue() == true end

	local function refreshBars()
		if addon.CombatMeter and addon.CombatMeter.functions and addon.CombatMeter.functions.UpdateBars then addon.CombatMeter.functions.UpdateBars() end
	end

	addon.functions.SettingsCreateCheckbox(cCM, {
		var = "combatMeterAlwaysShow",
		text = L["Always Show"],
		func = function(v)
			addon.db["combatMeterAlwaysShow"] = v
			refreshBars()
		end,
		parent = true,
		element = cmEnable.element,
		parentCheck = cmEnabled,
		parentSection = sectionCM,
	})

	addon.functions.SettingsCreateCheckbox(cCM, {
		var = "combatMeterResetOnChallengeStart",
		text = L["Reset on Challenge Start"],
		func = function(v)
			addon.db["combatMeterResetOnChallengeStart"] = v
			if addon.db["combatMeterEnabled"] and addon.CombatMeter and addon.CombatMeter.frame then
				if v then
					addon.CombatMeter.frame:RegisterEvent("CHALLENGE_MODE_START")
				else
					addon.CombatMeter.frame:UnregisterEvent("CHALLENGE_MODE_START")
				end
			end
		end,
		parent = true,
		element = cmEnable.element,
		parentCheck = cmEnabled,
		parentSection = sectionCM,
	})

	addon.functions.SettingsCreateSlider(cCM, {
		var = "combatMeterUpdateRate",
		text = L["Update Rate"],
		min = 0.05,
		max = 1,
		step = 0.05,
		default = addon.db["combatMeterUpdateRate"] or 0.2,
		get = function() return addon.db["combatMeterUpdateRate"] or 0.2 end,
		set = function(val)
			addon.db["combatMeterUpdateRate"] = val
			if addon.CombatMeter and addon.CombatMeter.functions and addon.CombatMeter.functions.setUpdateRate then addon.CombatMeter.functions.setUpdateRate(val) end
		end,
		parent = true,
		element = cmEnable.element,
		parentCheck = cmEnabled,
		parentSection = sectionCM,
	})

	addon.functions.SettingsCreateSlider(cCM, {
		var = "combatMeterFontSize",
		text = FONT_SIZE,
		min = 8,
		max = 32,
		step = 1,
		default = addon.db["combatMeterFontSize"] or 12,
		get = function() return addon.db["combatMeterFontSize"] or 12 end,
		set = function(val)
			addon.db["combatMeterFontSize"] = val
			if addon.CombatMeter and addon.CombatMeter.functions and addon.CombatMeter.functions.setFontSize then addon.CombatMeter.functions.setFontSize(val) end
		end,
		parent = true,
		element = cmEnable.element,
		parentCheck = cmEnabled,
		parentSection = sectionCM,
	})

	addon.functions.SettingsCreateSlider(cCM, {
		var = "combatMeterNameLength",
		text = L["Name Length"],
		min = 1,
		max = 20,
		step = 1,
		default = addon.db["combatMeterNameLength"] or 12,
		get = function() return addon.db["combatMeterNameLength"] or 12 end,
		set = function(val)
			addon.db["combatMeterNameLength"] = val
			refreshBars()
		end,
		parent = true,
		element = cmEnable.element,
		parentCheck = cmEnabled,
		parentSection = sectionCM,
	})

	local prePull = addon.functions.SettingsCreateCheckbox(cCM, {
		var = "combatMeterPrePullCapture",
		text = L["Pre-Pull Capture"],
		func = function(v) addon.db["combatMeterPrePullCapture"] = v end,
		parent = true,
		element = cmEnable.element,
		parentCheck = cmEnabled,
		parentSection = sectionCM,
	})
	local function prePullEnabled() return prePull and prePull.setting and prePull.setting:GetValue() == true and cmEnabled() end

	addon.functions.SettingsCreateSlider(cCM, {
		var = "combatMeterPrePullWindow",
		text = L["Window (sec)"],
		min = 1,
		max = 10,
		step = 1,
		default = addon.db["combatMeterPrePullWindow"] or 4,
		get = function() return addon.db["combatMeterPrePullWindow"] or 4 end,
		set = function(val) addon.db["combatMeterPrePullWindow"] = val end,
		parent = true,
		element = prePull.element,
		parentCheck = prePullEnabled,
		parentSection = sectionCM,
	})

	local function buildBarTextureOptions()
		local all = {
			["Interface\\Buttons\\WHITE8x8"] = L["Flat (white, tintable)"],
			["Interface\\Tooltips\\UI-Tooltip-Background"] = L["Dark Flat (Tooltip bg)"],
			[TEXTURE_PATH .. "eqol_base_flat_8x8.tga"] = L["EQoL: Flat (AddOn)"],
		}
		if LSM and LSM.HashTable then
			for name, path in pairs(LSM:HashTable("statusbar") or {}) do
				if type(path) == "string" and path ~= "" then all[path] = tostring(name) end
			end
		end
		local sorted, order = addon.functions.prepareListForDropdown(all)
		wipe(barTextureOrder)
		for i, key in ipairs(order) do
			barTextureOrder[i] = key
		end
		return sorted
	end

	addon.functions.SettingsCreateDropdown(cCM, {
		var = "combatMeterBarTexture",
		text = L["Bar Texture"],
		default = TEXTURE_PATH .. "eqol_base_flat_8x8.tga",
		listFunc = buildBarTextureOptions,
		order = barTextureOrder,
		get = function()
			local list = buildBarTextureOptions()
			local cur = addon.db["combatMeterBarTexture"] or (TEXTURE_PATH .. "eqol_base_flat_8x8.tga")
			if not list[cur] then cur = TEXTURE_PATH .. "eqol_base_flat_8x8.tga" end
			return cur
		end,
		set = function(key)
			addon.db["combatMeterBarTexture"] = key
			if addon.CombatMeter.functions.applyBarTextures then addon.CombatMeter.functions.applyBarTextures() end
		end,
		parent = true,
		element = cmEnable.element,
		parentCheck = cmEnabled,
		parentSection = sectionCM,
	})

	local overlayTextures = {
		[TEXTURE_PATH .. "eqol_overlay_gradient_512x64.tga"] = L["Gradient"],
		[TEXTURE_PATH .. "eqol_overlay_vidro_512x64.tga"] = L["Gloss/Vidro"],
		[TEXTURE_PATH .. "eqol_overlay_stripes_512x64.tga"] = L["Stripes"],
		[TEXTURE_PATH .. "eqol_overlay_noise_512x64.tga"] = L["Noise"],
	}
	local overlayOrder = {
		TEXTURE_PATH .. "eqol_overlay_gradient_512x64.tga",
		TEXTURE_PATH .. "eqol_overlay_vidro_512x64.tga",
		TEXTURE_PATH .. "eqol_overlay_stripes_512x64.tga",
		TEXTURE_PATH .. "eqol_overlay_noise_512x64.tga",
	}
	local defaultBlendByTexture = {
		[TEXTURE_PATH .. "eqol_overlay_gradient_512x64.tga"] = "ADD",
		[TEXTURE_PATH .. "eqol_overlay_vidro_512x64.tga"] = "ADD",
		[TEXTURE_PATH .. "eqol_overlay_stripes_512x64.tga"] = "MOD",
		[TEXTURE_PATH .. "eqol_overlay_noise_512x64.tga"] = "BLEND",
	}
	local blendOptions = {
		ADD = "ADD",
		MOD = "MOD",
		BLEND = "BLEND",
	}
	local blendOrder = { "ADD", "MOD", "BLEND" }

	local overlayEnable = addon.functions.SettingsCreateCheckbox(cCM, {
		var = "combatMeterUseOverlay",
		text = L["Use Overlay"],
		func = function(v)
			addon.db["combatMeterUseOverlay"] = v
			if addon.CombatMeter.functions.applyBarTextures then addon.CombatMeter.functions.applyBarTextures() end
		end,
		parent = true,
		element = cmEnable.element,
		parentCheck = cmEnabled,
		parentSection = sectionCM,
	})
	local function overlayEnabled() return overlayEnable and overlayEnable.setting and overlayEnable.setting:GetValue() == true and cmEnabled() end

	addon.functions.SettingsCreateDropdown(cCM, {
		var = "combatMeterOverlayTexture",
		text = L["Overlay Texture"],
		list = overlayTextures,
		default = TEXTURE_PATH .. "eqol_overlay_gradient_512x64.tga",
		get = function()
			local cur = addon.db["combatMeterOverlayTexture"] or (TEXTURE_PATH .. "eqol_overlay_gradient_512x64.tga")
			if not overlayTextures[cur] then cur = TEXTURE_PATH .. "eqol_overlay_gradient_512x64.tga" end
			return cur
		end,
		set = function(key)
			addon.db["combatMeterOverlayTexture"] = key
			addon.db["combatMeterOverlayBlend"] = defaultBlendByTexture[key] or addon.db["combatMeterOverlayBlend"]
			if addon.CombatMeter.functions.applyBarTextures then addon.CombatMeter.functions.applyBarTextures() end
		end,
		parent = true,
		element = overlayEnable.element,
		parentCheck = overlayEnabled,
		listOrder = overlayOrder,
		parentSection = sectionCM,
	})

	addon.functions.SettingsCreateDropdown(cCM, {
		var = "combatMeterOverlayBlend",
		text = L["Overlay Blend Mode"],
		list = blendOptions,
		default = "ADD",
		get = function() return addon.db["combatMeterOverlayBlend"] or "ADD" end,
		set = function(key)
			addon.db["combatMeterOverlayBlend"] = key
			if addon.CombatMeter.functions.applyBarTextures then addon.CombatMeter.functions.applyBarTextures() end
		end,
		parent = true,
		element = overlayEnable.element,
		parentCheck = overlayEnabled,
		listOrder = blendOrder,
		parentSection = sectionCM,
	})

	addon.functions.SettingsCreateSlider(cCM, {
		var = "combatMeterOverlayAlpha",
		text = L["Overlay Opacity"],
		min = 1,
		max = 100,
		step = 1,
		default = math.floor(((addon.db["combatMeterOverlayAlpha"] or 0.28) * 100) + 0.5),
		get = function() return math.floor(((addon.db["combatMeterOverlayAlpha"] or 0.28) * 100) + 0.5) end,
		set = function(val)
			addon.db["combatMeterOverlayAlpha"] = (val or 0) / 100
			if addon.CombatMeter.functions.applyBarTextures then addon.CombatMeter.functions.applyBarTextures() end
		end,
		parent = true,
		element = overlayEnable.element,
		parentCheck = overlayEnabled,
		parentSection = sectionCM,
	})

	addon.functions.SettingsCreateCheckbox(cCM, {
		var = "combatMeterRoundedCorners",
		text = L["Rounded Corners"],
		func = function(v)
			addon.db["combatMeterRoundedCorners"] = v
			if addon.CombatMeter.functions.applyBarTextures then addon.CombatMeter.functions.applyBarTextures() end
		end,
		parent = true,
		element = cmEnable.element,
		parentCheck = cmEnabled,
		parentSection = sectionCM,
	})

	local metricNames = {
		dps = L["DPS"],
		damageOverall = L["Damage Overall"],
		healingPerFight = L["Healing Per Fight"],
		healingOverall = L["Healing Overall"],
		interrupts = INTERRUPTS,
		interruptsOverall = INTERRUPTS .. L[" Overall"],
	}
	local metricOrder = { "damageOverall", "healingOverall", "interruptsOverall", "dps", "healingPerFight", "interrupts" }

	addon.functions.SettingsCreateDropdown(cCM, {
		var = "combatMeterAddGroup",
		text = L["Add Group"],
		list = metricNames,
		default = "",
		get = function() return "" end,
		set = function(value)
			if not value or value == "" then return end
			local newId = "cmg" .. tostring(math.floor(GetTime() * 1000)) .. tostring(math.random(1000, 9999))
			local barWidth = 210
			local barHeight = 25
			local frameWidth = barWidth + barHeight + 2
			local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
			local x = (screenW - frameWidth) / 2
			local y = -((screenH - barHeight) / 2)
			addon.db["combatMeterGroups"] = addon.db["combatMeterGroups"] or {}
			table.insert(addon.db["combatMeterGroups"], {
				id = newId,
				type = value,
				point = "TOPLEFT",
				x = x,
				y = y,
				barWidth = barWidth,
				barHeight = barHeight,
				maxBars = 8,
				alwaysShowSelf = false,
			})
			if addon.CombatMeter.functions.rebuildGroups then addon.CombatMeter.functions.rebuildGroups() end
		end,
		parent = true,
		element = cmEnable.element,
		parentCheck = cmEnabled,
		listOrder = metricOrder,
		parentSection = sectionCM,
	})
end

local band = bit.band
local bor = bit.bor
local CLEU = CombatLogGetCurrentEventInfo
local GPIG = GetPlayerInfoByGUID

-- Spirit Link Totem redistribution damage (friendly-fire that should not count as DPS)
local SPIRIT_LINK_DAMAGE_SPELL_ID = 98021
local TEMPERED_IN_BATTLE_DAMAGE_SPELL_ID = 469704

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

do
	local groups = addon.db and addon.db["combatMeterGroups"]
	if groups then
		local screenH = UIParent:GetHeight()
		for _, cfg in ipairs(groups) do
			if cfg.point and cfg.point ~= "TOPLEFT" then
				local w = (cfg.barWidth or 210) + (cfg.barHeight or 25) + 2
				local temp = CreateFrame("Frame", nil, UIParent)
				temp:SetSize(w, cfg.barHeight or 25)
				temp:SetPoint(cfg.point, UIParent, cfg.point, cfg.x or 0, cfg.y or 0)
				cfg.x = temp:GetLeft()
				cfg.y = temp:GetTop() - screenH
				cfg.point = "TOPLEFT"
				temp:Hide()
				temp:SetParent(nil)
			end
		end
	end
end

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

local spellCache = {}
local iconCache = {}

-- Guardians spawned without SPELL_SUMMON. Add NPC IDs here.
local missingSummonNPCs = {
	[144961] = true, -- SecTec
	[31216] = true, -- Mirror Images
	[165189] = true, -- Generic Hunter Pet
}

local tooltipLookup = {}

local getIDFromGUID = addon.functions.getIDFromGUID

local function setOwnerFromTooltip(guid)
	local tooltipData = C_TooltipInfo.GetHyperlink("unit:" .. guid)
	if not tooltipData then return end

	local ownerGUID = tooltipData.guid
	if (not ownerGUID or ownerGUID:find("^Pet")) and tooltipData.lines then
		for i = 1, #tooltipData.lines do
			local lineData = tooltipData.lines[i]
			local lToken = lineData.unitToken
			if lineData.unitToken then
				ownerGUID = UnitGUID(lineData.unitToken)
				if ownerGUID then break end
			end
			if lineData.guid and lineData.guid:find("^Player") then
				ownerGUID = lineData.guid
				if ownerGUID then break end
			end
		end
	end

	if ownerGUID and ownerGUID:find("^Player") then
		petOwner[guid] = ownerGUID
		ownerPets[ownerGUID] = ownerPets[ownerGUID] or {}
		ownerPets[ownerGUID][guid] = true
		return ownerGUID
	end
end

local function trySetOwnerFromTooltip(guid)
	local now = GetTime()
	if (tooltipLookup[guid] or 0) + 1 < now then
		tooltipLookup[guid] = now
		setOwnerFromTooltip(guid)
	end
end

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
		player.interrupts = 0
		-- Initialize friendly-fire trackers
		player.friendlyFire = 0
		player.spiritLinkDamage = 0
		player.temperedDamage = 0
		local _, class = GPIG(guid)
		player.class = class
		players[guid] = player
	end
	if name and player.name ~= name then player.name = name end
	player.damageSpells = player.damageSpells or {}
	player.healSpells = player.healSpells or {}
	player.interruptSpells = player.interruptSpells or {}
	return player
end

local function releasePlayers(players)
	local pool = cm.playerPool
	for guid in pairs(players) do
		local player = players[guid]
		local dmg = player.damageSpells
		if dmg then wipe(dmg) end
		local heal = player.healSpells
		if heal then wipe(heal) end
		local interrupts = player.interruptSpells
		if interrupts then wipe(interrupts) end
		wipe(player)
		player.damageSpells = dmg
		player.healSpells = heal
		player.interruptSpells = interrupts
		pool[#pool + 1] = player
		players[guid] = nil
	end
end

local function resetMeter()
	releasePlayers(cm.players)
	releasePlayers(cm.overallPlayers)
	cm.overallDuration = 0
	cm.fightDuration = 0
	cm.prePullHead = 1
	cm.prePullTail = 0
	wipe(cm.prePullBuffer)

	cm.historySelection = nil
	cm.historyUnits = nil

	cm.inCombat = UnitAffectingCombat("player")
	cm.fightStartTime = cm.inCombat and GetTime() or 0
	wipe(tooltipLookup)
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
	wipe(tooltipLookup)
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

local function addPrePull(ownerGUID, ownerName, damage, healing, spellId, spellName, crit, periodic)
	local buf = cm.prePullBuffer
	local now = GetTime()
	local tail = cm.prePullTail + 1
	buf[tail] = {
		t = now,
		guid = ownerGUID,
		name = ownerName,
		damage = damage or 0,
		healing = healing or 0,
		spellId = spellId,
		spellName = spellName,
		crit = crit,
		periodic = periodic,
	}
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
			local sid = e.spellId or -1
			local sname = e.spellName or "Other"
			local periodic = e.periodic
			local icon = iconCache[sid]
			if sid > 0 and not icon then
				local si = C_Spell.GetSpellInfo(sid)
				icon = si and si.iconID
				iconCache[sid] = icon
			end
			if e.damage and e.damage > 0 then
				local ps = p.damageSpells[sid]
				if not ps then
					ps = { name = sname, amount = 0, hits = 0, crits = 0, periodicHits = 0, icon = icon }
					p.damageSpells[sid] = ps
				end
				ps.name = sname
				ps.icon = ps.icon or icon
				ps.amount = ps.amount + e.damage
				ps.hits = (ps.hits or 0) + 1
				if periodic then ps.periodicHits = (ps.periodicHits or 0) + 1 end
				if e.crit then ps.crits = (ps.crits or 0) + 1 end
				local os = o.damageSpells[sid]
				if not os then
					os = { name = sname, amount = 0, hits = 0, crits = 0, periodicHits = 0, icon = icon }
					o.damageSpells[sid] = os
				end
				os.name = sname
				os.icon = os.icon or icon
				os.amount = os.amount + e.damage
				os.hits = (os.hits or 0) + 1
				if periodic then os.periodicHits = (os.periodicHits or 0) + 1 end
				if e.crit then os.crits = (os.crits or 0) + 1 end
				p.damage = p.damage + e.damage
				o.damage = o.damage + e.damage
			end
			if e.healing and e.healing > 0 then
				local ps = p.healSpells[sid]
				if not ps then
					ps = { name = sname, amount = 0, hits = 0, crits = 0, periodicHits = 0, icon = icon }
					p.healSpells[sid] = ps
				end
				ps.name = sname
				ps.icon = ps.icon or icon
				ps.amount = ps.amount + e.healing
				ps.hits = (ps.hits or 0) + 1
				if periodic then ps.periodicHits = (ps.periodicHits or 0) + 1 end
				if e.crit then ps.crits = (ps.crits or 0) + 1 end
				local os = o.healSpells[sid]
				if not os then
					os = { name = sname, amount = 0, hits = 0, crits = 0, periodicHits = 0, icon = icon }
					o.healSpells[sid] = os
				end
				os.name = sname
				os.icon = os.icon or icon
				os.amount = os.amount + e.healing
				os.hits = (os.hits or 0) + 1
				if periodic then os.periodicHits = (os.periodicHits or 0) + 1 end
				if e.crit then os.crits = (os.crits or 0) + 1 end
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

local function getSpellInfoFromSub(sub, a12, a15)
	if sub == "SWING_DAMAGE" then return 6603, "Melee", 135274 end
	-- Für SPELL_* und RANGE_* liegt die spellId in a12
	if sub == "RANGE_DAMAGE" or sub:find("^SPELL_") then
		local spellID = a12
		local name = spellID and spellCache[spellID]
		local icon = spellID and iconCache[spellID]
		if spellID and name and not icon then
			local si = C_Spell.GetSpellInfo(spellID)
			icon = si and si.iconID
			iconCache[spellID] = icon
		end
		if not name and spellID then
			local si = C_Spell.GetSpellInfo(spellID)
			if si then
				name = si.name
				icon = si.iconID
			else
				name = "Other"
			end
			spellCache[spellID] = name
			iconCache[spellID] = icon
		end
		return spellID or -1, name or "Other", icon
	end
	return -1, "Other", nil
end

local function isCritFor(sub, a18, a21)
	if sub == "SWING_DAMAGE" then return not not a18 end
	if sub == "SPELL_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE" or sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" then return not not a21 end
	return false
end

local TYPE_MASK = 64512
local TYPE_PLAYER = 1024
local TYPE_PET = 4096
local TYPE_GUARDIAN = 8192
local CONTROL_MASK = 768
local CONTROL_PLAYER = 256

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
				spiritLinkDamage = data.spiritLinkDamage or 0,
				friendlyFire = data.friendlyFire or 0,
				temperedDamage = data.temperedDamage or 0,
				interrupts = data.interrupts or 0,
				interruptSpells = (function()
					local source = data.interruptSpells
					if not source or not next(source) then return nil end
					local copy = {}
					for spellId, s in pairs(source) do
						copy[spellId] = { name = s.name, amount = s.amount, icon = s.icon }
					end
					return copy
				end)(),
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
		elseif
			not (
				dmgIdx[sub]
				or sub == "SPELL_HEAL"
				or sub == "SPELL_PERIODIC_HEAL"
				or sub == "SPELL_ABSORBED"
				or sub == "DAMAGE_SPLIT"
				or sub == "SWING_MISSED"
				or sub == "RANGE_MISSED"
				or sub == "SPELL_MISSED"
				or sub == "SPELL_PERIODIC_MISSED"
				or sub == "SPELL_INTERRUPT"
			)
		then
			return
		end
		if not inCombat and not pre then return end

		-- Attempt to map pet owners for guardians spawned without a summon event and no unitframe
		if dmgIdx[sub] and not petOwner[sourceGUID] and band(sourceFlags or 0, groupMask) ~= 0 then
			local petType = bit.band(sourceFlags, TYPE_MASK)
			if petType ~= TYPE_PLAYER then
				if (petType == TYPE_GUARDIAN or petType == TYPE_PET) and bit.band(sourceFlags, CONTROL_MASK) == CONTROL_PLAYER then
					local id = getIDFromGUID(sourceGUID)
					if id and missingSummonNPCs[id] then trySetOwnerFromTooltip(sourceGUID) end
				end
			end
		end

		local idx = dmgIdx[sub]
		if idx then
			if not sourceGUID then return end

			local ownerGUID, ownerName, ownerFlags = resolveOwner(sourceGUID, sourceName, sourceFlags)
			if not ownerFlags and cm.groupGUIDs and cm.groupGUIDs[ownerGUID] then ownerFlags = COMBATLOG_OBJECT_AFFILIATION_RAID end
			if band(ownerFlags or 0, groupMask) == 0 then return end
			local amount = (idx == 1 and a12) or a15 or 0
			local overkill = (sub == "SWING_DAMAGE") and (a13 or 0) or (a16 or 0)
			amount = amount - math.max(overkill or 0, 0)
			if amount <= 0 then return end
			local spellId, spellName, spellIcon = getSpellInfoFromSub(sub, a12, a15)
			local crit = isCritFor(sub, a18, a21)

			-- FRIENDLY-FIRE GUARD: do not count damage done to group members as DPS
			-- Track it separately so we can surface in tooltips later, and special-case Spirit Link.
			local isFriendlyTarget = band(destFlags or 0, groupMask) ~= 0
			if isFriendlyTarget then
				if inCombat then
					local player = acquirePlayer(cm.players, ownerGUID, ownerName)
					local overall = acquirePlayer(cm.overallPlayers, ownerGUID, ownerName)
					player.friendlyFire = (player.friendlyFire or 0) + amount
					overall.friendlyFire = (overall.friendlyFire or 0) + amount
					if spellId == SPIRIT_LINK_DAMAGE_SPELL_ID then
						player.spiritLinkDamage = (player.spiritLinkDamage or 0) + amount
						overall.spiritLinkDamage = (overall.spiritLinkDamage or 0) + amount
					elseif spellId == TEMPERED_IN_BATTLE_DAMAGE_SPELL_ID then
						player.temperedDamage = (player.temperedDamage or 0) + amount
						overall.temperedDamage = (overall.temperedDamage or 0) + amount
					end
				end
				return
			end

			if inCombat then
				local player = acquirePlayer(cm.players, ownerGUID, ownerName)
				local overall = acquirePlayer(cm.overallPlayers, ownerGUID, ownerName)
				local now = GetTime()
				player._first = player._first or now
				player._last = now
				player.damage = player.damage + amount
				overall.damage = overall.damage + amount
				local ps = player.damageSpells[spellId]
				if not ps then
					ps = { name = spellName, amount = 0, hits = 0, crits = 0, periodicHits = 0, icon = spellIcon }
					player.damageSpells[spellId] = ps
				end
				ps.name = spellName
				ps.icon = ps.icon or spellIcon
				ps.amount = ps.amount + amount
				ps.hits = (ps.hits or 0) + 1
				if sub == "SPELL_PERIODIC_DAMAGE" then ps.periodicHits = (ps.periodicHits or 0) + 1 end
				if crit then ps.crits = (ps.crits or 0) + 1 end
				local os = overall.damageSpells[spellId]
				if not os then
					os = { name = spellName, amount = 0, hits = 0, crits = 0, periodicHits = 0, icon = spellIcon }
					overall.damageSpells[spellId] = os
				end
				os.name = spellName
				os.icon = os.icon or spellIcon
				os.amount = os.amount + amount
				os.hits = (os.hits or 0) + 1
				if sub == "SPELL_PERIODIC_DAMAGE" then os.periodicHits = (os.periodicHits or 0) + 1 end
				if crit then os.crits = (os.crits or 0) + 1 end
			else
				addPrePull(ownerGUID, ownerName, amount, 0, spellId, spellName, crit, sub == "SPELL_PERIODIC_DAMAGE")
			end
			return
		end

		if sub == "SPELL_INTERRUPT" then
			if not inCombat then return end
			if not sourceGUID then return end
			local ownerGUID, ownerName, ownerFlags = resolveOwner(sourceGUID, sourceName, sourceFlags)
			if not ownerFlags and cm.groupGUIDs and cm.groupGUIDs[ownerGUID] then ownerFlags = COMBATLOG_OBJECT_AFFILIATION_RAID end
			if band(ownerFlags or 0, groupMask) == 0 then return end
			local player = acquirePlayer(cm.players, ownerGUID, ownerName)
			local overall = acquirePlayer(cm.overallPlayers, ownerGUID, ownerName)
			player.interrupts = (player.interrupts or 0) + 1
			overall.interrupts = (overall.interrupts or 0) + 1
			local extraSpellId, extraSpellName = a15, a16
			if extraSpellId and extraSpellName then
				local icon = iconCache[extraSpellId]
				if extraSpellId > 0 and not icon then
					local si = C_Spell.GetSpellInfo(extraSpellId)
					icon = si and si.iconID
					iconCache[extraSpellId] = icon
				end
				local ps = player.interruptSpells[extraSpellId]
				if not ps then
					ps = { name = extraSpellName, amount = 0, icon = icon }
					player.interruptSpells[extraSpellId] = ps
				end
				ps.name = extraSpellName
				ps.amount = (ps.amount or 0) + 1
				ps.icon = ps.icon or icon
				local os = overall.interruptSpells[extraSpellId]
				if not os then
					os = { name = extraSpellName, amount = 0, icon = icon }
					overall.interruptSpells[extraSpellId] = os
				end
				os.name = extraSpellName
				os.amount = (os.amount or 0) + 1
				os.icon = os.icon or icon
			end
			return
		end

		if sub == "SWING_MISSED" or sub == "RANGE_MISSED" or sub == "SPELL_MISSED" or sub == "SPELL_PERIODIC_MISSED" then
			if not sourceGUID then return end
			local missType, amount, crit
			if sub == "SWING_MISSED" then
				missType = a12
				amount = a14 or 0
				crit = a15
			else
				missType = a15
				amount = a17 or 0
				crit = a18
			end
			if missType ~= "ABSORB" or amount <= 0 then return end
			-- Ignore friendly-fire absorbs for outgoing damage credit
			if band(destFlags or 0, groupMask) ~= 0 then return end
			local ownerGUID, ownerName, ownerFlags = resolveOwner(sourceGUID, sourceName, sourceFlags)
			if not ownerFlags and cm.groupGUIDs and cm.groupGUIDs[ownerGUID] then ownerFlags = COMBATLOG_OBJECT_AFFILIATION_RAID end
			if band(ownerFlags or 0, groupMask) == 0 then return end
			local damageSub = sub:gsub("_MISSED", "_DAMAGE")
			local spellId, spellName, spellIcon = getSpellInfoFromSub(damageSub, a12, a15)
			local isPeriodic = damageSub == "SPELL_PERIODIC_DAMAGE"
			crit = not not crit
			if inCombat then
				local player = acquirePlayer(cm.players, ownerGUID, ownerName)
				local overall = acquirePlayer(cm.overallPlayers, ownerGUID, ownerName)
				local now = GetTime()
				player._first = player._first or now
				player._last = now
				player.damage = player.damage + amount
				overall.damage = overall.damage + amount
				local ps = player.damageSpells[spellId]
				if not ps then
					ps = { name = spellName, amount = 0, hits = 0, crits = 0, periodicHits = 0, icon = spellIcon }
					player.damageSpells[spellId] = ps
				end
				ps.name = spellName
				ps.icon = ps.icon or spellIcon
				ps.amount = ps.amount + amount
				ps.hits = (ps.hits or 0) + 1
				if isPeriodic then ps.periodicHits = (ps.periodicHits or 0) + 1 end
				if crit then ps.crits = (ps.crits or 0) + 1 end
				local os = overall.damageSpells[spellId]
				if not os then
					os = { name = spellName, amount = 0, hits = 0, crits = 0, periodicHits = 0, icon = spellIcon }
					overall.damageSpells[spellId] = os
				end
				os.name = spellName
				os.icon = os.icon or spellIcon
				os.amount = os.amount + amount
				os.hits = (os.hits or 0) + 1
				if isPeriodic then os.periodicHits = (os.periodicHits or 0) + 1 end
				if crit then os.crits = (os.crits or 0) + 1 end
			else
				addPrePull(ownerGUID, ownerName, amount, 0, spellId, spellName, crit, isPeriodic)
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
			local spellId, spellName, spellIcon = getSpellInfoFromSub(sub, a12, a15)
			local crit = isCritFor(sub, a18, a21)
			if inCombat then
				local player = acquirePlayer(cm.players, ownerGUID, ownerName)
				local overall = acquirePlayer(cm.overallPlayers, ownerGUID, ownerName)
				local now = GetTime()
				player._first = player._first or now
				player._last = now
				player.healing = player.healing + amount
				overall.healing = overall.healing + amount
				local ps = player.healSpells[spellId]
				if not ps then
					ps = { name = spellName, amount = 0, hits = 0, crits = 0, periodicHits = 0, icon = spellIcon }
					player.healSpells[spellId] = ps
				end
				ps.name = spellName
				ps.icon = ps.icon or spellIcon
				ps.amount = ps.amount + amount
				ps.hits = (ps.hits or 0) + 1
				if sub == "SPELL_PERIODIC_HEAL" then ps.periodicHits = (ps.periodicHits or 0) + 1 end
				if crit then ps.crits = (ps.crits or 0) + 1 end
				local os = overall.healSpells[spellId]
				if not os then
					os = { name = spellName, amount = 0, hits = 0, crits = 0, periodicHits = 0, icon = spellIcon }
					overall.healSpells[spellId] = os
				end
				os.name = spellName
				os.icon = os.icon or spellIcon
				os.amount = os.amount + amount
				os.hits = (os.hits or 0) + 1
				if sub == "SPELL_PERIODIC_HEAL" then os.periodicHits = (os.periodicHits or 0) + 1 end
				if crit then os.crits = (os.crits or 0) + 1 end
			else
				addPrePull(ownerGUID, ownerName, 0, amount, spellId, spellName, crit, sub == "SPELL_PERIODIC_HEAL")
			end
			return
		end

		-- We count absorbs exclusively via SPELL_ABSORBED. Some clients also emit *_MISSED with ABSORB for the same event; counting both leads to double credits.
		if sub == "SPELL_ABSORBED" then
			-- Heuristics: swing variant has 8 tail fields (a23 is number); spell variant has 9 (a23 is boolean, amount in a22)
			local absorberGUID, absorberName, absorberFlags, absorbedAmount, spellId, spellName, spellIcon
			if type(a23) == "boolean" then
				-- Spell-Variante mit Crit-Boolean (23 Rückgabewerte)
				absorberGUID, absorberName, absorberFlags, absorbedAmount, spellId, spellName = a15, a16, a17, a22, a19, a20
			elseif a22 ~= nil then
				-- Spell-Variante ohne Crit (22 Rückgabewerte)
				absorberGUID, absorberName, absorberFlags, absorbedAmount, spellId, spellName = a15, a16, a17, a22, a19, a20
			else
				-- Swing-Variante (19/20 Rückgabewerte)
				absorberGUID, absorberName, absorberFlags, absorbedAmount, spellId, spellName = a12, a13, a14, a19, a16, a17
			end
			if not absorberGUID or type(absorberFlags) ~= "number" then return end
			local ownerGUID, ownerName, ownerFlags = resolveOwner(absorberGUID, absorberName, absorberFlags)
			if not ownerFlags and cm.groupGUIDs and cm.groupGUIDs[ownerGUID] then ownerFlags = COMBATLOG_OBJECT_AFFILIATION_RAID end
			if band(ownerFlags or 0, groupMask) == 0 then return end
			if not absorbedAmount or absorbedAmount <= 0 then return end
			spellId, spellName, spellIcon = getSpellInfoFromSub(sub, spellId, spellName)
			if inCombat then
				local p = acquirePlayer(cm.players, ownerGUID, ownerName)
				local o = acquirePlayer(cm.overallPlayers, ownerGUID, ownerName)
				local now = GetTime()
				p._first = p._first or now
				p._last = now
				p.healing = p.healing + absorbedAmount
				o.healing = o.healing + absorbedAmount
				local ps = p.healSpells[spellId]
				if not ps then
					ps = { name = spellName, amount = 0, hits = 0, crits = 0, periodicHits = 0, icon = spellIcon }
					p.healSpells[spellId] = ps
				end
				ps.name = spellName
				ps.icon = ps.icon or spellIcon
				ps.amount = ps.amount + absorbedAmount
				ps.hits = (ps.hits or 0) + 1
				local os = o.healSpells[spellId]
				if not os then
					os = { name = spellName, amount = 0, hits = 0, crits = 0, periodicHits = 0, icon = spellIcon }
					o.healSpells[spellId] = os
				end
				os.name = spellName
				os.icon = os.icon or spellIcon
				os.amount = os.amount + absorbedAmount
				os.hits = (os.hits or 0) + 1
			else
				addPrePull(ownerGUID, ownerName, 0, absorbedAmount, spellId, spellName, false, false)
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
		player.spiritLinkDamage = p.spiritLinkDamage or 0
		player.friendlyFire = p.friendlyFire or 0
		player.temperedDamage = p.temperedDamage or 0
		player.interrupts = p.interrupts or 0
		local spells = player.interruptSpells
		if spells then wipe(spells) end
		if p.interruptSpells then
			for spellId, s in pairs(p.interruptSpells) do
				spells[spellId] = { name = s.name, amount = s.amount, icon = s.icon }
			end
		end
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
