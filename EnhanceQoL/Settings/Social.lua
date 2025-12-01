local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local cSocial = addon.functions.SettingsCreateCategory(nil, L["Social"], nil, "Social")
addon.SettingsLayout.chatframeCategory = cSocial

local data = {
	{
		var = "blockDuelRequests",
		text = L["blockDuelRequests"],
		type = "CheckBox",
		func = function(value) addon.db["blockDuelRequests"] = value end,
	},
	{
		var = "blockPetBattleRequests",
		text = L["blockPetBattleRequests"],
		type = "CheckBox",
		func = function(value) addon.db["blockPetBattleRequests"] = value end,
	},
	{
		var = "blockPartyInvites",
		text = L["blockPartyInvites"],
		type = "CheckBox",
		func = function(value) addon.db["blockPartyInvites"] = value end,
	},
	{
		var = "enableIgnore",
		text = L["EnableAdvancedIgnore"],
		type = "CheckBox",
		func = function(value)
			addon.db["enableIgnore"] = value
			if addon.Ignore and addon.Ignore.SetEnabled then addon.Ignore:SetEnabled(value) end
		end,
		children = {
			{

				var = "ignoreAttachFriendsFrame",
				text = L["IgnoreAttachFriends"],
				desc = L["IgnoreAttachFriendsDesc"],
				func = function(v) addon.db["ignoreAttachFriendsFrame"] = v end,
				parentCheck = function()
					return addon.SettingsLayout.elements["enableIgnore"]
						and addon.SettingsLayout.elements["enableIgnore"].setting
						and addon.SettingsLayout.elements["enableIgnore"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
			},
			{

				var = "ignoreAnchorFriendsFrame",
				text = L["IgnoreAnchorFriends"],
				desc = L["IgnoreAnchorFriendsDesc"],
				func = function(v)
					addon.db["ignoreAnchorFriendsFrame"] = v
					if addon.Ignore and addon.Ignore.UpdateAnchor then addon.Ignore:UpdateAnchor() end
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["enableIgnore"]
						and addon.SettingsLayout.elements["enableIgnore"].setting
						and addon.SettingsLayout.elements["enableIgnore"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
			},
			{

				var = "ignoreTooltipNote",
				text = L["ignoreTooltipNote"],
				func = function(v) addon.db["ignoreTooltipNote"] = v end,
				parentCheck = function()
					return addon.SettingsLayout.elements["enableIgnore"]
						and addon.SettingsLayout.elements["enableIgnore"].setting
						and addon.SettingsLayout.elements["enableIgnore"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
			},
			{
				var = "ignoreTooltipMaxChars",
				text = L["IgnoreTooltipMaxChars"],
				parentCheck = function()
					return addon.SettingsLayout.elements["enableIgnore"]
						and addon.SettingsLayout.elements["enableIgnore"].setting
						and addon.SettingsLayout.elements["enableIgnore"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.ignoreTooltipMaxChars or 100 end,
				set = function(value) addon.db["ignoreTooltipMaxChars"] = value end,
				min = 20,
				max = 200,
				step = 1,
				parent = true,
				default = 100,
				sType = "slider",
			},
			{
				var = "IgnoreTooltipWordsPerLine",
				text = L["IgnoreTooltipWordsPerLine"],
				parentCheck = function()
					return addon.SettingsLayout.elements["enableIgnore"]
						and addon.SettingsLayout.elements["enableIgnore"].setting
						and addon.SettingsLayout.elements["enableIgnore"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.ignoreTooltipWordsPerLine or 10 end,
				set = function(value) addon.db["IgnoreTooltipWordsPerLine"] = value end,
				min = 1,
				max = 20,
				step = 1,
				parent = true,
				default = 10,
				sType = "slider",
			},
			{
				text = "|cffffd700" .. L["IgnoreDesc2"] .. "|r",
				sType = "hint",
			},
			{
				text = "",
				sType = "hint",
			},
		},
	},
	{
		var = "autoAcceptGroupInvite",
		text = L["autoAcceptGroupInvite"],
		type = "CheckBox",
		func = function(value) addon.db["autoAcceptGroupInvite"] = value end,
		children = {
			{

				var = "autoAcceptGroupInviteGuildOnly",
				text = L["autoAcceptGroupInviteGuildOnly"],
				func = function(v) addon.db["autoAcceptGroupInviteGuildOnly"] = v end,
				parentCheck = function()
					return addon.SettingsLayout.elements["autoAcceptGroupInvite"]
						and addon.SettingsLayout.elements["autoAcceptGroupInvite"].setting
						and addon.SettingsLayout.elements["autoAcceptGroupInvite"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
			},
			{

				var = "autoAcceptGroupInviteFriendOnly",
				text = L["autoAcceptGroupInviteFriendOnly"],
				func = function(v) addon.db["autoAcceptGroupInviteFriendOnly"] = v end,
				parentCheck = function()
					return addon.SettingsLayout.elements["autoAcceptGroupInvite"]
						and addon.SettingsLayout.elements["autoAcceptGroupInvite"].setting
						and addon.SettingsLayout.elements["autoAcceptGroupInvite"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
			},
		},
	},
	{
		var = "friendsListDecorEnabled",
		text = L["friendsListDecorEnabledLabel"],
		type = "CheckBox",
		func = function(value)
			addon.db["friendsListDecorEnabled"] = value
			if addon.FriendsListDecor and addon.FriendsListDecor.SetEnabled then addon.FriendsListDecor:SetEnabled(addon.db["friendsListDecorEnabled"]) end
		end,
		children = {
			{
				text = "|cffffd700" .. L["friendsListDecorEnabledDesc"] .. "|r",
				sType = "hint",
			},
			{
				var = "friendsListDecorShowLocation",
				text = L["friendsListDecorShowLocation"],
				func = function(v)
					addon.db["friendsListDecorShowLocation"] = v
					if addon.FriendsListDecor and addon.FriendsListDecor.Refresh then addon.FriendsListDecor:Refresh() end
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["friendsListDecorEnabled"]
						and addon.SettingsLayout.elements["friendsListDecorEnabled"].setting
						and addon.SettingsLayout.elements["friendsListDecorEnabled"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
			},
			{
				var = "friendsListDecorHideOwnRealm",
				text = L["friendsListDecorHideOwnRealm"],
				func = function(v)
					addon.db["friendsListDecorHideOwnRealm"] = v
					if addon.FriendsListDecor and addon.FriendsListDecor.Refresh then addon.FriendsListDecor:Refresh() end
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["friendsListDecorEnabled"]
						and addon.SettingsLayout.elements["friendsListDecorEnabled"].setting
						and addon.SettingsLayout.elements["friendsListDecorEnabled"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
			},
			{
				var = "friendsListDecorNameFontSize",
				text = L["friendsListDecorNameFontSize"],
				parentCheck = function()
					return addon.SettingsLayout.elements["friendsListDecorEnabled"]
						and addon.SettingsLayout.elements["friendsListDecorEnabled"].setting
						and addon.SettingsLayout.elements["friendsListDecorEnabled"].setting:GetValue() == true
				end,
				get = function() return addon.db and addon.db.friendsListDecorNameFontSize or 0 end,
				set = function(value)
					addon.db["friendsListDecorNameFontSize"] = value
					if addon.FriendsListDecor and addon.FriendsListDecor.Refresh then addon.FriendsListDecor:Refresh() end
				end,
				min = 0,
				max = 24,
				step = 1,
				parent = true,
				default = 0,
				sType = "slider",
			},
		},
	},
}

addon.functions.SettingsCreateCheckboxes(cSocial, data)

----- REGION END

function addon.functions.initSocial() end

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
