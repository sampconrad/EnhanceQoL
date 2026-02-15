local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Mover")
local db

local groupOrder = {
	system = 10,
	character = 20,
	housing = 25,
	activities = 30,
	world = 40,
	bags = 50,
	vendors = 60,
	professions = 70,
	addons = 80,
}

local groups = {
	system = {
		label = L["System"] or "System",
		expanded = true,
	},
	character = {
		label = L["Character"] or "Character",
	},
	housing = {
		label = AUCTION_CATEGORY_HOUSING or "Housing",
		expanded = true,
	},
	activities = {
		label = L["Activities"] or "Activities",
	},
	world = {
		label = L["World"] or "World",
	},
	bags = {
		label = L["Bags & Bank"] or "Bags & Bank",
	},
	vendors = {
		label = L["Vendors"] or "Vendors",
	},
	professions = {
		label = L["Professions"] or "Professions",
	},
	addons = {
		label = L["Addons"] or "Addons",
	},
}

local frames = {
	{
		id = "SettingsPanel",
		label = L["Settings"] or "Settings",
		group = "system",
		names = { "SettingsPanel" },
		addon = "Blizzard_Settings",
		defaultEnabled = true,
	},
	{
		id = "SplashFrame",
		label = L["What's New"] or "What's New",
		group = "system",
		names = { "SplashFrame" },
		defaultEnabled = true,
	},
	{
		id = "GameMenuFrame",
		label = L["Game Menu"] or "Game Menu",
		group = "system",
		names = { "GameMenuFrame" },
		addon = "Blizzard_GameMenu",
		handlesRelative = { "Header" },
		skipOnHide = true,
		defaultEnabled = true,
	},
	{
		id = "MacroFrame",
		label = L["Macros"] or "Macros",
		group = "system",
		names = { "MacroFrame" },
		addon = "Blizzard_MacroUI",
		defaultEnabled = true,
	},
	{
		id = "MacroPopupFrame",
		label = L["Macro Popup"] or "Macro Popup",
		group = "system",
		names = { "MacroPopupFrame" },
		addon = "Blizzard_MacroUI",
		defaultEnabled = true,
	},
	{
		id = "AddonList",
		label = L["Addon List"] or "Addon List",
		group = "system",
		names = { "AddonList" },
		defaultEnabled = true,
	},
	{
		id = "CatalogShopFrame",
		label = L["Blizzard Shop"] or "Blizzard Shop",
		group = "system",
		names = { "CatalogShopFrame" },
		defaultEnabled = true,
	},
	{
		id = "AchievementFrame",
		label = L["Achievements"] or "Achievements",
		group = "character",
		names = { "AchievementFrame" },
		addon = "Blizzard_AchievementUI",
		handlesRelative = { "Header" },
		defaultEnabled = true,
	},
	{
		id = "HousingControlsFrame",
		label = L["Housing Controls"] or "Housing Controls",
		group = "housing",
		names = { "HousingControlsFrame" },
		addon = "Blizzard_HousingControls",
		handlesRelative = { "OwnerControlFrame" },
		defaultEnabled = true,
	},
	{
		id = "HousingDashboardFrame",
		label = L["Housing Dashboard"] or "Housing Dashboard",
		group = "housing",
		names = { "HousingDashboardFrame" },
		addon = "Blizzard_HousingDashboard",
		defaultEnabled = true,
	},
	{
		id = "HouseFinderFrame",
		label = L["House Finder"] or "House Finder",
		group = "housing",
		names = { "HouseFinderFrame" },
		addon = "Blizzard_HousingHouseFinder",
		defaultEnabled = true,
	},
	{
		id = "HouseListFrame",
		label = L["House List"] or "House List",
		group = "housing",
		names = { "HouseListFrame" },
		addon = "Blizzard_HouseList",
		defaultEnabled = true,
	},
	{
		id = "HousingHouseSettingsFrame",
		label = L["Housing Settings"] or "Housing Settings",
		group = "housing",
		names = { "HousingHouseSettingsFrame" },
		addon = "Blizzard_HousingHouseSettings",
		defaultEnabled = true,
	},
	{
		id = "AbandonHouseConfirmationDialog",
		label = L["Abandon House"] or "Abandon House",
		group = "housing",
		names = { "AbandonHouseConfirmationDialog" },
		addon = "Blizzard_HousingHouseSettings",
		defaultEnabled = true,
	},
	{
		id = "HousingCornerstoneVisitorFrame",
		label = L["Housing Cornerstone Visitor"] or "Housing Cornerstone Visitor",
		group = "housing",
		names = { "HousingCornerstoneVisitorFrame", "HousingCornerstoneHouseInfoFrame" },
		addon = "Blizzard_HousingCornerstone",
		defaultEnabled = true,
	},
	{
		id = "HousingModelPreviewFrame",
		label = L["Housing Model Preview"] or "Housing Model Preview",
		group = "housing",
		names = { "HousingModelPreviewFrame" },
		addon = "Blizzard_HousingModelPreview",
		defaultEnabled = true,
	},
	{
		id = "CharacterFrame",
		label = L["Character"] or "Character",
		group = "character",
		names = { "CharacterFrame" },
		defaultEnabled = true,
	},
	{
		id = "CooldownViewerSettings",
		label = HUD_EDIT_MODE_COOLDOWN_VIEWER_OPTIONS,
		group = "character",
		names = { "CooldownViewerSettings" },
		addon = "Blizzard_CooldownViewer",
		defaultEnabled = true,
	},
	{
		id = "InspectFrame",
		label = INSPECT,
		group = "character",
		names = { "InspectFrame" },
		defaultEnabled = true,
		addon = "Blizzard_InspectUI",
	},
	{
		id = "PlayerSpellsFrame",
		label = L["Talents & Spells"] or "Talents & Spells",
		group = "character",
		names = { "PlayerSpellsFrame" },
		handlesRelative = { "TalentsFrame", "TalentsFrame.ButtonsParent", "SpecFrame" },
		addon = "Blizzard_PlayerSpells",
		defaultEnabled = true,
	},
	{
		id = "HeroTalentsSelectionDialog",
		label = L["Hero Talents"] or "Hero Talents",
		group = "character",
		names = { "HeroTalentsSelectionDialog" },
		addon = "Blizzard_PlayerSpells",
		defaultEnabled = true,
	},
	{
		id = "PVEFrame",
		label = L["Group Finder"] or "Group Finder",
		group = "activities",
		names = { "PVEFrame" },
		defaultEnabled = true,
	},
	{
		id = "EncounterJournal",
		label = ADVENTURE_JOURNAL,
		group = "activities",
		names = { "EncounterJournal" },
		addon = "Blizzard_EncounterJournal",
		defaultEnabled = true,
	},
	{
		id = "LFGDungeonReadyDialog",
		label = L["Dungeon Ready Dialog"] or "Dungeon Ready Dialog",
		group = "activities",
		names = { "LFGDungeonReadyDialog" },
		defaultEnabled = true,
	},
	{
		id = "LFGListInviteDialog",
		label = L["LFG List Invite Dialog"] or "LFG List Invite Dialog",
		group = "activities",
		names = { "LFGListInviteDialog" },
		defaultEnabled = true,
	},
	{
		id = "ReadyCheckFrame",
		label = L["Ready Check"] or "Ready Check",
		group = "activities",
		names = { "ReadyCheckFrame" },
		defaultEnabled = true,
	},
	{
		id = "WeeklyRewardsFrame",
		label = L["Great Vault"] or "Great Vault",
		group = "activities",
		names = { "WeeklyRewardsFrame" },
		addon = "Blizzard_WeeklyRewards",
		defaultEnabled = true,
	},
	{
		id = "DelvesCompanionConfigurationFrame",
		label = L["Delves Companion"] or "Delves Companion",
		group = "activities",
		names = { "DelvesCompanionConfigurationFrame" },
		addon = "Blizzard_DelvesDashboardUI",
		handlesRelative = { "CompanionPortraitFrame" },
		defaultEnabled = true,
	},
	{
		id = "TransmogFrame",
		label = L["TransmogFrame"] or "Transmog Frame",
		group = "system",
		names = { "TransmogFrame" },
		addon = "Blizzard_Transmog",
		defaultEnabled = true,
	},
	{
		id = "DelvesCompanionAbilityListFrame",
		label = L["Delves Companion Abilities"] or "Delves Companion Abilities",
		group = "activities",
		names = { "DelvesCompanionAbilityListFrame" },
		addon = "Blizzard_DelvesDashboardUI",
		defaultEnabled = true,
	},
	{
		id = "ChallengesKeystoneFrame",
		label = L["Font of Power"] or "Font of Power",
		group = "activities",
		names = { "ChallengesKeystoneFrame" },
		addon = "Blizzard_ChallengesUI",
		defaultEnabled = true,
	},
	{
		id = "ItemInteractionFrame",
		label = L["Catalyst"],
		group = "character",
		names = { "ItemInteractionFrame" },
		addon = "Blizzard_ItemInteractionUI",
		defaultEnabled = true,
	},
	{
		id = "PlayerChoiceFrame",
		label = L["Player Choice"] or "Player Choice",
		group = "character",
		names = { "PlayerChoiceFrame" },
		addon = "Blizzard_PlayerChoice",
		defaultEnabled = true,
	},
	{
		id = "WorldMapFrame",
		label = L["World Map"] or "World Map",
		group = "world",
		names = { "WorldMapFrame" },
		defaultEnabled = true,
	},
	{
		id = "BattlefieldMapFrame",
		label = _G.BATTLEFIELD_MINIMAP,
		group = "world",
		names = { "BattlefieldMapFrame" },
		addon = "Blizzard_BattlefieldMap",
		disableMove = true,
		scaleTargets = { "BattlefieldMapTab" },
		defaultEnabled = true,
	},
	{
		id = "FlightMapFrame",
		label = L["Flight Map"] or "Flight Map",
		group = "world",
		names = { "FlightMapFrame" },
		addon = "Blizzard_FlightMap",
		defaultEnabled = true,
	},
	{
		id = "ContainerFrameCombinedBags",
		label = L["Combined Bags"] or "Combined Bags",
		group = "bags",
		names = { "ContainerFrameCombinedBags" },
		defaultEnabled = true,
	},
	{
		id = "ItemUpgradeFrame",
		label = L["Item Upgrade"] or "Item Upgrade",
		group = "vendors",
		names = { "ItemUpgradeFrame" },
		addon = "Blizzard_ItemUpgradeUI",
		defaultEnabled = true,
	},
	{
		id = "ItemSocketingFrame",
		label = ITEM_SOCKETING,
		group = "vendors",
		names = { "ItemSocketingFrame" },
		addon = "Blizzard_ItemSocketingUI",
		defaultEnabled = true,
	},
	{
		id = "ExpansionLandingPage",
		label = L["Expansion Landing Page"] or "Expansion Landing Page",
		group = "activities",
		names = { "ExpansionLandingPage" },
		addon = "Blizzard_MajorFactions",
		defaultEnabled = true,
	},
	{
		id = "MajorFactionRenownFrame",
		label = L["Renown"] or "Renown",
		group = "activities",
		names = { "MajorFactionRenownFrame" },
		handlesRelative = { "HeaderFrame" },
		addon = "Blizzard_MajorFactions",
		defaultEnabled = true,
	},
	{
		id = "ProfessionsCustomerOrdersFrame",
		label = L["Customer Orders"] or "Customer Orders",
		group = "professions",
		names = { "ProfessionsCustomerOrdersFrame" },
		addon = "Blizzard_ProfessionsCustomerOrders",
		defaultEnabled = true,
	},
	{
		id = "MerchantFrame",
		label = L["Merchant"] or "Merchant",
		group = "vendors",
		names = { "MerchantFrame" },
		defaultEnabled = true,
		ignoreFramePositionManager = true,
		userPlaced = true,
	},
	{
		id = "AuctionHouseFrame",
		label = L["Auction House"] or "Auction House",
		group = "vendors",
		names = { "AuctionHouseFrame" },
		addon = "Blizzard_AuctionHouseUI",
		defaultEnabled = true,
	},
	{
		id = "MailFrame",
		label = L["Mail"] or "Mail",
		group = "vendors",
		names = { "MailFrame" },
		addon = "Blizzard_MailFrame",
		useRootHandle = true,
		handles = { "SendMailFrame", "MailFrameInset" },
		defaultEnabled = true,
	},
	{
		id = "OpenMailFrame",
		label = L["OpenMail"] or "Open Mail",
		group = "vendors",
		names = { "OpenMailFrame" },
		addon = "Blizzard_MailFrame",
		useRootHandle = true,
		handles = { "OpenMailSender", "OpenMailFrameInset" },
		defaultEnabled = true,
	},
	{
		id = "ChatConfigFrame",
		label = L["Chat Settings"] or "Chat Settings",
		group = "system",
		names = { "ChatConfigFrame" },
		defaultEnabled = true,
	},
	{
		id = "HelpFrame",
		label = L["Support"] or "Support",
		group = "system",
		names = { "HelpFrame" },
		addon = "Blizzard_HelpFrame",
		defaultEnabled = true,
	},
	{
		id = "GarrisonCapacitiveDisplayFrame",
		label = L["Garrison"] or "Garrison",
		group = "activities",
		names = { "GarrisonCapacitiveDisplayFrame" },
		addon = "Blizzard_GarrisonUI",
		defaultEnabled = true,
	},
	{
		id = "DressUpFrame",
		label = L["Dressing Room"] or "Dressing Room",
		group = "character",
		names = { "DressUpFrame" },
		defaultEnabled = true,
	},
	{
		id = "CommunitiesFrame",
		label = L["Communities"] or "Communities",
		group = "activities",
		names = { "CommunitiesFrame" },
		addon = "Blizzard_Communities",
		defaultEnabled = true,
	},
	{
		id = "ClubFinderCommunityAndGuildFinderFrame",
		label = L["Community & Guild Finder"] or "Community & Guild Finder",
		group = "activities",
		names = { "ClubFinderCommunityAndGuildFinderFrame.RequestToJoinFrame" },
		addon = "Blizzard_Communities",
		defaultEnabled = true,
	},
	{
		id = "ClubFinderGuildFinderFrame",
		label = L["Guild Finder"] or "Guild Finder",
		group = "activities",
		names = { "ClubFinderGuildFinderFrame.RequestToJoinFrame" },
		addon = "Blizzard_Communities",
		defaultEnabled = true,
	},
	{
		id = "CommunitiesGuildLogFrame",
		label = L["Guild Log"] or "Guild Log",
		group = "activities",
		names = { "CommunitiesGuildLogFrame" },
		addon = "Blizzard_Communities",
		defaultEnabled = true,
	},
	{
		id = "CommunitiesGuildNewsFiltersFrame",
		label = L["Guild News Filters"] or "Guild News Filters",
		group = "activities",
		names = { "CommunitiesGuildNewsFiltersFrame" },
		addon = "Blizzard_Communities",
		defaultEnabled = true,
	},
	{
		id = "CommunitiesGuildTextEditFrame",
		label = L["Guild Text Edit"] or "Guild Text Edit",
		group = "activities",
		names = { "CommunitiesGuildTextEditFrame" },
		addon = "Blizzard_Communities",
		defaultEnabled = true,
	},
	{
		id = "CommunitiesRecruitmentDialog",
		label = L["Community Recruitment"] or "Community Recruitment",
		group = "activities",
		names = { "CommunitiesFrame.RecruitmentDialog" },
		addon = "Blizzard_Communities",
		defaultEnabled = true,
	},
	{
		id = "CommunitiesNotificationSettingsDialog",
		label = L["Community Notification Settings"] or "Community Notification Settings",
		group = "activities",
		names = { "CommunitiesFrame.NotificationSettingsDialog" },
		addon = "Blizzard_Communities",
		defaultEnabled = true,
	},
	{
		id = "FriendsFrame",
		label = L["Friends"] or "Friends",
		group = "activities",
		names = { "FriendsFrame" },
		defaultEnabled = true,
	},
	{
		id = "FriendsFrameIgnoreList",
		label = L["Ignore List"] or "Ignore List",
		group = "activities",
		names = { "FriendsFrame.IgnoreListWindow" },
		defaultEnabled = true,
	},
	{
		id = "RecruitAFriendRewardsFrame",
		label = L["Recruit A Friend Rewards"] or "Recruit A Friend Rewards",
		group = "activities",
		names = { "RecruitAFriendRewardsFrame" },
		defaultEnabled = true,
	},
	{
		id = "RecruitAFriendRecruitmentFrame",
		label = L["Recruit A Friend"] or "Recruit A Friend",
		group = "activities",
		names = { "RecruitAFriendRecruitmentFrame" },
		defaultEnabled = true,
	},
	{
		id = "FriendsFriendsFrame",
		label = L["Friends List"] or "Friends List",
		group = "activities",
		names = { "FriendsFriendsFrame" },
		defaultEnabled = true,
	},
	{
		id = "RaidInfoFrame",
		label = L["Raid Info"] or "Raid Info",
		group = "activities",
		names = { "RaidInfoFrame" },
		defaultEnabled = true,
	},
	{
		id = "AddFriendFrame",
		label = L["Add Friend"] or "Add Friend",
		group = "activities",
		names = { "AddFriendFrame" },
		defaultEnabled = true,
	},
	{
		id = "ClassTrainerFrame",
		label = MINIMAP_TRACKING_TRAINER_CLASS,
		group = "world",
		names = { "ClassTrainerFrame" },
		addon = "Blizzard_TrainerUI",
		defaultEnabled = true,
	},
	{
		id = "BankFrame",
		label = L["Bank"] or "Bank",
		group = "bags",
		names = { "BankFrame" },
		defaultEnabled = true,
	},
	{
		id = "ArtifactFrame",
		label = L["Artifact"] or "Artifact",
		group = "character",
		names = { "ArtifactFrame" },
		addon = "Blizzard_ArtifactUI",
		defaultEnabled = true,
	},
	{
		id = "CollectionsJournal",
		label = L["Collections"] or "Collections",
		group = "character",
		names = { "CollectionsJournal" },
		addon = "Blizzard_Collections",
		defaultEnabled = true,
	},
	{
		id = "ProfessionsFrame",
		label = L["Professions"] or "Professions",
		group = "professions",
		names = { "ProfessionsFrame" },
		addon = "Blizzard_Professions",
		defaultEnabled = true,
	},
	{
		id = "ProfessionsBookFrame",
		label = L["Professions Book"] or "Professions Book",
		group = "professions",
		names = { "ProfessionsBookFrame" },
		addon = "Blizzard_ProfessionsBook",
		defaultEnabled = true,
	},
	{
		id = "QuestFrame",
		label = L["Quest"] or "Quest",
		group = "world",
		names = { "QuestFrame", "GossipFrame" },
		defaultEnabled = true,
	},
	{
		id = "StaticPopup",
		label = L["Static Popups"] or "Static Popups",
		group = "system",
		names = { "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4", "StaticPopup5" },
		defaultEnabled = true,
	},
	{
		id = "EventToastManagerFrame",
		label = L["Event Toasts"] or "Event Toasts",
		group = "system",
		names = { "EventToastManagerFrame" },
		defaultEnabled = true,
	},
	{
		id = "CalendarFrame",
		label = L["Calendar"] or "Calendar",
		group = "system",
		names = { "CalendarFrame" },
		addon = "Blizzard_Calendar",
		defaultEnabled = true,
	},
	{
		id = "CalendarViewHolidayFrame",
		label = L["Calendar Holiday"] or "Calendar Holiday",
		group = "system",
		names = { "CalendarViewHolidayFrame" },
		addon = "Blizzard_Calendar",
		defaultEnabled = true,
	},
	{
		id = "CalendarCreateEventFrame",
		label = L["Calendar Event"] or "Calendar Event",
		group = "system",
		names = { "CalendarCreateEventFrame" },
		addon = "Blizzard_Calendar",
		defaultEnabled = true,
	},
	{
		id = "TimeManagerFrame",
		label = L["Time Manager"] or "Time Manager",
		group = "system",
		names = { "TimeManagerFrame" },
		addon = "Blizzard_TimeManager",
		defaultEnabled = true,
	},
	{
		id = "CovenantSanctumFrame",
		label = L["Covenant Sanctum Frame"] or "Covenant Sanctum Frame",
		group = "activities",
		names = { "CovenantSanctumFrame" },
		addon = "Blizzard_CovenantSanctum",
		defaultEnabled = true,
	},
	{
		id = "CovenantMissionFrame",
		label = L["Covenant Mission Frame"] or "Covenant Mission Frame",
		group = "activities",
		names = { "CovenantMissionFrame" },
		addon = "Blizzard_GarrisonUI",
		defaultEnabled = true,
	},
	{
		id = "CovenantRenownFrame",
		label = L["Covenant Renown Frame"] or "Covenant Renown Frame",
		group = "activities",
		names = { "CovenantRenownFrame" },
		addon = "Blizzard_CovenantRenown",
		defaultEnabled = true,
	},
	{
		id = "CovenantPreviewFrame",
		label = L["Covenant Preview Frame"] or "Covenant Preview Frame",
		group = "activities",
		names = { "CovenantPreviewFrame" },
		addon = "Blizzard_CovenantPreviewUI",
		defaultEnabled = true,
	},
	{
		id = "GarrisonLandingPage",
		label = L["Garrison Landing Page"] or "Garrison Landing Page",
		group = "activities",
		names = { "GarrisonLandingPage" },
		addon = "Blizzard_GarrisonUI",
		defaultEnabled = true,
	},
}

local settings = {
	{
		type = "checkbox",
		var = "moverEnabled",
		dbKey = "enabled",
		text = L["Global Move Enabled"] or "Enable moving",
		desc = L["Global Move Enabled Desc"] or "Enable movable handles to reposition frames.",
		default = false,
		get = function() return db.enabled end,
		set = function(value)
			db.enabled = value
			addon.Mover.functions.ApplyAll()
			if addon.Mover.functions.UpdateScaleWheelCaptureState then addon.Mover.functions.UpdateScaleWheelCaptureState() end
		end,
	},
	{
		type = "checkbox",
		var = "moverScaleEnabled",
		dbKey = "scaleEnabled",
		text = L["Global Scale Enabled"] or "Enable scaling",
		desc = L["Global Scale Enabled Desc"] or "Enable scaling with the mouse wheel on the move handle.",
		default = false,
		get = function() return db.scaleEnabled end,
		set = function(value)
			db.scaleEnabled = value
			addon.Mover.functions.ApplyAll()
			if addon.Mover.functions.UpdateScaleWheelCaptureState then addon.Mover.functions.UpdateScaleWheelCaptureState() end
		end,
		notify = "moverEnabled",
	},
	{
		type = "dropdown",
		var = "moverScaleModifier",
		dbKey = "scaleModifier",
		text = L["Scale Modifier"] or "Scale modifier key",
		desc = L["Scale Modifier Desc"] or "Select the modifier key used for scaling.",
		list = { SHIFT = "SHIFT", CTRL = "CTRL", ALT = "ALT" },
		order = { "SHIFT", "CTRL", "ALT" },
		default = "CTRL",
		get = function() return db.scaleModifier or "CTRL" end,
		set = function(value)
			db.scaleModifier = value
			if addon.Mover.functions.UpdateScaleWheelCaptureState then addon.Mover.functions.UpdateScaleWheelCaptureState() end
		end,
		parentCheck = function() return db.scaleEnabled end,
	},
	{
		type = "dropdown",
		var = "moverPositionPersistence",
		dbKey = "positionPersistence",
		text = L["Position Persistence"] or "Position persistence",
		list = {
			close = {
				text = L["Position Persistence Close"] or "Until close of the frame",
				tooltip = L["Position Persistence Close Tooltip"] or "Does not save the position and resets when the frame closes.",
			},
			lockout = {
				text = L["Position Persistence Lockout"] or "Until logout",
				tooltip = L["Position Persistence Lockout Tooltip"] or "Saves the position only until you log out.",
			},
			reset = {
				text = L["Position Persistence Reset"] or "Until reset",
				tooltip = L["Position Persistence Reset Tooltip"] or "Saves the position until you reset it.",
			},
		},
		order = { "close", "lockout", "reset" },
		default = "reset",
		get = function() return db.positionPersistence or "reset" end,
		set = function(value)
			db.positionPersistence = value
			addon.Mover.functions.ApplyAll()
		end,
		parentCheck = function() return db.enabled end,
	},
	{
		type = "checkbox",
		var = "moverRequireModifier",
		dbKey = "requireModifier",
		text = L["Require Modifier For Move"] or "Require modifier to move",
		desc = L["Require Modifier For Move Desc"] or "When enabled, hold the move modifier to drag frames.",
		default = true,
		get = function() return db.requireModifier end,
		set = function(value) db.requireModifier = value end,
		parentCheck = function() return db.enabled end,
		notify = "moverEnabled",
	},
	{
		type = "dropdown",
		var = "moverModifier",
		dbKey = "modifier",
		text = L["Move Modifier"] or (L["Scale Modifier"] or "Modifier"),
		desc = L["Move Modifier Desc"] or "Select the modifier key used for moving.",
		list = { SHIFT = "SHIFT", CTRL = "CTRL", ALT = "ALT" },
		order = { "SHIFT", "CTRL", "ALT" },
		default = "SHIFT",
		get = function() return db.modifier or "SHIFT" end,
		set = function(value) db.modifier = value end,
		parentCheck = function() return db.enabled and db.requireModifier end,
	},
}

addon.Mover.variables.groupOrder = groupOrder
addon.Mover.variables.groups = groups
addon.Mover.variables.frames = frames
addon.Mover.variables.settings = settings

local function initSettingsDefaults()
	if not db then return end
	for _, def in ipairs(settings) do
		if def.dbKey and def.default ~= nil and db[def.dbKey] == nil then db[def.dbKey] = def.default end
	end
end

function addon.Mover.functions.InitRegistry()
	if addon.Mover.variables.registryInitialized then return end
	db = addon.Mover.db
	if not db then return end

	initSettingsDefaults()
	if addon.Mover.functions.EnsureScaleCaptureFrame then addon.Mover.functions.EnsureScaleCaptureFrame() end

	for groupId, group in pairs(groups) do
		local order = groupOrder[groupId] or group.order
		addon.Mover.functions.RegisterGroup(groupId, group.label, {
			order = order,
			expanded = group.expanded,
		})
	end

	for _, def in ipairs(frames) do
		if def.group and groupOrder[def.group] and def.groupOrder == nil then def.groupOrder = groupOrder[def.group] end
		addon.Mover.functions.RegisterFrame(def)
	end

	addon.Mover.variables.registryInitialized = true
end
