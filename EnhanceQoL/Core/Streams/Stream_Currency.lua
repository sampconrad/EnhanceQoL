-- luacheck: globals EnhanceQoL GAMEMENU_OPTIONS C_CurrencyInfo
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.currency = addon.db.datapanel.currency or {}
	db = addon.db.datapanel.currency
	db.fontSize = db.fontSize or 14
	db.ids = db.ids or {}
end

local function RestorePosition(frame)
	if db.point and db.x and db.y then
		frame:ClearAllPoints()
		frame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
	end
end

local aceWindow
local listContainer

local function renderList()
	if not listContainer then return end
	listContainer:ReleaseChildren()
	for i, id in ipairs(db.ids) do
		local info = C_CurrencyInfo.GetCurrencyInfo(id)
		local name = info and info.name or ("ID %d"):format(id)
		local row = addon.functions.createContainer("SimpleGroup", "Flow")

		local label = AceGUI:Create("Label")
		label:SetText(("%s (%d)"):format(name, id))
		label:SetWidth(160)
		row:AddChild(label)

		local up = AceGUI:Create("Button")
		up:SetText("↑")
		up:SetWidth(30)
		up:SetCallback("OnClick", function()
			if i > 1 then
				db.ids[i], db.ids[i - 1] = db.ids[i - 1], db.ids[i]
				renderList()
				addon.DataHub:RequestUpdate(stream)
			end
		end)
		row:AddChild(up)

		local down = AceGUI:Create("Button")
		down:SetText("↓")
		down:SetWidth(30)
		down:SetCallback("OnClick", function()
			if i < #db.ids then
				db.ids[i], db.ids[i + 1] = db.ids[i + 1], db.ids[i]
				renderList()
				addon.DataHub:RequestUpdate(stream)
			end
		end)
		row:AddChild(down)

		local remove = AceGUI:Create("Button")
		remove:SetText("X")
		remove:SetWidth(30)
		remove:SetCallback("OnClick", function()
			table.remove(db.ids, i)
			renderList()
			addon.DataHub:RequestUpdate(stream)
		end)
		row:AddChild(remove)

		listContainer:AddChild(row)
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
	frame:SetTitle(GAMEMENU_OPTIONS)
	frame:SetWidth(320)
	frame:SetHeight(400)
	frame:SetLayout("List")

	frame.frame:SetScript("OnShow", function(self) RestorePosition(self) end)
	frame.frame:SetScript("OnHide", function(self)
		local point, _, _, xOfs, yOfs = self:GetPoint()
		db.point = point
		db.x = xOfs
		db.y = yOfs
	end)

	local fontSize = AceGUI:Create("Slider")
	fontSize:SetLabel("Font size")
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(fontSize)

	local addGroup = addon.functions.createContainer("SimpleGroup", "Flow")
	local addBox = AceGUI:Create("EditBox")
	addBox:SetLabel("Currency ID")
	addBox:SetWidth(150)
	addGroup:AddChild(addBox)
	local addBtn = AceGUI:Create("Button")
	addBtn:SetText("Add")
	addBtn:SetWidth(60)
	addBtn:SetCallback("OnClick", function()
		local id = tonumber(addBox:GetText())
		if id then
			table.insert(db.ids, id)
			addBox:SetText("")
			renderList()
			addon.DataHub:RequestUpdate(stream)
		end
	end)
	addGroup:AddChild(addBtn)
	frame:AddChild(addGroup)

	listContainer = addon.functions.createContainer("SimpleGroup", "List")
	frame:AddChild(listContainer)
	renderList()

	frame.frame:Show()
end

local function checkCurrencies(stream)
	ensureDB()
	local size = db.fontSize or 14
	local texts = {}
	for _, id in ipairs(db.ids) do
		local info = C_CurrencyInfo.GetCurrencyInfo(id)
		if info and info.icon then texts[#texts + 1] = ("|T%s:%d:%d:0:0|t %d"):format(info.icon, size, size, info.quantity or 0) end
	end
	stream.snapshot.fontSize = size
	stream.snapshot.text = table.concat(texts, " ")
	if not stream.snapshot.tooltip then stream.snapshot.tooltip = L["Right-Click for options"] end
end

local provider = {
	id = "currency",
	version = 1,
	title = "Currencies",
	update = checkCurrencies,
	events = {
		PLAYER_LOGIN = function(stream) addon.DataHub:RequestUpdate(stream) end,
		CURRENCY_DISPLAY_UPDATE = function(stream) addon.DataHub:RequestUpdate(stream) end,
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
