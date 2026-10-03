# PKMods development log

New entries go on top. Each entry records what was done, why, and what is still unverified or
open.

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
