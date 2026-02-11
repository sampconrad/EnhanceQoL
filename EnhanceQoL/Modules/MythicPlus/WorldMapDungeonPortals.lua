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

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_MythicPlus")

-- Lightweight World Map side-panel for Dungeon Portals, with a small tab
-- that sits together with the default Map Legend / Quest tabs. The panel
-- lists all teleports from addon.MythicPlus.variables.portalCompendium,
-- honoring favorites and the main teleport options where reasonable.

local f = CreateFrame("Frame")
local DISPLAY_MODE = "EQOL_DungeonPortals"
local ICON_ACTIVE = "Interface\\AddOns\\EnhanceQoL\\Modules\\MythicPlus\\Art\\teleport_active.tga"
local ICON_INACTIVE = "Interface\\AddOns\\EnhanceQoL\\Modules\\MythicPlus\\Art\\teleport_inactive.tga"

_G["BINDING_NAME_EQOL_TOGGLE_WORLDMAP_TELEPORT"] = L["teleportsWorldMapBinding"] or "Toggle World Map Teleport panel"

local function GetPlayerMapID()
	if C_Map and C_Map.GetBestMapForUnit then return C_Map.GetBestMapForUnit("player") end
	return nil
end

-- Cache some frequently used API
local FirstOwnedItemID
do
	local GetItemCount = C_Item.GetItemCount
	function FirstOwnedItemID(itemID)
		if type(itemID) == "table" then
			for _, id in ipairs(itemID) do
				if GetItemCount(id) > 0 then return id end
			end
			return itemID[1]
		end
		return itemID
	end
end

local function IsToyUsable(id)
	if not id or not PlayerHasToy(id) then return false end
	local tips = C_TooltipInfo.GetToyByItemID(id)
	if not tips or not tips.lines then return true end
	for _, line in pairs(tips.lines) do
		if line.type == 23 then -- requirement text; white = usable
			local c = line.leftColor
			if c and c.r == 1 and c.g == 1 and c.b == 1 then return true end
			return false
		end
	end
	return true
end

local spellEntriesCache
local spellEntriesCacheTime = 0
local seasonSectionCache
local seasonSectionCacheReady = false
local seasonSectionCacheTime = 0
local compendiumCacheDirty = true
local refreshQueued = false
local queuedFullRefresh = false
local queuedCooldownRefresh = false
local queuedInvalidateCache = false
local COMPENDIUM_CACHE_TTL = 1

local function isCacheExpired(cachedAt)
	if not cachedAt or cachedAt <= 0 then return true end
	local now = GetTime and GetTime() or 0
	if now <= 0 then return false end
	return (now - cachedAt) > COMPENDIUM_CACHE_TTL
end

local function InvalidateCompendiumCache()
	spellEntriesCache = nil
	spellEntriesCacheTime = 0
	seasonSectionCache = nil
	seasonSectionCacheReady = false
	seasonSectionCacheTime = 0
	compendiumCacheDirty = true
	if addon and addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.InvalidateTeleportCompendiumCaches then
		addon.MythicPlus.functions.InvalidateTeleportCompendiumCaches()
	end
end

local function BuildSpellEntries()
	if not addon or not addon.MythicPlus or not addon.MythicPlus.functions then return {} end
	if not addon.MythicPlus.functions.BuildTeleportCompendiumSections then return {} end
	if compendiumCacheDirty or not spellEntriesCache or isCacheExpired(spellEntriesCacheTime) then
		spellEntriesCache = addon.MythicPlus.functions.BuildTeleportCompendiumSections() or {}
		spellEntriesCacheTime = GetTime and GetTime() or 0
	end
	compendiumCacheDirty = false
	return spellEntriesCache
end

local function BuildSeasonSection()
	if not addon or not addon.MythicPlus or not addon.MythicPlus.functions then return nil end
	if not addon.MythicPlus.functions.BuildCurrentSeasonTeleportSection then return nil end
	if compendiumCacheDirty or not seasonSectionCacheReady or isCacheExpired(seasonSectionCacheTime) then
		seasonSectionCache = addon.MythicPlus.functions.BuildCurrentSeasonTeleportSection()
		seasonSectionCacheReady = true
		seasonSectionCacheTime = GetTime and GetTime() or 0
	end
	return seasonSectionCache
end

local function QueuePanelRefresh(opts)
	opts = opts or {}
	local delay = opts.delay or 0.05

	if opts.invalidate then queuedInvalidateCache = true end
	if opts.cooldownOnly then
		if not queuedFullRefresh then queuedCooldownRefresh = true end
	else
		queuedFullRefresh = true
		queuedCooldownRefresh = false
	end

	if refreshQueued then return end
	refreshQueued = true
	C_Timer.After(delay, function()
		refreshQueued = false
		local doFullRefresh = queuedFullRefresh
		local doCooldownRefresh = queuedCooldownRefresh and not doFullRefresh
		local doInvalidate = queuedInvalidateCache

		queuedFullRefresh = false
		queuedCooldownRefresh = false
		queuedInvalidateCache = false

		if doInvalidate then InvalidateCompendiumCache() end
		if not addon.db or not addon.db["teleportsWorldMapEnabled"] then return end
		if not WorldMapFrame or not WorldMapFrame:IsShown() then return end

		if doCooldownRefresh then
			f:UpdateCooldowns()
		else
			f:RefreshPanel()
		end
	end)
end

local function IsConsolePortLoaded()
	if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded("ConsolePort") or C_AddOns.IsAddOnLoaded("ConsolePort_Cursor") end
	if IsAddOnLoaded then return IsAddOnLoaded("ConsolePort") or IsAddOnLoaded("ConsolePort_Cursor") end
	return false
end

local function AddVariantTooltipLine(entry)
	if not entry or not entry.variantOtherCount or entry.variantOtherCount <= 0 then return end
	local fmt = L["teleportOtherVariants"] or "%d other variants available"
	GameTooltip:AddLine(string.format(fmt, entry.variantOtherCount), 0.7, 0.7, 0.7, true)
end

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

-- Cooldown helpers ---------------------------------------------------------
local function ApplyCooldownToButton(b)
	if not b or not b.cooldownFrame or not b.entry then return end
	local entry = b.entry
	local startTime, duration, modRate, enabled
	if entry.isToy and entry.toyID then
		local st, dur, en = C_Item.GetItemCooldown(entry.toyID)
		startTime, duration, modRate, enabled = st, dur, 1, en
	elseif entry.isItem and entry.itemID then
		local st, dur, en = C_Item.GetItemCooldown(entry.itemID)
		startTime, duration, modRate, enabled = st, dur, 1, en
	else
		local cd = C_Spell.GetSpellCooldown(entry.spellID)
		if cd then
			startTime, duration, modRate, enabled = cd.startTime, cd.duration, cd.modRate, cd.isEnabled
		end
	end

	if issecretvalue and issecretvalue(enabled) then
		b.cooldownFrame:SetCooldown(startTime or 0, duration or 0, modRate or 1)
	elseif enabled and duration and duration > 0 then
		b.cooldownFrame:SetCooldown(startTime or 0, duration or 0, modRate or 1)
	else
		if b.cooldownFrame.Clear then
			b.cooldownFrame:Clear()
		else
			b.cooldownFrame:SetCooldown(0, 0, 0)
		end
	end
end

-- Panel creation -----------------------------------------------------------
local panel -- content frame
local scrollBox
local tabButton -- forward-declare for SafeSetVisible
-- Safe visibility toggles (avoid Show/Hide taint during combat)
local function SafeSetVisible(frame, visible)
	if not frame then return end
	-- Never directly Show/Hide the World Map content frame or its tab; rely on Blizzard
	-- display mode system to toggle visibility. Use alpha + deferred apply to avoid taint.
	if frame == panel or frame == tabButton then
		frame._eqolPendingVisible = visible and true or false
		frame:SetAlpha(visible and 1 or 0)
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		frame._eqolPendingVisible = visible and true or false
		frame:SetAlpha(visible and 1 or 0)
		return
	end
	if visible then
		frame:Show()
	else
		if not InCombatLockdown() then frame:Hide() end
	end
end
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

local function SetCombatScrolling(enabled)
	if not panel or not panel.Scroll then return end
	local s = panel.Scroll
	if enabled then
		s:EnableMouse(true)
		s:EnableMouseWheel(true)
		if s.ScrollBar then
			s.ScrollBar.allowScroll = true
			if s.ScrollBar.Back then s.ScrollBar.Back:Enable() end
			if s.ScrollBar.Forward then s.ScrollBar.Forward:Enable() end
		end
	else
		-- In combat, suppress any scrolling to avoid protected SetVerticalScroll taint
		s:EnableMouse(false)
		s:EnableMouseWheel(false)
		if s.ScrollBar then
			s.ScrollBar.allowScroll = false
			if s.ScrollBar.Back then s.ScrollBar.Back:Disable() end
			if s.ScrollBar.Forward then s.ScrollBar.Forward:Disable() end
		end
	end
end

local function SetButtonsInteractable(enabled)
	if not panel or not panel._allButtons then return end
	for _, b in ipairs(panel._allButtons) do
		if b and b.EnableMouse then b:EnableMouse(enabled and true or false) end
	end
end

local function SetBlockerEnabled(enabled)
	if panel and panel.Blocker then
		panel.Blocker:SetAlpha(enabled and 1 or 0)
		panel.Blocker:EnableMouse(enabled and true or false)
		panel.Blocker:EnableMouseWheel(enabled and true or false)
	end
end

local function IsPanelSuppressed()
	return isRestrictedContent()
end

local function LeaveDisplayModeIfNeeded()
	if not QuestMapFrame or not QuestMapFrame.GetDisplayMode then return end
	if QuestMapFrame:GetDisplayMode() ~= DISPLAY_MODE then return end
	if InCombatLockdown and InCombatLockdown() then return end

	local questLogDisplayMode = _G.QuestLogDisplayMode
	if QuestMapFrame.SetDisplayMode and questLogDisplayMode and questLogDisplayMode.MapLegend then
		QuestMapFrame:SetDisplayMode(questLogDisplayMode.MapLegend)
		return
	end
	if QuestMapFrame.MapLegendTab and QuestMapFrame.MapLegendTab.Click then
		QuestMapFrame.MapLegendTab:Click()
	elseif QuestMapFrame.QuestsTab and QuestMapFrame.QuestsTab.Click then
		QuestMapFrame.QuestsTab:Click()
	end
end

local function ApplySuppressedPanelState()
	SetCombatScrolling(false)
	SetButtonsInteractable(false)
	SetBlockerEnabled(true)
	if panel then SafeSetVisible(panel, false) end
	if tabButton then SafeSetVisible(tabButton, false) end
	LeaveDisplayModeIfNeeded()
end

local function ApplyNormalPanelState()
	SetCombatScrolling(true)
	SetButtonsInteractable(true)
	SetBlockerEnabled(false)
end

local function EnsurePanel(parent)
	local targetParent = QuestMapFrame or parent
	if panel and panel:GetParent() ~= targetParent then panel:SetParent(targetParent) end
	if panel then return panel end

	panel = CreateFrame("Frame", "EQOLWorldMapDungeonPortalsPanel", targetParent, "BackdropTemplate")
	if not InCombatLockdown() then panel:Hide() end

	local function anchorPanel()
		local host = panel:GetParent() or targetParent
		local ca = QuestMapFrame and QuestMapFrame.ContentsAnchor
		panel:ClearAllPoints()
		if ca and ca.GetWidth and ca:GetWidth() > 0 and ca:GetHeight() > 0 then
			-- Match Blizzard MapLegend anchoring to ContentsAnchor
			panel:SetPoint("TOPLEFT", ca, "TOPLEFT", 0, -29)
			panel:SetPoint("BOTTOMRIGHT", ca, "BOTTOMRIGHT", -22, 0)
		else
			panel:SetAllPoints(host)
		end
	end

	anchorPanel()
	-- In case layout isn't ready on first tick, re-anchor shortly after
	C_Timer.After(0, anchorPanel)
	C_Timer.After(0.1, anchorPanel)
	-- Ensure our panel is on top of Blizzard content frames
	if QuestMapFrame then
		panel:SetFrameStrata("HIGH")
		panel:SetFrameLevel((QuestMapFrame:GetFrameLevel() or 0) + 200)
	else
		panel:SetFrameStrata("HIGH")
	end
	panel:SetToplevel(true)
	panel:EnableMouse(true)
	panel:EnableMouseWheel(true)
	SafeSetVisible(panel, false)

	-- Border & Title are positioned after Scroll creation

	-- Scroll area
	local s = CreateFrame("ScrollFrame", "EQOLWorldMapDungeonPortalsScrollFrame", panel, "ScrollFrameTemplate")
	-- Fill interior; ScrollBar will sit in the right gutter via offsets
	s:ClearAllPoints()
	s:SetPoint("TOPLEFT")
	s:SetPoint("BOTTOMRIGHT")

	-- Background inside the scrollframe similar to MapLegend
	if not s.Background then
		local bg = s:CreateTexture(nil, "BACKGROUND")
		if bg.SetAtlas then bg:SetAtlas("QuestLog-main-background", true) end
		-- Inset background to reveal border artwork (similar to MapLegend)
		bg:ClearAllPoints()
		bg:SetPoint("TOPLEFT", s, "TOPLEFT", 3, -1)
		bg:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -3, 0)
		s.Background = bg
	else
		s.Background:ClearAllPoints()
		s.Background:SetPoint("TOPLEFT", s, "TOPLEFT", 3, -13)
		s.Background:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -3, 0)
	end

	-- Align scrollbar like MapLegend: x=+8, topY=+2, bottomY=-4
	if s.ScrollBar and not s._eqolBarAnchored then
		s.ScrollBar:ClearAllPoints()
		s.ScrollBar:SetPoint("TOPLEFT", s, "TOPRIGHT", 8, 2)
		s.ScrollBar:SetPoint("BOTTOMLEFT", s, "BOTTOMRIGHT", 8, -4)
		s._eqolBarAnchored = true
	end

	local content = CreateFrame("Frame", "EQOLWorldMapDungeonPortalsScrollChild", s)
	content:SetSize(1, 1)
	s:SetScrollChild(content)

	panel.Content = content
	panel.Scroll = s

	-- Combat click blocker overlay (prevents any interaction while in combat)
	if not panel.Blocker then
		local blocker = CreateFrame("Frame", nil, panel, "BackdropTemplate")
		blocker:SetAllPoints(s)
		blocker:EnableMouse(false)
		blocker:EnableMouseWheel(false)
		blocker:SetAlpha(0)
		panel.Blocker = blocker
	end

	-- Ensure our interactive content renders above any sibling art
	local baseLevel = panel:GetFrameLevel() or 1
	s:SetFrameLevel(baseLevel + 1)
	content:SetFrameLevel(baseLevel + 2)

	-- Respect combat lockdown: prevent scrolling interactions during combat
	if InCombatLockdown and InCombatLockdown() then
		SetCombatScrolling(false)
		if panel.Blocker then
			panel.Blocker:SetAlpha(1)
			panel.Blocker:EnableMouse(true)
			panel.Blocker:EnableMouseWheel(true)
		end
	end

	-- Now that Scroll exists, create/anchor the border precisely around it
	if not panel.BorderFrame then
		local bf = CreateFrame("Frame", nil, panel, "QuestLogBorderFrameTemplate")
		bf:ClearAllPoints()
		bf:SetPoint("TOPLEFT", s, "TOPLEFT", -3, 7)
		bf:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 3, -6)
		bf:SetFrameStrata(panel:GetFrameStrata())
		bf:SetFrameLevel((panel:GetFrameLevel() or 2) + 3)
		bf:EnableMouse(false) -- ensure border never blocks clicks to our content
		panel.BorderFrame = bf
	else
		local bf = panel.BorderFrame
		bf:ClearAllPoints()
		bf:SetPoint("TOPLEFT", s, "TOPLEFT", -3, 13)
		bf:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 3, 0)
		bf:SetFrameStrata(panel:GetFrameStrata())
		bf:SetFrameLevel((panel:GetFrameLevel() or 2) + 3)
		bf:EnableMouse(false)
	end

	-- Create or re-anchor the title relative to the border top
	if not panel.Title then
		local title = panel:CreateFontString(nil, "OVERLAY", "Game15Font_Shadow")
		title:SetPoint("BOTTOM", panel.BorderFrame, "TOP", -1, 3)
		title:SetText(L["DungeonCompendium"] or "Dungeon Portals")
		panel.Title = title
	else
		panel.Title:ClearAllPoints()
		panel.Title:SetPoint("BOTTOM", panel.BorderFrame, "TOP", -1, 3)
		panel.Title:SetText(L["DungeonCompendium"] or "Dungeon Portals")
	end

	scrollBox = content
	-- Integrate with QuestLog display system

	-- Keep content up-to-date if the scroll area changes size after layout
	if not s._eqolSizeHook then
		s:HookScript("OnSizeChanged", function()
			if panel and panel:IsShown() then QueuePanelRefresh({ delay = 0.05 }) end
		end)
		s._eqolSizeHook = true
	end
	panel.displayMode = DISPLAY_MODE
	return panel
end

local function ClearContent()
	if not scrollBox then return end
	for _, child in ipairs({ scrollBox:GetChildren() }) do
		child:Hide()
		child:SetParent(nil)
	end
end

local function CreateSecureSpellButton(parent, entry)
	local b = CreateFrame("Button", nil, parent, "InsecureActionButtonTemplate, UIPanelButtonTemplate")
	b:SetSize(28, 28)
	b.entry = entry
	-- ConsolePort fires clicks as typerelease; force release-based casting for compatibility
	if IsConsolePortLoaded() then b:SetAttribute("useOnKeyDown", false) end

	-- Keep buttons above any background art
	if panel then
		b:SetFrameStrata(panel:GetFrameStrata())
		b:SetFrameLevel((panel:GetFrameLevel() or 1) + 10)
	end

	local tex = b:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints(b)
	if entry.iconID then
		tex:SetTexture(entry.iconID)
	else
		tex:SetTexture(136121)
	end
	b.Icon = tex

	local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	cd:SetAllPoints(tex) -- restrict overlay strictly to the icon
	cd:SetSwipeColor(0, 0, 0, 0.35)
	cd:SetUseCircularEdge(true)
	cd:SetDrawEdge(false)
	cd:SetDrawBling(false) -- prevent golden flare from bleeding outside
	b.cooldownFrame = cd

	-- Casting setup (Left click) — mirror compendium logic
	if entry.isToy then
		if entry.isKnown then
			b:SetAttribute("type1", "macro")
			b:SetAttribute("macrotext1", "/use item:" .. entry.toyID)
		end
	elseif entry.isItem then
		if entry.isKnown then
			b.itemID = entry.itemID
			b.equipSlot = entry.equipSlot
			b:SetAttribute("type1", "macro")
			b:SetAttribute("macrotext1", "/use item:" .. entry.itemID)
			if entry.equipSlot then
				b:SetScript("PreClick", function(self)
					local slot = self.equipSlot
					if not slot or not self.itemID then return end
					local equippedID = GetInventoryItemID("player", slot)
					if equippedID ~= self.itemID then
						self:SetAttribute("type1", "macro")
						self:SetAttribute("macrotext1", "/equip item:" .. self.itemID)
					else
						self:SetAttribute("type1", "macro")
						self:SetAttribute("macrotext1", "/use item:" .. self.itemID)
					end
				end)
			end
		end
	else
		b:SetAttribute("type1", "spell")
		b:SetAttribute("spell1", entry.spellID)
		b:SetAttribute("unit", "player")
		b:SetAttribute("checkselfcast", true)
	end

	-- Favorite toggle after secure click resolves
	b:RegisterForClicks("AnyDown", "AnyUp")
	b:SetScript("PostClick", function(self, btn)
		if btn == "RightButton" then
			if IsShiftKeyDown() then
				local favs = addon.db.teleportFavorites or {}
				if favs[self.entry.spellID] then
					favs[self.entry.spellID] = nil
				else
					favs[self.entry.spellID] = true
				end
				addon.db.teleportFavorites = favs
				QueuePanelRefresh({ invalidate = true, delay = 0 })
			else
				local entry = self.entry or {}
				local locID = entry.locID
				local x, y = entry.x, entry.y
				if locID and x and y then OpenMapAndCreatePin(locID, x, y) end
			end
		end
	end)

	b:SetScript("OnEnter", function(self)
		if not addon.db["portalShowTooltip"] then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if entry.isToy then
			GameTooltip:SetToyByItemID(entry.toyID)
		elseif entry.isItem then
			GameTooltip:SetItemByID(entry.itemID)
		else
			GameTooltip:SetSpellByID(entry.spellID)
		end
		AddVariantTooltipLine(entry)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- favorite star overlay
	local fav = b:CreateTexture(nil, "OVERLAY")
	fav:SetPoint("TOPRIGHT", 5, 5)
	fav:SetSize(14, 14)
	fav:SetAtlas("auctionhouse-icon-favorite")
	fav:SetShown(entry.isFavorite)
	b.FavOverlay = fav

	-- initial cooldown state
	ApplyCooldownToButton(b)

	return b
end

-- MapLegend-style row button: icon left, text right, full-row highlight
local function CreateLegendRowButton(parent, entry, width, height)
	local b = CreateFrame("Button", nil, parent, "InsecureActionButtonTemplate")
	b:SetSize(width, height)
	b.entry = entry
	-- ConsolePort fires clicks as typerelease; force release-based casting for compatibility
	if IsConsolePortLoaded() then b:SetAttribute("useOnKeyDown", false) end

	-- icon
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("LEFT", 4, 0)
	icon:SetSize(height - 6, height - 6)
	icon:SetTexture(entry.iconID or 136121)
	b.Icon = icon

	-- cooldown overlay on icon only
	local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	cd:SetAllPoints(icon) -- overlay only the icon, not the label row
	cd:SetSwipeColor(0, 0, 0, 0.35)
	cd:SetUseCircularEdge(true)
	cd:SetDrawEdge(false)
	cd:SetDrawBling(false)
	b.cooldownFrame = cd

	-- favorite star overlay (on icon)
	local fav = b:CreateTexture(nil, "OVERLAY")
	fav:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 4, 4)
	fav:SetSize(14, 14)
	fav:SetAtlas("auctionhouse-icon-favorite")
	fav:SetShown(entry.isFavorite)
	b.FavOverlay = fav

	-- label to the right of the icon
	local label = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	label:SetPoint("RIGHT", -6, 0)
	label:SetJustifyH("LEFT")
	label:SetWordWrap(false)
	label:SetText(entry.text or "")
	b.Label = label

	-- full-row highlight (lockable) using the same atlas as MapLegend
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(b)
	if hl.SetAtlas then
		hl:SetAtlas("Options_List_Active", true)
		if hl.SetBlendMode then hl:SetBlendMode("ADD") end
	else
		hl:SetColorTexture(1, 1, 1, 0.08)
	end
	b:SetHighlightTexture(hl)

	-- Casting setup (Left click) — mirror compendium logic
	if entry.isToy then
		if entry.isKnown then
			b:SetAttribute("type1", "macro")
			b:SetAttribute("macrotext1", "/use item:" .. entry.toyID)
		end
	elseif entry.isItem then
		if entry.isKnown then
			b.itemID = entry.itemID
			b.equipSlot = entry.equipSlot
			b:SetAttribute("type1", "macro")
			b:SetAttribute("macrotext1", "/use item:" .. entry.itemID)
			if entry.equipSlot then
				b:SetScript("PreClick", function(self)
					local slot = self.equipSlot
					if not slot or not self.itemID then return end
					local equippedID = GetInventoryItemID("player", slot)
					if equippedID ~= self.itemID then
						self:SetAttribute("type1", "macro")
						self:SetAttribute("macrotext1", "/equip item:" .. self.itemID)
					else
						self:SetAttribute("type1", "macro")
						self:SetAttribute("macrotext1", "/use item:" .. self.itemID)
					end
				end)
			end
		end
	else
		b:SetAttribute("type1", "spell")
		b:SetAttribute("spell1", entry.spellID)
		b:SetAttribute("unit", "player")
		b:SetAttribute("checkselfcast", true)
	end

	-- Right click: toggle favorite after secure click resolves
	b:RegisterForClicks("AnyDown", "AnyUp")
	b:SetScript("PostClick", function(self, btn)
		if btn == "RightButton" then
			if IsShiftKeyDown() then
				local favs = addon.db.teleportFavorites or {}
				if favs[self.entry.spellID] then
					favs[self.entry.spellID] = nil
				else
					favs[self.entry.spellID] = true
				end
				addon.db.teleportFavorites = favs
				QueuePanelRefresh({ invalidate = true, delay = 0 })
			else
				local entry = self.entry or {}
				local locID = entry.locID
				local x, y = entry.x, entry.y
				if locID and x and y then OpenMapAndCreatePin(locID, x, y) end
			end
		end
	end)

	-- Tooltip + highlight lock on hover (mirrors MapLegend feel)

	b:SetScript("OnEnter", function(self)
		if self.SetHighlightLocked then
			self:SetHighlightLocked(true)
		else
			self:LockHighlight()
		end
		if addon.db["portalShowTooltip"] then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if entry.isToy then
				GameTooltip:SetToyByItemID(entry.toyID)
			elseif entry.isItem then
				GameTooltip:SetItemByID(entry.itemID)
			else
				GameTooltip:SetSpellByID(entry.spellID)
			end
			AddVariantTooltipLine(entry)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		if self.SetHighlightLocked then
			self:SetHighlightLocked(false)
		else
			self:UnlockHighlight()
		end
		GameTooltip:Hide()
	end)
	-- Unknown visual state: keep hover for tooltip, but block casting
	if not entry.isKnown then
		if b.Icon then
			b.Icon:SetDesaturated(true)
			b.Icon:SetAlpha(0.5)
		end
		-- Make label clearly appear unavailable
		if b.Label and b.Label.SetTextColor then b.Label:SetTextColor(0.6, 0.6, 0.6) end
		-- Allow mouse for tooltip/right-click favorite, but prevent left-click actions
		b:EnableMouse(true)
		b:SetAttribute("type1", nil)
		b:SetAttribute("spell1", nil)
		b:SetAttribute("macrotext1", nil)
	else
		if b.Icon then
			b.Icon:SetDesaturated(false)
			b.Icon:SetAlpha(1)
		end
		-- Restore normal label color for known/owned teleports (gold-like)
		if b.Label and b.Label.SetTextColor then b.Label:SetTextColor(1.0, 0.82, 0.0) end
		b:EnableMouse(true)
	end

	-- Set frame strata above background art
	if panel then
		b:SetFrameStrata(panel:GetFrameStrata())
		b:SetFrameLevel((panel:GetFrameLevel() or 1) + 10)
	end

	-- initial cooldown state
	ApplyCooldownToButton(b)

	return b
end

local function PopulatePanel()
	if not panel then return end
	ClearContent()

	-- keep references for lightweight cooldown refresh
	panel._allButtons = {}

	-- Combine sections with preferred order: Favorites, HOME, Season, then others
	local combined = {}
	local comp = BuildSpellEntries() or {}
	local favoritesSec, homeSec
	local others = {}
	for _, sec in ipairs(comp) do
		local t = sec and sec.title
		if t == FAVORITES then
			favoritesSec = sec
		elseif t == HOME then
			homeSec = sec
		else
			table.insert(others, sec)
		end
	end

	if favoritesSec then table.insert(combined, favoritesSec) end
	if homeSec then table.insert(combined, homeSec) end

	if addon.db and addon.db["teleportsWorldMapShowSeason"] then
		local seasonSec = BuildSeasonSection()
		if seasonSec and seasonSec.items and #seasonSec.items > 0 then table.insert(combined, seasonSec) end
	end

	for _, sec in ipairs(others) do
		table.insert(combined, sec)
	end

	if not combined or #combined == 0 then
		local msg = (L["teleportCompendiumHeadline"] or "Teleports") .. ": None available"
		local label = scrollBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
		label:SetPoint("TOPLEFT", 10, -10)
		label:SetText(msg)
		scrollBox:SetHeight(40)
		return
	end

	-- Layout metrics similar to MapLegendScrollFrame
	local leftPadding = 12
	local topPadding = 10
	local categorySpacing = 10
	local buttonSpacingY = 5
	local stride = 2 -- 2 columns
	local rowHeight = 28

	-- compute available width per column
	local scrollW = panel.Scroll:GetWidth() or 330
	local scrollbarWidth = (panel.Scroll.ScrollBar and panel.Scroll.ScrollBar:GetWidth()) or 18
	local usableWidth = math.max(120, scrollW - scrollbarWidth - 20)
	local colWidth = math.floor((usableWidth - 0) / stride) -- no horizontal spacing requested

	local yOffset = -topPadding
	for _, section in ipairs(combined) do
		-- category container
		local category = CreateFrame("Frame", nil, scrollBox)
		category:SetPoint("TOPLEFT", leftPadding, yOffset)
		category:SetSize(usableWidth, 10) -- temporary height; will expand below

		-- title
		local titleFS = category:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		titleFS:SetPoint("TOPLEFT", 0, 0)
		titleFS:SetText(section.title or "")
		titleFS:SetFont(addon.variables.defaultFont, 13, "OUTLINE") -- Setzt die Schriftart, -größe und -stil (OUTLINE)

		-- build buttons for this category
		local buttons = {}
		for i, entry in ipairs(section.items or {}) do
			local b = CreateLegendRowButton(category, entry, colWidth, rowHeight)
			table.insert(buttons, b)
			table.insert(panel._allButtons, b)
		end

		-- grid layout with 2 columns, xSpacing=0, ySpacing=5
		if #buttons > 0 then
			local layout = AnchorUtil.CreateGridLayout(GridLayoutMixin.Direction.TopLeftToBottomRight, stride, 0, buttonSpacingY)
			local anchor = CreateAnchor("TOPLEFT", category, "TOPLEFT", 0, -3 - (titleFS:GetStringHeight() or 14))
			AnchorUtil.GridLayout(buttons, anchor, layout)

			-- adjust button widths to column width
			for _, b in ipairs(buttons) do
				b:SetWidth(colWidth)
			end
		end

		-- compute category height: title + rows*rowHeight + spacing
		local rows = math.ceil(#buttons / stride)
		local catHeight = (titleFS:GetStringHeight() or 14) + 3 + (rows > 0 and ((rows - 1) * (rowHeight + buttonSpacingY) + rowHeight) or 0)
		category:SetHeight(catHeight)

		yOffset = yOffset - catHeight - categorySpacing
	end

	-- update scroll child extents
	scrollBox:SetHeight(math.abs(yOffset) + topPadding)
	if panel.Scroll and panel.Scroll.UpdateScrollChildRect then panel.Scroll:UpdateScrollChildRect() end

	-- Respect combat: disable all button interactions while in combat
	if InCombatLockdown and InCombatLockdown() then SetButtonsInteractable(false) end
end

-- Tab creation -------------------------------------------------------------
-- tabButton declared above for forward reference

-- Prefer anchoring below WorldQuestTab's custom tab if present
local function GetPreferredTabAnchor()
	local wqtTab = _G and _G["WQT_QuestMapTab"]
	if wqtTab and wqtTab.GetObjectType and wqtTab:GetObjectType() then return wqtTab end
	return QuestMapFrame and (QuestMapFrame.MapLegendTab or QuestMapFrame.QuestsTab or (QuestMapFrame.DetailsFrame and QuestMapFrame.DetailsFrame.BackFrame)) or nil
end

local function EnsureTab(parent, anchorTo)
	if tabButton and tabButton:GetParent() ~= parent then tabButton:SetParent(parent) end
	-- If the tab already exists, still allow re-anchoring when a better anchor shows up later
	if tabButton then
		if anchorTo then
			tabButton:ClearAllPoints()
			tabButton:SetPoint("TOP", anchorTo, "BOTTOM", 0, -3)
		end
		return tabButton
	end

	-- Use Blizzard QuestLog tab template for a perfect visual match
	tabButton = CreateFrame("Button", "EQOLWorldMapDungeonPortalsTab", parent, "QuestLogTabButtonTemplate")
	if anchorTo then
		tabButton:SetPoint("TOP", anchorTo, "BOTTOM", 0, -3)
	else
		tabButton:SetPoint("TOPRIGHT", -6, -100)
	end

	-- Mirror hover/selected visuals via the template, but we'll supply our own icon
	tabButton.activeAtlas = "questlog-tab-icon-maplegend"
	tabButton.inactiveAtlas = "questlog-tab-icon-maplegend-inactive"
	tabButton.tooltipText = (L["DungeonCompendium"] or "Dungeon Portals")
	tabButton.displayMode = DISPLAY_MODE

	-- Hide template's atlas-driven icon and add our persistent custom icon
	if tabButton.Icon then tabButton.Icon:SetAlpha(0) end
	local customIcon = tabButton:CreateTexture(nil, "ARTWORK")
	customIcon:SetPoint("CENTER", -2, 0)
	customIcon:SetSize(20, 20)
	customIcon:SetTexture(ICON_INACTIVE)
	customIcon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
	tabButton.CustomIcon = customIcon

	-- helper to flip icon depending on selection
	local function UpdateTabIconChecked(tb, checked)
		if not tb or not tb.CustomIcon then return end
		if checked then
			tb.CustomIcon:SetTexture(ICON_ACTIVE)
		else
			tb.CustomIcon:SetTexture(ICON_INACTIVE)
		end
	end

	-- Guard against Blizzard re-showing the template icon
	if tabButton.Icon and not tabButton.Icon._eqolHook then
		hooksecurefunc(tabButton.Icon, "Show", function(icon) icon:SetAlpha(0) end)
		hooksecurefunc(tabButton.Icon, "SetAtlas", function(icon) icon:SetAlpha(0) end)
		tabButton.Icon._eqolHook = true
	end

	-- make sure we're not selected by default
	if tabButton.SetChecked then tabButton:SetChecked(false) end
	if tabButton.SelectedTexture then tabButton.SelectedTexture:SetAlpha(1) end
	SafeSetVisible(tabButton, true)

	-- Keep custom icon clear on state changes
	if not tabButton._eqolStateHooks then
		hooksecurefunc(tabButton, "SetChecked", function(self, checked)
			if self.CustomIcon then self.CustomIcon:SetDesaturated(false) end
			UpdateTabIconChecked(self, checked)
		end)
		hooksecurefunc(tabButton, "Disable", function(self)
			if self.CustomIcon then self.CustomIcon:SetDesaturated(true) end
		end)
		hooksecurefunc(tabButton, "Enable", function(self)
			if self.CustomIcon then self.CustomIcon:SetDesaturated(false) end
		end)
		tabButton._eqolStateHooks = true
	end

	-- Initialize checked state and icon based on QuestMapFrame displayMode
	local isActive = QuestMapFrame and QuestMapFrame.displayMode == DISPLAY_MODE
	if tabButton.SetChecked then tabButton:SetChecked(isActive) end
	-- Keep panel alpha in sync with current mode without Show/Hide
	if panel then SafeSetVisible(panel, isActive and true or false) end

	tabButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.tooltipText)
		GameTooltip:Show()
	end)
	tabButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	tabButton:SetScript("OnMouseUp", function(self, button, upInside)
		if button ~= "LeftButton" or not upInside then return end
		if not panel then return end
		if IsPanelSuppressed() then
			ApplySuppressedPanelState()
			return
		end
		if QuestMapFrame and QuestMapFrame.SetDisplayMode then
			QuestMapFrame:SetDisplayMode(DISPLAY_MODE)
		else
			-- No safe fallback: avoid showing protected frames directly
			-- Defer selection to the next OnShow if available
			f._selectOnNextShow = true
		end
	end)

	return tabButton
end

-- Glue into World Map ------------------------------------------------------
function f:TryInit()
	-- Only ensure injection when enabled
	if not QuestMapFrame then return end
	if not addon.db or not addon.db["teleportsWorldMapEnabled"] then
		if panel then SafeSetVisible(panel, false) end
		if tabButton then SafeSetVisible(tabButton, false) end
		return
	end
	if IsPanelSuppressed() then
		ApplySuppressedPanelState()
		return
	end

	local parent = QuestMapFrame
	EnsurePanel(parent)

	-- Re-anchor our panel whenever the map resizes or the content anchor becomes valid
	if not parent._eqolSizeHook then
		parent:HookScript("OnSizeChanged", function()
			if panel and panel:GetParent() then
				panel:ClearAllPoints()
				local ca = QuestMapFrame and QuestMapFrame.ContentsAnchor
				if ca and ca.GetWidth and ca:GetWidth() > 0 and ca:GetHeight() > 0 then
					panel:SetPoint("TOPLEFT", ca, "TOPLEFT", 0, -29)
					panel:SetPoint("BOTTOMRIGHT", ca, "BOTTOMRIGHT", -22, 0)
				else
					panel:SetAllPoints(panel:GetParent())
				end
				QueuePanelRefresh({ delay = 0.05 })
			end
		end)
		parent._eqolSizeHook = true
	end
	if QuestMapFrame.ContentsAnchor and not QuestMapFrame.ContentsAnchor._eqolSizeHook then
		QuestMapFrame.ContentsAnchor:HookScript("OnSizeChanged", function()
			if panel and panel:GetParent() then
				panel:ClearAllPoints()
				local ca = QuestMapFrame and QuestMapFrame.ContentsAnchor
				if ca and ca.GetWidth and ca:GetWidth() > 0 and ca:GetHeight() > 0 then
					panel:SetPoint("TOPLEFT", ca, "TOPLEFT", 0, -29)
					panel:SetPoint("BOTTOMRIGHT", ca, "BOTTOMRIGHT", -22, 0)
				else
					panel:SetAllPoints(panel:GetParent())
				end
				QueuePanelRefresh({ delay = 0.05 })
			end
		end)
		QuestMapFrame.ContentsAnchor._eqolSizeHook = true
	end

	-- Anchor the tab under the preferred tab (WorldQuestTab if present)
	local anchor = GetPreferredTabAnchor()
	EnsureTab(parent, anchor)

	-- If WorldQuestTab is enabled but its tab isn't created yet, try re-anchoring shortly after
	if C_AddOns and C_AddOns.GetAddOnEnableState and pcall(C_AddOns.GetAddOnEnableState, "WorldQuestTab") and C_AddOns.GetAddOnEnableState("WorldQuestTab") == 2 then
		C_Timer.After(0, function()
			local wqt = _G and _G["WQT_QuestMapTab"]
			if wqt then
				EnsureTab(parent, wqt)
				if QuestMapFrame and QuestMapFrame.ValidateTabs then QuestMapFrame:ValidateTabs() end
			end
		end)
		C_Timer.After(0.2, function()
			local wqt = _G and _G["WQT_QuestMapTab"]
			if wqt then
				EnsureTab(parent, wqt)
				if QuestMapFrame and QuestMapFrame.ValidateTabs then QuestMapFrame:ValidateTabs() end
			end
		end)
	end

	-- Inject our panel into ContentFrames so SetDisplayMode can manage visibility
	if QuestMapFrame.ContentFrames then
		local exists = false
		for _, frame in ipairs(QuestMapFrame.ContentFrames) do
			if frame == panel then
				exists = true
				break
			end
		end
		if not exists then table.insert(QuestMapFrame.ContentFrames, panel) end
	end

	-- Also register our tab as a managed tab for consistent checked state
	if QuestMapFrame.TabButtons then
		local present = false
		for _, b in ipairs(QuestMapFrame.TabButtons) do
			if b == tabButton then
				present = true
				break
			end
		end
		if not present then table.insert(QuestMapFrame.TabButtons, tabButton) end
	end

	-- Ensure tabs layout is recalculated so our tab appears immediately
	if QuestMapFrame and QuestMapFrame.ValidateTabs then QuestMapFrame:ValidateTabs() end

	-- Track display mode changes to update our tab state and refresh content
	if EventRegistry and not f._eqolDisplayEvent then
		EventRegistry:RegisterCallback("QuestLog.SetDisplayMode", function(_, mode)
			if mode == DISPLAY_MODE then
				if IsPanelSuppressed() then
					ApplySuppressedPanelState()
					return
				end
				if tabButton and tabButton.SetChecked then tabButton:SetChecked(true) end
				if panel then SafeSetVisible(panel, true) end
				QueuePanelRefresh({ delay = 0 })
			else
				if tabButton and tabButton.SetChecked then tabButton:SetChecked(false) end
				if panel then SafeSetVisible(panel, false) end
			end
		end, f)
		f._eqolDisplayEvent = true
	end

	-- Also ensure visibility is synced when Blizzard flips display mode via the frame method
	if QuestMapFrame and QuestMapFrame.SetDisplayMode and not QuestMapFrame._eqolSetDisplayHook then
		hooksecurefunc(QuestMapFrame, "SetDisplayMode", function(_, mode)
			if mode == DISPLAY_MODE then
				if IsPanelSuppressed() then
					ApplySuppressedPanelState()
					return
				end
				if panel then SafeSetVisible(panel, true) end
			else
				if panel then SafeSetVisible(panel, false) end
			end
		end)
		QuestMapFrame._eqolSetDisplayHook = true
	end

	-- Proactively build content once; subsequent tab/display changes will refresh as needed
	QueuePanelRefresh({ delay = 0, invalidate = true })
end

function f:RefreshPanel()
	if InCombatLockdown and InCombatLockdown() then return end
	if IsPanelSuppressed() then
		ApplySuppressedPanelState()
		return
	end
	ApplyNormalPanelState()
	if not addon.db or not addon.db["teleportsWorldMapEnabled"] then
		if panel then SafeSetVisible(panel, false) end
		if tabButton then SafeSetVisible(tabButton, false) end
		return
	end
	if not panel then return end
	PopulatePanel()
end

-- Only recompute and apply cooldowns for existing buttons
function f:UpdateCooldowns()
	if not panel or not panel:IsShown() then return end
	for _, b in ipairs(panel._allButtons or {}) do
		if b and b:IsVisible() and b.cooldownFrame and b.entry then ApplyCooldownToButton(b) end
	end
end

-- Events to build/refresh --------------------------------------------------
local function setWorldMapTeleportEventsEnabled(enabled)
	if not f then return end
	if enabled then
		if f._eqolEventsRegistered then return end
		f:RegisterEvent("ADDON_LOADED")
		f:RegisterEvent("PLAYER_REGEN_DISABLED")
		f:RegisterEvent("PLAYER_REGEN_ENABLED")
		f:RegisterEvent("SPELLS_CHANGED")
		f:RegisterEvent("BAG_UPDATE_DELAYED")
		f:RegisterEvent("TOYS_UPDATED")
		f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
		f:RegisterEvent("BAG_UPDATE_COOLDOWN")
		f._eqolEventsRegistered = true
	else
		if not f._eqolEventsRegistered then return end
		f:UnregisterAllEvents()
		f._eqolEventsRegistered = false
	end
end

local function worldMapEventHandler(self, event, arg1)
	if not addon.db or not addon.db["teleportsWorldMapEnabled"] then return end
	if event == "PLAYER_REGEN_DISABLED" then
		SetCombatScrolling(false)
		SetButtonsInteractable(false)
		SetBlockerEnabled(true)
		-- Avoid Show/Hide while in combat
		return
	elseif event == "PLAYER_REGEN_ENABLED" then
		local suppressed = IsPanelSuppressed()
		if suppressed then
			ApplySuppressedPanelState()
		else
			ApplyNormalPanelState()
		end
		-- Apply any deferred visibility changes now that combat ended
		if panel and panel._eqolPendingVisible ~= nil then
			SafeSetVisible(panel, panel._eqolPendingVisible)
			panel._eqolPendingVisible = nil
		end
		if tabButton and tabButton._eqolPendingVisible ~= nil then
			SafeSetVisible(tabButton, tabButton._eqolPendingVisible)
			tabButton._eqolPendingVisible = nil
		end
		if not suppressed then
			local modeActive = QuestMapFrame and QuestMapFrame.GetDisplayMode and QuestMapFrame:GetDisplayMode() == DISPLAY_MODE
			if tabButton then SafeSetVisible(tabButton, true) end
			if tabButton and tabButton.SetChecked then tabButton:SetChecked(modeActive and true or false) end
			if panel then SafeSetVisible(panel, modeActive and true or false) end
		end
		if f._pendingOpen and not IsPanelSuppressed() then
			f._pendingOpen = nil
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.OpenWorldMapTeleportPanel then addon.MythicPlus.functions.OpenWorldMapTeleportPanel(true) end
		end
		if WorldMapFrame and WorldMapFrame:IsShown() and addon.db and addon.db["teleportsWorldMapEnabled"] then QueuePanelRefresh({ delay = 0, invalidate = true }) end
		-- fall through to allow refresh if map is visible
	end
	if event == "ADDON_LOADED" and arg1 == "Blizzard_WorldMap" then
		-- Late-load: attach our OnShow hook once the World Map exists
		if WorldMapFrame and not WorldMapFrame._eqolTeleportHook then
			WorldMapFrame:HookScript("OnShow", function()
				if addon.db and addon.db["teleportsWorldMapEnabled"] then
					f:TryInit()
					if QuestMapFrame and QuestMapFrame.ValidateTabs then QuestMapFrame:ValidateTabs() end
					if f._selectOnNextShow and QuestMapFrame and QuestMapFrame.SetDisplayMode and not IsPanelSuppressed() then
						QuestMapFrame:SetDisplayMode(DISPLAY_MODE)
						f._selectOnNextShow = nil
					end
					QueuePanelRefresh({ delay = 0, invalidate = true })
				else
					if panel then SafeSetVisible(panel, false) end
					if tabButton then SafeSetVisible(tabButton, false) end
				end
			end)
			WorldMapFrame._eqolTeleportHook = true
		end
		return
	elseif event == "ADDON_LOADED" and arg1 == "WorldQuestTab" then
		-- WorldQuestTab just loaded; if its map tab exists, re-anchor below it
		if QuestMapFrame and WorldMapFrame then
			local wqt = _G and _G["WQT_QuestMapTab"]
			if wqt then
				EnsureTab(QuestMapFrame, wqt)
				if QuestMapFrame and QuestMapFrame.ValidateTabs then QuestMapFrame:ValidateTabs() end
			end
		end
		-- Do not return here; allow further processing when map is shown
	end

	-- Only refresh when the map is actually visible; avoid work while hidden
	if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
	if event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
		QueuePanelRefresh({ cooldownOnly = true, delay = 0.03 })
	elseif event == "SPELLS_CHANGED" or event == "BAG_UPDATE_DELAYED" or event == "TOYS_UPDATED" then
		if addon.db and addon.db["teleportsWorldMapEnabled"] then QueuePanelRefresh({ invalidate = true, delay = 0.1 }) end
	end
end

function addon.MythicPlus.functions.InitWorldMapTeleportPanel()
	if addon.MythicPlus.variables.worldMapTeleportInitialized then return end
	if not addon.db then return end
	addon.MythicPlus.variables.worldMapTeleportInitialized = true

	f:SetScript("OnEvent", worldMapEventHandler)
	setWorldMapTeleportEventsEnabled(addon.db["teleportsWorldMapEnabled"])

	-- make sure we also initialize when the WorldMap opens
	if WorldMapFrame and not WorldMapFrame._eqolTeleportHook then
		WorldMapFrame:HookScript("OnShow", function()
			if addon.db and addon.db["teleportsWorldMapEnabled"] then
				f:TryInit()
				if QuestMapFrame and QuestMapFrame.ValidateTabs then QuestMapFrame:ValidateTabs() end
				if f._selectOnNextShow and QuestMapFrame and QuestMapFrame.SetDisplayMode and not IsPanelSuppressed() then
					QuestMapFrame:SetDisplayMode(DISPLAY_MODE)
					f._selectOnNextShow = nil
				end
				QueuePanelRefresh({ delay = 0, invalidate = true })
			else
				if panel then SafeSetVisible(panel, false) end
				if tabButton then SafeSetVisible(tabButton, false) end
			end
		end)
		WorldMapFrame._eqolTeleportHook = true
	end
end

-- Export a small helper so options code can trigger a live refresh
function addon.MythicPlus.functions.RefreshWorldMapTeleportPanel()
	if not addon or not addon.db then return end
	setWorldMapTeleportEventsEnabled(addon.db["teleportsWorldMapEnabled"])
	InvalidateCompendiumCache()

	-- Proactively load the World Map addon so our hooks exist
	if not WorldMapFrame then pcall(UIParentLoadAddOn, "Blizzard_WorldMap") end

	if WorldMapFrame then
		-- Ensure our OnShow hook is installed even if we missed initial load timing
		if not WorldMapFrame._eqolTeleportHook then
			WorldMapFrame:HookScript("OnShow", function()
				if addon.db and addon.db["teleportsWorldMapEnabled"] then
					f:TryInit()
					if QuestMapFrame and QuestMapFrame.ValidateTabs then QuestMapFrame:ValidateTabs() end
					if f._selectOnNextShow and QuestMapFrame and QuestMapFrame.SetDisplayMode and not IsPanelSuppressed() then
						QuestMapFrame:SetDisplayMode(DISPLAY_MODE)
						f._selectOnNextShow = nil
					end
					QueuePanelRefresh({ delay = 0, invalidate = true })
				else
					if panel then SafeSetVisible(panel, false) end
					if tabButton then SafeSetVisible(tabButton, false) end
				end
			end)
			WorldMapFrame._eqolTeleportHook = true
		end

		-- Always ensure our UI is injected and tabs validated, even if hidden
		f:TryInit()
		if QuestMapFrame and QuestMapFrame.ValidateTabs then QuestMapFrame:ValidateTabs() end

		if not addon.db["teleportsWorldMapEnabled"] then
			if QuestMapFrame and QuestMapFrame.GetDisplayMode and QuestMapFrame:GetDisplayMode() == DISPLAY_MODE then
				if QuestMapFrame.MapLegendTab and QuestMapFrame.MapLegendTab.Click then
					QuestMapFrame.MapLegendTab:Click()
				elseif QuestMapFrame.QuestsTab and QuestMapFrame.QuestsTab.Click then
					QuestMapFrame.QuestsTab:Click()
				end
			end
			if panel then SafeSetVisible(panel, false) end
			if tabButton then SafeSetVisible(tabButton, false) end
			return
		end

		if WorldMapFrame:IsShown() then
			if IsPanelSuppressed() then
				ApplySuppressedPanelState()
				return
			end
			if tabButton then SafeSetVisible(tabButton, true) end
			if QuestMapFrame and QuestMapFrame.SetDisplayMode then QuestMapFrame:SetDisplayMode(DISPLAY_MODE) end
			QueuePanelRefresh({ delay = 0, invalidate = true })
		else
			f._selectOnNextShow = true
		end
	end
end

function addon.MythicPlus.functions.OpenWorldMapTeleportPanel(force)
	if not addon or not addon.db or not addon.db["teleportsWorldMapEnabled"] then return end
	if not force and InCombatLockdown and InCombatLockdown() then
		f._pendingOpen = true
		return
	end
	if IsPanelSuppressed() then
		ApplySuppressedPanelState()
		return
	end

	if not WorldMapFrame then pcall(UIParentLoadAddOn, "Blizzard_WorldMap") end
	if f and f.TryInit then f:TryInit() end

	if not WorldMapFrame then return end

	local playerMapID = GetPlayerMapID()
	local function shouldOpenQuestLog()
		if not WorldMapFrame then return false end
		if not WorldMapFrame:IsShown() then return true end
		if WorldMapFrame.IsMinimized and WorldMapFrame:IsMinimized() then
			if WorldMapFrame.IsSidePanelShown and not WorldMapFrame:IsSidePanelShown() then return true end
		end
		return false
	end

	if WorldMapFrame and WorldMapFrame.HandleUserActionOpenQuestLog and shouldOpenQuestLog() then
		WorldMapFrame:HandleUserActionOpenQuestLog(playerMapID)
	elseif not WorldMapFrame:IsShown() then
		if ToggleMap then
			ToggleMap()
		else
			ShowUIPanel(WorldMapFrame)
		end
	end

	if QuestMapFrame and QuestMapFrame.SetDisplayMode then
		QuestMapFrame:SetDisplayMode(DISPLAY_MODE)
	elseif f then
		f._selectOnNextShow = true
	end

	if QuestMapFrame and QuestMapFrame.ValidateTabs then QuestMapFrame:ValidateTabs() end
	if f and f.RefreshPanel then QueuePanelRefresh({ delay = 0 }) end
end
