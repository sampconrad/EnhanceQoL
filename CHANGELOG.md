# Changelog

## [6.5.0] – 2025-12-22

### ✨ Added

- Maelstrom Weapon tracking added as Resourcebar for Enhancement Shaman
- Devourer Resource bar tracking added (but disabled until next beta release of WoW - Will be non-secret than)
- Tooltips for Spell/Item/Aura-IDs enabled in Combat with better secret handling for midnight
- UF Plus now let's you enable/disable and change Raid Icons size/offset
- UF Plus now let's you show the blizzard class resources and manage it
- UF Plus optional castbar for boss frames added

### ❌ Removed

- Removed the option to show party frames in solo content

### 🐛 Fixed

- Rune cooldown text now renders above the border to avoid clipping at small bar heights
- Unit Frame status line settings now correctly gate name/level options and combat indicator sub-options

## [6.4.0] – 2025-12-17

### ✨ Added

- **Chat History**
  - Saves chat per character and channel (up to 2000 lines per channel/char), with live filters (including Currency), loot-quality multidropdown.
- Action Bars: optional toggle to hide the Extra Action/Zone Ability artwork and disable mouse input on the Extra Action bar.
- Collections: optional auto-unwrap for new mounts, pets, and toys (clears fanfare/alerts).
- UI & Input: toggle to hide the micro menu notification diamonds.
- Mythic+: keybind to open the World Map Teleport panel directly.
- Action Bars: out-of-range highlight now tints the action button icon directly (no separate overlay), using your chosen color/alpha.
- Profiles: export/import the active profile (full overwrite) via copy/paste with reload after import.
- Added Naaru's Enfold toy (ID 263489) support to teleport/hearthstone handling.

### 🔄 Changed

- Minimap Button Sink frame now uses `DIALOG` strata for its buttons inherit that strata with elevated frame levels so the bin stays above nearby UI elements.

### 🐛 Fixed

- Added missing visibility rule localization (and translations) to eliminate the AceLocale warning when Enhanced Unit Frames locks visibility.
- Assisted Combat Button Rotation border hide had an error with updating the button
- Cooldown Viewer visibility now only hooks mouseover/polling when a visibility rule is set, preventing unintended alpha changes.
- Cooldown Viewer frames no longer lose click-through behavior when using EQOL.
- UF Plus had an issue with some secret states

---

## [6.3.0] – 2025-12-14

### ✨ Added

- World Map: Optional player/cursor coordinates near the title (updates only while the map is open).
- Unit Frames (Target auras): stack text is now configurable (position, X/Y offsets, font size, and outline).
- Character frame and bag item level dropdowns now offer explicit TOP/CENTER/BOTTOM and LEFT/RIGHT anchors.

### 🔄 Changed

- TOC Update for midnight 12.0.1

### 🐛 Fixed

- Changed some removed API-calls to the new once introduced in 12.0.1
- `/way` parser now accepts two coordinate values followed by descriptive text (e.g., `/way 26.90 28.89 Melody 2nd`) without treating the note as extra arguments.
- Castbar in midnight fixed for UF Plus
- Tooltip: Item ID display now respects its toggle (no ID when disabled), and item icon size defaults are aligned to 16.

---

## [6.2.0] – 2025-12-11

### Important note

Minimap button behavior has changed:

- Left-click now opens the new options menu.
- Right-click now offers a shortcut to open the old legacy settings (until Midnight launches; legacy settings will likely be removed in Midnight).

### ✨ Added

- Currency Stream: per-currency shortening option.
- Button Sink: option to hide the border and/or background.
- Reputation / XP bar: scaling, width, and height settings.
- World Marker Cycle:
  - New keybind to cycle through all world markers.
  - New keybind to clear all world markers.
- Action Bars: option to hide action button borders.
- Action Bars: fade amount slider to control how transparent mouseover-hidden bars become (applies to pet and stance bars as well).
- Square minimap: new “layout re-anchor” option (on by default) that repositions the minimap, zoom buttons, addon compartment, and difficulty indicator for the square shape.
- Action Bars: option to hide the Assisted Combat Rotation overlay/glow on buttons.
- Automatically open the preview window for player housing items.
- Added _Cypher of Relocation_ and two missing Warlords teleports.
- SharedMedia: 4 new borders and 4 new status bar textures.
- Cooldown Manager: per-viewer **“Show when”** multi-select (in combat, while mounted / not mounted, on mouseover) for Essential / Utility / Buff Bar / Buff Icon viewers, with Edit-Mode-friendly fading.
- Minimap Button Sink: configurable flyout direction (auto or specific edge/corner) with a screen-safe fallback.
- Unit Frames (Player / Target / ToT / Pet / Focus / Boss):
  - Custom frames with Edit Mode controls for size, strata/level, borders, health/power bars (colors, fonts, textures, text formats), cast bars, and status line options.
  - Target auras: anchor/offset controls and an optional separate debuff anchor.
  - Boss frames: container anchor, growth direction, and spacing controls.
  - New **Settings** group with a copy dropdown + confirmation popup to duplicate another frame’s settings while keeping your current position and enable state.
- Resource Bars: health bar absorb configuration (enable/disable, custom color, custom texture, sample preview).
- Tooltip: item icon toggle with configurable size for item tooltips (icon inline before the item name).
- Tooltip: optional guild name line (with configurable color) on unit tooltips.
- Tooltip: scale slider to resize tooltips.
- Tooltip: optional guild rank line (with configurable color) on unit tooltips.
- Tooltip: optional hide-faction / PvP lines on unit tooltips.
- Tooltip: spell tooltips can show the spell icon inline (new toggle; uses the tooltip icon size setting).
- Housing décor items are now shown in **Container Action** to quickly open them.

### 🔄 Changed

- **Show leader icon on raid-style party frames** now also shows leader and assist icons in raids.
- All features that will be part of Midnight have been moved into the Blizzard Options menu.

### ❌ Removed

- Old / unused libraries.

### 🐛 Fixed

- _Enhance Ignore List_ frame strata was set too high.
- Range coloring on action bars now clears correctly when your bar switches (mounts / stance / override).

---

## [6.1.0] – 2025-11-20

### ✨ Added

- Actionbar and Frame fading if you choose to hide it
- PlayerFrame
  - Show when I target something
  - New visibility rule: “Always hide in party/raid” (overrides other rules while grouped; mouseover can still reveal)
- Quest Tracker
  - Optional quest counter beneath the tracker header, showing `current/max` with configurable offsets
- Resource Bars
  - Optional auto-hide while mounted or inside vehicles, reacting instantly to mounting/vehicle events
- Sync the width of your resource bars with the relative frame
- Missing Mythic Keystone id for Keystone helper

### ⏰ Temporarily disabled

- Show Party frame in solo content, this break in group content with secrets in midnight beta

### ❌ Removed

- Hide raid frame buffs (something changed as this now throws error in retail too)

### 🐛 Fixed

- Error: attempt to perform indexed assignment on field 'moneyTracker'
- Guard against ChatIM and Ignore feature in restricted content (Raid/M+) for midnight because of secret values
- Resource Bars: Druid form-specific visibility now uses a secure state driver (no more tug-of-war with the hide rules), and disabling all visibility rules no longer forces redundant bar rebuilds
- Resource Bars: The module now fully unregisters its visibility drivers when turned off, and “Hide while mounted” also suppresses bars in Travel/Stag form for Druids
- BR Tracker working in m+/raid now
- World Map Dungeon Teleports fixed in m+/raid
- Resource Bars: Health bar now has absorb configuration (enable/disable, custom color, custom texture, sample preview)
- Loot Spec Quick Switcher: Prevents reselecting the already active spec on right-click (no more pointless progress bar)
- Tooltip: Inline spell icon no longer requires the "Show Spell Icon ID" toggle

---

## [6.0.0] – 2025-11-15

## Midnight Beta – Addon Status

Because of Blizzard’s new addon API restrictions in **Midnight**, some EQoL features have to behave differently in combat than before.  
Here’s what currently works, what’s limited, and what’s turned off in the Midnight beta.

### ✨ Added

- Dungeon teleports and talent reminder for midnight dungeon
- **Visibility Hub** (UI → Action Bar) lets you pick any Blizzard action bar or frame, then mix-and-match mouseover, combat, and the new “Player health below 100%” triggers with a single dropdown workflow. Action bars still expose their anchor/keybind extras when selected.
- Action bars gained a dedicated “While skyriding” visibility rule so you can force a bar (e.g., Action Bar 1) to appear when using Skyriding/Dragonriding abilities.
- Legion Remix achievements can now list their reward items directly in the missing-items tooltip, complete with item-quality coloring.
- Resource Bars can now anchor to the Essential/Utility cooldown viewers, both buff trackers, and all default Blizzard action bars (Main + MultiBars) for tighter layouts without custom macros.
- Health bars gained a “Use class color” toggle alongside the existing custom-color controls so you can instantly match your class tint without extra configuration.
- Resource Bars now have an optional “Hide out of combat” toggle that drives the frame visibility via a secure state driver, so the bars stay hidden without tripping combat lockdown.
- Adjust the columns per row in **Button Sink**

### 🔄 Changed

- **Aura Tracker**
  - In **combat**, almost all auras are now “hidden” from addons by Blizzard.  
    → Practically **no auras can be iterated in combat** anymore.  
    → Aura checks and updates happen **after combat**, when the restrictions are lifted.
  - **Out of combat**, new auras are scanned and displayed as usual.
  - **Resource bars**
    - Fully **Midnight-compatible**.
- Unit frame visibility now uses the same scenario model as action bars, enabling multiple states per frame while keeping legacy “always hide” support.
- Health-triggered frame fades only register the relevant unit events when a frame actually uses that rule, and updates are throttled to avoid `UNIT_HEALTH_FREQUENT` spam.

### ⏰ Temporarily disabled

These features are turned off **only for the Midnight beta** until there’s a safe way to re-implement them:

- **Tooltip enhancements**
  - Actually all stuff doing anything like adding data to the tooltip is disabled, as of a bug in midnight beta
- **Buff hiding on raid frames** in Midnight beta (disabled until a working solution is found)
- **Vendor module** tooltip information
- Changing the **max color** for power/resource bars
- The **“Smooth bars”** option is temporarily disabled. Blizzard is adding a built-in smoothing feature, which EQoL will use once it’s available.
- Account money frame feature (due to tooltip-handling bugs)

### ❌ Removed (Midnight beta)

These features are currently removed in the Midnight beta because of API changes or bugs:

- **Inventory**
  - Cloak Upgrade button (Midnight beta only)
- **Module:** `CombatMeter`
- **Mythic+ features**
  - Auto-marking tank and healer (now requires hardware events / secure input)
  - Potion tracker
- **Aura-based features**
  - Cast tracker
  - Cooldown notify

### 💡 Side note

- The **trinket cooldown tracking** inside **_Aura Tracker_** still works.

### 🐛 Fixed

- Nameplate **health percentage / absolute values** corrected for Midnight beta
- Tooltip error when hovering items with the **ignore list** enabled
- Player frame now correctly shown at **100% health** in Midnight beta
- Boss frames are now **targetable** again when changing visibility behaviour
- Error when hovering the **EQoL options menu** fixed
- Removed `UNIT_HEALTH_FREQUENT` (API is deprecated)
- Context menu checks for **NPC ID** hardened to avoid errors
- Health macro combat checks moved into **protected** logic
- **Healthbar colors** no longer sometimes display the wrong color
- Keybind shortening leads to invisible text
