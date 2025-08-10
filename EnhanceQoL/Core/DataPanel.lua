local addonName, addon = ...
addon.DataPanel = addon.DataPanel or {}
local DataPanel = addon.DataPanel
local DataHub = addon.DataHub

local panels = {}

local function ensureSettings(id)
	addon.db = addon.db or {}
	addon.db.dataPanels = addon.db.dataPanels or {}
	local info = addon.db.dataPanels[id]
	if not info then
		info = { point = "CENTER", x = 0, y = 0, width = 200, height = 20 }
		addon.db.dataPanels[id] = info
	end
	return info
end

local function savePosition(frame, id)
	local info = ensureSettings(id)
	info.point, _, _, info.x, info.y = frame:GetPoint()
	info.width = frame:GetWidth()
	info.height = frame:GetHeight()
end

function DataPanel.Create(id)
	if panels[id] then return panels[id] end
	local info = ensureSettings(id)
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
	frame:SetScript("OnSizeChanged", function(f) savePosition(f, id) end)
	frame:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0, 0, 0, 0.5)

	local panel = { frame = frame, id = id, streams = {}, order = {} }

	function panel:Refresh()
		local prev
		for _, name in ipairs(self.order) do
			local data = self.streams[name]
			local btn = data.button
			btn:ClearAllPoints()
			btn:SetWidth(data.text:GetStringWidth())
			if prev then
				btn:SetPoint("LEFT", prev, "RIGHT", 5, 0)
			else
				btn:SetPoint("LEFT", self.frame, "LEFT", 5, 0)
			end
			prev = btn
		end
	end

	function panel:AddStream(name)
		if self.streams[name] then return end
		local button = CreateFrame("Button", nil, self.frame)
		button:SetHeight(self.frame:GetHeight())
		local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		text:SetAllPoints()
		text:SetJustifyH("LEFT")
		local data = { button = button, text = text }
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
		button:SetScript("OnClick", function(b, ...)
			local s = b.slot
			if s.OnClick then s.OnClick(b, ...) end
		end)

		self.order[#self.order + 1] = name

		local function cb(payload)
			payload = payload or {}
			data.text:SetText(payload.text or "")
			data.tooltip = payload.tooltip
			data.OnMouseEnter = payload.OnMouseEnter
			data.OnMouseLeave = payload.OnMouseLeave
			data.OnClick = payload.OnClick
			self:Refresh()
		end

		data.unsub = DataHub:Subscribe(name, cb)
		self.streams[name] = data
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
	end

	panels[id] = panel
	return panel
end

SLASH_EQOLPANEL1 = "/eqolpanel"
SlashCmdList.EQOLPANEL = function(msg)
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	if cmd == "create" then
		local id, w, h = rest:match("^(%S+)%s*(%d*)%s*(%d*)")
		if id then
			local panel = DataPanel.Create(id)
			if w ~= "" and h ~= "" then panel.frame:SetSize(tonumber(w), tonumber(h)) end
		end
	elseif cmd == "add" then
		local id, stream = rest:match("^(%S+)%s+(%S+)$")
		if id and stream then
			local panel = DataPanel.Create(id)
			panel:AddStream(stream)
		end
	elseif cmd == "remove" then
		local id, stream = rest:match("^(%S+)%s+(%S+)$")
		if id and stream and panels[id] then panels[id]:RemoveStream(stream) end
	else
		print("/eqolpanel create <id> [width] [height]")
		print("/eqolpanel add <id> <stream>")
		print("/eqolpanel remove <id> <stream>")
	end
end

return DataPanel
