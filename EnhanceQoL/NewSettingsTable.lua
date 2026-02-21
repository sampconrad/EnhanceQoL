local addonName, addon = ...

addon.variables.NewVersionTableEQOL = {

	-- Economy -> Bank -> Warband Bank gold sync
	["EQOL_ECONOMY"] = true,
	["EQOL_Bank"] = true,
	["EQOL_autoWarbandGold"] = true,
	["EQOL_autoWarbandGoldTargetGold"] = true,
	["EQOL_autoWarbandGoldTargetCharacter"] = true,
	["EQOL_autoWarbandGoldTargetGoldPerCharacter"] = true,
	["EQOL_autoWarbandGoldWithdraw"] = true,

	-- Interface -> Map Navigation -> Square Minimap Stats
	["EQOL_UI"] = true,
	["EQOL_MapNavigation"] = true,
	["EQOL_enableSquareMinimapStats"] = true,

	-- Interface -> Mover -> Activities -> Queue Status Button
	["EQOL_Mover"] = true,
	["EQOL_moverFrame_QueueStatusButton"] = true,
}
