class_name DSArm7
extends RefCounted
## High-level stand-in for the ARM7 processor's services, seen from the ARM9 through the IPC FIFO (PXI).
## The ARM9 code (NitroSDK libraries included) runs translated and unmodified; it sends 32-bit FIFO words
## (tag in bits 0-4, error bit 5, data in bits 6-31) and gets replies the same way, delivered as the
## IPC-receive interrupt. Each service below answers like the ARM7 component does.
##
## Tags (NitroSDK PXI_FIFO_TAG_*): 4 NVRAM, 5 RTC, 6 TOUCHPANEL, 7 SOUND, 8 PM, 9 MIC, 10 WM, 11 FS, 12 OS,
## 14 CARD.

const TAG_RTC := 5
const TAG_TP := 6
const TAG_SOUND := 7
const TAG_PM := 8
const TAG_CARD_BACKUP := 11

var core
var touch_raw: int = 0            ## value the ARM7 leaves at 0x027FFFAA (u32: x 12 bits, y 12 bits, touch, validity)
var unknown_seen: Dictionary = {}
var snd_commands: Array = []      ## sound commands received (when log_snd): [id, a0, a1, a2, a3]
var fixed_clock: Dictionary = {}
var backup := PackedByteArray()   ## save memory contents (the cartridge's EEPROM/FLASH)
var backup_dirty: bool = false
var _bk_cmd: int = 0              ## address of the ARM9's CARDiCommandArg block
var _bk_expect_addr: bool = false
## power-management IC registers (GBATEK "DS Power Management"): 0 control (bit0 amp, bit2/3 lower/upper
## backlight), 1 battery (0 = ok), 2 mic amp, 3 mic gain, 4 backlight level
var pm_regs := PackedByteArray([0x0D, 0x00, 0x00, 0x00, 0x03])  ## RTC override (lockstep determinism); empty = host clock
var log_fifo: bool = false
var log_snd: bool = false          ## keep the received sound commands in snd_commands (debugging)


var sound: DSSound


func _init(c) -> void:
	core = c
	sound = DSSound.new(c)


## ARM9 wrote IPCFIFOSEND
func fifo_in(word: int) -> void:
	var tag := word & 0x1F
	var err := (word >> 5) & 1
	var data := (word >> 6) & 0x3FFFFFF
	if log_fifo:
		print("PXI ARM9->ARM7 tag %d data %07x err %d" % [tag, data, err])
	match tag:
		TAG_TP:
			_tp(data)
		TAG_RTC:
			_rtc(data)
		TAG_SOUND:
			_sound(data)
		TAG_PM:
			_pm(data)
		TAG_CARD_BACKUP:
			_backup(data)
		_:
			if not unknown_seen.has(tag):
				unknown_seen[tag] = true
				push_warning("DSArm7: no service for PXI tag %d (data %07x)" % [tag, data])


func reply(tag: int, data: int, err: int = 0) -> void:
	core.ipc_push((tag & 0x1F) | ((err & 1) << 5) | ((data & 0x3FFFFFF) << 6))


# ------------------------------------------------------------------------------------------------ touch panel
## SPI protocol (NitroSDK spi/common): bit 25 start, bit 24 end, bits 8-14 command, bits 0-7 argument.
## Command 0 = sample once: the ARM7 stores the raw ADC reading at 0x027FFFAA and answers
## end-bit | command << 8 | result (0 = success).
func _tp(data: int) -> void:
	var cmd := (data >> 8) & 0x7F
	match cmd:
		0:
			core.w32(0x027FFFAA, touch_raw)
			reply(TAG_TP, 0x01000000 | (cmd << 8) | 0)
		_:
			reply(TAG_TP, 0x01000000 | (cmd << 8) | 0)


## Convert a touch on the bottom screen (pixels) to the raw ADC value the ARM7 would report, using the
## calibration points the firmware left in the shared user settings (0x027FFC80 + 0x58).
func set_touch(pressed: bool, sx: int, sy: int) -> void:
	if not pressed:
		touch_raw = 0
		return
	var b := 0x027FFC80
	var ax1: int = core.r16(b + 0x58)
	var ay1: int = core.r16(b + 0x5A)
	var sx1: int = core.r8(b + 0x5C)
	var sy1: int = core.r8(b + 0x5D)
	var ax2: int = core.r16(b + 0x5E)
	var ay2: int = core.r16(b + 0x60)
	var sx2: int = core.r8(b + 0x62)
	var sy2: int = core.r8(b + 0x63)
	var rx := ax1 + (sx - sx1) * (ax2 - ax1) / maxi(1, sx2 - sx1)
	var ry := ay1 + (sy - sy1) * (ay2 - ay1) / maxi(1, sy2 - sy1)
	touch_raw = (clampi(rx, 0, 0xFFF)) | (clampi(ry, 0, 0xFFF) << 12) | (1 << 24)


# ------------------------------------------------------------------------------------------------ RTC
## Commands (bits 8-14): 0x10 read date+time, 0x11 read date, 0x12 read time, 0x16/0x17 read status,
## 0x0x/0x2x writes. The ARM7 leaves BCD date at 0x027FFDE8 (year, month, day, weekday) and time at
## 0x027FFDEC (hour, minute, second), then answers command << 8 | result.
func _rtc(data: int) -> void:
	var cmd := (data >> 8) & 0x7F
	var t := fixed_clock if not fixed_clock.is_empty() else Time.get_datetime_dict_from_system()
	var date := _bcd(int(t.get("year", 2000)) % 100) | (_bcd(int(t.get("month", 1))) << 8) \
		| (_bcd(int(t.get("day", 1))) << 16) | ((int(t.get("weekday", 0)) & 7) << 24)
	var tim := _bcd(int(t.get("hour", 0))) | ((1 << 6) if int(t.get("hour", 0)) >= 12 else 0) \
		| (_bcd(int(t.get("minute", 0))) << 8) | (_bcd(int(t.get("second", 0))) << 16)
	if cmd >= 0x10 and cmd < 0x20:
		core.w32(0x027FFDE8, date)
		core.w32(0x027FFDEC, tim)
		core.w16(0x027FFDEA, (core.r16(0x027FFDEA) & 0xFF00) | 0x00)   # status: no alarm, 12h-format bit 0
	reply(TAG_RTC, (cmd << 8) | 0)


static func _bcd(v: int) -> int:
	return ((v / 10) << 4) | (v % 10)


# ------------------------------------------------------------------------------------------------ sound
## The ARM9 SND library queues command lists in main RAM (SNDCommand: next, id, arg[4]) and sends the list
## address. The ARM7 driver executes the list and increments SNDSharedWork.finishCommandTag (offset 0),
## which the ARM9 polls. Commands are handed to the port's sound layer through snd_commands.
## ---- sound: the original ARM7 sound driver (NitroSDK SND, translated: DSGame7) on the sound hardware (DSSound)
## The driver's thread (0x037FF17C) is run here: its init sequence once, then one loop iteration each time a
## message reaches its queue (interval alarm every 0xAA8 ticks = 5.2 ms: periodic work; PXI wakeup).
## ARM7 OS services it needs are provided here: ticks (64 bus cycles), alarms (scheduled in emulated time).
const SND_QUEUE := 0x038080DC             ## the driver thread's message queue (SND_WaitForIntervalTimer)
const SND_MSGBUF := 0x0380FF00            ## scratch word for the received message
const ARM7_SRC := 0x023801B0              ## autoload sources in the ARM7 binary (loaded at 0x02380000)
const ARM7_WRAM_SIZE := 0xFDD4
const ARM7_WRAM_BSS := 0x3758
const ARM7_MRAM_SIZE := 0x177DC
const ARM7_MRAM_BSS := 0x18B8

var core7                                 ## DSGame7
var cycles7: int = 0                      ## ARM7 time in bus cycles (33.513982 MHz)
var alarms: Dictionary = {}               ## OSAlarm address -> [fire_tick, period (0 = one shot), handler, arg]
var _in_driver: bool = false
var _driver_pending: bool = false         ## a message may be waiting for the driver thread
var _next_due: int = 0                    ## earliest alarm tick (skip the alarm scan before it)


func _update_next_due() -> void:
	_next_due = 1 << 62
	for k in alarms:
		_next_due = mini(_next_due, alarms[k][0])
var t_driver: int = 0                     ## profiling (usec): driver iterations / mixing
var t_mix: int = 0
var prof: bool = false                    ## part 32: time t_driver / t_mix (DSMachine.prof)


func boot_sound() -> void:
	core7 = DSGame7.new(core, sound)
	core7._register_all()
	var h: Dictionary = core7.hle
	var zero := func(_a = 0, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int: return 0
	for a in [0x037FC0B4, 0x037FC264, 0x037FC6B4, 0x037FC6E8, 0x037FDF48, 0x037FDF5C, 0x037FDF70, 0x037FDF88,
			0x037FDF9C, 0x037FDFB4, 0x03804118, 0x03804132, 0x037FB714, 0x03806724]:
		h[a] = zero
	h[0x037FD264] = func(_a = 0, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int: return cycles7 / 64
	h[0x037FD550] = _os_cancel_alarm
	h[0x037FD5E0] = _os_set_periodic_alarm
	h[0x037FD65C] = _os_set_alarm
	h[0x037FDFEC] = func(_a = 0, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int:
		push_error("DSArm7: ARM7 OS panic")
		return 0
	# runtime division helpers (same as the ARM9's, see DSCoreBase)
	h[0x038072EC] = core._rt_s32_div
	h[0x038074F8] = core._rt_u32_div
	h[0x03807500] = core._rt_u32_div
	h[0x038070E4] = core._rt_u64_div
	h[0x038070F0] = core._rt_u64_mod
	h[0x0380712C] = core._rt_s64_mod
	h[0x0380713C] = core._rt_s64_div
	h[0x03804188] = func(i = 0, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int: return DSBios7.pitch(i)
	h[0x0380418C] = func(i = 0, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int: return DSBios7.volume(i)
	# the ARM7 binary is in main RAM at 0x02380000 (DSBoot); crt0 autoloads its two segments
	var wram: PackedByteArray = core.M.slice(ARM7_SRC - 0x02000000, ARM7_SRC - 0x02000000 + ARM7_WRAM_SIZE)
	var src2 := ARM7_SRC + ARM7_WRAM_SIZE - 0x02000000
	var mram: PackedByteArray = core.M.slice(src2, src2 + ARM7_MRAM_SIZE)
	core7.load_image(PackedByteArray(), wram, ARM7_WRAM_BSS, mram, ARM7_MRAM_BSS)
	_in_driver = true
	core7.f7_03802d34()          # SND_CommandInit: command queue, PXI tag 7 callback
	core7.f7_037ff304()          # thread init: interval queue + alarm
	core7.f7_038002d0()          # SND_ExChannelInit
	core7.f7_03801f08()          # SND_SeqInit
	core7.f7_03802518()          # SND_AlarmInit
	core7.f7_037fea30()          # SND_Enable
	core7.f7_037fe8d8(0, 0, 0, 0)   # output selector
	core7.f7_037fe910(0x7F)      # master volume
	core7.f7_037ff2ac()          # start the interval timer (periodic alarm)
	_in_driver = false


func _os_set_alarm(alarm: int, tick_lo: int = 0, tick_hi: int = 0, handler: int = 0, arg: int = 0, _f = 0, _g = 0, _h = 0) -> int:
	var t := (tick_lo & 0xFFFFFFFF) | ((tick_hi & 0xFFFFFFFF) << 32)
	alarms[alarm] = [cycles7 / 64 + t, 0, handler, arg]
	core7._st(alarm, 4, handler)
	_update_next_due()
	return 0


func _os_set_periodic_alarm(alarm: int, start_lo: int = 0, start_hi: int = 0, per_lo: int = 0, per_hi: int = 0, handler: int = 0, arg: int = 0, _h = 0) -> int:
	var start := (start_lo & 0xFFFFFFFF) | ((start_hi & 0xFFFFFFFF) << 32)
	var period := (per_lo & 0xFFFFFFFF) | ((per_hi & 0xFFFFFFFF) << 32)
	alarms[alarm] = [start, maxi(period, 1), handler, arg]
	core7._st(alarm, 4, handler)
	_update_next_due()
	return 0


func _os_cancel_alarm(alarm: int, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int:
	alarms.erase(alarm)
	core7._st(alarm, 4, 0)
	_update_next_due()
	return 0


## emulated time passes (DSMachine, per scanline): ARM7 alarms, then the sound hardware mixes
func advance(cycles: int) -> void:
	if core7 == null:
		return
	var t0 := 0
	var t1 := 0
	if prof:   # part 32: clock reads only when profiling (GameDS perf / perflog)
		t0 = Time.get_ticks_usec()
		sound.advance(cycles)      # this scanline's time plays with the current channel state
		t1 = Time.get_ticks_usec()
		cycles7 += cycles
	else:
		var sn = sound.native      # (DSSound.advance inlined)
		if sn != null:
			sn.advance(cycles, [core.M])
		else:
			sound.advance(cycles)
		cycles7 += cycles
		if cycles7 / 64 < _next_due:   # part 32: no alarm due on this scanline (most lines): same as below, shorter
			if _driver_pending:
				_run_driver()
			return
	var now := cycles7 / 64
	var guard := 0
	if now < _next_due:
		guard = 64   # nothing due this scanline
	while guard < 64:
		var due := -1
		var best := 0
		for k in alarms:
			var e: Array = alarms[k]
			if e[0] <= now and (due < 0 or e[0] < best):
				due = k
				best = e[0]
		if due < 0:
			break
		if guard == 0:
			sound.flush()   # play what was due before the alarm handlers change sample data / registers
		var e: Array = alarms[due]
		if e[1] > 0:
			e[0] += e[1]
		else:
			alarms.erase(due)
			core7._st(due, 4, 0)
		core7._icall(e[2], e[3])
		_driver_pending = true
		guard += 1
		if guard == 64 or alarms.is_empty():
			break
	if guard > 0 and guard < 64 or now >= _next_due:
		_update_next_due()
	if not prof:
		if _driver_pending:
			_run_driver()
		return
	var t2 := Time.get_ticks_usec()
	if _driver_pending:
		_run_driver()
	t_driver += Time.get_ticks_usec() - t2
	t_mix += t1 - t0


## the driver thread: one loop iteration per queued message (1 = interval: periodic work, 2 = wakeup)
func _run_driver() -> void:
	if _in_driver:
		return
	_in_driver = true
	_driver_pending = false
	var guard := 0
	while guard < 16 and core7.f7_037fc78c(SND_QUEUE, SND_MSGBUF, 0) != 0:
		var periodic := 1 if core7._ld(SND_MSGBUF, 4, false) == 1 else 0
		core7.f7_038000e4()            # SND_UpdateExChannel
		core7.f7_038028bc()            # SND_CommandProc (command lists from the ARM9)
		core7.f7_03801e68(periodic)    # SND_SeqMain
		core7.f7_037ffdd8(periodic)    # SND_ExChannelMain
		core7.f7_038022a8()            # SND_UpdateSharedWork
		core7.f7_037fef24()            # random number update
		guard += 1
	_in_driver = false


func _sound(data: int) -> void:
	if log_snd and data >= 0x02000000:
		var p := data
		var guard := 0
		while p != 0 and guard < 256:
			snd_commands.append([core.r32(p + 4), core.r32(p + 8), core.r32(p + 12), core.r32(p + 16), core.r32(p + 20)])
			p = core.r32(p)
			guard += 1
	if core7 == null:
		return
	core7.f7_03802868(TAG_SOUND, data)   # the driver's PXI callback: queue the list / wake the thread
	_driver_pending = true
	_run_driver()


# ------------------------------------------------------------------------------------------------ power management
## SPI-style command (bits 8-14) with argument (bits 0-7). 0x65 = read register <arg>: the answer comes back as
## command 0x70 + register with the value in bits 0-7 (see the ARM9 callback 0x020B0B8C). Writes answer
## command << 8 | 0 (success).
func _pm(data: int) -> void:
	var cmd := (data >> 8) & 0x7F
	var arg := data & 0xFF
	match cmd:
		0x65:
			var reg := arg & 7
			reply(TAG_PM, ((0x70 + reg) << 8) | (pm_regs[reg] if reg < pm_regs.size() else 0))
		0x64:   # write register: high byte of the next word in the original protocol; keep it simple
			reply(TAG_PM, (cmd << 8) | 0)
		_:
			reply(TAG_PM, (cmd << 8) | 0)


# ------------------------------------------------------------------------------------------------ save memory
## CARD backup requests (ARM9 0x020B28B4): the request number is sent with the error bit set; request 0 (init)
## is followed by the address of the shared command block {+0 result, +0xC src, +0x10 dst, +0x14 len}.
## Requests: 2 identify, 6 read, 7 write, 8 program, 9 verify, 10-12 erase page/sector/chip, 13 status.
## The ARM7 answers with the error bit set once the block's result is filled in.
var _bk_total: int = 0


func _bk_addr(a: int) -> int:
	return a & (_bk_total - 1) if _bk_total > 0 else a


func _bk_grow(n: int) -> void:
	var old_size := backup.size()
	if n > old_size:
		backup.resize(n)
		for i in range(old_size, n):
			backup[i] = 0xFF


func _backup(data: int) -> void:
	if _bk_expect_addr:
		_bk_cmd = data
		_bk_expect_addr = false
		core.w32(_bk_cmd, 0)
		reply(TAG_CARD_BACKUP, 0, 1)
		return
	var req := data
	if req == 0:
		_bk_expect_addr = true
		return
	var result := 0
	if _bk_cmd != 0:
		var src: int = core.r32(_bk_cmd + 0xC)
		var dst: int = core.r32(_bk_cmd + 0x10)
		var n: int = core.r32(_bk_cmd + 0x14)
		if log_fifo:
			print("BACKUP req %d src %x dst %x len %x" % [req, src, dst, n])
		match req:
			2:   # identify: describe the chip for the type the ARM9 announced at +4 (kind | log2(size) << 8)
				var type: int = core.r32(_bk_cmd + 4)
				var kind := type & 0xFF
				var total := (1 << ((type >> 8) & 0xFF)) if type != 0 else 0
				var page := 0x20
				var width := 2
				var sector := 0
				if kind == 1:     # EEPROM
					page = 0x10 if total <= 0x200 else (0x20 if total <= 0x2000 else 0x80)
					width = 1 if total <= 0x200 else (2 if total <= 0x10000 else 3)
				elif kind == 2:   # FLASH
					page = 0x100
					width = 3
					sector = 0x10000
				elif kind == 3:   # FRAM
					page = total
					width = 2 if total <= 0x10000 else 3
				core.w32(_bk_cmd + 0x18, total)
				core.w32(_bk_cmd + 0x1C, sector)
				core.w32(_bk_cmd + 0x20, page)
				core.w32(_bk_cmd + 0x24, width)
				core.w32(_bk_cmd + 0x28, 0x4F if kind == 1 else 0x7F)
				_bk_total = total
				_bk_grow(total)
			6:   # read: save[src..] -> RAM[dst..] (chip addresses wrap at the chip size, like the hardware)
				for i in n:
					var a := _bk_addr(src + i)
					core.w8(dst + i, backup[a] if a < backup.size() else 0xFF)
			7, 8:   # write / program: RAM[src..] -> save[dst..]
				for i in n:
					var a := _bk_addr(dst + i)
					if a >= backup.size():
						_bk_grow(a + 1)
					backup[a] = core.r8(src + i)
				backup_dirty = true
			9:   # verify
				for i in n:
					var a := _bk_addr(dst + i)
					if a >= backup.size() or backup[a] != core.r8(src + i):
						result = 1
						break
			10, 11, 12:
				backup_dirty = true
		core.w32(_bk_cmd, result)
	reply(TAG_CARD_BACKUP, 0, 1)
