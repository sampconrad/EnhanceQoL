local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Sound")

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

function addon.Sounds.functions.InitState()
	applyMutedSounds()
end
