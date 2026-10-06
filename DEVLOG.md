# PKMods development log

New entries go on top. Each entry records what was done, why, and what is still unverified or
open.

---

## 2026-10-06 — State at the end of the playthrough

The user finished the game with the pack and is happy with it. Current features:
- **Air Control** (Ctrl+J, strength option);
- **Radar** (Ctrl+B, opacity Ctrl+= / Ctrl+-) with 14 category filters: Blood Crystals,
  Crests, Relics, Islands, Shrine Carvings, Music, Whisky, Transmissions, Ghost Items,
  Starlight Skins, Key Items, Shinji, Blood Shrines, Vending Machines. "Done" items are
  hidden via the game's own state: `bHasBeenRemoved` (this session), missing
  `Pickup_Glitch` / owned in the player's inventory (pickups), the player's collection
  (shrines, Shinji), owned drink (vending machines);
- **Fly Mode** (Ctrl+F): W/S along the view, Space/Alt up/down, 10–30 m/s;
- **Meditation Markers** (Ctrl+M, then tap Q): meditation hearts stay until toggled off,
  quick Q, 5× faster darkening;
- menu (F1, pages with 0), Ctrl+F9 diagnostics incl. the actors within 8 m.

Known open points: hot reload is disabled (it hung the game); the `StaticFindObject`
during-GC crash fix and the post-AR fly-speed restore weren't re-verified after the last
changes; the container research (crystals hidden in cupboards) was never finished.

---

## 2026-10-05 — Usage hints in the menu; flying slowed after the AR view

- Meditation Markers confirmed working (Ctrl+M, then tap Q; hearts stay).
- Menu: a feature can set `hint` (shown next to its item instead of the bare toggle key).
  Meditation: "Ctrl+M, then tap Q"; Fly: "Ctrl+F; Space up, Alt down".
- Bug: holding Ctrl (the game's AR view) while flying slows the player, and after leaving
  it flying stayed very slow. Likely the AR view restores its own movement values on exit
  and wipes ours; the fly tick only checked the movement mode. Now it also checks
  `MaxFlySpeed` and `MaxAcceleration` every tick and re-applies them. The first time it
  logs `Fly: movement values were changed by the game (...)` to confirm the cause.
- Refined at the user's request: while Ctrl is held, the game's slowdown is left alone;
  only for 2 s after Ctrl is released are fly speed / acceleration checked and
  re-applied (log: `Fly: after the AR view the game left ...`). Otherwise only the
  movement mode is checked.

---

## 2026-10-05 — Meditation Markers: Q still needed; faster darkening

- In-game: Ctrl+M alone showed no hearts. Log: on enable the forced
  `RevealTimeRemaining` made the pool visible ("markers shown"), but those were the
  previous meditation's markers at their old places. Choosing and placing markers happens
  in native code at the end of a meditation, so the mode can't replace Q.
- Changes: on enable, only hearts already showing are extended (no stale reveal); while
  on, the darkening timelines `MeditationEffect` / `MeditationEffect_Finished` get
  `SetPlayRate(5)` (restored to 1 on disable). Use: Ctrl+M once (the mode persists), then
  tap Q (0.15 s) for hearts that stay until Ctrl+M turns the mode off.

---

## 2026-10-05 — Meditation Markers: hearts that don't fade

- Watcher output during one meditation (hold Q):
  23:42:50 `Meditation.Timer` runs, `MeditationProcess` (post process) visible,
  `MeditationEffect` timeline active; 23:42:51 `bIsMeditating = true`; 23:42:53
  `MeditationItemRevealTimeRemaining: 0 -> 19.77`, `MeditationEffect_Finished` active, the
  markers' `bHidden: true -> false`; 23:43:13 (20 s later) markers hidden again.
- `pawn.Meditation` is a native `MeditationComponent`: `MeditationItemRevealTime = 20`,
  `MeditationItemRevealTimeRemaining`, `MeditationMarkerActorPool` (500 ×
  `BP_MeditationMarker`), `MeditationDistanceFromPlayer = 30000` (300 m),
  `TimeButtonHoldRequiredForMeditation = 0.7`, `RequiredKnowledgeForMeditation =
  MeditationKnowledge`. UFunctions are only event handlers (`OnReassessMarkers_From...`,
  `OnLoadedSaveGame`, `OnInventoryItemGained`, ...): no "reveal" to call.
- `features/meditation.lua` is now the real feature (Ctrl+M): while on, RevealTime and
  RevealTimeRemaining = 1e7 (hearts from a meditation stay; hearts already showing are
  extended), hold time 0.15 s. Re-applied every 0.5 s (float32 compare with tolerance).
  Off: Remaining = 0.05 (the game hides the hearts) and the original values return. It
  logs `Meditation: markers shown/hidden` (first pool marker's `bHidden`) to learn whether
  setting the timer alone reveals markers without a meditation.

---

## 2026-10-05 — Meditation Markers (research stage)

- User found the game's meditation (hold Q): the screen darkens, then hearts mark every
  unvisited / not-yet-activated place, and they fade quickly. Request: a hotkey that shows
  those markers at once, without the animation, until toggled off.
- Assets: player components `Meditation`, `MeditationProcess`, `MeditationEffect`,
  `MeditationEffect_Finished`; actor `Blueprint_MeditationMarkers/BP_MeditationMarker`;
  widget `UI/Meditation/MeditationWidget_BP`; `Materials/MovementPP/MeditationPostProcess`;
  knowledge `Knowledge/ItemData/Meditation/MeditationKnowledge` (the unlock).
- New feature `features/meditation.lua` (Ctrl+M, off by default), research only so far:
  on enable / Ctrl+F9 it writes `meditation_<date>_<time>.txt` (properties + UFunctions of
  those components, the widget and two markers); while on, every 0.5 s it logs changed
  simple properties (muted after 4) and the marker actor count. `Radar.snapshot` is now
  exported for this.
- Next: hold Q once with the feature on, read what changes, then implement the toggle.

---

## 2026-10-05 — Crash: StaticFindObject while collecting garbage

- The game froze and crashed with the engine reporting `LowLevelFatalError ... Illegal call
  to StaticFindObject() while collecting garbage!` (engine crash report,
  `UE4CC-Windows-607E9...`). It happened shortly after a Shinji exploded nearby (watcher:
  `bActorEnableCollision true -> false` at 21:50:38; report at 21:51:22). The game-thread
  stack goes through UE4SS's ProcessEvent detour (`UE4SS+0x462297`, twice); symbolizing it
  with the shipped PDB via dbghelp didn't resolve (likely an old dbghelp vs a new PDB).
- Our runtime code called `StaticFindObject` a lot: the WidgetLayoutLibrary CDO every tick
  (`UI.viewport`), the icon texture on every brush change, the collection struct every 2 s,
  widget classes on every UI rebuild. If any of our code runs while the engine collects
  garbage, that's fatal.
- Fix: `U.findPermanent(path)` looks classes / structs / CDOs up once and remembers them
  (they live all session); `U.cdo`, `UI.construct` and `playerProgress` use it. Icon
  textures are remembered at preload (the hidden keeper Images keep them alive) and
  checked with `U.valid` before use; `StaticFindObject` for textures only runs in the
  one-time preload after a level load.
- **Unverified:** whether this was the whole cause (the stack can't prove our Lua was
  running).

---

## 2026-10-05 — Hot reload disabled

- A 4th hang on Ctrl+R, this time with the menu open and Fly Mode off (so no per-frame
  timer): the log again ends at `All mods re-installed` (21:35:12). So UE4SS hot reload
  itself is unreliable with this game, not just our per-frame timer.
- The mod can't guard against it: Ctrl+R is handled by UE4SS, and a mod gets no "you're
  about to be reloaded" signal. So hot reload is now off (`EnableHotReloadSystem = 0`, the
  UE4SS default; build.ps1 no longer patches it on). Ctrl+R does nothing; updates load on
  game start. The Ctrl+R line is gone from the menu's HOTKEYS and the README; CLAUDE.md's
  testing loop now says "restart the game".

---

## 2026-10-05 — Slower flying

- User feedback: flying works and feels good, but too fast; climbing / descending with
  Space / Alt is too fast as well. The user's saved speed was 4000 (40 m/s, the max).
- Speeds are now 10 / 15 / 20 / 30 m/s, default 20. A saved value that's no longer offered
  (the old 4000) falls back to 20. Space / Alt add Z input of 0.5, i.e. half the flying
  speed. Flying along the view with W is unchanged.

---

## 2026-10-04 — Fly Mode, take 2: vertical input every frame

- The `AddMovementInput` hook logged only our own calls (`dir=(0,0,1)` from Space): the
  game moves the pawn from native code, past the UFunction, so its forward direction
  can't be swapped. The hook was removed.
- Space / Alt were very slow: our Z input came at 30 Hz while the game runs ~60 fps, and
  on the frames in between the strong flying braking (2 × speed) slowed the pawn again.
- Now, only while flying, a per-frame timer (`LoopInGameThreadAfterFrames(1)`, cancelled
  with `CancelDelayedAction` on disable) adds Z input every frame:
  `tan(camera pitch)` (capped at ±8) while W / S is held, so with the game's horizontal
  input the result points along the view, plus ±1 for Space / Left Alt.
  `MaxAcceleration` = 4 × speed while flying (restored on disable). Reminder: per-frame
  callbacks are suspected in the Ctrl+R hangs, so turn flying off before a Ctrl+R.

---

## 2026-10-04 — Fly Mode

- User request: a fly mode, off by default.
- `features/fly.lua`: Ctrl+F toggles; sets `CharacterMovement` to `MOVE_Flying` (5),
  `MaxFlySpeed` = 10/20/40 m/s (menu option, default 20), `BrakingDecelerationFlying` =
  2 × speed so it stops when keys are released. Vertical input via
  `pawn:AddMovementInput(Z ±1)` while Space / Left Alt are held (new `Input.held(key)`),
  since the game's own movement input is horizontal. Each tick re-applies flying if the
  game changed the mode. Turning it off restores the speed values and sets
  `MOVE_Falling` (3). Collision stays on.
- **Unverified in-game:** whether the game's controller overrides the movement mode every
  frame, and how smooth vertical movement is when input is added at 30 Hz.
- Follow-up (user request): W/S fly where the camera looks. A pre-hook on
  `/Script/Engine.Pawn:AddMovementInput` (the game's movement input, horizontal only)
  replaces a horizontal direction parallel to the control yaw (|dot| ≥ 0.9, i.e. the
  forward axis; strafe and our Z input pass through) with the camera's 3D forward
  (control rotation pitch included), keeping magnitude and sign. Written with
  `dirParam:set({X,Y,Z})`, falling back to field writes. The hook is registered on enable
  and unregistered on disable (`UnregisterHook`), so it only exists while flying (it runs
  every frame).

---

## 2026-10-04 — "What's in front of me?", Key Items, owned-item check for all pickups

- Ctrl+F9 now also logs every actor within 8 m (nearest first) with its item data or
  collection item (`main.lua`, `nearby()`), to identify an unknown object before picking
  it up. First use: `Blueprint_Pickup_FactoryEmployeeCard` → `Factory_EmployeeCard`, an
  item from `ItemData/KeyItems/` (6 items: Factory_EmployeeCard, Corridor_Key, Dog_treat,
  Gun_Love_Dies, LD_BloodVial, LD_Space_Helmet).
- New category Key Items (match by item data folder, icon
  `Inventory/Pickups/key_item_pickup`, white labels).
- Every pickup category gets `doneScan = ownedPickup`: the pickup's item data name is a
  key of the player's `Inventory.OwnedItems`. This should fix music (collected music
  pickups kept `Pickup_Glitch`, but `SoundTrack_*` items are in the inventory) and backs
  up the component checks for everything else.
- `ontake` was unreachable on the network; only the local PC got this version.

---

## 2026-10-04 — "Done" from the player's progress: drinks owned, collection items

- `playermaps_*` (keys read with `ToString`):
  - `pawn.Collection.CollectionData` keys = 7 categories: `MusicItemCategory`,
    `FoxMessengerCollection`, `ShrineCollection`, `IslandSequenceCollection`,
    `FootBathCollection`, `DrinkCollection`, `TransmissionCollection`; values are
    `HeldCollectionCategoryData` structs (fields not yet known by name);
  - `pawn.Inventory.OwnedItems` keys = item names (158), including bought drinks
    (`Collectable_Drink_Pillar`, `_PowerOfGoat`, `_Coffee_2`, `_Acid_2`,
    `_KillTheThirst_2`), crystals (`GoldCoin_017`), symbols, music, keys...;
  - `OwnedCurrency`: one entry `7 = 19` (Blood Crystals);
  - each vending machine's `Inventory.StartingItems` key is its drink
    (`VendingMachine_BizzareLychee` → `Collectable_Drink_BizzareLychee_2`,
    `_AngelNebula` → `Collectable_Drink_AngelNebula`, ...); `OwnedItems` holds it with
    amount 1 while unsold.
- `collection_states_*`: every shrine's `Collection` component has
  `CollectionCategory = ShrineCollection` and `CollectionItem = Shrine_<God>`; every
  Shinji has `FoxMessengerCollection` / `FoxItem_NN`. **Shinji is the Fox Messenger
  collection** (50 actors).
- New in `features/radar.lua`: `playerProgress()` (cached 2 s) builds `owned` from
  `Inventory.OwnedItems` and `collected` from every item name found in any field of the
  `CollectionData` structs (via `StaticFindObject(HeldCollectionCategoryData)` reflection;
  field names logged once as `Progress: ...`).
  - vending `doneScan`: `NumItemsPurchased > 0` or the machine's drink (first
    `StartingItems` key, cached) is owned. `CachedHasItems` dropped;
  - bloodshrine and shinji `doneScan`: the actor's `Collection.CollectionItem` name is
    in `collected` (Shinji keeps the collision check too).
- **Confirmed in-game:** vending machines and shrines disappear right after buying /
  donating and stay gone after a load. Log: `collection struct fields: CompletedItems`;
  collected names include `FoxItem_*`, `Shrine_*`, `Drink_*`, `MusicCollectable_*`,
  `IslandSequenceItem_*`, `TransmissionCollectable_*`, `footbath_*`; done counts at load:
  shinji 10/50, bloodshrine 4/17, vending 6/27.
- Open: music pickups collected before a load still show (all keep `Pickup_Glitch`); the
  collection has `MusicCollectable_*` names, so the same `collected` check could fix it
  once the pickup → `MusicCollectable_*` link is known.

---

## 2026-10-04 — Shrine donation leaves no trace on the shrine; reading the player's maps

- The user donated at a shrine with the watcher running (version from 17:51): **no**
  state change was logged, so no simple property of the shrine actor or its `Collection`
  component changes. The donation is stored elsewhere, most likely in the player's
  collection (`Collection.CollectionData`, a map) or a collection manager.
- UE4SS's TMap API here (Types.lua): `Find`, `Add`, `Contains`, `Remove`, `Empty`,
  `ForEach`. There's no `Num`.
- New research `playermaps` (a `run` function; research entries can now be custom code):
  walks `pawn.Collection.CollectionData`, `pawn.Inventory.OwnedItems` and
  `pawn.Inventory.OwnedCurrency` with `ForEach`, writing keys and simple values to
  `playermaps_<date>_<time>.txt`. Added with `collection` (the shrines' / Shinjis'
  Collection components) to `autoResearch`, so both are written at level load.
- Plan: match each shrine's collection item against a key of the player's
  `CollectionData` with `Contains`.

---

## 2026-10-04 — Vending sold-out after a load = `CachedHasItems == false`

- The new per-level debug lines answered it:
  - `Inventory.OwnedItems:Num()` fails with "attempt to call a nil value (method 'Num')":
    UE4SS maps have no `:Num()` here, which is why the load check found 0 of 27;
  - `CachedHasItems` on the machine actor: at 17:47:45 (right after the load) false on
    all five nearest; one second later true on all except `VendingMachine_Pillar`, most
    likely the machine sold out in an earlier session. So the game recomputes it on load.
    (`PowerOfGoat`, bought from before the restart, was true again; the save was probably
    from before that purchase.)
- Vending `doneScan` is now `CachedHasItems == false` or `Store.NumItemsPurchased > 0`.
  The brief all-false moment after a load is fixed by the next scan 3 s later. The map
  read is gone.
- **Unverified:** confirm `Pillar` is the machine sold out earlier and that it now stays
  off the radar after a restart.

---

## 2026-10-04 — Second hang on Ctrl+R; per-frame timer removed

- The game hung again right after a Ctrl+R: the log ends at `All mods re-installed`
  (17:46:05) with no output from the new Lua at all. Same picture as the 17:21 hang. The
  new code (OwnedItems map read, vending debug log) never got to run, so it isn't the
  cause.
- Both hangs happened right at a hot reload. Since yesterday the mod had a second timer
  that ran **every frame** (`LoopInGameThreadAfterFrames(1)` for key polling) next to the
  33 ms loop. Likely a race between UE4SS unloading the mod (another thread) and the game
  thread running our per-frame callback. Before that timer existed, Ctrl+R had worked
  dozens of times.
- Fix: the per-frame timer is gone; keys are polled in the single 33 ms loop. Advice:
  restart the game after updates instead of Ctrl+R (noted in CLAUDE.md).

---

## 2026-10-04 — Vending: works in-session, not after a load yet

- In-game: a machine bought from in this session disappears (`Store.NumItemsPurchased`).
  A machine sold out in an earlier session still shows: the load-time log said
  `Radar[vending]: 0 of 27 counted as done`, so `Inventory.OwnedItems:Num() == 0` never
  matched (either `:Num()` errors or the map isn't empty).
- The watcher caught the purchase: `Store.NumItemsPurchased: 0 -> 1` and, on the actor
  itself, `CachedHasItems: true -> false`. "Cached" suggests it may only be refreshed on
  interaction, so it may not survive a load.
- Added a category `debug(actor)` hook: once per level, for the 5 nearest items of a
  `doneScan` category, it logs the result (vending: `OwnedItems:Num()` or the error,
  `CachedHasItems`, `NumItemsPurchased`).
- Bug fixed: auto research ran in the main menu (`wrote 0 states`) and then never in the
  level. It now waits until any category has items and a pawn exists.

---

## 2026-10-04 — Vending "sold out" check

- Auto research dumps after a purchase (`vendingcomp_states_*`, `player_states_*`):
  - the machine just bought from has `Store.NumItemsPurchased = 1`, its neighbours 0. The
    earlier comparison after a fresh load didn't flag it on a machine sold out in a
    previous session, so the counter is probably per session;
  - each machine's `Inventory` (InventoryComponent) has `OwnedItems` (MapProperty, drink
    → amount), `bSaveInventoryState = true` and `bAutoFixItemsWithZeroAmounts = true`: the
    stock is saved and empty entries are removed, so **an empty `OwnedItems` = sold
    out**, also after a load;
  - machine actors are named after their drink (`VendingMachine_PowerOfGoat`,
    `_Fountain`, `_Pillar`);
  - player: `Inventory.OwnedItems` / `OwnedCurrency` / `StartingItems` maps,
    `SelectedTrackList`; `Collection.CollectionData` map; music in `ItemData/SoundTrack`.
- New category field `doneScan = fn(actor)` (runs per scan, results go into `c.gone`;
  logs `Radar[tag]: N of M counted as done` once per level). Vending:
  `Store.NumItemsPurchased > 0` or `Inventory.OwnedItems:Num() == 0`.
- **Risk / unverified:** first time a MapProperty is read (`:Num()` via UE4SS's TMap
  API). If the game hangs, revert this first. Also unverified: that `OwnedItems` really is
  empty on sold-out machines after a load.
- Likely the same mechanism for shrines and Shinji: the player's
  `Collection.CollectionData` map (not read yet).

---

## 2026-10-04 — Shinji "met" = collision off

- The user talked to a Shinji; he exploded but stayed on the radar. The state watcher
  logged `NPC_Shinji_C (3.8m): bActorEnableCollision: true -> false` (the
  `TimeInRotation` lines are a rotation timer, muted after 3).
- New category field `alive = fn(actor) -> bool` (per-frame, keep it cheap), checked in
  `isAlive`. Shinji: `alive = a.bActorEnableCollision == true`.
- **Unverified:** whether Shinjis met before a save load also come back with collision
  off (if not, they'd need a player-side check like the vending machines).

---

## 2026-10-04 — Vending: one machine = one drink; automatic research dumps

- After a fresh load the sold-out machine's `Store.bReceivedCancelMessage` /
  `bReassesInteraction` were false like everywhere else; they turned true only after the
  user talked to it. So they're interaction flags, not "sold out".
- User observation: every machine sells exactly one drink type. So "sold out" most likely
  means "the player already owns that drink". The radar needs (a) the drink each machine
  sells, which is probably in the machine's `Inventory` item array of structs, and (b) the
  player's inventory/collection.
- Snapshots now record every property's name and type, including the skipped complex ones
  (`<StructProperty, not read>`), plus array element types (`[n x StructProperty]`), so
  the right fields can be read on purpose later without risky blanket reads.
- New research `vendingcomp`: `Inventory` + `Store` of the 3 nearest machines.
- `cfg.autoResearch`: chosen research dumps (`vendingcomp`, `player`) are written
  automatically 3 s after the first scan of each level / Ctrl+R, since Ctrl+F9 dumps kept
  not happening.

---

## 2026-10-04 — Component comparison results; game hang from snapshotting a vending machine

- New research tool: `compare = { { tag, component } }` compares a component across all
  items of a category once per level (and on Ctrl+F9). It logs only properties with 2–8
  distinct values, each with the distance to the nearest item holding it.
- Results with the user standing at a sold-out vending machine:
  - vending `Store`: only `bReceivedCancelMessage` and `bReassesInteraction` are true on
    the nearby machine. That's probably the purchase window just opened and cancelled,
    not "sold out". The `Inventory` item lists are identical on all machines;
  - bloodshrine `Collection`: 0 differing properties across 17 shrines (one already
    donated to);
  - shinji `Collection`: only `bDisableInDemo` differs.
  - Conclusion: progress (drinks bought, blood donated, Shinji met) is most likely kept on
    the **player** (`FirstPersonCharacter` has `Inventory`, `Collection` components), not
    on these actors. Next: dump the player's `Collection` (research tag "player",
    Ctrl+F9) and match it against each shrine's / machine's item data.
- **Game hang:** right after the comparison, the game stopped responding (UE4SS kept
  hot-reloading, but nothing ran on the game thread any more). The first new thing then
  was the state watcher snapshotting the vending machine the user stood at, the first
  full snapshot of that class, listing elements of every array, structs included. Likely
  the hang. Fix:
  - `snapshot` reads only simple property types (bool/byte/enum/int/float/double/name/str/
    object/class); structs, maps, sets, delegates, text and interfaces are skipped; array
    elements are listed only for arrays of objects, and `ForEach` now stops (`return true`)
    after `maxElems` (it used to walk the whole array);
  - vending removed from the watcher.

---

## 2026-10-04 — Vending Machines on the radar

- User request: vending machines (all to be found), gone from the radar once a drink is
  bought.
- Assets: `Blueprints_VendingMachines/VendingMachine_Blueprint` and
  `VendingMachine_Broken_Blueprint` (unlocked via knowledge `BrokenVendingMachineUnlocked`).
  Drinks (`ItemData/Collectables/Drinks`, 23 + 3) are sold by them, which is why drinks
  never were world pickups.
- New category Vending Machines (`VendingMachine_*`, icon `Collectables/Drink_Coffee`,
  cyan labels), also watched by the state watcher.
- The watcher installed earlier hadn't run yet (no PKMods start after it in the log), so
  the user's purchase and donation weren't recorded.
- **Unverified:** what marks a machine as "bought from". Next: read the watcher's
  `state change` lines after a purchase.

---

## 2026-10-04 — State watcher for shrines and Shinji

- User donated at a shrine; its marker stayed. No Ctrl+F9 dump was taken afterwards, so
  there was nothing to compare.
- Added an automatic watcher (the approach that found `bHasBeenRemoved` for crystals):
  `Radar.new{ watch = { tags, radiusM, components } }`. Every 2 s, items of the watched
  categories within the radius are snapshotted (actor properties plus the listed
  components, here `Collection`), and changed values are logged as
  `Radar[tag] state change on <class> (<dist>): <key>: <old> -> <new>`. A key is muted
  after 3 changes so timers and animations don't flood the log. Watched: bloodshrine and
  shinji within 12 m.
- Next: donate at another shrine / talk to a Shinji, read the logged change, and turn it
  into the "done" check.

---

## 2026-10-04 — Shinji and Blood Shrines never showed: placeholder objects are truthy

- User: after Ctrl+R the new menu filters appeared, but no Shinji / shrine markers, even
  next to a shrine not yet donated to.
- pkmods.log: `Radar[bloodshrine]: 17 ... 17 with bHasBeenRemoved`, `Radar[shinji]: 50 ...
  50 with bHasBeenRemoved`. These actors have **no** `bHasBeenRemoved` property; UE4SS
  then returns a placeholder object instead of nil, and Lua treats any object as true. So
  every one counted as removed.
- Fix: `isAlive` and the component log compare strictly (`removed == true`,
  `hidden == true`). Rule for the codebase: never use a UE4SS property value directly as a
  Lua condition, compare with `== true`.
- Both Shinji (`Collection, InteractionDetection, VanishVFX, VanishSFX, ShinjiLaugh_Cue,
  ShadowMesh`) and the shrines (`Collection, Examine, InteractionDetection, Left_Flame,
  Right_Flame, Shrine_Fires_With_Sparks_Cue, Left_PointLight, Right_PointLight`) have a
  `Collection` component, likely where "met" / "donated" is kept. New research dump
  `collection_states_*.txt` (Ctrl+F9) with those components' properties.
- Ghost Items icon `Inventory/Pickups/ghost` isn't a Texture2D (logged), so it's replaced
  by `Inventory/KeyItems/Ghost_PowerStation_Item`.

---

## 2026-10-04 — Blood Shrines on the radar

- User request: the pyramid shrines where you let blood and donate a Blood Crystal (no
  name known; screenshots only). The "LADY LOVE DIES" speaker in the dialogue is the
  player character, not the shrine.
- Assets: class `Blueprint_Temples/Temple_Shrine_Blueprint`; collection
  `Collections/ItemData/Shrines/ShrineCollection` with 17 `ShrineItems/Shrine_<God>`
  (the same 17 god names as the Shrine Carvings); dialogue
  `Dialogue/Scripts/Collections/Shrines/Shrine_Generic`.
- New category Blood Shrines: parent and match `Temple_Shrine_Blueprint_C`, icon
  `2D_Assets/UI/Pyramid` (type-checked; a text marker if it isn't a Texture2D), red labels.
- **Unverified:** how a shrine already donated to is marked (no `Pickup_Glitch`, it isn't
  a pickup). Needs `Radar[bloodshrine]` in pkmods.log and a Ctrl+F9 dump.
- Also noticed: `BP_crate_collectable_pyramid_master` (a "pyramid" container) is
  something else, still in the container research.

---

## 2026-10-04 — Shinji on the radar

- User request: Shinji, an NPC met in many unexpected places, on the radar too.
- Assets: class `Assets/NPC/NPC_Shinji`; a collection of 25 encounters
  (`Dialogue/Scripts/Collections/Shinji/Shinji_01..25`); after talking he explodes /
  vanishes (`ShinjiExplode`, `ShinjiVanish`); avatar
  `2D_Assets/Characters/Avatars/shinji_avatar`.
- New category Shinji: parent and match `NPC_Shinji_C` (exact, never match-all because of
  the full-scan fallback), avatar icon, violet labels.
- **Unverified:** what a met Shinji looks like afterwards and after a save load
  (destroyed, hidden, or still there). The per-level component log `Radar[shinji]` will
  show it.

---

## 2026-10-04 — Radar marker opacity

- User request: an opacity scale for the radar markers on Ctrl+ / Ctrl-.
- `core/radar.lua`: setting `<id>.opacity` (default 1.0), 0.1–1.0 in 0.1 steps. Hotkeys
  Ctrl+`Equals` / Ctrl+`Hyphen` (plus numpad `Add` / `Subtract`, `hidden = true` so the
  menu lists them once); each change shows a toast (`Radar opacity: 60%`). Applied with
  `SetRenderOpacity` to labels and icons (off-screen icons ×0.75 as before). Menu item
  `Opacity: N%` (pressing it cycles 100 → 80 → … → 20 → 100).
- `core/input.lua`: `Input.label` shows readable names (`=`, `-`, `Num+`, `Num-`, `0`).
  `main.lua`: feature hotkeys with `hidden = true` aren't listed in the menu.

---

## 2026-10-03 — Real cause of the crashes: cached textures freed by the GC

- Local PC crashed right when entering the game from the main menu. The engine crash
  report (`%LOCALAPPDATA%\ParadiseKiller\Saved\Crashes\...\CrashContext.runtime-xml`)
  shows `EXCEPTION_ACCESS_VIOLATION reading address 0x00000003fff08dc2`, and the game
  thread stack goes through `UE4SS + 0x461c45`, i.e. it crashed while running our Lua.
- Cause (most likely, also for the `ontake` crash): `core/radar.lua` cached texture
  objects in a Lua table. Lua references don't count for Unreal's GC, so an icon not
  shown by any marker could be freed: on the level load after the main menu (icons had
  been preloaded in the menu), or by a periodic GC pass after 11 min of play on `ontake`.
  The next `SetBrushFromTexture` with the stale pointer then read freed memory.
- Fix:
  - texture objects are never cached; `textures[path]` only stores true/false, and every
    brush change looks the texture up with `StaticFindObject` and checks `Texture2D`;
  - for each icon, a hidden "keeper" `Image` in our UI holds the texture in its brush (a
    UPROPERTY reference), so the GC keeps it. Keepers are rebuilt per UI generation
    (`UI.generation`, bumped on every rebuild), and marker brushes are re-set then;
  - LoadAsset still runs only in `preloadIcons()` after a level load.
- Rule added to CLAUDE.md: don't hold UObjects in Lua across frames without re-checking,
  and keep assets alive through real UPROPERTY references.
- **Unverified:** that the crashes are gone.

---

## 2026-10-03 — Engine crash right after a runtime LoadAsset; icons preloaded

- `ontake` crashed with the UE4 Crash Reporter: `EXCEPTION_ACCESS_VIOLATION reading address
  0x0000014a00000038`, all frames in `ParadiseKiller_Win64_Shipping` (no UE4SS dump; the
  engine's own crash folder in AppData isn't reachable over the network).
- The last UE4SS.log line is `Asset loaded` at 23:06:49, the same second as the crash and
  11 min after the 10 icon loads at level start. The radar had just met an item whose icon
  wasn't loaded yet (per-item island/shrine pictures made that frequent) and called
  `LoadAsset` mid-gameplay. Likely causes: a synchronous asset load at an arbitrary
  moment, or a non-Texture2D object handed to `SetBrushFromTexture`. Not proven, but the
  timing is a strong hint.
- Fix (`core/radar.lua`): textures are loaded only by `preloadIcons()` on the first radar
  tick after a level load (category `icon` strings plus the new `icons` lists for function
  icons). After that, lookups only read the cache and never load. A loaded object must be
  a `Texture2D` or it's not used (logged). Islands and Shrine Carvings now use one generic
  icon (`Inventory/Pickups/collectables`) instead of ~40 per-item pictures.
- Crest component sets on `ontake`: `[Brackets, Pickup_Glitch]` ×13 and `[Brackets]` ×4
  (SyndicateCrest: the Red Crest was collected), farm valves `[Pickup_Glitch, SpawnScale]`.
  This confirms the `Pickup_Glitch` rule for crests too.
- **Unverified:** that the crash is gone.

---

## 2026-10-03 — Collected-before-load rule for all categories; crest bug

- User on `ontake`: a music pickup collected earlier showed on the radar again.
- The per-level component log (`ontake` pkmods.log) showed:
  - **Crest bug:** `Blueprint_Pickup_Parent_Crest_C` found nothing there, so the full-scan
    fallback ran with crest `match = function() return true end` and took **every
    actor** (gates, drains, lights, the player...) as a crest. Fix: crests match only the
    five known classes, and `Blueprint_Pickup_Parent_C` was added as a second parent.
    Lesson: `match` must never be match-all, because the fallback scans all actors.
  - **Collected rule:** nearly all pickups have components `[Pickup_Glitch, SpawnScale]`
    (music, transmissions: + `StaticMesh`; skins: + `MSH_FloppyDisk`). Some have only
    `[SpawnScale]`: 6 relics including the Crystallised Tear Necklace the user picked up,
    Islands 001–003, a shrine carving. Consistent with crystals (2 → 1 components). So a
    pickup without `Pickup_Glitch` was collected before the save was loaded.
- `core/radar.lua`: new category field `aliveComponent` (used: `"Pickup_Glitch"` for every
  category except crystals, which keep the verified `fullComponents = 2`). The
  collected-before check runs once per scan into `c.gone` (by address); walking component
  arrays every frame would be too slow.
- **Music is still unexplained:** all 13 music pickups had `Pickup_Glitch`, yet a collected
  song showed. Research: Ctrl+F9 now also dumps the player's `Inventory`, `Collection`,
  `ItemMonitor` components (`player_states_*.txt`, arrays up to 400 elements) to find where
  collected items are recorded. Dump headers now include the object name; objects without
  a location are fine.

---

## 2026-10-03 — Research: crystals hidden in containers

- User found that opening an interactive cupboard spawned a Blood Crystal, which only then
  appeared on the radar. Question: can such crystals be shown in advance?
- Fits an earlier observation: `GoldCoin_017` had `bNetStartup = false` (spawned at
  runtime, not placed in the map).
- Container classes in the assets (`Blueprints_Crates/`): `BP_crate_cupboard_master`,
  `BP_crate_cupboard_locked_hinged`, `BP_crate_cupboard_hinged_bloodChiller`,
  `BP_crate_gashapon_master`, `BP_crate_open_bin_master`,
  `BP_crate_collectable_pyramid_master`, `BP_locked_crate_no_computer`, plus
  `Blueprint_Lockers/Blueprint_EzraLocker`.
- Added: `Radar.new{ research = { { tag, parents } } }`. Ctrl+F9 dumps those actors too
  (`container_states_<date>_<time>.txt`). Snapshots now list the first array elements
  (`[n] a | b | ...`) instead of only the length, since the contents may be an array.
- Next: from the dump, find the property holding what a container spawns (a class
  reference or item data). Then show closed containers holding a crystal as a crystal
  marker (e.g. labelled "in box").

---

## 2026-10-03 — All world collectibles on the radar; menu pages

- User request: track every collectible type.
- Asset survey of `Blueprints_Pickups/` subfolders gave the world pickup kinds: Islands
  24, Shrine Carvings 17, Music 14, Whisky 12, Transmissions 6, Ghost Items 5, Starlight
  Skins 5 (plus crystals, crests, relics). Drinks (vending machines) and ancient symbols
  have no world pickups, so they got no category.
- New categories in `features/radar.lua`, matched by class-name prefix, with icons from
  `Inventory/Pickups/*` or per-item pictures (islands, shrine carvings) derived from the
  class name. Each has its own label color; the nearest of each is gold. Default ON.
- `core/radar.lua`:
  - one shared scan for all enabled categories: each parent class is searched with
    `FindAllOf` once per 3 s, not once per category (10 full object walks in one frame
    would hitch);
  - self-correcting parents: a category that finds nothing via its parent guess gets one
    full `FindAllOf("Actor")` scan per level, and the super classes of what it finds
    become its parents (logged as `Radar[tag]: found via full scan; parents now ...`);
  - marker selection: the nearest item of every enabled category is always shown, the
    rest fill up to 24 markers by distance;
  - turning a filter on triggers a rescan right away.
- Menu: 13 items now, so pages of 9; `0` turns the page (`Input.bind("Zero")`).
- **Unverified:** that the new pickups derive from `Blueprint_Pickup_Parent` (the full-scan
  fallback covers it), all icon paths, and how collected-before-load items of the new kinds
  look (`fullComponents` unset; per-level component logs in pkmods.log).

---

## 2026-10-03 — Relics category; items told apart by their ItemData folder

- User request: relics ("RELIC OBTAINED", e.g. Fantastic Crystallised Tear Necklace) on
  the radar too. In the world they all look like a heart, whatever the item.
- Found in the old crystal dump: every pickup has `ItemData` pointing to its
  `InventoryItemData` asset, and the asset folder gives the item type (see CLAUDE.md for
  the folder list). Relics = item data directly in `ItemData/Collectables/` (74) or in
  `Collectables/Update_NewCollectables/` (6); the other `Collectables` subfolders
  (Drinks, Islands, ShrineCarvings, Transmissions) are other collectible kinds.
- `core/radar.lua`: `match(className, actor)` now gets the actor too; new helper
  `Radar.itemDataPath(actor)` (GetFullName minus the class prefix; UE4SS has no
  GetPathName). New category Relics: parent `Blueprint_Pickup_Parent_C`, match by item data
  folder, icon `2D_Assets/Heart/heart-128`, pink labels, `fullComponents` unknown.
- Menu: 6 Relics. Installed on both PCs.
- Later candidates for categories (same ItemData approach): Drinks, Islands, Shrine
  Carvings, Transmissions, music (SoundTrack), Starlight skins, Whisky.
- **Unverified:** that relic pickups really carry `ItemData` like crystals (if not, the
  category stays empty: check the `Radar[relic]` line in pkmods.log).

---

## 2026-10-03 — One Radar with category filters

- User idea: instead of a separate radar per item type, one Radar toggled with Ctrl+B,
  with per-category ON/OFF filters in the menu.
- `core/radar.lua`: `Radar.new{ id, name, toggleKey, categories = {...} }` returns one
  feature. Each category (tag, label, parents, match, icon, fullComponents, colors) gets a
  menu option `<label>: ON/OFF`, stored as `radar.<tag>` (default ON). Markers of all
  enabled categories share one pool (16 markers), sorted by distance; the nearest item of
  **each** category is highlighted. The Ctrl+F9 dump writes one file per category.
- `features/radar.lua` defines the Radar and the categories Blood Crystals and Crests;
  `crystal_radar.lua` / `crest_radar.lua` are gone. Old settings
  (`crystal_radar.enabled`, `crest_radar.enabled`) are migrated once to `radar.enabled` /
  `radar.crystal` / `radar.crest`.
- Menu: 1 Air Control (Ctrl+J), 2 strength, 3 Radar (Ctrl+B), 4 Blood Crystals, 5 Crests.
- `install.ps1` now mirrors `PKMods\Scripts` exactly: scripts no longer in the package are
  removed from the game (the two old radar files were removed on both PCs).

---

## 2026-10-03 — Crest Radar; radar code made generic

- The user found a "Red Crest" pickup and asked for a radar for it too.
- Asset research (`tools/utoc_paths.py`): crests share the parent
  `Blueprint_Pickup_Parent_Crest`; five pickup classes, each placed several times
  (SyndicateCrest ×10, SuburbCrest ×3, DanchiCrest ×2, ApartmentStatusCrest ×2,
  Farm_Valve ×3, per the item data assets). Each has an inventory icon in
  `Textures/Inventory/KeyItems/`.
- Refactor: the radar logic moved from `features/crystal_radar.lua` into `core/radar.lua`
  (`Radar.new(cfg)`: parents, match, icon path or per-class function, `fullComponents`,
  colors). `crystal_radar.lua` and the new `crest_radar.lua` are now short configs. Marker
  icons are set per item (cached textures, brush changed only when the icon differs). The
  Ctrl+F9 dump files are now `<tag>_states_<date>_<time>.txt`. The once-per-level
  component log groups by component set (`Radar[<tag>]: N with components [...]`).
  The full-actor fallback scan was dropped (the parent-class search works).
- Crest Radar: separate menu item, no hotkey, off by default, cyan labels.
  `fullComponents` is unset, so crests collected before a save load may still show until
  the component log shows how they look.
- Installed on both PCs (local and `ontake`).
- **Unverified:** whether crests use `bHasBeenRemoved` like crystals, and their component
  sets.

---

## 2026-10-03 — Published to GitHub

- Repository: https://github.com/chepash/paradise_killer_mods (branch `main`).
- The local `.git` from an earlier clone attempt was an empty skeleton (no HEAD/config), so
  the repo was initialized locally and pushed to the empty remote.
- Repo-local git config: author `Pavel Cherdantsev <cherdantsev.p@gmail.com>`; the shell's
  HOME isn't the Windows profile, so `core.sshCommand` points at the SSH key and
  known_hosts explicitly (same setup as the user's other repos).
- `.gitattributes`: `* text=auto`, DLL/ZIP binary.

---

## 2026-10-03 — Repository restructured: sources + build script, no binaries

- The user plans to put the project on GitHub. The old `Win64\` folder was 21 MB, of which
  20.6 MB was `UE4SS.dll`; our own code is ~52 KB. Committing the third-party binary would
  add ~20 MB to the history on every UE4SS update.
- New layout:
  - `package\` contains only our files, in the game's layout (`ue4ss\Mods\mods.txt`,
    `mods.json`, `ue4ss\Mods\PKMods\Scripts\...`);
  - `build.ps1` downloads the pinned UE4SS asset (`experimental-latest` /
    `zDEV-UE4SS_v3.0.1-1152-ge3ba1016.zip`, SHA-256 `7D2DC616…7C77D00`, cached in
    `.cache\`), extracts only the shipped files (no 145 MB PDB, no demo mods), patches the
    ini (hot reload on) and Keybinds (ObjectDumper → Ctrl+Num4) by regex, lays `package\`
    over it, and writes `dist\Win64\` + `dist\PKMods-<VERSION>.zip` (8.3 MB);
  - `install.ps1` runs the build first (`-NoBuild` to skip), then copies changed files from
    `dist\Win64\`;
  - `VERSION` = 0.1.0; `.gitignore` = `dist/`, `.cache/`;
  - `README.txt` was replaced by a GitHub-style `README.md` (install from release, keys,
    build from source, credits).
- Verified: the build output matches the previous hand-made `Win64\` byte-for-byte except
  line endings in two UE4SS text files (the build keeps the original CRLF; the old copy had
  been converted to LF by `sed`). The zip uses forward-slash paths. The end-to-end
  `install.ps1` run worked.
- Note: `experimental-latest` is a rolling tag. If the asset changes, the build fails on the
  hash check; the new UE4SS must then be tested in the game before updating the pin.

---

## 2026-10-03 — Frozen "ghost" radar markers

- User screenshots: with the radar ON there were ~25 markers (the limit is 12), and after
  turning it OFF about 12 stayed on screen, frozen in place regardless of the camera. So
  an orphaned set of marker widgets from an earlier build was still attached to the HUD.
- Likely causes:
  1. widget names restarted at `PKM_<short>_1` after every Ctrl+R reload. Constructing an
     object with the name of an existing one in the same outer overwrites it in place, so
     old and new markers got tangled;
  2. the leftover sweep walked the host canvas with `GetAllChildren`, and apparently
     removed nothing (it fails silently inside `pcall`).
- Fix (`core/ui.lua`): widget names now carry a per-run random token
  (`PKM_<short>_<token>_<n>`); every widget created by the current build is recorded in a
  `live` set. After each build, `sweepOrphans()` finds every Image/TextBlock/Border in the
  game whose name starts with `PKM_`/`BCR_` and isn't live, then collapses and removes it.
  It logs `UI: removed N leftover widget(s)`.

---

## 2026-10-03 — Ctrl+B toggles the radar

- User request: bring Ctrl+B back, now as the radar's on/off key (`toggleKey`), so it shows
  up in the menu next to the radar item.
- The game's action mappings are only in the packed DefaultInput.ini (the user's
  `Saved\Config\WindowsNoEditor\Input.ini` has only axis settings), so whether B is used by
  the game couldn't be checked; it's unlikely. Our binding requires Ctrl, so a plain B still
  goes to the game. Side effect: holding Ctrl for the combo may open the game's AR view for
  a moment.

---

## 2026-10-03 — Hotkeys shown in the menu

- User request: the hotkeys are easy to forget, so show them in the F1 menu.
- A feature's `toggleKey` is shown next to its menu item (`[ON ]  Air Control   Ctrl+J`).
  A HOTKEYS list at the bottom shows feature `hotkeys` (new `desc` field) and global keys
  added with `Menu.addHotkey`: Ctrl+F9 diagnostics and Ctrl+R UE4SS reload. Labels are built
  from the same definitions the bindings use (`Input.label`), so new features show up
  automatically.

---

## 2026-10-03 — Air Control strength defaults to 1.0

- User request: on a fresh install (e.g. a new PC) Air Control strength should start at
  1.0, not 0.5. Changed the default in `features/air_control.lua`. The package contains no
  `settings.txt`, so a fresh install picks up the default; existing settings are kept.

---

## 2026-10-03 — Collected crystals come back after loading a save

- User report: picked up a crystal (it vanished from the radar), saved, quit, restarted,
  loaded. The radar pointed at that same crystal again. So the earlier conclusion
  "collected crystals aren't spawned after a load" was **wrong**: they are spawned, with
  `bHasBeenRemoved = false`.
- Looking again at the after-load dump from 20:08:51 (before that session's pickup): 4 of
  133 crystals had `BlueprintCreatedComponents = [1]` instead of `[2]`
  (`GoldCoin_117`, `_156`, `_159`, `_017`). That is the same change seen on pickup (2 → 1).
  `_017` also has `bNetStartup = false` (spawned at runtime, not placed in the map).
- Also found: the component lists in all dumps were empty. `K2_GetComponentsByClass`
  returns nothing for these actors, so the earlier component-visibility checks never
  checked anything.
- Change: `isAlive` = valid, `not bHasBeenRemoved`, `BlueprintCreatedComponents` count ≥ 2,
  `not bHidden`. The broken `meshes()` / `meshVisible()` were removed; the array is read
  directly. Once per level, `pkmods.log` gets a summary of component-name sets
  (`N crystal(s) with components [...]`), and the Ctrl+F9 dump lists the component names.
- **Unverified:** that the missing component really means "collected" (could also be
  crystals that are special by design, e.g. `_017`). The next step is to replace the count
  check with a check for the specific component by name, once the log shows it.

---

## 2026-10-03 — Radar no longer tied to Ctrl

- User decision: showing crystals together with the game's Ctrl AR view is redundant. Ctrl
  stays purely the game's; the radar is switched on/off in the F1 menu only and shows
  markers the whole time it's on.
- Removed: Ctrl-hold detection, the "always on (no Ctrl)" menu option, the Ctrl+B hotkey.
  The menu now has 3 items (Air Control, its strength, Blood Crystal Radar). The radar's
  default is now OFF for new installs; existing `settings.txt` values are kept.
  A leftover `crystal_radar.always_show` key in old settings files is ignored.

---

## 2026-10-03 — Found the real "picked up" flag: `bHasBeenRemoved`

- The pickup-signal workaround worked in the game: the crystal disappeared from the radar
  right after pickup. `pkmods.log`:
  `picked up Blueprint_Pickup_GoldCoin_066_C (1.4m away, via notification widget)`. Only the
  notification widget signal fired; the sound hooks never did (the cue is probably played
  some other way).
- The property diff found the real flag: on the crystal,
  `bHasBeenRemoved: false -> true` and `BlueprintCreatedComponents: [2] -> [1]`.
  Game-wide objects only showed the pickup popup (`GameInstance.ActiveWidgetBases`,
  `TriggerTimersBlocked`, `Pawn.bBlockMovement`, `PC.bShowMouseCursor`); no crystal counter
  showed up there.
- The after-load dump (`crystal_states_*.txt`): 133 crystals present in a mid-game save,
  none with `bHasBeenRemoved = true`. So crystals collected in earlier sessions aren't
  spawned at all, and only in-session pickups need the flag.
- Simplified the radar: `isAlive` = valid, `not bHasBeenRemoved`, `not bHidden`. Removed the
  whole pickup-tracking workaround (sound hooks, notification hook, per-second property
  snapshots, game-wide diffs, the automatic dump after every load) and the component
  visibility heuristic. Ctrl+F9 keeps the full dump of every crystal to
  `crystal_states_<date>_<time>.txt` plus a short list in the log. `pkmods.log` stays.
- **Unverified:** that crystal 066 is missing from the dump after the save is loaded again
  (this would confirm "collected crystals aren't spawned").

---

## 2026-10-03 — More research logging (save/load angle)

- Saves: `%LOCALAPPDATA%\ParadiseKiller\Saved\SaveGames\PKSlot_N.sav`, GVAS (UE 4.27) with a
  `/Script/ParadiseKiller.PlayerSaveData` object. All game state is in the
  `SerializedSaveData` string (hex, ~55 KB of bytes), and `bIsEncrypted = true`; entropy
  7.99 and no zlib stream, so it's encrypted. Reading saves offline isn't practical;
  research happens at runtime instead. Note: there is native game code (`/Script/ParadiseKiller.*`
  classes).
- Added:
  - `pkmods.log` in the mod folder: every `U.log` line is also appended there with a
    timestamp, because `UE4SS.log` is recreated on every game start;
  - on pickup, besides the crystal, the diff now covers game-wide objects: `GameInstance`,
    every `PlayerSaveData`, the PlayerController and the Pawn (scalars, object names and
    array lengths, floats skipped). This is meant to find the crystal counter or a
    "collected pickups" array;
  - 10 s after every level load (and on Ctrl+F9), the full state of every crystal is
    written to `crystal_states_<date>_<time>.txt` in the mod folder, to compare crystals
    collected in an earlier session with uncollected ones. May cause a ~1 s hitch.
- Test plan for the user: pick up 1–2 crystals → save → load that save (or restart the
  game and load) → wait 10 s → report back.

---

## 2026-10-03 — Picked-up crystals: detect the pickup event instead

- Confirmed: the key-polling fix works (no more crashes on rapid key presses). The user
  likes the gold highlight on the nearest crystal.
- Still broken: a crystal stays on the radar after pickup, so the `PrimitiveComponent`
  visibility check doesn't catch it either. No Ctrl+F9 dump was taken.
- The user suggested a workaround: keep a list of crystals and, when the player's crystal
  count goes up, drop the nearest one. Implemented with pickup signals that are easier to
  hook than the count:
  - `RegisterHook` on `GameplayStatics:PlaySound2D / SpawnSound2D / PlaySoundAtLocation /
    SpawnSoundAtLocation`; the sound name containing `Blood_Crystal_Acquired` is a pickup;
  - `NotifyOnNewObject` on `GoldCoinPickupNotification_BP_C` (registered once the class is
    loaded) as a second signal. Signals within 1 s count as one pickup, and signals in the
    first 8 s after a level load are ignored (HUD widgets get recreated then);
  - on a signal, the nearest crystal within 8 m is added to `collected` (keyed by class name,
    unique per crystal, kept for the game session) and disappears from the radar.
- Auto-research: crystals within 8 m are snapshotted every second (all readable properties
  of the class chain + component visibility). 700 ms after a pickup the differences are
  logged as `Radar:   changed ...`, so the real "collected" flag can be found without the
  user pressing Ctrl+F9. Ctrl+F9 now also lists `collected` and the notification hook state.
- **Unverified:** whether either signal fires (the log will show `Radar: picked up ... via
  ...`). Known limitation until the real flag is found: crystals collected in earlier game
  sessions still show, and a crystal given by an NPC while standing within 8 m of a lying
  one would mark that one.

---

## 2026-10-03 — Crash when pressing a menu key quickly; hotkeys moved to the game thread

- The new UE4SS works with the game: the log shows
  `Loaded 2 features (game-thread timers)`, the EngineTick hook is installed, and the menu
  works.
- Pressing "2" (Air Control strength) 5–6 times quickly crashed the game about 11 s later
  (no dump this time). The log showed Lua state corruption first:
  `No overload found for function 'FText'` on a plain string (crystal_radar.lua), then
  `[Lua::Registry::get_function_ref] Ref was not function` twice.
- Cause: `RegisterKeyBind` callbacks run on a separate UE4SS thread (they called
  `ExecuteInGameThread`), while the main loop runs on the game thread, so two threads used
  the same Lua state at once.
- Fix: new `core/input.lua`. No more `RegisterKeyBind`; keys are polled every frame on the
  game thread with `PlayerController:IsInputKeyDown` (`LoopInGameThreadAfterFrames(1)`, or
  every 33 ms on older UE4SS) and fire on the press edge. Ctrl must match the binding: Ctrl+B
  doesn't trigger a plain B binding, and digits with Ctrl held don't switch menu items. Key
  definitions use Unreal FKey names (`toggleKey = { key = "J", ctrl = true }`). All
  `SetText(FText(...))` calls now go through `UI.setText`, which passes `tostring(text)`.
- **Unverified:** whether hotkeys work while the game shows UI-only screens (polling needs a
  PlayerController), and whether the crash is gone.

---

## 2026-10-03 — Game crash; switched to a newer UE4SS

- The game froze and UE4SS wrote `crash_2026_10_03_15_48_34.dmp`, ~18 s into gameplay.
  The log just before the crash looked normal (UI attached to `HUDNotificationWidget_BP_C`,
  menu text color now white, so the black-text fix worked).
- Dump analysis (`tools/minidump_summary.py`, written for this; no debugger on the machine):
  exception `0xC0000264` STATUS_RESOURCE_NOT_OWNED in ntdll, raised from UE4SS.dll frames
  called from the game exe, i.e. the game thread running our queued callbacks and releasing
  a lock it didn't own. Most likely cause: our main loop was `LoopAsync(33)` +
  `ExecuteInGameThread`, about 30 cross-thread hand-offs per second, and UE4SS 3.0.1 has known
  threading bugs there (newer changelog: "Lua_lock implementation/threading fixes",
  "Added a lock guard for ExecuteInGameThread to prevent a crash", plus a use-after-free
  fix for Lua strings from UObject member access).
- Fix:
  - Switched to UE4SS **experimental-latest** (zip `zDEV-UE4SS_v3.0.1-1152-ge3ba1016`,
    changelog header v4.0.0-rc1). New layout: only `dwmapi.dll` next to the exe, everything
    else under `Win64\ue4ss\`. Hot reload had to be enabled in the ini (default is off).
    `mods.json` was added alongside `mods.txt`. ObjectDumper moved to Ctrl+Num4 because
    Num5 is now DumpJMAP.
  - `U.gameLoop` / `U.gameDelay` in `core/util.lua` use the new game-thread timers
    (`LoopInGameThreadWithDelay`, `ExecuteInGameThreadWithDelay`), with a fallback to the
    old async path on older UE4SS. The startup log says which one is active:
    `Loaded 2 features (game-thread timers)`.
  - `install.ps1` migrates `settings.txt` and removes the 3.0.1 root files.
- **Unverified:** whether the new UE4SS initializes correctly with this game (signature
  scanning) and whether the crash is gone. The two previous items (menu readability,
  picked-up crystals) are also still unverified.

---

## 2026-10-03 — Third run: black-on-black menu, picked-up crystals still shown

- Host is still `HUDNotificationWidget_BP_C`, now at opacity 1.00, so the background became
  fully opaque. But the menu text was invisible: black on black.
- Likely cause: `SetColorAndOpacity` on the TextBlock doesn't apply the intended color
  (the white text in the first run was probably just the TextBlock default). Fix: the menu
  text no longer sets a color (default white); background is dark blue-gray
  `(0.06, 0.07, 0.12, 0.92)` instead of black; the actual text color is logged as
  `menu text color: ...` right after the menu is built. **Unverified:** radar labels and the
  toast still use `UI.setColor`; check whether their colors render correctly.
- Picked-up crystals still stayed on the radar with the `MeshComponent` check. Hypothesis:
  crystals are drawn as icon sprites/billboards (assets `PickupIcon_DistanceBlend_GoldCoin`),
  not meshes, so no meshes were found and the crystal always counted as present. The check
  now covers every `PrimitiveComponent` (collision shapes are hidden in game by default, so
  they don't count). **Unverified:** if a picked-up crystal still shows, a Ctrl+F9 dump next
  to it is required to find the real "collected" flag.

---

## 2026-10-03 — Second run: the menu works, the radar finds crystals

Confirmed in the game: the F1 menu opens, and the radar finds crystals and shows them. The UI
attached to `HUDNotificationWidget_BP_C`.

Problems and fixes:
- **The menu was hard to read.** The host `HUDNotificationWidget_BP_C` is the pop-up
  notification widget (location name). Its opacity is animated, and our widgets inherit the
  host's opacity. Fix: `core/ui.lua` picks an opaque host (opacity ≥ 0.99), or the most opaque
  one if none is fully opaque, and moves when the host becomes more transparent. Our widgets
  are cleaned up only when the host actually changes. Menu background is almost black
  (A = 0.96), text is 20 pt light yellow, and the panel moved to Y = 240 (below the location
  banner).
- **A picked-up crystal stayed on the radar** (it pointed to a spot 1–3 m away). So after
  pickup the actor is not destroyed and `bHidden` is not set. New `isAlive` heuristic: a
  crystal counts as present if the actor has at least one visible `MeshComponent`
  (`IsVisible() and not bHiddenInGame`), cached for 500 ms per actor.
  **Unverified:** if this doesn't help, a Ctrl+F9 dump next to a freshly picked-up crystal is
  needed. The diagnostics now print meshes/visible/alive for every crystal, plus all
  components and properties of the two nearest ones.

---

## 2026-10-03 — First run: the mod crashed on startup

- Symptom: pressing F1 did nothing, no overlay at all.
- `UE4SS.log`: `main.lua:51: attempt to concatenate a nil value (field 'id')`.
  UE4SS v3.0.1 itself started normally.
- Cause: in Lua 5.4 `require` returns `(module, filepath)`. The last `require(...)` in the
  `FEATURES` table constructor expanded to both values, and the path string became a third
  "feature". The script stopped before the menu and key bindings were created.
- Fix: every `require` is wrapped in parentheses, `(require(...))`, and the rule is written
  down in CLAUDE.md. Added a fallback path for settings.txt and a log line with that path.
- Status: the fixed version is installed but not yet tested in the game.

---

## 2026-10-03 — Session 1: analysis, crystal radar, single package with a menu

**Status at the end of the session: the code is written and installed in the game, but has
never been run in the game.** Next step: run it, check it, and send the Ctrl+F9 output.

### 1. Game analysis
- Identified UE 4.27 (version string in the exe) with IoStore paks. `.ucas` contents are
  compressed, so Blueprints can't be inspected statically.
- Parsed the `.utoc` directory index and got the full asset list (12,694 entries).
  The script is saved as `tools/utoc_paths.py`.
- Found that **Blood Crystals are called `GoldCoin` internally**: ~165 separate
  `Blueprint_Pickup_GoldCoin_*` BPs in `Blueprints_Pickups/GoldCoins/`, and the string
  "Blood Crystal — A prized unit of currency." sits next to the `GoldCoin` data.
- The Ctrl mode that shows characters is `ARViewHud_BP` / `ARViewHUD_Icon_BP` (AR view).

### 2. Analysis of the third-party ParadiseKiller-AirControl-Mod
- It is UE4SS 3.x (`dwmapi.dll` proxy) plus a Lua script `AirControlMod/Scripts/main.lua`.
  The script sets `CharacterMovement.AirControl = 0.5` (by default the game has no air
  control), toggles with Ctrl+J, and re-applies on `PlayerController:ClientRestart`.
- The UE4SS bundle contained clutter: configs for other games, templates and demo mods. The
  built-in `Keybinds` mod also bound ObjectDumper to Ctrl+J.

### 3. Blood Crystal radar (first version, separate BloodCrystalRadar mod)
- User request: when Ctrl is pressed, show where crystals are, compass-style, alongside the
  characters.
- Decisions:
  - search: `FindAllOf("Blueprint_Pickup_Parent_C")` filtered by the `GoldCoin` class name;
    if nothing is found, fall back to scanning every `Actor`;
  - activation: Ctrl held (`IsInputKeyDown` LeftControl/RightControl), plus an "always show"
    mode on Ctrl+B;
  - drawing: `DrawDebug`/`PrintString` don't work in shipping and `UUserWidget` is abstract,
    so the markers (an Image with the crystal icon + a TextBlock with the distance) are put
    into the CanvasPanel of a game HUD widget that is already open;
  - crystals on screen get a marker in place; off-screen ones get a `< > ^ v` arrow at the
    screen edge. The nearest crystal is gold, and the 12 nearest are shown;
  - a collected crystal was assumed to be destroyed or `bHidden` (an assumption).

### 4. Single PKMods package (replaced AirControlMod and BloodCrystalRadar)
- User request: all mods in one folder that can be copied to a new PC, and a menu to turn
  each mod off separately.
- Done:
  - `Win64\` in the repository is an exact mirror of the game folder, with a minimal UE4SS
    (dlls, ini, shared, Keybinds) and a single `PKMods` mod;
  - `PKMods` consists of a framework (`main.lua` + `core\`) and features (`features\`). Air
    Control was rewritten as a feature: turning it off restores the original values,
    strength 0.35/0.5/0.75/1.0 is selectable in the menu, and the value is re-applied every
    2 s;
  - **F1** menu (key configurable via `menu.key` in settings.txt); items are switched with
    the number keys 1–9, and a toast appears on every switch;
  - settings are stored in `Win64\Mods\PKMods\settings.txt` (in .gitignore, not overwritten
    on install);
  - `install.ps1` removes old installs and copies the package. The package is installed in
    the game;
  - ObjectDumper in `Keybinds` moved to Ctrl+Num5.
- The separate BloodCrystalRadar folder was deleted (its code moved to
  `features\crystal_radar.lua`).

### Unverified assumptions (check on the first run)
1. `FindAllOf` returns subclass instances, and crystals derive from
   `Blueprint_Pickup_Parent_C`. If not, the slow fallback scan kicks in.
2. How the game removes collected crystals: destroys the actor, sets `bHidden`, or uses its
   own flag. If they stay on the radar, look for the flag in the property dump (Ctrl+F9).
3. Whether a suitable HUD host with a `CanvasPanel` root exists. Ctrl+F9 lists the widgets in
   the viewport.
4. Whether the `GoldCoin` icon loads via `LoadAsset`. If not, markers fall back to text (`*`).
5. Whether the game already uses F1, and whether the number keys 1–9 interfere.
6. Whether the island streams in parts (then only crystals in loaded areas are visible).
7. The Ctrl AR mode may be a toggle rather than hold. In that case, tie the radar to the
   visibility of `ARViewHud_BP` (Ctrl+F9 shows its functions and properties).

### Ideas for later
- Show other collectibles on the radar too (music, relics, Starlight skins, Whisky).
- Tie the radar to the game's AR view state instead of the key.
- Menu pages once there are more than 9 items.
- A UE4SS build without the console window for a "clean" release.
