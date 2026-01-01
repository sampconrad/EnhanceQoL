local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

if not addon.Sounds or not addon.Sounds.soundFiles then return end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Sound")

local function GetLabel(key) return L[key] or key end

local function IsPureNumbersTable(tbl)
	local hasEntries
	for _, v in pairs(tbl) do
		hasEntries = true
		if type(v) ~= "number" then return false end
	end
	return hasEntries and true or false
end

local function AllChildrenArePureNumbers(tbl)
	local hasEntries
	for _, child in pairs(tbl) do
		hasEntries = true
		if type(child) ~= "table" or not IsPureNumbersTable(child) then return false end
	end
	return hasEntries and true or false
end

local cSound = addon.functions.SettingsCreateCategory(nil, SOUND or SOUND_LABEL or "Sound", nil, "Sound")
addon.SettingsLayout.soundCategory = cSound

addon.functions.SettingsCreateHeadline(cSound, L["soundMuteExplained"])

local headlineCache = {}
local function EnsureHeadlineForPath(path)
	local key = table.concat(path, "/")
	if headlineCache[key] then return end
	headlineCache[key] = true
	local label = GetLabel(path[#path])
	addon.functions.SettingsCreateHeadline(cSound, label)
end

local function SortKeys(keys)
	table.sort(keys, function(a, b)
		local la, lb = GetLabel(a), GetLabel(b)
		if la == lb then return tostring(a) < tostring(b) end
		return la < lb
	end)
end

local function AddSoundOptions(path, data)
	if type(data) ~= "table" then return false end

	if IsPureNumbersTable(data) then
		local varName = "sounds_" .. table.concat(path, "_")
		local label = GetLabel(path[#path])
		local soundList = data
		addon.functions.SettingsCreateCheckbox(cSound, {
			var = varName,
			text = label,
			func = function(value)
				addon.db[varName] = value and true or false
				for _, soundID in ipairs(soundList) do
					if value then
						MuteSoundFile(soundID)
					else
						UnmuteSoundFile(soundID)
					end
				end
			end,
			default = false,
		})
		return true
	end

	if AllChildrenArePureNumbers(data) then
		local keys = {}
		for key in pairs(data) do
			table.insert(keys, key)
		end
		SortKeys(keys)

		if #path == 1 then
			local needHeadline
			for _, key in ipairs(keys) do
				local child = data[key]
				if type(child) == "table" and IsPureNumbersTable(child) then
					needHeadline = true
					break
				end
			end
			if needHeadline then EnsureHeadlineForPath(path) end

			local created = false
			for _, key in ipairs(keys) do
				table.insert(path, key)
				if AddSoundOptions(path, data[key]) then created = true end
				table.remove(path)
			end
			return created
		end

		local created = false
		local groupKey = table.concat(path, "_")
		if #keys > 0 then EnsureHeadlineForPath(path) end
		for _, key in ipairs(keys) do
			local varName = "sounds_" .. groupKey .. "_" .. key
			local label = GetLabel(key)
			local soundList = data[key]

			addon.functions.SettingsCreateCheckbox(cSound, {
				var = varName,
				text = label,
				func = function(value)
					addon.db[varName] = value and true or false
					if type(soundList) == "table" then
						for _, soundID in ipairs(soundList) do
							if value then
								MuteSoundFile(soundID)
							else
								UnmuteSoundFile(soundID)
							end
						end
					end
				end,
				default = false,
			})
			created = true
		end
		return created
	end

	local created = false
	local children = {}
	for key, value in pairs(data) do
		if type(value) == "table" then table.insert(children, key) end
	end
	SortKeys(children)

	for _, key in ipairs(children) do
		table.insert(path, key)
		if AddSoundOptions(path, data[key]) then created = true end
		table.remove(path)
	end
	return created
end

local topKeys = {}
for key in pairs(addon.Sounds.soundFiles) do
	table.insert(topKeys, key)
end
SortKeys(topKeys)

for _, treeKey in ipairs(topKeys) do
	AddSoundOptions({ treeKey }, addon.Sounds.soundFiles[treeKey])
end
