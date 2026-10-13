class_name QoLMpMenu
extends Control
# ---- MULTIPLAYER MENU (part 27)
## LOCAL MULTIPLAYER menus (docs/MULTIPLAYER_DESIGN.md 3.3 / 3.4), drawn by the port over the game's own VS BATTLE
## screen (scene 0x11, state 2) while the MULTIPLAYER setting is on:
## - relabel overlay: the HOST / CLIENT plates and picture buttons read LOCAL / LAN, the top message box explains
##   the option under the game's own cursor (work u16 [0x020E1148] + 0x1066). The choice itself is intercepted by
##   QoLGame.f_0207b778 (LOCAL opens the setup page, LAN only shows a notice).
## - "setup": the controller setup page of a LOCAL session: a device box per player (KEYBOARD / every connected
##   gamepad, NOT CONNECTED when its pad is missing; Left / Right or the box's arrows cycle, A / a tap on the box
##   opens a drop-down list), CONTROLS SET per player, READY (bottom right), BACK.
## - "map": one player's 12 DS buttons for the device it uses (keys or pad buttons; a new input is only taken from
##   that player's device), DEFAULT.
## - "drop": the device drop-down list. "ready": READY TO CONTINUE? YES / NO (NO first, B = NO).
## Both players drive one shared cursor (either player's pad / keys, the mouse, either gamepad cursor). Look: the
## settings menu (QoLMenu: black bands, orange hexagons, QoLFont) over the screen's hexagon background (BG1 only),
## texts on the upper screen in the game's message box. Faded with the game's MASTER_BRIGHT (fade in / out).

const TRIM := QoLMenu.TRIM
const HEX_EDGE := QoLMenu.HEX_EDGE
const HEX_FILL := QoLMenu.HEX_FILL
const HEX_TEXT := QoLMenu.HEX_TEXT
const HEX_RED := QoLMenu.HEX_RED
const CURSOR := QoLMenu.CURSOR
const PCOL := [Color8(232, 40, 24), Color8(40, 104, 248)]   ## PLAYER 1 red, PLAYER 2 blue (as their cursors)
const HEX_H := 24
const ROW_Y := 31
const ROW_PITCH := 27
const READY_RECT := Rect2(158, 160, 94, 26)
const MROW_Y := 37                         ## mapping page rows
const MROW_PITCH := 22
const MHEX_H := 20
const LEFT_COL := ["ds_a", "ds_b", "ds_x", "ds_y", "ds_l", "ds_r"]
const RIGHT_COL := ["ds_start", "ds_select", "ds_up", "ds_down", "ds_left", "ds_right"]
const WAIT_FRAMES := 360
## upper screen (the VS BATTLE screen's frame): title bar text area and the brown message box
const TITLE_BAR := Color8(251, 162, 0)
const BOX_STRIPES := [Color8(130, 97, 56), Color8(113, 89, 40), Color8(121, 89, 48)]   ## by y % 3
const BOX := Rect2(11, 59, 234, 90)
const TEXT := Color8(235, 235, 235)
## lower screen of the VS menu (measured on the game's screen, /tmp/ssw2/mp_research/vs1/p2820.png)
const HOST_PLATE := Rect2(12, 144, 41, 14)
const CLIENT_PLATE := Rect2(203, 32, 41, 14)
const LEFT_KANJI := Rect2(30, 66, 61, 61)    ## the yellow-outlined kanji 親 / 子 inside the picture buttons
const RIGHT_KANJI := Rect2(166, 67, 60, 60)

var qol                                    ## QoLController (or the preview tool's stand-in)
var font: QoLFont
var top: Control                            ## the upper-screen part (own modulate: engine B's brightness)
var page := ""                              ## "" (closed), "setup", "map", "drop", "ready"
var row := 1
var col := 0
var map_p := 0                              ## "map": the player whose buttons are shown
var drop_p := 0                             ## "drop": the player choosing
var leaving := false                        ## YES was chosen: the page stays up (no input) while the scene fades out
var vs_shown := false                       ## the LOCAL / LAN relabel overlay (VS BATTLE screen)
var vs_cursor := 0                          ## the game's cursor there: 0 LOCAL (left), 1 LAN (right)
var _rows: Array = []                       ## [[{id, rect}, ...], ...] of the current page
var _wait := {}                             ## "map": waiting for a new input {action, frames}
var _wait_release := false
var _notice := ""
var _notice_action := ""
var _lan_frames := 0                        ## LAN chosen: the notice shows for this many game frames
var _flash := {}
var _held_frames := {}
var _ignore := 0                            ## buttons held when the page opened: ignored until released


func _init() -> void:
	position = Vector2(0, 192)
	size = Vector2(256, 192)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # taps arrive through the game's touch input (frame_input)
	visible = false
	top = Control.new()
	top.position = Vector2(0, -192)
	top.size = Vector2(256, 192)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.draw.connect(_draw_top)
	add_child(top)


func _mi() -> QoLMpInput:
	return qol.mp_input


func is_open() -> bool:
	return page != ""


func waiting() -> bool:
	return page == "map" and not _wait.is_empty()


## LOCAL chosen: the controller setup page (a new session; QoLController starts it)
func open_setup() -> void:
	page = "setup"
	leaving = false
	_wait = {}
	_notice = ""
	_build()
	row = 1
	col = 0
	_lan_frames = 0
	_ignore = 0xFFF
	_update()


func close() -> void:
	page = ""
	_wait = {}
	leaving = false
	_update()


## the VS BATTLE screen's relabel overlay on / off and the game's cursor (QoLController.after_step)
func set_vs(shown: bool, cursor: int) -> void:
	if shown != vs_shown or cursor != vs_cursor:
		vs_shown = shown
		vs_cursor = cursor
		_update()
	if _lan_frames > 0:
		_lan_frames -= 1
		if _lan_frames == 0:
			_update()


## once per game frame while shown (QoLController): a pad plugged in / out shows at once
var _pads_seen := []
func tick() -> void:
	if page == "":
		return
	var l := _mi().pad_list()
	if l != _pads_seen:
		_pads_seen = l
		if page == "drop":
			_build()
			row = clampi(row, 0, _rows.size() - 1)
		queue_redraw()
		top.queue_redraw()


func lan_notice() -> void:
	_lan_frames = 240
	_update()


## the game's fade (MASTER_BRIGHT of the engine on each screen): 1 = full, 0 = black
func set_brightness(lower: float, upper: float) -> void:
	var cl := Color(lower, lower, lower)
	var cu := Color(upper, upper, upper)
	if self_modulate != cl:
		self_modulate = cl
	if top.modulate != cu:
		top.modulate = cu


func _update() -> void:
	visible = page != "" or vs_shown
	queue_redraw()
	top.queue_redraw()


func _process(delta: float) -> void:
	if not visible or _flash.is_empty():
		return
	for k in _flash.keys():
		_flash[k] -= delta
		if _flash[k] <= 0.0:
			_flash.erase(k)
	queue_redraw()


# ------------------------------------------------------------------------------------------------ pages
func _row_y(r: int) -> int:
	return ROW_Y + (r - 1) * ROW_PITCH


func _mrow_y(r: int) -> int:
	return MROW_Y + (r - 1) * MROW_PITCH


func _build() -> void:
	_rows = []
	match page:
		"setup", "ready":
			_rows = _setup_rows()
			if page == "ready":
				_rows.append([{"id": "yes", "rect": Rect2(66, 122, 54, HEX_H)}, {"id": "no", "rect": Rect2(136, 122, 54, HEX_H)}])
		"map":
			_rows.append([{"id": "mback", "rect": Rect2(211, 4, 41, 20)}])
			for i in 6:
				var y := _mrow_y(1 + i)
				_rows.append([{"id": "key:" + LEFT_COL[i], "rect": Rect2(58, y, 66, MHEX_H)},
					{"id": "key:" + RIGHT_COL[i], "rect": Rect2(188, y, 64, MHEX_H)}])
			_rows.append([{"id": "mdefault", "rect": Rect2(173, _mrow_y(7), 80, MHEX_H)}])
		"drop":
			var ch := _mi().choices(drop_p)
			for i in mini(ch.size(), 5):
				_rows.append([{"id": "pick:%d" % ch[i], "rect": Rect2(24, 62 + i * 24, 208, 22)}])


## the setup page's buttons by row: BACK, P1 device, P1 CONTROLS, P2 device, P2 CONTROLS, READY
func _setup_rows() -> Array:
	var r := [[{"id": "back", "rect": Rect2(211, 4, 41, 20)}]]
	for p in 2:
		r.append([{"id": "dev:%d" % p, "rect": Rect2(96, _row_y(1 + p * 2), 156, HEX_H)}])
		r.append([{"id": "map:%d" % p, "rect": Rect2(196, _row_y(2 + p * 2), 56, HEX_H)}])
	r.append([{"id": "ready", "rect": READY_RECT}])
	return r


func cur_id() -> String:
	if row < 0 or row >= _rows.size() or col >= _rows[row].size():
		return ""
	return _rows[row][col]["id"]


## the device choice cycled by one (Left / Right on the box, or its arrows)
func _cycle(p: int, d: int) -> void:
	var ch := _mi().choices(p)
	var i := ch.find(_mi().dev[p])
	_mi().set_device(p, ch[posmod(i + d, ch.size())])
	qol.se(QoLController.SE_MOVE)
	_flash["dev:%d" % p] = 0.12
	_changed()


func _changed() -> void:
	qol.settings.save_file()
	queue_redraw()
	top.queue_redraw()


func _press(id: String) -> void:
	var p := id.split(":")
	_flash[id] = 0.15
	match p[0]:
		"back":
			qol.se(QoLController.SE_BACK)
			qol.mp_setup_back()          # closes the page, ends the session: the LOCAL / LAN screen again
			return
		"dev":
			drop_p = int(p[1])
			page = "drop"
			_build()
			row = maxi(0, _mi().choices(drop_p).find(_mi().dev[drop_p]))
			col = 0
			qol.se(QoLController.SE_DECIDE)
		"devl", "devr":
			_cycle(int(p[1]), -1 if p[0] == "devl" else 1)
			row = 1 + int(p[1]) * 2
			col = 0
		"pick":
			_mi().set_device(drop_p, int(p[1]))
			qol.se(QoLController.SE_DECIDE)
			page = "setup"
			_build()
			row = 1 + drop_p * 2
			col = 0
			_changed()
		"map":
			map_p = int(p[1])
			page = "map"
			_notice = ""
			_build()
			row = 1
			col = 0
			qol.se(QoLController.SE_DECIDE)
		"mback":
			qol.se(QoLController.SE_BACK)
			_wait = {}
			page = "setup"
			_build()
			row = 2 + map_p * 2
			col = 0
		"key":
			qol.se(QoLController.SE_DECIDE)
			_wait = {"action": p[1], "frames": 0}
			_notice = ""
		"mdefault":
			qol.se(QoLController.SE_DECIDE)
			_mi().reset(map_p)
			_notice = "DEFAULT"
			_notice_action = ""
			_changed()
		"ready":
			qol.se(QoLController.SE_DECIDE)
			page = "ready"
			_build()
			row = _rows.size() - 1
			col = 1                                    # NO first
		"no":
			qol.se(QoLController.SE_BACK)
			page = "setup"
			_build()
			row = 5
			col = 0
		"yes":
			qol.se(QoLController.SE_DECIDE)
			page = "setup"
			_build()
			row = 5
			col = 0
			leaving = true
			qol.mp_setup_go()            # QoLGame.f_0207b778 leaves the scene -> character select
	queue_redraw()
	top.queue_redraw()


func finish_wait(code: String) -> void:
	var a: String = _wait["action"]
	_wait = {}
	var other := _mi().assign(map_p, a, code)
	_notice_action = a
	_notice = "%s = %s" % [QoLControls.label_of(a), QoLControls.name_of(code)]
	if other != "":
		_notice += " (swapped with %s)" % QoLControls.label_of(other)
	var sh := _mi().shared_key(map_p, code)
	if sh != "":
		_notice += " (also P%d %s)" % [2 - map_p, QoLControls.label_of(sh)]
	_wait_release = true
	qol.se(QoLController.SE_DECIDE)
	_flash["key:" + a] = 0.3
	_changed()


func cancel_wait() -> void:
	qol.se(QoLController.SE_BACK)
	_wait = {}
	_notice = ""
	_wait_release = true
	queue_redraw()
	top.queue_redraw()


# ------------------------------------------------------------------------------------------------ input
## once per game frame while a page is open (QoLController.mp_frame): `newly` / `down` = DS layout words of both
## players (QoLMp bits), `tap` = where a touch began (lower-screen pixels) or (-1, -1)
func frame_input(newly: Array, down: Array, tap: Vector2i) -> void:
	if page == "" or leaving:
		return
	var dn: int = down[0] | down[1]
	_ignore &= dn
	var nw: int = (newly[0] | newly[1]) & ~_ignore
	dn &= ~_ignore
	if not _wait.is_empty():
		_wait["frames"] += 1
		if tap.x >= 0 or _wait["frames"] >= WAIT_FRAMES:
			cancel_wait()
		elif _wait["frames"] % 60 == 0:
			top.queue_redraw()
			queue_redraw()
		return
	if _wait_release:
		if dn != 0 or tap.x >= 0:
			return
		_wait_release = false
	if tap.x >= 0:
		_tap(Vector2(tap))
		return
	var moved := false
	for b in [QoLMp.UP, QoLMp.DOWN, QoLMp.LEFT, QoLMp.RIGHT]:
		if (dn & b) == 0:
			_held_frames.erase(b)
			continue
		var f: int = _held_frames.get(b, -1) + 1
		_held_frames[b] = f
		if f == 0 or (f >= 21 and (f - 21) % 6 == 0):
			moved = _move(b) or moved
	if moved:
		qol.se(QoLController.SE_MOVE)
		queue_redraw()
		top.queue_redraw()
	if nw & (QoLMp.A | QoLMp.START):
		_press(cur_id())
	elif nw & QoLMp.B:
		match page:
			"setup": _press("back")
			"map": _press("mback")
			"ready": _press("no")
			"drop":
				qol.se(QoLController.SE_BACK)
				page = "setup"
				_build()
				row = 1 + drop_p * 2
				col = 0
				queue_redraw()
				top.queue_redraw()


func _move(b: int) -> bool:
	match page:
		"setup":
			if b == QoLMp.LEFT or b == QoLMp.RIGHT:
				if row == 1 or row == 3:          # the device box: cycle the device
					_cycle((row - 1) / 2, -1 if b == QoLMp.LEFT else 1)
					return false
				return false
			row = posmod(row + (1 if b == QoLMp.DOWN else -1), _rows.size())
			col = 0
			return true
		"ready":
			if b == QoLMp.LEFT and col > 0:
				col -= 1
				return true
			if b == QoLMp.RIGHT and col < 1:
				col += 1
				return true
		"drop":
			if b == QoLMp.UP or b == QoLMp.DOWN:
				row = posmod(row + (1 if b == QoLMp.DOWN else -1), _rows.size())
				return true
		"map":
			if b == QoLMp.LEFT or b == QoLMp.RIGHT:
				var nc := clampi(col + (1 if b == QoLMp.RIGHT else -1), 0, _rows[row].size() - 1)
				if nc != col:
					col = nc
					return true
				return false
			row = posmod(row + (1 if b == QoLMp.DOWN else -1), _rows.size())
			col = mini(col, _rows[row].size() - 1)
			if row == 0 or row == _rows.size() - 1:
				col = 0
			return true
	return false


func _tap(p: Vector2) -> void:
	if page == "drop":
		for r in _rows.size():
			if _rows[r][0]["rect"].grow(1).has_point(p):
				row = r
				_press(_rows[r][0]["id"])
				return
		qol.se(QoLController.SE_BACK)        # a tap outside the list: closed, nothing changed
		page = "setup"
		_build()
		row = 1 + drop_p * 2
		col = 0
		queue_redraw()
		top.queue_redraw()
		return
	for r in _rows.size():
		if page == "ready" and r != _rows.size() - 1:
			continue
		for i in _rows[r].size():
			var b: Dictionary = _rows[r][i]
			var rc: Rect2 = b["rect"]
			if rc.grow(1).has_point(p):
				row = r
				col = i
				if b["id"].begins_with("dev:") and (p.x < rc.position.x + 28 or p.x >= rc.end.x - 28):
					_press(("devl:" if p.x < rc.position.x + 28 else "devr:") + b["id"].substr(4))
				else:
					_press(b["id"])
				return
	if page == "setup":                      # a tap on a row's label moves the cursor there
		for r in range(1, 5):
			if Rect2(0, _row_y(r) + 2, 94, 20).has_point(p):
				qol.se(QoLController.SE_MOVE)
				row = r
				col = 0
				queue_redraw()
				top.queue_redraw()
				return


# ------------------------------------------------------------------------------------------------ texts
func focus_title() -> String:
	match page:
		"ready": return "READY?"
		"drop": return "PLAYER %d DEVICE" % (drop_p + 1)
		"map":
			var id := cur_id()
			if id == "mback":
				return "BACK"
			if id == "mdefault":
				return "DEFAULT"
			var fn := _func_of(id.substr(4))
			return "P%d %s - %s" % [map_p + 1, QoLControls.label_of(id.substr(4)), fn] if not fn.begins_with("(") else "P%d %s BUTTON" % [map_p + 1, QoLControls.label_of(id.substr(4))]
	var id := cur_id()
	if id == "back":
		return "BACK"
	if id.begins_with("dev:"):
		return "PLAYER %s DEVICE" % str(int(id.substr(4)) + 1)
	if id.begins_with("map:"):
		return "PLAYER %s CONTROLS" % str(int(id.substr(4)) + 1)
	if id == "ready":
		return "READY"
	return "LOCAL BATTLE"


static func _func_of(a: String) -> String:
	for b in QoLControls.BUTTONS:
		if b[0] == a:
			return b[2]
	return ""


func _dev_line(p: int) -> String:
	var mi := _mi()
	var d: int = mi.dev[p]
	if d == QoLMpInput.KEYBOARD:
		return "KEYBOARD" + (" (OWN KEY SET)" if p == 1 or mi.dev[1 - p] == QoLMpInput.KEYBOARD else "")
	if not mi.connected(d):
		return "PAD %d - NOT CONNECTED" % (d + 1)
	return "PAD %d: %s" % [d + 1, mi.pad_name(d).left(22)]


func focus_desc() -> String:
	var mi := _mi()
	match page:
		"ready":
			return "Go on to the character select?\nPLAYER 1: %s\nPLAYER 2: %s\nYES......character select\nNO.......back to the setup" % [_dev_line(0), _dev_line(1)]
		"drop":
			return "Choose the device of PLAYER %d:\nthe keyboard or a connected\ngamepad. A gamepad of the other\nplayer is swapped over.\nB or a tap outside: no change." % (drop_p + 1)
		"map":
			var id := cur_id()
			if id == "mback":
				return "Back to the setup page.\n(B does the same.)\nThe buttons are saved at once."
			if id == "mdefault":
				var dd := "the CONTROLS keys and\npad buttons of the settings." if map_p == 0 else "keys I K J L, N M H G, U O,\nP Y and the original pad layout."
				return "PLAYER %d back to the defaults:\n%s%s" % [map_p + 1, dd, "\nIn use now." if not mi.custom[map_p] else ""]
			var a := id.substr(4)
			var dname := "KEY" if not mi.uses_pad(map_p) else "PAD %d BUTTON" % (mi.dev[map_p] + 1)
			if not _wait.is_empty():
				return "Press the new %s\nfor PLAYER %d %s now.\nEsc or a tap: cancel.  %d\nOnly this player's %s\ncounts." % [dname, map_p + 1, QoLControls.label_of(a),
					ceili((WAIT_FRAMES - _wait["frames"]) / 60.0), "keyboard" if not mi.uses_pad(map_p) else "gamepad"]
			var head := "%s: %s" % [dname, QoLControls.name_of(mi.code(map_p, a))]
			if _notice != "" and (_notice_action == a or _notice_action == ""):
				head = _notice
			return "%s\nPress the box, then the new\n%s. Only PLAYER %d's\n%s counts here." % [head, "key" if not mi.uses_pad(map_p) else "gamepad button",
				map_p + 1, "keyboard" if not mi.uses_pad(map_p) else "gamepad"]
	var id := cur_id()
	if id == "back":
		return "Back to LOCAL / LAN.\n(B does the same.)"
	if id.begins_with("dev:"):
		var p := int(id.substr(4))
		return "Now: %s\nLEFT / RIGHT: next device\nA: list of devices\nP1 red cursor, P2 blue cursor\n(right stick, on gamepads)." % _dev_line(p)
	if id.begins_with("map:"):
		var p := int(id.substr(4))
		return "The buttons of PLAYER %d on\n%s (%s).\nThese replace the normal\ncontrols until you are back\non the Mode Select menu." % [p + 1, _dev_line(p).split(":")[0].split(" (")[0],
			"changed" if mi.custom[p] else "default"]
	if id == "ready":
		var warn := ""
		for p in 2:
			if not mi.connected(mi.dev[p]):
				warn = "\nPLAYER %d's pad is NOT CONNECTED!" % (p + 1)
		return "Both players set? On to the\ncharacter select (it asks\nfirst: READY TO CONTINUE?)." + warn
	return ""


# ------------------------------------------------------------------------------------------------ drawing
func _draw() -> void:
	if page == "":
		if vs_shown:
			_draw_vs()
		return
	match page:
		"setup", "ready", "drop":
			_draw_setup()
			if page == "ready":
				_draw_ready()
			elif page == "drop":
				_draw_drop()
		"map":
			_draw_map()


## the VS BATTLE screen with LOCAL / LAN: label plates and a framed word over each picture button's kanji
func _draw_vs() -> void:
	for k in 2:
		var plate: Rect2 = HOST_PLATE if k == 0 else CLIENT_PLATE
		draw_rect(Rect2(plate.position + Vector2(1, 0), plate.size - Vector2(2, 0)), Color.WHITE)
		draw_rect(Rect2(plate.position + Vector2(0, 1), plate.size - Vector2(0, 2)), Color.WHITE)
		font.draw_centered(self, plate, "LOCAL" if k == 0 else "LAN", Color.BLACK, QoLFont.BOLD)
		var r: Rect2 = (LEFT_KANJI if k == 0 else RIGHT_KANJI).grow(3)
		var lit := vs_cursor == k
		draw_rect(r, Color(0, 0, 0, 0.8))   # the kanji covered, the picture still shows around it
		draw_rect(r.grow(-1), Color8(255, 214, 0) if lit else Color8(160, 120, 0), false, 2.0)
		font.draw_centered(self, r, "LOCAL" if k == 0 else "LAN", Color8(255, 230, 64) if lit else Color8(210, 175, 60), QoLFont.HEAVY, Color.BLACK)


func _plate(t: String) -> void:
	draw_rect(Rect2(0, 1, 127, 1), TRIM)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 2), Vector2(125, 2), Vector2(112, 26), Vector2(0, 26)]), Color.BLACK)
	draw_line(Vector2(125.5, 2), Vector2(112.5, 26), TRIM)
	draw_rect(Rect2(0, 26, 113, 1), TRIM)
	draw_colored_polygon(PackedVector2Array([Vector2(7, 6), Vector2(15, 6), Vector2(12, 21), Vector2(4, 21)]), CURSOR)
	font.draw(self, Vector2(19, 6), t, HEX_TEXT, QoLFont.BIG)
	draw_rect(Rect2(16, 21, 90, 1), CURSOR)


func _band(y: int, h: int) -> void:
	draw_rect(Rect2(0, y - 1, 256, 1), TRIM)
	draw_rect(Rect2(0, y, 256, h), Color.BLACK)
	draw_rect(Rect2(0, y + h, 256, 1), TRIM)


func _hex_points(r: Rect2, inset: float) -> PackedVector2Array:
	var s := r.size.y * 0.32
	var x0 := r.position.x + inset
	var x1 := r.end.x - inset
	var y0 := r.position.y + inset
	var y1 := r.end.y - inset
	var ym := r.position.y + r.size.y / 2.0
	var si := s - inset * 0.4
	return PackedVector2Array([Vector2(x0 + si, y0), Vector2(x1 - si, y0), Vector2(x1, ym), Vector2(x1 - si, y1), Vector2(x0 + si, y1), Vector2(x0, ym)])


func _hex(r: Rect2, text: String, value: bool, cursor: bool, flash: bool, text_col: Color = HEX_TEXT) -> void:
	draw_colored_polygon(_hex_points(r, 0), CURSOR if cursor else HEX_EDGE)
	draw_colored_polygon(_hex_points(r, 2), Color.BLACK)
	draw_colored_polygon(_hex_points(r, 3), HEX_EDGE if flash else HEX_FILL)
	if text != "":
		var st := QoLFont.BOLD if font.width(text, QoLFont.BOLD) <= r.size.x - 10 else QoLFont.REGULAR
		font.draw_centered(self, r, text, HEX_RED if value else text_col, st)


## the player tag: a slanted block in the player's colour with its number
func _tag(x: float, y: float, p: int) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(x + 4, y), Vector2(x + 18, y), Vector2(x + 14, y + 14), Vector2(x, y + 14)]), PCOL[p])
	font.draw_centered(self, Rect2(x + 1, y + 2, 16, 10), str(p + 1), HEX_TEXT, QoLFont.BOLD)


func _draw_setup() -> void:
	var mi := _mi()
	var modal := page != "setup"
	var sr := _setup_rows()
	_plate("LOCAL BATTLE")
	var bb: Dictionary = sr[0][0]
	_hex(bb["rect"], "BACK", false, not modal and row == 0, _flash.has("back"))
	for p in 2:
		var y1 := _row_y(1 + p * 2)
		var y2 := _row_y(2 + p * 2)
		_band(y1 + 3, 18)
		_tag(4, y1 + 5, p)
		font.draw(self, Vector2(26, y1 + 6), "PLAYER %d" % (p + 1), HEX_TEXT, QoLFont.BIG)
		_band(y2 + 3, 18)
		font.draw(self, Vector2(26, y2 + 6), "CONTROLS", HEX_TEXT, QoLFont.BIG)
		font.draw(self, Vector2(110, y2 + 8), "CHANGED" if mi.custom[p] else "DEFAULT", HEX_EDGE, QoLFont.BOLD)
		var d: int = mi.dev[p]
		var r: Rect2 = sr[1 + p * 2][0]["rect"]
		var ok := mi.connected(d)
		var t := QoLMpInput.dev_label(d) + ("" if ok else " - NOT CONNECTED")
		var cur: bool = not modal and row == 1 + p * 2
		_hex(r, "", false, cur, _flash.has("dev:%d" % p))
		var st := QoLFont.BOLD if font.width(t, QoLFont.BOLD) <= r.size.x - 50 else QoLFont.REGULAR
		font.draw_centered(self, r, t, HEX_TEXT if ok else HEX_RED, st)
		for s in [-1, 1]:      # the cycling arrows inside the box
			var c := Vector2(r.position.x + 15, r.get_center().y) if s < 0 else Vector2(r.end.x - 15, r.get_center().y)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-4 * s, -6), c + Vector2(5 * s, 0), c + Vector2(-4 * s, 6)]), CURSOR if cur else HEX_TEXT)
		var mr: Dictionary = sr[2 + p * 2][0]
		_hex(mr["rect"], "SET", false, not modal and row == 2 + p * 2, _flash.has("map:%d" % p))
	var rr: Dictionary = sr[5][0]
	_hex(rr["rect"], "READY", false, not modal and row == 5, _flash.has("ready") or leaving)
	font.draw(self, Vector2(8, 169), "B: BACK", HEX_TEXT, QoLFont.BOLD, Color.BLACK)


func _dim() -> void:
	draw_rect(Rect2(0, 28, 256, 164), Color(0, 0, 0, 0.55))


func _draw_ready() -> void:
	_dim()
	var y := 66
	_band(y, 88)
	font.draw_centered(self, Rect2(0, y + 9, 256, 13), "READY TO CONTINUE?", HEX_TEXT, QoLFont.BIG)
	var mi := _mi()
	font.draw_centered(self, Rect2(0, y + 31, 256, 10), "P1 %s    P2 %s" % [QoLMpInput.dev_label(mi.dev[0]), QoLMpInput.dev_label(mi.dev[1])], HEX_EDGE, QoLFont.BOLD)
	var bs: Array = _rows[_rows.size() - 1]
	for i in bs.size():
		_hex(bs[i]["rect"], "YES" if i == 0 else "NO", false, col == i, _flash.has(bs[i]["id"]))


func _draw_drop() -> void:
	_dim()
	var n := _rows.size()
	var y0 := 34
	_band(y0, 30 + n * 24)
	_tag(8, y0 + 7, drop_p)
	font.draw(self, Vector2(30, y0 + 8), "PLAYER %d DEVICE" % (drop_p + 1), HEX_TEXT, QoLFont.BIG)
	var mi := _mi()
	for i in n:
		var b: Dictionary = _rows[i][0]
		var d := int(b["id"].substr(5))
		var t := QoLMpInput.dev_label(d)
		if d != QoLMpInput.KEYBOARD:
			t += "  " + (mi.pad_name(d).to_upper() if mi.connected(d) else "NOT CONNECTED")
		if d != QoLMpInput.KEYBOARD and mi.dev[1 - drop_p] == d:
			t += " (P%d)" % (2 - drop_p)
		t = t.left(30)
		_hex(b["rect"], t, d == mi.dev[drop_p], row == i, _flash.has(b["id"]))


func _draw_map() -> void:
	var mi := _mi()
	_plate("PLAYER %d %s" % [map_p + 1, "PAD" if mi.uses_pad(map_p) else "KEYS"])
	_hex(_rows[0][0]["rect"], "BACK", false, row == 0, _flash.has("mback"))
	_tag(130, 7, map_p)
	font.draw(self, Vector2(152, 9), QoLMpInput.dev_label(mi.dev[map_p]), HEX_EDGE, QoLFont.BOLD, Color.BLACK)
	for r in range(1, _rows.size()):
		var y := _mrow_y(r)
		draw_rect(Rect2(0, y + 1, 256, 1), TRIM)
		draw_rect(Rect2(0, y + 2, 256, 16), Color.BLACK)
		draw_rect(Rect2(0, y + 18, 256, 1), TRIM)
		if r == _rows.size() - 1:
			font.draw(self, Vector2(5, y + 5), "ALL BUTTONS", HEX_TEXT, QoLFont.BIG)
			_hex(_rows[r][0]["rect"], "DEFAULT", false, row == r, _flash.has("mdefault"))
			continue
		draw_rect(Rect2(127, y + 2, 1, 16), TRIM)
		for i in 2:
			var b: Dictionary = _rows[r][i]
			var a: String = b["id"].substr(4)
			font.draw(self, Vector2(5 if i == 0 else 132, y + 5), QoLControls.label_of(a), HEX_TEXT, QoLFont.BIG)
			var waiting: bool = not _wait.is_empty() and _wait["action"] == a
			var blink: bool = waiting and (_wait["frames"] / 15) % 2 == 0
			_hex(b["rect"], "PRESS" if waiting else QoLControls.name_of(mi.code(map_p, a)), false, (r == row and i == col) or blink,
				_flash.has(b["id"]) or (waiting and not blink))


## the upper screen: the VS BATTLE frame's title bar (while a page is open) and its message box
func _draw_top() -> void:
	var title := ""
	var desc := ""
	if page != "":
		title = focus_title()
		desc = focus_desc()
	elif vs_shown:
		if _lan_frames > 0:
			desc = "LAN BATTLE\n\nPlaying over a network is not\navailable yet (coming in a later\nversion). Choose LOCAL to play\ntwo players on this PC."
		elif vs_cursor == 0:
			desc = "LOCAL BATTLE\n\nTwo players on this PC, with the\nkeyboard and / or gamepads. Set\nup the controllers, then choose\nyour fighters and a stage."
		else:
			desc = "LAN BATTLE\n\nPlay against a friend's PC on\nyour home network: HOST a room\nor JOIN one by its IP address."   # part 30
	else:
		return
	if title != "":
		top.draw_rect(Rect2(0, 25, 199, 16), TITLE_BAR)
		font.draw(top, Vector2(43, 28), title, Color.BLACK, QoLFont.HEAVY)
	for y in range(int(BOX.position.y), int(BOX.end.y)):
		top.draw_rect(Rect2(BOX.position.x, y, BOX.size.x, 1), BOX_STRIPES[y % 3])
	var lines := desc.split("\n")
	var y0 := 66 if lines.size() >= 6 else 70
	for i in mini(lines.size(), 6):
		font.draw(top, Vector2(22, y0 + i * 13), lines[i], TEXT if i > 0 or page != "" or lines.size() < 2 or lines[1] != "" else Color8(255, 206, 0))
