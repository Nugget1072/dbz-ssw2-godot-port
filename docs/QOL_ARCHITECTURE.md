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
- Pages (`QoLMenu.PAGES`, 12): 1 SETTINGS (`main`: WINDOW SIZE 1X/2X/4X/8X/FULL with 10-s KEEP/UNDO `confirm` page, FRAME
  RATE 60/120/240/MAX, FPS COUNTER, MUSIC, SOUND FX, JUKEBOX) · 2 SETTINGS 2 (`main2`: CONTROLS, VOLUME, AUTO PAUSE,
  DETAILED SHADOWS, ZOOM, HI-SCORES RESET → `lbconfirm` page) · 3 SETTINGS 3 (`main3`: AUTO SKIP, DAMAGE NUMBERS, INPUT
  DISPLAY) · 4 BIG CHANGES (`mpset`: MULTIPLAYER, PERFORMANCE) · 5-9 cheats (`QoLMenu.CHEAT_PAGES`: FIGHTING, KI &
  ASSISTS, CHARACTERS, STAGE & MUSIC, CHALLENGES (part 36: GREEN DEMON; part 38: + BOMB RAIN)) · 10-12 WEIRD STUFF
  (`QoLMenu.WEIRD_PAGES`: 10 bevel / fuzzy / game boy / mirror / shake / crt, 11 blood / afterimages / 2nd fiddle / epic /
  flashy / confetti, 12 rainbow). HI-SCORES RESET (`lbyes`) also calls `QoLAllStarRecords.reset_files()` (part 38). The header's help text (`QoLMenu` page-row description) lists the page numbers. Sub-pages:
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

## Cheats (pages 5-9; QoLGame overrides, P1 only in single player, both sides in MP)
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
| GREEN DEMON (part 36, page 9 CHALLENGES) | `scripts/qol/qol_green_demon.gd` (no class_name) owned by QoLGame `# ---- GREEN DEMON (part 36)`: tick from f_0202954C, reset at f_0202A40C, drawn in `_fx_draw`, f_02021DD4 override (wrap-around / STAGE SHUFFLE move it), `_gd_kill` (KO through f_020293A4 with `_gd_killing` = damage cheats skipped). Art assets_qol/greendemon.png (16x16, from greendemon_src.png); texels in the shared port texture block `scripts/qol/qol_texblock.gd` (QoLGame `_tex_block()`, also BOMB RAIN's). Hunts P1 (both players in local / LAN MP: `_mp_on()`); LAN-safe (own RNG, game camera) |
| BOMB RAIN (part 38: a cheat, page 9 under GREEN DEMON) | see "Weird stuff" below for the code; `QoLSettings.bomb_rain` is now a property over `cheats["bomb_rain"]` ([cheats] in settings.cfg; an old [weird] value is read once when [cheats] has none) |
| Leaderboard rule | f_02002560 returns 0 while `QoLSettings.cheats_on() > 0`; `reset_leaderboards()` (`# ---- LEADERBOARD`); the ALL-STAR / ENDLESS records pages write nothing either |

## Weird stuff (pages 10-12) and other picture effects
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
  DEMON); hits copy FUN_0201E9EC, explosion FUN_0202247C / FUN_0202216C + SE 0x1E.
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
  `_gameover_letters` = the Game Over screen's title from `game/gameover_dat.arc` over the WINNER band, `_make_d`) and
  `endless_records.cfg` (`path(true)`, `before_e`). Preview: `tools/qol_preview.gd asrec` states `es_*`.
