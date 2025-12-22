-- luacheck: globals ScrollBoxListMixin EncounterJournal_LootUpdate EncounterJournal EJ_SelectInstance EJ_SetLootFilter EJ_SelectEncounter EJ_GetNumLoot EJ_GetDifficulty EJ_GetLootFilter
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.DungeonJournalLootSpec = addon.DungeonJournalLootSpec or {}
local Module = addon.DungeonJournalLootSpec

local pairs = pairs
local ipairs = ipairs
local next = next
local type = type
local wipe = wipe
local table_sort = table.sort

local CreateFrame = CreateFrame
local CreateTexturePool = CreateTexturePool
local hooksecurefunc = hooksecurefunc
local UnitClass = UnitClass
local C_Timer_After = C_Timer and C_Timer.After

local GetNumClasses = GetNumClasses
local GetNumSpecializationsForClassID = GetNumSpecializationsForClassID
local GetSpecializationInfoForClassID = GetSpecializationInfoForClassID
local GetClassInfo = C_CreatureInfo and C_CreatureInfo.GetClassInfo

local EJ_SelectInstance = EJ_SelectInstance
local EJ_SetLootFilter = EJ_SetLootFilter
local EJ_GetNumLoot = EJ_GetNumLoot
local EJ_SelectEncounter = EJ_SelectEncounter
local EJ_GetDifficulty = EJ_GetDifficulty
local EJ_GetLootFilter = EJ_GetLootFilter

local GetLootInfoByIndex = C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex

Module.frame = Module.frame or CreateFrame("Frame")
Module.enabled = Module.enabled or false
Module.scanInProgress = Module.scanInProgress or false
Module.pendingEncounterUpdate = Module.pendingEncounterUpdate or false
Module.updateScheduled = Module.updateScheduled or false
Module.updateAll = Module.updateAll or false
Module.isUpdatingLoot = Module.isUpdatingLoot or false
Module.needsRerun = Module.needsRerun or false
Module.scrollBoxAcquiredFunc = Module.scrollBoxAcquiredFunc or function(_, button) Module:OnScrollBoxAcquired(button) end
Module.scrollBoxReleasedFunc = Module.scrollBoxReleasedFunc or function(_, button) Module:OnScrollBoxReleased(button) end
Module.scrollBoxDataRangeFunc = Module.scrollBoxDataRangeFunc or function() Module:RequestLootUpdate(nil, true) end
Module.lootUpdateFunc = Module.lootUpdateFunc or function() Module:OnEncounterJournalLootUpdate() end

local classes = {}
local roles = {}
local cache = { items = {} }
local numSpecs = 0
local fakeEveryoneSpec = { { specIcon = 922035 } }

local ROLES_ATLAS = {
	TANK = "UI-LFG-RoleIcon-Tank-Micro-GroupFinder",
	HEALER = "UI-LFG-RoleIcon-Healer-Micro-GroupFinder",
	DAMAGER = "UI-LFG-RoleIcon-DPS-Micro-GroupFinder",
}

local ANCHOR = {
	"TOPRIGHT",
	"BOTTOMRIGHT",
}

local ANCHORFLIP = {
	TOPRIGHT = "TOPLEFT",
	BOTTOMRIGHT = "BOTTOMLEFT",
}

local PADDINGFLIP = {
	TOPRIGHT = 1,
	BOTTOMRIGHT = 1,
	TOPLEFT = 1,
	BOTTOMLEFT = -1,
}

local ClampValue = Clamp or function(val, minValue, maxValue)
	if val < minValue then return minValue end
	if val > maxValue then return maxValue end
	return val
end

local function BuildClassData()
	wipe(classes)
	wipe(roles)
	numSpecs = 0

	for i = 1, GetNumClasses() do
		local classInfo = GetClassInfo and GetClassInfo(i)
		if classInfo and classInfo.classID then
			classInfo.numSpecs = GetNumSpecializationsForClassID(classInfo.classID) or 0
			classInfo.specs = {}
			classes[classInfo.classID] = classInfo

			for j = 1, classInfo.numSpecs do
				local specID, specName, _, specIcon, specRole = GetSpecializationInfoForClassID(classInfo.classID, j)
				if specID and specRole then
					local spec = {
						id = specID,
						name = specName,
						icon = specIcon,
						role = specRole,
					}
					classInfo.specs[specID] = spec
					numSpecs = numSpecs + 1
					roles[specRole] = roles[specRole] or {}
					roles[specRole][specID] = classInfo.classID
				end
			end
		end
	end

	for role, specToClass in pairs(roles) do
		local count = 0
		for specID, _ in pairs(specToClass) do
			if specID ~= "numSpecs" then count = count + 1 end
		end
		specToClass.numSpecs = count
	end
end

local function CompressSpecs(specs)
	local compress
	for classID, classInfo in pairs(classes) do
		local remaining = classInfo.numSpecs or 0
		if remaining > 0 then
			for specID, _ in pairs(classInfo.specs) do
				for _, info in ipairs(specs) do
					if info.specID == specID then
						remaining = remaining - 1
						break
					end
				end
				if remaining == 0 then break end
			end
			if remaining == 0 then
				compress = compress or {}
				compress[classID] = true
			end
		end
	end
	if not compress then return specs end

	local encountered = {}
	local compressed = {}
	local index = 0
	for _, info in ipairs(specs) do
		if compress[info.classID] then
			if not encountered[info.classID] then
				encountered[info.classID] = true
				index = index + 1
				info.specID = 0
				info.specName = info.className
				info.specIcon = true
				info.specRole = ""
				compressed[index] = info
			end
		else
			index = index + 1
			compressed[index] = info
		end
	end
	return compressed
end

local function CompressRoles(specs)
	local compress
	for role, specToClass in pairs(roles) do
		local remaining = specToClass.numSpecs or 0
		for specID, _ in pairs(specToClass) do
			for _, info in ipairs(specs) do
				if info.specID == specID then
					remaining = remaining - 1
					break
				end
			end
			if remaining == 0 then break end
		end
		if remaining == 0 then
			compress = compress or {}
			compress[role] = true
		end
	end
	if not compress then return specs end

	local encountered = {}
	local compressed = {}
	local index = 0
	for _, info in ipairs(specs) do
		if compress[info.specRole] then
			if not encountered[info.specRole] then
				encountered[info.specRole] = true
				index = index + 1
				info.specID = 0
				info.specName = info.specRole
				info.specIcon = true
				info.specRole = true
				compressed[index] = info
			end
		else
			index = index + 1
			compressed[index] = info
		end
	end
	return compressed
end

local function SortByClassAndSpec(a, b)
	if a.className == b.className then return a.specName < b.specName end
	return a.className < b.className
end

local function GetConfig()
	local db = addon.db or {}
	local textureScale = type(db["dungeonJournalLootSpecScale"]) == "number" and db["dungeonJournalLootSpecScale"] or 1
	if textureScale <= 0 then textureScale = 1 end
	return {
		anchor = db["dungeonJournalLootSpecAnchor"] or 1,
		offsetX = db["dungeonJournalLootSpecOffsetX"] or 0,
		offsetY = db["dungeonJournalLootSpecOffsetY"] or 0,
		spacing = db["dungeonJournalLootSpecSpacing"] or 0,
		textureScale = textureScale,
		iconPadding = db["dungeonJournalLootSpecIconPadding"] or 0,
		compressSpecs = true,
		compressRoles = true,
		showAll = db["dungeonJournalLootSpecShowAll"] and true or false,
	}
end

local function GetSpecsForItem(button, config, playerClassID, specs)
	local itemID = button and button.itemID
	if not itemID then return end

	local itemCache = cache.items[itemID]
	if not itemCache then return end

	if itemCache.everyone then return true end

	specs = specs or {}
	wipe(specs)
	local index = 0

	for specID, classID in pairs(itemCache.specs) do
		if config.showAll or playerClassID == classID then
			local classInfo = classes[classID]
			local specInfo = classInfo and classInfo.specs and classInfo.specs[specID]
			if classInfo and specInfo then
				index = index + 1
				local info = specs[index]
				if not info then
					info = {}
					specs[index] = info
				end
				info.classID = classID
				info.className = classInfo.className
				info.classFile = classInfo.classFile
				info.specID = specID
				info.specName = specInfo.name
				info.specIcon = specInfo.icon
				info.specRole = specInfo.role
			end
		end
	end

	for i = index + 1, #specs do
		specs[i] = nil
	end

	if not specs[1] then return end

	if config.compressSpecs and specs[2] then specs = CompressSpecs(specs) end
	if config.compressRoles and specs[2] then specs = CompressRoles(specs) end
	if specs[2] then table_sort(specs, SortByClassAndSpec) end

	return specs
end

local function UpdateItems()
	if not EncounterJournal or not EncounterJournal.encounter then return end

	local difficulty = EJ_GetDifficulty and EJ_GetDifficulty()
	if cache.difficulty and cache.difficulty == difficulty and cache.instanceID == EncounterJournal.instanceID and cache.encounterID == EncounterJournal.encounterID then return end

	cache.difficulty = difficulty
	cache.instanceID = EncounterJournal.instanceID
	cache.encounterID = EncounterJournal.encounterID
	if EJ_GetLootFilter then
		cache.classID, cache.specID = EJ_GetLootFilter()
	end

	if not cache.instanceID then return end

	EJ_SelectInstance(cache.instanceID)
	wipe(cache.items)
	Module.scanInProgress = true

	local currentClassID, currentSpecID
	for classID, classData in pairs(classes) do
		for specID, _ in pairs(classData.specs) do
			if currentClassID ~= classID or currentSpecID ~= specID then
				EJ_SetLootFilter(classID, specID)
				currentClassID, currentSpecID = classID, specID
			end
			for index = 1, EJ_GetNumLoot() or 0 do
				local itemInfo = GetLootInfoByIndex and GetLootInfoByIndex(index)
				if itemInfo and itemInfo.itemID then
					local itemCache = cache.items[itemInfo.itemID]
					if not itemCache then
						itemCache = itemInfo
						itemCache.specs = {}
						cache.items[itemInfo.itemID] = itemCache
					end
					itemCache.specs[specID] = classID
				end
			end
		end
	end

	if cache.encounterID then EJ_SelectEncounter(cache.encounterID) end
	if cache.classID and cache.specID then EJ_SetLootFilter(cache.classID, cache.specID) end

	Module.scanInProgress = false
	if Module.pendingEncounterUpdate then
		if not Module.isUpdatingLoot then Module:RequestLootUpdate(nil, true) end
		Module.pendingEncounterUpdate = false
	end

	for _, itemCache in pairs(cache.items) do
		local count = 0
		for _ in pairs(itemCache.specs) do
			count = count + 1
		end
		itemCache.everyone = count == numSpecs
	end
end

local function UpdateItem(button, config, layout, playerClassID)
	local specs = GetSpecsForItem(button, config, playerClassID, button.eqolSpecs)
	if specs == nil then
		if button.eqolIcons then
			for i = 1, #button.eqolIcons do
				button.eqolIcons[i]:Hide()
			end
		end
		return
	end

	if specs == true then
		specs = fakeEveryoneSpec
	else
		button.eqolSpecs = specs
	end

	local iconPadding = layout.iconPadding
	local textureScale = layout.textureScale
	if not textureScale or textureScale <= 0 then textureScale = 1 end
	local anchorKey = layout.anchorKey
	local anchorFlip = layout.anchorFlip
	local xOffset = layout.xOffset
	local yOffset = layout.yOffset
	local xPrevOffset = layout.xPrevOffset

	local icons = button.eqolIcons
	if not icons then
		icons = {}
		button.eqolIcons = icons
	end

	local previousTexture
	for index, info in ipairs(specs) do
		local texture = icons[index]
		if not texture then
			texture = Module.pool:Acquire()
			icons[index] = texture
			texture:SetParent(button)
			texture:SetSize(16, 16)
		end

		if not texture.eqolSized then
			texture:SetSize(16, 16)
			texture.eqolSized = true
		end

		if texture.eqolScale ~= textureScale then
			texture.eqolScale = textureScale
			if textureScale ~= 1 then
				texture:SetScale(textureScale)
			else
				texture:SetScale(1)
			end
		end

		local anchorChanged = texture.eqolAnchorKey ~= anchorKey
			or texture.eqolAnchorFlip ~= anchorFlip
			or texture.eqolAnchorPrevious ~= previousTexture
			or texture.eqolAnchorXOffset ~= xOffset
			or texture.eqolAnchorYOffset ~= yOffset
			or texture.eqolAnchorPrevOffset ~= xPrevOffset

		if anchorChanged then
			texture:ClearAllPoints()
			if previousTexture then
				texture:SetPoint(anchorKey, previousTexture, anchorFlip, xPrevOffset, 0)
			else
				texture:SetPoint(anchorKey, button, anchorKey, xOffset, yOffset)
			end
			texture.eqolAnchorKey = anchorKey
			texture.eqolAnchorFlip = anchorFlip
			texture.eqolAnchorPrevious = previousTexture
			texture.eqolAnchorXOffset = xOffset
			texture.eqolAnchorYOffset = yOffset
			texture.eqolAnchorPrevOffset = xPrevOffset
		end

		if info.specRole == true then
			local atlas = ROLES_ATLAS[info.specName] or ""
			if texture.eqolAtlas ~= atlas then
				texture:SetAtlas(atlas)
				texture.eqolAtlas = atlas
				texture.eqolTexture = nil
			end
			if texture.eqolTexCoordPadding ~= iconPadding then
				texture:SetTexCoord(iconPadding, 1 - iconPadding, iconPadding, 1 - iconPadding)
				texture.eqolTexCoordPadding = iconPadding
			end
		elseif info.specIcon == true then
			if texture.eqolTexture ~= "Interface\\TargetingFrame\\UI-Classes-Circles" then
				texture:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
				texture.eqolTexture = "Interface\\TargetingFrame\\UI-Classes-Circles"
				texture.eqolAtlas = nil
			end
			local coords = CLASS_ICON_TCOORDS[info.classFile]
			if coords then
				if
					not texture.eqolTexCoord
					or texture.eqolTexCoord[1] ~= coords[1]
					or texture.eqolTexCoord[2] ~= coords[2]
					or texture.eqolTexCoord[3] ~= coords[3]
					or texture.eqolTexCoord[4] ~= coords[4]
				then
					texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
					texture.eqolTexCoord = coords
					texture.eqolTexCoordPadding = nil
				end
			else
				if texture.eqolTexCoordPadding ~= iconPadding then
					texture:SetTexCoord(iconPadding, 1 - iconPadding, iconPadding, 1 - iconPadding)
					texture.eqolTexCoordPadding = iconPadding
					texture.eqolTexCoord = nil
				end
			end
		else
			local texturePath = info.specIcon or 134400
			if texture.eqolTexture ~= texturePath then
				texture:SetTexture(texturePath)
				texture.eqolTexture = texturePath
				texture.eqolAtlas = nil
			end
			if texture.eqolTexCoordPadding ~= iconPadding then
				texture:SetTexCoord(iconPadding, 1 - iconPadding, iconPadding, 1 - iconPadding)
				texture.eqolTexCoordPadding = iconPadding
				texture.eqolTexCoord = nil
			end
		end

		texture:Show()
		previousTexture = texture
	end

	for index = #specs + 1, #icons do
		icons[index]:Hide()
	end
end

function Module:UnregisterScrollCallbacks()
	if not self.scrollBox or not self.scrollCallbacks then return end

	if self.scrollCallbacks.acquired then
		self.scrollBox:UnregisterCallback(ScrollBoxListMixin.Event.OnAcquiredFrame, self.scrollBoxAcquiredFunc)
		self.scrollCallbacks.acquired = nil
	end
	if self.scrollCallbacks.released then
		self.scrollBox:UnregisterCallback(ScrollBoxListMixin.Event.OnReleasedFrame, self.scrollBoxReleasedFunc)
		self.scrollCallbacks.released = nil
	end
	if self.scrollCallbacks.dataRange then
		self.scrollBox:UnregisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged, self.scrollBoxDataRangeFunc)
		self.scrollCallbacks.dataRange = nil
	end

	if not next(self.scrollCallbacks) then self.scrollCallbacks = nil end
end

function Module:RegisterScrollCallbacks()
	if not self.scrollBox then return end
	self.scrollCallbacks = self.scrollCallbacks or {}
	local callbacks = self.scrollCallbacks

	if not callbacks.acquired then
		self.scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnAcquiredFrame, self.scrollBoxAcquiredFunc)
		callbacks.acquired = true
	end
	if not callbacks.released then
		self.scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnReleasedFrame, self.scrollBoxReleasedFunc)
		callbacks.released = true
	end
	if not callbacks.dataRange then
		self.scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged, self.scrollBoxDataRangeFunc)
		callbacks.dataRange = true
	end
end

function Module:EnsurePool()
	if not EncounterJournal or not EncounterJournal.encounter or not EncounterJournal.encounter.info then return end
	local lootContainer = EncounterJournal.encounter.info.LootContainer
	if not lootContainer or not lootContainer.ScrollBox then return end

	local scrollBox = lootContainer.ScrollBox
	if self.scrollBox and self.scrollBox ~= scrollBox then
		local oldScrollBox = self.scrollBox
		self:UnregisterScrollCallbacks()
		if oldScrollBox then
			local buttons = oldScrollBox:GetFrames()
			if buttons then
				for _, button in ipairs(buttons) do
					self:ReleaseButtonIcons(button, true)
					button.eqolDirty = nil
				end
			end
		end
		if self.pool then
			self.pool:ReleaseAll()
			self.pool = nil
		end
	end

	self.scrollBox = scrollBox
	local created
	if not self.pool then
		self.pool = CreateTexturePool(scrollBox, "OVERLAY", 7)
		created = true
	end

	if created then
		self.updateAll = true
		self:MarkAllButtonsDirty()
	end

	return true, created
end

function Module:UpdateLoot(forceAll)
	if not self.enabled then
		if self.pool then self.pool:ReleaseAll() end
		return
	end

	if forceAll then self.updateAll = true end

	if self.isUpdatingLoot then
		if forceAll then self.needsRerun = true end
		return
	end

	if not self.pool or not self.scrollBox then
		if not self:EnsurePool() then
			self.isUpdatingLoot = false
			return
		end
	end
	if not self.pool or not self.scrollBox then
		self.isUpdatingLoot = false
		return
	end
	if not self.scrollCallbacks then self:RegisterScrollCallbacks() end

	local buttons = self.scrollBox:GetFrames()
	if not buttons then return end

	self.isUpdatingLoot = true

	local updateAll = self.updateAll
	self.updateAll = false

	local playerClassID = addon.variables.unitClassID
	local config = GetConfig()

	local anchorKey = ANCHOR[config.anchor] or ANCHOR[1]
	local anchorFlip = ANCHORFLIP[anchorKey]
	local paddingFlip = PADDINGFLIP[anchorKey] or 1
	local spacing = (config.spacing or 0) * paddingFlip
	local xPrevOffset = (1 * paddingFlip) - spacing
	local xOffset = (config.offsetX or 0) * paddingFlip
	local yOffset = (-6 * paddingFlip * (PADDINGFLIP[anchorFlip] or 1)) + ((config.offsetY or 0) * paddingFlip)
	local iconPadding = ClampValue(type(config.iconPadding) == "number" and config.iconPadding or 0, 0, 0.5)
	local textureScale = config.textureScale or 1

	local layout = self.layout or {}
	layout.anchorKey = anchorKey
	layout.anchorFlip = anchorFlip
	layout.xPrevOffset = xPrevOffset
	layout.xOffset = xOffset
	layout.yOffset = yOffset
	layout.iconPadding = iconPadding
	layout.textureScale = textureScale
	self.layout = layout

	local hasUpdatedItems
	for _, button in ipairs(buttons) do
		if button:IsVisible() and (updateAll or button.eqolDirty) then
			if not hasUpdatedItems then
				hasUpdatedItems = true
				UpdateItems()
			end
			UpdateItem(button, config, layout, playerClassID)
			button.eqolDirty = nil
		elseif updateAll and button.eqolIcons then
			for i = 1, #button.eqolIcons do
				button.eqolIcons[i]:Hide()
			end
		end
	end

	self.isUpdatingLoot = false

	if self.needsRerun then
		self.needsRerun = false
		self:UpdateLoot()
	elseif self.pendingEncounterUpdate then
		self.pendingEncounterUpdate = false
		self:RequestLootUpdate(nil, true)
	end
end

function Module:Refresh()
	if self.enabled then self:RequestLootUpdate(nil, true) end
end

function Module:MarkAllButtonsDirty()
	if not self.scrollBox then return end
	local buttons = self.scrollBox:GetFrames()
	if not buttons then return end
	for _, button in ipairs(buttons) do
		button.eqolDirty = true
	end
end

function Module:ReleaseButtonIcons(button, releaseToPool)
	if not button or not button.eqolIcons then return end

	for i = 1, #button.eqolIcons do
		local texture = button.eqolIcons[i]
		texture:Hide()
		texture.eqolSized = nil
		texture.eqolScale = nil
		texture.eqolAtlas = nil
		texture.eqolTexture = nil
		texture.eqolTexCoord = nil
		texture.eqolTexCoordPadding = nil
		texture.eqolAnchorKey = nil
		texture.eqolAnchorFlip = nil
		texture.eqolAnchorPrevious = nil
		texture.eqolAnchorXOffset = nil
		texture.eqolAnchorYOffset = nil
		texture.eqolAnchorPrevOffset = nil
		if releaseToPool and self.pool then self.pool:Release(texture) end
	end

	wipe(button.eqolIcons)
	button.eqolIcons = nil
	button.eqolSpecs = nil
end

function Module:RequestLootUpdate(button, forceAll)
	if button then button.eqolDirty = true end
	if forceAll then
		self.updateAll = true
		self:MarkAllButtonsDirty()
	end

	if not self.enabled then return end

	if self.isUpdatingLoot then
		self.needsRerun = true
		return
	end

	if self.updateScheduled then return end
	self.updateScheduled = true

	if C_Timer_After then
		C_Timer_After(0, function()
			Module.updateScheduled = false
			Module:UpdateLoot()
		end)
	else
		Module.updateScheduled = false
		Module:UpdateLoot()
	end
end

function Module:OnEncounterJournalLootUpdate()
	if not self.enabled then return end

	if self.scanInProgress or self.isUpdatingLoot then
		self.pendingEncounterUpdate = true
		return
	end

	self:RequestLootUpdate(nil, true)
end

function Module:OnScrollBoxAcquired(button)
	if not self.enabled or not button then return end
	self:RequestLootUpdate(button, false)
end

function Module:OnScrollBoxReleased(button)
	if not button then return end
	self:ReleaseButtonIcons(button, true)
	button.eqolDirty = nil
end

function Module:TryLoad()
	if not self.enabled then return end
	if not EncounterJournal or not EncounterJournal.encounter then return end

	self:EnsurePool()
	if not self.pool or not self.scrollBox then return end

	if not self.hookedLootUpdate then
		hooksecurefunc("EncounterJournal_LootUpdate", self.lootUpdateFunc)
		self.hookedLootUpdate = true
	end

	self:RegisterScrollCallbacks()
	self:MarkAllButtonsDirty()
	self:UpdateLoot(true)
end

function Module:OnEvent(event, arg1)
	if not self.enabled then return end

	if event == "ADDON_LOADED" and arg1 == "Blizzard_EncounterJournal" then
		self:TryLoad()
	elseif event == "PLAYER_LOGIN" then
		BuildClassData()
		wipe(cache.items)
		self.updateAll = true
		self:RequestLootUpdate(nil, true)
	elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
		if arg1 == nil or arg1 == "player" then
			self.updateAll = true
			self:RequestLootUpdate(nil, true)
		end
	end
end

Module.frame:SetScript("OnEvent", function(_, event, arg1) Module:OnEvent(event, arg1) end)

function Module:SetEnabled(value)
	value = not not value
	if value == self.enabled then
		if value then self:Refresh() end
		return
	end

	self.enabled = value

	if value then
		self.updateScheduled = false
		self.needsRerun = false
		self.pendingEncounterUpdate = false
		self.updateAll = true
		BuildClassData()
		wipe(cache.items)
		cache.difficulty = nil
		cache.instanceID = nil
		cache.encounterID = nil
		cache.classID = nil
		cache.specID = nil
		self.frame:RegisterEvent("ADDON_LOADED")
		self.frame:RegisterEvent("PLAYER_LOGIN")
		self.frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		self:TryLoad()
	else
		self.updateScheduled = false
		self.frame:UnregisterEvent("ADDON_LOADED")
		self.frame:UnregisterEvent("PLAYER_LOGIN")
		self.frame:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		if self.scrollBox then
			local buttons = self.scrollBox:GetFrames()
			if buttons then
				for _, button in ipairs(buttons) do
					self:ReleaseButtonIcons(button, true)
					button.eqolDirty = nil
				end
			end
			self:UnregisterScrollCallbacks()
		end
		if self.pool then
			self.pool:ReleaseAll()
			self.pool = nil
		end
		self.scrollBox = nil
		self.layout = nil
	end
end
