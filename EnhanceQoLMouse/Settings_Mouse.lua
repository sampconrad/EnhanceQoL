local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Mouse")

local cMouse = addon.functions.SettingsCreateCategory(nil, MOUSE_LABEL, nil, "MOUSE_LABEL")
addon.SettingsLayout.mouseCategory = cMouse
addon.functions.SettingsCreateHeadline(cMouse, L["mouseRing"])

local data = {
	{
		var = "mouseRingEnabled",
		text = L["mouseRingEnabled"],
		func = function(v)
			addon.db["mouseRingEnabled"] = v
			if v then
				addon.Mouse.functions.createMouseRing()
			else
				addon.Mouse.functions.removeMouseRing()
			end
		end,
		children = {
			{
				var = "mouseRingSize",
				text = L["mouseRingSize"],
				get = function() return addon.db and addon.db.mouseRingSize or 70 end,
				set = function(v)
					addon.db["mouseRingSize"] = v
					if addon.mousePointer and addon.mousePointer.texture1 then addon.mousePointer.texture1:SetSize(v, v) end
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
						dot:SetTexture(TEX_DOT)
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
			},
			{

				var = "mouseRingOnlyInCombat",
				text = L["mouseRingOnlyInCombat"],
				func = function(v)
					addon.db["mouseRingOnlyInCombat"] = v
					if addon.mousePointer then
						if v and not UnitAffectingCombat("player") then
							addon.mousePointer:Hide()
						elseif addon.db["mouseRingEnabled"] then
							addon.mousePointer:Show()
						end
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
			},
			{

				var = "mouseRingUseClassColor",
				text = L["mouseRingUseClassColor"],
				func = function(v)
					addon.db["mouseRingUseClassColor"] = v
					if addon.mousePointer and addon.mousePointer.texture1 then
						local _, class = UnitClass("player")
						if v then
							local r, g, b = GetClassColor(class)
							addon.mousePointer.texture1:SetVertexColor(r or 1, g or 1, b or 1, 1)
						else
							local c = addon.db["mouseRingColor"] or { r = 1, g = 1, b = 1, a = 1 }
							addon.mousePointer.texture1:SetVertexColor(c.r, c.g, c.b, c.a or 1)
						end
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
				notify = "mouseRingEnabled",
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
					if addon.mousePointer and addon.mousePointer.texture1 then addon.mousePointer.texture1:SetVertexColor(r, g, b, a) end
				end,
				parent = true,
				default = false,
				headerText = "Test",
				sType = "colorpicker",
			},
		},
	},
}
table.sort(data[1].children, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cMouse, data)

addon.functions.SettingsCreateHeadline(cMouse, L["mouseTrail"])
addon.functions.SettingsCreateText(cMouse, "|cff99e599" .. L["Trailinfo"] .. "|r")

data = {
	{
		var = "mouseTrailEnabled",
		text = L["mouseTrailEnabled"],
		func = function(v) addon.db["mouseTrailEnabled"] = v end,
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
			},
			{
				list = { [1] = VIDEO_OPTIONS_LOW, [2] = VIDEO_OPTIONS_MEDIUM, [3] = VIDEO_OPTIONS_HIGH, [4] = VIDEO_OPTIONS_ULTRA, [5] = VIDEO_OPTIONS_ULTRA_HIGH, _order = { 1, 2, 3, 4, 5 } },

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
