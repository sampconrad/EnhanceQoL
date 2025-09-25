local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = addon.L
local MU = MenuUtil

local Mailbox = addon.Mailbox or {}
addon.Mailbox = Mailbox

Mailbox.enabled = Mailbox.enabled or false
Mailbox.frame = Mailbox.frame or nil
Mailbox.searchText = Mailbox.searchText or ""
Mailbox.hooked = Mailbox.hooked or false
Mailbox.eventFrame = Mailbox.eventFrame or nil
Mailbox.rows = Mailbox.rows or {}
Mailbox.filtered = Mailbox.filtered or {}
Mailbox.sortKey = Mailbox.sortKey or "name"
Mailbox.sortAsc = Mailbox.sortAsc ~= false -- default true
Mailbox.seeded = Mailbox.seeded or false

local ROW_HEIGHT = 20
-- Effective content width equals 222 (see XML). Allocate columns conservatively to avoid clipping
local widths = { 130, 92 } -- name, server (sum=222)

local function ensureDB()
	if not addon or not addon.db then return end
	if addon.functions and addon.functions.InitDBValue then
		addon.functions.InitDBValue("enableMailboxAddressBook", false)
		addon.functions.InitDBValue("mailboxContacts", {})
	else
		addon.db.enableMailboxAddressBook = addon.db.enableMailboxAddressBook or false
		addon.db.mailboxContacts = addon.db.mailboxContacts or {}
	end
end

local function getClassColor(class)
	local tbl = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS) or {}
	local c = tbl[class] or { r = 1, g = 1, b = 1 }
	return c.r or 1, c.g or 1, c.b or 1
end

function Mailbox:AddSelfToContacts()
	ensureDB()
	if not addon.db.enableMailboxAddressBook then return end

	local name, realm = UnitName("player"), GetRealmName()
	if not name or name == "" then return end
	realm = realm or ""
	local class = select(2, UnitClass("player")) or "PRIEST"
	local r, g, b = getClassColor(class)
	local key = string.format("%s-%s", name, realm)

	local rec = addon.db.mailboxContacts[key] or {}
	rec.name = name
	rec.realm = realm
	rec.class = class
	rec.color = { r = r, g = g, b = b }
	addon.db.mailboxContacts[key] = rec
end

local function filteredContacts()
	ensureDB()
	local list = {}
	local needle = (Mailbox.searchText or ""):lower()
	for key, rec in pairs(addon.db.mailboxContacts) do
		local display = key
		local matchStr = (rec.name or "") .. "-" .. (rec.realm or "")
		if needle == "" or string.find(matchStr:lower(), needle, 1, true) then
			local r, g, b = 1, 1, 1
			if rec.class then
				r, g, b = getClassColor(rec.class)
			end
			table.insert(list, {
				key = key,
				display = string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, display),
				sortKey = (rec.name or key):lower(),
			})
		end
	end
	table.sort(list, function(a, b) return a.sortKey < b.sortKey end)
	return list
end

-- HybridScroll row mixin
local RowMixin = {}
function RowMixin:OnAcquired()
	if self.initialized then return end
	self.bg = self:CreateTexture(nil, "BACKGROUND")
	self.bg:SetAllPoints(self)
	self.bg:SetColorTexture(0, 0, 0, 0)

	self.cols = {}
	local x = 0
	for i, w in ipairs(widths) do
		local fs = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", x, 0)
		fs:SetWidth(w)
		fs:SetJustifyH("LEFT")
		self.cols[i] = fs
		x = x + w
	end
	self:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight")
	self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	self:SetScript("OnClick", function(btn, mouseButton) btn:OnClick(mouseButton) end)
	self.initialized = true
end

function RowMixin:Init(elementData)
	self.key = elementData.key
	self.cols[1]:SetText(elementData.nameColored or elementData.name or "")
	self.cols[2]:SetText(elementData.realm or "")
end

function RowMixin:OnClick(button)
	if button == "RightButton" then
		local key = self.key
		if not key then return end
		MU.CreateContextMenu(self, function(_, root)
			root:CreateTitle(key)
			root:CreateButton(REMOVE, function()
				if addon.db and addon.db.mailboxContacts and addon.db.mailboxContacts[key] then
					addon.db.mailboxContacts[key] = nil
					if addon.Mailbox and addon.Mailbox.RefreshList then addon.Mailbox:RefreshList(true) end
				end
			end)
		end)
		return
	end

	if SendMailNameEditBox and self.key then
		SendMailNameEditBox:SetText(self.key)
		SendMailNameEditBox:HighlightText(0, 0)
		SendMailNameEditBox:ClearFocus()
	end
end

function Mailbox:UpdateVisibility()
	if not self.enabled then
		if self.frame then self.frame:Hide() end
		return
	end
	if not MailFrame then return end
	if not self.frame then self.frame = _G.EQOLMailboxFrame end

	local shouldShow = MailFrame:IsShown() and (SendMailFrame and SendMailFrame:IsShown())
	if shouldShow then
		self.frame:Show()
		-- Match MailFrame height to avoid awkward gaps
		if MailFrame and self.frame then self.frame:SetHeight(MailFrame:GetHeight() or 430) end
		if MailFrame and self.frame then self.frame:SetFrameStrata(MailFrame:GetFrameStrata() or "MEDIUM") end
		-- Make sure we have visible rows once the frame has a real height
		if not self.rows or #self.rows == 0 then
			if self.EnsureRows then self:EnsureRows() end
		end
		self:RefreshList(true)
	else
		self.frame:Hide()
	end
end

local function ensureHooks()
	if Mailbox.hooked then return end
	Mailbox.hooked = true
	-- Events for show/hide
	Mailbox.eventFrame = Mailbox.eventFrame or CreateFrame("Frame")
	Mailbox.eventFrame:RegisterEvent("MAIL_SHOW")
	Mailbox.eventFrame:RegisterEvent("MAIL_CLOSED")
	Mailbox.eventFrame:RegisterEvent("MAIL_SEND_INFO_UPDATE")
	Mailbox.eventFrame:SetScript("OnEvent", function(_, event)
		if event == "MAIL_SHOW" then
			C_Timer.After(0, function()
				if addon.Mailbox then addon.Mailbox:UpdateVisibility() end
			end)
		elseif event == "MAIL_SEND_INFO_UPDATE" then
			if addon.Mailbox then addon.Mailbox:RefreshList() end
		else -- MAIL_CLOSED
			if addon.Mailbox and addon.Mailbox.frame then addon.Mailbox.frame:Hide() end
		end
	end)

	-- Also watch tab changes to update visibility
	hooksecurefunc("MailFrameTab_OnClick", function()
		if addon.Mailbox then addon.Mailbox:UpdateVisibility() end
	end)
end

function Mailbox:SetEnabled(v)
	ensureDB()
	self.enabled = v and true or false
	if self.enabled then
		-- Immediately add current character on enable
		self:AddSelfToContacts()
		-- Seed from moneyTracker if present and mailbox is empty
		if addon.db and addon.db.mailboxContacts and next(addon.db.mailboxContacts) == nil and type(addon.db.moneyTracker) == "table" then
			for guid, info in pairs(addon.db.moneyTracker) do
				if type(info) == "table" and info.name then
					local name = info.name
					local realm = info.realm or GetRealmName() or ""
					local class = info.class or select(2, UnitClass("player"))
					local r, g, b = getClassColor(class)
					local key = string.format("%s-%s", name, realm)
					addon.db.mailboxContacts[key] = {
						name = name,
						realm = realm,
						class = class,
						color = { r = r, g = g, b = b },
					}
				end
			end
		end
		ensureHooks()
		-- If frame is loaded via XML OnLoad we already have it; else it will appear later
		self:UpdateVisibility()
	else
		if self.frame then self.frame:Hide() end
	end
end

-- Build filtered + sorted table from saved contacts
local function BuildFiltered()
	if not addon or not addon.db then
		wipe(Mailbox.filtered)
		return
	end
	-- If contacts are empty but we have moneyTracker info, import once
	if addon.db.mailboxContacts == nil then addon.db.mailboxContacts = {} end
	if not Mailbox.seeded and next(addon.db.mailboxContacts) == nil and type(addon.db.moneyTracker) == "table" then
		for _, info in pairs(addon.db.moneyTracker) do
			if type(info) == "table" and info.name then
				local name = info.name
				local realm = info.realm or GetRealmName() or ""
				local class = info.class or select(2, UnitClass("player"))
				local r, g, b = getClassColor(class)
				local key = string.format("%s-%s", name, realm)
				addon.db.mailboxContacts[key] = {
					name = name,
					realm = realm,
					class = class,
					color = { r = r, g = g, b = b },
				}
			end
		end
		Mailbox.seeded = true
	end
	if not addon.db.mailboxContacts then
		wipe(Mailbox.filtered)
		return
	end
	wipe(Mailbox.filtered)
	-- determine own character to hide from list (normalize realms by removing spaces)
	local function lowerNoSpaces(s) return (s or ""):lower():gsub("%s", "") end
	local meName, meRealm = UnitFullName("player")
	meRealm = meRealm or (GetRealmName() or "")
	local myKeyLower = meName and string.format("%s-%s", meName, meRealm):lower() or nil
	local myKeyLowerNS = meName and string.format("%s-%s", meName, meRealm) or nil
	myKeyLowerNS = lowerNoSpaces(myKeyLowerNS)
	local needle = (Mailbox.searchText or ""):lower()
	for key, rec in pairs(addon.db.mailboxContacts) do
		-- skip own character (compare raw-lower and also lower-without-spaces for realm)
		local skip = false
		if myKeyLower and key and key:lower() == myKeyLower then
			skip = true
		else
			local keyNS = lowerNoSpaces(key)
			if myKeyLowerNS and keyNS == myKeyLowerNS then
				skip = true
			elseif meName and rec then
				local rn = rec.name and rec.name:lower()
				local rr = lowerNoSpaces(rec.realm)
				if rn and rn == meName:lower() and rr == lowerNoSpaces(meRealm) then skip = true end
			end
		end
		if skip then
		-- continue
		else
			local name = rec.name or key
			local realm = rec.realm or ""
			local class = rec.class or ""
			local r, g, b = getClassColor(class)
			local displayName = string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, name)

			local match
			if needle == "" then
				match = true
			else
				if string.find(name:lower(), needle, 1, true) then match = true end
				if not match and realm ~= "" and string.find(realm:lower(), needle, 1, true) then match = true end
			end
			if match then table.insert(Mailbox.filtered, {
				key = key,
				name = name,
				nameColored = displayName,
				realm = realm,
			}) end
		end
	end

	table.sort(Mailbox.filtered, function(a, b)
		local sk = Mailbox.sortKey
		local av, bv
		if sk == "name" then
			av = a.name:lower()
			bv = b.name:lower()
			if av == bv then
				av = a.realm:lower()
				bv = b.realm:lower()
			end
		elseif sk == "realm" then
			av = (a.realm or ""):lower()
			bv = (b.realm or ""):lower()
		else -- default
			av = a.name:lower()
			bv = b.name:lower()
		end
		if Mailbox.sortAsc then
			return av < bv
		else
			return av > bv
		end
	end)
end

function Mailbox:UpdateRows()
	if not self.scrollFrame or not self.rows then return end
	local buttons = self.rows
	local offset = HybridScrollFrame_GetOffset(self.scrollFrame)
	for i = 1, #buttons do
		local idx = i + offset
		local row = buttons[i]
		if self.filtered[idx] then
			row:Show()
			row:Init(self.filtered[idx])
		else
			row:Hide()
		end
	end
	local displayed = self.scrollFrame:GetHeight() or (10 * ROW_HEIGHT)
	HybridScrollFrame_Update(self.scrollFrame, #self.filtered * ROW_HEIGHT, displayed)
end

function Mailbox:RefreshList(rebuild)
	if rebuild then BuildFiltered() end
	self:UpdateRows()
end

-- Frame OnLoad from XML
function EQOLMailboxFrame_OnLoad(frame)
	ensureDB()
	Mailbox.frame = frame
	Mailbox.searchBox = _G[frame:GetName() .. "SearchBox"]
	Mailbox.header = _G[frame:GetName() .. "Header"]
	Mailbox.scrollFrame = _G[frame:GetName() .. "ScrollFrame"]
	Mailbox.scrollFrame.scrollBar = _G[frame:GetName() .. "ScrollFrameScrollBar"]

	-- Title and search label (like Ignore frame)
	frame:SetFrameStrata("DIALOG")
	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.title:SetPoint("TOP", frame, "TOP", 0, -6)
	frame.title:SetText((L and L["MailboxWindowTitle"]) or "Address Book")
	frame.searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	if Mailbox.searchBox then
		frame.searchLabel:SetPoint("RIGHT", Mailbox.searchBox, "LEFT", -5, 0)
		frame.searchLabel:SetText(SEARCH .. ":")
	end

	-- Column headers
	local columns = {
		{ key = "name", text = NAME, width = widths[1], idx = 1 },
		{ key = "realm", text = (FRIENDS_LIST_REALM or "Realm"):gsub(":%s*$", ""), width = widths[2], idx = 2 },
	}
	local c = 1
	for _, col in ipairs(columns) do
		local btn = _G[Mailbox.header:GetName() .. "Col" .. c]
		if btn then
			btn:SetWidth(col.width)
			local middle = _G[btn:GetName() .. "Middle"]
			if middle then middle:SetWidth(col.width - 9) end
			btn:SetText(col.text)
			btn.sortKey = col.key
			btn:SetScript("OnClick", function(self)
				if Mailbox.sortKey ~= self.sortKey then
					Mailbox.sortKey = self.sortKey
					Mailbox.sortAsc = true
				else
					Mailbox.sortAsc = not Mailbox.sortAsc
				end
				BuildFiltered()
				Mailbox:UpdateRows()
			end)
		end
		c = c + 1
	end

	function Mailbox:EnsureRows()
		if not self.scrollFrame then return end
		local have = (self.rows and #self.rows) or 0
		local height = self.scrollFrame:GetHeight() or 0
		-- If we only have 0/1 buttons but the frame is tall, rebuild buttons after the frame is visible
		if have <= 1 and height > (ROW_HEIGHT * 4) then
			-- Force re-create by clearing the cached buttons table
			self.scrollFrame.buttons = nil
		elseif have > 1 then
			return
		end

		HybridScrollFrame_CreateButtons(self.scrollFrame, "EQOLMailboxRowTemplate", 5, -6)
		self.rows = self.scrollFrame.buttons or {}
		self.scrollFrame.rows = self.rows
		for _, row in ipairs(self.rows) do
			Mixin(row, RowMixin)
			row:OnAcquired()
		end
		self.scrollFrame.update = function() self:UpdateRows() end
	end
	Mailbox:EnsureRows()

	-- Search box handler
	if Mailbox.searchBox then Mailbox.searchBox:SetScript("OnTextChanged", function(self)
		Mailbox.searchText = self:GetText() or ""
		BuildFiltered()
		Mailbox:UpdateRows()
	end) end

	-- Initial build
	BuildFiltered()
	-- Ensure rows even if OnLoad sizing was 0
	if not Mailbox.rows or #Mailbox.rows == 0 then C_Timer.After(0, function()
		Mailbox:EnsureRows()
		Mailbox:UpdateRows()
	end) end
	Mailbox:UpdateRows()
	Mailbox:UpdateVisibility()
end

-- Called from XML OnShow to finalize rows after the frame has a real height
function EQOLMailboxFrame_OnShow(frame)
	if not addon or not addon.Mailbox then return end
	local mb = addon.Mailbox
	mb:EnsureRows()
	mb:RefreshList(true)
end

-- Register a local login listener to add the player if enabled
if not Mailbox.loginFrame then
	Mailbox.loginFrame = CreateFrame("Frame")
	Mailbox.loginFrame:RegisterEvent("PLAYER_LOGIN")
	Mailbox.loginFrame:SetScript("OnEvent", function()
		ensureDB()
		if addon.db.enableMailboxAddressBook then Mailbox:AddSelfToContacts() end
		-- Apply enable state once UI exists
		Mailbox:SetEnabled(addon.db.enableMailboxAddressBook)
	end)
end
