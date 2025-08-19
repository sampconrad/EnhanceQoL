-- luacheck: globals EnhanceQoL GAMEMENU_OPTIONS C_CurrencyInfo C_Timer
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream

local updatePending = false
local function RequestUpdateDebounced()
	if updatePending then return end
	updatePending = true
	C_Timer.After(0.05, function()
		updatePending = false
		if stream then addon.DataHub:RequestUpdate(stream) end
	end)
end

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.currency = addon.db.datapanel.currency or {}
	db = addon.db.datapanel.currency
	db.fontSize = db.fontSize or 14
	db.ids = db.ids or {}
end

local aceWindowWidget -- AceGUI widget
local listContainer

local function renderList()
	if not listContainer then return end
	listContainer:ReleaseChildren()

	for i, id in ipairs(db.ids) do
		local idx = i -- wichtig: stabiles Capturing pro Zeile
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
			if idx > 1 then
				db.ids[idx], db.ids[idx - 1] = db.ids[idx - 1], db.ids[idx]
				renderList()
				RequestUpdateDebounced()
			end
		end)
		row:AddChild(up)

		local down = AceGUI:Create("Button")
		down:SetText("↓")
		down:SetWidth(30)
		down:SetCallback("OnClick", function()
			if idx < #db.ids then
				db.ids[idx], db.ids[idx + 1] = db.ids[idx + 1], db.ids[idx]
				renderList()
				RequestUpdateDebounced()
			end
		end)
		row:AddChild(down)

		local remove = AceGUI:Create("Button")
		remove:SetText("X")
		remove:SetWidth(30)
		remove:SetCallback("OnClick", function()
			table.remove(db.ids, idx)
			renderList()
			RequestUpdateDebounced()
		end)
		row:AddChild(remove)

		listContainer:AddChild(row)
	end
end

local function createAceWindow()
	if aceWindowWidget then
		aceWindowWidget:Show()
		return
	end
	ensureDB()
	local frame = AceGUI:Create("Window")
	aceWindowWidget = frame
	frame:SetTitle(GAMEMENU_OPTIONS)
	frame:SetWidth(320)
	frame:SetHeight(400)
	frame:SetLayout("List")

	db._windowStatus = db._windowStatus or {}
	frame:SetStatusTable(db._windowStatus)
	frame:SetCallback("OnClose", function(widget)
		AceGUI:Release(widget)
		aceWindowWidget = nil
		listContainer = nil
	end)

	local fontSize = AceGUI:Create("Slider")
	fontSize:SetLabel("Font size")
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		RequestUpdateDebounced()
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
			for _, existing in ipairs(db.ids) do
				if existing == id then
					addBox:SetText("")
					return
				end
			end
			table.insert(db.ids, id)
			addBox:SetText("")
			renderList()
			RequestUpdateDebounced()
		end
	end)
	addGroup:AddChild(addBtn)
	frame:AddChild(addGroup)

	listContainer = addon.functions.createContainer("SimpleGroup", "List")
	frame:AddChild(listContainer)
	renderList()

	frame:Show()
end

local iconCache = {} -- [currencyID] = texturePath or fileID
local function checkCurrencies(stream)
	ensureDB()
	local size = db.fontSize or 14
	local parts = {}
	for _, id in ipairs(db.ids) do
		local info = C_CurrencyInfo.GetCurrencyInfo(id)
		if info then
			if not iconCache[id] and info.icon then iconCache[id] = info.icon end
			local icon = iconCache[id] or info.icon
			parts[#parts + 1] = ("|T%s:%d:%d:0:0|t %d"):format(icon or 0, size, size, info.quantity or 0)
		end
	end

	local newText = table.concat(parts, " ")
	if stream.snapshot.text ~= newText or stream.snapshot.fontSize ~= size then
		stream.snapshot.text = newText
		stream.snapshot.fontSize = size
	end
	if not stream.snapshot.tooltip then stream.snapshot.tooltip = L["Right-Click for options"] end
end

local provider = {
	id = "currency",
	version = 1,
	title = "Currencies",
	update = checkCurrencies,
	events = {
		PLAYER_LOGIN = function() RequestUpdateDebounced() end,
		CURRENCY_DISPLAY_UPDATE = function() RequestUpdateDebounced() end,
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
