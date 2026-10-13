# LAN MULTIPLAYER — research results and implementation design (part 30)

> **Read this part for…** the architecture in one table: 0 · determinism / why lockstep, no rollback: 1 · frame gate,
> input delay, record format: 2 · guest battle view: 3 · select / stage / battle flow: 4 · transport, handshake,
> settings snapshot: 5 · menus + battle abort: 6 · files / hook points / QoLLan API: 7 (+7.1) · **test harness and every
> LAN debug flag: 8** · phases and what was built (parts 30-31): 9.1-9.3 · risks: 10. Status: implemented and QA'd in
> the VM (parts 30-32); not yet on two real PCs. Facts: DATA_NOTES part 30-32 sections (decomp/DATA_NOTES_INDEX.md).

Written by the LAN research agent (session 1 part 30). Facts with confidence and ARM9 addresses are in
`decomp/DATA_NOTES.md`, "Session 1 part 30 findings (LAN research)". This document repeats what implementers need and adds
the design. It builds on LOCAL MULTIPLAYER (docs/MULTIPLAYER_DESIGN.md, parts 27-29: QoLMp session, scene redirects in
`f_02001014`, P2 input via `f_0202dce0` → `MP_AI_OUT`, two-outline stage select, MP panel art, dual assists, Team Arts light).

Evidence: `/tmp/ssw2/lan_research/` — scratch copy of the project in `proj/` (debug code only there, sections
`# ---- LAN RESEARCH (debug)` at the end of `scripts/qol/qol_game.gd` and `scripts/game/game_ds.gd`, plus `lanr_w` in
qol_mp_input.gd), runners `run.sh` (headless turbo, per-frame hashes) and `runc.sh` (captures), inputs in `inputs.sh`,
comparison tools `tools/cmp.py` / `tools/bdiff.py`, results in `runs/<NAME>/hash.txt` (+ RAM dumps `hash.txt.r<R>.bin`) and
`runs/<NAME>.log`, ENet tests in `enet/`.

Rule for everything below (as for LOCAL MP): **with no LAN session every override only calls `super`** (off-identity:
/tmp/ssw2/btn via an off23.sh copy, /tmp/ssw2/intro via cap.sh 10 2210 10), and LOCAL MP must stay unchanged (part-27/28/29
QA scripts).

---------------------------------------------------------------------------------------------------------------
## 0. The architecture in one page

| Step | Where | What the port does |
|---|---|---|
| VS BATTLE → LOCAL / **LAN** | scene 0x11 state 2 (already relabelled, `f_0207b778`) | LAN opens the port's LAN pages (QoLLanMenu) over the screen's hexagon BG1, like the LOCAL setup page |
| HOST / JOIN, warnings, name / IP entry, connecting, lobby | still scene 0x11 state 2 | port pages + on-screen keyboard (QoLKeyboard); ENet session (QoLLan / QoLLanNet); host's cheats + weird snapshot applied on the guest (never saved) |
| host: "GO TO CHARACTER SELECT?" → guest ACCEPT | both machines | `f_0207b778` returns **1 (the game's HOST path)** on both → party +0x33 = 1, +0x32 = 1, **scene 4 in mode 2** = the game's own wireless-VS team select (Z-Battle look, READY? GO / BACK) |
| team select | scene 4 (FUN_02066558), mode 2, each machine alone | the game's single-player select on each machine; GO is held until the other player is READY (`f_0206cc94` hook) → picks exchanged → the game's own exit goes to scene 5 (mode 2 + host flag) |
| stage select | scene 5, both machines | LOCAL MP two-outline code; the local player drives its outline, the remote outline comes from the network; both chosen → **host** does the 50/50 and sends the result; roulette on both |
| battle | scene 7 asked by the game → `f_02001014` redirect → **scene 0, mode 5** | battle-start sync at `f_020140c8` (party, stage, RNG, id counter, host's save copy, port RNG seeds) → **deterministic lockstep with input delay**: host = P1 (left, DS pad + DS touch), guest = P2 (right, `f_0202dce0` → MP_AI_OUT), the same code on both machines |
| battle lower screen | | host: the game's own panel (side 0). guest: port-drawn side-1 panel in the game's single-player layout (QoLLanPanel, QoLMpPanel art) — taps at the same coordinates = side-1 panel coordinates. PING under Team Arts, "WAITING FOR PLAYER" band |
| battle end / pause exits | `f_02001014` from scene 0 | → scene 4 (mode 2) on both (lockstep ends at the same frame on both); B in scene 4 with no picks → the game's own exit to scene 0x11 = lobby |

Rollback is **not** feasible (section 1.7); the original game's own wireless mode is lockstep too (FUN_02079430 /
FUN_020789A8: the battle frame runs only when both pads arrived), and it makes its battle RNG deterministic exactly the way
this design does (FUN_020019FC(1), section 1.1).

---------------------------------------------------------------------------------------------------------------
## 1. Determinism (research question 1) — results

### 1.1 Method and runs
Free Battle (btnrun menu path, P1 Goku vs Goku), battle anchored at the battle init FUN_020140C8 ("r" = frames after it),
identical relative battle inputs (`lanin=` P1, `lanin2=` P2 in `mpbattle=1` runs), per-frame MD5 of the battle globals
block (G = u32 0x020DE3A0, 0x1C000 bytes: fighter records, team blocks 0x020DE3D0, effect pool, camera, timers), of every
64 KiB block of main RAM, the battle RNG, input-call / RNG-call counts, plus a "gameplay hash" (1.5). 2600 battle frames
each (VS intro, fight, tags, supports, Team Arts taps, pause + continue, KO, Game Over screen, back to the select).

| Pair | Histories | Synced at FUN_020140C8 | Result |
|---|---|---|---|
| A1 / B1 | fresh boot rtc 2026-01-01 / menus 97 frames later, rtc 2026-07-15 | nothing | **diverge**: RNG state differs from r1 (and the random stage icon chose another stage: 0x0E vs 0x0A); G block differs from r262, RTC reseeds of the RNG at different calls |
| A3 / B3 | as A1 / B1, CPU AI P2 | stage, RNG (FUN_020019FC(1)) | **G block identical all 2600 frames**, RNG + call counts identical; RAM differs only in 16 static bytes (save time stamp, sound work) + the music stream buffer (block 0x022E…) |
| A3 / C3 | fresh / **a previous battle** (other characters, other stage, paused → character select → same picks), rtc 2026-03-03 | stage, RNG | G differs from r2 — only in object ids offset by 0x19 (instance-id counter u16 0x020DD7B4) |
| A3 / C4 | as C3 | stage, RNG, **id counter = 0** | **G identical all 2600 frames** |
| A5 / C5 | fresh / previous battle, **MP battle** (P2 human via f_0202dce0, P1 taps: tag, Team Arts), ONE HIT KO, KO → Game Over → select | stage, RNG, id counter, party | **G identical all 2600 frames** incl. KOs, tags, battle end and the Game Over screen; RAM differs only from r2360 (the next select scene) |
| EA / EC | as A5 / C5 + RANDOM CHARACTERS, RANDOM STAGE, CHAOS SHUFFLE (46-48 swaps, file loads mid-battle), STAGE SHUFFLE, RANDOM MUSIC, BOMB RAIN, INFINITE HEALTH | + port RNG seeds (`qolseed`) | **G identical all 2600 frames** — although RANDOM MUSIC played a different BGM on each side (music_seed not synced: BGM 4 vs 13) |
| EA2 / EB2 | as EA, B-type history | everything but the RNG | **diverge** at the first battle RNG call (r1832) |
| A6 / D6 | same history; D6 with CAMERA ZOOM 4, DETAILED SHADOWS, DAMAGE NUMBERS, INPUT DISPLAY | all | G block differs (drawing-only fields, 1.5) but the **gameplay hash identical all 2600 frames** |

Commands: `source /tmp/ssw2/lan_research/inputs.sh; ./run.sh A3 6040 "$MENU" rtc=… lanin=$BAT lanhash_to=2600
landump=1,2,312,600,1500,2600 lansync=stage:0e,rng` (see inputs.sh for BAT / BAT5 / P2B / PRE2), compare with
`python3 tools/cmp.py runs/A3/hash.txt runs/B3/hash.txt`, byte diffs `python3 tools/bdiff.py runs/A3/hash.txt.r1.bin
runs/C3/hash.txt.r1.bin 0x02000000 0x02400000 8 40`.

**Conclusion:** the translated battle is bit-identical across machines given identical per-frame inputs once the few
history- and machine-dependent values below are synchronised at FUN_020140C8. The heap layout at battle init was the same
for every history tested (G = 0x02100048, heap free 2895384 in all runs); the first battle input call came 311-314
frames after the init in every run.

### 1.2 Sources of divergence and what to do

| Source | Address / code | Matters? | LAN action at battle start (QoLGame `f_020140c8`, before super) |
|---|---|---|---|
| **Battle RNG** (byte table) | struct u32 0x020DD4E4 {u32 mode, u8 index +4, u8 countdown +5}, table 0x020B63D4, FUN_02001998 / FUN_020018FC; mode 0 reseeds the index from the **RTC** (FUN_02001A50 = hour·min·sec) every 256 calls | **yes** (A1/B1, EA2/EB2). Used by camera shake, effects, script VM, AI; 0 calls in a plain MP battle, 65 with bombs + chaos, 281 with the CPU AI | `f_020019fc(1)`: index 0, countdown table[0], no RTC reseed — what the game's own wireless battle does (FUN_02079430 state 4). After the battle: `f_020019fc(0)` |
| Stage choice | party u8 0x020DD54A; the random icon (15) picks with the RNG in FUN_02071374 | yes | host's resolved stage id written (host resolves "random" itself) |
| Parties | party block 0x020DD514.. (mode, P1 s32[3] 0x020DD524, P2 0x020DD530, supports 0x020DD53C/40, counts 0x020DD548/49, boss level u8 0x020DD510) | yes | mode 5, P1 = host picks, P2 = guest picks, counts, supports, boss level 0; party +0x32 = +0x33 = 0 |
| Instance-id counter | u16 0x020DD7B4 (FUN_020061E0 → object +0x22), grows across battles, reset only by other scenes | yes for the RAM image (ids in G; not seen to change gameplay) | write 0 (a fresh boot has 0 there) |
| **Save copy in RAM** | 0x020DD5B4, 0x1F4 bytes. The loader FUN_0202A40C reads: options u16 0x020DD79C bits 3-4 (FUN_02002260) → teams +0x1676 = 0x100 / 0x140 / 0x180, bits 1-2 (FUN_0200228C) → FUN_0200231C CPU level; Team Arts unlock mask FUN_0202856C (story progress, FUN_02002410) → teams +0x8DC / +0x11C4 (read by FUN_02026548 = which Team Arts exist) | **yes** (code; all research runs used the same save) | guest swaps the **host's save copy** (sent with STAGE_RESULT) into 0x020DD5B4 for the battle and swaps its own back at the battle exit / abort. The on-disk save is never written during a LAN battle (Free Battle saves nothing; result screens are skipped by the redirect) |
| Frame counter | u16 0x020DD4C0 (NitroMain only; 3 literal refs) | not for the game (differs in all passing pairs); the port's shuffle / stage-shuffle tick dedupe compares it with a stale value | write 0, and reset `_shuf_frame`, `_stg_frame`, `_shuf_p2[1]` to -1 |
| RTC | battle reads it only through the RNG reseed (FUN_0200846C callers are story / practice / other scenes) | no, after the RNG fix | none |
| Hardware timers, ARM7 sound timing, music stream | emulated time; sound work bytes 0x020E35xx/0x020E37xx, stream buffer 0x022Exxxx differ | no (A3/B3, EA/EC: G identical; the BGM itself may differ) | none; send music_seed in the snapshot anyway (same music on both) |
| CPU level u8 0x020DD552 | set by the loader from the save options | AI only (no AI in MP) | covered by the save swap |
| Heap / addresses | G 0x02100048, heap free equal at init in every history | no | none (desync check catches the unexpected) |
| Port RNGs | QoLGame `rng` (RANDOM CHARACTERS / STAGE; new random seed per process), `_shuf_rng` / `_stg_rng` (`randomize()` once per process unless shufseed / stgseed), QoLBombs `_rng` (reset to bombseed at every battle start), `_fx_rng` (blood etc., visual only), QoLMp `rng` (50/50: host only), settings `music_seed` | yes (random picks, swap targets, bombs) | seed `rng`, `_shuf_rng` (+ `_shuf_seeded = true`), `_stg_rng` (+ `_stg_seeded`) from the battle seed the host sends (V EA/EC with `qolseed`); bombs reset already; music_seed in the session snapshot |
| BOMB RAIN spawn bounds | qol_bombs.gd `_spawn`: view left / right from `_cv_draw` = camera **as drawn**, incl. the local CAMERA ZOOM (QoLGame `_fx_draw`, zoom +6 while drawing) | **yes when CAMERA ZOOM differs** (code) | in a LAN battle use the game's unzoomed view (`_cam()` / zoom from the game's own value) |
| BOMB RAIN sway | `SWAY * sin(...)` in GDScript (C runtime `sin`) | maybe across OSes (MSVC UCRT vs Wine's ucrtbase on Proton) | in a LAN battle use a deterministic sine (the game's table 0x020B64D4, 256 steps, 1.0 = 256) |
| Other float math in gameplay | only `rng.randf() < 0.3` (RANDOM CHARACTERS support); everything else float is drawing (shadows, blood, sparkles, confetti, damage numbers) | no (PCG32 + IEEE double are the same on every x86-64) | keep gameplay code integer / double; never Vector2 (float32) or transcendental functions in gameplay hooks |
| Local settings (never copied) | CAMERA ZOOM, DETAILED SHADOWS, DAMAGE NUMBERS, INPUT DISPLAY, FPS / smooth motion, CRT etc. | drawing-only fields of G change (rec +0x140/+0x142, team +0x8A4/+0x8A6, G+0xE08), gameplay identical (A6/D6) | exclude those fields from the desync checksum (1.5); AUTO PAUSE off during a session (a paused machine stalls both) |
| Main-thread RAM writes | QoLController / panels during a battle | must not depend on local state | rule: during lockstep the only main-thread inputs to the game are the exchanged input records |
| Soft reset | L+R+Start+Select (NitroMain loop FUN_020011F8 ×4; scene 4 too) | would reset both machines | mask the combination in LAN input |
| Visual-only weird options (blood, confetti, afterimages, flashy ki, rainbow, fuzzy, bevel, game boy, CRT, epic, 2nd fiddle) | drawing / palettes | copied from the host anyway | none |
| MIRROR MODE | GameDS swaps LEFT / RIGHT of the DS word | input | swap at the **sender** (the local word before it is encoded); never swap received records |

### 1.3 Pause and battle end
Pause (either player's START, the DS word gets P2's START ORed in; in pause state 9 and battle-end states 0x0F-0x14 both
players' words are ORed, as in LOCAL MP) runs inside lockstep — no special handling: A1-A6 paused and continued, A5/C5 went
KO → state 0x11 → scene 0x14 (Game Over) → scene 3 in lockstep. The KO banner fix of part 27 (winner's banner, camera to
the winner) is deterministic and must run identically on both machines; any "YOU WIN / YOU LOSE" wording is a port
overlay only.

### 1.4 Lockstep boundaries
- Start: FUN_020140C8 (battle init) on the game thread: the sync writes of 1.2 happen there; lockstep frame L = 1 is the
  next game frame. Between the scene-5 exit and the init both machines run with a blank DS input (nothing needs input),
  so the different real times at which the two machines get there do not matter. The first D frames (input delay) use
  neutral inputs on both, after that a machine that is ahead simply waits (a natural barrier).
- End: the game thread calls FUN_02001014 from scene 0 (battle exit: 0x14 / 10 / 3 / 0xD / 6) — at the same lockstep
  frame on both machines (deterministic). The LAN redirect sends both to scene 4 (6 = pause "Mode Select" → lobby 0x11);
  inputs already sent for later frames are dropped. Restore the guest's save copy and RNG mode 0 there.

### 1.5 Desync checksum (verified to ignore local settings, to catch real divergence)
CRC32 or MD5 over: team blocks u32 [0x020DE3D0] .. +0x167C (both teams' records and the shared battle state up to the
effect pool) with **+0x140..+0x143 of each of the 6 records and team +0x8A4..+0x8A7 zeroed**; the effect pool u32
[0x020DE3CC] .. +0x4DF0 (48 × 0x164 objects, 8 more at +0x42C0, count at +0x4DE0) with **+0x140..+0x143 of each object
zeroed**; RNG 0x020DD4E4..+6; battle state u8 0x020DD4C5; timer u16 G+0x1BCA6; camera x / y u32 [0x020DE3A4]+0xC / +0x10.
Reference implementation: scratch `game_ds.gd` `_lanr_gameplay_hash()` (~6 KB hashed per frame, negligible). V: A6 / D6
(different zoom / shadows) equal all 2600 frames; 1861 distinct values in 2600 frames (sensitive); EA2 / EB2 differ.

### 1.6 Other notes from the runs
- With a CPU P2 (AI) the battle is deterministic too once synced (A3/B3, C4) — useful for single-machine tests.
- INPUT DISPLAY shows the DS pad word = PLAYER 1; on the guest it should show the local player's (P2) record.

### 1.7 Rollback: not feasible (confirmed)
- The game thread is a Godot thread parked inside translated GDScript: in a battle its stack is NitroMain → the scene
  function's own blocking loop → `f_0200077e` (VBlank wait) — plus other DS threads parked mid-function on their own Godot
  threads (DSMachine `_switch`). That state is native call stacks; it cannot be saved or restored. DSMachine.resume() only
  restarts from a snapshot taken in NitroMain's inner loop with a hand-written copy of the loop tail (lockstep tests).
- The rest of the state is large and spread over GDScript objects (8 MiB RAM, IO, VRAM banks, GX FIFO, ARM7 driver +
  DSSound channels, QoLGame / QoLBombs / panel variables).
- Cost: a game frame takes ~6-16 ms (Steam Deck 13-16 ms, part 26); re-simulating several frames per displayed frame is
  impossible.
⇒ Deterministic lockstep with input delay (what the original wireless mode does).

---------------------------------------------------------------------------------------------------------------
## 2. Frame pacing and input path (research question 2)

### 2.1 Where to block
`GameDS._tick_begin()` is the only place a game frame starts (`_tick()`, the `_process` loop, and the part-26 pipeline
`_pipe_start` all call it; it already returns false when no frame was started). Add at its top:
```
if qol != null and qol.lan_lockstep() and not qol.lan.can_step(frames + 1):
	_lan_stalled = true
	return false                      # no game frame: drawing, polling, overlays go on
```
- `_process`: when a step was refused, break the `for i in steps - _ahead` loop and clamp `_acc = minf(_acc, period)` so
  the game does not fast-forward when the inputs arrive (both machines wait for each other; nothing to catch up).
  `_pipe_start` simply does not start a frame (its `_tick_begin` returns false); `_pipe_join` is unaffected.
- Headless / turbo test runs: `_physics_process` → `_tick()` would spin; on a refused step `OS.delay_msec(1)` (two
  processes share 2 CPUs).
- Poll the network (QoLLanNet.service) at the start of `_process`, right before the gate and right after a local input
  record was produced (send at once). Polling once per Godot frame only adds up to one display frame of latency (ENet
  two-process localhost RTT measured 7 ms at 60 Hz polling vs 1 ms in a tight loop).
- Show "WAITING FOR PLAYER" after 30 consecutive refused game frames (0.5 s); "CONNECTION LOST" (and abort, 6.1) after 10 s
  without any packet or on ENet EVENT_DISCONNECT (`peer.set_timeout(32, 5000, 10000)`).
- Clock drift: both machines step at 59.83 Hz from their own clocks; the faster one would stall one frame every few seconds.
  Each input packet carries the sender's newest frame; frame advantage = local L − (remote L + RTT/2 in frames), smoothed;
  if it stays > 0.75 the leading machine slows its accumulator by up to 1 % (like the audio rate matching) — GGPO-style time
  sync. In lockstep use the timed pacing (not "one frame per refresh" lock to a 60 Hz display).
- AUTO PAUSE: off while a LAN session runs (QoLController.paused stays false).

### 2.2 Input delay and the buffer
- Delay D frames (fixed per battle): local input sampled when frame L starts is scheduled for frame L + D; frames 1..D are
  neutral on both. D = clamp(ceil((RTT_avg + 2·jitter) / 2 / 16.71 ms) + 1, 2, 8), chosen by the host from the lobby /
  stage-select pings (last 5 s) and sent in STAGE_RESULT. LAN: D = 2 (33 ms). Debug `landelay=N`. (Optional later:
  host-announced delay change at a future frame F; v1 keeps D fixed.)
- Ring buffer per player: records for frames up to L + D + 64. `can_step(L)` = local[L] and remote[L] present (local is
  present by construction for L ≤ newest + D).
- Input packet (ENet channel 1, FLAG_UNSEQUENCED, sent every Godot frame and after each sampled frame): all local records
  not yet acked by the remote (cap 16 → redundancy against loss), the newest remote frame received contiguously (ack),
  the sender's current frame, the newest (frame, checksum) pair (1.5). ~60-130 bytes (two-process test: 61 bytes with 8
  records, 0 % loss, all frames received).

### 2.3 Record format and how both machines feed it to the game (identical code on host and guest)
Record (7 bytes): u16 `held` (DS layout incl. X 0x400 / Y 0x800), u16 `tapped` (buttons pressed and released since the last
sample: GameDS `_tapped`, the gamepad cursor click, QoLMpInput latches), u8 flags (bit 0 touching, bit 1 a new touch began
since the last sample), u8 x, u8 y (lower-screen pixels 0..255 / 0..191).
Sender side (local machine, main thread, in `_tick_begin` where `qol.mp_frame()` is called today): the local word / touch
from the normal path (ds_* map, scripted `inputs=` / `laninputs=`, mouse, QoLCursor), **through `qol.filter_input`
(local state like keys still held when a menu closed) and the MIRROR swap**, soft-reset combo masked → record for frame
L + D → send. The host's record is P1, the guest's P2.
Apply side, for frame L on both machines (`QoLLan.apply(L)` → [keys, ext, touch] for the DS + QoLMp fields):
- DS pad word = P1.held | P1.tapped; | P2's START (pause); in pause (state u8 0x020DD4C5 == 9) and states 0x0F-0x14 | P2's
  word too (as LOCAL `mp_frame`).
- DS touch = P1's (x, y) when touching (→ `arm7.set_touch`, the game's own P1 path; deterministic: same firmware
  calibration on every machine), else none.
- P2: `mp.held[1] = P2.held | P2.tapped`, `mp.pressed[1]` / `mp.latch[1]` as QoLMpPanel.route does (latch |= newly
  pressed), `mp.touch[1] = (x, y)` or (-1, -1), `mp.tap[1] = (x, y)` when flag bit 1 → `f_0202dce0` → MP_AI_OUT (the edge
  logic there is per input CALL, identical on both).
- Neither machine applies `filter_input`, the MIRROR swap or any local device / cursor state to received or replayed
  records. `mp.stage = BATTLE`, `mp.active = true` during lockstep so every MP battle rule (cheats for both sides, dual
  assists, Team Arts light, banner fix) runs on both machines.
- Guest taps: its lower screen shows side 1 in the game's single-player geometry (3), so a tap at (x, y) **is** the side-1
  panel coordinate (records' rects +0x2D0..+0x2D6 are the same 8 + 80·k, 16..136 for both sides; Team Arts 8,144-248,184);
  no mapping table needed. Host taps on the game's own panel are side-0 coordinates already.

### 2.4 Pipelining (part 26)
Unchanged: the game sees the same input per frame; pipelining only reads the local input up to one display frame earlier
(slightly more latency on slow PCs). The gate inside `_tick_begin` covers the pipelined start. Nothing may touch game RAM
between `step_begin` and `step_end` (the LAN apply runs in `_tick_begin` before `step_begin`).

---------------------------------------------------------------------------------------------------------------
## 3. The guest's battle view (research question 3)
- The game draws the lower-screen panel only for the local side G+0x1BCA9 (0 on both machines; must stay 0 on both:
  it also decides banner kinds and the loader's Team Arts call). Host: the game's own panel, unchanged.
- Guest: hide the game's lower-screen BG layers while `display.battle_on_screen()` (as QoLMpPanel does) and draw
  **QoLLanPanel** = side 1 in the game's single-player layout: three 80x128 portraits at each side-1 record's own rect
  (+0x2D0 x0, +0x2D2 y0; the game's art sits at x 8 + 80·k, y 8..136 on the screen), active one highlighted (palette rows
  1-3), bench lit / dark by team ki ≥ 0x1400 (row 0 / 7), KO'd dark (row 4), support greyed when assists = 0; the Team
  Arts / Touch! bar = the full `e_pairatk` map (QoLMpPanel `_pair`, 256x192 indices) with palette row 5 (lit: ki ≥ 0xC800
  and the side's active record +0x274 & 0x100 — computed every frame for both sides by `# ---- MP TEAM ARTS LIGHT`) or 6;
  the red diamond in P2 blue (palette swap, as the MP plate). Reuse QoLMpPanel's `_portrait(id, kind)`, `_pal`, `_pair`
  (ROM decoding, no assets stored), fades from the lower engine's MASTER_BRIGHT, skull markers via `mark_at`. VS intro
  (team pointer 0): ids from the party block P2 slots.
- **Pixel check**: render QoLLanPanel for side 0 in a single-player battle and compare with the game's own panel
  (captures, `layersweep`): must match except the diamond colour.
- PING: both machines, port text "PING 12ms" (QoLFont small, white with a dark outline) bottom-left **under the Team Arts
  plate**: the free strip y ≈ 180..190, x ≈ 10..90 (lower4500.png: the Team Arts plate ends at y ≈ 176). Colour by value
  (< 30 ms white, < 80 yellow, else red). "WAITING FOR PLAYER" / "CONNECTION LOST" / "DESYNC" as a band over the top
  screen's centre (port overlay, like QoLMpSelect's bands). **Phase 4:** BOLD game font, "PING" yellow + value white on a black
  outline at x 8 / y 179, a 3-bar signal icon in front as the only colour hint (green / yellow / red); the RTT is measured by
  QoLLanNet's network thread (the real round trip, 1-3 ms on localhost). The team-select band sits in the top screen's name
  strip (x 8..247, y 138..160), not across the portraits.
- Top screen: unchanged (side 0 left = host, side 1 right = guest on both machines).

---------------------------------------------------------------------------------------------------------------
## 4. Select screens, stage, flow (research question 4)

### 4.1 Team select = scene 4 (FUN_02066558) in mode 2, on each machine
The game's wireless VS already does "each DS picks its own team": VS menu (scene 0x11) → HOST (result 1: party +0x33 = 1)
→ state 8: FUN_02002738(1) (+0x32 = 1) → **scene 4 in mode 2** (Z-Battle team select: three big portraits, DRAGONPOWER,
READY? GO / BACK — the "red / blue hexagons") → GO → **scene 5** (FUN_02066558 exit: mode 2 and host → 5) → stage A →
FUN_020717E8(1): FUN_02071374 then mode 2 + link flag + host → **scene 7** (wireless battle: "Connection Failed").
V (port, MP setting off, `runs/vs4`, sheet `vs4_sheet.png`): scene 0x11 → 4 at f2840 (mode 2, +0x32 = +0x33 = 1) → 5 at
f3180 → 7 at f3460 → "Connection Failed" f3600. Scene 4 and 5 contain no wireless code (no callee in the wireless range;
the only mode / host tests are the exits and FUN_0206B85C's drawing).
LAN flow: both machines take this path; only scene 7 is redirected (to the battle). Details:
- Enter: when the guest ACCEPTs, both QoLGame `f_0207b778` overrides return **1** (left button = the game's HOST path; never
  2 = client: +0x33 = 2 sends scene 0x11's next load to the wireless client wait, state 3).
- In scene 4 the game runs its own single-player select (`f_0206cc94` → super, SAME CHARACTERS / BOSS CHARACTERS paths
  as in single player; host cheats are active on the guest). DP max = FUN_020021F0 (save; ∞ with the 100 % save).
- **Wait for the other**: hook in `f_0206cc94` (LAN branch before the existing code): when super returns 0x8000 (GO)
  and the remote is not READY → send READY {picks}, keep the READY? overlay up, return 0x800 (nothing) every frame and
  draw "WAITING FOR <NAME>"; BACK (B / tap) while waiting → `f_0206a748(0)`, send UNREADY. Both READY → return 0x8000 →
  the game's exit (party P1 written by FUN_02002838(0, id), support moved last) → scene 5.
- Picks to send: the current team s32[3] 0x020DE64C (or party P1 after the exit) + per id "boss" (BOSS CHARACTERS: L held,
  QoLGame `boss_pending` / `_note_pick`). Each machine keeps the remote's team for the battle start.
- Scene-4 B with no picks: the game's own exit (mode 2) → FUN_02002738(0) + scene 0x11 = **back to the lobby**; send
  LEAVE_SELECT, the other machine follows (inject B or its own redirect), the lobby page reopens (like LOCAL `reopen_setup`).
- Note (C, M): FUN_02066558's exit replaces id 7 by 0x15 when the team also holds 0x1E (a special pair rule); the picks to
  send are read after it (party P1) or the same rule must be applied.

### 4.2 Stage select = scene 5 with the LOCAL two-outline code
- `mp.stage = STAGE` (session active, not `debug_battle`) and `f_0207215c` / `f_02071e64` / `f_02070718` run as in LOCAL
  MP with: player index 0 = host (red outline), 1 = guest (blue) on both machines; the local player's presses / taps go to
  its index (mp.pressed / sel_tap), the remote index gets none; its `icon` / `chosen` come from STAGE_CURSOR messages
  (reliable channel, sent on change; written on the main thread before the frame).
- 50/50: replace `mp.rng.randi()` in `f_0207215c` by a LAN hook: host decides (and resolves icon 15 "random" to a stage id
  with its own rng), sends STAGE_RESULT; guest returns 0 (keeps waiting, roulette not started) until STAGE_RESULT arrives,
  then uses the host's winner. Both run the same roulette and return 0x81 → FUN_02071374 → FUN_020717E8 → (mode 2, +0x32,
  host) → FUN_02001014(7).
- B with nothing chosen: LOCAL injects B (scene 5 → mode 2 → scene 4 for that machine); in LAN send STAGE_BACK, both go
  back to scene 4 (each injects B).
- STAGE_RESULT {winner icon, stage id, battle seed u32, input delay D, host save copy 0x1F4 bytes, both final teams + boss
  flags, host's party +0x32/33 not needed} — everything the battle start needs, sent once, reliably, by the host.

### 4.3 Into the battle
`f_02001014` LAN branch (QoLGame; session only): current scene 5 and asked 7 → write mode 5 (`f_0200297c(5)`), clear
+0x32 / +0x33 (`f_02002738(0)`, party +0x33 = 0), party P1 = host team, P2 = guest team (both machines), stage = STAGE_RESULT
stage, boss level 0, `mp.stage = BATTLE`, `lan.battle_pending = true` → redirect to 0. The rest of the sync is in
`f_020140c8` (1.2): RNG mode 1, id counter 0, frame counter 0, port RNG seeds, boss_teams per side, guest swaps the save copy.
Note: RANDOM CHARACTERS / RANDOM STAGE then run on both with the same seeded rng (V EA/EC); the stage-select's own random
pick (icon 15) is overwritten by the redirect.

### 4.4 After the battle
Battle exits (asked 0x14 / 10 / 3 / 0xD from scene 0) → **scene 4** with `f_0200297c(2)`, `f_02002738(1)`,
`f_020026e4(1)` (host flag) on both; restore the guest's save copy; `f_020019fc(0)`; lockstep ends. Pause "Mode Select"
(6) → scene 0x11 (lobby) on both. Scene 4 starts with empty picks (its init clears 0x020DE64C / 0x020DE658).

### 4.5 Flow summary
```
Mode Select --tile 2--> 0x11 state 2 [LOCAL | LAN]
  LAN -> port pages: HOST / JOIN -> warnings -> name (+ IP) -> connect -> LOBBY (still 0x11)
  host GO TO CHARACTER SELECT? -> guest ACCEPT -> both f_0207b778 = 1 -> scene 4 (mode 2, +0x32 = +0x33 = 1)
scene 4: own team, GO held until both READY -> picks exchanged -> scene 5
scene 5: two outlines (local + remote), both chosen -> host 50/50 -> STAGE_RESULT -> roulette -> 0x81 -> asks 7
  ==f_02001014==> 0 (mode 5, parties, stage) ; f_020140c8: sync ; lockstep L = 1..
battle exit 0x14|10|3|0xD ==> 4 (mode 2) ; pause Mode Select (6) ==> 0x11 lobby
scene 4 B with no picks -> game's own exit -> 0x11 lobby ; lobby B -> LEAVE? -> session ends -> LOCAL / LAN screen
```

---------------------------------------------------------------------------------------------------------------
## 5. Transport, session, settings snapshot (research question 5)

### 5.1 Transport
- **ENetConnection** (Godot's ENet module; in the official export templates the project uses) directly, not
  ENetMultiplayerPeer / MultiplayerAPI (no RPCs, peer ids or scene replication needed; ENetConnection gives channels,
  per-packet flags and RTT statistics). PacketPeerUDP would need our own reliability for session messages.
  V (`enet/enet_test.gd`, `enet/enet_2p.gd`): bind on 8082 OK, a second bind → `ERR_CANT_CREATE` (detect "port in use");
  connect in 2-470 ms; two processes on localhost: RTT 7 ms (60 Hz polling), 0 % loss, 900/900 frames, 61-byte packets.
- Host: `create_host_bound("*", port, 1, 3)` (1 peer: a second JOIN gets "SESSION FULL"); guest: `create_host(1, 3)` +
  `connect_to_host(ip, port, 3)`, 15 s timeout → "UNABLE TO CONNECT".
- Channels: 0 = session messages, FLAG_RELIABLE; 1 = input packets, FLAG_UNSEQUENCED (redundant records); 2 = pings,
  unreliable.
- Port **8082 UDP** default; `ip:port` accepted when joining. 8082 has no standard Windows or SteamOS service on UDP (TCP 8082
  is sometimes a web / dev server; TCP and UDP ports do not conflict). Fallback: if the bind fails, try 8083..8091 and show
  the port actually used on the host's lobby (the guest then types ip:port).
- Firewall: Windows shows the "Windows Defender Firewall has blocked some features" dialog the first time the exe binds
  (host) — the player must allow it (Private networks); a network marked "Public" blocks inbound UDP by default. The
  guest needs no rule (replies to its outbound packets pass). Say this on the HOST page and in docs/PLAYER_README.txt.
  SteamOS: no firewall by default; Proton maps sockets directly. NAT is irrelevant on a LAN (no internet play).
- Local addresses for the host page: `IP.get_local_addresses()` filtered to IPv4 private ranges (10/8, 172.16/12,
  192.168/16; 169.254/16 last), no 127.x / IPv6; show up to 3 with the port. (Optional later: LAN discovery broadcast.)
- Network work stays on the main thread (ENet objects are not thread-safe); if long loading hitches ever trip timeouts,
  move QoLLanNet to its own thread with locked queues.

### 5.2 Handshake (channel 0, `var_to_bytes` of a Dictionary, `bytes_to_var` without objects; reject anything else)
- Guest → HELLO {magic "DBZ-SSW2-LAN", proto 1, build (see below), rom_md5 (MD5 of the whole ROM image, hashed once on a
  thread), name}.
- Host → WELCOME {proto, build, rom_md5, name, session id, snapshot (5.4)} or REJECT {reason: "VERSION" (proto / build
  differ, show both), "ROM" (different game data), "FULL"} then disconnect_later.
- Build id: editor runs hash the source text of scripts/gen/*.gd + scripts/core + scripts/qol + game_ds.gd; exported builds
  (script_export_mode 2 has no source text) read `res://data/build_id.txt` written at export time (export.sh / the
  Windows export step; agents never run export.sh). Both machines must run the same port build. **As built (7.1):**
  exports hash their `.gdc` scripts; `build_id.txt` is only an optional override (no export step needed).

### 5.3 Messages
Session (ch 0, reliable): HELLO, WELCOME, REJECT, BYE{reason}, LOBBY {status}, PROPOSE_SELECT, ACCEPT, DENY,
SELECT_READY {team[3], boss[3]}, SELECT_UNREADY, LEAVE_SELECT, STAGE_CURSOR {icon, chosen}, STAGE_BACK, STAGE_RESULT (4.2),
DESYNC {frame, crc}, BATTLE_ABORT {reason}. Ping (ch 2): PING {t_ms} / PONG {t_ms} every 500 ms in all stages (RTT for
the display = smoothed app RTT; ENet's `PEER_ROUND_TRIP_TIME` as a cross-check). Battle (ch 1): INPUT {battle id u16, first
frame u32, count u8, records[count] (7 bytes each), ack u32, current frame u32, crc frame u32, crc u32}.

### 5.4 Cheats / weird snapshot and the restore guarantee
- Snapshot (host → guest in WELCOME, again if the host somehow changes them — it cannot during a session): `{"v": 1,
  "cheats": {name: bool for QoLSettings.CHEATS (18)}, "music_seed": int, "weird": {name: bool for QoLSettings.WEIRD (14:
  bevel_emboss, touch_fuzzy, epic_mode, second_fiddle, blood, afterimages, game_boy, mirror_mode, flashy_ki, screen_shake,
  ko_confetti, rainbow_ki, bomb_rain, crt_tv)}}`. Not copied (settings): window / fps / music / sfx / volume / auto pause /
  detailed shadows / camera zoom / auto skip / damage numbers / input display / controls / mp devices / multiplayer.
- QoLSettings gets `begin_override(snap)` (stores the guest's own values of exactly those keys in `_own`, sets the host's,
  `override_active = true`) and `end_override()` (puts `_own` back). **`save_file()` while `override_active` writes `_own`
  for the overridden keys** — so settings.cfg never contains host values, whoever calls save_file (MP setup, menus, …).
  A crash or kill therefore needs no recovery: the file still holds the guest's own values.
- After applying (both ways) call what the menu calls when such a value changes: RANDOM MUSIC `shuffle_music(seed, …)`,
  picture effects / CRT presenter refresh (`qol.apply_display`), epic mode init — one `QoLController.apply_session_settings()`.
- The settings menu cannot be reached during a session (it opens from Mode Select only; sessions live in scenes 0x11 / 4 /
  5 / 0); still guard `open_menu()` and the F-keys that change settings while `lan.active`.
- End of session (BYE, lobby LEAVE, disconnect, Mode Select): `end_override()`, `f_020019fc(0)`, close ENet, save copy
  restored if swapped.

---------------------------------------------------------------------------------------------------------------
## 6. Menus and keyboard (port pages, QoLMenu / QoLMpMenu look)
- LOCAL / LAN overlay exists (part 27). LAN (`f_0207b778` result 2 with MULTIPLAYER on) → QoLLanMenu page **LAN**:
  HOST / JOIN buttons + BACK. Text: "Play on your local network. HOST: wait for a friend. JOIN: connect to a host by IP".
- Confirm popups (lbconfirm style, NO first, B = NO):
  - HOST: "The other player will use YOUR cheats and weird options for this session. Their settings are not changed."
  - JOIN: "You will use the HOST's cheats and weird options for this session. Yours are restored when you leave (also
    after a crash). Settings (window, sound, controls…) stay yours."
- Name page (host and guest; default = last name, saved in settings.cfg [lan] name / last_ip — own settings, allowed):
  QoLKeyboard. JOIN adds the IP page ("192.168.1.23" or "192.168.1.23:8082"; validated: 4 octets 0-255, port 1-65535).
- **QoLKeyboard** (Control, 256x192 lower screen): text field (max 10 chars name / 21 IP) with caret, keys in a 10x4 grid
  (A-J / K-T / U-Z 0-3 / 4-9 . : - _) of 24x22 px hexagon-style buttons + a row SPACE | DEL | OK; cursor moved by the
  D-pad (wrap), A types, B = DEL (B on an empty field = back), Start = OK, L / R = caret; taps / mouse / gamepad cursor
  press keys; a real keyboard types directly through `QoLController.raw_input` (unicode A-Z a-z (upper-cased) 0-9 . : - _
  space; Backspace = DEL, Enter = OK, Esc = back) — while the page is open no event reaches the ds_* map. Top screen:
  title + hint ("Type with the keyboard or pick letters").
- CONNECTING page (guest): "CONNECTING TO 192.168.1.23:8082…" + countdown; 15 s → "UNABLE TO CONNECT" popup (OK → IP page).
  REJECT reasons as popups ("DIFFERENT GAME VERSION", "DIFFERENT ROM", "SESSION FULL").
- LOBBY (both, still scene 0x11): top screen (message box interior x 11-244, y 59-148, QoLFont): "HOST  <name>", "GUEST
  <name>" (YOU marked), "PING 3 ms", status ("WAITING FOR A PLAYER…" with the host's addresses + port, "CONNECTED", "WAITING
  FOR <HOST>…"); lower screen: host GO TO CHARACTER SELECT (enabled when a guest is in) / LEAVE; guest LEAVE.
  GO → PROPOSE_SELECT → guest popup "<HOST> wants to go to the character select. ACCEPT / DENY" → ACCEPT → both
  `mp.go`-style flag → `f_0207b778` returns 1. DENY → host popup "<GUEST> said no".
- LEAVE (B) → "LEAVE THE SESSION?" YES / NO → BYE → session end → the LOCAL / LAN screen.
- A remote BYE / disconnect anywhere: popup "<NAME> LEFT" / "CONNECTION LOST" → lobby (if in a select: the scene's own
  B path; in a battle: 6.1).

### 6.1 Battle abort — leaving a running battle after a disconnect or desync
End lockstep, return to free running on this machine, restore the save copy, and leave through the game's own pause menu:
inject START, then the pause menu path to "Mode Select" (item code 4 → next scene 6, FUN_0201546C), redirected to 0x11.
A DESYNC (checksums differ) → both show "DESYNC" for 2 s and abort the same way (log frame + both checksums; debug
`landesync` dumps).

---------------------------------------------------------------------------------------------------------------
## 7. Files, classes, hook points
New (all `scripts/qol/`, section headers `# ---- LAN (part 30)`):
- `qol_lan_net.gd` — `class_name QoLLanNet` (RefCounted): ENetConnection host / client, channels, encode / decode, ping,
  port fallback, local addresses, impairment for tests (`lanlag` / `lanjitter` / `lanloss`: delayed / dropped sends).
- `qol_lan.gd` — `class_name QoLLan` (RefCounted): session state machine (IDLE, HOSTING, CONNECTING, LOBBY, SELECT, STAGE,
  BATTLE), handshake, snapshot apply / restore, remote picks / stage cursor, STAGE_RESULT, lockstep buffers
  (`can_step`, `sample`, `apply`), delay, time sync, checksums, debug flags. Owned by QoLController (`lan`), shared with
  QoLGame (`lan`, null = off).
- `qol_lan_menu.gd` — `class_name QoLLanMenu` (Control under screen_root): pages of section 6, popups.
- `qol_keyboard.gd` — `class_name QoLKeyboard` (Control).
- `qol_lan_panel.gd` — `class_name QoLLanPanel` (Node2D): guest side-1 panel (section 3) + PING label + bands (host shows
  only the label / bands). Uses QoLMpPanel's art helpers (make them static or share the instance).
Changed (minimal hook lines):
- GameDS `_tick_begin`: gate (2.1); LAN input path instead of `qol.mp_frame()` + `filter_input` + mirror when
  `qol.lan_lockstep()` (2.3); `_process`: network poll, `_acc` clamp on stall; turbo sleep on stall.
- QoLController: `lan`, `lan_lockstep()`, after_step → `lan.after_step(core)` (scene tracking 0x11 / 4 / 5 / 0, menu
  pages, panel), `_mp_after` LAN mapping, AUTO PAUSE off, `open_menu` guard, INPUT DISPLAY local record.
- QoLGame `# ---- LAN (part 30)`: `f_0207b778` (LAN button → menu, ACCEPT → return 1), `f_0206cc94` (READY wait in scene 4),
  `f_0207215c` 50/50 hook (`_lan_stage_winner()`), `f_02001014` (5 → 7 ⇒ 0; 0 → exits ⇒ 4 / 0x11; 4 → 0x11 = lobby
  reopen), `f_020140c8` (battle-start sync 1.2, before `_mp_battle_start` and the random cheats), save-copy swap / restore,
  `_shuf_frame` / `_stg_frame` resets, bombs: unzoomed view + table sine when `lan` battle.
- QoLSettings: `begin_override` / `end_override` / save_file rule (5.4), [lan] name / last_ip.
- QoLBombs: `_cv_draw` → game view in LAN battles; `sin` → table.
Port-only RAM: none new needed (MP_AI_OUT 0x027C1000 reused).

### 7.1 QoLLan public API (phase 1, implemented — keep stable; the LAN menus use it)
`QoLController.lan` (QoLLan, always created; IDLE = inert), also `QoLGame.lan`. Fields: `state` (int: `QoLLan.IDLE` 0,
`HOSTING` 1 = room open / no guest, `CONNECTING` 2, `LOBBY` 3 = both connected, `SELECT` 4, `STAGE` 5, `BATTLE` 6) +
`state_name()` ("IDLE" …), `role` ("host" / "guest" / ""), `my_name`, `peer_name` (cleaned: A-Z 0-9 . : - _ space, max 10),
`ping_ms` (smoothed app RTT, -1 unknown), `port` (host: the port actually bound; guest: the target's), `reason` (why the
last connect / session failed), `target` ("ip:port" being joined), `settings` (QoLSettings), `in_battle`, `lockstep`,
`aborting`, `delay`, `battle_info` (STAGE_RESULT), `battle_pending`.
Methods: `local_addresses() -> Array[String]` (private IPv4 first, max 3), `host(name, port := 8082) -> bool` (false = no
port of 8082..8091 could be bound; `reason` "PORT IN USE"), `join(name, ip, port := 8082) -> bool` (`ip` may be "a.b.c.d:port";
false + event connect_failed for a bad address; else CONNECTING until an event), `leave()` (BYE; also inside a battle: it is
left through the abort path), `propose_select()` (host, LOBBY), `accept_select()` (guest: state SELECT) / `deny_select()`,
`poll()` (network + timers; GameDS calls it every Godot frame through `QoLController.lan_poll()`; extra calls are harmless),
`pop_event() -> Dictionary` ({} = none), `active()`, `connected()`, `waiting()` (lockstep stall > 0.5 s = "WAITING FOR
PLAYER"), `connect_left()` (seconds of the 15 s timeout), `send_stage_result(info)` (host, phase 3: {"stage": id or -1,
"teams": [[ids], [ids]] or []} + seed / delay / save copy added).
Events ("type"): "connected" (guest, WELCOME applied; +"name"), "connect_failed" (+"reason": TIMEOUT / NO ANSWER / BAD ADDRESS /
NETWORK ERROR), "rejected" (+"reason": "VERSION host p/build guest p/build" / "ROM" / "FULL" / "NOT THIS GAME"),
"peer_joined" (host; +"name"), "peer_left" (BYE; host → HOSTING, guest → IDLE), "lost" (ENet disconnect or 10 s silent;
same states), "proposal" (guest), "proposal_denied" / "proposal_accepted" (host only), "desync" (+"frame").
QoLController: `lan`, `lan_lockstep()`, `lan_poll()`, `lan_frame(keys, ext, touch)`, `apply_session_settings()`; `open_menu()`
refused and AUTO PAUSE off while `lan.state != IDLE`. QoLSettings: `snapshot()`, `begin_override(snap)`, `end_override()`,
`override_active` (+ the menus' `lan_name` / `lan_ip`, [lan] name / last_ip). QoLMp: `lan` (a LAN battle uses the MP
battle rules with `active` false: no local devices / cursors / select overrides / MP panel).
Phase 3 additions: see 9.1. Phase 4 additions (9.2): QoLLanNet runs a network thread (`threaded`, all ENet calls under
`_mutex`, `send_ping()`, events now also {"type": "rtt", "us"}, `shutdown(wait_ms)`); QoLLan `on_exit()` (QoLController._exit_tree:
BYE + graceful close), `on_battle_loaded()` (QoLGame.f_0202a40c: the checksum starts there), `_reset_battle_ids()` at the
session start. Phase-1 implementation notes (differences from the text above): `lanbattle=1` — the host sends STAGE_RESULT 2 s after the
guest joined (`lanteams=a.b.c/d.e.f`, `lanbstage=HEX` = stage id; else the menus' party / stage stay); the build id hashes the
source text (dev) or the exported `.gdc` scripts (exports), `res://data/build_id.txt` only overrides (no export step needed);
the exit frame (FUN_02001014 reseeds the RNG from the RTC there) has no checksum; input packets are 24 + 7·n bytes and resent
at most every 15 ms (plus one per new record: a resend per turbo iteration flooded ENet); the abort injects START only in
battle state 7 (A in 0x0F+ except 0x11) and `f_0201546c` returns 4 as soon as the pause menu takes input (sub-state 1);
the compare tool is `tools/linux/lan_cmp.py`.
Part 31 additions (9.3): `session_id` (0 = none; host: random at HELLO, WELCOME "session"), `flow` (the proposal both are in),
`start_info` (the STAGE_RESULT the running battle started on), `battle_fresh(info = battle_info)` (sid / flow / round are this
session's), `battle_redirect()` / `request_room(why)` (QoLGame's 5 → 7 redirect, game thread), `rem_where` (the other's last
WHERE), `prop_pending` (guest: a proposal waits); `accept_select()` only answers the LAST proposal. Every message carries "sid"
+ "flow" (added by `_send_msg`); new messages WHERE {p, battle} and BACK_TO_ROOM {reason, battle}; STAGE_RESULT has "sid",
"flow", "round", "battle" (the battle id both machines use); REJECT reason "HOST NOT IN ITS ROOM - TRY AGAIN" (QoLLanMenu shows
it as CONNECTION REFUSED); notices "OUT OF STEP" / "BATTLE STOPPED".

---------------------------------------------------------------------------------------------------------------
## 8. Test harness (research question 6)
- Two Godot processes on this machine, headless, localhost; each with its own settings / save / name:
```
H=/tmp/ssw2/<you>_lan; mkdir -p $H; cp "$SAV" $H/h.sav; cp "$SAV" $H/g.sav
$GODOT --headless --fixed-fps 60 --path $PROJ res://scenes/GameDS.tscn -- nds=$ROM sav=$H/h.sav save=$H/h.out.sav \
  qolcfg=$H/h.cfg turbo maxfps=0 mp=1 inputs=<to scene 0x11> lan=host lanname=HOST lanauto lanpicks=0.5.26 lanstage=9 \
  laninputs=<P1 battle input, frames relative to lockstep L> lanhash=$H/h.txt lanquit=2600 cheats=… > $H/h.log 2>&1 &
$GODOT … sav=$H/g.sav qolcfg=$H/g.cfg … lan=join:127.0.0.1:8082 lanname=GUEST lanauto lanpicks=5.0 lanstage=3 \
  laninputs=<P2's own input> lanhash=$H/g.txt lanquit=2600 rtc=2026-07-15T09:41:27 > $H/g.log 2>&1
python3 tools/linux/lan_cmp.py $H/h.txt $H/g.txt        # first differing lockstep frame (gameplay hash + G block)
```
  Kill only the PIDs you started. Give the guest a different `rtc=`, a menu detour in `inputs=` and other local settings
  (`zoom=4 shadows=1`) to prove the sync; use different cheats on the two sides to prove the snapshot (the guest's must
  win nothing).
- Debug flags (QoLLan; all inert without them): `lan=host|join:IP[:PORT]` (start hosting / joining as soon as scene 0x11
  state 2 is reached, no menu pages), `lanport=N`, `lanname=S`, `lanauto` (host proposes the select when the guest is in;
  guest accepts), `lanpicks=a.b.c` (scene 4: picks + READY by script), `lanstage=ICON` (scene 5: choose), `laninputs=L:Btn
  [+Btn|T<x>/<y>]:N` (the local player's input relative to lockstep frame L), `landelay=N`, `lanlag=MS`, `lanjitter=MS`,
  `lanloss=PCT`, `landbg` (protocol + lockstep log: `LAN f… L… stall …`), `lanhash=FILE` (per lockstep frame: L, gameplay
  hash, G hash, RNG, call counts — the scratch `_lanr_hash` format), `lanquit=L`, `landesync=L` (debug: corrupt one
  fighter's HP on this side at L to test detection), `lanbattle=1` (debug like `mpbattle=1`: both run the btnrun Free
  Battle by `inputs=`; at FUN_020140C8 it becomes a LAN battle with the sync of 1.2 — tests lockstep without menus).
  **Always pass `lanteams=a.b.c/d.e.f lanbstage=HEX` with it** (part 32): without them each machine keeps its own menu's
  battle, and the btnrun Free Battle's random stage comes from each machine's RTC → a correct DESYNC at the first checksummed
  frame (L277); QoLLan prints "LAN WARNING: lanbattle=1 without lanbstage" then. Also give every instance its own fresh
  `qolcfg=` (the shared settings.cfg may have cheats / BOMB RAIN on) and `lanwd=` in capture runs.
- Phase 4 (part 30 QA): `lanthread=0` (QoLLanNet without its network thread: service once per Godot frame, as before),
  `pingdbg` (one line per pong: rtt µs-exact, ENet's own RTT, the shown value), `mpdbg` with `landbg` adds heap free / open
  archives / file-cache entries to the LANS scene lines. Scripts: /tmp/ssw2/lanqa (rt.sh real time incl. windowed / mixed,
  mx.sh full flow + summary, disc.sh disconnects, rejoin.sh, wrun.sh exported exe under wine; DATA_NOTES "LAN QA").
- Part 31 (rejoin / disconnects): `lanrejoin=N[@C]` (N frames after a session of this process ended — lanleave, the other
  left / lost, a failed connect (retried, not counted) — the same `lan=` start again; C restarts), `lanquitat=WHAT[@N]` (quit
  like a window close N frames after the point WHAT), `lanoos=room|noresult|silent[@L]` (forced divergences for the watchdog:
  leave the team select without LEAVE_SELECT / ignore the STAGE_RESULT / stop sending input records from L), and `landbg`
  prints `POINT <name>` on every change (connecting, room, lobby, proposal, select, ready, stage, chosen, roulette, intro,
  battle, pause, end, aborting). Scripts: /tmp/ssw2/lanrj (two.sh; chain.sh NAME h|g "STAY FLAGS" "ACTION:POINT:DELAY|FLAGS"…
  = one side stays, the other is a sequence of fresh processes killed (-9 / -15) or closed at a POINT; chainsum.py; full.sh /
  busy.sh = a third process (FULL / host busy); hconn.sh; capx.sh = captures, also of a copy of the project).
- Part 32 (pause): `lanpace` (one `LANP` line per 60 lockstep frames: real time, stalls, input packets, rtt min / avg / max,
  CPU, frame time, network-thread passes, panel composes), `lanwd=K` (watchdog limits ×K, default 4 in capture runs).
  Scripts: /tmp/ssw2/lanpause (capb.sh, rt.sh, lanp.py, two.sh). The guest panel is drawn in every battle state incl.
  the pause (DATA_NOTES "Session 1 part 32 findings (LAN pause)").
- `lan=loop` (optional): one process, the remote is a recorded / scripted record stream with artificial latency — fast
  checks of the gate, pipelining and stall UI without a second process.
- Time budget (this VM, 2 CPUs): one headless turbo instance ≈ 95 frames/s (4000 frames in 42 s; per-frame RAM hashing
  costs ~30 %), two in parallel ≈ 50-90 each; boot → scene 0x11 ≈ 2780 frames; a full two-instance flow (lobby, select,
  stage, 2600 lockstep frames, back to the select) ≈ 6000 frames ≈ 2-3 minutes. Captures (xvfb, llvmpipe) of one
  instance only, for the UI pages and the guest panel; never more than these two Godot processes at a time.

---------------------------------------------------------------------------------------------------------------
## 9. Phases (each ends with its test; off-identity btn + intro after every phase; LOCAL MP regression after 1 and 3)
1. **Network core + session protocol + lockstep core** (risk first, no UI): QoLLanNet, QoLLan handshake / lobby state /
   ping / snapshot (QoLSettings override + save_file rule), lockstep buffer + GameDS gate + LAN input path, battle-start
   sync in `f_020140c8`, checksums + DESYNC, abort path; flags `lan=`, `lanbattle=1`, `laninputs=`, `lanhash=`,
   impairment flags. Tests: two instances `lanbattle=1` with different rtc / menu detour / zoom: lanhash identical for 2600
   frames incl. pause + KO; `lanlag=80 lanjitter=20 lanloss=10`: still identical, stalls logged; kill the guest → host
   shows CONNECTION LOST and leaves to the lobby; guest settings.cfg after `kill -9` = its own values (diff before / after).
2. **LAN menus + keyboard**: QoLLanMenu pages, popups, QoLKeyboard (keys, pad, taps, real keyboard), CONNECTING / 15 s
   timeout, REJECT reasons, lobby with names / ping / status / addresses, PROPOSE / ACCEPT / DENY, LEAVE. Tests: captures of
   every page (`tools/qol_preview.tscn -- lan`), scripted key / tap runs, wrong IP → UNABLE TO CONNECT after 15 s,
   version / ROM mismatch (debug flag to fake a build id).
3. **Select / stage / battle integration + guest panel + ping**: `f_0207b778` → scene 4 mode 2 on both, READY wait +
   picks, stage select two outlines (remote from the network) + host 50/50 + STAGE_RESULT, 7 → 0 redirect, exits → 4 /
   0x11, save-copy swap, QoLLanPanel (pixel check vs the game's own panel for side 0), PING label, WAITING / DESYNC bands,
   BOMB RAIN LAN fixes. Tests: full two-instance flows (2 battles in a row, pause → character select, pause → Mode Select =
   lobby, B chains select → lobby → leave), guest taps (tag, support, Team Arts) act for P2 (CHT / MPB lines), boss /
   same / random characters, chaos + stage shuffle + bombs with different zoom on the two sides (no desync).
   **Status: DONE (part 30, phase 3)** — see 9.1.
4. **QA**: cheats / weird matrix in LAN battles (as part 28 did for LOCAL), long battles (10 000 lockstep frames), many loops
   (heap / file cache per round as part 27 b2), impairment, disconnects in every stage, crash restore, LOCAL MP and single
   player unchanged, then the user's PCs: Windows firewall prompt, Windows ↔ Steam Deck (Proton) cross-play (the libm
   question of 1.2: bombs use the table sine), Wi-Fi latency (input delay choice).
   **Status: DONE in this VM (part 30, phase 4)** — see 9.2; the user's PCs remain.

### 9.1 Phase 3 as implemented (part 30) — differences and additions to sections 3 / 4 / 6.1
Status: phases 1-3 done (phase 4 QA open at the time; done since, 9.2). Facts: DATA_NOTES "Session 1 part 30 findings (LAN select / stage / battle)".
- **Rounds**: every select message carries `round` = scene-4 entries since the last room entry (both machines count alike;
  reset when the VS menu shows again), so a message from the previous select is never taken for the new one.
- **Team select GO**: GO on a machine holds the READY? overlay and sends SELECT_READY {team, boss}; the **host** decides:
  when both are ready it sends SELECT_GO and leaves, the guest leaves when the GO arrives (one authority: no race between
  a READY and an UNREADY). B / BACK while waiting = SELECT_UNREADY. Upper-screen band: "WAITING FOR <NAME>..." /
  "<NAME> IS READY". The team sent is FUN_02066558's exit order (support moved behind the fighters, id 7 → 0x15 with 0x1E).
- **Leaving the select**: B with no picks = the game's own exit to 0x11 + LEAVE_SELECT; the other machine leaves too
  (`force_leave`: team emptied + one B press; in the stage select the screen's own B first). The team select's teardown
  calls FUN_02001014(2) before its real exit (the override remembers the scene before the 2).
- **Stage select**: STAGE_CURSOR {icon, chosen} on change; B with nothing chosen: host → STAGE_BACK (both back), guest →
  STAGE_BACK_REQ (the host answers STAGE_BACK unless it already decided). The host resolves the random icon (15) to a stage
  id (table u32 [0x020715FC], its own RNG); STAGE_RESULT = {round, icons, winner, stage, teams [host, guest], boss [host,
  guest]} + seed / delay / save; boss picks become `boss_teams` at the battle start on both machines. The DS input is blank
  in a LAN stage select (the loop's own A would confirm).
- **Guest panel** (QoLLanPanel): covers the game's three portrait slots and the Team Arts strip only (the rest of the
  game's lower screen stays) and draws through the game's own palette RAM (shader), so palette fades / animations of the
  game apply; pixel check for side 0: identical.
- **Notices**: the other player gone during a select / stage / battle → this machine returns to its room (host, room open)
  or the LAN page (guest) and shows "CONNECTION LOST" / "<NAME> LEFT" / "BACK TO THE ROOM" / "DESYNC" (QoLLan.notice,
  QoLLanMenu.show_notice). A proposal that arrives before the guest's room page is back is shown when it opens.
- **leave()** sends BYE and disconnects LATER (QoLLanNet.close_graceful): the other side gets peer_left, not lost.
- New QoLLan API: `sel_round`, `sel_on()`, `me()`, `force_leave`, `notice`, `in_flow`, `last_peer`, `loc_ready` /
  `remote_ready()`, `sel_filter()`, `stage_result()`; QoLGame `_lan_select()` / `_lan_stage()` / `_lan_sel_redirect()`.
- Debug flags: `lanpicks=a.b.c[@D]` (ids; "5b" = picked as a boss; D frames after the select starts, default 120),
  `lanstage=ICON[@D]` (default 90), `lanrounds=N` (after N selects: B with no picks), `lanleave=K` (leave the session
  10 frames into the K-th room visit; 1 = after joining), `lanpanel=0` (pixel check: side 0 drawn by the port in any
  battle), `lanauto` (host proposes on every room visit, guest accepts).
- Open (phase 4): ENet notices a killed peer 3-6 s late outside a battle (no traffic there but pings); the WAITING FOR
  PLAYER band needs a stall > 0.5 s (kept 0.4 s after it); the select / stage are not lockstep (each machine its own pace).

### 9.2 Phase 4 (QA + polish) as done (part 30) — facts: DATA_NOTES "Session 1 part 30 findings (LAN QA)"
- Fixed: PING measured the frame rate (25-42 ms real time / ~500 ms in captures on localhost) → network thread in QoLLanNet
  (1-3 ms; sends flushed at once, so input records also leave without waiting for the next frame); PING label redesigned
  (game font, yellow / white, black outline, signal bars as the colour hint); team-select band moved into the name strip;
  **rejoin deadlock** (battle ids counted per process: a host's 2nd battle vs a new guest's 1st waited forever) → ids reset
  per session; **false DESYNC at L1-L4** when the two machines had different histories (checksum read the previous battle's
  freed blocks before the loader) → checksum from FUN_0202A40C on; closing the window sends BYE ("<NAME> LEFT" instead of a
  lost connection); notices name the player who left; MULTIPLAYER row text no longer says "LAN (coming later)".
- Verified: every cheat and weird option in LAN battles with different local options on the guest, 10 000-frame battle, 6
  loops with stable heap, impairment through select / stage / battle, kill -9 / SIGTERM / window close / leave in lobby,
  select, stage, battle on both sides, settings.cfg after crashes, settings restored after leaving (menu capture), real-time
  and windowed runs with pipelining 1 / auto and smooth motion, two Windows exports under wine, Windows exe ↔ Linux export
  (accepted, identical), Windows exe ↔ editor (rejected: different build), off-identity / intro / LOCAL MP unchanged.
- Still open: a vanished peer (crash, cable pulled) is reported after ENet's 5-10 s timeout (WAITING FOR PLAYER meanwhile); a
  battle left during the VS intro waits for battle state 7 (up to ~12 s of the CONNECTION LOST band); real-time 59.8 frames/s
  with two windowed instances could not be shown in this 2-CPU llvmpipe VM (headless real time: 53-59/s, CPU bound); the
  user's PCs: Windows firewall prompt, Wi-Fi latency / delay choice, Windows ↔ Steam Deck (Proton) cross-play.

### 9.3 Part 31: rejoin / disconnect hardening — facts: DATA_NOTES "Session 1 part 31 findings (LAN rejoin / disconnects)"
- **The user's bug** (a guest that left and rejoined auto-picked a stage and loaded into a broken battle while the host waited
  in the stage select): QoLLan's select / stage state (`stage_res`, `go_round`, `rem_ready_round` / `rem_team`, the remote stage
  cursor) lived for the process, not the session, and rounds count from 1 in every session → the rejoined guest took the
  old session's SELECT_GO and round-1 STAGE_RESULT; its battle then started without session info (a plain Free Battle with
  the mode-2 party block → crash in the loader).
- **Now**: session id + flow id on every message, stale ones dropped; `_reset_flow()` at session start / end, ACCEPT and the
  room's return; a battle starts only on a STAGE_RESULT of this session / flow / round (else both go back to the room), on a
  copy taken at the redirect (a session ending during the load → a LAN battle left at once, never an unsynced one); battle ids
  come from the host's STAGE_RESULT (a battle only one machine started no longer breaks every later battle of the session);
  WHERE + watchdog (other flow / room / 2 steps for 5 s, 1 step for 30 s, a 20 s lockstep stall with the peer alive) → both
  back to the room with a notice; a HELLO while the host is not in its room → "HOST NOT IN ITS ROOM - TRY AGAIN".
- **Verified**: kill -9 / window close / SIGTERM of either side at every point (proposal, lobby, select, ready, stage, chosen,
  roulette, VS intro, battle, pause, battle end), rejoin after each (fresh process and same process, also three quick leave /
  rejoins and a host re-hosting), FULL from a third process during a battle, impairment through all of it, forced divergences
  (lanoos); every survivor back in its room / on the LAN page with a notice, guest settings.cfg unchanged, every battle that
  ran on both identical.
- **Limits**: SIGTERM kills Godot without `_exit_tree` (the other side sees CONNECTION LOST, not LEFT); a peer that vanishes
  without closing its socket is still reported after ENet's 5-10 s; the watchdog uses real time (5 / 30 / 20 s; ×4 in capture
  runs); a battle aborted in the VS intro still waits for battle state 7 (up to ~12 s).

---------------------------------------------------------------------------------------------------------------
## 10. Risks and fallbacks
- R1 Unknown divergence source (a code path not covered by the research runs: other characters' supers, summons, Shenron,
  stage events, time-up): the per-frame checksum detects it at once; `lanhash` + `landump`-style RAM dumps of both sides
  at the first bad frame + `tools/bdiff.py` find the field (as done here). Mitigation for a source that cannot be fixed:
  sync that field at battle start or exclude it if drawing-only.
- R2 Save-dependent gameplay beyond the loader (e.g. a later read of the options word): covered because the guest runs the
  whole battle with the host's save copy.
- R3 A mid-battle file load taking a different number of emulated scanlines (card timing depends only on emulated state,
  so identical — V: chaos shuffle loads in EA / EC stayed identical).
- R4 Long loading hitches (90-210 ms) on one machine: just a stall of the other; ENet timeouts are seconds.
- R5 Different refresh / pacing (60 Hz locked vs timed): time sync (2.1) and the faster machine's stalls; never fast-forward.
- R6 Proton / Windows float differences: only BOMB RAIN's `sin`; avoid transcendental math in gameplay hooks.
- R7 Scene-4 / scene-5 mode-2 side effects: none found (no wireless code); keep +0x33 = 1 (never 2) and clear +0x32 / +0x33
  before the battle; restore mode 2 + flags for scene 4 after it.
- R8 Players changing their CAMERA ZOOM etc. between battles: drawing only (A6/D6), excluded from the checksum.
- R9 If the two-outline stage select over the network proves awkward, fallback: the host picks the stage alone (guest sees
  the host's cursor), still sent in STAGE_RESULT.
- R10 Rollback is impossible (1.7); if input delay feels heavy on Wi-Fi, increase D adaptively per battle — never try
  prediction.
