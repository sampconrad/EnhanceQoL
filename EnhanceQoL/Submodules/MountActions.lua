local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale(parentAddonName)

local MountActions = addon.MountActions or {}
addon.MountActions = MountActions
local issecretvalue = _G.issecretvalue

local RANDOM_FAVORITE_SPELL_ID = 150544
local GHOST_WOLF_SPELL_ID = 2645
local SLOW_FALL_SPELL_ID = 130
local LEVITATE_SPELL_ID = 1706
local DRACTHYR_RACE_TAG = "Dracthyr"
local DRACTHYR_VISAGE_AURA_CHECK_SPELL_ID = 372014
local DRACTHYR_VISAGE_SPELL_ID = 351239
local REPAIR_MOUNT_SPELLS = { 457485, 122708, 61425, 61447 }
local AH_MOUNT_SPELLS = { 264058, 465235 }
local MOUNT_TYPE_CATEGORIES = {
	water = { 231, 254, 232, 407 },
	flying = { 247, 248, 398, 407, 424, 402 },
	ground = { 230, 241, 269, 284, 408, 412, 231 },
}
local MOUNT_TYPE_KNOWN = {}
for _, ids in pairs(MOUNT_TYPE_CATEGORIES) do
	for _, id in ipairs(ids) do
		MOUNT_TYPE_KNOWN[id] = true
	end
end

local function isFlyableArea()
	local isFlyable = _G.IsFlyableArea
	if isFlyable and isFlyable() then return true end
	local isAdvanced = _G.IsAdvancedFlyableArea
	if isAdvanced and isAdvanced() then return true end
	return false
end

local function isSwimming()
	if IsSubmerged and IsSubmerged() then return true end
	if IsSwimming and IsSwimming() then return true end
	return false
end

local function entryMatchesCategory(entry, category)
	if not category then return true end
	if category == "flying" and entry.isSteadyFlight then return true end
	local mountTypeID = entry.mountTypeID
	if not mountTypeID or not MOUNT_TYPE_KNOWN[mountTypeID] then return category == "ground" end
	local ids = MOUNT_TYPE_CATEGORIES[category]
	if not ids then return false end
	for i = 1, #ids do
		if ids[i] == mountTypeID then return true end
	end
	return false
end

local function isEntryUsable(entry)
	if not entry or not entry.mountID then return false end
	if C_MountJournal and C_MountJournal.GetMountUsabilityByID then
		local usable = C_MountJournal.GetMountUsabilityByID(entry.mountID, true)
		if usable ~= nil then return usable == true end
	end
	return entry.isUsable == true
end

local function pickRandomMount(entries, category)
	local count = 0
	local chosen
	for i = 1, #entries do
		local entry = entries[i]
		if entryMatchesCategory(entry, category) and isEntryUsable(entry) then
			count = count + 1
			if math.random(count) == 1 then chosen = entry.spellID end
		end
	end
	return chosen
end

_G["BINDING_NAME_CLICK EQOLRandomMountButton:LeftButton"] = L["Random Mount"] or "Random Mount"
_G["BINDING_NAME_CLICK EQOLRepairMountButton:LeftButton"] = L["Repair Mount"] or "Repair Mount"
_G["BINDING_NAME_CLICK EQOLAuctionMountButton:LeftButton"] = L["Auction House Mount"] or "Auction House Mount"

local function getMountIdFromSource(sourceID)
	if not sourceID then return nil, nil end
	if C_MountJournal then
		if C_MountJournal.GetMountFromSpell then
			local mountID = C_MountJournal.GetMountFromSpell(sourceID)
			if mountID then return mountID, "spell" end
		end
		if C_MountJournal.GetMountFromItem then
			local mountID = C_MountJournal.GetMountFromItem(sourceID)
			if mountID then return mountID, "item" end
		end
	end
	return nil, nil
end

local function isMountSpellUsable(spellID)
	if not spellID then return false end
	local mountID = getMountIdFromSource(spellID)
	if not mountID then return false end
	local _, _, _, _, isUsable, _, _, _, _, shouldHideOnChar, isCollected = C_MountJournal.GetMountInfoByID(mountID)
	if not isCollected or shouldHideOnChar then return false end
	if C_MountJournal.GetMountUsabilityByID then
		local usable = C_MountJournal.GetMountUsabilityByID(mountID, true)
		if usable ~= nil then isUsable = usable end
	end
	return isUsable == true
end

local function pickFirstUsable(spellList)
	for _, spellID in ipairs(spellList) do
		if isMountSpellUsable(spellID) then return spellID end
	end
	return nil
end

local function getMountedTargetSpellID()
	if not UnitExists("target") then return nil end
	if not C_MountJournal or not C_MountJournal.GetMountFromSpell then return nil end
	if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return nil end

	if C_UnitAuras and C_UnitAuras.GetUnitAuras then
		local auras = C_UnitAuras.GetUnitAuras("target", "HELPFUL")
		if type(auras) == "table" then
			for i = 1, #auras do
				local aura = auras[i]
				local spellID = aura and aura.spellId
				if issecretvalue and issecretvalue(spellID) then spellID = nil end
				if spellID and C_MountJournal.GetMountFromSpell(spellID) then return spellID end
			end
		end
	end

	return nil
end

local function getSourceName(sourceID)
	local name
	if C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(sourceID) end
	if not name and GetSpellInfo then name = GetSpellInfo(sourceID) end
	if not name and C_Item and C_Item.GetItemNameByID then name = C_Item.GetItemNameByID(sourceID) end
	if not name and GetItemInfo then name = GetItemInfo(sourceID) end
	return name
end

local function getSpellNameByID(spellID)
	if not spellID then return nil end
	local name
	if C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(spellID) end
	if not name and GetSpellInfo then name = GetSpellInfo(spellID) end
	return name
end

local function isSpellKnown(spellID)
	if not spellID then return false end
	if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(spellID) == true end
	if IsSpellKnown then return IsSpellKnown(spellID) == true end
	return false
end

local function getFallingSafetySpellID()
	if not addon.db or addon.db.randomMountCastSlowFallWhenFalling ~= true then return nil end
	if not (IsFalling and IsFalling()) then return nil end

	local classTag = (addon.variables and addon.variables.unitClass) or select(2, UnitClass("player"))
	if classTag == "PRIEST" and isSpellKnown(LEVITATE_SPELL_ID) then return LEVITATE_SPELL_ID end
	if classTag == "MAGE" and isSpellKnown(SLOW_FALL_SPELL_ID) then return SLOW_FALL_SPELL_ID end
	return nil
end

local function getFallingSafetyMacro()
	local spellID = getFallingSafetySpellID()
	if not spellID then return nil end
	local name = getSpellNameByID(spellID)
	if not name or name == "" then return nil end
	return "/cast [@player] " .. name
end

local function shouldUseDracthyrVisageBeforeMount()
	if not addon.db or addon.db.randomMountDracthyrVisageBeforeMount ~= true then return false end
	local raceTag = (addon.variables and addon.variables.unitRace) or select(2, UnitRace("player"))
	if raceTag ~= DRACTHYR_RACE_TAG then return false end
	if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return false end
	local aura = C_UnitAuras.GetPlayerAuraBySpellID(DRACTHYR_VISAGE_AURA_CHECK_SPELL_ID)
	return aura == nil
end

local function getDracthyrVisageMacroLine()
	if not shouldUseDracthyrVisageBeforeMount() then return nil end
	local spellName = getSpellNameByID(DRACTHYR_VISAGE_SPELL_ID)
	if not spellName or spellName == "" then return nil end
	return "/cast " .. spellName
end

local function getDruidMoveFormMacro()
	local travelName = getSpellNameByID(783)
	local catName = getSpellNameByID(768)
	if not travelName and not catName then return nil end
	local travel = travelName or catName
	local cat = catName or travelName or ""
	if cat == "" then cat = travel end
	return "/cancelform\n/cast [swimming][outdoors] " .. travel .. "; [indoors] " .. cat .. "; " .. cat
end

local function getShamanGhostWolfMacro()
	local ghostName = getSpellNameByID(GHOST_WOLF_SPELL_ID)
	if not ghostName or ghostName == "" then return nil end
	return "/cancelform\n/cast " .. ghostName
end

local function buildMountMacro(spellID)
	local name = getSpellNameByID(spellID)
	if not name or name == "" then return nil end
	local lines = {}
	if addon.variables.unitClass == "DRUID" then lines[#lines + 1] = "/cancelform" end
	local visageLine = getDracthyrVisageMacroLine()
	if visageLine then lines[#lines + 1] = visageLine end
	lines[#lines + 1] = "/cast " .. name
	return table.concat(lines, "\n")
end

local function getMountDebugInfo(spellID)
	local sourceName = getSourceName(spellID)
	local mountID, sourceType = getMountIdFromSource(spellID)
	local mountName, isCollected, isUsable, isHidden
	if mountID and C_MountJournal and C_MountJournal.GetMountInfoByID then
		local name, _, _, _, usable, _, _, _, _, shouldHideOnChar, collected = C_MountJournal.GetMountInfoByID(mountID)
		mountName = name
		isCollected = collected
		isHidden = shouldHideOnChar
		isUsable = usable
		if C_MountJournal.GetMountUsabilityByID then
			local usableByID = C_MountJournal.GetMountUsabilityByID(mountID, true)
			if usableByID ~= nil then isUsable = usableByID end
		end
	end
	return sourceName, mountID, mountName, isCollected, isUsable, isHidden, sourceType
end

local function summonMountBySource(sourceID)
	if not sourceID then return false end
	if C_MountJournal and C_MountJournal.SummonByID then
		local mountID = getMountIdFromSource(sourceID)
		if mountID then
			C_MountJournal.SummonByID(mountID)
			return true
		end
	end
	if CastSpellByID then
		CastSpellByID(sourceID)
		return true
	end
	return false
end

function MountActions:IsRandomAllEnabled() return addon.db and addon.db.randomMountUseAll == true end

function MountActions:MarkRandomCacheDirty() self.randomMountDirty = true end

function MountActions:BuildRandomMountCache(useAll)
	local list = {}
	if not C_MountJournal or not C_MountJournal.GetMountIDs then return list end
	local mountIDs = C_MountJournal.GetMountIDs()
	if type(mountIDs) ~= "table" then return list end
	for _, mountID in ipairs(mountIDs) do
		local _, spellID, _, _, isUsable, _, isFavorite, _, _, shouldHideOnChar, isCollected, _, isSteadyFlight = C_MountJournal.GetMountInfoByID(mountID)
		if isCollected and not shouldHideOnChar and spellID and (useAll or isFavorite) then
			local _, _, _, _, mountTypeID = C_MountJournal.GetMountInfoExtraByID(mountID)
			list[#list + 1] = {
				mountID = mountID,
				spellID = spellID,
				mountTypeID = mountTypeID,
				isSteadyFlight = isSteadyFlight == true,
				isUsable = isUsable == true,
			}
		end
	end
	return list
end

function MountActions:GetRandomMountSpell()
	local useAll = self:IsRandomAllEnabled()
	local cacheMode = useAll and "all" or "favorites"
	if self.randomMountDirty or not self.randomMountCache or self.randomMountCacheMode ~= cacheMode then
		self.randomMountCache = self:BuildRandomMountCache(useAll)
		self.randomMountCacheMode = cacheMode
		self.randomMountDirty = false
	end
	local list = self.randomMountCache
	if not list or #list == 0 then return nil end
	local spellID
	if isSwimming() then
		spellID = pickRandomMount(list, "water")
		if not spellID and isFlyableArea() then spellID = pickRandomMount(list, "flying") end
		if not spellID then spellID = pickRandomMount(list, "ground") end
	elseif isFlyableArea() then
		spellID = pickRandomMount(list, "flying")
		if not spellID then spellID = pickRandomMount(list, "ground") end
	else
		spellID = pickRandomMount(list, "ground")
	end
	if not spellID then spellID = pickRandomMount(list) end
	return spellID
end

function MountActions:PrepareActionButton(btn)
	if InCombatLockdown and InCombatLockdown() then return end
	if not btn or not btn._eqolAction then return end
	btn:SetAttribute("type1", "macro")
	btn:SetAttribute("type", "macro")
	if btn._eqolAction == "random" and addon.variables.unitClass == "DRUID" and IsMounted and IsMounted() and IsPlayerMoving() and (C_SpellBook.IsSpellKnown(783) or C_SpellBook.IsSpellKnown(768)) then
		if not (IsFlying and IsFlying()) then
			if not (addon.db and addon.db.randomMountDruidNoShiftWhileMounted) then
				local macro = getDruidMoveFormMacro()
				if macro then
					btn:SetAttribute("macrotext1", macro)
					btn:SetAttribute("macrotext", macro)
					return
				end
			end
		end
	end
	if btn._eqolAction == "random" and addon.variables.unitClass == "SHAMAN" and IsMounted and IsMounted() and IsPlayerMoving() and C_SpellBook.IsSpellKnown(GHOST_WOLF_SPELL_ID) then
		if not (IsFlying and IsFlying()) then
			local macro = getShamanGhostWolfMacro()
			if macro then
				btn:SetAttribute("macrotext1", macro)
				btn:SetAttribute("macrotext", macro)
				return
			end
		end
	end
	if IsMounted and IsMounted() then
		btn:SetAttribute("macrotext1", "/dismount")
		btn:SetAttribute("macrotext", "/dismount")
		return
	end

	local fallingMacro = getFallingSafetyMacro()
	if fallingMacro then
		btn:SetAttribute("macrotext1", fallingMacro)
		btn:SetAttribute("macrotext", fallingMacro)
		return
	end

	if btn._eqolAction == "random" then
		if addon.variables.unitClass == "SHAMAN" and IsPlayerMoving() and C_SpellBook.IsSpellKnown(GHOST_WOLF_SPELL_ID) then
			local macro = getShamanGhostWolfMacro()
			if macro then
				btn:SetAttribute("macrotext1", macro)
				btn:SetAttribute("macrotext", macro)
				return
			end
		end
		if addon.variables.unitClass == "DRUID" and IsPlayerMoving() and (C_SpellBook.IsSpellKnown(783) or C_SpellBook.IsSpellKnown(768)) then
			local macro = getDruidMoveFormMacro()
			if macro then
				btn:SetAttribute("macrotext1", macro)
				btn:SetAttribute("macrotext", macro)
				return
			end
		end
		local spellID
		local targetSpellID = getMountedTargetSpellID()
		if targetSpellID and isMountSpellUsable(targetSpellID) then
			spellID = targetSpellID
		else
			spellID = self:GetRandomMountSpell()
		end
		local macro = buildMountMacro(spellID or RANDOM_FAVORITE_SPELL_ID)
		btn:SetAttribute("macrotext1", macro)
		btn:SetAttribute("macrotext", macro)
	elseif btn._eqolAction == "repair" then
		local spellID = pickFirstUsable(REPAIR_MOUNT_SPELLS)
		local macro = buildMountMacro(spellID)
		btn:SetAttribute("macrotext1", macro)
		btn:SetAttribute("macrotext", macro)
	elseif btn._eqolAction == "ah" then
		local spellID = pickFirstUsable(AH_MOUNT_SPELLS)
		local macro = buildMountMacro(spellID)
		btn:SetAttribute("macrotext1", macro)
		btn:SetAttribute("macrotext", macro)
	end
end

function MountActions:HandleClick(btn, button, down)
	if button and button ~= "LeftButton" then return end
	if down == false then return end
	if InCombatLockdown and InCombatLockdown() then return end
	if not btn or not btn._eqolAction then return end

	if btn._eqolAction == "random" then
		if IsMounted and IsMounted() then
			if C_MountJournal and C_MountJournal.Dismiss then
				C_MountJournal.Dismiss()
			elseif Dismount then
				Dismount()
			end
			return
		end
		local targetSpellID = getMountedTargetSpellID()
		if targetSpellID and isMountSpellUsable(targetSpellID) then
			summonMountBySource(targetSpellID)
			return
		end
		local spellID = self:GetRandomMountSpell()
		if spellID then
			summonMountBySource(spellID)
		else
			summonMountBySource(RANDOM_FAVORITE_SPELL_ID)
		end
	elseif btn._eqolAction == "repair" then
		local spellID = pickFirstUsable(REPAIR_MOUNT_SPELLS)
		if spellID then summonMountBySource(spellID) end
	elseif btn._eqolAction == "ah" then
		local spellID = pickFirstUsable(AH_MOUNT_SPELLS)
		if spellID then summonMountBySource(spellID) end
	end
end

function MountActions:EnsureButton(name, action)
	local btn = _G[name]
	if not btn then btn = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate") end
	btn:RegisterForClicks("AnyDown")
	btn:SetAttribute("type1", "macro")
	btn:SetAttribute("type", "macro")
	-- Force the action to trigger on key down regardless of ActionButtonUseKeyDown.
	btn:SetAttribute("pressAndHoldAction", true)
	btn._eqolAction = action
	if action == "random" then
		local macro = buildMountMacro(RANDOM_FAVORITE_SPELL_ID)
		btn:SetAttribute("macrotext1", macro)
		btn:SetAttribute("macrotext", macro)
	end
	btn:SetScript("PreClick", function(self) MountActions:PrepareActionButton(self) end)
	return btn
end

function MountActions:Init()
	if self.initialized then return end
	self.initialized = true
	self:MarkRandomCacheDirty()
	self:EnsureButton("EQOLRandomMountButton", "random")
	self:EnsureButton("EQOLRepairMountButton", "repair")
	self:EnsureButton("EQOLAuctionMountButton", "ah")
end

local function handleMountEvents() MountActions:MarkRandomCacheDirty() end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("MOUNT_JOURNAL_SEARCH_UPDATED")
eventFrame:RegisterEvent("MOUNT_JOURNAL_USABILITY_CHANGED")
eventFrame:RegisterEvent("COMPANION_LEARNED")
eventFrame:RegisterEvent("COMPANION_UNLEARNED")
eventFrame:RegisterEvent("COMPANION_UPDATE")
eventFrame:SetScript("OnEvent", handleMountEvents)

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function() MountActions:Init() end)
