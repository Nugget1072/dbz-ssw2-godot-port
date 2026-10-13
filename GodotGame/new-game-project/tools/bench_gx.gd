extends SceneTree
## debug/benchmark: replays geometry command streams saved by GameDS `gxdump=FROM:N` (capture/gx.bin) through
## DSGX, prints the time per frame and a hash of the output (must stay identical when optimising DSGX).
##   godot --headless --path GodotGame/new-game-project --script res://tools/bench_gx.gd -- gx=<gx.bin> [reps=3]
func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var f := FileAccess.open(String(args.get("gx", "")), FileAccess.READ)
	var frames: Array = f.get_var()
	var reps := int(args.get("reps", "3"))
	var best := 1 << 62
	var digest := ""
	var verts := 0
	for r in reps:
		var gx = ClassDB.instantiate("DSGXNative") if args.has("native") else DSGX.new()
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_MD5)
		var t := 0
		verts = 0
		for cmds in frames:
			var t0 := Time.get_ticks_usec()
			if args.has("native"):
				gx.run(cmds)
			else:
				gx.run(cmds, null)
			t += Time.get_ticks_usec() - t0
			var outs: Array = [gx.get_out_pos(), gx.get_out_col(), gx.get_out_uv(), gx.get_out_attr(), gx.get_out_tex(),
				gx.get_out_pal()] if args.has("native") else [gx.out_pos, gx.out_col, gx.out_uv, gx.out_attr, gx.out_tex, gx.out_pal]
			verts += (outs[0] as PackedVector4Array).size()
			for arr in outs:
				ctx.update(var_to_bytes(arr))
		best = mini(best, t)
		digest = ctx.finish().hex_encode()
	var cmdn := 0
	for cmds in frames:
		for c in cmds:
			cmdn += (c[3] as PackedInt32Array).size() if c[0] == -1 else 1
	print("BENCH frames %d, words %d/frame, verts %d/frame: %.3f ms/frame  md5 %s" % [frames.size(),
		cmdn / frames.size(), verts / frames.size(), best / 1000.0 / frames.size(), digest])
	quit()
