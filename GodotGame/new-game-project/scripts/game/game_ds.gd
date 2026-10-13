extends Node2D
## The port running the original game: boots the translated ARM9 program (DSMachine), steps it once per
## 60 Hz tick with the player's input and draws both screens from the emulated hardware (DSDisplay).

const KEY_ORDER := ["ds_a", "ds_b", "ds_select", "ds_start", "ds_right", "ds_left", "ds_up", "ds_down", "ds_r", "ds_l"]
const PILOT_NAMES := ["A", "B", "Select", "Start", "Right", "Left", "Up", "Down", "R", "L"]

var machine: DSMachine
var display: DSDisplay
## The game's save memory. Exported game: DBZ_SSW2_Port.sav next to the exe (user:// if that folder is read-only);
## editor runs: user://save100.sav; `save=PATH` overrides. A missing or damaged file is recreated from the completed
## save (100Save/ folder, else the copy built into the game, res://data/save100.sav), so everything stays unlocked.
var save_path := "user://save100.sav"
var frames: int = 0
var _gx_frames: Array = []
var qol: QoLController
var screen_root: Node = self              ## parent of everything drawn in DS space (see _ready)
var presenter: DSPresenter = null                ## settings menu, sound switches, jukebox (scripts/qol); null in tools
var smooth: bool = false:            ## QoL frame rates above 60: draw in-between frames (smooth motion)
	set(v):
		smooth = v
		if display != null:
			display.smooth = v
			if not v:
				display.set_interp(1.0)


func _ready() -> void:
	var core: DSGame = DSGame.new() if Game.args.has("noqol") else QoLGame.new()   # QoLGame: DSGame + cheat hooks
	core.fs_native = Game.flag("fsnative", "1") != "0"   # debug: fsnative=0 = translated FSi_FindPath
	machine = DSMachine.new(core)
	machine.hang_ms = 10000
	var rom := Assets.rom_bytes()
	if rom.is_empty():
		_rom_missing()
		return
	if Game.args.has("save"):
		save_path = Game.flag("save")
	elif not OS.has_feature("editor"):
		save_path = OS.get_executable_path().get_base_dir().path_join("DBZ_SSW2_Port.sav")
	core.arm7.backup = Assets.save_bytes(save_path)
	if not Game.args.has("capture") and not core.arm7.backup.is_empty():   # (re)create the save file right away
		var fs := FileAccess.open(save_path, FileAccess.READ)
		var ok := fs != null and fs.get_length() == core.arm7.backup.size()
		fs = null
		if not ok:
			core.arm7.backup_dirty = true   # written by the first _tick (falls back to user:// if read-only)
	# rtc=YYYY-MM-DDTHH:MM:SS freezes the clock (the game seeds its random numbers from it); capture runs
	# default to the clock tools/melonds-headless freezes, so both sides make the same random choices
	var rtc := Game.flag("rtc", "2026-01-01T12:00:00" if Game.args.has("capture") else "")
	if rtc != "":
		core.arm7.fixed_clock = Time.get_datetime_dict_from_datetime_string(rtc, true)
	# without V-Sync (switched off in the driver, or `vsync=0`) Godot would draw thousands of frames a second for a
	# 60 Hz game: cap it (pacing does not depend on it; this only saves CPU/GPU)
	Engine.max_fps = int(Game.flag("maxfps", "240"))
	if Game.flag("vsync", "1") == "0":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# the DS picture is drawn at 256x384 in `screen_root`: the root window itself for captures / headless runs,
	# else a SubViewport shown by DSPresenter (whole-multiple scaling in a window, sharp "fit" in full screen)
	if not Game.args.has("capture") and not Game.args.has("snap") and DisplayServer.get_name() != "headless" \
			and Game.flag("present", "1") != "0":
		var vp := SubViewport.new()
		vp.size = Vector2i(256, 384)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		add_child(vp)
		screen_root = vp
		presenter = DSPresenter.new(vp)
		add_child(presenter)
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	display = DSDisplay.new()
	display.machine = machine
	display.single_screen = Game.single_screen
	screen_root.add_child(display)
	display.r3d.threaded = Game.flag("gxthread", "1") != "0"   # geometry engine on a worker thread (default)
	# audio: the ARM7 mixer output (32768 Hz stereo) streamed through a generator
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = DSSound.MIX_RATE
	gen.buffer_length = 0.2
	_audio = AudioStreamPlayer.new()
	_audio.stream = gen
	add_child(_audio)
	_audio.play()
	_playback = _audio.get_stream_playback()
	_audio_cap = _playback.get_frames_available()
	if Game.args.has("iohook"):   # debug: iohook=ADDR[+LEN] prints the call stack of IO/VRAM writes there
		var spec := Game.flag("iohook").split("+")
		var lo := spec[0].hex_to_int()
		var hi := lo + (spec[1].hex_to_int() if spec.size() > 1 else 4)
		var from := int(Game.flag("iohook_from", "0"))
		var want: int = Game.flag("iohook_val", "-1").hex_to_int() if Game.args.has("iohook_val") else -1
		core.io_hook = func(a, sz, v):
			if frames >= from and a < hi and a + sz > lo and (want < 0 or v == want):
				var k := "%d %07x %d" % [frames, a >> 12, sz]
				if not _hook_seen.has(k) or Game.args.has("iohook_all"):   # first write per frame / 4 KiB page / size (iohook_all: every write)
					_hook_seen[k] = true
					print("IOHOOK f%d %08x <- %x (%d) " % [frames, a, v, sz], get_stack().slice(1, 11).map(func(d): return "%s:%d" % [d["function"], d["line"]]))
	core.arm7.log_snd = Game.args.has("sndlog")
	machine.boot(rom)
	if Game.args.has("capinterp"):
		display.smooth = true
	_pipe_setup()   # (before the QoL layer: PERFORMANCE MODE from the settings needs to know)
	if not Game.args.has("noqol"):
		qol = QoLController.new()
		add_child(qol)
		qol.setup(self, machine, rom)
	for e in Game.flag("inputs").split(",", false):
		var p := e.split(":")
		_script_keys.append([int(p[0]), p[1].split("+"), int(p[2]) if p.size() > 2 else 4])
	if DSPerfLog.wanted():   # part 26: `perflog` / DBZ_PERFLOG=1 -> frame-time lines in perflog.txt next to the game
		_plog = DSPerfLog.new()
		_plog.game = self
		add_child(_plog)
	# part 32: scanline timers only when someone reads them (`noprof`: perflog without them, CPU benchmarks)
	machine.prof = Game.args.has("perf") or (_plog != null and not Game.args.has("noprof"))
	machine.core.arm7.prof = machine.prof
	if Game.args.has("fakeslow"):   # debug (part 32): fakeslow=MS makes every game frame MS longer (a slower CPU's game thread)
		machine.fake_slow_us = int(float(Game.flag("fakeslow")) * 1000.0)


## No usable ROM: say on screen where to put it (the port contains no game data of its own).
func _rom_missing() -> void:
	machine = null
	var msg := "DRAGON BALL Z\nSUPERSONIC WARRIORS 2\n\nGame ROM not found.\n\nPut your own dump of the European cartridge " \
		+ "(any file name, e.g. game.nds) in the game's folder:\n\n%s\n\nthen start the game again." % Assets.rom_folder
	if not Assets.rom_rejected.is_empty():
		msg += "\n\nNot usable:\n" + "\n".join(Assets.rom_rejected)
	printerr(msg)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.12)
	bg.size = Vector2(256, 384)
	add_child(bg)
	var label := Label.new()
	label.text = msg
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(8, 8)
	label.size = Vector2(240, 368)
	label.add_theme_font_size_override("font_size", 11)
	add_child(label)


## Frame-exact capture for comparisons with melonDS (tools/melonds-headless): `capture=<dir> cap_every=N
## cap_to=M [cap_from=A]` saves <dir>/p<frame>.png after the game's frame <frame> is drawn, pausing the game
## while the screenshot is taken, then quits after frame M.
var _busy := false
var _script_keys: Array = []
var _hook_seen: Dictionary = {}
var _last_chmask: int = -1
var _t_step: int = 0
var _audio: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
const AUDIO_TARGET := 2300                ## queued samples to aim for (70 ms at 32768 Hz)
var _audio_cap: int = 0                   ## generator buffer size in samples
var _audio_last := Vector2.ZERO           ## last input sample of the previous frame (interpolation)
var _audio_phase: float = 0.0             ## resampling position carried into the next frame
var _wav := PackedVector2Array()      ## capture mode: all audio, saved as <capture>/audio.wav at the end
var _t_draw: int = 0


## Frame pacing: captures and pilots step once per physics tick (frame-exact, deterministic). Normal play steps
## from _process with a fixed-timestep accumulator: game speed is the DS's 59.8261 frames per real second on any PC,
## whatever the display does (60/75/120/144/240 Hz, V-Sync forced off, variable refresh). Time is only ever
## consumed, never created: the accumulator may go below zero (rounding lets a step start up to half a period
## early, which absorbs V-Sync jitter) and that debt is paid back. When the frames really arrive once per refresh
## of a ~60 Hz display the period is the display's own (one game frame per refresh, no judder from 59.83 vs 60).
## A slow PC catches up with at most 8 steps per refresh; a longer stall (loading) is dropped, not fast-forwarded.
## Debug: `fakehz=N` pretends the display runs at N Hz, `maxfps=N` caps Godot's frame rate (0 = uncapped),
## `vsync=0` turns V-Sync off, `pacelog` prints game frames per real second every 5 s.
const DS_HZ := 59.8261
var _free_run: bool = not Game.args.has("capture") and not Game.args.has("pilot") and not Game.args.has("turbo")   ## turbo: debug, one game frame per Godot frame (with --fixed-fps: CPU benchmarks)
var _acc: float = 0.0
var _dt_avg: float = 0.0                 ## smoothed frame time (is the display really driving the frames?)
var _pace_t0: int = 0                    ## pacelog: start of the measuring window (usec) and frames at that time
var _pace_f0: int = 0
var _next_snap: int = 0


func _physics_process(_delta: float) -> void:
	if not _free_run:
		_tick()
		if _lan_stalled:   # part 30 LAN: waiting for the other machine (turbo / captures: do not spin)
			OS.delay_msec(1)


## Pipelining (part 26, Steam Deck / slow CPUs): without it one displayed frame costs game frame + picture upload +
## Godot drawing + present, one after the other on the main thread, so a PC whose game frame alone takes most of a
## 60 Hz refresh (Steam Deck in battle: ~13-16 ms) misses refreshes and the catch-up steps make it worse (40 / 17 fps).
## With it the game thread already runs the next game frame while Godot draws and presents the current picture
## (started from RenderingServer.frame_pre_draw, after every script of the frame ran; joined before anything can
## touch game memory again: SceneTree.process_frame / physics_frame and GameDS._input). The game sees the same input
## per frame and the same frames, only the input is read up to one display frame earlier, so "auto" uses it only
## where it is needed: displayed frames come late (more than 1.3 game periods apart in over 10 % of the frames,
## smoothed) while a game frame takes over 30 % of a period; off again when game frames take under 20 %. A fast PC
## (never late) never uses it. `pipeline=0` never, `pipeline=1` always; captures / pilots / turbo / snap never
## (frame-exact paths); headless runs never draw, so never either.
var _pipe_mode: String = Game.flag("pipeline", "auto")
var _pipe_auto: bool = false             ## auto mode: currently on
var _inflight: bool = false              ## a game frame is running on the game thread while Godot draws
var _ahead: int = 0                      ## game frames already run for the next _process
var _period: float = 1.0 / DS_HZ         ## last game-frame period used by the pacing
var _run_ema: float = 0.0                ## smoothed game-thread time per game frame (usec)
var _late_ema: float = 0.0               ## smoothed fraction of displayed frames that came late
var _t_begin: int = 0                    ## _tick_begin -> _tick_end
var _began: bool = false
var _t_idle0: int = 0                    ## when the last game frame's bookkeeping ended (the game thread idles from then)
var _t_proc_end: int = 0                 ## perflog: end of GameDS._process
var _gap_ema: float = 0.0                ## smoothed main-thread time between a frame's end and the next pipelined start (usec)
var _pipe_on: bool = false               ## the pipelining signals are connected (not a frame-exact run, not pipeline=0)


## PERFORMANCE MODE (part 32; settings BIG CHANGES, QoLSettings.performance_mode, set by QoLController.apply_performance;
## debug `perfmode=1`). Only cheaper ways of doing the same game frames - the game's input, frames and memory are the
## same as without it (nothing here touches the emulated machine):
##  1. pipelining always on (not only when frames come late), so drawing never waits for the game frame;
##  2. the picture's Godot-side work (texture uploads, 3D mesh, shader parameters: DSDisplay.refresh_apply) runs
##     after the next game frame was started, only the reading of the emulated state (refresh_read) before it: the
##     game thread waits less for the main thread;
##  3. no in-between frames (FRAME RATE above 60 acts as 60: QoLController.apply_display);
##  4. (debug `perfhalf=auto`, off by default - see below) steady half rate: when the game frames do not fit one per 60 Hz
##     refresh any more (over 35 % of the pictures
##     late, i.e. under ~45 fps, smoothed over ~2 s, while a game frame + the main thread's gap before the next one take
##     over 90 % of a refresh) but two of them fit in one 30 fps picture (2 game frames + the gap under 95 % of 2
##     refreshes), the picture is held at 30 fps (Engine.max_fps 30: exactly 2 game frames per picture instead of an
##     uneven 1 / 2 / 3 mix, and the picture work once per 2 game frames); back to 60 when one game frame fits in 80 %
##     of a refresh (2 s), or when not even 2 per picture fit any more; at least 3 s between switches. Game speed stays
##     59.83 / s either way.
## Frame-exact runs (captures, turbo, pilots) never pipeline. The half rate is not on by default: measured with Deck-like
## game frames (13-14 ms, docs/TOOLING.md part 32) it gave mostly-2-step pictures but 22-29 fps instead of 27-48 at the
## same game speed (57-60 / s); `perfhalf=auto` (adaptive, as above) / `perfhalf=1` (always 30) to try it on a Deck.
var perf_mode: bool = false
var _half: bool = false                  ## perf mode: picture held at 30 fps
var _half_t: int = 0                     ## when _half last changed (usec)
var _fit_t: int = 0                      ## since when the game frames fit at 60 again (usec, 0 = they do not)
var _fps_base: int = -1                  ## Engine.max_fps to restore when the half rate ends
var _late_slow: float = 0.0              ## fraction of late displayed frames, smoothed over ~100 frames


func set_perf_mode(on: bool) -> void:
	if on == perf_mode:
		return
	perf_mode = on
	if not on:
		_set_half(false)
		if display != null and display.read_pending:
			_refresh_apply()
	if Game.args.has("pipedbg"):
		print("PIPE f%d performance mode %s" % [frames, "on" if on else "off"])
	if _plog != null:
		_plog.perf_mode_line()


## for the perflog header / lines
func perf_mode_info() -> String:
	if not perf_mode:
		return "off (pipeline %s)" % _pipe_mode
	return "on: pipelining %s, picture upload after the game frame starts, no in-between frames, half rate %s (now %s)" % [
		"always" if _pipe_on else "unavailable (%s)" % ("pipeline=0" if _pipe_mode == "0" else "frame-exact run"),
		{"0": "off", "1": "on", "auto": "auto"}.get(Game.flag("perfhalf", "0"), "off"), "30 fps" if _half else "60 fps"]


func _set_half(on: bool) -> void:
	if on == _half:
		return
	_half = on
	_half_t = Time.get_ticks_usec()
	_fit_t = 0
	if on:
		_fps_base = Engine.max_fps
		Engine.max_fps = 30
	else:
		if Engine.max_fps == 30 and _fps_base >= 0:
			Engine.max_fps = _fps_base
		_fps_base = -1
	if Game.args.has("pipedbg"):
		print("PIPE f%d half rate %s (game frame %.1f ms, gap %.1f ms, late %.2f)" % [frames, "on" if on else "off",
			_run_ema / 1000.0, _gap_ema / 1000.0, _late_slow])
	if _plog != null:
		_plog.perf_mode_line()


## once per displayed frame (perf mode): hold the picture at 30 fps while 60 does not fit, see above
func _perf_cadence(hz: float) -> void:
	var want := Game.flag("perfhalf", "0")
	if not perf_mode or not _pipe_on or want == "0" or hz < 50.0 or hz > 70.0 or (qol != null and qol.lan_lockstep()):
		_set_half(false)
		return
	if want == "1":
		_set_half(true)
		if Engine.max_fps != 30:   # (QoLController.apply_display set its own cap meanwhile)
			_fps_base = Engine.max_fps
			Engine.max_fps = 30
		return
	var now := Time.get_ticks_usec()
	if _half_t == 0:
		_half_t = now
	var p := 1e6 / hz
	var one := _run_ema + _gap_ema         # a game frame + the main thread's gap before the next one (usec)
	var two := 2.0 * _run_ema + _gap_ema   # two game frames per picture (the gap once)
	if not _half:
		if _late_slow > 0.35 and one > 0.9 * p and two < 1.9 * p and now - _half_t > 3000000:
			_set_half(true)
		return
	if Engine.max_fps != 30:
		_fps_base = Engine.max_fps
		Engine.max_fps = 30
	if one < 0.8 * p or two > 2.0 * p:   # 60 fits again, or not even 30 does (then the cap only lowers the fps)
		if _fit_t == 0:
			_fit_t = now
		elif now - _fit_t > 2000000 and now - _half_t > 3000000:
			_set_half(false)
	else:
		_fit_t = 0


func _refresh_apply() -> void:
	var t1 := Time.get_ticks_usec()
	display.refresh_apply()
	_t_draw += Time.get_ticks_usec() - t1
	if _plog != null:
		_plog.pic_us += Time.get_ticks_usec() - t1


func _pipe_setup() -> void:
	if Game.args.has("fakerender"):   # debug: fakerender=MS keeps the main thread busy MS ms per drawn frame (a slow
		_fake_us = int(float(Game.flag("fakerender")) * 1000.0)   # GPU driver / present; with --rendering-method dummy)
		RenderingServer.frame_post_draw.connect(_fake_render)
	# (read here, not in the member initialisers: when GameDS.tscn is the main scene it is created before Game parsed
	# the command line)
	_pipe_mode = Game.flag("pipeline", "auto")
	var exact := false
	for k in ["capture", "pilot", "turbo", "snap", "fxdump"]:
		exact = exact or Game.args.has(k)
	if Game.args.has("pipedbg"):
		print("PIPE setup mode %s%s" % [_pipe_mode, " (frame-exact run: off)" if exact else ""])
	if exact or _pipe_mode == "0":
		return
	_pipe_on = true
	RenderingServer.frame_pre_draw.connect(_pipe_start)
	get_tree().process_frame.connect(_pipe_join)
	get_tree().physics_frame.connect(_pipe_join)


func _pipe_start() -> void:
	_pipe_try_start()
	if display != null and display.read_pending:   # PERFORMANCE MODE: the picture's Godot-side half, while the game runs
		_refresh_apply()


func _pipe_try_start() -> void:
	if _inflight or machine == null or not machine.running or _busy or (qol != null and qol.paused):
		return
	if _pipe_mode != "1" and not perf_mode:
		var was := _pipe_auto
		if _late_ema > 0.1 and _run_ema > 0.3e6 * _period:
			_pipe_auto = true
		elif _run_ema < 0.2e6 * _period:
			_pipe_auto = false
		if _pipe_auto != was and Game.args.has("pipedbg"):
			print("PIPE f%d %s (game frame %.1f ms, late %.2f)" % [frames, "on" if _pipe_auto else "off", _run_ema / 1000.0, _late_ema])
		if not _pipe_auto:
			return
	if _acc + _dt_avg < 0.5 * _period:   # the next displayed frame would not run a game frame
		return
	if Game.args.has("quit_at") and frames >= int(Game.flag("quit_at")):   # test runs: quitting at this frame
		return
	var t_idle := _t_idle0
	if _tick_begin():
		_inflight = true
		if t_idle > 0:
			_gap_ema = lerpf(_gap_ema, minf(_t_begin - t_idle, 50000.0), 0.05)
			if _plog != null:
				_plog.gap_us += _t_begin - t_idle
				if _t_proc_end > t_idle:   # the part after GameDS._process (other nodes, Godot)
					_plog.gap2_us += _t_begin - _t_proc_end


func _pipe_join() -> void:
	if not _inflight:
		return
	_inflight = false
	_tick_end(true)
	_ahead += 1


## quitting (window closed, quit_at) with a game frame still running: let it park before anything is freed (the
## game thread must never run while the scripts are torn down), keep a save it made
func _exit_tree() -> void:
	for c in [[RenderingServer.frame_pre_draw, _pipe_start], [RenderingServer.frame_post_draw, _fake_render]]:
		if (c[0] as Signal).is_connected(c[1]):
			(c[0] as Signal).disconnect(c[1])
	if _inflight:
		_inflight = false
		if _began and machine.step_end():
			_write_save()


var _fake_us: int = 0


func _fake_render() -> void:
	OS.delay_usec(_fake_us)


func _process(delta: float) -> void:
	if display != null and display.read_pending:   # (a picture read but not applied: no frame was drawn since)
		_refresh_apply()
	if qol != null and qol.paused:   # AUTO PAUSE (window not in front): no game time passes
		_acc = 0.0
		return
	_pipe_join()
	if qol != null:
		qol.lan_poll()   # part 30 LAN: network (nothing without a session)
	var t_main := Time.get_ticks_usec()
	var f_main := frames - _ahead
	if _free_run and machine != null and machine.running and not _busy:
		_dt_avg = delta if _dt_avg <= 0.0 else lerpf(_dt_avg, minf(delta, 0.1), 0.05)
		_late_ema = lerpf(_late_ema, 1.0 if delta > 1.3 * _period else 0.0, 0.05)   # pipelining (auto)
		_late_slow = lerpf(_late_slow, 1.0 if delta > 1.3 * _period else 0.0, 0.01)   # PERFORMANCE MODE half rate
		var hz := float(Game.flag("fakehz")) if Game.args.has("fakehz") else DisplayServer.screen_get_refresh_rate()
		var locked := hz > 58.5 and hz < 61.5 and absf(_dt_avg * hz - 1.0) < 0.03   # one frame per refresh of a ~60 Hz display
		var period := 1.0 / hz if locked else 1.0 / DS_HZ
		if qol != null and qol.lan_lockstep():   # part 30 LAN time sync: the machine that is ahead runs up to 1 % slower
			delta *= qol.lan.time_scale()
		_acc = minf(_acc + delta, 8.5 * period)   # never clamped below zero: that would create time (= run fast)
		var steps := mini(int(_acc / period + 0.5), 8)   # rounding: V-Sync jitter around one period gives one step
		steps = maxi(steps, _ahead)   # a frame already run while the last picture was drawn (pipelining) counts
		_acc -= steps * period
		for i in steps - _ahead:
			_tick()
			if _lan_stalled:   # part 30 LAN: no input from the other machine yet: no catching up afterwards either
				_acc = minf(_acc, period)
				break
		_period = period
		if perf_mode:
			_perf_cadence(hz)
		if smooth:   # in-between frame: the last two game frames blended by the time since the last step
			display.set_interp(1.0 if locked else clampf(_acc / period + 0.5, 0.0, 1.0))
		if Game.args.has("pacelog"):
			var now := Time.get_ticks_usec()
			if _pace_t0 == 0:
				_pace_t0 = now
				_pace_f0 = frames
			elif now - _pace_t0 >= 5000000:
				print("PACE game %.2f frames/s, display %.1f fps (refresh %.1f Hz, %s)" % [(frames - _pace_f0) * 1e6 / (now - _pace_t0),
					Engine.get_frames_per_second(), hz, "one frame per refresh" if locked else "timed"])
				_pace_t0 = now
				_pace_f0 = frames
		if Game.args.has("pacedbg"): print("PACE d=%.1fms steps=%d acc=%.1f" % [delta*1000, steps, _acc*1000])
	_ahead = 0
	var draw := _new_frame and not Game.args.has("capture")
	if draw:
		_refresh()
	if _plog != null:
		_plog.frame(frames - f_main, Time.get_ticks_usec() - t_main)
		_t_proc_end = Time.get_ticks_usec()
	if draw:
		if Game.args.has("snap") and frames >= _next_snap:   # debug: snap=DIR snap_every=N (real-time screenshots)
			_next_snap = (frames / int(Game.flag("snap_every", "300")) + 1) * int(Game.flag("snap_every", "300"))
			var f := frames
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(Game.flag("snap"))
			get_viewport().get_texture().get_image().save_png(Game.flag("snap").path_join("s%d.png" % f))


## Presses that start and end between two emulated frames (a quick tap) still count for one frame: the game
## polls the pad once per frame, like the DS, and would otherwise miss them.
var _tapped := {}
var _tap_touch := false
var _lan_stalled := false   ## part 30 LAN: the last _tick_begin waited for the other machine (no frame started)


func _input(event: InputEvent) -> void:
	_pipe_join()   # QoL input handling reads / writes game memory: the game thread must be parked
	if qol != null:
		qol.cursor_event(event)   # gamepad cursor (part 24): only looks (mouse use hides it, click taps latched)
		qol.mp_latch(event)       # part 27 LOCAL MULTIPLAYER: short presses per player's device (only looks)
	if qol != null and qol.raw_input(event):   # CONTROLS menu waiting for a new key / pad input
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and qol != null and qol.handle_key(event):   # QoL keys (F3 FPS counter, F11)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:   # fullscreen on/off
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
		if presenter != null:
			presenter.recheck()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_tap_touch = true
	elif (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed() and not event.is_echo():
		for a in KEY_ORDER + ["ds_x", "ds_y"]:
			if event.is_action(a):
				_tapped[a] = true


func _tick() -> void:
	if _tick_begin():
		_tick_end(false)


## First half of a game frame (part 26): the input for the frame, debug pokes, then the game thread starts running
## the frame (DSMachine.step_begin). Returns false when no frame was started.
func _tick_begin() -> bool:
	if machine == null or not machine.running or _busy:
		return false
	_lan_stalled = false
	var t_in := Time.get_ticks_usec() if _plog != null else 0
	var lan_on := qol != null and qol.lan_lockstep()   # part 30 LAN battle: lockstep with the other machine
	if lan_on and not qol.lan.can_step(frames + 1):
		_lan_stalled = true
		return false
	var keys := 0x3FF
	var ext := 0x2C00         # 0x027FFFA8: X (0x400), Y (0x800), debug (0x2000) released (active low)
	var held: PackedStringArray = Pilot._held if Pilot.active else PackedStringArray()
	for i in KEY_ORDER.size():
		if Input.is_action_pressed(KEY_ORDER[i]) or _tapped.has(KEY_ORDER[i]) or PILOT_NAMES[i] in held:
			keys &= ~(1 << i)
	if Input.is_action_pressed("ds_x") or _tapped.has("ds_x") or "X" in held:
		ext &= ~0x400
	if Input.is_action_pressed("ds_y") or _tapped.has("ds_y") or "Y" in held:
		ext &= ~0x800
	_tapped.clear()
	if qol != null and qol.mp.active and not lan_on:   # part 27 LOCAL MULTIPLAYER: PLAYER 1's own device / mapping, not the ds_* map
		var w: int = qol.mp_poll_p1()
		keys = 0x3FF & ~(w & 0x3FF)
		ext = 0x2C00 & ~(w & 0xC00)
	# touch screen = the lower screen: left mouse button (or a scripted T<x>/<y> token)
	var touch := Vector2i(-1, -1)
	var tap := _tap_touch
	_tap_touch = false
	if (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or tap) and display.single_screen == false:
		var mp := presenter.to_ds(get_viewport().get_mouse_position()) if presenter != null else display.get_local_mouse_position()
		if mp.x >= 0 and mp.x < 256 and mp.y >= 192 and mp.y < 384:
			touch = Vector2i(int(mp.x), int(mp.y) - 192)
	if qol != null:   # the gamepad cursor's click (part 24, QoLCursor): a touch where it points, while held
		var ct := qol.cursor_touch()
		if touch.x < 0:
			touch = ct
	if not _script_keys.is_empty():   # scripted input: inputs=<frame>:<Button+Button|T<x>/<y>>:<frames>,...
		for e in _script_keys:
			if frames + 1 >= e[0] and frames + 1 < e[0] + e[2]:
				for b in e[1]:
					if b.begins_with("T"):
						var xy: PackedStringArray = b.substr(1).split("/")
						touch = Vector2i(int(xy[0]), int(xy[1]))
						continue
					if b.begins_with("K") and b.length() > 1:   # a raw keyboard key (K<name>, e.g. Kspace, Kescape):
						if frames + 1 == e[0] or frames + 1 == e[0] + e[2] - 1:   # pressed / released through Input,
							var kev := InputEventKey.new()                          # so the input map (CONTROLS) applies
							kev.physical_keycode = OS.find_keycode_from_string(b.substr(1))
							kev.keycode = kev.physical_keycode
							kev.pressed = frames + 1 == e[0]
							Input.parse_input_event(kev)
							if e[2] == 1:
								kev = kev.duplicate()
								kev.pressed = false
								Input.parse_input_event(kev)
						continue
					if b.begins_with("F") and b.substr(1).is_valid_int():   # function keys (F3, F11): one press
						if frames + 1 == e[0] and qol != null:
							var ev := InputEventKey.new()
							ev.keycode = KEY_F1 + int(b.substr(1)) - 1
							ev.pressed = true
							qol.handle_key(ev)
						continue
					var i := PILOT_NAMES.find(b)
					if i >= 0:
						keys &= ~(1 << i)
					elif b == "X":
						ext &= ~0x400
					elif b == "Y":
						ext &= ~0x800
	if qol != null and qol.mp.active and not lan_on:   # part 27: both players' input into QoLMp; what the DS sees per session stage
		var mf: Array = qol.mp_frame(keys, ext, touch)
		keys = mf[0]
		ext = mf[1]
		touch = mf[2]
	if qol != null:
		var f := qol.filter_input(keys, ext, touch)
		keys = f[0]
		ext = f[1]
		touch = f[2]
	if qol != null and display.mirror_active():   # WEIRD: MIRROR MODE (battle picture flipped): LEFT <-> RIGHT
		var r := (keys >> 4) & 1
		var l := (keys >> 5) & 1
		keys = (keys & ~0x30) | (l << 4) | (r << 5)
	if qol != null and (lan_on or qol.lan.aborting):   # part 30 LAN: this machine's record out, both records in
		var lr: Array = qol.lan_frame(keys, ext, touch)
		keys = lr[0]
		ext = lr[1]
		touch = lr[2]
	machine.keyinput = keys
	machine.ext_keys = ext
	machine.core.arm7.set_touch(touch.x >= 0, touch.x, touch.y)
	if Game.args.has("watch") and frames == int(Game.flag("watch_from", "0")):   # debug (WATCH=1 builds)
		var spec := Game.flag("watch").split("+")
		var lo := spec[0].hex_to_int()
		machine.core.watch.append([lo, lo + (spec[1].hex_to_int() if spec.size() > 1 else 4)])
	if Game.args.has("trace"):   # debug (TRACE=1 builds): trace=F1-F2 writes the call trace of those frames
		var tr := Game.flag("trace").split("-")
		machine.core._tracing = frames + 1 >= int(tr[0]) and frames + 1 <= int(tr[1])
		if frames == int(tr[1]):
			var tf := FileAccess.open(Game.flag("capture", "/tmp").path_join("trace.txt"), FileAccess.WRITE)
			tf.store_string("\n".join(machine.core.trace_log))
			tf.close()
	if Game.args.has("poke"):   # debug: poke=F:ADDR:VAL16[:N];... writes a RAM halfword before frames F..F+N-1
		for e in Game.flag("poke").split(";", false):
			var q := e.split(":")
			var pf := int(q[0])
			if frames + 1 >= pf and frames + 1 < pf + (int(q[3]) if q.size() > 3 else 1):
				machine.core.M.encode_u16(q[1].hex_to_int() - 0x2000000, q[2].hex_to_int() & 0xFFFF)
	if Game.args.has("clamp"):   # debug: clamp=ADDR:LO:HI;... keeps a RAM s16 within LO..HI (e.g. fighter HP)
		for e in Game.flag("clamp").split(";", false):
			var q := e.split(":")
			var off := q[0].hex_to_int() - 0x2000000
			var v: int = machine.core.M.decode_s16(off)
			var c := clampi(v, int(q[1]), int(q[2]))
			if c != v:
				machine.core.M.encode_s16(off, c)
	if Game.args.has("dumpram") and str(frames) in Game.flag("dumpram").split(","):
		# debug: dumpram=F1,F2 -> <capture or snap dir>/ram_<F>.bin (main RAM 0x02000000..0x023FFFFF before frame F+1)
		var dd := Game.flag("capture", Game.flag("snap", "user://"))
		DirAccess.make_dir_recursive_absolute(dd)
		var fr := FileAccess.open(dd.path_join("ram_%d.bin" % frames), FileAccess.WRITE)
		fr.store_buffer(machine.core.M.slice(0, 0x400000))
		fr.close()
	_t_begin = Time.get_ticks_usec()
	if _plog != null:
		_plog.pre_us += _t_begin - t_in
	_began = machine.step_begin()
	return true


## Second half: wait until the game thread parked at the end of the frame, then everything that reads the frame's
## results (QoL, audio, 3D commands, captures, save). `pipelined`: the frame ran while Godot drew the last one.
func _tick_end(pipelined: bool) -> void:
	var tw := Time.get_ticks_usec()
	var ok := _began and machine.step_end()
	var t0 := _t_begin
	if pipelined:   # step time = the game thread's own time (the rest of the wait overlapped with drawing)
		t0 = Time.get_ticks_usec() - machine.run_us
	if _plog != null:
		_plog.wait_us += Time.get_ticks_usec() - tw
		_plog.game_frame(machine.run_us, pipelined)
	if not ok:
		push_error("game stopped: " + machine.error)
		if Game.args.has("quit_at"):   # unattended test runs end instead of showing a frozen frame
			get_tree().quit(1)
		return
	frames += 1
	_run_ema = lerpf(_run_ema, minf(machine.run_us, 50000.0), 0.05)   # pipelining (auto)
	var t_post := Time.get_ticks_usec() if _plog != null else 0
	if qol != null:
		qol.after_step()
	if _plog != null:
		_plog.qol_us += Time.get_ticks_usec() - t_post
	if Game.args.has("sndstat"):
		var m := 0
		for i in 16:
			if machine.core.arm7.sound.ch[i].active:
				m |= 1 << i
		if m != _last_chmask:
			print("SNDSTAT f%d channels %04x" % [frames, m])
			var snd: DSSound = machine.core.arm7.sound
			for i in 16:
				if (m & ~_last_chmask) & (1 << i):
					var c: DSSound.Channel = snd.ch[i]
					print("   ch%d cnt %08x sad %08x tmr %04x pnt %04x len %06x data %s" % [i, snd.regs.decode_u32(i * 16),
						c.addr, snd.regs.decode_u16(i * 16 + 8), c.loop_start, c.loop_len,
						machine.core.M.slice(c.addr - 0x02000000, c.addr - 0x02000000 + 16).hex_encode() if c.addr >= 0x02000000 else "-"])
			_last_chmask = m
		if Game.args.has("sndcnt") and frames >= int(Game.flag("sndcnt")) and frames < int(Game.flag("sndcnt")) + 12:
			var snd2: DSSound = machine.core.arm7.sound
			var parts := []
			for i in 16:
				if m & (1 << i):
					parts.append("%d:%08x/%04x" % [i, snd2.regs.decode_u32(i * 16), snd2.regs.decode_u16(i * 16 + 8)])
			print("SNDCNT f%d %s" % [frames, " ".join(parts)])
	if Game.args.has("probe") and frames % int(Game.flag("probe_every", "10")) == 0:   # debug: probe=EXPR;EXPR
		# each EXPR: ADDR[+OFF] (u32 at ADDR, or at [ADDR]+OFF)
		var vals := []
		for ex in Game.flag("probe").split(";"):
			var pp := ex.split("+")
			var a := pp[0].hex_to_int()
			if pp.size() > 1:
				a = machine.core.r32(a) + pp[1].hex_to_int()
			vals.append("%x" % machine.core.r32(a))
		print("PROBE f%d %s" % [frames, " ".join(vals)])
	var t_aud := Time.get_ticks_usec() if _plog != null else 0
	_push_audio()
	if _plog != null:
		_plog.aud_us += Time.get_ticks_usec() - t_aud
	if Game.args.has("gxdump") and Game.args.has("capture"):   # debug: gxdump=FROM:N -> capture/gx.bin (tools/bench_gx.gd)
		var gp := Game.flag("gxdump").split(":")
		var g0 := int(gp[0])
		if frames >= g0 and frames < g0 + int(gp[1]):
			_gx_frames.append(machine.core.gx_cmds.duplicate(true))
		elif frames == g0 + int(gp[1]):
			var f := FileAccess.open(Game.flag("capture").path_join("gx.bin"), FileAccess.WRITE)
			f.store_var(_gx_frames)
			f.close()
	display.r3d.submit(machine.core.gx_cmds)
	var t1 := Time.get_ticks_usec()
	_t_step += t1 - t0
	_t_step_max = maxi(_t_step_max, t1 - t0)
	_t_idle0 = t1
	if _plog != null:
		_plog.post_us += t1 - t_post
		_plog.step_us += t1 - t0
		_plog.step_max = maxi(_plog.step_max, t1 - t0)
	if Game.args.has("perf") and t1 - t0 > 40000:
		print("PERF slow frame %d: %.1f ms" % [frames, (t1 - t0) / 1000.0])
		var pc: DSCoreBase = machine.core
		if pc.prof_on and Game.args.has("profslow"):   # PROFILE build: what that frame did
			var ps2: Dictionary = pc.prof_self
			var pk2 := ps2.keys()
			pk2.sort_custom(func(x, y): return ps2[x] > ps2[y])
			for k in pk2.slice(0, int(Game.flag("profslow", "12"))):
				print("PROFSLOW   %08x %.1f ms, %d calls" % [k, ps2[k] / 1000.0, pc.prof_calls[k]])
	if Game.args.has("profslow") and machine.core.prof_on:
		machine.core.prof_self.clear()
		machine.core.prof_calls.clear()
	_new_frame = true
	if Game.args.has("capture"):   # frame-exact captures: draw every emulated frame (cap_fast: captured ones only)
		if not Game.args.has("cap_fast") or (frames + 1) % int(Game.flag("cap_every", "1")) == 0 \
				or frames % int(Game.flag("cap_every", "1")) == 0:
			_refresh()
			if Game.args.has("capinterp"):   # debug: capture in-between frames (QoL smooth motion) at this blend
				display.set_interp(float(Game.flag("capinterp")))
	if Game.args.has("quit_at") and frames >= int(Game.flag("quit_at")):   # debug: quit_at=F (flushes release-build output)
		get_tree().quit()
	if frames % 600 == 0 and Game.args.has("perf"):
		var a7 = machine.core.arm7
		print("PERF fps %.1f (display %.1f Hz), file path lookups native %d / translated %d" % [Engine.get_frames_per_second(),
			DisplayServer.screen_get_refresh_rate(), machine.core.fs_fast[0], machine.core.fs_fast[1]])
		print("PERF frames %d: step %.2f ms (slowest %.1f; scanlines %.2f incl. sound driver %.2f, mixer %.2f), refresh %.2f ms per frame" % [frames,
			_t_step / 600000.0, _t_step_max / 1000.0, machine.t_lines / 600000.0, a7.t_driver / 600000.0, a7.t_mix / 600000.0, _t_draw / 600000.0])
		_t_step_max = 0
		machine.t_lines = 0
		var core: DSCoreBase = machine.core
		if core.prof_on:   # PROFILE=1 build of ds_game.gd: functions with the most own time in the last 600 frames
			var ps: Dictionary = core.prof_self
			var pk := ps.keys()
			pk.sort_custom(func(x, y): return ps[x] > ps[y])
			for k in pk.slice(0, 50):
				var nm: String = {1: "(scanlines)", 2: "(frame hand-over)", 3: "(thread blocked)"}.get(k, "%08x" % k)
				print("PROF %s %.3f ms/frame, %d calls/frame" % [nm, ps[k] / 600000.0, core.prof_calls[k] / 600])
			ps.clear()
			core.prof_calls.clear()
		print("PERF   3D %.2f ms (waiting for geometry %.2f; geometry work %.2f on a worker thread, texture upload %.2f)" % [
			display.t_3d / 600000.0, display.r3d.t_gx / 600000.0, display.r3d.t_gx_work / 600000.0, display.r3d.t_up / 600000.0])
		display.r3d.t_gx_work = 0
		display.t_3d = 0
		display.r3d.t_gx = 0
		display.r3d.t_up = 0
		a7.t_driver = 0
		a7.t_mix = 0
		_t_step = 0
		_t_draw = 0
	if Game.args.has("capture"):
		var every := int(Game.flag("cap_every", "1"))
		if frames >= int(Game.flag("cap_from", "1")) and frames % every == 0:
			_busy = true
			await RenderingServer.frame_post_draw
			var dir := Game.flag("capture")
			DirAccess.make_dir_recursive_absolute(dir)
			get_viewport().get_texture().get_image().save_png(dir.path_join("p%d.png" % frames))
			if Game.flag("layersweep") == str(frames):   # debug: the lower screen with one layer at a time (l<bit>)
				for b in 5:
					display.set_layer_keep(true, 0x100 << b)
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png(dir.path_join("p%d_l%d.png" % [frames, b]))
				display.set_layer_keep(true, 0x1F00)
			if Game.flag("dumpvram") == str(frames):
				var hw: DSHardware = machine.core.hw
				for b in 9:
					var f := FileAccess.open(dir.path_join("bank%d.bin" % b), FileAccess.WRITE)
					f.store_buffer(hw.bank[b])
				for nm in ["pal", "oam"]:
					var f := FileAccess.open(dir.path_join(nm + ".bin"), FileAccess.WRITE)
					f.store_buffer(hw.pal if nm == "pal" else hw.oam)
				var f := FileAccess.open(dir.path_join("io.bin"), FileAccess.WRITE)
				f.store_buffer(machine.core.IO)
				f = FileAccess.open(dir.path_join("ram.bin"), FileAccess.WRITE)
				f.store_buffer(machine.core.M)
				for nm in ["a", "b"]:   # per-line copies of the 2D registers (128 bytes per line) the frame was drawn with
					f = FileAccess.open(dir.path_join("lines_%s.bin" % nm), FileAccess.WRITE)
					f.store_buffer(machine.line_regs_a if nm == "a" else machine.line_regs_b)
			if Game.args.has("gxdbg") and not display.r3d.dbg_tex.is_empty():   # what the GPU textures were built from
				for k in 2:
					var ft := FileAccess.open(dir.path_join("gpu_%s.bin" % ["tex", "pal"][k]), FileAccess.WRITE)
					ft.store_buffer(display.r3d.dbg_tex[k])
			if Game.args.has("dump3d") and display.layer3d:
				display.layer3d.get_image().save_png(dir.path_join("l%d.png" % frames))
			_busy = false
		if frames >= int(Game.flag("cap_to", "0")):
			_save_wav(Game.flag("capture").path_join("audio.wav"))
			if Game.args.has("sndlog"):
				var hist := {}
				for c in machine.core.arm7.snd_commands:
					hist[c[0]] = int(hist.get(c[0], 0)) + 1
				print("SNDLOG ", hist)
				for c in machine.core.arm7.snd_commands:
					if c[0] <= 0x0B:
						print("SNDSEQ ", c.map(func(x): return "%x" % x))
			get_tree().quit()
	_write_save()


## the game wrote its save memory: store it in the save file
func _write_save() -> void:
	if machine.core.arm7.backup_dirty:
		machine.core.arm7.backup_dirty = false
		var f := FileAccess.open(save_path, FileAccess.WRITE)
		if f == null and not save_path.begins_with("user://"):   # game folder not writable: keep it in user://
			save_path = "user://save100.sav"
			f = FileAccess.open(save_path, FileAccess.WRITE)
		if f:
			f.store_buffer(machine.core.arm7.backup)
			f.close()


## Drawing happens once per displayed frame (Godot may run several 60 Hz game steps in one frame when it falls
## behind; only the last one is drawn, like an emulator's frame skip - the 3D commands of every step are
## still processed).
var _new_frame: bool = false
var _t_step_max: int = 0
var _plog: DSPerfLog = null           ## part 26: `perflog` / DBZ_PERFLOG=1 frame-time log (scripts/game/ds_perflog.gd)


func _refresh() -> void:
	_new_frame = false
	var t1 := Time.get_ticks_usec()
	if display.read_pending:
		display.refresh_apply()
	if perf_mode and _pipe_on and not Game.args.has("capture"):   # PERFORMANCE MODE: the Godot-side half in _pipe_start
		display.refresh_read()
		if _plog != null:
			_plog.read_us += Time.get_ticks_usec() - t1
	else:
		display.refresh()
	_t_draw += Time.get_ticks_usec() - t1
	if _plog != null:
		_plog.pic_us += Time.get_ticks_usec() - t1


func _push_audio() -> void:
	var snd: DSSound = machine.core.arm7.sound
	var buf := snd.take_out()
	if Game.args.has("capture"):
		_wav.append_array(buf)
		return
	if _playback == null or buf.is_empty():
		return
	# Rate matching: the game makes 32768 Hz audio per emulated frame, but frames follow the display (60 Hz,
	# vs the DS's 59.83) and stall on loads, so the queue drifts. Resample each frame's samples by up to ±1 %
	# toward a 70 ms queue (inaudible, no clicks) instead of dropping samples when the queue fills up.
	var room := _playback.get_frames_available()
	var queued := _audio_cap - room
	var ratio := 1.0 + clampf((queued - AUDIO_TARGET) / float(AUDIO_TARGET) * 0.01, -0.01, 0.01)
	if Game.args.has("pacedbg") and frames % 60 == 0:
		print("AUDIO queued %d of %d, ratio %.4f" % [queued, _audio_cap, ratio])
	var out := PackedVector2Array()
	var n := buf.size()
	var prev := _audio_last
	var t := _audio_phase
	while t < n:
		var i := int(t)
		var a: Vector2 = prev if i == 0 else buf[i - 1]
		out.append(a.lerp(buf[i], t - i))
		t += ratio
	_audio_phase = t - n
	_audio_last = buf[n - 1]
	if out.size() > room:
		out = out.slice(out.size() - room)   # far behind (long stall): drop the oldest samples
	_playback.push_buffer(out)


## 16-bit stereo WAV of the captured audio (compared with tools/melonds-headless audio captures)
func _save_wav(path: String) -> void:
	var n := _wav.size()
	var data := PackedByteArray()
	data.resize(n * 4)
	for i in n:
		data.encode_s16(i * 4, clampi(int(_wav[i].x * 32767.0), -32768, 32767))
		data.encode_s16(i * 4 + 2, clampi(int(_wav[i].y * 32767.0), -32768, 32767))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(2)
	f.store_32(DSSound.MIX_RATE)
	f.store_32(DSSound.MIX_RATE * 4)
	f.store_16(4)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data.size())
	f.store_buffer(data)
