local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Mouse")

-- Hotpath locals & constants
local GetCursorPosition = GetCursorPosition
local IsMouseButtonDown = IsMouseButtonDown
local UIParent = UIParent
local UnitAffectingCombat = UnitAffectingCombat
local UnitClass = UnitClass
local GetClassColor = GetClassColor
local RING_FRAME_NAME = addonName .. "_MouseRingFrame"
local TEX_MOUSE = "Interface\\AddOns\\" .. addonName .. "\\Assets\\Mouse\\Mouse.tga"
local TEX_DOT = "Interface\\AddOns\\" .. addonName .. "\\Assets\\Mouse\\Dot.tga"
addon.Mouse.variables.TEXT_DOT = TEX_DOT
local TEX_TRAIL = "Interface\\AddOns\\" .. addonName .. "\\Assets\\Mouse\\MouseTrail.tga"

local MaxActuationPoint = 1 -- Minimaler Bewegungsabstand für Trail-Elemente
local MaxActuationPointSq = MaxActuationPoint * MaxActuationPoint
local duration = 0.3 -- Lebensdauer der Trail-Elemente in Sekunden
local Density = 0.02 -- Zeitdichte für neue Elemente
local ElementCap = 28 -- Maximale Anzahl von Trail-Elementen
local PastCursorX, PastCursorY, PresentCursorX, PresentCursorY = nil, nil, nil, nil

local trailPool = {}
local activeCount = 0
local playerClass = UnitClass and select(2, UnitClass("player")) or nil
local classR, classG, classB
if playerClass and GetClassColor then
	classR, classG, classB = GetClassColor(playerClass)
end
local currentPreset = nil
local lastTrailWanted = false
local lastRingCombat = nil
local ringStyleDirty = true

local trailPresets = {
	[1] = { -- LOW
		MaxActuationPoint = 1.0,
		duration = 0.4,
		Density = 0.025,
		ElementCap = 20,
	},
	[2] = { -- MEDIUM
		MaxActuationPoint = 0.7,
		duration = 0.5,
		Density = 0.02,
		ElementCap = 40,
	},
	[3] = { -- HIGH (Sweet Spot)
		MaxActuationPoint = 0.5,
		duration = 0.7,
		Density = 0.012,
		ElementCap = 80,
	},
	[4] = { -- ULTRA
		MaxActuationPoint = 0.3,
		duration = 0.7,
		Density = 0.007,
		ElementCap = 120,
	},
	[5] = { -- ULTRA HIGH
		MaxActuationPoint = 0.2,
		duration = 0.8,
		Density = 0.005,
		ElementCap = 150,
	},
}

local function createTrailElement()
	local tex = UIParent:CreateTexture(nil)
	tex:SetTexture(TEX_TRAIL)
	tex:SetBlendMode("ADD")
	tex:SetSize(35, 35)

	local ag = tex:CreateAnimationGroup()
	ag:SetScript("OnFinished", function(self)
		local t = self:GetParent()
		t:Hide()
		trailPool[#trailPool + 1] = t
		activeCount = activeCount - 1
	end)
	local fade = ag:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0)

	tex.anim = ag
	tex.fade = fade

	return tex
end

local function ensureTrailPool()
	local total = activeCount + #trailPool
	if total >= ElementCap then return end
	for _ = 1, (ElementCap - total) do
		local tex = createTrailElement()
		tex:Hide()
		trailPool[#trailPool + 1] = tex
	end
end

local function applyPreset(presetName)
	local preset = trailPresets[presetName]
	if not preset then return end
	MaxActuationPoint = preset.MaxActuationPoint
	MaxActuationPointSq = MaxActuationPoint * MaxActuationPoint
	duration = preset.duration
	Density = preset.Density
	ElementCap = preset.ElementCap
	currentPreset = presetName

	if addon.db and addon.db["mouseTrailEnabled"] then ensureTrailPool() end
end
addon.Mouse.functions.applyPreset = applyPreset

local timeAccumulator = 0

local function isRingWanted(db, inCombat, rightClickActive)
	if not db or not db["mouseRingEnabled"] then return false end
	if db["mouseRingOnlyInCombat"] and not inCombat then return false end
	if db["mouseRingOnlyOnRightClick"] and not rightClickActive then return false end
	return true
end

local function getTrailColor()
	if addon.db["mouseTrailUseClassColor"] then
		if not classR then
			local class = playerClass or (UnitClass and select(2, UnitClass("player")))
			if class then playerClass = class end
			if class and GetClassColor then
				classR, classG, classB = GetClassColor(class)
			end
		end
		if classR then return classR, classG, classB, 1 end
		return 1, 1, 1, 1
	end
	local c = addon.db["mouseTrailColor"]
	if c then return c.r, c.g, c.b, c.a or 1 end
	return 1, 1, 1, 1
end

local function getRingColor()
	if addon.db["mouseRingUseClassColor"] then
		if not classR then
			local class = playerClass or (UnitClass and select(2, UnitClass("player")))
			if class then playerClass = class end
			if class and GetClassColor then
				classR, classG, classB = GetClassColor(class)
			end
		end
		if classR then return classR, classG, classB, 1 end
		return 1, 1, 1, 1
	end
	local c = addon.db["mouseRingColor"]
	if c then return c.r, c.g, c.b, c.a or 1 end
	return 1, 1, 1, 1
end

local function getCombatOverrideColor()
	local c = addon.db["mouseRingCombatOverrideColor"]
	if c then return c.r, c.g, c.b, c.a or 1 end
	return 1, 0.2, 0.2, 1
end

local function getCombatOverlayColor()
	local c = addon.db["mouseRingCombatOverlayColor"]
	if c then return c.r, c.g, c.b, c.a or 1 end
	return 1, 0.2, 0.2, 0.6
end

local function ensureCombatOverlay(frame)
	local overlay = frame.combatOverlay
	if overlay then return overlay end
	overlay = frame:CreateTexture(nil, "BACKGROUND")
	overlay:SetTexture(TEX_MOUSE)
	overlay:SetBlendMode("ADD")
	overlay:SetPoint("CENTER", frame, "CENTER", 0, 0)
	overlay:SetDrawLayer("BACKGROUND", -1)
	frame.combatOverlay = overlay
	return overlay
end

local function markRingStyleDirty() ringStyleDirty = true end
addon.Mouse.functions.markRingStyleDirty = markRingStyleDirty

local function applyRingStyle(inCombat)
	if not addon.db or not addon.mousePointer or not addon.mousePointer.texture1 then return end
	local db = addon.db
	local ringFrame = addon.mousePointer
	local combatActive = inCombat and true or false

	local size = db["mouseRingSize"] or 70
	local r, g, b, a = getRingColor()

	if combatActive and db["mouseRingCombatOverride"] then
		size = db["mouseRingCombatOverrideSize"] or size
		r, g, b, a = getCombatOverrideColor()
	end

	ringFrame.texture1:SetSize(size, size)
	ringFrame.texture1:SetVertexColor(r, g, b, a)

	if combatActive and db["mouseRingCombatOverlay"] then
		local overlay = ensureCombatOverlay(ringFrame)
		local overlaySize = db["mouseRingCombatOverlaySize"] or size
		local orr, org, orb, ora = getCombatOverlayColor()
		overlay:SetSize(overlaySize, overlaySize)
		overlay:SetVertexColor(orr, org, orb, ora)
		overlay:Show()
	elseif ringFrame.combatOverlay then
		ringFrame.combatOverlay:Hide()
	end
end
addon.Mouse.functions.applyRingStyle = applyRingStyle

local function refreshRingStyle(inCombat)
	ringStyleDirty = true
	if not addon.mousePointer then return end
	if inCombat == nil and UnitAffectingCombat then inCombat = UnitAffectingCombat("player") and true or false end
	applyRingStyle(inCombat)
	ringStyleDirty = false
	lastRingCombat = inCombat and true or false
end
addon.Mouse.functions.refreshRingStyle = refreshRingStyle

local function UpdateMouseTrail(delta, cursorX, cursorY, effectiveScale)
	-- Delta = Zeit seit letztem Frame

	-- Ersten Maus-Frame sauber initialisieren
	if PresentCursorX == nil then
		PresentCursorX, PresentCursorY = cursorX, cursorY
		return -- Startposition gesetzt
	end

	-- Zeit hochzählen
	timeAccumulator = timeAccumulator + delta

	-- Aktuelle Mausposition holen, Distanz ermitteln
	PastCursorX, PastCursorY = PresentCursorX, PresentCursorY
	PresentCursorX, PresentCursorY = cursorX, cursorY

	local dx = PresentCursorX - PastCursorX
	local dy = PresentCursorY - PastCursorY
	local distanceSq = dx * dx + dy * dy

	-- Neues Trail-Element anlegen?
	if timeAccumulator >= Density and distanceSq >= MaxActuationPointSq then
		timeAccumulator = timeAccumulator - Density

		if activeCount < ElementCap and #trailPool > 0 then
			local element = trailPool[#trailPool]
			trailPool[#trailPool] = nil
			activeCount = activeCount + 1

			element:SetPoint("CENTER", UIParent, "BOTTOMLEFT", PresentCursorX / effectiveScale, PresentCursorY / effectiveScale)

			local r, g, b, a = getTrailColor()
			element:SetVertexColor(r, g, b, a)

			element.fade:SetDuration(duration)
			element.anim:Stop()
			element.anim:Play()
			element:Show()
		end
	end
end

local function createMouseRing(inCombat)
	if addon.mousePointer then
		addon.mousePointer:Show()
		if addon.Mouse.functions.refreshRingStyle then addon.Mouse.functions.refreshRingStyle(inCombat) end
		return
	end

	local imageFrame = _G[RING_FRAME_NAME]
	if not imageFrame then
		imageFrame = CreateFrame("Frame", RING_FRAME_NAME, UIParent, "BackdropTemplate")
		imageFrame:SetSize(120, 120)
		imageFrame:SetBackdropColor(0, 0, 0, 0)
		imageFrame:SetFrameStrata("TOOLTIP")
	end

	local texture1 = imageFrame.texture1
	if not texture1 then
		texture1 = imageFrame:CreateTexture(nil, "BACKGROUND")
		texture1:SetTexture(TEX_MOUSE)
		texture1:SetPoint("CENTER", imageFrame, "CENTER", 0, 0)
		imageFrame.texture1 = texture1
	end

	if addon.db["mouseRingHideDot"] then
		if imageFrame.dot then imageFrame.dot:Hide() end
	else
		local dot = imageFrame.dot
		if not dot then
			dot = imageFrame:CreateTexture(nil, "BACKGROUND")
			dot:SetTexture(TEX_DOT)
			dot:SetSize(10, 10)
			dot:SetPoint("CENTER", imageFrame, "CENTER", 0, 0)
			imageFrame.dot = dot
		end
		dot:Show()
	end

	addon.mousePointer = imageFrame
	if addon.Mouse.functions.refreshRingStyle then addon.Mouse.functions.refreshRingStyle(inCombat) end
	imageFrame:Show()
end
addon.Mouse.functions.createMouseRing = createMouseRing

local function removeMouseRing()
	if addon.mousePointer then addon.mousePointer:Hide() end
end
addon.Mouse.functions.removeMouseRing = removeMouseRing

local function updateRunnerState()
	if not addon.mouseTrailRunner then return end
	local db = addon.db
	local shouldRun = db and (db["mouseRingEnabled"] or db["mouseTrailEnabled"])
	if shouldRun then
		if addon.mouseTrailRunner:GetScript("OnUpdate") == nil then addon.mouseTrailRunner:SetScript("OnUpdate", addon.Mouse.functions.runMouseRunner) end
	elseif addon.mouseTrailRunner:GetScript("OnUpdate") ~= nil then
		addon.mouseTrailRunner:SetScript("OnUpdate", nil)
	end
end
addon.Mouse.functions.updateRunnerState = updateRunnerState

local function refreshRingVisibility()
	local db = addon.db
	if not db then return false end
	local ringOnly = db["mouseRingOnlyInCombat"]
	local combatOverride = db["mouseRingCombatOverride"]
	local combatOverlay = db["mouseRingCombatOverlay"]
	local inCombat = false
	if ringOnly or combatOverride or combatOverlay then inCombat = UnitAffectingCombat and UnitAffectingCombat("player") and true or false end
	local rightClickActive = db["mouseRingOnlyOnRightClick"] and IsMouseButtonDown and IsMouseButtonDown("RightButton")
	local ringWanted = isRingWanted(db, inCombat, rightClickActive)

	if ringWanted then
		if not addon.mousePointer then createMouseRing(inCombat) end
		if addon.mousePointer and not addon.mousePointer:IsShown() then addon.mousePointer:Show() end
		if ringStyleDirty or lastRingCombat ~= inCombat then
			applyRingStyle(inCombat)
			ringStyleDirty = false
			lastRingCombat = inCombat
		end
	elseif addon.mousePointer and addon.mousePointer:IsShown() then
		addon.mousePointer:Hide()
	end

	return ringWanted
end
addon.Mouse.functions.refreshRingVisibility = refreshRingVisibility

function addon.Mouse.functions.InitState()
	local db = addon.db
	if not db then return end
	refreshRingVisibility()
	if db["mouseTrailEnabled"] then applyPreset(db["mouseTrailDensity"]) end
	updateRunnerState()
end

-- Manage visibility of the ring based on combat state
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- enter combat
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED") -- leave combat
eventFrame:SetScript("OnEvent", function()
	if not addon.db then return end
	refreshRingVisibility()
end)

-- Shared runner for ring + trail updates
if not addon.mouseTrailRunner then
	local runner = CreateFrame("Frame")
	addon.Mouse.functions.runMouseRunner = function(self, delta)
		local db = addon.db
		if not db then
			self:SetScript("OnUpdate", nil)
			return
		end
		if not db["mouseRingEnabled"] and not db["mouseTrailEnabled"] then
			self:SetScript("OnUpdate", nil)
			return
		end
		local ringOnly = db["mouseRingOnlyInCombat"]
		local trailOnly = db["mouseTrailOnlyInCombat"]
		local rightClickOnly = db["mouseRingOnlyOnRightClick"]
		local combatOverride = db["mouseRingCombatOverride"]
		local combatOverlay = db["mouseRingCombatOverlay"]
		local inCombat = false
		if ringOnly or trailOnly or combatOverride or combatOverlay then inCombat = UnitAffectingCombat and UnitAffectingCombat("player") and true or false end
		local rightClickActive = rightClickOnly and IsMouseButtonDown and IsMouseButtonDown("RightButton")
		local ringWanted = isRingWanted(db, inCombat, rightClickActive)
		local trailWanted = db["mouseTrailEnabled"] and (not trailOnly or inCombat)
		if trailWanted and currentPreset ~= db["mouseTrailDensity"] then applyPreset(db["mouseTrailDensity"]) end
		if trailWanted and not lastTrailWanted then
			ensureTrailPool()
			PresentCursorX, PresentCursorY = nil, nil
			timeAccumulator = 0
		end
		lastTrailWanted = trailWanted

		if ringWanted then
			if not addon.mousePointer then createMouseRing(inCombat) end
			if addon.mousePointer and not addon.mousePointer:IsShown() then addon.mousePointer:Show() end
			if ringStyleDirty or lastRingCombat ~= inCombat then
				applyRingStyle(inCombat)
				ringStyleDirty = false
				lastRingCombat = inCombat
			end
		elseif addon.mousePointer and addon.mousePointer:IsShown() then
			addon.mousePointer:Hide()
		end

		if not ringWanted and not trailWanted then return end
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		if ringWanted and addon.mousePointer and addon.mousePointer:IsShown() then
			addon.mousePointer:ClearAllPoints()
			addon.mousePointer:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
		end
		if trailWanted then UpdateMouseTrail(delta, x, y, scale) end
	end
	addon.mouseTrailRunner = runner
	updateRunnerState()
end
