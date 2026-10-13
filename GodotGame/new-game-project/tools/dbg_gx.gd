extends SceneTree
## debug: boot, run N frames, summarise the frame's geometry commands and DSGX output
func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var core := DSGame.new()
	var m := DSMachine.new(core)
	core.arm7.backup = FileAccess.get_file_as_bytes(load("res://tools/lockstep.gd")._first("baseroms", "sav"))
	m.boot(FileAccess.get_file_as_bytes(load("res://tools/lockstep.gd")._first("baseroms", "nds")))
	var n := int(args.get("frames", "600"))
	for k in n - 1:
		m.step()
	if args.has("hookval"):
		var hv: int = String(args["hookval"]).hex_to_int()
		core.io_hook = func(a, _s, v):
			if a >= 0x4000400 and a < 0x4000440 and v == hv:
				print("HOOK %x=%x " % [a, v], core.trace_stack if core.trace_stack != "" else "", get_stack().slice(1, 8).map(func(d): return "%s:%d" % [d["function"], d["line"]]))
	m.step()
	var hist := {}
	for c in core.gx_cmds:
		var key := "dl" if c[0] == -1 else "%x" % c[0]
		hist[key] = int(hist.get(key, 0)) + 1
	print("GX cmds ", core.gx_cmds.size(), " ", hist)
	print("DISP3DCNT %x DISPCNT %x MB %x BLDCNT %x BLDY %x MB_B %x" % [core.IO.decode_u16(0x60), core.IO.decode_u32(0), core.IO.decode_u16(0x6C), core.IO.decode_u16(0x50), core.IO.decode_u16(0x54), core.IO.decode_u16(0x106C)])
	var gx := DSGX.new()
	gx.begin_frame()
	gx.run(core.gx_cmds, core)
	print("GX verts ", gx.out_pos.size())
	if args.has("tris"):
		for t in range(0, gx.out_pos.size(), 3):
			var xs := []
			var ys := []
			for k in 3:
				xs.append(snappedf((gx.out_pos[t + k].x / gx.out_pos[t + k].w + 1.0) * 128.0, 0.1))
				ys.append(snappedf((1.0 - gx.out_pos[t + k].y / gx.out_pos[t + k].w) * 96.0, 0.1))
			print("  tri z%.6f x%s y%s tex %x pal %x attr %x col %s uv %s" % [gx.out_pos[t].z, str(xs), str(ys), gx.out_tex[t], gx.out_pal[t], gx.out_attr[t], gx.out_col[t].to_html(), str([gx.out_uv[t], gx.out_uv[t + 1], gx.out_uv[t + 2]])])
	if args.has("texdump"):   # texdump=TEXIMAGE_PARAM:PLTT_BASE -> /tmp/claude-0/tex.png (formats 2,3,4,7)
		var tv := core.hw.tex_view()
		var pv := core.hw.texpal_view()
		var pr := String(args["texdump"]).split(":")
		var tp := pr[0].hex_to_int()
		var pal := pr[1].hex_to_int()
		var fmt := (tp >> 26) & 7
		var w := 8 << ((tp >> 20) & 7)
		var h := 8 << ((tp >> 23) & 7)
		var base := (tp & 0xFFFF) * 8
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var nz := 0
		for y in h:
			for x in w:
				var i := 0
				var pb := pal * 16
				match fmt:
					2:
						i = (tv[base + ((y * w + x) >> 2)] >> ((x & 3) * 2)) & 3
						pb = pal * 8
					3: i = (tv[base + ((y * w + x) >> 1)] >> ((x & 1) * 4)) & 15
					4: i = tv[base + y * w + x]
				if i != 0: nz += 1
				var c := pv.decode_u16(pb + i * 2)
				img.set_pixel(x, y, Color((c & 31) / 31.0, ((c >> 5) & 31) / 31.0, ((c >> 10) & 31) / 31.0, 0.0 if i == 0 else 1.0))
		img.save_png("/tmp/claude-0/tex.png")
		print("TEX fmt %d %dx%d base %x nonzero %d slots %s" % [fmt, w, h, base, nz, str(core.hw.tex_slots)])
	for i in min(gx.out_pos.size(), int(args.get("show", "12"))):
		print("  ", gx.out_pos[i], " ", gx.out_col[i], " uv ", gx.out_uv[i], " tex %x attr %x" % [gx.out_tex[i], gx.out_attr[i]])
	if args.has("dump"):
		for c in core.gx_cmds.slice(0, int(args["dump"])):
			print("  cmd %x %x %s" % [c[0] & 0xFFFFFFFF, c[1], str(c[2]) if c.size() > 2 else ""])
	m.stop() if m.has_method("stop") else null
	quit()
