local addonName, addon = ...
addon.DataHub = addon.DataHub or {}
local DataHub = addon.DataHub

DataHub.Debug = DataHub.Debug or false

local function debugPrint(...)
	if DataHub.Debug then print("[DataHub]", ...) end
end

local eventFrame = CreateFrame("Frame")
local driver = CreateFrame("Frame")
local DRIVER_TICK = 0.1

DataHub.streams = {}
DataHub.eventMap = {}
DataHub.polling = {}
DataHub.eventsByStream = {}
DataHub.throttleTimers = {}
DataHub.driverTicker = DataHub.driverTicker or nil
DataHub.unitEventMap = DataHub.unitEventMap or {}
DataHub.unitFrames = DataHub.unitFrames or {}
DataHub.eventsByStreamUnit = DataHub.eventsByStreamUnit or {}

local ipairs = ipairs
local pairs = pairs
local GetTime = GetTime

local function getPlayerClassToken()
	if DataHub.playerClass ~= nil then return DataHub.playerClass end
	local class = UnitClass and select(2, UnitClass("player"))
	DataHub.playerClass = class
	return class
end

local function isStreamAllowed(stream)
	local filter = stream and stream.classFilter
	if not filter then return true end
	local class = getPlayerClassToken()
	if not class then return true end
	if type(filter) == "function" then
		local ok, result = pcall(filter, class)
		if ok then return result and true or false end
		return true
	end
	if type(filter) == "table" then return filter[class] and true or false end
	if type(filter) == "string" then return filter == class end
	return true
end

local function getUnitFrame(unitToken)
	local frames = DataHub.unitFrames
	local frame = frames[unitToken]
	if frame then return frame end
	frame = CreateFrame("Frame")
	frame._eqolUnit = unitToken
	frame:SetScript("OnEvent", function(_, event, ...)
		local unitMap = DataHub.unitEventMap[unitToken]
		if not unitMap then return end
		local streams = unitMap[event]
		if not streams then return end
		for stream, handler in pairs(streams) do
			if handler == true then
				DataHub:RequestUpdate(stream.name)
			else
				pcall(handler, ...)
			end
		end
	end)
	frames[unitToken] = frame
	return frame
end

local function acquireRow(stream)
	local pool = stream.pool
	local row = pool[#pool]
	pool[#pool] = nil
	if row then
		wipe(row)
	else
		row = {}
	end
	return row
end

local function releaseRows(stream)
	for i = #stream.snapshot, 1, -1 do
		local row = stream.snapshot[i]
		stream.snapshot[i] = nil
		stream.pool[#stream.pool + 1] = row
	end
end

local function runUpdate(stream)
	debugPrint("runUpdate", stream.name)
	releaseRows(stream)
	if stream.update then stream.update(stream) end
	if stream.interval and stream.interval > 0 then stream.nextPoll = GetTime() + stream.interval end
	if stream.subscribers then
		debugPrint("publish", stream.name)
		for cb in pairs(stream.subscribers) do
			pcall(cb, stream.snapshot, stream.name)
		end
	end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local streams = DataHub.eventMap[event]
	if streams then
		for stream, handler in pairs(streams) do
			if handler == true then
				DataHub:RequestUpdate(stream.name)
			else
				pcall(handler, ...)
			end
		end
	end
end)

local function driverUpdate()
	local now = GetTime()
	for _, stream in pairs(DataHub.polling) do
		if not stream.nextPoll or now >= stream.nextPoll then DataHub:RequestUpdate(stream.name) end
	end
end

function DataHub:UpdateDriver()
	if next(self.polling) then
		if not self.driverTicker then
			self.driverTicker = C_Timer.NewTicker(DRIVER_TICK, driverUpdate)
			driverUpdate()
		end
	else
		if self.driverTicker then
			self.driverTicker:Cancel()
			self.driverTicker = nil
		end
	end
end

function DataHub:RegisterStream(name, opts)
	-- Be tolerant: allow either (name, opts) **or** a provider table (dot/colon safe)
	local hub = DataHub
	local provider

	-- Case A: called as DataHub.RegisterStream(provider)
	if type(name) == "table" and opts == nil then
		provider = name
		name = provider.id or provider.name or provider.title
		opts = {}
	end
	-- Case B: accidentally called with dot so that 'self' is actually the provider
	if type(self) == "table" and self ~= hub and self.id and name == nil and opts == nil then
		provider = self
		name = provider.id or provider.name or provider.title
		opts = {}
	end

	assert(name, "RegisterStream: missing stream name (or provider.id)")
	opts = opts or {}

	-- Map provider fields (poll/collect) to hub opts/update
	if provider then
		-- poll mapping
		local p = provider.poll
		if type(p) == "number" then
			opts.interval = opts.interval or p
		elseif type(p) == "table" then
			opts.interval = opts.interval or p.interval
			opts.events = opts.events or p.events
			opts.throttleKey = opts.throttleKey or p.throttleKey
			opts.throttle = opts.throttle or p.throttleDelay or p.delay
		end
		if not opts.update and type(provider.update) == "function" then opts.update = provider.update end
		-- wrap collect into update if present
		if not opts.update and type(provider.collect) == "function" then
			opts.update = function(stream)
				local ctx = {
					acquireRow = function() return acquireRow(stream) end,
					rows = stream.snapshot,
					now = GetTime(),
				}
				local ok = pcall(provider.collect, ctx)
				stream.snapshot = ctx.rows
				if not ok then
					-- keep empty snapshot if collect failed
					stream.snapshot = stream.snapshot or {}
				end
			end
		end
	end

	-- Create/return stream
	if hub.streams[name] then return hub.streams[name] end
	local stream = {
		name = name,
		snapshot = {},
		pool = {},
		subscribers = {},
		update = opts and opts.update,
		throttle = (opts and opts.throttle) or 0.1,
		throttleKey = (opts and opts.throttleKey) or name,
		interval = opts and opts.interval,
		nextPoll = GetTime(),
		meta = provider, -- keep original provider for UI/metadata
	}
	if provider and provider.classFilter then stream.classFilter = provider.classFilter end
	if provider and provider.OnClick then stream.snapshot.OnClick = provider.OnClick end
	if provider and provider.OnMouseEnter then stream.snapshot.OnMouseEnter = provider.OnMouseEnter end
	hub.streams[name] = stream
	hub.eventsByStream[name] = {}
	hub.eventsByStreamUnit[name] = {}

	if opts and opts.events then
		for _, event in ipairs(opts.events) do
			-- store event definition without registering yet
			hub:RegisterEvent(stream, event)
		end
	end
	if provider and provider.events then
		for event, fn in pairs(provider.events) do
			local ev = event
			local handler = fn
			-- store handler without registering yet
			hub:RegisterEvent(stream, ev, function(...) handler(stream, ev, ...) end)
		end
	end
	if provider and provider.eventsUnit then
		for unitToken, unitEvents in pairs(provider.eventsUnit) do
			if type(unitEvents) == "table" then
				if #unitEvents > 0 then
					for _, event in ipairs(unitEvents) do
						hub:RegisterUnitEvent(stream, unitToken, event)
					end
				else
					for event, fn in pairs(unitEvents) do
						local ev = event
						local handler
						if type(fn) == "function" then
							handler = function(...) fn(stream, ev, ...) end
						else
							handler = true
						end
						hub:RegisterUnitEvent(stream, unitToken, ev, handler)
					end
				end
			end
		end
	end

	if stream.interval and stream.interval > 0 then stream.nextPoll = GetTime() end

	return stream
end

function DataHub:UnregisterStream(name)
	local stream = self.streams[name]
	if not stream then return end

	local events = self.eventsByStream[name]
	if events then
		for event in pairs(events) do
			self:UnregisterEvent(stream, event)
		end
		self.eventsByStream[name] = nil
	end
	local unitEvents = self.eventsByStreamUnit[name]
	if unitEvents then
		for unitToken, byEvent in pairs(unitEvents) do
			for event in pairs(byEvent) do
				self:UnregisterUnitEvent(stream, unitToken, event)
			end
		end
		self.eventsByStreamUnit[name] = nil
	end

	self.polling[name] = nil
	self:UpdateDriver()

	local key = stream.throttleKey or stream.name
	local timer = self.throttleTimers[key]
	if timer then
		timer:Cancel()
		self.throttleTimers[key] = nil
	end

	stream.subscribers = nil
	stream.pending = nil
	releaseRows(stream)
	self.streams[name] = nil
end

function DataHub:RegisterEvent(stream, event, handler)
	-- always store definition
	self.eventsByStream[stream.name][event] = handler or true
	-- only register with the event frame when the stream has subscribers
	if stream.subscribers and next(stream.subscribers) then
		self.eventMap[event] = self.eventMap[event] or {}
		self.eventMap[event][stream] = handler or true
		eventFrame:RegisterEvent(event)
	end
end

function DataHub:RegisterUnitEvent(stream, unitToken, event, handler)
	unitToken = tostring(unitToken)
	self.eventsByStreamUnit[stream.name] = self.eventsByStreamUnit[stream.name] or {}
	local byUnit = self.eventsByStreamUnit[stream.name][unitToken]
	if not byUnit then
		byUnit = {}
		self.eventsByStreamUnit[stream.name][unitToken] = byUnit
	end
	byUnit[event] = handler or true

	if stream.subscribers and next(stream.subscribers) then
		local unitMap = self.unitEventMap[unitToken]
		if not unitMap then
			unitMap = {}
			self.unitEventMap[unitToken] = unitMap
		end
		local streamMap = unitMap[event]
		if not streamMap then
			streamMap = {}
			unitMap[event] = streamMap
			local frame = getUnitFrame(unitToken)
			if frame and frame.RegisterUnitEvent then
				frame:RegisterUnitEvent(event, unitToken)
			elseif frame then
				frame:RegisterEvent(event)
			end
		end
		streamMap[stream] = handler or true
	end
end

function DataHub:UnregisterEvent(stream, event, keep)
	-- remove from the live event map
	local map = self.eventMap[event]
	if map then
		map[stream] = nil
		if not next(map) then
			self.eventMap[event] = nil
			eventFrame:UnregisterEvent(event)
		end
	end
	-- drop the stored definition unless explicitly kept
	if not keep then
		local events = self.eventsByStream[stream.name]
		if events then events[event] = nil end
	end
end

function DataHub:UnregisterUnitEvent(stream, unitToken, event, keep)
	unitToken = tostring(unitToken)
	local unitMap = self.unitEventMap[unitToken]
	if unitMap then
		local streamMap = unitMap[event]
		if streamMap then
			streamMap[stream] = nil
			if not next(streamMap) then
				unitMap[event] = nil
				local frame = self.unitFrames[unitToken]
				if frame then frame:UnregisterEvent(event) end
			end
		end
		if not next(unitMap) then self.unitEventMap[unitToken] = nil end
	end

	if not keep then
		local byStream = self.eventsByStreamUnit[stream.name]
		if byStream then
			local byUnit = byStream[unitToken]
			if byUnit then
				byUnit[event] = nil
				if not next(byUnit) then byStream[unitToken] = nil end
			end
			if not next(byStream) then self.eventsByStreamUnit[stream.name] = nil end
		end
	end
end

function DataHub:RequestUpdate(name, throttleKey)
	local stream = type(name) == "table" and name or self.streams[name]
	if not stream then return end
	if stream.classFiltered then return end
	if not stream.subscribers or not next(stream.subscribers) then return end
	local key = throttleKey or stream.throttleKey or stream.name
	if self.throttleTimers[key] then return end
	stream.pending = true
	self.throttleTimers[key] = C_Timer.NewTimer(stream.throttle, function()
		self.throttleTimers[key] = nil
		stream.pending = nil
		runUpdate(stream)
	end)
end

function DataHub:Publish(name, payload)
	local stream = type(name) == "table" and name or self.streams[name]
	if not stream or not stream.subscribers then return end
	local key = stream.throttleKey or stream.name
	local timer = self.throttleTimers[key]
	if timer then
		timer:Cancel()
		self.throttleTimers[key] = nil
	end
	stream.pending = nil
	stream.snapshot = payload
	debugPrint("publish", stream.name)
	for cb in pairs(stream.subscribers) do
		pcall(cb, payload, stream.name)
	end
end

function DataHub:AcquireRow(name)
	local stream = type(name) == "table" and name or self.streams[name]
	if not stream then return {} end
	return acquireRow(stream)
end

function DataHub:GetSnapshot(name)
	local stream = self.streams[name]
	return stream and stream.snapshot
end

function DataHub:Subscribe(name, callback)
	debugPrint("subscribe", name)
	local stream = self.streams[name]
	if not stream or type(callback) ~= "function" then return end
	stream.subscribers = stream.subscribers or {}
	local isFirst = not next(stream.subscribers)
	stream.subscribers[callback] = true
	local allowed = isStreamAllowed(stream)
	stream.classFiltered = not allowed
	if isFirst and allowed then
		-- register stored events now that there's a subscriber
		local events = self.eventsByStream[name]
		if events then
			for event, handler in pairs(events) do
				self:RegisterEvent(stream, event, handler)
			end
		end
		local unitEvents = self.eventsByStreamUnit[name]
		if unitEvents then
			for unitToken, byEvent in pairs(unitEvents) do
				for event, handler in pairs(byEvent) do
					self:RegisterUnitEvent(stream, unitToken, event, handler)
				end
			end
		end
		if stream.interval and stream.interval > 0 then
			self.polling[name] = stream
			self:UpdateDriver()
		end
	end
	if allowed then
		self:RequestUpdate(name)
	else
		stream.snapshot.hidden = true
		stream.snapshot.text = nil
		stream.snapshot.tooltip = nil
		pcall(callback, stream.snapshot, stream.name)
	end
	return function() self:Unsubscribe(name, callback) end
end

function DataHub:Unsubscribe(name, callback)
	local stream = self.streams[name]
	if not stream or not stream.subscribers then return end
	stream.subscribers[callback] = nil
	if next(stream.subscribers) then return end
	-- last subscriber removed: unregister events and polling
	stream.subscribers = nil
	local events = self.eventsByStream[name]
	if events then
		for event in pairs(events) do
			self:UnregisterEvent(stream, event, true)
		end
	end
	local unitEvents = self.eventsByStreamUnit[name]
	if unitEvents then
		for unitToken, byEvent in pairs(unitEvents) do
			for event in pairs(byEvent) do
				self:UnregisterUnitEvent(stream, unitToken, event, true)
			end
		end
	end
	if stream.interval and stream.interval > 0 then
		self.polling[name] = nil
		self:UpdateDriver()
	end
	local key = stream.throttleKey or stream.name
	local timer = self.throttleTimers[key]
	if timer then
		timer:Cancel()
		self.throttleTimers[key] = nil
	end
	stream.pending = nil
end

function DataHub:ExportCSV(name)
	local snapshot = self:GetSnapshot(name)
	if not snapshot or not snapshot[1] then return "" end

	local headers = {}
	for k in pairs(snapshot[1]) do
		headers[#headers + 1] = k
	end
	local lines = {}
	lines[1] = table.concat(headers, ",")
	for _, row in ipairs(snapshot) do
		local values = {}
		for i, key in ipairs(headers) do
			local v = row[key]
			if type(v) == "string" then
				v = v:gsub('"', '""')
				values[i] = '"' .. v .. '"'
			else
				values[i] = tostring(v or "")
			end
		end
		lines[#lines + 1] = table.concat(values, ",")
	end
	return table.concat(lines, "\n")
end

return DataHub
