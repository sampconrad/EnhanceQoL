-- luacheck: globals EnhanceQoL GetBindLocation GAMEMENU_OPTIONS FONT_SIZE UIParent NORMAL_FONT_COLOR C_Timer UNKNOWN C_Item GetItemInfoInstant GetItemIcon
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream

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
	addon.db.datapanel.hearthstone = addon.db.datapanel.hearthstone or {}
	db = addon.db.datapanel.hearthstone
	db.fontSize = db.fontSize or 14
	if db.hideIcon == nil then db.hideIcon = false end
	if not db.textColor then
		local r, g, b = 1, 0.82, 0
		if NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.GetRGB then
			r, g, b = NORMAL_FONT_COLOR:GetRGB()
		end
		db.textColor = { r = r, g = g, b = b }
	end
end

local function RestorePosition(frame)
	if not db then return end
	if db.point and db.x and db.y then
		frame:ClearAllPoints()
		frame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
	end
end

local aceWindow
local function createAceWindow()
	if aceWindow then
		aceWindow:Show()
		return
	end
	ensureDB()
	local frame = AceGUI:Create("Window")
	aceWindow = frame.frame
	frame:SetTitle((addon.DataPanel and addon.DataPanel.GetStreamOptionsTitle and addon.DataPanel.GetStreamOptionsTitle(stream and stream.meta and stream.meta.title)) or GAMEMENU_OPTIONS)
	frame:SetWidth(320)
	frame:SetHeight(240)
	frame:SetLayout("List")

	frame.frame:SetScript("OnShow", function(self) RestorePosition(self) end)
	frame.frame:SetScript("OnHide", function(self)
		local point, _, _, xOfs, yOfs = self:GetPoint()
		db.point = point
		db.x = xOfs
		db.y = yOfs
	end)

	local updateTimer
	local function scheduleUpdate()
		if updateTimer then updateTimer:Cancel() end
		updateTimer = C_Timer.NewTimer(0.05, function()
			updateTimer = nil
			if stream then addon.DataHub:RequestUpdate(stream) end
		end)
	end

	local fontSize = AceGUI:Create("Slider")
	fontSize:SetLabel(FONT_SIZE)
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		scheduleUpdate()
	end)
	frame:AddChild(fontSize)

	local hideIcon = AceGUI:Create("CheckBox")
	hideIcon:SetLabel(L["Hide icon"] or "Hide icon")
	hideIcon:SetValue(db.hideIcon)
	hideIcon:SetCallback("OnValueChanged", function(_, _, val)
		db.hideIcon = val and true or false
		scheduleUpdate()
	end)
	frame:AddChild(hideIcon)

	local textColor = AceGUI:Create("ColorPicker")
	textColor:SetLabel(L["Text color"] or "Text color")
	textColor:SetColor(db.textColor.r, db.textColor.g, db.textColor.b)
	textColor:SetCallback("OnValueChanged", function(_, _, r, g, b)
		db.textColor = { r = r, g = g, b = b }
		scheduleUpdate()
	end)
	frame:AddChild(textColor)

	frame.frame:Show()
end

local floor = math.floor
local function colorize(text)
	if not text or text == "" then return "" end
	local c = db and db.textColor
	local r = (c and c.r) or 1
	local g = (c and c.g) or 1
	local b = (c and c.b) or 1
	return ("|cff%02x%02x%02x%s|r"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5), text)
end

local HEARTHSTONE_ITEM_ID = 6948
local DEFAULT_HEARTHSTONE_ICON = 134414
local hearthstoneIcon
local function getHearthstoneIcon()
	if hearthstoneIcon then return hearthstoneIcon end
	if C_Item and C_Item.GetItemIconByID then
		hearthstoneIcon = C_Item.GetItemIconByID(HEARTHSTONE_ITEM_ID)
	end
	if not hearthstoneIcon and GetItemInfoInstant then
		local icon = select(5, GetItemInfoInstant(HEARTHSTONE_ITEM_ID))
		if icon then hearthstoneIcon = icon end
	end
	if not hearthstoneIcon and GetItemIcon then
		hearthstoneIcon = GetItemIcon(HEARTHSTONE_ITEM_ID)
	end
	if not hearthstoneIcon then hearthstoneIcon = DEFAULT_HEARTHSTONE_ICON end
	return hearthstoneIcon
end

local function updateHearthstone(s)
	s = s or stream
	ensureDB()

	local location = GetBindLocation and GetBindLocation() or ""
	if not location or location == "" then location = UNKNOWN or "Unknown" end
	local size = db.fontSize or 14
	local text = colorize(location)
	if not db.hideIcon then text = ("|T%d:%d:%d:0:0|t %s"):format(getHearthstoneIcon(), size, size, text) end

	s.snapshot.text = text
	s.snapshot.fontSize = size

	local tooltip = (L["Hearthstone"] or "Hearthstone") .. ": " .. location
	local hint = getOptionsHint()
	if hint then tooltip = tooltip .. "\n" .. hint end
	s.snapshot.tooltip = tooltip
end

local provider = {
	id = "hearthstone",
	version = 1,
	title = L["Hearthstone"] or "Hearthstone",
	update = updateHearthstone,
	events = {
		HEARTHSTONE_BOUND = function(s) addon.DataHub:RequestUpdate(s) end,
		PLAYER_ENTERING_WORLD = function(s) addon.DataHub:RequestUpdate(s) end,
		PLAYER_LOGIN = function(s) addon.DataHub:RequestUpdate(s) end,
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
