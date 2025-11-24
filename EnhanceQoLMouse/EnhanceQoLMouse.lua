local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Mouse")

local AceGUI = addon.AceGUI

-- Hotpath locals & constants
local GetCursorPosition = GetCursorPosition
local TEX_MOUSE = "Interface\\AddOns\\" .. addonName .. "\\Icons\\Mouse.tga"
local TEX_DOT = "Interface\\AddOns\\" .. addonName .. "\\Icons\\Dot.tga"
local TEX_TRAIL = "Interface\\AddOns\\" .. addonName .. "\\Icons\\MouseTrail.tga"

local MaxActuationPoint = 1 -- Minimaler Bewegungsabstand für Trail-Elemente
local MaxActuationPointSq = MaxActuationPoint * MaxActuationPoint
local duration = 0.3 -- Lebensdauer der Trail-Elemente in Sekunden
local Density = 0.02 -- Zeitdichte für neue Elemente
local ElementCap = 28 -- Maximale Anzahl von Trail-Elementen
local PastCursorX, PastCursorY, PresentCursorX, PresentCursorY = nil, nil, nil, nil

local trailPool = {}
local activeCount = 0

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

local function applyPreset(presetName)
	local preset = trailPresets[presetName]
	if not preset then return end
	MaxActuationPoint = preset.MaxActuationPoint
	MaxActuationPointSq = MaxActuationPoint * MaxActuationPoint
	duration = preset.duration
	Density = preset.Density
	ElementCap = preset.ElementCap

	-- Reuse existing pool; create or trim to match ElementCap
	local poolSize = #trailPool
	if poolSize < ElementCap then
		for i = poolSize + 1, ElementCap do
			local tex = createTrailElement()
			tex:Hide()
			trailPool[i] = tex
		end
	elseif poolSize > ElementCap then
		for i = poolSize, ElementCap + 1, -1 do
			trailPool[i] = nil
		end
	end
end
addon.Mouse.functions.applyPreset = applyPreset

local timeAccumulator = 0

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
		timeAccumulator = 0

		if activeCount < ElementCap and #trailPool > 0 then
			local element = trailPool[#trailPool]
			trailPool[#trailPool] = nil
			activeCount = activeCount + 1

			element:SetPoint("CENTER", UIParent, "BOTTOMLEFT", PresentCursorX / effectiveScale, PresentCursorY / effectiveScale)

			local function getTrailColor()
				if addon.db["mouseTrailUseClassColor"] then
					local _, class = UnitClass("player")
					local r, g, b = GetClassColor(class)
					return r or 1, g or 1, b or 1, 1
				end
				local c = addon.db["mouseTrailColor"]
				if c then return c.r, c.g, c.b, c.a or 1 end
				return 1, 1, 1, 1
			end
			local r, g, b, a = getTrailColor()
			element:SetVertexColor(r, g, b, a)

			element:SetSize(35, 35)
			element.fade:SetDuration(duration)
			element.anim:Play()
			element:Show()
		end
	end
end

local function createMouseRing()
	if not addon.mousePointer then
		local imageFrame = CreateFrame("Frame", "ImageTooltipFrame", UIParent, "BackdropTemplate")
		imageFrame:SetSize(120, 120)
		imageFrame:SetBackdropColor(0, 0, 0, 0)
		imageFrame:SetFrameStrata("TOOLTIP")

		imageFrame:SetScript("OnUpdate", function(self, delta)
			local x, y = GetCursorPosition()
			local scale = UIParent:GetEffectiveScale()
			self:ClearAllPoints()
			self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)

			-- Ring update only handles its own position. Trail is updated by a dedicated runner.
		end)

		local texture1 = imageFrame:CreateTexture(nil, "BACKGROUND")
		texture1:SetTexture(TEX_MOUSE)
		texture1:SetSize(addon.db["mouseRingSize"], addon.db["mouseRingSize"])
		texture1:SetPoint("CENTER", imageFrame, "CENTER", 0, 0)
		local function getRingColor()
			if addon.db["mouseRingUseClassColor"] then
				local _, class = UnitClass("player")
				local r, g, b = GetClassColor(class)
				return r or 1, g or 1, b or 1, 1
			end
			local c = addon.db["mouseRingColor"]
			if c then return c.r, c.g, c.b, c.a or 1 end
			return 1, 1, 1, 1
		end
		local rr, rg, rb, ra = getRingColor()
		texture1:SetVertexColor(rr, rg, rb, ra)

		local texture2
		if not addon.db["mouseRingHideDot"] then
			texture2 = imageFrame:CreateTexture(nil, "BACKGROUND")
			texture2:SetTexture(TEX_DOT)
			texture2:SetSize(10, 10)
			texture2:SetPoint("CENTER", imageFrame, "CENTER", 0, 0)
		end

		imageFrame:Show()
		addon.mousePointer = imageFrame
		addon.mousePointer.texture1 = texture1
		addon.mousePointer.dot = texture2
	end
end
addon.Mouse.functions.createMouseRing = createMouseRing

local function removeMouseRing()
	if addon.mousePointer then
		addon.mousePointer:SetScript("OnUpdate", nil)
		addon.mousePointer:Hide()
		addon.mousePointer = nil
	end
end
addon.Mouse.functions.removeMouseRing = removeMouseRing

addon.variables.statusTable.groups["mouse"] = true
-- Place Mouse under UI & Input
addon.functions.addToTree("ui", {
	value = "mouse",
	text = MOUSE_LABEL,
})

function addon.Mouse.functions.treeCallback(container, group)
	container:ReleaseChildren() -- Entfernt vorherige Inhalte
	-- Prüfen, welche Gruppe ausgewählt wurde
	if group == "mouse" then Settings.OpenToCategory(addon.SettingsLayout.mouseCategory:GetID()) end
end

if addon.db["mouseRingEnabled"] then createMouseRing() end

applyPreset(addon.db["mouseTrailDensity"])

-- Manage visibility of the ring based on combat state
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- enter combat
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED") -- leave combat
eventFrame:SetScript("OnEvent", function()
	if not addon.db["mouseRingEnabled"] then return end
	if addon.db["mouseRingOnlyInCombat"] then
		if UnitAffectingCombat("player") then
			if not addon.mousePointer then createMouseRing() end
			if addon.mousePointer then addon.mousePointer:Show() end
		else
			if addon.mousePointer then addon.mousePointer:Hide() end
		end
	else
		if not addon.mousePointer then createMouseRing() end
		if addon.mousePointer then addon.mousePointer:Show() end
	end
end)

-- Dedicated trail update runner (independent from ring visibility)
if not addon.mouseTrailRunner then
	local runner = CreateFrame("Frame")
	runner:SetScript("OnUpdate", function(self, delta)
		if not addon.db["mouseTrailEnabled"] then return end
		if addon.db["mouseTrailOnlyInCombat"] and not UnitAffectingCombat("player") then return end
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		UpdateMouseTrail(delta, x, y, scale)
	end)
	addon.mouseTrailRunner = runner
end
