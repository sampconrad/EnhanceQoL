local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local cChatFrame = addon.functions.SettingsCreateCategory(nil, CHAT, nil, "ChatFrame")
addon.SettingsLayout.chatframeCategory = cChatFrame

addon.functions.SettingsCreateHeadline(cChatFrame, COMMUNITIES_ADD_TO_CHAT_DROP_DOWN_TITLE)

local data = {
	{
		var = "chatShowLootCurrencyIcons",
		text = L["chatLootCurrencyIcons"],
		desc = L["chatLootCurrencyIconsDesc"],
		func = function(key)
			addon.db["chatShowLootCurrencyIcons"] = key
			if addon.ChatIcons and addon.ChatIcons.SetEnabled then addon.ChatIcons:SetEnabled(key) end
		end,
		default = false,
	},
	{
		var = "chatFrameMaxLines2000",
		text = L["chatFrameMaxLines2000"],
		desc = L["chatFrameMaxLines2000Desc"],
		func = function(key)
			addon.db["chatFrameMaxLines2000"] = key
			if addon.functions.ApplyChatFrameMaxLines then addon.functions.ApplyChatFrameMaxLines() end
		end,
		default = false,
	},
	{
		var = "chatShowItemLevelInLinks",
		text = L["chatItemLevelInLink"],
		desc = L["chatItemLevelInLinkDesc"],
		func = function(key)
			addon.db["chatShowItemLevelInLinks"] = key
			if addon.ChatIcons and addon.ChatIcons.SetItemLevelEnabled then addon.ChatIcons:SetItemLevelEnabled(key) end
		end,
		default = false,
		children = {
			{
				var = "chatShowItemLevelLocation",
				text = L["chatItemLevelLocation"],
				desc = L["chatItemLevelLocationDesc"],
				func = function(key)
					addon.db["chatShowItemLevelLocation"] = key
					if addon.ChatIcons and addon.ChatIcons.SetItemLevelLocation then addon.ChatIcons:SetItemLevelLocation(key) end
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["chatShowItemLevelInLinks"]
						and addon.SettingsLayout.elements["chatShowItemLevelInLinks"].setting
						and addon.SettingsLayout.elements["chatShowItemLevelInLinks"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
			},
		},
	},
	{
		var = "chatHideLearnUnlearn",
		text = L["chatHideLearnUnlearn"],
		desc = L["chatHideLearnUnlearn"],
		func = function(key)
			addon.db["chatHideLearnUnlearn"] = key
			if addon.functions.ApplyChatLearnFilter then addon.functions.ApplyChatLearnFilter(key) end
		end,
		default = false,
	},
	{
		var = "chatFrameFadeEnabled",
		text = L["chatFrameFadeEnabled"],
		desc = L["chatFrameFadeEnabled"],
		func = function(key)
			addon.db["chatFrameFadeEnabled"] = key
			if ChatFrame1 then ChatFrame1:SetFading(key) end
		end,
		default = false,
		children = {
			{
				var = "chatFrameFadeTimeVisible",
				text = L["chatFrameFadeTimeVisibleText"],
				parentCheck = function()
					return addon.SettingsLayout.elements["chatFrameFadeEnabled"]
						and addon.SettingsLayout.elements["chatFrameFadeEnabled"].setting
						and addon.SettingsLayout.elements["chatFrameFadeEnabled"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.chatFrameFadeTimeVisible or 30 end,
				set = function(value)
					addon.db["chatFrameFadeTimeVisible"] = value
					if ChatFrame1 then ChatFrame1:SetTimeVisible(value) end
				end,
				min = 1,
				max = 300,
				step = 1,
				parent = true,
				default = 30,
				sType = "slider",
			},
			{
				var = "chatFrameFadeDuration",
				text = L["chatFrameFadeDurationText"],
				parentCheck = function()
					return addon.SettingsLayout.elements["chatFrameFadeEnabled"]
						and addon.SettingsLayout.elements["chatFrameFadeEnabled"].setting
						and addon.SettingsLayout.elements["chatFrameFadeEnabled"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.chatFrameFadeDuration or 30 end,
				set = function(value)
					addon.db["chatFrameFadeDuration"] = value
					if ChatFrame1 then ChatFrame1:SetTimeVisible(value) end
				end,
				min = 1,
				max = 60,
				step = 1,
				parent = true,
				default = 3,
				sType = "slider",
			},
		},
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cChatFrame, data)

addon.functions.SettingsCreateHeadline(cChatFrame, CHAT_BUBBLES_TEXT)

data = {
	{
		var = "chatBubbleFontOverride",
		text = L["chatBubbleFontOverride"],
		desc = L["chatBubbleFontOverrideDesc"],
		func = function(key)
			addon.db["chatBubbleFontOverride"] = key
			addon.functions.ApplyChatBubbleFontSize(addon.db["chatBubbleFontSize"])
		end,
		default = false,
		children = {
			{
				var = "chatBubbleFontSize",
				text = L["chatBubbleFontSize"],
				parentCheck = function()
					return addon.SettingsLayout.elements["chatBubbleFontOverride"]
						and addon.SettingsLayout.elements["chatBubbleFontOverride"].setting
						and addon.SettingsLayout.elements["chatBubbleFontOverride"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.chatBubbleFontSize or 13 end,
				set = function(value)
					addon.db["chatBubbleFontSize"] = value
					local applied = addon.functions.ApplyChatBubbleFontSize(value)
				end,
				min = 1,
				max = 36,
				step = 1,
				parent = true,
				default = 13,
				sType = "slider",
			},
		},
	},
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cChatFrame, data)

addon.functions.SettingsCreateHeadline(cChatFrame, L["Instant Chats"])
addon.functions.SettingsCreateText(cChatFrame, "|cff99e599" .. L["RightClickCloseTab"] .. "|r")

data = {
	{
		var = "enableChatIM",
		text = L["enableChatIM"],
		desc = L["enableChatIMDesc"],
		func = function(key)
			addon.db["enableChatIM"] = key
			if addon.ChatIM and addon.ChatIM.SetEnabled then addon.ChatIM:SetEnabled(key) end
		end,
		default = false,
		notify = "chatIMUseCustomSound",
		children = {
			{

				var = "enableChatIMFade",
				text = L["enableChatIMFade"],
				desc = L["enableChatIMFadeDesc"],
				func = function(v)
					addon.db["enableChatIMFade"] = v
					if addon.ChatIM and addon.ChatIM.SetEnabled then addon.ChatIM:UpdateAlpha() end
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["enableChatIM"]
						and addon.SettingsLayout.elements["enableChatIM"].setting
						and addon.SettingsLayout.elements["enableChatIM"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
			},
			{

				var = "enableChatIMWCL",
				text = L["enableChatIMWCL"],
				func = function(v) addon.db["enableChatIMWCL"] = v end,
				parentCheck = function()
					return addon.SettingsLayout.elements["enableChatIM"]
						and addon.SettingsLayout.elements["enableChatIM"].setting
						and addon.SettingsLayout.elements["enableChatIM"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
			},
			{

				var = "chatIMUseCustomSound",
				text = L["chatIMUseCustomSound"],
				func = function(v) addon.db["chatIMUseCustomSound"] = v end,
				parentCheck = function()
					return addon.SettingsLayout.elements["enableChatIM"]
						and addon.SettingsLayout.elements["enableChatIM"].setting
						and addon.SettingsLayout.elements["enableChatIM"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
				children = {
					{

						var = "ChatIMCustomSound",
						text = L["ChatIMCustomSound"],
						default = "",
						optionfunc = function()
							if addon.ChatIM and addon.ChatIM.BuildSoundTable and not addon.ChatIM.availableSounds then addon.ChatIM:BuildSoundTable() end
							local tList = { [""] = "" }
							for name in pairs(addon.ChatIM.availableSounds or {}) do
								tList[name] = name
							end
							return tList
						end,
						get = function() return addon.db.chatIMCustomSoundFile or "" end,
						set = function(key) addon.db.chatIMCustomSoundFile = key end,
						parentCheck = function()
							return (
								addon.SettingsLayout.elements["chatIMUseCustomSound"]
								and addon.SettingsLayout.elements["chatIMUseCustomSound"].setting
								and addon.SettingsLayout.elements["chatIMUseCustomSound"].setting:GetValue() == true
								and addon.SettingsLayout.elements["enableChatIM"]
								and addon.SettingsLayout.elements["enableChatIM"].setting
								and addon.SettingsLayout.elements["enableChatIM"].setting:GetValue() == true
							) or false
						end,
						parent = true,
						sType = "sounddropdown",
					},
				},
			},
			{

				var = "chatIMHideInCombat",
				text = L["chatIMHideInCombat"],
				func = function(v) addon.db["chatIMHideInCombat"] = v end,
				parentCheck = function()
					return addon.SettingsLayout.elements["enableChatIM"]
						and addon.SettingsLayout.elements["enableChatIM"].setting
						and addon.SettingsLayout.elements["enableChatIM"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
			},
			{

				var = "chatIMUseAnimation",
				text = L["chatIMUseAnimation"],
				desc = L["chatIMUseAnimationDesc"],
				func = function(v) addon.db["chatIMUseAnimation"] = v end,
				parentCheck = function()
					return addon.SettingsLayout.elements["enableChatIM"]
						and addon.SettingsLayout.elements["enableChatIM"].setting
						and addon.SettingsLayout.elements["enableChatIM"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
			},
			{
				var = "chatIMMaxHistory",
				text = L["ChatIMHistoryLimit"],
				parentCheck = function()
					return addon.SettingsLayout.elements["enableChatIM"]
						and addon.SettingsLayout.elements["enableChatIM"].setting
						and addon.SettingsLayout.elements["enableChatIM"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.chatIMMaxHistory or 30 end,
				set = function(value)
					addon.db["chatIMMaxHistory"] = value
					if addon.ChatIM and addon.ChatIM.SetMaxHistoryLines then addon.ChatIM:SetMaxHistoryLines(value) end
				end,
				min = 0,
				max = 1000,
				step = 1,
				parent = true,
				default = 300,
				sType = "slider",
			},
		},
	},
}

table.sort(data[1].children, function(a, b) return a.text < b.text end)
table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cChatFrame, data)

data = {
	listFunc = function()
		local tList = { [""] = "" }
		for name in pairs(EnhanceQoL_IMHistory or {}) do
			tList[name] = name
		end
		return tList
	end,
	text = L["ChatIMHistoryDelete"],
	get = function() return "" end,
	set = function(key)
		StaticPopupDialogs["EQOL_DELETE_IM_HISTORY"] = StaticPopupDialogs["EQOL_DELETE_IM_HISTORY"]
			or {
				text = L["ChatIMHistoryDeleteConfirm"],
				button1 = YES,
				button2 = CANCEL,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
			}
		StaticPopupDialogs["EQOL_DELETE_IM_HISTORY"].OnAccept = function()
			EnhanceQoL_IMHistory[key] = nil
			if addon.ChatIM and addon.ChatIM.history then addon.ChatIM.history[key] = nil end
		end
		StaticPopup_Show("EQOL_DELETE_IM_HISTORY", key)
	end,
	parentCheck = function()
		return addon.SettingsLayout.elements["enableChatIM"] and addon.SettingsLayout.elements["enableChatIM"].setting and addon.SettingsLayout.elements["enableChatIM"].setting:GetValue() == true
	end,
	parent = true,
	element = addon.SettingsLayout.elements["enableChatIM"].element,
	default = "",
	var = "ChatIMHistoryClear",
	type = Settings.VarType.String,
}
addon.functions.SettingsCreateScrollDropdown(cChatFrame, data)

data = {
	var = "ChatIMHistoryClearAll",
	text = L["ChatIMHistoryClearAll"],
	parentCheck = function()
		return addon.SettingsLayout.elements["enableChatIM"] and addon.SettingsLayout.elements["enableChatIM"].setting and addon.SettingsLayout.elements["enableChatIM"].setting:GetValue() == true
	end,
	func = function()
		StaticPopupDialogs["EQOL_CLEAR_IM_HISTORY"] = StaticPopupDialogs["EQOL_CLEAR_IM_HISTORY"]
			or {
				text = L["ChatIMHistoryClearConfirm"],
				button1 = YES,
				button2 = CANCEL,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
			}
		StaticPopupDialogs["EQOL_CLEAR_IM_HISTORY"].OnAccept = function()
			wipe(EnhanceQoL_IMHistory)
			if addon.ChatIM then addon.ChatIM.history = EnhanceQoL_IMHistory end
		end
		StaticPopup_Show("EQOL_CLEAR_IM_HISTORY")
	end,
}
addon.functions.SettingsCreateButton(cChatFrame, data)

addon.functions.SettingsCreateHeadline(cChatFrame, L["CH_TITLE_HISTORY"])

local chatHistoryStrataOptions = {}
local strataOrder = {
	"BACKGROUND",
	"LOW",
	"MEDIUM",
	"HIGH",
	"DIALOG",
	"FULLSCREEN",
	"FULLSCREEN_DIALOG",
	"TOOLTIP",
}
for _, strata in ipairs(strataOrder) do
	chatHistoryStrataOptions[strata] = strata
end

local categoryOptions = {}
local function colorizeChannelLabel(key, text)
	local info = ChatTypeInfo and ChatTypeInfo[key]
	if not info and key == "GENERAL" then info = ChatTypeInfo and ChatTypeInfo["CHANNEL1"] end
	if info and info.r and info.g and info.b then
		local hex = string.format("|cff%02x%02x%02x", (info.r or 1) * 255, (info.g or 1) * 255, (info.b or 1) * 255)
		return string.format("%s%s|r", hex, text)
	end
	return text
end

local function makeFilterLabel(key, icon, text)
	local lbl = colorizeChannelLabel(key, text or key)
	if icon and icon ~= "" then return string.format("|T%s:14:14:0:0|t %s", icon, lbl) end
	return lbl
end

local CHAT_FILTER_OPTIONS = {
	{ key = "SAY", label = makeFilterLabel("SAY", "2056011", SAY) },
	{ key = "YELL", label = makeFilterLabel("YELL", "892447", YELL) },
	{ key = "WHISPER", label = makeFilterLabel("WHISPER", "133458", WHISPER) },
	{ key = "BN_WHISPER", label = makeFilterLabel("BN_WHISPER", "Interface\\FriendsFrame\\UI-Toast-ChatInviteIcon", BN_WHISPER) },
	{ key = "PARTY", label = makeFilterLabel("PARTY", "134149", PARTY) },
	{ key = "INSTANCE", label = makeFilterLabel("INSTANCE", "Interface\\AddOns\\EnhanceQoL\\Icons\\Dungeon.tga", INSTANCE) },
	{ key = "RAID", label = makeFilterLabel("RAID", "Interface\\AddOns\\EnhanceQoL\\Icons\\Raid.tga", RAID) },
	{ key = "GUILD", label = makeFilterLabel("GUILD", "514261", GUILD) },
	{ key = "OFFICER", label = makeFilterLabel("OFFICER", "133071", OFFICER) },
	{ key = "GENERAL", label = makeFilterLabel("GENERAL", nil, GENERAL) },
	{ key = "LOOT", label = makeFilterLabel("LOOT", "133639", LOOT) },
	{ key = "MONEY", label = makeFilterLabel("MONEY", "133785", MONEY) },
	{ key = "CURRENCY", label = makeFilterLabel("CURRENCY", "Interface\\Icons\\inv_misc_coin_01", CURRENCY) },
	{ key = "ACHIEVEMENT", label = makeFilterLabel("ACHIEVEMENT", "236507", ACHIEVEMENTS) },
	{ key = "SYSTEM", label = makeFilterLabel("SYSTEM", nil, SYSTEM_MESSAGES or SYSTEM) },
	{ key = "OPENING", label = makeFilterLabel("OPENING", nil, OPENING) },
	{ key = "MONSTER", label = makeFilterLabel("MONSTER", nil, EXAMPLE_TARGET_MONSTER or "Monster") },
}

data = {
	{
		var = "enableChatHistory",
		text = L["CH_OPTION_ENABLE"],
		desc = L["CH_OPTION_ENABLE_DESC"],
		func = function(val)
			addon.db["enableChatHistory"] = val
			if addon.ChatIM and addon.ChatIM.ChannelHistory and addon.ChatIM.ChannelHistory.SetEnabled then addon.ChatIM.ChannelHistory:SetEnabled(val) end
		end,
		default = false,
		children = {
			{
				var = "chatChannelHistoryMaxLines",
				text = L["CH_OPTION_MAX_LINES"],
				parentCheck = function()
					return addon.SettingsLayout.elements["enableChatHistory"]
						and addon.SettingsLayout.elements["enableChatHistory"].setting
						and addon.SettingsLayout.elements["enableChatHistory"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.chatChannelHistoryMaxLines or 500 end,
				set = function(value)
					addon.db["chatChannelHistoryMaxLines"] = value
					if addon.ChatIM and addon.ChatIM.ChannelHistory and addon.ChatIM.ChannelHistory.SetMaxLines then
						addon.ChatIM.ChannelHistory:SetMaxLines(value)
						addon.ChatIM.ChannelHistory:RequestLogRefresh()
					end
				end,
				min = 0,
				max = 2000,
				step = 10,
				parent = true,
				default = 500,
				sType = "slider",
			},
			{
				var = "chatChannelHistoryMaxViewLines",
				text = L["CH_OPTION_MAX_VIEW"],
				parentCheck = function()
					return addon.SettingsLayout.elements["enableChatHistory"]
						and addon.SettingsLayout.elements["enableChatHistory"].setting
						and addon.SettingsLayout.elements["enableChatHistory"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.chatChannelHistoryMaxViewLines or 1000 end,
				set = function(value)
					addon.db["chatChannelHistoryMaxViewLines"] = value
					if addon.ChatIM and addon.ChatIM.ChannelHistory and addon.ChatIM.ChannelHistory.SetUILineLimit then addon.ChatIM.ChannelHistory:SetUILineLimit(value) end
				end,
				min = 100,
				max = 2000,
				step = 50,
				parent = true,
				default = 1000,
				sType = "slider",
			},
			{
				var = "chatHistoryRestoreOnLogin",
				text = L["CH_OPTION_RESTORE_LOGIN"],
				desc = L["CH_OPTION_RESTORE_LOGIN_DESC"],
				parentCheck = function()
					return addon.SettingsLayout.elements["enableChatHistory"]
						and addon.SettingsLayout.elements["enableChatHistory"].setting
						and addon.SettingsLayout.elements["enableChatHistory"].setting:GetValue() == true
				end,
				func = function(val) addon.db.chatHistoryRestoreOnLogin = val and true or false end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
			},
			{
				var = "chatChannelHistoryFontSize",
				text = L["CH_OPTION_FONT"],
				desc = L["CH_OPTION_FONT_DESC"],
				parentCheck = function()
					return addon.SettingsLayout.elements["enableChatHistory"]
						and addon.SettingsLayout.elements["enableChatHistory"].setting
						and addon.SettingsLayout.elements["enableChatHistory"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.chatChannelHistoryFontSize or 12 end,
				set = function(value)
					addon.db["chatChannelHistoryFontSize"] = value
					if addon.ChatIM and addon.ChatIM.ChannelHistory and addon.ChatIM.ChannelHistory.UpdateLogFontSize then addon.ChatIM.ChannelHistory:UpdateLogFontSize(value) end
				end,
				min = 8,
				max = 20,
				step = 1,
				parent = true,
				default = 12,
				sType = "slider",
			},
			{
				var = "chatHistoryFrameStrata",
				text = L["CH_OPTION_FRAME_STRATA"],
				desc = L["CH_OPTION_FRAME_STRATA_DESC"],
				parentCheck = function()
					return addon.SettingsLayout.elements["enableChatHistory"]
						and addon.SettingsLayout.elements["enableChatHistory"].setting
						and addon.SettingsLayout.elements["enableChatHistory"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.chatHistoryFrameStrata or "MEDIUM" end,
				set = function(value)
					addon.db.chatHistoryFrameStrata = value or "MEDIUM"
					if addon.ChatIM and addon.ChatIM.ChannelHistory and addon.ChatIM.ChannelHistory.SetFrameStrata then addon.ChatIM.ChannelHistory:SetFrameStrata(value) end
				end,
				list = chatHistoryStrataOptions,
				parent = true,
				default = "MEDIUM",
				sType = "dropdown",
				type = Settings.VarType.String,
				order = strataOrder,
			},
			{
				var = "chatHistoryFrameLevel",
				text = L["CH_OPTION_FRAME_LEVEL"],
				desc = L["CH_OPTION_FRAME_LEVEL_DESC"],
				parentCheck = function()
					return addon.SettingsLayout.elements["enableChatHistory"]
						and addon.SettingsLayout.elements["enableChatHistory"].setting
						and addon.SettingsLayout.elements["enableChatHistory"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.chatHistoryFrameLevel or 600 end,
				set = function(value)
					local lvl = tonumber(value) or 600
					addon.db.chatHistoryFrameLevel = lvl
					if addon.ChatIM and addon.ChatIM.ChannelHistory and addon.ChatIM.ChannelHistory.SetFrameLevel then addon.ChatIM.ChannelHistory:SetFrameLevel(lvl) end
				end,
				min = 1,
				max = 1000,
				step = 1,
				parent = true,
				default = 600,
				sType = "slider",
			},
			{
				var = "chatHistoryButtonOffsetX",
				text = "History button offset X",
				desc = "Adjust horizontal offset of the Chat History toggle button relative to Quick Join.",
				parentCheck = function()
					return addon.SettingsLayout.elements["enableChatHistory"]
						and addon.SettingsLayout.elements["enableChatHistory"].setting
						and addon.SettingsLayout.elements["enableChatHistory"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.chatHistoryButtonOffsetX or 0 end,
				set = function(value)
					addon.db.chatHistoryButtonOffsetX = value or 0
					if addon.ChatIM and addon.ChatIM.ChannelHistory and addon.ChatIM.ChannelHistory.UpdateToggleButtonPosition then addon.ChatIM.ChannelHistory:UpdateToggleButtonPosition() end
				end,
				min = -200,
				max = 200,
				step = 1,
				parent = true,
				default = 0,
				sType = "slider",
			},
			{
				var = "chatHistoryButtonOffsetY",
				text = "History button offset Y",
				desc = "Adjust vertical offset of the Chat History toggle button relative to Quick Join.",
				parentCheck = function()
					return addon.SettingsLayout.elements["enableChatHistory"]
						and addon.SettingsLayout.elements["enableChatHistory"].setting
						and addon.SettingsLayout.elements["enableChatHistory"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.chatHistoryButtonOffsetY or -10 end,
				set = function(value)
					addon.db.chatHistoryButtonOffsetY = value or 0
					if addon.ChatIM and addon.ChatIM.ChannelHistory and addon.ChatIM.ChannelHistory.UpdateToggleButtonPosition then addon.ChatIM.ChannelHistory:UpdateToggleButtonPosition() end
				end,
				min = -200,
				max = 200,
				step = 1,
				parent = true,
				default = -10,
				sType = "slider",
			},
			{
				var = "chatHistoryShowButton",
				text = "Show History toggle icon",
				desc = "Show a small icon below the Quick Join toast to open/close Chat History.",
				parentCheck = function()
					return addon.SettingsLayout.elements["enableChatHistory"]
						and addon.SettingsLayout.elements["enableChatHistory"].setting
						and addon.SettingsLayout.elements["enableChatHistory"].setting:GetValue() == true
				end,
				func = function(val)
					addon.db.chatHistoryShowButton = val and true or false
					if addon.ChatIM and addon.ChatIM.ChannelHistory and addon.ChatIM.ChannelHistory.EnsureToggleButton then addon.ChatIM.ChannelHistory:EnsureToggleButton() end
				end,
				parent = true,
				default = true,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
			},
			{
				var = "chatHistoryHideUnlogged",
				text = L["CH_OPTION_HIDE_UNLOGGED"],
				desc = L["CH_OPTION_HIDE_UNLOGGED_DESC"],
				parentCheck = function()
					return addon.SettingsLayout.elements["enableChatHistory"]
						and addon.SettingsLayout.elements["enableChatHistory"].setting
						and addon.SettingsLayout.elements["enableChatHistory"].setting:GetValue() == true
				end,
				func = function(val)
					addon.db.chatHistoryHideUnlogged = val and true or false
					if addon.ChatIM and addon.ChatIM.ChannelHistory and addon.ChatIM.ChannelHistory.CreateFilterUI then addon.ChatIM.ChannelHistory:CreateFilterUI() end
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
			},
			{
				var = "chatChannelHistoryLootQualities",
				text = L["CH_OPTION_LOOT_MIN_RARITY"],
				desc = L["CH_OPTION_LOOT_MIN_RARITY_DESC"],
				parentCheck = function()
					return addon.SettingsLayout.elements["enableChatHistory"]
						and addon.SettingsLayout.elements["enableChatHistory"].setting
						and addon.SettingsLayout.elements["enableChatHistory"].setting:GetValue() == true
				end,
				isSelectedFunc = function(key)
					local map = addon.db and addon.db.chatChannelHistoryLootQualities
					return map and map[key] or false
				end,
				setSelectedFunc = function(key, shouldSelect)
					addon.db.chatChannelHistoryLootQualities = addon.db.chatChannelHistoryLootQualities or {}
					addon.db.chatChannelHistoryLootQualities[key] = shouldSelect and true or false
					if addon.ChatIM and addon.ChatIM.ChannelHistory and addon.ChatIM.ChannelHistory.InvalidateLootQualityCache then addon.ChatIM.ChannelHistory:InvalidateLootQualityCache() end
				end,
				options = (function()
					local opts = {}
					for q = Enum.ItemQuality.Poor, Enum.ItemQuality.WoWToken do
						local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
						local prefix = color and color.hex or ""
						local suffix = color and "|r" or ""
						opts[#opts + 1] = { value = q, text = string.format("%s%s%s", prefix, _G["ITEM_QUALITY" .. q .. "_DESC"], suffix) }
					end
					return opts
				end)(),
				parent = true,
				default = {
					[Enum.ItemQuality.Poor] = true,
					[Enum.ItemQuality.Common] = true,
					[Enum.ItemQuality.Uncommon] = true,
					[Enum.ItemQuality.Rare] = true,
					[Enum.ItemQuality.Epic] = true,
					[Enum.ItemQuality.Legendary] = true,
					[Enum.ItemQuality.Artifact] = true,
					[Enum.ItemQuality.Heirloom] = true,
					[Enum.ItemQuality.WoWToken] = true,
				},
				sType = "multidropdown",
			},
			{
				var = "chatChannelFiltersEnable",
				text = L["CH_OPTION_FILTER_SELECTION"],
				desc = L["CH_OPTION_FILTER_SELECTION_DESC"],
				parentCheck = function()
					return addon.SettingsLayout.elements["enableChatHistory"]
						and addon.SettingsLayout.elements["enableChatHistory"].setting
						and addon.SettingsLayout.elements["enableChatHistory"].setting:GetValue() == true
				end,
				parent = true,
				sType = "multidropdown",
				options = categoryOptions,
				isSelectedFunc = function(key) return addon.db.chatChannelFiltersEnable[key] end,
				setSelectedFunc = function(key, shouldSelect)
					addon.db.chatChannelFiltersEnable[key] = shouldSelect and true or false
					if addon.ChatIM and addon.ChatIM.ChannelHistory then
						if addon.ChatIM.ChannelHistory.UpdateLoggingFilter then addon.ChatIM.ChannelHistory:UpdateLoggingFilter(key) end
						if addon.ChatIM.ChannelHistory.CreateFilterUI then addon.ChatIM.ChannelHistory:CreateFilterUI() end
					end
				end,
			},
		},
	},
}

addon.functions.SettingsCreateCheckboxes(cChatFrame, data)
----- REGION END

function addon.functions.initChatFrame()
	addon.db.chatChannelFiltersEnable = addon.db.chatChannelFiltersEnable or {}
	for _, opt in ipairs(CHAT_FILTER_OPTIONS) do
		table.insert(categoryOptions, { value = opt.key, text = opt.label })
		if addon.db.chatChannelFiltersEnable[opt.key] == nil then addon.db.chatChannelFiltersEnable[opt.key] = true end
	end
	if addon.ChatIM and addon.ChatIM.ChannelHistory then addon.ChatIM.ChannelHistory.filterOptions = addon.ChatIM.ChannelHistory.filterOptions or CHAT_FILTER_OPTIONS end
end

local eventHandlers = {}

local function registerEvents(frame)
	for event in pairs(eventHandlers) do
		frame:RegisterEvent(event)
	end
end

local function eventHandler(self, event, ...)
	if eventHandlers[event] then eventHandlers[event](...) end
end

local frameLoad = CreateFrame("Frame")

registerEvents(frameLoad)
frameLoad:SetScript("OnEvent", eventHandler)
