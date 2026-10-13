class_name QoLControls
extends RefCounted
## Player-configurable controls (part 16, settings page 2 → CONTROLS). Every DS button (Godot input action ds_*)
## has one keyboard key and one gamepad input (a button, or a stick / trigger direction). The defaults are the
## project's own input map (project.godot), read once at startup, so DEFAULT always gives back exactly the
## original layout. Saved in settings.cfg, section [controls] ("k:<physical keycode>", "b:<button>",
## "a:<axis>:<+1/-1>", "" = none).

## [action, DS button, what it does] in menu order. The battle meanings were checked in the port (part 16, see
## DATA_NOTES): pressing each button alone in a Free Battle and reading the fighter's action.
const BUTTONS := [
	["ds_a", "A", "KI BLAST"],
	["ds_b", "B", "GUARD"],
	["ds_x", "X", "DASH"],
	["ds_y", "Y", "ATTACK"],
	["ds_l", "L", "POWER UP"],
	["ds_r", "R", "CHARGE KI"],
	["ds_start", "START", "PAUSE"],
	["ds_select", "SELECT", "(UNUSED)"],
	["ds_up", "UP", "MOVE UP"],
	["ds_down", "DOWN", "MOVE DOWN"],
	["ds_left", "LEFT", "MOVE LEFT"],
	["ds_right", "RIGHT", "MOVE RIGHT"],
]
## The gamepad mouse cursor of the touch screen (part 24, CONTROLS page 3, QoLCursor): its four directions and its
## click are input actions too ([action, short name, what it is]); defaults: right stick + right-stick press, no
## keys (project.godot has none of these, and no ds_* action uses the right stick or R3).
const CURSOR_ACTIONS := [
	["qol_cur_up", "UP", "CURSOR UP"],
	["qol_cur_down", "DOWN", "CURSOR DOWN"],
	["qol_cur_left", "LEFT", "CURSOR LEFT"],
	["qol_cur_right", "RIGHT", "CURSOR RIGHT"],
	["qol_cur_click", "CLICK", "TOUCH"],
]
const CURSOR_DEFAULTS := {
	"qol_cur_up": {"key": "", "pad": "a:3:-1"},
	"qol_cur_down": {"key": "", "pad": "a:3:1"},
	"qol_cur_left": {"key": "", "pad": "a:2:-1"},
	"qol_cur_right": {"key": "", "pad": "a:2:1"},
	"qol_cur_click": {"key": "", "pad": "b:8"},     # JOY_BUTTON_RIGHT_STICK
}
const CURSOR_DEADZONE := 0.2              ## stick directions of the cursor (QoLCursor applies its own radial deadzone)
const CURSOR_SPEED_DEFAULT := 5            ## SPEED 1..5 (part 25: 5, was 3)
var cursor_enabled := true                 ## CONTROLS page 3: the cursor is shown while a gamepad is connected
var cursor_speed := CURSOR_SPEED_DEFAULT

## keys the player cannot assign (the port's own: F3 FPS counter, F11 full screen; Escape cancels a mapping)
const RESERVED := [KEY_F3, KEY_F11, KEY_ESCAPE]
const AXIS_DEADZONE := 0.5

var defaults := {}      ## action -> {"key": code, "pad": code}
var map := {}           ## action -> {"key": code, "pad": code} in use


func _init() -> void:
	for b in BUTTONS:
		var d := {"key": "", "pad": ""}
		var setting = ProjectSettings.get_setting("input/" + b[0], {})
		if setting is Dictionary:
			for e in setting.get("events", []):
				var c := code_of(e)
				if c.begins_with("k:") and d["key"] == "":
					d["key"] = c
				elif (c.begins_with("b:") or c.begins_with("a:")) and d["pad"] == "":
					d["pad"] = c
		defaults[b[0]] = d
	for c in CURSOR_ACTIONS:
		defaults[c[0]] = CURSOR_DEFAULTS[c[0]].duplicate()
	reset()


## DEFAULT (CONTROLS page 2): every DS button and the cursor back to the original layout, cursor ON, speed 5
func reset() -> void:
	for a in defaults:
		map[a] = defaults[a].duplicate()
	cursor_enabled = true
	cursor_speed = CURSOR_SPEED_DEFAULT


func is_default() -> bool:
	for a in defaults:
		if map[a] != defaults[a]:
			return false
	return cursor_enabled and cursor_speed == CURSOR_SPEED_DEFAULT


## the menu / notices' name of an action ("A", "CURSOR UP", ...)
static func label_of(action: String) -> String:
	for b in BUTTONS:
		if b[0] == action:
			return b[1]
	for c in CURSOR_ACTIONS:
		if c[0] == action:
			return c[2] if c[0] != "qol_cur_click" else "CURSOR CLICK"
	return action


func load_cfg(c: ConfigFile) -> void:
	for a in defaults:
		for kind in ["key", "pad"]:
			var v := str(c.get_value("controls", "%s_%s" % [a, kind], map[a][kind]))
			if v == "" or _valid(v, kind):
				map[a][kind] = v
	var on = c.get_value("controls", "cursor_enabled", cursor_enabled)
	cursor_enabled = on if on is bool else str(on).strip_edges().to_lower() in ["true", "1", "yes", "on"]
	var sp := str(c.get_value("controls", "cursor_speed", cursor_speed))
	cursor_speed = clampi(int(sp), 1, 5) if sp.is_valid_int() else CURSOR_SPEED_DEFAULT
	# part 25: the default became 5. Files from part 24 always stored a speed (3 unless changed) and no
	# "cursor_speed_v" key: move them to the new default once
	if not c.has_section_key("controls", "cursor_speed_v"):
		cursor_speed = CURSOR_SPEED_DEFAULT


func save_cfg(c: ConfigFile) -> void:
	for a in defaults:
		for kind in ["key", "pad"]:
			c.set_value("controls", "%s_%s" % [a, kind], map[a][kind])
	c.set_value("controls", "cursor_enabled", cursor_enabled)
	c.set_value("controls", "cursor_speed", cursor_speed)
	c.set_value("controls", "cursor_speed_v", 2)


func _valid(v: String, kind: String) -> bool:
	var p := v.split(":")
	if kind == "key":
		return p.size() == 2 and p[0] == "k" and p[1].is_valid_int() and int(p[1]) > 0
	return (p.size() == 2 and p[0] == "b" and p[1].is_valid_int()) or (p.size() == 3 and p[0] == "a" and p[1].is_valid_int() and p[2] in ["1", "-1"])


## the Godot input map as `map` says (keys by physical position, like project.godot)
func apply() -> void:
	for a in defaults:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.2)
		InputMap.action_erase_events(a)
		for kind in ["key", "pad"]:
			var e := event_of(map[a][kind])
			if e != null:
				InputMap.action_add_event(a, e)
		var dz := AXIS_DEADZONE if map[a]["pad"].begins_with("a:") else 0.2
		if a.begins_with("qol_cur_") and a != "qol_cur_click":
			dz = CURSOR_DEADZONE
		InputMap.action_set_deadzone(a, dz)


## an input event -> "k:..", "b:..", "a:..:±1" ("" = not usable for a mapping)
static func code_of(e: InputEvent) -> String:
	if e is InputEventKey:
		var k: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		return "k:%d" % k if k != 0 else ""
	if e is InputEventJoypadButton:
		return "b:%d" % e.button_index
	if e is InputEventJoypadMotion:
		return "a:%d:%d" % [e.axis, 1 if e.axis_value > 0 else -1]
	return ""


static func event_of(c: String) -> InputEvent:
	var p := c.split(":")
	match p[0]:
		"k":
			var e := InputEventKey.new()
			e.physical_keycode = int(p[1])
			return e
		"b":
			var e := InputEventJoypadButton.new()
			e.button_index = int(p[1])
			e.device = -1
			return e
		"a":
			var e := InputEventJoypadMotion.new()
			e.axis = int(p[1])
			e.axis_value = float(p[2])
			e.device = -1
			return e
	return null


## Assign `code` to `action`'s key or pad slot. If another button already uses it, that button gets `action`'s
## old input instead (swap), so no DS button is ever left without its input by accident. (The cursor's key slots are
## empty by default: a key taken from a DS button for the cursor leaves that button without a key; the menu says so.)
func assign(action: String, kind: String, code: String) -> String:
	var old: String = map[action][kind]
	var swapped := ""
	for a in map:
		if a != action and map[a][kind] == code:
			map[a][kind] = old
			swapped = a
	map[action][kind] = code
	return swapped


## a raw event while the menu waits for a new input: the code to assign, "cancel", or "" (ignore the event)
func capture(e: InputEvent, kind: String) -> String:
	if e is InputEventKey:
		if not e.pressed or e.echo:
			return ""
		if e.keycode == KEY_ESCAPE or e.physical_keycode == KEY_ESCAPE:
			return "cancel"
		if kind != "key" or (e.keycode in RESERVED) or (e.physical_keycode in RESERVED):
			return ""
		return code_of(e)
	if kind != "pad":
		return ""
	if e is InputEventJoypadButton and e.pressed:
		return code_of(e)
	if e is InputEventJoypadMotion and absf(e.axis_value) >= 0.75:
		return code_of(e)
	return ""


const _PAD_BUTTONS := ["A", "B", "X", "Y", "BACK", "GUIDE", "START", "L-STICK", "R-STICK", "LB", "RB", "D-UP",
	"D-DOWN", "D-LEFT", "D-RIGHT", "MISC", "PADDLE1", "PADDLE2", "PADDLE3", "PADDLE4", "TOUCH"]
const _KEY_SHORT := {"BACKSPACE": "BKSP", "CAPSLOCK": "CAPS", "PAGEUP": "PG UP", "PAGEDOWN": "PG DN",
	"INSERT": "INS", "DELETE": "DEL", "ESCAPE": "ESC", "QUOTELEFT": "`", "APOSTROPHE": "'", "SEMICOLON": ";",
	"COMMA": ",", "PERIOD": ".", "SLASH": "/", "BACKSLASH": "\\", "BRACKETLEFT": "[", "BRACKETRIGHT": "]",
	"MINUS": "-", "EQUAL": "=", "NUMLOCK": "NUM", "SCROLLLOCK": "SCRL", "SPACE": "SPACE", "CTRL": "CTRL",
	"SHIFT": "SHIFT", "ENTER": "ENTER", "KP ENTER": "N.ENT", "TAB": "TAB", "HOME": "HOME", "END": "END",
	"LEFT": "LEFT", "RIGHT": "RIGHT", "UP": "UP", "DOWN": "DOWN", "META": "WIN", "MENU": "MENU", "PAUSE": "PAUSE",
	"PRINT": "PRINT", "SECTION": "§"}


## short name for the menu's boxes (fits about 6 characters)
static func name_of(c: String) -> String:
	if c == "":
		return "-"
	var p := c.split(":")
	match p[0]:
		"k":
			var s := OS.get_keycode_string(int(p[1])).to_upper()
			if s.begins_with("KP "):
				s = "NUM" + s.substr(3) if s.length() <= 5 else _KEY_SHORT.get(s, "N." + s.substr(3, 3))
			return _KEY_SHORT.get(s, s.left(6))
		"b":
			var i := int(p[1])
			return _PAD_BUTTONS[i] if i < _PAD_BUTTONS.size() else "BTN%d" % i
		"a":
			var ax := int(p[1])
			var plus := p[2] == "1"
			match ax:
				0: return "LS " + ("R" if plus else "L")
				1: return "LS " + ("D" if plus else "U")
				2: return "RS " + ("R" if plus else "L")
				3: return "RS " + ("D" if plus else "U")
				4: return "LT"
				5: return "RT"
			return "AX%d%s" % [ax, "+" if plus else "-"]
	return "?"
