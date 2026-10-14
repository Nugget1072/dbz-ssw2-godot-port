# Testing and verification

> **Read this part for…** setup + baselines: intro and top of 1-8 (captures vs melonDS, bars, `cmp_gx`, lockstep, GPU,
> portable build, perf, pacing) · a QoL feature's test: sections 9-24 by part (menu 9, cheats 10-16, zoom 17, weird
> 18-23, MP 24) · LAN: 25 + docs/LAN_DESIGN.md 8 · performance mode / part 32: docs/TOOLING.md "part 32" Checks.
> Off-identity baselines every change must keep: intro 221/221, barcheck 0, btn/off23 battle 21/21 PNGs + `CHT f`
> lines, headless pacing 59.8. Flag reference: docs/DEBUG_FLAGS.md.

**Part 35: on Windows (Claude Code) use `tools/test/ssw2.py`** (`offcheck`, `baseline`, `run`, `pngdiff`; stdlib only;
baselines in `local/baselines/<tag>/`; docs/CLAUDE_CODE.md). The `tools/linux/*.sh` scripts below are the Linux
originals; their `/tmp/ssw2` scratch folder is replaced by `local/` in ssw2.py.

The rule: a change is done when the port matches the original game, shown with images or RAM dumps — not when
it "looks right". The ground truth is melonDS 1.1 (frame-exact headless core in `tools/melonds-headless/`).
All scripts below are in `tools/linux/` (bash + Python 3 with Pillow/numpy; set `GODOT=` to the Godot 4.7.2 Linux
binary; `ROM`/`SAV` default to `finished/*.nds` and the project's `data/save100.sav` — `tools/linux/env.sh` still checks the
removed `baseroms/` / `100Save/` first; scratch output in `/tmp/ssw2`). They need an
X display for the GPU (Xvfb is started automatically). Setup: `docs/TOOLING.md`.

## 1. Frame captures vs melonDS (screens)
- Port: `tools/linux/cap.sh DIR EVERY TO [FROM] [inputs=...]` → `DIR/p<frame>.png` (both screens, 256x384). The game
  pauses while each frame is saved, and the RTC is frozen at 2026-01-01 12:00 (the game seeds its RNG from the
  clock), so runs are deterministic and repeatable.
- melonDS: `python3 tools/linux/melon.py OUTDIR run:N s:name ...` (optionally `ST=reference/states/<x>.mst`), or
  `tools/melonds-headless/mhs.py`. The same RTC freeze is built into the core.
- Match: `python3 tools/linux/match.py REFDIR PORTDIR` pairs each port frame with the closest melonDS frame (the
  original has lag frames while loading; the port does not) and prints the differing pixel count.
- Baselines (part 9): intro run `cap.sh DIR 10 2210 10` vs a melonDS run `run:1 s:r<i>` for 2,300 frames → 163 of
  221 sampled frames pixel-identical, total 216 k px. Stage: `tools/linux/stagecmp.sh 2 0 korin` → median 26.4 k px
  (mostly fighter animation phase). A change that makes these worse needs a reason.
- Useful input scripts: mode select `inputs=2141:Start:4,2300:Start:4` (from frame ~2400); Free Battle
  character select `inputs=2141:Start:4,2396:T128/120:6` ; full stage setup: see `tools/linux/stage.sh`.

## 2. Scrolling menu bars
`python3 tools/linux/barcheck.py DIR` on a mode-select capture (frames 2440–2560): the bar's black/white border
rows must be identical in all 256 columns and every frame (melonDS: rows 362/379 of the 384-row capture).

## 3. 3D geometry engine
- GDScript vs C++ parity: capture with `gxdump=FROM:N`, then
  `godot --headless --path GodotGame/new-game-project --script res://tools/cmp_gx.gd -- gx=DIR/gx.bin` (no output =
  identical). Required after any change to `ds_gx.gd` / `ds_gx_native.cpp`.
- `tools/dump_gx.gd gx=... frame=K` prints the triangles sent to the GPU; `tools/bench_gx.gd` benchmarks.

## 4. Lockstep (CPU/translation correctness)
`tools/linux/lockstep.sh REFDIR [frames]` runs the translated program against melonDS RAM dumps made by
`tools/melonds-headless/lockstep_ref.py` and lists differing RAM ranges per frame (`decomp/tools/lockstep_cmp.py`).
References: `t1` (battle snapshot, 18 frames; known diffs 0x020E18A9 / 0x020E1931 + the sound-stream buffer at 0x022E6400; `LSSAV=` overrides the original save) and `boot`
(power-on; aligns until the first heavy load, then lag frames). Rerun after any translator/runtime change.

## 5. On the user's GPU (Windows)
The cloud has no GPU (Mesa llvmpipe), and some bugs only show on real hardware (part 9: texels one row off on an
NVIDIA RTX 4070). Export, then double-click `tools/windows/capture_test.bat`: it writes `finished/cap/p*.png`
for frames 2440–2560 of mode select. Compare with `cmpdirs.py` against the same frames captured elsewhere
(part 9: 0 differing pixels between the RTX 4070 and llvmpipe) and run `barcheck.py` on them.

## 6. Portable build
Copy `finished/` (without the ROM) into an empty folder: the game must show "Game ROM not found" with the
folder path. Add the ROM under any name (e.g. `x.bin`): it must boot and create `DBZ_SSW2_Port.sav` beside the
exe. `tools/check_rom.gd file=PATH` prints why a file is (not) accepted. Search the exe for ROM bytes to be sure
none are embedded (part 9: none; only the 8 KiB 100% save).

## 7. Performance
`perf` flag prints timings every 600 frames (emulation step, scanlines, sound, 3D, refresh). Cloud VM battle:
≈7–9 ms step, ≈1–2 ms refresh. Release builds are ~2× faster than editor runs.

## 8. Game speed (frame pacing)
Game speed must be the DS rate (59.83 frames per real second; 60.00 when the frames are locked to a 60 Hz
display) on every PC. `pacelog` prints `PACE game <frames/s>` every 5 s. Without drawing cost (pacing logic only):
`DBZ_SSW2_Port.x86_64 --headless -- pacelog quit_at=1300 fakehz=N maxfps=M` for N/M = 60/0 (V-Sync off,
uncapped), 60/60, 75/75, 144/144, 165/165, 240/240, 30/30. On Windows: `tools/windows/pace_test.bat`
(part 10 on the user's 165 Hz RTX 4070 laptop: 59.7–60.2 in every case, including 700–3,000 fps uncapped).
The release build stdout is only flushed on a clean exit: always pass `quit_at=`.

## 9. QoL settings menu and smooth motion (parts 11-12)
- Layout: `godot --path GodotGame/new-game-project --rendering-driver opengl3 --resolution 256x384
  res://tools/qol_preview.tscn -- rom=ROM bg=CAPTURE.png out=DIR` draws every page / cursor state in seconds
  (no emulation). Compare with the game's OPTION MODE screen (melonDS: Mode Select → OPTION).
- Menu walk-through: `tools/linux/qoltest.sh DIR` (script in its header): keys and taps on every page, window
  size confirm / undo / keep / 10-second timeout, frame rate, FPS counter, sound effects off, jukebox play / next /
  pause / back, EXIT, the game's own navigation off the tile, and a press during Mode Select's exit transition
  (must reach the game). Look at the captures; `DIR.cfg` must hold the final settings (part 12: fullscreen,
  scale 2, 120, counter on, music on, SFX off); the `QOL`
  lines in `DIR.log` give per frame the music channels, mute mask and active channels (music OFF must mute the
  music mask, SFX OFF everything else; in the jukebox the music stays audible).
- `noqol` turns the layer off; with the layer on, the intro match and `barcheck.py` must stay at their baselines
  (part 11: 163/221 identical, 216 k; 0 bar pixels) — nothing is drawn unless the cursor is on the centre tile.
- Smooth motion: capture the same frames with and without `capinterp=0.5` (and `capinterp=0`, which must look like
  the previous frame for anything that moved): in-between frames must differ from both neighbours only where things
  move; static scenes and `capinterp=1` identical. Part 11, Korin battle 4200-4230 holding Right: in-between frames
  lie between the game frames (stage, BG and sprites aligned); Mode Select static pixels exact.
- Game speed with smooth motion: `--headless -- pacelog fakehz=120 maxfps=120 smooth=1 quit_at=1300` (and 240):
  59.8 game frames/s.
- 3D motion data: `cmp_gx.gd` compares `out_prev` too (GDScript vs C++).

## 10. Cheats (part 13)
- Menu: `tools/linux/qoltest2.sh DIR` (pages by L/R, arrows, taps; every cheat switched on; EXIT by tap and by
  keys); `DIR.cfg` must list all six cheats true; the tile description says "Cheats on: 6".
- Effects, headless with `cheatdbg` (pass `rtc=2026-01-01T12:00:00` for repeatable runs) and the Free Battle input
  script of `tools/linux/stage.sh`, plus A presses every 7-12 frames from 4200: INFINITE HEALTH keeps P1 HP at
  max while P2 hits; INFINITE KI keeps 51200; ONE-HIT KO: P2 HP → 0, action 0x33 after the first unguarded hit;
  NO COOLDOWN: more P1 ki blasts alive at once (6 vs 1); KI HOMING: more hits on a P2 that is not straight ahead
  (part 13: 9760 vs 10408 HP left); SAME CHARACTERS: with A pressed three times on Goku the party block shows
  P1 0 0 0 and the battle has three Gokus. Captures with and without the cheats for the visuals.
- With all cheats off the baselines (intro match, bars, lockstep with plain DSGame) must not change.

## 11. Boss / random characters, full screen (part 14)
- Boss: Free Battle input script with the cursor moved to Broly (Down×3, Right×3 from Goku) and `L:12` around the
  A press (`cheats=boss_characters cheatdbg`): log "CHT boss fighter … id 20 level 3 hp 26000 boss branches 8 of 8"
  (the GDScript bytecode walker must find the same 0x92 count as decomp/tools/charscript.py: Broly 8, SSJ Goku 11,
  Cell 10), skull on the select portrait and on the battle panel, boss ki blast ("15 RUSH") on A.
- Random: `cheats=random_characters cheatdbg`: party block changes at the battle start and returns to the picks
  after FUN_02013D60; team records show the random ids; never only supports.
- Full screen: `--resolution 1600x900 --position 0,0 -- presentfit` on Xvfb: "PRESENT ... rect (500,0) 600x900
  scale 2.344"; screenshot (`import -window root`): even letters (sharp-bilinear).

## 12. Assist spam, random music, title font (part 15)
- Titles: `tools/qol_preview.tscn` renders every title in the HEAVY font (look at them at 4x).
- Assist spam: Free Battle script + `poke=3520:020DD528:1A:8;3520:020DD548:0102:8;3520:020DD53C:1A:8` (P1 = Goku
  + support 26, after the party commit) and `T128/76:3` taps every 40 frames from 4200, `cheats=assist_spam,
  infinite_assists cheatdbg`: "assist slot … clones N" rises to 7; P2 13000 → 0 HP (10600 without the cheat).
- Random music: `cheats=random_music cheatdbg` vs without: "bgm mode/id" — Mode Select seq 1 → other, select
  STRM 19 → other, VS 18 → other, battle stage track → other; `qoldbg` shows the new sequence's channels active.

## 13. Controls, settings page 2, character shuffle, icon, black borders (part 16)
- Layout: `tools/qol_preview.tscn` (states page2*, controls1*, controls2*, controls_header/back, shuffle).
- Menu walk-through: `tools/linux/qoltest3.sh DIR` (raw keys are scripted as `K<name>`, e.g. `2680:Kspace:6`, sent
  through Godot's Input so the input map applies): SETTINGS 2 → CONTROLS, Y's KEY box → Space, Escape cancels,
  a tap cancels a PAD wait, page 2, BACK, AUTO PAUSE ON, VOLUME 50, B closes. `DIR.cfg`: ds_y_key="k:32", the
  other keys unchanged, volume=50, auto_pause=true.
- Remap in battle: Free Battle script + `qolcfg=` that cfg + `Kspace` / `Kc` / `Kz` presses: Space → melee
  (action 0x1C, P2 hit), C → nothing, Z → guard 0x18 (part 16 V).
- Button meanings: Free Battle with each DS button alone, `cheatdbg` actions (DATA_NOTES part 16).
- Character shuffle: `cheats=character_shuffle cheatdbg shufseed=N` → "CHT shuffle #n … id a -> b … hp x -> x";
  captures show sprite, life-bar face and lower-screen portrait of the new character; with the cheat off the
  run is byte-identical to the one before (17/17 PNGs, 1147 log lines).
- Black borders: `--resolution 1200x900 --position 0,0 -- presentfit`, screenshot (`DISPLAY=:99 import -window
  root`): every pixel outside the 600x900 picture is (0,0,0) (part 15 builds: white).
- Window icon: `qoldbg` prints "QOL icon from the ROM banner" and writes user://banner_icon.png (Goku face).

## 14. Smooth-motion edges, cheat combinations (part 17)
- Edge gap: the same Free Battle script twice, `cap_every=1` around a dash (X near the enemy), once plain and once
  with `capinterp=0.5`; count pixels in the outer 3 columns (y 20-170) of the in-between capture that match neither
  neighbouring 60 fps frame (part 17: 3836 before the fix, 485 after; look at frame 4812's right edge).
- Boss + shuffle: Free Battle with Broly picked with L (Down×3, Right×3, `2805:L:14` around the A at 2810),
  `cheats=boss_characters,character_shuffle shufseed=7` (Broly → Metal Cooler: skull gone) and `shufseed=3`
  (→ Majin Buu: "CHT boss fighter … id 16 level 2", skull stays).
- Combinations: shufrunB-style battle (P1 Goku + Vegeta + support 26 by poke, assist / tag taps) with many cheats at
  once and `cheatdbg`: no SCRIPT ERROR, battle ends and returns to the menus.

## 15. Part 18 cheats and the boss dash fix
- Boss dash: P1 boss Broly (L pick) vs CPU, R+direction dash then release, `dashdbg`: speed after release must stay
  positive (fixed 9960, normal Broly 3984; `nodashfix` shows −27136 and the camera racing). melonDS proof: poke the
  level-3 block into P1's +0x50 in battle_ready.mst (helper agent's /tmp script, see DATA_NOTES part 18).
- CHAOS SHUFFLE: `cheats=chaos_shuffle cheatdbg shufseed=N`, busy inputs: 30+ swaps, "waits: super 2c/2d" then a
  swap right after; archives / cache counts and heap per character stable.
- STAGE SHUFFLE: `cheats=stage_shuffle cheatdbg stglist=…`: "CHT stage #n" lines, bgm id unchanged, heap per stage
  identical on revisits, swapped-in stage = normally loaded stage (VRAM / registers) except the sky phase.
- TRIPLE KI: "blasts N" peak ~3× (23 vs 6). ATTACK SPAM: hits / P2 HP over 300 frames of X or Y spam (13 vs 3 hits).
- HARD MODE: same Free Battle with `cheats=hard_mode` vs none: P1's hits on P2 do half, P2's hits on P1 double.
- Cheats off: btnrun captures + cheatdbg lines byte-identical to the part-16 baseline.

## 16. Part 19 (menu sounds, chaos waits, shadows, random stage)
- Menu sounds: `cap.sh DIR 100 2700 2500 inputs=2141:Start:4,2300:Start:4,2480:Right:4,2510:Down:4,2540:A:4,
  2570:Down:4,2600:R:4,2630:A:4,2660:B:4 qoldbg qolcfg=X.cfg`: "QOL se 5/0/5/5/0/4" and a new SFX channel bit in
  "sfx channels" the frame after each (part 19: 0x0400, 0x0800, 0x0400, 0x0080, 0x8000, 0x0010).
- Chaos waits: `chaosat=F` to force a swap during Kid Buu's ball (victim 0x55), a throw (0x34), Broly's grab (0x59),
  P1 throw (0x85), Ginyu / Cooler summons: log "waits: held …" then the swap right after; P1 visible.
- Shadows: Free Battle on the ground with `shadows=1` vs without: every differing pixel is black (silhouette vs
  ellipse) except auras drawn over it; `shadows=0` byte-identical to the baseline.
- Random stage: `cheats=random_stage cheatdbg`: "CHT random stage a -> b", the battle shows stage b with its music.

## 17. Part 20 (zoom, dash lines, speed)
- Zoom: `zoom=N` (or `zoomcycle`: level = frame % 5) captures on several stages; level 2 byte-identical to the
  baseline; look at fighters / beams / shadows at levels 0 and 4, stage edges at 0.
- Dash lines: double-tap dash with `cheats=no_cooldown`: the lines end with the dash (17 frames, as melonDS).
- Game-step speed: `/tmp`-style script: `godot --headless --fixed-fps 60 --path … -- … inputs=<battle> turbo
  quit_at=5600` timed (wall clock), several runs per build; compare with `noqol` and an older tree.
- Renderer changes: intro capture identical (221/221), `capinterp=0.5` captures identical, a 2x window screenshot
  is exact 2x2 pixel blocks, `presentfit` fit unchanged.

## 18. Part 21 (weird settings, zoom culling)
- Off = identical: intro 221/221, barcheck 0, btn battle captures + CHT lines vs the baseline.
- `weird=bevel` / `weird=fuzzy` captures (menus, battle; capinterp, zoom=0); fuzzy outside battles = 0 px change.
- `weird=epic`: Mode Select / Option descriptions, Story dialogue; all 3040 story strings through QoLEpic offline
  (helper's epic_test.gd): none over 126 bytes; intro frames identical.
- `weird=fiddle`: same-character match → colours swap; different characters → only P1 changes.
- Zoom culling: camera sweep per stage at zoom=0/1 (`zoomcull=0` = before): objects enter/leave at the screen edge.

## 19. Part 22
- Button art: Mode Select captures on vs `nobutton`: 0 px outside the centre tile (x 87..168, y 63..108 of the
  lower screen); highlight / fades / re-entry checked.
- Fuzzy per mode (Practice, Story, Z-Battle, Maximum, Free): on in battle, 0 px change in menus / VS / dialogue.
- `weird=gameboy`, `weird=mirror` (LEFT/RIGHT swapped: a Right press moves the fighter to the right on screen),
  `weird=blood,after` captures; all off = btn identical.
- QA scripts (helper): menu walk by keys + taps, cfg robustness (typed / garbage files), SIGSTOP freeze test.

## 20. Part 23
- Epic pictures: `weird=epic` Data File pages, help panels, touch items, Option -> Credit roll captures; offline pass
  over all 278 EN Data File members (367 texts rewritten, 0 kept); off = btn identical.
- Blood scaling / flashy / confetti / shake: `blooddbg`, `flashydbg`, `fxdbg` SHAKE lines in Free Battle (damage → drops,
  shake offsets measured from the HUD); ONE-HIT KO for the caps; all off: intro 221/221, btn 345 PNG + CHT identical.
- Leaderboard: seed save with 5th place = 1000, Z-Battle win of 30000: no cheats → rank 5; any cheat → "not entered",
  table unchanged; `lbreset=F` → save result 0, only the ranking changes in the .sav, next boot shows defaults.
- Menu reset path: `cap.sh DIR 30 2880 2760 inputs=2141:Start:4,2300:Start:4,2480:Right:4,2510:Down:4,2540:A:4,
  2570:R:4,2600:Down:4,...(5 Downs),2780:A:4,2810:Left:4,2840:A:4 lbdbg` → confirm page (NO first), YES →
  "LEADERBOARD f2839 reset to defaults, save result 0" and "HI-SCORES RESET" on the upper screen.
- Layout: `tools/qol_preview.tscn` states page2_hs, lbconfirm, lbconfirm_yes, lbconfirm_no, weird_p1, weird_p2.

## 21. Part 24
- Gamepad cursor: `fakepad vcurmove=F:SX:SY:N,... vcurclick=F:N,... curdbg` from Mode Select (clicking the PORT tile
  opens the menu, clicks change pages / values); no gamepad → intro 221/221 and off23 battle identical.
- AUTO SKIP: `autoskip=1 skipdbg` in Story (qa_s/story1.in) and Z-Battle (qa_s/zb3.in without A presses): "SKIP f..."
  lines; story progress RAM 0x020DD5B4..0x020DD7A8 and the written .sav identical watched vs skipped.
- WEIRD 3: Free Battle `weird=dmgnum,rainbow` (+flashy, mirror, zoom=0), `w3dbg`, `w3merge=0` for stacking (part 24 also
  had `jelly`; JELLY FIGHTERS was removed in part 25).
- QA: offline menu checker over all pages (line widths, wrapping, paging, taps); cfg round-trip of every key;
  mirror + Start: pause menu readable.
- Freeze repro: `cheats=chaos_shuffle shufseed=49 noloadskip dmaread` hangs ("busy-wait on 040000dc"), without
  `noloadskip` it runs.

## 22. Part 25
- BOMB RAIN: `/tmp/ssw2/bomb_run.sh` Free Battle `weird=bombs bombdbg`: "BOMB ... direct 25.0% of 13000 ... 13000 ->
  9750", ground blast lines, GUARDED lines, dodged bombs; zoom=0 + mirror; Z-Battle and Story (autoskip) no errors.
- INPUT DISPLAY: `weird=inputs inpdbg` (pad bits vs scripted presses), with mirror / gameboy / crt.
- CRT TV: captures (CanvasLayer pass) + real-window screenshots through the presenter at 2X / 4X / fit (one dark row
  per DS row from 2X).
- Off: intro 221/221 and off23 battle (21 PNGs + CHT lines) identical.

## 23. Part 26 (Steam Deck / Proton: pipelining, perflog)
- Pipelining keeps the game identical: windowed free run (no capture) of the Free Battle script with `pipeline=1`
  (or auto when frames are late) + `cheatdbg cheats=infinite_health rtc=…`: all `^CHT f` lines up to 5300 identical
  to /tmp/ssw2/btn (capture mode); PERFLOG `pipe` > 0 shows frames really ran ahead.
- Off paths unchanged: intro 221/221 + audio.wav identical, off23 battle (21 PNGs + CHT) identical, headless pacing
  (`--headless -- pacelog fakehz=N maxfps=N quit_at=1300`) 59.8 (headless never draws, so never pipelines).
- Speed: `--rendering-method dummy fakerender=6 perflog` real-time Free Battle, `pipeline=0` vs `pipeline=1`
  (fps / game frames per second / `wait`); the same with the Windows export under Wine (docs/TOOLING.md part 26).
- Exit with a frame in flight: `--quit-after 400 … pipeline=1` exits cleanly (no SCRIPT ERROR, exit code 0).
- Bomb sprite / effect pairing (part 26): per-frame captures at `capinterp=0.25` / `0.5`, zoom 0 / 2 / 4
  (/tmp/ssw2/bs_work sheets); instrumented gxnative=0 copy counting wrong prev-polygon pairs per effect (0 after).
- Menu: preview states main3, weird, weird3 (SETTINGS 3 = AUTO SKIP / DAMAGE NUMBERS / INPUT DISPLAY).

## 24. Part 27 (local multiplayer)
- Battle core: btnrun + `mpbattle=1 p2inputs=4600:A:4,4700:Y:4,4800:R:40,4900:B:40 cheatdbg mpdbg` → P2 actions
  0x24 / 0x1C / 0x0C-0x0D / 0x18 at those frames, idle otherwise; panel taps per half (tag, support 0x28, Team Arts
  0x30 with ki full).
- Menu / setup: `mp=1` VS menu inputs `2141:Start:4,2396:T128/120:6,2560:Right:4,2590:Right:4,2660:A:4`; fake pads
  (`fakepads=2`, `mppad=`, `vcursor2`…); preview `tools/qol_preview.tscn -- mp fakepads=2`.
- Select / stage / loop: /tmp/ssw2/mpsel/run.sh (4 rounds, heap / file-cache counts identical per scene change).
- QA: /tmp/ssw2/qa (WIN/LOSE banner from the winner's side, pad cursors kept on their half, grey-outs).
- Off: MULTIPLAYER off and `mp=1` outside a session → btn 21/21 + CHT lines identical; intro 221/221.

## 25. Part 30 (LAN multiplayer)
- Two headless instances on 127.0.0.1 (docs/LAN_DESIGN.md 8): `lanbattle=1` lockstep with different rtc / menu detour /
  zoom on the guest → `lanhash` identical (tools/linux/lan_cmp.py); full flow `lan=host` / `lan=join:127.0.0.1 lanauto
  lanpicks= lanstage=` (two battles, loops, pause paths); impairment `lanlag=80 lanjitter=20 lanloss=10`; kill -9 /
  leave in every stage; `landesync=L`; 10 000-frame battle; 6 rounds heap stable; exported exe under Wine.
- Off: no session → btn 21/21 + CHT lines, intro 221/221, LOCAL MP flow log identical.

## 26. Parts 31-32 (LAN rejoin / pause, performance mode)
- LAN rejoin / disconnect matrix: docs/LAN_DESIGN.md 8 (part 31 flags) and 9.3; scripts were in /tmp/ssw2/lanrj.
- LAN pause: `lanpace pingdbg` real-time pair (/tmp/ssw2/lanpause); guest panel captured in pause (DATA_NOTES part 32
  "LAN pause").
- PERFORMANCE MODE + exact speed-ups: docs/TOOLING.md "Session 1 part 32" **Checks** (off and on identical, LAN hashes
  identical with it on one side, pacing 59.8 incl. `perfmode=1`).

## 27. Part 36 (GREEN DEMON cheat, shared texture block)
- Behaviour (Free Battle, `cheats=green_demon gddbg`, captures `--every 20`): P1 idle → spawn off the picture ~90
  frames into the fight, approach, KO with explosion + SE 0x2B, "KnockOut!! LOSE" (gd1); P1 fleeing
  `--inputs "4250:Left:400,4700:Right:400"` → never caught while fleeing, KO when flying back into it (gd3).
- Team / All-Star: `allstar=1 asp1=0,5,6 cheats=green_demon,infinite_health gddbg asdbg` → KO through INFINITE
  HEALTH, state 7 → 0xC, next member tags in, rest 120 frames (gd4). Catch-up after knock-backs: the status lines.
- Local MP: `mp=1 mpbattle=1 --inputs "4200:Left:1300" p2inputs=4200:Left:1300` → switches every 600 frames, lock /
  KO (gd7); `p2inputs=4200:Left:1300,5906:Left:200` → "lock lost" then random target (gd8).
- Stage moves: `cheats=green_demon,stage_shuffle` → `GD … shifted` at each swap, drawn on the new stage (gd9b).
- Sound: two runs with `--cfg` (a settings file with `[sound] music=false`), `gdse=-1` vs default: the audio.wav files
  are identical up to the kill, then the SE adds ~1.2 s (DATA_NOTES part 36).
- LAN: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\windows\lan_pair.ps1 -tag gd_lan -cheats green_demon
  -extra gddbg` (host cheat only, guest other RTC + zoom 4) → `gp first diff: none` over 1538 lockstep frames, same
  GD lines on both sides.
- Menu: `ssw2.py run menu_keys --every 30 --from 2500 --to 2900 --inputs "2141:Start:4,2396:T128/120:6,2560:T128/96:4,
  2640:L:4,2670:L:4,2700:L:4,2730:L:4,2770:Left:4,2800:A:4"` and the same with taps (`T139/13` ×4 = ◀, `T201/44` = ON)
  → `green_demon=true` in local/runs/NAME.cfg, page 9/12 shows ON. Preview: `tools/qol_preview.tscn` states
  `challenges`, `challenges_on`, `challenges_hdr` (quote `"rom=…"`: the ROM path has spaces).
- BOMB RAIN after the texture-block move: `weird=bombs bombdbg` run before / after → 61/61 captures + 21 event lines
  identical; both cheats on together: one TEXBLOCK reservation, both drawn.
- Off: `offcheck` PASS (21/21 + 1382 CHT, 221/221).

## 28. Part 37 (exported exe = editor; capture saves)
- Exe vs editor: run `finished\DBZ_SSW2_Port.exe -- quit_at=5301 "capture=<abs dir>" cap_every=50 cap_from=4300
  cap_to=5300 "sav=<copy>" "save=<copy>" "qolcfg=<fresh file>" rtc=2026-01-01T12:00:00 inputs=<BATTLE_PATH +
  BATTLE_ACTIONS> cheatdbg cheats=infinite_health` (the offcheck battle's flags) → `ssw2.py pngdiff <dir>
  local\baselines\windows\battle` = 21/21. `dumpram=F,…` in both builds + a byte compare finds the first differing
  frame / address (scratch script; part 37 found the user:// settings leak this way).
- Capture without `save=`: the exe's DBZ_SSW2_Port.sav keeps its hash and modification time.
- GitHub clone build: README "Building from a git clone" (clone → copy save100.sav → `ssw2.py export` → boot).

## 29. Part 38 (ENDLESS mode, BOMB RAIN = cheat)
- Swaps (headless, ~5 min): `ssw2.py run es1 --battle --headless --to 16000 --inputs "<A:3 every 12 frames from 4200>"
  allstar=1 endless=1 esseed=7 cheats=one_hit_ko,infinite_health,infinite_ki,ki_homing asdbg turbo` → `AS f… swap #n`
  lines with random ids (never one of the two before), heap free ≈1 MB without a trend, no SCRIPT ERROR (47 swaps).
- Death → records → select: `ssw2.py run es2 --battle --every 50 --from 4500 --to 6400 --inputs "5800:A:4" allstar=1
  endless=1 esseed=3 ashp=4700:0:0 asdbg esrec=<abs>\es2_rec.cfg` → p4650 HUD (MM:SS + "0" plate, hearts), `battle end
  … result lose`, `scene 0 -> 4 (asked 14)`, p5200 ENDLESS RECORDS (GAME OVER banner, Not Ranked), A → p6000 team select.
- Records page lettering (part 38 clean-up): zoom the preview PNGs 4-8x (scratch `zoom.gd`: Image.get_region + resize
  NEAREST) — GAME OVER in the banner's typeface inside the band, numbers without cell gaps ("131", "61:07"), "KO" the
  digits' size, even title spacing, "Character Select" clear of the inner frame; `asdbg` logs `banner letters 'WINERGADOSVM'`.
- Ranked: same with `esfake=7:2:15:1 --headless --to 5300` → `rank 1 saved true`, the cfg holds r1 with "beaten": 7.
- Gamemode menu: `ssw2.py run esm --every 25 --from 2650 --to 3500 --inputs "<BATTLE_PATH to 2660:A:4>,2900:Down:4,
  2950:Down:4,3000:A:4,3050:Up:4,3100:T200/44:4,3150:T149/85:4,3200:T149/85:4" newmodes=1 asdbg` → bars ALL-STAR /
  ENDLESS / EMPTY / EMPTY, EMPTY = buzzer, tap-tap ENDLESS → `session start (ENDLESS)`, select.
- Page layout: `tools/qol_preview.tscn … asrec asdbg` → `es_*` PNGs (new / 1st / 3rd / out / zero / cheats / 99999).
- ALL-STAR unchanged: an `allstar=1 asstart=22` one-hit-KO run (+ `asfakewin=9:59 asrec=…`) on the new code and on a
  `git worktree` of the previous commit (`GODOT` / `ROM` / `SAV` env set) → identical `AS` lines (only the art log's
  white-letter list gains "D").
- BOMB RAIN: settings page 9 shows GREEN DEMON + BOMB RAIN, page 12 RAINBOW KI only (preview `challenges*`, `weird3`).
- Off: `offcheck` PASS (21/21 + 1382 CHT, 221/221).

## 30. Part 39 (ULTRA INSTINCT, RANDOMIZER, FLIGHTLESS, SMASH KNOCKBACK)
Contact sheets: a scratch Godot script (Image.get_region + blit_rect, NEAREST zoom) over the capture PNGs.
- FLIGHTLESS: `ssw2.py run fl1 --battle --every 10 --from 4250 --to 4650 --inputs "4300:Up:80" cheats=flightless` →
  P1 holding Up only hops, both fighters back on the floor at once (CPU too); `fl2` (+ `infinite_ki`, X+A) → supers
  fired from the ground, knocked-back fighters arc down to the floor.
- SMASH KNOCKBACK: `kb1 --battle --headless --to 5300 --inputs <Y every 8 frames> cheats=smash_knockback cheatdbg` →
  "CHT knockback … xK velocity" lines, K = 1 + 2 × HP lost / max (x1.03 near full HP … x2.06 at 47 %).
- ULTRA INSTINCT effects: `ui2 --battle --every 2 --from 4116 --to 4176 cheats=ultra_instinct uiauto uidbg` → p4122
  "PARRY … stun", hit stop, P1 a silver-blue silhouette (blue hair) during the freeze, the game's guard spark, expanding
  silver silhouettes + sparkle ring, the attacker staggers (0x11). Taps: `ui4 --headless --to 5100 --inputs <B:3 every
  37 frames from 4150>` → windows open only in neutral / move / guard (not in hit stun 0xF / thrown 0x34), empty taps →
  "MISS" + lock 30, a real parry at f4631; `ui5` captures the red miss silhouette. Shots: `ui6 --headless --to 6500 uiauto`
  → "reflect" (ki blasts sent back: `ui7` shows the blast exploding on the CPU) and "ignore" (beams / super parts).
- Parry sound: `ssw2.py run se2 --battle --every 1000 --from 4000 --to 7320 --cfg <ABS path of a cfg with [sound]
  music=false> setest` → audio.wav, cut into 60-frame windows from port 4200 (32768 Hz): loudness / length / attack /
  spectral centroid / flatness per sound (DATA_NOTES part 39); 0x21 chosen.
- RANDOMIZER: `rz1 --battle --headless --to 6500 --inputs <X+A every 200 frames> cheats=randomizer,infinite_ki,
  infinite_health cheatdbg rzseed=5` → "super 2c as 0 -> N starts 2c" / "back to 0" pairs; `rz2` captures: portrait,
  face icon and sprite turn into Metal Cooler for the super, Goku again after. `rz4` (All-Star team `allstar=1 asp1=0,5,6`,
  X+A every 80 frames, `boss_characters`, no infinite health): 40+ supers, back on hits (act f / 0x11), a random
  ultimate (2e), the second member after a tag, no SCRIPT ERROR. `rz3` (+ `chaos_shuffle`, a won fight): back to the
  original at the win pose (fixed: it stayed the random fighter through the KO sequence).
- MP: `mp39 --battle --headless --to 5800 mp=1 mpbattle=1 p2inputs=… cheats=randomizer,ultra_instinct,infinite_ki,
  flightless,smash_knockback` → both players' supers randomized. LAN: `lan_pair.ps1 -tag p39_lan -cheats "randomizer,
  ultra_instinct,flightless,smash_knockback,infinite_ki" -hin/-gin <supers, B taps> -quit 2000 -extra "cheatdbg uidbg"`
  → lan_cmp exit 0, the same MISS / randomizer lines on both sides.
- Menu: `tools/qol_preview.tscn` states `p39_fighting(_on)`, `p39_characters`, `p39_challenges(_kb)` → 6 rows on pages
  5 and 7, 4 on page 9, descriptions fit the upper box.
- Off: `offcheck` PASS (21/21 + 1382 CHT, 221/221).

## 31. Part 40 (RANDOMIZER ultimates, FLIGHTLESS jump, SMASH KNOCKBACK off camera, HOT POTATO, RICOCHET KI)
- RANDOMIZER ultimates: `ssw2.py run rz6 --battle --headless --to 6500 --inputs <X+A every 250 frames from 4600>
  p1hp=4300:1500 cheats=randomizer,infinite_ki,infinite_health cheatdbg rzseed=5` → "super 2e as 0 -> 19 starts 2e"
  (Metal Cooler's own ultimate, 597 frames); `rz7` (+ `rzult`, X+A every 700) → Teen Gohan 2e, then Majin Vegeta
  "starts 2e (forced)" (its own test refused): its ultimate plays and KOs the CPU (`rz8` captures: cut-in, Final
  Explosion, 31 RUSH, face icon). Before the fix the test's 150 % was spent and nothing (or a plain super) started.
- FLIGHTLESS jump: `fl3 / fl4 --inputs "4300:Up:4,4380:Up:4,4460:Up:40" cheats=flightless,infinite_health fldbg` →
  peak 37 px, ~32 frames in the air (part 39: ~9 px); captures show the arc. Parameter sweep: scratch simulation.
- SMASH KNOCKBACK: `kb4 --battle --headless --to 7000 p1hp=4100:1500 cheats=smash_knockback,infinite_health cheatdbg
  kbdbg` → "KB … free" (tether undone, camera centre kept near the CPU), "off camera at x,y: -130 HP" every 20 frames
  (INFINITE HEALTH keeps the HP); `kb5` captures: the face-icon marker at the top edge, red on each tick, under the HUD.
- HOT POTATO: `hp1 --headless --to 6500 --inputs <Y every 30 frames> cheats=hot_potato hpdbg` → "fuse lit", "passed"
  both ways, "BOOM … HP 8506 / 13000" (30 %); `hp2` / `hp3` captures: countdown over the bomb over the holder's head,
  kept below the HUD, the game's explosion.
- RICOCHET KI: `rc1 --headless --to 5100 --inputs <A every 25 frames> cheats=ricochet_ki,infinite_ki,infinite_health
  rcdbg` → x / y bounces at the screen edges, up to 3 per shot, none outside the fight (part 40 fix: battle state 7);
  `rc2` captures: blasts bouncing back at the CPU.
- LAN: `lan_pair.ps1 -tag p40_lan -cheats "randomizer,flightless,smash_knockback,hot_potato,ricochet_ki,infinite_ki"`
  (+ blasts / jumps / supers both sides) → lan_cmp exit 0, the same 31 event lines on both sides.
- Menu: preview states `p40_ki`, `p40_potato(_on)`, `p39_challenges(_kb)` (all descriptions fit).
- Off: `offcheck` PASS (21/21 + 1382 CHT, 221/221).
## 32. Part 41 (marker / bomb sizes, VAMPIRE, TIME SKIP, DRAGON BALL HUNT, POWERS page)
- **Gotcha (PowerShell jobs):** inside `Start-Job { ... }` an UNQUOTED `cheats=a,b` argument loses everything after the
  comma (PowerShell array syntax): the run gets only `a` (part 41: a "Game Over" without INFINITE HEALTH, a TIME SKIP
  test without INFINITE KI). Quote it: `"cheats=a,b"`. Two instances in parallel are deterministic otherwise.
- SMASH KNOCKBACK marker: `kb6 --battle --every 15 --from 4940 --to 5240 p1hp=4100:1500 cheats=smash_knockback,
  infinite_health` → face icon 24 px 1:1 (its texture is 32x32 with the face at the top left; `kbdbg` before the fix
  printed `uv 0 0 512 512`) in a 28 px orange box, below the RUSH counter (y >= 57).
- HOT POTATO: `hp4` (hp3's inputs) → bomb 1:1 (11x12, crisp), countdown 5x7 digits (pop 2x on each new second).
- VAMPIRE: `vp1 --battle --headless --to 5900 --inputs <Y every 25 frames> cheats=vampire vpdbg` → "VP … heals 79"
  (198 x 2/5), beam ticks 120 → 48, both sides; `vp2` / `vp3` captures: green "+79", sparks victim → attacker, a light
  green pulse.
- TIME SKIP: `ts4 --headless --to 5000 --inputs <Y every 20> cheats=time_skip,infinite_ki,vampire tsdbg tsauto=4615
  tscpu=0 vpdbg` → "skips time", 6 hits land on the frozen CPU, "time runs again (time)" 120 battle frames later
  (+ hit-stop frames); `ts5` (`4615:Select:4`) = the real key; `ts6 --to 7000 cheats=time_skip tsdbg tscpu=60` → the CPU
  skips ("cpu"), one ended early by its own throw ("skipper action 2a"); `ts3` captures: violet tint, the skipper in
  its colours, the frozen fighter stone grey and still, ring in / out.
- DRAGON BALL HUNT: `db2 --every 4 --from 4150 --to 4330 cheats=dragon_balls,infinite_health dbdbg dbwait=60 dbgive=6
  dbhere=0` → grab of the 7th ball = WISH (HP / ki full, balls circle and fly off, gold flash); `db3` (dbgive=3,
  dbhere=70): a floating 5-star ball, HUD 3/7; `db4 --headless --to 6500 dbgive=3` → drops on hits >= 400 HP, both
  teams grab them again; `db5` captures: the drop (blinking gold while not grabbable), the edge marker of a ball off
  the picture. `texgap` + STAGE SHUFFLE: the game's texture blocks end by 0x19700 (the port block now 0x5D000-0x60000).
- All together: `st41 --headless --to 7500` with every part 39-41 cheat + Y / X+A / A / Select inputs → no script error.
- LAN: `lan_pair.ps1 -tag p41_lan -cheats "vampire,time_skip,dragon_balls,infinite_ki" -hin <Y every 20, Select 600 /
  1300> -gin <A every 30, Select 1000> -extra "tsdbg vpdbg dbdbg dbwait=100 p2hp=4300:6000 p1hp=4300:6000"` → lan_cmp
  exit 0, the same 18 VP / TS / DB lines on both sides (time skips by host and guest).
- Menu: preview states `p41_powers`, `p41_timeskip(_on)`, `p41_db(_on)`, `p41_help`, `p41_weird1` (13 pages, POWERS =
  page 10, descriptions fit; p39_challenges / p40_potato now press L 5 times).
- Off: `offcheck` PASS (21/21 + 1382 CHT, 221/221).
