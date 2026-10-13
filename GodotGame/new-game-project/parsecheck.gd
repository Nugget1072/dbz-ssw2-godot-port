extends SceneTree
## Headless parse check: godot --headless --path . --script res://parsecheck.gd -- res://a.gd res://b.gd
## (runs on the first frame, after the autoloads Game/Assets/... exist, so scripts that use them compile)
func _process(_delta: float) -> bool:
	var bad := 0
	for p in OS.get_cmdline_user_args():
		var s: GDScript = load(p)
		var ok: bool = s != null and s.can_instantiate()
		if not ok:
			bad += 1
		print("PARSE ", "OK " if ok else "FAIL ", p)
	print("PARSE SUMMARY bad=", bad)
	return true
