-- luacheck: globals TargetFrameHealthBarMixin TextStatusBar_UpdateTextStringWithValues
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
    addon = _G[parentAddonName]
else
    error(parentAddonName .. " is not loaded")
end

local HealthText = addon.HealthText or {}
addon.HealthText = HealthText

-- Modes per category: OFF, PERCENT, ABS, BOTH
HealthText.modes = HealthText.modes or { boss = "OFF", target = "OFF", player = "OFF" }

HealthText.frame = HealthText.frame or CreateFrame("Frame")
HealthText.hooked = HealthText.hooked or {}
HealthText._valueHooked = HealthText._valueHooked or false

local function isStatusTextEnabled()
    return tonumber(GetCVar("statusText") or "0") == 1
end

local function abbr(n)
    n = tonumber(n) or 0
    if n >= 1000000000 then
        local s = string.format("%.1fb", n / 1000000000)
        s = s:gsub("%.0b", "b")
        return s
    elseif n >= 1000000 then
        local s = string.format("%.1fm", n / 1000000)
        s = s:gsub("%.0m", "m")
        return s
    elseif n >= 1000 then
        local s = string.format("%.1fk", n / 1000)
        s = s:gsub("%.0k", "k")
        return s
    else
        return tostring(n)
    end
end

local function formatPct(pct)
    -- Round to 2 decimals, then trim trailing zeros and optional decimal point
    local s = string.format("%.2f", pct)
    s = s:gsub("%.?0+$", "")
    return s .. "%"
end

local function fmt(mode, cur, max)
    cur = cur or 0
    if mode == "ABS" then
        return abbr(cur)
    end
    local pct = 0
    if (max or 0) > 0 then pct = (cur / max) * 100 end
    if mode == "PERCENT" then
        return formatPct(pct)
    elseif mode == "BOTH" then
        return string.format("%s (%s)", formatPct(pct), abbr(cur))
    else
        return ""
    end
end

local function applyText(hb, text)
    if not hb or not text then return end
    local t = hb.TextString or hb.HealthBarText
    if not t then return end
    if hb.LeftText then hb.LeftText:Hide() end
    if hb.RightText then hb.RightText:Hide() end
    t:SetText(text)
    t:Show()
end

-- Resolve health bar widgets
local function getBossHB(i)
    local f = _G[("Boss%dTargetFrame"):format(i)]
    if not f or not f.TargetFrameContent then return end
    local main = f.TargetFrameContent.TargetFrameContentMain
    local hb = main and main.HealthBarsContainer and main.HealthBarsContainer.HealthBar
    return hb, f
end

local function getTargetHB()
    local tf = _G.TargetFrame
    if not tf or not tf.TargetFrameContent then return end
    local main = tf.TargetFrameContent.TargetFrameContentMain
    local hb = main and main.HealthBarsContainer and main.HealthBarsContainer.HealthBar
    return hb, tf
end

local function getPlayerHB()
    local pf = _G.PlayerFrame
    if not pf or not pf.PlayerFrameContent then return end
    local main = pf.PlayerFrameContent.PlayerFrameContentMain
    local hb = main and main.HealthBarsContainer and main.HealthBarsContainer.HealthBar
    return hb, pf
end

local function shouldApply(kind)
    local mode = HealthText.modes[kind] or "OFF"
    -- When a mode is selected (not OFF), we actively apply our text
    return mode ~= "OFF"
end

local function unitFor(kind, idx)
    if kind == "player" then return "player" end
    if kind == "target" then return "target" end
    if kind == "boss" and idx then return ("boss%d"):format(idx) end
end

function HealthText:Update(kind, idx)
    if not shouldApply(kind) then return end
    local hb
    if kind == "player" then
        hb = getPlayerHB()
    elseif kind == "target" then
        hb = getTargetHB()
    elseif kind == "boss" and idx then
        hb = getBossHB(idx)
    end
    if type(hb) == "table" then hb = hb end -- normalize when getter returns (hb, frame)
    if not hb then return end
    local unit = unitFor(kind, idx)
    if unit and not UnitExists(unit) and kind ~= "player" then return end
    applyText(hb, fmt(self.modes[kind], UnitHealth(unit), UnitHealthMax(unit)))
end

function HealthText:UpdateAll()
    if shouldApply("player") then self:Update("player") end
    if shouldApply("target") then self:Update("target") end
    if shouldApply("boss") then
        local n = _G.MAX_BOSS_FRAMES or 5
        for i = 1, n do self:Update("boss", i) end
    end
end

function HealthText:HideAll() end

local function ensureBarHook(hb, ctx)
    if not hb or HealthText.hooked[hb] then return end
    HealthText.hooked[hb] = ctx or true

    if hb.UpdateTextStringWithValues then
        hooksecurefunc(hb, "UpdateTextStringWithValues", function(bar, textString, value, min, max)
            if not addon or not addon.HealthText then return end
            local kind, idx = ctx.kind, ctx.idx
            if not shouldApply(kind) then return end
            if not textString then return end
            local unit = unitFor(kind, idx)
            if unit ~= "player" and not UnitExists(unit) then return end
            textString:SetText(fmt(addon.HealthText.modes[kind], UnitHealth(unit), UnitHealthMax(unit)))
            textString:Show()
            if bar.LeftText then bar.LeftText:Hide() end
            if bar.RightText then bar.RightText:Hide() end
        end)
    else
        hooksecurefunc("TextStatusBar_UpdateTextStringWithValues", function(statusBar, textString, value, min, max)
            if statusBar ~= hb or not textString then return end
            if not addon or not addon.HealthText then return end
            local kind, idx = ctx.kind, ctx.idx
            if not shouldApply(kind) then return end
            local unit = unitFor(kind, idx)
            if unit ~= "player" and not UnitExists(unit) then return end
            textString:SetText(fmt(addon.HealthText.modes[kind], UnitHealth(unit), UnitHealthMax(unit)))
            textString:Show()
            if statusBar.LeftText then statusBar.LeftText:Hide() end
            if statusBar.RightText then statusBar.RightText:Hide() end
        end)
    end
end

function HealthText:HookBars()
    -- Player
    local hb = getPlayerHB()
    if hb then ensureBarHook(hb, { kind = "player" }) end
    -- Target
    hb = getTargetHB()
    if hb then ensureBarHook(hb, { kind = "target" }) end
    -- Bosses
    local n = _G.MAX_BOSS_FRAMES or 5
    for i = 1, n do
        hb = getBossHB(i)
        if hb then ensureBarHook(hb, { kind = "boss", idx = i }) end
    end

    -- Post-hook: ensure our text after default updates for any TargetFrameHealthBarMixin
    if not self._valueHooked then
        hooksecurefunc(TargetFrameHealthBarMixin, "OnValueChanged", function(bar)
            if not addon or not addon.HealthText then return end
            local ht = addon.HealthText

            -- Walk up and detect context by frame name
            local p = bar
            for _ = 1, 8 do
                if not p then break end
                local name = p.GetName and p:GetName()
                if name == "PlayerFrame" then
                    if shouldApply("player") then ht:Update("player") end
                    return
                elseif name == "TargetFrame" then
                    if shouldApply("target") and UnitExists("target") then ht:Update("target") end
                    return
                elseif name then
                    local i = tonumber(name:match("^Boss(%d)TargetFrame$"))
                    if i then if shouldApply("boss") then ht:Update("boss", i) end return end
                end
                p = p.GetParent and p:GetParent() or nil
            end
        end)
        self._valueHooked = true
    end
end

local function anyEnabled()
    for _, v in pairs(HealthText.modes) do
        if v and v ~= "OFF" then return true end
    end
end

local function updateEventRegistration()
    if anyEnabled() then
        HealthText.frame:RegisterEvent("PLAYER_LOGIN")
        HealthText.frame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        HealthText.frame:RegisterEvent("UNIT_HEALTH")
        HealthText.frame:RegisterEvent("UNIT_MAXHEALTH")
        HealthText.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
        HealthText.frame:RegisterEvent("CVAR_UPDATE")
    else
        HealthText.frame:UnregisterEvent("PLAYER_LOGIN")
        HealthText.frame:UnregisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        HealthText.frame:UnregisterEvent("UNIT_HEALTH")
        HealthText.frame:UnregisterEvent("UNIT_MAXHEALTH")
        HealthText.frame:UnregisterEvent("PLAYER_TARGET_CHANGED")
        HealthText.frame:UnregisterEvent("CVAR_UPDATE")
        HealthText:HideAll()
    end
end

function HealthText:SetMode(kind, mode)
    if not kind then return end
    self.modes[kind] = mode or "OFF"
    updateEventRegistration()
    self:HookBars()
    self:UpdateAll()
end

-- No explicit CVar override controls: OFF = respect Blizzard; others = override

HealthText.frame:SetScript("OnEvent", function(_, event, arg1)
    if not addon or not addon.HealthText then return end
    if not anyEnabled() then return end

    if event == "PLAYER_LOGIN" or event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        addon.HealthText:HookBars()
        addon.HealthText:UpdateAll()
    elseif event == "PLAYER_TARGET_CHANGED" then
        addon.HealthText:Update("target")
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        local unit = tostring(arg1 or "")
        if unit == "player" then
            addon.HealthText:Update("player")
        elseif unit == "target" then
            addon.HealthText:Update("target")
        else
            local i = tonumber(unit:match("^boss(%d)$"))
            if i then addon.HealthText:Update("boss", i) end
        end
    elseif event == "CVAR_UPDATE" then
        -- When user toggles Blizzard status text, simply update to reflect state
        addon.HealthText:UpdateAll()
    end
end)

-- Initialize from DB after file load
local function initFromDB()
    if not addon or not addon.db then return end
    -- Migration for old setting
    if addon.db["healthTextBossMode"] == nil and addon.db["bossHealthMode"] ~= nil then
        addon.db["healthTextBossMode"] = addon.db["bossHealthMode"]
    end

    local modes = {
        boss = addon.db["healthTextBossMode"] or "OFF",
        target = addon.db["healthTextTargetMode"] or "OFF",
        player = addon.db["healthTextPlayerMode"] or "OFF",
    }
    for k, v in pairs(modes) do HealthText.modes[k] = v end

    updateEventRegistration()
    HealthText:HookBars()
    HealthText:UpdateAll()
end

initFromDB()
