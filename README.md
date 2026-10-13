# DBZ Supersonic Warriors 2 — Godot port

**To play:** put your own ROM of the European cartridge (any file name, e.g. `game.nds`) into `finished\` next to
`DBZ_SSW2_Port.exe`, then run the exe. The `finished` folder can be copied to any Windows 10/11 PC; it contains no
game data of its own (only the completed save, so everything is unlocked). Controls: `finished\README.txt`.

## Folder layout
| Folder / file | What it is |
|---|---|
| `finished/` | the built game (exe + native library + README.txt); add your ROM here to play |
| `GodotGame/new-game-project/` | the Godot project (`data/save100.sav` = the completed save built into the exe; `baseroms/` and `100Save/` were removed in part 21) |
| `decomp/` | reverse engineering: tools, translator, notes (`decomp/DATA_NOTES.md`); `decomp/extract/` is generated |
| `reference/` | melonDS reference screenshots and savestates |
| `tools/` | Godot, Python, melonDS (Windows) + headless melonDS and test scripts |
| `docs/` | testing / tooling guides, QoL architecture, debug flags, history, MP / LAN design, player readme |
| `CLAUDE.md` | start here if you are an AI agent (rules, map, commands); `AGENTS.md` points to it |
| `HANDOFF.md` | current state, known issues, next steps (history: `docs/HISTORY.md`) |
| `WORK_OUTSIDE_FOLDER.txt` | everything that happened outside this folder |

## Rebuilding
1. `tools\Python3.14.8\python.exe decomp\tools\build_all.py` (extracts the ROM in `finished\` for the tools; only
   needed for the reverse-engineering tools and the legacy scenes).
2. Open the project in Godot 4.7.2 and press Play, or Project → Export → "Windows Desktop" (export templates
   needed) to rebuild `finished\DBZ_SSW2_Port.exe`.

## Building from a git clone (part 37)
The repository holds the port's code, the translated game program (`scripts/gen/`), the native library binaries,
docs and tools, but **nothing taken from the game**: no ROM, no extracted or converted graphics / sound / text, no
captures (`.gitignore`). Not in git, so bring your own:
| Needed | Where it goes | Notes |
|---|---|---|
| Godot 4.7.2 (Windows, `_console.exe` included) | `tools\Godot_v4.7.2-stable_win64.exe\` (or set `GODOT=`) | official release |
| Godot 4.7.2 export templates | `%APPDATA%\Godot\export_templates\4.7.2.stable\` | editor → Manage Export Templates |
| Python 3.8+ | any (`py`), or `tools\Python3.14.8\` | stdlib only for `tools/test/ssw2.py` |
| the completed save `save100.sav` | `GodotGame\new-game-project\data\save100.sav` (create the `data` folder: a clone has none) | built into the exe; without it the build still works (with a warning) but the exe starts with an empty save |
| your own European ROM (code ADBP) | `finished\` (any `.nds` name) | only to play / test, not to build |

Build: `python tools\test\ssw2.py export` → `finished\DBZ_SSW2_Port.exe` + `libdsnative.windows.x86_64.dll` +
README.txt / BUGFIXES.txt (the native library is prebuilt in `GodotGame/new-game-project/bin/`; rebuilding it is
optional, docs/TOOLING.md). Then put your ROM next to the exe and run it. Verified in part 37: a fresh clone built
this way gives an exe whose standard test battle is frame-identical to the editor (21/21, docs/TESTING.md 28).
