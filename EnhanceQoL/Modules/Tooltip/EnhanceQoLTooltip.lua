local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Tooltip")

local frameLoad = CreateFrame("Frame")

-- ==== Inspect cache (spec/ilvl/score) ====
local InspectCache = {} -- [guid] = { ilvl, specName, score, last }
local CACHE_TTL = 30 -- seconds
local INSPECT_REQUEST_COOLDOWN = 1.25 -- avoid spamming NotifyInspect while hovering
local INSPECT_PENDING_TIMEOUT = 2.0 -- fail-safe in case INSPECT_READY is dropped
local function now() return GetTime() end

local function isSecret(value) return issecretvalue and issecretvalue(value) end

local function isTooltipRestricted() return addon.functions and addon.functions.isRestrictedContent and addon.functions.isRestrictedContent(true) end

local function safeEquals(a, b)
	if a == nil or b == nil then return false end
	if isSecret(a) or isSecret(b) then return false end
	return a == b
end

local function safeFind(text, pattern, plain)
	if not text or isSecret(text) then return nil end
	if pattern == nil or isSecret(pattern) then return nil end
	if type(text) ~= "string" or type(pattern) ~= "string" then return nil end
	return string.find(text, pattern, 1, plain)
end

local function safeMatch(text, pattern)
	if not text or isSecret(text) then return nil end
	if pattern == nil or isSecret(pattern) then return nil end
	if type(text) ~= "string" or type(pattern) ~= "string" then return nil end
	return string.match(text, pattern)
end

local function GetUnitTokenFromTooltip(tt)
	if addon.variables.isMidnight then return "mouseover" end
	local owner = tt and tt:GetOwner()
	if owner then
		if owner.unit then return owner.unit end
		if owner.GetAttribute then
			local u = owner:GetAttribute("unit")
			if u then return u end
		end
	end
	local _, unit = tt:GetUnit()
	return unit
end

-- no compact score formatting needed anymore

local pendingGUID, pendingUnit, pendingRequestedAt
local EnsureUnitData -- forward declaration
local fInspect = CreateFrame("Frame")

local function IsInspectUIBusy()
	if InspectFrame and InspectFrame.IsShown and InspectFrame:IsShown() then return true end
	if PlayerSpellsFrame and PlayerSpellsFrame.IsInspecting and PlayerSpellsFrame:IsInspecting() then return true end
	return false
end

local function ClearTooltipInspectState() pendingGUID, pendingUnit, pendingRequestedAt = nil, nil, nil end

local function FinishTooltipInspectRequest()
	ClearTooltipInspectState()
	if C_Timer and C_Timer.After and ClearInspectPlayer and not IsInspectUIBusy() then
		C_Timer.After(0, function()
			if ClearInspectPlayer and not IsInspectUIBusy() then ClearInspectPlayer() end
		end)
	end
end

-- Decide whether we need INSPECT_READY at all (opt-in)
local function ShouldUseInspectFeature() return (addon.db and (addon.db["TooltipUnitShowSpec"] or addon.db["TooltipUnitShowItemLevel"])) or false end

local function IsConfiguredModifierDown()
	local mod = addon.db and addon.db["TooltipMythicScoreModifier"] or "SHIFT"
	return (mod == "SHIFT" and IsShiftKeyDown()) or (mod == "ALT" and IsAltKeyDown()) or (mod == "CTRL" and IsControlKeyDown())
end

local function IsTooltipHideOverrideActive()
	if not addon.db or not addon.db["TooltipHideOverrideEnabled"] then return false end
	local mod = addon.db["TooltipHideOverrideModifier"] or "CTRL"
	if mod == "SHIFT" then return IsShiftKeyDown() end
	if mod == "ALT" then return IsAltKeyDown() end
	if mod == "CTRL" then return IsControlKeyDown() end
	return false
end

local function DoesKeyMatchConfiguredModifier(key)
	if not key or not addon.db then return false end
	local mod = addon.db["TooltipMythicScoreModifier"] or "SHIFT"
	if mod == "SHIFT" then return key == "LSHIFT" or key == "RSHIFT" end
	if mod == "ALT" then return key == "LALT" or key == "RALT" end
	if mod == "CTRL" then return key == "LCTRL" or key == "RCTRL" end
	return false
end

local function UpdateInspectEventRegistration()
	if not addon.db then return end
	if not fInspect then return end
	fInspect:UnregisterEvent("INSPECT_READY")
	fInspect:UnregisterEvent("MODIFIER_STATE_CHANGED")
	if ShouldUseInspectFeature() then
		fInspect:RegisterEvent("INSPECT_READY")
		if addon.db["TooltipUnitInspectRequireModifier"] then fInspect:RegisterEvent("MODIFIER_STATE_CHANGED") end
	else
		ClearTooltipInspectState()
	end
end

addon.functions.UpdateInspectEventRegistration = UpdateInspectEventRegistration

local function IsValidSpellIdentifier(id)
	local idType = type(id)
	return idType == "number" or idType == "string"
end

local function FindLineIndexByLabel(tt, label)
	local name = tt:GetName()
	for i = 1, tt:NumLines() do
		local left = _G[name .. "TextLeft" .. i]
		local text = left and left:GetText()
		if safeFind(text, label, true) then return i end
	end
	return nil
end

local function RefreshTooltipForGUID(guid)
	if not GameTooltip or not GameTooltip:IsShown() then return end
	local tt = GameTooltip
	local unit = GetUnitTokenFromTooltip(tt)
	if not unit then return end
	local uGuid = UnitGUID(unit)
	if not safeEquals(uGuid, guid) then return end
	local c = InspectCache[guid]
	if not c then return end

	local showSpec = addon.db["TooltipUnitShowSpec"] and c.specName
	local showIlvl = addon.db["TooltipUnitShowItemLevel"] and c.ilvl
	if addon.db["TooltipUnitInspectRequireModifier"] and not IsConfiguredModifierDown() then
		showSpec = false
		showIlvl = false
	end
	if not showSpec and not showIlvl then return end

	local labelSpec = SPECIALIZATION
	local labelIlvl = STAT_AVERAGE_ITEM_LEVEL or ITEM_LEVEL or "Item Level"

	local haveSpecLine = FindLineIndexByLabel(tt, labelSpec)
	local haveIlvlLine = FindLineIndexByLabel(tt, labelIlvl)

	local addedAny = false
	if showSpec then
		if haveSpecLine then
			local right = _G[tt:GetName() .. "TextRight" .. haveSpecLine]
			if right then right:SetText(c.specName) end
		else
			if not (haveSpecLine or haveIlvlLine) then tt:AddLine(" ") end
			tt:AddDoubleLine("|cffffd200" .. labelSpec .. "|r", c.specName)
			addedAny = true
		end
	end
	if showIlvl then
		if haveIlvlLine then
			local right = _G[tt:GetName() .. "TextRight" .. haveIlvlLine]
			if right then right:SetText(tostring(c.ilvl)) end
		else
			if not (haveSpecLine or haveIlvlLine) and not addedAny and not showSpec then tt:AddLine(" ") end
			tt:AddDoubleLine("|cffffd200" .. labelIlvl .. "|r", tostring(c.ilvl))
			addedAny = true
		end
	end
	if addedAny then tt:Show() end
end

fInspect:SetScript("OnEvent", function(_, ev, arg1, arg2)
	if ev == "INSPECT_READY" then
		local guid = arg1
		if isSecret(guid) or isSecret(arg1) or isSecret(arg2) or isSecret(pendingGUID) then return end
		if not safeEquals(guid, pendingGUID) then return end
		local unitGuid = pendingUnit and UnitGUID(pendingUnit)
		if isSecret(unitGuid) or isSecret(pendingUnit) then
			FinishTooltipInspectRequest()
			return
		end
		local unit = (unitGuid == guid) and pendingUnit or nil
		FinishTooltipInspectRequest()
		if not unit or not UnitExists(unit) then return end

		local ilvl
		if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
			ilvl = C_PaperDollInfo.GetInspectItemLevel(unit)
			if ilvl then ilvl = tonumber(string.format("%.1f", ilvl)) end
		end
		local specID = GetInspectSpecialization and GetInspectSpecialization(unit)
		local specName
		if specID and specID > 0 then
			local _, name = GetSpecializationInfoByID(specID)
			specName = name
		end
		local score = 0
		if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
			local s = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
			score = s and s.currentSeasonScore or score
		end

		local c = InspectCache[guid] or {}
		c.ilvl = ilvl
		c.specName = specName
		c.score = score
		c.last = now()
		InspectCache[guid] = c

		-- If the currently shown tooltip is for this unit, update it immediately
		RefreshTooltipForGUID(guid)
	elseif ev == "MODIFIER_STATE_CHANGED" then
		if not addon.db or not addon.db["TooltipUnitInspectRequireModifier"] then return end
		if not ShouldUseInspectFeature() then return end
		local key, state = arg1, arg2
		if state ~= 1 then return end
		if not DoesKeyMatchConfiguredModifier(key) then return end
		if not IsConfiguredModifierDown() then return end
		if not GameTooltip or not GameTooltip:IsShown() then return end
		local unit = GetUnitTokenFromTooltip(GameTooltip)
		if not unit or not UnitIsPlayer(unit) then return end
		EnsureUnitData(unit)
		local guid = UnitGUID(unit)
		if guid then RefreshTooltipForGUID(guid) end
	end
end)

EnsureUnitData = function(unit)
	if not unit or not UnitIsPlayer(unit) then return end
	if isTooltipRestricted() then return end
	-- Only fetch if at least one feature is enabled (opt-in)
	if not (addon.db["TooltipUnitShowSpec"] or addon.db["TooltipUnitShowItemLevel"]) then return end
	local guid = UnitGUID(unit)
	if type(guid) == "nil" or issecretvalue(guid) then return end
	if not guid then return end
	local tNow = now()
	local c = InspectCache[guid]
	if c then
		if tNow - (c.last or 0) < CACHE_TTL then return end
		if tNow - (c.requestAt or 0) < INSPECT_REQUEST_COOLDOWN then return end
	end

	-- Self: no inspect needed
	if UnitIsUnit(unit, "player") then
		local ilvl
		if GetAverageItemLevel then
			local _, eq = GetAverageItemLevel()
			ilvl = eq and tonumber(string.format("%.1f", eq))
		end
		local specName
		local si = GetSpecialization and GetSpecialization()
		if si then specName = select(2, GetSpecializationInfo(si)) end
		local score = C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore and C_ChallengeMode.GetOverallDungeonScore()
		InspectCache[guid] = { ilvl = ilvl, specName = specName, score = score, last = now() }
		return
	end

	if addon.db["TooltipUnitInspectRequireModifier"] and not IsConfiguredModifierDown() then return end

	if IsInspectUIBusy() then
		ClearTooltipInspectState()
		return
	end

	if pendingGUID and pendingRequestedAt and (tNow - pendingRequestedAt) >= INSPECT_PENDING_TIMEOUT then FinishTooltipInspectRequest() end

	-- Others: request inspect if possible
	if CanInspect and CanInspect(unit) and not InCombatLockdown() and not issecretvalue(unit) then
		if pendingGUID and pendingUnit then
			local pendingUnitGuid = UnitGUID(pendingUnit)
			if issecretvalue(pendingUnitGuid) or issecretvalue(pendingGUID) or issecretvalue(guid) then
				ClearTooltipInspectState()
			elseif pendingUnitGuid == pendingGUID and pendingGUID == guid then
				return
			elseif pendingRequestedAt and (tNow - pendingRequestedAt) < INSPECT_PENDING_TIMEOUT then
				return
			else
				ClearTooltipInspectState()
			end
		end
		local cacheEntry = c or {}
		cacheEntry.requestAt = tNow
		InspectCache[guid] = cacheEntry
		pendingGUID = guid
		pendingUnit = unit
		pendingRequestedAt = tNow
		if NotifyInspect then NotifyInspect(unit) end
	end
end

local function GetNPCIDFromGUID(guid)
	if guid and not (issecretvalue and issecretvalue(guid)) then
		local type, _, _, _, _, npcID = strsplit("-", guid)
		if type == "Creature" or type == "Vehicle" then return tonumber(npcID) end
	end
	return nil
end

local function FormatUnitName(unit)
	if not unit or (issecretvalue and issecretvalue(unit)) then return nil end
	if UnitIsUnit then
		local same = UnitIsUnit(unit, "player")
		if issecretvalue and issecretvalue(same) then return nil end
		if same then return "<YOU>" end
	end
	local name, realm = UnitName(unit)
	if not name then return nil end
	if issecretvalue and issecretvalue(name) then return nil end
	if realm and realm ~= "" then name = name .. "-" .. realm end
	return name
end

local function GetUnitMountInfo(unit)
	if not unit or not UnitIsPlayer or not UnitIsPlayer(unit) then return nil end
	if not (C_UnitAuras and C_UnitAuras.GetUnitAuras) then return nil end
	if not (C_MountJournal and C_MountJournal.GetMountFromSpell and C_MountJournal.GetMountInfoByID) then return nil end
	if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return nil end
	local auras = C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
	if type(auras) ~= "table" then return nil end
	for i = 1, #auras do
		local aura = auras[i]
		local spellID = aura and aura.spellId
		if spellID and (not issecretvalue or not issecretvalue(spellID)) then
			local mountID = C_MountJournal.GetMountFromSpell(spellID)
			if mountID then
				local name, _, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
				if not name or name == "" then
					if C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(spellID) end
					if not name and GetSpellInfo then name = GetSpellInfo(spellID) end
				end
				if name and name ~= "" then
					local collected = isCollected == true
					if issecretvalue and issecretvalue(isCollected) then collected = false end
					return name, icon, collected
				end
			end
		end
	end
	return nil
end

local function fmtNum(n)
	if BreakUpLargeNumbers then
		return BreakUpLargeNumbers(n or 0)
	else
		return tostring(n or 0)
	end
end

local function checkCurrency(tooltip, id)
	if tooltip:IsForbidden() or tooltip:IsProtected() then return end
	if not id then return end

	if addon.db["TooltipShowCurrencyID"] then
		tooltip:AddLine(" ")
		tooltip:AddDoubleLine(L["CurrencyID"], id)
	end

	if not addon.db["TooltipShowCurrencyAccountWide"] then return end
	local charList = C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters(id)

	local playerName, playerRealm = UnitFullName("player")
	if not playerRealm or playerRealm == "" then playerRealm = GetRealmName():gsub("%s+", "") end
	local playerFullName = playerName .. "-" .. playerRealm
	local playerQty = C_CurrencyInfo.GetCurrencyInfo(id).quantity or 0

	if nil == charList or #charList == 0 then
		-- no warband resources - just skip all to only show the player itself by blizzard
		return
	end

	table.insert(charList, {
		fullCharacterName = playerFullName,
		characterName = playerName,
		characterGUID = UnitGUID("player"),
		currencyID = id,
		quantity = playerQty,
	})

	if charList and #charList > 0 then
		table.sort(charList, function(a, b) return a.quantity > b.quantity end)

		for i = tooltip:NumLines(), 1, -1 do
			local left = _G[tooltip:GetName() .. "TextLeft" .. i]
			local right = _G[tooltip:GetName() .. "TextRight" .. i]
			local text = left and left:GetText()
			if text and safeMatch(text, "^" .. TOTAL .. ":") then
				-- wipe both columns and break; there is only one such line
				left:SetText("")
				if right then right:SetText("") end
				break
			end
		end

		tooltip:AddLine(" ")
		local total = 0
		for _, entry in ipairs(charList) do
			total = total + entry.quantity
		end

		tooltip:AddLine(string.format("%s: |cFFFFFFFF%s|r", TOTAL, fmtNum(total)), 1, 0.82, 0)

		tooltip:AddLine(" ")

		for _, entry in ipairs(charList) do
			tooltip:AddLine(string.format("%s: |cFFFFFFFF%s|r", entry.characterName, fmtNum(entry.quantity)))
		end
		tooltip:Show()
	end
end

local function checkSpell(tooltip, id, name, isSpell)
	local first = true
	if addon.db["TooltipShowSpellID"] then
		if id then
			if first then
				tooltip:AddLine(" ")
				first = false
			end
			tooltip:AddDoubleLine(name, id)
		end
	end

	if addon.db["TooltipShowSpellIconInline"] and isSpell and IsValidSpellIdentifier(id) then
		local spellInfo = C_Spell.GetSpellInfo(id)
		if spellInfo and spellInfo.iconID then
			local line = tooltip and _G[tooltip:GetName() .. "TextLeft1"]
			if line then
				local current = line:GetText()
				if current and not isSecret(current) and not safeFind(current, "|T", true) then
					local size = addon.db and addon.db["TooltipItemIconSize"] or 16
					if size < 10 then
						size = 10
					elseif size > 30 then
						size = 30
					end
					local tex = string.format("|T%d:%d:%d:0:0|t ", spellInfo.iconID, size, size)
					line:SetText(tex .. current)
				end
			end
		end
	end

	if addon.db["TooltipShowSpellIcon"] and isSpell and IsValidSpellIdentifier(id) then
		local spellInfo = C_Spell.GetSpellInfo(id)
		if spellInfo and spellInfo.iconID then
			if first then
				tooltip:AddLine(" ")
				first = false
			end
			tooltip:AddDoubleLine(L["IconID"], spellInfo.iconID)
		end
	end

	if addon.db["TooltipSpellHideType"] == 1 then return end -- only hide when ON
	if addon.db["TooltipSpellHideInDungeon"] and select(1, IsInInstance()) == false then return end -- only hide in dungeons
	if addon.db["TooltipSpellHideInCombat"] and UnitAffectingCombat("player") == false then return end -- only hide in combat
	if IsTooltipHideOverrideActive() then return end
	tooltip:Hide()
end

local function ResolveTooltipUnit(tooltip)
	local unit
	if addon.variables.isMidnight then
		unit = "mouseover"
	else
		if GetUnitTokenFromTooltip then unit = GetUnitTokenFromTooltip(tooltip) end
		if not unit and tooltip and tooltip.GetUnit then
			-- Fallback for older clients: read unit from tooltip directly
			local _, ttUnit = tooltip:GetUnit()
			unit = ttUnit
		end
	end
	if unit and UnitExists(unit) then return unit end
	if UnitExists("mouseover") then return "mouseover" end
	if tooltip == GameTooltip and UnitExists("target") then return "target" end
	return nil
end

local function HasUnitTooltipOptions()
	local db = addon.db
	if not db then return false end
	if db["TooltipUnitHideType"] and db["TooltipUnitHideType"] ~= 1 then return true end
	if db["TooltipUnitHideInCombat"] or db["TooltipUnitHideInDungeon"] then return true end
	if db["TooltipUnitHideHealthBar"] then return true end
	if db["TooltipShowMythicScore"] then return true end
	if db["TooltipShowClassColor"] then return true end
	if db["TooltipShowNPCID"] then return true end
	if db["TooltipHideFaction"] or db["TooltipHidePVP"] then return true end
	if db["TooltipShowGuildRank"] or db["TooltipColorGuildName"] then return true end
	if db["TooltipUnitShowTargetOfTarget"] then return true end
	if db["TooltipUnitShowMount"] then return true end
	if db["TooltipUnitShowSpec"] or db["TooltipUnitShowItemLevel"] then return true end
	return false
end

local function ShouldRunAdditionalTooltip()
	local db = addon.db
	if not db then return false end
	return db["TooltipShowNPCID"]
		or db["TooltipShowClassColor"]
		or db["TooltipHideFaction"]
		or db["TooltipHidePVP"]
		or db["TooltipShowGuildRank"]
		or db["TooltipColorGuildName"]
		or db["TooltipUnitShowTargetOfTarget"]
		or db["TooltipUnitShowMount"]
		or db["TooltipShowMythicScore"]
end

local function checkAdditionalTooltip(tooltip)
	if not ShouldRunAdditionalTooltip() then return end
	local unit = ResolveTooltipUnit(tooltip)
	local function challengeLabel(mapId)
		if addon.Tooltip and addon.Tooltip.variables and addon.Tooltip.variables.challengeMapID then
			local name = addon.Tooltip.variables.challengeMapID[mapId]
			if name and name ~= "" then return name end
		end
		if mapId then return "ID " .. tostring(mapId) end
		return "UNKNOWN"
	end
	if addon.db["TooltipShowNPCID"] and unit and UnitExists(unit) and not UnitPlayerControlled(unit) then
		local uGuid = UnitGUID(unit)
		local id = GetNPCIDFromGUID(uGuid)
		if id then
			tooltip:AddLine(" ")
			tooltip:AddDoubleLine(L["NPCID"], id)
		end
		return
	end
	if addon.db["TooltipShowClassColor"] and unit and UnitIsPlayer(unit) then
		local classDisplayName, class, classID = UnitClass(unit)
		if classDisplayName then
			local r, g, b = GetClassColor(class)
			local nameLine = _G[tooltip:GetName() .. "TextLeft1"]
			if nameLine then nameLine:SetTextColor(r, g, b) end
			for i = 1, tooltip:NumLines() do
				local line = _G[tooltip:GetName() .. "TextLeft" .. i]
				local text = line and line:GetText()
				if safeFind(text, classDisplayName, true) then
					line:SetTextColor(r, g, b)
					break
				end
			end
		end
	end
	if unit and UnitIsPlayer(unit) then
		local guildName, guildRank = GetGuildInfo(unit)
		if addon.db["TooltipHideFaction"] or addon.db["TooltipHidePVP"] then
			local ttName = tooltip:GetName()
			local factionName = addon.db["TooltipHideFaction"] and select(2, UnitFactionGroup(unit)) or nil
			local pvpText = addon.db["TooltipHidePVP"] and (PVP or "PvP") or nil
			for i = 1, tooltip:NumLines() do
				local line = _G[ttName .. "TextLeft" .. i]
				local text = line and line:GetText()
				if text then
					if factionName and safeEquals(text, factionName) then
						line:SetText("")
						line:Hide()
					elseif pvpText and safeEquals(text, pvpText) then
						line:SetText("")
						line:Hide()
					end
				end
			end
		end
		if guildName then
			local ttName = tooltip:GetName()
			local guildLine
			local guildLineText
			for i = 1, tooltip:NumLines() do
				local line = _G[ttName .. "TextLeft" .. i]
				local text = line and line:GetText()
				if safeFind(text, guildName, true) then
					guildLine = line
					guildLineText = text
					break
				end
			end

			local newText
			local nameText = guildName
			if addon.db["TooltipColorGuildName"] then
				local c = addon.db["TooltipGuildNameColor"] or { r = 1, g = 1, b = 1 }
				nameText = string.format("|cff%02x%02x%02x%s|r", (c.r or 1) * 255, (c.g or 1) * 255, (c.b or 1) * 255, guildName)
			end

			local rankText
			if addon.db["TooltipShowGuildRank"] and guildRank then
				local col = addon.db["TooltipGuildRankColor"] or { r = 1, g = 1, b = 1 }
				rankText = string.format("|cff%02x%02x%02x%s|r", (col.r or 1) * 255, (col.g or 1) * 255, (col.b or 1) * 255, guildRank)
			end

			if guildLine then
				newText = nameText
				if rankText and guildLineText and not isSecret(guildLineText) and not safeFind(guildLineText, guildRank or "", true) then newText = newText .. " - " .. rankText end
				guildLine:SetText(newText)
			else
				if rankText then
					tooltip:AddLine(" ")
					tooltip:AddDoubleLine(L["GuildRank"] or RANK, rankText)
				end
			end
		end
	end

	if unit and addon.db["TooltipUnitShowTargetOfTarget"] then
		local targetUnit = unit .. "target"
		if UnitExists(targetUnit) then
			local targetName = FormatUnitName(targetUnit)
			if targetName then tooltip:AddDoubleLine(L["TooltipTargeting"] or "Targeting", targetName) end
		end
	end

	if unit and addon.db["TooltipUnitShowMount"] and UnitIsPlayer(unit) then
		local mountName, mountIcon, mountCollected = GetUnitMountInfo(unit)
		if mountName then
			if mountIcon then mountName = ("|T%d:16:16:0:0|t %s"):format(mountIcon, mountName) end
			if mountCollected then mountName = ("|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14:0:0|t %s"):format(mountName) end
			tooltip:AddDoubleLine(L["TooltipMount"] or "Mount", mountName)
		end
	end

	local showMythic = addon.db["TooltipShowMythicScore"] and unit and UnitExists(unit) and UnitCanAttack("player", unit) == false and addon.Tooltip.variables.maxLevel == UnitLevel(unit)
	if showMythic and addon.db["TooltipMythicScoreRequireModifier"] and not IsConfiguredModifierDown() then showMythic = false end
	if showMythic then
		local _, _, timeLimit
		local rating = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
		if rating then
			local r, g, b
			local bestDungeon
			local dungeonList = {}
			local ratingInfo = {}

			-- Read parts selection; default to show all if unset
			local parts = addon.db["TooltipMythicScoreParts"]
			local wantScore = type(parts) ~= "table" and true or parts.score == true
			local wantBest = type(parts) ~= "table" and true or parts.best == true
			local wantDungeons = type(parts) ~= "table" and true or parts.dungeons == true

			local printedAny = false
			if wantScore then
				r, g, b = C_ChallengeMode.GetDungeonScoreRarityColor(rating.currentSeasonScore):GetRGB()
				tooltip:AddLine(" ")
				tooltip:AddDoubleLine(DUNGEON_SCORE, rating.currentSeasonScore, 1, 1, 0, r, g, b)
				printedAny = true
			end

			if rating.currentSeasonScore > 0 and (wantBest or wantDungeons) then
				for _, key in pairs(rating.runs) do
					ratingInfo[key.challengeModeID] = key
				end

				for _, key in pairs(C_ChallengeMode.GetMapTable()) do
					_, _, timeLimit = C_ChallengeMode.GetMapUIInfo(key)
					r, g, b = 0.5, 0.5, 0.5

					local data = key
					local mId = key
					local stars = 0
					local score = 0
					if ratingInfo[key] then
						data = ratingInfo[key]
						mId = data.challengeModeID
						if nil == bestDungeon then
							bestDungeon = data
						else
							if bestDungeon.mapScore < data.mapScore then bestDungeon = data end
						end

						if data.bestRunLevel > 0 then
							r, g, b = 1, 1, 1

							local bestRunDuration = data.bestRunDurationMS / 1000
							local timeForPlus3 = timeLimit * 0.6
							local timeForPlus2 = timeLimit * 0.8
							local timeForPlus1 = timeLimit
							score = data.mapScore
							if bestRunDuration <= timeForPlus3 then
								stars = "|cFFFFD700+++|r" -- Gold für 3 Sterne
							elseif bestRunDuration <= timeForPlus2 then
								stars = "|cFFFFD700++|r" -- Gold für 2 Sterne
							elseif bestRunDuration <= timeForPlus1 then
								stars = "|cFFFFD700+|r" -- Gold für 1 Stern
							else
								stars = ""
								r = 0.5
								g = 0.5
								b = 0.5
							end
							stars = stars .. data.bestRunLevel
						else
							stars = 0
							r = 0.5
							g = 0.5
							b = 0.5
						end
					end

					table.insert(dungeonList, {
						text = challengeLabel(mId),
						level = stars,
						score = score,
						r = r,
						g = g,
						b = b,
					})
				end
				if wantBest and bestDungeon and bestDungeon.mapScore > 0 then
					_, _, timeLimit = C_ChallengeMode.GetMapUIInfo(bestDungeon.challengeModeID)
					r, g, b = 1, 1, 1
					local stars = ""
					local hexColor = string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
					local bestName = challengeLabel(bestDungeon.challengeModeID)
					if bestDungeon.finishedSuccess then
						local bestRunDuration = bestDungeon.bestRunDurationMS / 1000
						local timeForPlus3 = timeLimit * 0.6
						local timeForPlus2 = timeLimit * 0.8
						local timeForPlus1 = timeLimit
						if bestRunDuration <= timeForPlus3 then
							stars = "+++"
						elseif bestRunDuration <= timeForPlus2 then
							stars = "++"
						elseif bestRunDuration <= timeForPlus1 then
							stars = "+"
						end
						stars = stars .. bestDungeon.bestRunLevel
					else
						stars = bestDungeon.bestRunLevel
						r, g, b = 0.5, 0.5, 0.5
					end
					if not printedAny then tooltip:AddLine(" ") end
					tooltip:AddDoubleLine(L["BestMythic+run"], hexColor .. stars .. "|r " .. bestName, 1, 1, 0, r, g, b)
					printedAny = true
				end

				if wantDungeons and #dungeonList > 0 then
					table.sort(dungeonList, function(a, b) return a.score > b.score end)
					-- Add a spacer before the dungeon list (always one blank line)
					tooltip:AddLine(" ")
					for _, dungeon in ipairs(dungeonList) do
						tooltip:AddDoubleLine(dungeon.text, dungeon.level, 1, 1, 1, dungeon.r, dungeon.g, dungeon.b)
					end
				end
			end
		end
	end
end

local function ShowCopyURL(url)
	if type(url) ~= "string" or url == "" then return end
	if not StaticPopupDialogs["ENHANCEQOL_COPY_URL"] then
		StaticPopupDialogs["ENHANCEQOL_COPY_URL"] = {
			text = "Copy URL:",
			button1 = OKAY,
			hasEditBox = true,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
			OnShow = function(self, data)
				local eb = self.editBox or self.GetEditBox and self:GetEditBox()
				if not eb then return end
				eb:SetAutoFocus(true)
				eb:SetText(data or "")
				eb:HighlightText()
				eb:SetCursorPosition(0)
			end,
			OnAccept = function(self) end,
			EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		}
	end
	StaticPopup_Show("ENHANCEQOL_COPY_URL", nil, nil, url)
end

local function UpdateTooltipHealthBarVisibility(tooltip)
	if not tooltip or not addon.db then return end
	local hideBar = addon.db["TooltipUnitHideHealthBar"] and true or false
	if not hideBar and not tooltip.__EnhanceQoLTooltipHealthBarTouched then return end

	local function handleAlpha(obj)
		if not obj or not obj.SetAlpha then return end
		if not obj.__EnhanceQoLTooltipOriginalAlpha then obj.__EnhanceQoLTooltipOriginalAlpha = (obj.GetAlpha and obj:GetAlpha()) or 1 end
		local alpha = hideBar and 0 or obj.__EnhanceQoLTooltipOriginalAlpha or 1
		obj:SetAlpha(alpha)
	end

	local function apply(bar)
		if not bar then return end
		if hideBar then
			if bar.SetShown then
				bar:SetShown(false)
			elseif bar.Hide then
				bar:Hide()
			end
		else
			if bar.SetShown then
				bar:SetShown(true)
			elseif bar.Show then
				bar:Show()
			end
		end
		handleAlpha(bar)
		handleAlpha(bar.Fill or bar.fill)
		handleAlpha(bar.Spark or bar.spark)
		handleAlpha(bar.Bg or bar.BG or bar.bg)
		handleAlpha(bar.Background or bar.background)
		handleAlpha(bar.TextString or bar.textString)
		handleAlpha(bar.Text or bar.text)
		handleAlpha(bar.Value or bar.value)
		handleAlpha(bar.LeftText)
		handleAlpha(bar.RightText)
		local texture = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
		handleAlpha(texture)
		local name = bar.GetName and bar:GetName()
		if name then
			handleAlpha(_G[name .. "Spark"])
			handleAlpha(_G[name .. "BG"])
			handleAlpha(_G[name .. "Background"])
			handleAlpha(_G[name .. "Border"])
			handleAlpha(_G[name .. "BorderLeft"])
			handleAlpha(_G[name .. "BorderRight"])
		end
	end

	apply(tooltip.StatusBar)
	apply(tooltip.statusBar)
	apply(tooltip.healthBar)
	if tooltip.statusBarPool and tooltip.statusBarPool.EnumerateActive then
		for bar in tooltip.statusBarPool:EnumerateActive() do
			apply(bar)
		end
	end
	if tooltip.StatusBarPool and tooltip.StatusBarPool.EnumerateActive then
		for bar in tooltip.StatusBarPool:EnumerateActive() do
			apply(bar)
		end
	end
	if tooltip.healthBarPool and tooltip.healthBarPool.EnumerateActive then
		for bar in tooltip.healthBarPool:EnumerateActive() do
			apply(bar)
		end
	end
	if tooltip == GameTooltip then
		apply(GameTooltipStatusBar)
		handleAlpha(GameTooltipStatusBarTexture)
		handleAlpha(GameTooltipStatusBarBackground)
	end
	tooltip.__EnhanceQoLTooltipHealthBarTouched = hideBar or nil
end

local function checkUnit(tooltip)
	UpdateTooltipHealthBarVisibility(tooltip)
	if not HasUnitTooltipOptions() then return end
	if addon.db["TooltipUnitHideInDungeon"] and select(1, IsInInstance()) == false then
		checkAdditionalTooltip(tooltip)
		return
	end -- only hide in dungeons
	if addon.db["TooltipUnitHideInCombat"] and UnitAffectingCombat("player") == false then
		checkAdditionalTooltip(tooltip)
		return
	end -- only hide in combat
	if addon.db["TooltipUnitHideType"] == 1 then
		checkAdditionalTooltip(tooltip)
		return
	end -- hide never
	local override = IsTooltipHideOverrideActive()
	if addon.db["TooltipUnitHideType"] == 4 and not override then tooltip:Hide() end -- hide always because we selected BOTH
	if addon.db["TooltipUnitHideType"] == 2 and UnitCanAttack("player", "mouseover") and not override then tooltip:Hide() end
	if addon.db["TooltipUnitHideType"] == 3 and UnitCanAttack("player", "mouseover") == false and not override then tooltip:Hide() end
	checkAdditionalTooltip(tooltip)
end

local tooltipScaleTargets = {
	"GameTooltip",
	"ItemRefTooltip",
	"ShoppingTooltip1",
	"ShoppingTooltip2",
	"ShoppingTooltip3",
	"EmbeddedItemTooltip",
}

local function ApplyTooltipScale()
	local scale = addon.db and tonumber(addon.db["TooltipScale"]) or 1
	if not scale or scale <= 0 then scale = 1 end
	if scale < 0.5 then
		scale = 0.5
	elseif scale > 1.5 then
		scale = 1.5
	end
	for _, name in ipairs(tooltipScaleTargets) do
		local tt = _G[name]
		if tt and tt.SetScale then tt:SetScale(scale) end
	end
end

addon.Tooltip = addon.Tooltip or {}
addon.Tooltip.ApplyScale = ApplyTooltipScale

local lastEntry
local function checkItem(tooltip, id, name, guid)
	local first = true

	-- Automatically preview housing items if enabled
	if addon.db["TooltipHousingAutoPreview"] and C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem then
		local housingData = C_HousingCatalog.GetCatalogEntryInfoByItem(id, false)
		if housingData and lastEntry ~= id then
			lastEntry = id

			if not HousingModelPreviewFrame and C_AddOns then C_AddOns.LoadAddOn("Blizzard_HousingModelPreview") end
			if HousingModelPreviewFrame and HousingModelPreviewFrame.ShowCatalogEntryInfo then HousingModelPreviewFrame:ShowCatalogEntryInfo(housingData) end
		end
	end

	local showItemID = addon.db["TooltipShowItemID"]

	if showItemID and id then
		if first then
			tooltip:AddLine(" ")
			first = false
		end
		tooltip:AddDoubleLine(name, id)
	end

	if addon.db["TooltipShowItemIcon"] then
		local icon = nil
		if id then icon = select(5, GetItemInfoInstant(id)) end
		local line = tooltip and _G[tooltip:GetName() .. "TextLeft1"]
		if line then
			local current = line:GetText()

			if current and icon and not isSecret(current) and not safeFind(current, "|T", true) then
				local size = addon.db and addon.db["TooltipItemIconSize"] or 16
				if size < 10 then
					size = 10
				elseif size > 30 then
					size = 30
				end
				local tex = string.format("|T%d:%d:%d:0:0|t ", icon, size, size)
				line:SetText(tex .. current)
			end
		end
	end

	if addon.db["TooltipShowTempEnchant"] and guid then
		local mhHas, mhExp, _, mhID, ohHas, ohExp, _, ohID, rhHas, rhExp = GetWeaponEnchantInfo()
		if mhHas and guid == Item:CreateFromEquipmentSlot(16):GetItemGUID() then
			if mhID then
				if first then
					tooltip:AddLine(" ")
					first = false
				end
				tooltip:AddDoubleLine(L["Temp. EnchantID"], mhID)
			end
		elseif ohHas and guid == Item:CreateFromEquipmentSlot(17):GetItemGUID() then
			if ohID then
				if first then
					tooltip:AddLine(" ")
					first = false
				end
				tooltip:AddDoubleLine(L["Temp. EnchantID"], ohID)
			end
		end
	end
	if addon.db["TooltipShowItemCount"] then
		if id then
			local bagCount = C_Item.GetItemCount(id)
			local bankCount = C_Item.GetItemCount(id, true) - bagCount
			local accountCount = C_Item.GetItemCount(id, true, false, false, true) - bankCount - bagCount -- last true = AccountBank
			local totalCount = bagCount + bankCount + accountCount

			if addon.db["TooltipShowSeperateItemCount"] then
				if bagCount > 0 then
					bankCount = bankCount - bagCount

					if first then
						tooltip:AddLine(" ")
						first = false
					end
					tooltip:AddDoubleLine(L["Bag"], bagCount)
				end
				if bankCount > 0 then
					if first then
						tooltip:AddLine(" ")
						first = false
					end
					tooltip:AddDoubleLine(L["Bank"], bankCount)
				end
				if accountCount > 0 then
					if first then
						tooltip:AddLine(" ")
						first = false
					end
					tooltip:AddDoubleLine(ACCOUNT_BANK_PANEL_TITLE, accountCount)
				end
			else
				tooltip:AddDoubleLine(L["Itemcount"], totalCount)
			end
		end
	end
	if addon.db["TooltipItemHideType"] == 1 then return end -- only hide when ON
	if addon.db["TooltipItemHideInDungeon"] and select(1, IsInInstance()) == false then return end -- only hide in dungeons
	if addon.db["TooltipItemHideInCombat"] and UnitAffectingCombat("player") == false then return end -- only hide in combat
	if IsTooltipHideOverrideActive() then return end
	tooltip:Hide()
end

local function checkAura(tooltip, id, name)
	local first = true
	if addon.db["TooltipShowSpellID"] then
		if id then
			if first then
				tooltip:AddLine(" ")
				first = false
			end
			tooltip:AddDoubleLine(name, id)
		end
	end

	if addon.db["TooltipShowSpellIconInline"] and IsValidSpellIdentifier(id) then
		local spellInfo = C_Spell.GetSpellInfo(id)
		if spellInfo and spellInfo.iconID then --and (not issecretvalue or (issecretvalue and not issecretvalue(spellInfo.iconID))) then
			local line = tooltip and _G[tooltip:GetName() .. "TextLeft1"]
			if line then
				local current = line:GetText()
				if current and not isSecret(current) then
					local size = addon.db and addon.db["TooltipItemIconSize"] or 16
					if size < 10 then
						size = 10
					elseif size > 30 then
						size = 30
					end
					local tex = string.format("|T%d:%d:%d:0:0|t ", spellInfo.iconID, size, size)
					line:SetText(tex .. current)
				end
			end
		end
	end

	if addon.db["TooltipShowSpellIcon"] and IsValidSpellIdentifier(id) then
		local spellInfo = C_Spell.GetSpellInfo(id)
		if spellInfo and spellInfo.iconID then
			if first then
				tooltip:AddLine(" ")
				first = false
			end
			tooltip:AddDoubleLine(L["IconID"], spellInfo.iconID)
		end
	end

	if addon.db["TooltipBuffHideType"] == 1 then return end -- only hide when ON
	if addon.db["TooltipBuffHideInDungeon"] and select(1, IsInInstance()) == false then return end -- only hide in dungeons
	if addon.db["TooltipBuffHideInCombat"] and UnitAffectingCombat("player") == false then return end -- only hide in combat
	if IsTooltipHideOverrideActive() then return end
	tooltip:Hide()
end

local function checkAdditionalUnit(tt)
	if not (addon.db["TooltipUnitShowSpec"] or addon.db["TooltipUnitShowItemLevel"]) then return end
	if isTooltipRestricted() then return end

	local unit = GetUnitTokenFromTooltip(tt)
	if not unit or not UnitIsPlayer(unit) then return end

	EnsureUnitData(unit)
	local guid = UnitGUID(unit)
	if not guid or isSecret(guid) then return end
	local c = InspectCache[guid]
	if not c then return end

	local showSpec = addon.db["TooltipUnitShowSpec"] and c.specName
	local showIlvl = addon.db["TooltipUnitShowItemLevel"] and c.ilvl
	if addon.db["TooltipUnitInspectRequireModifier"] and not IsConfiguredModifierDown() then
		showSpec = false
		showIlvl = false
	end
	if showSpec or showIlvl then tt:AddLine(" ") end
	if showSpec then tt:AddDoubleLine("|cffffd200" .. SPECIALIZATION .. "|r", c.specName) end
	if showIlvl then
		local label = STAT_AVERAGE_ITEM_LEVEL or ITEM_LEVEL or "Item Level"
		tt:AddDoubleLine("|cffffd200" .. label .. "|r", tostring(c.ilvl))
	end
	if showSpec or showIlvl then tt:Show() end
end

if TooltipDataProcessor then
	TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tooltip, data)
		if not addon.db then return end
		if not data or not data.type then return end

		local restricted = addon.functions.isRestrictedContent and addon.functions.isRestrictedContent(true)
		local id, name, _, timeLimit, kind

		if issecretvalue and issecretvalue(data.type) then
			-- check for owner
			local owner = tooltip.GetOwner and tooltip:GetOwner()
			if owner then
				if owner.auraInstanceID then kind = "aura" end
			end
			if not kind then
				-- check for mouseover
				if UnitIsEnemy("mouseover", "player") or UnitIsFriend("mouseover", "player") then
					kind = "unit"
				else
					-- assume it's an aura?
					kind = "aura"
				end
			end
		else
			kind = addon.Tooltip.variables.kindsByID[tonumber(data.type)]
		end
		if restricted and kind ~= "unit" then return end

		if kind == "spell" then
			id = data.id
			name = L["SpellID"]
			checkSpell(tooltip, id, name, true)
			return
		elseif kind == "macro" then
			local ttInfo = tooltip:GetPrimaryTooltipInfo()
			id = data.id
			if ttInfo and ttInfo.getterArgs then
				local actionSlot = ttInfo.getterArgs[1]
				if actionSlot then id = GetActionText(actionSlot) end
			end
			name = MACRO
			checkSpell(tooltip, id, name)
			return
		elseif kind == "unit" then
			checkUnit(tooltip)
			checkAdditionalUnit(tooltip)
			return
		elseif kind == "item" then
			id = data.id
			name = L["ItemID"]
			checkItem(tooltip, id, name, data.guid)
			return
		elseif kind == "aura" then
			id = data.id
			name = L["SpellID"]
			checkAura(tooltip, id, name)
			return
		elseif kind == "currency" then
			-- Show account‑wide character breakdown for the given currency
			id = data.id
			checkCurrency(tooltip, id)
			return
		end
	end)
end

local function IsUnitTooltip(tt)
	local owner = tt and tt:GetOwner()
	if not owner then return false end
	return owner.unit or (owner.GetAttribute and owner:GetAttribute("unit"))
end

local function EnsureQuestIDInQuestLogLabel()
	if addon.Tooltip.variables.questIDInQuestLogLabel then return addon.Tooltip.variables.questIDInQuestLogLabel end
	if not QuestMapFrame or not QuestMapFrame.DetailsFrame or not QuestMapFrame.DetailsFrame.BackFrame then return end

	local backFrame = QuestMapFrame.DetailsFrame.BackFrame and QuestMapFrame.DetailsFrame.BackFrame.BackButton or QuestMapFrame.DetailsFrame.BackFrame
	local anchor = backFrame.AccountCompletedNotice or backFrame
	local fs = backFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetJustifyH("RIGHT")
	fs:SetJustifyV("MIDDLE")
	if anchor ~= backFrame then
		fs:SetPoint("RIGHT", anchor, "LEFT", -18, 0)
	else
		fs:SetPoint("TOPLEFT", backFrame, "TOPRIGHT", 14, -8)
	end
	fs:Hide()

	addon.Tooltip.variables.questIDInQuestLogLabel = fs
	return fs
end

local function UpdateQuestIDInQuestLogLabel(questID)
	local fs = EnsureQuestIDInQuestLogLabel()
	if not fs then return end
	if not addon.db or not addon.db["TooltipShowQuestIDInQuestLog"] or not questID or questID == 0 then
		fs:SetText("")
		fs:Hide()
		return
	end

	local label = ID or "ID"
	fs:SetText(("%s: %s"):format(label, tostring(questID)))
	fs:Show()
end

function addon.Tooltip.functions.UpdateQuestIDInQuestLog(questID)
	if not QuestMapFrame or not QuestMapFrame.DetailsFrame then return end
	local detailsFrame = QuestMapFrame.DetailsFrame
	if not detailsFrame:IsShown() then
		UpdateQuestIDInQuestLogLabel(nil)
		return
	end
	UpdateQuestIDInQuestLogLabel(questID or detailsFrame.questID)
end

local function registerTooltipHooks()
	if addon.Tooltip.variables.hooksInitialized then return end
	addon.Tooltip.variables.hooksInitialized = true

	-- Apply initial tooltip scale once the UI is ready
	C_Timer.After(0, function()
		if addon.Tooltip and addon.Tooltip.ApplyScale then addon.Tooltip.ApplyScale() end
	end)

	hooksecurefunc("GameTooltip_SetDefaultAnchor", function(s, p)
		if not addon.db then return end
		if not s or not s.SetOwner then return end
		if s.IsForbidden and s:IsForbidden() then return end
		if p and p.IsForbidden and p:IsForbidden() then return end
		if addon.db["TooltipAnchorType"] == 1 then return end
		local anchor
		if addon.db["TooltipAnchorType"] == 2 then anchor = "ANCHOR_CURSOR" end
		if addon.db["TooltipAnchorType"] == 3 then anchor = "ANCHOR_CURSOR_LEFT" end
		if addon.db["TooltipAnchorType"] == 4 then anchor = "ANCHOR_CURSOR_RIGHT" end
		local xOffset = addon.db["TooltipAnchorOffsetX"]
		local yOffset = addon.db["TooltipAnchorOffsetY"]
		s:SetOwner(p, anchor, xOffset, yOffset)
	end)

	if Menu and Menu.ModifyMenu then
		local function AddTargetWowheadEntry(owner, root)
			if not addon.db or not addon.db["TooltipShowNPCWowheadLink"] then return end
			if not UnitExists("target") or UnitPlayerControlled("target") then return end
			local guid = UnitGUID("target")
			if issecretvalue and issecretvalue(guid) then return end
			local npcID = GetNPCIDFromGUID()
			if not npcID then return end

			root:CreateDivider()
			local btn = root:CreateButton(L["CopyWowheadURL"], function() ShowCopyURL(("https://www.wowhead.com/npc=%d"):format(npcID)) end)
			if not btn then return end
			btn:AddInitializer(function()
				btn:SetTooltip(function(tt)
					GameTooltip_SetTitle(tt, "Wowhead")
					GameTooltip_AddNormalLine(tt, ("npc=%d"):format(npcID))
				end)
			end)
		end

		Menu.ModifyMenu("MENU_UNIT_TARGET", AddTargetWowheadEntry)
	end

	hooksecurefunc("QuestMapLogTitleButton_OnEnter", function(self)
		if not addon.db or not addon.db["TooltipShowQuestID"] then return end
		if self then
			if self.questID and GameTooltip:IsShown() then
				GameTooltip:AddDoubleLine(ID, self.questID)
				GameTooltip:Show()
			end
		end
	end)

	hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(questID)
		if addon.Tooltip and addon.Tooltip.functions and addon.Tooltip.functions.UpdateQuestIDInQuestLog then addon.Tooltip.functions.UpdateQuestIDInQuestLog(questID) end
	end)

	hooksecurefunc("QuestMapFrame_CloseQuestDetails", function()
		if addon.Tooltip and addon.Tooltip.functions and addon.Tooltip.functions.UpdateQuestIDInQuestLog then addon.Tooltip.functions.UpdateQuestIDInQuestLog() end
	end)

	-- Optionally hide the default "Right-click for options" instruction on unit tooltips
	hooksecurefunc("GameTooltip_AddInstructionLine", function(tt, text)
		if not addon.db or not addon.db["TooltipUnitHideRightClickInstruction"] then return end
		if tt ~= GameTooltip then return end
		if text ~= UNIT_POPUP_RIGHT_CLICK then return end
		if not IsUnitTooltip(tt) then return end

		local i = tt:NumLines()
		local line = _G[tt:GetName() .. "TextLeft" .. i]
		if line then
			local tmpText = line:GetText()
			if isSecret(tmpText) then return end
			if safeEquals(tmpText, text) then
				line:SetText("")
				line:Hide()

				local mLine = _G[tt:GetName() .. "TextLeft" .. (i - 1)]
				local mText = mLine and mLine.GetText and mLine:GetText()
				if safeEquals(mText, " ") then mLine:Hide() end
				tt:Show()
			end
		end
	end)

	if addon.Tooltip and addon.Tooltip.functions and addon.Tooltip.functions.UpdateQuestIDInQuestLog then addon.Tooltip.functions.UpdateQuestIDInQuestLog() end
end

function addon.Tooltip.functions.InitState()
	registerTooltipHooks()
	UpdateInspectEventRegistration()
end
