local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")

addon.Visibility = addon.Visibility or {}
addon.Visibility.functions = addon.Visibility.functions or {}
local Visibility = addon.Visibility
Visibility.runtime = Visibility.runtime or {}

local Helper = Visibility.helper
if not Helper then return end

local math = math
local getEditor

local FADE_DURATION = 0.15
local FADE_THRESHOLD = 0.01
local MAX_GROUP_DEPTH = 3
local IGNORE_FRAME_NAMES = {
	UIParent = true,
	WorldFrame = true,
	MotionSicknessFrame = true,
	GlobalFXBackgroundModelScene = true,
}
local IGNORE_FRAME_NAME_PREFIXES = {
	"GlobalFXBackgroundModelScene",
}

local function isIgnoredFrameName(name)
	if not name or name == "" then return false end
	if IGNORE_FRAME_NAMES[name] then return true end
	for _, prefix in ipairs(IGNORE_FRAME_NAME_PREFIXES) do
		if name:sub(1, #prefix) == prefix then return true end
	end
	return false
end

local function getActionBarFrameEntries()
	local list = {}
	local seen = {}
	local entries = addon.variables and addon.variables.actionBarNames
	if type(entries) == "table" then
		for _, info in ipairs(entries) do
			local name = info and info.name
			if type(name) == "string" and name ~= "" and not seen[name] then
				seen[name] = true
				list[#list + 1] = { name = name, label = info.text or name, allowMissing = true }
			end
		end
	end
	return list
end

local function getUnitFrameEntries()
	local list = {}
	local seen = {}
	local entries = addon.variables and addon.variables.unitFrameNames
	if type(entries) == "table" then
		for _, info in ipairs(entries) do
			local name = info and info.name
			if type(name) == "string" and name ~= "" and not seen[name] then
				seen[name] = true
				list[#list + 1] = { name = name, label = info.text or name, allowMissing = true }
			end
		end
	end
	return list
end

local function getCooldownViewerEntries()
	local list = {}
	local frames = (addon.constants and addon.constants.COOLDOWN_VIEWER_FRAMES) or {
		"EssentialCooldownViewer",
		"UtilityCooldownViewer",
		"BuffBarCooldownViewer",
		"BuffIconCooldownViewer",
	}
	local labels = {
		EssentialCooldownViewer = L["cooldownViewerEssential"] or "Essential Cooldown Viewer",
		UtilityCooldownViewer = L["cooldownViewerUtility"] or "Utility Cooldown Viewer",
		BuffBarCooldownViewer = L["cooldownViewerBuffBar"] or "Buff Bar Cooldowns",
		BuffIconCooldownViewer = L["cooldownViewerBuffIcon"] or "Buff Icon Cooldowns",
	}
	local seen = {}
	for _, name in ipairs(frames) do
		if type(name) == "string" and name ~= "" and not seen[name] then
			seen[name] = true
			list[#list + 1] = { name = name, label = labels[name] or name, allowMissing = true }
		end
	end
	return list
end

local function getResourceBarEntries()
	local list = {}
	if not (addon and addon.db and addon.db.enableResourceFrame == true) then return list end
	local rb = addon.Aura and addon.Aura.ResourceBars
	if not rb then return list end
	local seen = {}
	local function add(name, label)
		if type(name) ~= "string" or name == "" or seen[name] then return end
		seen[name] = true
		list[#list + 1] = { name = name, label = label or name, allowMissing = true }
	end
	add("EQOLHealthBar", HEALTH or "Health")
	local class = addon.variables and addon.variables.unitClass
	local spec = addon.variables and addon.variables.unitSpec
	local allowed = rb.powertypeClasses and class and spec and rb.powertypeClasses[class] and rb.powertypeClasses[class][spec] or nil
	local function isAllowed(pType)
		if not allowed then return true end
		if allowed.MAIN and pType == allowed.MAIN then return true end
		return allowed[pType] == true
	end
	if rb.classPowerTypes then
		for _, pType in ipairs(rb.classPowerTypes) do
			if isAllowed(pType) then
				local frameName = "EQOL" .. tostring(pType) .. "Bar"
				local label = (rb.PowerLabels and rb.PowerLabels[pType]) or _G["POWER_TYPE_" .. tostring(pType)] or tostring(pType)
				add(frameName, label)
			end
		end
	end
	return list
end

local function stopFade(target)
	local group = target and target.EQOL_VisibilityFadeGroup
	if group and group.Stop then group:Stop() end
	if group then group.targetAlpha = nil end
end

local function applyAlphaToRegion(target, alpha, useFade)
	if not target or not target.SetAlpha then return end
	if not useFade or not target.CreateAnimationGroup then
		stopFade(target)
		target:SetAlpha(alpha)
		return
	end

	if addon.variables and addon.variables.isMidnight then
		stopFade(target)
		target:SetAlpha(alpha)
		return
	end

	local issecretvalue = _G.issecretvalue
	if issecretvalue and issecretvalue(alpha) then
		stopFade(target)
		target:SetAlpha(alpha)
		return
	end

	local current = target:GetAlpha()
	if issecretvalue and issecretvalue(current) then
		stopFade(target)
		target:SetAlpha(alpha)
		return
	end

	local delta = current - alpha
	if issecretvalue and issecretvalue(delta) then
		stopFade(target)
		target:SetAlpha(alpha)
		return
	end

	if math.abs(delta) < FADE_THRESHOLD then
		stopFade(target)
		target:SetAlpha(alpha)
		return
	end

	local group = target.EQOL_VisibilityFadeGroup
	if not group or not group.fade then
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
		target.EQOL_VisibilityFadeGroup = group
	end

	local anim = group.fade
	if not anim or not anim.SetFromAlpha or not anim.SetToAlpha or not anim.SetDuration then
		stopFade(target)
		target:SetAlpha(alpha)
		return
	end

	if group.targetAlpha ~= nil and group.targetAlpha == alpha and group.IsPlaying and group:IsPlaying() then return end
	if group.IsPlaying and group:IsPlaying() then group:Stop() end
	anim:SetFromAlpha(current)
	anim:SetToAlpha(alpha)
	anim:SetDuration(FADE_DURATION)
	group.targetAlpha = alpha
	group:Play()
end

local function ensureRoot()
	if not addon.db then return nil end
	addon.db.visibilityConfigs = Helper.NormalizeRoot(addon.db.visibilityConfigs)
	return addon.db.visibilityConfigs
end

function Visibility:EnsureDB() return ensureRoot() end
function Visibility:GetRoot() return ensureRoot() end

function Visibility:GetConfig(configId)
	local root = ensureRoot()
	return root and root.configs and root.configs[configId] or nil
end

function Visibility:GetConfigOrder()
	local root = ensureRoot()
	return root and root.order or {}
end

function Visibility:SetSelectedConfig(configId)
	local root = ensureRoot()
	if not root then return end
	if configId and root.configs and root.configs[configId] then
		root.selectedConfig = configId
	else
		root.selectedConfig = nil
	end
end

function Visibility:GetSelectedConfig()
	local root = ensureRoot()
	return root and root.selectedConfig or nil
end

function Visibility:CreateConfig(name)
	local root = ensureRoot()
	if not root then return nil end
	local configId = Helper.GetNextNumericId(root.configs)
	local config = Helper.CopyTableShallow(Helper.CONFIG_DEFAULTS)
	config.name = name or config.name
	config.frames = {}
	config.rules = { op = "AND", children = {} }
	root.configs[configId] = config
	root.order[#root.order + 1] = configId
	root.selectedConfig = configId
	return configId
end

function Visibility:DeleteConfig(configId)
	local root = ensureRoot()
	if not root or not root.configs or not root.configs[configId] then return false end
	local config = root.configs[configId]
	if config and config.frames then
		for _, name in ipairs(config.frames) do
			if root.frameIndex and root.frameIndex[name] == configId then root.frameIndex[name] = nil end
		end
	end
	root.configs[configId] = nil
	for i = #root.order, 1, -1 do
		if root.order[i] == configId then table.remove(root.order, i) end
	end
	if root.selectedConfig == configId then root.selectedConfig = nil end
	self:RequestUpdate()
	return true
end

local function resolveFrameByName(name)
	if type(name) ~= "string" or name == "" then return nil end
	local obj = _G[name]
	if not obj then
		if name == "PetActionBar" then
			obj = _G.PetActionBarFrame
		elseif name == "StanceBar" then
			obj = _G.StanceBarFrame
		end
	end
	if not obj or type(obj) ~= "table" then return nil end
	if obj.IsForbidden and obj:IsForbidden() then return nil end
	if obj.IsObjectType and not obj:IsObjectType("Frame") then return nil end
	return obj
end

function Visibility:AddFrame(configId, name)
	local root = ensureRoot()
	if not root then return false, "missing" end
	if not resolveFrameByName(name) then return false, "invalid" end
	local ok, reason = Helper.AddFrameToConfig(root, configId, name)
	if ok then self:RequestUpdate() end
	return ok, reason
end

function Visibility:RemoveFrame(configId, name)
	local root = ensureRoot()
	if not root then return false end
	local ok = Helper.RemoveFrameFromConfig(root, configId, name)
	if ok then self:RequestUpdate() end
	return ok
end

function Visibility:RequestUpdate()
	local runtime = self.runtime
	if runtime.pendingUpdate then return end
	runtime.pendingUpdate = true
	C_Timer.After(0, function()
		local state = Visibility.runtime
		if not state then return end
		state.pendingUpdate = nil
		Visibility:ApplyAll()
	end)
end

local function ensureMouseoverWatcher(runtime)
	if runtime.mouseoverWatcher then return end
	local watcher = CreateFrame("Frame")
	watcher.elapsed = 0
	watcher:SetScript("OnUpdate", function(self, elapsed)
		local state = Visibility.runtime
		if not state or not state.mouseoverActive then return end
		self.elapsed = (self.elapsed or 0) + (elapsed or 0)
		if self.elapsed < 0.05 then return end
		self.elapsed = 0
		local changed = false
		for _, entry in ipairs(state.mouseoverStates or {}) do
			local frame = entry and entry.frame
			local over = false
			if frame and frame.IsShown and frame:IsShown() then over = MouseIsOver and MouseIsOver(frame) or false end
			if over ~= entry.isMouseOver then
				entry.isMouseOver = over
				changed = true
			end
		end
		if changed then Visibility:RequestUpdate() end
	end)
	runtime.mouseoverWatcher = watcher
end

local function applyFrameConfig(state, config, context)
	local frame = state.frame
	if not frame then return end

	local baseAlpha = state.baseAlpha
	if type(baseAlpha) ~= "number" then
		baseAlpha = frame:GetAlpha() or 1
		state.baseAlpha = baseAlpha
	end
	local issecretvalue = _G.issecretvalue
	if issecretvalue and issecretvalue(baseAlpha) then
		applyAlphaToRegion(frame, baseAlpha, false)
		state.lastAlpha = baseAlpha
		return
	end

	local fadeAlpha = Helper.ClampAlpha(config.fadeAlpha) or 0
	if fadeAlpha < 0 then fadeAlpha = 0 end
	if fadeAlpha > 1 then fadeAlpha = 1 end

	context.MOUSEOVER = state.isMouseOver and true or false
	local match = Helper.EvaluateRule(config.rules, context)
	if match == nil then
		applyAlphaToRegion(frame, baseAlpha, true)
		state.lastAlpha = baseAlpha
		return
	end

	local shouldShow
	if config.mode == Helper.MODES.HIDE then
		shouldShow = not match
	else
		shouldShow = match
	end
	local targetAlpha = shouldShow and baseAlpha or (baseAlpha * fadeAlpha)
	applyAlphaToRegion(frame, targetAlpha, true)
	state.lastAlpha = targetAlpha
end

function Visibility:ApplyAll()
	local root = ensureRoot()
	if not root then return end

	local runtime = self.runtime
	runtime.frameStates = runtime.frameStates or {}
	local mouseoverStates = {}

	local context = Helper.BuildContext(runtime)
	local managed = {}

	for _, configId in ipairs(root.order or {}) do
		local config = root.configs and root.configs[configId]
		if config and config.enabled and Helper.HasRules(config.rules) then
			for _, name in ipairs(config.frames or {}) do
				local frame = resolveFrameByName(name)
				if frame then
					managed[name] = true
					local state = runtime.frameStates[name]
					if not state then
						state = { frame = frame, name = name }
						runtime.frameStates[name] = state
					else
						state.frame = frame
					end
					state.isMouseOver = state.isMouseOver or false
					state.usesMouseover = Helper.RuleUsesMouseover(config.rules)
					if state.usesMouseover then
						state.isMouseOver = MouseIsOver and MouseIsOver(frame)
						mouseoverStates[#mouseoverStates + 1] = state
					else
						state.isMouseOver = false
					end
					applyFrameConfig(state, config, context)
				end
			end
		end
	end

	for name, state in pairs(runtime.frameStates) do
		if not managed[name] then
			if state and state.frame and state.frame.SetAlpha then
				local baseAlpha = state.baseAlpha
				if type(baseAlpha) ~= "number" then baseAlpha = state.frame:GetAlpha() or 1 end
				applyAlphaToRegion(state.frame, baseAlpha, true)
			end
			runtime.frameStates[name] = nil
		end
	end

	runtime.mouseoverStates = mouseoverStates
	runtime.mouseoverActive = #mouseoverStates > 0
	if runtime.mouseoverActive then ensureMouseoverWatcher(runtime) end
end

local function ensureSkyridingDriver()
	local runtime = Visibility.runtime
	if runtime.skyridingDriver then return end
	local driver = CreateFrame("Frame")
	driver:Hide()
	local function update(value)
		runtime.isSkyriding = value and true or false
		Visibility:RequestUpdate()
	end
	driver:SetScript("OnShow", function() update(true) end)
	driver:SetScript("OnHide", function() update(false) end)

	local expr
	if addon.variables.unitClass == "DRUID" then
		expr = "[advflyable, mounted] show; [advflyable, stance:3] show; hide"
	else
		expr = "[advflyable, mounted] show; hide"
	end
	local function registerDriver()
		if runtime.skyridingDriverRegistered then return end
		if RegisterStateDriver then
			pcall(RegisterStateDriver, driver, "visibility", expr)
			runtime.skyridingDriverRegistered = true
			runtime.isSkyriding = driver:IsShown()
		end
	end

	if InCombatLockdown and InCombatLockdown() then
		runtime.pendingSkyridingDriver = registerDriver
		if not runtime.skyridingDriverWatcher then
			local watcher = CreateFrame("Frame")
			watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
			watcher:SetScript("OnEvent", function(self)
				if InCombatLockdown and InCombatLockdown() then return end
				local cb = runtime.pendingSkyridingDriver
				runtime.pendingSkyridingDriver = nil
				if cb then cb() end
				self:UnregisterEvent("PLAYER_REGEN_ENABLED")
				runtime.skyridingDriverWatcher = nil
			end)
			runtime.skyridingDriverWatcher = watcher
		end
	else
		registerDriver()
	end

	runtime.skyridingDriver = driver
end

local function safeRegisterUnitEvent(frame, event, ...)
	if not frame or not frame.RegisterUnitEvent or type(event) ~= "string" then return false end
	local ok = pcall(frame.RegisterUnitEvent, frame, event, ...)
	return ok
end

local function ensureWatcher()
	local runtime = Visibility.runtime
	if runtime.watcher then return end
	ensureSkyridingDriver()
	local watcher = CreateFrame("Frame")
	watcher:SetScript("OnEvent", function(self, event, unit)
		if event:match("^UNIT_") and unit and unit ~= "player" then return end
		Visibility:RequestUpdate()
	end)
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
	watcher:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
	watcher:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
	watcher:RegisterEvent("ZONE_CHANGED")
	watcher:RegisterEvent("ZONE_CHANGED_INDOORS")
	watcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	safeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_START", "player")
	safeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_STOP", "player")
	safeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_FAILED", "player")
	safeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_INTERRUPTED", "player")
	safeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_CHANNEL_START", "player")
	safeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_CHANNEL_STOP", "player")
	runtime.watcher = watcher
	Visibility:RequestUpdate()
end

function Visibility:Init()
	ensureRoot()
	ensureWatcher()
	Visibility:RequestUpdate()
end

Visibility.functions.InitState = function() Visibility:Init() end

getEditor = function()
	local runtime = Visibility.runtime
	return runtime and runtime.editor or nil
end

local function applyEditorPosition(frame)
	if not frame or not addon or not addon.db then return end
	local point = addon.db.visibilityEditorPoint
	local x = addon.db.visibilityEditorX
	local y = addon.db.visibilityEditorY
	if not point or x == nil or y == nil then return end
	frame:ClearAllPoints()
	frame:SetPoint(point, UIParent, point, x, y)
end

local function saveEditorPosition(frame)
	if not frame or not addon or not addon.db then return end
	local point, _, _, x, y = frame:GetPoint()
	if not point or x == nil or y == nil then return end
	addon.db.visibilityEditorPoint = point
	addon.db.visibilityEditorX = x
	addon.db.visibilityEditorY = y
end

local function applyPanelBorder(frame)
	local borderLayer, borderSubLevel = "BORDER", 0
	local borderPath = "Interface\\AddOns\\EnhanceQoL\\Assets\\PanelBorder_"
	local cornerSize = 70
	local edgeThickness = 70
	local cornerOffsets = 13

	local function makeTex(key, layer, subLevel)
		local tex = frame:CreateTexture(nil, layer or borderLayer, nil, subLevel or borderSubLevel)
		tex:SetTexture(borderPath .. key .. ".tga")
		tex:SetAlpha(0.95)
		return tex
	end

	local tl = makeTex("tl", borderLayer, borderSubLevel + 1)
	tl:SetSize(cornerSize, cornerSize)
	tl:SetPoint("TOPLEFT", frame, "TOPLEFT", -cornerOffsets, cornerOffsets)

	local tr = makeTex("tr", borderLayer, borderSubLevel + 1)
	tr:SetSize(cornerSize, cornerSize)
	tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", cornerOffsets + 8, cornerOffsets)

	local bl = makeTex("bl", borderLayer, borderSubLevel + 1)
	bl:SetSize(cornerSize, cornerSize)
	bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -cornerOffsets, -cornerOffsets)

	local br = makeTex("br", borderLayer, borderSubLevel + 1)
	br:SetSize(cornerSize, cornerSize)
	br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", cornerOffsets + 8, -cornerOffsets)

	local top = makeTex("t", borderLayer, borderSubLevel)
	top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
	top:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0)
	top:SetHeight(edgeThickness)
	top:SetHorizTile(true)

	local bottom = makeTex("b", borderLayer, borderSubLevel)
	bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT", 0, 0)
	bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
	bottom:SetHeight(edgeThickness)
	bottom:SetHorizTile(true)

	local left = makeTex("l", borderLayer, borderSubLevel)
	left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT", 0, 0)
	left:SetWidth(edgeThickness)
	left:SetVertTile(true)

	local right = makeTex("r", borderLayer, borderSubLevel)
	right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0)
	right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
	right:SetWidth(edgeThickness)
	right:SetVertTile(true)
end

local function applyInsetBorder(frame, offset)
	if not frame then return end
	offset = offset or 10

	local layer, subLevel = "BORDER", 2
	local path = "Interface\\AddOns\\EnhanceQoL\\Assets\\border_round_"
	local cornerSize = 36
	local edgeSize = 36

	frame.eqolInsetParts = frame.eqolInsetParts or {}
	local parts = frame.eqolInsetParts

	local function tex(name)
		if not parts[name] then parts[name] = frame:CreateTexture(nil, layer, nil, subLevel) end
		local t = parts[name]
		t:SetAlpha(0.7)
		t:SetTexture(path .. name .. ".tga")
		t:SetDrawLayer(layer, subLevel)
		return t
	end

	local tl = tex("tl")
	tl:SetSize(cornerSize, cornerSize)
	tl:ClearAllPoints()
	tl:SetPoint("TOPLEFT", frame, "TOPLEFT", offset, -offset)

	local tr = tex("tr")
	tr:SetSize(cornerSize, cornerSize)
	tr:ClearAllPoints()
	tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -offset, -offset)

	local bl = tex("bl")
	bl:SetSize(cornerSize, cornerSize)
	bl:ClearAllPoints()
	bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", offset, offset)

	local br = tex("br")
	br:SetSize(cornerSize, cornerSize)
	br:ClearAllPoints()
	br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -offset, offset)

	local top = tex("t")
	top:ClearAllPoints()
	top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
	top:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0)
	top:SetHeight(edgeSize)
	top:SetHorizTile(true)

	local bottom = tex("b")
	bottom:ClearAllPoints()
	bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT", 0, 0)
	bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
	bottom:SetHeight(edgeSize)
	bottom:SetHorizTile(true)

	local left = tex("l")
	left:ClearAllPoints()
	left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT", 0, 0)
	left:SetWidth(edgeSize)
	left:SetVertTile(true)

	local right = tex("r")
	right:ClearAllPoints()
	right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0)
	right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
	right:SetWidth(edgeSize)
	right:SetVertTile(true)
end

local function createLabel(parent, text, size, style)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetText(text or "")
	label:SetFont((addon.variables and addon.variables.defaultFont) or label:GetFont(), size or 12, style or "OUTLINE")
	label:SetTextColor(1, 0.82, 0, 1)
	return label
end

local function createButton(parent, text, width, height)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetText(text or "")
	btn:SetSize(width or 120, height or 22)
	return btn
end

local function createEditBox(parent, width, height)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width or 120, height or 22)
	box:SetAutoFocus(false)
	box:SetFontObject(GameFontHighlightSmall)
	return box
end

local function createCheck(parent, text)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb.Text:SetText(text or "")
	cb.Text:SetTextColor(1, 1, 1, 1)
	return cb
end

local function createSlider(parent, width, minValue, maxValue, step)
	local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
	slider:SetMinMaxValues(minValue or 0, maxValue or 1)
	slider:SetValueStep(step or 1)
	slider:SetObeyStepOnDrag(true)
	slider:SetWidth(width or 180)
	if slider.Low then slider.Low:SetText(tostring(minValue or 0)) end
	if slider.High then slider.High:SetText(tostring(maxValue or 1)) end
	return slider
end

local function createRowButton(parent, height)
	local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
	row:SetHeight(height or 28)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints(row)
	row.bg:SetColorTexture(0, 0, 0, 0.2)
	row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.highlight:SetAllPoints(row)
	row.highlight:SetColorTexture(1, 1, 1, 0.06)
	return row
end

local function setStatus(editor, text, r, g, b)
	if not editor or not editor.statusText then return end
	editor.statusText:SetText(text or "")
	editor.statusText:SetTextColor(r or 0.9, g or 0.9, b or 0.9, 1)
end

local function showModeMenu(owner, current, onSelect)
	if not MenuUtil or not MenuUtil.CreateContextMenu then return end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:SetTag("MENU_EQOL_VISIBILITY_MODE")
		root:CreateTitle(L["VisibilityMode"] or "Mode")
		root:CreateRadio(L["VisibilityModeShow"] or "Show when", function() return current == Helper.MODES.SHOW end, function() onSelect(Helper.MODES.SHOW) end)
		root:CreateRadio(L["VisibilityModeHide"] or "Hide when", function() return current == Helper.MODES.HIDE end, function() onSelect(Helper.MODES.HIDE) end)
	end)
end

local function showJoinMenu(owner, current, onSelect)
	if not MenuUtil or not MenuUtil.CreateContextMenu then return end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:SetTag("MENU_EQOL_VISIBILITY_JOIN")
		root:CreateTitle(L["VisibilityGroup"] or "Group")
		root:CreateRadio(QUEST_LOGIC_AND, function() return current == "AND" end, function() onSelect("AND") end)
		root:CreateRadio(QUEST_LOGIC_OR, function() return current == "OR" end, function() onSelect("OR") end)
	end)
end

local function getSortedRuleDefinitions()
	local defs = {}
	for _, def in ipairs(Helper.RULE_DEFINITIONS) do
		defs[#defs + 1] = def
	end
	table.sort(defs, function(a, b)
		local la = (a.label or a.key or ""):lower()
		local lb = (b.label or b.key or ""):lower()
		if la == lb then return (a.key or "") < (b.key or "") end
		return la < lb
	end)
	return defs
end

local function addFramesToConfig(frameEntries)
	local editor = getEditor()
	local configId = editor and editor.selectedConfigId
	if not configId then
		configId = Visibility:CreateConfig(L["VisibilityNewConfig"] or "New Visibility Config")
		Visibility:SetSelectedConfig(configId)
	end
	local root = ensureRoot()
	local cfg = configId and Visibility:GetConfig(configId)
	if not root or not cfg then return end
	local added, assigned, exists, invalid = 0, 0, 0, 0
	local changed = false
	for _, entry in ipairs(frameEntries or {}) do
		local name = entry and (entry.name or entry)
		local ok, reason
		if type(name) == "string" and name ~= "" then
			ok, reason = Helper.AddFrameToConfig(root, configId, name)
		end
		if ok then
			added = added + 1
			changed = true
		elseif reason == "assigned" then
			assigned = assigned + 1
		elseif reason == "exists" then
			exists = exists + 1
		elseif reason then
			invalid = invalid + 1
		end
	end
	if changed then Visibility:RequestUpdate() end
	if editor then
		if added > 0 then
			setStatus(editor, string.format(L["VisibilityFramesAdded"] or "Added %d frames.", added), 0.6, 0.9, 0.6)
		elseif assigned > 0 then
			setStatus(editor, L["VisibilityFramesAssigned"] or "Frames already assigned to another config.", 1, 0.5, 0.3)
		elseif exists > 0 then
			setStatus(editor, L["VisibilityFrameExists"] or "Frame already in this config.", 1, 0.5, 0.3)
		elseif invalid > 0 then
			setStatus(editor, L["VisibilityFrameInvalid"] or "Invalid frame.", 1, 0.5, 0.3)
		else
			setStatus(editor, L["VisibilityFramesNoneAdded"] or "No frames added.", 1, 0.5, 0.3)
		end
	end
	Visibility:RefreshEditor()
end

local function hasConditionInGroup(group, key, exclude)
	if not group or type(group.children) ~= "table" then return false end
	for _, child in ipairs(group.children) do
		if child ~= exclude and child.key == key then return true end
	end
	return false
end

local function showKnownFramesMenu(owner)
	if not MenuUtil or not MenuUtil.CreateContextMenu then return end
	local rootData = ensureRoot()
	local frameIndex = rootData and rootData.frameIndex or {}
	local function addGroup(root, label, allLabel, entries)
		if not entries or #entries == 0 then return end
		local addable = {}
		for _, entry in ipairs(entries) do
			local name = entry and entry.name
			if name and not frameIndex[name] then addable[#addable + 1] = entry end
		end
		local sub = root:CreateButton(label)
		local allButton = sub:CreateButton(allLabel, function() addFramesToConfig(addable) end)
		if #addable == 0 and allButton.SetEnabled then allButton:SetEnabled(false) end
		for _, entry in ipairs(entries) do
			local name = entry and entry.name
			local labelText = entry and (entry.label or entry.name) or ""
			local button = sub:CreateButton(labelText, function() addFramesToConfig({ entry }) end)
			if name and frameIndex[name] and button.SetEnabled then button:SetEnabled(false) end
		end
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:SetTag("MENU_EQOL_VISIBILITY_KNOWN")
		root:CreateTitle(L["VisibilityKnownFrames"] or "Known frames")
		addGroup(root, L["visibilityKindActionBars"] or "Action Bars", L["VisibilityAllActionBars"] or "All Action Bars", getActionBarFrameEntries())
		addGroup(root, L["VisibilityKnownUnitFrames"] or "Unit Frames", L["VisibilityAllUnitFrames"] or "All Unit Frames", getUnitFrameEntries())
		addGroup(root, L["VisibilityKnownResourceBars"] or "Resource Bars", L["VisibilityAllResourceBars"] or "All Resource Bars", getResourceBarEntries())
		addGroup(root, L["VisibilityKnownCooldownViewer"] or "Cooldown Viewer", L["VisibilityAllCooldownViewers"] or "All Cooldown Viewers", getCooldownViewerEntries())
	end)
end

local function showAddMenu(owner, canAddGroup, onAddGroup, onAddCondition)
	if not MenuUtil or not MenuUtil.CreateContextMenu then return end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:SetTag("MENU_EQOL_VISIBILITY_ADD")
		local groupButton = root:CreateButton(L["VisibilityGroup"] or "Group", function()
			if canAddGroup and onAddGroup then onAddGroup() end
		end)
		if not canAddGroup and groupButton.SetEnabled then groupButton:SetEnabled(false) end
		local submenu = root:CreateButton(L["VisibilityConditions"] or "Conditions")
		for _, def in ipairs(getSortedRuleDefinitions()) do
			submenu:CreateButton(def.label, function()
				if onAddCondition then onAddCondition(def.key) end
			end)
		end
	end)
end

local function showConditionMenu(owner, onSelect)
	if not MenuUtil or not MenuUtil.CreateContextMenu then return end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:SetTag("MENU_EQOL_VISIBILITY_COND")
		root:CreateTitle(L["VisibilityAddCondition"] or "Add condition")
		for _, def in ipairs(getSortedRuleDefinitions()) do
			root:CreateButton(def.label, function() onSelect(def.key) end)
		end
	end)
end

local function buildRuleRows(node, depth, list, isRoot, parent)
	if not node then return end
	if node.key then
		list[#list + 1] = { kind = "cond", node = node, depth = depth, parent = parent }
		return
	end
	list[#list + 1] = { kind = "group", node = node, depth = depth, isRoot = isRoot, parent = parent }
	for _, child in ipairs(node.children or {}) do
		buildRuleRows(child, depth + 1, list, false, node)
	end
end

local function ensurePicker(editor)
	local runtime = Visibility.runtime
	if runtime.picker then return runtime.picker end
	local picker = CreateFrame("Frame", "EQOL_VisibilityPicker", UIParent)
	picker:SetAllPoints(UIParent)
	picker:SetFrameStrata("TOOLTIP")
	picker:EnableMouse(true)
	picker:EnableKeyboard(true)
	picker:SetPropagateKeyboardInput(false)
	picker:EnableMouseWheel(true)
	picker:Hide()

	picker.highlight = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	picker.highlight:SetFrameStrata("TOOLTIP")
	if picker.highlight.SetBackdrop then
		picker.highlight:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
			insets = { left = 2, right = 2, top = 2, bottom = 2 },
		})
		picker.highlight:SetBackdropColor(0.1, 0.9, 0.2, 0.12)
		picker.highlight:SetBackdropBorderColor(0.2, 1, 0.4, 0.8)
	else
		picker.highlight.texture = picker.highlight:CreateTexture(nil, "OVERLAY")
		picker.highlight.texture:SetAllPoints(picker.highlight)
		picker.highlight.texture:SetColorTexture(0.1, 0.9, 0.2, 0.18)
	end
	picker.highlight:Hide()

	picker.label = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	picker.label:SetPoint("TOPLEFT", picker, "TOPLEFT", 20, -20)
	picker.label:SetTextColor(1, 1, 1, 1)

	picker.help = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	picker.help:SetPoint("TOPLEFT", picker.label, "BOTTOMLEFT", 0, -4)
	picker.help:SetText(L["VisibilityPickerHint"] or "Hover a frame and left-click to add. Right-click to cancel.")

	picker.tooltip = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	picker.tooltip:SetFrameStrata("TOOLTIP")
	picker.tooltip:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	picker.tooltip:SetBackdropColor(0, 0, 0, 0.85)
	picker.tooltip:SetBackdropBorderColor(0.2, 0.8, 0.2, 0.9)
	picker.tooltip:SetSize(200, 44)
	picker.tooltip.text = picker.tooltip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	picker.tooltip.text:SetPoint("TOPLEFT", picker.tooltip, "TOPLEFT", 8, -6)
	picker.tooltip.text:SetTextColor(1, 1, 1, 1)
	picker.tooltip.subtext = picker.tooltip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	picker.tooltip.subtext:SetPoint("TOPLEFT", picker.tooltip.text, "BOTTOMLEFT", 0, -2)
	picker.tooltip.subtext:SetTextColor(0.8, 0.8, 0.8, 1)
	picker.tooltip:Hide()

	runtime.picker = picker
	return picker
end

local function isFrameIgnored(frame, ignore)
	if not frame then return false end
	local current = frame
	while current do
		if current.GetName and isIgnoredFrameName(current:GetName()) then return true end
		if ignore[current] then return true end
		if not current.GetParent then break end
		current = current:GetParent()
	end
	return false
end

local function buildFrameStackList(ignore)
	if not C_System or not C_System.GetFrameStack then return {} end
	local stack = C_System.GetFrameStack()
	if not stack then return {} end
	local list = {}
	local seen = {}
	for _, obj in ipairs(stack) do
		if obj and obj.GetName then
			local frame = obj
			if not (frame.IsObjectType and frame:IsObjectType("Frame")) and obj.GetParent then frame = obj:GetParent() end
			if frame and frame.GetName and frame.IsObjectType and frame:IsObjectType("Frame") then
				local name = frame:GetName()
				if name and name ~= "" and _G[name] == frame and not seen[name] then
					if not isIgnoredFrameName(name) and not (frame.IsForbidden and frame:IsForbidden()) and not isFrameIgnored(frame, ignore) then
						seen[name] = true
						list[#list + 1] = { frame = frame, name = name }
					end
				end
			end
		end
	end
	return list
end

local function startPicker(editor, configId)
	local picker = ensurePicker(editor)
	local runtime = Visibility.runtime
	runtime.pickerConfigId = configId
	runtime.pickerIgnore = runtime.pickerIgnore or {}
	runtime.pickerIgnore[editor.frame] = true
	runtime.pickerIgnore[picker] = true
	runtime.pickerIgnore[picker.highlight] = true
	runtime.pickerIgnore[picker.tooltip] = true
	if addon and addon.mousePointer then runtime.pickerIgnore[addon.mousePointer] = true end
	if addon and addon.mouseTrailRunner then runtime.pickerIgnore[addon.mouseTrailRunner] = true end
	if _G[addonName .. "_MouseRingFrame"] then runtime.pickerIgnore[_G[addonName .. "_MouseRingFrame"]] = true end
	if _G.WorldFrame then runtime.pickerIgnore[_G.WorldFrame] = true end
	if _G.MotionSicknessFrame then runtime.pickerIgnore[_G.MotionSicknessFrame] = true end
	if _G.GlobalFXBackgroundModelScene then runtime.pickerIgnore[_G.GlobalFXBackgroundModelScene] = true end

	picker.currentName = nil
	picker.currentFrame = nil
	picker.nextUpdate = 0
	picker.stackIndex = nil
	picker.stack = nil
	picker.locked = false
	picker.lastCursorX = nil
	picker.lastCursorY = nil

	local function updateSelection(self)
		local stack = self.stack or {}
		local count = #stack
		if count == 0 then
			self.currentName = nil
			self.currentFrame = nil
			self.label:SetText(L["VisibilityPickerNone"] or "No named frame")
			if self.tooltip then self.tooltip:Hide() end
			picker.highlight:Hide()
			return
		end

		if not self.locked or not self.stackIndex then self.stackIndex = 1 end
		if self.stackIndex > count then self.stackIndex = count end
		if self.stackIndex < 1 then self.stackIndex = 1 end

		local entry = stack[self.stackIndex]
		self.currentName = entry and entry.name or nil
		self.currentFrame = entry and entry.frame or nil
		if self.currentFrame then
			picker.highlight:ClearAllPoints()
			picker.highlight:SetAllPoints(self.currentFrame)
			picker.highlight:Show()
		else
			picker.highlight:Hide()
		end

		local label = self.currentName or (L["VisibilityPickerNone"] or "No named frame")
		label = string.format("%s (%d/%d)", label, self.stackIndex or 0, count)
		self.label:SetText(label)

		if self.tooltip then
			local parentName
			if self.currentFrame and self.currentFrame.GetParent then
				local parent = self.currentFrame:GetParent()
				parentName = parent and parent.GetName and parent:GetName() or nil
			end
			self.tooltip.text:SetText(label)
			if parentName and parentName ~= "" then
				self.tooltip.subtext:SetText((L["VisibilityPickerParent"] or "Parent") .. ": " .. parentName)
			else
				self.tooltip.subtext:SetText("")
			end
		end
	end

	local function cycleSelection(self, dir)
		local stack = self.stack or {}
		local count = #stack
		if count == 0 then return end
		local idx = self.stackIndex or 1
		idx = idx + dir
		if idx < 1 then idx = count end
		if idx > count then idx = 1 end
		self.stackIndex = idx
		self.locked = true
		self.lockedUntil = GetTime() + 2
		self.nextUpdate = 0
		updateSelection(self)
	end

	picker:SetScript("OnUpdate", function(self)
		local now = GetTime()
		if now < (self.nextUpdate or 0) then return end
		self.nextUpdate = now + 0.05
		local x, y = GetCursorPosition()
		if self.lastCursorX and self.lastCursorY then
			local dx = math.abs(x - self.lastCursorX)
			local dy = math.abs(y - self.lastCursorY)
			if dx > 2 or dy > 2 then self.locked = false end
		end
		self.lastCursorX = x
		self.lastCursorY = y
		if self.locked and self.lockedUntil and now > self.lockedUntil then self.locked = false end

		self.stack = buildFrameStackList(runtime.pickerIgnore)
		updateSelection(self)

		if self.tooltip then
			local scale = UIParent:GetEffectiveScale()
			self.tooltip:ClearAllPoints()
			self.tooltip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (x / scale) + 14, (y / scale) + 14)
			if self.currentName then
				self.tooltip:Show()
			else
				self.tooltip:Hide()
			end
		end
	end)

	picker:SetScript("OnKeyDown", function(self, key)
		if key == "ESCAPE" then
			self:Hide()
			self.highlight:Hide()
			if self.tooltip then self.tooltip:Hide() end
			return
		end
		if key == "TAB" then cycleSelection(self, IsShiftKeyDown() and -1 or 1) end
	end)

	picker:SetScript("OnMouseWheel", function(self, delta)
		if delta > 0 then
			cycleSelection(self, -1)
		else
			cycleSelection(self, 1)
		end
	end)

	picker:SetScript("OnMouseUp", function(_, button)
		if button ~= "LeftButton" then
			picker:Hide()
			picker.highlight:Hide()
			if picker.tooltip then picker.tooltip:Hide() end
			return
		end
		local name = picker.currentName
		local targetConfig = runtime.pickerConfigId
		picker:Hide()
		picker.highlight:Hide()
		if picker.tooltip then picker.tooltip:Hide() end
		if not name or not targetConfig then return end
		local ok, reason = Visibility:AddFrame(targetConfig, name)
		if ok then
			setStatus(editor, (L["VisibilityFrameAdded"] or "Frame added.") .. " " .. name, 0.6, 0.9, 0.6)
		else
			local msg = L["VisibilityFrameInvalid"] or "Invalid frame."
			if reason == "assigned" then
				local root = ensureRoot()
				local ownerId = root and root.frameIndex and root.frameIndex[name]
				local owner = ownerId and root.configs and root.configs[ownerId]
				local ownerName = owner and owner.name or tostring(ownerId or "?")
				msg = (L["VisibilityFrameAssigned"] or "Frame already assigned to:") .. " " .. ownerName
			elseif reason == "exists" then
				msg = L["VisibilityFrameExists"] or "Frame already in this config."
			end
			setStatus(editor, msg, 1, 0.5, 0.3)
		end
		Visibility:RefreshEditor()
	end)

	picker:Show()
end

local function stopPicker()
	local runtime = Visibility.runtime
	if not runtime.picker then return end
	runtime.picker:Hide()
	if runtime.picker.highlight then runtime.picker.highlight:Hide() end
	if runtime.picker.tooltip then runtime.picker.tooltip:Hide() end
end

local function ensureEditor()
	local runtime = Visibility.runtime
	if runtime.editor and runtime.editor.frame then return runtime.editor.frame end

	local frame = CreateFrame("Frame", "EQOL_VisibilityEditor", UIParent, "BackdropTemplate")
	frame:SetSize(980, 560)
	frame:SetPoint("CENTER")
	applyEditorPosition(frame)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetFrameStrata("DIALOG")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		saveEditorPosition(self)
	end)
	frame:Hide()

	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
	frame.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 10)
	frame.bg:SetTexture("Interface\\AddOns\\EnhanceQoL\\Assets\\background_dark.tga")
	frame.bg:SetAlpha(0.9)
	applyPanelBorder(frame)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -12)
	frame.title:SetText(L["VisibilityEditor"] or "Visibility Configurator")
	frame.title:SetFont((addon.variables and addon.variables.defaultFont) or frame.title:GetFont(), 16, "OUTLINE")

	frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 20, 13)

	local left = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	left:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -44)
	left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
	left:SetWidth(220)
	left.bg = left:CreateTexture(nil, "BACKGROUND")
	left.bg:SetAllPoints(left)
	left.bg:SetTexture("Interface\\AddOns\\EnhanceQoL\\Assets\\background_gray.tga")
	left.bg:SetAlpha(0.85)
	applyInsetBorder(left, -4)
	frame.left = left

	local configTitle = createLabel(left, L["VisibilityConfigs"] or "Configs", 12, "OUTLINE")
	configTitle:SetPoint("TOPLEFT", left, "TOPLEFT", 12, -12)

	local configScroll = CreateFrame("ScrollFrame", nil, left, "UIPanelScrollFrameTemplate")
	configScroll:SetPoint("TOPLEFT", configTitle, "BOTTOMLEFT", 0, -8)
	configScroll:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -26, 44)
	local configContent = CreateFrame("Frame", nil, configScroll)
	configContent:SetSize(1, 1)
	configScroll:SetScrollChild(configContent)
	configContent:SetWidth(configScroll:GetWidth() or 1)
	configScroll:SetScript("OnSizeChanged", function(self) configContent:SetWidth(self:GetWidth() or 1) end)

	local addConfig = createButton(left, L["VisibilityAddConfig"] or "Add Config", 96, 22)
	addConfig:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 12, 12)

	local deleteConfig = createButton(left, L["VisibilityDeleteConfig"] or "Delete Config", 96, 22)
	deleteConfig:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -12, 12)

	local right = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -44)
	right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
	right:SetWidth(360)
	right.bg = right:CreateTexture(nil, "BACKGROUND")
	right.bg:SetAllPoints(right)
	right.bg:SetTexture("Interface\\AddOns\\EnhanceQoL\\Assets\\background_gray.tga")
	right.bg:SetAlpha(0.85)
	applyInsetBorder(right, -4)
	frame.right = right

	local condTitle = createLabel(right, L["VisibilityConditions"] or "Conditions", 12, "OUTLINE")
	condTitle:SetPoint("TOPLEFT", right, "TOPLEFT", 12, -12)
	condTitle:SetTextColor(0.9, 0.9, 0.9, 1)

	local configNameLabel = createLabel(right, L["VisibilityConfigName"] or "Config name", 11, "OUTLINE")
	configNameLabel:SetPoint("TOPLEFT", condTitle, "BOTTOMLEFT", 0, -8)
	configNameLabel:SetTextColor(0.9, 0.9, 0.9, 1)

	local configNameBox = createEditBox(right, 200, 20)
	configNameBox:SetPoint("TOPLEFT", configNameLabel, "BOTTOMLEFT", -2, -4)

	local enabledCheck = createCheck(right, L["VisibilityEnabled"] or "Enabled")
	enabledCheck:SetPoint("TOPLEFT", configNameBox, "BOTTOMLEFT", -2, -6)

	local modeLabel = createLabel(right, L["VisibilityMode"] or "Mode", 11, "OUTLINE")
	modeLabel:SetPoint("TOPLEFT", enabledCheck, "BOTTOMLEFT", 2, -8)
	modeLabel:SetTextColor(0.9, 0.9, 0.9, 1)

	local modeButton = createButton(right, L["VisibilityModeShow"] or "Show when", 160, 20)
	modeButton:SetPoint("TOPLEFT", modeLabel, "BOTTOMLEFT", -2, -4)

	local fadeLabel = createLabel(right, L["VisibilityFadeAmount"] or "Fade amount", 11, "OUTLINE")
	fadeLabel:SetPoint("TOPLEFT", modeButton, "BOTTOMLEFT", 2, -10)
	fadeLabel:SetTextColor(0.9, 0.9, 0.9, 1)

	local fadeSlider = createSlider(right, 200, 0, 100, 1)
	fadeSlider:SetPoint("TOPLEFT", fadeLabel, "BOTTOMLEFT", -2, -4)

	local condScroll = CreateFrame("ScrollFrame", nil, right, "UIPanelScrollFrameTemplate")
	condScroll:SetPoint("TOPLEFT", fadeSlider, "BOTTOMLEFT", 0, -10)
	condScroll:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -26, 14)
	local condContent = CreateFrame("Frame", nil, condScroll)
	condContent:SetSize(1, 1)
	condScroll:SetScrollChild(condContent)
	condContent:SetWidth(condScroll:GetWidth() or 1)
	condScroll:SetScript("OnSizeChanged", function(self) condContent:SetWidth(self:GetWidth() or 1) end)

	local middle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	middle:SetPoint("TOPLEFT", left, "TOPRIGHT", 16, 0)
	middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", -16, 0)
	middle.bg = middle:CreateTexture(nil, "BACKGROUND")
	middle.bg:SetAllPoints(middle)
	middle.bg:SetTexture("Interface\\AddOns\\EnhanceQoL\\Assets\\background_gray.tga")
	middle.bg:SetAlpha(0.85)
	applyInsetBorder(middle, -4)
	frame.middle = middle

	local framesTitle = createLabel(middle, L["VisibilityFrames"] or "Frames", 12, "OUTLINE")
	framesTitle:SetPoint("TOPLEFT", middle, "TOPLEFT", 12, -12)

	local frameScroll = CreateFrame("ScrollFrame", nil, middle, "UIPanelScrollFrameTemplate")
	frameScroll:SetPoint("TOPLEFT", framesTitle, "BOTTOMLEFT", 0, -8)
	frameScroll:SetPoint("BOTTOMRIGHT", middle, "BOTTOMRIGHT", -26, 80)
	local frameContent = CreateFrame("Frame", nil, frameScroll)
	frameContent:SetSize(1, 1)
	frameScroll:SetScrollChild(frameContent)
	frameContent:SetWidth(frameScroll:GetWidth() or 1)
	frameScroll:SetScript("OnSizeChanged", function(self) frameContent:SetWidth(self:GetWidth() or 1) end)

	local pickButton = createButton(middle, L["VisibilityPickFrame"] or "Pick Frame", 110, 22)
	pickButton:SetPoint("BOTTOMLEFT", middle, "BOTTOMLEFT", 12, 46)

	local knownFramesButton = createButton(middle, L["VisibilityAddKnownFrames"] or "Add known frames", 140, 22)
	knownFramesButton:SetPoint("LEFT", pickButton, "RIGHT", 8, 0)

	local frameNameLabel = createLabel(middle, L["VisibilityFrameName"] or "Frame name", 11, "OUTLINE")
	frameNameLabel:SetPoint("BOTTOMLEFT", middle, "BOTTOMLEFT", 12, 20)
	frameNameLabel:SetTextColor(0.9, 0.9, 0.9, 1)

	local frameNameBox = createEditBox(middle, 150, 20)
	frameNameBox:SetPoint("LEFT", frameNameLabel, "RIGHT", 6, 0)

	local addFrame = createButton(middle, L["VisibilityAddFrame"] or "Add", 60, 20)
	addFrame:SetPoint("LEFT", frameNameBox, "RIGHT", 8, 0)

	local statusText = middle:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	statusText:SetPoint("BOTTOMLEFT", middle, "BOTTOMLEFT", 12, 6)
	statusText:SetText("")
	frame.statusText = statusText

	frame:SetScript("OnShow", function() Visibility:RefreshEditor() end)
	frame:SetScript("OnHide", function()
		saveEditorPosition(frame)
		stopPicker()
	end)

	runtime.editor = {
		frame = frame,
		configRows = {},
		frameRows = {},
		condRows = {},
		selectedConfigId = nil,
		configList = { scroll = configScroll, content = configContent },
		frameList = { scroll = frameScroll, content = frameContent },
		condList = { scroll = condScroll, content = condContent },
		addConfig = addConfig,
		deleteConfig = deleteConfig,
		pickButton = pickButton,
		addKnownFrames = knownFramesButton,
		configNameBox = configNameBox,
		frameNameBox = frameNameBox,
		addFrame = addFrame,
		enabledCheck = enabledCheck,
		modeButton = modeButton,
		fadeSlider = fadeSlider,
		statusText = statusText,
	}

	addConfig:SetScript("OnClick", function()
		local id = Visibility:CreateConfig(L["VisibilityNewConfig"] or "New Visibility Config")
		Visibility:SetSelectedConfig(id)
		Visibility:RefreshEditor()
	end)

	deleteConfig:SetScript("OnClick", function()
		local editor = getEditor()
		local configId = editor and editor.selectedConfigId
		if not configId then return end
		if not StaticPopupDialogs["EQOL_VISIBILITY_DELETE"] then
			StaticPopupDialogs["EQOL_VISIBILITY_DELETE"] = {
				text = L["VisibilityDeleteConfirm"] or "Delete this visibility config?",
				button1 = YES,
				button2 = NO,
				OnAccept = function()
					local ed = getEditor()
					local id = ed and ed.selectedConfigId
					if id then
						Visibility:DeleteConfig(id)
						Visibility:RequestUpdate()
						Visibility:RefreshEditor()
					end
				end,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
			}
		end
		StaticPopup_Show("EQOL_VISIBILITY_DELETE")
	end)

	pickButton:SetScript("OnClick", function()
		local editor = getEditor()
		local configId = editor and editor.selectedConfigId
		if not configId then
			configId = Visibility:CreateConfig(L["VisibilityNewConfig"] or "New Visibility Config")
			Visibility:SetSelectedConfig(configId)
			Visibility:RefreshEditor()
		end
		startPicker(editor, configId)
	end)

	knownFramesButton:SetScript("OnClick", function(self)
		local editor = getEditor()
		local configId = editor and editor.selectedConfigId
		showKnownFramesMenu(self)
	end)

	addFrame:SetScript("OnClick", function()
		local editor = getEditor()
		local configId = editor and editor.selectedConfigId
		if not configId then return end
		local name = editor.frameNameBox:GetText()
		editor.frameNameBox:SetText("")
		editor.frameNameBox:ClearFocus()
		if not name or name == "" then return end
		local ok, reason = Visibility:AddFrame(configId, name)
		if ok then
			setStatus(editor, (L["VisibilityFrameAdded"] or "Frame added.") .. " " .. name, 0.6, 0.9, 0.6)
		else
			local msg = L["VisibilityFrameInvalid"] or "Invalid frame."
			if reason == "assigned" then
				local root = ensureRoot()
				local ownerId = root and root.frameIndex and root.frameIndex[name]
				local owner = ownerId and root.configs and root.configs[ownerId]
				local ownerName = owner and owner.name or tostring(ownerId or "?")
				msg = (L["VisibilityFrameAssigned"] or "Frame already assigned to:") .. " " .. ownerName
			elseif reason == "exists" then
				msg = L["VisibilityFrameExists"] or "Frame already in this config."
			end
			setStatus(editor, msg, 1, 0.5, 0.3)
		end
		Visibility:RefreshEditor()
	end)

	frameNameBox:SetScript("OnEnterPressed", function() addFrame:Click() end)

	configNameBox:SetScript("OnEnterPressed", function(self)
		local editor = getEditor()
		local configId = editor and editor.selectedConfigId
		local cfg = configId and Visibility:GetConfig(configId)
		if cfg then
			local text = self:GetText()
			if text and text ~= "" then cfg.name = text end
			Visibility:RefreshEditor()
		end
		self:ClearFocus()
	end)
	configNameBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		Visibility:RefreshEditor()
	end)

	enabledCheck:SetScript("OnClick", function(self)
		local editor = getEditor()
		local configId = editor and editor.selectedConfigId
		local cfg = configId and Visibility:GetConfig(configId)
		if cfg then
			cfg.enabled = self:GetChecked() and true or false
			Visibility:RequestUpdate()
			Visibility:RefreshEditor()
		end
	end)

	modeButton:SetScript("OnClick", function(self)
		local editor = getEditor()
		local configId = editor and editor.selectedConfigId
		local cfg = configId and Visibility:GetConfig(configId)
		if not cfg then return end
		showModeMenu(self, cfg.mode, function(mode)
			cfg.mode = mode
			Visibility:RequestUpdate()
			Visibility:RefreshEditor()
		end)
	end)

	fadeSlider:SetScript("OnValueChanged", function(self, value)
		local editor = getEditor()
		local configId = editor and editor.selectedConfigId
		local cfg = configId and Visibility:GetConfig(configId)
		if not cfg then return end
		local pct = tonumber(value) or 0
		if pct < 0 then pct = 0 end
		if pct > 100 then pct = 100 end
		cfg.fadeAlpha = 1 - (pct / 100)
		if self.Text then self.Text:SetText(string.format("%d%%", pct)) end
		Visibility:RequestUpdate()
	end)

	return frame
end

function Visibility:RefreshEditor()
	local editor = getEditor()
	if not editor then return end
	local root = ensureRoot()
	if not root then return end

	local selected = root.selectedConfig
	if not selected or not root.configs[selected] then
		selected = root.order and root.order[1]
		if selected and root.configs[selected] then root.selectedConfig = selected end
	end
	editor.selectedConfigId = selected

	-- Config list
	local rows = editor.configRows
	local content = editor.configList.content
	local rowHeight = 28
	local index = 0
	for _, configId in ipairs(root.order or {}) do
		local cfg = root.configs and root.configs[configId]
		if cfg then
			index = index + 1
			local row = rows[index]
			if not row then
				row = createRowButton(content, rowHeight)
				row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				row.text:SetPoint("LEFT", row, "LEFT", 8, 0)
				row:SetScript("OnClick", function(self)
					Visibility:SetSelectedConfig(self.configId)
					Visibility:RefreshEditor()
				end)
				rows[index] = row
			end
			row.configId = configId
			row.text:SetText(cfg.name or ("Config " .. tostring(configId)))
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((index - 1) * (rowHeight + 2)))
			row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -((index - 1) * (rowHeight + 2)))
			if configId == selected then
				row.bg:SetColorTexture(0.2, 0.4, 0.6, 0.35)
			else
				row.bg:SetColorTexture(0, 0, 0, 0.2)
			end
			row:Show()
		end
	end
	for i = index + 1, #rows do
		rows[i]:Hide()
	end
	content:SetHeight(math.max(1, index * (rowHeight + 2)))

	-- Inspector fields
	local cfg = selected and root.configs and root.configs[selected]
	if cfg then
		if editor.configNameBox then
			editor.configNameBox:SetText(cfg.name or "")
			editor.configNameBox:Enable()
		end
		if editor.frameNameBox then
			editor.frameNameBox:Enable()
			editor.addFrame:Enable()
			editor.pickButton:Enable()
		end
		if editor.addKnownFrames then editor.addKnownFrames:Enable() end
		editor.enabledCheck:SetChecked(cfg.enabled == true)
		editor.enabledCheck:Enable()
		local modeLabel = cfg.mode == Helper.MODES.HIDE and (L["VisibilityModeHide"] or "Hide when") or (L["VisibilityModeShow"] or "Show when")
		editor.modeButton:SetText(modeLabel)
		editor.modeButton:Enable()
		local fadePct = 100 - math.floor((cfg.fadeAlpha or 0) * 100 + 0.5)
		if fadePct < 0 then fadePct = 0 end
		if fadePct > 100 then fadePct = 100 end
		editor.fadeSlider:SetValue(fadePct)
		if editor.fadeSlider.Text then editor.fadeSlider.Text:SetText(string.format("%d%%", fadePct)) end
		editor.fadeSlider:Enable()
	else
		if editor.configNameBox then
			editor.configNameBox:SetText("")
			editor.configNameBox:Disable()
		end
		if editor.frameNameBox then
			editor.frameNameBox:SetText("")
			editor.frameNameBox:Disable()
			editor.addFrame:Disable()
			editor.pickButton:Enable()
		end
		if editor.addKnownFrames then editor.addKnownFrames:Enable() end
		editor.enabledCheck:SetChecked(false)
		editor.enabledCheck:Disable()
		editor.modeButton:SetText(L["VisibilityModeShow"] or "Show when")
		editor.modeButton:Disable()
		editor.fadeSlider:SetValue(0)
		editor.fadeSlider:Disable()
	end

	if editor.deleteConfig then
		if cfg then
			editor.deleteConfig:Enable()
		else
			editor.deleteConfig:Disable()
		end
	end

	-- Frame list
	local frameRows = editor.frameRows
	local fContent = editor.frameList.content
	local fIndex = 0
	if cfg and type(cfg.frames) == "table" then
		for _, name in ipairs(cfg.frames) do
			fIndex = fIndex + 1
			local row = frameRows[fIndex]
			if not row then
				row = createRowButton(fContent, rowHeight)
				row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				row.text:SetPoint("LEFT", row, "LEFT", 8, 0)
				row.remove = CreateFrame("Button", nil, row)
				row.remove:SetSize(16, 16)
				row.remove:SetPoint("RIGHT", row, "RIGHT", -6, 0)
				row.remove.icon = row.remove:CreateTexture(nil, "OVERLAY")
				row.remove.icon:SetAllPoints()
				row.remove.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
				row.remove:SetScript("OnClick", function(self)
					local parentRow = self:GetParent()
					local configId = editor.selectedConfigId
					if configId and parentRow and parentRow.frameName then
						Visibility:RemoveFrame(configId, parentRow.frameName)
						Visibility:RefreshEditor()
					end
				end)
				frameRows[fIndex] = row
			end
			row.frameName = name
			row.text:SetText(name)
			if resolveFrameByName(name) then
				row.text:SetTextColor(1, 1, 1, 1)
			else
				row.text:SetTextColor(0.7, 0.7, 0.7, 1)
			end
			row.remove:Show()
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", fContent, "TOPLEFT", 0, -((fIndex - 1) * (rowHeight + 2)))
			row:SetPoint("TOPRIGHT", fContent, "TOPRIGHT", 0, -((fIndex - 1) * (rowHeight + 2)))
			row:Show()
		end
	end
	for i = fIndex + 1, #frameRows do
		frameRows[i]:Hide()
	end
	fContent:SetHeight(math.max(1, fIndex * (rowHeight + 2)))

	-- Conditions list
	local condRows = editor.condRows
	local cContent = editor.condList.content
	local list = {}
	if cfg then
		cfg.rules = Helper.NormalizeRules(cfg.rules)
		buildRuleRows(cfg.rules, 0, list, true, nil)
	end
	local cIndex = 0
	local rowH = 24
	for _, entry in ipairs(list) do
		cIndex = cIndex + 1
		local row = condRows[cIndex]
		if not row then
			row = CreateFrame("Frame", nil, cContent)
			row:SetHeight(rowH)

			row.notCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
			row.notCheck:SetSize(20, 20)
			row.notCheck.Text:SetText("NOT")
			row.notCheck.Text:SetTextColor(1, 1, 1, 1)

			row.labelButton = createButton(row, "", 140, 18)
			row.labelButton:SetHeight(18)

			row.groupLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			row.groupLabel:SetTextColor(0.9, 0.9, 0.9, 1)

			row.joinButton = createButton(row, "AND", 48, 18)
			row.joinButton:SetHeight(18)

			row.addButton = createButton(row, "+", 24, 18)
			row.addButton:SetHeight(18)

			row.removeButton = CreateFrame("Button", nil, row)
			row.removeButton:SetSize(16, 16)
			row.removeButton.icon = row.removeButton:CreateTexture(nil, "OVERLAY")
			row.removeButton.icon:SetAllPoints()
			row.removeButton.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")

			condRows[cIndex] = row
		end

		local node = entry.node
		local parent = entry.parent
		local depth = entry.depth or 0
		local indent = depth * 14

		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", cContent, "TOPLEFT", 0, -((cIndex - 1) * (rowH + 2)))
		row:SetPoint("TOPRIGHT", cContent, "TOPRIGHT", 0, -((cIndex - 1) * (rowH + 2)))
		row:Show()

		row.notCheck:ClearAllPoints()
		row.notCheck:SetPoint("LEFT", row, "LEFT", 4 + indent, 0)
		row.notCheck:SetChecked(node.negate == true)
		row.notCheck:SetScript("OnClick", function(self)
			node.negate = self:GetChecked() and true or false
			Visibility:RequestUpdate()
			Visibility:RefreshEditor()
		end)

		row.labelButton:Hide()
		row.groupLabel:Hide()
		row.joinButton:Hide()
		row.addButton:Hide()
		row.removeButton:Hide()

		if entry.kind == "group" then
			row.groupLabel:SetText(L["VisibilityGroup"] or "Group")
			row.groupLabel:ClearAllPoints()
			row.groupLabel:SetPoint("LEFT", row.notCheck.Text or row.notCheck, "RIGHT", 8, 0)
			row.groupLabel:Show()

			row.joinButton:SetText(node.op or "AND")
			row.joinButton:ClearAllPoints()
			row.joinButton:SetPoint("LEFT", row.groupLabel, "RIGHT", 8, 0)
			row.joinButton:Show()
			row.joinButton:SetScript("OnClick", function(self)
				showJoinMenu(self, node.op, function(value)
					node.op = value
					Visibility:RequestUpdate()
					Visibility:RefreshEditor()
				end)
			end)

			row.addButton:ClearAllPoints()
			row.addButton:SetPoint("RIGHT", row, "RIGHT", entry.isRoot and -6 or -26, 0)
			row.addButton:Show()
			local canAddGroup = (entry.depth or 0) < MAX_GROUP_DEPTH
			row.addButton:SetScript("OnClick", function(self)
				showAddMenu(self, canAddGroup, function()
					node.children = node.children or {}
					node.children[#node.children + 1] = { op = "AND", children = {} }
					Visibility:RequestUpdate()
					Visibility:RefreshEditor()
				end, function(key)
					if hasConditionInGroup(node, key) then
						setStatus(editor, L["VisibilityDuplicateCondition"] or "Condition already exists in this group.", 1, 0.5, 0.3)
						return
					end
					node.children = node.children or {}
					node.children[#node.children + 1] = { key = key }
					Visibility:RequestUpdate()
					Visibility:RefreshEditor()
				end)
			end)

			if not entry.isRoot then
				row.removeButton:ClearAllPoints()
				row.removeButton:SetPoint("RIGHT", row, "RIGHT", -6, 0)
				row.removeButton:Show()
				row.removeButton:SetScript("OnClick", function()
					if parent and parent.children then
						for i, child in ipairs(parent.children) do
							if child == node then
								table.remove(parent.children, i)
								break
							end
						end
					end
					Visibility:RequestUpdate()
					Visibility:RefreshEditor()
				end)
			end
		else
			local label = Helper.GetRuleLabel(node.key)
			row.labelButton:SetText(label)
			row.labelButton:ClearAllPoints()
			row.labelButton:SetPoint("LEFT", row.notCheck.Text or row.notCheck, "RIGHT", 8, 0)
			row.labelButton:Show()
			row.labelButton:SetScript("OnClick", function(self)
				showConditionMenu(self, function(key)
					if node.key == key then return end
					if parent and hasConditionInGroup(parent, key, node) then
						setStatus(editor, L["VisibilityDuplicateCondition"] or "Condition already exists in this group.", 1, 0.5, 0.3)
						return
					end
					node.key = key
					Visibility:RequestUpdate()
					Visibility:RefreshEditor()
				end)
			end)

			row.removeButton:ClearAllPoints()
			row.removeButton:SetPoint("RIGHT", row, "RIGHT", -6, 0)
			row.removeButton:Show()
			row.removeButton:SetScript("OnClick", function()
				local parent = cfg.rules
				local function removeNode(group, target)
					if not group or not group.children then return false end
					for i, child in ipairs(group.children) do
						if child == target then
							table.remove(group.children, i)
							return true
						elseif child.op and removeNode(child, target) then
							return true
						end
					end
					return false
				end
				removeNode(parent, node)
				Visibility:RequestUpdate()
				Visibility:RefreshEditor()
			end)
		end
	end
	for i = cIndex + 1, #condRows do
		condRows[i]:Hide()
	end
	cContent:SetHeight(math.max(1, cIndex * (rowH + 2)))
end

function Visibility:OpenEditor()
	local frame = ensureEditor()
	if not frame then return end
	frame:Show()
	Visibility:RefreshEditor()
end

function Visibility:CloseEditor()
	local editor = getEditor()
	if editor and editor.frame then editor.frame:Hide() end
end

function Visibility:ToggleEditor()
	local editor = getEditor()
	if editor and editor.frame and editor.frame:IsShown() then
		self:CloseEditor()
	else
		self:OpenEditor()
	end
end

function Visibility:IsEditorOpen()
	local editor = getEditor()
	return editor and editor.frame and editor.frame:IsShown() or false
end
