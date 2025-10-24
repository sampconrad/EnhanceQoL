-- luacheck: globals DefaultCompactUnitFrameSetup CompactUnitFrame_UpdateAuras CompactUnitFrame_UpdateName UnitTokenFromGUID C_Bank
-- luacheck: globals HUD_EDIT_MODE_MINIMAP_LABEL
-- luacheck: globals Menu GameTooltip_SetTitle GameTooltip_AddNormalLine EnhanceQoL
-- luacheck: globals GenericTraitUI_LoadUI GenericTraitFrame
-- luacheck: globals CancelDuel DeclineGroup C_PetBattles
-- luacheck: globals ExpansionLandingPage ExpansionLandingPageMinimapButton ShowGarrisonLandingPage GarrisonLandingPage GarrisonLandingPage_Toggle GarrisonLandingPageMinimapButton CovenantSanctumFrame CovenantSanctumFrame_LoadUI EasyMenu
-- luacheck: globals ActionButton_UpdateRangeIndicator MAINMENU_BUTTON PlayerCastingBarFrame TargetFrameSpellBar FocusFrameSpellBar
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

local OPTIONS_FRAME_MIN_SCALE = 0.5
local OPTIONS_FRAME_MAX_SCALE = 2

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

local EQOL = select(2, ...)
EQOL.C = {}

-- localeadditions
local headerClassInfo = L["headerClassInfo"]:format(select(1, UnitClass("player")))
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

local function toggleGroupApplication(value)
	if value then
		-- Hide overlay and text label
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Label:Hide()
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Background:Hide()
		-- Hide the 3 animated texture icons
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Waitdot1:Hide()
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Waitdot2:Hide()
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Waitdot3:Hide()
	else
		-- Hide overlay and text label
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Label:Show()
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Background:Show()
		-- Hide the 3 animated texture icons
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Waitdot1:Show()
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Waitdot2:Show()
		_G.LFGListFrame.ApplicationViewer.UnempoweredCover.Waitdot3:Show()
	end
end

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

local lfgPoint, lfgRelativeTo, lfgRelativePoint, lfgXOfs, lfgYOfs

local function toggleLFGFilterPosition()
	if LFGListFrame and LFGListFrame.SearchPanel and LFGListFrame.SearchPanel.FilterButton and LFGListFrame.SearchPanel.FilterButton.ResetButton then
		if addon.db["groupfinderMoveResetButton"] then
			LFGListFrame.SearchPanel.FilterButton.ResetButton:ClearAllPoints()
			LFGListFrame.SearchPanel.FilterButton.ResetButton:SetPoint("TOPLEFT", LFGListFrame.SearchPanel.FilterButton, "TOPLEFT", -7, 13)
		else
			LFGListFrame.SearchPanel.FilterButton.ResetButton:ClearAllPoints()
			LFGListFrame.SearchPanel.FilterButton.ResetButton:SetPoint(lfgPoint, lfgRelativeTo, lfgRelativePoint, lfgXOfs, lfgYOfs)
		end
	end
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

local function removeLeaderIcon()
	if addon.variables.leaderFrame then
		addon.variables.leaderFrame:SetParent(nil)
		addon.variables.leaderFrame:Hide()
		addon.variables.leaderFrame = nil
	end
end

local function setLeaderIcon()
	local leaderFound = false
	for i = 1, 5 do
		if _G["CompactPartyFrameMember" .. i] and _G["CompactPartyFrameMember" .. i]:IsShown() and _G["CompactPartyFrameMember" .. i].unit then
			if UnitIsGroupLeader(_G["CompactPartyFrameMember" .. i].unit) then
				if not addon.variables.leaderFrame then
					addon.variables.leaderFrame = CreateFrame("Frame", nil, CompactPartyFrame)
					addon.variables.leaderFrame.leaderIcon = addon.variables.leaderFrame:CreateTexture(nil, "OVERLAY")
					addon.variables.leaderFrame.leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
					addon.variables.leaderFrame.leaderIcon:SetSize(16, 16)
				end
				addon.variables.leaderFrame.leaderIcon:ClearAllPoints()
				addon.variables.leaderFrame.leaderIcon:SetPoint("TOPRIGHT", _G["CompactPartyFrameMember" .. i], "TOPRIGHT", 5, 6)
				leaderFound = true
				break
			end
		end
	end
	if not leaderFound then removeLeaderIcon() end
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

local unitFrameVisibilityOptions = {
	NONE = { label = L["unitframeVisibility_none"] or NONE or "None", value = false },
	MOUSEOVER = { label = L["unitframeVisibility_mouseover"] or "Mouseover", value = "MOUSEOVER" },
	HIDE = { label = L["unitframeVisibility_hide"] or HIDE or "Hide", value = "hide" },
	SHOW_COMBAT = { label = L["unitframeVisibility_showCombat"] or "Show in combat", value = "[combat] show; hide" },
	HIDE_COMBAT = { label = L["unitframeVisibility_hideCombat"] or "Hide in combat", value = "[combat] hide; show" },
}
local unitFrameVisibilityOrder = { "NONE", "MOUSEOVER", "HIDE", "SHOW_COMBAT", "HIDE_COMBAT" }
local unitFrameVisibilityList = {}
local unitFrameVisibilityKeyByValue = {}

for key, option in pairs(unitFrameVisibilityOptions) do
	unitFrameVisibilityList[key] = option.label
	if option.value then unitFrameVisibilityKeyByValue[option.value] = key end
end
unitFrameVisibilityKeyByValue[false] = "NONE"

local function NormalizeUnitFrameSettingValue(value)
	if value == true then return "MOUSEOVER" end
	if value == false or value == "" then return nil end
	return value
end

local function GetUnitFrameDropdownKey(value)
	local normalized = NormalizeUnitFrameSettingValue(value)
	if not normalized then return "NONE" end
	return unitFrameVisibilityKeyByValue[normalized] or "NONE"
end

local function GetUnitFrameValueFromKey(key)
	local option = unitFrameVisibilityOptions[key]
	if not option then return nil end
	if option.value == false then return nil end
	return option.value
end

local function IsVisibilityKeyAllowed(cbData, key)
	if not key or key == "" then key = "NONE" end
	if not cbData or not cbData.allowedVisibility then return true end
	for _, allowedKey in ipairs(cbData.allowedVisibility) do
		if allowedKey == key then return true end
	end
	return false
end

local function GetUnitFrameDropdownData(cbData)
	local list = {}
	local order = {}
	local sourceOrder = (cbData and cbData.allowedVisibility) or unitFrameVisibilityOrder
	for _, key in ipairs(sourceOrder) do
		local label = unitFrameVisibilityList[key]
		if label then
			list[key] = label
			table.insert(order, key)
		end
	end
	return list, order
end

local function GetUnitFrameSettingKey(varName)
	if not addon.db or not varName then return "NONE" end
	return GetUnitFrameDropdownKey(addon.db[varName])
end

local function IsUnitFrameSetting(varName, key) return GetUnitFrameSettingKey(varName) == key end

local function ShouldUseMouseoverSetting(cbData)
	if not cbData or not cbData.var then return false end
	return IsUnitFrameSetting(cbData.var, "MOUSEOVER")
end

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

local function RestoreUnitFrameVisibility(frame, cbData)
	if frame and frame.SetAlpha then frame:SetAlpha(1) end
	if cbData and cbData.children then
		for _, child in pairs(cbData.children) do
			if child and child.SetAlpha then child:SetAlpha(1) end
		end
	end
	if cbData and cbData.hideChildren then
		for _, child in pairs(cbData.hideChildren) do
			if child and child.Show then child:Show() end
		end
	end
end

local UpdateUnitFrameMouseover -- forward declaration

local function ApplyUnitFrameStateDriverImmediate(frame, expression)
	if not frame then return true end
	if UnregisterStateDriver then pcall(UnregisterStateDriver, frame, "visibility") end
	if expression and RegisterStateDriver then
		local ok, err = pcall(RegisterStateDriver, frame, "visibility", expression)
		if not ok then
			frame.EQOL_VisibilityStateDriver = nil
			return false, err
		end
		frame.EQOL_VisibilityStateDriver = expression
	else
		frame.EQOL_VisibilityStateDriver = nil
	end
	return true
end

local function EnsureUnitFrameDriverWatcher()
	addon.variables = addon.variables or {}
	if addon.variables.unitFrameDriverWatcher then return end

	local watcher = CreateFrame("Frame")
	watcher:SetScript("OnEvent", function(self, event)
		if event ~= "PLAYER_REGEN_ENABLED" then return end
		local pending = addon.variables.pendingUnitFrameDriverUpdates
		if not pending then return end

		addon.variables.pendingUnitFrameDriverUpdates = nil
		for frameRef, data in pairs(pending) do
			if frameRef then
				ApplyUnitFrameStateDriverImmediate(frameRef, data.expression)
				if data.cbData and data.cbData.name then UpdateUnitFrameMouseover(data.cbData.name, data.cbData) end
			end
		end
	end)
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	addon.variables.unitFrameDriverWatcher = watcher
end

local function QueueUnitFrameDriverUpdate(frame, expression, cbData)
	EnsureUnitFrameDriverWatcher()
	addon.variables.pendingUnitFrameDriverUpdates = addon.variables.pendingUnitFrameDriverUpdates or {}
	addon.variables.pendingUnitFrameDriverUpdates[frame] = { expression = expression, cbData = cbData }
end

local function ApplyUnitFrameStateDriver(frame, expression, cbData)
	if not frame then return true end
	if InCombatLockdown and InCombatLockdown() then
		QueueUnitFrameDriverUpdate(frame, expression, cbData)
		return nil, "DEFERRED"
	end
	return ApplyUnitFrameStateDriverImmediate(frame, expression)
end

local function genericHoverOutCheck(frame, cbData)
	if not ShouldUseMouseoverSetting(cbData) then return end

	if frame and frame:IsVisible() then
		if not MouseIsOver(frame) then
			if frame.SetAlpha then frame:SetAlpha(0) end
			if cbData and cbData.children then
				for _, v in pairs(cbData.children) do
					if v and v.SetAlpha then v:SetAlpha(0) end
				end
			end
			if cbData and cbData.hideChildren then
				for _, v in pairs(cbData.hideChildren) do
					if v and v.Hide then v:Hide() end
				end
			end
		else
			C_Timer.After(0.3, function() genericHoverOutCheck(frame, cbData) end)
		end
	end
end

local hookedUnitFrames = {}
UpdateUnitFrameMouseover = function(barName, cbData)
	if not cbData or not cbData.var then return end

	local frame = _G[barName]
	if not frame then return end

	local stored = addon.db and addon.db[cbData.var]
	if stored == true then
		stored = "MOUSEOVER"
	elseif stored == false or stored == "" then
		stored = nil
	end

	local currentKey = GetUnitFrameDropdownKey(stored)
	if not IsVisibilityKeyAllowed(cbData, currentKey) then
		currentKey = "NONE"
		stored = nil
	end

	if currentKey ~= "NONE" and cbData.disableSetting then
		for _, v in pairs(cbData.disableSetting) do
			addon.db[v] = false
		end
	end
	local isMouseover = currentKey == "MOUSEOVER"
	local driverExpression
	if currentKey ~= "NONE" and currentKey ~= "MOUSEOVER" then
		local option = unitFrameVisibilityOptions[currentKey]
		driverExpression = option and option.value or nil
		stored = driverExpression
	elseif isMouseover then
		stored = "MOUSEOVER"
	else
		stored = nil
	end

	if addon.db then addon.db[cbData.var] = stored end

	if not hookedUnitFrames[frame] then
		local function handleEnter(self)
			if not ShouldUseMouseoverSetting(cbData) then return end
			if self and self.SetAlpha then self:SetAlpha(1) end
			if cbData.children then
				for _, child in pairs(cbData.children) do
					if child and child.SetAlpha then child:SetAlpha(1) end
				end
			end
			if cbData.hideChildren then
				for _, child in pairs(cbData.hideChildren) do
					if child and child.Show then child:Show() end
				end
			end
		end

		local function handleLeave(self)
			if not ShouldUseMouseoverSetting(cbData) then return end
			genericHoverOutCheck(self, cbData)
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

		if cbData.children then
			for _, child in ipairs(cbData.children) do
				if child and cbData.revealAllChilds then
					child:HookScript("OnEnter", function()
						if not ShouldUseMouseoverSetting(cbData) then return end
						if frame.SetAlpha then frame:SetAlpha(1) end
						for _, sibling in ipairs(cbData.children) do
							if sibling and sibling.SetAlpha then sibling:SetAlpha(1) end
						end
					end)
					child:HookScript("OnLeave", function() genericHoverOutCheck(frame, cbData) end)
				end
				if child then child.EQOL_MouseoverHooked = true end
			end
		end

		hookedUnitFrames[frame] = true
	end

	if isMouseover then
		ApplyUnitFrameStateDriver(frame, nil, cbData)
		RestoreUnitFrameVisibility(frame, cbData)
		if frame.Show then frame:Show() end
		if frame.SetAlpha then frame:SetAlpha(0) end
		if cbData.children then
			for _, child in ipairs(cbData.children) do
				if child and child.SetAlpha then child:SetAlpha(0) end
			end
		end
		if cbData.hideChildren then
			for _, child in ipairs(cbData.hideChildren) do
				if child and child.Hide then child:Hide() end
			end
		end

		C_Timer.After(0, function()
			if not ShouldUseMouseoverSetting(cbData) then return end
			if not frame then return end
			local hovered = MouseIsOver(frame)
			if not hovered and cbData and cbData.revealAllChilds and cbData.children then
				for _, child in pairs(cbData.children) do
					if child and child:IsVisible() and MouseIsOver(child) then
						hovered = true
						break
					end
				end
			end
			if hovered then
				if frame.SetAlpha then frame:SetAlpha(1) end
				if cbData.children then
					for _, child in pairs(cbData.children) do
						if child and child.SetAlpha then child:SetAlpha(1) end
					end
				end
				if cbData.hideChildren then
					for _, child in pairs(cbData.hideChildren) do
						if child and child.Show then child:Show() end
					end
				end
			else
				if frame.SetAlpha then frame:SetAlpha(0) end
				if cbData.children then
					for _, child in pairs(cbData.children) do
						if child and child.SetAlpha then child:SetAlpha(0) end
					end
				end
				if cbData.hideChildren then
					for _, child in pairs(cbData.hideChildren) do
						if child and child.Hide then child:Hide() end
					end
				end
			end
		end)
	else
		RestoreUnitFrameVisibility(frame, cbData)
		local ok, err = ApplyUnitFrameStateDriver(frame, driverExpression, cbData)
		if not ok then
			if err ~= "DEFERRED" then
				addon.variables.requireReload = true
				if addon.functions and addon.functions.checkReloadFrame then addon.functions.checkReloadFrame() end
			end
			return
		end
		if not driverExpression and frame.Show then frame:Show() end
	end
end

local function ApplyUnitFrameSettingByVar(varName)
	if not varName then return end
	for _, data in ipairs(addon.variables.unitFrameNames) do
		if data.var == varName and data.name then
			UpdateUnitFrameMouseover(data.name, data)
			break
		end
	end
end

local hookedButtons = {}

-- Keep action bars visible while interacting with SpellFlyout
local EQOL_LastMouseoverBar
local EQOL_LastMouseoverVar

local function EQOL_ShouldKeepVisibleByFlyout() return _G.SpellFlyout and _G.SpellFlyout:IsShown() and MouseIsOver(_G.SpellFlyout) end

local function EQOL_HideBarIfNotHovered(bar, variable)
	if not addon.db or not addon.db[variable] then return end
	C_Timer.After(0, function()
		-- Only hide if neither the bar nor the spell flyout is under the mouse
		if not MouseIsOver(bar) and not EQOL_ShouldKeepVisibleByFlyout() then bar:SetAlpha(0) end
	end)
end

local function EQOL_HookSpellFlyout()
	local flyout = _G.SpellFlyout
	if not flyout or flyout.EQOL_MouseoverHooked then return end

	flyout:HookScript("OnEnter", function()
		if EQOL_LastMouseoverBar and addon.db and addon.db[EQOL_LastMouseoverVar] then EQOL_LastMouseoverBar:SetAlpha(1) end
	end)

	flyout:HookScript("OnLeave", function()
		if EQOL_LastMouseoverBar and addon.db and addon.db[EQOL_LastMouseoverVar] then EQOL_HideBarIfNotHovered(EQOL_LastMouseoverBar, EQOL_LastMouseoverVar) end
	end)

	flyout:HookScript("OnHide", function()
		if EQOL_LastMouseoverBar and addon.db and addon.db[EQOL_LastMouseoverVar] then EQOL_HideBarIfNotHovered(EQOL_LastMouseoverBar, EQOL_LastMouseoverVar) end
	end)

	flyout.EQOL_MouseoverHooked = true
end
-- Action Bars
local function UpdateActionBarMouseover(barName, enable, variable)
	local bar = _G[barName]
	if not bar then return end

	local btnPrefix
	if barName == "MainMenuBar" then
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

	if enable then
		bar:SetAlpha(0)
		-- bar:EnableMouse(true)
		bar:SetScript("OnEnter", function(self)
			bar:SetAlpha(1)
			EQOL_LastMouseoverBar = bar
			EQOL_LastMouseoverVar = variable
		end)
		bar:SetScript("OnLeave", function(self) EQOL_HideBarIfNotHovered(bar, variable) end)
		for i = 1, 12 do
			local button = _G[btnPrefix .. i]
			if button and not hookedButtons[button] then
				if button.OnEnter then
					button:HookScript("OnEnter", function(self)
						if addon.db[variable] then
							bar:SetAlpha(1)
							EQOL_LastMouseoverBar = bar
							EQOL_LastMouseoverVar = variable
						end
					end)
					hookedButtons[button] = true
				else
					-- button:EnableMouse(true)
					button:SetScript("OnEnter", function(self)
						bar:SetAlpha(1)
						EQOL_LastMouseoverBar = bar
						EQOL_LastMouseoverVar = variable
					end)
				end
				if button.OnLeave then
					button:HookScript("OnLeave", function(self)
						if addon.db[variable] then EQOL_HideBarIfNotHovered(bar, variable) end
					end)
				else
					button:EnableMouse(true)
					button:SetScript("OnLeave", function(self)
						EQOL_HideBarIfNotHovered(bar, variable)
						GameTooltip:Hide()
					end)
				end
				if not hookedButtons[button] then GameTooltipActionButton(button) end
			end
		end
		-- Ensure flyout hooks are in place (once)
		C_Timer.After(0, EQOL_HookSpellFlyout)
	else
		bar:SetAlpha(1)
		-- bar:EnableMouse(true)
		bar:SetScript("OnEnter", nil)
		bar:SetScript("OnLeave", nil)
		for i = 1, 12 do
			local button = _G[btnPrefix .. i]
			if button and not hookedButtons[button] then
				-- button:EnableMouse(true)
				button:SetScript("OnEnter", nil)
				button:SetScript("OnLeave", nil)
				GameTooltipActionButton(button)
			end
		end
	end
end

-- Enhance QoL: Full button range coloring (taint-safe)
local function EnsureOverlay(btn)
	if btn.EQOL_RangeOverlay then return btn.EQOL_RangeOverlay end
	local tex = btn:CreateTexture(nil, "OVERLAY", nil, 7)
	tex:SetAllPoints(btn.icon or btn.Icon or btn)
	tex:Hide()
	btn.EQOL_RangeOverlay = tex
	return tex
end

local function ShowRangeOverlay(btn, show)
	local ov = EnsureOverlay(btn)
	if show and addon.db and addon.db.actionBarFullRangeColoring then
		local col = addon.db.actionBarFullRangeColor or { r = 1, g = 0.1, b = 0.1 }
		local alpha = addon.db.actionBarFullRangeAlpha or 0.35
		ov:SetColorTexture(col.r, col.g, col.b, alpha)
		ov:Show()
	else
		ov:Hide()
	end
end

local function RefreshAllRangeOverlays()
	for _, info in ipairs(addon.variables.actionBarNames or {}) do
		local prefix
		if info.name == "MainMenuBar" then
			prefix = "ActionButton"
		elseif info.name == "PetActionBar" then
			prefix = "PetActionButton"
		elseif info.name == "StanceBar" then
			prefix = "StanceButton"
		else
			prefix = info.name .. "Button"
		end
		for i = 1, 12 do
			local button = _G[prefix .. i]
			if button then ActionButton_UpdateRangeIndicator(button) end
		end
	end
end

local function UpdateMacroNameVisibility(button, hide)
	if not button or not button.GetName then return end

	local nameFrame = button.Name or _G[button:GetName() .. "Name"]
	if not nameFrame then return end

	if hide then
		if not nameFrame.EQOL_IsHiddenByEQOL then
			nameFrame.EQOL_OriginalAlpha = nameFrame:GetAlpha()
			nameFrame:SetAlpha(0)
			nameFrame.EQOL_IsHiddenByEQOL = true
		end
	elseif nameFrame.EQOL_IsHiddenByEQOL then
		nameFrame:SetAlpha(nameFrame.EQOL_OriginalAlpha or 1)
		nameFrame.EQOL_IsHiddenByEQOL = nil
	end
end

local function RefreshAllMacroNameVisibility()
	local hide = addon.db and addon.db.hideMacroNames
	for _, info in ipairs(addon.variables.actionBarNames or {}) do
		if info.name ~= "PetActionBar" and info.name ~= "StanceBar" then
			local prefix = info.name == "MainMenuBar" and "ActionButton" or (info.name .. "Button")
			for i = 1, 12 do
				local button = _G[prefix .. i]
				if button then UpdateMacroNameVisibility(button, hide) end
			end
		end
	end
end

hooksecurefunc("ActionButton_UpdateRangeIndicator", function(self, checksRange, inRange)
	if not self or not self.action then return end
	if checksRange and inRange == false then
		ShowRangeOverlay(self, true)
	else
		ShowRangeOverlay(self, false)
	end
end)

local doneHook = false
local inspectDone = {}
local inspectUnit = nil
addon.enchantTextCache = addon.enchantTextCache or {}
-- New helpers for Character vs Inspect display options
local function _ensureDisplayDB()
	addon.db = addon.db or {}
	-- migrate legacy toggles to new multi-select tables once
	if not addon.db.charDisplayOptions then
		addon.db.charDisplayOptions = {}
		if addon.db["showIlvlOnCharframe"] then addon.db.charDisplayOptions.ilvl = true end
		if addon.db["showGemsOnCharframe"] then addon.db.charDisplayOptions.gems = true end
		if addon.db["showEnchantOnCharframe"] then addon.db.charDisplayOptions.enchants = true end
		if addon.db["showGemsTooltipOnCharframe"] then addon.db.charDisplayOptions.gemtip = true end
	end
	if not addon.db.inspectDisplayOptions then
		addon.db.inspectDisplayOptions = {}
		for k, v in pairs(addon.db.charDisplayOptions) do
			addon.db.inspectDisplayOptions[k] = v
		end
	end
end

local function CharOpt(opt)
	_ensureDisplayDB()
	local t = addon.db.charDisplayOptions or {}
	-- Disable enchant checks entirely for Timerunners
	if opt == "enchants" and addon.functions and addon.functions.IsTimerunner and addon.functions.IsTimerunner() then return false end
	return t[opt] == true
end

local function InspectOpt(opt)
	_ensureDisplayDB()
	local t = addon.db.inspectDisplayOptions or {}
	-- Also suppress enchant checks in Inspect when player is a Timerunner
	if opt == "enchants" and addon.functions and addon.functions.IsTimerunner and addon.functions.IsTimerunner() then return false end
	return t[opt] == true
end

local function AnyInspectEnabled()
	_ensureDisplayDB()
	local t = addon.db.inspectDisplayOptions or {}
	return t.ilvl or t.gems or t.enchants or t.gemtip
end

local function CheckItemGems(element, itemLink, emptySocketsCount, key, pdElement, attempts)
	attempts = attempts or 1 -- Anzahl der Versuche
	if attempts > 10 then -- Abbruch nach 5 Versuchen, um Endlosschleifen zu vermeiden
		return
	end

	for i = 1, emptySocketsCount do
		local gemName, gemLink = C_Item.GetItemGem(itemLink, i)
		element.gems[i]:SetScript("OnEnter", nil)

		if gemName then
			local icon = C_Item.GetItemIconByID(gemLink)
			element.gems[i].icon:SetTexture(icon)
			element.gems[i].icon:SetVertexColor(1, 1, 1)
			element.gems[i]:SetScript("OnEnter", function(self)
				local showTip
				if pdElement == InspectPaperDollFrame then
					showTip = InspectOpt("gemtip")
				else
					showTip = CharOpt("gemtip")
				end
				if gemLink and showTip then
					local anchor = "ANCHOR_CURSOR"
					if addon.db["TooltipAnchorType"] == 3 then anchor = "ANCHOR_CURSOR_LEFT" end
					if addon.db["TooltipAnchorType"] == 4 then anchor = "ANCHOR_CURSOR_RIGHT" end
					local xOffset = addon.db["TooltipAnchorOffsetX"] or 0
					local yOffset = addon.db["TooltipAnchorOffsetY"] or 0
					GameTooltip:SetOwner(self, anchor, xOffset, yOffset)
					GameTooltip:SetHyperlink(gemLink)
					GameTooltip:Show()
				end
			end)
		else
			-- Wiederhole die Überprüfung nach einer Verzögerung, wenn der Edelstein noch nicht geladen ist
			C_Timer.After(0.1, function() CheckItemGems(element, itemLink, emptySocketsCount, key, pdElement, attempts + 1) end)
			return -- Abbrechen, damit wir auf die nächste Überprüfung warten
		end
	end
end

local function getTooltipInfoFromLink(link)
	if not link then return nil, nil end

	local enchantID = tonumber(link:match("item:%d+:(%d+)") or 0)
	local enchantText = nil

	if enchantID and enchantID > 0 then enchantText = addon.enchantTextCache[enchantID] end

	if enchantText == nil then
		local data = C_TooltipInfo.GetHyperlink(link)
		if data and data.lines then
			for _, v in pairs(data.lines) do
				if v.type == 15 then
					local r, g, b = v.leftColor:GetRGB()
					local colorHex = ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)

					local text = strmatch(gsub(gsub(gsub(v.leftText, "%s?|A.-|a", ""), "|cn.-:(.-)|r", "%1"), "[&+] ?", ""), addon.variables.enchantString)
					local icons = {}
					v.leftText:gsub("(|A.-|a)", function(iconString) table.insert(icons, iconString) end)
					text = text:gsub("(%d+)", "%1")
					text = text:gsub("(%a%a%a)%a+", "%1")
					text = text:gsub("%%", "%%%%")
					enchantText = colorHex .. text .. (icons[1] or "") .. "|r"
					break
				end
			end
		end

		if enchantID and enchantID > 0 then addon.enchantTextCache[enchantID] = enchantText or false end
	elseif enchantText == false then
		enchantText = nil
	end

	return enchantText
end

local itemCount = 0
local ilvlSum = 0

local function removeInspectElements()
	if nil == InspectPaperDollFrame then return end
	itemCount = 0
	ilvlSum = 0
	if InspectPaperDollFrame.ilvl then InspectPaperDollFrame.ilvl:SetText("") end
	local itemSlotsInspectList = {
		[1] = InspectHeadSlot,
		[2] = InspectNeckSlot,
		[3] = InspectShoulderSlot,
		[15] = InspectBackSlot,
		[5] = InspectChestSlot,
		[9] = InspectWristSlot,
		[10] = InspectHandsSlot,
		[6] = InspectWaistSlot,
		[7] = InspectLegsSlot,
		[8] = InspectFeetSlot,
		[11] = InspectFinger0Slot,
		[12] = InspectFinger1Slot,
		[13] = InspectTrinket0Slot,
		[14] = InspectTrinket1Slot,
		[16] = InspectMainHandSlot,
		[17] = InspectSecondaryHandSlot,
	}

	for key, element in pairs(itemSlotsInspectList) do
		if element.ilvl then element.ilvl:SetFormattedText("") end
		if element.ilvlBackground then element.ilvlBackground:Hide() end
		if element.enchant then element.enchant:SetText("") end
		if element.borderGradient then element.borderGradient:Hide() end
		if element.gems and #element.gems > 0 then
			for i = 1, #element.gems do
				element.gems[i]:UnregisterAllEvents()
				element.gems[i]:SetScript("OnUpdate", nil)
				element.gems[i]:Hide()
			end
		end
	end
	collectgarbage("collect")
end

local tooltipCache = {}

local function fmtToPattern(fmt)
	local pat = fmt:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
	pat = pat:gsub("%%%%d", "%%d+") -- "%d" -> "%d+"
	pat = pat:gsub("%%%%s", ".+") -- "%s" -> ".+"
	return "^" .. pat .. "$"
end

local pvpItemTooltip = fmtToPattern(PVP_ITEM_LEVEL_TOOLTIP)

local function getTooltipInfo(link)
	local key = link
	local cached = tooltipCache[key]
	if cached then return cached[1], cached[2] end

	local upgradeKey, isPVP
	local data = C_TooltipInfo.GetHyperlink(link)
	if data and data.lines then
		for i, v in pairs(data.lines) do
			if v.type == 42 then
				local text = v.rightText or v.leftText
				if text then
					local tier = text:gsub(".+:%s?", ""):gsub("%s?%d/%d", "")
					if tier then upgradeKey = string.lower(tier) end
				end
			elseif v.type == 0 and v.leftText:match(pvpItemTooltip) then
				isPVP = true
			end
		end
	end

	tooltipCache[key] = { upgradeKey, isPVP }
	return upgradeKey, isPVP
end

local function onInspect(arg1)
	if nil == InspectFrame then return end
	local unit = InspectFrame.unit
	if nil == unit then return end

	if UnitGUID(InspectFrame.unit) ~= arg1 then return end

	local pdElement = InspectPaperDollFrame
	if not doneHook then
		doneHook = true
		InspectFrame:HookScript("OnHide", function(self)
			inspectDone = {}
			removeInspectElements()
		end)
	end
	if inspectUnit ~= InspectFrame.unit then
		inspectUnit = InspectFrame.unit
		inspectDone = {}
	end
	if not InspectOpt("ilvl") and pdElement.ilvl then pdElement.ilvl:SetText("") end
	if not pdElement.ilvl and InspectOpt("ilvl") then
		pdElement.ilvlBackground = pdElement:CreateTexture(nil, "BACKGROUND")
		pdElement.ilvlBackground:SetColorTexture(0, 0, 0, 0.8) -- Schwarzer Hintergrund mit 80% Transparenz
		pdElement.ilvlBackground:SetPoint("TOPRIGHT", pdElement, "TOPRIGHT", -2, -28)
		pdElement.ilvlBackground:SetSize(20, 16) -- Größe des Hintergrunds (muss ggf. angepasst werden)

		pdElement.ilvl = pdElement:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		pdElement.ilvl:SetPoint("TOPRIGHT", pdElement.ilvlBackground, "TOPRIGHT", -1, -1) -- Position des Textes im Zentrum des Hintergrunds
		pdElement.ilvl:SetFont(addon.variables.defaultFont, 16, "OUTLINE") -- Setzt die Schriftart, -größe und -stil (OUTLINE)

		pdElement.ilvl:SetFormattedText("")
		pdElement.ilvl:SetTextColor(1, 1, 1, 1)

		local textWidth = pdElement.ilvl:GetStringWidth()
		pdElement.ilvlBackground:SetSize(textWidth + 6, pdElement.ilvl:GetStringHeight() + 4) -- Mehr Padding für bessere Lesbarkeit
	end
	local itemSlotsInspectList = {
		[1] = InspectHeadSlot,
		[2] = InspectNeckSlot,
		[3] = InspectShoulderSlot,
		[15] = InspectBackSlot,
		[5] = InspectChestSlot,
		[9] = InspectWristSlot,
		[10] = InspectHandsSlot,
		[6] = InspectWaistSlot,
		[7] = InspectLegsSlot,
		[8] = InspectFeetSlot,
		[11] = InspectFinger0Slot,
		[12] = InspectFinger1Slot,
		[13] = InspectTrinket0Slot,
		[14] = InspectTrinket1Slot,
		[16] = InspectMainHandSlot,
		[17] = InspectSecondaryHandSlot,
	}
	local twoHandLocs = {
		INVTYPE_2HWEAPON = true,
		INVTYPE_RANGED = true,
		INVTYPE_RANGEDRIGHT = true,
		INVTYPE_FISHINGPOLE = true,
	}

	for key, element in pairs(itemSlotsInspectList) do
		if nil == inspectDone[key] then
			if element.ilvl then element.ilvl:SetFormattedText("") end
			if element.ilvlBackground then element.ilvlBackground:Hide() end
			if element.enchant then element.enchant:SetText("") end
			local itemLink = GetInventoryItemLink(unit, key)
			if itemLink then
				local eItem = Item:CreateFromItemLink(itemLink)
				if eItem and not eItem:IsItemEmpty() then
					eItem:ContinueOnItemLoad(function()
						inspectDone[key] = true
						if InspectOpt("gems") then
							local itemStats = C_Item.GetItemStats(itemLink)
							local socketCount = 0
							for statName, statValue in pairs(itemStats) do
								if (statName:find("EMPTY_SOCKET") or statName:find("empty_socket")) and addon.variables.allowedSockets[statName] then socketCount = socketCount + statValue end
							end
							local neededSockets = addon.variables.shouldSocketed[key] or 0
							if neededSockets then
								local cSeason, isPvP = getTooltipInfo(itemLink)
								if addon.variables.shouldSocketedChecks[key] then
									if not addon.variables.shouldSocketedChecks[key].func(cSeason, isPvP) then neededSockets = 0 end
								end
							end
							local displayCount = math.max(socketCount, neededSockets)
							if element.gems and #element.gems > displayCount then
								for i = displayCount + 1, #element.gems do
									element.gems[i]:UnregisterAllEvents()
									element.gems[i]:SetScript("OnUpdate", nil)
									element.gems[i]:Hide()
								end
							end
							if not element.gems then element.gems = {} end
							for i = 1, displayCount do
								if not element.gems[i] then
									element.gems[i] = CreateFrame("Frame", nil, pdElement)
									element.gems[i]:SetSize(16, 16) -- Setze die Größe des Icons
									if addon.variables.itemSlotSide[key] == 0 then
										element.gems[i]:SetPoint("TOPLEFT", element, "TOPRIGHT", 5 + (i - 1) * 16, -1) -- Verschiebe jedes Icon um 20px
									elseif addon.variables.itemSlotSide[key] == 1 then
										element.gems[i]:SetPoint("TOPRIGHT", element, "TOPLEFT", -5 - (i - 1) * 16, -1)
									else
										element.gems[i]:SetPoint("BOTTOM", element, "TOPLEFT", -1, 5 + (i - 1) * 16)
									end

									element.gems[i]:SetFrameStrata("DIALOG")
									element.gems[i]:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

									element.gems[i].icon = element.gems[i]:CreateTexture(nil, "OVERLAY")
									element.gems[i].icon:SetAllPoints(element.gems[i])
								end
								element.gems[i].icon:SetTexture("Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic")
								if i > socketCount then
									element.gems[i].icon:SetVertexColor(1, 0, 0)
									element.gems[i]:SetScript("OnEnter", nil)
								else
									element.gems[i].icon:SetVertexColor(1, 1, 1)
								end
								element.gems[i]:Show()
							end
							if socketCount > 0 then CheckItemGems(element, itemLink, socketCount, key, pdElement) end
						elseif element.gems and #element.gems > 0 then
							for i = 1, #element.gems do
								element.gems[i]:UnregisterAllEvents()
								element.gems[i]:SetScript("OnUpdate", nil)
								element.gems[i]:Hide()
							end
						end

						if InspectOpt("ilvl") then
							local double = false
							if key == 16 then
								local offhandLink = GetInventoryItemLink(unit, 17)
								local _, _, _, itemEquipLoc = C_Item.GetItemInfoInstant(itemLink)
								if not offhandLink and twoHandLocs[itemEquipLoc] then double = true end
							end
							itemCount = itemCount + (double and 2 or 1)
							if not element.ilvlBackground then
								element.ilvlBackground = element:CreateTexture(nil, "BACKGROUND")
								element.ilvlBackground:SetColorTexture(0, 0, 0, 0.8) -- Schwarzer Hintergrund mit 80% Transparenz
								element.ilvl = element:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
								element.ilvl:SetFont(addon.variables.defaultFont, 14, "OUTLINE") -- Setzt die Schriftart, -größe und -stil (OUTLINE)
							end

							local cpos = addon.db["charIlvlPosition"] or "TOPRIGHT"
							element.ilvlBackground:ClearAllPoints()
							element.ilvl:ClearAllPoints()
							if cpos == "TOPLEFT" then
								element.ilvlBackground:SetPoint("TOPLEFT", element, "TOPLEFT", -1, 1)
								element.ilvl:SetPoint("TOPLEFT", element.ilvlBackground, "TOPLEFT", 1, -2)
							elseif cpos == "BOTTOMLEFT" then
								element.ilvlBackground:SetPoint("BOTTOMLEFT", element, "BOTTOMLEFT", -1, -1)
								element.ilvl:SetPoint("BOTTOMLEFT", element.ilvlBackground, "BOTTOMLEFT", 1, 1)
							elseif cpos == "BOTTOMRIGHT" then
								element.ilvlBackground:SetPoint("BOTTOMRIGHT", element, "BOTTOMRIGHT", 1, -1)
								element.ilvl:SetPoint("BOTTOMRIGHT", element.ilvlBackground, "BOTTOMRIGHT", -1, 1)
							else
								element.ilvlBackground:SetPoint("TOPRIGHT", element, "TOPRIGHT", 1, 1)
								element.ilvl:SetPoint("TOPRIGHT", element.ilvlBackground, "TOPRIGHT", -1, -2)
							end
							element.ilvlBackground:SetSize(30, 16) -- Größe des Hintergrunds (muss ggf. angepasst werden)

							local color = eItem:GetItemQualityColor()
							local itemLevelText = eItem:GetCurrentItemLevel()

							ilvlSum = ilvlSum + itemLevelText * (double and 2 or 1)
							element.ilvl:SetFormattedText(itemLevelText)
							element.ilvl:SetTextColor(color.r, color.g, color.b, 1)

							local textWidth = element.ilvl:GetStringWidth()
							element.ilvlBackground:SetSize(textWidth + 6, element.ilvl:GetStringHeight() + 4) -- Mehr Padding für bessere Lesbarkeit
						end
						if InspectOpt("enchants") then
							if not element.enchant then
								element.enchant = element:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
								if addon.variables.itemSlotSide[key] == 0 then
									element.enchant:SetPoint("BOTTOMLEFT", element, "BOTTOMRIGHT", 2, 1)
								elseif addon.variables.itemSlotSide[key] == 2 then
									element.enchant:SetPoint("TOPLEFT", element, "TOPRIGHT", 2, -1)
								else
									element.enchant:SetPoint("BOTTOMRIGHT", element, "BOTTOMLEFT", -2, 1)
								end
								if addon.variables.shouldEnchanted[key] or addon.variables.shouldEnchantedChecks[key] then
									element.borderGradient = element:CreateTexture(nil, "ARTWORK")
									element.borderGradient:SetPoint("TOPLEFT", element, "TOPLEFT", -2, 2)
									element.borderGradient:SetPoint("BOTTOMRIGHT", element, "BOTTOMRIGHT", 2, -2)
									element.borderGradient:SetColorTexture(1, 0, 0, 0.6) -- Grundfarbe Rot
									element.borderGradient:SetGradient("VERTICAL", CreateColor(1, 0, 0, 1), CreateColor(1, 0.3, 0.3, 0.5))
									element.borderGradient:Hide()
								end
								element.enchant:SetFont(addon.variables.defaultFont, 12, "OUTLINE")
							end
							if element.borderGradient then
								local enchantText = getTooltipInfoFromLink(itemLink)
								local foundEnchant = enchantText ~= nil
								if foundEnchant then element.enchant:SetFormattedText(enchantText) end

								if not foundEnchant and UnitLevel(inspectUnit) == addon.variables.maxLevel then
									element.enchant:SetText("")
									if
										nil == addon.variables.shouldEnchantedChecks[key]
										or (nil ~= addon.variables.shouldEnchantedChecks[key] and addon.variables.shouldEnchantedChecks[key].func(eItem:GetCurrentItemLevel()))
									then
										if key == 17 then
											local _, _, _, _, _, _, _, _, itemEquipLoc = C_Item.GetItemInfoInstant(itemLink)
											if addon.variables.allowedEnchantTypesForOffhand[itemEquipLoc] then
												element.borderGradient:Show()
												element.enchant:SetFormattedText(("|cff%02x%02x%02x"):format(255, 0, 0) .. L["MissingEnchant"] .. "|r")
											end
										else
											element.borderGradient:Show()
											element.enchant:SetFormattedText(("|cff%02x%02x%02x"):format(255, 0, 0) .. L["MissingEnchant"] .. "|r")
										end
									end
								end
							end
						else
							if element.borderGradient then element.borderGradient:Hide() end
							if element.enchant then element.enchant:SetText("") end
						end
					end)
				end
			end
		end
	end
	if InspectOpt("ilvl") and ilvlSum > 0 then pdElement.ilvl:SetText("" .. (math.floor((ilvlSum / 16) * 100 + 0.5) / 100)) end
end

local function setIlvlText(element, slot)
	-- Hide all gemslots
	if element then
		if element.gems then
			for i = 1, 3 do
				if element.gems[i] then
					element.gems[i]:Hide()
					element.gems[i].icon:SetTexture("Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic")
					element.gems[i]:SetScript("OnEnter", nil)
					element.gems[i].icon:SetVertexColor(1, 1, 1)
				end
			end
		end

		if element.borderGradient then element.borderGradient:Hide() end
		if not (CharOpt("gems") or CharOpt("ilvl") or CharOpt("enchants")) then
			element.ilvl:SetFormattedText("")
			element.enchant:SetText("")
			element.ilvlBackground:Hide()
			return
		end

		local eItem = Item:CreateFromEquipmentSlot(slot)
		if eItem and not eItem:IsItemEmpty() then
			eItem:ContinueOnItemLoad(function()
				local link = eItem:GetItemLink()
				local _, itemID, enchantID = string.match(link, "item:(%d+):(%d*):(%d*):(%d*):(%d*):(%d*):(%d*):(%d*):(%d*):(%d*):(%d*)")
				if CharOpt("gems") then
					local itemStats = C_Item.GetItemStats(link)
					local socketCount = 0
					for statName, statValue in pairs(itemStats) do
						if (statName:find("EMPTY_SOCKET") or statName:find("empty_socket")) and addon.variables.allowedSockets[statName] then socketCount = socketCount + statValue end
					end
					local neededSockets = addon.variables.shouldSocketed[slot] or 0
					if neededSockets then
						local cSeason, isPvP = getTooltipInfo(link)
						if addon.variables.shouldSocketedChecks[slot] then
							if not addon.variables.shouldSocketedChecks[slot].func(cSeason, isPvP) then neededSockets = 0 end
						end
					end
					local displayCount = math.max(socketCount, neededSockets)
					for i = 1, #element.gems do
						if i <= displayCount then
							element.gems[i]:Show()
							element.gems[i].icon:SetTexture("Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic")
							if i > socketCount then
								element.gems[i].icon:SetVertexColor(1, 0, 0)
								element.gems[i]:SetScript("OnEnter", nil)
							else
								element.gems[i].icon:SetVertexColor(1, 1, 1)
							end
						else
							element.gems[i]:Hide()
							element.gems[i]:SetScript("OnEnter", nil)
						end
					end
					if socketCount > 0 then CheckItemGems(element, link, socketCount, slot) end
				else
					for i = 1, #element.gems do
						element.gems[i]:Hide()
						element.gems[i]:SetScript("OnEnter", nil)
					end
				end

				local enchantText = getTooltipInfoFromLink(link)

				if CharOpt("ilvl") then
					local color = eItem:GetItemQualityColor()
					local itemLevelText = eItem:GetCurrentItemLevel()

					local cpos = addon.db["charIlvlPosition"] or "TOPRIGHT"
					element.ilvlBackground:ClearAllPoints()
					element.ilvl:ClearAllPoints()
					if cpos == "TOPLEFT" then
						element.ilvlBackground:SetPoint("TOPLEFT", element, "TOPLEFT", -1, 1)
						element.ilvl:SetPoint("TOPLEFT", element.ilvlBackground, "TOPLEFT", 1, -2)
					elseif cpos == "BOTTOMLEFT" then
						element.ilvlBackground:SetPoint("BOTTOMLEFT", element, "BOTTOMLEFT", -1, -1)
						element.ilvl:SetPoint("BOTTOMLEFT", element.ilvlBackground, "BOTTOMLEFT", 1, 1)
					elseif cpos == "BOTTOMRIGHT" then
						element.ilvlBackground:SetPoint("BOTTOMRIGHT", element, "BOTTOMRIGHT", 1, -1)
						element.ilvl:SetPoint("BOTTOMRIGHT", element.ilvlBackground, "BOTTOMRIGHT", -1, 1)
					else
						element.ilvlBackground:SetPoint("TOPRIGHT", element, "TOPRIGHT", 1, 1)
						element.ilvl:SetPoint("TOPRIGHT", element.ilvlBackground, "TOPRIGHT", -1, -2)
					end

					element.ilvl:SetFormattedText(itemLevelText)
					element.ilvl:SetTextColor(color.r, color.g, color.b, 1)

					local textWidth = element.ilvl:GetStringWidth()
					element.ilvlBackground:SetSize(textWidth + 6, element.ilvl:GetStringHeight() + 4) -- Mehr Padding für bessere Lesbarkeit
				else
					element.ilvl:SetFormattedText("")
					element.ilvlBackground:Hide()
				end

				if CharOpt("enchants") and element.borderGradient then
					local foundEnchant = enchantText ~= nil
					if foundEnchant then element.enchant:SetFormattedText(enchantText) end

					if not foundEnchant and UnitLevel("player") == addon.variables.maxLevel then
						element.enchant:SetText("")
						if
							nil == addon.variables.shouldEnchantedChecks[slot]
							or (nil ~= addon.variables.shouldEnchantedChecks[slot] and addon.variables.shouldEnchantedChecks[slot].func(eItem:GetCurrentItemLevel()))
						then
							if slot == 17 then
								local _, _, _, _, _, _, _, _, itemEquipLoc = C_Item.GetItemInfoInstant(link)
								if addon.variables.allowedEnchantTypesForOffhand[itemEquipLoc] then
									element.borderGradient:Show()
									element.enchant:SetFormattedText(("|cff%02x%02x%02x"):format(255, 0, 0) .. L["MissingEnchant"] .. "|r")
								end
							else
								element.borderGradient:Show()
								element.enchant:SetFormattedText(("|cff%02x%02x%02x"):format(255, 0, 0) .. L["MissingEnchant"] .. "|r")
							end
						end
					end
				else
					element.enchant:SetText("")
				end
			end)
		else
			element.ilvl:SetFormattedText("")
			element.ilvlBackground:Hide()
			element.enchant:SetText("")
			if element.borderGradient then element.borderGradient:Hide() end
		end
	end
end

function addon.functions.IsIndestructible(link)
	local itemParts = { strsplit(":", link) }
	for i = 13, #itemParts do
		local bonusID = tonumber(itemParts[i])
		if bonusID and bonusID == 43 then return true end
	end
	return false
end

local function calculateDurability()
	-- Timerunner gear is indestructible; hide and skip
	if addon.functions and addon.functions.IsTimerunner and addon.functions.IsTimerunner() then
		if addon.general and addon.general.durabilityIconFrame then addon.general.durabilityIconFrame:Hide() end
		return
	end
	local maxDur = 0 -- combined value of durability
	local currentDura = 0
	local critDura = 0 -- counter of items under 50%

	for key, _ in pairs(addon.variables.itemSlots) do
		local eItem = Item:CreateFromEquipmentSlot(key)
		if eItem and not eItem:IsItemEmpty() then
			eItem:ContinueOnItemLoad(function()
				local link = eItem:GetItemLink()
				if link then
					if addon.functions.IsIndestructible(link) == false then
						local current, maximum = GetInventoryItemDurability(key)
						if nil ~= current then
							local fDur = tonumber(string.format("%." .. 0 .. "f", current * 100 / maximum))
							maxDur = maxDur + maximum
							currentDura = currentDura + current
							if fDur < 50 then critDura = critDura + 1 end
						end
					end
				end
			end)
		end
	end

	-- When we only have full durable items so fake the numbers to show 100%
	if maxDur == 0 and currentDura == 0 then
		maxDur = 100
		currentDura = 100
	end

	local durValue = currentDura / maxDur * 100

	addon.variables.durabilityCount = tonumber(string.format("%." .. 0 .. "f", durValue)) .. "%"
	addon.general.durabilityIconFrame.count:SetText(addon.variables.durabilityCount)

	if tonumber(string.format("%." .. 0 .. "f", durValue)) > 80 then
		addon.general.durabilityIconFrame.count:SetTextColor(1, 1, 1)
	elseif tonumber(string.format("%." .. 0 .. "f", durValue)) > 50 then
		addon.general.durabilityIconFrame.count:SetTextColor(1, 1, 0)
	else
		addon.general.durabilityIconFrame.count:SetTextColor(1, 0, 0)
	end
end

local function UpdateItemLevel()
	local statFrame = CharacterStatsPane.ItemLevelFrame
	if statFrame and statFrame.Value then
		local avgItemLevel, equippedItemLevel = GetAverageItemLevel()
		local customItemLevel = equippedItemLevel
		statFrame.Value:SetText(string.format("%.2f", customItemLevel))
	end
end

hooksecurefunc("PaperDollFrame_SetItemLevel", function(statFrame, unit) UpdateItemLevel() end)

local function setCharFrame()
	UpdateItemLevel()
	if not addon.general.iconFrame then addon.functions.catalystChecks() end
	if addon.db["showCatalystChargesOnCharframe"] and addon.variables.catalystID and addon.general.iconFrame and not addon.functions.IsTimerunner() then
		local cataclystInfo = C_CurrencyInfo.GetCurrencyInfo(addon.variables.catalystID)
		addon.general.iconFrame.count:SetText(cataclystInfo.quantity)
	end
	if addon.db["showDurabilityOnCharframe"] and not addon.functions.IsTimerunner() then calculateDurability() end
	for key, value in pairs(addon.variables.itemSlots) do
		setIlvlText(value, key)
	end
end

local function addChatFrame(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)
	scroll:PauseLayout()

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)

	local data = {
		{
			var = "chatHideLearnUnlearn",
			text = L["chatHideLearnUnlearn"],
			type = "CheckBox",
			desc = L["chatHideLearnUnlearnDesc"],
			func = function(self, _, value)
				addon.db["chatHideLearnUnlearn"] = value
				if addon.functions.ApplyChatLearnFilter then addon.functions.ApplyChatLearnFilter(value) end
				container:ReleaseChildren()
				addChatFrame(container)
			end,
		},
	}

	table.sort(data, function(a, b) return a.text < b.text end)

	for _, cbData in ipairs(data) do
		local desc
		if cbData.desc then desc = cbData.desc end
		local cbElement = addon.functions.createCheckboxAce(cbData.text, addon.db[cbData.var], cbData.func, desc)
		groupCore:AddChild(cbElement)
	end

	local groupFade = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupFade)

	local fadeData = {
		{
			var = "chatFrameFadeEnabled",
			text = L["chatFrameFadeEnabled"],
			type = "CheckBox",
			func = function(self, _, value)
				addon.db["chatFrameFadeEnabled"] = value
				if ChatFrame1 then ChatFrame1:SetFading(value) end
				container:ReleaseChildren()
				addChatFrame(container)
			end,
		},
	}

	table.sort(fadeData, function(a, b) return a.text < b.text end)

	for _, cbData in ipairs(fadeData) do
		local desc
		if cbData.desc then desc = cbData.desc end
		local cbElement = addon.functions.createCheckboxAce(cbData.text, addon.db[cbData.var], cbData.func, desc)
		groupFade:AddChild(cbElement)
	end

	if addon.db["chatFrameFadeEnabled"] then
		local sliderTimeVisible = addon.functions.createSliderAce(
			L["chatFrameFadeTimeVisibleText"] .. ": " .. addon.db["chatFrameFadeTimeVisible"] .. "s",
			addon.db["chatFrameFadeTimeVisible"],
			1,
			300,
			1,
			function(self, _, value2)
				addon.db["chatFrameFadeTimeVisible"] = value2
				if ChatFrame1 then ChatFrame1:SetTimeVisible(value2) end
				self:SetLabel(L["chatFrameFadeTimeVisibleText"] .. ": " .. value2 .. "s")
			end
		)
		groupFade:AddChild(sliderTimeVisible)

		groupFade:AddChild(addon.functions.createSpacerAce())

		local sliderFadeDuration = addon.functions.createSliderAce(
			L["chatFrameFadeDurationText"] .. ": " .. addon.db["chatFrameFadeDuration"] .. "s",
			addon.db["chatFrameFadeDuration"],
			1,
			60,
			1,
			function(self, _, value2)
				addon.db["chatFrameFadeDuration"] = value2
				if ChatFrame1 then ChatFrame1:SetFadeDuration(value2) end
				self:SetLabel(L["chatFrameFadeDurationText"] .. ": " .. value2 .. "s")
			end
		)
		groupFade:AddChild(sliderFadeDuration)
	end

	local groupCoreSetting = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCoreSetting)

	data = {
		{
			var = "enableChatIM",
			text = L["enableChatIM"],
			type = "CheckBox",
			desc = L["enableChatIMDesc"],
			func = function(self, _, value)
				addon.db["enableChatIM"] = value
				if addon.ChatIM and addon.ChatIM.SetEnabled then addon.ChatIM:SetEnabled(value) end
				if not value then addon.variables.requireReload = true end
				container:ReleaseChildren()
				addChatFrame(container)
			end,
		},
	}

	for _, cbData in ipairs(data) do
		local desc
		if cbData.desc then desc = cbData.desc end
		local cbElement = addon.functions.createCheckboxAce(cbData.text, addon.db[cbData.var], cbData.func, desc)
		groupCoreSetting:AddChild(cbElement)
	end

	if addon.db["enableChatIM"] then
		local groupCoreSettingSub = addon.functions.createContainer("InlineGroup", "List")
		groupCoreSetting:AddChild(groupCoreSettingSub)

		data = {}
		table.insert(data, {
			var = "enableChatIMFade",
			text = L["enableChatIMFade"],
			type = "CheckBox",
			desc = L["enableChatIMFadeDesc"],
			func = function(self, _, value)
				addon.db["enableChatIMFade"] = value
				if addon.ChatIM and addon.ChatIM.SetEnabled then addon.ChatIM:UpdateAlpha() end
				container:ReleaseChildren()
				addChatFrame(container)
			end,
		})
		table.insert(data, {
			var = "enableChatIMRaiderIO",
			text = L["enableChatIMRaiderIO"],
			type = "CheckBox",
			func = function(self, _, value) addon.db["enableChatIMRaiderIO"] = value end,
		})
		table.insert(data, {
			var = "enableChatIMWCL",
			text = L["enableChatIMWCL"],
			type = "CheckBox",
			func = function(self, _, value) addon.db["enableChatIMWCL"] = value end,
		})
		table.insert(data, {
			var = "chatIMUseCustomSound",
			text = L["enableChatIMCustomSound"],
			type = "CheckBox",
			func = function(self, _, value)
				addon.db["chatIMUseCustomSound"] = value
				container:ReleaseChildren()
				addChatFrame(container)
			end,
		})
		table.insert(data, {
			var = "chatIMHideInCombat",
			text = L["chatIMHideInCombat"],
			type = "CheckBox",
			desc = L["chatIMHideInCombatDesc"],
			func = function(self, _, value)
				addon.db["chatIMHideInCombat"] = value
				if addon.ChatIM and addon.ChatIM.SetEnabled then addon.ChatIM:SetEnabled(true) end
			end,
		})
		table.insert(data, {
			var = "chatIMUseAnimation",
			text = L["chatIMUseAnimation"],
			type = "CheckBox",
			desc = L["chatIMUseAnimationDesc"],
			func = function(self, _, value) addon.db["chatIMUseAnimation"] = value end,
		})
		table.sort(data, function(a, b) return a.text < b.text end)

		for _, cbData in ipairs(data) do
			local desc
			if cbData.desc then desc = cbData.desc end
			local cbElement = addon.functions.createCheckboxAce(cbData.text, addon.db[cbData.var], cbData.func, desc)
			groupCoreSettingSub:AddChild(cbElement)
		end

		groupCoreSettingSub:AddChild(addon.functions.createSpacerAce())

		if addon.db["chatIMUseCustomSound"] then
			local soundList = {}
			for name in pairs(addon.ChatIM.availableSounds or {}) do
				soundList[name] = name
			end
			local list, order = addon.functions.prepareListForDropdown(soundList)
			local dropSound = addon.functions.createDropdownAce(L["ChatIMCustomSound"], list, order, function(self, _, val)
				addon.db["chatIMCustomSoundFile"] = val
				self:SetValue(val)
				local file = addon.ChatIM.availableSounds and addon.ChatIM.availableSounds[val]
				if file then PlaySoundFile(file, "Master") end
			end)
			dropSound:SetValue(addon.db["chatIMCustomSoundFile"])
			groupCoreSettingSub:AddChild(dropSound)
			groupCoreSettingSub:AddChild(addon.functions.createSpacerAce())
		end

		local sliderHistory = addon.functions.createSliderAce(L["ChatIMHistoryLimit"] .. ": " .. addon.db["chatIMMaxHistory"], addon.db["chatIMMaxHistory"], 0, 1000, 1, function(self, _, value)
			addon.db["chatIMMaxHistory"] = value
			if addon.ChatIM and addon.ChatIM.SetMaxHistoryLines then addon.ChatIM:SetMaxHistoryLines(value) end
			self:SetLabel(L["ChatIMHistoryLimit"] .. ": " .. value)
		end)
		groupCoreSettingSub:AddChild(sliderHistory)

		local historyList = {}
		for name in pairs(EnhanceQoL_IMHistory or {}) do
			historyList[name] = name
		end
		local list, order = addon.functions.prepareListForDropdown(historyList)
		local dropHistory = addon.functions.createDropdownAce(L["ChatIMHistoryPlayer"], list, order, function(self, _, val) self:SetValue(val) end)
		local btnDelete = addon.functions.createButtonAce(L["ChatIMHistoryDelete"], 140, function()
			local target = dropHistory:GetValue()
			if not target then return end
			StaticPopupDialogs["EQOL_DELETE_IM_HISTORY"] = StaticPopupDialogs["EQOL_DELETE_IM_HISTORY"]
				or {
					text = L["ChatIMHistoryDeleteConfirm"],
					button1 = YES,
					button2 = CANCEL,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				}
			StaticPopupDialogs["EQOL_DELETE_IM_HISTORY"].OnAccept = function()
				EnhanceQoL_IMHistory[target] = nil
				if addon.ChatIM and addon.ChatIM.history then addon.ChatIM.history[target] = nil end
				container:ReleaseChildren()
				addChatFrame(container)
			end
			StaticPopup_Show("EQOL_DELETE_IM_HISTORY", target)
		end)

		local btnClear = addon.functions.createButtonAce(L["ChatIMHistoryClearAll"], 140, function()
			StaticPopupDialogs["EQOL_CLEAR_IM_HISTORY"] = StaticPopupDialogs["EQOL_CLEAR_IM_HISTORY"]
				or {
					text = L["ChatIMHistoryClearConfirm"],
					button1 = YES,
					button2 = CANCEL,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				}
			StaticPopupDialogs["EQOL_CLEAR_IM_HISTORY"].OnAccept = function()
				wipe(EnhanceQoL_IMHistory)
				if addon.ChatIM then addon.ChatIM.history = EnhanceQoL_IMHistory end
				container:ReleaseChildren()
				addChatFrame(container)
			end
			StaticPopup_Show("EQOL_CLEAR_IM_HISTORY")
		end)

		groupCoreSettingSub:AddChild(dropHistory)
		groupCoreSettingSub:AddChild(btnDelete)
		groupCoreSettingSub:AddChild(btnClear)

		groupCoreSettingSub:AddChild(addon.functions.createSpacerAce())

		local hint = AceGUI:Create("Label")
		hint:SetFullWidth(true)
		hint:SetFont(addon.variables.defaultFont, 14, "OUTLINE")
		hint:SetText("|cffffd700" .. L["RightClickCloseTab"] .. "|r ")
		groupCoreSettingSub:AddChild(hint)
	end
	scroll:ResumeLayout()
	scroll:DoLayout()
end

-- (removed old addMinimapFrame; replaced by addMinimapFrame2 below)

-- New modular minimap UI builder that avoids full page rebuilds
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

			if not addon.db["useMinimapButtonBinIcon"] then
				local cbLock = addon.functions.createCheckboxAce(L["lockMinimapButtonBin"], addon.db["lockMinimapButtonBin"], function(self, _, value)
					addon.db["lockMinimapButtonBin"] = value
					addon.functions.toggleButtonSink()
				end)
				g:AddChild(cbLock)
			end

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
local function addUnitFrame2(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)
	local function doLayout()
		if scroll and scroll.DoLayout then scroll:DoLayout() end
	end
	wrapper:PauseLayout()

	local groups = {}

	local function ensureGroup(key, title)
		local g, known
		if groups[key] then
			g = groups[key]
			groups[key]:PauseLayout()
			groups[key]:ReleaseChildren()
			known = true
		else
			g = addon.functions.createContainer("InlineGroup", "List")
			g:SetTitle(title)
			wrapper:AddChild(g)
			groups[key] = g
		end

		return g, known
	end

	local function buildHitIndicator()
		local g, known = ensureGroup("hit", COMBAT_TEXT_LABEL)
		local data = {
			{
				var = "hideHitIndicatorPlayer",
				text = L["hideHitIndicatorPlayer"],
				func = function(_, _, value)
					addon.db["hideHitIndicatorPlayer"] = value
					if value then
						PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator:Hide()
					else
						PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator:Show()
					end
				end,
			},
			{
				var = "hideHitIndicatorPet",
				text = L["hideHitIndicatorPet"],
				func = function(_, _, value)
					addon.db["hideHitIndicatorPet"] = value
					if value and PetHitIndicator then PetHitIndicator:Hide() end
				end,
			},
		}
		table.sort(data, function(a, b) return a.text < b.text end)
		for _, cb in ipairs(data) do
			local w = addon.functions.createCheckboxAce(cb.text, addon.db[cb.var], cb.func)
			g:AddChild(w)
		end
		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildCore()
		local g, known = ensureGroup("core", "")
		g:SetLayout("Flow")
		local labelHeadline = addon.functions.createLabelAce("|cffffd700" .. L["UnitFrameHideExplain"] .. "|r", nil, nil, 14)
		labelHeadline:SetFullWidth(true)
		g:AddChild(labelHeadline)
		g:AddChild(addon.functions.createSpacerAce())

		for _, cbData in ipairs(addon.variables.unitFrameNames) do
			local dd = AceGUI:Create("Dropdown")
			dd:SetLabel(cbData.text)
			local list, order = GetUnitFrameDropdownData(cbData)
			dd:SetList(list, order)
			local currentKey = GetUnitFrameDropdownKey(addon.db and addon.db[cbData.var])
			if not IsVisibilityKeyAllowed(cbData, currentKey) then
				currentKey = "NONE"
				if addon.db then addon.db[cbData.var] = nil end
			end
			dd:SetValue(currentKey)
			dd:SetRelativeWidth(0.33)
			dd:SetCallback("OnValueChanged", function(_, _, key)
				if not IsVisibilityKeyAllowed(cbData, key) then return end
				addon.db[cbData.var] = GetUnitFrameValueFromKey(key)
				UpdateUnitFrameMouseover(cbData.name, cbData)
			end)
			g:AddChild(dd)
		end
		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildHealthText()
		local g, known = ensureGroup("healthText", L["Health Text"] or "Health Text")
		g:SetLayout("Flow")

		local list = { OFF = VIDEO_OPTIONS_DISABLED, PERCENT = STATUS_TEXT_PERCENT, ABS = STATUS_TEXT_VALUE, BOTH = STATUS_TEXT_BOTH }
		local order = { "OFF", "PERCENT", "ABS", "BOTH" }

		local htExplainText =
			string.format(L["HealthTextExplain"] or "%s follows Blizzard 'Status Text'. Any other mode shows your chosen format for Player, Target, and Boss frames.", VIDEO_OPTIONS_DISABLED)
		local lbl = addon.functions.createLabelAce("|cffffd700" .. htExplainText .. "|r", nil, nil, 10)
		lbl:SetFullWidth(true)
		g:AddChild(lbl)

		local dp = AceGUI:Create("Dropdown")
		dp:SetLabel(L["PlayerHealthText"] or "Player health text")
		dp:SetList(list, order)
		dp:SetValue(addon.db and addon.db["healthTextPlayerMode"] or "OFF")
		dp:SetRelativeWidth(0.33)
		dp:SetCallback("OnValueChanged", function(_, _, key)
			addon.db["healthTextPlayerMode"] = key or "OFF"
			if addon.HealthText and addon.HealthText.SetMode then addon.HealthText:SetMode("player", addon.db["healthTextPlayerMode"]) end
		end)
		g:AddChild(dp)

		local dt = AceGUI:Create("Dropdown")
		dt:SetLabel(L["TargetHealthText"] or "Target health text")
		dt:SetList(list, order)
		dt:SetValue(addon.db and addon.db["healthTextTargetMode"] or "OFF")
		dt:SetRelativeWidth(0.33)
		dt:SetCallback("OnValueChanged", function(_, _, key)
			addon.db["healthTextTargetMode"] = key or "OFF"
			if addon.HealthText and addon.HealthText.SetMode then addon.HealthText:SetMode("target", addon.db["healthTextTargetMode"]) end
		end)
		g:AddChild(dt)

		local db = AceGUI:Create("Dropdown")
		db:SetLabel(L["BossHealthText"] or "Boss health text")
		db:SetList(list, order)
		db:SetValue(addon.db and (addon.db["healthTextBossMode"] or addon.db["bossHealthMode"]) or "OFF")
		db:SetRelativeWidth(0.33)
		db:SetCallback("OnValueChanged", function(_, _, key)
			addon.db["healthTextBossMode"] = key or "OFF"
			if addon.HealthText and addon.HealthText.SetMode then addon.HealthText:SetMode("boss", addon.db["healthTextBossMode"]) end
		end)
		g:AddChild(db)

		-- OFF = obey Blizzard CVar, others override; no extra toggles

		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildCoreUF()
		local g, known = ensureGroup("coreUF", "")
		local labelHeadlineUF = addon.functions.createLabelAce("|cffffd700" .. (L["UnitFrameUFExplain"]:format(_G.RAID or "RAID", _G.PARTY or "Party", _G.PLAYER or "Player")) .. "|r", nil, nil, 14)
		labelHeadlineUF:SetFullWidth(true)
		g:AddChild(labelHeadlineUF)
		g:AddChild(addon.functions.createSpacerAce())

		local cbRaid = addon.functions.createCheckboxAce(L["hideRaidFrameBuffs"], addon.db["hideRaidFrameBuffs"], function(_, _, value)
			addon.db["hideRaidFrameBuffs"] = value
			addon.functions.updateRaidFrameBuffs()
			addon.variables.requireReload = true
		end)
		g:AddChild(cbRaid)

		local cbLeader = addon.functions.createCheckboxAce(L["showLeaderIconRaidFrame"], addon.db["showLeaderIconRaidFrame"], function(_, _, value)
			addon.db["showLeaderIconRaidFrame"] = value
			if value then
				setLeaderIcon()
			else
				removeLeaderIcon()
			end
		end)
		g:AddChild(cbLeader)

		local cbSolo = addon.functions.createCheckboxAce(L["showPartyFrameInSoloContent"], addon.db["showPartyFrameInSoloContent"], function(_, _, value)
			addon.db["showPartyFrameInSoloContent"] = value
			addon.variables.requireReload = true
			buildCoreUF()
			ApplyUnitFrameSettingByVar("unitframeSettingPlayerFrame")
			addon.functions.togglePartyFrameTitle(addon.db["hidePartyFrameTitle"])
		end)
		g:AddChild(cbSolo)

		local cbTitle = addon.functions.createCheckboxAce(L["hidePartyFrameTitle"], addon.db["hidePartyFrameTitle"], function(_, _, value)
			addon.db["hidePartyFrameTitle"] = value
			addon.functions.togglePartyFrameTitle(value)
		end)
		g:AddChild(cbTitle)

		-- Hide resting animation and glow on the Player frame
		local cbRest = addon.functions.createCheckboxAce(L["hideRestingGlow"] or "Hide resting animation and glow", addon.db["hideRestingGlow"], function(_, _, value)
			addon.db["hideRestingGlow"] = value
			if addon.functions.ApplyRestingVisuals then addon.functions.ApplyRestingVisuals() end
		end, L["hideRestingGlowDesc"] or "Removes the 'ZZZ' status texture and the resting glow on the player frame while resting.")
		g:AddChild(cbRest)

		local sliderName
		local cbTrunc = addon.functions.createCheckboxAce(L["unitFrameTruncateNames"], addon.db.unitFrameTruncateNames, function(_, _, v)
			addon.db.unitFrameTruncateNames = v
			if sliderName then sliderName:SetDisabled(not v) end
			addon.functions.updateUnitFrameNames()
		end)
		g:AddChild(cbTrunc)

		sliderName = addon.functions.createSliderAce(L["unitFrameMaxNameLength"] .. ": " .. addon.db.unitFrameMaxNameLength, addon.db.unitFrameMaxNameLength, 1, 20, 1, function(self, _, val)
			addon.db.unitFrameMaxNameLength = val
			self:SetLabel(L["unitFrameMaxNameLength"] .. ": " .. val)
			addon.functions.updateUnitFrameNames()
		end)
		sliderName:SetDisabled(not addon.db.unitFrameTruncateNames)
		g:AddChild(sliderName)

		local sliderScale
		local cbScale = addon.functions.createCheckboxAce(L["unitFrameScaleEnable"], addon.db.unitFrameScaleEnabled, function(_, _, v)
			addon.db.unitFrameScaleEnabled = v
			if sliderScale then sliderScale:SetDisabled(not v) end
			if v then
				addon.functions.updatePartyFrameScale()
			else
				addon.variables.requireReload = true
				addon.functions.checkReloadFrame()
			end
		end)
		g:AddChild(cbScale)

		sliderScale = addon.functions.createSliderAce(L["unitFrameScale"] .. ": " .. addon.db.unitFrameScale, addon.db.unitFrameScale, 0.5, 2, 0.05, function(self, _, val)
			addon.db.unitFrameScale = val
			self:SetLabel(L["unitFrameScale"] .. ": " .. string.format("%.2f", val))
			addon.functions.updatePartyFrameScale()
		end)
		sliderScale:SetDisabled(not addon.db.unitFrameScaleEnabled)
		g:AddChild(sliderScale)

		g:AddChild(addon.functions.createSpacerAce())

		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildCast()
		local g, known = ensureGroup("cast", L["CastBars"] or "Cast Bars")
		local dd = AceGUI:Create("Dropdown")
		dd:SetLabel(L["castBarsToHide"] or "Cast bars to hide")
		local list = {
			PlayerCastingBarFrame = L["castBar_player"] or _G.PLAYER or "Player",
			TargetFrameSpellBar = L["castBar_target"] or TARGET or "Target",
			FocusFrameSpellBar = L["castBar_focus"] or FOCUS or "Focus",
		}
		local order = { "PlayerCastingBarFrame", "TargetFrameSpellBar", "FocusFrameSpellBar" }
		dd:SetList(list, order)
		dd:SetMultiselect(true)
		dd:SetFullWidth(true)
		dd:SetCallback("OnValueChanged", function(widget, _, key, checked)
			addon.db.hiddenCastBars = addon.db.hiddenCastBars or {}
			addon.db.hiddenCastBars[key] = checked and true or false
			addon.functions.ApplyCastBarVisibility()
		end)
		if type(addon.db.hiddenCastBars) == "table" then
			for k, v in pairs(addon.db.hiddenCastBars) do
				if v then dd:SetItemValue(k, true) end
			end
		end
		g:AddChild(dd)
		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	buildHitIndicator()
	buildCore()
	buildHealthText()
	buildCoreUF()
	buildCast()
	wrapper:ResumeLayout()
	doLayout()
end

-- New modular Vendor & Economy UI builder
local function addVendorMainFrame2(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)
	local function doLayout()
		if scroll and scroll.DoLayout then scroll:DoLayout() end
	end
	wrapper:PauseLayout()

	local groups = {}
	local ahCore

	local function ensureGroup(key, title)
		local g, known
		if groups[key] then
			g = groups[key]
			groups[key]:PauseLayout()
			groups[key]:ReleaseChildren()
			known = true
		else
			g = addon.functions.createContainer("InlineGroup", "List")
			g:SetTitle(title)
			wrapper:AddChild(g)
			groups[key] = g
		end

		return g, known
	end

	local function buildAHCore()
		local g, known = ensureGroup("ahcore", BUTTON_LAG_AUCTIONHOUSE)
		local items = {
			{
				text = L["persistAuctionHouseFilter"],
				var = "persistAuctionHouseFilter",
				func = function(_, _, v) addon.db["persistAuctionHouseFilter"] = v end,
			},
			{
				text = (function()
					local label = _G["AUCTION_HOUSE_FILTER_CURRENTEXPANSION_ONLY"] or "Current Expansion Only"
					return L["alwaysUserCurExpAuctionHouse"]:format(label)
				end)(),
				var = "alwaysUserCurExpAuctionHouse",
				func = function(_, _, v) addon.db["alwaysUserCurExpAuctionHouse"] = v end,
			},
		}
		table.sort(items, function(a, b) return a.text < b.text end)
		for _, it in ipairs(items) do
			local w = addon.functions.createCheckboxAce(it.text, addon.db[it.var], it.func, it.desc)
			g:AddChild(w)
		end
		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildConvenience()
		local g, known = ensureGroup("conv", L["Convenience"])
		local checkboxes = {}
		local items = {
			{
				var = "autoRepair",
				text = L["autoRepair"],
				func = function(_, _, v)
					addon.db["autoRepair"] = v
					if checkboxes["autoRepairGuildBank"] then
						checkboxes["autoRepairGuildBank"]:SetDisabled(not v)
						if not v and addon.db["autoRepairGuildBank"] then
							addon.db["autoRepairGuildBank"] = false
							checkboxes["autoRepairGuildBank"]:SetValue(false)
						end
					end
				end,
				desc = L["autoRepairDesc"],
			},
			{
				var = "autoRepairGuildBank",
				text = L["autoRepairGuildBank"],
				func = function(_, _, v) addon.db["autoRepairGuildBank"] = v end,
				desc = L["autoRepairGuildBankDesc"],
			},
			{
				var = "sellAllJunk",
				text = L["sellAllJunk"],
				func = function(_, _, v)
					addon.db["sellAllJunk"] = v
					if v then checkBagIgnoreJunk() end
				end,
				desc = L["sellAllJunkDesc"],
			},
		}
		for _, it in ipairs(items) do
			local w = addon.functions.createCheckboxAce(it.text, addon.db[it.var], it.func, it.desc)
			if it.var == "autoRepairGuildBank" then w:SetDisabled(not addon.db["autoRepair"]) end
			g:AddChild(w)
			checkboxes[it.var] = w
		end

		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildMerchant()
		local g, known = ensureGroup("merchant", MERCHANT)
		local w = addon.functions.createCheckboxAce(L["enableExtendedMerchant"], addon.db["enableExtendedMerchant"], function(_, _, value)
			addon.db["enableExtendedMerchant"] = value
			if addon.Merchant then
				if value and addon.Merchant.Enable then
					addon.Merchant:Enable()
				elseif not value and addon.Merchant.Disable then
					addon.Merchant:Disable()
					addon.variables.requireReload = true
					addon.functions.checkReloadFrame()
				end
			end
		end, L["enableExtendedMerchantDesc"])
		g:AddChild(w)

		local highlightKnownCheckbox = addon.functions.createCheckboxAce(L["markKnownOnMerchant"], addon.db["markKnownOnMerchant"], function(_, _, value)
			addon.db["markKnownOnMerchant"] = value
			if MerchantFrame and MerchantFrame:IsShown() then
				if MerchantFrame.selectedTab == 2 then
					if MerchantFrame_UpdateBuybackInfo then MerchantFrame_UpdateBuybackInfo() end
				else
					if MerchantFrame_UpdateMerchantInfo then MerchantFrame_UpdateMerchantInfo() end
				end
			end
		end, L["markKnownOnMerchantDesc"])
		g:AddChild(highlightKnownCheckbox)

		local highlightCollectedPetsCheckbox = addon.functions.createCheckboxAce(L["markCollectedPetsOnMerchant"], addon.db["markCollectedPetsOnMerchant"], function(_, _, value)
			addon.db["markCollectedPetsOnMerchant"] = value
			if MerchantFrame and MerchantFrame:IsShown() then
				if MerchantFrame.selectedTab == 2 then
					if MerchantFrame_UpdateBuybackInfo then MerchantFrame_UpdateBuybackInfo() end
				else
					if MerchantFrame_UpdateMerchantInfo then MerchantFrame_UpdateMerchantInfo() end
				end
			end
		end, L["markCollectedPetsOnMerchantDesc"])
		g:AddChild(highlightCollectedPetsCheckbox)

		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildMailbox()
		local g, known = ensureGroup("mail", MINIMAP_TRACKING_MAILBOX)
		local w = addon.functions.createCheckboxAce(L["enableMailboxAddressBook"], addon.db["enableMailboxAddressBook"], function(_, _, value)
			addon.db["enableMailboxAddressBook"] = value
			if addon.Mailbox then
				if addon.Mailbox.SetEnabled then addon.Mailbox:SetEnabled(value) end
				if value and addon.Mailbox.AddSelfToContacts then addon.Mailbox:AddSelfToContacts() end
				if value and addon.Mailbox.RefreshList then addon.Mailbox:RefreshList() end
			end
			buildMailbox()
		end, L["enableMailboxAddressBookDesc"])
		g:AddChild(w)

		if addon.db["enableMailboxAddressBook"] then
			local sub = addon.functions.createContainer("InlineGroup", "List")
			sub:SetTitle(L["mailboxRemoveHeader"])
			g:AddChild(sub)

			local tList = {}
			for key, rec in pairs(addon.db["mailboxContacts"]) do
				local class = rec and rec.class
				local col = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class or ""] or { r = 1, g = 1, b = 1 }
				tList[key] = string.format("|cff%02x%02x%02x%s|r", col.r * 255, col.g * 255, col.b * 255, key)
			end
			local list, order = addon.functions.prepareListForDropdown(tList)
			local drop = addon.functions.createDropdownAce(L["mailboxRemoveSelect"], list, order, nil)
			sub:AddChild(drop)

			local btn = addon.functions.createButtonAce(REMOVE, 120, function()
				local selected = drop:GetValue()
				if selected and addon.db["mailboxContacts"][selected] then
					addon.db["mailboxContacts"][selected] = nil
					local refresh = {}
					for key, rec in pairs(addon.db["mailboxContacts"]) do
						local class = rec and rec.class
						local col = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class or ""] or { r = 1, g = 1, b = 1 }
						refresh[key] = string.format("|cff%02x%02x%02x%s|r", col.r * 255, col.g * 255, col.b * 255, key)
					end
					local nl, no = addon.functions.prepareListForDropdown(refresh)
					drop:SetList(nl, no)
					drop:SetValue(nil)
					if addon.Mailbox and addon.Mailbox.RefreshList then addon.Mailbox:RefreshList() end
				end
			end)
			sub:AddChild(btn)
		end
		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildMoney()
		local g, known = ensureGroup("money", MONEY)

		local cbEnable = addon.functions.createCheckboxAce(L["enableMoneyTracker"], addon.db["enableMoneyTracker"], function(_, _, v)
			addon.db["enableMoneyTracker"] = v
			buildMoney()
		end, L["enableMoneyTrackerDesc"])
		g:AddChild(cbEnable)

		if addon.db["enableMoneyTracker"] then
			local sub = addon.functions.createContainer("InlineGroup", "List")
			g:AddChild(sub)

			local cbGoldOnly = addon.functions.createCheckboxAce(L["showOnlyGoldOnMoney"], addon.db["showOnlyGoldOnMoney"], function(_, _, v) addon.db["showOnlyGoldOnMoney"] = v end)
			sub:AddChild(cbGoldOnly)

			local tList = {}
			for guid, v in pairs(addon.db["moneyTracker"]) do
				if guid ~= UnitGUID("player") then
					local col = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[v.class] or { r = 1, g = 1, b = 1 }
					local displayName = string.format("|cff%02x%02x%02x%s-%s|r", (col.r or 1) * 255, (col.g or 1) * 255, (col.b or 1) * 255, v.name or "?", v.realm or "?")
					tList[guid] = displayName
				end
			end

			local list, order = addon.functions.prepareListForDropdown(tList)
			local dropRemove = addon.functions.createDropdownAce(L["moneyTrackerRemovePlayer"], list, order, nil)
			local btnRemove = addon.functions.createButtonAce(REMOVE, 100, function()
				local sel = dropRemove:GetValue()
				if sel and addon.db["moneyTracker"][sel] then
					addon.db["moneyTracker"][sel] = nil
					local tList2 = {}
					for guid, v in pairs(addon.db["moneyTracker"]) do
						if guid ~= UnitGUID("player") then
							local col = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[v.class] or { r = 1, g = 1, b = 1 }
							local displayName = string.format("|cff%02x%02x%02x%s-%s|r", (col.r or 1) * 255, (col.g or 1) * 255, (col.b or 1) * 255, v.name or "?", v.realm or "?")
							tList2[guid] = displayName
						end
					end
					local nl, no = addon.functions.prepareListForDropdown(tList2)
					dropRemove:SetList(nl, no)
					dropRemove:SetValue(nil)
				end
			end)
			sub:AddChild(dropRemove)
			sub:AddChild(btnRemove)
		end
		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	buildAHCore()
	buildConvenience()
	buildMerchant()
	buildMailbox()
	buildMoney()
	wrapper:ResumeLayout()
	doLayout()
end

local function addActionBarFrame(container, d)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)

	local labelHeadline = addon.functions.createLabelAce(
		"|cffffd700"
			.. L["ActionbarHideExplain"]:format(_G["HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_ALWAYS"], _G["HUD_EDIT_MODE_SETTING_ACTION_BAR_ALWAYS_SHOW_BUTTONS"], _G["HUD_EDIT_MODE_MENU"])
			.. "|r",
		nil,
		nil,
		14
	)
	labelHeadline:SetFullWidth(true)
	groupCore:AddChild(labelHeadline)

	groupCore:AddChild(addon.functions.createSpacerAce())

	for _, cbData in ipairs(addon.variables.actionBarNames) do
		local desc
		if cbData.desc then desc = cbData.desc end
		local cbElement = addon.functions.createCheckboxAce(cbData.text, addon.db[cbData.var], function(self, _, value)
			if cbData.var and cbData.name then
				addon.db[cbData.var] = value
				UpdateActionBarMouseover(cbData.name, value, cbData.var)
			end
		end, desc)
		groupCore:AddChild(cbElement)
	end

	local cbHideMacroNames = addon.functions.createCheckboxAce(L["hideMacroNames"], addon.db["hideMacroNames"], function(_, _, value)
		addon.db["hideMacroNames"] = value
		RefreshAllMacroNameVisibility()
	end, L["hideMacroNamesDesc"])
	groupCore:AddChild(cbHideMacroNames)

	groupCore:AddChild(addon.functions.createSpacerAce())

	local cbRange = addon.functions.createCheckboxAce(L["fullButtonRangeColoring"], addon.db["actionBarFullRangeColoring"], function(_, _, value)
		addon.db["actionBarFullRangeColoring"] = value
		RefreshAllRangeOverlays()
		container:ReleaseChildren()
		addActionBarFrame(container)
	end, L["fullButtonRangeColoringDesc"])
	groupCore:AddChild(cbRange)

	if addon.db["actionBarFullRangeColoring"] then
		local colorPicker = AceGUI:Create("ColorPicker")
		colorPicker:SetLabel(L["rangeOverlayColor"])
		local c = addon.db["actionBarFullRangeColor"]
		colorPicker:SetColor(c.r, c.g, c.b)
		colorPicker:SetCallback("OnValueChanged", function(_, _, r, g, b)
			addon.db["actionBarFullRangeColor"] = { r = r, g = g, b = b }
			RefreshAllRangeOverlays()
		end)
		groupCore:AddChild(colorPicker)

		local alphaPercent = math.floor((addon.db["actionBarFullRangeAlpha"] or 0.35) * 100)
		local sliderAlpha = addon.functions.createSliderAce(L["rangeOverlayAlpha"] .. ": " .. alphaPercent .. "%", alphaPercent, 1, 100, 1, function(self, _, val)
			addon.db["actionBarFullRangeAlpha"] = val / 100
			self:SetLabel(L["rangeOverlayAlpha"] .. ": " .. val .. "%")
			RefreshAllRangeOverlays()
		end)
		groupCore:AddChild(sliderAlpha)
	end
end

local function addDungeonFrame(container, d)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	groupCore:SetTitle(LOOKING_FOR_DUNGEON_PVEFRAME)
	wrapper:AddChild(groupCore)

	local data = {
		{
			text = L["groupfinderAppText"],
			var = "groupfinderAppText",
			func = function(self, _, value)
				addon.db["groupfinderAppText"] = value
				toggleGroupApplication(value)
			end,
		},
		{
			text = L["groupfinderMoveResetButton"],
			var = "groupfinderMoveResetButton",
			func = function(self, _, value)
				addon.db["groupfinderMoveResetButton"] = value
				toggleLFGFilterPosition()
			end,
		},
		{
			text = L["groupfinderSkipRoleSelect"],
			var = "groupfinderSkipRoleSelect",
			func = function(self, _, value)
				addon.db["groupfinderSkipRoleSelect"] = value
				container:ReleaseChildren()
				addDungeonFrame(container)
			end,
			desc = L["interruptWithShift"],
		},
		{
			parent = DELVES_LABEL,
			var = "autoChooseDelvePower",
			text = L["autoChooseDelvePower"],
			type = "CheckBox",
			func = function(self, _, value) addon.db["autoChooseDelvePower"] = value end,
		},
		{
			parent = DUNGEONS,
			var = "persistSignUpNote",
			text = L["Persist LFG signup note"],
			type = "CheckBox",
			func = function(self, _, value) addon.db["persistSignUpNote"] = value end,
		},
		{
			parent = DUNGEONS,
			var = "skipSignUpDialog",
			text = L["Quick signup"],
			type = "CheckBox",
			func = function(self, _, value) addon.db["skipSignUpDialog"] = value end,
		},
		{
			parent = DUNGEONS,
			var = "lfgSortByRio",
			text = L["lfgSortByRio"],
			type = "CheckBox",
			func = function(self, _, value) addon.db["lfgSortByRio"] = value end,
		},
		{
			parent = DUNGEONS,
			var = "enableChatIMRaiderIO",
			text = L["enableChatIMRaiderIO"],
			type = "CheckBox",
			func = function(self, _, value) addon.db["enableChatIMRaiderIO"] = value end,
		},
	}

	table.sort(data, function(a, b) return a.text < b.text end)

	for _, cbData in ipairs(data) do
		local desc
		if cbData.desc then desc = cbData.desc end
		local cbElement = addon.functions.createCheckboxAce(cbData.text, addon.db[cbData.var], cbData.func, desc)
		groupCore:AddChild(cbElement)
	end

	if addon.db["groupfinderSkipRoleSelect"] then
		local list, order = addon.functions.prepareListForDropdown({ [1] = L["groupfinderSkipRolecheckUseSpec"], [2] = L["groupfinderSkipRolecheckUseLFD"] }, true)

		local dropRoleSelect = addon.functions.createDropdownAce("", list, order, function(self, _, value) addon.db["groupfinderSkipRoleSelectOption"] = value end)
		dropRoleSelect:SetValue(addon.db["groupfinderSkipRoleSelectOption"])

		local groupSkipRole = addon.functions.createContainer("InlineGroup", "List")
		wrapper:AddChild(groupSkipRole)
		groupSkipRole:SetTitle(L["groupfinderSkipRolecheckHeadline"])
		groupSkipRole:AddChild(dropRoleSelect)
	end
end

local function addTotemHideToggle(dbValue, data)
	table.insert(data, {
		parent = headerClassInfo,
		var = dbValue,
		text = L["shaman_HideTotem"],
		type = "CheckBox",
		callback = function(self, _, value)
			addon.db[dbValue] = value
			if value then
				TotemFrame:Hide()
			else
				TotemFrame:Show()
			end
		end,
	})
end

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

local function addCVarFrame(container, d)
	local scroll = addon.functions.createContainer("ScrollFrame", "List")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local persistenceGroup = addon.functions.createContainer("InlineGroup", "List")
	persistenceGroup:SetFullWidth(true)
	persistenceGroup:SetTitle(L["cvarPersistenceHeader"])
	wrapper:AddChild(persistenceGroup)

	local persistenceCheckbox = addon.functions.createCheckboxAce(L["cvarPersistence"], addon.db.cvarPersistenceEnabled, function(self, _, value)
		addon.db.cvarPersistenceEnabled = value and true or false
		addon.variables.requireReload = true
		if addon.functions.initializePersistentCVars then addon.functions.initializePersistentCVars() end
	end, L["cvarPersistenceDesc"])
	persistenceGroup:AddChild(persistenceCheckbox)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	groupCore:SetTitle(L["CVar"])
	wrapper:AddChild(groupCore)

	local data = addon.variables.cvarOptions

	local categories = {}
	for key, optionData in pairs(data) do
		local categoryKey = optionData.category or "cvarCategoryMisc"
		if not categories[categoryKey] then categories[categoryKey] = {} end
		table.insert(categories[categoryKey], {
			key = key,
			description = optionData.description,
			trueValue = optionData.trueValue,
			falseValue = optionData.falseValue,
			register = optionData.register or nil,
			persistent = optionData.persistent or nil,
			category = categoryKey,
		})
	end

	local function addCategoryGroup(categoryKey, entries)
		if not entries or #entries == 0 then return end

		table.sort(entries, function(a, b) return (a.description or "") < (b.description or "") end)

		local categoryGroup = addon.functions.createContainer("InlineGroup", "List")
		categoryGroup:SetTitle(L[categoryKey] or categoryKey)
		categoryGroup:SetFullWidth(true)
		groupCore:AddChild(categoryGroup)

		for _, entry in ipairs(entries) do
			local cvarKey = entry.key
			local cvarDesc = entry.description
			local cvarTrue = entry.trueValue
			local cvarFalse = entry.falseValue

			if entry.register and nil == GetCVar(cvarKey) then C_CVar.RegisterCVar(cvarKey, cvarTrue) end

			local actValue = (GetCVar(cvarKey) == cvarTrue)

			local cbElement = addon.functions.createCheckboxAce(cvarDesc, actValue, function(self, _, value)
				addon.variables.requireReload = true
				local newValue
				if value then
					newValue = cvarTrue
				else
					newValue = cvarFalse
				end

				if entry.persistent then
					addon.db.cvarOverrides = addon.db.cvarOverrides or {}
					addon.db.cvarOverrides[cvarKey] = newValue
				end

				setCVarValue(cvarKey, newValue)
			end)
			cbElement.trueValue = cvarTrue
			cbElement.falseValue = cvarFalse

			categoryGroup:AddChild(cbElement)
		end
	end

	local categoryOrder = {
		"cvarCategoryUtility",
		"cvarCategoryMovementInput",
		"cvarCategoryDisplay",
		"cvarCategorySystem",
		"cvarCategoryMisc",
	}

	for _, categoryKey in ipairs(categoryOrder) do
		if categories[categoryKey] then
			addCategoryGroup(categoryKey, categories[categoryKey])
			categories[categoryKey] = nil
		end
	end

	if next(categories) then
		local remaining = {}
		for categoryKey, entries in pairs(categories) do
			table.insert(remaining, { key = categoryKey, entries = entries })
		end
		table.sort(remaining, function(a, b)
			local labelA = L[a.key] or a.key
			local labelB = L[b.key] or b.key
			return labelA < labelB
		end)
		for _, bucket in ipairs(remaining) do
			addCategoryGroup(bucket.key, bucket.entries)
		end
	end
	scroll:DoLayout()
end

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

local function addUIFrame(container)
	local data = {
		{
			parent = "",
			var = "ignoreTalkingHead",
			text = string.format(L["ignoreTalkingHeadN"], HUD_EDIT_MODE_TALKING_HEAD_FRAME_LABEL),
			type = "CheckBox",
			callback = function(self, _, value) addon.db["ignoreTalkingHead"] = value end,
		},
		{
			parent = "",
			var = "hideDynamicFlightBar",
			text = L["hideDynamicFlightBar"]:format(DYNAMIC_FLIGHT),
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["hideDynamicFlightBar"] = value
				addon.functions.toggleDynamicFlightBar(addon.db["hideDynamicFlightBar"])
			end,
		},
		{
			parent = "",
			var = "hideQuickJoinToast",
			text = HIDE .. " " .. COMMUNITIES_NOTIFICATION_SETTINGS_DIALOG_QUICK_JOIN_LABEL,
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["hideQuickJoinToast"] = value
				addon.functions.toggleQuickJoinToastButton(addon.db["hideQuickJoinToast"])
			end,
		},
		{
			parent = "",
			var = "hideZoneText",
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["hideZoneText"] = value
				addon.functions.toggleZoneText(addon.db["hideZoneText"])
			end,
		},
		{
			parent = "",
			var = "hideOrderHallBar",
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["hideOrderHallBar"] = value
				if OrderHallCommandBar then
					if value then
						OrderHallCommandBar:Hide()
					else
						OrderHallCommandBar:Show()
					end
				end
			end,
		},
		{
			parent = "",
			var = "hideMinimapButton",
			text = L["Hide Minimap Button"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["hideMinimapButton"] = value
				addon.functions.toggleMinimapButton(addon.db["hideMinimapButton"])
			end,
		},
		{
			parent = "",
			var = "hideRaidTools",
			text = L["Hide Raid Tools"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["hideRaidTools"] = value
				addon.functions.toggleRaidTools(addon.db["hideRaidTools"], _G.CompactRaidFrameManager)
			end,
		},
		{
			parent = "",
			var = "optionsFrameScale",
			type = "Slider",
			text = L["optionsFrameScale"],
			value = addon.db["optionsFrameScale"] or 1.0,
			min = OPTIONS_FRAME_MIN_SCALE,
			max = OPTIONS_FRAME_MAX_SCALE,
			step = 0.05,
			labelFormatter = function(val) return string.format("%.2f", val) end,
			callback = function(widget, _, val)
				local applied = addon.functions.applyOptionsFrameScale(val)
				if math.abs(applied - val) > 0.0001 then widget:SetValue(applied) end
			end,
		},
		-- Game Menu scaling toggle
		{
			parent = MAINMENU_BUTTON,
			var = "gameMenuScaleEnabled",
			text = L["enableGameMenuScale"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["gameMenuScaleEnabled"] = value
				if value then
					addon.functions.applyGameMenuScale()
				else
					-- Only restore default if we were the last to apply a scale
					if GameMenuFrame and addon.variables and addon.variables.gameMenuScaleLastApplied then
						local current = GameMenuFrame:GetScale() or 1.0
						if math.abs(current - addon.variables.gameMenuScaleLastApplied) < 0.0001 then GameMenuFrame:SetScale(1.0) end
					end
				end
				container:ReleaseChildren()
				addUIFrame(container)
			end,
		},
	}

	-- Conditionally add the slider when enabled
	if addon.db["gameMenuScaleEnabled"] then
		table.insert(data, {
			parent = MAINMENU_BUTTON,
			var = "gameMenuScale",
			type = "Slider",
			text = L["gameMenuScale"],
			value = addon.db["gameMenuScale"],
			min = 0.5,
			max = 2.0,
			step = 0.05,
			labelFormatter = function(val) return string.format("%.2f", val) end,
			callback = function(widget, _, val)
				local rounded = math.floor(val * 100 + 0.5) / 100
				addon.db["gameMenuScale"] = rounded
				if math.abs(rounded - val) > 0.0001 then
					widget:SetValue(rounded)
				else
					addon.functions.applyGameMenuScale()
				end
			end,
		})
	end

	addon.functions.createWrapperData(data, container, L)
end

local function addBagFrame(container)
	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	container:AddChild(wrapper)

	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	wrapper:AddChild(scroll)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	groupCore:SetTitle(INFO)
	scroll:AddChild(groupCore)

	local data = {
		{
			parent = BAGSLOT,
			var = "showIlvlOnMerchantframe",
			text = L["showIlvlOnMerchantframe"],
			type = "CheckBox",
			callback = function(self, _, value) addon.db["showIlvlOnMerchantframe"] = value end,
		},
		{
			parent = BAGSLOT,
			var = "showIlvlOnBagItems",
			text = L["showIlvlOnBagItems"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["showIlvlOnBagItems"] = value
				for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
					if frame:IsShown() then addon.functions.updateBags(frame) end
				end
				if ContainerFrameCombinedBags:IsShown() then addon.functions.updateBags(ContainerFrameCombinedBags) end
				container:ReleaseChildren()
				addBagFrame(container)
			end,
		},
		{
			parent = BAGSLOT,
			var = "showBagFilterMenu",
			text = L["showBagFilterMenu"],
			desc = (L["showBagFilterMenuDesc"]):format(SHIFT_KEY_TEXT),
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["showBagFilterMenu"] = value
				for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
					if frame:IsShown() then addon.functions.updateBags(frame) end
				end
				if ContainerFrameCombinedBags:IsShown() then addon.functions.updateBags(ContainerFrameCombinedBags) end
				if value then
					if BankFrame:IsShown() then
						for slot = 1, C_Container.GetContainerNumSlots(BANK_CONTAINER) do
							local itemButton = _G["BankFrameItem" .. slot]
							if itemButton then addon.functions.updateBank(itemButton, -1, slot) end
						end
					end
				else
					if BankFrame:IsShown() then
						for slot = 1, C_Container.GetContainerNumSlots(BANK_CONTAINER) do
							local itemButton = _G["BankFrameItem" .. slot]
							if itemButton and itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
						end
					end
				end
				if _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end
			end,
		},
		{
			parent = BAGSLOT,
			var = "fadeBagQualityIcons",
			text = L["fadeBagQualityIcons"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["fadeBagQualityIcons"] = value
				for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
					if frame:IsShown() then addon.functions.updateBags(frame) end
				end
				if ContainerFrameCombinedBags:IsShown() then addon.functions.updateBags(ContainerFrameCombinedBags) end
				if _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end
			end,
		},
		{
			parent = BAGSLOT,
			var = "showIlvlOnBankFrame",
			text = L["showIlvlOnBankFrame"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["showIlvlOnBankFrame"] = value
				if value then
					if BankFrame:IsShown() then
						for slot = 1, C_Container.GetContainerNumSlots(BANK_CONTAINER) do
							local itemButton = _G["BankFrameItem" .. slot]
							if itemButton then addon.functions.updateBank(itemButton, -1, slot) end
						end
					end
				else
					if BankFrame:IsShown() then
						for slot = 1, C_Container.GetContainerNumSlots(BANK_CONTAINER) do
							local itemButton = _G["BankFrameItem" .. slot]
							if itemButton and itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
						end
					end
				end
				if _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end
			end,
		},
		{
			parent = BAGSLOT,
			var = "showBindOnBagItems",
			text = L["showBindOnBagItems"]:format(_G.ITEM_BIND_ON_EQUIP, _G.ITEM_ACCOUNTBOUND_UNTIL_EQUIP, _G.ITEM_BNETACCOUNTBOUND),
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["showBindOnBagItems"] = value
				for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
					if frame:IsShown() then addon.functions.updateBags(frame) end
				end
				if ContainerFrameCombinedBags:IsShown() then addon.functions.updateBags(ContainerFrameCombinedBags) end
			end,
		},
		{
			parent = BAGSLOT,
			var = "showUpgradeArrowOnBagItems",
			text = L["showUpgradeArrowOnBagItems"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["showUpgradeArrowOnBagItems"] = value
				for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
					if frame:IsShown() then addon.functions.updateBags(frame) end
				end
				if ContainerFrameCombinedBags:IsShown() then addon.functions.updateBags(ContainerFrameCombinedBags) end
				if _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end
				-- Rebuild UI to show/hide the upgrade icon position dropdown
				container:ReleaseChildren()
				addBagFrame(container)
			end,
		},
		-- moved Money Tracker to Vendors & Economy → Money
	}
	table.sort(data, function(a, b)
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
	for _, checkboxData in ipairs(data) do
		local desc
		if checkboxData.desc then desc = checkboxData.desc end
		local cbautoChooseQuest = addon.functions.createCheckboxAce(checkboxData.text, addon.db[checkboxData.var], checkboxData.callback, desc)
		groupCore:AddChild(cbautoChooseQuest)
	end

	local cbCloseAh = addon.functions.createCheckboxAce(
		L["closeBagsOnAuctionHouse"] or "Close bags on Auction House",
		addon.db["closeBagsOnAuctionHouse"],
		function(self, _, value) addon.db["closeBagsOnAuctionHouse"] = value end
	)
	groupCore:AddChild(cbCloseAh)

	local list = {
		TOPLEFT = L["topLeft"],
		TOPRIGHT = L["topRight"],
		BOTTOMLEFT = L["bottomLeft"],
		BOTTOMRIGHT = L["bottomRight"],
	}
	local order = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
	if addon.db["showIlvlOnBagItems"] then
		local dropIlvlPos = addon.functions.createDropdownAce(L["bagIlvlPosition"], list, order, function(self, _, value)
			addon.db["bagIlvlPosition"] = value
			for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
				if frame:IsShown() then addon.functions.updateBags(frame) end
			end
			if ContainerFrameCombinedBags:IsShown() then addon.functions.updateBags(ContainerFrameCombinedBags) end
		end)
		dropIlvlPos:SetValue(addon.db["bagIlvlPosition"])
		dropIlvlPos:SetRelativeWidth(0.4)
		groupCore:AddChild(dropIlvlPos)
	end

	if addon.db["showUpgradeArrowOnBagItems"] then
		local dropUpPos = addon.functions.createDropdownAce(L["bagUpgradeIconPosition"], list, order, function(self, _, value)
			addon.db["bagUpgradeIconPosition"] = value
			for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
				if frame and frame:IsShown() then addon.functions.updateBags(frame) end
			end
			if ContainerFrameCombinedBags:IsShown() then addon.functions.updateBags(ContainerFrameCombinedBags) end
			if _G.BankPanel and _G.BankPanel:IsShown() then addon.functions.updateBags(_G.BankPanel) end
			if MerchantFrame and MerchantFrame:IsShown() then
				if MerchantFrame_UpdateMerchantInfo then MerchantFrame_UpdateMerchantInfo() end
				if MerchantFrame_UpdateBuybackInfo then MerchantFrame_UpdateBuybackInfo() end
			end
			if EquipmentFlyoutFrame and EquipmentFlyoutFrame:IsShown() and EquipmentFlyout_UpdateItems then EquipmentFlyout_UpdateItems() end
		end)
		dropUpPos:SetValue(addon.db["bagUpgradeIconPosition"])
		dropUpPos:SetRelativeWidth(0.4)
		groupCore:AddChild(dropUpPos)
	end

	local groupConfirmation = addon.functions.createContainer("InlineGroup", "List")
	groupConfirmation:SetTitle(L["Confirmations"])
	scroll:AddChild(groupConfirmation)

	-- Confirmation
	data = {
		{
			parent = "",
			var = "deleteItemFillDialog",
			text = L["deleteItemFillDialog"]:format(DELETE_ITEM_CONFIRM_STRING),
			type = "CheckBox",
			desc = L["deleteItemFillDialogDesc"],
			callback = function(self, _, value) addon.db["deleteItemFillDialog"] = value end,
		},
		{
			parent = "",
			var = "confirmPatronOrderDialog",
			text = (L["confirmPatronOrderDialog"]):format(PROFESSIONS_CRAFTER_ORDER_TAB_NPC),
			type = "CheckBox",
			desc = L["confirmPatronOrderDialogDesc"],
			callback = function(self, _, value) addon.db["confirmPatronOrderDialog"] = value end,
		},
		{
			parent = "",
			var = "confirmTimerRemovalTrade",
			text = L["confirmTimerRemovalTrade"],
			type = "CheckBox",
			desc = L["confirmTimerRemovalTradeDesc"],
			callback = function(self, _, value) addon.db["confirmTimerRemovalTrade"] = value end,
		},
		{
			parent = "",
			var = "confirmReplaceEnchant",
			text = L["confirmReplaceEnchant"],
			type = "CheckBox",
			desc = L["confirmReplaceEnchantDesc"],
			callback = function(self, _, value) addon.db["confirmReplaceEnchant"] = value end,
		},
		{
			parent = "",
			var = "confirmSocketReplace",
			text = L["confirmSocketReplace"],
			type = "CheckBox",
			desc = L["confirmSocketReplaceDesc"],
			callback = function(self, _, value) addon.db["confirmSocketReplace"] = value end,
		},
	}

	table.sort(data, function(a, b)
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

	for _, checkboxData in ipairs(data) do
		local desc
		if checkboxData.desc then desc = checkboxData.desc end
		local cbautoChooseQuest = addon.functions.createCheckboxAce(checkboxData.text, addon.db[checkboxData.var], checkboxData.callback, desc)
		groupConfirmation:AddChild(cbautoChooseQuest)
	end
	scroll:DoLayout()
end

local function addCharacterFrame(container)
	local posList = {
		TOPLEFT = L["topLeft"],
		TOPRIGHT = L["topRight"],
		BOTTOMLEFT = L["bottomLeft"],
		BOTTOMRIGHT = L["bottomRight"],
	}
	local posOrder = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }

	-- Base layout
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	wrapper:SetFullWidth(true)
	scroll:AddChild(wrapper)

	-- Multi-dropdowns (Character/Inspect)
	_ensureDisplayDB()
	local ddGroup = addon.functions.createContainer("InlineGroup", "List")
	ddGroup:SetTitle(L["Character & Inspect Info"] or "Character & Inspect Info")
	wrapper:AddChild(ddGroup)

	local AceGUI = addon.AceGUI
	local optionsList = {
		ilvl = STAT_AVERAGE_ITEM_LEVEL or "Item Level",
		gems = AUCTION_CATEGORY_GEMS or "Gems",
		enchants = ENCHANTS or "Enchants",
		gemtip = L["Gem slot tooltip"] or "Gem slot tooltip",
		durability = DURABILITY or "Durability",
		catalyst = L["Catalyst Charges"] or "Catalyst Charges",
	}

	local ddChar = AceGUI:Create("Dropdown")
	ddChar:SetLabel(L["Show on Character Frame"] or "Show on Character Frame")
	ddChar:SetMultiselect(true)
	ddChar:SetFullWidth(true)
	ddChar:SetList(optionsList)
	for k in pairs(optionsList) do
		if k == "durability" then
			ddChar:SetItemValue(k, addon.db and addon.db["showDurabilityOnCharframe"] == true)
		elseif k == "catalyst" then
			ddChar:SetItemValue(k, addon.db and addon.db["showCatalystChargesOnCharframe"] == true)
		else
			local t = addon.db.charDisplayOptions or {}
			ddChar:SetItemValue(k, t[k] == true)
		end
	end
	ddChar:SetCallback("OnValueChanged", function(_, _, key, val)
		_ensureDisplayDB()
		local b = val and true or false
		if key == "durability" then
			addon.db["showDurabilityOnCharframe"] = b
			if addon.general and addon.general.durabilityIconFrame then
				if b and not addon.functions.IsTimerunner() then
					calculateDurability()
					addon.general.durabilityIconFrame:Show()
				else
					addon.general.durabilityIconFrame:Hide()
				end
			end
			addon.db.charDisplayOptions.durability = b
		elseif key == "catalyst" then
			addon.db["showCatalystChargesOnCharframe"] = b
			if addon.general and addon.general.iconFrame then
				if b and addon.variables and addon.variables.catalystID and not addon.functions.IsTimerunner() then
					local c = C_CurrencyInfo.GetCurrencyInfo(addon.variables.catalystID)
					if c then addon.general.iconFrame.count:SetText(c.quantity) end
					addon.general.iconFrame:Show()
				else
					addon.general.iconFrame:Hide()
				end
			end
			addon.db.charDisplayOptions.catalyst = b
		else
			addon.db.charDisplayOptions[key] = b
			setCharFrame()
		end
	end)
	ddGroup:AddChild(ddChar)

	local ddInsp = AceGUI:Create("Dropdown")
	ddInsp:SetLabel(L["Show on Inspect Frame"] or "Show on Inspect Frame")
	ddInsp:SetMultiselect(true)
	ddInsp:SetFullWidth(true)
	local inspOptionsList = {
		ilvl = STAT_AVERAGE_ITEM_LEVEL or "Item Level",
		gems = AUCTION_CATEGORY_GEMS or "Gems",
		enchants = ENCHANTS or "Enchants",
		gemtip = L["Gem slot tooltip"] or "Gem slot tooltip",
	}
	ddInsp:SetList(inspOptionsList)
	for k in pairs(inspOptionsList) do
		local t = addon.db.inspectDisplayOptions or {}
		ddInsp:SetItemValue(k, t[k] == true)
	end
	ddInsp:SetCallback("OnValueChanged", function(_, _, key, val)
		_ensureDisplayDB()
		addon.db.inspectDisplayOptions[key] = val and true or false
		if InspectFrame and InspectFrame:IsShown() and InspectFrame.unit then
			local guid = UnitGUID(InspectFrame.unit)
			if guid then onInspect(guid) end
		end
	end)
	ddGroup:AddChild(ddInsp)

	-- Info group
	local groupInfo = addon.functions.createContainer("InlineGroup", "List")
	groupInfo:SetTitle(INFO)
	wrapper:AddChild(groupInfo)

	local cbCloak = addon.functions.createCheckboxAce(L["showCloakUpgradeButton"], addon.db["showCloakUpgradeButton"], function(_, _, value)
		addon.db["showCloakUpgradeButton"] = value
		if addon.functions.updateCloakUpgradeButton then addon.functions.updateCloakUpgradeButton() end
	end)
	groupInfo:AddChild(cbCloak)

	local cbInstant = addon.functions.createCheckboxAce(L["instantCatalystEnabled"], addon.db["instantCatalystEnabled"], function(_, _, value)
		addon.db["instantCatalystEnabled"] = value
		addon.functions.toggleInstantCatalystButton(value)
	end, L["instantCatalystEnabledDesc"])
	groupInfo:AddChild(cbInstant)

	local cbMovementSpeed = addon.functions.createCheckboxAce(L["MovementSpeedInfo"]:format(STAT_MOVEMENT_SPEED), addon.db["movementSpeedStatEnabled"], function(_, _, value)
		addon.db["movementSpeedStatEnabled"] = value
		if value then
			if addon.MovementSpeedStat and addon.MovementSpeedStat.Refresh then addon.MovementSpeedStat.Refresh() end
		else
			addon.MovementSpeedStat.Disable()
		end
	end)
	groupInfo:AddChild(cbMovementSpeed)

	local cbOpenChar = addon.functions.createCheckboxAce(L["openCharframeOnUpgrade"], addon.db["openCharframeOnUpgrade"], function(_, _, value) addon.db["openCharframeOnUpgrade"] = value end)
	groupInfo:AddChild(cbOpenChar)

	-- Ilvl position group
	local groupIlvl = addon.functions.createContainer("InlineGroup", "List")
	groupIlvl:SetTitle(LFG_LIST_ITEM_LEVEL_INSTR_SHORT)
	wrapper:AddChild(groupIlvl)
	local dropIlvl = addon.functions.createDropdownAce(L["charIlvlPosition"], posList, posOrder, function(self, _, value)
		addon.db["charIlvlPosition"] = value
		setCharFrame()
	end)
	dropIlvl:SetValue(addon.db["charIlvlPosition"])
	dropIlvl:SetRelativeWidth(0.4)
	groupIlvl:AddChild(dropIlvl)

	-- Gems group
	local groupGems = addon.functions.createContainer("InlineGroup", "List")
	groupGems:SetTitle(AUCTION_CATEGORY_GEMS)
	wrapper:AddChild(groupGems)
	local cbGemHelper = addon.functions.createCheckboxAce(L["enableGemHelper"], addon.db["enableGemHelper"], function(_, _, value)
		addon.db["enableGemHelper"] = value
		if not value and EnhanceQoLGemHelper then
			EnhanceQoLGemHelper:Hide()
			EnhanceQoLGemHelper = nil
		end
	end, L["enableGemHelperDesc"])
	groupGems:AddChild(cbGemHelper)

	-- Class specific
	local classname = select(2, UnitClass("player"))
	local groupClass = addon.functions.createContainer("InlineGroup", "List")
	groupClass:SetTitle(headerClassInfo)
	wrapper:AddChild(groupClass)

	local function addTotemCheckbox(dbKey)
		local cb = addon.functions.createCheckboxAce(L["shaman_HideTotem"], addon.db[dbKey], function(_, _, value)
			addon.db[dbKey] = value
			if value then
				if TotemFrame then TotemFrame:Hide() end
			else
				if TotemFrame then TotemFrame:Show() end
			end
		end)
		groupClass:AddChild(cb)
	end

	if classname == "DEATHKNIGHT" then
		local cb = addon.functions.createCheckboxAce(L["deathknight_HideRuneFrame"], addon.db["deathknight_HideRuneFrame"], function(_, _, value)
			addon.db["deathknight_HideRuneFrame"] = value
			if value then
				if RuneFrame then RuneFrame:Hide() end
			else
				if RuneFrame then RuneFrame:Show() end
			end
		end)
		groupClass:AddChild(cb)
		addTotemCheckbox("deathknight_HideTotemBar")
	elseif classname == "DRUID" then
		addTotemCheckbox("druid_HideTotemBar")
		local cb = addon.functions.createCheckboxAce(L["druid_HideComboPoint"], addon.db["druid_HideComboPoint"], function(_, _, value)
			addon.db["druid_HideComboPoint"] = value
			if value then
				if DruidComboPointBarFrame then DruidComboPointBarFrame:Hide() end
			else
				if DruidComboPointBarFrame then DruidComboPointBarFrame:Show() end
			end
		end)
		groupClass:AddChild(cb)
	elseif classname == "EVOKER" then
		local cb = addon.functions.createCheckboxAce(L["evoker_HideEssence"], addon.db["evoker_HideEssence"], function(_, _, value)
			addon.db["evoker_HideEssence"] = value
			if value then
				if EssencePlayerFrame then EssencePlayerFrame:Hide() end
			else
				if EssencePlayerFrame then EssencePlayerFrame:Show() end
			end
		end)
		groupClass:AddChild(cb)
	elseif classname == "MAGE" then
		addTotemCheckbox("mage_HideTotemBar")
	elseif classname == "MONK" then
		local cb = addon.functions.createCheckboxAce(L["monk_HideHarmonyBar"], addon.db["monk_HideHarmonyBar"], function(_, _, value)
			addon.db["monk_HideHarmonyBar"] = value
			if value then
				if MonkHarmonyBarFrame then MonkHarmonyBarFrame:Hide() end
			else
				if MonkHarmonyBarFrame then MonkHarmonyBarFrame:Show() end
			end
		end)
		groupClass:AddChild(cb)
		addTotemCheckbox("monk_HideTotemBar")
	elseif classname == "PRIEST" then
		addTotemCheckbox("priest_HideTotemBar")
	elseif classname == "SHAMAN" then
		addTotemCheckbox("shaman_HideTotem")
	elseif classname == "ROGUE" then
		local cb = addon.functions.createCheckboxAce(L["rogue_HideComboPoint"], addon.db["rogue_HideComboPoint"], function(_, _, value)
			addon.db["rogue_HideComboPoint"] = value
			if value then
				if RogueComboPointBarFrame then RogueComboPointBarFrame:Hide() end
			else
				if RogueComboPointBarFrame then RogueComboPointBarFrame:Show() end
			end
		end)
		groupClass:AddChild(cb)
	elseif classname == "PALADIN" then
		local cb = addon.functions.createCheckboxAce(L["paladin_HideHolyPower"], addon.db["paladin_HideHolyPower"], function(_, _, value)
			addon.db["paladin_HideHolyPower"] = value
			if value then
				if PaladinPowerBarFrame then PaladinPowerBarFrame:Hide() end
			else
				if PaladinPowerBarFrame then PaladinPowerBarFrame:Show() end
			end
		end)
		groupClass:AddChild(cb)
		addTotemCheckbox("paladin_HideTotemBar")
	elseif classname == "WARLOCK" then
		local cb = addon.functions.createCheckboxAce(L["warlock_HideSoulShardBar"], addon.db["warlock_HideSoulShardBar"], function(_, _, value)
			addon.db["warlock_HideSoulShardBar"] = value
			if value then
				if WarlockPowerFrame then WarlockPowerFrame:Hide() end
			else
				if WarlockPowerFrame then WarlockPowerFrame:Show() end
			end
		end)
		groupClass:AddChild(cb)
		addTotemCheckbox("warlock_HideTotemBar")
	end

	scroll:DoLayout()
	wrapper:DoLayout()
end

-- Returns the raw Misc options table so we can reuse subsets in other views
local function getMiscOptions()
	local data = {
		{
			parent = "",
			var = "automaticallyOpenContainer",
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["automaticallyOpenContainer"] = value
				if addon.ContainerActions and addon.ContainerActions.OnSettingChanged then addon.ContainerActions:OnSettingChanged(value) end
			end,
		},
	}
	return data
end

-- Helper to render only a subset of the misc options by var name
local function addMiscSubsetFrame(container, include)
	local list = {}
	local allowed = {}
	for _, k in ipairs(include or {}) do
		allowed[k] = true
	end
	for _, entry in ipairs(getMiscOptions()) do
		if allowed[entry.var] then table.insert(list, entry) end
	end

	-- Keep original simple checkbox look used in Misc
	table.sort(list, function(a, b)
		local ta = a.text or L[a.var]
		local tb = b.text or L[b.var]
		return ta < tb
	end)

	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)

	for _, checkboxData in ipairs(list) do
		local desc = checkboxData.desc
		local text = checkboxData.text or L[checkboxData.var]
		local uFunc = checkboxData.callback or function(self, _, value) addon.db[checkboxData.var] = value end
		local cb = addon.functions.createCheckboxAce(text, addon.db[checkboxData.var], uFunc, desc)
		groupCore:AddChild(cb)
	end

	scroll:DoLayout()
end

local function addContainerActionsFrame(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "List")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	wrapper:SetFullWidth(true)
	scroll:AddChild(wrapper)

	local group = addon.functions.createContainer("InlineGroup", "List")
	group:SetFullWidth(true)
	group:SetTitle(L["ContainerActions"])
	wrapper:AddChild(group)

	if addon.ContainerActions and addon.ContainerActions.Init then addon.ContainerActions:Init() end

	local featureDesc = L["containerActionsFeatureDesc"]
	if featureDesc and featureDesc ~= "" then
		local featureLabel = addon.functions.createLabelAce(featureDesc, { r = 0.8, g = 0.8, b = 0.8 })
		featureLabel:SetFullWidth(true)
		group:AddChild(featureLabel)
	end

	local checkbox = addon.functions.createCheckboxAce(L["automaticallyOpenContainer"], addon.db["automaticallyOpenContainer"], function(_, _, value)
		addon.db["automaticallyOpenContainer"] = value
		if addon.ContainerActions and addon.ContainerActions.OnSettingChanged then addon.ContainerActions:OnSettingChanged(value) end
	end)
	group:AddChild(checkbox)

	local desc = L["containerActionsEditModeHint"] or L["containerActionsAnchorHelp"]
	if desc and desc ~= "" then
		local helpLabel = addon.functions.createLabelAce(desc, { r = 0.8, g = 0.8, b = 0.8 })
		helpLabel:SetFullWidth(true)
		group:AddChild(helpLabel)
	end

	local managedGroup = addon.functions.createContainer("InlineGroup", "List")
	managedGroup:SetFullWidth(true)
	managedGroup:SetTitle(L["containerActionsManagedItems"])
	group:AddChild(managedGroup)

	local blacklistDesc = L["containerActionsBlacklistDesc"]
	if blacklistDesc and blacklistDesc ~= "" then
		local descLabel = addon.functions.createLabelAce(blacklistDesc, { r = 0.8, g = 0.8, b = 0.8 })
		descLabel:SetFullWidth(true)
		managedGroup:AddChild(descLabel)
	end

	local blacklistHint = L["containerActionsBlacklistHint"]
	if blacklistHint and blacklistHint ~= "" then
		local hintLabel = addon.functions.createLabelAce(blacklistHint, { r = 0.6, g = 0.9, b = 0.6 })
		hintLabel:SetFullWidth(true)
		managedGroup:AddChild(hintLabel)
	end

	local blacklistDropdown = AceGUI:Create("Dropdown")
	blacklistDropdown:SetFullWidth(true)
	blacklistDropdown:SetLabel(L["containerActionsBlacklistLabel"])

	local removeButton = AceGUI:Create("Button")
	removeButton:SetText(L["containerActionsBlacklistRemove"])
	removeButton:SetDisabled(true)

	local selectedBlacklistID
	local function refreshBlacklistDropdown(selectedID)
		if not addon.ContainerActions then return end
		local entries = addon.ContainerActions:GetBlacklistEntries()
		local list, order = {}, {}
		local entryFormat = L["containerActionsBlacklistEntry"] or "%s - %d"
		for _, data in ipairs(entries) do
			local displayName = data.name or ("item:" .. data.itemID)
			local ok, line = pcall(string.format, entryFormat, displayName, data.itemID)
			if not ok then line = ("%s - %d"):format(displayName, data.itemID) end
			local key = tostring(data.itemID)
			list[key] = line
			order[#order + 1] = key
		end
		blacklistDropdown:SetList(list, order)
		if #order == 0 then
			blacklistDropdown:SetText(L["containerActionsBlacklistEmpty"])
			blacklistDropdown:SetValue(nil)
			removeButton:SetDisabled(true)
			selectedBlacklistID = nil
			return
		end
		if selectedID then
			local key = tostring(selectedID)
			if list[key] then
				blacklistDropdown:SetValue(key)
				removeButton:SetDisabled(false)
				selectedBlacklistID = tonumber(key)
				return
			end
		end
		blacklistDropdown:SetValue(nil)
		removeButton:SetDisabled(true)
		selectedBlacklistID = nil
	end

	blacklistDropdown:SetCallback("OnValueChanged", function(_, _, key)
		if key then
			selectedBlacklistID = tonumber(key)
			removeButton:SetDisabled(false)
		else
			selectedBlacklistID = nil
			removeButton:SetDisabled(true)
		end
	end)

	refreshBlacklistDropdown()
	managedGroup:AddChild(blacklistDropdown)

	removeButton:SetCallback("OnClick", function()
		if not selectedBlacklistID or not addon.ContainerActions then return end
		local ok, reason = addon.ContainerActions:RemoveItemFromBlacklist(selectedBlacklistID)
		if not ok then
			addon.ContainerActions:HandleBlacklistError(reason, selectedBlacklistID)
		else
			refreshBlacklistDropdown()
		end
	end)
	removeButton:SetFullWidth(true)
	managedGroup:AddChild(removeButton)

	local addBox = AceGUI:Create("EditBox")
	addBox:SetFullWidth(true)
	addBox:SetLabel(L["containerActionsBlacklistAddLabel"])
	if addBox.SetPlaceholderText then addBox:SetPlaceholderText(L["containerActionsBlacklistAddPlaceholder"]) end
	addBox:SetCallback("OnEnterPressed", function(widget, _, text)
		if not addon.ContainerActions then return end
		local itemID = addon.ContainerActions:ParseInputToItemID(text)
		if not itemID then
			addon.ContainerActions:HandleBlacklistError("invalid")
			return
		end
		local ok, reason = addon.ContainerActions:AddItemToBlacklist(itemID)
		if ok then
			widget:SetText("")
			widget:ClearFocus()
			refreshBlacklistDropdown(itemID)
		else
			addon.ContainerActions:HandleBlacklistError(reason, itemID)
		end
	end)
	managedGroup:AddChild(addBox)

	scroll:DoLayout()
	wrapper:DoLayout()
	group:DoLayout()
	managedGroup:DoLayout()
end

-- Check if a misc option exists (avoids empty debug-only pages)
local function hasMiscOption(var)
	for _, entry in ipairs(getMiscOptions()) do
		if entry.var == var then return true end
	end
	return false
end

-- Show a simple informational text on empty category roots

local initLootToast

local function addLootFrame(container, d)
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
			parent = "",
			var = "autoQuickLoot",
			desc = L["autoQuickLootDesc"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["autoQuickLoot"] = value
				container:ReleaseChildren()
				addLootFrame(container)
			end,
		},
		{
			parent = "",
			var = "autoHideBossBanner",
			text = L["autoHideBossBanner"],
			desc = L["autoHideBossBannerDesc"],
			type = "CheckBox",
			callback = function(self, _, value) addon.db["autoHideBossBanner"] = value end,
		},
		{
			parent = "",
			var = "hideAzeriteToast",
			text = L["hideAzeriteToast"],
			desc = L["hideAzeriteToastDesc"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["hideAzeriteToast"] = value
				if value then
					if AzeriteLevelUpToast then
						AzeriteLevelUpToast:UnregisterAllEvents()
						AzeriteLevelUpToast:Hide()
					end
				else
					addon.variables.requireReload = true
					addon.functions.checkReloadFrame()
				end
			end,
		},
	}

	table.sort(data, function(a, b)
		local textA = a.text or L[a.var]
		local textB = b.text or L[b.var]
		return textA < textB
	end)

	for _, checkboxData in ipairs(data) do
		local desc
		if checkboxData.desc then desc = checkboxData.desc end
		local text
		if checkboxData.text then
			text = checkboxData.text
		else
			text = L[checkboxData.var]
		end
		local uFunc = function(self, _, value) addon.db[checkboxData.var] = value end
		if checkboxData.callback then uFunc = checkboxData.callback end
		local cb = addon.functions.createCheckboxAce(text, addon.db[checkboxData.var], uFunc, desc)
		groupCore:AddChild(cb)
	end

	if addon.db["autoQuickLoot"] then
		local cbShift = addon.functions.createCheckboxAce(L["autoQuickLootWithShift"], addon.db["autoQuickLootWithShift"], function(self, _, value) addon.db["autoQuickLootWithShift"] = value end)
		groupCore:AddChild(cbShift)
	end

	local lootToastGroup = addon.functions.createContainer("InlineGroup", "List")
	lootToastGroup:SetTitle(L["lootToastSectionTitle"])
	wrapper:AddChild(lootToastGroup)

	local anchorToggle = addon.functions.createCheckboxAce(L["moveLootToast"], addon.db.enableLootToastAnchor, function(self, _, value)
		addon.db.enableLootToastAnchor = value
		if addon.LootToast and addon.LootToast.OnAnchorOptionChanged then addon.LootToast:OnAnchorOptionChanged(value) end
		initLootToast()
		container:ReleaseChildren()
		addLootFrame(container)
	end, L["moveLootToastDesc"])
	lootToastGroup:AddChild(anchorToggle)

	local anchorButton = addon.functions.createButtonAce(L["lootToastAnchorButton"], 200, function()
		if not addon.db.enableLootToastAnchor then return end
		addon.LootToast:ToggleAnchorPreview()
	end)
	anchorButton:SetFullWidth(true)
	anchorButton:SetDisabled(not addon.db.enableLootToastAnchor)
	lootToastGroup:AddChild(anchorButton)

	local anchorLabel = addon.functions.createLabelAce("")
	anchorLabel:SetFullWidth(true)
	local anchorHelp = L["lootToastAnchorHelp"] or L["lootToastAnchorLabel"] or ""
	if not addon.db.enableLootToastAnchor then
		anchorHelp = "|cff999999" .. anchorHelp .. "|r"
	else
		anchorHelp = "|cffffd700" .. anchorHelp .. "|r"
	end
	anchorLabel:SetText(anchorHelp)
	lootToastGroup:AddChild(anchorLabel)

	local filterToggle = addon.functions.createCheckboxAce(L["enableLootToastFilter"], addon.db.enableLootToastFilter, function(self, _, value)
		addon.db.enableLootToastFilter = value
		initLootToast()
		container:ReleaseChildren()
		addLootFrame(container)
	end, L["enableLootToastFilterDesc"])
	lootToastGroup:AddChild(filterToggle)

	if addon.db.enableLootToastFilter then
		local filterGroup = addon.functions.createContainer("InlineGroup", "List")
		filterGroup:SetTitle(L["lootToastFilterSettings"])
		lootToastGroup:AddChild(filterGroup)

		local tabs = {
			{ text = ITEM_QUALITY3_DESC, value = tostring(Enum.ItemQuality.Rare) },
			{ text = ITEM_QUALITY4_DESC, value = tostring(Enum.ItemQuality.Epic) },
			{ text = ITEM_QUALITY5_DESC, value = tostring(Enum.ItemQuality.Legendary) },
			{ text = L["Include"], value = "include" },
		}

		local function buildTab(tabContainer, rarity)
			tabContainer:ReleaseChildren()
			if rarity == "include" then
				local eBox
				local dropIncludeList

				local function addInclude(input)
					local id = tonumber(input)
					if not id then id = tonumber(string.match(tostring(input), "item:(%d+)")) end
					if not id then
						print("|cffff0000Invalid input!|r")
						eBox:SetText("")
						return
					end
					local eItem
					if type(input) == "string" and input:find("|Hitem:") then
						eItem = Item:CreateFromItemLink(input)
					else
						eItem = Item:CreateFromItemID(id)
					end
					if eItem and not eItem:IsItemEmpty() then
						eItem:ContinueOnItemLoad(function()
							local name = eItem:GetItemName()
							if not name then
								print(L["Item id does not exist"])
								eBox:SetText("")
								return
							end
							if not addon.db.lootToastIncludeIDs[eItem:GetItemID()] then
								addon.db.lootToastIncludeIDs[eItem:GetItemID()] = string.format("%s (%d)", name, eItem:GetItemID())
								local list, order = addon.functions.prepareListForDropdown(addon.db.lootToastIncludeIDs)
								dropIncludeList:SetList(list, order)
								dropIncludeList:SetValue(nil)
								print(L["lootToastItemAdded"]:format(name, eItem:GetItemID()))
							end
							eBox:SetText("")
						end)
					else
						print(L["Item id does not exist"])
						eBox:SetText("")
					end
				end

				eBox = addon.functions.createEditboxAce(L["Item id or drag item"], nil, function(self, _, txt)
					if txt ~= "" and txt ~= L["Item id or drag item"] then addInclude(txt) end
				end)
				tabContainer:AddChild(eBox)

				local list, order = addon.functions.prepareListForDropdown(addon.db.lootToastIncludeIDs)
				dropIncludeList = addon.functions.createDropdownAce(L["IncludeVendorList"], list, order, nil)
				local btnRemove = addon.functions.createButtonAce(REMOVE, 100, function()
					local sel = dropIncludeList:GetValue()
					if sel then
						addon.db.lootToastIncludeIDs[sel] = nil
						local l, o = addon.functions.prepareListForDropdown(addon.db.lootToastIncludeIDs)
						dropIncludeList:SetList(l, o)
						dropIncludeList:SetValue(nil)
					end
				end)
				local label = addon.functions.createLabelAce("", nil, nil, 14)
				label:SetFullWidth(true)
				tabContainer:AddChild(label)
				label:SetText("|cffffd700" .. L["includeInfoLoot"] .. "|r")
				tabContainer:AddChild(dropIncludeList)
				tabContainer:AddChild(btnRemove)
			else
				local q = tonumber(rarity)
				local filter = addon.db.lootToastFilters[q]
				local label = addon.functions.createLabelAce("", nil, nil, 14)
				label:SetFullWidth(true)
				tabContainer:AddChild(label)

				local function refreshLabel()
					local text
					if rarity ~= "include" then
						local extras = {}
						if filter.mounts then table.insert(extras, MOUNTS:lower()) end
						if filter.pets then table.insert(extras, PETS:lower()) end
						if filter.upgrade then table.insert(extras, L["lootToastExtrasUpgrades"]) end
						local eText = ""
						if #extras > 0 then eText = L["alwaysShow"] .. table.concat(extras, " " .. L["andWord"] .. " ") end
						if filter.ilvl then
							text = L["lootToastSummaryIlvl"]:format(addon.db.lootToastItemLevels[q], eText)
						else
							text = L["lootToastSummaryNoIlvl"]:format(eText)
						end
					else
						text = L["lootToastExplanation"]
					end
					label:SetText("|cffffd700" .. text .. "|r")
				end

				tabContainer:AddChild(addon.functions.createCheckboxAce(L["lootToastCheckIlvl"], filter.ilvl, function(self, _, v)
					addon.db.lootToastFilters[q].ilvl = v
					filter.ilvl = v
					refreshLabel()
				end))
				local slider = addon.functions.createSliderAce(L["lootToastItemLevel"] .. ": " .. addon.db.lootToastItemLevels[q], addon.db.lootToastItemLevels[q], 0, 1000, 1, function(self, _, val)
					addon.db.lootToastItemLevels[q] = val
					self:SetLabel(L["lootToastItemLevel"] .. ": " .. val)
					refreshLabel()
				end)
				tabContainer:AddChild(slider)

				local alwaysList = {
					mounts = L["lootToastAlwaysShowMounts"],
					pets = L["lootToastAlwaysShowPets"],
					upgrade = L["lootToastAlwaysShowUpgrades"],
				}
				local alwaysOrder = { "mounts", "pets", "upgrade" }
				local dropdownAlways = addon.functions.createDropdownAce(L["lootToastAlwaysShow"], alwaysList, alwaysOrder, function(self, _, key, checked)
					if not key then return end
					local isChecked = checked and true or false
					if addon.db.lootToastFilters[q][key] ~= nil then
						addon.db.lootToastFilters[q][key] = isChecked
						filter[key] = isChecked
						self:SetItemValue(key, isChecked)
						refreshLabel()
					end
				end)
				dropdownAlways:SetMultiselect(true)
				for _, key in ipairs(alwaysOrder) do
					dropdownAlways:SetItemValue(key, not not filter[key])
				end
				tabContainer:AddChild(dropdownAlways)

				refreshLabel()
			end
			scroll:DoLayout()
		end

		local cbSound = addon.functions.createCheckboxAce(L["enableLootToastCustomSound"], addon.db.lootToastUseCustomSound, function(self, _, v)
			addon.db.lootToastUseCustomSound = v
			container:ReleaseChildren()
			addLootFrame(container)
		end)
		filterGroup:AddChild(cbSound)

		if addon.db.lootToastUseCustomSound then
			if addon.ChatIM and addon.ChatIM.BuildSoundTable and not addon.ChatIM.availableSounds then addon.ChatIM:BuildSoundTable() end
			local soundList = {}
			for name in pairs(addon.ChatIM.availableSounds or {}) do
				soundList[name] = name
			end
			local list, order = addon.functions.prepareListForDropdown(soundList)
			local dropSound = addon.functions.createDropdownAce(L["lootToastCustomSound"], list, order, function(self, _, val)
				addon.db.lootToastCustomSoundFile = val
				self:SetValue(val)
				local file = addon.ChatIM.availableSounds and addon.ChatIM.availableSounds[val]
				if file then PlaySoundFile(file, "Master") end
			end)
			dropSound:SetValue(addon.db.lootToastCustomSoundFile)
			filterGroup:AddChild(dropSound)
		end

		local tabGroup = addon.functions.createContainer("TabGroup", "Flow")
		tabGroup:SetTabs(tabs)
		tabGroup:SetCallback("OnGroupSelected", function(tabContainer, _, groupVal) buildTab(tabContainer, groupVal) end)
		filterGroup:AddChild(tabGroup)
		tabGroup:SelectTab(tabs[1].value)
	end

	scroll:DoLayout()
end

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

local function addSocialFrame(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "List")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)

	local data = {
		{
			parent = "",
			var = "blockDuelRequests",
			text = L["blockDuelRequests"],
			type = "CheckBox",
			callback = function(self, _, value) addon.db["blockDuelRequests"] = value end,
		},
		{
			parent = "",
			var = "blockPetBattleRequests",
			text = L["blockPetBattleRequests"],
			type = "CheckBox",
			callback = function(self, _, value) addon.db["blockPetBattleRequests"] = value end,
		},
		{
			parent = "",
			var = "blockPartyInvites",
			text = L["blockPartyInvites"],
			type = "CheckBox",
			callback = function(self, _, value) addon.db["blockPartyInvites"] = value end,
		},
		{
			parent = "",
			var = "enableIgnore",
			text = L["EnableAdvancedIgnore"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["enableIgnore"] = value
				if addon.Ignore and addon.Ignore.SetEnabled then addon.Ignore:SetEnabled(value) end
				container:ReleaseChildren()
				addSocialFrame(container)
			end,
		},
	}
	if addon.db["enableIgnore"] then
		table.insert(data, {
			parent = "",
			var = "ignoreAttachFriendsFrame",
			text = L["IgnoreAttachFriends"],
			desc = L["IgnoreAttachFriendsDesc"],
			type = "CheckBox",
			callback = function(self, _, value) addon.db["ignoreAttachFriendsFrame"] = value end,
		})
		table.insert(data, {
			parent = "",
			var = "ignoreAnchorFriendsFrame",
			text = L["IgnoreAnchorFriends"],
			desc = L["IgnoreAnchorFriendsDesc"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["ignoreAnchorFriendsFrame"] = value
				if addon.Ignore and addon.Ignore.UpdateAnchor then addon.Ignore:UpdateAnchor() end
			end,
		})
		table.insert(data, {
			parent = "",
			var = "ignoreTooltipNote",
			text = L["IgnoreTooltipNote"],
			type = "CheckBox",
			callback = function(self, _, value)
				addon.db["ignoreTooltipNote"] = value
				container:ReleaseChildren()
				addSocialFrame(container)
			end,
			desc = L["IgnoreNoteDesc"],
		})
	end

	table.sort(data, function(a, b)
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

	for _, checkboxData in ipairs(data) do
		local desc
		if checkboxData.desc then desc = checkboxData.desc end
		local cb = addon.functions.createCheckboxAce(checkboxData.text, addon.db[checkboxData.var], checkboxData.callback, desc)
		groupCore:AddChild(cb)
	end

	-- Inline section for auto-accept invites
	local groupInv = addon.functions.createContainer("InlineGroup", "List")
	groupInv:SetTitle(L["autoAcceptGroupInvite"]) -- Section title
	wrapper:AddChild(groupInv)

	local cbMain = addon.functions.createCheckboxAce(L["autoAcceptGroupInvite"], addon.db["autoAcceptGroupInvite"], function(self, _, value)
		addon.db["autoAcceptGroupInvite"] = value
		container:ReleaseChildren()
		addSocialFrame(container)
	end)
	groupInv:AddChild(cbMain)

	if addon.db["autoAcceptGroupInvite"] then
		local lbl = addon.functions.createLabelAce("|cffffd700" .. L["autoAcceptGroupInviteOptions"] .. "|r", nil, nil, 12)
		lbl:SetFullWidth(true)
		groupInv:AddChild(lbl)

		local cbGuild = addon.functions.createCheckboxAce(
			L["autoAcceptGroupInviteGuildOnly"],
			addon.db["autoAcceptGroupInviteGuildOnly"],
			function(self, _, value) addon.db["autoAcceptGroupInviteGuildOnly"] = value end
		)
		groupInv:AddChild(cbGuild)

		local cbFriends = addon.functions.createCheckboxAce(
			L["autoAcceptGroupInviteFriendOnly"],
			addon.db["autoAcceptGroupInviteFriendOnly"],
			function(self, _, value) addon.db["autoAcceptGroupInviteFriendOnly"] = value end
		)
		groupInv:AddChild(cbFriends)
	end
	if addon.db["ignoreTooltipNote"] then
		local sliderMaxChars = addon.functions.createSliderAce(
			L["IgnoreTooltipMaxChars"] .. ": " .. addon.db["ignoreTooltipMaxChars"],
			addon.db["ignoreTooltipMaxChars"],
			20,
			200,
			1,
			function(self, _, val)
				addon.db["ignoreTooltipMaxChars"] = val
				self:SetLabel(L["IgnoreTooltipMaxChars"] .. ": " .. val)
			end
		)
		groupCore:AddChild(sliderMaxChars)

		local sliderWords = addon.functions.createSliderAce(
			L["IgnoreTooltipWordsPerLine"] .. ": " .. addon.db["ignoreTooltipWordsPerLine"],
			addon.db["ignoreTooltipWordsPerLine"],
			1,
			20,
			1,
			function(self, _, val)
				addon.db["ignoreTooltipWordsPerLine"] = val
				self:SetLabel(L["IgnoreTooltipWordsPerLine"] .. ": " .. val)
			end
		)
		groupCore:AddChild(sliderWords)

		groupCore:AddChild(addon.functions.createSpacerAce())
	end

	local labelHeadline = addon.functions.createLabelAce("|cffffd700" .. L["IgnoreDesc"], nil, nil, 14)
	labelHeadline:SetFullWidth(true)
	groupCore:AddChild(labelHeadline)
	container:DoLayout()
	wrapper:DoLayout()
	groupCore:DoLayout()
	groupInv:DoLayout()
	scroll:DoLayout()
end

local function buildDatapanelFrame(container)
	local DataPanel = addon.DataPanel
	local DataHub = addon.DataHub
	local panels = DataPanel.List()

	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	-- Panel management controls
	local controlGroup = addon.functions.createContainer("InlineGroup", "Flow")
	controlGroup:SetTitle(L["Panels"] or "Panels")
	wrapper:AddChild(controlGroup)

	-- Global option: require Shift to move panels
	addon.db = addon.db or {}
	addon.db.dataPanelsOptions = addon.db.dataPanelsOptions or {}
	local shiftLock = addon.functions.createCheckboxAce(
		L["Lock DataPanel position (hold Shift to move)"] or "Lock DataPanel position (hold Shift to move)",
		addon.db.dataPanelsOptions.requireShiftToMove == true,
		function(_, _, val) addon.db.dataPanelsOptions.requireShiftToMove = val and true or false end
	)
	shiftLock:SetRelativeWidth(1.0)
	controlGroup:AddChild(shiftLock)

	local hintToggle = addon.functions.createCheckboxAce(
		L["Show options tooltip hint"],
		addon.DataPanel.ShouldShowOptionsHint and addon.DataPanel.ShouldShowOptionsHint(),
		function(_, _, val)
			if addon.DataPanel.SetShowOptionsHint then addon.DataPanel.SetShowOptionsHint(val and true or false) end
			for name in pairs(DataHub.streams) do
				DataHub:RequestUpdate(name)
			end
		end
	)
	hintToggle:SetRelativeWidth(1.0)
	controlGroup:AddChild(hintToggle)

	addon.db.dataPanelsOptions.menuModifier = addon.db.dataPanelsOptions.menuModifier or "NONE"
	local modifierList = {
		NONE = L["Context menu modifier: None"] or (NONE or "None"),
		SHIFT = SHIFT_KEY_TEXT or "Shift",
		CTRL = CTRL_KEY_TEXT or "Ctrl",
		ALT = ALT_KEY_TEXT or "Alt",
	}
	local modifierOrder = { "NONE", "SHIFT", "CTRL", "ALT" }
	local modifierDropdown = addon.functions.createDropdownAce(
		L["Context menu modifier"] or "Context menu modifier",
		modifierList,
		modifierOrder,
		function(widget, _, key)
			if addon.DataPanel.SetMenuModifier then addon.DataPanel.SetMenuModifier(key) end
			if widget and widget.SetValue then widget:SetValue(key) end
		end
	)
	if modifierDropdown.SetValue then modifierDropdown:SetValue(addon.DataPanel.GetMenuModifier and addon.DataPanel.GetMenuModifier() or "NONE") end
	modifierDropdown:SetRelativeWidth(1.0)
	controlGroup:AddChild(modifierDropdown)

	local newName = addon.functions.createEditboxAce(L["Panel Name"] or "Panel Name")
	newName:SetRelativeWidth(0.4)
	controlGroup:AddChild(newName)

	local addButton = addon.functions.createButtonAce(L["Add Panel"] or "Add Panel", 120, function()
		local id = newName:GetText()
		if id and id ~= "" then
			DataPanel.Create(id)
			container:ReleaseChildren()
			buildDatapanelFrame(container)
		end
	end)
	addButton:SetRelativeWidth(0.3)
	controlGroup:AddChild(addButton)

	local panelList, panelOrder = {}, {}
	for id in pairs(panels) do
		panelList[id] = id
		panelOrder[#panelOrder + 1] = id
	end
	table.sort(panelOrder)

	local dropRemove = addon.functions.createDropdownAce(L["Panel"] or "Panel", panelList, panelOrder, function(self, _, val) self:SetValue(val) end)
	dropRemove:SetRelativeWidth(0.4)
	controlGroup:AddChild(dropRemove)

	local removeButton = addon.functions.createButtonAce(L["Remove Panel"] or "Remove Panel", 120, function()
		local id = dropRemove:GetValue()
		if id then
			DataPanel.Delete(id)
			container:ReleaseChildren()
			buildDatapanelFrame(container)
		end
	end)
	removeButton:SetRelativeWidth(0.3)
	controlGroup:AddChild(removeButton)

	local editModeHint = addon.functions.createLabelAce(
		"|cffffd700" .. (L["DataPanelEditModeHint"] or "Configure DataPanels in Edit Mode.") .. "|r",
		nil,
		nil,
		12
	)
	editModeHint:SetFullWidth(true)
	wrapper:AddChild(editModeHint)
	scroll:DoLayout()
end

local TooltipUtil = _G.TooltipUtil

local function merchantItemIsKnown(itemIndex)
	if not itemIndex or itemIndex <= 0 then return false end
	if not C_TooltipInfo or (not C_TooltipInfo.GetMerchantItem and not C_TooltipInfo.GetHyperlink) then return false end

	local tooltipData
	if C_TooltipInfo.GetMerchantItem then tooltipData = C_TooltipInfo.GetMerchantItem(itemIndex) end

	if not tooltipData and C_TooltipInfo.GetHyperlink and GetMerchantItemLink then
		local itemLink = GetMerchantItemLink(itemIndex)
		if itemLink then tooltipData = C_TooltipInfo.GetHyperlink(itemLink) end
	end

	if not tooltipData then return false end
	if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(tooltipData) end
	if not tooltipData.lines then return false end
	for _, line in ipairs(tooltipData.lines) do
		if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(line) end
		local text = line.leftText or line.rightText
		if text and text:find(ITEM_SPELL_KNOWN, 1, true) then return true end
	end
	return false
end

local petCollectedCache = {}

local function clearPetCollectedCache() wipe(petCollectedCache) end

local function getPetCollectedCount(speciesID)
	if not speciesID then return 0 end
	local cached = petCollectedCache[speciesID]
	if cached ~= nil then return cached end
	if not C_PetJournal or not C_PetJournal.GetNumCollectedInfo then return 0 end
	local numCollected = C_PetJournal.GetNumCollectedInfo(speciesID) or 0
	petCollectedCache[speciesID] = numCollected
	return numCollected
end

local function IsPetAlreadyCollectedFromItem(itemID)
	if not C_PetJournal or not C_PetJournal.GetNumCollectedInfo then return false end
	if not itemID then return false end

	if not C_PetJournal.GetPetInfoByItemID then return false end

	local speciesID = select(13, C_PetJournal.GetPetInfoByItemID(itemID))
	if not speciesID then return false end

	local count = getPetCollectedCount(speciesID)
	return count > 0
end

if C_PetJournal then
	local petJournalWatcher = CreateFrame("Frame")
	petJournalWatcher:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
	petJournalWatcher:RegisterEvent("PET_JOURNAL_PET_DELETED")
	petJournalWatcher:RegisterEvent("PET_JOURNAL_PET_RESTORED")
	petJournalWatcher:RegisterEvent("NEW_PET_ADDED")
	petJournalWatcher:SetScript("OnEvent", clearPetCollectedCache)
end

--[[
        Applies or removes a desaturation effect on the merchant item button icon. This mirrors
        the "greyed out" visual feedback players are familiar with from the default UI when an
        item cannot be interacted with.
]]
local function desaturateMerchantIcon(itemButton, desaturate)
	if not itemButton then return end

	local iconTexture = itemButton.Icon or itemButton.icon or itemButton.IconTexture or itemButton:GetNormalTexture()
	if iconTexture then
		if iconTexture.SetDesaturated then iconTexture:SetDesaturated(desaturate) end
		if iconTexture.SetVertexColor then
			if desaturate then
				iconTexture:SetVertexColor(0.7, 0.7, 0.7, 1)
			else
				iconTexture:SetVertexColor(1, 1, 1, 1)
			end
		end
	end
end

local function applyKnownFontTint(fontString, state)
	if not fontString or fontString.GetObjectType and fontString:GetObjectType() ~= "FontString" then return end
	if state then
		if not fontString.__EnhanceQoLOriginalColor then
			local r, g, b, a = fontString:GetTextColor()
			if not r or not g or not b then
				r, g, b = 1, 1, 1
			end
			if not a then a = 1 end
			fontString.__EnhanceQoLOriginalColor = { r, g, b, a }
		end
		local stored = fontString.__EnhanceQoLOriginalColor
		local r, g, b = stored[1], stored[2], stored[3]
		fontString:SetTextColor(r or 1, g or 1, b or 1, 0.4)
	elseif fontString.__EnhanceQoLOriginalColor then
		local color = fontString.__EnhanceQoLOriginalColor
		fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
		fontString.__EnhanceQoLOriginalColor = nil
	end
end

local function applyKnownTextureTint(texture, state)
	if not texture or texture.GetObjectType and texture:GetObjectType() ~= "Texture" then return end
	if state then
		if not texture.__EnhanceQoLOriginalVertexColor then
			local r, g, b, a = texture:GetVertexColor()
			if not r or not g or not b then
				r, g, b = 1, 1, 1
			end
			if not a or a == 0 then a = texture:GetAlpha() or 1 end
			texture.__EnhanceQoLOriginalVertexColor = { r, g, b, a }
		end
		local stored = texture.__EnhanceQoLOriginalVertexColor
		texture:SetVertexColor(0.55, 0.55, 0.55, stored and stored[4] or texture:GetAlpha() or 1)
	else
		local color = texture.__EnhanceQoLOriginalVertexColor
		if color then
			texture:SetVertexColor(color[1], color[2], color[3], color[4] or texture:GetAlpha() or 1)
			texture.__EnhanceQoLOriginalVertexColor = nil
		end
	end
end

local function applyKnownStateToFrame(frame, state, visited)
	if not frame or visited[frame] then return end
	visited[frame] = true

	local objectType = frame.GetObjectType and frame:GetObjectType()
	if objectType == "FontString" then
		applyKnownFontTint(frame, state)
		return
	elseif objectType == "Texture" then
		applyKnownTextureTint(frame, state)
		return
	end

	if frame.GetRegions then
		local regions = { frame:GetRegions() }
		for _, region in ipairs(regions) do
			applyKnownStateToFrame(region, state, visited)
		end
	end

	if frame.GetChildren then
		local children = { frame:GetChildren() }
		for _, child in ipairs(children) do
			applyKnownStateToFrame(child, state, visited)
		end
	end
end

local function setMerchantKnownIcon(itemButton, state)
	if not itemButton then return end

	if state then
		if not itemButton.MerchantKnownIcon then
			local icon = itemButton:CreateTexture(nil, "OVERLAY", nil, 7)
			if icon.SetAtlas and icon:SetAtlas("common-icon-checkmark") then
				icon:SetTexCoord(0, 1, 0, 1)
			else
				icon:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
			end
			icon:SetSize(18, 18)
			icon:SetPoint("TOPLEFT", itemButton, "TOPLEFT", -2, 2)
			icon:SetVertexColor(0.2, 0.9, 0.2, 0.9)
			itemButton.MerchantKnownIcon = icon
		end
		itemButton.MerchantKnownIcon:Show()
		if not itemButton.MerchantKnownOverlay then
			local overlay = itemButton:CreateTexture(nil, "OVERLAY", nil, 7)
			overlay:SetAllPoints()
			overlay:SetColorTexture(0.1, 0.1, 0.1, 0.55)
			itemButton.MerchantKnownOverlay = overlay
		end
		itemButton.MerchantKnownOverlay:Show()
		desaturateMerchantIcon(itemButton, true)
		local parentFrame = itemButton:GetParent()
		if parentFrame then
			local parentName = parentFrame:GetName()
			local nameRegion = parentFrame.Name or (parentName and _G[parentName .. "Name"])
			if nameRegion then applyKnownFontTint(nameRegion, true) end

			local moneyFrame = parentFrame.MoneyFrame or (parentName and _G[parentName .. "MoneyFrame"])
			if moneyFrame then applyKnownStateToFrame(moneyFrame, true, {}) end

			local altCurrencyFrame = parentFrame.AltCurrencyFrame or (parentName and _G[parentName .. "AltCurrencyFrame"])
			if altCurrencyFrame then applyKnownStateToFrame(altCurrencyFrame, true, {}) end
		end
	else
		if itemButton.MerchantKnownIcon then itemButton.MerchantKnownIcon:Hide() end
		if itemButton.MerchantKnownOverlay then itemButton.MerchantKnownOverlay:Hide() end
		-- desaturateMerchantIcon(itemButton, false)
		local parentFrame = itemButton:GetParent()
		if parentFrame then
			local parentName = parentFrame:GetName()
			local nameRegion = parentFrame.Name or (parentName and _G[parentName .. "Name"])
			if nameRegion then applyKnownFontTint(nameRegion, false) end

			local moneyFrame = parentFrame.MoneyFrame or (parentName and _G[parentName .. "MoneyFrame"])
			if moneyFrame then applyKnownStateToFrame(moneyFrame, false, {}) end

			local altCurrencyFrame = parentFrame.AltCurrencyFrame or (parentName and _G[parentName .. "AltCurrencyFrame"])
			if altCurrencyFrame then applyKnownStateToFrame(altCurrencyFrame, false, {}) end
		end
	end
end

local function applyMerchantButtonInfo()
	local showIlvl = addon.db["showIlvlOnMerchantframe"]
	local highlightKnown = addon.db["markKnownOnMerchant"]
	local highlightCollectedPets = addon.db["markCollectedPetsOnMerchant"]
	if not showIlvl and not highlightKnown and not highlightCollectedPets then
		local itemsPerPage = MERCHANT_ITEMS_PER_PAGE or 10
		for i = 1, itemsPerPage do
			local itemButton = _G["MerchantItem" .. i .. "ItemButton"]
			if itemButton then
				setMerchantKnownIcon(itemButton, false)
				if itemButton.ItemUpgradeIcon then itemButton.ItemUpgradeIcon:Hide() end
				if itemButton.ItemUpgradeArrow then itemButton.ItemUpgradeArrow:Hide() end
				if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
				if itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
			end
		end
		return
	end

	local itemsPerPage = MERCHANT_ITEMS_PER_PAGE or 10 -- Anzahl der Items pro Seite (Standard 10)
	local currentPage = MerchantFrame.page or 1 -- Aktuelle Seite
	local startIndex = (currentPage - 1) * itemsPerPage + 1 -- Startindex basierend auf der aktuellen Seite

	for i = 1, itemsPerPage do
		local itemButton = _G["MerchantItem" .. i .. "ItemButton"]
		if itemButton then
			if not itemButton:IsShown() then
				setMerchantKnownIcon(itemButton, false)
				if itemButton.ItemUpgradeArrow then itemButton.ItemUpgradeArrow:Hide() end
				if itemButton.ItemUpgradeIcon then itemButton.ItemUpgradeIcon:Hide() end
				if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
				if itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
			else
				local itemIndex = startIndex + i - 1
				local buttonID = itemButton:GetID()
				if buttonID and buttonID > 0 then itemIndex = buttonID end

				local itemLink = itemIndex and GetMerchantItemLink(itemIndex) or nil

				if itemLink then
					local merchantButton = itemButton:GetParent()
					if merchantButton and merchantButton.GetName and merchantButton:GetName():find("^MerchantItem%d+$") then MerchantFrameItem_UpdateQuality(merchantButton, itemLink) end
				end

				local shouldHighlight = false
				if highlightKnown and merchantItemIsKnown(itemIndex) then
					shouldHighlight = true
				elseif highlightCollectedPets and itemLink then
					local itemID, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemLink)
					if classID == 15 and subclassID == 2 then
						local collected = IsPetAlreadyCollectedFromItem(itemID)
						if collected then shouldHighlight = true end
					end
				end
				setMerchantKnownIcon(itemButton, shouldHighlight)
				-- Clear any stale overlays from recycled buttons
				if itemButton.ItemUpgradeArrow then itemButton.ItemUpgradeArrow:Hide() end
				if itemButton.ItemUpgradeIcon then itemButton.ItemUpgradeIcon:Hide() end
				if itemButton.ItemUpgradeIcon then itemButton.ItemUpgradeIcon:Hide() end
				if showIlvl and itemLink and itemLink:find("item:") then
					local eItem = Item:CreateFromItemLink(itemLink)
					eItem:ContinueOnItemLoad(function()
						-- local itemName, _, _, _, _, _, _, _, itemEquipLoc = C_Item.GetItemInfo(itemLink)
						local _, _, _, _, _, _, _, _, itemEquipLoc, _, _, classID, subclassID = C_Item.GetItemInfo(itemLink)

						if
							(itemEquipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" or (classID == 4 and subclassID == 0)) and not (classID == 4 and subclassID == 5) -- Cosmetic
						then
							local link = eItem:GetItemLink()
							local invSlot = select(4, C_Item.GetItemInfoInstant(link))
							if nil == addon.variables.allowedEquipSlotsBagIlvl[invSlot] then
								if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
								if itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
								return
							end

							if not itemButton.ItemLevelText then
								itemButton.ItemLevelText = itemButton:CreateFontString(nil, "OVERLAY")
								itemButton.ItemLevelText:SetFont(addon.variables.defaultFont, 16, "OUTLINE")
								itemButton.ItemLevelText:SetShadowOffset(1, -1)
								itemButton.ItemLevelText:SetShadowColor(0, 0, 0, 1)
							end
							itemButton.ItemLevelText:ClearAllPoints()
							local pos = addon.db["bagIlvlPosition"] or "TOPRIGHT"
							if pos == "TOPLEFT" then
								itemButton.ItemLevelText:SetPoint("TOPLEFT", itemButton, "TOPLEFT", 2, -2)
							elseif pos == "BOTTOMLEFT" then
								itemButton.ItemLevelText:SetPoint("BOTTOMLEFT", itemButton, "BOTTOMLEFT", 2, 2)
							elseif pos == "BOTTOMRIGHT" then
								itemButton.ItemLevelText:SetPoint("BOTTOMRIGHT", itemButton, "BOTTOMRIGHT", -1, 2)
							else
								itemButton.ItemLevelText:SetPoint("TOPRIGHT", itemButton, "TOPRIGHT", -1, -1)
							end

							local color = eItem:GetItemQualityColor()
							local candidateIlvl = eItem:GetCurrentItemLevel()
							itemButton.ItemLevelText:SetText(candidateIlvl)
							itemButton.ItemLevelText:SetTextColor(color.r, color.g, color.b, 1)
							itemButton.ItemLevelText:Show()
							local bType

							-- Upgrade arrow for Merchant items
							if addon.db["showUpgradeArrowOnBagItems"] then
								local function getEquipSlotsFor(equipLoc)
									if equipLoc == "INVTYPE_FINGER" then
										return { 11, 12 }
									elseif equipLoc == "INVTYPE_TRINKET" then
										return { 13, 14 }
									elseif equipLoc == "INVTYPE_HEAD" then
										return { 1 }
									elseif equipLoc == "INVTYPE_NECK" then
										return { 2 }
									elseif equipLoc == "INVTYPE_SHOULDER" then
										return { 3 }
									elseif equipLoc == "INVTYPE_CLOAK" then
										return { 15 }
									elseif equipLoc == "INVTYPE_CHEST" or equipLoc == "INVTYPE_ROBE" then
										return { 5 }
									elseif equipLoc == "INVTYPE_WRIST" then
										return { 9 }
									elseif equipLoc == "INVTYPE_HAND" then
										return { 10 }
									elseif equipLoc == "INVTYPE_WAIST" then
										return { 6 }
									elseif equipLoc == "INVTYPE_LEGS" then
										return { 7 }
									elseif equipLoc == "INVTYPE_FEET" then
										return { 8 }
									elseif equipLoc == "INVTYPE_WEAPONMAINHAND" or equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" then
										return { 16 }
									elseif equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_HOLDABLE" or equipLoc == "INVTYPE_SHIELD" then
										return { 17 }
									elseif equipLoc == "INVTYPE_WEAPON" then
										return { 16, 17 }
									end
									return nil
								end

								local invSlot = select(4, C_Item.GetItemInfoInstant(itemLink))
								local slots = getEquipSlotsFor(invSlot)
								local baseline
								if slots and #slots > 0 then
									for _, s in ipairs(slots) do
										local eqLink = GetInventoryItemLink("player", s)
										local eqIlvl = eqLink and (C_Item.GetDetailedItemLevelInfo(eqLink) or 0) or 0
										if baseline == nil then
											baseline = eqIlvl
										else
											baseline = math.min(baseline, eqIlvl)
										end
									end
								end
								local isUpgrade = baseline ~= nil and candidateIlvl and candidateIlvl > baseline
								if isUpgrade then
									if not itemButton.ItemUpgradeIcon then
										itemButton.ItemUpgradeIcon = itemButton:CreateTexture(nil, "OVERLAY")
										itemButton.ItemUpgradeIcon:SetSize(14, 14)
									end
									itemButton.ItemUpgradeIcon:SetTexture("Interface\\AddOns\\EnhanceQoL\\Icons\\upgradeilvl.tga")
									itemButton.ItemUpgradeIcon:ClearAllPoints()
									local posUp = addon.db["bagUpgradeIconPosition"] or "BOTTOMRIGHT"
									if posUp == "TOPRIGHT" then
										itemButton.ItemUpgradeIcon:SetPoint("TOPRIGHT", itemButton, "TOPRIGHT", -1, -2)
									elseif posUp == "TOPLEFT" then
										itemButton.ItemUpgradeIcon:SetPoint("TOPLEFT", itemButton, "TOPLEFT", 2, -2)
									elseif posUp == "BOTTOMLEFT" then
										itemButton.ItemUpgradeIcon:SetPoint("BOTTOMLEFT", itemButton, "BOTTOMLEFT", 2, 2)
									else
										itemButton.ItemUpgradeIcon:SetPoint("BOTTOMRIGHT", itemButton, "BOTTOMRIGHT", -1, 2)
									end
									itemButton.ItemUpgradeIcon:Show()
								elseif itemButton.ItemUpgradeIcon then
									itemButton.ItemUpgradeIcon:Hide()
								end
							end

							if addon.db["showBindOnBagItems"] then
								local data = C_TooltipInfo.GetMerchantItem(itemIndex)
								for i, v in pairs(data.lines) do
									if v.type == 20 then
										if v.leftText == ITEM_BIND_ON_EQUIP then
											bType = "BoE"
										elseif v.leftText == ITEM_ACCOUNTBOUND_UNTIL_EQUIP or v.leftText == ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP then
											bType = "WuE"
										elseif v.leftText == ITEM_ACCOUNTBOUND or v.leftText == ITEM_BIND_TO_BNETACCOUNT then
											bType = "WB"
										end
										break
									end
								end
							end
							if bType then
								if not itemButton.ItemBoundType then
									itemButton.ItemBoundType = itemButton:CreateFontString(nil, "OVERLAY")
									itemButton.ItemBoundType:SetFont(addon.variables.defaultFont, 10, "OUTLINE")
									itemButton.ItemBoundType:SetShadowOffset(2, 2)
									itemButton.ItemBoundType:SetShadowColor(0, 0, 0, 1)
								end
								itemButton.ItemBoundType:ClearAllPoints()
								if addon.db["bagIlvlPosition"] == "BOTTOMLEFT" then
									itemButton.ItemBoundType:SetPoint("TOPLEFT", itemButton, "TOPLEFT", 2, -2)
								elseif addon.db["bagIlvlPosition"] == "BOTTOMRIGHT" then
									itemButton.ItemBoundType:SetPoint("TOPRIGHT", itemButton, "TOPRIGHT", -1, -2)
								else
									itemButton.ItemBoundType:SetPoint("BOTTOMLEFT", itemButton, "BOTTOMLEFT", 2, 2)
								end
								itemButton.ItemBoundType:SetFormattedText(bType)
								itemButton.ItemBoundType:Show()
							elseif itemButton.ItemBoundType then
								itemButton.ItemBoundType:Hide()
							end
						else
							if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
							if itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
						end
					end)
				else
					if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
					if itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
				end
			end
		end
	end
end

local merchantRefreshPending = false

local function updateMerchantButtonInfo()
	if merchantRefreshPending then return end
	merchantRefreshPending = true

	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			merchantRefreshPending = false
			applyMerchantButtonInfo()
		end)
	else
		merchantRefreshPending = false
		applyMerchantButtonInfo()
	end
end

local function updateBuybackButtonInfo()
	local showIlvl = addon.db["showIlvlOnMerchantframe"]
	local highlightKnown = addon.db["markKnownOnMerchant"]
	if not showIlvl and not highlightKnown then return end

	local itemsPerPage = BUYBACK_ITEMS_PER_PAGE or 12
	for i = 1, itemsPerPage do
		local itemButton = _G["MerchantItem" .. i .. "ItemButton"]
		local itemLink = GetBuybackItemLink(i)

		if itemButton then
			setMerchantKnownIcon(itemButton, false)
			if not showIlvl then
				if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
				if itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
			elseif itemLink and itemLink:find("item:") then
				local eItem = Item:CreateFromItemLink(itemLink)
				eItem:ContinueOnItemLoad(function()
					local _, _, _, _, _, _, _, _, itemEquipLoc, _, _, classID, subclassID = C_Item.GetItemInfo(itemLink)

					if (itemEquipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" or (classID == 4 and subclassID == 0)) and not (classID == 4 and subclassID == 5) then
						local link = eItem:GetItemLink()
						local invSlot = select(4, C_Item.GetItemInfoInstant(link))
						if nil == addon.variables.allowedEquipSlotsBagIlvl[invSlot] then
							if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
							if itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
							return
						end

						if not itemButton.ItemLevelText then
							itemButton.ItemLevelText = itemButton:CreateFontString(nil, "OVERLAY")
							itemButton.ItemLevelText:SetFont(addon.variables.defaultFont, 16, "OUTLINE")
							itemButton.ItemLevelText:SetShadowOffset(1, -1)
							itemButton.ItemLevelText:SetShadowColor(0, 0, 0, 1)
						end
						itemButton.ItemLevelText:ClearAllPoints()
						local pos = addon.db["bagIlvlPosition"] or "TOPRIGHT"
						if pos == "TOPLEFT" then
							itemButton.ItemLevelText:SetPoint("TOPLEFT", itemButton, "TOPLEFT", 2, -2)
						elseif pos == "BOTTOMLEFT" then
							itemButton.ItemLevelText:SetPoint("BOTTOMLEFT", itemButton, "BOTTOMLEFT", 2, 2)
						elseif pos == "BOTTOMRIGHT" then
							itemButton.ItemLevelText:SetPoint("BOTTOMRIGHT", itemButton, "BOTTOMRIGHT", -1, 2)
						else
							itemButton.ItemLevelText:SetPoint("TOPRIGHT", itemButton, "TOPRIGHT", -1, -1)
						end

						local color = eItem:GetItemQualityColor()
						itemButton.ItemLevelText:SetText(eItem:GetCurrentItemLevel())
						itemButton.ItemLevelText:SetTextColor(color.r, color.g, color.b, 1)
						itemButton.ItemLevelText:Show()

						local bType
						if addon.db["showBindOnBagItems"] then
							local data = C_TooltipInfo.GetBuybackItem(i)
							for _, v in pairs(data.lines) do
								if v.type == 20 then
									if v.leftText == ITEM_BIND_ON_EQUIP then
										bType = "BoE"
									elseif v.leftText == ITEM_ACCOUNTBOUND_UNTIL_EQUIP or v.leftText == ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP then
										bType = "WuE"
									elseif v.leftText == ITEM_ACCOUNTBOUND or v.leftText == ITEM_BIND_TO_BNETACCOUNT then
										bType = "WB"
									end
									break
								end
							end
						end
						if bType then
							if not itemButton.ItemBoundType then
								itemButton.ItemBoundType = itemButton:CreateFontString(nil, "OVERLAY")
								itemButton.ItemBoundType:SetFont(addon.variables.defaultFont, 10, "OUTLINE")
								itemButton.ItemBoundType:SetShadowOffset(2, 2)
								itemButton.ItemBoundType:SetShadowColor(0, 0, 0, 1)
							end
							itemButton.ItemBoundType:ClearAllPoints()
							if addon.db["bagIlvlPosition"] == "BOTTOMLEFT" then
								itemButton.ItemBoundType:SetPoint("TOPLEFT", itemButton, "TOPLEFT", 2, -2)
							elseif addon.db["bagIlvlPosition"] == "BOTTOMRIGHT" then
								itemButton.ItemBoundType:SetPoint("TOPRIGHT", itemButton, "TOPRIGHT", -1, -2)
							else
								itemButton.ItemBoundType:SetPoint("BOTTOMLEFT", itemButton, "BOTTOMLEFT", 2, 2)
							end
							itemButton.ItemBoundType:SetFormattedText(bType)
							itemButton.ItemBoundType:Show()
						elseif itemButton.ItemBoundType then
							itemButton.ItemBoundType:Hide()
						end
					else
						if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
						if itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
					end
				end)
			else
				if itemButton.ItemBoundType then itemButton.ItemBoundType:Hide() end
				if itemButton.ItemUpgradeArrow then itemButton.ItemUpgradeArrow:Hide() end
				if itemButton.ItemLevelText then itemButton.ItemLevelText:Hide() end
			end
		end
	end
end

local function updateFlyoutButtonInfo(button)
	if not button then return end

	if CharOpt("ilvl") then
		-- Reset stale overlays on recycled flyout buttons
		if button.ItemUpgradeArrow then button.ItemUpgradeArrow:Hide() end
		if button.ItemUpgradeIcon then button.ItemUpgradeIcon:Hide() end
		local location = button.location
		if not location then return end

		-- TODO 12.0: EquipmentManager_UnpackLocation will change once Void Storage is removed
		local itemLink, _, _, bags, _, slot, bag
		if type(button.location) == "number" then
			_, _, bags, _, slot, bag = EquipmentManager_UnpackLocation(location)

			if bags then
				itemLink = C_Container.GetContainerItemLink(bag, slot)
			elseif not bags then
				itemLink = GetInventoryItemLink("player", slot)
			end
		elseif button.itemLink then
			itemLink = button.itemLink
		end
		if itemLink then
			local eItem = Item:CreateFromItemLink(itemLink)
			if eItem and not eItem:IsItemEmpty() then
				eItem:ContinueOnItemLoad(function()
					local itemLevel = eItem:GetCurrentItemLevel()
					local quality = eItem:GetItemQualityColor()

					if not button.ItemLevelText then
						button.ItemLevelText = button:CreateFontString(nil, "OVERLAY")
						button.ItemLevelText:SetFont(addon.variables.defaultFont, 16, "OUTLINE")
					end
					button.ItemLevelText:ClearAllPoints()
					local pos = addon.db["bagIlvlPosition"] or "TOPRIGHT"
					if pos == "TOPLEFT" then
						button.ItemLevelText:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
					elseif pos == "BOTTOMLEFT" then
						button.ItemLevelText:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
					elseif pos == "BOTTOMRIGHT" then
						button.ItemLevelText:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 2)
					else
						button.ItemLevelText:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
					end

					-- Setze den Text und die Farbe
					button.ItemLevelText:SetText(itemLevel)
					button.ItemLevelText:SetTextColor(quality.r, quality.g, quality.b, 1)
					button.ItemLevelText:Show()

					-- Upgrade icon for Flyout items: compare against the specific slot's equipped item
					if addon.db["showUpgradeArrowOnBagItems"] and itemLink then
						local function getEquipSlotsFor(equipLoc)
							if equipLoc == "INVTYPE_FINGER" then
								return { 11, 12 }
							elseif equipLoc == "INVTYPE_TRINKET" then
								return { 13, 14 }
							elseif equipLoc == "INVTYPE_HEAD" then
								return { 1 }
							elseif equipLoc == "INVTYPE_NECK" then
								return { 2 }
							elseif equipLoc == "INVTYPE_SHOULDER" then
								return { 3 }
							elseif equipLoc == "INVTYPE_CLOAK" then
								return { 15 }
							elseif equipLoc == "INVTYPE_CHEST" or equipLoc == "INVTYPE_ROBE" then
								return { 5 }
							elseif equipLoc == "INVTYPE_WRIST" then
								return { 9 }
							elseif equipLoc == "INVTYPE_HAND" then
								return { 10 }
							elseif equipLoc == "INVTYPE_WAIST" then
								return { 6 }
							elseif equipLoc == "INVTYPE_LEGS" then
								return { 7 }
							elseif equipLoc == "INVTYPE_FEET" then
								return { 8 }
							elseif equipLoc == "INVTYPE_WEAPONMAINHAND" or equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" then
								return { 16 }
							elseif equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_HOLDABLE" or equipLoc == "INVTYPE_SHIELD" then
								return { 17 }
							elseif equipLoc == "INVTYPE_WEAPON" then
								return { 16, 17 }
							end
							return nil
						end

						local invSlot = select(4, C_Item.GetItemInfoInstant(itemLink))
						local slots = getEquipSlotsFor(invSlot)

						-- Determine the specific target slot for this flyout (e.g., 13 or 14 for trinkets)
						local flyoutFrame = _G.EquipmentFlyoutFrame
						local targetSlot = flyoutFrame and flyoutFrame.button and flyoutFrame.button.GetID and flyoutFrame.button:GetID() or nil

						local baseline
						if slots and #slots > 0 then
							local function containsSlot(tbl, val)
								for i = 1, #tbl do
									if tbl[i] == val then return true end
								end
								return false
							end
							if targetSlot and containsSlot(slots, targetSlot) then
								-- Compare only against the item in the specific flyout's slot
								local eqLink = GetInventoryItemLink("player", targetSlot)
								baseline = eqLink and (C_Item.GetDetailedItemLevelInfo(eqLink) or 0) or 0
							else
								-- Fallback: compare against the worst of the valid slots
								for _, s in ipairs(slots) do
									local eqLink = GetInventoryItemLink("player", s)
									local eqIlvl = eqLink and (C_Item.GetDetailedItemLevelInfo(eqLink) or 0) or 0
									if baseline == nil then
										baseline = eqIlvl
									else
										baseline = math.min(baseline, eqIlvl)
									end
								end
							end
						end
						local isUpgrade = baseline ~= nil and itemLevel and itemLevel > baseline
						if isUpgrade then
							if not button.ItemUpgradeIcon then
								button.ItemUpgradeIcon = button:CreateTexture(nil, "OVERLAY")
								button.ItemUpgradeIcon:SetSize(14, 14)
							end
							button.ItemUpgradeIcon:SetTexture("Interface\\AddOns\\EnhanceQoL\\Icons\\upgradeilvl.tga")
							button.ItemUpgradeIcon:ClearAllPoints()
							local posUp = addon.db["bagUpgradeIconPosition"] or "BOTTOMRIGHT"
							if posUp == "TOPRIGHT" then
								button.ItemUpgradeIcon:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -2)
							elseif posUp == "TOPLEFT" then
								button.ItemUpgradeIcon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
							elseif posUp == "BOTTOMLEFT" then
								button.ItemUpgradeIcon:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
							else
								button.ItemUpgradeIcon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 2)
							end
							button.ItemUpgradeIcon:Show()
						elseif button.ItemUpgradeIcon then
							button.ItemUpgradeIcon:Hide()
						end
					end

					local bType
					if bag and slot then
						if addon.db["showBindOnBagItems"] then
							local data = C_TooltipInfo.GetBagItem(bag, slot)
							for i, v in pairs(data.lines) do
								if v.type == 20 then
									if v.leftText == ITEM_BIND_ON_EQUIP then
										bType = "BoE"
									elseif v.leftText == ITEM_ACCOUNTBOUND_UNTIL_EQUIP or v.leftText == ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP then
										bType = "WuE"
									elseif v.leftText == ITEM_ACCOUNTBOUND or v.leftText == ITEM_BIND_TO_BNETACCOUNT then
										bType = "WB"
									end
									break
								end
							end
						end
					end
					if bType then
						if not button.ItemBoundType then
							button.ItemBoundType = button:CreateFontString(nil, "OVERLAY")
							button.ItemBoundType:SetFont(addon.variables.defaultFont, 10, "OUTLINE")
							button.ItemBoundType:SetShadowOffset(2, 2)
							button.ItemBoundType:SetShadowColor(0, 0, 0, 1)
						end
						button.ItemBoundType:ClearAllPoints()
						if addon.db["bagIlvlPosition"] == "BOTTOMLEFT" then
							button.ItemBoundType:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
						elseif addon.db["bagIlvlPosition"] == "BOTTOMRIGHT" then
							button.ItemBoundType:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -2)
						else
							button.ItemBoundType:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
						end
						button.ItemBoundType:SetFormattedText(bType)
						button.ItemBoundType:Show()
					elseif button.ItemBoundType then
						button.ItemBoundType:Hide()
					end
				end)
			end
		elseif button.ItemLevelText then
			if button.ItemBoundType then button.ItemBoundType:Hide() end
			if button.ItemUpgradeArrow then button.ItemUpgradeArrow:Hide() end
			if button.ItemUpgradeIcon then button.ItemUpgradeIcon:Hide() end
			button.ItemLevelText:Hide()
		end
	elseif button.ItemLevelText then
		if button.ItemBoundType then button.ItemBoundType:Hide() end
		if button.ItemUpgradeArrow then button.ItemUpgradeArrow:Hide() end
		if button.ItemUpgradeIcon then button.ItemUpgradeIcon:Hide() end
		button.ItemLevelText:Hide()
	end
end

local function initDungeon()
	addon.functions.InitDBValue("autoChooseDelvePower", false)
	addon.functions.InitDBValue("lfgSortByRio", false)
	addon.functions.InitDBValue("groupfinderSkipRoleSelect", false)
	addon.functions.InitDBValue("enableChatIMRaiderIO", false)

	if LFGListFrame and LFGListFrame.SearchPanel and LFGListFrame.SearchPanel.FilterButton and LFGListFrame.SearchPanel.FilterButton.ResetButton then
		lfgPoint, lfgRelativeTo, lfgRelativePoint, lfgXOfs, lfgYOfs = LFGListFrame.SearchPanel.FilterButton.ResetButton:GetPoint()
	end
	if addon.db["groupfinderMoveResetButton"] then toggleLFGFilterPosition() end

	-- Add Raider.IO URL to LFG applicant member context menu
	if Menu and Menu.ModifyMenu then
		local regionTable = { "US", "KR", "EU", "TW", "CN" }
		local function AddLFGApplicantRIO(owner, root, ctx)
			if not addon.db["enableChatIMRaiderIO"] then return end

			local appID = owner and owner._eqolApplicantID or (ctx and (ctx.applicantID or ctx.appID))
			local memberIdx = owner and owner._eqolMemberIdx or (ctx and (ctx.memberIdx or ctx.memberIndex))
			if not appID or not memberIdx then return end

			local name = C_LFGList and C_LFGList.GetApplicantMemberInfo and C_LFGList.GetApplicantMemberInfo(appID, memberIdx)
			if type(name) ~= "string" or name == "" then return end

			local targetName = name
			if not targetName:find("-", 1, true) then targetName = targetName .. "-" .. (GetRealmName() or ""):gsub("%s", "") end

			local char, realm = targetName:match("^([^%-]+)%-(.+)$")
			if not char or not realm then return end

			local regionKey = regionTable[GetCurrentRegion()] or "EU"
			local realmSlug = string.lower((realm or ""):gsub("%s+", "-"))
			local riolink = "https://raider.io/characters/" .. string.lower(regionKey) .. "/" .. realmSlug .. "/" .. char

			root:CreateDivider()
			root:CreateButton(L["RaiderIOUrl"], function(link)
				if StaticPopup_Show then StaticPopup_Show("EQOL_URL_COPY", nil, nil, link) end
			end, riolink)
		end

		Menu.ModifyMenu("MENU_LFG_FRAME_MEMBER_APPLY", AddLFGApplicantRIO)
	end
end

local function initActionBars()
	addon.functions.InitDBValue("actionBarFullRangeColoring", false)
	addon.functions.InitDBValue("actionBarFullRangeColor", { r = 1, g = 0.1, b = 0.1 })
	addon.functions.InitDBValue("actionBarFullRangeAlpha", 0.35)
	addon.functions.InitDBValue("hideMacroNames", false)
	for _, cbData in ipairs(addon.variables.actionBarNames) do
		if cbData.var and cbData.name then
			if addon.db[cbData.var] then UpdateActionBarMouseover(cbData.name, addon.db[cbData.var], cbData.var) end
		end
	end
	RefreshAllMacroNameVisibility()
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
					if _G["CompactPartyFrame"]:IsShown() and strmatch(type, "party%d") then
						if UnitInParty("player") and not UnitInRaid("player") then setLeaderIcon() end
					end
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

local function initQuest()
	addon.functions.InitDBValue("autoChooseQuest", false)
	addon.functions.InitDBValue("ignoreTrivialQuests", false)
	addon.functions.InitDBValue("ignoreDailyQuests", false)
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
end

local function initMisc()
	addon.functions.InitDBValue("confirmTimerRemovalTrade", false)
	addon.functions.InitDBValue("confirmPatronOrderDialog", false)
	addon.functions.InitDBValue("deleteItemFillDialog", false)
	addon.functions.InitDBValue("confirmReplaceEnchant", false)
	addon.functions.InitDBValue("confirmSocketReplace", false)
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
	addon.functions.InitDBValue("automaticallyOpenContainer", false)
	addon.functions.InitDBValue("containerActionAnchor", { point = "CENTER", relativePoint = "CENTER", x = 0, y = -200 })
	addon.functions.InitDBValue("containerAutoOpenDisabled", {})
	addon.functions.InitDBValue("containerActionAreaBlocks", {})

	-- Hook all static popups, because not the first one has to be the one for sell all junk if another popup is already shown
	for i = 1, 4 do
		local popup = _G["StaticPopup" .. i]
		if popup then
			hooksecurefunc(popup, "Show", function(self)
				if self then
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
	if addon.ChatIM and addon.ChatIM.BuildSoundTable and not addon.ChatIM.availableSounds then addon.ChatIM:BuildSoundTable() end
end

local function initUnitFrame()
	MigrateLegacyVisibilityFlags()
	addon.functions.InitDBValue("hideHitIndicatorPlayer", false)
	addon.functions.InitDBValue("hideHitIndicatorPet", false)
	-- Player resting visuals (ZZZ + glow)
	addon.functions.InitDBValue("hideRestingGlow", false)
	addon.functions.InitDBValue("hideRaidFrameBuffs", false)
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

	local function DisableBlizzBuffs(cuf)
		if addon.db["hideRaidFrameBuffs"] then
			if not cuf.optionTable then return end
			if cuf.optionTable.displayBuffs then
				cuf.optionTable.displayBuffs = false
				CompactUnitFrame_UpdateAuras(cuf) -- entfernt sofort bestehende Buff-Buttons
			end
		end
	end
	hooksecurefunc("CompactUnitFrame_SetUpFrame", DisableBlizzBuffs)

	local function TruncateFrameName(cuf)
		if not addon.db["unitFrameTruncateNames"] then return end
		if not addon.db["unitFrameMaxNameLength"] then return end
		if not cuf then return end

		if cuf.unit and cuf.unit:match("^nameplate") then return end

		local name
		if cuf.unit and UnitExists(cuf.unit) then
			name = UnitName(cuf.unit)
		elseif cuf.displayedUnit and UnitExists(cuf.displayedUnit) then
			name = UnitName(cuf.displayedUnit)
		elseif cuf.name and type(cuf.name.GetText) == "function" then
			name = cuf.name:GetText()
		end

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
	function addon.functions.updateRaidFrameBuffs()
		for i = 1, 5 do
			local f = _G["CompactPartyFrameMember" .. i]
			if f then DisableBlizzBuffs(f) end
		end
		for i = 1, 40 do
			local f = _G["CompactRaidFrame" .. i]
			if f then DisableBlizzBuffs(f) end
		end
	end

	function addon.functions.updatePartyFrameScale()
		if not addon.db["unitFrameScaleEnabled"] then return end
		if not addon.db["unitFrameScale"] then return end
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

	if addon.db["hideRaidFrameBuffs"] then addon.functions.updateRaidFrameBuffs() end
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

local function initChatFrame()
	-- Build learn/unlearn message patterns and filter once
	if not addon.variables.learnUnlearnPatterns then
		local patterns = {}
		if ERR_LEARN_PASSIVE_S then table.insert(patterns, fmtToPattern(ERR_LEARN_PASSIVE_S)) end
		if ERR_LEARN_SPELL_S then table.insert(patterns, fmtToPattern(ERR_LEARN_SPELL_S)) end
		if ERR_LEARN_ABILITY_S then table.insert(patterns, fmtToPattern(ERR_LEARN_ABILITY_S)) end
		if ERR_SPELL_UNLEARNED_S then table.insert(patterns, fmtToPattern(ERR_SPELL_UNLEARNED_S)) end
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
	addon.functions.InitDBValue("chatHideLearnUnlearn", false)
	-- Apply learn/unlearn message filter based on saved setting
	addon.functions.ApplyChatLearnFilter(addon.db["chatHideLearnUnlearn"])

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
	if addon.Ignore and addon.Ignore.SetEnabled then addon.Ignore:SetEnabled(addon.db["enableIgnore"]) end
	if addon.Ignore and addon.Ignore.UpdateAnchor then addon.Ignore:UpdateAnchor() end
end

initLootToast = function()
	if (addon.db.enableLootToastFilter or addon.db.enableLootToastAnchor) and addon.LootToast and addon.LootToast.Enable then
		addon.LootToast:Enable()
	elseif addon.LootToast and addon.LootToast.Disable then
		addon.LootToast:Disable()
	end
end

local function initUI()
	MigrateLegacyVisibilityFlags()
	addon.functions.InitDBValue("enableMinimapButtonBin", false)
	addon.functions.InitDBValue("buttonsink", {})
	addon.functions.InitDBValue("enableLootspecQuickswitch", false)
	addon.functions.InitDBValue("lootspec_quickswitch", {})
	addon.functions.InitDBValue("minimapSinkHoleData", {})
	addon.functions.InitDBValue("hideQuickJoinToast", false)
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

	table.insert(addon.variables.unitFrameNames, {
		name = "MicroMenu",
		var = "unitframeSettingMicroMenu",
		text = addon.L["MicroMenu"],
		allowedVisibility = { "NONE", "MOUSEOVER", "HIDE" },
		children = { MicroMenu:GetChildren() },
		revealAllChilds = true,
	})
	table.insert(addon.variables.unitFrameNames, {
		name = "BagsBar",
		var = "unitframeSettingBagsBar",
		text = addon.L["BagsBar"],
		allowedVisibility = { "NONE", "MOUSEOVER", "HIDE" },
		children = { BagsBar:GetChildren() },
		revealAllChilds = true,
	})

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
		local bar = UIWidgetPowerBarContainerFrame
		if not bar then return end
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

	local COLUMNS = 4
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
			buttonBag:SetBackdrop({
				bgFile = "Interface\\Buttons\\WHITE8x8",
				edgeFile = "Interface\\Buttons\\WHITE8x8",
				edgeSize = 1,
			})

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
			buttonBag:SetBackdropColor(0, 0, 0, 0.4)
			buttonBag:SetBackdropBorderColor(1, 1, 1, 1)
			addon.variables.buttonSink = buttonBag
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
						local col = (index - 1) % COLUMNS
						local row = math.floor((index - 1) / COLUMNS)

						button:SetParent(addon.variables.buttonSink)
						button:SetSize(ICON_SIZE, ICON_SIZE)
						button:SetPoint("TOPLEFT", addon.variables.buttonSink, "TOPLEFT", col * (ICON_SIZE + PADDING) + PADDING, -row * (ICON_SIZE + PADDING) - PADDING)
						button:Show()
					else
						button:Hide()
					end
				end

				local totalRows = math.ceil(index / COLUMNS)
				local width = (ICON_SIZE + PADDING) * COLUMNS + PADDING
				local height = (ICON_SIZE + PADDING) * totalRows + PADDING
				addon.variables.buttonSink:SetSize(width, height)
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
end

function addon.functions.createCatalystFrame()
	if addon.variables.catalystID then
		if addon.general.iconFrame then return end
		local cataclystInfo = C_CurrencyInfo.GetCurrencyInfo(addon.variables.catalystID)
		if cataclystInfo then
			local iconID = cataclystInfo.iconFileID

			addon.general.iconFrame = CreateFrame("Button", nil, PaperDollFrame, "BackdropTemplate")
			addon.general.iconFrame:SetSize(32, 32)
			addon.general.iconFrame:SetPoint("BOTTOMLEFT", PaperDollSidebarTab3, "BOTTOMRIGHT", 4, 0)

			addon.general.iconFrame.icon = addon.general.iconFrame:CreateTexture(nil, "OVERLAY")
			addon.general.iconFrame.icon:SetSize(32, 32)
			addon.general.iconFrame.icon:SetPoint("CENTER", addon.general.iconFrame, "CENTER")
			addon.general.iconFrame.icon:SetTexture(iconID)

			addon.general.iconFrame.count = addon.general.iconFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
			addon.general.iconFrame.count:SetPoint("BOTTOMRIGHT", addon.general.iconFrame, "BOTTOMRIGHT", 1, 2)
			addon.general.iconFrame.count:SetFont(addon.variables.defaultFont, 14, "OUTLINE")
			addon.general.iconFrame.count:SetText(cataclystInfo.quantity)
			addon.general.iconFrame.count:SetTextColor(1, 0.82, 0)
			if addon.db["showCatalystChargesOnCharframe"] == false then addon.general.iconFrame:Hide() end
		end
	end
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

local function initCharacter()
	addon.functions.InitDBValue("showIlvlOnBankFrame", false)
	addon.functions.InitDBValue("showIlvlOnMerchantframe", false)
	addon.functions.InitDBValue("markKnownOnMerchant", false)
	addon.functions.InitDBValue("markCollectedPetsOnMerchant", false)
	addon.functions.InitDBValue("showIlvlOnCharframe", false)
	addon.functions.InitDBValue("showIlvlOnBagItems", false)
	addon.functions.InitDBValue("showBagFilterMenu", false)
	addon.functions.InitDBValue("bagFilterDockFrame", true)
	addon.functions.InitDBValue("showBindOnBagItems", false)
	addon.functions.InitDBValue("showUpgradeArrowOnBagItems", false)
	addon.functions.InitDBValue("bagIlvlPosition", "TOPRIGHT")
	addon.functions.InitDBValue("bagUpgradeIconPosition", "BOTTOMRIGHT")
	addon.functions.InitDBValue("charIlvlPosition", "TOPRIGHT")
	addon.functions.InitDBValue("fadeBagQualityIcons", false)
	addon.functions.InitDBValue("showGemsOnCharframe", false)
	addon.functions.InitDBValue("showGemsTooltipOnCharframe", false)
	addon.functions.InitDBValue("showEnchantOnCharframe", false)
	addon.functions.InitDBValue("showCatalystChargesOnCharframe", false)
	addon.functions.InitDBValue("movementSpeedStatEnabled", false)
	addon.functions.InitDBValue("showCloakUpgradeButton", false)
	addon.functions.InitDBValue("bagFilterFrameData", {})
	addon.functions.InitDBValue("closeBagsOnAuctionHouse", false)

	hooksecurefunc(ContainerFrameCombinedBags, "UpdateItems", addon.functions.updateBags)
	for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
		hooksecurefunc(frame, "UpdateItems", addon.functions.updateBags)
	end

	hooksecurefunc("MerchantFrame_UpdateMerchantInfo", updateMerchantButtonInfo)
	hooksecurefunc("MerchantFrame_UpdateBuybackInfo", updateBuybackButtonInfo)

	local function RefreshAllFlyoutButtons()
		local f = _G.EquipmentFlyoutFrame
		if not f then return end
		-- Blizzard pflegt eine buttons-Liste, darauf verlassen wir uns:
		if f.buttons then
			for _, btn in ipairs(f.buttons) do
				if btn and btn:IsShown() then
					updateFlyoutButtonInfo(btn) -- <- deine vorhandene Routine
				end
			end
			return
		end
		-- Fallback (falls mal keine Liste existiert): Children scannen
		for i = 1, (f:GetNumChildren() or 0) do
			local child = select(i, f:GetChildren())
			if child and child:IsShown() and child.icon then updateFlyoutButtonInfo(child) end
		end
	end
	hooksecurefunc("EquipmentFlyout_UpdateItems", RefreshAllFlyoutButtons)

	if _G.BankPanel then
		hooksecurefunc(BankPanel, "GenerateItemSlotsForSelectedTab", addon.functions.updateBags)
		hooksecurefunc(BankPanel, "RefreshAllItemsForSelectedTab", addon.functions.updateBags)
		hooksecurefunc(BankPanel, "UpdateSearchResults", addon.functions.updateBags)
	end

	-- Add Cataclyst charges in char frame
	addon.functions.createCatalystFrame()
	if addon.MovementSpeedStat and addon.MovementSpeedStat.Refresh then addon.MovementSpeedStat.Refresh() end
	-- add durability icon on charframe

	addon.general.durabilityIconFrame = CreateFrame("Button", nil, PaperDollFrame, "BackdropTemplate")
	addon.general.durabilityIconFrame:SetSize(32, 32)
	addon.general.durabilityIconFrame:SetPoint("TOPLEFT", CharacterFramePortrait, "RIGHT", 4, 0)

	addon.general.durabilityIconFrame.icon = addon.general.durabilityIconFrame:CreateTexture(nil, "OVERLAY")
	addon.general.durabilityIconFrame.icon:SetSize(32, 32)
	addon.general.durabilityIconFrame.icon:SetPoint("CENTER", addon.general.durabilityIconFrame, "CENTER")
	addon.general.durabilityIconFrame.icon:SetTexture(addon.variables.durabilityIcon)

	addon.general.durabilityIconFrame.count = addon.general.durabilityIconFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	addon.general.durabilityIconFrame.count:SetPoint("BOTTOMRIGHT", addon.general.durabilityIconFrame, "BOTTOMRIGHT", 1, 2)
	addon.general.durabilityIconFrame.count:SetFont(addon.variables.defaultFont, 12, "OUTLINE")

	if addon.db["showDurabilityOnCharframe"] == false or (addon.functions and addon.functions.IsTimerunner and addon.functions.IsTimerunner()) then addon.general.durabilityIconFrame:Hide() end

	addon.general.cloakUpgradeFrame = CreateFrame("Button", nil, PaperDollFrame, "BackdropTemplate")
	addon.general.cloakUpgradeFrame:SetSize(32, 32)
	addon.general.cloakUpgradeFrame:SetPoint("LEFT", addon.general.durabilityIconFrame, "RIGHT", 4, 0)

	addon.general.cloakUpgradeFrame.icon = addon.general.cloakUpgradeFrame:CreateTexture(nil, "OVERLAY")
	addon.general.cloakUpgradeFrame.icon:SetSize(32, 32)
	addon.general.cloakUpgradeFrame.icon:SetPoint("CENTER", addon.general.cloakUpgradeFrame, "CENTER")
	addon.general.cloakUpgradeFrame.icon:SetTexture(addon.variables.cloakUpgradeIcon)

	addon.general.cloakUpgradeFrame:SetScript("OnClick", function()
		GenericTraitUI_LoadUI()
		GenericTraitFrame:SetSystemID(29)
		GenericTraitFrame:SetTreeID(1115)
		ToggleFrame(GenericTraitFrame)
	end)
	addon.general.cloakUpgradeFrame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["cloakUpgradeTooltip"] or "Upgrade skills")
		GameTooltip:Show()
	end)
	addon.general.cloakUpgradeFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local function updateCloakUpgradeButton()
		if PaperDollFrame and PaperDollFrame:IsShown() then
			if addon.db["showCloakUpgradeButton"] and C_Item.IsEquippedItem(235499) then
				addon.general.cloakUpgradeFrame:Show()
			else
				addon.general.cloakUpgradeFrame:Hide()
			end
		end
	end
	addon.functions.updateCloakUpgradeButton = updateCloakUpgradeButton
	local cloakEventFrame = CreateFrame("Frame")
	cloakEventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	cloakEventFrame:SetScript("OnEvent", updateCloakUpgradeButton)
	cloakEventFrame:Hide()

	for key, value in pairs(addon.variables.itemSlots) do
		-- Hintergrund für das Item-Level
		value.ilvlBackground = value:CreateTexture(nil, "BACKGROUND")
		value.ilvlBackground:SetColorTexture(0, 0, 0, 0.8) -- Schwarzer Hintergrund mit 80% Transparenz
		value.ilvlBackground:SetPoint("TOPRIGHT", value, "TOPRIGHT", 1, 1)
		value.ilvlBackground:SetSize(30, 16) -- Größe des Hintergrunds (muss ggf. angepasst werden)

		-- Roter Rahmen mit Farbverlauf
		if addon.variables.shouldEnchanted[key] or addon.variables.shouldEnchantedChecks[key] then
			value.borderGradient = value:CreateTexture(nil, "ARTWORK")
			value.borderGradient:SetPoint("TOPLEFT", value, "TOPLEFT", -2, 2)
			value.borderGradient:SetPoint("BOTTOMRIGHT", value, "BOTTOMRIGHT", 2, -2)
			value.borderGradient:SetColorTexture(1, 0, 0, 0.6) -- Grundfarbe Rot
			value.borderGradient:SetGradient("VERTICAL", CreateColor(1, 0, 0, 1), CreateColor(1, 0.3, 0.3, 0.5))
			value.borderGradient:Hide()
		end
		-- Text für das Item-Level
		value.ilvl = value:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		value.ilvl:SetPoint("TOPRIGHT", value.ilvlBackground, "TOPRIGHT", -1, -2) -- Position des Textes im Zentrum des Hintergrunds
		value.ilvl:SetFont(addon.variables.defaultFont, 14, "OUTLINE") -- Setzt die Schriftart, -größe und -stil (OUTLINE)

		value.enchant = value:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		if addon.variables.itemSlotSide[key] == 0 then
			value.enchant:SetPoint("BOTTOMLEFT", value, "BOTTOMRIGHT", 2, 1)
		elseif addon.variables.itemSlotSide[key] == 2 then
			value.enchant:SetPoint("BOTTOMLEFT", value, "BOTTOMRIGHT", 2, 1)
		else
			value.enchant:SetPoint("BOTTOMRIGHT", value, "BOTTOMLEFT", -2, 1)
		end
		value.enchant:SetFont(addon.variables.defaultFont, 12, "OUTLINE")

		value.gems = {}
		for i = 1, 3 do
			value.gems[i] = CreateFrame("Frame", nil, PaperDollFrame)
			value.gems[i]:SetSize(16, 16) -- Setze die Größe des Icons

			if addon.variables.itemSlotSide[key] == 0 then
				value.gems[i]:SetPoint("TOPLEFT", value, "TOPRIGHT", 5 + (i - 1) * 16, -1) -- Verschiebe jedes Icon um 20px
			elseif addon.variables.itemSlotSide[key] == 1 then
				value.gems[i]:SetPoint("TOPRIGHT", value, "TOPLEFT", -5 - (i - 1) * 16, -1)
			else
				value.gems[i]:SetPoint("BOTTOM", value, "TOPLEFT", -1, 5 + (i - 1) * 16)
			end

			value.gems[i]:SetFrameStrata("HIGH")

			value.gems[i]:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

			value.gems[i].icon = value.gems[i]:CreateTexture(nil, "OVERLAY")
			value.gems[i].icon:SetAllPoints(value.gems[i])
			value.gems[i].icon:SetTexture("Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic") -- Setze die erhaltene Textur

			value.gems[i]:Hide()
		end
	end

	PaperDollFrame:HookScript("OnShow", function(self)
		setCharFrame()
		addon.functions.updateCloakUpgradeButton()
	end)

	if OrderHallCommandBar then
		OrderHallCommandBar:HookScript("OnShow", function(self)
			if addon.db["hideOrderHallBar"] then
				self:Hide()
			else
				self:Show()
			end
		end)
		if addon.db["hideOrderHallBar"] then OrderHallCommandBar:Hide() end
	end
end

-- Frame-Position wiederherstellen
local function RestorePosition(frame)
	if addon.db.point and addon.db.x and addon.db.y then
		frame:ClearAllPoints()
		frame:SetPoint(addon.db.point, UIParent, addon.db.point, addon.db.x, addon.db.y)
	end
end

function addon.functions.checkReloadFrame()
	if addon.variables.requireReload == false then return end
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
			{ value = "actionbar", text = ACTIONBARS_LABEL },
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

	-- Conditionally add "Container Actions" under Items if it exists
	if hasMiscOption("automaticallyOpenContainer") then
		addon.functions.addToTree("items", { value = "container", text = L["ContainerActions"] }, true)
		addon.treeGroup:SetTree(addon.treeGroupData)
	end

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
		-- Items & Inventory
		if group == "items" then
			addBagFrame(container)
		elseif group == "items\001loot" then
			addLootFrame(container, true)
		elseif group == "items\001container" then
			addContainerActionsFrame(container)
		-- Gear & Upgrades
		elseif group == "items\001gear" then
			addCharacterFrame(container)
		-- Vendors & Economy
		elseif group == "items\001economy" then
			addVendorMainFrame2(container)
		elseif string.sub(group, 1, string.len("items\001economy\001selling")) == "items\001economy\001selling" then
			-- Forward Selling (Auto-Sell) pages to Vendor UI
			addon.Vendor.functions.treeCallback(container, group)
			-- CraftShopper is integrated into the Selling root; no standalone panel
			-- Combat & Dungeons
		elseif group == "combat" then
			addDungeonFrame(container)
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
		elseif group == "ui" then
			addUIFrame(container)
		elseif group == "ui\001actionbar" then
			addActionBarFrame(container)
		elseif group == "ui\001chatframe" then
			addChatFrame(container)
		elseif group == "ui\001unitframe" then
			addUnitFrame2(container)
		elseif group == "ui\001datapanel" then
			buildDatapanelFrame(container)
		elseif group == "ui\001mouse" then
			addon.Mouse.functions.treeCallback(container, "mouse")
		elseif group == "ui\001tooltip" then
			addon.Tooltip.functions.treeCallback(container, group:sub(4)) -- pass "tooltip..."
		-- Quests under Map & Navigation
		elseif group == "nav\001quest" then
			addQuestFrame(container, true)
		-- Social under UI
		elseif group == "ui\001social" then
			addSocialFrame(container)
		-- System
		elseif group == "ui\001system" then
			addCVarFrame(container, true)
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
	addon.treeGroup:SelectByPath("items")

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
	initDungeon()
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
			if addon.Aura and addon.Aura.ResourceBars and addon.Aura.ResourceBars.MarkTextureListDirty then
				addon.Aura.ResourceBars.MarkTextureListDirty()
			end
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
	local category, layout = Settings.RegisterCanvasLayoutCategory(configFrame, configFrame.name)
	Settings.RegisterAddOnCategory(category)
	addon.settingsCategory = category
end

-- Erstelle ein Frame f��r Events
local frameLoad = CreateFrame("Frame")

local gossipClicked = {}

local wOpen = false -- Variable to ignore multiple checks for openItems
local function openItems(items)
	local function openNextItem()
		if #items == 0 then
			addon.functions.checkForContainer()
			return
		end

		if not MerchantFrame:IsShown() then
			local item = table.remove(items, 1)
			local iLoc = ItemLocation:CreateFromBagAndSlot(item.bag, item.slot)
			-- if iLoc then
			-- 	if C_Item.IsLocked(iLoc) then C_Item.UnlockItem(iLoc) end
			-- end
			C_Timer.After(0.15, function()
				C_Container.UseContainerItem(item.bag, item.slot)
				C_Timer.After(0.4, openNextItem) -- 400ms Pause zwischen den boxen
			end)
		end
	end
	openNextItem()
end

function addon.functions.checkForContainer(bags)
	if not addon.db["automaticallyOpenContainer"] then
		if addon.ContainerActions and addon.ContainerActions.UpdateItems then addon.ContainerActions:UpdateItems({}) end
		wOpen = false
		return
	end

	local safeItems, secureItems = {}, {}
	if addon.ContainerActions and addon.ContainerActions.ScanBags then
		safeItems, secureItems = addon.ContainerActions:ScanBags(bags)
	end

	if addon.ContainerActions and addon.ContainerActions.UpdateItems then addon.ContainerActions:UpdateItems(secureItems) end

	if #safeItems > 0 then
		openItems(safeItems)
	else
		wOpen = false
	end
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
			loadSubAddon("EnhanceQoLCombatMeter")
			loadSubAddon("EnhanceQoLDrinkMacro")
			loadSubAddon("EnhanceQoLTooltip")
			loadSubAddon("EnhanceQoLVendor")

			if addon.ContainerActions and addon.ContainerActions.Init then
				addon.ContainerActions:Init()
				if addon.ContainerActions.OnSettingChanged then addon.ContainerActions:OnSettingChanged(addon.db["automaticallyOpenContainer"]) end
			end

			if addon.Events and addon.Events.LegionRemix and addon.Events.LegionRemix.Init then addon.Events.LegionRemix:Init() end

			checkBagIgnoreJunk()
		end
		if arg1 == "Blizzard_ItemInteractionUI" then addon.functions.toggleInstantCatalystButton(addon.db["instantCatalystEnabled"]) end
	end,
	["BAG_UPDATE"] = function(bag)
		addon._bagsDirty = addon._bagsDirty or {}
		if type(bag) == "number" then addon._bagsDirty[bag] = true end
	end,
	["BAG_UPDATE_DELAYED"] = function()
		if addon.functions.clearTooltipCache then
			local now = GetTime()
			if not addon._ttCacheLastClear or (now - addon._ttCacheLastClear) > 0.25 then
				addon._ttCacheLastClear = now
				addon.functions.clearTooltipCache()
			end
		end

		if not addon.db["automaticallyOpenContainer"] then return end
		if wOpen or addon._bagScanScheduled then return end

		addon._bagScanScheduled = true
		C_Timer.After(0, function()
			addon._bagScanScheduled = nil
			if wOpen or not addon.db["automaticallyOpenContainer"] then return end

			wOpen = true

			local bags
			if addon._bagsDirty and next(addon._bagsDirty) then
				bags = {}
				for b in pairs(addon._bagsDirty) do
					if type(b) == "number" then table.insert(bags, b) end
				end
				addon._bagsDirty = nil
			end

			addon.functions.checkForContainer(bags)
		end)
	end,
	["CURRENCY_DISPLAY_UPDATE"] = function(arg1)
		if arg1 == addon.variables.catalystID and addon.variables.catalystID then
			local cataclystInfo = C_CurrencyInfo.GetCurrencyInfo(addon.variables.catalystID)
			addon.general.iconFrame.count:SetText(cataclystInfo.quantity)
		end
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
	["ENCHANT_SPELL_COMPLETED"] = function(arg1, arg2)
		if PaperDollFrame:IsShown() and CharOpt("enchants") and arg1 == true and arg2 and arg2.equipmentSlotIndex then
			C_Timer.After(1, function() setIlvlText(addon.variables.itemSlots[arg2.equipmentSlotIndex], arg2.equipmentSlotIndex) end)
		end
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
	["GUILDBANK_UPDATE_MONEY"] = function()
		if addon.db["showDurabilityOnCharframe"] then calculateDurability() end
	end,

	["LFG_ROLE_CHECK_SHOW"] = function()
		if addon.db["groupfinderSkipRoleSelect"] and UnitInParty("player") then skipRolecheck() end
	end,
	["LFG_LIST_APPLICANT_UPDATED"] = function()
		if PVEFrame:IsShown() and addon.db["lfgSortByRio"] then C_LFGList.RefreshApplicants() end
		if InCombatLockdown() then return end
		if addon.db["groupfinderAppText"] then toggleGroupApplication(true) end
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
	["INSPECT_READY"] = function(arg1)
		if AnyInspectEnabled() then onInspect(arg1) end
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
	["PLAYERBANKSLOTS_CHANGED"] = function(arg1)
		if not addon.db["showIlvlOnBankFrame"] then return end
		local itemButton = _G["BankFrameItem" .. arg1]
		if itemButton then addon.functions.updateBank(itemButton, -1, arg1) end
	end,
	["PLAYER_CHOICE_UPDATE"] = function()
		if select(3, GetInstanceInfo()) == 208 and addon.db["autoChooseDelvePower"] then
			local choiceInfo = C_PlayerChoice.GetCurrentPlayerChoiceInfo()
			if choiceInfo and choiceInfo.options and #choiceInfo.options == 1 then
				C_PlayerChoice.SendPlayerChoiceResponse(choiceInfo.options[1].buttons[1].id)
				if PlayerChoiceFrame:IsShown() then PlayerChoiceFrame:Hide() end
			end
		end
	end,
	["PLAYER_DEAD"] = function()
		if addon.db["showDurabilityOnCharframe"] then calculateDurability() end
	end,
	["PLAYER_EQUIPMENT_CHANGED"] = function(arg1)
		if addon.variables.itemSlots[arg1] and PaperDollFrame:IsShown() then
			if ItemInteractionFrame and ItemInteractionFrame:IsShown() then
				C_Timer.After(0.4, function() setIlvlText(addon.variables.itemSlots[arg1], arg1) end)
			else
				setIlvlText(addon.variables.itemSlots[arg1], arg1)
			end
		end
		if addon.db["showDurabilityOnCharframe"] then calculateDurability() end
	end,
	["PLAYER_INTERACTION_MANAGER_FRAME_SHOW"] = function(arg1)
		if arg1 == 53 and addon.db["openCharframeOnUpgrade"] then
			if CharacterFrame:IsShown() == false then ToggleCharacter("PaperDollFrame") end
		end
	end,
	["PLAYER_LOGIN"] = function()
		if addon.db["enableMinimapButtonBin"] then addon.functions.toggleButtonSink() end
		addon.variables.unitSpec = C_SpecializationInfo.GetSpecialization()
		if addon.variables.unitSpec then
			local specId, specName = C_SpecializationInfo.GetSpecializationInfo(addon.variables.unitSpec)
			addon.variables.unitSpecName = specName
			addon.variables.unitRole = GetSpecializationRole(addon.variables.unitSpec)
			addon.variables.unitSpecId = specId
		end

		addon.db["moneyTracker"][UnitGUID("player")] = {
			name = UnitName("player"),
			realm = GetRealmName(),
			money = GetMoney(),
			class = select(2, UnitClass("player")),
		}
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
		if addon.db["showDurabilityOnCharframe"] then calculateDurability() end
		if addon.db["moneyTracker"][UnitGUID("player")]["money"] then addon.db["moneyTracker"][UnitGUID("player")]["money"] = GetMoney() end
	end,
	["ACCOUNT_MONEY"] = function() addon.db["warbandGold"] = C_Bank.FetchDepositedMoney(Enum.BankType.Account) end,
	["PLAYER_REGEN_ENABLED"] = function()
		if addon.db["showDurabilityOnCharframe"] then calculateDurability() end
	end,
	["PLAYER_UNGHOST"] = function()
		if addon.db["showDurabilityOnCharframe"] then calculateDurability() end
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
	["SOCKET_INFO_UPDATE"] = function()
		if PaperDollFrame:IsShown() and CharOpt("gems") then C_Timer.After(0.5, function() setCharFrame() end) end
	end,
	["ZONE_CHANGED_NEW_AREA"] = function()
		if addon.variables.hookedOrderHall == false then
			local ohcb = OrderHallCommandBar
			if ohcb then
				ohcb:HookScript("OnShow", function(self)
					if addon.db["hideOrderHallBar"] then
						self:Hide()
					else
						self:Show()
					end
				end)
				addon.variables.hookedOrderHall = true
				if addon.db["hideOrderHallBar"] then OrderHallCommandBar:Hide() end
			end
		end
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
