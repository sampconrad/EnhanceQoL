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
local brAnchor
local defaultButtonSize = 60
local defaultFontSize = 16

local EditMode = addon.EditMode
local BR_EDITMODE_ID = "mythicPlusBRTracker"
local brEditModeRegistered = false

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

local function buildBRLayoutSnapshot(layoutName)
	local layout = EditMode and EditMode:GetLayoutData(BR_EDITMODE_ID, layoutName)
	if layout then
		if not layout.relativePoint then layout.relativePoint = layout.point end
		return layout
	end

	return {
		point = addon.db["mythicPlusBRTrackerPoint"] or "CENTER",
		relativePoint = addon.db["mythicPlusBRTrackerPoint"] or "CENTER",
		x = addon.db["mythicPlusBRTrackerX"] or 0,
		y = addon.db["mythicPlusBRTrackerY"] or 0,
		size = addon.db["mythicPlusBRButtonSize"] or defaultButtonSize,
	}
end

local function applyBRLayoutData(data)
	local config = data or buildBRLayoutSnapshot()

	local point = config.point or "CENTER"
	local relativePoint = config.relativePoint or point
	local x = config.x or 0
	local y = config.y or 0
	local size = config.size or defaultButtonSize

	if addon.db then
		addon.db["mythicPlusBRTrackerPoint"] = point
		addon.db["mythicPlusBRTrackerX"] = x
		addon.db["mythicPlusBRTrackerY"] = y
		addon.db["mythicPlusBRButtonSize"] = size
	end

	if brAnchor then
		brAnchor:SetSize(size, size)
		brAnchor:ClearAllPoints()
		brAnchor:SetPoint(point, UIParent, relativePoint, x, y)
	end

	if brButton then
		brButton:SetSize(size, size)
		brButton:ClearAllPoints()
		brButton:SetPoint(point, UIParent, relativePoint, x, y)

		local scaleFactor = size / defaultButtonSize
		local newFontSize = math.floor(defaultFontSize * scaleFactor + 0.5)

		if brButton.cooldownFrame then brButton.cooldownFrame:SetScale(scaleFactor) end
		if brButton.charges then brButton.charges:SetFont(addon.variables.defaultFont, newFontSize, "OUTLINE") end
	end
end

local function ensureBRAnchor()
	if not brAnchor then
		brAnchor = CreateFrame("Frame", "EnhanceQoLMythicPlusBRAnchor", UIParent)
		brAnchor:SetClampedToScreen(true)
		brAnchor:SetMovable(true)
		brAnchor:EnableMouse(true)

		local bg = brAnchor:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.1, 0.6, 0.6, 0.35)
		brAnchor.bg = bg

		local border = brAnchor:CreateTexture(nil, "OVERLAY")
		border:SetAllPoints()
		border:SetTexture("Interface\\BUTTONS\\UI-Quickslot2")
		border:SetTexCoord(0.2, 0.8, 0.2, 0.8)
		border:SetVertexColor(0.1, 0.6, 0.6, 0.7)
		brAnchor.border = border

		brAnchor.label = brAnchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		brAnchor.label:SetPoint("CENTER")
		brAnchor.label:SetText(L["mythicPlusBRTrackerAnchor"])
	end

	if EditMode and not brEditModeRegistered then
		local settingType = EditMode.lib and EditMode.lib.SettingType
		local settings
		if settingType then
			settings = {
				{
					field = "size",
					name = L["mythicPlusBRButtonSizeHeadline"],
					kind = settingType.Slider,
					minValue = 20,
					maxValue = 100,
					valueStep = 1,
					default = addon.db["mythicPlusBRButtonSize"] or defaultButtonSize,
				},
			}
		end

		EditMode:RegisterFrame(BR_EDITMODE_ID, {
			frame = brAnchor,
			title = L["mythicPlusBRTrackerAnchor"],
			layoutDefaults = {
				point = addon.db["mythicPlusBRTrackerPoint"] or "CENTER",
				relativePoint = addon.db["mythicPlusBRTrackerPoint"] or "CENTER",
				x = addon.db["mythicPlusBRTrackerX"] or 0,
				y = addon.db["mythicPlusBRTrackerY"] or 0,
				size = addon.db["mythicPlusBRButtonSize"] or defaultButtonSize,
			},
			legacyKeys = {
				point = "mythicPlusBRTrackerPoint",
				relativePoint = "mythicPlusBRTrackerPoint",
				x = "mythicPlusBRTrackerX",
				y = "mythicPlusBRTrackerY",
				size = "mythicPlusBRButtonSize",
			},
			isEnabled = function() return addon.db["mythicPlusBRTrackerEnabled"] end,
			onApply = function(_, layoutName, data) applyBRLayoutData(data) end,
			settings = settings,
		})
		brEditModeRegistered = true
	else
		applyBRLayoutData()
	end

	return brAnchor
end

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
	if not addon.db["mythicPlusBRTrackerEnabled"] then
		if brAnchor then brAnchor:Hide() end
		if EditMode then EditMode:RefreshFrame(BR_EDITMODE_ID) end
		return
	end
	local layout = buildBRLayoutSnapshot()
	ensureBRAnchor()
	if IsInGroup() and shouldShowBRTracker() then
		local point = layout.point or "CENTER"
		local relativePoint = layout.relativePoint or point
		local xOfs = layout.x or 0
		local yOfs = layout.y or 0
		local size = layout.size or defaultButtonSize

		brButton = CreateFrame("Button", nil, UIParent)
		brButton:SetSize(size, size)
		brButton:SetPoint(point, UIParent, relativePoint, xOfs, yOfs)

		local bg = brButton:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(brButton)
		bg:SetColorTexture(0, 0, 0, 0.8)

		local icon = brButton:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints(brButton)
		icon:SetTexture(136080)
		brButton.icon = icon

		local scaleFactor = size / defaultButtonSize
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
	applyBRLayoutData(layout)
	if EditMode then EditMode:RefreshFrame(BR_EDITMODE_ID) end
end

ensureBRAnchor()

local function setBRInfo(info)
	if brButton and brButton.cooldownFrame and info then
		local current = info.currentCharges
		local max = info.maxCharges

		if issecretvalue and issecretvalue(current) then
			brButton.cooldownFrame:SetCooldown(info.cooldownStartTime, info.cooldownDuration, info.chargeModRate)
			brButton.cooldownFrame.startTime = info.cooldownStartTime
			brButton.cooldownFrame.charges = current

			-- TODO actually no way to do saturation stuff in m+/raid in midnight
			-- if current > 0 then
			brButton.charges:SetTextColor(0, 1, 0)
			brButton.icon:SetDesaturated(false)
			brButton.cooldownFrame:SetSwipeColor(0, 0, 0, 0.3)
			brButton.charges:Show()
			-- else
			-- 	brButton.cooldownFrame:SetSwipeColor(0, 0, 0, 1)
			-- 	brButton.icon:SetDesaturated(true)
			-- 	brButton.charges:SetTextColor(1, 0, 0)
			-- 	brButton.charges:Hide()
			-- end
		elseif current < max then
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
				if id == 180653 or id == 151086 then
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
if not addon.variables.isMidnight then
	frameLoad:RegisterEvent("RAID_TARGET_UPDATE")
	frameLoad:RegisterEvent("PLAYER_ROLES_ASSIGNED")
	frameLoad:RegisterEvent("READY_CHECK")
	frameLoad:RegisterEvent("GROUP_ROSTER_UPDATE")
end
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
	-- TODO remove feature on midnight release
	if addon.variables.isMidnight then return false end
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

-- Keep remaining Mythic+ related entries top-level if not in the grouped category
local mpChildren = {
	{ value = "talents", text = L["TalentReminder"] },
}
for _, child in ipairs(mpChildren) do
	addon.functions.addToTree("combat", child, true)
end

function addon.MythicPlus.functions.treeCallback(container, group)
	container:ReleaseChildren() -- Entfernt vorherige Inhalte
	-- Prüfen, welche Gruppe ausgewählt wurde

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

		local dpos = group:find("dungeon\001", 1, true)
		if dpos then
			group = "mythicplus\001" .. group:sub(dpos + #"dungeon\001")
		else
			local cpos = group:find("combat\001", 1, true)
			if cpos then group = "mythicplus\001" .. group:sub(cpos + #"combat\001") end
		end
	end

	-- Force combined view for direct leaf routes under mythicplus
	if group == "mythicplus\001talents" then addTalentFrame(container) end
end

if addon.db["mythicPlusEnableDungeonFilter"] then addon.MythicPlus.functions.addDungeonFilter() end
