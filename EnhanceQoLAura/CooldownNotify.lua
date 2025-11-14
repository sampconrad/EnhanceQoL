-- CooldownNotify.lua - Notify when cooldowns are ready
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end
if addon.variables.isMidnight then return end

addon.Aura = addon.Aura or {}
addon.Aura.CooldownNotify = addon.Aura.CooldownNotify or {}
local CN = addon.Aura.CooldownNotify
CN.functions = CN.functions or {}

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")
local AceGUI = addon.AceGUI
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local cooldowns = {}
local animating = {}
local treeGroup
local anchors = {}
-- store the category id of the cooldown currently shown
local currentCatId
-- list of spellIDs currently known to the player
local playerSpells = {}
-- forward declaration for functions referenced before definition
local applyAnchor
local ShareCategory
local importCategory
local exportCategory
local GetItemInfo = C_Item.GetItemInfo
local previewImportCategory

for _, cat in pairs(addon.db.cooldownNotifyCategories or {}) do
	if cat.useAdvancedTracking == nil then cat.useAdvancedTracking = true end
	cat.spells = cat.spells or {}
	local tmp = {}
	for id, info in pairs(cat.spells) do
		local num = tonumber(id)
		if num then
			if type(info) == "table" then
				if not info.trackType and num < 0 then info.trackType = "ITEM" end
				if not info.slot and num < 0 then info.slot = -num end
				tmp[num] = info
			elseif num < 0 then
				tmp[num] = { trackType = "ITEM", slot = -num }
			else
				tmp[num] = true
			end
		end
	end
	cat.spells = tmp
	cat.ignoredSpells = cat.ignoredSpells or {}
end

local DCP = CreateFrame("Frame", nil, UIParent)
DCP:SetPoint("CENTER")
DCP:SetSize(75, 75)
DCP:SetAlpha(0)
DCP:Hide()
DCP:SetScript("OnEvent", function(self, event, ...)
	if CN[event] then CN[event](CN, ...) end
end)

DCP.texture = DCP:CreateTexture(nil, "BACKGROUND")
DCP.texture:SetAllPoints(DCP)

DCP.text = DCP:CreateFontString(nil, "ARTWORK")
DCP.text:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
DCP.text:SetShadowOffset(2, -2)
DCP.text:SetPoint("CENTER", DCP, "CENTER")
DCP.text:SetWidth(185)
DCP.text:SetJustifyH("CENTER")
DCP.text:SetTextColor(1, 1, 1)

local elapsed = 0
local runtimer = 0

-- Resolve and play a configured sound from multiple sources (internal table, LibSharedMedia, SOUNDKIT id/name)
local function playConfiguredSound(key)
	if not key then return end
	-- 1) Internal mapping table (string label -> file path)
	local path = addon.Aura and addon.Aura.sounds and addon.Aura.sounds[key]
	-- 2) LibSharedMedia lookup (e.g., "BigWigs: Alarm")
	if not path and LSM and LSM.Fetch then path = LSM:Fetch("sound", key, true) end
	if path then
		PlaySoundFile(path, "Master")
		return
	end
	-- 3) Numeric SOUNDKIT id
	local id = tonumber(key)
	if id then
		PlaySound(id, "Master")
		return
	end
	-- 4) SOUNDKIT name constant, e.g., "RAID_WARNING"
	if type(key) == "string" and SOUNDKIT and SOUNDKIT[key] then
		PlaySound(SOUNDKIT[key], "Master")
		return
	end
	-- If nothing matched, silently ignore to avoid Lua errors
end

local function IsAnimatingCooldown(name, catId)
	for _, info in ipairs(animating) do
		if info[2] == name and info[3] == catId then return true end
	end
	return false
end

local function BuildPlayerSpellList()
	wipe(playerSpells)
	for tab = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local spellBookInfo = C_SpellBook.GetSpellBookSkillLineInfo(tab)
		if not spellBookInfo.offSpecID and spellBookInfo.itemIndexOffset and spellBookInfo.numSpellBookItems then
			local offset, numSlots = spellBookInfo.itemIndexOffset, spellBookInfo.numSpellBookItems
			for j = offset + 1, offset + numSlots do
				local name, subName = C_SpellBook.GetSpellBookItemName(j, Enum.SpellBookSpellBank.Player)
				local spellID = select(3, C_SpellBook.GetSpellBookItemType(j, Enum.SpellBookSpellBank.Player))
				if spellID and not C_Spell.IsSpellPassive(spellID) then playerSpells[spellID] = true end
			end
		end
	end
end

local function OnUpdate(_, update)
	elapsed = elapsed + update
	if elapsed > 0.05 then
		for i, cd in pairs(cooldowns) do
			if cd.start then
				local remaining = cd.duration - (GetTime() - cd.start)
				local cat = addon.db.cooldownNotifyCategories[cd.catId] or {}
				local threshold = cat.remainingCooldownWhenNotified or 0
				if remaining <= threshold then
					if not IsAnimatingCooldown(cd.name, cd.catId) then
						table.insert(animating, {
							cd.texture,
							cd.name,
							cd.catId,
							cd.id,
							cat.fadeInTime or 0.3,
							cat.fadeOutTime or 0.7,
							cat.maxAlpha or 0.7,
							cat.animScale or 1.5,
							cat.iconSize or 75,
							cat.holdTime or 0,
						})
					end
					cooldowns[i] = nil
				end
			else
				cooldowns[i] = nil
			end
		end
		elapsed = 0
		if #animating == 0 and next(cooldowns) == nil then
			DCP:SetScript("OnUpdate", nil)
			DCP:Hide()
			return
		end
	end

	if #animating > 0 then
		runtimer = runtimer + update
		local info = animating[1]
		local cat = addon.db.cooldownNotifyCategories[info[3]] or {}
		local fadeInTime = info[5] or 0.3
		local fadeOutTime = info[6] or 0.7
		local maxAlpha = info[7] or 0.7
		local animScale = info[8] or 1.5
		local iconSize = info[9] or 75
		local holdTime = info[10] or 0
		if runtimer > (fadeInTime + holdTime + fadeOutTime) then
			table.remove(animating, 1)
			runtimer = 0
			DCP.text:SetText(nil)
			DCP.texture:SetTexture(nil)
			DCP.texture:SetVertexColor(1, 1, 1)
			currentCatId = nil
		else
			if not DCP.texture:GetTexture() then
				currentCatId = info[3]
				if cat.showName and info[2] then
					local txt = info[2]
					if cat.customTextEnabled and cat.customText and cat.customText ~= "" then txt = cat.customText end
					DCP.text:SetText(txt)
				end
				DCP.texture:SetTexture(info[1])
				DCP.texture:SetVertexColor(1, 1, 1)
				local anch = cat.anchor or {}
				DCP:SetPoint(anch.point or "CENTER", UIParent, anch.point or "CENTER", anch.x or 0, anch.y or 0)
				DCP:SetSize(iconSize, iconSize)
				DCP:Show()
				local soundKey
				if addon.db.cooldownNotifySoundsEnabled[info[3]] and addon.db.cooldownNotifySoundsEnabled[info[3]][info[4]] then
					soundKey = addon.db.cooldownNotifySounds[info[3]] and addon.db.cooldownNotifySounds[info[3]][info[4]]
				end
				if soundKey then playConfiguredSound(soundKey) end
			end
			local alpha = maxAlpha
			if runtimer < fadeInTime then
				alpha = maxAlpha * (runtimer / fadeInTime)
			elseif runtimer >= fadeInTime + holdTime then
				alpha = maxAlpha - (maxAlpha * ((runtimer - holdTime - fadeInTime) / fadeOutTime))
			end
			DCP:SetAlpha(alpha)
			local scale = iconSize + (iconSize * ((animScale - 1) * (runtimer / (fadeInTime + holdTime + fadeOutTime))))
			DCP:SetSize(scale, scale)
		end
	end
end

local function ensureAnchor(id)
	if anchors[id] then return anchors[id] end

	local cat = addon.db.cooldownNotifyCategories[id]
	if not cat then return nil end

	cat.anchor = cat.anchor or { point = "CENTER", x = 0, y = 0 }

	local anchor = CreateFrame("Frame", "EQOLCooldownNotifyAnchor" .. id, UIParent, "BackdropTemplate")
	anchor:SetSize(cat.iconSize or 75, cat.iconSize or 75)
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
		cat.anchor.point = point
		cat.anchor.x = xOfs
		cat.anchor.y = yOfs
		applyAnchor(id)
	end)

	anchor:SetScript("OnShow", function()
		if cat.anchor then
			anchor:ClearAllPoints()
			anchor:SetPoint(cat.anchor.point, UIParent, cat.anchor.point, cat.anchor.x, cat.anchor.y)
		end
	end)

	if cat.anchor then
		anchor:ClearAllPoints()
		anchor:SetPoint(cat.anchor.point, UIParent, cat.anchor.point, cat.anchor.x, cat.anchor.y)
	end

	anchors[id] = anchor
	return anchor
end

local function changeAnchorName(id)
	local anchor = ensureAnchor(id)
	if not anchor then return end
	local cat = addon.db.cooldownNotifyCategories[id]
	if not cat then return end
	if anchor.text then anchor.text:SetText(L["DragToPosition"]:format("|cffffd700" .. (cat.name or "") .. "|r")) end
end

local function applyLockState()
	for id, anchor in pairs(anchors) do
		if not addon.db.cooldownNotifyEnabled[id] then
			anchor:Hide()
		elseif addon.db.cooldownNotifyLocked[id] then
			anchor:RegisterForDrag()
			anchor:SetMovable(false)
			anchor:EnableMouse(false)
			anchor:SetScript("OnDragStart", nil)
			anchor:SetScript("OnDragStop", nil)
			anchor:SetBackdropColor(0, 0, 0, 0)
			if anchor.text then anchor.text:Hide() end
			anchor:Show()
		else
			anchor:RegisterForDrag("LeftButton")
			anchor:SetMovable(true)
			anchor:EnableMouse(true)
			anchor:SetScript("OnDragStart", anchor.StartMoving)
			anchor:SetScript("OnDragStop", function(self)
				self:StopMovingOrSizing()
				local cat = addon.db.cooldownNotifyCategories[id]
				if cat and cat.anchor then
					local point, _, _, xOfs, yOfs = self:GetPoint()
					cat.anchor.point = point
					cat.anchor.x = xOfs
					cat.anchor.y = yOfs
					applyAnchor(id)
				end
			end)
			anchor:SetBackdropColor(0, 0, 0, 0.6)
			if anchor.text then
				local cat = addon.db.cooldownNotifyCategories[id]
				anchor.text:SetText(L["DragToPosition"]:format("|cffffd700" .. ((cat and cat.name) or "") .. "|r"))
				anchor.text:Show()
			end
			anchor:Show()
		end
	end
end

-- Throttle trinket cooldown checks to coalesce rapid events
local trinketUpdatePending = false
local function scheduleTrinketUpdate()
	if trinketUpdatePending then return end
	trinketUpdatePending = true
	C_Timer.After(0.10, function()
		trinketUpdatePending = false
		CN:SPELL_UPDATE_COOLDOWN(-13)
		CN:SPELL_UPDATE_COOLDOWN(-14)
	end)
end

local function updateEventRegistration()
	local anyEnabled
	for _, enabled in pairs(addon.db.cooldownNotifyEnabled or {}) do
		if enabled then
			anyEnabled = true
			break
		end
	end
	if anyEnabled then
		if not DCP:IsEventRegistered("SPELL_UPDATE_COOLDOWN") then
			DCP:RegisterEvent("SPELL_UPDATE_COOLDOWN")
			DCP:RegisterEvent("PLAYER_LOGIN")
			DCP:RegisterEvent("SPELLS_CHANGED")
			DCP:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
			DCP:RegisterEvent("BAG_UPDATE_COOLDOWN")
		end
	else
		if DCP:IsEventRegistered("SPELL_UPDATE_COOLDOWN") then
			DCP:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
			DCP:UnregisterEvent("PLAYER_LOGIN")
			DCP:UnregisterEvent("SPELLS_CHANGED")
			DCP:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
			DCP:UnregisterEvent("BAG_UPDATE_COOLDOWN")
		end
	end
end

local function applySize(id)
	local cat = addon.db.cooldownNotifyCategories[id]
	if not cat then return end
	local anchor = ensureAnchor(id)
	anchor:SetSize(cat.iconSize or 75, cat.iconSize or 75)
	if DCP:IsShown() and currentCatId == id then DCP:SetSize(cat.iconSize or 75, cat.iconSize or 75) end
end

function applyAnchor(id)
	local cat = addon.db.cooldownNotifyCategories[id]
	if not cat then return end
	local anchor = ensureAnchor(id)
	anchor:ClearAllPoints()
	anchor:SetPoint(cat.anchor.point, UIParent, cat.anchor.point, cat.anchor.x, cat.anchor.y)

	if DCP:IsShown() then
		if currentCatId == id then
			DCP:ClearAllPoints()
			DCP:SetPoint(cat.anchor.point or "CENTER", UIParent, cat.anchor.point or "CENTER", cat.anchor.x or 0, cat.anchor.y or 0)
		end
	else
		-- Update the cooldown frame position so it spawns at the new anchor
		DCP:ClearAllPoints()
		DCP:SetPoint(cat.anchor.point or "CENTER", UIParent, cat.anchor.point or "CENTER", cat.anchor.x or 0, cat.anchor.y or 0)
	end
end

function CN:SPELL_UPDATE_COOLDOWN(spellID)
	if not spellID then
		for cid, cat in pairs(addon.db.cooldownNotifyCategories or {}) do
			if addon.db.cooldownNotifyEnabled[cid] then
				if cat.useAdvancedTracking == false then
					for sid in pairs(playerSpells) do
						if not (cat.ignoredSpells and cat.ignoredSpells[sid]) then self:SPELL_UPDATE_COOLDOWN(sid) end
					end
				else
					for sid in pairs(cat.spells or {}) do
						self:SPELL_UPDATE_COOLDOWN(sid)
					end
				end
			end
		end
		scheduleTrinketUpdate()
		return
	end
	local found = false
	for catId, cat in pairs(addon.db.cooldownNotifyCategories or {}) do
		if addon.db.cooldownNotifyEnabled[catId] then
			local entry = cat.spells and cat.spells[spellID]
			if
				(cat.useAdvancedTracking ~= false and entry)
				or (cat.useAdvancedTracking == false and (playerSpells[spellID] or spellID < 0) and not (cat.ignoredSpells and cat.ignoredSpells[spellID]))
			then
				if (type(entry) == "table" and entry.trackType == "ITEM") or spellID < 0 then
					local slot = (type(entry) == "table" and entry.slot) or -spellID
					local start, duration, enabled = GetInventoryItemCooldown("player", slot)
					if enabled and duration and duration > 2 then
						local key = spellID .. ":" .. catId
						local texture = GetInventoryItemTexture("player", slot)
						local itemID = GetInventoryItemID and GetInventoryItemID("player", slot)
						local name = itemID and GetItemInfo(itemID)
						cooldowns[key] = {
							start = start,
							duration = duration,
							texture = texture,
							name = name,
							catId = catId,
							id = spellID,
						}
						found = true
					end
				else
					local cd = C_Spell.GetSpellCooldown(spellID)
					if cd and cd.isEnabled ~= 0 and cd.duration and cd.duration > 2 then
						local key = spellID .. ":" .. catId
						cooldowns[key] = {
							start = cd.startTime,
							duration = cd.duration,
							texture = C_Spell.GetSpellTexture(spellID),
							name = C_Spell.GetSpellName(spellID),
							catId = catId,
							id = spellID,
						}
						found = true
					end
				end
			end
		end
	end
	if found and not DCP:GetScript("OnUpdate") then
		DCP:SetScript("OnUpdate", OnUpdate)
		DCP:Show()
	end
end

function CN:PLAYER_LOGIN()
	BuildPlayerSpellList()
	for catId, cat in pairs(addon.db.cooldownNotifyCategories or {}) do
		if addon.db.cooldownNotifyEnabled[catId] then
			if cat.useAdvancedTracking == false then
				for spellID in pairs(playerSpells) do
					if not (cat.ignoredSpells and cat.ignoredSpells[spellID]) then self:SPELL_UPDATE_COOLDOWN(spellID) end
				end
			else
				for spellID in pairs(cat.spells or {}) do
					self:SPELL_UPDATE_COOLDOWN(spellID)
				end
			end
		end
	end
	scheduleTrinketUpdate()
end

function CN:SPELLS_CHANGED() BuildPlayerSpellList() end

function CN:PLAYER_EQUIPMENT_CHANGED(slot)
	if slot == 13 or slot == 14 then scheduleTrinketUpdate() end
end

function CN:BAG_UPDATE_COOLDOWN() scheduleTrinketUpdate() end

function CN.functions.addTrinketCooldown(catId, slot)
	local cat = addon.db.cooldownNotifyCategories[catId]
	if not cat then return end
	cat.spells = cat.spells or {}
	local id = -slot
	cat.spells[id] = { trackType = "ITEM", slot = slot }
	addon.db.cooldownNotifySounds[catId] = addon.db.cooldownNotifySounds[catId] or {}
	addon.db.cooldownNotifySoundsEnabled[catId] = addon.db.cooldownNotifySoundsEnabled[catId] or {}
	addon.db.cooldownNotifySounds[catId][id] = addon.db.cooldownNotifyDefaultSound
	addon.db.cooldownNotifySoundsEnabled[catId][id] = false
end

CN.frame = DCP

local function getCategoryTree()
	local tree = {}
	for catId, cat in pairs(addon.db.cooldownNotifyCategories or {}) do
		local text = cat.name
		if addon.db.cooldownNotifyEnabled[catId] == false then text = "|cff808080" .. text .. "|r" end
		local node = { value = catId, text = text, children = {} }

		local spells = {}
		for id in pairs(cat.spells or {}) do
			table.insert(spells, id)
		end
		table.sort(spells)
		for _, spellId in ipairs(spells) do
			local text, icon
			if spellId < 0 then
				local slot = -spellId
				local itemID = GetInventoryItemID("player", slot)
				local name = itemID and GetItemInfo(itemID)
				text = name or tostring(spellId)
				icon = GetInventoryItemTexture("player", slot)
			else
				local info = C_Spell.GetSpellInfo(spellId)
				text = info and info.name or tostring(spellId)
				icon = info and info.iconID
			end
			table.insert(node.children, {
				value = catId .. "\001" .. spellId,
				text = text,
				icon = icon,
			})
		end
		table.insert(tree, node)
	end

	table.sort(tree, function(a, b) return a.value < b.value end)
	table.insert(tree, { value = "ADD_CATEGORY", text = "|cff00ff00+ " .. (L["Add Category"] or "Add Category") })
	table.insert(tree, { value = "IMPORT_CATEGORY", text = "|cff00ccff+ " .. (L["ImportCategory"] or "Import Category") })
	return tree
end

local function refreshTree(selectValue)
	if not treeGroup then return end
	treeGroup:SetTree(getCategoryTree())
	if selectValue then treeGroup:SelectByValue(tostring(selectValue)) end
end

local function buildCategoryOptions(container, catId)
	addon.db.cooldownNotifySelectedCategory = catId
	local cat = addon.db.cooldownNotifyCategories[catId]
	local group = addon.functions.createContainer("SimpleGroup", "List")
	container:AddChild(group)

	local enableCB = addon.functions.createCheckboxAce(L["EnableCooldownNotify"]:format(cat.name), addon.db.cooldownNotifyEnabled[catId], function(_, _, val)
		addon.db.cooldownNotifyEnabled[catId] = val
		applyLockState()
		updateEventRegistration()
	end)
	group:AddChild(enableCB)

	local lockCB = addon.functions.createCheckboxAce(L["buffTrackerLocked"], addon.db.cooldownNotifyLocked[catId], function(_, _, val)
		addon.db.cooldownNotifyLocked[catId] = val
		applyLockState()
	end)
	group:AddChild(lockCB)

	local nameEdit = addon.functions.createEditboxAce(L["CategoryName"], cat.name, function(self, _, text)
		if text ~= "" then
			cat.name = text
			changeAnchorName(catId)
		end

		refreshTree(catId)
		container:ReleaseChildren()
		buildCategoryOptions(container, catId)
	end)
	group:AddChild(nameEdit)

	local advCB = addon.functions.createCheckboxAce(L["UseAdvancedTracking"] or "Use advanced tracking", cat.useAdvancedTracking ~= false, function(_, _, val)
		cat.useAdvancedTracking = val
		container:ReleaseChildren()
		buildCategoryOptions(container, catId)
	end)
	advCB:SetRelativeWidth(0.6)

	local infoIcon = AceGUI:Create("Icon")
	infoIcon:SetImage("Interface\\FriendsFrame\\InformationIcon")
	infoIcon:SetImageSize(16, 16)
	infoIcon:SetRelativeWidth(0.4)
	infoIcon:SetWidth(16)
	infoIcon:SetCallback("OnEnter", function(widget)
		GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["advancedTrackingInfo"])
		GameTooltip:Show()
	end)
	infoIcon:SetCallback("OnLeave", function() GameTooltip:Hide() end)

	local infoGroup = addon.functions.createContainer("SimpleGroup", "Flow")
	infoGroup:SetFullWidth(true)
	infoGroup:AddChild(advCB)
	infoGroup:AddChild(infoIcon)
	group:AddChild(infoGroup)

	local showNameCB = addon.functions.createCheckboxAce(L["ShowCooldownName"], cat.showName, function(_, _, val)
		cat.showName = val
		if not val then cat.customTextEnabled = false end
		container:ReleaseChildren()
		buildCategoryOptions(container, catId)
	end)
	group:AddChild(showNameCB)

	local customTextCB = addon.functions.createCheckboxAce(L["Show custom text"], cat.customTextEnabled, function(_, _, val)
		cat.customTextEnabled = val
		container:ReleaseChildren()
		buildCategoryOptions(container, catId)
	end)
	customTextCB:SetDisabled(not cat.showName)
	group:AddChild(customTextCB)

	local customTextEdit = addon.functions.createEditboxAce(L["Text"], cat.customText or "", function(_, _, text) cat.customText = text end)
	customTextEdit:SetDisabled(not cat.customTextEnabled or not cat.showName)
	group:AddChild(customTextEdit)

	local fadeSlider = addon.functions.createSliderAce(L["Fade In"], cat.fadeInTime or 0.3, 0, 2, 0.1, function(_, _, val) cat.fadeInTime = val end)
	group:AddChild(fadeSlider)
	local holdSlider = addon.functions.createSliderAce(L["Hold Time"], cat.holdTime or 0, 0, 2, 0.1, function(_, _, val) cat.holdTime = val end)
	group:AddChild(holdSlider)
	local fadeOutSlider = addon.functions.createSliderAce(L["Fade Out"], cat.fadeOutTime or 0.7, 0, 2, 0.1, function(_, _, val) cat.fadeOutTime = val end)
	group:AddChild(fadeOutSlider)
	local scaleSlider = addon.functions.createSliderAce(L["Scale"], cat.animScale or 1.5, 0.5, 3, 0.1, function(_, _, val) cat.animScale = val end)
	group:AddChild(scaleSlider)
	local sizeSlider = addon.functions.createSliderAce(HUD_EDIT_MODE_SETTING_ACTION_BAR_ICON_SIZE, cat.iconSize or 75, 20, 200, 1, function(_, _, val)
		cat.iconSize = val
		applySize(catId)
	end)
	group:AddChild(sizeSlider)

	local spellEdit = addon.functions.createEditboxAce(L["AddSpellID"], nil, function(self, _, text)
		local id = tonumber(text)
		if id then
			if id < 0 then
				CN.functions.addTrinketCooldown(catId, -id)
			else
				cat.spells[id] = true
				addon.db.cooldownNotifySounds[catId] = addon.db.cooldownNotifySounds[catId] or {}
				addon.db.cooldownNotifySoundsEnabled[catId] = addon.db.cooldownNotifySoundsEnabled[catId] or {}
				addon.db.cooldownNotifySounds[catId][id] = addon.db.cooldownNotifyDefaultSound
				addon.db.cooldownNotifySoundsEnabled[catId][id] = false
			end
			refreshTree(catId)
			container:ReleaseChildren()
			buildCategoryOptions(container, catId)
		end
		self:SetText("")
	end)
	spellEdit:SetRelativeWidth(0.6)
	group:AddChild(spellEdit)

	-- Action buttons in a 2-column flow (50% width each)
	local actionsRow = addon.functions.createContainer("SimpleGroup", "Flow")
	group:AddChild(actionsRow)

	local trinket13Btn = addon.functions.createButtonAce(L["TrackTrinketSlot"]:format(13), 150, function()
		CN.functions.addTrinketCooldown(catId, 13)
		refreshTree(catId)
		container:ReleaseChildren()
		buildCategoryOptions(container, catId)
	end)
	trinket13Btn:SetRelativeWidth(0.5)
	actionsRow:AddChild(trinket13Btn)

	local trinket14Btn = addon.functions.createButtonAce(L["TrackTrinketSlot"]:format(14), 150, function()
		CN.functions.addTrinketCooldown(catId, 14)
		refreshTree(catId)
		container:ReleaseChildren()
		buildCategoryOptions(container, catId)
	end)
	trinket14Btn:SetRelativeWidth(0.5)
	actionsRow:AddChild(trinket14Btn)

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
			local editBox = self.editBox or self.GetEditBox and self:GetEditBox()
			self:SetFrameStrata("TOOLTIP")
			editBox:SetText(data)
			editBox:HighlightText()
			editBox:SetFocus()
		end
		StaticPopup_Show("EQOL_EXPORT_CATEGORY")
	end)
	exportBtn:SetRelativeWidth(0.5)
	actionsRow:AddChild(exportBtn)

	local shareBtn = addon.functions.createButtonAce(L["ShareCategory"] or "Share Category", 150, function() ShareCategory(catId) end)
	shareBtn:SetRelativeWidth(0.5)
	actionsRow:AddChild(shareBtn)

	local testBtn = addon.functions.createButtonAce(L["Test"] or "Test", 150, function()
		ensureAnchor(catId)
		local tex, name
		local firstSpell = next(cat.spells)
		if firstSpell then
			if firstSpell < 0 then
				local slot = -firstSpell
				tex = GetInventoryItemTexture("player", slot)
				local itemID = GetInventoryItemID("player", slot)
				name = itemID and GetItemInfo(itemID)
			else
				tex = C_Spell.GetSpellTexture(firstSpell)
				name = C_Spell.GetSpellName(firstSpell)
			end
		end
		tex = tex or "Interface\\Icons\\INV_Misc_QuestionMark"
		name = name or L["Test"] or "Test"
		table.insert(animating, {
			tex,
			name,
			catId,
			0,
			cat.fadeInTime or 0.3,
			cat.fadeOutTime or 0.7,
			cat.maxAlpha or 0.7,
			cat.animScale or 1.5,
			cat.iconSize or 75,
			cat.holdTime or 0,
		})
		if not DCP:GetScript("OnUpdate") then
			DCP:SetScript("OnUpdate", OnUpdate)
			DCP:Show()
		end
	end)
	testBtn:SetRelativeWidth(0.5)
	actionsRow:AddChild(testBtn)

	local delBtn = addon.functions.createButtonAce(L["DeleteCategory"], 150, function()
		local catName = addon.db.cooldownNotifyCategories[catId].name or ""
		StaticPopupDialogs["EQOL_DELETE_CDN_CATEGORY"] = StaticPopupDialogs["EQOL_DELETE_CDN_CATEGORY"]
			or {
				text = L["DeleteCategoryConfirm"],
				button1 = YES,
				button2 = CANCEL,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
			}
		StaticPopupDialogs["EQOL_DELETE_CDN_CATEGORY"].OnShow = function(self) self:SetFrameStrata("TOOLTIP") end
		StaticPopupDialogs["EQOL_DELETE_CDN_CATEGORY"].OnAccept = function()
			addon.db.cooldownNotifyCategories[catId] = nil
			addon.db.cooldownNotifyEnabled[catId] = nil
			addon.db.cooldownNotifyLocked[catId] = nil
			addon.db.cooldownNotifyOrder[catId] = nil
			addon.db.cooldownNotifySounds[catId] = nil
			addon.db.cooldownNotifySoundsEnabled[catId] = nil
			if anchors[catId] then
				anchors[catId]:Hide()
				anchors[catId] = nil
			end
			addon.db.cooldownNotifySelectedCategory = next(addon.db.cooldownNotifyCategories)
			applyLockState()
			updateEventRegistration()
			refreshTree(addon.db.cooldownNotifySelectedCategory)
			container:ReleaseChildren()
		end
		StaticPopup_Show("EQOL_DELETE_CDN_CATEGORY", catName)
	end)
	delBtn:SetRelativeWidth(0.5)
	actionsRow:AddChild(delBtn)
	container:DoLayout()
end

local function buildSpellOptions(container, catId, spellId)
	local cat = addon.db.cooldownNotifyCategories[catId]
	if not (cat and cat.spells and cat.spells[spellId]) then return end

	local wrapper = addon.functions.createContainer("SimpleGroup", "List")
	container:AddChild(wrapper)

	local name
	if spellId < 0 then
		local slot = -spellId
		local itemID = GetInventoryItemID("player", slot)
		name = L["TrinketSlot"]:format(slot == 13 and 1 or 2)
	else
		local info = C_Spell.GetSpellInfo(spellId)
		name = (info and info.name or tostring(spellId)) .. " (" .. spellId .. ")"
	end
	local label = addon.functions.createLabelAce(name)
	wrapper:AddChild(label)

	addon.db.cooldownNotifySounds[catId] = addon.db.cooldownNotifySounds[catId] or {}
	addon.db.cooldownNotifySoundsEnabled[catId] = addon.db.cooldownNotifySoundsEnabled[catId] or {}

	local cbSound = addon.functions.createCheckboxAce(L["buffTrackerSoundsEnabled"], addon.db.cooldownNotifySoundsEnabled[catId][spellId], function(_, _, val)
		addon.db.cooldownNotifySoundsEnabled[catId][spellId] = val
		container:ReleaseChildren()
		buildSpellOptions(container, catId, spellId)
	end)
	wrapper:AddChild(cbSound)

	if addon.db.cooldownNotifySoundsEnabled[catId][spellId] then
		local soundList = {}
		for sname in pairs(addon.Aura.sounds or {}) do
			soundList[sname] = sname
		end
		local list, order = addon.functions.prepareListForDropdown(soundList)
		local dropSound = addon.functions.createDropdownAce(L["SoundFile"], list, order, function(self, _, val)
			addon.db.cooldownNotifySounds[catId][spellId] = val
			self:SetValue(val)
			local file = addon.Aura.sounds and addon.Aura.sounds[val]
			if file then PlaySoundFile(file, "Master") end
		end)
		dropSound:SetValue(addon.db.cooldownNotifySounds[catId][spellId])
		wrapper:AddChild(dropSound)
	end

	if cat.useAdvancedTracking == false then
		cat.ignoredSpells = cat.ignoredSpells or {}
		local cbIgnore = addon.functions.createCheckboxAce(L["CooldownIgnoreSpell"] or "Ignore this spell", cat.ignoredSpells[spellId], function(_, _, val)
			if val then
				cat.ignoredSpells[spellId] = true
			else
				cat.ignoredSpells[spellId] = nil
			end
		end)
		wrapper:AddChild(cbIgnore)
	end

	local btn = addon.functions.createButtonAce(L["Remove"], 150, function()
		cat.spells[spellId] = nil
		if cat.ignoredSpells then cat.ignoredSpells[spellId] = nil end
		if addon.db.cooldownNotifySounds[catId] then addon.db.cooldownNotifySounds[catId][spellId] = nil end
		if addon.db.cooldownNotifySoundsEnabled[catId] then addon.db.cooldownNotifySoundsEnabled[catId][spellId] = nil end
		refreshTree(catId)
		container:ReleaseChildren()
	end)
	wrapper:AddChild(btn)
	container:DoLayout()
end

function CN.functions.addCooldownNotifyOptions(container)
	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	wrapper:SetFullHeight(true)
	wrapper:SetLayout("Fill")
	container:AddChild(wrapper)

	local tree = getCategoryTree()

	treeGroup = AceGUI:Create("TreeGroup")
	treeGroup.enabletooltips = false

	treeGroup:SetTree(tree)
	treeGroup:SetCallback("OnGroupSelected", function(widget, _, value)
		if value == "ADD_CATEGORY" then
			local newId = 1
			for id in pairs(addon.db.cooldownNotifyCategories) do
				if id >= newId then newId = id + 1 end
			end
			addon.db.cooldownNotifyCategories[newId] = {
				name = L["NewCategoryName"] or "New",
				anchor = { point = "CENTER", x = 0, y = 0 },
				iconSize = 75,
				fadeInTime = 0.3,
				fadeOutTime = 0.7,
				holdTime = 0,
				animScale = 1.5,
				showName = true,
				spells = {},
			}
			addon.db.cooldownNotifyEnabled[newId] = true
			addon.db.cooldownNotifyLocked[newId] = false
			addon.db.cooldownNotifySounds[newId] = {}
			addon.db.cooldownNotifySoundsEnabled[newId] = {}
			ensureAnchor(newId)
			applyLockState()
			updateEventRegistration()
			refreshTree(newId)
			return
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
				local editBox = self.editBox or self.GetEditBox and self:GetEditBox()
				self:SetFrameStrata("TOOLTIP")
				editBox:SetText("")
				editBox:SetFocus()
				local txt = self.text or self.Text
				if txt then txt:SetText(L["ImportCategory"]) end
			end
			StaticPopupDialogs["EQOL_IMPORT_CATEGORY"].EditBoxOnTextChanged = function(editBox)
				local frame = editBox:GetParent()
				local name, count = previewImportCategory(editBox:GetText())
				local txt = frame.text or frame.Text
				if not txt then return end
				if name then
					txt:SetFormattedText("%s\n%s", L["ImportCategory"], (L["ImportCategoryPreview"] or "Category: %s (%d auras)"):format(name, count))
				else
					txt:SetText(L["ImportCategory"])
				end
			end
			StaticPopupDialogs["EQOL_IMPORT_CATEGORY"].OnAccept = function(self)
				local editBox = self.editBox or self.GetEditBox and self:GetEditBox()
				local text = editBox:GetText()
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
		local catId, _, spellId = strsplit("\001", value)
		catId = tonumber(catId)
		widget:ReleaseChildren()

		local scroll = addon.functions.createContainer("ScrollFrame", "List")
		scroll:SetFullWidth(true)
		scroll:SetFullHeight(true)
		widget:AddChild(scroll)

		if spellId then
			buildSpellOptions(scroll, catId, tonumber(spellId))
		else
			buildCategoryOptions(scroll, catId)
		end
	end)
	wrapper:AddChild(treeGroup)
	treeGroup:SetFullHeight(true)
	treeGroup:SetFullWidth(true)
	treeGroup:SetLayout("Fill")
	treeGroup:SetTreeWidth(200, true)
	local ok = treeGroup:SelectByValue(tostring(addon.db.cooldownNotifySelectedCategory or 1))
	if not ok and tree[1] and tree[1].value then treeGroup:SelectByValue(tree[1].value) end
end

function exportCategory(catId, encodeMode)
	local cat = addon.db.cooldownNotifyCategories and addon.db.cooldownNotifyCategories[catId]
	if not cat then return end
	local data = {
		-- guard: identify payload source to prevent cross-imports
		kind = "EQOL_CDN_CATEGORY",
		category = cat,
		order = addon.db.cooldownNotifyOrder and addon.db.cooldownNotifyOrder[catId] or {},
		sounds = addon.db.cooldownNotifySounds and addon.db.cooldownNotifySounds[catId] or {},
		soundsEnabled = addon.db.cooldownNotifySoundsEnabled and addon.db.cooldownNotifySoundsEnabled[catId] or {},
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

function importCategory(encoded)
	if type(encoded) ~= "string" or encoded == "" then return end
	local deflate = LibStub("LibDeflate")
	local serializer = LibStub("AceSerializer-3.0")
	local decoded = deflate:DecodeForPrint(encoded) or deflate:DecodeForWoWChatChannel(encoded) or deflate:DecodeForWoWAddonChannel(encoded)
	if not decoded then return end
	local decompressed = deflate:DecompressDeflate(decoded)
	if not decompressed then return end
	local ok, data = serializer:Deserialize(decompressed)
	if not ok or type(data) ~= "table" then return end
	-- strict guard: only accept CooldownNotify payloads
	if data.kind ~= "EQOL_CDN_CATEGORY" then return end
	local cat = data.category or data.cat or data
	if type(cat) ~= "table" then return end
	if type(cat.spells) ~= "table" then return end
	cat.anchor = cat.anchor or { point = "CENTER", x = 0, y = 0 }
	cat.iconSize = cat.iconSize or 75
	cat.fadeInTime = cat.fadeInTime or 0.3
	cat.fadeOutTime = cat.fadeOutTime or 0.7
	cat.animScale = cat.animScale or 1.5
	cat.holdTime = cat.holdTime or 0
	cat.showName = cat.showName ~= false
	cat.spells = cat.spells or {}
	local tmp = {}
	for id, info in pairs(cat.spells) do
		local num = tonumber(id)
		if num then
			if type(info) == "table" then
				if not info.trackType and num < 0 then info.trackType = "ITEM" end
				if not info.slot and num < 0 then info.slot = -num end
				tmp[num] = info
			elseif num < 0 then
				tmp[num] = { trackType = "ITEM", slot = -num }
			else
				tmp[num] = true
			end
		end
	end
	cat.spells = tmp
	cat.ignoredSpells = cat.ignoredSpells or {}
	local newId = 1
	for id in pairs(addon.db.cooldownNotifyCategories) do
		if id >= newId then newId = id + 1 end
	end
	addon.db.cooldownNotifyCategories[newId] = cat
	addon.db.cooldownNotifyEnabled[newId] = true
	addon.db.cooldownNotifyLocked[newId] = false
	addon.db.cooldownNotifyOrder[newId] = data.order or {}
	addon.db.cooldownNotifySounds[newId] = data.sounds or {}
	addon.db.cooldownNotifySoundsEnabled[newId] = data.soundsEnabled or {}
	ensureAnchor(newId)
	applyLockState()
	updateEventRegistration()
	return newId
end

-- Returns (name, count) if valid CDN import string, otherwise nil
function previewImportCategory(encoded)
	if type(encoded) ~= "string" or encoded == "" then return end
	local deflate = LibStub("LibDeflate")
	local serializer = LibStub("AceSerializer-3.0")
	local decoded = deflate:DecodeForPrint(encoded) or deflate:DecodeForWoWChatChannel(encoded) or deflate:DecodeForWoWAddonChannel(encoded)
	if not decoded then return end
	local decompressed = deflate:DecompressDeflate(decoded)
	if not decompressed then return end
	local ok, data = serializer:Deserialize(decompressed)
	if not ok or type(data) ~= "table" then return end
	if data.kind ~= "EQOL_CDN_CATEGORY" then return end
	local cat = data.category or data.cat or data
	if type(cat) ~= "table" then return end
	if type(cat.spells) ~= "table" then return end
	local count = 0
	for _ in pairs(cat.spells) do
		count = count + 1
	end
	return cat.name or "", count
end

local COMM_PREFIX = "EQOLCDNSHARE"
local AceComm = LibStub("AceComm-3.0")
local incoming = {}
local pending = {}
local pendingSender = {}

function ShareCategory(catId, targetPlayer)
	local addonEncoded = exportCategory(catId, "addon")
	if not addonEncoded then return end
	local label = ("%s - %s"):format(UnitName("player"), (addon.db.cooldownNotifyCategories[catId] and addon.db.cooldownNotifyCategories[catId].name) or catId)
	local placeholder = ("[EQOLCDN: %s]"):format(label)
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

local PATTERN = "%[EQOLCDN: ([^%]]+)%]"

local function EQOL_CDN_Filter(_, _, msg, sender, ...)
	local newMsg, hits = msg:gsub(PATTERN, function(label)
		local pktID = pendingSender[sender]
		if pktID then
			pending[label] = pktID
			pendingSender[sender] = nil
		end
		return ("|Hgarrmission:eqolcdn:%s|h|cff00ff88[%s]|h|r"):format(label, label)
	end)
	if hits > 0 then return false, newMsg, sender, ... end
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
	ChatFrame_AddMessageEventFilter(ev, EQOL_CDN_Filter)
end

local function HandleEQOLLink(link, text, button, frame)
	local label = link:match("^garrmission:eqolcdn:(.+)")
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
		self:SetFrameStrata("TOOLTIP")
		local encoded = incoming[data]
		local name, count = previewImportCategory(encoded or "")
		local txt = self.text or self.Text
		if not txt then return end
		if name then
			txt:SetFormattedText("%s\n%s", L["ImportCategory"], (L["ImportCategoryPreview"] or "Category: %s (%d auras)"):format(name, count))
		else
			txt:SetText(L["ImportCategory"])
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
	pendingSender[sender] = pktID
end

AceComm:RegisterComm(COMM_PREFIX, OnComm)

updateEventRegistration()

for id in pairs(addon.db.cooldownNotifyCategories or {}) do
	ensureAnchor(id)
	applySize(id)
end
applyLockState()
