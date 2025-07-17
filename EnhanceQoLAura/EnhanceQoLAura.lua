-- Store the original Blizzard SetupMenu generator for rewrapping
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

addon.tempScrollPos = 0 -- holds last scroll offset for Essential list

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")
local AceGUI = addon.AceGUI

local tabContainerMain

local function addResourceFrame(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)

	local data = {
		{
			text = "Enable Resource frame",
			var = "enableResourceFrame",
			func = function(self, _, value)
				addon.db["enableResourceFrame"] = value
				if value then
					addon.Aura.ResourceBars.EnableResourceBars()
				elseif addon.Aura.ResourceBars and addon.Aura.ResourceBars.DisableResourceBars then
					addon.Aura.ResourceBars.DisableResourceBars()
				end
			end,
		},
	}

	table.sort(data, function(a, b) return a.text < b.text end)

	for _, cbData in ipairs(data) do
		local uFunc = function(self, _, value) addon.db[cbData.var] = value end
		if cbData.func then uFunc = cbData.func end
		local cbElement = addon.functions.createCheckboxAce(cbData.text, addon.db[cbData.var], uFunc)
		groupCore:AddChild(cbElement)
	end

	if addon.db["enableResourceFrame"] then
		local data = {
			{
				text = "Healthbar Width",
				var = "personalResourceBarHealthWidth",
				func = function(self, _, value)
					addon.db["personalResourceBarHealthWidth"] = value
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.SetHealthBarSize then
						addon.Aura.ResourceBars.SetHealthBarSize(addon.db["personalResourceBarHealthWidth"], addon.db["personalResourceBarHealthHeight"])
					end
				end,
				min = 1,
				max = 2000,
			},
			{
				text = "Healthbar Height",
				var = "personalResourceBarHealthHeight",
				func = function(self, _, value)
					addon.db["personalResourceBarHealthHeight"] = value
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.SetHealthBarSize then
						addon.Aura.ResourceBars.SetHealthBarSize(addon.db["personalResourceBarHealthWidth"], addon.db["personalResourceBarHealthHeight"])
					end
				end,
				min = 1,
				max = 2000,
			},
			{
				text = "Manabar Width",
				var = "personalResourceBarManaWidth",
				func = function(self, _, value)
					addon.db["personalResourceBarManaWidth"] = value
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.SetPowerBarSize then
						addon.Aura.ResourceBars.SetPowerBarSize(addon.db["personalResourceBarManaWidth"], addon.db["personalResourceBarManaHeight"])
					end
				end,
				min = 1,
				max = 2000,
			},
			{
				text = "Manabar Height",
				var = "personalResourceBarManaHeight",
				func = function(self, _, value)
					addon.db["personalResourceBarManaHeight"] = value
					if addon.Aura.ResourceBars and addon.Aura.ResourceBars.SetPowerBarSize then
						addon.Aura.ResourceBars.SetPowerBarSize(addon.db["personalResourceBarManaWidth"], addon.db["personalResourceBarManaHeight"])
					end
				end,
				min = 1,
				max = 100,
			},
		}

		for _, cbData in ipairs(data) do
			local uFunc = function(self, _, value) addon.db[cbData.var] = value end
			if cbData.func then uFunc = cbData.func end

			local healthBarWidth = addon.functions.createSliderAce(cbData.text, addon.db[cbData.var], cbData.min, cbData.max, 1, uFunc)
			healthBarWidth:SetFullWidth(true)
			groupCore:AddChild(healthBarWidth)

			groupCore:AddChild(addon.functions.createSpacerAce())
		end

		local anchorPoints = {
			TOPLEFT = "TOPLEFT",
			TOP = "TOP",
			TOPRIGHT = "TOPRIGHT",
			LEFT = "LEFT",
			CENTER = "CENTER",
			RIGHT = "RIGHT",
			BOTTOMLEFT = "BOTTOMLEFT",
			BOTTOM = "BOTTOM",
			BOTTOMRIGHT = "BOTTOMRIGHT",
		}
		local anchorOrder = {
			"TOPLEFT",
			"TOP",
			"TOPRIGHT",
			"LEFT",
			"CENTER",
			"RIGHT",
			"BOTTOMLEFT",
			"BOTTOM",
			"BOTTOMRIGHT",
		}

		local baseFrameList = {
			UIParent = "UIParent",
			PlayerFrame = "PlayerFrame",
			TargetFrame = "TargetFrame",
		}

		local function addAnchorOptions(barType, parent, info, frameList)
			info = info or {}
			frameList = frameList or baseFrameList

			local header = addon.functions.createLabelAce(barType .. " Anchor")
			parent:AddChild(header)

			local dropFrame = addon.functions.createDropdownAce("Relative Frame", frameList, nil, function(self, _, val)
				info.relativeFrame = val
				if addon.Aura.ResourceBars then addon.Aura.ResourceBars.Refresh() end
			end)
			dropFrame:SetValue(info.relativeFrame or "UIParent")
			parent:AddChild(dropFrame)

			local dropPoint = addon.functions.createDropdownAce("Point", anchorPoints, anchorOrder, function(self, _, val)
				info.point = val
				if addon.Aura.ResourceBars then addon.Aura.ResourceBars.Refresh() end
			end)
			dropPoint:SetValue(info.point or "TOPLEFT")
			parent:AddChild(dropPoint)

			local dropRelPoint = addon.functions.createDropdownAce("Relative Point", anchorPoints, anchorOrder, function(self, _, val)
				info.relativePoint = val
				if addon.Aura.ResourceBars then addon.Aura.ResourceBars.Refresh() end
			end)
			dropRelPoint:SetValue(info.relativePoint or info.point or "TOPLEFT")
			parent:AddChild(dropRelPoint)

			local editX = addon.functions.createEditboxAce("X", tostring(info.x or 0), function(self)
				info.x = tonumber(self:GetText()) or 0
				if addon.Aura.ResourceBars then addon.Aura.ResourceBars.Refresh() end
			end)
			parent:AddChild(editX)

			local editY = addon.functions.createEditboxAce("Y", tostring(info.y or 0), function(self)
				info.y = tonumber(self:GetText()) or 0
				if addon.Aura.ResourceBars then addon.Aura.ResourceBars.Refresh() end
			end)
			parent:AddChild(editY)

			parent:AddChild(addon.functions.createSpacerAce())
		end

		local specTabs = {}
		for i = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(addon.variables.unitClassID) do
			local _, specName = GetSpecializationInfoForClassID(addon.variables.unitClassID, i)
			table.insert(specTabs, { text = specName, value = i })
		end

		local function buildSpec(container, specIndex)
			container:ReleaseChildren()
			if not addon.Aura.ResourceBars.powertypeClasses[addon.variables.unitClass] then return end
			local specInfo = addon.Aura.ResourceBars.powertypeClasses[addon.variables.unitClass][specIndex]
			if not specInfo then return end

			addon.db.personalResourceBarSettings[addon.variables.unitClass] = addon.db.personalResourceBarSettings[addon.variables.unitClass] or {}
			addon.db.personalResourceBarSettings[addon.variables.unitClass][specIndex] = addon.db.personalResourceBarSettings[addon.variables.unitClass][specIndex] or {}
			local dbSpec = addon.db.personalResourceBarSettings[addon.variables.unitClass][specIndex]

			for _, pType in ipairs(addon.Aura.ResourceBars.classPowerTypes) do
				local real
				if specInfo.MAIN == pType then
					real = specInfo.MAIN
				elseif specInfo[pType] then
					real = pType
				end
				if real then
					dbSpec[real] = dbSpec[real]
						or {
							enabled = true,
							width = addon.db["personalResourceBarManaWidth"],
							height = addon.db["personalResourceBarManaHeight"],
							textStyle = real == "MANA" and "PERCENT" or "CURMAX",
							fontSize = 16,
						}
					dbSpec[real].anchor = dbSpec[real].anchor or {}

					local cfg = dbSpec[real]
					local label = _G[real] or real
                                        local cb = addon.functions.createCheckboxAce(label, cfg.enabled, function(self, _, val)
                                                cfg.enabled = val
                                                addon.Aura.ResourceBars.Refresh()
                                                container:ReleaseChildren()
                                                addResourceFrame(container)
                                                buildSpec(tabContainerMain, specIndex)
                                        end)
					container:AddChild(cb)

					if cfg.enabled then
						local sw = addon.functions.createSliderAce("Width", cfg.width, 1, 2000, 1, function(self, _, val)
							cfg.width = val
							addon.Aura.ResourceBars.SetPowerBarSize(val, cfg.height, real)
						end)
						container:AddChild(sw)
						local sh = addon.functions.createSliderAce("Height", cfg.height, 1, 2000, 1, function(self, _, val)
							cfg.height = val
							addon.Aura.ResourceBars.SetPowerBarSize(cfg.width, val, real)
						end)
						container:AddChild(sh)

						local tList = { PERCENT = "Percentage", CURMAX = "Current/Max", CURRENT = "Current" }
						local tOrder = { "PERCENT", "CURMAX", "CURRENT" }
						local drop = addon.functions.createDropdownAce("Text", tList, tOrder, function(self, _, key)
							cfg.textStyle = key
							addon.Aura.ResourceBars.Refresh()
						end)
						drop:SetValue(cfg.textStyle)
						container:AddChild(drop)

						local sFont = addon.functions.createSliderAce("Text Size", cfg.fontSize or 16, 6, 64, 1, function(self, _, val)
							cfg.fontSize = val
							addon.Aura.ResourceBars.Refresh()
						end)
						container:AddChild(sFont)

						local frames = {}
						for k, v in pairs(baseFrameList) do
							frames[k] = v
						end
						frames.EQOLHealthBar = "EQOLHealthBar"
						for _, t in ipairs(addon.Aura.ResourceBars.classPowerTypes) do
							if dbSpec[t] and dbSpec[t].enabled ~= false then frames["EQOL" .. t .. "Bar"] = "EQOL" .. t .. "Bar" end
						end

						addAnchorOptions(real, container, cfg.anchor, frames)
					end
					container:AddChild(addon.functions.createSpacerAce())
				end
			end
		end

		local tabGroup = addon.functions.createContainer("TabGroup", "Flow")
		tabGroup:SetTabs(specTabs)
		tabGroup:SetCallback("OnGroupSelected", function(tabContainer, _, val)
			tabContainerMain = tabContainer
			buildSpec(tabContainer, val)
		end)
		wrapper:AddChild(tabGroup)
		tabGroup:SelectTab(addon.variables.unitSpec or specTabs[1].value)
	end
	scroll:DoLayout()
end

addon.variables.statusTable.groups["aura"] = true

addon.functions.addToTree(nil, {
	value = "aura",
	text = L["Aura"],
	children = {
		{ value = "resourcebar", text = DISPLAY_PERSONAL_RESOURCE },
		{ value = "bufftracker", text = L["BuffTracker"] },
	},
})

function addon.Aura.functions.treeCallback(container, group)
	container:ReleaseChildren()
	if group == "aura\001resourcebar" then
		addResourceFrame(container)
	elseif group == "aura\001bufftracker" then
		addon.Aura.functions.addBuffTrackerOptions(container)
		addon.Aura.scanBuffs()
	end
end
