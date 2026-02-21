-- luacheck: globals MinimapCluster
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local InstanceDifficulty = addon.InstanceDifficulty or {}
addon.InstanceDifficulty = InstanceDifficulty
InstanceDifficulty.enabled = InstanceDifficulty.enabled or false

InstanceDifficulty.frame = InstanceDifficulty.frame or CreateFrame("Frame")

local indicator = MinimapCluster.InstanceDifficulty

indicator:SetAlpha(1)
if indicator.Default then
	indicator.Default:Hide()
	indicator.Default:SetScript("OnShow", indicator.Default.Hide)
end
if indicator.ChallengeMode then
	indicator.ChallengeMode:Hide()
	indicator.ChallengeMode:SetScript("OnShow", indicator.ChallengeMode.Hide)
end
if indicator.Guild then
	indicator.Guild:Hide()
	indicator.Guild:SetScript("OnShow", indicator.Guild.Hide)
end

indicator:HookScript("OnShow", function() InstanceDifficulty:Update() end)

InstanceDifficulty.text = InstanceDifficulty.text or indicator:CreateFontString(nil, "OVERLAY", "GameFontNormal")
InstanceDifficulty.text:SetFont(addon.variables.defaultFont, 14, "OUTLINE")
InstanceDifficulty.text:Hide()

local nmNames = {
	[RAID_DIFFICULTY1] = true,
	[RAID_DIFFICULTY2] = true,
	[RAID_DIFFICULTY_10PLAYER] = true,
	[RAID_DIFFICULTY_20PLAYER] = true,
	[RAID_DIFFICULTY_25PLAYER] = true,
	[RAID_DIFFICULTY_40PLAYER] = true,
}

local hcNames = {
	[RAID_DIFFICULTY3] = true,
	[RAID_DIFFICULTY4] = true,
	[RAID_DIFFICULTY_10PLAYER_HEROIC] = true,
	[RAID_DIFFICULTY_25PLAYER_HEROIC] = true,
}

local function getShortLabel(difficultyID, difficultyName)
	if difficultyID == 1 or difficultyID == 3 or difficultyID == 4 or difficultyID == 14 or difficultyID == 33 or difficultyID == 150 or nmNames[difficultyName] or difficultyID == 12 then
		return "NM"
	elseif difficultyID == 2 or difficultyID == 5 or difficultyID == 6 or difficultyID == 15 or difficultyID == 205 or difficultyID == 230 or hcNames[difficultyName] or difficultyID == 13 then
		return "HC"
	elseif difficultyID == 16 or difficultyID == 23 then
		return "M"
	elseif difficultyID == 8 then
		local level = C_ChallengeMode.GetActiveKeystoneInfo()
		if level and type(level) == "number" and level > 0 then return "M+" .. level end
		return "M+"
	elseif difficultyID == 7 or difficultyID == 17 or difficultyID == 151 then
		return "LFR"
	elseif difficultyID == 24 then
		return "TW"
	end
	return difficultyName
end

function InstanceDifficulty:Update()
	if not self.enabled or not addon.db then return end
	if not IsInInstance() then
		self.text:Hide()
		return
	end

	local _, _, difficultyID, difficultyName, _, _, _, _, maxPlayers = GetInstanceInfo()
	local short = getShortLabel(difficultyID, difficultyName)
	-- Stable code for color mapping
	local code
	if difficultyID == 1 or difficultyID == 3 or difficultyID == 4 or difficultyID == 14 or difficultyID == 33 or difficultyID == 150 or nmNames[difficultyName] then
		code = "NM"
	elseif difficultyID == 2 or difficultyID == 5 or difficultyID == 6 or difficultyID == 15 or difficultyID == 205 or difficultyID == 230 or hcNames[difficultyName] then
		code = "HC"
	elseif difficultyID == 16 or difficultyID == 23 then
		code = "M"
	elseif difficultyID == 8 then
		code = "MPLUS"
	elseif difficultyID == 7 or difficultyID == 17 or difficultyID == 151 then
		code = "LFR"
	elseif difficultyID == 24 then
		code = "TW"
	end

	local text
	if maxPlayers and maxPlayers > 0 then
		text = string.format("%d (%s)", maxPlayers, short)
	else
		text = short
	end
	-- Apply anchor (fixed center) and offsets
	local anchor = "CENTER"
	local offX = (addon.db and addon.db["instanceDifficultyOffsetX"]) or 0
	local offY = (addon.db and addon.db["instanceDifficultyOffsetY"]) or 0
	self.text:ClearAllPoints()
	self.text:SetPoint(anchor, indicator, anchor, offX, offY)

	self.text:SetText(text)
	-- Apply font size
	local fontSize = (addon.db and addon.db["instanceDifficultyFontSize"]) or 14
	self.text:SetFont(addon.variables.defaultFont, fontSize, "OUTLINE")
	-- Apply optional difficulty colors
	if addon.db and addon.db["instanceDifficultyUseColors"] then
		local colors = addon.db["instanceDifficultyColors"] or {}
		local c = (code and colors[code]) or { r = 1, g = 1, b = 1 }
		self.text:SetTextColor(c.r or 1, c.g or 1, c.b or 1)
	else
		self.text:SetTextColor(1, 1, 1)
	end
	self.text:Show()
end

function InstanceDifficulty:SetEnabled(value)
	self.enabled = value
	if value then
		self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
		self.frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
		self.frame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
		self.frame:RegisterEvent("CHALLENGE_MODE_START")
		if indicator.Default then
			indicator.Default:Hide()
			indicator.Default:SetScript("OnShow", indicator.Default.Hide)
		end
		self:Update()
	else
		self.frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
		self.frame:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
		self.frame:UnregisterEvent("PLAYER_DIFFICULTY_CHANGED")
		self.frame:UnregisterEvent("CHALLENGE_MODE_START")
		self.text:Hide()
		if indicator.Default then
			indicator.Default:SetScript("OnShow", nil)
			if IsInInstance() then indicator.Default:Show() end
		end
	end
end

InstanceDifficulty.frame:SetScript("OnEvent", function(e) InstanceDifficulty:Update() end)
