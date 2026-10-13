extends SceneTree
## Lockstep test of the translated game against reference RAM dumps from the original (melonDS).
##   godot --headless --path . --script res://tools/lockstep.gd -- ref=<dir> out=<dir> frames=N [rom=...]
##   [watch=addr+len,...] [trace=frame,...] [pxilog] [cardlog]
## <ref> comes from tools/melonds-headless/lockstep_ref.py. If it has frame_0000.io the game resumes from that
## snapshot (taken in NitroMain's vblank wait); a reference made with STATE=boot starts from power-on.
## The port presents one frame per vblank wait. Frames are matched by NitroMain's loop counter (0x020DD4C0) and,
## for nested waits inside one logic step, by the occurrence index: port frame (counter c, n-th wait with c)
## <-> the reference frame where the main thread waits with counter c for the n-th time. Reference frames
## that ended mid-logic have no counterpart (the port has no lag). Matched port frames are written as
## <out>/frame_<reference index>.ram; compare with decomp/tools/lockstep_cmp.py.

const INTRWAIT_PC := "0xffff0238"

var machine: DSMachine
var out: String
var args := {}
var _snap := PackedByteArray()


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var ref := String(args.get("ref", ""))
	out = String(args.get("out", "/tmp/lockstep_out"))
	var frames := int(args.get("frames", "1"))
	DirAccess.make_dir_recursive_absolute(out)
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string(ref.path_join("inputs.json")))
	# reference frames where the main thread waits, keyed by (counter, occurrence)
	var ref_key := {}
	var seen := {}
	for e in inputs:
		if bool(e.get("main_waiting", String(e.get("pc", INTRWAIT_PC)) == INTRWAIT_PC)):
			var c := int(e.get("counter", -1))
			var o := int(seen.get(c, 0))
			seen[c] = o + 1
			ref_key["%d/%d" % [c, o]] = int(e["frame"])
	var core := DSGame.new()
	machine = DSMachine.new(core)
	# RAM as at the emulator's frame end (before the next frame's visible lines and their HBlank handlers)
	machine.on_sync_before_display = func(): _snap = _ram_now()
	machine.hang_ms = int(args.get("hang_ms", "20000"))
	core.arm7.log_fifo = args.has("pxilog")
	core.hw.log_card = args.has("cardlog")
	core.fs_native = args.get("fsnative", "1") != "0"
	for w in String(args.get("watch", "")).split(",", false):
		var lohi := w.split("+")
		var lo := lohi[0].hex_to_int()
		core.watch.append([lo, lo + (int(lohi[1]) if lohi.size() > 1 else 1)])
	# the clock the reference was made with (tools/melonds-headless freezes the RTC there; the game reads it at
	# boot), so results do not change from run to run
	core.arm7.fixed_clock = Time.get_datetime_dict_from_datetime_string(String(args.get("rtc", "2026-01-01T12:00:00")), true)
	var rom := FileAccess.get_file_as_bytes(String(args.get("rom", _first("baseroms", "nds"))))
	core.arm7.backup = FileAccess.get_file_as_bytes(String(args.get("sav", _first("baseroms", "sav"))))
	var io_path := ref.path_join("frame_0000.io")
	var t0 := Time.get_ticks_usec()
	var start: Dictionary = {}
	if FileAccess.file_exists(ref.path_join("start.json")):
		start = JSON.parse_string(FileAccess.get_file_as_string(ref.path_join("start.json")))
	if not bool(start.get("boot", false)) and FileAccess.file_exists(io_path):
		machine.resume(FileAccess.get_file_as_bytes(ref.path_join("frame_0000.ram")),
			FileAccess.get_file_as_bytes(ref.path_join("frame_0000.dtcm")), FileAccess.get_file_as_bytes(io_path), rom)
	else:
		machine.boot(rom)
	var trace_frames := String(args.get("trace", "")).split(",", false)
	if args.has("break"):   # break=ADDR[:COUNT]: dump <out>/break.ram when that function is entered
		var bp := String(args["break"]).split(":")
		core.break_addr = bp[0].hex_to_int()
		core.break_count = int(bp[1]) if bp.size() > 1 else 1
		core._break_on = true
		core.on_break = func():
			_dump_named("break")
			print("LOCKSTEP break hit at %08x" % core.break_addr)
	var pos := 0                       # reference frame the port is aligned with
	var syncs: Array = []
	var port_seen := {}
	var c0 := int(machine.core.r16(0x020DD4C0))
	port_seen[c0] = 1
	for k in range(1, frames + 1):
		if pos + 1 > inputs.size():
			break
		# input: what the original read at the start of this logic step = the frame after the aligned one
		var inp: Dictionary = inputs[pos]
		machine.keyinput = int(inp["keyinput"])
		machine.ext_keys = int(inp["xy"])
		core.arm7.touch_raw = int(inp.get("touch_raw", 0))
		core._tracing = str(pos + 1) in trace_frames
		core.trace_log.clear()
		var t := Time.get_ticks_usec()
		if not machine.step():
			print("LOCKSTEP game thread ended: ", machine.error)
			break
		var c := int(core.r16(0x020DD4C0))
		var o := int(port_seen.get(c, 0))
		port_seen[c] = o + 1
		var key := "%d/%d" % [c, o]
		var fr: int = int(ref_key.get(key, -1))
		print("LOCKSTEP frame %d counter %d/%d -> ref %d  %.1f ms" % [k, c, o, fr, (Time.get_ticks_usec() - t) / 1000.0])
		if fr >= 0:
			pos = fr
			_dump(fr)
		else:
			pos += 1
		_dump_named("sync_%04d" % k)
		syncs.append({"sync": k, "counter": c})
		if core._tracing:
			var tf := FileAccess.open(out.path_join("trace_%04d.txt" % pos), FileAccess.WRITE)
			tf.store_string("\n".join(core.trace_log))
			tf.close()
	var sf := FileAccess.open(out.path_join("syncs.json"), FileAccess.WRITE)
	sf.store_string(JSON.stringify(syncs))
	sf.close()
	var hits: Array = core.hle_hits.keys()
	hits.sort()
	print("LOCKSTEP hle hits: ", ", ".join(hits.map(func(a): return "%08x x%d" % [a, core.hle_hits[a]])))
	if machine.core.prof_on:   # PROFILE=1 translation: busiest functions of the whole run
		var ps: Dictionary = machine.core.prof_self
		var pk := ps.keys()
		pk.sort_custom(func(x, y): return ps[x] > ps[y])
		for k in pk.slice(0, 25):
			print("PROF %08x %.1f ms, %d calls" % [k, ps[k] / 1000.0, machine.core.prof_calls[k]])
	print("LOCKSTEP fs path lookups native %d, original %d" % [core.fs_fast[0], core.fs_fast[1]])
	print("LOCKSTEP done in %.1f ms; missing functions hit: %s" % [(Time.get_ticks_usec() - t0) / 1000.0,
		", ".join(core._missing_seen.keys().map(func(a): return "%08x" % a))])
	print("LOCKSTEP arm7 unknown tags: ", core.arm7.unknown_seen.keys())
	quit()


func _ram_now() -> PackedByteArray:
	var c = machine.core
	var r: PackedByteArray = c.M.slice(0, 0x3FF000)
	r.append_array(c.M.slice(0x7FF000, 0x800000))   # system area from its 0x027FF000 mirror
	return r


## break points dump the live RAM; frame dumps use the snapshot taken at the emulator-equivalent frame end
func _dump_named(name: String) -> void:
	var f := FileAccess.open(out.path_join(name + ".ram"), FileAccess.WRITE)
	f.store_buffer(_snap if name.begins_with("sync_") else _ram_now())
	f.close()


func _dump(fr: int) -> void:
	var f := FileAccess.open(out.path_join("frame_%04d.ram" % fr), FileAccess.WRITE)
	f.store_buffer(_snap)
	f.close()


## first <folder>/*.<ext> of the repository (baseroms/ holds the user's ROM and original save)
static func _first(folder: String, ext: String) -> String:
	var root := ProjectSettings.globalize_path("res://").path_join("../..").path_join(folder).simplify_path()
	var d := DirAccess.open(root)
	if d:
		for f in d.get_files():
			if f.get_extension().to_lower() == ext:
				return root.path_join(f)
	return ""
