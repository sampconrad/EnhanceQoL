# Changelog

## [7.0.0] - 2026-01-10

### ✨ Added

- **UF Plus**
  - Per-frame aura toggle for Player/Target/Boss frames
  - Boss frames can optionally show auras.
  - Player frame can optionally show auras (default off).
  - Player unit status can show group number.
  - Edit Mode shows sample auras for frames with auras enabled.
- **Misc**
  - Auto-accept summons.
  - Auto-accept resurrection requests.
  - Auto-release in PvP/BGs.
  - Quick-skip cinematics option (auto-confirms the skip prompt on Esc/Space/Enter).

### 🔄 Changed

- **Settings UI**
  - Root categories now use a consistent expandable section layout.
  - Social now contains Chat settings under the Social root.
  - System root adds dedicated accordions for CVar, Sound, and Shared Media.
  - Economy root reorganized into Vendors & Services, Merchant UI, Auction House, Mailbox, and Gold & Tracking.
  - Vendor module settings moved under Economy with separate Selling & Shopping and Destroy sections.
  - Quest settings moved to Gameplay with a single Questing accordion.

### 🐛 Fixed

- Unit Frame Strata set at least "High" blocks options window

---

## [6.6.2] – 2025-12-31

### 🐛 Fixed

- Empty currecy streams in datapanels set all others streams hidden

---

## [6.6.1] – 2025-12-31

### 🐛 Fixed

- Frame level of absorb on UF Plus was behind the bar

---

## [6.6.0] – 2025-12-30

### ✨ Added

- **UF Plus**

  - New text modes (Max, Max/Percent) + optional percent symbol hiding.
  - New unit frame text modes (Cur/Max + percent combos) + separator dropdown.
  - Target aura anchor now supports LEFT/RIGHT + growth direction combinations.
  - Separate debuff growth direction option for target auras.
  - Power bar can be detached with custom width + offsets.
  - Per-frame “Show when” visibility rules for custom unit frames in Edit Mode.
  - Per-main-power color overrides for power bars (optional desaturation).
  - Portrait options for unit frames (side + separator).
  - Portrait separator settings (toggle/size/texture/color).
  - Portrait option to force a square background.
  - Border offset control for unit frame textures.
  - Status line name max width.
  - Option to hide level display at max level.
  - Unit status (AFK/DND/offline) indicator with adjustable offsets.
  - Click Casting Addon support (e.g. Clique).

- **Mover**

  - Position persistence mode (close / logout / reset).
  - Reset scale + position to defaults with scale modifier + right-click on a handle.

- **Data Panels**

  - Difficulty stream now opens a difficulty selection menu on click.
  - New Mythic+ Key stream with owned-key display.
  - New Loot Spec stream with quick menu for loot spec + active spec.
  - New Coordinates stream for persistent player coordinates.

- **Action Bars**

  - Option to show all action bars when hovering any mouseover bar.

- **Chat / Social / History**

  - Social: Community chat privacy toggle (Always / Session) + quick eye reveal + overlay hint.
  - Chat History: optional restore of recent messages on login.
  - Chat: toggle to bump the default chat window history to 2000 lines.
  - Chat: optional item level (and equip slot) appended to item links.

- **Bags**

  - New filter toggle to show upgrades only.

- **Misc**
  - Black border for square minimap in housing.
  - Upgrade arrow outline for better visibility on bright icons.
  - Added 4 missing teleport items for Brawl'gar Arena.

### 🔄 Changed

- **UF Plus / Resource Bars**

  - Resting indicator settings merged into the Unit status section.
  - Sample cast previews now auto-show in Edit Mode.
  - Name/Level font sizes are now configurable independently in the status line.
  - UF/Resource Bars: texture/font/outline dropdowns now stay open on click (faster SharedMedia browsing).
  - Castbar backdrop now uses the Blizzard default background when the default texture is selected.

- **Mover**

  - Merged Quest and Gossip Frame.

- **Data Panels**

  - Talent stream now offers a loadout switch menu.
  - Durability stream tooltip expanded with per-item details and repair info.

- **Chat**

  - Item/currency icon option now applies to all item links.
  - “DELETE” for the delete-item dialog now also removes focus of the editbox (for addons like DialogKey).

- **Misc**
  - Upgrade arrow color in inventory changed to green.
  - Upgrade arrow size increased.
  - Moved the “Hide Minimap Button” setting to Map Navigation.
  - `/eqol` now opens the new settings menu; `/eqol combat` and `/eqol legacy` open the legacy options window.

### 🐛 Fixed

- **UF Plus / Resource Bars**

  - Resource Bars: anchor changes made via dropdowns/sliders now sync to Edit Mode layouts (positions persist after reload).
  - Focus frame health now updates on unit health events.
  - Defaults are now properly used as fallback.
  - Castbar backdrop was shown on reload when nothing was being cast.
  - Some target auras were missing.
  - Aura debuff color fixed in Midnight.
  - Non-interruptible color wasn’t working in Midnight.
  - Channeling animation for castbar was in the wrong direction.
  - Font/outline bug fixed.
  - Click Casting modifiers for Target/Menu weren’t working.
  - Class resources (e.g., combo points) now stay above unit frame borders after form swaps.

- **Mover**

  - Fixed overlapping issues with some UI elements.

- **Action Bars**

  - Fade amount slider now applies instantly without animation (reduces lag).
  - Mouseover performance: coalesced refreshes and reduced fade restarts.

- **Tooltips / Misc**
  - Macro-ID on tooltip was wrong.
  - Aura tooltip was hidden in restricted combat (secret) on party/raid when _Hide friendly tooltip_ was active
  - Auto container opening now skips while dead to avoid "You can't do that when you're dead" spam.
  - Mouse ring/trail now share a single runner and lazily allocate trail elements to reduce hot-path work.
  - Upgrade Arrow in inventory didn't check for "recommended for specialization"

---

## [6.5.0] – 2025-12-22

### ✨ Added

- Enhancement Shaman: Maelstrom Weapon resource bar.
- Devourer resource bar tracking added (disabled until the next WoW beta release; will be enabled then).
- Combat tooltips now show spell/item/aura IDs with improved secret handling for Midnight.
- UF Plus: toggle and adjust raid icon size/offset.
- UF Plus: show Blizzard class resources and manage them.
- UF Plus: optional cast bar for boss frames.
- Mover: new module that lets you move and scale frames and keeps their positions saved

### ❌ Removed

- UF Plus: removed "Show sample cast" and "Show sample absorb" toggles (auto in Edit Mode).
- Removed the option to show party frames in solo content
- Removed the cloak upgrade button feature

### 🐛 Fixed

- Rune cooldown text now renders above the border to avoid clipping at small bar heights
- Rune ready colors now refresh reliably after spec or color setting changes
- Dungeon Journal loot spec icon scale no longer crashes when the saved value is 0
- Unit Frame status line settings now correctly gate name/level options and combat indicator sub-options

---

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
