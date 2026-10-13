extends Node
## Scripted play-through for automated testing (autoload "Pilot"). Inactive unless launched with
##   -- pilot="run:60 press:A:4 shot:name ..." shots=<dir> [scene=res://...]
## The command syntax is the same as tools/melonds-headless/mhs.py, so one script drives both the
## original (in melonDS) and the port, and the screenshots can be compared frame for frame.
##   run:N              advance N frames with no input
##   press:A+Right:N    hold the listed DS buttons for N frames (default 4)
##   shot:name          save <shots>/<name>.png (both screens, 256x384)
##   quit               exit (implicit at the end)

var active: bool = false
var _cmds: PackedStringArray = []
var _held: PackedStringArray = []
var _prev_held: PackedStringArray = []
var _wait: int = 0
var _shots: String = ""
var frame: int = 0


func _ready() -> void:
	if not Game.args.has("pilot"):
		return
	active = true
	process_priority = -100
	process_physics_priority = -100
	_cmds = String(Game.args["pilot"]).split(" ", false)
	_shots = String(Game.args.get("shots", OS.get_user_data_dir().path_join("shots")))
	DirAccess.make_dir_recursive_absolute(_shots)
	if Game.args.has("mute") or true:
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	print("PILOT start: ", _cmds)


func _physics_process(_delta: float) -> void:
	if not active:
		return
	frame += 1
	_prev_held = _held.duplicate()
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			_held = []
		return
	while _cmds.size() > 0 and _wait == 0:
		var c := _cmds[0]
		_cmds.remove_at(0)
		var p := c.split(":")
		match p[0]:
			"run":
				_held = []
				_wait = int(p[1])
			"press", "hold":
				_held = p[1].split("+")
				_wait = int(p[2]) if p.size() > 2 else 4
			"shot":
				_shot.call_deferred(p[1])
			"quit":
				_finish()
			_:
				push_error("PILOT bad command " + c)
	if _cmds.size() == 0 and _wait == 0:
		_finish.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shots.path_join(name + ".png"))
	print("PILOT shot ", name, " frame ", frame)


var _finished := false


func _finish() -> void:
	if _finished:
		return
	_finished = true
	var snd := get_node_or_null("/root/Sound")
	if snd:
		print("PILOT music=", snd.current, " playing=", snd.music.playing,
			" len=", snd.music.stream.get_length() if snd.music.stream else 0.0)
	await get_tree().create_timer(0.3).timeout
	print("PILOT PASS")
	get_tree().quit()


func _has(b: String) -> bool:
	return _held.has(b)


func _pressed(b: String) -> bool:
	return _held.has(b) and not _prev_held.has(b)


func input_state() -> Dictionary:
	return {
		"left": _has("Left"), "right": _has("Right"), "up": _has("Up"), "down": _has("Down"),
		"a_pressed": _pressed("A"), "b_pressed": _pressed("B"), "x_pressed": _pressed("X"),
		"y_pressed": _pressed("Y"), "l_pressed": _pressed("L"), "r_pressed": _pressed("R"),
	}
