-- luacheck: globals EnhanceQoL GAMEMENU_OPTIONS C_CurrencyInfo ITEM_QUALITY_COLORS HIGHLIGHT_FONT_COLOR_CODE RED_FONT_COLOR_CODE FONT_COLOR_CODE_CLOSE CURRENCY_SEASON_TOTAL_MAXIMUM CURRENCY_SEASON_TOTAL CURRENCY_TOTAL CURRENCY_TOTAL_CAP BreakUpLargeNumbers
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream
local tracked = {}
local trackedDirty = true

local abs = math.abs
local floor = math.floor
local ceil = math.ceil

local MAX_DECIMALS = 3
local SHORT_SUFFIXES = { "K", "M", "B", "T", "P", "E" }
local FORMAT_RULES = {
	full = { mode = "full", decimals = 0 },
	short0 = { mode = "short", decimals = 0 },
	short1 = { mode = "short", decimals = 1 },
	short2 = { mode = "short", decimals = 2 },
	short3 = { mode = "short", decimals = 3 },
}
local FORMAT_LABELS = {
	full = L["CurrencyFormatFull"] or "Full (13,343)",
	short0 = L["CurrencyFormatShort0"] or "Short (13k)",
	short1 = L["CurrencyFormatShort1"] or "Short (13.3k)",
	short2 = L["CurrencyFormatShort2"] or "Short (13.34k)",
	short3 = L["CurrencyFormatShort3"] or "Short (13.343k)",
}
local FORMAT_ORDER = { "full", "short0", "short1", "short2", "short3" }
local EMPTY_TRACKING_TEXT = L["No currency tracking"] or "No currency tracking"

local checkCurrencies
local updateCurrency
local function getOptionsHint()
	if addon.DataPanel and addon.DataPanel.GetOptionsHintText then
		local text = addon.DataPanel.GetOptionsHintText()
		if text ~= nil then return text end
		return nil
	end
	return L["Right-Click for options"]
end

local function publish(s)
	s = s or stream
	if s then addon.DataHub:Publish(s, s.snapshot) end
end

local function fullUpdate(s)
	s = s or stream
	if not s then return end
	checkCurrencies(s)
	publish(s)
end

local function rebuildTracked()
	if not db then return end
	for k in pairs(tracked) do
		tracked[k] = nil
	end
	for _, id in ipairs(db.ids) do
		tracked[id] = true
	end
	trackedDirty = false
end

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.currency = addon.db.datapanel.currency or {}
	db = addon.db.datapanel.currency
	db.fontSize = db.fontSize or 14
	db.ids = db.ids or {}
	db.currencyOptions = db.currencyOptions or {}
	db.tooltipPerCurrency = db.tooltipPerCurrency or false
	if db.showDescription == nil then db.showDescription = true end
	if trackedDirty then rebuildTracked() end
end

local function clampDecimals(value)
	local decimals = tonumber(value) or 0
	if decimals < 0 then decimals = 0 elseif decimals > MAX_DECIMALS then decimals = MAX_DECIMALS end
	return floor(decimals + 0.5)
end

local function getCurrencyOptions(id)
	db.currencyOptions[id] = db.currencyOptions[id] or {}
	local opts = db.currencyOptions[id]
	opts.mode = opts.mode == "short" and "short" or "full"
	opts.decimals = clampDecimals(opts.decimals)
	return opts
end

local function getFormatKey(opts)
	if opts.mode == "short" then
		local dec = clampDecimals(opts.decimals)
		if dec < 0 then dec = 0 elseif dec > MAX_DECIMALS then dec = MAX_DECIMALS end
		return "short" .. dec
	end
	return "full"
end

local function applyFormatChoice(opts, key)
	local choice = FORMAT_RULES[key]
	if not choice then return end
	opts.mode = choice.mode
	opts.decimals = clampDecimals(choice.decimals)
end

local function trimDecimals(text)
	local trimmed = text:gsub("(%..-)0+$", "%1")
	return trimmed:gsub("%.$", "")
end

local function truncateDecimals(value, decimals)
	decimals = decimals or 0
	if decimals <= 0 then return value >= 0 and floor(value) or ceil(value) end
	local factor = 10 ^ decimals
	if value >= 0 then
		return floor(value * factor) / factor
	else
		return ceil(value * factor) / factor
	end
end

local function abbreviateNumber(value, decimals)
	local absValue = abs(value)
	local suffix = ""
	local scaled = value
	for i = 1, #SHORT_SUFFIXES do
		if absValue >= 1000 then
			absValue = absValue / 1000
			scaled = scaled / 1000
			suffix = SHORT_SUFFIXES[i]
		else
			break
		end
	end
	if suffix == "" then
		if BreakUpLargeNumbers then return BreakUpLargeNumbers(value) end
		return tostring(value)
	end
	local truncated = truncateDecimals(scaled, decimals)
	local text
	if decimals > 0 then
		text = trimDecimals(("%." .. decimals .. "f"):format(truncated))
	else
		text = ("%d"):format(truncated)
	end
	return text .. suffix
end

local function formatCurrencyAmount(id, amount)
	local opts = getCurrencyOptions(id)
	if opts.mode == "short" then return abbreviateNumber(amount, opts.decimals or 0) end
	if BreakUpLargeNumbers then return BreakUpLargeNumbers(amount) end
	return tostring(amount)
end

local aceWindowWidget -- AceGUI widget
local listContainer

local function renderList()
	if not listContainer then return end
	listContainer:ReleaseChildren()

	for i, id in ipairs(db.ids) do
		local idx = i -- wichtig: stabiles Capturing pro Zeile
		local info = C_CurrencyInfo.GetCurrencyInfo(id)
		local name = info and info.name or ("ID %d"):format(id)
		local options = getCurrencyOptions(id)

		local row = addon.functions.createContainer("SimpleGroup", "Flow")

		local label = AceGUI:Create("Label")
		label:SetText(("%s (%d)"):format(name, id))
		label:SetWidth(160)
		row:AddChild(label)

		local formatDropdown = AceGUI:Create("Dropdown")
		formatDropdown:SetList(FORMAT_LABELS, FORMAT_ORDER)
		formatDropdown:SetValue(getFormatKey(options))
		formatDropdown:SetWidth(150)
		formatDropdown:SetCallback("OnValueChanged", function(_, _, key)
			applyFormatChoice(options, key)
			formatDropdown:SetValue(getFormatKey(options))
			fullUpdate()
		end)
		row:AddChild(formatDropdown)

		if idx > 1 then
			local up = AceGUI:Create("Icon")
			up:SetImage("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up") -- TODO replace placeholder
			up:SetImageSize(16, 16)
			up:SetWidth(30)
			up:SetCallback("OnClick", function()
				db.ids[idx], db.ids[idx - 1] = db.ids[idx - 1], db.ids[idx]
				renderList()
				fullUpdate()
			end)
			row:AddChild(up)
		else
			local spacer = AceGUI:Create("Label")
			spacer:SetWidth(30)
			row:AddChild(spacer)
		end

		if idx < #db.ids then
			local down = AceGUI:Create("Icon")
			down:SetImage("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up") -- TODO replace placeholder
			down:SetImageSize(16, 16)
			down:SetWidth(30)
			down:SetCallback("OnClick", function()
				db.ids[idx], db.ids[idx + 1] = db.ids[idx + 1], db.ids[idx]
				renderList()
				fullUpdate()
			end)
			row:AddChild(down)
		else
			local spacer = AceGUI:Create("Label")
			spacer:SetWidth(30)
			row:AddChild(spacer)
		end

		local remove = AceGUI:Create("Icon")
		remove:SetImage("Interface\\Buttons\\UI-GroupLoot-Pass-Up") -- TODO replace placeholder
		remove:SetImageSize(16, 16)
		remove:SetWidth(30)
		remove:SetCallback("OnClick", function()
			table.remove(db.ids, idx)
			db.currencyOptions[id] = nil
			rebuildTracked()
			renderList()
			fullUpdate()
		end)
		row:AddChild(remove)

		listContainer:AddChild(row)
	end
end

local function createAceWindow()
	if aceWindowWidget then
		aceWindowWidget:Show()
		return
	end
	ensureDB()
	local frame = AceGUI:Create("Window")
	aceWindowWidget = frame
	frame:SetTitle((addon.DataPanel and addon.DataPanel.GetStreamOptionsTitle and addon.DataPanel.GetStreamOptionsTitle(stream and stream.meta and stream.meta.title)) or GAMEMENU_OPTIONS)
	frame:SetWidth(280)
	frame:SetHeight(320)
	frame:SetLayout("List")

	db._windowStatus = db._windowStatus or {}
	frame:SetStatusTable(db._windowStatus)
	frame:SetCallback("OnClose", function(widget)
		AceGUI:Release(widget)
		aceWindowWidget = nil
		listContainer = nil
	end)

	local fontSize = AceGUI:Create("Slider")
	fontSize:SetLabel(FONT_SIZE)
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		fullUpdate()
	end)
	frame:AddChild(fontSize)

	local perTip = AceGUI:Create("CheckBox")
	perTip:SetLabel(L["Per-currency tooltips"] or "Per-currency tooltips")
	perTip:SetValue(db.tooltipPerCurrency)
	perTip:SetCallback("OnValueChanged", function(_, _, val)
		db.tooltipPerCurrency = val and true or false
		fullUpdate()
	end)
	frame:AddChild(perTip)

	local showDesc = AceGUI:Create("CheckBox")
	showDesc:SetLabel(L["Show description in tooltip"] or "Show description in tooltip")
	showDesc:SetValue(db.showDescription)
	showDesc:SetCallback("OnValueChanged", function(_, _, val)
		db.showDescription = val and true or false
		fullUpdate()
	end)
	frame:AddChild(showDesc)

	local addGroup = addon.functions.createContainer("SimpleGroup", "Flow")
	local addBox = AceGUI:Create("EditBox")
	addBox:SetLabel(L["Currency ID"] or "Currency ID")
	addBox:SetWidth(150)
	addGroup:AddChild(addBox)
	local addBtn = AceGUI:Create("Button")
	addBtn:SetText(ADD)
	addBtn:SetWidth(60)
	addBtn:SetCallback("OnClick", function()
		local id = tonumber(addBox:GetText())
		if id then
			for _, existing in ipairs(db.ids) do
				if existing == id then
					addBox:SetText("")
					return
				end
			end
			table.insert(db.ids, id)
			rebuildTracked()
			addBox:SetText("")
			renderList()
			fullUpdate()
		end
	end)
	addGroup:AddChild(addBtn)
	frame:AddChild(addGroup)

	listContainer = addon.functions.createContainer("SimpleGroup", "List")
	frame:AddChild(listContainer)
	renderList()

	frame:Show()
end

local iconCache = {} -- [currencyID] = texturePath or fileID
local idToIndex = {} -- [currencyID] = index in parts
local tooltipParts = {} -- [currencyID] = { lines }

local function rebuildTooltip(s)
	s = s or stream
	if db.tooltipPerCurrency then
		s.snapshot.tooltip = nil
		s.snapshot.perCurrency = true
		s.snapshot.showDescription = db.showDescription
		return
	end
	local tips = {}
	for _, id in ipairs(db.ids) do
		local lines = tooltipParts[id]
		if lines then
			for i = 1, #lines do
				tips[#tips + 1] = lines[i]
			end
		end
	end
	if #tips > 0 then
		if tips[#tips] == "" then tips[#tips] = nil end
		local hint = getOptionsHint()
		if hint then
			tips[#tips + 1] = ""
			tips[#tips + 1] = hint
		end
		if #tips > 0 then
			s.snapshot.tooltip = table.concat(tips, "\n")
		else
			s.snapshot.tooltip = hint
		end
	else
		s.snapshot.tooltip = EMPTY_TRACKING_TEXT
	end
	s.snapshot.perCurrency = false
	s.snapshot.showDescription = db.showDescription
end

checkCurrencies = function(s)
	s = s or stream
	ensureDB()
	local size = db.fontSize or 14
	local parts = {}
	for k in pairs(idToIndex) do
		idToIndex[k] = nil
	end
	for k in pairs(tooltipParts) do
		tooltipParts[k] = nil
	end
	for _, id in ipairs(db.ids) do
		local info = C_CurrencyInfo.GetCurrencyInfo(id)
		if info then
			if not iconCache[id] and info.iconFileID then iconCache[id] = info.iconFileID end
			local icon = iconCache[id] or info.iconFileID
			local qty = info.quantity or 0
			local colorCode = HIGHLIGHT_FONT_COLOR_CODE
			if info.useTotalEarnedForMaxQty and info.maxQuantity and info.maxQuantity > 0 then
				local earnedRaw = info.totalEarned or info.trackedQuantity or 0
				if earnedRaw >= info.maxQuantity then colorCode = RED_FONT_COLOR_CODE end
			elseif info.maxQuantity and info.maxQuantity > 0 and qty >= info.maxQuantity then
				colorCode = RED_FONT_COLOR_CODE
			end
			local qtyText = formatCurrencyAmount(id, qty)
			parts[#parts + 1] = {
				id = id,
				text = ("|T%s:%d:%d:0:0|t %s%s%s"):format(icon or 0, size, size, colorCode, qtyText, FONT_COLOR_CODE_CLOSE),
			}
			idToIndex[id] = #parts
			if not db.tooltipPerCurrency then
				local lines = {}
				local color = ITEM_QUALITY_COLORS[info.quality]
				local name = (color and color.hex or "|cffffffff") .. (info.name or ("ID %d"):format(id)) .. "|r"
				lines[#lines + 1] = name
				if db.showDescription and info.description and info.description ~= "" then lines[#lines + 1] = info.description end
				lines[#lines + 1] = ""
				lines[#lines + 1] = CURRENCY_TOTAL:format(HIGHLIGHT_FONT_COLOR_CODE, BreakUpLargeNumbers(qty)) .. FONT_COLOR_CODE_CLOSE
				if info.useTotalEarnedForMaxQty then
					local earnedRaw = info.totalEarned or info.trackedQuantity or 0
					local earned = BreakUpLargeNumbers(earnedRaw)
					if info.maxQuantity and info.maxQuantity > 0 then
						local colorCode2 = earnedRaw >= info.maxQuantity and RED_FONT_COLOR_CODE or HIGHLIGHT_FONT_COLOR_CODE
						lines[#lines + 1] = CURRENCY_SEASON_TOTAL_MAXIMUM:format(colorCode2, earned, BreakUpLargeNumbers(info.maxQuantity)) .. FONT_COLOR_CODE_CLOSE
					else
						lines[#lines + 1] = CURRENCY_SEASON_TOTAL:format(HIGHLIGHT_FONT_COLOR_CODE, earned) .. FONT_COLOR_CODE_CLOSE
					end
				elseif info.maxQuantity and info.maxQuantity > 0 then
					local colorCode2 = qty >= info.maxQuantity and RED_FONT_COLOR_CODE or HIGHLIGHT_FONT_COLOR_CODE
					lines[#lines + 1] = CURRENCY_TOTAL_CAP:format(colorCode2, BreakUpLargeNumbers(qty), BreakUpLargeNumbers(info.maxQuantity)) .. FONT_COLOR_CODE_CLOSE
				end
				lines[#lines + 1] = ""
				tooltipParts[id] = lines
			end
		end
	end
	if #parts > 0 then
		s.snapshot.parts = parts
		s.snapshot.text = nil
	else
		s.snapshot.parts = nil
		s.snapshot.text = EMPTY_TRACKING_TEXT
	end
	s.snapshot.fontSize = size
	rebuildTooltip(s)
end

updateCurrency = function(s, id)
	s = s or stream
	ensureDB()
	local idx = idToIndex[id]
	if not idx then
		fullUpdate(s)
		return
	end
	local info = C_CurrencyInfo.GetCurrencyInfo(id)
	if not info then return end
	if not iconCache[id] and info.iconFileID then iconCache[id] = info.iconFileID end
	local icon = iconCache[id] or info.iconFileID
	local qty = info.quantity or 0
	local colorCode = HIGHLIGHT_FONT_COLOR_CODE
	if info.useTotalEarnedForMaxQty and info.maxQuantity and info.maxQuantity > 0 then
		local earnedRaw = info.totalEarned or info.trackedQuantity or 0
		if earnedRaw >= info.maxQuantity then colorCode = RED_FONT_COLOR_CODE end
	elseif info.maxQuantity and info.maxQuantity > 0 and qty >= info.maxQuantity then
		colorCode = RED_FONT_COLOR_CODE
	end
	local size = db.fontSize or 14
	local qtyText = formatCurrencyAmount(id, qty)
	s.snapshot.parts[idx].text = ("|T%s:%d:%d:0:0|t %s%s%s"):format(icon or 0, size, size, colorCode, qtyText, FONT_COLOR_CODE_CLOSE)
	if not db.tooltipPerCurrency then
		local lines = {}
		local color = ITEM_QUALITY_COLORS[info.quality]
		local name = (color and color.hex or "|cffffffff") .. (info.name or ("ID %d"):format(id)) .. "|r"
		lines[#lines + 1] = name
		if db.showDescription and info.description and info.description ~= "" then lines[#lines + 1] = info.description end
		lines[#lines + 1] = ""
		lines[#lines + 1] = CURRENCY_TOTAL:format(HIGHLIGHT_FONT_COLOR_CODE, BreakUpLargeNumbers(qty)) .. FONT_COLOR_CODE_CLOSE
		if info.useTotalEarnedForMaxQty then
			local earnedRaw = info.totalEarned or info.trackedQuantity or 0
			local earned = BreakUpLargeNumbers(earnedRaw)
			if info.maxQuantity and info.maxQuantity > 0 then
				local colorCode2 = earnedRaw >= info.maxQuantity and RED_FONT_COLOR_CODE or HIGHLIGHT_FONT_COLOR_CODE
				lines[#lines + 1] = CURRENCY_SEASON_TOTAL_MAXIMUM:format(colorCode2, earned, BreakUpLargeNumbers(info.maxQuantity)) .. FONT_COLOR_CODE_CLOSE
			else
				lines[#lines + 1] = CURRENCY_SEASON_TOTAL:format(HIGHLIGHT_FONT_COLOR_CODE, earned) .. FONT_COLOR_CODE_CLOSE
			end
		elseif info.maxQuantity and info.maxQuantity > 0 then
			local colorCode2 = qty >= info.maxQuantity and RED_FONT_COLOR_CODE or HIGHLIGHT_FONT_COLOR_CODE
			lines[#lines + 1] = CURRENCY_TOTAL_CAP:format(colorCode2, BreakUpLargeNumbers(qty), BreakUpLargeNumbers(info.maxQuantity)) .. FONT_COLOR_CODE_CLOSE
		end
		lines[#lines + 1] = ""
		tooltipParts[id] = lines
		rebuildTooltip(s)
	end
	publish(s)
end

local provider = {
	id = "currency",
	version = 1,
	title = CURRENCY,
	update = checkCurrencies,
	events = {
		PLAYER_LOGIN = function(s) fullUpdate(s) end,
		CURRENCY_DISPLAY_UPDATE = function(s, _, currencyType)
			if tracked[currencyType] then updateCurrency(s, currencyType) end
		end,
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
