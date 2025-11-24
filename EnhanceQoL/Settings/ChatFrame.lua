local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local cChatFrame = addon.functions.SettingsCreateCategory(nil, HUD_EDIT_MODE_CHAT_FRAME_LABEL, nil, "ChatFrame")
addon.SettingsLayout.chatframeCategory = cChatFrame

addon.functions.SettingsCreateHeadline(cChatFrame, CHAT)

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
						listFunc = function()
							if addon.ChatIM and addon.ChatIM.BuildSoundTable and not addon.ChatIM.availableSounds then addon.ChatIM:BuildSoundTable() end
							local tList = { [""] = "" }
							for name in pairs(addon.ChatIM.availableSounds or {}) do
								tList[name] = name
							end
							return tList
						end,
						text = L["ChatIMCustomSound"],
						get = function() return addon.db.chatIMCustomSoundFile or "" end,
						set = function(key)
							addon.db.chatIMCustomSoundFile = key
							local file = addon.ChatIM.availableSounds and addon.ChatIM.availableSounds[key]
							if file then PlaySoundFile(file, "Master") end
						end,
						parentCheck = function()
							return addon.SettingsLayout.elements["chatIMUseCustomSound"]
								and addon.SettingsLayout.elements["chatIMUseCustomSound"].setting
								and addon.SettingsLayout.elements["chatIMUseCustomSound"].setting:GetValue() == true
								and addon.SettingsLayout.elements["enableChatIM"]
								and addon.SettingsLayout.elements["enableChatIM"].setting
								and addon.SettingsLayout.elements["enableChatIM"].setting:GetValue() == true
						end,
						parent = true,
						default = "",
						var = "chatIMCustomSoundFile",
						type = Settings.VarType.String,
						sType = "dropdown",
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
addon.functions.SettingsCreateDropdown(cChatFrame, data)

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
----- REGION END

function addon.functions.initChatFrame() end

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
