local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end
local LSM = LibStub("LibSharedMedia-3.0")

--! EQOL Whisper Sink: All related changes are marked with this tag
--! EQOL Whisper Sink: to allow easy removal once Blizzard fixes the bug.
--! EQOL Whisper Sink: see docs/KnownIssues_Blizzard.md for context and revert steps.
local ChatIM = addon.ChatIM or {}
addon.ChatIM = ChatIM
ChatIM.enabled = false
ChatIM.whisperHooked = ChatIM.whisperHooked or false
ChatIM.soundPath = "Interface\\AddOns\\" .. parentAddonName .. "\\Sounds\\ChatIM\\"
--! EQOL Whisper Sink: state for hidden sink + original groups
ChatIM._originalGroups = ChatIM._originalGroups or nil
ChatIM._sinkFrame = ChatIM._sinkFrame or nil
ChatIM._sinkActive = ChatIM._sinkActive or false

function ChatIM:BuildSoundTable()
	local result = {}

	for name, path in pairs(LSM:HashTable("sound")) do
		result[name] = path
	end
	ChatIM.availableSounds = result
end

local function shouldPlaySound(sender)
	if not ChatIM.widget or not ChatIM.widget.frame:IsShown() then return true end
	if ChatIM.activeTab ~= sender then return true end
	local tab = ChatIM.tabs[sender]
	if not tab or not tab.edit or not tab.edit:HasFocus() then return true end
	return false
end

local function playIncomingSound(sender)
	if not shouldPlaySound(sender) then return end
	if addon.db and addon.db["chatIMUseCustomSound"] then
		local key = addon.db["chatIMCustomSoundFile"]
		local file = key and ChatIM.availableSounds[key]
		if file then
			PlaySoundFile(file, "Master")
			return
		end
	end
	PlaySound(SOUNDKIT.TELL_MESSAGE)
end

local function whisperFilter() return true end

local function focusTab(target)
	ChatIM:CreateTab(target)
	if ChatIM.widget and ChatIM.widget.frame and not ChatIM.widget.frame:IsShown() then
		UIFrameFlashStop(ChatIM.widget.frame)
		ChatIM:ShowWindow()
	end
	local tab = ChatIM.tabs[target]
	if tab and tab.edit then
		ChatIM.tabGroup:SelectTab(target)
		tab.edit:SetFocus()
	end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
	if not ChatIM.enabled then return end
	if event == "PLAYER_REGEN_DISABLED" then
		ChatIM.inCombat = true
		if addon.db and addon.db["chatIMHideInCombat"] then
			if ChatIM.widget and ChatIM.widget.frame:IsShown() then
				ChatIM.wasOpenBeforeCombat = true
				ChatIM:HideWindow()
			else
				ChatIM.wasOpenBeforeCombat = false
			end
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		ChatIM.inCombat = false
		if addon.db and addon.db["chatIMHideInCombat"] then
			if (ChatIM.wasOpenBeforeCombat or ChatIM.pendingShow) and ChatIM.widget then ChatIM:ShowWindow() end
			for _, snd in ipairs(ChatIM.soundQueue or {}) do
				playIncomingSound(snd)
			end
			ChatIM.pendingShow = false
			ChatIM.soundQueue = {}
		end
	elseif event == "CHAT_MSG_WHISPER" then
		local msg, sender = ...
		if addon.Ignore and addon.Ignore.CheckIgnore and addon.Ignore:CheckIgnore(sender) then return end
		ChatIM:AddMessage(sender, msg)
		if addon.db and addon.db["chatIMHideInCombat"] and ChatIM.inCombat then
			table.insert(ChatIM.soundQueue, sender)
			ChatIM.pendingShow = true
		else
			playIncomingSound(sender)
			ChatIM:Flash()
		end
	elseif event == "CHAT_MSG_BN_WHISPER" then
		local msg, sender, _, _, _, _, _, _, _, _, _, _, bnetID = ...
		ChatIM:AddMessage(sender, msg, nil, true, bnetID)
		if addon.db and addon.db["chatIMHideInCombat"] and ChatIM.inCombat then
			table.insert(ChatIM.soundQueue, sender)
			ChatIM.pendingShow = true
		else
			playIncomingSound(sender)
			ChatIM:Flash()
		end
	elseif event == "CHAT_MSG_WHISPER_INFORM" then
		local msg, target = ...
		ChatIM:AddMessage(target, msg, true)
		focusTab(target)
	elseif event == "CHAT_MSG_BN_WHISPER_INFORM" then
		local msg, target, _, _, _, _, _, _, _, _, _, _, bnetID = ...
		ChatIM:AddMessage(target, msg, true, true, bnetID)
		focusTab(target)
	elseif event == "PLAYER_LOGIN" or event == "UPDATE_CHAT_WINDOWS" then
		--! EQOL Whisper Sink: initialize or recover after chat frame reset
		if ChatIM.enabled and not ChatIM._sinkActive then ChatIM:TrySetupWhisperSink() end
	elseif event == "PLAYER_LOGOUT" then
		-- Restore any moved message groups on logout to avoid persisting state
		ChatIM:RestoreWhisperGroups()
	end
end)

local function updateRegistration()
	if ChatIM.enabled then
		frame:RegisterEvent("CHAT_MSG_WHISPER")
		frame:RegisterEvent("CHAT_MSG_BN_WHISPER")
		frame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
		frame:RegisterEvent("CHAT_MSG_BN_WHISPER_INFORM")
		frame:RegisterEvent("PLAYER_LOGIN")
		--! EQOL Whisper Sink: re-init on login and when chat windows reset
		frame:RegisterEvent("UPDATE_CHAT_WINDOWS")
		if addon.db and addon.db["chatIMHideInCombat"] then
			frame:RegisterEvent("PLAYER_REGEN_DISABLED")
			frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		else
			frame:UnregisterEvent("PLAYER_REGEN_DISABLED")
			frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
		end

		-- Ensure we restore groups on logout
		frame:RegisterEvent("PLAYER_LOGOUT")

		--! EQOL Whisper Sink: using message group routing instead of global filters

		EnhanceQoL_IMHistory = EnhanceQoL_IMHistory or {}
		ChatIM.history = EnhanceQoL_IMHistory

		ChatIM:BuildSoundTable()
	else
		frame:UnregisterAllEvents()
		if ChatIM.widget and ChatIM.widget.frame then ChatIM:HideWindow() end
	end
end

--! EQOL Whisper Sink: move whisper message groups to a hidden frame (no INFORM variants)
--! EQOL Whisper Sink BEGIN
local SINK_GROUPS = { "WHISPER", "BN_WHISPER" }

local function containsGroup(chatFrame, group)
	if type(ChatFrame_ContainsMessageGroup) == "function" then return ChatFrame_ContainsMessageGroup(chatFrame, group) end
	-- Fallback: not strictly accurate, assume true to be conservative
	return true
end

--! EQOL Whisper Sink: create sink window and rewire message groups
function ChatIM:SetupWhisperSink()
	if self._sinkActive then return end

	--! EQOL Whisper Sink: ensure a hidden chat frame exists as sink
	local sink = self._sinkFrame
	if not sink then
		--! EQOL Whisper Sink: create a new floating chat window; we'll hide and undock it
		sink = FCF_OpenNewWindow("EQOL_WhisperSink")
		if not sink then return end
		sink:SetMovable(false)
		sink:EnableMouse(false)
		FCF_UnDockFrame(sink)
		sink:Hide()
		sink:SetClampedToScreen(false)
		sink:ClearAllPoints()
		sink:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 0)
		sink:SetUserPlaced(false)
		self._sinkFrame = sink
	end

	--! EQOL Whisper Sink: make sure sink doesn't receive any other messages
	if type(ChatFrame_RemoveAllMessageGroups) == "function" then ChatFrame_RemoveAllMessageGroups(sink) end

	--! EQOL Whisper Sink: collect current frames and record which groups they have, then move them
	self._originalGroups = {}
	for i = 1, (NUM_CHAT_WINDOWS or 0) do
		local f = _G["ChatFrame" .. i]
		if f and f ~= self._sinkFrame then
			for _, g in ipairs(SINK_GROUPS) do
				if containsGroup(f, g) then
					self._originalGroups[f] = self._originalGroups[f] or {}
					self._originalGroups[f][g] = true
					ChatFrame_RemoveMessageGroup(f, g)
				end
			end
		end
	end

	for _, g in ipairs(SINK_GROUPS) do
		ChatFrame_AddMessageGroup(sink, g)
	end

	self._sinkActive = true
end

--! EQOL Whisper Sink: wait for chat system to be fully ready
local function chatFramesReady()
	local cf1 = _G.ChatFrame1
	return type(FCF_OpenNewWindow) == "function" and cf1 and cf1.selectedColorTable and cf1.messageTypeList
end

--! EQOL Whisper Sink: safe entry with retry/timer
function ChatIM:TrySetupWhisperSink()
	if self._sinkActive then return end
	if not chatFramesReady() then
		if not self._sinkRetryScheduled and C_Timer and C_Timer.After then
			self._sinkRetryScheduled = true
			C_Timer.After(1.5, function()
				self._sinkRetryScheduled = false
				if ChatIM.enabled and not ChatIM._sinkActive then ChatIM:TrySetupWhisperSink() end
			end)
		end
		return
	end
	self:SetupWhisperSink()
end

function ChatIM:RestoreWhisperGroups()
	-- Move groups back to their original frames and close the sink
	local sink = self._sinkFrame
	if sink then
		for _, g in ipairs(SINK_GROUPS) do
			ChatFrame_RemoveMessageGroup(sink, g)
		end
		if type(FCF_Close) == "function" then pcall(FCF_Close, sink) end
		self._sinkFrame = nil
	end

	if self._originalGroups then
		for f, groups in pairs(self._originalGroups) do
			for g, had in pairs(groups) do
				if had then ChatFrame_AddMessageGroup(f, g) end
			end
		end
	end
	self._originalGroups = nil
	self._sinkActive = false
end

--! EQOL Whisper Sink END

function ChatIM:SetEnabled(val)
	self.enabled = val and true or false
	if self.enabled then
		self:SetMaxHistoryLines(addon.db and addon.db["chatIMMaxHistory"])
		self:CreateUI()
		--! EQOL Whisper Sink: deferred init on enable
		self:TrySetupWhisperSink()
		if not self.whisperHooked then
			hooksecurefunc("ChatFrame_SendTell", function(name)
				if not ChatIM.enabled then return end
				if name then
					if nil == name:match("-") then
						-- no minus means same realm so get my realm and add it
						name = name .. "-" .. (GetRealmName()):gsub("%s", "")
					end
					ChatIM:StartWhisper(name)
				end
			end)
			hooksecurefunc("ChatFrame_SendBNetTell", function(target)
				if not ChatIM.enabled then return end
				local bnetID = nil
				local plain = BNTokenFindName(target) or target
				bnetID = BNet_GetBNetIDAccount(plain)
				target = plain
				if bnetID then
					local accountTag
					local info = C_BattleNet.GetAccountInfoByID(bnetID)
					if info then accountTag = info.battleTag end
					if accountTag then ChatIM:StartWhisper(target, bnetID, accountTag) end
				end
			end)
			self.whisperHooked = true
		end
	else
		--! EQOL Whisper Sink: disabling → restore chat groups and close sink
		self:RestoreWhisperGroups()
	end
	updateRegistration()
end
SLASH_EQOLIM1 = "/eim"
SlashCmdList["EQOLIM"] = function()
	if ChatIM.enabled then ChatIM:Toggle() end
end

function ChatIM:ToggleIgnore(name)
	if C_FriendList.IsIgnored and C_FriendList.IsIgnored(name) or IsIgnored and IsIgnored(name) then
		if C_FriendList.DelIgnore then
			C_FriendList.DelIgnore(name)
		else
			DelIgnore(name)
		end
	else
		if C_FriendList.AddIgnore then
			C_FriendList.AddIgnore(name)
		else
			AddIgnore(name)
		end
	end
end
