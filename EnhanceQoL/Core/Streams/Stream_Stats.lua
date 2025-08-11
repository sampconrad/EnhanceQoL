-- luacheck: globals EnhanceQoL GAMEMENU_OPTIONS
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream
local provider

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.stats = addon.db.datapanel.stats or {}
	db = addon.db.datapanel.stats
	db.prefix = db.prefix or ""
	db.fontSize = db.fontSize or 14
	db.hideIcon = db.hideIcon or false
end
local function RestorePosition(frame)
	if db.point and db.x and db.y then
		frame:ClearAllPoints()
		frame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
	end
end

local aceWindow
local function createAceWindow()
	if aceWindow then
		aceWindow:Show()
		return
	end
	ensureDB()
	local frame = AceGUI:Create("Window")
	aceWindow = frame.frame
	frame:SetTitle(GAMEMENU_OPTIONS)
	frame:SetWidth(300)
	frame:SetHeight(200)
	frame:SetLayout("List")

	frame.frame:SetScript("OnShow", function(self) RestorePosition(self) end)
	frame.frame:SetScript("OnHide", function(self)
		local point, _, _, xOfs, yOfs = self:GetPoint()
		db.point = point
		db.x = xOfs
		db.y = yOfs
	end)

	local prefix = AceGUI:Create("EditBox")
	prefix:SetLabel("Prefix")
	prefix:SetText(db.prefix)
	prefix:SetCallback("OnEnterPressed", function(_, _, val)
		db.prefix = val or ""
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(prefix)

	local fontSize = AceGUI:Create("Slider")
	fontSize:SetLabel("Font size")
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(fontSize)

	local hide = AceGUI:Create("CheckBox")
	hide:SetLabel("Hide icon")
	hide:SetValue(db.hideIcon)
	hide:SetCallback("OnValueChanged", function(_, _, val)
		db.hideIcon = val and true or false
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(hide)

	frame.frame:Show()
end

local function GetConfigName(configID)
	if configID then
		if type(configID) == "number" then
			local info = C_Traits.GetConfigInfo(configID)
			if info then return info.name end
		end
	end
	return "Unknown"
end

local f = CreateFrame("Frame")
local pending

local function Recalc()
	pending = nil
	-- Lies deine Werte JETZT aus (Beispiele):
	local haste = GetHaste()
	local hasteRating = GetCombatRating(CR_HASTE_MELEE)
	local mastery = GetMastery()
	local masteryRating = GetCombatRating(CR_MASTERY)

	local crit = GetCritChance()
	local critRating = GetCombatRating(CR_CRIT_MELEE)

	local versatility = GetCombatRating(CR_VERSATILITY_DAMAGE_DONE)
	local versatilityDamageBonus = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) + GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE)
	local versatilityDamageTakenReduction = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_TAKEN) + GetVersatilityBonus(CR_VERSATILITY_DAMAGE_TAKEN)

	print("Vers: " .. string.format("%.2f", versatilityDamageBonus) .. "% / " .. string.format("%.2f", versatilityDamageTakenReduction) .. "%")

	-- print(("Haste %.1f  Mastery %.1f  Crit %.1f  Vers %.1f"):format(haste, mastery, crit, vers))
end

local function Schedule()
	if pending then return end
	pending = true
	C_Timer.After(0.05, Recalc) -- bündelt Event-Stürme
end

-- Unit-gebundene Events:
f:RegisterUnitEvent("UNIT_SPELL_HASTE", "player")
f:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
f:RegisterUnitEvent("UNIT_STATS", "player")
f:RegisterUnitEvent("UNIT_AURA", "player")

-- Globale Events:
f:RegisterEvent("COMBAT_RATING_UPDATE")
f:RegisterEvent("MASTERY_UPDATE")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("PLAYER_TALENT_UPDATE")
f:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
f:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
f:RegisterEvent("PLAYER_ENTERING_WORLD")

f:SetScript("OnEvent", Schedule)

provider = {
	id = "talent",
	version = 1,
	title = TALENTS,
	update = GetCurrentTalents,
	events = {
		PLAYER_LOGIN = function(stream)
			C_Timer.After(1, function() addon.DataHub:RequestUpdate(stream) end)
		end,
		TRAIT_CONFIG_CREATED = function(stream) addon.DataHub:RequestUpdate(stream) end,
		TRAIT_CONFIG_DELETED = function(stream) addon.DataHub:RequestUpdate(stream) end,
		TRAIT_CONFIG_UPDATED = function(stream)
			C_Timer.After(0.02, function() addon.DataHub:RequestUpdate(stream) end)
		end,
		ZONE_CHANGED_NEW_AREA = function(stream) addon.DataHub:RequestUpdate(stream) end,
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
