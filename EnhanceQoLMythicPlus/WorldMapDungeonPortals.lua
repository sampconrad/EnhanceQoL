local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_MythicPlus")

-- Lightweight World Map side-panel for Dungeon Portals, with a small tab
-- that sits together with the default Map Legend / Quest tabs. The panel
-- lists all teleports from addon.MythicPlus.variables.portalCompendium,
-- honoring favorites and the main teleport options where reasonable.

local f = CreateFrame("Frame")
local DISPLAY_MODE = "EQOL_DungeonPortals"

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

local function BuildSpellEntries()
	local faction = select(2, UnitFactionGroup("player"))
	local comp = addon.MythicPlus and addon.MythicPlus.variables and addon.MythicPlus.variables.portalCompendium
	if not comp then return {} end

	local out = {}
	local favorites = addon.db.teleportFavorites or {}

	local function shouldInclude(data, spellID)
		local aMapID = C_Map.GetBestMapForUnit("player")
		local ok = true
		if data.faction and data.faction ~= faction then ok = false end
		if data.map then
			if type(data.map) == "number" then
				ok = ok and (data.map == aMapID)
			elseif type(data.map) == "table" then
				ok = ok and (data.map[aMapID] == true)
			end
		end
		if addon.db["portalHideMissing"] then
			if data.isToy then
				ok = ok and IsToyUsable(data.toyID)
			elseif data.isItem then
				local iid = FirstOwnedItemID(data.itemID)
				ok = ok and (iid and C_Item.GetItemCount(iid) > 0)
			else
				ok = ok and C_SpellBook.IsSpellInSpellBook(spellID)
			end
		end
		if not ok and addon.db.teleportFavoritesIgnoreFilters and favorites[spellID] then ok = true end
		return ok
	end

	for _, section in pairs(comp) do
		local list = {}
		for spellID, data in pairs(section.spells) do
			if shouldInclude(data, spellID) then
				local known = (C_SpellBook.IsSpellInSpellBook(spellID) and not data.isToy)
					or (data.isToy and IsToyUsable(data.toyID))
					or (data.isItem and C_Item.GetItemCount(FirstOwnedItemID(data.itemID)) > 0)

				table.insert(list, {
					spellID = spellID,
					text = data.text,
					iconID = data.iconID,
					isToy = data.isToy,
					toyID = data.toyID,
					isItem = data.isItem,
					itemID = FirstOwnedItemID(data.itemID),
					isKnown = known,
					isFavorite = favorites[spellID] or false,
				})
			end
		end
		if #list > 0 then
			table.sort(list, function(a, b)
				if a.isFavorite ~= b.isFavorite then return a.isFavorite end
				if a.text ~= b.text then return a.text < b.text end
				return (a.spellID or 0) < (b.spellID or 0)
			end)
			table.insert(out, { title = section.headline, items = list })
		end
	end

	-- Favorites block on top (if any)
	local favs = {}
	for _, sec in ipairs(out) do
		for _, it in ipairs(sec.items) do
			if it.isFavorite then table.insert(favs, it) end
		end
	end
	if #favs > 0 then
		table.sort(favs, function(a, b) return a.text < b.text end)
		table.insert(out, 1, { title = FAVORITES, items = favs })
	end
	return out
end

-- Panel creation -----------------------------------------------------------
local panel -- content frame
local scrollBox
local function EnsurePanel(parent)
	if panel and panel:GetParent() ~= parent then panel:SetParent(parent) end
	if panel then return panel end

	panel = CreateFrame("Frame", "EQOLWorldMapDungeonPortalsPanel", parent, "BackdropTemplate")
	panel:ClearAllPoints()
	if QuestMapFrame and QuestMapFrame.ContentsAnchor then
		panel:SetPoint("TOPLEFT", QuestMapFrame.ContentsAnchor, "TOPLEFT", 0, -29)
		panel:SetPoint("BOTTOMRIGHT", QuestMapFrame.ContentsAnchor, "BOTTOMRIGHT", -22, 0)
	else
		panel:SetAllPoints(parent)
	end
	-- Ensure our panel is on top of Blizzard content frames
	if QuestMapFrame then
		panel:SetFrameStrata(QuestMapFrame:GetFrameStrata())
		panel:SetFrameLevel(QuestMapFrame:GetFrameLevel() + 10)
	end
	panel:Hide()

	-- Try to mimic Blizzard side-panel visuals: use inset background
	if panel.NineSlice == nil then
		panel:SetBackdrop({
			bgFile = "Interface/Tooltips/UI-Tooltip-Background",
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		panel:SetBackdropColor(0, 0, 0, 0.65)
	end

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 12, -12)
	title:SetText(L["DungeonCompendium"] or "Dungeon Portals")
	panel.Title = title

	-- Scroll area
	local s = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	s:SetPoint("TOPLEFT", 8, -36)
	s:SetPoint("BOTTOMRIGHT", -28, 10)

	local content = CreateFrame("Frame", nil, s)
	content:SetSize(1, 1)
	s:SetScrollChild(content)

	panel.Content = content
	panel.Scroll = s

	scrollBox = content
	-- Integrate with QuestLog display system
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
	local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate, UIPanelButtonTemplate")
	b:SetSize(28, 28)
	b.entry = entry

	local tex = b:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints(b)
	if entry.iconID then
		tex:SetTexture(entry.iconID)
	else
		tex:SetTexture(136121) -- generic portal swirl icon fallback
	end
	b.Icon = tex

	b.cooldownFrame = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cooldownFrame:SetAllPoints(b)
	b.cooldownFrame:SetSwipeColor(0, 0, 0, 0.35)

	-- Casting setup (Left click)
	if entry.isToy then
		b:SetAttribute("type1", "toy")
		b:SetAttribute("toy", entry.toyID)
	elseif entry.isItem then
		b:SetAttribute("type1", "item")
		b:SetAttribute("item", entry.itemID)
	else
		b:SetAttribute("type1", "spell")
		b:SetAttribute("spell", entry.spellID)
	end

	-- Favorite toggle (Right click)
	b:RegisterForClicks("AnyUp")
	b:SetScript("OnClick", function(self, btn)
		if btn == "RightButton" then
			local favs = addon.db.teleportFavorites or {}
			if favs[self.entry.spellID] then
				favs[self.entry.spellID] = nil
			else
				favs[self.entry.spellID] = true
			end
			addon.db.teleportFavorites = favs
			f:RefreshPanel() -- rebuild list to reflect favorite
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

	return b
end

local function PopulatePanel()
	if not panel then return end
	ClearContent()

	local sections = BuildSpellEntries()
	if not sections or #sections == 0 then
		local msg = (L["teleportCompendiumHeadline"] or "Teleports") .. ": None available"
		local label = scrollBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
		label:SetPoint("TOPLEFT", 10, -10)
		label:SetText(msg)
		scrollBox:SetHeight(40)
		return
	end

	local y = -2
	local xStart = 10
	local x = xStart
	local scrollW = panel.Scroll:GetWidth()
	if not scrollW or scrollW <= 0 then scrollW = (panel:GetWidth() or 330) - 30 end
	local maxWidth = math.max(100, scrollW - 50)
	local perRow = math.max(1, math.floor(maxWidth / 44))
	local countInRow = 0

	local function nextRow()
		y = y - 44
		x = xStart
		countInRow = 0
	end

	for _, section in ipairs(sections) do
		local header = scrollBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		header:SetPoint("TOPLEFT", 8, y)
		header:SetText(section.title)
		y = y - 18

		for _, entry in ipairs(section.items) do
			if countInRow >= perRow then nextRow() end
			local b = CreateSecureSpellButton(scrollBox, entry)
			b:SetPoint("TOPLEFT", x, y)

			local label = scrollBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			label:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
			label:SetText(entry.text)

			-- cooldown display
			local cd
			if entry.isToy and entry.toyID then
				local st, dur, en = C_Item.GetItemCooldown(entry.toyID)
				cd = { startTime = st, duration = dur, modRate = 1, isEnabled = en }
			elseif entry.isItem and entry.itemID then
				local st, dur, en = C_Item.GetItemCooldown(entry.itemID)
				cd = { startTime = st, duration = dur, modRate = 1, isEnabled = en }
			else
				cd = C_Spell.GetSpellCooldown(entry.spellID)
			end
			if cd and cd.isEnabled and b.cooldownFrame then b.cooldownFrame:SetCooldown(cd.startTime, cd.duration, cd.modRate) end

			x = x + 44
			countInRow = countInRow + 1
		end
		nextRow()
	end

	scrollBox:SetHeight(math.abs(y) + 44)
end

-- Tab creation -------------------------------------------------------------
local tabButton
local function EnsureTab(parent, anchorTo)
	if tabButton and tabButton:GetParent() ~= parent then tabButton:SetParent(parent) end
	if tabButton then return tabButton end

	-- Use Blizzard QuestLog tab template for a perfect visual match
	tabButton = CreateFrame("Button", "EQOLWorldMapDungeonPortalsTab", parent, "QuestLogTabButtonTemplate")
	tabButton:SetSize(32, 32)
	if anchorTo then
		tabButton:SetPoint("TOP", anchorTo, "BOTTOM", 0, -3)
	else
		tabButton:SetPoint("TOPRIGHT", -6, -100)
	end

	-- Mirror the MapLegendTab key values (hover/selected visuals via the template)
	tabButton.activeAtlas = "questlog-tab-icon-maplegend"
	tabButton.inactiveAtlas = "questlog-tab-icon-maplegend-inactive"
	tabButton.tooltipText = (L["DungeonCompendium"] or "Dungeon Portals")
	tabButton.displayMode = DISPLAY_MODE

	-- Ensure an icon texture layer exists (we always use our custom icon)
	if not tabButton.Icon then
		local icon = tabButton:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints(tabButton)
		tabButton.Icon = icon
	end

	-- Apply custom Dungeon icon texture (overrides atlas)
	local function ApplyCustomDungeonIcon()
		if not tabButton or not tabButton.Icon then return end
		tabButton.Icon:ClearAllPoints()
		tabButton.Icon:SetPoint("CENTER", -2, 0)
		tabButton.Icon:SetTexture("Interface\\AddOns\\EnhanceQoL\\Icons\\Dungeon.tga")
		tabButton.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
		tabButton.Icon:SetSize(20, 20)
	end

	ApplyCustomDungeonIcon()

	-- make sure we're not selected by default
	if tabButton.SetChecked then tabButton:SetChecked(false) end
	if tabButton.SelectedTexture then tabButton.SelectedTexture:Hide() end

	-- keep custom icon persistent if Blizzard toggles our checked state
	if not tabButton._eqolHookedChecked then
		hooksecurefunc(tabButton, "SetChecked", function(self, checked)
			-- reapply custom icon so atlas never shows
			if self.Icon then
				self.Icon:ClearAllPoints()
				self.Icon:SetPoint("CENTER", -2, 0)
				self.Icon:SetTexture("Interface\\AddOns\\EnhanceQoL\\Icons\\Dungeon.tga")
				self.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
				self.Icon:SetSize(20, 20)
				self.Icon:SetDesaturated(false)
			end
		end)
		tabButton._eqolHookedChecked = true
	end

	tabButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.tooltipText)
		GameTooltip:Show()
	end)
	tabButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	tabButton:SetScript("OnMouseUp", function(self, button, upInside)
		if button ~= "LeftButton" or not upInside then return end
		if not panel then return end
		if QuestMapFrame and QuestMapFrame.SetDisplayMode then
			QuestMapFrame:SetDisplayMode(DISPLAY_MODE)
		else
			-- Fallback: show our panel if SetDisplayMode not available
			panel:Show()
			f:RefreshPanel()
			if tabButton.SetChecked then tabButton:SetChecked(true) end
		end
	end)

	return tabButton
end

-- Glue into World Map ------------------------------------------------------
local initialized = false
function f:TryInit()
	if initialized then return end
	if not QuestMapFrame then return end

	local parent = QuestMapFrame
	-- The legend/content area lives on the QuestMapFrame; reuse it as bounds
	local hostPanel = parent.DetailsFrame or parent

	EnsurePanel(hostPanel)

	-- Anchor the tab under the Map Legend tab if we can find it
	local anchor = QuestMapFrame.MapLegendTab or QuestMapFrame.QuestsTab or (QuestMapFrame.DetailsFrame and QuestMapFrame.DetailsFrame.BackFrame)
	EnsureTab(parent, anchor)

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

	-- Track display mode changes to update our tab state and refresh content
	if EventRegistry and not f._eqolDisplayEvent then
		EventRegistry:RegisterCallback("QuestLog.SetDisplayMode", function(_, mode)
			if mode == DISPLAY_MODE then
				if tabButton and tabButton.SetChecked then tabButton:SetChecked(true) end
				if panel then panel:Show() end
				f:RefreshPanel()
			else
				if tabButton and tabButton.SetChecked then tabButton:SetChecked(false) end
				if panel then panel:Hide() end
			end
		end, f)
		f._eqolDisplayEvent = true
	end

	initialized = panel and tabButton
end

function f:RefreshPanel()
	if not panel or not panel:IsShown() then return end
	PopulatePanel()
end

-- Events to build/refresh --------------------------------------------------
f:SetScript("OnEvent", function(self, event, arg1)
	if event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and (arg1 == "Blizzard_WorldMap" or arg1 == addonName or arg1 == parentAddonName)) then
		C_Timer.After(0.3, function()
			f:TryInit()
			f:RefreshPanel()
		end)
	elseif event == "SPELLS_CHANGED" or event == "BAG_UPDATE_DELAYED" or event == "TOYS_UPDATED" then
		f:RefreshPanel()
	end
end)

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("TOYS_UPDATED")

-- make sure we also initialize when the WorldMap opens
if WorldMapFrame and not WorldMapFrame._eqolTeleportHook then
	WorldMapFrame:HookScript("OnShow", function() f:TryInit() end)
	WorldMapFrame._eqolTeleportHook = true
end
