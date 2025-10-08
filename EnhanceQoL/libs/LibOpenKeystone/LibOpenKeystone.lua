-- LibOpenKeystone-1.0 (minimal, LOR-compatible J/K comms only)
local MAJOR, MINOR = "LibOpenKeystone-1.0", 5
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- forward declarations for luacheck/lint friendliness
local ReadOwnKeystone, SendLogged, BuildKPayload

-- Storage
lib.UnitData = lib.UnitData or {} -- [ "Name" or "Name-Realm" ] = { challengeMapID=..., level=..., lastSeen=... }
lib._callbacks = lib._callbacks or { KeystoneUpdate = {}, KeystoneWipe = {} }
-- Debounce/state helpers
lib._pendingAnnounce = lib._pendingAnnounce or false
lib._lastRequestAt = lib._lastRequestAt or 0
lib._bagPending = lib._bagPending or false
-- OOC gating flags
lib._pendingSendMyData = lib._pendingSendMyData or false
lib._pendingRequestParty = lib._pendingRequestParty or false
-- M+ gating
lib._mplusActive = lib._mplusActive or false
lib._eligible = lib._eligible or true -- assume true until we can evaluate

-- Outgoing messages use a custom prefix; incoming accepts both LibOpenRaid
-- and LibOpenKeystone prefixes
local SEND_PREFIX = "EQKS"
local SEND_PREFIX_LOGGED = "EQKS_LOGGED"
local RECV_PREFIXES = { ["LRS"] = true, [SEND_PREFIX] = true }
local RECV_PREFIXES_LOGGED = { ["LRS_LOGGED"] = true, [SEND_PREFIX_LOGGED] = true }
local KDATA_PREFIX = "K"
local KREQ_PREFIX = "J"

local ownRealm = (GetRealmName():gsub("%s", ""))
-- Utils
local function FullName(unit)
	local n, r = UnitFullName(unit or "player")
	if not n then return UnitName(unit or "player") or "Unknown" end
	if r and r ~= "" and r ~= ownRealm then return n .. "-" .. r end
	return n
end
local function NormalizeKey(name, sender)
	if not name or name == "" then return nil end
	-- split 'Name' or 'Name-Realm'
	local base, realm = name:match("^([^%-]+)%-?(.*)$")
	if realm == "" then realm = nil end
	local senderRealm = sender and sender:match("-(.+)$") or nil
	realm = (realm and realm:gsub("%s", "")) or senderRealm or ownRealm
	-- LOR-kompatibel: gleicher Realm => Kurzname, sonst Name-Realm
	if realm == ownRealm then
		return base
	else
		return base .. "-" .. realm
	end
end

local function Now() return GetServerTime() end
local function InCombat() return InCombatLockdown and InCombatLockdown() end

local function IsMPlusActive()
	if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive then
		local ok = C_ChallengeMode.IsChallengeModeActive()
		if ok ~= nil then return ok end
	end
	local _, _, diff = GetInstanceInfo()
	return diff == 8
end

local function GetCurrentExpansionMaxLevel()
	local gmlfe = _G and _G.GetMaxLevelForExpansionLevel
	local lec = _G and _G.LE_EXPANSION_LEVEL_CURRENT
	if gmlfe and lec then return gmlfe(lec) end
	local gmlfpe = _G and _G.GetMaxLevelForPlayerExpansion
	if gmlfpe then return gmlfpe() end
	return nil
end

local function IsEligibleForKeystone()
	local lvl = UnitLevel and UnitLevel("player") or 0
	local maxLvl = GetCurrentExpansionMaxLevel()
	if type(maxLvl) == "number" and maxLvl > 0 then return lvl >= maxLvl end
	-- If we cannot determine, default to true to avoid disabling legit comms
	return true
end

local function QueueSendMyData() lib._pendingSendMyData = true end

local function QueueRequestParty() lib._pendingRequestParty = true end

local function FlushPending()
	if lib._pendingRequestParty and lib._eligible and not InCombat() and not lib._mplusActive then
		lib._pendingRequestParty = false
		-- Anfrage nach OOC
		SendLogged(KREQ_PREFIX)
	end
	if lib._pendingSendMyData and lib._eligible and not InCombat() and not lib._mplusActive then
		lib._pendingSendMyData = false
		-- Eigen-Daten nach OOC
		local mapID, level = ReadOwnKeystone()
		SendLogged(BuildKPayload(mapID, level))
	end
end

-- Public callbacks API (same shape as LOR)
function lib.RegisterCallback(addonObject, event, method)
	if type(addonObject) == "string" then addonObject = _G[addonObject] end
	if not addonObject or not lib._callbacks[event] then return false end
	table.insert(lib._callbacks[event], { addonObject, method })
	return true
end
function lib.UnregisterCallback(addonObject, event, method)
	local t = lib._callbacks[event]
	if not t then return end
	for i = #t, 1, -1 do
		local e = t[i]
		if e[1] == addonObject and e[2] == method then table.remove(t, i) end
	end
end
local function Fire(event, ...)
	local t = lib._callbacks[event]
	if not t then return end
	for i = 1, #t do
		local obj, meth = t[i][1], t[i][2]
		local fn = type(meth) == "function" and meth or (obj and obj[meth])
		if fn then pcall(fn, obj, ...) end
	end
end

-- Local keystone read (Retail APIs; with fallbacks)
function ReadOwnKeystone()
	local mapID, level = 0, 0
	if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID then
		mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID() or 0
		level = C_MythicPlus.GetOwnedKeystoneLevel and (C_MythicPlus.GetOwnedKeystoneLevel() or 0) or 0
	elseif C_ChallengeMode and C_ChallengeMode.GetOwnedKeystoneMapID then
		mapID = C_ChallengeMode.GetOwnedKeystoneMapID() or 0
		level = C_ChallengeMode.GetOwnedKeystoneLevel and (C_ChallengeMode.GetOwnedKeystoneLevel() or 0) or 0
	end
	return mapID, level
end

-- Public API
function lib.GetAllKeystonesInfo() return lib.UnitData end
function lib.WipeKeystoneData()
	for k in pairs(lib.UnitData) do
		lib.UnitData[k] = nil
	end
	Fire("KeystoneWipe")
end

-- Safe/logged send (uses our custom send prefix only)
function SendLogged(text, channel)
	-- Zielkanal ermitteln
	local ch = channel
	if not ch then
		if IsInRaid() then
			ch = IsInRaid(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "RAID"
		elseif IsInGroup() then
			ch = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY"
		else
			ch = "WHISPER"
		end
	end
	if ch == "WHISPER" then return end -- keine Whisper-Broadcasts

	-- Preferred: compressed AceComm on our own prefix
	local AceComm = LibStub:GetLibrary("AceComm-3.0", true)
	local LibDeflate = LibStub:GetLibrary("LibDeflate", true)
	if AceComm and LibDeflate then
		local compressed = LibDeflate:CompressDeflate(text, { level = 9 })
		local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)
		AceComm:SendCommMessage(SEND_PREFIX, encoded, ch, nil, "NORMAL")
		return
	end

	-- Fallback: LOGGED-safe
	if ChatThrottleLib and ChatThrottleLib.SendAddonMessageLogged then
		local plain = text:gsub("\n", "%%"):gsub(",", ";")
		local commId = tostring(GetServerTime() + GetTime())
		plain = plain .. "#" .. commId
		ChatThrottleLib:SendAddonMessageLogged("NORMAL", SEND_PREFIX_LOGGED, plain, ch)
		return
	end

	-- Last resort: plain logged via C_ChatInfo
	local plain = text:gsub("\n", "%%"):gsub(",", ";")
	local commId = tostring(GetServerTime() + GetTime())
	plain = plain .. "#" .. commId
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(SEND_PREFIX_LOGGED, plain, ch) end
end

-- Build / parse payloads
-- LOR-compatible: no name in payload
function BuildKPayload(mapID, level)
	mapID = tonumber(mapID) or 0
	level = tonumber(level) or 0
	return string.format("%s,%d,%d", KDATA_PREFIX, mapID, level)
end
local function ParseLoggedPayload(text)
	-- reverse LOR safe-encoding
	local s = text:gsub("%%", "\n")
	s = s:gsub("#[^#]+$", "") -- strip #commId
	s = s:gsub(";", ",") -- restore commas
	return s
end

-- Common processor for decoded data (either from LOGGED-safe or AceComm-compressed)
local function ProcessData(sender, channel, data)
	if lib._mplusActive then return end -- no processing during active M+
	local dtype = data:sub(1, 1)
	if dtype == KREQ_PREFIX then
		-- someone asked → respond with our key (OOC and not during M+ only)
		local me = FullName("player")
		local mapID, level = ReadOwnKeystone()
		-- only send OOC + not in M+
		if InCombat() or lib._mplusActive then
			QueueSendMyData()
		else
			SendLogged(BuildKPayload(mapID, level), channel)
		end
		return
	elseif dtype == KDATA_PREFIX then
		local tokens = { strsplit(",", data) }
		local key, mapID, level

		-- A) LOR: K,<mapID>,<level>
		-- B) LOK: K,<mapID>,<level>
		key = NormalizeKey(sender, sender) -- Sender ist der Spieler
		if #tokens > 3 then
			level = tonumber(tokens[2]) or 0
			mapID = tonumber(tokens[4]) or 0
		else
			mapID = tonumber(tokens[2]) or 0
			level = tonumber(tokens[3]) or 0
		end

		if key and key ~= "" then
			-- Kurz <-> Voll konsolidieren
			local short = key:match("^[^-]+")
			local alt = (key:find("-", 1, true) and short) or (short .. "-" .. ownRealm)
			if alt ~= key and lib.UnitData[alt] then lib.UnitData[alt] = nil end

			-- WICHTIG: kompletten Eintrag ersetzen -> keine Fremdfelder wie classColor behalten
			lib.UnitData[key] = {
				challengeMapID = mapID,
				level = level,
				lastSeen = Now(),
			}

			Fire("KeystoneUpdate", key, lib.UnitData[key])
		end
	end
end

-- Receive & handle data
local recvParts = {} -- sender -> { total, chunks={} }
local function HandleCompleteLogged(sender, channel, msg)
	local data = ParseLoggedPayload(msg)
	ProcessData(sender, channel, data)
end

local function OnLogged(self, event, prefix, text, channel, sender)
	if lib._mplusActive then return end -- ignore inbound during M+
	if not RECV_PREFIXES_LOGGED[prefix] then return end
	sender = Ambiguate(sender, "none")
	-- ignore self (short oder full)
	local meShort = UnitName("player")
	local meFull = FullName("player")
	local senderShort = sender and sender:match("^[^-]+")
	if sender == meShort or sender == meFull or (senderShort and senderShort == meShort) then return end
	-- chunked?
	local n, total, rest = text:match("^%$(%d+)%$(%d+)(.*)")
	if n and total and rest then
		n, total = tonumber(n), tonumber(total)
		local rec = recvParts[sender]
		if not rec then
			rec = { total = total, chunks = {} }
			recvParts[sender] = rec
		end
		rec.chunks[n] = rest
		local done = true
		for i = 1, rec.total do
			if not rec.chunks[i] then
				done = false
				break
			end
		end
		if done then
			local full = table.concat(rec.chunks, "")
			recvParts[sender] = nil
			HandleCompleteLogged(sender, channel, full)
		end
	else
		HandleCompleteLogged(sender, channel, text)
	end
end

-- Also accept compressed AceComm traffic on LibOpenRaid and our prefix
do
	local AceComm = LibStub:GetLibrary("AceComm-3.0", true)
	local LibDeflate = LibStub:GetLibrary("LibDeflate", true)
	if AceComm and LibDeflate then
		lib._ace = lib._ace or {}
		function lib._ace:OnReceiveComm(prefix, text, channel, sender)
			if lib._mplusActive then return end -- ignore inbound during M+
			if not RECV_PREFIXES[prefix] then return end
			sender = Ambiguate(sender, "none")
			-- ignore self (short or full)
			local meShort = UnitName("player")
			local meFull = FullName("player")
			local senderShort = sender and sender:match("^[^-]+")
			if sender == meShort or sender == meFull or (senderShort and senderShort == meShort) then return end

			local decoded = LibDeflate:DecodeForWoWAddonChannel(text)
			if not decoded then return end
			local data = LibDeflate:DecompressDeflate(decoded)
			if type(data) ~= "string" or #data < 1 then return end
			ProcessData(sender, channel, data)
		end
		AceComm:Embed(lib._ace)
		for p in pairs(RECV_PREFIXES) do
			lib._ace:RegisterComm(p, "OnReceiveComm")
		end
	end
end

-- Register for logged comms
if C_ChatInfo then
	for p in pairs(RECV_PREFIXES_LOGGED) do
		C_ChatInfo.RegisterAddonMessagePrefix(p)
	end
end
local f = lib._frame or CreateFrame("Frame")
lib._frame = f
f:RegisterEvent("CHAT_MSG_ADDON_LOGGED")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("CHALLENGE_MODE_START")
f:RegisterEvent("CHALLENGE_MODE_COMPLETED")
f:RegisterEvent("CHALLENGE_MODE_RESET")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:SetScript("OnEvent", function(_, ev, ...)
	if ev == "CHAT_MSG_ADDON_LOGGED" then return OnLogged(_, ev, ...) end
	if ev == "PLAYER_ENTERING_WORLD" or ev == "GROUP_ROSTER_UPDATE" then
		-- Update initial M+ state on zone/load
		lib._mplusActive = IsMPlusActive()
		-- Evaluate eligibility (max level)
		lib._eligible = IsEligibleForKeystone()
		-- Debounce bursts: schedule a single announce for rapid event sequences
		if not lib._pendingAnnounce then
			lib._pendingAnnounce = true
			C_Timer.After(0.25 + math.random() * 0.2, function()
				lib._pendingAnnounce = false
				if IsInGroup() then
					lib.RequestKeystoneDataFromParty()
				else
					-- solo: just refresh local
					if not lib._mplusActive and lib._eligible then
						local me = UnitName("player")
						local mapID, level = ReadOwnKeystone()
						lib.UnitData[me] = { challengeMapID = mapID, level = level, lastSeen = Now() }
						Fire("KeystoneUpdate", me, lib.UnitData[me])
					end
				end
			end)
		end
	elseif ev == "BAG_UPDATE_DELAYED" then
		if not lib._eligible then return end
		-- Lightly buffer multiple bag events close together
		if not lib._bagPending then
			lib._bagPending = true
			C_Timer.After(0.15, function()
				lib._bagPending = false
				-- if our key changed, notify group (cheap)
				local me = UnitName("player")
				local mapID, level = ReadOwnKeystone()
				local e = lib.UnitData[me]
				if not e or e.challengeMapID ~= mapID or e.level ~= level then
					if not lib._mplusActive then
						lib.UnitData[me] = { challengeMapID = mapID, level = level, lastSeen = Now() }
						Fire("KeystoneUpdate", me, lib.UnitData[me])
					end
					if IsInGroup() then
						if lib._mplusActive then
							-- no-op during active M+
						elseif InCombat() then
							QueueSendMyData()
						else
							SendLogged(BuildKPayload(mapID, level))
						end
					end
				end
			end)
		end
	elseif ev == "PLAYER_REGEN_ENABLED" then
		-- Flush any queued comms after combat ends
		FlushPending()
	elseif ev == "CHALLENGE_MODE_START" then
		-- During active M+ do not send any comms
		lib._mplusActive = true
	elseif ev == "CHALLENGE_MODE_RESET" then
		-- Run aborted: allow comms again and do a delayed flush
		lib._mplusActive = false
		lib._pendingRequestParty = true -- ensure a fresh check after abort
		C_Timer.After(2.0, FlushPending)
	elseif ev == "CHALLENGE_MODE_COMPLETED" then
		-- After finish: small grace period, then flush any pending
		lib._mplusActive = false
		lib._pendingRequestParty = true -- ensure a fresh check after finish
		C_Timer.After(2.0, FlushPending)
	elseif ev == "PLAYER_LEVEL_UP" then
		local was = lib._eligible
		lib._eligible = IsEligibleForKeystone()
		if lib._eligible and not was then
			-- became eligible: optionally request party after short delay
			C_Timer.After(1.0, function()
				if not InCombat() and not lib._mplusActive and IsInGroup() then lib.RequestKeystoneDataFromParty() end
			end)
		end
	end
end)

-- Public: request from party/raid + send own key proactively
function lib.RequestKeystoneDataFromParty()
	if not (IsInGroup() or IsInRaid()) then return end
	-- simple cooldown to avoid burst storms
	local t = GetTime()
	if (t - (lib._lastRequestAt or 0)) < 5 then return end
	lib._lastRequestAt = t

	-- Anfrage
	if lib._mplusActive then return end
	if InCombat() then
		QueueRequestParty()
	else
		SendLogged(KREQ_PREFIX)
	end

	-- sofortige Eigen-Antwort
	local mapID, level = ReadOwnKeystone()
	if lib._mplusActive then return end
	if InCombat() then
		QueueSendMyData()
	else
		SendLogged(BuildKPayload(mapID, level))
	end
end
