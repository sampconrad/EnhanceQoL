# Changelog

## [6.2.0] – 2025-11-22

### Options Update

Starting to change stuff to blizzard options, for now only a small part is there but more and more will follow

- Options menus transformed
  - Combat & Dungeons
  - Container Action
  - Items & Inventory
  
### ✨ Added

- Shortening per _Currency_ in _Currency Stream_ added
- Hide border and/or background of *Button Sink*

### 🔄 Changed

- _Show leader icon on raid style party frames_ now also shows leader and assist in raids

### 🐛 Fixed

- *Enhance Ignore List* Strata was to high

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

---

## [5.14.0] – 2025-11-07

### ✨ Added

- Hide the _release button_ and only make it usable with a modifier
  - Enable it by difficulty
- Action Bar → new _Button text_ inline group with macro/keybind font & outline controls (opt-in via dedicated toggles), per-bar keybind visibility, and an optional keybind shortening mode (e.g., **SM3** for Shift + Mouse Button 3). Macro fonts now disable automatically when “Hide macro text” is on.

### 🐛 Fixed

- Action Bar growth direction wasn't applied on first login
- Fixed some wrong remix achievement phases

---

## [5.13.0] – 2025-11-03

### ✨ Added

- Loot → _Group loot roll frames_ section with an enable toggle and live scale slider for the new anchor system.
- Social → _Friends list enhancements_ panel to toggle the decorator and adjust location visibility, home-realm hiding, and name font size.
- Action Bar → _Button growth_ controls that let you enable custom anchors per bar and choose growth directions from a compact dropdown grid.
- Action Bar → _Visibility_ dropdown now supports combining Mouseover, in-combat, and out-of-combat states per bar while keeping the Blizzard default when everything is unchecked.
- Action Bar → _Visibility_ dropdown now supports Pet Frame
- Items → _Selling & Shopping → Destroy_ queue that lets you purge junk via a secure minimap/bag button. It auto-uses the include list, skips protected items like Artifact/Heirloom/Token gear, highlights bag slots, and shows optional chat feedback.
- Chat → Optional chat bubble font override toggle with a size slider that updates bubbles instantly and persists per profile.

### 🔄 Changed

- Switched from SecureActionButtonTemplate to InsecureActionButtonTemplate

### 🐛 Fixed

- Resource bars with seperator were behind the bar
- Container action button now stays disabled while a Challenge Mode run is active
- Health macro no longer hammers cooldown checks, easing the performance hit during runs
- Chat options now refresh inline groups instead of rebuilding the whole page, so toggling checkboxes no longer jumps the scroll position.
- Lua taint error on in combat map opening (WorldMapDungeonPortals)

---

## [5.12.0] – 2025-10-26

### ✨ Added

- Legion Remix Tracker
  - Show all achievements which yields bronze or infinity knowledge now
  - Categories are now sorted alphabetically so mounts, pets, etc. are easier to scan.
  - Bronze + Infinity Knowledge achievements can define World Quest requirements; "Current" only lists bosses whose quests are active and tooltips explain the missing requirements.
  - Header now shows a `Collected: X / Y` indicator that matches the active filter (All vs. Current), alongside the remaining bronze.
  - Overlay frame strata can now be adjusted, and a gear button beside collapse opens the Legion Remix options directly.
- Edit Mode data panels can now pick their frame strata per panel for finer layering control.
- Data Panels now have an Edit Mode delete button with a confirmation prompt for faster cleanup.
- Food Reminder now appears in Edit Mode with slider and dropdown settings for quick tuning.
- Tooltip: target context menu can now copy NPC Wowhead links (toggle in Tooltip → Unit → NPCs).
- Chat Frame option to show loot and currency icons alongside their chat links (disabled by default).
- Encounter Journal loot spec overlay now adds per-loot specialization icons with configuration under Interface → EnhanceQoL → Items & Inventory → Loot.

### 🔄 Changed

- Removed the old options dropdown for deleting Data Panels; use the Edit Mode button instead.
- Food Reminder options panel now only offers an enable toggle; detailed settings live in Edit Mode.
- Simplified Food Reminder sound selection to a single dropdown with None/Default/custom choices.
- Tooltip → Unit options are now grouped into Player/NPC inline sections with a Player detail multiselect and dedicated modifier settings, keeping the panel compact.
- Autofocus of chat-IM removed

### 🐛 Fixed

- Legion Remix Tracker now listens for `ACHIEVEMENT_EARNED`, so freshly completed achievements update without reloading the UI.
- Removing a data panel now unregisters it from Edit Mode, preventing leftover ghosts in the layout picker.

---

## [5.11.0] – 2025-10-24

### ✨ Added

- More customizations for **Resource Bars**
- Option to reposition the **BR Tracker** outside of Raid and M+
- **Import/Export** for Resource Bars settings
- Copy Resource Bars settings across your other specs
- Data Panel stats can now show **rating** and **percent** together

### 🔄 Changed

- Data Panels are now configurable in size and position via **Edit Mode**
- **BR Tracker** is now part of **Edit Mode**
- Quick **Open Containers** button is now part of **Edit Mode**

### 🐛 Fixed

- Improved taint guard in world map teleports
- Container action cleared the cached list which leads to not showing all clickable containers
- **Infinite Bazaar** teleport was shown for non-**Timerunner** characters
- Stat order in the **Stats Panel** now respects Blizzard’s default stat order
- Cloaks on Legion Remix Collection Tracker were not correctly checked for the right phase

---

## [5.10.0] – 2025-10-22

### ✨ Added

- Option to show movement speed in character panel

### 🐛 Fixed

- Instance difficulty while in a guild group wasn't correctly hidden
- Hearthstone in Teleport Compendium wasn't shown
- Performance improvements because of multiple event calls
- Frame level of minimap border sometimes overlapped Expansion Landing Page

---

## [5.9.2] – 2025-10-20

### 🐛 Fixed

- Fixed missing and incorrect localizations across several languages.
- Container open quick button had some issues while moving the button

---

## [5.9.1] – 2025-10-19

### 🐛 Fixed

- Sometimes the gossip autoselect throws a lua error
- Backs were not counted as collected

---

## [5.9.0] – 2025-10-19

### ✨ Added

- Use **Guild Bank funds** for repairs when permitted.
- **Remix Collection Tracker** (Options → Events):
  - Customizable list of owned/purchased items.
  - Displays remaining **Bronze** required.
  - **Available** filter that matches your current _Legion Remix_ phase.

---

## [5.8.0] – 2025-10-17

### ✨ Added

- Options window now has a scale slider so you can resize the custom config panel without reloading.

### 🐛 Fixed

- Tooltip inspect integration no longer clears inspect data early, so the Blizzard inspect frame opens correctly even when showing spec and item level in tooltips.
- Merchant highlights now respect addons that hide or reindex vendor entries (e.g. TroveTally), so known/collected overlays no longer stick to ghost items.

---

## [5.7.0] – 2025-10-16

### ✨ Added

- Option to mark collected battle pets at merchants
- Missing chests for quick opening
- UI & Input → CVar: Added optional persistence toggle and grouped controls for new CVars (Auto Push to Action Bar, personal nameplate in combat, mouseover cast, cooldown viewer, raid/PvP class colors).

### 🔄 Changed

- More visibility to "known" items at merchants with a gray overlay and dim to texts

---

## [5.6.0] – 2025-10-15

### ✨ Added

- Tooltip: Unit tab now includes a "Hide health bar on Tooltip" toggle so you can hide the GameTooltip health bar.
- Action Bars: New "Hide macro names" checkbox to suppress macro labels on action buttons.

### 🔄 Changed

- Unit Frames & UI: Former mouseover-only toggles for Player, Target, Boss frames as well as the Micro Menu and Bags Bar are now unified dropdowns with multiple visibility options (always show, mouseover, hide in combat, etc.), replacing the old standalone “Hide” checkboxes.

---

## [5.5.0] – 2025-10-14

### ✨ Added

- Mythic+: New “Show Mythic+ chest timers” toggle (enabled by default) so players running AngryKeystones or similar can hide the duplicate +2/+3 timer overlay.
- Container Actions: Auto-open loot boxes for you and surface an action button for the few that still need a click (reputation insignias, Epoch Mementos, mounts); Shift+Right-Click to blacklist or add your own favourites.

### 🐛 Fixed

- Performance increasement to healthmacro

---

## [5.4.0] – 2025-10-12

### ✨ Added

- Legion Remix to the Infinite Bazaar for remix characters
- New Sound: Upgrade
- Loot toast filters per rarity now include an "Always show upgrades" checkbox that compares the drop against your equipped gear (class/spec aware)
- Option to move the loot toast message with a draggable anchor
- Merchants: highlight collectibles you already know with a green checkmark overlay (Items & Inventory → Vendors & Economy → Merchant)
- Vendors & Economy → Selling & Shopping → Remix (EnhanceQoLVendor): new auto-scrap toggle and controls to streamline Remix scrapping

### 🔄 Changed

- Loot toast settings are grouped together; the anchor button is only enabled once "Move loot toast" is toggled on
- Loot toast "Always show" choices for mounts, pets, and upgrades now live in a single dropdown
- Portal Compendium shows only timerunner related spells as remix character

---

## [5.3.0] – 2025-10-10

### 🔄 Changed

- BR Tracker is also visible in Raid encounter now
- LibOpenKeystone is silent during M+ runs and in combat now
- Some options and elements are disabled in remix/timerunner content
- Remix/Timerunner: Enchant display and missing‑enchant checks are fully disabled on Character and Inspect frames
- Flight Masters Whistle is now a toy

### 🐛 Fixed

- Worldmap teleports had some bugs during combat

---

## [5.2.0] – 2025-10-06

### ✨ Added

- DataPanels: Global “Lock position” option — hold Shift to move panels.
- DataPanels: Per‑panel toggle to hide the panel border.
- Items & Inventory → Bags: Option “Close bags when opening the Auction House”.
  - Disabled by default. Enable to automatically close all bags when the Auction House opens.
- Auratracker: New condition to check if you have learned a spell

### 🔄 Changed

- Gear & Upgrades → Character: Clearer controls for what to show.
  - One picker for the Character Frame (item level, gems, enchants, gem tooltips, durability, catalyst charges).
  - One separate picker for the Inspect Frame (item level, gems, enchants, gem tooltips).
  - Old individual checkboxes were folded into these pickers to keep the page tidy.

### 🐛 Fixed

- Teleports: Delve‑O‑Bot 7001 and Delver’s Mana‑Bound Ethergate now work with the new World Map panel on all characters.
- Chat: Fixed an error when quick‑replying and linking an achievement.
- Potion Tracker: Correct cooldown for Draught of Silent Footfalls.
- DataPanels: Font size now persists after a reload.

---

## [5.1.1] – 2025-10-01

### 🐛 Fixed

- Currency Datapanel sometimes marked the number red when still not at maximum
- Game Menu scaling overwrote other addons changes too

---

## [5.1.0] – 2025-09-28

### ✨ Added

- Unit Frames: Checkbox to hide the resting animation and glow on the Player frame.
- Dungeon Finder: Right‑click context menu on applicant members now includes “Copy Raider.IO URL” (toggle under Dungeons → disabled by default).

### 🧹 Cleanup

- Removed obsolete UI pages and unused tree callbacks (old Unitframe page, confirmations/mailbox stubs).
- Dropped no-op Bank hook and other dead helpers to reduce noise and maintenance.

### 🐛 Fixed

- While using World Quest Tab the Map icon was on the wrong position

---

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
