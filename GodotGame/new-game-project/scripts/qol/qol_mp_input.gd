class_name QoLMpInput
extends RefCounted
# ---- MULTIPLAYER (part 27): per-player input devices and button mappings (docs/MULTIPLAYER_DESIGN.md 3.2 / 3.4)
## LOCAL MULTIPLAYER input. Each player has a device (KEYBOARD or one gamepad, by Godot joypad device id) and an
## own mapping of the 12 DS buttons: a key set (used when the device is the keyboard) and a pad set (used when it is
## a gamepad; read from THAT pad only). The ds_* input map (CONTROLS) is not used during a session: Input is polled
## per device (Input.is_physical_key_pressed / is_joy_button_pressed / get_joy_axis), so the keyboard and every pad
## drive only the player they belong to (joypad events carry their device id; keyboard events are never joypad
## events). Short presses between two game frames are latched from the raw events (`latch`).
## Defaults: PLAYER 1 = keyboard with the CONTROLS keys and pad buttons in use when the session first starts,
## PLAYER 2 = the first connected gamepad (else the keyboard with its own key set KEYBOARD 2: I K J L, N M H G,
## U O, P Y), pad buttons = the game's default pad layout. Saved in settings.cfg [mp].
## Debug / tests: `fakepads=N` (N pretend gamepads with ids 0..N-1), `mppad=F:DEV:CODE:N,…` (fake pad DEV holds
## CODE = b<button> or a<axis>+ / a<axis>- during game frames F..F+N-1; its first frame also counts as a raw press
## for the mapping capture), `mpdev=a,b` (devices of P1 / P2 for the run: k = keyboard, 0.. = pad id),
## `p2inputs=F:Btn[+Btn]:N[,F:T<x>/<y>:N]` (scripted PLAYER 2 input, syntax of inputs=).

const KEYBOARD := -1
## DS layout bit i = ORDER[i] (0x001 A … 0x200 L, 0x400 X, 0x800 Y; QoLMp constants)
const ORDER := ["ds_a", "ds_b", "ds_select", "ds_start", "ds_right", "ds_left", "ds_up", "ds_down", "ds_r", "ds_l", "ds_x", "ds_y"]
const SCRIPT_NAMES := ["A", "B", "Select", "Start", "Right", "Left", "Up", "Down", "R", "L", "X", "Y"]
## the second key set (PLAYER 2 on the keyboard): away from PLAYER 1's arrows, X Z S C A D, Enter, Backspace
const KB2 := {"ds_up": KEY_I, "ds_down": KEY_K, "ds_left": KEY_J, "ds_right": KEY_L, "ds_a": KEY_N, "ds_b": KEY_M,
	"ds_x": KEY_H, "ds_y": KEY_G, "ds_l": KEY_U, "ds_r": KEY_O, "ds_start": KEY_P, "ds_select": KEY_Y}
const AXIS_ON := 0.5

var controls: QoLControls                 ## the CONTROLS mapping (PLAYER 1's defaults, pad defaults)
var dev := [KEYBOARD, 0]                  ## device per player
var devices_set := false                  ## false until the player chose devices once (then P2 = first pad)
var keys := [{}, {}]                      ## per player: action -> "k:<physical keycode>" or ""
var pads := [{}, {}]                      ## per player: action -> "b:<button>" / "a:<axis>:<±1>" or ""
var custom := [false, false]              ## the player changed its mapping (else it follows the defaults; saved only then)
var _latched := [0, 0]
var _fake: Array = []                     ## mppad entries [from, dev, code, n]
var _script2: Array = []                  ## p2inputs entries [from, tokens, n]


func _init(c: QoLControls = null) -> void:
	controls = c
	for e in Game.flag("mppad").split(",", false):
		var q := e.split(":")
		if q.size() >= 3:
			_fake.append([int(q[0]), int(q[1]), _fake_code(q[2]), int(q[3]) if q.size() > 3 else 4])
	for e in Game.flag("p2inputs").split(",", false):
		var q := e.split(":")
		if q.size() >= 2:
			_script2.append([int(q[0]), q[1].split("+"), int(q[2]) if q.size() > 2 else 4])
	for p in 2:
		reset(p)


## "b0" -> "b:0", "a1+" -> "a:1:1", "a1-" -> "a:1:-1"
static func _fake_code(s: String) -> String:
	if s.begins_with("a") and s.length() >= 3:
		return "a:%s:%s" % [s.substr(1, s.length() - 2), "-1" if s.ends_with("-") else "1"]
	if s.begins_with("b"):
		return "b:" + s.substr(1)
	return s


## DEFAULT of a player's mapping (CONTROLS page of the setup): P1 = the CONTROLS keys / pad buttons in use now,
## P2 = KEYBOARD 2 keys + the original pad layout
func reset(p: int) -> void:
	keys[p] = {}
	pads[p] = {}
	for a in ORDER:
		if controls != null and controls.map.has(a):
			keys[p][a] = controls.map[a]["key"] if p == 0 else "k:%d" % KB2[a]
			pads[p][a] = controls.map[a]["pad"] if p == 0 else controls.defaults[a]["pad"]
		else:
			keys[p][a] = "" if p == 0 else "k:%d" % KB2[a]
			pads[p][a] = ""
	custom[p] = false


func is_default(p: int) -> bool:
	for a in ORDER:
		var k: String = controls.map[a]["key"] if p == 0 else "k:%d" % KB2[a]
		var d: String = controls.map[a]["pad"] if p == 0 else controls.defaults[a]["pad"]
		if keys[p][a] != k or pads[p][a] != d:
			return false
	return true


## the connected gamepads (device ids), or the pretend ones of `fakepads=N`
func pad_list() -> Array:
	if Game.args.has("fakepads"):
		return range(clampi(int(Game.flag("fakepads", "1")), 0, 8))
	return Input.get_connected_joypads()


func connected(d: int) -> bool:
	return d == KEYBOARD or d in pad_list()


## the choices of the device box: KEYBOARD, then every connected pad (and the player's own device even when it is
## not connected, so it can be seen as NOT CONNECTED)
func choices(p: int) -> Array:
	var l := [KEYBOARD]
	for d in pad_list():
		l.append(d)
	if not dev[p] in l:
		l.append(dev[p])
	return l


static func dev_label(d: int) -> String:
	return "KEYBOARD" if d == KEYBOARD else "PAD %d" % (d + 1)


func pad_name(d: int) -> String:
	if d == KEYBOARD:
		return "Keyboard"
	if Game.args.has("fakepads"):
		return "Fake gamepad %d" % (d + 1)
	var n := Input.get_joy_name(d)
	return n if n != "" else "Gamepad"


## first session (no choice saved yet): P1 keyboard, P2 the first pad (else KEYBOARD 2). `mpdev=` overrides.
func resolve_defaults() -> void:
	if Game.args.has("mpdev"):
		var q := Game.flag("mpdev").split(",")
		for p in mini(2, q.size()):
			dev[p] = KEYBOARD if q[p] == "k" else int(q[p])
		devices_set = true
	if devices_set:
		return
	var l := pad_list()
	dev = [KEYBOARD, l[0] if not l.is_empty() else KEYBOARD]


## a device for player p; another player's PAD is swapped over (the keyboard can be shared: each player has its own
## key set)
func set_device(p: int, d: int) -> void:
	var o := 1 - p
	if d != KEYBOARD and dev[o] == d:
		dev[o] = dev[p]
	dev[p] = d
	devices_set = true


func uses_pad(p: int) -> bool:
	return dev[p] != KEYBOARD


## the code of player p's button `a` on its current device ("" = none)
func code(p: int, a: String) -> String:
	return pads[p][a] if uses_pad(p) else keys[p][a]


# ------------------------------------------------------------------------------------------------ polling
## player p's buttons held now (DS layout word), from its device only, plus presses latched since the last poll and
## the debug fake pads (`f` = the game frame about to run)
func poll(p: int, f: int) -> int:
	var w := 0
	var d: int = dev[p]
	for i in ORDER.size():
		var c: String = code(p, ORDER[i])
		if c != "" and (_down(d, c) or _fake_down(d, c, f)):
			w |= 1 << i
	w |= _latched[p]
	_latched[p] = 0
	return w


func _down(d: int, c: String) -> bool:
	var q := c.split(":")
	match q[0]:
		"k":
			return d == KEYBOARD and Input.is_physical_key_pressed(int(q[1]))
		"b":
			return d >= 0 and Input.is_joy_button_pressed(d, int(q[1]))
		"a":
			return d >= 0 and Input.get_joy_axis(d, int(q[1])) * float(q[2]) >= AXIS_ON
	return false


func _fake_down(d: int, c: String, f: int) -> bool:
	for e in _fake:
		if e[1] == d and e[2] == c and f >= e[0] and f < e[0] + e[3]:
			return true
	return false


## debug fake pads: [dev, code] of the presses that start at game frame f (the mapping capture sees them as events)
func fake_presses(f: int) -> Array:
	var r := []
	for e in _fake:
		if e[0] == f:
			r.append([e[1], e[2]])
	return r


## the analog value -1..1 of player p's pad for code c (cursor stick): buttons 0 / 1, axes signed by the code
func strength(p: int, c: String) -> float:
	var d: int = dev[p]
	if d < 0 or c == "":
		return 0.0
	var q := c.split(":")
	if q[0] == "b":
		return 1.0 if Input.is_joy_button_pressed(d, int(q[1])) else 0.0
	if q[0] == "a":
		return maxf(0.0, Input.get_joy_axis(d, int(q[1])) * float(q[2]))
	return 0.0


## raw events (GameDS._input): a press that starts and ends between two game frames still counts for one frame
func latch(e: InputEvent) -> void:
	if not e.is_pressed() or e.is_echo():
		return
	var c := QoLControls.code_of(e)
	if c == "":
		return
	if e is InputEventJoypadMotion and absf(e.axis_value) < AXIS_ON:
		return
	for p in 2:
		var mine: bool = (e is InputEventKey and dev[p] == KEYBOARD) or ((e is InputEventJoypadButton or e is InputEventJoypadMotion) and e.device == dev[p])
		if not mine:
			continue
		for i in ORDER.size():
			if code(p, ORDER[i]) == c:
				_latched[p] |= 1 << i


## PLAYER 2's scripted input for game frame f: [word, tap]
func script2(f: int) -> Array:
	var w := 0
	var t := Vector2i(-1, -1)
	for e in _script2:
		if f >= e[0] and f < e[0] + e[2]:
			for b in e[1]:
				if b.begins_with("T"):
					var xy: PackedStringArray = b.substr(1).split("/")
					t = Vector2i(int(xy[0]), int(xy[1]))
					continue
				var i := SCRIPT_NAMES.find(b)
				if i >= 0:
					w |= 1 << i
	return [w, t]


# ------------------------------------------------------------------------------------------------ mapping
## a raw event while player p's mapping page waits for a new input: the code, "cancel" (Esc), or "" (not this
## player's device / not usable)
func capture(e: InputEvent, p: int) -> String:
	if e is InputEventKey:
		if e.pressed and not e.echo and (e.keycode == KEY_ESCAPE or e.physical_keycode == KEY_ESCAPE):
			return "cancel"
		return controls.capture(e, "key") if not uses_pad(p) else ""
	if (e is InputEventJoypadButton or e is InputEventJoypadMotion) and uses_pad(p) and e.device == dev[p]:
		return controls.capture(e, "pad")
	return ""


## assign `c` to player p's button `a` (key or pad set by the code); a button of the same player that had it gets
## `a`'s old input (swap). Returns that button's action or "".
func assign(p: int, a: String, c: String) -> String:
	var m: Dictionary = keys[p] if c.begins_with("k:") else pads[p]
	var old: String = m[a]
	var swapped := ""
	for b in m:
		if b != a and m[b] == c:
			m[b] = old
			swapped = b
	m[a] = c
	custom[p] = true
	return swapped


## the other player's button using key code `c` too, while both play on the keyboard ("" = none)
func shared_key(p: int, c: String) -> String:
	var o := 1 - p
	if uses_pad(o) or uses_pad(p) or not c.begins_with("k:"):
		return ""
	for a in ORDER:
		if keys[o][a] == c:
			return a
	return ""


func load_cfg(c: ConfigFile) -> void:
	devices_set = bool(QoLSettings._val(c, "mp", "devices_set", false))
	for p in 2:
		var d := str(c.get_value("mp", "p%d_device" % (p + 1), dev[p]))
		if d.is_valid_int():
			dev[p] = clampi(int(d), KEYBOARD, 15)
		if not c.has_section_key("mp", "p%d_ds_a_key" % (p + 1)):
			continue
		for a in ORDER:
			for kind in ["key", "pad"]:
				var v := str(c.get_value("mp", "p%d_%s_%s" % [p + 1, a, kind], ""))
				if v == "" or controls._valid(v, kind):
					(keys[p] if kind == "key" else pads[p])[a] = v
		custom[p] = true


## a player who never changed its mapping gets the defaults again (P1: the CONTROLS mapping in use now)
func refresh_defaults() -> void:
	for p in 2:
		if not custom[p]:
			reset(p)


func save_cfg(c: ConfigFile) -> void:
	c.set_value("mp", "devices_set", devices_set)
	for p in 2:
		c.set_value("mp", "p%d_device" % (p + 1), dev[p])
		if not custom[p]:
			continue
		for a in ORDER:
			c.set_value("mp", "p%d_%s_key" % [p + 1, a], keys[p][a])
			c.set_value("mp", "p%d_%s_pad" % [p + 1, a], pads[p][a])
