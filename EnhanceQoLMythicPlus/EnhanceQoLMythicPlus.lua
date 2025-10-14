local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_MythicPlus")
local LSM = LibStub("LibSharedMedia-3.0")

local frameLoad = CreateFrame("Frame")

local brButton
local defaultButtonSize = 60
local defaultFontSize = 16

local function removeBRFrame()
	if brButton then
		brButton:Hide()
		brButton:SetParent(nil)
		brButton:SetScript("OnClick", nil)
		brButton:SetScript("OnEnter", nil)
		brButton:SetScript("OnLeave", nil)
		brButton:SetScript("OnUpdate", nil)
		brButton:SetScript("OnEvent", nil)
		brButton:SetScript("OnDragStart", nil)
		brButton:SetScript("OnDragStop", nil)
		brButton:UnregisterAllEvents()
		brButton:ClearAllPoints()
		brButton = nil
	end
end

local function isRaidDifficulty(d) return d == 14 or d == 15 or d == 16 or d == 17 end

local function shouldShowBRTracker()
	if not addon.db["mythicPlusBRTrackerEnabled"] then return false end
	if not IsInInstance() then return false end
	local _, _, diff = GetInstanceInfo()
	if diff == 8 then return true end
	if isRaidDifficulty(diff) then return IsEncounterInProgress() end
	return false
end

local function createBRFrame()
	removeBRFrame()
	if not addon.db["mythicPlusBRTrackerEnabled"] then return end
	if IsInGroup() and shouldShowBRTracker() then
		brButton = CreateFrame("Button", nil, UIParent)
		brButton:SetSize(addon.db["mythicPlusBRButtonSize"], addon.db["mythicPlusBRButtonSize"])
		brButton:SetPoint(addon.db["mythicPlusBRTrackerPoint"], UIParent, addon.db["mythicPlusBRTrackerPoint"], addon.db["mythicPlusBRTrackerX"], addon.db["mythicPlusBRTrackerY"])

		if addon.db["mythicPlusBRTrackerLocked"] == false then
			brButton:SetMovable(true)
			brButton:EnableMouse(true)
			brButton:RegisterForDrag("LeftButton")

			brButton:SetScript("OnDragStart", brButton.StartMoving)
			brButton:SetScript("OnDragStop", function(self)
				self:StopMovingOrSizing()
				local point, _, _, xOfs, yOfs = self:GetPoint()
				addon.db["mythicPlusBRTrackerPoint"] = point
				addon.db["mythicPlusBRTrackerX"] = xOfs
				addon.db["mythicPlusBRTrackerY"] = yOfs
			end)
		end

		local bg = brButton:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(brButton)
		bg:SetColorTexture(0, 0, 0, 0.8)

		local icon = brButton:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints(brButton)
		icon:SetTexture(136080)
		brButton.icon = icon

		local scaleFactor = addon.db["mythicPlusBRButtonSize"] / defaultButtonSize
		local newFontSize = math.floor(defaultFontSize * scaleFactor + 0.5)

		brButton.cooldownFrame = CreateFrame("Cooldown", nil, brButton, "CooldownFrameTemplate")
		brButton.cooldownFrame:SetAllPoints(brButton)
		brButton.cooldownFrame.cooldownSet = false
		brButton.cooldownFrame:SetSwipeColor(0, 0, 0, 0.3)
		brButton.cooldownFrame:SetCountdownAbbrevThreshold(600)
		brButton.cooldownFrame:SetScale(scaleFactor)
		brButton.cooldownFrame:SetDrawEdge(false)

		brButton.charges = brButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		brButton.charges:SetPoint("BOTTOMRIGHT", brButton, "BOTTOMRIGHT", -3, 3)
		brButton.charges:SetFont(addon.variables.defaultFont, newFontSize, "OUTLINE")
	end
end

local function setBRInfo(info)
	if brButton and brButton.cooldownFrame and info then
		local current = info.currentCharges
		local max = info.maxCharges

		if current < max then
			if brButton.cooldownFrame.charges ~= current or brButton.cooldownFrame.startTime ~= info.cooldownStartTime then
				brButton.cooldownFrame:SetCooldown(info.cooldownStartTime, info.cooldownDuration, info.chargeModRate)
				brButton.cooldownFrame.startTime = info.cooldownStartTime
				brButton.cooldownFrame.charges = current

				if current > 0 then
					brButton.charges:SetTextColor(0, 1, 0)
					brButton.icon:SetDesaturated(false)
					brButton.cooldownFrame:SetSwipeColor(0, 0, 0, 0.3)
					brButton.charges:Show()
				else
					brButton.cooldownFrame:SetSwipeColor(0, 0, 0, 1)
					brButton.icon:SetDesaturated(true)
					brButton.charges:SetTextColor(1, 0, 0)
					brButton.charges:Hide()
				end
			end
		else
			brButton.cooldownFrame:Clear()
			brButton.charges:SetTextColor(0, 1, 0)
		end
		brButton.charges:SetText(current)
	end
end

hooksecurefunc(ScenarioObjectiveTracker.ChallengeModeBlock, "UpdateTime", function(self, elapsedTime)
	if addon.db["mythicPlusBRTrackerEnabled"] then
		if not brButton or not brButton.cooldownFrame or not brButton.cooldownFrame.cooldownSet then
			createBRFrame()
			if brButton and brButton.cooldownFrame then
				brButton.cooldownFrame.cooldownSet = true
				local info = C_Spell.GetSpellCharges(20484)
				setBRInfo(info)
			end
		end
	end

	if not addon.db["enableKeystoneHelper"] or not addon.db["mythicPlusShowChestTimers"] then return end

	-- Always show chest timers in challenge mode
	local timeLeft = math.max(0, self.timeLimit - elapsedTime)
	local chest3Time = self.timeLimit * 0.4
	local chest2Time = self.timeLimit * 0.2

	if not self.CustomTextAdded then
		self.ChestTimeText2 = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		self.ChestTimeText2:SetPoint("TOPLEFT", self.TimeLeft, "TOPRIGHT", 3, 2)
		self.ChestTimeText3 = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		self.ChestTimeText3:SetPoint("BOTTOMLEFT", self.TimeLeft, "BOTTOMRIGHT", 3, 0)
		self.CustomTextAdded = true
	end

	if timeLeft > 0 then
		local chestText3 = ""
		local chestText2 = ""

		if timeLeft >= chest3Time then chestText3 = string.format("+3: %s", SecondsToClock(timeLeft - chest3Time)) end
		if timeLeft >= chest2Time then chestText2 = string.format("+2: %s", SecondsToClock(timeLeft - chest2Time)) end

		self.ChestTimeText2:SetText(chestText2)
		self.ChestTimeText3:SetText(chestText3)
	else
		self.ChestTimeText2:SetText("")
		self.ChestTimeText3:SetText("")
	end
end)

local function GetScenarioPercent(criteriaIndex)
	local criteriaInfo = C_ScenarioInfo.GetCriteriaInfo(criteriaIndex)
	if criteriaInfo and criteriaInfo.isWeightedProgress then
		local sValue = criteriaInfo.quantity
		if criteriaInfo.quantityString then
			sValue = tonumber(string.sub(criteriaInfo.quantityString, 1, string.len(criteriaInfo.quantityString) - 1)) / criteriaInfo.totalQuantity * 100
			sValue = math.floor(sValue * 100 + 0.5) / 100
		end
		return sValue
	end
	return nil
end

hooksecurefunc(ScenarioTrackerProgressBarMixin, "SetValue", function(self, percentage)
	-- Always show decimal progress for enemy forces in M+
	if not IsInInstance() or not self:IsVisible() then return end
	local _, _, diff = GetInstanceInfo()
	if diff ~= 8 then return end -- only in mythic challenge mode
	local sData = C_ScenarioInfo.GetScenarioStepInfo()
	if nil == sData then return end

	local truePercent
	if self.criteriaIndex then self.criteriaIndex = nil end
	for criteriaIndex = 1, sData.numCriteria do
		if nil == truePercent then
			truePercent = GetScenarioPercent(criteriaIndex)
			if truePercent then
				self.Bar.Label:SetFormattedText(truePercent .. "%%")
				self.percentage = percentage
			end
		end
	end
end)

local function createButtons()
	-- Always use improved Keystone Helper UI
	addon.MythicPlus.functions.addRCButton()
	addon.MythicPlus.functions.addPullButton()
end

local function checkKeyStone()
	addon.MythicPlus.variables.handled = false -- reset handle on Keystoneframe open
	addon.MythicPlus.functions.removeExistingButton()
	if not addon.db["enableKeystoneHelper"] then return end
	local GetContainerNumSlots = C_Container.GetContainerNumSlots
	local GetContainerItemID = C_Container.GetContainerItemID
	local UseContainerItem = C_Container.UseContainerItem
	local GetContainerItemInfo = C_Container.GetContainerItemInfo

	local kId = C_MythicPlus.GetOwnedKeystoneMapID()
	local mapId = select(8, GetInstanceInfo())
	if nil ~= kId and mapId == kId then
		for container = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
			for slot = 1, GetContainerNumSlots(container) do
				local id = GetContainerItemID(container, slot)
				if id == 180653 then
					-- Button for ReadyCheck and Pulltimer
					if UnitInParty("player") and UnitIsGroupLeader("player") then createButtons() end

					if addon.db["autoInsertKeystone"] and addon.db["autoInsertKeystone"] == true then
						UseContainerItem(container, slot)
						if addon.db["closeBagsOnKeyInsert"] and addon.db["closeBagsOnKeyInsert"] == true then CloseAllBags() end
					end
					break
				end
			end
		end
	end
end

-- Registriere das Event
frameLoad:RegisterEvent("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN")
frameLoad:RegisterEvent("READY_CHECK_FINISHED")
frameLoad:RegisterEvent("LFG_ROLE_CHECK_SHOW")
frameLoad:RegisterEvent("RAID_TARGET_UPDATE")
frameLoad:RegisterEvent("PLAYER_ROLES_ASSIGNED")
frameLoad:RegisterEvent("READY_CHECK")
frameLoad:RegisterEvent("GROUP_ROSTER_UPDATE")
frameLoad:RegisterEvent("SPELL_UPDATE_CHARGES")
frameLoad:RegisterEvent("ENCOUNTER_END")
frameLoad:RegisterEvent("ENCOUNTER_START")

local function setActTank()
	if UnitGroupRolesAssigned("player") == "TANK" then
		addon.MythicPlus.actTank = "player"
		return
	end
	for i = 1, 4 do
		local unit = "party" .. i
		if UnitGroupRolesAssigned(unit) == "TANK" then
			addon.MythicPlus.actTank = unit
			return
		end
	end
	addon.MythicPlus.actTank = nil
end

local function setActHealer()
	if UnitGroupRolesAssigned("player") == "HEALER" then
		addon.MythicPlus.actHealer = "player"
		return
	end
	for i = 1, 4 do
		local unit = "party" .. i
		if UnitGroupRolesAssigned(unit) == "HEALER" then
			addon.MythicPlus.actHealer = unit
			return
		end
	end
	addon.MythicPlus.actHealer = nil
end

local function checkRaidMarker()
	if addon.db["autoMarkTankInDungeon"] then
		if nil == addon.MythicPlus.actTank then setActTank() end
		if nil ~= addon.MythicPlus.actTank and UnitInParty(addon.MythicPlus.actTank) then
			local rIndex = GetRaidTargetIndex(addon.MythicPlus.actTank)
			if rIndex == nil or rIndex ~= addon.db["autoMarkTankInDungeonMarker"] and (UnitGroupRolesAssigned("player") == "TANK" or UnitIsGroupLeader("player")) then
				SetRaidTarget(addon.MythicPlus.actTank, addon.db["autoMarkTankInDungeonMarker"])
			end
		end
	end

	if addon.db["autoMarkHealerInDungeon"] then
		if nil == addon.MythicPlus.actHealer then setActHealer() end
		if nil ~= addon.MythicPlus.actHealer and UnitInParty(addon.MythicPlus.actHealer) then
			if addon.MythicPlus.actHealer == "player" and addon.db["mythicPlusNoHealerMark"] then return end
			local rIndex = GetRaidTargetIndex(addon.MythicPlus.actHealer)
			if rIndex == nil or rIndex ~= addon.db["autoMarkHealerInDungeonMarker"] and (UnitGroupRolesAssigned("player") == "HEALER" or UnitIsGroupLeader("player")) then
				SetRaidTarget(addon.MythicPlus.actHealer, addon.db["autoMarkHealerInDungeonMarker"])
			end
		end
	end
end

local function checkCondition()
	if addon.db["mythicPlusNoHealerMark"] and UnitInParty("player") and UnitGroupRolesAssigned("player") == "HEALER" then
		local rIndex = GetRaidTargetIndex("player")
		if nil ~= rIndex then SetRaidTarget("player", 0) end
	end

	if addon.db["autoMarkTankInDungeon"] or addon.db["autoMarkHealerInDungeon"] then
		local _, _, difficultyID, difficultyName = GetInstanceInfo()
		if difficultyID == 1 and addon.db["mythicPlusIgnoreNormal"] then return false end
		if difficultyID == 2 and addon.db["mythicPlusIgnoreHeroic"] then return false end
		if difficultyID == 19 and addon.db["mythicPlusIgnoreEvent"] then return false end
		if (difficultyID == 23 or difficultyID == 150) and addon.db["mythicPlusIgnoreMythic"] then return false end
		if difficultyID == 24 and addon.db["mythicPlusIgnoreTimewalking"] then return false end
		if UnitInParty("player") and not UnitInRaid("player") and select(1, IsInInstance()) == true then return true end
	end
	return false
end

-- Funktion zum Umgang mit Events
local function eventHandler(self, event, arg1, arg2, arg3, arg4)
	if event == "ADDON_LOADED" and arg1 == addonName then
		-- loadMain()
	elseif event == "CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN" then
		if InCombatLockdown() then return end
		if addon.db["enableKeystoneHelper"] then checkKeyStone() end
	elseif event == "READY_CHECK_FINISHED" and ChallengesKeystoneFrame and addon.MythicPlus.Buttons["ReadyCheck"] then
		addon.MythicPlus.Buttons["ReadyCheck"]:SetText(L["ReadyCheck"])
	elseif event == "RAID_TARGET_UPDATE" and checkCondition() then
		C_Timer.After(0.5, function() checkRaidMarker() end)
	elseif event == "PLAYER_ROLES_ASSIGNED" and checkCondition() then
		setActTank()
		setActHealer()
		checkRaidMarker()
	elseif event == "GROUP_ROSTER_UPDATE" and checkCondition() then
		setActTank()
		setActHealer()
		checkRaidMarker()
	elseif event == "READY_CHECK" and checkCondition() then
		setActTank()
		setActHealer()
		checkRaidMarker()
	elseif event == "SPELL_UPDATE_CHARGES" then
		if shouldShowBRTracker() then
			if not brButton or not brButton.cooldownFrame then createBRFrame() end
			local info = C_Spell.GetSpellCharges(20484)
			setBRInfo(info)
		else
			removeBRFrame()
		end
	elseif event == "ENCOUNTER_START" then
		local _, _, diff = GetInstanceInfo()
		if isRaidDifficulty(diff) and shouldShowBRTracker() then
			if not brButton or not brButton.cooldownFrame then createBRFrame() end
			local info = C_Spell.GetSpellCharges(20484)
			setBRInfo(info)
		end
	elseif event == "ENCOUNTER_END" then
		-- In raids we hide after encounter; in M+ we keep showing
		if not shouldShowBRTracker() then removeBRFrame() end
	end
end

-- Setze den Event-Handler
frameLoad:SetScript("OnEvent", eventHandler)

local function addPotionTrackerFrame(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "List")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)
	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)
	groupCore:SetTitle(L["potionTrackerHeadline"])

	local cbPotionTrackerEnabled = addon.functions.createCheckboxAce(L["potionTracker"], addon.db["potionTracker"], function(self, _, value)
		addon.db["potionTracker"] = value
		container:ReleaseChildren()
		addPotionTrackerFrame(container)
		if value == false then addon.MythicPlus.functions.resetCooldownBars() end
	end)
	groupCore:AddChild(cbPotionTrackerEnabled)

	if addon.db["potionTracker"] then
		groupCore:AddChild(addon.functions.createSpacerAce())

		local btnToggleAnchor = addon.functions.createButtonAce(L["Toggle Anchor"], 140, function(self)
			if addon.MythicPlus.anchorFrame:IsShown() then
				addon.MythicPlus.anchorFrame:Hide()
				self:SetText(L["Toggle Anchor"])
			else
				self:SetText(L["Save Anchor"])
				addon.MythicPlus.anchorFrame:Show()
			end
		end)
		groupCore:AddChild(btnToggleAnchor)
		groupCore:AddChild(addon.functions.createSpacerAce())

		local data = {
			{
				text = L["potionTrackerUpwardsBar"],
				var = "potionTrackerUpwardsBar",
				func = function(self, _, value)
					addon.db["potionTrackerUpwardsBar"] = value
					addon.MythicPlus.functions.updateBars()
				end,
			},
			{
				text = L["potionTrackerClassColor"],
				var = "potionTrackerClassColor",
			},
			{
				text = L["potionTrackerDisableRaid"],
				var = "potionTrackerDisableRaid",
				func = function(self, _, value)
					addon.db["potionTrackerDisableRaid"] = value
					if value == true and UnitInRaid("player") then addon.MythicPlus.functions.resetCooldownBars() end
				end,
			},
			{
				text = L["potionTrackerShowTooltip"],
				var = "potionTrackerShowTooltip",
			},
			{
				text = L["potionTrackerHealingPotions"],
				var = "potionTrackerHealingPotions",
			},
			{
				text = L["potionTrackerOffhealing"],
				var = "potionTrackerOffhealing",
			},
		}

		table.sort(data, function(a, b) return a.text < b.text end)

		for _, cbData in ipairs(data) do
			local uFunc = function(self, _, value) addon.db[cbData.var] = value end
			if cbData.func then uFunc = cbData.func end
			local cbElement = addon.functions.createCheckboxAce(cbData.text, addon.db[cbData.var], uFunc)
			groupCore:AddChild(cbElement)
		end

		-- Bar Texture dropdown (DEFAULT + built-ins + LSM)
		local function buildPotionTextureOptions()
			local map = {
				["DEFAULT"] = DEFAULT,
				["Interface\\TargetingFrame\\UI-StatusBar"] = "Blizzard: UI-StatusBar",
				["Interface\\Buttons\\WHITE8x8"] = "Flat (white, tintable)",
				["Interface\\Tooltips\\UI-Tooltip-Background"] = "Dark Flat (Tooltip bg)",
			}
			-- Merge LSM statusbar textures (path -> displayName)
			for name, path in pairs(LSM and LSM:HashTable("statusbar") or {}) do
				if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
			end
			-- Build sorted list excluding DEFAULT first
			local noDefault = {}
			for k, v in pairs(map) do
				if k ~= "DEFAULT" then noDefault[k] = v end
			end
			local sorted, order = addon.functions.prepareListForDropdown(noDefault)
			-- Reinsert DEFAULT at the top of order
			sorted["DEFAULT"] = DEFAULT
			table.insert(order, 1, "DEFAULT")
			return sorted, order
		end

		local list, order = buildPotionTextureOptions()
		local dropTex = addon.functions.createDropdownAce(L["Bar Texture"], list, order, function(_, _, key)
			addon.db["potionTrackerBarTexture"] = key
			if addon.MythicPlus.functions.applyPotionBarTexture then addon.MythicPlus.functions.applyPotionBarTexture() end
		end)
		local cur = addon.db["potionTrackerBarTexture"] or "DEFAULT"
		if not list[cur] then cur = "DEFAULT" end
		dropTex:SetValue(cur)
		groupCore:AddChild(dropTex)

		addon.MythicPlus.ui = addon.MythicPlus.ui or {}
		addon.MythicPlus.ui.potionTextureDropdown = dropTex
		addon.MythicPlus.functions.RefreshPotionTextureDropdown = function()
			local dd = addon.MythicPlus.ui and addon.MythicPlus.ui.potionTextureDropdown
			if not dd then return end
			local l, o = buildPotionTextureOptions()
			dd:SetList(l, o)
			local v = addon.db and addon.db["potionTrackerBarTexture"] or "DEFAULT"
			if not l[v] then v = "DEFAULT" end
			dd:SetValue(v)
		end
	end
	scroll:DoLayout()
end

local function addTeleportFrame(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)
	groupCore:SetTitle(L["teleportsHeadline"])

	local cbTeleportsEnabled = addon.functions.createCheckboxAce(L["teleportEnabled"], addon.db["teleportFrame"], function(self, _, value)
		addon.db["teleportFrame"] = value
		container:ReleaseChildren()
		addTeleportFrame(container)
		addon.MythicPlus.functions.toggleFrame()
	end, L["teleportEnabledDesc"])
	groupCore:AddChild(cbTeleportsEnabled)

	-- World Map Compendium toggle, independent of Teleport Frame
	local cbWorldMapEnabled = addon.functions.createCheckboxAce(L["teleportsWorldMapEnabled"], addon.db["teleportsWorldMapEnabled"], function(self, _, value)
		addon.db["teleportsWorldMapEnabled"] = value
		if addon.MythicPlus.functions.RefreshWorldMapTeleportPanel then addon.MythicPlus.functions.RefreshWorldMapTeleportPanel() end
		-- Rebuild this section so the hint label appears/disappears immediately
		container:ReleaseChildren()
		addTeleportFrame(container)
	end, L["teleportsWorldMapEnabledDesc"])
	groupCore:AddChild(cbWorldMapEnabled)

	-- Show the classic season list inside the World Map panel
	local cbWorldMapSeason = addon.functions.createCheckboxAce(L["teleportsWorldMapShowSeason"], addon.db["teleportsWorldMapShowSeason"], function(self, _, value)
		addon.db["teleportsWorldMapShowSeason"] = value
		if addon.MythicPlus.functions.RefreshWorldMapTeleportPanel then addon.MythicPlus.functions.RefreshWorldMapTeleportPanel() end
		container:ReleaseChildren()
		addTeleportFrame(container)
	end, L["teleportsWorldMapShowSeasonDesc"])
	groupCore:AddChild(cbWorldMapSeason)

	-- Show a short usage hint when the World Map panel is enabled
	if addon.db["teleportsWorldMapEnabled"] then
		local hint = addon.functions.createLabelAce(
			"|cffffd700" .. (L["teleportsWorldMapHelp"] or "Right-click to display the teleport destination\nShift+Right-click to toggle favorite") .. "|r",
			nil,
			nil,
			12
		)
		hint:SetFullWidth(true)
		groupCore:AddChild(hint)
		groupCore:AddChild(addon.functions.createSpacerAce())
	end

	-- if addon.db["teleportFrame"] then
	local data = {
		{
			text = L["portalHideMissing"],
			var = "portalHideMissing",
		},
		{
			text = L["portalShowTooltip"],
			var = "portalShowTooltip",
			func = function(self, _, value)
				addon.db["portalShowTooltip"] = value
				if addon.MythicPlus.functions.RefreshWorldMapTeleportPanel then addon.MythicPlus.functions.RefreshWorldMapTeleportPanel() end
			end,
		},
	}

	table.sort(data, function(a, b) return a.text < b.text end)

	for _, cbData in ipairs(data) do
		local uFunc = function(self, _, value)
			addon.db[cbData.var] = value
			addon.MythicPlus.functions.toggleFrame()
			if addon.MythicPlus.functions.RefreshWorldMapTeleportPanel then addon.MythicPlus.functions.RefreshWorldMapTeleportPanel() end
		end
		if cbData.func then uFunc = cbData.func end
		local cbElement = addon.functions.createCheckboxAce(cbData.text, addon.db[cbData.var], uFunc)
		groupCore:AddChild(cbElement)
	end
	-- end

	-- Legacy/old compendium options removed; modern World Map compendium is always used.

	scroll:DoLayout()
	wrapper:DoLayout()
end

-- TODO after the other TODOs where we change some frames and pack them into this, go and optimize the "ReleaseChildren" and addAutoMarkFrame so we have less frame garbage collecting
local function addAutoMarkFrame(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)

	local labelExplanation = addon.functions.createLabelAce("|cffffd700" .. L["autoMarkTankExplanation"]:format(TANK, COMMUNITY_MEMBER_ROLE_NAME_LEADER, TANK) .. "|r", nil, nil, 14)
	labelExplanation:SetFullWidth(true)
	groupCore:AddChild(labelExplanation)
	groupCore:AddChild(addon.functions.createSpacerAce())

	local cbAutoMarkTank = addon.functions.createCheckboxAce(L["autoMarkTankInDungeon"]:format(TANK), addon.db["autoMarkTankInDungeon"], function(self, _, value)
		addon.db["autoMarkTankInDungeon"] = value
		if value and UnitInParty("player") and not UnitInRaid("player") and select(1, IsInInstance()) == true then
			setActTank()
			checkRaidMarker()
		end
		container:ReleaseChildren()
		addAutoMarkFrame(container)
	end)
	groupCore:AddChild(cbAutoMarkTank)

	if addon.db["autoMarkTankInDungeon"] then
		local list, order = addon.functions.prepareListForDropdown({
			[1] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:20|t",
			[2] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_2:20|t",
			[3] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:20|t",
			[4] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_4:20|t",
			[5] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_5:20|t",
			[6] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_6:20|t",
			[7] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:20|t",
			[8] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:20|t",
		})

		local dropTankMark = addon.functions.createDropdownAce(L["autoMarkTankInDungeonMarker"], list, order, function(self, _, value)
			if value == addon.db["autoMarkHealerInDungeonMarker"] then
				print("|cff00ff98Enhance QoL|r: " .. L["markerAlreadyUsed"]:format(HEALER))
				self:SetValue(addon.db["autoMarkTankInDungeonMarker"])
				return
			end
			addon.db["autoMarkTankInDungeonMarker"] = value
		end)
		dropTankMark:SetValue(addon.db["autoMarkTankInDungeonMarker"])
		dropTankMark:SetFullWidth(false)
		dropTankMark:SetWidth(100)
		groupCore:AddChild(dropTankMark)

		groupCore:AddChild(addon.functions.createSpacerAce())
	end

	local cbAutoMarkHealer = addon.functions.createCheckboxAce(L["autoMarkHealerInDungeon"]:format(HEALER), addon.db["autoMarkHealerInDungeon"], function(self, _, value)
		addon.db["autoMarkHealerInDungeon"] = value
		if value and UnitInParty("player") and not UnitInRaid("player") and select(1, IsInInstance()) == true then
			setActHealer()
			checkRaidMarker()
		end
		container:ReleaseChildren()
		addAutoMarkFrame(container)
	end)
	groupCore:AddChild(cbAutoMarkHealer)

	if addon.db["autoMarkHealerInDungeon"] then
		local list, order = addon.functions.prepareListForDropdown({
			[1] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:20|t",
			[2] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_2:20|t",
			[3] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:20|t",
			[4] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_4:20|t",
			[5] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_5:20|t",
			[6] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_6:20|t",
			[7] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:20|t",
			[8] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:20|t",
		})

		local dropHealerMark = addon.functions.createDropdownAce(L["autoMarkHealerInDungeonMarker"], list, order, function(self, _, value)
			if value == addon.db["autoMarkTankInDungeonMarker"] then
				print("|cff00ff98Enhance QoL|r: " .. L["markerAlreadyUsed"]:format(TANK))
				self:SetValue(addon.db["autoMarkHealerInDungeonMarker"])
				return
			end
			addon.db["autoMarkHealerInDungeonMarker"] = value
		end)
		dropHealerMark:SetValue(addon.db["autoMarkHealerInDungeonMarker"])
		dropHealerMark:SetFullWidth(false)
		dropHealerMark:SetWidth(100)
		groupCore:AddChild(dropHealerMark)
		groupCore:AddChild(addon.functions.createSpacerAce())
	end

	local data = {
		{
			text = L["mythicPlusNoHealerMark"],
			var = "mythicPlusNoHealerMark",
			func = function(self, _, value)
				addon.db["mythicPlusNoHealerMark"] = value
				checkCondition()
			end,
		},
	}

	for _, cbData in ipairs(data) do
		local uFunc = function(self, _, value) addon.db[cbData.var] = value end
		if cbData.func then uFunc = cbData.func end
		local cbElement = addon.functions.createCheckboxAce(cbData.text, addon.db[cbData.var], uFunc)
		groupCore:AddChild(cbElement)
	end

	if addon.db["autoMarkHealerInDungeon"] or addon.db["autoMarkTankInDungeon"] then
		-- Sub-inline group for exclusions (kept near main options)
		local sub = addon.functions.createContainer("InlineGroup", "List")
		sub:SetTitle(L["Exclude"] or "Excludes")
		groupCore:AddChild(sub)

		-- Multi-select dropdown to replace individual checkboxes
		local list = {
			normal = PLAYER_DIFFICULTY1,
			heroic = PLAYER_DIFFICULTY2,
			mythic = PLAYER_DIFFICULTY6,
			timewalking = PLAYER_DIFFICULTY_TIMEWALKER,
			event = BATTLE_PET_SOURCE_7,
		}
		local order = { "normal", "heroic", "mythic", "timewalking", "event" }
		local keyMap = {
			normal = "mythicPlusIgnoreNormal",
			heroic = "mythicPlusIgnoreHeroic",
			mythic = "mythicPlusIgnoreMythic",
			timewalking = "mythicPlusIgnoreTimewalking",
			event = "mythicPlusIgnoreEvent",
		}

		local dd = addon.functions.createDropdownAce("Ignore in", list, order, function(widget, _, key, checked)
			local dbKey = keyMap[key]
			if dbKey then addon.db[dbKey] = checked and true or false end
		end)
		dd:SetMultiselect(true)
		-- Initialize selected items from legacy booleans
		dd:SetCallback("OnOpened", function(widget)
			for _, code in ipairs(order) do
				local dbKey = keyMap[code]
				if dbKey then widget:SetItemValue(code, addon.db[dbKey] and true or false) end
			end
		end)
		dd:SetFullWidth(true)
		sub:AddChild(dd)
	end
	scroll:DoLayout()
end

local activeTalentContainer
local function addTalentFrame(container)
	activeTalentContainer = container

	addon.MythicPlus.functions.getAllLoadouts()

	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)

	local data = {
		{
			text = L["talentReminderEnabled"],
			var = "talentReminderEnabled",
			func = function(self, _, value)
				addon.db["talentReminderEnabled"] = value
				container:ReleaseChildren()
				addTalentFrame(container)
				addon.MythicPlus.functions.checkLoadout()
			end,
			desc = L["talentReminderEnabledDesc"]:format(PLAYER_DIFFICULTY6, PLAYER_DIFFICULTY_MYTHIC_PLUS),
		},
	}

	if addon.db["talentReminderEnabled"] then
		table.insert(data, {
			text = L["talentReminderLoadOnReadyCheck"]:format(READY_CHECK),
			var = "talentReminderLoadOnReadyCheck",
			func = function(self, _, value)
				addon.db["talentReminderLoadOnReadyCheck"] = value
				addon.MythicPlus.functions.checkLoadout()
			end,
		})
		table.insert(data, {
			text = L["talentReminderSoundOnDifference"],
			var = "talentReminderSoundOnDifference",
			func = function(self, _, value)
				addon.db["talentReminderSoundOnDifference"] = value
				addon.MythicPlus.functions.checkLoadout()
			end,
		})
		table.insert(data, {
			text = L["talentReminderShowActiveBuild"],
			var = "talentReminderShowActiveBuild",
			func = function(self, _, value)
				addon.db["talentReminderShowActiveBuild"] = value
				addon.MythicPlus.functions.updateActiveTalentText()
				container:ReleaseChildren()
				addTalentFrame(container)
			end,
		})
	end

	for _, cbData in ipairs(data) do
		local uFunc = function(self, _, value) addon.db[cbData.var] = value end
		if cbData.func then uFunc = cbData.func end
		local desc
		if cbData.desc then desc = cbData.desc end
		local cbElement = addon.functions.createCheckboxAce(cbData.text, addon.db[cbData.var], uFunc, desc)
		groupCore:AddChild(cbElement)
	end

	if addon.db["talentReminderEnabled"] and addon.db["talentReminderSoundOnDifference"] then
		local cbCustomSound = addon.functions.createCheckboxAce(L["talentReminderUseCustomSound"], addon.db["talentReminderUseCustomSound"], function(self, _, value)
			addon.db["talentReminderUseCustomSound"] = value
			container:ReleaseChildren()
			addTalentFrame(container)
		end)
		groupCore:AddChild(cbCustomSound)

		if addon.db["talentReminderUseCustomSound"] then
			local soundList = {}
			if addon.ChatIM and addon.ChatIM.BuildSoundTable and not addon.ChatIM.availableSounds then addon.ChatIM:BuildSoundTable() end
			local soundTable = (addon.ChatIM and addon.ChatIM.availableSounds) or LSM:HashTable("sound")
			for name in pairs(soundTable or {}) do
				soundList[name] = name
			end
			local list, order = addon.functions.prepareListForDropdown(soundList)
			local dropSound = addon.functions.createDropdownAce(L["talentReminderCustomSound"], list, order, function(self, _, val)
				addon.db["talentReminderCustomSoundFile"] = val
				self:SetValue(val)
				local file = soundTable and soundTable[val]
				if file then PlaySoundFile(file, "Master") end
			end)
			dropSound:SetValue(addon.db["talentReminderCustomSoundFile"])
			groupCore:AddChild(dropSound)
			groupCore:AddChild(addon.functions.createSpacerAce())
		end
	end

	if addon.db["talentReminderEnabled"] then
		if addon.db["talentReminderShowActiveBuild"] then
			local sliderSize = addon.functions.createSliderAce(
				L["talentReminderActiveBuildTextSize"] .. ": " .. addon.db["talentReminderActiveBuildSize"],
				addon.db["talentReminderActiveBuildSize"],
				6,
				64,
				1,
				function(self, _, value2)
					addon.db["talentReminderActiveBuildSize"] = value2
					addon.MythicPlus.functions.updateActiveTalentText()
					self:SetLabel(L["talentReminderActiveBuildTextSize"] .. ": " .. value2)
				end
			)
			groupCore:AddChild(sliderSize)

			local cbLock = addon.functions.createCheckboxAce(L["talentReminderLockActiveBuild"], addon.db["talentReminderActiveBuildLocked"], function(self, _, value)
				addon.db["talentReminderActiveBuildLocked"] = value
				addon.MythicPlus.functions.updateActiveTalentText()
			end)
			groupCore:AddChild(cbLock)

			local list, order = addon.functions.prepareListForDropdown({
				[1] = L["talentReminderShowActiveBuildOutside"],
				[2] = L["talentReminderShowActiveBuildInstance"],
				[3] = L["talentReminderShowActiveBuildRaid"],
			})

			local dropShow = addon.functions.createDropdownAce(L["talentReminderShowActiveBuildDropdown"], list, order, function(self, event, key, value)
				if type(addon.db["talentReminderActiveBuildShowOnly"]) ~= "table" then addon.db["talentReminderActiveBuildShowOnly"] = {} end
				addon.db["talentReminderActiveBuildShowOnly"][key] = value or nil
				addon.MythicPlus.functions.updateActiveTalentText()
			end)
			dropShow:SetMultiselect(true)
			for c, val in pairs(type(addon.db["talentReminderActiveBuildShowOnly"]) == "table" and addon.db["talentReminderActiveBuildShowOnly"] or {}) do
				if val then dropShow:SetItemValue(c, true) end
			end
			dropShow:SetFullWidth(false)
			dropShow:SetWidth(200)
			groupCore:AddChild(dropShow)
		end
	end

	if addon.db["talentReminderEnabled"] then
		local groupTalent = addon.functions.createContainer("TabGroup", "Flow")

		groupTalent:SetFullWidth(true) -- Nimmt die volle Breite des Parents

		groupTalent:SetTabs(addon.MythicPlus.variables.specNames)
		groupTalent:SetCallback("OnGroupSelected", function(tabContainer, event, group)
			tabContainer:ReleaseChildren()
			if not addon.db["talentReminderSettings"][addon.variables.unitPlayerGUID] then addon.db["talentReminderSettings"][addon.variables.unitPlayerGUID] = {} end
			if not addon.db["talentReminderSettings"][addon.variables.unitPlayerGUID][group] then addon.db["talentReminderSettings"][addon.variables.unitPlayerGUID][group] = {} end

			for _, cbData in pairs(addon.MythicPlus.variables.seasonMapInfo) do
				local list, order = addon.functions.prepareListForDropdown(addon.MythicPlus.variables.knownLoadout[group])

				local dropPullTimerType = addon.functions.createDropdownAce(cbData.name, list, order, function(self, _, value)
					addon.db["talentReminderSettings"][addon.variables.unitPlayerGUID][group][cbData.id] = value
					C_Timer.After(1, function() addon.MythicPlus.functions.checkLoadout() end)
				end)
				if dropPullTimerType.label and dropPullTimerType.label.SetFont then dropPullTimerType.label:SetFont(addon.variables.defaultFont, 14, "OUTLINE") end
				if addon.db["talentReminderSettings"][addon.variables.unitPlayerGUID][group][cbData.id] then
					dropPullTimerType:SetValue(addon.db["talentReminderSettings"][addon.variables.unitPlayerGUID][group][cbData.id])
				else
					dropPullTimerType:SetValue(0)
				end
				dropPullTimerType:SetFullWidth(false)
				dropPullTimerType:SetWidth(200)
				tabContainer:AddChild(dropPullTimerType)
				local spacer = addon.AceGUI:Create("Label")
				spacer:SetWidth(20) -- 20 Pixel Freiraum
				spacer:SetText("") -- Leer
				tabContainer:AddChild(spacer)
			end
			C_Timer.After(0.1, function()
				scroll:DoLayout()
				wrapper:DoLayout()
			end)
		end)
		if addon.MythicPlus.variables.currentSpecID and addon.MythicPlus.variables.knownLoadout[addon.MythicPlus.variables.currentSpecID] then
			groupTalent:SelectTab(addon.MythicPlus.variables.currentSpecID)
		else
			groupTalent:SelectTab(addon.MythicPlus.variables.specNames[1].value)
		end

		wrapper:AddChild(groupTalent)

		if TalentLoadoutEx then
			local groupInfo = addon.functions.createContainer("InlineGroup", "List")
			groupInfo:SetTitle(INFO)
			wrapper:AddChild(groupInfo)

			local labelHeadlineExplain = addon.functions.createLabelAce("|cffffd700" .. L["labelExplainedlineTLE"] .. "|r", nil, nil, 14)
			groupInfo:AddChild(labelHeadlineExplain)
			labelHeadlineExplain:SetFullWidth(true)
			groupInfo:AddChild(addon.functions.createSpacerAce())

			local btnToggleAnchor = addon.functions.createButtonAce(L["ReloadLoadouts"], 220, function(self)
				addon.MythicPlus.functions.getAllLoadouts()
				addon.MythicPlus.functions.checkRemovedLoadout()
				addon.MythicPlus.functions.refreshTalentFrameIfOpen()
			end)
			local fs = btnToggleAnchor.frame:GetFontString()
			btnToggleAnchor:SetWidth(fs:GetStringWidth() + 50)
			groupInfo:AddChild(btnToggleAnchor)
		end
	end
end
function addon.MythicPlus.functions.refreshTalentFrameIfOpen()
	if not activeTalentContainer then return end
	local sel = addon.variables.statusTable.selected or ""
	local pos = sel:find("mythicplus\001talents", 1, true)
	if pos == 1 or sel:find("general\001mythicplus\001talents", 1, true) or sel:find("general\001combat\001talents", 1, true) or sel:find("combat\001talents", 1, true) then
		activeTalentContainer:ReleaseChildren()
		addTalentFrame(activeTalentContainer)
	end
end

-- Register Mythic+ panels under General -> Combat & Dungeons -> Dungeon
-- addon.variables.statusTable.groups["general\001combat"] = true
-- addon.variables.statusTable.groups["general\001combat\001dungeon"] = true

-- Create a single Mythic+ category under Combat & Dungeons
addon.functions.addToTree("combat", { value = "mythicplus", text = PLAYER_DIFFICULTY_MYTHIC_PLUS .. " & " .. RAID }, true)

-- Keep remaining Mythic+ related entries top-level if not in the grouped category
local mpChildren = {
	{ value = "automark", text = L["AutoMark"] },
	{ value = "talents", text = L["TalentReminder"] },
}
for _, child in ipairs(mpChildren) do
	addon.functions.addToTree("combat", child, true)
end

-- Place Potion Tracker under Combat (works everywhere)
addon.functions.addToTree("combat", { value = "potiontracker", text = L["Potion Tracker"] }, true)

-- Place Teleports under Map & Navigation
addon.functions.addToTree("nav", { value = "teleports", text = L["Teleports"] }, true)

-- Combined Mythic+ category root
local function addMythicPlusRootFrame(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groups = {}
	if wrapper.PauseLayout then wrapper:PauseLayout() end
	local function doLayout()
		if scroll and scroll.DoLayout then scroll:DoLayout() end
	end
	local function ensureGroup(key, title)
		local g = groups[key]
		local known = false
		if g then
			known = true
			g:PauseLayout()
			g:ReleaseChildren()
		else
			g = addon.functions.createContainer("InlineGroup", "List")
			if title and title ~= "" then g:SetTitle(title) end
			groups[key] = g
			wrapper:AddChild(g)
		end
		return g, known
	end

	-- Section builders (inline, migrated from old frames)
	local function buildKeystone()
		local g, known = ensureGroup("keystone", L["Keystone"])
		local cbEnable = addon.functions.createCheckboxAce(L["enableKeystoneHelper"], addon.db["enableKeystoneHelper"], function(_, _, value)
			addon.db["enableKeystoneHelper"] = value
			buildKeystone()
			if _G["ChallengesKeystoneFrame"] and ChallengesKeystoneFrame:IsShown() then checkKeyStone() end
			if C_MythicPlus.IsMythicPlusActive() and value == false then
				local block = ScenarioObjectiveTracker and ScenarioObjectiveTracker.ChallengeModeBlock
				if block then
					if block.ChestTimeText2 then block.ChestTimeText2:SetText("") end
					if block.ChestTimeText3 then block.ChestTimeText3:SetText("") end
				end
			end
		end, L["enableKeystoneHelperDesc"])
		g:AddChild(cbEnable)

		if addon.db["enableKeystoneHelper"] then
			local data = {
				{ text = L["Automatically insert keystone"], var = "autoInsertKeystone" },
				{ text = L["Close all bags on keystone insert"], var = "closeBagsOnKeyInsert" },
				{ text = L["autoKeyStart"], var = "autoKeyStart" },
				{
					text = L["groupfinderShowPartyKeystone"],
					var = "groupfinderShowPartyKeystone",
					func = function(_, _, v)
						addon.db["groupfinderShowPartyKeystone"] = v
						addon.MythicPlus.functions.togglePartyKeystone()
					end,
					desc = L["groupfinderShowPartyKeystoneDesc"],
				},
				{
					text = L["mythicPlusShowChestTimers"],
					var = "mythicPlusShowChestTimers",
					func = function(self, _, value)
						addon.db["mythicPlusShowChestTimers"] = value
						if not value then
							local block = ScenarioObjectiveTracker and ScenarioObjectiveTracker.ChallengeModeBlock
							if block then
								if block.ChestTimeText2 then block.ChestTimeText2:SetText("") end
								if block.ChestTimeText3 then block.ChestTimeText3:SetText("") end
							end
						end
					end,
					desc = L["mythicPlusShowChestTimersDesc"],
				},
			}
			table.sort(data, function(a, b) return a.text < b.text end)
			for _, cb in ipairs(data) do
				local u = cb.func or function(_, _, v) addon.db[cb.var] = v end
				local el = addon.functions.createCheckboxAce(cb.text, addon.db[cb.var], u, cb.desc)
				g:AddChild(el)
			end

			local list, order = addon.functions.prepareListForDropdown({ [1] = L["None"], [2] = L["Blizzard Pull Timer"], [3] = L["DBM / BigWigs Pull Timer"], [4] = L["Both"] })
			local row0 = addon.functions.createContainer("SimpleGroup", "Flow")
			g:AddChild(row0)
			local dropPullTimerType = addon.functions.createDropdownAce(L["PullTimer"], list, order, function(self, _, value) addon.db["PullTimerType"] = value end)
			dropPullTimerType:SetValue(addon.db["PullTimerType"])
			dropPullTimerType:SetFullWidth(false)
			if dropPullTimerType.SetRelativeWidth then dropPullTimerType:SetRelativeWidth(0.5) end
			row0:AddChild(dropPullTimerType)

			local cbNoChat = addon.functions.createCheckboxAce(L["noChatOnPullTimer"], addon.db["noChatOnPullTimer"], function(_, _, v) addon.db["noChatOnPullTimer"] = v end)
			if cbNoChat.SetRelativeWidth then cbNoChat:SetRelativeWidth(0.5) end
			row0:AddChild(cbNoChat)

			-- Sliders in one row (50% width each)
			local row = addon.functions.createContainer("SimpleGroup", "Flow")
			g:AddChild(row)

			local longSlider = addon.functions.createSliderAce(L["sliderLongTime"] .. ": " .. addon.db["pullTimerLongTime"] .. "s", addon.db["pullTimerLongTime"], 0, 60, 1, function(self, _, v)
				addon.db["pullTimerLongTime"] = v
				self:SetLabel(L["sliderLongTime"] .. ": " .. v .. "s")
			end)
			longSlider:SetFullWidth(false)
			if longSlider.SetRelativeWidth then longSlider:SetRelativeWidth(0.5) end
			row:AddChild(longSlider)

			local shortSlider = addon.functions.createSliderAce(L["sliderShortTime"] .. ": " .. addon.db["pullTimerShortTime"] .. "s", addon.db["pullTimerShortTime"], 0, 60, 1, function(self, _, v)
				addon.db["pullTimerShortTime"] = v
				self:SetLabel(L["sliderShortTime"] .. ": " .. v .. "s")
			end)
			shortSlider:SetFullWidth(false)
			if shortSlider.SetRelativeWidth then shortSlider:SetRelativeWidth(0.5) end
			row:AddChild(shortSlider)
		end

		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildObjective()
		local g, known = ensureGroup("objective", HUD_EDIT_MODE_OBJECTIVE_TRACKER_LABEL)
		local cb = addon.functions.createCheckboxAce(L["mythicPlusEnableObjectiveTracker"], addon.db["mythicPlusEnableObjectiveTracker"], function(_, _, v)
			addon.db["mythicPlusEnableObjectiveTracker"] = v
			buildObjective()
			addon.MythicPlus.functions.setObjectiveFrames()
		end, L["mythicPlusEnableObjectiveTrackerDesc"])
		g:AddChild(cb)

		if addon.db["mythicPlusEnableObjectiveTracker"] then
			local list, order = addon.functions.prepareListForDropdown({ [1] = L["HideTracker"], [2] = L["collapse"] })
			local drop = addon.functions.createDropdownAce(L["mythicPlusObjectiveTrackerSetting"], list, order, function(_, _, value)
				addon.db["mythicPlusObjectiveTrackerSetting"] = value
				addon.MythicPlus.functions.setObjectiveFrames()
			end)
			if addon.db["mythicPlusObjectiveTrackerSetting"] then drop:SetValue(addon.db["mythicPlusObjectiveTrackerSetting"]) end
			g:AddChild(drop)
		end

		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildRating()
		local g, known = ensureGroup("rating", DUNGEON_SCORE)
		local el = addon.functions.createCheckboxAce(L["groupfinderShowDungeonScoreFrame"]:format(DUNGEON_SCORE), addon.db["groupfinderShowDungeonScoreFrame"], function(_, _, v)
			addon.db["groupfinderShowDungeonScoreFrame"] = v
			addon.MythicPlus.functions.toggleFrame()
		end)
		g:AddChild(el)
		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildBR()
		local g, known = ensureGroup("brtracker", L["BRTracker"])
		local cb = addon.functions.createCheckboxAce(L["mythicPlusBRTrackerEnabled"], addon.db["mythicPlusBRTrackerEnabled"], function(_, _, v)
			addon.db["mythicPlusBRTrackerEnabled"] = v
			createBRFrame()
			buildBR()
		end)
		g:AddChild(cb)

		if addon.db["mythicPlusBRTrackerEnabled"] then
			local data = {
				{
					text = L["mythicPlusBRTrackerLocked"],
					var = "mythicPlusBRTrackerLocked",
					func = function(_, _, v2)
						addon.db["mythicPlusBRTrackerLocked"] = v2
						createBRFrame()
					end,
				},
			}
			table.sort(data, function(a, b) return a.text < b.text end)
			for _, cbData in ipairs(data) do
				local u = cbData.func or function(_, _, v3)
					addon.db[cbData.var] = v3
					addon.MythicPlus.functions.toggleFrame()
				end
				local el = addon.functions.createCheckboxAce(cbData.text, addon.db[cbData.var], u)
				g:AddChild(el)
			end

			local s = addon.functions.createSliderAce(
				L["mythicPlusBRButtonSizeHeadline"] .. ": " .. addon.db["mythicPlusBRButtonSize"],
				addon.db["mythicPlusBRButtonSize"],
				20,
				100,
				1,
				function(self, _, v4)
					addon.db["mythicPlusBRButtonSize"] = v4
					createBRFrame()
					self:SetLabel(L["mythicPlusBRButtonSizeHeadline"] .. ": " .. v4)
				end
			)
			g:AddChild(s)
		end

		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildGroupFilter()
		local g, known = ensureGroup("groupfilter", LFG_TITLE)
		local cb = addon.functions.createCheckboxAce(L["mythicPlusEnableDungeonFilter"], addon.db["mythicPlusEnableDungeonFilter"], function(_, _, v)
			addon.db["mythicPlusEnableDungeonFilter"] = v
			if v then
				addon.MythicPlus.functions.addDungeonFilter()
			else
				addon.MythicPlus.functions.removeDungeonFilter()
			end
			buildGroupFilter()
		end, L["mythicPlusEnableDungeonFilterDesc"]:format(REPORT_GROUP_FINDER_ADVERTISEMENT))
		g:AddChild(cb)

		if addon.db["mythicPlusEnableDungeonFilter"] then
			local cb2 = addon.functions.createCheckboxAce(
				L["mythicPlusEnableDungeonFilterClearReset"],
				addon.db["mythicPlusEnableDungeonFilterClearReset"],
				function(_, _, v) addon.db["mythicPlusEnableDungeonFilterClearReset"] = v end
			)
			g:AddChild(cb2)
		end

		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	-- Build sections
	buildBR()
	buildGroupFilter()
	buildKeystone()
	buildRating()
	buildObjective()

	if wrapper.ResumeLayout then wrapper:ResumeLayout() end
	doLayout()
end

function addon.MythicPlus.functions.treeCallback(container, group)
	container:ReleaseChildren() -- Entfernt vorherige Inhalte
	-- Prüfen, welche Gruppe ausgewählt wurde

	if group == "combat\001mythicplus" or group == "mythicplus" then
		addMythicPlusRootFrame(container)
		return
	end
	-- Normalize path so both previous and embedded paths work
	-- Supported suffixes after either "mythicplus\001" or "...\001dungeon\001"
	local pos = group:find("mythicplus\001", 1, true)
	if pos then
		group = group:sub(pos)
	else
		-- Map legacy "dungeon" paths or flattened "combat" paths to mythicplus namespace
		if group == "combat\001mythicplus" then group = "mythicplus" end
		local ppos = group:find("party\001groupfilter", 1, true)
		if ppos then group = "mythicplus\001groupfilter" end
		local ppos2 = group:find("party\001potiontracker", 1, true)
		if ppos2 then group = "mythicplus\001potiontracker" end
		local npos = group:find("nav\001teleports", 1, true)
		if npos then group = "mythicplus\001teleports" end

		local dpos = group:find("dungeon\001", 1, true)
		if dpos then
			group = "mythicplus\001" .. group:sub(dpos + #"dungeon\001")
		else
			local cpos = group:find("combat\001", 1, true)
			if cpos then group = "mythicplus\001" .. group:sub(cpos + #"combat\001") end
		end
	end

	-- Force combined view for direct leaf routes under mythicplus
	if
		group == "mythicplus"
		or group == "mythicplus\001mythicplus"
		or group == "mythicplus\001keystone"
		or group == "mythicplus\001brtracker"
		or group == "mythicplus\001rating"
		or group == "mythicplus\001objectivetracker"
	then
		addMythicPlusRootFrame(container)
		return
	elseif group == "mythicplus\001potiontracker" then
		addPotionTrackerFrame(container)
		-- TODO rename automark to Dungeon and put brtracker into that frame, each in his own group in the container
	elseif group == "mythicplus\001automark" then
		addAutoMarkFrame(container)
	elseif group == "mythicplus\001teleports" then
		addTeleportFrame(container)
	elseif group == "mythicplus\001talents" then
		addTalentFrame(container)
	elseif group == "mythicplus\001groupfilter" then
		addMythicPlusRootFrame(container)
	end
end

if addon.db["mythicPlusEnableDungeonFilter"] then addon.MythicPlus.functions.addDungeonFilter() end
