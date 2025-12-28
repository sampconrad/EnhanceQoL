-- luacheck: globals CommunitiesFrame CommunitiesFrameMixin COMMUNITIES_FRAME_DISPLAY_MODES
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local CommunityChatPrivacy = addon.CommunityChatPrivacy or {}
addon.CommunityChatPrivacy = CommunityChatPrivacy
local L = addon.L or {}

CommunityChatPrivacy.enabled = CommunityChatPrivacy.enabled or false
CommunityChatPrivacy.sessionAllowed = CommunityChatPrivacy.sessionAllowed or false
CommunityChatPrivacy.loaded = CommunityChatPrivacy.loaded or false
CommunityChatPrivacy.hooksInstalled = CommunityChatPrivacy.hooksInstalled or false

local MODE_ALWAYS = 1
local MODE_SESSION = 2

local LFG_EYE_TEXTURE = [[Interface\LFGFrame\LFG-Eye]]
local LFG_EYE_FRAME_OPEN = 0
local LFG_EYE_FRAME_CLOSED = 4
local LFG_EYE_FRAME_WIDTH = 64
local LFG_EYE_FRAME_HEIGHT = 64
local LFG_EYE_TEXTURE_WIDTH = 512
local LFG_EYE_TEXTURE_HEIGHT = 256

local function setEyeFrame(tex, frameIndex)
	if not tex or not frameIndex then return end
	local cols = LFG_EYE_TEXTURE_WIDTH / LFG_EYE_FRAME_WIDTH
	local col = frameIndex % cols
	local row = math.floor(frameIndex / cols)

	local left = (col * LFG_EYE_FRAME_WIDTH) / LFG_EYE_TEXTURE_WIDTH
	local right = ((col + 1) * LFG_EYE_FRAME_WIDTH) / LFG_EYE_TEXTURE_WIDTH
	local top = (row * LFG_EYE_FRAME_HEIGHT) / LFG_EYE_TEXTURE_HEIGHT
	local bottom = ((row + 1) * LFG_EYE_FRAME_HEIGHT) / LFG_EYE_TEXTURE_HEIGHT

	tex:SetTexCoord(left, right, top, bottom)
end

local function updateEyeButton(eyeButton, hidden)
	if not eyeButton then return end
	local tex = eyeButton:GetNormalTexture()
	if tex then
		tex:SetTexture(LFG_EYE_TEXTURE)
		setEyeFrame(tex, hidden and LFG_EYE_FRAME_CLOSED or LFG_EYE_FRAME_OPEN)
		tex:SetDesaturated(false)
	end
end

local function isCommunitiesLoaded()
	if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded("Blizzard_Communities") end
	return false
end

function CommunityChatPrivacy:IsAlwaysMode()
	if addon.db and addon.db.communityChatPrivacyMode then return addon.db.communityChatPrivacyMode == MODE_ALWAYS end
	return true
end

function CommunityChatPrivacy:IsHidden() return self.enabled and not self.sessionAllowed end

function CommunityChatPrivacy:PositionToggleButton()
	local button = self.eyeButton
	if not button or not CommunitiesFrame then return end

	local anchor = CommunitiesFrame.MaximizeMinimizeFrame
	if not anchor then
		button:Hide()
		return
	end

	button:ClearAllPoints()
	button:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
	local size = ((anchor.GetHeight and anchor:GetHeight()) or 20) + 4
	if size > 0 then button:SetSize(size, size) end
	button:SetShown(self.enabled)
end

function CommunityChatPrivacy:UpdateButtonState()
	if not self.eyeButton then return end
	updateEyeButton(self.eyeButton, not self:IsHidden())
end

function CommunityChatPrivacy:CreateToggleButton()
	if self.eyeButton or not CommunitiesFrame then return end

	local button = CreateFrame("Button", nil, CommunitiesFrame)
	button:SetSize(24, 24)
	button:SetNormalTexture(LFG_EYE_TEXTURE)
	button:SetFrameStrata("HIGH")
	button:SetFrameLevel(CommunitiesFrame:GetFrameLevel() + 1)
	local tex = button:GetNormalTexture()
	if tex then setEyeFrame(tex, LFG_EYE_FRAME_OPEN) end
	button:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]])
	local highlight = button:GetHighlightTexture()
	if highlight then highlight:SetAlpha(0) end
	button:SetScript("OnClick", function()
		if not CommunityChatPrivacy.enabled then return end
		CommunityChatPrivacy.sessionAllowed = not CommunityChatPrivacy.sessionAllowed
		CommunityChatPrivacy:Apply()
	end)
	button:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		local hidden = CommunityChatPrivacy:IsHidden()
		local text
		if hidden then
			text = L["communityChatPrivacyEyeShow"] or "Show Communities chat and members"
		else
			text = L["communityChatPrivacyEyeHide"] or "Hide Communities chat and members"
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(text)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)

	self.eyeButton = button
	self:PositionToggleButton()
	self:UpdateButtonState()
end

function CommunityChatPrivacy:CreateOverlay()
	if self.overlay or not CommunitiesFrame then return end

	local overlay = CreateFrame("Frame", nil, CommunitiesFrame)
	overlay:SetFrameStrata("HIGH")
	overlay:SetFrameLevel(CommunitiesFrame:GetFrameLevel() + 1)
	overlay:EnableMouse(false)
	overlay:Hide()

	local text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	text:SetPoint("TOPLEFT", overlay, "TOPLEFT", 12, -12)
	text:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -12, 12)
	text:SetJustifyH("CENTER")
	text:SetJustifyV("MIDDLE")
	text:SetWordWrap(true)
	overlay.text = text

	self.overlay = overlay
end

function CommunityChatPrivacy:UpdateOverlay(hidden, showChat, showMemberList)
	if not hidden or not self.enabled then
		if self.overlay then self.overlay:Hide() end
		return
	end

	if not self.overlay then self:CreateOverlay() end
	local overlay = self.overlay
	if not overlay then return end

	local anchor = nil
	if showChat and CommunitiesFrame.Chat then
		anchor = CommunitiesFrame.Chat
	elseif showMemberList and CommunitiesFrame.MemberList then
		anchor = CommunitiesFrame.MemberList
	end
	if not anchor then
		overlay:Hide()
		return
	end

	overlay:ClearAllPoints()
	overlay:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
	overlay:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
	overlay.text:SetText(L["communityChatPrivacyOverlay"] or "Click the eye in the top right corner to reveal chat")
	overlay:Show()
end

function CommunityChatPrivacy:Apply()
	if not self.loaded or not CommunitiesFrame then return end

	local hidden = self:IsHidden()
	local displayMode = CommunitiesFrame.GetDisplayMode and CommunitiesFrame:GetDisplayMode() or nil
	local showChat = displayMode == COMMUNITIES_FRAME_DISPLAY_MODES.CHAT or displayMode == COMMUNITIES_FRAME_DISPLAY_MODES.MINIMIZED
	local showMemberList = displayMode == COMMUNITIES_FRAME_DISPLAY_MODES.CHAT or displayMode == COMMUNITIES_FRAME_DISPLAY_MODES.ROSTER

	if hidden then
		if CommunitiesFrame.Chat then CommunitiesFrame.Chat:Hide() end
		if CommunitiesFrame.MemberList then CommunitiesFrame.MemberList:Hide() end
	else
		if CommunitiesFrame.Chat and showChat then CommunitiesFrame.Chat:Show() end
		if CommunitiesFrame.MemberList and showMemberList then CommunitiesFrame.MemberList:Show() end
	end

	self:UpdateOverlay(hidden, showChat, showMemberList)
	self:PositionToggleButton()
	self:UpdateButtonState()
end

function CommunityChatPrivacy:OnDisplayModeChanged() self:Apply() end

function CommunityChatPrivacy:OnShow() self:Apply() end

function CommunityChatPrivacy:OnHide()
	if not self.enabled then return end
	if self:IsAlwaysMode() then self.sessionAllowed = false end
end

function CommunityChatPrivacy:OnClubSelected() self:Apply() end

function CommunityChatPrivacy:OnCommunitiesLoaded()
	if self.loaded or not CommunitiesFrame then return end
	self.loaded = true

	self:CreateToggleButton()

	if not self.hooksInstalled then
		if CommunitiesFrame.RegisterCallback and CommunitiesFrameMixin and CommunitiesFrameMixin.Event then
			CommunitiesFrame:RegisterCallback(CommunitiesFrameMixin.Event.DisplayModeChanged, self.OnDisplayModeChanged, self)
			CommunitiesFrame:RegisterCallback(CommunitiesFrameMixin.Event.ClubSelected, self.OnClubSelected, self)
		end
		CommunitiesFrame:HookScript("OnShow", function() self:OnShow() end)
		CommunitiesFrame:HookScript("OnHide", function() self:OnHide() end)
		self.hooksInstalled = true
	end

	self:Apply()
end

function CommunityChatPrivacy:SetMode(mode)
	if addon.db then addon.db.communityChatPrivacyMode = mode end
	if self.enabled then self:Apply() end
end

function CommunityChatPrivacy:SetEnabled(enabled)
	self.enabled = enabled and true or false
	if not self.enabled then self.sessionAllowed = false end

	if self.enabled and isCommunitiesLoaded() then self:OnCommunitiesLoaded() end

	if self.eyeButton then self.eyeButton:SetShown(self.enabled) end
	self:Apply()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
	if name == "Blizzard_Communities" then CommunityChatPrivacy:OnCommunitiesLoaded() end
end)

if isCommunitiesLoaded() then CommunityChatPrivacy:OnCommunitiesLoaded() end
