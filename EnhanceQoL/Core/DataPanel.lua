local addonName, addon = ...
addon.DataPanel = addon.DataPanel or {}
local DataPanel = addon.DataPanel
local DataHub = addon.DataHub
local L = addon.L
local EditMode = addon.EditMode
local SettingType = EditMode and EditMode.lib and EditMode.lib.SettingType

local registerEditModePanel

local panels = {}

local function copyList(source)
	local result = {}
	if source then
		for i, v in ipairs(source) do
			result[i] = v
		end
	end
	return result
end

local function streamDisplayName(name)
	local stream = DataHub and DataHub.streams and DataHub.streams[name]
	if stream and stream.meta then return stream.meta.title or stream.meta.name or name end
	return name
end

local function sortedStreams()
	local list = {}
	if DataHub and DataHub.streams then
		for name in pairs(DataHub.streams) do
			list[#list + 1] = name
		end
	end
	table.sort(list, function(a, b) return streamDisplayName(a) < streamDisplayName(b) end)
	return list
end

local function requireShiftToMove()
	local opts = addon.db and addon.db.dataPanelsOptions
	return opts and opts.requireShiftToMove == true
end

local function shouldShowOptionsHint()
	local opts = addon.db and addon.db.dataPanelsOptions
	return not (opts and opts.hideRightClickHint)
end

function DataPanel.ShouldShowOptionsHint() return shouldShowOptionsHint() end

function DataPanel.GetOptionsHintText()
	if shouldShowOptionsHint() then return L["Right-Click for options"] end
end

local function registerEditModePanel(panel)
	if not EditMode or not EditMode.RegisterFrame then return end
	if panel.editModeRegistered then
		if panel.editModeId then EditMode:RefreshFrame(panel.editModeId) end
		return
	end

	local id = "dataPanel:" .. tostring(panel.id)
	panel.frame.editModeName = panel.name

	local defaults = {
		point = panel.info.point or "CENTER",
		x = panel.info.x or 0,
		y = panel.info.y or 0,
		width = panel.info.width or panel.frame:GetWidth() or 200,
		height = panel.info.height or panel.frame:GetHeight() or 20,
		hideBorder = panel.info.noBorder or false,
		streams = copyList(panel.info.streams),
	}

	local settings
	if SettingType then
		settings = {
			{
				name = L["DataPanelWidth"],
				kind = SettingType.Slider,
				field = "width",
				default = defaults.width,
				minValue = 50,
				maxValue = 800,
				valueStep = 1,
			},
			{
				name = L["DataPanelHeight"],
				kind = SettingType.Slider,
				field = "height",
				default = defaults.height,
				minValue = 16,
				maxValue = 600,
				valueStep = 1,
			},
			{
				name = L["DataPanelHideBorder"],
				kind = SettingType.Checkbox,
				field = "hideBorder",
				default = defaults.hideBorder,
			},
			{
				name = L["DataPanelStreams"],
				kind = SettingType.Dropdown,
				field = "streams",
				default = copyList(defaults.streams),
				height = 240,
				get = function() return copyList(panel.info.streams) end,
				set = function(_, value)
					panel.applyingFromEditMode = true
					panel:ApplyStreams(copyList(value) or {})
					panel.applyingFromEditMode = nil
				end,
				generator = function(_, rootDescription)
					for _, streamName in ipairs(sortedStreams()) do
						rootDescription:CreateCheckbox(streamDisplayName(streamName), function() return panel.info.streamSet and panel.info.streamSet[streamName] end, function()
							local enabled = panel.info.streamSet and panel.info.streamSet[streamName]
							if enabled then
								panel:RemoveStream(streamName)
							else
								panel:AddStream(streamName)
							end
						end)
					end
				end,
			},
		}
	end

	EditMode:RegisterFrame(id, {
		frame = panel.frame,
		title = panel.name,
		layoutDefaults = defaults,
		onApply = function(_, _, data) panel:ApplyEditMode(data or {}) end,
		onPositionChanged = function(_, _, data) panel:UpdatePositionInfo(data) end,
		settings = settings,
		showOutsideEditMode = true,
	})
	panel.editModeRegistered = true
	panel.editModeId = id
end

function DataPanel.SetShowOptionsHint(val)
	addon.db = addon.db or {}
	addon.db.dataPanelsOptions = addon.db.dataPanelsOptions or {}
	if val then
		addon.db.dataPanelsOptions.hideRightClickHint = nil
	else
		addon.db.dataPanelsOptions.hideRightClickHint = true
	end
end

local function getMenuModifierSetting()
	local opts = addon.db and addon.db.dataPanelsOptions
	return (opts and opts.menuModifier) or "NONE"
end

local function isModifierDown(mod)
	if mod == "SHIFT" then
		return IsShiftKeyDown()
	elseif mod == "CTRL" then
		return IsControlKeyDown()
	elseif mod == "ALT" then
		return IsAltKeyDown()
	end
	return true
end

function DataPanel.GetMenuModifier() return getMenuModifierSetting() end

function DataPanel.SetMenuModifier(mod)
	addon.db = addon.db or {}
	addon.db.dataPanelsOptions = addon.db.dataPanelsOptions or {}
	if not mod or not (mod == "NONE" or mod == "SHIFT" or mod == "CTRL" or mod == "ALT") then mod = "NONE" end
	addon.db.dataPanelsOptions.menuModifier = mod
end

function DataPanel.IsMenuModifierActive(btn)
	if btn and btn ~= "RightButton" then return true end
	local mod = getMenuModifierSetting()
	if mod == "NONE" then return true end
	return isModifierDown(mod)
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
			name = name or ((L["Panel"] or "Panel") .. " " .. id),
			noBorder = false,
		}
	else
		info.streams = info.streams or {}
		info.streamSet = info.streamSet or {}
		info.name = info.name or name or ((L["Panel"] or "Panel") .. " " .. id)
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
	local panel = panels[id]
	if panel then
		panel:SyncEditModePosition(info.point, info.x, info.y)
		panel:SyncEditModeValue("width", info.width)
		panel:SyncEditModeValue("height", info.height)
	end
end

function DataPanel.Create(id, name, existingOnly)
	addon.db = addon.db or {}
	addon.db.dataPanels = addon.db.dataPanels or {}
	addon.db.dataPanelsOptions = addon.db.dataPanelsOptions or {}
	addon.db.dataPanelsOptions.menuModifier = addon.db.dataPanelsOptions.menuModifier or "NONE"
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
	frame:SetScript("OnMouseDown", nil)
	frame:SetScript("OnMouseUp", nil)

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
		self:SyncEditModeValue("hideBorder", i and i.noBorder or false)
	end

	function panel:SyncEditModeValue(field, value)
		if not EditMode or not self.editModeId or self.suspendEditSync or self.applyingFromEditMode then return end
		self.suspendEditSync = true
		if field == "width" or field == "height" or field == "hideBorder" or field == "streams" then EditMode:SetValue(self.editModeId, field, value) end
		self.suspendEditSync = nil
	end

	function panel:SyncEditModePosition(point, x, y)
		if not EditMode or not self.editModeId or self.suspendEditSync then return end
		self.suspendEditSync = true
		EditMode:SetFramePosition(self.editModeId, point, x, y)
		self.suspendEditSync = nil
	end

	function panel:SyncEditModeStreams()
		if not EditMode or not self.editModeId then return end
		self:SyncEditModeValue("streams", copyList(self.info.streams))
	end

	function panel:UpdatePositionInfo(data)
		if not data then return end
		local info = self.info
		if not info then return end
		if data.point then info.point = data.point end
		if data.x then info.x = data.x end
		if data.y then info.y = data.y end
	end

	function panel:ApplyStreams(streamList)
		self.suspendEditSync = true
		local desired = {}
		for _, name in ipairs(streamList or {}) do
			desired[name] = true
		end
		for existing in pairs(self.streams) do
			if not desired[existing] then self:RemoveStream(existing) end
		end
		for _, name in ipairs(streamList or {}) do
			if not self.streams[name] then self:AddStream(name) end
		end
		self.order = {}
		self.info.streams = {}
		self.info.streamSet = {}
		for _, name in ipairs(streamList or {}) do
			if self.streams[name] then
				self.order[#self.order + 1] = name
				self.info.streams[#self.info.streams + 1] = name
				self.info.streamSet[name] = true
			end
		end
		self:Refresh()
		self.suspendEditSync = nil
		if not self.applyingFromEditMode then self:SyncEditModeStreams() end
	end

	function panel:ApplyEditMode(data)
		self.suspendEditSync = true
		local info = self.info
		if data.width then
			info.width = round2(data.width)
			self.frame:SetWidth(info.width)
		end
		if data.height then
			info.height = round2(data.height)
			self.frame:SetHeight(info.height)
		end
		if data.hideBorder ~= nil then
			info.noBorder = data.hideBorder and true or false
			self:ApplyBorder()
		end
		if data.streams then
			self.applyingFromEditMode = true
			self:ApplyStreams(data.streams)
			self.applyingFromEditMode = nil
		end
		self.suspendEditSync = nil
	end

	function panel:Refresh()
		local visible = {}
		for _, name in ipairs(self.order) do
			local data = self.streams[name]
			if data then
				if data.hidden then
					data.button:Hide()
				else
					visible[#visible + 1] = name
				end
			end
		end

		local changed = false
		if not self.lastOrder or #self.lastOrder ~= #visible then
			changed = true
		else
			for i, name in ipairs(visible) do
				local data = self.streams[name]
				if self.lastOrder[i] ~= name or (self.lastWidths and self.lastWidths[name] ~= (data.lastWidth or 0)) then
					changed = true
					break
				end
			end
		end
		if not changed then return end

		local prev
		for _, name in ipairs(visible) do
			local data = self.streams[name]
			local btn = data.button
			btn:Show()
			btn:ClearAllPoints()
			btn:SetWidth(data.lastWidth or 0)
			if prev then
				btn:SetPoint("LEFT", prev, "RIGHT", 5, 0)
			else
				btn:SetPoint("LEFT", self.frame, "LEFT", 5, 0)
			end
			prev = btn
		end

		self.lastOrder = {}
		self.lastWidths = {}
		for i, name in ipairs(visible) do
			self.lastOrder[i] = name
			self.lastWidths[name] = self.streams[name].lastWidth or 0
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
			if btn == "RightButton" and not DataPanel.IsMenuModifierActive(btn) then return end
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

			if payload.hidden then
				data.button:Hide()
				if not data.hidden then
					data.hidden = true
					data.lastWidth = 0
					data.lastText = ""
					if data.parts then
						for _, child in ipairs(data.parts) do
							child:Hide()
						end
					end
					data.text:SetText("")
					self:Refresh()
				end
				data.tooltip = nil
				data.perCurrency = nil
				data.showDescription = nil
				data.hover = nil
				data.OnMouseEnter = nil
				data.OnMouseLeave = nil
				if payload.OnClick ~= nil then data.OnClick = payload.OnClick end
				return
			elseif data.hidden then
				data.hidden = nil
				data.button:Show()
				self:Refresh()
			end

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
							local hint = DataPanel.GetOptionsHintText and DataPanel.GetOptionsHintText()
							if hint then
								GameTooltip:AddLine(" ")
								GameTooltip:AddLine(hint)
							end
						elseif data.tooltip then
							GameTooltip:SetText(data.tooltip)
						end
						GameTooltip:Show()
					end)
					child:SetScript("OnLeave", function() GameTooltip:Hide() end)
					child:SetScript("OnClick", function(_, btn, ...)
						if btn == "RightButton" and not DataPanel.IsMenuModifierActive(btn) then return end
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
		self:SyncEditModeStreams()
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
		self:SyncEditModeStreams()
	end

	panels[id] = panel

	if info.streams then
		for _, name in ipairs(info.streams) do
			panel:AddStream(name)
		end
	end

	registerEditModePanel(panel)
	panel:SyncEditModeStreams()

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
