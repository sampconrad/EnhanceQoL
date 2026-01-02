local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_SharedMedia")

addon.SharedMedia = addon.SharedMedia or {}
addon.SharedMedia.functions = addon.SharedMedia.functions or {}

local cSharedMedia = addon.SettingsLayout.rootSYSTEM
addon.SettingsLayout.sharedMediaCategory = cSharedMedia

local sharedMediaExpandable = addon.functions.SettingsCreateExpandableSection(cSharedMedia, {
	name = L["SharedMedia"],
	expanded = false,
	colorizeTitle = false,
})

local function CreateButton(data)
	data.parentSection = sharedMediaExpandable
	return addon.functions.SettingsCreateButton(cSharedMedia, data)
end

local function CreateCheckbox(data)
	data.parentSection = sharedMediaExpandable
	return addon.functions.SettingsCreateCheckbox(cSharedMedia, data)
end

local soundSettings = {}
local bulkUpdate = false

local function ToggleSound(sound, value)
	addon.SharedMedia.functions.UpdateSound(sound.key, value and true or false)
	if value and not bulkUpdate and sound.path then PlaySoundFile(sound.path, "Master") end
end

local function SetAllSounds(state)
	bulkUpdate = true
	for _, setting in pairs(soundSettings) do
		if setting and setting.SetValue then setting:SetValue(state and true or false) end
	end
	bulkUpdate = false
end

CreateButton({
	var = "SharedMediaEnableAll",
	text = L["Enable All"],
	func = function() SetAllSounds(true) end,
})

CreateButton({
	var = "SharedMediaDisableAll",
	text = L["Disable All"],
	func = function() SetAllSounds(false) end,
})

local function SanitizeVar(key) return (tostring(key):gsub("[^%w_]", "_")) end

for _, sound in ipairs(addon.SharedMedia.sounds or {}) do
	local entry = CreateCheckbox({
		var = "SharedMediaSound_" .. SanitizeVar(sound.key),
		text = sound.label,
		get = function() return addon.db.sharedMediaSounds[sound.key] and true or false end,
		func = function(value) ToggleSound(sound, value) end,
		default = false,
	})
	if entry and entry.setting then soundSettings[sound.key] = entry.setting end
end
