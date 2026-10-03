# PKMods — mods for Paradise Killer

A set of UE4SS Lua mods for Paradise Killer (Steam, Unreal Engine 4 version). The goal is **one
package**: copy the built `dist\Win64\` folder (or the release zip) into the game and every
mod works right away. An in-game menu turns each mod on or off separately.

The git repository holds only our sources (`package\`) and the build scripts. UE4SS is
downloaded by `build.ps1` from a pinned URL with a SHA-256 check, not committed.

The development history and the reasons behind decisions are in [DEVLOG.md](DEVLOG.md). Read
the latest entry before starting work: it has the current status and lists what is still
unverified.

## The game

- Example install path: `D:\games\steamapps\common\Paradise Killer\`.
  Exe: `ParadiseKiller\Binaries\Win64\ParadiseKiller-Win64-Shipping.exe`.
- **Unreal Engine 4.27** (`++UE4+Release-4.27`), shipping build.
  Assets are in IoStore: `Content\Paks\*.pak/.ucas/.utoc`. The container is not encrypted,
  but `.ucas` contents are compressed. Asset names and paths come from
  `python tools/utoc_paths.py` (it parses the `.utoc` directory index). Class properties
  and functions are only available at runtime (UE4SS dumps, Ctrl+F9).
- Internal names:
  - **Blood Crystal = `GoldCoin`.** Every crystal is a separate Blueprint:
    `/Game/Assets/Blueprints/Blueprints_Pickups/GoldCoins/Blueprint_Pickup_GoldCoin_NNN`
    (001–159 plus named ones such as `_SyndicateMural`, `_HQ_CryingGrudge` and
    `_DanchiLightStatue_1`; ~165 in total). The parent class is assumed to be
    `Blueprint_Pickup_Parent_C`.
    Icon: `/Game/Assets/2D_Assets/Textures/Inventory/GoldCoins/GoldCoin`.
    `Blueprint_Pickup_droppedcoins` is a collectible item, **not** a crystal.
    **Picked-up state:** the actor stays in the world. On pickup the game sets
    `bHasBeenRemoved = true` and destroys one of the 2 entries in
    `BlueprintCreatedComponents` (bHidden doesn't change). After a save is loaded,
    collected crystals **are spawned again with `bHasBeenRemoved = false`**, but the
    component is still missing (`BlueprintCreatedComponents` has 1 entry). So "collected"
    = flag set **or** fewer than 2 created components (hypothesis, being verified; the
    component names are logged once per level to `pkmods.log`).
    `K2_GetComponentsByClass` returned nothing on these actors; read
    `BlueprintCreatedComponents` directly. Pickup also creates
    `GoldCoinPickupNotification_BP_C`.
  - Saves: `%LOCALAPPDATA%\ParadiseKiller\Saved\SaveGames\PKSlot_N.sav`, GVAS with an
    **encrypted** `SerializedSaveData` payload, so not readable offline.
  - Native game code exists: `/Script/ParadiseKiller.*` classes (e.g. `PlayerSaveData`).
  - Ctrl AR view (highlights characters): `/Game/UI/Notifications/ARView/ARViewHud_BP`,
    `ARViewHUD_Icon_BP`.
  - Player: `Blueprints_Player/FirstPersonCharacter`, `PlayerController_BP`.

## Repository layout

```
VERSION                        package version, used in the release zip name
build.ps1                      builds dist\Win64\ and dist\PKMods-<version>.zip:
                               1. downloads UE4SS (cached in .cache\, SHA-256 checked)
                               2. extracts only what we ship (dwmapi.dll, UE4SS.dll, LICENSE,
                                  UE4SS-settings.ini, Mods\shared, Mods\Keybinds; no PDB)
                               3. patches: ini EnableHotReloadSystem = 1, Keybinds
                                  ObjectDumper Ctrl+J -> Ctrl+Num4
                               4. lays package\ over it, zips the result
install.ps1                    runs build.ps1 (unless -NoBuild), removes old installs,
                               copies changed files of dist\Win64\ into the game
package\                       OUR files, in the same layout as <game>\...\Binaries\Win64
  ue4ss\Mods\mods.txt, mods.json   PKMods + Keybinds
  ue4ss\Mods\PKMods\Scripts\
    main.lua                   FEATURES list, menu, keys, main loop
    core\util.lua              log, valid, getPC (throttled), className, gameLoop/gameDelay
    core\settings.lua          ue4ss\Mods\PKMods\settings.txt (key = value), created in the game
    core\ui.lua                widgets on the game's HUD, toast
    core\menu.lua              F1 menu, number keys 1–9
    core\input.lua             hotkeys polled on the game thread
    features\air_control.lua
    features\crystal_radar.lua
tools\utoc_paths.py            lists every asset in the game
tools\minidump_summary.py      summarizes a crash_*.dmp (exception, module, stack scan)
dist\, .cache\                 build output / download cache, git-ignored
```

UE4SS in use: `experimental-latest` asset `zDEV-UE4SS_v3.0.1-1152-ge3ba1016.zip`
(changelog "v4.0.0-rc1"), dev build with a console window, MIT license. The tag is rolling:
if the asset changes, the build fails on the hash check; test the new UE4SS in the game
before updating `$UE4SS_URL` / `$UE4SS_SHA256` in `build.ps1`.

## Adding a feature

Create `features\<name>.lua` that returns a table, and add `(require("features.<name>"))` to
`FEATURES` in `main.lua`. **The parentheses are required:** in Lua 5.4 `require` returns two
values, and without parentheses the file path ends up in the table as an extra entry.

```lua
local F = {
  id = "my_feature", name = "My Feature", default = true,
  toggleKey = { key = "X", ctrl = true },                   -- optional; Unreal FKey names
  hotkeys   = { { key = "Y", ctrl = true, fn = fn, desc = "what it does" } },
                                          -- fire only while the feature is on; listed in the menu
  options   = { { label = fn -> string, activate = fn } },  -- menu sub-items
}
function F.onEnable() end   function F.onDisable() end
function F.tick() end       -- ~30 times/s, only while enabled, on the game thread
function F.onRestart() end  -- new level / respawn
function F.diag() end       -- output for Ctrl+F9
return F
```

`main.lua` sets the `F.enabled` flag and saves it to `settings.txt` as `<id>.enabled`.
A feature stores its own settings with `S.get/S.set("<id>.<key>")`.
The menu holds at most 9 items (number keys). It will need pages once it gets crowded.
Every hotkey is shown in the menu: a feature's `toggleKey` next to its item, `hotkeys`
(with `desc`) and global keys (`Menu.addHotkey`) in the HOTKEYS list at the bottom.

## Technical constraints (important)

- **Not available in a shipping build:** `DrawDebug*` and on-screen `PrintString`, so
  everything on screen is drawn with UMG.
- **`UUserWidget` is abstract**, so Lua can't create a widget of its own. Instead,
  `core/ui.lua` puts Image, TextBlock and Border widgets into the root `CanvasPanel` of a
  game widget that is already in the viewport. `IsInViewport` means it covers the full
  screen. Our widgets inherit the host's opacity, so a fully opaque host is preferred
  (preferred classes first: `YMKHUDBP_C`, `HUD_TopCorner_C`, `ARViewHud_BP_C`, then any).
  If none is fully opaque, the most opaque one is used. The UI moves when the host becomes
  translucent or disappears; all `UI.onBuild` builders then rebuild their widgets. Our
  widgets have the `PKM_` prefix, and leftovers are removed only when the host actually
  changes. Widget names must stay unique across Ctrl+R reloads (they carry a per-run
  token): reusing a name in the same outer overwrites the old object in place. Leftovers
  are found with `FindAllOf` by name prefix, not via the host's children.
- UObjects may only be touched on the game thread. Use `U.gameLoop` / `U.gameDelay`, which
  wrap `LoopInGameThreadWithDelay` / `ExecuteInGameThreadWithDelay` (timers that run on the
  game thread). **Don't call `LoopAsync` + `ExecuteInGameThread` at a high rate:** on UE4SS
  3.0.1 that crashed the game (`0xC0000264`, a lock released by a thread that didn't own
  it).
- **All PKMods Lua runs on the game thread only. Don't use `RegisterKeyBind`:** its
  callbacks run on a separate UE4SS thread, and pressing keys quickly corrupted the Lua state
  and crashed the game. Hotkeys are polled every frame with `PlayerController:IsInputKeyDown`
  in `core/input.lua` (`Input.bind(keyName, ctrl, fn)`), using Unreal key names
  (`"F1"`, `"J"`, `"One"`…`"Nine"`).
- `FindAllOf` walks the whole object array, so it must not be called every frame. Throttling:
  the PC lookup and the host check run once per second, the crystal scan every 3 s.
- Screen projection is calculated by hand (camera, FOV, viewport size), without UFunction
  out-params.
- Lua hot reload: Ctrl+R (UE4SS; enabled in UE4SS-settings.ini). Log: `UE4SS.log` in
  `<game>\...\Win64\` or `<game>\...\Win64\ue4ss\`. Crash dumps: `crash_*.dmp` next to the log.

## Testing

Claude can't play the game itself. The loop is: edit `package\` → `install.ps1` (builds and
copies; works while the game runs, since unchanged DLLs are skipped) → the user presses
Ctrl+R in the game or restarts it → the user sends the
UE4SS console output or the Ctrl+F9 result. Claude can also read `UE4SS.log` from the game
folder directly.
