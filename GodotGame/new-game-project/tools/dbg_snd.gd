extends SceneTree
## debug: histogram of the SND commands the ARM9 sends (ids per NitroSDK SNDCommandID), first N frames
func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var core := DSGame.new()
	core.arm7.log_snd = true
	var m := DSMachine.new(core)
	core.arm7.backup = FileAccess.get_file_as_bytes(load("res://tools/lockstep.gd")._first("baseroms", "sav"))
	m.boot(FileAccess.get_file_as_bytes(load("res://tools/lockstep.gd")._first("baseroms", "nds")))
	var hist := {}
	var first := {}
	var t0 := Time.get_ticks_msec()
	for k in int(args.get("frames", "600")):
		m.hang_ms = 20000
		if not m.step():
			print("STOPPED ", m.error)
			break
		if k % 50 == 0:
			print("frame ", k, " ", Time.get_ticks_msec() - t0, " ms")
		for c in core.arm7.snd_commands:
			hist[c[0]] = int(hist.get(c[0], 0)) + 1
			if not first.has(c[0]):
				first[c[0]] = [k, c.slice(1).map(func(x): return "%x" % x)]
		core.arm7.snd_commands.clear()
	print("THREADS ", m._threads.keys().map(func(x): return "%x" % x), " line ", m._line)
	var ks := hist.keys()
	ks.sort()
	for id in ks:
		print("SND id 0x%02x x%d first frame %d args %s" % [id, hist[id], first[id][0], str(first[id][1])])
	quit()
