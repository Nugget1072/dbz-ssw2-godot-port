extends SceneTree
## Checks whether files are the ROM this port was made from (the same test the game runs on the files in its folder):
##   godot --headless --path GodotGame/new-game-project --script res://tools/check_rom.gd -- file=<path> [file=...]
func _process(_delta: float) -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("file="):
			var p := a.substr(5)
			var why: String = root.get_node("Assets").rom_problem(FileAccess.get_file_as_bytes(p))
			print("%s: %s" % [p, "OK" if why == "" else why])
	return true   # quit
