local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Aura = addon.Aura or {}
addon.Aura.functions = addon.Aura.functions or {}
addon.Aura.variables = addon.Aura.variables or {}

function addon.Aura.functions.InitDB()
	if not addon.db or not addon.functions or not addon.functions.InitDBValue then return end
	local init = addon.functions.InitDBValue

	-- resource bar defaults
	init("enableResourceFrame", false)
	init("resourceBarsHideOutOfCombat", false)
	init("resourceBarsHideMounted", false)
	init("resourceBarsHideVehicle", false)
	init("resourceBarsHidePetBattle", false)
	init("resourceBarsHideClientScene", true)
	if addon.db.resourceBarsHidePetBattle == nil and addon.db.auraHideInPetBattle ~= nil then addon.db.resourceBarsHidePetBattle = addon.db.auraHideInPetBattle and true or false end

	-- spec specific settings for personal resource bars
	init("personalResourceBarSettings", {})
	init("personalResourceBarAnchors", {})

	init("cooldownPanels", {
		version = 1,
		panels = {},
		order = {},
		selectedPanel = nil,
		defaults = {
			layout = {
				iconSize = 36,
				spacing = 2,
				direction = "RIGHT",
				wrapCount = 0,
				wrapDirection = "DOWN",
				strata = "MEDIUM",
			},
			entry = {
				alwaysShow = true,
				showCooldown = true,
				showCooldownText = true,
				showCharges = false,
				showStacks = false,
				glowReady = false,
				glowDuration = 0,
			},
		},
	})
	init("cooldownPanelsEditorPoint", "CENTER")
	init("cooldownPanelsEditorX", 0)
	init("cooldownPanelsEditorY", 0)

	if addon.Aura and addon.Aura.CooldownPanels and addon.Aura.CooldownPanels.NormalizeAll then addon.Aura.CooldownPanels:NormalizeAll() end
end
