local addonName, addon = ...
addon.DataHub = addon.DataHub or {}
local DataHub = addon.DataHub

local eventFrame = CreateFrame("Frame")
local driver = CreateFrame("Frame")

DataHub.streams = {}
DataHub.eventMap = {}
DataHub.polling = {}
DataHub.eventsByStream = {}
DataHub.throttleTimers = {}

local tinsert = table.insert
local tremove = table.remove
local ipairs = ipairs
local pairs = pairs
local GetTime = GetTime

local function acquireRow(stream)
	local row = tremove(stream.pool)
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
	releaseRows(stream)
	if stream.update then stream.update(stream) end
	if stream.interval and stream.interval > 0 then stream.nextPoll = GetTime() + stream.interval end
	if stream.subscribers then
		for cb in pairs(stream.subscribers) do
			pcall(cb, stream.snapshot, stream.name)
		end
	end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local streams = DataHub.eventMap[event]
	if streams then
		for stream in pairs(streams) do
			DataHub:RequestUpdate(stream.name)
		end
	end
end)

function DataHub:UpdateDriver()
	if next(self.polling) then
		driver:SetScript("OnUpdate", function()
			local now = GetTime()
			for _, stream in pairs(DataHub.polling) do
				if not stream.nextPoll or now >= stream.nextPoll then DataHub:RequestUpdate(stream.name) end
			end
		end)
	else
		driver:SetScript("OnUpdate", nil)
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
		-- wrap collect into update if present
		if not opts.update and type(provider.collect) == "function" then
			opts.update = function(stream)
				local ctx = {
					acquireRow = function() return acquireRow(stream) end,
					now = GetTime(),
				}
				local ok, out = pcall(provider.collect, ctx)
				if ok and out and out.rows then
					-- Use the provider's row set (rows are acquired from this stream's pool)
					stream.snapshot = out.rows
				else
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
	hub.streams[name] = stream
	hub.eventsByStream[name] = {}

	if opts and opts.events then
		for _, event in ipairs(opts.events) do
			hub:RegisterEvent(stream, event)
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

function DataHub:RegisterEvent(stream, event)
	self.eventsByStream[stream.name][event] = true
	self.eventMap[event] = self.eventMap[event] or {}
	self.eventMap[event][stream] = true
	eventFrame:RegisterEvent(event)
end

function DataHub:UnregisterEvent(stream, event)
	local events = self.eventsByStream[stream.name]
	if events then events[event] = nil end
	local map = self.eventMap[event]
	if map then
		map[stream] = nil
		if not next(map) then
			self.eventMap[event] = nil
			eventFrame:UnregisterEvent(event)
		end
	end
end

function DataHub:RequestUpdate(name, throttleKey)
	local stream = type(name) == "table" and name or self.streams[name]
	if not stream then return end
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
	local stream = self.streams[name]
	if not stream or type(callback) ~= "function" then return end
	stream.subscribers = stream.subscribers or {}
	local isFirst = not next(stream.subscribers)
	stream.subscribers[callback] = true
	if isFirst and stream.interval and stream.interval > 0 then
		self.polling[name] = stream
		self:UpdateDriver()
	end
	self:RequestUpdate(name)
	return function() self:Unsubscribe(name, callback) end
end

function DataHub:Unsubscribe(name, callback)
	local stream = self.streams[name]
	if not stream or not stream.subscribers then return end
	stream.subscribers[callback] = nil
	if next(stream.subscribers) then return end
	stream.subscribers = nil
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
