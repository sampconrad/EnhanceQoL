-- luacheck: globals EnhanceQoL MenuUtil MenuResponse C_AddOns UIParentLoadAddOn PlayerSpellsUtil TogglePlayerSpellsFrame C_Garrison C_Covenants Enum ShowGarrisonLandingPage HousingFramesUtil ToggleCharacter ToggleProfessionsBook ToggleAchievementFrame ToggleQuestLog ToggleCalendar ToggleTimeManager ToggleEncounterJournal ToggleGuildFrame PVEFrame_ToggleFrame ToggleCollectionsJournal ToggleGameMenu ToggleHelpFrame ToggleChannelFrame ToggleFriendsFrame UnitClass UIParent GAMEMENU_OPTIONS GameMenuFrame HideUIPanel ShowUIPanel InCombatLockdown UIErrorsFrame ERR_NOT_IN_COMBAT C_Texture PlayerSpellsMicroButton SpellbookMicroButton TalentMicroButton
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local format = string.format
local lower = string.lower
local G = _G
local floor = math.floor
local securecallfunction = G.securecallfunction

local STREAM_ID = "microbar"
local DEFAULT_ICON_SIZE = 14
local MIN_ICON_SIZE = 10
local MAX_ICON_SIZE = 60
local DEFAULT_ICON_GAP = 5
local MIN_ICON_GAP = 0
local MAX_ICON_GAP = 16
local DEFAULT_BUTTON_SIZE = 20
local MIN_BUTTON_SIZE = 14
local MAX_BUTTON_SIZE = 40
local DEFAULT_BUTTON_BACKDROP_COLOR = { r = 0.03, g = 0.03, b = 0.03, a = 0.6 }
local DEFAULT_BUTTON_BORDER_COLOR = { r = 0.7, g = 0.7, b = 0.7, a = 0.9 }
local DEFAULT_TEXTURE_TEX_COORD = { 0.07, 0.93, 0.07, 0.93 }
local DEFAULT_ATLAS_TEX_COORD = { 0.04, 0.96, 0.04, 0.96 }

local db
local stream
local aceWindow
local aceScroll

local function clampInt(value, minValue, maxValue, fallback)
	value = tonumber(value)
	if not value then return fallback end
	value = floor(value + 0.5)
	if value < minValue then return minValue end
	if value > maxValue then return maxValue end
	return value
end

local function clampColorChannel(value, fallback)
	value = tonumber(value)
	if not value then return fallback end
	if value < 0 then return 0 end
	if value > 1 then return 1 end
	return value
end

local function normalizeColor(value, fallback)
	local fallbackR = fallback.r or fallback[1] or 1
	local fallbackG = fallback.g or fallback[2] or 1
	local fallbackB = fallback.b or fallback[3] or 1
	local fallbackA = fallback.a or fallback[4] or 1
	if type(value) ~= "table" then value = fallback end
	return {
		r = clampColorChannel(value.r or value[1], fallbackR),
		g = clampColorChannel(value.g or value[2], fallbackG),
		b = clampColorChannel(value.b or value[3], fallbackB),
		a = clampColorChannel(value.a or value[4], fallbackA),
	}
end

local function normalizeTexCoord(value, fallback)
	local source = value
	if type(source) ~= "table" then source = fallback end
	local fallbackL = fallback[1] or 0
	local fallbackR = fallback[2] or 1
	local fallbackT = fallback[3] or 0
	local fallbackB = fallback[4] or 1
	return {
		clampColorChannel(source[1], fallbackL),
		clampColorChannel(source[2], fallbackR),
		clampColorChannel(source[3], fallbackT),
		clampColorChannel(source[4], fallbackB),
	}
end

local function resolvedIconTexCoord(iconSpec, isAtlas)
	if iconSpec.useFullTexCoord then return { 0, 1, 0, 1 } end
	local fallback = isAtlas and DEFAULT_ATLAS_TEX_COORD or DEFAULT_TEXTURE_TEX_COORD
	return normalizeTexCoord(iconSpec.texCoord, fallback)
end

local function atlasIcon(atlas, size)
	if not atlas then return "" end
	size = size or DEFAULT_ICON_SIZE
	return format("|A:%s:%d:%d|a ", atlas, size, size)
end

local function textureIcon(texture, size)
	if not texture then return "" end
	size = size or DEFAULT_ICON_SIZE
	return format("|T%s:%d:%d|t ", texture, size, size)
end

local function classAtlas()
	local class = UnitClass and select(2, UnitClass("player"))
	if not class then return nil end
	return "classicon-" .. lower(class)
end

local function ensureAddOn(name)
	if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.LoadAddOn then
		if not C_AddOns.IsAddOnLoaded(name) then C_AddOns.LoadAddOn(name) end
	elseif UIParentLoadAddOn then
		UIParentLoadAddOn(name)
	end
end

local function openCharacter()
	if ToggleCharacter then ToggleCharacter("PaperDollFrame") end
end

local function blockedInCombat()
	if InCombatLockdown and InCombatLockdown() then
		if UIErrorsFrame and ERR_NOT_IN_COMBAT then UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT) end
		return true
	end
	return false
end

local function openProfessions()
	if ToggleProfessionsBook then ToggleProfessionsBook() end
end

local function callSecure(fn, ...)
	if type(fn) ~= "function" then return false end
	if securecallfunction then
		securecallfunction(fn, ...)
	else
		fn(...)
	end
	return true
end

local function clickButtonSecure(button)
	if not button or type(button.Click) ~= "function" then return false end
	return callSecure(button.Click, button, "LeftButton", true)
end

local function clickNamedButtonSecure(buttonName)
	if not buttonName then return false end
	return clickButtonSecure(G[buttonName])
end

local function openTalents()
	if blockedInCombat() then return end

	-- Retail uses a single native PlayerSpells micro button; prefer that path to avoid taint.
	if clickNamedButtonSecure("PlayerSpellsMicroButton") then return end
	if clickNamedButtonSecure("TalentMicroButton") then return end
	ensureAddOn("Blizzard_PlayerSpells")
	if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentFrame and callSecure(PlayerSpellsUtil.ToggleClassTalentFrame) then return end
	if
		PlayerSpellsUtil
		and PlayerSpellsUtil.FrameTabs
		and PlayerSpellsUtil.FrameTabs.ClassTalents
		and TogglePlayerSpellsFrame
		and callSecure(TogglePlayerSpellsFrame, PlayerSpellsUtil.FrameTabs.ClassTalents)
	then
		return
	end
	if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentOrSpecFrame and callSecure(PlayerSpellsUtil.ToggleClassTalentOrSpecFrame) then return end
end

local function openSpellbook()
	if blockedInCombat() then return end

	-- Retail has no separate Spellbook micro button; use PlayerSpells button first.
	if clickNamedButtonSecure("PlayerSpellsMicroButton") then return end
	if clickNamedButtonSecure("SpellbookMicroButton") then return end
	ensureAddOn("Blizzard_PlayerSpells")
	if PlayerSpellsUtil and PlayerSpellsUtil.ToggleSpellBookFrame and callSecure(PlayerSpellsUtil.ToggleSpellBookFrame) then return end
	if
		PlayerSpellsUtil
		and PlayerSpellsUtil.FrameTabs
		and PlayerSpellsUtil.FrameTabs.SpellBook
		and TogglePlayerSpellsFrame
		and callSecure(TogglePlayerSpellsFrame, PlayerSpellsUtil.FrameTabs.SpellBook)
	then
		return
	end
end

local function openAchievements()
	if ToggleAchievementFrame then ToggleAchievementFrame() end
end

local function openQuestLog()
	ensureAddOn("Blizzard_WorldMap")
	if ToggleQuestLog then ToggleQuestLog() end
end

local function openHousing()
	ensureAddOn("Blizzard_HousingEventHandler")
	if HousingFramesUtil and HousingFramesUtil.ToggleHousingDashboard then HousingFramesUtil.ToggleHousingDashboard() end
end

local function openGuild()
	ensureAddOn("Blizzard_Communities")
	if ToggleGuildFrame then ToggleGuildFrame() end
end

local function openLFG()
	ensureAddOn("Blizzard_GroupFinder")
	if PVEFrame_ToggleFrame then PVEFrame_ToggleFrame() end
end

local function openDungeonJournal()
	if ToggleEncounterJournal then ToggleEncounterJournal() end
end

local function openCollections()
	if ToggleCollectionsJournal then ToggleCollectionsJournal() end
end

local function openGameMenu()
	if blockedInCombat() then return end

	if GameMenuFrame and GameMenuFrame:IsShown() then
		if HideUIPanel then
			HideUIPanel(GameMenuFrame)
		else
			GameMenuFrame:Hide()
		end
		return
	end

	if GameMenuFrame and ShowUIPanel then
		ShowUIPanel(GameMenuFrame)
		return
	end

	if ToggleGameMenu then ToggleGameMenu() end
end

local function openHelp()
	if ToggleHelpFrame then ToggleHelpFrame() end
end

local function openCalendar()
	if ToggleCalendar then ToggleCalendar() end
end

local function openClock()
	if ToggleTimeManager then ToggleTimeManager() end
end

local function openChatChannels()
	ensureAddOn("Blizzard_Channels")
	if ToggleChannelFrame then ToggleChannelFrame() end
end

local function openSocial()
	ensureAddOn("Blizzard_FriendsFrame")
	if ToggleFriendsFrame then ToggleFriendsFrame() end
end

local function getMissionsGarrisonType()
	if not C_Garrison or not C_Garrison.GetLandingPageGarrisonType then return nil end
	local garrTypeID = C_Garrison.GetLandingPageGarrisonType()
	if not garrTypeID or garrTypeID == 0 then return nil end
	if C_Garrison.IsLandingPageMinimapButtonVisible and not C_Garrison.IsLandingPageMinimapButtonVisible(garrTypeID) then return nil end
	if Enum and Enum.GarrisonType and Enum.GarrisonType.Type_9_0_Garrison and garrTypeID == Enum.GarrisonType.Type_9_0_Garrison then
		if not C_Covenants or not C_Covenants.GetActiveCovenantID then return nil end
		local covenantID = C_Covenants.GetActiveCovenantID()
		if not covenantID or covenantID == 0 then return nil end
		if C_Covenants.GetCovenantData and not C_Covenants.GetCovenantData(covenantID) then return nil end
	end
	return garrTypeID
end

local function missionsEnabled() return getMissionsGarrisonType() ~= nil end

local function openMissions()
	local garrTypeID = getMissionsGarrisonType()
	if not garrTypeID then return end
	ensureAddOn("Blizzard_GarrisonBase")
	if ShowGarrisonLandingPage then ShowGarrisonLandingPage(garrTypeID) end
end

local function ensureDB()
	addon.db = addon.db or {}
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.microbar = addon.db.datapanel.microbar or {}
	db = addon.db.datapanel.microbar
	if db.displayMode ~= "menu" and db.displayMode ~= "inline" then db.displayMode = "menu" end
	if type(db.hiddenEntries) ~= "table" then db.hiddenEntries = {} end
	db.iconSize = clampInt(db.iconSize, MIN_ICON_SIZE, MAX_ICON_SIZE, DEFAULT_ICON_SIZE)
	db.iconGap = clampInt(db.iconGap, MIN_ICON_GAP, MAX_ICON_GAP, DEFAULT_ICON_GAP)
	db.buttonSize = clampInt(db.buttonSize, MIN_BUTTON_SIZE, MAX_BUTTON_SIZE, DEFAULT_BUTTON_SIZE)
	if db.equalButtonSize == nil then db.equalButtonSize = false end
	if db.buttonBackdrop == nil then db.buttonBackdrop = false end
	if db.buttonBorder == nil then db.buttonBorder = true end
	db.buttonBorderColor = normalizeColor(db.buttonBorderColor, DEFAULT_BUTTON_BORDER_COLOR)
	return db
end

local function requestUpdate()
	if addon.DataHub and addon.DataHub.RequestUpdate then addon.DataHub:RequestUpdate(STREAM_ID) end
end

local function getIconSize()
	ensureDB()
	return db.iconSize
end

local function setIconSize(value)
	ensureDB()
	value = clampInt(value, MIN_ICON_SIZE, MAX_ICON_SIZE, DEFAULT_ICON_SIZE)
	if db.iconSize == value then return end
	db.iconSize = value
	requestUpdate()
end

local function getIconGap()
	ensureDB()
	return db.iconGap
end

local function setIconGap(value)
	ensureDB()
	value = clampInt(value, MIN_ICON_GAP, MAX_ICON_GAP, DEFAULT_ICON_GAP)
	if db.iconGap == value then return end
	db.iconGap = value
	requestUpdate()
end

local function getButtonSize()
	ensureDB()
	return db.buttonSize
end

local function setButtonSize(value)
	ensureDB()
	value = clampInt(value, MIN_BUTTON_SIZE, MAX_BUTTON_SIZE, DEFAULT_BUTTON_SIZE)
	if db.buttonSize == value then return end
	db.buttonSize = value
	requestUpdate()
end

local function hasEqualButtonSize()
	ensureDB()
	return db.equalButtonSize == true
end

local function setEqualButtonSize(value)
	ensureDB()
	local nextValue = value and true or false
	if db.equalButtonSize == nextValue then return end
	db.equalButtonSize = nextValue
	requestUpdate()
end

local function hasButtonBackdrop()
	ensureDB()
	return db.buttonBackdrop == true
end

local function setButtonBackdrop(value)
	ensureDB()
	local nextValue = value and true or false
	if db.buttonBackdrop == nextValue then return end
	db.buttonBackdrop = nextValue
	requestUpdate()
end

local function hasButtonBorder()
	ensureDB()
	return db.buttonBorder == true
end

local function setButtonBorder(value)
	ensureDB()
	local nextValue = value and true or false
	if db.buttonBorder == nextValue then return end
	db.buttonBorder = nextValue
	requestUpdate()
end

local function getButtonBorderColor()
	ensureDB()
	return db.buttonBorderColor
end

local function setButtonBorderColor(r, g, b, a)
	ensureDB()
	local color = normalizeColor({ r = r, g = g, b = b, a = a }, DEFAULT_BUTTON_BORDER_COLOR)
	local current = db.buttonBorderColor or DEFAULT_BUTTON_BORDER_COLOR
	if current.r == color.r and current.g == color.g and current.b == color.b and current.a == color.a then return end
	db.buttonBorderColor = color
	requestUpdate()
end

local function isInlineMode()
	ensureDB()
	return db.displayMode == "inline"
end

local function setDisplayMode(mode)
	ensureDB()
	if mode ~= "menu" and mode ~= "inline" then mode = "menu" end
	if db.displayMode == mode then return end
	db.displayMode = mode
	requestUpdate()
end

local function isEntryHidden(entryID)
	ensureDB()
	return db.hiddenEntries[entryID] == true
end

local function setEntryHidden(entryID, hidden)
	ensureDB()
	if hidden then
		db.hiddenEntries[entryID] = true
	else
		db.hiddenEntries[entryID] = nil
	end
	requestUpdate()
end

local function atlasExists(atlas)
	if not atlas or atlas == "" then return false end
	if not C_Texture or not C_Texture.GetAtlasInfo then return true end
	return C_Texture.GetAtlasInfo(atlas) ~= nil
end

local function getMicroButtonIconSpec(buttonName, fallback)
	local button = buttonName and G[buttonName]
	local normal = button and button.GetNormalTexture and button:GetNormalTexture()
	if normal then
		local atlas = normal.GetAtlas and normal:GetAtlas()
		if atlas and atlas ~= "" and atlasExists(atlas) then return { atlas = atlas } end

		local texture = normal.GetTexture and normal:GetTexture()
		if texture then
			local icon = { texture = texture }
			if normal.GetTexCoord then
				local l, r, t, b = normal:GetTexCoord()
				if l and r and t and b then icon.texCoord = { l, r, t, b } end
			end
			return icon
		end
	end
	return fallback
end

local menuEntries = {
	{
		id = "achievements",
		label = G.ACHIEVEMENT_BUTTON or "Achievements",
		iconSpec = { atlas = "UI-HUD-MicroMenu-Achievements-Up" },
		action = openAchievements,
	},
	{
		id = "calendar",
		label = G.CALENDAR or "Calendar",
		iconSpec = {
			texture = "Interface\\Calendar\\EventNotification",
			useFullTexCoord = true,
			offsetX = -1,
		},
		action = openCalendar,
	},
	{
		id = "character",
		label = G.CHARACTER_BUTTON or "Character",
		iconSpec = function() return { atlas = classAtlas() } end,
		action = openCharacter,
	},
	{
		id = "chatchannels",
		label = G.CHAT_CHANNELS or "Chat Channels",
		iconSpec = { texture = "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up" },
		action = openChatChannels,
	},
	{
		id = "clock",
		label = G.TIMEMANAGER_TITLE or "Clock",
		iconSpec = { texture = "Interface\\TimeManager\\GlobeIcon" },
		action = openClock,
	},
	{
		id = "dungeonjournal",
		label = G.ENCOUNTER_JOURNAL or G.ADVENTURE_JOURNAL or "Dungeon Journal",
		iconSpec = { atlas = "UI-HUD-MicroMenu-AdventureGuide-Up" },
		action = openDungeonJournal,
	},
	{
		id = "guild",
		label = G.GUILD or "Guild",
		iconSpec = { atlas = "UI-HUD-MicroMenu-GuildCommunities-Up" },
		action = openGuild,
	},
	{
		id = "housing",
		label = G.HOUSING_DASHBOARD_HOUSEINFO_FRAMETITLE or G.HOUSING_MICRO_BUTTON or "Housing Dashboard",
		iconSpec = { atlas = "UI-HUD-MicroMenu-Housing-Up" },
		action = openHousing,
	},
	{
		id = "lfg",
		label = G.DUNGEONS_BUTTON or "Looking For Group",
		iconSpec = { atlas = "UI-HUD-MicroMenu-Groupfinder-Up" },
		action = openLFG,
	},
	{
		id = "missions",
		label = G.GARRISON_MISSIONS or "Missions",
		iconSpec = { texture = "Interface\\Icons\\INV_Garrison_Mission" },
		action = openMissions,
		enabled = missionsEnabled,
	},
	{
		id = "professions",
		label = G.PROFESSIONS_BUTTON or "Professions",
		iconSpec = { atlas = "UI-HUD-MicroMenu-Professions-Up" },
		action = openProfessions,
	},
	{
		id = "questlog",
		label = G.QUESTLOG_BUTTON or "Quest Log",
		iconSpec = { atlas = "UI-HUD-MicroMenu-Questlog-Up" },
		action = openQuestLog,
	},
	{
		id = "social",
		label = L["Social"] or "Social",
		iconSpec = { texture = "Interface\\FriendsFrame\\PlusManz-PlusManz" },
		action = openSocial,
	},
	{
		id = "talents",
		label = L["Specialization & Talents"] or G.PLAYERSPELLS_BUTTON or "Specialization & Talents",
		iconSpec = { atlas = "UI-HUD-MicroMenu-SpecTalents-Up" },
		action = openTalents,
	},
	{
		id = "spellbook",
		label = G.SPELLBOOK_ABILITIES_BUTTON or "Spellbook",
		iconSpec = { texture = "Interface\\Icons\\INV_Misc_Book_09" },
		action = openSpellbook,
	},
	{
		id = "collections",
		label = L["Warband Collections"] or G.COLLECTIONS or "Collections",
		iconSpec = { atlas = "UI-HUD-MicroMenu-Collections-Up" },
		action = openCollections,
	},
	{
		id = "gamemenu",
		label = G.MAINMENU_BUTTON or "Game Menu",
		iconSpec = function() return getMicroButtonIconSpec("MainMenuMicroButton", { atlas = "UI-HUD-MicroMenu-GameMenu-Up" }) end,
		action = openGameMenu,
	},
	{
		id = "support",
		label = L["Customer Support"] or G.HELP_BUTTON or "Customer Support",
		iconSpec = function()
			return getMicroButtonIconSpec("HelpMicroButton", {
				atlas = "UI-HUD-MicroMenu-Help-Up",
				fallback = { texture = "Interface\\TutorialFrame\\TutorialFrame-QuestionMark" },
			})
		end,
		action = openHelp,
	},
}

local entriesByID = {}
for _, entry in ipairs(menuEntries) do
	if entry.id then entriesByID[entry.id] = entry end
end

local inlineSecureButtons = {
	achievements = "AchievementMicroButton",
	character = "CharacterMicroButton",
	collections = "CollectionsMicroButton",
	dungeonjournal = "EJMicroButton",
	gamemenu = "MainMenuMicroButton",
	guild = "GuildMicroButton",
	lfg = "LFDMicroButton",
	professions = "ProfessionMicroButton",
	questlog = "QuestLogMicroButton",
	spellbook = "PlayerSpellsMicroButton",
	support = "HelpMicroButton",
	talents = "PlayerSpellsMicroButton",
}

local function getInlineSecureSpec(entryID)
	local buttonName = inlineSecureButtons[entryID]
	if not buttonName then return nil end
	local target = G[buttonName]
	if not target or type(target.Click) ~= "function" then return nil end
	return {
		key = "microbar:" .. entryID .. ":" .. buttonName,
		attributes = {
			type = "click",
			clickbutton = target,
		},
	}
end

local function hasCombinedPlayerSpellsButton()
	local button = G.PlayerSpellsMicroButton
	return button ~= nil and type(button.Click) == "function"
end

local function isEntryAvailable(entry)
	if not entry then return false end
	-- On Retail, talents/spellbook live behind one native PlayerSpells micro button.
	if entry.id == "spellbook" and hasCombinedPlayerSpellsButton() then return false end
	return true
end

local function getEntryLabel(entry)
	if entry and entry.id == "talents" and hasCombinedPlayerSpellsButton() then return L["Talents & Spellbook"] or "Talents & Spellbook" end
	local label = entry.label
	if type(label) == "function" then label = label() end
	if not label then label = "" end
	return label
end

local function getEntryIconSpec(entry)
	local iconSpec = entry.iconSpec
	if type(iconSpec) == "function" then iconSpec = iconSpec() end
	if type(iconSpec) ~= "table" then return nil end
	if iconSpec.atlas and atlasExists(iconSpec.atlas) then
		return {
			atlas = iconSpec.atlas,
			texCoord = resolvedIconTexCoord(iconSpec, true),
			offsetX = iconSpec.offsetX,
			offsetY = iconSpec.offsetY,
		}
	end
	if iconSpec.texture then return {
		texture = iconSpec.texture,
		texCoord = resolvedIconTexCoord(iconSpec, false),
		offsetX = iconSpec.offsetX,
		offsetY = iconSpec.offsetY,
	} end
	if type(iconSpec.fallback) == "table" then
		local fallback = iconSpec.fallback
		if fallback.atlas and atlasExists(fallback.atlas) then
			return {
				atlas = fallback.atlas,
				texCoord = resolvedIconTexCoord(fallback, true),
				offsetX = fallback.offsetX,
				offsetY = fallback.offsetY,
			}
		end
		if fallback.texture then return {
			texture = fallback.texture,
			texCoord = resolvedIconTexCoord(fallback, false),
			offsetX = fallback.offsetX,
			offsetY = fallback.offsetY,
		} end
	end
	return nil
end

local function getEntryIcon(entry, size)
	local iconSpec = getEntryIconSpec(entry)
	if not iconSpec then return "" end
	if iconSpec.atlas then return atlasIcon(iconSpec.atlas, size) end
	if iconSpec.texture then return textureIcon(iconSpec.texture, size) end
	return ""
end

local function getMenuLabel(entry)
	local label = getEntryLabel(entry)
	local icon = getEntryIcon(entry, getIconSize())
	return icon .. label
end

local function getOptionsEntryLabel(entry) return getEntryLabel(entry) end

local function isEntryEnabled(entry)
	if entry.enabled == nil then return true end
	if type(entry.enabled) == "function" then return entry.enabled() end
	return entry.enabled and true or false
end

local function RestorePosition(frame)
	if not db then return end
	if db.point and db.x ~= nil and db.y ~= nil then
		frame:ClearAllPoints()
		frame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
	end
end

local function createAceWindow()
	if aceWindow then
		aceWindow:Show()
		if aceScroll and aceScroll.SetScroll then aceScroll:SetScroll(0) end
		return
	end

	ensureDB()
	local frame = AceGUI:Create("Window")
	aceWindow = frame.frame
	frame:SetTitle((addon.DataPanel and addon.DataPanel.GetStreamOptionsTitle and addon.DataPanel.GetStreamOptionsTitle(stream and stream.meta and stream.meta.title)) or GAMEMENU_OPTIONS)
	frame:SetWidth(360)
	frame:SetHeight(560)
	frame:SetLayout("List")

	frame.frame:SetScript("OnShow", function(self) RestorePosition(self) end)
	frame.frame:SetScript("OnHide", function(self)
		local point, _, _, xOfs, yOfs = self:GetPoint()
		db.point = point
		db.x = xOfs
		db.y = yOfs
	end)

	local scroll = addon.functions.createContainer("ScrollFrame", "List")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	aceScroll = scroll
	frame:AddChild(scroll)

	local displayMode = AceGUI:Create("Dropdown")
	displayMode:SetLabel(L["MicroBarDisplayModeTitle"] or "Display mode")
	displayMode:SetList({
		menu = L["MicroBarDisplayModeMenu"] or "Show as menu",
		inline = L["MicroBarDisplayModeInline"] or "Show icons in DataPanel",
	}, { "menu", "inline" })
	displayMode:SetValue(db.displayMode)
	displayMode:SetCallback("OnValueChanged", function(_, _, val)
		if val ~= "menu" and val ~= "inline" then return end
		setDisplayMode(val)
	end)
	scroll:AddChild(displayMode)

	local iconSize = AceGUI:Create("Slider")
	iconSize:SetLabel(L["MicroBarIconSize"] or "Icon size")
	iconSize:SetSliderValues(MIN_ICON_SIZE, MAX_ICON_SIZE, 1)
	iconSize:SetValue(getIconSize())
	scroll:AddChild(iconSize)

	local iconGap = AceGUI:Create("Slider")
	iconGap:SetLabel(L["MicroBarIconGap"] or "Icon gap")
	iconGap:SetSliderValues(MIN_ICON_GAP, MAX_ICON_GAP, 1)
	iconGap:SetValue(getIconGap())
	scroll:AddChild(iconGap)

	local equalButtonSize = AceGUI:Create("CheckBox")
	equalButtonSize:SetLabel(L["MicroBarEqualButtons"] or "Use equal button size")
	equalButtonSize:SetValue(hasEqualButtonSize())
	scroll:AddChild(equalButtonSize)

	local buttonBackdrop = AceGUI:Create("CheckBox")
	buttonBackdrop:SetLabel(L["MicroBarButtonBackdrop"] or "Show button backdrop")
	buttonBackdrop:SetValue(hasButtonBackdrop())
	scroll:AddChild(buttonBackdrop)

	local buttonBorder = AceGUI:Create("CheckBox")
	buttonBorder:SetLabel(L["MicroBarButtonBorder"] or "Show button border")
	buttonBorder:SetValue(hasButtonBorder())
	scroll:AddChild(buttonBorder)

	local buttonBorderColor = AceGUI:Create("ColorPicker")
	buttonBorderColor:SetLabel(L["MicroBarButtonBorderColor"] or "Button border color")
	buttonBorderColor:SetHasAlpha(true)
	do
		local color = getButtonBorderColor()
		buttonBorderColor:SetColor(color.r, color.g, color.b, color.a)
	end
	scroll:AddChild(buttonBorderColor)

	local buttonSize = AceGUI:Create("Slider")
	buttonSize:SetLabel(L["MicroBarButtonSize"] or "Button size")
	buttonSize:SetSliderValues(MIN_BUTTON_SIZE, MAX_BUTTON_SIZE, 1)
	buttonSize:SetValue(getButtonSize())
	scroll:AddChild(buttonSize)

	local header = AceGUI:Create("Label")
	header:SetText(L["MicroBarVisibleEntries"] or "Visible icons")
	header:SetFullWidth(true)
	scroll:AddChild(header)

	for _, entry in ipairs(menuEntries) do
		if isEntryAvailable(entry) then
			local check = AceGUI:Create("CheckBox")
			check:SetLabel(getOptionsEntryLabel(entry))
			check:SetValue(not isEntryHidden(entry.id))
			check:SetCallback("OnValueChanged", function(_, _, val) setEntryHidden(entry.id, not (val and true or false)) end)
			scroll:AddChild(check)
		end
	end

	iconSize:SetCallback("OnValueChanged", function(_, _, val) setIconSize(val) end)

	iconGap:SetCallback("OnValueChanged", function(_, _, val) setIconGap(val) end)

	local function refreshButtonVisualState()
		local useButtonSizing = hasEqualButtonSize() or hasButtonBackdrop() or hasButtonBorder()
		if buttonSize.SetDisabled then buttonSize:SetDisabled(not useButtonSizing) end
		if buttonBorderColor.SetDisabled then buttonBorderColor:SetDisabled(not hasButtonBorder()) end
	end

	equalButtonSize:SetCallback("OnValueChanged", function(_, _, val)
		setEqualButtonSize(val and true or false)
		refreshButtonVisualState()
	end)

	buttonBackdrop:SetCallback("OnValueChanged", function(_, _, val)
		setButtonBackdrop(val and true or false)
		refreshButtonVisualState()
	end)

	buttonBorder:SetCallback("OnValueChanged", function(_, _, val)
		setButtonBorder(val and true or false)
		refreshButtonVisualState()
	end)

	buttonBorderColor:SetCallback("OnValueChanged", function(_, _, r, g, b, a) setButtonBorderColor(r, g, b, a) end)

	buttonSize:SetCallback("OnValueChanged", function(_, _, val) setButtonSize(val) end)

	refreshButtonVisualState()

	frame.frame:Show()
	scroll:DoLayout()
end

local function tryActivateEntry(entryID)
	local entry = entriesByID[entryID]
	if not entry then return false end
	if not isEntryAvailable(entry) then return false end
	if isEntryHidden(entry.id) then return false end
	if not isEntryEnabled(entry) then return false end
	if entry.action then entry.action() end
	return true
end

local function buildInlineParts()
	local parts = {}
	local iconSize = getIconSize()
	local equalButtons = hasEqualButtonSize()
	local buttonBackdrop = hasButtonBackdrop()
	local buttonBorder = hasButtonBorder()
	local buttonBorderColor = getButtonBorderColor()
	local buttonSize = getButtonSize()

	for _, entry in ipairs(menuEntries) do
		if isEntryAvailable(entry) and not isEntryHidden(entry.id) and isEntryEnabled(entry) then
			local iconSpec = getEntryIconSpec(entry)
			if iconSpec then
				local part = {
					id = entry.id,
				}
				local secureSpec = getInlineSecureSpec(entry.id)
				if secureSpec then part.secure = secureSpec end
				local widthBase = iconSize
				local displaySize = iconSize

				if buttonBackdrop or buttonBorder then
					widthBase = buttonSize
					if displaySize > buttonSize then displaySize = buttonSize end
					local borderAlpha = 0
					if buttonBorder then borderAlpha = buttonBorderColor.a or 0 end
					part.backdrop = {
						bgFile = "Interface\\Buttons\\WHITE8x8",
						edgeFile = "Interface\\Buttons\\WHITE8x8",
						edgeSize = math.max(1, floor(widthBase * 0.08 + 0.5)),
						bgColor = {
							buttonBackdrop and DEFAULT_BUTTON_BACKDROP_COLOR.r or 0,
							buttonBackdrop and DEFAULT_BUTTON_BACKDROP_COLOR.g or 0,
							buttonBackdrop and DEFAULT_BUTTON_BACKDROP_COLOR.b or 0,
							buttonBackdrop and DEFAULT_BUTTON_BACKDROP_COLOR.a or 0,
						},
						borderColor = {
							buttonBorderColor.r or DEFAULT_BUTTON_BORDER_COLOR.r,
							buttonBorderColor.g or DEFAULT_BUTTON_BORDER_COLOR.g,
							buttonBorderColor.b or DEFAULT_BUTTON_BORDER_COLOR.b,
							borderAlpha,
						},
					}
				else
					if equalButtons then
						if widthBase < buttonSize then widthBase = buttonSize end
					end
				end

				iconSpec.size = displaySize
				part.icon = iconSpec
				part.iconSize = displaySize
				part.iconWidth = widthBase
				if buttonBackdrop or buttonBorder then
					part.height = widthBase
				else
					part.height = displaySize
				end
				parts[#parts + 1] = part
			else
				parts[#parts + 1] = {
					id = entry.id,
					text = getEntryLabel(entry),
				}
			end
		end
	end
	return parts
end

local function showActionMenu(owner)
	if not MenuUtil or not MenuUtil.CreateContextMenu then return end
	MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
		rootDescription:SetTag("MENU_EQOL_MICROBAR")
		rootDescription:CreateTitle(L["Micro Bar"] or "Micro Bar")

		local hasEntries = false
		for _, entry in ipairs(menuEntries) do
			if isEntryAvailable(entry) and not isEntryHidden(entry.id) then
				hasEntries = true
				local label = getMenuLabel(entry)
				local enabled = isEntryEnabled(entry)
				local button = rootDescription:CreateButton(label, function()
					if enabled and entry.action then entry.action() end
					return MenuResponse and MenuResponse.Close
				end)
				if button and not enabled then button:SetEnabled(false) end
			end
		end

		if not hasEntries then
			local row = rootDescription:CreateButton(L["MicroBarNoEntries"] or "No entries visible")
			if row then row:SetEnabled(false) end
		end
	end)
end

local function updateMicroBar(stream)
	local snapshot = stream.snapshot
	snapshot.fontSize = getIconSize()
	snapshot.tooltip = nil
	snapshot.perCurrency = nil
	snapshot.showDescription = nil

	if isInlineMode() then
		local parts = buildInlineParts()
		if #parts > 0 then
			snapshot.parts = parts
			snapshot.partSpacing = getIconGap()
			snapshot.text = nil
			return
		end
	end

	snapshot.parts = nil
	snapshot.partSpacing = nil
	snapshot.text = L["Micro Bar"] or "Micro Bar"
end

local provider = {
	id = STREAM_ID,
	version = 1,
	title = L["Micro Bar"] or "Micro Bar",
	update = updateMicroBar,
	events = {
		PLAYER_ENTERING_WORLD = function(s) addon.DataHub:RequestUpdate(s) end,
	},
	OnClick = function(button, btn)
		if btn == "RightButton" then
			createAceWindow()
			return
		end
		if btn ~= "LeftButton" then return end
		if isInlineMode() and tryActivateEntry(button and button.currencyID) then return end
		showActionMenu(button)
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
