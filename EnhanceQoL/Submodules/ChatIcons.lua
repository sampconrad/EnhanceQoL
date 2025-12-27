local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.ChatIcons = addon.ChatIcons or {}
local ChatIcons = addon.ChatIcons

local ICON_SIZE = 12
local CURRENCY_LINK_PATTERN = "(|Hcurrency:(%d+)[^|]*|h%[[^%]]+%]|h%|r)"
local ITEM_LINK_PATTERN = "|Hitem:.-|h%[.-%]|h|r"

local ITEMLINK_EVENTS_FALLBACK = {
	"CHAT_MSG_LOOT",
	"CHAT_MSG_CURRENCY",
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_COMMUNITIES_CHANNEL",
	"CHAT_MSG_SAY",
	"CHAT_MSG_YELL",
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_BN_WHISPER",
	"CHAT_MSG_BN_WHISPER_INFORM",
	"CHAT_MSG_GUILD",
	"CHAT_MSG_OFFICER",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING",
	"CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER",
	"CHAT_MSG_BATTLEGROUND",
	"CHAT_MSG_BATTLEGROUND_LEADER",
	"CHAT_MSG_EMOTE",
	"CHAT_MSG_TEXT_EMOTE",
	"CHAT_MSG_SYSTEM",
	"CHAT_MSG_ACHIEVEMENT",
	"CHAT_MSG_GUILD_ACHIEVEMENT",
	"CHAT_MSG_GUILD_ITEM_LOOTED",
}

local tonumber = tonumber
local format = string.format
local GetDetailedItemLevelInfo = GetDetailedItemLevelInfo or (C_Item and C_Item.GetDetailedItemLevelInfo)
local GetItemInfo = C_Item and C_Item.GetItemInfo

local function GetItemTexture(link)
	if not link then return nil end

	if GetItemIcon then
		local ok, texture = pcall(GetItemIcon, link)
		if ok and texture then return texture end
	end

	if C_Item and C_Item.GetItemIconByID then
		local itemID = link:match("item:(%d+)")
		if itemID then return C_Item.GetItemIconByID(tonumber(itemID)) end
	end

	return nil
end

local function AppendIcon(texture, link)
	if not texture then return link end
	return format("|T%s:%d|t%s", texture, ICON_SIZE, link)
end

local function FormatItemLink(link)
	return AppendIcon(GetItemTexture(link), link)
end

local function BuildItemLinkEvents()
	local events = {}
	if type(ChatTypeGroup) == "table" then
		for _, group in pairs(ChatTypeGroup) do
			if type(group) == "table" then
				for _, event in pairs(group) do
					events[event] = true
				end
			end
		end
	end
	for _, event in ipairs(ITEMLINK_EVENTS_FALLBACK) do
		events[event] = true
	end
	return events
end

local function GetItemLevelAndEquipLoc(link)
	local level
	if GetDetailedItemLevelInfo then level = GetDetailedItemLevelInfo(link) end

	local equipLoc
	if GetItemInfo then
		local _, _, _, baseLevel, _, _, _, _, itemEquipLoc = GetItemInfo(link)
		equipLoc = itemEquipLoc
		if not level or level == 0 then level = baseLevel end
	end

	if level and level > 0 then return level, equipLoc end
	return nil, equipLoc
end

local function FormatItemLinkWithLevel(link)
	if not ChatIcons.itemLevelEnabled then return link end

	local prefix, label, suffix = link:match("^(|Hitem:[^|]+|h)%[(.-)%](|h|r)$")
	if not prefix or not label or not suffix then return link end

	local level, equipLoc = GetItemLevelAndEquipLoc(link)
	if not level then return link end
	if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" then return link end

	local parts = {}
	if ChatIcons.itemLevelShowLocation and equipLoc and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" and _G[equipLoc] then
		parts[#parts + 1] = _G[equipLoc]
	end
	parts[#parts + 1] = tostring(level)

	local suffixText = table.concat(parts, " ")
	if suffixText == "" then return link end

	return prefix .. "[" .. label .. " (" .. suffixText .. ")]" .. suffix
end

local function FormatCurrencyLink(link, id)
	id = tonumber(id)
	if not id then return link end
	if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyInfo then return link end

	local info = C_CurrencyInfo.GetCurrencyInfo(id)
	local texture = info and (info.iconFileID or info.icon)
	return AppendIcon(texture, link)
end

local function FilterChatMessage(_, event, message, ...)
	if type(message) ~= "string" or message == "" then return false end

	if ChatIcons.enabled and event == "CHAT_MSG_LOOT" then
		message = message:gsub(ITEM_LINK_PATTERN, FormatItemLink)
	end
	if ChatIcons.enabled and (event == "CHAT_MSG_LOOT" or event == "CHAT_MSG_CURRENCY") then
		message = message:gsub(CURRENCY_LINK_PATTERN, FormatCurrencyLink)
	end
	if ChatIcons.itemLevelEnabled then
		message = message:gsub(ITEM_LINK_PATTERN, FormatItemLinkWithLevel)
	end

	return false, message, ...
end

ChatIcons.Filter = ChatIcons.Filter or FilterChatMessage
ChatIcons.enabled = ChatIcons.enabled or false
ChatIcons.itemLevelEnabled = ChatIcons.itemLevelEnabled or false
ChatIcons.itemLevelShowLocation = ChatIcons.itemLevelShowLocation or false
ChatIcons.registeredEvents = ChatIcons.registeredEvents or {}

function ChatIcons:UpdateFilters()
	local needed = {}
	if self.itemLevelEnabled then
		self.itemLinkEvents = self.itemLinkEvents or BuildItemLinkEvents()
		for event in pairs(self.itemLinkEvents) do
			needed[event] = true
		end
	end
	if self.enabled then
		needed["CHAT_MSG_LOOT"] = true
		needed["CHAT_MSG_CURRENCY"] = true
	end

	for event in pairs(self.registeredEvents) do
		if not needed[event] then
			ChatFrame_RemoveMessageEventFilter(event, self.Filter)
			self.registeredEvents[event] = nil
		end
	end
	for event in pairs(needed) do
		if not self.registeredEvents[event] then
			ChatFrame_AddMessageEventFilter(event, self.Filter)
			self.registeredEvents[event] = true
		end
	end
end

function ChatIcons:SetEnabled(enabled)
	self.enabled = enabled and true or false
	self:UpdateFilters()
end

function ChatIcons:SetItemLevelEnabled(enabled)
	self.itemLevelEnabled = enabled and true or false
	self.itemLevelShowLocation = addon.db and addon.db.chatShowItemLevelLocation or self.itemLevelShowLocation
	self:UpdateFilters()
end

function ChatIcons:SetItemLevelLocation(enabled)
	self.itemLevelShowLocation = enabled and true or false
end
