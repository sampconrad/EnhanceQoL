local addonName, addon = ...
addon.DataPanel = addon.DataPanel or {}
local DataPanel = addon.DataPanel
local DataHub = addon.DataHub
local L = addon.L

local panels = {}

local function requireShiftToMove()
    local opts = addon.db and addon.db.dataPanelsOptions
    return opts and opts.requireShiftToMove == true
end

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
            noBorder = false,
        }
    else
        info.streams = info.streams or {}
        info.streamSet = info.streamSet or {}
        info.name = info.name or name or ("Panel " .. id)
        if info.noBorder == nil then info.noBorder = false end
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
	-- Do not recreate database entries when saving position.
	-- Only persist if the panel still exists in the DB.
	if not addon.db or not addon.db.dataPanels or not addon.db.dataPanels[id] then return end
	local info = addon.db.dataPanels[id]
	info.point, _, _, info.x, info.y = frame:GetPoint()
	info.width = round2(frame:GetWidth())
	info.height = round2(frame:GetHeight())
end

function DataPanel.Create(id, name, existingOnly)
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

	-- If we are asked to only use existing panels, do not implicitly
	-- create a new database entry for unknown IDs.
	if existingOnly and not addon.db.dataPanels[id] and not addon.db.dataPanels[tonumber(id)] then return nil end

    local info = ensureSettings(id, name)
    local frame = CreateFrame("Frame", addonName .. "DataPanel" .. id, UIParent, "BackdropTemplate")
    frame:SetSize(info.width, info.height)
    frame:SetPoint(info.point, info.x, info.y)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f)
        if requireShiftToMove() and not IsShiftKeyDown() then return end
        -- mark dragging and hide any open tooltip so it won't get in the way
        local panelObj = panels[id]
        if panelObj then panelObj.isDragging = true end
        GameTooltip:Hide()
        f:StartMoving()
    end)
	frame:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		savePosition(f, id)
		local panelObj = panels[id]
		if panelObj then panelObj.isDragging = nil end
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

    if not info.noBorder then
        frame:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.5)
    end

    function panel:ApplyBorder()
        local i = self.info
        if i and i.noBorder then
            self.frame:SetBackdrop(nil)
        else
            self.frame:SetBackdrop({
                bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                tile = true,
                tileSize = 16,
                edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            self.frame:SetBackdropColor(0, 0, 0, 0.5)
        end
    end

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
        -- allow dragging even when hovering stream buttons
        button:RegisterForDrag("LeftButton")
        button:SetScript("OnDragStart", function(b)
            if requireShiftToMove() and not IsShiftKeyDown() then return end
            local p = panels[id]
            if p and p.frame then
                p.isDragging = true
                GameTooltip:Hide()
                p.frame:StartMoving()
            end
        end)
		button:SetScript("OnDragStop", function(b)
			local p = panels[id]
			if p and p.frame then
				p.frame:StopMovingOrSizing()
				savePosition(p.frame, id)
				p.isDragging = nil
			end
		end)
		button:SetScript("OnEnter", function(b)
			local s = b.slot
			local p = panels[id]
			if p and p.isDragging then return end
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
			local p = panels[id]
			if p and p.isDragging then return end -- suppress clicks after a drag
			local s = b.slot
			local fn = s.OnClick
			if type(fn) == "table" then fn = fn[btn] end
			if fn then fn(b, btn, ...) end
		end)

		self.order[#self.order + 1] = name

		local function cb(payload)
			payload = payload or {}
			local font = (addon.variables and addon.variables.defaultFont) or select(1, data.text:GetFont())
			local size = payload.fontSize or data.fontSize or 14

			if payload.parts then
				data.text:SetText("")
				data.text:Hide()
				data.parts = data.parts or {}
				local prev
				local totalWidth = 0
				for i, part in ipairs(payload.parts) do
					local child = data.parts[i]
					if not child then
						child = CreateFrame("Button", nil, button)
						child.text = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
						child.text:SetAllPoints()
						child:RegisterForClicks("AnyUp")
						data.parts[i] = child
					end
					child:Show()
					child:SetHeight(button:GetHeight())
					child.text:SetFont(font, size, "OUTLINE")
					child.text:SetText(part.text or "")
					local w = child.text:GetStringWidth()
					child:SetWidth(w)
					child:ClearAllPoints()
					if prev then
						child:SetPoint("LEFT", prev, "RIGHT", 5, 0)
					else
						child:SetPoint("LEFT", button, "LEFT", 0, 0)
					end
					prev = child
					child.currencyID = part.id
					-- enable dragging from part segments too
					child:RegisterForDrag("LeftButton")
                child:SetScript("OnDragStart", function()
                    if requireShiftToMove() and not IsShiftKeyDown() then return end
                    local p = panels[id]
                    if p and p.frame then
                        p.isDragging = true
                        GameTooltip:Hide()
                        p.frame:StartMoving()
                    end
                end)
					child:SetScript("OnDragStop", function()
						local p = panels[id]
						if p and p.frame then
							p.frame:StopMovingOrSizing()
							savePosition(p.frame, id)
							p.isDragging = nil
						end
					end)
					child:SetScript("OnEnter", function(b)
						local p = panels[id]
						if p and p.isDragging then return end
						GameTooltip:SetOwner(b, "ANCHOR_TOPLEFT")
						if data.perCurrency and b.currencyID then
							GameTooltip:SetCurrencyByID(b.currencyID)
							if data.showDescription == false then
								local info = C_CurrencyInfo.GetCurrencyInfo(b.currencyID)
								if info and info.description and info.description ~= "" then
									local name = GameTooltip:GetName()
									for i = 2, GameTooltip:NumLines() do
										local line = _G[name .. "TextLeft" .. i]
										if line and line:GetText() == info.description then
											line:SetText("")
											break
										end
									end
								end
							end
							GameTooltip:AddLine(" ")
							GameTooltip:AddLine(L["Right-Click for options"])
						elseif data.tooltip then
							GameTooltip:SetText(data.tooltip)
						end
						GameTooltip:Show()
					end)
					child:SetScript("OnLeave", function() GameTooltip:Hide() end)
					child:SetScript("OnClick", function(_, btn, ...)
						local p = panels[id]
						if p and p.isDragging then return end
						local fn = data.OnClick
						if type(fn) == "table" then fn = fn[btn] end
						if fn then fn(_, btn, ...) end
					end)
					totalWidth = totalWidth + w + (i > 1 and 5 or 0)
				end
				if data.parts then
					for i = #payload.parts + 1, #data.parts do
						data.parts[i]:Hide()
					end
				end
				if totalWidth ~= data.lastWidth then
					data.lastWidth = totalWidth
					self:Refresh()
				end
			else
				if data.parts then
					for _, child in ipairs(data.parts) do
						child:Hide()
					end
				end
				data.text:Show()
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
			end

			local newSize = payload.fontSize or data.fontSize
			if newSize and data.fontSize ~= newSize then
				data.text:SetFont(font, newSize, "OUTLINE")
				data.fontSize = newSize
				if not payload.parts then
					local width = data.text:GetStringWidth()
					if width ~= data.lastWidth then
						data.lastWidth = width
						self:Refresh()
					end
				end
			end
			data.tooltip = payload.tooltip
			data.perCurrency = payload.perCurrency
			data.showDescription = payload.showDescription
			data.hover = payload.hover
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
	local panel = panels[id] or panels[tonumber(id)]
	if panel then panel:AddStream(name) end
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
	-- Always remove the database entry first so a partial failure in
	-- UI cleanup never re-saves an empty leftover panel on reload.
	if addon.db and addon.db.dataPanels then
		local named = panel and panel.name
		-- primary key cleanup
		addon.db.dataPanels[id] = nil
		if addon.db.dataPanels[tonumber(id)] then addon.db.dataPanels[tonumber(id)] = nil end
		-- defensive sweep: remove any entries that accidentally reference the same panel
		for k, info in pairs(addon.db.dataPanels) do
			if tostring(k) == id then
				addon.db.dataPanels[k] = nil
			elseif type(info) == "table" then
				if info.name == id or (named and info.name == named) then addon.db.dataPanels[k] = nil end
			end
		end
	end

	if panel then
		-- Unsubscribe and detach all streams safely
		for i = #panel.order, 1, -1 do
			local ok = pcall(function() panel:RemoveStream(panel.order[i]) end)
			if not ok then
				-- continue cleanup even if a single stream removal fails
			end
		end
		if panel.frame then
			-- Prevent savePosition from firing during teardown
			panel.frame:SetScript("OnSizeChanged", nil)
			panel.frame:Hide()
			panel.frame:SetParent(nil)
		end
		panels[id] = nil
		if panels[tonumber(id)] then panels[tonumber(id)] = nil end
	end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
	addon.db = addon.db or {}
	local panelsDB = addon.db.dataPanels or {}
	addon.db.dataPanels = panelsDB

	for id in pairs(panelsDB) do
		DataPanel.Create(id, nil, true)
	end

	self:UnregisterEvent("PLAYER_LOGIN")
end)

return DataPanel
