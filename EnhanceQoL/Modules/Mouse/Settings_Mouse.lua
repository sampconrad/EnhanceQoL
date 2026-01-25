local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Mouse")
local LMain = LibStub("AceLocale-3.0"):GetLocale(parentAddonName)
local getCVarOptionState = addon.functions.GetCVarOptionState or function() return false end
local setCVarOptionState = addon.functions.SetCVarOptionState or function() end

local cMouse = addon.SettingsLayout.rootGENERAL

local expandable = addon.functions.SettingsCreateExpandableSection(cMouse, {
	name = (LMain and LMain["MouseAndAccessibility"]) or "Mouse & Accessibility",
	expanded = false,
	colorizeTitle = false,
})

addon.functions.SettingsCreateCheckbox(cMouse, {
	var = "enableMouseoverCast",
	text = (LMain and LMain["enableMouseoverCast"]) or "Enable Mouseover Cast",
	get = function() return getCVarOptionState("enableMouseoverCast") end,
	func = function(value) setCVarOptionState("enableMouseoverCast", value) end,
	default = false,
	parentSection = expandable,
})

addon.functions.SettingsCreateHeadline(cMouse, L["mouseRing"], { parentSection = expandable })

local data = {
	{
		var = "mouseRingEnabled",
		text = L["mouseRingEnabled"],
		func = function(v)
			addon.db["mouseRingEnabled"] = v
			if v then
				if addon.Mouse.functions.refreshRingVisibility then
					addon.Mouse.functions.refreshRingVisibility()
				else
					addon.Mouse.functions.createMouseRing()
				end
			else
				addon.Mouse.functions.removeMouseRing()
			end
			if addon.Mouse.functions.updateRunnerState then addon.Mouse.functions.updateRunnerState() end
		end,
		parentSection = expandable,
		children = {
			{
				var = "mouseRingSize",
				text = L["mouseRingSize"],
				get = function() return addon.db and addon.db.mouseRingSize or 70 end,
				set = function(v)
					addon.db["mouseRingSize"] = v
					if addon.Mouse.functions.refreshRingStyle then addon.Mouse.functions.refreshRingStyle() end
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["mouseRingEnabled"]
						and addon.SettingsLayout.elements["mouseRingEnabled"].setting
						and addon.SettingsLayout.elements["mouseRingEnabled"].setting:GetValue() == true
				end,
				min = 20,
				max = 200,
				step = 1,
				parent = true,
				default = 70,
				sType = "slider",
				parentSection = expandable,
			},
			{

				var = "mouseRingHideDot",
				text = L["mouseRingHideDot"],
				func = function(v)
					addon.db["mouseRingHideDot"] = v
					if addon.mousePointer and addon.mousePointer.dot then
						if v then
							addon.mousePointer.dot:Hide()
						else
							addon.mousePointer.dot:Show()
						end
					elseif addon.mousePointer and not v then
						local dot = addon.mousePointer:CreateTexture(nil, "BACKGROUND")
						dot:SetTexture(addon.Mouse.variables.TEXT_DOT)
						dot:SetSize(10, 10)
						dot:SetPoint("CENTER", addon.mousePointer, "CENTER", 0, 0)
						addon.mousePointer.dot = dot
					end
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["mouseRingEnabled"]
						and addon.SettingsLayout.elements["mouseRingEnabled"].setting
						and addon.SettingsLayout.elements["mouseRingEnabled"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
				parentSection = expandable,
			},
			{

				var = "mouseRingOnlyInCombat",
				text = L["mouseRingOnlyInCombat"],
				func = function(v)
					addon.db["mouseRingOnlyInCombat"] = v
					if addon.Mouse.functions.refreshRingVisibility then addon.Mouse.functions.refreshRingVisibility() end
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["mouseRingEnabled"]
						and addon.SettingsLayout.elements["mouseRingEnabled"].setting
						and addon.SettingsLayout.elements["mouseRingEnabled"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
				parentSection = expandable,
			},
			{
				var = "mouseRingOnlyOnRightClick",
				text = L["mouseRingOnlyOnRightClick"],
				func = function(v)
					addon.db["mouseRingOnlyOnRightClick"] = v
					if addon.Mouse.functions.refreshRingVisibility then addon.Mouse.functions.refreshRingVisibility() end
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["mouseRingEnabled"]
						and addon.SettingsLayout.elements["mouseRingEnabled"].setting
						and addon.SettingsLayout.elements["mouseRingEnabled"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
				parentSection = expandable,
			},
			{
				var = "mouseRingCombatOverride",
				text = L["mouseRingCombatOverride"],
				func = function(v)
					addon.db["mouseRingCombatOverride"] = v
					if addon.Mouse.functions.refreshRingStyle then addon.Mouse.functions.refreshRingStyle() end
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["mouseRingEnabled"]
						and addon.SettingsLayout.elements["mouseRingEnabled"].setting
						and addon.SettingsLayout.elements["mouseRingEnabled"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
				parentSection = expandable,
				children = {
					{
						var = "mouseRingCombatOverrideSize",
						text = L["mouseRingCombatOverrideSize"],
						get = function() return addon.db and addon.db.mouseRingCombatOverrideSize or 70 end,
						set = function(v)
							addon.db["mouseRingCombatOverrideSize"] = v
							if addon.Mouse.functions.refreshRingStyle then addon.Mouse.functions.refreshRingStyle() end
						end,
						parentCheck = function()
							return addon.SettingsLayout.elements["mouseRingEnabled"]
								and addon.SettingsLayout.elements["mouseRingEnabled"].setting
								and addon.SettingsLayout.elements["mouseRingEnabled"].setting:GetValue() == true
								and addon.SettingsLayout.elements["mouseRingCombatOverride"]
								and addon.SettingsLayout.elements["mouseRingCombatOverride"].setting
								and addon.SettingsLayout.elements["mouseRingCombatOverride"].setting:GetValue() == true
						end,
						min = 20,
						max = 200,
						step = 1,
						parent = true,
						default = 70,
						sType = "slider",
						parentSection = expandable,
					},
					{
						var = "mouseRingCombatOverrideColor",
						text = L["mouseRingCombatOverrideColor"],
						parentCheck = function()
							return addon.SettingsLayout.elements["mouseRingEnabled"]
								and addon.SettingsLayout.elements["mouseRingEnabled"].setting
								and addon.SettingsLayout.elements["mouseRingEnabled"].setting:GetValue() == true
								and addon.SettingsLayout.elements["mouseRingCombatOverride"]
								and addon.SettingsLayout.elements["mouseRingCombatOverride"].setting
								and addon.SettingsLayout.elements["mouseRingCombatOverride"].setting:GetValue() == true
						end,
						callback = function(r, g, b, a)
							if addon.Mouse.functions.refreshRingStyle then addon.Mouse.functions.refreshRingStyle() end
						end,
						parent = true,
						sType = "colorpicker",
						parentSection = expandable,
					},
				},
			},
			{
				var = "mouseRingCombatOverlay",
				text = L["mouseRingCombatOverlay"],
				func = function(v)
					addon.db["mouseRingCombatOverlay"] = v
					if addon.Mouse.functions.refreshRingStyle then addon.Mouse.functions.refreshRingStyle() end
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["mouseRingEnabled"]
						and addon.SettingsLayout.elements["mouseRingEnabled"].setting
						and addon.SettingsLayout.elements["mouseRingEnabled"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
				parentSection = expandable,
				children = {
					{
						var = "mouseRingCombatOverlaySize",
						text = L["mouseRingCombatOverlaySize"],
						get = function() return addon.db and addon.db.mouseRingCombatOverlaySize or 90 end,
						set = function(v)
							addon.db["mouseRingCombatOverlaySize"] = v
							if addon.Mouse.functions.refreshRingStyle then addon.Mouse.functions.refreshRingStyle() end
						end,
						parentCheck = function()
							return addon.SettingsLayout.elements["mouseRingEnabled"]
								and addon.SettingsLayout.elements["mouseRingEnabled"].setting
								and addon.SettingsLayout.elements["mouseRingEnabled"].setting:GetValue() == true
								and addon.SettingsLayout.elements["mouseRingCombatOverlay"]
								and addon.SettingsLayout.elements["mouseRingCombatOverlay"].setting
								and addon.SettingsLayout.elements["mouseRingCombatOverlay"].setting:GetValue() == true
						end,
						min = 20,
						max = 240,
						step = 1,
						parent = true,
						default = 90,
						sType = "slider",
						parentSection = expandable,
					},
					{
						var = "mouseRingCombatOverlayColor",
						text = L["mouseRingCombatOverlayColor"],
						parentCheck = function()
							return addon.SettingsLayout.elements["mouseRingEnabled"]
								and addon.SettingsLayout.elements["mouseRingEnabled"].setting
								and addon.SettingsLayout.elements["mouseRingEnabled"].setting:GetValue() == true
								and addon.SettingsLayout.elements["mouseRingCombatOverlay"]
								and addon.SettingsLayout.elements["mouseRingCombatOverlay"].setting
								and addon.SettingsLayout.elements["mouseRingCombatOverlay"].setting:GetValue() == true
						end,
						callback = function(r, g, b, a)
							if addon.Mouse.functions.refreshRingStyle then addon.Mouse.functions.refreshRingStyle() end
						end,
						parent = true,
						sType = "colorpicker",
						parentSection = expandable,
					},
				},
			},
			{

				var = "mouseRingUseClassColor",
				text = L["mouseRingUseClassColor"],
				func = function(v)
					addon.db["mouseRingUseClassColor"] = v
					if addon.Mouse.functions.refreshRingStyle then addon.Mouse.functions.refreshRingStyle() end
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["mouseRingEnabled"]
						and addon.SettingsLayout.elements["mouseRingEnabled"].setting
						and addon.SettingsLayout.elements["mouseRingEnabled"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
				notify = "mouseRingEnabled",
				parentSection = expandable,
			},
			{
				var = "mouseRingColor",
				text = L["Ring Color"],
				parentCheck = function()
					return addon.SettingsLayout.elements["mouseRingEnabled"]
						and addon.SettingsLayout.elements["mouseRingEnabled"].setting
						and addon.SettingsLayout.elements["mouseRingEnabled"].setting:GetValue() == true
						and addon.SettingsLayout.elements["mouseRingUseClassColor"]
						and addon.SettingsLayout.elements["mouseRingUseClassColor"].setting
						and addon.SettingsLayout.elements["mouseRingUseClassColor"].setting:GetValue() == false
				end,
				callback = function(r, g, b, a)
					if addon.Mouse.functions.refreshRingStyle then addon.Mouse.functions.refreshRingStyle() end
				end,
				parent = true,
				default = false,
				headerText = "Test",
				sType = "colorpicker",
				parentSection = expandable,
			},
		},
	},
}
table.sort(data[1].children, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cMouse, data)

addon.functions.SettingsCreateHeadline(cMouse, L["mouseTrail"], { parentSection = expandable })
addon.functions.SettingsCreateText(cMouse, "|cff99e599" .. L["Trailinfo"] .. "|r", { parentSection = expandable })

data = {
	{
		var = "mouseTrailEnabled",
		text = L["mouseTrailEnabled"],
		func = function(v)
			addon.db["mouseTrailEnabled"] = v
			if addon.Mouse.functions.updateRunnerState then addon.Mouse.functions.updateRunnerState() end
		end,
		parentSection = expandable,
		children = {
			{

				var = "mouseTrailOnlyInCombat",
				text = L["mouseTrailOnlyInCombat"],
				func = function(v) addon.db["mouseTrailOnlyInCombat"] = v end,
				parentCheck = function()
					return addon.SettingsLayout.elements["mouseTrailEnabled"]
						and addon.SettingsLayout.elements["mouseTrailEnabled"].setting
						and addon.SettingsLayout.elements["mouseTrailEnabled"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
				parentSection = expandable,
			},
			{

				var = "mouseTrailUseClassColor",
				text = L["mouseTrailUseClassColor"],
				func = function(v) addon.db["mouseTrailUseClassColor"] = v end,
				parentCheck = function()
					return addon.SettingsLayout.elements["mouseTrailEnabled"]
						and addon.SettingsLayout.elements["mouseTrailEnabled"].setting
						and addon.SettingsLayout.elements["mouseTrailEnabled"].setting:GetValue() == true
				end,
				parent = true,
				default = false,
				type = Settings.VarType.Boolean,
				sType = "checkbox",
				notify = "mouseTrailEnabled",
				parentSection = expandable,
			},
			{
				var = "mouseTrailColor",
				text = L["Trail Color"],
				parentCheck = function()
					return addon.SettingsLayout.elements["mouseTrailEnabled"]
						and addon.SettingsLayout.elements["mouseTrailEnabled"].setting
						and addon.SettingsLayout.elements["mouseTrailEnabled"].setting:GetValue() == true
						and addon.SettingsLayout.elements["mouseTrailUseClassColor"]
						and addon.SettingsLayout.elements["mouseTrailUseClassColor"].setting
						and addon.SettingsLayout.elements["mouseTrailUseClassColor"].setting:GetValue() == false
				end,
				parent = true,
				default = false,
				sType = "colorpicker",
				parentSection = expandable,
			},
			{
				list = { [1] = VIDEO_OPTIONS_LOW, [2] = VIDEO_OPTIONS_MEDIUM, [3] = VIDEO_OPTIONS_HIGH, [4] = VIDEO_OPTIONS_ULTRA, [5] = VIDEO_OPTIONS_ULTRA_HIGH },
				order = { 1, 2, 3, 4, 5 },
				text = L["mouseTrailDensity"],
				get = function() return addon.db["mouseTrailDensity"] or 1 end,
				set = function(key)
					addon.db["mouseTrailDensity"] = key
					addon.Mouse.functions.applyPreset(addon.db["mouseTrailDensity"])
				end,
				parentCheck = function()
					return addon.SettingsLayout.elements["mouseTrailEnabled"]
						and addon.SettingsLayout.elements["mouseTrailEnabled"].setting
						and addon.SettingsLayout.elements["mouseTrailEnabled"].setting:GetValue() == true
				end,
				parent = true,
				default = 1,
				var = "mouseTrailDensity",
				type = Settings.VarType.Number,
				sType = "dropdown",
				parentSection = expandable,
			},
		},
	},
}
table.sort(data[1].children, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cMouse, data)

----- REGION END

function addon.functions.initMouse() end

local eventHandlers = {}

local function registerEvents(frame)
	for event in pairs(eventHandlers) do
		frame:RegisterEvent(event)
	end
end

local function eventHandler(self, event, ...)
	if eventHandlers[event] then eventHandlers[event](...) end
end

local frameLoad = CreateFrame("Frame")

registerEvents(frameLoad)
frameLoad:SetScript("OnEvent", eventHandler)
