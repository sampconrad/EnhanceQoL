local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local ResourceBars = addon.Aura and addon.Aura.ResourceBars
if not ResourceBars then return end

function ResourceBars.ShouldHideInClientScene() return addon and addon.db and addon.db.resourceBarsHideClientScene == true end

function ResourceBars.ApplyClientSceneAlphaToFrame(frame, forceHide)
	if not (frame and frame.SetAlpha) then return end
	if forceHide then
		frame._rbClientSceneAlphaHidden = true
		if frame.GetAlpha and frame:GetAlpha() ~= 0 then frame:SetAlpha(0) end
	elseif frame._rbClientSceneAlphaHidden then
		frame._rbClientSceneAlphaHidden = nil
		if frame.GetAlpha and frame:GetAlpha() == 0 then frame:SetAlpha(1) end
	end
end

local function normalizeGradientColor(value)
	if type(value) == "table" then
		if value.r ~= nil then return value.r or 1, value.g or 1, value.b or 1, value.a or 1 end
		return value[1] or 1, value[2] or 1, value[3] or 1, value[4] or 1
	end
	return 1, 1, 1, 1
end

local function isGradientDebugEnabled()
	if _G and _G.EQOL_DEBUG_RB_GRADIENT == true then return true end
	return addon and addon.db and addon.db.debugResourceBarsGradient == true
end

local function formatColor(r, g, b, a) return string.format("%.2f/%.2f/%.2f/%.2f", r or 0, g or 0, b or 0, a or 1) end

local function debugGradient(bar, reason, cfg, baseR, baseG, baseB, baseA, sr, sg, sb, sa, er, eg, eb, ea, force)
	if not isGradientDebugEnabled() then return end
	local now = GetTime and GetTime() or 0
	if bar then
		bar._rbGradDebugNext = bar._rbGradDebugNext or 0
		if now < bar._rbGradDebugNext then return end
		bar._rbGradDebugNext = now + 0.75
	end
	local name = (bar and bar.GetName and bar:GetName()) or tostring(bar) or "bar"
	local cfgStart, cfgEnd = "nil", "nil"
	if cfg then
		local csr, csg, csb, csa = normalizeGradientColor(cfg.gradientStartColor)
		local cer, ceg, ceb, cea = normalizeGradientColor(cfg.gradientEndColor)
		cfgStart = formatColor(csr, csg, csb, csa)
		cfgEnd = formatColor(cer, ceg, ceb, cea)
	end
	local msg = string.format(
		"grad %s %s base=%s cfgStart=%s cfgEnd=%s outStart=%s outEnd=%s force=%s",
		reason or "?",
		name,
		formatColor(baseR, baseG, baseB, baseA),
		cfgStart,
		cfgEnd,
		formatColor(sr, sg, sb, sa),
		formatColor(er, eg, eb, ea),
		force and "1" or "0"
	)
	print("|cff00ff98Enhance QoL|r: " .. msg)
end

local function resolveGradientColors(cfg, baseR, baseG, baseB, baseA)
	local sr, sg, sb, sa = normalizeGradientColor(cfg and cfg.gradientStartColor)
	local er, eg, eb, ea = normalizeGradientColor(cfg and cfg.gradientEndColor)
	local br, bg, bb, ba = baseR or 1, baseG or 1, baseB or 1, baseA or 1
	return br * sr, bg * sg, bb * sb, (ba or 1) * (sa or 1), br * er, bg * eg, bb * eb, (ba or 1) * (ea or 1)
end

local function clearGradientState(bar)
	bar._rbGradientEnabled = nil
	bar._rbGradientTex = nil
	bar._rbGradDir = nil
	bar._rbGradSR = nil
	bar._rbGradSG = nil
	bar._rbGradSB = nil
	bar._rbGradSA = nil
	bar._rbGradER = nil
	bar._rbGradEG = nil
	bar._rbGradEB = nil
	bar._rbGradEA = nil
end

function ResourceBars.DeactivateEssenceTicker(bar)
	if not bar then return end
	if bar:GetScript("OnUpdate") == bar._essenceUpdater then bar:SetScript("OnUpdate", nil) end
	bar._essenceAnimating = false
	bar._essenceAccum = 0
	bar._essenceUpdateInterval = nil
end

function ResourceBars.ComputeEssenceFraction(bar, current, maxPower, now, powerEnum)
	if not bar then return 0, 0 end
	if current == nil or maxPower == nil then
		bar._essenceNextTick = nil
		bar._essenceFraction = 0
		return 0, 0
	end
	if issecretvalue and (issecretvalue(current) or issecretvalue(maxPower)) then
		bar._essenceNextTick = nil
		bar._essenceFraction = 0
		return 0, 0
	end
	local regen = GetPowerRegenForPowerType and GetPowerRegenForPowerType(powerEnum)
	if not regen or regen <= 0 then regen = 0.2 end
	local tickDuration = 1 / regen

	bar._essenceTickDuration = tickDuration
	bar._essenceNextTick = bar._essenceNextTick or nil
	bar._essenceLastPower = bar._essenceLastPower or current

	if current > bar._essenceLastPower then
		if current < maxPower then
			bar._essenceNextTick = now + tickDuration
		else
			bar._essenceNextTick = nil
		end
	end

	if current < maxPower and not bar._essenceNextTick then bar._essenceNextTick = now + tickDuration end

	if current >= maxPower then bar._essenceNextTick = nil end

	bar._essenceLastPower = current

	local fraction = 0
	if current < maxPower and bar._essenceNextTick and tickDuration > 0 then
		local remaining = bar._essenceNextTick - now
		if remaining < 0 then remaining = 0 end
		fraction = 1 - (remaining / tickDuration)
		if fraction < 0 then
			fraction = 0
		elseif fraction > 1 then
			fraction = 1
		end
	end

	if UnitPartialPower and current < maxPower and powerEnum then
		local partial = UnitPartialPower("player", powerEnum)
		if partial ~= nil and not (issecretvalue and issecretvalue(partial)) then
			local partialFrac = partial / 1000
			if partialFrac < 0 then
				partialFrac = 0
			elseif partialFrac > 1 then
				partialFrac = 1
			end
			fraction = partialFrac
			if tickDuration > 0 then bar._essenceNextTick = now + (1 - fraction) * tickDuration end
		end
	end

	bar._essenceFraction = fraction
	return fraction, tickDuration
end

function ResourceBars.LayoutEssences(bar, cfg, count, texturePath)
	if not bar then return end
	if not count or count <= 0 then
		if bar.essences then
			for i = 1, #bar.essences do
				if bar.essences[i] then bar.essences[i]:Hide() end
			end
		end
		bar._essenceSegments = 0
		return
	end

	bar.essences = bar.essences or {}
	local inner = bar._rbInner or bar
	local w = math.max(1, inner:GetWidth() or (bar:GetWidth() or 0))
	local h = math.max(1, inner:GetHeight() or (bar:GetHeight() or 0))
	local vertical = cfg and cfg.verticalFill == true
	local segPrimary
	if vertical then
		segPrimary = math.max(1, math.floor(h / count + 0.5))
	else
		segPrimary = math.max(1, math.floor(w / count + 0.5))
	end

	for i = 1, count do
		local sb = bar.essences[i]
		if not sb then
			sb = CreateFrame("StatusBar", bar:GetName() .. "Essence" .. i, inner)
			sb:SetMinMaxValues(0, 1)
			bar.essences[i] = sb
		end
		if texturePath and sb._rb_tex ~= texturePath then
			sb:SetStatusBarTexture(texturePath)
			sb._rb_tex = texturePath
		end
		sb:ClearAllPoints()
		if sb:GetParent() ~= inner then sb:SetParent(inner) end
		sb:SetFrameLevel((bar:GetFrameLevel() or 1) + 1)
		if vertical then
			sb:SetWidth(w)
			sb:SetHeight(segPrimary)
			sb:SetOrientation("VERTICAL")
			if i == 1 then
				sb:SetPoint("BOTTOM", inner, "BOTTOM", 0, 0)
			else
				sb:SetPoint("BOTTOM", bar.essences[i - 1], "TOP", 0, 0)
			end
			if i == count then sb:SetPoint("TOP", inner, "TOP", 0, 0) end
		else
			sb:SetHeight(h)
			sb:SetOrientation("HORIZONTAL")
			if i == 1 then
				sb:SetPoint("LEFT", inner, "LEFT", 0, 0)
			else
				sb:SetPoint("LEFT", bar.essences[i - 1], "RIGHT", 0, 0)
			end
			if i == count then
				sb:SetPoint("RIGHT", inner, "RIGHT", 0, 0)
			else
				sb:SetWidth(segPrimary)
			end
		end
		if not sb:IsShown() then sb:Show() end
	end
	for i = count + 1, #bar.essences do
		if bar.essences[i] then bar.essences[i]:Hide() end
	end
	bar._essenceSegments = count
	bar._essenceVertical = vertical
end

function ResourceBars.UpdateEssenceSegments(bar, cfg, current, maxPower, fraction, fallbackColor, layoutFunc, texturePath)
	if not bar then return end
	if not maxPower or maxPower <= 0 then
		if bar.essences then
			for i = 1, #bar.essences do
				if bar.essences[i] then bar.essences[i]:Hide() end
			end
		end
		return
	end
	if not bar.essences or bar._essenceSegments ~= maxPower or bar._essenceVertical ~= (cfg and cfg.verticalFill == true) then
		if layoutFunc then layoutFunc(bar, cfg, maxPower, texturePath) end
	end
	if not bar.essences then return end

	local base = bar._lastColor or bar._baseColor or fallbackColor or { 1, 1, 1, 1 }
	local fullR, fullG, fullB, fullA = base[1] or 1, base[2] or 1, base[3] or 1, base[4] or 1
	local dimFactor = 0.5
	local dimR, dimG, dimB, dimA = fullR * dimFactor, fullG * dimFactor, fullB * dimFactor, fullA
	local colorKey = fullR .. ":" .. fullG .. ":" .. fullB .. ":" .. fullA

	for i = 1, maxPower do
		local sb = bar.essences[i]
		if sb then
			local state
			local value
			if i <= current then
				state = "full"
				value = 1
			elseif i == current + 1 and fraction and fraction > 0 then
				state = "partial"
				value = fraction
			else
				state = "empty"
				value = 0
			end
			sb:SetMinMaxValues(0, 1)
			sb:SetValue(value)

			local wantR, wantG, wantB, wantA
			if state == "full" then
				wantR, wantG, wantB, wantA = fullR, fullG, fullB, fullA
			else
				wantR, wantG, wantB, wantA = dimR, dimG, dimB, dimA
			end

			local needsColor = sb._essenceState ~= state or sb._essenceColorKey ~= colorKey
			sb._essenceState = state
			sb._essenceColorKey = colorKey
			if needsColor then
				if ResourceBars.SetStatusBarColorWithGradient then
					ResourceBars.SetStatusBarColorWithGradient(sb, cfg, wantR, wantG, wantB, wantA)
				else
					sb:SetStatusBarColor(wantR, wantG, wantB, wantA or 1)
				end
				sb._rbColorInitialized = true
			elseif ResourceBars.RefreshStatusBarGradient then
				ResourceBars.RefreshStatusBarGradient(sb, cfg, wantR, wantG, wantB, wantA)
			end
			if not sb:IsShown() then sb:Show() end
		end
	end
	for i = maxPower + 1, #bar.essences do
		if bar.essences[i] then bar.essences[i]:Hide() end
	end
end

function ResourceBars.ApplyBarGradient(bar, cfg, baseR, baseG, baseB, baseA, force)
	if not bar or not cfg or cfg.useGradient ~= true then return false end
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not tex or not tex.SetGradient then return false end
	local sr, sg, sb, sa, er, eg, eb, ea = resolveGradientColors(cfg, baseR, baseG, baseB, baseA)
	local direction = (cfg and cfg.gradientDirection) or "VERTICAL"
	if type(direction) == "string" then direction = direction:upper() end
	if direction ~= "HORIZONTAL" then direction = "VERTICAL" end
	if
		not force
		and bar._rbGradientEnabled
		and bar._rbGradientTex == tex
		and bar._rbGradDir == direction
		and bar._rbGradSR == sr
		and bar._rbGradSG == sg
		and bar._rbGradSB == sb
		and bar._rbGradSA == sa
		and bar._rbGradER == er
		and bar._rbGradEG == eg
		and bar._rbGradEB == eb
		and bar._rbGradEA == ea
	then
		return true
	end
	tex:SetGradient(direction, CreateColor(sr, sg, sb, sa), CreateColor(er, eg, eb, ea))
	debugGradient(bar, "apply", cfg, baseR, baseG, baseB, baseA, sr, sg, sb, sa, er, eg, eb, ea, force)
	bar._rbGradientEnabled = true
	bar._rbGradientTex = tex
	bar._rbGradDir = direction
	bar._rbGradSR, bar._rbGradSG, bar._rbGradSB, bar._rbGradSA = sr, sg, sb, sa
	bar._rbGradER, bar._rbGradEG, bar._rbGradEB, bar._rbGradEA = er, eg, eb, ea
	return true
end

function ResourceBars.SetStatusBarColorWithGradient(bar, cfg, r, g, b, a)
	if not bar then return end
	local alpha = a or 1
	bar:SetStatusBarColor(r, g, b, alpha)
	bar._lastColor = bar._lastColor or {}
	bar._lastColor[1], bar._lastColor[2], bar._lastColor[3], bar._lastColor[4] = r, g, b, alpha
	if cfg and cfg.useGradient == true then
		ResourceBars.ApplyBarGradient(bar, cfg, r, g, b, alpha, true)
	elseif bar._rbGradientEnabled then
		debugGradient(bar, "clear", cfg, r, g, b, a)
		clearGradientState(bar)
	end
end

function ResourceBars.RefreshStatusBarGradient(bar, cfg, r, g, b, a)
	if not bar then return end
	if cfg and cfg.useGradient == true then
		local br, bg, bb, ba = r, g, b, a
		if br == nil then
			if bar._lastColor then
				br, bg, bb, ba = bar._lastColor[1], bar._lastColor[2], bar._lastColor[3], bar._lastColor[4]
			elseif bar.GetStatusBarColor then
				br, bg, bb, ba = bar:GetStatusBarColor()
			end
		end
		ResourceBars.ApplyBarGradient(bar, cfg, br or 1, bg or 1, bb or 1, ba or 1, true)
	elseif bar._rbGradientEnabled then
		local br, bg, bb, ba = r, g, b, a
		if br == nil then
			if bar._lastColor then
				br, bg, bb, ba = bar._lastColor[1], bar._lastColor[2], bar._lastColor[3], bar._lastColor[4]
			elseif bar.GetStatusBarColor then
				br, bg, bb, ba = bar:GetStatusBarColor()
			end
		end
		if br ~= nil then bar:SetStatusBarColor(br, bg or 1, bb or 1, ba or 1) end
		clearGradientState(bar)
	end
end

function ResourceBars.ResolveRuneCooldownColor(cfg)
	local fallback = 0.35
	local c = cfg and cfg.runeCooldownColor
	return c and (c[1] or fallback) or fallback, c and (c[2] or fallback) or fallback, c and (c[3] or fallback) or fallback, c and (c[4] or 1) or 1
end
