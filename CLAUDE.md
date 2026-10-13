# CLAUDE.md — DBZ Supersonic Warriors 2 → Godot port (read this first, every session)

**What this is.** A faithful port of *Dragon Ball Z: Supersonic Warriors 2* (Nintendo DS, the user's European dump,
code ADBP) to **Godot 4.7.2**: the ARM9 program (3,316 functions) and the ARM7 sound driver were decompiled with Ghidra
and machine-translated to GDScript, running on an emulated DS (hardware at register level); Godot draws the screens
from emulated VRAM/registers. Complete and playable; current work: polish, exactness, QoL (single-screen next).

## Rules (from the user — do not break)
1. Work only inside this folder (`SupersonicMain`). Anything that must happen elsewhere is written down in
   `WORK_OUTSIDE_FOLDER.txt`.
2. Use only the user's own dump (`finished/*.nds`; the user removed `baseroms/` and `100Save/` in part 21); never
   modify it; never download ROMs, BIOS or keys.
3. **Nothing from the ROM ships with the game or goes into git**: no ROM, no extracted/converted assets. The exported
   exe looks for the player's ROM in its own folder (any file name; validated by header CRC + code MD5,
   `scripts/core/assets.gd`). The only data built into the exe is the 100% save (player progress,
   `GodotGame/new-game-project/data/save100.sav`).
4. Accuracy is checked against the original, preferably frame-exact against melonDS (`docs/TESTING.md`). Look at the
   images before claiming anything is fixed. Fix root causes, not symptoms.
5. `scripts/gen/ds_game.gd` and `ds_game7.gd` are GENERATED — never hand-edit; fix the translator
   (`decomp/tools/ghidra2gd.py`, `decomp/tools/transpile/`), the Ghidra script or the runtime (`scripts/core/`).
6. HLE only at the CPU/ARM7 boundary (`decomp/tools/transpile/hle_list.py`). Exception: exact native fast paths for
   memory-pure SDK functions (C++ in `native/src`, translated body kept as fallback, lockstep identical).
7. The GDScript and C++ versions of the 3D geometry engine (`scripts/render/ds_gx.gd`, `native/src/ds_gx_native.cpp`)
   must stay output-identical (`tools/cmp_gx.gd`).
8. After translator/runtime changes rerun the lockstep tests; after renderer changes rerun the capture checks.
9. Every decoded fact goes into `decomp/DATA_NOTES.md` with confidence H/M/L and its ARM9 address.
10. Before each user task: rewrite the user's prompt into a more detailed brief, send it, then work from it.
    Keep `HANDOFF.md` (the status doc) and this file current when done; deliver the build to `finished/`.

## Folder map
| Path | What |
|---|---|
| `finished/` | exported game: `DBZ_SSW2_Port.exe` + `libdsnative.windows.x86_64.dll` + README.txt / BUGFIXES.txt / BOSS_CHARACTERS.txt (+ the user's ROM, never distributed; `linux/` older Linux export) |
| `GodotGame/new-game-project/` | the Godot project (below); `data/save100.sav` = the completed save built into the exe |
| `decomp/tools/` | ROM extraction, converters, Ghidra script, translator (`ghidra2gd.py`, `transpile/`), lockstep compare |
| `decomp/DATA_NOTES.md` (+ `DATA_NOTES_INDEX.md`), `decomp/notes/` | knowledge base (never read DATA_NOTES whole: use the index + grep) |
| `decomp/extract/` | generated: extracted ROM files + translation work dir (git-ignored) |
| `tools/` | Windows: Godot 4.7.2, Python 3.14.8, melonDS 1.1 (+ config). `test/ssw2.py` portable test harness (Windows + Linux), `melonds-headless/` frame-exact melonDS core (Linux), `linux/` Linux test scripts, `windows/` GPU capture + pace tests |
| `local/` | git-ignored: test runs, baselines (`baselines/<tag>/`), menu-preview background `prevbg.png` |
| `.claude/` | Claude Code: `settings.json` (permissions; generated files protected), `commands/` (/brief /offcheck /deliver /handoff), `agents/ssw2-helper.md` |
| `reference/` | melonDS reference shots; `reference/states/` savestates (git-ignored, ROM-derived) |
| `docs/` | see "Where to read next"; `PLAYER_README.txt` / `BUGFIXES.txt` / `BOSS_CHARACTERS.txt` = sources of the finished/ texts |

Godot project: `scripts/gen/` translated game · `scripts/core/` DS runtime · `scripts/render/` 2D engines
(`ds_display.gd`), 3D (`ds_gx.gd`, `ds_render3d.gd`, `shaders/ds_poly.gdshader`), `ds_presenter.gd` ·
`scripts/game/game_ds.gd` main scene (pacing, input, save, flags) · `scripts/qol/` port additions · `native/` C++
GDExtension (geometry, mixer, SDK memory functions, FS lookup) → `bin/` · `tools/*.gd` debug tools · `assets_qol/` the
user's art. Legacy, unused: `scenes/battle/`, `scripts/{battle,ui,audio,pilot}/`.

## Run, test, deliver (Claude Code on the user's Windows PC, from part 35 on — details `docs/CLAUDE_CODE.md`)
- `py` = `tools\Python3.14.8\python.exe`. One harness for routine work: `py tools\test\ssw2.py env | parse FILE |
  import | run NAME --battle --every N --from F --to T --inputs ... FLAGS | offcheck | baseline | pngdiff A B | export`
  (output in `local/`, git-ignored). Slash commands: `/brief`, `/offcheck`, `/deliver`, `/handoff`; helper agent
  brief: `.claude/agents/ssw2-helper.md`.
- Play / edit: `tools\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --path GodotGame\new-game-project`
  (ROM from `finished/`). ROM tools: `py decomp\tools\build_all.py` (→ decomp/extract).
- Flags go after `--` (`Game.args`): full list `docs/DEBUG_FLAGS.md`. Keys: arrows, X = A, Z = B, S = X, C = Y, A = L,
  D = R, Enter = Start, Backspace = Select, mouse = touch (lower screen), F3 FPS, F11 fullscreen (remappable: CONTROLS).
- Tests: `docs/TESTING.md`. **Off-identity after every change**: `py tools\test\ssw2.py offcheck` must PASS
  (battle 21/21 PNGs + 1382 `CHT f` lines, intro 221/221). PNG baselines are per machine: the first session records
  the PC's own (`baseline`, on the delivered state, before any change); CHT lines are machine-independent.
- **Delivery**: `py tools\test\ssw2.py export` (= `--export-release "Windows Desktop"` → `finished/DBZ_SSW2_Port.exe`,
  copies `docs/PLAYER_README.txt` → `finished/README.txt`, `docs/BUGFIXES.txt` → `finished/BUGFIXES.txt`; export
  templates 4.7.2 needed; close running games first). `docs/BOSS_CHARACTERS.txt` → `finished/` only if changed.
  Never rebuild the native library (`native/build.sh`, `tools/linux/export.sh`) while a game runs. Then commit (git:
  check `git status` shows nothing ROM-derived).
- Linux (cloud / WSL): `tools/linux/env.sh` (GODOT, ROM, SAV, Xvfb), setup `docs/TOOLING.md`; `ssw2.py` works there too.

## Gotchas
- Godot `--script` tools run before autoloads exist in `_init`; do the work in `_process` (see `parsecheck.gd`).
  Scripts that use classes referring to the `Game` autoload (QoL classes) do not even compile under `--script`: run
  them as a scene (`tools/qol_preview.tscn`).
- Parse-check: `godot --headless --path GodotGame/new-game-project --script res://parsecheck.gd -- res://a.gd ...`.
- Parts 1-34 were tested in a cloud sandbox without GPU (Mesa llvmpipe); now runs use the PC's GPU, so pictures can
  differ slightly from the llvmpipe baselines (record the PC's own; GPU-only bugs: docs/TESTING.md 5).
- Exported builds resolve relative paths against the exe folder; settings.cfg / .sav / perflog.txt live next to the exe.
- Game speed must be 59.83 frames/s on every PC (fixed-timestep accumulator in `game_ds.gd` `_process`; never clamp it
  below zero). Check: `--headless -- pacelog fakehz=N maxfps=N quit_at=1300` (TESTING 8) / `tools/windows/pace_test.bat`.
- QoL code never edits generated code: override in `QoLGame`, off = `super` only; call game code from the main thread
  only via `QoLController.on_game_thread`.
- `lanbattle=1` test runs need `lanteams=… lanbstage=HEX` (else a correct DESYNC at L277) and a fresh `qolcfg=` each.
- Keep at most 2 game instances running at once (memory); kill only the processes you started.

## Where to read next
| Need | Read |
|---|---|
| State, open issues, next steps | `HANDOFF.md` (history: `docs/HISTORY.md`) |
| Claude Code setup, harness, baselines, philosophy | `docs/CLAUDE_CODE.md` |
| Which file / class / function implements a QoL feature | `docs/QOL_ARCHITECTURE.md` |
| Debug / test flags | `docs/DEBUG_FLAGS.md` |
| How to verify anything (procedures, baselines) | `docs/TESTING.md` |
| Toolchain setup, export, performance / Proton analysis | `docs/TOOLING.md` |
| Translator, runtime, lockstep | `decomp/notes/transpiler.md` |
| A decoded fact / RAM address | `decomp/DATA_NOTES_INDEX.md` → grep / read that section of `decomp/DATA_NOTES.md` |
| Local MP / LAN design + facts | `docs/MULTIPLAYER_DESIGN.md`, `docs/LAN_DESIGN.md` (read their top summary first) |
| All-Star mode (parts 34-35) | `docs/ALLSTAR_DESIGN.md` (2a = status + QoLAllStar API) |
| Player-facing texts | `docs/PLAYER_README.txt`, `docs/BUGFIXES.txt`, `docs/BOSS_CHARACTERS.txt` |
| Original task | `docs/PROJECT_BRIEF.md` (historical: paths there predate part 21) |
