local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.MythicPlus = addon.MythicPlus or {}
addon.MythicPlus.functions = addon.MythicPlus.functions or {}
addon.MythicPlus.variables = addon.MythicPlus.variables or {}

local openRaidLib = LibStub:GetLibrary("LibOpenKeystone-1.0", true) or LibStub:GetLibrary("LibOpenRaid-1.0", true)
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_MythicPlus")

local cModeIDs
local portalSpells = {}
local allSpells = {} --  for Cooldown checking
local mapInfo = {}
local mapIDInfo = {} -- TODO 11.2: remove mapIDInfo after new mapID from GetMapUIInfo
local selectedMapId
local faction = select(2, UnitFactionGroup("player"))
local checkCooldown

local minFrameSize = 0

local GetItemCooldown = C_Item.GetItemCooldown
local GetItemCount = C_Item.GetItemCount
local toyUsableCache = {}
local toyUsableCacheTime = {}
local TOY_USABLE_CACHE_TTL = 2

local function clearToyUsableCache()
	if wipe then
		wipe(toyUsableCache)
		wipe(toyUsableCacheTime)
	else
		for key in pairs(toyUsableCache) do
			toyUsableCache[key] = nil
		end
		for key in pairs(toyUsableCacheTime) do
			toyUsableCacheTime[key] = nil
		end
	end
end

function addon.MythicPlus.functions.InvalidateTeleportCompendiumCaches() clearToyUsableCache() end

-- Open World Map to a mapID and create a user waypoint pin at x,y (0..1)
local function OpenMapAndCreatePin(mapID, x, y)
	if not mapID or not x or not y then return end
	if WorldMapFrame and WorldMapFrame.SetMapID then
		if not WorldMapFrame:IsShown() then
			if ToggleMap then
				ToggleMap()
			else
				ShowUIPanel(WorldMapFrame)
			end
		end
		WorldMapFrame:SetMapID(mapID)
	end
	if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
		local point = UiMapPoint.CreateFromCoordinates(mapID, x, y)
		if point then
			C_Map.SetUserWaypoint(point)
			if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
		end
	end
end

-- Returns an itemID to use when the data provides multiple possible IDs.
local function FirstOwnedItemID(itemID)
	if type(itemID) == "table" then
		for _, id in ipairs(itemID) do
			if GetItemCount(id) > 0 then return id end
		end
		return itemID[1]
	end
	return itemID
end

local function GetCooldownData(spellInfo)
	if not spellInfo then return end

	local cooldownData, isSecret = nil, false
	if spellInfo.isToy then
		if spellInfo.toyID then
			local startTime, duration, enable = GetItemCooldown(spellInfo.toyID)
			cooldownData = {
				startTime = startTime,
				duration = duration,
				modRate = 1,
				isEnabled = enable,
			}
		end
	elseif spellInfo.isItem then
		if spellInfo.itemID then
			local id = FirstOwnedItemID(spellInfo.itemID)
			local startTime, duration, enable = GetItemCooldown(id)
			cooldownData = {
				startTime = startTime,
				duration = duration,
				modRate = 1,
				isEnabled = enable,
			}
		end
	else
		local spellID = spellInfo.spellID
		if FindSpellOverrideByID(spellID) and FindSpellOverrideByID(spellID) ~= spellID then
			spellID = FindSpellOverrideByID(spellID)
			spellInfo.spellID = spellID
		end
		cooldownData = C_Spell.GetSpellCooldownDuration(spellID)
		isSecret = true
	end
	return cooldownData, isSecret
end

local function getCurrentSeasonPortal()
	-- Timerunners have no current-season portals; skip population
	local timerunnerID = _G.PlayerGetTimerunningSeasonID and _G.PlayerGetTimerunningSeasonID() or nil

	local cModeIDs = C_ChallengeMode.GetMapTable()
	local cModeIDLookup = {}
	for _, id in ipairs(cModeIDs) do
		cModeIDLookup[id] = true
	end

	local filteredPortalSpells = {}
	local filteredMapInfo = {}
	local filteredMapID = {}

	for _, section in pairs(addon.MythicPlus.variables.portalCompendium) do
		if (timerunnerID ~= nil and timerunnerID == section.timerunner) or (timerunnerID == nil) then
			for spellID, data in pairs(section.spells) do
				if data.cId then
					for cId in pairs(data.cId) do
						local mapInfoText = data.textID and data.textID[cId] or data.text
						if cModeIDLookup[cId] then
							local mapName, _, _, texture, backgroundTexture = C_ChallengeMode.GetMapUIInfo(cId)
							filteredPortalSpells[spellID] = {
								text = data.text,
								iconID = data.iconID,
								-- pass through optional map pin metadata if present (use only locID)
								locID = data.locID,
								x = data.x,
								y = data.y,
							}
							if data.faction then
								filteredPortalSpells[spellID].faction = data.faction
								if data.faction == faction then
									filteredMapInfo[cId] = {
										text = mapInfoText,
										spellId = spellID,
										mapName = mapName,
										texture = texture,
										background = backgroundTexture,
									}
								end
							else
								filteredMapInfo[cId] = {
									text = mapInfoText,
									spellId = spellID,
									mapName = mapName,
									texture = texture,
									background = backgroundTexture,
								}
							end
							if data.mapID then
								if type(data.mapID) == "table" then
									for _, mID in pairs(data.mapID) do
										filteredMapID[mID] = cId
									end
								else
									filteredMapID[data.mapID] = cId
								end
							end
						end
					end
				end
				allSpells[spellID] = {
					spellID = spellID,
					isToy = data.isToy or false,
					toyID = data.toyID,
					isItem = data.isItem or false,
					itemID = data.itemID,
				}
			end
		end
	end
	portalSpells = filteredPortalSpells
	mapInfo = filteredMapInfo
	mapIDInfo = filteredMapID -- TODO 11.2: remove mapIDInfo once mapID param is used
end

local isKnown = {}
local parentFrame = PVEFrame
local doAfterCombat = false

local function isRestrictedContent()
	local restrictionTypes = Enum and Enum.AddOnRestrictionType
	local restrictedActions = _G.C_RestrictedActions
	if not (restrictionTypes and restrictedActions and restrictedActions.GetAddOnRestrictionState) then return false end
	for _, v in pairs(restrictionTypes) do
		if v ~= 4 then
			if restrictedActions.GetAddOnRestrictionState(v) == 2 then return true end
		end
	end
	return false
end

local function SafeSetSize(frame, width, height)
	if not frame then return end
	if InCombatLockdown() then
		doAfterCombat = true
	else
		frame:SetSize(width, height)
	end
end

local frameAnchor = CreateFrame("Frame", "DungeonTeleportFrame", parentFrame, "BackdropTemplate")
frameAnchor:SetBackdrop({
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", -- Hintergrund
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", -- Rahmen
	edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
frameAnchor:SetBackdropColor(0, 0, 0, 0.8) -- Dunkler Hintergrund mit 80% Transparenz

frameAnchor:SetMovable(true)
frameAnchor:EnableMouse(true)
frameAnchor:SetClampedToScreen(true)
-- Ensure hidden by default for Timerunners
if addon and addon.functions and addon.functions.IsTimerunner and addon.functions.IsTimerunner() then frameAnchor:Hide() end
frameAnchor:RegisterForDrag("LeftButton")
frameAnchor:SetScript("OnDragStart", function(self)
	if addon.db.teleportFrameLocked then return end
	if InCombatLockdown() then return end
	if not IsShiftKeyDown() then return end
	self:StartMoving()
end)
frameAnchor:SetScript("OnDragStop", function(self)
	if InCombatLockdown() then return end
	self:StopMovingOrSizing()
	local point, _, parentPoint, xOfs, yOfs = self:GetPoint()
	addon.db.teleportFrameData.point = point
	addon.db.teleportFrameData.parentPoint = parentPoint
	addon.db.teleportFrameData.x = xOfs
	addon.db.teleportFrameData.y = yOfs
end)

local btnDockTeleport = CreateFrame("Button", nil, frameAnchor)
btnDockTeleport:SetPoint("TOPRIGHT", frameAnchor, "TOPRIGHT", -5, -5)
btnDockTeleport:SetSize(16, 16)
btnDockTeleport.isDocked = true
local iconTeleport = btnDockTeleport:CreateTexture(nil, "ARTWORK")
iconTeleport:SetAllPoints(btnDockTeleport)
btnDockTeleport.icon = iconTeleport
if btnDockTeleport.isDocked then
	iconTeleport:SetTexture("Interface\\Addons\\EnhanceQoL\\Icons\\ClosedLock.tga")
else
	iconTeleport:SetTexture("Interface\\Addons\\EnhanceQoL\\Icons\\OpenLock.tga")
end
btnDockTeleport:SetScript("OnClick", function(self)
	self.isDocked = not self.isDocked
	addon.db.teleportFrameLocked = self.isDocked
	if self.isDocked then
		self.icon:SetTexture("Interface\\Addons\\EnhanceQoL\\Icons\\ClosedLock.tga")
	else
		self.icon:SetTexture("Interface\\Addons\\EnhanceQoL\\Icons\\OpenLock.tga")
	end
	addon.MythicPlus.functions.toggleFrame()
end)
btnDockTeleport:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if self.isDocked then
		GameTooltip:SetText(L["frameUnlock"])
	else
		GameTooltip:SetText(L["frameLock"])
	end
	GameTooltip:Show()
end)
btnDockTeleport:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Überschrift hinzufügen
local title = frameAnchor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -10)
title:SetFormattedText(CHALLENGES)
minFrameSize = max(title:GetStringWidth() + 20, 205)
SafeSetSize(frameAnchor, minFrameSize, 205)

-- Legacy in-frame compendium has been removed in favor of the modern World Map panel

local activeBars = {}
addon.MythicPlus.portalFrame = frameAnchor

local buttonSize = 30
local spacing = 15
local hSpacing = 30

local function CreatePortalButtonsWithCooldown(frame, spells)
	-- Entferne alle bestehenden Buttons
	for _, button in pairs(frame.buttons or {}) do
		button:Hide()
		button:ClearAllPoints()
	end
	frame.buttons = {}

	-- Sortiere und filtere die bekannten Spells
	local favoriteLookup = addon.db.teleportFavorites
	local favorites = {}
	local others = {}
	for spellID, data in pairs(spells) do
		local known = C_SpellBook.IsSpellInSpellBook(spellID)
		local isFavorite = favoriteLookup[spellID]
		local passes = (not data.faction or data.faction == faction)
		if addon.db["portalHideMissing"] then passes = passes and known end

		if passes or (isFavorite and (not addon.db["portalHideMissing"] or known)) then
			local entry = {
				spellID = spellID,
				text = data.text,
				iconID = data.iconID,
				isKnown = known,
				isFavorite = isFavorite,
			}
			if isFavorite then
				table.insert(favorites, entry)
			else
				table.insert(others, entry)
			end
		end
	end

	table.sort(favorites, function(a, b) return a.text < b.text end)
	table.sort(others, function(a, b) return a.text < b.text end)

	local sortedSpells = {}
	for _, v in ipairs(favorites) do
		table.insert(sortedSpells, v)
	end
	for _, v in ipairs(others) do
		table.insert(sortedSpells, v)
	end

	-- Berechne dynamische Anzahl der Buttons (robust, falls 0 Einträge)
	local totalButtons = #sortedSpells
	local buttonsPerRow = (totalButtons > 0) and math.ceil(totalButtons / 2) or 1
	local totalButtonWidth
	if totalButtons > 0 then
		totalButtonWidth = (buttonSize * buttonsPerRow) + (spacing * (buttonsPerRow - 1))
	else
		totalButtonWidth = 0
	end
	local frameWidth = math.max(totalButtonWidth + 40, title:GetStringWidth() + 20, minFrameSize)
	local initialSpacing = (totalButtonWidth > 0) and math.max(0, (frameWidth - totalButtonWidth) / 2) or 0

	-- Dynamische Höhe
	local rows = (totalButtons > 0) and math.ceil(totalButtons / buttonsPerRow) or 0
	local frameHeight = math.max(title:GetStringHeight() + 20, 40 + rows * (buttonSize + hSpacing))
	SafeSetSize(frame, frameWidth, frameHeight)

	-- Erstelle neue Buttons
	local index = 1
	for _, spellData in ipairs(sortedSpells) do
		local spellID = spellData.spellID
		local spellInfo = C_Spell.GetSpellInfo(spellID)

		if spellInfo then
			-- Button erstellen
			local button = CreateFrame("Button", "PortalButton" .. index, frame, "InsecureActionButtonTemplate")
			button:SetSize(buttonSize, buttonSize)
			button.spellID = spellID

			-- Hintergrund
			local bg = button:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints(button)
			bg:SetColorTexture(0, 0, 0, 0.8)

			-- Rahmen
			local border = button:CreateTexture(nil, "BORDER")
			border:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
			border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
			border:SetColorTexture(1, 1, 1, 1)

			-- Highlight/Glow-Effekt bei Mouseover
			local highlight = button:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints(button)
			highlight:SetColorTexture(1, 1, 0, 0.4) -- Gelber Glow mit 30% Transparenz
			button:SetHighlightTexture(highlight)

			-- Positionierung
			local row = math.ceil(index / buttonsPerRow) - 1
			local col = (index - 1) % buttonsPerRow
			button:SetPoint("TOPLEFT", frame, "TOPLEFT", initialSpacing + col * (buttonSize + spacing), -40 - row * (buttonSize + hSpacing))

			-- Icon
			local icon = button:CreateTexture(nil, "ARTWORK")
			icon:SetAllPoints(button)
			icon:SetTexture(spellInfo.iconID or "Interface\\ICONS\\INV_Misc_QuestionMark")
			button.icon = icon

			-- Favoritenanzeige
			local star = button:CreateTexture(nil, "OVERLAY")
			star:SetSize(12, 12)
			star:SetPoint("TOPRIGHT", -2, -2)
			star:SetTexture("Interface\\COMMON\\ReputationStar")
			if not spellData.isFavorite then star:Hide() end
			button.favoriteStar = star

			-- berprüfen, ob der Zauber bekannt ist
			if not spellData.isKnown then
				icon:SetDesaturated(true) -- Macht das Icon grau/schwarzweiß
				icon:SetAlpha(0.5) -- Optional: Reduziert die Sichtbarkeit
				button:EnableMouse(false) -- Deaktiviert Klicks auf den Button
			else
				isKnown[spellID] = true
				icon:SetDesaturated(false)
				icon:SetAlpha(1) -- Normale Sichtbarkeit
				button:EnableMouse(true) -- Aktiviert Klicks
			end

			-- Cooldown-Spirale
			button.cooldownFrame = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
			button.cooldownFrame:SetAllPoints(button)

			-- Sichere Aktion (CastSpell)
			button:SetAttribute("type1", "spell")
			button:SetAttribute("spell1", spellID)
			button:SetAttribute("type2", nil)
			button:SetAttribute("spell2", nil)

			-- store data reference for map pins (may include mapID/locID/x/y)
			button._eqolData = spells[spellID]

			button:RegisterForClicks("AnyUp", "AnyDown")
			button:SetScript("OnMouseUp", function(self, btn)
				if btn == "RightButton" then
					if IsShiftKeyDown() then
						local favs = addon.db.teleportFavorites
						if favs[self.spellID] then
							favs[self.spellID] = nil
						else
							favs[self.spellID] = true
						end
						checkCooldown()
					else
						local d = self._eqolData or {}
						local x, y = d.x, d.y
						local locID = d.locID
						if locID and x and y then OpenMapAndCreatePin(locID, x, y) end
					end
				end
			end)
			-- Text und Tooltip
			local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			label:SetPoint("TOP", button, "BOTTOM", 0, -2)
			label:SetText(spellData.text)

			button:SetScript("OnEnter", function(self)
				if addon.db["portalShowTooltip"] then
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetSpellByID(spellID)
					GameTooltip:Show()
				end
			end)
			button:SetScript("OnLeave", function() GameTooltip:Hide() end)

			-- Button speichern
			table.insert(frame.buttons, button)
			index = index + 1
		end
	end
end

local function isToyUsable(id)
	if id == nil then return false end
	local now = GetTime and GetTime() or 0

	local cached = toyUsableCache[id]
	if cached ~= nil then
		local cachedAt = toyUsableCacheTime[id] or 0
		if now == 0 or (cachedAt > 0 and (now - cachedAt) <= TOY_USABLE_CACHE_TTL) then return cached end
	end

	if not PlayerHasToy(id) then
		toyUsableCache[id] = false
		toyUsableCacheTime[id] = now
		return false
	end

	local tipData = C_TooltipInfo.GetToyByItemID(id)
	local lines = tipData and tipData.lines
	if lines then
		for i = 1, #lines do
			local line = lines[i]
			if line and line.type == 23 then
				local color = line.leftColor
				local usable = color and color.r == 1 and color.g == 1 and color.b == 1
				toyUsableCache[id] = usable and true or false
				toyUsableCacheTime[id] = now
				return toyUsableCache[id]
			end
		end
	end

	-- No requirement line means the toy is usable.
	toyUsableCache[id] = true
	toyUsableCacheTime[id] = now
	return true
end

local function checkProfession()
	-- Capture all profession slots into a table
	local professionIndices = { GetProfessions() }
	for _, profIndex in ipairs(professionIndices) do
		-- Only valid indices
		if profIndex and profIndex > 0 then
			local _, _, _, _, _, _, skillLine = GetProfessionInfo(profIndex)
			if skillLine == 202 then return true end
		end
	end
	return false
end

local GNOMISH = 20219
local GOBLIN = 20222
local function GetEngineeringBranch()
	if IsPlayerSpell(GNOMISH) or IsSpellKnown(GNOMISH) then
		return true, false -- Gnomish Engineering
	elseif IsPlayerSpell(GOBLIN) or IsSpellKnown(GOBLIN) then
		return false, true -- Goblin Engineering
	else
		return false, false -- keine Spezialisierung (oder kein Engineering)
	end
end

-- Returns a list of sections containing filtered, sorted entries built
-- with the exact same logic used by the in-frame Teleport Compendium.
-- Each section: { title = string, items = { {spellID, text, iconID, isToy, toyID, isItem, itemID, isKnown, isFavorite, isClassTP, isMagePortal, equipSlot} } }
function addon.MythicPlus.functions.BuildTeleportCompendiumSections()
	-- ensure seasonal portal cache is present for hideActualSeason filter
	if not portalSpells or next(portalSpells) == nil then
		if getCurrentSeasonPortal then getCurrentSeasonPortal() end
	end

	-- Resolve the display text for an entry, preferring "modern" or zone name
	local function resolveDisplayText(spellID, data)
		-- Default short label
		local label = data and data.text or ""

		-- 1) Explicit modern label on dataset
		if data and type(data.modern) == "string" and data.modern ~= "" then return data.modern end

		-- Helper to fetch and DB‑cache a map/zone name
		local function cachedMapName(keyPrefix, id)
			if not id then return nil end
			local cacheKey = tostring(keyPrefix) .. ":" .. tostring(id)
			addon.db.teleportNameCache = addon.db.teleportNameCache or {}
			local cached = addon.db.teleportNameCache[cacheKey]
			if cached and cached ~= "" then return cached end
			local mi = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
			local name = mi and mi.name or nil
			if name and name ~= "" then addon.db.teleportNameCache[cacheKey] = name end
			return name
		end

		-- 2) If an explicit zoneID is present, use its map name
		if data and type(data.zoneID) == "number" then
			local n = cachedMapName("zone", data.zoneID)
			if n and n ~= "" then return n end
		end

		-- 3) Some entries encode per‑variant zoneIDs inside mapID tables
		if data and type(data.mapID) == "table" then
			local keys = {}
			for cid in pairs(data.mapID) do
				table.insert(keys, cid)
			end
			table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
			for _, cid in ipairs(keys) do
				local v = data.mapID[cid]
				if type(v) == "table" and type(v.zoneID) == "number" then
					local n = cachedMapName("zone", v.zoneID)
					if n and n ~= "" then return n end
				end
			end
		end

		-- 4) Fallback (keep original short code)
		return label
	end

	local hasEngineering, hasGnomish, hasGoblin = checkProfession(), false, false
	if hasEngineering then
		hasGnomish, hasGoblin = GetEngineeringBranch()
	end
	local aMapID = C_Map.GetBestMapForUnit("player")
	local pMapID, tempMapInfo = nil, nil
	if aMapID then local tempMapInfo = C_Map.GetMapInfo(aMapID) end
	if tempMapInfo and tempMapInfo.parentMapID then pMapID = tempMapInfo.parentMapID end
	addon.MythicPlus.functions.setRandomHearthstone()

	local favorites = addon.db.teleportFavorites or {}
	local baseComp = addon.MythicPlus.variables.portalCompendium or {}
	local FAVORITES_SECTION_KEY = 10000 -- keep separate from HOME (9999)

	local timerunnerID = _G.PlayerGetTimerunningSeasonID and _G.PlayerGetTimerunningSeasonID() or nil

	-- Split out favourites into a separate section, no expansion-level hide anymore
	local working = {}
	local favSpells = {}
	for k, section in pairs(baseComp) do
		if (timerunnerID ~= nil and timerunnerID == section.timerunner) or (timerunnerID == nil) or section.ignoreTimerunner then
			local newSpells = {}
			for spellID, data in pairs(section.spells) do
				if favorites[spellID] then
					favSpells[spellID] = data
				else
					newSpells[spellID] = data
				end
			end
			working[k] = { headline = section.headline, spells = newSpells }
		end
	end
	if next(favSpells) then working[FAVORITES_SECTION_KEY] = { headline = FAVORITES, spells = favSpells } end

	-- Merge class/race teleports (section [10]) into HOME (section [9999])
	do
		local home = working[9999]
		if not home then
			home = { headline = HOME, spells = {} }
			working[9999] = home
		end
		home.spells = home.spells or {}
		local classSec = working[10]
		if classSec and classSec.spells then
			for spellID, data in pairs(classSec.spells) do
				if not home.spells[spellID] then home.spells[spellID] = data end
			end
			-- hide CLASS section from display, teleports live only in HOME
			working[10] = nil
		end
	end

	-- Sort sections high->low to mimic UI order
	local sectionOrder = {}
	for k in pairs(working) do
		table.insert(sectionOrder, k)
	end
	table.sort(sectionOrder, function(a, b) return a > b end)

	local out = {}
	for _, k in ipairs(sectionOrder) do
		local section = working[k]
		do
			local list = {}
			for spellID, data in pairs(section.spells) do
				-- Engineering specialization gate
				local specOk = true
				if data.isGnomish then specOk = specOk and hasGnomish end
				if data.isGoblin then specOk = specOk and hasGoblin end

				-- Handle multiple itemIDs by splitting into separate entries (optionally only show owned variants)
				-- If a class-specific mapping exists, only include the item for the player's class
				if data.isItem and type(data.itemID) == "table" then
					local allowedIDs = data.itemID
					if data.classItemID and addon.variables and addon.variables.unitClass then
						local classToken = addon.variables.unitClass
						local classSpecific = data.classItemID[classToken]
						if classSpecific then
							allowedIDs = { classSpecific }
						else
							allowedIDs = {} -- this class cannot use any of these variants
						end
					end
					local baseShow = specOk
						and (not data.faction or data.faction == faction)
						and (not data.map or ((type(data.map) == "number" and (data.map == aMapID or data.map == pMapID)) or (type(data.map) == "table" and (data.map[aMapID] or data.map[pMapID]))))
						and (not data.isEngineering or hasEngineering)
						and (not data.isClassTP or (addon.variables and addon.variables.unitClass == data.isClassTP))
						and (not data.isRaceTP or (addon.variables and addon.variables.unitRace == data.isRaceTP))
						and (not data.isMagePortal or (addon.variables and addon.variables.unitClass == "MAGE"))
						and (not data.timerunnerID or (data.timerunnerID == timerunnerID))

					if #allowedIDs > 0 then
						local showIDs = allowedIDs
						if data.ownedOnly then
							local ownedIDs = {}
							for _, iid in ipairs(allowedIDs) do
								if C_Item.GetItemCount(iid) > 0 then table.insert(ownedIDs, iid) end
							end
							if #ownedIDs > 0 then
								showIDs = ownedIDs
							else
								showIDs = { allowedIDs[1] }
							end
						end

						local otherVariants
						if data.ownedOnly and #allowedIDs > #showIDs then otherVariants = #allowedIDs - #showIDs end

						for _, iid in ipairs(showIDs) do
							local knownX = C_Item.GetItemCount(iid) > 0
							local showX = baseShow and (not addon.db["portalHideMissing"] or (addon.db["portalHideMissing"] and knownX))
							-- Favourites always bypass non-availability filters (except Hide Missing)
							if not showX and favorites[spellID] then showX = (not addon.db["portalHideMissing"] or (addon.db["portalHideMissing"] and knownX)) end
							if showX then
								local iconID = data.icon
								if not iconID then
									local _, _, itemIcon = C_Item.GetItemInfoInstant(iid)
									iconID = itemIcon
								end
								table.insert(list, {
									spellID = spellID,
									text = resolveDisplayText(spellID, data),
									iconID = iconID,
									isKnown = knownX,
									isToy = false,
									toyID = false,
									isItem = true,
									itemID = iid,
									variantOtherCount = otherVariants,
									isClassTP = data.isClassTP or false,
									isMagePortal = data.isMagePortal or false,
									equipSlot = data.equipSlot,
									isFavorite = favorites[spellID] and true or false,
									locID = data.locID,
									x = data.x,
									y = data.y,
								})
							end
						end
					end
				else
					local known = (C_SpellBook.IsSpellInSpellBook(spellID) and not data.isToy)
						or (hasEngineering and specOk and data.toyID and not data.isHearthstone and isToyUsable(data.toyID))
						or (data.isItem and C_Item.GetItemCount(FirstOwnedItemID(data.itemID)) > 0)
						or (data.isHearthstone and isToyUsable(data.toyID))

					local showSpell = specOk
						and (not data.faction or data.faction == faction)
						and (not data.map or ((type(data.map) == "number" and data.map == aMapID) or (type(data.map) == "table" and data.map[aMapID])))
						and (not data.isEngineering or hasEngineering)
						and (not data.isClassTP or (addon.variables and addon.variables.unitClass == data.isClassTP))
						and (not data.isRaceTP or (addon.variables and addon.variables.unitRace == data.isRaceTP))
						and (not data.isMagePortal or (addon.variables and addon.variables.unitClass == "MAGE"))
						and (not addon.db["portalHideMissing"] or (addon.db["portalHideMissing"] and known))
						and (not data.timerunnerID or (data.timerunnerID == timerunnerID))

					-- Favourites always bypass non-availability filters (except Hide Missing)
					if not showSpell and favorites[spellID] then showSpell = (not addon.db["portalHideMissing"] or (addon.db["portalHideMissing"] and known)) end

					if showSpell then
						local iconID
						local chosenItemID
						if data.isItem then
							chosenItemID = FirstOwnedItemID(data.itemID)
							local _, _, itemIcon = C_Item.GetItemInfoInstant(chosenItemID)
							iconID = data.icon or itemIcon
						elseif data.isToy then
							if data.icon then
								iconID = data.icon
							else
								local _, _, toyIcon = C_ToyBox.GetToyInfo(data.toyID)
								iconID = toyIcon
							end
						else
							local si = C_Spell.GetSpellInfo(spellID)
							iconID = si and si.iconID or nil
						end

						table.insert(list, {
							spellID = spellID,
							text = resolveDisplayText(spellID, data),
							iconID = iconID,
							isKnown = known,
							isToy = data.isToy or false,
							toyID = data.toyID or false,
							isItem = data.isItem or false,
							itemID = chosenItemID or data.itemID or false,
							isClassTP = data.isClassTP or false,
							isMagePortal = data.isMagePortal or false,
							equipSlot = data.equipSlot,
							isFavorite = favorites[spellID] and true or false,
							locID = data.locID,
							x = data.x,
							y = data.y,
						})
					end
				end
			end

			-- Stable-ish sort to match in-frame ordering rules with nil-safety
			table.sort(list, function(a, b)
				if a == nil and b == nil then return false end
				if a == nil then return false end
				if b == nil then return true end
				local at, bt = a.text or "", b.text or ""
				if at ~= bt then return at < bt end
				-- prefer class teleports over mage portals if same text
				local aTP = (a.isClassTP and true or false)
				local bTP = (b.isClassTP and true or false)
				local aPort, bPort = a.isMagePortal or false, b.isMagePortal or false
				if aTP ~= bTP then return aTP end
				if aPort ~= bPort then return not aPort end
				return (a.spellID or 0) < (b.spellID or 0)
			end)

			if #list > 0 then table.insert(out, { title = section.headline, items = list }) end
		end
	end

	return out
end

-- Build a single section containing only the current Mythic+ season dungeons,
-- mirroring availability rules from the compendium. Returns
-- { title = string, items = { entries... } }
function addon.MythicPlus.functions.BuildCurrentSeasonTeleportSection()
	-- Do not show the current season list for Timerunners
	if addon and addon.functions and addon.functions.IsTimerunner and addon.functions.IsTimerunner() then return nil end

	-- Determine active challenge map IDs for this season
	local activeSet = {}
	local mt = C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable() or {}
	for _, id in ipairs(mt) do
		activeSet[id] = true
	end

	-- Resolve the display text for an entry, preferring modern/zone names
	local function resolveDisplayText(spellID, data)
		local label = data and data.text or ""
		if data and type(data.modern) == "string" and data.modern ~= "" then return data.modern end

		local function cachedMapName(keyPrefix, id)
			if not id then return nil end
			local cacheKey = tostring(keyPrefix) .. ":" .. tostring(id)
			addon.db.teleportNameCache = addon.db.teleportNameCache or {}
			local cached = addon.db.teleportNameCache[cacheKey]
			if cached and cached ~= "" then return cached end
			local mi = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
			local name = mi and mi.name or nil
			if name and name ~= "" then addon.db.teleportNameCache[cacheKey] = name end
			return name
		end

		if data and type(data.zoneID) == "number" then
			local n = cachedMapName("zone", data.zoneID)
			if n and n ~= "" then return n end
		end

		if data and type(data.mapID) == "table" then
			local keys = {}
			for cid in pairs(data.mapID) do
				table.insert(keys, cid)
			end
			table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
			for _, cid in ipairs(keys) do
				local v = data.mapID[cid]
				if type(v) == "table" and type(v.zoneID) == "number" then
					local n = cachedMapName("zone", v.zoneID)
					if n and n ~= "" then return n end
				end
			end
		end
		return label
	end

	local hasEngineering, hasGnomish, hasGoblin = checkProfession(), false, false
	if hasEngineering then
		hasGnomish, hasGoblin = GetEngineeringBranch()
	end
	local aMapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local pMapID
	do
		local mi = aMapID and C_Map.GetMapInfo and C_Map.GetMapInfo(aMapID)
		if mi and mi.parentMapID then pMapID = mi.parentMapID end
	end
	addon.MythicPlus.functions.setRandomHearthstone()

	local favorites = addon.db.teleportFavorites or {}
	local baseComp = addon.MythicPlus.variables.portalCompendium or {}

	local list = {}
	for _, section in pairs(baseComp) do
		for spellID, data in pairs(section.spells or {}) do
			local inSeason = false
			if data.cId and type(data.cId) == "table" then
				for cId in pairs(data.cId) do
					if activeSet[cId] then
						inSeason = true
						break
					end
				end
			end
			if inSeason then
				local specOk = true
				if data.isGnomish then specOk = specOk and hasGnomish end
				if data.isGoblin then specOk = specOk and hasGoblin end

				-- Handle item variants per class (optionally only show owned variants)
				if data.isItem and type(data.itemID) == "table" then
					local allowedIDs = data.itemID
					if data.classItemID and addon.variables and addon.variables.unitClass then
						local classToken = addon.variables.unitClass
						local classSpecific = data.classItemID[classToken]
						if classSpecific then
							allowedIDs = { classSpecific }
						else
							allowedIDs = {}
						end
					end

					local baseShow = specOk
						and (not data.faction or data.faction == faction)
						and (not data.map or ((type(data.map) == "number" and (data.map == aMapID or data.map == pMapID)) or (type(data.map) == "table" and (data.map[aMapID] or data.map[pMapID]))))
						and (not data.isEngineering or hasEngineering)
						and (not data.isClassTP or (addon.variables and addon.variables.unitClass == data.isClassTP))
						and (not data.isRaceTP or (addon.variables and addon.variables.unitRace == data.isRaceTP))
						and (not data.isMagePortal or (addon.variables and addon.variables.unitClass == "MAGE"))

					if #allowedIDs > 0 then
						local showIDs = allowedIDs
						if data.ownedOnly then
							local ownedIDs = {}
							for _, iid in ipairs(allowedIDs) do
								if C_Item.GetItemCount(iid) > 0 then table.insert(ownedIDs, iid) end
							end
							if #ownedIDs > 0 then
								showIDs = ownedIDs
							else
								showIDs = { allowedIDs[1] }
							end
						end

						local otherVariants
						if data.ownedOnly and #allowedIDs > #showIDs then otherVariants = #allowedIDs - #showIDs end

						for _, iid in ipairs(showIDs) do
							local knownX = C_Item.GetItemCount(iid) > 0
							local showX = baseShow and (not addon.db["portalHideMissing"] or (addon.db["portalHideMissing"] and knownX))
							if not showX and favorites[spellID] then showX = (not addon.db["portalHideMissing"] or (addon.db["portalHideMissing"] and knownX)) end
							if showX then
								local iconID = data.icon
								if not iconID then
									local _, _, itemIcon = C_Item.GetItemInfoInstant(iid)
									iconID = itemIcon
								end
								table.insert(list, {
									spellID = spellID,
									text = resolveDisplayText(spellID, data),
									iconID = iconID,
									isKnown = knownX,
									isToy = false,
									toyID = false,
									isItem = true,
									itemID = iid,
									variantOtherCount = otherVariants,
									isClassTP = data.isClassTP or false,
									isMagePortal = data.isMagePortal or false,
									equipSlot = data.equipSlot,
									isFavorite = favorites[spellID] and true or false,
									locID = data.locID,
									x = data.x,
									y = data.y,
								})
							end
						end
					end
				else
					local known = (C_SpellBook.IsSpellInSpellBook(spellID) and not data.isToy)
						or (hasEngineering and specOk and data.toyID and not data.isHearthstone and isToyUsable(data.toyID))
						or (data.isItem and C_Item.GetItemCount(FirstOwnedItemID(data.itemID)) > 0)
						or (data.isHearthstone and isToyUsable(data.toyID))

					local showSpell = specOk
						and (not data.faction or data.faction == faction)
						and (not data.map or ((type(data.map) == "number" and data.map == aMapID) or (type(data.map) == "table" and data.map[aMapID])))
						and (not data.isEngineering or hasEngineering)
						and (not data.isClassTP or (addon.variables and addon.variables.unitClass == data.isClassTP))
						and (not data.isRaceTP or (addon.variables and addon.variables.unitRace == data.isRaceTP))
						and (not data.isMagePortal or (addon.variables and addon.variables.unitClass == "MAGE"))
						and (not addon.db["portalHideMissing"] or (addon.db["portalHideMissing"] and known))

					if not showSpell and favorites[spellID] then showSpell = (not addon.db["portalHideMissing"] or (addon.db["portalHideMissing"] and known)) end

					if showSpell then
						local iconID
						local chosenItemID
						if data.isItem then
							chosenItemID = FirstOwnedItemID(data.itemID)
							local _, _, itemIcon = C_Item.GetItemInfoInstant(chosenItemID)
							iconID = data.icon or itemIcon
						elseif data.isToy then
							if data.icon then
								iconID = data.icon
							else
								local _, _, toyIcon = C_ToyBox.GetToyInfo(data.toyID)
								iconID = toyIcon
							end
						else
							local si = C_Spell.GetSpellInfo(spellID)
							iconID = si and si.iconID or nil
						end

						table.insert(list, {
							spellID = spellID,
							text = resolveDisplayText(spellID, data),
							iconID = iconID,
							isKnown = known,
							isToy = data.isToy or false,
							toyID = data.toyID or false,
							isItem = data.isItem or false,
							itemID = chosenItemID or data.itemID or false,
							isClassTP = data.isClassTP or false,
							isMagePortal = data.isMagePortal or false,
							equipSlot = data.equipSlot,
							isFavorite = favorites[spellID] and true or false,
							locID = data.locID,
							x = data.x,
							y = data.y,
						})
					end
				end
			end
		end
	end

	table.sort(list, function(a, b)
		if a == nil and b == nil then return false end
		if a == nil then return false end
		if b == nil then return true end
		local at, bt = a.text or "", b.text or ""
		if at ~= bt then return at < bt end
		local aTP = (a.isClassTP and true or false)
		local bTP = (b.isClassTP and true or false)
		local aPort, bPort = a.isMagePortal or false, b.isMagePortal or false
		if aTP ~= bTP then return aTP end
		if aPort ~= bPort then return not aPort end
		return (a.spellID or 0) < (b.spellID or 0)
	end)

	local title = CHALLENGES
	if type(title) == "string" then title = string.gsub(title, "%s*%b()", "") end
	return { title = title or "Mythic+ Season", items = list }
end

function checkCooldown()
	if addon.db["teleportFrame"] then CreatePortalButtonsWithCooldown(frameAnchor, portalSpells) end

	for _, button in pairs(frameAnchor.buttons or {}) do
		if isKnown[button.spellID] then
			local cooldownData, isSecret = GetCooldownData(button)
			if isSecret and button.cooldownFrame.SetCooldownFromDuration then
				if cooldownData then button.cooldownFrame:SetCooldownFromDuration(cooldownData) end
			elseif cooldownData and cooldownData.isEnabled then
				button.cooldownFrame:SetCooldown(cooldownData.startTime, cooldownData.duration, cooldownData.modRate)
			else
				button.cooldownFrame:SetCooldown(0, 0)
			end
		end
	end
end

local function waitCooldown(arg3)
	C_Timer.After(0.1, function()
		local spellInfo = allSpells[arg3]
		local cooldownData = GetCooldownData(spellInfo)
		if cooldownData and cooldownData.duration > 0 then
			checkCooldown()
		else
			waitCooldown(arg3)
		end
	end)
end

local textList = {}
local textListUsed = 0
local gFrameAnchorScore

local function acquireRioText(index)
	local fs = textList[index]
	if fs then return fs end
	fs = gFrameAnchorScore:CreateFontString(nil, "OVERLAY")
	fs:SetFont(addon.variables.defaultFont, 14, "OUTLINE")
	textList[index] = fs
	return fs
end

local function updateRioLockButton(button)
	if not (button and button.icon) then return end
	button.isDocked = addon.db.dungeonScoreFrameLocked and true or false
	if button.isDocked then
		button.icon:SetTexture("Interface\\Addons\\EnhanceQoL\\Icons\\ClosedLock.tga")
	else
		button.icon:SetTexture("Interface\\Addons\\EnhanceQoL\\Icons\\OpenLock.tga")
	end
end

local function hideUnusedRioText()
	for i = textListUsed + 1, #textList do
		textList[i]:Hide()
	end
end

local function createString(textLeft, textRight, colorLeft, colorRight, anchor, selected)
	textListUsed = textListUsed + 1
	local titleScore1 = acquireRioText(textListUsed)
	titleScore1:SetFormattedText(textLeft)
	titleScore1:ClearAllPoints()
	titleScore1:SetPoint("TOPLEFT", 7, (addon.functions.getHeightOffset(anchor) - 10))
	if selected then
		titleScore1:SetTextColor(0, 1, 0, 1)
	elseif colorLeft then
		titleScore1:SetTextColor(colorLeft.r, colorLeft.g, colorLeft.b, 1)
	else
		titleScore1:SetTextColor(1, 1, 1, 1)
	end
	titleScore1:Show()

	textListUsed = textListUsed + 1
	local titleScoreValue = acquireRioText(textListUsed)
	titleScoreValue:SetFormattedText(textRight)
	titleScoreValue:ClearAllPoints()
	titleScoreValue:SetPoint("TOPRIGHT", -7, (addon.functions.getHeightOffset(anchor) - 10))
	if colorRight then
		titleScoreValue:SetTextColor(colorRight.r, colorRight.g, colorRight.b, 1)
	else
		titleScoreValue:SetTextColor(1, 1, 1, 1)
	end
	titleScoreValue:Show()
	return titleScore1
end

local function ensureRioScoreFrame()
	if gFrameAnchorScore then return gFrameAnchorScore end

	local frameAnchorScore = _G["EQOLDungeonScoreFrame"]
	if not frameAnchorScore then frameAnchorScore = CreateFrame("Frame", "EQOLDungeonScoreFrame", parentFrame, "BackdropTemplate") end
	gFrameAnchorScore = frameAnchorScore
	if frameAnchorScore._eqolRioInitialized then return frameAnchorScore end

	frameAnchorScore._eqolRioInitialized = true
	frameAnchorScore:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frameAnchorScore:SetBackdropColor(0, 0, 0, 0.8)
	frameAnchorScore:SetFrameStrata("TOOLTIP")
	frameAnchorScore:SetMovable(true)
	frameAnchorScore:EnableMouse(true)
	frameAnchorScore:SetClampedToScreen(true)
	frameAnchorScore:RegisterForDrag("LeftButton")
	frameAnchorScore:SetScript("OnDragStart", function(self)
		if addon.db.dungeonScoreFrameLocked then return end
		if InCombatLockdown() then return end
		if not IsShiftKeyDown() then return end
		self:StartMoving()
	end)
	frameAnchorScore:SetScript("OnDragStop", function(self)
		if InCombatLockdown() then return end
		self:StopMovingOrSizing()
		local point, _, parentPoint, xOfs, yOfs = self:GetPoint()
		addon.db.dungeonScoreFrameData.point = point
		addon.db.dungeonScoreFrameData.parentPoint = parentPoint
		addon.db.dungeonScoreFrameData.x = xOfs
		addon.db.dungeonScoreFrameData.y = yOfs
	end)

	local btnDockScore = CreateFrame("Button", nil, frameAnchorScore)
	btnDockScore:SetPoint("TOPRIGHT", frameAnchorScore, "TOPRIGHT", -5, -5)
	btnDockScore:SetSize(16, 16)
	local iconScore = btnDockScore:CreateTexture(nil, "ARTWORK")
	iconScore:SetAllPoints(btnDockScore)
	btnDockScore.icon = iconScore
	updateRioLockButton(btnDockScore)
	btnDockScore:SetScript("OnClick", function(self)
		self.isDocked = not self.isDocked
		addon.db.dungeonScoreFrameLocked = self.isDocked
		updateRioLockButton(self)
		addon.MythicPlus.functions.toggleFrame()
	end)
	btnDockScore:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.isDocked then
			GameTooltip:SetText(L["frameUnlock"])
		else
			GameTooltip:SetText(L["frameLock"])
		end
		GameTooltip:Show()
	end)
	btnDockScore:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frameAnchorScore.btnDockScore = btnDockScore

	local titleScore = frameAnchorScore:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	titleScore:SetFormattedText(DUNGEON_SCORE)
	titleScore:SetPoint("TOP", 0, -10)
	frameAnchorScore.titleScore = titleScore

	return frameAnchorScore
end

local function updateRioScoreFrame()
	if not gFrameAnchorScore then return end

	local frameAnchorScore = gFrameAnchorScore
	local titleScore = frameAnchorScore.titleScore
	updateRioLockButton(frameAnchorScore.btnDockScore)
	titleScore:SetFormattedText(DUNGEON_SCORE)

	minFrameSize = max(titleScore:GetStringWidth() + 20, title:GetStringWidth() + 20, 205, minFrameSize)
	SafeSetSize(frameAnchorScore, minFrameSize, 170)
	if addon.db["teleportFrame"] then
		frameAnchorScore:ClearAllPoints()
		frameAnchorScore:SetPoint("TOPLEFT", DungeonTeleportFrame, "BOTTOMLEFT", 0, 0)
	elseif nil ~= RaiderIO_ProfileTooltip then
		local offsetX = RaiderIO_ProfileTooltip:GetSize()
		frameAnchorScore:ClearAllPoints()
		frameAnchorScore:SetPoint("TOPLEFT", parentFrame, "TOPRIGHT", offsetX, 0)
	else
		frameAnchorScore:ClearAllPoints()
		frameAnchorScore:SetPoint("TOPLEFT", parentFrame, "TOPRIGHT", 0, 0)
	end
	if not addon.db.dungeonScoreFrameLocked and addon.db.dungeonScoreFrameData and addon.db.dungeonScoreFrameData.point then
		frameAnchorScore:ClearAllPoints()
		frameAnchorScore:SetPoint(addon.db.dungeonScoreFrameData.point, UIParent, addon.db.dungeonScoreFrameData.parentPoint, addon.db.dungeonScoreFrameData.x, addon.db.dungeonScoreFrameData.y)
	end
	SafeSetSize(frameAnchor, minFrameSize, 170)

	textListUsed = 0

	local ratingInfo = {}
	local _, _, timeLimit
	local rating = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
	if rating then
		for _, key in pairs(rating.runs) do
			ratingInfo[key.challengeModeID] = key
		end

		local r, g, b = C_ChallengeMode.GetDungeonScoreRarityColor(rating.currentSeasonScore):GetRGB()
		local l1 = createString(BATTLEGROUND_RATING, rating.currentSeasonScore, nil, { r = r, g = g, b = b }, titleScore)
		local nWidth = l1:GetStringWidth() + 60
		local dungeonList = {}

		for _, key in pairs(C_ChallengeMode.GetMapTable()) do
			_, _, timeLimit = C_ChallengeMode.GetMapUIInfo(key)
			r, g, b = 0.5, 0.5, 0.5

			local data = key
			local mId = key
			local stars = 0
			local score = 0
			if ratingInfo[key] then
				data = ratingInfo[key]
				mId = data.challengeModeID

				if data.bestRunLevel > 0 then
					r, g, b = 1, 1, 1

					local bestRunDuration = data.bestRunDurationMS / 1000
					local timeForPlus3 = timeLimit * 0.6
					local timeForPlus2 = timeLimit * 0.8
					local timeForPlus1 = timeLimit
					score = data.mapScore
					if bestRunDuration <= timeForPlus3 then
						stars = "|cFFFFD700+++|r"
					elseif bestRunDuration <= timeForPlus2 then
						stars = "|cFFFFD700++|r"
					elseif bestRunDuration <= timeForPlus1 then
						stars = "|cFFFFD700+|r"
					else
						stars = ""
						r = 0.5
						g = 0.5
						b = 0.5
					end
					stars = stars .. data.bestRunLevel
				else
					stars = 0
					r = 0.5
					g = 0.5
					b = 0.5
				end
			end

			local selected = false
			if key == selectedMapId then selected = true end
			table.insert(dungeonList, {
				text = addon.MythicPlus.variables.challengeMapID[mId] or "UNKNOWN",
				stars = stars,
				score = score,
				r = r,
				g = g,
				b = b,
				select = selected,
			})
		end

		table.sort(dungeonList, function(a, b) return a.score > b.score end)

		local lastElement = l1
		for _, dungeon in ipairs(dungeonList) do
			lastElement = createString(dungeon.text, dungeon.stars, nil, { r = dungeon.r, g = dungeon.g, b = dungeon.b }, lastElement, dungeon.select)
		end

		local _, _, _, _, lp = lastElement:GetPoint()
		minFrameSize = max(nWidth + 20, 205, title:GetStringWidth() + 20, minFrameSize)
		SafeSetSize(frameAnchorScore, minFrameSize, max(lp * -1 + 30, 170))
		SafeSetSize(frameAnchor, minFrameSize, 170)
	end

	hideUnusedRioText()
	frameAnchorScore:Show()
end

local function CreateRioScore()
	if addon and addon.functions and addon.functions.IsTimerunner and addon.functions.IsTimerunner() then
		if gFrameAnchorScore then gFrameAnchorScore:Hide() end
		return
	end
	if addon.variables.maxLevel ~= UnitLevel("player") then
		if gFrameAnchorScore then gFrameAnchorScore:Hide() end
		return
	end
	if addon.db["groupfinderShowDungeonScoreFrame"] ~= true then
		if gFrameAnchorScore then gFrameAnchorScore:Hide() end
		return
	end

	ensureRioScoreFrame()
	updateRioScoreFrame()
end

local keyStoneFrame
local measureFontString
local function calculateMaxWidth(dataTable)
	local maxWidth = 0
	for key, data in pairs(dataTable) do
		if UnitInParty(key) or key == UnitName("player") then
			if not measureFontString then return end
			local widthMap = 0
			if data.challengeMapID and data.challengeMapID > 0 then
				local mapData = mapInfo[data.challengeMapID]
				if not mapData then mapData = { mapName = L["NoKeystone"] } end
				measureFontString:SetText(mapData.mapName or "")
				widthMap = measureFontString:GetStringWidth() + 25 + buttonSize
			else
				measureFontString:SetText(L["NoKeystone"] or "")
				widthMap = measureFontString:GetStringWidth() + 25 + buttonSize
			end
			local uName = UnitName(key)

			measureFontString:SetText(uName or "")
			local widthCharName = measureFontString:GetStringWidth() + 25 + buttonSize
			local width = max(widthCharName, widthMap)
			if width > maxWidth then maxWidth = width end
		end
	end
	return maxWidth
end

local function updateKeystoneInfo()
	if InCombatLockdown() then
		doAfterCombat = true
		return
	end
	if isRestrictedContent() then return end
	if parentFrame:IsShown() then
		local minHightOffset = 0
		if PVEFrameTab1 and PVEFrameTab1:IsVisible() then minHightOffset = 0 - PVEFrameTab1:GetHeight() end
		if not keyStoneFrame then
			keyStoneFrame = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
			SafeSetSize(keyStoneFrame, 200, 300)
			keyStoneFrame:Show()
		else
			for _, child in ipairs({ keyStoneFrame:GetChildren() }) do
				child:Hide()
				child:SetParent(nil)
			end
		end
		if IsInRaid() then return end
		keyStoneFrame:SetPoint("TOPRIGHT", parentFrame, "BOTTOMRIGHT", 0, minHightOffset)
		if #portalSpells == 0 then getCurrentSeasonPortal() end
		local keystoneData = openRaidLib.GetAllKeystonesInfo()

		if keystoneData then
			local unitsAdded = {}
			local isOnline = true

			local maxWidthKeystone = calculateMaxWidth(keystoneData)

			local index = 0
			for key, data in pairs(keystoneData) do
				local uName, uRealm = UnitName(key)
				data.charName = uName
				data.classColor = RAID_CLASS_COLORS[select(2, UnitClass(key))] or { r = 1, g = 1, b = 1 }

				if UnitInParty(key) or key == addon.variables.unitName then
					local mapData
					if data.challengeMapID and data.challengeMapID > 0 then
						mapData = mapInfo[data.challengeMapID]
						if not mapData then mapData = {
							mapName = L["NoKeystone"],
						} end
					else
						mapData = {
							mapName = L["NoKeystone"],
						}
					end
					local frame = CreateFrame("Frame", nil, keyStoneFrame, "BackdropTemplate")
					SafeSetSize(frame, maxWidthKeystone, 50)
					frame:SetPoint("TOPRIGHT", keyStoneFrame, "TOPRIGHT", 0, -50 * index)
					frame:SetBackdrop({
						bgFile = "Interface\\Buttons\\WHITE8x8", -- Hintergrund
						edgeFile = nil, -- Rahmen
						edgeSize = 16,
						insets = { left = 4, right = 4, top = 1, bottom = 0 },
					})
					frame:SetBackdropColor(0, 0, 0, 0.8) -- Dunkler Hintergrund mit 80% Transparenz
					frame:Show()

					-- Button erstellen
					local button = CreateFrame("Button", nil, frame, "InsecureActionButtonTemplate")
					button:SetSize(buttonSize, buttonSize)
					button:SetPoint("LEFT", frame, "LEFT", 10, 0)
					if mapData.spellId then button.spellID = mapData.spellId end
					-- Dungeonname (zum Beispiel rechtsbündig)
					local dungeonText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
					dungeonText:SetPoint("TOPLEFT", button, "TOPRIGHT", 5, 0)
					dungeonText:SetText(mapData.mapName or "Unknown Dungeon")

					-- Hintergrund
					local bg = button:CreateTexture(nil, "BACKGROUND")
					bg:SetAllPoints(button)
					bg:SetColorTexture(0, 0, 0, 0.8)

					-- Rahmen
					local border = button:CreateTexture(nil, "BORDER")
					border:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
					border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
					border:SetColorTexture(1, 1, 1, 1)

					-- Highlight/Glow-Effekt
					local highlight = button:CreateTexture(nil, "HIGHLIGHT")
					highlight:SetAllPoints(button)
					highlight:SetColorTexture(1, 1, 0, 0.4)
					button:SetHighlightTexture(highlight)

					-- Icon
					local icon = button:CreateTexture(nil, "ARTWORK")
					icon:SetAllPoints(button)
					icon:SetTexture(mapData.texture or "Interface\\ICONS\\INV_Misc_QuestionMark")
					button.icon = icon

					-- Überprüfen, ob der Zauber bekannt ist
					if mapData.spellId and C_SpellBook.IsSpellInSpellBook(mapData.spellId) then
						local cooldownData = C_Spell.GetSpellCooldown(mapData.spellId)
						if cooldownData and cooldownData.isEnabled then
							button:EnableMouse(true) -- Aktiviert Klicks

							-- Cooldown-Spirale
							button:SetAttribute("type", "spell")
							button:SetAttribute("spell", mapData.spellId)
							button:RegisterForClicks("AnyUp", "AnyDown")
						else
							button:EnableMouse(false)
						end
					else
						button:EnableMouse(false) -- Deaktiviert Klicks auf den Button
					end

					if data.level and data.level > 0 then
						-- Key-Level als Text
						local levelText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
						levelText:SetPoint("CENTER", button, "CENTER", 0, 0)
						levelText:SetText((data.level or "0"))
						levelText:SetTextColor(1, 1, 1)
					end
					-- Spielername in Klassenfarbe
					local playerNameText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
					playerNameText:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT", 5, 0)

					local classColor = data.classColor
					playerNameText:SetText(data.charName)
					playerNameText:SetTextColor(classColor.r, classColor.g, classColor.b)
					index = index + 1
				end
			end
		end
	end
end

function addon.MythicPlus.onKeystoneUpdate(unitName, keystoneInfo, keystoneData)
	if parentFrame:IsShown() then updateKeystoneInfo() end
end

local isRegistered = false
function addon.MythicPlus.functions.togglePartyKeystone()
	if InCombatLockdown() then
		doAfterCombat = true
	else
		if addon.db["groupfinderShowPartyKeystone"] and not IsInRaid() then
			if not isRegistered then
				isRegistered = true
				measureFontString = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
				measureFontString:Hide()
				openRaidLib.RegisterCallback(addon.MythicPlus, "KeystoneUpdate", "onKeystoneUpdate")
				openRaidLib.RequestKeystoneDataFromParty()
			end
		else
			isRegistered = false
			measureFontString = nil
			if keyStoneFrame then
				keyStoneFrame:Hide()
				keyStoneFrame:SetParent(nil)
				keyStoneFrame = nil
			end
			openRaidLib.UnregisterCallback(addon.MythicPlus, "KeystoneUpdate", "onKeystoneUpdate")
			openRaidLib.WipeKeystoneData()
		end
	end
end

function addon.MythicPlus.triggerRequest()
	if not IsInRaid() then openRaidLib.RequestKeystoneDataFromParty() end
end

function addon.MythicPlus.functions.toggleFrame()
	if InCombatLockdown() then
		doAfterCombat = true
	else
		doAfterCombat = false
		if isRestrictedContent() then
			if frameAnchor then frameAnchor:Hide() end
			if keyStoneFrame then keyStoneFrame:Hide() end
			return
		end
		-- Never show teleport frame for Timerunners
		if addon and addon.functions and addon.functions.IsTimerunner and addon.functions.IsTimerunner() then
			frameAnchor:Hide()
			return
		end
		frameAnchor:SetAlpha(1)
		if nil ~= RaiderIO_ProfileTooltip then
			C_Timer.After(0.1, function()
				if InCombatLockdown() then
					doAfterCombat = true
				else
					CreateRioScore()
				end
			end)
		else
			CreateRioScore()
		end
		if addon.db["teleportFrame"] then
			if #portalSpells == 0 then getCurrentSeasonPortal() end
			checkCooldown()

			-- Based on RaiderIO Client place the Frame
			if nil ~= RaiderIO_ProfileTooltip then
				C_Timer.After(0.1, function()
					if InCombatLockdown() then
						doAfterCombat = true
					else
						CreateRioScore()
						local offsetX = RaiderIO_ProfileTooltip:GetSize()
						if addon.db.teleportFrameLocked then
							frameAnchor:ClearAllPoints()
							frameAnchor:SetPoint("TOPLEFT", parentFrame, "TOPRIGHT", offsetX, 0)
						elseif addon.db.teleportFrameData.point then
							frameAnchor:ClearAllPoints()
							frameAnchor:SetPoint(addon.db.teleportFrameData.point, UIParent, addon.db.teleportFrameData.parentPoint, addon.db.teleportFrameData.x, addon.db.teleportFrameData.y)
						end
					end
				end)
			else
				if addon.db.teleportFrameLocked then
					frameAnchor:ClearAllPoints()
					frameAnchor:SetPoint("TOPLEFT", parentFrame, "TOPRIGHT", 0, 0)
				elseif addon.db.teleportFrameData.point then
					frameAnchor:ClearAllPoints()
					frameAnchor:SetPoint(addon.db.teleportFrameData.point, UIParent, addon.db.teleportFrameData.parentPoint, addon.db.teleportFrameData.x, addon.db.teleportFrameData.y)
				end
			end

			-- Set Visibility
			if addon.db["teleportFrame"] == true and not (addon and addon.functions and addon.functions.IsTimerunner and addon.functions.IsTimerunner()) then
				if not frameAnchor:IsShown() then frameAnchor:Show() end
			else
				frameAnchor:Hide()
			end
		else
			frameAnchor:Hide()
		end
		if addon.db["groupfinderShowPartyKeystone"] then
			addon.MythicPlus.triggerRequest()
			updateKeystoneInfo() -- precall to check if we have all information already
		end
	end
end

-- Buttons erstellen
local function eventHandler(self, event, arg1, arg2, arg3, arg4)
	-- Never show teleport frame for Timerunners
	if addon and addon.functions and addon.functions.IsTimerunner and addon.functions.IsTimerunner() then
		if frameAnchor then frameAnchor:Hide() end
		return
	end
	if addon.db["teleportFrame"] then
		if InCombatLockdown() then
			doAfterCombat = true
		else
			if event == "ADDON_LOADED" and arg1 == addonName then
				CreatePortalButtonsWithCooldown(frameAnchor, portalSpells)
				CreateRioScore()
				frameAnchor:SetPoint("TOPLEFT", parentFrame, "TOPRIGHT", 230, 0)
				if not (addon and addon.functions and addon.functions.IsTimerunner and addon.functions.IsTimerunner()) then
					frameAnchor:Show()
				else
					frameAnchor:Hide()
				end
			elseif event == "GROUP_JOINED" then
				if PVEFrame:IsShown() then
					addon.MythicPlus.triggerRequest() -- because I won't get the information from the people already in party otherwise
				end
			elseif event == "GROUP_ROSTER_UPDATE" then
				if (IsInRaid() and isRegistered) or (not IsInRaid() and not isRegistered) then addon.MythicPlus.functions.togglePartyKeystone() end
			elseif parentFrame:IsShown() then -- Only do stuff, when PVEFrame Open
				if event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
					if allSpells[arg3] then waitCooldown(arg3) end
				elseif event == "ENCOUNTER_END" and arg3 == 8 then
					C_Timer.After(0.1, function() checkCooldown() end)
				elseif event == "SPELL_DATA_LOAD_RESULT" and portalSpells[arg1] then
					print("Loaded", portalSpells[arg1].text)
				elseif event == "PLAYER_REGEN_ENABLED" then
					if doAfterCombat then
						if (IsInRaid() and isRegistered) or (not IsInRaid() and not isRegistered) then addon.MythicPlus.functions.togglePartyKeystone() end
						addon.MythicPlus.functions.toggleFrame()
					end
				end
			end
		end
	end
end

function addon.MythicPlus.functions.InitDungeonPortal()
	if addon.MythicPlus.variables.dungeonPortalInitialized then return end
	if not addon.db then return end
	addon.MythicPlus.variables.dungeonPortalInitialized = true

	btnDockTeleport.isDocked = addon.db.teleportFrameLocked and true or false
	if btnDockTeleport.icon then
		if btnDockTeleport.isDocked then
			btnDockTeleport.icon:SetTexture("Interface\\Addons\\EnhanceQoL\\Icons\\ClosedLock.tga")
		else
			btnDockTeleport.icon:SetTexture("Interface\\Addons\\EnhanceQoL\\Icons\\OpenLock.tga")
		end
	end

	if addon.db["groupfinderShowPartyKeystone"] then addon.MythicPlus.functions.togglePartyKeystone() end

	frameAnchor:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	frameAnchor:RegisterEvent("ENCOUNTER_END")
	frameAnchor:RegisterEvent("ADDON_LOADED")
	frameAnchor:RegisterEvent("SPELL_DATA_LOAD_RESULT")
	frameAnchor:RegisterEvent("PLAYER_REGEN_ENABLED")
	frameAnchor:RegisterEvent("GROUP_ROSTER_UPDATE")
	frameAnchor:RegisterEvent("GROUP_JOINED")

	if GameTooltip and not addon.MythicPlus.variables.dungeonPortalTooltipHooked then
		GameTooltip:HookScript("OnShow", function(self)
			if PVEFrame:IsVisible() then
				selectedMapId = nil
				local owner = self:GetOwner()
				if
					owner
					and owner.GetParent
					and LFGListFrame
					and LFGListFrame.SearchPanel
					and LFGListFrame.SearchPanel.ScrollBox
					and LFGListFrame.SearchPanel.ScrollBox.ScrollTarget
					and owner:GetParent() == LFGListFrame.SearchPanel.ScrollBox.ScrollTarget
				then
					local resultID = owner.resultID
					if resultID then
						local searchResultInfo = C_LFGList.GetSearchResultInfo(resultID)
						if searchResultInfo then
							local mapData = C_LFGList.GetActivityInfoTable(searchResultInfo.activityIDs[1])
							if mapData then
								if mapIDInfo[mapData.mapID] then selectedMapId = mapIDInfo[mapData.mapID] end
							end
						end
					end
					CreateRioScore()
					local offsetX = 0
					if nil ~= RaiderIO_ProfileTooltip then offsetX = RaiderIO_ProfileTooltip:GetSize() end
					if gFrameAnchorScore and addon.db["dungeonScoreFrameLocked"] then gFrameAnchorScore:SetPoint("TOPLEFT", GameTooltip, "TOPRIGHT", offsetX, 0) end

					if addon.db["teleportFrame"] then frameAnchor:SetAlpha(0) end
				end
			end
		end)
		GameTooltip:HookScript("OnHide", function(self)
			if PVEFrame:IsVisible() then
				selectedMapId = nil
				local owner = self:GetOwner()
				CreateRioScore()
				if addon.db["teleportFrame"] then frameAnchor:SetAlpha(1) end
			end
		end)
		addon.MythicPlus.variables.dungeonPortalTooltipHooked = true
	end

	-- Setze den Event-Handler
	frameAnchor:SetScript("OnEvent", eventHandler)

	if parentFrame and parentFrame.HookScript and not parentFrame._eqolMythicPlusPortalHook then
		parentFrame:HookScript("OnShow", function(self) addon.MythicPlus.functions.toggleFrame() end)
		parentFrame._eqolMythicPlusPortalHook = true
	end
end
