local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local cProfiles = addon.functions.SettingsCreateCategory(nil, L["Profiles"], nil, "Profiles")
addon.SettingsLayout.chatframeCategory = cProfiles

local data = {
	listFunc = function()
		local list = {}
		for i in pairs(EnhanceQoLDB.profiles) do
			list[i] = i
		end
		table.sort(list)
		return list
	end,
	text = L["ProfileActive"],
	get = function() return EnhanceQoLDB.profileKeys[UnitGUID("player")] or EnhanceQoLDB.profileGlobal end,
	set = function(value)
		EnhanceQoLDB.profileKeys[UnitGUID("player")] = value
		addon.variables.requireReload = true
		addon.functions.checkReloadFrame()
	end,
	default = "",
	var = "profiledata",
}

addon.functions.SettingsCreateDropdown(cProfiles, data)

addon.functions.SettingsCreateText(cProfiles, "")

local data = {
	listFunc = function()
		local list = {}
		for i in pairs(EnhanceQoLDB.profiles) do
			list[i] = i
		end
		table.sort(list)
		return list
	end,
	text = L["ProfileUseGlobal"],
	desc = L["ProfileUseGlobalDesc"],
	get = function() return EnhanceQoLDB.profileDefaultFirstStart or EnhanceQoLDB.profileGlobal end,
	set = function(value) EnhanceQoLDB.profileDefaultFirstStart = value end,
	default = "",
	var = "profilefirststart",
}

addon.functions.SettingsCreateDropdown(cProfiles, data)

data = {
	var = "AddProfile",
	text = L["ProfileName"],
	func = function() StaticPopup_Show("EQOL_CREATE_PROFILE") end,
}
addon.functions.SettingsCreateButton(cProfiles, data)

----- REGION END
function addon.functions.initProfile()
	StaticPopupDialogs["EQOL_CREATE_PROFILE"] = StaticPopupDialogs["EQOL_CREATE_PROFILE"]
		or {
			text = L["ProfileName"],
			hasEditBox = true,
			button1 = OKAY,
			button2 = CANCEL,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
			OnShow = function(self, data)
				local editBox = self.editBox or self.GetEditBox and self:GetEditBox()
				if editBox then
					editBox:SetText(data or "")
					editBox:SetFocus()
					editBox:HighlightText()
				end
			end,
			OnAccept = function(self)
				local id = self:GetEditBox():GetText()
				if id and id ~= "" then
					if not EnhanceQoLDB.profiles[id] or type(EnhanceQoLDB.profiles[id]) ~= "table" then EnhanceQoLDB.profiles[id] = {} end
				end
			end,
		}
end
