local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
-- luacheck: globals GENERAL SlashCmdList
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.CombatMeter = {}
addon.CombatMeter.functions = {}
addon.LCombatMeter = {}

local AceGUI = addon.AceGUI
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_CombatMeter")
local TEXTURE_PATH = "Interface\\AddOns\\EnhanceQoLCombatMeter\\Texture\\"

addon.variables.statusTable.groups["combatmeter"] = true
addon.functions.addToTree(nil, {
	value = "combatmeter",
	text = L["Combat Meter"],
	children = {
		{ value = "general", text = GENERAL },
	},
})

local function addGeneralFrame(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)

	local cbEnabled = addon.functions.createCheckboxAce(L["Enabled"], addon.db["combatMeterEnabled"], function(self, _, value)
		addon.db["combatMeterEnabled"] = value
		addon.CombatMeter.functions.toggle(value)
	end)
	groupCore:AddChild(cbEnabled)

	local cbAlwaysShow = addon.functions.createCheckboxAce(L["Always Show"], addon.db["combatMeterAlwaysShow"], function(self, _, value)
		addon.db["combatMeterAlwaysShow"] = value
		if addon.CombatMeter.functions.UpdateBars then addon.CombatMeter.functions.UpdateBars() end
	end)
        groupCore:AddChild(cbAlwaysShow)

        local cbResetOnChallengeStart = addon.functions.createCheckboxAce(L["Reset on Challenge Start"], addon.db["combatMeterResetOnChallengeStart"], function(_, _, value)
                addon.db["combatMeterResetOnChallengeStart"] = value
                if addon.db["combatMeterEnabled"] and addon.CombatMeter and addon.CombatMeter.frame then
                        if value then
                                addon.CombatMeter.frame:RegisterEvent("CHALLENGE_MODE_START")
                        else
                                addon.CombatMeter.frame:UnregisterEvent("CHALLENGE_MODE_START")
                        end
                end
        end)
        groupCore:AddChild(cbResetOnChallengeStart)

        local sliderRate = addon.functions.createSliderAce(L["Update Rate"] .. ": " .. addon.db["combatMeterUpdateRate"], addon.db["combatMeterUpdateRate"], 0.05, 1, 0.05, function(self, _, val)
                addon.db["combatMeterUpdateRate"] = val
                addon.CombatMeter.functions.setUpdateRate(val)
                self:SetLabel(L["Update Rate"] .. ": " .. string.format("%.2f", val))
        end)
        groupCore:AddChild(sliderRate)

	local sliderFont = addon.functions.createSliderAce(L["Font Size"] .. ": " .. addon.db["combatMeterFontSize"], addon.db["combatMeterFontSize"], 8, 32, 1, function(self, _, val)
		addon.db["combatMeterFontSize"] = val
		if addon.CombatMeter.functions.setFontSize then addon.CombatMeter.functions.setFontSize(val) end
		self:SetLabel(L["Font Size"] .. ": " .. val)
	end)
	groupCore:AddChild(sliderFont)

	local sliderNameLength = addon.functions.createSliderAce(L["Name Length"] .. ": " .. addon.db["combatMeterNameLength"], addon.db["combatMeterNameLength"], 1, 20, 1, function(self, _, val)
		addon.db["combatMeterNameLength"] = val
		if addon.CombatMeter.functions.UpdateBars then addon.CombatMeter.functions.UpdateBars() end
		self:SetLabel(L["Name Length"] .. ": " .. val)
	end)
	groupCore:AddChild(sliderNameLength)

	local sliderPrePull
	local cbPrePull = addon.functions.createCheckboxAce(L["Pre-Pull Capture"], addon.db["combatMeterPrePullCapture"], function(_, _, value)
		addon.db["combatMeterPrePullCapture"] = value
		if sliderPrePull then sliderPrePull:SetDisabled(not value) end
	end)
	groupCore:AddChild(cbPrePull)

	sliderPrePull = addon.functions.createSliderAce(L["Window (sec)"] .. ": " .. addon.db["combatMeterPrePullWindow"], addon.db["combatMeterPrePullWindow"], 1, 10, 1, function(self, _, val)
		addon.db["combatMeterPrePullWindow"] = val
		self:SetLabel(L["Window (sec)"] .. ": " .. val)
	end)
	sliderPrePull:SetDisabled(not addon.db["combatMeterPrePullCapture"])
	groupCore:AddChild(sliderPrePull)

	local barTextures = {
		["Interface\\Buttons\\WHITE8x8"] = L["Flat (white, tintable)"],
		["Interface\\Tooltips\\UI-Tooltip-Background"] = L["Dark Flat (Tooltip bg)"],
		[TEXTURE_PATH .. "eqol_base_flat_8x8.tga"] = L["EQoL: Flat (AddOn)"],
	}
	local barOrder = {
		"Interface\\Buttons\\WHITE8x8",
		"Interface\\Tooltips\\UI-Tooltip-Background",
		TEXTURE_PATH .. "eqol_base_flat_8x8.tga",
	}
	local dropBarTexture = addon.functions.createDropdownAce(L["Bar Texture"], barTextures, barOrder, function(_, _, key)
		addon.db["combatMeterBarTexture"] = key
		if addon.CombatMeter.functions.applyBarTextures then addon.CombatMeter.functions.applyBarTextures() end
	end)
	dropBarTexture:SetValue(addon.db["combatMeterBarTexture"] or (TEXTURE_PATH .. "eqol_base_flat_8x8.tga"))
	groupCore:AddChild(dropBarTexture)

	local dropOverlayTex, dropOverlayBlend, sliderOverlayAlpha
	local cbOverlay = addon.functions.createCheckboxAce(L["Use Overlay"], addon.db["combatMeterUseOverlay"], function(_, _, value)
		addon.db["combatMeterUseOverlay"] = value
		if dropOverlayTex then dropOverlayTex:SetDisabled(not value) end
		if dropOverlayBlend then dropOverlayBlend:SetDisabled(not value) end
		if sliderOverlayAlpha then sliderOverlayAlpha:SetDisabled(not value) end
		if addon.CombatMeter.functions.applyBarTextures then addon.CombatMeter.functions.applyBarTextures() end
	end)
	groupCore:AddChild(cbOverlay)

	local overlayTextures = {
		[TEXTURE_PATH .. "eqol_overlay_gradient_512x64.tga"] = L["Gradient"], -- default
		[TEXTURE_PATH .. "eqol_overlay_vidro_512x64.tga"] = L["Gloss/Vidro"],
		[TEXTURE_PATH .. "eqol_overlay_stripes_512x64.tga"] = L["Stripes"],
		[TEXTURE_PATH .. "eqol_overlay_noise_512x64.tga"] = L["Noise"],
	}
	local overlayOrder = {
		TEXTURE_PATH .. "eqol_overlay_gradient_512x64.tga",
		TEXTURE_PATH .. "eqol_overlay_vidro_512x64.tga",
		TEXTURE_PATH .. "eqol_overlay_stripes_512x64.tga",
		TEXTURE_PATH .. "eqol_overlay_noise_512x64.tga",
	}
	local defaultBlendByTexture = {
		[TEXTURE_PATH .. "eqol_overlay_gradient_512x64.tga"] = "ADD",
		[TEXTURE_PATH .. "eqol_overlay_vidro_512x64.tga"] = "ADD",
		[TEXTURE_PATH .. "eqol_overlay_stripes_512x64.tga"] = "MOD",
		[TEXTURE_PATH .. "eqol_overlay_noise_512x64.tga"] = "BLEND",
	}
	dropOverlayTex = addon.functions.createDropdownAce(L["Overlay Texture"], overlayTextures, overlayOrder, function(_, _, key)
		addon.db["combatMeterOverlayTexture"] = key
		addon.db["combatMeterOverlayBlend"] = defaultBlendByTexture[key] or addon.db["combatMeterOverlayBlend"]
		if dropOverlayBlend then dropOverlayBlend:SetValue(addon.db["combatMeterOverlayBlend"]) end
		if addon.CombatMeter.functions.applyBarTextures then addon.CombatMeter.functions.applyBarTextures() end
	end)
	local initialOverlayTex = addon.db["combatMeterOverlayTexture"] or (TEXTURE_PATH .. "eqol_overlay_gradient_512x64.tga")
	dropOverlayTex:SetValue(initialOverlayTex)
	groupCore:AddChild(dropOverlayTex)

	dropOverlayBlend = addon.functions.createDropdownAce(L["Overlay Blend Mode"], { ADD = "ADD", BLEND = "BLEND", MOD = "MOD" }, { "ADD", "BLEND", "MOD" }, function(_, _, key)
		addon.db["combatMeterOverlayBlend"] = key
		if addon.CombatMeter.functions.applyBarTextures then addon.CombatMeter.functions.applyBarTextures() end
	end)
	local initialBlend = addon.db["combatMeterOverlayBlend"] or defaultBlendByTexture[initialOverlayTex] or "ADD"
	addon.db["combatMeterOverlayBlend"] = initialBlend
	dropOverlayBlend:SetValue(initialBlend)
	groupCore:AddChild(dropOverlayBlend)

	sliderOverlayAlpha = addon.functions.createSliderAce(
		L["Overlay Opacity"] .. ": " .. math.floor(((addon.db["combatMeterOverlayAlpha"] or 0.28) * 100) + 0.5) .. "%",
		addon.db["combatMeterOverlayAlpha"] or 0.28,
		0,
		1,
		0.01,
		function(self, _, val)
			addon.db["combatMeterOverlayAlpha"] = val
			self:SetLabel(L["Overlay Opacity"] .. ": " .. math.floor((val * 100) + 0.5) .. "%")
			if addon.CombatMeter.functions.applyBarTextures then addon.CombatMeter.functions.applyBarTextures() end
		end
	)
	groupCore:AddChild(sliderOverlayAlpha)

	dropOverlayTex:SetDisabled(not addon.db["combatMeterUseOverlay"])
	dropOverlayBlend:SetDisabled(not addon.db["combatMeterUseOverlay"])
	sliderOverlayAlpha:SetDisabled(not addon.db["combatMeterUseOverlay"])

	local cbRounded = addon.functions.createCheckboxAce(L["Rounded Corners"], addon.db["combatMeterRoundedCorners"], function(_, _, value)
		addon.db["combatMeterRoundedCorners"] = value
		if addon.CombatMeter.functions.applyBarTextures then addon.CombatMeter.functions.applyBarTextures() end
	end)
	groupCore:AddChild(cbRounded)

	local btnReset = addon.functions.createButtonAce(L["Reset"], nil, function()
		if SlashCmdList and SlashCmdList["EQOLCM"] then SlashCmdList["EQOLCM"]("reset") end
		if addon.CombatMeter.functions.applyBarTextures then addon.CombatMeter.functions.applyBarTextures() end
		if addon.CombatMeter.functions.UpdateBars then addon.CombatMeter.functions.UpdateBars() end
	end)
	groupCore:AddChild(btnReset)

	local groupGroup = addon.functions.createContainer("InlineGroup", "List")
	groupGroup:SetTitle(L["Groups"])
	wrapper:AddChild(groupGroup)

	local metricNames = {
		dps = L["DPS"],
		damageOverall = L["Damage Overall"],
		healingPerFight = L["Healing Per Fight"],
		healingOverall = L["Healing Overall"],
	}
	local metricOrder = { "dps", "damageOverall", "healingPerFight", "healingOverall" }

	for i, cfg in ipairs(addon.db["combatMeterGroups"]) do
		local idx = i
		local groupCfg = cfg

		local row = addon.functions.createContainer("SimpleGroup", "Flow")
		groupGroup:AddChild(row)

		local label = AceGUI:Create("Label")
		label:SetText(metricNames[groupCfg.type] or groupCfg.type)
		label:SetWidth(150)
		row:AddChild(label)

		local btnRemove = addon.functions.createButtonAce(L["Remove"], nil, function()
			table.remove(addon.db["combatMeterGroups"], idx)
			addon.CombatMeter.functions.rebuildGroups()
			container:ReleaseChildren()
			addGeneralFrame(container)
		end)
		row:AddChild(btnRemove)

		local sw = addon.functions.createSliderAce(L["Bar Width"] .. ": " .. (groupCfg.barWidth or 210), groupCfg.barWidth or 210, 50, 1000, 1, function(self, _, val)
			groupCfg.barWidth = val
			self:SetLabel(L["Bar Width"] .. ": " .. val)
			addon.CombatMeter.functions.rebuildGroups()
		end)
		groupGroup:AddChild(sw)

		local sh = addon.functions.createSliderAce(L["Bar Height"] .. ": " .. (groupCfg.barHeight or 25), groupCfg.barHeight or 25, 10, 100, 1, function(self, _, val)
			groupCfg.barHeight = val
			self:SetLabel(L["Bar Height"] .. ": " .. val)
			addon.CombatMeter.functions.rebuildGroups()
		end)
		groupGroup:AddChild(sh)

		local smb = addon.functions.createSliderAce(L["Max Bars"] .. ": " .. (groupCfg.maxBars or 8), groupCfg.maxBars or 8, 1, 40, 1, function(self, _, val)
			groupCfg.maxBars = val
			self:SetLabel(L["Max Bars"] .. ": " .. val)
			addon.CombatMeter.functions.rebuildGroups()
		end)
		groupGroup:AddChild(smb)

		local cbSelf = addon.functions.createCheckboxAce(L["Always Show Self"], groupCfg.alwaysShowSelf or false, function(self, _, value)
			groupCfg.alwaysShowSelf = value
			addon.CombatMeter.functions.rebuildGroups()
		end)
		groupGroup:AddChild(cbSelf)
	end

	local addDrop = addon.functions.createDropdownAce(L["Add Group"], metricNames, metricOrder, function(self, _, val)
		table.insert(addon.db["combatMeterGroups"], {
			type = val,
			point = "CENTER",
			x = 0,
			y = 0,
			barWidth = 210,
			barHeight = 25,
			maxBars = 8,
			alwaysShowSelf = false,
		})
		addon.CombatMeter.functions.rebuildGroups()
		container:ReleaseChildren()
		addGeneralFrame(container)
	end)
	groupGroup:AddChild(addDrop)
	scroll:DoLayout()
end

function addon.CombatMeter.functions.treeCallback(container, group)
	container:ReleaseChildren()
	if group == "combatmeter\001general" then addGeneralFrame(container) end
end

addon.functions.InitDBValue("combatMeterEnabled", false)
addon.functions.InitDBValue("combatMeterHistory", {})
addon.functions.InitDBValue("combatMeterAlwaysShow", false)
addon.functions.InitDBValue("combatMeterUpdateRate", 0.2)
addon.functions.InitDBValue("combatMeterFontSize", 12)
addon.functions.InitDBValue("combatMeterNameLength", 12)
addon.functions.InitDBValue("combatMeterPrePullCapture", true)
addon.functions.InitDBValue("combatMeterPrePullWindow", 4)
addon.functions.InitDBValue("combatMeterBarTexture", TEXTURE_PATH .. "eqol_base_flat_8x8.tga")
addon.functions.InitDBValue("combatMeterUseOverlay", false)
addon.functions.InitDBValue("combatMeterOverlayTexture", TEXTURE_PATH .. "eqol_overlay_gradient_512x64.tga")
addon.functions.InitDBValue("combatMeterOverlayBlend", "ADD")
addon.functions.InitDBValue("combatMeterOverlayAlpha", 0.28)
addon.functions.InitDBValue("combatMeterRoundedCorners", false)
addon.functions.InitDBValue("combatMeterResetOnChallengeStart", true)
addon.functions.InitDBValue("combatMeterGroups", {
        {
                type = "dps",
                point = "CENTER",
                x = 0,
		y = 0,
		barWidth = 210,
		barHeight = 25,
		maxBars = 5,
		alwaysShowSelf = true,
	},
})
