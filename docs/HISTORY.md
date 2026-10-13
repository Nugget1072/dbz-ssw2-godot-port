# HISTORY — what each part did (newest first)

Moved verbatim from HANDOFF.md in the part-32 docs cleanup. Current state, open issues and next steps: `HANDOFF.md`;
how the systems fit together now: `docs/QOL_ARCHITECTURE.md`; decoded facts per part: `decomp/DATA_NOTES.md`
(index `decomp/DATA_NOTES_INDEX.md`). Names in old entries may be superseded (e.g. `QoLMenu.WEIRD_ROWS` → `WEIRD_PAGES`,
page numbers changed in parts 19 / 24 / 26 / 27 / 32 — the current menu is in QOL_ARCHITECTURE.md).

## Per part (details in DATA_NOTES / transpiler notes)
- **Part 39** — *four cheats (2026-10-13)*: ULTRA INSTINCT (B-tap parry, 5 frames: hit stop, guard spark, SE 0x21,
  silver silhouette through a port palette; attacker stunned, blasts reflected; red flash on a missed tap; new module
  `qol_ultra.gd`), RANDOMIZER (every super done by a random fighter via the dispatcher + CHARACTER SHUFFLE's loader),
  FLIGHTLESS (gravity, the game's own landing), SMASH KNOCKBACK (push × HP lost). Corrections: +0x10 bit 0 = on the
  ground, the dispatcher reads held bits. TESTING 30, DATA_NOTES "part 39 findings".
- **Part 38** — *ENDLESS mode (2026-10-13)*: Gamemode menu slot 2 = ENDLESS (random enemies with no end on the
  All-Star machinery, `QoLAllStar.endless` / `at()`), death → ENDLESS RECORDS page (the records page with the Game Over
  screen's own title, "n KO" rows, `endless_records.cfg`); HI-SCORES RESET clears both records files; BOMB RAIN moved
  from WEIRD STUFF 3 to the cheats (page 9, counts for the leaderboard rule). ALLSTAR_DESIGN 7, TESTING 29, DATA_NOTES
  "part 38 findings (Endless)".
- **Part 37** — *first-session fixes, editor-vs-exe "divergence" (a settings leak in test runs), private GitHub
  repository* (HANDOFF part 37, TESTING 28, DATA_NOTES "part 37 findings").
- **Part 36** — *first Claude Code session (2026-10-13)*: sanity check + Windows baselines + test build (HANDOFF part
  36); then the cheat **GREEN DEMON** (new cheat page 9 CHALLENGES; weird pages now 10-12): a 1-UP (the user's art,
  edited to 16x16) chases the player's fighter and KOs it on touch, warps away and rests; local / LAN MP: hunts both
  players with 10-s target switches and a close-range lock (scripts/qol/qol_green_demon.gd, QoLGame `# ---- GREEN
  DEMON (part 36)`). BOMB RAIN's texture block moved to the shared scripts/qol/qol_texblock.gd (bombs identical).
  `tools/windows/lan_pair.ps1` = the two-instance LAN check on Windows. DATA_NOTES "part 36 findings (green demon)".
- **Part 35** — *All-Star fixes + move to Claude Code* (2 helper agents): life bars of members healed / revived on the
  bench and of every reloaded enemy were drawn with "lost" colours (the game repaints only the active member's colour
  buffer; DATA_NOTES "part 35 findings (All-Star life bars)") → `_asb_bar_paint` + `f_0201cbbc` override; records page
  rebuilt as the game's scene-10 results screen from its own art and lettering (DATA_NOTES "records redesign");
  procedural DS-style space sky (DATA_NOTES "All-Star sky"). Hand-off: `tools/test/ssw2.py`, `.claude/`,
  `docs/CLAUDE_CODE.md`, `local/baselines/`, git repository.
- **Parts 33-34** — docs compacted (part 33); NEW GAMEMODES + ALL-STAR mode (part 34, docs/ALLSTAR_DESIGN.md).
- **Part 32** — *BIG CHANGES page, LAN pause panel, PERFORMANCE MODE* (3 helper agents; DATA_NOTES part 32, docs/TOOLING.md
  "Session 1 part 32"): Deck perflog analysed (game frame 13-15 ms, 1.4-2.3 steps per picture, main thread waits a
  whole game frame per extra step); always-on exact speed-ups (battle game frame −10 to −20 %); PERFORMANCE MODE
  (pipelining forced, refresh split, no interpolation; measured fps 38.9 → 43.5 and main thread 13.2 → 6.9 ms per
  picture at Deck-like load); `perfhalf` 30-fps cadence experiment off by default. LAN: guest panel + PING in pause
  (state 9) and during aborts; pause lag not reproduced (`lanpace pingdbg` for the user's PCs). The perf agent's
  "L277 desync" was a harness mistake (lanbattle=1 without lanteams / lanbstage). Native ideas (not built): packed GX
  command log, scanline loop in C++, FS read / decompression fast path for the 250-690 ms scene-load spikes.
- **Part 31** — *LAN fixes* (2 helper agents, DATA_NOTES part 31): lower-screen layer mask left at BG1-only after
  closing the LAN pages without a session → one `_keep_mask()` rule + per-frame `_layers_guard()`; rejoin desync →
  session id + flow id on every message, `_reset_flow` at session start / end / ACCEPT / room, battle only from a
  fresh STAGE_RESULT, host-numbered battle ids, WHERE / BACK_TO_ROOM watchdog (OUT OF STEP / BATTLE STOPPED), HELLO
  refused while the host is not in its room; full disconnect matrix in /tmp/ssw2/lanrj.
- **Part 30** — *LAN multiplayer* (5 helper agents: research → core ∥ menus → select / stage / battle → QA; design +
  status docs/LAN_DESIGN.md, DATA_NOTES part 30 sections). Deterministic lockstep with input delay 2 on LAN (rollback
  infeasible: parked DS threads, no savestates; the original wireless mode is lockstep too). Battle-start sync verified
  bit-identical across different histories / RTC / local zoom; checksums detect desyncs; ENet service thread for real
  RTT; snapshot of the host's cheats / weird options never written to the guest's settings.cfg. Tested with two
  instances on one machine (also Windows exe under Wine ↔ Linux export); not yet on two real PCs / Wi-Fi / Steam Deck.
- **Part 29** — *MP Touch! light, dual assists, SAME CHARACTERS rules* (2 helper agents, DATA_NOTES part 29): the
  Team Arts partner bit (+0x274 & 0x100) is only set by FUN_02026548, which the loader calls for side 0 only → MP calls
  it per active fighter every frame (`# ---- MP TEAM ARTS LIGHT`); one assist slot (teams+0x11E0) → per-side slots in MP
  (`# ---- MP DUAL ASSISTS`: real support records, the second run with the slot pointed at it; f_0202B580 / f_0202759C /
  f_0202B4A0 overrides; ASSIST SPAM pool 16 copies, 8 per side). SP SAME CHARACTERS: `_hide_fighters()` keeps supports
  visible to the game's own one-support / START checks (fighter first, one support). Open: Shenron freeze ops only
  freeze the global-slot assist.
- **Part 28** — *Local multiplayer fixes* (2 helper agents, DATA_NOTES part 28 "MP select / panel" and "MP cheats /
  weird QA"): select D.P bytes per side (u8 0x020DE7C8 / 0x020DE7E4 / 0x020DE800 reloaded in `_ms_side`, `_mp_grey`
  per player); MP support rules (fighters first, at most one support without SAME CHARACTERS) and split support box
  with per-half calls (`# ---- MP SUPPORTS (part 28)`: FUN_02026C00 needs the touch inside every support rect, so
  two supports were never callable — also in single player with SAME CHARACTERS, still open there); new Touch! plate
  from the game's Team Arts button art (lit / dim / pressed); shuffle HUD icon scratch buffer per side; STAGE SHUFFLE
  register write deferred to the battle VBlank (`_stage_regs_defer` / `_stage_regs_apply`).
- **Part 27** — *Local multiplayer* (5 helper agents: research → battle core + panel ∥ input + menu → select / stage
  / loop → QA; design + facts in docs/MULTIPLAYER_DESIGN.md and DATA_NOTES part 27 sections). Built on the game's own
  screens: VS menu (scene 0x11, HOST/CLIENT relabelled), Practice select (scene 3 mode 0xB) with a second tinted
  outline drawn by re-running the menu object drawer, stage select (scene 5) with 50/50 roulette, Free Battle (mode
  5) with the CPU AI input function f_0202DCE0 returning P2's pad / touch; lower screen = port panel (both teams,
  mockup docs/mp_mockup.png (local only, not in git: cut from the game's art)); WIN/LOSE banner from the winner's side in MP. Cheats apply to both sides in MP.
  Limits: LAN not implemented; shared DP tab in the select; game result screens skipped between rounds; two real
  gamepads untested.
- **Part 26** — *Reorganized settings, effect pairing fix, Proton performance* (2 helper agents; DATA_NOTES part 26,
  docs/TOOLING.md "Session 1 part 26: Proton / Wine performance"): the smooth-motion renderer pairs polygon i with
  the previous frame's polygon i (attr / texparam / PLTT_BASE / texcoords equal) — identical-looking untextured
  effect quads got each other's motion (bomb split / grey boxes, damage-number blocks, blood streaks); bombs are now
  one direct-colour textured quad each (texture VRAM 0x5F000, block reserved in the game's texture manager
  0x020DE380 with key 0x7B0B0B26, re-checked every fight frame), other effects use per-quad PLTT_BASE keys. Proton:
  measured under GE-Proton10-34's Wine here — Wine itself costs only 5-15 %; frames were serial (game step + render
  + present on the main thread), now pipelined when frames come late (`pipeline=auto`); unknown refresh rate → no
  extra 60 limiter; `perflog` / DBZ_PERFLOG=1 writes perflog.txt. Deck-only unknowns: real step time, radeonsi /
  gamescope present cost.
- **Part 25** — *Bomb rain, input display, CRT TV* (2 helper agents, DATA_NOTES part 25): BOMB RAIN in
  scripts/qol/qol_bombs.gd (own RNG reseeded per battle in f_0202A40C, tick from f_0202954C in battle state 7 only,
  frozen in pause/events/cut-ins/supers/throws; direct hit = 25% max HP through f_020293A4 (scale [globals+0x1676]),
  knock-back FUN_020213A8 + reaction FUN_02021B4C like FUN_0201E9EC, guard 1/4; floor blast 12%→3% within 40 px;
  explosion = game effect FUN_0202247C(owner, 1) + FUN_0202216C size 1, SE 0x1E via FUN_02029E3C; drawn as GX quads
  appended to gx_cmds; hurt boxes via FUN_0201DF20 into port-only RAM 0x027C0000). INPUT DISPLAY (QoLInputDisplay,
  pad word 0x020DD4E0, LEFT/RIGHT swapped back under mirror). CRT TV (QoLCrt + ds_fx_crt.gdshader in the presenter,
  scanline per DS row from 2X; CanvasLayer 65 in captures; the open settings menu stays sharp). JELLY FIGHTERS code
  removed. Cursor speed default 5 (old cfg files without `cursor_speed_v` migrate once).
- **Part 24** — *Gamepad cursor, auto skip, weird 3, QA* (4 helper agents, DATA_NOTES part 24): QoLCursor (scripts/
  qol/qol_cursor.gd) on the lower screen while a gamepad is connected; actions qol_cur_up/down/left/right/click in
  QoLControls (defaults right stick a:3/a:2 and R3 b:8, keys empty; cursor_enabled / cursor_speed in [controls]);
  GameDS `_tick` uses `qol.cursor_touch()` when the mouse is not touching (same filter_input → set_touch path).
  AUTO SKIP (`# ---- AUTO SKIP`): story scripts (story state 0x15 / 0x1D at 0x020DE4EC) skipped by reporting the
  game's own SKIP touch button (f_0203E214 → FUN_02037A7C, script context +0x84D = 0xFF); Z-Battle VS screen
  (FUN_02018714, sub-states 1/2 at 0x020DD4C6, mode 0x020DD514 == 0) gets A like the original accepts; progress RAM
  and .sav identical to watching. WEIRD 3 (`# ---- WEIRD 3`): f_020A71C8 (rotation helper called once per sprite)
  locates the current sprite; damage numbers merged within 10 frames and stacked, rainbow tint for blast/beam
  handlers, jelly springs per fighter. QA: page counter / arrows, tile text, narrow font for long pad names, confirm
  sound, MIRROR off in pause (state 9). Card-DMA freeze analysed: same on hardware, workaround kept.
- **Part 23** — *Epic pictures, scaled blood, flashy ki, shake, confetti, leaderboard* (4 helper agents, DATA_NOTES
  part 23): EPIC MODE pictures — QoLGame overrides the resource-pack loader FUN_02009B28; QoLEpicImg reads the text out
  of each loaded Data File / help / touch-item / credits picture by matching glyphs cut from the ROM at run time
  (QoLEpicRefs coordinates), rewrites it (QoLEpic) and redraws it with the same glyphs/colours (BG pictures re-encoded,
  grown credits pictures get a new heap block). BLOOD: 2 + damage/100 drops, damage capped at 3000 → max 30, pool 160.
  FLASHY KI / KO CONFETTI drawn in the part-22 `_fx_draw` path (`flashydbg`); SCREEN SHAKE: f_020293A4 records
  `shake_dmg`, DSDisplay's FX_SHAKE shader variant moves engine A's battle picture (max 6 px). Leaderboard: the only
  one is the Z-Battle HI-SCORE RANKING (0x020DD5C4, 5 x 0x14, insert FUN_02002560, defaults 0x020B6888);
  f_02002560 returns 0 while `cheats_on() > 0`; `reset_leaderboards()` copies the defaults and saves with the game's
  own open/write/close (`lbdbg`, `lbreset=F`). Menu: SETTINGS 2 row HI-SCORES [RESET] → page `lbconfirm` (window-size
  confirm style, YES/NO, NO first, B = NO) → `qol.on_game_thread(core.reset_leaderboards)`; WEIRD STUFF 1 + SCREEN
  SHAKE (5 rows), WEIRD STUFF 2 + FLASHY KI, KO CONFETTI (6 rows). The user removed DragonBallTile*.png from finished/.
- **Part 22** — *Button art, more weird options, QA* (4 helper agents, DATA_NOTES part 22): the user's 80x44
  `assets_qol/port_button.png` replaces the centre tile: Mode Select's bottom screen is engine A with the tiles as
  3D quads; tile k = 16-colour texture at slot 0 + k*0x1000; QoLButton (scripts/qol/qol_button.gd) rewrites offset
  0x4000 with the PNG mapped (CIELAB, 15/16 brightness) to palette 0 while scene 0x020738E0 runs (`btndbg`,
  `nobutton`). Battle signal for picture effects: VBlank handler (DTCM 0x027E0004) == FUN_02013030 and state
  0x020DD4C5 >= 4 (`DSDisplay.battle_on_screen()`): fuzzy now in every mode. GAME BOY (top CanvasLayer pass,
  ds_fx_gameboy.gdshader, edge rule for readability), MIRROR MODE (top screen flipped in battle; GameDS swaps
  LEFT/RIGHT while `display.mirror_active()`), BLOOD + AFTERIMAGES (QoLGame `# ---- BLOOD / AFTERIMAGES`: droplet
  pool of 64 simulated per battle frame, drawn as GX quads after the sprite list; afterimages = 3 tinted copies of
  the current sprite quad at older positions; `blooddbg`). Bevel now fades with MASTER_BRIGHT / BLDY (applied after
  the bevel pass). QA (helper agent): tile-4 A-press → scene 2 (boot) fixed by blocking all keys pressed with the
  move / open; DSMachine.step watchdog counts only time the game could run (sleep / SIGSTOP); settings.cfg values
  converted by type (`_val`). Seen, not fixed: a huge Z-Battle course score with many cheats (game formula).
- **Part 21** — *Weird settings, zoom culling* (4 helper agents, DATA_NOTES part 21 ×5): page 7 WEIRD STUFF
  (`QoLMenu.WEIRD_ROWS`, QoLSettings bevel_emboss / touch_fuzzy / epic_mode / second_fiddle, [weird] in
  settings.cfg, test flag `weird=bevel,fuzzy,epic,fiddle`). BEVEL EMBOSS / TOUCH FUZZY: renderer only (ds_engine2d /
  ds_poly `FX_*` shader variants, ds_fx_bevel.gdshader post-pass; DSDisplay reads the settings from core.cheats each
  refresh; bevel: per-shape inner bevel from a layer code + 3D object-id render; fuzzy: battle-only (scene byte
  0x020DD4C4 == 0, state 0x020DD4C5 4-9), BG2/BG3 per-scanline waves + zoom pulse, stage polygons (perspective, w
  != 1) wave, sprites (ortho) untouched, pastel hue tint; global uniform `ds_fx`; `fxdump`, `fxdbg`). EPIC MODE:
  QoLEpic (scripts/qol/qol_epic.gd) seeded rule-based rewriter; story/tutorial strings via the only text drawer
  FUN_0200B954 (128-glyph limit → ≤126 bytes, re-wrapped to the box), Mode Select / Option descriptions (images)
  redrawn with own text after FUN_02075CC4 / FUN_020864E0; `epicdbg`. 2ND FIDDLE: mirror palette rule (loader
  FUN_0202A094: P2 record, id < 0x1A, same id in P1's team → +0xFC += 0x100) inverted after the loader + shuffle.
  Zoom culling: stage script op 0x11 (camera-x window, FUN_0201A794), repeating props and panorama pairs
  (FUN_02019C74) widened / completed while drawing at levels 0-1; `zoomcull=0`. The user deleted baseroms/ and
  100Save/: tools fall back to finished/*.nds and data/save100.sav. Dragon Ball tile PNG for the user extracted from
  a BG0 layer capture (not in the repo).
- **Part 20** — *Zoom, dash lines, speed*: CAMERA ZOOM (helper agent, DATA_NOTES part 20 camera zoom): levels
  0.7/0.85/1/1.15/1.3; the scaled camera zoom (+6 of 0x021003CC) is written only while drawing (f_02019328,
  f_02012d70, f_02012154) so game logic is identical at every level; the stage's perspective (f_020a7710) scaled the
  same way; zoom-in never past both fighters 40 px inside the screen; BG2/BG3 panorama not scaled; `zoom=N`,
  `zoomcycle`, `zoomk=`, `zoomdbg`. Dash lines (helper agent, DATA_NOTES part 20 graphics): the NO COOLDOWN
  f_0202104c override turned every P1 effect with life flag 8 (dies with the owner's action: step-dash / R-dash
  lines, charge auras) into a 60-frame countdown on any action change → override removed; `_nc_keep` converts only
  the cut attack's objects. Regression scan current vs part 17 vs noqol: identical with cheats off. Speed: game
  step CPU measured with `turbo` + `--fixed-fps 60` headless (5600 frames: current 57-58 s, part 17 61-63 s, noqol
  61.6 s) — no regression; per-picture work trimmed: `interp` is now a GLOBAL shader uniform (`ds_interp_2d` /
  `ds_interp_3d`, project.godot [shader_globals]) set once per picture when it changes, instead of
  set_shader_parameter on every 3D material and both screens; DSPresenter no longer draws a full-window black rect
  (clear colour) and uses plain nearest scaling without the shader at whole multiples (identical output). Checks:
  intro 221/221, capinterp dash frames 22/22 identical, 2x window = exact 2x2 blocks, fit 2.344 unchanged.
- **Part 19** — *Sounds, chaos fixes, silhouette shadows, cheat pages*: menu sounds = the game's SE function
  f_0200FF9C(0, id) on the game thread (Mode Select FUN_02073AAC: 5 cursor, 0 decide, 4 back), `QoLController.se`;
  `qoldbg` prints the SFX channels that start. CHAOS SHUFFLE fixes (helper agent, DATA_NOTES part 19 chaos): throws
  (table 0x020D76BC: thrower 0x85, victim 0x34-0x50), grab supers (FUN_02028DDC + table 0x020D7724: victim
  0x53-0x66; Kid Buu ball 0x55), +0x250 & 0x420 held flags, hidden rec+0x161 == 0, super / summon objects tracked at
  spawn → `_chaos_held` waits (summon objects capped 600 frames); debug `chaosat=`, `p2keys=`. DETAILED SHADOWS
  (helper agent, DATA_NOTES part 19 shadows): battle sprites are 3D quads in the sprite list [0x020DE384] drawn by
  FUN_02011384; the per-team ellipse (team +0x888, FUN_0202A254) is replaced while drawing by a black, squashed,
  mirrored copy of the fighter's own quad (same texture = same frame); supports / spam copies too; `shadows=1`,
  `shadowdbg`, `shadowk=`, `shadowc=`, `shadowflip=0`. RANDOM STAGE: f_020140C8 writes a random id 0-14 to
  0x020DD54A (not restored; the stage select / mode sets it again). Cheat pages: `QoLMenu.CHEAT_PAGES`.
- **Part 18** — *Boss dash bug, five new cheats* (RE by three helper agents; DATA_NOTES part 18 ×3): the boss
  dash flying backwards = int32 overflow in FUN_0202C1D4 (no-direction dash speed = s16 blk+0xC × u16 blk+2 × 256
  >> 16; level-3 blocks 0x1E00 × 0x500 → negative; proven in melonDS) → `f_0202c1d4` override recomputes with the
  normal block's scale for cheat bosses only. CHAOS SHUFFLE (60-frame period, waits only for supers / KO / tag /
  pause / camera modes, kills the old character's effect objects, restarts generic actions once; panel cache).
  STAGE SHUFFLE (unload textures / palette slots / model, game's FUN_0201C150 for the new stage, fighter bounds +
  move, music untouched; stgseed/stglist). TRIPLE KI BLASTS (two copies through FUN_020225C8 at the shot's first
  handler call, facing ±9/256). ATTACK SPAM (attacks end with FUN_0202B630 on a new press; P1 melee knock-back
  scaled to 64/256 so repeats connect; supers / throws / team arts untouched). HARD MODE (f_020293a4: damage to
  P1 ×2, to enemies ÷2 — HP is s16, so "double health" is half damage). Port freeze found by the chaos agent:
  VBlank IRQ during a card read with card DMA3 armed → the VBlank upload queues busy-wait forever; worked around by
  skipping FUN_0201098C / FUN_02006518 during character and stage swaps (queues stay < 32; root cause in the
  runtime's card/IRQ timing is still open — see Known issues).
- **Part 17** — *Cleanup + bug hunt*: removed from the user's folder: `Claude outputs/` (old preview PNGs),
  `GodotGame/new-game-project/assets/` (186 MB of converted ROM assets used only by the legacy hand-built scenes;
  `decomp/tools/build_all.py` recreates them) and `native/build-linux|build-windows` (CMake object trees;
  `native/build.sh` recreates them; the cloud sync now excludes them). Bugs (docs/BUGFIXES.txt → finished/):
  (1) smooth motion opened a strip of void at the screen edge during fast camera moves — ds_poly.gdshader keeps
  vertices on the screen edge from moving inward in in-between frames (edge stray pixels 3836 → 485 in a dash
  capture, 60 fps unchanged); (2) BOSS CHARACTERS + CHARACTER SHUFFLE left the skull on a non-boss —
  `QoLGame._shuffle_boss` makes the new character a boss when it has a boss version, else drops it. Checked and
  NOT bugs: the solid black fighter shadows (melonDS shows the same). Combination battles without errors: all
  cheats but one-hit KO / random (2 shuffles incl. a tagged member, assist spam, boss), random + same + shuffle +
  assist spam + one-hit KO.
- **Part 16** — *Controls, settings page 2, character shuffle, icon, black borders*: `QoLControls` (scripts/qol/
  qol_controls.gd) owns the DS-button input map (defaults read from project.godot at startup, one key + one pad
  input per button, swap on conflict, [controls] in settings.cfg, applied with InputMap). The CONTROLS sub-pages
  (controls1/2, 22-px rows) wait for a raw event: `GameDS._input` → `QoLController.raw_input` → `QoLMenu.finish_wait`;
  menu input is ignored until the mapped key is released. Button meanings checked in battle (DATA_NOTES 16).
  VOLUME = master bus; AUTO PAUSE = GameDS skips stepping while the app is unfocused. CHARACTER SHUFFLE (helper
  agent): QoLGame `_shuffle_*` rebuilds P1's active record like the loader FUN_0202A094 when the fighter is calm
  (frees the old file-cache entries / archives, palettes into the record's own slots, face icon, lower-screen panels
  via FUN_0201B78C, voices like a tag). DSPresenter's margins were white in full screen (drawn through the picture
  shader) → picture in a child node, black clear colour, black boot splash without the Godot image. Window icon =
  ROM banner icon (QoLController.banner_icon); the exe / project icon is an original "SW2" hexagon (port_icon.png).
  `inputs=` takes raw keys `K<name>`; `qoltest2.sh` updated for the new page order; `qoltest3.sh` new.
- **Part 15** — *Assist spam, random music, titles, sharp scaling*: the orange-bar titles were made by
  thickening the thin text font (broken W/N/M/K) and full screen scaled by a fraction with nearest sampling (uneven
  pixel columns); now a hand-drawn HEAVY font (QoLFont.HEAVY_GLYPHS, game-title style) and DSPresenter (SubViewport
  + sharp-bilinear shader; windows stay whole multiples). ASSIST SPAM: QoLGame overrides FUN_02026C00 (slot not
  blocking for P1), FUN_020277AC (busy slot → copy of the support record at 0x02700000 + 0x2E0·i, max 8, game's own
  arrival steps) and FUN_020294B8 (copies updated once per frame with the slot pointing at them; the game's end code
  frees them). RANDOM MUSIC: f_0200FE48/f_0200FE98 remap stream→stream (1..19) and sequence→sequence no bigger
  than the original + 32 KiB (QoLSound.seq_size from the SDAT), new seed each time it is switched on; jukebox sets
  music_bypass. BOSS CHARACTERS row: LIST button → names on the upper screen. RE by a helper agent (DATA_NOTES 15).
- **Part 14** — *Bosses, random teams, full-screen fit*: a boss = normal id + boss level (0x020DD510 for CPU
  teams); `QoLGame` notes a pick made with L held (f_0206CC94), `QoLController._boss_frame` ties it to the select
  slot (Free Battle 0x020DE658[6], Z-Battle/Maximum 0x020DE64C[3]) and to the team the loader will read; after
  f_0202A40C the boss gets the level's parameter block + HP, and its own 'c' chunk copy has the boss branches (op
  0x92, level L) turned into gotos (op 0x05; bytecode walker = charscript.py). Skulls (`QoLMarkers`) on the select
  upper screen and on the battle panel (rec+0x2D0). RANDOM CHARACTERS rewrites the party at f_020140C8 (VS screen,
  panels and loader all see it) and restores it after f_02013D60. INFINITE ASSISTS rewrites team +0x8CA each P1
  update. Full screen: `content_scale_stretch` fractional (fit, aspect kept); windows integer. `BOSS_CHARACTERS.txt`
  (docs/ → finished/) lists the 18 bosses. RE by a helper agent (DATA_NOTES part 14).
- **Part 13** — *Cheats page*: header row on settings pages = ◀ page ▶ + EXIT (L/R flip too). Cheats via
  `QoLGame extends DSGame` overriding translated functions (no generated code edited; off = `super` only):
  FUN_020293A4 damage (infinite health → 0 damage for P1; one-hit KO → enemy HP 0 unless guarding), FUN_02027950
  ki spend + FUN_0202954C pre-hook (P1 team ki 0xC800; NO COOLDOWN: an A/Y press during an attack action returns
  the fighter to neutral via FUN_02021B4C so the dispatcher starts the new attack the same frame — melee combos
  and a ki blast before its first shot excepted), FUN_0202104C (P1 beams whose action was cut short get a 60-frame
  countdown instead of dying), FUN_020209E0 ki-blast handler (turn 3/256 per frame toward FUN_0201EE60's
  direction, velocity vectors rotated with the game's sine table), FUN_0206CC94 / FUN_0206ABB0 (character select
  sees an empty team → duplicates, also same-family and several supports). RE by two helper agents (melonDS RAM
  experiments) + port runs; DATA_NOTES part 13 (incl. the team-block correction).
- **Part 12** — *Menu restyle*: the menu now copies the game's OPTION MODE screen (captured in melonDS): title plate,
  black rows with orange trim, bold italic labels, hexagon buttons (value red, cursor white). Text uses the game's
  own font `romdata/scene/font_eu.bin`, read from the ROM at startup by `QoLFont` (NitroFS lookup + RLE; bold /
  italic / tall / heavy variants generated). Behind the menu only the game's BG1 (the scrolling hexagons) is shown
  (`layer_keep` uniform in ds_engine2d.gdshader). Cursor model: every button on every page (EXIT, jukebox
  PREVIOUS/PLAY/NEXT/BACK, KEEP/UNDO) by D-pad + A, or by tap. Top screen: title inside the orange bar (between its
  black lines, heavy black like the game's titles) and a description of the row under the cursor. New: window 1X
  and FULL (confirm/revert like the others; F11 updates the setting), FPS COUNTER row + F3 anywhere
  (`QoLFpsCounter`). Layout preview tool `tools/qol_preview.tscn`.
- **Part 11** — *QoL settings menu* (`scripts/qol/`, CLAUDE.md "QoL layer"). The game's code is untouched: the
  port reads Mode Select's scene/cursor/state bytes (DATA_NOTES part 11), moves the cursor onto the centre tile
  when the player pushes toward it (from tiles 1/3/5/7) or taps it, and opens a Godot-drawn menu on the bottom
  screen (game colours, hexagon background, 5x7 pixel font; every control works with keys and touch/mouse).
  Window size changes must be kept within 10 s (counted in game frames) or revert. Frame rate: `Engine.max_fps`
  / V-Sync; above 60 the display draws in-between frames (2D scroll + sprite positions and 3D vertices moved back
  by `1 - interp` of their motion since the previous game frame, whole DS pixels, jumps > 32 px not blended;
  3D motion per vertex from polygon matching in DSGX/DSGXNative, parity checked). Music/SFX switches mute
  hardware channels by owner (BGM player tracks + stream channels vs the rest). Jukebox: 20 streams + 18 MIDI
  sequences from the SDAT, played through the game's own BGM manager on the game thread; leaving it restores the
  menu music and the sound heap. Settings in `settings.cfg` next to the exe.
- **Part 10** — *Game too fast on other PCs*: the frame-pacing accumulator was clamped at zero after rounding let
  it go negative, so every refresh that came early created time. With V-Sync off (driver setting) or high-refresh
  / VRR displays the game ran up to ~1.7× too fast (simulation: 100 game frames/s at 1,000 fps; 61.7 at 165 Hz,
  67.8 at 240 Hz). Now a proper fixed-timestep accumulator (time only consumed, debt kept, 8.5-period stall cap,
  max 8 catch-up steps); one-frame-per-refresh only when frames really arrive at a ~60 Hz display's rate
  (smoothed frame time within 3 %); `Engine.max_fps = 240` so an uncapped GPU doesn't spin. Debug knobs
  `pacelog`, `fakehz`, `maxfps`, `vsync=0`; `tools/windows/pace_test.bat`.
- **Part 9** — *Loose pixels on the scrolling bars* (only on real GPUs): each dilated triangle was drawn as one
  fan over its outline, which made long slivers; GPUs rebuild attribute planes from sub-pixel-snapped corners,
  so along a quad's diagonal some pixels sampled the texel row above. Now each triangle is drawn as itself
  (corners on the pixel grid) plus a dilation ring (bands on outer edges, corner wedges), dilation 118/256 px
  (on the GPU's sub-pixel grid). Reproduced and verified on the user's RTX 4070 with `capture_test.bat`: 240 →
  0 differing pixels vs the reference, bar borders exact; intro match 161 → 163 identical frames; Korin
  26.7 k → 26.4 k; no perf change. *No game data in the exe*: the built-in ROM is gone; the exe scans its
  folder (any name/extension), validates title/code ADBP, header CRC16 0x53C2 and ARM9/ARM7 MD5, and shows an
  on-screen message if nothing fits. Folder tidied for hand-over: `tools/linux/` harness, `docs/TESTING.md`,
  `docs/TOOLING.md`, rewritten `CLAUDE.md`, savestates in `reference/states/`, cloud paths removed from tools.
- **Part 8** — bars shook: quads were clipped as two triangles (the DS clips the quad as one polygon) → whole-
  quad clipping (`_quad4`). Portable folder; `finished/README.txt`; F11 fullscreen.
- **Part 7** — Maximum rank bars black (shader palette mask dropped bit 15); Story "Map Clear 3/14" (12 functions
  with literal-sized stack frames overwrote callers' frames: translator fix, stack 15 KiB); Y → C; save next to
  the exe; inner quad edges not dilated; translucent equal-depth test.
- **Part 6** — stage holes (homogeneous culling), seams (UV clamp + DS coverage dilation), hit-stop flicker
  (polygons accumulate until SWAP_BUFFERS), Practice/Story/Data menus (veneers, callbacks), Maximum hang
  (MI_StopDma address, card IRQ inside DMA, DMA restart), 100% save, keys, native GDExtension, pacing, audio
  resampling, quick taps.
- **Part 5** — geometry engine 3.5× faster and threaded; profiling builds; 14 callback functions added.
- **Parts 1–4** — extraction, converters, Ghidra pipeline, translator, runtime, lockstep, renderer, ARM7 sound
  driver translation, BIOS HLE fixes, 64-bit IO stores, LZ77 negative offsets, EEPROM wrap.

## Feature timeline (the old HANDOFF "current state" paragraph, parts 11-27)
Part 11 added the port's first quality-of-life features: the unused Dragon Ball tile on Mode Select opens a
settings menu on the bottom screen (window size 2x/4x/8x with confirm-or-revert, frame rate 60/120/240/uncapped
with smooth in-between frames at unchanged game speed, music on/off, sound effects on/off, a 38-track jukebox).
Part 12 restyled it after the game's OPTION MODE screen (game font from the ROM, hexagon buttons, the real
scrolling Mode Select background), made every button reachable by keys and touch, and added 1X / FULL window
sizes and an FPS counter (menu or F3). Part 13 added menu pages (arrows / L / R) and a CHEATS page: no cooldown,
infinite health, one-hit KO, infinite ki, ki homing, same characters (all off by default). Part 14: page 3 (boss
characters picked with L + skull markers, random team every battle, infinite assists), full screen fits the screen.
Part 15: assist spam (many supports at once), random music, boss list, hand-drawn title font, sharp full-screen
scaling (DSPresenter). Part 16: menu pages are now SETTINGS 1, SETTINGS 2 (CONTROLS remapping with KEY/PAD boxes and
DEFAULT, VOLUME, AUTO PAUSE), CHEATS 1, CHEATS 2 (+ CHARACTER SHUFFLE: a random roster fighter every 10 s, HP kept);
black full-screen borders; the window icon is read from the ROM's banner at startup. Part 17: cleanup of the user's
folder, smooth-motion edge gap fixed, boss skull + shuffle fixed (finished/BUGFIXES.txt). Part 18: boss dash
overflow fixed; CHEATS 3 page: chaos shuffle, stage shuffle, triple ki blasts, attack spam, hard mode. Part 19:
menu sounds, chaos shuffle grab/throw/summon fixes, DETAILED SHADOWS, RANDOM STAGE, cheat pages sorted by theme
(pages 3-6: FIGHTING, KI & ASSISTS, CHARACTERS, STAGE & MUSIC). Part 20: CAMERA ZOOM (SETTINGS 2), NO COOLDOWN
dash-line bug fixed, per-picture rendering work trimmed. Part 21: WEIRD STUFF page (bevel emboss, touch fuzzy, epic
mode, 2nd fiddle), zoom stage-object culling fixed; baseroms/ and 100Save/ removed by the user (ROM in finished/).
Part 22: WEIRD STUFF 2 page (blood, afterimages; game boy, mirror on page 1), the user's PORT button on Mode Select,
fuzzy in every battle, QA fixes (logo restart on tile-4 select, watchdog after sleep, cfg typing).
Part 23: EPIC MODE also rewrites the Data File and staff-credit pictures, BLOOD scales with damage (capped), new weird
options FLASHY KI / SCREEN SHAKE / KO CONFETTI, cheats keep Z-Battle scores out of the HI-SCORE RANKING, SETTINGS 2
HI-SCORES RESET with an "ARE YOU SURE?" page.
Part 24: gamepad mouse cursor (CONTROLS page 3), AUTO SKIP (SETTINGS 3), WEIRD STUFF 3 (damage numbers, rainbow ki,
jelly fighters), QA fixes (mirror off while paused, confirm sound, long pad names, tile cheat text, page counter).
Part 25: cursor speed default 5, JELLY FIGHTERS removed, WEIRD STUFF 3 + BOMB RAIN, INPUT DISPLAY, CRT TV.
Part 26: settings moved (DAMAGE NUMBERS / INPUT DISPLAY → SETTINGS 3, CRT TV → WEIRD 1), bomb sprite textured +
smooth-motion pairing keys for all effects, frame pipelining for slow CPUs / Proton, perflog.
Part 27: LOCAL MULTIPLAYER (settings page 4; VS BATTLE → LOCAL / LAN; controller setup, two-cursor select,
stage roulette, P2-controlled Free Battle with a two-team touch panel, loop back to the select). LAN = notice only.

## Verification evidence of parts 11-16 and smooth motion (old HANDOFF "Verified" rows)
| Area | Proof |
|---|---|
| QoL menu (parts 11-12) | `tools/linux/qoltest.sh`: keys + touch through every page, confirm/undo/keep/timeout, FPS counter, settings file; jukebox streams + MIDI; music/SFX masks; F3 in scripted input; window 1X/4X/full on the Linux export (Xvfb); intro 163/221 + bars 0 px unchanged |
| Cheats (part 13) | `qoltest2.sh` (pages, all cheats on by keys + taps, cfg); headless `cheatdbg` battles: HP/ki stay full, one hit → KO, 6 vs 1 live ki blasts, homing 9760 vs 10408 HP left; three Gokus picked and loaded; off = baselines unchanged |
| Bosses / random (part 14) | Broly picked with L: level 3, 26000 HP vs P2 Broly 18500, 8/8 boss branches patched, boss ki blast barrage ("6 RUSH"), skulls on select + battle panel; Z-Battle with RANDOM: Gotenks → Piccolo → SSJ Vegeta in consecutive fights, party restored; fit scaling 600x900 in a 1600x900 window (fractional) |
| Part 15 | titles re-rendered (preview), sharp fit 600x900 in 1600x900 with even letters; assist spam: 7 copies, P2 KO'd (vs 10600 HP left); random music: every BGM id remapped (seq 1→2, STRM 19→4, 18→19, 9→11), new seq audible |
| Part 16 | `qoltest3.sh`: CONTROLS by keys, taps, raw keys (Space for Y, Esc cancel, tap cancel), cfg saved; battle with the cfg: Space = melee, C nothing, Z guard; shuffle (helper agent): 4+ swaps per run, HP identical across swaps, sprite / face icon / portrait of the new fighter (icon + portrait 0 px vs melonDS loading that fighter), off = byte-identical; presentfit 1200x900: margins (0,0,0); banner icon = Goku face |
| Smooth motion | captures with `capinterp=0/0.5`: in-between frames lie between game frames; `capinterp=1` and static scenes identical to normal frames |
