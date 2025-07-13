local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")
local AceGUI = addon.AceGUI

local selectedCategory = addon.db["buffTrackerSelectedCategory"] or 1

for _, cat in pairs(addon.db["buffTrackerCategories"]) do
	for _, buff in pairs(cat.buffs or {}) do
		if not buff.trackType then buff.trackType = "BUFF" end
		if not buff.allowedSpecs then buff.allowedSpecs = {} end
		if not buff.allowedClasses then buff.allowedClasses = {} end
		if not buff.allowedRoles then buff.allowedRoles = {} end
	end
end

local anchors = {}
local activeBuffFrames = {}
local auraInstanceMap = {}
local altToBase = {}
local spellToCat = {}

local LSM = LibStub("LibSharedMedia-3.0")

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

local function getCategory(id) return addon.db["buffTrackerCategories"][id] end

local function rebuildAltMapping()
	wipe(altToBase)
	wipe(spellToCat)
	for catId, cat in pairs(addon.db["buffTrackerCategories"]) do
		for baseId, buff in pairs(cat.buffs or {}) do
			spellToCat[baseId] = spellToCat[baseId] or {}
			spellToCat[baseId][catId] = true
			if buff.altIDs then
				for _, altId in ipairs(buff.altIDs) do
					altToBase[altId] = baseId
				end
			end
		end
	end
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
	anchor.text:SetText(L["DragToPosition"])

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
	for _, frame in pairs(activeBuffFrames[id]) do
		frame:SetSize(size, size)
		frame.cd:SetAllPoints(frame)
	end
	updatePositions(id)
end

local function createBuffFrame(icon, parent, size, castOnClick, spellID)
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
	frame.cd = cd

	frame.castOnClick = castOnClick
	if castOnClick then
		frame:SetAttribute("type", "spell")
		frame:SetAttribute("spell", spellID)
		frame:EnableMouse(true)
		frame:RegisterForClicks("AnyUp", "AnyDown")
		frame:SetScript("PostClick", function() C_Timer.After(0.1, addon.Aura.scanBuffs) end)
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

local function updateBuff(catId, id)
	local cat = getCategory(catId)
	local buff = cat and cat.buffs and cat.buffs[id]
	if buff and not buffAllowed(buff) then
		if activeBuffFrames[catId] and activeBuffFrames[catId][id] then activeBuffFrames[catId][id]:Hide() end
		return
	end

	local aura = C_UnitAuras.GetPlayerAuraBySpellID(id)
	local triggeredId = id
	if not aura and buff and buff.altIDs then
		for _, altId in ipairs(buff.altIDs) do
			aura = C_UnitAuras.GetPlayerAuraBySpellID(altId)
			if aura then
				triggeredId = altId
				break
			end
		end
	end
	if aura then
		local tType = buff and buff.trackType or (cat and cat.trackType) or "BUFF"
		if tType == "DEBUFF" and not aura.isHarmful then
			aura = nil
		elseif tType == "BUFF" and not aura.isHelpful then
			aura = nil
		end
	end

	activeBuffFrames[catId] = activeBuffFrames[catId] or {}
	local frame = activeBuffFrames[catId][id]
	local prevInst = frame and frame.auraInstanceID
	if prevInst then auraInstanceMap[prevInst] = nil end
	local wasShown = frame and frame:IsShown()
	local wasActive = frame and frame.isActive

	if buff and buff.showAlways then
		local icon = buff.icon or (aura and aura.icon)
		if not frame then
			frame = createBuffFrame(icon, ensureAnchor(catId), getCategory(catId).size, false, id)
			activeBuffFrames[catId][id] = frame
		end
		frame.icon:SetTexture(icon)
		if aura then
			if aura.duration and aura.duration > 0 then
				frame.cd:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
			else
				frame.cd:Clear()
			end
			frame.icon:SetDesaturated(false)
			frame.icon:SetAlpha(1)
			if not wasActive then playBuffSound(catId, id, triggeredId) end
			frame.isActive = true
		else
			frame.cd:Clear()
			frame.icon:SetDesaturated(true)
			frame.icon:SetAlpha(0.5)
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
	elseif buff and buff.showWhenMissing then
		if aura then
			if frame then
				frame.isActive = false
				ActionButton_HideOverlayGlow(frame)
				frame:Hide()
			end
		else
			local icon = buff.icon
			local shouldSecure = buff.castOnClick and (IsSpellKnown(id) or IsSpellKnownOrOverridesKnown(id))
			if not frame or frame.castOnClick ~= shouldSecure then
				frame = createBuffFrame(icon, ensureAnchor(catId), getCategory(catId).size, shouldSecure, id)
				activeBuffFrames[catId][id] = frame
			end
			frame.icon:SetTexture(icon)
			frame.icon:SetDesaturated(false)
			frame.icon:SetAlpha(1)
			frame.cd:Clear()
			if shouldSecure then
				frame:EnableMouse(true)
				frame:RegisterForClicks("AnyUp", "AnyDown")
			end
			if not wasShown then playBuffSound(catId, id, triggeredId) end
			frame.isActive = true
			if buff.glow then
				ActionButton_ShowOverlayGlow(frame)
			else
				ActionButton_HideOverlayGlow(frame)
			end
			frame:Show()
		end
	else
		if aura then
			local icon = buff and buff.icon or aura.icon
			if not frame then
				frame = createBuffFrame(icon, ensureAnchor(catId), getCategory(catId).size, false, id)
				activeBuffFrames[catId][id] = frame
			end
			frame.icon:SetTexture(icon)
			frame.icon:SetDesaturated(false)
			frame.icon:SetAlpha(1)
			if aura.duration and aura.duration > 0 then
				frame.cd:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
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
			if frame then
				frame.isActive = false
				ActionButton_HideOverlayGlow(frame)
				frame:Hide()
			end
		end
	end

	if frame then
		if aura then
			frame.auraInstanceID = aura.auraInstanceID
			auraInstanceMap[aura.auraInstanceID] = { catId = catId, buffId = id }
		else
			frame.auraInstanceID = nil
		end
	end
end

local function scanBuffs()
	for catId, cat in pairs(addon.db["buffTrackerCategories"]) do
		if addon.db["buffTrackerEnabled"][catId] and categoryAllowed(cat) then
			for id in pairs(cat.buffs) do
				if not addon.db["buffTrackerHidden"][id] then
					updateBuff(catId, id)
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
end

addon.Aura.buffAnchors = anchors
addon.Aura.scanBuffs = scanBuffs

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, unit, ...)
	if event == "PLAYER_LOGIN" or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
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
			C_Timer.After(1, scanBuffs)
			return
		end
	end

	if event == "UNIT_AURA" and unit == "player" then
		local eventInfo = ...
		if eventInfo then
			local changed = {}
			for _, aura in ipairs(eventInfo.addedAuras or {}) do
				local id = altToBase[aura.spellId] or aura.spellId
				changed[id] = true
			end
			for _, inst in ipairs(eventInfo.updatedAuraInstanceIDs or {}) do
				local data = C_UnitAuras.GetAuraDataByAuraInstanceID("player", inst)
				if data then
					local id = altToBase[data.spellId] or data.spellId
					changed[id] = true
				elseif auraInstanceMap[inst] then
					changed[auraInstanceMap[inst].buffId] = true
				end
			end
			for _, inst in ipairs(eventInfo.removedAuraInstanceIDs or {}) do
				if auraInstanceMap[inst] then changed[auraInstanceMap[inst].buffId] = true end
				auraInstanceMap[inst] = nil
			end

			local updated = {}
			for spellId in pairs(changed) do
				for catId in pairs(spellToCat[spellId] or {}) do
					local cat = addon.db["buffTrackerCategories"][catId]
					if addon.db["buffTrackerEnabled"][catId] and categoryAllowed(cat) then
						if not addon.db["buffTrackerHidden"][spellId] then
							updateBuff(catId, spellId)
						elseif activeBuffFrames[catId] and activeBuffFrames[catId][spellId] then
							activeBuffFrames[catId][spellId]:Hide()
						end
						updated[catId] = true
					end
				end
			end

			for catId in pairs(updated) do
				updatePositions(catId)
				if anchors[catId] then anchors[catId]:Show() end
			end
			return
		end
	end

	scanBuffs()
end)
eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")

local function addBuff(catId, id)
	-- get spell name and icon once
	local spellData = C_Spell.GetSpellInfo(id)
	if not spellData then return end

	local cat = getCategory(catId)
	if not cat then return end

	cat.buffs[id] = {
		name = spellData.name,
		icon = spellData.iconID,
		altIDs = {},
		showWhenMissing = false,
		showAlways = false,
		glow = false,
		castOnClick = false,
		trackType = "BUFF",
		allowedSpecs = {},
		allowedClasses = {},
		allowedRoles = {},
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
	rebuildAltMapping()
	scanBuffs()
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
	return tree
end

local function refreshTree(selectValue)
	if not treeGroup then return end
	treeGroup:SetTree(getCategoryTree())
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
	end)
	core:AddChild(enableCB)

	local lockCB = addon.functions.createCheckboxAce(L["buffTrackerLocked"], addon.db["buffTrackerLocked"][catId], function(self, _, val)
		addon.db["buffTrackerLocked"][catId] = val
		applyLockState()
	end)
	core:AddChild(lockCB)

	local nameEdit = addon.functions.createEditboxAce(L["CategoryName"], cat.name, function(self, _, text)
		if text ~= "" then cat.name = text end
		refreshTree(catId)
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
		StaticPopupDialogs["EQOL_DELETE_CATEGORY"].OnAccept = function()
			addon.db["buffTrackerCategories"][catId] = nil
			addon.db["buffTrackerOrder"][catId] = nil
			if anchors[catId] then
				anchors[catId]:Hide()
				anchors[catId] = nil
			end
			selectedCategory = next(addon.db["buffTrackerCategories"]) or 1
			rebuildAltMapping()
			refreshTree(selectedCategory)
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

	local cbMissing, cbAlways
	cbMissing = addon.functions.createCheckboxAce(L["buffTrackerShowWhenMissing"], buff.showWhenMissing, function(_, _, val)
		buff.showWhenMissing = val
		if val then
			buff.showAlways = false
			if cbAlways then cbAlways:SetValue(false) end
		end
		scanBuffs()
	end)
	wrapper:AddChild(cbMissing)

	cbAlways = addon.functions.createCheckboxAce(L["buffTrackerAlwaysShow"], buff.showAlways, function(_, _, val)
		buff.showAlways = val
		if val then
			buff.showWhenMissing = false
			if cbMissing then cbMissing:SetValue(false) end
		end
		scanBuffs()
	end)
	wrapper:AddChild(cbAlways)

	local cbGlow = addon.functions.createCheckboxAce(L["buffTrackerGlow"], buff.glow, function(_, _, val)
		buff.glow = val
		scanBuffs()
	end)
	wrapper:AddChild(cbGlow)

	local typeDrop = addon.functions.createDropdownAce(L["TrackType"], { BUFF = L["Buff"], DEBUFF = L["Debuff"] }, nil, function(self, _, val)
		buff.trackType = val
		scanBuffs()
	end)
	typeDrop:SetValue(buff.trackType or "BUFF")
	typeDrop:SetRelativeWidth(0.4)
	wrapper:AddChild(typeDrop)
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

	wrapper:AddChild(addon.functions.createSpacerAce())

	local delBtn = addon.functions.createButtonAce(L["DeleteAura"], 150, function()
		removeBuff(catId, buffId)
		refreshTree(catId)
	end)
	wrapper:AddChild(delBtn)
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
			local newId = (#addon.db["buffTrackerCategories"] or 0) + 1
			addon.db["buffTrackerCategories"][newId] = {
				name = L["NewCategoryName"] or "New",
				point = "CENTER",
				x = 0,
				y = 0,
				size = 36,
				direction = "RIGHT",
				buffs = {},
			}
			ensureAnchor(newId)
			refreshTree(newId) -- rebuild tree and select new node
			return -- don’t build options for pseudo‑node
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
