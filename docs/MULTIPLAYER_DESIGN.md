# LOCAL MULTIPLAYER — reverse-engineering facts and implementation design (part 27)

> **Read this part for…** the whole design in one table: 0 · game facts per screen (VS menu, select, stage, battle
> input / panel, pause): 1 Q1-Q8 · scene redirects: 2 · per-file implementation and how it was actually built: 3 + the
> "Status (part 27)" paragraph in 4 · test inputs: 5 · risks: 6. Status: implemented (parts 27-29; later fixes in
> DATA_NOTES parts 28-29). The "LAN: not available yet" notice below was replaced by real LAN play in part 30
> (docs/LAN_DESIGN.md). Code map: docs/QOL_ARCHITECTURE.md; flags: docs/DEBUG_FLAGS.md.

Written by the research agent (session 1 part 27). Facts carry their confidence in `decomp/DATA_NOTES.md`,
"Session 1 part 27 findings (multiplayer research)"; this document repeats what implementers need and adds the
design. Evidence runs: `/tmp/ssw2/mp_research/` (script `run.sh NAME INPUTS CAP_FROM CAP_TO CAP_EVERY QUIT [flags]`).
Rule for everything below: **with MULTIPLAYER off (or no MP session running) every override only calls `super`**;
off-identity is checked with an off23.sh copy (/tmp/ssw2/btn) and cap.sh 10 2210 10 (/tmp/ssw2/intro).

---------------------------------------------------------------------------------------------------------------
## 0. Recommended architecture in one page

| Step | Where it runs | What the port does |
|---|---|---|
| Mode Select → VS BATTLE tile | game scene 0x11 (FUN_0207BA08), state 2 | keep the real screen; port overlay relabels HOST → **LOCAL**, CLIENT → **LAN**; `f_0207b778` override intercepts the choice |
| LOCAL → controller setup | still scene 0x11 state 2 | port-drawn page (QoLMenu style) over the screen's hexagon BG1; READY → "READY TO CONTINUE?" YES / NO |
| YES → character select | game scene 3 in **Practice mode (0xB)** | `f_02001014` redirects 4 → 3; `f_0206cc94` override = two port cursors that call the game's own pick code per player; two outlines = the game's outline object drawn twice, tinted (GX COLOR) |
| both READY → confirmation | scene 3's own **READY? GO / BACK** overlay (the "red / blue hexagons" of Z-Battle) | port sets confirm state; GO returns 0x8000 with side byte 1 |
| stage select | game scene 5 | `f_0207215c` override = two port cursors, outline object drawn twice; both picked → 50/50 → return 0x81 |
| battle | game scene 0, **mode 5 (Free Battle)** | `f_02001014` redirects 0x13 → 0 and sets mode 5; `f_0202dce0` (the CPU AI) replaced by P2's pad + touch; lower screen = port-drawn mockup layout (both teams), taps mapped per half to each side's touch fields |
| battle end / pause "character select" | FUN_02001014 from scene 0 | redirect to scene 3 (mode 0xB); B with no picks → back to controller setup |

Why this split: every screen keeps the game's own art, sounds, fades and loading; the port only replaces the
*inputs* of four functions that are each called exactly once per frame by their scene, and draws extra overlays.
The game's CPU opponent and its single-player touch handling are already "per side" in the engine (Q4 / Q5).

---------------------------------------------------------------------------------------------------------------
## 1. Answers to the research questions (short; addresses in DATA_NOTES part 27)

### Q1 Mode Select → VS BATTLE
- Tile 2 → scene **0x11 = FUN_0207BA08** (FUN_02075738 mapping; port probe: scene 0x11 state 2 from f2780 with
  `2141:Start:4,2396:T128/120:6,2560:Right:4,2590:Right:4,2660:A:4`). Capture: vs1/p2820.png (HOST 親 left, CLIENT 子
  right, top message "Starting Battle. After choosing a character, please select a stage and wait.").
- States (u8 0x020DD4C5): 0 fade, 1 load (FUN_0207BF70), **2 = choice FUN_0207B778**, 3-6 wireless, 7 fade,
  8/9 leave via FUN_02001014(work +0x18CB). Work block = u32 0x020E1148 (heap 0x164F4).
- FUN_0207B778 per frame: Left / Right toggle cursor u16 work+0x1066 (0 = left, 1 = right; SE 4); tap x 0..120 or
  136..256, y 48..144 selects / confirms; A confirms → returns 1 (left) / 2 (right); B → 3; else 0. Result 1/2 sets
  party +0x33 host/client and +0x18CB = 4 (team select) then fades; result 3 → Mode Select. Wireless starts only later
  (scene 4 / 7), so states 1-2 are a plain menu (FUN_020033C0 is the card pull-out callback, not wireless).
- Graphics (vs2 layersweep f2880, vs2_layers.png): lower = engine A. BG0 3D = yellow selection frame (object work+0x1068,
  vsmode.bin `tex_cursol1`, at (0x37,0x6E) / (200,0x6E)); BG1 = hexagon BG (vsmode.bin `bg`); **BG2 = both picture
  buttons incl. the kanji, the HOST / CLIENT label plates and the DBZ footer** (vsmode.bin `bg_tenka`, 256 colours).
  Upper = engine B: BG0 common_bg.bin frame, BG1 `msg_e` text; FUN_0207A31C(0/1/2) swaps the message (32x10 map region
  from work +0x15CF4 / +0x15F74 / +0x161F4).
- **Recommendation: enter the real scene 0x11 and repurpose it** (no wireless risk up to state 2). Relabel with a port
  overlay (`QoLMpMenu`, child of screen_root like QoLMenu): plates over the HOST / CLIENT label plates (white plate,
  black text "LOCAL" / "LAN", QoLFont BOLD) and a framed plate over each kanji box (black, yellow rim, HEAVY "LOCAL" /
  "LAN"), pictures kept; top message box: fill the box interior (brown) and draw the description in QoLFont (white,
  like QoLTopInfo). Alternative (exact pixels, more work): rewrite BG2 tiles in VRAM like QoLEpicImg does. Drawing our
  own menu over Mode Select is NOT recommended (loses the real screen and its fade / music).

### Q2 Free Battle flow and the party block
- Free: Mode Select tile 5 → scene 3 (mode 5) → scene 5 → scene 0 (battle). Practice: tile 6 → scene 0xC → scene 3
  (mode 0xB) → scene 5 → scene 0x13 (Practice battle). Same scene 3 / 5 code; mode decides limits and exits.
- The battle reads only the party block (u32 mode 0x020DD514, P1 s32[3] 0x020DD524, P2 s32[3] 0x020DD530, supports
  0x020DD53C / 0x020DD540, counts u8 0x020DD548 / 549, stage u8 0x020DD54A, boss level u8 0x020DD510 (0), CPU level
  0x020DD552). V (fb1): Free Goku vs Goku → mode 5, ids 0 / 0, counts 1 / 1, stage 0x0E. Writer: stage select exit
  FUN_02071374 (support moved last, FUN_02002838(side, id)); readers: FUN_020140C8 (battle start) / FUN_02013D60.
- Starting a battle "from our own data": write the block, then a scene must leave with FUN_02001014(0) after its own
  teardown. Do not switch the scene byte from outside (leaks the scene's heap / VRAM). **Recommended: drive the game's
  own select screens** (they write the block); redirect only the final scene number (0x13 → 0, mode 0xB → 5).

### Q3 Practice character select / stage select / confirmation
- Character select = scene 3 FUN_0206DCE8 (blocking loop, one pass per frame). Input → result: **FUN_0206CC94**
  (0x800 nothing, character id = pick for the side byte u8 0x020DEA2C, -1 refused, 0x8000 = GO). Picks s32[6] 0x020DE658
  (0-2 P1, 3-5 P2); current side's team s32[3] 0x020DE64C (duplicate / family / 2nd-support tests read it).
  FUN_0206ED18(id) commits a pick for the side byte (and redraws the PLAYER / ENEMY lists). B in the loop removes the
  LAST pick of all six slots (FUN_0206EABC), Start with a pick → READY?, A in READY? → GO.
- Grid (engine A lower; BG0 = 3D objects, BG1 = hexagon BG; prac2_layers.png): 16 hexes, **ids share hexes — the DP
  tab (u32 0x020DB534, 0-6 = DP1-7, 7 = SP) decides which character a hex shows lit**. Tab members 0x020D060C, first id
  0x020D0400, SP = supports 26-35 (hex list 0x020D05D8). Neighbours per id 0x020D0530: Left, Right, Up (previous tab),
  Down (next tab). Cursor block 0x020DE9B8: +0x57 cursor id, +4 outline object, +8 DP-label object, +0x28 DP digits.
- Outline = 3D quad object drawn by FUN_0200AEBC / FUN_0200AB48 (from FUN_0206A3D8). Objects: +5 alpha (0 = hidden),
  +0x3C / +0x40 / +0x44 x / y / z in 20.12; position = hex x + 0x16, hex y + 0x10 (FUN_0206A980). No COLOR command in
  the drawer → **a GX COLOR written before the draw call tints it** (white outline × red = red). Second outline = draw
  the same object again at P2's hex (see 3.5). **Verified** in a scratch copy (`mptint`,
  /tmp/ssw2/mp_research/tint1_sheet.png): red outline on Goku, blue on Piccolo, the game's pulse intact.
- Input there: pad block via FUN_02001230 (pressed) and TPData rects via FUN_02009844 — only P1's DS. P2 must come
  from the port: override FUN_0206CC94 (called once per frame) and run both cursors in the port.
- Confirmation "with red / blue hexagons" = the READY? overlay (GO red circle / BACK blue circle) of scene 3 / 4
  (zb2 f2820, prac2 f3120): confirm state u32 0x020DE8AC+0x10 (FUN_0206A748(1) shows it). It is part of scene 3, so it
  is available in the Practice flow (prac2 shows it after each side). GO rect x 131..171 y 43..87, BACK x 75..117
  y 98..142.
- Stage select = scene 5: per-frame input FUN_0207215C (returns 0x81 = confirm), cursor icon s16 0x020DEB2C (4x4,
  Up/Down ±4, Left/Right ±1 in the row), cursor objects [0x020DEB0C+0xC] / [+0x10] drawn by FUN_0200AB48 inside
  FUN_02071E64, positions u16 0x020D0768 / 0x020D076A (stride 8). Icon → stage 0x020D0758; icon 15 = random.

### Q4 Battle input
- Input function pointer **G + 0x1BCB4** (G = u32 0x020DE3A0) = **FUN_02012DA8** in every non-wireless battle (V fb1).
  It copies the pad block (0x020DD4DC +0/+2/+4) into P1's active record +0x26C / +0x26E / +0x270 and, in action 0 / 5,
  the touch (TPData 0x020DE208 → +0x264..+0x26A, flags 0x020DE1F4 → +0x263). P2: `p = FUN_0202DCE0(P2 rec, P1 rec)`
  = **the CPU AI**, which returns a fake pad + fake touch (u16[0..3] → +0x26C/E/70/72, [4..7] → +0x264.., byte +0x10 →
  +0x263). FUN_0202DCE0 is called only from FUN_02012DA8.
- **Cleanest hook: override `f_0202dce0`**: in an MP battle return the address of a port-only RAM struct filled with P2's
  pad words + P2's touch (layout above); otherwise `super`. P1's path stays 100 % original. No AI runs for P2 (its RNG /
  AI state simply do not advance). **Verified** in a scratch copy (`mpai`, /tmp/ssw2/mp_research/ai1.log +
  ai1_sheet.png): without input P2 stands still; held LEFT → action 3, x 8256 → 8088; A → ki blasts (0x24). Alternative: override `f_02012da8` and write both records (needed only if P1's touch
  must not come through the DS touch screen; not recommended).
- Wireless "human P2" exists (FUN_020789A8 reads both pads from scene 7's link block u32 0x020E1144 +0x1D1F0..) but it
  needs scene 7's lockstep machinery; not reusable. Nothing else in the battle treats P2 as CPU except: boss level
  (0 in Free), VM op 0x92 (boss only), AI. P2's directions are absolute like P1's.

### Q5 Battle lower screen
- Single player: engine B BG0-2 (BG-manager layers 4-6) = three 80x128 portraits (SubScrNBFC/NBFS.bin, entry = id)
  + `e_pairatk` Team Arts / Touch! bar (game_subbg.bin), palette game_bg.arc #0x66, drawn by FUN_0201B78C for the
  local side (G + 0x1BCA9 = 0) only; highlight FUN_0201CA60 only for the local side.
- Actions (neutral handler FUN_0202CC70, when the fighter's +0x263 bit 0 is set): FUN_02026E34 Team Arts (touch in
  8,144 - 248,184; ki 200 %; >= 2 members), FUN_02026C00(f,1) assist (touch inside the support's panel), FUN_02027164
  (f,1,20) tag (touch inside a bench member's panel; ki >= 20 %). **All parameterised by the fighter (side +0x1A)**; the
  touch test FUN_02029084(side, rect) reads that side's active record. Panel rects exist for every record of BOTH
  sides (loader FUN_0202A40C): member k = x 8+80k .. 88+80k, y 16 .. 136. The AI taps rect + 0x20 (FUN_0202D66C /
  FUN_0202D820). ⇒ P2 switches / calls support / team-attacks exactly like single player by putting a touch at those
  coordinates into P2's struct (flags: 3 on the first frame, 2 while held, 4 on release, 0 otherwise).
- P2's portraits are not in VRAM (the game loads only the local side's). Decode from the ROM at MP start: portrait
  tiles SubScrNBFC.bin[id] + map SubScrNBFS.bin[id] (cols 0-9 of 16, rows 0-15), palettes: **colour (active) =
  scene/common/CharFace.bin `<abbr>_face.nbfp`** (verified: gho renders exactly as the mockup's Gohan,
  portraits3.png), inactive / bench / support = game_bg.arc #0x66 row 0, KO'd = row 4 or 7 (dark); Touch! art and
  diamond from game_subbg.bin `e_pairatk` (red diamond; blue = palette swap). QoLEpicImg already has pack reading,
  decompression and BG → pixel helpers (`_pack`, `member`, `_decompress`, `bg_to_px`).

### Q6 Pause and battle end
- Start (pad block) in state 7 → pause (state 9, FUN_0201546C: A / B / Start from the pad block). Pause items: 2 →
  next scene G+0x1BCAE = 3 (character select) in Free, 4 → 6 (Mode Select). KO: Free goes to 0x14 (Game Over /
  Continue) when P1 lost (loser u32 [teams+0x11D4] side 0), else 10 (results). Every exit = FUN_02001014(scene) after
  the battle teardown → **override `f_02001014`** to send an MP battle's exits 0x14 / 10 / 3 / 0xD to scene 3 with
  mode 0xB (6 = leave MP: Mode Select).

### Q7 P1-only cheats (QoLGame) and the MP change
| Cheat | Where (qol_game.gd) | P1 test today | MP change |
|---|---|---|---|
| infinite_health | f_020293a4 | `p1 = rec+0x1A == 0` → damage 0 | no damage for either side's records |
| one_hit_ko | f_020293a4 | `not p1` (enemy dies) | any unguarded hit KOs on both sides |
| hard_mode | f_020293a4 | P1 ×2, enemy ÷2 | symmetric ×2 for both (or ignore in MP; decide with the user) |
| infinite_ki | f_02027950 (`+0x1A == 0` → no spend), f_0202954c P1 block (P1 team +0x8D0 = full) | side 0 | both sides: spend skipped for side 1 too; P2 team block (teams+0x8E8)+0x8D0 = full |
| ki_homing | f_020209e0 / `_home` (`+0x1A == 0`, owner = f_02027c00(0), target f_02027bd0(0)) | side 0 | owner = active of the object's side, target = f_02027bd0(side) |
| no_cooldown | f_0202954c P1 block → `_cancel_attack` | side 0 | also for the P2 active record |
| attack_spam | f_0202954c P1 block → `_spam_tick`; f_02027c2c (`+0x1A != 0` skip) | side 0 | both sides |
| infinite_assists | f_0202a40c `_assists` (P1 +0x8CA), f_0202954c rewrite | side 0 | per-side `_assists[2]` |
| assist_spam | f_02026c00, f_020277ac (`+0x1A != 0` → super), f_020294b8 | side 0 | both sides (copies use the caller's team support; part 29: 8 per side, each side's copies only while its own slot is busy) |
| character_shuffle / chaos_shuffle | f_0202954c P1 block → `_shuffle_tick` | side 0 | both sides (per-side timers; lower-screen refresh: the MP panel re-reads ids, FUN_0201B78C only for side 0) |
| triple_ki | f_020225c8 (line ~1514: `+0x1A == 0`) | side 0 | both sides |
| boss_characters | `_note_pick` reads L from KEYINPUT (P1's DS) | P1's L | the MP select passes the picking player's L state |
| random_characters | f_020140c8 `_randomize_party` (P1 party) | P1 party | both parties |
| same_characters | f_0206cc94 / f_0206abb0 | — | the MP select override honours it (skip the duplicate test) |
| stage_shuffle, random_stage, random_music | global | — | none |
Implementation: one helper in QoLGame, e.g. `_helped(rec) -> bool: side == 0 or (_mp_battle and side == 1)`, used
in place of each `+0x1A == 0` test; team-level writes loop over `_mp_sides()` (`[0]` or `[0, 1]`). Off: identical.

### Q8 Port input
- GameDS._tick_begin builds KEYINPUT from InputMap actions `ds_*` (`Input.is_action_pressed`, device-agnostic: every
  pad drives P1) + `_tapped` latches from `_input`; touch = mouse over the lower screen, else `qol.cursor_touch()`
  (QoLCursor, actions `qol_cur_*`, any pad); then `qol.filter_input(keys, ext, touch)`; mirror swap; `machine.keyinput`.
- QoLControls owns one mapping per DS button (one key + one pad code: "k:<keycode>", "b:<button>", "a:<axis>:<±1>";
  `code_of` / `event_of` / `name_of`; saved in settings.cfg [controls]); raw events reach the CONTROLS page through
  `QoLController.raw_input`.
- Per-device input: `InputEvent.device` is the pad index for joypad events (keyboard / mouse events are not joypad
  events, so pads and keyboard never collide). InputMap actions match all devices unless the event's device is set.
  **Recommended: do not use the InputMap for MP players** — a `QoLMpInput` polls each player's own mapping per device
  (`Input.is_physical_key_pressed`, `Input.is_joy_button_pressed(dev, b)`, `Input.get_joy_axis(dev, a)`) and latches
  short presses from `_input` filtered by `event.device`. P1 in MP: keyboard (existing ds_* key codes) and/or its pad;
  P2: its pad or a second key set. Cursor: one QoLCursor per pad player (`device` field, axis read with
  `Input.get_joy_axis(device, …)`), red / blue tint.

---------------------------------------------------------------------------------------------------------------
## 2. Flow and scene redirects

```
Mode Select (6) --tile 2--> VS menu (0x11) state 2
   [LOCAL] -> port page CONTROLLERS (still 0x11, game input blocked) -> READY -> "READY TO CONTINUE?" YES
        -> our f_0207b778 returns 2 (CLIENT path: the scene tears itself down + fades)
        -> state 8: FUN_02002738(1); FUN_02001014(4)   ==f_02001014==>  scene 3, mode 0xB, party +0x32/+0x33 = 0
   [LAN]   -> notice "LAN: not available yet" (future work), stays   (part 30: opens the LAN pages, LAN_DESIGN 0)
   [B]     -> Mode Select (game's own)
Character select (3, mode 0xB, MP): two cursors -> both READY -> READY? overlay -> GO -> scene 5
   B with no picks (both empty) -> loop exits to 0xC   ==f_02001014==>  0x11 (setup page reopens)
Stage select (5, MP): two cursors -> both picked -> 50/50 -> 0x81 -> FUN_02071374 -> FUN_02001014(0x13)
                                                      ==f_02001014==>  scene 0, mode 5
Battle (0, mode 5, MP): P2 human, MP lower screen; end / pause "character select" -> FUN_02001014(0x14|10|3|0xD)
                                                      ==f_02001014==>  scene 3, mode 0xB
   pause "Mode Select" (6) -> end the MP session
```
`f_02001014(scene)` override (QoLGame): only acts while `mp.session` is set; reads the current scene u8 0x020DD4C4
(before super changes it) and maps, writing the extra RAM before calling super: (0x11 → 4) ⇒ 3 [mode 0xB; party
+0x32 = +0x33 = 0 — FUN_02002738(1) already ran just before FUN_02001014]; (3 → 0xC) ⇒ 0x11 [`mp.reopen_setup`; the
loop writes mode 6 right after the call, harmless: 0x11 → 3 sets 0xB again, risk R4]; (5 → 0x13) ⇒ 0 [mode 5];
(0 → 0x14 / 10 / 3 / 0xD) ⇒ 3 [mode 0xB]; (0 → 6) ⇒ 6 and end the session. Everything else: super.

---------------------------------------------------------------------------------------------------------------
## 3. Design by part

### 3.1 Files, data, settings
New files (all scripts/qol/, each its own section header `# ---- MULTIPLAYER (part 27)`):
- `qol_mp.gd` — `class_name QoLMp` (RefCounted): the session. Fields: `active: bool` (a LOCAL session is running),
  `stage: int` (SETUP, SELECT, STAGE, BATTLE), `dev: Array[2]` (device ids: -1 keyboard, 0..n pad), per-player
  `held / pressed / released` (12-bit DS layout: 0x001 A, 0x002 B, 0x004 Select, 0x008 Start, 0x010 Right, 0x020
  Left, 0x040 Up, 0x080 Down, 0x100 R, 0x200 L, 0x400 X, 0x800 Y), `touch: Array[2]` (Vector2i panel coordinates or
  (-1,-1)) + `tflags: Array[2]`, select state (`cur[2]` ids, `tab`, `ready[2]`, `picks` mirror), stage state
  (`icon[2]`, `chosen[2]`). Written by the main thread in `_tick_begin` (before step_begin), read by QoLGame
  overrides on the game thread — same hand-off as `machine.keyinput`.
- `qol_mp_input.gd` — `class_name QoLMpInput`: per-player mapping (same code strings as QoLControls; P1 = the
  current ds_* mapping restricted to P1's device, P2 = own mapping saved in settings.cfg [mp]), `poll(p) -> int`,
  `latch(event)` (from GameDS._input, by `event.device`), `name_of_device()`.
- `qol_mp_menu.gd` — `class_name QoLMpMenu` (Control under screen_root): LOCAL / LAN relabel overlay, the
  CONTROLLERS page, READY TO CONTINUE? page; QoLMenu look (hexagon buttons, QoLFont), menu sounds `qol.se()`.
- `qol_mp_panel.gd` — `class_name QoLMpPanel` (Node2D under screen_root): the battle lower screen (mockup) + hit
  regions; textures decoded from the ROM once per battle (both teams' ids from the party block).
- QoLGame (`qol_game.gd`): a new section `# ---- MULTIPLAYER (part 27)` with the overrides of 3.3-3.7, field
  `mp: QoLMp = null` (null when the setting is off or no session → every override is `super` only).
- QoLSettings: `multiplayer` (bool, page MULTIPLAYER — exists per PART 27 NOTES), plus [mp] cfg keys: `p1_device`,
  `p2_device`, `p2_<button>_key`, `p2_<button>_pad`.
- Port-only RAM: `MP_AI_OUT := 0x027C1000` (0x20 bytes, the struct returned by f_0202dce0). The port maps 8 MiB flat;
  in use: 0x02700000, 0x02710000, 0x02740000, 0x02760000, 0x02780000 (debug), 0x027B0000, 0x027C0000 (8 bytes).

### 3.2 Input path (GameDS + QoLController)
- `GameDS._input`: also `qol.mp_latch(event)` (before the existing handlers; never consumes).
- `GameDS._tick_begin`: if `qol.mp_active()`: `keys/ext` for the DS = `qol.mp_ds_keys()` instead of the ds_* actions
  (P1's device only, plus injections below); the touch for the DS = `qol.mp_ds_touch(touch)`; compute P2's words and
  both players' battle touches into QoLMp. Scripted input keeps working: `inputs=` drives P1, new `p2inputs=` drives P2.
- What the DS (game pad block) sees in MP, by stage:
  - SETUP (scene 0x11 page open): nothing (0x3FF), touch none — the port menu gets both players' presses.
  - SELECT / STAGE: nothing, except one-frame injections the overrides request (`mp.inject`: B to leave when both
    teams are empty, B in stage select = back). Touch: none (port handles READY? taps itself).
  - BATTLE: P1's buttons; P2's Start ORed in (pause); in pause (u8 0x020DD4C5 == 9) and in states 0x0F-0x14 both
    players ORed (either may navigate). Touch: a tap on P1's half is mapped to P1's panel coordinates and given to the
    DS touch screen (the game's own P1 path); a tap on P2's half never reaches the DS, it goes to `mp.touch[1]` (3.7).
  - MIRROR MODE: swap LEFT / RIGHT for P2's word too.
- Touch per half (battle): mouse: x < 128 → P1, else P2; pad cursors: each player's QoLCursor, clamped to its own half
  in battle (free elsewhere). Region → panel coordinates in 3.7.

### 3.3 VS menu: LOCAL / LAN (scene 0x11)
- `f_0207b778` (QoLGame): `if mp == null or not cheats.multiplayer: return super`. Otherwise:
  - setup page open (`mp.stage == SETUP`) → call super anyway (the DS input is blank in SETUP, so it only runs its
    drawing tail: FUN_02011F98 cursor frame + FUN_0207A1F4 blink) and return 0 whatever it returns.
  - else r = super(); r == 1 (left, LOCAL) → open the setup page (`mp.stage = SETUP`), return 0; r == 2 (LAN) → notice,
    return 0; r == 3 → return 3; `mp.go` (YES was chosen) → return 2 (client path; see section 2).
- Overlay (QoLMpMenu): drawn while u16 0x020DD4C4 == 0x0211 (scene 0x11, state 2): label plates over HOST
  (≈ x 12..48, y 146..158 of the lower screen) and CLIENT (≈ x 200..244, y 32..46) → LOCAL / LAN; the picture buttons
  (yellow rims: left x 0..118 y 48..143, right x 139..253 y 50..141, measured on vs1/p2820.png) get a plate with the
  word over the kanji; top message box (upper screen ≈ x 10..246, y 46..148)
  text by cursor (work u16 0x020E1148→+0x1066): LOCAL "Two players on this PC. Set up both controllers, then pick
  your fighters." / LAN "Play over your network (coming in a later version)." Measure exact boxes from vs1/p2820.png
  in tools/qol_preview.tscn.

### 3.4 Controller setup (port page, still scene 0x11 state 2)
- Layer keep: `display.set_layer_keep(true, 0x200)` (only BG1 hexagons on the lower screen), like QoLMenu.
- Rows: `PLAYER 1  [DEVICE ◀ KEYBOARD ▶] [CONTROLS SET]`, `PLAYER 2  [DEVICE ◀ PAD 1 ▶] [CONTROLS SET]`, `[READY]`.
  Device list: KEYBOARD, then every `Input.get_connected_joypads()` (names via `Input.get_joy_name`). Defaults: P1
  keyboard (+ pad 0 if it is the only pad and P2 has the keyboard), P2 = first pad not used by P1, else KEYBOARD 2 (a
  second key set; proposed defaults that avoid P1's keys (arrows, X Z S C A D, Enter, Backspace): I K J L = Up Down
  Left Right, N = A, M = B, H = X, G = Y, U = L, O = R, P = Start, Y = Select; pads use the same button codes as
  QoLControls' pad defaults). CONTROLS SET opens a 12-row mapping page per player (reuse QoLControls' row drawing / capture logic;
  a capture accepts only events from that player's device). Both players can move a cursor on the page (P1 red, P2
  blue highlight) — or simpler: one shared cursor driven by either player (recommended for v1).
- READY → page "READY TO CONTINUE?" YES / NO (lbconfirm style, NO first, B = NO). YES → `mp.go = true` (3.3).
- B on the first page → close, back to LOCAL / LAN (the scene's own screen).
- Save [mp] in settings.cfg on YES.

### 3.5 Character select (scene 3, mode 0xB, MP)
State in QoLMp: `cur = [id1, id2]`, `tab` (shared), `ready = [bool, bool]`, picks = the game's 0x020DE658 (read back).
Override `f_0206cc94` (QoLGame; existing same-characters code stays in the non-MP branch):
```
if mp == null or mp.stage != SELECT: (existing code)
if confirm (f_0206a76c() == 1):            # READY? overlay shown
    A from either player or a tap in the GO rect → _st(0x020DEA2C, 1, 1); return 0x8000   # scene → stage select
    B from either player or a tap in BACK     → f_0206a748(0); mp.ready = [false, false]; return 0x800
    return 0x800
for p in [0, 1]:
    dirs: Left/Right → cur[p] = NB[cur[p]][0/1] (0x020D0530); Up/Down → tab ± 1 (wrap 0..7; from SP only Up to DP7 /
          Down to DP1) for BOTH players: each cursor → its own NB[...][2/3] if that id is in the new tab, else the
          tab's first id (0x020D0400[tab]); write u32 0x020DB534 = tab; f_0206adb8()   ("one goes to SP, the other is
          brought along")
    A → pick(p, cur[p]) (one pick per frame; a second player's pick waits one frame)
    B → unpick_last(p)  (or, when both teams are empty, mp.inject = B → the loop leaves → redirected to setup)
    Start → ready[p] = (player p has >= 1 pick); X → toggle SP shortcut (optional)
if ready[0] and ready[1]: f_0206a748(1)    # READY? overlay (the game draws it, FUN_0206A4B8)
# visuals for the game's own cursor = P1 (only when cur[0] changed: FUN_0206A980 also restarts the outline's
# pulse counter +0x5C/+0x5E, so calling it every frame would freeze the animation)
_st(0x020DE9B8 + 0x57, 1, cur[0]); f_0206a980(5)   # 5 = just reposition objects (+4/+8) and neighbours
f_0206abb0()                                          # grey-outs (the original ends with it)
return pending_pick_result or 0x800
```
- `pick(p, id)`: refuse like the original FUN_0206CC94 does: f_0206a77c(id) == 0 (locked), duplicate in player p's
  picks (unless same_characters), f_0206a688(id) family (unless same_characters), id >= 26 and player p already has a
  support (f_02069488 + f_02066088 after loading 0x020DE64C), team full (3 slots incl. the support). Then: side byte
  u8 0x020DEA2C = p; 0x020DE64C[0..2] = 0x020DE658[3p..3p+2]; return id (the loop calls FUN_0206ED18(id), which fills
  the next free slot of that side, DP displays and the PLAYER (p = 0) / ENEMY (p = 1) list). Refused → SE 7 (buzzer,
  `qol.se(7)`); accepted SE as the game (the loop plays it). BOSS CHARACTERS: note the pick with player p's L.
- `unpick_last(p)`: last non-(-1) slot k of 0x020DE658[3p..3p+2]: f_02065e90(3p+k, -1), f_02065e70(k, -1) (after
  loading 0x020DE64C for p), the slot's DP display (f_02066ca4 / 94 / 84 (0) for k = 0 / 1 / 2) with side byte p, then
  f_0206ef54(); f_0206fa64(); (mirrors FUN_0206EABC for one slot). The game's own B path would pop the last pick of
  BOTH sides, so never let a raw B reach the loop while picks exist.
- "Up to 3 fighters + support": the team block holds 3 records, so a team is at most 3 entries **including** the
  support (the game's own rule). The design keeps that.
- Outlines (two, tinted): override **`f_0200aebc`** and **`f_0200ab48`** (menu object drawers; cheap test first):
```
if mp == null or not mp.dup.has(obj): return super
for e in mp.dup[obj]:            # [[o, x, y, color], …] filled each frame by the select / stage overrides
    o = e.o (usually obj itself; the stage select may need its other cursor variant)
    save o+0x3C/+0x40; write e.x << 12, e.y << 12; io_write(0x04000480, 4, e.color); super(o); restore
io_write(0x04000480, 4, 0x7FFF); return 1
```
  (Verified pattern: /tmp/ssw2/mp_research/proj, `# ---- MP RESEARCH (debug)`, f_0200aebc.)
  For the select: objects u32 [0x020DE9B8+4] (outline) and [+8] (DP label): entries for P1 at hex(cur[0]) (red
  0x001F) and P2 at hex(cur[1]) (blue 0x7C00); same id → one entry, purple 0x7C0F. Position = (u16 0x020D04F0[hex·2] +
  0x16, u16 0x020D04F2[hex·2] + (0x10 if x+0x16 < 0x60 else 0xF)), hex = u8 0x020D04A0[id] (SP ids: their hex from
  0x020D04A0 too). GX COLOR tinting is verified (tint1_sheet.png); the DP-label object [+8] can stay untinted.
- Top screen: the game's PLAYER / ENEMY lists = P1 / P2. Optional overlay: "1P" / "2P" over the PLAYER / ENEMY labels
  and a READY tick per player.
- Touch: ignored in MP select except the READY? GO / BACK rects (both players).

### 3.6 Stage select (scene 5, MP)
Override **`f_0207215c`**: `if mp == null or mp.stage != STAGE: return super`. Else: r = super() with the DS input blank
(keeps the bar scroll and positions the game's own cursor objects from u16 0x020DEB2C); then for each player: Left /
Right ±1 within the row (wrap like FUN_02071F18), Up / Down ±4 (wrap mod 16); A → `chosen[p] = icon[p]`; B → un-choose
(both un-chosen + B → `mp.inject = B` = back to the select). Write s16 0x020DEB2C = icon of the player who moved last
(the top screen's stage name / description follows it) and set `mp.dup` for BOTH cursor objects A = [0x020DEB0C+0xC] and
B = [0x020DEB0C+0x10] (the game draws only one of them per frame, chosen by its own cursor's column: FUN_020724B4 →
+0x22, FUN_02071E64) to the same list: one entry per player [object for that player's column (A for columns 0 / 2,
B for 1 / 3), x = u16 0x020D0768[icon·4], y = u16 0x020D076A[icon·4], red / blue; same icon → one purple entry]. When both chose: pick one 50/50 (QoLMp rng; same icon →
that one), optional 40-frame flicker between the two, write 0x020DEB2C = winner, return 0x81 → the loop confirms →
FUN_02071374 commits → FUN_02001014(0x13) → redirect to 0 with mode 5 (section 2).

### 3.7 Battle (scene 0, mode 5, MP)
- **P2 input** — override `f_0202dce0(p2rec, p1rec)`: `if mp == null or mp.stage != BATTLE: return super`. Else fill
  MP_AI_OUT: u16 +0 pressed, +2 released, +4 held (P2's DS-layout word; edges against the held word of the previous
  CALL), +6 0, +8 x, +0xA y, +0xC touch (1 while touching), +0xE validity 0, u8 +0x10 flags (3 first frame of a touch,
  2 held, 4 the frame after release, else 0); return MP_AI_OUT. FUN_02012DA8 copies all of P2's fields every frame
  (P1's touch only in actions 0 / 5); the neutral handler acts on +0x263 bit 0 only in actions 0 / 5 anyway, so a tap
  made during an attack is lost exactly like a P1 tap in single player. Keep a tap's flags at 3 for its first CALL
  (not its first port frame: hit-stop frames do not call the input function).
- **P1 touch**: P1's taps on its half are mapped (table below) and sent to the DS touch screen
  (`machine.core.arm7.set_touch`) → the game's own P1 path. Nothing else in a fight reads the DS touch.
- **Lower screen** (QoLMpPanel): hide engine B's BG layers on the lower screen while `display.battle_on_screen()` and
  MP battle (`display.set_layer_keep(true, mask)`: 0x1F00 = all layers, 0x100 << n = BG n; use a mask without BG0-2 —
  check the backdrop), draw the mockup layout
  (docs/mp_mockup.png (local only, not in git: cut from the game's art) = 256x192 × 2.8; measured): columns P1-A x 0-59, bar 60-67, P1-B 68-126, black divider
  127-129, P2-A 130-188, bar 189-196, P2-B 197-255; rows 0-94 / line 95 / 96-191. Per player (A = its first column,
  B = its second):
  - A top: active portrait (60x95 crop of the 80x128 portrait — e.g. x 10..69, y 0..94; compare with the mockup), in
    **colour** (palette CharFace.bin `<abbr>_face.nbfp`).
  - A bottom: bench, the two bench members split by the line (0, 158) – (59, 129) (local x): upper-left part = first
    bench member in party order after the active one, lower-right = second; palette #0x66 row 0; KO'd member dark
    (row 4 / 7); one bench member → the whole box; none → empty `nul1` art.
  - B top: support portrait (row 0; greyed when team +0x8CA == 0); no support → `nul1`.
  - B bottom: Touch! plate (brown, e_pairatk-style frame) with the diamond (red P1, blue P2) and "Touch !" text; dim
    while team ki (team +0x8D0) < 0xC800 (200 %) or < 2 members.
  - Bars blue-grey with dark 1-px edges, black frame lines as in the mockup.
  - Live state each frame from RAM: active index team +0x8C8, count +0x8C9, assists +0x8CA, team ki +0x8D0, ids rec+5,
    HP rec+0x24A (KO ≤ 0); teams = u32 0x020DE3D0, team p = teams + p·0x8E8, record k = team + k·0x2D8.
- **Tap mapping** (screen region → DS panel coordinates written as the side's touch): bench part for party slot k →
  (8 + 80k + 40, 76); support box (support at party slot k_s) → (8 + 80·k_s + 40, 76); Touch! → (128, 164); active
  portrait → no touch. Held for as long as the finger / click is held (flags 3 → 2 → 4). P1's mapped point goes to
  the DS touch screen, P2's into MP_AI_OUT.
- **Part 29**: each side has its own assist slot in an MP battle (QoLGame `# ---- MP DUAL ASSISTS`: both supports on screen
  together, also the same character; one at a time per player, ASSIST SPAM per side) and each side's Touch! light is
  recomputed every frame (`# ---- MP TEAM ARTS LIGHT`: the game computes the Team Arts partner bit only for the local
  side at the loader). DATA_NOTES part 29.
- Pause: Start of either player (3.2). Battle end → section 2 redirect. Optional banner "PLAYER n WINS" in states
  0x10 / 0x11 (loser = u32 [teams + 0x11D4] side).
- AI-only state that becomes unused: CPU level 0x020DD552 (keep), boss level 0x020DD510 (0 in Free; BOSS CHARACTERS
  handles picks itself).

### 3.8 Cheats in MP
As in the Q7 table. Gate everything with `_mp_battle` (QoLMp stage BATTLE) so non-MP play is byte-identical.

---------------------------------------------------------------------------------------------------------------
### 3.9 Reference code from the research (scratch only)
/tmp/ssw2/mp_research/proj/scripts/qol/qol_game.gd, section `# ---- MP RESEARCH (debug)` at the end: working
`f_0200aebc` duplicate-and-tint and `f_0202dce0` P2-struct overrides (debug flags `mptint`, `mpai`, `mprdbg`), and
/tmp/ssw2/mp_research/run.sh / runp.sh (repo / scratch project runners). Copy the patterns, not the scripted values.

## 4. Phases (each ends with the listed test; one Godot run at a time)

1. **Battle core (no menus)** — `mpbattle=1` debug flag: the normal Free Battle (btnrun inputs) becomes an MP battle at
   its FUN_020140C8 (QoLMp stage BATTLE, devices from flags). Implement f_0202dce0, `p2inputs=`, the cheat
   generalisation. Test: btnrun + `mpbattle=1 p2inputs=4600:A:4,4700:Y:4,4800:R:40,4900:B:40 cheatdbg`: CHT lines
   show P2 actions 0x24 / 0x1C / 0x0C / 0x18 at those frames; P2 no longer moves on its own (no input → P2 stands);
   P2 tag via `p2inputs=…:T<x>/<y>:6` once the panel mapping exists (phase 2).
2. **Battle lower screen** — QoLMpPanel + tap mapping + per-half routing. Tests: captures of the lower screen vs the
   mockup; P1 panel pixels vs the game's own panel (same tiles / palette rows); P1 tap on the bench → tag (CHT active
   index changes), P2 tap → P2 tag, support call (action 0x28), Touch! with ki poked to 0xC800 (`poke=` team +0x8D0)
   → action 0x30.
3. **Device input** — QoLMpInput, two cursors, GameDS hooks, keyboard / pad separation (test with `fakepad` variants;
   on the user's PC with two real pads).
4. **VS menu + setup page** — f_0207b778, f_02001014 (0x11 → 3), QoLMpMenu. Test: vs1 inputs + `mp=1` + A at the
   LOCAL button → setup page → READY → YES → scene 3 mode 0xB (probe 020DD4C4;020DD514).
5. **Character select** — f_0206cc94 MP branch, f_0200aebc / f_0200ab48 duplicates, READY? → GO. Test: picks for both
   players visible in the PLAYER / ENEMY lists, outlines red / blue / purple, SP tab moves both, 0x020DE658 contents.
6. **Stage select + battle start + loop back** — f_0207215c, redirects 0x13 → 0 (mode 5) and battle exits → 3.
   Test: full flow to a battle and back to the select; pause → character select; B chain back to setup.
7. **Polish** — top-screen labels, winner banner, LAN notice, settings page text, README.
Off-identity after every phase: off23.sh copy vs /tmp/ssw2/btn (21 PNGs + CHT lines to 5300) and intro 221/221.

Status (part 27): phases 1-7 implemented. Phases 5-7 as built (differences from the plan above): the select runs the
game's own FUN_0206CC94 once per player with that player's pad words / repeat counters / cursor bytes / tap / side /
team swapped in (instead of re-implementing moves and pick tests); a tab change brings the other cursor to the same
fighter; a face is greyed when every player still picking would be refused it (part 27 QA); the outline AND its pulse ring (+8) are tinted; FUN_02069990 is wrapped
(it opens READY? by itself when the drawn side's team is full); the stage cursor's palette is forced white
(FUN_02070718) so the tint shows, the cursor is drawn per player by an f_02071e64 override (not f_0200ab48); a tap on
a stage icon chooses it; the 50/50 is a roulette (12 switches slowing down + 36 frames on the winner); QoLMpSelect adds
1P / 2P tags, READY plates, CHOOSING / READY bands and a PLAYER n WINS band; the MP panel also covers the battle's VS
intro. Facts: DATA_NOTES "part 27 findings (MP select / stage / loop)".

## 5. Debug flags and test inputs
Flags (implemented as proposed; current list with LAN / later additions: docs/DEBUG_FLAGS.md): `mp=1` (MULTIPLAYER on for the run), `mpbattle=1` (phase-1 shortcut),
`p2inputs=F:Btn[+Btn]:N[,F:T<x>/<y>:N]` (P2 pad / P2-half taps in lower-screen coordinates), `mpdev=p1,p2` (devices,
e.g. `k,0`), `mpdbg` ("MP f<frame> stage S scene X state Y cur a/b tab t picks … icons … p2 held … touch …" every 10
frames), `mpseed=N` (50/50 pick).
Known inputs (port, 100% save, `rtc=2026-01-01T12:00:00`, measured in this research):
- VS menu (scene 0x11 state 2 from f2780): `2141:Start:4,2396:T128/120:6,2560:Right:4,2590:Right:4,2660:A:4`
  (Right at 2900 moves its cursor to CLIENT).
- Practice character select (scene 3, mode 0xB from f2940): `2141:Start:4,2396:T128/120:6,2560:Down:4,2590:Down:4,2660:A:4,2900:A:4`.
- Practice to stage select (scene 5 from f3640): + `3000:A:4,3100:Start:4,3200:A:4,3350:Right:4,3400:A:4,3500:Start:4,3600:A:4`
  (P1 Goku, READY? GO, ENEMY Piccolo, READY? GO); `3900:Right:4,4000:Down:4` move the stage cursor.
- Z-Battle READY? overlay: `2141:Start:4,2396:T128/120:6,2560:A:4,2700:A:6,2800:Start:4` (overlay from f2810).
- Free Battle battle (control from ~f4540): /tmp/ssw2/btnrun.sh inputs.
- Probes: `probe=020DD4C4;020DD514;020DEA2C;020DE658;020DE664 probe_every=20` (scene/state, mode, side byte, picks);
  battle: `probe=020DE3A0+1BCB4;020DE3A0+1BCA9` (input fn 0x02012DA8, local side 0).

## 6. Risks and fallbacks
- R1 Shared DP tab: the game's grid shows one tab's characters lit; two cursors on different tabs cannot both show a
  lit face. The design shares the tab (either player's Up / Down moves both, the other cursor follows its own
  neighbour). If the user wants fully independent cursors, **fallback: a port-drawn select screen** that keeps the
  scene's background and the top-screen lists but draws all 26 fighter faces (MainScrIcon.bin face textures, 2048
  bytes each + palette, from the ROM) in a 7 x 4 hex grid plus an SP page, with the two outlines drawn by Godot; picks
  still go through FUN_0206ED18 via the f_0206cc94 override (so the top screen and the party block stay the game's).
- R2 Tint: verified for the select outline (scratch run tint1). If some object ignores the vertex colour (decal mode),
  fallback: a red / blue copy of its palette in a free texture-palette slot (game palette manager FUN_02010B6C) and
  PLTT_BASE swapped for the duplicate draw. Stage icons 12 and 15 use a 1-px smaller cursor size (FUN_02071F18 writes
  object +0x10/+0x12 = 0x47/0x1F instead of 0x48/0x20 for the GAME's cursor icon): set the size per entry too.
- R3 Calling game functions from the overrides: all overrides run on the game thread inside the scene's own frame
  (same as the existing cheats); never call game code from the main thread (use `qol.on_game_thread` if needed).
- R4 Scene redirect side effects: the scene-3 exit writes mode 6 AFTER FUN_02001014(0xC) (`FUN_0200297c(6)`); the
  redirect to 0x11 must therefore not depend on the mode, and the MP session sets mode 0xB again when scene 3 starts
  (or when 0x11 → 3 is redirected). The 0x11 exit runs FUN_02002738(1) (+0x32 = 1) before FUN_02001014 → clear +0x32
  and +0x33 in the redirect (Free / VS screens read +0x32: A-skip of the VS screen is disabled while it is set).
  Check heap free and file-cache counts over several loops (setup → select → battle → select …).
- R5 Practice-mode scene 3 differences from Free (mode 5): DP ∞ comes from u32 0x020DE638; if a mode-0xB-only
  behaviour shows up (e.g. the support rules), consider mode 5 with 0x020DE638 forced to 0xFF during MP select.
- R6 Second support / 3-slot limit: the engine allows 3 entries incl. one support per team; do not offer 3 + 1.
- R7 Pause: only the pad block pauses; P2's Start is ORed in by the port (3.2). The pause menu belongs to whoever
  navigates (both ORed).
- R8 Two simultaneous pick presses in one frame: queue the second player's pick to the next frame (the loop processes
  one result per frame).
- R9 AUTO SKIP's VS-screen A (f_02018714) only acts in mode 0: unaffected. RANDOM CHARACTERS / RANDOM STAGE rewrite
  the party / stage at FUN_020140C8 — in MP randomise both teams.
