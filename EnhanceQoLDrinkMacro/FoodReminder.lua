local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

-- Cache globals for performance
local CreateFrame = CreateFrame
local UIParent = UIParent
local print = print
local C_Item_GetItemCount = C_Item.GetItemCount
local LFDQueueFrame_SetType = LFDQueueFrame_SetType
local C_LFGInfo = C_LFGInfo
local LFGDungeonList_SetDungeonEnabled = LFGDungeonList_SetDungeonEnabled

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_DrinkMacro")
local LSM = LibStub("LibSharedMedia-3.0")

-- Enable or disable the food reminder frame
addon.functions.InitDBValue("mageFoodReminder", false)
local defaultPos = { point = "TOP", x = 0, y = -100 }
addon.functions.InitDBValue("mageFoodReminderPos", { point = defaultPos.point, x = defaultPos.x, y = defaultPos.y })
addon.functions.InitDBValue("mageFoodReminderScale", 1)
addon.functions.InitDBValue("mageFoodReminderSound", true)
addon.functions.InitDBValue("mageFoodReminderUseCustomSound", false)
addon.functions.InitDBValue("mageFoodReminderJoinSoundFile", "")
addon.functions.InitDBValue("mageFoodReminderLeaveSoundFile", "")

local brButton
local defaultButtonSize = 60
local defaultFontSize = 16

local queuedFollower = false

local function playReminderSound(kind)
	if not addon.db["mageFoodReminderSound"] then return end

	local key
	if kind == "leave" then
		key = addon.db["mageFoodReminderLeaveSoundFile"]
	else
		key = addon.db["mageFoodReminderJoinSoundFile"]
	end

	if addon.db["mageFoodReminderUseCustomSound"] then
		local file = key ~= "" and LSM:HashTable("sound")[key]
		if file then
			PlaySoundFile(file, "Master")
			return
		end
	end

	PlaySound(SOUNDKIT.RAID_WARNING)
end

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

local function applyButtonSettings()
	if not brButton then return end

	brButton:SetMovable(true)
	brButton:EnableMouse(true)
	brButton:RegisterForDrag("LeftButton")

	brButton:SetScript("OnDragStart", function()
		if not IsAltKeyDown() then return end
		brButton:StartMoving()
	end)
	brButton:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, xOfs, yOfs = self:GetPoint()
		addon.db["mageFoodReminderPos"] = { point = point, x = xOfs, y = yOfs }
	end)

	local pos = addon.db["mageFoodReminderPos"]
	brButton:ClearAllPoints()
	brButton:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
	brButton:SetScale(addon.db["mageFoodReminderScale"] or 1)
end

local function createLeaveFrame()
	removeBRFrame()
	brButton = CreateFrame("Button", nil, UIParent)
	brButton:SetSize(defaultButtonSize, defaultButtonSize)
	brButton:SetPoint("TOP", UIParent, "TOP", 0, -100)
	brButton:SetFrameStrata("HIGH")
	brButton:SetScript("OnClick", function() C_PartyInfo.LeaveParty() end)

	brButton.info = brButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	brButton.info:SetPoint("TOP", brButton, "BOTTOM", 0, -3)
	brButton.info:SetFont(addon.variables.defaultFont, defaultFontSize, "OUTLINE")
	brButton.info:SetText(L["mageFoodLeaveText"])

	local bg = brButton:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(brButton)
	bg:SetColorTexture(0, 0, 0, 0.8)

	local icon = brButton:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(brButton)
	icon:SetTexture(136813) -- door icon
	brButton.icon = icon

	local jumpGroup = brButton:CreateAnimationGroup()
	local up = jumpGroup:CreateAnimation("Translation")
	up:SetOffset(0, 50)
	up:SetDuration(1)
	up:SetSmoothing("OUT")

	local down = jumpGroup:CreateAnimation("Translation")
	down:SetOffset(0, -50)
	down:SetDuration(1)
	down:SetSmoothing("IN")

	jumpGroup:SetLooping("BOUNCE")
	jumpGroup:Play()
	applyButtonSettings()
end

local function createBRFrame()
	removeBRFrame()
	-- if not addon.db["mythicPlusBRTrackerEnabled"] then return end
	brButton = CreateFrame("Button", nil, UIParent)
	brButton:SetSize(defaultButtonSize, defaultButtonSize)
	brButton:SetPoint("TOP", UIParent, "TOP", 0, -100)
	brButton:SetFrameStrata("HIGH")
	brButton:SetScript("OnClick", function()
		LFDQueueFrame_SetType("follower")

		LFDQueueFrame_Update()
		for _, dungeonID in ipairs(_G["LFDDungeonList"]) do
			if dungeonID >= 0 and C_LFGInfo.IsLFGFollowerDungeon(dungeonID) then
				LFGDungeonList_SetDungeonEnabled(dungeonID, true)

				LFDQueueFrameList_Update()
				LFDQueueFrame_UpdateRoleButtons()
				LFDQueueFrameFindGroupButton:Click()
				queuedFollower = true
				return
			end
		end
	end)

	brButton.info = brButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	brButton.info:SetPoint("TOP", brButton, "BOTTOM", 0, -3)
	brButton.info:SetFont(addon.variables.defaultFont, defaultFontSize, "OUTLINE")
	brButton.info:SetText(L["mageFoodReminderText"])

	local bg = brButton:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(brButton)
	bg:SetColorTexture(0, 0, 0, 0.8)

	local icon = brButton:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(brButton)
	icon:SetTexture(134029)
	brButton.icon = icon

	local jumpGroup = brButton:CreateAnimationGroup()
	local up = jumpGroup:CreateAnimation("Translation")
	up:SetOffset(0, 50)
	up:SetDuration(1)
	up:SetSmoothing("OUT")

	local down = jumpGroup:CreateAnimation("Translation")
	down:SetOffset(0, -50)
	down:SetDuration(1)
	down:SetSmoothing("IN")

	jumpGroup:SetLooping("BOUNCE")
	jumpGroup:Play()
	applyButtonSettings()
end

local healerRole

local function hasEnoughMageFood()
	local mageFoodList = addon.Drinks.mageFood
	if mageFoodList then
		for itemID in pairs(mageFoodList) do
			local count = C_Item_GetItemCount(itemID, false, false)
			if count and count > 20 then return true end
		end
	end
	return false
end

local soundPlayed = false
local function checkShow()
	if not addon.db["mageFoodReminder"] then
		removeBRFrame()
		return
	end

	local enoughFood = hasEnoughMageFood()
	if queuedFollower and IsInLFGDungeon() then
		if enoughFood then
			createLeaveFrame()
			if soundPlayed == false then
				soundPlayed = true
				C_Timer.After(0.3, function()
					playReminderSound("leave")
					soundPlayed = false
				end)
			end
		else
			removeBRFrame()
		end
		return
	end

	if not healerRole or not IsResting() then
		removeBRFrame()
		return
	end
	if IsInGroup() then
		removeBRFrame()
		return
	end
	if not enoughFood then
		createBRFrame()
		if soundPlayed == false then
			soundPlayed = true
			C_Timer.After(0.3, function()
				playReminderSound("join")
				soundPlayed = false
			end)
		end
	else
		removeBRFrame()
	end
end

function addon.Drinks.functions.updateRole()
	healerRole = GetSpecializationRole(GetSpecialization()) == "HEALER" or false
	checkShow()
end

local frameLoad = CreateFrame("Frame")
-- Registriere das Event
frameLoad:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
frameLoad:RegisterEvent("PLAYER_LOGIN")
frameLoad:RegisterEvent("BAG_UPDATE_DELAYED")
frameLoad:RegisterEvent("PLAYER_UPDATE_RESTING")
frameLoad:RegisterEvent("GROUP_ROSTER_UPDATE")

frameLoad:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		healerRole = GetSpecializationRole(GetSpecialization()) == "HEALER" or false
	elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
		healerRole = GetSpecializationRole(GetSpecialization()) == "HEALER" or false
	elseif event == "PLAYER_UPDATE_RESTING" and IsResting() then
		queuedFollower = false
	end
	if IsResting() or IsInLFGDungeon() then
		checkShow()
	else
		removeBRFrame()
	end
end)
