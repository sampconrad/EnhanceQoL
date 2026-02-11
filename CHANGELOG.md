# Changelog

## [7.12.0] - 2026-02-11

### ✨ Added

- Unit Frames: Added configurable `Castbar strata` + `Castbar frame level offset` (Player/Target/Focus/Boss).
- Unit Frames: Added configurable `Level text strata` + `Level text frame level offset`.
- GCD Bar: Added `Match relative frame width` for anchored layouts, including live width sync with the selected relative frame.
- GCD Bar: Anchor target list now focuses on supported EQoL anchors (legacy ActionBar/StanceBar entries removed).
- Unit Frames: Added per-frame `Hide in vehicles` visibility option.
- Cooldown Panels: Added per-panel `Hide in vehicles` display option.
- Aura: Added per-module `Hide in pet battles` options for Unit Frames, Cooldown Panels, Resource Bars, and GCD Bar.
- Aura: Added `Hide in client scenes` (e.g. minigames) for Unit Frames, Cooldown Panels, and Resource Bars (default enabled).
- Resource Bars: Added per-bar `Click-through` option in Edit Mode
- World Map Teleport: Added Ever-Shifting Mirror
- Vendor: Added configurable auto-sell rules for `Poor` items (including `Ignore BoE`), hide crafting-expansion filtering for `Poor`, and disable global `Automatically sell all junk items` when `Poor` auto-sell is enabled.

### ⚡ Performance

- Unit Frames: `setBackdrop`/`applyBarBackdrop` now run with style-diff caching, so unchanged backdrop styles are skipped instead of being reapplied every refresh.
- Unit Frames: Edit Mode registration now batches refresh requests and skips no-op anchor `onApply` refreshes, reducing load-time spikes during UF frame/settings registration.
- Health/Power percent: Removed some pcalls
- Drinks: Improved sorting
- Unit Frames: Health updates now cache absorb/heal-absorb values and refresh them on absorb events instead of querying absorb APIs every health tick.
- Unit Frames: `formatPercentMode` was moved out of `formatText` hot-path to avoid per-update closure allocations.
- Resource Bars: `configureSpecialTexture` now caches special atlas state (`atlas` + normalize mode) and skips redundant texture/color reconfiguration.

### 🐛 Fixed

- Tooltip: Fixed a rare error when hovering unit tooltips.
- Objective Tracker: Hiding of M+ timer fixed
- Unit Frames: Main frame strata fallback is now stable `LOW` (instead of inheriting Blizzard `PlayerFrame` strata), preventing addon interaction from unexpectedly forcing Player/Target/ToT/Focus frames to `MEDIUM`.
- LibButtonGlow Update - Secret error
- World Map Teleport: Fixed restricted-content taint (`ScrollBar.lua` secret `scrollPercentage`) by suppressing the EQoL teleport display mode/interactions while restricted.

---

## [7.11.4] - 2026-02-09

### 🐛 Fixed

- Unit Frames: Power colors/textures now resolve by numeric power type first.
- Item Inventory (Inspect): Improved `INSPECT_READY` handling and reliability.
- Item Inventory (Inspect): Performance improvements for inspect updates.
- Tooltip: Fixed an error when showing additional unit info in restricted situations.
- Chat: `Chat window history: 2000 lines` now reapplies correctly after reload.
- Unit Frames: Some borders used the wrong draw type

---

## [7.11.3] - 2026-02-08

### 🐛 Fixed

- Missing locale

---

## [7.11.2] - 2026-02-08

### 🐛 Fixed

- Group Frames (Party/Raid): `Name class color` now persists correctly after `/reload`.
- Cooldown Panels: Edit Mode overlay strata now follows panel strata correctly.
- Cooldown Panels: `Copy settings` now refreshes Edit Mode settings and correctly updates layout mode/radial options.

---

## [7.11.1] - 2026-02-08

### 🐛 Fixed

- Cooldown Panels: Anchoring to other addons wasn't working

---

## [7.11.0] - 2026-02-08

### ✨ Added

- Data Panels: Panel-wide stream text scale option in Edit Mode.
- Data Panels: Panel-wide class text color option for stream payload text.
- Data Panels: Equipment Sets stream now has right-click options for text size and class/custom text color.

### 🔄 Changed

- Data Panels: Stream options windows now show the active stream name in the header instead of only "Options".
- Data Panels: Equipment Sets stream icon size now follows the configured text size.
- Mounts: Added tooltip hints for class/race-specific mount options (Mage/Priest/Dracthyr) when shown globally in settings.

### 🐛 Fixed

- Action Tracker: Removed some DK, Evoker and Priest fake spells
- Cooldown Panels: Improved reliability when changing spec and entering/leaving instances.
- Cooldown Panels: Fixed cases where hidden panels or cursor overlays could remain visible.
- Cooldown Panels: Improved static text behavior for multi-entry panels.
- Cooldown Panels: Simplified Static Text options in Edit Mode to reduce confusion.
- Unit Frames: Raid frame color change was wrong

---

## [7.10.0] - 2026-02-07

### ✨ Added

- Unit Frames: Aura icons can use custom border textures (boss frames included)
- Mount Keybinding: Random mount can shift into Ghost Wolf for shamans while moving (requires Ghost Wolf known).
- MythicPlus: Added a keybind for random Hearthstone usage (picks from available Hearthstone items/toys).
- Unit Frames: Option to round percent values for health/power text
- Unit Frames: Castbar border options (texture/color/size/offset)
- Unit Frames: Option to disable interrupt feedback on castbars
- Unit Frames: Castbar can use class color instead of custom cast color
- Unit Frames: Per-frame smooth fill option for health/power/absorb bars (default off)
- Group Frames (Party/Raid): **BETA** (performance test) for feedback on missing features or breakage. Aura filters require 12.0.1; on 12.0.0 you will see more auras (e.g., Externals filtering won’t work yet).
- Group Frames (Raid): Optional split blocks for Main Tank and Main Assist with separate anchors and full raid-style appearance settings.
- Cooldown Panels: Optional radial layout with radius/rotation controls (layout fields auto-hide on switch)
- Cooldown Panels: Cursor anchor mode with Edit Mode preview and live cursor follow
- Cooldown Panels: Hide on CD option for cooldown icons
- Cooldown Panels: Show on CD option for cooldown icons
- Cooldown Panels: Per-entry static text with Edit Mode font/anchor/offset controls
- System: Optional `/rl` slash command to reload the UI (skips if the command is already claimed)
- Unit Frames: Combat feedback text with configurable font/anchor/events
- Skinner: Character Frame flat skin (buttons, dropdowns, title pane hover/selection)
- Data Panels: Background and border textures/colors are now configurable via SharedMedia.
- Data Panels: Durability stream now has an option to hide the critical warning text (`Items < 50%`).
- Data Panels: Gold stream now supports a custom text color and optional silver/copper display in addition to gold.
- Data Panels: Durability stream now has customizable high/mid/low colors.

### 🔄 Changed

- Data Panels: **Hide Border** now hides only the border. Migration sets background alpha to 0 if Hide Border was previously enabled, so you may need to re-adjust background alpha.
- Unit Frames: Increased offset slider range in UF settings from ±400 to ±1000.

### ⚡ Performance

- Unit Frames: Cache aura container height/visibility updates to reduce UI calls
- Tooltips: Skip unit tooltip processing and health bar updates when all tooltip options are disabled
- MythicPlus: World Map teleport panel events now register only when the feature is enabled
- Food: Drink/health macro updates and Recuperate checks now run only when the macros are enabled
- Unit Frames: Truncate-name hooks now register only when the feature is enabled
- Action Bars: Visibility watcher now disables when no bar visibility rules are active

### ❌ Removed

- Aura Tracker (BuffTracker module + settings/UI)
- Legacy AceGUI options window (tree-based settings UI)
- Mover: Individual bag frame entries (Bag 1–6)

### 🐛 Fixed

- Tooltips: Guard secret values when resolving unit names (prevents secret boolean test errors)
- Group Frames: Guard missing Edit Mode registration IDs on disable
- Unit Frames: Boss cast bar interrupt texture now resets on new casts
- Unit Frames: Aura cooldown text size no longer defaults to ultra-small "Auto"; default now uses a readable size
- Resource Bars: Smooth fill now uses status bar interpolation (fixes legacy smooth update behavior)
- ChatIM: Disabling instant messenger restores whispers in normal chat
- Vendor: Disable destroy-queue Add button when the feature is off
- MythicPlus: ConsolePort left-click on World Map teleports now triggers the cast correctly
- Visibility: Skyriding stance check no longer triggers for non-druids (e.g., paladin auras)
- World Map Teleport: Mixed Alliance and Horde for Tol Barad Portal
- World Map Teleport: Tab selector was hidden
- Cooldown Panels: Specs were not correctly checked
- Itemlevel in Bags and Characterpanel are now correct
- Missing locales

---

## [7.9.1] - 2026-02-02

### 🐛 Fixed

- Wrong default font for zhTW

---

## [7.9.0] - 2026-02-02

### ✨ Added

- Keybinding: Toggle friendly NPC nameplates (nameplateShowFriendlyNpcs)
- UF Plus: Unit status group number format options (e.g., Group 1, (1), | 1 |, G1)
- UF Plus: Target range fade via spell range events (configurable opacity)

### 🔁 Changed

- Resource Bars: Bar width min value changed to 10

### 🐛 Fixed

- Secret error: LFG List sorting by mythic+ score is now ignored in restricted content
- Questing: Guard UnitGUID secret values when checking ignored quest NPCs (prevents secret conversion errors)
- Health Text: Text was shown when unit is dead
- Nameplates: Class colors on nameplates now work in 12.0.1 (updated CVar)
- Cooldown Panels: Guarding against a protection state produced by anchoring protected frames to CDPanels

---

## [7.8.1] - 2026-01-31

### 🐛 Fixed

- Missing locale fixed

---

## [7.8.0] - 2026-01-31

### ✨ Added

- Resource Bars: Evoker Essence bars now show filling animation
- Resource Bars: Gradiant color works horizontal now too
- Cooldown Panels: Option to enable charge duration show
- UF Plus: Cast duration format option for Remaining/Total.
- Cooldown Panels: Added anchor points for ElvUI, Unhalted Unit Frames, and more MSUF frames (ToT/Focus/Pet/Boss).
- Cooldown Panels: Edit Mode panel filters (only show panels of your class) and Copy Settings dropdown to clone layout/anchor settings (keeps entries + enabled state untouched).
- UF Plus: Focus frame aura icons are now supported and configurable.
- UF Plus: Health and power bars can now reverse their fill direction (right-to-left).
- Cooldown Panels: New `/cpe` slash command alias (opens the Cooldown Panel editor).
- Tooltips: Optional target-of-target line on unit tooltips.
- Tooltips: Optional mount display on player tooltips.
- Character Frame: Optional missing-enchant overlay toggle (defaults on).
- Mover: Covenant frames are now movable (Sanctum, Mission, Renown, Preview).

### 🔁 Changed

- Cooldown Panels: Switched button glow to LibButtonGlow

### ❌ Removed

- Visibility: Removed "Player health below 100%" rule for Action Bars/Cooldown Viewer because secret alpha values can leak into other addons and trigger comparison errors/taint (e.g. ActionBarLabels).

### 🐛 Fixed

- Mover: MailFrame/SendMail and Open Mail are now movable.
- Cooldown Panels: Spell usable checks are now evaluated correctly.
- Cooldown Panels: Overlay glow now resolves override spell IDs (talent replacements) correctly.
- UF Plus: Cast bar icons now fade with the interrupt animation for target/focus enemies.
- World Map: Teleport panel tab no longer overlaps other map tabs when WorldQuestTab is enabled.
- Combat Logging: Switched to advance api because of an issue

---

## [7.7.2] - 2026-01-27

### 🐛 Fixed

- Cooldown Panels: Range checks now get enabled for newly added spells so range overlay updates reliably.
- Cooldown Panels: "Show stack count" now uses ActionBar display counts (updates on SPELL_UPDATE_USES), supporting secret stacks.

---

## [7.7.1] - 2026-01-27

### 🐛 Fixed

- Resource Bars: Class color was not working on some classes

---

## [7.7.0] - 2026-01-25

### ✨ Added

- Mount Keybinding: Option to disable shifting into Travel/Cat Form while mounted for druids using random mount.
- Cooldown Viewer: Separate fade amount slider for “Show when” visibility rules.
- Cooldown Panels: Edit Mode sliders for in-combat and out-of-combat opacity.
- Cooldown Panels: Panel-level keybind display settings in Edit Mode (enable, anchor, offsets, font).
- Cooldown Panels: Growth point option to center icon rows/columns.
- Cooldown Panels: Spell activation overlay glows now shown on matching entries.
- Cooldown Panels: Optional range overlay with customizable color (spell range checks).
- Cooldown Panels: Optional power check tint when a spell is unusable due to insufficient resources.
- Cooldown Panels: Panel spec filter (show only for specific specs).
- Cooldown Panels: Power tint color can be customized.
- Cooldown Panels: Added /ecd slash command to open the editor (if the command is free).
- GCD Bar: Styling options (background, border, progress mode, fill direction, border offset; reverse fill fix).
- UF Plus: Absorb and heal absorb overlay height option capping at max health height
- UF Plus: Highlight dispellable debuffs option for aura icons.
- UF Plus: Aura cooldown text can be toggled separately for buffs and debuffs.
- UF Plus: Aura cooldown text size can be set separately for buffs and debuffs.
- UF Plus: Aura stack size can be set separately for buffs and debuffs.
- Resource Bars: Gradient tint controls (start/end) for bar fills.
- Resource Bars: Rune cooldown text font/size controls and customizable cooldown color.
- Resource Bars: Percent rounding option for percent text (round to nearest/down).
- Resource Bars: Optional extended Stagger colors with high/extreme thresholds.
- Action Tracker: Optional “time since last action” text under icons.
- Action Tracker: Masque skinning support for tracker icons.
- Trade Log: Trade history line now shows colorized item names per side (You/Other).
- Trade Log: Removed “Trade” from trade history preview.
- Settings: Optional slash commands for Edit Mode (/em, /edit, /editmode) and Quick Keybind Mode (/kb).
- Settings: Optional /pull slash command for the Blizzard pull countdown (skips if claimed).
- Settings: Moved slash command toggles to General → UI Utilities.
- Questing: Optional modifier requirement for quest automation (accept/complete).
- Mouse Ring: Combat-only color/size override and optional extra combat ring overlay.
- Sound: Personal crafting orders now have extra sound options for New/Removed orders (fires only on changes).
- Shared Media: 2 new voices for crafting orders (Crafting Order - New, Crafting Order - Canceled).
- Visibility: Added player casting/mounted/in-group rules plus skyriding show/hide and player health < 100% support for action bars/cooldown viewer.
- Mover: Ready Check frame is now movable.

### 🔁 Changed

- Resource Bars: Druid Treant form no longer listed in form filters (mapped to Humanoid)
- Minimap: Only re-show hidden elements if EnhanceQoL hid them (avoids overriding other addons)

### 🐛 Fixed

- Cooldown Panel glow wasn't working correctly in restricted environment
- Cooldown Panels: Growth point alignment now uses left/center/right start points to keep the edit mode overlay aligned
- Cooldown Panels: Track override spell IDs so talent-based replacements update correctly
- Cooldown Panels: Item uses/charge count now tracked correctly (includeUses)
- Hide Raid Tools: Only hook CompactRaidFrameManager when setting is enabled and avoid protected Hide in combat (alpha fallback)
- Data Panels: Reflow inline texture widths on UI scale changes to prevent squished text
- Resource Bars: Druid forms missed Tree of Life
- Enchant checks: Keep legacy required slots until Midnight rules apply (level 81+)
- Health Macro: Added Custom Spells dropdown hint to clarify selection removes entries and field stays blank
- Unit Frames: Rightclicking a Unit Frame in restricted environment with NPC ID option enabled

---

## [7.6.0] - 2026-01-24

### ✨ Added

- Quest Tracker: Minimized '+' anchor now supports bottom corners properly.
- Cooldown Panels: Item entries can show charges using item uses.
- DataPanels: Bag Space stream with icon toggle and Free/Max or Free display.
- DataPanels: Hearthstone stream showing bind location with optional icon.
- UF Plus: Detached power bar can use a custom strata.
- UF Plus: Optional handling for empty power bars (max 0) when power is detached.
- UF Plus: Added Heal Absorb Bar options (texture, color, sample, reverse fill) for anti-heal displays.
- UF Plus: Absorb Bar to boss frames
- Cooldown Viewer: Optional /cdm and /wa slash commands to open settings.
- DataPanels: Combat time stream with optional boss timer (stacked or inline).
- World Map: Coordinate updates can run faster (down to 0.01s) and cursor coords hide off-map.
- Mount Keybinding: Druid random mount now chooses Travel Form outdoors and Cat Form indoors when moving.

### 🐛 Fixed

- Action Tracker: Ignore list updated for Spark of Madness and alchemy/cooking DNT casts.
- Mythic+: Party keystone list now includes your own key during prepatch (uses player expansion max level).
- Mythic+: Dungeon portal UI now ignores restriction type 4 (matching world map behavior).
- Mythic+: World map teleport panel now opens correctly from the collapsed map state.
- Cooldown Viewer: Druid Travel Form detection now supports dynamic form order (including Flight Form variants).
- Resource Bars: Max height increased to support vertical layouts.
- UF Plus: Debuff border colors now use the modern dispel color API (DebuffTypeColor removed).
- World Marker Cycle: Sometimes not working for some users
- Mount Keybinding: Only Druids should cancel their respective form now
- Tooltips: Secret error on inspect in restricted environment
- Money Stream: Missed to add the remove dropdown for characters
- Resource Bars: Void Metamorphosis now respects Soul Glutton (max 35) and Collapsing Star (max 30)

---

## [7.5.0] - 2026-01-23

### ✨ Added

- Cooldown Panels: Slot entries can be shown even without cooldowns (equipped items).

### 🐛 Fixed

- Mover: Inspect Frame wasn't movable
- UF Plus: Dimensius P3 Boss frame wasn't reappearing
- Cooldown Panels: Some spells where not shown
- Cooldown Panels: Masque icons now size correctly when adding new entries (no reload needed).
- XP/Rep Bar: Resizing no longer flips the bar or distorts textures (rested overlay/tick aligned).
- Mount keybinds now auto-cancel Druid shapeshift forms before summoning auction/repair/random mounts.
- Action Bars: Full out-of-range overlay no longer disappears on button mouseover.
- Resource Bars: Maelstrom Weapon separator was missing
- Resource Bars: Maelstrom Weapon bar was fixed to 5 and overcap now either 5 stack bar with overcap or 10 stack bar

---

## [7.4.0] - 2026-01-22

### ✨ Added

- DataPanels: Stream gap slider per panel.
- DataPanels: Time stream left-click opens the Time Manager (stopwatch/alarm).
- Combat text: +Combat/-Combat indicator with Edit Mode settings (duration, font, size, color).
- UF Plus: Aura cooldown text size slider.
- UF Plus: Masque for Buff/Debuff
- Resource Bars: Added "Use short numbers" toggle for text to control AbbreviateNumbers usage.
- Cooldown Panels: New Cooldown Manager editor to build panels and add spells/items/slots with per-entry options (cooldown text, charges, stacks, glow, sound, item count).
- Cooldown Panels: Anchor to Player/Target (auto-uses UF if enabled) and some external unit frames.
- Cooldown Panels: Editor keybind and saved editor window position.

### 🐛 Fixed

- Action Tracker: Ignore list updated for recent profession/cooking casts and arachnophobia.
- Buff Tracker: Avoid secret-value table indexing when resolving pending aura spell IDs.
- UF Plus: Castbar icon no longer renders behind the castbar.

---

## [7.3.1] - 2026-01-21

### 🐛 Fixed

- Tooltip: Guard against secret values when scanning unit tooltip lines (prevents combat mouseover errors).
- Action Tracker: No longer misses the first cast when enabled after login.
- Resource Bars: Max color changes now rebuild the Midnight curve immediately.

---

## [7.3.0] - 2026-01-21

### ⏰ Temporarily disabled

- Money tracker in bags still has a tooltip error (secret related) in latest retail version
- Close all Bags option in restricted Environment (m+ key running) when opening auction house - leads to lua error when opening mailbox afterwards...

### ✨ Added

- Option to hide the "Screen captured" text

### 🐛 Fixed

- Class Resources: Hide toggles now respect UF player frame activation when switching.

---

## [7.2.0] - 2026-01-21

### ✨ Added

- Quest Tracker: Option to remember collapsed/expanded state across login/reload.
- UF Plus: Option to use Edit Mode tooltip position for unit frames.
- Resource Bars: Threshold lines can use absolute values.

### 🐛 Fixed

- UF Plus: Combined aura layout no longer errors on secret auras.

---

## [7.1.3] - 2026-01-20

### 🐛 Fixed

- DataPanels: Background and border now respect in/out-of-combat opacity.
- Resource Bars: Demon Hunter spec 3 now uses Void Metamorphosis as the main resource.
- Resource Bars: Void Metamorphosis default color now matches Blizzard UI.

---

## [7.1.2] - 2026-01-20

### 🐛 Fixed

- Single UF profile import wasn't changing x/y position of UF frames

---

## [7.1.1] - 2026-01-20

### 🐛 Fixed

- Bug when entering Edit Mode while in combat
- Fixed Action Tracker showing passive effects of spells
- Profiles import doesn't apply UF locations

---

## [7.1.0] - 2026-01-20

### ✨ Added

- DataPanels: Pet Tracker stream with customizable text color/size and optional blinking when a pet spec has no active pet. Checks for Frost Mage, Hunter, Warlock, Unholy DK and respects needed talents.
- DataPanels: Edit Mode click-through toggle to make panels ignore mouse input.
- DataPanels: Edit Mode font selection per panel + tooltip toggle.
- DataPanels: Content alignment option (left/center/right) in Edit Mode.
- DataPanels: Mail notification stream with minimap mail icon and tooltip senders.
- Sound: Additional sounds mapping per event with a per-event dropdown (extra sounds toggle).
- Combat & Dungeons: Auto combat logging in instances with per-instance + difficulty rules.
- Inventory: Bag sort and loot order controls (left-to-right or right-to-left).
- Inventory: Enhanced rarity glow for bags and the character frame.
- Mounts: New keybind actions for Random, Repair, and Auction House mounts with an option to use all mounts for Random.
- Action Bars: Custom action button border selection (including SharedMedia) with edge size + padding controls.
- Action Bars: Charge/stack count font override (font, size, outline).
- UF Plus: Custom class colors for unit frames.
- UF Plus: Secondary/tertiary delimiter options for health/power texts.
- UF Plus: Status line option to show elite/rare/rareelite icons on non-player frames.
- UF Plus: Option to hide elite/rare text indicators when the classification icon is enabled.
- UF Plus: Shaman Maelstrom Weapon class resource bar with animated swirl/proc visuals (respects UF Player + Class Resource settings).
- Inventory: Midnight Season 1 catalyst charge display on the character frame.
- Gear & Upgrades: Gem Helper tracker under the character frame (shows equipped gem types and missing highlights).
- Gear & Upgrades: Character stat formatting option to show rating + percent for secondary stats.
- Food: Added Midnight drinks and mana potions.

### ⚠️ Warning

- **Action Bars: "Button growth" (Modify Action Bar anchor) can cause protected action errors when switching specs or opening Edit Mode.**

### 🔄 Changed

- Minimap Button Bin: Buttons are now sorted alphabetically by default.
- DataPanels: Talents stream defaults to a grey "Talents:" prefix.
- Resource Bars: Bar/Absorb texture dropdowns now show previews.
- Vendors: Auto-repair now prints a message when repairs are paid from the guild bank.
- Mounts: Random mount keybind now picks a usable random mount based on swimming/flyable/ground conditions.
- UF Plus: Role/PvP indicator options are now under Unit status.

### 🐛 Fixed

- Resource Bars: Font dropdown selection no longer resets on click (fonts are selectable again).
- Resource Bars: Class color and max-color overrides now apply correctly to resource bars.
- Resource Bars: max-color caused lua errors in secret environments
- DataPanels: Volume stream right-click no longer requires the context menu modifier.
- Talents: Filter out the internal TalentLoadoutManager placeholder loadout in selection lists.
- UF Plus: Aura icon tooltips now show for private/secret auras via auraInstanceID fallback.
- UF Plus: Boss frame name/level color options are available like other frames.
- UF Plus: Channelled casts no longer show failed when re-pressing the spell mid-channel.

### ❌ Removed

- Removed the CombatMeter module and clean up its saved variables on load.
- Removed Legion Remix event modules and vendor remnants.
- Removed Aura: Cast Tracker and Cooldown Notify modules.
- Removed the Combat & Dungeons/Combat Assist options tree nodes (Aura Tracker is now the root).

---

## [7.0.2] - 2026-01-11

### 🐛 Fixed

- Combat meter was shown even if disabled

---

## [7.0.1] - 2026-01-11

### 🐛 Fixed

- DataPanels: Edit Mode selection overlay no longer falls behind panels with higher frame strata.
- Resource Bars: Absorb overfill now caps at max health and no longer errors with secret values.

---

## [7.0.0] - 2026-01-10

### ✨ Added

- **UF Plus**
  - Per-frame aura toggle for Player/Target/Boss frames
  - Player unit status can show group number.
  - Additional health/mana text modes (percent-first + level combos).
  - Health/Power texts now support a center slot with independent offsets.
  - Unit status text now has its own font size/font/outline controls + Edit Mode sample.
  - PvP indicator icon for Player/Target/Focus.
  - Role indicator icon for Player/Target/Focus.
  - Optional reverse-fill absorb bar in UF.
  - Cast bars now show interrupted/failed feedback on Target/Focus/Boss.
  - Cast bars can show Remaining or Elapsed/Total duration text.
  - Resource bars can show configurable threshold lines (count/color/thickness).
  - Single opacity slider for UF Plus “Show when” visibility.
  - Brewmaster: Stagger secondary resource bar with native Stagger colors.
  - Detached power bar can use its own border (texture/size/offset).
  - Cast bar icon offset slider for Target/Focus/Boss frames.
  - Optional border highlight for mouseover/aggro.
  - Edit Mode shows sample auras for frames with auras enabled.
  - Tapped mob color indicator for unit frames.
  - Player castbar can optionally show the cast target.
  - Castbar change max name width cap
- **Misc**
  - Auto-accept summons.
  - Auto-accept resurrection requests.
  - Auto-release in PvP/BGs.
  - Latency stream: configurable ping colors + display mode (FPS/Latency).
  - Master volume stream: DataPanel popup slider for Sound_MasterVolume.
  - DataPanels: new Location, Time, and Realm streams (subzone + zone color + time format + time color options).
  - DataPanels: Item Level stream with per-slot tooltip breakdown.
  - DataPanels: Mythic+ Rating stream (current season score + run list tooltip).
  - DataPanels: Equipment Sets stream with left-click swap menu.
  - DataPanels: Micro Bar stream with a quick-access menu.
  - DataPanels: text outline/shadow toggles + in/out-of-combat opacity sliders.
  - DataPanels: Latency + Realm streams now support a text color picker.
  - Quick-skip cinematics option (auto-confirms the skip prompt on Esc/Space/Enter).
  - Added missing Dalaran teleport ring variants.
- **Chat**
  - Use arrow keys in the chat input without holding Alt.
  - Move the chat editbox to the top of the chat window.
  - Unclamp chat windows from the screen edges.
  - Hide the combat log tab while docked.
- **Questing**
  - Objective Tracker can minimize to the (+) button only.
- **Minimap**
  - Hide addon minimap buttons until you mouse over the minimap.
  - Unclamp the minimap cluster so it can sit closer to the screen edge.
- **Interface**
  - Train All button in the trainer window to learn all available skills at once.
  - Login UI scale preset (applies on login; changing it reloads the UI).
- **Action Tracker**
  - Edit Mode-driven tracker for recent player spells with size/spacing/direction/fade and max icon count.
- **Cooldown Viewer**
  - Added a “When I have a target” visibility rule in the Cooldown Manager “Show when” options.
- **GCD Bar (Midnight)**
  - Edit Mode bar for the global cooldown with size, texture, and color controls.
- **Mailbox**
  - Option to remember the last recipient in the Send Mail field until the mailbox closes.
- **Character Frame**
  - Item level display can show equipped/average when enabled.

### 🔄 Changed

- **Settings UI**
  - Root categories now use a consistent expandable section layout.
  - UI root renamed to Display.
  - Social now contains Chat settings under the Social root.
  - System root removed; Sound + Shared Media moved to a dedicated Sound root.
  - CVar toggles moved into General (Movement & Input + System), Display (Frames), Minimap & Map, Mouse, Action Bars, and Chat.
  - Economy root reorganized into Repair Options, Vendor Options, Merchant UI, Auction House, Mailbox, and Gold & Tracking.
  - Vendor module settings moved under Economy as Vendor Options, with Destroy as a subsection.
  - Quest settings moved to Gameplay with a single Questing accordion.
  - Frame visibility rules now have a global fade amount slider.
  - Blizzard frame options now hide when EQoL frames are enabled (Health Text, Castbars, Visibility rules).
  - Game Menu scaling option removed (Mover handles it instead).
- **UF Plus / Resource Bars**
  - Brewmaster no longer shows the unused Mana bar.
  - Removed the "Gap between bars" unit frame setting (detached power bar replaces this use case).
  - Export scope now lists only specs with saved settings; “All specs” exports only configured specs.
  - Profile export/import now supports an “All classes” scope (exports all class specs + global Resource Bar settings; auto-detects All-Classes payloads on import and reloads).
- **Gear & Upgrades**
  - Character/Inspect display options now use a multi-select dropdown with per-option tooltips.
- **Items & Inventory**
  - Bag display options and item level targets now use multi-select dropdowns with tooltips.
  - Dialog auto-confirm options are grouped into a single multi-select dropdown.
- **Vendors & Services**
  - Section renamed to “Repair Options”.
  - Craft Shopper moved under Auction House.
  - Auto-sell junk moved under Vendor Options.
- **Minimap**
  - Square minimap layout now anchors the mail icon to the top-left of the minimap.
  - Button Sink labels and tooltips refreshed for clarity.
  - Button Sink settings moved under Minimap & Map.
- **Mythic+ Teleports**
  - Teleports now collapse to owned items when multiple variants exist (ex. Kirin Tor Rings); tooltip shows `X other variants available`.
- **Tooltip**
  - Optional modifier override to show hidden tooltips while in combat/dungeons.

### 🐛 Fixed

- Resource bars hidden kept a wrong health/powervalue on show
- Unit Frame Strata set at least "High" blocks options window
- Unit Frames had a shadow color on the texts which made it darker
- TomTom Minimap Icons are ignored in Button Sink
- Mover: Dragging no longer overlays the PlayerSpells/Talents UI, so buttons remain clickable.
- Mover: Disabled entries no longer get touched, and mousewheel scaling no longer blocks MerchantFrame scrolling.
- Blizzard Boss Frame visibility rule now hides when EQoL Boss Frames are enabled.
- UF Plus Edit Mode samples now show percent text for Boss frame power/health.
- Resource Bars: Warlock Soul Shards now show partial values (e.g. 3.4).
- Resource Bars: Spec toggles now initialize unused specs and profile scope no longer errors on missing data (invalid class IDs or scope table).
- UF Plus: Level text now refreshes on level-up.
- DataPanels: Micro Bar missions entry no longer errors when Covenant data is unavailable.
- Show Leader/Assist Icon on Raidframes expanded the size in edit mode for the selection overlay
- Bonus Roll frame no longer disappears when loot anchoring is disabled.
- Edit Mode: imported layouts now reuse the last EQoL layout positions instead of resetting.

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
