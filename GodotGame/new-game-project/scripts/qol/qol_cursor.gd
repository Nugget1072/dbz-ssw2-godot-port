class_name QoLCursor
extends Node2D
## Gamepad mouse cursor for the touch screen (part 24, CONTROLS page 3). While a gamepad is connected and the
## cursor is ON, the right stick (input actions qol_cur_up/down/left/right, remappable in QoLControls) moves a
## pointer over the lower DS screen and the right-stick press (qol_cur_click) touches the screen where it points,
## for as long as it is held: GameDS._tick feeds that touch through exactly the same path as a mouse click
## (QoLController.filter_input -> the game's touch screen), so it works in the settings menu and everywhere the
## game uses the touch screen. Drawn at DS-pixel scale inside the 256x384 screen (the presenter scales it like the
## game's picture), on top of everything. Hidden after 4 s without stick movement or click, and when the real mouse
## is used (until the stick moves again).
## Debug / tests: `fakepad` (pretend a gamepad is connected; captures never show the cursor without it or vcursor),
## `vcursor=X,Y` (shown at once at lower-screen pixel X,Y, never hidden), `vcurmove=F:SX:SY:N,...` (stick deflection
## SX,SY in -1..1 during game frames F..F+N-1), `vcurclick=F:N,...` (click held in frames F..F+N-1), `curspeed=1..5`,
## `curdbg` (a "CUR" line per game frame while it moves / clicks). In captures the cursor moves once per game frame
## (1/59.83 s), so the scripted runs are frame-exact.
## Part 27 LOCAL MULTIPLAYER: during a session this cursor is hidden and each player whose device is a gamepad gets
## an own cursor (`player` 0 / 1, red / blue, same arrow), moved by THAT pad only (QoLMpInput, the qol_cur_* pad
## inputs of CONTROLS page 3). Their touches go to QoLMp.ctouch. Tests: `fakepads=N` + `mpdev=`, player 1's cursor
## takes vcursor / vcurmove / vcurclick, player 2's vcursor2 / vcur2move / vcur2click.

const DEADZONE := 0.2                  ## radial, on the stick vector (the actions' own deadzone is the same)
const SPEEDS := [60.0, 100.0, 150.0, 220.0, 300.0]   ## DS pixels per second at full deflection, SPEED 1..5
const RAMP := 0.5                      ## seconds of continuous movement from 60 % to full speed (slight acceleration)
const IDLE_HIDE := 4.0                 ## seconds without movement / click before the cursor hides
const DS_HZ := 59.8261
const PAD := 4                         ## margin around the arrow in its texture (shadow, pressed rays)

## the arrow, 11x15 DS pixels, tip = hotspot (top-left): K outline, W highlight, O body, D shade. Colours of the
## settings menu (QoLMenu): cream-white body like its white selection hexagon, orange shade (HEX_EDGE); pressed it
## turns orange like a pressed hexagon's face (the menu's "flash"), with a yellow highlight and brown shade (TRIM).
const ARROW := [
	"K..........",
	"KK.........",
	"KWK........",
	"KWOK.......",
	"KWODK......",
	"KWOODK.....",
	"KWOOODK....",
	"KWOOOODK...",
	"KWOOOOODK..",
	"KWOOOOOODK.",
	"KWOOODKKKKK",
	"KWOKODK....",
	"KWK.KODK...",
	"KK..KODK...",
	".....KK....",
]
const COLORS := {"K": Color8(24, 12, 0), "W": Color8(255, 255, 255), "O": Color8(255, 247, 239), "D": Color8(255, 166, 0)}
const COLORS_PRESSED := {"K": Color8(24, 12, 0), "W": Color8(255, 226, 120), "O": Color8(255, 166, 0), "D": Color8(190, 125, 28)}
## part 27: the two players' cursors (red / blue body, lighter when pressed)
const PLAYER_COLORS := [
	[{"K": Color8(24, 0, 0), "W": Color8(255, 200, 190), "O": Color8(240, 48, 32), "D": Color8(150, 16, 8)},
	 {"K": Color8(24, 0, 0), "W": Color8(255, 236, 160), "O": Color8(255, 120, 96), "D": Color8(200, 40, 24)}],
	[{"K": Color8(0, 4, 24), "W": Color8(200, 225, 255), "O": Color8(40, 110, 255), "D": Color8(16, 50, 160)},
	 {"K": Color8(0, 4, 24), "W": Color8(220, 245, 255), "O": Color8(110, 170, 255), "D": Color8(30, 80, 210)}],
]

var qol                                ## QoLController (null: preview / forced)
var player := -1                       ## part 27: -1 = the normal cursor, 0 / 1 = a LOCAL MULTIPLAYER player's cursor
var half := -1                         ## part 27 QA: 0 / 1 = kept on that half of the lower screen (MP battle panel)
var pos := Vector2(128, 96)            ## lower-screen DS pixels (sub-pixel; drawn at whole pixels)
var pressed := false
var shown := false
var force := false                     ## vcursor / preview: always shown
var _idle := 0.0
var _hold := 0.0
var _mouse_hidden := false
var _latched := false                  ## a click press seen as an event (taps shorter than a game frame count)
var _was_down := false
var _swallow := false                  ## the press that only brought the cursor back (after mouse use)
var _dbg_stick := Vector2.ZERO
var _dbg_click := false
var _moves: Array = []                 ## vcurmove [from, sx, sy, n]
var _clicks: Array = []                ## vcurclick [from, n]
var _tex_up: ImageTexture
var _tex_down: ImageTexture
var _free_run := true


func _init() -> void:
	z_index = 1000                     # above the menu, FPS counter and markers
	visible = false
	_tex_up = ImageTexture.create_from_image(_image(false))
	_tex_down = ImageTexture.create_from_image(_image(true))
	_free_run = not Game.args.has("capture") and not Game.args.has("pilot") and not Game.args.has("turbo")
	_flags("vcursor", "vcurmove", "vcurclick")


func _flags(fc: String, fm: String, fk: String) -> void:
	force = false
	_moves = []
	_clicks = []
	if Game.args.has(fc):
		var p := Game.flag(fc).split(",")
		if p.size() >= 2:
			pos = Vector2(clampf(float(p[0]), 0, 255), clampf(float(p[1]), 0, 191))
		force = true
	for e in Game.flag(fm).split(",", false):
		var q := e.split(":")
		if q.size() >= 4:
			_moves.append([int(q[0]), float(q[1]), float(q[2]), int(q[3])])
	for e in Game.flag(fk).split(",", false):
		var q := e.split(":")
		_clicks.append([int(q[0]), int(q[1]) if q.size() > 1 else 4])


## part 27: make this a LOCAL MULTIPLAYER player's cursor (red P1 / blue P2; P2 takes the vcursor2 / vcur2move /
## vcur2click test flags)
func set_player(p: int) -> void:
	player = p
	_tex_up = ImageTexture.create_from_image(_image(false, p))
	_tex_down = ImageTexture.create_from_image(_image(true, p))
	if p == 1:
		_flags("vcursor2", "vcur2move", "vcur2click")
	pos = Vector2(64 if p == 0 else 192, 96) if not force else pos
	visible = false


## the arrow picture (PAD margin): normal = with a soft drop shadow; pressed = moved 1 px in, no shadow, lighter,
## with three short white "tap" rays at the tip
static func _image(down: bool, pl: int = -1) -> Image:
	var img := Image.create(11 + PAD * 2, 15 + PAD * 2, false, Image.FORMAT_RGBA8)
	var o := PAD + (1 if down else 0)
	var cols: Dictionary = COLORS_PRESSED if down else COLORS
	if pl >= 0:
		cols = PLAYER_COLORS[pl][1 if down else 0]
	if not down:
		for y in ARROW.size():
			for x in ARROW[y].length():
				if ARROW[y][x] != ".":
					img.set_pixel(PAD + x + 1, PAD + y + 1, Color(0, 0, 0, 0.45))
	else:
		var ray := Color8(255, 247, 239)
		for p in [Vector2i(-3, -3), Vector2i(-2, -2), Vector2i(-4, 0), Vector2i(-3, 0), Vector2i(0, -4), Vector2i(0, -3)]:
			img.set_pixel(o + p.x, o + p.y, ray)
	for y in ARROW.size():
		for x in ARROW[y].length():
			var c: String = ARROW[y][x]
			if c != ".":
				img.set_pixel(o + x, o + y, cols[c])
	return img


func _draw() -> void:
	var p := pos.floor() + Vector2(0, 192) - Vector2(PAD, PAD)
	draw_texture(_tex_down if pressed else _tex_up, p)


## the cursor can be used now: touch screen in use, cursor ON (or forced), a gamepad connected
func available() -> bool:
	if player >= 0:
		return _mp_available()
	if qol != null and qol.mp.active:    # part 27: the players' own cursors replace it during a session
		return false
	if force:
		return true
	if qol == null:
		return false
	if qol.game != null and qol.game.display != null and qol.game.display.single_screen:
		return false
	if not qol.controls.cursor_enabled:
		return false
	if Game.args.has("fakepad"):
		return true
	if Game.args.has("capture"):         # frame-exact captures: never, unless a debug flag asks
		return false
	return not Input.get_connected_joypads().is_empty()


## part 27: a player's cursor: during a LOCAL session, cursor ON, the player's device a connected pad
func _mp_available() -> bool:
	if qol == null:
		return force
	if not qol.mp.active:
		return false
	if qol.game != null and qol.game.display != null and qol.game.display.single_screen:
		return false
	var mi: QoLMpInput = qol.mp_input
	if not mi.uses_pad(player) or not qol.controls.cursor_enabled:
		return false
	if force:
		return true
	if Game.args.has("capture") and not Game.args.has("fakepads"):
		return false
	return mi.connected(mi.dev[player])


func _waiting() -> bool:
	if qol != null and qol.get("mp_menu") != null and qol.mp_menu.waiting():
		return true
	return qol != null and qol.menu != null and qol.menu.waiting_kind() != ""


## raw input events (GameDS._input): real mouse use hides the cursor; click presses are latched
func on_event(e: InputEvent) -> void:
	if e is InputEventMouseMotion and not Game.args.has("capture"):
		if e.relative.length() > 0.5 and not _mouse_hidden:
			_mouse_hidden = true
			_update()
	elif e is InputEventMouseButton and e.pressed and not Game.args.has("capture"):
		_mouse_hidden = true
		_update()
	elif player >= 0:
		if (e is InputEventJoypadButton or e is InputEventJoypadMotion) and qol != null and e.device == qol.mp_input.dev[player] \
				and e.is_pressed() and QoLControls.code_of(e) == qol.controls.map["qol_cur_click"]["pad"]:
			_latched = true
	elif InputMap.has_action("qol_cur_click") and e.is_action_pressed("qol_cur_click"):
		_latched = true


## the stick (or keys) of the qol_cur_* actions, -1..1 per axis
func _stick() -> Vector2:
	var v := Vector2.ZERO
	if player >= 0:                      # part 27: this player's pad only
		if qol == null or not qol.mp.active:
			return v
		var m: Dictionary = qol.controls.map
		var mi: QoLMpInput = qol.mp_input
		return Vector2(mi.strength(player, m["qol_cur_right"]["pad"]) - mi.strength(player, m["qol_cur_left"]["pad"]),
			mi.strength(player, m["qol_cur_down"]["pad"]) - mi.strength(player, m["qol_cur_up"]["pad"]))
	if InputMap.has_action("qol_cur_right"):
		v += Vector2(Input.get_action_raw_strength("qol_cur_right") - Input.get_action_raw_strength("qol_cur_left"),
			Input.get_action_raw_strength("qol_cur_down") - Input.get_action_raw_strength("qol_cur_up"))
	return v


## movement by stick vector `v` and idle time over `dt` seconds
func _advance(dt: float, v: Vector2) -> void:
	if not available() or _waiting():
		_hold = 0.0
		_update()
		return
	var l := v.length()
	if l > DEADZONE:
		var m := clampf((l - DEADZONE) / (1.0 - DEADZONE), 0.0, 1.0)
		_hold = minf(_hold + dt, RAMP)
		var sp: int = clampi(int(Game.flag("curspeed", str(qol.controls.cursor_speed if qol != null else QoLControls.CURSOR_SPEED_DEFAULT))), 1, 5)
		var speed: float = SPEEDS[sp - 1] * (0.35 * m + 0.65 * m * m) * (0.6 + 0.4 * _hold / RAMP)
		var np := _keep_in(pos + v / l * speed * dt)
		if np.floor() != pos.floor():
			queue_redraw()
		pos = np
		_idle = 0.0
		_mouse_hidden = false
	else:
		_hold = 0.0
		if not pressed:
			_idle += dt
	_update()


## the lower screen, or (part 27 QA, MP battle) the player's own half of it: taps there act for that player only
func _keep_in(p: Vector2) -> Vector2:
	if half == 0:
		return p.clamp(Vector2.ZERO, Vector2(127.99, 191.99))
	if half == 1:
		return p.clamp(Vector2(128, 0), Vector2(255.99, 191.99))
	return p.clamp(Vector2.ZERO, Vector2(255.99, 191.99))


func _update() -> void:
	var s := available() and (force or (_idle < IDLE_HIDE and not _mouse_hidden))
	if s != shown or visible != s:
		shown = s
		visible = s
		queue_redraw()


func _process(delta: float) -> void:
	if _free_run:
		_advance(delta, _stick())


## once per game frame (GameDS._tick through QoLController.cursor_touch, `f` = the frame about to run): the touch the
## cursor makes this frame (lower-screen pixel), or (-1, -1)
func frame_touch(f: int) -> Vector2i:
	_dbg_stick = Vector2.ZERO
	for m in _moves:
		if f >= m[0] and f < m[0] + m[3]:
			_dbg_stick = Vector2(m[1], m[2])
	_dbg_click = false
	for c in _clicks:
		if f >= c[0] and f < c[0] + c[1]:
			_dbg_click = true
	if not _free_run:                  # captures: one game frame of movement (stick + scripted), frame-exact
		_advance(1.0 / DS_HZ, _stick() + _dbg_stick)
	elif _dbg_stick != Vector2.ZERO:     # scripted moves in normal runs: per game frame too
		_advance(1.0 / DS_HZ, _dbg_stick)
	if half >= 0 and _keep_in(pos) != pos:   # part 27 QA: the MP battle panel: own half only
		pos = _keep_in(pos)
		queue_redraw()
	var down := _dbg_click or _latched
	if player >= 0:
		down = down or (qol != null and qol.mp.active and qol.mp_input.strength(player, qol.controls.map["qol_cur_click"]["pad"]) >= 0.5)
	else:
		down = down or (InputMap.has_action("qol_cur_click") and Input.is_action_pressed("qol_cur_click"))
	_latched = false
	if not available() or _waiting():
		down = false
	if down and not _was_down:
		_swallow = _mouse_hidden and not force   # after mouse use the first press only brings the cursor back
		_mouse_hidden = false
		_idle = 0.0
	_was_down = down
	if down != pressed:
		pressed = down
		queue_redraw()
	if down:
		_idle = 0.0
	_update()
	var t := Vector2i(int(pos.x), int(pos.y)) if down and not _swallow and shown else Vector2i(-1, -1)
	if Game.args.has("curdbg") and (down or _dbg_stick != Vector2.ZERO):
		print("CUR%s f%d pos %d,%d shown %s touch %s" % ["" if player < 0 else " P%d" % (player + 1), f, int(pos.x), int(pos.y), shown, t])
	return t
