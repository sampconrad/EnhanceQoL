local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local ActionTracker = addon.ActionTracker

local ignorelist = {
	[75] = true, -- Auto Shot
	[836] = true, -- Login effect
	[5374] = true, -- Mutilate
	[7268] = true, -- Arcane Missiles
	[72734] = true, -- Mass Dispel fake
	[27576] = true, -- Mutilate
	[32175] = true, -- Stormstrike
	[32176] = true, -- Stormstrike (Off-Hand)
	[4036] = true, -- Engineering basic
	[50622] = true, -- Bladestorm
	[52174] = true, -- Heroic Leap
	[57794] = true, -- Heroic Leap
	[61391] = true, -- Typhoon
	[84721] = true, -- Frozen Orb
	[85384] = true, -- Raging Blow
	[88263] = true, -- Hammer of the Righteous
	[96103] = true, -- Raging Blow
	[102794] = true, -- Ursol's Vortex
	[107270] = true, -- Spinning Crane Kick
	[110745] = true, -- Divine Star
	[114089] = true, -- Windlash
	[114093] = true, -- Windlash Off-Hand
	[115357] = true, -- Windstrike
	[115360] = true, -- Windstrike Off-Hand
	[115464] = true, -- Healing Sphere
	[120692] = true, -- Halo
	[120696] = true, -- Halo
	[121473] = true, -- Shadow Blade
	[121474] = true, -- Shadow Blade Off-hand
	[122128] = true, -- Divine Star
	[126664] = true, -- Charge fake
	[127797] = true, -- Ursol's Vortex
	[132951] = true, -- Flare
	[135299] = true, -- Tar Trap
	[155777] = true, -- Germination fake
	[157982] = true, -- Tranquility tick
	[184707] = true, -- Rampage
	[184709] = true, -- Rampage
	[197886] = true, -- Artifact weapon garbage
	[198928] = true, -- Cinderstorm
	[196771] = true, -- Remoseless Winter fake
	[145629] = true, -- AMZ fake
	[47750] = true, -- Penance fake
	[81782] = true, -- PW Barrier fake
	[397374] = true, -- Empower Instant cast fake
	[363922] = true, -- Dream breath fake
	[64844] = true, -- Divine Hymn fake
	[2550] = true, -- Cooking basic
	[199672] = true, -- Rupture
	[201363] = true, -- Rampage
	[201364] = true, -- Rampage
	[204255] = true, -- Soul Fragments
	[213241] = true, -- Felblade
	[213243] = true, -- Felblade
	[218617] = true, -- Rampage
	[225919] = true, -- Fracture
	[225921] = true, -- Fracture
	[228354] = true, -- Flurry
	[228537] = true, -- Shattered Souls
	[228597] = true, -- Frostbolt
	[240022] = true, -- Broken Shore fake
	[272790] = true, -- Frenzy; BM hunter buff
	[276245] = true, -- Env; envenom buff
	[337819] = true, -- Screaming Brutality - Throw Glaive
	[346665] = true, -- Throw Glaive
	[361195] = true, -- Verdant Embrace friendly heal
	[361509] = true, -- Living Flame friendly heal
	[367230] = true, -- Spiritbloom
	[370966] = true, -- The Hunt Impact (DH Class Tree Talent)
	[371817] = true, -- Recall fake mage
	[372120] = true, -- Fake buff
	[383313] = true, -- Abomination Limb periodical
	[384255] = true, -- Change Talents
	[385060] = true, -- Odyn's Fury
	[385061] = true, -- Odyn's Fury
	[385062] = true, -- Odyn's Fury
	[385954] = true, -- Shield Charge
	[388658] = true, -- Fake blacksmith
	[391775] = true, -- Cooking DNT
	[391312] = true, -- Fake tailor
	[394003] = true, -- Spark of Madness
	[394009] = true, -- Fish fake
	[394007] = true, -- Engi fake
	[395369] = true, -- Fish DNT
	[395392] = true, -- Fake blacksmith
	[395396] = true, -- Fake tailor
	[395397] = true, -- Engineering DNT
	[395470] = true, -- Engineering DNT
	[395471] = true, -- Same
	[395394] = true, -- Alchemy DNT
	[395473] = true, -- Alchemy DNT
	[395475] = true, -- Fake blacksmith
	[455760] = true, -- Alchemy DNT
	[455693] = true, -- Tailor DNT
	[455711] = true, -- Fake tailer
	[455720] = true, -- Same
	[455694] = true, -- Fake blacksmith
	[455727] = true, -- Fake blacksmith
	[455789] = true, -- Engi DNT
	[393035] = true, -- Throw Glaive
	[408385] = true, -- Crusading Strikes
	[410499] = true, -- Fake rested
	[429826] = true, -- Hammer of Light
	[431398] = true, -- Empyrean Hammer
	[434144] = true, -- Infliction of Sorrow fake cast
	[437965] = true, -- Pulsing Flames, fake cast in Cinderbrew Area first pull
	[441426] = true, -- Exterminate cleave
	[441437] = true, -- Arachnophobia
	[456640] = true, -- Consuming Fire fake cast
	[455706] = true, -- Profession DNT
	[455701] = true, -- Profession Engineering
	[455773] = true, -- Profession DNT
	[455712] = true, -- Cooking
	[455738] = true, -- Cooking
	[458357] = true, -- Chain Heal via Lively Totems
	[470411] = true, -- Flame Shock fake cast
	[1270292] = true, -- Lunar beam fake
	[1251595] = true, -- Flamefang Pitch, Midnight Survival Hunter
	[1253859] = true, -- Takedown, Midnight Survival Hunter
	[1263886] = true, -- Transmog fake call
	[395472] = true, -- Cooking
}

ActionTracker.ignoreList = ignorelist

local cUI = addon.SettingsLayout.rootUI

local expandable = addon.functions.SettingsCreateExpandableSection(cUI, {
	name = L["ActionTracker"] or "Action Tracker",
	expanded = false,
	colorizeTitle = false,
})

addon.functions.SettingsCreateText(cUI, L["actionTrackerDesc"] or "Shows your most recently cast spells as icons.", {
	parentSection = expandable,
})

addon.functions.SettingsCreateCheckbox(cUI, {
	var = "actionTrackerEnabled",
	text = L["actionTrackerEnabled"] or "Enable Action Tracker",
	func = function(value)
		addon.db["actionTrackerEnabled"] = value and true or false
		if addon.ActionTracker and addon.ActionTracker.OnSettingChanged then addon.ActionTracker:OnSettingChanged(addon.db["actionTrackerEnabled"]) end
	end,
	parentSection = expandable,
})

addon.functions.SettingsCreateText(cUI, "|cffffd700" .. (L["actionTrackerEditModeHint"] or "Use Edit Mode to configure the tracker.") .. "|r", {
	parentSection = expandable,
})

function addon.functions.initActionTracker()
	local defaults = (ActionTracker and ActionTracker.defaults) or {}
	addon.functions.InitDBValue("actionTrackerEnabled", false)
	addon.functions.InitDBValue("actionTrackerMaxIcons", defaults.maxIcons or 5)
	addon.functions.InitDBValue("actionTrackerIconSize", defaults.iconSize or 48)
	addon.functions.InitDBValue("actionTrackerSpacing", defaults.spacing or 0)
	addon.functions.InitDBValue("actionTrackerDirection", defaults.direction or "RIGHT")
	addon.functions.InitDBValue("actionTrackerFadeDuration", defaults.fadeDuration or 0)
	addon.functions.InitDBValue("actionTrackerShowElapsed", defaults.showElapsed or false)

	if addon.ActionTracker and addon.ActionTracker.OnSettingChanged then addon.ActionTracker:OnSettingChanged(addon.db["actionTrackerEnabled"]) end
end
