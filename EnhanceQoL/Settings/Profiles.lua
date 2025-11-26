local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local cProfiles = addon.functions.SettingsCreateCategory(nil, L["Profiles"], nil, "Profiles")
addon.SettingsLayout.chatframeCategory = cProfiles

-- Build a sorted dropdown list, optionally keeping an empty entry pinned to the top
local function buildSortedProfileList(excludeFunc, includeEmpty)
	local list, order = {}, {}

	if includeEmpty then
		list[""] = ""
		table.insert(order, "")
	end

	local entries = {}
	for name in pairs(EnhanceQoLDB.profiles) do
		if not excludeFunc or not excludeFunc(name) then table.insert(entries, name) end
	end

	table.sort(entries, function(a, b)
		local la, lb = string.lower(a), string.lower(b)
		if la == lb then return a < b end
		return la < lb
	end)
	for _, name in ipairs(entries) do
		list[name] = name
		table.insert(order, name)
	end

	list._order = order
	return list
end

local data = {
	listFunc = function() return buildSortedProfileList() end,
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

data = {
	listFunc = function() return buildSortedProfileList() end,
	text = L["ProfileUseGlobal"],
	get = function() return EnhanceQoLDB.profileGlobal end,
	set = function(value) EnhanceQoLDB.profileGlobal = value end,
	default = "",
	var = "profilefirststart",
}

addon.functions.SettingsCreateDropdown(cProfiles, data)
addon.functions.SettingsCreateText(cProfiles, L["ProfileUseGlobalDesc"])

data = {
	listFunc = function()
		local currentProfile = EnhanceQoLDB.profileKeys[UnitGUID("player")]
		return buildSortedProfileList(function(name) return name == currentProfile end, true)
	end,
	text = L["ProfileCopy"],
	get = function() return "" end,
	set = function(value)
		if value ~= "" then
			StaticPopupDialogs["EQOL_COPY_PROFILE"] = StaticPopupDialogs["EQOL_COPY_PROFILE"]
				or {
					text = "",
					button1 = YES,
					button2 = CANCEL,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
					OnAccept = function(self)
						local source = self.data
						if not source or source == "" then return end
						local target = EnhanceQoLDB.profileKeys[UnitGUID("player")]
						if not target then return end
						EnhanceQoLDB.profiles[target] = CopyTable(EnhanceQoLDB.profiles[source])
						C_UI.Reload()
					end,
				}
			StaticPopupDialogs["EQOL_COPY_PROFILE"].text = L["ProfileCopyDesc"]:format(value)
			StaticPopup_Show("EQOL_COPY_PROFILE", nil, nil, value)
		end
	end,
	default = "",
	var = "profilecopy",
}

addon.functions.SettingsCreateDropdown(cProfiles, data)

data = {
	listFunc = function()
		local currentProfile = EnhanceQoLDB.profileKeys[UnitGUID("player")]
		local globalProfile = EnhanceQoLDB.profileGlobal
		return buildSortedProfileList(function(name) return name == currentProfile or name == globalProfile end, true)
	end,
	text = L["ProfileDelete"],
	get = function() return "" end,
	set = function(value)
		if value ~= "" then
			StaticPopupDialogs["EQOL_DELETE_PROFILE"] = StaticPopupDialogs["EQOL_DELETE_PROFILE"]
				or {
					text = "",
					button1 = YES,
					button2 = CANCEL,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
					OnAccept = function(self)
						local profile = self.data
						if profile and profile ~= "" then EnhanceQoLDB.profiles[profile] = nil end
					end,
				}
			StaticPopupDialogs["EQOL_DELETE_PROFILE"].text = L["ProfileDeleteDesc"]:format(value)
			StaticPopup_Show("EQOL_DELETE_PROFILE", nil, nil, value)
		end
	end,
	desc = L["ProfileDeleteDesc2"],
	default = "",
	var = "profiledelete",
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
