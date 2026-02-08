local addonName, addon = ...

addon.EditMode = addon.EditMode or {}
local EditMode = addon.EditMode

local LibEditMode = LibStub("LibEQOLEditMode-1.0")

local DEFAULT_LAYOUT = "_Global"

local function getSelection(lib, frame)
	if not lib or not lib.frameSelections then return nil end
	return lib.frameSelections[frame]
end

local function copyDefaults(target, defaults)
	if not defaults then return end
	for key, value in pairs(defaults) do
		if target[key] == nil then
			if type(value) == "table" then
				target[key] = CopyTable(value)
			else
				target[key] = value
			end
		end
	end
end

EditMode.frames = EditMode.frames or {}
EditMode.lib = LibEditMode
EditMode.activeLayout = EditMode.activeLayout
EditMode.layoutFresh = EditMode.layoutFresh or {}

function EditMode:IsAvailable() return self.lib ~= nil end

function EditMode:IsInEditMode() return self:IsAvailable() and self.lib:IsInEditMode() end

function EditMode:_ensureDB()
	if not addon.db then return nil end
	addon.db.editModeLayouts = addon.db.editModeLayouts or {}
	return addon.db.editModeLayouts
end

function EditMode:GetActiveLayoutName()
	if self:IsAvailable() then
		local layoutName = self.lib:GetActiveLayoutName()
		if layoutName and layoutName ~= "" then
			if self.activeLayout and self.activeLayout ~= layoutName then self.lastActiveLayout = self.activeLayout end
			self.activeLayout = layoutName
			return layoutName
		end
	end
	return self.activeLayout or DEFAULT_LAYOUT
end

function EditMode:_resolveLayoutName(layoutName)
	if layoutName and layoutName ~= "" then return layoutName end
	return self:GetActiveLayoutName()
end

function EditMode:_resolveLayoutNameByIndex(layoutIndex)
	if not layoutIndex then return nil end
	local lib = self.lib
	local layoutNames = lib and lib.layoutNames
	return layoutNames and layoutNames[layoutIndex]
end

function EditMode:_layoutHasData(layoutName)
	if not layoutName then return false end
	local layouts = self:_ensureDB()
	if not layouts then return false end
	local data = layouts[layoutName]
	return data ~= nil and next(data) ~= nil
end

function EditMode:_copyLayoutData(sourceLayoutName, targetLayoutName, force)
	if not sourceLayoutName or not targetLayoutName or sourceLayoutName == targetLayoutName then return false end
	local layouts = self:_ensureDB()
	if not layouts then return false end
	local source = layouts[sourceLayoutName]
	if not source or next(source) == nil then return false end
	local target = layouts[targetLayoutName]
	if target and next(target) ~= nil and not force then return false end
	layouts[targetLayoutName] = CopyTable(source)
	return true
end

function EditMode:_getLayoutCopySource(targetLayoutName)
	local source = self:GetActiveLayoutName()
	if source == targetLayoutName then source = self.lastActiveLayout end
	if source == targetLayoutName then source = nil end
	return source
end

function EditMode:_applyLayoutIfActive(layoutName)
	if not layoutName then return end
	if self:GetActiveLayoutName() == layoutName then self:OnLayoutChanged(layoutName) end
end

local function isInCombat() return InCombatLockdown and InCombatLockdown() end

function EditMode:_ensureCombatWatcher()
	if self.combatWatcher then return end
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	watcher:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			EditMode:_flushPendingLayout()
			EditMode:_flushPendingVisibility()
			EditMode:_refreshAllVisibility()
		else
			EditMode:_refreshAllVisibility()
		end
	end)
	self.combatWatcher = watcher
end

function EditMode:_flushPendingVisibility()
	local pending = self.pendingVisibility
	if not pending then return end
	self.pendingVisibility = nil
	for entry, shouldShow in pairs(pending) do
		if entry then self:_applyVisibility(entry, nil, entry._lastEnabled, true) end
	end
end

function EditMode:_flushPendingLayout()
	local pending = self.pendingLayout
	if not pending then return end
	self.pendingLayout = nil
	for entry, data in pairs(pending) do
		if entry and data then self:_applyLayoutPosition(entry, data, true) end
	end
end

function EditMode:_refreshAllVisibility()
	for _, entry in pairs(self.frames) do
		self:_applyVisibility(entry, nil, entry._lastEnabled, true)
	end
end

function EditMode:_setFrameShown(entry, shouldShow, immediate)
	local frame = entry.frame
	if not frame then return end

	local isProtected = frame.IsProtected and frame:IsProtected()
	if not immediate and isProtected and isInCombat() then
		self.pendingVisibility = self.pendingVisibility or {}
		self.pendingVisibility[entry] = shouldShow
		self:_ensureCombatWatcher()
		return
	end

	if self.pendingVisibility then self.pendingVisibility[entry] = nil end

	local currentlyShown = frame:IsShown()
	if shouldShow then
		if not currentlyShown then frame:Show() end
	else
		if currentlyShown then frame:Hide() end
	end
end

local function resolveRelativeFrame(entry)
	if not entry then return UIParent end
	local relative = entry.relativeTo
	if type(relative) == "function" then relative = relative() end
	return relative or UIParent
end

function EditMode:_applyLayoutPosition(entry, data, immediate)
	local frame = entry.frame
	if not frame then return end

	if frame.IsProtected and frame:IsProtected() and not immediate and isInCombat() then
		self.pendingLayout = self.pendingLayout or {}
		local config = {
			point = data.point,
			relativePoint = data.relativePoint,
			x = data.x,
			y = data.y,
		}
		self.pendingLayout[entry] = config
		self:_ensureCombatWatcher()
		return
	end

	if self.pendingLayout then self.pendingLayout[entry] = nil end

	local point = data.point
	local relativePoint = data.relativePoint or point
	local x = data.x or 0
	local y = data.y or 0
	local relative = resolveRelativeFrame(entry)

	frame:ClearAllPoints()
	frame:SetPoint(point, relative, relativePoint, x, y)
end

function EditMode:EnsureLayoutData(id, layoutName)
	local entry = self.frames[id]
	if not entry then return nil end

	local container = self:_ensureDB()
	if not container then
		entry._fallback = entry._fallback or {}
		local layoutKey = self:_resolveLayoutName(layoutName)
		local record = entry._fallback[layoutKey]
		if not record then
			record = {}
			entry._fallback[layoutKey] = record
		end
		copyDefaults(record, entry.defaults)
		return record
	end

	local layoutKey = self:_resolveLayoutName(layoutName)
	local layout = container[layoutKey]
	if not layout then
		layout = {}
		container[layoutKey] = layout
	end

	local record = layout[id]
	if not record then
		record = {}
		if entry.legacy then
			for field, key in pairs(entry.legacy) do
				local value = addon.db and addon.db[key]
				if value ~= nil then record[field] = value end
			end
		end
		copyDefaults(record, entry.defaults)
		layout[id] = record
	end

	return record
end

function EditMode:GetLayoutData(id, layoutName) return self:EnsureLayoutData(id, layoutName) end

function EditMode:SetFramePosition(id, point, x, y, layoutName, skipApply)
	local data = self:EnsureLayoutData(id, layoutName)
	if not data then return end

	data.point = point
	data.relativePoint = point
	data.x = x
	data.y = y

	if not skipApply then self:ApplyLayout(id, layoutName) end
end

function EditMode:SetValue(id, field, value, layoutName, skipApply)
	local data = self:EnsureLayoutData(id, layoutName)
	if not data then return end

	data[field] = value
	if not skipApply then self:ApplyLayout(id, layoutName) end
end

function EditMode:GetValue(id, field, layoutName)
	local data = self:EnsureLayoutData(id, layoutName)
	return data and data[field]
end

function EditMode:_isEntryEnabled(entry)
	if entry.isEnabled then
		local ok, result = pcall(entry.isEnabled, entry.frame)
		if not ok then
			geterrorhandler()(result)
			return true
		end
		return not not result
	end
	return true
end

function EditMode:_applyVisibility(entry, layoutName, enabled, forceImmediate)
	local frame = entry.frame
	local lib = self.lib
	if enabled == nil then enabled = self:_isEntryEnabled(entry) end
	entry._lastEnabled = enabled

	local selection = getSelection(lib, frame)
	local inEditMode = self:IsInEditMode()
	local inCombat = isInCombat()

	if frame then
		local shouldShow = false
		if enabled then
			if entry.showOutsideEditMode then shouldShow = true end
			if inEditMode and not inCombat then shouldShow = true end
		end
		self:_setFrameShown(entry, shouldShow, forceImmediate)
	end

	if selection then
		if enabled and inEditMode and not inCombat then
			selection:Show()
		else
			selection:Hide()
			selection.isSelected = false
		end
	end

	return enabled
end

function EditMode:RefreshFrame(id, layoutName)
	local entry = self.frames[id]
	if not entry then return end
	layoutName = self:_resolveLayoutName(layoutName)
	self:ApplyLayout(id, layoutName)
end

function EditMode:ApplyLayout(id, layoutName)
	local entry = self.frames[id]
	if not entry or not entry.frame then return end

	layoutName = self:_resolveLayoutName(layoutName)
	local data = self:EnsureLayoutData(id, layoutName)
	if not data then return end

	if entry.managePosition ~= false then
		local position = {
			point = data.point or entry.defaults.point or "CENTER",
			relativePoint = data.relativePoint or entry.defaults.relativePoint or data.point or entry.defaults.point or "CENTER",
			x = data.x or entry.defaults.x or 0,
			y = data.y or entry.defaults.y or 0,
		}
		self:_applyLayoutPosition(entry, position)
	end

	if entry.onApply then entry.onApply(entry.frame, layoutName, data) end

	self:_applyVisibility(entry, layoutName)
end

function EditMode:_registerCallbacks()
	if self.callbacksRegistered then return end
	if not self:IsAvailable() then return end
	self.callbacksRegistered = true

	self.lib:RegisterCallback("enter", function() self:OnEnterEditMode() end)
	self.lib:RegisterCallback("exit", function() self:OnExitEditMode() end)
	self.lib:RegisterCallback("layout", function(layoutName)
		if layoutName and layoutName ~= "" then
			if self.activeLayout and self.activeLayout ~= layoutName then self.lastActiveLayout = self.activeLayout end
			self.activeLayout = layoutName
		end
		self:OnLayoutChanged(layoutName)
	end)
	self.lib:RegisterCallback("layoutrenamed", function(oldName, newName, layoutIndex) self:OnLayoutRenamed(oldName, newName, layoutIndex) end)
	self.lib:RegisterCallback(
		"layoutadded",
		function(layoutIndex, activateNewLayout, isLayoutImported, layoutType, layoutName) self:OnLayoutAdded(layoutIndex, activateNewLayout, isLayoutImported, layoutType, layoutName) end
	)
	self.lib:RegisterCallback(
		"layoutduplicate",
		function(addedLayoutIndex, dupes, isLayoutImported, layoutType, newName) self:OnLayoutDuplicate(addedLayoutIndex, dupes, isLayoutImported, layoutType, newName) end
	)
end

function EditMode:OnEnterEditMode()
	for _, entry in pairs(self.frames) do
		local layoutName = self:GetActiveLayoutName()
		local enabled = self:_applyVisibility(entry, layoutName)
		if enabled and entry.onEnter then entry.onEnter(entry.frame, layoutName, self:EnsureLayoutData(entry.id)) end
	end
end

function EditMode:OnExitEditMode()
	for _, entry in pairs(self.frames) do
		if entry.onExit and entry._lastEnabled then entry.onExit(entry.frame, self:GetActiveLayoutName(), self:EnsureLayoutData(entry.id)) end
		self:_applyVisibility(entry, self:GetActiveLayoutName())
	end
end

function EditMode:OnLayoutChanged(layoutName)
	local resolved = self:_resolveLayoutName(layoutName)
	if resolved and not self:_layoutHasData(resolved) then
		if not self.layoutFresh[resolved] then self.layoutFresh[resolved] = true end
	end
	for id in pairs(self.frames) do
		self:ApplyLayout(id, layoutName)
	end
end

function EditMode:OnLayoutRenamed(oldName, newName, layoutIndex)
	if not oldName or oldName == "" or not newName or newName == "" or oldName == newName then return end
	local layouts = self:_ensureDB()
	if layouts then
		local data = layouts[oldName]
		if data then
			layouts[newName] = data
			layouts[oldName] = nil
		end
	else
		for _, entry in pairs(self.frames) do
			local fallback = entry._fallback
			if fallback and fallback[oldName] then
				fallback[newName] = fallback[oldName]
				fallback[oldName] = nil
			end
		end
	end
	if self.activeLayout == oldName then self.activeLayout = newName end
	if self.lastActiveLayout == oldName then self.lastActiveLayout = newName end
	if self.layoutFresh and self.layoutFresh[oldName] then
		self.layoutFresh[newName] = true
		self.layoutFresh[oldName] = nil
	end
end

function EditMode:OnLayoutAdded(layoutIndex, activateNewLayout, isLayoutImported, layoutType, layoutName)
	local targetName = layoutName or self:_resolveLayoutNameByIndex(layoutIndex)
	if not targetName or targetName == "" then return end
	local sourceName = self:_getLayoutCopySource(targetName)
	if not sourceName then return end
	local force = self.layoutFresh and self.layoutFresh[targetName] and true or false
	if self:_copyLayoutData(sourceName, targetName, force) then self:_applyLayoutIfActive(targetName) end
	if self.layoutFresh then self.layoutFresh[targetName] = nil end
end

function EditMode:OnLayoutDuplicate(addedLayoutIndex, dupes, isLayoutImported, layoutType, newName)
	local targetName = newName or self:_resolveLayoutNameByIndex(addedLayoutIndex)
	if not targetName or targetName == "" then return end

	local sourceName
	if type(dupes) == "table" then
		for _, dupeIndex in ipairs(dupes) do
			local dupeName = self:_resolveLayoutNameByIndex(dupeIndex)
			if dupeName and self:_layoutHasData(dupeName) then
				sourceName = dupeName
				break
			end
		end
	end

	if not sourceName then sourceName = self:_getLayoutCopySource(targetName) end
	if not sourceName then return end
	if self:_copyLayoutData(sourceName, targetName, true) then self:_applyLayoutIfActive(targetName) end
	if self.layoutFresh then self.layoutFresh[targetName] = nil end
end

function EditMode:_prepareSetting(id, setting)
	local copy = {}
	for key, value in pairs(setting) do
		if key ~= "field" and key ~= "onValueChanged" then copy[key] = value end
	end

	local field = setting.field
	local onChange = setting.onValueChanged

	local requiresField = not copy.generator and copy.kind ~= EditMode.lib.SettingType.Label and copy.kind ~= EditMode.lib.SettingType.Divider and copy.kind ~= EditMode.lib.SettingType.Collapsible

	if not copy.get and requiresField then
		assert(field, "setting.field required when getter is omitted")
		copy.get = function(layoutName)
			local data = self:EnsureLayoutData(id, layoutName)
			return data and data[field]
		end
	end

	if not copy.set and requiresField then
		assert(field, "setting.field required when setter is omitted")
		copy.set = function(layoutName, value)
			self:SetValue(id, field, value, layoutName, true)
			local data = self:EnsureLayoutData(id, layoutName)
			if onChange then onChange(layoutName, value, data) end
			self:ApplyLayout(id, layoutName)
		end
	end

	local entry = self.frames[id]
	if requiresField and copy.default == nil and entry and entry.defaults then copy.default = entry.defaults[field] end

	return copy
end

function EditMode:RegisterSettings(id, settings)
	if not settings or #settings == 0 then return end
	if not self:IsAvailable() then return end

	local entry = self.frames[id]
	if not entry or not entry.frame then return end

	local prepared = {}
	for index = 1, #settings do
		local s = self:_prepareSetting(id, settings[index])
		prepared[index] = s
		if s.field then
			entry.settingsByField = entry.settingsByField or {}
			entry.settingsByField[s.field] = s
		end
	end

	self.lib:AddFrameSettings(entry.frame, prepared)
end

function EditMode:RegisterButtons(id, buttons)
	if not buttons or #buttons == 0 then return end
	if not self:IsAvailable() then return end

	local entry = self.frames[id]
	if not entry or not entry.frame then return end

	entry.buttons = entry.buttons or {}
	for index = 1, #buttons do
		local source = buttons[index]
		if source and source.text and source.click then
			local prepared = {
				text = source.text,
				click = function(...)
					local ok, err = pcall(source.click, ...)
					if not ok then geterrorhandler()(err) end
				end,
			}
			self.lib:AddFrameSettingsButton(entry.frame, prepared)
			entry.buttons[#entry.buttons + 1] = prepared
		elseif source and source.text then
			local prepared = {
				text = source.text,
				click = function() end,
			}
			self.lib:AddFrameSettingsButton(entry.frame, prepared)
			entry.buttons[#entry.buttons + 1] = prepared
		end
	end
end

function EditMode:RegisterFrame(id, opts)
	assert(type(id) == "string" and id ~= "", "frame id must be a non-empty string")
	opts = opts or {}

	local frame = opts.frame
	if not frame and opts.createFrame then frame = opts.createFrame() end
	assert(frame, "EditMode:RegisterFrame requires a frame")

	local defaults = opts.layoutDefaults or {}
	defaults.point = defaults.point or "CENTER"
	defaults.relativePoint = defaults.relativePoint or defaults.point
	defaults.x = defaults.x or 0
	defaults.y = defaults.y or 0

	local entry = {
		id = id,
		frame = frame,
		defaults = defaults,
		legacy = opts.legacyKeys,
		isEnabled = opts.isEnabled,
		managePosition = opts.managePosition,
		relativeTo = opts.relativeTo,
		showOutsideEditMode = not not opts.showOutsideEditMode,
		onApply = opts.onApply,
		onEnter = opts.onEnter,
		onExit = opts.onExit,
	}

	self.frames[id] = entry

	if opts.title then frame.editModeName = opts.title end

	self:EnsureLayoutData(id, nil)

	if not entry.showOutsideEditMode then frame:Hide() end

	if self:IsAvailable() then
		self:_registerCallbacks()

		local defaultPosition = {
			point = self:GetValue(id, "point") or defaults.point,
			x = self:GetValue(id, "x") or defaults.x,
			y = self:GetValue(id, "y") or defaults.y,
			enableOverlayToggle = opts.enableOverlayToggle or false,
			collapseExclusive = opts.collapseExclusive or false,
			allowDrag = opts.allowDrag,
			settingsSpacing = opts.settingsSpacing,
			sliderHeight = opts.sliderHeight,
			dropdownHeight = opts.dropdownHeight,
			checkboxColorHeight = opts.checkboxColorHeight,
			multiDropdownSummaryHeight = opts.multiDropdownSummaryHeight,
			dividerHeight = opts.dividerHeight,
			showSettingsReset = opts.showSettingsReset,
			showReset = opts.showReset,
			settingsMaxHeight = opts.settingsMaxHeight,
		}

		self.lib:AddFrame(frame, function(_, layoutName, point, x, y)
			self:SetFramePosition(id, point, x, y, layoutName, true)
			if opts.onPositionChanged then opts.onPositionChanged(frame, layoutName, self:EnsureLayoutData(id, layoutName)) end
			self:ApplyLayout(id, layoutName)
		end, defaultPosition)

		if opts.settings then self:RegisterSettings(id, opts.settings) end
		if opts.buttons then self:RegisterButtons(id, opts.buttons) end
	end

	self:ApplyLayout(id, self:GetActiveLayoutName())
	-- self.lib:AddManagerCheckbox({
    --     label = frame.editModeName,
    --     frames = frame,
    --     category = "EnhanceQoL",
    --     id = id,
    -- })

	return frame
end

function EditMode:UnregisterFrame(id)
	if not id then return end
	id = tostring(id)
	local entry = self.frames and self.frames[id]
	if not entry then return end

	if self.pendingLayout then self.pendingLayout[entry] = nil end
	if self.pendingVisibility then self.pendingVisibility[entry] = nil end

	if self:IsAvailable() and entry.frame and self.lib then
		local frame = entry.frame
		local lib = self.lib
		local selection = lib.frameSelections and lib.frameSelections[frame]
		if selection then
			if lib.internal and lib.internal.magnetismManager and lib.internal.magnetismManager.UnregisterFrame then lib.internal.magnetismManager:UnregisterFrame(selection) end
			selection:Hide()
			selection:SetParent(nil)
			lib.frameSelections[frame] = nil
		end
		if lib.frameCallbacks then lib.frameCallbacks[frame] = nil end
		if lib.frameDefaults then lib.frameDefaults[frame] = nil end
		if lib.frameSettings then lib.frameSettings[frame] = nil end
		if lib.frameButtons then lib.frameButtons[frame] = nil end
	end

	local layouts = addon.db and addon.db.editModeLayouts
	if layouts then
		for layoutName, layout in pairs(layouts) do
			if type(layout) == "table" then
				layout[id] = nil
				if not next(layout) then layouts[layoutName] = nil end
			end
		end
	end

	self.frames[id] = nil
end
