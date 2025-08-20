-- luacheck: globals EnhanceQoL GAMEMENU_OPTIONS C_CurrencyInfo C_Timer ITEM_QUALITY_COLORS HIGHLIGHT_FONT_COLOR_CODE RED_FONT_COLOR_CODE FONT_COLOR_CODE_CLOSE CURRENCY_SEASON_TOTAL_MAXIMUM CURRENCY_SEASON_TOTAL CURRENCY_TOTAL CURRENCY_TOTAL_CAP BreakUpLargeNumbers UIParent GameTooltip GetCursorPosition GameFontNormal
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream
local tracked = {}
local trackedDirty = true
local measureFont = UIParent:CreateFontString()

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

local updatePending = false
local function RequestUpdateDebounced()
	if updatePending then return end
	updatePending = true
	C_Timer.After(0.05, function()
		updatePending = false
		if stream then addon.DataHub:RequestUpdate(stream) end
	end)
end

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.currency = addon.db.datapanel.currency or {}
	db = addon.db.datapanel.currency
	db.fontSize = db.fontSize or 14
	db.ids = db.ids or {}
	db.tooltipPerCurrency = db.tooltipPerCurrency or false
	if db.showDescription == nil then db.showDescription = true end
	if trackedDirty then rebuildTracked() end
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

		local row = addon.functions.createContainer("SimpleGroup", "Flow")

		local label = AceGUI:Create("Label")
		label:SetText(("%s (%d)"):format(name, id))
		label:SetWidth(160)
		row:AddChild(label)

		if idx > 1 then
			local up = AceGUI:Create("Icon")
			up:SetImage("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up") -- TODO replace placeholder
			up:SetImageSize(16, 16)
			up:SetWidth(30)
			up:SetCallback("OnClick", function()
				db.ids[idx], db.ids[idx - 1] = db.ids[idx - 1], db.ids[idx]
				renderList()
				RequestUpdateDebounced()
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
				RequestUpdateDebounced()
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
			rebuildTracked()
			renderList()
			RequestUpdateDebounced()
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
	frame:SetTitle(GAMEMENU_OPTIONS)
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
	fontSize:SetLabel("Font size")
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		RequestUpdateDebounced()
	end)
	frame:AddChild(fontSize)

	local perTip = AceGUI:Create("CheckBox")
	perTip:SetLabel("Per-currency tooltips")
	perTip:SetValue(db.tooltipPerCurrency)
	perTip:SetCallback("OnValueChanged", function(_, _, val)
		db.tooltipPerCurrency = val and true or false
		RequestUpdateDebounced()
	end)
	frame:AddChild(perTip)

	local showDesc = AceGUI:Create("CheckBox")
	showDesc:SetLabel("Show description in tooltip")
	showDesc:SetValue(db.showDescription)
	showDesc:SetCallback("OnValueChanged", function(_, _, val)
		db.showDescription = val and true or false
		RequestUpdateDebounced()
	end)
	frame:AddChild(showDesc)

	local addGroup = addon.functions.createContainer("SimpleGroup", "Flow")
	local addBox = AceGUI:Create("EditBox")
	addBox:SetLabel("Currency ID")
	addBox:SetWidth(150)
	addGroup:AddChild(addBox)
	local addBtn = AceGUI:Create("Button")
	addBtn:SetText("Add")
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
			RequestUpdateDebounced()
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
local function checkCurrencies(stream)
	ensureDB()
	local size = db.fontSize or 14
	local parts = {}
	local tips = db.tooltipPerCurrency and nil or {}
	local hover = db.tooltipPerCurrency and {} or nil
	local font = (addon.variables and addon.variables.defaultFont) or select(1, GameFontNormal:GetFont())
	measureFont:SetFont(font, size, "OUTLINE")
	measureFont:SetText(" ")
	local spaceWidth = measureFont:GetStringWidth()
	local x = 0
	for _, id in ipairs(db.ids) do
		local info = C_CurrencyInfo.GetCurrencyInfo(id)
		if info then
			if not iconCache[id] and info.iconFileID then iconCache[id] = info.iconFileID end
			local icon = iconCache[id] or info.iconFileID
			local qty = info.quantity or 0
			local colorCode = HIGHLIGHT_FONT_COLOR_CODE
			if info.useTotalEarnedForMaxQty and info.maxQuantity and info.maxQuantity > 0 then
				local earnedRaw = info.trackedQuantity or info.totalEarned or 0
				if earnedRaw >= info.maxQuantity then colorCode = RED_FONT_COLOR_CODE end
			elseif info.maxQuantity and info.maxQuantity > 0 and qty >= info.maxQuantity then
				colorCode = RED_FONT_COLOR_CODE
			end
			parts[#parts + 1] = ("|T%s:%d:%d:0:0|t %s%d%s"):format(icon or 0, size, size, colorCode, qty, FONT_COLOR_CODE_CLOSE)
			if hover then
				if #hover > 0 then x = x + spaceWidth end
				local start = x
				measureFont:SetText(tostring(qty))
				local numWidth = measureFont:GetStringWidth()
				x = x + size + spaceWidth + numWidth
				hover[#hover + 1] = { id = id, start = start, stop = x }
			else
				local color = ITEM_QUALITY_COLORS[info.quality]
				local name = (color and color.hex or "|cffffffff") .. (info.name or ("ID %d"):format(id)) .. "|r"
				tips[#tips + 1] = name
				if db.showDescription and info.description and info.description ~= "" then tips[#tips + 1] = info.description end
				tips[#tips + 1] = ""
				tips[#tips + 1] = CURRENCY_TOTAL:format(HIGHLIGHT_FONT_COLOR_CODE, BreakUpLargeNumbers(qty)) .. FONT_COLOR_CODE_CLOSE
				if info.useTotalEarnedForMaxQty then
					local earnedRaw = info.trackedQuantity or info.totalEarned or 0
					local earned = BreakUpLargeNumbers(earnedRaw)
					if info.maxQuantity and info.maxQuantity > 0 then
						local colorCode2 = earnedRaw >= info.maxQuantity and RED_FONT_COLOR_CODE or HIGHLIGHT_FONT_COLOR_CODE
						tips[#tips + 1] = CURRENCY_SEASON_TOTAL_MAXIMUM:format(colorCode2, earned, BreakUpLargeNumbers(info.maxQuantity)) .. FONT_COLOR_CODE_CLOSE
					else
						tips[#tips + 1] = CURRENCY_SEASON_TOTAL:format(HIGHLIGHT_FONT_COLOR_CODE, earned) .. FONT_COLOR_CODE_CLOSE
					end
				elseif info.maxQuantity and info.maxQuantity > 0 then
					local colorCode2 = qty >= info.maxQuantity and RED_FONT_COLOR_CODE or HIGHLIGHT_FONT_COLOR_CODE
					tips[#tips + 1] = CURRENCY_TOTAL_CAP:format(colorCode2, BreakUpLargeNumbers(qty), BreakUpLargeNumbers(info.maxQuantity)) .. FONT_COLOR_CODE_CLOSE
				end
				tips[#tips + 1] = ""
			end
		end
	end

	local newText
	if #parts > 0 then
		newText = table.concat(parts, " ")
	else
		newText = L["Right-Click for options"]
	end
	if stream.snapshot.text ~= newText or stream.snapshot.fontSize ~= size then
		stream.snapshot.text = newText
		stream.snapshot.fontSize = size
	end
	stream.snapshot.hover = hover
	if tips then
		if #tips > 0 then
			if tips[#tips] == "" then tips[#tips] = nil end
			tips[#tips + 1] = ""
			tips[#tips + 1] = L["Right-Click for options"]
			stream.snapshot.tooltip = table.concat(tips, "\n")
		else
			stream.snapshot.tooltip = L["Right-Click for options"]
		end
	else
		stream.snapshot.tooltip = L["Right-Click for options"]
	end
end

local provider = {
	id = "currency",
	version = 1,
	title = "Currencies",
	update = checkCurrencies,
	events = {
		PLAYER_LOGIN = function() RequestUpdateDebounced() end,
		CURRENCY_DISPLAY_UPDATE = function(_, currencyType)
			ensureDB()
			if tracked[currencyType] then RequestUpdateDebounced() end
		end,
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
	OnMouseEnter = function(b)
		local tip = GameTooltip
		tip:ClearLines()
		tip:SetOwner(b, "ANCHOR_TOPLEFT")

		local hover = stream.snapshot and stream.snapshot.hover
		if hover and #hover > 0 then
			local mx = GetCursorPosition()
			local scale = b:GetEffectiveScale()
			mx = mx / scale - b:GetLeft()
			for _, h in ipairs(hover) do
				if mx >= h.start and mx <= h.stop then
					tip:SetCurrencyByID(h.id)
					tip:AddLine(("ID %d"):format(h.id))
					tip:AddLine(" ")
					break
				end
			end
			tip:AddLine(L["Right-Click for options"])
		elseif stream.snapshot and stream.snapshot.tooltip then
			for line in string.gmatch(stream.snapshot.tooltip, "[^\n]+") do
				tip:AddLine(line)
			end
		else
			tip:AddLine(L["Right-Click for options"])
		end
		tip:Show()
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
