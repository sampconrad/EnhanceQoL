local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.LayoutTools = addon.LayoutTools or {}
addon.LayoutTools.functions = addon.LayoutTools.functions or {}
addon.LayoutTools.variables = addon.LayoutTools.variables or {}

addon.functions.InitDBValue("eqolLayoutTools", {})
local db = addon.db["eqolLayoutTools"]

local function initDbValue(key, defaultValue)
	if db[key] == nil then db[key] = defaultValue end
end

initDbValue("enabled", false)
initDbValue("requireModifier", true)
initDbValue("modifier", "SHIFT")
initDbValue("frames", {})

local function normalizeDbVarFromId(id)
	if not id or type(id) ~= "string" then return nil end
	return string.lower(string.sub(id, 1, 1)) .. string.sub(id, 2)
end

local function resolveFramePath(path)
	if not path or type(path) ~= "string" then return nil end
	local first, rest = path:match("([^.]+)%.?(.*)")
	local obj = _G[first]
	if not obj then return nil end
	if rest and rest ~= "" then
		for seg in rest:gmatch("([^.]+)") do
			obj = obj and obj[seg]
			if not obj then return nil end
		end
	end
	return obj
end

local registry = addon.LayoutTools.variables.registry or {
	groups = {},
	groupList = {},
	frames = {},
	frameList = {},
	byName = {},
	addonIndex = {},
	noAddonEntries = {},
}
addon.LayoutTools.variables.registry = registry
registry.addonIndex = registry.addonIndex or {}
registry.noAddonEntries = registry.noAddonEntries or {}

local IsAddonLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

local function entryAddonList(entry)
	local list = {}
	local seen = {}
	if entry then
		if type(entry.addon) == "string" then
			if not seen[entry.addon] then
				seen[entry.addon] = true
				table.insert(list, entry.addon)
			end
		elseif type(entry.addon) == "table" then
			for _, name in ipairs(entry.addon) do
				if type(name) == "string" and not seen[name] then
					seen[name] = true
					table.insert(list, name)
				end
			end
		end
		if type(entry.addons) == "table" then
			for _, name in ipairs(entry.addons) do
				if type(name) == "string" and not seen[name] then
					seen[name] = true
					table.insert(list, name)
				end
			end
		end
	end
	return list
end

local function indexEntryByAddon(entry)
	local list = entryAddonList(entry)
	if #list == 0 then
		table.insert(registry.noAddonEntries, entry)
		return
	end
	for _, name in ipairs(list) do
		registry.addonIndex[name] = registry.addonIndex[name] or {}
		table.insert(registry.addonIndex[name], entry)
	end
end

local function isAnyAddonLoaded(entry)
	local list = entryAddonList(entry)
	if #list == 0 then return true end
	if not IsAddonLoaded then return false end
	for _, name in ipairs(list) do
		if IsAddonLoaded(name) then return true end
	end
	return false
end

local function matchesAddon(entry, addonName)
	if not addonName then return false end
	for _, name in ipairs(entryAddonList(entry)) do
		if name == addonName then return true end
	end
	return false
end

local function resolveEntry(entryOrId)
	if type(entryOrId) == "table" then return entryOrId end
	if type(entryOrId) == "string" then return registry.frames[entryOrId] end
	return nil
end

local function ensureFrameDb(entry)
	local resolved = resolveEntry(entry)
	if not resolved then return nil end
	local frames = db.frames
	frames[resolved.id] = frames[resolved.id] or {}
	local frameDb = frames[resolved.id]
	if frameDb.enabled == nil then frameDb.enabled = resolved.defaultEnabled ~= false end
	return frameDb
end

local function modifierPressed()
	if not db.requireModifier then return true end
	local mod = db.modifier or "SHIFT"
	return (mod == "SHIFT" and IsShiftKeyDown()) or (mod == "CTRL" and IsControlKeyDown()) or (mod == "ALT" and IsAltKeyDown())
end

function addon.LayoutTools.functions.RegisterGroup(id, label, opts)
	if not id or id == "" then return nil end
	local group = registry.groups[id]
	if not group then
		group = {
			id = id,
			label = label or id,
			order = opts and opts.order or nil,
			expanded = opts and opts.expanded or false,
		}
		registry.groups[id] = group
		table.insert(registry.groupList, id)
	else
		if label then group.label = label end
		if opts and opts.order ~= nil then group.order = opts.order end
		if opts and opts.expanded ~= nil then group.expanded = opts.expanded end
	end
	return group
end

local function makeSettingKey(id) return "layoutToolsFrame_" .. tostring(id):gsub("[^%w]", "_") end

function addon.LayoutTools.functions.RegisterFrame(def)
	if not def or not def.id then return nil end
	if registry.frames[def.id] then return registry.frames[def.id] end

	local names
	if type(def.names) == "table" then
		names = def.names
	elseif type(def.names) == "string" then
		names = { def.names }
	elseif type(def.name) == "string" then
		names = { def.name }
	elseif type(def.frame) == "string" then
		names = { def.frame }
	else
		names = { def.id }
	end

	local handles = {}
	local handlesSeen = {}
	local function addHandle(handle)
		if type(handle) ~= "string" or handle == "" then return end
		if handlesSeen[handle] then return end
		handlesSeen[handle] = true
		table.insert(handles, handle)
	end

	local function addRelativeHandles(list)
		if type(list) == "string" then list = { list } end
		if type(list) ~= "table" then return end
		for _, rel in ipairs(list) do
			if type(rel) == "string" and rel ~= "" then
				for _, base in ipairs(names) do
					addHandle(base .. "." .. rel)
				end
			end
		end
	end

	if type(def.handles) == "string" then
		addHandle(def.handles)
	elseif type(def.handles) == "table" then
		for _, handle in ipairs(def.handles) do
			addHandle(handle)
		end
	end
	addRelativeHandles(def.handlesRelative or def.dragbars or def.subframes)

	local entry = {
		id = def.id,
		label = def.label or def.id,
		group = def.group or "default",
		groupLabel = def.groupLabel,
		groupOrder = def.groupOrder,
		defaultEnabled = def.defaultEnabled,
		names = names,
		handles = (#handles > 0) and handles or nil,
		addon = def.addon,
		useRootHandle = def.useRootHandle,
		ignoreFramePositionManager = def.ignoreFramePositionManager,
		userPlaced = def.userPlaced,
		settingKey = def.settingKey or makeSettingKey(def.id),
	}

	registry.frames[entry.id] = entry
	table.insert(registry.frameList, entry)

	addon.LayoutTools.functions.RegisterGroup(entry.group, entry.groupLabel, {
		order = entry.groupOrder,
	})

	for _, name in ipairs(entry.names) do
		registry.byName[name] = entry.id
	end

	ensureFrameDb(entry)
	addon.LayoutTools.functions.MigrateLegacyPosition(entry)
	indexEntryByAddon(entry)
	addon.LayoutTools.functions.TryHookEntry(entry)

	return entry
end

function addon.LayoutTools.functions.GetGroups()
	local out = {}
	for _, id in ipairs(registry.groupList) do
		local group = registry.groups[id]
		if group then table.insert(out, group) end
	end
	table.sort(out, function(a, b)
		local ao = a.order or 1000
		local bo = b.order or 1000
		if ao ~= bo then return ao < bo end
		return (a.label or a.id) < (b.label or b.id)
	end)
	return out
end

function addon.LayoutTools.functions.GetEntriesForGroup(groupId)
	local list = {}
	for _, entry in ipairs(registry.frameList) do
		if entry.group == groupId then table.insert(list, entry) end
	end
	table.sort(list, function(a, b) return (a.label or a.id) < (b.label or b.id) end)
	return list
end

function addon.LayoutTools.functions.GetEntryForFrameName(name)
	local id = name and registry.byName[name] or nil
	return id and registry.frames[id] or nil
end

function addon.LayoutTools.functions.IsFrameEnabled(entry)
	local resolved = resolveEntry(entry)
	if not resolved then return false end
	local frameDb = ensureFrameDb(resolved)
	return frameDb and frameDb.enabled ~= false
end

function addon.LayoutTools.functions.SetFrameEnabled(entry, value)
	local resolved = resolveEntry(entry)
	if not resolved then return end
	local frameDb = ensureFrameDb(resolved)
	if frameDb then frameDb.enabled = value and true or false end
end

function addon.LayoutTools.functions.MigrateLegacyPosition(entry)
	local resolved = resolveEntry(entry)
	if not resolved then return end
	local frameDb = ensureFrameDb(resolved)
	if frameDb and frameDb.point then return end
	for _, name in ipairs(resolved.names or {}) do
		local legacyKey = normalizeDbVarFromId(name)
		local legacy = legacyKey and db[legacyKey] or nil
		if legacy and legacy.point and legacy.x and legacy.y then
			frameDb.point = legacy.point
			frameDb.x = legacy.x
			frameDb.y = legacy.y
			return
		end
	end
end

addon.LayoutTools.variables.pendingApply = addon.LayoutTools.variables.pendingApply or {}
addon.LayoutTools.variables.combatQueue = addon.LayoutTools.variables.combatQueue or {}

function addon.LayoutTools.functions.deferApply(frame, entry)
	if not frame then return end
	addon.LayoutTools.variables.pendingApply[frame] = entry or true
end

local function isEntryActive(entry)
	if not db.enabled then return false end
	return addon.LayoutTools.functions.IsFrameEnabled(entry)
end

function addon.LayoutTools.functions.applyFrameSettings(frame, entry)
	if not frame then return end
	local resolved = resolveEntry(entry) or addon.LayoutTools.functions.GetEntryForFrameName(frame:GetName() or "")
	if not resolved then return end
	if not isEntryActive(resolved) then return end
	local frameDb = ensureFrameDb(resolved)
	if not frameDb or not frameDb.point or frameDb.x == nil or frameDb.y == nil then return end
	if InCombatLockdown() and frame:IsProtected() then
		addon.LayoutTools.functions.deferApply(frame, resolved)
		return
	end
	frame._eqol_isApplying = true
	frame:ClearAllPoints()
	frame:SetPoint(frameDb.point, UIParent, frameDb.point, frameDb.x, frameDb.y)
	frame._eqol_isApplying = nil
end

function addon.LayoutTools.functions.StoreFramePosition(frame, entry)
	local resolved = resolveEntry(entry) or addon.LayoutTools.functions.GetEntryForFrameName(frame:GetName() or "")
	if not resolved then return end
	local frameDb = ensureFrameDb(resolved)
	if not frameDb then return end
	local point, _, _, xOfs, yOfs = frame:GetPoint()
	if not point then return end
	frameDb.point = point
	frameDb.x = xOfs
	frameDb.y = yOfs
end

function addon.LayoutTools.functions.createHooks(frame, entry)
	if not frame then return end
	if frame.IsForbidden and frame:IsForbidden() then return end
	if frame._eqolLayoutHooks then return end

	local resolved = resolveEntry(entry) or addon.LayoutTools.functions.GetEntryForFrameName(frame:GetName() or "")
	if not resolved then return end

	if InCombatLockdown() then
		addon.LayoutTools.variables.combatQueue[frame] = resolved
		return
	end

	frame._eqolLayoutEntryId = resolved.id
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	if resolved.userPlaced ~= nil and frame.SetUserPlaced then frame:SetUserPlaced(resolved.userPlaced) end
	if resolved.ignoreFramePositionManager ~= nil then frame.ignoreFramePositionManager = resolved.ignoreFramePositionManager end
	if frame.EnableMouse then frame:EnableMouse(true) end

	local function onStartDrag()
		if not isEntryActive(resolved) then return end
		if not modifierPressed() then return end
		if InCombatLockdown() and frame:IsProtected() then return end
		frame._eqol_isDragging = true
		frame:StartMoving()
	end

	local function onStopDrag()
		if not isEntryActive(resolved) then return end
		if InCombatLockdown() and frame:IsProtected() then return end
		frame:StopMovingOrSizing()
		frame._eqol_isDragging = nil
		addon.LayoutTools.functions.StoreFramePosition(frame, resolved)
	end

	local function attachHandle(anchor)
		if not anchor then return nil end
		local handle
		if pcall(function() handle = CreateFrame("Frame", nil, anchor, "PanelDragBarTemplate") end) and handle then
			handle.onDragStartCallback = function() return false end
			handle.target = frame
		else
			handle = CreateFrame("Frame", nil, anchor)
		end
		handle:SetAllPoints(anchor)
		handle:SetFrameLevel(anchor:GetFrameLevel() + 1)
		if not InCombatLockdown() then
			if handle.SetPropagateMouseMotion then handle:SetPropagateMouseMotion(true) end
			if handle.SetPropagateMouseClicks then handle:SetPropagateMouseClicks(true) end
		end
		if handle.EnableMouse then handle:EnableMouse(true) end
		handle:HookScript("OnDragStart", onStartDrag)
		handle:HookScript("OnDragStop", onStopDrag)
		return handle
	end

	if resolved.useRootHandle ~= false then frame._eqolMoveHandle = attachHandle(frame) end

	local createdSubs = frame._eqolMoveSubHandles or {}
	if resolved.handles then
		local function attachHandleToPath(path)
			local anchor = resolveFramePath(path)
			if not anchor or createdSubs[anchor] then return end
			if anchor.IsForbidden and anchor:IsForbidden() then return end
			createdSubs[anchor] = attachHandle(anchor)
		end

		for _, path in ipairs(resolved.handles) do
			attachHandleToPath(path)
		end

		frame:HookScript("OnShow", function()
			for _, path in ipairs(resolved.handles) do
				attachHandleToPath(path)
			end
		end)
	end
	frame._eqolMoveSubHandles = createdSubs

	hooksecurefunc(frame, "SetPoint", function(self)
		if not isEntryActive(resolved) then return end
		if self._eqol_isDragging or self._eqol_isApplying then return end
		local frameDb = ensureFrameDb(resolved)
		if not frameDb or not frameDb.point or frameDb.x == nil or frameDb.y == nil then return end
		if InCombatLockdown() and self:IsProtected() then
			addon.LayoutTools.functions.deferApply(self, resolved)
			return
		end
		self._eqol_isApplying = true
		self:ClearAllPoints()
		self:SetPoint(frameDb.point, UIParent, frameDb.point, frameDb.x, frameDb.y)
		self._eqol_isApplying = nil
	end)

	frame:HookScript("OnShow", function(self) addon.LayoutTools.functions.applyFrameSettings(self, resolved) end)

	frame._eqolLayoutHooks = true
	addon.LayoutTools.variables.combatQueue[frame] = nil

	local function setHandleEnabled(handle, enabled)
		if not handle then return end
		if handle.EnableMouse then handle:EnableMouse(enabled) end
		if handle.SetShown then handle:SetShown(enabled) end
	end

	local function updateHandleState()
		local enabled = isEntryActive(resolved)
		setHandleEnabled(frame._eqolMoveHandle, enabled)
		for _, handle in pairs(frame._eqolMoveSubHandles or {}) do
			setHandleEnabled(handle, enabled)
		end
	end

	frame._eqolUpdateHandleState = updateHandleState
	updateHandleState()
end

function addon.LayoutTools.functions.TryHookEntry(entry)
	local resolved = resolveEntry(entry)
	if not resolved then return end
	if not isAnyAddonLoaded(resolved) then return end
	for _, name in ipairs(resolved.names or {}) do
		local frame = resolveFramePath(name)
		if frame then
			addon.LayoutTools.functions.createHooks(frame, resolved)
			addon.LayoutTools.functions.applyFrameSettings(frame, resolved)
		end
	end
end

function addon.LayoutTools.functions.TryHookAll()
	for _, entry in ipairs(registry.frameList) do
		addon.LayoutTools.functions.TryHookEntry(entry)
	end
end

function addon.LayoutTools.functions.UpdateHandleState(entry)
	local resolved = resolveEntry(entry)
	if not resolved then return end
	for _, name in ipairs(resolved.names or {}) do
		local frame = resolveFramePath(name)
		if frame and frame._eqolUpdateHandleState then frame._eqolUpdateHandleState() end
	end
end

function addon.LayoutTools.functions.RefreshEntry(entry)
	addon.LayoutTools.functions.TryHookEntry(entry)
	addon.LayoutTools.functions.UpdateHandleState(entry)
end

function addon.LayoutTools.functions.ApplyAll()
	for _, entry in ipairs(registry.frameList) do
		addon.LayoutTools.functions.RefreshEntry(entry)
	end
end

local eventHandlers = {
	["ADDON_LOADED"] = function(arg1)
		if arg1 == addonName then
			for _, entry in ipairs(registry.noAddonEntries or {}) do
				addon.LayoutTools.functions.TryHookEntry(entry)
			end
		end
		print(arg1)
		local list = registry.addonIndex and registry.addonIndex[arg1]
		if list then
			for _, entry in ipairs(list) do
				addon.LayoutTools.functions.TryHookEntry(entry)
			end
		end
	end,
	["PLAYER_REGEN_ENABLED"] = function()
		local combatQueue = addon.LayoutTools.variables.combatQueue or {}
		for frame, entry in pairs(combatQueue) do
			combatQueue[frame] = nil
			if frame then addon.LayoutTools.functions.createHooks(frame, entry) end
		end

		local pending = addon.LayoutTools.variables.pendingApply or {}
		for frame, entry in pairs(pending) do
			pending[frame] = nil
			if frame then addon.LayoutTools.functions.applyFrameSettings(frame, entry) end
		end
	end,
}

local function registerEvents(frame)
	for event in pairs(eventHandlers) do
		frame:RegisterEvent(event)
	end
end

local function eventHandler(self, event, ...)
	if eventHandlers[event] then eventHandlers[event](...) end
end

local frameLoad = CreateFrame("Frame")

registerEvents(frameLoad)
frameLoad:SetScript("OnEvent", eventHandler)
