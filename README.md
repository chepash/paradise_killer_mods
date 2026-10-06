# PKMods — a mod pack for Paradise Killer

Quality-of-life mods for **Paradise Killer** (PC / Steam, Unreal Engine 4 version), built on
[UE4SS](https://github.com/UE4SS-RE/RE-UE4SS). Everything comes as one drop-in package with an
in-game menu to switch each mod on or off.

| Mod | What it does |
|---|---|
| **Air Control** | Steer while in the air (the game locks it). Strength 0.35 / 0.5 / 0.75 / 1.0, default 1.0. |
| **Fly Mode** | Unreal's built-in flying movement: no gravity, W/S fly where the camera looks, A/D strafe, Space up, Left Alt down; collision stays on. Speed 10 / 15 / 20 / 30 m/s (default 20); Space / Alt climb at half speed. Off by default. |
| **Radar** | While on: marks items still lying in the loaded world, with icon and distance; off-screen items get an arrow at the screen edge; the nearest item of each kind is gold. Menu filters choose what it shows: **Blood Crystals**, **Crests** (crests and farm valves, the puzzle items), **Relics**, **Islands**, **Shrine Carvings**, **Music**, **Whisky**, **Transmissions**, **Ghost Items**, **Starlight Skins**, **Key Items**, **Shinji** (the Fox Messenger NPC), **Blood Shrines** (the 17 shrines to donate blood at), **Vending Machines**. Off by default. |

## Install

1. Download `PKMods-<version>.zip` from the Releases page.
2. Find the game folder: in Steam, right-click Paradise Killer → Manage → Browse local files.
3. Extract the zip into `ParadiseKiller\Binaries\Win64\` (next to
   `ParadiseKiller-Win64-Shipping.exe`). You should get `dwmapi.dll` next to the exe and a
   `ue4ss` folder.
4. Start the game. A UE4SS console window opens alongside it; that's expected.

Saves aren't touched: the mods only change things in memory while the game runs, so your
saves (and Steam Cloud sync) stay as they are.

**Uninstall:** delete `dwmapi.dll` and the `ue4ss` folder from `Binaries\Win64\`.

## Keys

| Key | Action |
|---|---|
| F1 | Mod menu; number keys 1–9 switch items, 0 turns the page |
| Ctrl+J | Air Control on/off |
| Ctrl+B | Radar on/off (filters in the menu) |
| Ctrl+F | Fly Mode on/off; while flying: Space up, Left Alt down |
| Ctrl+= / Ctrl+- | Radar markers more visible / more transparent (10–100 %; numpad +/- too) |
| Ctrl+F9 | Diagnostics → `ue4ss\Mods\PKMods\pkmods.log` |

The menu lists these keys too. Choices are saved to `ue4ss\Mods\PKMods\settings.txt`; the
menu key can be changed there (`menu.key = F2`).

## Build from source

Requirements: Windows, PowerShell 5.1+, internet access for the first build.

```powershell
.\build.ps1      # -> dist\Win64\ and dist\PKMods-<version>.zip
.\install.ps1    # build + copy into the game (-GameDir "<path to Paradise Killer>")
```

`build.ps1` downloads a pinned UE4SS release (checked against a SHA-256 hash, cached in
`.cache\`), keeps only the files the pack needs, applies two small config changes, and lays
the contents of `package\` on top. Only `package\` and the scripts are in git.

## Layout

```
package\ue4ss\Mods\
  mods.txt, mods.json      which UE4SS mods load
  PKMods\Scripts\
    main.lua               feature list, menu, keys, main loop
    core\                  util, settings, ui (widgets on the game HUD), menu, input
    features\              one file per mod
build.ps1, install.ps1, VERSION
tools\                     research helpers (asset list from the .utoc, crash dump summary)
CLAUDE.md, DEVLOG.md       developer notes and development history
```

A new mod is a new file in `features\` plus one line in `FEATURES` in `main.lua`; see
[CLAUDE.md](CLAUDE.md).

## Credits

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) by the UE4SS-RE team (MIT license; its
  `LICENSE` ships in the package).
- Air Control is based on the idea of an earlier community Air Control mod.

Use at your own risk; single-player only.
