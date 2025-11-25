local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Tooltip")

local AceGUI = addon.AceGUI

local frameLoad = CreateFrame("Frame")

-- ==== Inspect cache (spec/ilvl/score) ====
local InspectCache = {} -- [guid] = { ilvl, specName, score, last }
local CACHE_TTL = 30 -- seconds
local function now() return GetTime() end

local function GetUnitTokenFromTooltip(tt)
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

local pendingGUID, pendingUnit
local EnsureUnitData -- forward declaration
local fInspect = CreateFrame("Frame")

-- Decide whether we need INSPECT_READY at all (opt-in)
local function ShouldUseInspectFeature()
	-- TODO on midnight beta - bug we are not able to add lines to tooltip in secure states
	if not addon.variables.isMidnight then
		return (addon.db and (addon.db["TooltipUnitShowSpec"] or addon.db["TooltipUnitShowItemLevel"])) or false
	else
		return false
	end
end

local function IsConfiguredModifierDown()
	local mod = addon.db and addon.db["TooltipMythicScoreModifier"] or "SHIFT"
	return (mod == "SHIFT" and IsShiftKeyDown()) or (mod == "ALT" and IsAltKeyDown()) or (mod == "CTRL" and IsControlKeyDown())
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
	if not fInspect then return end
	fInspect:UnregisterEvent("INSPECT_READY")
	fInspect:UnregisterEvent("MODIFIER_STATE_CHANGED")
	if ShouldUseInspectFeature() then
		fInspect:RegisterEvent("INSPECT_READY")
		if addon.db["TooltipUnitInspectRequireModifier"] then fInspect:RegisterEvent("MODIFIER_STATE_CHANGED") end
	else
		pendingGUID, pendingUnit = nil, nil
	end
end

local function FindLineIndexByLabel(tt, label)
	local name = tt:GetName()
	for i = 1, tt:NumLines() do
		local left = _G[name .. "TextLeft" .. i]
		local text = left and left:GetText()
		if text and text:find(label, 1, true) then return i end
	end
	return nil
end

local function RefreshTooltipForGUID(guid)
	if not GameTooltip or not GameTooltip:IsShown() then return end
	local tt = GameTooltip
	local unit = GetUnitTokenFromTooltip(tt)
	if not unit then return end
	local uGuid = UnitGUID(unit)
	if uGuid ~= guid then return end
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
	-- TODO bug in midnight beta we can'T change tooltip
	if addon.variables.isMidnight then return end
	if ev == "INSPECT_READY" then
		local guid = arg1
		if not guid or guid ~= pendingGUID then return end
		local unit = (pendingUnit and UnitGUID(pendingUnit) == guid) and pendingUnit or nil
		pendingGUID, pendingUnit = nil, nil
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
	-- TODO midnight tooltip bug - we can't do anything for now
	if addon.variables.isMidnight then return end
	-- Only fetch if at least one feature is enabled (opt-in)
	if not (addon.db["TooltipUnitShowSpec"] or addon.db["TooltipUnitShowItemLevel"]) then return end
	local guid = UnitGUID(unit)
	if not guid then return end
	local c = InspectCache[guid]
	if c and (now() - (c.last or 0) < CACHE_TTL) then return end

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

	-- Others: request inspect if possible
	if CanInspect and CanInspect(unit) and not InCombatLockdown() then
		if pendingGUID and pendingUnit and UnitGUID(pendingUnit) == pendingGUID and pendingGUID == guid then return end
		pendingGUID = guid
		pendingUnit = unit
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

local function fmtNum(n)
	if BreakUpLargeNumbers then
		return BreakUpLargeNumbers(n or 0)
	else
		return tostring(n or 0)
	end
end

local function checkCurrency(tooltip, id)
	-- TODO bug in midnight beta
	if addon.variables.isMidnight then return end
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
			if left and left:GetText() and left:GetText():match("^" .. TOTAL .. ":") then
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
	-- TODO bug in midnight beta with tooltip adding
	if addon.db["TooltipShowSpellID"] and not addon.variables.isMidnight then
		if id then
			if first then
				tooltip:AddLine(" ")
				first = false
			end
			tooltip:AddDoubleLine(name, id)
		end
	end

	-- TODO bug in midnight beta with tooltip adding
	if addon.db["TooltipShowSpellIcon"] and not addon.variables.isMidnight and isSpell then
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
	tooltip:Hide()
end

local function ResolveTooltipUnit(tooltip)
	local unit
	if addon.variables.isMidnight then
		unit = "mouseover"
	else
		GetUnitTokenFromTooltip(tooltip)
	end
	if unit and UnitExists(unit) then return unit end
	if UnitExists("mouseover") then return "mouseover" end
	if tooltip == GameTooltip and UnitExists("target") then return "target" end
	return nil
end

local function checkAdditionalTooltip(tooltip)
	local unit = ResolveTooltipUnit(tooltip)
	-- TODO midnight beta bug - skipping
	if addon.db["TooltipShowNPCID"] and not addon.variables.isMidnight and unit and UnitExists(unit) and not UnitPlayerControlled(unit) then
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
			for i = 1, tooltip:NumLines() do
				local line = _G[tooltip:GetName() .. "TextLeft" .. i]
				local text = line:GetText()
				if text and text:find(classDisplayName) then
					line:SetTextColor(r, g, b)
					break
				end
			end
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
						text = addon.Tooltip.variables.challengeMapID[mId] or "UNKNOWN",
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
					tooltip:AddDoubleLine(L["BestMythic+run"], hexColor .. stars .. "|r " .. addon.Tooltip.variables.challengeMapID[bestDungeon.challengeModeID], 1, 1, 0, r, g, b)
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
end

local function checkUnit(tooltip)
	UpdateTooltipHealthBarVisibility(tooltip)
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
	if addon.db["TooltipUnitHideType"] == 4 then tooltip:Hide() end -- hide always because we selected BOTH
	if addon.db["TooltipUnitHideType"] == 2 and UnitCanAttack("player", "mouseover") then tooltip:Hide() end
	if addon.db["TooltipUnitHideType"] == 3 and UnitCanAttack("player", "mouseover") == false then tooltip:Hide() end
	checkAdditionalTooltip(tooltip)
end

local function checkItem(tooltip, id, name, guid)
	local first = true
	-- TODO Bug in midnight beta with tooltip handling
	if addon.db["TooltipShowItemID"] and not addon.variables.isMidnight then
		if id then
			if first then
				tooltip:AddLine(" ")
				first = false
			end
			tooltip:AddDoubleLine(name, id)
		end
	end
	-- TODO Bug in midnight beta with tooltip handling
	if addon.db["TooltipShowTempEnchant"] and not addon.variables.isMidnight and guid then
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
	-- TODO Bug in midnight beta with tooltip handling
	if addon.db["TooltipShowItemCount"] and not addon.variables.isMidnight then
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
	tooltip:Hide()
end

local function checkAura(tooltip, id, name)
	local first = true
	-- TODO midnight beta bug - skipping
	if addon.db["TooltipShowSpellID"] and not addon.variables.isMidnight then
		if id then
			if first then
				tooltip:AddLine(" ")
				first = false
			end
			tooltip:AddDoubleLine(name, id)
		end
	end

	-- TODO midnight beta bug - skipping
	if addon.db["TooltipShowSpellIcon"] and not addon.variables.isMidnight then
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
	tooltip:Hide()
end

local function checkAdditionalUnit(tt)
	-- TODO bug in midnight beta - can't change tooltip
	if addon.variables.isMidnight then return end
	if not (addon.db["TooltipUnitShowSpec"] or addon.db["TooltipUnitShowItemLevel"]) then return end

	local unit = GetUnitTokenFromTooltip(tt)
	if not unit or not UnitIsPlayer(unit) then return end

	EnsureUnitData(unit)
	local guid = UnitGUID(unit)
	local c = guid and InspectCache[guid] or nil
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
		if not data or not data.type then return end

		local id, name, _, timeLimit, kind

		if issecretvalue and issecretvalue(data.type) then
			-- check for mouseover
			if UnitIsEnemy("mouseover", "player") or UnitIsFriend("mouseover", "player") then kind = "unit" end
		else
			kind = addon.Tooltip.variables.kindsByID[tonumber(data.type)]
		end
		if kind == "spell" then
			id = data.id
			name = L["SpellID"]
			checkSpell(tooltip, id, name, true)
			return
		elseif kind == "macro" then
			id = data.id
			name = L["MacroID"]
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

hooksecurefunc("GameTooltip_SetDefaultAnchor", function(s, p)
	if addon.db["TooltipAnchorType"] == 1 then return end
	local anchor
	if addon.db["TooltipAnchorType"] == 2 then anchor = "ANCHOR_CURSOR" end
	if addon.db["TooltipAnchorType"] == 3 then anchor = "ANCHOR_CURSOR_LEFT" end
	if addon.db["TooltipAnchorType"] == 4 then anchor = "ANCHOR_CURSOR_RIGHT" end
	local xOffset = addon.db["TooltipAnchorOffsetX"]
	local yOffset = addon.db["TooltipAnchorOffsetY"]
	s:SetOwner(p, anchor, xOffset, yOffset)
end)

-- Initial registration based on current settings (opt-in)
UpdateInspectEventRegistration()

addon.variables.statusTable.groups["tooltip"] = true

-- Place Tooltip under UI & Input
addon.functions.addToTree("ui", {
	value = "tooltip",
	text = L["Tooltip"],
})

-- New unified Tooltip options UI using root wrapper + ensureGroup
local function addTooltipFrame2(container, which)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)
	local function doLayout()
		if scroll and scroll.DoLayout then scroll:DoLayout() end
	end
	wrapper:PauseLayout()

	local groups = {}

	local function ensureGroup(key, title)
		local g, known
		if groups[key] then
			g = groups[key]
			groups[key]:PauseLayout()
			groups[key]:ReleaseChildren()
			known = true
		else
			g = addon.functions.createContainer("InlineGroup", "List")
			if title and title ~= "" then g:SetTitle(title) end
			wrapper:AddChild(g)
			groups[key] = g
		end
		return g, known
	end

	local function buildBuffDebuff() end

	local function buildItem() end

	local function buildSpell() end

	local function buildQuests() end

	local function buildUnit()
		local g, known = ensureGroup("unit", L["Unit"])
		g:SetLayout("Flow")

		local list, order = addon.functions.prepareListForDropdown({ [1] = NONE, [2] = L["Enemies"], [3] = L["Friendly"], [4] = L["Both"] })
		local dropTooltipUnitHideType = addon.functions.createDropdownAce(L["TooltipUnitHideType"], list, order, function(self) addon.db["TooltipUnitHideType"] = self:GetValue() end)
		dropTooltipUnitHideType:SetValue(addon.db["TooltipUnitHideType"])
		dropTooltipUnitHideType:SetFullWidth(false)
		dropTooltipUnitHideType:SetWidth(150)
		g:AddChild(dropTooltipUnitHideType)

		local cbHideInCombat = addon.functions.createCheckboxAce(
			L["TooltipUnitHideInCombat"],
			addon.db["TooltipUnitHideInCombat"],
			function(_, _, value) addon.db["TooltipUnitHideInCombat"] = value end
		)
		g:AddChild(cbHideInCombat)

		local cbHideInDungeon = addon.functions.createCheckboxAce(
			L["TooltipUnitHideInDungeon"],
			addon.db["TooltipUnitHideInDungeon"],
			function(_, _, value) addon.db["TooltipUnitHideInDungeon"] = value end
		)
		g:AddChild(cbHideInDungeon)

		local cbHideHealthBar = addon.functions.createCheckboxAce(L["TooltipUnitHideHealthBar"], addon.db["TooltipUnitHideHealthBar"], function(_, _, value)
			addon.db["TooltipUnitHideHealthBar"] = value
			if GameTooltip then UpdateTooltipHealthBarVisibility(GameTooltip) end
		end)
		g:AddChild(cbHideHealthBar)

		local cbHideInstruction = addon.functions.createCheckboxAce(
			L["TooltipUnitHideRightClickInstruction"]:format(UNIT_POPUP_RIGHT_CLICK),
			addon.db["TooltipUnitHideRightClickInstruction"],
			function(_, _, value) addon.db["TooltipUnitHideRightClickInstruction"] = value end
		)
		g:AddChild(cbHideInstruction)

		local playerGroup = addon.functions.createContainer("InlineGroup", "List")
		playerGroup:SetTitle(L["TooltipUnitPlayerGroup"] or PLAYER)
		playerGroup:SetLayout("Flow")
		g:AddChild(playerGroup)

		local playerOptions = {}
		local playerOrder = {}
		if not addon.variables.isMidnight then
			playerOptions = {
				mythic = L["TooltipShowMythicScore"]:format(DUNGEON_SCORE),
				spec = L["TooltipUnitShowSpec"],
				ilvl = L["TooltipUnitShowItemLevel"],
				classColor = L["TooltipShowClassColor"],
			}
			playerOrder = { "mythic", "spec", "ilvl" }
		else
			playerOrder = { "classColor" }
			playerOptions = {
				classColor = L["TooltipShowClassColor"],
			}
			addon.db["TooltipUnitShowItemLevel"] = false
			addon.db["TooltipUnitShowSpec"] = false
			addon.db["TooltipShowMythicScore"] = false
		end

		local dropPlayerDetails = addon.functions.createDropdownAce(L["TooltipPlayerDetailsLabel"], playerOptions, playerOrder, function() end)
		dropPlayerDetails:SetMultiselect(true)
		dropPlayerDetails:SetFullWidth(false)
		dropPlayerDetails:SetWidth(340)
		if addon.db["TooltipShowMythicScore"] then dropPlayerDetails:SetItemValue("mythic", true) end
		if addon.db["TooltipUnitShowSpec"] then dropPlayerDetails:SetItemValue("spec", true) end
		if addon.db["TooltipUnitShowItemLevel"] then dropPlayerDetails:SetItemValue("ilvl", true) end
		if addon.db["TooltipShowClassColor"] then dropPlayerDetails:SetItemValue("classColor", true) end
		dropPlayerDetails:SetCallback("OnValueChanged", function(_, _, key, checked)
			local enabled = checked and true or false
			if key == "mythic" then addon.db["TooltipShowMythicScore"] = enabled end
			if key == "spec" then addon.db["TooltipUnitShowSpec"] = enabled end
			if key == "ilvl" then addon.db["TooltipUnitShowItemLevel"] = enabled end
			if key == "classColor" then addon.db["TooltipShowClassColor"] = enabled end
			if key == "spec" or key == "ilvl" then UpdateInspectEventRegistration() end
			if key == "mythic" or key == "spec" or key == "ilvl" then buildUnit() end
		end)
		playerGroup:AddChild(dropPlayerDetails)

		if not addon.variables.isMidnight then
			local additionalGroup = addon.functions.createContainer("InlineGroup", "List")
			additionalGroup:SetTitle(L["TooltipPlayerAdditionalOptions"])
			playerGroup:AddChild(additionalGroup)

			local cbMythicModifier = addon.functions.createCheckboxAce(
				L["TooltipMythicScoreRequireModifier"]:format(DUNGEON_SCORE),
				addon.db["TooltipMythicScoreRequireModifier"],
				function(_, _, value)
					addon.db["TooltipMythicScoreRequireModifier"] = value
					buildUnit()
				end
			)
			cbMythicModifier:SetDisabled(not addon.db["TooltipShowMythicScore"])
			additionalGroup:AddChild(cbMythicModifier)

			local cbInspectModifier = addon.functions.createCheckboxAce(L["TooltipUnitInspectRequireModifier"], addon.db["TooltipUnitInspectRequireModifier"], function(_, _, value)
				addon.db["TooltipUnitInspectRequireModifier"] = value
				UpdateInspectEventRegistration()
				buildUnit()
			end)
			cbInspectModifier:SetDisabled(not (addon.db["TooltipUnitShowSpec"] or addon.db["TooltipUnitShowItemLevel"]))
			additionalGroup:AddChild(cbInspectModifier)

			local gatedMythic = addon.db["TooltipMythicScoreRequireModifier"] and addon.db["TooltipShowMythicScore"]
			local gatedInspect = addon.db["TooltipUnitInspectRequireModifier"] and (addon.db["TooltipUnitShowSpec"] or addon.db["TooltipUnitShowItemLevel"])
			if gatedMythic or gatedInspect then
				local modList = { SHIFT = SHIFT_KEY_TEXT, ALT = ALT_KEY_TEXT, CTRL = CTRL_KEY_TEXT }
				local list2, order2 = addon.functions.prepareListForDropdown(modList)

				local parts = {}
				if gatedMythic then table.insert(parts, DUNGEON_SCORE) end
				if gatedInspect then
					if addon.db["TooltipUnitShowSpec"] and addon.db["TooltipUnitShowItemLevel"] then
						table.insert(parts, L["SpecAndIlvl"] or (SPECIALIZATION .. " & " .. (STAT_AVERAGE_ITEM_LEVEL or ITEM_LEVEL or "Item Level")))
					elseif addon.db["TooltipUnitShowSpec"] then
						table.insert(parts, SPECIALIZATION)
					elseif addon.db["TooltipUnitShowItemLevel"] then
						table.insert(parts, STAT_AVERAGE_ITEM_LEVEL or ITEM_LEVEL or "Item Level")
					end
				end
				local label
				if #parts <= 1 then
					label = (L["TooltipMythicScoreModifier"] or "Required modifier for %s"):format(parts[1] or DUNGEON_SCORE)
				else
					label = (L["TooltipModifierForMultiple"] or "Required modifier for: %s"):format(table.concat(parts, ", "))
				end

				local dropMod = addon.functions.createDropdownAce(label, list2, order2, function(self) addon.db["TooltipMythicScoreModifier"] = self:GetValue() end)
				dropMod:SetValue(addon.db["TooltipMythicScoreModifier"])
				dropMod:SetFullWidth(false)
				dropMod:SetWidth(340)
				additionalGroup:AddChild(dropMod)
			end

			if addon.db["TooltipShowMythicScore"] then
				local partsList = {
					score = DUNGEON_SCORE,
					best = L["BestMythic+run"],
					dungeons = L["SeasonDungeons"] or "Season dungeons",
				}
				local dropParts = addon.functions.createDropdownAce(L["MythicScorePartsLabel"] or "Mythic+ details to show", partsList, nil, function(self, _, key, checked)
					addon.db["TooltipMythicScoreParts"] = addon.db["TooltipMythicScoreParts"] or { score = true, best = true, dungeons = true }
					if checked then
						addon.db["TooltipMythicScoreParts"][key] = true
					else
						addon.db["TooltipMythicScoreParts"][key] = nil
					end
				end)
				dropParts:SetMultiselect(true)
				local selected = addon.db["TooltipMythicScoreParts"] or {}
				for k, v in pairs(selected) do
					if v then dropParts:SetItemValue(k, true) end
				end
				dropParts:SetFullWidth(false)
				dropParts:SetWidth(340)
				additionalGroup:AddChild(dropParts)
			end
		end

		local npcGroup = addon.functions.createContainer("InlineGroup", "List")
		npcGroup:SetTitle(L["TooltipUnitNPCGroup"])
		npcGroup:SetLayout("List")
		g:AddChild(npcGroup)

		if not addon.variables.isMidnight then
			local cbNPCID = addon.functions.createCheckboxAce(L["TooltipShowNPCID"], addon.db["TooltipShowNPCID"], function(_, _, value) addon.db["TooltipShowNPCID"] = value end)
			npcGroup:AddChild(cbNPCID)
		else
			addon.db["TooltipShowNPCID"] = false
		end
		local cbNPCWowhead = addon.functions.createCheckboxAce(
			L["TooltipShowNPCWowheadLink"],
			addon.db["TooltipShowNPCWowheadLink"],
			function(_, _, value) addon.db["TooltipShowNPCWowheadLink"] = value end,
			L["TooltipShowNPCWowheadLink_desc"]
		)
		npcGroup:AddChild(cbNPCWowhead)

		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildGeneral()
		local g, known = ensureGroup("general", GENERAL)
		local list, order = addon.functions.prepareListForDropdown({ [1] = DEFAULT, [2] = L["CursorCenter"], [3] = L["CursorLeft"], [4] = L["CursorRight"] })

		local drop = addon.functions.createDropdownAce(L["TooltipAnchorType"], list, order, function(self)
			addon.db["TooltipAnchorType"] = self:GetValue()
			buildGeneral()
		end)
		drop:SetValue(addon.db["TooltipAnchorType"])
		drop:SetFullWidth(false)
		drop:SetWidth(200)
		g:AddChild(drop)

		if addon.db["TooltipAnchorType"] > 1 then
			local sliderOffsetX = addon.functions.createSliderAce(
				L["TooltipAnchorOffsetX"] .. ": " .. addon.db["TooltipAnchorOffsetX"],
				addon.db["TooltipAnchorOffsetX"],
				-300,
				300,
				1,
				function(self, _, value2)
					addon.db["TooltipAnchorOffsetX"] = value2
					self:SetLabel(L["TooltipAnchorOffsetX"] .. ": " .. value2)
				end
			)
			g:AddChild(sliderOffsetX)

			local sliderOffsetY = addon.functions.createSliderAce(
				L["TooltipAnchorOffsetY"] .. ": " .. addon.db["TooltipAnchorOffsetY"],
				addon.db["TooltipAnchorOffsetY"],
				-300,
				300,
				1,
				function(self, _, value2)
					addon.db["TooltipAnchorOffsetY"] = value2
					self:SetLabel(L["TooltipAnchorOffsetY"] .. ": " .. value2)
				end
			)
			g:AddChild(sliderOffsetY)
		end
		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildCurrency()
		-- TODO bugfix midnight beta
		if addon.variables.isMidnight then return end
		local g, known = ensureGroup("currency", CURRENCY)
		local data = {
			{ text = L["TooltipShowCurrencyAccountWide"], var = "TooltipShowCurrencyAccountWide" },
			{ text = L["TooltipShowCurrencyID"], var = "TooltipShowCurrencyID" },
		}
		table.sort(data, function(a, b) return a.text < b.text end)
		for _, cbData in ipairs(data) do
			local cb = addon.functions.createCheckboxAce(cbData.text, addon.db[cbData.var], function(_, _, v) addon.db[cbData.var] = v end)
			g:AddChild(cb)
		end
		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	-- Build all sections into one scrollable view, sorted by translated title
	local sections = {
		{ key = "general", title = GENERAL, builder = buildGeneral },
		{ key = "unit", title = L["Unit"], builder = buildUnit },
		{ key = "buff_debuff", title = L["Buff_Debuff"], builder = buildBuffDebuff },
		{ key = "item", title = L["Item"], builder = buildItem },
		{ key = "spell", title = L["Spell"], builder = buildSpell },
		{ key = "quests", title = QUESTLOG_BUTTON, builder = buildQuests },
		{ key = "currency", title = CURRENCY, builder = buildCurrency },
	}
	table.sort(sections, function(a, b) return tostring(a.title) < tostring(b.title) end)
	for _, s in ipairs(sections) do
		s.builder()
	end

	wrapper:ResumeLayout()
	doLayout()
end

function addon.Tooltip.functions.treeCallback(container, group)
	container:ReleaseChildren()
	addTooltipFrame2(container, group)
end

if Menu and Menu.ModifyMenu then
	local function AddTargetWowheadEntry(owner, root)
		if not addon.db["TooltipShowNPCWowheadLink"] then return end
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
	if addon.db["TooltipShowQuestID"] then
		if self then
			if self.questID and GameTooltip:IsShown() then
				GameTooltip:AddDoubleLine(ID, self.questID)
				GameTooltip:Show()
			end
		end
	end
end)

local function IsUnitTooltip(tt)
	local owner = tt and tt:GetOwner()
	if not owner then return false end
	return owner.unit or (owner.GetAttribute and owner:GetAttribute("unit"))
end

-- Optionally hide the default "Right-click for options" instruction on unit tooltips
hooksecurefunc("GameTooltip_AddInstructionLine", function(tt, text)
	if not addon.db["TooltipUnitHideRightClickInstruction"] then return end
	if tt ~= GameTooltip then return end
	if text ~= UNIT_POPUP_RIGHT_CLICK then return end
	if not IsUnitTooltip(tt) then return end

	local i = tt:NumLines()
	local line = _G[tt:GetName() .. "TextLeft" .. i]
	if line then
		local tmpText = line:GetText()
		if issecretvalue and issecretvalue(tmpText) then return end
		if line:GetText() == text then
			line:SetText("")
			line:Hide()

			local mLine = _G[tt:GetName() .. "TextLeft" .. (i - 1)]
			if mLine and mLine.GetText and mLine:GetText() == " " then mLine:Hide() end
			tt:Show()
		end
	end
end)
