# Tooling — what is needed for which job, and how to set it up

> **Read this part for…** tools already in the folder / a fresh Linux sandbox: first two tables · translation, export
> and delivery commands: Pipelines · sandbox pitfalls: Environment notes · Steam Deck / Proton slowness, pipelining,
> `perflog` fields: "part 26" · PERFORMANCE MODE, profile numbers, exact speed-ups and their checks: "part 32".
> Debug flags: docs/DEBUG_FLAGS.md.

The game itself only needs Godot. The reverse-engineering and verification tools run best on Linux (that is
where they were built: an Anthropic cloud sandbox, Ubuntu 24.04, 2 cores, no GPU). Nothing here is downloaded
into the game; everything except the user's ROM is open source. Record anything installed outside this folder
in `docs/WORK_OUTSIDE_FOLDER.txt`.

## Already in this folder (Windows)
| Tool | Path | Used for |
|---|---|---|
| Godot 4.7.2 (editor) | `tools/Godot_v4.7.2-stable_win64.exe/` | running/editing/exporting the project |
| Python 3.14.8 | `tools/Python3.14.8/` | `decomp/tools/*.py` converters (stdlib only) |
| melonDS 1.1 | `tools/melonDS-1.1-windows-x86_64/` (keys: `tools/melonDS-config/README.txt`) | playing the original side by side |
| headless melonDS core | `tools/melonds-headless/` (`libmelonds_headless.so`, Linux) | frame-exact references, RAM dumps |

Windows export: Godot → Editor → Manage Export Templates → download 4.7.2 (goes to `%APPDATA%\Godot\`).

## Linux toolchain (recreate in a fresh sandbox)
| Need | Version used | How |
|---|---|---|
| Godot Linux editor | 4.7.2-stable (official build) | github.com/godotengine/godot/releases → `Godot_v4.7.2-stable_linux.x86_64`; set `GODOT=` |
| Export templates | 4.7.2-stable | `Godot_v4.7.2-stable_export_templates.tpz` → unzip to `~/.local/share/godot/export_templates/4.7.2.stable/` |
| Display + GL | Xvfb, Mesa (llvmpipe) | `apt install xvfb mesa-utils`; runs use `--rendering-driver opengl3` on `DISPLAY=:99` |
| Python packages | Pillow, numpy (tests); pycparser + capstone (translator) | `pip install pillow numpy pycparser capstone` (or `CAPSTONE_PY=<capstone>/bindings/python`) |
| Ghidra | 11.4.2 + OpenJDK 21 | ghidra-sre.org release zip; `GHIDRA=<dir>` for `decomp/tools/transpile/run.sh` |
| melonDS headless | melonDS 1.1 source + `tools/melonds-headless/melonds_headless.cpp` | `tools/melonds-headless/build.sh` (cmake, ninja, g++) |
| Native GDExtension | godot-cpp (master @ 507ed9d8), API JSON from `godot --dump-extension-api`, CMake + Ninja, llvm-mingw 20260922 (UCRT) for the Windows DLL | `GODOT_CPP=… API=… MINGW=… GodotGame/new-game-project/native/build.sh [linux|windows|all]` |

The Windows DLL is linked statically (`-static`): it only imports KERNEL32 and the Universal CRT that ships with
Windows 10/11. Without the native library the game still runs (GDScript fallbacks), much slower.

## Pipelines
- **Assets** (reverse-engineering tools + reference): `python3 decomp/tools/build_all.py` → `decomp/extract/`, `assets/`.
- **Translation**: `tools/linux/regen.sh [gen|ghidra|all]` → `scripts/gen/ds_game.gd` (ARM9);
  `decomp/tools/transpile/run7.sh` → `ds_game7.gd` (ARM7). Details: `decomp/notes/transpiler.md`.
- **Lockstep references**: `python3 tools/melonds-headless/lockstep_ref.py` (see its header; large, keep outside git).
- **Export**: delivery = Windows only: `cd GodotGame/new-game-project && $GODOT --headless --path . --export-release
  "Windows Desktop"` (→ `finished/DBZ_SSW2_Port.exe`), then copy `docs/PLAYER_README.txt` → `finished/README.txt` and
  `docs/BUGFIXES.txt` → `finished/BUGFIXES.txt`. `tools/linux/export.sh` (native libs for both platforms + Windows and
  Linux exports into `finished/`) rebuilds `bin/`: never run it (or `native/build.sh`) while any game instance runs.
- **Delivering to the user's PC from a cloud sandbox**: files over ~25 MB are split, sent, committed into the
  folder and joined there (the exe is ~115 MB); check the MD5 after joining.

## Environment notes (cloud sandbox)
- Each shell call is time-limited (~10 min): run long captures with `nohup … &` and poll.
- `pkill -f <pattern>` can match and kill your own shell: find PIDs with `ps`/`pgrep` and `kill` them.
- Xvfb dies when the container restarts; `tools/linux/env.sh` restarts it.
- Capture mode renders every frame and runs at ~6–8 fps on llvmpipe; the intro run (2,210 frames) takes ~6 min.

## Session 1 part 26: Proton / Wine performance (Steam Deck report)
Report: the Windows build on a Steam Deck (SteamOS, GE-Proton10-34) ran below 60 fps in the menus and ~40 fps in
battles with dips to 17; the window size made no difference.

**Reproducing without a Deck** (cloud sandbox, nothing installed into the folder): GE-Proton10-34 release tarball
(github.com/GloriousEggroll/proton-ge-custom) unpacked; its Wine used directly: `WINEPREFIX=<dir>`,
`LD_LIBRARY_PATH=files/lib/x86_64-linux-gnu:files/lib`, `WINEDLLPATH=files/lib/vkd3d:files/lib/wine`,
`files/bin/wine64 wineboot -u`, then copy `files/lib/vkd3d/x86_64-windows/*.dll` into the prefix's
`drive_c/windows/system32` (Godot's exe imports dxgi.dll → wined3d → libvkd3d; Proton itself uses DXVK there).
`WINEFSYNC=1` = Proton's default thread synchronisation. Export the Windows build to a scratch folder with
`godot --headless --path … --export-release "Windows Desktop" <dir>/DBZ_SSW2_Port.exe`, copy the ROM next to it,
run `wine64 ./DBZ_SSW2_Port.exe [--headless | --rendering-method dummy] -- <flags>` on Xvfb (Mesa llvmpipe).
Under Wine the build uses OpenGL 4.5 core through Wine's opengl32 → host Mesa (no ANGLE: the export has no ANGLE
DLLs), thread model "safe", V-Sync on; Wine on Xvfb reports a 0 Hz refresh (FRAME RATE 60 then sets
`Engine.max_fps = 60` on top of V-Sync).

**Measurements** (2-CPU Xeon sandbox shared with other jobs; Linux export vs the same Windows export under Wine):
| What | native Linux | Windows exe under Wine |
|---|---|---|
| headless `turbo` CPU benchmark, Free Battle, 5400 frames | 53.3 s | 57.5 s (server sync) |
| game frame (game thread) in battle / menus | 10.3–10.8 / 4.1–5.5 ms | 10.4–10.6 / 5.1–6.3 ms |
| 3000 menu frames | 28.2 s | 30.5 s with fsync, 33.2 s without |
| `Time.get_ticks_usec()` / Semaphore post+wait / Mutex (µs) | 0.083 / 0.094 / 0.072 | 0.134 / 0.18 / 0.043 |
| DS thread switches (Godot thread hand-overs) per game frame | 0–3 | same |
| main-thread CPU per displayed frame (windowed, llvmpipe) | — | ~3 ms, of it ~2 ms GDScript (upload): GL calls + Wine thunks ≲ 1 ms |
So Wine adds 5–15 % CPU and nothing explodes (no per-frame sync storms, readbacks, file I/O or print spam; the
thread hand-overs are 1 + 0–3 per frame). Proton's fsync is on by default on the Deck.

**Root cause**: the per-frame work was strictly serial on the main thread: game frame(s) (the main thread blocked
in `DSMachine.step()` while the game thread ran) + picture upload + Godot drawing + GL driver + present. A displayed
frame takes `n × S + R` (n game frames, S ≈ one game frame, R = the rest); the pacing then needs n = frame / 16.7 ms
game frames next time, so the frame time settles at `R / (1 − S / 16.7 ms)`: with S = 14 ms, R = 4 ms → 25 ms
(40 fps), with S = 15.7 ms → 67 ms (15 fps); the smallest hiccup (a heavy effect, a loading frame) pushes it there.
A Deck core is about as fast as this sandbox's (battle S here 10.5 ms + Wine 5–15 % + Deck clocks under load), so
battle frames sit right at that edge — independent of the window size, as reported.

**Fix (part 26)**: *pipelining* in `GameDS` (scripts/game/game_ds.gd, `_pipe_*`): the next game frame is started on
the game thread from `RenderingServer.frame_pre_draw` (after every script of the frame ran and the picture was
uploaded) and joined at `SceneTree.process_frame` / `physics_frame` / `GameDS._input` (before anything can read or
write game memory again; all QoL input goes through `GameDS._input`). Drawing, GL driver work and present now run
while the game computes the next frame: a displayed frame costs max(S, R) instead of S + R, so the Deck holds 60 fps
while S < 16.7 ms. The game gets the same input per frame and runs the same frames (scripted Free Battle with
pipelining: all 1382 `CHT f` lines up to 5300 identical to the capture-mode reference); only the input is sampled
before the present instead of after it, so `pipeline=auto` (default) switches it on only when displayed frames
come late (> 1.3 game periods apart in > 10 % of frames, smoothed) while a game frame takes > 30 % of a period (off below 20 %):
a fast PC never uses it. Never in captures / pilot / turbo / snap / fxdump runs; headless runs never draw, so the
pacing test is unaffected. Quitting with a frame in flight waits for it (`_exit_tree`). `DSMachine.step()` is now
`step_begin()` + `step_end()`; `run_us` (game-thread time of the last frame) and `switches` (DS thread switches) are
recorded for the log.
A/B with `--rendering-method dummy fakerender=6` (no GPU work, 6 ms of simulated driver/present per frame, editor
binary, sandbox contended): Free Battle serial 12–20 fps (game 42–53 frames/s), pipelined 21–39 fps (46–56/s).

**Player tool: `perflog`** (scripts/game/ds_perflog.gd): command-line flag `perflog`, or environment variable
`DBZ_PERFLOG=1` (Steam → game Properties → Launch Options `DBZ_PERFLOG=1 %command%`; for a non-Steam shortcut the
same). Writes `perflog.txt` next to the exe (user:// if read-only): a header (OS, Wine/Proton environment, CPU,
GPU/driver/API, renderer, thread model, V-Sync, max_fps, refresh, window) and every 5 s: fps, game frames/s, game
frames per displayed frame (histogram), frame time avg/p95/max, `run` (game-thread ms per game frame), `wait` (main
thread blocked on the game), `main`, `pipe` (% pipelined), `render` / `gpu` (viewport CPU / GPU ms), thread switches.
`game` below 59.8 = the game itself slows down; `run` near 16 ms = the CPU is the limit; `render`/`gpu` large =
driver / GPU. Debug flags: `pipeline=0|1|auto`, `pipedbg` (prints when auto switches), `fakerender=MS`.

**Only confirmable on the Deck**: the real `run` time there (Zen 2 under the shared 15 W budget), the GL driver /
present cost through Proton + gamescope (radeonsi; the sandbox only has llvmpipe), what refresh rate Wine reports
under gamescope (0 Hz → the 60 fps limiter on top of V-Sync), a gamescope frame limit set in the Deck's quick menu
(caps the FPS counter), and fsync. Ask for a `perflog.txt` from a battle if it is still slow.

## Session 1 part 32: performance mode (Steam Deck perflog)
**The Deck log** (Windows build under Proton, radeonsi, window 2X, V-Sync 60, pipeline auto): menus and light scenes
60 fps (game frame `run` 6-11 ms, `pipe` 95-100 %); battles `run` 13-15 ms average (max ~30), 1.4-2.3 game frames per
displayed frame (3+ in up to 40 % of them), 24-45 fps, game speed 55-60 / s, `main` 8-25 ms, GPU 1.6 ms (idle). Why
`main` balloons with 2-3 steps: every game frame beyond the pipelined one runs synchronously in `GameDS._process`, so
the main thread waits a whole game frame each time (`wait` 20-33 ms there); a displayed frame then costs
`(n - 1) x run + max(run, picture + draw)`, which needs n = 2-3 game frames again next time (the spiral of part 26,
only shifted). The game thread itself idles while the main thread does its share between two game frames (bookkeeping
+ reading the picture + the other nodes' scripts + Godot until `frame_pre_draw`): with run 14 ms + ~2.5 ms of such gap
a 16.7 ms refresh does not fit, and the speed drops to 55-58 / s. The 250-690 ms spikes are game-thread frames
(`run max` 216-627 ms) at scene changes: file reads + decompression in the translated code (HANDOFF next step 3).

**Profiling tools (part 32)**: perflog has a second line per period, `PERFLOG f<N> split` (fields in
`scripts/game/ds_perflog.gd`): game thread per game frame = `arm9` (translated code of all DS threads, DMA, scanline
loop) + `tmr` / `cap` / `irq` / `a7` (ARM7 driver) / `mix`; main thread per game frame `in` / `out` (`qol`, `aud`); per
displayed frame `pic` (`read` = the part before the next game frame starts in PERFORMANCE MODE; `3d`, `wait`, `tex`),
`geo` (native geometry, worker thread), `gap` (main-thread time between the end of a game frame and the start of the
pipelined next one, `after GameDS` = the part spent in other nodes / Godot), `cpu` (process CPU ms per game frame,
Linux /proc only), `performance on / off, 60 / 30 fps`; `PERFLOG f<N> performance ...` lines at start and at every
switch. Scanline timers only run with `perflog` / `perf` (`noprof`: without them). `perfmark=F1,F2` prints the process
CPU time at those game frames. Benchmarks on this VM were noisy (2 cores shared with another agent's runs: battle game
frames 9-23 ms depending on its load), so every speed-up below was measured **in one process, interleaved** (old and
new code on alternate frames or calls, outputs compared for equality), scripts in /tmp/ssw2/pm (bench.sh = headless
turbo heavy Free Battle with supers, prof.sh = real time, mkab.py / proj_exp = A/B copies).

**Profile** (editor build, heavy Free Battle with infinite ki supers; per game frame unless noted): game thread 10-13 ms
in battle, 5-7 in menus: translated ARM9 code ~65-75 %, ARM7 driver 1.0-2.3, per-line 2D register capture 1.0-1.9,
timers 0.2-0.4, HBlank / VBlank handlers < 0.3, native mixer 0.2-0.6, scanline loop + clock reads ~1. Per battle frame
~2,000 IO writes (1,350 geometry command words), 160 IO reads, ~1,300 dynamic loads, ~1,600 dynamic stores, ~100
indirect calls, ~20 native fast paths. Main thread: input 0.1, after-frame 0.25-0.5 (QoL 0.1, audio resampling
0.12-0.2); per displayed frame the picture 1.3-2.5 ms in menus, 3-9 ms in battle (headless / dummy renderer): VRAM
views 2-5 ms (BG 1-1.8, OBJ 0.7-1.3, 3D textures 0.8-1.5: re-copied whenever a bank changed, i.e. every battle frame),
3D mesh 1-4 (surfaces 0.4-2.7, new materials 0.1-0.45), plus 0.6-3.9 ms of other nodes / Godot before `frame_pre_draw`.

**Exact speed-ups, always on** (same RAM / pictures / sound; scripts/core, scripts/render):
| What | before → after |
|---|---|
| per-line 2D register capture (`DSMachine._capture_line`): only a 128-byte compare per engine and line on the game thread; the 192 lines are built when the picture asks (`line_regs(e)`) | 1.0-1.4 → 0.26-0.29 ms per game frame (+0.16-0.24 ms per displayed frame on the main thread); 0 mismatches over 6,000 frames |
| geometry command words in `io_write` (size 4, 0x04000400-5FF): stored + logged without the general path's checks | 1.4-1.6 → 0.9-1.25 µs per call (≈ -0.6..-0.9 ms per battle frame) |
| no clock reads in the scanline loop unless profiling (5 per line), ARM7 `advance` short path when no alarm is due, typed core access per line | (part of the total below) |
| game thread in total (interleaved A/B, alternate frames, same run) | menus 7.0 → 5.7, 6.9 → 5.5 ms; battle 10.2 → 9.2, 11.4 → 10.3, 12.9 → 10.9, 11.9 → 10.2 ms (-10..-20 %) |
| VRAM / texture views (`DSHardware.region_view`, `_slot_view`, `slots_view`): one native copy per page (`DSMemNative.blit`) into a zeroed buffer instead of slice + append | 0.68 → 0.12 ms per view (3-5 per battle frame); 0 mismatches over 4,600 views |
| translucent 3D materials kept frame to frame (`DSRender3D._tm_cache`) | -0.1..-0.45 ms per displayed frame |

**PERFORMANCE MODE** (settings BIG CHANGES, `QoLSettings.performance_mode`, `QoLController.apply_performance()`, debug
`perfmode=1`; GameDS `# PERFORMANCE MODE` comment block): never touches the emulated machine. (1) pipelining always;
(2) `DSDisplay.refresh()` = `refresh_read()` (everything read from the emulated machine, while it is parked) +
`refresh_apply()` (texture uploads, 3D mesh, shader parameters); in performance mode the apply half runs in
`_pipe_start` after the next game frame was started, so the game thread no longer waits for it (measured: of `pic` 4.9-8.8
ms in battle only `read` 0.9-1.6 ms stays before the start, in menus 0.5-0.9 of 1.6-1.8; `gap` in battle 6.2-10.6 → 4.2-6.5
ms); (3) no in-between frames (every FRAME RATE acts as 60). (4) A steady half rate was built and measured but is **off
by default** (`perfhalf=auto` adaptive: Engine.max_fps 30 while one game frame + gap takes > 90 % of a refresh and > 35 %
of the pictures come late but two fit in a 30 fps picture, back to 60 when one fits in 80 %; `perfhalf=1` always 30; never
in a LAN battle): with Deck-like battle frames (run 13-14 ms, two instances at once) it made the pictures mostly 2 game
frames each but gave 22-29 fps instead of 27-48 fps at the same game speed (57-60 / s), because Godot's frame limiter lets
a picture follow at once after one that ran late, so the cadence is not steady anyway. `fakeslow=MS` (debug) makes every
game frame MS longer (a slower CPU's game thread). End-to-end numbers on this VM depend on the other agent's load (battle
game frames 9-23 ms). **End to end** (two instances at once so both see the same load, windowed with the dummy renderer,
60 Hz limiter, 2 ms of simulated driver / present per picture (`fakerender=2`), heavy Free Battle, battle game frames
13 ms = Deck-like): off 38.9 fps, game 57.56 / s, 1.70 game frames per picture (3+: 14 %), picture p95 67 ms, main
13.2 ms, gap 3.75 ms → PERFORMANCE MODE 43.5 fps (+12 %), 58.73 / s, 1.43 (3+: 9 %), p95 55 ms, main 6.9 ms, gap 1.81
ms; menus 59.3 / 59.5 fps both, picture p95 20.4 → 17.8 ms (/tmp/ssw2/pm/g_off.log, g_on.log). The expected Deck
effect is in DATA_NOTES part 32.

**Checks** (all on the final tree): performance mode off: off23 battle script (`/tmp/ssw2/pm/off32.sh`) 21/21 PNGs +
1382 `CHT f` lines identical to /tmp/ssw2/btn; intro (`cap.sh 10 2210 10`) 221/221 PNGs identical to /tmp/ssw2/intro
(audio.wav: identical samples; its length varies by ~1 frame from run to run with the old code too); headless pacing
(`pacelog fakehz=N maxfps=N quit_at=1300`) 59.8 at 60/0, 60/60, 144/144, and with `perfmode=1` 30/30, 60/60 (+ `perfhalf=1`),
240/240. On: captures with `perfmode=1` (exact path) 21/21 + CHT identical; real-time windowed (dummy renderer, 60 Hz,
pipelined, half rate switching) Free Battle script: all 1382 `CHT f` lines up to 5300 identical (settings from an empty
`qolcfg=`: the shared user settings.cfg had BOMB RAIN on, which changes the battle). LAN `lanbattle=1` (/tmp/ssw2/pm/lan32.sh):
the guest's per-frame hashes with performance mode on and off are byte-identical; both runs (and one with both sides off)
hit the same DESYNC at L277 with this tree's LAN code, independent of performance mode (reported to the main agent;
later found to be a harness mistake — `lanbattle=1` without `lanteams` / `lanbstage`, DATA_NOTES part 32 "combined
verification").

**Native changes that would help** (not built: rebuilding the library breaks running games): geometry commands as a
packed int log instead of one `[addr, value]` Array per word (~1,350 allocations per battle frame); a scanline batch
in C++ (timers + register-block compare + mixer advance for N lines); FS_ReadFile / decompression fast path for the
scene-change spikes.
