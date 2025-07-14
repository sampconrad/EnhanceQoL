local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")

addon.Aura.unitFrame = {}

local function ensureIcon(frame)
	if frame.EQOLTrackedAura then return frame.EQOLTrackedAura end
	local iconFrame = CreateFrame("Frame", nil, frame)
	iconFrame:SetSize(20, 20)
	iconFrame:SetPoint("CENTER", frame)
	local tex = iconFrame:CreateTexture(nil, "OVERLAY")
	tex:SetAllPoints(iconFrame)
	iconFrame.icon = tex
	frame.EQOLTrackedAura = iconFrame
	return iconFrame
end

local function UpdateTrackedBuffs(frame, unit)
	if not frame or not unit or not addon.db.unitFrameAuraIDs then return end
	local iconFrame = ensureIcon(frame)

	local found
	-- Iterate all helpful auras with the Dragonflight+/TWW API
	AuraUtil.ForEachAura(unit, "HELPFUL", nil, function(icon, ...)
		local spellId = select(9, ...)
		if addon.db.unitFrameAuraIDs[spellId] then
                        print(spellId,addon.db.unitFrameAuraIDs[spellId])
			iconFrame.icon:SetTexture(icon)
			iconFrame:Show()
			found = true
			return true -- stop the iteration early
		end
	end)

	if not found then
		-- nothing tracked on this unit right now
		iconFrame:Hide()
	end
end

addon.Aura.unitFrame.Update = UpdateTrackedBuffs

local function RefreshAll()
	if CompactRaidFrameContainer and CompactRaidFrameContainer.GetFrames then
		for frame in CompactRaidFrameContainer:GetFrames() do
			UpdateTrackedBuffs(frame, frame.unit)
		end
	end
	for i = 1, 5 do
		local f = _G["CompactPartyFrameMember" .. i]
		if f then UpdateTrackedBuffs(f, f.unit) end
	end
end

addon.Aura.unitFrame.RefreshAll = RefreshAll

-- Hook the global update function once; Blizzard calls this for every CompactUnitFrame
hooksecurefunc("CompactUnitFrame_UpdateAuras", function(frame)
	-- 'displayedUnit' is the unit token Blizzard uses; fall back to frame.unit
	local unit = frame and frame.displayedUnit or frame.unit
	if unit then UpdateTrackedBuffs(frame, unit) end
end)

function addon.Aura.functions.addUnitFrameAuraOptions(container)
	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	wrapper:SetFullWidth(true)
	container:AddChild(wrapper)

	local drop
	local function refresh()
		local list, order = addon.functions.prepareListForDropdown(addon.db.unitFrameAuraIDs)
		drop:SetList(list, order)
		drop:SetValue(nil)
		RefreshAll()
	end

	local edit = addon.functions.createEditboxAce(L["AddSpellID"], nil, function(self, _, text)
		local id = tonumber(text)
		if id then
			local info = C_Spell.GetSpellInfo(id)
			if info then
				addon.db.unitFrameAuraIDs[id] = string.format("%s (%d)", info.name, id)
				refresh()
			end
		end
		self:SetText("")
	end)
	wrapper:AddChild(edit)

	local list, order = addon.functions.prepareListForDropdown(addon.db.unitFrameAuraIDs)
	drop = addon.functions.createDropdownAce(L["TrackedAuras"], list, order, nil)
	wrapper:AddChild(drop)

	local btn = addon.functions.createButtonAce(REMOVE, 100, function()
		local sel = drop:GetValue()
		if sel then
			addon.db.unitFrameAuraIDs[sel] = nil
			refresh()
		end
	end)
	wrapper:AddChild(btn)
end
