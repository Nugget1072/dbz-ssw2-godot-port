extends Node
## Renders the QoL menu pages without running the game (fast look at layout changes):
##   godot --path . --rendering-driver opengl3 --resolution 256x384 res://tools/qol_preview.tscn -- \
##     rom=PATH bg=BOTTOM.png top=TOP.png out=DIR
## bg / top: captures to draw behind (e.g. a Mode Select capture with only BG1 shown: `layersweep=` in GameDS).
## Writes DIR/<state>.png for a list of menu states (cursor positions, pages).

class Stub:
	var settings := QoLSettings.new()
	var sound := QoLSound.new()
	var controls: QoLControls:
		get: return settings.controls
	func apply_controls() -> void: pass
	func se(_id: int) -> void: pass
	func apply_window() -> void: pass
	func apply_display() -> void: pass
	func on_game_thread(c: Callable) -> void: pass
	# part 27 LOCAL MULTIPLAYER menu (QoLMpMenu)
	var mp := QoLMp.new()
	var mp_input: QoLMpInput:
		get: return settings.mp_input
	func mp_setup_back() -> void: pass
	func mp_setup_go() -> void: pass
	# part 30 LAN menus (QoLLanMenu): `lan` = a LanStub in the `lan` states (the real QoLLan is QoLController.lan)
	var lan = null
	func lan_menu_back() -> void: pass


## part 30: a stand-in for QoLLan (phase 1's session) with the API the LAN pages use; events are queued by the states
class LanStub:
	var state := "IDLE"
	var role := ""
	var my_name := ""
	var peer_name := ""
	var ping_ms := -1
	var port := 8082
	var events: Array = []
	var log: Array = []
	func state_name() -> String: return state
	func local_addresses() -> PackedStringArray: return PackedStringArray(["192.168.1.5", "10.0.0.17"])
	func host(n: String, p: int = 8082) -> bool:
		log.append("host %s %d" % [n, p]); my_name = n; role = "host"; state = "HOSTING"; port = p; return true
	func join(n: String, ip: String, p: int = 8082) -> void:
		log.append("join %s %s %d" % [n, ip, p]); my_name = n; role = "guest"; state = "CONNECTING"
	func leave() -> void:
		log.append("leave"); state = "IDLE"; role = ""; peer_name = ""; ping_ms = -1
	func propose_select() -> void: log.append("propose")
	func accept_select() -> void: log.append("accept"); state = "SELECT"
	func deny_select() -> void: log.append("deny")
	func poll() -> void: pass
	func pop_event() -> Dictionary: return {} if events.is_empty() else events.pop_front()

var _frames := 0
var _menu: QoLMenu
var _top: QoLTopInfo
var _fps: QoLFpsCounter
var _cur: QoLCursor
var _mpm: QoLMpMenu                            ## part 27: `mp` -> only the LOCAL MULTIPLAYER menu states
var _lm: QoLLanMenu                            ## part 30: `lan` -> only the LAN menu states
var _cur2: Array = []
var _states := []
var _i := -1
var _out := ""


func _ready() -> void:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else ""
	_out = a.get("out", "/tmp/qolprev")
	DirAccess.make_dir_recursive_absolute(_out)
	var rom := FileAccess.get_file_as_bytes(a.get("rom", ""))
	var font := QoLFont.new(rom)
	print("font from rom: ", font.from_rom)
	var root2 := Node2D.new()
	add_child(root2)
	for k in ["top", "bg"]:
		if a.has(k):
			var img := Image.load_from_file(a[k])
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(img)
			tr.position = Vector2(0, 0)
			root2.add_child(tr)
	var stub := Stub.new()
	stub.sound.ok = true
	for n in ["OP", "BGM 01", "BGM 02", "BOSS 1", "END 3"]:
		stub.sound.tracks.append({"kind": "strm" if n != "END 3" else "seq", "id": 0, "name": n})
	_top = QoLTopInfo.new()
	_top.font = font
	_top.visible = true
	root2.add_child(_top)
	_menu = QoLMenu.new()
	_menu.qol = stub
	_menu.font = font
	root2.add_child(_menu)
	_fps = QoLFpsCounter.new()
	_fps.font = font
	_fps.visible = true
	root2.add_child(_fps)
	_cur = QoLCursor.new()                     # the gamepad cursor (part 24), shown in the cursor_* states
	root2.add_child(_cur)
	if a.has("mp"):
		_mp_states(stub, root2, font)
		return
	if a.has("lan"):
		_lan_states(stub, root2, font)
		return
	if a.has("asrec"):
		_asrec_states(rom, root2, font)
		return
	_menu.focus_changed.connect(func(): _top.show_text(_menu.focus_title(), _menu.focus_desc()) if _menu.visible else _top.show_text("SETTINGS", "Change the game's settings."))
	_states = [
		["tile", func(): _menu.visible = false; _top.show_text("SETTINGS", "Change the game's settings.")],
		["main", func(): _menu.open()],
		["main_fps", func(): _press(128)],                    # down: frame rate row
		["main_exit", func(): _menu.open(); _press(64); _press(16)],   # up (wraps to the last row) + right: EXIT
		["main_pressed", func(): _menu.open(); _press(128); _press(16); _press(1)],   # 120 fps chosen
		["confirm", func(): _menu.open(); _press(32); _press(1)],   # window 1X -> confirm page
		["jukebox", func(): _menu.page = "main"; _menu.open(); _press(64); _press(1)],
		["jukebox_play", func(): stub.sound.jb_playing = true; stub.sound.jb_index = 1; _press(16); _press(16)],
		["jukebox_back", func(): _press(128)],
		["header", func(): _menu.page = "main"; _menu.open(); _press(64); _press(16)],     # up: header, right
		["cheats", func(): _menu.open(); _press(256); _press(256); _press(256); _press(256)],                     # R R: page 3
		["cheats_on", func(): _press(128); _press(32); _press(1); _press(128); _press(128); _press(32); _press(1)],
		["cheats_header", func(): _press(64); _press(64); _press(64); _press(64)],
		["back_to_1", func(): _press(512); _press(512)],                                # L L: page 1
		["page3", func(): _menu.open(); _press(512); _press(512)],                                     # L from page 1: page 3
		["page3_on", func(): _press(128); _press(32); _press(1)],
		["bosslist", func(): _press(64); _press(32); _press(32)],
		["assist", func(): _press(128); _press(128); _press(128)],
		["music", func(): _press(128)],
		["shuffle", func(): _press(128)],
		["cheats3", func(): _menu.open(); _press(512); _press(512)],
		["main3", func(): _menu.open(); _press(256); _press(256)],
		["mpset", func(): _menu.open(); _press(256); _press(256); _press(256)],                       # R R: settings 3
		["main3_on", func(): _press(128); _press(32); _press(1)],
		["weird", func(): _menu.open(); _press(512); _press(512); _press(512)],
		["weird3", func(): _menu.open(); _press(512)],
		["weird3_on", func(): _press(128); _press(32); _press(1); _press(128); _press(128)],
		["weird2", func(): _menu.open(); _press(512); _press(512)],
		["challenges", func(): _menu.open(); for i in 4: _press(512)],                        # part 36: L x4 = page 9 CHALLENGES
		["challenges_on", func(): _press(32); _press(1)],                                  # (cursor stays on row 1) ON pressed
		["challenges_hdr", func(): _press(64)],                                            # up: the header (page help)
		# part 39: the four new cheats (page 5 row 6, page 7 row 6, page 9 rows 3-4)
		["p39_fighting", func(): _menu.open(); _presses(256, 4); _presses(128, 5)],
		["p39_fighting_on", func(): _press(32); _press(1)],
		["p39_characters", func(): _menu.open(); _presses(256, 6); _presses(128, 5)],
		["p39_challenges", func(): _menu.open(); _presses(512, 4); _presses(128, 2)],   # (part 42: CHALLENGES = page 10 = 4 x L)
		["p39_challenges_kb", func(): _press(128); _press(32); _press(1)],
		# part 40: RICOCHET KI (page 6 row 4), HOT POTATO (page 9 row 5)
		["p40_ki", func(): _menu.open(); _presses(256, 5); _presses(128, 3)],
		["p40_potato", func(): _menu.open(); _presses(512, 4); _presses(128, 4)],
		# part 41: POWERS (page 10: ULTRA INSTINCT, VAMPIRE, TIME SKIP), DRAGON BALL HUNT (page 9 row 6)
		["p41_powers", func(): _menu.open(); _presses(512, 5); _presses(128, 2)],   # (part 42: POWERS = page 9)
		["p41_timeskip", func(): _press(128)],
		["p41_timeskip_on", func(): _press(32); _press(1)],
		["p41_db", func(): _menu.open(); _presses(512, 4); _presses(128, 5)],
		["p41_db_on", func(): _press(32); _press(1)],
		["p41_weird1", func(): _menu.open(); _presses(512, 3)],
		["p41_help", func(): _menu.open(); _press(64)],
		# part 42: NONDIRECTIONAL (page 5 row 6), POWERS page 9 (Z-VANISH row 3, BODY CHANGE row 5), CHALLENGES page 10
		["p42_fighting", func(): _menu.open(); _presses(256, 4); _presses(128, 5)],
		["p42_zvanish", func(): _menu.open(); _presses(512, 5); _presses(128, 2)],
		["p42_bodychange", func(): _presses(128, 2)],
		["p42_bodychange_on", func(): _press(32); _press(1)],
		["p42_challenges", func(): _menu.open(); _presses(512, 4)],
		["p42_ctrl_a", func(): _menu.open(); _press(256); _press(1); _press(128)],   # CONTROLS: the A row (help text)
		["p42_ctrl_b", func(): _press(128)],
		["p42_ctrl_sel", func(): _menu.open(); _press(256); _press(1); _press(256)],   # CONTROLS 2: SELECT
		["p40_potato_on", func(): _press(32); _press(1)],
		["weird_on", func(): _press(128); _press(32); _press(1); _press(128); _press(128)],                                    # L from page 1: CHEATS 3
		["cheats3_on", func(): _press(128); _press(32); _press(1); _press(128); _press(128); _press(128); _press(128)],
		["cheats3_header", func(): _press(128); _press(64); _press(64); _press(64); _press(64); _press(64); _press(64)],
		["page2", func(): _menu.open(); _press(256)],                                       # R from page 1: settings 2
		["page2_vol", func(): _press(128); _press(16); _press(1)],                         # VOLUME 25 chosen
		["page2_pause", func(): _press(128); _press(1)],
		["page2_hs", func(): _menu.open(); _press(256); for i in 5: _press(128)],          # HI-SCORES row
		["lbconfirm", func(): _press(1)],                                                  # RESET -> are you sure (NO first)
		["lbconfirm_yes", func(): _press(32)],                                             # cursor on YES
		["lbconfirm_no", func(): _press(2)],                                               # B = NO: back on HI-SCORES
		["weird_p1", func(): _menu.open(); _press(512); _press(512); _press(512); _press(64)],          # page 7, last row
		["weird_p2", func(): _menu.open(); _press(512); _press(512); _press(64)],                       # page 8, last row
		["controls1", func(): _menu.open(); _press(256); _press(1)],                       # CONTROLS - SET
		["controls1_y", func(): _press(128); _press(128); _press(128)],                    # Y row, KEY box
		["controls1_wait", func(): _press(1)],                                             # waiting for a key
		["controls1_mapped", func(): _menu.finish_wait("k:%d" % KEY_SPACE)],               # Space for Y
		["controls1_pad", func(): _menu.frame_input(0, 0, Vector2i(-1, -1)); _press(16)],
		["controls1_swap", func(): _press(1); _menu.finish_wait("b:9")],                  # LB (was L's) for Y
		["controls2", func(): _menu.frame_input(0, 0, Vector2i(-1, -1)); _press(256)],
		["controls2_default", func(): _press(128); _press(128); _press(128); _press(128); _press(128)],
		["controls2_after", func(): _press(1)],
		["controls_header", func(): _press(64); _press(64); _press(64); _press(64); _press(64); _press(64); _press(16); _press(16)],
		["controls_back", func(): _press(2)],
		# CONTROLS page 3: the gamepad mouse cursor (part 24)
		["controls3", func(): stub.controls.reset(); _menu.open(); _press(256); _press(1); _press(512)],   # L from CONTROLS 1
		["controls3_click", func(): _press(128); _press(128); _press(128); _press(128)],     # CLICK row, KEY box
		["controls3_wait", func(): _press(1)],                                              # waiting for a key
		["controls3_mapped", func(): _menu.finish_wait("k:%d" % KEY_X)],                   # X (A's key): A has none now
		["controls3_pad", func(): _menu.frame_input(0, 0, Vector2i(-1, -1)); _press(16); _press(1); _menu.finish_wait("b:1")],   # pad B (A's): swap
		["controls3_on", func(): _menu.frame_input(0, 0, Vector2i(-1, -1)); _press(128)],   # CURSOR ON/OFF row
		["controls3_off", func(): _press(16); _press(1)],
		["controls3_speed", func(): _press(128)],                                           # SPEED row (value 3)
		["controls3_speed5", func(): _press(16); _press(16); _press(1)],
		["controls3_header", func(): for i in 7: _press(64)],
		["controls3_up", func(): _press(128)],                                              # CURSOR UP row
		["controls2_from3", func(): _press(512); for i in 5: _press(128)],                  # L: page 2, DEFAULT row
		["controls2_reset", func(): _press(1)],
		["controls3_reset", func(): _press(256); _press(64)],                               # R: page 3 again, SPEED row
		["cursor_menu", func(): _cur.pos = Vector2(170, 100); _cur.force = true; _cur.queue_redraw()],
		["cursor_pressed", func(): _cur.pressed = true; _cur.queue_redraw()],
		["cursor_edge", func(): _cur.pressed = false; _cur.pos = Vector2(255, 191); _cur.queue_redraw()],
		["cursor_off", func(): _cur.force = false],

	]


## part 27: the VS menu overlay and the controller setup pages (args: mp [fakepads=N])
func _mp_states(stub, root2: Node, font: QoLFont) -> void:
	_menu.visible = false
	_mpm = QoLMpMenu.new()
	_mpm.qol = stub
	_mpm.font = font
	root2.add_child(_mpm)
	for p in 2:
		var c := QoLCursor.new()
		c.set_player(p)
		c.pos = Vector2(70 + p * 110, 120)
		c.force = false
		root2.add_child(c)
		_cur2.append(c)
	var mi: QoLMpInput = stub.mp_input
	mi.dev = [QoLMpInput.KEYBOARD, 0]
	var P := func(b: int): _mpm.frame_input([b, 0], [b, 0], Vector2i(-1, -1)); _mpm.frame_input([0, 0], [0, 0], Vector2i(-1, -1))
	var P2 := func(b: int): _mpm.frame_input([0, b], [0, b], Vector2i(-1, -1)); _mpm.frame_input([0, 0], [0, 0], Vector2i(-1, -1))
	_states = [
		["mp_vs_local", func(): _mpm.set_vs(true, 0)],
		["mp_vs_lan", func(): _mpm.set_vs(true, 1)],
		["mp_vs_lan_notice", func(): _mpm.lan_notice()],
		["mp_setup", func(): _mpm.set_vs(false, 0); _mpm.open_setup(); _mpm._ignore = 0],
		["mp_setup_cursors", func(): _cur2[0].force = true; _cur2[1].force = true],
		["mp_setup_cursors_pressed", func(): _cur2[0].pressed = true; _cur2[1].pressed = true; _cur2[0].queue_redraw(); _cur2[1].queue_redraw()],
		["mp_setup_p2dev", func(): _cur2[0].force = false; _cur2[1].force = false; P2.call(QoLMp.DOWN); P2.call(QoLMp.DOWN)],
		["mp_setup_nc", func(): mi.dev[1] = 5],                                        # a pad that is not connected
		["mp_setup_cycle", func(): mi.dev[1] = 0; P.call(QoLMp.UP); P.call(QoLMp.UP); P.call(QoLMp.RIGHT)],   # P1: PAD 1 (P2 swapped)
		["mp_drop", func(): P.call(QoLMp.A)],
		["mp_drop_down", func(): P.call(QoLMp.DOWN)],
		["mp_drop_pick", func(): P.call(QoLMp.A)],
		["mp_setup_back_kb", func(): mi.dev = [QoLMpInput.KEYBOARD, 0]; _mpm.open_setup(); _mpm._ignore = 0; P.call(QoLMp.UP)],
		["mp_setup_ctl", func(): P.call(QoLMp.DOWN); P.call(QoLMp.DOWN)],
		["mp_map_kb", func(): P.call(QoLMp.A)],
		["mp_map_kb_wait", func(): P.call(QoLMp.DOWN); P.call(QoLMp.RIGHT); P.call(QoLMp.A)],
		["mp_map_kb_mapped", func(): _mpm.finish_wait("k:%d" % KEY_SPACE)],
		["mp_map_default", func(): _mpm.frame_input([0, 0], [0, 0], Vector2i(-1, -1)); _mpm.row = 6; P.call(QoLMp.DOWN)],
		["mp_map_header", func(): P.call(QoLMp.DOWN)],
		["mp_map_p2pad", func(): _mpm.open_setup(); _mpm._ignore = 0; P.call(QoLMp.DOWN); P.call(QoLMp.DOWN); P.call(QoLMp.DOWN); P.call(QoLMp.A)],
		["mp_map_p2pad_wait", func(): P.call(QoLMp.A)],
		["mp_setup_ready", func(): _mpm.open_setup(); _mpm._ignore = 0; P.call(QoLMp.UP); P.call(QoLMp.UP)],
		["mp_ready", func(): P.call(QoLMp.A)],
		["mp_ready_yes", func(): P2.call(QoLMp.LEFT)],
		["mp_ready_no", func(): P.call(QoLMp.B)],
		["mp_tap_dev", func(): _mpm.frame_input([0, 0], [0, 0], Vector2i(240, 43))],    # tap on P2... P1 box's right arrow
		["mp_tap_drop", func(): _mpm.frame_input([0, 0], [0, 0], Vector2i(170, 97))],   # tap on P2's box middle: list
		["mp_tap_pick", func(): _mpm.frame_input([0, 0], [0, 0], Vector2i(100, 73))],   # tap the first entry
	]


## part 30: the LAN pages (args: lan qolcfg=SCRATCH.cfg — the name / IP are saved there)
func _lan_states(stub, root2: Node, font: QoLFont) -> void:
	_menu.visible = false
	_top.visible = false
	var l := LanStub.new()
	stub.lan = l
	_lm = QoLLanMenu.new()
	_lm.qol = stub
	_lm.font = font
	root2.add_child(_lm)
	_lm.position = Vector2(0, 192)
	var c := QoLCursor.new()
	c.pos = Vector2(150, 120)
	root2.add_child(c)
	var P := func(b: int): _lm.frame_input(0, 0, Vector2i(-1, -1)); _lm.frame_input(b, b, Vector2i(-1, -1)); _lm.frame_input(0, 0, Vector2i(-1, -1))
	var T := func(x: int, y: int): _lm.frame_input(0, 0, Vector2i(-1, -1)); _lm.frame_input(0, 0, Vector2i(x, y)); _lm.frame_input(0, 0, Vector2i(-1, -1))
	var K := func(code: int, uni: int = 0):
		var e := InputEventKey.new()
		e.keycode = code
		e.unicode = uni
		e.pressed = true
		_lm.key_event(e)
		var r := e.duplicate()
		r.pressed = false
		_lm.key_event(r)
		_lm.frame_input(0, 0, Vector2i(-1, -1))     # a game frame in between (keys released)
	var typ := func(t: String):
		for ch in t:
			K.call(KEY_A if ch == "a" else KEY_NONE, ch.unicode_at(0))
	var EV := func(e: Dictionary): l.events.append(e); _lm.tick()
	stub.settings.set("lan_name", "")
	stub.settings.set("lan_ip", "")
	_states = [
		["lan_page", func(): _lm.open_lan(); _lm._ignore = 0],
		["lan_join", func(): P.call(QoLMp.RIGHT)],
		["lan_back", func(): P.call(QoLMp.UP)],
		["lan_warn_host", func(): P.call(QoLMp.DOWN); P.call(QoLMp.LEFT); P.call(QoLMp.A)],
		["lan_warn_host_yes", func(): P.call(QoLMp.LEFT)],
		["lan_name_host", func(): P.call(QoLMp.A)],
		["lan_name_host_typed", func(): typ.call("Goku 1")],
		["lan_name_host_pad", func(): P.call(QoLMp.DOWN); P.call(QoLMp.RIGHT); P.call(QoLMp.RIGHT); P.call(QoLMp.A)],   # M typed by D-pad + A
		["lan_name_host_cursor", func(): c.force = true; c.pos = Vector2(116, 132); c.queue_redraw()],
		["lan_name_host_tapdel", func(): c.force = false; c.queue_redraw(); T.call(130, 182); T.call(130, 182)],      # DEL twice by taps
		["lan_name_host_full", func(): typ.call("GOKU_SSJ3XYZ")],                                                     # capped at 10
		["lan_sure_host", func(): K.call(KEY_ENTER)],
		["lan_lobby_host_wait", func(): P.call(QoLMp.A)],
		["lan_lobby_host_conn", func(): l.state = "LOBBY"; l.peer_name = "Vegeta"; l.ping_ms = 3; EV.call({"type": "peer_joined"})],
		["lan_lobby_host_asking", func(): P.call(QoLMp.START)],
		["lan_lobby_host_denied", func(): EV.call({"type": "proposal_denied"})],
		["lan_lobby_host_declined", func(): P.call(QoLMp.A)],
		["lan_lobby_host_ping", func(): l.ping_ms = 95; _lm.status = ""; _lm._update()],
		["lan_lobby_leave", func(): P.call(QoLMp.B)],
		["lan_lobby_peer_left", func(): P.call(QoLMp.B); l.state = "HOSTING"; EV.call({"type": "peer_left"}); l.peer_name = ""],
		["lan_lobby_host_again", func(): P.call(QoLMp.A)],
		["lan_lobby_leave_yes", func(): P.call(QoLMp.B); P.call(QoLMp.LEFT); P.call(QoLMp.A)],   # -> LAN page
		["lan_warn_join", func(): _lm._ignore = 0; P.call(QoLMp.RIGHT); P.call(QoLMp.A)],
		["lan_name_join", func(): P.call(QoLMp.LEFT); P.call(QoLMp.A)],
		["lan_name_join_ip", func(): typ.call("192.168.1.x")],                                       # the x is refused
		["lan_name_join_tab", func(): K.call(KEY_TAB)],                                               # TAB: NAME box
		["lan_name_join_tab2", func(): K.call(KEY_TAB)],                                              # TAB: IP box again
		["lan_name_join_badip", func(): K.call(KEY_ENTER)],
		["lan_name_join_fixed", func(): P.call(QoLMp.A); typ.call("23:8082")],
		["lan_sure_join", func(): P.call(QoLMp.START)],
		["lan_connecting", func(): P.call(QoLMp.A); _lm._frames = 240],
		["lan_unable", func(): _lm._frames = QoLLanMenu.CONNECT_FRAMES - 1; _lm.tick()],
		["lan_unable_back", func(): P.call(QoLMp.A)],
		["lan_reject_version", func(): P.call(QoLMp.START); P.call(QoLMp.A); EV.call({"type": "rejected", "reason": "VERSION"})],
		["lan_reject_rom", func(): P.call(QoLMp.A); P.call(QoLMp.START); P.call(QoLMp.A); EV.call({"type": "rejected", "reason": "ROM"})],
		["lan_reject_full", func(): P.call(QoLMp.A); P.call(QoLMp.START); P.call(QoLMp.A); EV.call({"type": "rejected", "reason": "FULL"})],
		["lan_lobby_guest", func(): P.call(QoLMp.A); P.call(QoLMp.START); P.call(QoLMp.A); l.state = "LOBBY"; l.peer_name = "Vegeta"; l.ping_ms = 41; EV.call({"type": "connected"})],
		["lan_proposal", func(): EV.call({"type": "proposal"})],
		["lan_proposal_deny", func(): P.call(QoLMp.RIGHT)],
		["lan_guest_declined", func(): P.call(QoLMp.A)],
		["lan_guest_accept", func(): EV.call({"type": "proposal"}); P.call(QoLMp.A)],
		["lan_guest_lost", func(): _lm.status = ""; l.state = "IDLE"; EV.call({"type": "lost"})],
		["lan_noname", func(): P.call(QoLMp.A); _lm._ignore = 0; P.call(QoLMp.A); P.call(QoLMp.LEFT); P.call(QoLMp.A); _lm.kb.fields[0]["text"] = ""; K.call(KEY_ENTER)],
		["lan_log", func(): print("LANSTUB log: ", l.log); print("LANSTUB cfg name=%s ip=%s" % [stub.settings.get("lan_name"), stub.settings.get("lan_ip")])],
	]


func _press(bit: int) -> void:
	_menu.frame_input(bit, bit, Vector2i(-1, -1))
	_menu.frame_input(0, 0, Vector2i(-1, -1))


func _presses(bit: int, n: int) -> void:
	for k in n:
		_press(bit)


func _process(_d: float) -> void:
	_frames += 1
	if _frames % 3 != 0:
		return
	if _i >= 0:
		get_viewport().get_texture().get_image().save_png(_out.path_join("%s.png" % _states[_i][0]))
	_i += 1
	if _i >= _states.size():
		get_tree().quit()
		return
	_states[_i][1].call()
	_menu.queue_redraw()


## part 35: the ALL-STAR records page (QoLAllStarRecords) in several table states (args: asrec [asdbg]); the page is
## shown in its "on" blink phase (`_off` states: the new row's flash / the cursor in the other half of the blink)
class AsStub:
	var allstar := QoLAllStar.new()
	var font: QoLFont
	var settings := QoLSettings.new()
	var _block_keys := 0
	var _block_touch := false
	func se(_id: int) -> void: pass


func _asrec_states(rom: PackedByteArray, root2: Node, font: QoLFont) -> void:
	_menu.visible = false
	_top.visible = false
	var st := AsStub.new()
	st.font = font
	var page := QoLAllStarRecords.new()
	page.setup(st, rom)
	root2.add_child(page)
	var E := func(m: int, s: int, h: int, ids: Array) -> Dictionary:
		return {"frames": int((m * 60 + s) * QoLAllStarRecords.FPS) + 1, "hearts": h, "ids": ids, "date": "2026-10-12T10:00:00"}
	var full := [E.call(8, 21, 0, [6, 7, 33]), E.call(9, 2, 1, [0]), E.call(12, 32, 2, [15, 25]), E.call(13, 55, 3, [20, 27]),
		E.call(16, 42, 1, [1, 2, 3])]
	X = func(b: int, m: int, s: int, h: int, ids: Array) -> Dictionary:
		var d: Dictionary = E.call(m, s, h, ids)
		d["beaten"] = b
		return d
	efull = [X.call(48, 30, 2, 1, [6, 7, 33]), X.call(31, 19, 45, 3, [0]), X.call(27, 14, 3, 0, [15, 25]),
		X.call(9, 4, 12, 2, [20, 27]), X.call(4, 1, 58, 0, [1, 2, 3])]
	var S := func(tab: Array, e: Dictionary, r: int, nt: String, t: int, p1: Array = []) -> void:
		page.table = tab
		page.entry = e
		page.new_rank = r
		page.note = nt
		st.allstar.p1_ids = p1 if not p1.is_empty() else e.ids
		page.show_page()
		page._phase = 1
		page._t = t
		page.queue_redraw()
	_states = [
		["as_empty_new", func():
			var e: Dictionary = E.call(12, 34, 1, [0, 5, 6])
			S.call([e], e, 0, "", 16)],
		["as_empty_new_off", func(): page._t = 24; page.queue_redraw()],
		["as_full_1st", func():
			var e: Dictionary = E.call(7, 59, 0, [9, 12, 30])
			S.call([e] + full.slice(0, 4), e, 0, "", 16)],
		["as_full_1st_off", func(): page._t = 24; page.queue_redraw()],
		["as_full_5th", func():
			var e: Dictionary = E.call(14, 5, 2, [36])
			var t := full.slice(0, 4)
			t.append(e)
			S.call(t, e, 4, "", 24)],
		["as_out", func(): S.call(full, E.call(25, 0, 3, [17, 18]), -1, "out", 16)],
		["as_cheats", func(): S.call(full.slice(0, 2), E.call(3, 2, 0, [10, 11, 34]), -1, "cheats", 16)],
		["as_partial", func(): S.call([], E.call(0, 41, 0, [0]), -1, "partial", 16)],
		["as_long", func():
			var e: Dictionary = E.call(99, 59, 3, [26, 4])
			S.call([E.call(59, 59, 1, [16, 21, 35]), E.call(70, 1, 2, [13, 14, 31]), e], e, 2, "", 16)],
		["as_nofile", func():
			var e: Dictionary = E.call(10, 5, 2, [0])
			S.call([e], e, 0, "nofile", 16)],
		["as_fade", func(): page._phase = 0; page._t = 8; page.queue_redraw()],
		# part 38: the ENDLESS RECORDS page (enemies beaten, minutes, seconds, hearts, team)
		["es_empty_new", func():
			page.endless = true
			var e: Dictionary = X.call(12, 8, 21, 1, [0, 5, 6])
			S.call([e], e, 0, "", 16)],
		["es_full_1st", func():
			var e: Dictionary = X.call(131, 61, 7, 0, [9, 12, 30])
			S.call([e] + efull.slice(0, 4), e, 0, "", 16)],
		["es_full_1st_off", func(): page._t = 24; page.queue_redraw()],
		["es_full_3rd", func():
			var e: Dictionary = X.call(29, 9, 40, 2, [36])
			S.call(efull.slice(0, 2) + [e] + efull.slice(2, 4), e, 2, "", 16)],
		["es_out", func(): S.call(efull, X.call(3, 1, 2, 3, [17, 18]), -1, "out", 16)],
		["es_zero", func(): S.call([], X.call(0, 0, 41, 0, [0]), -1, "out", 16)],
		["es_cheats", func(): S.call(efull.slice(0, 2), X.call(40, 12, 0, 0, [10, 11, 34]), -1, "cheats", 16)],
		["es_long", func():
			var e: Dictionary = X.call(99999, 99, 59, 3, [26, 4])
			S.call([e] + efull.slice(0, 1), e, 0, "", 16)],
	]


var X: Callable                                ## part 38: ENDLESS entry (beaten, m, s, hearts, ids)
var efull: Array = []
