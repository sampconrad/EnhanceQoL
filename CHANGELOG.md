# Changelog

## [5.0.0] – 2025-09-28

### 🧭 Major change — Teleport Compendium (redesign)

- **Legacy window removed:** The old standalone Teleport Compendium UI has been **fully retired**.
- **Now built into the World Map:** Open the World Map (`M`) and click the **Teleport** icon in the right dock to open the new panel.
- **Native look & feel:** Uses Blizzard’s layout, scrolling and categories (Favorites, Home, expansions) for a seamless experience.
- **Cleaner & faster:** Fewer custom frames, lower taint risk, and better compatibility with other UI mods/skins.

### 🧭 Major change — Options overhaul (read me)

- New navigation with clear top‑level groups. The whole options UI is reorganized for faster discovery and less scrolling:
  - Combat & Dungeons — hosts all combat modules: Aura Tracker, Cast Tracker, Resource Bars, Cooldown Notify, Drink Macro, Combat Meter, and Mythic+.
  - Items & Inventory — split into Loot, Gear & Upgrades, and Vendors & Economy (auto‑sell, Craft Shopper, mailbox address book, etc.).
  - Map & Navigation — quest helpers and the Teleport Compendium panel hook‑ins.
  - UI & Input — action bars, chat, unit frames, data panel, social, and system toggles.
  - Media & Sound — central place for SharedMedia and sound muting (if those modules are enabled).
  - Profiles — Ace3 profile management.
- Consolidated/renamed pages. Many options moved to more obvious homes and labels got simplified. Obsolete or duplicate toggles were removed.
- Mythic+ options are no longer a separate root; they live under Combat & Dungeons and add their Teleports tab under Map & Navigation.

Heads‑up (migration notes)
- Saved profiles are preserved. Because names/locations changed, a few options may show as “new” or appear reset — re‑enable them once in the new location.
- Minimap button and AddOn Compartment open the new options window; Teleport Compendium is now on the World Map dock (click the Teleport icon).
- If a setting seems missing, look under the new parent group listed above; nothing critical was removed beyond duplicates/legacy.

### ✨ Added

- **Teleport Compendium (data):** Added **30** missing teleport spells/items.
- **Mythic+ Tooltips:** Choose which score details to show on unit tooltips (overall score, best dungeon, season overview).
- **Upgrade Indicators:** Optional arrow overlay on bag items that are upgrades vs. your equipped gear.  
  ▸ On flyouts the comparison evaluates the **actual items** in your bags (e.g., both trinket slots), not only the equipped slot.
- **Merchant Frame:** Option to expand the merchant page to **20 items** per page.
- **Mailbox Address Book:** Address book on the Send Mail UI populated with your alts.
- **Castbars:** Option to hide **Player**, **Target**, and **Focus** castbars.
- **Minimap Options:**  
  ▸ Hide selected minimap icons.  
  ▸ Optional border in **square** minimap mode.
- **Game Menu:** Scaling option for the Game Menu.
- **Health Macro:**  
  ▸ Option to use **combat potions/custom spells** in combat.  
  ▸ Customizable priority: **custom spells**, **potions**, **healthstones**, **combat potions**.
- **Player, Target and Boss Frame Health Text:** Always show **percent**, **value**, or **both** on frames **independent** of the global CVar.

### 🐛 Fixed

- **Health Macro:** _Invigorating Healing Potion_ used the wrong healing amount — corrected.
- **Localization:** Fixed several dialogs with missing localized strings.
- **Bag filter:** Sometimes the bag filter was empty
- **Instance difficulty:** Disabling this setting while not in Dungeon showed the default icon
- **Aura Tracker:** After deleting all auras, switching menus could auto‑select “+ Add Category” and spawn a new frame. New categories now start disabled so nothing pops up unexpectedly.
- **Option UI:** Resizing sometimes overlapped outside of the option menu
- **Strata Issue:** CastTracker, AuraTracker, CooldownNotify had some trouble with frame strata of popups

---

## [4.16.0] – 2025-09-13

### ✨ Added

- **Drink Macro:** Option to use Mana-Potions in combat
  - _±80 mana potions_ known
  - 10 missing mana drinks of 11.2.5 were added

---

## [4.15.1] – 2025-09-13

### 🐛 Fixed

- **HealthMacro:** Sometimes on /abandon when you are infight, there was a chance for a lua error

---

## [4.15.0] – 2025-09-11

### ✨ Added

- **Chat Frame:** Option to hide the messages of "learned" and "unlearned" spells on respec
- **Instance Difficulty:** Change the location, color and size of the dungeon difficulty text

### 🐛 Fixed

- **Spell Flyout on Mouseover:** Action bar on mouseover hide had a problem with _Spell Flyout Menus_

---

## [4.14.0] – 2025-09-10

### ✨ Added

- **Auction House:** Option to automatically select "Current Expension only" by default on opening
- **HealthMacro:** Option to allow "Recuperate" out of combat. This sets the healthstone/potion to combat only

### 🐛 Fixed

- **Active Talentbuild:** Wrong default value initilized
- **Aura Tracker:** Missing sound messages on import of disabled custom sound effects
- **Tooltip:** “Right‑click for options” had an empty line left

---

## [4.13.0] – 2025-09-10

### ✨ Added

- **LibSharedMedia support:** **Combat Meter**, **Cast Tracker**, **Potion Tracker**, and **Resource Bars** now support styling via **LibSharedMedia** (bar textures, fonts, sounds).
- **Datapanel Latency:** New Datastream to show FPS and Ping (world | home) as Stream

---

## [4.12.1] – 2025-09-09

### 🐛 Fixed

- **Mouse:** Incorrect condition checks for some options.
- **Cast/Aura Tracker, Cooldown Notify:** Guard against invalid import strings.
- **Cooldown Notify:** Error on **Import Category** click.

---

## [4.12.0] – 2025-09-07

### 🔄 Changed

- **Craft Shopper:** Added **Track multiple** per recipe — enter a craft count and it adds all required reagents for **X** crafts to your Shopping List in one go.

---

## [4.11.1] – 2025-09-07

### 🐛 Fixed

- **Upgrade Merchant – flyout menu:** could show stale item levels; now displays the correct values.
- **Health Macro:** fixed a Lua error on login for Warlock characters.
- **Tooltip – spell icon ID:** hovering pet spells could trigger a Lua error.
- **LibOpenKeystone:** perfomance bugfixes.

---

## [4.11.0] – 2025-09-05

### ✨ Added

- **Tooltip · Unit:** Optional item level and specialization lines.
  - Loads via Inspect on first hover (outside combat), then cached briefly.
  - Updates the currently shown tooltip immediately when data arrives.
- **Tooltip · Unit:** Toggle to hide the “Right‑click for options” instruction line.
- **Tooltip · Mythic+ rating:** Optional modifier requirement (Shift/Alt/Ctrl) before showing the rating.
- **Mouse:** Independent “only show in combat” toggles for Ring and Trail.
- **Mouse:** Optional class‑color tint for Ring and Trail (disables the color picker while active).
- **Drink Macro · Health Macro:** New macro that always picks the best available Healthstone/potion, with options to use both in a castsequence, reorder by cooldown outside combat, and support for Demonic Healthstone.

### 🔄 Changed

- **TOC Update:** Updated TOC for 11.2.5 PTR and fixed some bugs to be compatible with PTR

### 🐛 Fixed

- **Vehicle Exit** was hidden, when ActionBar set to mouseover
- **DataPanel – Friends:** Cross‑realm display sanitized (no repeated realm suffixes like “-Antonidas-Antonidas”).
- **Dungeon Portal:** Division-by-zero when no teleports were available under certain filters.
- **Mythic+ – Talent Reminder:** Skip loadout entries missing a `text` field to avoid errors.

---

## [4.10.2] – 2025-09-04

### 🐛 Fixed

- **Resource Bars** were not visible at all

---

## [4.10.1] – 2025-09-03

### 🐛 Fixed

- **DataPanel – Friends:** Removed duplicate entries and clarified the tooltip with grouped sections (Battle.net, Friends, Guild).
- **Unit Frames – Mouseover:** Setting now takes effect immediately.
- **Import:** Fixed a small issue that could affect importing **Auras** and **CastTracker** categories.
- **DataPanel – Panel deletion:** Deleting panels no longer leaves stale “ghost” entries.

---

## [4.10.0] – 2025-08-30

### ✨ Added

- **Resource Bars:** Movable bars for Health and your class resources.
  - Disabled by default — enable via Options → Aura → Resource Bars.
  - Per‑spec: choose which bars to show. Supports Health and all class resources.
  - Positioning: anchor to the UI or to another Resource Bar; bars stack neatly. Hold Shift to drag when anchored to the UI.
  - Appearance: set width/height; pick the text style (Percent, Current/Max, Current) and font size. The Health bar has an absorb overlay and changes color with your health.
  - Setup & performance: simple per‑spec configuration; lightweight and resource‑friendly.
  - Charge‑style: optional separator ticks for charge resources; with customizable color.
  - Druid: per‑form visibility.

## [4.9.1] – 2025-08-28

### 🐛 Fixed

- **DataPanel – Currency:** Fixed season cap calculation.
- **Inspect – Item Level:** Corrected average item level computation (2H/off-hand handling).

## [4.9.0] – 2025-08-27

### ✨ Added

- **Combat Meter:** Interrupts are now tracked with a dedicated metric and panel.
- **Combat Meter:** Tooltips list which spells were interrupted.
- **Character Frame:** Red highlight for socket-eligible items without a socket (incl. Helm, Wrist, Waist in PvP)

### 🐛 Fixed

- **New Combat Meter Panel:** Loads and anchors correctly.
- Minor polish across the meter.
- _Catalyst_ an item missed the red marking for missed enchants sometimes

---

## [4.8.1] – 2025-08-25

### 🐛 Fixed

-- **Drink Macro:** Syntax error fixed

---

## [4.8.0] – 2025-08-25

### ✨ Added

- **Drink Macro:** Option to use _Recuperate_ alongside your normal drinks for faster regeneration.

### 🔄 Changed

- **Drink Macro:** Overall performance increased

### 🐛 Fixed

- **Combat Meter:** Spirit Link Totem / Tempered in Battle redistribution was incorrectly credited as damage done. It is now treated as **negative healing**, excluded from DPS.

---

## [4.7.1] – 2025-08-24

### 🐛 Fixed

- **BuffTrack:** Delves were not recognized as a valid difficulty, causing buff tracking to be skipped. Detection now works correctly.
- **Catalyst Charge:** Resolved cases where the feature unnecessarily fell back to the heavy detection path; it now prefers the lightweight path as intended.
- **Currency Stream:** Fixed a timing issue that could prevent currencies from refreshing. Values now update reliably after gains/spends and on login.
- **Combat Meter:** Corrected an anchoring/clamping issue that could make the window shift or “grow upward” when bars changed or on instance transitions. Frames now keep their position and clamp to screen properly.

---

## [4.7.0] – 2025-08-20

### ✨ Added

- DataPanel currency stream: per-currency tooltips, optional description hiding, and red highlight when capped
- Optional right-click menu for minimap buttons (Report, Garrison, Covenant)
- Full button range coloring
  - Entire action button is tinted when out of range
  - Choose your color and opacity for the overlay

### 🐛 Fixed

- DataPanel currency stream: per-currency tooltips now respect the description toggle and no longer show stray _“Right-Click for options”_ tooltips

---

## [4.6.0] – 2025-08-18

### ✨ Added

- Options to block duel requests, party invites, and pet-battle requests
- **Ignore:** remembers sort order and search term
- **Ignore:** right-click context menu with quick actions
- **Aura Tracker** - Filter for group type (Raid, Party, solo)

### 🔄 Changed

- Switched from LibOpenRaid to LibOpenKeystone
- Refactored the Dungeon Filter

### ❌ Removed

- _Hidden_ counter in the Dungeon Filter

### 🐛 Fixed

- Anchor issue with Mythic+ rating

---

## [4.5.0] – 2025-08-16

### ✨ Added

- **No Bloodlust in group** (LFG Filter)  
  Hides groups that already include a Bloodlust provider (Mage, Shaman, Evoker, or Hunter via pet), showing only groups **without** Bloodlust.
- **Repositioning**: Optionally move **Teleport Compendium**, **Mythic+ Rating**, and **Mythic+ Dungeons** frames.

### 🐛 Fixed

- **Combat Meter**: _Secret Technique_ (Rogue) was not counted.
- **Combat Meter**: Beast Mastery second pet (_Generic Hunter Pet_, NPC **165189**) was not mapped.
- **Potion Tracker**: **Offhealing** voice line did not always play.
- **Combat Meter**: **Reset during combat** could disable event logging.
- **Dungeon Filter**: Filtering failed in certain situations.
- **Patreon**: **Skip confirmation** behavior broken since 11.2.

---

## [4.4.0] – 2025-08-14

### ✨ Added

- **Combat Meter**: metric switch to toggle displayed metrics.
- **Combat Meter**: spell breakdown on bar hover
- **Combat Meter**: absorbed \*\_MISSED events now count toward damage done.

### 🐛 Fixed

- Resolved issues in **DataPanel**.
- Improved **Combat Meter** DPS/HPS determination accuracy.
- Fixed an error when filtering inventory by item level.
- **Combat Meter** no longer counts overkill for \*\_DAMAGE events.

---

## [4.3.0] – 2025-08-07

### ✨ Added

- Introduced the **DataPanel** system powered by a **DataHub** for sharing module data.
  - Create fully movable DataPanels and attach multiple data streams for real-time information.
  - Right-click any data stream for quick access to additional options.
- **Reshii Wraps Talent Frame** button option
  - Enable in _Character Frame_ settings to show an icon that instantly opens Reshii Wraps Talents for upgrades.

### 🆕 New Module: Combat Meter

- **Combat Meter** – track detailed combat statistics with fully customizable bar groups.
  - Disabled by default – enable via **Options → Combat Meter**.
  - Supports metrics for **DPS**, **Overall Damage**, **Healing per Fight**, and **Overall Healing**.
  - Per-group customization: bar width, height, max bars, and an “Always Show Self” option.
  - Optional **Pre-Pull Capture** window includes casts and actions just before combat starts.
  - Bars support texture & overlay selection, rounded corners, adjustable update rate, and font size.
  - Ultra lightweight – in most cases uses well under 1 ms per update, even in full 40-player raids at a 0.05 s update rate.

### 📊 Built-in Data Streams

- **Difficulty** – shows current instance or raid difficulty.
- **Durability** – displays average equipment durability.

  - Mouseover for a detailed per-slot breakdown.

- **Friends** – shows the number of online friends.
- **Gold** – tracks current character gold.
- **Stats** – summarizes key player statistics.
- **Talent Build** – displays the active talent loadout.

### 🐛 Fixed

- Fixed: Dungeon Rating now includes **Streets of Wonder** and **So’leah’s Gambit**.

---

## [4.2.0] – 2025-08-07

### ✨ Added

- Added 62 new sounds.
- Added an option to hide zone-change text.
- Added an option to show a Wowhead quick link in quest context menus (Quest Log and Objective Tracker).
- **Cooldown Notify** can now track on-use trinket cooldowns.
- **Enhance Ignore:** quick ignore/unignore action in the unit context menu.

### 🔄 Changed

- Performance improvements in **Aura Tracker**.
- Performance improvements in **Cast Tracker**.
- Performance improvements in **Mouse Trail**.
- Performance improvements in **Group Filter**.

### 🐛 Fixed

- Drag-and-drop in **Cast Tracker** / **Aura Tracker** no longer clears assigned sounds.
- **P.O.S.T. Master’s Express Hearthstone** was missing from the hearthstone list.
- **Cosmic Hearthstone** was missing from the hearthstone list.
- Party leader icon now disappears correctly after leaving the group.
- Deleting a **Cast Tracker** category could leave behind residual settings.

---

## [4.1.1] – 2025-08-06

### 🐛 Fixed

- Overlapping UI elements when **Mythic+ Rating** and **Dungeon Teleport** were both enabled.
- Blizzard’s 11.2 EditBox changes that broke several text-entry features.

---

## [4.1.0] – 2025-08-06

### ✨ Added

- **Tooltip**
  - Shows the item count from the Warband Bank.

### 🔄 Changed

- Updated the TOC files for the new 11.2 performance improvements

### ❌ Removed

- Deprecated code that became obsolete with patch 11.2.

---

## [4.0.0] – 2025-08-05

### ✨ Added

- **EnhanceQoL Shared Media**
  - New sub-module with **200+** voice lines and SFX, published via **LibSharedMedia**.
  - All sounds are **disabled by default**; enable only the ones you need.
- **Cooldown Notify**
  - Pops up a small alert when an ability becomes ready.
  - Supports **blacklist** (track everything except excluded spells) and **whitelist** (track only selected spells) modes.
  - Optional custom sound when the spell comes off cooldown.
- **Aura Tracker**
  - **Spacing** slider to adjust the gap between icons.
  - Now tracks on-use **trinket cooldowns**.
  - _Show for Difficulty_ filter — “Outside World,” “Any Instance,” or specific difficulties.
  - Tracks **temporary weapon enchants** with optional Enchant-ID filter.
- **Talent Reminder**
  - Custom sound when the wrong build is active.
- **Talent Reminder – Build Info**
  - Displays the name of the active talent build.
  - Text can be shown **only outside instances**, **only in 5-mans/Delves**, or **only in raids**.
- **Tooltip**
  - Can display IDs of temporary weapon enchants (stones, oils, imbues, etc.).
  - Option to show **spell icon ID**.
- **QoL Prompts**
  - Auto-confirm dialogs for **enchant overwrite** and **socket overwrite**.
- **Drink Macro**
  - _Food reminder_ icon is movable (hold **Alt**) and now has a size option.
  - Optional join/leave sound alerts.
- **Craft Shopper**
  - Shows a shopping list of missing crafting materials next to the Auction House.
  - Search and buy each item with a single click.
- **Unit Frames**
  - Option to hide the party-frame title.

### 🔄 Changed

- **Gem Helper**
  - Cleaner per-socket gem display.
- **Drink Macro**
  - Falls back to casting _Conjure Refreshment_ for mages if no food is available.
- **Dungeon Portal**
  - Performance improvements.

### 🐛 Fixed

- Catalyst charges sometimes disappeared near season end.
- Missing variable in Aura Tracker cooldown logic caused extra CPU load.
- Buff frame strata was too high.
- Cast Tracker now processes only mobs **actually fighting the player/group**.
- Unit-frame name truncation no longer affects nameplates.
- Nested conditions in _Aura Tracker_ now evaluate correctly.
- **Gem Helper** could rarely throw an error.
- **Vendor sell overlay** sometimes remained visible after changing settings.
- **Dungeon Portal** could occasionally throw a Lua error in combat.
- **Auction house sellable filter** had ignored some rare items

---

## [3.36.0] – 2025-07-29

### ✨ Added

- **Item-level display position**
  - You can now choose where the item level appears in your bags/bank and on the Character Frame.

### 🐛 Fixed

- **Cross-character gold tracker**
  - Warband gold was not included; it is now tracked correctly.

---

## [3.35.1] – 2025-07-29

### 🔄 Changed

- Cast Tracker is now disabled by default. Enable it manually to opt in.

---

## [3.35.0] – 2025-07-28

### ✨ Added

- **Cast Tracker**
  - Displays important enemy casts in a fully configurable progress bar.  
    Organise spells with drag-and-drop categories, pick custom icons and add optional sounds.
  - Ultra-lightweight: even with every tracked cast **and** buff in a Mythic-plus run  
    the tracker uses **≤ 1 ms CPU time per frame** and **≈ 400 KB RAM**.

### 🔄 Changed

- **Mouse Trail performance improved**

### 🐛 Fixed

- WuE, BoE and BA Gear was sometimes incorrectly shown in the bag

---

## [3.34.0] – 2025-07-26

### ✨ Added

- **Umbral Essentia**
  - The Shadowmelt Potion is now tracked in the _Potion Tracker_.
- **Fiber Socket**
  - Added support for the new _Fiber_ socket on the legendary cloak.
- **Aura Tracker**
  - Added a **Custom Text** field that can be anchored to **TOP / LEFT / RIGHT / BOTTOM** of the icon.
  - Custom text can now display calculated values: use `<stack>` as the current stack count, multiply it by a user-defined factor, and optionally clamp it to a minimum.

### 🔄 Changed

- **Sell-all-junk**
  - Now uses Blizzard’s newer, more reliable API.
- **Talent Reminder – Mega-dungeons**
  - Mega-dungeons such as _Tazavesh_ are handled separately.
- **Talent Reminder – initial load**
  - Significantly reduced initialization time.

### 🐛 Fixed

- Name-truncation issue in solo-dungeon content.
- _Aura Tracker_ option height was not sized dynamically.

---

## [3.33.1] – 2025-07-25

### 🐛 Fixed

- **Taint error when copying character names**
  - Resolved a protected-function taint that occurred in the context-menu’s **Copy Character Name** option.

---

## [3.33.0] – 2025-07-24

### ✨ Added

- **Delve-O-Bot 7001**
  - The teleport item is now listed in the _Dungeon Compendium_.
- **Quick-loot only while holding Shift**
  - New option: quick-loot triggers only when the **Shift** key is held.
- **Option tooltips**
  - Added concise UI descriptions for several settings.

### 🔄 Changed

- **Portal Compendium**
  - Favourites now have a fixed maximum number of buttons per row, so the window no longer stretches too wide.

### 🐛 Fixed

- **Instant Messenger**
  - Special characters no longer break message history.

---

## [3.32.0] – 2025-07-23

### ✨ Added

- **Vendor**
  - Added option to display a small **coin** icon on items marked for auto-sell
  - Added option to display an additional **red overlay** for clearer visual feedback
  - Added option to show **tooltip** information on items marked for auto-sell

### 🐛 Fixed

- **Memory usage**
  - Removed obsolete and duplicate function calls
  - Replaced excessive API calls with leaner, more performant alternatives
- **Aura Tracker**
  - Fixed a rare issue where some auras marked **“show when missing”** were not visible on login

---

## [3.31.0] – 2025-07-16

### ✨ Added

- **Quick vendor include-list management**
  - **Alt + Left-Click**: add the item to the include list (auto-sell)
  - **Alt + Right-Click**: remove the item from the include list

---

## [3.30.1] – 2025-07-16

### 🐛 Fixed

- **Aura Tracker on Login without Duration**
  - Fallback condition added when sometimes Timer-Texts are missing during login

---

## [3.30.0] – 2025-07-16

### ✨ Added

- **Aura Tracker**
  - **Category export/import** – share any aura setup with a single string.  
    Friends just paste it to import.
  - **In-game sharing** – send a clickable chat link to party, instance, raid, or guild;  
    one click opens the import dialog and pulls the auras in.
  - **Charges display** – optionally show remaining spell charges (requires **Always Shown**).
  - **Cooldown display** – optionally show remaining cooldown time (requires **Always Shown**).

### 🐛 Fixed

- **Aura Tracker** – rare database mismatch on startup.
- **Instance difficulty** – corrected several mislabeled difficulties (e.g. “MC 40 player”).
- **Aura Tracker** – auras visible at login but not tracked later are now handled correctly.

---

## [3.29.0] – 2025-07-15

### ✨ Added

- **Hide Boss-Kill Banner**  
  Automatically suppresses the victory/loot banner that appears after a boss kill.
- **Feature Descriptions**  
  Added concise in-UI descriptions for several existing options to make them easier to understand.
- **Full support for the new bank UI (11.2)**  
  All bank-related features work with the updated interface on patch 11.2.

### 🔄 Changed

- Removed some obsolete old code

### 🐛 Fixed

- Fixed a Lua error when opening the bank on PTR 11.2.
- Fixed a Lua error in item tooltips on PTR 11.2.
- Filtering for _Equipment_ still showed _Bags_ and _Profession Tools_

---

## [3.28.1] – 2025-07-14

### 🔄 Changed

- **Aura Tracker** – Some Buttons were moved

### 🐛 Fixed

- **Loot Toast** – resolved a rare error when opening the loot-toast settings panel.
- **Aura Tracker** – newly created auras are now automatically selected after you add their category.
- **Aura Tracker** – deleting a category immediately clears the right-hand options panel.
- **Aura Tracker** – glow effect now scales correctly when you change the icon size.
- **Aura Tracker** - fixed a missing Tooltip for _Alt spell IDs_

---

## [3.28.0] – 2025-07-14

### ✨ Added

- **Aura Tracker (module)**
  - Create draggable panels that show your own auras (buffs & debuffs).
  - Extensive filters: role, class, spec, stack count, remaining time, and more.
  - Ultra‑lightweight code – virtually zero performance impact even with hundreds of auras.
- **Truncate Raid-Frame Names**
  - Limit the number of characters(name-length) shown in the default party/raid frames.
- **Extended Raid-Frame Scale**
  - Scale the default party/raid frames beyond Blizzard’s built-in maximum.

### 🔄 Changed

- **Option Re-organisation**
  - Unit-Frame settings have been moved into their own _Unit Frame_ category.

### 🐛 Fixed

- Performance issue when _Hide buffs on raid-style frames_ was enabled.
- Error in TOC-Files

---

## [3.27.0] – 2025-07-11

### ✨ Added

- **Teleport Favorites in the Compendium**
  - New option lets you right-click any portal, teleport, toy, or hearthstone in the Compendium to mark it as a favourite.
  - Favourited entries receive a star icon, are pinned to the top of their section, and can be set to ignore expansion or filter-based hiding.
- **Auto-Mark Healer**
  - Automatically assigns a raid/world marker to the party’s healer, just like the existing _Auto-Mark Tank_ feature.

### 🐛 Fixed

- _Sell Next_ button was sometimes behind the frame on non repair merchants

---

## [3.26.0] – 2025-07-10

### ✨ Added

- **Alternative Difficulty Indicator**
  - New toggle that replaces the default icon with a clear text label, making the current dungeon difficulty easier to read at a glance.

---

## [3.25.0] – 2025-07-07

### ✨ Added

- **Delve Hearthstone**
  - The _Redeployment Module_ is now part of the Teleport Frame’s random-hearthstone pool.
- **Auto-Skip Cinematics**
  - New toggle that automatically skips all in-game cinematics whenever possible.
- **Loot-Toast Upgrades**
  - Fine-tune which loot toasts appear and how they behave.
  - Maintain a watch-list of specific items; when any of them drop you’ll get a custom sound and popup.  
    _Example: play a sound whenever you loot a particular uncommon trade good._
- **Vendor – Sell Next**
  - When _Only sell 12 items_ is enabled, a **Sell Next** button appears in the merchant window to unload the next batch.

---

## [3.24.0] – 2025-07-02

### ✨ Added

- **Vendoring**
  - New per-rarity option that lets you choose which crafting materials (grouped by expansion) are automatically sold.

---

## [3.23.0] – 2025-06-27

### ✨ Added

- **Enhanced Ignore List** – brand-new tool to manage ignored players (`/eil`, when enabled)
  - Can open next to the Friends frame and stay anchored there, or be moved freely.
  - Includes a search box for quick lookup.
  - Highlights Group-Finder applicants who are on your list in red (`!!! <NAME> !!!`).
  - Highlights group listings in the Dungeon Finder with `!!! <Name> !!!` in red when the leader is on your ignore list.
  - Blocks:
    - Trade requests
    - Duels
    - Pet Battles
    - Whispers
    - Yells
    - Emotes
- **Drink Macro** - Added Recuperate (Heal) as an Option for the macro when there is no mana food available

---

## [3.22.1] – 2025-06-25

### 🐛 Fixed

- Fixed a rare Lua error that occurred when joining instances and **hovering over currencies**.
- Upgrading items sometimes **resulted** in a Lua error when **Instant Catalyst** was enabled.
- While visiting a merchant, **incorrect item-level information** was occasionally displayed.

---

## [3.22.0] – 2025-06-24

### ✨ Added

- **TWW S3 Catalyst Currency**
- **Dungeon Teleports for TWW S3**
- **Updated TOC for 11.2.0**
- **Instant Catalyst button**
  - Instantly catalyst an item without the waiting time

### 🐛 Fixed

- Character frame reliably shows **Catalyst charges** again
- Mega-dungeon teleports work for **both halves** of split dungeons
- Fixed errors when visiting merchants that sell items for **currency**

---

## [3.21.0] – 2025-06-17

### ✨ Added

- **Bag-Filter Reset**
  - One-click button that clears all active bag-filter settings.

### 🔄 Changed

- Reduced some required libs
- Updated TOC for 11.1.7

---

## [3.20.1] – 2025-06-12

### 🐛 Fixed

- Fixed an issue in groups with **Hide buffs on raid frames**

---

## [3.20.0] – 2025-06-12

### ✨ Added

- **Hide buffs on raid frames**
  - New checkbox to hide _all_ buff icons on raid-style party frames (General → Party).
- **Hide player frame**
  - Option to hide your own unit frame while **“Show Party Frame in Solo Content”** is active (General → Party).
- **Hide dot in cursor ring**
  - Checkbox to remove the centre dot from the mouse cursor ring (Mouse → General).

### 🔄 Changed

- **/way command improvements**
  - The `/way` slash command now **accepts TomTom-style syntax**, e.g.  
    `/way #2403 47.6 74.5 …`

---

## [3.19.0] – 2025-06-09

### 🔁 Changed

- **Shared Media**
  - Changed ChatIM sounds to LibSharedMedia to have more sounds available

---

## [3.18.0] – 2025-06-01

### ✨ Added

- **Skyriding**
  - new checkbox that hides the Vigor-bar while on the ground
- **Vendor**
  - **Skip Heroic‑track items** – new checkbox that omits Heroic‑track gear when using _Epic‑track vendoring_.
  - **Skip Mythic‑track items** – new checkbox that omits Mythic‑track gear when using _Epic‑track vendoring_.

### 🐛 Fixed

- **Mythic Plus**
  - Fixed frame strata of Readycheck and Pulltimer to not overlap other frames
- **Vendor**
  - Upgrade-track items were no longer ignored after patch 11.1.5. This has been corrected.

## [3.17.1] – 2025-05-30

### 🐛 Fixed

- ChatIM frame strata was too high.
- Descenders (e.g. “g”) were slightly clipped by the edit box.
- `/r` and **Shift + R** no longer broke when ChatIM was enabled.
- Inspect now shows the correct item level for scaling items (heirlooms, artifacts).

---

## [3.17.0] – 2025-05-29

### ✨ Added

- **Instant Messenger** – Option to show incoming **and** outgoing whispers in a compact IM-style window.
  - Each conversation opens in its own tab, which flashes when a new message arrives.
  - Toggle the window with `/eim`; it can optionally fade when it loses focus.
  - Persistent history stores up to **1,000 messages per player**
    - History can be cleared per player or wiped entirely via the options panel.

---

## [3.16.0] – 2025-05-26

### ✨ Added

- **Gem-Socket Helper** – New Option under General->Character: Shows all socketable gems in a panel below the socket UI.

---

## [3.15.0] – 2025-05-26

### ✨ Added

- **Customisable Mouse-Ring Size** – Added a slider to adjust the diameter of the on-screen mouse ring.
- **Upgrade-Track Bag Filter** – New filter that groups items by upgrade track (Veteran, Champion, Hero, Mythic, etc.).
- **Vendor-Sellable Filter** – Quickly show items that can be sold to a vendor.
- **Auction-House-Sellable Filter** – Quickly show items that can be listed on the Auction House.
- **/way Command** - Added an Option to automatically place a Map Pin to find your destination.

### 🐛 Fixed

- Disabling **Auto-Keystone** no longer triggers Lua errors in edge cases.
- Bind-type labels (BoE, BoP and WA) now stay attached to the correct items instead of drifting to neighbouring slots.

## [3.14.0] – 2025-05-21

### ✨ Added

- **Re-enabled “Dungeon Filter” option**
- **Bag Filter: Binding Type** – filter bag items by their binding type

### 🐛 Fixed

- Fixed errors that could occur when buying or selling items with the **Vendor** feature.
- Vendor tools now load correctly after an update.
- Miscellaneous internal clean-up for improved stability.
- ButtonSink now correctly captures the minimap button of a specific add-on.

---

## [3.13.0] – 2025-05-14

### ✨ Added

- **Support for Talent Loadout Ex** – Talent Reminder now supports loadouts created with Talent Loadout Ex.

### 🐛 Fixed

- Mythic+ rating text could overlap other Enhance QoL frames in certain situations.

## [3.12.0] – 2025‑05‑10

### ✨ Added

- **Conditional enchant checks** – detects missing enchants context‑sensitively (e.g., Horrific‑Visions helm).
- **Missing Xal'atath voicelines** - some voicelines added in S2 were missing

### 🔁 Changed

- **Faster enchant scan** – internal routine streamlined for quicker results.

### 🐛 Fixed

- Tooltip did not appear on player, target, or boss frames when **Mouse‑over Hide** was enabled.

---

## [3.11.0] – 2025‑05‑06

### ✨ Added

- **CurseForge Localization Support** – all strings are now hosted on CurseForge; anyone can contribute translations.
- **Sound** module – central hub to toggle (or mute) specific in‑game sounds.
- **Keystone Helper** – brand‑new UI with new ready‑check status

### 🐛 Fixed

- Faction‑specific teleport items missing on non‑English clients.
- Objective Tracker erroneously depended on the _Talent Reminder_ module.
- Multiple missing translations and malformed localisation symbols.
- Default WoW bag search failed when “separate bags” was enabled.

### 🔊 Improved

- One‑click mute buttons for several annoying game sounds (roll‑out continues).

### 🎨 UI

- Polished Autokeystone & Pull‑Timer design  
  • Cleaner layout and visuals  
  • Animated status icon that reflects the ready‑check result  
  • Option to revert to the legacy look

---

## [3.10.0] – 2025-05-03

### Added

- **Auction House Filter Persistence** – remembers your Auction House search filters for the entire session.

- **Food Reminder** – lowered frame strata so it no longer obscures important notifications.
- **Module Icons** – refreshed symbol set for all module toggles.
- **Module naming cleanup** – removed the `Enhance QoL` prefix from all sub‑addon folder names for shorter, clearer titles.

### 🐛 Fixed

- Lua error when inspecting another player.

---

## [3.9.0] – 2025-05-01

### ✨ New Options

- **Bag Filter: Item-Level Range** – hide items outside a custom ilvl range.
- **Healer Spec: Auto-unmark self** – raid marker is cleared when you switch to healer.

### 🔁 Changed

- **“Tank Marker” → “Auto Marker”** – new name

### 🐛 Fixed

- Item level missing on some chest pieces in bags.

---

## [3.8.1] – 2025-04-30

### 🐛 Bug Fixes

- Added the missing translation for the account-gold option.
- Fixed an error that could break LFG Quick Signup.
- Persistent signup note in LFG now saves correctly.
- Corrected window positioning for several settings panels.

---

## [3.8.0] – 2025-04-29

### ✨ New Features

- **Objective-Tracker Auto-Hide in Mythic+**  
  Hides (or collapses) every objective-tracker block automatically when a Mythic-Plus key starts.
- **Square Minimap Toggle**  
  Replaces the round minimap with a space-efficient square version and re-anchors all minimap buttons.
- **Profile Manager**  
  Create, copy, delete and switch between profiles (character-specific or global).

### 🐛 Bug Fixes

- Fixed garbled characters (�) in the Chinese and Korean locales.

---

## [3.7.1] – 2025-04-28

### 🐛 Bug Fixes

- Garbled characters (�) in the Russian locale.  
  Removed rogue control characters and forced a Cyrillic-capable font in ruRU locale to eliminate yellow “missing glyph” squares.

---

## [3.7.0] – 2025-04-26

### ✨ Added

- Option to **show account-wide currency totals** in tooltips

### 🔁 Changed

- Temporary disabled the Dungeon filter to investigate a memory heap problem

### ❌ Removed

- Removed the option to disable the Blizzard AddOn Profiler (CVar no longer exists)
- Deprecated function calls

### 🐛 Bug Fixes

- Dungeon filter sometimes kept full groups in the list instead of cleaning them
- Dungeon filter sometimes showed filtered entries for a short time

---

## [3.6.1] – 2025‑04‑22

### 🐛 Bug Fixes

- Clearing the search filter sometimes left inventory items faded.

> **Note:** 3.6.1 is a pure bug‑fix patch.  
> All new features, changes, and additional fixes are listed in the **3.6.0** entry below.

---

## [3.6.0] – 2025‑04‑21

### ✨ New Features

- **Hideable Target Frame**  
  Hide the default target frame and let it reappear on mouse‑over.
- **Hideable Bag Bar**  
  Hide the bag bar and make it reappear on mouse‑over.
- **Hideable Micro Menu**  
  Hide the micro menu and make it reappear on mouse‑over.
- **Mage‑Food Reminder**  
  A handy button that queues you for a follower dungeon to grab free Mage food. (Only in Healer role and rested area)
- **Profession Icon Fade**  
  Optionally fade profession quality icons in your bags while searching.
- **Bag Filter Window**  
  A flexible filter panel for the default bags:  
  &nbsp;&nbsp;• Filter by equipment slot, item rarity, or specialization usability.
- **Money Tracker**  
  See the gold of all your characters in a single tooltip.
- **Show Party Frame in Solo Content**  
  Enables the party frame even when you’re playing solo.
- **Dungeon Filter Extension**  
  Extends the default dungeon filter:  
  &nbsp;&nbsp;• Filter for groups that have Bloodlust (or space for it) – shown only to classes without Bloodlust.  
  &nbsp;&nbsp;• Filter for groups that have Battle Res (or space for it) – shown only to classes without Battle Res.  
  &nbsp;&nbsp;• Filter for groups that match your current party.  
  &nbsp;&nbsp;• Filter for groups that already include your specialization – only shown for DPS specs.

### ⚙️ Changes

- All bag‑related options have been moved to a dedicated **“Bags”** tab.

### 🐛 Bug Fixes

- Engineering teleport buttons now appear reliably in every situation.
- Bag search no longer hides item‑level or bind‑type indicators.
