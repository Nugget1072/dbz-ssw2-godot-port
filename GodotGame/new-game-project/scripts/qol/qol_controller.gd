class_name QoLController
extends Node
## Quality-of-life layer on top of the original game (GameDS): the settings menu behind Mode Select's unused
## Dragon Ball tile, applying the settings (window size, frame rate, music / sound effect switches) and the
## jukebox. The game's code is not changed: the port reads Mode Select's state from RAM, moves its cursor onto
## the centre tile (index 4, which the game highlights but never selects) and keeps input away from the game
## while the menu is open.

# Mode Select (DATA_NOTES "QoL: Mode Select")
const MS_VBLANK_CB := 0x020DE374     ## the scene's VBlank callback slot: 0x020738E0 while Mode Select runs
const MS_VBLANK_FN := 0x020738E0
const MS_CURSOR := 0x020DEC20        ## u8 tile 0..8 (row-major 3x3; 4 = the Dragon Ball tile)
const MS_STATE := 0x020DEBD8         ## u8 scene step: 3 while the player chooses (4 once a mode was picked)
const CENTER_RECT := Rect2i(88, 64, 81, 45)   ## Dragon Ball tile on the touch screen
## from these tiles the D-pad direction toward the centre lands on the Dragon Ball tile (the game skips it)
const TO_CENTER := {1: 7, 3: 4, 5: 5, 7: 6}   ## cursor -> KEYINPUT bit (4 right, 5 left, 6 up, 7 down)

var game                             ## GameDS
var mp := QoLMp.new()                ## part 27 LOCAL MULTIPLAYER session (QoLMp.active only during a session)
var lan := QoLLan.new()              ## part 30 LAN session + lockstep (always created; IDLE = inert)
var allstar := QoLAllStar.new()      ## part 34 NEW GAMEMODES / ALL-STAR session (`active` only during a session)
var machine: DSMachine
var settings := QoLSettings.new()
var controls: QoLControls:                ## the DS button mapping (part 16), kept in the settings
	get: return settings.controls
var paused := false                      ## AUTO PAUSE: the window is not in front (GameDS does not step the game)
var _focused := true
var sound := QoLSound.new()
var menu: QoLMenu
var top: QoLTopInfo
var fps_counter: QoLFpsCounter
var markers: QoLMarkers
var pad_cursor: QoLCursor                    ## gamepad mouse cursor on the touch screen (part 24, CONTROLS page 3)
var input_display: QoLInputDisplay           ## WEIRD 3 INPUT DISPLAY (part 25)
var crt: QoLCrt                              ## WEIRD 3 CRT TV (part 25)
var mp_panel: QoLMpPanel                     ## part 27 MP battle lower screen; route(mp) = per-half battle taps
var as_hearts: QoLAllStarHearts              ## part 34 ALL-STAR battle: the three hearts under "Team Arts"
var as_records: QoLAllStarRecords            ## part 34 ALL-STAR records page after a win (both screens)
var lan_panel: QoLLanPanel                   ## part 30 phase 3: LAN battle (guest's side-1 panel, PING) / select bands
var mp_menu: QoLMpMenu                       ## part 27 VS menu LOCAL / LAN overlay + controller setup page
var mp_cursors: Array = []                   ## part 27 the players' gamepad cursors (red P1, blue P2)
var mp_select: QoLMpSelect                   ## part 27 MP select / stage select / battle-end marks
var mp_input: QoLMpInput:                    ## part 27 per-player devices / mappings (kept in the settings)
	get: return settings.mp_input
var font: QoLFont
var button := QoLButton.new()            ## Mode Select's centre tile shows the port's own picture (part 22)
var _layers_hidden := false
var in_mode_select: bool = false
var cursor: int = -1
var _prev_keys: int = 0x3FF
var _prev_touch: bool = false
var _block_keys: int = 0             ## keys held through a QoL action stay hidden from the game until released
var _block_touch: bool = false
var _menu_ignore: int = 0
var _se_dbg := 0


func setup(g, m: DSMachine, rom: PackedByteArray) -> void:
	game = g
	machine = m
	settings.load_file()
	apply_controls()
	_set_icon(rom)
	if Game.args.has("weird"):           # debug / tests: weird=bevel,fuzzy,epic,fiddle turns WEIRD SETTINGS on
		var w := Game.flag("weird").split(",", false)
		settings.bevel_emboss = "bevel" in w
		settings.touch_fuzzy = "fuzzy" in w
		settings.epic_mode = "epic" in w
		settings.second_fiddle = "fiddle" in w
		settings.blood = "blood" in w
		settings.afterimages = "after" in w
		settings.game_boy = "gameboy" in w
		settings.mirror_mode = "mirror" in w
		settings.flashy_ki = "flashy" in w
		settings.screen_shake = "shake" in w
		settings.ko_confetti = "confetti" in w
		settings.damage_numbers = "dmgnum" in w
		settings.rainbow_ki = "rainbow" in w
		settings.bomb_rain = "bombs" in w
		settings.input_display = "inputs" in w
		settings.crt_tv = "crt" in w
	if Game.args.has("zoom"):            # debug / tests: zoom=0..4 sets CAMERA ZOOM (2 = the game's own)
		settings.camera_zoom = clampi(int(Game.flag("zoom")), 0, 4)
	if Game.args.has("newmodes"):        # debug / tests: newmodes=1 / 0 sets NEW GAMEMODES (part 34)
		settings.new_gamemodes = Game.flag("newmodes") != "0"
	if Game.args.has("perfmode"):        # debug / tests: perfmode=1 / 0 sets PERFORMANCE (part 32)
		settings.performance_mode = Game.flag("perfmode") != "0"
	if Game.args.has("mp"):              # debug / tests: mp=1 / 0 sets MULTIPLAYER (part 27)
		settings.multiplayer = Game.flag("mp") != "0"
	if Game.args.has("autoskip"):        # debug / tests: autoskip=1 / 0 sets AUTO SKIP
		settings.auto_skip = Game.flag("autoskip") != "0"
	if Game.args.has("shadows"):         # debug / tests: shadows=1 / 0 sets DETAILED SHADOWS
		settings.detailed_shadows = Game.flag("shadows") != "0"
	if Game.args.has("cheats"):          # debug / tests: cheats=a,b,... turns these on (names: QoLSettings.CHEATS)
		for k in Game.flag("cheats").split(",", false):
			settings.cheats[k] = true
	if m.core is QoLGame:
		m.core.cheats = settings
		m.core.mp = mp                    # part 27: LOCAL MULTIPLAYER session (inactive unless a session runs)
		m.core.lan = lan                  # part 30: LAN session (IDLE unless a session runs)
		m.core.allstar = allstar          # part 34: ALL-STAR session (inactive unless a session runs)
	sound.setup(m.core, rom)
	font = QoLFont.new(rom)
	top = QoLTopInfo.new()
	top.font = font
	g.screen_root.add_child(top)
	_as_setup(g)                         # part 34: Gamemode menu upper screen + labels (`# ---- ALLSTAR`)
	menu = QoLMenu.new()
	menu.qol = self
	menu.font = font
	menu.focus_changed.connect(_update_top)
	g.screen_root.add_child(menu)
	fps_counter = QoLFpsCounter.new()
	fps_counter.font = font
	g.screen_root.add_child(fps_counter)
	input_display = QoLInputDisplay.new()   # part 25 (WEIRD 3): battles, top screen
	input_display.settings = settings
	input_display.display = g.display
	g.screen_root.add_child(input_display)
	crt = QoLCrt.new()                      # part 25 (WEIRD 3): CRT TV (presenter shader / CanvasLayer 65)
	crt.qol = self
	add_child(crt)
	markers = QoLMarkers.new()
	g.screen_root.add_child(markers)
	mp_panel = QoLMpPanel.new()             # part 27: MP battle lower screen (both teams) + per-half tap routing
	mp_panel.setup(self, rom)
	g.screen_root.add_child(mp_panel)
	as_hearts = QoLAllStarHearts.new()      # part 34: ALL-STAR battle hearts (nothing outside an All-Star battle)
	as_hearts.setup(self)
	g.screen_root.add_child(as_hearts)
	as_records = QoLAllStarRecords.new()    # part 34: ALL-STAR records page (nothing until a won All-Star battle)
	as_records.setup(self, rom)
	g.screen_root.add_child(as_records)
	lan_panel = QoLLanPanel.new()           # part 30 phase 3: guest's panel, PING, WAITING bands (nothing without LAN)
	lan_panel.setup(self)
	g.screen_root.add_child(lan_panel)
	mp_menu = QoLMpMenu.new()               # part 27: LOCAL / LAN overlay and the controller setup page
	mp_menu.qol = self
	mp_menu.font = font
	g.screen_root.add_child(mp_menu)
	lan_menu = QoLLanMenu.new()             # part 30: LAN pages (HOST / JOIN, keyboard, connecting, lobby)
	lan_menu.qol = self
	lan_menu.font = font
	g.screen_root.add_child(lan_menu)
	mp_select = QoLMpSelect.new()           # part 27: 1P / 2P tags, READY plates, winner band
	mp_select.qol = self
	mp_select.mp = mp
	mp_select.font = font
	g.screen_root.add_child(mp_select)
	pad_cursor = QoLCursor.new()         # last child + z_index 1000: drawn over everything on the lower screen
	pad_cursor.qol = self
	g.screen_root.add_child(pad_cursor)
	for p in 2:                             # part 27: one cursor per gamepad player during a LOCAL session
		var c := QoLCursor.new()
		c.qol = self
		c.set_player(p)
		g.screen_root.add_child(c)
		mp_cursors.append(c)
	if m.core is QoLGame:
		if settings.music_seed == 0:
			settings.music_seed = randi() | 1
		m.core.shuffle_music(settings.music_seed, sound.seq_size)
	apply_display(true)
	apply_performance()                  # part 32: PERFORMANCE MODE from the settings file / `perfmode=`
	_update_top()                        # part 24 QA: the tile's text counts the cheats from the start too
	lan.setup(self, rom)                 # part 30 (debug flags `lan=` ... start a session here)


## every emulated frame, before the game reads its input: returns [keys, ext, touch] as the game will see them
func filter_input(keys: int, ext: int, touch: Vector2i) -> Array:
	var down := ~keys & 0x3FF                 # pressed now (active-high)
	var newly := down & ~(~_prev_keys & 0x3FF)
	var touching := touch.x >= 0
	var new_touch := touching and not _prev_touch
	_prev_keys = keys
	_prev_touch = touching
	_block_keys &= down                       # released keys are visible to the game again
	if not touching:
		_block_touch = false
	if as_records.shown:                     # part 34: the ALL-STAR records page takes every button / tap
		return as_records.filter(newly, down, touch, new_touch)
	if lan_menu != null and lan_menu.is_open():   # part 30: the LAN pages take every button / tap
		return _lan_input(newly, down, touch, new_touch)
	if lan.sel_on() and not lan.lockstep and not lan.aborting and not lan.in_battle:   # part 30 phase 3: LAN select / stage
		return lan.sel_filter(keys | _block_keys, ext, Vector2i(-1, -1) if _block_touch else touch, new_touch and not _block_touch)
	if menu.visible:
		_menu_ignore &= down                  # the press that opened the menu does not act in it
		menu.frame_input(newly & ~_menu_ignore, down & ~_menu_ignore, touch if new_touch else Vector2i(-1, -1))
		_block_keys = down                    # still held when the menu closes: kept from the game
		_block_touch = touching
		return [0x3FF, 0x2C00, Vector2i(-1, -1)]
	if in_mode_select:
		if TO_CENTER.has(cursor) and (newly & (1 << TO_CENTER[cursor])) != 0:
			# every new press of this frame is kept from the game: A / Start together with the move would otherwise
			# select tile 4 itself, which the game never expects (part 22 QA: it fell back to the opening screens)
			_block_keys |= newly
			_select_center()
			se(SE_MOVE)
		elif cursor == 4 and (newly & 1) != 0:   # A on the Dragon Ball tile
			_block_keys |= down
			se(SE_DECIDE)
			open_menu()
		elif new_touch and CENTER_RECT.has_point(touch):
			_select_center()
			_block_keys |= down                   # (a key pressed in the same frame as the tap: as above)
			_block_touch = true
			se(SE_DECIDE)
			open_menu()
	if as_hearts.shown:                      # part 34: ALL-STAR hearts: taps on a heart / SELECT kept from the game
		var hf: Array = as_hearts.filter(newly, touch, new_touch)
		_block_touch = _block_touch or hf[0]
		_block_keys |= hf[1]
	keys |= _block_keys
	if _block_touch:
		touch = Vector2i(-1, -1)
	return [keys, ext, touch]


## after every emulated frame (game thread parked): Mode Select state, sound switches
func after_step() -> void:
	var core = machine.core
	in_mode_select = core.r32(MS_VBLANK_CB) == MS_VBLANK_FN and core.r8(MS_STATE) == 3
	cursor = core.r8(MS_CURSOR) if in_mode_select else -1
	if menu.visible and not in_mode_select:
		menu.close()
	# part 27 QA: MULTIPLAYER on: the VS BATTLE tile (2) says what it opens now (the game's text is about wireless play)
	var vs_mp: bool = in_mode_select and cursor == 2 and settings.multiplayer and not menu.visible
	if vs_mp != _top_vs:
		_top_vs = vs_mp
		_update_top()
	top.visible = in_mode_select and (cursor == 4 or menu.visible or vs_mp)
	# behind the menu only the Mode Select background (BG1, hexagons) stays on the lower screen
	if menu.visible != _layers_hidden:
		_layers_hidden = menu.visible
		game.display.set_layer_keep(true, 0x200 if menu.visible else 0x1F00)
	_boss_frame(core)
	input_display.held_override = int(mp.held[1]) if lan.in_battle and lan.battle_side == 1 else -1   # part 30: own input (32: side)
	input_display.frame(core)            # part 25: INPUT DISPLAY (off: one test)
	mp_panel.frame(core)                 # part 27: MP battle lower screen (nothing outside an MP battle)
	as_hearts.frame(core)                # part 34: ALL-STAR hearts (nothing outside an All-Star battle)
	as_records.frame(core)               # part 34: ALL-STAR records page (opens after a won All-Star battle)
	_mp_after(core)                      # part 27: VS menu overlay / setup page / session end (off: one test)
	if lan.busy():
		lan.after_step(core)             # part 30: LAN battle start / checksums / end (IDLE: one test)
	if lan_menu.visible or _lan_layers or lan.state != QoLLan.IDLE or not lan.notice.is_empty():
		_lan_after(core)                 # part 30: LAN pages (nothing without a session, an open page or a notice)
	_layers_guard()                      # part 31: no port page open -> every layer drawn (one test)
	lan_panel.frame(core)                # part 30 phase 3: guest panel, PING, bands (no session: one test)
	mp_select.frame(core)                # part 27: MP select / stage / battle-end marks (nothing outside a session)
	button.frame(core, game.frames)
	_as_after(core)                      # part 34: GAMEMODE tile / Gamemode menu (NEW GAMEMODES off: one test)
	var snd: DSSound = core.arm7.sound
	var mute := 0
	if sound.ok and (not settings.music or not settings.sfx):
		var mm := sound.music_mask()
		if not settings.music and not sound.jb_active:
			mute |= mm
		if not settings.sfx:
			mute |= ~mm & 0xFFFF
	if snd.mute_mask != mute:
		snd.mute_mask = mute
	if _se_dbg > 0:   # debug (qoldbg): channels playing that are not music, for a few frames after a menu sound
		_se_dbg -= 1
		var act: int = snd.native.active_mask() if snd.native != null else 0
		if snd.native == null:
			for i in 16:
				if snd.ch[i].active:
					act |= 1 << i
		print("QOL f%d sfx channels %04x" % [game.frames, act & ~(sound.music_mask() if sound.ok else 0) & 0xFFFF])
	if Game.args.has("cheatdbg") and game.frames % 10 == 0:
		_cheat_debug(core)
	if Game.args.has("qoldump") and game.frames == int(Game.flag("qoldump")):
		sound.debug_dump()
	if Game.args.has("qoldbg") and game.frames % 20 == 0:
		var act := 0
		for i in 16:
			if snd.native != null:
				act = snd.native.active_mask()
				break
			if snd.ch[i].active:
				act |= 1 << i
		print("QOL f%d ms %s cur %d menu %s music %04x mute %04x active %04x" % [game.frames, in_mode_select, cursor, menu.visible, sound.music_mask() if sound.ok else 0, mute, act])


func _select_center() -> void:
	machine.core.w8(MS_CURSOR, 4)   # the game highlights the tile itself and navigates away from it normally
	cursor = 4


func open_menu() -> void:
	if lan.state != QoLLan.IDLE:         # part 30: no settings changes during a LAN session (5.4)
		return
	_menu_ignore = ~_prev_keys & 0x3FF
	menu.open()


## a cheat was switched in the menu; RANDOM MUSIC gets a new shuffle every time it is switched on
func cheat_changed(name: String, on: bool) -> void:
	if name == "random_music" and on and machine.core is QoLGame:
		settings.music_seed = randi() | 1
		machine.core.shuffle_music(settings.music_seed, sound.seq_size)


var _top_vs := false                  ## part 27 QA: the top box shows the MULTIPLAYER text of the VS BATTLE tile


func _update_top() -> void:
	if menu.visible:
		top.show_text(menu.focus_title(), menu.focus_desc())
	elif _top_vs:
		top.show_text("VS BATTLE", "LOCAL: two players on this PC,\nwith the keyboard and / or\ngamepads.\nLAN: against a friend's PC on\nyour network (HOST / JOIN).")
	else:
		var n := settings.cheats_on()
		top.show_text("SETTINGS", "Change the game's settings." + ("" if n == 0 else "\n\nCheats on: %d (menu pages 5-9)." % n))   # part 24 QA: pages moved, text ran out of the box


## keys that work anywhere in the game: F3 frame-rate counter, F11 full screen (both saved)
func handle_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	match event.keycode:
		KEY_F3:
			settings.fps_counter = not settings.fps_counter
		KEY_F11:
			settings.fullscreen = not settings.fullscreen
			apply_window()
		_:
			return false
	settings.save_file()
	apply_display()
	menu.queue_redraw()
	return true


## the gamepad cursor's touch for the game frame about to run (GameDS._tick, when the mouse does not touch)
func cursor_touch() -> Vector2i:
	var t := pad_cursor.frame_touch(game.frames + 1) if pad_cursor != null else Vector2i(-1, -1)
	for p in mp_cursors.size():          # part 27: the players' cursors (their touches go to mp_frame)
		mp_cursors[p].half = p if mp.active and mp_panel != null and mp_panel.shown else -1   # QA: own half in battle
		mp.ctouch[p] = mp_cursors[p].frame_touch(game.frames + 1)
	return t if not mp.active else Vector2i(-1, -1)


## every raw event (GameDS._input): mouse use hides the gamepad cursor, its click presses are latched
func cursor_event(event: InputEvent) -> void:
	if pad_cursor != null:
		pad_cursor.on_event(event)
	for c in mp_cursors:
		c.on_event(event)


## raw key / gamepad events (GameDS._input, before anything else): while CONTROLS waits for a new input the
## event is taken for the mapping and kept from the game. Returns true when the event was used.
func raw_input(event: InputEvent) -> bool:
	if lan_menu != null and lan_menu.key_event(event):   # part 30: typing on the LAN keyboard pages (ESC = B)
		return true
	if mp_menu != null and mp_menu.waiting():   # part 27: a player's mapping page (only that player's device)
		var mc := mp_input.capture(event, mp_menu.map_p)
		if mc == "cancel":
			mp_menu.cancel_wait()
		elif mc != "":
			mp_menu.finish_wait(mc)
		elif event is InputEventKey and event.pressed and (event.keycode == KEY_F3 or event.keycode == KEY_F11):
			return false
		return event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion
	var kind := menu.waiting_kind() if menu != null else ""
	if kind == "":
		return false
	var c := controls.capture(event, kind)
	if c == "cancel":
		menu.cancel_wait()
	elif c != "":
		menu.finish_wait(c)
	elif event is InputEventKey and event.pressed and (event.keycode == KEY_F3 or event.keycode == KEY_F11):
		return false   # still the FPS counter / full screen
	return event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion


## the input map from the settings (CONTROLS), saved with them
func apply_controls() -> void:
	controls.apply()
	settings.save_file()


## part 30 phase 4: the LAN network thread ends with the game
func _exit_tree() -> void:
	if lan != null:
		lan.on_exit()                    # (BYE: the other machine says "<NAME> LEFT")


## AUTO PAUSE: the window in front or not
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
	else:
		return
	_update_pause()


func _update_pause() -> void:
	var p := settings.auto_pause and not _focused and not Game.args.has("capture") and lan.state == QoLLan.IDLE   # part 30: never in LAN
	if p != paused:
		paused = p
		AudioServer.set_bus_mute(0, paused or settings.volume == 0)


## the window icon: the game's own icon from the ROM's banner (32x32, 4 bpp, 16 colours; NDS header +0x68 =
## banner offset, icon tiles at banner +0x20, palette at +0x220). Read from the player's ROM at startup, so the
## port itself contains no ROM data. Fallback: icon.png next to the exe, if the banner is missing.
func _set_icon(rom: PackedByteArray) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var img := banner_icon(rom)
	if img == null:
		var f := OS.get_executable_path().get_base_dir().path_join("icon.png")
		if FileAccess.file_exists(f):
			img = Image.load_from_file(f)
	if img == null:
		print("QOL icon: no banner icon in the ROM")
		return
	# window managers want a bigger picture than 32x32: whole-pixel scaling keeps it sharp
	var big := img.duplicate()
	big.resize(128, 128, Image.INTERPOLATE_NEAREST)
	DisplayServer.set_icon(big)
	if Game.args.has("qoldbg"):
		big.save_png(OS.get_user_data_dir().path_join("banner_icon.png"))
		print("QOL icon from the ROM banner")


static func banner_icon(rom: PackedByteArray) -> Image:
	if rom.size() < 0x200:
		return null
	var off := rom.decode_u32(0x68)
	if off == 0 or off + 0x240 > rom.size():
		return null
	var ver := rom.decode_u16(off)
	if ver < 1 or ver > 0x103:
		return null
	var pal := []
	for i in 16:
		var c := rom.decode_u16(off + 0x220 + i * 2)
		pal.append(Color8(((c & 31) * 255) / 31, (((c >> 5) & 31) * 255) / 31, (((c >> 10) & 31) * 255) / 31, 0 if i == 0 else 255))
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for t in 16:                      # 4x4 tiles of 8x8, 4 bpp (low nibble = left pixel)
		for y in 8:
			for x in 8:
				var b := rom[off + 0x20 + t * 32 + y * 4 + (x >> 1)]
				var v := (b >> 4) if (x & 1) else (b & 15)
				img.set_pixel((t % 4) * 8 + x, (t / 4) * 8 + y, pal[v])
	return img


## the game's own menu sounds (Mode Select FUN_02073AAC: cursor 5, decide 0, back 4), played with the game's SE
## function f_0200FF9C(0, id) on the game thread, so SOUND FX OFF and VOLUME apply as to every game sound (part 19)
const SE_DECIDE := 0
const SE_BACK := 4
const SE_MOVE := 5


func se(id: int) -> void:
	var core = machine.core
	on_game_thread(func(): core.f_0200ff9c(0, id))
	if Game.args.has("qoldbg"):
		print("QOL se %d at f%d" % [id, game.frames])
		_se_dbg = 8


## run `c` on the game thread at the start of the next frame (where the game itself changes music)
func on_game_thread(c: Callable) -> void:
	machine.inject.append(c)


# ------------------------------------------------------------------------------------------------ settings
func apply_display(startup: bool = false) -> void:
	if Game.args.has("capture"):         # frame-exact captures: always the plain 60 fps frames
		fps_counter.visible = settings.fps_counter and Game.args.has("qolcfg")
		return
	# FPS cap; with V-Sync the display's refresh rate already limits it (a limiter at the same rate as the
	# display only adds stutter), "uncapped" also turns V-Sync off
	var hz := DisplayServer.screen_get_refresh_rate()
	# part 32: PERFORMANCE MODE draws no in-between frames: every FRAME RATE acts as 60 (V-Sync on)
	var fps: int = 60 if settings.performance_mode else settings.fps
	# part 26: an unknown refresh rate (hz <= 0: Wine / Proton under gamescope, some Linux setups) is left to V-Sync
	# too, a 60 limiter on top of V-Sync only adds stutter there
	Engine.max_fps = 0 if fps > 0 and (hz <= 0 or hz <= fps + 1.0) else fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED if fps == 0 else DisplayServer.VSYNC_ENABLED)
	if Game.args.has("maxfps"):          # debug overrides (pace tests)
		Engine.max_fps = int(Game.flag("maxfps"))
	if Game.flag("vsync", "1") == "0":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game.smooth = (settings.smooth() and not settings.performance_mode) if not Game.args.has("smooth") else Game.flag("smooth") != "0"
	fps_counter.visible = settings.fps_counter
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(settings.volume, 0.01) / 100.0))
	AudioServer.set_bus_mute(0, paused or settings.volume == 0)
	_update_pause()
	if startup:
		apply_window()


## part 32: PERFORMANCE MODE (BIG CHANGES page) on / off: GameDS's cheaper paths (pipelining, picture work after
## the game frame starts, steady 30 fps when 60 does not fit) and no in-between frames (apply_display). Never changes
## what the game computes (LAN: each side may differ). Called by the menu and at startup.
func apply_performance() -> void:
	if game.has_method("set_perf_mode"):
		game.set_perf_mode(settings.performance_mode)
	apply_display()


## the window as the settings say: full screen, or windowed at `scale` x the DS screens
func apply_window() -> void:
	if Game.args.has("capture") or Game.args.has("presentfit") or DisplayServer.get_name() == "headless":
		return
	# full screen: DSPresenter fits the picture to the screen (sharp scaling); windows: whole multiples
	if settings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		set_window_scale(settings.scale)
	if game.get("presenter") != null:   # part 32: it reads the window mode only now and then
		game.presenter.recheck()
	if Game.args.has("qoldbg"):
		print("QOL window mode %d size %s" % [DisplayServer.window_get_mode(), DisplayServer.window_get_size()])


func set_window_scale(s: int) -> void:
	if Game.args.has("capture") or DisplayServer.get_name() == "headless":
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var size := Vector2i(256 * s, 384 * s)
	DisplayServer.window_set_size(size)
	var scr := DisplayServer.window_get_current_screen()
	var area := DisplayServer.screen_get_usable_rect(scr)
	DisplayServer.window_set_position(area.position + Vector2i(maxi(0, (area.size.x - size.x) / 2), maxi(0, (area.size.y - size.y) / 2)))


## debug (`cheatdbg`): battle state every 10 frames: HP of both active fighters, P1 ki, P1 action, live P1 effects
func _cheat_debug(core) -> void:
	print("CHT f%d bgm mode %d id %d" % [game.frames, core.r16(0x020DE2A0 + 0xA0) & 1, core.r32(0x020DE2A0 + 0xA8)])
	print("CHT f%d cursor %d select %d %d %d party p1 %d %d %d p2 %d %d %d" % [game.frames, core.r8(0x020DEA0F), core.r32(0x020DE64C), core.r32(0x020DE650),
		core.r32(0x020DE654), core.r32(0x020DD524), core.r32(0x020DD528), core.r32(0x020DD52C), core.r32(0x020DD530),
		core.r32(0x020DD534), core.r32(0x020DD538)])
	var teams: int = core.r32(0x020DE3D0)
	if teams < 0x02000000 or teams >= 0x02400000:
		return
	var p1: int = teams + core.r8(teams + 0x8C8) * 0x2D8
	var t2: int = teams + 0x8E8
	var p2: int = t2 + core.r8(t2 + 0x8C8) * 0x2D8
	var pool: int = core.r32(0x020DE3CC)
	var objs := 0
	var blasts := 0
	if pool >= 0x02000000 and pool < 0x02400000:
		for i in 48:
			var o := pool + i * 0x164
			if core.r8(o + 4) == 1 and core.r8(o + 0x1A) == 0:
				objs += 1
				var h: int = core.r32(core.r32(o + 0x40) + core.r8(o + 6) * 8)
				if h == 0x020209E0 and core.r32(o) == p1:
					blasts += 1
	if game.frames % 200 == 0:
		print("CHT chunks p1 %x p2 %x scene %x" % [core.r32(p1 + 0x44), core.r32(p2 + 0x44), core.r32(0x020DE374)])
	if core is QoLGame:
		print("CHT f%d assist slot %x clones %d assists left %d" % [game.frames, core.r32(teams + 0x11E0), core._clones.size(), core.r8(teams + 0x8CA)])
	print("CHT f%d p1 %d/%d/%d hp %d/%d ki %d act %x | p2 %d hp %d/%d act %x | p1 objs %d blasts %d" % [game.frames,
		core.r8(teams + 5), core.r8(teams + 0x2D8 + 5), core.r8(teams + 0x5B0 + 5), core.r16(p1 + 0x24A), core.r16(p1 + 0x24C), core.r16(teams + 0x8D0), core.r8(p1 + 6),
		core.r8(p2 + 5), core.r16(p2 + 0x24A), core.r16(p2 + 0x24C), core.r8(p2 + 6), objs, blasts])


# ------------------------------------------------------------------------------------------------ boss characters
const SEL_FREE := 0x0206D61C        ## Free Battle character select (scene VBlank callback)
const SEL_TEAM := 0x02065E60        ## Z-Battle / Maximum team select
var _sel_scene := 0
var _sel_ids: Array = []
var _sel_boss: Array = []


## every frame: which select slots hold a boss pick (QoLGame notes a pick made with L held), the game's boss
## teams for the battle loader, and the skull markers
func _boss_frame(core) -> void:
	if not core is QoLGame:
		return
	var g: QoLGame = core
	var scene: int = core.r32(MS_VBLANK_CB)
	var pts := []
	if scene == SEL_FREE or scene == SEL_TEAM:
		g.battle_loaded = false
		var base := 0x020DE658 if scene == SEL_FREE else 0x020DE64C
		var n := 6 if scene == SEL_FREE else 3
		if scene != _sel_scene:
			_sel_scene = scene
			_sel_ids = []
			_sel_boss = []
			for k in n:
				_sel_ids.append(-1)
				_sel_boss.append(false)
		for k in n:
			var id: int = core.r32(base + k * 4)
			if id >= 0x80000000:
				id -= 0x100000000
			if id != _sel_ids[k]:
				var side := 0 if k < 3 else 1
				_sel_boss[k] = id >= 0 and id == g.boss_pending and side == g.boss_pending_side
				if _sel_boss[k]:
					g.boss_pending = -1
				_sel_ids[k] = id
		for side in (2 if n == 6 else 1):
			var team := []
			var boss := []
			for k in range(side * 3, side * 3 + 3):
				if _sel_ids[k] >= 0 and _sel_ids[k] < 38:
					team.append(_sel_ids[k])
					if _sel_boss[k]:
						boss.append(_sel_ids[k])
			team.sort()
			g.boss_teams[side] = {"team": team, "boss": boss}
			for k in range(side * 3, side * 3 + 3):
				if _sel_boss[k] and settings.cheat("boss_characters"):
					if scene == SEL_FREE:
						pts.append(Vector2(5, 45 + 40 * k) if side == 0 else Vector2(180, 37 + 40 * (k - 3)))
					else:
						pts.append(Vector2(10 + 80 * k, 10))
	else:
		_sel_scene = 0
		if scene != 0:
			g.battle_loaded = false
		elif g.battle_loaded:
			for b in g.battle_bosses:
				var f: int = b[0]
				if mp_panel != null and mp_panel.shown:   # part 27: MP battle: on the MP panel's box of that fighter
					var at := mp_panel.mark_at(f, core.r8(f + 0x1A))
					if at.x >= 0:
						pts.append(at)
				elif lan_panel != null and lan_panel.shown:   # part 30: the LAN guest's panel shows side 1
					var at2 := lan_panel.mark_at(f)
					if at2.x >= 0:
						pts.append(at2)
				elif core.r8(f + 0x1A) == 0:   # P1's panels are on the lower screen
					pts.append(Vector2(core.r16(f + 0x2D0) + 2, 192 + 10))
	markers.show_at(pts)


# ---- MULTIPLAYER MENU (part 27) -----------------------------------------------------------------------------------
## LOCAL MULTIPLAYER input and menus (docs/MULTIPLAYER_DESIGN.md 3.2-3.4). During a session (mp.active) GameDS takes
## PLAYER 1's buttons from mp_poll_p1() (its own device / mapping, not the ds_* input map) and passes every frame's
## input through mp_frame(): both players' words go to QoLMp, the setup page gets both players' presses, and the DS
## sees what the session stage allows. Outside a session nothing here runs (one test per frame).
const MP_VS_SCENE := 0x11                ## VS BATTLE menu (FUN_0207BA08); state u8 0x020DD4C5, 2 = HOST / CLIENT choice
const MP_VS_WORK := 0x020E1148           ## u32 -> its work block; +0x1066 u16 cursor (0 left, 1 right)
var _mp_layers := false
var _mp_prev_any := false


## PLAYER 1's buttons held now (DS layout word incl. X 0x400 / Y 0x800) from its own device
func mp_poll_p1() -> int:
	return mp_input.poll(0, game.frames + 1)


## raw events (GameDS._input): short presses of each player's device are latched for the next game frame
func mp_latch(event: InputEvent) -> void:
	if mp.active:
		mp_input.latch(event)


## one game frame of a session: [keys, ext, touch] for the DS. `keys` / `ext` = PLAYER 1 (own device + `inputs=`),
## `touch` = mouse or scripted tap (the gamepad cursors are added here, per player)
func mp_frame(keys: int, ext: int, touch: Vector2i) -> Array:
	var f: int = game.frames + 1
	var w0 := (~keys & 0x3FF) | (~ext & 0xC00)
	var s2 := mp_input.script2(f)
	var w1: int = mp_input.poll(1, f) | s2[0]
	if game.display.mirror_active():   # MIRROR MODE: PLAYER 2's LEFT / RIGHT swapped like PLAYER 1's (GameDS)
		w1 = (w1 & ~0x30) | ((w1 & 0x10) << 1) | ((w1 & 0x20) >> 1)
	var ws := [w0, w1]
	for p in 2:
		mp.pressed[p] = ws[p] & ~mp.held[p]
		mp.released[p] = mp.held[p] & ~ws[p]
		mp.held[p] = ws[p]
	mp.mtouch = touch
	mp.ptouch = s2[1]
	var any := touch
	for t in [mp.ctouch[0], mp.ctouch[1], mp.ptouch]:
		if any.x < 0:
			any = t
	var new_tap := any.x >= 0 and not _mp_prev_any
	_mp_prev_any = any.x >= 0
	_mp_sel_taps(touch)
	if Game.args.has("mpdbg") and (w0 | w1) != 0:
		print("MP f%d stage %d p1 %03x p2 %03x touch %s c1 %s c2 %s" % [f, mp.stage, w0, w1, touch, mp.ctouch[0], mp.ctouch[1]])
	if mp_menu.is_open():
		if mp_menu.waiting() and mp_input.uses_pad(mp_menu.map_p):   # debug fake pads (mppad=): their presses map too
			for e in mp_input.fake_presses(f):
				if e[0] == mp_input.dev[mp_menu.map_p] and mp_menu.waiting():
					mp_menu.finish_wait(e[1])
		mp_menu.frame_input(mp.pressed, mp.held, any if new_tap else Vector2i(-1, -1))
		if not mp.active:                # BACK ended the session: filter_input keeps the held keys / touch away
			return [keys, ext, touch]    # from the game until released (mp_setup_back)
		return [0x3FF, 0x2C00, Vector2i(-1, -1)]
	var dsw := 0
	var t := Vector2i(-1, -1)
	if not mp.stage in mp.port_stages:
		dsw = w0
		t = any
		if mp.stage == QoLMp.BATTLE:
			var st: int = machine.core.r8(0x020DD4C5)
			dsw |= w1 & QoLMp.START          # either player pauses
			if st == 9 or (st >= 0x0F and st <= 0x14):   # pause menu / battle end screens: either player navigates
				dsw |= w1
			if mp_panel != null:
				t = mp_panel.route(mp)
	dsw |= mp.inject
	mp.inject = 0
	return [0x3FF & ~(dsw & 0x3FF), 0x2C00 & ~(dsw & 0xC00), t]


## per player, where a new touch began this frame (character / stage select): mouse and scripted `inputs=` taps belong
## to the keyboard player (PLAYER 1 when both or neither use the keyboard), a gamepad cursor to its player,
## `p2inputs=` taps to PLAYER 2
var _mp_src_prev := [false, false, false, false]
func _mp_sel_taps(touch: Vector2i) -> void:
	var kb := QoLMpInput.KEYBOARD
	mp.mouse_p = 1 if mp_input.dev[0] != kb and mp_input.dev[1] == kb else 0
	var src := [[mp.mouse_p, touch], [0, mp.ctouch[0]], [1, mp.ctouch[1]], [1, mp.ptouch]]
	mp.sel_tap = [Vector2i(-1, -1), Vector2i(-1, -1)]
	for i in src.size():
		var t: Vector2i = src[i][1]
		var down := t.x >= 0
		if down and not _mp_src_prev[i] and mp.sel_tap[src[i][0]].x < 0:
			mp.sel_tap[src[i][0]] = t
		_mp_src_prev[i] = down


## setup page BACK / B: the session ends, the VS menu's LOCAL / LAN screen is back with the normal controls
func mp_setup_back() -> void:
	_mp_end()
	_block_keys = 0x3FF                  # keys still held (B) stay away from the game until released
	_block_touch = true


## "READY TO CONTINUE?" YES: QoLGame.f_0207b778 leaves the scene (CLIENT path) -> redirected to character select
func mp_setup_go() -> void:
	settings.save_file()
	mp.go = true


func _mp_end() -> void:
	mp.stop()
	mp_menu.close()
	settings.save_file()


## after every game frame: VS menu choices, session stage by scene, overlay / setup page, layers, fades
func _mp_after(core) -> void:
	if not mp.active and not settings.multiplayer and not mp_menu.visible and mp.menu_req == 0:
		return
	var sc: int = core.r8(0x020DD4C4)
	var st: int = core.r8(0x020DD4C5)
	if mp.active and mp.reopen_setup and sc == MP_VS_SCENE and st >= 2 and not mp_menu.is_open():
		# part 27 phase 7: back from the character select, the page opens with the screen's first frame of state 2 and
		# fades in with it (not after the fade, over the LOCAL / LAN screen); states 0-1 (loading: VRAM and the
		# screen swap not set up yet) show the plain black of the scene's fade
		mp_menu.open_setup()
		_mp_prev_any = true
	if mp.menu_req != 0:
		var q := mp.menu_req
		mp.menu_req = 0
		if q == 1:                       # LOCAL: a session starts (or goes on, back from the character select)
			if not mp.active:
				mp.start()
				mp_input.refresh_defaults()
				mp_input.resolve_defaults()
			mp.stage = QoLMp.SETUP
			if not mp_menu.is_open():
				mp_menu.open_setup()
			_mp_prev_any = true          # a touch still held from the LOCAL tap is not a tap on the page
		else:
			lan_menu_open()              # part 30: LAN -> the LAN pages (HOST / JOIN)
	if mp.active and not mp.debug_battle:
		match sc:
			3: mp.stage = QoLMp.SELECT
			5: mp.stage = QoLMp.STAGE
			0: mp.stage = QoLMp.BATTLE
			6: _mp_end()                 # back on Mode Select: the normal controls again
	if mp_menu.is_open() and sc != MP_VS_SCENE:
		mp_menu.close()
	var vs: bool = settings.multiplayer and sc == MP_VS_SCENE and st >= 2 and st <= 8 and not mp_menu.is_open() \
		and not lan_menu.is_open()       # part 30: no LOCAL / LAN labels under the LAN pages
	var vc := 0
	if vs:
		var w: int = core.r32(MP_VS_WORK)
		if w >= 0x02000000 and w < 0x02400000:
			vc = 1 if core.r16(w + 0x1066) == 1 else 0
	mp_menu.set_vs(vs, vc)
	mp_menu.tick()
	var keep: bool = mp_menu.is_open() and sc == MP_VS_SCENE
	if keep != _mp_layers:
		_mp_layers = keep
		game.display.set_layer_keep(true, _keep_mask())   # only BG1 (hexagons) behind the page (part 31: any page)
	if mp_menu.visible:
		var swap: bool = (core.IO.decode_u16(0x304) & 0x8000) != 0
		mp_menu.set_brightness(_mp_bright(core, 0x1000 if swap else 0), _mp_bright(core, 0 if swap else 0x1000))
	if Game.args.has("mpdbg") and game.frames % 10 == 0:
		print("MP f%d active %s stage %d scene %02x state %d page %s vs %s dev %s go %s mode %d" % [game.frames, mp.active, mp.stage,
			sc, st, mp_menu.page, vs, mp_input.dev, mp.go, core.r32(0x020DD514)])


## the game's fade of one engine (IO base 0 = A, 0x1000 = B) as a factor: MASTER_BRIGHT down, or the colour-effect
## brightness decrease (BLDCNT mode 3, BLDY) the scene fades use; fades to white are left as they are
static func _mp_bright(core, base: int) -> float:
	var b := 1.0
	var v: int = core.IO.decode_u16(base + 0x6C)
	if ((v >> 14) & 3) == 2:
		b = 1.0 - minf(float(v & 0x1F), 16.0) / 16.0
	var bc: int = core.IO.decode_u16(base + 0x50)
	if ((bc >> 6) & 3) == 3 and (bc & 0x3F) != 0:
		b = minf(b, 1.0 - minf(float(core.IO[base + 0x54] & 0x1F), 16.0) / 16.0)
	return b


# ---- LAN CORE (part 30) ---------------------------------------------------------------------------------------------
## docs/LAN_DESIGN.md 2 / 5: QoLLan (scripts/qol/qol_lan.gd) is polled from GameDS._process; during a LAN battle GameDS
## asks lan_lockstep() / lan.can_step() before every game frame and passes the local input through lan_frame().

## a LAN battle's frames wait for the other machine (GameDS gate)
func lan_lockstep() -> bool:
	return lan.lockstep


## every Godot frame (GameDS._process, game thread parked): network, timers, AUTO PAUSE off while a session runs
func lan_poll() -> void:
	if lan.state == QoLLan.IDLE and lan.net.con == null and not lan.net.closing():
		return
	lan.poll()
	if lan.lockstep or lan.aborting:
		lan_panel.update_bands()         # part 30 phase 3: WAITING FOR PLAYER while no game frame runs
	if paused:
		_update_pause()


## GameDS._tick_begin, after filter_input / MIRROR: [keys, ext, touch] the DS sees (lockstep: from both records)
func lan_frame(keys: int, ext: int, touch: Vector2i) -> Array:
	return lan.frame(keys, ext, touch)


## the host's snapshot was applied / removed on this machine (QoLSettings.begin_override / end_override): what the
## menu does when such a value changes (RANDOM MUSIC shuffle, picture effects / CRT, the tile's text)
func apply_session_settings() -> void:
	if machine.core is QoLGame:
		machine.core.shuffle_music(settings.music_seed, sound.seq_size)
	apply_display()
	_update_top()


# ---- LAN MENU (part 30) ---------------------------------------------------------------------------------------------
## docs/LAN_DESIGN.md 6: the LAN pages (QoLLanMenu, scripts/qol/qol_lan_menu.gd) over the VS BATTLE screen (scene 0x11):
## opened by LAN on the LOCAL / LAN screen (QoLGame.f_0207b778 -> mp.menu_req 2 -> _mp_after). While a page is open the
## DS sees no input (filter_input -> _lan_input); typing arrives through raw_input -> lan_menu.key_event. Nothing runs
## without an open page or a session (after_step: one test).
var lan_menu: QoLLanMenu
var _lan_layers := false


func lan_menu_open() -> void:
	lan_menu.open_lan()


## LAN page BACK / B: the LOCAL / LAN screen again; buttons / touch still held stay away from the game until released
func lan_menu_back() -> void:
	lan_menu.close()
	_block_keys = 0x3FF
	_block_touch = true
	_lan_layers = false                  # part 31: the game's own layers again at once (was left on: LAN exit bug)
	game.display.set_layer_keep(true, _keep_mask())


## part 31: the lower-screen layer keep (only BG1, the hexagons) belongs to whichever port page is open: the settings
## menu (_layers_hidden), the LOCAL setup page (_mp_layers) or the LAN pages (_lan_layers). Before, _lan_after (which
## turns the keep off) ran only while a LAN page was open or a session ran, so BACK / B on the LAN page left it on:
## the LOCAL / LAN screen and Mode Select showed only their background (DATA_NOTES part 31).
func _keep_mask() -> int:
	return 0x200 if _layers_hidden or _mp_layers or _lan_layers else 0x1F00


## safety net every frame: with no port page open every layer of both engines is drawn (one test when all is well)
func _layers_guard() -> void:
	if _layers_hidden or _mp_layers or _lan_layers:
		return
	var k: Array = game.display._layer_keep
	if k[0] != 0x1F00 or k[1] != 0x1F00:
		game.display.set_layer_keep(true, 0x1F00)


func _lan_input(newly: int, down: int, touch: Vector2i, new_touch: bool) -> Array:
	lan_menu.frame_input(newly, down, touch if new_touch else Vector2i(-1, -1))
	_block_keys |= down                  # still held when the pages close: kept from the game until released
	_block_touch = _block_touch or touch.x >= 0
	return [0x3FF, 0x2C00, Vector2i(-1, -1)]


## after every game frame while a page is open or a session runs: pages by scene, network events, layers, fades
func _lan_after(core) -> void:
	var sc: int = core.r8(0x020DD4C4)
	var st: int = core.r8(0x020DD4C5)
	if lan_menu.is_open() and sc != MP_VS_SCENE:
		lan_menu.close()                 # (accepted: the scene changes to the character select, phase 3)
	elif not lan_menu.is_open() and sc == MP_VS_SCENE and st >= 2 and st <= 8 and lan.state in [QoLLan.HOSTING, QoLLan.LOBBY]:
		lan_menu.open_lobby()            # a session on the VS screen (back from the select, `lan=` debug start): the lobby
	elif not lan_menu.is_open() and sc == MP_VS_SCENE and st >= 2 and st <= 8 and lan.state == QoLLan.IDLE and not lan.notice.is_empty():
		while not lan.pop_event().is_empty():   # (old events of the ended session: the notice says it)
			pass
		lan_menu.open_lan()              # part 30 phase 3: the session ended away from the room (host left / lost): LAN page
	if lan_menu.is_open() and not lan.notice.is_empty() and sc == MP_VS_SCENE:
		lan_menu.show_notice(lan.notice) # part 30 phase 3: why this machine is back (other player left, lost, desync)
		lan.notice = {}
	lan_menu.tick()
	var keep: bool = lan_menu.is_open()
	if keep != _lan_layers:
		_lan_layers = keep
		game.display.set_layer_keep(true, _keep_mask())   # only BG1 (hexagons) behind the pages
	if lan_menu.visible:
		var swap: bool = (core.IO.decode_u16(0x304) & 0x8000) != 0
		lan_menu.set_brightness(_mp_bright(core, 0x1000 if swap else 0), _mp_bright(core, 0 if swap else 0x1000))


# ---- ALLSTAR (part 34) ----------------------------------------------------------------------------------------------
## NEW GAMEMODES phase 1 (docs/ALLSTAR_DESIGN.md 1.1 / 1.2): the GAMEMODE label on Mode Select's tile 5 and the Gamemode
## menu's bar labels (QoLAllStarMenu, texture rewrites), the upper-screen texts (Mode Select tile 5: `top`; Gamemode
## menu: `as_top`, a QoLTopInfo at the course select's full brightness over its header / box, faded with the game).
## Game-side flow / routing: QoLGame `# ---- ALLSTAR MENU (part 34)`.
var as_menu: QoLAllStarMenu
var as_top: QoLTopInfo
var _top_gm := false                 ## the Mode Select box shows the GAMEMODE text (tile 5)
const AS_TEXTS := [
	["ALL-STAR", "Fight all 26 characters, one after\nanother in story order, in one long\nbattle in the Time Chamber. Lose\nand you start over from the\ncharacter select!"],
	["ENDLESS", "Random enemies, one after\nanother, with no end, in the\nTime Chamber. How many can you\nbeat? When your team is out,\nyour run goes on the records!"],   # part 38
	["EMPTY", "Nothing here yet:\nmore game modes may come in a\nlater version of the port."],
]
const AS_TILE_TEXT := ["GAMEMODE", "New game modes made for the\nport: ALL-STAR (the whole cast\nin a row), ENDLESS (random\nenemies with no end) and more\nto come."]


func _as_setup(g) -> void:
	as_menu = QoLAllStarMenu.new()
	as_top = QoLTopInfo.new()
	as_top.font = font
	as_top.full = true
	g.screen_root.add_child(as_top)


func _as_after(core) -> void:
	var on := settings.new_gamemodes
	as_menu.tile_frame(core, on)
	# (also while Mode Select fades in / out with the cursor there: the game's own FREE BATTLE text would show)
	var gm_tile: bool = on and core.r32(MS_VBLANK_CB) == MS_VBLANK_FN and core.r8(MS_CURSOR) == 5 and not menu.visible \
		and lan.state == QoLLan.IDLE
	if gm_tile:
		top.show_text(AS_TILE_TEXT[0], AS_TILE_TEXT[1])
		top.visible = true
		var swap: bool = (core.IO.decode_u16(0x304) & 0x8000) != 0
		var bu := _mp_bright(core, 0 if swap else 0x1000)
		if top.modulate.r != bu:
			top.modulate = Color(bu, bu, bu)
	elif _top_gm:
		top.modulate = Color.WHITE
		_update_top()
	_top_gm = gm_tile
	var menu_on: bool = on and allstar.stage == QoLAllStar.MENU and core.r8(0x020DD4C4) == 0xB
	as_menu.bars_frame(core, menu_on)
	var st: int = core.r8(0x020DE554) if menu_on else 0
	var show := menu_on and st >= 5 and st <= 9
	if show:
		var t: Array = AS_TEXTS[mini(allstar.menu_cursor, 2)]
		as_top.show_text(t[0], t[1])
		var swap: bool = (core.IO.decode_u16(0x304) & 0x8000) != 0
		var bu := _mp_bright(core, 0 if swap else 0x1000)
		if as_top.modulate.r != bu:
			as_top.modulate = Color(bu, bu, bu)
	if as_top.visible != show:
		as_top.visible = show
