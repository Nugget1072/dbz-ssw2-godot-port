# HANDOFF — living state of the port

_Last updated: 2026-10-04 (session 1, part 8)_

## How to see it
1. `tools\Python3.14.8\python.exe decomp\tools\build_all.py` (≈30 s; writes `decomp/extract/` and `GodotGame/new-game-project/assets/`)
2. Open `GodotGame/new-game-project` in `tools\Godot_v4.7.2-stable_win64.exe`, press Play (F5).
   The default scene is now **the original game running in Godot** (`scenes/GameDS.tscn`): power-on → logos →
   intro movie → attract-mode battle → title → menus. It reads the ROM and save from `baseroms/`.
   Keys: arrows, X = A, Z = B, S = X, C = Y, A = L, D = R, Enter = Start, Backspace = Select;
   mouse = touch screen (lower screen). The old hand-built battle scene: `-- scene=res://scenes/battle/Battle.tscn`.
   **Finished build**: `finished/DBZ_SSW2_Port.exe` (+ `libdsnative.windows.x86_64.dll` next to it) — double-click.
   The `finished` folder is portable: the ROM is built into the exe (`res://data/game.nds`, copied by
   build_all.py, git-ignored); a ROM in `../baseroms`, `./baseroms` or the exe folder takes precedence. F11 = fullscreen.
   Controls + fun facts for players: `finished/README.txt`. Its save is `finished/DBZ_SSW2_Port.sav`, created from `100Save/` (or the
   copy built into the exe) so everything is unlocked; delete it to return to the 100% save. Editor runs use
   `user://save100.sav`. `baseroms/` and `100Save/` are never written. Folder map: `README.md`.
   Comparison captures (`capture=...`) freeze the clock at 2026-01-01 12:00 like tools/melonds-headless does:
   the game seeds its random numbers from the clock.

## Architecture
The whole ARM9 program (3,290 functions incl. NitroSDK) is decompiled with Ghidra and translated to GDScript
(`scripts/gen/ds_game.gd`, class `DSGame`). It runs on an emulated ARM9 memory map with the hardware modelled at
register level (VRAM banks, DMA, IPC, card, IRQs, DIV/SQRT, BIOS calls) and the ARM7 replaced by high-level
services. Godot draws each frame from the emulated VRAM/registers (2D engines: one shader per screen; 3D: the
geometry commands are turned into a mesh and drawn by the GPU with DS rules). See `decomp/notes/transpiler.md`
and `decomp/DATA_NOTES.md` ("Display output rules").

## Done (with proof)
| Area | State | Proof |
|---|---|---|
| Ghidra + transpiler pipeline (`decomp/tools/transpile/run.sh`) | 3,304 / 3,304 functions (14 callbacks/IRQ handlers found in part 5) | parse-checked |
| Battle logic, frame-exact | H | lockstep from a battle snapshot (18 frames): main RAM identical except the sound-stream buffers |
| **Sound**: original ARM7 sound driver translated (`scripts/gen/ds_game7.gd`) on register-level sound hardware | H | intro music correlates 0.96–0.99 with the game's own stream data; touch/menu SFX envelopes match melonDS frame-exactly (level within ~10 %) |
| DS threads (Godot threads with a baton), hardware timers, OS_Halt / VBlankIntrWait time model | H | battle lockstep still exact; intro/menu captures unchanged |
| Power-on → logos → intro → attract battle → title (2,200 frames, no input) | H | frame captures vs melonDS: 107/220 sampled frames pixel-identical, 74 more within 500 px (3D edge rounding), see below |
| Title screen → touch → main menu | H | identical except blink phase of the cursor |
| Save memory (user's `.sav`, CRC-checked by the game) | H | game accepts it (no "save data corrupted" screen) |
| Renderer: 2D engines A/B, 3D (textures, translucency, polygon IDs, clear plane), fades | H | as above |
| Title → main menu → character select → battle (scripted inputs, frozen RTC on both sides) | H | same random opponent/stage as melonDS; screens match |
| Performance (cloud VM, 2 cores, software GL): menus 7–10 ms/frame, battle ≈23 ms (game 14–20 ms in parallel with the 3D geometry on a worker thread, main-thread drawing 3.5 ms). The user's i7-13700HX runs Python-style code ≈1.7× faster than the VM, so battle should be ≈10–12 ms there | M | `perf` flag; `tools/bench_gx.gd` |

### Comparison method (repeatable)
- Reference: `python3 tools/melonds-headless/mhs.py ROM SAV - - OUTDIR run:1 shot:r1 ...` (one PNG per frame).
- Port: `godot --path GodotGame/new-game-project res://scenes/GameDS.tscn -- capture=DIR cap_every=N cap_to=M
  [cap_from=A] [inputs=FRAME:Start:4,FRAME:T128/120:6] [dumpvram=F] [perf]` → `DIR/p<frame>.png`, frame-exact
  (the game pauses while each screenshot is taken).
- Each port frame is matched to the closest melonDS frame (the original has lag frames while loading; the port
  does not), then the pixel difference is counted.

## Fixed this session (all were real translation/emulation bugs)
- BIOS calls had no arguments (GetCRC16 checksummed nothing → "save data corrupted"); BIOS wrappers are now
  declared `f(r0..r3)` and run as HLE (CpuSet, CpuFastSet, GetCRC16, Sqrt, WaitByLoop).
- Computed calls with stack arguments (sound stream callback) lost arguments 5–6.
- 64-bit IO stores (DIV/SQRT operands) were truncated → all camera/rotation matrices were zero → no 3D.
- Negative pointer offsets computed in unsigned 32-bit (LZ77 back-references) read address 4 GiB+ → corrupt
  decompressed menu graphics.
- EEPROM addresses now wrap at the chip size; 8-bit VRAM writes are accepted (DS, unlike GBA).
- Renderer: Y orientation, reverse-Z, Godot's approximate sRGB round trip (pre-compensated per 6-bit level),
  6-bit colour pipeline, DS brightness/blend formulas, integer vertex snapping after clipping, texel sampling at
  the pixel corner, one-frame 3D latency, translucent polygons (were never drawn), same-ID translucency rule.

## Part 5 (performance)
- 3D geometry engine (DSGX) 3.5× faster with identical output (`tools/bench_gx.gd` md5 over 60 battle frames;
  intro captures and battle frames pixel-identical to before): packed command decoding, per-vertex commands
  handled in the word loop, outcodes for trivial accept/reject before clipping, no per-vertex Array allocations.
- DSGX now runs on a worker thread while the game emulates the next frame (its result is drawn one frame
  later, which the DS does anyway). `gxthread=0` turns it off.
- Profiling tools: `PROFILE=1 ./regen` build (own time per translated function), `gxdump=FROM:N` (saves the
  geometry commands for the benchmark).
- Translation gaps closed: 14 functions only referenced as callbacks (IRQ handlers, task callbacks) were
  missing and silently did nothing; the game-over setup 0x0209E1A4 did not translate (PTR_ global types).

## Part 6 (user bug list: stages, flicker, menus, speed, unlocks, controls, exe)
- **3D stages**: back-face culling now uses the homogeneous triple product (screen-space culling after clipping
  culled visible polygons → holes in Ice Field / New Planet Vegeta / Korin / Uninhabited Island ground); seams in
  ice and rock models were texture sampling outside the triangle (UVs clamped to each triangle's UV box) plus
  DS span coverage (triangles dilated by 0.46 px). Stages checked side by side with melonDS.
- **Heavy-hit flicker**: during hit-stop the game sends no SWAP_BUFFERS; the DS keeps showing the last polygon
  list. Polygons now accumulate until SWAP_BUFFERS (`acc_*` in DSGX), the last list is redrawn otherwise.
- **Menus**: Practice / Story / Data File lost their 3D (untranslated veneers) and Story select ignored A (missing
  callbacks) — fixed in the translator (veneer aliases, literal-pool scan, 3,316 functions). Story → map →
  "dragon ball" text screens advance; Z-Battle → team select → battles → opponents' teams; Free Battle, Options,
  VS menus work. **Maximum mode hung** loading its battle: MI_StopDma (0x020AB738) wrote DMAxCNT at the wrong
  address (translator scaled `&DAT_040000b0 + n` by 4), so the card DMA never stopped and the card IRQ handler
  waited forever; also the card IRQ fired inside the DMA loop and rewriting an enabled DMA restarted it. All
  three fixed (translator, DSHardware, io_write); Maximum → rank → board → battle now runs. Z-Battle is a
  survival series (Trunks, Gohan, Goku, Krillin… ran 25,000 frames); losing → Game Over → No → title works.
- **100% save + controls**: `100Save/` seeds the port's save (all characters, stages, modes unlocked). Keys:
  L = A, R = D, Y = C.
- **Speed** (release build, cloud VM; the user's PC is ≈1.7× faster): battle ≈6 ms emulation + 1 ms drawing per
  frame; native GDExtension `native/` (C++ ports of the 3D geometry engine, the sound mixer, the SDK memory
  functions and the file-system path lookup, all output-identical); OS_SpinWait lets emulated time pass (the SND
  command wait spun for 20 s); frame pacing follows the display (one game frame per refresh on 60 Hz screens,
  time-based otherwise, up to 8 catch-up steps); audio is resampled by ≤ ±1 % to hold a 70 ms queue (no clicks).
  Screen changes that load ~200 files still take 90–210 ms on the cloud VM (was 140–330 ms).
- **Input**: a key or touch tap shorter than one frame now still counts for one frame (taps were being missed).
- **Windows build tested on the user's PC** (2026-10-04): boots, intro → title → mode select → Free Battle →
  Ice Field battle, keyboard and mouse touch working.
- **Debug helpers**: `snap=DIR snap_every=N` (real-time screenshots), `clamp=`, `poke=`, `dumpram=`, `quit_at=`,
  `pacedbg`, `profslow=N`, `fsnative=0`, `cap_fast`.

## Part 7 (user list: Maximum rank screen, MODE SELECT bar, Map Clear count, Y key, save location, tidy)
- **Maximum rank select** drew its rank bars black: 3D texture palettes above 32 KiB were read from the wrong
  place (shader masked addresses with 0x17FFF). Fixed; matches melonDS.
- **Scrolling MODE/CHARACTER SELECT bars** flickered at the seam between their two quads: the quad's two
  triangles were each dilated across the shared diagonal and sampled slightly different texels there. Inner
  edges (quad diagonals, fan edges of clipped polygons) are no longer dilated (DSGX + native, identical output).
  Translucent polygons at equal depth now fail the depth test like on the DS (shine overlays).
  Cost: intro capture match 115 -> 109 exactly matching frames (the others differ by a few pixels in thin
  textured quads); stage comparisons unchanged (Korin median 26.7 k px, as before).
- **Story "Map Clear 3/14"**: translator bug — 12 functions with literal-sized stack frames overwrote their
  callers' frames. Fixed in ghidra2gd.py; now 14/14 like melonDS. Main-thread synthetic stack 12 -> 15 KiB.
- **Keys**: Y moved to C. **Save**: next to the exe, rebuilt from the built-in 100% copy when missing/damaged.
- **Folder tidy**: transfer leftovers removed, `docs/` for the brief and methodology, `README.md` folder map.

## Part 8 (user list: bar still shaking, portable folder, controls txt)
- **Scrolling bars (MODE SELECT, CHARACTER SELECT, ...)**: the real cause was clipping. The DS clips a quad as one
  polygon; the port clipped its two triangles separately, so where the bar crossed the screen edge each half got
  different clip vertices and the integer-snapped edges stepped by 1 px from frame to frame. DSGX / DSGXNative now
  clip quads whole (`_quad4` / `quad4`, fan-split after clipping, diagonals not dilated). Verified: mode-select bar
  rows 12/29 (of the bar strip) in all 256 columns over 65 consecutive frames, character-select bar black row 368 /
  white 369 over 32 frames — both identical to melonDS; the exported exe gives the same. GD vs native parity
  (`tools/cmp_gx.gd`) exact on a 120-frame menu dump and a battle dump. Bonus: intro capture match 109 -> 161
  exactly-matching frames (of 221), total diff px 269 k -> 216 k. Lockstep boot: only the stack-address bytes
  from the part-7 stack resize differ vs the older baseline; t1 unchanged (known diffs only).
- **Portable folder**: the exe embeds the ROM (exe ≈ 181 MB) and the 100% save; nothing outside `finished/` is
  needed. Tested by copying the Linux export into an empty directory with no baseroms/100Save/app data: it boots
  to the title and mode select and creates `DBZ_SSW2_Port.sav` beside itself. Same test with the Windows exe on the user's PC (copy in a
  folder with no baseroms nearby): boots, reaches mode select, steady bar. The DLL only imports
  KERNEL32 + the Universal CRT (part of Windows 10/11); Godot uses ANGLE automatically if OpenGL is missing.
- `finished/README.txt`: controls (keyboard + gamepad) and a few fun facts. F11 toggles fullscreen.

## Next steps (in order)
1. User feedback on the finished exe (`-- perf` on the exe's command line prints timings every 600 frames).
2. Z-Battle course end: play a full course (or find the course-progress variable and `poke=` it) and compare the
   ending screens with melonDS; the same for Maximum / Dragon Balls / VS (wireless VS needs a second DS: show a
   message instead).
3. Screen-change hitches: the remaining cost is FSi_SendCommand (0x020AE998) + FS_ReadFile through the CARD
   worker thread, ~7 commands per file. A native FS_ReadFile for the memory/ROM archive is the next fast path.
4. QoL: single-screen layout (flag exists in DSDisplay; needs touch remapping and a toggle key).
5. 3D exactness: per-span attribute interpolation like the DS (pass the polygon's vertices to the shader) would
   remove the remaining texel differences of quads; translucent-over-translucent blending (DS: blend only where destination alpha ≠ 0, alpha =
   max) and DS edge rules for diagonal edges (≈1–2 k px per frame in the intro's scaled-portrait scene).
6. Random-looking effects (TV-noise intro scene) differ: the original seeds them from timers the port does not
   emulate cycle-exactly.

## Known differences vs the original
- Sound capture unit (used by some effects) is not emulated; mixing has no interpolation (melonDS default too).
- No lag frames (the original drops frames while loading); timers are not cycle-accurate.
- RTC uses the host clock; touch uses the firmware calibration.
- Boot RAM lockstep (`lockstep/boot`) aligns well until the first heavy load (port frame ~188) and then the
  aligner loses track (lag frames); the screen captures show the port stays in sync visually.
