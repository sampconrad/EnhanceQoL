-- luacheck: globals UIWidgetObjectiveTracker MonthlyActivitiesObjectiveTracker InitiativeTasksObjectiveTracker
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.MythicPlus = addon.MythicPlus or {}
addon.MythicPlus.functions = addon.MythicPlus.functions or {}
addon.MythicPlus.Buttons = addon.MythicPlus.Buttons or {}
addon.MythicPlus.nrOfButtons = addon.MythicPlus.nrOfButtons or 0
addon.MythicPlus.variables = addon.MythicPlus.variables or {}
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_MythicPlus")

_G["BINDING_NAME_CLICK EQOLRandomHearthstoneButton:LeftButton"] = L["teleportsRandomHearthstoneBinding"] or "Random Hearthstone"

function addon.MythicPlus.functions.InitDB()
	if addon.MythicPlus.variables.dbInitialized then return end
	if not addon.db or not addon.functions or not addon.functions.InitDBValue then return end
	addon.MythicPlus.variables.dbInitialized = true
	local init = addon.functions.InitDBValue

	-- Always use the improved Keystone Helper UI (legacy removed)
	-- PullTimer
	init("enableKeystoneHelper", false)
	init("autoInsertKeystone", false)
	init("closeBagsOnKeyInsert", false)
	init("noChatOnPullTimer", false)
	init("autoKeyStart", false)
	init("mythicPlusCurrentPull", false)
	init("mythicPlusCurrentPullLocked", false)
	init("mythicPlusCurrentPullFontSize", 14)
	init("mythicPlusCurrentPullPoint", "CENTER")
	init("mythicPlusCurrentPullX", 0)
	init("mythicPlusCurrentPullY", 0)
	init("pullTimerShortTime", 5)
	init("pullTimerLongTime", 10)
	init("PullTimerType", 4)

	-- Dungeon Browser
	init("groupfinderAppText", false)
	init("groupfinderSkipRoleSelect", false)
	init("groupfinderSkipRoleSelectOption", 1)
	init("groupfinderShowDungeonScoreFrame", false)

	-- Misc

	-- Mythic+ timer tweaks
	init("mythicPlusShowChestTimers", true)

	-- BR Tracker
	init("mythicPlusBRTrackerEnabled", false)
	init("mythicPlusBRButtonSize", 50)
	init("mythicPlusBRTrackerPoint", "CENTER")
	init("mythicPlusBRTrackerX", 0)
	init("mythicPlusBRTrackerY", 0)

	-- Talent Reminder
	init("talentReminderEnabled", false)
	init("talentReminderSettings", {})
	init("talentReminderShowActiveBuild", false)
	init("talentReminderActiveBuildPoint", "CENTER")
	init("talentReminderActiveBuildX", 0)
	init("talentReminderActiveBuildY", 0)
	init("talentReminderActiveBuildSize", 14)
	init("talentReminderActiveBuildLocked", false)
	-- switched from single number -> table (multiselect)
	init("talentReminderActiveBuildShowOnly", {})
	init("talentReminderLoadOnReadyCheck", false)
	init("talentReminderSoundOnDifference", false)
	init("talentReminderUseCustomSound", false)
	init("talentReminderCustomSoundFile", "")

	-- Backward compatibility migration: convert old numeric value to table
	local v = addon.db["talentReminderActiveBuildShowOnly"]
	if type(v) ~= "table" then
		local newVal = {}
		if type(v) == "number" and v >= 1 and v <= 3 then newVal[v] = true end
		addon.db["talentReminderActiveBuildShowOnly"] = newVal
	end

	-- Teleports
	init("teleportFrame", false)
	init("portalHideMissing", false)
	init("portalShowTooltip", false)
	-- World Map panel enable toggle (modern compendium)
	-- Cache for resolved map/zone names used by modern frame
	init("teleportNameCache", {})
	init("teleportFavorites", {})
	-- Enable/disable World Map Teleport Panel independently
	init("teleportsWorldMapEnabled", false)
	-- Also show the classic current season list in the World Map panel
	init("teleportsWorldMapShowSeason", false)
	-- Favorites override is now always active in code
	init("teleportFrameLocked", true)
	init("teleportFrameData", {})
	init("dungeonScoreFrameLocked", true)
	init("dungeonScoreFrameData", {})

	-- Group Dungeon Filter
	init("mythicPlusEnableDungeonFilter", false)
	init("mythicPlusEnableDungeonFilterClearReset", false)
	init("mythicPlusDungeonFilters", {})
end

function addon.MythicPlus.functions.InitState()
	if addon.MythicPlus.variables.stateInitialized then return end
	if not addon.db then return end
	addon.MythicPlus.variables.stateInitialized = true
	if addon.MythicPlus.functions.InitDungeonPortal then addon.MythicPlus.functions.InitDungeonPortal() end
	if addon.MythicPlus.functions.InitTalentReminder then addon.MythicPlus.functions.InitTalentReminder() end
	if addon.MythicPlus.functions.InitDungeonFilter then addon.MythicPlus.functions.InitDungeonFilter() end
	if addon.MythicPlus.functions.InitObjectiveTracker then addon.MythicPlus.functions.InitObjectiveTracker() end
	if addon.MythicPlus.functions.InitWorldMapTeleportPanel then addon.MythicPlus.functions.InitWorldMapTeleportPanel() end
	if addon.MythicPlus.functions.InitMain then addon.MythicPlus.functions.InitMain() end
end

-- Default Hearthstone name (6948), loaded safely even if uncached
addon.MythicPlus.variables.hearthstoneName = nil

-- Returns cached name immediately if available; otherwise ensures it is loaded
-- and invokes optional callback once resolved. Also caches the result.
function addon.MythicPlus.functions.EnsureDefaultHearthstoneName(callback)
	-- Try cache first
	if addon.MythicPlus.variables.hearthstoneName then
		if callback then callback(addon.MythicPlus.variables.hearthstoneName) end
		return addon.MythicPlus.variables.hearthstoneName
	end

	-- Attempt synchronous fetch (works if client has it cached)
	local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(6948)
	if name then
		addon.MythicPlus.variables.hearthstoneName = name
		if callback then callback(name) end
		return name
	end

	-- Fallback: request load and resolve asynchronously
	if Item and Item.CreateFromItemID then
		local eItem = Item:CreateFromItemID(6948)
		eItem:ContinueOnItemLoad(function()
			local loadedName = (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(6948)) or addon.MythicPlus.variables.hearthstoneName
			addon.MythicPlus.variables.hearthstoneName = loadedName
			if callback then callback(loadedName) end
		end)
	end

	return nil
end

-- Prime the cache early during init
addon.MythicPlus.functions.EnsureDefaultHearthstoneName()

-- PullTimer
addon.MythicPlus.variables.handled = false
addon.MythicPlus.variables.breakIt = false

addon.MythicPlus.variables.resetCooldownEncounterDifficult = {
	[3] = true,
	[4] = true,
	[5] = true,
	[6] = true,
	[7] = true,
	[9] = true,
	[14] = true,
	[15] = true,
	[16] = true,
	[17] = true,
	[18] = true,
	[33] = true,
	[151] = true,
	[208] = true, -- delves
}

function addon.MythicPlus.functions.addRCButton()
	local rcButton = CreateFrame("Button", "EnhanceQoLMythicPlus_ReadyCheck", ChallengesKeystoneFrame)
	rcButton:ClearAllPoints()
	rcButton:SetPoint("TOPLEFT", ChallengesKeystoneFrame, "TOPLEFT", 15, -15)
	rcButton:SetSize(110, 110)
	rcButton:SetHitRectInsets(15, 15, 15, 15)
	rcButton:SetScript("OnClick", function(self, button)
		if not self.readyCheckRunning then
			self.readyCheckRunning = true
			DoReadyCheck()
		end
	end)
	rcButton:RegisterEvent("READY_CHECK")
	rcButton:RegisterEvent("READY_CHECK_CONFIRM")
	rcButton:RegisterEvent("READY_CHECK_FINISHED")
	rcButton:SetScript("OnEvent", function(self, event, ...)
		if event == "READY_CHECK" then
			self.icon:SetVertexColor(1, 0.8, 0)
			self.icon:SetDesaturated(false)
			self.spin:Play()
			-- pulse animation for "waiting" state
			if self.iconPulse and not self.iconPulse:IsPlaying() then
				self.iconPulse:Play() -- start pulsing while we wait
			end
			self.readyCheckRunning = true
		elseif event == "READY_CHECK_CONFIRM" then
			local unit, ready = ...
			if not ready then
				self.notReady = true
				self.icon:SetVertexColor(1, 0.2, 0.2)
			end
		elseif event == "READY_CHECK_FINISHED" then
			if self.iconPulse and self.iconPulse:IsPlaying() then
				self.iconPulse:Stop() -- stop pulsing, restore full alpha
				self.icon:SetAlpha(1)
			end
			if not self.notReady then self.icon:SetVertexColor(0, 1, 0.3) end
			self.readyCheckRunning = false
			C_Timer.After(2, function()
				if self.readyCheckRunning then return end
				self.icon:SetVertexColor(1, 1, 1)
				self.notReady = false
				if not MouseIsOver(rcButton) then
					self.spin:Stop()
					self.ring:SetRotation(0)
				end
			end)
		end
	end)
	rcButton:SetFrameStrata("HIGH")

	local icon = rcButton:CreateTexture(nil, "ARTWORK", nil, 0)
	icon:SetPoint("CENTER", rcButton, "CENTER")
	icon:SetTexture("Interface\\AddOns\\EnhanceQoL\\Modules\\MythicPlus\\Art\\coreRC.tga")
	icon:SetSize(70, 70)
	rcButton.icon = icon

	-- pulse animation for "waiting" state
	local pulse = icon:CreateAnimationGroup()
	local fadeOut = pulse:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0.3)
	fadeOut:SetDuration(0.8)
	fadeOut:SetOrder(1)

	local fadeIn = pulse:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0.3)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(0.8)
	fadeIn:SetOrder(2)

	pulse:SetLooping("REPEAT")
	rcButton.iconPulse = pulse

	local ring = rcButton:CreateTexture(nil, "OVERLAY", nil, 1)
	ring:SetTexture("Interface\\AddOns\\EnhanceQoL\\Modules\\MythicPlus\\Art\\coreRing.tga")
	ring:SetSize(110, 110)
	ring:SetPoint("CENTER", rcButton, "CENTER")
	rcButton.ring = ring

	local spin = ring:CreateAnimationGroup()
	local rot = spin:CreateAnimation("Rotation")
	rot:SetDegrees(360)
	rot:SetDuration(24)
	spin:SetLooping("REPEAT")
	rcButton.spin = spin

	rcButton:SetScript("OnEnter", function(self, button)
		if not self.readyCheckRunning then spin:Play() end
	end)
	rcButton:SetScript("OnLeave", function(self, button)
		if not self.readyCheckRunning then
			spin:Stop()
			ring:SetRotation(0)
		end
	end)
	addon.MythicPlus.Buttons["EnhanceQoLMythicPlus_ReadyCheck"] = rcButton
	addon.MythicPlus.nrOfButtons = addon.MythicPlus.nrOfButtons + 1
end

function addon.MythicPlus.functions.addPullButton()
	local rcButton = CreateFrame("Button", "EnhanceQoLMythicPlus_PullTimer", ChallengesKeystoneFrame)
	rcButton:ClearAllPoints()
	rcButton:SetPoint("TOPRIGHT", ChallengesKeystoneFrame, "TOPRIGHT", -15, -15)
	rcButton:SetSize(110, 110)
	rcButton:SetHitRectInsets(15, 15, 15, 15)
	-- streamlined pull‑timer logic
	local function startPull(self, duration)
		self.remaining = duration
		self.icon:Hide()
		self.timerCountdown:SetText(duration)
		self.timerCountdown:Show()
		if self.remaining > 6 then
			self.timerCountdown:SetVertexColor(0, 1, 0)
		elseif self.remaining > 3 then
			self.timerCountdown:SetVertexColor(1, 1, 0)
		else
			self.timerCountdown:SetVertexColor(1, 0, 0)
		end
		-- blizzard / DBM alignment
		local _, _, _, _, _, _, _, instanceId = GetInstanceInfo()
		if addon.db["PullTimerType"] == 2 or addon.db["PullTimerType"] == 4 then C_PartyInfo.DoCountdown(duration) end
		if addon.db["PullTimerType"] == 3 or addon.db["PullTimerType"] == 4 then
			C_ChatInfo.SendAddonMessage("D4", ("PT\t%d\t%d"):format(duration, instanceId), IsInGroup(2) and "INSTANCE_CHAT" or "RAID")
		end
		if not addon.db["noChatOnPullTimer"] then C_ChatInfo.SendChatMessage(("PULL in %ds"):format(duration), "PARTY") end

		-- ticker updates local countdown (also handles chat, optional)
		self.ticker = C_Timer.NewTicker(1, function(t)
			self.remaining = self.remaining - 1
			if self.remaining > 6 then
				self.timerCountdown:SetVertexColor(0, 1, 0)
			elseif self.remaining > 3 then
				self.timerCountdown:SetVertexColor(1, 1, 0)
			else
				self.timerCountdown:SetVertexColor(1, 0, 0)
			end
			if self.remaining <= 0 then
				t:Cancel()
				self.timerCountdown:SetText("0")
				self.icon:Show()
				self.timerCountdown:Hide()
				self.running = false
				if not MouseIsOver(rcButton) then
					self.spin:Stop()
					self.ring:SetRotation(0)
				end

				if not addon.db["noChatOnPullTimer"] then C_ChatInfo.SendChatMessage(">>PULL NOW<<", "PARTY") end
				if addon.db["autoKeyStart"] and C_ChallengeMode.GetSlottedKeystoneInfo() then
					C_ChallengeMode.StartChallengeMode()
					ChallengesKeystoneFrame:Hide()
				end
			else
				self.timerCountdown:SetText(self.remaining)
				if not addon.db["noChatOnPullTimer"] then C_ChatInfo.SendChatMessage(("PULL in %d"):format(self.remaining), "PARTY") end
			end
		end)
		self.running = true
	end

	local function cancelPull(self)
		if self.ticker then self.ticker:Cancel() end
		self.icon:Show()
		self.timerCountdown:Hide()
		self.running = false
		if not MouseIsOver(rcButton) then
			self.spin:Stop()
			self.ring:SetRotation(0)
		end
		C_PartyInfo.DoCountdown(0) -- abort Blizzard countdown
		if not addon.db["noChatOnPullTimer"] then C_ChatInfo.SendChatMessage("PULL Canceled", "PARTY") end
	end

	rcButton:RegisterForClicks("RightButtonDown", "LeftButtonDown")
	rcButton:SetScript("OnClick", function(self, button)
		if self.running then
			cancelPull(self)
			return
		end

		local duration = (button == "RightButton") and addon.db["pullTimerShortTime"] or addon.db["pullTimerLongTime"]
		startPull(self, duration)
	end)
	rcButton:SetFrameStrata("HIGH")

	local icon = rcButton:CreateTexture(nil, "ARTWORK", nil, 0)
	icon:SetPoint("CENTER", rcButton, "CENTER")
	icon:SetTexture("Interface\\AddOns\\EnhanceQoL\\Modules\\MythicPlus\\Art\\corePull.tga")
	icon:SetSize(72, 72)
	rcButton.icon = icon

	local timerCountdown = rcButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	timerCountdown:SetPoint("CENTER", rcButton, "CENTER", 0, 0)
	timerCountdown:SetFont(addon.variables.defaultFont, 20, "OUTLINE")
	timerCountdown:SetVertexColor(1, 1, 0)
	timerCountdown:Hide()
	rcButton.timerCountdown = timerCountdown

	-- pulse animation for "waiting" state
	local pulse = icon:CreateAnimationGroup()
	local fadeOut = pulse:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0.3)
	fadeOut:SetDuration(0.8)
	fadeOut:SetOrder(1)

	local fadeIn = pulse:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0.3)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(0.8)
	fadeIn:SetOrder(2)

	pulse:SetLooping("REPEAT")
	rcButton.iconPulse = pulse

	local ring = rcButton:CreateTexture(nil, "OVERLAY", nil, 1)
	ring:SetTexture("Interface\\AddOns\\EnhanceQoL\\Modules\\MythicPlus\\Art\\coreRing.tga")
	ring:SetSize(110, 110)
	ring:SetPoint("CENTER", rcButton, "CENTER")
	rcButton.ring = ring

	local spin = ring:CreateAnimationGroup()
	local rot = spin:CreateAnimation("Rotation")
	rot:SetDegrees(360)
	rot:SetDuration(24)
	spin:SetLooping("REPEAT")
	rcButton.spin = spin

	rcButton:SetScript("OnEnter", function(self, button)
		if not self.running then spin:Play() end
	end)
	rcButton:SetScript("OnLeave", function(self, button)
		if not self.running then
			spin:Stop()
			ring:SetRotation(0)
		end
	end)
	addon.MythicPlus.Buttons["EnhanceQoLMythicPlus_PullTimer"] = rcButton
	addon.MythicPlus.nrOfButtons = addon.MythicPlus.nrOfButtons + 1
end

function addon.MythicPlus.functions.addButton(frame, name, text, call)
	local button = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
	button:SetPoint("TOPRIGHT", frame, "TOPLEFT", 0, (addon.MythicPlus.nrOfButtons * -40))
	button:SetSize(140, 40)
	button:SetText(text)
	button:SetNormalFontObject("GameFontNormalLarge")
	button:SetHighlightFontObject("GameFontHighlightLarge")
	button:RegisterForClicks("RightButtonDown", "LeftButtonDown")
	button:SetScript("OnClick", call)
	if UnitIsGroupLeader("Player") == false then button:Hide() end
	addon.MythicPlus.Buttons[name] = button
	addon.MythicPlus.nrOfButtons = addon.MythicPlus.nrOfButtons + 1
end

function addon.MythicPlus.functions.removeExistingButton()
	for _, button in pairs(addon.MythicPlus.Buttons) do
		if button then
			button:Hide() -- Versteckt den Button
			button:SetParent(nil) -- Entfernt den Parent-Frame

			-- Entferne alle registrierten Event-Handler und Scripte
			button:SetScript("OnClick", nil)
			button:SetScript("OnEnter", nil)
			button:SetScript("OnLeave", nil)
			button:SetScript("OnUpdate", nil)
			button:SetScript("OnEvent", nil)

			-- Entferne alle Texturen und andere Frames
			button:UnregisterAllEvents()
			button:ClearAllPoints()
		end
	end
	addon.MythicPlus.Buttons = {}
	addon.MythicPlus.nrOfButtons = 0
end

-- dumb the map cursor position: /dump WorldMapFrame:GetMapID(), WorldMapFrame.ScrollContainer:GetNormalizedCursorPosition()
-- delete name cache: /run EnhanceQoL.db.teleportNameCache = nil
-- WorldMapFrame:GetMapID()
addon.MythicPlus.variables.portalCompendium = {

	[9999] = {
		headline = HOME,
		spells = {
			-- [1233637] = { zoneID = 2352 },
		},
	},
	[130] = {
		headline = EXPANSION_NAME11 or "Midnight",
		spells = {
			[1254559] = { text = "MC", cId = { [560] = true }, mapID = 2501, locID = 2437, x = 0.4368, y = 0.3963, zoneID = 2501 },
			[1254563] = { text = "NPX", cId = { [559] = true }, mapID = 2556, locID = 2405, x = 0.6484, y = 0.6158, zoneID = 2556 },
			[1254572] = { text = "MT", cId = { [558] = true }, mapID = 2511, locID = 2424, x = 0.6329, y = 0.1549, zoneID = 2511 },
			-- [1254580] = { text = "DON", mapID = 2514, locID = 2437, x = 0.2969, y = 0.8454, zoneID = 2514 },
			[1254400] = { text = "WRS", cId = { [557] = true }, mapID = 2494, locID = 2395, x = 0.3543, y = 0.7908, zoneID = 2494 },
			-- [1254569] = { text = "MR", mapID = 2433, locID = 2393, x = 0.5719, y = 0.6097, zoneID = 2433 },
			-- [1254577] = { text = "TBV", mapID = 2500, locID = 2413, x = 0.2635, y = 0.7790, zoneID = 2500 },
			-- [1254567] = { text = "VSA", mapID = 2572, locID = 2405, x = 0.5145, y = 0.1918, zoneID = 2572 },
		},
	},
	[120] = {
		headline = EXPANSION_NAME10,
		spells = {
			[445269] = { text = "SV", cId = { [501] = true }, mapID = 2652, locID = 2214, x = 0.4249, y = 0.0842, zoneID = 2341 },
			[445416] = { text = "COT", cId = { [502] = true }, mapID = 2663, locID = 2255, x = 0.4667, y = 0.6922, zoneID = 2343 },
			[445414] = { text = "DAWN", cId = { [505] = true }, mapID = 2662, locID = 2215, x = 0.5492, y = 0.6276, zoneID = 2359 },
			[445417] = { text = "ARAK", cId = { [503] = true }, mapID = 2660, locID = 2255, x = 0.494, y = 0.808, zoneID = 2357 },
			[1216786] = { text = "FLOOD", cId = { [525] = true }, mapID = 2773, locID = 2214, x = 0.4201, y = 0.3952, zoneID = 2387 },
			[1237215] = { text = "ED", cId = { [542] = true }, mapID = 2830, locID = 2371, x = 0.6520, y = 0.6837, zoneID = 2449 },
			[445440] = { text = "BREW", cId = { [506] = true }, mapID = 2661, locID = 2248, x = 0.7656, y = 0.4383, zoneID = 2335 },
			[445444] = { text = "PSF", cId = { [499] = true }, mapID = 2649, locID = 2215, x = 0.4129, y = 0.4939, zoneID = 2308 },
			[445441] = { text = "DFC", cId = { [504] = true }, mapID = 2651, locID = 2214, x = 0.5528, y = 0.2152, zoneID = 2303 },
			[445443] = { text = "ROOK", cId = { [500] = true }, mapID = 2648, locID = 2339, x = 0.3185, y = 0.3576, zoneID = 2316 },
			[448126] = { text = "ENGI", isToy = true, toyID = 221966, isEngineering = true, zoneID = 2274 },
			[446540] = { text = "DORN", isClassTP = "MAGE", locID = 2339, x = 0.4249, y = 0.2905, zoneID = 2339 },
			[446534] = { text = "DORN", isMagePortal = true, locID = 2339, x = 0.4249, y = 0.2905, zoneID = 2339 },
			[1226482] = { text = "LOU", isRaid = true, locID = 2346, x = 0.4151, y = 0.4880, zoneID = 2346 },
			[1223041] = { text = addon.MythicPlus.variables.hearthstoneName or "HS", isItem = true, itemID = 234389, isRaid = true, icon = 3718248, map = 2406, zoneID = 2406 },
			[1239155] = { text = "MFO", isRaid = true, locID = 2371, x = 0.4153, y = 0.2141, zoneID = 2460 },
			[467470] = { text = DELVE_LABEL, isToy = true, toyID = 230850, isHearthstone = true },
			[1234526] = { text = DELVE_LABEL, isToy = true, toyID = 243056, isHearthstone = true, icon = 7137505, locID = 2339, x = 0.4775, y = 0.4447, zoneID = 2339 },
		},
	},
	[110] = {
		headline = EXPANSION_NAME9,
		spells = {

			[424197] = {
				text = "DOTI",
				cId = { [463] = true, [464] = true },
				mapID = { [463] = { mapID = 2579, zoneID = 2190 }, [464] = { mapID = 2579, zoneID = 2195 } }, -- Checks for zoneID + mapID for Mega Dungeons},
				locID = 2025,
				x = 0.6108,
				y = 0.8440,
			},
			[393256] = { text = "RLP", cId = { [399] = true }, mapID = 2521, locID = 2022, x = 0.6006, y = 0.7568, zoneID = 2095 },
			[393262] = { text = "NO", cId = { [400] = true }, mapID = 2516, locID = 2023, x = 0.6078, y = 0.3891, zoneID = 2093 },
			[393267] = { text = "BH", cId = { [405] = true }, mapID = 2520, locID = 2024, x = 0.1140, y = 0.4860, zoneID = 2096 },
			[393273] = { text = "AA", cId = { [402] = true }, mapID = 2526, locID = 2025, x = 0.5827, y = 0.4239, zoneID = 2097 },
			[393276] = { text = "NELT", cId = { [404] = true }, locID = 2022, zoneID = 2080, x = 0.2572, y = 0.5631 },
			[393279] = { text = "AV", cId = { [401] = true }, locID = 2024, zoneID = 2073, x = 0.3878, y = 0.6438 },
			[393283] = { text = "HOI", cId = { [406] = true }, locID = 2025, x = 0.5911, y = 0.6050, zoneID = 2082 },
			[393222] = { text = "ULD", cId = { [403] = true }, locID = 15, x = 0.4112, y = 0.1023, zoneID = 2071 },
			[432254] = { text = "VOTI", isRaid = true, locID = 2025, x = 0.7465, y = 0.5512, zoneID = 2119 },
			[432258] = { text = "AMIR", isRaid = true, locID = 2200, x = 0.2730, y = 0.3109, zoneID = 2232 },
			[432257] = { text = "ASC", isRaid = true, locID = 2133, x = 0.4846, y = 0.1208, zoneID = 2166 },
			[386379] = { text = "ENGI", isToy = true, toyID = 198156, isEngineering = true, zoneID = 1978 },
			-- Valdrakken (Dragonflight)
			[395277] = { text = "Vald", isClassTP = "MAGE", locID = 2112, x = 0.5432, y = 0.4788, zoneID = 2112 },
			[395289] = { text = "Vald", isMagePortal = true, locID = 2112, x = 0.5432, y = 0.4788, zoneID = 2112 },
		},
	},
	[100] = {
		headline = EXPANSION_NAME8,
		spells = {
			[354462] = { text = "NW", cId = { [376] = true }, locID = 1533, x = 0.4010, y = 0.5523, zoneID = 1666 },
			[354463] = { text = "PF", cId = { [379] = true }, locID = 1536, x = 0.5923, y = 0.6492, zoneID = 1674 },
			[354464] = { text = "MISTS", cId = { [375] = true }, locID = 1565, x = 0.3543, y = 0.5416, zoneID = 1669 },
			[354465] = { text = "HOA", cId = { [378] = true }, mapID = 2287, locID = 1525, x = 0.7835, y = 0.4895, zoneID = 1663 },
			[354466] = { text = "SOA", cId = { [381] = true }, locID = 1533, x = 0.5851, y = 0.2851, zoneID = 1693 },
			[354467] = { text = "TOP", cId = { [382] = true }, mapID = 2293, locID = 1536, x = 0.5301, y = 0.5279, zoneID = 1683 },
			[354468] = { text = "DOS", cId = { [377] = true }, locID = 1565, x = 0.6855, y = 0.6653, zoneID = 1679 },
			[354469] = { text = "SD", cId = { [380] = true }, locID = 1525, x = 0.5109, y = 0.2994, zoneID = 1675 },
			[367416] = {
				text = "TAZA",
				cId = { [391] = true, [392] = true },
				mapID = { [391] = { mapID = 2441, zoneID = 1989 }, [392] = { mapID = 2441, zoneID = 1995 } }, -- Checks for zoneID + mapID for Mega Dungeons
				textID = { [391] = "STREET", [392] = "GAMBIT" },
				locID = 2371,
				x = 0.6355,
				y = 0.7016,
			},
			[373190] = { text = "CN", isRaid = true, locID = 1525, x = 0.4631, y = 0.4142, zoneID = 1735 }, -- Raids
			[373192] = { text = "SFO", isRaid = true, locID = 1970, x = 0.8039, y = 0.5344, zoneID = 2047 }, -- Raids
			[373191] = { text = "SOD", isRaid = true, locID = 1543, x = 0.6963, y = 0.3192, zoneID = 1998 }, -- Raids
			[324031] = { text = "ENGI", isToy = true, toyID = 172924, isEngineering = true, zoneID = 1550 },
			-- Oribos (Shadowlands)
			[344587] = { text = "Orib", isClassTP = "MAGE", locID = 1670, x = 0.5229, y = 0.7460, zoneID = 1670 },
			[344597] = { text = "Orib", isMagePortal = true, locID = 1670, x = 0.5229, y = 0.7460, zoneID = 1670 },

			[325624] = { text = "Maw", isItem = true, itemID = 180817, icon = 442739, locID = 1543, x = 0.4727, y = 0.4361, zoneID = 1543 },
		},
	},
	[90] = {
		headline = EXPANSION_NAME7,
		spells = {
			[410071] = { text = "FH", cId = { [245] = true }, locID = 895, x = 0.8445, y = 0.7880, zoneID = 936 },
			[410074] = { text = "UR", cId = { [251] = true }, locID = 863, x = 0.5109, y = 0.6456, zoneID = 1041 },
			[373274] = { text = "WORK", cId = { [369] = true, [370] = true }, mapID = 2097, locID = 1462, x = 0.7285, y = 0.3647, zoneID = 1490 },
			[424167] = { text = "WM", cId = { [248] = true }, locID = 896, x = 0.3364, y = 0.1244, zoneID = 1015 },
			[424187] = { text = "AD", cId = { [244] = true }, locID = 862, x = 0.4350, y = 0.3946, zoneID = 934 },
			[445418] = { text = "SIEG", faction = FACTION_ALLIANCE, cId = { [353] = true }, locID = 1161, x = 0.7560, y = 0.1926, zoneID = 1162 },
			[464256] = { text = "SIEG", faction = FACTION_HORDE, cId = { [353] = true }, locID = 895, x = 0.8829, y = 0.5097, zoneID = 1162 },
			[467553] = { text = "ML", faction = FACTION_ALLIANCE, cId = { [247] = true }, mapID = 1594, locID = 862, x = 0.3928, y = 0.7148, zoneID = 1010 },
			[467555] = { text = "ML", faction = FACTION_HORDE, cId = { [247] = true }, mapID = 1594, locID = 862, x = 0.5607, y = 0.5981, zoneID = 1010 },
			[299083] = { text = "ENGI", isToy = true, toyID = 168807, isEngineering = true, zoneID = 876 },
			[299084] = { text = "ENGI", isToy = true, toyID = 168808, isEngineering = true, zoneID = 875 },
			-- Boralus (BfA)
			[281403] = { text = "Borl", isClassTP = "MAGE", faction = FACTION_ALLIANCE, locID = 1161, x = 0.6960, y = 0.1996, zoneID = 1161 },
			[281400] = { text = "Borl", isMagePortal = true, faction = FACTION_ALLIANCE, locID = 1161, x = 0.6960, y = 0.1996, zoneID = 1161 },
			-- Dazar'alor (BfA)
			[281404] = { text = "Daza", isClassTP = "MAGE", faction = FACTION_HORDE, locID = 1165, x = 0.4978, y = 0.4114, zoneID = 1165 },
			[281402] = { text = "Daza", isMagePortal = true, faction = FACTION_HORDE, locID = 1165, x = 0.4978, y = 0.4114, zoneID = 1165 },
			[396591] = { text = "HS", isItem = true, itemID = 202046, isHearthstone = true, icon = 2203919, zoneID = 942, x = 0.4069, y = 0.3647 },

			[289284] = {
				text = addon.MythicPlus.variables.hearthstoneName or "HS",
				isItem = true,
				itemID = 166560,
				isHearthstone = true,
				icon = 804960,
				equipSlot = 11,
				faction = FACTION_ALLIANCE,
				locID = 1161,
				x = 0.6960,
				y = 0.1996,
				zoneID = 1161,
			},
			[289283] = {
				text = addon.MythicPlus.variables.hearthstoneName or "HS",
				isItem = true,
				itemID = 166559,
				isHearthstone = true,
				icon = 804962,
				equipSlot = 11,
				faction = FACTION_HORDE,
				locID = 1165,
				x = 0.4978,
				y = 0.4114,
				zoneID = 1165,
			},
		},
	},
	[80] = {
		timerunner = 2,
		headline = EXPANSION_NAME6,
		spells = {
			[424153] = { text = "BRH", cId = { [199] = true }, locID = 641, x = 0.3711, y = 0.5028, zoneID = 751 },
			[393766] = { text = "COS", cId = { [210] = true }, locID = 680, x = 0.5062, y = 0.6545, zoneID = 761 },
			[424163] = { text = "DHT", cId = { [198] = true }, locID = 641, x = 0.5899, y = 0.3109, zoneID = 733 },
			[393764] = { text = "HOV", cId = { [200] = true }, locID = 634, x = 0.7254, y = 0.7047, zoneID = 704 },
			[410078] = { text = "NL", cId = { [206] = true }, locID = 650, x = 0.4942, y = 0.6832, zoneID = 731 },
			[373262] = { text = "KARA", cId = { [227] = true, [234] = true }, locID = 42, x = 0.4705, y = 0.7485, zoneID = 350 },
			[250796] = { text = "ENGI", isToy = true, toyID = 151652, isEngineering = true, zoneID = 905 },
			[222695] = { text = "DALA", isToy = true, toyID = 140192, isHearthstone = true, icon = 1444943, locID = 627, x = 0.6042, y = 0.4440, zoneID = 627 },
			-- Dalaran (Broken Isles, Legion)
			[224869] = { text = "DalB", isClassTP = "MAGE", locID = 627, x = 0.6042, y = 0.4440, zoneID = 627 },
			[224871] = { text = "DalB", isMagePortal = true, locID = 627, x = 0.6042, y = 0.4440, zoneID = 627 },
			[1254551] = { text = "SotT", cId = { [239] = true }, mapID = 903, locID = 882, x = 0.2503, y = 0.528, zoneID = 903 },
			[227334] = { text = "FMW", isToy = true, toyID = 141605, isHearthstone = true, icon = 132161 },
			[82674] = { text = addon.MythicPlus.variables.hearthstoneName or "HS", isItem = true, itemID = 64457, isHearthstone = true, icon = 458240 },
			[223444] = {
				text = addon.MythicPlus.variables.hearthstoneName or "HS",
				isToy = true,
				toyID = 140324,
				isHearthstone = true,
				icon = 237445,
				map = 680,
				locID = 680,
				x = 0.3732,
				y = 0.4405,
				zoneID = 680,
			},

			[200061] = { text = "ENGI", isItem = true, itemID = { 144341, 132523 }, isEngineering = true, icon = 1405815, isReaves = true, zoneID = 619 },
			[231054] = {
				text = addon.MythicPlus.variables.hearthstoneName or "HS",
				isItem = true,
				itemID = 142469,
				isHearthstone = true,
				icon = 1391739,
				equipSlot = 11,
				locID = 42,
				x = 0.4705,
				y = 0.7485,
				zoneID = 350,
			},
		},
	},
	[70] = {
		headline = EXPANSION_NAME5,
		spells = {
			[159897] = { text = "AUCH", cId = { [164] = true }, locID = 535, x = 0.4619, y = 0.7395, zoneID = 593 },
			[159895] = { text = "BSM", cId = { [163] = true }, locID = 525, x = 0.4978, y = 0.2464, zoneID = 573 },
			[159901] = { text = "EB", cId = { [168] = true }, locID = 543, x = 0.5946, y = 0.4555, zoneID = 620 },
			[159900] = { text = "GD", cId = { [166] = true }, locID = 543, x = 0.5504, y = 0.3174, zoneID = 606 },
			[159896] = { text = "ID", cId = { [169] = true }, locID = 543, x = 0.4536, y = 0.1345, zoneID = 595 },
			[159899] = { text = "SBG", cId = { [165] = true }, locID = 539, x = 0.3185, y = 0.4257, zoneID = 574 },
			[1254557] = { text = "SR", cId = { [161] = true }, mapID = 601, locID = 542, x = 0.3555, y = 0.3360, zoneID = 601 },
			[159902] = { text = "UBRS", cId = { [167] = true }, locID = 36, x = 0.2013, y = 0.2600, zoneID = 617 },
			[163830] = { text = "ENGI", isToy = true, toyID = 112059, isEngineering = true, zoneID = 572 },
			[171253] = { text = GARRISON_LOCATION_TOOLTIP, isToy = true, toyID = 110560, isHearthstone = true },
			[189838] = { text = GARRISON_LOCATION_TOOLTIP, isItem = true, itemID = 128353, icon = 134234, isHearthstone = true },
			[194812] = { text = "ESM", isToy = true, toyID = 129929, icon = 458243 },

			[49359] = { text = "THER", isClassTP = "MAGE", faction = FACTION_ALLIANCE, locID = 70, x = 0.6628, y = 0.4828, zoneID = 70 },
			[49360] = { text = "THER", isMagePortal = true, faction = FACTION_ALLIANCE, locID = 70, x = 0.6628, y = 0.4828, zoneID = 70 },
			[49358] = { text = "STON", isClassTP = "MAGE", faction = FACTION_HORDE, locID = 51, x = 0.4703, y = 0.5505, zoneID = 51 },
			[49361] = { text = "STON", isMagePortal = true, faction = FACTION_HORDE, locID = 51, x = 0.4703, y = 0.5505, zoneID = 51 },

			[176248] = { text = "STORM", isClassTP = "MAGE", faction = FACTION_ALLIANCE, locID = 622, x = 0.4715, y = 0.4759, zoneID = 622 },
			[176246] = { text = "STORM", isMagePortal = true, faction = FACTION_ALLIANCE, locID = 622, x = 0.4715, y = 0.4759, zoneID = 622 },
			[176242] = { text = "WARS", isClassTP = "MAGE", faction = FACTION_HORDE, locID = 624, x = 0.5217, y = 0.4921, zoneID = 624 },
			[176244] = { text = "WARS", isMagePortal = true, faction = FACTION_HORDE, locID = 624, x = 0.5217, y = 0.4921, zoneID = 624 },

			[175608] = { text = "KARABOR", icon = 133316, isItem = true, itemID = 118663, faction = FACTION_ALLIANCE, locID = 539, x = 0.3398, y = 0.2646, zoneID = 539 },
			[175604] = { text = "BLADESPIRE", icon = 133283, isItem = true, itemID = 118662, faction = FACTION_HORDE, locID = 525, x = 0.2778, y = 0.4268, zoneID = 525 },
		},
	},
	[60] = {
		headline = EXPANSION_NAME4,
		spells = {
			[131225] = { text = "GSS", cId = { [57] = true }, x = 0.1547, y = 0.7234, zoneID = 437, locID = 1530 },
			[131222] = { text = "MP", cId = { [60] = true }, x = 0.8051, y = 0.3289, zoneID = 453, locID = 390 },
			[131232] = { text = "SCHO", cId = { [76] = true }, x = 0.6975, y = 0.7352, zoneID = 476, locID = 22 },
			[131231] = { text = "SH", cId = { [77] = true }, x = 0.8529, y = 0.3246, zoneID = 431, locID = 18 },
			[131229] = { text = "SM", cId = { [78] = true }, x = 0.8476, y = 0.3035, zoneID = 435, locID = 18 },
			[131228] = { text = "SN", cId = { [59] = true }, x = 0.3460, y = 0.8149, zoneID = 458, locID = 388 },
			[131206] = { text = "SPM", cId = { [58] = true }, x = 0.3663, y = 0.4734, zoneID = 443, locID = 379 },
			[131205] = { text = "SB", cId = { [56] = true }, x = 0.3603, y = 0.6911, zoneID = 440, locID = 376 },
			[131204] = { text = "TJS", cId = { [2] = true }, x = 0.5612, y = 0.5781, zoneID = 429, locID = 371 },
			[126755] = { text = "ENGI", isToy = true, toyID = 87215, isEngineering = true, zoneID = 424 },
			[132621] = { text = "VALE", isClassTP = "MAGE", faction = FACTION_ALLIANCE, x = 0.8637, y = 0.6319, zoneID = 1530, locID = 1530 },
			[132620] = { text = "VALE", isMagePortal = true, faction = FACTION_ALLIANCE, x = 0.8637, y = 0.6319, zoneID = 1530, locID = 1530 },
			[132627] = { text = "VALE", isClassTP = "MAGE", faction = FACTION_HORDE, x = 0.6186, y = 0.2213, zoneID = 1530, locID = 1530 },
			[132625] = { text = "VALE", isMagePortal = true, faction = FACTION_HORDE, x = 0.6186, y = 0.2213, zoneID = 1530, locID = 1530 },

			-- Alliance beacon
			[140295] = {
				text = addon.MythicPlus.variables.hearthstoneName or "HS",
				isToy = true,
				toyID = 95567,
				isHearthstone = true,
				icon = 801132,
				map = { [504] = true, [508] = true },
				faction = FACTION_ALLIANCE,
				x = 0.6437,
				y = 0.7449,
				zoneID = 504,
				locID = 504,
			},
			-- Horde beacon
			[140300] = {
				text = addon.MythicPlus.variables.hearthstoneName or "HS",
				isToy = true,
				toyID = 95568,
				isHearthstone = true,
				icon = 838819,
				map = { [504] = true, [508] = true },
				faction = FACTION_HORDE,
				x = 0.3352,
				y = 0.3324,
				zoneID = 504,
				locID = 504,
			},

			[145430] = {
				text = "HS",
				isItem = true,
				itemID = 103678,
				isHearthstone = true,
				icon = 643915,
				equipSlot = 13,
				x = 0.4285,
				y = 0.5477,
				zoneID = 554,
				locID = 554,
			},
		},
	},
	[50] = {
		headline = EXPANSION_NAME3,
		spells = {
			[445424] = { text = "GB", cId = { [507] = true }, x = 0.1917, y = 0.5416, zoneID = 293, locID = 241 },
			[424142] = { text = "TOTT", cId = { [456] = true }, x = 0.4799, y = 0.4035, zoneID = 323, locID = 203 },
			[410080] = { text = "VP", cId = { [438] = true }, x = 0.7656, y = 0.8428, zoneID = 325, locID = 1527 },
			-- Tol Barad (Cata)
			[88342] = { text = "TolB", isClassTP = "MAGE", faction = FACTION_ALLIANCE, x = 0.7357, y = 0.6079, zoneID = 245, locID = 245 },
			[88345] = { text = "TolB", isMagePortal = true, faction = FACTION_ALLIANCE, x = 0.5480, y = 0.7819, zoneID = 245, locID = 245 },
			[88344] = { text = "TolB", isClassTP = "MAGE", faction = FACTION_HORDE, x = 0.5480, y = 0.7819, zoneID = 245, locID = 245 },
			[88346] = { text = "TolB", isMagePortal = true, faction = FACTION_HORDE, x = 0.7357, y = 0.6079, zoneID = 245, locID = 245 },

			[80256] = { text = "DH", isItem = true, itemID = 58487, isHearthstone = true, icon = 463898, x = 0.4978, y = 0.5523, zoneID = 207, locID = 207 },
			[59317] = { text = "VC", isToy = true, toyID = 43824, isHearthstone = true, icon = 133743, map = 125, x = 0.2372, y = 0.4670, zoneID = 125, locID = 125 },

			[89597] = {
				text = addon.MythicPlus.variables.hearthstoneName or "HS",
				isItem = true,
				itemID = 63379,
				isHearthstone = true,
				icon = 456571,
				faction = FACTION_ALLIANCE,
				equipSlot = 19,
				x = 0.7357,
				y = 0.6079,
				zoneID = 245,
				locID = 245,
			},
			[89598] = {
				text = addon.MythicPlus.variables.hearthstoneName or "HS",
				isItem = true,
				itemID = 63378,
				isHearthstone = true,
				icon = 456564,
				faction = FACTION_HORDE,
				equipSlot = 19,
				x = 0.5480,
				y = 0.7819,
				zoneID = 245,
				locID = 245,
			},
		},
	},
	[40] = {
		headline = EXPANSION_NAME2,
		spells = {
			[67833] = { text = "ENGI", isToy = true, toyID = 48933, isEngineering = true, zoneID = 113 },
			[73324] = { text = "DALA", isItem = true, itemID = 52251, isHearthstone = true, icon = 133308, x = 0.2372, y = 0.4670, zoneID = 125, locID = 125 },
			[54406] = {
				text = "DALA",
				isItem = true,
				itemID = { 40586, 48954, 48955, 48956, 48957, 45688, 45689, 45690, 45691, 44934, 44935, 51560, 51558, 51559, 51557, 40585 },
				ownedOnly = true,
				isHearthstone = true,
				icon = 133415,
				equipSlot = 11,
				x = 0.2372,
				y = 0.4670,
				zoneID = 125,
				locID = 125,
			},
			-- Dalaran (Northrend, WotLK)
			[53140] = { text = "DalN", isClassTP = "MAGE", x = 0.2372, y = 0.4670, zoneID = 125, locID = 125 },
			[53142] = { text = "DalN", isMagePortal = true, x = 0.2372, y = 0.4670, zoneID = 125, locID = 125 },

			[66238] = { text = "ATG", isItem = true, itemID = 46874, isHearthstone = true, icon = 135026, equipSlot = 19, x = 0.7166, y = 0.2152, zoneID = 118, locID = 118 },
			[1254555] = { text = "POS", cId = { [556] = true }, mapID = 184, x = 0.5467, y = 0.9162, zoneID = 184, locID = 118 },
		},
	},
	[30] = {
		headline = EXPANSION_NAME1,
		spells = {
			-- Shattrath (TBC)
			[245173] = { text = "BT", isToy = true, toyID = 151016, isHearthstone = true, x = 0.7106, y = 0.4609, zoneID = 340, locID = 104 },
			[33690] = { text = "Shat", isClassTP = "MAGE", x = 0.5528, y = 0.3909, zoneID = 111, locID = 111 },
			[33691] = { text = "Shat", isMagePortal = true, x = 0.5528, y = 0.3909, zoneID = 111, locID = 111 },
			[32271] = { text = "Exod", isClassTP = "MAGE", faction = FACTION_ALLIANCE, x = 0.4787, y = 0.5900, zoneID = 103, locID = 103 }, -- Teleport: Exodar
			[32266] = { text = "Exod", isMagePortal = true, faction = FACTION_ALLIANCE, x = 0.4787, y = 0.5900, zoneID = 103, locID = 103 }, -- Portal: Exodar
			[32272] = { text = "SMC", isClassTP = "MAGE", faction = FACTION_HORDE, x = 0.7214, y = 0.5997, zoneID = 110, locID = 110 }, -- Teleport: Silvermoon
			[32267] = { text = "SMC", isMagePortal = true, faction = FACTION_HORDE, x = 0.7214, y = 0.5997, zoneID = 110, locID = 110 }, -- Portal: Silvermoon

			[36941] = { text = "ENGI", isToy = true, toyID = 30544, isEngineering = true, isGnomish = true, x = 0.6090, y = 0.7048, zoneID = 105, locID = 105 },
			[36890] = { text = "ENGI", isToy = true, toyID = 30542, isEngineering = true, isGoblin = true, x = 0.3137, y = 0.6660, zoneID = 109, locID = 109 },

			[41234] = {
				text = addon.MythicPlus.variables.hearthstoneName or "HS",
				isItem = true,
				itemID = 32757,
				isHearthstone = true,
				icon = 133279,
				equipSlot = 2,
				x = 0.7106,
				y = 0.4609,
				zoneID = 340,
				locID = 104,
			},
			-- Atiesh variants are class-specific: map IDs by class so we can pick the right one
			[28148] = {
				text = "KARA",
				isItem = true,
				itemID = { 22589, 22632, 22630, 22631 },
				classItemID = { MAGE = 22589, DRUID = 22632, WARLOCK = 22630, PRIEST = 22631 },
				isHearthstone = true,
				icon = 135226,
				equipSlot = 16,
				locID = 42,
				x = 0.4705,
				y = 0.7485,
				zoneID = 350,
			},
			[39937] = { text = addon.MythicPlus.variables.hearthstoneName or "HS", isItem = true, itemID = 28585, isHearthstone = true, icon = 132566, equipSlot = 8 },
		},
	},
	[20] = {
		headline = EXPANSION_NAME0,
		spells = {
			-- Allianz
			[3561] = { text = "SW", isClassTP = "MAGE", faction = FACTION_ALLIANCE, locID = 84, x = 0.4571, y = 0.9038, zoneID = 84 },
			[10059] = { text = "SW", isMagePortal = true, faction = FACTION_ALLIANCE, locID = 84, x = 0.4571, y = 0.9038, zoneID = 84 },
			[3562] = { text = "IF", isClassTP = "MAGE", faction = FACTION_ALLIANCE, locID = 87, x = 0.2551, y = 0.0914, zoneID = 87 },
			[11416] = { text = "IF", isMagePortal = true, faction = FACTION_ALLIANCE, locID = 87, x = 0.2551, y = 0.0914, zoneID = 87 },
			[3565] = { text = "Darn", isClassTP = "MAGE", faction = FACTION_ALLIANCE, locID = 62, x = 0.4595, y = 0.1972, zoneID = 62 },
			[11419] = { text = "Darn", isMagePortal = true, faction = FACTION_ALLIANCE, locID = 62, x = 0.4595, y = 0.1972, zoneID = 62 },

			-- Horde
			[3567] = { text = "Orgr", isClassTP = "MAGE", faction = FACTION_HORDE, locID = 85, x = 0.5265, y = 0.8984, zoneID = 85 },
			[11417] = { text = "Orgr", isMagePortal = true, faction = FACTION_HORDE, locID = 85, x = 0.5265, y = 0.8984, zoneID = 85 },
			[3563] = { text = "UC", isClassTP = "MAGE", faction = FACTION_HORDE, locID = 90, x = 0.8110, y = 0.2105, zoneID = 90 },
			[11418] = { text = "UC", isMagePortal = true, faction = FACTION_HORDE, locID = 90, x = 0.8110, y = 0.2105, zoneID = 90 },
			[3566] = { text = "ThBl", isClassTP = "MAGE", faction = FACTION_HORDE, locID = 88, x = 0.4667, y = 0.4921, zoneID = 88 },
			[11420] = { text = "ThBl", isMagePortal = true, faction = FACTION_HORDE, locID = 88, x = 0.4667, y = 0.4921, zoneID = 88 },

			[23453] = { text = "ENGI", isToy = true, toyID = 18986, isEngineering = true, isGnomish = true, locID = 71, x = 0.5133, y = 0.3066, zoneID = 71 },
			[23442] = { text = "ENGI", isToy = true, toyID = 18984, isEngineering = true, isGoblin = true, locID = 83, x = 0.6090, y = 0.4913, zoneID = 83 },

			[89157] = { text = "SW", isItem = true, itemID = 65360, isHearthstone = true, icon = 461812, equipSlot = 15, faction = FACTION_ALLIANCE, locID = 84, x = 0.4571, y = 0.9038, zoneID = 84 },
			[1221360] = { text = "SW", isItem = true, itemID = 63206, isHearthstone = true, icon = 461811, equipSlot = 15, faction = FACTION_ALLIANCE, locID = 84, x = 0.4571, y = 0.9038, zoneID = 84 },
			[1221359] = { text = "SW", isItem = true, itemID = 63352, isHearthstone = true, icon = 461810, equipSlot = 15, faction = FACTION_ALLIANCE, locID = 84, x = 0.4571, y = 0.9038, zoneID = 84 },

			[89158] = { text = "OG", isItem = true, itemID = 65274, isHearthstone = true, icon = 461815, equipSlot = 15, faction = FACTION_HORDE, locID = 85, x = 0.5265, y = 0.8984, zoneID = 85 },
			[1221356] = { text = "OG", isItem = true, itemID = 63353, isHearthstone = true, icon = 461813, equipSlot = 15, faction = FACTION_HORDE, locID = 85, x = 0.5265, y = 0.8984, zoneID = 85 },
			[1221357] = { text = "OG", isItem = true, itemID = 63207, isHearthstone = true, icon = 461814, equipSlot = 15, faction = FACTION_HORDE, locID = 85, x = 0.5265, y = 0.8984, zoneID = 85 },

			[49844] = {
				text = addon.MythicPlus.variables.hearthstoneName or "HS",
				isItem = true,
				itemID = 37863,
				isHearthstone = true,
				icon = 133015,
				zoneID = 242,
				locID = 243,
				x = 0.4496,
				y = 0.5204,
			}, -- Grim Guzzler
			[71436] = {
				text = addon.MythicPlus.variables.hearthstoneName or "HS",
				isItem = true,
				itemID = 50287,
				isHearthstone = true,
				icon = 132578,
				equipSlot = 8,
				locID = 210,
				x = 0.3818,
				y = 0.7306,
				zoneID = 210,
			}, -- Boots of the Bay

			[139437] = {
				text = "BP",
				isItem = true,
				itemID = { 95051, 144391, 118907 },
				isHearthstone = true,
				icon = 133345,
				ownedOnly = true,
				faction = FACTION_ALLIANCE,
				equipSlot = 11,
				locID = 499,
				x = 0.8110,
				y = 0.2105,
				zoneID = 499,
			},
			[139432] = {
				text = "BA",
				isItem = true,
				itemID = { 95050, 144392, 118908 },
				isHearthstone = true,
				ownedOnly = true,
				icon = 133345,
				faction = FACTION_HORDE,
				equipSlot = 11,
				locID = 499,
				x = 0.8110,
				y = 0.2105,
				zoneID = 499,
			},

			[120145] = { text = "DALA", isClassTP = "MAGE", x = 0.3065, y = 0.3622, zoneID = 627, locID = 25 },
			[120146] = { text = "DALA", isMagePortal = true, x = 0.3065, y = 0.3622, zoneID = 627, locID = 25 },
		},
	},
	[10] = {
		ignoreTimerunner = true,
		headline = CLASS,
		spells = {
			[1225967] = { text = "Infinite Bazaar", timerunnerID = 2, isItem = true, itemID = 238727, isHearthstone = true, icon = 134491, locID = 619, x = 0.4560, y = 0.6743, zoneID = 619 },

			[193759] = { text = "CLASS", isClassTP = "MAGE", x = 0.5731, y = 0.8669, zoneID = 734, locID = 734 },
			[193753] = { text = "CLASS", isClassTP = "DRUID", x = 0.5492, y = 0.6276, zoneID = 715, locID = 715 },
			[50977] = { text = "CLASS", isClassTP = "DEATHKNIGHT", x = 0.2706, y = 0.2994, zoneID = 648, locID = 648 },
			[556] = { text = addon.MythicPlus.variables.hearthstoneName or "CLASS", isClassTP = "SHAMAN" },
			[126892] = { text = "CLASS", isClassTP = "MONK", x = 0.5133, y = 0.4992, zoneID = 709, locID = 709 },
			[265225] = { text = RACIAL_TRAITS_TOOLTIP, isRaceTP = "DarkIronDwarf" },
			[312372] = { text = RACIAL_TRAITS_TOOLTIP, isRaceTP = "Vulpera" },
		},
	},
}

-- Pre-Stage all icon to have less calls to LUA API
local RANDOM_HS_ID = 999999
local hearthstoneID = {
	-- 11.2
	{ isToy = true, icon = 133469, id = 245970, spellID = 1240219 }, -- P.O.S.T. Master's Express Hearthstone
	{ isToy = true, icon = 5852174, id = 246565, spellID = 1242509 }, -- Cosmic Hearthstone

	--TWW
	{ isToy = true, icon = 4622300, id = 235016, spellID = 1217281 }, -- Redeployment Module
	{ isItem = true, icon = 134414, id = 6948, spellID = 8690 }, -- Default Hearthstone
	{ isToy = true, icon = 236222, id = 54452, spellID = 75136 }, -- Ethereal Portal
	{ isToy = true, icon = 458254, id = 64488, spellID = 94716 }, -- The Innkeeper's Daughter
	{ isToy = true, icon = 255348, id = 93672, spellID = 136508 }, -- Dark Portal
	-- { isToy = true, icon = 1529351, id = 142542, spellID = 231504 }, -- Tome of Town Portal -- Cooldown is to long to be usable
	{ isToy = true, icon = 2124576, id = 162973, spellID = 278244 }, -- Greatfather Winter's Hearthstone
	{ isToy = true, icon = 2124575, id = 163045, spellID = 278559 }, -- Headless Horseman's Hearthstone
	{ isToy = true, icon = 2491049, id = 165669, spellID = 285362 }, -- Lunar Elder's Hearthstone
	{ isToy = true, icon = 2491048, id = 165670, spellID = 285424 }, -- Peddlefeet's Lovely Hearthstone
	{ isToy = true, icon = 2491065, id = 165802, spellID = 286031 }, -- Noble Gardener's Hearthstone
	{ isToy = true, icon = 2491064, id = 166746, spellID = 286331 }, -- Fire Eater's Hearthstone
	{ isToy = true, icon = 2491063, id = 166747, spellID = 286353 }, -- Brewfest Reveler's Hearthstone
	{ isToy = true, icon = 2491049, id = 168907, spellID = 298068 }, -- Holographic Digitalization Hearthstone
	{ isToy = true, icon = 3084684, id = 172179, spellID = 308742 }, -- Eternal Traveler's Hearthstone
	{ isToy = true, icon = 3528303, id = 188952, spellID = 363799 }, -- Dominated Hearthstone
	{ isToy = true, icon = 3950360, id = 190196, spellID = 366945 }, -- Enlightened Hearthstone
	{ isToy = true, icon = 3954409, id = 190237, spellID = 367013 }, -- Broker Translocation Matrix
	{ isToy = true, icon = 4571434, id = 193588, spellID = 375357 }, -- Timewalker's Hearthstone
	{ isToy = true, icon = 4080564, id = 200630, spellID = 391042 }, -- Ohn'ir Windsage's Hearthstone
	{ isToy = true, icon = 1708140, id = 206195, spellID = 412555 }, -- Path of the Naaru
	{ isToy = true, icon = 5333528, id = 208704, spellID = 420418 }, -- Deepdweller's Earth Hearthstone
	{ isToy = true, icon = 2491064, id = 209035, spellID = 422284 }, -- Hearthstone of the Flame
	{ isToy = true, icon = 5524923, id = 212337, spellID = 401802 }, -- Stone of the Hearth
	{ isToy = true, icon = 5891370, id = 228940, spellID = 463481 }, -- Notorious Thread's Hearthstone
	{ isToy = true, icon = 6383489, id = 236687, spellID = 1220729 }, -- Explosive Hearthstone
	{ isToy = true, icon = 1029741, id = 263489, spellID = 1298582 }, -- Naaru's Enfold
	{
		isToy = true,
		icon = 1686574,
		id = 210455,
		spellID = 438606,
		usable = function()
			if addon.variables.unitRace == "LightforgedDraenei" or addon.variables.unitRace == "Draenei" and PlayerHasToy(210455) then
				return true
			else
				return false
			end
		end,
	}, -- Draenic Hologem

	-- Covenent Hearthstones
	{ isToy = true, icon = 3257748, id = 184353, spellID = 345393, achievementID = 15242 }, -- Kyrian Hearthstone
	{ isToy = true, icon = 3514225, id = 183716, spellID = 342122, achievementID = 15245 }, -- Venthyr Sinstone
	{ isToy = true, icon = 3489827, id = 180290, spellID = 326064, achievementID = 15244 }, -- Night Fae Hearthstone
	{ isToy = true, icon = 3716927, id = 182773, spellID = 340200, achievementID = 15243 }, -- Necrolord Hearthstone
}

local availableHearthstones = {}

local function setAvailableHearthstone()
	availableHearthstones = {}
	for _, v in pairs(hearthstoneID) do
		local addIt = false
		if v.isItem then
			if C_Item.GetItemCount(v.id) > 0 then addIt = true end
		elseif PlayerHasToy(v.id) then
			if v.usable and v.usable() then
				addIt = true
			elseif v.achievementID then
				if select(4, GetAchievementInfo(v.achievementID)) then addIt = true end
			else
				addIt = true
			end
		end
		if addIt then table.insert(availableHearthstones, v) end
	end
end

function addon.MythicPlus.functions.setRandomHearthstone(forceRefresh)
	if forceRefresh or #availableHearthstones == 0 then
		setAvailableHearthstone() -- recheck hearthstones
		if #availableHearthstones == 0 then return nil end
	end

	local randomIndex = math.random(1, #availableHearthstones)

	local hs = availableHearthstones[randomIndex]
	-- Ensure we do not overwrite other HOME entries (e.g., class/race teleports)
	local homeSection = addon.MythicPlus.variables.portalCompendium[9999]
	if not homeSection then
		addon.MythicPlus.variables.portalCompendium[9999] = { headline = HOME, spells = {} }
		homeSection = addon.MythicPlus.variables.portalCompendium[9999]
	end
	homeSection.spells = homeSection.spells or {}
	homeSection.ignoreTimerunner = true
	homeSection.spells[RANDOM_HS_ID] = {
		text = addon.MythicPlus.variables.hearthstoneName or "HS",
		isItem = hs.isItem or false,
		itemID = hs.id,
		isToy = hs.isToy or false,
		toyID = hs.id,
		isHearthstone = true,
		icon = hs.icon,
	}
	return homeSection.spells[RANDOM_HS_ID]
end

function addon.MythicPlus.functions.EnsureRandomHearthstoneButton()
	local btn = _G.EQOLRandomHearthstoneButton
	if not btn then btn = CreateFrame("Button", "EQOLRandomHearthstoneButton", UIParent, "SecureActionButtonTemplate") end
	btn:RegisterForClicks("AnyDown")
	btn:SetAttribute("type1", "macro")
	btn:SetAttribute("type", "macro")
	-- Trigger action on key down regardless of ActionButtonUseKeyDown.
	btn:SetAttribute("pressAndHoldAction", true)
	if not btn._eqolRandomHearthMacro then
		btn:SetAttribute("macrotext1", "/use item:6948")
		btn:SetAttribute("macrotext", "/use item:6948")
		btn._eqolRandomHearthMacro = true
	end
	if not btn._eqolRandomHearthPreClick then
		btn:SetScript("PreClick", function(self)
			if InCombatLockdown and InCombatLockdown() then return end
			local entry = addon.MythicPlus.functions.setRandomHearthstone(true)
			local itemID = entry and ((entry.isToy and entry.toyID) or entry.itemID)
			if not itemID then itemID = 6948 end
			local macro = "/use item:" .. tostring(itemID)
			self:SetAttribute("macrotext1", macro)
			self:SetAttribute("macrotext", macro)
		end)
		btn._eqolRandomHearthPreClick = true
	end
	return btn
end

do
	local initFrame = CreateFrame("Frame")
	initFrame:RegisterEvent("PLAYER_LOGIN")
	initFrame:SetScript("OnEvent", function()
		if addon and addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.EnsureRandomHearthstoneButton then addon.MythicPlus.functions.EnsureRandomHearthstoneButton() end
	end)
end

addon.MythicPlus.variables.collapseFrames = {
	{ frame = UIWidgetObjectiveTracker, name = "UIWidgetObjectiveTracker" },
	{ frame = CampaignQuestObjectiveTracker, name = "CampaignQuestObjectiveTracker" },
	{ frame = QuestObjectiveTracker, name = "QuestObjectiveTracker" },
	{ frame = AdventureObjectiveTracker, name = "AdventureObjectiveTracker" },
	{ frame = AchievementObjectiveTracker, name = "AchievementObjectiveTracker" },
	{ frame = MonthlyActivitiesObjectiveTracker, name = "MonthlyActivitiesObjectiveTracker" },
	{ frame = InitiativeTasksObjectiveTracker, name = "InitiativeTasksObjectiveTracker" },
	{ frame = ProfessionsRecipeTracker, name = "ProfessionsRecipeTracker" },
	{ frame = BonusObjectiveTracker, name = "BonusObjectiveTracker" },
	{ frame = WorldQuestObjectiveTracker, name = "WorldQuestObjectiveTracker" },
}

addon.MythicPlus.variables.challengeMapID = {
	[560] = "MC",
	[559] = "NPX",
	[558] = "MT",
	[557] = "WRS",
	[239] = "SOTT",
	[556] = "POS",
	[542] = "ED",
	[501] = "SV",
	[502] = "COT",
	[505] = "DAWN",
	[503] = "ARAK",
	[525] = "FLOOD",
	[506] = "MEAD",
	[499] = "PSF",
	[504] = "DFC",
	[500] = "ROOK",
	[463] = "DOTI",
	[464] = "DOTI",
	[399] = "RLP",
	[400] = "NO",
	[405] = "BH",
	[402] = "AA",
	[404] = "NELT",
	[401] = "AV",
	[406] = "HOI",
	[403] = "ULD",
	[376] = "NW",
	[379] = "PF",
	[375] = "MISTS",
	[378] = "HOA",
	[381] = "SOA",
	[382] = "TOP",
	[377] = "DOS",
	[380] = "SD",
	[391] = "STREET",
	[392] = "GAMBIT",
	[245] = "FH",
	[251] = "UR",
	[369] = "WORK",
	[370] = "WORK",
	[248] = "WM",
	[244] = "AD",
	[353] = "SIEG",
	[247] = "ML",
	[199] = "BRH",
	[210] = "COS",
	[198] = "DHT",
	[200] = "HOV",
	[206] = "NL",
	[227] = "KARA",
	[234] = "KARA",
	[164] = "AUCH",
	[163] = "BSM",
	[168] = "EB",
	[166] = "GD",
	[169] = "ID",
	[165] = "SBG",
	[161] = "SR",
	[167] = "UBRS",
	[57] = "GSS",
	[60] = "MP",
	[76] = "SCHO",
	[77] = "SH",
	[78] = "SM",
	[59] = "SN",
	[58] = "SPM",
	[56] = "SB",
	[2] = "TJS",
	[507] = "GB",
	[456] = "TOTT",
	[438] = "VP",
}
