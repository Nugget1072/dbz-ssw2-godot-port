class_name DSCoreBase
extends RefCounted
## Runtime for code translated from the DS ARM9 binary by decomp/tools/ghidra2gd.py.
##
## M is an 8 MiB image of the ARM9 address range 0x02000000-0x027FFFFF (main RAM incl. mirrors area and
## DTCM at 0x027E0000), so every pointer in the translated code is the original DS address.
## Hardware registers / VRAM / OAM / palette (0x04xxxxxx-0x07xxxxxx) go through io_read/io_write, which
## implement the math coprocessor (DIV/SQRT) and record everything else for the HLE layers.

const BASE := 0x02000000
const SIZE := 0x00800000
const STACK_TOP := 0x027E3F00     ## emulated stack for locals whose address is taken (DTCM, like the DS)

var M := PackedByteArray()
var _sp: int = STACK_TOP - 0x3D00   ## the main thread's frames grow upwards from 0x027E0200 (15 KiB, like the DS stack)
var _fn: Dictionary = {}          ## address -> Callable (indirect call dispatch)
var _missing_seen: Dictionary = {}
var hle: Dictionary = {}          ## address -> Callable overriding translated/missing functions
var io: Dictionary = {}           ## last written value per IO address (for HLE inspection)
var trace_missing: bool = true

var hw: DSHardware
var arm7: DSArm7
var timers: DSTimers
var irq_count: int = 0             ## interrupts taken so far (OS_Halt / IntrWait wake-up test)
var on_irq_exit: Callable          ## set by DSMachine: OS_IrqHandler's tail (thread rescheduling)
var ipc_recv: Array = []          ## ARM7 -> ARM9 FIFO words not yet read
var _ipc_last: int = 0


func _init() -> void:
	M.resize(SIZE)
	_io_init()
	hw = DSHardware.new(self)
	arm7 = DSArm7.new(self)
	timers = DSTimers.new(self)
	# CPU-state functions (mrs/msr): interrupt enable flag and processor mode
	hle[0x020AB358] = func(_a = 0, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int: return _set_i(0, 0x80)
	hle[0x020AB36C] = func(_a = 0, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int: return _set_i(0x80, 0x80)
	hle[0x020AB380] = func(a = 0, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int: return _set_i(int(a) & 0x80, 0x80)
	hle[0x020AB398] = func(_a = 0, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int: return _set_i(0xC0, 0xC0)
	hle[0x020AB3AC] = func(a = 0, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int: return _set_i(int(a) & 0xC0, 0xC0)
	hle[0x020AB3C4] = func(_a = 0, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int: return 0x12 if in_irq else 0x1F
	hle[0x020AB3E8] = _os_terminate
	hle[0x020B1A2C] = _card_set_task
	# Metrowerks runtime division helpers (ARM9 0x020B5C28..0x020B6230). They return quotient in r0 and
	# remainder in r1; Ghidra is told they return 64-bit (r0:r1), so results are packed q | r << 32.
	hle[0x020B5E30] = _rt_s32_div
	hle[0x020B603C] = _rt_u32_div
	hle[0x020B6044] = _rt_u32_div
	hle[0x020B5C28] = _rt_u64_div
	hle[0x020B5C34] = _rt_u64_mod
	hle[0x020B5C70] = _rt_s64_mod
	hle[0x020B5C80] = _rt_s64_div


# ---------------------------------------------------------------- BIOS calls
## The ARM9 binary carries Thumb wrappers `swi #n; bx lr` (0x02000000..0x02000800) for the BIOS functions.
## Each one found is replaced by the BIOS function it calls (GBATEK "BIOS Functions"), arguments in r0..r3.
var bios_wrappers: Dictionary = {}   ## wrapper address -> swi number


# ------------------------------------------------------------------------------------------------ fast paths
## Native versions (native/src/ds_mem_native.cpp) of the NitroSDK memory functions marked FASTPATH in
## decomp/tools/ghidra2gd.py, for main-RAM addresses (offset = address - 0x02000000 in M). Same bytes as the
## original code; anything else (VRAM, no native library) returns null and the translated code runs.
var _fast_on: bool = true
var _native: bool = ClassDB.class_exists("DSMemNative")
## OS_SpinWait (0x020AB3DC) burns `cycles` ARM9 cycles; the machine lets that much emulated time pass (the SDK
## waits this way for the ARM7, e.g. for free sound command buffers - without time passing, the ARM7 never
## answered and the wait spun for seconds). Set by DSMachine.
var on_spin_wait: Callable
var fs_native := true     ## FSi_FindPath fast path on (lockstep fsnative=0 compares with the original)
var fs_fast := [0, 0]   ## path lookups done natively / by the translated original (preconditions unmet)


func _fast_call(addr: int, a0: int, a1: int, a2: int) -> Variant:
	if addr == 0x020AB3DC:
		if not on_spin_wait.is_valid():
			return null
		on_spin_wait.call(a0 & 0xFFFFFFFF)
		return ((a0 & 3) - 4) & 0xFFFFFFFF
	if not _native:
		return null
	if addr == 0x020B23F0:
		return _fast_card_read(a0)
	if addr == 0x020ADF08 and fs_native:   # FSi_FindPath(file): the file-name-table walk in C++ (DSFSNative); -1 = preconditions unmet
		var r: int = DSFSNative.find_path([M], a0, _sp)
		fs_fast[0 if r >= 0 else 1] += 1
		return r if r >= 0 else null
	var h := [M]
	if _vram(a1) or (addr == 0x020ABC4C and _vram(a0)):
		return _fast_vram(addr, a0, a1, a2, h)
	match addr:
		0x020ABB30:   # MIi_CpuClear16(data, dest, size)
			if _ram(a1) and DSMemNative.clear16(h, a0, a1 - 0x2000000, a2):
				return a0
		0x020ABB48:   # MIi_CpuCopy16(src, dest, size)
			if _ram(a0) and _ram(a1) and DSMemNative.copy16(h, a0 - 0x2000000, a1 - 0x2000000, a2):
				return a0
		0x020ABB64, 0x020ABB90:   # MIi_CpuClear32 / MIi_CpuClearFast(data, dest, size)
			if _ram(a1) and DSMemNative.clear32(h, a0, a1 - 0x2000000, a2):
				return a0
		0x020ABB78, 0x020ABBDC:   # MIi_CpuCopy32 / MIi_CpuCopyFast(src, dest, size)
			if _ram(a0) and _ram(a1) and DSMemNative.copy32(h, a0 - 0x2000000, a1 - 0x2000000, a2):
				return a0
		0x020ABC4C:   # MI_CpuFill8(dest, data, size)
			if _ram(a0) and DSMemNative.fill8(h, a0 - 0x2000000, a1, a2):
				return a0
		0x020ABCE0:   # MI_CpuCopy8(src, dest, size)
			if _ram(a0) and _ram(a1) and DSMemNative.copy8(h, a0 - 0x2000000, a1 - 0x2000000, a2):
				return a0
		0x020ABE18, 0x020ABF84:   # MI_UncompressLZ8 / MI_UncompressRL8(src, dest) -> source end pointer
			if _ram(a0) and _ram(a1):
				var end: int = DSMemNative.uncompress_lz8(h, a0 - 0x2000000, a1 - 0x2000000) if addr == 0x020ABE18 \
					else DSMemNative.uncompress_rl8(h, a0 - 0x2000000, a1 - 0x2000000)
				if end >= 0:
					return end + 0x2000000
	return null


## the same functions with a VRAM destination: the bytes are built natively and written through the VRAM
## mapping (DSHardware.vram_write_bytes); sources outside main RAM fall back to the translated code
func _fast_vram(addr: int, a0: int, a1: int, a2: int, h: Array) -> Variant:
	var size := a2 & 0xFFFFFFFF
	var bytes := PackedByteArray()
	var dest := a1
	match addr:
		0x020ABB30, 0x020ABB64, 0x020ABB90:   # clear16 / clear32 / clearFast(data, dest, size)
			if size >= 0x80000000:
				return a0
			var unit := 2 if addr == 0x020ABB30 else 4
			var n := (size + unit - 1) / unit * unit
			bytes = _pattern(a0, unit, n)
		0x020ABB48, 0x020ABB78, 0x020ABBDC:   # copy16 / copy32 / copyFast(src, dest, size)
			if size >= 0x80000000:
				return a0
			var unit := 2 if addr == 0x020ABB48 else 4
			var n := (size + unit - 1) / unit * unit
			if not _ram(a0) or not _ram(a0 + n - 1):
				return null
			bytes = M.slice(a0 - 0x2000000, a0 - 0x2000000 + n)
		0x020ABC4C:   # MI_CpuFill8(dest, data, size)
			dest = a0
			bytes.resize(size)
			bytes.fill(a1 & 0xFF)
		0x020ABCE0:   # MI_CpuCopy8(src, dest, size)
			if not _ram(a0) or not _ram(a0 + size - 1):
				return null
			bytes = M.slice(a0 - 0x2000000, a0 - 0x2000000 + size)
		0x020ABE18, 0x020ABF84:   # MI_UncompressLZ8 / MI_UncompressRL8(src, dest) -> source end pointer
			if not _ram(a0):
				return null
			var res: Array = DSMemNative.uncompress_lz8_buf(h, a0 - 0x2000000) if addr == 0x020ABE18 \
				else DSMemNative.uncompress_rl8_buf(h, a0 - 0x2000000)
			if res.is_empty():
				return null
			bytes = res[0]
			if not bytes.is_empty():
				hw.vram_write_bytes(dest & 0xFFFFFFFF, bytes)
			return int(res[1]) + 0x2000000
		_:
			return null
	if not bytes.is_empty():
		hw.vram_write_bytes(dest & 0xFFFFFFFF, bytes)
	return a0


## CARD ROM read loop (0x020B23F0, argument = the CARD command block): per 512-byte block it selects the
## destination (the final buffer when aligned, else the block's cache at +0x20), sets up command 0xB7
## (0x020B277C), starts the transfer by writing ROMCTRL and stores every data word the card delivers, then
## advances the request (0x020E5240: +0x18 card address, +0x1C destination, +0x20 bytes left) or lets
## 0x020B281C copy from the cache. Same steps as the translated loop, but the words of a transfer are moved in
## one go instead of being polled one by one through ROMCTRL / 0x04100010.
func _fast_card_read(sl: int) -> Variant:
	const SB := 0x020E5240
	while true:
		var r0 := r32(SB + 0x18)
		var r1 := r0 & 0xFFFFFE00
		var r8: int
		if r1 == r0 and (r32(SB + 0x1C) & 3) == 0 and r32(SB + 0x20) >= 0x200:
			r8 = r32(SB + 0x1C)
		else:
			r8 = (sl + 0x20) & 0xFFFFFFFF
			w32(sl + 8, r1)
		_icall(0x020B277C, (r1 >> 8) | 0xB7000000, (r1 << 24) & 0xFFFFFFFF)
		io_write(0x040001A4, 4, r32(sl + 4))
		var data: PackedByteArray = hw.card_take_all()
		var n := mini(data.size() / 4, 0x200) * 4
		if n > 0:
			if _ram(r8) and _ram(r8 + n - 1):
				DSMemNative.blit([M], 0, r8 - 0x2000000, data, 0, n)
			else:
				for k in range(0, n, 4):
					w32(r8 + k, data.decode_u32(k))
		if r8 == r32(SB + 0x1C):
			w32(SB + 0x18, r32(SB + 0x18) + 0x200)
			w32(SB + 0x1C, r32(SB + 0x1C) + 0x200)
			var left := (r32(SB + 0x20) - 0x200) & 0xFFFFFFFF
			w32(SB + 0x20, left)
			if left != 0:
				continue
			return 0
		if _icall(0x020B281C, sl) == 0:
			return 0
	return 0


## n bytes repeating the low `unit` bytes of v
static func _pattern(v: int, unit: int, n: int) -> PackedByteArray:
	var b := PackedByteArray()
	if unit == 2 and (v & 0xFF) == ((v >> 8) & 0xFF) or unit == 4 and (v & 0xFFFFFFFF) == (v & 0xFF) * 0x01010101:
		b.resize(n)
		b.fill(v & 0xFF)
		return b
	b.resize(unit)
	if unit == 2:
		b.encode_u16(0, v & 0xFFFF)
	else:
		b.encode_u32(0, v & 0xFFFFFFFF)
	while b.size() < n:
		b.append_array(b)
	return b.slice(0, n)


static func _vram(a: int) -> bool:
	a &= 0xFFFFFFFF
	return a >= 0x06000000 and a < 0x07000000


static func _ram(a: int) -> bool:
	a &= 0xFFFFFFFF
	return a >= 0x02000000 and a < 0x02800000


func install_bios_hle() -> void:
	for o in range(0, 0x800, 2):
		if M[o + 1] == 0xDF and M.decode_u16(o + 2) == 0x4770:
			var n: int = M[o]
			var f: Callable
			match n:
				0x03: f = func(_a = 0, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int: return 0   # WaitByLoop
				0x0B: f = _bios_cpu_set
				0x0C: f = _bios_cpu_fast_set
				0x0E: f = _bios_crc16
				0x0D: f = func(a = 0, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int: return int(sqrt(float(int(a) & 0xFFFFFFFF)))
				0x0F: f = func(_a = 0, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int: return 0   # IsDebugger: no
				_: continue
			bios_wrappers[BASE + o] = n
			hle[BASE + o] = f


## CpuSet: r0 src, r1 dst, r2 = count (bits 0-20) | fill (bit 24) | 32-bit units (bit 26)
func _bios_cpu_set(src: int = 0, dst: int = 0, ctl: int = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int:
	var n := ctl & 0x1FFFFF
	var w := 4 if (ctl & 0x4000000) != 0 else 2
	src &= ~(w - 1)
	dst &= ~(w - 1)
	var fill := (ctl & 0x1000000) != 0
	var v := _ld(src, w, false)
	for i in n:
		if not fill:
			v = _ld(src + i * w, w, false)
		_st(dst + i * w, w, v)
	return 0


## CpuFastSet: like CpuSet in 32-bit units, count rounded up to 8 words
func _bios_cpu_fast_set(src: int = 0, dst: int = 0, ctl: int = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int:
	var n := ((ctl & 0x1FFFFF) + 7) & ~7
	return _bios_cpu_set(src, dst, n | (ctl & 0x1000000) | 0x4000000)


## GetCRC16: r0 initial value, r1 address, r2 length in bytes (CRC-16, reflected polynomial 0xA001)
func _bios_crc16(crc: int = 0, src: int = 0, n: int = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int:
	crc &= 0xFFFF
	src &= ~1
	n &= ~1
	var o := src - BASE
	var fast := o >= 0 and o + n <= SIZE
	for i in n:
		crc ^= M[o + i] if fast else _ld(src + i, 1, false)
		for j in 8:
			crc = (crc >> 1) ^ 0xA001 if (crc & 1) != 0 else crc >> 1
	return crc


# ---------------------------------------------------------------- CPU state / interrupts
var cpsr_if: int = 0       ## CPSR I (0x80) and F (0x40) bits
var in_irq: bool = false


## sets the masked CPSR bits to `bits`, returns their previous value; re-enabling delivers pending IRQs
func _set_i(bits: int, mask: int) -> int:
	var old := cpsr_if & mask
	cpsr_if = (cpsr_if & ~mask) | (bits & mask)
	if (cpsr_if & 0x80) == 0 and not in_irq:
		_deliver_pending_irqs()
	return old


## ARM7 -> ARM9 FIFO word; raises the IPC receive-not-empty IRQ (bit 18) when enabled in IPCFIFOCNT
func ipc_push(word: int) -> void:
	ipc_recv.append(word & 0xFFFFFFFF)
	if (IO.decode_u16(0x184) & 0x8400) == 0x8400:
		raise_irq(18)


## hardware raises IRQ `bit` (IF |= 1 << bit) and the CPU takes it if IME, IE and CPSR allow
func raise_irq(bit: int) -> void:
	IO.encode_u32(0x214, IO.decode_u32(0x214) | (1 << bit))
	if (cpsr_if & 0x80) == 0 and not in_irq:
		_deliver_pending_irqs()


## OS_IrqHandler (ITCM 0x01FF8000): dispatch IF & IE through OS_IRQTable (DTCM 0x027E0004); the handlers
## acknowledge IF themselves (via OS_SetIrqCheckFlag/IF writes).
func _deliver_pending_irqs() -> void:
	var guard := 0
	var taken := 0
	while (IO.decode_u16(0x208) & 1) != 0 and guard < 32:
		var pending := IO.decode_u32(0x214) & IO.decode_u32(0x210)
		if pending == 0:
			break
		var bit := 0
		while (pending & (1 << bit)) == 0:
			bit += 1
		IO.encode_u32(0x214, IO.decode_u32(0x214) & ~(1 << bit))
		var h := r32(0x027E0004 + bit * 4)
		if h >= 0x02000000 and h < 0x020B7000:
			in_irq = true
			_icall(h)
			in_irq = false
		irq_count += 1
		taken += 1
		guard += 1
	if taken > 0 and on_irq_exit.is_valid():
		on_irq_exit.call()


## CARDi_SetTask (0x020B1A2C): the CARD library hands a job to its worker thread (0x020B29F0) and wakes it.
## The port has no threads, so the job runs right here; it ends with CARDi_EndTask, which clears the busy
## flags and calls the completion callback exactly as the worker would.
const CARD_COMMON := 0x020E5240


var _card_pending: int = 0


func _card_set_task(task: int, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int:
	w32(CARD_COMMON + 0xD4, CARD_COMMON + 0x40)
	w32(CARD_COMMON + 0x3C, task)
	w32(CARD_COMMON + 0xE0, r32(CARD_COMMON + 0xE0) | 8)
	# the worker has a higher priority than the caller: waking it switches to it at once
	_card_pending = 0
	_icall(task, CARD_COMMON)
	return 0


## Work the other threads would do while the current one is blocked: the CARD worker's pending job.
## (The sound-stream thread is not run: the port plays music itself.)
func run_other_threads() -> void:
	if _card_pending != 0:
		var task := _card_pending
		_card_pending = 0
		_icall(task, CARD_COMMON)


## OS_SleepThread (0x020AA100): the caller blocks until another thread or an IRQ wakes it. Without real
## threads: let the other threads' pending work and pending interrupts run, then return to the caller,
## which re-checks its wait condition (all SDK waits are loops around OS_SleepThread).
var _sleep_spins: int = 0


func _os_sleep_thread(_queue = 0, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int:
	var was_i := cpsr_if
	run_other_threads()
	cpsr_if &= ~0x80
	_deliver_pending_irqs()
	cpsr_if = was_i
	_sleep_spins += 1
	if _sleep_spins == 100000:
		push_error("DSCore: thread sleeps forever? " + str(get_stack().slice(1, 6).map(func(d): return "%s:%d" % [d["function"], d["line"]])))
	return 0


func _os_terminate(_a = 0, _b = 0, _c = 0, _d = 0, _e = 0, _f = 0, _g = 0, _h = 0) -> int:
	push_error("DSCore: OS_Terminate (assertion failure in the original code) " + str(get_stack().slice(1, 6).map(func(d): return d["function"])))
	return 0


# ---------------------------------------------------------------- runtime library (verified vs disassembly)
static func _pack(q: int, r: int) -> int:
	return (q & 0xFFFFFFFF) | ((r & 0xFFFFFFFF) << 32)


## _s32_div_f 0x020B5E30: signed; divide by 0 gives q = n, r = 0.
func _rt_s32_div(n: int, d: int, _a2 = 0, _a3 = 0, _a4 = 0, _a5 = 0, _a6 = 0, _a7 = 0) -> int:
	n = _sx32(n)
	d = _sx32(d)
	var un := absi(n) & 0xFFFFFFFF
	var ud := absi(d) & 0xFFFFFFFF
	var q := un
	var r := 0
	if ud != 0:
		q = un / ud
		r = un % ud
	if (n < 0) != (d < 0):
		q = -q
	if n < 0:
		r = -r
	return _pack(q, r)


## _u32_div_f 0x020B603C / 0x020B6044: unsigned; divide by 0 gives q = n, r = 0.
func _rt_u32_div(n: int, d: int, _a2 = 0, _a3 = 0, _a4 = 0, _a5 = 0, _a6 = 0, _a7 = 0) -> int:
	n &= 0xFFFFFFFF
	d &= 0xFFFFFFFF
	if d == 0:
		return _pack(n, 0)
	return _pack(n / d, n % d)


## 64-bit helpers: Ghidra declares (u)longlong (n, d), so each argument arrives as one 64-bit int.
## Divide by 0 returns the numerator (both quotient and remainder entry points).
static func _udiv64(n: int, d: int) -> Array:
	if d == 0:
		return [n, n]
	if d < 0:   # d >= 2^63: quotient is 0 or 1
		return [1, n - d] if _uge(n, d) else [0, n]
	if n >= 0:
		return [n / d, n % d]
	var q := (((n >> 1) & 0x7FFFFFFFFFFFFFFF) / d) << 1
	var r := n - q * d
	if _uge(r, d):
		q += 1
		r -= d
	return [q, r]


static func _ult(a: int, b: int) -> bool:
	return (a ^ (1 << 63)) < (b ^ (1 << 63))


static func _uge(a: int, b: int) -> bool:
	return not _ult(a, b)


func _rt_u64_div(a0: int, a1: int, a2 = 0, a3 = 0, _a4 = 0, _a5 = 0, _a6 = 0, _a7 = 0) -> int:
	var nd := [a0, a1]
	return _udiv64(nd[0], nd[1])[0]


func _rt_u64_mod(a0: int, a1: int, a2 = 0, a3 = 0, _a4 = 0, _a5 = 0, _a6 = 0, _a7 = 0) -> int:
	var nd := [a0, a1]
	return _udiv64(nd[0], nd[1])[1] if nd[1] != 0 else nd[0]


func _rt_s64_div(a0: int, a1: int, a2 = 0, a3 = 0, _a4 = 0, _a5 = 0, _a6 = 0, _a7 = 0) -> int:
	var nd := [a0, a1]
	if nd[1] == 0:
		return nd[0]
	return _div(nd[0], nd[1])


func _rt_s64_mod(a0: int, a1: int, a2 = 0, a3 = 0, _a4 = 0, _a5 = 0, _a6 = 0, _a7 = 0) -> int:
	var nd := [a0, a1]
	if nd[1] == 0:
		return nd[0]
	return _mod(nd[0], nd[1])


## Load the ARM9 binary (code + static data) at 0x02000000 like the DS loader.
func load_arm9(bytes: PackedByteArray) -> void:
	for i in bytes.size():
		M[i] = bytes[i]


## Copy a RAM snapshot (e.g. dumped from melonDS) into M. `offset` relative to BASE.
func load_snapshot(bytes: PackedByteArray, offset: int = 0) -> void:
	for i in bytes.size():
		M[offset + i] = bytes[i]


# ---------------------------------------------------------------- memory helpers (outside generated code)
func r8(a: int) -> int: return M.decode_u8(a - BASE)
func r16(a: int) -> int: return M.decode_u16(a - BASE)
func r32(a: int) -> int: return M.decode_u32(a - BASE)
func s8(a: int) -> int: return M.decode_s8(a - BASE)
func s16(a: int) -> int: return M.decode_s16(a - BASE)
func s32(a: int) -> int: return M.decode_s32(a - BASE)
func w8(a: int, v: int) -> void: M.encode_u8(a - BASE, v & 0xFF)
func w16(a: int, v: int) -> void: M.encode_u16(a - BASE, v & 0xFFFF)
func w32(a: int, v: int) -> void: M.encode_u32(a - BASE, v & 0xFFFFFFFF)


## run-time dispatched access for pointers that may hold IO addresses (see ghidra2gd taint pass)
func _ld(a: int, size: int, signed: bool) -> int:
	a &= 0xFFFFFFFF   # 32-bit address space (pointer + negative offset computed in 64 bits)
	var o := a - BASE
	if o < 0 or o >= SIZE:
		var v := io_read(a & 0xFFFFFFFF, size) if (a >> 24) != 0x02 else 0
		if signed:
			var h := 1 << (8 * size - 1)
			v = ((v + h) & ((h << 1) - 1)) - h
		return v
	match size:
		1: return M.decode_s8(o) if signed else M.decode_u8(o)
		2: return M.decode_s16(o) if signed else M.decode_u16(o)
		4: return M.decode_s32(o) if signed else M.decode_u32(o)
	return M.decode_s64(o)


## call tracing (debug builds made with TRACE=1)
var _tracing: bool = false
var trace_log: PackedStringArray = []
## PROFILE=1 builds of ds_game.gd: self time (usec) and calls per function address. DSMachine adds pseudo
## frames (PROF_LINES, PROF_PARK, PROF_SWITCH) so scanline events, the frame hand-over and blocked threads do
## not count as their caller's own time.
const PROF_LINES := 1
const PROF_PARK := 2
const PROF_SWITCH := 3
var prof_on: bool = false
var prof_self: Dictionary = {}
var prof_calls: Dictionary = {}
var _pst: Dictionary = {}               ## thread id -> stack of child-time accumulators


func _prof_stack() -> Array:
	var id := OS.get_thread_caller_id()
	var st = _pst.get(id)
	if st == null:
		st = []
		_pst[id] = st
	return st


func _prof_enter() -> int:
	_prof_stack().append(0)
	return Time.get_ticks_usec()


func _prof_leave(key: int, t0: int) -> void:
	var dt := Time.get_ticks_usec() - t0
	var st := _prof_stack()
	var c: int = st.pop_back()
	prof_self[key] = int(prof_self.get(key, 0)) + dt - c
	prof_calls[key] = int(prof_calls.get(key, 0)) + 1
	if not st.is_empty():
		st[-1] += dt


var trace_stack: String = ""


var _break_on: bool = false
var break_addr: int = -1          ## TRACE builds: call on_break when this function is entered for the
var break_count: int = 1          ## break_count-th time (code-point alignment with tools/melonds-headless/breakref.py)
var _break_hits: int = 0
var on_break: Callable


func _trace(addr: int, params: Array) -> void:
	if addr == break_addr and (params.is_empty() or params[0] != -1):
		_break_hits += 1
		if _break_hits == break_count and on_break.is_valid():
			on_break.call()
	if not _tracing:
		return
	if trace_stack == "":
		trace_stack = str(get_stack().map(func(d): return "%s:%d" % [d["function"], d["line"]]))
	trace_log.append("%s%08x(%s)" % ["  ".repeat(mini(get_stack().size(), 40)), addr, ", ".join(params.map(func(p): return "%x" % (p & 0xFFFFFFFF)))])


## write watchpoints (debug builds made with WATCH=1 route every store through _st): [lo, hi) ranges
var watch: Array = []


func _st(a: int, size: int, v: int) -> void:
	a &= 0xFFFFFFFF
	var o := a - BASE
	if not watch.is_empty():
		for w in watch:
			if a < w[1] and a + size > w[0]:
				print("WATCH %08x <- %x (%d bytes) " % [a, v, size], get_stack().slice(1, 6).map(func(d): return "%s:%d" % [d["function"], d["line"]]))
	if o < 0 or o >= SIZE:
		io_write(a & 0xFFFFFFFF, size, v & ((1 << (8 * size)) - 1) if size < 8 else v)
		return
	match size:
		1: M.encode_u8(o, v & 0xFF)
		2: M.encode_u16(o, v & 0xFFFF)
		4: M.encode_u32(o, v & 0xFFFFFFFF)
		_: M.encode_s64(o, v)


# ---------------------------------------------------------------- calls
func _icall(addr: int, a0: int = 0, a1: int = 0, a2: int = 0, a3: int = 0, a4: int = 0, a5: int = 0, a6: int = 0, a7: int = 0) -> int:
	addr &= 0xFFFFFFFE   # thumb bit
	if hle.has(addr):
		return int((hle[addr] as Callable).call(a0, a1, a2, a3, a4, a5, a6, a7))
	if _fn.has(addr):
		return int((_fn[addr] as Callable).call(a0, a1, a2, a3, a4, a5, a6, a7))
	return _missing(addr)


## SDK/hardware functions replaced by high-level emulation. Unknown ones are no-ops returning 0
## (recorded in hle_hits so the lockstep tests show which ones run).
var hle_hits: Dictionary = {}


func _hle(addr: int, a0: int = 0, a1: int = 0, a2: int = 0, a3: int = 0, a4: int = 0, a5: int = 0, a6: int = 0, a7: int = 0) -> int:
	hle_hits[addr] = int(hle_hits.get(addr, 0)) + 1
	if _tracing and addr != 0x020AB36C and addr != 0x020AB380:
		_trace(addr, [a0, a1, a2, a3])
	if hle.has(addr):
		return int((hle[addr] as Callable).call(a0, a1, a2, a3, a4, a5, a6, a7))
	return 0


func _missing(addr: int) -> int:
	if hle.has(addr):
		return 0
	if trace_missing and not _missing_seen.has(addr):
		_missing_seen[addr] = true
		push_warning("DSCore: function %08x not translated/HLE'd" % addr)
	return 0


func _unrecovered(addr: int) -> int:
	if trace_missing and not _missing_seen.has(addr | 1):
		_missing_seen[addr | 1] = true
		push_warning("DSCore: unrecovered jump table in %08x" % addr)
	return 0


# ---------------------------------------------------------------- C arithmetic helpers
static func _div(a: int, b: int) -> int:
	if b == 0:
		return 0
	var q := absi(a) / absi(b)
	return -q if (a < 0) != (b < 0) else q


static func _mod(a: int, b: int) -> int:
	if b == 0:
		return a
	return a - _div(a, b) * b


func CONCAT11(a: int, b: int) -> int: return ((a & 0xFF) << 8) | (b & 0xFF)
func CONCAT22(a: int, b: int) -> int: return ((a & 0xFFFF) << 16) | (b & 0xFFFF)
func CONCAT31(a: int, b: int) -> int: return ((a & 0xFFFFFF) << 8) | (b & 0xFF)
func CONCAT44(a: int, b: int) -> int: return ((a & 0xFFFFFFFF) << 32) | (b & 0xFFFFFFFF)
func CARRY4(a: int, b: int) -> int: return 1 if (a & 0xFFFFFFFF) + (b & 0xFFFFFFFF) > 0xFFFFFFFF else 0
func SCARRY4(a: int, b: int) -> int:
	var r := (a + b + 0x80000000 & 0xFFFFFFFF) - 0x80000000
	return 1 if r != a + b else 0
func SBORROW4(a: int, b: int) -> int:
	var r := (a - b + 0x80000000 & 0xFFFFFFFF) - 0x80000000
	return 1 if r != a - b else 0
func LZCOUNT(a: int) -> int:
	a &= 0xFFFFFFFF
	var n := 0
	while n < 32 and (a & 0x80000000) == 0:
		a <<= 1
		n += 1
	return n
func __swi(_n: int = 0, _a: int = 0, _b: int = 0) -> int: return 0
func software_interrupt(_n: int = 0) -> int: return 0
func coprocessor_moveto(_a: int = 0, _b: int = 0, _c: int = 0, _d: int = 0, _e: int = 0, _f: int = 0) -> int: return 0
func coprocessor_movefrom(_a: int = 0, _b: int = 0, _c: int = 0, _d: int = 0, _e: int = 0) -> int: return 0


# ---------------------------------------------------------------- IO
## ARM9 IO registers 0x04000000-0x040010FF as bytes (seeded from the emulator for lockstep tests). Reads of the
## display status / VCOUNT come from the scanline the main loop is emulating. Geometry-engine command ports are
## logged in gx_cmds (consumed by the 3D renderer). Everything else (VRAM/palette/OAM) goes to the `io` dict.
const IO_BASE := 0x04000000
const IO_SIZE := 0x1100
var IO := PackedByteArray()
var vcount: int = 0
var _spin: int = 0                ## IO reads this frame (busy-wait detector)
var _spin_reported: int = -1
var gx_cmds: Array = []          ## [port_address, value] in submission order


func _io_init() -> void:
	IO.resize(IO_SIZE)


func io_read(addr: int, size: int) -> int:
	if addr >= 0x05000000:
		return hw.bus_read(addr, size)
	if addr == 0x04100010:
		return hw.card_read_word()
	if addr == 0x04100000:   # IPCFIFORECV
		if not ipc_recv.is_empty():
			_ipc_last = ipc_recv.pop_front()
		return _ipc_last
	_spin += 1
	if _spin > 2000000 and _spin_reported != addr:
		_spin_reported = addr
		push_error("DSCore: busy-wait on %08x? " % addr + str(get_stack().slice(1, 6).map(func(d): return "%s:%d" % [d["function"], d["line"]])))
	var o := addr - IO_BASE
	if o >= 0x100 and o < 0x110:
		return timers.read(o, size)
	if o >= 0 and o + size <= IO_SIZE:
		match o:
			0x004:
				var ds := IO.decode_u16(4) & ~7
				ds |= (1 if vcount >= 192 and vcount < 262 else 0) | 2   # in vblank, in hblank (handlers run in hblank)
				if vcount == (IO.decode_u16(4) >> 8 | (IO.decode_u16(4) & 0x80) << 1):
					ds |= 4
				return ds | (vcount << 16) if size == 4 else ds
			0x006:
				return vcount
			0x184:   # IPCFIFOCNT: send FIFO always drained by the ARM7 model; receive state from the queue
				var c := IO.decode_u16(0x184) & 0xC404
				c |= 1 | (0x100 if ipc_recv.is_empty() else 0) | (0x200 if ipc_recv.size() >= 16 else 0)
				return c
			0x180:   # IPCSYNC: the ARM7 side answers the boot handshake by echoing ARM9 output + 1
				var sy := IO.decode_u16(0x180)
				return (sy & 0x4F00) | ((((sy >> 8) & 0xF) + 1) & 0xF)
			0x600, 0x602:   # GXSTAT: geometry engine never busy, FIFO empty (commands execute on write)
				var gs := (IO.decode_u32(0x600) & ~0x0FFF0000 & ~(1 << 27)) | (1 << 25) | (1 << 26)
				return gs if o == 0x600 and size == 4 else ((gs >> 16) if o == 0x602 else gs & 0xFFFF)
		match size:
			1: return IO.decode_u8(o)
			2: return IO.decode_u16(o)
			8: return IO.decode_s64(o)   # 64-bit access (ldrd / two words), e.g. DIV/SQRT operands
			_: return IO.decode_u32(o)
	return int(io.get(addr, 0))


var io_hook: Callable:   ## debug: called as io_hook(addr, size, value) for every IO write when set
	set(f):
		io_hook = f
		_io_hooked = f.is_valid()
var _io_hooked: bool = false


func io_write(addr: int, size: int, v: int) -> void:
	var o := addr - IO_BASE
	if size == 4 and o >= 0x400 and o < 0x600 and not _io_hooked:
		# part 32 (exact speed-up): a geometry engine command / parameter word (~1,300 per battle frame) - the same
		# effect as the general path below (logged for the 3D renderer + stored), without its other checks
		v &= 0xFFFFFFFF
		gx_cmds.append([addr, v])
		IO.encode_u32(o, v)
		return
	if _io_hooked:
		io_hook.call(addr, size, v)
	if addr >= 0x05000000:
		hw.bus_write(addr, size, v)
		return
	if o < 0 or o + size > IO_SIZE:
		io[addr] = v
		return
	if o >= 0x400 and o < 0x600:
		gx_cmds.append([addr, v & 0xFFFFFFFF])
		if size == 8:
			gx_cmds.append([addr + 4, (v >> 32) & 0xFFFFFFFF])
	if o == 0x184 and size >= 2:   # IPCFIFOCNT: bit 14 = error acknowledge, bit 3 = send-FIFO clear (write-only)
		IO.encode_u16(0x184, v & 0x8404)
		return
	if o == 0x188:    # IPCFIFOSEND
		arm7.fifo_in(v & 0xFFFFFFFF)
		return
	if o == 0x214:    # IF: write 1 to acknowledge
		IO.encode_u32(0x214, IO.decode_u32(0x214) & ~(v & 0xFFFFFFFF))
		return
	var dma_was_on := false
	if o >= 0xB0 and o < 0xE0:
		dma_was_on = (IO.decode_u32(0xB0 + 12 * ((o - 0xB0) / 12) + 8) & 0x80000000) != 0
	match size:
		1: IO.encode_u8(o, v & 0xFF)
		2: IO.encode_u16(o, v & 0xFFFF)
		8: IO.encode_s64(o, v)   # 64-bit store (strd / stm of two words), e.g. DIV/SQRT operands
		_: IO.encode_u32(o, v & 0xFFFFFFFF)
	if o >= 0x100 and o < 0x110:
		timers.write(o, size, v)
	elif o >= 0x280 and o < 0x2A0:
		_do_div()
	elif o >= 0x2B0 and o < 0x2C0:
		_do_sqrt()
	elif o >= 0xB0 and o < 0xE0:
		# DMAxCNT is the last word of each 12-byte channel block; a write touching its top byte that turns the
		# enable bit on starts it (rewriting an enabled channel, e.g. MI_StopDma clearing the timing bits
		# before the enable bit, does not restart it)
		var ch := (o - 0xB0) / 12
		if o + size > 0xB0 + 12 * ch + 11 and not dma_was_on:
			hw.dma_control_written(ch)
	elif o >= 0x240 and o < 0x24A:
		for k in size:
			var i := DSHardware.vramcnt_index(addr + k)
			if i >= 0:
				hw.set_vramcnt(i, IO[o + k])
	elif o >= 0x1A4 and o < 0x1A8 and o + size > 0x1A7 and (v >> (8 * (0x1A7 - o))) & 0x80:
		hw.card_start()


func _sx32(v: int) -> int:
	return ((v & 0xFFFFFFFF) + 0x80000000 & 0xFFFFFFFF) - 0x80000000


## math coprocessor: DIVCNT 0x280, DIV_NUMER 0x290, DIV_DENOM 0x298, DIV_RESULT 0x2A0, DIVREM_RESULT 0x2A8
func _do_div() -> void:
	var mode := IO.decode_u16(0x280) & 3
	var n: int
	var d: int
	match mode:
		0:
			n = _sx32(IO.decode_u32(0x290))
			d = _sx32(IO.decode_u32(0x298))
		1:
			n = IO.decode_s64(0x290)
			d = _sx32(IO.decode_u32(0x298))
		_:
			n = IO.decode_s64(0x290)
			d = IO.decode_s64(0x298)
	var q: int
	var r: int
	if d == 0:
		q = -1 if n >= 0 else 1
		r = n
		IO.encode_u16(0x280, IO.decode_u16(0x280) | 0x4000)
	else:
		q = _div(n, d)
		r = n - q * d
		IO.encode_u16(0x280, IO.decode_u16(0x280) & ~0x4000)
	if mode == 0:
		q = _sx32(q)   # 32/32 results are sign-extended to 64 bits
		r = _sx32(r)
	IO.encode_s64(0x2A0, q)
	IO.encode_s64(0x2A8, r)


## SQRTCNT 0x2B0, SQRT_RESULT 0x2B4, SQRT_PARAM 0x2B8
func _do_sqrt() -> void:
	var p: int = IO.decode_u32(0x2B8) if (IO.decode_u16(0x2B0) & 1) == 0 else IO.decode_s64(0x2B8)
	var neg := p < 0
	if neg:   # 64-bit unsigned: sqrt(2^64 + p)
		var hi := sqrt(float(p) + 18446744073709551616.0)
		var rr := int(hi)
		IO.encode_u32(0x2B4, rr)
		return
	var res := int(floor(sqrt(float(p))))
	while res * res > p:
		res -= 1
	while (res + 1) * (res + 1) <= p:
		res += 1
	IO.encode_u32(0x2B4, res)
