# DBZ Supersonic Warriors 2 — Godot port

> **Disclaimer: this is "AI slop".** Everything in this repository — the decompilation and translation tooling, the
> port's code, the extras, the tests and the docs — was made by AI (Claude, Anthropic), with one exception: the PORT
> button graphic (`GodotGame/new-game-project/assets_qol/port_button.png`) was drawn by the project's owner.

A faithful PC port of *Dragon Ball Z: Supersonic Warriors 2* (Nintendo DS, European cartridge) in Godot 4.7.2.
The game's own ARM9 program and ARM7 sound driver were decompiled and machine-translated to GDScript and run on an
emulated DS at register level; Godot draws both screens from the emulated video hardware. Every mode of the original
is playable and checked frame by frame against melonDS — plus a long list of optional extras.

**You need your own copy of the game.** The port contains no ROM, no graphics, sound or text from the game: it reads
them from your cartridge dump at start-up.

## Play
1. Get the release zip (or build it, below) and unpack it anywhere on a Windows 10/11 PC.
2. Put your own dump of the European cartridge (game code ADBP) next to `DBZ_SSW2_Port.exe`. Any file name works;
   the game checks the contents.
3. Run `DBZ_SSW2_Port.exe`. Everything is unlocked from the start. Controls, settings and every extra are described
   in the `README.txt` next to the exe ([`docs/PLAYER_README.txt`](docs/PLAYER_README.txt)).

Keyboard by default (arrows, X = A, Z = B, S = X, C = Y, A = L, D = R, Enter = Start), gamepads work too, and the
mouse is the touch screen. Steam Deck / Linux: runs under Proton (see the player readme).

## What the port adds (all optional; switched off it plays exactly like the DS)
- **Settings menu in the game's own style** (the PORT tile on MODE SELECT): window size up to full screen, 60-240 fps
  smooth motion, controls remapping for keys and pads, gamepad mouse cursor, volume, jukebox, camera zoom, detailed
  shadows, auto pause, auto skip, damage numbers, input display, hitbox viewer (hit boxes red, hurt boxes blue).
- **New gamemodes** (setting NEW GAMEMODES: the FREE BATTLE tile becomes GAMEMODE): ALL-STAR (beat the whole roster in one long battle), ENDLESS (how long
  can you last?), BOSS RUSH (all 18 boss versions back to back, SSJ Goku last) and TOURNAMENT (an 8-team bracket),
  each with records pages.
- **Local multiplayer and LAN play**: two players on one PC (keyboard + pads) or over the network, deterministic
  lockstep.
- **Over 30 cheats**: infinite health / ki, one-hit KO, boss characters, character and stage shuffles, RANDOMIZER,
  ULTRA INSTINCT parries, Z-VANISH, TIME SKIP, VAMPIRE, BODY CHANGE, GREEN DEMON, BOMB RAIN, HOT POTATO, SMASH
  KNOCKBACK, DRAGON BALL HUNT and more.
- **Weird stuff**: Game Boy palette, CRT TV, mirror mode, bevel emboss, blood, afterimages, rainbow ki, EPIC MODE…
- **Bug fixes** of the original game, listed in [`docs/BUGFIXES.txt`](docs/BUGFIXES.txt).

## Build from source
The repository holds the port's code (`GodotGame/new-game-project/`), the machine-translated game program
(`scripts/gen/`, generated from the ROM's code by `decomp/tools/`), prebuilt native libraries, tools and docs —
**no ROM and nothing extracted or converted from it** (no graphics, sound, text or captures; see `.gitignore`).

| Needed (not in git) | Where it goes | Notes |
|---|---|---|
| Godot 4.7.2 (Windows, `_console.exe` included) | `tools\Godot_v4.7.2-stable_win64.exe\` (or set `GODOT=`) | official release |
| Godot 4.7.2 export templates | `%APPDATA%\Godot\export_templates\4.7.2.stable\` | editor → Manage Export Templates |
| Python 3.8+ | any, or `tools\Python3.14.8\` | stdlib only for `tools/test/ssw2.py` |
| your own European ROM (code ADBP) | `finished\` (any `.nds` name) | to play and test, not to build |

```bash
python tools/test/ssw2.py export
```
builds `finished\DBZ_SSW2_Port.exe` + `libdsnative.windows.x86_64.dll` + README.txt / BUGFIXES.txt (the native
library is prebuilt in `GodotGame/new-game-project/bin/`; rebuilding it is optional, [`docs/TOOLING.md`](docs/TOOLING.md)).
A fresh clone built this way gives an exe whose standard test battle is frame-identical to the editor
([`docs/TESTING.md`](docs/TESTING.md) section 28). `python tools/test/ssw2.py` lists the test harness commands
(scripted runs, captures, the off-identity check, export).

## Repository layout
| Folder / file | What it is |
|---|---|
| `GodotGame/new-game-project/` | the Godot project: `scripts/gen/` translated game, `scripts/core/` DS hardware, `scripts/render/` 2D / 3D engines, `scripts/qol/` everything the port adds, `native/` C++ GDExtension |
| `decomp/` | reverse engineering: ROM tools, Ghidra script, translator, knowledge base (`decomp/DATA_NOTES.md`) |
| `tools/` | test harness (`tools/test/ssw2.py`), headless melonDS reference core, Linux / Windows test scripts |
| `docs/` | player readme, bug fixes, testing / tooling guides, QoL architecture, debug flags, MP / LAN and gamemode design, history (`docs/archive/`: old briefs) |
| `finished/` | (not in git) the built game; add your ROM here to play |
| `HANDOFF.md` | current state, known issues, next steps |
| `CLAUDE.md` / `AGENTS.md` | instructions for AI coding agents working on the project |

## License
The port's own code, tools and docs are under the [MIT License](LICENSE): use, copy, modify and redistribute them for
any purpose, commercial included, as long as the license notice stays with them. Not covered (owned by others):
- the game itself, and `scripts/gen/` (the machine translation of the game's program code) and
  `decomp/notes/charvm_ops_disasm.md`, which are derived from it;
- `tools/melonds-headless/` (melonDS, GPL-3.0; see its README);
- Dragon Ball characters and names, and the Nintendo characters pictured in two cheats' art (`assets_qol/`).
Third-party software inside the exe (Godot Engine, godot-cpp, FreeBIOS tables):
[`docs/THIRD_PARTY_NOTICES.txt`](docs/THIRD_PARTY_NOTICES.txt).

## Legal
Fan project, not affiliated with or endorsed by the game's developer or publishers or the *Dragon Ball* rights
holders (Bird Studio / Shueisha, Toei Animation, Bandai Namco). All trademarks belong to their owners. No ROM or game
assets are distributed; you must own the game to play.
