extends SceneTree
## Headless: boot the translated game and print per-frame display statistics.
##   godot --headless --path . --script res://tools/dsstats.gd -- frames=N every=K nds=... sav=...
func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var core := DSGame.new()
	var m := DSMachine.new(core)
	m.hang_ms = 10000
	core.arm7.backup = FileAccess.get_file_as_bytes(String(args.get("sav", load("res://tools/lockstep.gd")._first("baseroms", "sav"))))
	m.boot(FileAccess.get_file_as_bytes(String(args.get("nds", load("res://tools/lockstep.gd")._first("baseroms", "nds")))))
	var gx := DSGX.new()
	var every := int(args.get("every", "50"))
	for k in range(1, int(args.get("frames", "600")) + 1):
		if not m.step():
			print("stopped: ", m.error)
			break
		if k % every == 0:
			gx.begin_frame()
			gx.run(core.gx_cmds, core)
			var objs_a := 0
			var objs_b := 0
			for i in 128:
				var a0: int = core.hw.oam.decode_u16(i * 8)
				if (a0 & 0x300) != 0x200:
					objs_a += 1
				var b0: int = core.hw.oam.decode_u16(0x400 + i * 8)
				if (b0 & 0x300) != 0x200:
					objs_b += 1
			var lists := 0
			for c in core.gx_cmds:
				if c[0] == -1:
					lists += 1
			print("frame %d: DISPCNT A %08x B %08x  3D cmds %d (lists %d) tris %d  OBJ A %d B %d  DISP3DCNT %04x  POW %04x" % [
				k, core.IO.decode_u32(0), core.IO.decode_u32(0x1000), core.gx_cmds.size(), lists, gx.out_pos.size() / 3,
				objs_a, objs_b, core.IO.decode_u16(0x60), core.IO.decode_u16(0x304)])
	quit()
