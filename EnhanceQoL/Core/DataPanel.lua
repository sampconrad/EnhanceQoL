local addonName, addon = ...
addon.DataPanel = addon.DataPanel or {}
local DataPanel = addon.DataPanel
local DataHub = addon.DataHub

local panels = {}

local function ensureSettings(id, name)
	id = tostring(id)
	addon.db = addon.db or {}
	addon.db.dataPanels = addon.db.dataPanels or {}
	local info = addon.db.dataPanels[id] or addon.db.dataPanels[tonumber(id)]
	if not info then
		info = {
			point = "CENTER",
			x = 0,
			y = 0,
			width = 200,
			height = 20,
			streams = {},
			streamSet = {},
			name = name or ("Panel " .. id),
		}
	else
		info.streams = info.streams or {}
		info.streamSet = info.streamSet or {}
		info.name = info.name or name or ("Panel " .. id)
	end

	addon.db.dataPanels[id] = info
	if addon.db.dataPanels[tonumber(id)] then addon.db.dataPanels[tonumber(id)] = nil end

	for _, n in ipairs(info.streams) do
		info.streamSet[n] = true
	end

	return info
end

local function round2(v) return math.floor(v * 100 + 0.5) / 100 end

local function savePosition(frame, id)
	id = tostring(id)
	local info = ensureSettings(id)
	info.point, _, _, info.x, info.y = frame:GetPoint()
	info.width = round2(frame:GetWidth())
	info.height = round2(frame:GetHeight())
end

function DataPanel.Create(id, name)
	addon.db = addon.db or {}
	addon.db.dataPanels = addon.db.dataPanels or {}
	if not addon.db.nextPanelId then
		addon.db.nextPanelId = 1
		for k in pairs(addon.db.dataPanels) do
			local num = tonumber(k)
			if num and num >= addon.db.nextPanelId then addon.db.nextPanelId = num + 1 end
		end
	end
	if not id then
		id = tostring(addon.db.nextPanelId)
		addon.db.nextPanelId = addon.db.nextPanelId + 1
	else
		id = tostring(id)
	end
	if panels[id] then return panels[id] end
	local info = ensureSettings(id, name)
	local frame = CreateFrame("Frame", addonName .. "DataPanel" .. id, UIParent, "BackdropTemplate")
	frame:SetSize(info.width, info.height)
	frame:SetPoint(info.point, info.x, info.y)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		savePosition(f, id)
	end)
	frame:SetScript("OnMouseDown", function(f, btn)
		if btn == "RightButton" then f:StartSizing("BOTTOMRIGHT") end
	end)
	frame:SetScript("OnMouseUp", function(f, btn)
		if btn == "RightButton" then
			f:StopMovingOrSizing()
			savePosition(f, id)
		end
	end)

	local panel = { frame = frame, id = id, name = info.name, streams = {}, order = {}, info = info }

	frame:SetScript("OnSizeChanged", function(f)
		savePosition(f, id)
		for _, data in pairs(panel.streams) do
			data.button:SetHeight(f:GetHeight())
		end
	end)

	frame:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0, 0, 0, 0.5)

	function panel:Refresh()
		local changed = false
		if not self.lastOrder or #self.lastOrder ~= #self.order then
			changed = true
		else
			for i, name in ipairs(self.order) do
				if self.lastOrder[i] ~= name or (self.lastWidths and self.lastWidths[name] ~= self.streams[name].lastWidth) then
					changed = true
					break
				end
			end
		end
		if not changed then return end

		local prev
		for _, name in ipairs(self.order) do
			local data = self.streams[name]
			local btn = data.button
			btn:ClearAllPoints()
			btn:SetWidth(data.lastWidth)
			if prev then
				btn:SetPoint("LEFT", prev, "RIGHT", 5, 0)
			else
				btn:SetPoint("LEFT", self.frame, "LEFT", 5, 0)
			end
			prev = btn
		end

		self.lastOrder = {}
		self.lastWidths = {}
		for i, name in ipairs(self.order) do
			self.lastOrder[i] = name
			self.lastWidths[name] = self.streams[name].lastWidth
		end
	end

	function panel:AddStream(name)
		if self.streams[name] then return end
		local button = CreateFrame("Button", nil, self.frame)
		button:SetHeight(self.frame:GetHeight())
		local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		text:SetAllPoints()
		text:SetJustifyH("LEFT")
		local data = { button = button, text = text, lastWidth = text:GetStringWidth(), lastText = "" }
		button.slot = data
		button:SetScript("OnEnter", function(b)
			local s = b.slot
			if s.tooltip then
				GameTooltip:SetOwner(b, "ANCHOR_TOPLEFT")
				GameTooltip:SetText(s.tooltip)
				GameTooltip:Show()
			end
			if s.OnMouseEnter then s.OnMouseEnter(b) end
		end)
		button:SetScript("OnLeave", function(b)
			local s = b.slot
			if s.OnMouseLeave then s.OnMouseLeave(b) end
			GameTooltip:Hide()
		end)
		button:RegisterForClicks("AnyUp")
		button:SetScript("OnClick", function(b, btn, ...)
			local s = b.slot
			local fn = s.OnClick
			if type(fn) == "table" then fn = fn[btn] end
			if fn then fn(b, btn, ...) end
		end)

		self.order[#self.order + 1] = name

		local function cb(payload)
			payload = payload or {}
			local text = payload.text or ""
			if text ~= data.lastText then
				data.text:SetText(text)
				data.lastText = text
				local width = data.text:GetStringWidth()
				if width ~= data.lastWidth then
					data.lastWidth = width
					self:Refresh()
				end
			end
			if payload.fontSize and data.fontSize ~= payload.fontSize then
				local font = (addon.variables and addon.variables.defaultFont) or select(1, data.text:GetFont())
				data.text:SetFont(font, payload.fontSize, "OUTLINE")
				data.fontSize = payload.fontSize
				local width = data.text:GetStringWidth()
				if width ~= data.lastWidth then
					data.lastWidth = width
					self:Refresh()
				end
			end
			data.tooltip = payload.tooltip
			data.OnMouseEnter = payload.OnMouseEnter
			data.OnMouseLeave = payload.OnMouseLeave
			if payload.OnClick ~= nil then data.OnClick = payload.OnClick end
		end

		data.unsub = DataHub:Subscribe(name, cb)
		self.streams[name] = data

		local streams = self.info.streams
		local streamSet = self.info.streamSet
		if not streamSet[name] then
			streamSet[name] = true
			streams[#streams + 1] = name
		end
	end

	function panel:RemoveStream(name)
		local info = self.streams[name]
		if not info then return end
		if info.unsub then info.unsub() end
		info.button:Hide()
		info.button:SetParent(nil)
		self.streams[name] = nil
		for i, n in ipairs(self.order) do
			if n == name then
				table.remove(self.order, i)
				break
			end
		end
		self:Refresh()

		local streams = self.info.streams
		local streamSet = self.info.streamSet
		if streamSet[name] then
			streamSet[name] = nil
			for i, s in ipairs(streams) do
				if s == name then
					table.remove(streams, i)
					break
				end
			end
		end
	end

	panels[id] = panel

	if info.streams then
		for _, name in ipairs(info.streams) do
			panel:AddStream(name)
		end
	end

	return panel
end

function DataPanel.Get(id)
	id = tostring(id)
	return panels[id]
end

function DataPanel.AddStream(id, name)
	id = tostring(id)
	local panel = DataPanel.Create(id)
	panel:AddStream(name)
end

function DataPanel.RemoveStream(id, name)
	id = tostring(id)
	local panel = panels[id]
	if panel then panel:RemoveStream(name) end
end

function DataPanel.Move(id, point, x, y)
	id = tostring(id)
	local panel = panels[id]
	if panel then
		panel.frame:ClearAllPoints()
		panel.frame:SetPoint(point, x, y)
		savePosition(panel.frame, id)
	end
end

function DataPanel.List()
	addon.db = addon.db or {}
	addon.db.dataPanels = addon.db.dataPanels or {}
	local result = {}
	for id, info in pairs(addon.db.dataPanels) do
		id = tostring(id)
		local entry = { list = {}, set = {} }
		result[id] = entry
		if info.streams then
			for _, stream in ipairs(info.streams) do
				if not entry.set[stream] then
					entry.set[stream] = true
					entry.list[#entry.list + 1] = stream
				end
			end
		end
	end
	for id, panel in pairs(panels) do
		id = tostring(id)
		local entry = result[id]
		if not entry then
			entry = { list = {}, set = {} }
			result[id] = entry
		end
		for _, stream in ipairs(panel.order) do
			if not entry.set[stream] then
				entry.set[stream] = true
				entry.list[#entry.list + 1] = stream
			end
		end
	end
	for id, info in pairs(result) do
		result[id] = info.list
	end
	return result
end

function DataPanel.Delete(id)
	id = tostring(id)
	local panel = panels[id] or panels[tonumber(id)]
	if panel then
		for i = #panel.order, 1, -1 do
			panel:RemoveStream(panel.order[i])
		end
		panel.frame:Hide()
		panel.frame:SetParent(nil)
		panels[id] = nil
		if panels[tonumber(id)] then panels[tonumber(id)] = nil end
	end
	if addon.db and addon.db.dataPanels then
		addon.db.dataPanels[id] = nil
		if addon.db.dataPanels[tonumber(id)] then addon.db.dataPanels[tonumber(id)] = nil end
	end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
	addon.db = addon.db or {}
	local panelsDB = addon.db.dataPanels or {}
	addon.db.dataPanels = panelsDB

	for id in pairs(panelsDB) do
		DataPanel.Create(id)
	end

	self:UnregisterEvent("PLAYER_LOGIN")
end)

return DataPanel
