-- LibOpenKeystone-1.0 (minimal, LOR-compatible J/K comms only)
local MAJOR, MINOR = "LibOpenKeystone-1.0", 3
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- Storage
lib.UnitData = lib.UnitData or {} -- [ "Name-Realm" ] = { challengeMapID=..., level=..., lastSeen=... }
lib._callbacks = lib._callbacks or { KeystoneUpdate = {}, KeystoneWipe = {} }

-- Constants (match LibOpenRaid)
local PREFIX = "LRS"
local PREFIX_LOGGED = "LRS_LOGGED"
local KDATA_PREFIX = "K"
local KREQ_PREFIX = "J"

local ownRealm = GetRealmName()
-- Utils
local function FullName(unit)
    local n, r = UnitFullName(unit or "player")
	r = r or ownRealm
	return (n and r) and (n .. "-" .. r) or (UnitName(unit or "player") or "Unknown")
end

local function Now() return GetServerTime() end

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
local function ReadOwnKeystone()
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

-- Safe/logged send (compatible with LOR expectations)
local function SendLogged(text, channel)
	-- encode like LOR does:
	local plain = text
	plain = plain:gsub("\n", "%%")
	plain = plain:gsub(",", ";")
	local commId = tostring(GetServerTime() + GetTime())
	plain = plain .. "#" .. commId
	-- target channel
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
	if ch == "WHISPER" then return end -- no need
	if ChatThrottleLib and ChatThrottleLib.SendAddonMessageLogged then
		ChatThrottleLib:SendAddonMessageLogged("NORMAL", PREFIX_LOGGED, plain, ch)
	else
		-- Fallback (unthrottled). Receivers with LOR still parse it.
		C_ChatInfo.SendAddonMessage(PREFIX_LOGGED, plain, ch)
	end
end

-- Build / parse payloads
local function BuildKPayload(nameRealm, mapID, level)
	nameRealm = nameRealm or FullName("player")
	mapID = tonumber(mapID) or 0
	level = tonumber(level) or 0
	-- Keep it tiny and LOR-friendly. Extra fields can be added at the end.
	return string.format("%s,%s,%d,%d", KDATA_PREFIX, nameRealm, mapID, level)
end
local function ParseLoggedPayload(text)
	-- reverse LOR safe-encoding
	local s = text:gsub("%%", "\n")
	s = s:gsub("#[^#]+$", "") -- strip #commId
	s = s:gsub(";", ",") -- restore commas
	return s
end

-- Receive & handle data
local recvParts = {} -- sender -> { total, chunks={} }
local function HandleCompleteLogged(sender, channel, msg)
	local data = ParseLoggedPayload(msg)
	local dtype = data:sub(1, 1)
	if dtype == KREQ_PREFIX then
		-- someone asked → respond with our key
		local me = FullName("player")
		local mapID, level = ReadOwnKeystone()
		SendLogged(BuildKPayload(me, mapID, level), channel)
	elseif dtype == KDATA_PREFIX then
		-- tableize, tolerate extra/unknown fields
		local tokens = { strsplit(",", data) }
		-- tokens[1] == "K"
		local nameRealm = tokens[2]
		-- heuristics: find first and second numeric tokens
		local nums = {}
		for i = 3, #tokens do
			local n = tonumber(tokens[i])
			if n then nums[#nums + 1] = n end
		end
		local mapID = nums[1] or 0
		local level = nums[2] or 0

		if nameRealm and nameRealm ~= "" then
			lib.UnitData[nameRealm] = lib.UnitData[nameRealm] or {}
			local entry = lib.UnitData[nameRealm]
			entry.challengeMapID = mapID
			entry.level = level
			entry.lastSeen = Now()
			-- fire callback: same shape as LOR: (self, playerKey, data)
			Fire("KeystoneUpdate", nameRealm, entry)
		end
	end
end

local function OnLogged(self, event, prefix, text, channel, sender)
	if prefix ~= PREFIX_LOGGED then return end
	sender = Ambiguate(sender, "none")
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

-- Register for logged comms
if C_ChatInfo then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX_LOGGED) end
local f = lib._frame or CreateFrame("Frame")
lib._frame = f
f:RegisterEvent("CHAT_MSG_ADDON_LOGGED")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:SetScript("OnEvent", function(_, ev, ...)
	if ev == "CHAT_MSG_ADDON_LOGGED" then return OnLogged(_, ev, ...) end
	if ev == "PLAYER_ENTERING_WORLD" or ev == "GROUP_ROSTER_UPDATE" then
		-- ask group and also advertise our own key once
		C_Timer.After(0.2, function()
			if IsInGroup() then
				lib.RequestKeystoneDataFromParty()
			else
				-- solo: just refresh local
				local me = FullName("player")
				local mapID, level = ReadOwnKeystone()
				lib.UnitData[me] = { challengeMapID = mapID, level = level, lastSeen = Now() }
				Fire("KeystoneUpdate", me, lib.UnitData[me])
			end
		end)
	elseif ev == "BAG_UPDATE_DELAYED" then
		-- if our key changed, notify group (cheap)
		local me = FullName("player")
		local mapID, level = ReadOwnKeystone()
		local e = lib.UnitData[me]
		if not e or e.challengeMapID ~= mapID or e.level ~= level then
			lib.UnitData[me] = { challengeMapID = mapID, level = level, lastSeen = Now() }
			Fire("KeystoneUpdate", me, lib.UnitData[me])
			if IsInGroup() then SendLogged(BuildKPayload(me, mapID, level)) end
		end
	end
end)

-- Public: request from party/raid + send own key proactively
function lib.RequestKeystoneDataFromParty()
	if not (IsInGroup() or IsInRaid()) then return end
	-- broadcast request
	SendLogged(KREQ_PREFIX .. "," .. FullName("player"))
	-- answer for ourselves too (immediate)
	local me = FullName("player")
	local mapID, level = ReadOwnKeystone()
	SendLogged(BuildKPayload(me, mapID, level))
end
