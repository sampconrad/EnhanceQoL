local addonName, addon = ...

local STAT_TOKEN = "MOVESPEED"
local STAT_TBL = {
	stat = STAT_TOKEN,
	hideAt = 0,
}
addon.MovementSpeedStat = {}

local function targetCategory()
	local categories = PAPERDOLL_STATCATEGORIES
	if not categories then return nil end

	for _, category in ipairs(categories) do
		if category.categoryFrame == "AttributesCategory" then return category end
	end

	return categories[1]
end

local function findStatIndex(category)
	if not (category and category.stats) then return nil end

	for index, entry in ipairs(category.stats) do
		if type(entry) == "table" then
			if entry.stat == STAT_TOKEN then return index end
		elseif entry == STAT_TOKEN then
			return index
		end
	end
end

local function enable()
	local category = targetCategory()
	if not category or not category.stats then return end
	if findStatIndex(category) then return end

	table.insert(category.stats, STAT_TBL)
end

local function disable() addon.variables.requireReload = true end

function addon.MovementSpeedStat.Enable() enable() end

function addon.MovementSpeedStat.Disable() disable() end

function addon.MovementSpeedStat.Refresh()
	if not addon.db then return end
	if addon.db.movementSpeedStatEnabled then enable() end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(_, event, name)
	if event == "PLAYER_LOGIN" then
		addon.MovementSpeedStat.Refresh()
	elseif event == "ADDON_LOADED" and (name == "Blizzard_CharacterUI" or name == "Blizzard_UIPanels_Game") then
		addon.MovementSpeedStat.Refresh()
	end
end)
