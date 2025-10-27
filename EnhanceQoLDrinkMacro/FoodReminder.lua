local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

-- Cache globals for performance
local CreateFrame = CreateFrame
local UIParent = UIParent
local IsAltKeyDown = IsAltKeyDown
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
local EditMode = addon.EditMode
local SettingType = EditMode and EditMode.lib and EditMode.lib.SettingType

-- Enable or disable the food reminder frame
addon.functions.InitDBValue("mageFoodReminder", false)
local defaultPos = { point = "TOP", x = 0, y = -100 }
addon.functions.InitDBValue("mageFoodReminderPos", { point = defaultPos.point, x = defaultPos.x, y = defaultPos.y })
addon.functions.InitDBValue("mageFoodReminderScale", 1)
addon.functions.InitDBValue("mageFoodReminderSound", true)
addon.functions.InitDBValue("mageFoodReminderUseCustomSound", false)
addon.functions.InitDBValue("mageFoodReminderJoinSoundFile", "")
addon.functions.InitDBValue("mageFoodReminderLeaveSoundFile", "")

local oldSoundDisabled = addon.db.mageFoodReminderSound == false
if oldSoundDisabled then
	addon.db.mageFoodReminderJoinSoundFile = addon.db.mageFoodReminderJoinSoundFile or ""
	addon.db.mageFoodReminderLeaveSoundFile = addon.db.mageFoodReminderLeaveSoundFile or ""
else
	if addon.db.mageFoodReminderJoinSoundFile == "" then addon.db.mageFoodReminderJoinSoundFile = nil end
	if addon.db.mageFoodReminderLeaveSoundFile == "" then addon.db.mageFoodReminderLeaveSoundFile = nil end
end
addon.db.mageFoodReminderSound = nil
addon.db.mageFoodReminderUseCustomSound = nil

local brButton
local defaultButtonSize = 60
local defaultFontSize = 16

local queuedFollower = false
local reminderAnchor
local editModeRegistered = false
local editModeId = "EnhanceQoL:FoodReminder"
local editModeActive = false
local registerEditModeFrame -- forward declaration
local DEFAULT_SOUND_SENTINEL = "__DEFAULT_SOUND__"

local function updateButtonMouseState()
	if not brButton then return end
	if editModeActive then
		brButton:EnableMouse(false)
	else
		brButton:EnableMouse(true)
	end
end

local syncingPosition = false

local function syncEditModePosition()
	if syncingPosition then return end
	if not (EditMode and editModeRegistered and EditMode.SetFramePosition) then return end
	local pos = addon.db["mageFoodReminderPos"] or defaultPos
	if not pos.point then pos.point = defaultPos.point end
	if pos.x == nil then pos.x = defaultPos.x end
	if pos.y == nil then pos.y = defaultPos.y end
	syncingPosition = true
	local ok, err = pcall(EditMode.SetFramePosition, EditMode, editModeId, pos.point, pos.x, pos.y)
	if not ok and err then geterrorhandler()(err) end
	syncingPosition = false
end

local function ensureAnchor()
	if reminderAnchor then return reminderAnchor end

	local anchor = CreateFrame("Frame", addonName .. "FoodReminderAnchor", UIParent, "BackdropTemplate")
	anchor:SetSize(defaultButtonSize, defaultButtonSize)
	anchor:SetFrameStrata("HIGH")
	anchor:SetClampedToScreen(true)
	anchor:SetMovable(true)
	anchor:SetDontSavePosition(true)
	anchor:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	anchor:SetBackdropColor(0, 0, 0, 0)
	anchor:SetBackdropBorderColor(1, 0.82, 0, 0.9)
	anchor:SetAlpha(0.999) -- ensure mouse events
	anchor:EnableMouse(false)
	anchor:RegisterForDrag("LeftButton")
	anchor:SetScript("OnDragStart", function(self)
		if editModeActive or IsAltKeyDown() then self:StartMoving() end
	end)
	anchor:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, xOfs, yOfs = self:GetPoint()
		addon.db["mageFoodReminderPos"] = { point = point, x = xOfs, y = yOfs }
		syncEditModePosition()
	end)

	local pos = addon.db["mageFoodReminderPos"] or defaultPos
	anchor:ClearAllPoints()
	anchor:SetPoint(pos.point or defaultPos.point, UIParent, pos.point or defaultPos.point, pos.x or defaultPos.x, pos.y or defaultPos.y)
	local scale = addon.db["mageFoodReminderScale"] or 1
	scale = math.floor(scale / 0.05 + 0.5) * 0.05
	if scale < 0.1 then
		scale = 0.1
	elseif scale > 2.0 then
		scale = 2.0
	end
	scale = tonumber(string.format("%.2f", scale))
	anchor:SetScale(scale)
	addon.db["mageFoodReminderScale"] = scale
	anchor:Hide()

	reminderAnchor = anchor
	return anchor
end

local function playReminderSound(kind)
	local key
	if kind == "leave" then
		key = addon.db["mageFoodReminderLeaveSoundFile"]
	else
		key = addon.db["mageFoodReminderJoinSoundFile"]
	end

	if key == "" then return end -- no sound

	if key and key ~= "" then
		local soundTable = LSM and LSM:HashTable("sound")
		local file = soundTable and soundTable[key]
		if file then
			PlaySoundFile(file, "Master")
			return
		end
	end

	PlaySound(SOUNDKIT.RAID_WARNING)
end

local function removeBRFrame()
	if brButton then
		if brButton.jumpGroup then brButton.jumpGroup:Stop() end
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
	if reminderAnchor and not editModeActive then reminderAnchor:Hide() end
end

local function applyButtonSettings()
	local anchor = ensureAnchor()
	local pos = addon.db["mageFoodReminderPos"] or defaultPos
	anchor:ClearAllPoints()
	anchor:SetPoint(pos.point or defaultPos.point, UIParent, pos.point or defaultPos.point, pos.x or defaultPos.x, pos.y or defaultPos.y)
	anchor:SetScale(addon.db["mageFoodReminderScale"] or 1)

	if brButton then
		brButton:ClearAllPoints()
		brButton:SetAllPoints(anchor)
	end
	updateButtonMouseState()

	if addon.db["mageFoodReminder"] or editModeActive then
		anchor:Show()
	else
		anchor:Hide()
	end
	anchor:EnableMouse(editModeActive)
	anchor:SetFrameStrata(editModeActive and "HIGH" or "MEDIUM")
	if brButton then brButton:SetFrameStrata(editModeActive and "HIGH" or "DIALOG") end

	if editModeActive then
		anchor:SetBackdropColor(0.05, 0.05, 0.05, 0.6)
	else
		anchor:SetBackdropColor(0, 0, 0, 0)
	end

	syncEditModePosition()
end

local function createLeaveFrame()
	removeBRFrame()
	local anchor = ensureAnchor()
	brButton = CreateFrame("Button", nil, anchor)
	brButton:SetAllPoints(anchor)
	brButton:SetFrameStrata("HIGH")
	brButton:SetScript("OnClick", function()
		if editModeActive then return end
		C_PartyInfo.LeaveParty()
	end)
	brButton:RegisterForDrag("LeftButton")
	brButton:SetScript("OnDragStart", function()
		if editModeActive or not IsAltKeyDown() then return end
		local parent = ensureAnchor()
		parent:StartMoving()
	end)
	brButton:SetScript("OnDragStop", function()
		local parent = ensureAnchor()
		parent:StopMovingOrSizing()
		local point, _, _, xOfs, yOfs = parent:GetPoint()
		addon.db["mageFoodReminderPos"] = { point = point, x = xOfs, y = yOfs }
		syncEditModePosition()
	end)

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
	brButton.jumpGroup = jumpGroup
	applyButtonSettings()
end

local function createBRFrame()
	removeBRFrame()
	local anchor = ensureAnchor()
	brButton = CreateFrame("Button", nil, UIParent)
	brButton:SetAllPoints(anchor)
	brButton:SetFrameStrata("HIGH")
	brButton:SetScript("OnClick", function()
		if editModeActive then return end
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
	brButton:RegisterForDrag("LeftButton")
	brButton:SetScript("OnDragStart", function()
		if editModeActive or not IsAltKeyDown() then return end
		local parent = ensureAnchor()
		parent:StartMoving()
	end)
	brButton:SetScript("OnDragStop", function()
		local parent = ensureAnchor()
		parent:StopMovingOrSizing()
		local point, _, _, xOfs, yOfs = parent:GetPoint()
		addon.db["mageFoodReminderPos"] = { point = point, x = xOfs, y = yOfs }
		syncEditModePosition()
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
	brButton.jumpGroup = jumpGroup
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

local joinSoundPlayed = false
local leaveSoundPlayed = false
local function checkShow()
	applyButtonSettings()

	if editModeActive then
		if addon.db["mageFoodReminder"] then
			if not brButton then createBRFrame() end
		else
			removeBRFrame()
		end
		return
	end

	-- Timerunner mode: no follower dungeons; disable reminder entirely
	if addon.functions and addon.functions.IsTimerunner and addon.functions.IsTimerunner() then
		removeBRFrame()
		joinSoundPlayed = false
		leaveSoundPlayed = false
		return
	end

	if not addon.db["mageFoodReminder"] then
		removeBRFrame()
		joinSoundPlayed = false
		leaveSoundPlayed = false
		return
	end

	local enoughFood = hasEnoughMageFood()
	if queuedFollower and IsInLFGDungeon() then
		if enoughFood then
			createLeaveFrame()
			if not leaveSoundPlayed then
				leaveSoundPlayed = true
				joinSoundPlayed = false
				playReminderSound("leave")
			end
		else
			removeBRFrame()
			leaveSoundPlayed = false
		end
		return
	end

	if not healerRole or not IsResting() or IsInGroup() then
		removeBRFrame()
		joinSoundPlayed = false
		leaveSoundPlayed = false
		return
	end

	if not enoughFood then
		createBRFrame()
		if not joinSoundPlayed then
			joinSoundPlayed = true
			leaveSoundPlayed = false
			playReminderSound("join")
		end
	else
		removeBRFrame()
		joinSoundPlayed = false
	end
end

local function createSoundDropdownSetting(labelKey, dbKey)
	if not SettingType then return nil end
	return {
		name = L[labelKey] or labelKey,
		kind = SettingType.Dropdown,
		height = 260,
		get = function()
			local value = addon.db[dbKey]
			if value == nil then return DEFAULT_SOUND_SENTINEL end
			return value
		end,
		set = function(_, value)
			if value == DEFAULT_SOUND_SENTINEL then
				addon.db[dbKey] = nil
			elseif value == "" then
				addon.db[dbKey] = ""
			else
				addon.db[dbKey] = value
				local soundTable = LSM and LSM:HashTable("sound")
				local file = soundTable and soundTable[value]
				if file then PlaySoundFile(file, "Master") end
			end
		end,
		generator = function(_, rootDescription)
			if rootDescription.SetScrollMode then rootDescription:SetScrollMode(260) end
			local noneLabel = NONE or L["None"] or "None"
			rootDescription:CreateRadio(noneLabel, function() return addon.db[dbKey] == "" end, function() addon.db[dbKey] = "" end)
			local defaultLabel = L["mageFoodReminderDefaultSound"] or DEFAULT
			rootDescription:CreateRadio(defaultLabel, function() return addon.db[dbKey] == nil end, function()
				addon.db[dbKey] = nil
				PlaySound(SOUNDKIT.RAID_WARNING)
			end)
			local soundTable = LSM and LSM:HashTable("sound")
			if soundTable then
				for _, soundName in ipairs(LSM:List("sound")) do
					rootDescription:CreateRadio(soundName, function() return addon.db[dbKey] == soundName end, function()
						addon.db[dbKey] = soundName
						local file = soundTable[soundName]
						if file then PlaySoundFile(file, "Master") end
					end)
				end
			end
		end,
	}
end

local registeringEditMode = false

registerEditModeFrame = function()
	if editModeRegistered or registeringEditMode or not EditMode or not EditMode.RegisterFrame then return end
	registeringEditMode = true

	local function performRegistration()
		local anchor = ensureAnchor()
		local defaults = {
			point = defaultPos.point,
			relativePoint = defaultPos.point,
			x = defaultPos.x,
			y = defaultPos.y,
			scale = 1,
		}

		local settings
		if SettingType then
			settings = {}

			local joinDropdown = createSoundDropdownSetting("mageFoodReminderJoinSound", "mageFoodReminderJoinSoundFile")
			if joinDropdown then settings[#settings + 1] = joinDropdown end

			local leaveDropdown = createSoundDropdownSetting("mageFoodReminderLeaveSound", "mageFoodReminderLeaveSoundFile")
			if leaveDropdown then settings[#settings + 1] = leaveDropdown end

			settings[#settings + 1] = {
				name = L["mageFoodReminderSize"] or "Reminder scale",
				kind = SettingType.Slider,
				minValue = 0.1,
				maxValue = 2.0,
				valueStep = 0.05,
				default = 1,
				get = function() return addon.db.mageFoodReminderScale or 1 end,
				set = function(_, value)
					value = tonumber(value) or addon.db.mageFoodReminderScale or 1
					value = math.floor(value / 0.05 + 0.5) * 0.05
					if value < 0.1 then
						value = 0.1
					elseif value > 2.0 then
						value = 2.0
					end
					value = tonumber(string.format("%.2f", value))
					addon.db.mageFoodReminderScale = value
					applyButtonSettings()
				end,
				formatter = function(value)
					value = math.floor(value / 0.05 + 0.5) * 0.05
					if value < 0.1 then
						value = 0.1
					elseif value > 2.0 then
						value = 2.0
					end
					return string.format("%.2f", value)
				end,
			}
		end

		EditMode:RegisterFrame(editModeId, {
			frame = anchor,
			title = L["mageFoodReminder"] or "Food Reminder",
			layoutDefaults = defaults,
			onApply = function(_, layoutName, data)
				if not data then
					addon.db["mageFoodReminderPos"] = CopyTable(defaultPos)
					addon.db.mageFoodReminderScale = 1
				else
					if data.point then addon.db["mageFoodReminderPos"] = {
						point = data.point,
						x = data.x or 0,
						y = data.y or 0,
					} end
					if data.scale then addon.db.mageFoodReminderScale = data.scale end
				end
				applyButtonSettings()
				syncEditModePosition()
			end,
			onPositionChanged = function(_, layoutName, data)
				if not data then return end
				addon.db["mageFoodReminderPos"] = {
					point = data.point or defaults.point,
					x = data.x or defaults.x,
					y = data.y or defaults.y,
				}
				applyButtonSettings()
				syncEditModePosition()
			end,
			onEnter = function()
				editModeActive = true
				local anchorFrame = ensureAnchor()
				anchorFrame:Show()
				checkShow()
			end,
			onExit = function()
				editModeActive = false
				checkShow()
			end,
			isEnabled = function() return addon.db.mageFoodReminder end,
			managePosition = true,
			settings = settings,
		})

		if EditMode.lib and EditMode.lib.frameDefaults then EditMode.lib.frameDefaults[anchor] = CopyTable(defaultPos) end
		editModeRegistered = true
		syncEditModePosition()
	end

	local ok, err = pcall(performRegistration)
	registeringEditMode = false
	if not ok and err then geterrorhandler()(err) end
end

function addon.Drinks.functions.updateRole()
	healerRole = GetSpecializationRole(C_SpecializationInfo.GetSpecialization()) == "HEALER" or false
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
		healerRole = GetSpecializationRole(C_SpecializationInfo.GetSpecialization()) == "HEALER" or false
	elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
		healerRole = GetSpecializationRole(C_SpecializationInfo.GetSpecialization()) == "HEALER" or false
	elseif event == "PLAYER_UPDATE_RESTING" and IsResting() then
		queuedFollower = false
	end
	if IsResting() or IsInLFGDungeon() then
		checkShow()
	else
		removeBRFrame()
	end
end)

registerEditModeFrame()
