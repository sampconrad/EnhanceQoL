-- luacheck: globals EnhanceQoL MenuUtil MenuResponse C_EquipmentSet UnitCastingInfo UIErrorsFrame ERR_CLIENT_LOCKED_OUT EQUIPMENT_SETS GameTooltip UNKNOWN GAMEMENU_OPTIONS FONT_SIZE UIParent NORMAL_FONT_COLOR RAID_CLASS_COLORS CUSTOM_CLASS_COLORS UnitClass
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local format = string.format

local sets = {}
local db
local stream
local aceWindow

local function getOptionsHint()
	if addon.DataPanel and addon.DataPanel.GetOptionsHintText then
		local text = addon.DataPanel.GetOptionsHintText()
		if text ~= nil then return text end
		return nil
	end
	return L["Right-Click for options"]
end

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.equipmentsets = addon.db.datapanel.equipmentsets or {}
	db = addon.db.datapanel.equipmentsets
	db.fontSize = db.fontSize or 14
	if db.useTextColor == nil then db.useTextColor = false end
	if db.useClassColor == nil then db.useClassColor = false end
	if not db.textColor then
		local r, g, b = 1, 1, 1
		if NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.GetRGB then
			r, g, b = NORMAL_FONT_COLOR:GetRGB()
		end
		db.textColor = { r = r, g = g, b = b }
	end
end

local function getClassColor()
	local classToken = UnitClass and select(2, UnitClass("player"))
	if not classToken then return nil end
	local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
	if not colors then return nil end
	return colors[classToken]
end

local function colorizeText(text)
	if not text or text == "" then return text end
	if db and db.useClassColor then
		local color = getClassColor()
		if color and color.r and color.g and color.b then
			return format("|cff%02x%02x%02x%s|r", math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5), text)
		end
	end
	if db and db.useTextColor and db.textColor then
		local c = db.textColor
		return format("|cff%02x%02x%02x%s|r", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5), text)
	end
	return text
end

local function sortSetIDs(ids)
	if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetAssignedSpec then return ids end
	local sorted = {}
	for _, setID in ipairs(ids) do
		if C_EquipmentSet.GetEquipmentSetAssignedSpec(setID) then sorted[#sorted + 1] = setID end
	end
	for _, setID in ipairs(ids) do
		if not C_EquipmentSet.GetEquipmentSetAssignedSpec(setID) then sorted[#sorted + 1] = setID end
	end
	return sorted
end

local function collectSets()
	if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetIDs then return {} end
	local ids = C_EquipmentSet.GetEquipmentSetIDs() or {}
	ids = sortSetIDs(ids)
	for i, setID in ipairs(ids) do
		local name, icon, _, isEquipped, _, _, _, numLost = C_EquipmentSet.GetEquipmentSetInfo(setID)
		local entry = sets[i] or {}
		entry.id = setID
		entry.name = name
		entry.icon = icon
		entry.isEquipped = isEquipped
		entry.numLost = numLost or 0
		sets[i] = entry
	end
	for i = #ids + 1, #sets do
		sets[i] = nil
	end
	return ids
end

local function buildStreamText()
	local label = L["Set:"] or "Set:"
	local equippedName
	local equippedIcon
	for _, entry in ipairs(sets) do
		if entry.isEquipped then
			equippedName = entry.name
			equippedIcon = entry.icon
			break
		end
	end
	if not equippedName then return L["No Set Equipped"] or "No Set Equipped" end

	local iconSize = (db and db.fontSize) or 14
	local iconText = ""
	if equippedIcon then iconText = format(" |T%d:%d:%d:0:0:64:64:4:60:4:60|t", equippedIcon, iconSize, iconSize) end
	return format("%s %s%s", label, equippedName, iconText)
end

local function updateSets(s)
	ensureDB()
	collectSets()

	s.snapshot.text = colorizeText(buildStreamText())
	s.snapshot.fontSize = db.fontSize or 14
end

local function showSetMenu(owner)
	if not MenuUtil or not MenuUtil.CreateContextMenu then return end
	MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
		rootDescription:SetTag("MENU_EQOL_EQUIPMENT_SETS")
		rootDescription:CreateTitle(L["Equipment Sets"] or "Equipment Sets")

		if #sets == 0 then
			rootDescription:CreateButton(L["No Set Equipped"] or "No Set Equipped")
			return
		end

		for _, entry in ipairs(sets) do
			local name = entry.name or UNKNOWN
			local iconText = ""
			if entry.icon then iconText = format("|T%d:14:14:0:0:64:64:4:60:4:60|t ", entry.icon) end
			local label = iconText .. name
			rootDescription:CreateRadio(label, function() return entry.isEquipped end, function()
				if C_EquipmentSet and C_EquipmentSet.EquipmentSetContainsLockedItems and C_EquipmentSet.EquipmentSetContainsLockedItems(entry.id) then
					if UIErrorsFrame and ERR_CLIENT_LOCKED_OUT then UIErrorsFrame:AddMessage(ERR_CLIENT_LOCKED_OUT, 1.0, 0.1, 0.1, 1.0) end
					return
				end
				if UnitCastingInfo and UnitCastingInfo("player") then
					if UIErrorsFrame and ERR_CLIENT_LOCKED_OUT then UIErrorsFrame:AddMessage(ERR_CLIENT_LOCKED_OUT, 1.0, 0.1, 0.1, 1.0) end
					return
				end
				if C_EquipmentSet and C_EquipmentSet.UseEquipmentSet then C_EquipmentSet.UseEquipmentSet(entry.id) end
				return MenuResponse and MenuResponse.Close
			end, entry.id)
		end
	end)
end

local function restorePosition(frame)
	if db and db.point and db.x and db.y then
		frame:ClearAllPoints()
		frame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
	end
end

local function createAceWindow()
	if aceWindow then
		aceWindow:Show()
		return
	end
	ensureDB()
	local frame = AceGUI:Create("Window")
	aceWindow = frame.frame
	frame:SetWidth(320)
	frame:SetHeight(260)
	frame:SetLayout("List")
	frame:SetTitle((addon.DataPanel and addon.DataPanel.GetStreamOptionsTitle and addon.DataPanel.GetStreamOptionsTitle(stream and stream.meta and stream.meta.title)) or GAMEMENU_OPTIONS)

	frame.frame:SetScript("OnShow", function(self) restorePosition(self) end)
	frame.frame:SetScript("OnHide", function(self)
		local point, _, _, xOfs, yOfs = self:GetPoint()
		db.point = point
		db.x = xOfs
		db.y = yOfs
	end)

	local fontSize = AceGUI:Create("Slider")
	fontSize:SetLabel(FONT_SIZE)
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize or 14)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		if stream then addon.DataHub:RequestUpdate(stream) end
	end)
	frame:AddChild(fontSize)

	local useClassColor = AceGUI:Create("CheckBox")
	useClassColor:SetLabel(L["DataPanelUseClassTextColor"] or "Use class text color")
	useClassColor:SetValue(db.useClassColor and true or false)
	useClassColor:SetCallback("OnValueChanged", function(_, _, val)
		db.useClassColor = val and true or false
		if stream then addon.DataHub:RequestUpdate(stream) end
	end)
	frame:AddChild(useClassColor)

	local useTextColor = AceGUI:Create("CheckBox")
	useTextColor:SetLabel(L["goldPanelUseTextColor"] or "Use custom text color")
	useTextColor:SetValue(db.useTextColor and true or false)
	useTextColor:SetCallback("OnValueChanged", function(_, _, val)
		db.useTextColor = val and true or false
		if stream then addon.DataHub:RequestUpdate(stream) end
	end)
	frame:AddChild(useTextColor)

	local textColor = AceGUI:Create("ColorPicker")
	textColor:SetLabel(L["Text color"] or "Text color")
	textColor:SetColor(db.textColor.r, db.textColor.g, db.textColor.b)
	textColor:SetCallback("OnValueChanged", function(_, _, r, g, b)
		db.textColor = { r = r, g = g, b = b }
		if stream and db.useTextColor and not db.useClassColor then addon.DataHub:RequestUpdate(stream) end
	end)
	frame:AddChild(textColor)
end

local function showTooltip(btn)
	local tip = GameTooltip
	tip:ClearLines()
	tip:SetOwner(btn, "ANCHOR_TOPLEFT")
	tip:AddLine(L["Equipment Sets"] or "Equipment Sets")

	if #sets == 0 then
		tip:AddLine(" ")
		tip:AddLine(L["No Set Equipped"] or "No Set Equipped", 1, 1, 1)
		tip:Show()
		return
	end

	for i, entry in ipairs(sets) do
		if i == 1 then tip:AddLine(" ") end
		local iconText = ""
		if entry.icon then iconText = format("|T%d:14:14:0:0:64:64:4:60:4:60|t ", entry.icon) end
		local text = iconText .. (entry.name or UNKNOWN)
		if entry.numLost and entry.numLost > 0 then
			tip:AddLine(text, 1, 0.2, 0.2)
		elseif entry.isEquipped then
			tip:AddLine(text, 0.2, 1, 0.2)
		else
			tip:AddLine(text, 1, 1, 1)
		end
	end

	local hint = getOptionsHint()
	if hint then
		tip:AddLine(" ")
		tip:AddLine(hint, 0.7, 0.7, 0.7)
	end

	tip:Show()
end

local provider = {
	id = "equipmentsets",
	version = 2,
	title = L["Equipment Sets"] or "Equipment Sets",
	update = updateSets,
	events = {
		EQUIPMENT_SETS_CHANGED = function(s) addon.DataHub:RequestUpdate(s) end,
		EQUIPMENT_SWAP_FINISHED = function(s) addon.DataHub:RequestUpdate(s) end,
		PLAYER_EQUIPMENT_CHANGED = function(s) addon.DataHub:RequestUpdate(s) end,
		PLAYER_ENTERING_WORLD = function(s) addon.DataHub:RequestUpdate(s) end,
	},
	OnClick = function(button, btn)
		if btn == "LeftButton" then
			showSetMenu(button)
		elseif btn == "RightButton" then
			createAceWindow()
		end
	end,
	OnMouseEnter = function(btn) showTooltip(btn) end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
