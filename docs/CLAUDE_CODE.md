# Working on this project with Claude Code (set up in part 35)

Until part 35 the work ran in Claude Cowork: a Linux cloud sandbox did the builds and tests and copied the results
into this folder. From now on Claude Code runs **in this folder on the user's Windows PC**. Everything it needs is
here; nothing from the old sandbox is required. Start every session with `CLAUDE.md`, then `HANDOFF.md`.

## The project's philosophy (unchanged)
- A **faithful port**, not a remake: the original ARM9/ARM7 code is translated and runs on an emulated DS; the port
  must match the original (melonDS) frame for frame. Fix root causes; prove fixes with pictures / RAM dumps.
- **The user's own dump only**, and **nothing from the ROM in git or in the shipped game** (the exe reads the ROM at
  runtime; captures, baselines and extracted files stay in git-ignored folders: `local/`, `decomp/extract/`,
  `reference/**/*.png`, `finished/`).
- **Generated code is never hand-edited** (`scripts/gen/ds_game.gd`, `ds_game7.gd`): fix the translator / runtime.
- **QoL additions never change the original game while they are off** (off = `super` only; the off-identity check
  proves it after every change). New UI works with touch/mouse AND buttons/keyboard, lives on the bottom screen in
  the game's own style, readability and function first; menu page order: settings → Big Changes → cheats → weird.
- **Every decoded fact goes into `decomp/DATA_NOTES.md`** (H/M/L confidence + ARM9 address) and its index.
- **Before each user task: rewrite the request into a detailed brief, show it, work from it** (`/brief`).
- Keep `HANDOFF.md`, `CLAUDE.md` and the docs current; deliver the build to `finished/` (`/deliver`).

## One-time setup on the PC
| What | Where / how |
|---|---|
| Godot 4.7.2 | already in `tools/Godot_v4.7.2-stable_win64.exe/` (use the `_console.exe` from scripts: it prints output) |
| Python 3.14 | already in `tools/Python3.14.8/` (stdlib is enough for `tools/test/ssw2.py`; the Linux tools in `tools/linux/` also want `pip install pillow numpy`) |
| Export templates 4.7.2 | Godot editor → Editor → Manage Export Templates → Download (installs to `%APPDATA%\Godot\export_templates\4.7.2.stable\`, outside the folder: note it in `WORK_OUTSIDE_FOLDER.txt`). Already installed on the user's PC (checked part 36) |
| The ROM | the user's European dump (code ADBP) in `finished/` (any `.nds` name; git-ignored) |
| The 100% save | `GodotGame/new-game-project/data/save100.sav` (present; git-ignored) |
| git | the folder is a git repository from part 35 on (`.gitignore` keeps ROM-derived data out — check `git status` before every commit). On the user's PC `git` is **not on PATH**: the only git is the one bundled with GitHub Desktop, `%LOCALAPPDATA%\GitHubDesktop\app-<version>\resources\app\git\cmd\git.exe` (part 36: `app-3.6.6`; the version folder changes when GitHub Desktop updates). Call it by full path, or install Git for Windows to get `git` on PATH |
| Native library | prebuilt in `GodotGame/new-game-project/bin/` (Windows DLL + Linux .so). Rebuilding needs godot-cpp + CMake + llvm-mingw or MSVC (`docs/TOOLING.md`); only rebuild when a C++ change is needed and no game is running |

## Everyday commands (from the folder root)
`py` below = `tools\Python3.14.8\python.exe` (or any Python 3.8+ on PATH). Note: typing `py` itself on Windows
starts the Python launcher, which runs a system Python (3.12 / 3.13 on the user's PC), not the bundled one; that
also works for `ssw2.py` (stdlib only), but write the full path in scripts.

| Job | Command |
|---|---|
| Show detected paths | `py tools\test\ssw2.py env` |
| Parse-check scripts | `py tools\test\ssw2.py parse GodotGame/new-game-project/scripts/qol/qol_game.gd` |
| Re-import (after adding a class file) | `py tools\test\ssw2.py import` |
| Scripted run with captures | `py tools\test\ssw2.py run NAME --battle --every 10 --from 4300 --to 4800 --inputs "4400:A:4" allstar=1 asdbg` → `local\runs\NAME\p<frame>.png` + `NAME.log` |
| Off-identity check (after every change) | `py tools\test\ssw2.py offcheck` (or `/offcheck`) |
| Record this PC's baselines (once, on the delivered state, before changing anything) | `py tools\test\ssw2.py baseline` |
| Compare two capture folders | `py tools\test\ssw2.py pngdiff DIR_A DIR_B` |
| Export + copy README / BUGFIXES into `finished/` | `py tools\test\ssw2.py export` (close running game instances first) |
| Capture run of the exported exe | `finished\DBZ_SSW2_Port.exe -- quit_at=2400 capture=<ABSOLUTE path>\local\exe_cap cap_every=200 cap_to=2400` (a relative `capture=` lands next to the exe, in `finished\`). It reads the player's `finished\DBZ_SSW2_Port.sav` but (part 37) never writes it unless `save=` is given. To compare with editor runs pass the same flags as `ssw2.py` (`sav=`/`save=` a copy, a fresh `qolcfg=`, `rtc=`): exe and editor are then frame-identical (part 37: 21/21 battle PNGs) |
| Play / edit in the editor | `tools\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --path GodotGame\new-game-project` |

Debug flags go after `--` on a game run: full list `docs/DEBUG_FLAGS.md`. Test procedures per feature:
`docs/TESTING.md` (its `tools/linux/*.sh` scripts are the Linux versions; `ssw2.py` covers the routine ones on Windows).

### Baselines (important)
`local/baselines/<tag>/` holds what the off-identity check compares against:
- `battle_cht.txt` — the game-state lines (`CHT f…`) of the standard battle run up to frame 5300. These are the same on
  every machine (deterministic emulation): the strongest check.
- `battle/` (21 PNGs) and `intro/` (221 PNGs) — pictures; they depend on the graphics driver. The part-35 copies are
  tagged `linux-llvmpipe` (the cloud's software renderer); on the PC the tag is `windows`. **First Claude Code
  session: run `py tools\test\ssw2.py baseline` before any change** (the delivered part-35 state passed the check in
  the cloud), then every later `offcheck` compares against the PC's own pictures. The CHT lines are checked against
  the PC's file, or the llvmpipe one when the PC has none.
- Never re-record baselines to make a failing check pass: re-record only on a state that is known to be right.
- `local/baselines/windows/` was recorded in part 36 on the user's RTX 4070 laptop (CHT lines identical to the
  llvmpipe file). GPU vs llvmpipe, for reference: battle 0/21 PNGs identical (0.4-10 k px each, all in the 3D floor
  of the top screen, almost all < 8 colour levels in the 5 frames checked; bottom screen identical), intro 215/221
  identical (6 frames differ by 0.2-4.6 k px; the 2 checked by ≤ 5 levels). So never compare PNGs across machines; use the CHT lines for that.
- Every game log ends with `ERROR: 1 RID allocations ... leaked at exit` / `resources still in use at exit` (and
  sometimes `WARNING: ... ObjectDB instances were leaked`): Godot shutdown noise, harmless; `ssw2.py` only reports
  `SCRIPT ERROR` / `Parse Error` / `game stopped`.

## Working style that worked (parts 1-35)
- Rewrite the request into a brief first; make a task list; finish with verification (captures you looked at +
  `offcheck`).
- Large features: write a design doc first (`docs/*_DESIGN.md`: facts per question with addresses, then phases), then
  implement phase by phase; helper agents (`.claude/agents/ssw2-helper.md`) get a precise brief each and work on
  separate files / sections. At most 2 game instances at a time (memory).
- New code lives in its own `# ---- <NAME> (part N)` section of `qol_game.gd` / `qol_controller.gd` or its own
  `scripts/qol/qol_*.gd` class, with one-line hooks elsewhere (map: `docs/QOL_ARCHITECTURE.md`).
- Research the game's own code first (`grep -n "func f_0201cbbc" scripts/gen/ds_game.gd`, DATA_NOTES_INDEX) and reuse
  its assets / functions (fonts, plates, sound effects) so additions look like the game.
- Player-visible changes go into `docs/PLAYER_README.txt` / `docs/BUGFIXES.txt` (copied into `finished/`).

## What lived in the cloud sandbox and where it is now
| Cloud (Cowork) | Now |
|---|---|
| `/tmp/ssw2/env16.sh`, `off23.sh`, `btnrun.sh` | `tools/test/ssw2.py` (`env`, `offcheck`, `run --battle`); Linux: `tools/linux/env.sh`, `cap.sh` |
| `/tmp/ssw2/btn`, `btn.log`, `intro/` (baselines) | `local/baselines/linux-llvmpipe/` (git-ignored) |
| `/tmp/ssw2/prevbg.png` (menu preview background) | `local/prevbg.png` (git-ignored; `tools/qol_preview.tscn bg=local/prevbg.png`) |
| `/tmp/ssw2/agent_common.md` (helper brief) | `.claude/agents/ssw2-helper.md` |
| delivery by split / commit / join | not needed: `ssw2.py export` writes `finished/` directly |
| evidence folders `/tmp/ssw2/as34`, `as35…` | not kept (ROM-derived pictures); the facts are in DATA_NOTES and the design docs |
