local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")
local AceGUI = addon.AceGUI

-- luacheck: globals ChatFrame_OpenChat

local selectedCategory = addon.db["buffTrackerSelectedCategory"] or 1

for _, cat in pairs(addon.db["buffTrackerCategories"]) do
	for _, buff in pairs(cat.buffs or {}) do
		if not buff.trackType then buff.trackType = "BUFF" end
		if not buff.allowedSpecs then buff.allowedSpecs = {} end
		if not buff.allowedClasses then buff.allowedClasses = {} end
		if not buff.allowedRoles then buff.allowedRoles = {} end
		if buff.showCooldown == nil then buff.showCooldown = false end
		if not buff.conditions then buff.conditions = { join = "AND", conditions = {} } end
	end
	cat.allowedSpecs = nil
	cat.allowedClasses = nil
	cat.allowedRoles = nil
end

local anchors = {}
local activeBuffFrames = {}
local auraInstanceMap = {}
local buffInstances = {}
local altToBase = {}
local spellToCat = {}
local chargeSpells = {}

local timedAuras = {}
local timeTicker
local refreshTimeTicker
local rescanTimer
local firstScan = true

local function scheduleRescan()
	if rescanTimer then rescanTimer:Cancel() end
	rescanTimer = C_Timer.NewTimer(0.1, function()
		rescanTimer = nil
		addon.Aura.scanBuffs()
	end)
end

local LSM = LibStub("LibSharedMedia-3.0")
local getSpellCooldown = C_Spell and C_Spell.GetSpellCooldown or GetSpellCooldown

local function CDResetScript(self)
	local icon = self:GetParent().icon
	icon:SetDesaturated(false)
	icon:SetAlpha(1)
end

local function isNumber(val)
	if type(val) == "number" then return true end
	if type(val) == "string" then return tonumber(val) ~= nil end
	return false
end

local specNames = {}
local specOrder = {}
local classNames = {}

-- gather and sort classes alphabetically
local classes = {}
for classID = 1, GetNumClasses() do
	local className, classTag = select(1, GetClassInfo(classID))
	table.insert(classes, { id = classID, name = className, tag = classTag })
end
table.sort(classes, function(a, b) return a.name < b.name end)

-- build specialization names and order grouped by class
for _, classInfo in ipairs(classes) do
	local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classInfo.id)
	for i = 1, numSpecs do
		local specID, specName, _, specIcon = GetSpecializationInfoForClassID(classInfo.id, i)
		specNames[specID] = string.format("|T%s:14:14|t %s (%s)", specIcon, specName, classInfo.name)
		table.insert(specOrder, specID)
	end

	local coords = CLASS_ICON_TCOORDS[classInfo.tag]
	if coords then
		classNames[classInfo.tag] = string.format(
			"|TInterface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes:14:14:0:0:256:256:%d:%d:%d:%d|t %s",
			coords[1] * 256,
			coords[2] * 256,
			coords[3] * 256,
			coords[4] * 256,
			classInfo.name
		)
	else
		classNames[classInfo.tag] = classInfo.name
	end
end

local roleNames = {
	TANK = INLINE_TANK_ICON .. " " .. TANK,
	HEALER = INLINE_HEALER_ICON .. " " .. HEALER,
	DAMAGER = INLINE_DAMAGER_ICON .. " " .. DAMAGER,
}

local function categoryAllowed(cat)
	if cat.allowedClasses and next(cat.allowedClasses) then
		if not cat.allowedClasses[addon.variables.unitClass] then return false end
	end
	if cat.allowedSpecs and next(cat.allowedSpecs) then
		local specIndex = addon.variables.unitSpec
		if not specIndex then return false end
		local currentSpecID = GetSpecializationInfo(specIndex)
		if not cat.allowedSpecs[currentSpecID] then return false end
	end
	if cat.allowedRoles and next(cat.allowedRoles) then
		local role = UnitGroupRolesAssigned("player")
		if role == "NONE" then role = addon.variables.unitRole end
		if not role or not cat.allowedRoles[role] then return false end
	end
	return true
end

local function buffAllowed(buff)
	if buff.allowedClasses and next(buff.allowedClasses) then
		if not buff.allowedClasses[addon.variables.unitClass] then return false end
	end
	if buff.allowedSpecs and next(buff.allowedSpecs) then
		local specIndex = addon.variables.unitSpec
		if not specIndex then return false end
		local currentSpecID = GetSpecializationInfo(specIndex)
		if not buff.allowedSpecs[currentSpecID] then return false end
	end
	if buff.allowedRoles and next(buff.allowedRoles) then
		local role = UnitGroupRolesAssigned("player")
		if role == "NONE" then role = addon.variables.unitRole end
		if not role or not buff.allowedRoles[role] then return false end
	end
	return true
end

function addon.Aura.functions.BuildSoundTable()
	local result = {}

	for name, path in pairs(LSM:HashTable("sound")) do
		result[name] = path
	end
	addon.Aura.sounds = result
end
addon.Aura.functions.BuildSoundTable()

local function evaluateCondition(cond, aura)
	if not cond or not cond.type then return true end
	if cond.type == "missing" then
		local missing = aura == nil
		local val = cond.value
		if cond.operator == "~=" or cond.operator == "!=" then return missing ~= val end
		return missing == val
	elseif cond.type == "stack" then
		if not isNumber(cond.value) then return true end
		local stacks = aura and aura.applications or 0
		local val = tonumber(cond.value) or 0
		if cond.operator == ">" then
			return stacks > val
		elseif cond.operator == "<" then
			return stacks < val
		elseif cond.operator == ">=" then
			return stacks >= val
		elseif cond.operator == "<=" then
			return stacks <= val
		elseif cond.operator == "~=" or cond.operator == "!=" then
			return stacks ~= val
		end
		return stacks == val
	elseif cond.type == "time" then
		if not aura or not aura.duration or aura.duration <= 0 then return false end
		if not isNumber(cond.value) then return true end
		local remaining = aura.expirationTime - GetTime()
		local val = tonumber(cond.value) or 0
		if cond.operator == ">" then
			return remaining > val
		elseif cond.operator == "<" then
			return remaining < val
		elseif cond.operator == ">=" then
			return remaining >= val
		elseif cond.operator == "<=" then
			return remaining <= val
		elseif cond.operator == "~=" or cond.operator == "!=" then
			return remaining ~= val
		end
		return remaining == val
	end
	return true
end

local function evaluateGroup(group, aura)
	if not group then return true end
	local join = group.join or "AND"
	local children = group.conditions or {}
	if #children == 0 then return true end
	if join == "AND" then
		for _, child in ipairs(children) do
			local ok = child.join and evaluateGroup(child, aura) or evaluateCondition(child, aura)
			if not ok then return false end
		end
		return true
	else
		for _, child in ipairs(children) do
			local ok = child.join and evaluateGroup(child, aura) or evaluateCondition(child, aura)
			if ok then return true end
		end
		return false
	end
end

local function hasMissingCondition(group)
	if not group then return false end
	for _, child in ipairs(group.conditions or {}) do
		if child.join then
			if hasMissingCondition(child) then return true end
		elseif child.type == "missing" then
			return true
		end
	end
	return false
end

local function hasTimeCondition(group)
	if not group then return false end
	for _, child in ipairs(group.conditions or {}) do
		if child.join then
			if hasTimeCondition(child) then return true end
		elseif child.type == "time" then
			return true
		end
	end
	return false
end

local function getCategory(id) return addon.db["buffTrackerCategories"][id] end

local function rebuildAltMapping()
	wipe(altToBase)
	wipe(spellToCat)
	wipe(chargeSpells)
	for catId, cat in pairs(addon.db["buffTrackerCategories"]) do
		for baseId, buff in pairs(cat.buffs or {}) do
			spellToCat[baseId] = spellToCat[baseId] or {}
			spellToCat[baseId][catId] = true

			buff.altHash = {}
			if buff.altIDs then
				for _, altId in ipairs(buff.altIDs) do
					altToBase[altId] = baseId
					buff.altHash[altId] = true
				end
			end

			local info = C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(baseId)
			if info and info.maxCharges and info.maxCharges > 0 then
				chargeSpells[baseId] = true
				buff.hasCharges = true
			else
				buff.hasCharges = false
			end
		end
	end
end

local function getNextCategoryId()
	local max = 0
	for id in pairs(addon.db["buffTrackerCategories"]) do
		if type(id) == "number" and id > max then max = id end
	end
	return max + 1
end

local function ensureAnchor(id)
	if anchors[id] then return anchors[id] end

	local cat = getCategory(id)
	if not cat then return end

	local anchor = CreateFrame("Frame", "EQOLBuffTrackerAnchor" .. id, UIParent, "BackdropTemplate")
	anchor:SetSize(cat.size, cat.size)
	anchor:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
	anchor:SetBackdropColor(0, 0, 0, 0.6)
	anchor:SetMovable(true)
	anchor:EnableMouse(true)
	anchor:RegisterForDrag("LeftButton")
	anchor.text = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	anchor.text:SetPoint("CENTER", anchor, "CENTER")
	anchor.text:SetText(L["DragToPosition"]:format("|cffffd700" .. (cat.name or "") .. "|r"))

	anchor:SetScript("OnDragStart", anchor.StartMoving)
	anchor:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, xOfs, yOfs = self:GetPoint()
		cat.point = point
		cat.x = xOfs
		cat.y = yOfs
	end)

	anchor:SetScript("OnShow", function()
		if cat.point then
			anchor:ClearAllPoints()
			anchor:SetPoint(cat.point, UIParent, cat.point, cat.x, cat.y)
		end
	end)
	if cat.point then
		anchor:ClearAllPoints()
		anchor:SetPoint(cat.point, UIParent, cat.point, cat.x, cat.y)
	end
	anchors[id] = anchor
	return anchor
end

local function changeAnchorName(id)
	local anchor = ensureAnchor(id)
	if not anchor then return end
	local cat = getCategory(id)
	if not cat then return end
	anchor.text:SetText(L["DragToPosition"]:format("|cffffd700" .. (cat.name or "") .. "|r"))
end

local function updatePositions(id)
	local cat = getCategory(id)
	local anchor = ensureAnchor(id)
	local point = cat.direction or "RIGHT"
	local prev = anchor
	activeBuffFrames[id] = activeBuffFrames[id] or {}
	for _, frame in pairs(activeBuffFrames[id]) do
		if frame:IsShown() then
			frame:ClearAllPoints()
			if point == "LEFT" then
				frame:SetPoint("RIGHT", prev, "LEFT", -2, 0)
			elseif point == "UP" then
				frame:SetPoint("BOTTOM", prev, "TOP", 0, 2)
			elseif point == "DOWN" then
				frame:SetPoint("TOP", prev, "BOTTOM", 0, -2)
			else
				frame:SetPoint("LEFT", prev, "RIGHT", 2, 0)
			end
			prev = frame
		end
	end
end

local function applyLockState()
	for id, anchor in pairs(anchors) do
		if not addon.db["buffTrackerEnabled"][id] then
			anchor:Hide()
		elseif addon.db["buffTrackerLocked"][id] then
			anchor:RegisterForDrag()
			anchor:SetMovable(false)
			anchor:EnableMouse(false)
			anchor:SetScript("OnDragStart", nil)
			anchor:SetScript("OnDragStop", nil)
			anchor:SetBackdropColor(0, 0, 0, 0)
			anchor.text:Hide()
		else
			anchor:RegisterForDrag("LeftButton")
			anchor:SetMovable(true)
			anchor:EnableMouse(true)
			anchor:SetScript("OnDragStart", anchor.StartMoving)
			anchor:SetScript("OnDragStop", function(self)
				self:StopMovingOrSizing()
				local cat = getCategory(id)
				local point, _, _, xOfs, yOfs = self:GetPoint()
				cat.point = point
				cat.x = xOfs
				cat.y = yOfs
			end)
			anchor:SetBackdropColor(0, 0, 0, 0.6)
			anchor.text:Show()
		end
	end
end

local function applySize(id)
	local cat = getCategory(id)
	local anchor = ensureAnchor(id)
	local size = cat.size
	anchor:SetSize(size, size)
	activeBuffFrames[id] = activeBuffFrames[id] or {}
	for buffId, frame in pairs(activeBuffFrames[id]) do
		frame:SetSize(size, size)
		frame.cd:SetAllPoints(frame)
		if frame.SpellActivationAlert then
			ActionButton_HideOverlayGlow(frame)
			local buff = cat.buffs and cat.buffs[buffId]
			if buff and buff.glow and frame.isActive then ActionButton_ShowOverlayGlow(frame) end
		end
	end
	updatePositions(id)
end

local function applyTimerText()
	for catId, frames in pairs(activeBuffFrames) do
		local cat = getCategory(catId)
		for buffId, frame in pairs(frames) do
			local buff = cat and cat.buffs and cat.buffs[buffId]
			local show = buff and buff.showTimerText
			if show == nil then show = addon.db["buffTrackerShowTimerText"] end
			if show == nil then show = true end
			if frame.cd then frame.cd:SetHideCountdownNumbers(not show) end
		end
	end
end

local function createBuffFrame(icon, parent, size, castOnClick, spellID, showTimerText)
	local frameType = castOnClick and "Button" or "Frame"
	-- local template = castOnClick and "SecureActionButtonTemplate" or nil
	local template = nil
	local frame = CreateFrame(frameType, nil, parent, template)
	frame:SetSize(size, size)
	frame:SetFrameStrata("DIALOG")

	local tex = frame:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints(frame)
	tex:SetTexture(icon)
	frame.icon = tex

	local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
	cd:SetAllPoints(frame)
	cd:SetDrawEdge(false)
	local show = showTimerText
	if show == nil then show = addon.db["buffTrackerShowTimerText"] end
	if show == nil then show = true end
	cd:SetHideCountdownNumbers(not show)
	frame.cd = cd

	local overlay = CreateFrame("Frame", nil, frame)
	overlay:SetAllPoints(frame)
	overlay:SetFrameLevel(cd:GetFrameLevel() + 5)

	local count = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	count:SetFont(addon.variables.defaultFont, 16, "OUTLINE")
	count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
	count:SetShadowOffset(1, -1)
	count:SetShadowColor(0, 0, 0, 1)
	frame.count = count

	local charges = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	charges:SetFont(addon.variables.defaultFont, 16, "OUTLINE")
	charges:SetPoint("CENTER", frame, "TOP", 0, -1)
	charges:SetShadowOffset(1, -1)
	charges:SetShadowColor(0, 0, 0, 1)
	frame.charges = charges

	frame.castOnClick = castOnClick
	if castOnClick then
		frame:SetAttribute("type", "spell")
		frame:SetAttribute("spell", spellID)
		frame:EnableMouse(true)
		frame:RegisterForClicks("AnyUp", "AnyDown")
		frame:SetScript("PostClick", scheduleRescan)
	end

	return frame
end

local function playBuffSound(catId, baseId, altId)
	if not addon.db["buffTrackerSoundsEnabled"] then return end
	if not addon.db["buffTrackerSoundsEnabled"][catId] then return end

	local function getSound(id)
		if addon.db["buffTrackerSoundsEnabled"][catId][id] then return addon.db["buffTrackerSounds"][catId][id] end
	end

	local sound = altId and getSound(altId) or nil
	if not sound then sound = getSound(baseId) end

	if not sound then return end

	local file = addon.Aura.sounds[sound]
	if file then PlaySoundFile(file, "Master") end
end

local function updateBuff(catId, id, changedId, firstScan)
	if firstScan == nil then firstScan = false end
	local cat = getCategory(catId)
	local buff = cat and cat.buffs and cat.buffs[id]
	local key = catId .. ":" .. id
	local before = timedAuras[key] ~= nil
	if buff and hasTimeCondition(buff.conditions) then
		timedAuras[key] = { catId = catId, buffId = id }
	else
		timedAuras[key] = nil
	end
	if before ~= (timedAuras[key] ~= nil) and refreshTimeTicker then refreshTimeTicker() end
	if buff and not buffAllowed(buff) then
		if activeBuffFrames[catId] and activeBuffFrames[catId][id] then activeBuffFrames[catId][id]:Hide() end
		return
	end

	local aura
	local triggeredId = id
	if changedId and (changedId == id or (buff and buff.altHash and buff.altHash[changedId])) then
		aura = C_UnitAuras.GetPlayerAuraBySpellID(changedId)
		triggeredId = changedId
	else
		aura = C_UnitAuras.GetPlayerAuraBySpellID(id)
		triggeredId = id
		if not aura and buff and buff.altHash then
			for altId in pairs(buff.altHash) do
				aura = C_UnitAuras.GetPlayerAuraBySpellID(altId)
				if aura then
					triggeredId = altId
					break
				end
			end
		end
	end
	if aura then
		local tType = buff and buff.trackType or (cat and cat.trackType) or "BUFF"
		if tType == "DEBUFF" and not aura.isHarmful then
			aura = nil
		elseif tType == "BUFF" and not aura.isHelpful then
			aura = nil
		elseif firstScan and aura.expirationTime and aura.expirationTime > 0 and (not aura.duration or aura.duration <= 0) then
			aura.duration = aura.expirationTime - GetTime()
		end
	end

	local condOk = evaluateGroup(buff and buff.conditions, aura)
	if aura == nil and not hasMissingCondition(buff and buff.conditions) then condOk = false end
	local displayAura = condOk and aura or nil

	activeBuffFrames[catId] = activeBuffFrames[catId] or {}
	local frame = activeBuffFrames[catId][id]
	local keyInst = catId .. ":" .. id
	local prevInst = buffInstances[keyInst]
	if prevInst then auraInstanceMap[prevInst] = nil end
	local wasShown = frame and frame:IsShown()
	local wasActive = frame and frame.isActive

	if buff and buff.showAlways then
		local icon = buff.icon or (aura and aura.icon)
		local showTimer = buff.showTimerText
		if showTimer == nil then showTimer = addon.db["buffTrackerShowTimerText"] end
		if showTimer == nil then showTimer = true end
		if not frame then
			frame = createBuffFrame(icon, ensureAnchor(catId), getCategory(catId).size, false, id, showTimer)
			activeBuffFrames[catId][id] = frame
		else
			frame.cd:SetHideCountdownNumbers(not showTimer)
		end
		frame.icon:SetTexture(icon)
		if aura then
			if firstScan and aura.expirationTime and aura.expirationTime > 0 and (not aura.duration or aura.duration <= 0) then aura.duration = aura.expirationTime - GetTime() end
			if aura.duration and aura.duration > 0 then
				frame.cd:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
				frame.cd:SetReverse(true)
			else
				frame.cd:SetReverse(false)
				frame.cd:Clear()
			end
			frame.icon:SetDesaturated(false)
			frame.icon:SetAlpha(1)
			if not wasActive then playBuffSound(catId, id, triggeredId) end
			frame.isActive = true
		else
			if buff.showCooldown then
				local spellInfo = getSpellCooldown(id)
				local cdStart = spellInfo.startTime
				local cdDur = spellInfo.duration
				local cdEnable = spellInfo.isEnabled
				local modRate = spellInfo.modRate
				frame.cd:SetReverse(false)
				if cdEnable and cdDur and cdDur > 0 and cdStart > 0 and (cdStart + cdDur) > GetTime() then
					frame.cd:SetCooldown(cdStart, cdDur, modRate)
					frame.icon:SetDesaturated(true)
					frame.icon:SetAlpha(0.5)
					frame.cd:SetScript("OnCooldownDone", CDResetScript)
				else
					frame.cd:Clear()
					frame.cd:SetScript("OnCooldownDone", nil)
					frame.icon:SetDesaturated(false)
					frame.icon:SetAlpha(1)
				end
			else
				frame.cd:Clear()
				frame.cd:SetScript("OnCooldownDone", nil)
				frame.icon:SetDesaturated(true)
				frame.icon:SetAlpha(0.5)
			end
			frame.isActive = false
		end
		if buff.glow then
			if frame.isActive then
				ActionButton_ShowOverlayGlow(frame)
			else
				ActionButton_HideOverlayGlow(frame)
			end
		else
			ActionButton_HideOverlayGlow(frame)
		end
		frame:Show()
	elseif condOk then
		if displayAura then
			if firstScan and displayAura.expirationTime and displayAura.expirationTime > 0 and (not displayAura.duration or displayAura.duration <= 0) then
				displayAura.duration = displayAura.expirationTime - GetTime()
			end
			local icon = buff and buff.icon or displayAura.icon
			local showTimer = buff and buff.showTimerText
			if showTimer == nil then showTimer = addon.db["buffTrackerShowTimerText"] end
			if showTimer == nil then showTimer = true end
			if not frame then
				frame = createBuffFrame(icon, ensureAnchor(catId), getCategory(catId).size, false, id, showTimer)
				activeBuffFrames[catId][id] = frame
			else
				frame.cd:SetHideCountdownNumbers(not showTimer)
			end
			frame.icon:SetTexture(icon)
			frame.icon:SetDesaturated(false)
			frame.icon:SetAlpha(1)
			if displayAura.duration and displayAura.duration > 0 then
				frame.cd:SetCooldown(displayAura.expirationTime - displayAura.duration, displayAura.duration)
			else
				frame.cd:Clear()
			end
			if not wasShown then playBuffSound(catId, id, triggeredId) end
			frame.isActive = true
			if buff.glow then
				ActionButton_ShowOverlayGlow(frame)
			else
				ActionButton_HideOverlayGlow(frame)
			end
			frame:Show()
		else
			local icon = buff.icon
			-- TODO 11.2: Replace IsSpellKnown* usage with C_SpellBook.IsSpellInSpellBook
			local shouldSecure = buff.castOnClick and (IsSpellKnown(id) or IsSpellKnownOrOverridesKnown(id))
			local showTimer = buff.showTimerText
			if showTimer == nil then showTimer = addon.db["buffTrackerShowTimerText"] end
			if showTimer == nil then showTimer = true end
			if not frame or frame.castOnClick ~= shouldSecure then
				frame = createBuffFrame(icon, ensureAnchor(catId), getCategory(catId).size, shouldSecure, id, showTimer)
				activeBuffFrames[catId][id] = frame
			else
				frame.cd:SetHideCountdownNumbers(not showTimer)
			end
			frame.icon:SetTexture(icon)
			local cdStart, cdDur, cdEnable, modRate
			if buff.showCooldown then
				local spellInfo = getSpellCooldown(id)
				cdStart = spellInfo.startTime
				cdDur = spellInfo.duration
				cdEnable = spellInfo.isEnabled
				modRate = spellInfo.modRate
			end
			if buff.showCooldown and cdEnable and cdDur and cdDur > 0 and cdStart > 0 and (cdStart + cdDur) > GetTime() then
				frame.cd:SetCooldown(cdStart, cdDur, modRate)
				frame.icon:SetDesaturated(true)
				frame.icon:SetAlpha(0.5)
				frame.cd:SetScript("OnCooldownDone", CDResetScript)
			else
				frame.cd:Clear()
				frame.cd:SetScript("OnCooldownDone", nil)
				frame.icon:SetDesaturated(false)
				frame.icon:SetAlpha(1)
			end
			if shouldSecure then
				frame:EnableMouse(true)
				frame:RegisterForClicks("AnyUp", "AnyDown")
			end
			if not wasShown then playBuffSound(catId, id, triggeredId) end
			frame.isActive = hasMissingCondition(buff and buff.conditions)
			if buff.glow then
				ActionButton_ShowOverlayGlow(frame)
			else
				ActionButton_HideOverlayGlow(frame)
			end
			frame:Show()
		end
	else
		if frame then
			frame.isActive = false
			ActionButton_HideOverlayGlow(frame)
			frame:Hide()
		end
	end

	buffInstances[keyInst] = aura and aura.auraInstanceID or nil
	if aura then auraInstanceMap[aura.auraInstanceID] = { catId = catId, buffId = id } end

	if frame then
		frame.auraInstanceID = buffInstances[keyInst]

		local showStacks = buff and buff.showStacks
		if showStacks == nil then showStacks = addon.db["buffTrackerShowStacks"] end
		if showStacks == nil then showStacks = true end
		if showStacks and aura and aura.applications and aura.applications > 1 then
			frame.count:SetText(aura.applications)
			frame.count:Show()
		else
			frame.count:Hide()
		end

		local showCharges = buff and buff.showCharges
		if showCharges == nil then showCharges = addon.db["buffTrackerShowCharges"] end
		if not (buff and buff.showAlways) then showCharges = false end
		if showCharges and buff.hasCharges then
			local info = C_Spell.GetSpellCharges(id)
			if info and info.maxCharges then
				frame.charges:SetText(info.currentCharges)
				frame.charges:Show()
				if not aura and buff.showCooldown and info.currentCharges < info.maxCharges then
					frame.cd:SetCooldown(info.cooldownStartTime, info.cooldownDuration, info.chargeModRate)
					frame.cd:SetReverse(false)
					frame.cd:SetScript("OnCooldownDone", CDResetScript)
					if info.currentCharges == 0 then
						frame.icon:SetDesaturated(true)
						frame.icon:SetAlpha(0.5)
					else
						frame.icon:SetDesaturated(false)
						frame.icon:SetAlpha(1)
					end
				end
			else
				frame.charges:Hide()
			end
		else
			frame.charges:Hide()
		end
	end
end

refreshTimeTicker = function()
	if timeTicker then
		timeTicker:Cancel()
		timeTicker = nil
	end
	if next(timedAuras) then
		local updatedCats = {}
		timeTicker = C_Timer.NewTicker(1, function()
			for _, info in pairs(timedAuras) do
				updateBuff(info.catId, info.buffId)
				updatedCats[info.catId] = true
			end
			for catId in pairs(updatedCats) do
				updatePositions(catId)
			end
			wipe(updatedCats)
		end)
	end
end

local function scanBuffs()
	wipe(timedAuras)
	wipe(buffInstances)
	wipe(auraInstanceMap)
	for catId, cat in pairs(addon.db["buffTrackerCategories"]) do
		if addon.db["buffTrackerEnabled"][catId] and categoryAllowed(cat) then
			for id in pairs(cat.buffs) do
				if not addon.db["buffTrackerHidden"][id] then
					updateBuff(catId, id, nil, firstScan)
				elseif activeBuffFrames[catId] and activeBuffFrames[catId][id] then
					activeBuffFrames[catId][id]:Hide()
				end
			end
			updatePositions(catId)
			if anchors[catId] then anchors[catId]:Show() end
		else
			if anchors[catId] then anchors[catId]:Hide() end
			if activeBuffFrames[catId] then
				for _, frame in pairs(activeBuffFrames[catId]) do
					frame:Hide()
				end
			end
		end
	end
	refreshTimeTicker()
	firstScan = false
end

local function collectActiveAuras()
	for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
		local i = 1
		local aura = C_UnitAuras.GetAuraDataByIndex("player", i, filter)
		while aura do
			local base = altToBase[aura.spellId] or aura.spellId
			auraInstanceMap[aura.auraInstanceID] = { buffId = base }
			for catId in pairs(spellToCat[base] or {}) do
				local key = catId .. ":" .. base
				buffInstances[key] = aura.auraInstanceID
			end
			i = i + 1
			aura = C_UnitAuras.GetAuraDataByIndex("player", i, filter)
		end
	end
end

addon.Aura.buffAnchors = anchors
addon.Aura.scanBuffs = scanBuffs

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, unit, ...)
	if event == "PLAYER_LOGIN" or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
		for id, anchor in pairs(anchors) do
			local cat = getCategory(id)
			if addon.db["buffTrackerEnabled"][id] and categoryAllowed(cat) then
				anchor:Show()
			else
				anchor:Hide()
			end
		end
		if event == "PLAYER_LOGIN" then
			addon.Aura.functions.BuildSoundTable()
			rebuildAltMapping()
		end
		if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
			collectActiveAuras()
			firstScan = true
			C_Timer.After(1, scanBuffs)
			return
		end
	end

	if event == "UNIT_AURA" and unit == "player" then
		local eventInfo = ...
		if eventInfo then
			local changed = {}
			for _, aura in ipairs(eventInfo.addedAuras or {}) do
				local base = altToBase[aura.spellId] or aura.spellId
				changed[base] = aura.spellId
			end
			for _, inst in ipairs(eventInfo.updatedAuraInstanceIDs or {}) do
				local data = C_UnitAuras.GetAuraDataByAuraInstanceID("player", inst)
				if data then
					local base = altToBase[data.spellId] or data.spellId
					changed[base] = data.spellId
				elseif auraInstanceMap[inst] then
					changed[auraInstanceMap[inst].buffId] = true
				end
			end
			for _, inst in ipairs(eventInfo.removedAuraInstanceIDs or {}) do
				if auraInstanceMap[inst] then changed[auraInstanceMap[inst].buffId] = true end
				auraInstanceMap[inst] = nil
			end

			local needsLayout = {}
			for spellId, cId in pairs(changed) do
				for catId in pairs(spellToCat[spellId] or {}) do
					local cat = addon.db["buffTrackerCategories"][catId]
					if addon.db["buffTrackerEnabled"][catId] and categoryAllowed(cat) then
						if not addon.db["buffTrackerHidden"][spellId] then
							local changedId = cId ~= true and cId or nil
							updateBuff(catId, spellId, changedId)
						elseif activeBuffFrames[catId] and activeBuffFrames[catId][spellId] then
							activeBuffFrames[catId][spellId]:Hide()
						end
						needsLayout[catId] = true
					end
				end
			end

			for catId in pairs(needsLayout) do
				updatePositions(catId)
				if anchors[catId] then anchors[catId]:Show() end
			end
			return
		end
	end

	if event == "SPELL_UPDATE_COOLDOWN" then
		local changedSpell = ...
		local needsLayout = {}

		if changedSpell then
			local baseSpell = altToBase[changedSpell] or changedSpell
			for catId in pairs(spellToCat[baseSpell] or {}) do
				local cat = addon.db["buffTrackerCategories"][catId]
				if addon.db["buffTrackerEnabled"][catId] and categoryAllowed(cat) then
					local buff = cat.buffs[baseSpell]
					if buff and buff.showCooldown then
						updateBuff(catId, baseSpell)
						needsLayout[catId] = true
					end
				end
			end
		else
			for catId, cat in pairs(addon.db["buffTrackerCategories"]) do
				if addon.db["buffTrackerEnabled"][catId] and categoryAllowed(cat) then
					for id, buff in pairs(cat.buffs) do
						if buff.showCooldown then
							updateBuff(catId, id)
							needsLayout[catId] = true
						end
					end
				end
			end
		end

		for catId in pairs(needsLayout) do
			updatePositions(catId)
		end
		return
	end

	if event == "SPELL_UPDATE_CHARGES" then
		local changedSpell = ...
		local needsLayout = {}

		if changedSpell then
			local baseSpell = altToBase[changedSpell] or changedSpell
			if chargeSpells[baseSpell] then
				for catId in pairs(spellToCat[baseSpell] or {}) do
					local cat = addon.db["buffTrackerCategories"][catId]
					if addon.db["buffTrackerEnabled"][catId] and categoryAllowed(cat) then
						local buff = cat.buffs[baseSpell]
						if buff and (buff.showCharges or buff.showCooldown) then
							updateBuff(catId, baseSpell)
							needsLayout[catId] = true
						end
					end
				end
			end
		else
			for spellId in pairs(chargeSpells) do
				for catId in pairs(spellToCat[spellId] or {}) do
					local cat = addon.db["buffTrackerCategories"][catId]
					if addon.db["buffTrackerEnabled"][catId] and categoryAllowed(cat) then
						local buff = cat.buffs[spellId]
						if buff and (buff.showCharges or buff.showCooldown) then
							updateBuff(catId, spellId)
							needsLayout[catId] = true
						end
					end
				end
			end
		end

		for catId in pairs(needsLayout) do
			updatePositions(catId)
		end
		return
	end

	scanBuffs()
end)
eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")

local function addBuff(catId, id)
	-- get spell name and icon once
	local spellData = C_Spell.GetSpellInfo(id)
	if not spellData then return end

	local cat = getCategory(catId)
	if not cat then return end

	local defStacks = addon.db["buffTrackerShowStacks"]
	if defStacks == nil then defStacks = true end
	local defTimer = addon.db["buffTrackerShowTimerText"]
	if defTimer == nil then defTimer = true end
	cat.buffs[id] = {
		name = spellData.name,
		icon = spellData.iconID,
		altIDs = {},
		showAlways = false,
		glow = false,
		castOnClick = false,
		showCooldown = false,
		showCharges = addon.db["buffTrackerShowCharges"] or false,
		trackType = "BUFF",
		conditions = { join = "AND", conditions = {} },
		allowedSpecs = {},
		allowedClasses = {},
		allowedRoles = {},
		showStacks = defStacks,
		showTimerText = defTimer,
	}

	if nil == addon.db["buffTrackerOrder"][catId] then addon.db["buffTrackerOrder"][catId] = {} end
	if not tContains(addon.db["buffTrackerOrder"][catId], id) then table.insert(addon.db["buffTrackerOrder"][catId], id) end

	-- make sure the buff is not hidden
	addon.db["buffTrackerHidden"][id] = nil

	rebuildAltMapping()
	scanBuffs()
end

local function removeBuff(catId, id)
	local cat = getCategory(catId)
	if not cat then return end
	cat.buffs[id] = nil
	addon.db["buffTrackerHidden"][id] = nil
	addon.db["buffTrackerSounds"][catId][id] = nil
	if addon.db["buffTrackerSoundsEnabled"] and addon.db["buffTrackerSoundsEnabled"][catId] then addon.db["buffTrackerSoundsEnabled"][catId][id] = nil end
	if nil == addon.db["buffTrackerOrder"][catId] then addon.db["buffTrackerOrder"][catId] = {} end
	for i, v in ipairs(addon.db["buffTrackerOrder"][catId]) do
		if v == id then
			table.remove(addon.db["buffTrackerOrder"][catId], i)
			break
		end
	end
	if activeBuffFrames[catId] and activeBuffFrames[catId][id] then
		activeBuffFrames[catId][id]:Hide()
		activeBuffFrames[catId][id] = nil
	end
	local instKey = catId .. ":" .. id
	if buffInstances[instKey] then
		auraInstanceMap[buffInstances[instKey]] = nil
		buffInstances[instKey] = nil
	end
	rebuildAltMapping()
	scanBuffs()
end

local function sanitiseCategory(cat)
	if not cat then return end
	cat.allowedSpecs = nil
	cat.allowedClasses = nil
	cat.allowedRoles = nil
	for _, buff in pairs(cat.buffs or {}) do
		if not buff.altIDs then buff.altIDs = {} end
		if buff.showAlways == nil then buff.showAlways = false end
		if buff.glow == nil then buff.glow = false end
		if buff.castOnClick == nil then buff.castOnClick = false end
		if not buff.trackType then buff.trackType = "BUFF" end
		if not buff.allowedSpecs then buff.allowedSpecs = {} end
		if not buff.allowedClasses then buff.allowedClasses = {} end
		if not buff.allowedRoles then buff.allowedRoles = {} end
		if not buff.conditions then buff.conditions = { join = "AND", conditions = {} } end
		if buff.showStacks == nil then
			local def = addon.db["buffTrackerShowStacks"]
			if def == nil then def = true end
			buff.showStacks = def
		end
		if buff.showTimerText == nil then
			local def = addon.db["buffTrackerShowTimerText"]
			if def == nil then def = true end
			buff.showTimerText = def
		end
		if buff.showCharges == nil then
			local def = addon.db["buffTrackerShowCharges"]
			if def == nil then def = false end
			buff.showCharges = def
		end
	end
end

-- encodeMode = "chat" | "addon" | nil
-- forward declaration so luacheck sees ShareCategory below
local ShareCategory

local function exportCategory(catId, encodeMode)
	local cat = addon.db["buffTrackerCategories"][catId]
	if not cat then return end
	local data = {
		category = cat,
		order = addon.db["buffTrackerOrder"][catId] or {},
		sounds = addon.db["buffTrackerSounds"][catId] or {},
		soundsEnabled = addon.db["buffTrackerSoundsEnabled"][catId] or {},
		version = 1,
	}
	local serializer = LibStub("AceSerializer-3.0")
	local deflate = LibStub("LibDeflate")
	local serialized = serializer:Serialize(data)
	local compressed = deflate:CompressDeflate(serialized)
	if encodeMode == "chat" then
		return deflate:EncodeForWoWChatChannel(compressed)
	elseif encodeMode == "addon" then
		return deflate:EncodeForWoWAddonChannel(compressed)
	end
	return deflate:EncodeForPrint(compressed)
end

local function importCategory(encoded)
	if type(encoded) ~= "string" or encoded == "" then return end
	local deflate = LibStub("LibDeflate")
	local serializer = LibStub("AceSerializer-3.0")
	local decoded = deflate:DecodeForPrint(encoded) or deflate:DecodeForWoWChatChannel(encoded) or deflate:DecodeForWoWAddonChannel(encoded)
	if not decoded then return end
	local decompressed = deflate:DecompressDeflate(decoded)
	if not decompressed then return end
	local ok, data = serializer:Deserialize(decompressed)
	if not ok or type(data) ~= "table" then return end
	local cat = data.category or data.cat or data
	if type(cat) ~= "table" then return end
	sanitiseCategory(cat)
	local newId = getNextCategoryId()
	addon.db["buffTrackerCategories"][newId] = cat
	addon.db["buffTrackerOrder"][newId] = data.order or {}
	addon.db["buffTrackerEnabled"][newId] = true
	addon.db["buffTrackerLocked"][newId] = false

	addon.db["buffTrackerSounds"][newId] = {}
	addon.db["buffTrackerSoundsEnabled"][newId] = {}
	local missing = {}
	if type(data.sounds) == "table" and type(data.soundsEnabled) == "table" then
		for id, sound in pairs(data.sounds) do
			if addon.Aura.sounds[sound] then
				addon.db["buffTrackerSounds"][newId][id] = sound
				if data.soundsEnabled[id] then addon.db["buffTrackerSoundsEnabled"][newId][id] = true end
			else
				table.insert(missing, tostring(sound))
			end
		end
	end
	ensureAnchor(newId)
	rebuildAltMapping()
	scanBuffs()
	if #missing > 0 then print((L["ImportCategoryMissingSounds"] or "Missing sounds: %s"):format(table.concat(missing, ", "))) end
	return newId
end

local function previewImportCategory(encoded)
	if type(encoded) ~= "string" or encoded == "" then return end
	local deflate = LibStub("LibDeflate")
	local serializer = LibStub("AceSerializer-3.0")
	local decoded = deflate:DecodeForPrint(encoded) or deflate:DecodeForWoWChatChannel(encoded) or deflate:DecodeForWoWAddonChannel(encoded)
	if not decoded then return end
	local decompressed = deflate:DecompressDeflate(decoded)
	if not decompressed then return end
	local ok, data = serializer:Deserialize(decompressed)
	if not ok or type(data) ~= "table" then return end
	local cat = data.category or data.cat or data
	if type(cat) ~= "table" then return end
	local count = 0
	for _ in pairs(cat.buffs or {}) do
		count = count + 1
	end
	return cat.name or "", count
end

local treeGroup

local function getCategoryTree()
	local tree = {}
	for catId, cat in pairs(addon.db["buffTrackerCategories"]) do
		local text = cat.name
		if addon.db["buffTrackerEnabled"] and addon.db["buffTrackerEnabled"][catId] == false then text = "|cff808080" .. text .. "|r" end
		local node = { value = catId, text = text, children = {} }
		local buffs = {}
		for id, data in pairs(cat.buffs) do
			table.insert(buffs, { id = id, name = data.name })
		end
		if nil == addon.db["buffTrackerOrder"][catId] then addon.db["buffTrackerOrder"][catId] = {} end
		local orderIndex = {}
		for idx, bid in ipairs(addon.db["buffTrackerOrder"][catId]) do
			orderIndex[bid] = idx
		end
		table.sort(buffs, function(a, b)
			local ia = orderIndex[a.id] or math.huge
			local ib = orderIndex[b.id] or math.huge
			if ia ~= ib then return ia < ib end
			return a.name < b.name
		end)
		for _, info in ipairs(buffs) do
			table.insert(node.children, { value = catId .. "\001" .. info.id, text = info.name, icon = info.icon or (C_Spell.GetSpellInfo(info.id)).iconID })
		end
		table.insert(tree, node)
	end
	table.sort(tree, function(a, b) return a.value < b.value end)
	-- pseudo‑node for adding new categories
	table.insert(tree, {
		value = "ADD_CATEGORY",
		text = "|cff00ff00+ " .. (L["Add Category"] or "Add Category ..."),
	})
	table.insert(tree, {
		value = "IMPORT_CATEGORY",
		text = "|cff00ccff+ " .. (L["ImportCategory"] or "Import Category ..."),
	})
	return tree
end

local function refreshTree(selectValue)
	if not treeGroup then return end
	treeGroup:SetTree(getCategoryTree())
	if selectValue then
		treeGroup:SelectByValue(tostring(selectValue))
		-- C_Timer.After(0, function()
		treeGroup:Select(selectValue)
		--  end)
	end
end

local function handleDragDrop(src, dst)
	if not src or not dst then return end

	local sCat, _, sBuff = strsplit("\001", src)
	local dCat, _, dBuff = strsplit("\001", dst)
	sCat = tonumber(sCat)
	dCat = tonumber(dCat)
	if not sBuff then return end
	sBuff = tonumber(sBuff)
	if dBuff then dBuff = tonumber(dBuff) end

	local srcCat = addon.db["buffTrackerCategories"][sCat]
	local dstCat = addon.db["buffTrackerCategories"][dCat]
	if not srcCat or not dstCat then return end

	local buffData = srcCat.buffs[sBuff]
	if not buffData then return end

	srcCat.buffs[sBuff] = nil
	addon.db["buffTrackerOrder"][sCat] = addon.db["buffTrackerOrder"][sCat] or {}
	for i, v in ipairs(addon.db["buffTrackerOrder"][sCat]) do
		if v == sBuff then
			table.remove(addon.db["buffTrackerOrder"][sCat], i)
			break
		end
	end

	dstCat.buffs[sBuff] = buffData
	addon.db["buffTrackerOrder"][dCat] = addon.db["buffTrackerOrder"][dCat] or {}
	local insertPos = #addon.db["buffTrackerOrder"][dCat] + 1
	if dBuff then
		for i, v in ipairs(addon.db["buffTrackerOrder"][dCat]) do
			if v == dBuff then
				insertPos = i
				break
			end
		end
	end
	table.insert(addon.db["buffTrackerOrder"][dCat], insertPos, sBuff)

	rebuildAltMapping()
	refreshTree(selectedCategory)
	scanBuffs()
end

function addon.Aura.functions.buildCategoryOptions(container, catId)
	local cat = getCategory(catId)
	if not cat then return end
	local core = addon.functions.createContainer("InlineGroup", "Flow")
	container:AddChild(core)

	local enableCB = addon.functions.createCheckboxAce(L["EnableBuffTracker"]:format(cat.name), addon.db["buffTrackerEnabled"][catId], function(self, _, val)
		addon.db["buffTrackerEnabled"][catId] = val
		for id, anchor in pairs(anchors) do
			if addon.db["buffTrackerEnabled"][id] then
				anchor:Show()
			else
				anchor:Hide()
			end
		end
		applyLockState()
		scanBuffs()
		refreshTree(selectedCategory)
		container:ReleaseChildren()
		addon.Aura.functions.buildCategoryOptions(container, catId)
	end)
	core:AddChild(enableCB)

	if addon.db["buffTrackerEnabled"][catId] then
		local lockCB = addon.functions.createCheckboxAce(L["buffTrackerLocked"], addon.db["buffTrackerLocked"][catId], function(self, _, val)
			addon.db["buffTrackerLocked"][catId] = val
			applyLockState()
		end)
		core:AddChild(lockCB)
	end

	local nameEdit = addon.functions.createEditboxAce(L["CategoryName"], cat.name, function(self, _, text)
		if text ~= "" then
			cat.name = text
			changeAnchorName(catId)
		end

		refreshTree(catId)
		container:ReleaseChildren()
		addon.Aura.functions.buildCategoryOptions(container, catId)
	end)
	core:AddChild(nameEdit)

	local sizeSlider = addon.functions.createSliderAce(L["buffTrackerIconSizeHeadline"] .. ": " .. cat.size, cat.size, 0, 100, 1, function(self, _, val)
		cat.size = val
		self:SetLabel(L["buffTrackerIconSizeHeadline"] .. ": " .. val)
		applySize(catId)
	end)
	core:AddChild(sizeSlider)

	local dirDrop = addon.functions.createDropdownAce(L["GrowthDirection"], { LEFT = "LEFT", RIGHT = "RIGHT", UP = "UP", DOWN = "DOWN" }, nil, function(self, _, val)
		cat.direction = val
		updatePositions(catId)
	end)
	dirDrop:SetValue(cat.direction)
	dirDrop:SetRelativeWidth(0.4)
	core:AddChild(dirDrop)

	local spellEdit = addon.functions.createEditboxAce(L["AddSpellID"], nil, function(self, _, text)
		local id = tonumber(text)
		if id then
			addBuff(catId, id)
			refreshTree(catId)
			container:ReleaseChildren()
			addon.Aura.functions.buildCategoryOptions(container, catId)
		end
		self:SetText("")
	end)
	spellEdit:SetRelativeWidth(0.6)
	core:AddChild(spellEdit)

	local exportBtn = addon.functions.createButtonAce(L["ExportCategory"], 150, function()
		local data = exportCategory(catId)
		if not data then return end
		StaticPopupDialogs["EQOL_EXPORT_CATEGORY"] = StaticPopupDialogs["EQOL_EXPORT_CATEGORY"]
			or {
				text = L["ExportCategory"],
				button1 = CLOSE,
				hasEditBox = true,
				editBoxWidth = 320,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
			}
		StaticPopupDialogs["EQOL_EXPORT_CATEGORY"].OnShow = function(self)
			self:SetFrameStrata("FULLSCREEN_DIALOG")
			self.editBox:SetText(data)
			self.editBox:HighlightText()
			self.editBox:SetFocus()
		end
		StaticPopup_Show("EQOL_EXPORT_CATEGORY")
	end)
	core:AddChild(exportBtn)

	local shareBtn = addon.functions.createButtonAce(L["ShareCategory"] or "Share Category", 150, function() ShareCategory(catId) end)
	core:AddChild(shareBtn)

	local delBtn = addon.functions.createButtonAce(L["DeleteCategory"], 150, function()
		local catName = addon.db["buffTrackerCategories"][catId].name or ""
		StaticPopupDialogs["EQOL_DELETE_CATEGORY"] = StaticPopupDialogs["EQOL_DELETE_CATEGORY"]
			or {
				text = L["DeleteCategoryConfirm"],
				button1 = YES,
				button2 = CANCEL,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
			}
		StaticPopupDialogs["EQOL_DELETE_CATEGORY"].OnShow = function(self) self:SetFrameStrata("FULLSCREEN_DIALOG") end
		StaticPopupDialogs["EQOL_DELETE_CATEGORY"].OnAccept = function()
			-- clean up all buff data for this category
			for buffId in pairs(addon.db["buffTrackerCategories"][catId].buffs or {}) do
				addon.db["buffTrackerHidden"][buffId] = nil
			end
			addon.db["buffTrackerCategories"][catId] = nil
			addon.db["buffTrackerOrder"][catId] = nil
			addon.db["buffTrackerSounds"][catId] = nil
			addon.db["buffTrackerSoundsEnabled"][catId] = nil
			addon.db["buffTrackerEnabled"][catId] = nil
			addon.db["buffTrackerLocked"][catId] = nil
			if anchors[catId] then
				anchors[catId]:Hide()
				anchors[catId] = nil
			end
			selectedCategory = next(addon.db["buffTrackerCategories"]) or 1
			rebuildAltMapping()
			refreshTree(selectedCategory)
			container:ReleaseChildren()
		end
		StaticPopup_Show("EQOL_DELETE_CATEGORY", catName)
	end)
	core:AddChild(delBtn)

	return core
end

function addon.Aura.functions.buildBuffOptions(container, catId, buffId)
	local buff = addon.db["buffTrackerCategories"][catId]["buffs"][buffId]
	if not buff then return end

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	container:AddChild(groupCore)

	local wrapper = addon.functions.createContainer("SimpleGroup", "List")
	groupCore:AddChild(wrapper)
	wrapper:SetFullWidth(true)
	wrapper:SetFullHeight(true)

	local label = AceGUI:Create("Label")
	label:SetText((buff.name or "") .. " (" .. buffId .. ")")
	wrapper:AddChild(label)

	addon.db["buffTrackerSounds"][catId] = addon.db["buffTrackerSounds"][catId] or {}
	addon.db["buffTrackerSoundsEnabled"][catId] = addon.db["buffTrackerSoundsEnabled"][catId] or {}

	local cbElement = addon.functions.createCheckboxAce(L["buffTrackerSoundsEnabled"], addon.db["buffTrackerSoundsEnabled"][catId][buffId], function(_, _, val)
		addon.db["buffTrackerSoundsEnabled"][catId][buffId] = val
		container:ReleaseChildren()
		addon.Aura.functions.buildBuffOptions(container, catId, buffId)
	end)
	wrapper:AddChild(cbElement)

	if addon.db["buffTrackerSoundsEnabled"][catId][buffId] then
		local soundList = {}
		for sname in pairs(addon.Aura.sounds or {}) do
			soundList[sname] = sname
		end
		local list, order = addon.functions.prepareListForDropdown(soundList)
		local dropSound = addon.functions.createDropdownAce(L["SoundFile"], list, order, function(self, _, val)
			addon.db["buffTrackerSounds"][catId][buffId] = val
			self:SetValue(val)
			local file = addon.Aura.sounds and addon.Aura.sounds[val]
			if file then PlaySoundFile(file, "Master") end
		end)
		dropSound:SetValue(addon.db["buffTrackerSounds"][catId][buffId])
		wrapper:AddChild(dropSound)
		wrapper:AddChild(addon.functions.createSpacerAce())
	end

	local cbCooldown = addon.functions.createCheckboxAce(L["buffTrackerShowCooldown"], buff.showCooldown, function(_, _, val)
		buff.showCooldown = val
		scanBuffs()
	end)
	local cbCharges = addon.functions.createCheckboxAce(L["buffTrackerShowCharges"], buff.showCharges == nil and addon.db["buffTrackerShowCharges"] or buff.showCharges, function(_, _, val)
		buff.showCharges = val
		scanBuffs()
	end)

	local alwaysCB = addon.functions.createCheckboxAce(L["buffTrackerAlwaysShow"], buff.showAlways, function(_, _, val)
		buff.showAlways = val
		cbCooldown:SetDisabled(not val)
		cbCharges:SetDisabled(not val)
		scanBuffs()
	end)
	wrapper:AddChild(alwaysCB)
	cbCooldown:SetDisabled(not buff.showAlways)
	cbCharges:SetDisabled(not buff.showAlways)
	wrapper:AddChild(cbCooldown)
	wrapper:AddChild(cbCharges)

	local cbGlow = addon.functions.createCheckboxAce(L["buffTrackerGlow"], buff.glow, function(_, _, val)
		buff.glow = val
		scanBuffs()
	end)
	wrapper:AddChild(cbGlow)

	local cbStacks = addon.functions.createCheckboxAce(L["buffTrackerShowStacks"], buff.showStacks == nil and addon.db["buffTrackerShowStacks"] or buff.showStacks, function(_, _, val)
		buff.showStacks = val
		scanBuffs()
	end)
	wrapper:AddChild(cbStacks)

	local cbTimer = addon.functions.createCheckboxAce(
		L["buffTrackerShowTimerText"],
		buff.showTimerText == nil and (addon.db["buffTrackerShowTimerText"] ~= nil and addon.db["buffTrackerShowTimerText"] or true) or buff.showTimerText,
		function(_, _, val)
			buff.showTimerText = val
			applyTimerText()
		end
	)
	wrapper:AddChild(cbTimer)

	local typeDrop = addon.functions.createDropdownAce(L["TrackType"], { BUFF = L["Buff"], DEBUFF = L["Debuff"] }, nil, function(self, _, val)
		buff.trackType = val
		scanBuffs()
	end)
	typeDrop:SetValue(buff.trackType or "BUFF")
	typeDrop:SetRelativeWidth(0.4)
	wrapper:AddChild(typeDrop)
	wrapper:AddChild(addon.functions.createSpacerAce())

	local function buildGroupUI(parent, group)
		group.join = group.join or "AND"

		local joinDrop = addon.functions.createDropdownAce(L["JoinType"], { AND = "AND", OR = "OR" }, nil, function(_, _, val)
			group.join = val
			container:ReleaseChildren()
			addon.Aura.functions.buildBuffOptions(container, catId, buffId)
			scanBuffs()
		end)
		joinDrop:SetValue(group.join)
		parent:AddChild(joinDrop)

		for idx, child in ipairs(group.conditions or {}) do
			if child.join then
				local sub = addon.functions.createContainer("InlineGroup", "List")
				parent:AddChild(sub)
				buildGroupUI(sub, child)

				local rem = addon.functions.createButtonAce(L["Remove"], 80, function()
					table.remove(group.conditions, idx)
					container:ReleaseChildren()
					addon.Aura.functions.buildBuffOptions(container, catId, buffId)
					scanBuffs()
				end)
				sub:AddChild(rem)
			else
				local row = addon.functions.createContainer("SimpleGroup", "Flow")
				row:SetFullWidth(true)
				local typeDrop = addon.functions.createDropdownAce(nil, { missing = L["ConditionMissing"], stack = L["ConditionStacks"], time = L["ConditionTime"] }, nil, function(_, _, val)
					child.type = val
					if val ~= "missing" and (child.value == nil or type(child.value) ~= "number") then
						child.value = 0
					elseif val == "missing" and type(child.value) ~= "boolean" then
						child.value = true
					end
					container:ReleaseChildren()
					addon.Aura.functions.buildBuffOptions(container, catId, buffId)
					scanBuffs()
				end)
				typeDrop:SetValue(child.type)
				typeDrop:SetRelativeWidth(0.3)
				row:AddChild(typeDrop)

				local ops = { [">"] = ">", ["<"] = "<", [">="] = ">=", ["<="] = "<=", ["=="] = "==", ["!="] = "!=" }
				if child.type == "missing" then ops = { ["=="] = "==", ["!="] = "!=" } end
				local opDrop = addon.functions.createDropdownAce(nil, ops, nil, function(_, _, val)
					child.operator = val
					scanBuffs()
				end)
				opDrop:SetValue(child.operator)
				opDrop:SetRelativeWidth(0.2)
				row:AddChild(opDrop)

				if child.type == "missing" then
					local boolDrop = addon.functions.createDropdownAce(nil, { ["true"] = L["True"], ["false"] = L["False"] }, nil, function(_, _, val)
						child.value = val == "true"
						scanBuffs()
					end)
					boolDrop:SetValue(tostring(child.value))
					boolDrop:SetRelativeWidth(0.3)
					row:AddChild(boolDrop)
				else
					local valEdit = addon.functions.createEditboxAce(nil, child.value and tostring(child.value) or "", function(self, _, text)
						local num = tonumber(text)
						child.value = num
						scanBuffs()
					end)
					valEdit:SetRelativeWidth(0.3)
					row:AddChild(valEdit)
				end

				local remIcon = AceGUI:Create("Icon")
				remIcon:SetLabel("")
				remIcon:SetImage("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
				remIcon:SetImageSize(16, 16)
				remIcon:SetRelativeWidth(0.2)
				remIcon:SetHeight(16)
				remIcon:SetCallback("OnClick", function()
					table.remove(group.conditions, idx)
					container:ReleaseChildren()
					addon.Aura.functions.buildBuffOptions(container, catId, buffId)
					scanBuffs()
				end)
				row:AddChild(remIcon)

				parent:AddChild(row)
			end
		end

		local addRow = addon.functions.createContainer("SimpleGroup", "Flow")
		addRow:SetFullWidth(true)
		local addCond = addon.functions.createButtonAce(L["AddCondition"], 120, function()
			table.insert(group.conditions, { type = "missing", operator = "==", value = true })
			container:ReleaseChildren()
			addon.Aura.functions.buildBuffOptions(container, catId, buffId)
			scanBuffs()
		end)
		addRow:AddChild(addCond)

		local addGrp = addon.functions.createButtonAce(L["AddGroup"], 120, function()
			table.insert(group.conditions, { join = "AND", conditions = {} })
			container:ReleaseChildren()
			addon.Aura.functions.buildBuffOptions(container, catId, buffId)
			scanBuffs()
		end)
		addRow:AddChild(addGrp)
		parent:AddChild(addRow)
	end

	buildGroupUI(wrapper, buff.conditions or { join = "AND", conditions = {} })
	wrapper:AddChild(addon.functions.createSpacerAce())

	local roleDrop = addon.functions.createDropdownAce(L["ShowForRole"], roleNames, nil, function(self, event, key, checked)
		buff.allowedRoles = buff.allowedRoles or {}
		buff.allowedRoles[key] = checked or nil
		scanBuffs()
	end)
	roleDrop:SetMultiselect(true)
	for r, val in pairs(buff.allowedRoles or {}) do
		if val then roleDrop:SetItemValue(r, true) end
	end
	roleDrop:SetRelativeWidth(0.7)
	wrapper:AddChild(roleDrop)
	wrapper:AddChild(addon.functions.createSpacerAce())

	local classDrop = addon.functions.createDropdownAce(L["ShowForClass"], classNames, nil, function(self, event, key, checked)
		buff.allowedClasses = buff.allowedClasses or {}
		buff.allowedClasses[key] = checked or nil
		scanBuffs()
	end)
	classDrop:SetMultiselect(true)
	for c, val in pairs(buff.allowedClasses or {}) do
		if val then classDrop:SetItemValue(c, true) end
	end
	classDrop:SetRelativeWidth(0.7)
	wrapper:AddChild(classDrop)
	wrapper:AddChild(addon.functions.createSpacerAce())

	local specDrop = addon.functions.createDropdownAce(L["ShowForSpec"], specNames, specOrder, function(self, event, key, checked)
		buff.allowedSpecs = buff.allowedSpecs or {}
		buff.allowedSpecs[key] = checked or nil
		scanBuffs()
	end)

	specDrop:SetMultiselect(true)
	for specID, val in pairs(buff.allowedSpecs or {}) do
		if val then specDrop:SetItemValue(specID, true) end
	end
	specDrop:SetRelativeWidth(0.7)
	wrapper:AddChild(specDrop)
	wrapper:AddChild(addon.functions.createSpacerAce())

	-- TODO 11.2: Replace IsSpellKnown* check with C_SpellBook.IsSpellInSpellBook
	-- if IsSpellKnown(buffId) or IsSpellKnownOrOverridesKnown(buffId) then
	-- 	local cbCast = addon.functions.createCheckboxAce(L["buffTrackerCastOnClick"], buff.castOnClick, function(_, _, val)
	-- 		buff.castOnClick = val
	-- 		scanBuffs()
	-- 	end)
	-- 	wrapper:AddChild(cbCast)
	-- end

	buff.altIDs = buff.altIDs or {}
	for _, altId in ipairs(buff.altIDs) do
		local row = addon.functions.createContainer("SimpleGroup", "Flow")
		row:SetFullWidth(true)
		local lbl = AceGUI:Create("Label")
		local altInfo = C_Spell.GetSpellInfo(altId)
		if altInfo then
			lbl:SetText(L["AltSpellIDs"] .. ": " .. altInfo.name .. " (" .. altId .. ")")
		else
			lbl:SetText(L["AltSpellIDs"] .. ": " .. altId)
		end
		lbl:SetRelativeWidth(0.7)
		row:AddChild(lbl)

		local removeIcon = AceGUI:Create("Icon")
		removeIcon:SetLabel("")
		removeIcon:SetImage("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
		removeIcon:SetImageSize(16, 16)
		removeIcon:SetRelativeWidth(0.3)
		removeIcon:SetHeight(16)
		removeIcon:SetCallback("OnClick", function()
			for i, v in ipairs(buff.altIDs) do
				if v == altId then
					table.remove(buff.altIDs, i)
					break
				end
			end
			rebuildAltMapping()
			container:ReleaseChildren()
			addon.Aura.functions.buildBuffOptions(container, catId, buffId)
		end)
		row:AddChild(removeIcon)
		wrapper:AddChild(row)
	end

	local altEdit = addon.functions.createEditboxAce(L["AddAltSpellID"], nil, function(self, _, text)
		local alt = tonumber(text)
		if alt then
			if not tContains(buff.altIDs, alt) then table.insert(buff.altIDs, alt) end
			rebuildAltMapping()
			self:SetText("")
			container:ReleaseChildren()
			addon.Aura.functions.buildBuffOptions(container, catId, buffId)
		end
	end)
	wrapper:AddChild(altEdit)

	local infoIcon = AceGUI:Create("Icon")
	infoIcon:SetImage("Interface\\FriendsFrame\\InformationIcon")
	infoIcon:SetImageSize(16, 16)
	infoIcon:SetWidth(16)
	infoIcon:SetCallback("OnEnter", function(widget)
		GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["AlternativeSpellInfo"])
		GameTooltip:Show()
	end)
	infoIcon:SetCallback("OnLeave", function() GameTooltip:Hide() end)
	wrapper:AddChild(infoIcon)

	wrapper:AddChild(addon.functions.createSpacerAce())

	local delBtn = addon.functions.createButtonAce(L["DeleteAura"], 150, function()
		removeBuff(catId, buffId)
		refreshTree(nil)
		container:ReleaseChildren()
	end)
	wrapper:AddChild(delBtn)

	container:DoLayout()
end

function addon.Aura.functions.addBuffTrackerOptions(container)
	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	wrapper:SetFullHeight(true)
	container:AddChild(wrapper)

	local left = addon.functions.createContainer("SimpleGroup", "Flow")
	left:SetWidth(300)
	left:SetFullHeight(true)
	wrapper:AddChild(left)

	treeGroup = AceGUI:Create("EQOL_DragTreeGroup")
	treeGroup:SetFullHeight(true)
	treeGroup:SetFullWidth(true)
	treeGroup:SetTreeWidth(200, true)
	treeGroup:SetTree(getCategoryTree())
	treeGroup:SetCallback("OnGroupSelected", function(widget, _, value)
		-- Handle click on pseudo‑node for adding new categories
		if value == "ADD_CATEGORY" then
			-- create a new category with default settings
			local newId = getNextCategoryId()
			addon.db["buffTrackerCategories"][newId] = {
				name = L["NewCategoryName"] or "New",
				point = "CENTER",
				x = 0,
				y = 0,
				size = 50,
				direction = "RIGHT",
				buffs = {},
			}
			addon.db["buffTrackerEnabled"][newId] = true
			addon.db["buffTrackerLocked"][newId] = false
			addon.db["buffTrackerSounds"][newId] = {}
			addon.db["buffTrackerSoundsEnabled"][newId] = {}
			ensureAnchor(newId)
			refreshTree(newId)
			return -- don’t build options for pseudo‑node
		elseif value == "IMPORT_CATEGORY" then
			StaticPopupDialogs["EQOL_IMPORT_CATEGORY"] = StaticPopupDialogs["EQOL_IMPORT_CATEGORY"]
				or {
					text = L["ImportCategory"],
					button1 = ACCEPT,
					button2 = CANCEL,
					hasEditBox = true,
					editBoxWidth = 320,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				}
			StaticPopupDialogs["EQOL_IMPORT_CATEGORY"].OnShow = function(self)
				self.editBox:SetText("")
				self.editBox:SetFocus()
				self.text:SetText(L["ImportCategory"])
			end
			StaticPopupDialogs["EQOL_IMPORT_CATEGORY"].EditBoxOnTextChanged = function(editBox)
				local frame = editBox:GetParent()
				local name, count = previewImportCategory(editBox:GetText())
				if name then
					frame.text:SetFormattedText("%s\n%s", L["ImportCategory"], (L["ImportCategoryPreview"] or "Category: %s (%d auras)"):format(name, count))
				else
					frame.text:SetText(L["ImportCategory"])
				end
			end
			StaticPopupDialogs["EQOL_IMPORT_CATEGORY"].OnAccept = function(self)
				local text = self.editBox:GetText()
				local id = importCategory(text)
				if id then
					refreshTree(id)
				else
					print(L["ImportCategoryError"] or "Invalid string")
				end
			end
			StaticPopup_Show("EQOL_IMPORT_CATEGORY")
			return
		end

		local catId, _, buffId = strsplit("\001", value)
		catId = tonumber(catId)
		selectedCategory = catId
		addon.db["buffTrackerSelectedCategory"] = catId
		widget:ReleaseChildren()

		local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
		scroll:SetFullWidth(true)
		scroll:SetFullHeight(true)
		widget:AddChild(scroll)

		if buffId then
			addon.Aura.functions.buildBuffOptions(scroll, catId, tonumber(buffId))
		else
			addon.Aura.functions.buildCategoryOptions(scroll, catId)
		end
	end)
	treeGroup:SetCallback("OnDragDrop", function(_, _, src, dst) handleDragDrop(src, dst) end)

	left:AddChild(treeGroup)

	local ok = treeGroup:SelectByValue(tostring(selectedCategory))
	if not ok then
		-- fallback: pick first root node from current tree
		local tree = treeGroup.tree
		if tree and tree[1] and tree[1].value then treeGroup:SelectByValue(tree[1].value) end
	end
end

for id in pairs(addon.db["buffTrackerCategories"]) do
	applySize(id)
end
applyLockState()
applyTimerText()

-- ---------------------------------------------------------------------------
-- Share Aura-Category via Chat & Addon-Channel
-- ---------------------------------------------------------------------------
local COMM_PREFIX = "EQOLBTSHARE"
local AceComm = LibStub("AceComm-3.0")

local incoming = {}
local pending = {}

local function getCatName(catId)
	local cat = addon.db["buffTrackerCategories"][catId]
	return cat and cat.name or tostring(catId)
end

ShareCategory = function(catId, targetPlayer)
	local addonEncoded = exportCategory(catId, "addon")
	if not addonEncoded then return end

	local label = ("%s - %s"):format(UnitName("player"), getCatName(catId))
	local placeholder = ("[EQOL: %s]"):format(label)
	ChatFrame_OpenChat(placeholder)

	local pktID = tostring(time() * 1000):gsub("%D", "")
	pending[label] = pktID

	local dist, target = "WHISPER", targetPlayer
	if not targetPlayer then
		if IsInRaid(LE_PARTY_CATEGORY_HOME) then
			dist = "RAID"
		elseif IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
			dist = "INSTANCE_CHAT"
		elseif IsInGroup() then
			dist = "PARTY"
		elseif IsInGuild() then
			dist = "GUILD"
		else
			target = UnitName("player")
		end
	end

	AceComm:SendCommMessage(COMM_PREFIX, ("<%s>%s"):format(pktID, addonEncoded), dist, target, "BULK")
end

local PATTERN = "%[EQOL: ([^%]]+)%]"

local function EQOL_ChatFilter(_, _, msg, ...)
	local newMsg, hits = msg:gsub(PATTERN, function(label) return ("|Hgarrmission:eqolaura:%s|h|cff00ff88[%s]|h|r"):format(label, label) end)
	if hits > 0 then return false, newMsg, ... end
end

for _, ev in ipairs({
	"CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER",
	"CHAT_MSG_SAY",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_GUILD",
	"CHAT_MSG_OFFICER",
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_WHISPER_INFORM",
}) do
	ChatFrame_AddMessageEventFilter(ev, EQOL_ChatFilter)
end

local function HandleEQOLLink(link, text, button, frame)
       local label = link:match("^garrmission:eqolaura:(.+)")
       if not label then return end

       local pktID = pending[label]
       if not (pktID and incoming[pktID]) then return end

       StaticPopupDialogs["EQOL_IMPORT_FROM_SHARE"] = StaticPopupDialogs["EQOL_IMPORT_FROM_SHARE"]
               or {
                       text = L["ImportCategory"],
                       button1 = ACCEPT,
                       button2 = CANCEL,
                       timeout = 0,
                       whileDead = true,
                       hideOnEscape = true,
                       preferredIndex = 3,
                       OnAccept = function(_, data)
                               local encoded = incoming[data]
                               incoming[data] = nil
                               pending[label] = nil
                               local newId = importCategory(encoded)
                               if newId then refreshTree(newId) end
                       end,
               }

       StaticPopupDialogs["EQOL_IMPORT_FROM_SHARE"].OnShow = function(self, data)
               local encoded = incoming[data]
               local name, count = previewImportCategory(encoded or "")
               if name then
                       self.text:SetFormattedText("%s\n%s", L["ImportCategory"], (L["ImportCategoryPreview"] or "Category: %s (%d auras)"):format(name, count))
               else
                       self.text:SetText(L["ImportCategory"])
               end
       end

       StaticPopup_Show("EQOL_IMPORT_FROM_SHARE", nil, nil, pktID)
end

hooksecurefunc("SetItemRef", HandleEQOLLink)

local function OnComm(prefix, message, dist, sender)
	if prefix ~= COMM_PREFIX then return end
	local pktID, payload = message:match("^<(%d+)>(.+)")
	if not pktID then return end
	incoming[pktID] = payload
end

AceComm:RegisterComm(COMM_PREFIX, OnComm)
