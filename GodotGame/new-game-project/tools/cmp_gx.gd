extends SceneTree
## debug: runs a GameDS gxdump (capture/gx.bin) through DSGX (GDScript) and DSGXNative and prints the first
## differing value per frame and output array (they must agree exactly)
##   godot --headless --path GodotGame/new-game-project --script res://tools/cmp_gx.gd -- gx=<gx.bin>
func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var frames: Array = FileAccess.open(String(args["gx"]), FileAccess.READ).get_var()
	var g := DSGX.new()
	var n = ClassDB.instantiate("DSGXNative")
	var fi := 0
	for cmds in frames:
		g.run(cmds, null)
		n.run(cmds)
		var a: Array = [g.out_pos, g.out_col, g.out_uv, g.out_attr, g.out_tex, g.out_pal, g.out_prev]
		var b: Array = [n.get_out_pos(), n.get_out_col(), n.get_out_uv(), n.get_out_attr(), n.get_out_tex(), n.get_out_pal(), n.get_out_prev()]
		for k in a.size():
			if a[k].size() != b[k].size():
				print("frame ", fi, " arr ", k, " size ", a[k].size(), " vs ", b[k].size())
				continue
			for i in a[k].size():
				if a[k][i] != b[k][i]:
					print("frame ", fi, " arr ", k, " idx ", i, ": ", a[k][i], " vs ", b[k][i])
					break
		fi += 1
	quit()
