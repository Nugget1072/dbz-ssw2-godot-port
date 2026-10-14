# QoL layer — architecture by system (where each feature lives)

The port's own additions. **Rule: the game's code is never changed for them** — the generated `DSGame`
(`scripts/gen/ds_game.gd`) is untouched; `QoLGame` (`scripts/qol/qol_game.gd`) extends it and overrides translated
functions `f_XXXXXXXX`. GDScript methods are virtual and `_fn` holds method references, so direct and indirect calls
both reach the overrides. **With a feature off every override just calls `super`** (off-identity is tested: intro
221/221, btn battle captures + `CHT` lines; docs/TESTING.md). `noqol` uses plain `DSGame`; the lockstep tool always does.
Overrides run on the game thread inside the scene's own frame; the main thread calls game code only via
`QoLController.on_game_thread(c)` (→ `DSMachine.inject`, run inside `_vblank_wait`).
RAM addresses / decoded facts: `decomp/DATA_NOTES.md` (index: `decomp/DATA_NOTES_INDEX.md`). History per part:
`docs/HISTORY.md`. Sections in qol_game.gd are marked `# ---- <NAME> (part N)` — grep for them.

## Core wiring
- `QoLController` (`qol_controller.gd`, created by `GameDS`): reads Mode Select's state from RAM (DATA_NOTES part 11),
  rewrites the input the game sees (`filter_input`: moves the cursor onto the centre tile, opens `QoLMenu`, hides input
  while the menu is open), `after_step()` per game frame, sets `DSSound.mute_mask` per hardware channel (music channels
  from `QoLSound.music_mask()`, which reads the ARM7 driver's players / tracks), `apply_*` setters, `se(id)` = the game's
  SE function f_0200FF9C(0, id) on the game thread (Mode Select sounds: 5 cursor, 0 decide, 4 back),
  `banner_icon` (window icon from the ROM banner at startup; the exe / project icon is an original "SW2" hexagon,
  `port_icon.png`). Raw events reach the menu through `GameDS._input` → `QoLController.raw_input`.
- `QoLSettings` (`qol_settings.gd`): every option; `settings.cfg` next to the exe (editor: user://; captures ignore it
  unless `qolcfg=`). Sections [display] [sound] [game] [mp] [lan] [weird] [cheats] [controls]; values converted by type
  (`_val`). Names: `QoLSettings.CHEATS`, `QoLSettings.WEIRD`. DAMAGE NUMBERS / INPUT DISPLAY are settings (page 3) but
  still saved in [weird].
- `GameDS` (`scripts/game/game_ds.gd`): main scene — pacing, input, save, debug flags (docs/DEBUG_FLAGS.md); feeds
  `qol.cursor_touch()` into the touch path when the mouse is not touching.

## Settings menu (Mode Select centre tile)
- `QoLMenu` (`qol_menu.gd`) draws on the bottom screen in the style of the game's OPTION MODE screen (part 12) over the
  game's own Mode Select BG1 (`DSDisplay.set_layer_keep` / `layer_keep` uniform in ds_engine2d.gdshader hides the other
  layers while the menu is open). Header row = ◀ page ▶ + EXIT (L / R flip pages); every button by D-pad + A or tap.
- Pages (`QoLMenu.PAGES`, 13 since part 41): 1 SETTINGS (`main`: WINDOW SIZE 1X/2X/4X/8X/FULL with 10-s KEEP/UNDO `confirm` page, FRAME
  RATE 60/120/240/MAX, FPS COUNTER, MUSIC, SOUND FX, JUKEBOX) · 2 SETTINGS 2 (`main2`: CONTROLS, VOLUME, AUTO PAUSE,
  DETAILED SHADOWS, ZOOM, HI-SCORES RESET → `lbconfirm` page) · 3 SETTINGS 3 (`main3`: AUTO SKIP, DAMAGE NUMBERS, INPUT
  DISPLAY) · 4 BIG CHANGES (`mpset`: MULTIPLAYER, PERFORMANCE) · 5-10 cheats (`QoLMenu.CHEAT_PAGES`: FIGHTING (part 39: +
  ULTRA INSTINCT, moved to POWERS in part 41), KI & ASSISTS (part 40: + RICOCHET KI), CHARACTERS (part 39: + RANDOMIZER), STAGE & MUSIC, 9 POWERS
  (part 41: ULTRA INSTINCT, VAMPIRE, TIME SKIP; part 42: + Z-VANISH, BODY CHANGE; page 10 in part 41), 10 CHALLENGES
  (part 36: GREEN DEMON; part 38: + BOMB RAIN; part 39: + FLIGHTLESS, SMASH KNOCKBACK; part 40: + HOT POTATO; part 41: +
  DRAGON BALL HUNT; page 9 until part 41); part 42: FIGHTING + NONDIRECTIONAL. `PAGES` lists "cheats6" (POWERS) before
  "cheats5" (CHALLENGES)) · 11-13 WEIRD STUFF
  (`QoLMenu.WEIRD_PAGES`: 11 bevel / fuzzy / game boy / mirror / shake / crt, 12 blood / afterimages / 2nd fiddle / epic /
  flashy / confetti, 13 rainbow). HI-SCORES RESET (`lbyes`) also calls `QoLAllStarRecords.reset_files()` (part 38). The header's help text (`QoLMenu` page-row description) lists the page numbers. Sub-pages:
  `controls1`-`controls3` (`QoLMenu.CPAGES`), `jukebox`, `confirm`, `lbconfirm`.
- Text: the game's font `romdata/scene/font_eu.bin` read from the ROM at startup (`QoLFont`; styles REGULAR / BOLD /
  LABEL / BIG / HEAVY; HEAVY = hand-drawn title font `QoLFont.HEAVY_GLYPHS`). `QoLTopInfo` writes the upper-screen header
  + description of the row under the cursor; `QoLFpsCounter` (row or F3 anywhere).
- PORT tile art: `QoLButton` (`qol_button.gd`) rewrites the centre tile's texture (tile k = 16-colour texture at slot 0 +
  k·0x1000; offset 0x4000) with the user's `assets_qol/port_button.png` while scene 0x020738E0 runs (`btndbg`, `nobutton`).
- Layout preview: `tools/qol_preview.tscn` renders every page / state in seconds (no emulation).

## Sound: music / SFX switches, volume, jukebox, random music
- Switches mute hardware channels by owner (BGM player tracks + stream channels vs the rest); VOLUME = master bus.
- Jukebox: 20 streams + 18 MIDI sequences from the SDAT, played through the game's own BGM functions on the game thread
  (`on_game_thread`); leaving restores the menu music and the sound heap. `QoLSound` (`qol_sound.gd`) reads the SDAT.
- RANDOM MUSIC: f_0200FE48 / f_0200FE98 remapped stream→stream and sequence→sequence (no bigger than the original + 32 KiB,
  `QoLSound.seq_size`); new seed (`music_seed`) each time it is switched on; the jukebox sets `music_bypass`.

## Controls, gamepad cursor, auto pause
- `QoLControls` (`qol_controls.gd`) owns the ds_* input map (defaults from project.godot, one key + one pad input per
  button, swap on conflict, [controls] in settings.cfg, applied with InputMap). CONTROLS sub-pages wait for a raw event
  (`QoLMenu.finish_wait`); menu input is ignored until the mapped key is released.
- `QoLCursor` (`qol_cursor.gd`, as `pad_cursor` under `screen_root`) on the lower screen while a gamepad is connected;
  actions `qol_cur_up/down/left/right/click` (defaults right stick a:3/a:2, R3 b:8); `cursor_enabled` / `cursor_speed`
  in [controls]; speed default 5 (old cfg files without `cursor_speed_v` migrate once). CONTROLS page 3 = MOUSE CURSOR.
- AUTO PAUSE: GameDS skips stepping while the app is unfocused.

## Display, window, smooth motion, performance mode (renderer side)
- Display (part 15): outside captures GameDS draws into a 256x384 SubViewport (`screen_root`) and `DSPresenter`
  (`scripts/render/ds_presenter.gd`) scales it: whole multiples in a window (nearest, no shader), sharp-bilinear fit in
  full screen, black clear colour / borders; touch goes through `presenter.to_ds()`.
- Smooth motion (FPS > 60): the game still steps at 59.83/s; in-between frames are drawn with `interp` = fraction of the
  way from the previous game frame (global shader uniforms `ds_interp_2d` / `ds_interp_3d`, [shader_globals] in
  project.godot): 2D BG scroll / sprite positions from `oam_prev` / `regs_prev` (ds_engine2d.gdshader), 3D vertices moved
  back by their screen motion (DSGX `out_prev` → CUSTOM1.yzw, ds_poly.gdshader), whole pixels, jumps > 32 px not blended,
  vertices on the screen edge never move inward. Pairing: polygon i ↔ previous polygon i when attr / texparam /
  PLTT_BASE / texcoords match — port effects give each untextured quad its own PLTT_BASE key.
- Frame pipelining (part 26): GameDS `_pipe_*`, `DSMachine.step_begin()` / `step_end()`; `pipeline=auto` only when
  frames come late (slow CPUs / Proton); never in captures. Details docs/TOOLING.md.
- PERFORMANCE MODE (part 32; BIG CHANGES): `QoLSettings.performance_mode` → `QoLController.apply_performance()` →
  `GameDS.set_perf_mode` (GameDS `## PERFORMANCE MODE` comment): pipelining forced, `DSDisplay.refresh_read()` /
  `refresh_apply()` split so uploads / mesh overlap the next game frame, no in-between frames. Never touches the
  emulated machine. Always-on exact speed-ups in scripts/core + render (deferred per-line register capture, io_write GX
  short path, scanline loop, native VRAM view copies) — docs/TOOLING.md "part 32".

## Cheats (pages 5-10; QoLGame overrides, P1 only in single player, both sides in MP)
| Cheat | Where / how |
|---|---|
| INFINITE HEALTH, ONE-HIT KO, HARD MODE | damage FUN_020293A4 (`f_020293a4`): P1 0 damage / enemy HP 0 unless guarding / P1 ×2, enemies ÷2 |
| INFINITE KI, NO COOLDOWN | ki spend FUN_02027950 + FUN_0202954C pre-hook (team ki 0xC800); A/Y during an attack → neutral via FUN_02021B4C; `_nc_keep` converts only the cut attack's objects |
| KI HOMING | ki-blast handler FUN_020209E0 (turn 3/256 per frame) |
| TRIPLE KI BLASTS | two copies via FUN_020225C8 (`# ---- TRIPLE KI BLASTS`) |
| ATTACK SPAM | FUN_0202B630 on a new press (`# ---- ATTACK SPAM`) |
| INFINITE ASSISTS / ASSIST SPAM | team +0x8CA; FUN_02026C00 / FUN_020277AC / FUN_020294B8 overrides, copies of the support record at 0x02700000 (max 8 / side) |
| SAME CHARACTERS | character select f_0206cc94 / f_0206abb0; `_hide_fighters()` keeps the one-support / START rules |
| BOSS CHARACTERS | pick with L held (f_0206CC94), `QoLController._boss_frame`; boss level + boss scripts after the loader f_0202A40C; `QoLMarkers` skulls; boss dash fix `# ---- BOSS DASH` (f_0202c1d4, overflow also in the original) |
| RANDOM CHARACTERS | party rewritten at f_020140C8, restored after f_02013D60 |
| CHARACTER / CHAOS SHUFFLE | `_shuffle_*` (`# ---- CHARACTER SHUFFLE`, `# ---- CHAOS SHUFFLE`, `# ---- CHAOS SHUFFLE FIXES` with `_chaos_held` waits); load uploads skipped while loading (`_shuf_loading`) — card-DMA freeze workaround |
| RANDOM STAGE / STAGE SHUFFLE | f_020140C8 writes 0x020DD54A; `# ---- STAGE SHUFFLE` (`_stg_busy`, `_stage_regs_defer` / `_stage_regs_apply`) |
| RANDOM MUSIC | see Sound |
| GREEN DEMON (part 36, page 10 CHALLENGES) | `scripts/qol/qol_green_demon.gd` (no class_name) owned by QoLGame `# ---- GREEN DEMON (part 36)`: tick from f_0202954C, reset at f_0202A40C, drawn in `_fx_draw`, f_02021DD4 override (wrap-around / STAGE SHUFFLE move it), `_gd_kill` (KO through f_020293A4 with `_gd_killing` = damage cheats skipped). Art assets_qol/greendemon.png (16x16, from greendemon_src.png); texels in the shared port texture block `scripts/qol/qol_texblock.gd` (QoLGame `_tex_block()`, also BOMB RAIN's). Hunts P1 (both players in local / LAN MP: `_mp_on()`); LAN-safe (own RNG, game camera) |
| BOMB RAIN (part 38: a cheat, CHALLENGES (page 10 since part 42) under GREEN DEMON) | see "Weird stuff" below for the code; `QoLSettings.bomb_rain` is now a property over `cheats["bomb_rain"]` ([cheats] in settings.cfg; an old [weird] value is read once when [cheats] has none) |
| ULTRA INSTINCT (part 39; page 9 POWERS since part 41, page 5 before) | `scripts/qol/qol_ultra.gd` (no class_name) owned by QoLGame `# ---- ULTRA INSTINCT (part 39)`: `tick` from f_0202954C (`_c39_tick`: a fresh B press opens a 5-pass parry window), `before` / `after` around the collision pass (QoLGame override f_0201E5BC: its own copy of the box test finds enemy attack boxes on the parrier, who is left out of that pass with +4 = 0; then stun 0x11 / reflect / ignore + hit stop + guard spark 0xB + SE 0x21), drawn in `_fx_draw` (silhouettes through two palettes it allocates with the game's FUN_02010B6C; `_spr_copy` / `_spr_emit` got a `pal` argument) |
| RANDOMIZER (part 39, page 7 CHARACTERS) | QoLGame `# ---- RANDOMIZER (part 39)`: override f_0202AEB4 (the action dispatcher: a super / ultimate started → record bytes AND the team block tail (ki: the ultimate test FUN_02026A8C spends its 150 % itself; part 40 fix) put back (`_rz_snap` / `_rz_restore`), an ultimate the random fighter's own test refuses is started the dispatcher's way (`_rz_ultimate`), `_rz_load` = CHARACTER SHUFFLE's loader with a random id, dispatcher again), `_rz_tick` (back on a hit / win pose / when the super and its objects are over), `_rz_back`; shuffles wait (`_shuffle_tick`); LAN seed with the battle seed |
| FLIGHTLESS (part 39, page 10 CHALLENGES) | QoLGame `# ---- FLIGHTLESS (part 39)` `_fl_tick` (from `_c39_tick`, both teams' active fighters): own fall speed added to y; the game's ground test FUN_020214C4 lands them; part 40: a takeoff gets an extra lift and a lighter pull while rising (`_fl_up`: ~35 px jump) |
| SMASH KNOCKBACK (part 39, page 10 CHALLENGES) | QoLGame `# ---- SMASH KNOCKBACK (part 39, part 40)`: f_020293A4 notes victims while `_kb_on` (inside the f_0201E5BC override), `_kb_apply` scales their push after the pass and marks them launched (`_kb_free`); override f_02019594 (camera mode 0) undoes the tether pull for launched fighters and keeps the centre near the other one; `_kb_tick` (from `_c39_tick`) off-camera damage; `_kb_draw` edge markers (face icon sprite rec+0x290 via `_spr_emit`; part 41: drawn 1:1 = its 32x32 texture with the 24x24 face at the top left, in a 28 px box, kept below the RUSH counter) |
| HOT POTATO (part 40, page 10 CHALLENGES) | `scripts/qol/qol_potato.gd` (no class_name) owned by QoLGame `# ---- HOT POTATO (part 40)`: tick from f_0202954C, `hit` from f_020293A4 while `_hp_coll` (inside the f_0201E5BC override), reset at f_0202A40C, drawn in `_fx_draw` (BOMB RAIN's bomb frames in the shared texture block + the DAMAGE NUMBERS digits `_dn_emit`; part 41: bomb 1:1, digits one size smaller) |
| RICOCHET KI (part 40, page 6) | QoLGame `# ---- RICOCHET KI (part 40)` `_rc_bounce` after the plain-shot handler (f_020209E0 override); slot counts forgotten in f_020225C8 |
| VAMPIRE (part 41, page 9 POWERS) | `scripts/qol/qol_vampire.gd` (no class_name) owned by QoLGame `# ---- VAMPIRE (part 41)`: f_020293A4 measures the HP really lost around the whole damage call while `_vp_coll` (inside the f_0201E5BC override; `_vp_in` guards the re-entry) → `hit` heals the other side's active fighter 40 %; drawn in `_fx_draw` (green palette via FUN_02010B6C at 0x027C0140, sparks, "+N" with the DAMAGE NUMBERS digits: glyph ':' = "+") |
| TIME SKIP (part 41, page 9 POWERS) | `scripts/qol/qol_timeskip.gd` (no class_name) owned by QoLGame `# ---- TIME SKIP (part 41)`: tick from f_0202954C (Select edge on +0x270, CPU chance, end rules); the frozen side's fighter runs `freeze_step` instead of FUN_0202954C (hurt box registered, nothing else); overrides f_02021F54 (its objects get obj +4 bit 4 around the effect loop), f_0201E224 / f_02019594 (it cannot be pushed / tethered), f_020294B8 (its support only drawn); ALL-STAR hearts leave SELECT to it (`QoLAllStarHearts.filter`); drawn in `_fx_draw` (violet tint quad, the skipper's copy, the frozen fighter grey via a palette at 0x027C01A0, rings) |
| NONDIRECTIONAL (part 42, page 5 FIGHTING) | QoLGame `# ---- NONDIRECTIONAL (part 42)`: f_0202AEB4 wraps the dispatcher (`_aeb` = the old body with RANDOMIZER's handling): `_nd_pick` (pure precheck of the super / ultimate with the held direction's angle) -> +7 = that angle for the call, put back after |
| Z-VANISH (part 42, page 9 POWERS) | `scripts/qol/qol_zvanish.gd` (no class_name) owned by QoLGame `# ---- Z-VANISH (part 42)`: tick for each active fighter from f_0202954C (before it runs, after TIME SKIP's freeze check): B edge in hit stun 0xF-0x12 -> FUN_02021340 stop, placed behind the attacker, neutral, +0x250 \|= 0x40 while untouchable; CPU roll per hit stun (seeded); afterimages in `_fx_draw` |
| BODY CHANGE (part 42, page 9 POWERS) | `scripts/qol/qol_bodychange.gd` (no class_name) owned by QoLGame `# ---- BODY CHANGE (part 42)`: tick from f_0202954C (HP shares swapped every 1200 battle frames), countdown (DAMAGE NUMBERS digits, bottom centre), ray + violet glow (palette at 0x027C01C0) in `_fx_draw` |
| DRAGON BALL HUNT (part 41, page 10 CHALLENGES) | `scripts/qol/qol_dragonballs.gd` (no class_name) owned by QoLGame `# ---- DRAGON BALL HUNT (part 41)`: tick from f_0202954C, `hit` from f_020293A4 while `_db_coll` (VAMPIRE's measured HP), reset at f_0202A40C, drawn in `_fx_draw`. Art: the game's own clear-event Dragon Balls (clearevent.bin db_normal.ntft + palettes) decoded at runtime from the player's ROM, box-filtered to 24 / 12 px 16-colour textures in the shared texture block (grown to 12 KiB in part 41: 0x5D000-0x60000), palettes via FUN_02010B6C at 0x027C0160 |
| Leaderboard rule | f_02002560 returns 0 while `QoLSettings.cheats_on() > 0`; `reset_leaderboards()` (`# ---- LEADERBOARD`); the ALL-STAR / ENDLESS records pages write nothing either |

## Weird stuff (pages 11-13) and other picture effects
- Renderer only (no game state): BEVEL EMBOSS, TOUCH FUZZY (`FX_*` shader variants in ds_engine2d / ds_poly,
  ds_fx_bevel.gdshader; global uniform `ds_fx`), GAME BOY (ds_fx_gameboy.gdshader), MIRROR MODE (`DSDisplay.mirror_active()`;
  GameDS swaps LEFT / RIGHT; off in pause), SCREEN SHAKE (`FX_SHAKE`; f_020293A4 records `shake_dmg`) — `DSDisplay`
  sections `# ---- WEIRD SETTINGS` / `# ---- SCREEN SHAKE`; battle signal `DSDisplay.battle_on_screen()`.
- CRT TV: `QoLCrt` + shaders/ds_fx_crt.gdshader via `DSPresenter.set_crt` (CanvasLayer 65 in captures; the menu stays sharp).
- QoLGame drawing (GX quads after the game's sprite list, `_fx_draw` path): BLOOD / AFTERIMAGES (`# ---- BLOOD /
  AFTERIMAGES`), FLASHY KI / KO CONFETTI (`# ---- FLASHY KI / KO CONFETTI`), DAMAGE NUMBERS / RAINBOW KI (`# ---- WEIRD 3`,
  f_020A71C8 per-sprite hook), DETAILED SHADOWS (silhouettes in the f_02011384 override, `# ---- DETAILED SHADOWS`).
- BOMB RAIN (a cheat since part 38, CHALLENGES page): `scripts/qol/qol_bombs.gd` (no class_name; owned by QoLGame `# ---- BOMB RAIN`): sprite
  assets_qol/bomb.png (from the user's bomb_src.png), one direct-colour textured quad per bomb at texture VRAM 0x5F000
  reserved through the game's texture manager 0x020DE380 (part 36: that block is `qol_texblock.gd`, shared with GREEN
  DEMON and HOT POTATO; part 41: grown downward to 12 KiB for DRAGON BALL HUNT, `put()` offsets unchanged from 0x5F000,
  `put_abs()` for the new part); hits copy FUN_0201E9EC, explosion FUN_0202247C / FUN_0202216C + SE 0x1E.
- INPUT DISPLAY: `QoLInputDisplay` (pad word 0x020DD4E0). 2ND FIDDLE: `# ---- 2ND FIDDLE`. EPIC MODE: `QoLEpic` (text
  rewriter; story strings via FUN_0200B954), `QoLEpicImg` + `QoLEpicRefs` (Data File / credits pictures; FUN_02009B28
  override). JELLY FIGHTERS was removed in part 25.

## CAMERA ZOOM, AUTO SKIP
- CAMERA ZOOM (`# ---- CAMERA ZOOM`): zoom written only while drawing (f_02019328, f_02012d70, f_02012154; perspective
  f_020a7710), so game logic is identical at every level; stage-object culling widened (`zoomcull=0` = off).
- AUTO SKIP (`# ---- AUTO SKIP`): story — f_0203E214 reports the game's own SKIP touch button; Z-Battle VS screen —
  f_02018714 gets A.

## LOCAL MULTIPLAYER (part 27-29; design docs/MULTIPLAYER_DESIGN.md)
- Session `QoLMp` (`qol_mp.gd`), shared by `QoLController.mp` / `QoLGame.mp`; inert outside a session.
- VS menu scene 0x11 relabelled LOCAL / LAN (f_0207b778) + setup page `QoLMpMenu`; per-player devices `QoLMpInput`.
- Select = Practice scene 3 mode 0xB with two tinted outlines (f_0206cc94 etc., `QoLMpSelect`, `# ---- MULTIPLAYER
  SELECT`); stage scene 5 (f_0207215c); battle = Free Battle mode 5 with P2 input via f_0202dce0 (CPU AI replaced; `#
  ---- MULTIPLAYER BATTLE`) and lower screen `QoLMpPanel` (`QoLController.mp_panel`); scene redirects in f_02001014.
- `# ---- MP SUPPORTS` (part 28), `# ---- MP TEAM ARTS LIGHT` / `# ---- MP DUAL ASSISTS` (part 29: per-side assist slots;
  f_0202B580 / f_0202759C / f_0202B4A0).

## LAN MULTIPLAYER (parts 30-32; design docs/LAN_DESIGN.md)
- Deterministic lockstep with input delay (no rollback: DS threads are parked Godot threads, no savestates).
- `QoLLanNet` (ENet on UDP 8082, fallback 8083-8091, own service thread); `QoLLan` (`qol_lan.gd`: session, handshake build
  id + ROM MD5, settings snapshot never saved, battle-start sync in f_020140C8: f_020019FC(1), 0x020DD7B4, parties / stage /
  host save copy / port seeds; checksum from f_0202A40C; `# ---- LAN SESSION RESET / WATCHDOG (part 31)`); GameDS
  `_tick_begin` gate.
- Menus `QoLLanMenu` + `QoLKeyboard` (QoLController `# ---- LAN MENU`); select = the game's HOST path scene 4 mode 2,
  stage = LOCAL two-outline code + host 50/50; guest panel `QoLLanPanel` + PING, kept in pause (`QoLLan.battle_side`).
- Lower-screen layer mask after the LAN pages: one `QoLController._keep_mask()` rule + per-frame `_layers_guard()` (part 31).

## NEW GAMEMODES / ALL-STAR (part 34; design docs/ALLSTAR_DESIGN.md)
- Setting `QoLSettings.new_gamemodes` (BIG CHANGES row NEW GAMEMODES; `newmodes=`). Session `QoLAllStar`
  (`qol_allstar.gd`, shared by `QoLController.allstar` / `QoLGame.allstar`; API in ALLSTAR_DESIGN 2a).
- Menus (phase 1): `QoLAllStarMenu` (`qol_allstar_menu.gd`) rewrites the game's textures like QoLButton — Mode Select
  tile 5 label FREE BATTLE -> GAMEMODE (letters copied from the other tiles' labels + the port's own G), and in scene
  0xB the bar textures (+0x2000 ALL-STAR, +0x4000 EMPTY, both from the Hard bar). QoLGame `# ---- ALLSTAR MENU (part
  34)`: `f_02075738` (tile 5 -> scene 0xB), `f_0205495c` (4 bars + cursor), `f_0204dd8c` (input: keys / taps / repeat,
  exit 3 -> All-Star select, 4 -> Mode Select), `_gm_route` (hooked at the top of `f_02001014`: 0xB -> 4 mode 5,
  4 -> 6 => 0xB, battle exits 0x14 / 10 / 3 / 0xD => 4, 0 -> 6 ends the session, `allstar=1`). QoLController `# ----
  ALLSTAR (part 34)`: `_as_after` (labels, tile-5 text in `top`, `as_top` = QoLTopInfo with `full` colours over the
  course select's upper screen, faded with the game).
- Battle rules (phase 2): QoLGame `# ---- ALLSTAR BATTLE (part 34)` (prefix `_asb_`): `_asb_battle_setup` /
  `_asb_battle_started` (hooked in `f_020140c8`: P2 pair, stage 4, no time limit), `f_020010f4` (per-frame tick: KO
  count, clock, reload of the KO'd CPU record with the shuffle loader, hearts, HUD MM:SS + "n/26" in BG1 tiles
  0x180-0x197, result), `f_02027164` / `f_02026e34` (CPU tag / Team Arts refused). `QoLAllStarHearts`
  (`qol_allstar_hearts.gd`, QoLController `as_hearts`: drawn in `after_step`, taps / SELECT in `filter_input`) = the
  three hearts under "Team Arts" (revive `FUN_020298D4` + heal `FUN_02029428` on the game thread). Part 35 life
  bars: `_asb_bar_paint` / `_asb_bars` + override `f_0201cbbc` repaint a member's bar colour buffer from its HP (after a
  heart, at every tag-in / KO entrance, after a CPU reload).
- Stage look + music (phase 3): `QoLAllStarStage` (`qol_allstar_stage.gd`), owned by QoLGame `# ---- ALLSTAR STAGE (part
  34)` (`_ass_reset` / `_ass_tick`, called from the ALLSTAR BATTLE section only while `_asb_on`): BG3 space sky
  (part 35: procedural gradient + nebula + 230 coloured twinkling stars + 6 glints, built on a thread at `reset()`,
  palette 32-188) + hidden light-ray objects (Time Chamber sky only), and the BGM rotation (stream position
  vs `as_strm_info` from `QoLSound.strm_info`, switch = the game's stop + play).
- Records (phase 4): `QoLAllStarRecords` (`qol_allstar_records.gd`, QoLController `as_records`: opened in `after_step`
  when `QoLAllStar.records_req` is set by QoLGame `# ---- ALLSTAR RECORDS (part 34)` `_asr_win` (a won battle asking for
  scene 10, rerouted to the select by `_gm_route`), all input in `filter_input` while shown) = the ALL-STAR RECORDS page
  over both screens from `game/result.bin` art, `allstar_records.cfg` I/O; `retitle()` also relabels the Gamemode
  menu's header (QoLAllStarMenu `bars_frame`, COURSE SELECT -> GAMEMODE SELECT). Part 35 redesign: upper = the
  results' score panel (e_res_bg + CharFace256 portraits + cstat_bg hexagons), lower = the HI-SCORE RANKING + OK plate;
  letters cut at runtime from the game's pre-lettered labels (inner classes `Canvas` = index image, `GFont` = harvested
  font; `harvest()` / `harvest_plate()` / `plate_title()`); `show_page()` builds + shows (also from
  `tools/qol_preview.gd` `asrec`).
- ENDLESS (part 38; docs/ALLSTAR_DESIGN.md section 7): the same session class with `QoLAllStar.endless` — Gamemode
  menu slot 1 (`f_0205495c` draws the third bar object, texture +0x6000 relabelled ENDLESS by QoLAllStarMenu;
  `_gm_decide` / `_gm_route` start the session with `start(menu_cursor == 1)`), every battle hook of `# ---- ALLSTAR
  BATTLE` unchanged except: enemies from `QoLAllStar.at(i)` (random list growing on demand, never one of the two
  before), `total()` = no end, HUD tracker = enemies beaten. Death (0 -> 0x14) -> `_asr_win` asks for the records page;
  `QoLAllStarRecords.endless` = the ENDLESS RECORDS layout (`_open_endless`, `_table_lines_e`, `_row_endless`,
  `_banner_word` = GAME OVER in the WINNER band's own typeface (`harvest_cc`, `_make_m`, `_shrink`), `_make_d`; shared:
  `_packed` digits, GFont.contour title spacing, `_label_room`) and
  `endless_records.cfg` (`path(true)`, `before_e`). Preview: `tools/qol_preview.gd asrec` states `es_*`.
