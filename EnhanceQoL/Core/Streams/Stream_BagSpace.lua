-- luacheck: globals EnhanceQoL GAMEMENU_OPTIONS FONT_SIZE UIParent NORMAL_FONT_COLOR C_Timer Enum C_Container GetContainerNumSlots GetContainerNumFreeSlots
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
	addon.db.datapanel.bagspace = addon.db.datapanel.bagspace or {}
	db = addon.db.datapanel.bagspace
	db.fontSize = db.fontSize or 14
	db.displayMode = db.displayMode or "freeMax"
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
	frame:SetHeight(260)
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

	local display = AceGUI:Create("Dropdown")
	display:SetLabel(L["bagSpaceDisplay"] or "Bag space display")
	display:SetList({
		freeMax = L["bagSpaceDisplayFreeMax"] or "Free/Max",
		free = L["bagSpaceDisplayFree"] or "Free",
	})
	display:SetValue(db.displayMode)
	display:SetCallback("OnValueChanged", function(_, _, key)
		db.displayMode = key or "freeMax"
		scheduleUpdate()
	end)
	frame:AddChild(display)

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

local GetContainerNumSlotsFn = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetContainerNumFreeSlotsFn = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
local REAGENT_BAG = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local BAG_IDS = { 0, 1, 2, 3, 4, REAGENT_BAG }

local function getBagSpace()
	if not GetContainerNumSlotsFn or not GetContainerNumFreeSlotsFn then return 0, 0 end
	local free, total = 0, 0
	for _, bag in ipairs(BAG_IDS) do
		local slots = GetContainerNumSlotsFn(bag)
		if slots and slots > 0 then
			total = total + slots
			local freeSlots = GetContainerNumFreeSlotsFn(bag)
			if freeSlots and freeSlots > 0 then free = free + freeSlots end
		end
	end
	return free, total
end

local function updateBagSpace(s)
	s = s or stream
	ensureDB()

	local free, total = getBagSpace()
	local size = db.fontSize or 14
	local displayMode = db.displayMode or "freeMax"
	local text
	if displayMode == "free" then
		text = tostring(free)
	else
		text = ("%d/%d"):format(free, total)
	end
	text = colorize(text)
	if not db.hideIcon then text = ("|T%s:%d:%d:0:0|t %s"):format(BAG_ICON, size, size, text) end

	s.snapshot.text = text
	s.snapshot.fontSize = size

	local tooltip = (L["Bag Space"] or "Bag Space") .. ": " .. tostring(free) .. "/" .. tostring(total)
	local hint = getOptionsHint()
	if hint then tooltip = tooltip .. "\n" .. hint end
	s.snapshot.tooltip = tooltip
end

local provider = {
	id = "bagspace",
	version = 1,
	title = L["Bag Space"] or "Bag Space",
	update = updateBagSpace,
	events = {
		BAG_UPDATE_DELAYED = function(s) addon.DataHub:RequestUpdate(s) end,
		PLAYER_ENTERING_WORLD = function(s) addon.DataHub:RequestUpdate(s) end,
		PLAYER_LOGIN = function(s) addon.DataHub:RequestUpdate(s) end,
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
