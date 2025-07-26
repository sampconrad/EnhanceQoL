local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Aura = addon.Aura or {}
addon.Aura.CastTracker = addon.Aura.CastTracker or {}
local CastTracker = addon.Aura.CastTracker
CastTracker.functions = CastTracker.functions or {}
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")
local AceGUI = addon.AceGUI

local framePool = {}
local activeBars = {}
local activeOrder = {}
local anchor

local function UpdateActiveBars()
       local db = addon.db.castTracker or {}
       for _, bar in pairs(activeBars) do
               bar.status:SetStatusBarColor(unpack(db.color or { 1, 0.5, 0, 1 }))
               bar.icon:SetSize(db.height or 20, db.height or 20)
               bar:SetSize(db.width or 200, db.height or 20)
       end
       CastTracker.functions.LayoutBars()
end

local function AcquireBar()
	local bar = table.remove(framePool)
	if not bar then
		bar = CreateFrame("Frame", nil, anchor)
		bar.status = CreateFrame("StatusBar", nil, bar)
		bar.status:SetAllPoints()
		bar.status:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		bar.icon = bar:CreateTexture(nil, "ARTWORK")
		bar.text = bar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		bar.text:SetPoint("LEFT", 4, 0)
		bar.time = bar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		bar.time:SetPoint("RIGHT", -4, 0)
		bar.time:SetJustifyH("RIGHT")
	end
	bar:Show()
	return bar
end

local function ReleaseBar(bar)
	if not bar then return end
	bar:SetScript("OnUpdate", nil)
	bar:Hide()
	activeBars[bar.owner] = nil
	for i, b in ipairs(activeOrder) do
		if b == bar then
			table.remove(activeOrder, i)
			break
		end
	end
	table.insert(framePool, bar)
	CastTracker.functions.LayoutBars()
end

local function BarUpdate(self)
	local now = GetTime()
	if now >= self.finish then
		ReleaseBar(self)
		return
	end
	self.status:SetValue(now - self.start)
	self.time:SetFormattedText("%.1f", self.finish - now)
end

function CastTracker.functions.LayoutBars()
	for i, bar in ipairs(activeOrder) do
		bar:ClearAllPoints()
		if i == 1 then
			bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
		else
			bar:SetPoint("TOPLEFT", activeOrder[i - 1], "BOTTOMLEFT", 0, -2)
		end
	end
end

function CastTracker.functions.StartBar(spellId, sourceGUID)
        local name, _, icon, castTime = GetSpellInfo(spellId)
        castTime = (castTime or 0) / 1000
        local db = addon.db.castTracker or {}
        if db.duration and db.duration > 0 then castTime = db.duration end
        if castTime <= 0 then return end
        local bar = activeBars[sourceGUID]
        if bar then ReleaseBar(bar) end
	bar = AcquireBar()
	activeBars[sourceGUID] = bar
	bar.owner = sourceGUID
	bar.spellId = spellId
	bar.icon:SetTexture(icon)
	bar.text:SetText(name)
	bar.status:SetMinMaxValues(0, castTime)
	bar.status:SetValue(0)
	bar.status:SetStatusBarColor(unpack(db.color or { 1, 0.5, 0, 1 }))
	bar.icon:SetSize(db.height or 20, db.height or 20)
	bar.icon:SetPoint("RIGHT", bar, "LEFT", -2, 0)
	bar:SetSize(db.width or 200, db.height or 20)
	bar.start = GetTime()
	bar.finish = bar.start + castTime
	bar:SetScript("OnUpdate", BarUpdate)
	table.insert(activeOrder, bar)
	CastTracker.functions.LayoutBars()
	if db.sound then PlaySound(db.sound) end
end

CastTracker.functions.AcquireBar = AcquireBar
CastTracker.functions.ReleaseBar = ReleaseBar
CastTracker.functions.BarUpdate = BarUpdate
CastTracker.functions.UpdateActiveBars = UpdateActiveBars

local function HandleCLEU()
       local _, subevent, _, sourceGUID, _, sourceFlags, _, destGUID, _, _, _, spellId = CombatLogGetCurrentEventInfo()
       if subevent == "SPELL_CAST_START" then
               local db = addon.db.castTracker or {}
               if db.spells and db.spells[spellId] and bit.band(sourceFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) ~= 0 then
                       CastTracker.functions.StartBar(spellId, sourceGUID)
               end
       elseif subevent == "SPELL_CAST_SUCCESS" or subevent == "SPELL_CAST_FAILED" or subevent == "SPELL_INTERRUPT" then
		local bar = activeBars[sourceGUID]
		if bar and bar.spellId == spellId then ReleaseBar(bar) end
	elseif subevent == "UNIT_DIED" then
		ReleaseBar(activeBars[destGUID])
	end
end

local eventFrame = CreateFrame("Frame")

function CastTracker.functions.Refresh()
       local db = addon.db.castTracker or {}
       if not anchor then
               anchor = CreateFrame("Frame", nil, UIParent)
       end
       anchor:ClearAllPoints()
       anchor:SetPoint(db.anchor.point, UIParent, db.anchor.point, db.anchor.x, db.anchor.y)
       eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
       eventFrame:SetScript("OnEvent", HandleCLEU)
       UpdateActiveBars()
end

function CastTracker.functions.addCastTrackerOptions(container)
       local db = addon.db.castTracker or {}
       db.spells = db.spells or {}

       local function rebuild()
               container:ReleaseChildren()
               CastTracker.functions.addCastTrackerOptions(container)
       end

       local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
       container:AddChild(wrapper)

       local groupCore = addon.functions.createContainer("InlineGroup", "List")
       groupCore:SetTitle(L["CastTracker"])
       wrapper:AddChild(groupCore)

       local sw = addon.functions.createSliderAce(L["CastTrackerWidth"] .. ": " .. (db.width or 200), db.width or 200, 50, 400, 1, function(self, _, val)
               db.width = val
               self:SetLabel(L["CastTrackerWidth"] .. ": " .. val)
               UpdateActiveBars()
       end)
       groupCore:AddChild(sw)

       local sh = addon.functions.createSliderAce(L["CastTrackerHeight"] .. ": " .. (db.height or 20), db.height or 20, 10, 60, 1, function(self, _, val)
               db.height = val
               self:SetLabel(L["CastTrackerHeight"] .. ": " .. val)
               UpdateActiveBars()
       end)
       groupCore:AddChild(sh)

       local dur = addon.functions.createSliderAce(L["CastTrackerDuration"] .. ": " .. (db.duration or 0), db.duration or 0, 0, 10, 0.5, function(self, _, val)
               db.duration = val
               self:SetLabel(L["CastTrackerDuration"] .. ": " .. val)
       end)
       groupCore:AddChild(dur)

       local col = AceGUI:Create("ColorPicker")
       col:SetLabel(L["CastTrackerColor"])
       local c = db.color or { 1, 0.5, 0, 1 }
       col:SetColor(c[1], c[2], c[3], c[4])
       col:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
               db.color = { r, g, b, a }
               UpdateActiveBars()
       end)
       groupCore:AddChild(col)

       local soundList = {}
       for sname in pairs(addon.Aura.sounds or {}) do
               soundList[sname] = sname
       end
       local list, order = addon.functions.prepareListForDropdown(soundList)
       local dropSound = addon.functions.createDropdownAce(L["SoundFile"], list, order, function(self, _, val)
               db.sound = val
               self:SetValue(val)
               local file = addon.Aura.sounds and addon.Aura.sounds[val]
               if file then PlaySoundFile(file, "Master") end
       end)
       dropSound:SetValue(db.sound)
       groupCore:AddChild(dropSound)

       wrapper:AddChild(addon.functions.createSpacerAce())

       local groupSpells = addon.functions.createContainer("InlineGroup", "Flow")
       groupSpells:SetTitle(L["CastTrackerSpells"])
       wrapper:AddChild(groupSpells)

       local addEdit = addon.functions.createEditboxAce(L["AddSpellID"], nil, function(self, _, text)
               local id = tonumber(text)
               if id then
                       db.spells[id] = true
                       self:SetText("")
                       rebuild()
               end
       end)
       groupSpells:AddChild(addEdit)

       for spellId in pairs(db.spells) do
               local line = addon.functions.createContainer("SimpleGroup", "Flow")
               line:SetFullWidth(true)
               local name = GetSpellInfo(spellId) or tostring(spellId)
               local label = addon.functions.createLabelAce(name .. " (" .. spellId .. ")")
               label:SetRelativeWidth(0.7)
               line:AddChild(label)
               local btn = addon.functions.createButtonAce(L["Remove"], 80, function()
                       db.spells[spellId] = nil
                       for _, b in pairs(activeBars) do
                               if b.spellId == spellId then ReleaseBar(b) end
                       end
                       rebuild()
               end)
               line:AddChild(btn)
               groupSpells:AddChild(line)
       end
end

CastTracker.functions.Refresh()
