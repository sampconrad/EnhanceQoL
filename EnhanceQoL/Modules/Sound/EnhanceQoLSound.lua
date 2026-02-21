local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Sound")
local LSM = LibStub("LibSharedMedia-3.0", true)

local function toggleSounds(sounds, state)
	if type(sounds) == "table" then
		for _, v in pairs(sounds) do
			if state then
				MuteSoundFile(v)
			else
				UnmuteSoundFile(v)
			end
		end
	end
end

-- hooksecurefunc("PlaySound", function(soundID, channel, forceNoDuplicates)
-- 	if addon.db["sounds_DebugEnabled"] then print("Sound played:", soundID, "on channel:", channel) end
-- end)

-- -- Hook für PlaySoundFile
-- hooksecurefunc("PlaySoundFile", function(soundFile, channel)
-- 	if addon.db["sounds_DebugEnabled"] then print("Sound file played:", soundFile, "on channel:", channel) end
-- end)

local function applyMutedSounds()
	if not addon.db or not addon.Sounds or not addon.Sounds.soundFiles then return end
	for topic in pairs(addon.Sounds.soundFiles) do
		if topic == "emotes" then
		elseif topic == "spells" then
			for spell in pairs(addon.Sounds.soundFiles[topic]) do
				if addon.db["sounds_mounts_" .. spell] then toggleSounds(addon.Sounds.soundFiles[topic][spell], true) end
			end
		elseif topic == "mounts" then
			for mount in pairs(addon.Sounds.soundFiles[topic]) do
				if addon.db["sounds_mounts_" .. mount] then toggleSounds(addon.Sounds.soundFiles[topic][mount], true) end
			end
		else
			for class in pairs(addon.Sounds.soundFiles[topic]) do
				for key in pairs(addon.Sounds.soundFiles[topic][class]) do
					if addon.db["sounds_" .. topic .. "_" .. class .. "_" .. key] then toggleSounds(addon.Sounds.soundFiles[topic][class][key], true) end
				end
			end
		end
	end
end

local function isFrameShown(frame) return frame and frame.IsShown and frame:IsShown() end

local function isCinematicPlaying() return isFrameShown(CinematicFrame) or isFrameShown(MovieFrame) end

local function applyAudioSync()
	if not SetCVar then return end
	SetCVar("Sound_OutputDriverIndex", "0")
	if Sound_GameSystem_RestartSoundSystem and not isCinematicPlaying() then Sound_GameSystem_RestartSoundSystem() end
end

local function resolveExtraSound(soundName)
	if not soundName or soundName == "" or not LSM then return end
	return LSM:Fetch("sound", soundName, true)
end

local function getExtraEventEntry(eventName)
	local events = addon.Sounds and addon.Sounds.extraSoundEvents
	if type(events) ~= "table" then return end
	for _, entry in ipairs(events) do
		if entry and entry.event == eventName then return entry end
	end
end

local extraSoundFrame

local function playExtraSoundByKey(eventKey, ...)
	if not addon.db or addon.db.soundExtraEnabled ~= true then return end
	local entry = getExtraEventEntry(eventKey)
	if entry and type(entry.condition) == "function" then
		if not entry.condition(eventKey, ...) then return end
	end
	local mapping = addon.db.soundExtraEvents
	local soundName = mapping and mapping[eventKey]
	if not soundName or soundName == "" then return end
	local file = resolveExtraSound(soundName)
	if file then PlaySoundFile(file, "Master") end
end

local personalOrdersSnapshot
local craftingOrdersTrackingActive = false

local function getPersonalOrderCounts()
	if not C_CraftingOrders or not C_CraftingOrders.GetPersonalOrdersInfo then return end
	local infos = C_CraftingOrders.GetPersonalOrdersInfo()
	if type(infos) ~= "table" then return end
	local counts = {}
	for _, info in ipairs(infos) do
		local count = tonumber(info.numPersonalOrders) or 0
		local professionKey = info.profession or info.professionName
		if professionKey ~= nil then counts[professionKey] = (counts[professionKey] or 0) + count end
	end
	return counts
end

local function primePersonalOrdersSnapshot()
	local counts = getPersonalOrderCounts()
	if counts then personalOrdersSnapshot = counts end
end

local function diffPersonalOrderCounts(oldCounts, newCounts)
	local added, removed = 0, 0
	for key, newCount in pairs(newCounts) do
		local oldCount = oldCounts[key] or 0
		if newCount > oldCount then
			added = added + (newCount - oldCount)
		elseif newCount < oldCount then
			removed = removed + (oldCount - newCount)
		end
	end
	for key, oldCount in pairs(oldCounts) do
		if newCounts[key] == nil and oldCount > 0 then removed = removed + oldCount end
	end
	return added, removed, (added > 0 or removed > 0)
end

local function handleCraftingOrdersUpdate()
	local newCounts = getPersonalOrderCounts()
	if not newCounts then return end
	if not personalOrdersSnapshot then
		personalOrdersSnapshot = newCounts
		return
	end
	local added, removed, changed = diffPersonalOrderCounts(personalOrdersSnapshot, newCounts)
	personalOrdersSnapshot = newCounts
	if not changed then return end
	if added > 0 then playExtraSoundByKey("CRAFTINGORDERS_PERSONAL_ORDER_NEW") end
	if removed > 0 then playExtraSoundByKey("CRAFTINGORDERS_PERSONAL_ORDER_REMOVED") end
end

local function isCraftingOrdersSoundConfigured(mapping)
	if not mapping then return false end
	return (mapping["CRAFTINGORDERS_PERSONAL_ORDER_NEW"] and mapping["CRAFTINGORDERS_PERSONAL_ORDER_NEW"] ~= "")
		or (mapping["CRAFTINGORDERS_PERSONAL_ORDER_REMOVED"] and mapping["CRAFTINGORDERS_PERSONAL_ORDER_REMOVED"] ~= "")
end

local function playExtraSound(event, ...)
	if event == "CRAFTINGORDERS_UPDATE_PERSONAL_ORDER_COUNTS" then
		handleCraftingOrdersUpdate()
		return
	end
	if event == "PLAYER_ENTERING_WORLD" and craftingOrdersTrackingActive then primePersonalOrdersSnapshot() end
	playExtraSoundByKey(event, ...)
end

local audioSyncFrame

function addon.Sounds.functions.UpdateAudioSync()
	if not audioSyncFrame then
		audioSyncFrame = CreateFrame("Frame")
		audioSyncFrame:SetScript("OnEvent", function()
			if not addon.db or not addon.db.keepAudioSynced then return end
			applyAudioSync()
		end)
	end

	audioSyncFrame:UnregisterEvent("VOICE_CHAT_OUTPUT_DEVICES_UPDATED")

	if addon.db and addon.db.keepAudioSynced then
		audioSyncFrame:RegisterEvent("VOICE_CHAT_OUTPUT_DEVICES_UPDATED")
		applyAudioSync()
	end
end

function addon.Sounds.functions.UpdateExtraSounds()
	if not addon.db or addon.db.soundExtraEnabled ~= true then
		if extraSoundFrame then extraSoundFrame:UnregisterAllEvents() end
		personalOrdersSnapshot = nil
		craftingOrdersTrackingActive = false
		return
	end

	if not extraSoundFrame then
		extraSoundFrame = CreateFrame("Frame")
		extraSoundFrame:SetScript("OnEvent", function(_, event, ...) playExtraSound(event, ...) end)
	end

	extraSoundFrame:UnregisterAllEvents()

	local events = addon.Sounds and addon.Sounds.extraSoundEvents
	if type(events) ~= "table" then return end
	local mapping = addon.db.soundExtraEvents
	local craftingOrdersActive = isCraftingOrdersSoundConfigured(mapping)
	if craftingOrdersActive ~= craftingOrdersTrackingActive then
		craftingOrdersTrackingActive = craftingOrdersActive
		personalOrdersSnapshot = nil
	end
	if craftingOrdersTrackingActive and not personalOrdersSnapshot then primePersonalOrdersSnapshot() end
	for _, entry in ipairs(events) do
		local eventName = entry and entry.event
		if type(eventName) == "string" and eventName ~= "" then
			local soundName = mapping and mapping[eventName]
			if soundName and soundName ~= "" then
				local registerEvent = entry.registerEvent or eventName
				if type(registerEvent) == "table" then
					for _, eventToRegister in ipairs(registerEvent) do
						if type(eventToRegister) == "string" and eventToRegister ~= "" then extraSoundFrame:RegisterEvent(eventToRegister) end
					end
				elseif type(registerEvent) == "string" and registerEvent ~= "" then
					extraSoundFrame:RegisterEvent(registerEvent)
				end
			end
		end
	end
end

function addon.Sounds.functions.InitState()
	applyMutedSounds()
	addon.Sounds.functions.UpdateAudioSync()
	if addon.Sounds.functions.UpdateExtraSounds then addon.Sounds.functions.UpdateExtraSounds() end
end
