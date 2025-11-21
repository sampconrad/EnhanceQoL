-- luacheck: globals DefaultCompactUnitFrameSetup CompactUnitFrame_UpdateAuras CompactUnitFrame_UpdateName UnitTokenFromGUID C_Bank
-- luacheck: globals HUD_EDIT_MODE_MINIMAP_LABEL
-- luacheck: globals Menu GameTooltip_SetTitle GameTooltip_AddNormalLine EnhanceQoL
-- luacheck: globals GenericTraitUI_LoadUI GenericTraitFrame
-- luacheck: globals CancelDuel DeclineGroup C_PetBattles
-- luacheck: globals ExpansionLandingPage ExpansionLandingPageMinimapButton ShowGarrisonLandingPage GarrisonLandingPage GarrisonLandingPage_Toggle GarrisonLandingPageMinimapButton CovenantSanctumFrame CovenantSanctumFrame_LoadUI EasyMenu
-- luacheck: globals ActionButton_UpdateRangeIndicator MAINMENU_BUTTON PlayerCastingBarFrame TargetFrameSpellBar FocusFrameSpellBar ChatBubbleFont
local addonName, addon = ...

local LDB = LibStub("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0")
local AceGUI = LibStub("AceGUI-3.0")
local AceDB = LibStub("AceDB-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDlg = LibStub("AceConfigDialog-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")
local defaults = {
	profile = {
		dataPanels = {},
		cvarOverrides = {},
		cvarPersistenceEnabled = false,
		optionsFrameScale = 1,
		editModeLayouts = {},
		legionRemix = {},
	},
}

addon.AceGUI = AceGUI
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")

addon.functions = addon.functions or {}
addon.ActionBarLabels = addon.ActionBarLabels or {}
local ActionBarLabels = addon.ActionBarLabels

addon.constants = addon.constants or {}

addon.optionsPages = addon.optionsPages or {}

function addon.functions.RegisterOptionsPage(path, builder)
	if type(path) ~= "string" or path == "" then return end
	if type(builder) ~= "function" then return end
	addon.optionsPages[path] = builder
end

function addon.functions.HasOptionsPage(path)
	local pages = addon.optionsPages
	if type(pages) ~= "table" or type(path) ~= "string" then return false end
	return type(pages[path]) == "function"
end

function addon.functions.ShowOptionsPage(container, path)
	local pages = addon.optionsPages
	if type(pages) ~= "table" then return false end
	local fn = pages[path]
	if type(fn) ~= "function" then return false end
	fn(container, path)
	return true
end

local OPTIONS_FRAME_MIN_SCALE = 0.5
local OPTIONS_FRAME_MAX_SCALE = 2

addon.constants.OPTIONS_FRAME_MIN_SCALE = OPTIONS_FRAME_MIN_SCALE
addon.constants.OPTIONS_FRAME_MAX_SCALE = OPTIONS_FRAME_MAX_SCALE

function addon.functions.applyOptionsFrameScale(scale)
	local db = addon.db
	local desired = tonumber(scale)
	if not desired then desired = (db and db["optionsFrameScale"]) or 1.0 end
	if desired < OPTIONS_FRAME_MIN_SCALE then desired = OPTIONS_FRAME_MIN_SCALE end
	if desired > OPTIONS_FRAME_MAX_SCALE then desired = OPTIONS_FRAME_MAX_SCALE end

	desired = math.floor(desired * 100 + 0.5) / 100

	if db then db["optionsFrameScale"] = desired end

	if addon.aceFrame and addon.aceFrame.SetScale then addon.aceFrame:SetScale(desired) end
	return desired
end

local LFGListFrame = _G.LFGListFrame
local GetContainerItemInfo = C_Container.GetContainerItemInfo
local StaticPopup_Visible = StaticPopup_Visible
local IsShiftKeyDown = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsAltKeyDown = IsAltKeyDown
local IsInGroup = IsInGroup
local math = math
local TooltipUtil = _G.TooltipUtil
local GetTime = GetTime

local EQOL = select(2, ...)
EQOL.C = {}

local ACTION_BAR_FRAME_NAMES = {
	"MultiBarBottomLeft",
	"MultiBarBottomRight",
	"MultiBarRight",
	"MultiBarLeft",
	"MultiBar5",
	"MultiBar6",
	"MultiBar7",
}

if _G.MainMenuBar then table.insert(ACTION_BAR_FRAME_NAMES, 1, "MainMenuBar") end
if _G.MainActionBar then table.insert(ACTION_BAR_FRAME_NAMES, 1, "MainActionBar") end
addon.constants.ACTION_BAR_FRAME_NAMES = ACTION_BAR_FRAME_NAMES

local ACTION_BAR_ANCHOR_ORDER = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
addon.constants.ACTION_BAR_ANCHOR_ORDER = ACTION_BAR_ANCHOR_ORDER

local ACTION_BAR_ANCHOR_CONFIG = {
	TOPLEFT = { addButtonsToTop = false, addButtonsToRight = true },
	TOPRIGHT = { addButtonsToTop = false, addButtonsToRight = false },
	BOTTOMLEFT = { addButtonsToTop = true, addButtonsToRight = true },
	BOTTOMRIGHT = { addButtonsToTop = true, addButtonsToRight = false },
}
addon.constants.ACTION_BAR_ANCHOR_CONFIG = ACTION_BAR_ANCHOR_CONFIG

local DEFAULT_BUTTON_SINK_COLUMNS = 4

local function GetActionBarFrame(index)
	local name = ACTION_BAR_FRAME_NAMES[index]
	if not name then return nil, nil end
	return _G[name], name
end

local function DetermineAnchorFromBar(bar)
	if not bar then return "TOPLEFT" end
	local addTop = bar.addButtonsToTop == true
	local addRight = bar.addButtonsToRight == true
	if addTop and addRight then
		return "BOTTOMLEFT"
	elseif addTop and not addRight then
		return "BOTTOMRIGHT"
	elseif not addTop and addRight then
		return "TOPLEFT"
	else
		return "TOPRIGHT"
	end
end

local function ApplyActionBarAnchor(index, anchorKey)
	local bar = GetActionBarFrame(index)
	if not bar then return end
	local config = ACTION_BAR_ANCHOR_CONFIG[anchorKey]
	if not config then return end
	bar.addButtonsToTop = config.addButtonsToTop
	bar.addButtonsToRight = config.addButtonsToRight
	if bar.UpdateGridLayout then bar:UpdateGridLayout() end
end

function addon.functions.GetActionBarAnchor(index) return DetermineAnchorFromBar(select(1, GetActionBarFrame(index))) end

function addon.functions.SetActionBarAnchor(index, anchorKey) ApplyActionBarAnchor(index, anchorKey) end

local function RefreshAllActionBarAnchors()
	if InCombatLockdown and InCombatLockdown() then
		addon.variables = addon.variables or {}
		addon.variables.pendingActionBarAnchorRefresh = true
		return
	end

	if addon.variables then addon.variables.pendingActionBarAnchorRefresh = nil end
	addon.variables.actionBarAnchorDefaults = addon.variables.actionBarAnchorDefaults or {}
	local enabled = addon.db and addon.db.actionBarAnchorEnabled
	for i = 1, #ACTION_BAR_FRAME_NAMES do
		local defaultKey = "actionBarAnchorDefault" .. i
		local storedDefault = addon.db and addon.db[defaultKey]
		if not storedDefault or not ACTION_BAR_ANCHOR_CONFIG[storedDefault] then
			storedDefault = addon.functions.GetActionBarAnchor(i)
			if addon.db then addon.db[defaultKey] = storedDefault end
		end
		addon.variables.actionBarAnchorDefaults[i] = storedDefault

		local key = "actionBarAnchor" .. i
		local stored = addon.db and addon.db[key]
		if not stored or not ACTION_BAR_ANCHOR_CONFIG[stored] then
			stored = storedDefault
			if addon.db then addon.db[key] = stored end
		end

		if enabled then
			ApplyActionBarAnchor(i, stored)
		else
			ApplyActionBarAnchor(i, storedDefault)
		end
	end
end
addon.functions.RefreshAllActionBarAnchors = RefreshAllActionBarAnchors

-- localeadditions
local hookedATT = false -- need to hook ATT because of the way the minimap button is created

hooksecurefunc("LFGListSearchEntry_OnClick", function(s, button)
	local panel = LFGListFrame.SearchPanel
	if button ~= "RightButton" and LFGListSearchPanelUtil_CanSelectResult(s.resultID) and panel.SignUpButton:IsEnabled() then
		if panel.selectedResult ~= s.resultID then LFGListSearchPanel_SelectResult(panel, s.resultID) end
		LFGListSearchPanel_SignUp(panel)
	end
end)

local function checkBagIgnoreJunk()
	if addon.db["sellAllJunk"] then
		local counter = 0
		for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
			if C_Container.GetBagSlotFlag(bag, Enum.BagSlotFlags.ExcludeJunkSell) then counter = counter + 1 end
		end
		if counter > 0 then
			local message = string.format(L["SellJunkIgnoredBag"], counter)

			StaticPopupDialogs["SellJunkIgnoredBag"] = {
				text = message,
				button1 = OKAY,
				timeout = 15,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
				OnShow = function(self) self:SetFrameStrata("TOOLTIP") end,
			}
			StaticPopup_Show("SellJunkIgnoredBag")
		end
	end
end
addon.functions.checkBagIgnoreJunk = checkBagIgnoreJunk

local function skipRolecheck()
	if addon.db["groupfinderSkipRoleSelectOption"] == 1 then
		local tank, healer, dps = false, false, false
		local role = UnitGroupRolesAssigned("player")
		if role == "NONE" then role = GetSpecializationRole(C_SpecializationInfo.GetSpecialization()) end
		if role == "TANK" then
			tank = true
		elseif role == "DAMAGER" then
			dps = true
		elseif role == "HEALER" then
			healer = true
		end
		if LFDRoleCheckPopupRoleButtonTank.checkButton:IsEnabled() then LFDRoleCheckPopupRoleButtonTank.checkButton:SetChecked(tank) end
		if LFDRoleCheckPopupRoleButtonHealer.checkButton:IsEnabled() then LFDRoleCheckPopupRoleButtonHealer.checkButton:SetChecked(healer) end
		if LFDRoleCheckPopupRoleButtonDPS.checkButton:IsEnabled() then LFDRoleCheckPopupRoleButtonDPS.checkButton:SetChecked(dps) end
	elseif addon.db["groupfinderSkipRoleSelectOption"] == 2 then
		if LFDQueueFrameRoleButtonTank and LFDQueueFrameRoleButtonTank:IsEnabled() then
			LFGListApplicationDialog.TankButton.CheckButton:SetChecked(LFDQueueFrameRoleButtonTank.checkButton:GetChecked())
		end
		if LFDQueueFrameRoleButtonHealer and LFDQueueFrameRoleButtonHealer:IsEnabled() then
			LFGListApplicationDialog.HealerButton.CheckButton:SetChecked(LFDQueueFrameRoleButtonHealer.checkButton:GetChecked())
		end
		if LFDQueueFrameRoleButtonDPS and LFDQueueFrameRoleButtonDPS:IsEnabled() then
			LFGListApplicationDialog.DamagerButton.CheckButton:SetChecked(LFDQueueFrameRoleButtonDPS.checkButton:GetChecked())
		end
	else
		return
	end

	LFDRoleCheckPopupAcceptButton:Enable()
	LFDRoleCheckPopupAcceptButton:Click()
end

LFGListApplicationDialog:HookScript("OnShow", function(self)
	if not addon.db.skipSignUpDialog then return end
	if self.SignUpButton:IsEnabled() and not IsShiftKeyDown() then self.SignUpButton:Click() end
end)

local didApplyPatch = false
local originalFunc = LFGListApplicationDialog_Show
local patchedFunc = function(self, resultID)
	if resultID then
		local searchResultInfo = C_LFGList.GetSearchResultInfo(resultID)

		self.resultID = resultID
		self.activityID = searchResultInfo.activityID
	end
	LFGListApplicationDialog_UpdateRoles(self)
	StaticPopupSpecial_Show(self)
end

function EQOL.PersistSignUpNote()
	if addon.db.persistSignUpNote then
		-- overwrite function with patched func missing the call to ClearApplicationTextFields
		LFGListApplicationDialog_Show = patchedFunc
		didApplyPatch = true
	elseif didApplyPatch then
		-- restore previously overwritten function
		LFGListApplicationDialog_Show = originalFunc
	end
end

local function ensureAssistFrame(key, parent, refFrame)
	addon.variables.assistFrame = addon.variables.assistFrame or {}
	local af = addon.variables.assistFrame[key]
	if not af then
		af = CreateFrame("Frame", nil, parent)
		af:SetFrameStrata(refFrame:GetFrameStrata())
		af:SetFrameLevel(refFrame:GetFrameLevel() + 1)
		af.leaderIcon = af:CreateTexture(nil, "OVERLAY")
		af.leaderIcon:SetTexture(132061)
		af.leaderIcon:SetSize(16, 16)
		addon.variables.assistFrame[key] = af
	else
		af:SetParent(parent)
	end
	af.leaderIcon:ClearAllPoints()
	af.leaderIcon:SetPoint("TOPRIGHT", refFrame, "TOPRIGHT", 5, 6)
	af:Show()
	return af
end

local function removeAssistIcon()
	if addon.variables.assistFrame then
		for _, f in pairs(addon.variables.assistFrame) do
			f:Hide()
			f.leaderIcon:ClearAllPoints()
		end
	end
end

local function ensureLeaderFrame(parent, anchor)
	if not addon.variables.leaderFrame then
		local f = CreateFrame("Frame", nil, parent)
		f.leaderIcon = f:CreateTexture(nil, "OVERLAY")
		f.leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
		f.leaderIcon:SetSize(16, 16)
		addon.variables.leaderFrame = f
	else
		addon.variables.leaderFrame:SetParent(parent)
	end
	addon.variables.leaderFrame.leaderIcon:ClearAllPoints()
	addon.variables.leaderFrame.leaderIcon:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 5, 6)
	addon.variables.leaderFrame:SetFrameStrata(anchor:GetFrameStrata())
	addon.variables.leaderFrame:SetFrameLevel(anchor:GetFrameLevel() + 1)
	addon.variables.leaderFrame:Show()
	return addon.variables.leaderFrame
end

local function removeLeaderIcon()
	local f = addon.variables.leaderFrame
	if f then
		f:Hide()
		f.leaderIcon:ClearAllPoints()
	end
	removeAssistIcon()
end
addon.functions.removeLeaderIcon = removeLeaderIcon

local function setLeaderIcon()
	local leaderFound = false
	if UnitInParty("player") and not UnitInRaid("player") then
		for i = 1, 5 do
			if _G["CompactPartyFrameMember" .. i] and _G["CompactPartyFrameMember" .. i]:IsShown() and _G["CompactPartyFrameMember" .. i].unit then
				if UnitIsGroupLeader(_G["CompactPartyFrameMember" .. i].unit) then
					ensureLeaderFrame(_G["CompactPartyFrameMember" .. i], _G["CompactPartyFrameMember" .. i])
					leaderFound = true
					break
				end
			end
		end
	elseif UnitInRaid("player") then
		removeAssistIcon()
		for i = 1, 8 do
			for j = 1, 5 do
				if _G["CompactRaidGroup" .. i .. "Member" .. j] and _G["CompactRaidGroup" .. i .. "Member" .. j]:IsShown() and _G["CompactRaidGroup" .. i .. "Member" .. j].unit then
					local tmpUnit = _G["CompactRaidGroup" .. i .. "Member" .. j].unit
					if UnitIsGroupLeader(tmpUnit) then
						ensureLeaderFrame(_G["CompactRaidFrameContainer"], _G["CompactRaidGroup" .. i .. "Member" .. j])
						leaderFound = true
					elseif UnitIsRaidOfficer(tmpUnit) then
						ensureAssistFrame(tmpUnit, _G["CompactRaidFrameContainer"], _G["CompactRaidGroup" .. i .. "Member" .. j])
					end
				end
			end
		end
	end

	if not leaderFound then removeLeaderIcon() end
end
addon.functions.setLeaderIcon = setLeaderIcon

local function GameTooltipActionButton(button)
	button:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip_SetDefaultAnchor(GameTooltip, UIParent) -- Use default positioning
		GameTooltip.default = 1

		if self.action then
			GameTooltip:SetAction(self.action) -- Displays the action of the button (spell, item, etc.)
		else
			GameTooltip:Hide() -- Hide the tooltip if no action is assigned
		end

		GameTooltip:Show()
	end)
	button:HookScript("OnLeave", function(self) GameTooltip:Hide() end)
end

local visibilityRuleMetadata = {
	MOUSEOVER = {
		key = "MOUSEOVER",
		label = L["visibilityRule_mouseover"] or (L["ActionBarVisibilityMouseover"] or "Mouseover"),
		description = L["visibilityRule_mouseover_desc"],
		appliesTo = { actionbar = true, frame = true },
		order = 10,
	},
	ALWAYS_IN_COMBAT = {
		key = "ALWAYS_IN_COMBAT",
		label = L["visibilityRule_inCombat"] or (L["ActionBarVisibilityInCombat"] or "Always in combat"),
		description = L["visibilityRule_inCombat_desc"],
		appliesTo = { actionbar = true, frame = true },
		contextKey = "inCombat",
		order = 20,
	},
	ALWAYS_OUT_OF_COMBAT = {
		key = "ALWAYS_OUT_OF_COMBAT",
		label = L["visibilityRule_outCombat"] or (L["ActionBarVisibilityOutOfCombat"] or "Always out of combat"),
		description = L["visibilityRule_outCombat_desc"],
		appliesTo = { actionbar = true, frame = true },
		contextKey = "outOfCombat",
		order = 30,
	},
	PLAYER_HEALTH_NOT_FULL = {
		key = "PLAYER_HEALTH_NOT_FULL",
		label = L["visibilityRule_playerHealth"] or "Player health below 100%",
		description = L["visibilityRule_playerHealth_desc"],
		appliesTo = { frame = true },
		unitRequirement = "player",
		order = 40,
	},
	PLAYER_HAS_TARGET = {
		key = "PLAYER_HAS_TARGET",
		label = L["visibilityRule_playerHasTarget"] or "When I have a target",
		description = L["visibilityRule_playerHasTarget_desc"],
		appliesTo = { frame = true },
		unitRequirement = "player",
		order = 45,
	},
	ALWAYS_HIDE_IN_GROUP = {
		key = "ALWAYS_HIDE_IN_GROUP",
		label = L["visibilityRule_groupedHide"] or "Always hide in party/raid",
		description = L["visibilityRule_groupedHide_desc"]
			or "Hides the player frame whenever you are in a party or raid. While grouped, only this rule (and Mouseover, if enabled) is evaluated; other visibility rules are ignored.",
		appliesTo = { frame = true },
		unitRequirement = "player",
		order = 47,
	},
	SKYRIDING_ACTIVE = {
		key = "SKYRIDING_ACTIVE",
		label = L["visibilityRule_skyriding"] or "While skyriding",
		description = L["visibilityRule_skyriding_desc"],
		appliesTo = { actionbar = true },
		order = 25,
	},
	ALWAYS_HIDDEN = {
		key = "ALWAYS_HIDDEN",
		label = L["visibilityRule_alwaysHidden"] or "Always hidden",
		description = L["visibilityRule_alwaysHidden_desc"],
		appliesTo = { frame = true },
		advanced = true,
		order = 100,
	},
}
addon.constants = addon.constants or {}
addon.constants.VISIBILITY_RULES = visibilityRuleMetadata
function addon.functions.GetVisibilityRuleMetadata() return visibilityRuleMetadata end

local FRAME_VISIBILITY_KEYS = {}
local ACTIONBAR_VISIBILITY_KEYS = {}
for key, meta in pairs(visibilityRuleMetadata) do
	if meta.appliesTo then
		if meta.appliesTo.frame then FRAME_VISIBILITY_KEYS[key] = true end
		if meta.appliesTo.actionbar then ACTIONBAR_VISIBILITY_KEYS[key] = true end
	end
end
addon.constants.FRAME_VISIBILITY_KEYS = FRAME_VISIBILITY_KEYS
addon.constants.ACTIONBAR_VISIBILITY_KEYS = ACTIONBAR_VISIBILITY_KEYS

local function copyVisibilityFlags(source, allowedKeys)
	if type(source) ~= "table" then return nil end
	local result
	for key in pairs(allowedKeys) do
		if source[key] then
			result = result or {}
			result[key] = true
		end
	end
	return result
end

local function NormalizeUnitFrameVisibilityConfig(varName, incoming)
	local source = incoming
	if source == nil and addon.db then source = addon.db[varName] end
	local config

	if type(source) == "table" then
		config = copyVisibilityFlags(source, FRAME_VISIBILITY_KEYS)
	elseif source == true or source == "MOUSEOVER" then
		config = { MOUSEOVER = true }
	elseif source == "hide" then
		config = { ALWAYS_HIDDEN = true }
	elseif source == "[combat] show; hide" then
		config = { ALWAYS_IN_COMBAT = true }
	elseif source == "[combat] hide; show" then
		config = { ALWAYS_OUT_OF_COMBAT = true }
	elseif source == false or source == "" then
		config = nil
	end

	if config and not next(config) then config = nil end

	if addon.db and varName then addon.db[varName] = config end
	return config
end
addon.functions.NormalizeUnitFrameVisibilityConfig = NormalizeUnitFrameVisibilityConfig

local function MigrateLegacyVisibilityFlag(oldKey, targetVar)
	if not addon.db or addon.db[oldKey] == nil then return end
	local legacy = addon.db[oldKey]
	addon.db[oldKey] = nil
	if legacy then addon.db[targetVar] = "hide" end
end

local function MigrateLegacyVisibilityFlags()
	if not addon.db then return end
	MigrateLegacyVisibilityFlag("hidePlayerFrame", "unitframeSettingPlayerFrame")
	MigrateLegacyVisibilityFlag("hideMicroMenu", "unitframeSettingMicroMenu")
	MigrateLegacyVisibilityFlag("hideBagsBar", "unitframeSettingBagsBar")
end

local FRAME_VISIBILITY_FADE_DURATION = 0.15
local FRAME_VISIBILITY_FADE_THRESHOLD = 0.01

local function StopFrameFade(target)
	local group = target and target.EQOL_FadeGroup
	if group and group.Stop then group:Stop() end
	if group then group.targetAlpha = nil end
end

local function ApplyAlphaToRegion(target, alpha, useFade)
	if not target or not target.SetAlpha then return end
	if not useFade or not target.CreateAnimationGroup then
		StopFrameFade(target)
		target:SetAlpha(alpha)
		return
	end

	-- TODO disable for midnight for now until a fix is found:
	--[[
		6x ...aceBlizzard_UnitFrame/Mainline/UnitFrame.lua:256: attempt to compare local 'myCurrentHealAbsorb' (a secret value)
		[Blizzard_UnitFrame/Mainline/UnitFrame.lua]:256: in function 'UnitFrameHealPredictionBars_Update'
		[Blizzard_UnitFrame/Mainline/UnitFrame.lua]:230: in function 'UnitFrameHealPredictionBars_UpdateSize'
		[Blizzard_UnitFrame/Mainline/PetFrame.lua]:221: in function <...faceBlizzard_UnitFrame/Mainline/PetFrame.lua:220>
		[C]: in function 'Play'
		[EnhanceQoL/EnhanceQoL.lua]:581: in function <EnhanceQoL/EnhanceQoL.lua:512>
		[EnhanceQoL/EnhanceQoL.lua]:814: in function <EnhanceQoL/EnhanceQoL.lua:812>
		[EnhanceQoL/EnhanceQoL.lua]:895: in function <EnhanceQoL/EnhanceQoL.lua:858>
		[EnhanceQoL/EnhanceQoL.lua]:907: in function <EnhanceQoL/EnhanceQoL.lua:903>
	--]]
	if addon.variables.isMidnight then
		StopFrameFade(target)
		target:SetAlpha(alpha)
		return
	end

	if issecretvalue and issecretvalue(alpha) then
		StopFrameFade(target)
		target:SetAlpha(alpha)
		return
	end

	local current = target:GetAlpha()
	if issecretvalue and issecretvalue(current) then
		StopFrameFade(target)
		target:SetAlpha(alpha)
		return
	end

	local delta = current - alpha
	if issecretvalue and issecretvalue(delta) then
		StopFrameFade(target)
		target:SetAlpha(alpha)
		return
	end

	if math.abs(delta) < FRAME_VISIBILITY_FADE_THRESHOLD then
		StopFrameFade(target)
		target:SetAlpha(alpha)
		return
	end

	local group = target.EQOL_FadeGroup
	if not group or not group.fade then
		if not target.CreateAnimationGroup then
			target:SetAlpha(alpha)
			return
		end
		group = target:CreateAnimationGroup()
		if not group then
			target:SetAlpha(alpha)
			return
		end
		local anim = group:CreateAnimation("Alpha")
		if anim and anim.SetSmoothing then anim:SetSmoothing("IN_OUT") end
		group.fade = anim
		group:SetScript("OnFinished", function(self)
			local desired = self.targetAlpha
			local owner = self:GetParent()
			if owner and owner.SetAlpha and desired ~= nil then owner:SetAlpha(desired) end
			self.targetAlpha = nil
		end)
		target.EQOL_FadeGroup = group
	end

	local anim = group.fade
	if not anim or not anim.SetFromAlpha or not anim.SetToAlpha or not anim.SetDuration then
		StopFrameFade(target)
		target:SetAlpha(alpha)
		return
	end

	if group:IsPlaying() then group:Stop() end
	anim:SetFromAlpha(current)
	anim:SetToAlpha(alpha)
	anim:SetDuration(FRAME_VISIBILITY_FADE_DURATION)
	group.targetAlpha = alpha

	group:Play()
end

local function RestoreUnitFrameVisibility(frame, cbData)
	ApplyAlphaToRegion(frame, 1, false)
	if cbData and cbData.children then
		for _, child in pairs(cbData.children) do
			ApplyAlphaToRegion(child, 1, false)
		end
	end
	if cbData and cbData.hideChildren then
		for _, child in pairs(cbData.hideChildren) do
			ApplyAlphaToRegion(child, 1, false)
		end
	end
end

local UpdateUnitFrameMouseover -- forward declaration

local frameVisibilityContext = {
	inCombat = false,
	playerHealthMissing = false,
	playerHealthAlpha = 0,
	hasTarget = false,
	inGroup = false,
}
local frameVisibilityStates = {}
local hookedUnitFrames = {}
local frameVisibilityHealthEnabled = false
local FRAME_VISIBILITY_HEALTH_THROTTLE = 0.1
local ApplyFrameVisibilityState -- forward declaration
local midnightPlayerHealthCurve

local function GetMidnightPlayerHealthAlpha()
	if not addon or not addon.variables or not addon.variables.isMidnight then return nil end
	if not UnitHealthPercentColor or not C_CurveUtil or not C_CurveUtil.CreateColorCurve or not CreateColor then return nil end

	if not midnightPlayerHealthCurve then
		local curve = C_CurveUtil.CreateColorCurve()
		if not curve then return nil end
		if curve.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then curve:SetType(Enum.LuaCurveType.Step) end
		if curve.AddPoint then
			curve:AddPoint(0, CreateColor(1, 1, 1, 1))
			curve:AddPoint(1, CreateColor(1, 1, 1, 0))
			midnightPlayerHealthCurve = curve
		end
	end

	local ok, color = pcall(UnitHealthPercentColor, "player", midnightPlayerHealthCurve)
	if not ok or not color or not color.GetRGBA then return nil end
	local _, _, _, alpha = color:GetRGBA()
	return alpha
end

local function UpdateFrameVisibilityContext()
	local inCombat = false
	if InCombatLockdown and InCombatLockdown() then
		inCombat = true
	elseif UnitAffectingCombat then
		inCombat = UnitAffectingCombat("player") and true or false
	end
	frameVisibilityContext.inCombat = inCombat

	local hasTarget = UnitExists and UnitExists("target") and true or false
	frameVisibilityContext.hasTarget = hasTarget
	frameVisibilityContext.inGroup = (IsInGroup and IsInGroup()) and true or false

	if frameVisibilityHealthEnabled then
		local isMidnight = addon and addon.variables and addon.variables.isMidnight
		if isMidnight then
			local alpha = GetMidnightPlayerHealthAlpha()
			if type(alpha) ~= "number" then alpha = 0 end
			frameVisibilityContext.playerHealthAlpha = alpha
			frameVisibilityContext.playerHealthMissing = true
		else
			local maxHP = UnitHealthMax and UnitHealthMax("player") or 0
			local currentHP = UnitHealth and UnitHealth("player") or 0
			local missing = maxHP > 0 and currentHP < maxHP
			frameVisibilityContext.playerHealthMissing = missing
			frameVisibilityContext.playerHealthAlpha = missing and 1 or 0
		end
	else
		frameVisibilityContext.playerHealthMissing = false
		frameVisibilityContext.playerHealthAlpha = 0
	end
end

local function SafeRegisterUnitEvent(frame, event, ...)
	if not frame or not frame.RegisterUnitEvent or type(event) ~= "string" then return false end
	local ok = pcall(frame.RegisterUnitEvent, frame, event, ...)
	return ok
end

local function FrameVisibilityNeedsHealthRule()
	for _, state in pairs(frameVisibilityStates) do
		if state.config and state.config.PLAYER_HEALTH_NOT_FULL and state.supportsPlayerHealthRule then return true end
	end
	return false
end

local function BuildUnitFrameDriverExpression(config)
	if not config then return nil end
	if config.ALWAYS_HIDDEN then return "hide" end
	if config.ALWAYS_HIDE_IN_GROUP then return nil end
	local inCombat = config.ALWAYS_IN_COMBAT == true
	local outCombat = config.ALWAYS_OUT_OF_COMBAT == true
	if inCombat and outCombat then return "show" end
	if inCombat then return "[combat] show; hide" end
	if outCombat then return "[combat] hide; show" end
	return nil
end

local function EnsureUnitFrameDriverWatcher()
	addon.variables = addon.variables or {}
	if addon.variables.unitFrameDriverWatcher then return end
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	watcher:SetScript("OnEvent", function()
		local pending = addon.variables.pendingUnitFrameDriverUpdates
		if not pending then return end
		addon.variables.pendingUnitFrameDriverUpdates = nil
		for frame, data in pairs(pending) do
			if frame then
				if not data or not data.expression then
					if UnregisterStateDriver then pcall(UnregisterStateDriver, frame, "visibility") end
					frame.EQOL_VisibilityStateDriver = nil
				elseif RegisterStateDriver then
					local ok = pcall(RegisterStateDriver, frame, "visibility", data.expression)
					if ok then frame.EQOL_VisibilityStateDriver = data.expression end
				end
			end
		end
	end)
	addon.variables.unitFrameDriverWatcher = watcher
end

local function ApplyUnitFrameStateDriver(frame, expression)
	if not frame then return end
	if frame.EQOL_VisibilityStateDriver == expression then return end
	if InCombatLockdown and InCombatLockdown() then
		addon.variables = addon.variables or {}
		addon.variables.pendingUnitFrameDriverUpdates = addon.variables.pendingUnitFrameDriverUpdates or {}
		addon.variables.pendingUnitFrameDriverUpdates[frame] = { expression = expression }
		EnsureUnitFrameDriverWatcher()
		return
	end
	if not expression then
		if UnregisterStateDriver then pcall(UnregisterStateDriver, frame, "visibility") end
		frame.EQOL_VisibilityStateDriver = nil
		return
	end
	if RegisterStateDriver then
		local ok = pcall(RegisterStateDriver, frame, "visibility", expression)
		if ok then frame.EQOL_VisibilityStateDriver = expression end
	end
end

local function UpdateFrameVisibilityHealthRegistration()
	local needs = FrameVisibilityNeedsHealthRule()
	frameVisibilityHealthEnabled = needs
	local watcher = addon.variables and addon.variables.frameVisibilityWatcher
	if not watcher then return end

	if needs then
		if watcher._eqol_healthRegistered then return end
		SafeRegisterUnitEvent(watcher, "UNIT_HEALTH", "player")
		SafeRegisterUnitEvent(watcher, "UNIT_MAXHEALTH", "player")
		watcher._eqol_healthRegistered = true
	else
		if not watcher._eqol_healthRegistered then return end
		watcher:UnregisterEvent("UNIT_HEALTH")
		watcher:UnregisterEvent("UNIT_MAXHEALTH")
		watcher._eqol_healthRegistered = false
		watcher._eqol_lastHealthEvent = nil
	end
end

local function RefreshAllFrameVisibilities()
	for _, state in pairs(frameVisibilityStates) do
		ApplyFrameVisibilityState(state)
	end
end

local function EnsureFrameVisibilityWatcher()
	addon.variables = addon.variables or {}
	if addon.variables.frameVisibilityWatcher then return end

	local watcher = CreateFrame("Frame")
	watcher:SetScript("OnEvent", function(self, event, unit)
		local isHealthEvent = event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH"
		if isHealthEvent then
			if not frameVisibilityHealthEnabled or unit ~= "player" then return end
			local now = GetTime()
			local last = self._eqol_lastHealthEvent or 0
			if (now - last) < FRAME_VISIBILITY_HEALTH_THROTTLE then return end
			self._eqol_lastHealthEvent = now
		end
		UpdateFrameVisibilityContext()
		RefreshAllFrameVisibilities()
	end)
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
	watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
	addon.variables.frameVisibilityWatcher = watcher
	UpdateFrameVisibilityContext()
	UpdateFrameVisibilityHealthRegistration()
end

local function EvaluateFrameVisibility(state)
	local cfg = state.config
	if not cfg or not next(cfg) then return false, nil end

	if cfg.ALWAYS_HIDDEN then return false, "ALWAYS_HIDDEN" end
	local context = frameVisibilityContext

	if cfg.ALWAYS_HIDE_IN_GROUP and state.supportsGroupRule and context.inGroup then
		if cfg.MOUSEOVER and state.isMouseOver then return true, "MOUSEOVER" end
		return false, "ALWAYS_HIDE_IN_GROUP"
	end

	if cfg.ALWAYS_IN_COMBAT and context.inCombat then return true, "ALWAYS_IN_COMBAT" end
	if cfg.ALWAYS_OUT_OF_COMBAT and not context.inCombat then return true, "ALWAYS_OUT_OF_COMBAT" end
	if cfg.PLAYER_HAS_TARGET and state.supportsPlayerTargetRule and context.hasTarget then return true, "PLAYER_HAS_TARGET" end
	if cfg.MOUSEOVER and state.isMouseOver then return true, "MOUSEOVER" end
	if cfg.PLAYER_HEALTH_NOT_FULL and state.supportsPlayerHealthRule and context.playerHealthMissing then return true, "PLAYER_HEALTH_NOT_FULL" end

	return false, nil
end

local function ApplyToFrameAndChildren(state, alpha, useFade)
	local frame = state.frame
	if frame then ApplyAlphaToRegion(frame, alpha, useFade) end

	if state.cbData and state.cbData.children then
		for _, child in pairs(state.cbData.children) do
			ApplyAlphaToRegion(child, alpha, useFade)
		end
	end

	if state.cbData and state.cbData.hideChildren then
		for _, child in pairs(state.cbData.hideChildren) do
			ApplyAlphaToRegion(child, alpha, useFade)
		end
	end
end

local function genericHoverOutCheck(state)
	if not state or not state.frame then return end
	if not state.config or not state.config.MOUSEOVER then return end

	C_Timer.After(0.05, function()
		if not state.frame or frameVisibilityStates[state.frame] ~= state then return end
		if not state.frame:IsVisible() then return end

		local hovered = MouseIsOver(state.frame)
		if not hovered and state.cbData and state.cbData.revealAllChilds and state.cbData.children then
			for _, child in pairs(state.cbData.children) do
				if child and child:IsVisible() and MouseIsOver(child) then
					hovered = true
					break
				end
			end
		end

		state.isMouseOver = hovered
		if hovered then
			C_Timer.After(0.3, function()
				if frameVisibilityStates[state.frame] == state then genericHoverOutCheck(state) end
			end)
		else
			ApplyFrameVisibilityState(state)
		end
	end)
end

ApplyFrameVisibilityState = function(state)
	local cfg = state.config
	if not cfg or not next(cfg) then
		if state.visible ~= nil then RestoreUnitFrameVisibility(state.frame, state.cbData) end
		frameVisibilityStates[state.frame] = nil
		UpdateFrameVisibilityHealthRegistration()
		return
	end

	if state.driverActive then return end

	EnsureFrameVisibilityWatcher()
	local context = frameVisibilityContext
	local shouldShow, activeRule = EvaluateFrameVisibility(state)
	local targetAlpha = shouldShow and 1 or 0
	local isMidnightPlayerFrame = addon and addon.variables and addon.variables.isMidnight and state.frame == _G.PlayerFrame
	local applyMidnightAlpha = shouldShow and activeRule == "PLAYER_HEALTH_NOT_FULL" and isMidnightPlayerFrame

	if applyMidnightAlpha then
		local midnightAlpha = context.playerHealthAlpha
		if midnightAlpha == nil then midnightAlpha = 0 end
		targetAlpha = midnightAlpha
	end

	if shouldShow then
		if state.visible == true and not applyMidnightAlpha then
			UpdateFrameVisibilityHealthRegistration()
			if addon.variables.isMidnight then ApplyToFrameAndChildren(state, targetAlpha, not applyMidnightAlpha) end
			return
		end
	else
		if state.visible == false then
			UpdateFrameVisibilityHealthRegistration()
			return
		end
	end

	ApplyToFrameAndChildren(state, targetAlpha, not applyMidnightAlpha)
	state.visible = shouldShow
	UpdateFrameVisibilityHealthRegistration()
end

local function HookFrameForMouseover(frame, cbData)
	if hookedUnitFrames[frame] then return end

	local function handleEnter()
		local state = frameVisibilityStates[frame]
		if not state or not state.config or not state.config.MOUSEOVER then return end
		state.isMouseOver = true
		ApplyFrameVisibilityState(state)
	end

	local function handleLeave()
		local state = frameVisibilityStates[frame]
		if not state then return end
		genericHoverOutCheck(state)
	end

	if frame.OnEnter or frame:GetScript("OnEnter") then
		frame:HookScript("OnEnter", handleEnter)
	else
		frame:SetScript("OnEnter", handleEnter)
	end

	if frame.OnLeave or frame:GetScript("OnLeave") then
		frame:HookScript("OnLeave", handleLeave)
	else
		frame:SetScript("OnLeave", handleLeave)
	end

	if cbData and cbData.children and cbData.revealAllChilds then
		for _, child in pairs(cbData.children) do
			if child and not child.EQOL_MouseoverHooked then
				child:HookScript("OnEnter", function()
					local state = frameVisibilityStates[frame]
					if not state or not state.config or not state.config.MOUSEOVER then return end
					state.isMouseOver = true
					ApplyFrameVisibilityState(state)
				end)
				child:HookScript("OnLeave", function()
					local state = frameVisibilityStates[frame]
					if not state then return end
					genericHoverOutCheck(state)
				end)
				child.EQOL_MouseoverHooked = true
			end
		end
	end

	hookedUnitFrames[frame] = true
end

local function EnsureFrameState(frame, cbData)
	local state = frameVisibilityStates[frame]
	if not state then
		state = { frame = frame, cbData = cbData, isMouseOver = false }
		frameVisibilityStates[frame] = state
		HookFrameForMouseover(frame, cbData)
	else
		state.cbData = cbData
	end
	return state
end

local function ClearUnitFrameState(frame, cbData)
	if not frame then return end
	ApplyUnitFrameStateDriver(frame, nil)
	RestoreUnitFrameVisibility(frame, cbData)
	frameVisibilityStates[frame] = nil
end

local function ApplyVisibilityToUnitFrame(frameName, cbData, config)
	if type(frameName) ~= "string" or frameName == "" then return false end
	local frame = _G[frameName]
	if not frame then return false end

	if not config then
		ClearUnitFrameState(frame, cbData)
		return true
	end

	local state = EnsureFrameState(frame, cbData)
	state.config = config
	local isPlayerUnit = (cbData.unitToken == "player")
	state.supportsPlayerHealthRule = isPlayerUnit
	state.supportsPlayerTargetRule = isPlayerUnit
	state.supportsGroupRule = isPlayerUnit

	local driverExpression = BuildUnitFrameDriverExpression(config)
	local needsHealth = config and config.PLAYER_HEALTH_NOT_FULL and state.supportsPlayerHealthRule
	local useDriver = driverExpression and not config.MOUSEOVER and not needsHealth

	if useDriver then
		state.driverActive = true
		ApplyUnitFrameStateDriver(frame, driverExpression)
		ApplyToFrameAndChildren(state, 1, false)
		return true
	end

	state.driverActive = false
	ApplyUnitFrameStateDriver(frame, nil)

	if config.MOUSEOVER then
		state.isMouseOver = MouseIsOver(frame)
	else
		state.isMouseOver = false
	end
	ApplyFrameVisibilityState(state)
	return true
end

UpdateUnitFrameMouseover = function(barName, cbData)
	if not cbData or not cbData.var then return end

	local config = NormalizeUnitFrameVisibilityConfig(cbData.var)
	-- local handled = false

	local function processTarget(name)
		if ApplyVisibilityToUnitFrame(name, cbData, config) then
			-- handled = true
		end
	end

	local onlyChildren = cbData.onlyChildren
	local hasChildTargets = false
	if type(onlyChildren) == "table" then
		local seen = {}
		for _, child in ipairs(onlyChildren) do
			if type(child) == "string" and child ~= "" and not seen[child] then
				processTarget(child)
				seen[child] = true
				hasChildTargets = true
			end
		end
		for _, child in pairs(onlyChildren) do
			if type(child) == "string" and child ~= "" and not seen[child] then
				processTarget(child)
				seen[child] = true
				hasChildTargets = true
			end
		end
		if hasChildTargets then
			local container = _G[barName]
			ClearUnitFrameState(container, cbData)
		end
	end

	if not hasChildTargets then processTarget(barName) end

	UpdateFrameVisibilityHealthRegistration()
end
addon.functions.UpdateUnitFrameMouseover = UpdateUnitFrameMouseover

local function ApplyUnitFrameSettingByVar(varName)
	if not varName then return end
	for _, data in ipairs(addon.variables.unitFrameNames) do
		if data.var == varName and data.name then
			UpdateUnitFrameMouseover(data.name, data)
			break
		end
	end
end
addon.functions.ApplyUnitFrameSettingByVar = ApplyUnitFrameSettingByVar

local hookedButtons = {}

-- Keep action bars visible while interacting with SpellFlyout
local EQOL_LastMouseoverBar
local EQOL_LastMouseoverVar

local function EQOL_ShouldKeepVisibleByFlyout() return _G.SpellFlyout and _G.SpellFlyout:IsShown() and MouseIsOver(_G.SpellFlyout) end

local function GetActionBarVisibilityConfig(variable, incoming, persistLegacy)
	local source = incoming
	if source == nil and addon.db then source = addon.db[variable] end

	local config
	if type(source) == "table" then
		config = {
			MOUSEOVER = source.MOUSEOVER == true,
			ALWAYS_IN_COMBAT = source.ALWAYS_IN_COMBAT == true,
			ALWAYS_OUT_OF_COMBAT = source.ALWAYS_OUT_OF_COMBAT == true,
			SKYRIDING_ACTIVE = source.SKYRIDING_ACTIVE == true,
		}
	elseif source == true then
		config = {
			MOUSEOVER = true,
			ALWAYS_IN_COMBAT = false,
			ALWAYS_OUT_OF_COMBAT = false,
			SKYRIDING_ACTIVE = false,
		}
	else
		config = nil
	end

	if config and not (config.MOUSEOVER or config.ALWAYS_IN_COMBAT or config.ALWAYS_OUT_OF_COMBAT or config.SKYRIDING_ACTIVE) then config = nil end

	if persistLegacy and addon.db then
		if not config then
			addon.db[variable] = nil
		else
			local stored = {}
			if config.MOUSEOVER then stored.MOUSEOVER = true end
			if config.ALWAYS_IN_COMBAT then stored.ALWAYS_IN_COMBAT = true end
			if config.ALWAYS_OUT_OF_COMBAT then stored.ALWAYS_OUT_OF_COMBAT = true end
			if config.SKYRIDING_ACTIVE then stored.SKYRIDING_ACTIVE = true end
			addon.db[variable] = stored
		end
	end

	return config
end

local function NormalizeActionBarVisibilityConfig(variable, incoming) return GetActionBarVisibilityConfig(variable, incoming, true) end
addon.functions.NormalizeActionBarVisibilityConfig = NormalizeActionBarVisibilityConfig

local function ActionBarShouldForceShowByConfig(config, combatOverride)
	if not config then return false end
	if config.SKYRIDING_ACTIVE and addon.variables and addon.variables.isPlayerSkyriding then return true end
	local inCombat = combatOverride
	if inCombat == nil then inCombat = InCombatLockdown and InCombatLockdown() end
	if inCombat then return config.ALWAYS_IN_COMBAT == true end
	return config.ALWAYS_OUT_OF_COMBAT == true
end

local function IsActionBarMouseoverEnabled(variable)
	local cfg = GetActionBarVisibilityConfig(variable)
	return cfg and cfg.MOUSEOVER == true
end

local function ApplyActionBarAlpha(bar, variable, config, combatOverride)
	if not bar then return end
	local cfg
	if type(config) == "table" then
		cfg = NormalizeActionBarVisibilityConfig(variable, config)
	elseif config ~= nil then
		cfg = NormalizeActionBarVisibilityConfig(variable, config)
	else
		cfg = GetActionBarVisibilityConfig(variable)
	end
	if not cfg then return end
	if ActionBarShouldForceShowByConfig(cfg, combatOverride) then
		ApplyAlphaToRegion(bar, 1, true)
		return
	end
	if cfg.MOUSEOVER then
		if MouseIsOver(bar) or EQOL_ShouldKeepVisibleByFlyout() then
			ApplyAlphaToRegion(bar, 1, true)
		else
			ApplyAlphaToRegion(bar, 0, true)
		end
	else
		ApplyAlphaToRegion(bar, 0, true)
	end
end

local function EQOL_HideBarIfNotHovered(bar, variable)
	local cfg = GetActionBarVisibilityConfig(variable)
	if not cfg then return end
	C_Timer.After(0, function()
		local current = GetActionBarVisibilityConfig(variable)
		if not current then return end
		if ActionBarShouldForceShowByConfig(current) then
			ApplyAlphaToRegion(bar, 1, true)
			return
		end
		if not current.MOUSEOVER then
			ApplyAlphaToRegion(bar, 0, true)
			return
		end
		-- Only hide if neither the bar nor the spell flyout is under the mouse
		if not MouseIsOver(bar) and not EQOL_ShouldKeepVisibleByFlyout() then
			ApplyAlphaToRegion(bar, 0, true)
		else
			ApplyAlphaToRegion(bar, 1, true)
		end
	end)
end
local function EQOL_HookSpellFlyout()
	local flyout = _G.SpellFlyout
	if not flyout or flyout.EQOL_MouseoverHooked then return end

	flyout:HookScript("OnEnter", function()
		if EQOL_LastMouseoverBar and IsActionBarMouseoverEnabled(EQOL_LastMouseoverVar) then EQOL_LastMouseoverBar:SetAlpha(1) end
	end)

	flyout:HookScript("OnLeave", function()
		if EQOL_LastMouseoverBar and IsActionBarMouseoverEnabled(EQOL_LastMouseoverVar) then EQOL_HideBarIfNotHovered(EQOL_LastMouseoverBar, EQOL_LastMouseoverVar) end
	end)

	flyout:HookScript("OnHide", function()
		if EQOL_LastMouseoverBar and IsActionBarMouseoverEnabled(EQOL_LastMouseoverVar) then EQOL_HideBarIfNotHovered(EQOL_LastMouseoverBar, EQOL_LastMouseoverVar) end
	end)

	flyout.EQOL_MouseoverHooked = true
end
-- Action Bars
local function UpdateActionBarMouseover(barName, config, variable)
	local bar = _G[barName]
	if not bar then return end

	local btnPrefix
	if barName == "MainMenuBar" or barName == "MainActionBar" then
		-- we have to change the Vehice Leave Button behaviour
		local leave = _G.MainMenuBarVehicleLeaveButton
		if leave then
			leave:SetIgnoreParentAlpha(true)
			leave:SetAlpha(1)
		end
		btnPrefix = "ActionButton"
	elseif barName == "PetActionBar" then
		btnPrefix = "PetActionButton"
	elseif barName == "StanceBar" then
		btnPrefix = "StanceButton"
	else
		btnPrefix = barName .. "Button"
	end

	local cfg = NormalizeActionBarVisibilityConfig(variable, config)

	if not cfg then
		bar:SetScript("OnEnter", nil)
		bar:SetScript("OnLeave", nil)
		bar:SetAlpha(1)
		if EQOL_LastMouseoverVar == variable then
			if EQOL_LastMouseoverBar == bar then EQOL_LastMouseoverBar = nil end
			EQOL_LastMouseoverVar = nil
		end
		return
	end

	if cfg.MOUSEOVER then
		bar:SetScript("OnEnter", function()
			local current = GetActionBarVisibilityConfig(variable)
			if not current or not current.MOUSEOVER then return end
			bar:SetAlpha(1)
			EQOL_LastMouseoverBar = bar
			EQOL_LastMouseoverVar = variable
		end)
		bar:SetScript("OnLeave", function() EQOL_HideBarIfNotHovered(bar, variable) end)
	else
		bar:SetScript("OnEnter", nil)
		bar:SetScript("OnLeave", nil)
	end

	local function handleButtonEnter()
		local current = GetActionBarVisibilityConfig(variable)
		if not current then return end
		if current.MOUSEOVER then
			bar:SetAlpha(1)
			EQOL_LastMouseoverBar = bar
			EQOL_LastMouseoverVar = variable
		elseif ActionBarShouldForceShowByConfig(current) then
			bar:SetAlpha(1)
		end
	end

	local function handleButtonLeave() EQOL_HideBarIfNotHovered(bar, variable) end

	for i = 1, 12 do
		local button = _G[btnPrefix .. i]
		if button and not hookedButtons[button] then
			if button.OnEnter then
				button:HookScript("OnEnter", handleButtonEnter)
				hookedButtons[button] = true
			else
				button:SetScript("OnEnter", handleButtonEnter)
			end
			if button.OnLeave then
				button:HookScript("OnLeave", handleButtonLeave)
			else
				button:EnableMouse(true)
				button:SetScript("OnLeave", function()
					handleButtonLeave()
					GameTooltip:Hide()
				end)
			end
			if not hookedButtons[button] then GameTooltipActionButton(button) end
		end
	end

	if cfg.MOUSEOVER then C_Timer.After(0, EQOL_HookSpellFlyout) end

	ApplyActionBarAlpha(bar, variable, cfg)
end
addon.functions.UpdateActionBarMouseover = UpdateActionBarMouseover

local function RefreshAllActionBarVisibilityAlpha(_, event)
	local combatOverride
	if event == "PLAYER_REGEN_DISABLED" then
		combatOverride = true
	elseif event == "PLAYER_REGEN_ENABLED" then
		combatOverride = false
	end
	for _, info in ipairs(addon.variables.actionBarNames or {}) do
		local bar = _G[info.name]
		if bar then ApplyActionBarAlpha(bar, info.var, nil, combatOverride) end
	end
end

local function EnsureSkyridingStateDriver()
	addon.variables = addon.variables or {}
	if addon.variables.skyridingDriver then return end
	local driver = CreateFrame("Frame")
	driver:Hide()
	driver:SetScript("OnShow", function()
		addon.variables.isPlayerSkyriding = true
		RefreshAllActionBarVisibilityAlpha()
	end)
	driver:SetScript("OnHide", function()
		addon.variables.isPlayerSkyriding = false
		RefreshAllActionBarVisibilityAlpha()
	end)
	local expr = "[advflyable, mounted] show; [advflyable, stance:3] show; hide"
	RegisterStateDriver(driver, "visibility", expr)
	addon.variables.skyridingDriver = driver
	addon.variables.isPlayerSkyriding = driver:IsShown()
end

local function EnsureActionBarVisibilityWatcher()
	addon.variables = addon.variables or {}
	if addon.variables.actionBarVisibilityWatcher then return end
	EnsureSkyridingStateDriver()
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:SetScript("OnEvent", function(_, event) RefreshAllActionBarVisibilityAlpha(nil, event) end)
	addon.variables.actionBarVisibilityWatcher = watcher
end

local DEFAULT_CHAT_BUBBLE_FONT_SIZE = 13
local CHAT_BUBBLE_FONT_MIN = 1
local CHAT_BUBBLE_FONT_MAX = 36

function addon.functions.ApplyChatBubbleFontSize(size)
	local desired = tonumber(size) or (addon.db and addon.db["chatBubbleFontSize"]) or DEFAULT_CHAT_BUBBLE_FONT_SIZE
	if desired < CHAT_BUBBLE_FONT_MIN then desired = CHAT_BUBBLE_FONT_MIN end
	if desired > CHAT_BUBBLE_FONT_MAX then desired = CHAT_BUBBLE_FONT_MAX end

	if ChatBubbleFont then
		addon.variables = addon.variables or {}
		if not addon.variables.defaultChatBubbleFont then
			local defaultFont, defaultSize, defaultFlags = ChatBubbleFont:GetFont()
			addon.variables.defaultChatBubbleFont = {
				font = defaultFont or STANDARD_TEXT_FONT,
				size = defaultSize or DEFAULT_CHAT_BUBBLE_FONT_SIZE,
				flags = defaultFlags or "",
			}
		end

		local override = addon.db and addon.db["chatBubbleFontOverride"]
		if override then
			local fontInfo = addon.variables.defaultChatBubbleFont or {}
			local font = STANDARD_TEXT_FONT or fontInfo.font
			local flags = fontInfo.flags or ""
			ChatBubbleFont:SetFont(font, desired, flags)
		else
			local defaults = addon.variables.defaultChatBubbleFont
			if defaults and defaults.font then
				ChatBubbleFont:SetFont(defaults.font, defaults.size, defaults.flags)
			elseif STANDARD_TEXT_FONT then
				ChatBubbleFont:SetFont(STANDARD_TEXT_FONT, DEFAULT_CHAT_BUBBLE_FONT_SIZE, "")
			end
		end
	end

	return desired
end

local function addMinimapFrame(container)
	local ui = { groups = {} }

	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	ui.scroll = scroll
	ui.wrapper = wrapper

	local function doLayout()
		if ui.scroll and ui.scroll.DoLayout then ui.scroll:DoLayout() end
	end

	local function ensureGroup(key, title)
		local g = ui.groups[key]
		if not g then
			g = addon.functions.createContainer("InlineGroup", "List")
			g:SetTitle(title)
			ui.groups[key] = g
			wrapper:AddChild(g)
		end
		g:ReleaseChildren()
		return g
	end

	local function buildGeneral()
		local g = ensureGroup("general", MINIMAP_LABEL)
		local cb = addon.functions.createCheckboxAce(L["enableWayCommand"], addon.db["enableWayCommand"], function(self, _, value)
			addon.db["enableWayCommand"] = value
			if value then
				addon.functions.registerWayCommand()
			else
				addon.variables.requireReload = true
			end
		end, L["enableWayCommandDesc"])
		g:AddChild(cb)
		doLayout()
	end

	local function buildSpec()
		local g = ensureGroup("spec", SPECIALIZATION)
		local cb = addon.functions.createCheckboxAce(L["enableLootspecQuickswitch"], addon.db["enableLootspecQuickswitch"], function(self, _, value)
			addon.db["enableLootspecQuickswitch"] = value
			if value then
				addon.functions.createLootspecFrame()
			else
				addon.functions.removeLootspecframe()
			end
		end, L["enableLootspecQuickswitchDesc"])
		g:AddChild(cb)
		doLayout()
	end

	local function buildHideElements()
		local g = ensureGroup("hideElements", HUD_EDIT_MODE_MINIMAP_LABEL)
		local dd = AceGUI:Create("Dropdown")
		dd:SetLabel(L["minimapHideElements"])
		local list = {
			Tracking = L["minimapHideElements_Tracking"],
			ZoneInfo = L["minimapHideElements_ZoneInfo"],
			Clock = L["minimapHideElements_Clock"],
			Calendar = L["minimapHideElements_Calendar"],
			Mail = L["minimapHideElements_Mail"],
			AddonCompartment = L["minimapHideElements_AddonCompartment"],
		}
		local order = { "Tracking", "ZoneInfo", "Clock", "Calendar", "Mail", "AddonCompartment" }
		dd:SetList(list, order)
		dd:SetMultiselect(true)
		dd:SetFullWidth(true)
		dd:SetCallback("OnValueChanged", function(widget, _, key, checked)
			addon.db.hiddenMinimapElements = addon.db.hiddenMinimapElements or {}
			addon.db.hiddenMinimapElements[key] = checked and true or false
			if addon.functions.ApplyMinimapElementVisibility then addon.functions.ApplyMinimapElementVisibility() end
		end)
		if type(addon.db.hiddenMinimapElements) == "table" then
			for k, v in pairs(addon.db.hiddenMinimapElements) do
				if v then dd:SetItemValue(k, true) end
			end
		end
		addon.elements["minimapHideElementsDD"] = dd
		g:AddChild(dd)
		doLayout()
	end

	local function buildSquare()
		local g = ensureGroup("square", L["SquareMinimap"])
		local cbSquare = addon.functions.createCheckboxAce(L["enableSquareMinimap"], addon.db["enableSquareMinimap"], function(self, _, value)
			addon.db["enableSquareMinimap"] = value
			addon.variables.requireReload = true
			addon.functions.checkReloadFrame()
		end, L["enableSquareMinimapDesc"])
		g:AddChild(cbSquare)

		if addon.db["enableSquareMinimap"] then
			local cbBorder = addon.functions.createCheckboxAce(L["enableSquareMinimapBorder"], addon.db["enableSquareMinimapBorder"], function(self, _, value)
				addon.db["enableSquareMinimapBorder"] = value
				if addon.functions.applySquareMinimapBorder then addon.functions.applySquareMinimapBorder() end
				buildSquare()
			end, L["enableSquareMinimapBorderDesc"])
			g:AddChild(cbBorder)

			if addon.db["enableSquareMinimapBorder"] then
				local size = addon.functions.createSliderAce(
					L["squareMinimapBorderSize"] .. ": " .. (addon.db["squareMinimapBorderSize"] or 1),
					addon.db["squareMinimapBorderSize"],
					1,
					8,
					1,
					function(self, _, val)
						addon.db["squareMinimapBorderSize"] = val
						self:SetLabel(L["squareMinimapBorderSize"] .. ": " .. tostring(val))
						if addon.functions.applySquareMinimapBorder then addon.functions.applySquareMinimapBorder() end
					end
				)
				g:AddChild(size)

				local cp = AceGUI:Create("ColorPicker")
				cp:SetLabel(L["squareMinimapBorderColor"])
				local c = addon.db["squareMinimapBorderColor"] or { r = 0, g = 0, b = 0 }
				cp:SetColor(c.r or 0, c.g or 0, c.b or 0)
				cp:SetCallback("OnValueChanged", function(_, _, r, g, b)
					addon.db["squareMinimapBorderColor"] = { r = r, g = g, b = b }
					if addon.functions.applySquareMinimapBorder then addon.functions.applySquareMinimapBorder() end
				end)
				g:AddChild(cp)
			end
		end
		doLayout()
	end

	local function buildButtonBin()
		local g = ensureGroup("buttonBin", L["MinimapButtonSinkGroup"])
		local cb = addon.functions.createCheckboxAce(L["enableMinimapButtonBin"], addon.db["enableMinimapButtonBin"], function(self, _, value)
			addon.db["enableMinimapButtonBin"] = value
			addon.functions.toggleButtonSink()
			buildButtonBin()
		end, L["enableMinimapButtonBinDesc"])
		g:AddChild(cb)

		if addon.db["enableMinimapButtonBin"] then
			local cbIcon = addon.functions.createCheckboxAce(L["useMinimapButtonBinIcon"], addon.db["useMinimapButtonBinIcon"], function(self, _, value)
				addon.db["useMinimapButtonBinIcon"] = value
				if value then addon.db["useMinimapButtonBinMouseover"] = false end
				addon.functions.toggleButtonSink()
				buildButtonBin()
			end)
			g:AddChild(cbIcon)

			local cbMouse = addon.functions.createCheckboxAce(L["useMinimapButtonBinMouseover"], addon.db["useMinimapButtonBinMouseover"], function(self, _, value)
				addon.db["useMinimapButtonBinMouseover"] = value
				if value then addon.db["useMinimapButtonBinIcon"] = false end
				addon.functions.toggleButtonSink()
				buildButtonBin()
			end)
			g:AddChild(cbMouse)

			local cbHideBg = addon.functions.createCheckboxAce(L["minimapButtonBinHideBackground"], addon.db["minimapButtonBinHideBackground"], function(self, _, value)
				addon.db["minimapButtonBinHideBackground"] = value and true or false
				if addon.functions.applyButtonSinkAppearance then addon.functions.applyButtonSinkAppearance() end
			end)
			g:AddChild(cbHideBg)

			local cbHideBorder = addon.functions.createCheckboxAce(L["minimapButtonBinHideBorder"], addon.db["minimapButtonBinHideBorder"], function(self, _, value)
				addon.db["minimapButtonBinHideBorder"] = value and true or false
				if addon.functions.applyButtonSinkAppearance then addon.functions.applyButtonSinkAppearance() end
			end)
			g:AddChild(cbHideBorder)

			if not addon.db["useMinimapButtonBinIcon"] then
				local cbLock = addon.functions.createCheckboxAce(L["lockMinimapButtonBin"], addon.db["lockMinimapButtonBin"], function(self, _, value)
					addon.db["lockMinimapButtonBin"] = value
					addon.functions.toggleButtonSink()
				end)
				g:AddChild(cbLock)
			end

			local currentColumns = tonumber(addon.db["minimapButtonBinColumns"]) or DEFAULT_BUTTON_SINK_COLUMNS
			currentColumns = math.floor(currentColumns + 0.5)
			if currentColumns < 1 then
				currentColumns = 1
			elseif currentColumns > 10 then
				currentColumns = 10
			end
			local columnSlider = addon.functions.createSliderAce(L["minimapButtonBinColumns"] .. ": " .. currentColumns, currentColumns, 1, 10, 1, function(self, _, val)
				val = math.floor(val + 0.5)
				if val < 1 then
					val = 1
				elseif val > 10 then
					val = 10
				end
				addon.db["minimapButtonBinColumns"] = val
				self:SetLabel(L["minimapButtonBinColumns"] .. ": " .. tostring(val))
				addon.functions.LayoutButtons()
			end)
			g:AddChild(columnSlider)

			local lbl = AceGUI:Create("Label")
			lbl:SetText(MINIMAP_LABEL .. ": " .. L["ignoreMinimapSinkHole"])
			lbl:SetFont(addon.variables.defaultFont, 12, "OUTLINE")
			lbl:SetFullWidth(true)
			g:AddChild(lbl)

			for i, _ in pairs(addon.variables.bagButtonState) do
				local cbIg = addon.functions.createCheckboxAce(i, addon.db["ignoreMinimapButtonBin_" .. i] or false, function(self, _, value)
					addon.db["ignoreMinimapButtonBin_" .. i] = value
					addon.functions.LayoutButtons()
				end)
				g:AddChild(cbIg)
			end
		end

		doLayout()
	end

	local function buildLanding()
		local g = ensureGroup("landing", L["LandingPage"])
		local cb = addon.functions.createCheckboxAce(
			L["enableLandingPageMenu"],
			addon.db["enableLandingPageMenu"],
			function(self, _, value) addon.db["enableLandingPageMenu"] = value end,
			L["enableLandingPageMenuDesc"]
		)
		g:AddChild(cb)

		local lbl = AceGUI:Create("Label")
		lbl:SetText(L["landingPageHide"])
		lbl:SetFont(addon.variables.defaultFont, 12, "OUTLINE")
		lbl:SetFullWidth(true)
		g:AddChild(lbl)

		for id in pairs(addon.variables.landingPageType) do
			local page = addon.variables.landingPageType[id]
			local actValue = addon.db["hiddenLandingPages"][id] or false
			local cbLP = addon.functions.createCheckboxAce(page.checkbox, actValue, function(self, _, value)
				addon.db["hiddenLandingPages"][id] = value
				addon.functions.toggleLandingPageButton(page.title, value)
			end)
			g:AddChild(cbLP)
		end
		doLayout()
	end

	local function buildInstanceDifficulty()
		local g = ensureGroup("instanceDiff", L["showInstanceDifficulty"])
		local cb = addon.functions.createCheckboxAce(L["showInstanceDifficulty"], addon.db["showInstanceDifficulty"], function(self, _, value)
			addon.db["showInstanceDifficulty"] = value
			if addon.InstanceDifficulty and addon.InstanceDifficulty.SetEnabled then addon.InstanceDifficulty:SetEnabled(value) end
			buildInstanceDifficulty()
		end, L["showInstanceDifficultyDesc"])
		g:AddChild(cb)

		if addon.db["showInstanceDifficulty"] then
			local sliderSize = addon.functions.createSliderAce(
				L["instanceDifficultyFontSize"] .. ": " .. addon.db["instanceDifficultyFontSize"],
				addon.db["instanceDifficultyFontSize"],
				8,
				28,
				1,
				function(self, _, val)
					addon.db["instanceDifficultyFontSize"] = val
					self:SetLabel(L["instanceDifficultyFontSize"] .. ": " .. tostring(val))
					if addon.InstanceDifficulty then addon.InstanceDifficulty:Update() end
				end
			)
			g:AddChild(sliderSize)

			local sliderX = addon.functions.createSliderAce(
				L["instanceDifficultyOffsetX"] .. ": " .. addon.db["instanceDifficultyOffsetX"],
				addon.db["instanceDifficultyOffsetX"],
				-400,
				400,
				1,
				function(self, _, val)
					addon.db["instanceDifficultyOffsetX"] = val
					self:SetLabel(L["instanceDifficultyOffsetX"] .. ": " .. tostring(val))
					if addon.InstanceDifficulty then addon.InstanceDifficulty:Update() end
				end
			)
			g:AddChild(sliderX)

			local sliderY = addon.functions.createSliderAce(
				L["instanceDifficultyOffsetY"] .. ": " .. addon.db["instanceDifficultyOffsetY"],
				addon.db["instanceDifficultyOffsetY"],
				-400,
				400,
				1,
				function(self, _, val)
					addon.db["instanceDifficultyOffsetY"] = val
					self:SetLabel(L["instanceDifficultyOffsetY"] .. ": " .. tostring(val))
					if addon.InstanceDifficulty then addon.InstanceDifficulty:Update() end
				end
			)
			g:AddChild(sliderY)

			local cbColors = addon.functions.createCheckboxAce(L["instanceDifficultyUseColors"], addon.db["instanceDifficultyUseColors"], function(self, _, v)
				addon.db["instanceDifficultyUseColors"] = v
				if addon.InstanceDifficulty then addon.InstanceDifficulty:Update() end
				buildInstanceDifficulty()
			end)
			g:AddChild(cbColors)

			if addon.db["instanceDifficultyUseColors"] then
				local colors = addon.db["instanceDifficultyColors"] or {}

				local function addCP(label, key)
					local cp = AceGUI:Create("ColorPicker")
					cp:SetLabel(label)
					local cc = colors[key] or { r = 1, g = 1, b = 1 }
					cp:SetColor(cc.r or 1, cc.g or 1, cc.b or 1)
					cp:SetCallback("OnValueChanged", function(_, _, r, g, b)
						addon.db["instanceDifficultyColors"][key] = { r = r, g = g, b = b }
						if addon.InstanceDifficulty then addon.InstanceDifficulty:Update() end
					end)
					g:AddChild(cp)
				end

				addCP(_G["PLAYER_DIFFICULTY3"] or "Raid Finder", "LFR")
				addCP(_G["PLAYER_DIFFICULTY1"] or "Normal", "NM")
				addCP(_G["PLAYER_DIFFICULTY2"] or "Heroic", "HC")
				addCP(_G["PLAYER_DIFFICULTY6"] or "Mythic", "M")
				addCP(_G["PLAYER_DIFFICULTY_MYTHIC_PLUS"] or "Mythic+", "MPLUS")
				addCP(_G["PLAYER_DIFFICULTY_TIMEWALKER"] or "Timewalking", "TW")
			end
		end

		doLayout()
	end

	buildGeneral()
	buildSpec()
	buildHideElements()
	buildSquare()
	buildButtonBin()
	buildLanding()
	buildInstanceDifficulty()
end

-- New modular Unit Frames UI builder
-- New modular Vendor & Economy UI builder

local function setCVarValue(cvarKey, newValue)
	if newValue == nil then return end

	newValue = tostring(newValue)
	local currentValue = GetCVar(cvarKey)
	if currentValue ~= nil then currentValue = tostring(currentValue) end

	if currentValue == newValue then return end

	local guard = addon.variables.cvarEnforceGuard
	if not guard then
		guard = {}
		addon.variables.cvarEnforceGuard = guard
	end

	guard[cvarKey] = true
	SetCVar(cvarKey, newValue)
end
addon.functions.setCVarValue = setCVarValue

local function initializePersistentCVars()
	if not addon.db then return end

	local overrides = addon.db.cvarOverrides or {}
	addon.db.cvarOverrides = overrides

	local persistentKeys = addon.variables.cvarPersistentKeys
	if persistentKeys then
		wipe(persistentKeys)
	else
		persistentKeys = {}
		addon.variables.cvarPersistentKeys = persistentKeys
	end

	if not addon.variables.cvarEnforceGuard then addon.variables.cvarEnforceGuard = {} end

	local persistenceEnabled = addon.db.cvarPersistenceEnabled and true or false

	for cvarKey, optionData in pairs(addon.variables.cvarOptions) do
		if optionData.persistent then
			persistentKeys[cvarKey] = true

			if optionData.register and nil == GetCVar(cvarKey) then C_CVar.RegisterCVar(cvarKey, optionData.trueValue) end

			local currentValue = GetCVar(cvarKey)
			if currentValue ~= nil then
				currentValue = tostring(currentValue)
			elseif optionData.falseValue ~= nil then
				currentValue = tostring(optionData.falseValue)
			elseif optionData.trueValue ~= nil then
				currentValue = tostring(optionData.trueValue)
			else
				currentValue = "0"
			end

			if overrides[cvarKey] == nil then
				overrides[cvarKey] = currentValue
			else
				overrides[cvarKey] = tostring(overrides[cvarKey])
			end

			if persistenceEnabled then
				local desiredValue = overrides[cvarKey]
				if desiredValue and currentValue ~= desiredValue then setCVarValue(cvarKey, desiredValue) end
			end
		end
	end
end

addon.functions.initializePersistentCVars = initializePersistentCVars

-- removed: addPartyFrame (party settings relocated to Social/UI sections)

local function addQuestFrame(container, d)
	local list, order = addon.functions.prepareListForDropdown(addon.db["ignoredQuestNPC"])

	local scroll = addon.functions.createContainer("ScrollFrame", "List")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)
	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)

	local groupData = {
		{
			parent = "",
			var = "autoChooseQuest",
			text = L["autoChooseQuest"],
			type = "CheckBox",
			callback = function(self, _, value) addon.db[self.var] = value end,
			desc = L["interruptWithShift"],
		},
		{
			parent = "",
			var = "ignoreDailyQuests",
			text = L["ignoreDailyQuests"]:format(QUESTS_LABEL),
			type = "CheckBox",
			callback = function(self, _, value) addon.db[self.var] = value end,
		},
		{
			parent = "",
			var = "ignoreWarbandCompleted",
			text = L["ignoreWarbandCompleted"]:format(ACCOUNT_COMPLETED_QUEST_LABEL, QUESTS_LABEL),
			type = "CheckBox",
			callback = function(self, _, value) addon.db[self.var] = value end,
		},
		{
			parent = "",
			var = "ignoreTrivialQuests",
			text = L["ignoreTrivialQuests"]:format(QUESTS_LABEL),
			type = "CheckBox",
			callback = function(self, _, value) addon.db[self.var] = value end,
		},
		{
			parent = "",
			var = "questWowheadLink",
			text = L["questWowheadLink"],
			type = "CheckBox",
			callback = function(self, _, value) addon.db[self.var] = value end,
		},
		{
			parent = "",
			var = "autoCancelCinematic",
			text = L["autoCancelCinematic"],
			type = "CheckBox",
			desc = L["autoCancelCinematicDesc"] .. "\n" .. L["interruptWithShift"],
			callback = function(self, _, value) addon.db["autoCancelCinematic"] = value end,
		},
	}
	table.sort(groupData, function(a, b)
		local textA = a.var
		local textB = b.var
		if a.text then
			textA = a.text
		else
			textA = L[a.var]
		end
		if b.text then
			textB = b.text
		else
			textB = L[b.var]
		end
		return textA < textB
	end)
	for _, checkboxData in ipairs(groupData) do
		local desc
		if checkboxData.desc then desc = checkboxData.desc end
		local cbautoChooseQuest = addon.functions.createCheckboxAce(checkboxData.text, addon.db[checkboxData.var], function(self, _, value) addon.db[checkboxData.var] = value end, desc)
		groupCore:AddChild(cbautoChooseQuest)
	end

	local trackerGroup = addon.functions.createContainer("InlineGroup", "List")
	trackerGroup:SetTitle(L["questTrackerOptions"] or QUESTS_LABEL)
	wrapper:AddChild(trackerGroup)

	local function refreshTrackerControls()
		local enabled = addon.db.questTrackerShowQuestCount == true
		if trackerGroup._sliderX then trackerGroup._sliderX:SetDisabled(not enabled) end
		if trackerGroup._sliderY then trackerGroup._sliderY:SetDisabled(not enabled) end
	end

	local questCountCheckbox = addon.functions.createCheckboxAce(L["questTrackerShowQuestCount"] or "Show quest count under tracker", addon.db.questTrackerShowQuestCount, function(self, _, value)
		addon.db.questTrackerShowQuestCount = value and true or false
		refreshTrackerControls()
		addon.functions.UpdateQuestTrackerQuestCount()
	end, L["questTrackerShowQuestCount_desc"])
	trackerGroup:AddChild(questCountCheckbox)

	local function sliderLabelX(val) return string.format("%s: %d", L["questTrackerQuestCountOffsetX"] or (L["instanceDifficultyOffsetX"] or "Horizontal offset"), val) end
	local function sliderLabelY(val) return string.format("%s: %d", L["questTrackerQuestCountOffsetY"] or (L["instanceDifficultyOffsetY"] or "Vertical offset"), val) end

	local sliderX = addon.functions.createSliderAce(sliderLabelX(addon.db.questTrackerQuestCountOffsetX or 0), addon.db.questTrackerQuestCountOffsetX or 0, -200, 200, 1, function(self, _, value)
		local rounded = math.floor((value or 0) + 0.5)
		addon.db.questTrackerQuestCountOffsetX = rounded
		self:SetLabel(sliderLabelX(rounded))
		addon.functions.UpdateQuestTrackerQuestCountPosition()
	end)
	trackerGroup._sliderX = sliderX
	trackerGroup:AddChild(sliderX)

	local sliderY = addon.functions.createSliderAce(sliderLabelY(addon.db.questTrackerQuestCountOffsetY or 0), addon.db.questTrackerQuestCountOffsetY or 0, -200, 200, 1, function(self, _, value)
		local rounded = math.floor((value or 0) + 0.5)
		addon.db.questTrackerQuestCountOffsetY = rounded
		self:SetLabel(sliderLabelY(rounded))
		addon.functions.UpdateQuestTrackerQuestCountPosition()
	end)
	trackerGroup._sliderY = sliderY
	trackerGroup:AddChild(sliderY)
	refreshTrackerControls()

	local groupNPC = addon.functions.createContainer("InlineGroup", "List")
	groupNPC:SetTitle(L["questAddNPCToExclude"])
	wrapper:AddChild(groupNPC)

	local dropIncludeList = addon.functions.createDropdownAce(L["Excluded NPCs"], list, order, nil)
	local btnAddNPC = addon.functions.createButtonAce(ADD, 100, function(self, _, value)
		local guid = nil
		local name = nil
		local type = nil
		local unitType = nil

		if nil ~= UnitGUID("npc") then
			type = "npc"
		elseif nil ~= UnitGUID("target") then
			type = "target"
		else
			return
		end

		guid = UnitGUID(type)
		name = UnitName(type)
		unitType = strsplit("-", guid)

		if UnitCanAttack(type, "player") or (UnitPlayerControlled(type) and not unitType == "Vehicle") then return end -- ignore attackable and player types

		local mapID = C_Map.GetBestMapForUnit("player")
		if mapID and not unitType == "Vehicle" then
			local mapInfo = C_Map.GetMapInfo(mapID)
			if mapInfo and mapInfo.name then name = name .. " (" .. mapInfo.name .. ")" end
		end

		guid = addon.functions.getIDFromGUID(guid)
		if addon.db["ignoredQuestNPC"][guid] then return end -- no duplicates

		print(ADD .. ":", guid, name)

		addon.db["ignoredQuestNPC"][guid] = name
		local list, order = addon.functions.prepareListForDropdown(addon.db["ignoredQuestNPC"])

		dropIncludeList:SetList(list, order)
	end)
	local btnRemoveNPC = addon.functions.createButtonAce(REMOVE, 100, function(self, _, value)
		local selectedValue = dropIncludeList:GetValue() -- Hole den aktuellen Wert des Dropdowns
		if selectedValue then
			if addon.db["ignoredQuestNPC"][selectedValue] then
				addon.db["ignoredQuestNPC"][selectedValue] = nil -- Entferne aus der Datenbank
				-- Aktualisiere die Dropdown-Liste
				local list, order = addon.functions.prepareListForDropdown(addon.db["ignoredQuestNPC"])
				dropIncludeList:SetList(list, order)
				dropIncludeList:SetValue(nil) -- Setze die Auswahl zurück
			end
		end
	end)
	groupNPC:AddChild(btnAddNPC)
	groupNPC:AddChild(dropIncludeList)
	groupNPC:AddChild(btnRemoveNPC)
	scroll:DoLayout()
end

local QUEST_TRACKER_QUEST_COUNT_COLOR = { r = 1, g = 210 / 255, b = 0 }
local questTrackerQuestCountFrame
local questTrackerQuestCountText
local questTrackerQuestCountWatcher

local function GetQuestTrackerQuestCountText()
	if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then return "" end
	local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
	if not numQuests then numQuests = 0 end
	local maxQuests = C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()
	if not maxQuests or maxQuests <= 0 then
		if numQuests <= 0 then return "" end
		return tostring(numQuests)
	end
	return string.format("%d/%d", numQuests, maxQuests)
end

local function PositionQuestTrackerQuestCount()
	if not questTrackerQuestCountFrame or not addon or not addon.db then return end
	local header = _G.QuestObjectiveTracker and _G.QuestObjectiveTracker.Header
	if not header then return end
	questTrackerQuestCountFrame:ClearAllPoints()
	local x = addon.db.questTrackerQuestCountOffsetX or 0
	local y = addon.db.questTrackerQuestCountOffsetY or 0
	questTrackerQuestCountFrame:SetPoint("CENTER", header, "CENTER", x, y)
end

local function EnsureQuestTrackerQuestCountFrame()
	local header = _G.QuestObjectiveTracker and _G.QuestObjectiveTracker.Header
	if not header then return nil end
	if not questTrackerQuestCountFrame then
		questTrackerQuestCountFrame = CreateFrame("Frame", nil, header)
		questTrackerQuestCountFrame:SetSize(1, 1)
	end
	questTrackerQuestCountFrame:SetParent(header)
	if not questTrackerQuestCountText then
		questTrackerQuestCountText = questTrackerQuestCountFrame:CreateFontString(nil, "OVERLAY")
		questTrackerQuestCountText:SetPoint("TOPLEFT")
		questTrackerQuestCountText:SetJustifyH("LEFT")
		questTrackerQuestCountText:SetJustifyV("TOP")
	end
	local referenceFont = header.Text and header.Text:GetFontObject()
	if referenceFont then
		questTrackerQuestCountText:SetFontObject(referenceFont)
	else
		questTrackerQuestCountText:SetFont(addon.variables.defaultFont or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	end
	questTrackerQuestCountText:SetTextColor(QUEST_TRACKER_QUEST_COUNT_COLOR.r, QUEST_TRACKER_QUEST_COUNT_COLOR.g, QUEST_TRACKER_QUEST_COUNT_COLOR.b)
	return questTrackerQuestCountFrame
end

local function UpdateQuestTrackerQuestCountPosition()
	if not addon or not addon.db then return end
	if not questTrackerQuestCountFrame or not questTrackerQuestCountFrame:IsShown() then
		if addon.db.questTrackerShowQuestCount then addon.functions.UpdateQuestTrackerQuestCount() end
		return
	end
	PositionQuestTrackerQuestCount()
end
addon.functions.UpdateQuestTrackerQuestCountPosition = UpdateQuestTrackerQuestCountPosition

local function UpdateQuestTrackerQuestCount()
	if not addon or not addon.db or not addon.db.questTrackerShowQuestCount then
		if questTrackerQuestCountFrame then questTrackerQuestCountFrame:Hide() end
		return
	end
	local header = _G.QuestObjectiveTracker and _G.QuestObjectiveTracker.Header
	if not header then
		if questTrackerQuestCountFrame then questTrackerQuestCountFrame:Hide() end
		return
	end
	local container = EnsureQuestTrackerQuestCountFrame()
	if not container or not questTrackerQuestCountText then return end
	PositionQuestTrackerQuestCount()
	local textValue = GetQuestTrackerQuestCountText()
	if textValue == "" then
		questTrackerQuestCountFrame:Hide()
		return
	end
	questTrackerQuestCountText:SetText(textValue)
	questTrackerQuestCountFrame:SetSize(math.max(1, questTrackerQuestCountText:GetStringWidth()), math.max(1, questTrackerQuestCountText:GetStringHeight()))
	questTrackerQuestCountFrame:Show()
	questTrackerQuestCountText:Show()
end
addon.functions.UpdateQuestTrackerQuestCount = UpdateQuestTrackerQuestCount

local function EnsureQuestTrackerQuestCountWatcher()
	if questTrackerQuestCountWatcher then return end
	questTrackerQuestCountWatcher = CreateFrame("Frame")
	local events = { "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_REMOVED" }
	for _, evt in ipairs(events) do
		questTrackerQuestCountWatcher:RegisterEvent(evt)
	end
	questTrackerQuestCountWatcher:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_ENTERING_WORLD" then
			C_Timer.After(0.5, UpdateQuestTrackerQuestCount)
		else
			UpdateQuestTrackerQuestCount()
		end
	end)
end

local function initActionBars()
	addon.functions.InitDBValue("actionBarAnchorEnabled", false)
	addon.functions.InitDBValue("actionBarFullRangeColoring", false)
	addon.functions.InitDBValue("actionBarFullRangeColor", { r = 1, g = 0.1, b = 0.1 })
	addon.functions.InitDBValue("actionBarFullRangeAlpha", 0.35)
	addon.functions.InitDBValue("hideMacroNames", false)
	addon.functions.InitDBValue("actionBarMacroFontOverride", false)
	addon.functions.InitDBValue("actionBarHotkeyFontOverride", false)
	addon.functions.InitDBValue("actionBarMacroFontFace", addon.variables.defaultFont)
	addon.functions.InitDBValue("actionBarMacroFontSize", 12)
	addon.functions.InitDBValue("actionBarMacroFontOutline", "OUTLINE")
	addon.functions.InitDBValue("actionBarHotkeyFontFace", addon.variables.defaultFont)
	addon.functions.InitDBValue("actionBarHotkeyFontSize", 12)
	addon.functions.InitDBValue("actionBarHotkeyFontOutline", "OUTLINE")
	addon.functions.InitDBValue("actionBarShortHotkeys", false)
	addon.functions.InitDBValue("actionBarHiddenHotkeys", {})
	if type(addon.db.actionBarHiddenHotkeys) ~= "table" then addon.db.actionBarHiddenHotkeys = {} end
	local normalizeFontSize = ActionBarLabels and ActionBarLabels.NormalizeFontSize
	local function clampFontSize(value)
		if normalizeFontSize then return normalizeFontSize(value, 6, 32) end
		local num = tonumber(value) or 6
		if num < 6 then num = 6 end
		if num > 32 then num = 32 end
		return num
	end
	addon.db.actionBarMacroFontSize = clampFontSize(addon.db.actionBarMacroFontSize)
	addon.db.actionBarHotkeyFontSize = clampFontSize(addon.db.actionBarHotkeyFontSize)
	for _, cbData in ipairs(addon.variables.actionBarNames) do
		if cbData.var and cbData.name then
			local cfg = NormalizeActionBarVisibilityConfig(cbData.var, addon.db[cbData.var])
			UpdateActionBarMouseover(cbData.name, cfg, cbData.var)
		end
	end
	RefreshAllActionBarVisibilityAlpha()
	EnsureActionBarVisibilityWatcher()
	if ActionBarLabels and ActionBarLabels.RefreshAllMacroNameVisibility then ActionBarLabels.RefreshAllMacroNameVisibility() end
	addon.variables.actionBarAnchorDefaults = addon.variables.actionBarAnchorDefaults or {}
	for index = 1, #ACTION_BAR_FRAME_NAMES do
		local dbKey = "actionBarAnchor" .. index
		local defaultAnchor = addon.functions.GetActionBarAnchor(index)
		if not addon.variables.actionBarAnchorDefaults[index] then addon.variables.actionBarAnchorDefaults[index] = defaultAnchor end
		local defaultKey = "actionBarAnchorDefault" .. index
		addon.functions.InitDBValue(defaultKey, addon.variables.actionBarAnchorDefaults[index])
		addon.functions.InitDBValue(dbKey, addon.db[defaultKey])
		local stored = addon.db[dbKey]
		if not ACTION_BAR_ANCHOR_CONFIG[stored] then
			stored = addon.db[defaultKey] or defaultAnchor
			addon.db[dbKey] = stored
		end
	end
	RefreshAllActionBarAnchors()
	if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
end

local function initParty()
	addon.functions.InitDBValue("autoAcceptGroupInvite", false)
	addon.functions.InitDBValue("autoAcceptGroupInviteFriendOnly", false)
	addon.functions.InitDBValue("autoAcceptGroupInviteGuildOnly", false)
	addon.functions.InitDBValue("showLeaderIconRaidFrame", false)
	addon.functions.InitDBValue("showPartyFrameInSoloContent", false)

	if CompactUnitFrame_SetUnit then
		hooksecurefunc("CompactUnitFrame_SetUnit", function(s, type)
			if addon.db["showLeaderIconRaidFrame"] then
				if type then
					if (_G["CompactPartyFrame"]:IsShown() and strmatch(type, "party%d")) or (_G["CompactRaidFrameContainer"]:IsShown() and strmatch(type, "raid%d+")) then setLeaderIcon() end
				end
			end
		end)
	end

	local leaderUpdateFrame = CreateFrame("Frame")
	leaderUpdateFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
	leaderUpdateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	leaderUpdateFrame:SetScript("OnEvent", function()
		if addon.db["showLeaderIconRaidFrame"] then
			setLeaderIcon()
		else
			removeLeaderIcon()
		end
	end)

	local last_solo
	local pending_update = false
	local updateFrame = CreateFrame("Frame")

	-- TODO throws many errors in midnight in group content for now - maybe later in beta it works
	if not addon.variables.isMidnight then
		local function manage_raid_frame()
			if not addon.db["showPartyFrameInSoloContent"] then return end
			if InCombatLockdown() then
				if not pending_update then
					pending_update = true
					updateFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
				end
				return
			end

			local solo = 1
			if IsInGroup() or IsInRaid() then solo = 0 end

			if solo == 0 and last_solo == 0 then return end

			CompactPartyFrame:SetShown(solo)
			last_solo = solo
		end

		updateFrame:SetScript("OnEvent", function(self, event)
			if event == "PLAYER_REGEN_ENABLED" and pending_update then
				self:UnregisterEvent("PLAYER_REGEN_ENABLED")
				pending_update = false
				manage_raid_frame()
			end
		end)

		hooksecurefunc(CompactPartyFrame, "UpdateVisibility", manage_raid_frame)
	end
end

local function initQuest()
	addon.functions.InitDBValue("autoChooseQuest", false)
	addon.functions.InitDBValue("ignoreTrivialQuests", false)
	addon.functions.InitDBValue("ignoreDailyQuests", false)
	addon.functions.InitDBValue("questTrackerShowQuestCount", false)
	addon.functions.InitDBValue("questTrackerQuestCountOffsetX", 0)
	addon.functions.InitDBValue("questTrackerQuestCountOffsetY", 0)
	addon.functions.InitDBValue("questWowheadLink", false)
	addon.functions.InitDBValue("ignoredQuestNPC", {})
	addon.functions.InitDBValue("autogossipID", {})

	local function EQOL_GetQuestIDFromMenu(owner, ctx)
		if ctx and (ctx.questID or ctx.questId) then return ctx.questID or ctx.questId end

		addon.db.testOwner = owner

		if owner then
			if owner.questID then return owner.questID end
			if owner.GetQuestID then
				local ok, id = pcall(owner.GetQuestID, owner)
				if ok and id then return id end
			end
			if owner.questLogIndex and C_QuestLog and C_QuestLog.GetInfo then
				local info = C_QuestLog.GetInfo(owner.questLogIndex)
				if info and info.questID then return info.questID end
			end
		end
		return nil
	end

	local function EQOL_ShowCopyURL(url)
		if not StaticPopupDialogs["ENHANCEQOL_COPY_URL"] then
			StaticPopupDialogs["ENHANCEQOL_COPY_URL"] = {
				text = "Copy URL:",
				button1 = OKAY,
				hasEditBox = true,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
				OnShow = function(self, data)
					local eb = self.editBox or self.GetEditBox and self:GetEditBox()
					eb:SetAutoFocus(true)
					eb:SetText(data or "")
					eb:HighlightText()
					eb:SetCursorPosition(0)
				end,
				OnAccept = function(self) end,
				EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
			}
		end
		StaticPopup_Show("ENHANCEQOL_COPY_URL", nil, nil, url)
	end

	local function EQOL_AddQuestWowheadEntry(owner, root, ctx)
		if not addon.db["questWowheadLink"] then return end
		local qid
		if owner.GetName and owner:GetName() == "ObjectiveTrackerFrame" then
			local mFocus = GetMouseFoci()
			if mFocus and mFocus[1] and mFocus[1].GetParent then
				local pInfo = mFocus[1]:GetParent()
				if pInfo.poiQuestID then
					qid = pInfo.poiQuestID
				else
					return
				end
			end
		else
			qid = EQOL_GetQuestIDFromMenu(owner, ctx)
		end
		if not qid then return end
		root:CreateDivider()
		local btn = root:CreateButton("Copy Wowhead URL", function() EQOL_ShowCopyURL(("https://www.wowhead.com/quest=%d"):format(qid)) end)
		btn:AddInitializer(function()
			btn:SetTooltip(function(tt)
				GameTooltip_SetTitle(tt, "Wowhead")
				GameTooltip_AddNormalLine(tt, ("quest=%d"):format(qid))
			end)
		end)
	end

	-- Register for Blizzard's menu tags (provided by /etrace):
	if Menu and Menu.ModifyMenu then
		Menu.ModifyMenu("MENU_QUEST_MAP_LOG_TITLE", EQOL_AddQuestWowheadEntry)
		Menu.ModifyMenu("MENU_QUEST_OBJECTIVE_TRACKER", EQOL_AddQuestWowheadEntry)
	end

	EnsureQuestTrackerQuestCountWatcher()
	UpdateQuestTrackerQuestCount()
end

local function initMisc()
	addon.functions.InitDBValue("confirmTimerRemovalTrade", false)
	addon.functions.InitDBValue("confirmPatronOrderDialog", false)
	addon.functions.InitDBValue("deleteItemFillDialog", false)
	addon.functions.InitDBValue("confirmReplaceEnchant", false)
	addon.functions.InitDBValue("confirmSocketReplace", false)
	addon.functions.InitDBValue("timeoutRelease", false)
	addon.functions.InitDBValue("timeoutReleaseModifier", "SHIFT")
	addon.functions.InitDBValue("hideRaidTools", false)
	addon.functions.InitDBValue("autoRepair", false)
	addon.functions.InitDBValue("autoRepairGuildBank", false)
	addon.functions.InitDBValue("sellAllJunk", false)
	addon.functions.InitDBValue("autoCancelCinematic", false)
	addon.functions.InitDBValue("ignoreTalkingHead", false)
	addon.functions.InitDBValue("autoHideBossBanner", false)
	addon.functions.InitDBValue("autoQuickLoot", false)
	addon.functions.InitDBValue("autoQuickLootWithShift", false)
	addon.functions.InitDBValue("hideAzeriteToast", false)
	addon.functions.InitDBValue("hiddenLandingPages", {})
	addon.functions.InitDBValue("enableLandingPageMenu", false)
	addon.functions.InitDBValue("hideMinimapButton", false)
	addon.functions.InitDBValue("hideZoneText", false)
	addon.functions.InitDBValue("instantCatalystEnabled", false)

	-- Hook all static popups, because not the first one has to be the one for sell all junk if another popup is already shown
	for i = 1, 4 do
		local popup = _G["StaticPopup" .. i]
		if popup then
			hooksecurefunc(popup, "Show", function(self)
				if self then
					if self.which == "RECOVER_CORPSE" then
						local acceptbtn = self:GetButton(1)
						if acceptbtn then
							if acceptbtn:GetAlpha() ~= 1 then acceptbtn:SetAlpha(1) end
						end
						return
					end
					if self.GetButton then
						local btn = self:GetButton(1)
						if btn:GetAlpha() ~= 1 then btn:SetAlpha(1) end
					end
					local isDeathPopup = (self.which == "DEATH") and (self.numButtons or 0) > 0 and self.GetButton
					if isDeathPopup then
						local releaseButton = self:GetButton(1)
						local shouldGateRelease = addon.db["timeoutRelease"] and addon.functions.shouldUseTimeoutReleaseForCurrentContext()

						if shouldGateRelease then
							local modifierKey = addon.functions.getTimeoutReleaseModifierKey()
							local modifierDisplayName = addon.functions.getTimeoutReleaseModifierDisplayName(modifierKey)
							local isModifierDown = addon.functions.isTimeoutReleaseModifierDown(modifierKey)
							if releaseButton then releaseButton:SetAlpha(isModifierDown and 1 or 0) end
							addon.functions.showTimeoutReleaseHint(self, modifierDisplayName)
						else
							if releaseButton then releaseButton:SetAlpha(1) end
							addon.functions.hideTimeoutReleaseHint(self)
						end
					else
						addon.functions.hideTimeoutReleaseHint(self)
					end

					if addon.db["sellAllJunk"] and self.data and type(self.data) == "table" and self.data.text == SELL_ALL_JUNK_ITEMS_POPUP and self.button1 then
						self.button1:Click()
					elseif
						addon.db["deleteItemFillDialog"]
						and (self.which == "DELETE_GOOD_ITEM" or self.which == "DELETE_GOOD_QUEST_ITEM")
						and (self.editBox or self.GetEditBox and self:GetEditBox())
					then
						local editBox = self.editBox or self.GetEditBox and self:GetEditBox()
						editBox:SetText(DELETE_ITEM_CONFIRM_STRING)
					elseif addon.db["confirmPatronOrderDialog"] and self.data and type(self.data) == "table" and self.data.text == CRAFTING_ORDERS_OWN_REAGENTS_CONFIRMATION and self.GetButton then
						local order = C_CraftingOrders.GetClaimedOrder()
						if order and order.npcCustomerCreatureID and order.npcCustomerCreatureID > 0 then self:GetButton(1):Click() end
					elseif addon.db["confirmTimerRemovalTrade"] and self.which == "CONFIRM_MERCHANT_TRADE_TIMER_REMOVAL" and self.GetButton then
						self:GetButton(1):Click()
					elseif addon.db["confirmReplaceEnchant"] and self.which == "REPLACE_ENCHANT" and self.numButtons > 0 and self.GetButton then
						self:GetButton(1):Click()
					elseif addon.db["confirmSocketReplace"] and self.which == "CONFIRM_ACCEPT_SOCKETS" and self.numButtons > 0 and self.GetButton then
						self:GetButton(1):Click()
					end
				end
			end)
			if not popup._eqolTimeoutReleaseOnHideHooked then
				popup:HookScript("OnHide", function(self) addon.functions.hideTimeoutReleaseHint(self) end)
				popup._eqolTimeoutReleaseOnHideHooked = true
			end
		end
	end

	hooksecurefunc(MerchantFrame, "Show", function(self, button)
		if addon.db["autoRepair"] and CanMerchantRepair() then
			local repairAllCost = GetRepairAllCost()
			if repairAllCost and repairAllCost > 0 then
				if addon.db["autoRepairGuildBank"] and CanGuildBankRepair() then
					RepairAllItems(true)
				else
					RepairAllItems()
				end
				PlaySound(SOUNDKIT.ITEM_REPAIR)
				print(L["repairCost"] .. addon.functions.formatMoney(repairAllCost))
			end
		end
		if addon.db["sellAllJunk"] and C_MerchantFrame.IsSellAllJunkEnabled() then C_MerchantFrame.SellAllJunkItems() end
	end)

	hooksecurefunc(TalkingHeadFrame, "PlayCurrent", function(self)
		if addon.db["ignoreTalkingHead"] then self:Hide() end
	end)
	hooksecurefunc(BossBanner, "PlayBanner", function(self)
		if addon.db["autoHideBossBanner"] then self:Hide() end
	end)
	if addon.db["hideAzeriteToast"] and AzeriteLevelUpToast then
		AzeriteLevelUpToast:UnregisterAllEvents()
		AzeriteLevelUpToast:Hide()
	end
	_G.CompactRaidFrameManager:SetScript("OnShow", function(self) addon.functions.toggleRaidTools(addon.db["hideRaidTools"], self) end)
	ExpansionLandingPageMinimapButton:HookScript("OnShow", function(self)
		local id = addon.variables.landingPageReverse[self.title]
		if addon.db["enableSquareMinimap"] then
			self:ClearAllPoints()
			if id == 20 then
				self:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -25, -25)
			else
				self:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -16, -16)
			end
		end
		if addon.db["hiddenLandingPages"][id] then self:Hide() end
	end)

	-- Right-click context menu for expansion/garrison minimap buttons
	local MU = MenuUtil
	local tinsert = table.insert

	local function ShowLandingMenu(owner)
		if MU and MU.CreateContextMenu then
			MU.CreateContextMenu(owner, function(_, root)
				if ShowGarrisonLandingPage and Enum and Enum.GarrisonType then
					root:CreateButton(GARRISON_TYPE_9_0_LANDING_PAGE_TITLE, function() ShowGarrisonLandingPage(Enum.GarrisonType.Type_9_0) end)
					root:CreateButton(ORDER_HALL_LANDING_PAGE_TITLE, function() ShowGarrisonLandingPage(3) end)
					root:CreateButton(GARRISON_LANDING_PAGE_TITLE, function() ShowGarrisonLandingPage(2) end)
					root:CreateButton(ADVENTURE_MAP_TITLE, function() ShowGarrisonLandingPage(9) end)
				end
			end)
		end
	end

	local function AttachRightClickMenu(button)
		if not button or button._eqolMenuHooked then return end
		button:HookScript("OnMouseUp", function(self, btn)
			if btn == "RightButton" and addon.db["enableLandingPageMenu"] then ShowLandingMenu(self) end
		end)
		button._eqolMenuHooked = true
	end

	C_Timer.After(0, function()
		if ExpansionLandingPageMinimapButton then AttachRightClickMenu(ExpansionLandingPageMinimapButton) end
		if GarrisonLandingPageMinimapButton then AttachRightClickMenu(GarrisonLandingPageMinimapButton) end
	end)
end

local function initLoot()
	addon.functions.InitDBValue("enableLootToastAnchor", false)
	addon.functions.InitDBValue("enableLootToastFilter", false)
	addon.functions.InitDBValue("lootToastItemLevels", {
		[Enum.ItemQuality.Rare] = 600,
		[Enum.ItemQuality.Epic] = 600,
		[Enum.ItemQuality.Legendary] = 600,
	})
	if addon.db.lootToastItemLevel then
		local v = addon.db.lootToastItemLevel
		addon.db.lootToastItemLevels[Enum.ItemQuality.Rare] = v
		addon.db.lootToastItemLevels[Enum.ItemQuality.Epic] = v
		addon.db.lootToastItemLevels[Enum.ItemQuality.Legendary] = v
		addon.db.lootToastItemLevel = nil
	end
	addon.functions.InitDBValue("lootToastFilters", {
		[Enum.ItemQuality.Rare] = { ilvl = true, mounts = true, pets = true, upgrade = false },
		[Enum.ItemQuality.Epic] = { ilvl = true, mounts = true, pets = true, upgrade = false },
		[Enum.ItemQuality.Legendary] = { ilvl = true, mounts = true, pets = true, upgrade = false },
	})
	for _, quality in ipairs({ Enum.ItemQuality.Rare, Enum.ItemQuality.Epic, Enum.ItemQuality.Legendary }) do
		local filter = addon.db.lootToastFilters[quality]
		if filter.upgrade == nil then filter.upgrade = false end
	end
	addon.functions.InitDBValue("lootToastIncludeIDs", {})
	addon.functions.InitDBValue("lootToastUseCustomSound", false)
	addon.functions.InitDBValue("lootToastCustomSoundFile", "")
	addon.functions.InitDBValue("lootToastAnchor", { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 240 })
	-- migrate legacy LootRollMover-inspired settings to the new group-loot anchor keys
	if addon.db.enableLootRollAnchor ~= nil then
		if addon.db.enableGroupLootAnchor == nil then addon.db.enableGroupLootAnchor = addon.db.enableLootRollAnchor == true end
		addon.db.enableLootRollAnchor = nil
	end
	if addon.db.lootRollAnchor then
		addon.db.groupLootAnchor = addon.db.lootRollAnchor
		addon.db.lootRollAnchor = nil
	end
	if addon.db.lootRollLayout then
		addon.db.groupLootLayout = addon.db.lootRollLayout
		addon.db.lootRollLayout = nil
	end

	addon.functions.InitDBValue("enableGroupLootAnchor", false)
	addon.functions.InitDBValue("groupLootAnchor", { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 300 })
	addon.functions.InitDBValue("groupLootLayout", { scale = 1, offsetX = 0, offsetY = 0, spacing = 4 })

	local layout = addon.db.groupLootLayout
	if type(layout) ~= "table" then
		layout = { scale = 1, offsetX = 0, offsetY = 0, spacing = 4 }
		addon.db.groupLootLayout = layout
	end
	if type(layout.scale) ~= "number" then layout.scale = 1 end
	if layout.scale < 0.5 then layout.scale = 0.5 end
	if layout.scale > 3 then layout.scale = 3 end
	if layout.offsetX == nil then layout.offsetX = 0 end
	if layout.offsetY == nil then layout.offsetY = 0 end
	if layout.spacing == nil then layout.spacing = 4 end
	if addon.ChatIM and addon.ChatIM.BuildSoundTable and not addon.ChatIM.availableSounds then addon.ChatIM:BuildSoundTable() end
end

local function initUnitFrame()
	MigrateLegacyVisibilityFlags()
	addon.functions.InitDBValue("hideHitIndicatorPlayer", false)
	addon.functions.InitDBValue("hideHitIndicatorPet", false)
	-- Player resting visuals (ZZZ + glow)
	addon.functions.InitDBValue("hideRestingGlow", false)
	addon.functions.InitDBValue("hidePartyFrameTitle", false)
	addon.functions.InitDBValue("unitFrameTruncateNames", false)
	addon.functions.InitDBValue("unitFrameMaxNameLength", addon.variables.unitFrameMaxNameLength)
	addon.functions.InitDBValue("unitFrameScaleEnabled", false)
	addon.functions.InitDBValue("unitFrameScale", addon.variables.unitFrameScale)
	addon.functions.InitDBValue("hiddenCastBars", addon.db["hiddenCastBars"] or {})
	-- Health text settings (player/target/boss)
	addon.functions.InitDBValue("healthTextPlayerMode", addon.db["healthTextPlayerMode"] or "OFF")
	addon.functions.InitDBValue("healthTextTargetMode", addon.db["healthTextTargetMode"] or "OFF")
	addon.functions.InitDBValue("healthTextBossMode", addon.db["healthTextBossMode"] or addon.db["bossHealthMode"] or "OFF")
	-- No separate CVar-override flags; OFF means follow Blizzard statusText
	if addon.db["hideHitIndicatorPlayer"] then PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator:Hide() end

	if PetHitIndicator then hooksecurefunc(PetHitIndicator, "Show", function(self)
		if addon.db["hideHitIndicatorPet"] then PetHitIndicator:Hide() end
	end) end

	-- Hide resting ZZZ texture and resting glow loop (opt-in, perf-safe)
	local function ApplyRestingVisuals()
		if not PlayerFrame or not PlayerFrame.PlayerFrameContent then return end
		local content = PlayerFrame.PlayerFrameContent
		local main = content.PlayerFrameContentMain
		local contextual = content.PlayerFrameContentContextual
		local statusTexture = main and main.StatusTexture
		local playerRestLoop = contextual and contextual.PlayerRestLoop
		if addon.db["hideRestingGlow"] and IsResting() then
			if statusTexture and statusTexture.Hide then statusTexture:Hide() end
			if playerRestLoop and playerRestLoop.Hide then
				playerRestLoop:Hide()
				if playerRestLoop.PlayerRestLoopAnim and playerRestLoop.PlayerRestLoopAnim.Stop then playerRestLoop.PlayerRestLoopAnim:Stop() end
			end
		else
			-- Let Blizzard refresh according to current resting state
			if PlayerFrame_UpdateStatus then PlayerFrame_UpdateStatus(PlayerFrame) end
		end
	end

	if PlayerFrame_UpdateStatus then
		hooksecurefunc("PlayerFrame_UpdateStatus", function(self)
			if not addon.db or not addon.db["hideRestingGlow"] then return end
			if IsResting() then
				local content = PlayerFrame.PlayerFrameContent
				local main = content and content.PlayerFrameContentMain
				local statusTexture = main and main.StatusTexture
				if statusTexture and statusTexture.Hide then statusTexture:Hide() end
				if PlayerFrame_UpdatePlayerRestLoop then PlayerFrame_UpdatePlayerRestLoop(true) end
			end
		end)
	end

	if PlayerFrame_UpdatePlayerRestLoop then
		hooksecurefunc("PlayerFrame_UpdatePlayerRestLoop", function(state)
			if not addon.db or not addon.db["hideRestingGlow"] then return end
			if state then
				local content = PlayerFrame.PlayerFrameContent
				local contextual = content and content.PlayerFrameContentContextual
				local playerRestLoop = contextual and contextual.PlayerRestLoop
				if playerRestLoop and playerRestLoop.Hide then
					playerRestLoop:Hide()
					if playerRestLoop.PlayerRestLoopAnim and playerRestLoop.PlayerRestLoopAnim.Stop then playerRestLoop.PlayerRestLoopAnim:Stop() end
				end
			end
		end)
	end

	addon.functions.ApplyRestingVisuals = ApplyRestingVisuals

	function addon.functions.togglePartyFrameTitle(value)
		if InCombatLockdown and InCombatLockdown() then
			addon.variables = addon.variables or {}
			addon.variables.pendingPartyFrameTitle = value
			return
		end
		if not CompactPartyFrameTitle then return end
		if value then
			CompactPartyFrameTitle:Hide()
		else
			CompactPartyFrameTitle:Show()
		end
	end
	if CompactPartyFrameTitle then CompactPartyFrameTitle:HookScript("OnShow", function(self)
		if addon.db["hidePartyFrameTitle"] then self:Hide() end
	end) end
	addon.functions.togglePartyFrameTitle(addon.db["hidePartyFrameTitle"])

	local function TruncateFrameName(cuf)
		if not addon.db["unitFrameTruncateNames"] then return end
		if not addon.db["unitFrameMaxNameLength"] then return end
		if not cuf then return end
		if issecretvalue and issecretvalue(cuf.unit) then return end

		if cuf.unit and cuf.unit:match("^nameplate") then return end

		local name
		if cuf.unit and UnitExists(cuf.unit) then
			name = UnitName(cuf.unit)
		elseif cuf.displayedUnit and UnitExists(cuf.displayedUnit) then
			name = UnitName(cuf.displayedUnit)
		elseif cuf.name and type(cuf.name.GetText) == "function" then
			name = cuf.name:GetText()
		end

		if issecretvalue and issecretvalue(name) then return end

		if name and cuf.name and type(cuf.name.SetText) == "function" then
			-- Remove server names before truncation
			local shortName = strsplit("-", name)
			if #shortName > addon.db["unitFrameMaxNameLength"] then shortName = strsub(shortName, 1, addon.db["unitFrameMaxNameLength"]) end
			if shortName ~= name then cuf.name:SetText(shortName) end
		end
	end

	local function ApplyFrameSettings(cuf) TruncateFrameName(cuf) end

	if CompactUnitFrame_UpdateName then hooksecurefunc("CompactUnitFrame_UpdateName", TruncateFrameName) end

	if DefaultCompactUnitFrameSetup then hooksecurefunc("DefaultCompactUnitFrameSetup", ApplyFrameSettings) end

	function addon.functions.updateUnitFrameNames()
		if not addon.db["unitFrameTruncateNames"] then return end
		for i = 1, 5 do
			local f = _G["CompactPartyFrameMember" .. i]
			TruncateFrameName(f)
		end
		for i = 1, 40 do
			local f = _G["CompactRaidFrame" .. i]
			TruncateFrameName(f)
		end
	end

	function addon.functions.updatePartyFrameScale()
		if not addon.db["unitFrameScaleEnabled"] then return end
		if not addon.db["unitFrameScale"] then return end
		if InCombatLockdown and InCombatLockdown() then
			addon.variables = addon.variables or {}
			addon.variables.pendingPartyFrameScale = true
			return
		end
		if addon.variables then addon.variables.pendingPartyFrameScale = nil end
		if CompactPartyFrame then CompactPartyFrame:SetScale(addon.db["unitFrameScale"]) end
	end

	-- Cast bar visibility handling
	local castBarFrames = {
		PlayerCastingBarFrame = function() return _G.PlayerCastingBarFrame end,
		TargetFrameSpellBar = function() return _G.TargetFrameSpellBar end,
		FocusFrameSpellBar = function() return _G.FocusFrameSpellBar end,
	}

	local function EnsureCastbarHook(frame)
		if not frame or frame.EQOL_CastbarHooked then return end
		frame:HookScript("OnShow", function(self)
			if addon.db and addon.db.hiddenCastBars and addon.db.hiddenCastBars[self:GetName()] then self:Hide() end
		end)
		frame.EQOL_CastbarHooked = true
	end

	function addon.functions.ApplyCastBarVisibility()
		if not addon.db or type(addon.db.hiddenCastBars) ~= "table" then return end
		for key, getter in pairs(castBarFrames) do
			local frame = getter and getter() or _G[key]
			if frame then
				EnsureCastbarHook(frame)
				if addon.db.hiddenCastBars[key] then frame:Hide() end
			end
		end
	end

	if addon.db["unitFrameTruncateNames"] then addon.functions.updateUnitFrameNames() end
	if addon.db["unitFrameScaleEnabled"] then addon.functions.updatePartyFrameScale() end
	-- Apply resting visuals if option is enabled
	if addon.db["hideRestingGlow"] and addon.functions.ApplyRestingVisuals then addon.functions.ApplyRestingVisuals() end
	-- Initialize HealthText module
	if addon.HealthText then
		if addon.HealthText.SetMode then
			addon.HealthText:SetMode("player", addon.db["healthTextPlayerMode"])
			addon.HealthText:SetMode("target", addon.db["healthTextTargetMode"])
			addon.HealthText:SetMode("boss", addon.db["healthTextBossMode"])
		end
	end
	addon.functions.ApplyCastBarVisibility()

	for _, cbData in ipairs(addon.variables.unitFrameNames) do
		if cbData.var and cbData.name then UpdateUnitFrameMouseover(cbData.name, cbData) end
	end
end

local function initBagsFrame()
	-- TODO actual bug in beta - we can't change anything with tooltip
	if not addon.variables.isMidnight then
		addon.functions.InitDBValue("moneyTracker", {})
		addon.functions.InitDBValue("enableMoneyTracker", false)
		addon.functions.InitDBValue("showOnlyGoldOnMoney", false)
		addon.functions.InitDBValue("warbandGold", 0)
		if addon.db["moneyTracker"][UnitGUID("player")] == nil or type(addon.db["moneyTracker"][UnitGUID("player")]) ~= "table" then addon.db["moneyTracker"][UnitGUID("player")] = {} end

		local moneyFrame = ContainerFrameCombinedBags.MoneyFrame
		local otherMoney = {}

		local function ShowBagMoneyTooltip(self)
			if not addon.db["enableMoneyTracker"] then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:ClearLines()

			local list, total = {}, 0
			for _, info in pairs(addon.db["moneyTracker"]) do
				total = total + (info.money or 0)
				table.insert(list, info)
			end
			table.sort(list, function(a, b) return (a.money or 0) > (b.money or 0) end)

			GameTooltip:AddDoubleLine(L["warbandGold"], addon.functions.formatMoney(addon.db["warbandGold"] or 0, "tracker"))
			GameTooltip:AddLine(" ")

			for _, info in ipairs(list) do
				local col = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[info.class] or { r = 1, g = 1, b = 1 }
				local displayName
				if info.realm == GetRealmName() or not info.realm or info.realm == "" then
					displayName = string.format("|cff%02x%02x%02x%s|r", col.r * 255, col.g * 255, col.b * 255, info.name)
				else
					displayName = string.format("|cff%02x%02x%02x%s-%s|r", col.r * 255, col.g * 255, col.b * 255, info.name, info.realm)
				end
				GameTooltip:AddDoubleLine(displayName, addon.functions.formatMoney(info.money, "tracker"))
			end

			GameTooltip:AddLine(" ")
			GameTooltip:AddDoubleLine(TOTAL, addon.functions.formatMoney(total, "tracker"))
			GameTooltip:Show()
		end

		local function HideBagMoneyTooltip()
			if not addon.db["enableMoneyTracker"] then return end
			GameTooltip:Hide()
		end

		moneyFrame:HookScript("OnEnter", ShowBagMoneyTooltip)
		moneyFrame:HookScript("OnLeave", HideBagMoneyTooltip)
		for _, coin in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
			local btn = moneyFrame[coin]
			if btn then
				btn:HookScript("OnEnter", ShowBagMoneyTooltip)
				btn:HookScript("OnLeave", HideBagMoneyTooltip)
			end
		end

		moneyFrame = ContainerFrame1.MoneyFrame
		moneyFrame:HookScript("OnEnter", ShowBagMoneyTooltip)
		moneyFrame:HookScript("OnLeave", HideBagMoneyTooltip)
		for _, coin in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
			local btn = moneyFrame[coin]
			if btn then
				btn:HookScript("OnEnter", ShowBagMoneyTooltip)
				btn:HookScript("OnLeave", HideBagMoneyTooltip)
			end
		end
	end
end

local function initChatFrame()
	-- Build learn/unlearn message patterns and filter once
	if not addon.variables.learnUnlearnPatterns then
		local patterns = {}
		if ERR_LEARN_PASSIVE_S then table.insert(patterns, addon.functions.fmtToPattern(ERR_LEARN_PASSIVE_S)) end
		if ERR_LEARN_SPELL_S then table.insert(patterns, addon.functions.fmtToPattern(ERR_LEARN_SPELL_S)) end
		if ERR_LEARN_ABILITY_S then table.insert(patterns, addon.functions.fmtToPattern(ERR_LEARN_ABILITY_S)) end
		if ERR_SPELL_UNLEARNED_S then table.insert(patterns, addon.functions.fmtToPattern(ERR_SPELL_UNLEARNED_S)) end
		addon.variables.learnUnlearnPatterns = patterns
	end

	addon.functions.ChatLearnFilter = addon.functions.ChatLearnFilter
		or function(_, _, msg)
			if not msg then return false end
			for _, pat in ipairs(addon.variables.learnUnlearnPatterns or {}) do
				if msg:match(pat) then return true end
			end
			return false
		end

	addon.functions.ApplyChatLearnFilter = addon.functions.ApplyChatLearnFilter
		or function(enabled)
			if enabled then
				ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", addon.functions.ChatLearnFilter)
			else
				ChatFrame_RemoveMessageEventFilter("CHAT_MSG_SYSTEM", addon.functions.ChatLearnFilter)
			end
		end

	if ChatFrame1 then
		addon.functions.InitDBValue("chatFrameFadeEnabled", ChatFrame1:GetFading())
		addon.functions.InitDBValue("chatFrameFadeTimeVisible", ChatFrame1:GetTimeVisible())
		addon.functions.InitDBValue("chatFrameFadeDuration", ChatFrame1:GetFadeDuration())

		ChatFrame1:SetFading(addon.db["chatFrameFadeEnabled"])
		ChatFrame1:SetTimeVisible(addon.db["chatFrameFadeTimeVisible"])
		ChatFrame1:SetFadeDuration(addon.db["chatFrameFadeDuration"])
	else
		addon.functions.InitDBValue("chatFrameFadeEnabled", true)
		addon.functions.InitDBValue("chatFrameFadeTimeVisible", 120)
		addon.functions.InitDBValue("chatFrameFadeDuration", 3)
	end

	addon.functions.InitDBValue("enableChatIM", false)
	addon.functions.InitDBValue("enableChatIMFade", false)
	addon.functions.InitDBValue("chatIMUseCustomSound", false)
	addon.functions.InitDBValue("chatIMCustomSoundFile", "")
	addon.functions.InitDBValue("chatIMMaxHistory", 250)
	addon.functions.InitDBValue("chatIMFrameData", {})
	addon.functions.InitDBValue("chatIMHideInCombat", false)
	addon.functions.InitDBValue("chatIMUseAnimation", true)
	addon.functions.InitDBValue("chatShowLootCurrencyIcons", false)
	addon.functions.InitDBValue("chatHideLearnUnlearn", false)
	addon.functions.InitDBValue("chatBubbleFontOverride", false)
	addon.functions.InitDBValue("chatBubbleFontSize", DEFAULT_CHAT_BUBBLE_FONT_SIZE)
	addon.functions.ApplyChatBubbleFontSize(addon.db["chatBubbleFontSize"])
	-- Apply learn/unlearn message filter based on saved setting
	addon.functions.ApplyChatLearnFilter(addon.db["chatHideLearnUnlearn"])
	if addon.ChatIcons and addon.ChatIcons.SetEnabled then addon.ChatIcons:SetEnabled(addon.db["chatShowLootCurrencyIcons"]) end

	if addon.ChatIM and addon.ChatIM.SetEnabled then addon.ChatIM:SetEnabled(addon.db["enableChatIM"]) end
end

local function initMap()
	addon.functions.InitDBValue("enableWayCommand", false)
	if addon.db["enableWayCommand"] then addon.functions.registerWayCommand() end
end

local function initSocial()
	addon.functions.InitDBValue("enableIgnore", false)
	addon.functions.InitDBValue("ignoreAttachFriendsFrame", true)
	addon.functions.InitDBValue("ignoreAnchorFriendsFrame", false)
	addon.functions.InitDBValue("ignoreTooltipNote", false)
	addon.functions.InitDBValue("ignoreTooltipMaxChars", 100)
	addon.functions.InitDBValue("ignoreTooltipWordsPerLine", 5)
	addon.functions.InitDBValue("ignoreFramePoint", "CENTER")
	addon.functions.InitDBValue("ignoreFrameX", 0)
	addon.functions.InitDBValue("ignoreFrameY", 0)
	addon.functions.InitDBValue("blockDuelRequests", false)
	addon.functions.InitDBValue("blockPetBattleRequests", false)
	addon.functions.InitDBValue("blockPartyInvites", false)
	addon.functions.InitDBValue("friendsListDecorEnabled", false)
	addon.functions.InitDBValue("friendsListDecorShowLocation", true)
	addon.functions.InitDBValue("friendsListDecorHideOwnRealm", true)
	addon.functions.InitDBValue("friendsListDecorNameFontSize", 0)
	if addon.Ignore and addon.Ignore.SetEnabled then addon.Ignore:SetEnabled(addon.db["enableIgnore"]) end
	if addon.Ignore and addon.Ignore.UpdateAnchor then addon.Ignore:UpdateAnchor() end
	if addon.FriendsListDecor and addon.FriendsListDecor.SetEnabled then addon.FriendsListDecor:SetEnabled(addon.db["friendsListDecorEnabled"] == true) end
end

local initLootToast

initLootToast = function()
	if (addon.db.enableLootToastFilter or addon.db.enableLootToastAnchor or addon.db.enableGroupLootAnchor) and addon.LootToast and addon.LootToast.Enable then
		addon.LootToast:Enable()
	elseif addon.LootToast and addon.LootToast.Disable then
		addon.LootToast:Disable()
	end
end
addon.functions.initLootToast = initLootToast

local function initUI()
	MigrateLegacyVisibilityFlags()
	addon.functions.InitDBValue("enableMinimapButtonBin", false)
	addon.functions.InitDBValue("buttonsink", {})
	addon.functions.InitDBValue("minimapButtonBinColumns", DEFAULT_BUTTON_SINK_COLUMNS)
	addon.functions.InitDBValue("minimapButtonBinHideBackground", false)
	addon.functions.InitDBValue("minimapButtonBinHideBorder", false)
	addon.functions.InitDBValue("enableLootspecQuickswitch", false)
	addon.functions.InitDBValue("lootspec_quickswitch", {})
	addon.functions.InitDBValue("minimapSinkHoleData", {})
	addon.functions.InitDBValue("hideQuickJoinToast", false)
	addon.functions.InitDBValue("autoCancelDruidFlightForm", false)
	addon.functions.InitDBValue("enableSquareMinimap", false)
	addon.functions.InitDBValue("enableSquareMinimapBorder", false)
	addon.functions.InitDBValue("squareMinimapBorderSize", 1)
	addon.functions.InitDBValue("squareMinimapBorderColor", { r = 0, g = 0, b = 0 })
	addon.functions.InitDBValue("hiddenMinimapElements", addon.db["hiddenMinimapElements"] or {})
	addon.functions.InitDBValue("persistAuctionHouseFilter", false)
	addon.functions.InitDBValue("alwaysUserCurExpAuctionHouse", false)
	addon.functions.InitDBValue("hideDynamicFlightBar", false)
	addon.functions.InitDBValue("enableExtendedMerchant", false)
	addon.functions.InitDBValue("showInstanceDifficulty", false)
	-- anchor no longer used; position controlled by offsets from CENTER
	addon.functions.InitDBValue("instanceDifficultyOffsetX", 0)
	addon.functions.InitDBValue("instanceDifficultyOffsetY", 0)
	addon.functions.InitDBValue("instanceDifficultyFontSize", 14)
	addon.functions.InitDBValue("instanceDifficultyUseColors", false)
	if type(addon.db["instanceDifficultyColors"]) ~= "table" then addon.db["instanceDifficultyColors"] = {} end
	-- Ensure default color entries exist
	local defaultColors = {
		NM = { r = 0.20, g = 0.95, b = 0.20 }, -- Normal: Green
		HC = { r = 0.25, g = 0.55, b = 1.00 }, -- Heroic: Blue
		M = { r = 0.80, g = 0.40, b = 1.00 }, -- Mythic: Violet
		MPLUS = { r = 0.80, g = 0.40, b = 1.00 }, -- Mythic+: Violet
		LFR = { r = 1.00, g = 1.00, b = 1.00 }, -- LFR: White (editable)
		TW = { r = 1.00, g = 1.00, b = 1.00 }, -- Timewalking: White (editable)
	}
	for k, v in pairs(defaultColors) do
		if type(addon.db["instanceDifficultyColors"][k]) ~= "table" then addon.db["instanceDifficultyColors"][k] = v end
	end
	-- addon.functions.InitDBValue("instanceDifficultyUseIcon", false)

	addon.functions.InitDBValue("dungeonJournalLootSpecIcons", false)
	addon.functions.InitDBValue("dungeonJournalLootSpecAnchor", 1)
	addon.functions.InitDBValue("dungeonJournalLootSpecOffsetX", 0)
	addon.functions.InitDBValue("dungeonJournalLootSpecOffsetY", 0)
	addon.functions.InitDBValue("dungeonJournalLootSpecSpacing", 0)
	addon.functions.InitDBValue("dungeonJournalLootSpecScale", 1)
	addon.functions.InitDBValue("dungeonJournalLootSpecIconPadding", 0)
	addon.functions.InitDBValue("dungeonJournalLootSpecShowAll", false)

	-- Game Menu (ESC) scaling
	addon.functions.InitDBValue("gameMenuScaleEnabled", false)
	addon.functions.InitDBValue("gameMenuScale", 1.0)
	addon.functions.InitDBValue("optionsFrameScale", 1.0)
	addon.functions.applyOptionsFrameScale(addon.db["optionsFrameScale"])

	-- Mailbox address book
	addon.functions.InitDBValue("enableMailboxAddressBook", false)
	addon.functions.InitDBValue("mailboxContacts", {})

	-- Remember the last scale we applied so we can avoid overwriting other addons
	addon.variables = addon.variables or {}
	function addon.functions.applyGameMenuScale()
		if not GameMenuFrame then return end
		if not addon.db or not addon.db["gameMenuScaleEnabled"] then return end
		local desired = addon.db["gameMenuScale"] or 1.0
		local current = GameMenuFrame:GetScale() or 1.0
		if math.abs(current - desired) > 0.0001 then GameMenuFrame:SetScale(desired) end
		addon.variables.gameMenuScaleLastApplied = desired
	end

	-- Apply once on load if enabled; do not keep overriding thereafter
	addon.functions.applyGameMenuScale()

	local function makeSquareMinimap()
		MinimapCompassTexture:Hide()
		Minimap:SetMaskTexture("Interface\\BUTTONS\\WHITE8X8")
		function GetMinimapShape() return "SQUARE" end
	end
	if addon.db["enableSquareMinimap"] then makeSquareMinimap() end

	-- Border for square minimap
	function addon.functions.applySquareMinimapBorder()
		if not Minimap then return end
		local enableBorder = addon.db and addon.db["enableSquareMinimapBorder"]
		local isSquare = addon.db and addon.db["enableSquareMinimap"]

		-- Ensure holder frame exists (above minimap texture, below buttons)
		if not addon.general.squareMinimapBorderFrame then
			local f = CreateFrame("Frame", "EQOLBORDER", Minimap)
			f:SetFrameStrata("LOW") -- below MEDIUM buttons, above BACKGROUND
			f:SetFrameLevel((Minimap:GetFrameLevel() or 2))
			f:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
			f:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 0, 0)

			-- Create 4 edge textures
			f.tTop = f:CreateTexture(nil, "ARTWORK")
			f.tBottom = f:CreateTexture(nil, "ARTWORK")
			f.tLeft = f:CreateTexture(nil, "ARTWORK")
			f.tRight = f:CreateTexture(nil, "ARTWORK")
			addon.general.squareMinimapBorderFrame = f
		end

		local f = addon.general.squareMinimapBorderFrame
		local size = (addon.db and addon.db.squareMinimapBorderSize) or 1
		local col = (addon.db and addon.db.squareMinimapBorderColor) or { r = 0, g = 0, b = 0 }

		local r, g, b = col.r or 0, col.g or 0, col.b or 0

		-- Top
		f.tTop:ClearAllPoints()
		f.tTop:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		f.tTop:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
		f.tTop:SetHeight(size)
		f.tTop:SetColorTexture(r, g, b, 1)
		-- Bottom
		f.tBottom:ClearAllPoints()
		f.tBottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
		f.tBottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
		f.tBottom:SetHeight(size)
		f.tBottom:SetColorTexture(r, g, b, 1)
		-- Left
		f.tLeft:ClearAllPoints()
		f.tLeft:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		f.tLeft:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
		f.tLeft:SetWidth(size)
		f.tLeft:SetColorTexture(r, g, b, 1)
		-- Right
		f.tRight:ClearAllPoints()
		f.tRight:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
		f.tRight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
		f.tRight:SetWidth(size)
		f.tRight:SetColorTexture(r, g, b, 1)

		if enableBorder and isSquare then
			f:Show()
		else
			f:Hide()
		end
	end

	-- Apply border at startup
	C_Timer.After(0, function()
		if addon.functions.applySquareMinimapBorder then addon.functions.applySquareMinimapBorder() end
	end)

	function addon.functions.toggleMinimapButton(value)
		if value == false then
			LDBIcon:Show(addonName)
		else
			LDBIcon:Hide(addonName)
		end
	end
	function addon.functions.toggleZoneText(value)
		if value then
			ZoneTextFrame:UnregisterAllEvents()
			ZoneTextFrame:Hide()
		else
			addon.variables.requireReload = true
		end
	end
	addon.functions.toggleZoneText(addon.db["hideZoneText"])

	function addon.functions.toggleQuickJoinToastButton(value)
		if value == false then
			QuickJoinToastButton:Show()
		else
			QuickJoinToastButton:Hide()
		end
	end
	addon.functions.toggleQuickJoinToastButton(addon.db["hideQuickJoinToast"])

	--@debug@
	local druidFlightWatcher
	local druidFlightPending

	local function isPlayerDruid()
		local classTag = (addon.variables and addon.variables.unitClass) or select(2, UnitClass("player"))
		return classTag == "DRUID"
	end

	local function evaluateDruidFlightForm()
		if not addon.db or not addon.db["autoCancelDruidFlightForm"] then
			druidFlightPending = nil
			return
		end
		if not isPlayerDruid() then
			druidFlightPending = nil
			return
		end
		if not GetShapeshiftFormID or not IsFlyableArea or not CancelShapeshiftForm then return end
		local formID = GetShapeshiftFormID()
		if formID == 3 and IsFlyableArea() then
			if InCombatLockdown and InCombatLockdown() then
				druidFlightPending = true
				return
			end
			druidFlightPending = nil
			CancelShapeshiftForm()
		else
			druidFlightPending = nil
		end
	end

	local function handleDruidFlightEvent(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			if druidFlightPending then evaluateDruidFlightForm() end
		else
			evaluateDruidFlightForm()
		end
	end

	function addon.functions.updateDruidFlightFormWatcher()
		if not druidFlightWatcher then
			druidFlightWatcher = CreateFrame("Frame")
			druidFlightWatcher:SetScript("OnEvent", handleDruidFlightEvent)
		end
		druidFlightWatcher:UnregisterEvent("MOUNT_JOURNAL_USABILITY_CHANGED")
		druidFlightWatcher:UnregisterEvent("PLAYER_REGEN_ENABLED")
		druidFlightPending = nil
		if addon.db and addon.db["autoCancelDruidFlightForm"] and isPlayerDruid() then
			druidFlightWatcher:RegisterEvent("MOUNT_JOURNAL_USABILITY_CHANGED")
			druidFlightWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
			evaluateDruidFlightForm()
		end
	end

	if addon.functions.updateDruidFlightFormWatcher then addon.functions.updateDruidFlightFormWatcher() end
	--@end-debug@

	-- Hide/show specific minimap elements based on multi-select
	local function getMinimapElementFrames()
		local t = {}
		-- Tracking icon
		t.Tracking = {}
		if MinimapCluster and MinimapCluster.Tracking then table.insert(t.Tracking, MinimapCluster.Tracking) end
		if _G["MiniMapTracking"] then table.insert(t.Tracking, _G["MiniMapTracking"]) end
		-- Zone info (package)
		t.ZoneInfo = {}
		if MinimapCluster then
			if MinimapCluster.BorderTop then table.insert(t.ZoneInfo, MinimapCluster.BorderTop) end
			if MinimapCluster.ZoneTextButton then table.insert(t.ZoneInfo, MinimapCluster.ZoneTextButton) end
		end
		-- Clock
		t.Clock = {}
		if _G["TimeManagerClockButton"] then table.insert(t.Clock, _G["TimeManagerClockButton"]) end
		-- Calendar
		t.Calendar = {}
		if _G["GameTimeFrame"] then table.insert(t.Calendar, _G["GameTimeFrame"]) end
		-- Mail
		t.Mail = {}
		if MinimapCluster and MinimapCluster.IndicatorFrame and MinimapCluster.IndicatorFrame.MailFrame then table.insert(t.Mail, MinimapCluster.IndicatorFrame.MailFrame) end
		if _G["MiniMapMailFrame"] then table.insert(t.Mail, _G["MiniMapMailFrame"]) end
		if _G["MinimapMailFrame"] then table.insert(t.Mail, _G["MinimapMailFrame"]) end
		-- Addon compartment
		t.AddonCompartment = {}
		if _G["AddonCompartmentFrame"] then table.insert(t.AddonCompartment, _G["AddonCompartmentFrame"]) end
		return t
	end

	function addon.functions.ApplyMinimapElementVisibility()
		local cfg = addon.db and addon.db.hiddenMinimapElements or {}
		local elems = getMinimapElementFrames()
		for key, frames in pairs(elems) do
			local shouldHide = cfg and cfg[key]
			for _, f in ipairs(frames) do
				if shouldHide then
					f:Hide()
				else
					f:Show()
				end
				if not f._eqolMinimapHideHooked then
					f._eqolMinimapHideHooked = true
					local hookKey = key
					f:HookScript("OnShow", function(self)
						local c = addon.db and addon.db.hiddenMinimapElements
						if c and c[hookKey] then self:Hide() end
					end)
				end
			end
		end
	end

	-- Apply on load with a tiny delay to ensure frames exist
	C_Timer.After(0, function()
		if addon.functions.ApplyMinimapElementVisibility then addon.functions.ApplyMinimapElementVisibility() end
	end)

	-- Apply merchant extension on load if enabled
	if addon.db["enableExtendedMerchant"] and addon.Merchant and addon.Merchant.Enable then addon.Merchant:Enable() end

	function addon.functions.toggleDynamicFlightBar(value)
		addon.variables = addon.variables or {}
		local bar = UIWidgetPowerBarContainerFrame
		if not bar then return end
		if InCombatLockdown and InCombatLockdown() then
			-- Defer secure attribute updates until combat lockdown ends.
			addon.variables.pendingDynamicFlightBar = value
			return
		end

		addon.variables.pendingDynamicFlightBar = nil
		if value then
			if not bar.alphaDriverSet then
				RegisterAttributeDriver(bar, "state-visibility", "[flying]show;hide;")
				bar.alphaDriverSet = true
			end
		else
			addon.variables.requireReload = true
		end
	end
	if addon.db["hideDynamicFlightBar"] then addon.functions.toggleDynamicFlightBar(addon.db["hideDynamicFlightBar"]) end

	local eventFrame = CreateFrame("Frame")
	eventFrame:SetScript("OnUpdate", function(self)
		addon.functions.toggleMinimapButton(addon.db["hideMinimapButton"])
		self:SetScript("OnUpdate", nil)
	end)

	local ICON_SIZE = 32
	local PADDING = 4
	addon.variables.bagButtons = {}
	addon.variables.bagButtonState = {}
	addon.variables.bagButtonPoint = {}
	addon.variables.buttonSink = nil

	local function hoverOutFrame()
		if addon.variables.buttonSink and LDBIcon.objects[addonName .. "_ButtonSinkMap"] then
			if not MouseIsOver(addon.variables.buttonSink) and not MouseIsOver(LDBIcon.objects[addonName .. "_ButtonSinkMap"]) then
				addon.variables.buttonSink:Hide()
			elseif addon.variables.buttonSink:IsShown() then
				C_Timer.After(1, function() hoverOutFrame() end)
			end
		end
	end
	local function hoverOutCheck(frame)
		if frame and frame:IsVisible() then
			if not MouseIsOver(frame) then
				frame:SetAlpha(0)
			else
				C_Timer.After(1, function() hoverOutCheck(frame) end)
			end
		end
	end

	local function positionBagFrame(bagFrame, anchorButton)
		bagFrame:ClearAllPoints()

		-- Zuerst berechnen wir die absoluten Bildschirmkoordinaten des Buttons.
		-- Das geht am einfachsten über 'GetLeft()', 'GetRight()', 'GetTop()', 'GetBottom()'.
		local bLeft = anchorButton:GetLeft() or 0
		local bRight = anchorButton:GetRight() or 0
		local bTop = anchorButton:GetTop() or 0
		local bBottom = anchorButton:GetBottom() or 0

		local screenWidth = GetScreenWidth()
		local screenHeight = GetScreenHeight()

		local bagWidth = bagFrame:GetWidth()
		local bagHeight = bagFrame:GetHeight()

		-- Standard-Anker: Wir wollen z.B. "BOTTOMRIGHT" der Bag an "TOPLEFT" des Buttons
		-- Also Bag rechts vom Button (und Bag unten am Button) – das können wir anpassen
		local pointOnBag = "BOTTOMRIGHT"
		local pointOnButton = "TOPLEFT"

		-- Prüfen, ob wir vertikal oben rausrennen
		-- Falls bTop + bagHeight zu hoch ist, docken wir uns an der "BOTTOMLEFT" des Buttons an
		-- und die Bag an "TOPRIGHT"
		if (bTop + bagHeight) > screenHeight then
			pointOnBag = "TOPRIGHT"
			pointOnButton = "BOTTOMLEFT"
		end

		-- Prüfen, ob wir horizontal links rausrennen (z. B. der Button ist links am Bildschirm
		-- und bagWidth würde drüber hinausragen)
		if (bLeft - bagWidth) < 0 then
			-- Dann wollen wir lieber rechts daneben andocken
			-- Also "BOTTOMLEFT" an "TOPRIGHT"
			if pointOnBag == "BOTTOMRIGHT" then
				pointOnBag = "BOTTOMLEFT"
				pointOnButton = "TOPRIGHT"
			else
				-- oder "TOPLEFT" an "BOTTOMRIGHT"
				pointOnBag = "TOPLEFT"
				pointOnButton = "BOTTOMRIGHT"
			end
		end

		-- Jetzt setzen wir den finalen Anker
		bagFrame:SetPoint(pointOnBag, anchorButton, pointOnButton, 0, 0)
	end

	local function removeButtonSink()
		if addon.variables.buttonSink then
			addon.variables.buttonSink:SetParent(nil)
			addon.variables.buttonSink:SetScript("OnLeave", nil)
			addon.variables.buttonSink:SetScript("OnDragStart", nil)
			addon.variables.buttonSink:SetScript("OnDragStop", nil)
			addon.variables.buttonSink:SetScript("OnEnter", nil)
			addon.variables.buttonSink:SetScript("OnLeave", nil)
			addon.variables.buttonSink:Hide()
			addon.variables.buttonSink = nil
		end
		addon.functions.LayoutButtons()
		if _G[addonName .. "_ButtonSinkMap"] then
			_G[addonName .. "_ButtonSinkMap"]:SetParent(nil)
			_G[addonName .. "_ButtonSinkMap"]:SetScript("OnEnter", nil)
			_G[addonName .. "_ButtonSinkMap"]:SetScript("OnLeave", nil)
			_G[addonName .. "_ButtonSinkMap"]:Hide()
			_G[addonName .. "_ButtonSinkMap"] = nil
		end
		if LDBIcon:IsRegistered(addonName .. "_ButtonSinkMap") then
			local button = LDBIcon.objects[addonName .. "_ButtonSinkMap"]
			if button then button:Hide() end
			LDBIcon.objects[addonName .. "_ButtonSinkMap"] = nil
		end
	end

	local function applyButtonSinkAppearance(frame)
		frame = frame or (addon.variables and addon.variables.buttonSink)
		if not frame or not frame.SetBackdrop then return end
		local hideBg = addon.db["minimapButtonBinHideBackground"]
		local hideBorder = addon.db["minimapButtonBinHideBorder"]
		if hideBg and hideBorder then
			frame:SetBackdrop(nil)
			return
		end
		frame:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
		})
		if hideBg then
			frame:SetBackdropColor(0, 0, 0, 0)
		else
			frame:SetBackdropColor(0, 0, 0, 0.4)
		end
		if hideBorder then
			frame:SetBackdropBorderColor(1, 1, 1, 0)
		else
			frame:SetBackdropBorderColor(1, 1, 1, 1)
		end
	end
	addon.functions.applyButtonSinkAppearance = applyButtonSinkAppearance

	local function firstStartButtonSink(counter)
		if hookedATT then return end
		if C_AddOns.IsAddOnLoadable("AllTheThings") then
			if _G["AllTheThings-Minimap"] then
				addon.functions.gatherMinimapButtons()
				addon.functions.LayoutButtons()
				return
			end
			if _G["AllTheThings"] and _G["AllTheThings"].SetMinimapButtonSettings then
				hooksecurefunc(_G["AllTheThings"], "SetMinimapButtonSettings", function(self, visible)
					addon.functions.gatherMinimapButtons()
					addon.functions.LayoutButtons()
				end)
				hookedATT = true
				return
			end
			if counter < 30 then C_Timer.After(0.5, function() firstStartButtonSink(counter + 1) end) end
		end
	end

	function addon.functions.toggleButtonSink()
		if addon.db["enableMinimapButtonBin"] then
			removeButtonSink()

			firstStartButtonSink(0)
			local buttonBag = CreateFrame("Frame", addonName .. "_ButtonSink", UIParent, "BackdropTemplate")
			buttonBag:SetSize(150, 150)

			if addon.db["useMinimapButtonBinIcon"] then
				buttonBag:SetScript("OnLeave", function(self)
					if addon.db["useMinimapButtonBinIcon"] then C_Timer.After(1, function() hoverOutFrame() end) end
				end)
			else
				if not addon.db["lockMinimapButtonBin"] then
					buttonBag:SetMovable(true)
					buttonBag:EnableMouse(true)
					buttonBag:RegisterForDrag("LeftButton")
					buttonBag:SetScript("OnDragStart", buttonBag.StartMoving)
					buttonBag:SetScript("OnDragStop", function(self)
						self:StopMovingOrSizing()
						-- Position speichern
						local point, _, _, xOfs, yOfs = self:GetPoint()
						addon.db["minimapSinkHoleData"].point = point
						addon.db["minimapSinkHoleData"].x = xOfs
						addon.db["minimapSinkHoleData"].y = yOfs
					end)
				end
				buttonBag:SetPoint(
					addon.db["minimapSinkHoleData"].point or "CENTER",
					UIParent,
					addon.db["minimapSinkHoleData"].point or "CENTER",
					addon.db["minimapSinkHoleData"].x or 0,
					addon.db["minimapSinkHoleData"].y or 0
				)
				if addon.db["useMinimapButtonBinMouseover"] then
					buttonBag:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
					buttonBag:SetScript("OnLeave", function(self) hoverOutCheck(self) end)
					buttonBag:SetAlpha(0)
				end
			end
			addon.variables.buttonSink = buttonBag
			applyButtonSinkAppearance(buttonBag)
			addon.functions.gatherMinimapButtons()
			addon.functions.LayoutButtons()

			-- create ButtonSink Button
			if addon.db["useMinimapButtonBinIcon"] then
				local iconData = {
					type = "launcher",
					icon = "Interface\\AddOns\\" .. addonName .. "\\Icons\\SinkHole.tga" or "Interface\\ICONS\\INV_Misc_QuestionMark", -- irgendein Icon
					label = addonName .. "_ButtonSinkMap",
					OnEnter = function(self)
						positionBagFrame(addon.variables.buttonSink, LDBIcon.objects[addonName .. "_ButtonSinkMap"])
						addon.variables.buttonSink:Show()
					end,
					OnLeave = function(self)
						if addon.db["useMinimapButtonBinIcon"] then C_Timer.After(1, function() hoverOutFrame() end) end
					end,
				}
				-- Registriere das Icon bei LibDBIcon
				LDB:NewDataObject(addonName .. "_ButtonSinkMap", iconData)
				LDBIcon:Register(addonName .. "_ButtonSinkMap", iconData, addon.db["buttonsink"])
				buttonBag:Hide()
			else
				buttonBag:Show()
			end
		elseif addon.variables.buttonSink then
			removeButtonSink()
		end
	end

	function addon.functions.LayoutButtons()
		if addon.db["enableMinimapButtonBin"] then
			local columns = tonumber(addon.db["minimapButtonBinColumns"]) or DEFAULT_BUTTON_SINK_COLUMNS
			columns = math.floor(columns + 0.5)
			if columns < 1 then
				columns = 1
			elseif columns > 10 then
				columns = 10
			end
			if addon.variables.buttonSink then
				local index = 0
				for name, button in pairs(addon.variables.bagButtons) do
					if addon.db["ignoreMinimapButtonBin_" .. name] then
						button:ClearAllPoints()
						button:SetParent(Minimap)
						if addon.variables.bagButtonPoint[name] then
							local pData = addon.variables.bagButtonPoint[name]
							if pData.point and pData.relativePoint and pData.relativeTo and pData.xOfs and pData.yOfs then
								button:SetPoint(pData.point, pData.relativeTo, pData.relativePoint, pData.xOfs, pData.yOfs)
							end
							if button:GetFrameStrata() == "LOW" then button:SetFrameStrata("MEDIUM") end
						end
					elseif addon.variables.bagButtonState[name] then
						index = index + 1
						button:ClearAllPoints()
						local col = (index - 1) % columns
						local row = math.floor((index - 1) / columns)

						button:SetParent(addon.variables.buttonSink)
						button:SetSize(ICON_SIZE, ICON_SIZE)
						button:SetPoint("TOPLEFT", addon.variables.buttonSink, "TOPLEFT", col * (ICON_SIZE + PADDING) + PADDING, -row * (ICON_SIZE + PADDING) - PADDING)
						button:Show()
					else
						button:Hide()
					end
				end

				local totalRows = math.ceil(index / columns)
				local tmpColumns = min(index, columns)
				local width = (ICON_SIZE + PADDING) * tmpColumns + PADDING
				local height = (ICON_SIZE + PADDING) * totalRows + PADDING
				if index == 0 then
					addon.variables.buttonSink:SetSize(0, 0)
				else
					addon.variables.buttonSink:SetSize(width, height)
				end
			end
		else
			for name, button in pairs(addon.variables.bagButtons) do
				button:ClearAllPoints()
				button:SetParent(Minimap)
				addon.variables.bagButtons[name] = nil
				addon.variables.bagButtonState[name] = nil
				if addon.variables.bagButtonPoint[name] then
					local pData = addon.variables.bagButtonPoint[name]
					if pData.point and pData.relativePoint and pData.relativeTo and pData.xOfs and pData.yOfs then
						button:SetPoint(pData.point, pData.relativeTo, pData.relativePoint, pData.xOfs, pData.yOfs)
					else
						LDBIcon:Show(name)
					end
					if button:GetFrameStrata() == "LOW" then button:SetFrameStrata("MEDIUM") end
					addon.variables.bagButtonPoint[name] = nil
				end
			end
		end
	end

	function addon.functions.gatherMinimapButtons()
		for _, child in ipairs({ Minimap:GetChildren() }) do
			if child:IsObjectType("Button") and child:GetName() then
				local btnName = child:GetName():gsub("^LibDBIcon10_", ""):gsub(".*_LibDBIcon_", "")
				if
					not (
						btnName == "MinimapZoomIn"
						or btnName == "MinimapZoomOut"
						or btnName == "MiniMapWorldMapButton"
						or btnName == "MiniMapTracking"
						or btnName == "GameTimeFrame"
						or btnName == "MinimapMailFrame"
						or btnName:match("^HandyNotesPin")
						or btnName == addonName .. "_ButtonSinkMap"
					)
				then
					if not addon.variables.bagButtonPoint[btnName] or not addon.variables.bagButtonPoint[btnName].point then
						local point, relativeTo, relativePoint, xOfs, yOfs = child:GetPoint()
						addon.variables.bagButtonPoint[btnName] = {
							point = point,
							relativeTo = relativeTo,
							relativePoint = relativePoint,
							xOfs = xOfs,
							yOfs = yOfs,
						}
					end
					if (child.db and child.db.hide) or not child:IsVisible() then
						addon.variables.bagButtonState[btnName] = false
					else
						addon.variables.bagButtonState[btnName] = true
						addon.variables.bagButtons[btnName] = child
					end
				end
			end
		end
	end
	hooksecurefunc(LDBIcon, "Show", function(self, name)
		if addon.db["enableMinimapButtonBin"] then
			if nil ~= addon.variables.bagButtonState[name] then addon.variables.bagButtonState[name] = true end
			addon.functions.gatherMinimapButtons()
			addon.functions.LayoutButtons()
		end
	end)

	hooksecurefunc(LDBIcon, "Hide", function(self, name)
		if addon.db["enableMinimapButtonBin"] then
			addon.variables.bagButtonState[name] = false
			addon.functions.gatherMinimapButtons()
			addon.functions.LayoutButtons()
		end
	end)

	local radioRows = {}
	local maxTextWidth = 0
	local rowHeight = 28 -- Höhe pro Zeile (Font + etwas Puffer)
	local totalRows = 0

	function addon.functions.updateLootspecIcon()
		if not LDBIcon or not LDBIcon:IsRegistered(addonName .. "_LootSpec") then return end

		local _, specIcon

		local curSpec = C_SpecializationInfo.GetSpecialization()

		if GetLootSpecialization() == 0 and curSpec then
			_, _, _, specIcon = GetSpecializationInfoForClassID(addon.variables.unitClassID, curSpec)
		else
			_, _, _, specIcon = GetSpecializationInfoByID(GetLootSpecialization())
		end

		local button = LDBIcon.objects[addonName .. "_LootSpec"]
		if button and button.icon and specIcon then button.icon:SetTexture(specIcon) end
	end

	local function UpdateRadioSelection()
		local lootSpecID = GetLootSpecialization() or 0
		for _, row in ipairs(radioRows) do
			row.radio:SetChecked(row.specId == lootSpecID)
		end
	end

	local function CreateRadioRow(parent, specId, specName, index)
		totalRows = totalRows + 1

		local row = CreateFrame("Button", "MyRadioRow" .. index, parent, "BackdropTemplate")
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		row:GetHighlightTexture():SetAlpha(0.3)

		row.radio = CreateFrame("CheckButton", "$parentRadio", row, "UIRadioButtonTemplate")
		row.radio:SetPoint("LEFT", row, "LEFT", 4, 0)
		row.radio:SetChecked(false)

		row.radio.text:SetFontObject(GameFontNormalLarge)
		row.radio.text:SetText(specName)

		row:RegisterForClicks("AnyUp")
		row.radio:RegisterForClicks("AnyUp")

		local textWidth = row.radio.text:GetStringWidth()
		if textWidth > maxTextWidth then maxTextWidth = textWidth end

		row.specId = specId

		row:SetScript("OnClick", function(self, button)
			if button == "LeftButton" then
				SetLootSpecialization(specId)
			else
				C_SpecializationInfo.SetSpecialization(index)
			end
		end)

		row.radio:SetScript("OnClick", function(self, button)
			if button == "LeftButton" then
				SetLootSpecialization(specId)
			else
				C_SpecializationInfo.SetSpecialization(index)
			end
		end)

		table.insert(radioRows, row)
		return row
	end

	function addon.functions.removeLootspecframe()
		if LDBIcon:IsRegistered(addonName .. "_LootSpec") then
			local button = LDBIcon.objects[addonName .. "_LootSpec"]
			if button then button:Hide() end
			LDBIcon.objects[addonName .. "_LootSpec"] = nil
		end
		if addon.variables.lootSpec then
			addon.variables.lootSpec:SetParent(nil)
			addon.variables.lootSpec:SetScript("OnEvent", nil)
			addon.variables.lootSpec:Hide()
			addon.variables.lootSpec = nil
		end
	end

	local function hoverCheckHide(frame)
		if frame and frame:IsVisible() then
			if not MouseIsOver(frame) then
				frame:Hide()
			else
				C_Timer.After(1, function() hoverCheckHide(frame) end)
			end
		end
	end

	function addon.functions.createLootspecFrame()
		totalRows = 0
		radioRows = {}
		local lootSpec = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
		lootSpec:SetPoint("CENTER")
		lootSpec:SetSize(200, 200) -- Erstmal ein Dummy-Wert, wir passen es später an
		lootSpec:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
		})
		lootSpec:SetBackdropColor(0, 0, 0, 0.4)
		lootSpec:SetBackdropBorderColor(1, 1, 1, 1)
		addon.variables.lootSpec = lootSpec
		lootSpec:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")
		lootSpec:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
		lootSpec:SetScript("OnEvent", function(self, event)
			if event == "ACTIVE_TALENT_GROUP_CHANGED" then
				addon.functions.removeLootspecframe()
				addon.functions.createLootspecFrame()
			end
			addon.functions.updateLootspecIcon()
			UpdateRadioSelection()
		end)

		local container = CreateFrame("Frame", nil, lootSpec, "BackdropTemplate")
		container:SetPoint("TOPLEFT", 10, -10)
		if nil == C_SpecializationInfo.GetSpecialization() then return end

		local _, curSpecName = GetSpecializationInfoForClassID(addon.variables.unitClassID, C_SpecializationInfo.GetSpecialization())
		local totalSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(addon.variables.unitClassID)
		local row = CreateRadioRow(container, 0, string.format(LOOT_SPECIALIZATION_DEFAULT, curSpecName), 0)
		for i = 1, totalSpecs do
			local specID, specName, _, specIcon = GetSpecializationInfoForClassID(addon.variables.unitClassID, i)
			CreateRadioRow(container, specID, specName, i)
		end

		for i, row in ipairs(radioRows) do
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i - 1) * rowHeight)
			row:SetSize(maxTextWidth + 40, rowHeight)
		end

		local finalHeight = #radioRows * rowHeight + 20
		local finalWidth = math.max(maxTextWidth + 40, 150)

		container:SetSize(finalWidth, finalHeight)
		lootSpec:SetSize(finalWidth + 20, finalHeight + 20)

		local iconData = {
			type = "launcher",
			icon = "Interface\\ICONS\\INV_Misc_QuestionMark", -- irgendein Icon
			label = addonName .. "_LootSpec",
			OnEnter = function(self)
				if addon.variables.lootSpec then
					positionBagFrame(addon.variables.lootSpec, LDBIcon.objects[addonName .. "_LootSpec"])
					addon.variables.lootSpec:Show()
				end
			end,
			OnLeave = function(self)
				C_Timer.After(1, function() hoverCheckHide(addon.variables.lootSpec) end)
			end,
		}

		LDB:NewDataObject(addonName .. "_LootSpec", iconData)
		LDBIcon:Register(addonName .. "_LootSpec", iconData, addon.db["lootspec_quickswitch"])

		UpdateRadioSelection()
		lootSpec:Hide()
		addon.functions.updateLootspecIcon()
	end

	if addon.db["enableLootspecQuickswitch"] then addon.functions.createLootspecFrame() end
	if addon.InstanceDifficulty and addon.InstanceDifficulty.SetEnabled then addon.InstanceDifficulty:SetEnabled(addon.db["showInstanceDifficulty"]) end
	if addon.DungeonJournalLootSpec and addon.DungeonJournalLootSpec.SetEnabled then addon.DungeonJournalLootSpec:SetEnabled(addon.db["dungeonJournalLootSpecIcons"]) end
end

function addon.functions.createInstantCatalystButton()
	if not ItemInteractionFrame or EnhanceQoLInstantCatalyst then return end

	local parent = ItemInteractionFrame.ButtonFrame or ItemInteractionFrame
	local anchor = ItemInteractionFrame.TopTileStreaks

	local button = CreateFrame("Button", "EnhanceQoLInstantCatalyst", parent, "BackdropTemplate")
	button:SetSize(32, 32)
	button:SetEnabled(false)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(button)
	icon:SetTexture("Interface\\AddOns\\EnhanceQoL\\Icons\\InstantCatalyst.tga")
	button.icon = icon

	-- TODO bug in midnight beta we can't modify tooltip
	if not addon.variables.isMidnight then
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:ClearLines()
			GameTooltip:AddLine(L["Instant Catalyst"])
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
	end

	if anchor then
		button:SetPoint("RIGHT", anchor, "RIGHT", -2, 0)
	else
		button:SetPoint("BOTTOM", parent, "BOTTOM", 0, 4)
	end

	button:SetScript("OnClick", function() C_ItemInteraction.PerformItemInteraction() end)

	ItemInteractionFrame:HookScript("OnShow", function()
		button:SetEnabled(false)
		button.icon:SetDesaturated(true)
	end)
end

function addon.functions.toggleInstantCatalystButton(value)
	if not C_AddOns.IsAddOnLoaded("Blizzard_ItemInteractionUI") then return end
	if not ItemInteractionFrame then return end

	if value then
		if not EnhanceQoLInstantCatalyst then addon.functions.createInstantCatalystButton() end
		if EnhanceQoLInstantCatalyst then
			EnhanceQoLInstantCatalyst:Show()
			if ItemInteractionFrame:IsShown() then
				if not ItemInteractionFrame.ButtonFrame.ActionButton:IsEnabled() then
					EnhanceQoLInstantCatalyst:SetEnabled(false)
					EnhanceQoLInstantCatalyst.icon:SetDesaturated(true)
				else
					EnhanceQoLInstantCatalyst:SetEnabled(true)
					EnhanceQoLInstantCatalyst.icon:SetDesaturated(false)
				end
			end
		end
	elseif EnhanceQoLInstantCatalyst then
		EnhanceQoLInstantCatalyst:Hide()
	end
end

local function initCharacter() addon.functions.initItemInventory() end

-- Frame-Position wiederherstellen
local function RestorePosition(frame)
	if addon.db.point and addon.db.x and addon.db.y then
		frame:ClearAllPoints()
		frame:SetPoint(addon.db.point, UIParent, addon.db.point, addon.db.x, addon.db.y)
	end
end

function addon.functions.checkReloadFrame()
	if addon.variables.requireReload == false then return end
	if _G["ReloadUIPopup"] and _G["ReloadUIPopup"]:IsShown() then return end

	if _G["ReloadUIPopup"] then
		_G["ReloadUIPopup"]:Show()
		return
	end
	local reloadFrame = CreateFrame("Frame", "ReloadUIPopup", UIParent, "BasicFrameTemplateWithInset")
	reloadFrame:SetFrameStrata("TOOLTIP")
	reloadFrame:SetSize(500, 120) -- Breite und Höhe
	reloadFrame:SetPoint("TOP", UIParent, "TOP", 0, -200) -- Zentriert auf dem Bildschirm

	reloadFrame.title = reloadFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	reloadFrame.title:SetPoint("TOP", reloadFrame, "TOP", 0, -6)
	reloadFrame.title:SetText(L["tReloadInterface"])

	reloadFrame.infoText = reloadFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	reloadFrame.infoText:SetPoint("CENTER", reloadFrame, "CENTER", 0, 10)
	reloadFrame.infoText:SetText(L["bReloadInterface"])

	local reloadButton = CreateFrame("Button", nil, reloadFrame, "GameMenuButtonTemplate")
	reloadButton:SetSize(120, 30)
	reloadButton:SetPoint("BOTTOMLEFT", reloadFrame, "BOTTOMLEFT", 10, 10)
	reloadButton:SetText(RELOADUI)
	reloadButton:SetScript("OnClick", function() ReloadUI() end)

	local cancelButton = CreateFrame("Button", nil, reloadFrame, "GameMenuButtonTemplate")
	cancelButton:SetSize(120, 30)
	cancelButton:SetPoint("BOTTOMRIGHT", reloadFrame, "BOTTOMRIGHT", -10, 10)
	cancelButton:SetText(CANCEL)
	cancelButton:SetScript("OnClick", function()
		reloadFrame:Hide()
		addon.variables.requireReload = false -- disable the prompt on cancel
	end)

	reloadFrame:Show()
end

local function CreateUI()
	-- Create the main frame
	local frame = AceGUI:Create("Frame")
	addon.aceFrame = frame.frame
	addon.functions.applyOptionsFrameScale()
	frame:SetTitle("EnhanceQoL")
	frame:SetWidth(800)
	frame:SetHeight(600)
	frame:SetLayout("Fill")

	-- Frame wiederherstellen und überprfen, wenn das Addon geladen wird
	frame.frame:Hide()
	frame.frame:SetScript("OnShow", function(self)
		addon.functions.applyOptionsFrameScale()
		RestorePosition(self)
	end)
	frame.frame:SetScript("OnHide", function(self)
		local point, _, _, xOfs, yOfs = self:GetPoint()
		addon.db.point = point
		addon.db.x = xOfs
		addon.db.y = yOfs
		addon.functions.checkReloadFrame()
	end)
	addon.treeGroupData = {}

	-- Create the TreeGroup with new top-level navigation
	addon.treeGroup = AceGUI:Create("TreeGroup")
	addon.treeGroup.enabletooltips = false

	-- Top: Combat & Dungeons (children added by sub-addons like Aura, Mythic+, Drink, CombatMeter)
	addon.functions.addToTree(nil, { value = "combat", text = L["CombatDungeons"] })

	-- Top: Items & Inventory (core pages + Vendors & Economy)
	addon.functions.addToTree(nil, {
		value = "items",
		text = L["ItemsInventory"],
		children = {
			{ value = "loot", text = L["Loot"] },
			{ value = "gear", text = L["GearUpgrades"] },
			{ value = "economy", text = L["VendorsEconomy"] },
			{ value = "container", text = L["ContainerActions"] }
		},
	})

	-- Top: Map & Navigation (Teleports added by Mythic+)
	addon.functions.addToTree(nil, {
		value = "nav",
		text = L["MapNavigation"],
		children = {
			{ value = "quest", text = L["Quest"] },
		},
	})

	-- Top: UI & Input
	addon.functions.addToTree(nil, {
		value = "ui",
		text = L["UIInput"],
		children = {
			{ value = "actionbar", text = L["VisibilityHubName"] or ACTIONBARS_LABEL },
			{ value = "chatframe", text = HUD_EDIT_MODE_CHAT_FRAME_LABEL },
			{ value = "unitframe", text = UNITFRAME_LABEL },
			{ value = "datapanel", text = "Datapanel" },
			{ value = "social", text = L["Social"] },
			{ value = "system", text = L["System"] },
		},
	})

	-- Top: Media & Sound (only if at least one media addon is available)
	local addMediaRoot = false

	local ok1 = false
	local ok2 = false
	if C_AddOns and C_AddOns.GetAddOnEnableState then
		ok1 = C_AddOns.GetAddOnEnableState("EnhanceQoLSharedMedia", UnitName("player")) == 2
		ok2 = C_AddOns.GetAddOnEnableState("EnhanceQoLSound", UnitName("player")) == 2
	end
	if ok1 or ok2 then addMediaRoot = true end

	if addMediaRoot then addon.functions.addToTree(nil, { value = "media", text = L["Media & Sound"] or "Media & Sound" }) end

	-- Top: Events
	-- if addon.functions.IsTimerunner() then addon.functions.addToTree(nil, {
	-- 	value = "events",
	-- 	text = EVENTS_LABEL or L["Events"] or "Events",
	-- }) end

	-- Top: Profiles
	table.insert(addon.treeGroupData, {
		value = "profiles",
		text = L["Profiles"],
	})
	addon.treeGroup:SetLayout("Fill")
	addon.treeGroup:SetTree(addon.treeGroupData)
	addon.treeGroup:SetCallback("OnGroupSelected", function(container, _, group)
		container:ReleaseChildren() -- Entfernt vorherige Inhalte
		-- Prüfen, welche Gruppe ausgewählt wurde
		if addon.functions.ShowOptionsPage and addon.functions.ShowOptionsPage(container, group) then return end

		-- Vendors & Economy sub-pages handled by vendor module
		if string.sub(group, 1, string.len("items\001economy\001selling")) == "items\001economy\001selling" then
			-- Forward Selling (Auto-Sell) pages to Vendor UI
			addon.Vendor.functions.treeCallback(container, group)
			-- CraftShopper is integrated into the Selling root; no standalone panel
			-- Combat & Dungeons
		elseif group == "combat" then
			Settings.OpenToCategory(addon.SettingsLayout.characterInspectCategory:GetID())
		-- Forward Combat subtree for modules (Mythic+, Aura, Drink, CombatMeter)
		elseif group == "items" then
			Settings.OpenToCategory(addon.SettingsLayout.inventoryCategory:GetID())
		elseif group == "items\001container" then
			Settings.OpenToCategory(addon.SettingsLayout.containerActionCategory:GetID())
		-- Forward Combat subtree for modules (Mythic+, Aura, Drink, CombatMeter)
		elseif string.sub(group, 1, string.len("combat\001")) == "combat\001" then
			-- Normalize and dispatch for known combat modules
			if string.find(group, "mythicplus", 1, true) then
				addon.MythicPlus.functions.treeCallback(container, group)
			elseif
				group:find("combat\001resourcebar", 1, true)
				or group:find("combat\001bufftracker", 1, true)
				or group:find("combat\001casttracker", 1, true)
				or group:find("combat\001cooldownnotify", 1, true)
				or group:find("combat\001combatassist", 1, true)
			then
				addon.Aura.functions.treeCallback(container, group)
			elseif string.find(group, "\001drink", 1, true) or string.sub(group, 1, 5) == "drink" or group:find("combat\001drink", 1, true) then
				local pos = group:find("drink", 1, true)
				addon.Drinks.functions.treeCallback(container, group:sub(pos))
			elseif string.find(group, "\001combatmeter", 1, true) or string.sub(group, 1, 11) == "combatmeter" or group:find("combat\001combatmeter", 1, true) then
				local pos = group:find("combatmeter", 1, true)
				addon.CombatMeter.functions.treeCallback(container, group:sub(pos))
			else
				-- Fallback to Mythic+ for other combat children
				addon.MythicPlus.functions.treeCallback(container, group)
			end
		-- Map & Navigation
		elseif group == "nav" then
			addMinimapFrame(container)
		elseif group == "nav\001teleports" then
			addon.MythicPlus.functions.treeCallback(container, group)
		-- UI & Input
		elseif group == "ui\001mouse" then
			addon.Mouse.functions.treeCallback(container, "mouse")
		elseif group == "ui\001tooltip" then
			addon.Tooltip.functions.treeCallback(container, group:sub(4)) -- pass "tooltip..."
		-- UF Plus
		elseif string.match(group, "^ufplus") then
			if addon.Aura and addon.Aura.UF and addon.Aura.UF.treeCallback then addon.Aura.UF.treeCallback(container, group) end
		-- Quests under Map & Navigation
		elseif group == "nav\001quest" then
			addQuestFrame(container, true)
		-- Social under UI
		-- Events
		elseif group == "events" or group == "events\001legionremix" then
			if addon.Events and addon.Events.LegionRemix and addon.Events.LegionRemix.functions and addon.Events.LegionRemix.functions.treeCallback then
				addon.Events.LegionRemix.functions.treeCallback(container, group)
			end
		elseif group == "profiles" then
			local scroll = addon.functions.createContainer("ScrollFrame", "List")
			scroll:SetFullWidth(true)
			scroll:SetFullHeight(true)
			container:AddChild(scroll)

			local sub = addon.functions.createContainer("SimpleGroup", "Flow")
			scroll:AddChild(sub)
			AceConfigDlg:Open("EQOL_Profiles", sub)
			scroll:DoLayout()
		-- Media & Sound wrappers
		elseif group == "media" then
			-- Show Shared Media content directly when available
			if addon.SharedMedia and addon.SharedMedia.functions and addon.SharedMedia.functions.treeCallback then addon.SharedMedia.functions.treeCallback(container, "media") end
		elseif string.sub(group, 1, string.len("media\001")) == "media\001" then
			-- Route any Media children to Sound module (flattened categories)
			if addon.Sounds and addon.Sounds.functions and addon.Sounds.functions.treeCallback then addon.Sounds.functions.treeCallback(container, group) end
		elseif string.match(group, "^vendor") then
			addon.Vendor.functions.treeCallback(container, group)
		elseif string.match(group, "^drink") then
			addon.Drinks.functions.treeCallback(container, group)
		elseif string.find(group, "mythicplus", 1, true) then
			addon.MythicPlus.functions.treeCallback(container, group)
		elseif string.match(group, "^aura") then
			addon.Aura.functions.treeCallback(container, group)
		elseif string.match(group, "^sound") then
			addon.Sounds.functions.treeCallback(container, group)
		elseif string.match(group, "^sharedmedia") then
			addon.SharedMedia.functions.treeCallback(container, group)
		elseif string.match(group, "^mouse") then
			addon.Mouse.functions.treeCallback(container, group)
		elseif string.match(group, "^combatmeter") then
			addon.CombatMeter.functions.treeCallback(container, group)
		elseif string.match(group, "^move") then
			addon.LayoutTools.functions.treeCallback(container, group)
		elseif string.sub(group, 1, string.len("ui\001move")) == "ui\001move" then
			addon.LayoutTools.functions.treeCallback(container, group:sub(4))
		end
	end)
	addon.treeGroup:SetStatusTable(addon.variables.statusTable)
	addon.variables.statusTable.groups["items"] = true
	frame:AddChild(addon.treeGroup)

	-- Select a meaningful default page
	addon.treeGroup:SelectByPath("profiles")

	-- Datenobjekt fr den Minimap-Button
	local EnhanceQoLLDB = LDB:NewDataObject("EnhanceQoL", {
		type = "launcher",
		text = addonName,
		icon = "Interface\\AddOns\\" .. addonName .. "\\Icons\\Icon.tga", -- Hier kannst du dein eigenes Icon verwenden
		OnClick = function(_, msg)
			if msg == "LeftButton" then
				if frame:IsShown() then
					frame:Hide()
				else
					frame:Show()
				end
			else
				Settings.OpenToCategory(addon.SettingsLayout.rootCategory:GetID())
			end
		end,
		OnTooltipShow = function(tt)
			tt:AddLine(addonName)
			tt:AddLine(L["Left-Click to show options"])
		end,
	})
	-- Toggle Minimap Button based on settings
	LDBIcon:Register(addonName, EnhanceQoLLDB, EnhanceQoLDB)

	-- Register to addon compartment
	AddonCompartmentFrame:RegisterAddon({
		text = "Enhance QoL",
		icon = "Interface\\AddOns\\EnhanceQoL\\Icons\\Icon.tga",
		notCheckable = true,
		func = function(button, menuInputData, menu)
			if frame:IsShown() then
				frame:Hide()
			else
				frame:Show()
			end
		end,
		funcOnEnter = function(button)
			MenuUtil.ShowTooltip(button, function(tooltip) tooltip:SetText(L["Left-Click to show options"]) end)
		end,
		funcOnLeave = function(button) MenuUtil.HideTooltip(button) end,
	})
end

local function setAllHooks()
	if RuneFrame then
		RuneFrame:HookScript("OnShow", function(self)
			if addon.db["deathknight_HideRuneFrame"] then
				RuneFrame:Hide()
			else
				RuneFrame:Show()
			end
		end)

		if addon.db["deathknight_HideRuneFrame"] then RuneFrame:Hide() end
	end

	if DruidComboPointBarFrame then
		DruidComboPointBarFrame:HookScript("OnShow", function(self)
			if addon.db["druid_HideComboPoint"] then
				DruidComboPointBarFrame:Hide()
			else
				DruidComboPointBarFrame:Show()
			end
		end)
		if addon.db["druid_HideComboPoint"] then DruidComboPointBarFrame:Hide() end
	end

	if EssencePlayerFrame then
		EssencePlayerFrame:HookScript("OnShow", function(self)
			if addon.db["evoker_HideEssence"] then EssencePlayerFrame:Hide() end
		end)
		if addon.db["evoker_HideEssence"] then EssencePlayerFrame:Hide() end -- Initialset
	end

	if MonkHarmonyBarFrame then
		MonkHarmonyBarFrame:HookScript("OnShow", function(self)
			if addon.db["monk_HideHarmonyBar"] then
				MonkHarmonyBarFrame:Hide()
			else
				MonkHarmonyBarFrame:Show()
			end
		end)
		if addon.db["monk_HideHarmonyBar"] then MonkHarmonyBarFrame:Hide() end
	end

	if RogueComboPointBarFrame then
		RogueComboPointBarFrame:HookScript("OnShow", function(self)
			if addon.db["rogue_HideComboPoint"] then
				RogueComboPointBarFrame:Hide()
			else
				RogueComboPointBarFrame:Show()
			end
		end)
		if addon.db["rogue_HideComboPoint"] then RogueComboPointBarFrame:Hide() end
	end

	if PaladinPowerBarFrame then
		PaladinPowerBarFrame:HookScript("OnShow", function(self)
			if addon.db["paladin_HideHolyPower"] then
				PaladinPowerBarFrame:Hide()
			else
				PaladinPowerBarFrame:Show()
			end
		end)
		if addon.db["paladin_HideHolyPower"] then PaladinPowerBarFrame:Hide() end
	end

	if TotemFrame then
		local classname = string.lower(select(2, UnitClass("player")))
		TotemFrame:HookScript("OnShow", function(self)
			if addon.db[classname .. "_HideTotemBar"] then
				TotemFrame:Hide()
			else
				TotemFrame:Show()
			end
		end)
		if addon.db[classname .. "_HideTotemBar"] then TotemFrame:Hide() end
	end

	if WarlockPowerFrame then
		WarlockPowerFrame:HookScript("OnShow", function(self)
			if addon.db["warlock_HideSoulShardBar"] then
				WarlockPowerFrame:Hide()
			else
				WarlockPowerFrame:Show()
			end
		end)
		if addon.db["warlock_HideSoulShardBar"] then WarlockPowerFrame:Hide() end
	end

	local ignoredApplicants = {}

	local function FlagIgnoredApplicants(applicantIDs)
		if not addon.db.enableIgnore or not addon.Ignore or not addon.Ignore.CheckIgnore then return end
		wipe(ignoredApplicants)
		for _, applicantID in ipairs(applicantIDs) do
			local name = C_LFGList.GetApplicantMemberInfo(applicantID, 1)
			if type(name) == "string" then
				local entry = addon.Ignore:CheckIgnore(name)
				if entry then ignoredApplicants[applicantID] = entry end
			end
		end
	end

	local function ApplyIgnoreHighlight(memberFrame, applicantID)
		local entry = ignoredApplicants[applicantID]
		if not entry or not memberFrame or not memberFrame.Name then return end
		memberFrame.Name:SetTextColor(1, 0, 0, 1)
		memberFrame.Name:SetText("!!! " .. memberFrame.Name:GetText() .. " !!!")
		memberFrame.eqolIgnoreEntry = entry
	end

	local function SortApplicants(applicants)
		if addon.db.lfgSortByRio then
			local function SortApplicantsCB(applicantID1, applicantID2)
				local applicantInfo1 = C_LFGList.GetApplicantInfo(applicantID1)
				local applicantInfo2 = C_LFGList.GetApplicantInfo(applicantID2)

				if applicantInfo1 == nil then return false end

				if applicantInfo2 == nil then return true end

				local _, _, _, _, _, _, _, _, _, _, _, dungeonScore1 = C_LFGList.GetApplicantMemberInfo(applicantInfo1.applicantID, 1)
				local _, _, _, _, _, _, _, _, _, _, _, dungeonScore2 = C_LFGList.GetApplicantMemberInfo(applicantInfo2.applicantID, 1)

				return dungeonScore1 > dungeonScore2
			end

			table.sort(applicants, SortApplicantsCB)
		end

		FlagIgnoredApplicants(applicants)
		LFGListApplicationViewer_UpdateResults(LFGListFrame.ApplicationViewer)
	end

	hooksecurefunc("LFGListApplicationViewer_UpdateApplicantMember", function(memberFrame, appID, memberIdx)
		-- Store identifiers for context-menu usage (e.g., Raider.IO link)
		if memberFrame then
			memberFrame._eqolApplicantID = appID
			memberFrame._eqolMemberIdx = memberIdx
		end
		if addon.db.enableIgnore then ApplyIgnoreHighlight(memberFrame, appID) end
	end)

	hooksecurefunc("LFGListApplicationViewer_UpdateResults", function()
		if not addon.db.enableIgnore or addon.db.lfgSortByRio then return end
		local applicants = C_LFGList.GetApplicants() or {}
		FlagIgnoredApplicants(applicants)
	end)

	-- Highlight group listings where the leader is on the ignore list
	local function ApplyIgnoreHighlightSearch(entry)
		if not addon.db.enableIgnore or not addon.Ignore or not addon.Ignore.CheckIgnore then return end
		if not entry or not entry.resultID then return end

		local info = C_LFGList.GetSearchResultInfo(entry.resultID)
		if not info or not info.leaderName then return end

		local ignoreEntry = addon.Ignore:CheckIgnore(info.leaderName)
		if not ignoreEntry then return end

		local function colorString(fs)
			if fs and fs.SetTextColor then fs:SetTextColor(1, 0, 0, 1) end
		end

		colorString(entry.Name)
		colorString(entry.ActivityName)

		if entry.Name and entry.Name.GetText then
			local text = entry.Name:GetText() or ""
			if not text:find("!!!", 1, true) then entry.Name:SetText("!!! " .. text .. " !!!") end
		end
	end

	hooksecurefunc("LFGListSearchEntry_Update", function(entry) ApplyIgnoreHighlightSearch(entry) end)

	hooksecurefunc("LFGListUtil_SortApplicants", SortApplicants)

	initCharacter()
	initMisc()
	initLoot()
	initQuest()
	addon.functions.initDungeonFrame()

	initParty()
	initActionBars()
	initUI()
	initUnitFrame()
	initChatFrame()
	initMap()
	initSocial()
	initLootToast()
	initBagsFrame()

	local LSM = LibStub("LibSharedMedia-3.0")
	local lsmSoundDirty = false
	LSM:RegisterCallback("LibSharedMedia_Registered", function(event, mediaType, ...)
		if mediaType == "sound" then
			if not lsmSoundDirty then
				lsmSoundDirty = true
				C_Timer.After(1, function()
					lsmSoundDirty = false
					if addon.Aura and addon.Aura.functions and addon.Aura.functions.BuildSoundTable then addon.Aura.functions.BuildSoundTable() end
					if addon.ChatIM and addon.ChatIM.BuildSoundTable then addon.ChatIM:BuildSoundTable() end
				end)
			end
		elseif mediaType == "statusbar" then
			-- When new statusbar textures are registered, refresh any UI using them
			if addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.MarkTextureListDirty then addon.Aura.ResourceBars.MarkTextureListDirty() end
			if addon.CombatMeter and addon.CombatMeter.functions and addon.CombatMeter.functions.RefreshBarTextureDropdown then addon.CombatMeter.functions.RefreshBarTextureDropdown() end
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.RefreshPotionTextureDropdown then addon.MythicPlus.functions.RefreshPotionTextureDropdown() end
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.applyPotionBarTexture then addon.MythicPlus.functions.applyPotionBarTexture() end
			if addon.Aura and addon.Aura.CastTracker and addon.Aura.CastTracker.functions and addon.Aura.CastTracker.functions.RefreshTextureDropdown then
				addon.Aura.CastTracker.functions.RefreshTextureDropdown()
			end
			if addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.RefreshTextureDropdown then addon.Aura.ResourceBars.RefreshTextureDropdown() end
		end
	end)
end

function loadMain()
	CreateUI()

	-- Schleife zur Erzeugung der Checkboxen
	addon.checkboxes = {}
	-- addon.db = EnhanceQoLDB
	addon.variables.acceptQuestID = {}

	setAllHooks()

	-- Slash-Command hinzufügen
	SLASH_ENHANCEQOL1 = "/eqol"
	SLASH_ENHANCEQOL2 = "/eqol resetframe"
	SLASH_ENHANCEQOL3 = "/eqol aag"
	SLASH_ENHANCEQOL4 = "/eqol rag"
	SLASH_ENHANCEQOL5 = "/eqol lag"
	SLASH_ENHANCEQOL6 = "/eqol lcid"
	SLASH_ENHANCEQOL6 = "/eqol rq"
	SlashCmdList["ENHANCEQOL"] = function(msg)
		if msg == "resetframe" then
			-- Frame zurücksetzen
			addon.aceFrame:ClearAllPoints()
			addon.aceFrame:SetPoint("CENTER", UIParent, "CENTER")
			addon.db.point = "CENTER"
			addon.db.x = 0
			addon.db.y = 0
			print(addonName .. " frame has been reset to the center.")
		elseif msg:match("^aag%s*(%d+)$") then
			local id = tonumber(msg:match("^aag%s*(%d+)$")) -- Extrahiere die ID
			if id then
				addon.db["autogossipID"][id] = true
				print(ADD, "ID: ", id)
			else
				print("|cffff0000Invalid input! Please provide a ID|r")
			end
		elseif msg:match("^rag%s*(%d+)$") then
			local id = tonumber(msg:match("^rag%s*(%d+)$")) -- Extrahiere die ID
			if id then
				if addon.db["autogossipID"][id] then
					addon.db["autogossipID"][id] = nil
					print(REMOVE, "ID: ", id)
				end
			else
				print("|cffff0000Invalid input! Please provide a ID|r")
			end
		elseif msg == "lag" then
			local options = C_GossipInfo.GetOptions()
			if #options > 0 then
				for _, v in pairs(options) do
					print(v.gossipOptionID, v.name)
				end
			end
		elseif msg == "lcid" then
			for i = 1, 600, 1 do
				local name, id = C_ChallengeMode.GetMapUIInfo(i)
				if name then print(name, id) end
			end
		elseif msg == "rq" then
			if addon.Query and addon.Query.frame then addon.Query.frame:Show() end
		else
			if addon.aceFrame:IsShown() then
				addon.aceFrame:Hide()
			else
				addon.aceFrame:Show()
			end
		end
	end

	-- Frame für die Optionen
	local configFrame = CreateFrame("Frame", addonName .. "ConfigFrame", InterfaceOptionsFramePanelContainer)
	configFrame.name = addonName

	-- Button fr die Optionen
	local configButton = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
	configButton:SetSize(140, 40)
	configButton:SetPoint("TOPLEFT", 10, -10)
	configButton:SetText("Config")
	configButton:SetScript("OnClick", function()
		if addon.aceFrame:IsShown() then
			addon.aceFrame:Hide()
		else
			addon.aceFrame:Show()
		end
	end)

	-- Frame zu den Interface-Optionen hinzufügen
	-- InterfaceOptions_AddCategory(configFrame)
	-- local category, layout = Settings.RegisterCanvasLayoutCategory(configFrame, configFrame.name)
	-- Settings.RegisterAddOnCategory(category)
	-- addon.settingsCategory = category
end

-- Erstelle ein Frame f��r Events
local frameLoad = CreateFrame("Frame")

local gossipClicked = {}

local function loadSubAddon(name)
	local subAddonName = name

	local loadable, reason = C_AddOns.IsAddOnLoadable(name)
	if not loadable and reason == "DEMAND_LOADED" then
		local loaded, value = C_AddOns.LoadAddOn(name)
	end
end

local eventHandlers = {
	["ACTIVE_PLAYER_SPECIALIZATION_CHANGED"] = function(arg1)
		addon.variables.unitSpec = C_SpecializationInfo.GetSpecialization()
		if addon.variables.unitSpec then
			local specId, specName = C_SpecializationInfo.GetSpecializationInfo(addon.variables.unitSpec)
			addon.variables.unitSpecName = specName
			addon.variables.unitRole = GetSpecializationRole(addon.variables.unitSpec)
			addon.variables.unitSpecId = specId
		end

		if addon.db["showIlvlOnBagItems"] then
			addon.functions.updateBags(ContainerFrameCombinedBags)
			for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
				addon.functions.updateBags(frame)
			end
			if _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end
		end
	end,
	["ADDON_LOADED"] = function(arg1)
		if arg1 == addonName then
			local legacy = {}
			if EnhanceQoLDB and not EnhanceQoLDB.profiles then
				for k, v in pairs(EnhanceQoLDB) do
					legacy[k] = v
				end
			end

			local dbObj = AceDB:New("EnhanceQoLDB", defaults, "Default")

			addon.dbObject = dbObj
			addon.db = dbObj.profile
			dbObj:RegisterCallback("OnProfileChanged", function() addon.variables.requireReload = true end)
			dbObj:RegisterCallback("OnProfileCopied", function() addon.variables.requireReload = true end)
			dbObj:RegisterCallback("OnProfileReset", function() addon.variables.requireReload = true end)

			if next(legacy) then
				for k, v in pairs(legacy) do
					if addon.db[k] == nil then addon.db[k] = v end
					EnhanceQoLDB[k] = nil
				end
			end
			local profilesPage = AceDBOptions:GetOptionsTable(addon.dbObject)
			AceConfig:RegisterOptionsTable("EQOL_Profiles", profilesPage)

			if addon.functions.initializePersistentCVars then addon.functions.initializePersistentCVars() end

			loadMain()
			EQOL.PersistSignUpNote()

			--@debug@
			loadSubAddon("EnhanceQoLLayoutTools")
			loadSubAddon("EnhanceQoLQuery")
			--@end-debug@
			loadSubAddon("EnhanceQoLAura")
			loadSubAddon("EnhanceQoLSharedMedia")
			loadSubAddon("EnhanceQoLSound")
			loadSubAddon("EnhanceQoLMouse")
			loadSubAddon("EnhanceQoLMythicPlus")
			if not addon.variables.isMidnight then loadSubAddon("EnhanceQoLCombatMeter") end
			loadSubAddon("EnhanceQoLDrinkMacro")
			loadSubAddon("EnhanceQoLTooltip")
			loadSubAddon("EnhanceQoLVendor")
			
			if addon.Events and addon.Events.LegionRemix and addon.Events.LegionRemix.Init then addon.Events.LegionRemix:Init() end

			checkBagIgnoreJunk()
		end
		if arg1 == "Blizzard_ItemInteractionUI" then addon.functions.toggleInstantCatalystButton(addon.db["instantCatalystEnabled"]) end
	end,
	["CVAR_UPDATE"] = function(cvarName, value)
		local persistentKeys = addon.variables.cvarPersistentKeys
		if not persistentKeys or not persistentKeys[cvarName] then return end

		if not addon.db then return end

		local guard = addon.variables.cvarEnforceGuard
		local persistenceEnabled = addon.db and addon.db.cvarPersistenceEnabled and true or false
		if guard and guard[cvarName] then
			guard[cvarName] = nil
			if not persistenceEnabled then return end
		end

		local overrides = addon.db.cvarOverrides or {}
		addon.db.cvarOverrides = overrides

		local currentValue = value
		if currentValue == nil then currentValue = GetCVar(cvarName) end
		if currentValue ~= nil then currentValue = tostring(currentValue) end

		if overrides[cvarName] == nil or not persistenceEnabled then
			overrides[cvarName] = currentValue
			if not persistenceEnabled then return end
		else
			overrides[cvarName] = tostring(overrides[cvarName])
		end

		local desiredValue = overrides[cvarName]
		if desiredValue and currentValue ~= desiredValue then setCVarValue(cvarName, desiredValue) end
	end,

	["GOSSIP_CLOSED"] = function()
		gossipClicked = {} -- clear all already clicked gossips
	end,
	["GOSSIP_SHOW"] = function()
		if addon.db["autoChooseQuest"] and not IsShiftKeyDown() then
			if nil ~= UnitGUID("npc") and nil ~= addon.db["ignoredQuestNPC"][addon.functions.getIDFromGUID(UnitGUID("npc"))] then return end

			local options = C_GossipInfo.GetOptions()

			local aQuests = C_GossipInfo.GetAvailableQuests()

			if C_GossipInfo.GetNumActiveQuests() > 0 then
				for i, quest in pairs(C_GossipInfo.GetActiveQuests()) do
					if quest.isComplete then C_GossipInfo.SelectActiveQuest(quest.questID) end
				end
			end

			if #aQuests > 0 then
				for i, quest in pairs(aQuests) do
					if addon.db["ignoreTrivialQuests"] and quest.isTrivial then
					-- ignore trivial
					elseif addon.db["ignoreDailyQuests"] and (quest.frequency > 0) then
						-- ignore daily/weekly
					elseif addon.db["ignoreWarbandCompleted"] and C_QuestLog.IsQuestFlaggedCompletedOnAccount(quest.questID) then
						-- ignore warband completed
					else
						C_GossipInfo.SelectAvailableQuest(quest.questID)
					end
				end
			else
				if options and #options > 0 then
					if #options > 1 then
						for _, v in pairs(options) do
							if v.gossipOptionID and addon.db["autogossipID"][v.gossipOptionID] then C_GossipInfo.SelectOption(v.gossipOptionID) end
							if v.flags == 1 and v.gossipOptionID then
								C_GossipInfo.SelectOption(v.gossipOptionID)
								return
							end
						end
					elseif #options == 1 then
						local onlyOption = options[1]
						if onlyOption and onlyOption.gossipOptionID and not gossipClicked[onlyOption.gossipOptionID] then
							gossipClicked[onlyOption.gossipOptionID] = true
							C_GossipInfo.SelectOption(onlyOption.gossipOptionID)
						end
					end
				end
			end
		end
	end,

	["LFG_ROLE_CHECK_SHOW"] = function()
		if addon.db["groupfinderSkipRoleSelect"] and UnitInParty("player") then skipRolecheck() end
	end,
	["LOOT_READY"] = function()
		if addon.db["autoQuickLoot"] then
			local requireShift = addon.db["autoQuickLootWithShift"]
			if (requireShift and IsShiftKeyDown()) or (not requireShift and not IsShiftKeyDown()) then
				for i = 1, GetNumLootItems() do
					C_Timer.After(0.1, function() LootSlot(i) end)
				end
			end
		end
	end,
	["ITEM_INTERACTION_ITEM_SELECTION_UPDATED"] = function(arg1)
		if not ItemInteractionFrame or not ItemInteractionFrame:IsShown() then return end
		if not EnhanceQoLInstantCatalyst then return end
		EnhanceQoLInstantCatalyst:SetEnabled(false)
		EnhanceQoLInstantCatalyst.icon:SetDesaturated(true)
		if arg1 ~= nil then
			local item
			if arg1.bagID and arg1.slotIndex then
				item = ItemLocation:CreateFromBagAndSlot(arg1.bagID, arg1.slotIndex)
			elseif arg1.equipmentSlotIndex then
				item = ItemLocation:CreateFromEquipmentSlot(arg1.equipmentSlotIndex)
			end
			if not item then return end
			local conversionCost = C_ItemInteraction.GetItemConversionCurrencyCost(item)
			if not conversionCost then return end
			if conversionCost.amount > 0 and conversionCost.currencyID ~= 0 then
				local cInfo = C_CurrencyInfo.GetCurrencyInfo(conversionCost.currencyID)
				if not cInfo then return end
				if cInfo.quantity == 0 then return end
			end
			EnhanceQoLInstantCatalyst:SetEnabled(true)
			EnhanceQoLInstantCatalyst.icon:SetDesaturated(false)
		end
	end,
	["DUEL_REQUESTED"] = function()
		if addon.db["blockDuelRequests"] then
			CancelDuel()
			StaticPopup_Hide("DUEL_REQUESTED")
		end
	end,
	["PET_BATTLE_PVP_DUEL_REQUESTED"] = function()
		if addon.db["blockPetBattleRequests"] then
			C_PetBattles.CancelPVPDuel()
			StaticPopup_Hide("PET_BATTLE_PVP_DUEL_REQUESTED")
		end
	end,
	["INVENTORY_SEARCH_UPDATE"] = function()
		if addon.db["showBagFilterMenu"] then
			C_Timer.After(0, function()
				addon.functions.updateBags(ContainerFrameCombinedBags)
				for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
					addon.functions.updateBags(frame)
				end
				if _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end
			end)
		end
	end,
	["PARTY_INVITE_REQUEST"] = function(unitName, arg2, arg3, arg4, arg5, arg6, unitID, arg8)
		if addon.db["autoAcceptGroupInvite"] then
			if addon.db["autoAcceptGroupInviteGuildOnly"] then
				local gMember = GetNumGuildMembers()
				if gMember then
					for i = 1, gMember do
						local name = GetGuildRosterInfo(i)
						if name == unitName then
							AcceptGroup()
							StaticPopup_Hide("PARTY_INVITE")
							return
						end
					end
				end
			end
			if addon.db["autoAcceptGroupInviteFriendOnly"] then
				if C_BattleNet.GetGameAccountInfoByGUID(unitID) then
					AcceptGroup()
					StaticPopup_Hide("PARTY_INVITE")
					return
				end
				for i = 1, C_FriendList.GetNumFriends() do
					local friendInfo = C_FriendList.GetFriendInfoByIndex(i)
					if friendInfo.guid == unitID then
						AcceptGroup()
						StaticPopup_Hide("PARTY_INVITE")
						return
					end
				end
			end
			if not addon.db["autoAcceptGroupInviteGuildOnly"] and not addon.db["autoAcceptGroupInviteFriendOnly"] then
				AcceptGroup()
				StaticPopup_Hide("PARTY_INVITE")
				return
			end
		end
		if addon.db["blockPartyInvites"] then
			DeclineGroup()
			StaticPopup_Hide("PARTY_INVITE")
		end
	end,
	["PLAYER_INTERACTION_MANAGER_FRAME_SHOW"] = function(arg1)
		if arg1 == 53 and addon.db["openCharframeOnUpgrade"] then
			if CharacterFrame:IsShown() == false then ToggleCharacter("PaperDollFrame") end
		end
	end,
	["PLAYER_LOGIN"] = function()
		if addon.db["enableMinimapButtonBin"] then addon.functions.toggleButtonSink() end
		if addon.db["actionBarAnchorEnabled"] then RefreshAllActionBarAnchors() end
		addon.variables.unitSpec = C_SpecializationInfo.GetSpecialization()
		if addon.variables.unitSpec then
			local specId, specName = C_SpecializationInfo.GetSpecializationInfo(addon.variables.unitSpec)
			addon.variables.unitSpecName = specName
			addon.variables.unitRole = GetSpecializationRole(addon.variables.unitSpec)
			addon.variables.unitSpecId = specId
		end

		if addon.db["moneyTracker"] then
			addon.db["moneyTracker"][UnitGUID("player")] = {
				name = UnitName("player"),
				realm = GetRealmName(),
				money = GetMoney(),
				class = select(2, UnitClass("player")),
			}
		end
		addon.db["warbandGold"] = C_Bank.FetchDepositedMoney(Enum.BankType.Account)
		if addon.ChatIM then addon.ChatIM:BuildSoundTable() end

		-- Timerunner cleanup: remove Durability stream from all DataPanels
		if addon.functions and addon.functions.IsTimerunner and addon.functions.IsTimerunner() then
			if addon.DataPanel and addon.DataPanel.List and addon.DataPanel.RemoveStream then
				local panels = addon.DataPanel.List()
				for id, streams in pairs(panels or {}) do
					for _, s in ipairs(streams or {}) do
						if s == "durability" then pcall(function() addon.DataPanel.RemoveStream(id, "durability") end) end
					end
				end
			end
		end
		if addon.functions.IsTimerunner() then addon.functions.addToTree(nil, {
			value = "events",
			text = EVENTS_LABEL or L["Events"] or "Events",
		}) end
	end,
	["PLAYER_MONEY"] = function()
		if addon.db["moneyTracker"] and addon.db["moneyTracker"][UnitGUID("player")] and addon.db["moneyTracker"][UnitGUID("player")]["money"] then
			addon.db["moneyTracker"][UnitGUID("player")]["money"] = GetMoney()
		end
	end,
	["ACCOUNT_MONEY"] = function() addon.db["warbandGold"] = C_Bank.FetchDepositedMoney(Enum.BankType.Account) end,
	["PLAYER_REGEN_ENABLED"] = function()
		if addon.variables then
			if addon.variables.pendingDynamicFlightBar ~= nil then addon.functions.toggleDynamicFlightBar(addon.variables.pendingDynamicFlightBar) end
			if addon.variables.pendingActionBarAnchorRefresh then
				addon.variables.pendingActionBarAnchorRefresh = nil
				RefreshAllActionBarAnchors()
			end
			if addon.variables.pendingPartyFrameScale then
				addon.variables.pendingPartyFrameScale = nil
				addon.functions.updatePartyFrameScale()
			end
			if addon.variables.pendingPartyFrameTitle ~= nil then
				local pending = addon.variables.pendingPartyFrameTitle
				addon.variables.pendingPartyFrameTitle = nil
				addon.functions.togglePartyFrameTitle(pending)
			end
		end
	end,
	["QUEST_COMPLETE"] = function()
		if addon.db["autoChooseQuest"] and not IsShiftKeyDown() then
			local numQuestRewards = GetNumQuestChoices()
			if numQuestRewards > 1 then
			elseif numQuestRewards == 1 then
				GetQuestReward(1)
			else
				GetQuestReward()
			end
		end
	end,
	["QUEST_DATA_LOAD_RESULT"] = function(arg1)
		if arg1 and addon.variables.acceptQuestID[arg1] and addon.db["autoChooseQuest"] then
			if nil ~= UnitGUID("npc") and nil ~= addon.db["ignoredQuestNPC"][addon.functions.getIDFromGUID(UnitGUID("npc"))] then return end
			if addon.db["ignoreDailyQuests"] and addon.functions.IsQuestRepeatableType(arg1) then return end
			if addon.db["ignoreTrivialQuests"] and C_QuestLog.IsQuestTrivial(arg1) then return end
			if addon.db["ignoreWarbandCompleted"] and C_QuestLog.IsQuestFlaggedCompletedOnAccount(arg1) then return end

			AcceptQuest()
			if QuestFrame:IsShown() then QuestFrame:Hide() end -- Sometimes the frame is still stuck - hide it forcefully than
		end
	end,
	["QUEST_DETAIL"] = function()
		if addon.db["autoChooseQuest"] and not IsShiftKeyDown() then
			if nil ~= UnitGUID("npc") and nil ~= addon.db["ignoredQuestNPC"][addon.functions.getIDFromGUID(UnitGUID("npc"))] then return end

			local id = GetQuestID()
			addon.variables.acceptQuestID[id] = true
			C_QuestLog.RequestLoadQuestByID(id)
		end
	end,
	["QUEST_GREETING"] = function()
		if addon.db["autoChooseQuest"] and not IsShiftKeyDown() then
			if nil ~= UnitGUID("npc") and nil ~= addon.db["ignoredQuestNPC"][addon.functions.getIDFromGUID(UnitGUID("npc"))] then return end
			for i = 1, GetNumAvailableQuests() do
				if addon.db["ignoreTrivialQuests"] and IsAvailableQuestTrivial(i) then
				else
					SelectAvailableQuest(i)
				end
			end
			for i = 1, GetNumActiveQuests() do
				if select(2, GetActiveTitle(i)) then SelectActiveQuest(i) end
			end
		end
	end,
	["QUEST_PROGRESS"] = function()
		if addon.db["autoChooseQuest"] and not IsShiftKeyDown() and IsQuestCompletable() then CompleteQuest() end
	end,
	["AUCTION_HOUSE_SHOW"] = function()
		if addon.db["closeBagsOnAuctionHouse"] then CloseAllBags() end
		if addon.db["persistAuctionHouseFilter"] then
			if not AuctionHouseFrame.SearchBar.FilterButton.eqolHooked then
				hooksecurefunc(AuctionHouseFrame.SearchBar.FilterButton, "Reset", function(self)
					if not addon.db["persistAuctionHouseFilter"] or not addon.variables.safedAuctionFilters then
					else
						if addon.variables.safedAuctionFilters then AuctionHouseFrame.SearchBar.FilterButton.filters = addon.variables.safedAuctionFilters end
						AuctionHouseFrame.SearchBar.FilterButton.minLevel = addon.variables.safedAuctionMinlevel
						AuctionHouseFrame.SearchBar.FilterButton.maxLevel = addon.variables.safedAuctionMaxlevel
						addon.variables.safedAuctionFilters = nil
						self.ClearFiltersButton:Show()
						-- Ensure the Current Expansion filter remains enforced when both options are enabled
						if addon.db["alwaysUserCurExpAuctionHouse"] then
							AuctionHouseFrame.SearchBar.FilterButton.filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
							AuctionHouseFrame.SearchBar:UpdateClearFiltersButton()
						end
					end
				end)
				AuctionHouseFrame.SearchBar.FilterButton.eqolHooked = true
			end
		end
		if addon.db["alwaysUserCurExpAuctionHouse"] then
			C_Timer.After(0, function()
				AuctionHouseFrame.SearchBar.FilterButton.filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
				AuctionHouseFrame.SearchBar:UpdateClearFiltersButton()
			end)
		end
	end,
	["AUCTION_HOUSE_CLOSED"] = function()
		if not addon.db["persistAuctionHouseFilter"] then return end
		if AuctionHouseFrame.SearchBar.FilterButton.ClearFiltersButton:IsShown() then
			addon.variables.safedAuctionFilters = AuctionHouseFrame.SearchBar.FilterButton.filters
			addon.variables.safedAuctionMinlevel = AuctionHouseFrame.SearchBar.FilterButton.minLevel
			addon.variables.safedAuctionMaxlevel = AuctionHouseFrame.SearchBar.FilterButton.maxLevel
		else
			addon.variables.safedAuctionFilters = nil
		end
	end,
	["CINEMATIC_START"] = function()
		if addon.db["autoCancelCinematic"] then
			if CinematicFrame.isRealCinematic then
				StopCinematic()
			elseif CanCancelScene() then
				CancelScene()
			end
		end
	end,
	["PLAY_MOVIE"] = function()
		if addon.db["autoCancelCinematic"] then MovieFrame:Hide() end
	end,
}

local function registerEvents(frame)
	for event in pairs(eventHandlers) do
		frame:RegisterEvent(event)
	end
end

local function eventHandler(self, event, ...)
	if eventHandlers[event] then eventHandlers[event](...) end
end

registerEvents(frameLoad)
frameLoad:SetScript("OnEvent", eventHandler)
