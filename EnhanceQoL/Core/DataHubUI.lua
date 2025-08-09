local addonName, addon = ...
local DataHub = addon.DataHub

addon.DataHubUI = addon.DataHubUI or {}
local UI = addon.DataHubUI

UI.tabs = {}
UI.colWidth = {}

local menuFrame = CreateFrame("Frame", "EQOLDataHubRowMenu", UIParent, "UIDropDownMenuTemplate")

function UI:Create()
	if self.frame then return end
	local frame = CreateFrame("Frame", "EQOLDataHubFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(700, 400)
	frame:SetPoint("CENTER")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 5, 0)
	frame.title:SetText("DataHub")
	frame:SetScript("OnHide", function() self:DeactivateStream() end)

	local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	search:SetSize(200, 20)
	search:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -30)
	search:SetScript("OnTextChanged", function(box)
		SearchBoxTemplate_OnTextChanged(box)
		self:RefreshRows()
	end)
	self.searchBox = search

	local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	refresh:SetSize(60, 22)
	refresh:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -28)
	refresh:SetText("Refresh")
	refresh:SetScript("OnClick", function()
		if self.activeStreamName then DataHub:RequestUpdate(self.activeStreamName) end
	end)

	local export = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	export:SetSize(60, 22)
	export:SetPoint("RIGHT", refresh, "LEFT", -5, 0)
	export:SetText("Export")
	export:SetScript("OnClick", function()
		if not self.activeStreamName then return end
		local csv = DataHub:ExportCSV(self.activeStreamName)
		if csv and csv ~= "" then print(csv) end
	end)

	local settings = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	settings:SetSize(60, 22)
	settings:SetPoint("RIGHT", export, "LEFT", -5, 0)
	settings:SetText("Settings")
	settings:SetScript("OnClick", function()
		if self.provider and self.provider.actions and self.provider.actions.settings then self.provider.actions.settings(self.activeStreamName) end
	end)

	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
	header:SetPoint("TOPRIGHT", settings, "BOTTOMRIGHT", 0, -8)
	header:SetHeight(20)
	self.header = header

	local scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
	scrollBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 10)
	local scrollBar = CreateFrame("EventFrame", nil, scrollBox, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 1, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 1, 0)

	local view = CreateScrollBoxListLinearView()
	view:SetElementFactory(function(factory, elementData)
		factory("BUTTON", function(button, elementData) self:InitRow(button, elementData) end)
	end)
	view:SetElementExtent(20)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	local dp = CreateDataProvider()
	scrollBox:SetDataProvider(dp)
	self.scrollBox = scrollBox
	self.scrollBar = scrollBar
	self.view = view
	self.frame = frame

	self:RefreshTabs()
end

function UI:RefreshTabs()
	if not self.frame then return end
	for _, tab in ipairs(self.tabs) do
		tab:Hide()
	end
	table.wipe(self.tabs)
	local names = {}
	for name in pairs(DataHub.streams) do
		names[#names + 1] = name
	end
	table.sort(names, function(a, b)
		local sa = DataHub.streams[a].title or a
		local sb = DataHub.streams[b].title or b
		return sa < sb
	end)
	for i, name in ipairs(names) do
		local stream = DataHub.streams[name]
		local tab = CreateFrame("Button", self.frame:GetName() .. "Tab" .. i, self.frame, "TabButtonTemplate")
		tab:SetText(stream.title or name)
		tab:SetID(i)
		tab.streamName = name
		tab:SetScript("OnClick", function(btn) self:SelectTab(btn) end)
		tab:ClearAllPoints()
		if i == 1 then
			tab:SetPoint("BOTTOMLEFT", self.frame, "TOPLEFT", 20, 0)
		else
			tab:SetPoint("LEFT", self.tabs[i - 1], "RIGHT", -15, 0)
		end
		PanelTemplates_TabResize(tab, 0)
		PanelTemplates_DeselectTab(tab)
		self.tabs[i] = tab
	end
	PanelTemplates_SetNumTabs(self.frame, #self.tabs)
	if self.tabs[1] then self:SelectTab(self.tabs[1]) end
end

function UI:SelectTab(tab)
	PanelTemplates_SetTab(self.frame, tab:GetID())
	self:ActivateStream(tab.streamName)
end

function UI:BuildHeader()
	if not self.provider then return end
	local cols = self.provider.columns or {}
	for _, fs in ipairs(self.header.cols or {}) do
		fs:Hide()
	end
	self.header.cols = {}
	local total = self.header:GetWidth()
	if total <= 0 then total = self.frame:GetWidth() - 40 end
	local width = total / #cols
	wipe(self.colWidth)
	local x = 0
	for i, col in ipairs(cols) do
		local fs = self.header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("LEFT", self.header, "LEFT", x + 4, 0)
		fs:SetWidth(width - 8)
		fs:SetJustifyH("LEFT")
		fs:SetText(col.title or col.key)
		self.header.cols[i] = fs
		self.colWidth[i] = width
		x = x + width
	end
end

function UI:InitRow(button, row)
	button:SetHeight(20)
	button.data = row
	if not button.cols then
		button.cols = {}
		local offset = 0
		for i, col in ipairs(self.provider.columns or {}) do
			local fs = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetPoint("LEFT", button, "LEFT", offset + 4, 0)
			fs:SetWidth((self.colWidth[i] or 100) - 8)
			fs:SetJustifyH("LEFT")
			button.cols[i] = fs
			offset = offset + (self.colWidth[i] or 100)
		end
		button:SetScript("OnMouseUp", function(btn, mouseButton)
			if mouseButton == "RightButton" then self:ShowRowMenu(btn.data) end
		end)
	end
	for i, col in ipairs(self.provider.columns or {}) do
		local v = row[col.key]
		button.cols[i]:SetText(v ~= nil and tostring(v) or "")
	end
end

function UI:ShowRowMenu(row)
	local actions = self.provider and self.provider.actions
	if not actions then return end
	local menu = {}
	for label, func in pairs(actions) do
		menu[#menu + 1] = { text = label, func = function() func(row, self.activeStreamName) end }
	end
	if #menu > 0 then EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU") end
end

function UI:OnSnapshotUpdate(snapshot)
	self.snapshot = snapshot
	self:RefreshRows()
end

function UI:RefreshRows()
	if not self.activeStreamName then return end
	local snapshot = self.snapshot or DataHub:GetSnapshot(self.activeStreamName) or {}
	local query = self.searchBox:GetText()
	local filter = self.provider and self.provider.filter
	local dp = self.scrollBox:GetDataProvider()
	dp:Flush()
	for _, row in ipairs(snapshot) do
		local ok = true
		if filter then ok = filter(row, query) ~= false end
		if ok then dp:Insert(row) end
	end
	if self.scrollBox.FullUpdate then
		if ScrollBoxConstants and ScrollBoxConstants.UpdateImmediately then
			self.scrollBox:FullUpdate(ScrollBoxConstants.UpdateImmediately)
		else
			self.scrollBox:FullUpdate()
		end
	end
end

function UI:ActivateStream(name)
	self:DeactivateStream()
	self.activeStreamName = name
	self.provider = DataHub.streams[name]
	if not self.provider then return end
	self:BuildHeader()
	local dp = self.scrollBox:GetDataProvider()
	dp:Flush()
	self.unsubscribe = DataHub:Subscribe(name, function(snapshot) self:OnSnapshotUpdate(snapshot) end)
	DataHub:RequestUpdate(name)
end

function UI:DeactivateStream()
	if self.unsubscribe then self.unsubscribe() end
	self.unsubscribe = nil
	self.activeStreamName = nil
	self.provider = nil
	self.snapshot = nil
	local dp = self.scrollBox and self.scrollBox:GetDataProvider()
	if dp then dp:Flush() end
end

function UI:Toggle()
	if not self.frame then self:Create() end
	if self.frame:IsShown() then
		self.frame:Hide()
	else
		self.frame:Show()
		self:RefreshTabs()
	end
end

return UI
