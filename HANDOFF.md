# HANDOFF — state of the port

_Last updated: 2026-10-13 (part 36 — first Claude Code sessions on the user's PC: sanity check, then the GREEN DEMON
cheat; part 35 was the last Cowork part: `docs/CLAUDE_CODE.md`)._ Start with `CLAUDE.md` (rules, map, commands).
Per-part history: `docs/HISTORY.md`.

## Current state
The whole game runs from the user's ROM: power-on → intro → title → every menu → all modes (Story 14/14 maps,
Z-Battle series, Maximum, Free Battle, Practice, Data File, Options, VS host screen) → battles on every stage, with the
original sound driver. The user plays it on Windows (RTX 4070 laptop) from `finished/` ("almost perfect visually and
plays very well") and on a Steam Deck under Proton. The exported folder is portable and contains no game data (the exe
finds the player's ROM in its own folder under any name). On top: the QoL layer behind Mode Select's centre (PORT) tile —
12 menu pages (settings 1-3, BIG CHANGES = MULTIPLAYER + PERFORMANCE, cheats 5-9, WEIRD STUFF 10-12), LOCAL MULTIPLAYER
(parts 27-29), LAN MULTIPLAYER (parts 30-32, lockstep), PERFORMANCE MODE (part 32). Map of all of it:
`docs/QOL_ARCHITECTURE.md`.

## How it works (details: decomp/notes/transpiler.md, decomp/DATA_NOTES.md via DATA_NOTES_INDEX.md)
ARM9 program (3,316 functions incl. NitroSDK) → Ghidra decompiler output → `ghidra2gd.py` → GDScript class `DSGame`
(`scripts/gen/ds_game.gd`), running on `DSCoreBase` (flat memory, IO, synthetic stack growing upward, fast paths) +
`DSHardware` (VRAM banks, DMA, IPC/FIFO, card, IRQs, DIV/SQRT, timers) + `DSMachine` (scanline model, DS threads as
Godot threads with a baton). The ARM7 sound driver is translated the same way (`ds_game7.gd`) on register-level sound
hardware (`ds_sound.gd`). Drawing: `ds_display.gd` (both 2D engines in shaders, DS blending/brightness, 6-bit colour),
`ds_gx.gd` (geometry engine: matrices, lighting, clipping, culling, DS coverage) → `ds_render3d.gd` +
`shaders/ds_poly.gdshader` (textures decoded from emulated VRAM). QoL: `QoLGame extends DSGame` overrides translated
functions (off = `super`), `QoLController` + `QoLMenu` etc. (`docs/QOL_ARCHITECTURE.md`).

## Verified (with proof — methods in docs/TESTING.md; parts 11-16 evidence in docs/HISTORY.md)
| Area | Proof |
|---|---|
| Battle logic frame-exact | lockstep from a battle snapshot: RAM identical except known sound-stream bytes |
| Boot → intro → title | 163/221 sampled frames pixel-identical with melonDS, rest within a few hundred px (3D edge rules) |
| Menus, Story, Z-Battle, Maximum, Free Battle | side-by-side captures vs melonDS; scripted input runs to battle |
| Stages | `stagecmp.sh` per stage (Korin median 26.4 k px, mostly fighter animation phase) |
| Scrolling menu bars | `barcheck.py`: 0 misplaced pixels over 122 frames on llvmpipe and on the user's RTX 4070 |
| Sound | intro music correlates 0.96–0.99 with the game's stream data; SFX envelopes frame-exact |
| Portable build | empty folder + ROM under another name boots and saves; no ROM → on-screen message; US ROM rejected |
| Windows build on the user's PC | boots, plays, keyboard + mouse touch, F11 fullscreen |
| Game speed on any PC | `pace_test.bat` on the user's 165 Hz laptop: 59.7–60.2 game frames/s at default, V-Sync off uncapped (700–3,000 fps), simulated 60/144/240 Hz; headless 30–240 Hz all ≈59.8 |
| QoL off-identity (every part) | all features off: intro 221/221 identical, off23/btn battle 21/21 PNGs + 1382 `CHT f` lines identical, headless pacing 59.8 (TESTING 18-26) |
| QoL features (parts 11-29) | per-part scripts + captures, TESTING sections 9-24 |
| LAN (parts 30-32) | two instances (also Windows exe under Wine ↔ Linux export): battle-start sync bit-identical across different histories / RTC / zoom, `lanhash` identical, disconnect / rejoin matrix, 10 000-frame battle (TESTING 25, LAN_DESIGN 9) |
| PERFORMANCE MODE (part 32) | captures + real-time `CHT f` lines identical on / off; LAN hashes identical with it on one side; Deck-like load 38.9 → 43.5 fps (TOOLING part 32) |

## Known differences / open issues
- Sound capture unit not emulated; mixing without interpolation (melonDS default too).
- No lag frames (the original drops frames while loading); timers are not cycle-accurate; random-looking effects
  seeded from timers (TV-noise intro scene) differ.
- 3D: the DS interpolates attributes per span, the GPU per triangle → a few texels differ on scaled/rotated quads;
  translucent-over-translucent blending and DS edge rules for diagonal edges (≈1–2 k px/frame in the intro's
  scaled-portrait scene).
- Screen changes that load ~200 files hitch (90–210 ms on the cloud VM; 250-690 ms game-thread spikes in the Deck perflog).
- Smooth motion (FPS > 60) moves things between their DS positions; animation frames, fades and palette effects
  still change at the game's 60 per second, and in-between frames show the last game frame ~½–1 frame late.
- The original's wireless VS needs a second DS: only its host screen is reachable (the port's LAN mode replaces it).
- Card DMA vs VBlank (part 24 analysis): a DMA card read during a mid-battle swap hangs the battle VBlank uploads, as
  it would on a DS (repeat DMA3 stays armed until the card IRQ, which the VBlank wait blocks); not a port timing bug.
  The shuffle cheats skip those uploads while they load (keep `_shuf_loading` / `_stg_busy`); repro `noloadskip dmaread`.
- RTC uses the host clock (frozen in captures); touch uses the firmware calibration.
- Local MP: Shenron freeze ops only freeze the global-slot assist; game result screens skipped between rounds; two real
  gamepads untested. LAN: not yet tested on two real PCs / Wi-Fi / Steam Deck; the user's pause lag not reproduced.
- `perfhalf` (30-fps cadence) built but off by default (gave fewer fps, docs/TOOLING.md part 32).
- Seen, not fixed: a huge Z-Battle course score with many cheats (game formula; cheat scores are never ranked).

## Next steps (in order)
1. User feedback on the part-32 build: PERFORMANCE MODE on the Deck (ask for `perflog.txt` from a battle); LAN on two
   real PCs / Wi-Fi / Deck (`-- lanpace pingdbg` for the pause lag). Still unconfirmed from earlier builds: weird
   effects through the presenter on their GPU, FPS at MAX, zoom in real play, a real gamepad in CONTROLS, shuffle hitch,
   auto pause, taskbar icon.
2. QoL: single-screen layout (flag `single_screen` exists in `DSDisplay`; needs touch remapping + a toggle key).
3. Screen-change hitches: native fast path for FS_ReadFile / decompression on the ROM archive (FSi_SendCommand
   0x020AE998, ~7 commands per file). Other native ideas (not built): packed GX command log, scanline loop in C++.
   Rebuilding the native library breaks running games — only when no game runs.
4. Z-Battle course end / Maximum end / Dragon Balls screens: play through (or `poke=` the progress) and compare
   with melonDS.
5. 3D exactness: per-span attribute interpolation (pass the polygon's vertices/planes to the shader).
6. Fill the three EMPTY Gamemode slots when the user asks (the menu, routing and session classes are reusable).

## All-Star (parts 34-35) — DONE
NEW GAMEMODES setting, GAMEMODE tile, 4-slot Gamemode menu ("GAMEMODE SELECT"), All-Star team select + routing,
26-enemy run in story order (qol_allstar*.gd; QoLGame sections ALLSTAR MENU / BATTLE / STAGE / RECORDS), no CPU tag /
Team Arts, MM:SS clock + n/26, three hearts, music rotation, records file. Part 35: life bars repainted from HP for
members healed / revived on the bench and for every incoming enemy (`_asb_bar_paint`, override `f_0201cbbc`;
DATA_NOTES "part 35 findings (All-Star life bars)"); records page redesigned as the game's results screen
(QoLAllStarRecords, all lettering cut from the game's own art at runtime; preview `tools/qol_preview.tscn -- asrec`);
space sky = procedural DS-style gradient + Milky Way + coloured twinkling stars (QoLAllStarStage, 386 BG3 tiles,
palette 32-188). Design + status: docs/ALLSTAR_DESIGN.md 2a.
Open: hourglass glass shows the sky (translucent); ≤1-frame silence at a music switch; a track ending in pause switches
on resume; support names 26-36 partly guessed (M); records rows 28 px apart (game 32) to fit the Character Select
plate; a few records letters (d H w ! -) assembled from the font's strokes; no full QA of every mode with NEW
GAMEMODES on beyond Maximum / Practice / Z-Battle select / off-identity.

## Part 35: moved to Claude Code
Everything the cloud sandbox held is now in the folder: `tools/test/ssw2.py` (portable harness: run / offcheck /
baseline / export), `local/baselines/linux-llvmpipe/` (git-ignored), `.claude/` (settings, /brief /offcheck /deliver
/handoff, helper agent), `docs/CLAUDE_CODE.md` (setup, philosophy, commands). First Claude Code session: install the
4.7.2 export templates if missing, run `py tools\test\ssw2.py baseline` on the delivered state (records the PC's own
PNG baselines) and `offcheck` once to confirm; the folder is a git repository (initial commit = part 35).

## Part 36: first Claude Code session (2026-10-13) — sanity check + test build, no game code changed
- Environment OK: Godot 4.7.2, ROM in `finished\`, `save100.sav`, export templates already installed, import clean,
  all 33 `scripts/qol/*.gd` + `game_ds.gd` parse OK. `git` is not on PATH (GitHub Desktop's bundled git is used,
  `docs/CLAUDE_CODE.md` setup).
- **Baselines recorded** on the RTX 4070 laptop: `local/baselines/windows/` (battle 21 PNGs + 1382 CHT lines, intro 221;
  the CHT lines are identical to the cloud's `linux-llvmpipe` file). **offcheck: PASS** (21/21, 1382, 221/221).
  GPU vs llvmpipe PNGs: battle 0/21 identical (3D floor, mostly < 8 levels), intro 215/221 (numbers in CLAUDE_CODE.md).
- All-Star smoke (`allstar=1 asdbg cheats=one_hit_ko`, A every 10 frames 4200-5600): 5 KOs (1/26 → 5/26 at 00:18),
  5 swaps, 11 "life bar … repainted" lines; every incoming enemy bar full (yellow slot 0 / lavender slot 1; slot 2 =
  green not reached in this window); space sky shown.
- **Export OK** (`ssw2.py export`, code 0); the new `finished\DBZ_SSW2_Port.exe` boots intro → title by frame 2400, its
  intro captures pixel-identical to the editor baseline. Doc fixes: git path, `py` launcher, exe capture runs rewrite
  the save's time stamps (CLAUDE_CODE.md, DEBUG_FLAGS.md `capture=`), harmless "leaked at exit" log lines.
- Open question for the user: `docs/mp_mockup.png` (the user's MP mockup) is built from the game's portraits / plates,
  i.e. ROM-derived pixels in git (rule 3); proposed: untrack + ignore it (still in the part-35 commit).

## Part 36 (cont.): GREEN DEMON cheat — DONE
New cheat page 9 **CHALLENGES** (weird pages moved to 10-12; header help text updated) with **GREEN DEMON**: a 1-UP
(the user's art: assets_qol/greendemon_src.png → hand-made 16x16 greendemon.png, ¼ of base Goku's height, dark
outline, no fog) spawns off the picture, creeps at 0.9 px / frame toward P1's active fighter (catch-up up to 3.0 when
a knock-back leaves it > 300 px behind), KOs it on touch (game explosion + SE 0x2B, through guard / INFINITE HEALTH;
the game's own KO / tag-in follows), warps ≥ 320 px away and rests 120 frames; ignores the CPU side. Local / LAN MP:
hunts both, random target, switch every 10 s, lock within 24 px (lost beyond 40 → random target). Code:
`scripts/qol/qol_green_demon.gd` + QoLGame `# ---- GREEN DEMON (part 36)`; BOMB RAIN's texture block is now the shared
`scripts/qol/qol_texblock.gd`. Verified (TESTING 27): SP / team / All-Star / fleeing / stage shuffle / local MP
switching + lock + unlock / LAN lockstep identical (`tools/windows/lan_pair.ps1`) / keys + taps menu / sound audible /
BOMB RAIN identical / offcheck PASS. Facts: DATA_NOTES "part 36 findings (green demon)".
(The "editor vs exe battle divergence" noted here was solved in part 37: a test-harness settings leak, see below.)
Open: tuning by feel on real play (speed 0.9, catch-up, 2-s rest, lock 24/40 px are constants at the top of
qol_green_demon.gd; `gdspeed=` for tests); the 1-UP is drawn behind the battle HUD (like the fighters' feet) when it is
low on the screen; the preview's built-in-font fallback errors when the ROM is not found (`qol_font.gd:299`, old).

## Part 37: first-session fixes, editor-vs-exe "divergence", private GitHub repo (2026-10-13)
- `docs/mp_mockup.png` (cut from the game's art) untracked, git-ignored and purged from the whole git history (file
  kept locally); `.gitignore` also ignores `*.nds *.srl *.sav *.dsv *.ml? *.wav ram_*.bin` anywhere.
- Capture runs never write a save unless `save=` is given (`game_ds.gd _write_save`; V: the first session's exe
  capture run now leaves finished\DBZ_SSW2_Port.sav byte-identical).
- **Editor vs exe "divergence" = settings leak, not emulation.** RAM dumps of both builds (same args): identical to
  f4090, first difference f4100 at 0x02100A00 = a texture-manager block {0x5F000, 0x1000, key 0x7B0B0B26} = BOMB RAIN's
  block, and the f3950 picture difference (RAM identical) = AFTERIMAGES. Cause: `QoLSettings.load_file` in an
  exported build fell back to `user://settings.cfg` (%APPDATA%\DBZSSW2Port\, the read-only-folder copy) whenever the
  settings file could not be loaded — also for a test's fresh `qolcfg=` file — so exe test runs played with the
  player's own cheats / weird options. Fix: the user:// fallback (load and save) only without `qolcfg=`; normal play
  unchanged. V: exe standard battle run 21/21 PNGs identical to the editor baseline; offcheck PASS.
- **Private GitHub repository** https://github.com/Nugget1072/dbz-ssw2-godot-port (published with GitHub Desktop,
  "Keep this code private"; V: the GitHub API answers an anonymous request with 404, the owner's profile with 200).
  Audit before publishing (every file in the tree and in every commit): the only ROM-derived file was the mockup
  (purged). Kept by the user's decision: the translated game code `scripts/gen/` and `decomp/notes/charvm_ops_disasm.md`
  (program code, no assets). Other images: the user's own art (bomb / 1-UP = Nintendo characters but not from this ROM;
  port_button.png documented as the user's art). The BIOS volume table is melonDS FreeBIOS (BSD).
  V: a clone from GitHub, built per README "Building from a git clone", gives an exe frame-identical to the editor
  baseline (21/21). Pushing: command-line git has no GitHub login on this PC: push / fetch with GitHub Desktop.
