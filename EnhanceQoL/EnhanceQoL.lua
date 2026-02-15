-- luacheck: globals DefaultCompactUnitFrameSetup CompactUnitFrame_UpdateAuras CompactUnitFrame_UpdateName UnitTokenFromGUID C_Bank CompactRaidFrameContainer
-- luacheck: globals HUD_EDIT_MODE_MINIMAP_LABEL
-- luacheck: globals Menu GameTooltip_SetTitle GameTooltip_AddNormalLine EnhanceQoL
-- luacheck: globals GenericTraitUI_LoadUI GenericTraitFrame
-- luacheck: globals CancelDuel DeclineGroup C_PetBattles
-- luacheck: globals ExpansionLandingPage ExpansionLandingPageMinimapButton ShowGarrisonLandingPage GarrisonLandingPage GarrisonLandingPage_Toggle GarrisonLandingPageMinimapButton CovenantSanctumFrame CovenantSanctumFrame_LoadUI EasyMenu
-- luacheck: globals ActionButton_UpdateRangeIndicator MAINMENU_BUTTON PlayerCastingBarFrame TargetFrameSpellBar FocusFrameSpellBar ChatBubbleFont
-- luacheck: globals NUM_CHAT_WINDOWS ChatFrame1Tab ChatFrame2 ChatFrame2Tab FCF_SetWindowName FCFDock_UpdateTabs GENERAL_CHAT_DOCK EventUtil ClassTrainerFrame ClassTrainerTrainButton ClassTrainerFrameMoneyBg
local addonName, addon = ...

local LDB = LibStub("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0")
local AceGUI = LibStub("AceGUI-3.0")

addon.AceGUI = AceGUI
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")

addon.functions = addon.functions or {}
addon.ActionBarLabels = addon.ActionBarLabels or {}
local ActionBarLabels = addon.ActionBarLabels

addon.constants = addon.constants or {}

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

local COOLDOWN_VIEWER_FRAMES = {
	"EssentialCooldownViewer",
	"UtilityCooldownViewer",
	"BuffBarCooldownViewer",
	"BuffIconCooldownViewer",
}
addon.constants.COOLDOWN_VIEWER_FRAMES = COOLDOWN_VIEWER_FRAMES

local COOLDOWN_VIEWER_VISIBILITY_MODES = {
	IN_COMBAT = "IN_COMBAT",
	WHILE_MOUNTED = "WHILE_MOUNTED",
	WHILE_NOT_MOUNTED = "WHILE_NOT_MOUNTED",
	SKYRIDING_ACTIVE = "SKYRIDING_ACTIVE",
	SKYRIDING_INACTIVE = "SKYRIDING_INACTIVE",
	MOUSEOVER = "MOUSEOVER",
	PLAYER_HAS_TARGET = "PLAYER_HAS_TARGET",
	PLAYER_CASTING = "PLAYER_CASTING",
	PLAYER_IN_GROUP = "PLAYER_IN_GROUP",
}
addon.constants.COOLDOWN_VIEWER_VISIBILITY_MODES = COOLDOWN_VIEWER_VISIBILITY_MODES

local SPELL_ACTIVATION_OVERLAY_FRAME_NAME = "SpellActivationOverlayFrame"
addon.constants.SPELL_ACTIVATION_OVERLAY_FRAME_NAME = SPELL_ACTIVATION_OVERLAY_FRAME_NAME
local SPELL_ACTIVATION_OVERLAY_VISIBILITY_KEYS = {
	[COOLDOWN_VIEWER_VISIBILITY_MODES.WHILE_MOUNTED] = true,
	[COOLDOWN_VIEWER_VISIBILITY_MODES.WHILE_NOT_MOUNTED] = true,
	[COOLDOWN_VIEWER_VISIBILITY_MODES.SKYRIDING_ACTIVE] = true,
	[COOLDOWN_VIEWER_VISIBILITY_MODES.SKYRIDING_INACTIVE] = true,
	[COOLDOWN_VIEWER_VISIBILITY_MODES.PLAYER_CASTING] = true,
	[COOLDOWN_VIEWER_VISIBILITY_MODES.PLAYER_HAS_TARGET] = true,
}
addon.constants.SPELL_ACTIVATION_OVERLAY_VISIBILITY_KEYS = SPELL_ACTIVATION_OVERLAY_VISIBILITY_KEYS

local DEFAULT_BUTTON_SINK_COLUMNS = 4

local DEFAULT_ACTION_BUTTON_COUNT = _G.NUM_ACTIONBAR_BUTTONS or 12
local PET_ACTION_BUTTON_COUNT = _G.NUM_PET_ACTION_SLOTS or 10
local STANCE_ACTION_BUTTON_COUNT = _G.NUM_STANCE_SLOTS or _G.NUM_SHAPESHIFT_SLOTS or 10

local ACTION_BAR_FRAME_ALIASES = {
	PetActionBar = { "PetActionBarFrame" },
	StanceBar = { "StanceBarFrame" },
}

local function ResolveActionBarFrame(barName)
	if type(barName) ~= "string" or barName == "" then return nil end
	local frame = _G[barName]
	if frame then return frame end
	local aliases = ACTION_BAR_FRAME_ALIASES[barName]
	if not aliases then return nil end
	for _, alias in ipairs(aliases) do
		frame = _G[alias]
		if frame then return frame end
	end
	return nil
end

local function GetActionBarButtonPrefix(barName)
	if not barName then return nil, 0 end
	if barName == "MainMenuBar" or barName == "MainActionBar" then return "ActionButton", DEFAULT_ACTION_BUTTON_COUNT end
	if barName == "PetActionBar" or barName == "PetActionBarFrame" then return "PetActionButton", PET_ACTION_BUTTON_COUNT end
	if barName == "StanceBar" or barName == "StanceBarFrame" then return "StanceButton", STANCE_ACTION_BUTTON_COUNT end
	return barName .. "Button", DEFAULT_ACTION_BUTTON_COUNT
end

local function ForEachActionButton(callback)
	if type(callback) ~= "function" then return end
	local list = addon.variables and addon.variables.actionBarNames
	if not list then return end
	local seen = {}
	for _, info in ipairs(list) do
		local prefix, count = GetActionBarButtonPrefix(info.name)
		if prefix and count then
			for i = 1, count do
				local button = _G[prefix .. i]
				if button and not seen[button] then
					seen[button] = true
					if not button.EQOL_ActionBarName then button.EQOL_ActionBarName = info.name end
					callback(button, info, i)
				end
			end
		end
	end
end

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
	local enabled = addon.db and addon.db.actionBarAnchorEnabled
	if not enabled then
		if addon.variables then addon.variables.pendingActionBarAnchorRefresh = nil end
		return
	end

	if InCombatLockdown and InCombatLockdown() then
		addon.variables = addon.variables or {}
		addon.variables.pendingActionBarAnchorRefresh = true
		return
	end

	if addon.variables then addon.variables.pendingActionBarAnchorRefresh = nil end
	addon.variables.actionBarAnchorDefaults = addon.variables.actionBarAnchorDefaults or {}
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

		ApplyActionBarAnchor(i, stored)
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
	PLAYER_CASTING = {
		key = "PLAYER_CASTING",
		label = L["visibilityRule_playerCasting"] or "Player is casting",
		description = L["visibilityRule_playerCasting_desc"],
		appliesTo = { actionbar = true, frame = true },
		unitRequirement = "player",
		order = 35,
	},
	PLAYER_MOUNTED = {
		key = "PLAYER_MOUNTED",
		label = L["visibilityRule_playerMounted"] or "Mounted",
		description = L["visibilityRule_playerMounted_desc"],
		appliesTo = { actionbar = true, frame = true },
		unitRequirement = "player",
		order = 36,
	},
	PLAYER_NOT_MOUNTED = {
		key = "PLAYER_NOT_MOUNTED",
		label = L["visibilityRule_playerNotMounted"] or "Not mounted",
		description = L["visibilityRule_playerNotMounted_desc"],
		appliesTo = { actionbar = true, frame = true },
		unitRequirement = "player",
		order = 37,
	},
	PLAYER_HAS_TARGET = {
		key = "PLAYER_HAS_TARGET",
		label = L["visibilityRule_playerHasTarget"] or "When I have a target",
		description = L["visibilityRule_playerHasTarget_desc"],
		appliesTo = { frame = true },
		unitRequirement = "player",
		order = 45,
	},
	PLAYER_IN_GROUP = {
		key = "PLAYER_IN_GROUP",
		label = L["visibilityRule_inGroup"] or "In party/raid",
		description = L["visibilityRule_inGroup_desc"],
		appliesTo = { actionbar = true, frame = true },
		unitRequirement = "player",
		order = 46,
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
	SKYRIDING_INACTIVE = {
		key = "SKYRIDING_INACTIVE",
		label = L["visibilityRule_hideSkyriding"] or "Hide while skyriding",
		description = L["visibilityRule_hideSkyriding_desc"],
		appliesTo = { actionbar = true },
		order = 26,
	},
	ALWAYS_HIDDEN = {
		key = "ALWAYS_HIDDEN",
		label = L["visibilityRule_alwaysHidden"] or "Always hidden",
		description = L["visibilityRule_alwaysHidden_desc"],
		appliesTo = { actionbar = true, frame = true },
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

addon.variables = addon.variables or {}
addon.variables.frameVisibilityOverrides = addon.variables.frameVisibilityOverrides or {}

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

local function NormalizeUnitFrameVisibilityConfig(varName, incoming, opts)
	local source = incoming
	local skipSave = opts and opts.skipSave
	local ignoreOverride = opts and opts.ignoreOverride
	if source == nil then
		if not ignoreOverride and addon.variables.frameVisibilityOverrides and addon.variables.frameVisibilityOverrides[varName] then
			source = addon.variables.frameVisibilityOverrides[varName]
			skipSave = true
		elseif addon.db then
			source = addon.db[varName]
		end
	end
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

	if not skipSave and addon.db and varName then addon.db[varName] = config end
	return config
end
addon.functions.NormalizeUnitFrameVisibilityConfig = NormalizeUnitFrameVisibilityConfig

local function SetFrameVisibilityOverride(varName, config)
	if not varName then return nil end
	addon.variables.frameVisibilityOverrides = addon.variables.frameVisibilityOverrides or {}
	if config == nil then
		addon.variables.frameVisibilityOverrides[varName] = nil
		return nil
	end
	local normalized = NormalizeUnitFrameVisibilityConfig(varName, config, { skipSave = true, ignoreOverride = true })
	addon.variables.frameVisibilityOverrides[varName] = normalized
	return normalized
end
addon.functions.SetFrameVisibilityOverride = SetFrameVisibilityOverride

local function HasFrameVisibilityOverride(varName) return varName ~= nil and addon.variables.frameVisibilityOverrides ~= nil and addon.variables.frameVisibilityOverrides[varName] ~= nil end
addon.functions.HasFrameVisibilityOverride = HasFrameVisibilityOverride

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

local function StopFrameFade(target)
	local group = target and target.EQOL_FadeGroup
	if group and group.Stop then group:Stop() end
	if group then group.targetAlpha = nil end
end

local function ApplyAlphaToRegion(target, alpha, _useFade)
	if not target or not target.SetAlpha then return end
	-- Keep visibility alpha behavior, but apply immediately (no animated fade).
	StopFrameFade(target)
	target:SetAlpha(alpha)
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

local BOSS_FRAME_CONTAINER_NAME = "BossTargetFrameContainer"
local bossFrameForceHidden
local bossFramePrevSelectionAlpha
local bossFrameAlphaHooked

local function IsBossFrameContainer(frame)
	if not frame then return false end
	if frame == _G[BOSS_FRAME_CONTAINER_NAME] then return true end
	if frame.GetName and frame:GetName() == BOSS_FRAME_CONTAINER_NAME then return true end
	return false
end

local function EnsureBossFrameHideHook(container)
	if bossFrameAlphaHooked or not container or not hooksecurefunc then return end
	bossFrameAlphaHooked = true
	hooksecurefunc(container, "SetAlpha", function(self)
		if bossFrameForceHidden and self.GetAlpha and self:GetAlpha() ~= 0 then self:SetAlpha(0) end
	end)
end

local function SetBossFrameHidden(shouldHide)
	local container = _G[BOSS_FRAME_CONTAINER_NAME]
	if not container or not container.SetAlpha then return end

	EnsureBossFrameHideHook(container)

	local selection = container.Selection
	local hide = shouldHide and true or false

	if hide then
		if not bossFrameForceHidden then
			if selection and selection.GetAlpha then bossFramePrevSelectionAlpha = selection:GetAlpha() end
		end
		bossFrameForceHidden = true
		if container.GetAlpha and container:GetAlpha() ~= 0 then container:SetAlpha(0) end
		if selection and selection.SetAlpha then selection:SetAlpha(0) end
		return
	end

	if container.GetAlpha and container:GetAlpha() ~= 1 then container:SetAlpha(1) end
	if bossFrameForceHidden and selection and selection.SetAlpha then
		local selectionAlpha = bossFramePrevSelectionAlpha
		if selectionAlpha == nil then selectionAlpha = 1 end
		selection:SetAlpha(selectionAlpha)
	end

	bossFrameForceHidden = false
	bossFramePrevSelectionAlpha = nil
end

local UpdateUnitFrameMouseover -- forward declaration

local frameVisibilityContext = {
	inCombat = false,
	hasTarget = false,
	inGroup = false,
	isCasting = false,
	isMounted = false,
}
local frameVisibilityStates = {}
local hookedUnitFrames = {}
local ApplyFrameVisibilityState -- forward declaration
local IsInDruidTravelForm
local EnsureSkyridingStateDriver
local EnsureSpellActivationOverlayWatcher

local function IsPlayerCasting()
	if UnitCastingInfo and UnitCastingInfo("player") then return true end
	if UnitChannelInfo and UnitChannelInfo("player") then return true end
	return false
end

local function IsPlayerMounted()
	if IsMounted and IsMounted() then return true end
	if IsInDruidTravelForm and IsInDruidTravelForm() then return true end
	return false
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
	frameVisibilityContext.isCasting = IsPlayerCasting()
	frameVisibilityContext.isMounted = IsPlayerMounted()
end

local function SafeRegisterUnitEvent(frame, event, ...)
	if not frame or not frame.RegisterUnitEvent or type(event) ~= "string" then return false end
	local ok = pcall(frame.RegisterUnitEvent, frame, event, ...)
	return ok
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

local function RefreshAllFrameVisibilities()
	for _, state in pairs(frameVisibilityStates) do
		ApplyFrameVisibilityState(state)
	end
end
addon.functions.RefreshAllFrameVisibilityAlpha = RefreshAllFrameVisibilities

local function EnsureFrameVisibilityWatcher()
	addon.variables = addon.variables or {}
	if addon.variables.frameVisibilityWatcher then return end

	local watcher = CreateFrame("Frame")
	watcher:SetScript("OnEvent", function(self, event, unit)
		UpdateFrameVisibilityContext()
		RefreshAllFrameVisibilities()
	end)
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
	watcher:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
	watcher:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
	SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_START", "player")
	SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_STOP", "player")
	SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_FAILED", "player")
	SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_INTERRUPTED", "player")
	SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_CHANNEL_START", "player")
	SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_CHANNEL_STOP", "player")
	addon.variables.frameVisibilityWatcher = watcher
	UpdateFrameVisibilityContext()
end

local function clampVisibilityAlpha(value)
	if type(value) ~= "number" then return nil end
	if value < 0 then return 0 end
	if value > 1 then return 1 end
	return value
end

local function getVisibilityFadeAlpha(state)
	if not state then return nil end
	return clampVisibilityAlpha(state.fadeAlpha)
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
	if cfg.PLAYER_CASTING and state.supportsPlayerCastingRule and context.isCasting then return true, "PLAYER_CASTING" end
	if cfg.PLAYER_MOUNTED and state.supportsPlayerMountedRule and context.isMounted then return true, "PLAYER_MOUNTED" end
	if cfg.PLAYER_NOT_MOUNTED and state.supportsPlayerMountedRule and not context.isMounted then return true, "PLAYER_NOT_MOUNTED" end
	if cfg.PLAYER_IN_GROUP and state.supportsGroupRule and context.inGroup then return true, "PLAYER_IN_GROUP" end
	if cfg.MOUSEOVER and state.isMouseOver then return true, "MOUSEOVER" end

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
	if state.isBossFrame then
		local cfg = state.config
		if not cfg or not next(cfg) then
			if state.visible ~= nil then SetBossFrameHidden(false) end
			frameVisibilityStates[state.frame] = nil
			return
		end

		EnsureFrameVisibilityWatcher()
		local shouldShow = EvaluateFrameVisibility(state)
		SetBossFrameHidden(not shouldShow)
		state.visible = shouldShow
		return
	end

	local cfg = state.config
	if not cfg or not next(cfg) then
		if state.visible ~= nil then RestoreUnitFrameVisibility(state.frame, state.cbData) end
		frameVisibilityStates[state.frame] = nil
		return
	end

	if state.driverActive then return end

	EnsureFrameVisibilityWatcher()
	local shouldShow, activeRule = EvaluateFrameVisibility(state)
	local forcedHidden = activeRule == "ALWAYS_HIDDEN" or activeRule == "ALWAYS_HIDE_IN_GROUP"
	local fadeAlpha = getVisibilityFadeAlpha(state)
	if fadeAlpha == nil and addon.functions and addon.functions.GetFrameFadedAlpha then fadeAlpha = addon.functions.GetFrameFadedAlpha() end
	if fadeAlpha == nil then fadeAlpha = 0 end
	local targetAlpha
	if shouldShow then
		targetAlpha = 1
	else
		targetAlpha = fadeAlpha
	end
	if forcedHidden then targetAlpha = 0 end

	local lastAlpha = state.lastAlpha
	if shouldShow then
		if state.visible == true then return end
	else
		if state.visible == false then return end
	end

	ApplyToFrameAndChildren(state, targetAlpha, true)
	state.visible = shouldShow
	state.lastAlpha = targetAlpha
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

local function ClearUnitFrameState(frame, cbData, opts)
	if not frame then return end
	if IsBossFrameContainer(frame) then
		ApplyUnitFrameStateDriver(frame, nil)
		SetBossFrameHidden(false)
		frameVisibilityStates[frame] = nil
		return
	end
	if not (opts and opts.noStateDriver) then ApplyUnitFrameStateDriver(frame, nil) end
	RestoreUnitFrameVisibility(frame, cbData)
	frameVisibilityStates[frame] = nil
end

local function ApplyVisibilityToUnitFrame(frameName, cbData, config, opts)
	if type(frameName) ~= "string" or frameName == "" then return false end
	local frame = _G[frameName]
	if not frame then return false end

	if not config then
		ClearUnitFrameState(frame, cbData, opts)
		return true
	end

	local state = EnsureFrameState(frame, cbData)
	state.config = config
	state.fadeAlpha = clampVisibilityAlpha(opts and opts.fadeAlpha)
	state.isBossFrame = frameName == BOSS_FRAME_CONTAINER_NAME
	local unitToken = cbData.unitToken
	local isPlayerUnit = (unitToken == "player")
	local isTargetUnit = (unitToken == "target")
	state.supportsPlayerTargetRule = isPlayerUnit or isTargetUnit
	state.supportsPlayerCastingRule = isPlayerUnit
	state.supportsPlayerMountedRule = isPlayerUnit
	state.supportsGroupRule = isPlayerUnit

	local driverExpression = BuildUnitFrameDriverExpression(config)
	local usesManualRules = config and (config.MOUSEOVER or config.PLAYER_HAS_TARGET or config.PLAYER_CASTING or config.PLAYER_MOUNTED or config.PLAYER_NOT_MOUNTED or config.PLAYER_IN_GROUP)
	local hasFadeAlpha = type(state.fadeAlpha) == "number"
	local useDriver = driverExpression and not usesManualRules and not (opts and opts.noStateDriver) and not state.isBossFrame and not hasFadeAlpha

	if useDriver then
		state.driverActive = true
		ApplyUnitFrameStateDriver(frame, driverExpression)
		ApplyToFrameAndChildren(state, 1, false)
		return true
	end

	state.driverActive = false
	if not (opts and opts.noStateDriver) or state.isBossFrame then ApplyUnitFrameStateDriver(frame, nil) end

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

	if barName == BOSS_FRAME_CONTAINER_NAME then
		local onlyChildren = cbData.onlyChildren
		local children = {}
		if type(onlyChildren) == "table" then
			local seen = {}
			for _, child in ipairs(onlyChildren) do
				if type(child) == "string" and child ~= "" and not seen[child] then
					local frame = _G[child]
					if frame then
						table.insert(children, frame)
						seen[child] = true
					end
				end
			end
			for _, child in pairs(onlyChildren) do
				if type(child) == "string" and child ~= "" and not seen[child] then
					local frame = _G[child]
					if frame then
						table.insert(children, frame)
						seen[child] = true
					end
				end
			end
		end

		if #children > 0 then
			cbData.children = children
			cbData.revealAllChilds = true
		else
			cbData.children = nil
			cbData.revealAllChilds = nil
		end

		ApplyVisibilityToUnitFrame(barName, cbData, config)
		return
	end

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
end
addon.functions.UpdateUnitFrameMouseover = UpdateUnitFrameMouseover

local function ApplyFrameVisibilityConfig(frameName, cbData, config, opts) return ApplyVisibilityToUnitFrame(frameName, cbData, config, opts) end
addon.functions.ApplyFrameVisibilityConfig = ApplyFrameVisibilityConfig

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

local function IsCooldownViewerEnabled()
	if not C_CVar or not C_CVar.GetCVar then return false end
	addon.variables = addon.variables or {}
	if addon.variables.cooldownViewerEnabledCache ~= nil and not addon.variables.cooldownViewerEnabledDirty then return addon.variables.cooldownViewerEnabledCache end
	local ok, value = pcall(C_CVar.GetCVar, "cooldownViewerEnabled")
	local enabled = ok and tonumber(value) == 1
	addon.variables.cooldownViewerEnabledCache = enabled
	addon.variables.cooldownViewerEnabledDirty = nil
	return enabled
end
addon.functions.IsCooldownViewerEnabled = IsCooldownViewerEnabled

local function normalizeCooldownViewerConfigValue(val, acc)
	acc = acc or {}
	if val == COOLDOWN_VIEWER_VISIBILITY_MODES.IN_COMBAT then acc[COOLDOWN_VIEWER_VISIBILITY_MODES.IN_COMBAT] = true end
	if val == COOLDOWN_VIEWER_VISIBILITY_MODES.WHILE_MOUNTED then acc[COOLDOWN_VIEWER_VISIBILITY_MODES.WHILE_MOUNTED] = true end
	if val == COOLDOWN_VIEWER_VISIBILITY_MODES.WHILE_NOT_MOUNTED then acc[COOLDOWN_VIEWER_VISIBILITY_MODES.WHILE_NOT_MOUNTED] = true end
	if val == COOLDOWN_VIEWER_VISIBILITY_MODES.SKYRIDING_ACTIVE then acc[COOLDOWN_VIEWER_VISIBILITY_MODES.SKYRIDING_ACTIVE] = true end
	if val == COOLDOWN_VIEWER_VISIBILITY_MODES.SKYRIDING_INACTIVE then acc[COOLDOWN_VIEWER_VISIBILITY_MODES.SKYRIDING_INACTIVE] = true end
	if val == COOLDOWN_VIEWER_VISIBILITY_MODES.MOUSEOVER then acc[COOLDOWN_VIEWER_VISIBILITY_MODES.MOUSEOVER] = true end
	if val == COOLDOWN_VIEWER_VISIBILITY_MODES.PLAYER_HAS_TARGET then acc[COOLDOWN_VIEWER_VISIBILITY_MODES.PLAYER_HAS_TARGET] = true end
	if val == COOLDOWN_VIEWER_VISIBILITY_MODES.PLAYER_CASTING then acc[COOLDOWN_VIEWER_VISIBILITY_MODES.PLAYER_CASTING] = true end
	if val == COOLDOWN_VIEWER_VISIBILITY_MODES.PLAYER_IN_GROUP then acc[COOLDOWN_VIEWER_VISIBILITY_MODES.PLAYER_IN_GROUP] = true end
	-- Legacy mapping: "hide while mounted" -> show while not mounted
	if val == "HIDE_WHILE_MOUNTED" then acc[COOLDOWN_VIEWER_VISIBILITY_MODES.WHILE_NOT_MOUNTED] = true end
	if val == "HIDE_IN_COMBAT" then acc[COOLDOWN_VIEWER_VISIBILITY_MODES.IN_COMBAT] = nil end
	return acc
end

local function sanitizeCooldownViewerConfig(cfg)
	if type(cfg) == "table" then
		local result
		for key, value in pairs(cfg) do
			if value == true then result = normalizeCooldownViewerConfigValue(key, result or {}) end
		end
		return result
	end
	if type(cfg) == "string" then return normalizeCooldownViewerConfigValue(cfg, {}) end
	return nil
end

local function HasCooldownViewerVisibilityConfig()
	local db = addon.db and addon.db.cooldownViewerVisibility
	if type(db) ~= "table" then return false end
	for _, cfg in pairs(db) do
		local sanitized = sanitizeCooldownViewerConfig(cfg)
		if sanitized and next(sanitized) then return true end
	end
	return false
end

local DRUID_TRAVEL_FORM_SPELL_IDS = {
	[783] = true, -- Travel Form
	[1066] = true, -- Aquatic Form
	[33943] = true, -- Flight Form
	[40120] = true, -- Swift Flight Form
	[210053] = true, -- Mount Form (Stag)
}

IsInDruidTravelForm = function()
	local class = addon.variables and addon.variables.unitClass
	if not class and UnitClass then
		local _, eng = UnitClass("player")
		class = eng
	end
	if not class or class ~= "DRUID" then return false end
	if not GetShapeshiftForm then return false end
	local form = GetShapeshiftForm()
	if not form or form == 0 then return false end
	if GetShapeshiftFormID then
		local formID = GetShapeshiftFormID()
		if formID == DRUID_TRAVEL_FORM or formID == DRUID_ACQUATIC_FORM or formID == DRUID_FLIGHT_FORM or formID == 29 then return true end
	end
	local spellID = select(4, GetShapeshiftFormInfo(form))
	if spellID and DRUID_TRAVEL_FORM_SPELL_IDS[spellID] then return true end
	-- Fallback: Travel Form is always slot 3 in the druid shapeshift list.
	return form == 3
end

local function computeCooldownViewerTargetAlpha(cfg, state)
	if not cfg or not next(cfg) then return 1 end

	local mounted = (IsMounted and IsMounted()) or IsInDruidTravelForm()
	local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))

	local hovered = state and state.hovered
	local sharedHover = addon.db and addon.db.cooldownViewerSharedHover
	local viewerStates = addon.variables and addon.variables.cooldownViewerStates
	if not hovered and sharedHover and viewerStates then
		for _, otherState in pairs(addon.variables.cooldownViewerStates) do
			if otherState.hovered then
				hovered = true
				break
			end
		end
	end

	local hasTarget = UnitExists and UnitExists("target")
	local isCasting = IsPlayerCasting()
	local inGroup = IsInGroup and IsInGroup() and true or false
	local isSkyriding = addon.variables and addon.variables.isPlayerSkyriding
	local fadedAlpha = (addon.functions and addon.functions.GetCooldownViewerFadedAlpha and addon.functions.GetCooldownViewerFadedAlpha()) or 0
	local hideSkyriding = cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.SKYRIDING_INACTIVE] == true
	local hasShowRules = cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.IN_COMBAT]
		or cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.WHILE_MOUNTED]
		or cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.WHILE_NOT_MOUNTED]
		or cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.SKYRIDING_ACTIVE]
		or cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.MOUSEOVER]
		or cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.PLAYER_HAS_TARGET]
		or cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.PLAYER_CASTING]
		or cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.PLAYER_IN_GROUP]

	if hideSkyriding and isSkyriding then return fadedAlpha end
	if not hasShowRules then return 1 end

	local shouldShow = false
	if cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.IN_COMBAT] and inCombat then shouldShow = true end
	if cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.WHILE_MOUNTED] and mounted then shouldShow = true end
	if cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.WHILE_NOT_MOUNTED] and not mounted then shouldShow = true end
	if cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.SKYRIDING_ACTIVE] and isSkyriding then shouldShow = true end
	if cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.MOUSEOVER] and hovered then shouldShow = true end
	if cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.PLAYER_HAS_TARGET] and hasTarget then shouldShow = true end
	if cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.PLAYER_CASTING] and isCasting then shouldShow = true end
	if cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.PLAYER_IN_GROUP] and inGroup then shouldShow = true end

	if shouldShow then return 1 end
	return fadedAlpha
end

local function IsCooldownViewerInEditMode()
	if addon.variables and addon.variables.cooldownViewerEditMode ~= nil then return addon.variables.cooldownViewerEditMode end
	if addon.EditMode and addon.EditMode.IsInEditMode then
		local ok, result = pcall(addon.EditMode.IsInEditMode, addon.EditMode)
		if ok then return result end
	end
	return false
end

local function applyCooldownViewerMode(frameName, cfg)
	local frame = frameName and _G[frameName]
	if not frame then return false end

	local hasActiveConfig = false
	if type(cfg) == "table" then
		for _, v in pairs(cfg) do
			if v then
				hasActiveConfig = true
				break
			end
		end
	end

	local hoverEnabled = hasActiveConfig and cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.MOUSEOVER] == true

	addon.variables = addon.variables or {}
	addon.variables.cooldownViewerStates = addon.variables.cooldownViewerStates or {}
	local states = addon.variables.cooldownViewerStates

	local state = states[frame]

	if not hasActiveConfig and not state then return true end

	if not state then
		state = {
			frame = frame,
			frameName = frameName,

			hovered = false,
			applied = false,

			hoverEnabled = false,
			hoverPollInitialized = false,
			hoverPollRunning = false,

			prevOnUpdate = nil,
			onUpdateWrapper = nil,
			hoverHandlers = nil,
		}
		states[frame] = state
	end

	state.hoverEnabled = hoverEnabled

	if hoverEnabled and not state.hoverPollInitialized and frame.HookScript then
		state.hoverPollInitialized = true
		state.hoverHooked = false

		local function setHovered(v)
			if state.hovered == v then return end
			state.hovered = v
			if addon.functions.ApplyCooldownViewerVisibility then addon.functions.ApplyCooldownViewerVisibility() end
		end

		local function hoverUpdate(self, elapsed)
			self._eqolHoverElapsed = (self._eqolHoverElapsed or 0) + (elapsed or 0)
			if self._eqolHoverElapsed < 0.05 then return end -- ~20 Hz
			self._eqolHoverElapsed = 0
			setHovered(MouseIsOver(self))
		end

		local function startHoverPoll(self)
			if not state.hoverEnabled then return end
			if state.hoverPollRunning then return end
			state.hoverPollRunning = true

			self._eqolHoverElapsed = 0

			if not state.hoverHooked then
				self:HookScript("OnUpdate", hoverUpdate)
				state.hoverHooked = true
			end
		end

		local function stopHoverPoll(self)
			if not state.hoverPollRunning then return end
			state.hoverPollRunning = false

			setHovered(false)
		end

		state.hoverHandlers = { start = startHoverPoll, stop = stopHoverPoll }

		frame:HookScript("OnShow", startHoverPoll)
		frame:HookScript("OnHide", stopHoverPoll)

		-- Wenn er gerade sichtbar ist: direkt starten
		if frame.IsShown and frame:IsShown() then startHoverPoll(frame) end
	end

	-- Sicherstellen: ohne hoverEnabled wird NIE ein OnUpdate gesetzt.
	if state.hoverHandlers then
		if hoverEnabled then
			if frame.IsShown and frame:IsShown() then
				state.hoverHandlers.start(frame)
			else
				state.hoverHandlers.stop(frame)
			end
		else
			state.hoverHandlers.stop(frame)
			state.hovered = false
		end
	end

	-- Wenn nichts aktiv ist: Defaults herstellen, Polling stoppen und ggf. State komplett entfernen.
	if not hasActiveConfig then
		if state.hoverHandlers then state.hoverHandlers.stop(frame) end

		if state.applied and frame.GetAlpha and frame.SetAlpha and frame:GetAlpha() ~= 1 then frame:SetAlpha(1) end

		state.applied = false
		state.hoverEnabled = false
		state.hovered = false

		-- Wenn wir nie Hooks installiert haben, können wir den State komplett vergessen.
		-- (WICHTIG: wenn hoverPollInitialized true war, NICHT löschen, sonst hängen die Hook-Closures am alten state.)
		if not state.hoverPollInitialized then states[frame] = nil end

		return true
	end

	-- Ab hier: aktive Config -> normales Verhalten
	local targetAlpha = computeCooldownViewerTargetAlpha(cfg, state)
	if IsCooldownViewerInEditMode() then targetAlpha = 1 end
	if frame.GetAlpha and frame.SetAlpha then
		if issecretvalue(targetAlpha) or issecretvalue(frame:GetAlpha()) then
			frame:SetAlpha(targetAlpha)
		elseif frame:GetAlpha() ~= targetAlpha then
			frame:SetAlpha(targetAlpha)
		end
	end

	state.applied = true
	return true
end

local function ensureCooldownViewerDb()
	addon.db = addon.db or {}
	if type(addon.db.cooldownViewerVisibility) ~= "table" then addon.db.cooldownViewerVisibility = {} end
	return addon.db.cooldownViewerVisibility
end

function addon.functions.GetCooldownViewerVisibility(frameName)
	local db = ensureCooldownViewerDb()
	local sanitized = sanitizeCooldownViewerConfig(db[frameName])
	if not sanitized then return nil end
	local copy = {}
	for k, v in pairs(sanitized) do
		if v == true then copy[k] = true end
	end
	return copy
end

function addon.functions.SetCooldownViewerVisibility(frameName, key, shouldSelect)
	local db = ensureCooldownViewerDb()
	local current = sanitizeCooldownViewerConfig(db[frameName]) or {}
	if shouldSelect then
		current = normalizeCooldownViewerConfigValue(key, current)
	else
		current[key] = nil
	end
	if current and next(current) then
		db[frameName] = current
	else
		db[frameName] = nil
	end
	if addon.functions.EnsureCooldownViewerWatcher then addon.functions.EnsureCooldownViewerWatcher() end
	if addon.functions.ApplyCooldownViewerVisibility then addon.functions.ApplyCooldownViewerVisibility() end
end

local function scheduleCooldownViewerReapply()
	addon.variables = addon.variables or {}
	if addon.variables.cooldownViewerReapplyPending then return end
	if not C_Timer or not C_Timer.After then return end

	local attempts = (addon.variables.cooldownViewerRetryCount or 0) + 1
	addon.variables.cooldownViewerRetryCount = attempts
	if attempts > 10 then return end

	addon.variables.cooldownViewerReapplyPending = true
	C_Timer.After(1, function()
		addon.variables.cooldownViewerReapplyPending = nil
		if addon.functions.ApplyCooldownViewerVisibility then addon.functions.ApplyCooldownViewerVisibility() end
	end)
end

function addon.functions.ApplyCooldownViewerVisibility()
	addon.db = addon.db or {}
	addon.variables = addon.variables or {}
	local enabled = IsCooldownViewerEnabled()
	local missingFrame = false

	for _, frameName in ipairs(COOLDOWN_VIEWER_FRAMES) do
		local cfg = addon.functions.GetCooldownViewerVisibility(frameName)
		if not enabled then cfg = nil end
		if not applyCooldownViewerMode(frameName, cfg) then missingFrame = true end
	end

	if enabled and missingFrame then
		scheduleCooldownViewerReapply()
	elseif addon.variables then
		addon.variables.cooldownViewerRetryCount = nil
	end
end

local COOLDOWN_VIEWER_EVENTS = {
	"PLAYER_ENTERING_WORLD",
	"COOLDOWN_VIEWER_DATA_LOADED",
	"CVAR_UPDATE",
	"PLAYER_REGEN_ENABLED",
	"PLAYER_REGEN_DISABLED",
	"PLAYER_MOUNT_DISPLAY_CHANGED",
	"UPDATE_SHAPESHIFT_FORM",
	"PLAYER_TARGET_CHANGED",
	"GROUP_ROSTER_UPDATE",
}

local function setCooldownViewerWatcherEnabled(watcher, enabled)
	if not watcher then return end
	if enabled then
		if watcher._eqolEventsRegistered then return end
		for _, event in ipairs(COOLDOWN_VIEWER_EVENTS) do
			watcher:RegisterEvent(event)
		end
		SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_START", "player")
		SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_STOP", "player")
		SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_FAILED", "player")
		SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_INTERRUPTED", "player")
		SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_CHANNEL_START", "player")
		SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_CHANNEL_STOP", "player")
		watcher._eqolEventsRegistered = true
	else
		if not watcher._eqolEventsRegistered then return end
		watcher:UnregisterAllEvents()
		watcher._eqolEventsRegistered = false
	end
end

local function EnsureCooldownViewerWatcher()
	addon.variables = addon.variables or {}
	local enable = HasCooldownViewerVisibilityConfig()
	local watcher = addon.variables.cooldownViewerWatcher

	if not watcher then
		if not enable then return false end
		EnsureSkyridingStateDriver()
		watcher = CreateFrame("Frame")
		watcher:SetScript("OnEvent", function(_, event, name)
			if event == "CVAR_UPDATE" and name ~= "cooldownViewerEnabled" then return end
			if addon.variables then
				addon.variables.cooldownViewerRetryCount = nil
				if event == "CVAR_UPDATE" and name == "cooldownViewerEnabled" then addon.variables.cooldownViewerEnabledDirty = true end
			end
			if addon.functions.ApplyCooldownViewerVisibility then addon.functions.ApplyCooldownViewerVisibility() end
		end)
		addon.variables.cooldownViewerWatcher = watcher
	end

	if not enable then
		setCooldownViewerWatcherEnabled(watcher, false)
		return false
	end

	EnsureSkyridingStateDriver()
	setCooldownViewerWatcherEnabled(watcher, true)
	return true
end
addon.functions.EnsureCooldownViewerWatcher = EnsureCooldownViewerWatcher

local function EnsureCooldownViewerEditCallbacks()
	addon.variables = addon.variables or {}
	if addon.variables.cooldownViewerEditHooked then return end
	if not addon.EditMode or not addon.EditMode.lib or not addon.EditMode.lib.RegisterCallback then return end

	local owner = addon.variables.cooldownViewerEditOwner or {}
	addon.variables.cooldownViewerEditOwner = owner
	local function refreshEditModeFlag(active)
		addon.variables.cooldownViewerEditMode = active and true or false
		if addon.functions.ApplyCooldownViewerVisibility then addon.functions.ApplyCooldownViewerVisibility() end
	end

	addon.EditMode.lib:RegisterCallback("enter", function() refreshEditModeFlag(true) end, owner)
	addon.EditMode.lib:RegisterCallback("exit", function() refreshEditModeFlag(false) end, owner)

	addon.variables.cooldownViewerEditMode = addon.EditMode:IsInEditMode()
	addon.variables.cooldownViewerEditHooked = true
end
addon.functions.EnsureCooldownViewerEditCallbacks = EnsureCooldownViewerEditCallbacks

local function normalizeSpellActivationOverlayConfigValue(val, acc)
	if not SPELL_ACTIVATION_OVERLAY_VISIBILITY_KEYS[val] then return acc end
	acc = acc or {}
	acc[val] = true
	return acc
end

local function sanitizeSpellActivationOverlayConfig(cfg)
	if type(cfg) == "table" then
		local result
		for key, value in pairs(cfg) do
			if value == true then result = normalizeSpellActivationOverlayConfigValue(key, result) end
		end
		return result
	end
	if type(cfg) == "string" then return normalizeSpellActivationOverlayConfigValue(cfg, {}) end
	return nil
end

function addon.functions.GetSpellActivationOverlayVisibility()
	local cfg = sanitizeSpellActivationOverlayConfig(addon.db and addon.db.spellActivationOverlayVisibility)
	if not cfg then return nil end
	local copy = {}
	for key, value in pairs(cfg) do
		if value == true then copy[key] = true end
	end
	return copy
end

function addon.functions.SetSpellActivationOverlayVisibility(key, shouldSelect)
	addon.db = addon.db or {}
	local current = sanitizeSpellActivationOverlayConfig(addon.db.spellActivationOverlayVisibility) or {}
	if shouldSelect then
		current = normalizeSpellActivationOverlayConfigValue(key, current)
	else
		current[key] = nil
	end
	if current and next(current) then
		addon.db.spellActivationOverlayVisibility = current
	else
		addon.db.spellActivationOverlayVisibility = nil
	end
	if EnsureSpellActivationOverlayWatcher then EnsureSpellActivationOverlayWatcher() end
	if addon.functions.ApplySpellActivationOverlayVisibility then addon.functions.ApplySpellActivationOverlayVisibility() end
end

local function getSpellActivationOverlayAlphaValue(key, fallback)
	if not addon.db then return fallback end
	local value = clampVisibilityAlpha(addon.db[key])
	if value == nil then return fallback end
	return value
end

local function computeSpellActivationOverlayTargetAlpha(cfg, activeAlpha, hiddenAlpha)
	local mounted = IsPlayerMounted()
	local isSkyriding = addon.variables and addon.variables.isPlayerSkyriding and true or false
	local hasTarget = UnitExists and UnitExists("target") and true or false
	local isCasting = IsPlayerCasting()

	local shouldShow = false
	if cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.WHILE_MOUNTED] and mounted then shouldShow = true end
	if cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.WHILE_NOT_MOUNTED] and not mounted then shouldShow = true end
	if cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.SKYRIDING_ACTIVE] and isSkyriding then shouldShow = true end
	if cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.SKYRIDING_INACTIVE] and not isSkyriding then shouldShow = true end
	if cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.PLAYER_CASTING] and isCasting then shouldShow = true end
	if cfg[COOLDOWN_VIEWER_VISIBILITY_MODES.PLAYER_HAS_TARGET] and hasTarget then shouldShow = true end

	if shouldShow then return activeAlpha end
	return hiddenAlpha
end

local function applySpellActivationOverlayMode(cfg)
	local frame = _G[SPELL_ACTIVATION_OVERLAY_FRAME_NAME]
	if not frame then return false end
	addon.variables = addon.variables or {}
	local vars = addon.variables

	if not cfg or not next(cfg) then
		if vars.spellActivationOverlayApplied then
			local baseAlpha = vars.spellActivationOverlayBaseAlpha
			if type(baseAlpha) ~= "number" then baseAlpha = 1 end
			ApplyAlphaToRegion(frame, baseAlpha, false)
		end
		vars.spellActivationOverlayApplied = nil
		vars.spellActivationOverlayBaseAlpha = nil
		return true
	end

	if vars.spellActivationOverlayBaseAlpha == nil and frame.GetAlpha then
		local baseAlpha = frame:GetAlpha()
		if type(baseAlpha) == "number" then
			vars.spellActivationOverlayBaseAlpha = baseAlpha
		else
			vars.spellActivationOverlayBaseAlpha = 1
		end
	end

	local useCustomAlpha = addon.db and addon.db.spellActivationOverlayUseCustomAlpha == true
	local activeAlpha = 1
	local hiddenAlpha = 0
	if useCustomAlpha then
		activeAlpha = getSpellActivationOverlayAlphaValue("spellActivationOverlayActiveAlpha", 1)
		hiddenAlpha = getSpellActivationOverlayAlphaValue("spellActivationOverlayHiddenAlpha", 0)
	end

	local targetAlpha = computeSpellActivationOverlayTargetAlpha(cfg, activeAlpha, hiddenAlpha)
	ApplyAlphaToRegion(frame, targetAlpha, false)
	vars.spellActivationOverlayApplied = true
	return true
end

local function scheduleSpellActivationOverlayReapply()
	addon.variables = addon.variables or {}
	if addon.variables.spellActivationOverlayReapplyPending then return end
	if not C_Timer or not C_Timer.After then return end

	local attempts = (addon.variables.spellActivationOverlayRetryCount or 0) + 1
	addon.variables.spellActivationOverlayRetryCount = attempts
	if attempts > 10 then return end

	addon.variables.spellActivationOverlayReapplyPending = true
	C_Timer.After(1, function()
		addon.variables.spellActivationOverlayReapplyPending = nil
		if addon.functions.ApplySpellActivationOverlayVisibility then addon.functions.ApplySpellActivationOverlayVisibility() end
	end)
end

function addon.functions.ApplySpellActivationOverlayVisibility()
	addon.db = addon.db or {}
	addon.variables = addon.variables or {}
	EnsureSkyridingStateDriver()

	local cfg = addon.functions.GetSpellActivationOverlayVisibility()
	local ok = applySpellActivationOverlayMode(cfg)

	if cfg and not ok then
		scheduleSpellActivationOverlayReapply()
	elseif addon.variables then
		addon.variables.spellActivationOverlayRetryCount = nil
	end
end

EnsureSpellActivationOverlayWatcher = function()
	addon.variables = addon.variables or {}
	if addon.variables.spellActivationOverlayWatcher then return end

	EnsureSkyridingStateDriver()
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
	watcher:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
	watcher:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_START", "player")
	SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_STOP", "player")
	SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_FAILED", "player")
	SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_INTERRUPTED", "player")
	SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_CHANNEL_START", "player")
	SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_CHANNEL_STOP", "player")
	watcher:SetScript("OnEvent", function()
		if addon.functions.ApplySpellActivationOverlayVisibility then addon.functions.ApplySpellActivationOverlayVisibility() end
	end)
	addon.variables.spellActivationOverlayWatcher = watcher
end
addon.functions.EnsureSpellActivationOverlayWatcher = EnsureSpellActivationOverlayWatcher

local hookedButtons = {}

-- Keep action bars visible while interacting with SpellFlyout
local EQOL_LastMouseoverBar
local EQOL_LastMouseoverVar

local function EQOL_ShouldKeepVisibleByFlyout() return _G.SpellFlyout and _G.SpellFlyout:IsShown() and MouseIsOver(_G.SpellFlyout) end
local ACTIONBAR_VISIBILITY_MOUSEOVER_ONLY = { MOUSEOVER = true }
local function IsActionBarMouseoverGroupEnabled() return addon.db and addon.db.actionBarMouseoverShowAll == true end

local function ShouldFadeActionBar(skipFade)
	if skipFade then return false end
	return not IsActionBarMouseoverGroupEnabled()
end

local function IsActionBarGroupHoverActive()
	local vars = addon.variables
	return vars and vars._eqolActionBarGroupHoverActive == true
end

local function UpdateActionBarGroupHoverState(frame, isEnter)
	if not IsActionBarMouseoverGroupEnabled() then return end
	addon.variables = addon.variables or {}
	local vars = addon.variables
	local hovered = vars._eqolActionBarHoverFrames
	if not hovered then
		hovered = {}
		vars._eqolActionBarHoverFrames = hovered
	end

	if isEnter then
		if frame then hovered[frame] = true end
		if vars._eqolActionBarGroupHoverActive == true then return end
		vars._eqolActionBarGroupHoverActive = true
		if addon.functions and addon.functions.RefreshAllActionBarVisibilityAlpha then addon.functions.RefreshAllActionBarVisibilityAlpha() end
		return
	end

	if frame then hovered[frame] = nil end
	if vars._eqolActionBarHoverUpdatePending then return end
	vars._eqolActionBarHoverUpdatePending = true
	C_Timer.After(0, function()
		local state = addon.variables
		if not state then return end
		state._eqolActionBarHoverUpdatePending = nil

		local active = EQOL_ShouldKeepVisibleByFlyout()
		local set = state._eqolActionBarHoverFrames
		if set then
			for target in pairs(set) do
				if target and target.IsShown and target:IsShown() and MouseIsOver(target) then
					active = true
					break
				else
					set[target] = nil
				end
			end
		end

		if state._eqolActionBarGroupHoverActive == active then return end
		state._eqolActionBarGroupHoverActive = active
		if addon.functions and addon.functions.RefreshAllActionBarVisibilityAlpha then addon.functions.RefreshAllActionBarVisibilityAlpha() end
	end)
end

local function ShouldShowActionBarOnMouseover(bar)
	if MouseIsOver(bar) or EQOL_ShouldKeepVisibleByFlyout() then return true end
	if IsActionBarMouseoverGroupEnabled() then return IsActionBarGroupHoverActive() end
	return false
end

local function GetActionBarVisibilityConfig(variable, incoming, persistLegacy)
	local source = incoming
	if source == nil and addon.db then source = addon.db[variable] end

	if not persistLegacy and incoming == nil then
		if type(source) == "table" then
			if
				source.MOUSEOVER == true
				or source.ALWAYS_IN_COMBAT == true
				or source.ALWAYS_OUT_OF_COMBAT == true
				or source.SKYRIDING_ACTIVE == true
				or source.SKYRIDING_INACTIVE == true
				or source.PLAYER_CASTING == true
				or source.PLAYER_MOUNTED == true
				or source.PLAYER_NOT_MOUNTED == true
				or source.PLAYER_IN_GROUP == true
				or source.ALWAYS_HIDDEN == true
			then
				return source
			end
			return nil
		end
		if source == true then return ACTIONBAR_VISIBILITY_MOUSEOVER_ONLY end
	end

	local config
	if type(source) == "table" then
		config = {
			MOUSEOVER = source.MOUSEOVER == true,
			ALWAYS_IN_COMBAT = source.ALWAYS_IN_COMBAT == true,
			ALWAYS_OUT_OF_COMBAT = source.ALWAYS_OUT_OF_COMBAT == true,
			SKYRIDING_ACTIVE = source.SKYRIDING_ACTIVE == true,
			SKYRIDING_INACTIVE = source.SKYRIDING_INACTIVE == true,
			PLAYER_CASTING = source.PLAYER_CASTING == true,
			PLAYER_MOUNTED = source.PLAYER_MOUNTED == true,
			PLAYER_NOT_MOUNTED = source.PLAYER_NOT_MOUNTED == true,
			PLAYER_IN_GROUP = source.PLAYER_IN_GROUP == true,
			ALWAYS_HIDDEN = source.ALWAYS_HIDDEN == true,
		}
	elseif source == true then
		config = {
			MOUSEOVER = true,
			ALWAYS_IN_COMBAT = false,
			ALWAYS_OUT_OF_COMBAT = false,
			SKYRIDING_ACTIVE = false,
			SKYRIDING_INACTIVE = false,
			PLAYER_CASTING = false,
			PLAYER_MOUNTED = false,
			PLAYER_NOT_MOUNTED = false,
			PLAYER_IN_GROUP = false,
			ALWAYS_HIDDEN = false,
		}
	elseif source == "hide" then
		config = {
			ALWAYS_HIDDEN = true,
		}
	else
		config = nil
	end

	if
		config
		and not (
			config.MOUSEOVER
			or config.ALWAYS_IN_COMBAT
			or config.ALWAYS_OUT_OF_COMBAT
			or config.SKYRIDING_ACTIVE
			or config.SKYRIDING_INACTIVE
			or config.PLAYER_CASTING
			or config.PLAYER_MOUNTED
			or config.PLAYER_NOT_MOUNTED
			or config.PLAYER_IN_GROUP
			or config.ALWAYS_HIDDEN
		)
	then
		config = nil
	end

	if persistLegacy and addon.db then
		if not config then
			addon.db[variable] = nil
		else
			local stored = {}
			if config.MOUSEOVER then stored.MOUSEOVER = true end
			if config.ALWAYS_IN_COMBAT then stored.ALWAYS_IN_COMBAT = true end
			if config.ALWAYS_OUT_OF_COMBAT then stored.ALWAYS_OUT_OF_COMBAT = true end
			if config.SKYRIDING_ACTIVE then stored.SKYRIDING_ACTIVE = true end
			if config.SKYRIDING_INACTIVE then stored.SKYRIDING_INACTIVE = true end
			if config.PLAYER_CASTING then stored.PLAYER_CASTING = true end
			if config.PLAYER_MOUNTED then stored.PLAYER_MOUNTED = true end
			if config.PLAYER_NOT_MOUNTED then stored.PLAYER_NOT_MOUNTED = true end
			if config.PLAYER_IN_GROUP then stored.PLAYER_IN_GROUP = true end
			if config.ALWAYS_HIDDEN then stored.ALWAYS_HIDDEN = true end
			addon.db[variable] = stored
		end
	end

	return config
end

local function NormalizeActionBarVisibilityConfig(variable, incoming) return GetActionBarVisibilityConfig(variable, incoming, true) end
addon.functions.NormalizeActionBarVisibilityConfig = NormalizeActionBarVisibilityConfig

local function GetActionBarVisibilityContext(combatOverride)
	local inCombat = combatOverride
	if inCombat == nil then
		if InCombatLockdown and InCombatLockdown() then
			inCombat = true
		elseif UnitAffectingCombat then
			inCombat = UnitAffectingCombat("player") and true or false
		else
			inCombat = false
		end
	end

	return {
		inCombat = inCombat,
		hasTarget = UnitExists and UnitExists("target") and true or false,
		inGroup = IsInGroup and IsInGroup() and true or false,
		mounted = IsPlayerMounted(),
		isCasting = IsPlayerCasting(),
		isSkyriding = addon.variables and addon.variables.isPlayerSkyriding,
	}
end

local function ActionBarShouldForceShowByConfig(config, context, combatOverride)
	if not config then return false end
	if config.ALWAYS_HIDDEN then return false end
	local ctx = context or GetActionBarVisibilityContext(combatOverride)
	if config.SKYRIDING_ACTIVE and ctx.isSkyriding then return true end
	if config.ALWAYS_IN_COMBAT and ctx.inCombat then return true end
	if config.ALWAYS_OUT_OF_COMBAT and not ctx.inCombat then return true end
	if config.PLAYER_CASTING and ctx.isCasting then return true end
	if config.PLAYER_MOUNTED and ctx.mounted then return true end
	if config.PLAYER_NOT_MOUNTED and not ctx.mounted then return true end
	if config.PLAYER_IN_GROUP and ctx.inGroup then return true end
	return false
end

local function IsActionBarMouseoverEnabled(variable)
	local cfg = GetActionBarVisibilityConfig(variable)
	return cfg and cfg.MOUSEOVER == true
end

local function HasActionBarVisibilityConfig()
	local list = addon.variables and addon.variables.actionBarNames
	if not list then return false end
	for _, info in ipairs(list) do
		if info.var and GetActionBarVisibilityConfig(info.var) then return true end
	end
	return false
end

local function GetActionBarFadeStrength()
	if not addon.db then return 1 end
	local strength = tonumber(addon.db.actionBarFadeStrength)
	if not strength then strength = 1 end
	if strength < 0 then strength = 0 end
	if strength > 1 then strength = 1 end
	return strength
end
addon.functions.GetActionBarFadeStrength = GetActionBarFadeStrength

local function GetActionBarFadedAlpha() return 1 - GetActionBarFadeStrength() end

local function GetActionBarBaseAlpha(cfg, fadeAlpha)
	if type(fadeAlpha) ~= "number" then fadeAlpha = GetActionBarFadedAlpha() end
	return fadeAlpha
end

local function GetFrameFadeStrength()
	if not addon.db then return 1 end
	local strength = tonumber(addon.db.frameVisibilityFadeStrength)
	if not strength then strength = 1 end
	if strength < 0 then strength = 0 end
	if strength > 1 then strength = 1 end
	return strength
end
addon.functions.GetFrameFadeStrength = GetFrameFadeStrength

local function GetFrameFadedAlpha() return 1 - GetFrameFadeStrength() end
addon.functions.GetFrameFadedAlpha = GetFrameFadedAlpha

local function GetCooldownViewerFadeStrength()
	if not addon.db then return 1 end
	local strength = tonumber(addon.db.cooldownViewerFadeStrength)
	if not strength then strength = 1 end
	if strength < 0 then strength = 0 end
	if strength > 1 then strength = 1 end
	return strength
end
addon.functions.GetCooldownViewerFadeStrength = GetCooldownViewerFadeStrength

local function GetCooldownViewerFadedAlpha() return 1 - GetCooldownViewerFadeStrength() end
addon.functions.GetCooldownViewerFadedAlpha = GetCooldownViewerFadedAlpha

local function ApplyActionBarAlpha(bar, variable, config, combatOverride, skipFade, context)
	if not bar then return end
	if addon.variables and addon.variables.actionBarShowGrid then
		ApplyAlphaToRegion(bar, 1, false)
		return
	end
	local cfg
	if type(config) == "table" then
		cfg = NormalizeActionBarVisibilityConfig(variable, config)
	elseif config ~= nil then
		cfg = NormalizeActionBarVisibilityConfig(variable, config)
	else
		cfg = GetActionBarVisibilityConfig(variable)
	end
	if not cfg then return end
	local useFade = ShouldFadeActionBar(skipFade)
	if cfg.ALWAYS_HIDDEN then
		ApplyAlphaToRegion(bar, 0, useFade)
		return
	end
	local ctx = context or GetActionBarVisibilityContext(combatOverride)
	local fadedAlpha = GetActionBarFadedAlpha()
	local baseAlpha = GetActionBarBaseAlpha(cfg, fadedAlpha)
	local hasShowRules = cfg.MOUSEOVER
		or cfg.ALWAYS_IN_COMBAT
		or cfg.ALWAYS_OUT_OF_COMBAT
		or cfg.SKYRIDING_ACTIVE
		or cfg.PLAYER_CASTING
		or cfg.PLAYER_MOUNTED
		or cfg.PLAYER_NOT_MOUNTED
		or cfg.PLAYER_IN_GROUP

	if cfg.SKYRIDING_INACTIVE then
		if ctx.isSkyriding then
			ApplyAlphaToRegion(bar, baseAlpha, useFade)
			return
		elseif not hasShowRules then
			ApplyAlphaToRegion(bar, 1, useFade)
			return
		end
	end

	if ActionBarShouldForceShowByConfig(cfg, ctx, combatOverride) then
		ApplyAlphaToRegion(bar, 1, useFade)
		return
	end
	if cfg.MOUSEOVER then
		if ShouldShowActionBarOnMouseover(bar) then
			ApplyAlphaToRegion(bar, 1, useFade)
		else
			ApplyAlphaToRegion(bar, baseAlpha, useFade)
		end
	else
		ApplyAlphaToRegion(bar, baseAlpha, useFade)
	end
end

local function EQOL_HideBarIfNotHovered(bar, variable)
	local cfg = GetActionBarVisibilityConfig(variable)
	if not cfg then return end
	C_Timer.After(0, function()
		if addon.variables and addon.variables.actionBarShowGrid then
			ApplyAlphaToRegion(bar, 1, false)
			return
		end
		local current = GetActionBarVisibilityConfig(variable)
		if not current then return end
		local useFade = ShouldFadeActionBar()
		local context = GetActionBarVisibilityContext()
		local fadedAlpha = GetActionBarFadedAlpha()
		local baseAlpha = GetActionBarBaseAlpha(current, fadedAlpha)
		if current.ALWAYS_HIDDEN then
			ApplyAlphaToRegion(bar, 0, useFade)
			return
		end
		if ActionBarShouldForceShowByConfig(current, context) then
			ApplyAlphaToRegion(bar, 1, useFade)
			return
		end
		if not current.MOUSEOVER then
			ApplyAlphaToRegion(bar, baseAlpha, useFade)
			return
		end
		-- Only hide if neither the bar nor other hover targets are under the mouse
		if not ShouldShowActionBarOnMouseover(bar) then
			ApplyAlphaToRegion(bar, baseAlpha, useFade)
		else
			ApplyAlphaToRegion(bar, 1, useFade)
		end
	end)
end
local function EQOL_HookSpellFlyout()
	local flyout = _G.SpellFlyout
	if not flyout or flyout.EQOL_MouseoverHooked then return end

	flyout:HookScript("OnEnter", function()
		if IsActionBarMouseoverGroupEnabled() then
			UpdateActionBarGroupHoverState(flyout, true)
			return
		end
		if EQOL_LastMouseoverBar and IsActionBarMouseoverEnabled(EQOL_LastMouseoverVar) then EQOL_LastMouseoverBar:SetAlpha(1) end
	end)

	flyout:HookScript("OnLeave", function()
		if IsActionBarMouseoverGroupEnabled() then
			UpdateActionBarGroupHoverState(flyout, false)
			return
		end
		if EQOL_LastMouseoverBar and IsActionBarMouseoverEnabled(EQOL_LastMouseoverVar) then EQOL_HideBarIfNotHovered(EQOL_LastMouseoverBar, EQOL_LastMouseoverVar) end
	end)

	flyout:HookScript("OnHide", function()
		if IsActionBarMouseoverGroupEnabled() then
			UpdateActionBarGroupHoverState(flyout, false)
			return
		end
		if EQOL_LastMouseoverBar and IsActionBarMouseoverEnabled(EQOL_LastMouseoverVar) then EQOL_HideBarIfNotHovered(EQOL_LastMouseoverBar, EQOL_LastMouseoverVar) end
	end)

	flyout.EQOL_MouseoverHooked = true
end
-- Action Bars
local EnsureActionBarVisibilityWatcher
local function UpdateActionBarMouseover(barName, config, variable)
	local bar = ResolveActionBarFrame(barName)
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
	elseif barName == "PetActionBar" or barName == "PetActionBarFrame" then
		btnPrefix = "PetActionButton"
	elseif barName == "StanceBar" or barName == "StanceBarFrame" then
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
		if EnsureActionBarVisibilityWatcher then EnsureActionBarVisibilityWatcher() end
		return
	end

	if cfg.MOUSEOVER then
		bar:SetScript("OnEnter", function()
			local current = GetActionBarVisibilityConfig(variable)
			if not current or not current.MOUSEOVER then return end
			if IsActionBarMouseoverGroupEnabled() then
				UpdateActionBarGroupHoverState(bar, true)
			else
				bar:SetAlpha(1)
			end
			EQOL_LastMouseoverBar = bar
			EQOL_LastMouseoverVar = variable
		end)
		bar:SetScript("OnLeave", function()
			if IsActionBarMouseoverGroupEnabled() then
				UpdateActionBarGroupHoverState(bar, false)
			else
				EQOL_HideBarIfNotHovered(bar, variable)
			end
		end)
	else
		bar:SetScript("OnEnter", nil)
		bar:SetScript("OnLeave", nil)
	end

	local function handleButtonEnter(self)
		local current = GetActionBarVisibilityConfig(variable)
		if not current then return end
		if current.MOUSEOVER then
			if IsActionBarMouseoverGroupEnabled() then
				UpdateActionBarGroupHoverState(self, true)
			else
				bar:SetAlpha(1)
			end
			EQOL_LastMouseoverBar = bar
			EQOL_LastMouseoverVar = variable
		elseif ActionBarShouldForceShowByConfig(current) then
			bar:SetAlpha(1)
		end
	end

	local function handleButtonLeave(self)
		local current = GetActionBarVisibilityConfig(variable)
		if not current then return end
		if current.MOUSEOVER then
			if IsActionBarMouseoverGroupEnabled() then
				UpdateActionBarGroupHoverState(self, false)
			else
				EQOL_HideBarIfNotHovered(bar, variable)
			end
			return
		end
		ApplyActionBarAlpha(bar, variable, current)
	end

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
				button:SetScript("OnLeave", function(self)
					handleButtonLeave(self)
					GameTooltip:Hide()
				end)
			end
			if not hookedButtons[button] then GameTooltipActionButton(button) end
		end
	end

	if cfg.MOUSEOVER then C_Timer.After(0, EQOL_HookSpellFlyout) end

	ApplyActionBarAlpha(bar, variable, cfg)
	if EnsureActionBarVisibilityWatcher then EnsureActionBarVisibilityWatcher() end
end
addon.functions.UpdateActionBarMouseover = UpdateActionBarMouseover

local function EnsureAssistedCombatFrameHidden(button)
	if not addon.db then return end
	local frame = button and button.AssistedCombatRotationFrame
	if not frame then return end

	if not frame.EQOL_AssistedHideHooked then
		frame.EQOL_AssistedHideHooked = true
		frame:HookScript("OnShow", function(self)
			if addon.db and addon.db.actionBarHideAssistedRotation then
				self:SetAlpha(0)
			elseif self:GetAlpha() ~= 1 then
				self:SetAlpha(1)
			end
		end)
	end

	if addon.db.actionBarHideAssistedRotation then frame:SetAlpha(0) end
end

local function UpdateAssistedCombatFrameHiding()
	addon.variables = addon.variables or {}
	local enabled = addon.db and addon.db.actionBarHideAssistedRotation

	if enabled then
		if not addon.variables.assistedCombatCallbackOwner then
			addon.variables.assistedCombatCallbackOwner = {}
			EventRegistry:RegisterCallback("ActionButton.OnAssistedCombatRotationFrameChanged", function(_, button, added)
				if not addon.db or not addon.db.actionBarHideAssistedRotation then return end
				if added then EnsureAssistedCombatFrameHidden(button) end
			end, addon.variables.assistedCombatCallbackOwner)
		end
		ForEachActionButton(function(button) EnsureAssistedCombatFrameHidden(button) end)
	else
		if addon.variables.assistedCombatCallbackOwner then
			EventRegistry:UnregisterCallback("ActionButton.OnAssistedCombatRotationFrameChanged", addon.variables.assistedCombatCallbackOwner)
			addon.variables.assistedCombatCallbackOwner = nil
		end
	end
end
addon.functions.UpdateAssistedCombatFrameHiding = UpdateAssistedCombatFrameHiding

local function ApplyExtraActionArtworkSetting()
	if not addon.db then return end

	local shouldHide = addon.db.hideExtraActionArtwork == true
	addon.variables = addon.variables or {}
	local applied = addon.variables.extraActionArtworkApplied == true

	-- Only act when we need to apply or explicitly undo our own change.
	if InCombatLockdown and InCombatLockdown() and (shouldHide or applied) then
		addon.variables.pendingExtraActionArtwork = true
		return
	end
	if not shouldHide and not applied then
		addon.variables.pendingExtraActionArtwork = nil
		return
	end

	local extraActionButton = _G.ExtraActionButton1
	local extraStyle = extraActionButton and extraActionButton.style
	if extraStyle then
		if shouldHide then
			extraStyle:SetAlpha(0)
			extraStyle:Hide()
		else
			extraStyle:SetAlpha(1)
			extraStyle:Show()
		end
	end

	local zoneAbilityFrame = _G.ZoneAbilityFrame
	local zoneStyle = zoneAbilityFrame and zoneAbilityFrame.Style
	if zoneStyle then
		if shouldHide then
			zoneStyle:SetAlpha(0)
			zoneStyle:Hide()
		else
			zoneStyle:SetAlpha(1)
			zoneStyle:Show()
		end
	end

	local extraActionBarFrame = _G.ExtraActionBarFrame
	if extraActionBarFrame and extraActionBarFrame.EnableMouse then extraActionBarFrame:EnableMouse(not shouldHide) end

	addon.variables.extraActionArtworkApplied = shouldHide
	addon.variables.pendingExtraActionArtwork = nil
end
addon.functions.ApplyExtraActionArtworkSetting = ApplyExtraActionArtworkSetting

local function ApplyActionBarVisibilityAlpha(skipFade, event)
	if addon.variables then
		if not IsActionBarMouseoverGroupEnabled() then
			addon.variables._eqolActionBarGroupHoverActive = nil
			addon.variables._eqolActionBarHoverFrames = nil
			addon.variables._eqolActionBarHoverUpdatePending = nil
		elseif addon.variables._eqolActionBarGroupHoverActive == nil then
			addon.variables._eqolActionBarGroupHoverActive = EQOL_ShouldKeepVisibleByFlyout() and true or false
		end
	end
	local combatOverride
	if event == "PLAYER_REGEN_DISABLED" then
		combatOverride = true
	elseif event == "PLAYER_REGEN_ENABLED" then
		combatOverride = false
	end
	local context = GetActionBarVisibilityContext(combatOverride)
	for _, info in ipairs(addon.variables.actionBarNames or {}) do
		local bar = ResolveActionBarFrame(info.name)
		if bar then ApplyActionBarAlpha(bar, info.var, nil, combatOverride, skipFade, context) end
	end
end
local function RefreshAllActionBarVisibilityAlpha(skipFade, event)
	if type(skipFade) == "string" and event == nil then
		event = skipFade
		skipFade = nil
	end
	addon.variables = addon.variables or {}
	local vars = addon.variables
	if EnsureActionBarVisibilityWatcher and not EnsureActionBarVisibilityWatcher() then
		vars._eqolActionBarRefreshSkipFade = nil
		vars._eqolActionBarRefreshEvent = nil
		vars._eqolActionBarRefreshPending = nil
		return
	end
	if skipFade then vars._eqolActionBarRefreshSkipFade = true end
	if event then vars._eqolActionBarRefreshEvent = event end
	if vars._eqolActionBarRefreshPending then return end
	vars._eqolActionBarRefreshPending = true
	C_Timer.After(0, function()
		local state = addon.variables
		if not state then return end
		local pendingSkipFade = state._eqolActionBarRefreshSkipFade
		local pendingEvent = state._eqolActionBarRefreshEvent
		state._eqolActionBarRefreshSkipFade = nil
		state._eqolActionBarRefreshEvent = nil
		state._eqolActionBarRefreshPending = nil
		ApplyActionBarVisibilityAlpha(pendingSkipFade, pendingEvent)
	end)
end
addon.functions.RefreshAllActionBarVisibilityAlpha = RefreshAllActionBarVisibilityAlpha
addon.functions.RequestActionBarRefresh = RefreshAllActionBarVisibilityAlpha

EnsureSkyridingStateDriver = function()
	addon.variables = addon.variables or {}
	if addon.variables.skyridingDriver then return end
	local driver = CreateFrame("Frame")
	driver:Hide()
	local function refreshSkyridingDependents()
		RefreshAllActionBarVisibilityAlpha()
		if addon.functions and addon.functions.ApplyCooldownViewerVisibility then addon.functions.ApplyCooldownViewerVisibility() end
		if addon.functions and addon.functions.ApplySpellActivationOverlayVisibility then addon.functions.ApplySpellActivationOverlayVisibility() end
	end
	driver:SetScript("OnShow", function()
		addon.variables.isPlayerSkyriding = true
		refreshSkyridingDependents()
	end)
	driver:SetScript("OnHide", function()
		addon.variables.isPlayerSkyriding = false
		refreshSkyridingDependents()
	end)
	local expr
	if addon.variables.unitClass == "DRUID" then
		expr = "[advflyable, mounted] show; [advflyable, stance:3] show; hide"
	else
		expr = "[advflyable, mounted] show; hide"
	end
	local function registerDriver()
		if addon.variables.skyridingDriverRegistered then return end
		if RegisterStateDriver then
			RegisterStateDriver(driver, "visibility", expr)
			addon.variables.skyridingDriverRegistered = true
			addon.variables.isPlayerSkyriding = driver:IsShown()
		end
	end
	if InCombatLockdown and InCombatLockdown() then
		addon.variables.pendingSkyridingDriverRegister = registerDriver
		local watcher = addon.variables.skyridingDriverWatcher
		if not watcher then
			watcher = CreateFrame("Frame")
			watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
			watcher:SetScript("OnEvent", function(self)
				if InCombatLockdown and InCombatLockdown() then return end
				local cb = addon.variables and addon.variables.pendingSkyridingDriverRegister
				addon.variables.pendingSkyridingDriverRegister = nil
				if cb then cb() end
				self:UnregisterEvent("PLAYER_REGEN_ENABLED")
				addon.variables.skyridingDriverWatcher = nil
			end)
			addon.variables.skyridingDriverWatcher = watcher
		end
	else
		registerDriver()
	end
	addon.variables.skyridingDriver = driver
end

local ACTIONBAR_VISIBILITY_EVENTS = {
	"PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED",
	"PLAYER_ENTERING_WORLD",
	"PLAYER_MOUNT_DISPLAY_CHANGED",
	"UPDATE_SHAPESHIFT_FORM",
	"GROUP_ROSTER_UPDATE",
	"ACTIONBAR_SHOWGRID",
	"ACTIONBAR_HIDEGRID",
}

local function setActionBarVisibilityWatcherEnabled(watcher, enabled)
	if not watcher then return end
	if enabled then
		if watcher._eqolEventsRegistered then return end
		for _, event in ipairs(ACTIONBAR_VISIBILITY_EVENTS) do
			watcher:RegisterEvent(event)
		end
		SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_START", "player")
		SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_STOP", "player")
		SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_FAILED", "player")
		SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_INTERRUPTED", "player")
		SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_CHANNEL_START", "player")
		SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_CHANNEL_STOP", "player")
		SafeRegisterUnitEvent(watcher, "UNIT_HEALTH", "player")
		SafeRegisterUnitEvent(watcher, "UNIT_MAXHEALTH", "player")
		watcher._eqolEventsRegistered = true
	else
		if not watcher._eqolEventsRegistered then return end
		watcher:UnregisterAllEvents()
		watcher._eqolEventsRegistered = false
	end
end

EnsureActionBarVisibilityWatcher = function()
	addon.variables = addon.variables or {}
	local enable = HasActionBarVisibilityConfig()
	local watcher = addon.variables.actionBarVisibilityWatcher
	if not watcher then
		if not enable then
			addon.variables.actionBarShowGrid = nil
			addon.variables._eqolActionBarGroupHoverActive = nil
			addon.variables._eqolActionBarHoverFrames = nil
			addon.variables._eqolActionBarHoverUpdatePending = nil
			return false
		end
		EnsureSkyridingStateDriver()
		watcher = CreateFrame("Frame")
		watcher:SetScript("OnEvent", function(_, event)
			if event == "ACTIONBAR_SHOWGRID" then
				addon.variables = addon.variables or {}
				addon.variables.actionBarShowGrid = true
				RefreshAllActionBarVisibilityAlpha(true, event)
				return
			end
			if event == "ACTIONBAR_HIDEGRID" then
				if addon.variables then addon.variables.actionBarShowGrid = nil end
				RefreshAllActionBarVisibilityAlpha(true, event)
				return
			end
			RefreshAllActionBarVisibilityAlpha(nil, event)
		end)
		addon.variables.actionBarVisibilityWatcher = watcher
	end

	if not enable then
		setActionBarVisibilityWatcherEnabled(watcher, false)
		addon.variables.actionBarShowGrid = nil
		addon.variables._eqolActionBarGroupHoverActive = nil
		addon.variables._eqolActionBarHoverFrames = nil
		addon.variables._eqolActionBarHoverUpdatePending = nil
		return false
	end

	EnsureSkyridingStateDriver()
	setActionBarVisibilityWatcherEnabled(watcher, true)
	return true
end
addon.functions.UpdateActionBarVisibilityWatcher = EnsureActionBarVisibilityWatcher

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

-- New modular Unit Frames UI builder
-- New modular Vendor & Economy UI builder

local function setCVarValue(cvarKey, newValue)
	if newValue == nil then return end

	newValue = tostring(newValue)
	local currentValue = C_CVar.GetCVar(cvarKey)
	if currentValue ~= nil then currentValue = tostring(currentValue) end

	if currentValue == newValue then return end

	local guard = addon.variables.cvarEnforceGuard
	if not guard then
		guard = {}
		addon.variables.cvarEnforceGuard = guard
	end

	guard[cvarKey] = true
	C_CVar.SetCVar(cvarKey, newValue)
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

local function initActionBars()
	addon.functions.InitDBValue("actionBarAnchorEnabled", false)
	addon.functions.InitDBValue("actionBarFadeStrength", 1)
	addon.functions.InitDBValue("actionBarFullRangeColoring", false)
	addon.functions.InitDBValue("actionBarFullRangeColor", { r = 1, g = 0.1, b = 0.1 })
	addon.functions.InitDBValue("actionBarHideBorders", false)
	addon.functions.InitDBValue("actionBarHideBordersAuto", false)
	addon.functions.InitDBValue("actionBarBorderStyle", "DEFAULT")
	addon.functions.InitDBValue("actionBarBorderEdgeSize", 16)
	addon.functions.InitDBValue("actionBarBorderPadding", 0)
	addon.functions.InitDBValue("actionBarBorderColoring", false)
	addon.functions.InitDBValue("actionBarBorderColor", { r = 1, g = 1, b = 1, a = 1 })
	addon.functions.InitDBValue("actionBarHideAssistedRotation", false)
	addon.functions.InitDBValue("hideExtraActionArtwork", false)
	addon.functions.InitDBValue("hideMacroNames", false)
	addon.functions.InitDBValue("actionBarMacroFontOverride", false)
	addon.functions.InitDBValue("actionBarHotkeyFontOverride", false)
	addon.functions.InitDBValue("actionBarMacroFontFace", addon.variables.defaultFont)
	addon.functions.InitDBValue("actionBarMacroFontSize", 12)
	addon.functions.InitDBValue("actionBarMacroFontOutline", "OUTLINE")
	addon.functions.InitDBValue("actionBarHotkeyFontFace", addon.variables.defaultFont)
	addon.functions.InitDBValue("actionBarHotkeyFontSize", 12)
	addon.functions.InitDBValue("actionBarHotkeyFontOutline", "OUTLINE")
	addon.functions.InitDBValue("actionBarCountFontOverride", false)
	addon.functions.InitDBValue("actionBarCountFontFace", addon.variables.defaultFont)
	addon.functions.InitDBValue("actionBarCountFontSize", 12)
	addon.functions.InitDBValue("actionBarCountFontOutline", "OUTLINE")
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
	addon.db.actionBarCountFontSize = clampFontSize(addon.db.actionBarCountFontSize)
	addon.db.actionBarFadeStrength = GetActionBarFadeStrength()
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
	if ActionBarLabels and ActionBarLabels.RefreshAllCountStyles then ActionBarLabels.RefreshAllCountStyles() end
	UpdateAssistedCombatFrameHiding()
	if ActionBarLabels and ActionBarLabels.RefreshActionButtonBorders then ActionBarLabels.RefreshActionButtonBorders() end
	ApplyExtraActionArtworkSetting()
end

local function initParty()
	addon.functions.InitDBValue("autoAcceptGroupInvite", false)
	addon.functions.InitDBValue("autoAcceptGroupInviteFriendOnly", false)
	addon.functions.InitDBValue("autoAcceptGroupInviteGuildOnly", false)
	addon.functions.InitDBValue("autoAcceptSummon", false)
end

local function setupQuickSkipCinematic()
	addon.variables = addon.variables or {}
	if addon.variables.quickSkipCinematicHooked then return end
	if not CinematicFrame or not CinematicFrame.HookScript then return end

	CinematicFrame:HookScript("OnKeyDown", function(_, key)
		if not addon.db or not addon.db["quickSkipCinematic"] then return end
		if key == "ESCAPE" then
			if CinematicFrame:IsShown() and CinematicFrame.closeDialog and _G.CinematicFrameCloseDialogConfirmButton then CinematicFrame.closeDialog:Hide() end
		end
	end)

	CinematicFrame:HookScript("OnKeyUp", function(_, key)
		if not addon.db or not addon.db["quickSkipCinematic"] then return end
		if key == "SPACE" or key == "ESCAPE" or key == "ENTER" then
			if CinematicFrame:IsShown() and CinematicFrame.closeDialog and _G.CinematicFrameCloseDialogConfirmButton then _G.CinematicFrameCloseDialogConfirmButton:Click() end
		end
	end)

	if MovieFrame and MovieFrame.HookScript then
		MovieFrame:HookScript("OnKeyUp", function(_, key)
			if not addon.db or not addon.db["quickSkipCinematic"] then return end
			if key == "SPACE" or key == "ESCAPE" or key == "ENTER" then
				if MovieFrame:IsShown() and MovieFrame.CloseDialog and MovieFrame.CloseDialog.ConfirmButton then MovieFrame.CloseDialog.ConfirmButton:Click() end
			end
		end)
	end

	addon.variables.quickSkipCinematicHooked = true
end

local AUTO_RELEASE_PVP_WORLD_MAPS = {
	[123] = true, -- Wintergrasp
	[244] = true, -- Tol Barad (PvP)
	[588] = true, -- Ashran
	[622] = true, -- Stormshield
	[624] = true, -- Warspear
}

local AUTO_RELEASE_PVP_EXCLUDE_ALTERAC = {
	[91] = true, -- Alterac Valley
	[1537] = true, -- Alterac Valley (legacy)
}

local AUTO_RELEASE_PVP_EXCLUDE_WINTERGRASP = {
	[123] = true, -- Wintergrasp
	[1334] = true, -- Wintergrasp (instanced)
}

local AUTO_RELEASE_PVP_EXCLUDE_TOLBARAD = {
	[244] = true, -- Tol Barad (PvP)
}

local AUTO_RELEASE_PVP_EXCLUDE_ASHRAN = {
	[588] = true, -- Ashran
	[622] = true, -- Stormshield
	[624] = true, -- Warspear
	[1478] = true, -- Ashran (instanced)
}

local function hasUsableSelfResurrection()
	local deathInfo = _G.C_DeathInfo
	local options = deathInfo and deathInfo.GetSelfResurrectOptions and deathInfo.GetSelfResurrectOptions()
	if not options then return false end
	for _, option in ipairs(options) do
		if option and option.canUse then return true end
	end
	return false
end

local function isAutoReleasePvPExcluded(mapID)
	if not mapID then return false end
	if addon.db["autoReleasePvPExcludeAlterac"] and AUTO_RELEASE_PVP_EXCLUDE_ALTERAC[mapID] then return true end
	if addon.db["autoReleasePvPExcludeWintergrasp"] and AUTO_RELEASE_PVP_EXCLUDE_WINTERGRASP[mapID] then return true end
	if addon.db["autoReleasePvPExcludeTolBarad"] and AUTO_RELEASE_PVP_EXCLUDE_TOLBARAD[mapID] then return true end
	if addon.db["autoReleasePvPExcludeAshran"] and AUTO_RELEASE_PVP_EXCLUDE_ASHRAN[mapID] then return true end
	return false
end

local function shouldAutoReleasePvP(mapID, inInstance, instanceType)
	if not addon.db or not addon.db["autoReleasePvP"] then return false end
	if hasUsableSelfResurrection() then return false end
	if inInstance and instanceType == "pvp" then return not isAutoReleasePvPExcluded(mapID) end
	if mapID and AUTO_RELEASE_PVP_WORLD_MAPS[mapID] then return not isAutoReleasePvPExcluded(mapID) end
	return false
end

local function scheduleAutoReleasePvP(popup)
	if not popup or not popup.GetButton then return end
	if not addon.db or not addon.db["autoReleasePvP"] then return end

	local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local inInstance, instanceType = IsInInstance()
	if not shouldAutoReleasePvP(mapID, inInstance, instanceType) then return end

	local delayMs = tonumber(addon.db["autoReleasePvPDelay"] or 0) or 0
	if delayMs < 0 then delayMs = 0 end
	local delay = delayMs / 1000

	if popup._eqolAutoReleaseTimer then
		popup._eqolAutoReleaseTimer:Cancel()
		popup._eqolAutoReleaseTimer = nil
	end

	local function tryRelease()
		if not popup:IsShown() or popup.which ~= "DEATH" then return end
		local currentMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
		local inInstanceNow, instanceTypeNow = IsInInstance()
		if not shouldAutoReleasePvP(currentMapID, inInstanceNow, instanceTypeNow) then return end
		local button = popup:GetButton(1)
		if button then button:Click() end
	end

	if delay <= 0 then
		C_Timer.After(0, tryRelease)
	else
		popup._eqolAutoReleaseTimer = C_Timer.NewTimer(delay, function()
			popup._eqolAutoReleaseTimer = nil
			tryRelease()
		end)
	end
end

local function resolveResurrectOffererUnit(offerer)
	if issecretvalue and issecretvalue(offerer) then return nil end
	if not offerer or offerer == "" then return nil end
	if UnitExists(offerer) then return offerer end

	local function matches(unit)
		local name, realm = UnitName(unit)
		if not name then return false end
		if realm and realm ~= "" and offerer == (name .. "-" .. realm) then return true end
		return offerer == name
	end

	if matches("player") then return "player" end
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local unit = "raid" .. i
			if matches(unit) then return unit end
		end
	elseif IsInGroup() then
		for i = 1, GetNumSubgroupMembers() do
			local unit = "party" .. i
			if matches(unit) then return unit end
		end
	end

	return nil
end

local function shouldAutoAcceptResurrection(offerer)
	if not addon.db or not addon.db["autoAcceptResurrection"] then return false end
	local unit = resolveResurrectOffererUnit(offerer)
	if addon.db["autoAcceptResurrectionExcludeCombat"] then
		if unit and UnitAffectingCombat(unit) then return false end
	end
	if addon.db["autoAcceptResurrectionExcludeAfterlife"] then
		if unit and UnitIsDeadOrGhost(unit) then return false end
	end
	return true
end

local function initMisc()
	addon.functions.InitDBValue("confirmTimerRemovalTrade", false)
	addon.functions.InitDBValue("confirmPatronOrderDialog", false)
	addon.functions.InitDBValue("deleteItemFillDialog", false)
	addon.functions.InitDBValue("confirmReplaceEnchant", false)
	addon.functions.InitDBValue("confirmSocketReplace", false)
	addon.functions.InitDBValue("confirmHighCostItem", false)
	addon.functions.InitDBValue("confirmPurchaseTokenItem", false)
	addon.functions.InitDBValue("timeoutRelease", false)
	addon.functions.InitDBValue("timeoutReleaseModifier", "SHIFT")
	addon.functions.InitDBValue("autoAcceptResurrection", false)
	addon.functions.InitDBValue("autoAcceptResurrectionExcludeCombat", true)
	addon.functions.InitDBValue("autoAcceptResurrectionExcludeAfterlife", true)
	addon.functions.InitDBValue("autoReleasePvP", false)
	addon.functions.InitDBValue("autoReleasePvPDelay", 0)
	addon.functions.InitDBValue("autoReleasePvPExcludeAlterac", false)
	addon.functions.InitDBValue("autoReleasePvPExcludeWintergrasp", false)
	addon.functions.InitDBValue("autoReleasePvPExcludeTolBarad", false)
	addon.functions.InitDBValue("autoReleasePvPExcludeAshran", false)
	addon.functions.InitDBValue("hideRaidTools", false)
	addon.functions.InitDBValue("autoRepair", false)
	addon.functions.InitDBValue("autoRepairGuildBank", false)
	addon.functions.InitDBValue("sellAllJunk", false)
	addon.functions.InitDBValue("autoCancelCinematic", false)
	addon.functions.InitDBValue("quickSkipCinematic", false)
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

	if addon.db["autoCancelCinematic"] and addon.db["quickSkipCinematic"] then addon.db["quickSkipCinematic"] = false end

	setupQuickSkipCinematic()

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

						scheduleAutoReleasePvP(self)
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
						editBox:ClearFocus()
						editBox:SetAutoFocus(false)
					elseif addon.db["confirmPatronOrderDialog"] and self.data and type(self.data) == "table" and self.data.text == CRAFTING_ORDERS_OWN_REAGENTS_CONFIRMATION and self.GetButton then
						local order = C_CraftingOrders.GetClaimedOrder()
						if order and order.npcCustomerCreatureID and order.npcCustomerCreatureID > 0 then self:GetButton(1):Click() end
					elseif addon.db["confirmTimerRemovalTrade"] and self.which == "CONFIRM_MERCHANT_TRADE_TIMER_REMOVAL" and self.GetButton then
						self:GetButton(1):Click()
					elseif addon.db["confirmReplaceEnchant"] and self.which == "REPLACE_ENCHANT" and self.numButtons > 0 and self.GetButton then
						self:GetButton(1):Click()
					elseif addon.db["confirmSocketReplace"] and self.which == "CONFIRM_ACCEPT_SOCKETS" and self.numButtons > 0 and self.GetButton then
						self:GetButton(1):Click()
					elseif addon.db["confirmPurchaseTokenItem"] and self.which == "CONFIRM_PURCHASE_TOKEN_ITEM" and self.numButtons > 0 and self.GetButton then
						self:GetButton(1):Click()
					elseif addon.db["confirmHighCostItem"] and self.which == "CONFIRM_HIGH_COST_ITEM" and self.numButtons > 0 and self.GetButton then
						C_Timer.After(0, function() self:GetButton(1):Click() end)
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
				local usedGuildBank = addon.db["autoRepairGuildBank"] and CanGuildBankRepair()
				if usedGuildBank then
					RepairAllItems(true)
				else
					RepairAllItems()
				end
				PlaySound(SOUNDKIT.ITEM_REPAIR)
				print(L["repairCost"] .. addon.functions.formatMoney(repairAllCost))
				if usedGuildBank then print(L["repairFromGuildBank"] or "Repaired from guild bank.") end
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
	addon.functions.updateRaidToolsHook()
	addon.variables = addon.variables or {}

	local function applySquareLandingPageButtonAnchor(button)
		if not button or not addon.db or not addon.db["enableSquareMinimap"] then return end
		local reverse = addon.variables and addon.variables.landingPageReverse
		local id = reverse and reverse[button.title]
		button:ClearAllPoints()
		if id == 20 then
			button:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -25, -25)
		else
			button:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -16, -16)
		end
	end

	local function refreshLandingPageButtonFix()
		local button = _G.ExpansionLandingPageMinimapButton
		if not button then return end

		applySquareLandingPageButtonAnchor(button)

		local reverse = addon.variables and addon.variables.landingPageReverse
		local id = reverse and reverse[button.title]
		if addon.db and addon.db["hiddenLandingPages"] and id and addon.db["hiddenLandingPages"][id] then button:Hide() end
	end

	if ExpansionLandingPageMinimapButton and not addon.variables._eqolLandingPageButtonHooked then
		ExpansionLandingPageMinimapButton:HookScript("OnShow", refreshLandingPageButtonFix)
		ExpansionLandingPageMinimapButton:RegisterEvent("COVENANT_CHOSEN")
		ExpansionLandingPageMinimapButton:HookScript("OnEvent", function(_, event)
			if event ~= "COVENANT_CHOSEN" then return end
			C_Timer.After(0, refreshLandingPageButtonFix)
		end)
		addon.variables._eqolLandingPageButtonHooked = true
	end

	C_Timer.After(0, refreshLandingPageButtonFix)

	-- Right-click context menu for expansion/garrison minimap buttons
	local MU = MenuUtil

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
		[Enum.ItemQuality.Rare] = 0,
		[Enum.ItemQuality.Epic] = 0,
		[Enum.ItemQuality.Legendary] = 0,
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
	addon.functions.InitDBValue("unitFrameScaleEnabled", false)
	addon.functions.InitDBValue("unitFrameScale", addon.variables.unitFrameScale)
	addon.functions.InitDBValue("ufUseCustomClassColors", false)
	addon.functions.InitDBValue("ufClassColors", {})
	addon.functions.InitDBValue("hiddenCastBars", addon.db["hiddenCastBars"] or {})
	addon.functions.InitDBValue("cooldownViewerVisibility", addon.db["cooldownViewerVisibility"] or {})
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

	-- Name truncation was removed to avoid touching CompactUnitFrame name update flows.
	-- Keep no-op functions for compatibility with any lingering callers.
	addon.functions.EnsureUnitFrameNameHooks = function() end
	addon.functions.updateUnitFrameNames = function() end

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

	local function getStandaloneCastbarModule()
		local castbarModule = addon.Aura and (addon.Aura.Castbar or addon.Aura.UFStandaloneCastbar)
		if type(castbarModule) ~= "table" then return nil end
		if type(castbarModule.GetConfig) ~= "function" then return nil end
		return castbarModule
	end

	local function guardStandaloneCastbarDisabledWhenUnavailable()
		addon.db = addon.db or {}
		addon.db.castbar = type(addon.db.castbar) == "table" and addon.db.castbar or {}
		if getStandaloneCastbarModule() ~= nil then return false end
		if addon.db.castbar.enabled ~= true then return false end
		addon.db.castbar.enabled = false
		return true
	end

	local function isCustomPlayerCastbarEnabled()
		local standaloneEnabled = false
		local castbarModule = getStandaloneCastbarModule()
		if castbarModule and castbarModule.GetConfig then
			local cfg = castbarModule.GetConfig()
			if type(cfg) == "table" and cfg.enabled ~= nil then standaloneEnabled = cfg.enabled == true end
		end

		if standaloneEnabled then return true end

		-- Fallback gate: if UF player castbar is active, Blizzard player castbar must be hidden too.
		local uf = addon.Aura and addon.Aura.UF
		local playerCfg = uf and uf.GetConfig and uf.GetConfig("player")
		if type(playerCfg) ~= "table" or playerCfg.enabled ~= true then return false end
		local playerCast = playerCfg.cast
		return type(playerCast) == "table" and playerCast.enabled == true
	end

	local function EnsureCastbarHook(frame)
		if not frame or frame.EQOL_CastbarHooked then return end
		frame:HookScript("OnShow", function(self)
			local frameName = self:GetName()
			local hideByList = addon.db and addon.db.hiddenCastBars and addon.db.hiddenCastBars[frameName]
			local hidePlayerForCustom = frameName == "PlayerCastingBarFrame" and isCustomPlayerCastbarEnabled()
			if hideByList or hidePlayerForCustom then self:Hide() end
		end)
		frame.EQOL_CastbarHooked = true
	end

	function addon.functions.ApplyCastBarVisibility()
		if not addon.db then return end
		if type(addon.db.hiddenCastBars) ~= "table" then addon.db.hiddenCastBars = {} end
		guardStandaloneCastbarDisabledWhenUnavailable()
		local hidePlayerForCustom = isCustomPlayerCastbarEnabled()
		for key, getter in pairs(castBarFrames) do
			local frame = getter and getter() or _G[key]
			if frame then
				EnsureCastbarHook(frame)
				if addon.db.hiddenCastBars[key] or (key == "PlayerCastingBarFrame" and hidePlayerForCustom) then frame:Hide() end
			end
		end
	end

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

	if addon.functions.ApplyCooldownViewerVisibility then addon.functions.ApplyCooldownViewerVisibility() end
	if addon.functions.EnsureCooldownViewerWatcher then addon.functions.EnsureCooldownViewerWatcher() end
	if addon.functions.EnsureCooldownViewerEditCallbacks then addon.functions.EnsureCooldownViewerEditCallbacks() end
	if addon.functions.ApplySpellActivationOverlayVisibility then addon.functions.ApplySpellActivationOverlayVisibility() end
	if addon.functions.EnsureSpellActivationOverlayWatcher then addon.functions.EnsureSpellActivationOverlayWatcher() end
end

local function initBagsFrame()
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

	-- ! Still bugging as of 2026-01-21 - need to disable it
	-- moneyFrame:HookScript("OnEnter", ShowBagMoneyTooltip)
	-- moneyFrame:HookScript("OnLeave", HideBagMoneyTooltip)
	-- for _, coin in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
	-- 	local btn = moneyFrame[coin]
	-- 	if btn then
	-- 		btn:HookScript("OnEnter", ShowBagMoneyTooltip)
	-- 		btn:HookScript("OnLeave", HideBagMoneyTooltip)
	-- 	end
	-- end

	-- moneyFrame = ContainerFrame1.MoneyFrame
	-- moneyFrame:HookScript("OnEnter", ShowBagMoneyTooltip)
	-- moneyFrame:HookScript("OnLeave", HideBagMoneyTooltip)
	-- for _, coin in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
	-- 	local btn = moneyFrame[coin]
	-- 	if btn then
	-- 		btn:HookScript("OnEnter", ShowBagMoneyTooltip)
	-- 		btn:HookScript("OnLeave", HideBagMoneyTooltip)
	-- 	end
	-- end
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
			if issecretvalue and issecretvalue(msg) then return end
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

	addon.functions.ApplyChatFrameMaxLines = addon.functions.ApplyChatFrameMaxLines
		or function()
			local frame = DEFAULT_CHAT_FRAME or ChatFrame1
			if not frame or not frame.SetMaxLines then return end
			if addon.db and addon.db.chatFrameMaxLines2000 then
				frame:SetMaxLines(2000)
			else
				frame:SetMaxLines(128)
			end
		end

	local function getChatEditBox(chatFrame)
		if not chatFrame then return nil end
		if chatFrame.editBox then return chatFrame.editBox end
		local name = chatFrame:GetName()
		return name and _G[name .. "EditBox"]
	end

	local function forEachChatFrame(callback)
		local maxFrames = math.max(NUM_CHAT_WINDOWS or 0, 50)
		for i = 1, maxFrames do
			local frame = _G["ChatFrame" .. i]
			if frame then callback(frame, getChatEditBox(frame)) end
		end
	end

	local function ensureChatFrameHooks()
		addon.variables = addon.variables or {}
		if addon.variables.chatFrameHooksInstalled then return end
		addon.variables.chatFrameHooksInstalled = true

		hooksecurefunc("FCF_OpenTemporaryWindow", function()
			if addon.db and addon.db.chatUseArrowKeys and addon.functions.ApplyChatArrowKeys then addon.functions.ApplyChatArrowKeys(true) end
			if addon.db and addon.db.chatEditBoxOnTop and addon.functions.ApplyChatEditBoxOnTop then addon.functions.ApplyChatEditBoxOnTop(true) end
			if addon.db and addon.db.chatUnclampFrame and addon.functions.ApplyChatUnclampFrame then addon.functions.ApplyChatUnclampFrame(true) end
			if addon.db and addon.db.chatHideCombatLogTab and addon.functions.ApplyChatHideCombatLogTab then addon.functions.ApplyChatHideCombatLogTab(true) end
		end)

		hooksecurefunc("FCF_SetTabPosition", function()
			if not (addon.db and addon.db.chatHideCombatLogTab) then return end
			if ChatFrame1Tab and ChatFrame2Tab then ChatFrame2Tab:SetPoint("BOTTOMLEFT", ChatFrame1Tab, "BOTTOMRIGHT", 0, 0) end
		end)

		local frame = CreateFrame("Frame")
		frame:RegisterEvent("UPDATE_CHAT_WINDOWS")
		frame:SetScript("OnEvent", function()
			if addon.db and addon.db.chatUseArrowKeys and addon.functions.ApplyChatArrowKeys then addon.functions.ApplyChatArrowKeys(true) end
			if addon.db and addon.db.chatEditBoxOnTop and addon.functions.ApplyChatEditBoxOnTop then addon.functions.ApplyChatEditBoxOnTop(true) end
			if addon.db and addon.db.chatUnclampFrame and addon.functions.ApplyChatUnclampFrame then addon.functions.ApplyChatUnclampFrame(true) end
			if addon.db and addon.db.chatHideCombatLogTab and addon.functions.ApplyChatHideCombatLogTab then addon.functions.ApplyChatHideCombatLogTab(true) end
		end)
		addon.variables.chatFrameWatcher = frame
	end

	addon.functions.ApplyChatArrowKeys = addon.functions.ApplyChatArrowKeys
		or function(enabled)
			addon.variables = addon.variables or {}
			addon.variables.chatArrowKeyModeCache = addon.variables.chatArrowKeyModeCache or {}
			local cache = addon.variables.chatArrowKeyModeCache

			forEachChatFrame(function(_, editBox)
				if not (editBox and editBox.SetAltArrowKeyMode) then return end
				if enabled then
					if cache[editBox] == nil and editBox.GetAltArrowKeyMode then cache[editBox] = editBox:GetAltArrowKeyMode() end
					editBox:SetAltArrowKeyMode(false)
				else
					if cache[editBox] ~= nil then
						editBox:SetAltArrowKeyMode(cache[editBox])
						cache[editBox] = nil
					end
				end
			end)

			ensureChatFrameHooks()
		end

	local function storeEditBoxPoints(editBox)
		addon.variables = addon.variables or {}
		addon.variables.chatEditBoxAnchorCache = addon.variables.chatEditBoxAnchorCache or {}
		local cache = addon.variables.chatEditBoxAnchorCache
		if cache[editBox] then return end
		local points = {}
		for i = 1, editBox:GetNumPoints() do
			points[i] = { editBox:GetPoint(i) }
		end
		cache[editBox] = { points = points, width = editBox:GetWidth(), height = editBox:GetHeight() }
	end

	local function restoreEditBoxPoints(editBox)
		addon.variables = addon.variables or {}
		local cache = addon.variables.chatEditBoxAnchorCache
		local state = cache and cache[editBox]
		if not state then return end
		editBox:ClearAllPoints()
		if state.points then
			for _, point in ipairs(state.points) do
				editBox:SetPoint(point[1], point[2], point[3], point[4], point[5])
			end
		end
		if not state.points or #state.points == 0 then
			if state.width then editBox:SetWidth(state.width) end
			if state.height then editBox:SetHeight(state.height) end
		end
		cache[editBox] = nil
	end

	addon.functions.ApplyChatEditBoxOnTop = addon.functions.ApplyChatEditBoxOnTop
		or function(enabled)
			forEachChatFrame(function(frame, editBox)
				if not (frame and editBox) then return end
				if enabled then
					storeEditBoxPoints(editBox)
					editBox:ClearAllPoints()
					editBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
					editBox:SetWidth(frame:GetWidth())
					if not frame.eqolEditBoxSizeHooked then
						frame:HookScript("OnSizeChanged", function(self)
							if addon.db and addon.db.chatEditBoxOnTop and self.editBox then self.editBox:SetWidth(self:GetWidth()) end
						end)
						frame.eqolEditBoxSizeHooked = true
					end
				else
					restoreEditBoxPoints(editBox)
				end
			end)

			ensureChatFrameHooks()
		end

	local function storeChatClampState(frame)
		addon.variables = addon.variables or {}
		addon.variables.chatClampCache = addon.variables.chatClampCache or {}
		local cache = addon.variables.chatClampCache
		if cache[frame] then return end
		local state = {
			clamped = frame.IsClampedToScreen and frame:IsClampedToScreen() or nil,
		}
		if frame.GetClampRectInsets then state.insets = { frame:GetClampRectInsets() } end
		cache[frame] = state
	end

	local function restoreChatClampState(frame)
		addon.variables = addon.variables or {}
		local cache = addon.variables.chatClampCache
		local state = cache and cache[frame]
		if not state then return end
		if frame.SetClampedToScreen and state.clamped ~= nil then frame:SetClampedToScreen(state.clamped) end
		if state.insets and frame.SetClampRectInsets then frame:SetClampRectInsets(state.insets[1], state.insets[2], state.insets[3], state.insets[4]) end
		cache[frame] = nil
	end

	addon.functions.ApplyChatUnclampFrame = addon.functions.ApplyChatUnclampFrame
		or function(enabled)
			forEachChatFrame(function(frame)
				if not frame then return end
				if enabled then
					storeChatClampState(frame)
					if frame.SetClampedToScreen then frame:SetClampedToScreen(false) end
				else
					restoreChatClampState(frame)
				end
			end)

			ensureChatFrameHooks()
		end

	local function hideCombatLogTab()
		if not (ChatFrame2 and ChatFrame2Tab) then return end
		addon.variables = addon.variables or {}
		local state = addon.variables.chatCombatLogTabState or {}
		if not state.saved then
			state.name = ChatFrame2.name or (GetChatWindowInfo(2))
			state.scale = ChatFrame2Tab:GetScale()
			state.width = ChatFrame2Tab:GetWidth()
			state.height = ChatFrame2Tab:GetHeight()
			state.mouseEnabled = ChatFrame2Tab:IsMouseEnabled()
			state.saved = true
			addon.variables.chatCombatLogTabState = state
		end
		ChatFrame2Tab:EnableMouse(false)
		ChatFrame2Tab:SetText(" ")
		ChatFrame2Tab:SetScale(0.01)
		ChatFrame2Tab:SetWidth(0.01)
		ChatFrame2Tab:SetHeight(0.01)
		addon.variables.chatCombatLogHidden = true
	end

	local function showCombatLogTab()
		if not (ChatFrame2 and ChatFrame2Tab) then return end
		addon.variables = addon.variables or {}
		local state = addon.variables.chatCombatLogTabState or {}
		local name = state.name or COMBAT_LOG
		ChatFrame2Tab:SetScale(state.scale or 1)
		if state.width then ChatFrame2Tab:SetWidth(state.width) end
		if state.height then ChatFrame2Tab:SetHeight(state.height) end
		ChatFrame2Tab:EnableMouse(state.mouseEnabled ~= false)
		if FCF_SetWindowName then
			FCF_SetWindowName(ChatFrame2, name, true)
		else
			ChatFrame2Tab:SetText(name)
		end
		if FCFDock_UpdateTabs and GENERAL_CHAT_DOCK then FCFDock_UpdateTabs(GENERAL_CHAT_DOCK, true) end
		addon.variables.chatCombatLogHidden = nil
	end

	addon.functions.ApplyChatHideCombatLogTab = addon.functions.ApplyChatHideCombatLogTab
		or function(enabled)
			ensureChatFrameHooks()
			if not (ChatFrame2 and ChatFrame2Tab) then return end
			addon.variables = addon.variables or {}

			if enabled then
				if ChatFrame2.isDocked then
					hideCombatLogTab()
					addon.variables.chatCombatLogPending = nil
				else
					if addon.variables.chatCombatLogHidden then showCombatLogTab() end
					if not addon.variables.chatCombatLogWarned then
						local msg = L and L["chatHideCombatLogTabUndocked"] or "Combat log tab cannot be hidden while undocked."
						if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
							DEFAULT_CHAT_FRAME:AddMessage(msg)
						else
							print(msg)
						end
						addon.variables.chatCombatLogWarned = true
					end
					addon.variables.chatCombatLogPending = true
				end
			else
				if addon.variables.chatCombatLogHidden then showCombatLogTab() end
				addon.variables.chatCombatLogPending = nil
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

	addon.functions.InitDBValue("chatFrameMaxLines2000", false)
	addon.functions.InitDBValue("enableChatIM", false)
	addon.functions.InitDBValue("enableChatIMFade", false)
	addon.functions.InitDBValue("chatIMUseCustomSound", false)
	addon.functions.InitDBValue("chatIMCustomSoundFile", "")
	addon.functions.InitDBValue("chatIMMaxHistory", 250)
	addon.functions.InitDBValue("enableChatHistory", false)
	addon.functions.InitDBValue("chatChannelHistoryMaxLines", 500)
	addon.functions.InitDBValue("chatChannelHistoryMaxViewLines", 1000)
	addon.functions.InitDBValue("chatHistoryRestoreOnLogin", false)
	addon.functions.InitDBValue("chatChannelHistoryFontSize", 12)
	addon.functions.InitDBValue("chatChannelHistoryLootQualities", {
		[0] = true,
		[1] = true,
		[2] = true,
		[3] = true,
		[4] = true,
		[5] = true,
		[6] = true,
		[7] = true,
		[8] = true,
	})
	addon.functions.InitDBValue("chatHistoryFrameStrata", "MEDIUM")
	addon.functions.InitDBValue("chatHistoryFrameLevel", 600)
	addon.functions.InitDBValue("chatHistoryButtonOffsetX", 0)
	addon.functions.InitDBValue("chatHistoryButtonOffsetY", -10)
	addon.functions.InitDBValue("chatHistoryShowButton", true)
	addon.functions.InitDBValue("chatHistoryFramePos", nil)
	addon.functions.InitDBValue("chatChannelFilters", {})
	addon.functions.InitDBValue("chatChannelFiltersEnable", {})
	addon.functions.InitDBValue("chatIMFrameData", {})
	addon.functions.InitDBValue("chatIMHideInCombat", false)
	addon.functions.InitDBValue("chatIMUseAnimation", true)
	addon.functions.InitDBValue("chatShowLootCurrencyIcons", false)
	addon.functions.InitDBValue("chatShowItemLevelInLinks", false)
	addon.functions.InitDBValue("chatShowItemLevelLocation", false)
	addon.functions.InitDBValue("chatHideLearnUnlearn", false)
	addon.functions.InitDBValue("chatUseArrowKeys", false)
	addon.functions.InitDBValue("chatEditBoxOnTop", false)
	addon.functions.InitDBValue("chatUnclampFrame", false)
	addon.functions.InitDBValue("chatHideCombatLogTab", false)
	addon.functions.InitDBValue("chatBubbleFontOverride", false)
	addon.functions.InitDBValue("chatBubbleFontSize", DEFAULT_CHAT_BUBBLE_FONT_SIZE)
	addon.functions.ApplyChatBubbleFontSize(addon.db["chatBubbleFontSize"])
	-- Apply learn/unlearn message filter based on saved setting
	addon.functions.ApplyChatLearnFilter(addon.db["chatHideLearnUnlearn"])
	if addon.ChatIcons and addon.ChatIcons.SetEnabled then addon.ChatIcons:SetEnabled(addon.db["chatShowLootCurrencyIcons"]) end
	if addon.ChatIcons and addon.ChatIcons.SetItemLevelEnabled then addon.ChatIcons:SetItemLevelEnabled(addon.db["chatShowItemLevelInLinks"]) end

	if addon.ChatIM and addon.ChatIM.SetEnabled then addon.ChatIM:SetEnabled(addon.db["enableChatIM"]) end
	if addon.functions.ApplyChatFrameMaxLines then addon.functions.ApplyChatFrameMaxLines() end
	if addon.functions.ApplyChatArrowKeys then addon.functions.ApplyChatArrowKeys(addon.db["chatUseArrowKeys"]) end
	if addon.functions.ApplyChatEditBoxOnTop then addon.functions.ApplyChatEditBoxOnTop(addon.db["chatEditBoxOnTop"]) end
	if addon.functions.ApplyChatUnclampFrame then addon.functions.ApplyChatUnclampFrame(addon.db["chatUnclampFrame"]) end
	if addon.functions.ApplyChatHideCombatLogTab then addon.functions.ApplyChatHideCombatLogTab(addon.db["chatHideCombatLogTab"]) end
end

local function initMap()
	addon.functions.InitDBValue("enableWayCommand", false)
	if addon.db["enableWayCommand"] then addon.functions.registerWayCommand() end
	addon.functions.InitDBValue("enableCooldownManagerSlashCommand", false)
	if addon.db["enableCooldownManagerSlashCommand"] then addon.functions.registerCooldownManagerSlashCommand() end
	addon.functions.InitDBValue("enablePullTimerSlashCommand", false)
	if addon.db["enablePullTimerSlashCommand"] then addon.functions.registerPullTimerSlashCommand() end
	addon.functions.InitDBValue("enableEditModeSlashCommand", false)
	if addon.db["enableEditModeSlashCommand"] then addon.functions.registerEditModeSlashCommand() end
	addon.functions.InitDBValue("enableQuickKeybindSlashCommand", false)
	if addon.db["enableQuickKeybindSlashCommand"] then addon.functions.registerQuickKeybindSlashCommand() end
	addon.functions.InitDBValue("enableReloadUISlashCommand", false)
	if addon.db["enableReloadUISlashCommand"] then addon.functions.registerReloadUISlashCommand() end
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
	addon.functions.InitDBValue("communityChatPrivacyEnabled", false)
	addon.functions.InitDBValue("communityChatPrivacyMode", 1)
	if addon.Ignore and addon.Ignore.SetEnabled then addon.Ignore:SetEnabled(addon.db["enableIgnore"]) end
	if addon.Ignore and addon.Ignore.UpdateAnchor then addon.Ignore:UpdateAnchor() end
	if addon.FriendsListDecor and addon.FriendsListDecor.SetEnabled then addon.FriendsListDecor:SetEnabled(addon.db["friendsListDecorEnabled"] == true) end
	if addon.CommunityChatPrivacy and addon.CommunityChatPrivacy.SetMode then addon.CommunityChatPrivacy:SetMode(addon.db["communityChatPrivacyMode"]) end
	if addon.CommunityChatPrivacy and addon.CommunityChatPrivacy.SetEnabled then addon.CommunityChatPrivacy:SetEnabled(addon.db["communityChatPrivacyEnabled"]) end
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
	addon.functions.InitDBValue("frameVisibilityFadeStrength", 1)
	addon.functions.InitDBValue("buttonsink", {})
	addon.functions.InitDBValue("buttonSinkAnchorPreference", "AUTO")
	addon.functions.InitDBValue("minimapButtonBinColumns", DEFAULT_BUTTON_SINK_COLUMNS)
	addon.functions.InitDBValue("minimapButtonBinHideBackground", false)
	addon.functions.InitDBValue("minimapButtonBinHideBorder", false)
	addon.functions.InitDBValue("enableLootspecQuickswitch", false)
	addon.functions.InitDBValue("lootspec_quickswitch", {})
	addon.functions.InitDBValue("minimapSinkHoleData", {})
	addon.functions.InitDBValue("hideQuickJoinToast", false)
	addon.functions.InitDBValue("hideScreenshotStatus", false)
	addon.functions.InitDBValue("showTrainAllButton", false)
	addon.functions.InitDBValue("autoCancelDruidFlightForm", false)
	addon.functions.InitDBValue("randomMountDruidNoShiftWhileMounted", false)
	addon.functions.InitDBValue("randomMountDracthyrVisageBeforeMount", false)
	addon.functions.InitDBValue("randomMountCastSlowFallWhenFalling", false)
	addon.functions.InitDBValue("cooldownViewerFadeStrength", 1)
	addon.functions.InitDBValue("enableSquareMinimap", false)
	addon.functions.InitDBValue("enableSquareMinimapBorder", false)
	addon.functions.InitDBValue("enableSquareMinimapLayout", false)
	addon.functions.InitDBValue("squareMinimapBorderSize", 1)
	addon.functions.InitDBValue("squareMinimapBorderColor", { r = 0, g = 0, b = 0 })
	addon.functions.InitDBValue("minimapButtonsMouseover", false)
	addon.functions.InitDBValue("unclampMinimapCluster", false)
	addon.functions.InitDBValue("enableMinimapClusterScale", false)
	addon.functions.InitDBValue("minimapClusterScale", 1)
	addon.functions.InitDBValue("showWorldMapCoordinates", false)
	addon.functions.InitDBValue("worldMapCoordinatesUpdateInterval", 0.1)
	addon.functions.InitDBValue("worldMapCoordinatesHideCursor", true)
	addon.functions.InitDBValue("hiddenMinimapElements", addon.db["hiddenMinimapElements"] or {})
	addon.functions.InitDBValue("persistAuctionHouseFilter", false)
	addon.functions.InitDBValue("alwaysUserCurExpAuctionHouse", false)
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

	-- Mailbox address book
	addon.functions.InitDBValue("enableMailboxAddressBook", false)
	addon.functions.InitDBValue("mailboxContacts", {})

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
		local col = (addon.db and addon.db.squareMinimapBorderColor) or { r = 0, g = 0, b = 0, a = 1 }

		local r, g, b, a = col.r or 0, col.g or 0, col.b or 0, col.a or 1

		-- Top
		f.tTop:ClearAllPoints()
		f.tTop:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		f.tTop:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
		f.tTop:SetHeight(size)
		f.tTop:SetColorTexture(r, g, b, a)
		-- Bottom
		f.tBottom:ClearAllPoints()
		f.tBottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
		f.tBottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
		f.tBottom:SetHeight(size)
		f.tBottom:SetColorTexture(r, g, b, a)
		-- Left
		f.tLeft:ClearAllPoints()
		f.tLeft:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		f.tLeft:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
		f.tLeft:SetWidth(size)
		f.tLeft:SetColorTexture(r, g, b, a)
		-- Right
		f.tRight:ClearAllPoints()
		f.tRight:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
		f.tRight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
		f.tRight:SetWidth(size)
		f.tRight:SetColorTexture(r, g, b, a)

		if enableBorder and isSquare then
			f:Show()
		else
			f:Hide()
		end
	end

	-- Fill square minimap corners when the housing static overlay is shown
	function addon.functions.applySquareMinimapHousingBackdrop()
		if not Minimap or not MinimapBackdrop or not MinimapBackdrop.StaticOverlayTexture or not addon.db.enableSquareMinimap then return end

		if not addon.general.squareMinimapHousingBackdropFrame then
			local f = CreateFrame("Frame", nil, Minimap)
			f:SetAllPoints(Minimap)
			f:SetFrameStrata("LOW")
			f:SetFrameLevel(4)
			f.texture = f:CreateTexture(nil, "BACKGROUND")
			f.texture:SetAllPoints(f)
			f.texture:SetColorTexture(0, 0, 0, 1)
			f:Hide()
			addon.general.squareMinimapHousingBackdropFrame = f
		end

		local show = addon.db and addon.db.enableSquareMinimap and MinimapBackdrop.StaticOverlayTexture:IsShown()
		addon.general.squareMinimapHousingBackdropFrame:SetShown(show)
		if show then
			if _G.EQOLBORDER then _G.EQOLBORDER:SetFrameLevel(5) end
		else
			if _G.EQOLBORDER then _G.EQOLBORDER:SetFrameLevel(Minimap:GetFrameLevel() or 2) end
		end

		if not addon.variables.squareMinimapHousingBackdropHooked then
			MinimapBackdrop.StaticOverlayTexture:HookScript("OnShow", addon.functions.applySquareMinimapHousingBackdrop)
			MinimapBackdrop.StaticOverlayTexture:HookScript("OnHide", addon.functions.applySquareMinimapHousingBackdrop)
			addon.variables.squareMinimapHousingBackdropHooked = true
		end
	end

	-- Apply border at startup
	C_Timer.After(0, function()
		if addon.functions.applySquareMinimapBorder then addon.functions.applySquareMinimapBorder() end
		if addon.functions.applySquareMinimapHousingBackdrop then addon.functions.applySquareMinimapHousingBackdrop() end
	end)

	function addon.functions.applyMinimapClusterClamp()
		if not MinimapCluster or not MinimapCluster.SetClampedToScreen then return end
		if addon.db and addon.db.unclampMinimapCluster then
			MinimapCluster:SetClampedToScreen(false)
		else
			MinimapCluster:SetClampedToScreen(true)
		end
	end

	if addon.functions.applyMinimapClusterClamp then addon.functions.applyMinimapClusterClamp() end

	function addon.functions.applyMinimapClusterScale()
		if not MinimapCluster or not MinimapCluster.SetScale then return end
		if addon.db and addon.db.enableMinimapClusterScale then
			local scale = tonumber(addon.db.minimapClusterScale) or 1
			if scale < 0.5 then
				scale = 0.5
			elseif scale > 2 then
				scale = 2
			end
			MinimapCluster:SetScale(scale)
		else
			MinimapCluster:SetScale(1)
		end
	end

	if addon.functions.applyMinimapClusterScale then addon.functions.applyMinimapClusterScale() end

	function addon.functions.toggleMinimapButton(value)
		if value == false then
			LDBIcon:Show(addonName)
		else
			LDBIcon:Hide(addonName)
		end
	end
	function addon.functions.toggleZoneText(value, ignore)
		if value then
			ZoneTextFrame:UnregisterAllEvents()
			ZoneTextFrame:Hide()
		elseif not ignore then
			addon.variables.requireReload = true
		end
	end
	addon.functions.toggleZoneText(addon.db["hideZoneText"], true)

	function addon.functions.toggleScreenshotStatus(value)
		local actionStatus = _G.ActionStatus
		if not actionStatus or not actionStatus.UnregisterEvent or not actionStatus.RegisterEvent then return end
		if value then
			actionStatus:UnregisterEvent("SCREENSHOT_STARTED")
			actionStatus:UnregisterEvent("SCREENSHOT_SUCCEEDED")
			actionStatus:UnregisterEvent("SCREENSHOT_FAILED")
			if actionStatus.Hide then actionStatus:Hide() end
		else
			actionStatus:RegisterEvent("SCREENSHOT_STARTED")
			actionStatus:RegisterEvent("SCREENSHOT_SUCCEEDED")
			actionStatus:RegisterEvent("SCREENSHOT_FAILED")
		end
	end
	addon.functions.toggleScreenshotStatus(addon.db["hideScreenshotStatus"])

	function addon.functions.toggleQuickJoinToastButton(value)
		if value == false then
			QuickJoinToastButton:Show()
		else
			QuickJoinToastButton:Hide()
		end
	end
	addon.functions.toggleQuickJoinToastButton(addon.db["hideQuickJoinToast"])

	local function getTrainAllSummary()
		if not GetNumTrainerServices or not GetTrainerServiceInfo then return 0, 0 end
		local count, cost = 0, 0
		local numServices = GetNumTrainerServices() or 0
		for i = 1, numServices do
			local _, serviceType = GetTrainerServiceInfo(i)
			if serviceType == "available" then
				count = count + 1
				local price = GetTrainerServiceCost(i)
				if price then cost = cost + price end
			end
		end
		return count, cost
	end

	local function updateTrainAllButtonState()
		local button = addon.variables and addon.variables.trainAllButton
		if not button then return end
		if not addon.db or not addon.db.showTrainAllButton then
			button:Hide()
			return
		end
		local count = select(1, getTrainAllSummary())
		button:SetEnabled(count > 0)
		if button:IsMouseOver() then
			if count > 0 then
				local onEnter = button:GetScript("OnEnter")
				if onEnter then onEnter(button) end
			elseif GameTooltip and GameTooltip:IsOwned(button) then
				GameTooltip_Hide()
			end
		end
	end

	function addon.functions.applyTrainAllButton()
		if not addon.db or not addon.db.showTrainAllButton then
			if addon.variables and addon.variables.trainAllButton then addon.variables.trainAllButton:Hide() end
			return
		end

		EventUtil.ContinueOnAddOnLoaded("Blizzard_TrainerUI", function()
			if not addon.db or not addon.db.showTrainAllButton then return end
			if not ClassTrainerFrame or not ClassTrainerTrainButton then return end
			addon.variables = addon.variables or {}
			local button = addon.variables.trainAllButton
			if not button then
				button = CreateFrame("Button", "EQOLTrainAllButton", ClassTrainerFrame, "MagicButtonTemplate")
				button:SetText((L and L["trainAllButtonLabel"]) or "Train All")
				button:SetHeight(ClassTrainerTrainButton:GetHeight() or 22)
				button:SetScript("OnClick", function()
					for i = 1, GetNumTrainerServices() do
						local _, serviceType = GetTrainerServiceInfo(i)
						if serviceType == "available" then BuyTrainerService(i) end
					end
				end)
				button:SetScript("OnEnter", function(self)
					local count, cost = getTrainAllSummary()
					if count <= 0 then return end
					GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
					GameTooltip:ClearLines()
					local template = (count == 1 and L and L["trainAllButtonTooltipSingle"]) or (L and L["trainAllButtonTooltipMulti"])
					if template then
						local moneyString = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString and C_CurrencyInfo.GetCoinTextureString(cost) or GetCoinTextureString(cost)
						GameTooltip:AddLine(template:format(count, moneyString))
						GameTooltip:Show()
					end
				end)
				button:SetScript("OnLeave", GameTooltip_Hide)
				addon.variables.trainAllButton = button
			end

			button:ClearAllPoints()
			button:SetPoint("RIGHT", ClassTrainerTrainButton, "LEFT", -1, 0)

			local fontString = button.GetFontString and button:GetFontString()
			if fontString then fontString:SetWordWrap(false) end
			local baseWidth = (fontString and fontString:GetStringWidth() or 0) + 20
			local minWidth = 80
			if baseWidth < minWidth then baseWidth = minWidth end
			button:SetWidth(baseWidth)

			if ClassTrainerFrameMoneyBg then
				local gap = ClassTrainerFrame:GetWidth() - ClassTrainerFrameMoneyBg:GetWidth() - ClassTrainerTrainButton:GetWidth() - 13
				if gap > 0 and button:GetWidth() > gap then
					button:SetWidth(gap)
					if fontString then fontString:SetWidth(gap - 10) end
				end
			end

			button:Show()

			if not addon.variables.trainAllButtonHooked then
				hooksecurefunc("ClassTrainerFrame_Update", updateTrainAllButtonState)
				addon.variables.trainAllButtonHooked = true
			end
			updateTrainAllButtonState()
		end)
	end

	if addon.functions.applyTrainAllButton then addon.functions.applyTrainAllButton() end

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
					f._eqolMinimapHidden = true
				elseif f._eqolMinimapHidden then
					f._eqolMinimapHidden = nil
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

	local eventFrame = CreateFrame("Frame")
	eventFrame:SetScript("OnUpdate", function(self)
		addon.functions.toggleMinimapButton(addon.db["hideMinimapButton"])
		self:SetScript("OnUpdate", nil)
	end)

	local ICON_SIZE = 32
	local PADDING = 4
	local BUTTON_SINK_ANCHORS = {
		TOPLEFT = { bag = "BOTTOMRIGHT", button = "TOPLEFT" },
		TOPRIGHT = { bag = "BOTTOMLEFT", button = "TOPRIGHT" },
		BOTTOMLEFT = { bag = "TOPRIGHT", button = "BOTTOMLEFT" },
		BOTTOMRIGHT = { bag = "TOPLEFT", button = "BOTTOMRIGHT" },
		TOP = { bag = "BOTTOM", button = "TOP" },
		BOTTOM = { bag = "TOP", button = "BOTTOM" },
		LEFT = { bag = "RIGHT", button = "LEFT" },
		RIGHT = { bag = "LEFT", button = "RIGHT" },
	}
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

		local bLeft = anchorButton:GetLeft() or 0
		local bRight = anchorButton:GetRight() or 0
		local bTop = anchorButton:GetTop() or 0
		local bBottom = anchorButton:GetBottom() or 0
		local bCenterX = (bLeft + bRight) / 2
		local bCenterY = (bTop + bBottom) / 2

		local screenWidth = GetScreenWidth()
		local screenHeight = GetScreenHeight()

		local bagWidth = bagFrame:GetWidth()
		local bagHeight = bagFrame:GetHeight()

		local preferredAnchor = "AUTO"
		if bagFrame == addon.variables.buttonSink and addon.db and type(addon.db.buttonSinkAnchorPreference) == "string" then preferredAnchor = string.upper(addon.db.buttonSinkAnchorPreference) end

		local function getButtonPointCoords(point)
			if point == "TOPLEFT" then return bLeft, bTop end
			if point == "TOPRIGHT" then return bRight, bTop end
			if point == "BOTTOMLEFT" then return bLeft, bBottom end
			if point == "BOTTOMRIGHT" then return bRight, bBottom end
			if point == "TOP" then return bCenterX, bTop end
			if point == "BOTTOM" then return bCenterX, bBottom end
			if point == "LEFT" then return bLeft, bCenterY end
			if point == "RIGHT" then return bRight, bCenterY end
		end

		local function calculateBounds(bagPoint, btnPoint)
			local anchorX, anchorY = getButtonPointCoords(btnPoint)
			if not anchorX then return end
			if bagPoint == "TOPLEFT" then return anchorX, anchorX + bagWidth, anchorY, anchorY - bagHeight end
			if bagPoint == "TOPRIGHT" then return anchorX - bagWidth, anchorX, anchorY, anchorY - bagHeight end
			if bagPoint == "BOTTOMLEFT" then return anchorX, anchorX + bagWidth, anchorY + bagHeight, anchorY end
			if bagPoint == "BOTTOMRIGHT" then return anchorX - bagWidth, anchorX, anchorY + bagHeight, anchorY end
			if bagPoint == "TOP" then return anchorX - bagWidth / 2, anchorX + bagWidth / 2, anchorY, anchorY - bagHeight end
			if bagPoint == "BOTTOM" then return anchorX - bagWidth / 2, anchorX + bagWidth / 2, anchorY + bagHeight, anchorY end
			if bagPoint == "LEFT" then return anchorX, anchorX + bagWidth, anchorY + bagHeight / 2, anchorY - bagHeight / 2 end
			if bagPoint == "RIGHT" then return anchorX - bagWidth, anchorX, anchorY + bagHeight / 2, anchorY - bagHeight / 2 end
		end

		local function fitsOnScreen(left, right, top, bottom)
			if not left then return false end
			return left >= 0 and right <= screenWidth and top <= screenHeight and bottom >= 0
		end

		local pointOnBag, pointOnButton
		local anchorConfig = BUTTON_SINK_ANCHORS[preferredAnchor]
		if anchorConfig then
			local left, right, top, bottom = calculateBounds(anchorConfig.bag, anchorConfig.button)
			if fitsOnScreen(left, right, top, bottom) then
				pointOnBag = anchorConfig.bag
				pointOnButton = anchorConfig.button
			end
		end

		if not pointOnBag or not pointOnButton then
			pointOnBag = "BOTTOMRIGHT"
			pointOnButton = "TOPLEFT"

			if (bTop + bagHeight) > screenHeight then
				pointOnBag = "TOPRIGHT"
				pointOnButton = "BOTTOMLEFT"
			end

			if (bLeft - bagWidth) < 0 then
				if pointOnBag == "BOTTOMRIGHT" then
					pointOnBag = "BOTTOMLEFT"
					pointOnButton = "TOPRIGHT"
				else
					pointOnBag = "TOPLEFT"
					pointOnButton = "BOTTOMRIGHT"
				end
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
			C_Timer.After(2, function()
				addon.functions.gatherMinimapButtons()
				addon.functions.LayoutButtons()
			end)
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

	local function setLibDBIconMouseover(name, enable, button)
		if not name then return end
		addon.variables = addon.variables or {}

		local function getManualMouseoverButtons()
			if not addon.variables.eqolManualMouseoverButtons then addon.variables.eqolManualMouseoverButtons = setmetatable({}, { __mode = "k" }) end
			return addon.variables.eqolManualMouseoverButtons
		end

		local function ensureManualMouseoverHooks()
			if addon.variables.eqolManualMouseoverHooked or not Minimap or not Minimap.HookScript then return end
			addon.variables.eqolManualMouseoverHooked = true
			Minimap:HookScript("OnEnter", function()
				local buttons = addon.variables.eqolManualMouseoverButtons
				if not buttons then return end
				for btn in pairs(buttons) do
					if btn and btn.eqolShowOnMouseover then
						if btn.eqolFadeOut then btn.eqolFadeOut:Stop() end
						btn:SetAlpha(1)
					end
				end
			end)
			Minimap:HookScript("OnLeave", function()
				local buttons = addon.variables.eqolManualMouseoverButtons
				if not buttons then return end
				for btn in pairs(buttons) do
					if btn and btn.eqolShowOnMouseover then
						if btn.eqolFadeOut then
							btn.eqolFadeOut:Play()
						else
							btn:SetAlpha(0)
						end
					end
				end
			end)
		end

		local function ensureManualFade(btn)
			if not btn or btn.eqolFadeOut then return end
			local fade = btn:CreateAnimationGroup()
			local animOut = fade:CreateAnimation("Alpha")
			animOut:SetOrder(1)
			animOut:SetDuration(0.2)
			animOut:SetFromAlpha(1)
			animOut:SetToAlpha(0)
			animOut:SetStartDelay(1)
			fade:SetToFinalAlpha(true)
			btn.eqolFadeOut = fade
		end

		local function setManualMinimapMouseover(btn, on)
			if not btn or not btn.SetAlpha then return end
			local list = getManualMouseoverButtons()
			btn.eqolShowOnMouseover = on and true or false
			if on then
				ensureManualFade(btn)
				list[btn] = true
				if btn.eqolFadeOut then btn.eqolFadeOut:Stop() end
				btn:SetAlpha(0)
			else
				list[btn] = nil
				if btn.eqolFadeOut then btn.eqolFadeOut:Stop() end
				btn:SetAlpha(1)
			end
			if not btn.eqolMouseoverHooked then
				btn:HookScript("OnEnter", function(self)
					if self.eqolShowOnMouseover then
						if self.eqolFadeOut then self.eqolFadeOut:Stop() end
						self:SetAlpha(1)
					end
				end)
				btn:HookScript("OnLeave", function(self)
					if self.eqolShowOnMouseover then
						if self.eqolFadeOut then
							self.eqolFadeOut:Play()
						else
							self:SetAlpha(0)
						end
					end
				end)
				btn.eqolMouseoverHooked = true
			end
			ensureManualMouseoverHooks()
		end

		if LDBIcon and LDBIcon.ShowOnEnter then
			local ldbButton = LDBIcon.GetMinimapButton and LDBIcon:GetMinimapButton(name)
			if ldbButton then
				LDBIcon:ShowOnEnter(name, enable)
			else
				setManualMinimapMouseover(button, enable)
			end
			return
		end

		if not button then return end
		button.showOnMouseover = enable and true or false
		if button.fadeOut then button.fadeOut:Stop() end
		if enable then
			button:SetAlpha(0)
		else
			button:SetAlpha(1)
		end
	end
	function addon.functions.LayoutButtons()
		if addon.db["enableMinimapButtonBin"] then
			local columns = tonumber(addon.db["minimapButtonBinColumns"]) or DEFAULT_BUTTON_SINK_COLUMNS
			columns = math.floor(columns + 0.5)
			if columns < 1 then
				columns = 1
			elseif columns > 99 then
				columns = 99
			end
			if addon.variables.buttonSink then
				local index = 0
				local orderedNames = {}
				for name in pairs(addon.variables.bagButtons) do
					orderedNames[#orderedNames + 1] = name
				end
				table.sort(orderedNames, function(a, b)
					local aKey = string.lower(a or "")
					local bKey = string.lower(b or "")
					if aKey == bKey then return (a or "") < (b or "") end
					return aKey < bKey
				end)
				for _, name in ipairs(orderedNames) do
					local button = addon.variables.bagButtons[name]
					if addon.db["ignoreMinimapButtonBin_" .. name] then
						if addon.db.minimapButtonsMouseover then setLibDBIconMouseover(name, true, button) end
						button:ClearAllPoints()
						button:SetParent(Minimap)
						if addon.variables.bagButtonPoint[name] then
							local pData = addon.variables.bagButtonPoint[name]
							if pData.point and pData.relativePoint and pData.relativeTo and pData.xOfs and pData.yOfs then
								button:SetPoint(pData.point, pData.relativeTo, pData.relativePoint, pData.xOfs, pData.yOfs)
							end
							button:SetFrameStrata(pData.strata or "MEDIUM")
							if pData.level then button:SetFrameLevel(pData.level) end
						end
					elseif addon.variables.bagButtonState[name] then
						if addon.db.minimapButtonsMouseover then setLibDBIconMouseover(name, false, button) end
						index = index + 1
						button:ClearAllPoints()
						local col = (index - 1) % columns
						local row = math.floor((index - 1) / columns)

						button:SetParent(addon.variables.buttonSink)
						button:SetFrameStrata("DIALOG")
						button:SetFrameLevel(100)
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
					button:SetFrameStrata(pData.strata or "MEDIUM")
					if pData.level then button:SetFrameLevel(pData.level) end
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
						or btnName:match("^TTMinimapButton")
						or btnName == addonName .. "_ButtonSinkMap"
						or btnName == "ZygorGuidesViewerMapIcon"
					)
				then
					local pData = addon.variables.bagButtonPoint[btnName] or {}
					if not pData.point then
						local point, relativeTo, relativePoint, xOfs, yOfs = child:GetPoint()
						pData.point = point
						pData.relativeTo = relativeTo
						pData.relativePoint = relativePoint
						pData.xOfs = xOfs
						pData.yOfs = yOfs
					end
					pData.strata = pData.strata or child:GetFrameStrata()
					pData.level = pData.level or child:GetFrameLevel()
					addon.variables.bagButtonPoint[btnName] = pData
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

	local function shouldEnableMinimapButtonMouseover() return addon.db and addon.db.minimapButtonsMouseover end
	function addon.functions.applyMinimapButtonMouseover()
		if not LDBIcon then return end

		addon.functions.gatherMinimapButtons()

		addon.variables = addon.variables or {}
		local enable = shouldEnableMinimapButtonMouseover()
		for name, button in pairs(addon.variables.bagButtons) do
			local enableit = enable
			if addon.db["enableMinimapButtonBin"] and not addon.db["ignoreMinimapButtonBin_" .. name] then enableit = false end
			setLibDBIconMouseover(name, enableit, button)
		end
		if not addon.variables.minimapButtonMouseoverHooked then
			if LDBIcon.RegisterCallback then
				LDBIcon.RegisterCallback(addon, "LibDBIcon_IconCreated", function(_, button, name)
					if shouldEnableMinimapButtonMouseover() then setLibDBIconMouseover(name, true) end
				end)
			else
				hooksecurefunc(LDBIcon, "Register", function(self, name)
					if shouldEnableMinimapButtonMouseover() then setLibDBIconMouseover(name, true) end
				end)
			end
			addon.variables.minimapButtonMouseoverHooked = true
		end
	end
	if addon.functions.applyMinimapButtonMouseover then addon.functions.applyMinimapButtonMouseover() end

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
				local cur = C_SpecializationInfo.GetSpecialization()
				if index > 0 and cur and cur == index then return end
				C_SpecializationInfo.SetSpecialization(index)
			end
		end)

		row.radio:SetScript("OnClick", function(self, button)
			if button == "LeftButton" then
				SetLootSpecialization(specId)
			else
				local cur = C_SpecializationInfo.GetSpecialization()
				if index > 0 and cur and cur == index then return end
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

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:ClearLines()
		GameTooltip:AddLine(L["Instant Catalyst"])
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

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

local function OpenSettingsRoot()
	if not (Settings and Settings.OpenToCategory) then return end
	if not (addon.SettingsLayout and addon.SettingsLayout.rootCategory) then return end

	if InCombatLockdown and InCombatLockdown() then
		addon.variables = addon.variables or {}
		addon.variables.pendingSettingsOpen = true
		return
	end

	addon.variables = addon.variables or {}
	addon.variables.pendingSettingsOpen = nil
	Settings.OpenToCategory(addon.SettingsLayout.rootCategory:GetID())
end

addon.functions.OpenSettingsRoot = OpenSettingsRoot

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
	local function QuickMenuGenerator(_, root)
		local first = true
		local function DoDevider()
			if not first then
				root:CreateDivider()
			else
				first = false
			end
		end
		if addon.db["enableLootToastFilter"] then
			first = false
			root:CreateTitle(L["SettingsLootHeaderToasts"])
			root:CreateButton(L["SettingsLootAddInclude"], function() local dialog = StaticPopup_Show("EQOL_LOOT_INCLUDE_ADD") end)
			root:CreateButton(OPTIONS, function() Settings.OpenToCategory(addon.SettingsLayout.vendorEconomyCalootCategorytegory:GetID(), L["enableLootToastFilter"]) end)
		end

		DoDevider()
		root:CreateTitle(L["DataPanel"])
		root:CreateButton(L["SettingsDataPanelCreate"], function() local dialog = StaticPopup_Show("EQOL_CREATE_DATAPANEL") end)

		if addon.db["enableChatHistory"] and addon.ChatIM and addon.ChatIM.ChannelHistory then
			DoDevider()
			root:CreateButton(L["CH_TITLE_HISTORY"], function()
				if addon.ChatIM.ChannelHistory.ToggleWindow then addon.ChatIM.ChannelHistory:ToggleWindow() end
			end)
		end

		DoDevider()
		root:CreateButton(L["CooldownPanelEditor"] or "Cooldown Panel Editor", function()
			if addon.Aura and addon.Aura.CooldownPanels and addon.Aura.CooldownPanels.OpenEditor then addon.Aura.CooldownPanels:OpenEditor() end
		end)
		--@debug@
		root:CreateButton(L["VisibilityEditor"] or "Visibility Configurator", function()
			if addon.Visibility and addon.Visibility.OpenEditor then addon.Visibility:OpenEditor() end
		end)
		--@end-debug@
	end

	-- Datenobjekt fr den Minimap-Button
	local EnhanceQoLLDB = LDB:NewDataObject("EnhanceQoL", {
		type = "launcher",
		text = addonName,
		icon = "Interface\\AddOns\\" .. addonName .. "\\Icons\\Icon.tga", -- Hier kannst du dein eigenes Icon verwenden
		OnClick = function(_, msg)
			if msg == "LeftButton" then
				OpenSettingsRoot()
			else
				MenuUtil.CreateContextMenu(UIParent, QuickMenuGenerator)
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
		func = function(button, menuInputData, menu) OpenSettingsRoot() end,
		funcOnEnter = function(button)
			MenuUtil.ShowTooltip(button, function(tooltip) tooltip:SetText(L["Left-Click to show options"]) end)
		end,
		funcOnLeave = function(button) MenuUtil.HideTooltip(button) end,
	})
end

local ensureClassResourceHideHook

local function updateClassResourceVisibility()
	if not addon.db then return end
	local ufActive = addon.db.ufFrames and addon.db.ufFrames.player and addon.db.ufFrames.player.enabled
	local _, classTag = UnitClass("player")
	if not classTag then return end
	if ensureClassResourceHideHook then ensureClassResourceHideHook() end

	local function apply(frame, hideKey)
		if not frame then return end
		if addon.db[hideKey] and not ufActive then frame:Hide() end
	end

	if classTag == "DEATHKNIGHT" then
		apply(RuneFrame, "deathknight_HideRuneFrame")
	elseif classTag == "DRUID" then
		apply(DruidComboPointBarFrame, "druid_HideComboPoint")
	elseif classTag == "EVOKER" then
		apply(EssencePlayerFrame, "evoker_HideEssence")
	elseif classTag == "MONK" then
		apply(MonkHarmonyBarFrame, "monk_HideHarmonyBar")
	elseif classTag == "ROGUE" then
		apply(RogueComboPointBarFrame, "rogue_HideComboPoint")
	elseif classTag == "PALADIN" then
		apply(PaladinPowerBarFrame, "paladin_HideHolyPower")
	elseif classTag == "WARLOCK" then
		apply(WarlockPowerFrame, "warlock_HideSoulShardBar")
	end
end

addon.functions.UpdateClassResourceVisibility = updateClassResourceVisibility

local classResourceHideHooks = {}
local classResourceHideConfig = {
	DEATHKNIGHT = { frameName = "RuneFrame", hideKey = "deathknight_HideRuneFrame" },
	DRUID = { frameName = "DruidComboPointBarFrame", hideKey = "druid_HideComboPoint" },
	EVOKER = { frameName = "EssencePlayerFrame", hideKey = "evoker_HideEssence" },
	MONK = { frameName = "MonkHarmonyBarFrame", hideKey = "monk_HideHarmonyBar" },
	ROGUE = { frameName = "RogueComboPointBarFrame", hideKey = "rogue_HideComboPoint" },
	PALADIN = { frameName = "PaladinPowerBarFrame", hideKey = "paladin_HideHolyPower" },
	WARLOCK = { frameName = "WarlockPowerFrame", hideKey = "warlock_HideSoulShardBar" },
}

local function isPlayerUFActive() return addon.db and addon.db.ufFrames and addon.db.ufFrames.player and addon.db.ufFrames.player.enabled end

local function shouldHideClassResource(hideKey) return addon.db and addon.db[hideKey] and not isPlayerUFActive() end

ensureClassResourceHideHook = function()
	local _, classTag = UnitClass("player")
	local cfg = classTag and classResourceHideConfig[classTag]
	if not cfg or not addon.db or not addon.db[cfg.hideKey] then return end
	if classResourceHideHooks[cfg.hideKey] then return end
	local frame = _G[cfg.frameName]
	if not frame then return end
	classResourceHideHooks[cfg.hideKey] = true
	hooksecurefunc(frame, "Show", function(self)
		if shouldHideClassResource(cfg.hideKey) then self:Hide() end
	end)
end

local function setAllHooks()
	updateClassResourceVisibility()

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
		if addon.functions.isRestrictedContent() then return end
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
	addon.functions.initDungeonFrame()
	addon.functions.initGearUpgrade()
	addon.functions.initUIInput()
	addon.functions.initQuest()
	addon.functions.initDataPanel()
	addon.functions.initProfile()
	addon.functions.initMapNav()
	addon.functions.initChatFrame()
	addon.functions.initUIOptions()
	addon.functions.initActionTracker()
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
					if addon.ChatIM and addon.ChatIM.BuildSoundTable then addon.ChatIM:BuildSoundTable() end
				end)
			end
		elseif mediaType == "statusbar" then
			-- When new statusbar textures are registered, refresh any UI using them
			if addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.MarkTextureListDirty then addon.Aura.ResourceBars.MarkTextureListDirty() end
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.RefreshPotionTextureDropdown then addon.MythicPlus.functions.RefreshPotionTextureDropdown() end
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.applyPotionBarTexture then addon.MythicPlus.functions.applyPotionBarTexture() end
			if addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.RefreshTextureDropdown then addon.Aura.ResourceBars.RefreshTextureDropdown() end
		elseif mediaType == "border" then
			if ActionBarLabels and ActionBarLabels.ResetBorderCache then ActionBarLabels.ResetBorderCache() end
		end
	end)

	-- Init modules
	if addon.Aura and addon.Aura.functions then
		if addon.Aura.functions.InitDB then addon.Aura.functions.InitDB() end
		if addon.Aura.functions.InitResourceBars then addon.Aura.functions.InitResourceBars() end
		if addon.Aura.functions.InitUnitFrames then addon.Aura.functions.InitUnitFrames() end
	end
	if addon.Drinks and addon.Drinks.functions then
		if addon.Drinks.functions.InitDrinkMacro then addon.Drinks.functions.InitDrinkMacro() end
		if addon.Drinks.functions.InitFoodReminder then addon.Drinks.functions.InitFoodReminder() end
	end
	if addon.Health and addon.Health.functions and addon.Health.functions.InitHealthMacro then addon.Health.functions.InitHealthMacro() end
	if addon.Mouse and addon.Mouse.functions then
		if addon.Mouse.functions.InitDB then addon.Mouse.functions.InitDB() end
		if addon.Mouse.functions.InitState then addon.Mouse.functions.InitState() end
	end
	if addon.Mover and addon.Mover.functions then
		if addon.Mover.functions.InitDB then addon.Mover.functions.InitDB() end
		if addon.Mover.functions.InitRegistry then addon.Mover.functions.InitRegistry() end
		if addon.Mover.functions.InitSettings then addon.Mover.functions.InitSettings() end
	end
	if addon.Skinner and addon.Skinner.functions then
		if addon.Skinner.functions.InitDB then addon.Skinner.functions.InitDB() end
	end
	if addon.MythicPlus and addon.MythicPlus.functions then
		if addon.MythicPlus.functions.InitDB then addon.MythicPlus.functions.InitDB() end
		if addon.MythicPlus.functions.InitState then addon.MythicPlus.functions.InitState() end
	end
	if addon.Sounds and addon.Sounds.functions then
		if addon.Sounds.functions.InitDB then addon.Sounds.functions.InitDB() end
		if addon.Sounds.functions.InitState then addon.Sounds.functions.InitState() end
	end
	if addon.Tooltip and addon.Tooltip.functions then
		if addon.Tooltip.functions.InitDB then addon.Tooltip.functions.InitDB() end
		if addon.Tooltip.functions.InitState then addon.Tooltip.functions.InitState() end
	end
	if addon.Visibility and addon.Visibility.functions then
		if addon.Visibility.functions.InitDB then addon.Visibility.functions.InitDB() end
		if addon.Visibility.functions.InitState then addon.Visibility.functions.InitState() end
	end
	if addon.Vendor and addon.Vendor.functions then
		if addon.Vendor.functions.InitDB then addon.Vendor.functions.InitDB() end
		if addon.Vendor.functions.InitState then addon.Vendor.functions.InitState() end
		if addon.Vendor.functions.InitSettings then addon.Vendor.functions.InitSettings() end
	end
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
	SlashCmdList["ENHANCEQOL"] = function(msg)
		if msg:match("^aag%s*(%d+)$") then
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
			OpenSettingsRoot()
		end
	end
end

-- Erstelle ein Frame f��r Events
local frameLoad = CreateFrame("Frame")

local gossipClicked = {}

local function isQuestAutomationModifierHeld(modifier)
	if modifier == "SHIFT" then return IsShiftKeyDown() end
	if modifier == "CTRL" then return IsControlKeyDown() end
	if modifier == "ALT" then return IsAltKeyDown() end
	return false
end

local function shouldAutoChooseQuest()
	if not addon.db or not addon.db["autoChooseQuest"] then return false end
	local modifier = addon.db["autoChooseQuestModifier"]
	if modifier == "SHIFT" or modifier == "CTRL" or modifier == "ALT" then return isQuestAutomationModifierHeld(modifier) end
	-- Legacy behavior: allow auto questing unless Shift is held
	return not IsShiftKeyDown()
end

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
	["ACTIVE_TALENT_GROUP_CHANGED"] = function(arg1)
		local uSpec = C_SpecializationInfo.GetSpecialization()
		if uSpec and uSpec > 0 then
			addon.variables.unitSpec = uSpec
			local specId, specName = C_SpecializationInfo.GetSpecializationInfo(addon.variables.unitSpec)
			addon.variables.unitSpecName = specName
			addon.variables.unitRole = GetSpecializationRole(addon.variables.unitSpec)
			addon.variables.unitSpecId = specId
		end
	end,
	["ADDON_LOADED"] = function(arg1)
		if arg1 == addonName then
			local legacy = {}
			EnhanceQoLDB = EnhanceQoLDB or {}
			if EnhanceQoLDB and not EnhanceQoLDB.profiles then
				for k, v in pairs(EnhanceQoLDB) do
					legacy[k] = v
				end
				EnhanceQoLDB.profiles = {
					["Default"] = {},
				}
			end

			local defaultProfile = "Default"

			if not EnhanceQoLDB.profileKeys then EnhanceQoLDB.profileKeys = {} end
			local name, realm = UnitName("player"), GetRealmName()

			-- check for global profile
			if EnhanceQoLDB.profileGlobal then
				defaultProfile = EnhanceQoLDB.profileGlobal
			else
				EnhanceQoLDB.profileGlobal = defaultProfile
			end

			if EnhanceQoLDB.profileKeys[UnitGUID("player")] then
				defaultProfile = EnhanceQoLDB.profileKeys[UnitGUID("player")]
			elseif EnhanceQoLDB.profileKeys[name .. " - " .. realm] then
				-- Legacy AceDB transform to new model
				EnhanceQoLDB.profileKeys[UnitGUID("player")] = EnhanceQoLDB.profileKeys[name .. " - " .. realm]
				EnhanceQoLDB.profileKeys[name .. " - " .. realm] = nil
				defaultProfile = EnhanceQoLDB.profileKeys[UnitGUID("player")]
			else
				defaultProfile = EnhanceQoLDB.profileGlobal
				EnhanceQoLDB.profileKeys[UnitGUID("player")] = defaultProfile
			end

			if not EnhanceQoLDB.profiles[defaultProfile] or type(EnhanceQoLDB.profiles[defaultProfile]) ~= "table" then EnhanceQoLDB.profiles[defaultProfile] = {} end

			addon.db = EnhanceQoLDB.profiles[defaultProfile]

			if next(legacy) then
				for k, v in pairs(legacy) do
					if addon.db[k] == nil then addon.db[k] = v end
					EnhanceQoLDB[k] = nil
				end
			end

			if addon.functions.CleanupOldStuff then addon.functions.CleanupOldStuff() end
			if addon.functions.initializePersistentCVars then addon.functions.initializePersistentCVars() end

			loadMain()
			EQOL.PersistSignUpNote()

			--@debug@
			loadSubAddon("EnhanceQoLQuery")
			--@end-debug@
			loadSubAddon("EnhanceQoLSharedMedia")

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
		if shouldAutoChooseQuest() then
			local ignored = addon.db and addon.db["ignoredQuestNPC"]
			local npcId = addon.functions.getIDFromGUID(UnitGUID("npc"))
			if npcId and ignored and ignored[npcId] then return end

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
	["CONFIRM_SUMMON"] = function()
		if not addon.db["autoAcceptSummon"] then return end
		if UnitAffectingCombat("player") then return end
		local summonInfo = _G.C_SummonInfo
		if not summonInfo or not summonInfo.ConfirmSummon then return end

		C_Timer.After(0, function()
			if not addon.db or not addon.db["autoAcceptSummon"] then return end
			if UnitAffectingCombat("player") then return end
			local info = _G.C_SummonInfo
			if not info then return end
			if not info.GetSummonConfirmTimeLeft or info.GetSummonConfirmTimeLeft() <= 0 then return end
			if not info.GetSummonConfirmSummoner or not info.GetSummonConfirmSummoner() then return end

			info.ConfirmSummon()
			StaticPopup_Hide("CONFIRM_SUMMON")
			StaticPopup_Hide("CONFIRM_SUMMON_SCENARIO")
			StaticPopup_Hide("CONFIRM_SUMMON_STARTING_AREA")
		end)
	end,
	["RESURRECT_REQUEST"] = function(offerer)
		if not shouldAutoAcceptResurrection(offerer) then return end
		AcceptResurrect()
		StaticPopup_Hide("RESURRECT")
		StaticPopup_Hide("RESURRECT_NO_SICKNESS")
		StaticPopup_Hide("RESURRECT_NO_TIMER")
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
		addon.functions.applyUIScalePreset()

		addon.variables.screenHeight = GetScreenHeight()

		if addon.db["enableMinimapButtonBin"] then addon.functions.toggleButtonSink() end
		if addon.db["actionBarAnchorEnabled"] then RefreshAllActionBarAnchors() end
		addon.variables.unitSpec = C_SpecializationInfo.GetSpecialization()
		if addon.variables.unitSpec then
			local specId, specName = C_SpecializationInfo.GetSpecializationInfo(addon.variables.unitSpec)
			addon.variables.unitSpecName = specName
			addon.variables.unitRole = GetSpecializationRole(addon.variables.unitSpec)
			addon.variables.unitSpecId = specId
		end

		if not addon.variables.maxLevel then addon.variables.maxLevel = GetMaxLevelForPlayerExpansion() end
		addon.variables.isMaxLevel = {}
		addon.variables.isMaxLevel[addon.variables.maxLevel] = true

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
		if addon.Aura and addon.Aura.functions then
			if addon.Aura.functions.InitCooldownPanels then addon.Aura.functions.InitCooldownPanels() end
		end
		if addon.MythicPlus and addon.MythicPlus.functions then
			if addon.MythicPlus.functions.InitSettings then addon.MythicPlus.functions.InitSettings() end
		end
	end,
	["PLAYER_MONEY"] = function()
		if addon.db["moneyTracker"] and addon.db["moneyTracker"][UnitGUID("player")] and addon.db["moneyTracker"][UnitGUID("player")]["money"] then
			addon.db["moneyTracker"][UnitGUID("player")]["money"] = GetMoney()
		end
	end,
	["ACCOUNT_MONEY"] = function() addon.db["warbandGold"] = C_Bank.FetchDepositedMoney(Enum.BankType.Account) end,
	["PLAYER_REGEN_ENABLED"] = function()
		if addon.variables then
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
			if addon.variables.pendingExtraActionArtwork then
				addon.variables.pendingExtraActionArtwork = nil
				if addon.functions.ApplyExtraActionArtworkSetting then addon.functions.ApplyExtraActionArtworkSetting() end
			end
			if addon.variables.pendingSettingsOpen then OpenSettingsRoot() end
		end
	end,
	["QUEST_COMPLETE"] = function()
		if shouldAutoChooseQuest() then
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
			local ignored = addon.db and addon.db["ignoredQuestNPC"]
			local npcId = addon.functions.getIDFromGUID(UnitGUID("npc"))
			if npcId and ignored and ignored[npcId] then return end
			if addon.db["ignoreDailyQuests"] and addon.functions.IsQuestRepeatableType(arg1) then return end
			if addon.db["ignoreTrivialQuests"] and C_QuestLog.IsQuestTrivial(arg1) then return end
			if addon.db["ignoreWarbandCompleted"] and C_QuestLog.IsQuestFlaggedCompletedOnAccount(arg1) then return end

			AcceptQuest()
			if QuestFrame:IsShown() then QuestFrame:Hide() end -- Sometimes the frame is still stuck - hide it forcefully than
		end
	end,
	["QUEST_DETAIL"] = function()
		if shouldAutoChooseQuest() then
			local ignored = addon.db and addon.db["ignoredQuestNPC"]
			local npcId = addon.functions.getIDFromGUID(UnitGUID("npc"))
			if npcId and ignored and ignored[npcId] then return end

			local id = GetQuestID()
			addon.variables.acceptQuestID[id] = true
			C_QuestLog.RequestLoadQuestByID(id)
		end
	end,
	["QUEST_GREETING"] = function()
		if shouldAutoChooseQuest() then
			local ignored = addon.db and addon.db["ignoredQuestNPC"]
			local npcId = addon.functions.getIDFromGUID(UnitGUID("npc"))
			if npcId and ignored and ignored[npcId] then return end
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
		if shouldAutoChooseQuest() and IsQuestCompletable() then CompleteQuest() end
	end,
	["AUCTION_HOUSE_SHOW"] = function()
		if addon.db["closeBagsOnAuctionHouse"] and not addon.functions.isRestrictedContent() then CloseAllBags() end
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
		if addon.db["autoCancelCinematic"] and not addon.db["quickSkipCinematic"] then
			if CinematicFrame.isRealCinematic then
				StopCinematic()
			elseif CanCancelScene() then
				CancelScene()
			end
		end
	end,
	["PLAY_MOVIE"] = function()
		if addon.db["autoCancelCinematic"] and not addon.db["quickSkipCinematic"] then MovieFrame:Hide() end
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
