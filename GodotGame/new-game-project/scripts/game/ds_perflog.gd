class_name DSPerfLog
extends Node
## Frame-time log for players (part 26): `perflog` on the command line (Steam launch options: `%command% -- perflog`)
## or the environment variable DBZ_PERFLOG=1 (Steam launch options: `DBZ_PERFLOG=1 %command%`). Every 5 s one line
## goes to stdout and to perflog.txt next to the game (user:// if that folder is read-only):
##   fps      displayed frames per second (Godot frames)
##   game     emulated frames per second (must stay ~59.8: lower = the game itself runs slow)
##   steps    game frames run per displayed frame: average, and how many displayed frames ran 0 / 1 / 2 / 3+
##   frame    time between displayed frames: average / 95th percentile / worst (ms)
##   run      game-thread time of one game frame (translated game + emulated hardware): average / worst (ms)
##   wait     main thread blocked waiting for the game thread, per displayed frame (ms)
##   main     main-thread time in GameDS._process per displayed frame (game frames not run ahead + picture upload)
##   pipe     % of game frames that ran while Godot drew the previous picture (GameDS pipelining)
##   render   CPU time Godot spent drawing the viewports; gpu: their GPU time (0 if the driver does not report it)
##   thread switches  DS thread switches per game frame (each one wakes another Godot thread)
## The first lines describe the machine: OS, Wine / Proton, CPU, GPU + driver, renderer, thread model, V-Sync.
## Part 32: a second line per period ("PERFLOG f<N> split") divides the work:
##   game thread, ms per game frame: arm9 (translated game code of every DS thread, DMA, the rest of the scanline
##     loop) + the scanline events tmr ARM9 timers, cap per-line 2D register capture, irq HBlank / VBlank handlers,
##     a7 ARM7 sound driver, mix sound mixer
##   main thread, ms per game frame: in (input for the frame), out (after the frame: qol QoL checks, aud audio
##     resampling, the rest 3D command queueing)
##   main thread, ms per displayed frame: pic (picture upload: 3d = waiting for the geometry worker + mesh build +
##     texture upload tex; the rest = the 2D engines' VRAM / palette / OAM / register textures)
##   geo: geometry engine (native, worker thread) ms per displayed frame
##   gap: main-thread time per displayed frame between the end of a pipelined game frame and the start of the next
##     one (the game thread idles then); cpu: process CPU time per game frame (all threads; Linux only, else -1)
## and "PERFLOG performance ..." lines say whether PERFORMANCE MODE (settings, BIG CHANGES) is on and what it does.

const PERIOD_US := 5000000

var game: Node                         ## GameDS
var run_us: int = 0                    ## accumulated by GameDS._tick_end (game-thread time of the game frames)
var wait_us: int = 0                   ## accumulated by GameDS._tick_end (main thread waiting for the game thread)
var step_us: int = 0                   ## (kept for GameDS: game frame + its bookkeeping on the main thread)
var step_max: int = 0
var pre_us: int = 0                    ## part 32 (GameDS): input before each game frame
var post_us: int = 0                   ## after each game frame (QoL + audio + 3D queue)
var qol_us: int = 0
var aud_us: int = 0
var pic_us: int = 0                    ## picture upload per displayed frame (GameDS._refresh)
var gap_us: int = 0                    ## GameDS pipelining: join -> next start (game thread idle)
var read_us: int = 0                   ## PERFORMANCE MODE: the reading half of pic_us (before the next game frame starts)
var gap2_us: int = 0                   ## the part of gap_us after GameDS._process (other nodes' scripts, Godot)
var _cpu0: float = -1.0
var _prev: Dictionary = {}             ## counters owned by DSMachine / DSArm7 / DSDisplay at the last line
var _run_max: int = 0
var _pipe_frames: int = 0
var _file: FileAccess
var _t0: int = 0
var _f0: int = 0                       ## game frames at _t0
var _sw0: int = 0                      ## DS thread switches at _t0
var _frames: int = 0                   ## displayed frames in this window
var _steps: int = 0
var _hist := PackedInt32Array([0, 0, 0, 0])
var _dts := PackedFloat32Array()       ## frame intervals (ms) in this window
var _last: int = 0
var _main_us: int = 0
var _main_max: int = 0
var _rcpu: float = 0.0
var _rgpu: float = 0.0
var _vps: Array[RID] = []


static func wanted() -> bool:
	return Game.args.has("perflog") or OS.get_environment("DBZ_PERFLOG") not in ["", "0"]


## Wine / Proton (the Windows build on Linux / Steam Deck): Wine passes these through to the Windows process
static func wine_info() -> String:
	var parts: PackedStringArray = []
	for k in ["STEAM_COMPAT_TOOL_PATHS", "STEAM_COMPAT_DATA_PATH", "WINEPREFIX", "WINEESYNC", "WINEFSYNC", "PROTON_NO_FSYNC",
			"PROTON_NO_ESYNC", "SteamDeck", "SteamOS", "WINE_CPU_TOPOLOGY"]:
		var v := OS.get_environment(k)
		if v != "":
			parts.append("%s=%s" % [k, v.get_file() if k == "STEAM_COMPAT_TOOL_PATHS" else v.left(60)])
	return ", ".join(parts)


func _ready() -> void:
	var dir := OS.get_executable_path().get_base_dir() if not OS.has_feature("editor") else "user://"
	_file = FileAccess.open(dir.path_join("perflog.txt"), FileAccess.WRITE)
	if _file == null:
		_file = FileAccess.open("user://perflog.txt", FileAccess.WRITE)
	var v := Engine.get_version_info()
	_out("PERFLOG start %s, Godot %s, %s %s, %s" % [Time.get_datetime_string_from_system(), v.string, OS.get_name(), OS.get_version(),
		OS.get_distribution_name()])
	var w := wine_info()
	_out("PERFLOG wine/proton: %s" % (w if w != "" else "not detected"))
	_out("PERFLOG cpu %s, %d threads; pipeline %s" % [OS.get_processor_name(), OS.get_processor_count(), Game.flag("pipeline", "auto")])
	_out("PERFLOG gpu %s / %s, API %s, driver %s, method %s, thread model %d, vsync %d, max_fps %d, refresh %.1f Hz, window %s mode %d" % [
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
		RenderingServer.get_video_adapter_api_version(), RenderingServer.get_current_rendering_driver_name(),
		RenderingServer.get_current_rendering_method(), int(ProjectSettings.get_setting("rendering/driver/threads/thread_model", 1)),
		DisplayServer.window_get_vsync_mode(), Engine.max_fps, DisplayServer.screen_get_refresh_rate(),
		DisplayServer.window_get_size(), DisplayServer.window_get_mode()])
	perf_mode_line()
	_vps = [get_viewport().get_viewport_rid()]
	if game.screen_root is Viewport:
		_vps.append((game.screen_root as Viewport).get_viewport_rid())
	if game.display != null:
		_vps.append(game.display.r3d.get_viewport_rid())
	for r in _vps:
		RenderingServer.viewport_set_measure_render_time(r, true)


## PERFORMANCE MODE (part 32) state: at the start and whenever it changes (GameDS.apply_perf_mode)
func perf_mode_line() -> void:
	if game != null and game.has_method("perf_mode_info"):
		_out("PERFLOG f%d performance %s" % [game.frames, game.perf_mode_info()])


## [scanlines, timers, capture, irq, ARM7 driver, mixer, 3D, texture upload, geometry wait, geometry work] (usec) since
## the last call
func _split_deltas() -> Array:
	var m: DSMachine = game.machine
	var a7 = m.core.arm7
	var d = game.display
	return [_delta("lines", m.t_lines), _delta("tmr", m.t_tmr), _delta("cap", m.t_cap), _delta("irq", m.t_irq),
		_delta("drv", a7.t_driver), _delta("mix", a7.t_mix), _delta("t3d", d.t_3d), _delta("tup", d.r3d.t_up),
		_delta("gw", d.r3d.t_gx), _delta("geo", d.r3d.t_gx_work)]


## CPU time of the whole process (ms; Linux /proc only, else -1): benchmarks that do not depend on other load
static func proc_cpu_ms() -> float:
	var f := FileAccess.open("/proc/self/stat", FileAccess.READ) if OS.get_name() == "Linux" else null
	if f == null:
		return -1.0
	var st := f.get_line()   # (/proc files report length 0: get_as_text would read nothing)
	var p := st.substr(st.rfind(")") + 2).split(" ")
	if p.size() < 13:
		return -1.0
	return (int(p[11]) + int(p[12])) * 10.0   # utime + stime, clock ticks (USER_HZ 100)


## counters kept elsewhere (they may also be reset by the `perf` flag's report: then count from 0)
func _delta(key: String, v: int) -> int:
	var p: int = _prev.get(key, 0)
	_prev[key] = v
	return v - p if v >= p else v


func _out(s: String) -> void:
	print(s)
	if _file != null:
		_file.store_line(s)
		_file.flush()


## debug (benchmarks): perfmark=F1,F2,... prints the process CPU time when game frame F is reached
var _marks: PackedInt32Array = PackedInt32Array(Array(Game.flag("perfmark").split(",", false)).map(func(x): return int(x)))


## per game frame, from GameDS._tick_end (before GameDS.frames counts it)
func game_frame(run: int, pipelined: bool) -> void:
	if not _marks.is_empty() and game.frames + 1 in _marks:
		print("PERFMARK f%d cpu %.0f ms" % [game.frames + 1, proc_cpu_ms()])
	run_us += run
	_run_max = maxi(_run_max, run)
	if pipelined:
		_pipe_frames += 1


## once per displayed frame, from GameDS._process: `steps` game frames ran, `main_us` time spent in GameDS._process
func frame(steps: int, main_us: int) -> void:
	var now := Time.get_ticks_usec()
	if _t0 == 0:
		_t0 = now
		_last = now
		_f0 = game.frames
		_sw0 = game.machine.switches
		run_us = 0
		wait_us = 0
		_run_max = 0
		_pipe_frames = 0
		_split_deltas()
		_cpu0 = proc_cpu_ms()
		gap_us = 0
		gap2_us = 0
		read_us = 0
		pre_us = 0
		post_us = 0
		qol_us = 0
		aud_us = 0
		pic_us = 0
		return
	_dts.append((now - _last) / 1000.0)
	_last = now
	_frames += 1
	_steps += steps
	_hist[mini(steps, 3)] += 1
	_main_us += main_us
	_main_max = maxi(_main_max, main_us)
	for r in _vps:
		_rcpu += RenderingServer.viewport_get_measured_render_time_cpu(r)
		_rgpu += RenderingServer.viewport_get_measured_render_time_gpu(r)
	if now - _t0 < PERIOD_US or _frames == 0:
		return
	var secs := (now - _t0) / 1e6
	var gf: int = maxi(game.frames - _f0, 1)
	var sorted := _dts.duplicate()
	sorted.sort()
	var n := float(_frames)
	_out("PERFLOG f%d fps %.1f game %.2f/s | steps %.2f/frame (0:%d 1:%d 2:%d 3+:%d) | frame %.1f p95 %.1f max %.1f ms | run %.2f max %.1f | wait %.2f | main %.2f max %.1f | pipe %d%% | render %.2f gpu %.2f ms | thread switches %.1f/frame" % [
		game.frames, n / secs, (game.frames - _f0) / secs, _steps / n, _hist[0], _hist[1], _hist[2], _hist[3],
		secs * 1000.0 / n, sorted[int(n * 0.95)], sorted[-1], run_us / 1000.0 / gf, _run_max / 1000.0, wait_us / 1000.0 / n,
		_main_us / 1000.0 / n, _main_max / 1000.0, _pipe_frames * 100 / gf, _rcpu / n, _rgpu / n,
		(game.machine.switches - _sw0) / float(gf)])
	var sd := _split_deltas()
	var g := float(gf) * 1000.0
	var cpu := proc_cpu_ms()
	var cpu_f := (cpu - _cpu0) / gf if cpu >= 0.0 and _cpu0 >= 0.0 else -1.0
	_cpu0 = cpu
	_out("PERFLOG f%d split | game thread /game frame: arm9 %.2f + scanlines: tmr %.2f cap %.2f irq %.2f a7 %.2f mix %.2f | main /game frame: in %.2f out %.2f (qol %.2f aud %.2f) | main /shown frame: pic %.2f (read %.2f; 3d %.2f: wait %.2f tex %.2f) | geo %.2f | gap %.2f (after GameDS %.2f) | cpu %.2f | performance %s" % [
		game.frames, maxf(run_us - sd[1] - sd[2] - sd[3] - sd[4] - sd[5], 0) / g, sd[1] / g, sd[2] / g, sd[3] / g, sd[4] / g, sd[5] / g,
		pre_us / g, post_us / g, qol_us / g, aud_us / g, pic_us / 1000.0 / n, read_us / 1000.0 / n, sd[6] / 1000.0 / n, sd[8] / 1000.0 / n,
		sd[7] / 1000.0 / n, sd[9] / 1000.0 / n, gap_us / 1000.0 / n, gap2_us / 1000.0 / n, cpu_f,
		("on, " + ("30 fps" if game.get("_half") else "60 fps")) if game.get("perf_mode") else "off"])
	gap_us = 0
	gap2_us = 0
	read_us = 0
	pre_us = 0
	post_us = 0
	qol_us = 0
	aud_us = 0
	pic_us = 0
	_sw0 = game.machine.switches
	_t0 = now
	_f0 = game.frames
	_frames = 0
	_steps = 0
	_hist = PackedInt32Array([0, 0, 0, 0])
	_dts.clear()
	_main_us = 0
	_main_max = 0
	run_us = 0
	wait_us = 0
	_run_max = 0
	_pipe_frames = 0
	step_us = 0
	step_max = 0
	_rcpu = 0.0
	_rgpu = 0.0
