class_name DSMachine
extends RefCounted
## Runs the translated game the way the DS does: the ARM9 program executes on its own thread (a Godot
## Thread) and blocks in SVC_WaitVBlankIntr (0x0200077E) once per displayed frame. That wait is where the
## port synchronises with Godot: the main thread lets the game run until its next wait (step()), then reads
## the emulated memory, VRAM and registers to draw the frame while the game is parked.
##
## Every nested wait inside scene code (fades, loading loops) is a frame too, exactly like on hardware.
##
## Time model: the CPU is infinitely fast; emulated time only passes while the CPU is halted (BIOS
## VBlankIntrWait, OS_Halt in the idle thread), one scanline at a time (_advance_line): hardware timers,
## HBlank/VBlank interrupts, the ARM7's sound alarms. Line 192 (start of VBlank) is where the port presents
## a frame to Godot (_park): melonDS frames end there too.
##   [parked] -> line 192: VBlank IRQ, HBlank 192 -> the game runs until it halts -> lines 193..262, 0..191
##   (HBlank IRQs, per-line register capture) -> [parked]
##
## DS threads (OSThread) run on Godot threads with a baton: only the thread the OS scheduler selected runs;
## OS_RescheduleThread (0x020A9F40) is replaced by a switch that wakes the selected thread's Godot thread and
## blocks the current one (_switch).

const MODULE_PARAMS := 0x02000B4C        ## crt0 module parameters (autoload list, bss range)
const NITRO_MAIN := 0x02000B88
const VBLANK_WAIT := 0x0200077E
const OS_RESCHEDULE := 0x020A9F40         ## OS_RescheduleThread
const OS_HALT := 0x020AB3D0               ## OS_Halt (CP15 wait for interrupt), used by the idle thread
const OS_INFO := 0x020E31BC               ## OSThreadInfo {u16 need_resched, u16 irq_depth?, +8 current, +0xC list}
const OS_SELECT := 0x020AA02C             ## OS_SelectThread (translated)
const LINE_CYCLES := 2130                 ## ARM9 bus cycles per scanline (355 dots x 6)

var core                                 ## generated DSGame (extends DSCoreBase)
var _cb: DSCoreBase                      ## the same, typed (part 32: faster member access on the per-scanline path)
var thread: Thread
var _sem_go := Semaphore.new()
var _sem_done := Semaphore.new()
var _quit: bool = false
var running: bool = false
var syncs: int = 0                       ## frames presented so far
var keyinput: int = 0x3FF                ## KEYINPUT for the next frame (active low)
var ext_keys: int = 0x2C00               ## 0x027FFFA8 (X, Y, pen-down from the ARM7; active low)
var on_sync: Callable                    ## optional, called on the game thread at each sync
var on_sync_before_display: Callable     ## optional, game thread, at the frame boundary before the visible lines
                                         ## of the next frame run (= melonDS frame end: lockstep dumps)
var error: String = ""
## Callables run on the game's main thread at its next VBlank wait (the point in the main loop where the game
## itself starts and stops music): QoL features call the game's own functions there. Append between steps.
var inject: Array = []
var _main_thread: int = 0
var hang_ms: int = 0                     ## step() gives up (and collects a call trace) after this long; 0 = never


func _init(game_core) -> void:
	core = game_core
	_cb = game_core
	core._register_all()
	core.prof_on = core.has_method("_pf_02000080")   # PROFILE=1 translation
	core.hle[VBLANK_WAIT] = _vblank_wait
	core.hle[OS_RESCHEDULE] = _os_reschedule
	core.hle[OS_HALT] = _os_halt
	core.on_irq_exit = _irq_exit
	core.on_spin_wait = _spin_wait


# ------------------------------------------------------------------------------------------------ start
## Power-on boot from the cartridge image, like the BIOS + crt0 (0x02000800) would set things up.
func boot(rom: PackedByteArray) -> void:
	core.hw.rom = rom
	DSBoot.load(core, rom, core.arm7.backup)
	_start(_run_fresh)


## Resume from a RAM/DTCM/IO snapshot taken while the game waited in its main loop (lockstep tests).
func resume(ram: PackedByteArray, dtcm: PackedByteArray, io: PackedByteArray, rom: PackedByteArray) -> void:
	core.hw.rom = rom
	var m := PackedByteArray()
	m.append_array(ram)
	m.append_array(ram)
	m.resize(DSCoreBase.SIZE)
	for i in dtcm.size():
		m[0x7E0000 + i] = dtcm[i]
	core.M = m
	if io.size() > 0:
		core.IO = io.duplicate()
		core.IO.resize(DSCoreBase.IO_SIZE)
		for i in 9:   # rebuild the VRAM mapping from the snapshot's VRAMCNT
			core.hw.vramcnt[i] = core.IO[0x240 + (i if i < 7 else i + 1)]
		core.hw.remap_vram()
	_start(_run_resume)


func _start(entry: Callable) -> void:
	core.install_bios_hle()
	running = true
	thread = Thread.new()
	thread.start(entry)
	_sem_done.wait()            # the game thread parks at its first wait


## Let the game run one frame (until its next vblank wait). Returns false once the game thread ended.
func step() -> bool:
	if not step_begin():
		return false
	return step_end()


## step() in two halves (part 26, GameDS pipelining): step_begin() lets the game thread run its frame and returns
## at once; step_end() waits until it parked again. Nothing may read or write the emulated state in between.
func step_begin() -> bool:
	if not running:
		return false
	_sem_go.post()
	return true


func step_end() -> bool:
	if hang_ms <= 0:
		_sem_done.wait()
		return running
	var t := Time.get_ticks_msec()
	var busy := 0
	while not _sem_done.try_wait():
		OS.delay_usec(200)
		# time the game thread could have run: a jump between two polls (the PC asleep / suspended, the whole
		# process frozen or starved) is not the game hanging (part 22 QA: a 12 s freeze stopped the game)
		var now := Time.get_ticks_msec()
		busy += mini(now - t, 100)
		t = now
		if busy > hang_ms:
			# diagnostics: the game did not reach its vblank wait; record what it is doing (TRACE builds)
			core.trace_log.clear()
			core.trace_stack = ""
			core._tracing = true
			OS.delay_msec(300)
			core._tracing = false
			error = "game thread busy for %d ms; stack %s\nlast calls:\n%s" % [hang_ms, core.trace_stack, "\n".join(core.trace_log.slice(-20))]
			running = false
			return false
	return running


## The translated code cannot be interrupted; the game thread stays parked in its wait and dies with the
## process.
func stop() -> void:
	_quit = true
	running = false


# ------------------------------------------------------------------------------------------------ game thread
func _run_fresh() -> void:
	_park()                     # wait for the first step()
	if not _quit:
		core.f_020b6220()       # crt0: OS init hook (empty), static initialisers, then NitroMain
		core.f_02000b48()
		core.f_020b6234()
		core.f_02000b88()
	_finish()


## The snapshot was taken inside NitroMain's inner loop, in its vblank wait. Continue that loop from there
## (hand-written copy of the loop tail at 0x02000C64; a soft reset is not supported in this mode).
func _run_resume() -> void:
	_park()
	var key_buf := 0x027E3E00
	_line = 192
	_after_vblank()
	while not _quit:
		core.f_0209fe54()
		core.f_02003360()
		core.w16(0x020DD4C0, core.r16(0x020DD4C0) + 1)
		core.f_0200124c(key_buf)
		core.f_020105c0()
		if core.f_020010f4() == 0:
			error = "soft reset requested (not supported when resuming from a snapshot)"
			break
		_vblank_wait()
	_finish()


func _finish() -> void:
	running = false
	_sem_done.post()


## SVC_WaitVBlankIntr (BIOS IntrWait(1, VBlank)): discard the VBlank flag, then halt until the VBlank handler
## sets it again (0x027E3FF8 bit 0, the BIOS IRQ check flags).
func _vblank_wait(_a = 0, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int:
	if _main_thread == 0:
		_main_thread = core.r32(OS_INFO + 8)
	if not inject.is_empty() and not core.in_irq:   # QoL calls into the game's own functions (jukebox)
		if core.r32(OS_INFO + 8) == _main_thread:
			var calls := inject.duplicate()
			inject.clear()
			for c: Callable in calls:
				c.call()
	core.w32(0x027E3FF8, core.r32(0x027E3FF8) & ~1)
	var lines := 0
	while (core.r32(0x027E3FF8) & 1) == 0 and not _quit:
		_advance_line()
		lines += 1
		if lines > 263 * 4:   # the VBlank handler never set the flag: do it like a missing handler would hang
			core.w32(0x027E3FF8, core.r32(0x027E3FF8) | 1)
	return 0


## OS_SpinWait: `cycles` ARM9 cycles (2 per bus cycle) of emulated time pass, scanline by scanline
var _spin_acc: int = 0


func _spin_wait(cycles: int) -> void:
	_spin_acc += cycles / 2
	while _spin_acc >= LINE_CYCLES and not _quit:
		_spin_acc -= LINE_CYCLES
		_advance_line()


## OS_Halt: the CPU sleeps until an interrupt is taken
func _os_halt(_a = 0, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int:
	var n: int = core.irq_count
	var lines := 0
	while core.irq_count == n and not _quit:
		_advance_line()
		lines += 1
		if lines > 263 * 8:
			break
	return 0


# ------------------------------------------------------------------------------------------------ time
var _line: int = 192                     ## current scanline (its events have happened)
var _hb_latched: bool = false


## One scanline of emulated time: timers, ARM7 alarms, then the line's display events.
## Profiling (part 32): only with `prof` (GameDS `perf` / perflog) are the scanline events timed (t_lines and the
## parts t_tmr / t_cap / t_irq; ARM7 driver / mixer in DSArm7.t_driver / t_mix); otherwise no clock reads here.
var t_lines: int = 0                    ## profiling (usec): scanline events (excluding the frame hand-over)
var t_tmr: int = 0                      ## profiling: ARM9 timers
var t_cap: int = 0                      ## profiling: per-line 2D register capture
var t_irq: int = 0                      ## profiling: HBlank / VBlank interrupt handlers (translated ARM9 code)
var prof: bool = false


func _advance_line() -> void:
	if core.prof_on:
		var t0 := Time.get_ticks_usec()
		var pt: int = core._prof_enter()
		_advance_line_inner()
		core._prof_leave(DSCoreBase.PROF_LINES, pt)
		t_lines += Time.get_ticks_usec() - t0
	elif prof:
		var t0 := Time.get_ticks_usec()
		_advance_line_inner()
		t_lines += Time.get_ticks_usec() - t0
	else:
		_advance_line_inner()


func _advance_line_inner() -> void:
	var c := _cb
	_line += 1
	if _line == 263:
		_line = 0
	if prof:
		var tq := Time.get_ticks_usec()
		c.timers.advance(LINE_CYCLES)
		t_tmr += Time.get_ticks_usec() - tq
	else:
		c.timers.advance(LINE_CYCLES)
	c.arm7.advance(LINE_CYCLES)
	if c.hw.card_irq_pending:   # card transfer moved by DMA has completed (DSHardware._dma_run)
		c.hw.card_irq_pending = false
		c.raise_irq(19)
	if _line < 192:
		c.vcount = _line
		if _line == 0 and on_sync_before_display.is_valid():
			on_sync_before_display.call()
		if prof:
			var tq := Time.get_ticks_usec()
			_capture_line(_line)
			t_cap += Time.get_ticks_usec() - tq
		else:
			_capture_line(_line)
		if _hb_latched:
			_hblank()
		if _line == 191:
			c.vcount = 192
	elif _line == 262:
		c.vcount = 262
		_hb_latched = (c.IO.decode_u16(4) & 0x10) != 0
		if _hb_latched:
			_hblank()
	elif _line == 192:
		c.vcount = 192
		if prof:
			var tp := Time.get_ticks_usec()
			_park()
			t_lines -= Time.get_ticks_usec() - tp
		else:
			_park()
		_after_vblank()
	else:
		c.vcount = 192   # lines 193..261: the game sees VBlank (VCOUNT kept at 192 as before)


# ------------------------------------------------------------------------------------------------ threads
class DSThread:
	var sem := Semaphore.new()
	var thread: Thread = null
	var sp: int = 0
	var cpsr: int = 0
	var started: bool = false

var _threads: Dictionary = {}            ## OSThread address -> DSThread
var switches: int = 0                    ## DS thread switches so far (part 26 perflog: each is a Godot thread hand-over)


func _thr(p: int) -> DSThread:
	if not _threads.has(p):
		_threads[p] = DSThread.new()
	return _threads[p]


## OS_RescheduleThread: run the highest-priority ready thread. Inside an interrupt (or while rescheduling is
## disabled) it only sets the request flag; OS_IrqHandler reschedules on exit (_irq_exit).
func _os_reschedule(_a = 0, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int:
	var dis: int = core.r32(OS_INFO - 4)
	if dis != 0:
		return dis
	if core.r16(OS_INFO + 4) != 0 or core.in_irq:
		core.w16(OS_INFO, 1)
		return 1
	var cur: int = core.r32(OS_INFO + 8)
	var nxt: int = core.f_020aa02c()
	if nxt == cur or nxt == 0:
		return nxt
	for cb in [core.r32(OS_INFO - 0x10), core.r32(OS_INFO + 0x10)]:
		if cb != 0:
			core._icall(cb, cur, nxt)
	core.w32(OS_INFO + 8, nxt)
	_switch(cur, nxt)
	return 1


## IRQ handler tail (OS_IrqHandler): pending reschedule request
func _irq_exit() -> void:
	if core.in_irq or core.r16(OS_INFO) == 0:
		return
	core.w16(OS_INFO, 0)
	_os_reschedule()


func _switch(cur: int, nxt: int) -> void:
	switches += 1
	var a := _thr(cur)
	a.started = true
	a.sp = core._sp
	a.cpsr = core.cpsr_if
	var b := _thr(nxt)
	if not b.started:
		b.started = true
		b.thread = Thread.new()
		b.thread.start(_thread_entry.bind(nxt))
	else:
		core._sp = b.sp
		core.cpsr_if = b.cpsr
		b.sem.post()
	if core.prof_on:
		var pt: int = core._prof_enter()
		a.sem.wait()
		core._prof_leave(DSCoreBase.PROF_SWITCH, pt)
	else:
		a.sem.wait()                      # until some thread switches back to us (never, if terminated)


## first run of a thread created by OS_CreateThread: context pc+4 at +0x40, r0 at +4, stack bottom at +0x84
## (port frames grow upwards), then OS_ExitThread through the context's lr when the function returns.
func _thread_entry(p: int) -> void:
	core._sp = core.r32(p + 0x84) + 8
	core.cpsr_if = core.r32(p) & 0xC0
	var pc: int = core.r32(p + 0x40) - 4
	core._icall(pc, core.r32(p + 4))
	core._icall(core.r32(p + 0x3C))


# ------------------------------------------------------------------------------------------------ display state
## Registers 0x00-0x7F of both 2D engines as they are on each visible line (raster effects), 128 x 192 bytes, with
## the affine BGs' internal reference points (latched at line 0 or when BGxX/BGxY is written, then advanced by PB / PD
## each line) in place of BGxX/BGxY. Read them while the game thread is parked (after a frame).
## Part 32 (exact speed-up): the game thread only keeps the register blocks of the lines where they changed
## (`_runs`, one 128-byte compare per engine and line); the 192 lines are built from them when the picture asks
## (`line_regs(e)`, once per displayed frame instead of on every line of every game frame).
var line_regs_a: PackedByteArray:
	get: return line_regs(0)
var line_regs_b: PackedByteArray:
	get: return line_regs(1)
var _runs: Array = [[], []]              ## frame being run: per engine [line, registers] whenever they changed
var _runs_done: Array = [[], []]         ## the last complete frame (lines 0..191)
var _lr_cache: Array = [null, null]      ## its line buffers, built on demand
var _cap_a := PackedByteArray()          ## the registers of the last line captured (engine A, B)
var _cap_b := PackedByteArray()


static func _sx28(v: int) -> int:
	v &= 0x0FFFFFFF
	return v - 0x10000000 if v & 0x08000000 else v


func _capture_line(line: int) -> void:
	var a: PackedByteArray = _cb.IO.slice(0, 128)
	var b: PackedByteArray = _cb.IO.slice(0x1000, 0x1080)
	if line == 0:
		_runs = [[[0, a]], [[0, b]]]   # new lists: the last frame's stay readable
		_cap_a = a
		_cap_b = b
		return
	if a != _cap_a:
		_runs[0].append([line, a])
		_cap_a = a
	if b != _cap_b:
		_runs[1].append([line, b])
		_cap_b = b
	if line == 191:
		_runs_done = _runs
		_lr_cache = [null, null]


## the last complete frame's per-line registers of engine `e` (0 = A, 1 = B)
func line_regs(e: int) -> PackedByteArray:
	if _lr_cache[e] == null:
		_lr_cache[e] = _build_line_regs(_runs_done[e])
	return _lr_cache[e]


func _build_line_regs(runs: Array) -> PackedByteArray:
	var out := PackedByteArray()
	if runs.is_empty():
		return out
	# BG2 X, BG2 Y, BG3 X, BG3 Y at 0x28 0x2C 0x38 0x3C; their steps PB / PD at 0x22 0x26 0x32 0x36
	var r0 := 0
	var r1 := 0
	var r2 := 0
	var r3 := 0
	var s0 := 0
	var s1 := 0
	var s2 := 0
	var s3 := 0
	var ri := 0
	var nr := runs.size()
	var raw: PackedByteArray
	for line in 192:
		if ri < nr and runs[ri][0] == line:   # registers changed: reload the reference points that were written
			var prev := raw
			raw = runs[ri][1]
			ri += 1
			var x0 := raw.decode_u32(0x28)
			var x1 := raw.decode_u32(0x2C)
			var x2 := raw.decode_u32(0x38)
			var x3 := raw.decode_u32(0x3C)
			s0 = raw.decode_s16(0x22)
			s1 = raw.decode_s16(0x26)
			s2 = raw.decode_s16(0x32)
			s3 = raw.decode_s16(0x36)
			var first := line == 0
			r0 = _sx28(x0) if first or x0 != prev.decode_u32(0x28) else r0 + s0
			r1 = _sx28(x1) if first or x1 != prev.decode_u32(0x2C) else r1 + s1
			r2 = _sx28(x2) if first or x2 != prev.decode_u32(0x38) else r2 + s2
			r3 = _sx28(x3) if first or x3 != prev.decode_u32(0x3C) else r3 + s3
		else:
			r0 += s0
			r1 += s1
			r2 += s2
			r3 += s3
		var o := out.size()
		out.append_array(raw)
		out.encode_u32(o + 0x28, r0 & 0x0FFFFFFF)
		out.encode_u32(o + 0x2C, r1 & 0x0FFFFFFF)
		out.encode_u32(o + 0x38, r2 & 0x0FFFFFFF)
		out.encode_u32(o + 0x3C, r3 & 0x0FFFFFFF)
	return out


var fake_slow_us: int = 0   ## debug (GameDS `fakeslow=MS`): the game thread sleeps this long per frame (a slower CPU)


func _park() -> void:
	syncs += 1
	if fake_slow_us > 0:
		OS.delay_usec(fake_slow_us)
	if on_sync.is_valid():
		on_sync.call()
	run_us = Time.get_ticks_usec() - _run_t0
	_sem_done.post()
	if core.prof_on:
		var pt: int = core._prof_enter()
		_sem_go.wait()
		core._prof_leave(DSCoreBase.PROF_PARK, pt)
	else:
		_sem_go.wait()
	_run_t0 = Time.get_ticks_usec()


var run_us: int = 0     ## game-thread time of the last frame (woken up -> parked again), usec (part 26 perflog)
var _run_t0: int = 0


# ------------------------------------------------------------------------------------------------ IRQ timing
func _hblank() -> void:
	_irq(1)


func _irq(bit: int) -> void:
	if (_cb.IO.decode_u32(0x210) & (1 << bit)) == 0 or (_cb.IO.decode_u16(0x208) & 1) == 0:
		return
	if prof:
		var tq := Time.get_ticks_usec()
		_irq_run(bit)
		t_irq += Time.get_ticks_usec() - tq
	else:
		_irq_run(bit)


func _irq_run(bit: int) -> void:
	var h: int = core.r32(0x027E0004 + bit * 4)
	if h >= 0x02000000 and h < 0x020B7000:
		core.in_irq = true
		core._icall(h)
		core.in_irq = false
	core.irq_count += 1
	_irq_exit()


## next frame up to and including the VBlank interrupt
func _after_vblank() -> void:
	core._spin = 0
	core._sleep_spins = 0
	core.gx_cmds.clear()
	core.IO.encode_u16(0x130, keyinput)
	core.w16(0x027FFFA8, ext_keys)
	var dispstat: int = core.IO.decode_u16(4)
	core.vcount = 192
	core.hw.dma_start_timed(1)          # VBlank-timed DMA
	if dispstat & 0x8:
		_irq(0)
	else:
		core.w32(0x027E3FF8, core.r32(0x027E3FF8) | 1)
	if dispstat & 0x10:
		_hblank()
	core.w32(0x027FFC3C, core.r32(0x027FFC3C) + 1)   # ARM7 side: VBlank counter in the shared area
