extends SceneTree
## debug: prints DSGX's output triangles for the frames in a GameDS `gxdump=FROM:N` file (capture/gx.bin)
##   godot --headless --path GodotGame/new-game-project --script res://tools/dump_gx.gd -- gx=<gx.bin> [frame=K]
func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var f := FileAccess.open(String(args.get("gx", "")), FileAccess.READ)
	var frames: Array = f.get_var()
	var gx := DSGX.new()
	var k := 0
	for cmds in frames:
		gx.run(cmds, null)
		if not args.has("frame") or int(args["frame"]) == k:
			print("FRAME %d swaps %d verts %d" % [k, gx.swaps, gx.out_pos.size()])
			for i in range(0, gx.out_pos.size(), 3):
				print("  tri attr %08x tex %08x pal %x  col %s  pos %s %s %s  uv %s %s %s" % [gx.out_attr[i / 3] if gx.out_attr.size() > i / 3 else -1,
					gx.out_tex[i / 3] if gx.out_tex.size() > i / 3 else -1, gx.out_pal[i / 3] if gx.out_pal.size() > i / 3 else -1,
					gx.out_col[i], gx.out_pos[i], gx.out_pos[i + 1], gx.out_pos[i + 2], gx.out_uv[i], gx.out_uv[i + 1], gx.out_uv[i + 2]])
		k += 1
	quit()
