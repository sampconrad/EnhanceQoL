local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.GCDBar = addon.GCDBar or {}
local GCDBar = addon.GCDBar

local L = LibStub("AceLocale-3.0"):GetLocale(parentAddonName)
local EditMode = addon.EditMode
local SettingType = EditMode and EditMode.lib and EditMode.lib.SettingType
local LSM = LibStub("LibSharedMedia-3.0", true)

local EDITMODE_ID = "gcdBar"
local GCD_SPELL_ID = 61304
local ANCHOR_TARGET_UI = "UIParent"
local ANCHOR_TARGET_PLAYER_CASTBAR = "PLAYER_CASTBAR"
local EQOL_PLAYER_CASTBAR = "EQOLUFPlayerHealthCast"
local ANCHOR_POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local VALID_ANCHOR_POINTS = {}
for _, point in ipairs(ANCHOR_POINTS) do
	VALID_ANCHOR_POINTS[point] = true
end

GCDBar.defaults = GCDBar.defaults
	or {
		width = 200,
		height = 18,
		texture = "DEFAULT",
		color = { r = 1, g = 0.82, b = 0.2, a = 1 },
		bgEnabled = false,
		bgTexture = "SOLID",
		bgColor = { r = 0, g = 0, b = 0, a = 0 },
		borderEnabled = false,
		borderTexture = "DEFAULT",
		borderColor = { r = 0, g = 0, b = 0, a = 0.8 },
		borderSize = 1,
		borderOffset = 0,
		progressMode = "REMAINING",
		fillDirection = "LEFT",
		anchorRelativeFrame = ANCHOR_TARGET_UI,
		anchorMatchRelativeWidth = false,
		anchorPoint = "CENTER",
		anchorRelativePoint = "CENTER",
		anchorOffsetX = 0,
		anchorOffsetY = -120,
		hideInPetBattle = false,
	}

local defaults = GCDBar.defaults

local DB_ENABLED = "gcdBarEnabled"
local DB_WIDTH = "gcdBarWidth"
local DB_HEIGHT = "gcdBarHeight"
local DB_TEXTURE = "gcdBarTexture"
local DB_COLOR = "gcdBarColor"
local DB_BG_ENABLED = "gcdBarBackgroundEnabled"
local DB_BG_TEXTURE = "gcdBarBackgroundTexture"
local DB_BG_COLOR = "gcdBarBackgroundColor"
local DB_BORDER_ENABLED = "gcdBarBorderEnabled"
local DB_BORDER_TEXTURE = "gcdBarBorderTexture"
local DB_BORDER_COLOR = "gcdBarBorderColor"
local DB_BORDER_SIZE = "gcdBarBorderSize"
local DB_BORDER_OFFSET = "gcdBarBorderOffset"
local DB_PROGRESS_MODE = "gcdBarProgressMode"
local DB_FILL_DIRECTION = "gcdBarFillDirection"
local DB_ANCHOR_RELATIVE_FRAME = "gcdBarAnchorTarget"
local DB_ANCHOR_MATCH_WIDTH = "gcdBarAnchorMatchWidth"
local DB_ANCHOR_POINT = "gcdBarAnchorPoint"
local DB_ANCHOR_RELATIVE_POINT = "gcdBarAnchorRelativePoint"
local DB_ANCHOR_OFFSET_X = "gcdBarAnchorOffsetX"
local DB_ANCHOR_OFFSET_Y = "gcdBarAnchorOffsetY"
local DB_HIDE_IN_PET_BATTLE = "gcdBarHideInPetBattle"

local DEFAULT_TEX = "Interface\\TargetingFrame\\UI-StatusBar"
local GetSpellCooldownInfo = (C_Spell and C_Spell.GetSpellCooldown) or GetSpellCooldown
local GetTime = GetTime

local function getValue(key, fallback)
	if not addon.db then return fallback end
	local value = addon.db[key]
	if value == nil then return fallback end
	return value
end

local function shouldHideInPetBattleForGCD() return getValue(DB_HIDE_IN_PET_BATTLE, defaults.hideInPetBattle) == true end

local function isPetBattleActive() return C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() == true end

local function clamp(value, minValue, maxValue)
	value = tonumber(value) or minValue
	if value < minValue then return minValue end
	if value > maxValue then return maxValue end
	return value
end

local function normalizeColor(value, fallback)
	if type(value) == "table" then
		local r = value.r or value[1] or 1
		local g = value.g or value[2] or 1
		local b = value.b or value[3] or 1
		local a = value.a or value[4]
		return r, g, b, a
	elseif type(value) == "number" then
		return value, value, value
	end
	local d = fallback or defaults.color or {}
	return d.r or 1, d.g or 1, d.b or 1, d.a
end

local function resolveTexture(key)
	if key == "SOLID" then return "Interface\\Buttons\\WHITE8x8" end
	if not key or key == "DEFAULT" then return DEFAULT_TEX end
	if LSM and LSM.Fetch then
		local tex = LSM:Fetch("statusbar", key, true)
		if tex then return tex end
	end
	return key
end

local function resolveBorderTexture(key)
	if key == "SOLID" then return "Interface\\Buttons\\WHITE8x8" end
	if not key or key == "DEFAULT" then return "Interface\\Buttons\\WHITE8x8" end
	if LSM and LSM.Fetch then
		local tex = LSM:Fetch("border", key, true)
		if tex then return tex end
	end
	return key
end

local function textureOptions()
	local list = {}
	local seen = {}
	local function add(value, label)
		local lv = tostring(value or ""):lower()
		if lv == "" or seen[lv] then return end
		seen[lv] = true
		list[#list + 1] = { value = value, label = label }
	end
	add("DEFAULT", _G.DEFAULT)
	add("SOLID", "Solid")
	if LSM and LSM.HashTable then
		for name, path in pairs(LSM:HashTable("statusbar") or {}) do
			if type(path) == "string" and path ~= "" then add(name, tostring(name)) end
		end
	end
	table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return list
end

local function borderOptions()
	local list = {}
	local seen = {}
	local function add(value, label)
		local lv = tostring(value or ""):lower()
		if lv == "" or seen[lv] then return end
		seen[lv] = true
		list[#list + 1] = { value = value, label = label }
	end
	add("DEFAULT", _G.DEFAULT)
	add("SOLID", "Solid")
	if LSM and LSM.HashTable then
		for name, path in pairs(LSM:HashTable("border") or {}) do
			if type(path) == "string" and path ~= "" then add(name, tostring(name)) end
		end
	end
	table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return list
end

local function normalizeProgressMode(value)
	if value == "ELAPSED" then return "ELAPSED" end
	return "REMAINING"
end

local function normalizeFillDirection(value)
	if value == "RIGHT" then return "RIGHT" end
	return "LEFT"
end

local function normalizeAnchorPoint(value, fallback)
	if value and VALID_ANCHOR_POINTS[value] then return value end
	if fallback and VALID_ANCHOR_POINTS[fallback] then return fallback end
	return "CENTER"
end

local function normalizeAnchorRelativeFrame(value)
	if value == ANCHOR_TARGET_PLAYER_CASTBAR or value == "PlayerCastingBarFrame" or value == EQOL_PLAYER_CASTBAR then return ANCHOR_TARGET_PLAYER_CASTBAR end
	if type(value) == "string" and value ~= "" then return value end
	return ANCHOR_TARGET_UI
end

local function normalizeAnchorOffset(value, fallback)
	local num = tonumber(value)
	if num == nil then num = fallback end
	if num == nil then num = 0 end
	return clamp(num, -1000, 1000)
end

local function refreshSettingsUI()
	local lib = addon.EditModeLib
	if not (lib and lib.internal) then return end
	if lib.internal.RefreshSettings then lib.internal:RefreshSettings() end
	if lib.internal.RefreshSettingValues then lib.internal:RefreshSettingValues() end
end

local function isCustomPlayerCastbarEnabled()
	local cfg = addon.db and addon.db.ufFrames and addon.db.ufFrames.player
	if not (cfg and cfg.enabled == true) then return false end
	local castCfg = cfg.cast
	if not castCfg then
		local uf = addon.Aura and addon.Aura.UF
		local defaults = uf and uf.defaults and uf.defaults.player
		castCfg = defaults and defaults.cast
	end
	if not castCfg then return false end
	return castCfg.enabled ~= false
end

local function resolvePlayerCastbarFrame()
	local wantsCustom = isCustomPlayerCastbarEnabled()
	if wantsCustom then
		local custom = _G and _G[EQOL_PLAYER_CASTBAR]
		if custom then return custom, true, true end
	end
	local blizz = _G and _G.PlayerCastingBarFrame
	if blizz then return blizz, false, wantsCustom end
	return UIParent, false, wantsCustom
end

function GCDBar:GetWidth() return clamp(getValue(DB_WIDTH, defaults.width), 50, 800) end

function GCDBar:GetHeight() return clamp(getValue(DB_HEIGHT, defaults.height), 6, 200) end

function GCDBar:GetTextureKey()
	local key = getValue(DB_TEXTURE, defaults.texture)
	if not key or key == "" then key = defaults.texture end
	return key
end

function GCDBar:GetColor() return normalizeColor(getValue(DB_COLOR, defaults.color), defaults.color) end

function GCDBar:GetBackgroundEnabled() return getValue(DB_BG_ENABLED, defaults.bgEnabled) == true end

function GCDBar:GetBackgroundTextureKey()
	local key = getValue(DB_BG_TEXTURE, defaults.bgTexture)
	if not key or key == "" then key = defaults.bgTexture end
	return key
end

function GCDBar:GetBackgroundColor() return normalizeColor(getValue(DB_BG_COLOR, defaults.bgColor), defaults.bgColor) end

function GCDBar:GetBorderEnabled() return getValue(DB_BORDER_ENABLED, defaults.borderEnabled) == true end

function GCDBar:GetBorderTextureKey()
	local key = getValue(DB_BORDER_TEXTURE, defaults.borderTexture)
	if not key or key == "" then key = defaults.borderTexture end
	return key
end

function GCDBar:GetBorderColor() return normalizeColor(getValue(DB_BORDER_COLOR, defaults.borderColor), defaults.borderColor) end

function GCDBar:GetBorderSize() return clamp(getValue(DB_BORDER_SIZE, defaults.borderSize), 1, 20) end

function GCDBar:GetBorderOffset() return clamp(getValue(DB_BORDER_OFFSET, defaults.borderOffset), -20, 20) end

function GCDBar:GetProgressMode() return normalizeProgressMode(getValue(DB_PROGRESS_MODE, defaults.progressMode)) end

function GCDBar:GetFillDirection() return normalizeFillDirection(getValue(DB_FILL_DIRECTION, defaults.fillDirection)) end

function GCDBar:GetAnchorRelativeFrame()
	local target = getValue(DB_ANCHOR_RELATIVE_FRAME, defaults.anchorRelativeFrame or ANCHOR_TARGET_UI)
	return normalizeAnchorRelativeFrame(target)
end

function GCDBar:GetAnchorMatchWidth() return getValue(DB_ANCHOR_MATCH_WIDTH, defaults.anchorMatchRelativeWidth == true) == true end

function GCDBar:GetAnchorPoint() return normalizeAnchorPoint(getValue(DB_ANCHOR_POINT, defaults.anchorPoint), defaults.anchorPoint) end

function GCDBar:GetAnchorRelativePoint()
	local point = normalizeAnchorPoint(getValue(DB_ANCHOR_RELATIVE_POINT, defaults.anchorRelativePoint), self:GetAnchorPoint())
	return point
end

function GCDBar:GetAnchorOffsetX() return normalizeAnchorOffset(getValue(DB_ANCHOR_OFFSET_X, defaults.anchorOffsetX), defaults.anchorOffsetX) end

function GCDBar:GetAnchorOffsetY() return normalizeAnchorOffset(getValue(DB_ANCHOR_OFFSET_Y, defaults.anchorOffsetY), defaults.anchorOffsetY) end

function GCDBar:GetHideInPetBattle() return shouldHideInPetBattleForGCD() end

function GCDBar:AnchorUsesUIParent() return self:GetAnchorRelativeFrame() == ANCHOR_TARGET_UI end

function GCDBar:AnchorUsesMatchedWidth() return self:GetAnchorMatchWidth() and not self:AnchorUsesUIParent() end

local function anchorDefaultsFor(target)
	if target == ANCHOR_TARGET_UI then
		local point = defaults.anchorPoint or "CENTER"
		local relPoint = defaults.anchorRelativePoint or point
		return point, relPoint, defaults.anchorOffsetX or 0, defaults.anchorOffsetY or 0
	end
	return "TOPLEFT", "BOTTOMLEFT", 0, 0
end

function GCDBar:ResolveAnchorFrame()
	local target = self:GetAnchorRelativeFrame()
	self._anchorUsingCustom = nil
	self._anchorWantsCustom = nil

	if target == ANCHOR_TARGET_UI then return UIParent end

	if target == ANCHOR_TARGET_PLAYER_CASTBAR then
		local frame, usingCustom, wantsCustom = resolvePlayerCastbarFrame()
		self._anchorUsingCustom = usingCustom
		self._anchorWantsCustom = wantsCustom
		if wantsCustom and not usingCustom then self:ScheduleAnchorRefresh(target) end
		return frame or UIParent
	end

	local frame = _G and _G[target]
	if frame then return frame end
	self:ScheduleAnchorRefresh(target)
	return UIParent
end

function GCDBar:ScheduleAnchorRefresh(target)
	if not (C_Timer and C_Timer.NewTicker) then return end
	local desired = normalizeAnchorRelativeFrame(target or self:GetAnchorRelativeFrame())
	if desired == ANCHOR_TARGET_UI then return end

	if self._anchorRefreshTicker then
		if self._anchorRefreshTarget == desired then return end
		self._anchorRefreshTicker:Cancel()
		self._anchorRefreshTicker = nil
	end

	self._anchorRefreshTarget = desired
	local tries = 0
	self._anchorRefreshTicker = C_Timer.NewTicker(0.2, function()
		tries = tries + 1
		if self:GetAnchorRelativeFrame() ~= desired then
			if self._anchorRefreshTicker then self._anchorRefreshTicker:Cancel() end
			self._anchorRefreshTicker = nil
			self._anchorRefreshTarget = nil
			return
		end

		if desired == ANCHOR_TARGET_PLAYER_CASTBAR then
			local frame, usingCustom, wantsCustom = resolvePlayerCastbarFrame()
			if frame and (not wantsCustom or usingCustom) then
				if self._anchorRefreshTicker then self._anchorRefreshTicker:Cancel() end
				self._anchorRefreshTicker = nil
				self._anchorRefreshTarget = nil
				self:RefreshAnchor()
				return
			end
		elseif _G and _G[desired] then
			if self._anchorRefreshTicker then self._anchorRefreshTicker:Cancel() end
			self._anchorRefreshTicker = nil
			self._anchorRefreshTarget = nil
			self:RefreshAnchor()
			return
		end

		if tries >= 25 then
			if self._anchorRefreshTicker then self._anchorRefreshTicker:Cancel() end
			self._anchorRefreshTicker = nil
			self._anchorRefreshTarget = nil
		end
	end)
end

function GCDBar:RefreshAnchor()
	if self._refreshingAnchor then return end
	local target = self:GetAnchorRelativeFrame()
	if self._anchorRefreshTicker and (target == ANCHOR_TARGET_UI or self._anchorRefreshTarget ~= target) then
		self._anchorRefreshTicker:Cancel()
		self._anchorRefreshTicker = nil
		self._anchorRefreshTarget = nil
	end
	self._refreshingAnchor = true
	if EditMode and EditMode.RefreshFrame then EditMode:RefreshFrame(EDITMODE_ID) end
	self._refreshingAnchor = nil
	if target == ANCHOR_TARGET_PLAYER_CASTBAR then
		if isCustomPlayerCastbarEnabled() and not (_G and _G[EQOL_PLAYER_CASTBAR]) then self:ScheduleAnchorRefresh(target) end
	elseif target ~= ANCHOR_TARGET_UI then
		if not (_G and _G[target]) then self:ScheduleAnchorRefresh(target) end
	end
end

function GCDBar:MaybeUpdateAnchor()
	local target = self:GetAnchorRelativeFrame()
	if target == ANCHOR_TARGET_PLAYER_CASTBAR then
		if isCustomPlayerCastbarEnabled() then
			if _G and _G[EQOL_PLAYER_CASTBAR] and not self._anchorUsingCustom then
				self:RefreshAnchor()
			elseif not (_G and _G[EQOL_PLAYER_CASTBAR]) then
				self:ScheduleAnchorRefresh(target)
			end
		elseif self._anchorUsingCustom then
			self:RefreshAnchor()
		end
	elseif target ~= ANCHOR_TARGET_UI then
		if not (_G and _G[target]) then self:ScheduleAnchorRefresh(target) end
	end
end

local widthMatchHookedFrames = {}
local pendingWidthHookRetries = {}
local widthSyncQueued = false

function GCDBar:ScheduleMatchedWidthSync()
	if widthSyncQueued then return end
	if not (C_Timer and C_Timer.After) then
		self:ApplySize()
		return
	end
	widthSyncQueued = true
	C_Timer.After(0, function()
		widthSyncQueued = false
		if not (addon and addon.db and addon.db[DB_ENABLED] == true) then return end
		GCDBar:ApplySize()
		if EditMode and EditMode.RefreshFrame then EditMode:RefreshFrame(EDITMODE_ID) end
	end)
end

function GCDBar:EnsureWidthSyncHook(frameName)
	if not frameName or frameName == "" or frameName == ANCHOR_TARGET_UI or frameName == "EQOL_GCDBar" then return end
	if widthMatchHookedFrames[frameName] then return end
	local frame = _G and _G[frameName]
	if not frame then
		if C_Timer and C_Timer.After and not pendingWidthHookRetries[frameName] then
			pendingWidthHookRetries[frameName] = true
			C_Timer.After(1, function()
				pendingWidthHookRetries[frameName] = nil
				if GCDBar and GCDBar.EnsureWidthSyncHook then GCDBar:EnsureWidthSyncHook(frameName) end
			end)
		end
		return
	end
	if frame.HookScript then
		local function onGeometryChanged()
			if GCDBar and GCDBar.AnchorUsesMatchedWidth and GCDBar:AnchorUsesMatchedWidth() then GCDBar:ScheduleMatchedWidthSync() end
		end
		local okSize = pcall(frame.HookScript, frame, "OnSizeChanged", onGeometryChanged)
		local okShow = pcall(frame.HookScript, frame, "OnShow", onGeometryChanged)
		local okHide = pcall(frame.HookScript, frame, "OnHide", onGeometryChanged)
		if okSize or okShow or okHide then widthMatchHookedFrames[frameName] = true end
	end
end

function GCDBar:EnsureWidthSyncHooks()
	if not self:AnchorUsesMatchedWidth() then return end
	local target = self:GetAnchorRelativeFrame()
	if target == ANCHOR_TARGET_PLAYER_CASTBAR then
		self:EnsureWidthSyncHook("PlayerCastingBarFrame")
		self:EnsureWidthSyncHook(EQOL_PLAYER_CASTBAR)
	elseif target ~= ANCHOR_TARGET_UI then
		self:EnsureWidthSyncHook(target)
	end
end

function GCDBar:GetResolvedWidth()
	local width = self:GetWidth()
	if not self:AnchorUsesMatchedWidth() then return width end
	local relativeFrame = self:ResolveAnchorFrame()
	if not (relativeFrame and relativeFrame.GetWidth) then return width end
	local relativeWidth = tonumber(relativeFrame:GetWidth()) or 0
	if relativeWidth <= 0 then return width end
	return math.max(50, relativeWidth)
end

function GCDBar:ApplyAppearance()
	if not self.frame then return end
	local texture = resolveTexture(self:GetTextureKey())
	self.frame:SetStatusBarTexture(texture)
	local r, g, b, a = self:GetColor()
	self.frame:SetStatusBarColor(r, g, b, a or 1)
	if self.frame.SetReverseFill then self.frame:SetReverseFill(self:GetFillDirection() == "RIGHT") end

	if self.frame.bg then
		if self:GetBackgroundEnabled() then
			local bgTex = resolveTexture(self:GetBackgroundTextureKey())
			self.frame.bg:SetTexture(bgTex)
			local br, bg, bb, ba = self:GetBackgroundColor()
			local alpha = (ba == nil) and 1 or ba
			self.frame.bg:SetVertexColor(br or 0, bg or 0, bb or 0, alpha)
			self.frame.bg:Hide()
			if alpha > 0 then self.frame.bg:Show() end
		else
			self.frame.bg:Hide()
		end
	end

	if self.frame.border then
		if not self:GetBorderEnabled() then
			self.frame.border:SetBackdrop(nil)
			self.frame.border:Hide()
		else
			local size = self:GetBorderSize()
			local offset = self:GetBorderOffset()
			local borderTex = resolveBorderTexture(self:GetBorderTextureKey())
			self.frame.border:SetBackdrop({
				edgeFile = borderTex,
				edgeSize = size,
				insets = { left = 0, right = 0, top = 0, bottom = 0 },
			})
			local br, bg, bb, ba = self:GetBorderColor()
			self.frame.border:SetBackdropBorderColor(br or 0, bg or 0, bb or 0, ba or 1)
			self.frame.border:SetBackdropColor(0, 0, 0, 0)
			self.frame.border:ClearAllPoints()
			self.frame.border:SetPoint("TOPLEFT", self.frame, "TOPLEFT", -offset, offset)
			self.frame.border:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", offset, -offset)
			self.frame.border:Show()
		end
	end
end

function GCDBar:ApplySize()
	if not self.frame then return end
	self:EnsureWidthSyncHooks()
	local width = self:GetResolvedWidth()
	local height = self:GetHeight()
	self.frame:SetSize(width, height)
	if self.frame.bg then self.frame.bg:SetAllPoints(self.frame) end
	if self.frame.editBg then self.frame.editBg:SetAllPoints(self.frame) end
	if self.frame.border then self.frame.border:SetAllPoints(self.frame) end
end

function GCDBar:EnsureFrame()
	if self.frame then return self.frame end

	local bar = CreateFrame("StatusBar", "EQOL_GCDBar", UIParent)
	bar:SetMinMaxValues(0, 1)
	bar:SetClampedToScreen(true)
	bar:Hide()

	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(bar)
	bar.bg = bg

	local editBg = bar:CreateTexture(nil, "BORDER")
	editBg:SetAllPoints(bar)
	editBg:SetColorTexture(0.1, 0.6, 0.6, 0.2)
	editBg:Hide()
	bar.editBg = editBg

	local border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
	border:SetAllPoints(bar)
	border:SetFrameLevel((bar:GetFrameLevel() or 0) + 2)
	border:Hide()
	bar.border = border

	local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("CENTER")
	label:SetText(L["GCDBar"] or "GCD Bar")
	label:Hide()
	bar.label = label

	self.frame = bar
	self:ApplyAppearance()
	self:ApplySize()

	return bar
end

function GCDBar:ShowEditModeHint(show)
	if not self.frame then return end
	if show then
		if self.frame.editBg then self.frame.editBg:Show() end
		self.frame.label:Show()
		self.previewing = true
		self.frame:SetMinMaxValues(0, 1)
		self.frame:SetValue(1)
		self.frame:Show()
	else
		if self.frame.editBg then self.frame.editBg:Hide() end
		self.frame.label:Hide()
		self.previewing = nil
		self:UpdateGCD()
	end
end

function GCDBar:StopTimer()
	if self.frame and self.frame.SetScript then self.frame:SetScript("OnUpdate", nil) end
	self._gcdActive = nil
	self._gcdStart = nil
	self._gcdDuration = nil
	self._gcdRate = nil
	if self.frame then self.frame:Hide() end
end

function GCDBar:UpdateTimer()
	if self.previewing then return end
	if not self.frame then return end
	if not self._gcdActive then return end
	local start = self._gcdStart
	local duration = self._gcdDuration
	if not start or not duration or duration <= 0 then
		self:StopTimer()
		return
	end
	local now = GetTime and GetTime() or 0
	local rate = self._gcdRate or 1
	local elapsed = (now - start) * rate
	if elapsed >= duration then
		self:StopTimer()
		return
	end
	local progress = elapsed / duration
	if progress < 0 then progress = 0 end
	if progress > 1 then progress = 1 end
	local value = progress
	if self:GetProgressMode() ~= "ELAPSED" then value = 1 - progress end
	self.frame:SetMinMaxValues(0, 1)
	self.frame:SetValue(value)
	self.frame:Show()
end

function GCDBar:UpdateGCD()
	if self.previewing then return end
	if not self.frame then return end
	if shouldHideInPetBattleForGCD() and isPetBattleActive() then
		self:StopTimer()
		return
	end
	self:MaybeUpdateAnchor()
	if not GetSpellCooldownInfo then return end

	local start, duration, enabled, modRate
	local info, info2, info3, info4 = GetSpellCooldownInfo(GCD_SPELL_ID)
	if type(info) == "table" then
		start = info.startTime
		duration = info.duration
		enabled = info.isEnabled
		modRate = info.modRate or 1
	else
		start, duration, enabled, modRate = info, info2, info3, info4
	end
	if not enabled or not duration or duration <= 0 or not start or start <= 0 then
		self:StopTimer()
		return
	end
	self._gcdActive = true
	self._gcdStart = start
	self._gcdDuration = duration
	self._gcdRate = modRate or 1
	if self.frame.SetScript then self.frame:SetScript("OnUpdate", function() GCDBar:UpdateTimer() end) end
	self:UpdateTimer()
end

function GCDBar:OnEvent(event, spellID, baseSpellID)
	if event ~= "SPELL_UPDATE_COOLDOWN" and event ~= "PET_BATTLE_OPENING_START" and event ~= "PET_BATTLE_CLOSE" then return end
	self:UpdateGCD()
end

function GCDBar:RegisterEvents()
	if self.eventsRegistered then return end
	local frame = self:EnsureFrame()
	frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	frame:RegisterEvent("PET_BATTLE_OPENING_START")
	frame:RegisterEvent("PET_BATTLE_CLOSE")
	frame:SetScript("OnEvent", function(_, event, ...) GCDBar:OnEvent(event, ...) end)
	self.eventsRegistered = true
end

function GCDBar:UnregisterEvents()
	if not self.eventsRegistered or not self.frame then return end
	self.frame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
	self.frame:UnregisterEvent("PET_BATTLE_OPENING_START")
	self.frame:UnregisterEvent("PET_BATTLE_CLOSE")
	self.frame:SetScript("OnEvent", nil)
	self.eventsRegistered = false
end

local editModeRegistered = false

function GCDBar:ApplyLayoutData(data)
	if not data or not addon.db then return end

	local width = clamp(data.width or defaults.width, 50, 800)
	local height = clamp(data.height or defaults.height, 6, 200)
	local texture = data.texture or defaults.texture
	local r, g, b, a = normalizeColor(data.color or defaults.color, defaults.color)
	local bgEnabled = data.bgEnabled == true
	local bgTexture = data.bgTexture or defaults.bgTexture
	local bgr, bgg, bgb, bga = normalizeColor(data.bgColor or defaults.bgColor, defaults.bgColor)
	local borderEnabled = data.borderEnabled == true
	local borderTexture = data.borderTexture or defaults.borderTexture
	local bdr, bdg, bdb, bda = normalizeColor(data.borderColor or defaults.borderColor, defaults.borderColor)
	local borderSize = clamp(data.borderSize or defaults.borderSize, 1, 20)
	local borderOffset = clamp(data.borderOffset or defaults.borderOffset, -20, 20)
	local progressMode = normalizeProgressMode(data.progressMode or defaults.progressMode)
	local fillDirection = normalizeFillDirection(data.fillDirection or defaults.fillDirection)
	local anchorRelativeFrame = normalizeAnchorRelativeFrame(data.anchorRelativeFrame or data.anchorTarget or addon.db[DB_ANCHOR_RELATIVE_FRAME] or defaults.anchorRelativeFrame)
	local anchorMatchWidth = addon.db[DB_ANCHOR_MATCH_WIDTH] == true
	if data.anchorMatchWidth ~= nil then
		anchorMatchWidth = data.anchorMatchWidth == true
	elseif data.anchorMatchRelativeWidth ~= nil then
		anchorMatchWidth = data.anchorMatchRelativeWidth == true
	end
	local anchorPoint = normalizeAnchorPoint(data.point or addon.db[DB_ANCHOR_POINT], defaults.anchorPoint)
	local anchorRelativePoint = normalizeAnchorPoint(data.relativePoint or addon.db[DB_ANCHOR_RELATIVE_POINT], anchorPoint)
	local anchorOffsetX = normalizeAnchorOffset(data.x ~= nil and data.x or addon.db[DB_ANCHOR_OFFSET_X], defaults.anchorOffsetX)
	local anchorOffsetY = normalizeAnchorOffset(data.y ~= nil and data.y or addon.db[DB_ANCHOR_OFFSET_Y], defaults.anchorOffsetY)
	local hideInPetBattle = addon.db[DB_HIDE_IN_PET_BATTLE] == true
	if data.hideInPetBattle ~= nil then hideInPetBattle = data.hideInPetBattle == true end

	addon.db[DB_WIDTH] = width
	addon.db[DB_HEIGHT] = height
	addon.db[DB_TEXTURE] = texture
	addon.db[DB_COLOR] = { r = r, g = g, b = b, a = a }
	addon.db[DB_BG_ENABLED] = bgEnabled
	addon.db[DB_BG_TEXTURE] = bgTexture
	addon.db[DB_BG_COLOR] = { r = bgr, g = bgg, b = bgb, a = bga }
	addon.db[DB_BORDER_ENABLED] = borderEnabled
	addon.db[DB_BORDER_TEXTURE] = borderTexture
	addon.db[DB_BORDER_COLOR] = { r = bdr, g = bdg, b = bdb, a = bda }
	addon.db[DB_BORDER_SIZE] = borderSize
	addon.db[DB_BORDER_OFFSET] = borderOffset
	addon.db[DB_PROGRESS_MODE] = progressMode
	addon.db[DB_FILL_DIRECTION] = fillDirection
	local prevAnchorRelativeFrame = addon.db[DB_ANCHOR_RELATIVE_FRAME]
	addon.db[DB_ANCHOR_RELATIVE_FRAME] = anchorRelativeFrame
	addon.db[DB_ANCHOR_MATCH_WIDTH] = anchorMatchWidth and true or false
	addon.db[DB_ANCHOR_POINT] = anchorPoint
	addon.db[DB_ANCHOR_RELATIVE_POINT] = anchorRelativePoint
	addon.db[DB_ANCHOR_OFFSET_X] = anchorOffsetX
	addon.db[DB_ANCHOR_OFFSET_Y] = anchorOffsetY
	addon.db[DB_HIDE_IN_PET_BATTLE] = hideInPetBattle and true or false

	self:ApplySize()
	self:ApplyAppearance()
	if prevAnchorRelativeFrame ~= anchorRelativeFrame then self:RefreshAnchor() end
	self:UpdateGCD()
end

local function applySetting(field, value)
	if not addon.db then return end
	local editField = field
	local skipEditValue

	if field == "width" then
		local width = clamp(value, 50, 800)
		addon.db[DB_WIDTH] = width
		value = width
	elseif field == "height" then
		local height = clamp(value, 6, 200)
		addon.db[DB_HEIGHT] = height
		value = height
	elseif field == "texture" then
		local tex = value or defaults.texture
		addon.db[DB_TEXTURE] = tex
		value = tex
	elseif field == "color" then
		local r, g, b, a = normalizeColor(value, defaults.color)
		addon.db[DB_COLOR] = { r = r, g = g, b = b, a = a }
		value = addon.db[DB_COLOR]
	elseif field == "bgEnabled" then
		local enabled = value == true
		addon.db[DB_BG_ENABLED] = enabled
		value = enabled
	elseif field == "bgTexture" then
		local tex = value or defaults.bgTexture
		addon.db[DB_BG_TEXTURE] = tex
		value = tex
	elseif field == "bgColor" then
		local r, g, b, a = normalizeColor(value, defaults.bgColor)
		addon.db[DB_BG_COLOR] = { r = r, g = g, b = b, a = a }
		value = addon.db[DB_BG_COLOR]
	elseif field == "borderEnabled" then
		local enabled = value == true
		addon.db[DB_BORDER_ENABLED] = enabled
		value = enabled
	elseif field == "borderTexture" then
		local tex = value or defaults.borderTexture
		addon.db[DB_BORDER_TEXTURE] = tex
		value = tex
	elseif field == "borderColor" then
		local r, g, b, a = normalizeColor(value, defaults.borderColor)
		addon.db[DB_BORDER_COLOR] = { r = r, g = g, b = b, a = a }
		value = addon.db[DB_BORDER_COLOR]
	elseif field == "borderSize" then
		local size = clamp(value, 1, 20)
		addon.db[DB_BORDER_SIZE] = size
		value = size
	elseif field == "borderOffset" then
		local offset = clamp(value, -20, 20)
		addon.db[DB_BORDER_OFFSET] = offset
		value = offset
	elseif field == "progressMode" then
		local mode = normalizeProgressMode(value)
		addon.db[DB_PROGRESS_MODE] = mode
		value = mode
	elseif field == "fillDirection" then
		local dir = normalizeFillDirection(value)
		addon.db[DB_FILL_DIRECTION] = dir
		value = dir
	elseif field == "anchorRelativeFrame" then
		local target = normalizeAnchorRelativeFrame(value)
		local prev = addon.db[DB_ANCHOR_RELATIVE_FRAME]
		addon.db[DB_ANCHOR_RELATIVE_FRAME] = target
		editField = "anchorRelativeFrame"
		if EditMode and EditMode.SetValue then EditMode:SetValue(EDITMODE_ID, editField, target, nil, true) end
		if prev ~= target then
			local point, relPoint, x, y = anchorDefaultsFor(target)
			addon.db[DB_ANCHOR_POINT] = point
			addon.db[DB_ANCHOR_RELATIVE_POINT] = relPoint
			addon.db[DB_ANCHOR_OFFSET_X] = x
			addon.db[DB_ANCHOR_OFFSET_Y] = y
			if EditMode and EditMode.SetValue then
				EditMode:SetValue(EDITMODE_ID, "point", point, nil, true)
				EditMode:SetValue(EDITMODE_ID, "relativePoint", relPoint, nil, true)
				EditMode:SetValue(EDITMODE_ID, "x", x, nil, true)
				EditMode:SetValue(EDITMODE_ID, "y", y, nil, true)
			end
			refreshSettingsUI()
		end
		value = target
		skipEditValue = true
	elseif field == "anchorMatchWidth" then
		local enabled = value == true
		addon.db[DB_ANCHOR_MATCH_WIDTH] = enabled and true or false
		value = enabled
		refreshSettingsUI()
	elseif field == "anchorPoint" then
		local point = normalizeAnchorPoint(value, defaults.anchorPoint)
		addon.db[DB_ANCHOR_POINT] = point
		editField = "point"
		value = point
		local rel = normalizeAnchorPoint(addon.db[DB_ANCHOR_RELATIVE_POINT], point)
		if addon.db[DB_ANCHOR_RELATIVE_POINT] ~= rel then
			addon.db[DB_ANCHOR_RELATIVE_POINT] = rel
			if EditMode and EditMode.SetValue then EditMode:SetValue(EDITMODE_ID, "relativePoint", rel, nil, true) end
		end
	elseif field == "anchorRelativePoint" then
		local rel = normalizeAnchorPoint(value, defaults.anchorRelativePoint)
		addon.db[DB_ANCHOR_RELATIVE_POINT] = rel
		editField = "relativePoint"
		value = rel
	elseif field == "anchorOffsetX" then
		local offset = normalizeAnchorOffset(value, defaults.anchorOffsetX)
		addon.db[DB_ANCHOR_OFFSET_X] = offset
		editField = "x"
		value = offset
	elseif field == "anchorOffsetY" then
		local offset = normalizeAnchorOffset(value, defaults.anchorOffsetY)
		addon.db[DB_ANCHOR_OFFSET_Y] = offset
		editField = "y"
		value = offset
	elseif field == "hideInPetBattle" then
		local enabled = value == true
		addon.db[DB_HIDE_IN_PET_BATTLE] = enabled and true or false
		value = enabled
	end

	if not skipEditValue and EditMode and EditMode.SetValue then EditMode:SetValue(EDITMODE_ID, editField, value, nil, true) end
	GCDBar:ApplySize()
	GCDBar:ApplyAppearance()
	GCDBar:RefreshAnchor()
	GCDBar:UpdateGCD()
end

function GCDBar:RegisterEditMode()
	if editModeRegistered or not EditMode or not EditMode.RegisterFrame then return end

	local settings
	if SettingType then
		local function anchorFrameEntries()
			local entries = {}
			local seen = {}
			local function frameIsAvailable(key)
				if key == ANCHOR_TARGET_UI or key == ANCHOR_TARGET_PLAYER_CASTBAR then return true end
				return _G and _G[key] ~= nil
			end
			local function add(key, label, force)
				if not key or key == "" or seen[key] then return end
				if not force and not frameIsAvailable(key) then return end
				seen[key] = true
				entries[#entries + 1] = { key = key, label = label or key }
			end

			add(ANCHOR_TARGET_UI, L["gcdBarAnchorScreen"] or "Screen (UIParent)", true)
			add(ANCHOR_TARGET_PLAYER_CASTBAR, L["gcdBarAnchorPlayerCastbar"] or "Player Castbar", true)

			add("PlayerFrame", _G.HUD_EDIT_MODE_PLAYER_FRAME_LABEL or PLAYER or "Player Frame")
			add("TargetFrame", _G.HUD_EDIT_MODE_TARGET_FRAME_LABEL or TARGET or "Target Frame")

			add("EssentialCooldownViewer", L["cooldownViewerEssential"] or "Essential Cooldown Viewer")
			add("UtilityCooldownViewer", L["cooldownViewerUtility"] or "Utility Cooldown Viewer")
			add("BuffBarCooldownViewer", L["cooldownViewerBuffBar"] or "Buff Bar Cooldowns")
			add("BuffIconCooldownViewer", L["cooldownViewerBuffIcon"] or "Buff Icon Cooldowns")

			local cooldownPanels = addon.Aura and addon.Aura.CooldownPanels
			if cooldownPanels and cooldownPanels.GetRoot then
				local root = cooldownPanels:GetRoot()
				if root and root.panels then
					local order = root.order or {}
					local function addPanelEntry(panelId, panel)
						if not panel or panel.enabled == false then return end
						local label = string.format("Panel %s: %s", tostring(panelId), panel.name or "Cooldown Panel")
						add("EQOL_CooldownPanel" .. tostring(panelId), label)
					end
					if #order > 0 then
						for _, panelId in ipairs(order) do
							addPanelEntry(panelId, root.panels[panelId])
						end
					else
						for panelId, panel in pairs(root.panels) do
							addPanelEntry(panelId, panel)
						end
					end
				end
			end

			local rb = addon.Aura and addon.Aura.ResourceBars
			add("EQOLHealthBar", HEALTH or "Health")
			if rb and rb.classPowerTypes then
				for _, pType in ipairs(rb.classPowerTypes) do
					local frameName = "EQOL" .. tostring(pType) .. "Bar"
					local label = (rb.PowerLabels and rb.PowerLabels[pType]) or _G["POWER_TYPE_" .. tostring(pType)] or tostring(pType)
					add(frameName, label)
				end
			end

			local current = GCDBar:GetAnchorRelativeFrame()
			if current and not seen[current] then add(current, current, true) end

			return entries
		end

		settings = {
			{
				name = L["gcdBarAnchor"] or "Anchor to",
				kind = SettingType.Dropdown,
				field = "anchorRelativeFrame",
				height = 180,
				get = function() return GCDBar:GetAnchorRelativeFrame() end,
				set = function(_, value) applySetting("anchorRelativeFrame", value) end,
				generator = function(_, root)
					for _, option in ipairs(anchorFrameEntries()) do
						root:CreateRadio(option.label, function() return GCDBar:GetAnchorRelativeFrame() == option.key end, function() applySetting("anchorRelativeFrame", option.key) end)
					end
				end,
			},
			{
				name = L["gcdBarAnchorPoint"] or "Anchor point",
				kind = SettingType.Dropdown,
				field = "anchorPoint",
				height = 180,
				get = function() return GCDBar:GetAnchorPoint() end,
				set = function(_, value) applySetting("anchorPoint", value) end,
				generator = function(_, root)
					for _, point in ipairs(ANCHOR_POINTS) do
						root:CreateRadio(point, function() return GCDBar:GetAnchorPoint() == point end, function() applySetting("anchorPoint", point) end)
					end
				end,
			},
			{
				name = L["gcdBarAnchorRelativePoint"] or "Relative point",
				kind = SettingType.Dropdown,
				field = "anchorRelativePoint",
				height = 180,
				get = function() return GCDBar:GetAnchorRelativePoint() end,
				set = function(_, value) applySetting("anchorRelativePoint", value) end,
				generator = function(_, root)
					for _, point in ipairs(ANCHOR_POINTS) do
						root:CreateRadio(point, function() return GCDBar:GetAnchorRelativePoint() == point end, function() applySetting("anchorRelativePoint", point) end)
					end
				end,
			},
			{
				name = L["gcdBarAnchorOffsetX"] or "X Offset",
				kind = SettingType.Slider,
				field = "anchorOffsetX",
				minValue = -1000,
				maxValue = 1000,
				valueStep = 1,
				allowInput = true,
				get = function() return GCDBar:GetAnchorOffsetX() end,
				set = function(_, value) applySetting("anchorOffsetX", value) end,
			},
			{
				name = L["gcdBarAnchorOffsetY"] or "Y Offset",
				kind = SettingType.Slider,
				field = "anchorOffsetY",
				minValue = -1000,
				maxValue = 1000,
				valueStep = 1,
				allowInput = true,
				get = function() return GCDBar:GetAnchorOffsetY() end,
				set = function(_, value) applySetting("anchorOffsetY", value) end,
			},
			{
				name = L["gcdBarAnchorMatchWidth"] or "Match relative frame width",
				kind = SettingType.Checkbox,
				field = "anchorMatchWidth",
				default = defaults.anchorMatchRelativeWidth == true,
				get = function() return GCDBar:GetAnchorMatchWidth() end,
				set = function(_, value) applySetting("anchorMatchWidth", value) end,
				isEnabled = function() return not GCDBar:AnchorUsesUIParent() end,
			},
			{
				name = L["gcdBarHideInPetBattle"] or "Hide in pet battles",
				kind = SettingType.Checkbox,
				field = "hideInPetBattle",
				default = defaults.hideInPetBattle == true,
				get = function() return GCDBar:GetHideInPetBattle() end,
				set = function(_, value) applySetting("hideInPetBattle", value) end,
			},
			{
				name = L["gcdBarWidth"] or "Bar width",
				kind = SettingType.Slider,
				field = "width",
				default = defaults.width,
				minValue = 50,
				maxValue = 800,
				valueStep = 1,
				get = function() return GCDBar:GetWidth() end,
				set = function(_, value) applySetting("width", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
				isEnabled = function() return not GCDBar:AnchorUsesMatchedWidth() end,
			},
			{
				name = L["gcdBarHeight"] or "Bar height",
				kind = SettingType.Slider,
				field = "height",
				default = defaults.height,
				minValue = 6,
				maxValue = 200,
				valueStep = 1,
				get = function() return GCDBar:GetHeight() end,
				set = function(_, value) applySetting("height", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = L["gcdBarTexture"] or "Bar texture",
				kind = SettingType.Dropdown,
				field = "texture",
				height = 180,
				get = function() return GCDBar:GetTextureKey() end,
				set = function(_, value) applySetting("texture", value) end,
				generator = function(_, root)
					for _, option in ipairs(textureOptions()) do
						root:CreateRadio(option.label, function() return GCDBar:GetTextureKey() == option.value end, function() applySetting("texture", option.value) end)
					end
				end,
			},
			{
				name = L["gcdBarColor"] or "Bar color",
				kind = SettingType.Color,
				field = "color",
				default = defaults.color,
				hasOpacity = true,
				get = function()
					local r, g, b, a = GCDBar:GetColor()
					return { r = r, g = g, b = b, a = a }
				end,
				set = function(_, value) applySetting("color", value) end,
			},
			{
				name = L["gcdBarBackgroundEnabled"] or "Use background",
				kind = SettingType.Checkbox,
				field = "bgEnabled",
				default = defaults.bgEnabled == true,
				get = function() return GCDBar:GetBackgroundEnabled() end,
				set = function(_, value) applySetting("bgEnabled", value) end,
			},
			{
				name = L["gcdBarBackgroundTexture"] or "Background texture",
				kind = SettingType.Dropdown,
				field = "bgTexture",
				height = 180,
				get = function() return GCDBar:GetBackgroundTextureKey() end,
				set = function(_, value) applySetting("bgTexture", value) end,
				generator = function(_, root)
					for _, option in ipairs(textureOptions()) do
						root:CreateRadio(option.label, function() return GCDBar:GetBackgroundTextureKey() == option.value end, function() applySetting("bgTexture", option.value) end)
					end
				end,
				isEnabled = function() return GCDBar:GetBackgroundEnabled() end,
			},
			{
				name = L["gcdBarBackgroundColor"] or "Background color",
				kind = SettingType.Color,
				field = "bgColor",
				default = defaults.bgColor,
				hasOpacity = true,
				get = function()
					local r, g, b, a = GCDBar:GetBackgroundColor()
					return { r = r, g = g, b = b, a = a }
				end,
				set = function(_, value) applySetting("bgColor", value) end,
				isEnabled = function() return GCDBar:GetBackgroundEnabled() end,
			},
			{
				name = L["gcdBarBorderEnabled"] or "Use border",
				kind = SettingType.Checkbox,
				field = "borderEnabled",
				default = defaults.borderEnabled == true,
				get = function() return GCDBar:GetBorderEnabled() end,
				set = function(_, value) applySetting("borderEnabled", value) end,
			},
			{
				name = L["gcdBarBorderTexture"] or "Border texture",
				kind = SettingType.Dropdown,
				field = "borderTexture",
				height = 180,
				get = function() return GCDBar:GetBorderTextureKey() end,
				set = function(_, value) applySetting("borderTexture", value) end,
				generator = function(_, root)
					for _, option in ipairs(borderOptions()) do
						root:CreateRadio(option.label, function() return GCDBar:GetBorderTextureKey() == option.value end, function() applySetting("borderTexture", option.value) end)
					end
				end,
				isEnabled = function() return GCDBar:GetBorderEnabled() end,
			},
			{
				name = L["gcdBarBorderSize"] or "Border size",
				kind = SettingType.Slider,
				field = "borderSize",
				default = defaults.borderSize,
				minValue = 1,
				maxValue = 20,
				valueStep = 1,
				get = function() return GCDBar:GetBorderSize() end,
				set = function(_, value) applySetting("borderSize", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
				isEnabled = function() return GCDBar:GetBorderEnabled() end,
			},
			{
				name = L["gcdBarBorderOffset"] or "Border offset",
				kind = SettingType.Slider,
				field = "borderOffset",
				default = defaults.borderOffset,
				minValue = -20,
				maxValue = 20,
				valueStep = 1,
				get = function() return GCDBar:GetBorderOffset() end,
				set = function(_, value) applySetting("borderOffset", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
				isEnabled = function() return GCDBar:GetBorderEnabled() end,
			},
			{
				name = L["gcdBarBorderColor"] or "Border color",
				kind = SettingType.Color,
				field = "borderColor",
				default = defaults.borderColor,
				hasOpacity = true,
				get = function()
					local r, g, b, a = GCDBar:GetBorderColor()
					return { r = r, g = g, b = b, a = a }
				end,
				set = function(_, value) applySetting("borderColor", value) end,
				isEnabled = function() return GCDBar:GetBorderEnabled() end,
			},
			{
				name = L["gcdBarProgressMode"] or "Progress mode",
				kind = SettingType.Dropdown,
				field = "progressMode",
				height = 100,
				get = function() return GCDBar:GetProgressMode() end,
				set = function(_, value) applySetting("progressMode", value) end,
				generator = function(_, root)
					local opts = {
						{ value = "REMAINING", label = L["gcdBarProgressDeplete"] or "Deplete (remaining time)" },
						{ value = "ELAPSED", label = L["gcdBarProgressFill"] or "Fill (elapsed time)" },
					}
					for _, option in ipairs(opts) do
						root:CreateRadio(option.label, function() return GCDBar:GetProgressMode() == option.value end, function() applySetting("progressMode", option.value) end)
					end
				end,
			},
			{
				name = L["gcdBarFillDirection"] or "Fill direction",
				kind = SettingType.Dropdown,
				field = "fillDirection",
				height = 100,
				get = function() return GCDBar:GetFillDirection() end,
				set = function(_, value) applySetting("fillDirection", value) end,
				generator = function(_, root)
					local opts = {
						{ value = "LEFT", label = L["gcdBarFillLeft"] or "Left to right" },
						{ value = "RIGHT", label = L["gcdBarFillRight"] or "Right to left" },
					}
					for _, option in ipairs(opts) do
						root:CreateRadio(option.label, function() return GCDBar:GetFillDirection() == option.value end, function() applySetting("fillDirection", option.value) end)
					end
				end,
			},
		}
	end

	EditMode:RegisterFrame(EDITMODE_ID, {
		frame = self:EnsureFrame(),
		title = L["GCDBar"] or "GCD Bar",
		layoutDefaults = {
			point = self:GetAnchorPoint(),
			relativePoint = self:GetAnchorRelativePoint(),
			x = self:GetAnchorOffsetX(),
			y = self:GetAnchorOffsetY(),
			width = self:GetWidth(),
			height = self:GetHeight(),
			texture = self:GetTextureKey(),
			bgEnabled = self:GetBackgroundEnabled(),
			bgTexture = self:GetBackgroundTextureKey(),
			bgColor = (function()
				local r, g, b, a = self:GetBackgroundColor()
				return { r = r, g = g, b = b, a = a }
			end)(),
			borderEnabled = self:GetBorderEnabled(),
			borderTexture = self:GetBorderTextureKey(),
			borderColor = (function()
				local r, g, b, a = self:GetBorderColor()
				return { r = r, g = g, b = b, a = a }
			end)(),
			borderSize = self:GetBorderSize(),
			borderOffset = self:GetBorderOffset(),
			progressMode = self:GetProgressMode(),
			fillDirection = self:GetFillDirection(),
			anchorRelativeFrame = self:GetAnchorRelativeFrame(),
			anchorMatchWidth = self:GetAnchorMatchWidth(),
			hideInPetBattle = self:GetHideInPetBattle(),
			color = (function()
				local r, g, b, a = self:GetColor()
				return { r = r, g = g, b = b, a = a }
			end)(),
		},
		onApply = function(_, _, data) GCDBar:ApplyLayoutData(data) end,
		onEnter = function() GCDBar:ShowEditModeHint(true) end,
		onExit = function() GCDBar:ShowEditModeHint(false) end,
		isEnabled = function() return addon.db and addon.db[DB_ENABLED] end,
		settings = settings,
		relativeTo = function() return GCDBar:ResolveAnchorFrame() end,
		allowDrag = function() return GCDBar:AnchorUsesUIParent() end,
		showOutsideEditMode = false,
		showReset = false,
		showSettingsReset = false,
		enableOverlayToggle = true,
	})

	editModeRegistered = true
end

function GCDBar:OnSettingChanged(enabled)
	if enabled then
		self:EnsureFrame()
		self:RegisterEditMode()
		self:RegisterEvents()
		self:ApplySize()
		self:ApplyAppearance()
		self:UpdateGCD()
	else
		self:UnregisterEvents()
		self:StopTimer()
		if self.frame then self.frame:Hide() end
		if self._anchorRefreshTicker then
			self._anchorRefreshTicker:Cancel()
			self._anchorRefreshTicker = nil
		end
	end

	if EditMode and EditMode.RefreshFrame then EditMode:RefreshFrame(EDITMODE_ID) end
end

return GCDBar
