-- luacheck: globals EnhanceQoL GetRealmName GAMEMENU_OPTIONS FONT_SIZE UIParent NORMAL_FONT_COLOR
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local cachedRealm
local stream
local aceWindow

local function getOptionsHint()
	if addon.DataPanel and addon.DataPanel.GetOptionsHintText then
		local text = addon.DataPanel.GetOptionsHintText()
		if text ~= nil then return text end
		return nil
	end
	return L["Right-Click for options"]
end

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.realm = addon.db.datapanel.realm or {}
	db = addon.db.datapanel.realm
	db.fontSize = db.fontSize or 14
	if not db.textColor then
		local r, g, b = 1, 0.82, 0
		if NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.GetRGB then
			r, g, b = NORMAL_FONT_COLOR:GetRGB()
		end
		db.textColor = { r = r, g = g, b = b }
	end
end

local function RestorePosition(frame)
	if db and db.point and db.x and db.y then
		frame:ClearAllPoints()
		frame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
	end
end

local function createAceWindow()
	if aceWindow then
		aceWindow:Show()
		return
	end
	ensureDB()
	local frame = AceGUI:Create("Window")
	aceWindow = frame.frame
	frame:SetTitle((addon.DataPanel and addon.DataPanel.GetStreamOptionsTitle and addon.DataPanel.GetStreamOptionsTitle(stream and stream.meta and stream.meta.title)) or GAMEMENU_OPTIONS)
	frame:SetWidth(300)
	frame:SetHeight(200)
	frame:SetLayout("List")

	frame.frame:SetScript("OnShow", function(self) RestorePosition(self) end)
	frame.frame:SetScript("OnHide", function(self)
		local point, _, _, xOfs, yOfs = self:GetPoint()
		db.point = point
		db.x = xOfs
		db.y = yOfs
	end)

	local fontSize = AceGUI:Create("Slider")
	fontSize:SetLabel(FONT_SIZE)
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(fontSize)

	local textColor = AceGUI:Create("ColorPicker")
	textColor:SetLabel(L["Text color"] or "Text color")
	textColor:SetColor(db.textColor.r, db.textColor.g, db.textColor.b)
	textColor:SetCallback("OnValueChanged", function(_, _, r, g, b)
		db.textColor = { r = r, g = g, b = b }
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(textColor)

	frame.frame:Show()
end

local function getRealm()
	if cachedRealm and cachedRealm ~= "" then return cachedRealm end
	local name = GetRealmName and GetRealmName() or ""
	if name and name ~= "" then cachedRealm = name end
	return name or ""
end

local function colorize(text, color)
	if not text or text == "" then return text end
	if color and color.r and color.g and color.b then return ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, text) end
	return text
end

local function updateRealm(s)
	s = s or stream
	if not s then return end
	ensureDB()
	s.snapshot.text = colorize(getRealm(), db.textColor)
	s.snapshot.fontSize = db.fontSize or 14
	s.snapshot.tooltip = getOptionsHint()
end

local provider = {
	id = "realm",
	version = 1,
	title = L["Realm"] or "Realm",
	update = updateRealm,
	events = {
		PLAYER_LOGIN = function(s) addon.DataHub:RequestUpdate(s) end,
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

hooksecurefunc(addon.DataHub, "Subscribe", function(_, name)
	if name ~= provider.id then return end
	if not stream then return end
	if stream.snapshot and stream.snapshot.text and stream.snapshot.text ~= "" then
		addon.DataHub:Publish(stream, stream.snapshot)
	else
		addon.DataHub:RequestUpdate(stream)
	end
end)

return provider
