# HANDOFF — state of the port

_Last updated: 2026-10-14 (part 44 — release clean-up, README / release notes, showcase clips; part 43 — gamemodes BOSS RUSH and TOURNAMENT; part 42 — POWERS before CHALLENGES, slower Dragon Balls, cheats NONDIRECTIONAL, Z-VANISH, BODY CHANGE, cheat-mix bug hunt in local MP + LAN; part 41 — cheats VAMPIRE, TIME SKIP, DRAGON BALL HUNT, new cheat page POWERS, marker / bomb sizes fixed; part 40 — RANDOMIZER ultimates fixed, FLIGHTLESS jump, SMASH KNOCKBACK off camera, cheats HOT POTATO + RICOCHET KI; part 39 ULTRA INSTINCT etc.; part 38 ENDLESS; parts 36-37 were the first Claude Code
sessions on the user's PC; part 35 was the last Cowork part: `docs/CLAUDE_CODE.md`)._ Start with `CLAUDE.md` (rules, map, commands).
Per-part history: `docs/HISTORY.md`.

## Current state
The whole game runs from the user's ROM: power-on → intro → title → every menu → all modes (Story 14/14 maps,
Z-Battle series, Maximum, Free Battle, Practice, Data File, Options, VS host screen) → battles on every stage, with the
original sound driver. The user plays it on Windows (RTX 4070 laptop) from `finished/` ("almost perfect visually and
plays very well") and on a Steam Deck under Proton. The exported folder is portable and contains no game data (the exe
finds the player's ROM in its own folder under any name). On top: the QoL layer behind Mode Select's centre (PORT) tile —
13 menu pages (settings 1-3, BIG CHANGES = MULTIPLAYER + PERFORMANCE + NEW GAMEMODES, cheats 5-10, WEIRD STUFF 11-13),
LOCAL MULTIPLAYER (parts 27-29), LAN MULTIPLAYER (parts 30-32, lockstep), PERFORMANCE MODE (part 32), NEW GAMEMODES
ALL-STAR (parts 34-35), ENDLESS (part 38), BOSS RUSH and TOURNAMENT (part 43). Map of all of it:
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
6. TOURNAMENT for 2 players (local MP / LAN) when the user asks (ALLSTAR_DESIGN 9 "Not yet"). All four Gamemode slots
   are used (part 43); a 5th mode would need a scrolling / paged Gamemode menu.

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

## Part 38: ENDLESS mode, BOMB RAIN = cheat (2026-10-13) — DONE
- **ENDLESS** (Gamemode menu slot 2, the bar relabelled like ALL-STAR's; design + status docs/ALLSTAR_DESIGN.md 7): the
  All-Star session with `QoLAllStar.endless`: team select → Time Chamber battle against random enemies with no end
  (`QoLAllStar.at()`: never one of the two before; `esseed=`), same sky / music / hearts / CPU rules, HUD = clock +
  enemies beaten. Death (Game Over, scene 0x14) → **ENDLESS RECORDS** page (QoLAllStarRecords `endless`: tab ENDLESS,
  the WINNER band re-lettered GAME OVER in its own typeface, enemies / hearts / rank / best, rows "n KO" + faces +
  time) → A / START / B / tap → team select. `endless_records.cfg` next to the exe, most enemies first; nothing written
  with cheats on; a run that beat nobody is not ranked. HI-SCORES RESET (settings page 2) now also clears both records
  files (confirm text updated).
- **BOMB RAIN** moved from WEIRD STUFF 3 to cheats page 10 CHALLENGES under GREEN DEMON: `QoLSettings.bomb_rain` is a
  property over `cheats["bomb_rain"]` ([cheats]; an old [weird] value is carried over once), so it counts in
  `cheats_on()` (no Z-Battle ranking, no ALL-STAR / ENDLESS record) and travels in the LAN snapshot as a cheat.
- V (TESTING 29): 47 random swaps headless (heap flat), death → page → select captures, ranked file write, Gamemode menu
  by keys and taps, records layouts in the preview (`es_*`), ALL-STAR battle + records log identical to the part-37 code
  (git worktree A/B), menu pages, offcheck PASS. Facts: DATA_NOTES "part 38 findings (Endless)".
- Records page clean-up (user: text cut off, pasted, misaligned): GAME OVER is now set in the WINNER banner's own
  typeface (letters cut at runtime from the five languages' banner words, M = N's stem + V + stem, the word shrunk
  as a whole by area averaging into the banner's shades to fit); all numbers on both records pages packed from the
  digits' ink 1 px apart ("13 1" / "6 1:07" were the game's 8-px cells); "KO" drawn like the ranking digits; the
  ranking titles spaced by letter outlines ("ENDLES S" fixed, ALL-STAR RECORDS too); "Character Select" given 3 px
  before the plate's inner frame line. The emblem paste (`_gameover_letters`) is gone.
- Open: ENDLESS keeps
  ALL-STAR's 99:59 clock cap (enemy count ranks first); no real-play tuning yet (enemy level = the Option difficulty,
  as ALL-STAR).

## Part 39: four new cheats (2026-10-13) — DONE
- **ULTRA INSTINCT** (page 5 FIGHTING row 6; page 9 POWERS since part 41; `scripts/qol/qol_ultra.gd`): a Smash Ultimate / SF3-style parry. A fresh B
  tap in neutral / moving / guarding opens a 5-frame window; an enemy attack box touching the fighter then is parried
  (the fighter is left out of that collision pass): no damage, 12-frame hit stop, the game's guard spark, SE 0x21 (the
  tag-in "shing", chosen by analysing all 50 battle sounds: DATA_NOTES part 39), a silver-blue silhouette of the fighter
  + expanding silhouettes + a sparkle ring; the melee attacker staggers (0x11, stun 30), ki blasts are reflected the
  game's own way, beams / super parts pass through; 20 frames immunity. An empty tap = red flicker + 30 frames lock.
  Holding B = normal guard. Player 1 (both humans in MP).
- **RANDOMIZER** (page 7 CHARACTERS, row 6): each super / ultimate (X+A) is done by a random fighter (dispatcher
  FUN_0202AEB4 override + CHARACTER SHUFFLE's loader), back to the original when it is over, at once on a hit, at the
  win pose, or when benched after a KO; HP kept; boss picks keep their boss level; shuffles wait. Player 1 (both in MP).
- **FLIGHTLESS** (page 9): airborne active fighters of both teams fall (own fall speed added to y; the game lands them);
  supers / ultimates / throws / sequences / KO / poses stay in the air.
- **SMASH KNOCKBACK** (page 9, my extra idea): knock-back × (1 + 2 × HP lost / max), both teams.
- All four are cheats (no rankings / records), in the LAN snapshot (RANDOMIZER seeded by the battle seed); with them off
  every hook calls only the original. V (TESTING 30): captures of every effect, tap / miss / parry / reflect logs, 40+
  randomized supers in an All-Star team, MP run, LAN pair lan_cmp exit 0, menu previews, offcheck PASS.
- Code corrections found on the way: fighter +0x10 bit 0 = ON the ground (old comment said in the air); the dispatcher
  tests HELD bits (FUN_020011B4 reads +0x270). Debug flags `uidbg uiauto uise= rzseed= rzto= setest` (DEBUG_FLAGS).
- Open: real-play tuning (parry window 5 / stun 30 / knock-back factor 2 / fall speed) after the user tries them; the
  parry sound can be changed in one constant (`qol_ultra.gd` PARRY_SE) if 0x21 does not feel right.

## Part 40: cheat fixes + HOT POTATO, RICOCHET KI (2026-10-13) — DONE
- **RANDOMIZER + ultimates (bug)**: the ultimate test FUN_02026A8C spends the 150 % itself; RANDOMIZER now puts the
  team block tail (ki) back with the record before the swap, and starts the random fighter's ultimate the dispatcher's
  way when that fighter's own test refuses (direction rule). V: Metal Cooler / Teen Gohan / Majin Vegeta (forced)
  ultimates as random fighters, ki spent once.
- **FLIGHTLESS jump** (user: 3x higher): extra lift + lighter pull while rising: ~37 px (was ~9), ~32 frames.
- **SMASH KNOCKBACK** (user: too dull): push factor 1.4 (was 2); launched fighters can leave the picture (the camera
  tether's pull undone, the camera stays near the other fighter); off the camera 1 % max HP every 20 frames (KO
  possible); edge marker = the fighter's own face icon in a dark orange-rimmed box with an arrow, red on each tick.
- **HOT POTATO** (new, page 9, `qol_potato.gd`): a bomb with a 10-s countdown on a fighter's head, passed by hitting
  the other team, explodes for 30 % (the game's explosion + sound). Both teams.
- **RICOCHET KI** (new, page 6): player 1's ki blasts bounce off the screen edges / floor up to 3 times.
- V (TESTING 31): logs + captures of each, LAN pair lan_cmp exit 0 with all of them, menu previews, offcheck PASS.
  Facts: DATA_NOTES "part 40 findings". Debug flags: `p1hp p2hp rzult fldbg kbdbg hpdbg hpseed hpfuse hpwait rcdbg`.
- Open: tuning after the user plays (off-camera damage rate, potato fuse / damage, bounce count).

## Part 41: marker / bomb sizes + VAMPIRE, TIME SKIP, DRAGON BALL HUNT (2026-10-13) — DONE
- **SMASH KNOCKBACK marker** (user: icon badly sized in its box): the face icon's texture is 32x32 with the 24x24 face at
  its top left; it was squeezed into 24 px (face 18 px in a corner of a 30 px box). Now drawn 1:1 (crisp, 24 px) in a
  28 px box, and kept below the RUSH counter.
- **HOT POTATO size** (user: weirdly sized): the 11x12 bomb was drawn 1.5x (uneven pixels): now 1:1 on whole pixels,
  the countdown one digit size smaller (5x7; pops 2x on each new second).
- **New cheat page 9 POWERS** (pages now 13: weird stuff 11-13; header help text updated): ULTRA INSTINCT (moved from
  FIGHTING, which was full), VAMPIRE, TIME SKIP. DRAGON BALL HUNT = CHALLENGES row 6.
- **VAMPIRE** (`qol_vampire.gd`): every hit heals the attacking team's fighter 2/5 of the HP it took (measured around
  FUN_020293A4 inside the collision pass), green sparks victim → healer, a light green pulse, a green "+N". Both teams.
- **TIME SKIP** (`qol_timeskip.gd`, Hit's Time Skip): SELECT (no battle use in the game; research: DATA_NOTES part 41)
  with 100 % ki stops the enemy for 120 battle frames: its fighter skips FUN_0202954C but stays hittable, its support /
  objects frozen (the game's object freeze bit), body push / tether cannot move it; violet tint, the skipper drawn in
  its colours, the frozen fighter stone grey, rings in / out. Ends early on KO / grab / the skipper's throw or super.
  The CPU uses it too (seeded). In ALL-STAR / ENDLESS SELECT is TIME SKIP's while it is on (hearts by tap).
- **DRAGON BALL HUNT** (`qol_dragonballs.gd`): the game's own Dragon Balls (clear-event texture, decoded from the
  player's ROM at runtime, 24 / 12 px 16-colour textures in the port texture block, grown to 12 KiB) appear one at a
  time; touching grabs for the team, a 400+ HP hit drops the last one, all seven = wish (HP + ki full). HUD: 7 slots per
  team above the ki gauges; edge marker for a ball off the picture.
- Helpers: two research agents (time freeze + battle controls; Dragon Ball art) — their findings are in DATA_NOTES part
  41. Test gotcha found: unquoted `cheats=a,b` inside PowerShell `Start-Job` loses `b` (TESTING 32).
- V (TESTING 32): logs + captures of each, all-cheat stress run, LAN pair lan_cmp exit 0 (heals, skips both ways, balls),
  menu previews, offcheck PASS. Debug flags `vpdbg tsdbg tscpu tsauto tsseed dbdbg dbseed dbwait dbgive dbhere texgap`.
- Open: tuning after the user plays (heal 40 %, skip length / cost / CPU chance, ball drop threshold); TIME SKIP during
  throws / grab supers / beam struggles on the frozen side is cut short by design (untested combinations end the skip).

## Part 42: page order, NONDIRECTIONAL, Z-VANISH, BODY CHANGE, cheat-mix bug hunt (2026-10-14) — DONE
- **Pages**: POWERS is page 9, CHALLENGES page 10 (`QoLMenu.PAGES` lists "cheats6" before "cheats5"; help text updated).
- **DRAGON BALL HUNT**: first ball after 300 running frames (was 240), next 480 + 0-120 seeded after a grab (was 150).
- **NONDIRECTIONAL** (FIGHTING row 6, user idea): a held direction with X+A picks the super variant (up / level toward
  the enemy / down) whatever the angle; with red HP any direction fires the ultimate. +7 substituted around the
  dispatcher after a pure precheck (`_nd_pick`); research (VM op 4, 3 variants per fighter): DATA_NOTES part 42.
- **Z-VANISH** (POWERS, my idea; `qol_zvanish.gd`): B in a hit stun with 50 % ki → behind the attacker, neutral,
  untouchable until it acts, afterimage; not against supers / throws; CPU 30 % of its hit stuns (seeded).
- **BODY CHANGE** (POWERS, my idea; `qol_bodychange.gd`): every 20 s the active fighters trade HP shares; countdown at
  the bottom centre, Ginyu ray + violet glow.
- **Bug hunt** (TESTING 33): five local-MP cheat mixes + two LAN mixes: no script errors, LAN identical; three overlap
  problems fixed (BODY CHANGE countdown vs HOT POTATO countdown, VAMPIRE "+N" vs RUSH / HUD, Dragon Ball edge marker vs
  the HUD row).
- Helpers: two research agents (super variants; vanish mechanics) — DATA_NOTES part 42, local/research_*.md.
- Open: tuning (vanish cost / CPU chance, swap interval, ball timing); NONDIRECTIONAL diagonals as tilted level supers
  (index 5 / 10) not offered (untested).

## Part 43: gamemodes BOSS RUSH + TOURNAMENT (2026-10-14) — DONE
User asked for gamemode ideas (6 offered), picked BOSS RUSH and TOURNAMENT (TOURNAMENT 1 player first). Design + status:
docs/ALLSTAR_DESIGN.md 8 / 9; facts DATA_NOTES part 43; tests TESTING 34.
- **Gamemode menu**: the two EMPTY slots are BOSS RUSH (+0x4000 bar) and TOURNAMENT (a 4th bar written to free texture
  memory +0x8000; the second bar object's texture handle is pointed there for slot 3's draw). `QoLAllStar.mode` =
  the slot (ALLSTAR / ENDLESS / BOSSRUSH / TOURNAMENT); `start(mode)`.
- **BOSS RUSH**: ALL-STAR's battle against the 18 fighters with a boss version, levels 1 → 3, SSJ Goku last, each the
  game's own boss version (`_make_boss`, in `battle_bosses` for the dash fix); one heart; boss BGMs; BOSS RUSH RECORDS
  (`bossrush_records.cfg`; tab / plate letters B / H / U put together from the game's own letters).
- **TOURNAMENT**: `QoLTournament` (8-team seeded bracket, CPU matches rolled by team max HP) + `QoLTournamentPage`
  (bracket page, both screens, keys + taps, FIGHT / QUIT-CONFIRM / OK) + QoLGame `# ---- TOURNAMENT` (battle scene held
  at state 0 while the page shows; won → 10 rerouted to a new battle; CPU level +0 / 2 / 4 per round; titles in
  `tournament_records.cfg`).
- V: br1 (18 bosses, win, records), tn1 (QF / SF / F won), tn3 (lost → knocked out), gm1 / tn2 (menu path, QUIT),
  preview `tour`, ALL-STAR / ENDLESS A/B against part 42 (git worktree): identical AS lines; offcheck PASS.
- Open: TOURNAMENT for 2 players (local MP / LAN: MP routing puts the second human on side 1 only, the bracket would
  need the LAN snapshot); BOSS RUSH / TOURNAMENT difficulty tuning from real play.

## Part 44: release clean-up + showcase clips (2026-10-14) — DONE
User: clean up the repo / folders for a GitHub release (repo stays private) and record 3-4 short clips of the best
cheats, one with Kid Gohan (not SSJ2 Gohan) parrying Final Boss SSJ Goku's whole super with ULTRA INSTINCT.
- **Removed** (unused since the translated game took over; git history has them): `scenes/battle/`,
  `scripts/{battle,ui,audio}/`, the `Sound` autoload, shaders `ds_bg` / `ds_textbg` / `palette_sprite`, the orphan
  `ds_main_loop.gd.uid`, `Game`'s `p1` / `p2` / `stage` / `p2_cpu` flags. `Pilot` stays (scripted test input).
- **Docs**: README.md = GitHub front page (features, play, build, clips, legal); `docs/RELEASE_NOTES.md` = release text
  draft; `docs/archive/` (HANDOFF_ARCHIVE_part8, PROJECT_BRIEF, ROM_REMIX_ONBOARDING); `docs/WORK_OUTSIDE_FOLDER.txt`.
- **Clips** (for the user only, not published; `local/release/videos/`, game footage, never in git): `ssw2.py clip` (every-frame capture + its
  audio.wav → H.264 / AAC MP4, 3x nearest) and `tools/test/showcase.py` (the four clips, TESTING 35):
  ULTRA INSTINCT (Kid Gohan = id 24 vs Final Boss SSJ Goku: 12 real B-tap parries incl. all ten blasts of the boss's
  super from above, 0 misses, Gohan 10000/10000 HP, then his 16-hit counter super), TIME SKIP (SSJ Goku vs Frieza,
  22-hit finish), RANDOMIZER (Krillin's supers as Piccolo / Broly / Gotenks, enemy held still), Z-VANISH (Goku vs
  Vegeta vanish exchange). ffmpeg: one already on the PC (`FFMPEG=`, docs/WORK_OUTSIDE_FOLDER.txt).
- **Release zip**: `local/release/DBZ_SSW2_Port_v1.0_windows.zip` = exe + dll + README / BUGFIXES / BOSS_CHARACTERS
  only (no ROM, no settings / save / records files).
- V: offcheck PASS after the removal (21/21 + 1382 CHT, 221/221); export + the exe's offcheck battle vs the baseline
  21/21; `showcase.py` twice = every frame identical (deterministic); clips checked frame by frame (contact sheets).
  The zip is written with Python's zipfile (forward-slash paths; PowerShell 5.1's Compress-Archive writes backslashes).
- **GitHub release v1.0** (private like the repo): https://github.com/Nugget1072/dbz-ssw2-godot-port/releases/tag/v1.0
  = the zip + the same five files loose, text = docs/RELEASE_NOTES.md. Made with the GitHub CLI (`tools/gh/`,
  git-ignored, signed in by the user with a device code; `tools\gh\bin\gh.exe release …`). V: the release downloaded
  again = zip contents byte-identical to the loose files; unpacked + a renamed ROM copy: no ROM → "Game ROM not found"
  screen, first run creates DBZ_SSW2_Port.sav + settings.cfg, boots to MODE SELECT, PORT menu by mouse, offcheck
  battle 21/21; a fresh `gh repo clone` + save100.sav + `ssw2.py export` → battle 21/21. ROM copies deleted after.
- **LICENSE** (user: "allows all legal uses") = MIT for the port's own code; README "License" lists what it cannot
  cover (the game, `scripts/gen/` + `charvm_ops_disasm.md`, melonDS GPL tool, Dragon Ball / Nintendo characters);
  `docs/THIRD_PARTY_NOTICES.txt` (Godot, godot-cpp, FreeBIOS BSD table) — both copied to finished/ by `ssw2.py export`
  and added to the release (zip rebuilt with the same exe; re-download = identical).
- **Commit email** (user request): all 18 commits rewritten (git fast-export → author / committer lines only → fast-import;
  trees identical) from the Gmail address to `164543587+Nugget1072@users.noreply.github.com`, tag v1.0 moved with them,
  force-pushed by the user (the permission check blocks force pushes from Claude). Repo `user.email` = the no-reply
  address; the user turned on GitHub's private-email settings. Backup of the old history:
  `local/backup_before_email_rewrite.bundle`. GitHub still serves the old commits by their exact SHA until its garbage
  collection (GitHub Support can purge them).
- **Personal-data sweep** (user request): no Windows user name, local folder paths or the PC's IP addresses anywhere —
  current files, all history (rewritten again: fast-export, the few doc lines with the user's path replaced, trees of
  later commits identical), release files (exe / dll strings: only Godot's and the sandbox's build paths) and GitHub's
  repo text. Example IPs in the LAN UI / docs are generic (192.168.1.23, 127.0.0.1, 192.0.2.x). Backups of the old
  histories: `local/backup_before_*.bundle` (git-ignored, contain the old data).
- `local/` pruned on the user's request (~1.8 GB of old runs); kept: baselines, release zip, research notes, prevbg.png,
  the history-rewrite bundle. Not done: a LICENSE (the user's decision).
- For a public release later: `scripts/gen/` is a machine translation of the game's program code (kept by the user's
  decision, part 37); `tools/melonds-headless/libmelonds_headless.so` is a GPL-3 build of melonDS (its source is
  upstream; a public repo should say so).
