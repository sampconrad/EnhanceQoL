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

local anchors = {}
local ensureAnchor
local framePools = {}
local activeBars = {}
local activeOrder = {}
local altToBase = {}

local function rebuildAltMapping()
	wipe(altToBase)
	for _, cat in pairs(addon.db.castTrackerCategories or {}) do
		for baseId, spell in pairs(cat.spells or {}) do
			if type(spell) ~= "table" then
				cat.spells[baseId] = { altIDs = {} }
				spell = cat.spells[baseId]
			end
			spell.altIDs = spell.altIDs or {}
			spell.altHash = {}
			for _, altId in ipairs(spell.altIDs) do
				altToBase[altId] = baseId
				spell.altHash[altId] = true
			end
		end
	end
end
local selectedCategory = addon.db["castTrackerSelectedCategory"] or 1
local treeGroup

local function UpdateActiveBars(catId)
	local cat = addon.db.castTrackerCategories and addon.db.castTrackerCategories[catId] or {}
	local anchor = ensureAnchor(catId)
	if anchor then anchor:SetSize(cat.width or 200, cat.height or 20) end
	for _, bar in pairs(activeBars[catId] or {}) do
		bar.status:SetStatusBarColor(unpack(cat.color or { 1, 0.5, 0, 1 }))
		bar.icon:SetSize(cat.height or 20, cat.height or 20)
		bar:SetSize(cat.width or 200, cat.height or 20)
	end
	CastTracker.functions.LayoutBars(catId)
end

ensureAnchor = function(id)
	if anchors[id] then return anchors[id] end

	local cat = addon.db.castTrackerCategories[id]
	if not cat then return nil end

	local anchor = CreateFrame("Frame", "EQOLCastTrackerAnchor" .. id, UIParent, "BackdropTemplate")
	anchor:SetSize(cat.width or 200, cat.height or 20)
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

local function applyLockState()
	for id, anchor in pairs(anchors) do
		local cat = addon.db.castTrackerCategories[id]
		if not addon.db.castTrackerEnabled[id] then
			anchor:Hide()
		elseif addon.db.castTrackerLocked[id] then
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
				local point, _, _, xOfs, yOfs = self:GetPoint()
				cat.anchor.point = point
				cat.anchor.x = xOfs
				cat.anchor.y = yOfs
			end)
			anchor:SetBackdropColor(0, 0, 0, 0.6)
			if anchor.text then
				anchor.text:SetText(L["DragToPosition"]:format("|cffffd700" .. (cat.name or "") .. "|r"))
				anchor.text:Show()
			end
			anchor:Show()
		end
	end
end

local function AcquireBar(catId)
	framePools[catId] = framePools[catId] or {}
	local pool = framePools[catId]
	local bar = table.remove(pool)
	if not bar then
		bar = CreateFrame("Frame", nil, ensureAnchor(catId))
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
	bar:SetParent(ensureAnchor(catId))
	bar:Show()
	return bar
end

local function ReleaseBar(catId, bar)
	if not bar then return end
	bar:SetScript("OnUpdate", nil)
	bar:Hide()
	activeBars[catId][bar.owner] = nil
	for i, b in ipairs(activeOrder[catId]) do
		if b == bar then
			table.remove(activeOrder[catId], i)
			break
		end
	end
	table.insert(framePools[catId], bar)
	CastTracker.functions.LayoutBars(catId)
end

local function getNextCategoryId()
	local max = 0
	for id in pairs(addon.db.castTrackerCategories or {}) do
		if type(id) == "number" and id > max then max = id end
	end
	return max + 1
end

-- encodeMode = "chat" | "addon" | nil
-- forward declaration so luacheck sees ShareCategory below
local ShareCategory

local function exportCategory(catId, encodeMode)
	local cat = addon.db.castTrackerCategories and addon.db.castTrackerCategories[catId]
	if not cat then return end
	local data = {
		category = cat,
		order = addon.db.castTrackerOrder and addon.db.castTrackerOrder[catId] or {},
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
	cat.anchor = cat.anchor or { point = "CENTER", x = 0, y = 0 }
	cat.width = cat.width or addon.db.castTrackerBarWidth or 200
	cat.height = cat.height or addon.db.castTrackerBarHeight or 20
	cat.color = cat.color or addon.db.castTrackerBarColor or { 1, 0.5, 0, 1 }
	if cat.duration == nil then cat.duration = 0 end
	if cat.sound == nil then cat.sound = addon.db.castTrackerBarSound or SOUNDKIT.ALARM_CLOCK_WARNING_3 end
	cat.direction = cat.direction or addon.db.castTrackerBarDirection or "DOWN"
	cat.spells = cat.spells or {}
	for sid, sp in pairs(cat.spells) do
		if type(sp) ~= "table" then
			cat.spells[sid] = { altIDs = {} }
		else
			sp.altIDs = sp.altIDs or {}
		end
	end
	local newId = getNextCategoryId()
	addon.db.castTrackerCategories[newId] = cat
	addon.db.castTrackerOrder[newId] = data.order or {}
	addon.db.castTrackerEnabled[newId] = true
	addon.db.castTrackerLocked[newId] = false
	ensureAnchor(newId)
	rebuildAltMapping()
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
	for _ in pairs(cat.spells or {}) do
		count = count + 1
	end
	return cat.name or "", count
end

local function getCategoryTree()
	local tree = {}
	for catId, cat in pairs(addon.db.castTrackerCategories or {}) do
		local text = cat.name
		if addon.db.castTrackerEnabled and addon.db.castTrackerEnabled[catId] == false then text = "|cff808080" .. text .. "|r" end
		local node = { value = catId, text = text, children = {} }
		local spells = {}
		for id in pairs(cat.spells or {}) do
			table.insert(spells, id)
		end
		if nil == addon.db.castTrackerOrder[catId] then addon.db.castTrackerOrder[catId] = {} end
		local orderIndex = {}
		for idx, sid in ipairs(addon.db.castTrackerOrder[catId]) do
			orderIndex[sid] = idx
		end
		table.sort(spells, function(a, b)
			local ia = orderIndex[a] or math.huge
			local ib = orderIndex[b] or math.huge
			if ia ~= ib then return ia < ib end
			local na = C_Spell.GetSpellInfo(a)
			local nb = C_Spell.GetSpellInfo(b)
			local naName = na and na.name
			local nbName = nb and nb.name
			return (naName or tostring(a)) < (nbName or tostring(b))
		end)
		for _, spellId in ipairs(spells) do
			local info = C_Spell.GetSpellInfo(spellId)
			table.insert(node.children, {
				value = catId .. "\001" .. spellId,
				text = info and info.name or tostring(spellId),
				icon = info and info.iconID,
			})
		end
		table.insert(tree, node)
	end
	table.sort(tree, function(a, b) return a.value < b.value end)
	table.insert(tree, { value = "ADD_CATEGORY", text = "|cff00ff00+ " .. (L["Add Category"] or "Add Category ...") })
	table.insert(tree, { value = "IMPORT_CATEGORY", text = "|cff00ccff+ " .. (L["ImportCategory"] or "Import Category ...") })
	return tree
end

local function refreshTree(selectValue)
	if not treeGroup then return end
	treeGroup:SetTree(getCategoryTree())
	if selectValue then
		treeGroup:SelectByValue(tostring(selectValue))
		treeGroup:Select(selectValue)
	end
end

local function handleDragDrop(src, dst)
	if not src or not dst then return end
	local sCat, _, sSpell = strsplit("\001", src)
	local dCat, _, dSpell = strsplit("\001", dst)
	sCat = tonumber(sCat)
	dCat = tonumber(dCat)
	if not sSpell then return end
	sSpell = tonumber(sSpell)
	if dSpell then dSpell = tonumber(dSpell) end

	local srcCat = addon.db.castTrackerCategories[sCat]
	local dstCat = addon.db.castTrackerCategories[dCat]
	if not srcCat or not dstCat then return end
	if not srcCat.spells[sSpell] then return end

	local spellData = srcCat.spells[sSpell]
	srcCat.spells[sSpell] = nil
	addon.db.castTrackerOrder[sCat] = addon.db.castTrackerOrder[sCat] or {}
	for i, v in ipairs(addon.db.castTrackerOrder[sCat]) do
		if v == sSpell then
			table.remove(addon.db.castTrackerOrder[sCat], i)
			break
		end
	end

	dstCat.spells[sSpell] = spellData
	addon.db.castTrackerOrder[dCat] = addon.db.castTrackerOrder[dCat] or {}
	local insertPos = #addon.db.castTrackerOrder[dCat] + 1
	if dSpell then
		for i, v in ipairs(addon.db.castTrackerOrder[dCat]) do
			if v == dSpell then
				insertPos = i
				break
			end
		end
	end
	table.insert(addon.db.castTrackerOrder[dCat], insertPos, sSpell)

	rebuildAltMapping()
	refreshTree(selectedCategory)
end

local function buildCategoryOptions(container, catId)
	local db = addon.db.castTrackerCategories[catId]
	if not db then return end
	db.spells = db.spells or {}

	local enableCB = addon.functions.createCheckboxAce(_G.ENABLE, addon.db.castTrackerEnabled[catId], function(self, _, val)
		addon.db.castTrackerEnabled[catId] = val
		applyLockState()
	end)
	container:AddChild(enableCB)

	local lockCB = addon.functions.createCheckboxAce(L["buffTrackerLocked"], addon.db.castTrackerLocked[catId], function(self, _, val)
		addon.db.castTrackerLocked[catId] = val
		applyLockState()
	end)
	container:AddChild(lockCB)

	local nameEdit = addon.functions.createEditboxAce(L["CategoryName"], db.name, function(self, _, text)
		if text ~= "" then db.name = text end
		refreshTree(catId)
		container:ReleaseChildren()
		buildCategoryOptions(container, catId)
	end)
	container:AddChild(nameEdit)

	local sw = addon.functions.createSliderAce(L["CastTrackerWidth"] .. ": " .. (db.width or 200), db.width or 200, 50, 400, 1, function(self, _, val)
		db.width = val
		self:SetLabel(L["CastTrackerWidth"] .. ": " .. val)
		UpdateActiveBars(catId)
	end)
	container:AddChild(sw)

	local sh = addon.functions.createSliderAce(L["CastTrackerHeight"] .. ": " .. (db.height or 20), db.height or 20, 10, 60, 1, function(self, _, val)
		db.height = val
		self:SetLabel(L["CastTrackerHeight"] .. ": " .. val)
		UpdateActiveBars(catId)
	end)
	container:AddChild(sh)

	local dur = addon.functions.createSliderAce(L["CastTrackerDuration"] .. ": " .. (db.duration or 0), db.duration or 0, 0, 10, 0.5, function(self, _, val)
		db.duration = val
		self:SetLabel(L["CastTrackerDuration"] .. ": " .. val)
	end)
	container:AddChild(dur)

	local col = AceGUI:Create("ColorPicker")
	col:SetLabel(L["CastTrackerColor"])
	local c = db.color or { 1, 0.5, 0, 1 }
	col:SetColor(c[1], c[2], c[3], c[4])
	col:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
		db.color = { r, g, b, a }
		UpdateActiveBars(catId)
	end)
	container:AddChild(col)

	local dirDrop = addon.functions.createDropdownAce(L["GrowthDirection"], { LEFT = "LEFT", RIGHT = "RIGHT", UP = "UP", DOWN = "DOWN" }, nil, function(self, _, val)
		db.direction = val
		CastTracker.functions.LayoutBars(catId)
	end)
	dirDrop:SetValue(db.direction)
	dirDrop:SetRelativeWidth(0.4)
	container:AddChild(dirDrop)

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
	container:AddChild(dropSound)

	container:AddChild(addon.functions.createSpacerAce())

	local groupSpells = addon.functions.createContainer("InlineGroup", "Flow")
	groupSpells:SetTitle(L["CastTrackerSpells"])
	container:AddChild(groupSpells)

	local addEdit = addon.functions.createEditboxAce(L["AddSpellID"], nil, function(self, _, text)
		local id = tonumber(text)
		if id then
			db.spells[id] = { altIDs = {} }
			self:SetText("")
			rebuildAltMapping()
			refreshTree(catId)
			container:ReleaseChildren()
			buildCategoryOptions(container, catId)
		end
	end)
	groupSpells:AddChild(addEdit)

	for _, spellId in ipairs(addon.db.castTrackerOrder[catId] or {}) do
		if db.spells[spellId] then
			local line = addon.functions.createContainer("SimpleGroup", "Flow")
			line:SetFullWidth(true)
			local info = C_Spell.GetSpellInfo(spellId)
			local name = info and info.name or tostring(spellId)
			local label = addon.functions.createLabelAce(name .. " (" .. spellId .. ")")
			label:SetRelativeWidth(0.7)
			line:AddChild(label)
			local btn = addon.functions.createButtonAce(L["Remove"], 80, function()
				db.spells[spellId] = nil
				rebuildAltMapping()
				refreshTree(catId)
				container:ReleaseChildren()
				buildCategoryOptions(container, catId)
			end)
			line:AddChild(btn)
			groupSpells:AddChild(line)
		end
	end

	container:AddChild(addon.functions.createSpacerAce())

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
	container:AddChild(exportBtn)

	local shareBtn = addon.functions.createButtonAce(L["ShareCategory"] or "Share Category", 150, function() ShareCategory(catId) end)
	container:AddChild(shareBtn)

	local importBtn = addon.functions.createButtonAce(L["ImportCategory"], 150, function()
		StaticPopupDialogs["EQOL_IMPORT_CATEGORY_BTN"] = StaticPopupDialogs["EQOL_IMPORT_CATEGORY_BTN"]
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
		StaticPopupDialogs["EQOL_IMPORT_CATEGORY_BTN"].OnShow = function(self)
			self.editBox:SetText("")
			self.editBox:SetFocus()
			self.text:SetText(L["ImportCategory"])
		end
		StaticPopupDialogs["EQOL_IMPORT_CATEGORY_BTN"].EditBoxOnTextChanged = function(editBox)
			local frame = editBox:GetParent()
			local name, count = previewImportCategory(editBox:GetText())
			if name then
				frame.text:SetFormattedText("%s\n%s", L["ImportCategory"], (L["ImportCategoryPreview"] or "Category: %s (%d auras)"):format(name, count))
			else
				frame.text:SetText(L["ImportCategory"])
			end
		end
		StaticPopupDialogs["EQOL_IMPORT_CATEGORY_BTN"].OnAccept = function(self)
			local text = self.editBox:GetText()
			local id = importCategory(text)
			if id then
				refreshTree(id)
			else
				print(L["ImportCategoryError"] or "Invalid string")
			end
		end
		StaticPopup_Show("EQOL_IMPORT_CATEGORY_BTN")
	end)
	container:AddChild(importBtn)
end

local function buildSpellOptions(container, catId, spellId)
	local cat = addon.db.castTrackerCategories[catId]
	local spell = cat and cat.spells[spellId]
	if not cat or not spell then return end

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	wrapper:SetFullWidth(true)
	container:AddChild(wrapper)

	local info = C_Spell.GetSpellInfo(spellId)
	local name = info and info.name or tostring(spellId)
	local label = addon.functions.createLabelAce(name .. " (" .. spellId .. ")")
	wrapper:AddChild(label)

	spell.altIDs = spell.altIDs or {}
	for _, altId in ipairs(spell.altIDs) do
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
			for i, v in ipairs(spell.altIDs) do
				if v == altId then
					table.remove(spell.altIDs, i)
					break
				end
			end
			rebuildAltMapping()
			container:ReleaseChildren()
			buildSpellOptions(container, catId, spellId)
		end)
		row:AddChild(removeIcon)
		wrapper:AddChild(row)
	end

	local altEdit = addon.functions.createEditboxAce(L["AddAltSpellID"], nil, function(self, _, text)
		local alt = tonumber(text)
		if alt then
			if not tContains(spell.altIDs, alt) then table.insert(spell.altIDs, alt) end
			rebuildAltMapping()
			self:SetText("")
			container:ReleaseChildren()
			buildSpellOptions(container, catId, spellId)
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

	local btn = addon.functions.createButtonAce(L["Remove"], 150, function()
		cat.spells[spellId] = nil
		rebuildAltMapping()
		refreshTree(catId)
		container:ReleaseChildren()
	end)
	wrapper:AddChild(btn)
end

local function BarUpdate(self)
	local now = GetTime()
	if now >= self.finish then
		ReleaseBar(self.catId, self)
		return
	end
	self.status:SetValue(now - self.start)
	self.time:SetFormattedText("%.1f", self.finish - now)
end

function CastTracker.functions.LayoutBars(catId)
	local order = activeOrder[catId] or {}
	local anchor = ensureAnchor(catId)
	local dir = addon.db.castTrackerCategories[catId] and addon.db.castTrackerCategories[catId].direction or "DOWN"
	for i, bar in ipairs(order) do
		bar:ClearAllPoints()
		if i == 1 then
			if dir == "UP" then
				bar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
			elseif dir == "LEFT" then
				bar:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, 0)
			elseif dir == "RIGHT" then
				bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
			else
				bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
			end
		else
			local prev = order[i - 1]
			if dir == "UP" then
				bar:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", 0, 2)
			elseif dir == "LEFT" then
				bar:SetPoint("TOPRIGHT", prev, "TOPLEFT", -2, 0)
			elseif dir == "RIGHT" then
				bar:SetPoint("TOPLEFT", prev, "TOPRIGHT", 2, 0)
			else
				bar:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)
			end
		end
	end
end

function CastTracker.functions.StartBar(spellId, sourceGUID, catId)
	local spellData = C_Spell.GetSpellInfo(spellId)
	local name = spellData and spellData.name
	local icon = spellData and spellData.iconID
	local castTime = spellData and spellData.castTime
	castTime = (castTime or 0) / 1000
	local db = addon.db.castTrackerCategories and addon.db.castTrackerCategories[catId] or {}
	if db.duration and db.duration > 0 then castTime = db.duration end
	if castTime <= 0 then return end
	activeBars[catId] = activeBars[catId] or {}
	activeOrder[catId] = activeOrder[catId] or {}
	framePools[catId] = framePools[catId] or {}
	local bar = activeBars[catId][sourceGUID]
	if bar then ReleaseBar(catId, bar) end
	bar = AcquireBar(catId)
	activeBars[catId][sourceGUID] = bar
	bar.owner = sourceGUID
	bar.spellId = spellId
	bar.catId = catId
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
	table.insert(activeOrder[catId], bar)
	CastTracker.functions.LayoutBars(catId)
       if db.sound then
               local file = addon.Aura.sounds and addon.Aura.sounds[db.sound]
               if file then
                       PlaySoundFile(file, "Master")
               else
                       PlaySound(db.sound)
               end
       end
end

CastTracker.functions.AcquireBar = AcquireBar
CastTracker.functions.ReleaseBar = ReleaseBar
CastTracker.functions.BarUpdate = BarUpdate
CastTracker.functions.UpdateActiveBars = UpdateActiveBars

local function HandleCLEU()
	local _, subevent, _, sourceGUID, _, sourceFlags, _, destGUID, _, _, _, spellId = CombatLogGetCurrentEventInfo()
	local baseSpell = altToBase[spellId] or spellId
	if subevent == "SPELL_CAST_START" then
		for catId, cat in pairs(addon.db.castTrackerCategories or {}) do
			if addon.db.castTrackerEnabled[catId] and cat.spells and cat.spells[baseSpell] then CastTracker.functions.StartBar(baseSpell, sourceGUID, catId) end
		end
	elseif subevent == "SPELL_CAST_SUCCESS" or subevent == "SPELL_CAST_FAILED" or subevent == "SPELL_INTERRUPT" then
		for id, bars in pairs(activeBars) do
			local bar = bars[sourceGUID]
			if bar and bar.spellId == baseSpell then ReleaseBar(id, bar) end
		end
	elseif subevent == "UNIT_DIED" then
		for id, bars in pairs(activeBars) do
			local bar = bars[destGUID]
			if bar then ReleaseBar(id, bar) end
		end
	else
	end
end

local eventFrame = CreateFrame("Frame")

function CastTracker.functions.Refresh()
	rebuildAltMapping()
	for id, cat in pairs(addon.db.castTrackerCategories or {}) do
		local a = ensureAnchor(id)
		a:ClearAllPoints()
		a:SetPoint(cat.anchor.point, UIParent, cat.anchor.point, cat.anchor.x, cat.anchor.y)
		UpdateActiveBars(id)
	end
	eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	eventFrame:SetScript("OnEvent", HandleCLEU)
	applyLockState()
end

function CastTracker.functions.addCastTrackerOptions(container)
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
		if value == "ADD_CATEGORY" then
			local newId = getNextCategoryId()
			addon.db.castTrackerCategories[newId] = {
				name = L["NewCategoryName"] or "New",
				anchor = { point = "CENTER", x = 0, y = 0 },
				width = addon.db.castTrackerBarWidth,
				height = addon.db.castTrackerBarHeight,
				color = addon.db.castTrackerBarColor,
				duration = 0,
				sound = addon.db.castTrackerBarSound,
				direction = addon.db.castTrackerBarDirection,
				spells = {},
			}
			addon.db.castTrackerEnabled[newId] = true
			addon.db.castTrackerLocked[newId] = false
			addon.db.castTrackerOrder[newId] = {}
			ensureAnchor(newId)
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

		local catId, _, spellId = strsplit("\001", value)
		catId = tonumber(catId)
		selectedCategory = catId
		addon.db.castTrackerSelectedCategory = catId
		widget:ReleaseChildren()

		local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
		scroll:SetFullWidth(true)
		scroll:SetFullHeight(true)
		widget:AddChild(scroll)

		if spellId then
			buildSpellOptions(scroll, catId, tonumber(spellId))
		else
			buildCategoryOptions(scroll, catId)
		end
	end)
	treeGroup:SetCallback("OnDragDrop", function(_, _, src, dst) handleDragDrop(src, dst) end)

	left:AddChild(treeGroup)

	local ok = treeGroup:SelectByValue(tostring(selectedCategory))
	if not ok then
		local tree = treeGroup.tree
		if tree and tree[1] and tree[1].value then treeGroup:SelectByValue(tree[1].value) end
	end
end

CastTracker.functions.Refresh()

-- ---------------------------------------------------------------------------
-- Share Category via Chat & Addon-Channel
-- ---------------------------------------------------------------------------
local COMM_PREFIX = "EQOLCTSHARE"
local AceComm = LibStub("AceComm-3.0")

local incoming = {}
local pending = {}

local function getCatName(catId)
	local cat = addon.db.castTrackerCategories and addon.db.castTrackerCategories[catId]
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
	local newMsg, hits = msg:gsub(PATTERN, function(label) return ("|Hgarrmission:eqolcast:%s|h|cff00ff88[%s]|h|r"):format(label, label) end)
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
	local label = link:match("^garrmission:eqolcast:(.+)")
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
