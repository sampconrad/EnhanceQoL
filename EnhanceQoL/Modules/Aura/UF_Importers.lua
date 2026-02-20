local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Aura = addon.Aura or {}
local UF = addon.Aura.UF
local UFHelper = addon.Aura.UFHelper
if not UF or not UFHelper then return end

local ensureDB = UF._ensureDB
local defaultsFor = UF._defaultsFor
local isBossUnit = UF._isBossUnit
local maxBossFrames = tonumber(UF._maxBossFrames) or (MAX_BOSS_FRAMES or 5)
local UF_FRAME_NAMES = UF._frameNames
local MIN_WIDTH = tonumber(UF._minWidth) or 40
local UNIT = UF._unitTokens
local IMPORT_UUF_ANCHORS = false
local IMPORT_UUF_AURA_ANCHORS = true
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

if type(ensureDB) ~= "function" then return end
if type(defaultsFor) ~= "function" then return end
if type(isBossUnit) ~= "function" then return end
if type(UF_FRAME_NAMES) ~= "table" then return end
if type(UNIT) ~= "table" then return end

function UF.ImportUnhaltedProfile(encoded, scopeKey)
	local function normalize(key)
		if not key or key == "" then return "ALL" end
		if key == "ALL" then return "ALL" end
		if isBossUnit(key) then return "boss" end
		return key
	end
	local function clampNumber(value, minValue, maxValue)
		if type(value) ~= "number" then return nil end
		if value < minValue then return minValue end
		if value > maxValue then return maxValue end
		return value
	end
	local function valueFromKeys(source, ...)
		if type(source) ~= "table" then return nil end
		for i = 1, select("#", ...) do
			local key = select(i, ...)
			local value = source[key]
			if value ~= nil then return value end
		end
		return nil
	end
	local function mapUUFSeparator(separator)
		if type(separator) ~= "string" or separator == "" then return nil end
		if separator == "||" then return "|" end
		if separator == "-" or separator == "/" or separator == ":" or separator == "|" then return separator end
		if separator == " " then return " " end
		return nil
	end
	local function mapUUFTextureKey(textureName)
		if type(textureName) ~= "string" then return nil end
		local name = UFHelper.trim(textureName)
		if name == "" then return nil end
		local lower = string.lower(name)
		if lower == "solid" then return "SOLID" end
		if lower == "default" then return "DEFAULT" end

		local textureHash = LSM and LSM.HashTable and LSM:HashTable("statusbar") or nil
		if type(textureHash) == "table" then
			if textureHash[name] then return name end
			for key in pairs(textureHash) do
				if type(key) == "string" and string.lower(key) == lower then return key end
			end
		end

		-- UUF-specific default: if not registered in current client, fall back to Blizzard.
		if lower == "better blizzard" then return "DEFAULT" end

		-- Accept explicit texture paths.
		if name:find("[/\\]") or name:find("%.[A-Za-z0-9]+$") then return name end
		return nil
	end
	local function mapUUFAnchorPointToSide(point)
		if type(point) ~= "string" then return "BOTTOM" end
		local token = string.upper(point)
		if token:find("TOP", 1, true) then return "TOP" end
		if token:find("BOTTOM", 1, true) then return "BOTTOM" end
		if token:find("LEFT", 1, true) then return "LEFT" end
		if token:find("RIGHT", 1, true) then return "RIGHT" end
		return "BOTTOM"
	end
	local function mapUUFGrowth(primaryDirection, secondaryDirection, fallbackAnchor)
		local primary = type(primaryDirection) == "string" and string.upper(primaryDirection) or nil
		local secondary = type(secondaryDirection) == "string" and string.upper(secondaryDirection) or nil
		local function isVertical(direction) return direction == "UP" or direction == "DOWN" end
		if primary and secondary and primary ~= secondary and isVertical(primary) ~= isVertical(secondary) then return primary .. secondary end
		if primary and not secondary then
			if isVertical(primary) then
				secondary = "RIGHT"
			else
				secondary = "DOWN"
			end
		elseif secondary and not primary then
			if isVertical(secondary) then
				primary = "RIGHT"
			else
				primary = "DOWN"
			end
		end
		if primary and secondary and isVertical(primary) ~= isVertical(secondary) then return primary .. secondary end
		local anchor = mapUUFAnchorPointToSide(fallbackAnchor)
		if anchor == "TOP" then return "RIGHTUP" end
		if anchor == "LEFT" then return "LEFTDOWN" end
		return "RIGHTDOWN"
	end
	local function decodeUUFEncodedFilter(value)
		if type(value) ~= "string" then return nil end
		local decoded = value:gsub("%|%|", "|")
		decoded = string.lower(UFHelper.trim(decoded))
		if decoded == "" then return nil end
		return decoded
	end
	local function mapUUFAuraAnchor(layout)
		if type(layout) ~= "table" then return "BOTTOM" end
		local point = type(layout[1]) == "string" and string.upper(layout[1]) or ""
		local relativePoint = type(layout[2]) == "string" and string.upper(layout[2]) or ""
		local token = relativePoint ~= "" and relativePoint or point
		if token:find("TOP", 1, true) then return "TOP" end
		if token:find("BOTTOM", 1, true) then return "BOTTOM" end
		if token:find("LEFT", 1, true) then return "LEFT" end
		if token:find("RIGHT", 1, true) then return "RIGHT" end
		local x = tonumber(layout[3]) or 0
		local y = tonumber(layout[4]) or 0
		if math.abs(y) >= math.abs(x) then
			if y >= 0 then return "TOP" end
			return "BOTTOM"
		end
		if x >= 0 then return "RIGHT" end
		return "LEFT"
	end
	local function resolveUUFAuraCategoryConfigs(rawBuffCfg, rawDebuffCfg)
		local helpfulCfg
		local harmfulCfg
		local function assign(cfg, defaultHelpful)
			if type(cfg) ~= "table" then return end
			local decodedFilter = decodeUUFEncodedFilter(cfg.Filter)
			local isHelpful = defaultHelpful
			if decodedFilter then
				if decodedFilter:find("harmful", 1, true) then
					isHelpful = false
				elseif decodedFilter:find("helpful", 1, true) then
					isHelpful = true
				end
			end
			if isHelpful then
				if not helpfulCfg then
					helpfulCfg = cfg
				elseif not harmfulCfg then
					harmfulCfg = cfg
				end
			else
				if not harmfulCfg then
					harmfulCfg = cfg
				elseif not helpfulCfg then
					helpfulCfg = cfg
				end
			end
		end
		assign(rawBuffCfg, true)
		assign(rawDebuffCfg, false)
		if not helpfulCfg and type(rawBuffCfg) == "table" then helpfulCfg = rawBuffCfg end
		if not harmfulCfg and type(rawDebuffCfg) == "table" and rawDebuffCfg ~= helpfulCfg then harmfulCfg = rawDebuffCfg end
		return helpfulCfg, harmfulCfg
	end
	local function unpackUUFColor(color, alphaOverride, defaultAlpha)
		if type(color) ~= "table" then return nil end
		local function normalizeChannel(value)
			local channel = tonumber(value)
			if channel == nil then return nil end
			if channel > 1 then channel = channel / 255 end
			if channel < 0 then channel = 0 end
			if channel > 1 then channel = 1 end
			return channel
		end
		local r = normalizeChannel(color[1] or color.r or color.R or color.red or color.Red)
		local g = normalizeChannel(color[2] or color.g or color.G or color.green or color.Green)
		local b = normalizeChannel(color[3] or color.b or color.B or color.blue or color.Blue)
		if r == nil or g == nil or b == nil then return nil end
		local a = normalizeChannel(alphaOverride)
		if a == nil then a = normalizeChannel(color[4] or color.a or color.A or color.alpha or color.Alpha) end
		if a == nil then a = defaultAlpha or 1 end
		return { r, g, b, a }
	end
	local function resolveUUFUnitData(units, unitKey)
		if type(units) ~= "table" or type(unitKey) ~= "string" then return nil end
		local direct = units[unitKey]
		if type(direct) == "table" then return direct end
		local unitLower = string.lower(unitKey)
		for key, value in pairs(units) do
			if type(key) == "string" and type(value) == "table" and string.lower(key) == unitLower then return value end
		end
		if unitLower == "boss" then
			for key, value in pairs(units) do
				if type(key) == "string" and type(value) == "table" and string.lower(key):match("^boss") then return value end
			end
		end
		return nil
	end
	local function resolveUUFAnchorParent(anchorParent)
		if type(anchorParent) ~= "string" or anchorParent == "" then return "UIParent" end
		local map = {
			UUF_Player = UF_FRAME_NAMES.player.frame,
			UUF_Target = UF_FRAME_NAMES.target.frame,
			UUF_TargetTarget = UF_FRAME_NAMES.targettarget.frame,
			UUF_Focus = UF_FRAME_NAMES.focus.frame,
			UUF_FocusTarget = UF_FRAME_NAMES.focus.frame,
			UUF_Pet = UF_FRAME_NAMES.pet.frame,
			UUF_Boss = "EQOLUFBossContainer",
		}
		for i = 1, maxBossFrames do
			map["UUF_Boss" .. i] = "EQOLUFBossContainer"
		end
		return map[anchorParent] or "UIParent"
	end
	local function parseUUFTagTokens(tagString)
		local tokens = {}
		if type(tagString) ~= "string" then return tokens end
		for token in string.gmatch(string.lower(tagString), "%[([^%]]+)%]") do
			token = UFHelper.trim(token)
			if token ~= "" then tokens[#tokens + 1] = token end
		end
		if #tokens == 0 then
			local raw = UFHelper.trim(string.lower(tagString))
			if raw ~= "" then tokens[1] = raw end
		end
		return tokens
	end
	local function tokenStartsWith(token, prefix) return token == prefix or token:sub(1, #prefix + 1) == prefix .. ":" end
	local function hasTagPrefix(tokens, prefix)
		for i = 1, #tokens do
			if tokenStartsWith(tokens[i], prefix) then return true end
		end
		return false
	end
	local function hasAbbreviatedTag(tokens)
		for i = 1, #tokens do
			if tokens[i]:find(":abbr", 1, true) then return true end
		end
		return false
	end
	local function findTagNameMaxChars(tokens)
		for i = 1, #tokens do
			local count = tokens[i]:match("^name:short:(%d+)")
			if count then
				local value = tonumber(count)
				if value and value > 0 then return clampNumber(value, 1, 60) end
			end
		end
		return nil
	end

	local SUPPORTED_TEXT_MODES = {
		PERCENT = true,
		CURMAX = true,
		CURRENT = true,
		MAX = true,
		CURPERCENT = true,
		CURMAXPERCENT = true,
		MAXPERCENT = true,
		PERCENTMAX = true,
		PERCENTCUR = true,
		PERCENTCURMAX = true,
		LEVELPERCENT = true,
		LEVELPERCENTMAX = true,
		LEVELPERCENTCUR = true,
		LEVELPERCENTCURMAX = true,
		NONE = true,
	}

	local function normalizeSupportedTextMode(mode)
		if type(mode) ~= "string" then return nil end
		if SUPPORTED_TEXT_MODES[mode] then return mode end
		return nil
	end

	local function mapUUFTagMode(tokens, barKey)
		local hasLevel = hasTagPrefix(tokens, "level")
		local hasCurrent, hasMax, hasPercent
		if barKey == "power" then
			hasCurrent = hasTagPrefix(tokens, "curpp")
			hasMax = hasTagPrefix(tokens, "maxpp")
			hasPercent = hasTagPrefix(tokens, "perpp")
			if hasTagPrefix(tokens, "curpp:manapercent") then
				hasCurrent = true
				hasPercent = true
			end
		else
			hasCurrent = hasTagPrefix(tokens, "curhp") or hasTagPrefix(tokens, "absorbs")
			hasMax = hasTagPrefix(tokens, "maxhp")
			hasPercent = hasTagPrefix(tokens, "perhp")
			if hasTagPrefix(tokens, "curhpperhp") then
				hasCurrent = true
				hasPercent = true
			end
		end

		if hasLevel and hasPercent and hasCurrent and hasMax then return "LEVELPERCENTCURMAX" end
		if hasLevel and hasPercent and hasMax then return "LEVELPERCENTMAX" end
		if hasLevel and hasPercent and hasCurrent then return "LEVELPERCENTCUR" end
		if hasLevel and hasPercent then return "LEVELPERCENT" end
		if hasCurrent and hasMax and hasPercent then return "CURMAXPERCENT" end
		if hasCurrent and hasMax then return "CURMAX" end
		if hasCurrent and hasPercent then return "CURPERCENT" end
		if hasMax and hasPercent then return "MAXPERCENT" end
		if hasPercent then return "PERCENT" end
		if hasCurrent then return "CURRENT" end
		if hasMax then return "MAX" end
		return nil
	end
	local function resolveTextSlot(point, x)
		local token = type(point) == "string" and string.upper(point) or ""
		if token:find("LEFT", 1, true) then return "left" end
		if token:find("RIGHT", 1, true) then return "right" end
		local offsetX = tonumber(x)
		if offsetX and offsetX < 0 then return "right" end
		if offsetX and offsetX > 0 then return "left" end
		return "center"
	end
	local function resolveStatusAnchor(point, x)
		local token = type(point) == "string" and string.upper(point) or ""
		if token:find("LEFT", 1, true) then return "LEFT" end
		if token:find("RIGHT", 1, true) then return "RIGHT" end
		local offsetX = tonumber(x)
		if offsetX and offsetX < 0 then return "RIGHT" end
		if offsetX and offsetX > 0 then return "LEFT" end
		return "CENTER"
	end
	local function mapStatusNameOffset(nameTag, sourceUnit, defaults)
		local x = tonumber(nameTag and nameTag.x) or 0
		local y = tonumber(nameTag and nameTag.y) or 0
		local point = type(nameTag and nameTag.point) == "string" and string.upper(nameTag.point) or ""
		local frameCfg = type(sourceUnit) == "table" and type(sourceUnit.Frame) == "table" and sourceUnit.Frame or nil
		local frameHeight = clampNumber(frameCfg and tonumber(frameCfg.Height) or nil, 6, 1200)
		if frameHeight and not point:find("TOP", 1, true) and not point:find("BOTTOM", 1, true) then y = y - (frameHeight / 2) end

		local epsilon = 0.001
		if nameTag and nameTag.anchor == "LEFT" and math.abs(x) <= epsilon then
			local pad = defaults and defaults.health and defaults.health.offsetLeft and tonumber(defaults.health.offsetLeft.x) or 6
			if not pad or pad <= 0 then pad = 6 end
			x = pad
		elseif nameTag and nameTag.anchor == "RIGHT" then
			if math.abs(x) <= epsilon then
				local pad = defaults and defaults.health and defaults.health.offsetRight and tonumber(defaults.health.offsetRight.x) or -6
				if not pad or pad >= 0 then pad = -6 end
				x = pad
			elseif x > 0 then
				x = -x
			end
		end
		y = clampNumber(y, -300, 300) or 0
		return x, y
	end
	local function sanitizeBarTextModes(barCfg, defaults)
		if type(barCfg) ~= "table" then return end
		defaults = type(defaults) == "table" and defaults or {}
		local leftFallback = normalizeSupportedTextMode(defaults.textLeft) or "PERCENT"
		local centerFallback = normalizeSupportedTextMode(defaults.textCenter) or "NONE"
		local rightFallback = normalizeSupportedTextMode(defaults.textRight) or "CURMAX"
		barCfg.textLeft = normalizeSupportedTextMode(barCfg.textLeft) or leftFallback
		barCfg.textCenter = normalizeSupportedTextMode(barCfg.textCenter) or centerFallback
		barCfg.textRight = normalizeSupportedTextMode(barCfg.textRight) or rightFallback
	end
	local function applyUUFTagConfig(unitKey, sourceUnit, targetCfg, profileData, defaults)
		local tagsCfg = type(sourceUnit.Tags) == "table" and sourceUnit.Tags or nil
		if not tagsCfg then return end
		targetCfg.health = targetCfg.health or {}
		targetCfg.power = targetCfg.power or {}
		local healthSlots = {}
		local powerSlots = {}
		local nameTag
		local orderedTags = { "TagOne", "TagTwo", "TagThree", "TagFour", "TagFive" }
		local powerEnabled = targetCfg.power.enabled ~= false
		for i = 1, #orderedTags do
			local tagData = type(tagsCfg[orderedTags[i]]) == "table" and tagsCfg[orderedTags[i]] or nil
			local tagExpression = tagData and UFHelper.trim(tagData.Tag or "") or ""
			if tagExpression ~= "" then
				local layout = type(tagData.Layout) == "table" and tagData.Layout or {}
				local point = type(layout[1]) == "string" and layout[1] or nil
				local x = tonumber(layout[3]) or 0
				local y = tonumber(layout[4]) or 0
				local slot = resolveTextSlot(point, x)
				local tokens = parseUUFTagTokens(tagExpression)
				local fontSize = clampNumber(tonumber(tagData.FontSize), 6, 60)
				local abbr = hasAbbreviatedTag(tokens)
				local hasNameToken = hasTagPrefix(tokens, "name")
				if hasNameToken and not nameTag then
					local tagColor = unpackUUFColor(type(tagData.Colour) == "table" and tagData.Colour or nil, nil, 1)
					nameTag = {
						anchor = resolveStatusAnchor(point, x),
						point = point,
						x = x,
						y = y,
						fontSize = fontSize,
						maxChars = findTagNameMaxChars(tokens),
						colorByTag = hasTagPrefix(tokens, "name:colour"),
						color = tagColor,
					}
				end
				local healthMode = normalizeSupportedTextMode(mapUUFTagMode(tokens, "health"))
				local powerMode = powerEnabled and normalizeSupportedTextMode(mapUUFTagMode(tokens, "power")) or nil

				if healthMode and not healthSlots[slot] then healthSlots[slot] = {
					mode = healthMode,
					x = x,
					y = y,
					fontSize = fontSize,
					abbr = abbr,
				} end
				if powerMode and not powerSlots[slot] then powerSlots[slot] = {
					mode = powerMode,
					x = x,
					y = y,
					fontSize = fontSize,
					abbr = abbr,
				} end
			end
		end

		local function applyTextSlots(barCfg, slots, forceClear)
			local hasSlots = type(slots) == "table" and (slots.left or slots.center or slots.right)
			if not hasSlots and not forceClear then return end
			barCfg.textLeft = slots.left and slots.left.mode or "NONE"
			barCfg.textCenter = slots.center and slots.center.mode or "NONE"
			barCfg.textRight = slots.right and slots.right.mode or "NONE"
			if not hasSlots then
				barCfg.useShortNumbers = false
				return
			end
			if slots.left then barCfg.offsetLeft = { x = slots.left.x or 0, y = slots.left.y or 0 } end
			if slots.center then barCfg.offsetCenter = { x = slots.center.x or 0, y = slots.center.y or 0 } end
			if slots.right then barCfg.offsetRight = { x = slots.right.x or 0, y = slots.right.y or 0 } end
			local hasAbbr
			local bestFont
			for _, slotData in pairs(slots) do
				if slotData.abbr then hasAbbr = true end
				if slotData.fontSize and (not bestFont or slotData.fontSize > bestFont) then bestFont = slotData.fontSize end
			end
			barCfg.useShortNumbers = hasAbbr == true
			if bestFont then barCfg.fontSize = bestFont end
		end

		applyTextSlots(targetCfg.health, healthSlots, true)
		applyTextSlots(targetCfg.power, powerSlots, true)

		if nameTag then
			local statusCfg = targetCfg.status or {}
			targetCfg.status = statusCfg
			statusCfg.enabled = true
			statusCfg.nameAnchor = nameTag.anchor or statusCfg.nameAnchor or "LEFT"
			local mappedNameX, mappedNameY = mapStatusNameOffset(nameTag, sourceUnit, defaults)
			statusCfg.nameOffset = statusCfg.nameOffset or {}
			statusCfg.nameOffset.x = mappedNameX
			statusCfg.nameOffset.y = mappedNameY
			if nameTag.fontSize then statusCfg.nameFontSize = nameTag.fontSize end
			if nameTag.maxChars then statusCfg.nameMaxChars = nameTag.maxChars end
			if nameTag.colorByTag then
				statusCfg.nameColorMode = "CLASS"
				if unitKey == UNIT.TARGET or unitKey == UNIT.TARGET_TARGET or unitKey == UNIT.FOCUS or unitKey == "boss" then statusCfg.nameUseReactionColor = true end
			elseif nameTag.color then
				statusCfg.nameColorMode = "CUSTOM"
				statusCfg.nameColor = nameTag.color
				statusCfg.nameUseReactionColor = false
			end
			local defaultStatusHeight = defaults and defaults.statusHeight
			if type(defaultStatusHeight) ~= "number" or defaultStatusHeight <= 0 then defaultStatusHeight = 18 end
			if type(targetCfg.statusHeight) ~= "number" or targetCfg.statusHeight <= 0 then targetCfg.statusHeight = defaultStatusHeight end
		end

		local general = type(profileData) == "table" and profileData.General or nil
		local delimiter = mapUUFSeparator(type(general) == "table" and general.Separator or nil)
		if delimiter then
			targetCfg.health.textDelimiter = delimiter
			targetCfg.power.textDelimiter = delimiter
		end
	end
	local function applyUUFAuraConfig(unitKey, sourceUnit, targetCfg)
		if unitKey ~= UNIT.PLAYER and unitKey ~= UNIT.TARGET and unitKey ~= UNIT.FOCUS and unitKey ~= "boss" then return end
		local auraCfg = type(sourceUnit.Auras) == "table" and sourceUnit.Auras or nil
		if not auraCfg then return end
		local rawBuffCfg = type(auraCfg.Buffs) == "table" and auraCfg.Buffs or nil
		local rawDebuffCfg = type(auraCfg.Debuffs) == "table" and auraCfg.Debuffs or nil
		if not rawBuffCfg and not rawDebuffCfg then return end
		local buffCfg, debuffCfg = resolveUUFAuraCategoryConfigs(rawBuffCfg, rawDebuffCfg)
		if not buffCfg and not debuffCfg then return end
		targetCfg.auraIcons = targetCfg.auraIcons or {}
		local ac = targetCfg.auraIcons
		local showBuffs = buffCfg and buffCfg.Enabled == true or false
		local showDebuffs = debuffCfg and debuffCfg.Enabled == true or false
		ac.enabled = showBuffs or showDebuffs
		ac.showBuffs = showBuffs
		ac.showDebuffs = showDebuffs

		local buffSize = clampNumber(buffCfg and tonumber(buffCfg.Size) or nil, 8, 80)
		local debuffSize = clampNumber(debuffCfg and tonumber(debuffCfg.Size) or nil, 8, 80)
		if buffSize then ac.size = buffSize end
		if debuffSize and (not buffSize or debuffSize ~= buffSize) then ac.debuffSize = debuffSize end

		local spacing = clampNumber(
			(buffCfg and type(buffCfg.Layout) == "table" and tonumber(buffCfg.Layout[5])) or (debuffCfg and type(debuffCfg.Layout) == "table" and tonumber(debuffCfg.Layout[5])) or nil,
			0,
			30
		)
		if spacing then ac.padding = spacing end

		local buffMax = clampNumber(buffCfg and tonumber(buffCfg.Num) or nil, 0, 80)
		local debuffMax = clampNumber(debuffCfg and tonumber(debuffCfg.Num) or nil, 0, 80)
		local totalMax = 0
		if showBuffs and buffMax then totalMax = totalMax + buffMax end
		if showDebuffs and debuffMax then totalMax = totalMax + debuffMax end
		if totalMax <= 0 then totalMax = buffMax or debuffMax or 16 end
		ac.max = clampNumber(totalMax, 1, 80) or ac.max

		local buffWrap = clampNumber(buffCfg and tonumber(buffCfg.Wrap) or nil, 0, 40)
		local debuffWrap = clampNumber(debuffCfg and tonumber(debuffCfg.Wrap) or nil, 0, 40)
		local perRow = buffWrap or debuffWrap
		if debuffWrap and perRow and debuffWrap > perRow then perRow = debuffWrap end
		if perRow then
			if perRow > 0 then
				ac.perRow = math.floor(perRow + 0.5)
			else
				ac.perRow = 0
			end
		end

		local baseCfg = showBuffs and buffCfg or debuffCfg
		if baseCfg and type(baseCfg.Layout) == "table" then
			local baseLayout = baseCfg.Layout
			ac.offset = ac.offset or {}
			ac.offset.x = tonumber(baseLayout[3]) or 0
			ac.offset.y = tonumber(baseLayout[4]) or 0
			if IMPORT_UUF_AURA_ANCHORS then
				ac.anchor = mapUUFAuraAnchor(baseLayout)
				local growthFallback = (type(baseLayout[2]) == "string" and baseLayout[2]) or baseLayout[1]
				ac.growth = mapUUFGrowth(baseCfg.GrowthDirection, baseCfg.WrapDirection, growthFallback)
			end
		end

		if buffCfg and type(buffCfg.Count) == "table" then
			local countCfg = buffCfg.Count
			local countLayout = type(countCfg.Layout) == "table" and countCfg.Layout or nil
			if countLayout then
				ac.countOffset = ac.countOffset or {}
				ac.countOffset.x = tonumber(countLayout[3]) or ((ac.countOffset and ac.countOffset.x) or -2)
				ac.countOffset.y = tonumber(countLayout[4]) or ((ac.countOffset and ac.countOffset.y) or 2)
				if IMPORT_UUF_AURA_ANCHORS and type(countLayout[1]) == "string" then ac.countAnchor = string.upper(countLayout[1]) end
			end
			local countFont = clampNumber(tonumber(countCfg.FontSize), 6, 60)
			if countFont then ac.countFontSizeBuff = countFont end
		end
		if debuffCfg and type(debuffCfg.Count) == "table" then
			local countFont = clampNumber(tonumber(debuffCfg.Count.FontSize), 6, 60)
			if countFont then ac.countFontSizeDebuff = countFont end
		end
		local durationCfg = type(auraCfg.AuraDuration) == "table" and auraCfg.AuraDuration or nil
		if durationCfg then
			local cooldownSize = clampNumber(tonumber(durationCfg.FontSize), 6, 60)
			if cooldownSize then
				if showBuffs then ac.cooldownFontSizeBuff = cooldownSize end
				if showDebuffs then ac.cooldownFontSizeDebuff = cooldownSize end
			end
		end

		if IMPORT_UUF_AURA_ANCHORS then
			if showBuffs and showDebuffs and buffCfg and debuffCfg and type(buffCfg.Layout) == "table" and type(debuffCfg.Layout) == "table" then
				local buffLayout = buffCfg.Layout
				local debuffLayout = debuffCfg.Layout
				local buffAnchor = mapUUFAuraAnchor(buffLayout)
				local debuffAnchor = mapUUFAuraAnchor(debuffLayout)
				local buffGrowthFallback = (type(buffLayout[2]) == "string" and buffLayout[2]) or buffLayout[1]
				local debuffGrowthFallback = (type(debuffLayout[2]) == "string" and debuffLayout[2]) or debuffLayout[1]
				local buffGrowth = mapUUFGrowth(buffCfg.GrowthDirection, buffCfg.WrapDirection, buffGrowthFallback)
				local debuffGrowth = mapUUFGrowth(debuffCfg.GrowthDirection, debuffCfg.WrapDirection, debuffGrowthFallback)
				local buffX = tonumber(buffCfg.Layout[3]) or 0
				local buffY = tonumber(buffCfg.Layout[4]) or 0
				local debuffX = tonumber(debuffCfg.Layout[3]) or 0
				local debuffY = tonumber(debuffCfg.Layout[4]) or 0
				local splitDebuffAnchor = debuffAnchor ~= buffAnchor or debuffGrowth ~= buffGrowth or debuffX ~= buffX or debuffY ~= buffY
				ac.separateDebuffAnchor = splitDebuffAnchor
				if splitDebuffAnchor then
					ac.debuffAnchor = debuffAnchor
					ac.debuffOffset = { x = debuffX, y = debuffY }
					ac.debuffGrowth = debuffGrowth
					if buffMax and debuffMax then
						local requiredForDebuffs = math.ceil((debuffMax + 0.001) / 0.4)
						local requiredForBuffs = math.ceil((buffMax + 0.001) / 0.6)
						local requiredMax = requiredForDebuffs
						if requiredForBuffs > requiredMax then requiredMax = requiredForBuffs end
						local clampedMax = clampNumber(requiredMax, 1, 80)
						if clampedMax and clampedMax > (ac.max or 0) then ac.max = clampedMax end
					end
				else
					ac.debuffAnchor = nil
					ac.debuffOffset = nil
					ac.debuffGrowth = nil
				end
			else
				ac.separateDebuffAnchor = false
				ac.debuffAnchor = nil
				ac.debuffOffset = nil
				ac.debuffGrowth = nil
			end
		end
	end
	local function applyUUFGeneralColorOverrides(profileData)
		local generalCfg = type(profileData) == "table" and profileData.General or nil
		local colors = type(generalCfg) == "table" and generalCfg.Colours or nil
		if type(colors) ~= "table" then return end
		addon.db = addon.db or {}
		if type(colors.Reaction) == "table" then
			local overrides = {}
			local enemy = type(colors.Reaction[2]) == "table" and colors.Reaction[2] or colors.Reaction[1]
			local neutral = colors.Reaction[4]
			local friendly = type(colors.Reaction[5]) == "table" and colors.Reaction[5] or colors.Reaction[8]
			local function applyReactionColor(key, value)
				local converted = unpackUUFColor(value, nil, 1)
				if converted then overrides[key] = converted end
			end
			applyReactionColor("enemy", enemy)
			applyReactionColor("neutral", neutral)
			applyReactionColor("friendly", friendly)
			if next(overrides) then addon.db.ufNPCColorOverrides = overrides end
		end
		if type(colors.Power) == "table" then
			local overrides = {}
			for powerType, color in pairs(colors.Power) do
				local converted = unpackUUFColor(color, nil, 1)
				if converted then
					local key = tonumber(powerType)
					if key == nil then key = tostring(powerType) end
					overrides[key] = converted
				end
			end
			if next(overrides) then addon.db.ufPowerColorOverrides = overrides end
		end
	end
	local function applyUUFBasicFrameConfig(unitKey, sourceUnit, targetCfg, profileData)
		if type(sourceUnit) ~= "table" or type(targetCfg) ~= "table" then return end
		local frameCfg = type(sourceUnit.Frame) == "table" and sourceUnit.Frame or {}
		local generalCfg = type(profileData) == "table" and profileData.General or nil
		local textureCfg = type(generalCfg) == "table" and generalCfg.Textures or nil
		local foregroundTextureKey = mapUUFTextureKey(textureCfg and textureCfg.Foreground or nil)
		local def = defaultsFor(unitKey)
		local defaultCast = (def and def.cast) or {}

		if sourceUnit.Enabled ~= nil then targetCfg.enabled = sourceUnit.Enabled == true end

		local width = clampNumber(tonumber(frameCfg.Width), MIN_WIDTH, 1200)
		if width then targetCfg.width = width end
		if type(frameCfg.FrameStrata) == "string" and frameCfg.FrameStrata ~= "" then targetCfg.strata = frameCfg.FrameStrata end

		local layout = type(frameCfg.Layout) == "table" and frameCfg.Layout or nil
		if layout then
			local x = tonumber(layout[3]) or 0
			local y = tonumber(layout[4]) or 0
			targetCfg.anchor = targetCfg.anchor or {}
			targetCfg.anchor.x = x
			targetCfg.anchor.y = y
			if IMPORT_UUF_ANCHORS then
				local point = type(layout[1]) == "string" and layout[1] or "CENTER"
				local relativePoint = type(layout[2]) == "string" and layout[2] or point
				local relativeTo = "UIParent"
				if unitKey == UNIT.PLAYER or unitKey == UNIT.TARGET then
					local healthCfg = sourceUnit.HealthBar
					if type(healthCfg) == "table" and healthCfg.AnchorToCooldownViewer == true then relativeTo = "EssentialCooldownViewer" end
				else
					relativeTo = resolveUUFAnchorParent(frameCfg.AnchorParent)
				end
				targetCfg.anchor.point = point
				targetCfg.anchor.relativePoint = relativePoint
				targetCfg.anchor.relativeTo = relativeTo
			end
		end

		local healthCfg = type(sourceUnit.HealthBar) == "table" and sourceUnit.HealthBar or nil
		targetCfg.health = targetCfg.health or {}
		if foregroundTextureKey then targetCfg.health.texture = foregroundTextureKey end
		local healthInverse = healthCfg and valueFromKeys(healthCfg, "Inverse")
		if healthInverse ~= nil then targetCfg.health.reverseFill = healthInverse == true end
		local healthColorByClass = healthCfg and valueFromKeys(healthCfg, "ColourByClass", "ColorByClass")
		if healthColorByClass ~= nil then targetCfg.health.useClassColor = healthColorByClass == true end
		local healthColorWhenTapped = healthCfg and valueFromKeys(healthCfg, "ColourWhenTapped", "ColorWhenTapped")
		if healthColorWhenTapped ~= nil then targetCfg.health.useTapDeniedColor = healthColorWhenTapped == true end
		if healthCfg then
			local useClassColor = targetCfg.health.useClassColor == true
			local useReaction = valueFromKeys(healthCfg, "ColourByReaction", "ColorByReaction") == true
			if unitKey == UNIT.PLAYER or unitKey == UNIT.PET then useReaction = false end
			local healthColor = unpackUUFColor(valueFromKeys(healthCfg, "Foreground"), valueFromKeys(healthCfg, "ForegroundOpacity", "ForegroundAlpha"), 1)
			if useClassColor or useReaction then
				targetCfg.health.useCustomColor = false
			elseif healthColor then
				targetCfg.health.useCustomColor = true
				targetCfg.health.color = healthColor
			end
			local backdropColor = unpackUUFColor(valueFromKeys(healthCfg, "Background"), valueFromKeys(healthCfg, "BackgroundOpacity", "BackgroundAlpha"), 1)
			local backdropColorByClass = valueFromKeys(healthCfg, "ColourBackgroundByClass", "ColorBackgroundByClass")
			targetCfg.health.backdrop = targetCfg.health.backdrop or {}
			targetCfg.health.backdrop.enabled = true
			targetCfg.health.backdrop.clampToFill = false
			if backdropColor then targetCfg.health.backdrop.color = backdropColor end
			if backdropColorByClass ~= nil then targetCfg.health.backdrop.useClassColor = backdropColorByClass == true end
		end

		local powerCfg = type(sourceUnit.PowerBar) == "table" and sourceUnit.PowerBar or nil
		targetCfg.power = targetCfg.power or {}
		if foregroundTextureKey then targetCfg.power.texture = foregroundTextureKey end
		local powerEnabledFlag = powerCfg and valueFromKeys(powerCfg, "Enabled")
		if powerEnabledFlag ~= nil then targetCfg.power.enabled = powerEnabledFlag == true end
		local powerEnabled = targetCfg.power.enabled ~= false

		local importedPowerHeight = clampNumber(powerCfg and tonumber(valueFromKeys(powerCfg, "Height")) or nil, 1, 300)
		if importedPowerHeight then targetCfg.powerHeight = importedPowerHeight end
		local powerInverse = powerCfg and valueFromKeys(powerCfg, "Inverse")
		if powerInverse ~= nil then targetCfg.power.reverseFill = powerInverse == true end
		if powerCfg then
			local colorByClass = valueFromKeys(powerCfg, "ColourByClass", "ColorByClass") == true
			local colorByType = valueFromKeys(powerCfg, "ColourByType", "ColorByType") ~= false
			targetCfg.power.useClassColor = colorByClass
			if colorByClass then
				targetCfg.power.useCustomColor = false
			elseif not colorByType then
				local powerColor = unpackUUFColor(valueFromKeys(powerCfg, "Foreground"), valueFromKeys(powerCfg, "ForegroundOpacity", "ForegroundAlpha"), 1)
				if powerColor then
					targetCfg.power.useCustomColor = true
					targetCfg.power.color = powerColor
				end
			else
				targetCfg.power.useCustomColor = false
			end
			local powerBackdrop = unpackUUFColor(valueFromKeys(powerCfg, "Background"), valueFromKeys(powerCfg, "BackgroundOpacity", "BackgroundAlpha"), 1)
			if powerBackdrop then
				targetCfg.power.backdrop = targetCfg.power.backdrop or {}
				targetCfg.power.backdrop.enabled = true
				targetCfg.power.backdrop.color = powerBackdrop
			end
		end

		local frameHeight = clampNumber(tonumber(frameCfg.Height), 6, 1200)
		if frameHeight then
			local powerHeight = powerEnabled and (clampNumber(tonumber(targetCfg.powerHeight or (def and def.powerHeight) or 0), 0, 400) or 0) or 0
			local healthHeight = frameHeight - powerHeight
			if healthHeight < 6 then healthHeight = frameHeight end
			targetCfg.healthHeight = clampNumber(healthHeight, 6, 1200) or targetCfg.healthHeight
		end

		if unitKey == UNIT.TARGET then
			local rangeCfg = sourceUnit.Range
			if type(rangeCfg) ~= "table" and type(profileData) == "table" then
				local general = profileData.General
				if type(general) == "table" then rangeCfg = general.Range end
			end
			if type(rangeCfg) == "table" then
				targetCfg.rangeFade = targetCfg.rangeFade or {}
				if rangeCfg.Enabled ~= nil then targetCfg.rangeFade.enabled = rangeCfg.Enabled == true end
				local alpha = clampNumber(tonumber(rangeCfg.OutOfRange), 0, 1)
				if alpha then targetCfg.rangeFade.alpha = alpha end
			end
		end

		if unitKey == "boss" then
			local growth = type(frameCfg.GrowthDirection) == "string" and string.upper(frameCfg.GrowthDirection) or nil
			if growth == "UP" or growth == "DOWN" then targetCfg.growth = growth end
			local spacing = clampNumber(layout and tonumber(layout[5]) or nil, 0, 200)
			if spacing then targetCfg.spacing = spacing end
		end

		local castCfg = type(sourceUnit.CastBar) == "table" and sourceUnit.CastBar or nil
		if castCfg then
			targetCfg.cast = targetCfg.cast or {}
			local targetCast = targetCfg.cast
			targetCast.enabled = castCfg.Enabled == true
			targetCast.standalone = false

			local castHeight = clampNumber(tonumber(castCfg.Height), 6, 300)
			if castHeight then targetCast.height = castHeight end

			local castWidth
			if castCfg.MatchParentWidth == true then
				castWidth = clampNumber(tonumber(frameCfg.Width), MIN_WIDTH, 1200)
			else
				castWidth = clampNumber(tonumber(castCfg.Width), MIN_WIDTH, 1200)
			end
			if castWidth then targetCast.width = castWidth end

			if type(castCfg.FrameStrata) == "string" and castCfg.FrameStrata ~= "" then targetCast.strata = castCfg.FrameStrata end

			local castLayout = type(castCfg.Layout) == "table" and castCfg.Layout or nil
			if castLayout then
				targetCast.offset = targetCast.offset or {}
				targetCast.offset.x = tonumber(castLayout[3]) or 0
				targetCast.offset.y = tonumber(castLayout[4]) or 0
				if IMPORT_UUF_ANCHORS then
					local castPoint = type(castLayout[1]) == "string" and string.upper(castLayout[1]) or ""
					targetCast.anchor = castPoint:find("TOP", 1, true) and "TOP" or "BOTTOM"
				end
			elseif IMPORT_UUF_ANCHORS and not targetCast.anchor and defaultCast.anchor then
				targetCast.anchor = defaultCast.anchor
			end

			if type(castCfg.Foreground) == "table" then
				targetCast.color = {
					tonumber(castCfg.Foreground[1]) or 0.9,
					tonumber(castCfg.Foreground[2]) or 0.7,
					tonumber(castCfg.Foreground[3]) or 0.2,
					tonumber(castCfg.Foreground[4]) or 1,
				}
			end
			if type(castCfg.Background) == "table" then
				targetCast.backdrop = targetCast.backdrop or {}
				targetCast.backdrop.enabled = true
				targetCast.backdrop.color = {
					tonumber(castCfg.Background[1]) or 0,
					tonumber(castCfg.Background[2]) or 0,
					tonumber(castCfg.Background[3]) or 0,
					tonumber(castCfg.Background[4]) or 0.6,
				}
			end
			if type(castCfg.NotInterruptibleColour) == "table" then
				targetCast.notInterruptibleColor = {
					tonumber(castCfg.NotInterruptibleColour[1]) or 0.8,
					tonumber(castCfg.NotInterruptibleColour[2]) or 0.8,
					tonumber(castCfg.NotInterruptibleColour[3]) or 0.8,
					tonumber(castCfg.NotInterruptibleColour[4]) or 1,
				}
			end
			if castCfg.ColourByClass ~= nil then targetCast.useClassColor = castCfg.ColourByClass == true end

			local iconCfg = type(castCfg.Icon) == "table" and castCfg.Icon or nil
			if iconCfg then
				targetCast.showIcon = iconCfg.Enabled == true
				local iconSize = castHeight and clampNumber(castHeight - 2, 8, 300) or nil
				if iconSize then targetCast.iconSize = iconSize end
				targetCast.iconOffset = targetCast.iconOffset or {}
				targetCast.iconOffset.x = (type(defaultCast.iconOffset) == "table" and defaultCast.iconOffset.x) or -4
				targetCast.iconOffset.y = (type(defaultCast.iconOffset) == "table" and defaultCast.iconOffset.y) or 0
			end

			local textCfg = type(castCfg.Text) == "table" and castCfg.Text or nil
			local spellCfg = textCfg and type(textCfg.SpellName) == "table" and textCfg.SpellName or nil
			local durationCfg = textCfg and type(textCfg.Duration) == "table" and textCfg.Duration or nil

			if spellCfg then
				targetCast.showName = spellCfg.Enabled ~= false
				if spellCfg.MaxChars ~= nil then targetCast.nameMaxChars = math.max(0, tonumber(spellCfg.MaxChars) or 0) end
				if spellCfg.FontSize ~= nil then targetCast.fontSize = clampNumber(tonumber(spellCfg.FontSize), 6, 60) or targetCast.fontSize end
				local spellLayout = type(spellCfg.Layout) == "table" and spellCfg.Layout or nil
				if spellLayout then
					targetCast.nameOffset = targetCast.nameOffset or {}
					targetCast.nameOffset.x = tonumber(spellLayout[3]) or 0
					targetCast.nameOffset.y = tonumber(spellLayout[4]) or 0
				end
			end

			if durationCfg then
				targetCast.showDuration = durationCfg.Enabled ~= false
				if durationCfg.FontSize ~= nil and targetCast.fontSize == nil then targetCast.fontSize = clampNumber(tonumber(durationCfg.FontSize), 6, 60) end
				targetCast.durationFormat = "REMAINING"
				local durLayout = type(durationCfg.Layout) == "table" and durationCfg.Layout or nil
				if durLayout then
					targetCast.durationOffset = targetCast.durationOffset or {}
					targetCast.durationOffset.x = tonumber(durLayout[3]) or 0
					targetCast.durationOffset.y = tonumber(durLayout[4]) or 0
				end
			end
		end

		applyUUFTagConfig(unitKey, sourceUnit, targetCfg, profileData, def)
		sanitizeBarTextModes(targetCfg.health, def and def.health)
		sanitizeBarTextModes(targetCfg.power, def and def.power)
		applyUUFAuraConfig(unitKey, sourceUnit, targetCfg)
	end

	scopeKey = normalize(scopeKey)
	encoded = UFHelper.trim(encoded or "")
	if not encoded or encoded == "" then return false, "NO_INPUT" end
	if encoded:sub(1, 5) ~= "!UUF_" then return false, "WRONG_KIND" end

	local deflate = LibStub("LibDeflate")
	local serializer = LibStub("AceSerializer-3.0")
	local decoded = deflate:DecodeForPrint(encoded:sub(6))
	if not decoded then return false, "DECODE" end
	local decompressed = deflate:DecompressDeflate(decoded)
	if not decompressed then return false, "DECOMPRESS" end
	local ok, data = serializer:Deserialize(decompressed)
	if not ok or type(data) ~= "table" then return false, "DESERIALIZE" end

	local profileData = data.profile
	local units = type(profileData) == "table" and profileData.Units or nil
	if type(units) ~= "table" then return false, "NO_FRAMES" end
	applyUUFGeneralColorOverrides(profileData)

	local requestedUnits = { "player", "target", "targettarget", "focus", "pet", "boss" }
	if scopeKey ~= "ALL" then requestedUnits = { scopeKey } end

	local applied = {}
	for _, unitKey in ipairs(requestedUnits) do
		local sourceUnit = resolveUUFUnitData(units, unitKey)
		if type(sourceUnit) == "table" then
			local targetCfg = ensureDB(unitKey)
			applyUUFBasicFrameConfig(unitKey, sourceUnit, targetCfg, profileData)
			applied[#applied + 1] = unitKey
		elseif scopeKey ~= "ALL" then
			return false, "SCOPE_MISSING"
		end
	end

	if #applied == 0 then return false, "NO_FRAMES" end
	table.sort(applied, function(a, b) return tostring(a) < tostring(b) end)
	UF.SyncEditModeLayoutAnchors(applied)
	addon.variables.requireReload = true
	return true, applied
end

addon.Aura.functions = addon.Aura.functions or {}
addon.Aura.functions.importUUFProfile = UF.ImportUnhaltedProfile
addon.importUUFProfile = function(encoded, scopeKey) return UF.ImportUnhaltedProfile(encoded, scopeKey) end
